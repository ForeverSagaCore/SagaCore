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
    -- Un enchantement ne fabrique pas d'objet : il se pose sur un objet,
    -- choisi au moment de le lancer (voir Enchanter). Sans objet connu hors
    -- enchantement, rien a lancer.
    if not recette.objetProduit and NS.recettes.MetierDe(recette) ~= 333 then return nil end
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
    actions.serie = { total = tonumber(nombre) or 1, faits = 0, reussis = 0, garde = garde, recette = recette and recette.id }
    -- Le metier va s'ouvrir en cache : sans le bruit d'ouverture.
    if not (NS.recettes.PretALancer and NS.recettes.PretALancer(recette)) and actions.Silence then actions.Silence() end
    local resultat = NS.recettes.Fabriquer(recette, nombre or 1)
    -- La barre de progression ne remplace le bouton que si la fabrication
    -- est vraiment lancee (pas quand le clic ne fait qu'ouvrir le metier).
    if actions.serie then actions.serie.lancee = resultat ~= "ouverture" and resultat ~= "impossible" end
    if resultat == "ouverture" then
        -- Ouvert par notre bouton : la fenetre du metier reste invisible.
        actions.fantomeDemande = NS.Appeler(GetTime) or 0
        NS.Dire(L.CRAFT_OPENED)
        -- Le bouton devient "Lancer" : on redessine des que le metier est la.
        local plusTard = NS.Lecture("C_Timer.After")
        -- Fenetre et suivi : le bouton passe a « Lancer » aussitot.
        local function Redessiner()
            if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
        end
        if plusTard then
            NS.Appeler(plusTard, 0.3, Redessiner)
            NS.Appeler(plusTard, 1, Redessiner)
        end
    elseif resultat == "enchantement" then
        actions.serie = nil
        actions.Enchanter(recette)
    elseif resultat == "impossible" then
        NS.Dire(L.CRAFT_IMPOSSIBLE)
    end
end

-- La barre d'une serie de fabrication, la meme partout : celle du jeu (barre
-- d'incantation des metiers, son remplissage et son cadre), en petit.
-- barre:Poser(faits, total).
local function Atlas(nom)
    local ct = _G.C_Texture
    if not (ct and ct.GetAtlasInfo) then return nil end
    local ok, info = pcall(ct.GetAtlasInfo, nom)
    return ok and info and nom or nil
end
function actions.BarreDeSerie(parent)
    local barre = CreateFrame("StatusBar", nil, parent)
    barre:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local remplissage = Atlas("ui-castingbar-filling-tradeskill") or Atlas("ui-castingbar-filling-standard")
    local tex = barre:GetStatusBarTexture()
    if remplissage and tex and tex.SetAtlas then
        pcall(tex.SetAtlas, tex, remplissage, false)
    else
        barre:SetStatusBarColor(1, 0.7, 0)
    end
    barre.fond = barre:CreateTexture(nil, "BACKGROUND")
    barre.fond:SetAllPoints()
    local fond = Atlas("ui-castingbar-background")
    if fond then barre.fond:SetAtlas(fond, false) else barre.fond:SetColorTexture(0, 0, 0, 0.5) end
    barre.cadre = barre:CreateTexture(nil, "OVERLAY")
    local cadre = Atlas("ui-castingbar-frame")
    if cadre then
        barre.cadre:SetAtlas(cadre, false)
        barre.cadre:SetPoint("TOPLEFT", barre, "TOPLEFT", -2, 2)
        barre.cadre:SetPoint("BOTTOMRIGHT", barre, "BOTTOMRIGHT", 2, -2)
    else
        barre.cadre:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
        barre.cadre:SetPoint("TOPLEFT", barre, "TOPLEFT", -6, 6)
        barre.cadre:SetPoint("BOTTOMRIGHT", barre, "BOTTOMRIGHT", 6, -6)
    end
    barre.texte = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    barre.texte:SetPoint("CENTER", barre, "CENTER", 0, 0)
    if barre.texte.SetShadowOffset then barre.texte:SetShadowOffset(1, -1) end
    function barre:Poser(faits, total)
        total = math.max(1, tonumber(total) or 1)
        faits = math.max(0, math.min(total, tonumber(faits) or 0))
        self:SetMinMaxValues(0, total)
        self:SetValue(faits)
        self.texte:SetText(faits .. " / " .. total)
        self:Show()
    end
    return barre
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

-- Plus jamais : changer l'echelle ou la transparence d'une fenetre du jeu
-- (et la fermer par HideUIPanel) la « salissait », avec elle la gestion des
-- fenetres du jeu, jusqu'au menu (Quitter bloque). La fenetre du metier
-- s'ouvre donc normalement ; elle se referme par la fonction du jeu.
local CACHER_LA_FENETRE = false
local function Cacher()
    if not CACHER_LA_FENETRE then return end
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
        -- Note sur le disque : si le jeu se ferme pendant ce court instant,
        -- les bruitages sont remis a la connexion suivante.
        if CraftCoreDB then CraftCoreDB.sonCoupe = avant end
        NS.Appeler(poser, "Sound_EnableSFX", "0")
    end
    local plusTard = NS.Lecture("C_Timer.After")
    local function Remettre()
        if sonCoupe then NS.Appeler(poser, "Sound_EnableSFX", sonCoupe) sonCoupe = nil end
        if CraftCoreDB then CraftCoreDB.sonCoupe = nil end
    end
    if plusTard then NS.Appeler(plusTard, 0.6, Remettre) else Remettre() end
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "PLAYER_LOGOUT")
    pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, evenement)
        local poser = NS.Lecture("C_CVar.SetCVar", "SetCVar")
        if not poser then return end
        if evenement == "PLAYER_LOGIN" then
            -- Bruitages restes coupes par une fermeture au mauvais moment.
            if CraftCoreDB and CraftCoreDB.sonCoupe then
                NS.Appeler(poser, "Sound_EnableSFX", CraftCoreDB.sonCoupe)
                CraftCoreDB.sonCoupe = nil
            end
            return
        end
        if sonCoupe then NS.Appeler(poser, "Sound_EnableSFX", sonCoupe) sonCoupe = nil end
        if CraftCoreDB then CraftCoreDB.sonCoupe = nil end
    end)
