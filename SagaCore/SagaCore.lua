-- SagaCore (bascule) : un bouton de minicarte, comme les autres add-ons, qui
-- ouvre trois choix exclusifs :
--   Ma version : toute ta suite, rien d'autre (ni Dev, ni Live) ;
--   Dev        : toute la suite Dev, rien d'autre ;
--   Live       : la version publiee, complete ou les modules coches.
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
    local n, total = vus.live, 0
    for _, a in ipairs(ADDONS) do if Existe(a .. "Live") then total = total + 1 end end
    if n >= total then return "|cff33ccffLive|r" end
    return "|cff33ccffLive|r" .. (n == 1 and " (un module)" or (" (" .. n .. " modules)"))
end

-- Le coeur : active exactement la cible, coupe tout le reste des trois
-- suites, puis recharge. `seuls` : en Live, les modules coches (et ce dont
-- ils ont besoin pour se charger) ; nil ou vide : la suite complete.
local function Appliquer(cible, seuls)
    local activer, couper = F("EnableAddOn"), F("DisableAddOn")
    if not (activer and couper) then return end
    local gardes
    if seuls and next(seuls) then
        gardes = {}
        for module in pairs(seuls) do
            for d in pairs(Requis(module .. "Live")) do gardes[d] = true end
            gardes[module .. "Live"] = true
        end
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

-- La fenetre : trois lignes, un bouton chacune. Sous Live, une case par
-- module : rien de coche, la suite complete ; sinon les modules coches.
local fenetre
local function Coches()
    SagaCoreBasculeDB.modulesLive = type(SagaCoreBasculeDB.modulesLive) == "table" and SagaCoreBasculeDB.modulesLive or {}
    return SagaCoreBasculeDB.modulesLive
end
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
        local seuls = {}
        for m, oui in pairs(Coches()) do if oui and Existe(m .. "Live") then seuls[m] = true end end
        Appliquer("live", seuls)
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
    f.legendeLive = Legende(f.bLive, "")
    f.cases = {}
    f:Hide()
    fenetre = f
    return f
end

-- Les cases des modules Live installes, sur deux colonnes sous le bouton Live.
local function PoserCases(f)
    local modules = {}
    for _, n in ipairs(ADDONS) do if Existe(n .. "Live") then table.insert(modules, n) end end
    for _, c in ipairs(f.cases) do c:Hide() end
    for i, n in ipairs(modules) do
        local c = f.cases[i]
        if not c then
            c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            c:SetSize(24, 24)
            c.texte = c.text or c.Text or c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            c.texte:ClearAllPoints()
            c.texte:SetPoint("LEFT", c, "RIGHT", 2, 0)
            c.texte:SetFontObject("GameFontHighlightSmall")
            c.texte:SetWordWrap(false)
            c:SetScript("OnClick", function(self)
                Coches()[self.module] = self:GetChecked() and true or nil
                f.MajLegende()
            end)
            f.cases[i] = c
        end
        c.module = n
        c.texte:SetText(n)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + ((i - 1) % 2) * 134, -160 - math.floor((i - 1) / 2) * 24)
        c:SetChecked(Coches()[n] == true)
        c:Show()
    end
    f:SetHeight(160 + math.ceil(#modules / 2) * 24 + 14)
    return modules
end

local function Rafraichir()
    local f = Fenetre()
    f.etat:SetText("Chargee : " .. EtatActuel())
    PoserCases(f)
    function f.MajLegende()
        local n = 0
        for m, oui in pairs(Coches()) do if oui and Existe(m .. "Live") then n = n + 1 end end
        f.legendeLive:SetText(n == 0 and "complete (rien de coche)" or (n == 1 and "le module coche" or (n .. " modules coches")))
    end
    f.MajLegende()
    local v = Version("CraftCoreLive")
    f.bLive:SetText("|cff33ccffLive|r" .. (v and (" " .. v) or ""))
    local function Present(suffixe)
        for _, n in ipairs(ADDONS) do if Existe(n .. suffixe) then return true end end
        return false
    end
    f.bDev:SetEnabled(Present("Dev"))
    f.bLive:SetEnabled(Present("Live"))
end

-- Manette : la croix passe d'un element a l'autre (il s'allume), A valide,
-- B ferme.
local function Elements(f)
    local l = { f.bNormale, f.bDev, f.bLive }
    for _, c in ipairs(f.cases) do if c:IsShown() then table.insert(l, c) end end
    return l
end
local function Allumer(f)
    for i, b in ipairs(Elements(f)) do
        if i == f.rang then b:LockHighlight() else b:UnlockHighlight() end
    end
end
local function BrancherManette(f)
    if f.manette or not f.EnableGamePadButton then return end
    f.manette = true
    f:SetScript("OnGamePadButtonDown", function(self, bouton)
        local l = Elements(self)
        if bouton == "PADDUP" or bouton == "PADDLEFT" then self.rang = math.max(1, (self.rang or 1) - 1)
        elseif bouton == "PADDDOWN" or bouton == "PADDRIGHT" then self.rang = math.min(#l, (self.rang or 1) + 1)
        elseif bouton == "PAD1" then local b = l[self.rang or 1] if b and b:IsEnabled() then b:Click() end
        elseif bouton == "PAD2" then self:Hide() return end
        Allumer(self)
    end)
    f:HookScript("OnShow", function(self) pcall(self.EnableGamePadButton, self, true) self.rang = 1 Allumer(self) end)
    f:HookScript("OnHide", function(self) pcall(self.EnableGamePadButton, self, false) end)
end

local function Ouvrir()
    local f = Fenetre()
    if f:IsShown() then f:Hide() return end
    BrancherManette(f)
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
