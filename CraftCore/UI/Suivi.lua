local _, NS = ...

-- ===========================================================================
-- Suivi de recolte
-- ===========================================================================
--
-- Une petite fenetre du jeu, comme le suivi des quetes : a chaque objet
-- ramasse qui sert a un projet ou a la progression d'un metier, elle dit ce
-- qu'il apporte. Elle compte la session de farm, se deplace a la souris et
-- garde sa place, devient presque transparente quand on court, se masque
-- par sa croix et revient au prochain objet utile. Reinitialiser remet la
-- session a zero. Rien n'est jamais dit dans la discussion.
--
-- Deux onglets :
--   Session     tout ce qui a ete ramasse d'utile, et a quoi ca sert ;
--   Objectifs   les rangs vises (page Progression, "Viser un rang") et les
--               projets : chacun avec son pourcentage, et deplie, ses
--               matieres (grisees tant qu'on n'en a aucune).

local infobulles = NS.infobulles

NS.suivi = {}
local suivi = NS.suivi

local LARGEUR_SUIVI = 300
local ALPHA_EN_COURSE = 0.25
local cadreSuivi

local function Session()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { objets = {}, ordre = 0 } end
    local cle = NS.ClePersonnage and NS.ClePersonnage() or "?"
    d.suiviRecolte = d.suiviRecolte or {}
    if not d.suiviRecolte[cle] then d.suiviRecolte[cle] = { objets = {}, ordre = 0, debut = NS.Horodatage() } end
    return d.suiviRecolte[cle]
end

local function Actif()
    local g = NS.base.ReglagesGeneraux()
    if g.suiviRecolte == nil then g.suiviRecolte = true end
    return g.suiviRecolte
end

-- Ce qu'un objet apporte, en quelques lignes, pour le personnage connecte.
local function Utilite(objet)
    local L = NS.L
    local lignes = {}
    -- Projets et fabrications rapides : ce qui manque encore apres ce butin.
    infobulles.Invalider()
    local projets = NS.infobulles.Index()[objet]
    if projets then
        for nom, manque in pairs(projets) do
            if manque > 0 then
                table.insert(lignes, { string.format(L.TRACK_PROJECT_MISSING, nom, manque), 1, 0.82, 0 })
            else
                table.insert(lignes, { string.format(L.TRACK_PROJECT_DONE, nom), 0.31, 0.82, 0.41 })
            end
        end
    end
    -- Progression : les recettes oranges qui l'utilisent, et jusqu'ou le
    -- metier peut monter maintenant.
    local fiche = NS.base.Personnage()
    local catalogue = NS.recettes
    if fiche and type(fiche.metiers) == "table" and catalogue and catalogue.Progression then
        for cleMetier, sien in pairs(fiche.metiers) do
            local ligneMetier = tonumber(cleMetier)
            if ligneMetier and ligneMetier > 0 and type(sien) == "table" and sien.rang then
                local sert
                for _, recette in ipairs((catalogue.Pour(ligneMetier))) do
                    if catalogue.ChanceDePoint(recette, sien.rang) >= 0.5 and catalogue.EstApprise(recette.id) then
                        for _, comp in ipairs(recette.composants or {}) do
                            if comp.objet == objet then sert = recette break end
                        end
                    end
                    if sert then break end
                end
                if sert then
                    local plan = catalogue.Progression(ligneMetier, sien.rang, sien.rangMax, nil)
                    local nom = sien.nom or catalogue.NomDuMetier(ligneMetier) or "?"
                    if plan.atteint > sien.rang then
                        table.insert(lignes, { string.format(L.TRACK_PROGRESS, nom, plan.atteint, plan.atteint - sien.rang),
                            0.31, 0.82, 0.41 })
                    else
                        table.insert(lignes, { string.format(L.TRACK_PROGRESS_USE, nom, sert.nom or "?"), 0.8, 0.8, 0.8 })
                    end
                end
            end
        end
    end
    return lignes
end

-- ---------------------------------------------------------------------------
-- Objectifs : rangs vises et projets
-- ---------------------------------------------------------------------------

local function EstApprise(id)
    return NS.recettes and NS.recettes.EstApprise and NS.recettes.EstApprise(id) or false
end

-- Une matiere d'objectif : requis, ce qui manque encore, ce qu'on possede.
local function Matieres(requis, manques)
    local liste = {}
    for objet, n in pairs(requis) do
        if n > 0 then
            -- Couvert = requis moins ce qui manque encore : le meme calcul que le
            -- pourcentage, donc une matiere complete est toujours en vert.
            local manque = math.max(0, math.min(n, manques[objet] or 0))
            local possede = n - manque
            table.insert(liste, { objet = objet, requis = n, manque = manque, possede = possede })
        end
    end
    -- En cours d'abord, puis pas commencees, puis completes.
    local function Ordre(m)
        if m.manque == 0 then return 3 end
        if m.possede == 0 then return 2 end
        return 1
    end
    table.sort(liste, function(a, b)
        if Ordre(a) ~= Ordre(b) then return Ordre(a) < Ordre(b) end
        return a.manque > b.manque
    end)
    return liste
end

-- Rangs vises du personnage connecte.
local function ObjectifsDeProgression(liste)
    local L = NS.L
    local fiche = NS.base.Personnage()
    local catalogue = NS.recettes
    if not fiche or type(fiche.objectifsProgression) ~= "table" or not catalogue then return end
    -- Metiers qui ont deja leur projet de progression : l'objectif n'est pas
    -- montre en double, le projet suffit (rang actuel, rang vise, recettes).
    local avecProjet = {}
    for _, projet in ipairs(NS.projets and NS.projets.Tous and NS.projets.Tous(false) or {}) do
        if projet.progression and not projet.horsSuivi then avecProjet[tostring(projet.progression)] = true end
    end
    for cle in pairs(fiche.objectifsProgression) do
        local ligne = tonumber(cle)
        local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
        if ligne and type(sien) == "table" and sien.rang and not avecProjet[tostring(cle)] then
            local nom = sien.nom or catalogue.NomDuMetier(ligne) or "?"
            -- Un objectif par rang vise, a la suite (82, puis 90...).
            for _, seg in ipairs(catalogue.PlansVises(fiche, cle, sien.rang, sien.rangMax)) do
            local vise, plan = seg.vise, seg.plan
            local requis = {}
            for _, etape in ipairs(plan.etapes or {}) do
                for _, comp in ipairs(etape.recette.composants or {}) do
                    if not catalogue.EstVenduPartout(comp.objet) then
                        requis[comp.objet] = (requis[comp.objet] or 0) + comp.quantite * etape.fois
                    end
                end
            end
            -- Ce qu'on fabrique soi-meme (silex a aiguiser, fait de pierre) :
            -- seule la part deja en stock compte pour lui ; le reste devient
            -- ses propres composants, a reunir.
            local inter = plan.intermediaires or {}
            if next(inter) then
                local producteurs = {}
                for _, r in pairs(catalogue.Toutes and catalogue.Toutes() or {}) do
                    if type(r) == "table" and r.objetProduit and inter[r.objetProduit] and catalogue.EstApprise(r.id) then
                        producteurs[r.objetProduit] = r
                    end
                end
                for objet, fois in pairs(inter) do
                    local r = producteurs[objet]
                    if r then
                        local fabriques = fois * math.max(1, tonumber(r.quantiteMin) or 1)
                        requis[objet] = math.max(0, (requis[objet] or 0) - fabriques)
                        for _, c in ipairs(r.composants or {}) do
                            if not catalogue.EstVenduPartout(c.objet) then
                                requis[c.objet] = (requis[c.objet] or 0) + c.quantite * fois
                            end
                        end
                    end
                end
            end
            local total, manque = 0, 0
            for objet, n in pairs(requis) do
                total = total + n
                manque = manque + math.min(n, plan.manques[objet] or 0)
            end
            local pct
            if sien.rang >= vise then pct = 1
            elseif total > 0 then pct = (total - manque) / total
            else pct = 0 end
            table.insert(liste, { cle = "prog" .. cle .. ":" .. vise, ligne = ligne, vise = vise, nom = string.format(L.GOAL_PROG, nom, vise), genre = "progression",
                detail = string.format(L.GOAL_PROG_DETAIL, sien.rang, vise), pct = pct, atteint = sien.rang >= vise,
                matieres = Matieres(requis, plan.manques), achats = plan.achats,
                -- Les recettes du plan, dans l'ordre : le bouton Creer les lance.
                lignes = (function()
                    local t = {}
                    for _, etape in ipairs(plan.etapes or {}) do
                        if etape.recette and etape.recette.id then
                            table.insert(t, { recette = etape.recette.id, quantite = etape.fois or 1 })
                        end
                    end
                    return t
                end)() })
            end
        end
    end
end

