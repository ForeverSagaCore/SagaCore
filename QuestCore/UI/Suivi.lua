local _, NS = ...

-- Suivi des quetes : un panneau leger a la maniere du suivi d'objectifs du
-- jeu, pour le personnage connecte. Deplacable par son titre, redimensionnable
-- par son coin, repliable, et la molette le fait defiler. Sous chaque objet a
-- rapporter, il dit si un autre de vos personnages en detient deja.

NS.suivi = {}
local suivi = NS.suivi
local L = NS.L

local LARGEUR, HAUTEUR = 300, 320
-- Hauteur la plus petite d'un suivi deplie : onglets, boutons et quelques lignes.
local HAUTEUR_MINI = 180
local HAUTEUR_TITRE = 28
local HAUTEUR_REPLIE = 100
local cadre
local PoserOngletsVues
local CategorieDe, TourneeRecolte

local function Reglages()
    local g = NS.base.ReglagesGeneraux()
    g.suivi = g.suivi or {}
    local s = g.suivi
    if s.afficher == nil then s.afficher = true end
    s.replies = s.replies or {}
    s.sections = s.sections or {}
    -- Hauteur reduite par l'ancienne borne (suivi pose en bas d'ecran) : une
    -- fois, on revient a la hauteur normale.
    if not s.hauteurRetablie then
        if type(s.hauteur) == "number" and s.hauteur < 260 then s.hauteur = nil end
        s.hauteurRetablie = true
    end
    if s.regroupement ~= "etat" then s.regroupement = "zone" end
    -- Reglages d'affichage, avec leurs valeurs par defaut.
    if type(s.taille) ~= "number" then s.taille = 12 end
    if type(s.alphaRepos) ~= "number" then s.alphaRepos = 1 end
    if type(s.alphaMouvement) ~= "number" then s.alphaMouvement = 0.15 end
    if type(s.alphaSurvol) ~= "number" then s.alphaSurvol = 1 end
    if s.modeRepos ~= "survol" then s.modeRepos = "visible" end
    if s.modeCombat ~= "estompe" and s.modeCombat ~= "cache" then s.modeCombat = "normal" end
    if s.souder ~= true then s.souder = false end
    -- Soudes, les quetes sont toujours en haut et la recolte dessous.
    s.ordre = "quetes"
    if s.vue ~= "parcours" and s.vue ~= "favoris" and s.vue ~= "pvp" then s.vue = "quetes" end
    if s.memeOpacite == nil then s.memeOpacite = true end
    if s.masquerNatif ~= true then s.masquerNatif = false end
    -- Quete terminee : par defaut, elle quitte l'onglet Quetes pour ne plus
    -- etre que dans A rendre ; au choix, elle reste aussi dans Quetes.
    if s.termineesDansQuetes ~= true then s.termineesDansQuetes = false end
    -- L'ancienne selection, commune au compte : remplacee par la selection de
    -- chaque onglet, propre au personnage (Selection).
    s.aRendreChoisies = nil
    return s
end

-- Quetes cochees (petite carte sur leur ligne), propres au personnage et a
-- l'onglet : "quetes" ou "favoris". Le bouton Guider de l'onglet guide
-- exactement celles-la.
local function Selection(onglet)
    local cle = NS.ClePersonnage()
    local d = QuestCoreDB
    if not cle or type(d) ~= "table" then return {} end
    d.choix = type(d.choix) == "table" and d.choix or {}
    local c = type(d.choix[cle]) == "table" and d.choix[cle] or {}
    d.choix[cle] = c
    c[onglet] = type(c[onglet]) == "table" and c[onglet] or {}
    return c[onglet]
end
suivi.Selection = Selection

-- L'onglet dont on coche les quetes : Quetes ou Favoris (ni A rendre, ni
-- Itineraire, ni JcJ, ni un membre du groupe).
local function OngletDeSelection()
    local s = Reglages()
    if s.vuePerso then return nil end
    if s.vue == "favoris" then return "favoris" end
    if s.vue == "quetes" and not NS.base.FiltreARendre() then return "quetes" end
    return nil
end
suivi.OngletDeSelection = OngletDeSelection

-- L'objectif du bouton Guider de l'onglet affiche : le type et ses
-- parametres, ou nil (rien a guider ici).
local function ObjectifDeLOnglet()
    local s = Reglages()
    if s.vuePerso or s.vue == "parcours" or s.vue == "pvp" then return nil end
    if s.vue ~= "favoris" and NS.base.FiltreARendre() then return "rendus", {} end
    local ids = {}
    for id in pairs(Selection(OngletDeSelection() or "quetes")) do table.insert(ids, id) end
    table.sort(ids)
    if #ids == 0 then return nil end
    return "quetes", { ids = ids }
end
suivi.ObjectifDeLOnglet = ObjectifDeLOnglet

local RendreVueParcours
local TRIS, Difficulte
local HAUT_ONGLETS = 38
local HauteurMaxi

local function Police(nom, repli)
    return _G[nom] and nom or repli
end

suivi.Reglages = Reglages


-- ---------------------------------------------------------------------------
-- Lignes
-- ---------------------------------------------------------------------------

local function Ligne(index)
    local corps = cadre.corps
    corps.lignes = corps.lignes or {}
    local l = corps.lignes[index]
    if l then return l end
    l = CreateFrame("Button", nil, corps)
    pcall(l.RegisterForClicks, l, "LeftButtonUp", "RightButtonUp")
    -- Surbrillance de la ligne (souris ou manette) : la barre du journal de
    -- quetes du jeu.
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    -- Marque d'etat devant le titre : les icones du journal de quetes du jeu
    -- (rond a trois points en cours, rond au point d'interrogation a rendre).
    l.marque = l:CreateTexture(nil, "ARTWORK")
    l.marque:SetSize(16, 16)
    l.marque:SetPoint("TOPLEFT", l, "TOPLEFT", 2, 1)
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, 0)
    l.droite:SetJustifyH("RIGHT")
    l.filet = l:CreateTexture(nil, "ARTWORK")
    l.filet:SetHeight(1)
    l.filet:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, -2)
    l.filet:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, -2)
    l.filet:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    -- Separateur fin, au-dessus d'un en-tete de zone (pas le premier), avec de
    -- l'air de part et d'autre.
    l.separateur = l:CreateTexture(nil, "ARTWORK")
    l.separateur:SetHeight(1)
    l.separateur:SetPoint("BOTTOMLEFT", l, "TOPLEFT", 0, 7)
    l.separateur:SetPoint("BOTTOMRIGHT", l, "TOPRIGHT", 0, 7)
    l.separateur:SetColorTexture(0.8, 0.65, 0.35, 0.35)
    l.separateur:Hide()
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    l.texte:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, 0)
    l.texte:SetJustifyH("LEFT")
    l.texte:SetWordWrap(true)
    -- Etoile de favori, a droite du titre d'une quete : l'etoile des marques
    -- de cible du jeu, en couleur quand la quete est en favori, grise sinon.
    l.etoile = CreateFrame("Button", nil, l)
    l.etoile.pasPilote = true
    l.etoile:SetSize(12, 12)
    l.etoile.t = l.etoile:CreateTexture(nil, "ARTWORK")
    l.etoile.t:SetAllPoints()
    -- Etoile pleine (favori) ou vide (pas encore) : celles du jeu si le
    -- client les a, sinon l'etoile des marques de cible, grisee.
    l.etoile.Poser = function(self, plein)
        local t = self.t
        local atlas = plein and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off"
        if t.SetAtlas and pcall(t.SetAtlas, t, atlas) and t:GetAtlas() then
            t:SetDesaturated(false)
            self:SetAlpha(1)
        else
            t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            t:SetDesaturated(not plein)
            self:SetAlpha(plein and 1 or 0.35)
        end
    end
    l.etoile:SetScript("OnClick", function(self) if self.auClic then self.auClic() end end)
    l.etoile:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.actif and L.FAV_REMOVE or L.FAV_ADD, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    l.etoile:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:Poser(self.actif)
    end)
    l.etoile:Hide()
    -- Petite carte au bout de la ligne "A rendre a ..." : choisir les quetes
    -- a rendre pour l'itineraire.
    -- Dans un petit rond, comme les boutons ronds du haut.
    l.pion = CreateFrame("Button", nil, l)
    l.pion.pasPilote = true
    l.pion:SetSize(18, 18)
    l.pion.fond = l.pion:CreateTexture(nil, "BACKGROUND")
    l.pion.fond:SetSize(14, 14)
    l.pion.fond:SetPoint("CENTER")
    l.pion.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    l.pion.t = l.pion:CreateTexture(nil, "ARTWORK")
    l.pion.t:SetSize(12, 12)
    l.pion.t:SetPoint("CENTER")
    l.pion.t:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    if l.pion.t.SetMask then pcall(l.pion.t.SetMask, l.pion.t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    l.pion.anneau = l.pion:CreateTexture(nil, "OVERLAY")
    l.pion.anneau:SetSize(31, 31)
    l.pion.anneau:SetPoint("TOPLEFT", l.pion, "TOPLEFT", 0, 0)
    l.pion.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    l.pion:SetScript("OnClick", function(self) if self.auClic then self.auClic() end end)
    l.pion:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.actif and L.ROUTE_TURNIN_REMOVE or L.ROUTE_TURNIN_ADD, 1, 0.82, 0)
        GameTooltip:AddLine(self.aide or (self.afaire and L.ROUTE_TODO_HELP or L.ROUTE_TURNIN_HELP), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    l.pion:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l.pion:Hide()
    -- A cote de la petite carte : voir la quete sur la carte de QuestCore
    -- (meme rond, une longue-vue).
    l.voir = CreateFrame("Button", nil, l)
    l.voir.pasPilote = true
    l.voir:SetSize(18, 18)
    l.voir.fond = l.voir:CreateTexture(nil, "BACKGROUND")
    l.voir.fond:SetSize(14, 14)
    l.voir.fond:SetPoint("CENTER")
    l.voir.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    l.voir.t = l.voir:CreateTexture(nil, "ARTWORK")
    l.voir.t:SetSize(12, 12)
    l.voir.t:SetPoint("CENTER")
    l.voir.t:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    if l.voir.t.SetMask then pcall(l.voir.t.SetMask, l.voir.t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    l.voir.anneau = l.voir:CreateTexture(nil, "OVERLAY")
    l.voir.anneau:SetSize(31, 31)
    l.voir.anneau:SetPoint("TOPLEFT", l.voir, "TOPLEFT", 0, 0)
    l.voir.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    l.voir:SetScript("OnClick", function(self) if self.auClic then self.auClic() end end)
    l.voir:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TURNIN_SHOW_MAP, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    l.voir:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l.voir:Hide()
    corps.lignes[index] = l
    return l
end

-- Icone d'etat d'une quete, exactement celle du journal du jeu : le jeu la
-- pose lui-meme quand il sait le faire (QuestUtil), sinon les memes images.
-- etat : true a rendre, -1 echouee, false en cours.
-- Le rond du journal de quetes du jeu, recompose a l'identique avec les memes
-- images (code du jeu, POIButton.lua) : le fond "UI-QuestPoi-QuestNumber" et,
-- dessus, "UI-QuestIcon-TurnIn-Normal" (a rendre) ou
-- "Quest-In-Progress-Icon-yellow" (en cours). Seulement des images : creer le
-- bouton du jeu lui-meme faisait bloquer l'add-on par le jeu.
local function AtlasExiste(nom)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(nom) ~= nil
end

local function RondDuJeu(ligne, etat, x, y)
    if not (AtlasExiste("UI-QuestPoi-QuestNumber")) then return nil end
    -- "fait" : le point d'interrogation du rendu, en vert (quete rendue).
    local symbole = (etat == true or etat == "fait") and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow"
    if not AtlasExiste(symbole) then return nil end
    if not ligne.rond then
        local support = CreateFrame("Frame", nil, ligne)
        support:SetSize(18, 18)
        support.fond = support:CreateTexture(nil, "ARTWORK", nil, 1)
        support.fond:SetSize(24, 24)
        support.fond:SetPoint("CENTER")
        support.symbole = support:CreateTexture(nil, "ARTWORK", nil, 2)
        support.symbole:SetSize(24, 24)
        support.symbole:SetPoint("CENTER")
        ligne.rond = support
    end
    ligne.rond:ClearAllPoints()
    ligne.rond:SetPoint("TOPLEFT", ligne, "TOPLEFT", x or 1, y or 2)
    ligne.rond.fond:SetAtlas("UI-QuestPoi-QuestNumber")
    ligne.rond.fond:SetSize(24, 24)
    ligne.rond.symbole:SetAtlas(symbole)
    ligne.rond.symbole:SetSize(24, 24)
    ligne.rond.symbole:SetDesaturated(etat == "fait" or etat == "suite")
    if etat == "fait" then ligne.rond.symbole:SetVertexColor(0.3, 1, 0.3)
    elseif etat == "suite" then ligne.rond.symbole:SetVertexColor(0.55, 0.55, 0.55)
    else ligne.rond.symbole:SetVertexColor(1, 1, 1) end
    ligne.rond.fond:SetDesaturated(etat == "suite")
    ligne.rond:Show()
    return ligne.rond
end

suivi.Rond = RondDuJeu

local function IconeDeQuete(texture, etat)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetDesaturated(false)
    if etat == "fait" then
        texture:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        texture:SetSize(16, 16)
        return
    end
    if etat == "suite" then
        texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        texture:SetDesaturated(true)
        texture:SetSize(16, 16)
        return
    end
    if etat == -1 then
        texture:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        texture:SetSize(16, 16)
        return
    end
    local util = _G.QuestUtil
    if util and util.ApplyQuestIconActiveToTexture then
        local ok = pcall(util.ApplyQuestIconActiveToTexture, texture, etat == true)
        if ok then texture:SetSize(16, 16) return end
    end
    if etat == true then
        texture:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("SideInProgressquesticon") then
        texture:SetAtlas("SideInProgressquesticon")
    else
        texture:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
    end
    texture:SetSize(16, 16)
end

suivi.Icone = IconeDeQuete

-- Couleurs du cadeau (icone grisee puis teintee). "violet" : l'icone du jeu
-- telle quelle. Le vert est reserve au don qui complete l'objectif.
local COULEURS_DON = { vert = { 0.35, 0.95, 0.4 }, bleu = { 0.45, 0.7, 1 }, orange = { 1, 0.62, 0.25 },
    rouge = { 1, 0.35, 0.35 }, jaune = { 1, 0.88, 0.3 } }
suivi.COULEURS_DON = COULEURS_DON

-- Nom d'un membre du groupe, a la couleur de sa classe.
local function NomDeMembre(nom)
    local classe = NS.groupe and NS.groupe.Classe and NS.groupe.Classe(nom)
    local c = classe and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classe]
    if c then
        return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), tostring(nom))
    end
    return "|cff66c7ff" .. tostring(nom) .. "|r"
end

-- Les membres du groupe (avec QuestCore) qui ont cette quete dans leur
-- journal : "Groupe : Paltank (en cours), Bigdheal (a rendre)". nil sinon.
-- Sert aux quetes qui ne sont pas dans mon journal (suites, prerequis,
-- quetes de donjon) ; celles de mon journal montrent deja chacun en detail.
local function TexteDuGroupe(id)
    local membres = NS.groupe and NS.groupe.Membres and NS.groupe.Membres(id) or {}
    if #membres == 0 then return nil end
    local morceaux = {}
    for _, m in ipairs(membres) do
        local etat = (m.etat == 1 and L.GROUP_STATE_DONE) or (m.etat == -1 and L.GROUP_STATE_FAILED) or L.GROUP_STATE_ON
        table.insert(morceaux, NomDeMembre(m.nom) .. " (" .. etat .. ")")
    end
    return string.format(L.TRACK_GROUP_LINE, table.concat(morceaux, ", "))
end

