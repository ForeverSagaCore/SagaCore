local _, NS = ...

-- La carte de champ de bataille : une petite carte flottante, placee ou l'on
-- veut (meme au milieu de l'ecran), avec la position de chaque membre du
-- groupe a la couleur de sa classe, la votre en fleche, et les points
-- d'interet du champ de bataille (bases, tours, cimetieres...).
-- Sa transparence a deux reglages, de 0 a 100 % : en mouvement et a l'arret.
-- Deux raccourcis la forcent a tout moment : entierement visible, ou cachee
-- (un second appui revient au reglage).

NS.carte = {}
local C = NS.carte
local T = NS.T

local DEFAUTS = { taille = 300, alphaMarche = 0.35, alphaArret = 0.9, verrouillee = false, partout = false, affichee = true }
function C.Reglages()
    PvPCoreDB = type(PvPCoreDB) == "table" and PvPCoreDB or {}
    PvPCoreDB.carte = type(PvPCoreDB.carte) == "table" and PvPCoreDB.carte or {}
    local r = PvPCoreDB.carte
    for k, v in pairs(DEFAUTS) do if r[k] == nil then r[k] = v end end
    return r
end
local R = C.Reglages

local function Lire(nom) return NS.Lecture(nom) end
local function Nombre(v)
    if _G.issecretvalue and _G.issecretvalue(v) then return nil end
    return tonumber(v)
end
local function XY(pos)
    if type(pos) ~= "table" then return nil end
    local ok, x, y = pcall(function() if pos.GetXY then return pos:GetXY() end return pos.x, pos.y end)
    x, y = ok and Nombre(x), ok and Nombre(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return x, y
end

-- Le mode force par les raccourcis : nil (le reglage), "opaque" ou "cachee".
local force = nil
function C.Forcer(mode)
    if force == mode then force = nil else force = mode end
    if NS.Dire then
        NS.Dire(force == "opaque" and T("Carte : entièrement visible.", "Map : fully visible.")
            or force == "cachee" and T("Carte : cachée.", "Map : hidden.")
            or T("Carte : transparence du réglage.", "Map : transparency from settings."))
    end
end

local cadre
local function Construire()
    if cadre then return cadre end
    local ok, f = pcall(CreateFrame, "Frame", "PvPCoreCarte", UIParent, "TooltipBackdropTemplate")
    if not ok or not f then f = CreateFrame("Frame", "PvPCoreCarte", UIParent) end
    if f.SetBackdropColor then f:SetBackdropColor(0.02, 0.02, 0.03, 0.85) end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not R().verrouillee then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and ux then R().point = { math.floor(x - ux + 0.5), math.floor(y - uy + 0.5) } end
    end)
    -- La toile : les tuiles de la carte, puis les points par-dessus.
    f.toile = CreateFrame("Frame", nil, f)
    f.toile:SetPoint("TOPLEFT", 5, -5)
    f.toile:SetPoint("BOTTOMRIGHT", -5, 5)
    f.toile:SetClipsChildren(true)
    f.tuiles, f.points, f.poi = {}, {}, {}
    f.nom = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nom:SetPoint("TOP", f, "TOP", 0, -8)
    -- Les objectifs du champ de bataille, en direct, sous la carte.
    f.objectifs = {}
    for i = 1, 6 do
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOP", i == 1 and f or f.objectifs[i - 1], "BOTTOM", 0, i == 1 and -4 or -2)
        t:SetShadowOffset(1, -1)
        t:SetWordWrap(false)
        f.objectifs[i] = t
    end
    f.fleche = f.toile:CreateTexture(nil, "OVERLAY", nil, 7)
    f.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.fleche:SetSize(22, 22)
    f.fleche:Hide()
    f:Hide()
    cadre = f
    C.cadre = f
    return f
end

local function Placer(f)
    local r = R()
    f:ClearAllPoints()
    if type(r.point) == "table" then f:SetPoint("CENTER", UIParent, "CENTER", r.point[1], r.point[2])
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
end

-- Les tuiles de la carte : la grille du jeu (couche 1), mise a l'echelle.
local function Tuiles(f, carte)
    for _, t in ipairs(f.tuiles) do t:Hide() end
    f.largeurCarte, f.hauteurCarte = nil, nil
    local couches = Lire("C_Map.GetMapArtLayers")
    local textures = Lire("C_Map.GetMapArtLayerTextures")
    if not (couches and textures) then return end
    local okC, liste = pcall(couches, carte)
    local c = okC and type(liste) == "table" and liste[1]
    local okT, fichiers = pcall(textures, carte, 1)
    if not (c and okT and type(fichiers) == "table") then return end
    local lw, lh, tw, th = c.layerWidth, c.layerHeight, c.tileWidth, c.tileHeight
    if not (lw and lh and tw and th) or lw <= 0 or lh <= 0 then return end
    f.largeurCarte, f.hauteurCarte = lw, lh
    local colonnes = math.ceil(lw / tw)
    local W = R().taille
    local echelle = W / lw
    f:SetSize(W + 10, lh * echelle + 10)
    for i, fichier in ipairs(fichiers) do
        local t = f.tuiles[i]
        if not t then t = f.toile:CreateTexture(nil, "ARTWORK") f.tuiles[i] = t end
        local col, ligne = (i - 1) % colonnes, math.floor((i - 1) / colonnes)
        t:SetTexture(fichier)
        t:SetSize(tw * echelle, th * echelle)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.toile, "TOPLEFT", col * tw * echelle, -ligne * th * echelle)
        t:Show()
    end
