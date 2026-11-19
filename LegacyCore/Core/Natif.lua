-- LegacyCore : releve des elements de la fenetre d'heritage du jeu.
-- Quand la fenetre du jeu est ouverte, on note comment elle dessine un
-- talent (cadre, icone, case du rang, police) et ses fleches. Nos arbres
-- reprennent ensuite exactement ces elements, en un peu plus petit.
local _, NS = ...

local natif = {}
NS.natif = natif

local RANG = "^%s*(%d+)%s*/%s*(%d+)%s*$"

function natif.Releve()
    local d = LegacyCoreDB
    return type(d) == "table" and type(d.natif) == "table" and d.natif or nil
end

local function Couleur(t)
    if not t.GetVertexColor then return nil end
    local r, g, b, a = t:GetVertexColor()
    return { r or 1, g or 1, b or 1, a or 1 }
end

local function Texture(t, cx, cy, ref)
    local w, h = t:GetWidth() or 0, t:GetHeight() or 0
    local tx, ty = t:GetCenter()
    if not (tx and ty) or w <= 0 or h <= 0 then return nil end
    local couche, sous = t:GetDrawLayer()
    local atlas = t.GetAtlas and t:GetAtlas() or nil
    if atlas == "" then atlas = nil end
    local d = {
        atlas = atlas,
        fichier = (not atlas) and t:GetTexture() or nil,
        coords = (not atlas) and { t:GetTexCoord() } or nil,
        couche = couche, sous = sous,
        w = w / ref, h = h / ref, dx = (tx - cx) / ref, dy = (ty - cy) / ref,
        couleur = Couleur(t), alpha = t.GetAlpha and t:GetAlpha() or 1,
        gris = t.IsDesaturated and t:IsDesaturated() or false,
        mode = t.GetBlendMode and t:GetBlendMode() or nil,
    }
    return d
end

-- Le talent qui porte ce texte de rang : le premier cadre a peu pres carre
-- en remontant.
local function TalentDe(fs)
    local p = fs:GetParent()
    for _ = 1, 4 do
        if not p or not p.GetWidth then return nil end
        local w, h = p:GetWidth() or 0, p:GetHeight() or 0
        if w >= 24 and w <= 96 and math.abs(w - h) <= 8 then return p end
        p = p:GetParent()
    end
    return nil
end

local function Regions(f, liste, prof)
    for _, r in ipairs({ f:GetRegions() }) do table.insert(liste, r) end
    if prof > 0 then
        for _, c in ipairs({ f:GetChildren() }) do
            if c:IsShown() then Regions(c, liste, prof - 1) end
        end
    end
end

local function DecrireTalent(noeud, fs)
    local ref = noeud:GetWidth()
    local cx, cy = noeud:GetCenter()
    if not (ref and ref > 0 and cx and cy) then return nil end
    local d = { textures = {}, masques = {} }
    local regions = {}
    Regions(noeud, regions, 2)
    local meilleure, aire = nil, 0
    for _, r in ipairs(regions) do
        local genre = r.GetObjectType and r:GetObjectType()
        if genre == "Texture" and r:IsShown() then
            local t = Texture(r, cx, cy, ref)
            if t then
                table.insert(d.textures, t)
                -- L'icone : la plus grande texture d'un fichier (pas d'un
                -- atlas), a peu pres carree et de la taille du talent.
                if not t.atlas and t.w >= 0.5 and t.w <= 1.05 and math.abs(t.w - t.h) < 0.15 then
                    local nom = string.lower(tostring(t.fichier or ""))
                    local score = t.w * t.h
                    if type(t.fichier) == "number" or string.find(nom, "icons", 1, true) then score = score + 10 end
                    if score > aire then meilleure, aire = #d.textures, score end
                end
            end
        elseif genre == "MaskTexture" then
            local w, h = r:GetWidth() or 0, r:GetHeight() or 0
            local fichier = r.GetTexture and r:GetTexture() or nil
            local atlas = r.GetAtlas and r:GetAtlas() or nil
            if (fichier or atlas) and w > 0 then
                table.insert(d.masques, { fichier = fichier, atlas = atlas ~= "" and atlas or nil, w = w / ref, h = h / ref })
            end
        end
    end
    d.icone = meilleure
    local police, taille, options = fs:GetFont()
    local fx, fy = fs:GetCenter()
    local r, g, b = fs:GetTextColor()
    d.rang = { police = police, taille = (taille or 12) / ref, options = options,
        dx = fx and (fx - cx) / ref or 0.3, dy = fy and (fy - cy) / ref or -0.4, couleur = { r or 1, g or 1, b or 1 } }
    return d
