local _, NS = ...

-- La fenetre de PvPCore, comme celles de la suite (menu a gauche). Seul,
-- PvPCore a la meme fenetre, avec une page pour faire connaitre la suite.

NS.fenetre = {}
local F = NS.fenetre
local T = NS.T
local function R() return NS.carte.Reglages() end
local O_RETRAIT = 16
local function Pct(v) return string.format("%d %%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end

-- Des rubriques ({ titre, lignes }) disposees dans une zone de page : un
-- titre de section par rubrique (meme police et meme filet que les autres
-- pages), puis ses lignes, libelle a gauche, valeur a droite. Disposees a
-- chaque ouverture : aucun trou quand une rubrique manque.
local function RendreRubriques(page, rubriques)
    local zone = page.zone
    local largeur = zone:GetWidth() or 500
    for _, t in ipairs(page.titres) do t.fs:Hide() t.filet:Hide() end
    for _, l in ipairs(page.lignes) do l.nom:Hide() l.valeur:Hide() end
    local y, nT, nL = 0, 0, 0
    for k, x in ipairs(rubriques) do
        if k > 1 then y = y + 8 end
        nT = nT + 1
        local t = page.titres[nT]
        if not t then
            t = { fs = zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = zone:CreateTexture(nil, "ARTWORK") }
            t.fs:SetJustifyH("LEFT")
            page.titres[nT] = t
        end
        t.fs:ClearAllPoints()
        t.fs:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
        t.fs:SetText(x.titre)
        t.filet:ClearAllPoints()
        t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
        t.filet:SetSize(largeur, 1)
        if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet)
        else t.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
        t.fs:Show() t.filet:Show()
        y = y + 34
        for _, e in ipairs(x.lignes) do
            nL = nL + 1
            local l = page.lignes[nL]
            if not l then
                l = { nom = zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                      valeur = zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
                l.nom:SetJustifyH("LEFT")
                l.nom:SetWordWrap(false)
                l.valeur:SetJustifyH("RIGHT")
                l.valeur:SetWordWrap(false)
                page.lignes[nL] = l
            end
            l.nom:ClearAllPoints()
            l.nom:SetPoint("TOPLEFT", zone, "TOPLEFT", O_RETRAIT, -y)
            l.nom:SetPoint("RIGHT", zone, "RIGHT", -360, 0)
            l.valeur:ClearAllPoints()
            l.valeur:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -10, -y)
            l.valeur:SetWidth(340)
            l.nom:SetText(e.texte or "")
            l.valeur:SetText(e.droite or "")
            local c = e.couleur or { 1, 1, 1 }
            l.nom:SetTextColor(c[1], c[2], c[3])
            l.nom:Show() l.valeur:Show()
            y = y + 20
        end
    end
    return y
end

-- Une page de rubriques (honneur, parties), lues a l'ouverture de la page.
local function PageRubriques(cle, icone, libelle, titre, intro, rubriques)
    return { cle = cle, icone = icone, libelle = libelle,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(40)
            page.zone = O.Rangee(20)
            -- Haut de la zone : la page prend la hauteur de ses rubriques.
            page.yZone = page.y - 20
            page.titres, page.lignes = {}, {}
        end,
        rendre = function(page)
            page.t1:SetText(titre())
            page.intro:SetText(intro())
            local h = RendreRubriques(page, rubriques())
            page.zone:SetHeight(math.max(h, 20))
            page.hauteur = page.yZone + math.max(h, 20)
        end }
end

local function PageHonneur()
    return PageRubriques("honneur", "Interface\\Icons\\INV_BannerPVP_02",
        function() return T("Honneur", "Honour") end,
        function() return T("Votre JcJ", "Your PvP") end,
        function() return T("Rang, honneur du jour et objectif de la semaine, cibles du jour, files d'attente, champ de bataille en cours et quêtes JcJ.",
            "Rank, today's honour and weekly goal, today's targets, queues, current battleground and PvP quests.") end,
        function() return NS.honneur.Rubriques() end)
end