end

-- La serie sert-elle encore ? Sinon on arrete de repeter la fabrication.
function actions.VerifierSerie()
    local serie = actions.serie
    if not serie then return end
    -- Borne : la quantite demandee est faite, on s'arrete la.
    local fini = (serie.reussis or 0) >= (serie.total or 1)
    if not fini and serie.garde then
        local ok, utile = pcall(serie.garde)
        fini = ok and utile == false
    end
    if fini then
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

    end
end
fantome.Fermer = Fermer

-- Rendre visible la fenetre cachee (repli de l'enchantement) : elle reste
-- ouverte, comme si le joueur l'avait ouverte lui-meme.
function fantome.Montrer()
    fantome.actif = nil
    actions.fantomeDemande = nil
    for _, f in ipairs(Fenetres()) do Rendre(f) end
end

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
    f:SetScript("OnEvent", function(_, evenement, unite, ...)
        if evenement == "UNIT_SPELLCAST_SUCCEEDED" or evenement == "BAG_UPDATE_DELAYED" or evenement == "SKILL_LINES_CHANGED" then
            if evenement == "UNIT_SPELLCAST_SUCCEEDED" and unite == "player" and actions.serie then
                local _, sort = ...
                local serie = actions.serie
                local secret = _G.issecretvalue and _G.issecretvalue(sort)
                if secret or not serie.recette or tostring(sort) == tostring(serie.recette) then
                    serie.reussis = (serie.reussis or 0) + 1
                    actions.VerifierSerie()
                    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                    -- La barre de la fenetre avance aussi.
                    if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
                end
            end
            if evenement ~= "UNIT_SPELLCAST_SUCCEEDED" or unite == "player" then
                -- Le suivi suit chaque objet fabrique, sans attendre.
                if evenement == "BAG_UPDATE_DELAYED" and NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
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
                local serieFinie = not serie or (serie.reussis or 0) >= (serie.total or 1)
                if not enCours and serieFinie and not EncoreAFaire() then Fermer() end
            end
        end
    end)
end


-- ---------------------------------------------------------------------------
-- Enchanter. D'abord directement : l'objet se choisit dans une petite
-- fenetre de CraftCore, puis l'enchantement s'y pose (commande du jeu
-- CraftEnchant). Si le client ne l'a pas, ou si le jeu la refuse a
-- l'add-on : la fenetre du metier se montre sur la recette, avec les sacs et
-- la fiche du personnage (ou la fenetre d'echange deja ouverte) ; le joueur
-- clique Enchanter puis l'objet, comme dans le jeu.
-- ---------------------------------------------------------------------------

local enchant = {}
actions.enchant = enchant

local function ReglagesEnchant()
    local g = NS.base and NS.base.ReglagesGeneraux and NS.base.ReglagesGeneraux()
    return type(g) == "table" and g or {}
end

-- Les objets qui peuvent recevoir cet enchantement (sacs et equipement).
local function ObjetsEnchantables(recette)
    local lire = NS.Lecture("C_TradeSkillUI.GetEnchantItems")
    local placer = NS.Lecture("C_Item.GetItemLocation")
    if not (lire and placer) then return nil end
    local ok, guids = pcall(lire, tonumber(recette.id) or recette.id)
    if not ok or type(guids) ~= "table" then return nil end
    local nomDe = NS.Lecture("C_Item.GetItemName")
    local iconeDe = NS.Lecture("C_Item.GetItemIcon")
    local liste = {}
    for _, guid in ipairs(guids) do
        local okL, lieu = pcall(placer, guid)
        if okL and lieu then
            table.insert(liste, { lieu = lieu, nom = NS.Appeler(nomDe, lieu) or "?", icone = NS.Appeler(iconeDe, lieu) })
        end
    end
    return liste
end

-- Solution de repli : la fenetre du metier du jeu, visible, sur la recette.
function enchant.Repli(recette)
    local L = NS.L
    if actions.fantome and actions.fantome.Montrer then actions.fantome.Montrer() end
    local ouvrir = NS.Lecture("C_TradeSkillUI.OpenRecipe")
    if ouvrir then NS.Appeler(ouvrir, tonumber(recette.id) or recette.id) end
    if not NS.Appeler(InCombatLockdown) then
        if _G.OpenAllBags then pcall(_G.OpenAllBags) end
        local echange = _G.TradeFrame and _G.TradeFrame:IsShown()
        local fiche = _G.CharacterFrame and _G.CharacterFrame:IsShown()
        if not echange and not fiche and _G.ToggleCharacter then pcall(_G.ToggleCharacter, "PaperDollFrame") end
    end
    NS.Dire(L.ENCHANT_FALLBACK)
end

-- Le jeu refuse l'action a l'add-on : on le retient et on passe au repli.
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, _, addon, fonction)
        if addon ~= "CraftCore" or not enchant.essai then return end
        if not string.find(tostring(fonction), "Enchant") then return end
        ReglagesEnchant().enchantDirectRefuse = true
        if _G.StaticPopup_Hide then pcall(_G.StaticPopup_Hide, "ADDON_ACTION_FORBIDDEN") end
        local r = enchant.essai
        enchant.essai = nil
        enchant.Repli(r)
    end)