end

local function DecrireFleches(racine)
    local fleches = {}
    local function Voir(f, prof)
        for _, r in ipairs({ f:GetRegions() }) do
            local genre = r.GetObjectType and r:GetObjectType()
            if genre == "Line" and r:IsShown() and not fleches.trait then
                local atlas = r.GetAtlas and r:GetAtlas() or nil
                fleches.trait = { epaisseur = r.GetThickness and r:GetThickness() or 2, couleur = Couleur(r),
                    atlas = atlas ~= "" and atlas or nil, fichier = r.GetTexture and r:GetTexture() or nil }
            elseif genre == "Texture" and r:IsShown() and not fleches.pointe then
                local atlas = r.GetAtlas and r:GetAtlas() or ""
                local fichier = r.GetTexture and r:GetTexture() or ""
                local nom = string.lower(tostring(atlas) .. " " .. tostring(fichier))
                if string.find(nom, "arrow", 1, true) then
                    fleches.pointe = { atlas = atlas ~= "" and atlas or nil, fichier = atlas == "" and fichier or nil,
                        coords = { r:GetTexCoord() }, w = r:GetWidth(), h = r:GetHeight(), couleur = Couleur(r),
                        rotation = r.GetRotation and r:GetRotation() or 0 }
                end
            end
        end
        if prof > 0 then for _, c in ipairs({ f:GetChildren() }) do if c:IsShown() then Voir(c, prof - 1) end end end
    end
    Voir(racine, 10)
    return fleches
end

-- Releve d'une fenetre ouverte : vrai si on y a trouve des talents.
function natif.Mesurer(racine)
    if not (racine and racine.IsShown and racine:IsShown()) then return false end
    local trouves, vus = { vide = nil, pris = nil, ref = nil }, 0
    local function Voir(f, prof)
        if trouves.vide and trouves.pris then return end
        vus = vus + 1
        if vus > 4000 then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsVisible() then
                local n = string.match(tostring(r:GetText() or ""), RANG)
                if n then
                    local cle = tonumber(n) > 0 and "pris" or "vide"
                    if not trouves[cle] then
                        local noeud = TalentDe(r)
                        local d = noeud and DecrireTalent(noeud, r)
                        if d then
                            trouves[cle] = d
                            trouves.ref = trouves.ref or noeud:GetWidth()
                        end
                    end
                end
            end
        end
        if prof > 0 then for _, c in ipairs({ f:GetChildren() }) do if c:IsShown() then Voir(c, prof - 1) end end end
    end
    Voir(racine, 12)
    if not (trouves.vide or trouves.pris) then return false end
    LegacyCoreDB = type(LegacyCoreDB) == "table" and LegacyCoreDB or {}
    LegacyCoreDB.natif = { vide = trouves.vide or trouves.pris, pris = trouves.pris or trouves.vide,
        taille = trouves.ref, fleches = DecrireFleches(racine), version = 1 }
    if NS.fenetre and NS.fenetre.Visible and NS.fenetre.Visible() then pcall(NS.fenetre.Rendre) end
    return true
end

-- Les fenetres du jeu qui peuvent etre celle de l'heritage (par leur nom).
local candidats = {}
local function Chercher()
    candidats = {}
    for nom, valeur in pairs(_G) do
        if type(nom) == "string" and type(valeur) == "table" and (string.find(nom, "Legacy") or string.find(nom, "Heritage"))
            and not string.find(nom, "^LegacyCore") and type(valeur.IsShown) == "function"
            and type(valeur.GetChildren) == "function" then
            table.insert(candidats, valeur)
        end
    end
end

local fait = false
local function Surveiller()
    if fait then return end
    for _, f in ipairs(candidats) do
        local ok, ouverte = pcall(f.IsShown, f)
        if ok and ouverte then
            local ok2, reussi = pcall(natif.Mesurer, f)
            if ok2 and reussi then fait = true return end
        end
    end
end

local veille = CreateFrame("Frame")
veille:RegisterEvent("PLAYER_LOGIN")
veille:RegisterEvent("ADDON_LOADED")
local cumul, aChercher = 0, false
veille:SetScript("OnEvent", function() aChercher = true end)
veille:SetScript("OnUpdate", function(_, ecoule)
    cumul = cumul + (ecoule or 0)
    if cumul < 1 or fait then return end
    cumul = 0
    if aChercher then aChercher = false pcall(Chercher) end
    pcall(Surveiller)
end)