-- Une ligne de texte, au retrait donne, sur plusieurs lignes au besoin.
local function Poser(index, y, texte, options)
    local corps = cadre.corps
    local l = Ligne(index)
    local retrait = options.retrait or 0
    if options.separateur then y = y + 14 end
    -- Mini filet : plus fin et plus serre, sous nos objectifs, avant ceux
    -- du groupe.
    if options.miniFilet then y = y + 9 end
    l.separateur:ClearAllPoints()
    l.separateur:SetPoint("BOTTOMLEFT", l, "TOPLEFT", 0, options.miniFilet and 4 or 7)
    l.separateur:SetPoint("BOTTOMRIGHT", l, "TOPRIGHT", options.miniFilet and -40 or 0, options.miniFilet and 4 or 7)
    l.separateur:SetColorTexture(0.8, 0.65, 0.35, options.miniFilet and 0.22 or 0.35)
    l.separateur:SetShown(options.separateur == true or options.miniFilet == true)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", corps, "TOPLEFT", retrait, -y)
    l:SetPoint("RIGHT", corps, "RIGHT", -4, 0)
    l.marque:Hide()
    if l.rond then l.rond:Hide() end
    l.texte:ClearAllPoints()
    if options.marqueTexture then
        l.marque:SetTexture(options.marqueTexture)
        l.marque:SetTexCoord(0, 1, 0, 1)
        l.marque:SetSize(14, 14)
        l.marque:Show()
        l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 20, 0)
    elseif options.marque ~= nil then
        local natif = options.marque ~= -1 and RondDuJeu(l, options.marque)
        if not natif then
            IconeDeQuete(l.marque, options.marque)
            l.marque:Show()
        end
        l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 22, 0)
    else
        l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    end
    -- Etoile de favori (titres de quete).
    if options.etoile then
        l.etoile.actif, l.etoile.auClic = options.etoile.actif, options.etoile.auClic
        l.etoile:Poser(options.etoile.actif)
        l.etoile:ClearAllPoints()
        l.etoile:Show()
    else
        l.etoile:Hide()
    end
    if options.pion then
        l.pion.actif, l.pion.auClic, l.pion.afaire = options.pion.actif, options.pion.auClic, options.pion.afaire
        l.pion.aide = options.pion.aide
        l.pion.t:SetDesaturated(not options.pion.actif)
        l.pion:SetAlpha(options.pion.actif and 1 or 0.55)
        l.pion:ClearAllPoints()
        l.pion:SetPoint("RIGHT", l, "RIGHT", 0, 0)
        l.pion.anneau:SetDesaturated(not options.pion.actif)
        l.pion:Show()
    else
        l.pion:Hide()
    end
    if options.voir then
        l.voir.auClic = options.voir
        l.voir:ClearAllPoints()
        if options.pion then l.voir:SetPoint("RIGHT", l.pion, "LEFT", -2, 0)
        else l.voir:SetPoint("RIGHT", l, "RIGHT", 0, 0) end
        l.voir:Show()
    else
        l.voir:Hide()
    end
    -- Don : une petite icone de cadeau au bout d'une ligne d'objectif d'un
    -- membre ; la quantite est dans l'infobulle.
    if options.don then
        if not l.don then
            l.don = CreateFrame("Button", nil, l)
            l.don:SetSize(11, 11)
            l.don.t = l.don:CreateTexture(nil, "ARTWORK")
            l.don.t:SetAllPoints()
            l.don.t:SetTexture("Interface\\Icons\\INV_Misc_Gift_02")
            l.don.t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            l.don:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            l.don:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local d = options.don
        -- Vert : le don complète son objectif. Sinon, la couleur choisie
        -- dans les réglages pour les dons partiels (violet du jeu par défaut).
        local teinte = d.complet and COULEURS_DON.vert or COULEURS_DON[Reglages().couleurDon or "violet"]
        l.don.t:SetDesaturated(teinte ~= nil)
        if teinte then l.don.t:SetVertexColor(teinte[1], teinte[2], teinte[3])
        else l.don.t:SetVertexColor(1, 1, 1) end
        l.don:ClearAllPoints()
        l.don:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, 0)
        l.don:SetScript("OnClick", d.auClic)
        l.don:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(d.texte, 1, 0.82, 0)
            if d.aide then GameTooltip:AddLine(d.aide, 1, 1, 1, true) end
            if d.complet then GameTooltip:AddLine(L.GIVE_FULL, 0.31, 0.82, 0.41, true)
            else GameTooltip:AddLine(L.GIVE_PARTIAL, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        l.don:Show()
    elseif l.don then
        l.don:Hide()
    end
    l.droite:SetText(options.droite or "")
    if options.droite then
        local cd = options.couleurDroite or { 0.8, 0.8, 0.8 }
        l.droite:SetTextColor(cd[1], cd[2], cd[3])
    end
    if options.droite or options.etoile then
        -- Place reservee a droite (pourcentage, etoile) ; le texte s'arrete
        -- avant. Les positions verticales sont fixees apres la police.
        l.texte:SetPoint("TOPRIGHT", l, "TOPRIGHT", -40, 0)
    elseif options.don then
        l.texte:SetPoint("TOPRIGHT", l.don, "TOPLEFT", -4, -1)
    elseif options.pion or options.margeDroite then
        l.texte:SetPoint("TOPRIGHT", l, "TOPRIGHT", -(options.margeDroite or 22), 0)
    else
        l.texte:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, 0)
    end
    l.filet:SetShown(options.filet == true)
    l.texte:SetFontObject(options.police or Police("ObjectiveTrackerLineFont", "GameFontHighlightSmall"))
    -- Taille reglable dans Parametres : les titres un cran au-dessus.
    local fichier, _, drapeaux = l.texte:GetFont()
    if fichier then
        -- Hierarchie : zone (+3), titre de quete (+1), texte, detail (-1).
        local taille = Reglages().taille + (options.zone and 3 or 0) + (options.titre and 1 or 0)
            - (options.petit and 1 or 0)
        l.texte:SetFont(NS.Police(fichier), taille, drapeaux)
        local f2, _, d2 = l.droite:GetFont()
        if f2 then l.droite:SetFont(NS.Police(f2), Reglages().taille, d2) end
    end
    -- Tout ce qui borde la premiere ligne (rond, marque, pourcentage,
    -- etoile) est centre sur elle, quelle que soit la taille de police.
    local _, tailleLigne = l.texte:GetFont()
    local milieu = -math.floor((tonumber(tailleLigne) or 12) / 2 + 0.5)
    if l.rond and l.rond:IsShown() then
        l.rond:ClearAllPoints()
        l.rond:SetPoint("CENTER", l, "TOPLEFT", 10, milieu - 1)
    end
    if l.marque:IsShown() then
        l.marque:ClearAllPoints()
        l.marque:SetPoint("CENTER", l, "TOPLEFT", options.marqueTexture and 7 or 10, milieu)
    end
    l.droite:ClearAllPoints()
    l.droite:SetPoint("RIGHT", l, "TOPRIGHT", options.etoile and -18 or 0, milieu)
    if options.etoile then
        l.etoile:ClearAllPoints()
        l.etoile:SetPoint("RIGHT", l, "TOPRIGHT", 0, milieu - 1)
    end
    if options.droite or options.etoile then
        local large = (options.droite and ((l.droite:GetStringWidth() or 0) + 6) or 0) + (options.etoile and 18 or 0)
        l.texte:SetPoint("TOPRIGHT", l, "TOPRIGHT", -math.ceil(large), 0)
    end
    -- Titres sur une seule ligne, tronques ; le reste peut passer a la ligne.
    l.texte:SetWordWrap(not options.uneLigne)
    if l.texte.SetMaxLines then l.texte:SetMaxLines(options.uneLigne and 1 or 0) end
    l.texte:SetText(texte)
    local c = options.couleur or { 0.8, 0.8, 0.8 }
    l.texte:SetTextColor(c[1], c[2], c[3])
    local hauteur = math.max(12, (l.texte:GetStringHeight() or 12))
    l:SetHeight(hauteur)
    l:SetScript("OnClick", options.auClic)
    l:EnableMouse(options.auClic ~= nil)
    -- Manette : de titre de quete en titre de quete (et les zones, pour les
    -- deplier) ; seuls les titres de quete s'allument.
    l.pasPilote = not (options.titre or options.zone)
    local hl = l:GetHighlightTexture()
    if hl then hl:SetAlpha(options.titre and 1 or 0) end
    if options.auClic then
        l:SetScript("OnEnter", function(self)
            self.texte:SetTextColor(1, 1, 1)
            if options.survol then
                -- Toujours au meme endroit : contre le haut du suivi, du cote
                -- choisi (la suite place l'infobulle).
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(options.survol, GameTooltip)
                GameTooltip:Show()
            end
        end)
        l:SetScript("OnLeave", function(self)
            self.texte:SetTextColor(c[1], c[2], c[3])
            if options.survol then GameTooltip:Hide() end
        end)
    else
        l:SetScript("OnEnter", nil)
        l:SetScript("OnLeave", nil)
    end
    l:Show()
    return y + hauteur + (options.apres or 2)
end

-- Qui d'autre detient un objet : "Thrall en a 7".
local function AutresDetenteurs(objet, moi)
    if not NS.ref.StocksDisponibles() then return nil end
    local morceaux = {}
    for cle, fiche in pairs(_G.CraftCoreDB.personnages) do
        if cle ~= moi.cle and type(fiche) == "table"
            and (not fiche.faction or not moi.faction or fiche.faction == moi.faction) then
            local sacs, banque = NS.ref.Detenu(cle, objet)
            if sacs + banque > 0 then table.insert(morceaux, NS.NomCourt(cle) .. " " .. (sacs + banque)) end
        end
    end
    if #morceaux == 0 or not NS.ref.Envoyable(objet) then return nil end
    table.sort(morceaux)
    return string.format(L.TRACK_OTHERS, table.concat(morceaux, ", "))
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

-- Avancement d'une quete en cours : la part des objectifs remplie (objets,
-- creatures...), en pourcentage. nil si la quete n'a rien a compter.
local function Avancement(q)
    local fait, total = 0, 0
    for _, o in ipairs(q.objectifs or {}) do
        if (o.requis or 0) > 0 then
            fait = fait + math.min(o.n or 0, o.requis)
            total = total + o.requis
        else
            total = total + 1
            if o.fait then fait = fait + 1 end
        end
    end
    if total == 0 then return nil end
    return math.floor(100 * fait / total + 0.5)
end
suivi.Avancement = Avancement

-- Tris du suivi, dans l'ordre du bouton.
TRIS = { difficulte = 1, xpPlus = 2, xpMoins = 3, orPlus = 4, orMoins = 5 }
local ORDRE_TRIS = { "difficulte", "xpPlus", "xpMoins", "orPlus", "orMoins" }

-- Rang de difficulte d'une quete, d'apres la couleur du jeu : 0 grise,
-- 1 verte, 2 jaune, 3 orange, 4 rouge.
Difficulte = function(niveau, niveauPerso)
    local r, g = NS.ref.CouleurDeNiveau(niveau or 0, niveauPerso)
    if r == 0.5 and g == 0.5 then return 0 end
    if r < 0.5 then return 1 end
    if g >= 0.9 then return 2 end
    if g >= 0.4 then return 3 end
    return 4
end

-- Le client donne les noms de zone en deux langues : "Sombrivage (Darkshore)".
-- Dans le suivi, seul le premier nom est garde.
local function NomDeZoneCourt(nom)
    if type(nom) ~= "string" then return nom end
    return (nom:gsub("%s*%([^()]*%)$", ""))
end
-- "Laird (Sombrivage (Darkshore))" -> "Laird (Sombrivage)".
local function SansSecondNom(texte)
    if type(texte) ~= "string" then return texte end
    return (texte:gsub("%s*%([^()]*%)%)$", ")"))
end

-- Une quete : son titre (icone du jeu, niveau, avancement), puis ses objectifs.
-- Favoris : les quetes qu'on se fixe (seul ou a plusieurs), par personnage.
-- Une quete rendue ou abandonnee sort des favoris.
local function Favoris()
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.Perso(cle)
    if not p then return {} end
    p.favoris = type(p.favoris) == "table" and p.favoris or {}
    for id in pairs(p.favoris) do
        if not (p.quetes and p.quetes[id]) then p.favoris[id] = nil end
    end
    return p.favoris
end
suivi.ListeFavoris = Favoris

function suivi.Favori(id) return Favoris()[id] == true end

-- Rafraichissement du trajet (carte, filigrane, suivi) : differe d'une image
-- et regroupe, jamais au milieu d'un clic ou d'un releve.
local rafraichirPrevu = false
local function RafraichirTrajet()
    if NS.carte then NS.carte.Invalider() end
    local S = NS.suite or _G.CoreSuite
    if S and S.Invalider then S.Invalider() end
    if rafraichirPrevu then return end
    rafraichirPrevu = true
    local function Faire()
        rafraichirPrevu = false
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then pcall(NS.pageCarte.Rendre)
        elseif NS.fenetre and NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
        if suivi.Rendre then pcall(suivi.Rendre) end
    end
    local apres = _G.C_Timer and _G.C_Timer.After
    if apres then apres(0, Faire) else Faire() end
end
suivi.RafraichirTrajet = RafraichirTrajet

-- Question Oui / Non propre a QuestCore (plus de StaticPopup systeme) : une
-- seule a l'ecran, les suivantes attendent leur tour ; la reponse est
-- traitee a l'image suivante.
local question, enAttente = nil, {}
local function MontrerQuestion() end
local function Repondre(oui)
    if NS.Trace then NS.Trace("reponse : " .. (oui and "oui" or "non")) end
    local q = question and question.courante
    if question then question.courante = nil question:Hide() end
    local function Suite()
        if q and oui and q.oui then pcall(q.oui) end
        if #enAttente > 0 then MontrerQuestion(table.remove(enAttente, 1)) end
    end
    local apres = _G.C_Timer and _G.C_Timer.After
    if apres then apres(0, Suite) else Suite() end
end
MontrerQuestion = function(q)
    if NS.Trace then NS.Trace("question : " .. tostring(q.texte)) end
    if not question then
        local ok, f = pcall(CreateFrame, "Frame", "QuestCoreQuestion", UIParent, "BackdropTemplate")
        question = ok and f or CreateFrame("Frame", "QuestCoreQuestion", UIParent)
        if question.SetBackdrop then
            question:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            question:SetBackdropColor(0.09, 0.09, 0.09, 0.92)
            question:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
        end
        question:SetFrameStrata("DIALOG")
        question:SetClampedToScreen(true)
        question:SetPoint("TOP", UIParent, "TOP", 0, -190)
        question:SetWidth(380)
        question:EnableMouse(true)
        question.texte = question:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        question.texte:SetPoint("TOPLEFT", question, "TOPLEFT", 14, -12)
        question.texte:SetPoint("TOPRIGHT", question, "TOPRIGHT", -14, -12)
        question.texte:SetJustifyH("CENTER")
        local function Bouton(libelle, oui, cote)
            local okB, b = pcall(CreateFrame, "Button", nil, question, "UIPanelButtonTemplate")
            b = okB and b or CreateFrame("Button", nil, question)
            b:SetSize(110, 22)
            b:SetText(libelle)
            b:SetPoint("BOTTOM", question, "BOTTOM", cote * 62, 10)
            b:SetScript("OnClick", function() Repondre(oui) end)
            return b
        end
        question.oui = Bouton(_G.YES or "Oui", true, -1)
        question.non = Bouton(_G.NO or "Non", false, 1)
        -- A la manette : A pour Oui, B pour Non, tant que la question est la.
        if question.EnableGamePadButton then
            question:SetScript("OnGamePadButtonDown", function(_, bouton)
                if bouton == "PAD1" then Repondre(true) elseif bouton == "PAD2" then Repondre(false) end
            end)
            question:SetScript("OnShow", function(self) pcall(self.EnableGamePadButton, self, true) end)
            question:SetScript("OnHide", function(self) pcall(self.EnableGamePadButton, self, false) end)
        end
        question:Hide()
    end
    -- Avec une manette : la touche sur chaque bouton.
    local manette = _G.C_GamePad and _G.C_GamePad.IsEnabled and select(2, pcall(_G.C_GamePad.IsEnabled)) == true
    -- Les icones A et B du jeu (celles de la manette choisie dans les options).
    local function Touche(t)
        if not (manette and NS.manette and NS.manette.Glyphe) then return "" end
        local ok, g = pcall(NS.manette.Glyphe, t, 13)
        return ok and g and (g .. " ") or ""
    end
    question.oui:SetText(Touche("PAD1") .. (_G.YES or "Oui"))
    question.non:SetText(Touche("PAD2") .. (_G.NO or "Non"))
    question.courante = q
    question.texte:SetText(q.texte)
    question:SetHeight(math.max(70, (question.texte:GetStringHeight() or 30) + 52))
    question:Show()
end
local function Demander(texte, oui)
    if question and question.courante then
        table.insert(enAttente, { texte = texte, oui = oui })
    else
        MontrerQuestion({ texte = texte, oui = oui })
    end
end
suivi.Demander = Demander

function suivi.PoserFavori(id, oui)
    Favoris()[id] = oui and true or nil
    if NS.groupe and NS.groupe.EnvoyerFavoris then pcall(NS.groupe.EnvoyerFavoris) end
    suivi.Rendre()
end

-- Longue-vue : la quete sur la carte de QuestCore (objectifs, rendu ou
-- donneur), sans fleche de guidage.
local function VoirSurCarte(id, moi)
    local ok, points = pcall(NS.carte.PointsPour, id, moi)
    -- D'abord un lieu sur la carte ou l'on est, puis dans la zone de la
    -- quete, puis n'importe ou dehors ; sinon un lieu de donjon (son entree).
    local ici = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local zoneQ = tonumber(NS.ref.Lire("QuestDB", id, "zoneOrSort"))
    local carteQ = zoneQ and zoneQ > 0 and NS.carte.CarteDeZone(zoneQ)
    local liste = ok and points or {}
    local pt
    for _, cible in ipairs({ ici, carteQ, true }) do
        for _, p in ipairs(liste) do
            if p.carte and not NS.carte.EstInstance(p.carte) and (cible == true or p.carte == cible) then pt = p break end
        end
        if pt then break end
    end
    pt = pt or liste[1]
    if pt and pt.carte and NS.pageCarte and NS.pageCarte.MontrerQuete then
        NS.pageCarte.MontrerQuete(id, pt.carte, pt.x, pt.y, NS.ref.NomDeQuete(id, moi), pt.quoi, true, pt.genre, true)
    end
    if NS.fenetre and NS.fenetre.OuvrirCarte then NS.fenetre.OuvrirCarte() end
end

local function RendreQuete(moi, quetes, id, index, y, prefixe)
    local s = Reglages()
    local q = quetes[id]
    local replieQ = s.replies[id] == true
    local r, g, b = NS.ref.CouleurDeNiveau(q.niveau, moi.niveau)
    local idQuete = id
    local pourcent = (q.complete ~= true and q.complete ~= -1) and Avancement(q) or nil
    local yDebut = y
    local ligneRendu, avecRecompense, yApresTitre, yFinMoi
    index = index + 1
    -- Quete qui se fait dans une instance : l'icone de donjon devant son niveau.
    local donjonQ = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id) and (NS.ref.IconeDonjon() .. " ") or ""
    y = Poser(index, y, (prefixe or "") .. donjonQ .. string.format("|cff%02x%02x%02x[%d]|r %s", math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255), q.niveau or 0, q.titre or ("#" .. id)), { uneLigne = true,
        police = Police("ObjectiveTrackerHeaderFont", "GameFontNormal"), couleur = { 1, 0.82, 0 }, titre = true,
        marque = (q.complete == true) and true or (q.complete == -1 and -1 or false), idQuete = id,
        droite = pourcent and (pourcent .. " %") or nil,
        survol = function(tt) NS.ref.InfobulleDeQuete(tt, q, idQuete, moi) end,
        etoile = moi.cle == NS.ClePersonnage() and { actif = suivi.Favori(idQuete),
            auClic = function() suivi.PoserFavori(idQuete, not suivi.Favori(idQuete)) end } or nil,
        couleurDroite = pourcent and (pourcent >= 100 and { 0.31, 0.82, 0.41 } or { 0.8, 0.8, 0.8 }) or nil,
        auClic = function(_, bouton)
            if bouton == "RightButton" then
                NS.fenetre.OuvrirQuete(moi.cle, idQuete)
            else
                s.replies[idQuete] = not s.replies[idQuete] or nil
                suivi.Rendre()
            end
        end })
    yApresTitre = y
    if not replieQ then
        -- Petite carte (itineraire) et longue-vue (voir sur la carte) :
        -- toujours sur la premiere ligne sous le titre, a droite, pour
        -- toutes les quetes.
        local icones = moi.cle == NS.ClePersonnage() and q.complete ~= -1
        local ongletSel = icones and OngletDeSelection()
        local choisiesQ = ongletSel and Selection(ongletSel)
        local pionQ = choisiesQ and { actif = choisiesQ[idQuete] == true, afaire = q.complete ~= true, auClic = function()
            choisiesQ[idQuete] = not choisiesQ[idQuete] or nil
            suivi.Rendre()
        end } or nil
        local voirQ = icones and function() VoirSurCarte(idQuete, moi) end or nil
        -- Recompense (XP et or) en premier ; le survol garde le detail complet.
        local resume = NS.ref.ResumeRecompenses(q)
        if resume then
            index = index + 1
            y = Poser(index, y, string.format(L.REWARD_LINE, resume), { retrait = 22, couleur = { 1, 0.82, 0 },
                police = "GameFontNormalSmall", petit = true, uneLigne = true,
                pion = pionQ, voir = voirQ, margeDroite = icones and 42 or nil })
            avecRecompense = true
            pionQ, voirQ = nil, nil
        end
        if q.complete == true then
            local receveurs = NS.ref.Receveurs(id)
            index = index + 1
            y = Poser(index, y, receveurs[1] and string.format(L.TRACK_TURN_IN, SansSecondNom(receveurs[1]))
                or L.DONE, { retrait = 22, couleur = { 0.31, 0.82, 0.41 },
                pion = pionQ, voir = voirQ, margeDroite = pionQ and 42 or nil })
        elseif q.complete == -1 then
            index = index + 1
            y = Poser(index, y, L.FAILED, { retrait = 22, couleur = { 0.9, 0.3, 0.3 } })
        else
            local objets = NS.ref.ObjetsRequis(moi, id)
            local rangObjet = 0
            local objetParRang = {}
            -- Mode groupe : les membres du groupe qui ont la meme quete (et
            -- QuestCore), sous nos objectifs.
            local membres = NS.groupe and NS.groupe.Membres(id) or {}
            for rang, o in ipairs(q.objectifs or {}) do
                index = index + 1
                local premiere = rang == 1 and pionQ ~= nil
                y = Poser(index, y, "- " .. tostring(o.texte or ""), { retrait = 22,
                    couleur = o.fait and { 0.5, 0.5, 0.5 } or { 0.85, 0.85, 0.85 },
                    margeDroite = premiere and 42 or nil,
                    pion = premiere and pionQ or nil, voir = premiere and voirQ or nil })
                if o.type == "item" then
                    rangObjet = rangObjet + 1
                    local requis = objets[rangObjet]
                    objetParRang[rang] = requis and requis.objet
                    local autres = requis and not o.fait and AutresDetenteurs(requis.objet, moi)
                    if autres then
                        index = index + 1
                        y = Poser(index, y, autres, { retrait = 32, couleur = { 1, 0.82, 0 },
                            police = "GameFontNormalSmall", petit = true })
                    end
                end
            end
            -- Ou ca se fait : qui laisse les objets, ou sont les creatures ;
            -- sans objectif localise, qui reprend la quete.
            -- Une quete de donjon le dit en clair : elle se fait a l'interieur.
            local dQ = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
            if dQ and dQ.nom then
                index = index + 1
                y = Poser(index, y, string.format(L.TRACK_IN_DUNGEON, dQ.nom), { retrait = 22,
                    couleur = { 1, 0.82, 0 }, police = "GameFontNormalSmall", petit = true, uneLigne = true })
            end
            local ou, parQui = NS.ref.OuSeFait(id)
            if ou and not dQ then
                index = index + 1
                y = Poser(index, y, string.format(parQui and L.TRACK_SEE or L.TRACK_WHERE, ou), { retrait = 22,
                    couleur = { 1, 0.82, 0 }, police = "GameFontNormalSmall", petit = true })
            end
            -- Le groupe : sous nos objectifs, un mini filet, puis chacun avec
            -- son nom (couleur de sa classe) et ou il en est.
            yFinMoi = y
            for rangM, m in ipairs(membres) do
                -- Son nom, et ou il en est en tout (comme notre pourcentage).
                local fait, total = 0, 0
                for _, ob in ipairs(m.objs or {}) do
                    if ob.r > 0 then fait = fait + math.min(ob.n, ob.r) total = total + ob.r end
                end
                local nomEtPart = NomDeMembre(m.nom)
                if m.etat ~= 1 and total > 0 then
                    nomEtPart = nomEtPart .. "  |cffbbbbbb" .. math.floor(fait * 100 / total) .. " %|r"
                end
                index = index + 1
                y = Poser(index, y, nomEtPart, { retrait = 22, police = "GameFontNormalSmall",
                    petit = true, uneLigne = true, miniFilet = rangM == 1 })
                if m.etat == 1 then
                    index = index + 1
                    y = Poser(index, y, L.DONE, { retrait = 32, couleur = { 0.31, 0.82, 0.41 },
                        police = "GameFontNormalSmall", petit = true })
                else
                    for rang, o in ipairs(q.objectifs or {}) do
                        local ob = m.objs[rang]
                        if ob then
                            local fini = ob.r > 0 and ob.n >= ob.r
                            -- Il lui en manque et j'en ai en trop (en gardant
                            -- ce qu'il me faut) : bouton Donner, sur mon perso.
                            local don
                            local objet = objetParRang[rang]
                            -- Groupe simule (mode developpeur) : apercu du bouton
                            -- sur chaque objectif qui lui manque.
                            local simule = NS.groupe.Simule and NS.groupe.Simule(m.nom)
                            if not fini and simule and NS.don then
                                -- Apercu : un objectif sur deux en don complet, l'autre partiel.
                                local nom, n = m.nom, ob.r - ob.n
                                local complet = rang % 2 == 1
                                if not complet and n > 1 then n = math.ceil(n / 2) end
                                don = { texte = string.format(L.GIVE, n), aide = L.GIVE_SIMULATED, complet = complet,
                                    auClic = function() NS.don.Donner(nom, objet or 0, n) end }
                            elseif not fini and objet and NS.don and moi.cle == NS.ClePersonnage() then
                                local manque = ob.r - ob.n
                                local n = math.min(manque, NS.don.EnTrop(objet, tonumber(o.requis) or 0))
                                if n > 0 then
                                    local nom, quantite = m.nom, n
                                    local nomObjet = (NS.Appeler(_G.GetItemInfo, objet)) or ""
                                    don = { texte = string.format(L.GIVE, n), complet = n >= manque,
                                        aide = string.format(L.GIVE_TIP, nom, n, nomObjet),
                                        auClic = function() NS.don.Donner(nom, objet, quantite) end }
                                end
                            end
                            index = index + 1
                            y = Poser(index, y, "- " .. NS.groupe.TexteAvec(o.texte, ob), { retrait = 32,
                                couleur = fini and { 0.5, 0.5, 0.5 } or { 0.85, 0.85, 0.85 },
                                police = "GameFontNormalSmall", petit = true, don = don })
                        end
                    end
                end
            end
        end
    end
    -- Place du bloc, pour le faire clignoter s'il vient d'avancer.
    cadre.blocs = cadre.blocs or {}
    cadre.blocs[id] = { haut = yDebut, bas = y + 2 }
    return index, y + 6
