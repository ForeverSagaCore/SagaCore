-- SagaCore (bascule) : un bouton sur la minicarte qui ouvre les trois suites
-- de Forever SagaCore (la tienne, la Live, la Dev) et passe de l'une a
-- l'autre en un clic. Toujours actif, independant des suites. Prive.
--   /saga : la meme fenetre.

local ADDONS = { "CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore", "PvPCore", "AchievementCore" }
local PRIVES = { "TradeCore" }
local MODES = {
    { cle = "normale", suffixe = "", nom = "Ma version", couleur = "ffd100" },
    { cle = "live", suffixe = "Live", nom = "Live", couleur = "33ccff" },
    { cle = "dev", suffixe = "Dev", nom = "Dev", couleur = "ff8000" },
}

local A = _G.C_AddOns or {}
local function F(nom) return A[nom] or _G[nom] end

local function Existe(n)
    local info = F("GetAddOnInfo")
    if not info then return false end
    local ok, nom, _, _, _, raison = pcall(info, n)
    return ok and nom ~= nil and raison ~= "MISSING"
end
local function Charge(n)
    local f = F("IsAddOnLoaded")
    local ok, oui = pcall(f, n)
    return ok and oui and true or false
end
local function Version(n)
    local f = F("GetAddOnMetadata")
    if not f then return nil end
    local ok, v = pcall(f, n, "X-SagaCore-Version")
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

-- La suite active : celle dont un add-on est charge.
local function ModeActif()
    for _, m in ipairs(MODES) do
        for _, n in ipairs(ADDONS) do
            if Charge(n .. m.suffixe) then return m.cle end
        end
    end
    return nil
end
local function Presente(m)
    for _, n in ipairs(ADDONS) do if Existe(n .. m.suffixe) then return true end end
    return false
end

local function Basculer(cible)
    local activer, couper = F("EnableAddOn"), F("DisableAddOn")
    if not (activer and couper) then return end
    for _, n in ipairs(ADDONS) do
        for _, m in ipairs(MODES) do
            if Existe(n .. m.suffixe) then
                if m.cle == cible then pcall(activer, n .. m.suffixe) else pcall(couper, n .. m.suffixe) end
            end
        end
    end
    -- TradeCore (prive, jamais publie) : coupe en Live, comme chez les joueurs.
    for _, n in ipairs(PRIVES) do
        if Existe(n) then if cible == "live" then pcall(couper, n) else pcall(activer, n) end end
    end
    if _G.C_UI and _G.C_UI.Reload then _G.C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
end

-- La fenetre : trois boutons, l'actif grise et dit « active ».
local fenetre
local function Fenetre()
    if fenetre then return fenetre end
    local f = CreateFrame("Frame", "SagaCoreBascule", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(240, 162)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "SagaCoreBascule")
    local titre = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then titre:SetPoint("TOP", 0, -5) end
    titre:SetText("Forever SagaCore")
    f.boutons = {}
    for i, m in ipairs(MODES) do
        local b = CreateFrame("Button", "SagaCoreBascule" .. m.cle, f, "UIPanelButtonTemplate")
        b:SetSize(200, 26)
        b:SetPoint("TOP", f, "TOP", 0, -34 - (i - 1) * 36)
        b:SetScript("OnClick", function() Basculer(m.cle) end)
        b.mode = m
        f.boutons[i] = b
    end
    f:Hide()
    fenetre = f
    return f
end
local function Rafraichir()
    local f = Fenetre()
    local actif = ModeActif()
    for _, b in ipairs(f.boutons) do
        local m = b.mode
        local v = (m.cle == "live") and Version("CraftCoreLive")
        local texte = "|cff" .. m.couleur .. m.nom .. "|r" .. (v and (" " .. v) or "")
        local present = Presente(m)
        if actif == m.cle then texte = texte .. "  (active)"
        elseif not present then texte = texte .. "  (absente)" end
        b:SetText(texte)
        b:SetEnabled(present and actif ~= m.cle)
    end
end
local function Ouvrir()
    local f = Fenetre()
    if f:IsShown() then f:Hide() return end
    Rafraichir()
    f:Show()
end

-- Bouton de minicarte, deplacable autour de la minicarte.
local function Placer(b)
    local angle = math.rad((SagaCoreBasculeDB and SagaCoreBasculeDB.angle) or 200)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end
local function CreerBouton()
    local b = CreateFrame("Button", "SagaCoreBasculeMinicarte", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icone = b:CreateTexture(nil, "BACKGROUND")
    icone:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    icone:SetSize(20, 20)
    icone:SetPoint("TOPLEFT", 7, -6)
    local bord = b:CreateTexture(nil, "OVERLAY")
    bord:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bord:SetSize(53, 53)
    bord:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", Ouvrir)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            SagaCoreBasculeDB.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Placer(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever SagaCore")
        local actif = ModeActif()
        for _, m in ipairs(MODES) do
            if m.cle == actif then GameTooltip:AddLine("Suite active : |cff" .. m.couleur .. m.nom .. "|r", 1, 1, 1) end
        end
        GameTooltip:AddLine("Clic : changer de suite", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Placer(b)
end

local demarrage = CreateFrame("Frame")
demarrage:RegisterEvent("PLAYER_LOGIN")
demarrage:SetScript("OnEvent", function()
    SagaCoreBasculeDB = type(SagaCoreBasculeDB) == "table" and SagaCoreBasculeDB or {}
    CreerBouton()
end)

SLASH_SAGACOREBASCULE1 = "/saga"
SlashCmdList.SAGACOREBASCULE = Ouvrir