-- Projets en cours : ce qu'il faut recolter au bout de la chaine.
local function ObjectifsDeProjets(liste)
    local L = NS.L
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return end
    -- Les fabrications rapides d'abord, comme dans Mes fabrications, puis les
    -- projets suivis.
    local blocs = { { id = "rapides", rapides = true } }
    for _, projet in ipairs(NS.projets.Tous(false) or {}) do table.insert(blocs, projet) end
    -- Les commandes (demandees par un autre personnage) : une meme
    -- fabrication demandee par plusieurs personnages n'en fait qu'une, aux
    -- quantites additionnees, avec la liste de ceux pour qui on la fait.
    local moiCle = NS.ClePersonnage and NS.ClePersonnage()
    local function DemandeurDe(projet)
        if projet.rapides then return nil end
        if projet.commande ~= nil then
            local c = NS.commandes and NS.commandes.Par and NS.commandes.Par(projet.commande)
            return (c and c.demandeur) or "?"
        end
        if projet.pour and projet.pour ~= moiCle then return projet.pour end
        return nil
    end
    local rendus, fusions = {}, {}
    for _, projet in ipairs(blocs) do
      if not projet.horsSuivi then
        local lignesP = {}
        for _, entree in ipairs(NS.projets.Contenu(projet.id) or {}) do
            table.insert(lignesP, { recette = tonumber(entree.recette) or entree.recette,
                quantite = tonumber(entree.quantite) or 1 })
        end
        local demandeur = #lignesP > 0 and DemandeurDe(projet)
        if demandeur then
            local cles = {}
            for _, l in ipairs(lignesP) do table.insert(cles, tostring(l.recette)) end
            table.sort(cles)
            local k = table.concat(cles, ",")
            local f = fusions[k]
            if f then
                for _, l in ipairs(lignesP) do
                    for _, fl in ipairs(f.lignes) do
                        if tostring(fl.recette) == tostring(l.recette) then fl.quantite = fl.quantite + l.quantite end
                    end
                end
                local deja = false
                for _, p in ipairs(f.pour) do if p == demandeur then deja = true end end
                if not deja then table.insert(f.pour, demandeur) end
            else
                f = { projet = projet, lignes = lignesP, pour = { demandeur } }
                fusions[k] = f
                table.insert(rendus, f)
            end
        else
            table.insert(rendus, { projet = projet, lignes = lignesP })
        end
      end
    end
    for _, e in ipairs(rendus) do
      local projet, lignes = e.projet, e.lignes
      do
        if #lignes > 0 then
            -- Besoin complet (sans rien en stock), puis ce qui manque vraiment.
            local _, requis = NS.moteur.DecomposerPlusieurs(catalogue, {}, lignes, EstApprise)
            local arbres, manques = NS.moteur.DecomposerPlusieurs(catalogue, NS.projets.StocksDuCompte(), lignes, EstApprise)
            local pct = NS.moteur.Couverture(arbres) or 0
            -- Le pourcentage dit ce qui est reuni, comme les comptes des
            -- matieres (ce qui reste a fabriquer en route n'en fait pas partie).
            local total, reuni = 0, 0
            for objet, n in pairs(requis or {}) do
                if n > 0 then
                    total = total + n
                    reuni = reuni + (n - math.max(0, math.min(n, (manques or {})[objet] or 0)))
                end
            end
            if total > 0 then pct = reuni / total end
            -- Ce qu'il y aura a fabriquer une fois tout reuni.
            local fabriquer = {}
            for _, l in ipairs(lignes) do
                local r = catalogue[l.recette] or catalogue[tostring(l.recette)]
                local nomR = type(r) == "table" and (r.nom or r.name)
                if nomR and #fabriquer < 3 then table.insert(fabriquer, nomR) end
            end
            local nomBloc = projet.rapides and L.NAV_QUICK or NS.projets.NomDe(projet)
            -- Projet tire d'un plan de progression : dans les progressions,
            -- sous son nom seul.
            local deProg = not projet.rapides and NS.projets.EstDeProgression(projet)
            local commande = e.pour ~= nil
            if commande then deProg = false end
            -- Pour qui : les noms, a la couleur de leur classe.
            local pourQui
            if commande then
                local noms = {}
                for _, cleP in ipairs(e.pour) do
                    local nom = NS.inventaire.NomCourt(cleP)
                    local fiche
                    for _, f in ipairs(NS.base.TousLesPersonnages()) do if f.cle == cleP then fiche = f end end
                    local jeton = type(fiche) == "table" and fiche.jetonClasse
                    local c = jeton and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[jeton]
                    if c and c.colorStr then nom = "|c" .. c.colorStr .. nom .. "|r"
                    elseif c then nom = string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, nom) end
                    table.insert(noms, nom)
                end
                pourQui = string.format(L.TRACK_ORDER_FOR, table.concat(noms, ", "))
            end
            table.insert(liste, { groupe = deProg and "progression" or "projets", commande = commande or nil, pourQui = pourQui,
                cle = commande and ("commande" .. table.concat((function() local t = {} for _, l in ipairs(lignes) do table.insert(t, tostring(l.recette)) end table.sort(t) return t end)(), ",")) or ("projet" .. tostring(projet.id)),
                genre = "projet", rapides = projet.rapides,
                titreAnnonce = nomBloc, fabriquer = fabriquer, nLignes = #lignes, lignes = lignes,
                nom = (projet.rapides or deProg or commande) and nomBloc or string.format(L.GOAL_PROJECT, nomBloc), pct = pct, atteint = pct >= 1,
                matieres = Matieres(requis or {}, manques or {}) })
        end
      end
    end
end