end

local function Poser(recette, objet)
    local poser = NS.Lecture("C_TradeSkillUI.CraftEnchant")
    if not poser then enchant.Repli(recette) return end
    enchant.essai = recette
    local ok = pcall(poser, tonumber(recette.id) or recette.id, 1, nil, objet.lieu)
    local plusTard = NS.Lecture("C_Timer.After")
    if plusTard then NS.Appeler(plusTard, 1, function() enchant.essai = nil end) else enchant.essai = nil end
    if not ok and enchant.essai then
        enchant.essai = nil
        enchant.Repli(recette)
    end
end

-- La petite fenetre de choix : un bouton par objet, et Annuler. Jouable a la
-- manette (des boutons, dans la fenetre de CraftCore si elle est ouverte).
local function Choisir(recette, objets)
    local L = NS.L
    local parent = UIParent
    local c = enchant.cadre
    if not c then
        c = CreateFrame("Frame", "CraftCoreChoixEnchant", UIParent, "BackdropTemplate")
        c:SetFrameStrata("DIALOG")
        c:SetSize(300, 80)
        if c.SetBackdrop then
            c:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        end
        c.titre = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        c.titre:SetPoint("TOP", 0, -16)
        c.boutons = {}
        c.annuler = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        c.annuler:SetSize(120, 22)
        c.annuler:SetScript("OnClick", function() c:Hide() end)
        table.insert(_G.UISpecialFrames or {}, "CraftCoreChoixEnchant")
        -- Manette : croix haut / bas pour choisir, A pour valider, B pour annuler.
        c.rang = 1
        local function Eclairer()
            local liste = {}
            for _, b in ipairs(c.boutons) do if b:IsShown() then table.insert(liste, b) end end
            table.insert(liste, c.annuler)
            c.rang = math.max(1, math.min(#liste, c.rang))
            for i, b in ipairs(liste) do
                if i == c.rang then b:LockHighlight() else b:UnlockHighlight() end
            end
            return liste
        end
        c.Eclairer = Eclairer
        if c.EnableGamePadButton then
            c:EnableGamePadButton(true)
            c:SetScript("OnGamePadButtonDown", function(self, touche)
                local liste = Eclairer()
                if touche == "PADDUP" then self.rang = self.rang - 1 Eclairer()
                elseif touche == "PADDDOWN" then self.rang = self.rang + 1 Eclairer()
                elseif touche == "PAD1" then local b = liste[self.rang] if b then b:Click() end
                elseif touche == "PAD2" then self:Hide() end
            end)
        end
        enchant.cadre = c
    end
    c:SetParent(parent)
    c:SetFrameStrata("DIALOG")
    c:ClearAllPoints()
    c:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    c.titre:SetText(string.format(L.ENCHANT_PICK, recette.nom or "?"))
    for _, b in ipairs(c.boutons) do b:Hide() end
    local y = -44
    for i, objet in ipairs(objets) do
        local b = c.boutons[i]
        if not b then
            b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
            b:SetSize(260, 22)
            c.boutons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOP", c, "TOP", 0, y)
        b:SetText((objet.icone and ("|T" .. objet.icone .. ":16|t ") or "") .. objet.nom)
        b:SetScript("OnClick", function() c:Hide() Poser(recette, objet) end)
        b:Show()
        y = y - 26
    end
    c.annuler:ClearAllPoints()
    c.annuler:SetPoint("TOP", c, "TOP", 0, y - 6)
    c.annuler:SetText(_G.CANCEL or "Annuler")
    c:SetHeight(-y + 44)
    c.rang = 1
    c:Show()
    c.Eclairer()
end

function actions.Enchanter(recette)
    local L = NS.L
    local direct = NS.Lecture("C_TradeSkillUI.CraftEnchant") and not ReglagesEnchant().enchantDirectRefuse
    local objets = direct and ObjetsEnchantables(recette) or nil
    if not objets then enchant.Repli(recette) return end
    if #objets == 0 then
        NS.Dire(L.ENCHANT_NONE)
        return
    end
    Choisir(recette, objets)
end
