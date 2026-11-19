local _, NS = ...

-- Bouton de minicarte. Patron repris mot pour mot de Panorama, installe sur ce
-- client : gabarit rond du jeu, deplacable autour de la minicarte, sans aucune
-- bibliotheque. L'icone est celle de la Forge du jeu, donc rien a fournir.

local ICONE = "Interface\\Icons\\INV_Misc_Gear_01"
local atan2 = math.atan2 or math.atan

local bouton

-- Reglages de position, crees avec leurs valeurs par defaut si absents : une
-- base ecrite par une version qui ne les connaissait pas reste lisible.
local function Reglages()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { angle = 200, afficher = true } end
    d.reglages = d.reglages or {}
    d.reglages.minicarte = d.reglages.minicarte or {}
    local m = d.reglages.minicarte
    if type(m.angle) ~= "number" then m.angle = 200 end
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
    bouton = CreateFrame("Button", "CraftCoreMinimapButton", Minimap)
    bouton:SetSize(31, 31)
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp")
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

    bouton:SetScript("OnClick", function()
        NS.ecran.Basculer()
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
        GameTooltip:AddLine(L.WINDOW_TITLE)
        GameTooltip:AddLine(L.MINIMAP_TIP_OPEN, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 1, 1, 1)
        GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NS.ActualiserBoutonDeMinicarte()
end

-- ---------------------------------------------------------------------------
-- Lieux de recolte sur la minicarte du jeu : l'icone ronde de chaque matiere
-- deja ramassee (herbe, minerai, poisson...), la meme que sur les cartes de
-- la suite. On sait ce que c'est avant d'y aller, sans survoler.
-- Suit les filtres de recolte des cartes (herboristerie, minage, peche).
-- Le jeu ne dit pas aux add-ons si un noeud est present en ce moment :
-- l'interieur du pion est gris et translucide dans un anneau dore, le point
-- jaune du jeu se voit au travers.
-- ---------------------------------------------------------------------------

-- Diametre de la minicarte en metres (yards), selon le zoom, dehors et dedans.
local DEHORS = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 3, [4] = 200, [5] = 133 + 1 / 3 }
local DEDANS = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 }

local pions, tailles = {}, {}

-- Taille d'une carte en metres : largeur (est-ouest), hauteur (nord-sud).
local function TailleDeCarte(carte)
    if tailles[carte] ~= nil then return tailles[carte] end
    local r = false
    local taille = NS.Lecture("C_Map.GetMapWorldSize")
    local l, h = NS.Appeler(taille, carte)
    if tonumber(l) and tonumber(h) and l > 0 and h > 0 then
        r = { l, h }
    else
        local versMonde, vecteur = NS.Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
        if versMonde and vecteur then
            local _, a = NS.Appeler(versMonde, carte, vecteur(0, 0))
            local _, b = NS.Appeler(versMonde, carte, vecteur(1, 1))
            if type(a) == "table" and type(b) == "table" and a.x and b.x then
                local largeur, hauteur = math.abs(a.y - b.y), math.abs(a.x - b.x)
                if largeur > 0 and hauteur > 0 then r = { largeur, hauteur } end
            end
        end
    end
    tailles[carte] = r
    return r or nil
end

local function Pion(rang)
    local p = pions[rang]
    if p then return p end
    local Suite = NS.suite or _G.CoreSuite
    if not (Suite and Suite.PionRecolte) then return nil end
    p = Suite.PionRecolte(_G.Minimap, 14)
    if p.Discret then p:Discret() end
    p:SetFrameStrata(_G.Minimap:GetFrameStrata())
    p:SetFrameLevel(_G.Minimap:GetFrameLevel() + 5)
    pions[rang] = p
    return p
end

local function PoserPionsMinicarte()
    local minicarte = _G.Minimap
    local Suite = NS.suite or _G.CoreSuite
    local n = 0
    local api = _G.CraftCoreAPI
    local montrer = minicarte and minicarte:IsVisible() and api and api.Lieux

    local carte = montrer and NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carte and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
    local taille = carte and TailleDeCarte(carte)
    if type(pos) == "table" and pos.GetXY and taille then
        local jx, jy = pos:GetXY()
        local zoom = tonumber(minicarte.GetZoom and minicarte:GetZoom()) or 0
        local dedans = NS.Appeler(_G.IsIndoors) == true
        local diametre = (dedans and DEDANS or DEHORS)[zoom] or 300
        local rayonPx = (minicarte:GetWidth() or 140) / 2
        local parMetre = rayonPx * 2 / diametre
        local tourne = NS.Appeler(_G.GetCVar, "rotateMinimap") == "1"
        local face = tourne and tonumber(NS.Appeler(_G.GetPlayerFacing)) or 0
        local c, s = math.cos(face), math.sin(face)
        local ok, lieux = pcall(api.Lieux, carte)
        for _, l in ipairs(jx and ok and lieux or {}) do
          if (not (Suite and Suite.LieuVisible) or Suite.LieuVisible(l)) then
            -- Est et nord en metres, puis en pixels.
            local est = (l.x - jx) * taille[1]
            local nord = -(l.y - jy) * taille[2]
            local px, py = est * parMetre, nord * parMetre
            if tourne then px, py = px * c + py * s, -px * s + py * c end
            if px * px + py * py <= (rayonPx - 6) * (rayonPx - 6) then
                local p = Pion(n + 1)
                if not p then break end
                n = n + 1
                p:Poser(l)
                p:ClearAllPoints()
                p:SetPoint("CENTER", minicarte, "CENTER", px, py)
                p:Show()
            end
          end
        end
    end
    for i = n + 1, #pions do pions[i]:Hide() end
end

local horloge = CreateFrame("Frame")
local attente = 0
horloge:SetScript("OnUpdate", function(_, ecoule)
    attente = attente - (ecoule or 0)
    if attente > 0 then return end
    attente = 0.1
    if not _G.Minimap then return end
    local ok, souci = pcall(PoserPionsMinicarte)
    if not ok then
        attente = 5
        if NS.base and NS.base.NoterIncident then NS.base.NoterIncident("minicarte, lieux", souci) end
    end
end)