-- Rangs vises du personnage affiche dans la fenetre (page Mes progressions).
function suivi.RangsVises()
    local liste = {}
    local ok, souci = pcall(NS.base.AvecPersonnage, NS.base.CleAffichee(), function()
        ObjectifsDeProgression(liste)
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("rangs vises", souci) end
    table.sort(liste, function(a, b) return tostring(a.nom) < tostring(b.nom) end)
    return liste
end

function suivi.Objectifs()
    -- Onglet Fabrications : fabrications rapides et projets nommes. Onglet
    -- Progressions : rangs vises, puis projets tires d'un plan.
    local liste = {}
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    local ok, souci = pcall(NS.base.AvecPersonnage, cle, function()
        ObjectifsDeProjets(liste)
        local rangs = {}
        ObjectifsDeProgression(rangs)
        -- Rang atteint : l'objectif quitte le suivi (felicitations a la place).
        for _, o in ipairs(rangs) do
            if not o.atteint then o.groupe = "progression" table.insert(liste, o) end
        end
        -- Les rangs vises avant les projets de progression ; les commandes
        -- pour mes autres personnages apres mes propres fabrications.
        local avant, apres = {}, {}
        for _, o in ipairs(liste) do
            if (o.groupe == "progression" and o.genre == "projet") or o.commande then table.insert(apres, o) else table.insert(avant, o) end
        end
        for k in pairs(liste) do liste[k] = nil end
        for _, o in ipairs(avant) do table.insert(liste, o) end
        for _, o in ipairs(apres) do table.insert(liste, o) end
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("objectifs de recolte", souci) end
    return liste
end

-- La barre d'avancement de QuestCore : texture des competences du jeu, fine
-- bordure d'infobulle aux coins arrondis, pourcentage dedans.
local function Barre(parent)
    local okF, b = pcall(CreateFrame, "StatusBar", nil, parent, "BackdropTemplate")
    b = okF and b or CreateFrame("StatusBar", nil, parent)
    b.sansEncre = true
    b:SetSize(90, 10)
    b:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    b:SetMinMaxValues(0, 1)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetColorTexture(0, 0, 0, 0.65)
    local okB, bordure = pcall(CreateFrame, "Frame", nil, b, "BackdropTemplate")
    bordure = okB and bordure or CreateFrame("Frame", nil, b)
    bordure:SetPoint("TOPLEFT", -2, 2)
    bordure:SetPoint("BOTTOMRIGHT", 2, -2)
    if bordure.SetBackdrop then
        bordure:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
        bordure:SetBackdropBorderColor(0.8, 0.65, 0.35, 1)
    end
    bordure:SetFrameLevel(b:GetFrameLevel() + 2)
    b.texte = bordure:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.texte:SetPoint("CENTER", b, "CENTER", 0, 0)
    local fichier, _, drapeaux = b.texte:GetFont()
    if fichier then b.texte:SetFont(NS.Police(fichier), 9, drapeaux) end
    b.texte:SetShadowOffset(1, -1)
    return b
end

local function Vue()
    local g = NS.base.ReglagesGeneraux()
    if g.vueRecolte == "progressions" or g.vueRecolte == "commandes" then return g.vueRecolte end
    return "fabrications"
end

-- Memes polices et memes tailles que le suivi des quetes de QuestCore :
-- titres un cran au-dessus, lignes a la taille du suivi.
-- La taille du suivi des quetes (reglage de QuestCore, 12 par defaut).
local TAILLE_LIGNE = 12
local function TailleDesQuetes()
    local d = _G.QuestCoreDB
    local s = type(d) == "table" and type(d.reglages) == "table" and type(d.reglages.general) == "table"
        and d.reglages.general.suivi
    return tonumber(type(s) == "table" and s.taille) or 12
end
local function Police(nom, repli) return _G[nom] and nom or repli end
local function Taille(fs, taille)
    local fichier, _, drapeaux = fs:GetFont()
    if fichier then fs:SetFont(NS.Police and NS.Police(fichier) or fichier, taille, drapeaux) end
end
local HAUT_ONGLETS = 38

-- Le suivi est tenu par son coin BAS gauche : quand il grandit (onglet
-- Session, objectifs deplies), il s'ouvre vers le haut et son bas reste ou
-- on l'a pose.
local function TenirParLeBas(cadre)
    local gauche, bas = cadre:GetLeft(), cadre:GetBottom()
    if not gauche or not bas then return end
    cadre:ClearAllPoints()
    cadre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", gauche, bas)
    NS.base.ReglagesGeneraux().placeSuivi = { point = "BOTTOMLEFT", relatif = "BOTTOMLEFT", x = gauche, y = bas }
end

local function Placer(cadre)
    cadre:ClearAllPoints()
    local place = NS.base.ReglagesGeneraux().placeSuivi
    if type(place) == "table" and place.point then
        cadre:SetPoint(place.point, UIParent, place.relatif or place.point, place.x or 0, place.y or 0)
        -- Ancienne position (centre, haut...) : convertie une fois par le bas.
        if place.point ~= "BOTTOMLEFT" then pcall(TenirParLeBas, cadre) end
    else
        cadre:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function Construire()
    local cadre = NS.charte.Fenetre("CraftCoreSuivi", LARGEUR_SUIVI, 120,
        { portrait = false, strate = "MEDIUM", sansPied = true })
    if cadre.titre then cadre.titre:SetText(NS.L.TRACK_TITLE) end

    -- Reglages de l'add-on, en haut a gauche : un clic les ouvre.
    local reglages = CreateFrame("Button", nil, cadre)
    reglages:SetSize(14, 14)
    reglages:SetPoint("TOPLEFT", cadre, "TOPLEFT", 19, -5)
    -- Au niveau du bouton de fermeture, au-dessus du cadre du jeu (sinon le
    -- bord du cadre le recouvre des que la fenetre est pleinement opaque).
    local fermer = cadre.fermer or cadre.CloseButton
    reglages:SetFrameLevel(math.max(cadre:GetFrameLevel() + 20, (fermer and fermer:GetFrameLevel() or 0) + 2))
    reglages:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    reglages:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    reglages:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(NS.L.OPEN_SETTINGS, 1, 1, 1)
        GameTooltip:Show()
    end)
    reglages:SetScript("OnLeave", function() GameTooltip:Hide() end)
    reglages:SetScript("OnClick", function() if NS.ecran and NS.ecran.Montrer then NS.ecran.Montrer("reglages") end end)
    cadre.boutonReglages = reglages
    cadre:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TenirParLeBas(self)
        suivi.Dessiner()
    end)
    cadre.fermer:SetScript("OnClick", function() cadre:Hide() end)
    cadre.textes, cadre.icones, cadre.barres, cadre.boutons = {}, {}, {}, {}

    -- Replier / deplier tout le suivi, comme celui des quetes de QuestCore.
    local niveauTitre = (cadre.fermer:GetFrameLevel() or cadre:GetFrameLevel()) + 1
    local replier = CreateFrame("Button", nil, cadre)
    replier:SetFrameLevel(niveauTitre)
    replier:SetSize(16, 16)
    replier:SetPoint("RIGHT", cadre.fermer, "LEFT", -2, 0)
    replier:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    replier:SetScript("OnClick", function()
        local g = NS.base.ReglagesGeneraux()
        g.suiviReplie = not g.suiviReplie or nil
        suivi.Dessiner()
    end)
    cadre.replier = replier
    cadre.resume = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cadre.resume:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -2)
    cadre.resume:SetPoint("RIGHT", cadre.zone, "RIGHT", 0, 0)
    cadre.resume:SetJustifyH("LEFT")
    cadre.resume:SetWordWrap(false)
    cadre.resume:Hide()
    -- Ancre : ne bouge qu'en mode Edition du jeu.
    cadre:SetScript("OnDragStart", function(self)
        if NS.suite and NS.suite.Libre and not NS.suite.Libre("CraftCoreSuivi") then return end
        self:StartMoving()
    end)
    if NS.suite and NS.suite.Ancrable then
        pcall(NS.suite.Ancrable, "CraftCoreSuivi", cadre, NS.L.TRACK_EDIT_LABEL)
    end

    -- Onglets, comme ceux du suivi des quetes de QuestCore : des boutons
    -- ronds, l'icone du jeu et un compte a cote, le nom au survol, un filet
    -- dessous. Fabrications (mes projets), commandes (pour mes autres
    -- personnages), progressions (rangs vises).
    cadre.vues = {}
    local largeurZone = LARGEUR_SUIVI - 2 * NS.charte.MARGE - 10
    local pas = math.floor(largeurZone / 3)
    for rang, v in ipairs({
        { "fabrications", NS.L.TRACK_TAB_CRAFTS, "Interface\\Icons\\Trade_BlackSmithing" },
        { "commandes", NS.L.TRACK_TAB_ORDERS, "Interface\\Icons\\INV_Letter_15" },
        { "progressions", NS.L.TRACK_TAB_PROGRESSIONS, "Interface\\Icons\\INV_Misc_Book_09" } }) do
        local b = CreateFrame("Button", nil, cadre)
        b:SetSize(24, 24)
        b:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", (rang - 1) * pas + 2, 0)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetSize(19, 19)
        b.fond:SetPoint("CENTER")
        b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        b.image = b:CreateTexture(nil, "ARTWORK")
        b.image:SetPoint("CENTER")
        b.image:SetSize(16, 16)
        b.image:SetTexture(v[3])
        if b.image.SetMask then pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        b.anneau = b:CreateTexture(nil, "OVERLAY")
        b.anneau:SetSize(41, 41)
        b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        b.compte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.compte:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.nom = v[2]
        function b.Compter(self, n) self.compte:SetText(tostring(n or 0)) end
        function b.Choisir(self, oui)
            self.image:SetDesaturated(not oui)
            self.image:SetAlpha(oui and 1 or 0.55)
            self.anneau:SetDesaturated(not oui)
            self.compte:SetTextColor(oui and 1 or 0.6, oui and 0.82 or 0.6, oui and 0 or 0.6)
        end
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.nom, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local cle = v[1]
        b:SetScript("OnClick", function()
            NS.base.ReglagesGeneraux().vueRecolte = cle
            suivi.Dessiner()
        end)
        cadre.vues[cle] = b
    end
    local filetHaut = cadre:CreateTexture(nil, "ARTWORK")
    filetHaut:SetHeight(1)
    filetHaut:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -HAUT_ONGLETS + 6)
    filetHaut:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", 0, -HAUT_ONGLETS + 6)
    filetHaut:SetColorTexture(0.8, 0.65, 0.35, 0.35)
    cadre.filetHaut = filetHaut

    -- Tout ouvrir / tout fermer les objectifs de l'onglet.
    local tout = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    tout:SetSize(110, 20)
    tout:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    tout:SetScript("OnClick", function(self) suivi.ToutOuvrir(self.ouvrir) end)
    cadre.tout = tout

    -- Onglet Objectifs : guider vers le lieu connu le plus proche d'une
    -- matiere qui manque encore (meme place que le bouton de la session).
    local guider = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    guider:SetSize(110, 20)
    guider:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    guider:SetScript("OnClick", function() suivi.Guider() end)
    guider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(NS.L.GUIDE_GOALS_HELP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    guider:Hide()
    cadre.guider = guider

    -- Presque transparente quand on court, nette a l'arret.
    local attente = 0
    cadre:SetScript("OnUpdate", function(self, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.2
        local bouge = NS.Lecture("IsPlayerMoving")
        local ok, enMouvement = false, false
        if bouge then ok, enMouvement = pcall(bouge) end
        local survol = self.IsMouseOver and self:IsMouseOver()
        self:SetAlpha((ok and enMouvement and not survol) and ALPHA_EN_COURSE or 1)
    end)
    Placer(cadre)
    cadre:Hide()
    return cadre
end

local function Texte(rang, police)
    local t = cadreSuivi.textes[rang]
    if not t then
        t = cadreSuivi:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        cadreSuivi.textes[rang] = t
    end
    t:SetFontObject(police or "GameFontHighlightSmall")
    -- Un texte est reutilise d'un tour a l'autre (nom, puis compte) : son
    -- alignement repart a gauche, sinon un nom herite du calage a droite.
    t:SetJustifyH("LEFT")
    t:SetWordWrap(true)
    t:Show()
    return t
end

-- Objectifs ouverts (deplies), par cle.
local function Ouverts()
    local g = NS.base.ReglagesGeneraux()
    if type(g.objectifsOuverts) ~= "table" then g.objectifsOuverts = {} end
    return g.objectifsOuverts
end

local function OngletDe(o)
    if o.groupe == "progression" then return "progressions" end
    if o.commande then return "commandes" end
    return "fabrications"
end

local function DeLOnglet(objectifs, vue)
    local rendu = {}
    for _, o in ipairs(objectifs) do
        if OngletDe(o) == vue then table.insert(rendu, o) end
    end
    return rendu
end

-- Tout ouvrir (oui) ou tout fermer les objectifs de l'onglet affiche.
function suivi.ToutOuvrir(oui)
    local ouverts = Ouverts()
    for _, o in ipairs(DeLOnglet(suivi.Objectifs(), Vue())) do ouverts[o.cle] = oui and true or nil end
    suivi.Dessiner()
end

-- Recette qui fabrique un objet (apprise), cherchee une fois par dessin.
local producteurs
local function Producteur(objet)
    if not producteurs then
        producteurs = {}
        for _, rec in pairs(CraftCoreDB and CraftCoreDB.recettes or {}) do
            if type(rec) == "table" and rec.objetProduit and NS.recettes.EstApprise and NS.recettes.EstApprise(rec.id) then
                producteurs[rec.objetProduit] = producteurs[rec.objetProduit] or rec
            end
        end
    end
    return producteurs[objet]
end

-- Les etapes de fabrication d'un projet, dans l'ordre : d'abord ce qu'il
-- faut fabriquer en route (barres, catalyseurs...), puis l'objet lui-meme.
-- Chaque etape : recette, objet, combien de fois, faite ou non.
-- Combien on en a sur soi, lu en direct dans le jeu (le releve des sacs a
-- une seconde de retard).
local function SurSoi(objet)
    local compter = NS.Lecture("C_Item.GetItemCount", "GetItemCount")
    local n = compter and NS.Appeler(compter, objet, false) or nil
    if type(n) == "number" then return n end
    return NS.inventaire.DisponibleDansLesSacs(objet) or 0
end

local function EtapesDeFabrication(lignes)
    local etapes = {}
    local catalogue = CraftCoreDB and CraftCoreDB.recettes or {}
    for _, l in ipairs(lignes or {}) do
        local rec = catalogue[tostring(l.recette)] or catalogue[l.recette]
        if type(rec) == "table" then
            local quantite = l.quantite or 1
            for _, comp in ipairs(rec.composants or {}) do
                local sous = Producteur(comp.objet)
                if sous and sous ~= rec then
                    local besoin = comp.quantite * quantite
                    local avoir = SurSoi(comp.objet)
                    local parFois = math.max(1, tonumber(sous.quantiteMin) or 1)
                    table.insert(etapes, { recette = sous, objet = comp.objet, besoin = besoin, avoir = math.min(avoir, besoin),
                        fois = math.max(1, math.ceil(math.max(0, besoin - avoir) / parFois)), faite = avoir >= besoin })
                end
            end
            table.insert(etapes, { recette = rec, objet = rec.objetProduit, besoin = quantite, fois = quantite, faite = false, finale = true })
        end
    end
    return etapes
end

-- La prochaine etape : la premiere pas faite. Rend l'etape, son rang, et
-- si elle peut etre lancee maintenant (tout dans les sacs).
local function ProchaineEtape(etapes)
    local A = NS.actions
    for rang, e in ipairs(etapes) do
        if not e.faite then
            local pret = A and A.EtatPourFabriquer and A.EtatPourFabriquer(e.recette) == true
            return e, rang, pret
        end
    end
    return nil
end

-- La premiere fabrication prete d'un projet. Rend la recette, le nombre de
-- fois, l'etape et son rang.
local function PremiereFabricationPrete(lignes)
    local A = NS.actions
    if not (A and A.EtatPourFabriquer) then return nil end
    local etapes = EtapesDeFabrication(lignes)
    local e, rang, pret = ProchaineEtape(etapes)
    if e and pret then
        return e.recette, math.min(e.fois, A.NombrePossible(e.recette)), e, rang, etapes
    end
    return nil, nil, nil, nil, etapes
end

-- Une fabrication prete dans le metier ouvert, pour un des objectifs du
-- suivi : la fenetre cachee du metier reste alors ouverte.
function suivi.FabricationPreteIci()
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return false end
    producteurs = nil
    for _, o in ipairs(objectifs or {}) do
        local rec = PremiereFabricationPrete(o.lignes)
        if rec and NS.recettes.PretALancer and NS.recettes.PretALancer(rec) then return true end
    end
    return false
end

-- La fabrication `idRec` sert-elle encore l'objectif `cle` ? Non si
-- l'objectif est atteint (rang vise, projet fini) ou si l'etape en cours a
-- deja ce qu'il lui faut, compte en direct dans les sacs.
function suivi.EncoreUtile(cle, idRec)
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return true end
    producteurs = nil
    for _, o in ipairs(objectifs or {}) do
        if o.cle == cle then
            if o.atteint then return false end
            for _, e in ipairs(EtapesDeFabrication(o.lignes)) do
                if e.recette and tostring(e.recette.id) == tostring(idRec) then
                    if e.finale then return true end
                    return SurSoi(e.objet) < (e.besoin or 0)
                end
            end
            return false
        end
    end
    return false
end

-- Le groupe d'un objectif dans son onglet, comme les zones du suivi des
-- quetes : cle et titre.
local function GroupeDe(o, vue)
    local L = NS.L
    if vue == "commandes" then return "commandes", L.TRACK_TAB_ORDERS end
    if vue == "progressions" then
        if o.genre == "progression" then return "rangs", L.TRACK_GROUP_RANKS end
        return "plans", L.TRACK_GROUP_PLANS
    end
    if o.rapides then return "rapides", L.NAV_QUICK end
    return "projets", L.TRACK_GROUP_PROJECTS
end

local function Favoris()
    local g = NS.base.ReglagesGeneraux()
    if type(g.favorisSuivi) ~= "table" then g.favorisSuivi = {} end
    return g.favorisSuivi
end

local function GroupesReplies()
    local g = NS.base.ReglagesGeneraux()
    if type(g.groupesReplies) ~= "table" then g.groupesReplies = {} end
    return g.groupesReplies
end

-- Les objectifs de l'onglet, presentes comme le suivi des quetes : des
-- groupes (comme les zones) separes d'un filet, qui se replient ; dedans,
-- chaque objectif comme une quete, son pourcentage a droite ; deplie, ses
-- matieres comme des objectifs de quete.
local function DessinerObjectifs(y, objectifs, vue)
    local L = NS.L
    local zone = cadreSuivi.zone
    local largeur = LARGEUR_SUIVI - 2 * NS.charte.MARGE - 10
    local nt, ni, nbo, ne, nf = 0, 0, 0, 0, 0
    local LIGNE = Police("ObjectiveTrackerLineFont", "GameFontHighlightSmall")
    local TITRE = Police("ObjectiveTrackerHeaderFont", "GameFontNormal")
    local function T(police, taille)
        nt = nt + 1
        local t = Texte(nt, police)
        if taille then Taille(t, taille) end
        return t
    end
    local function Icone()
        ni = ni + 1
        local icone = cadreSuivi.icones[ni]
        if not icone then
            icone = cadreSuivi:CreateTexture(nil, "ARTWORK")
            icone:SetSize(16, 16)
            cadreSuivi.icones[ni] = icone
        end
        icone:ClearAllPoints()
        icone:SetDesaturated(false)
        icone:Show()
        return icone
    end
    local function Filet(yF)
        nf = nf + 1
        cadreSuivi.filets = cadreSuivi.filets or {}
        local f = cadreSuivi.filets[nf]
        if not f then
            f = cadreSuivi:CreateTexture(nil, "ARTWORK")
            cadreSuivi.filets[nf] = f
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -yF)
        f:SetPoint("TOPRIGHT", zone, "TOPRIGHT", 0, -yF)
        if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(f, 1, 1) else f:SetHeight(1) end
        f:SetColorTexture(0.8, 0.65, 0.35, 0.35)
        f:Show()
    end
    local function Ligne(pool)
        cadreSuivi[pool] = cadreSuivi[pool] or {}
        local liste = cadreSuivi[pool]
        local rang = (pool == "entetes") and (ne + 1) or (nbo + 1)
        if pool == "entetes" then ne = rang else nbo = rang end
        local b = liste[rang]
        if not b then
            b = CreateFrame("Button", nil, cadreSuivi)
            b:SetHeight(18)
            b.marqueur = b:CreateTexture(nil, "ARTWORK")
            b.marqueur:SetSize(14, 14)
            b.marqueur:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.nom = b:CreateFontString(nil, "OVERLAY", TITRE)
            b.nom:SetPoint("LEFT", b.marqueur, "RIGHT", 4, 0)
            b.nom:SetJustifyH("LEFT")
            b.nom:SetWordWrap(false)
            b.droite = b:CreateFontString(nil, "OVERLAY", TITRE)
            b.droite:SetPoint("RIGHT", b, "RIGHT", 0, 0)
            b.droite:SetJustifyH("RIGHT")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            liste[rang] = b
        end
        b:ClearAllPoints()
        if b.creer then b.creer:Hide() end
        b:Show()
        return b
    end
    if #objectifs == 0 then
        local t = T(LIGNE, TAILLE_LIGNE)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
        t:SetWidth(largeur)
        t:SetText(L.GOAL_NONE)
        t:SetTextColor(0.8, 0.8, 0.8)
        return y + (t:GetStringHeight() or 14) + 8
    end
    -- Les groupes, dans l'ordre ou ils apparaissent.
    local groupes, ordre = {}, {}
    for _, o in ipairs(objectifs) do
        local cleG, titreG = GroupeDe(o, vue)
        if not groupes[cleG] then
            groupes[cleG] = { titre = titreG, liste = {} }
            table.insert(ordre, cleG)
        end
        table.insert(groupes[cleG].liste, o)
    end
    -- Les favoris en tete de leur groupe.
    local fav = Favoris()
    for _, gr in pairs(groupes) do
        local avant, apres = {}, {}
        for _, o in ipairs(gr.liste) do if fav[o.cle] then table.insert(avant, o) else table.insert(apres, o) end end
        for _, o in ipairs(apres) do table.insert(avant, o) end
        gr.liste = avant
    end
    local ouverts, replies = Ouverts(), GroupesReplies()
    for rangG, cleG in ipairs(ordre) do
        local gr = groupes[cleG]
        local replie = replies[cleG] == true
        if rangG > 1 then
            y = y + 8
            Filet(y)
            y = y + 6
        end
        -- En-tete du groupe : comme une zone du suivi des quetes.
        local e = Ligne("entetes")
        e:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
        e:SetWidth(largeur)
        e:SetHeight(20)
        e.marqueur:SetTexture(replie and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        e.nom:SetFontObject("GameFontNormal")
        Taille(e.nom, TAILLE_LIGNE + 3)
        e.nom:SetText(gr.titre)
        e.nom:SetTextColor(1, 0.82, 0)
        e.droite:SetFontObject("GameFontNormal")
        Taille(e.droite, TAILLE_LIGNE)
        e.droite:SetText(tostring(#gr.liste))
        e.droite:SetTextColor(0.8, 0.8, 0.8)
        e.nom:SetPoint("RIGHT", e.droite, "LEFT", -6, 0)
        e:SetScript("OnClick", function()
            replies[cleG] = not replies[cleG] or nil
            suivi.Dessiner()
        end)
        y = y + 24
        if not replie then
            for _, o in ipairs(gr.liste) do
                local estOuvert = ouverts[o.cle] == true
                local b = Ligne("boutons")
                b:SetPoint("TOPLEFT", zone, "TOPLEFT", 6, -y)
                b:SetWidth(largeur - 6)
                b:SetHeight(18)
                b.marqueur:SetTexture(estOuvert and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
                b.nom:SetFontObject(TITRE)
                Taille(b.nom, TAILLE_LIGNE + 1)
                b.nom:SetText(o.nom)
                if o.atteint then b.nom:SetTextColor(0.31, 0.82, 0.41) else b.nom:SetTextColor(1, 0.82, 0) end
                -- Le pourcentage, comme celui des quetes.
                local pct = math.floor((o.pct or 0) * 100 + 0.5)
                b.droite:SetFontObject(TITRE)
                Taille(b.droite, TAILLE_LIGNE)
                b.droite:SetText(pct .. " %")
                if pct >= 100 then b.droite:SetTextColor(0.31, 0.82, 0.41) else b.droite:SetTextColor(0.8, 0.8, 0.8) end
                b.nom:SetPoint("RIGHT", b.droite, "LEFT", -8, 0)
                -- Etoile de favori, a droite, comme pour les quetes.
                if not b.etoile then
                    b.etoile = CreateFrame("Button", nil, b)
                    b.etoile:SetSize(12, 12)
                    b.etoile.t = b.etoile:CreateTexture(nil, "ARTWORK")
                    b.etoile.t:SetAllPoints()
                    b.etoile:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
                local estFavori = Favoris()[o.cle] == true
                local te = b.etoile.t
                local atlas = estFavori and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off"
                if not (te.SetAtlas and pcall(te.SetAtlas, te, atlas) and te:GetAtlas()) then
                    te:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
                    te:SetDesaturated(not estFavori)
                end
                b.etoile:SetAlpha(estFavori and 1 or 0.6)
                b.etoile:ClearAllPoints()
                b.etoile:SetPoint("RIGHT", b, "RIGHT", 0, 1)
                b.etoile:SetFrameLevel(b:GetFrameLevel() + 3)
                local cleF = o.cle
                b.etoile:SetScript("OnClick", function()
                    Favoris()[cleF] = not Favoris()[cleF] or nil
                    suivi.Dessiner()
                end)
                b.etoile:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(estFavori and L.TRACK_FAV_REMOVE or L.TRACK_FAV_ADD, 1, 0.82, 0)
                    GameTooltip:Show()
                end)
                b.etoile:Show()
                b.droite:ClearAllPoints()
                b.droite:SetPoint("RIGHT", b.etoile, "LEFT", -6, 0)
                local cle = o.cle
                b:SetScript("OnClick", function()
                    ouverts[cle] = not ouverts[cle] or nil
                    suivi.Dessiner()
                end)
                -- Au survol : une infobulle collee a droite du suivi, avec la
                -- prochaine etape et ce qui manque encore dans les sacs (et ou
                -- le trouver), quand le bouton Creer n'est pas la.
                local objectif = o
                b:SetScript("OnEnter", function(self)
                    local etapesS = EtapesDeFabrication(objectif.lignes)
                    local e, rangE = ProchaineEtape(etapesS)
                    GameTooltip:SetOwner(self, "ANCHOR_NONE")
                    GameTooltip:ClearAllPoints()
                    local droite = cadreSuivi:GetRight() or 0
                    local largeurEcran = UIParent:GetWidth() or 0
                    if droite + 300 > largeurEcran then
                        GameTooltip:SetPoint("TOPRIGHT", cadreSuivi, "TOPLEFT", -4, 0)
                    else
                        GameTooltip:SetPoint("TOPLEFT", cadreSuivi, "TOPRIGHT", 4, 0)
                    end
                    GameTooltip:SetText(objectif.nom or "", 1, 0.82, 0)
                    if e then
                        GameTooltip:AddLine(string.format(L.CRAFT_STEP_TIP, rangE, #etapesS, NS.inventaire.NomDObjet(e.objet), e.fois or 1), 1, 1, 1, true)
                        local pret = NS.actions and NS.actions.EtatPourFabriquer and NS.actions.EtatPourFabriquer(e.recette)
                        if pret == false then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(L.CRAFT_NOT_IN_BAGS, 1, 0.5, 0.3, true)
                            NS.inventaire.ComposantsDansLInfobulle(GameTooltip, e.recette)
                        elseif pret == nil then
                            GameTooltip:AddLine(L.CRAFT_OTHER_CHAR, 0.8, 0.8, 0.8, true)
                        end
                    end
                    for _, achat in pairs(objectif.achats or {}) do
                        GameTooltip:AddLine(L.CRAFT_TO_BUY, 1, 0.82, 0, true)
                        break
                    end
                    for objet, n in pairs(objectif.achats or {}) do
                        local dans = NS.inventaire.DisponibleDansLesSacs(objet) or 0
                        if dans < n then
                            GameTooltip:AddLine("  " .. NS.inventaire.NomDObjet(objet) .. "  x" .. (n - dans), 1, 1, 1)
                        end
                    end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                -- Tout est reuni : un bouton Creer sur la ligne, comme la petite
                -- carte et l'etoile du suivi des quetes. Un clic lance la
                -- premiere fabrication prete (le premier ouvre le metier).
                local recettePrete, fois, etapeP, rangP, etapes = PremiereFabricationPrete(o.lignes)
                -- Une etape vient de se terminer : on le dit, et on invite a la suivante.
                local suiviEtapes = NS.base.ReglagesGeneraux()
                suiviEtapes.etapesFab = type(suiviEtapes.etapesFab) == "table" and suiviEtapes.etapesFab or {}
                if rangP then
                    local avant = suiviEtapes.etapesFab[o.cle]
                    if avant and rangP > avant and etapes and #etapes > 1 then
                        NS.Dire(string.format(L.CRAFT_STEP_DONE, avant, rangP))
                    end
                    suiviEtapes.etapesFab[o.cle] = rangP
                end
                if recettePrete then
                    if not b.creer then
                        b.creer = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
                        b.creer:SetSize(52, 16)
                    end
                    b.creer:ClearAllPoints()
                    b.creer:SetPoint("RIGHT", b.droite, "LEFT", -6, 0)
                    b.creer:SetSize(60, 16)
                    b.creer:SetText((etapes and #etapes > 1) and L.CRAFT_STEP_NOW or L.CRAFT_BUTTON)
                    local cleO, idRec = o.cle, recettePrete.id
                    NS.actions.PreparerBoutonFabriquer(b.creer, recettePrete, fois, function()
                        return suivi.EncoreUtile(cleO, idRec)
                    end)
                    -- L'infobulle dit quelle etape le clic va lancer.
                    b.creer.etape = (etapes and #etapes > 1 and etapeP) and string.format(L.CRAFT_STEP_TIP, rangP, #etapes,
                        NS.inventaire.NomDObjet(etapeP.objet), fois or 1) or nil
                    if not b.creer.etapeAccroche then
                        b.creer.etapeAccroche = true
                        b.creer:HookScript("OnEnter", function(self)
                            if self.etape and GameTooltip:IsOwned(self) then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(self.etape, 1, 0.82, 0, true)
                                GameTooltip:Show()
                            end
                        end)
                    end
                    local txt = b.creer:GetFontString()
                    if txt then Taille(txt, 10) end
                    b.creer:SetFrameLevel(b:GetFrameLevel() + 3)
                    b.nom:SetPoint("RIGHT", b.creer, "LEFT", -6, 0)
                end
                -- Des matieres manquent et leurs lieux sont connus : la petite
                -- carte du suivi des quetes lance le guidage de recolte.
                local lieux = (not recettePrete) and suivi.LieuxManquants({ o }) or {}
                if #lieux > 0 then
                    if not b.pion then
                        b.pion = CreateFrame("Button", nil, b)
                        b.pion:SetSize(18, 18)
                        b.pion.fond = b.pion:CreateTexture(nil, "BACKGROUND")
                        b.pion.fond:SetSize(14, 14)
                        b.pion.fond:SetPoint("CENTER")
                        b.pion.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
                        b.pion.t = b.pion:CreateTexture(nil, "ARTWORK")
                        b.pion.t:SetSize(12, 12)
                        b.pion.t:SetPoint("CENTER")
                        b.pion.t:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
                        if b.pion.t.SetMask then pcall(b.pion.t.SetMask, b.pion.t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
                        b.pion.anneau = b.pion:CreateTexture(nil, "OVERLAY")
                        b.pion.anneau:SetSize(31, 31)
                        b.pion.anneau:SetPoint("TOPLEFT", b.pion, "TOPLEFT", 0, 0)
                        b.pion.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                        b.pion:SetScript("OnClick", function() suivi.Guider() end)
                        b.pion:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(suivi.EnGuidage() and L.GUIDE_GOALS_STOP or L.GUIDE_GOALS, 1, 0.82, 0)
                            GameTooltip:AddLine(L.GUIDE_GOALS_HELP, 1, 1, 1, true)
                            GameTooltip:Show()
                        end)
                        b.pion:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end
                    b.pion:ClearAllPoints()
                    b.pion:SetPoint("RIGHT", b.droite, "LEFT", -4, 0)
                    b.pion:SetFrameLevel(b:GetFrameLevel() + 3)
                    local actif = suivi.EnGuidage()
                    b.pion.t:SetDesaturated(not actif)
                    b.pion.anneau:SetDesaturated(not actif)
                    b.pion:Show()
                    b.nom:SetPoint("RIGHT", b.pion, "LEFT", -4, 0)
                elseif b.pion then
                    b.pion:Hide()
                end
                y = y + 20
                -- Tout est reuni et il y a plusieurs etapes : elles s'affichent
                -- dessous, dans l'ordre, chacune avec son etat.
                if (o.pct or 0) >= 1 and etapes and #etapes > 1 then
                    -- De l'air sous la ligne (et son bouton) avant les etapes.
                    y = y + 4
                    for rangE, e in ipairs(etapes) do
                        local t = T(LIGNE, TAILLE_LIGNE - 1)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -(y - 2))
                        t:SetWidth(largeur - 24 - 70)
                        t:SetWordWrap(false)
                        -- Compte "fait / a faire" : 0 / 5, puis 1 / 5... jusqu'a 5 / 5.
                        local fait, total
                        if e.finale then
                            local cleT = tostring(o.cle) .. "/" .. tostring(e.recette.id)
                            suiviEtapes.totauxFab = type(suiviEtapes.totauxFab) == "table" and suiviEtapes.totauxFab or {}
                            total = math.max(tonumber(suiviEtapes.totauxFab[cleT]) or 0, e.besoin or 1)
                            suiviEtapes.totauxFab[cleT] = total
                            fait = total - (e.besoin or 1)
                        else
                            fait, total = e.avoir or 0, e.besoin or 1
                        end
                        t:SetText(string.format(L.CRAFT_STEP_LINE, rangE, NS.inventaire.NomDObjet(e.objet), fait, total))
                        local etat = T(LIGNE, TAILLE_LIGNE - 1)
                        etat:ClearAllPoints()
                        etat:SetPoint("TOPRIGHT", zone, "TOPLEFT", largeur, -(y - 2))
                        etat:SetWidth(70)
                        etat:SetJustifyH("RIGHT")
                        -- Faite : toute la ligne en vert. La prochaine : en blanc,
                        -- suivie de "A creer" (le bouton de la ligne la lance).
                        -- Les suivantes : en blanc.
                        if e.faite then
                            t:SetTextColor(0.31, 0.82, 0.41)
                            etat:SetText(L.GUIDE_DONE)
                            etat:SetTextColor(0.31, 0.82, 0.41)
                        elseif rangE == rangP then
                            t:SetTextColor(1, 1, 1)
                            etat:SetText(L.CRAFT_STEP_NOW)
                            etat:SetTextColor(1, 0.82, 0)
                        else
                            t:SetTextColor(1, 1, 1)
                            etat:SetText("")
                        end
                        y = y + 14
                    end
                    y = y + 2
                end
                -- Commande : pour qui, en dessous, comme l'XP sous une zone.
                if o.pourQui then
                    local t = T(LIGNE, TAILLE_LIGNE - 1)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -(y - 2))
                    t:SetWidth(largeur - 24)
                    t:SetWordWrap(false)
                    t:SetText(o.pourQui)
                    t:SetTextColor(0.8, 0.8, 0.8)
                    y = y + 14
                end
                if estOuvert then
                    if o.detail then
                        -- L'objectif (rang actuel, rang vise), puis un petit
                        -- filet avant les matieres.
                        y = y + 4
                        local t = T(LIGNE, TAILLE_LIGNE - 1)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -y)
                        t:SetWidth(largeur - 24)
                        t:SetText(o.detail)
                        t:SetTextColor(0.8, 0.8, 0.8)
                        y = y + (t:GetStringHeight() or 14) + 5
                        nf = nf + 1
                        cadreSuivi.filets = cadreSuivi.filets or {}
                        local f = cadreSuivi.filets[nf]
                        if not f then
                            f = cadreSuivi:CreateTexture(nil, "ARTWORK")
                            cadreSuivi.filets[nf] = f
                        end
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -y)
                        f:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -40, -y)
                        if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(f, 1, 1) else f:SetHeight(1) end
                        f:SetColorTexture(0.8, 0.65, 0.35, 0.22)
                        f:Show()
                        y = y + 6
                    end
                    if #(o.matieres or {}) == 0 then
                        local t = T(LIGNE, TAILLE_LIGNE)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 28, -y)
                        t:SetWidth(largeur - 28)
                        t:SetText(L.GOAL_NOTHING_TO_GATHER)
                        t:SetTextColor(0.8, 0.8, 0.8)
                        y = y + 16
                    end
                    for _, m in ipairs(o.matieres or {}) do
                        local icone = Icone()
                        icone:SetPoint("TOPLEFT", zone, "TOPLEFT", 28, -y)
                        icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, m.objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
                        icone:SetDesaturated(m.possede == 0)
                        local nom = T(LIGNE, TAILLE_LIGNE)
                        nom:ClearAllPoints()
                        nom:SetPoint("LEFT", icone, "RIGHT", 6, 0)
                        nom:SetWidth(largeur - 28 - 22 - 60)
                        nom:SetWordWrap(false)
                        nom:SetText(NS.inventaire.NomDObjet(m.objet))
                        local compte = T(LIGNE, TAILLE_LIGNE)
                        compte:ClearAllPoints()
                        compte:SetPoint("RIGHT", icone, "LEFT", largeur - 2 - 28, 0)
                        compte:SetWidth(60)
                        compte:SetJustifyH("RIGHT")
                        compte:SetText(math.min(m.possede, m.requis) .. " / " .. m.requis)
                        if m.manque == 0 then
                            nom:SetTextColor(0.5, 0.5, 0.5)
                            compte:SetTextColor(0.31, 0.82, 0.41)
                        elseif m.possede == 0 then
                            nom:SetTextColor(0.6, 0.6, 0.6)
                            compte:SetTextColor(0.6, 0.6, 0.6)
                        else
                            nom:SetTextColor(0.85, 0.85, 0.85)
                            compte:SetTextColor(1, 1, 1)
                        end
                        y = y + 18
                    end
                    y = y + 4
                end
            end
        end
    end
    return y + 4
end

function suivi.Dessiner()
    if not cadreSuivi then return end
    local L = NS.L
    for _, t in ipairs(cadreSuivi.textes) do t:Hide() end
    for _, i in ipairs(cadreSuivi.icones) do i:Hide() end
    for _, b in ipairs(cadreSuivi.barres) do b:Hide() end
    for _, b in ipairs(cadreSuivi.boutons) do b:Hide() end
    for _, b in ipairs(cadreSuivi.entetes or {}) do b:Hide() end
    for _, f in ipairs(cadreSuivi.filets or {}) do f:Hide() end
    if cadreSuivi.filetCommandes then cadreSuivi.filetCommandes:Hide() end
    local vue = Vue()
    TAILLE_LIGNE = TailleDesQuetes()
    producteurs = nil
    local objectifs = suivi.Objectifs()
    local g = NS.base.ReglagesGeneraux()
    cadreSuivi.replier:SetNormalTexture(g.suiviReplie and "Interface\\Buttons\\UI-PlusButton-Up"
        or "Interface\\Buttons\\UI-MinusButton-Up")
    if g.suiviReplie then
        -- Replie : une ligne de resume, la moyenne des objectifs.
        for _, b in pairs(cadreSuivi.vues) do b:Hide() end
        if cadreSuivi.filetHaut then cadreSuivi.filetHaut:Hide() end
        cadreSuivi.tout:Hide()
        cadreSuivi.guider:Hide()
        local texte = L.GOAL_NONE_SHORT
        if #objectifs > 0 then
            local somme = 0
            for _, o in ipairs(objectifs) do somme = somme + o.pct end
            texte = string.format(L.TRACK_FOLDED_GOALS, #objectifs, math.floor(somme / #objectifs * 100 + 0.5))
        end
        cadreSuivi.resume:SetText(texte)
        cadreSuivi.resume:Show()
        -- Meme hauteur que le suivi des quetes replie (QuestCore).
        cadreSuivi:SetHeight(100)
        return
    end
    cadreSuivi.resume:Hide()
    local deLOnglet = DeLOnglet(objectifs, vue)
    local comptes = { fabrications = 0, commandes = 0, progressions = 0 }
    for _, o in ipairs(objectifs) do comptes[OngletDe(o)] = comptes[OngletDe(o)] + 1 end
    for cle, b in pairs(cadreSuivi.vues) do
        b:Compter(comptes[cle])
        b:Choisir(cle == vue)
        b:Show()
    end
    if cadreSuivi.filetHaut then cadreSuivi.filetHaut:Show() end
    local y = HAUT_ONGLETS
    y = DessinerObjectifs(y, deLOnglet, vue)
    -- Tout ouvrir / tout fermer : selon ce qui est deja ouvert.
    local ouverts, tousOuverts = Ouverts(), #deLOnglet > 0
    for _, o in ipairs(deLOnglet) do if not ouverts[o.cle] then tousOuverts = false end end
    cadreSuivi.tout.ouvrir = not tousOuverts
    cadreSuivi.tout:SetText(tousOuverts and L.TRACK_CLOSE_ALL or L.TRACK_OPEN_ALL)
    cadreSuivi.tout:SetShown(#deLOnglet > 1)
    -- Guidage possible si une matiere qui manque a un lieu connu.
    local guidable = suivi.EnGuidage() or #suivi.LieuxManquants(objectifs) > 0
    cadreSuivi.guider:SetShown(guidable)
    cadreSuivi.guider:SetText(suivi.EnGuidage() and L.GUIDE_GOALS_STOP or L.GUIDE_GOALS)
    if guidable or #deLOnglet > 1 then y = y + 26 end
    cadreSuivi:SetHeight(24 + NS.charte.MARGE + y + NS.charte.MARGE + 4)
end

-- Affichage permanent (reglage) : le suivi se montre des la connexion, meme
-- sans rien ramasse ; sinon il attend le premier objet utile.
function suivi.Permanent() return NS.base.ReglagesGeneraux().suiviPermanent == true end

function suivi.Demarrer()
    if Actif() and suivi.Permanent() then suivi.Montrer() end
end

function suivi.Montrer()
    cadreSuivi = cadreSuivi or Construire()
    suivi.Dessiner()
    cadreSuivi:Show()
end

function suivi.Reinitialiser()
    local d = CraftCoreDB
    local cle = NS.ClePersonnage and NS.ClePersonnage() or "?"
    if type(d) == "table" and d.suiviRecolte then d.suiviRecolte[cle] = nil end
    suivi.Dessiner()
end

-- Appele apres chaque releve des sacs avec ce qui vient d'y arriver.
function suivi.ObjetsArrives(arrives)
    if not Actif() or type(arrives) ~= "table" then return end
    local session = Session()
    local change = false
    for objet, n in pairs(arrives) do
        local cle = NS.ClePersonnage and NS.ClePersonnage()
        local ok, lignes = pcall(NS.base.AvecPersonnage, cle, Utilite, objet)
        if ok and #lignes > 0 then
            local e = session.objets[objet] or { n = 0 }
            e.n = (e.n or 0) + n
            session.ordre = (session.ordre or 0) + 1
            e.ordre = session.ordre
            e.lignes = lignes
            session.objets[objet] = e
            change = true
        elseif not ok and NS.base.NoterIncident then
            NS.base.NoterIncident("suivi de recolte", lignes)
        end
    end
    if change then
        suivi.Montrer()
    elseif cadreSuivi and cadreSuivi:IsShown() and Vue() == "objectifs" then
        -- Les pourcentages suivent les sacs, meme pour un objet sans autre usage.
        suivi.Dessiner()
    end
end

-- ---------------------------------------------------------------------------
-- Fond du suivi (gris, parchemin ou illustre), commun a la suite : pose
-- apres chaque rendu ; sur parchemin, les textes passent a l'encre.
-- ---------------------------------------------------------------------------

local DessinerSansFond = suivi.Dessiner
suivi.Dessiner = function(...)
    DessinerSansFond(...)
    if not cadreSuivi or not NS.charte.HabillerSuivi then return end
    local ok, souci = pcall(function()
        local parchemin = NS.charte.HabillerSuivi(cadreSuivi)
        NS.charte.EncrerTextes(cadreSuivi.textes, parchemin)
        local autres = { cadreSuivi.resume }
        for _, b in ipairs(cadreSuivi.boutons or {}) do table.insert(autres, b.nom) end
        NS.charte.EncrerTextes(autres, parchemin)
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("fond du suivi", souci) end
end
if NS.charte.SurFondDesSuivis then NS.charte.SurFondDesSuivis(function() suivi.Dessiner() end) end

-- ---------------------------------------------------------------------------
-- Lieux de recolte : ou chaque matiere a ete ramassee (noeuds d'herbes, de
-- minerai, coffres, peche), pour les afficher sur la carte de MapCore.
-- Points proches fusionnes ; au plus 60 lieux par matiere et par carte.
-- ---------------------------------------------------------------------------

local RAYON_FUSION = 0.012

-- Metier de recolte d'une matiere : "herbes" (herboristerie), "minerais"
-- (minage : minerais, pierres, gemmes) ou nil (autre chose, ex. un coffre).
-- Herbes, minerais, pierres et gemmes du jeu d'origine : reconnus d'emblee,
-- meme pour les lieux notes avant que le metier ne soit memorise.
local CONNUS = {}
for _, id in ipairs({ 765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819,
    3820, 3821, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468, 19726 }) do
    CONNUS[id] = "herbes"
end
for _, id in ipairs({ 2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370, 2835, 2836, 2838, 7912, 12365,
    774, 818, 1206, 1210, 1529, 1705, 3864, 7909, 7910, 12361, 12364, 12799, 12800 }) do
    CONNUS[id] = "minerais"
end

-- Ce qui a ete appris en recoltant (sort lance juste avant le butin) fait
-- foi ; a defaut, la classe de l'objet.
local function MetierDeMatiere(objet)
    local d = CraftCoreDB
    local appris = type(d) == "table" and type(d.metierObjet) == "table" and d.metierObjet[objet]
    if appris then return appris end
    if CONNUS[objet] then return CONNUS[objet] end
    local info = NS.Lecture("C_Item.GetItemInfoInstant", "GetItemInfoInstant")
    local _, _, _, _, _, classe, sousClasse = NS.Appeler(info, objet)
    if classe == 7 and sousClasse == 9 then return "herbes" end
    if (classe == 7 and sousClasse == 7) or classe == 3 then return "minerais" end
    return nil
end

-- Dernier sort de recolte lance : Cueillette (herboristerie) ou Minage, par
-- leur nom dans la langue du jeu, tous rangs confondus.
local dernierSort = { metier = nil, quand = 0 }
local function NomDeSort(id)
    local f = NS.Lecture("C_Spell.GetSpellName")
    local nom = f and NS.Appeler(f, id)
    if not nom then nom = NS.Appeler(NS.Lecture("GetSpellInfo"), id) end
    return nom
end
local ecouteSorts = CreateFrame("Frame")
pcall(ecouteSorts.RegisterUnitEvent or ecouteSorts.RegisterEvent, ecouteSorts, "UNIT_SPELLCAST_SUCCEEDED", "player")
ecouteSorts:SetScript("OnEvent", function(_, _, _, _, idSort)
    local nom = NomDeSort(idSort)
    if not nom then return end
    local metier
    if nom == NomDeSort(2366) then metier = "herbes"
    elseif nom == NomDeSort(2575) then metier = "minerais" end
    if metier then dernierSort.metier, dernierSort.quand = metier, NS.Appeler(GetTime) or 0 end
end)
local function SortRecent()
    local maintenant = NS.Appeler(GetTime) or 0
    if dernierSort.metier and maintenant - dernierSort.quand < 8 then return dernierSort.metier end
    return nil
end

local OterRepere -- plus bas

local function NoterLieux()
    local d = CraftCoreDB
    if type(d) ~= "table" then return end
    local source = NS.Appeler(NS.Lecture("GetLootSourceInfo"), 1)
    local peche = NS.Appeler(NS.Lecture("IsFishingLoot"))
    if not peche and not (type(source) == "string" and string.find(source, "^GameObject")) then return end
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carte and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
    if type(pos) ~= "table" or not pos.GetXY then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    d.lieux = d.lieux or {}
    for slot = 1, tonumber(NS.Appeler(NS.Lecture("GetNumLootItems"))) or 0 do
        local lien = NS.Appeler(NS.Lecture("GetLootSlotLink"), slot)
        local objet = type(lien) == "string" and tonumber(string.match(lien, "item:(%d+)"))
        local metier = objet and (peche and "peche" or SortRecent() or MetierDeMatiere(objet))
        if metier then
            pcall(OterRepere, carte, x, y, metier)
            -- Appris pour de bon : sert aussi aux lieux deja notes de cet objet.
            if peche or SortRecent() then
                d.metierObjet = d.metierObjet or {}
                d.metierObjet[objet] = metier
            end
            local parCarte = d.lieux[objet] or {}
            d.lieux[objet] = parCarte
            local liste = parCarte[carte] or {}
            parCarte[carte] = liste
            local fusion
            for _, l in ipairs(liste) do
                if math.abs(l[1] - x) < RAYON_FUSION and math.abs(l[2] - y) < RAYON_FUSION then fusion = l break end
            end
            if fusion then
                fusion[3] = (fusion[3] or 1) + 1
            elseif #liste < 60 then
                table.insert(liste, { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, 1, metier })
            end
        end
    end
end

-- Noeud qu'on ne peut pas recolter ("Requiert Minage") : on note quand meme
-- l'endroit, pour y revenir avec un personnage qui a le metier. Le nom du
-- noeud vient de l'infobulle du jeu quand elle est affichee. Une vraie
-- recolte au meme endroit remplace ensuite le repere.
local NOMS_METIER = { herbes = { 2366, "Herboristerie", "Herbalism" }, minerais = { 2575, "Minage", "Mining" } }
local ICONES_METIER = { herbes = "Interface\\Icons\\Trade_Herbalism", minerais = "Interface\\Icons\\Trade_Mining" }

local function MetierExige(message)
    if type(message) ~= "string" then return nil end
    for metier, noms in pairs(NOMS_METIER) do
        for _, n in ipairs(noms) do
            local nom = type(n) == "number" and NomDeSort(n) or n
            if nom and nom ~= "" and string.find(message, nom, 1, true) then return metier end
        end
    end
    return nil
end

local function NoterNoeudRepere(message, metierConnu, nomConnu)
    local metier = metierConnu or MetierExige(message)
    local d = CraftCoreDB
    if not metier or type(d) ~= "table" then return end
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carte and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
    if type(pos) ~= "table" or not pos.GetXY then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    local nom = nomConnu
    local tt = _G.GameTooltip
    local ligne = _G.GameTooltipTextLeft1
    if not nom and tt and tt:IsShown() and ligne and ligne.GetText then nom = ligne:GetText() end
    d.noeuds = d.noeuds or {}
    local liste = d.noeuds[carte] or {}
    d.noeuds[carte] = liste
    for _, l in ipairs(liste) do
        if l[4] == metier and math.abs(l[1] - x) < RAYON_FUSION and math.abs(l[2] - y) < RAYON_FUSION then
            l[5] = l[5] or nom
            return
        end
    end
    if #liste < 200 then
        table.insert(liste, { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, 1, metier, nom })
    end
end

-- Recolte faite : le repere au meme endroit n'a plus lieu d'etre.
OterRepere = function(carte, x, y, metier)
    local liste = type(CraftCoreDB) == "table" and CraftCoreDB.noeuds and CraftCoreDB.noeuds[carte]
    for i = #(liste or {}), 1, -1 do
        local l = liste[i]
        if l[4] == metier and math.abs(l[1] - x) < RAYON_FUSION * 2 and math.abs(l[2] - y) < RAYON_FUSION * 2 then
            table.remove(liste, i)
        end
    end
end

-- Debut d'une cueillette ou d'un minage : le noeud est note tout de suite,
-- avec son nom (la cible du sort). Si quelqu'un l'a pris avant nous, le
-- repere reste ; si la recolte aboutit, le vrai lieu le remplace.
local function NoterNoeudVise(cible, idSort)
    local nom = NomDeSort(idSort)
    local metier = nom and ((nom == NomDeSort(2366) and "herbes") or (nom == NomDeSort(2575) and "minerais"))
    if not metier then return end
    NoterNoeudRepere(nil, metier, type(cible) == "string" and cible ~= "" and cible or nil)
    if _G.CraftCoreAPI and _G.CraftCoreAPI.OublierLieux then _G.CraftCoreAPI.OublierLieux() end
end

local ecouteVise = CreateFrame("Frame")
pcall(ecouteVise.RegisterUnitEvent or ecouteVise.RegisterEvent, ecouteVise, "UNIT_SPELLCAST_SENT", "player")
ecouteVise:SetScript("OnEvent", function(_, _, unite, cible, _, idSort)
    if unite ~= "player" then return end
    local ok, souci = pcall(NoterNoeudVise, cible, idSort)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("noeud vise", souci) end
end)

local ecouteErreurs = CreateFrame("Frame")
pcall(ecouteErreurs.RegisterEvent, ecouteErreurs, "UI_ERROR_MESSAGE")
ecouteErreurs:SetScript("OnEvent", function(_, _, a, b)
    -- Selon la version du jeu : (type, message) ou (message).
    local message = type(b) == "string" and b or a
    local ok, souci = pcall(NoterNoeudRepere, message)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("noeud repere", souci) end
end)

local ecouteLieux = CreateFrame("Frame")
pcall(ecouteLieux.RegisterEvent, ecouteLieux, "LOOT_OPENED")
ecouteLieux:SetScript("OnEvent", function()
    local ok, souci = pcall(NoterLieux)
    if _G.CraftCoreAPI and _G.CraftCoreAPI.OublierLieux then _G.CraftCoreAPI.OublierLieux() end
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("lieux de recolte", souci) end
end)

-- Pour MapCore : les lieux connus sur une carte, { objet, x, y, n }.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
-- Le resultat est garde 3 secondes par carte : la minicarte le demande dix
-- fois par seconde.
local lieuxEnCache, lieuxCarte, lieuxQuand = nil, nil, 0
local ConstruireLieux
_G.CraftCoreAPI.Lieux = function(carte)
    local maintenant = NS.Appeler(GetTime) or 0
    if lieuxEnCache and lieuxCarte == carte and maintenant - lieuxQuand < 3 then return lieuxEnCache end
    lieuxEnCache, lieuxCarte, lieuxQuand = ConstruireLieux(carte), carte, maintenant
    return lieuxEnCache
end
_G.CraftCoreAPI.OublierLieux = function() lieuxEnCache = nil end
ConstruireLieux = function(carte)
    local liste = {}
    local d = CraftCoreDB
    for objet, parCarte in pairs(type(d) == "table" and d.lieux or {}) do
        for _, l in ipairs(parCarte[carte] or {}) do
            local metier = l[4] or MetierDeMatiere(objet)
            if metier then
                table.insert(liste, { objet = objet, x = l[1], y = l[2], n = l[3] or 1, metier = metier,
                    nomType = NS.inventaire.NomDObjet(objet) })
            end
        end
    end
    -- Noeuds reperes sans pouvoir les recolter : symbole du metier.
    for _, l in ipairs(type(d) == "table" and d.noeuds and d.noeuds[carte] or {}) do
        table.insert(liste, { x = l[1], y = l[2], n = l[3] or 1, metier = l[4], nom = l[5], repere = true,
            icone = ICONES_METIER[l[4]], nomType = l[5] })
    end
    return liste
end

-- Metiers de recolte a proposer en filtre sur les cartes : ceux du
-- personnage (herboristerie 182, minage 186, peche 356), et ceux dont des
-- lieux sont deja notes.
local LIGNES_RECOLTE = { herbes = "182", minerais = "186", peche = "356" }
-- Le personnage connecte a-t-il ce metier de recolte ? Sans lui, ni filtre
-- ni lieux de ce metier sur les cartes.
_G.CraftCoreAPI.ARecolte = function(metier)
    local fiche = NS.base.Personnage and NS.base.Personnage()
    local siens = fiche and type(fiche.metiers) == "table" and fiche.metiers
    return siens and siens[LIGNES_RECOLTE[metier] or ""] ~= nil or false
end
_G.CraftCoreAPI.MetierDeRecolte = function(metier) return _G.CraftCoreAPI.ARecolte(metier) end
_G.CraftCoreAPI.Objet = function(objet)
    if type(objet) == "string" then return nil end
    return NS.inventaire.NomDObjet(objet), NS.Appeler(NS.jeu.iconeObjet, objet)
end

-- ---------------------------------------------------------------------------
-- Guidage vers ce qui manque : parmi les matieres qui manquent encore aux
-- objectifs suivis, les lieux ou on les a deja recoltees (tous personnages) ;
-- la fleche de la suite mene au plus proche, puis au plus proche suivant.
-- Un lieu atteint est compte comme visite pour la session ; tous visites,
-- on recommence (les noeuds repoussent).
-- ---------------------------------------------------------------------------

local visites = {}
local cacheManques = { quand = -100 }

-- Lieux { carte, x, y, objet, cle } des matieres qui manquent.
function suivi.LieuxManquants(objectifs)
    local manques = {}
    for _, o in ipairs(objectifs or {}) do
        for _, m in ipairs(o.matieres or {}) do
            if (m.manque or 0) > 0 then manques[m.objet] = true end
        end
    end
    local liste = {}
    local d = CraftCoreDB
    for objet in pairs(manques) do
        for carte, lieux in pairs(type(d) == "table" and d.lieux and d.lieux[objet] or {}) do
            for _, l in ipairs(lieux) do
                table.insert(liste, { carte = carte, x = l[1], y = l[2], objet = objet,
                    cle = objet .. ":" .. carte .. ":" .. l[1] .. ":" .. l[2] })
            end
        end
    end
    return liste
end

local function Monde(carte, x, y)
    local f, V = NS.Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if not (f and V) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        return a, b, continent
    end
    return nil
end

-- La fleche demande sa cible vingt fois par seconde : le lieu vise n'est
-- recherche que toutes les 4 secondes (ou des qu'il est atteint).
local cibleRecolte, cibleRecolteQuand = nil, -100
local fournisseurRecolte
local function ChercherCible()
        local maintenant = NS.Appeler(GetTime) or 0
        -- Les objectifs se recalculent toutes les 5 secondes, pas plus.
        if maintenant - cacheManques.quand > 5 then
            cacheManques.quand = maintenant
            cacheManques.lieux = suivi.LieuxManquants(suivi.Objectifs())
        end
        local lieux = cacheManques.lieux or {}
        if #lieux == 0 then return nil, "fini" end
        local carteJ = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
        local pos = carteJ and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carteJ, "player")
        local jx, jy, jc
        if type(pos) == "table" and pos.GetXY then jx, jy, jc = Monde(carteJ, pos:GetXY()) end
        local function Chercher()
            local meilleur, cible
            for _, l in ipairs(lieux) do
                if not visites[l.cle] then
                    local x, y, c = Monde(l.carte, l.x, l.y)
                    if x and jx and c == jc then
                        local dist = (x - jx) ^ 2 + (y - jy) ^ 2
                        if not meilleur or dist < meilleur then meilleur, cible = dist, l end
                    end
                end
            end
            return cible
        end
        local cible = Chercher()
        if not cible then
            visites = {}
            cible = Chercher()
        end
        if not cible then return nil end
        local nom = NS.inventaire.NomDObjet(cible.objet)
        return { carte = cible.carte, x = cible.x, y = cible.y, qui = nom, cle = cible.cle,
            titre = NS.L.GUIDE_GOALS_TITLE }
end
fournisseurRecolte = {
    Cible = function()
        local maintenant = NS.Appeler(GetTime) or 0
        if maintenant - cibleRecolteQuand < 4 then return cibleRecolte end
        local c, raison = ChercherCible()
        if raison then return nil, raison end
        cibleRecolte, cibleRecolteQuand = c, maintenant
        return c
    end,
    Arrivee = function(cible)
        if cible.cle and not visites[cible.cle] then visites[cible.cle] = true end
        cibleRecolteQuand = -100
    end,
    Fin = function() if suivi.Dessiner then pcall(suivi.Dessiner) end end,
}

-- Pour la vue d'ensemble de MapCore : le circuit de recolte (lieux connus
-- des matieres qui manquent), et son guidage.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
_G.CraftCoreAPI.CircuitRecolte = function()
    local ok, objectifs = pcall(suivi.Objectifs)
    local lieux = ok and suivi.LieuxManquants(objectifs) or {}
    if #lieux == 0 then return nil end
    local matieres = {}
    for _, l in ipairs(lieux) do matieres[l.objet] = true end
    local n = 0
    for _ in pairs(matieres) do n = n + 1 end
    return { lieux = #lieux, matieres = n, guide = suivi.EnGuidage() }
end
_G.CraftCoreAPI.GuiderRecolte = function(oui) return suivi.Guider(oui) end

function suivi.EnGuidage()
    local S = NS.suite or _G.CoreSuite
    return S and S.GuidageActif and S.GuidageActif("CraftCore") or false
end

function suivi.Guider(oui)
    if NS.Trace then NS.Trace("guidage recolte : " .. tostring(oui)) end
    local S = NS.suite or _G.CoreSuite
    if not (S and S.Guider) then return end
    if oui == nil then oui = not suivi.EnGuidage() end
    if oui then
        visites = {}
        cacheManques.quand = -100
        cibleRecolteQuand = -100
        if NS.marchands and NS.marchands.OterDrapeau then pcall(NS.marchands.OterDrapeau) end
        S.Guider("CraftCore", fournisseurRecolte)
    else
        S.ArreterGuidage("CraftCore")
    end
    pcall(suivi.Dessiner)
end


-- ---------------------------------------------------------------------------
-- Annonce : un projet (ou un rang vise) arrive a 100 %. Le meme bandeau que
-- l'avancement des quetes de QuestCore (memes reglages, meme place) ; sans
-- QuestCore, un message en haut de l'ecran et dans la discussion.
-- ---------------------------------------------------------------------------

local etatsAnnonce, premierPassage = {}, true
local function Annoncer(titre, detail, detail2)
    if NS.Trace then NS.Trace("annonce : " .. tostring(titre)) end
    local qc = _G.QuestCoreAPI
    if qc and qc.Bandeau then
        local ok, montre = pcall(qc.Bandeau, titre, detail, true, detail2)
        if ok and montre then return end
    end
    local texte = titre .. " : " .. detail .. (detail2 and (". " .. detail2) or "")
    if _G.UIErrorsFrame then pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, texte, 1, 0.82, 0) end
    NS.Dire(texte)
end

local resumesAnnonce = {}
local function Verifier()
    local L = NS.L
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return end
    local vus = {}
    local function Vendu(objet)
        local r = NS.recettes
        if not (r and r.EstVenduPartout) then return false end
        local okV, oui = pcall(r.EstVenduPartout, objet)
        return okV and oui == true
    end
    local function Liste(matieres)
        local t = {}
        for k, m in ipairs(matieres) do
            if k > 3 then t[#t + 1] = "..." break end
            t[#t + 1] = string.format("%s x%d", NS.inventaire.NomDObjet(m.objet) or ("#" .. tostring(m.objet)), m.manque)
        end
        return table.concat(t, ", ")
    end
    for _, o in ipairs(objectifs or {}) do
        -- Ce qui manque encore : a acheter chez un marchand, a recolter
        -- (herbes, minerais), ou autre chose (butin, fabrication...).
        local aAcheter, autres, recoltables, recoltesManquantes = {}, {}, 0, 0
        for _, m in ipairs(o.matieres or {}) do
            local recolte = MetierDeMatiere(m.objet) ~= nil
            if recolte then
                recoltables = recoltables + 1
                if (m.manque or 0) > 0 then recoltesManquantes = recoltesManquantes + 1 end
            end
            if (m.manque or 0) > 0 then
                if Vendu(m.objet) then table.insert(aAcheter, m)
                elseif not recolte then table.insert(autres, m) end
            end
        end
        local etat = "encours"
        if o.atteint then etat = "atteint"
        elseif (o.pct or 0) >= 1 then etat = "reuni"
        elseif recoltesManquantes == 0 and #autres == 0 and #aAcheter > 0 then etat = "achats"
        elseif recoltables > 0 and recoltesManquantes == 0 and #autres > 0 then etat = "recolte" end
        local avant = etatsAnnonce[o.cle]
        vus[o.cle] = true
        etatsAnnonce[o.cle] = etat
        local titre = (o.genre == "projet" and not o.rapides) and string.format(L.ANNOUNCE_PROJECT, o.titreAnnonce or o.nom) or o.nom
        resumesAnnonce[o.cle] = { titre = o.commande and o.nom or titre,
            felicitation = (o.commande and L.ANNOUNCE_DONE_ORDER) or (o.groupe == "progression" and L.ANNOUNCE_DONE_PROG) or L.ANNOUNCE_DONE_PROJECT,
            quoi = #(o.fabriquer or {}) > 0 and table.concat(o.fabriquer, ", ") or nil }
        if not premierPassage and avant and avant ~= etat and (etat == "achats" or etat == "recolte") then
            Annoncer(titre, L.ANNOUNCE_GATHERED, string.format(etat == "achats" and L.ANNOUNCE_BUY or L.ANNOUNCE_LEFT,
                Liste(etat == "achats" and aAcheter or autres)))
        elseif not premierPassage and avant and avant ~= etat and etat ~= "encours" then
            if o.genre == "projet" then
                local quoi = #(o.fabriquer or {}) > 0 and table.concat(o.fabriquer, ", ")
                    .. (((o.nLignes or 0) > #o.fabriquer) and ", ..." or "") or nil
                Annoncer(o.rapides and o.nom or string.format(L.ANNOUNCE_PROJECT, o.titreAnnonce or o.nom), L.ANNOUNCE_100,
                    quoi and string.format(L.ANNOUNCE_CRAFT, quoi) or L.ANNOUNCE_CRAFT_ANY)
            elseif o.genre == "progression" then
                if etat == "atteint" then
                    Annoncer(o.nom, L.ANNOUNCE_RANK_DONE, nil)
                elseif avant == "encours" then
                    Annoncer(o.nom, L.ANNOUNCE_100, L.ANNOUNCE_RANK_GO)
                end
            end
        end
    end
    -- Un objectif tout juste fabrique disparait du suivi : bravo, au milieu
    -- de l'ecran, avec ce qui a ete fait. Seulement juste apres une
    -- fabrication (pas quand on supprime un projet a la main).
    local recent = NS.actions and NS.actions.derniereFabrication
        and ((NS.Appeler(GetTime) or 0) - NS.actions.derniereFabrication) < 30
    for cle in pairs(etatsAnnonce) do
        if not vus[cle] then
            local r = resumesAnnonce[cle]
            if recent and r and etatsAnnonce[cle] == "reuni" then
                Annoncer(r.titre, r.felicitation, r.quoi and string.format(L.ANNOUNCE_MADE, r.quoi) or nil)
            end
            etatsAnnonce[cle] = nil
            resumesAnnonce[cle] = nil
        end
    end
    premierPassage = false
end

local ecouteAnnonce = CreateFrame("Frame")
local annonceDans
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(ecouteAnnonce.RegisterEvent, ecouteAnnonce, e)
end
-- Au plus une verification toutes les 2 secondes (le sac change souvent).
ecouteAnnonce:SetScript("OnEvent", function() annonceDans = annonceDans or 2 end)
ecouteAnnonce:SetScript("OnUpdate", function(_, ecoule)
    if not annonceDans then return end
    annonceDans = annonceDans - (ecoule or 0)
    if annonceDans > 0 then return end
    annonceDans = nil
    local okV, souci = pcall(Verifier)
    if not okV and NS.base.NoterIncident then NS.base.NoterIncident("annonce d'objectif", souci) end
end)
suivi.VerifierAnnonces = Verifier

-- Pour les raccourcis de la suite : montrer ou cacher le suivi de mes
-- fabrications, et ouvrir la page Monter un metier.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
_G.CraftCoreAPI.BasculerSuivi = function()
    local cadre = _G.CraftCoreSuivi
    if cadre and cadre:IsShown() then cadre:Hide() else suivi.Montrer() end
end
_G.CraftCoreAPI.MonterUnMetier = function() if NS.ecran then NS.ecran.Montrer("progression") end end