local function PageParties()
    return PageRubriques("parties", "Interface\\Icons\\INV_Misc_Note_02",
        function() return T("Parties", "Matches") end,
        function() return T("Vos parties", "Your matches") end,
        function() return T("Chaque champ de bataille terminé : victoire ou défaite, durée, victoires honorables (VH), coups de grâce (CG) et honneur gagné.",
            "Each finished battleground : victory or defeat, length, honourable kills (HK), killing blows (KB) and honour gained.") end,
        function() return NS.parties.Rubriques() end)
end

-- Les reglages du suivi : objectif de la semaine, infobulle, resume.
local function PageReglages()
    local function V() return NS.victoires end
    return { cle = "reglages", icone = "Interface\\Icons\\INV_Misc_Gear_01",
        libelle = function() return T("Réglages", "Settings") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(40)
            page.sObjectif = O.Section()
            page.rObjectif = O.Rangee()
            -- La valeur entre fleches simples (1) et doubles (5), comme la suite.
            local S = _G.CoreSuite
            local c = S.Curseur(page.rObjectif, 0, 999, 1, function() return V().Objectif() end,
                function(v) V().PoserObjectif(v) end, function(v) return tostring(math.floor(v)) end, true, 5)
            c:SetPoint("RIGHT", page.rObjectif, "RIGHT", -10, 0)
            c.surParchemin = function() return NS.charte and NS.charte.Fond and NS.charte.Fond() == "parchemin" end
            for _, b in ipairs(c.boutonsPM or {}) do table.insert(page.focus, b) end
            table.insert(page.controles, c)
            page.dObjectif = O.Detail(28)
            page.sInfobulle = O.Section()
            page.rInfobulle = O.Rangee()
            page.cInfobulle = O.Case(page.rInfobulle, function(oui) V().Reglages().infobulle = oui and true or false end)
            page.cInfobulle:SetPoint("RIGHT", page.rInfobulle, "RIGHT", -8, 0)
            page.dInfobulle = O.Detail(28)
            page.sFiles = O.Section()
            page.rFiles = O.Rangee()
            page.cFiles = O.Case(page.rFiles, function(oui) V().Reglages().files = oui and true or false end)
            page.cFiles:SetPoint("RIGHT", page.rFiles, "RIGHT", -8, 0)
            page.dFiles = O.Detail(28)
            page.sFin = O.Section()
            page.rResume = O.Rangee()
            page.cResume = O.Case(page.rResume, function(oui) V().Reglages().resume = oui and true or false end)
            page.cResume:SetPoint("RIGHT", page.rResume, "RIGHT", -8, 0)
        end,
        rendre = function(page)
            page.t1:SetText(T("Réglages du suivi JcJ", "PvP tracking settings"))
            page.intro:SetText(T("Ce que PvPCore lit pour vous : honneur de la journée, rendement décroissant de chaque cible et résultat de vos parties.",
                "What PvPCore reads for you : today's honour, diminishing returns of each target and the result of your matches."))
            page.sObjectif:SetText(T("Objectif de la semaine", "Weekly goal"))
            page.rObjectif.nom:SetText(T("Honneur visé, en milliers (0 : aucun)", "Target honour, in thousands (0 : none)"))
            page.dObjectif:SetText(T("Suivi dans la page Honneur et dans l'onglet JcJ du suivi des quêtes, avec les 15 victoires pour être classé.",
                "Shown on the Honour page and in the quest tracker's PvP tab, with the 15 kills needed to be ranked."))
            page.sInfobulle:SetText(T("Victoires honorables", "Honourable kills"))
            page.rInfobulle.nom:SetText(T("Victoires du jour dans l'infobulle des adversaires", "Today's kills in enemy player tooltips"))
            page.cInfobulle:SetChecked(V().Reglages().infobulle ~= false)
            page.dInfobulle:SetText(T("Même cible le même jour : 100, 75, 50, 25 puis 0 % de l'honneur.",
                "Same target on the same day : 100, 75, 50, 25 then 0 % of the honour."))
            page.sFiles:SetText(T("Files d'attente", "Queues"))
            page.rFiles.nom:SetText(T("Avertir quand un champ de bataille est prêt", "Warn when a battleground is ready"))
            page.cFiles:SetChecked(V().Reglages().files ~= false)
            page.dFiles:SetText(T("Le temps pour entrer dans votre discussion, puis un rappel sonore 15 secondes avant la fin.",
                "The time left to enter in your chat, then a sound 15 seconds before it runs out."))
            page.sFin:SetText(T("Fin de partie", "End of match"))
            page.rResume.nom:SetText(T("Résumé de la partie dans votre discussion (vous seul)", "Match summary in your chat (only you)"))
            page.cResume:SetChecked(V().Reglages().resume ~= false)
        end }
