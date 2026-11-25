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
    -- Plus de trait visible entre le menu et le contenu : il ne sert que de repere.
    trait:SetColorTexture(0, 0, 0, 0)
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
        NS.pageCarte.Rendre(cadre.droite, cadre.droite, cadre.menu, nil, cadre)
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
--   croix haut / bas      ligne du menu precedente / suivante
--   croix gauche / droite personnage precedent / suivant (portraits en haut)
--   A                     choisir la ligne
--   LT / RT               continent precedent / suivant (onglets a droite)
--   LB / RB               zoom arriere / avant
--   X                     echelon au-dessus (ville, zone, continent)
--   Vue                   entre sous la carte (services, filtres, boutons) ;
--                         la croix s'y deplace, A clique, Vue ou B en sort
--   L3 / R3               add-on voisin de la suite
--   B                     fermer

local rangFocus = 0
local enZone, focus = false, nil

local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

-- Icone d'un bouton de la manette : atlas du jeu, sinon la lettre en or.
local GLYPHES = { PAD1 = { "A", "Cross" }, PAD2 = { "B", "Circle" }, PADLTRIGGER = { "LTrigger", "LTrigger", "LT" },
    PADRTRIGGER = { "RTrigger", "RTrigger", "RT" }, PADDUP = { "Up", "Up", "^" }, PADDDOWN = { "Down", "Down", "v" },
    PADDRIGHT = { "Right", "Right", ">" }, PADDLEFT = { "Left", "Left", "<" }, PAD4 = { "Y", "Triangle" }, PAD3 = { "X", "Square" }, PADLSHOULDER = { "LShoulder", "LShoulder", "LB" },
    PADRSHOULDER = { "RShoulder", "RShoulder", "RB" }, PADBACK = { "View", "Share", "Vue" },
    PADLSTICK = { "LStickIn", "LStickIn", "L3" }, PADRSTICK = { "RStickIn", "RStickIn", "R3" } }