end

-- Un point du groupe, a la couleur de sa classe.
local function Point(f, i)
    local p = f.points[i]
    if not p then
        p = f.toile:CreateTexture(nil, "OVERLAY", nil, 5)
        p:SetTexture("Interface\\Masks\\CircleMaskScalable")
        p:SetSize(10, 10)
        f.points[i] = p
    end
    return p
end

local function PoserSur(f, objet, x, y)
    objet:ClearAllPoints()
    objet:SetPoint("CENTER", f.toile, "TOPLEFT", x * f.toile:GetWidth(), -y * f.toile:GetHeight())
end

local function Positions(f, carte)
    local position = Lire("C_Map.GetPlayerMapPosition")
    for _, p in ipairs(f.points) do p:Hide() end
    f.fleche:Hide()
    if not position then return end
    local raid = NS.Appeler(_G.IsInRaid)
    local n = NS.Appeler(_G.GetNumGroupMembers) or 0
    local rang = 0
    for i = 1, n do
        local unite = raid and ("raid" .. i) or ("party" .. i)
        if NS.Appeler(UnitExists, unite) and not NS.Appeler(UnitIsUnit, unite, "player") then
            local x, y = XY(NS.Appeler(position, carte, unite))
            if x then
                rang = rang + 1
                local p = Point(f, rang)
                local _, classe = NS.Appeler(UnitClass, unite)
                local c = classe and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classe]
                if c then p:SetVertexColor(c.r, c.g, c.b, 1) else p:SetVertexColor(0.8, 0.8, 0.8, 1) end
                -- Mort : en gris.
                if NS.Appeler(UnitIsDeadOrGhost, unite) then p:SetVertexColor(0.35, 0.35, 0.35, 1) end
                PoserSur(f, p, x, y)
                p:Show()
            end
        end
    end
    local x, y = XY(NS.Appeler(position, carte, "player"))
    if x then
        PoserSur(f, f.fleche, x, y)
        local face = Nombre(NS.Appeler(_G.GetPlayerFacing))
        if face and f.fleche.SetRotation then f.fleche:SetRotation(face) end
        f.fleche:Show()
    end
end

-- Les points d'interet de la carte (bases, tours, cimetieres, drapeaux).
local function PointsDInteret(f, carte)
    for _, p in ipairs(f.poi) do p:Hide() end
    local pourCarte = Lire("C_AreaPoiInfo.GetAreaPOIForMap")
    local info = Lire("C_AreaPoiInfo.GetAreaPOIInfo")
    if not (pourCarte and info) then return end
    local ok, ids = pcall(pourCarte, carte)
    local rang = 0
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
        local okI, poi = pcall(info, carte, id)
        local x, y
        if okI and type(poi) == "table" then x, y = XY(poi.position) end
        if x then
            rang = rang + 1
            local t = f.poi[rang]
            if not t then t = f.toile:CreateTexture(nil, "OVERLAY", nil, 3) t:SetSize(16, 16) f.poi[rang] = t end
            local pose = false
            if type(poi.atlasName) == "string" and poi.atlasName ~= "" then pose = pcall(t.SetAtlas, t, poi.atlasName) end
            if not pose and poi.textureIndex and _G.GetPOITextureCoords then
                local okc, a, b, c2, d = pcall(_G.GetPOITextureCoords, poi.textureIndex)
                if okc and a then
                    t:SetTexture("Interface\\Minimap\\POIIcons")
                    t:SetTexCoord(a, b, c2, d)
                    pose = true
                end
            end
            if pose then PoserSur(f, t, x, y) t:Show() end
        end
    end
