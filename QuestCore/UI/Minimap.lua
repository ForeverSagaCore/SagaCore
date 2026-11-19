local _, NS = ...

-- Bouton de minicarte. Patron repris mot pour mot de Panorama, installe sur ce
-- client : gabarit rond du jeu, deplacable autour de la minicarte, sans aucune
-- bibliotheque. L icone est un livre du jeu, donc rien a fournir.

local ICONE = "Interface\\Icons\\INV_Misc_Book_08"
local atan2 = math.atan2 or math.atan

local bouton

-- Reglages de position, crees avec leurs valeurs par defaut si absents : une
-- base ecrite par une version qui ne les connaissait pas reste lisible.
local function Reglages()
    local d = QuestCoreDB
    if type(d) ~= "table" then return { angle = 230, afficher = true } end
    d.reglages = d.reglages or {}
    d.reglages.minicarte = d.reglages.minicarte or {}
    local m = d.reglages.minicarte
    if type(m.angle) ~= "number" then m.angle = 230 end
    if m.afficher == nil then m.afficher = true end
    return m
end

-- Place le bouton sur le bord de la minicarte. Une minicarte carree, posee par
-- une autre extension, borne la position au carre.
local function Placer()
    local m = Reglages()
    local angle = math.rad(m.angle)
    local demi = Minimap:GetWidth() / 2 + 5
    local forme = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = math.cos(angle), math.sin(angle)
    if forme == "ROUND" then
        x, y = x * demi, y * demi
    else
        local portee = demi * 1.4142
        x = math.max(-demi, math.min(x * portee, demi))
        y = math.max(-demi, math.min(y * portee, demi))
    end
    bouton:ClearAllPoints()
    bouton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SuivreLeCurseur()
    local centreX, centreY = Minimap:GetCenter()
    local echelle = Minimap:GetEffectiveScale()
    local curseurX, curseurY = GetCursorPosition()
    Reglages().angle = math.deg(atan2(curseurY / echelle - centreY, curseurX / echelle - centreX))
    Placer()
end

function NS.ActualiserBoutonDeMinicarte()
    if not bouton then return end
    if Reglages().afficher then
        Placer()
        bouton:Show()
    else
        bouton:Hide()
    end
end

function NS.ConstruireBoutonDeMinicarte()
    if bouton or not Minimap then return end
    bouton = CreateFrame("Button", "QuestCoreMinimapButton", Minimap)
    bouton:SetSize(31, 31)
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bouton:RegisterForDrag("LeftButton")

    -- Gabarit rond des boutons de minicarte : fond, icone masquee en cercle, anneau.
    local fond = bouton:CreateTexture(nil, "BACKGROUND")
    fond:SetSize(20, 20)
    fond:SetPoint("TOPLEFT", 7, -5)
    fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icone = bouton:CreateTexture(nil, "ARTWORK")
    icone:SetSize(17, 17)
    icone:SetPoint("TOPLEFT", 7, -6)
    icone:SetTexture(ICONE)
    icone:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local anneau = bouton:CreateTexture(nil, "OVERLAY")
    anneau:SetSize(53, 53)
    anneau:SetPoint("TOPLEFT")
    anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bouton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    bouton:SetScript("OnClick", function(_, souris)
        if souris == "RightButton" then NS.suivi.Basculer() else NS.fenetre.Basculer() end
    end)
    bouton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", SuivreLeCurseur)
        GameTooltip:Hide()
    end)
    bouton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    bouton:SetScript("OnEnter", function(self)
        local L = NS.L
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TITLE)
        GameTooltip:AddLine(L.MINIMAP_TIP_OPEN, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_TRACK, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 1, 1, 1)
        GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NS.ActualiserBoutonDeMinicarte()
end