local function Glyphe(touche, taille)
    taille = taille or 22
    local g = GLYPHES[touche] or { touche }
    local info = NS.Lecture("C_Texture.GetAtlasInfo")
    if info then
        for _, nom in ipairs({ "Gamepad_Ltr_" .. g[1] .. "_64", "Gamepad_Shp_" .. (g[2] or g[1]) .. "_64",
            "Gamepad_Gen_" .. g[1] .. "_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":" .. taille .. ":" .. taille .. "|a" end
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
    for _, l in ipairs(liste) do l:UnlockHighlight() end
    if not ManetteActive() or rangFocus < 1 or enZone then return end
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

-- ---------------------------------------------------------------------------
-- Sous la carte : tout ce qui se clique autour d'elle (services, filtres,
-- boutons), sans les reperes poses sur la carte.
-- ---------------------------------------------------------------------------

local function Atteignable(objet)
    if not objet or not objet.IsObjectType or not objet:IsObjectType("Button") then return false end
    if not objet:IsVisible() then return false end
    if objet.IsMouseEnabled and not objet:IsMouseEnabled() then return false end
    if objet.IsEnabled and not objet:IsEnabled() then return false end
    return objet:GetScript("OnClick") ~= nil
end

local function Parcourir(c, liste, profondeur, exclu)
    if not c or not c.GetChildren or profondeur > 8 or c == exclu then return end
    for _, enfant in ipairs({ c:GetChildren() }) do
        if enfant ~= exclu and enfant:IsVisible() then
            if Atteignable(enfant) then table.insert(liste, enfant) end
            Parcourir(enfant, liste, profondeur + 1, exclu)
        end
    end
end

local function Elements()
    local liste = {}
    Parcourir(cadre.droite, liste, 1, NS.pageCarte.Toile and NS.pageCarte.Toile())
    table.sort(liste, function(a, b)
        local ha, hb = a:GetTop() or 0, b:GetTop() or 0
        if math.abs(ha - hb) > 4 then return ha > hb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    return liste
end

local function Relacher()
    if focus then
        if focus.UnlockHighlight then focus:UnlockHighlight() end
        local quitter = focus:GetScript("OnLeave")
        if quitter then pcall(quitter, focus) end
    end
    focus = nil
end

local function Choisir(e)
    Relacher()
    focus = e
    if not e then return end
    if e.LockHighlight then e:LockHighlight() end
    local survol = e:GetScript("OnEnter")
    if survol then pcall(survol, e) end
end

local function Boite(e)
    local l, b, w, h = e:GetLeft(), e:GetBottom(), e:GetWidth(), e:GetHeight()
    if not l or not b or not w or not h then return nil end
    return { l = l, r = l + w, x = l + w / 2, y = b + h / 2, h = h }
end

local function DeplacerVers(dx, dy)
    local liste = Elements()
    if #liste == 0 then Relacher() return end
    local depart = focus and focus:IsVisible() and Boite(focus)
    if not depart then Choisir(liste[#liste]) return end
    local meilleur, scoreMin
    for _, e in ipairs(liste) do
        local b = e ~= focus and Boite(e)
        if b then
            local score
            if dy ~= 0 then
                local avance = (dy > 0) and (depart.y - b.y) or (b.y - depart.y)
                if avance > 4 then
                    local ecart = math.max(0, math.max(depart.l, b.l) - math.min(depart.r, b.r))
                    score = avance * 4 + ecart * 2 + math.abs(b.x - depart.x) * 0.01
                end
            else
                local ecartV = math.abs(b.y - depart.y)
                local memeLigne = ecartV < math.max(depart.h, b.h) / 2 + 2
                local avance = (dx > 0) and (b.x - depart.x) or (depart.x - b.x)
                if avance > 2 then score = memeLigne and avance or (10000 + avance + ecartV * 2) end
            end
            if score and (not scoreMin or score < scoreMin) then meilleur, scoreMin = e, score end
        end
    end
    if meilleur then Choisir(meilleur) end
end

local function Lisere()
    if not cadre.lisereZone then
        local ok, c = pcall(CreateFrame, "Frame", nil, cadre, "BackdropTemplate")
        c = ok and c or CreateFrame("Frame", nil, cadre)
        if c.SetBackdrop then
            c:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
            c:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        c:EnableMouse(false)
        cadre.lisereZone = c
    end
    local c = cadre.lisereZone
    if not enZone then c:Hide() return end
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", cadre.droite, "TOPLEFT", -6, 6)
    c:SetPoint("BOTTOMRIGHT", cadre.droite, "BOTTOMRIGHT", 6, -6)
    c:SetFrameLevel((cadre.droite:GetFrameLevel() or 1) + 30)
    c:Show()
end

local function BasculerZone()
    enZone = not enZone
    Relacher()
    if enZone then
        rangFocus = 0
        Eclairer()
        DeplacerVers(0, 1)
    end
    Lisere()
    fen.ApresRendu()
end

-- ---------------------------------------------------------------------------
-- Indications : la barre sous la fenetre, et l'icone de chaque bouton pres
-- de ce qu'il fait (portraits, onglets), comme CraftCore et QuestCore.
-- ---------------------------------------------------------------------------

local function Marque(cle, touche, ancre, point, relatif, dx, dy)
    cadre.marquesManette = cadre.marquesManette or {}
    local m = cadre.marquesManette[cle]
    if not m then
        m = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cadre.marquesManette[cle] = m
    end
    if not ancre then m:Hide() return end
    m:ClearAllPoints()
    m:SetPoint(point, ancre, relatif, dx, dy)
    m:SetText(Glyphe(touche, 20))
    m:Show()
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
    if not ManetteActive() then
        barre:Hide()
        for _, m in pairs(cadre.marquesManette or {}) do m:Hide() end
        return
    end
    local L_ = NS.L
    local portraits = NS.pageCarte.Portraits and NS.pageCarte.Portraits() or {}
    local onglets = cadre.ordreContinents or {}
    Marque("dg", "PADDLEFT", #portraits > 1 and portraits[#portraits] or nil, "LEFT", "RIGHT", 10, 0)
    Marque("dd", "PADDRIGHT", #portraits > 1 and cadre.marquesManette.dg or nil, "LEFT", "RIGHT", 2, 0)
    Marque("lt", "PADLTRIGGER", onglets[1], "BOTTOM", "TOP", 0, 12)
    Marque("rt", "PADRTRIGGER", onglets[#onglets], "TOP", "BOTTOM", 0, -10)
    local morceaux
    if enZone then
        morceaux = { { "PADDUP PADDDOWN PADDLEFT PADDRIGHT", L_.PAD_MOVE }, { "PAD1", L_.PAD_SELECT },
            { "PAD3", L_.PAD_ONLY }, { "PADBACK PAD2", L_.PAD_ZONE_OUT } }
    else
        morceaux = { { "PADDUP PADDDOWN", L_.PAD_LINES }, { "PAD1", L_.PAD_SELECT },
            { "PADLSHOULDER PADRSHOULDER", L_.PAD_ZOOM }, { "PAD3", L_.PAD_MAP_UP },
            { "PADBACK", L_.PAD_ZONE_IN }, { "PADLSTICK PADRSTICK", L_.PAD_SUITE }, { "PAD2", L_.PAD_CLOSE } }
        local S = NS.suite or _G.CoreSuite
        if NS.pageCarte.EnPlan and NS.pageCarte.EnPlan() and S and S.OutilDonjon and S.OutilDonjon() then
            table.insert(morceaux, 4, { "PAD4", L_.PAD_PLAN_TOOL })
        end
    end
    local texte = {}
    for _, m in ipairs(morceaux) do
        local g = {}
        for touche in string.gmatch(m[1], "%S+") do table.insert(g, Glyphe(touche)) end
        table.insert(texte, table.concat(g, " ") .. "  " .. m[2])
    end
    barre.texte:SetText(table.concat(texte, "      "))
    barre:SetWidth((barre.texte:GetStringWidth() or 400) + 24)
    barre:Show()
end

local function Traiter(bouton)
    if bouton == "PADBACK" then BasculerZone() return false end
    if enZone then
        if bouton == "PAD2" then BasculerZone() return false end
        if bouton == "PADDUP" then DeplacerVers(0, -1) return false end
        if bouton == "PADDDOWN" then DeplacerVers(0, 1) return false end
        if bouton == "PADDLEFT" then DeplacerVers(-1, 0) return false end
        if bouton == "PADDRIGHT" then DeplacerVers(1, 0) return false end
        if bouton == "PAD1" or bouton == "PAD3" then
            if focus and focus:IsVisible() and focus.Click then
                local garde = focus
                focus:Click(bouton == "PAD3" and "RightButton" or "LeftButton")
                -- Le clic redessine : on garde le meme bouton choisi.
                if garde:IsVisible() then Choisir(garde) end
            end
            return false
        end
    end
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
    if bouton == "PADDLEFT" then NS.pageCarte.PersoVoisin(-1) return false end
    if bouton == "PADDRIGHT" then NS.pageCarte.PersoVoisin(1) return false end
    if bouton == "PADLTRIGGER" then NS.pageCarte.ContinentVoisin(-1) return false end
    if bouton == "PADRTRIGGER" then NS.pageCarte.ContinentVoisin(1) return false end
    if bouton == "PAD3" then NS.pageCarte.Remonter() return false end
    -- Y, dans un donjon : l'outil de donjon choisi, sur ce seul appui.
    if bouton == "PAD4" and NS.pageCarte.EnPlan and NS.pageCarte.EnPlan() then
        NS.pageCarte.OuvrirOutilDonjon()
        return false
    end
    -- Itineraires : LB / RB passent d'un type (ou d'une zone) a l'autre.
    if NS.pageCarte.EnItineraires and NS.pageCarte.EnItineraires() then
        if bouton == "PADLSHOULDER" then NS.pageCarte.ItinVoisin(-1) return false end
        if bouton == "PADRSHOULDER" then NS.pageCarte.ItinVoisin(1) return false end
    end
    if bouton == "PADLSHOULDER" then NS.pageCarte.Zoomer(1 / 1.25) return false end
    if bouton == "PADRSHOULDER" then NS.pageCarte.Zoomer(1.25) return false end
    if bouton == "PAD2" then cadre:Hide() return false end
    return true
end

BrancherManette = function()
    if not cadre.EnableGamePadButton then return end
    if not pcall(cadre.EnableGamePadButton, cadre, true) then return end
    cadre:SetScript("OnGamePadButtonDown", function(_, bouton)
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
    cadre:HookScript("OnHide", function()
        rangFocus = 0
        enZone = false
        Relacher()
        if cadre.lisereZone then cadre.lisereZone:Hide() end
    end)
end

function fen.ApresRendu()
    if not cadre or not cadre:IsShown() then return end
    if not ManetteActive() then enZone = false Relacher() end
    pcall(Eclairer)
    pcall(Lisere)
    pcall(Indications)
end

function fen.Basculer()
    if not cadre then Construire() end
    if cadre:IsShown() then cadre:Hide() else cadre:Show() end
end

function fen.Cadre() return cadre end
