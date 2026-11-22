local _, NS = ...

-- La fenetre de PvPCore, comme celles de la suite (menu a gauche). Seul,
-- PvPCore a la meme fenetre, avec une page pour faire connaitre la suite.

NS.fenetre = {}
local F = NS.fenetre
local T = NS.T
local function R() return NS.carte.Reglages() end
local O_RETRAIT = 16
local function Pct(v) return string.format("%d %%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end

-- Page des rubriques (rang, victoires, files, champ en cours, quetes JcJ) :
-- un titre de section par rubrique (meme police et meme filet que les autres
-- pages), puis ses lignes, libelle a gauche, valeur a droite. Disposees a
-- chaque ouverture : aucun trou quand une rubrique manque.
local function PageHonneur()
    return { cle = "honneur", icone = "Interface\\Icons\\INV_BannerPVP_02",
        libelle = function() return T("Honneur", "Honour") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(40)
            page.zone = O.Rangee(900)
            page.titres, page.lignes = {}, {}
        end,
        rendre = function(page)
            page.t1:SetText(T("Votre JcJ", "Your PvP"))
            page.intro:SetText(T("Rang, victoires honorables, files d'attente, champ de bataille en cours et quêtes JcJ, lus à l'ouverture de la page.",
                "Rank, honourable kills, queues, current battleground and PvP quests, read when the page opens."))
            local zone = page.zone
            local largeur = zone:GetWidth() or 500
            for _, t in ipairs(page.titres) do t.fs:Hide() t.filet:Hide() end
            for _, l in ipairs(page.lignes) do l.nom:Hide() l.valeur:Hide() end
            local y, nT, nL = 0, 0, 0
            for k, x in ipairs(NS.honneur.Rubriques()) do
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
                        page.lignes[nL] = l
                    end
                    l.nom:ClearAllPoints()
                    l.nom:SetPoint("TOPLEFT", zone, "TOPLEFT", O_RETRAIT, -y)
                    l.nom:SetPoint("RIGHT", zone, "RIGHT", -170, 0)
                    l.valeur:ClearAllPoints()
                    l.valeur:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -10, -y)
                    l.nom:SetText(e.texte or "")
                    l.valeur:SetText(e.droite or "")
                    local c = e.couleur or { 1, 1, 1 }
                    l.nom:SetTextColor(c[1], c[2], c[3])
                    l.nom:Show() l.valeur:Show()
                    y = y + 20
                end
            end
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
    local pages = { PageHonneur(), PageCarte() }
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
