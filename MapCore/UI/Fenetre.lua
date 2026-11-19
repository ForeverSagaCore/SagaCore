local _, NS = ...

-- Fenetre de MapCore : meme charte et meme taille que CraftCore et QuestCore,
-- pour passer de l'un a l'autre sans saut. A gauche : affichage et zones ; a
-- droite : la carte.

NS.fenetre = {}
local fen = NS.fenetre
local L = NS.L

local LARGEUR, HAUTEUR = 1060, 740
local LARGEUR_MENU = 170
-- Ecart du menu au filet, et du filet au contenu : le meme que CraftCore.
local ECART_MENU = 14
local cadre
local BrancherManette

local function Construire()
    cadre = NS.charte.Fenetre("MapCoreFenetre", LARGEUR, HAUTEUR, {})
    cadre:SetPoint("CENTER")
    cadre:Hide()
    table.insert(UISpecialFrames, "MapCoreFenetre")
    local portrait = cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait)
    if portrait then portrait:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end
    if cadre.titre then cadre.titre:SetText(L.TITLE) end

    local menu = CreateFrame("Frame", nil, cadre)
    menu:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    menu:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    menu:SetWidth(LARGEUR_MENU)
    cadre.menu = menu
    local trait = cadre:CreateTexture(nil, "ARTWORK")
    trait:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    trait:SetWidth(1)
    trait:SetPoint("TOPLEFT", menu, "TOPRIGHT", ECART_MENU, 0)
    trait:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", ECART_MENU, 0)

    local fondMenu = cadre.fond:CreateTexture(nil, "BACKGROUND", nil, 5)
    fondMenu:SetPoint("TOPLEFT", cadre.fond, "TOPLEFT", 3, -3)
    fondMenu:SetPoint("BOTTOMRIGHT", trait, "BOTTOMLEFT", -1, -(NS.charte.MARGE - 3))
    fondMenu:Hide()
    cadre.fondMenu = fondMenu

    local droite = CreateFrame("Frame", nil, cadre)
    droite:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_MENU, 0)
    droite:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    cadre.droite = droite

    -- Parchemin au choix (fond commun a la suite), comme QuestCore et CraftCore.
    NS.charte.Parchemin(cadre, { "TOPLEFT", trait, "TOPRIGHT", 2, NS.charte.MARGE - 4 },
        { "BOTTOMRIGHT", cadre.fond, "BOTTOMRIGHT", -4, 4 }, cadre.fond)

    local fermer = NS.charte.BoutonDePied(cadre, L.CLOSE, 110)
    fermer:SetScript("OnClick", function() cadre:Hide() end)

    if NS.suite then pcall(NS.suite.Entete, cadre, "MapCore", cadre.entete) end
    pcall(BrancherManette)
    cadre:SetScript("OnShow", function() fen.Rendre() end)
end

function fen.Rendre()
    if not cadre or not cadre:IsShown() then return end
    local ok, souci = pcall(function()
        if not cadre.fondMenu:IsShown() then pcall(NS.charte.FondDuJournal, cadre.fondMenu) end
        local parchemin = NS.charte.Fond() == "parchemin"
        if cadre.parchemin then cadre.parchemin.Montrer(parchemin) end
        NS.pageCarte.Rendre(cadre.droite, cadre.droite, cadre.menu)
        NS.charte.Encrer(cadre.droite, parchemin)
        fen.ApresRendu()
    end)
    if not ok then NS.base.NoterIncident("fenetre", souci) end
end

function fen.Ouvrir()
    if not cadre then Construire() end
    if not cadre:IsShown() then cadre:Show() end
end

-- ---------------------------------------------------------------------------
-- Manette, comme CraftCore et QuestCore
-- ---------------------------------------------------------------------------
--
--   croix haut / bas   ligne du menu precedente / suivante
--   A                  choisir la ligne (zone, continent, option)
--   LB / RB            zoom arriere / avant
--   LT / RT            add-on voisin de la suite (onglets lateraux)
--   B                  fermer (ou quitter les add-ons de la suite)
-- Rien dans la carte elle-meme : on ne s'y deplace pas a la manette.

local rangFocus = 0

local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

-- Icone d'un bouton de la manette : atlas du jeu, sinon la lettre en or.
local GLYPHES = { PAD1 = { "A", "Cross" }, PAD2 = { "B", "Circle" }, PADLTRIGGER = { "LTrigger", "LTrigger", "LT" },
    PADRTRIGGER = { "RTrigger", "RTrigger", "RT" }, PADDUP = { "Up", "Up", "^" }, PADDDOWN = { "Down", "Down", "v" },
    PADDRIGHT = { "Right", "Right", ">" }, PADLSHOULDER = { "LShoulder", "LShoulder", "LB" },
    PADRSHOULDER = { "RShoulder", "RShoulder", "RB" }, PADBACK = { "View", "Share", "Vue" },
    PADLSTICK = { "LStickIn", "LStickIn", "L3" }, PADRSTICK = { "RStickIn", "RStickIn", "R3" } }