end

-- En mouvement ? La vitesse du jeu quand elle est lisible ; sinon (en champ
-- de bataille, le jeu peut la cacher) le deplacement de notre position sur
-- la carte. Jamais en vol.
local derniereX, derniereY, bougeJusque = nil, nil, 0
local function EnMouvement()
    if _G.UnitOnTaxi and NS.Appeler(_G.UnitOnTaxi, "player") then return false end
    local ok, v = pcall(GetUnitSpeed, "player")
    if ok and not (_G.issecretvalue and _G.issecretvalue(v)) and tonumber(v) then
        if tonumber(v) > 0 then return true end
    end
    local maintenant = (GetTime and GetTime()) or 0
    local carte = Nombre(NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
    local position = Lire("C_Map.GetPlayerMapPosition")
    if carte and position then
        local x, y = XY(NS.Appeler(position, carte, "player"))
        if x and derniereX and (math.abs(x - derniereX) + math.abs(y - derniereY)) > 0.00005 then
            bougeJusque = maintenant + 0.4
        end
        derniereX, derniereY = x, y
    end
    return maintenant < bougeJusque
end

-- La boucle : quatre fois par seconde les positions, toutes les deux
-- secondes les points d'interet, a chaque image le fondu.
function C.Demarrer()
    local f = Construire()
    Placer(f)
    local veille = CreateFrame("Frame")
    local attente, attentePoi, carteVue = 0, 0, nil
    veille:SetScript("OnUpdate", function(_, ecoule)
        ecoule = ecoule or 0.05
        local r = R()
        local voulue = r.affichee and (NS.honneur.EnChamp() or r.partout)
        if not voulue then
            if f:IsShown() then f:Hide() end
            carteVue = nil
            return
        end
        -- Opacite visee : forcee par un raccourci, sinon en mouvement / a l'arret.
        local cible = (force == "opaque" and 1) or (force == "cachee" and 0) or (EnMouvement() and r.alphaMarche or r.alphaArret)
        local actuel = f:IsShown() and (f:GetAlpha() or 1) or 0
        if math.abs(actuel - cible) >= 0.01 then
            local pas = 3 * ecoule
            actuel = (actuel < cible) and math.min(cible, actuel + pas) or math.max(cible, actuel - pas)
        else
            actuel = cible
        end
        if actuel <= 0.01 then
            if f:IsShown() then f:Hide() end
        else
            if not f:IsShown() then f:Show() end
            f:SetAlpha(actuel)
        end
        -- Verrouillee : les clics passent au travers (la carte ne gene jamais).
        f:EnableMouse(not r.verrouillee)
        attente = attente - ecoule
        attentePoi = attentePoi - ecoule
        if attente > 0 then return end
        attente = 0.25
        local carte = Nombre(NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
        if not carte then return end
        if carte ~= carteVue or f.tailleVue ~= r.taille then
            carteVue, f.tailleVue = carte, r.taille
            Tuiles(f, carte)
            local infoCarte = NS.Appeler(Lire("C_Map.GetMapInfo"), carte)
            f.nom:SetText(type(infoCarte) == "table" and infoCarte.name or "")
            attentePoi = 0
        end
        Positions(f, carte)
        if attentePoi <= 0 then
            attentePoi = 2
            PointsDInteret(f, carte)
        end
        -- Objectifs : quatre fois par seconde, comme les positions.
        local textes = NS.honneur.Objectifs()
        for i, t in ipairs(f.objectifs) do
            t:SetText(textes[i] or "")
            t:SetShown(textes[i] ~= nil)
        end
    end)
end

-- Remet la carte au centre (reglages).
function C.Recentrer()
    R().point = nil
    if cadre then Placer(cadre) end
end

-- Raccourcis clavier ou manette.
_G.BINDING_HEADER_PVPCORE = "PvPCore"
_G.BINDING_NAME_PVPCORE_OPAQUE = NS.T("Carte : entièrement visible (ou retour au réglage)", "Map : fully visible (or back to settings)")
_G.BINDING_NAME_PVPCORE_CACHEE = NS.T("Carte : cachée (ou retour au réglage)", "Map : hidden (or back to settings)")
function _G.PvPCore_CarteOpaque() C.Forcer("opaque") end
function _G.PvPCore_CarteCachee() C.Forcer("cachee") end
