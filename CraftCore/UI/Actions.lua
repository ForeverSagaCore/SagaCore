local _, NS = ...

-- Actions sur une recette, les memes sur toutes les pages : Fabriquer, et
-- Ajouter a un projet ou aux fabrications rapides. Un seul code, donc un seul
-- comportement et une seule correction quand il faut corriger.
--
-- Rien ici n'utilise de menu deroulant : ouvert par un add-on, il peut
-- amener le jeu a bloquer l'add-on. Le choix se fait par une rangee de
-- boutons du jeu.

NS.actions = {}
local actions = NS.actions

-- Etat de fabrication pour le personnage connecte : nil si la recette n'est
-- pas la sienne (ou si c'est un enchantement), sinon pret, et ce qui manque
-- dans ses sacs.
function actions.EtatPourFabriquer(recette)
    if not recette or NS.base.CleAffichee() ~= NS.ClePersonnage() then return nil end
    if not NS.recettes.EstApprise(recette.id) then return nil end
    -- Un enchantement ne fabrique pas d'objet : il se pose sur un objet que
    -- seule la fenetre du metier du jeu peut faire choisir. Lance d'ici, le
    -- jeu bloque l'add-on. Pas de bouton.
    if not recette.objetProduit then return nil end
    local manques = {}
    for _, comp in ipairs(recette.composants or {}) do
        local dispo = NS.inventaire.DisponibleDansLesSacs(comp.objet) or 0
        if dispo < comp.quantite then
            table.insert(manques, { objet = comp.objet, manque = comp.quantite - dispo })
        end
    end
    return #manques == 0, manques
end

-- Combien de fois la recette peut etre faite avec ce qu'il y a dans les sacs.
function actions.NombrePossible(recette)
    local possible
    for _, comp in ipairs(recette and recette.composants or {}) do
        local dispo = NS.inventaire.DisponibleDansLesSacs(comp.objet) or 0
        local fois = math.floor(dispo / math.max(1, comp.quantite or 1))
        if not possible or fois < possible then possible = fois end
    end
    return math.max(1, possible or 1)
end

-- Lance la fabrication. Toujours depuis un clic : le jeu l'exige.
-- `nombre` = "tout" : autant que les sacs le permettent, compte au clic.
function actions.Fabriquer(recette, nombre)
    local L = NS.L
    if nombre == "tout" then nombre = actions.NombrePossible(recette) end
    -- Metier deja ouvert : ce qu'il faut a proximite (forge, enclume, feu
    -- de camp...) est dit au moment de lancer, s'il manque.
    if NS.recettes.PretALancer and NS.recettes.PretALancer(recette) then
        local f = NS.Lecture("C_TradeSkillUI.GetRecipeRequirements")
        local ok, besoins = false, nil
        if f then ok, besoins = pcall(f, tonumber(recette.id) or recette.id) end
        if ok and type(besoins) == "table" then
            local manquent = {}
            for _, b in ipairs(besoins) do
                if type(b) == "table" and b.name and b.met == false then table.insert(manquent, b.name) end
            end
            if #manquent > 0 then
                local texte = string.format(L.CRAFT_NEEDS, table.concat(manquent, ", "))
                NS.Dire(texte)
                if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, texte, 1, 0.82, 0) end
                return
            end
        end
    end
    -- Serie en cours, pour la barre de fabrication ("3 / 12").
    actions.serie = { total = tonumber(nombre) or 1, faits = 0 }
    local resultat = NS.recettes.Fabriquer(recette, nombre or 1)
    if resultat == "ouverture" then
        NS.Dire(L.CRAFT_OPENED)
        -- Le bouton devient "Lancer" : on redessine des que le metier est la.
        local plusTard = NS.Lecture("C_Timer.After")
        if plusTard and NS.ecran and NS.ecran.Actualiser then
            NS.Appeler(plusTard, 0.3, function() pcall(NS.ecran.Actualiser) end)
            NS.Appeler(plusTard, 1, function() pcall(NS.ecran.Actualiser) end)
        end
    elseif resultat == "impossible" then
        NS.Dire(L.CRAFT_IMPOSSIBLE)
    end
end

-- Pose sur un bouton du jeu tout ce qu'il faut pour fabriquer `recette` :
-- grise s'il manque quelque chose dans les sacs, et au survol, chaque
-- composant, ce qu'on en a et ou est le reste.
function actions.PreparerBoutonFabriquer(bouton, recette, nombre)
    local L = NS.L
    local pret, manques = actions.EtatPourFabriquer(recette)
    if pret == nil then
        bouton:Hide()
        return false
    end
    bouton:SetEnabled(pret)
    -- Deux temps, deux libelles : "Creer" ouvre le metier, "Lancer" fabrique.
    local lancer = NS.recettes.PretALancer and NS.recettes.PretALancer(recette)
    if lancer then bouton:SetText(L.CRAFT_BUTTON_GO) end
    -- Un bouton grise ne recoit pas le survol par defaut : sans cela,
    -- l'infobulle qui dit ce qui manque et ou c'est ne s'affichait jamais.
    if bouton.SetMotionScriptsWhileDisabled then pcall(bouton.SetMotionScriptsWhileDisabled, bouton, true) end
    bouton:SetScript("OnClick", function() actions.Fabriquer(recette, nombre or 1) end)
    bouton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if pret then
            GameTooltip:SetText(lancer and L.CRAFT_TIP_GO or L.CRAFT_TIP, 1, 1, 1, 1, true)
        else
            GameTooltip:SetText(L.GEAR_CRAFT_MISSING, 1, 0.82, 0)
            NS.inventaire.ComposantsDansLInfobulle(GameTooltip, recette)
        end
        GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bouton:Show()
    return true, pret, manques