end

local function PageCarte()
    return { cle = "carte", icone = "Interface\\Icons\\INV_Misc_Map_01",
        libelle = function() return T("La carte", "The map") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(40)
            page.sAffichage = O.Section()
            page.rVoir = O.Rangee()
            page.cVoir = O.Case(page.rVoir, function(oui) R().affichee = oui and true or false end)
            page.cVoir:SetPoint("RIGHT", page.rVoir, "RIGHT", -8, 0)
            page.rPartout = O.Rangee()
            page.cPartout = O.Case(page.rPartout, function(oui) R().partout = oui and true or false end)
            page.cPartout:SetPoint("RIGHT", page.rPartout, "RIGHT", -8, 0)
            page.rVerrou = O.Rangee()
            page.cVerrou = O.Case(page.rVerrou, function(oui) R().verrouillee = oui and true or false end)
            page.cVerrou:SetPoint("RIGHT", page.rVerrou, "RIGHT", -8, 0)
            page.rTaille = O.Rangee()
            O.Curseur(page.rTaille, 150, 600, 10, function() return R().taille end, function(v) R().taille = v end, nil, true)
            page.rCentre = O.Rangee()
            page.bCentre = O.Bouton(page.rCentre, 120, function() NS.carte.Recentrer() end)
            page.bCentre:SetPoint("RIGHT", page.rCentre, "RIGHT", -8, 0)
            page.sTransparence = O.Section()
            page.rMarche = O.Rangee()
            O.Curseur(page.rMarche, 0, 1, 0.05, function() return R().alphaMarche end, function(v) R().alphaMarche = v end, Pct, true)
            page.rArret = O.Rangee()
            O.Curseur(page.rArret, 0, 1, 0.05, function() return R().alphaArret end, function(v) R().alphaArret = v end, Pct, true)
            page.sSous = O.Section()
            page.rObjectifs = O.Rangee()
            page.cObjectifs = O.Case(page.rObjectifs, function(oui) R().objectifs = oui and true or false end)
            page.cObjectifs:SetPoint("RIGHT", page.rObjectifs, "RIGHT", -8, 0)
            page.rPorteurs = O.Rangee()
            page.cPorteurs = O.Case(page.rPorteurs, function(oui) R().porteurs = oui and true or false end)
            page.cPorteurs:SetPoint("RIGHT", page.rPorteurs, "RIGHT", -8, 0)
            page.rMinuteurs = O.Rangee()
            page.cMinuteurs = O.Case(page.rMinuteurs, function(oui) R().minuteurs = oui and true or false end)
            page.cMinuteurs:SetPoint("RIGHT", page.rMinuteurs, "RIGHT", -8, 0)
            page.aide = O.Detail(44)
        end,
        rendre = function(page)
            page.t1:SetText(T("La carte de champ de bataille", "The battleground map"))
            page.intro:SetText(T("Une petite carte à placer où vous voulez : votre groupe à la couleur de sa classe, vous en flèche, les bases et les tours du champ de bataille.",
                "A small map you place anywhere : your group in its class colour, you as an arrow, the battleground's bases and towers."))
            page.sAffichage:SetText(T("Affichage", "Display"))
            page.rVoir.nom:SetText(T("Afficher la carte en champ de bataille", "Show the map in battlegrounds"))
            page.cVoir:SetChecked(R().affichee ~= false)
            page.rPartout.nom:SetText(T("L'afficher aussi hors des champs de bataille", "Also show it outside battlegrounds"))
            page.cPartout:SetChecked(R().partout == true)
            page.rVerrou.nom:SetText(T("Verrouiller (les clics passent au travers)", "Lock (clicks go through)"))
            page.cVerrou:SetChecked(R().verrouillee == true)
            page.rTaille.nom:SetText(T("Largeur", "Width"))
            page.rCentre.nom:SetText(T("Position", "Position"))
            page.bCentre:SetText(T("Recentrer", "Recenter"))
            page.sTransparence:SetText(T("Transparence", "Transparency"))
            page.rMarche.nom:SetText(T("Opacité en mouvement", "Opacity while moving"))
            page.rArret.nom:SetText(T("Opacité à l'arrêt", "Opacity when stopped"))
            page.sSous:SetText(T("Sous la carte", "Below the map"))
            page.rObjectifs.nom:SetText(T("Objectifs et fin estimée des ressources", "Objectives and estimated end of resources"))
            page.cObjectifs:SetChecked(R().objectifs ~= false)
            page.rPorteurs.nom:SetText(T("Porteurs de drapeau", "Flag carriers"))
            page.cPorteurs:SetChecked(R().porteurs ~= false)
            page.rMinuteurs.nom:SetText(T("Minuteurs : début de partie, bases et tours", "Timers : match start, bases and towers"))
            page.cMinuteurs:SetChecked(R().minuteurs ~= false)
            page.aide:SetText(T("Deux raccourcis (Options, Raccourcis, PvPCore) : carte entièrement visible, ou cachée. Un second appui revient au réglage.",
                "Two key bindings (Options, Key Bindings, PvPCore) : map fully visible, or hidden. Pressing again goes back to settings."))
        end }