end

-- ---------------------------------------------------------------------------
-- Vue d'un membre du groupe : ses quetes et ou il en est (ce qu'il envoie).
-- Titres et objectifs : ceux qu'il envoie ; a defaut, les miens ou la base.
-- ---------------------------------------------------------------------------

-- Une quete d'un membre : titre, pourcentage, objectifs avec ses comptes.
-- ---------------------------------------------------------------------------
-- Suites de quetes : une quete d'une suite se montre avec toute sa suite.
-- Avant elle, celles deja faites (en vert, rond vert) ; elle, en entier ;
-- apres, celles qui restent, en gris. Un trait vertical relie leurs ronds.
-- Valable pour toutes les suites connues de la base (donjon ou non).
-- ---------------------------------------------------------------------------

local dejaRendues = {}
local traitsPoses = 0
-- Un trait fin, de la couleur de l'anneau dore, accroche au rond d'une
-- quete et au rond de la suivante : centre au pixel, d'un bord a l'autre.
local function Trait(ligneA, ligneB)
    local corps = cadre.corps
    local a = (ligneA.rond and ligneA.rond:IsShown() and ligneA.rond) or ligneA.marque
    local b = (ligneB.rond and ligneB.rond:IsShown() and ligneB.rond) or ligneB.marque
    if not (a and b) then return end
    corps.traits = corps.traits or {}
    traitsPoses = traitsPoses + 1
    local t = corps.traits[traitsPoses]
    if not t then
        t = corps:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0.8, 0.65, 0.3, 0.7)
        corps.traits[traitsPoses] = t
    end
    t:ClearAllPoints()
    t:SetWidth(1)
    t:SetPoint("TOP", a, "BOTTOM", 0, 3)
    t:SetPoint("BOTTOM", b, "TOP", 0, -3)
    t:Show()
end

local function Chaine(moi, id)
    if not (NS.parcours and NS.parcours.Suite) then return nil end
    local ok, liste = pcall(NS.parcours.Suite, moi, id)
    if not ok or type(liste) ~= "table" or #liste < 2 then return nil end
    return liste
end

-- La quete qui suit une quete rendue dans sa suite, si elle n'est pas
-- encore faite : par la suite connue de la base, ou, a defaut, par une
-- quete du journal dont la suite contient celle-ci.
local function SuiteRestante(moi, id)
    local function Faite(c) return moi.faites and moi.faites[c] end
    local chaine = Chaine(moi, id)
    if chaine then
        local passe = false
        for _, c in ipairs(chaine) do
            if c == id then passe = true
            elseif passe and not Faite(c) then return c end
        end
    end
    for c in pairs(moi.quetes or {}) do
        if c ~= id then
            local ch = Chaine(moi, c)
            if ch then for _, x in ipairs(ch) do if x == id then return c end end end
        end
    end
    return nil
end

local RendreEtapeBase
local function RendreAvecChaine(moi, quetes, id, index, y, prefixe)
    if dejaRendues[id] then return index, y end
    local chaine = Chaine(moi, id)
    if not chaine then
        dejaRendues[id] = true
        return RendreQuete(moi, quetes, id, index, y, prefixe)
    end
    -- Les quetes deja rendues ne s'affichent plus : la premiere qui reste
    -- prend leur place, deroulee (dans le journal, ou a prendre) ; les
    -- suivantes, en gris, sans detail, reliees par un trait vertical.
    -- Une quete du journal placee apres des quetes pas encore faites : la
    -- base relie mal la suite ; elle se montre a part, a sa place.
    local aPart, vuTete, trou = {}, false, false
    for _, c in ipairs(chaine) do
        local fait = moi.faites and moi.faites[c]
        if quetes[c] then
            if trou then aPart[c] = true else vuTete = true end
        elseif not fait then
            if vuTete then trou = true else vuTete = true end
        end
    end
    if aPart[id] then
        dejaRendues[id] = true
        return RendreQuete(moi, quetes, id, index, y, prefixe)
    end
    local hauts = {}   -- la ligne de titre de chaque quete de la suite
    local tete, apres = false, 0
    for _, c in ipairs(chaine) do
        local fait = moi.faites and moi.faites[c]
        if c ~= id and dejaRendues[c] then
            -- deja montree avec une autre suite
        elseif aPart[c] then
            -- montree a part, a sa place
        elseif quetes[c] then
            dejaRendues[c] = true
            table.insert(hauts, index + 1)
            index, y = RendreQuete(moi, quetes, c, index, y, c == id and prefixe or nil)
            tete = true
        elseif not fait and not tete then
            dejaRendues[c] = true
            table.insert(hauts, index + 1)
            index, y = RendreEtapeBase(moi, c, nil, NS.parcours.EtatEtape(moi, c), index, y)
            tete = true
        elseif not fait then
            dejaRendues[c] = true
            apres = apres + 1
            if apres <= 6 then
                local niveau = tonumber(NS.ref.Lire("QuestDB", c, "questLevel")) or 0
                local idC = c
                table.insert(hauts, index + 1)
                index = index + 1
                y = Poser(index, y, string.format("[%d] %s", niveau, NS.ref.NomDeQuete(c, moi)), {
                    uneLigne = true, titre = true, marque = "suite", couleur = { 0.55, 0.55, 0.55 },
                    police = Police("ObjectiveTrackerHeaderFont", "GameFontNormal"),
                    survol = function(tt) NS.ref.InfobulleDeLaBase(tt, idC, moi) end }) + 4
                local groupeC = TexteDuGroupe(c)
                if groupeC then
                    index = index + 1
                    y = Poser(index, y - 4, groupeC, { retrait = 22, couleur = { 0.85, 0.85, 0.85 },
                        police = "GameFontNormalSmall", petit = true, uneLigne = true }) + 4
                end
            end
        end
    end
    -- Les traits, d'un rond au suivant (ronds a 1 point du bord, 18 de large).
    for k = 1, #hauts - 1 do Trait(Ligne(hauts[k]), Ligne(hauts[k + 1])) end
    -- Celles montrees a part : juste apres, sans trait.
    for _, c in ipairs(chaine) do
        if aPart[c] and not dejaRendues[c] then
            dejaRendues[c] = true
            index, y = RendreQuete(moi, quetes, c, index, y + 4, nil)
        end
    end
    return index, y + 4
end

-- Une quete rendue d'une suite : sa suivante, retenue tant qu'elle n'est ni
-- prise ni faite, garde la suite visible entre les deux.
local function ChainesEnAttente()
    local g = NS.base.ReglagesGeneraux()
    g.chaines = type(g.chaines) == "table" and g.chaines or {}
    local cle = NS.ClePersonnage()
    if not cle then return {} end
    g.chaines[cle] = type(g.chaines[cle]) == "table" and g.chaines[cle] or {}
    return g.chaines[cle]
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "QUEST_TURNED_IN")
    f:SetScript("OnEvent", function(_, _, idQ)
        local suivante = tonumber(NS.ref.Lire("QuestDB", tonumber(idQ) or 0, "nextQuestInChain"))
        if suivante and suivante > 0 then ChainesEnAttente()[suivante] = true end
    end)
end

local function RendreQueteMembre(moi, e, id, index, y)
    local titres = e.titres or {}
    local function Niveau(i)
        return (titres[i] and titres[i].niveau) or (moi and moi.quetes[i] and moi.quetes[i].niveau)
            or tonumber(NS.ref.Lire("QuestDB", i, "questLevel")) or 0
    end
    local q = e.quetes[id]
    local t = titres[id] or {}
    local mienne = moi and moi.quetes[id]
    local titre = t.titre ~= "" and t.titre or (mienne and mienne.titre) or NS.ref.NomDeQuete(id, moi)
    local niveau = Niveau(id)
    local r, g, b = NS.ref.CouleurDeNiveau(niveau, moi and moi.niveau)
    local fait, total = 0, 0
    for _, ob in ipairs(q.objs) do
        if ob.r > 0 then fait = fait + math.min(ob.n, ob.r) total = total + ob.r end
    end
    local pourcent = (q.etat ~= 1 and total > 0) and math.floor(fait * 100 / total) or nil
    index = index + 1
    y = Poser(index, y, string.format("|cff%02x%02x%02x[%d]|r %s", math.floor(r * 255), math.floor(g * 255),
        math.floor(b * 255), niveau, titre or ("#" .. id)), { uneLigne = true,
        police = Police("ObjectiveTrackerHeaderFont", "GameFontNormal"), couleur = { 1, 0.82, 0 }, titre = true,
        marque = (q.etat == 1) and true or (q.etat == -1 and -1 or false),
        droite = pourcent and (pourcent .. " %") or (mienne and L.TRACK_MEMBER_SHARED or nil),
        couleurDroite = pourcent and { 0.8, 0.8, 0.8 } or { 0.4, 0.78, 1 } })
    if q.etat == 1 then
        index = index + 1
        y = Poser(index, y, L.DONE, { retrait = 22, couleur = { 0.31, 0.82, 0.41 } })
    else
        for rang, ob in ipairs(q.objs) do
            local libelle = t.objs and t.objs[rang]
            if not libelle or libelle == "" then
                local o = mienne and mienne.objectifs and mienne.objectifs[rang]
                if o then libelle = NS.groupe.TexteAvec(o.texte, ob)
                else libelle = string.format(L.TRACK_MEMBER_OBJ, rang) .. " : " .. ob.n .. "/" .. ob.r end
            else
                libelle = libelle .. " : " .. ob.n .. "/" .. ob.r
            end
            local fini = ob.r > 0 and ob.n >= ob.r
            index = index + 1
            y = Poser(index, y, "- " .. libelle, { retrait = 22,
                couleur = fini and { 0.5, 0.5, 0.5 } or { 0.85, 0.85, 0.85 } })
        end
    end
    return index, y + 6
end

