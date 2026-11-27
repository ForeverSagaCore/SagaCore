local _, NS = ...

-- Les cartes de GloryCore, comme sur la maquette : panneaux sombres a liseré
-- d'or, anneaux d'avancement, petites tuiles de chiffres. Textes aux
-- couleurs de la carte (jamais a l'encre du parchemin : la carte est sombre).

NS.cartes = {}
local C = NS.cartes

local DISQUE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local FOND_CARTE = { 0.09, 0.066, 0.04, 0.96 }
local BORD = { 0.55, 0.42, 0.2, 1 }
local BORD_FORT = { 0.8, 0.63, 0.29, 1 }
C.OR = { 1, 0.82, 0.29 }
C.CLAIR = { 0.95, 0.89, 0.72 }
C.GRIS = { 0.66, 0.6, 0.49 }

-- Couleur de chaque categorie (celles de la maquette).
C.COULEURS = {
    quetes = { 0.91, 0.76, 0.35 }, exploration = { 0.5, 0.77, 0.91 }, donjons = { 0.79, 0.48, 0.33 },
    rares = { 0.86, 0.36, 0.36 }, objets = { 0.71, 0.55, 0.85 }, metiers = { 0.56, 0.81, 0.42 },
    races = { 0.88, 0.6, 0.82 }, reputations = { 0.84, 0.71, 0.43 }, jcj = { 0.62, 0.66, 0.92 },
    heritage = { 0.94, 0.82, 0.48 },
}
function C.Couleur(cle) return C.COULEURS[cle] or C.OR end

local function Texte(parent, police, couleur, justif)
    local fs = parent:CreateFontString(nil, "OVERLAY", police or "GameFontHighlightSmall")
    fs:SetJustifyH(justif or "LEFT")
    fs:SetWordWrap(false)
    fs.couleurPropre = true
    local c = couleur or C.CLAIR
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end
C.Texte = Texte

function C.Couleurer(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- Un panneau : Button (cliquable a la souris et a la manette) ou Frame.
function C.Panneau(parent, cliquable)
    local ok, f = pcall(CreateFrame, cliquable and "Button" or "Frame", nil, parent, "BackdropTemplate")
    if not ok or not f then f = CreateFrame(cliquable and "Button" or "Frame", nil, parent) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(FOND_CARTE[1], FOND_CARTE[2], FOND_CARTE[3], FOND_CARTE[4])
        f:SetBackdropBorderColor(BORD[1], BORD[2], BORD[3], BORD[4])
    end
    if cliquable then
        pcall(f.RegisterForClicks, f, "LeftButtonUp")
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local hl = f:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", 4, -4)
            hl:SetPoint("BOTTOMRIGHT", -4, 4)
            hl:SetAlpha(0.5)
        end
    end
    return f
end

-- Liseré plus vif pour la carte principale d'une page.
function C.Fort(f, fort)
    if not f.SetBackdropBorderColor then return end
    local c = fort and BORD_FORT or BORD
    f:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- Un anneau d'avancement : piste sombre, arc de couleur, pourcentage au
-- milieu. L'arc est le balayage d'un temps de recharge arrete (celui des
-- boutons d'action du jeu) ; sans lui, l'anneau reste plein ou vide.
function C.Anneau(parent, taille)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(taille, taille)
    a.piste = a:CreateTexture(nil, "BACKGROUND")
    a.piste:SetAllPoints()
    a.piste:SetTexture(DISQUE)
    a.piste:SetVertexColor(0.24, 0.18, 0.1, 1)
    a.plein = a:CreateTexture(nil, "BORDER")
    a.plein:SetAllPoints()
    a.plein:SetTexture(DISQUE)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, a, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints()
        pcall(cd.SetSwipeTexture, cd, DISQUE)
        pcall(cd.SetDrawEdge, cd, false)
        pcall(cd.SetDrawBling, cd, false)
        pcall(cd.SetHideCountdownNumbers, cd, true)
        pcall(cd.SetReverse, cd, true)
        if cd.EnableMouse then cd:EnableMouse(false) end
        a.cd = cd
    end
    local centre = CreateFrame("Frame", nil, a)
    centre:SetPoint("CENTER")
    local trou = math.floor(taille * 0.76)
    centre:SetSize(trou, trou)
    centre:SetFrameLevel(a:GetFrameLevel() + 5)
    a.trou = centre:CreateTexture(nil, "ARTWORK")
    a.trou:SetAllPoints()
    a.trou:SetTexture(DISQUE)
    a.trou:SetVertexColor(0.07, 0.05, 0.03, 1)
    a.texte = Texte(centre, taille >= 60 and "GameFontNormal" or "GameFontHighlightSmall", C.CLAIR, "CENTER")
    a.texte:SetPoint("CENTER", centre, "CENTER", 0, 0)
    if a.EnableMouse then a:EnableMouse(false) end
    return a
end

function C.PoserAnneau(a, v, couleur, texte)
    v = math.max(0, math.min(1, tonumber(v) or 0))
    local c = couleur or C.OR
    a.plein:SetVertexColor(c[1], c[2], c[3], 1)
    a.texte:SetText(texte or (math.floor(v * 100) .. "%"))
    local arc = false
    if a.cd and v > 0.005 and v < 0.995 then
        pcall(a.cd.SetSwipeColor, a.cd, c[1], c[2], c[3], 1)
        local maintenant = (GetTime and GetTime()) or 0
        local duree = 1000
        local ok = pcall(a.cd.SetCooldown, a.cd, maintenant - v * duree, duree)
        if ok and a.cd.Pause then arc = pcall(a.cd.Pause, a.cd) end
        a.cd:SetShown(arc)
    elseif a.cd then
        a.cd:Hide()
    end
    -- Sans arc (vide, plein ou client sans balayage) : l'anneau plein de
    -- couleur s'il est fini, sinon sa piste.
    a.plein:SetShown(v >= 0.995)
end

-- Une barre fine dans un cadre d'or.
function C.Barre(parent, hauteur)
    local ok, b = pcall(CreateFrame, "StatusBar", nil, parent, "BackdropTemplate")
    b = ok and b or CreateFrame("StatusBar", nil, parent)
    b:SetHeight(hauteur or 10)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetColorTexture(0.03, 0.02, 0.01, 1)
    local okC, cadre = pcall(CreateFrame, "Frame", nil, b, "BackdropTemplate")
    cadre = okC and cadre or CreateFrame("Frame", nil, b)
    cadre:SetPoint("TOPLEFT", -2, 2)
    cadre:SetPoint("BOTTOMRIGHT", 2, -2)
    if cadre.SetBackdrop then
        cadre:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
        cadre:SetBackdropBorderColor(0.45, 0.35, 0.18, 1)
    end
    cadre:SetFrameLevel(b:GetFrameLevel() + 2)
    if b.EnableMouse then b:EnableMouse(false) end
    return b
end

function C.PoserBarre(b, v, couleur)
    local c = couleur or C.OR
    b:SetValue(math.max(0, math.min(1, tonumber(v) or 0)))
    b:SetStatusBarColor(c[1], c[2], c[3])
end

-- Une icone carree dans le cadre des boutons d'action du jeu.
function C.Icone(parent, taille)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(taille, taille)
    f.icone = f:CreateTexture(nil, "ARTWORK")
    f.icone:SetPoint("TOPLEFT", 2, -2)
    f.icone:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.cadre = f:CreateTexture(nil, "OVERLAY")
    f.cadre:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    f.cadre:SetPoint("TOPLEFT", -taille * 0.36, taille * 0.36)
    f.cadre:SetPoint("BOTTOMRIGHT", taille * 0.36, -taille * 0.36)
    if f.EnableMouse then f:EnableMouse(false) end
    return f
end

-- Un titre de colonne (police des titres de la suite) et son filet.
function C.TitreDeColonne(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    f.fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.fs:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.fs:SetJustifyH("LEFT")
    f.fs:SetWordWrap(false)
    f.filet = f:CreateTexture(nil, "ARTWORK")
    f.filet:SetHeight(1)
    f.filet:SetPoint("TOPLEFT", f.fs, "TOPLEFT", 0, -22)
    f.filet:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    if f.EnableMouse then f:EnableMouse(false) end
    return f
end

function C.PoserTitre(f, texte, x, y, largeur, zone)
    C.Placer(f, zone, x, y, largeur, 24)
    f.fs:SetText(texte)
    if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, f.fs, f.filet)
    else f.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
    return y + 34
end

-- Une reserve de cartes du meme modele, reutilisees d'un rendu a l'autre.
function C.Reserve(fabrique)
    local r = { liste = {}, n = 0 }
    function r.Prendre(parent)
        r.n = r.n + 1
        local x = r.liste[r.n]
        if not x then x = fabrique(parent) r.liste[r.n] = x end
        x:Show()
        return x
    end
    function r.Cacher()
        for _, x in ipairs(r.liste) do x:Hide() end
        r.n = 0
    end
    return r
end

function C.Placer(f, zone, x, y, l, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", zone, "TOPLEFT", x, -y)
    f:SetSize(l, h)
end

function C.Survol(f, fn)
    f:SetScript("OnEnter", fn)
    f:SetScript("OnLeave", fn and function() GameTooltip:Hide() end or nil)
end
