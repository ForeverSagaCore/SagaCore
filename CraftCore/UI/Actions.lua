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
function actions.Fabriquer(recette, nombre, garde)
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
    -- `garde` dit si la fabrication sert encore (etape finie, rang atteint) :
    -- la serie s'arrete des qu'elle ne sert plus.
    actions.serie = { total = tonumber(nombre) or 1, faits = 0, garde = garde }
    -- Le metier va s'ouvrir en cache : sans le bruit d'ouverture.
    if not (NS.recettes.PretALancer and NS.recettes.PretALancer(recette)) and actions.Silence then actions.Silence() end
    local resultat = NS.recettes.Fabriquer(recette, nombre or 1)
    if resultat == "ouverture" then
        -- Ouvert par notre bouton : la fenetre du metier reste invisible.
        actions.fantomeDemande = NS.Appeler(GetTime) or 0
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
function actions.PreparerBoutonFabriquer(bouton, recette, nombre, garde)
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
    bouton:SetScript("OnClick", function() actions.Fabriquer(recette, nombre or 1, garde) end)
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
    actions.derniereFabrication = NS.Appeler(GetTime) or 0
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


-- ---------------------------------------------------------------------------
-- Metier ouvert en cache. Le jeu ne fabrique que fenetre du metier ouverte :
-- quand c'est notre bouton qui l'ouvre, elle est rendue invisible (et ne
-- prend plus les clics), seule notre interface se voit. Elle se referme
-- d'elle-meme quand il n'y a plus rien a fabriquer dans ce metier, ou des que
-- le personnage se deplace. Ouverte par le joueur, elle reste normale.
-- ---------------------------------------------------------------------------

local fantome = {}
actions.fantome = fantome

local function Fenetres() return { _G.ProfessionsFrame, _G.TradeSkillFrame } end

local function Rendre(f)
    if f and f.avantFantome then
        pcall(f.SetScale, f, f.avantFantome.echelle or 1)
        pcall(f.SetAlpha, f, f.avantFantome.alpha or 1)
        f.avantFantome = nil
    end
end

local function Cacher()
    if NS.Appeler(InCombatLockdown) then return end
    for _, f in ipairs(Fenetres()) do
        if f and f.IsShown and f:IsShown() and not f.avantFantome then
            f.avantFantome = { alpha = f:GetAlpha(), echelle = f:GetScale() }
            -- Transparente et minuscule : plus rien a voir ni a cliquer.
            pcall(f.SetAlpha, f, 0)
            pcall(f.SetScale, f, 0.01)
            if not f.fantomeAccroche then
                f.fantomeAccroche = true
                f:HookScript("OnHide", function(self)
                    Rendre(self)
                    fantome.actif = nil
                end)
            end
            fantome.actif = true
        end
    end
end

-- Coupe les bruitages un court instant (ouverture et fermeture du metier en
-- cache), puis les remet comme ils etaient.
local sonCoupe
function actions.Silence()
    local lire = NS.Lecture("C_CVar.GetCVar", "GetCVar")
    local poser = NS.Lecture("C_CVar.SetCVar", "SetCVar")
    if not (lire and poser) then return end
    if not sonCoupe then
        local avant = NS.Appeler(lire, "Sound_EnableSFX")
        if avant ~= "1" then return end
        sonCoupe = avant
        NS.Appeler(poser, "Sound_EnableSFX", "0")
    end
    local plusTard = NS.Lecture("C_Timer.After")
    local function Remettre()
        if sonCoupe then NS.Appeler(poser, "Sound_EnableSFX", sonCoupe) sonCoupe = nil end
    end
    if plusTard then NS.Appeler(plusTard, 0.6, Remettre) else Remettre() end
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        local poser = NS.Lecture("C_CVar.SetCVar", "SetCVar")
        if sonCoupe and poser then NS.Appeler(poser, "Sound_EnableSFX", sonCoupe) sonCoupe = nil end
    end)
end

-- La serie sert-elle encore ? Sinon on arrete de repeter la fabrication.
function actions.VerifierSerie()
    local serie = actions.serie
    if not (serie and serie.garde) then return end
    local ok, utile = pcall(serie.garde)
    if ok and utile == false then
        actions.serie = nil
        local arreter = NS.Lecture("C_TradeSkillUI.StopRecipeRepeat")
        if arreter then NS.Appeler(arreter) end
    end
end

local function Fermer()
    if not fantome.actif then return end
    fantome.actif = nil
    actions.Silence()
    local j = NS.jeu
    if j and j.fermerMetier then pcall(j.fermerMetier) end
    for _, f in ipairs(Fenetres()) do
        Rendre(f)
        if f and f.IsShown and f:IsShown() and _G.HideUIPanel and not NS.Appeler(InCombatLockdown) then pcall(_G.HideUIPanel, f) end
    end
end
fantome.Fermer = Fermer

-- Encore une fabrication prete dans ce metier ? Alors on garde la fenetre.
local function EncoreAFaire()
    return NS.suivi and NS.suivi.FabricationPreteIci and NS.suivi.FabricationPreteIci() or false
end

do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "PLAYER_REGEN_DISABLED",
        "UNIT_SPELLCAST_SUCCEEDED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local fermerDans
    f:SetScript("OnEvent", function(_, evenement, unite)
        if evenement == "UNIT_SPELLCAST_SUCCEEDED" or evenement == "BAG_UPDATE_DELAYED" or evenement == "SKILL_LINES_CHANGED" then
            if evenement ~= "UNIT_SPELLCAST_SUCCEEDED" or unite == "player" then
                local plusTard = NS.Lecture("C_Timer.After")
                if plusTard then NS.Appeler(plusTard, 0.1, actions.VerifierSerie) else actions.VerifierSerie() end
            end
            return
        end
        if evenement == "TRADE_SKILL_SHOW" or evenement == "TRADE_SKILL_LIST_UPDATE" then
            local quand = actions.fantomeDemande
            if quand and (NS.Appeler(GetTime) or 0) - quand < 5 then
                actions.fantomeDemande = nil
                Cacher()
                -- Le cadre du jeu s'affiche parfois juste apres l'evenement.
                local plusTard = NS.Lecture("C_Timer.After")
                if plusTard then NS.Appeler(plusTard, 0, Cacher) NS.Appeler(plusTard, 0.2, Cacher) end
            end
        elseif evenement == "PLAYER_REGEN_DISABLED" then
            Fermer()
        elseif unite == "player" and fantome.actif then
            -- Fin d'une incantation : la serie est-elle finie ? On regarde un
            -- peu plus tard (la suivante s'enchaine aussitot).
            fermerDans = 1.5
        end
    end)
    local attente = 0
    f:SetScript("OnUpdate", function(_, ecoule)
        if not fantome.actif then fermerDans = nil return end
        -- Le personnage bouge : il a fini avec le metier.
        local ok, vitesse = pcall(GetUnitSpeed, "player")
        if ok and not (_G.issecretvalue and _G.issecretvalue(vitesse)) and (tonumber(vitesse) or 0) > 0 then
            Fermer()
            return
        end
        if fermerDans then
            fermerDans = fermerDans - (ecoule or 0)
            if fermerDans <= 0 then
                fermerDans = nil
                local okC, sort = pcall(UnitCastingInfo, "player")
                local enCours = okC and sort ~= nil
                local serie = actions.serie
                local serieFinie = not serie or (serie.faits or 0) >= (serie.total or 1)
                if not enCours and serieFinie and not EncoreAFaire() then Fermer() end
            end
        end
    end)
end