local function RendreVueMembre(moi, nom, index, y)
    local e = NS.groupe.Etat(nom)
    index = index + 1
    y = Poser(index, y, string.format(L.TRACK_MEMBER_TITLE, nom), { police = "GameFontNormal", couleur = { 1, 0.82, 0 },
        titre = true, uneLigne = true, filet = true, apres = 6 })
    local ids = {}
    for id in pairs(e and e.quetes or {}) do table.insert(ids, id) end
    if #ids == 0 then
        index = index + 1
        y = Poser(index, y, L.TRACK_MEMBER_NONE, { couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    -- En cours d'abord, puis a rendre ; par niveau.
    local titres = e.titres or {}
    local function Niveau(id)
        return (titres[id] and titres[id].niveau) or (moi and moi.quetes[id] and moi.quetes[id].niveau)
            or tonumber(NS.ref.Lire("QuestDB", id, "questLevel")) or 0
    end
    table.sort(ids, function(a, b)
        local fa, fb = e.quetes[a].etat == 1, e.quetes[b].etat == 1
        if fa ~= fb then return fb end
        if Niveau(a) ~= Niveau(b) then return Niveau(a) < Niveau(b) end
        return a < b
    end)
    for _, id in ipairs(ids) do
        index, y = RendreQueteMembre(moi, e, id, index, y)
    end
    return index, y
end

-- Vue Favoris : mes quetes favorites (comme dans Quetes, avancement du
-- groupe compris), puis les favoris de chaque membre que je n'ai pas deja.
local function RendreVueFavoris(moi, index, y)
    local quetes = moi and moi.quetes or {}
    local mes = {}
    for id in pairs(Favoris()) do if quetes[id] then table.insert(mes, id) end end
    table.sort(mes, function(a, b)
        local na, nb = quetes[a].niveau or 0, quetes[b].niveau or 0
        if na ~= nb then return na < nb end
        return a < b
    end)
    local vus = {}
    for _, id in ipairs(mes) do
        vus[id] = true
        index, y = RendreAvecChaine(moi, quetes, id, index, y)
    end
    local autres = false
    for _, nom in ipairs(NS.groupe and NS.groupe.Noms() or {}) do
        local e = NS.groupe.Etat(nom)
        local siens = {}
        for id in pairs(e and e.favoris or {}) do
            if e.quetes[id] and not vus[id] then table.insert(siens, id) end
        end
        if #siens > 0 then
            autres = true
            table.sort(siens)
            index = index + 1
            y = Poser(index, y, string.format(L.FAV_OF, nom), { police = "GameFontNormal", couleur = { 0.4, 0.78, 1 },
                uneLigne = true, filet = true, apres = 6, separateur = #mes > 0 })
            for _, id in ipairs(siens) do index, y = RendreQueteMembre(moi, e, id, index, y) end
        end
    end
    if #mes == 0 and not autres then
        index = index + 1
        y = Poser(index, y, L.FAV_NONE, { couleur = { 0.6, 0.6, 0.6 } })
    end
    return index, y
end

-- Onglets lateraux, a gauche du suivi, quand on est groupe avec des membres
-- qui ont QuestCore : le premier pour soi, puis un par membre (icone de
-- classe). Petits onglets du grimoire du jeu, retournes pour le bord gauche.
local function OngletMembre(rang)
    cadre.onglets = cadre.onglets or {}
    local b = cadre.onglets[rang]
    if b then return b end
    b = CreateFrame("CheckButton", nil, cadre)
    b:SetSize(26, 26)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    do local S = NS.suite or _G.CoreSuite if S and S.TeinteOnglet then S.TeinteOnglet(b.fond) end end
    b.fond:SetTexCoord(1, 0, 0, 1)
    b.fond:SetSize(52, 52)
    b.fond:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 9)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local halo = b:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    b:SetScript("OnClick", function(self)
        Reglages().vuePerso = self.nom
        suivi.Rendre()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.nom or NS.groupe.MonNom(), 1, 0.82, 0)
        GameTooltip:AddLine(self.nom and L.TRACK_MEMBER_TIP or L.TRACK_MEMBER_ME, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cadre.onglets[rang] = b
    return b
end

local function IconeDeClasse(tex, unite, classeConnue)
    local classe = classeConnue
    if not classe then classe = select(2, NS.Appeler(UnitClass, unite)) end
    local coords = classe and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classe]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(unpack(coords))
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
end

-- Deux onglets lateraux, en bas a gauche du suivi (le haut est aux membres
-- du groupe) : le suivi des quetes, et l'itineraire (boussole), grise tant
-- qu'il n'y a aucun trajet. Memes petits onglets du grimoire.
local function OngletVue(cle, icone, nom, aide)
    cadre.ongletsVues = cadre.ongletsVues or {}
    local b = cadre.ongletsVues[cle]
    if b then return b end
    b = CreateFrame("CheckButton", nil, cadre)
    b:SetSize(26, 26)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    do local S = NS.suite or _G.CoreSuite if S and S.TeinteOnglet then S.TeinteOnglet(b.fond) end end
    b.fond:SetTexCoord(1, 0, 0, 1)
    b.fond:SetSize(52, 52)
    b.fond:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 9)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.icone:SetTexture(icone)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    b.ongletPilote = 1
    local halo = b:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b.cle, b.nom, b.aide = cle, nom, aide
    b:SetScript("OnClick", function(self)
        local s = Reglages()
        s.vuePerso = nil
        if self.cle == "itineraire" then
            if s.vue ~= "parcours" and s.vue ~= "pvp" then s.vueAvantItineraire = s.vue end
            s.vue = "parcours"
        elseif self.cle == "pvp" then
            if s.vue ~= "parcours" and s.vue ~= "pvp" then s.vueAvantItineraire = s.vue end
            s.vue = "pvp"
        else
            s.vue = (s.vueAvantItineraire == "favoris") and "favoris" or "quetes"
        end
        suivi.Rendre()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.nom, 1, 0.82, 0)
        GameTooltip:AddLine(self:IsEnabled() and self.aide or L.TRACK_SIDE_ROUTE_NONE, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cadre.ongletsVues[cle] = b
    return b
end

-- Une boussole : la premiere des icones du jeu qui existe dans ce client.
local boussole
local function IconeBoussole()
    if boussole then return boussole end
    local candidates = {
        "Interface\\Icons\\inv_10_dungeonjewelry_explorer_trinket_1compass_color2",
        "Interface\\Icons\\inv_10_dungeonjewelry_explorer_trinket_1compass_color1",
        "Interface\\Icons\\inv_10_dungeonjewelry_explorer_trinket_1compass_color3",
        "Interface\\Icons\\INV_Misc_Map_01",
    }
    local existe = NS.Lecture("GetFileIDFromPath")
    for _, c in ipairs(candidates) do
        if not existe or NS.Appeler(existe, c) then boussole = c return c end
    end
    boussole = candidates[#candidates]
    return boussole
end

PoserOngletsVues = function(replie, nParcours)
    local s = Reglages()
    local quetes = OngletVue("quetes", "Interface\\Icons\\INV_Misc_Book_08", L.TRACK_SIDE_QUESTS, L.TRACK_SIDE_QUESTS_TIP)
    local route = OngletVue("itineraire", IconeBoussole(), L.TRACK_SIDE_ROUTE, L.TRACK_SIDE_ROUTE_TIP)
    local avecRoute = (nParcours or 0) > 0
    -- Plus de trajet : retour au suivi des quetes.
    if not avecRoute and s.vue == "parcours" then s.vue = "quetes" end
    local enRoute = s.vue == "parcours" and not s.vuePerso
    -- Onglet JcJ, sous les deux autres, quand PvPCore est installe.
    local avecPvp = _G.PvPCoreAPI ~= nil
    local pvp = avecPvp and OngletVue("pvp", "Interface\\Icons\\INV_BannerPVP_02", L.TRACK_SIDE_PVP, L.TRACK_SIDE_PVP_TIP)
    if not avecPvp and s.vue == "pvp" then s.vue = "quetes" end
    local enPvp = s.vue == "pvp" and not s.vuePerso
    if enPvp then enRoute = false end
    quetes:SetChecked(not enRoute and not enPvp and not s.vuePerso)
    route:SetChecked(enRoute)
    route:SetEnabled(avecRoute)
    route.icone:SetDesaturated(not avecRoute)
    route.icone:SetAlpha(avecRoute and 1 or 0.5)
    quetes:ClearAllPoints()
    route:ClearAllPoints()
    if pvp then
        pvp:ClearAllPoints()
        pvp:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMLEFT", -2, 40)
        pvp:SetChecked(enPvp)
        pvp:SetShown(not replie)
        route:SetPoint("BOTTOM", pvp, "TOP", 0, 12)
    else
        route:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMLEFT", -2, 40)
        if cadre.ongletsVues and cadre.ongletsVues.pvp then cadre.ongletsVues.pvp:Hide() end
    end
    quetes:SetPoint("BOTTOM", route, "TOP", 0, 12)
    quetes:SetShown(not replie)
    route:SetShown(not replie)
end

local function PoserOngletsMembres(replie)
    local noms = (NS.groupe and not replie) and NS.groupe.Noms() or {}
    local s = Reglages()
    local trouve = s.vuePerso == nil
    for _, n in ipairs(noms) do if n == s.vuePerso then trouve = true end end
    if not trouve then s.vuePerso = nil end
    for _, b in ipairs(cadre.onglets or {}) do b:Hide() end
    if #noms == 0 then return end
    local liste = { { nom = nil, unite = "player" } }
    for _, n in ipairs(noms) do table.insert(liste, { nom = n, unite = NS.groupe.Unite(n), classe = NS.groupe.Classe and NS.groupe.Classe(n) }) end
    local precedent
    for rang, m in ipairs(liste) do
        local b = OngletMembre(rang)
        b.nom = m.nom
        IconeDeClasse(b.icone, m.unite or "none", m.classe)
        b:SetChecked(s.vuePerso == m.nom)
        b:ClearAllPoints()
        if precedent then b:SetPoint("TOP", precedent, "BOTTOM", 0, -12)
        else b:SetPoint("TOPRIGHT", cadre, "TOPLEFT", -2, -40) end
        b:Show()
        precedent = b
    end
end

-- Onglet Parcours : la liste des parcours, et le parcours choisi deplie,
-- etape par etape, pour ne travailler qu'avec lui.
local ETATS_COULEUR = { faite = { 0.5, 0.5, 0.5 }, rendre = { 0.31, 0.82, 0.41 }, cours = { 1, 0.82, 0 },
    prendre = { 1, 0.82, 0 }, attente = { 0.6, 0.6, 0.6 } }

-- Sorte d'un parcours, pour les onglets de l'itineraire.
CategorieDe = function(pc) return (pc and pc.genre == "kit") and "donjons" or "divers" end

-- La tournee de recolte de MapCore, s'il y en a une.
TourneeRecolte = function()
    local api = _G.MapCoreAPI
    if not (api and api.Tournee) then return nil end
    local ok, t = pcall(api.Tournee)
    return ok and type(t) == "table" and t or nil
end

-- Une etape pas encore au journal, presentee comme une quete du suivi :
-- niveau a la couleur du jeu, titre, recompense connue (XP de la base ;
-- l'argent n'y est pas), objectifs de la base, puis chez qui la prendre (un
-- clic : sur la carte). Le survol donne tout ce que la base en sait.
RendreEtapeBase = function(moi, id, rang, e, index, y, pion)
    local s = Reglages()
    local niveau = tonumber(NS.ref.Lire("QuestDB", id, "questLevel")) or 0
    local r, g, b = NS.ref.CouleurDeNiveau(niveau, moi.niveau)
    local attente = e == "attente"
    local replieE = s.replies[id] == true
    local idE = id
    -- Petite carte et longue-vue : sur la premiere ligne sous le titre,
    -- comme pour les quetes prises ; sur le titre si l'etape est repliee.
    local voirE = pion and function() VoirSurCarte(idE, moi) end or nil
    local pionL, voirL = pion, voirE
    local function Icones()
        local p1, v1 = pionL, voirL
        pionL, voirL = nil, nil
        return { pion = p1, voir = v1, marge = p1 and 42 or nil }
    end
    index = index + 1
    local donjonE = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id) and (NS.ref.IconeDonjon() .. " ") or ""
    y = Poser(index, y, (rang and (rang .. ". ") or "") .. donjonE .. string.format("|cff%02x%02x%02x[%d]|r %s", math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255), niveau, NS.ref.NomDeQuete(id, moi)), { uneLigne = true,
        police = Police("ObjectiveTrackerHeaderFont", "GameFontNormal"), titre = true,
        couleur = attente and { 0.6, 0.6, 0.6 } or { 1, 0.82, 0 },
        pion = replieE and pion or nil, voir = replieE and voirE or nil,
        survol = function(tt)
            NS.ref.InfobulleDeLaBase(tt, idE, moi)
            local textes = NS.ref.Lire("QuestDB", idE, "objectivesText")
            if type(textes) == "table" and #textes > 0 then
                tt:AddLine(" ")
                tt:AddLine(L.QUEST_GOAL, 1, 0.82, 0)
                for _, t in ipairs(textes) do
                    local ligne = tostring(t):match("^%s*(.-)%s*$")
                    if ligne ~= "" then tt:AddLine(ligne, 1, 1, 1, true) end
                end
            end
        end,
        auClic = function()
            s.replies[idE] = not s.replies[idE] or nil
            suivi.Rendre()
        end })
    if not replieE then
        local dE = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
        if dE and dE.nom then
            index = index + 1
            local ic = Icones()
            y = Poser(index, y, string.format(L.TRACK_IN_DUNGEON, dE.nom), { retrait = 22, couleur = { 1, 0.82, 0 },
                police = "GameFontNormalSmall", petit = true, uneLigne = true, pion = ic.pion, voir = ic.voir, margeDroite = ic.marge })
        end
        local groupeE = TexteDuGroupe(id)
        if groupeE then
            index = index + 1
            local ic = Icones()
            y = Poser(index, y, groupeE, { retrait = 22, couleur = { 0.85, 0.85, 0.85 }, police = "GameFontNormalSmall",
                petit = true, uneLigne = true, pion = ic.pion, voir = ic.voir, margeDroite = ic.marge })
        end
        local xp = NS.ref.XPDeLaBase(id, moi.niveau)
        if xp and xp > 0 then
            index = index + 1
            local ic = Icones()
            y = Poser(index, y, string.format(L.REWARD_LINE, string.format(L.REWARD_XP, xp)), { retrait = 22,
                couleur = { 1, 0.82, 0 }, police = "GameFontNormalSmall", petit = true, uneLigne = true,
                pion = ic.pion, voir = ic.voir, margeDroite = ic.marge })
        end
        local textes = NS.ref.Lire("QuestDB", id, "objectivesText")
        if type(textes) == "table" then
            -- La base coupe ses textes en paragraphes, avec des lignes vides.
            for _, t in ipairs(textes) do
                local ligne = tostring(t):match("^%s*(.-)%s*$")
                if ligne ~= "" then
                    index = index + 1
                    local ic = Icones()
                    y = Poser(index, y, "- " .. ligne, { retrait = 22, couleur = { 0.85, 0.85, 0.85 },
                        pion = ic.pion, voir = ic.voir, margeDroite = ic.marge })
                end
            end
        end
        local detail, couleurDetail
        if e == "prendre" then
            local donneurs = NS.ref.Donneurs(id)
            detail = donneurs[1] and string.format(L.TRACK_PICK_UP, donneurs[1]) or L.ROUTE_TO_TAKE
            couleurDetail = { 1, 0.82, 0 }
        else
            local requis = tonumber(NS.ref.Lire("QuestDB", id, "requiredLevel")) or 0
            detail = (moi.niveau and requis > moi.niveau) and string.format(L.ROUTE_LEVEL, requis) or L.DUNGEON_LOCKED
            couleurDetail = { 0.6, 0.6, 0.6 }
        end
        index = index + 1
        local ic = Icones()
        y = Poser(index, y, detail, { retrait = 22, couleur = couleurDetail,
            pion = ic.pion, voir = ic.voir, margeDroite = ic.marge,
            auClic = (NS.fenetre and NS.fenetre.VoirQuete) and function() NS.fenetre.VoirQuete(idE, moi, true) end or nil })
    end
    return index, y + 6
end

-- La tournee de recolte de MapCore : ses lieux par matiere, et ceux deja
-- visites ce tour-ci.
local function RendreTournee(index, y)
    local t = TourneeRecolte()
    if not t then
        index = index + 1
        y = Poser(index, y, L.TRACK_FARM_NONE, { couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    local pct = t.total > 0 and math.floor(t.faits * 100 / t.total + 0.5) or 0
    local info = NS.Lecture("C_Map.GetMapInfo")
    local zone = info and NS.Appeler(info, t.carte)
    index = index + 1
    y = Poser(index, y, (type(zone) == "table" and zone.name) and string.format(L.TRACK_FARM_IN, zone.name) or L.TRACK_ROUTE_FARM,
        { police = "GameFontNormal", zone = true, uneLigne = true, couleur = { 1, 0.82, 0 },
        droite = pct .. " %", couleurDroite = { 1, 1, 1 }, apres = 4 })
    local parObjet, ordre = {}, {}
    for _, p in ipairs(t.points or {}) do
        if not parObjet[p.objet] then parObjet[p.objet] = 0 table.insert(ordre, p.objet) end
        parObjet[p.objet] = parObjet[p.objet] + 1
    end
    for _, objet in ipairs(ordre) do
        index = index + 1
        y = Poser(index, y, string.format("|T%s:14|t %s", tostring(NS.ref.IconeDObjet(objet)), NS.ref.NomDObjet(objet)),
            { retrait = 22, couleur = { 1, 1, 1 }, uneLigne = true,
            droite = string.format(L.TRACK_FARM_SPOTS, parObjet[objet]), couleurDroite = { 0.8, 0.8, 0.8 } })
    end
    return index, y + 6
end

-- Onglet JcJ (avec PvPCore) : ses rubriques (champ de bataille en cours,
-- files d'attente, rang, victoires honorables, marques, quetes JcJ), meme
-- presentation que les zones et les quetes. Rafraichi toutes les 3 secondes
-- tant que l'onglet est ouvert (temps d'attente, objectifs).
local rafraichirPvp = false
local function RendreVuePvp(index, y)
    local api = _G.PvPCoreAPI
    local rubriques = (api and api.Rubriques) and api.Rubriques() or {}
    if #rubriques == 0 then
        index = index + 1
        y = Poser(index, y, L.TRACK_PVP_EMPTY, { couleur = { 0.6, 0.6, 0.6 } })
    end
    for k, x in ipairs(rubriques) do
        index = index + 1
        y = Poser(index, y, x.titre, { police = "GameFontNormal", zone = true, uneLigne = true, couleur = { 1, 0.82, 0 },
            separateur = k > 1, apres = 4 })
        for _, e in ipairs(x.lignes or {}) do
            index = index + 1
            y = Poser(index, y, e.texte or "", { retrait = 22, couleur = e.couleur or { 1, 1, 1 }, uneLigne = true,
                droite = e.droite, couleurDroite = { 0.85, 0.85, 0.85 } })
        end
    end
    if not rafraichirPvp then
        -- Une veille legere (une fois) : toutes les 3 secondes, seulement
        -- tant que l'onglet JcJ est ouvert et le suivi visible.
        rafraichirPvp = true
        local veille, attente = CreateFrame("Frame"), 3
        veille:SetScript("OnUpdate", function(_, ecoule)
            attente = attente - (ecoule or 0)
            if attente > 0 then return end
            attente = 3
            local s = Reglages()
            if s.vue == "pvp" and not s.replie and cadre and cadre:IsShown() then pcall(suivi.Rendre) end
        end)
    end
    return index, y + 6
end

RendreVueParcours = function(moi, index, y)
    local s = Reglages()
    local categorie = s.routeCategorie or "divers"
    if categorie == "recolte" then return RendreTournee(index, y) end
    local cle = NS.ClePersonnage()
    -- Les parcours termines s'en vont d'eux-memes (et leur guidage avec).
    if moi and NS.parcours and NS.parcours.Nettoyer then
        for _, idR in ipairs(NS.parcours.Nettoyer(cle, moi)) do
            if type(s.parcoursOuverts) == "table" then s.parcoursOuverts[idR] = nil end
            if NS.carte and NS.carte.Invalider then NS.carte.Invalider() end
        end
    end
    local liste = {}
    for _, pc in ipairs((moi and NS.parcours) and NS.parcours.Liste(cle) or {}) do
        if CategorieDe(pc) == categorie then table.insert(liste, pc) end
    end
    if #liste == 0 then
        index = index + 1
        y = Poser(index, y, L.TRACK_NO_ROUTE, { couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    -- Plusieurs parcours peuvent etre ouverts a la fois ; le dernier choisi
    -- est celui du bouton Guider.
    local choisi = NS.parcours.Trouver(cle, s.parcoursChoisi)
    if not choisi or CategorieDe(choisi) ~= categorie then choisi = liste[1] end
    s.parcoursChoisi = choisi.id
    s.parcoursOuverts = type(s.parcoursOuverts) == "table" and s.parcoursOuverts or {}
    if next(s.parcoursOuverts) == nil then s.parcoursOuverts[choisi.id] = true end
    for _, pc in ipairs(liste) do
        local faites, total, pct = NS.parcours.Avancement(moi, pc)
        local ouvert = s.parcoursOuverts[pc.id] == true
        local idP = pc.id
        index = index + 1
        -- Meme hierarchie que l'onglet Quetes : le parcours comme une zone,
        -- ses etapes comme des quetes.
        y = Poser(index, y, pc.nom, { police = "GameFontNormal", zone = true, uneLigne = true,
            couleur = ouvert and { 1, 0.82, 0 } or { 0.7, 0.7, 0.7 },
            marqueTexture = ouvert and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up",
            droite = pct .. " %", couleurDroite = pct >= 100 and { 0.31, 0.82, 0.41 } or { 1, 1, 1 },
            separateur = index > 1, apres = 4,
            auClic = function(_, bouton)
                if bouton == "RightButton" then NS.fenetre.OuvrirParcours() return end
                s.parcoursOuverts[idP] = not s.parcoursOuverts[idP] or nil
                s.parcoursChoisi = idP
                suivi.Rendre()
            end })
        if ouvert then
            if total > 0 and faites >= total then
                -- Tout est fait : plus rien a montrer, le bouton Supprimer
                -- est en bas du suivi.
                index = index + 1
                y = Poser(index, y, L.ROUTE_ALL_DONE, { retrait = 22, couleur = { 0.31, 0.82, 0.41 } }) + 6
            else
                -- La petite carte d'une etape : la garder dans l'itineraire
                -- (guidage et carte) ou l'en retirer ; retiree, elle reste en
                -- bas, grisee, pour la remettre.
                -- Trois groupes lisibles : en cours (quetes prises), a faire
                -- (a prendre), fait (en vert, coche) ; le numero reste celui
                -- du parcours.
                local enCours, aRendre, aFaire, faites = {}, {}, {}, {}
                local dansLeTrajet = {}
                for _, id in ipairs(pc.etapes) do dansLeTrajet[id] = true end
                for rang, id in ipairs(pc.etapes) do
                    local e = NS.parcours.EtatEtape(moi, id)
                    local q = moi.quetes[id]
                    -- Une etape rendue dont la suite continue : la suivante
                    -- prend sa place (prise, a rendre ou a prendre).
                    local suite = e == "faite" and SuiteRestante(moi, id)
                    if suite and dansLeTrajet[suite] then suite = nil end
                    if (e == "cours" or e == "rendre") and q then
                        table.insert(q.complete == true and aRendre or enCours, { rang = rang, id = id })
                    elseif suite and moi.quetes[suite] then
                        table.insert(moi.quetes[suite].complete == true and aRendre or enCours, { rang = rang, id = suite })
                    elseif suite then
                        table.insert(aFaire, { rang = rang, id = suite, suite = true })
                    elseif e == "faite" then
                        table.insert(faites, { rang = rang, id = id })
                    else
                        table.insert(aFaire, { rang = rang, id = id, e = e })
                    end
                end
                -- Les quatre groupes : meme titre, meme retrait ; les quetes y
                -- gardent leur presentation habituelle.
                local function Groupe(titre, n, couleur)
                    index = index + 1
                    y = Poser(index, y, titre .. " (" .. n .. ")", { uneLigne = true, couleur = couleur,
                        police = "GameFontNormalSmall", petit = true }) + 2
                end
                -- Quetes d'un donjon : rangees selon le moment, pour qu'on sache
                -- tout de suite quoi faire avant d'entrer, quoi faire dedans,
                -- et quoi rendre au retour.
                if pc.genre == "kit" and NS.donjons and NS.donjons.DeQuete then
                    local avant, dedans, retour = {}, {}, {}
                    local function Dedans(id) return NS.donjons.DeQuete(id) ~= nil end
                    for _, t in ipairs(enCours) do table.insert(Dedans(t.id) and dedans or avant, t) end
                    for _, t in ipairs(aFaire) do table.insert(avant, t) end
                    for _, t in ipairs(aRendre) do table.insert(retour, t) end
                    table.sort(avant, function(a2, b2) return a2.rang < b2.rang end)
                    local function Etape(t)
                        if dejaRendues[t.id] then return end
                        if moi.quetes[t.id] or t.suite then
                            index, y = RendreAvecChaine(moi, moi.quetes, t.id, index, y, t.rang .. ". ")
                        else
                            local idQ = t.id
                            index, y = RendreEtapeBase(moi, t.id, t.rang, t.e, index, y, { actif = true, aide = L.ROUTE_STEP_HELP,
                                auClic = function()
                                    if suivi.PasserEtape then suivi.PasserEtape(idP, idQ) end
                                    suivi.Rendre()
                                end })
                        end
                    end
                    if #avant > 0 then
                        Groupe(L.KIT_BEFORE, #avant, { 1, 0.82, 0 })
                        for _, t in ipairs(avant) do Etape(t) end
                    end
                    if #dedans > 0 then
                        Groupe(L.KIT_INSIDE, #dedans, { 0.4, 0.75, 1 })
                        for _, t in ipairs(dedans) do Etape(t) end
                    end
                    if #retour > 0 then
                        Groupe(L.KIT_AFTER, #retour, { 1, 0.6, 0.2 })
                        for _, t in ipairs(retour) do Etape(t) end
                    end
                    enCours, aRendre, aFaire = {}, {}, {}
                end
                if #enCours > 0 then
                    Groupe(L.TRACK_SECTION_ACTIVE, #enCours, { 0.4, 0.75, 1 })
                    for _, t in ipairs(enCours) do
                        index, y = RendreAvecChaine(moi, moi.quetes, t.id, index, y, t.rang .. ". ")
                    end
                end
                if #aRendre > 0 then
                    Groupe(L.TRACK_SECTION_DONE, #aRendre, { 1, 0.6, 0.2 })
                    for _, t in ipairs(aRendre) do
                        index, y = RendreAvecChaine(moi, moi.quetes, t.id, index, y, t.rang .. ". ")
                    end
                end
                -- Deja montrees dans une suite plus haut : pas deux fois.
                local resteAFaire = {}
                for _, t in ipairs(aFaire) do if not dejaRendues[t.id] then table.insert(resteAFaire, t) end end
                aFaire = resteAFaire
                if #aFaire > 0 then
                    Groupe(L.ROUTE_GROUP_TODO, #aFaire, { 1, 0.82, 0 })
                    for _, t in ipairs(aFaire) do
                        local idQ = t.id
                        if t.suite then
                            index, y = RendreAvecChaine(moi, moi.quetes, t.id, index, y, t.rang .. ". ")
                        else
                        index, y = RendreEtapeBase(moi, t.id, t.rang, t.e, index, y, { actif = true, aide = L.ROUTE_STEP_HELP,
                            auClic = function()
                                if suivi.PasserEtape then suivi.PasserEtape(idP, idQ) end
                                suivi.Rendre()
                            end })
                        end
                    end
                end
                if #faites > 0 then
                    Groupe(L.ROUTE_GROUP_DONE, #faites, { 0.25, 0.9, 0.25 })
                    for _, t in ipairs(faites) do
                        -- Comme un titre de quete : meme police, meme place, avec
                        -- le rond du jeu et son point d'interrogation en vert.
                        local niveau = tonumber(NS.ref.Lire("QuestDB", t.id, "questLevel")) or 0
                        index = index + 1
                        y = Poser(index, y, string.format("%d. [%d] %s", t.rang, niveau, NS.ref.NomDeQuete(t.id, moi)),
                            { uneLigne = true, titre = true, marque = "fait", couleur = { 0.25, 0.9, 0.25 },
                            police = Police("ObjectiveTrackerHeaderFont", "GameFontNormal") }) + 4
                    end
                end
                local retirees = {}
                for idR in pairs(type(pc.ignorees) == "table" and pc.ignorees or {}) do
                    if NS.parcours.EtatEtape(moi, idR) ~= "faite" then table.insert(retirees, idR) end
                end
                table.sort(retirees)
                for _, idR in ipairs(retirees) do
                    local idQ = idR
                    index = index + 1
                    y = Poser(index, y, NS.ref.NomDeQuete(idR, moi), { uneLigne = true, couleur = { 0.5, 0.5, 0.5 },
                        police = "GameFontNormalSmall", petit = true,
                        pion = { actif = false, aide = L.ROUTE_STEP_HELP, auClic = function()
                            NS.parcours.RemettreEtape(cle, idP, idQ)
                            if suivi.RafraichirTrajet then pcall(suivi.RafraichirTrajet) end
                            suivi.Rendre()
                        end } }) + 4
                end
            end
            y = y + 4
        end
    end
    return index, y
end

function suivi.Rendre()
    if not cadre then return end
    local ok, souci = pcall(function()
        local s = Reglages()
        local moi = NS.base.Perso(NS.ClePersonnage())
        local quetes = moi and moi.quetes or {}
        local ids = {}
        local filtre = NS.base.FiltreARendre()
        local nRendre = 0
        for id, q in pairs(quetes) do
            if q.complete == true then nRendre = nRendre + 1 end
            if filtre then
                if q.complete == true then table.insert(ids, id) end
            elseif q.complete ~= true or s.termineesDansQuetes then
                table.insert(ids, id)
            end
        end
        local total = 0
        for _ in pairs(quetes) do total = total + 1 end
        -- Tri choisi en bas du suivi : difficulte (grises, vertes, jaunes,
        -- oranges, rouges), XP ou or rapportes, du plus au moins ou l'inverse.
        local tri = TRIS[s.tri] and s.tri or "difficulte"
        local function Valeur(q)
            if tri == "difficulte" then return Difficulte(q.niveau, moi and moi.niveau) end
            local r = q.recompenses or {}
            if tri == "xpPlus" or tri == "xpMoins" then return tonumber(r.xp) or 0 end
            return tonumber(r.argent) or 0
        end
        local decroissant = tri == "xpPlus" or tri == "orPlus"
        table.sort(ids, function(a, b)
            local qa, qb = quetes[a], quetes[b]
            local va, vb = Valeur(qa), Valeur(qb)
            if va ~= vb then
                if decroissant then return va > vb end
                return va < vb
            end
            if (qa.niveau or 0) ~= (qb.niveau or 0) then return (qa.niveau or 0) < (qb.niveau or 0) end
            return tostring(qa.titre) < tostring(qb.titre)
        end)
        if cadre.titre then cadre.titre:SetText(string.format(L.TRACK_TITLE, total)) end
        cadre.replier:SetNormalTexture(s.replie and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")

        local corps = cadre.corps
        for _, l in ipairs(corps.lignes or {}) do l:Hide() end
        for _, t in ipairs(corps.traits or {}) do t:Hide() end
        traitsPoses = 0
        dejaRendues = {}
        cadre.defilement:SetShown(not s.replie)
        cadre.poignee:SetShown(not s.replie)
        if cadre.poigneeHaut then cadre.poigneeHaut:SetShown(cadre.poignee:IsShown()) end
        cadre.resume:SetShown(s.replie == true)
        local vueEffective = (s.vue == "parcours" or s.vue == "favoris") and s.vue or (filtre and "rendre" or "quetes")
        if s.vuePerso then vueEffective = nil end
        for cle, b in pairs(cadre.vues) do b:Choisir(cle == vueEffective) end
        -- Onglets du haut : une icone et un compte (le nom au survol).
        local nFavoris = 0
        for _ in pairs(Favoris()) do nFavoris = nFavoris + 1 end
        local nCours = 0
        for _, q in pairs(quetes) do if q.complete ~= true then nCours = nCours + 1 end end
        local nParcours = NS.parcours and #NS.parcours.Liste(NS.ClePersonnage()) or 0
        cadre.vues.quetes:Compter(nCours)
        cadre.vues.rendre:Compter(nRendre)
        cadre.vues.favoris:Compter(nFavoris)
        -- Onglet Itineraire : ses trois onglets a la place de ceux des quetes.
        local enItineraire = s.vue == "parcours" and not s.vuePerso
        for _, b in pairs(cadre.vues) do b:SetShown(not s.replie and not enItineraire and s.vue ~= "pvp") end
        local nDivers, nDonjons = 0, 0
        for _, pc in ipairs(NS.parcours and NS.parcours.Liste(NS.ClePersonnage()) or {}) do
            if CategorieDe(pc) == "donjons" then nDonjons = nDonjons + 1 else nDivers = nDivers + 1 end
        end
        local tournee = TourneeRecolte()
        local nRecolte = tournee and 1 or 0
        nParcours = nParcours + nRecolte
        -- Premiere fois : la sorte du dernier parcours choisi.
        if not s.routeCategorie then
            local choisi = NS.parcours and NS.parcours.Trouver(NS.ClePersonnage(), s.parcoursChoisi)
            s.routeCategorie = choisi and CategorieDe(choisi) or (nDivers == 0 and nDonjons > 0 and "donjons") or "divers"
        end
        for cleR, b in pairs(cadre.vuesRoute or {}) do
            b:SetShown(not s.replie and enItineraire)
            b:Choisir(cleR == s.routeCategorie)
        end
        if cadre.vuesRoute then
            cadre.vuesRoute.divers:Compter(nDivers)
            cadre.vuesRoute.recolte:Compter(nRecolte)
            cadre.vuesRoute.donjons:Compter(nDonjons)
        end
        cadre.filetHaut:SetShown(not s.replie)
        cadre.tout:Hide()
        cadre.trier:Hide()
        cadre.voirCarte:Hide()
        -- Bilan a rendre : quetes, XP et argent, et si l'XP suffit pour
        -- monter de niveau.
        local xpRendre, orRendre = 0, 0
        for _, q in pairs(quetes) do
            if q.complete == true then
                local r = q.recompenses or {}
                xpRendre = xpRendre + (tonumber(r.xp) or 0)
                orRendre = orRendre + (tonumber(r.argent) or 0)
            end
        end
        local bilan = cadre.bilan
        local manque = (NS.Appeler(UnitXPMax, "player") or 0) - (NS.Appeler(UnitXP, "player") or 0)
        local function XPDe(id)
            local q = quetes[id]
            local r = q and q.recompenses
            return tonumber(r and r.xp) or NS.ref.XPDeLaBase(id, moi and moi.niveau) or 0
        end
        local rangs = {}
        local function Titre(gauche, droite) table.insert(rangs, { genre = "titre", gauche = gauche, droite = droite }) end
        local function Detail(texte, couleur) table.insert(rangs, { genre = "detail", texte = texte, couleur = couleur }) end
        local function XP(n) return (n and n > 0) and (NS.ref.NombreLisible(n) .. " XP") or nil end
        local function Quetes(n) return string.format(n > 1 and L.TRACK_N_QUESTS or L.TRACK_1_QUEST, n) end
        -- Ce que montre l'onglet : le parcours choisi, ou les favoris.
        if s.vue == "parcours" and NS.parcours then
            local liste = NS.parcours.Liste(NS.ClePersonnage())
            local pc = NS.parcours.Trouver(NS.ClePersonnage(), s.parcoursChoisi) or liste[1]
            if pc and moi then
                local reste, xp = 0, 0
                for _, id in ipairs(pc.etapes) do
                    if NS.parcours.EtatEtape(moi, id) ~= "faite" then reste = reste + 1 xp = xp + XPDe(id) end
                end
                Titre(L.TRACK_COL_ROUTE .. " : " .. string.format(L.TRACK_N_STEPS, reste), XP(xp))
            end
        elseif s.vue == "favoris" then
            local n, xp = 0, 0
            for id in pairs(Favoris()) do n = n + 1 xp = xp + XPDe(id) end
            if n > 0 then Titre(L.TRACK_COL_FAV .. " : " .. Quetes(n), XP(xp)) end
        end
        -- Ce qu'il y a a rendre, puis la selection de l'onglet (cochees,
        -- terminees ou en cours).
        local nSel, xpSel, orSel = 0, 0, 0
        local ongletSel = OngletDeSelection()
        for idSel in pairs(ongletSel and Selection(ongletSel) or {}) do
            local qs = quetes[idSel]
            if qs and qs.complete ~= -1 then
                nSel = nSel + 1
                xpSel = xpSel + (tonumber(qs.recompenses and qs.recompenses.xp) or 0)
                orSel = orSel + (tonumber(qs.recompenses and qs.recompenses.argent) or 0)
            end
        end
        local niveauSuivant = (tonumber(NS.Appeler(UnitLevel, "player")) or 0) + 1
        if nRendre == 0 then
            Detail(L.TRACK_BILAN_NONE, { 0.6, 0.6, 0.6 })
        else
            Titre(L.TRACK_COL_TURNIN .. " : " .. Quetes(nRendre), XP(xpRendre))
            if orRendre > 0 then Detail(NS.ref.TexteArgent(orRendre), { 0.85, 0.85, 0.85 }) end
            if nSel > 0 then
                Titre(L.TRACK_COL_PATH .. " : " .. Quetes(nSel), XP(xpSel))
                if orSel > 0 then Detail(NS.ref.TexteArgent(orSel), { 0.85, 0.85, 0.85 }) end
            end
        end
        -- Prochain niveau : ce qui manque encore (lu en direct, remis a zero
        -- a chaque niveau), puis ce qu'apporte le rendu (ou la selection).
        if manque > 0 then
            Titre(string.format(L.TRACK_NEXT_LEVEL, niveauSuivant),
                string.format(L.TRACK_NEXT_LEVEL_LEFT, NS.ref.NombreLisible(manque)))
            local apport = nSel > 0 and xpSel or xpRendre
            if apport >= manque then
                Detail(string.format(L.TRACK_BAR_OK, niveauSuivant), { 0.31, 0.82, 0.41 })
            elseif apport > 0 then
                Detail(string.format(L.TRACK_NEXT_LEVEL_AFTER, NS.ref.NombreLisible(manque - apport)), { 0.6, 0.6, 0.6 })
            end
        end
        -- Boutons : trajet le plus court pour le niveau, et guidage du trajet.
        local boutons = {}
        -- Trajet niveau : dans la vue des quetes, pas dans celle d'un parcours
        -- (son propre trajet y a deja ses boutons).
        -- Onglet Parcours : le bouton guide le parcours affiche.
        local pcVue
        local categorie = s.routeCategorie or "divers"
        if s.vue == "parcours" and NS.parcours and categorie ~= "recolte" then
            pcVue = NS.parcours.Trouver(NS.ClePersonnage(), s.parcoursChoisi)
            if not pcVue or CategorieDe(pcVue) ~= categorie then
                pcVue = nil
                for _, pc in ipairs(NS.parcours.Liste(NS.ClePersonnage())) do
                    if not pcVue and CategorieDe(pc) == categorie then pcVue = pc end
                end
            end
        end
        -- Recolte : guider la tournee de MapCore, ou l'effacer.
        if s.vue == "parcours" and categorie == "recolte" then
            local t = TourneeRecolte()
            local api = _G.MapCoreAPI
            if t and api then
                table.insert(boutons, { t.guide and L.GUIDE_STOP or L.GUIDE_START, function()
                    if api.BasculerTournee then pcall(api.BasculerTournee) end
                    suivi.Rendre()
                end, L.GUIDE_HELP })
                table.insert(boutons, { L.TRACK_FARM_CLEAR, function()
                    if api.EffacerTournee then pcall(api.EffacerTournee) end
                    suivi.Rendre()
                end })
            end
        end
        local S = NS.suite or _G.CoreSuite
        -- Le parcours affiche entierement fait : Supprimer (il disparait), a
        -- la place de Guider et de l'itineraire, qui n'ont plus rien a faire.
        -- Seulement celui qu'on regarde, jamais un autre.
        local fini
        if pcVue and NS.parcours and moi then
            local f, t = NS.parcours.Avancement(moi, pcVue)
            if t > 0 and f >= t then fini = pcVue end
        end

        if fini then
            local idF, nomF, uidF = fini.id, fini.nom, fini.uid
            table.insert(boutons, { L.ROUTE_DELETE, function()
                if NS.guidage.EstActif("parcours", { uid = uidF }) then S.Arreter("joueur") end
                NS.parcours.Supprimer(NS.ClePersonnage(), idF)
                if type(s.parcoursOuverts) == "table" then s.parcoursOuverts[idF] = nil end
                if NS.carte then NS.carte.Invalider() end
                suivi.Rendre()
            end, string.format(L.ROUTE_DELETE_TIP, nomF or "") })
            pcVue = nil
        end
        if pcVue then
            local pUid = { uid = pcVue.uid }
            local ici = NS.guidage.EstActif("parcours", pUid)
            table.insert(boutons, { ici and L.GUIDE_STOP or L.GUIDE_START,
                function() NS.guidage.Basculer("parcours", pUid) end, L.GUIDE_HELP })
            if ici and S and S.PeutChangerDeGuide and S.PeutChangerDeGuide() then
                table.insert(boutons, { L.GUIDE_SWITCH, function() S.ChangerDeGuide() end, L.GUIDE_SWITCH_HELP })
            end
        elseif s.vue ~= "parcours" then
            -- Le bouton de l'onglet guide un objectif precis : A rendre, toutes
            -- les quetes terminees ; Quetes et Favoris, exactement les quetes
            -- cochees dans l'onglet (aucun bouton sans quete cochee). Arreter
            -- seulement quand c'est ce meme objectif qui est guide.
            local t, params = ObjectifDeLOnglet()
            if t and NS.guidage.EstActif(t, params) then
                table.insert(boutons, { L.GUIDE_STOP, function() NS.guidage.Basculer(false) end, L.GUIDE_HELP })
                if S and S.PeutChangerDeGuide and S.PeutChangerDeGuide() then
                    table.insert(boutons, { L.GUIDE_SWITCH, function() S.ChangerDeGuide() end, L.GUIDE_SWITCH_HELP })
                end
            elseif t == "rendus" and nRendre > 0 then
                table.insert(boutons, { L.GUIDE_START, function() NS.guidage.Lancer("rendus", {}) end,
                    string.format(L.GUIDE_WHAT_TURNIN, nRendre) .. "\n\n" .. L.GUIDE_HELP })
            elseif t == "quetes" then
                table.insert(boutons, { L.GUIDE_START, function() NS.guidage.Lancer("quetes", params) end,
                    string.format(L.GUIDE_WHAT_SEL, #params.ids) .. "\n\n" .. L.GUIDE_HELP })
            end
        end
        if #boutons > 0 then table.insert(rangs, { genre = "boutons", boutons = boutons }) end

        -- Pose des rangs.
        for _, r in ipairs(bilan.rangs) do r:Hide() end
        local yB = -8
        for k, d in ipairs(rangs) do
            local r = bilan:Rang(k)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", bilan, "TOPLEFT", 0, yB)
            r:SetPoint("TOPRIGHT", bilan, "TOPRIGHT", 0, yB)
            r.gauche:Hide() r.droite:Hide()
            for _, b in ipairs(r.boutons) do b:Hide() end
            local hauteur, apres = 14, 3
            if d.genre == "titre" then
                r.gauche:SetFontObject("GameFontNormal")
                r.gauche:ClearAllPoints()
                r.gauche:SetPoint("LEFT", r, "LEFT", 0, 0)
                r.gauche:SetText(d.gauche)
                r.gauche:SetTextColor(1, 0.82, 0)
                r.gauche:Show()
                r.droite:SetText(d.droite or "")
                r.droite:Show()
                hauteur = 15
                if k > 1 then
                    -- Un peu d'air avant chaque titre, sauf le premier.
                    yB = yB - 4
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", bilan, "TOPLEFT", 0, yB)
                    r:SetPoint("TOPRIGHT", bilan, "TOPRIGHT", 0, yB)
                end
            elseif d.genre == "detail" then
                r.gauche:SetFontObject("GameFontHighlightSmall")
                r.gauche:ClearAllPoints()
                r.gauche:SetPoint("LEFT", r, "LEFT", 14, 0)
                r.gauche:SetText(d.texte)
                r.gauche:SetTextColor(d.couleur[1], d.couleur[2], d.couleur[3])
                r.gauche:Show()
            elseif d.genre == "boutons" then
                -- Deux boutons de meme largeur, sur toute la largeur.
                yB = yB - 4
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", bilan, "TOPLEFT", 0, yB)
                r:SetPoint("TOPRIGHT", bilan, "TOPRIGHT", 0, yB)
                -- Deux par rangee ; un troisieme (Supprimer un parcours fini,
                -- par exemple) passe sur une rangee de plus.
                local n = #d.boutons
                for m, info in ipairs(d.boutons) do
                    local b = r.boutons[m] or r.NouveauBouton(m)
                    b:SetText(info[1])
                    b.action, b.aide = info[2], info[3]
                    b:ClearAllPoints()
                    local ligne = math.floor((m - 1) / 2)
                    local yL = -ligne * 24
                    local seul = (m % 2 == 1) and (m == n)
                    if seul then
                        b:SetPoint("TOPLEFT", r, "TOPLEFT", 0, yL)
                        b:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, yL)
                    elseif m % 2 == 1 then
                        b:SetPoint("TOPLEFT", r, "TOPLEFT", 0, yL)
                        b:SetPoint("TOPRIGHT", r, "TOP", -2, yL)
                    else
                        b:SetPoint("TOPLEFT", r, "TOP", 2, yL)
                        b:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, yL)
                    end
                    b:Show()
                end
                local rangees = math.ceil(n / 2)
                hauteur, apres = rangees * 20 + (rangees - 1) * 4, 0
            end
            r:SetHeight(hauteur)
            r:Show()
            yB = yB - hauteur - apres
        end
        bilan.hauteur = -yB + 6
        -- La liste s'arrete au-dessus du bilan, lui-meme au-dessus des
        -- boutons du bas quand il y en a.
        local function BasDeListe(avecBoutons)
            local bas = avecBoutons and 24 or 0
            bilan:ClearAllPoints()
            bilan:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, bas)
            bilan:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, bas)
            -- Le bilan : dans les quatre onglets (A rendre, prochain niveau,
            -- trajet), pour ne pas avoir a changer d'onglet.
            local avecBilan = not s.replie and not s.vuePerso and s.vue ~= "pvp"
            bilan:SetShown(avecBilan)
            local hauteurBilan = avecBilan and math.ceil(bilan.hauteur or 24) or -4
            bilan:SetHeight(hauteurBilan)
            cadre.defilement:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, bas + hauteurBilan + 4)
        end
        pcall(PoserOngletsMembres, s.replie)
        pcall(PoserOngletsVues, s.replie, nParcours)
        if s.vuePerso and not s.replie and NS.groupe and NS.groupe.Etat(s.vuePerso) then
            cadre:SetHeight(math.min(math.max(s.hauteur or HAUTEUR, HAUTEUR_MINI), HauteurMaxi()))
            BasDeListe(false)
            local _, yFin = RendreVueMembre(moi, s.vuePerso, 0, 0)
            corps:SetHeight(math.max(yFin, 1))
            return
        end
        if s.vue == "favoris" and not s.replie then
            cadre:SetHeight(math.min(math.max(s.hauteur or HAUTEUR, HAUTEUR_MINI), HauteurMaxi()))
            BasDeListe(false)
            -- Le rond de la premiere quete deborde au-dessus de sa ligne : un
            -- peu d'air sous le filet, comme sous un titre de zone ailleurs.
            local _, yFin = RendreVueFavoris(moi, 0, 10)
            corps:SetHeight(math.max(yFin, 1))
            return
        end
        if s.vue == "pvp" and not s.replie and _G.PvPCoreAPI then
            cadre:SetHeight(math.min(math.max(s.hauteur or HAUTEUR, HAUTEUR_MINI), HauteurMaxi()))
            BasDeListe(false)
            local _, yFin = RendreVuePvp(0, 0)
            corps:SetHeight(math.max(yFin, 1))
            return
        end
        if s.vue == "parcours" and not s.replie then
            cadre:SetHeight(math.min(math.max(s.hauteur or HAUTEUR, HAUTEUR_MINI), HauteurMaxi()))
            BasDeListe(false)
            local _, yFin = RendreVueParcours(moi, 0, 0)
            corps:SetHeight(math.max(yFin, 1))
            return
        end
        if s.replie then
            -- Replie : la fenetre garde sa bordure entiere, avec une ligne de
            -- resume ; jamais un cadre coupe.
            cadre.resume:SetText(string.format(L.TRACK_SUMMARY, total, nRendre))
            bilan:Hide()
            cadre:SetHeight(HAUTEUR_REPLIE)
            return
        end
        cadre:SetHeight(math.min(math.max(s.hauteur or HAUTEUR, HAUTEUR_MINI), HauteurMaxi()))

        -- Bouton "tout replier / tout deplier", en tete de liste.
        local unOuvert = false
        for _, id in ipairs(ids) do if not s.replies[id] then unOuvert = true break end end
        local tout = cadre.tout
        tout:SetText(unOuvert and L.TRACK_COLLAPSE_ALL or L.TRACK_EXPAND_ALL)
        tout:SetWidth((tout.GetTextWidth and tout:GetTextWidth() or 80) + 24)
        tout:SetScript("OnClick", function()
            for _, id in ipairs(ids) do s.replies[id] = unOuvert or nil end
            suivi.Rendre()
        end)
        tout:SetShown(#ids > 0)
        cadre.trier:SetText(L["TRACK_SORT_" .. (TRIS[s.tri] and s.tri or "difficulte")])
        cadre.trier:SetShown(#ids > 1)
        -- Selections nettoyees : une quete rendue, abandonnee ou echouee n'y
        -- reste pas.
        for _, onglet in ipairs({ "quetes", "favoris" }) do
            local sel = Selection(onglet)
            for id in pairs(sel) do
                if not (quetes[id] and quetes[id].complete ~= -1) then sel[id] = nil end
            end
        end
        -- Plus de bouton Carte / Trajet ici : le bouton Guider du bilan fait tout.
        cadre.voirCarte:SetShown(false)
        cadre.voirCarte:SetText(L.TRACK_MAP_SHORT)
        cadre.voirCarte:SetWidth((cadre.voirCarte.GetTextWidth and cadre.voirCarte:GetTextWidth() or 80) + 24)
        -- Rangee du bas alignee sur toute la largeur : "Tout replier" et le
        -- bouton de carte a leur taille, le tri prend la place entre les deux.
        local voirCarte, trier = cadre.voirCarte, cadre.trier
        voirCarte:ClearAllPoints()
        voirCarte:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
        trier:ClearAllPoints()
        trier:SetPoint("LEFT", tout, "RIGHT", 4, 0)
        if voirCarte:IsShown() then trier:SetPoint("RIGHT", voirCarte, "LEFT", -4, 0)
        else trier:SetPoint("RIGHT", cadre.zone, "RIGHT", 0, 0) end

        BasDeListe(#ids > 0)
        local index, y = 0, 0
        -- Suites en attente : la quete d'avant rendue, la suivante pas encore
        -- prise ; la suite reste visible, en tete.
        if not filtre and moi then
            local attente = ChainesEnAttente()
            local premiere = true
            for idS in pairs(attente) do
                if (moi.faites and moi.faites[idS]) or quetes[idS] then
                    attente[idS] = nil
                elseif not dejaRendues[idS] then
                    if premiere then
                        premiere = false
                        index = index + 1
                        y = Poser(index, y, L.TRACK_CHAINS, { police = "GameFontNormal", couleur = { 1, 0.82, 0 }, uneLigne = true, apres = 2 })
                    end
                    index, y = RendreAvecChaine(moi, quetes, idS, index, y)
                end
            end
        end
        if #ids == 0 then
            index = index + 1
            y = Poser(index, y, filtre and L.TURNIN_NONE or L.TRACK_NONE, { couleur = { 0.6, 0.6, 0.6 } })
        end

        -- Rubriques : par zone, comme le journal du jeu (dans chaque zone, les
        -- quetes a rendre d'abord) ; ou par etat, a rendre puis en cours.
        local rubriques = {}
        if s.regroupement == "etat" then
            rubriques = { { cle = "rendre", titre = L.TRACK_SECTION_DONE, ids = {} },
                { cle = "cours", titre = L.TRACK_SECTION_ACTIVE, ids = {} } }
            for _, id in ipairs(ids) do
                table.insert(quetes[id].complete == true and rubriques[1].ids or rubriques[2].ids, id)
            end
        else
            -- Quetes de donjon ou de raid : une rubrique par instance, apres
            -- les zones ("Donjon : Les Mortemines").
            local parZone = {}
            for _, id in ipairs(ids) do
                local q = quetes[id]
                local zone, instance = q.zone or L.ZONE_OTHER, nil
                if q.instance then
                    instance = true
                    zone = string.format(q.genreInstance == "raid" and L.TRACK_RAID or L.TRACK_DUNGEON, q.instance)
                end
                if not parZone[zone] then
                    parZone[zone] = { cle = "z:" .. zone, titre = zone, ids = {}, instance = instance }
                    table.insert(rubriques, parZone[zone])
                end
                table.insert(parZone[zone].ids, id)
            end
            table.sort(rubriques, function(a, b)
                if (a.instance == true) ~= (b.instance == true) then return not a.instance end
                return a.titre < b.titre
            end)
        end

        local parZoneBilan
        if s.regroupement ~= "etat" and NS.histoire and moi then
            local ok, liste = pcall(NS.histoire.Bilan, moi, true)
            if ok then
                parZoneBilan = {}
                for _, z in ipairs(liste) do parZoneBilan[z.nom] = z end
            end
        end
        -- La zone ou l'on se trouve : "Vous etes ici" sous son en-tete. Si
        -- aucune quete du journal n'y est, une ligne en tete de liste.
        local zoneIci = NS.Appeler(NS.Lecture("GetRealZoneText"))
        local zoneIciCourte = NomDeZoneCourt(zoneIci)
        -- Sous l'en-tete de zone : "Vous etes ici" (en vert, en tete) puis l'XP,
        -- sur une seule ligne ; l'en-tete garde le nom de zone seul.
        local function LigneZone(bilan, xpEnCours, ici)
            local morceaux = {}
            if ici then table.insert(morceaux, "|cff4fd16a" .. L.TRACK_HERE .. "|r") end
            if xpEnCours and xpEnCours > 0 then
                table.insert(morceaux, string.format(L.TRACK_LOG_XP, NS.ref.NombreLisible(xpEnCours)))
            end
            local reste = bilan and NS.histoire.XPRestante(moi, bilan) or 0
            if reste > 0 then table.insert(morceaux, string.format(L.TRACK_ZONE_XP, NS.ref.NombreLisible(reste))) end
            if #morceaux == 0 then return end
            index = index + 1
            y = Poser(index, y, table.concat(morceaux, "     "), { retrait = 18, couleur = { 0.8, 0.8, 0.8 },
                police = "GameFontNormalSmall", petit = true, uneLigne = true, apres = 6 })
        end
        if s.regroupement ~= "etat" and zoneIci then
            local presente = false
            for _, rubrique in ipairs(rubriques) do
                if NomDeZoneCourt(rubrique.titre) == zoneIciCourte then presente = true end
            end
            if not presente and not filtre then
                index = index + 1
                y = Poser(index, y, zoneIciCourte,
                    { police = "GameFontNormal", couleur = { 1, 0.82, 0 }, zone = true, apres = 2, uneLigne = true })
                LigneZone(parZoneBilan and parZoneBilan[zoneIci], 0, true)
                y = y + 4
            end
        end
        local premiereZone = 0
        for _, rubrique in ipairs(rubriques) do
            if #rubrique.ids > 0 then
                local fermee = s.sections[rubrique.cle] == true
                local cleRubrique = rubrique.cle
                -- Avancement de la zone (Mon histoire) : quetes rendues / possibles.
                local bilan = parZoneBilan and parZoneBilan[rubrique.titre]
                local droite, couleurDroite
                if bilan then
                    droite = string.format(L.TRACK_ZONE_PROGRESS, bilan.faites, bilan.total, bilan.pct)
                    couleurDroite = bilan.pct >= 100 and { 0.31, 0.82, 0.41 } or { 0.8, 0.8, 0.8 }
                end
                -- Nom de zone seul (sans le second nom), "Vous etes ici" a cote.
                local ici = s.regroupement ~= "etat" and zoneIciCourte ~= nil
                    and NomDeZoneCourt(rubrique.titre) == zoneIciCourte
                index = index + 1
                premiereZone = premiereZone + 1
                y = Poser(index, y, NomDeZoneCourt(rubrique.titre) .. " (" .. #rubrique.ids .. ")", {
                    police = "GameFontNormal", couleur = { 1, 0.82, 0 }, zone = true, uneLigne = true,
                    separateur = premiereZone > 1 or index > 1,
                    droite = droite, couleurDroite = couleurDroite,
                    marqueTexture = fermee and "Interface\\Buttons\\UI-PlusButton-Up"
                        or "Interface\\Buttons\\UI-MinusButton-Up",
                    auClic = function()
                        s.sections[cleRubrique] = not s.sections[cleRubrique] or nil
                        suivi.Rendre()
                    end, apres = (s.regroupement ~= "etat") and 2 or 6 })
                if s.regroupement ~= "etat" then
                    local xpEnCours = 0
                    for _, id in ipairs(rubrique.ids) do
                        local r = quetes[id].recompenses
                        xpEnCours = xpEnCours + (r and tonumber(r.xp) or 0)
                    end
                    LigneZone(bilan, xpEnCours, ici)
                end
                if not fermee then
                    for _, id in ipairs(rubrique.ids) do
                        index, y = RendreAvecChaine(moi, quetes, id, index, y)
                    end
                end
                y = y + 4
            end
        end
        corps:SetHeight(math.max(y, 1))
    end)
    if not ok then NS.base.NoterIncident("suivi", souci) end
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local SuiviRecolte, Fondre, MemeOpacite

-- Le suivi est tenu par son coin BAS gauche : deplie ou agrandi, il
-- s'ouvre vers le haut et son bas reste ou on l'a pose.
local function TenirParLeBas()
    local gauche, bas = cadre:GetLeft(), cadre:GetBottom()
    if not gauche or not bas then return end
    local s = Reglages()
    cadre:ClearAllPoints()
    cadre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", gauche, bas)
    s.point, s.pointRelatif, s.x, s.y = "BOTTOMLEFT", "BOTTOMLEFT", gauche, bas
end

local function Enregistrer()
    local s = Reglages()
    if not (s.souder and SuiviRecolte() and s.ordre ~= "quetes") then
        TenirParLeBas()
    end
    -- Une hauteur trop petite (ancienne borne) n'est jamais gardee.
    if not s.replie and (cadre:GetHeight() or 0) >= HAUTEUR_MINI then s.hauteur = cadre:GetHeight() end
end

-- ---------------------------------------------------------------------------
-- Soudure au suivi de recolte de CraftCore
-- ---------------------------------------------------------------------------
-- Les deux suivis ont la meme largeur : soudes, celui des quetes se pose
-- juste sous celui de la recolte et le suit quand on le deplace. Rien n'est
-- change dans CraftCore : on s'accroche a sa fenetre telle qu'elle est.

SuiviRecolte = function()
    local cc = _G.CraftCoreSuivi
    if type(cc) == "table" and cc.GetObjectType then return cc end
    return nil
end

function suivi.CraftCorePresent()
    return type(CraftCoreDB) == "table" or SuiviRecolte() ~= nil
end

local function Soude()
    return Reglages().souder == true and SuiviRecolte() ~= nil
end

local function PlacerSelonReglages()
    local s = Reglages()
    cadre:ClearAllPoints()
    if s.point then
        cadre:SetPoint(s.point, UIParent, s.pointRelatif or s.point, s.x or 0, s.y or 0)
    else
        cadre:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240)
    end
    -- Ancienne position (haut, centre...) : convertie une fois par le bas.
    if s.point ~= "BOTTOMLEFT" then pcall(TenirParLeBas) end
end

-- Ecart entre les deux suivis soudes : bord contre bord, sans chevauchement.
local JOINT = 4

local function RecolteEnHaut() return Reglages().ordre ~= "quetes" end

-- La recolte rendue a sa propre place, notee dans CraftCore par sa fin de glisser.
local function LibererRecolte(cc)
    local gauche, haut = cc:GetLeft(), cc:GetTop()
    if not gauche or not haut then return end
    cc:ClearAllPoints()
    cc:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gauche, haut)
    local fin = cc:GetScript("OnDragStop")
    if fin then pcall(fin, cc) end
end

-- Hauteur la plus grande possible pour le suivi des quetes : soude, la
-- recolte dessous doit rester entiere a l'ecran ; sinon le bas de l'ecran.
-- (Le cadre de la recolte est retenu a l'ecran par CraftCore : sans cette
-- borne, les quetes grandissaient par-dessus.)
HauteurMaxi = function()
    local maxi = 900
    if not cadre then return maxi end
    -- Tenu par le bas, il grandit vers le haut : la place, c'est du bas du
    -- suivi jusqu'en haut de l'ecran.
    local bas = cadre:GetBottom()
    local hautEcran = UIParent:GetTop()
    if not bas or not hautEcran then return maxi end
    hautEcran = hautEcran * (UIParent:GetEffectiveScale() or 1) / (cadre:GetEffectiveScale() or 1)
    return math.max(HAUTEUR_MINI, math.min(maxi, math.floor(hautEcran - bas)))
end

-- Ramene le suivi a la hauteur permise (sans toucher a la hauteur choisie,
-- qui revient d'elle-meme quand la place le permet).
local function Borner()
    if not cadre or Reglages().replie then return end
    local maxi = HauteurMaxi()
    if (cadre:GetHeight() or 0) > maxi + 0.5 then cadre:SetHeight(maxi) end
end

local function Placer()
    if not cadre then return end
    local cc = SuiviRecolte()
    if Reglages().souder and cc then
        if RecolteEnHaut() then
            -- Recolte en haut : les quetes dessous ; recolte masquee, a sa place.
            cadre:ClearAllPoints()
            if cc:IsShown() then
                cadre:SetPoint("TOPLEFT", cc, "BOTTOMLEFT", 0, -JOINT)
            else
                cadre:SetPoint("TOPLEFT", cc, "TOPLEFT", 0, 0)
            end
        else
            -- Quetes en haut : elles gardent leur place, la recolte dessous.
            PlacerSelonReglages()
            cc:ClearAllPoints()
            cc:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 0, -JOINT)
            Borner()
        end
    else
        PlacerSelonReglages()
    end
end
suivi.Placer = Placer

-- La fenetre de recolte peut naitre apres la notre : on s'y accroche des
-- qu'elle existe, une seule fois.
local accrochee
local function Accrocher()
    local cc = SuiviRecolte()
    if not cc or accrochee == cc then return end
    accrochee = cc
    cc:HookScript("OnShow", Placer)
    cc:HookScript("OnHide", Placer)
    -- La recolte grandit (une ressource de plus) : les quetes se reduisent.
    cc:HookScript("OnSizeChanged", function() pcall(Borner) end)
    -- Quetes en haut : saisir la recolte deplace toute la colonne, par le haut.
    cc:HookScript("OnDragStart", function(self)
        if Reglages().souder and not RecolteEnHaut() and cadre then
            if NS.suite and NS.suite.Libre and not NS.suite.Libre("QuestCoreSuivi") then
                self:StopMovingOrSizing()
                return
            end
            self:StopMovingOrSizing()
            cadre:StartMoving()
            cadre.porteParRecolte = true
        end
    end)
    cc:HookScript("OnDragStop", function()
        if cadre and cadre.porteParRecolte then
            cadre.porteParRecolte = nil
            cadre:StopMovingOrSizing()
            Enregistrer()
        end
        Placer()
    end)
    Placer()
end

-- Position actuelle notee comme position propre, pour qu'un suivi dessoude
-- reste la ou il est.
local function NoterPositionAbsolue()
    local gauche, haut = cadre:GetLeft(), cadre:GetTop()
    if not gauche or not haut then return end
    local s = Reglages()
    s.point, s.pointRelatif, s.x, s.y = "TOPLEFT", "BOTTOMLEFT", gauche, haut
end

function suivi.Souder(oui)
    local s = Reglages()
    local cc = SuiviRecolte()
    if cadre and s.souder and not oui then
        NoterPositionAbsolue()
        if cc and not RecolteEnHaut() then LibererRecolte(cc) end
    end
    s.souder = oui and true or false
    Accrocher()
    Placer()
end

-- Ordre de la colonne : "recolte" (recolte en haut) ou "quetes".
function suivi.Ordre(ordre)
    local s = Reglages()
    local cc = SuiviRecolte()
    if cadre and s.souder and cc then
        if ordre == "quetes" and RecolteEnHaut() then
            -- Les quetes prennent la place du haut de la colonne.
            local gauche, haut = cc:GetLeft(), cc:GetTop()
            if gauche and haut then s.point, s.pointRelatif, s.x, s.y = "TOPLEFT", "BOTTOMLEFT", gauche, haut end
        elseif ordre ~= "quetes" and not RecolteEnHaut() then
            -- La recolte reprend la place du haut.
            local gauche, haut = cadre:GetLeft(), cadre:GetTop()
            if gauche and haut then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gauche, haut)
                local fin = cc:GetScript("OnDragStop")
                if fin then pcall(fin, cc) end
            end
        end
    end
    s.ordre = (ordre == "quetes") and "quetes" or "recolte"
    Placer()
end

-- Centre a l'ecran le suivi, ou la colonne des deux suivis s'ils sont soudes.
function suivi.Centrer()
    if not cadre then return end
    local cc = SuiviRecolte()
    if Soude() then
        local hauteur = cadre:GetHeight() or 0
        if cc:IsShown() then hauteur = hauteur + (cc:GetHeight() or 0) + JOINT end
        if RecolteEnHaut() then
            cc:ClearAllPoints()
            cc:SetPoint("TOP", UIParent, "CENTER", 0, hauteur / 2)
            -- Sa propre fin de glisser enregistre sa position dans CraftCore.
            local fin = cc:GetScript("OnDragStop")
            if fin then pcall(fin, cc) end
        else
            cadre:ClearAllPoints()
            cadre:SetPoint("TOP", UIParent, "CENTER", 0, hauteur / 2)
            local s = Reglages()
            local point, _, pointRelatif, x, y = cadre:GetPoint(1)
            s.point, s.pointRelatif, s.x, s.y = point, pointRelatif, x, y
        end
        Placer()
    else
        cadre:ClearAllPoints()
        cadre:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        local s = Reglages()
        local point, _, pointRelatif, x, y = cadre:GetPoint(1)
        s.point, s.pointRelatif, s.x, s.y = point, pointRelatif, x, y
    end
end

local function Construire()
    local s = Reglages()
    -- La meme fenetre que le suivi de recolte de CraftCore, a la meme largeur :
    -- l'une au-dessus de l'autre, elles forment une colonne harmonisee.
    cadre = NS.charte.Fenetre("QuestCoreSuivi", LARGEUR, s.hauteur or HAUTEUR,
        { portrait = false, strate = "MEDIUM", sansPied = true })
    cadre:HookScript("OnShow", function() if suivi.RangerQuestie then pcall(suivi.RangerQuestie) end end)
    cadre:HookScript("OnHide", function() if suivi.RangerQuestie then pcall(suivi.RangerQuestie) end end)
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
    reglages:SetScript("OnClick", function() if NS.fenetre and NS.fenetre.OuvrirReglages then NS.fenetre.OuvrirReglages() end end)
    cadre.boutonReglages = reglages
    cadre:ClearAllPoints()
    if s.point then
        cadre:SetPoint(s.point, UIParent, s.pointRelatif or s.point, s.x or 0, s.y or 0)
    else
        cadre:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240)
    end
    cadre:SetResizable(true)
    if cadre.SetResizeBounds then
        cadre:SetResizeBounds(LARGEUR, HAUTEUR_MINI, LARGEUR, 900)
    elseif cadre.SetMinResize then
        cadre:SetMinResize(LARGEUR, 90)
        cadre:SetMaxResize(LARGEUR, 900)
    end
    -- Soude, on deplace la colonne entiere : c'est la recolte qui bouge.
    cadre:SetScript("OnDragStart", function(self)
        -- Ancre : ne bouge qu'en mode Edition du jeu.
        if NS.suite and NS.suite.Libre and not NS.suite.Libre("QuestCoreSuivi") then return end
        local cc = SuiviRecolte()
        if Soude() and RecolteEnHaut() then
            local debut = cc:GetScript("OnDragStart")
            if debut then pcall(debut, cc) else pcall(cc.StartMoving, cc) end
        else
            self:StartMoving()
        end
    end)
    cadre:SetScript("OnDragStop", function(self)
        local cc = SuiviRecolte()
        if Soude() and RecolteEnHaut() then
            local fin = cc:GetScript("OnDragStop")
            if fin then pcall(fin, cc) else pcall(cc.StopMovingOrSizing, cc) end
            Placer()
        else
            self:StopMovingOrSizing()
            Enregistrer()
            Placer()
        end
    end)
    -- Ancrage et mode Edition du jeu (voir la suite) : quand l'etat change,
    -- le rendu montre ou cache la poignee (pas pendant la construction).
    if NS.suite and NS.suite.Ancrable then
        pcall(NS.suite.Ancrable, "QuestCoreSuivi", cadre, L.TRACK_EDIT_LABEL, function()
            if cadre.replier then suivi.Rendre() end
        end)
    end
    cadre.fermer:SetScript("OnClick", function()
        Reglages().afficher = false
        cadre:Hide()
    end)

    -- Dans la barre de titre, a gauche de la croix : replier, ouvrir QuestCore.
    -- Au niveau de la croix : sinon la barre de titre les recouvre a pleine opacite.
    local niveauTitre = (cadre.fermer:GetFrameLevel() or cadre:GetFrameLevel()) + 1
    local replier = CreateFrame("Button", nil, cadre)
    replier:SetFrameLevel(niveauTitre)
    replier:SetSize(16, 16)
    replier:SetPoint("RIGHT", cadre.fermer, "LEFT", -2, 0)
    replier:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    replier:SetScript("OnClick", function()
        local r = Reglages()
        if not r.replie then Enregistrer() end
        r.replie = not r.replie
        suivi.Rendre()
    end)
    cadre.replier = replier

    local ouvrir = CreateFrame("Button", nil, cadre)
    ouvrir:SetFrameLevel(niveauTitre)
    ouvrir:SetSize(16, 16)
    ouvrir:SetPoint("RIGHT", replier, "LEFT", -4, 0)
    ouvrir:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_08")
    ouvrir:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ouvrir:SetScript("OnClick", function() NS.fenetre.Basculer() end)
    ouvrir:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.TRACK_OPEN_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    ouvrir:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Ligne de resume, montree quand le suivi est replie.
    local resume = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resume:SetPoint("LEFT", cadre.zone, "LEFT", 2, 0)
    resume:SetPoint("RIGHT", cadre.zone, "RIGHT", -2, 0)
    resume:SetJustifyH("LEFT")
    resume:Hide()
    cadre.resume = resume

    -- Corps defilant a la molette, dans la zone de la charte.
    -- Entre la rangee d'onglets (en haut) et celle des boutons (en bas) :
    -- les deux restent en place, seule la liste defile.
    local defilement = CreateFrame("ScrollFrame", nil, cadre)
    defilement:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -HAUT_ONGLETS)
    defilement:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    defilement:EnableMouseWheel(true)
    defilement:SetScript("OnMouseWheel", function(self, sens)
        local maximum = math.max(0, (cadre.corps:GetHeight() or 0) - (self:GetHeight() or 0))
        local cible = math.max(0, math.min(maximum, (self:GetVerticalScroll() or 0) - sens * 24))
        self:SetVerticalScroll(cible)
    end)
    local corps = CreateFrame("Frame", nil, defilement)
    corps:SetSize(LARGEUR - 2 * NS.charte.MARGE - 10, 1)
    defilement:SetScrollChild(corps)
    cadre.defilement = defilement
    cadre.corps = corps

    -- En bas : Tout replier, puis Voir sur la carte, alignes a gauche ; la
    -- poignee reste seule dans le coin.
    local tout = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    tout:SetHeight(20)
    tout:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    cadre.tout = tout

    -- Bilan de ce qu'il y a a rendre, au-dessus des boutons : un filet, puis
    -- "A rendre : 3 quetes   1 250 XP   2 po", dans tous les onglets.
    -- Bilan du bas : un petit tableau aligne (libelle, quetes, XP, argent),
    -- et de vrais boutons la ou l'on peut agir.
    local bilan = CreateFrame("Frame", nil, cadre)
    bilan:SetHeight(20)
    bilan.filet = bilan:CreateTexture(nil, "ARTWORK")
    bilan.filet:SetHeight(1)
    bilan.filet:SetPoint("TOPLEFT", bilan, "TOPLEFT", 0, 0)
    bilan.filet:SetPoint("TOPRIGHT", bilan, "TOPRIGHT", 0, 0)
    bilan.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35)
    bilan.rangs = {}
    -- Rangs a la maniere du suivi : un titre en dore (avec une valeur a
    -- droite, comme le pourcentage d'une zone), une ligne de detail en petit,
    -- et une rangee de deux boutons de meme largeur.
    function bilan.Rang(self, rang)
        local r = self.rangs[rang]
        if r then return r end
        r = CreateFrame("Frame", nil, self)
        r:SetHeight(16)
        r.gauche = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.gauche:SetJustifyH("LEFT")
        r.gauche:SetWordWrap(false)
        r.droite = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.droite:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.droite:SetJustifyH("RIGHT")
        r.boutons = {}
        function r.NouveauBouton(k)
            local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
            b:SetHeight(20)
            -- Guider, Itineraire detaille... : une fois clique, l'infobulle
            -- s'efface (et ne revient qu'en revenant sur le bouton).
            b:SetScript("OnClick", function(x)
                x.muet = true
                GameTooltip:Hide()
                if x.action then x.action() end
            end)
            b:SetScript("OnEnter", function(x)
                if not x.aide or x.muet then return end
                GameTooltip:SetOwner(x, "ANCHOR_TOP")
                GameTooltip:SetText(x:GetText() or "", 1, 0.82, 0)
                GameTooltip:AddLine(x.aide, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function(x) x.muet = nil GameTooltip:Hide() end)
            r.boutons[k] = b
            return b
        end
        for k = 1, 2 do r.NouveauBouton(k) end
        self.rangs[rang] = r
        return r
    end
    cadre.bilan = bilan

    -- Tri : un clic passe au suivant, un clic droit revient au precedent.
    local trier = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    trier:SetSize(96, 20)
    trier:SetPoint("LEFT", tout, "RIGHT", 4, 0)
    trier:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    trier:SetScript("OnClick", function(_, bouton)
        local s = Reglages()
        local rang = TRIS[s.tri] or 1
        rang = rang + (bouton == "RightButton" and -1 or 1)
        if rang < 1 then rang = #ORDRE_TRIS elseif rang > #ORDRE_TRIS then rang = 1 end
        s.tri = ORDRE_TRIS[rang]
        suivi.Rendre()
    end)
    trier:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TRACK_SORT_TITLE, 1, 0.82, 0)
        for _, cle in ipairs(ORDRE_TRIS) do
            local choisi = (Reglages().tri or "difficulte") == cle
            GameTooltip:AddLine((choisi and "> " or "   ") .. L["TRACK_SORT_LONG_" .. cle], choisi and 0.31 or 1,
                choisi and 0.82 or 1, choisi and 0.41 or 1)
        end
        GameTooltip:AddLine(L.TRACK_SORT_HELP, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    trier:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cadre.trier = trier

    local voirCarte = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    voirCarte:SetHeight(20)
    voirCarte:SetPoint("LEFT", trier, "RIGHT", 4, 0)
    voirCarte:SetText(L.TRACK_MAP_SHORT)
    voirCarte:SetWidth((voirCarte.GetTextWidth and voirCarte:GetTextWidth() or 80) + 24)
    -- La carte de QuestCore (le bouton reste cache : Guider fait tout).
    voirCarte:SetScript("OnClick", function()
        if NS.fenetre and NS.fenetre.OuvrirCarte then NS.fenetre.OuvrirCarte() end
    end)
    voirCarte:Hide()
    cadre.voirCarte = voirCarte

    -- Deux onglets en tete : toutes les quetes, ou un parcours seul.
    cadre.vues = {}
    local precedent
    -- Quatre onglets en boutons ronds, comme les filtres sous les cartes de la
    -- suite : l'icone du jeu et un compte a cote, le nom en infobulle. Celui
    -- qui est affiche est en couleur, les autres en gris.
    local largeurZone = LARGEUR - 2 * NS.charte.MARGE - 10
    -- Les parcours ont leur onglet lateral (Itineraire), en bas a gauche.
    local pas = math.floor(largeurZone / 3)
    -- Un onglet rond du haut : icone du jeu, compte a cote, nom au survol.
    local function OngletRond(rang, v)
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
        if not (v[3] and b.image.SetAtlas and pcall(b.image.SetAtlas, b.image, v[3]) and b.image:GetAtlas()) then
            b.image:SetTexture(v[4])
        end
        if v[5] and b.image.SetMask then pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        b.anneau = b:CreateTexture(nil, "OVERLAY")
        b.anneau:SetSize(41, 41)
        b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        b.compte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.compte:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.nom = v[2]
        -- Compte a cote de l'icone ; "choisi" : l'onglet affiche.
        function b.Compter(self, texte) self.compte:SetText(tostring(texte or "")) end
        b.ongletPilote = 2
        function b.Choisir(self, oui)
            self.choisi = oui and true or nil
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
        return b
    end
    for rang, v in ipairs({
        { "quetes", L.TRACK_TAB_QUESTS, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" },
        { "rendre", L.TRACK_TAB_TURNIN, "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" },
        { "favoris", L.TRACK_TAB_FAV, nil, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" } }) do
        local b = OngletRond(rang, v)
        local cle = v[1]
        b:SetScript("OnClick", function()
            -- "A rendre" est le filtre partage avec la fenetre et la carte.
            -- Un onglet du haut ramene toujours a ses propres quetes.
            Reglages().vuePerso = nil
            if cle == "parcours" or cle == "favoris" then
                Reglages().vue = cle
                suivi.Rendre()
            else
                Reglages().vue = "quetes"
                NS.base.PoserFiltreARendre(cle == "rendre")
            end
        end)
        b.vue = cle
        cadre.vues[cle] = b
    end
    -- Onglet Itineraire : trois sortes de trajets, comme les trois onglets
    -- des quetes. Divers (niveau, rendu, suites), recolte (la tournee de
    -- MapCore) et donjons (prerequis).
    cadre.vuesRoute = {}
    for rang, v in ipairs({
        { "divers", L.TRACK_ROUTE_MISC, nil, "Interface\\Icons\\INV_Misc_Map_01", true },
        { "recolte", L.TRACK_ROUTE_FARM, nil, "Interface\\Icons\\Trade_Herbalism", true },
        { "donjons", L.TRACK_ROUTE_DUNGEON, "Dungeon", "Interface\\Minimap\\Dungeon" } }) do
        local b = OngletRond(rang, v)
        local cle = v[1]
        b:SetScript("OnClick", function()
            Reglages().routeCategorie = cle
            suivi.Rendre()
        end)
        b:Hide()
        cadre.vuesRoute[cle] = b
    end
    -- Filet sous les onglets, puis de l'air avant la liste.
    local filetHaut = cadre:CreateTexture(nil, "ARTWORK")
    filetHaut:SetHeight(1)
    filetHaut:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -HAUT_ONGLETS + 6)
    filetHaut:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", 0, -HAUT_ONGLETS + 6)
    filetHaut:SetColorTexture(0.8, 0.65, 0.35, 0.35)
    cadre.filetHaut = filetHaut

    -- Poignee du coin, celle des fenetres de discussion du jeu.
    local poignee = CreateFrame("Button", nil, cadre)
    poignee:SetSize(14, 14)
    poignee:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -4, 4)
    poignee:SetFrameLevel(cadre:GetFrameLevel() + 10)
    poignee:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    poignee:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    poignee:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- La taille reste toujours reglable, meme ancre : l'ancrage fige la place.
    poignee:SetScript("OnMouseDown", function()
        -- Vers le bas : pas plus bas que le bas de l'ecran.
        local haut = cadre:GetTop() or 900
        local maxi = math.max(HAUTEUR_MINI, math.min(900, math.floor(haut)))
        if cadre.SetResizeBounds then cadre:SetResizeBounds(LARGEUR, HAUTEUR_MINI, LARGEUR, maxi)
        elseif cadre.SetMaxResize then cadre:SetMaxResize(LARGEUR, maxi) end
        cadre:StartSizing("BOTTOMRIGHT")
    end)
    poignee:SetScript("OnMouseUp", function()
        cadre:StopMovingOrSizing()
        Enregistrer()
        Placer()
        suivi.Rendre()
    end)
    cadre.poignee = poignee

    -- La meme poignee en haut a gauche : agrandit vers le haut (le bas du
    -- suivi reste en place). Indispensable quand il est pose en bas d'ecran.
    local poigneeHaut = CreateFrame("Button", nil, cadre)
    poigneeHaut:SetSize(14, 14)
    poigneeHaut:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -4)
    poigneeHaut:SetFrameLevel(cadre:GetFrameLevel() + 10)
    for _, etat in ipairs({ { "SetNormalTexture", "Up" }, { "SetHighlightTexture", "Highlight" },
        { "SetPushedTexture", "Down" } }) do
        poigneeHaut[etat[1]](poigneeHaut, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-" .. etat[2])
    end
    -- Image retournee : la pointe vers le coin haut gauche.
    for _, t in ipairs({ poigneeHaut:GetNormalTexture(), poigneeHaut:GetHighlightTexture(), poigneeHaut:GetPushedTexture() }) do
        if t then t:SetTexCoord(1, 0, 1, 0) end
    end
    poigneeHaut:SetScript("OnMouseDown", function()
        local maxi = HauteurMaxi()
        if cadre.SetResizeBounds then cadre:SetResizeBounds(LARGEUR, HAUTEUR_MINI, LARGEUR, maxi)
        elseif cadre.SetMaxResize then cadre:SetMaxResize(LARGEUR, maxi) end
        cadre:StartSizing("TOPLEFT")
    end)
    poigneeHaut:SetScript("OnMouseUp", poignee:GetScript("OnMouseUp"))
    cadre.poigneeHaut = poigneeHaut
end

-- ---------------------------------------------------------------------------
-- Visibilite : selon qu'on se deplace, qu'on combat, qu'on survole le suivi.
-- Le passage d'une opacite a l'autre est progressif.
-- ---------------------------------------------------------------------------

local function Cible(survole)
    local s = Reglages()
    if survole then return s.alphaSurvol end
    local enCombat = NS.Appeler(UnitAffectingCombat, "player")
    if enCombat then
        if s.modeCombat == "cache" then return 0 end
        if s.modeCombat == "estompe" then return s.alphaMouvement end
    end
    local vitesse = NS.Appeler(GetUnitSpeed, "player") or 0
    -- En combat, le jeu peut rendre une valeur secrete : on ne s'en sert pas.
    if _G.issecretvalue and _G.issecretvalue(vitesse) then vitesse = 0 end
    -- En vol (maitre de vol, monture volante) : le suivi reste lisible.
    local enVol = (NS.Appeler(UnitOnTaxi, "player")) or (_G.IsFlying and NS.Appeler(_G.IsFlying))
    if vitesse > 0 and not enVol then return s.alphaMouvement end
    if s.modeRepos == "survol" then return s.alphaMouvement end
    return s.alphaRepos
end

local cumul = 0
local guet = 0
-- Environ un tiers de seconde pour passer d'une opacite a l'autre.
Fondre = function(f, cible, pas)
    local actuel = f:GetAlpha() or 1
    if math.abs(actuel - cible) < 0.01 then return end
    local vitesse = 3 * pas
    if actuel < cible then actuel = math.min(cible, actuel + vitesse) else actuel = math.max(cible, actuel - vitesse) end
    f:SetAlpha(actuel)
end

-- Opacite de la recolte reglee par QuestCore : sa propre regle (estompee en
-- course) est mise de cote, et rendue des que l'option est coupee ou que le
-- suivi des quetes se ferme.
local reglePropre
MemeOpacite = function()
    local cc = SuiviRecolte()
    if not cc then return nil end
    if Reglages().memeOpacite and cadre and cadre:IsShown() then
        if not reglePropre then
            reglePropre = cc:GetScript("OnUpdate") or false
            cc:SetScript("OnUpdate", nil)
        end
        return cc
    end
    if reglePropre ~= nil then
        if reglePropre then cc:SetScript("OnUpdate", reglePropre) end
        reglePropre = nil
    end
    return nil
end
suivi.MemeOpacite = MemeOpacite

local function SurMiseAJour(_, ecoule)
    -- La fenetre de recolte de CraftCore peut apparaitre plus tard.
    guet = guet + (ecoule or 0)
    if guet > 1 then
        guet = 0
        if Reglages().souder and not accrochee then Accrocher() end
    end
    cumul = cumul + (ecoule or 0)
    if cumul < 0.05 then return end
    local pas = cumul
    cumul = 0
    -- Memes regles pour le suivi de recolte de CraftCore, si demande. Soudes,
    -- les deux suivis ne font qu'un au survol.
    local cc = MemeOpacite()
    local survol = cadre:IsMouseOver()
    local survolRecolte = cc and cc:IsShown() and cc:IsMouseOver()
    if Soude() then survol = survol or survolRecolte survolRecolte = survol end
    Fondre(cadre, Cible(survol), pas)
    if cc then Fondre(cc, Cible(survolRecolte), pas) end
end

-- Reapplique taille de texte et opacite apres un changement de reglage.
function suivi.Appliquer()
    if not cadre then return end
    cadre:SetAlpha(Cible())
    suivi.Rendre()
end

-- Suivi des quetes du jeu, masque sur demande. On le cache et on le recache
-- s'il revient ; rien n'est remplace. Jamais en combat.
local SUIVIS_DU_JEU = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local suivisAccroches = {}

local function MasquerSiDemande(f)
    if not Reglages().masquerNatif then return end
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(f.Hide, f)
end

function suivi.AppliquerNatif()
    for _, nom in ipairs(SUIVIS_DU_JEU) do
        local f = _G[nom]
        if type(f) == "table" and f.Hide then
            if not suivisAccroches[f] then
                suivisAccroches[f] = true
                pcall(f.HookScript, f, "OnShow", MasquerSiDemande)
            end
            if Reglages().masquerNatif then
                MasquerSiDemande(f)
            elseif not (InCombatLockdown and InCombatLockdown()) then
                pcall(f.Show, f)
            end
        end
    end
end

function suivi.MasquerNatif(oui)
    Reglages().masquerNatif = oui and true or false
    suivi.AppliquerNatif()
end

function suivi.Installer()
    if cadre then return end
    pcall(suivi.AppliquerNatif)
    Construire()
    Accrocher()
    Placer()
    cadre:SetScript("OnUpdate", SurMiseAJour)
    -- Suivi des quetes ferme : la recolte reprend sa propre regle d'opacite.
    cadre:HookScript("OnHide", function() pcall(MemeOpacite) end)
    if Reglages().afficher then cadre:Show() else cadre:Hide() end
    suivi.Rendre()
end

function suivi.Basculer()
    if not cadre then Construire() end
    local s = Reglages()
    s.afficher = not cadre:IsShown()
    cadre:SetShown(s.afficher)
    if s.afficher then suivi.Rendre() end
end

-- Montrer un parcours dans le suivi : onglet Parcours, ce parcours deplie.
function suivi.MontrerParcours(idParcours)
    if not cadre then Construire() end
    local s = Reglages()
    s.vue = "parcours"
    s.parcoursChoisi = idParcours
    s.parcoursOuverts = type(s.parcoursOuverts) == "table" and s.parcoursOuverts or {}
    s.parcoursOuverts[idParcours] = true
    local pc = NS.parcours and NS.parcours.Trouver(NS.ClePersonnage(), idParcours)
    if pc then s.routeCategorie = CategorieDe(pc) end
    s.afficher = true
    cadre:Show()
    suivi.Rendre()
end

-- ---------------------------------------------------------------------------
-- Fond du suivi (gris, parchemin ou illustre), commun a la suite : pose
-- apres chaque rendu ; sur parchemin, les textes passent a l'encre.
-- ---------------------------------------------------------------------------

local RendreSansFond = suivi.Rendre
suivi.Rendre = function(...)
    RendreSansFond(...)
    if not cadre or not NS.charte.HabillerSuivi then return end
    local ok, souci = pcall(function()
        local parchemin = NS.charte.HabillerSuivi(cadre)
        NS.charte.Encrer(cadre.corps, parchemin)
        if cadre.resume then NS.charte.EncrerTextes({ cadre.resume }, parchemin) end
    end)
    if not ok then NS.base.NoterIncident("fond du suivi", souci) end
end
if NS.charte.SurFondDesSuivis then NS.charte.SurFondDesSuivis(function() suivi.Rendre() end) end

-- ---------------------------------------------------------------------------
-- Quete qui vient d'avancer : son bloc (titre, recompense, objectifs)
-- clignote doucement 4 secondes, puis se refige. S'il est hors de vue, la
-- liste defile jusqu'a lui.
-- ---------------------------------------------------------------------------

local DUREE_ECLAT = 4
local eclats = {}

local function Eclat(rang)
    local e = eclats[rang]
    if e then return e end
    e = cadre.corps:CreateTexture(nil, "BACKGROUND", nil, 1)
    e:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    e:SetBlendMode("ADD")
    e:SetVertexColor(1, 0.82, 0)
    eclats[rang] = e
    return e
end

local animation
local function Animer()
    if animation then return end
    animation = CreateFrame("Frame")
    animation:SetScript("OnUpdate", function(self)
        local maintenant = NS.Appeler(GetTime) or 0
        local actifs = false
        for _, e in ipairs(eclats) do
            if e:IsShown() and e.depart then
                local t = maintenant - e.depart
                if t >= DUREE_ECLAT then
                    e:Hide()
                else
                    actifs = true
                    -- Deux pulsations par seconde, qui s'estompent a la fin.
                    local fin = math.min(1, (DUREE_ECLAT - t) / 0.6)
                    e:SetAlpha((0.18 + 0.32 * (0.5 + 0.5 * math.sin(t * math.pi * 4))) * fin)
                end
            end
        end
        if not actifs then self:Hide() end
    end)
end

local function EclairerAvancees()
    for _, e in ipairs(eclats) do e:Hide() end
    local avancees = NS.journal and NS.journal.avancees
    if not cadre or not cadre.corps or not avancees or Reglages().replie then return end
    local maintenant = NS.Appeler(GetTime) or 0
    local n, plusRecente, quand = 0, nil, -1
    for id, depart in pairs(avancees) do
        if maintenant - depart >= DUREE_ECLAT then
            avancees[id] = nil
        else
            local bloc = cadre.blocs and cadre.blocs[id]
            if bloc then
                n = n + 1
                local e = Eclat(n)
                e:ClearAllPoints()
                e:SetPoint("TOPLEFT", cadre.corps, "TOPLEFT", -2, -bloc.haut + 2)
                e:SetPoint("BOTTOMRIGHT", cadre.corps, "TOPRIGHT", 0, -bloc.bas)
                e.depart = depart
                e:Show()
                if depart > quand then plusRecente, quand = bloc, depart end
            end
        end
    end
    if n == 0 then return end
    Animer()
    animation:Show()
    -- Hors de vue : on defile jusqu'au bloc, une seule fois par avancee.
    local d = cadre.defilement
    if plusRecente and d and quand ~= cadre.dernierDefilement then
        cadre.dernierDefilement = quand
        local vue = d:GetHeight() or 0
        local haut = d:GetVerticalScroll() or 0
        if plusRecente.haut < haut or plusRecente.bas > haut + vue then
            local maximum = math.max(0, (cadre.corps:GetHeight() or 0) - vue)
            d:SetVerticalScroll(math.max(0, math.min(maximum, plusRecente.haut - 6)))
        end
    end
end

do
    local rendre = suivi.Rendre
    suivi.Rendre = function(...)
        if cadre then cadre.blocs = {} end
        rendre(...)
        local ok, souci = pcall(EclairerAvancees)
        if not ok then NS.base.NoterIncident("suivi, quete avancee", souci) end
    end
end

-- ---------------------------------------------------------------------------
-- Bandeau des quetes : quand un objectif avance, une ligne s'affiche quelques
-- secondes a l'ecran (titre de la quete, puis ce qui vient d'avancer) ; une
-- quete terminee s'affiche avec la coche du jeu, et s'annonce au groupe.
-- Place : en mode Edition du jeu, ou avec /qc bandeau, on le glisse ou l'on
-- veut ; la position est gardee.
-- ---------------------------------------------------------------------------

local bandeau = {}
NS.bandeau = bandeau
local DUREE_BANDEAU = 3.5
local MAX_LIGNES = 4
local cadreB, enPlacement
local lignesB = {}

local LARGEUR_BANDEAU = 380
-- Par defaut : centre, en haut, a moins d'un centimetre du bord.
local HAUT_DEFAUT = -30

local function ReglagesBandeau()
    local g = NS.base.ReglagesGeneraux()
    g.bandeau = type(g.bandeau) == "table" and g.bandeau or {}
    local r = g.bandeau
    if r.actif == nil then r.actif = true end
    if type(r.duree) ~= "number" then r.duree = DUREE_BANDEAU end
    if r.disparition ~= "net" then r.disparition = "fondu" end
    if type(r.fondu) ~= "number" then r.fondu = 0.5 end
    return r
end
bandeau.Reglages = ReglagesBandeau

-- Toujours accroche par son milieu haut : il reste centre quelle que soit
-- sa hauteur. x = ecart au milieu de l'ecran, y = ecart au haut.
local function PlacerCadre()
    local r = ReglagesBandeau()
    cadreB:ClearAllPoints()
    if r.point ~= "TOP" then r.point, r.x, r.y = "TOP", 0, HAUT_DEFAUT end
    cadreB:SetPoint("TOP", UIParent, "TOP", r.x or 0, r.y or HAUT_DEFAUT)
end

-- Aimantation : au milieu de l'ecran a 12 pixels pres, et a la grille du
-- mode Edition du jeu quand elle est affichee.
local function Aimanter(x, y)
    if math.abs(x) < 12 then x = 0 end
    local e = _G.EditModeManagerFrame
    local grille = e and e:IsShown() and e.Grid and e.Grid:IsShown()
    local pas = grille and tonumber(e.Grid.gridSpacing or (e.GetGridSpacing and e:GetGridSpacing()))
    if pas and pas > 0 then
        if x ~= 0 then x = math.floor(x / pas + 0.5) * pas end
        y = math.floor(y / pas + 0.5) * pas
    end
    return x, y
end

local function ConstruireBandeau()
    if cadreB then return cadreB end
    -- Meme habit que les cartes de la suite : bord dore, fond gris sombre.
    local ok, f = pcall(CreateFrame, "Frame", "QuestCoreBandeau", UIParent, "BackdropTemplate")
    cadreB = ok and f or CreateFrame("Frame", "QuestCoreBandeau", UIParent)
    if cadreB.SetBackdrop then
        cadreB:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        cadreB:SetBackdropColor(0.09, 0.09, 0.09, 0.9)
        cadreB:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
    end
    cadreB:SetFrameStrata("HIGH")
    cadreB:SetSize(LARGEUR_BANDEAU, 40)
    cadreB:SetClampedToScreen(true)
    cadreB:SetMovable(true)
    cadreB:EnableMouse(false)
    cadreB:RegisterForDrag("LeftButton")
    cadreB:SetScript("OnDragStart", function(self) if enPlacement then self:StartMoving() end end)
    cadreB:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Repasse en accroche par le milieu haut, puis aimante.
        local echelle = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local cx = (self:GetCenter() or 0) * echelle
        local haut = (self:GetTop() or 0) * echelle
        local x = cx - (UIParent:GetWidth() or 0) / 2
        local y = haut - (UIParent:GetHeight() or 0)
        x, y = Aimanter(x, math.min(0, y))
        local r = ReglagesBandeau()
        if not self:GetCenter() then PlacerCadre() return end
        r.point, r.x, r.y = "TOP", math.floor(x + 0.5), math.floor(y + 0.5)
        PlacerCadre()
    end)
    cadreB.voile = cadreB:CreateTexture(nil, "OVERLAY")
    cadreB.voile:SetAllPoints()
    cadreB.voile:SetColorTexture(0.25, 0.6, 1, 0.22)
    cadreB.voile:Hide()
    cadreB:Hide()
    PlacerCadre()
    cadreB:SetScript("OnUpdate", function(self)
        if enPlacement then self:SetAlpha(1) return end
        local reste = (self.fin or 0) - (NS.Appeler(GetTime) or 0)
        if reste <= 0 then
            self:Hide()
            for _, l in ipairs(lignesB) do l.utile = false end
            return
        end
        -- Disparition en fondu (sur la duree choisie) ou d'un coup.
        local r = ReglagesBandeau()
        if r.disparition == "fondu" and r.fondu > 0 then self:SetAlpha(math.min(1, reste / r.fondu))
        else self:SetAlpha(1) end
    end)
    return cadreB
end

local function LigneB(rang)
    local l = lignesB[rang]
    if l then return l end
    l = {}
    l.icone = cadreB:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.titre = cadreB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l.titre:SetJustifyH("LEFT")
    l.detail = cadreB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.detail:SetJustifyH("LEFT")
    -- Troisieme ligne, pour une quete terminee : recompense et niveau.
    l.detail2 = cadreB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.detail2:SetJustifyH("LEFT")
    lignesB[rang] = l
    return l
end

local function Disposer()
    local y = -10
    for rang = 1, MAX_LIGNES do
        local l = lignesB[rang]
        if l and l.utile then
            l.icone:ClearAllPoints()
            l.icone:SetPoint("TOPLEFT", cadreB, "TOPLEFT", 10, y)
            l.titre:ClearAllPoints()
            l.titre:SetPoint("TOPLEFT", l.icone, "TOPRIGHT", 6, 0)
            l.titre:SetPoint("RIGHT", cadreB, "RIGHT", -10, 0)
            l.titre:SetWordWrap(false)
            l.titre:SetText(l.texteTitre)
            l.detail:ClearAllPoints()
            l.detail:SetPoint("TOPLEFT", l.titre, "BOTTOMLEFT", 0, -2)
            l.detail:SetPoint("RIGHT", cadreB, "RIGHT", -10, 0)
            l.detail:SetWordWrap(false)
            l.detail:SetText(l.texteDetail)
            local c = l.couleur
            l.detail:SetTextColor(c[1], c[2], c[3])
            l.icone:Show() l.titre:Show() l.detail:Show()
            if l.texteDetail2 then
                l.detail2:ClearAllPoints()
                l.detail2:SetPoint("TOPLEFT", l.detail, "BOTTOMLEFT", 0, -2)
                l.detail2:SetPoint("RIGHT", cadreB, "RIGHT", -10, 0)
                l.detail2:SetWordWrap(false)
                l.detail2:SetText(l.texteDetail2)
                l.detail2:SetTextColor(1, 0.82, 0)
                l.detail2:Show()
                y = y - 50
            else
                l.detail2:Hide()
                y = y - 36
            end
        elseif l then
            l.icone:Hide() l.titre:Hide() l.detail:Hide() l.detail2:Hide()
        end
    end
    cadreB:SetSize(LARGEUR_BANDEAU, -y + 2)
end

-- Icone de quete du jeu : coche (terminee) ou point d'interrogation gris.
local function PoserIcone(tex, terminee)
    tex:SetTexCoord(0, 1, 0, 1)
    if terminee then
        if not (tex.SetAtlas and pcall(tex.SetAtlas, tex, "QuestTurnin") and tex:GetAtlas()) then
            tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        end
    else
        if not (tex.SetAtlas and pcall(tex.SetAtlas, tex, "QuestNormal") and tex:GetAtlas()) then
            tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        end
    end
end

local function Montrer(titre, detail, terminee, detail2)
    ConstruireBandeau()
    -- Une ligne par quete : la meme quete remplace sa ligne.
    local cible
    for rang = 1, MAX_LIGNES do
        local l = lignesB[rang]
        if l and l.utile and l.texteTitre == titre then cible = l break end
    end
    if not cible then
        for rang = 1, MAX_LIGNES do
            local l = LigneB(rang)
            if not l.utile then cible = l break end
        end
    end
    if not cible then
        -- Plein : on decale, la plus ancienne s'en va.
        for rang = 1, MAX_LIGNES - 1 do
            local a, b = lignesB[rang], lignesB[rang + 1]
            a.texteTitre, a.texteDetail, a.couleur, a.terminee = b.texteTitre, b.texteDetail, b.couleur, b.terminee
            a.texteDetail2 = b.texteDetail2
            PoserIcone(a.icone, a.terminee)
        end
        cible = lignesB[MAX_LIGNES]
    end
    cible.utile = true
    cible.texteTitre, cible.texteDetail, cible.terminee = titre, detail, terminee
    cible.texteDetail2 = detail2
    cible.couleur = terminee and { 0.31, 0.82, 0.41 } or { 1, 1, 1 }
    PoserIcone(cible.icone, terminee)
    Disposer()
    local r = ReglagesBandeau()
    -- Le fondu s'ajoute au temps d'affichage plein.
    cadreB.fin = (NS.Appeler(GetTime) or 0) + r.duree + (r.disparition == "fondu" and r.fondu or 0)
    cadreB:SetAlpha(1)
    cadreB:Show()
end

-- Annonce au groupe (raid, groupe d'instance ou groupe), seulement si groupe.
local function AnnoncerAuGroupe(titre)
    local enGroupe = NS.Lecture("IsInGroup")
    if not (enGroupe and NS.Appeler(enGroupe)) then return end
    local canal = "PARTY"
    if NS.Appeler(NS.Lecture("IsInRaid")) then canal = "RAID" end
    local instance = _G.LE_PARTY_CATEGORY_INSTANCE
    local maison = _G.LE_PARTY_CATEGORY_HOME
    if instance and NS.Appeler(enGroupe, instance) and not (maison and NS.Appeler(enGroupe, maison)) then
        canal = "INSTANCE_CHAT"
    end
    local envoyer = NS.Lecture("C_ChatInfo.SendChatMessage", "SendChatMessage")
    if envoyer then NS.Appeler(envoyer, string.format(L.BANNER_PARTY, titre), canal) end
end

-- Quete terminee : ou la rendre, ce qu'elle rapporte, et l'XP qui manque
-- pour le niveau suivant au regard de tout ce qui est a rendre.
local function DetailsDeRendu(q, id)
    local receveurs = id and NS.ref.Receveurs(id) or {}
    local ligne1 = L.BANNER_DONE
    if receveurs[1] then ligne1 = ligne1 .. "   " .. string.format(L.TRACK_TURN_IN, SansSecondNom(receveurs[1])) end
    local morceaux = {}
    local r = q and q.recompenses or {}
    if (tonumber(r.xp) or 0) > 0 then table.insert(morceaux, NS.ref.NombreLisible(r.xp) .. " XP") end
    if (tonumber(r.argent) or 0) > 0 then table.insert(morceaux, NS.ref.TexteArgent(r.argent)) end
    local manque = (NS.Appeler(UnitXPMax, "player") or 0) - (NS.Appeler(UnitXP, "player") or 0)
    local total = 0
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.Perso(cle)
    for _, x in pairs(p and p.quetes or {}) do
        if x.complete == true then total = total + (tonumber(x.recompenses and x.recompenses.xp) or 0) end
    end
    if manque > 0 and total > 0 then
        if total >= manque then
            table.insert(morceaux, "|cff4fd168" .. L.TRACK_BILAN_LEVEL .. "|r")
        else
            table.insert(morceaux, "|cffb3b3b3" .. string.format(L.BANNER_XP_MISSING, NS.ref.NombreLisible(manque - total)) .. "|r")
        end
    end
    return ligne1, #morceaux > 0 and table.concat(morceaux, "   ") or nil
end

function bandeau.Annoncer(q, textes, terminee, id)
    local titre = q and q.titre or "?"
    if terminee then AnnoncerAuGroupe(titre) end
    if not ReglagesBandeau().actif then return end
    if terminee then
        local ligne1, ligne2 = DetailsDeRendu(q, id)
        Montrer(titre, ligne1, true, ligne2)
    else
        Montrer(titre, table.concat(textes or {}, "   "), false)
    end
end

function bandeau.EnPlacement() return enPlacement == true end

-- Pour l'avancement des membres du groupe (voir Journal.lua).
function bandeau.Montrer(titre, detail, terminee, detail2)
    if enPlacement or not ReglagesBandeau().actif then return end
    Montrer(titre, detail, terminee, detail2)
end

-- Apercu depuis les Parametres : un exemple, avec les reglages en cours.
function bandeau.Apercu()
    if enPlacement then return end
    Montrer(L.BANNER_SAMPLE_TITLE, L.BANNER_SAMPLE_DETAIL, false)
end

function bandeau.Recentrer()
    local r = ReglagesBandeau()
    r.point, r.x, r.y = "TOP", 0, HAUT_DEFAUT
    if cadreB then PlacerCadre() end
end

-- Placement : montre un bandeau d'exemple, deplacable a la souris.
local function Placement(oui)
    ConstruireBandeau()
    enPlacement = oui
    cadreB:EnableMouse(oui)
    cadreB.voile:SetShown(oui)
    if oui then
        for _, l in ipairs(lignesB) do l.utile = false end
        local l = LigneB(1)
        l.utile, l.texteTitre, l.texteDetail, l.couleur, l.terminee = true, L.BANNER_PLACE, L.BANNER_PLACE_HELP, { 1, 1, 1 }, false
        PoserIcone(l.icone, false)
        Disposer()
        cadreB:Show()
    else
        cadreB:Hide()
        for _, l in ipairs(lignesB) do l.utile = false end
    end
end

function bandeau.Placer() Placement(not enPlacement) end

-- En mode Edition du jeu, le bandeau se montre et se deplace aussi.
do
    local e = _G.EditModeManagerFrame
    if e and e.HookScript then
        e:HookScript("OnShow", function() pcall(Placement, true) end)
        e:HookScript("OnHide", function() pcall(Placement, false) end)
    end
end

-- ---------------------------------------------------------------------------
-- Passer une etape d'un parcours (clic droit sur son numero) : elle sort du
-- parcours et de la selection.
function suivi.PasserEtape(idParcours, quete)
    local cle = NS.ClePersonnage()
    if not (cle and NS.parcours and NS.parcours.PasserEtape) then return end
    if NS.parcours.PasserEtape(cle, idParcours, quete) then
        Selection("quetes")[quete] = nil
        Selection("favoris")[quete] = nil
        RafraichirTrajet()
    end
end

-- ---------------------------------------------------------------------------
-- Questie : son suivi de quetes se range tant que le notre est affiche, au
-- meme endroit ; il revient quand on ferme le notre. Rien n'est change dans
-- les reglages de Questie.
-- ---------------------------------------------------------------------------
do
    local function NotreSuiviVisible() return cadre and cadre:IsShown() end
    local function SuiviQuestie() return _G.Questie_BaseFrame end
    local accroche = false

    local function Ranger()
        local q = SuiviQuestie()
        if not q then return end
        if not accroche then
            accroche = true
            q:HookScript("OnShow", function(self)
                if NotreSuiviVisible() and not NS.Appeler(InCombatLockdown) then self:Hide() end
            end)
        end
        if NotreSuiviVisible() then
            if q:IsShown() and not NS.Appeler(InCombatLockdown) then q:Hide() end
        else
            local profil = _G.Questie and _G.Questie.db and _G.Questie.db.profile
            if profil and profil.trackerEnabled and not q:IsShown() and not NS.Appeler(InCombatLockdown) then q:Show() end
        end
    end
    suivi.RangerQuestie = Ranger

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        -- Questie construit son suivi un peu apres la connexion.
        local plusTard = NS.Lecture("C_Timer.After")
        if plusTard then
            plusTard(3, function() pcall(Ranger) end)
            plusTard(10, function() pcall(Ranger) end)
        end
    end)
end

-- Pour les raccourcis de la suite : montrer ou cacher le suivi des quetes.
if _G.QuestCoreAPI then _G.QuestCoreAPI.BasculerSuivi = function() suivi.Basculer() end end