local function Glyphe(touche)
    local g = GLYPHES[touche] or { touche }
    local info = NS.Lecture("C_Texture.GetAtlasInfo")
    if info then
        for _, nom in ipairs({ "Gamepad_Ltr_" .. g[1] .. "_64", "Gamepad_Shp_" .. (g[2] or g[1]) .. "_64",
            "Gamepad_Gen_" .. g[1] .. "_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":22:22|a" end
        end
    end
    return "|cffffd100" .. (g[3] or g[1]) .. "|r"
end

local function Lignes()
    local menu = NS.pageCarte.Menu and NS.pageCarte.Menu()
    local liste = {}
    for _, l in ipairs(menu and menu.lignes or {}) do
        if l:IsShown() and l:GetScript("OnClick") then table.insert(liste, l) end
    end
    return liste, menu
end

local function Eclairer()
    local liste, menu = Lignes()
    for _, l in ipairs(menu and menu.lignes or {}) do l:UnlockHighlight() end
    if not ManetteActive() or rangFocus < 1 then return end
    rangFocus = math.min(rangFocus, #liste)
    local l = liste[rangFocus]
    if not l then return end
    l:LockHighlight()
    -- Garder la ligne choisie a l'ecran, dans le menu qui defile.
    local _, _, _, _, y = l:GetPoint(1)
    local haut = -(y or 0)
    local vue = menu:GetHeight() or 0
    local actuel = menu:GetVerticalScroll() or 0
    if haut < actuel then menu:SetVerticalScroll(haut)
    elseif haut + 20 > actuel + vue then menu:SetVerticalScroll(math.max(0, haut + 20 - vue)) end
end

local function Indications()
    local barre = cadre.barreManette
    if not barre then
        local ok, cree = pcall(CreateFrame, "Frame", nil, cadre, "TooltipBackdropTemplate")
        barre = ok and cree or CreateFrame("Frame", nil, cadre)
        barre:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 10, 2)
        barre:SetHeight(38)
        barre:SetFrameLevel(cadre:GetFrameLevel() + 10)
        barre.texte = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        barre.texte:SetPoint("LEFT", barre, "LEFT", 12, 0)
        cadre.barreManette = barre
    end
    if not ManetteActive() then barre:Hide() return end
    local L_ = NS.L
    barre.texte:SetText(Glyphe("PADDUP") .. " " .. Glyphe("PADDDOWN") .. "  " .. L_.PAD_LINES .. "      "
        .. Glyphe("PAD1") .. "  " .. L_.PAD_SELECT .. "      " .. Glyphe("PADLSHOULDER") .. " " .. Glyphe("PADRSHOULDER")
        .. "  " .. L_.PAD_ZOOM .. "      " .. Glyphe("PADLSTICK") .. " "
        .. Glyphe("PADRSTICK") .. "  " .. L_.PAD_SUITE .. "      "
        .. Glyphe("PAD2") .. "  " .. L_.PAD_CLOSE)
    barre:SetWidth((barre.texte:GetStringWidth() or 400) + 24)
    barre:Show()
end

local function Traiter(bouton)
    local S = NS.suite
    if S and S.CurseurActif and S.CurseurActif(cadre) then
        if bouton == "PADDLEFT" then S.CurseurDeplacer(cadre, -1) return false end
        if bouton == "PADDRIGHT" then S.CurseurDeplacer(cadre, 1) return false end
        if bouton == "PAD1" then S.CurseurValider(cadre) return false end
        if bouton == "PAD2" then S.CurseurQuitter(cadre) return false end
        S.CurseurQuitter(cadre)
    end
    if bouton == "PADDUP" or bouton == "PADDDOWN" then
        local liste = Lignes()
        if #liste == 0 then return false end
        rangFocus = math.max(1, math.min(#liste, rangFocus + (bouton == "PADDUP" and -1 or 1)))
        Eclairer()
        return false
    end
    if bouton == "PAD1" then
        local l = Lignes()[rangFocus]
        if l then l:Click("LeftButton") end
        return false
    end
    if bouton == "PADLSHOULDER" then NS.pageCarte.Zoomer(1 / 1.5) return false end
    if bouton == "PADRSHOULDER" then NS.pageCarte.Zoomer(1.5) return false end
    if bouton == "PAD2" then cadre:Hide() return false end
    return true
end

BrancherManette = function()
    if not cadre.EnableGamePadButton then return end
    if not pcall(cadre.EnableGamePadButton, cadre, true) then return end
    cadre:SetScript("OnGamePadButtonDown", function(_, bouton)
        -- Vue tenue + LB / RB : add-on voisin (la suite s'en charge).
        local S = NS.suite
        if S and S.ManetteBas then
            local okS, pris = pcall(S.ManetteBas, "MapCore", bouton)
            if okS and pris then return false end
        end
        local ok, laisser = pcall(Traiter, bouton)
        if not ok then NS.base.NoterIncident("manette", laisser) return true end
        return laisser
    end)
    pcall(cadre.SetScript, cadre, "OnGamePadButtonUp", function(_, bouton)
        local S = NS.suite
        if S and S.ManetteHaut then pcall(S.ManetteHaut, bouton) end
    end)
    cadre:HookScript("OnHide", function() rangFocus = 0 end)
end

function fen.ApresRendu()
    if not cadre then return end
    pcall(Eclairer)
    pcall(Indications)
end

function fen.Basculer()
    if not cadre then Construire() end
    if cadre:IsShown() then cadre:Hide() else cadre:Show() end
end

function fen.Cadre() return cadre end
