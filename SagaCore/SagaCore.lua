-- SagaCore (bascule) : un bouton de minicarte, comme les autres add-ons, qui
-- ouvre trois choix exclusifs :
--   Ma version : toute ta suite, rien d'autre (ni Dev, ni Live) ;
--   Dev        : toute la suite Dev, rien d'autre ;
--   Live       : la version publiee, complete ou un seul module.
-- Chaque choix remet TOUT en ordre, quel que soit l'etat de depart (meme un
-- melange), puis recharge l'interface. Toujours actif, independant des
-- suites. Prive.  /saga : la meme fenetre.

local ADDONS = { "CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore", "PvPCore", "AchievementCore" }
local PRIVES = { "TradeCore" }   -- ta version seulement (jamais publie)
local SUFFIXES = { normale = "", dev = "Dev", live = "Live" }

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
    if not f then return false end
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
local function Requis(nom)
    local f = F("GetAddOnDependencies")
    local r = {}
    if f then
        local ok, liste = pcall(function() return { f(nom) } end)
        for _, d in ipairs(ok and liste or {}) do r[d] = true end
    end
    return r
end

-- Ce qui est charge en ce moment, en clair.
local function EtatActuel()
    local vus = {}
    for mode, suffixe in pairs(SUFFIXES) do
        for _, n in ipairs(ADDONS) do
            if Charge(n .. suffixe) then vus[mode] = (vus[mode] or 0) + 1 end
        end
    end
    local modes = {}
    for m in pairs(vus) do table.insert(modes, m) end
    if #modes == 0 then return "aucune suite chargee" end
    if #modes > 1 then return "|cffff4040melange de versions|r" end
    local m = modes[1]
    if m == "normale" then return "|cffffd100Ma version|r" end
    if m == "dev" then return "|cffff8000Dev|r" end
    local n = vus.live
    return "|cff33ccffLive|r" .. (n == 1 and " (un module)" or "")
end

-- Le coeur : active exactement la cible, coupe tout le reste des trois
-- suites, puis recharge. `seul` : en Live, un seul module (et ce dont il a
-- besoin pour se charger).
local function Appliquer(cible, seul)
    local activer, couper = F("EnableAddOn"), F("DisableAddOn")
    if not (activer and couper) then return end
    local gardes
    if seul then
        gardes = Requis(seul .. "Live")
        gardes[seul .. "Live"] = true
    end
    for _, n in ipairs(ADDONS) do
        for mode, suffixe in pairs(SUFFIXES) do
            local nom = n .. suffixe
            if Existe(nom) then
                if mode == cible and (not gardes or gardes[nom]) then pcall(activer, nom) else pcall(couper, nom) end
            end
        end
    end
    for _, n in ipairs(PRIVES) do
        if Existe(n) then if cible == "normale" then pcall(activer, n) else pcall(couper, n) end end
    end
    if _G.C_UI and _G.C_UI.Reload then _G.C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
end