end

-- Ou ajouter une recette : les projets en cours, les fabrications rapides,
-- un nouveau projet.
function actions.Destinations(idRecette)
    local L = NS.L
    local choix = {}
    for _, projet in ipairs(NS.projets.Tous(false) or {}) do
        local nom = NS.projets.NomDe(projet)
        local dedans = false
        for _, entree in ipairs(NS.projets.Contenu(projet.id) or {}) do
            if idRecette and tostring(entree.recette) == tostring(idRecette) then dedans = true break end
        end
        table.insert(choix, { cle = projet.id, libelle = dedans and (nom .. " (+1)") or nom,
            nom = nom, cible = projet.id })
    end
    table.insert(choix, { cle = "rapides", libelle = L.NAV_QUICK, nom = L.NAV_QUICK, cible = "rapides" })
    table.insert(choix, { cle = "nouveau", libelle = L.PROJECTS_NEW_WITH, nouveau = true })
    return choix
end

-- Ajoute `quantite` de la recette a la destination choisie.
function actions.AjouterA(choix, idRecette, nomObjet, quantite)
    local L = NS.L
    local cible, nomCible = choix.cible, choix.nom
    if choix.nouveau then
        local projet = NS.projets.Creer(nil)
        if not projet then return false end
        cible, nomCible = projet.id, NS.projets.NomDe(projet)
    end
    if NS.projets.Ajouter(cible, idRecette, quantite or 1) then
        NS.projets.PoserDestination(cible)
        NS.Dire(string.format(L.ADDED_TO, nomObjet or tostring(idRecette), nomCible or "?"))
        return true
    end
    return false
end

-- Rangee de boutons de destination, de droite a gauche depuis `ancre`.
-- `pool` garde les boutons d'un rendu a l'autre. `apres` est appele une fois
-- l'ajout fait (pour refermer la rangee et redessiner).
function actions.RangeeDeDestinations(parent, pool, ancre, idRecette, nomObjet, apres)
    for _, b in ipairs(pool) do b:Hide() end
    local choix = actions.Destinations(idRecette)
    for rang = #choix, 1, -1 do
        local c = choix[rang]
        local b = pool[rang]
        if not b then
            b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            b:SetHeight(20)
            pool[rang] = b
        end
        b:SetText(c.libelle)
        b:SetWidth((b.GetTextWidth and b:GetTextWidth() or 80) + 20)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", ancre, "BOTTOMLEFT", -6, 0)
        b:SetScript("OnClick", function()
            actions.AjouterA(c, idRecette, nomObjet, 1)
            if apres then apres() end
        end)
        b:Show()
        ancre = b
    end
end

-- ---------------------------------------------------------------------------
-- Une fabrication reussie fait baisser la quantite visee : dans les
-- fabrications rapides d'abord, sinon dans le premier projet qui la contient.
-- A zero, la ligne disparait. (L'identifiant d'une recette est celui du sort
-- de fabrication que le jeu annonce.)
-- ---------------------------------------------------------------------------

local function FabricationFaite(idSort)
    local cle = tostring(idSort)
    if not (CraftCoreDB and CraftCoreDB.recettes and CraftCoreDB.recettes[cle]) then return end
    local cibles = { "rapides" }
    for _, projet in ipairs(NS.projets.Tous(false) or {}) do table.insert(cibles, projet.id) end
    for _, cible in ipairs(cibles) do
        for _, entree in ipairs(NS.projets.Contenu(cible) or {}) do
            if tostring(entree.recette) == cle then
                -- Projet destine a un autre personnage : ce qui sort de la
                -- fabrication est a lui envoyer.
                local projet = cible ~= "rapides" and NS.projets.Par(cible)
                if projet and not projet.commande and projet.pour and projet.pour ~= NS.ClePersonnage() and NS.commandes
                    and NS.commandes.AEnvoyerPour then
                    local r = CraftCoreDB.recettes[cle]
                    pcall(NS.commandes.AEnvoyerPour, projet.pour, cle, math.max(1, tonumber(r and r.quantiteMin) or 1))
                end
                NS.projets.ChangerQuantite(cible, entree.recette, -1)
                if cible ~= "rapides" and NS.commandes then pcall(NS.commandes.ProjetVide, NS.projets.Par(cible)) end
                if NS.Trace then NS.Trace("fabrique : " .. cle .. " dans " .. tostring(cible)) end
                if NS.ecran and NS.ecran.Montrer and NS.ecran.page then pcall(NS.ecran.Montrer, NS.ecran.page) end
                if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                return
            end
        end
    end
end

local ecouteFabrication = CreateFrame("Frame")
pcall(ecouteFabrication.RegisterUnitEvent or ecouteFabrication.RegisterEvent, ecouteFabrication,
    "UNIT_SPELLCAST_SUCCEEDED", "player")
ecouteFabrication:SetScript("OnEvent", function(_, _, unite, _, idSort)
    if unite and unite ~= "player" then return end
    local ok, souci = pcall(FabricationFaite, idSort)
    if not ok and NS.base and NS.base.NoterIncident then NS.base.NoterIncident("fabrication faite", souci) end
end)