end

-- La page de la suite complete (PvPCore installe seul).
local ADRESSE_SUITE = "https://www.curseforge.com/projects/1817365"
local function PageSuite()
    return { cle = "suite", icone = "Interface\\Icons\\INV_Misc_Book_11",
        libelle = function() return T("La suite", "The suite") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(70)
            page.t2 = O.Texte(20)
            page.rLien = O.Rangee(28)
            local e = CreateFrame("EditBox", nil, page.rLien, "InputBoxTemplate")
            e:SetSize(420, 24)
            e:SetPoint("LEFT", page.rLien, "LEFT", 6, 0)
            e:SetAutoFocus(false)
            e:SetText(ADRESSE_SUITE)
            e:SetCursorPosition(0)
            e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            e:SetScript("OnTextChanged", function(self, parUtilisateur)
                if parUtilisateur then self:SetText(ADRESSE_SUITE) self:HighlightText() end
            end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            table.insert(page.focus, e)
            page.aide = O.Detail(30)
        end,
        rendre = function(page)
            page.t1:SetText("Forever SagaCore")
            page.intro:SetText(T("PvPCore fait partie de Forever SagaCore, une suite d'add-ons pour WoW Forever : fabrications et métiers (CraftCore), quêtes et trajets (QuestCore), carte et services (MapCore), héritage (LegacyCore). Installés ensemble, ils partagent la même fenêtre, les mêmes réglages et la même manette.",
                "PvPCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."))
            page.t2:SetText(T("Retrouvez la suite complète sur CurseForge :", "Get the complete suite on CurseForge :"))
            page.rLien.nom:SetText("")
            page.aide:SetText(T("Cliquez sur l'adresse, puis Ctrl+C (Cmd+C sur Mac) pour la copier.", "Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."))
        end }
end

function F.Construire()
    local S = _G.CoreSuite
    if F.w or not (S and S.FenetreAPages) then return F.w end
    local pages = { PageHonneur(), PageParties(), PageCarte(), PageReglages() }
    if S.Seul and S.Seul() then table.insert(pages, PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "PvPCoreFenetre", cle = "PvPCore", icone = "Interface\\Icons\\INV_BannerPVP_02",
        titre = function() return "PvPCore" end,
        pages = pages,
    })
    return F.w
end

function F.Ouvrir()
    local S = _G.CoreSuite
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("PvPCore") return true end
    return false
end