-- La fenetre : trois lignes, un bouton chacune. Live a son choix
-- (Complete ou un module) entre deux fleches, a cote.
local fenetre
local CHOIX_LIVE = { "Complete" }
local function Fenetre()
    if fenetre then return fenetre end
    local f = CreateFrame("Frame", "SagaCoreBascule", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(300, 190)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "SagaCoreBascule")
    local titre = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then titre:SetPoint("TOP", 0, -5) end
    titre:SetText("Forever SagaCore")

    f.etat = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.etat:SetPoint("TOP", f, "TOP", 0, -32)
    f.etat:SetWordWrap(false)

    local function Bouton(nom, texte, y, action)
        local b = CreateFrame("Button", nom, f, "UIPanelButtonTemplate")
        b:SetSize(130, 26)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
        b:SetText(texte)
        b:SetScript("OnClick", action)
        return b
    end
    f.bNormale = Bouton("SagaCoreBasculeNormale", "|cffffd100Ma version|r", -56, function() Appliquer("normale") end)
    f.bDev = Bouton("SagaCoreBasculeDev", "|cffff8000Dev|r", -92, function() Appliquer("dev") end)
    f.bLive = Bouton("SagaCoreBasculeLive", "|cff33ccffLive|r", -128, function()
        local choix = CHOIX_LIVE[f.choix or 1]
        Appliquer("live", choix ~= "Complete" and choix or nil)
    end)
    local function Legende(b, texte)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("LEFT", b, "RIGHT", 10, 0)
        t:SetWidth(130)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        t:SetText(texte)
        return t
    end
    Legende(f.bNormale, "toute ta suite")
    Legende(f.bDev, "toute la suite Dev")

    -- Choix Live : Complete ou un module, entre deux fleches.
    local nom = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nom:SetPoint("LEFT", f.bLive, "RIGHT", 34, 0)
    nom:SetWidth(84)
    nom:SetWordWrap(false)
    f.nomLive = nom
    local function Fleche(sens)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(22, 22)
        local base = sens < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
        b:SetNormalTexture(base .. "Up")
        b:SetPushedTexture(base .. "Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetPoint(sens < 0 and "RIGHT" or "LEFT", nom, sens < 0 and "LEFT" or "RIGHT", sens < 0 and -2 or 2, 0)
        b:SetScript("OnClick", function()
            f.choix = ((f.choix or 1) - 1 + sens) % #CHOIX_LIVE + 1
            nom:SetText(CHOIX_LIVE[f.choix])
        end)
    end
    Fleche(-1)
    Fleche(1)
    f:Hide()
    fenetre = f
    return f
end

local function Rafraichir()
    local f = Fenetre()
    f.etat:SetText("Chargee : " .. EtatActuel())
    -- Les modules Live installes.
    for i = #CHOIX_LIVE, 2, -1 do table.remove(CHOIX_LIVE, i) end
    for _, n in ipairs(ADDONS) do if Existe(n .. "Live") then table.insert(CHOIX_LIVE, n) end end
    if not f.choix or f.choix > #CHOIX_LIVE then f.choix = 1 end
    f.nomLive:SetText(CHOIX_LIVE[f.choix])
    local v = Version("CraftCoreLive")
    f.bLive:SetText("|cff33ccffLive|r" .. (v and (" " .. v) or ""))
    local function Present(suffixe)
        for _, n in ipairs(ADDONS) do if Existe(n .. suffixe) then return true end end
        return false
    end
    f.bDev:SetEnabled(Present("Dev"))
    f.bLive:SetEnabled(Present("Live"))
end

local function Ouvrir()
    local f = Fenetre()
    if f:IsShown() then f:Hide() return end
    Rafraichir()
    f:Show()
end

local function Aide(tt)
    tt:AddLine("Forever SagaCore")
    tt:AddLine("Chargee : " .. EtatActuel(), 1, 1, 1)
    tt:AddLine("Clic : changer de version", 0.7, 0.7, 0.7)
end

-- Bouton de minicarte : celui des autres add-ons (LibDBIcon) quand il est
-- disponible, sinon un bouton pose sur le bord de la minicarte, de la meme
-- facon.
local function BoutonMaison()
    local b = CreateFrame("Button", "SagaCoreBasculeMinicarte", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    local fond = b:CreateTexture(nil, "BACKGROUND")
    fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    fond:SetSize(20, 20)
    fond:SetPoint("TOPLEFT", 7, -5)
    local icone = b:CreateTexture(nil, "ARTWORK")
    icone:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    icone:SetSize(17, 17)
    icone:SetPoint("TOPLEFT", 7, -6)
    local bord = b:CreateTexture(nil, "OVERLAY")
    bord:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bord:SetSize(53, 53)
    bord:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local function Placer()
        local angle = math.rad(SagaCoreBasculeDB.angle or 200)
        local rayon = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rayon, math.sin(angle) * rayon)
    end
    b:SetScript("OnClick", Ouvrir)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            SagaCoreBasculeDB.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Placer()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Aide(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Placer()
end

local function CreerBouton()
    local LibStub = _G.LibStub
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if ldb and icon then
        local ok = pcall(function()
            local objet = ldb:NewDataObject("SagaCoreBascule", {
                type = "launcher",
                text = "Forever SagaCore",
                icon = "Interface\\Icons\\INV_Misc_Book_11",
                OnClick = function() Ouvrir() end,
                OnTooltipShow = function(tt) Aide(tt) end,
            })
            SagaCoreBasculeDB.icone = SagaCoreBasculeDB.icone or {}
            icon:Register("SagaCoreBascule", objet, SagaCoreBasculeDB.icone)
        end)
        if ok then return end
    end
    BoutonMaison()
end

local demarrage = CreateFrame("Frame")
demarrage:RegisterEvent("PLAYER_LOGIN")
demarrage:SetScript("OnEvent", function()
    SagaCoreBasculeDB = type(SagaCoreBasculeDB) == "table" and SagaCoreBasculeDB or {}
    CreerBouton()
end)

SLASH_SAGACOREBASCULE1 = "/saga"
SlashCmdList.SAGACOREBASCULE = Ouvrir
