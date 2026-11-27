local _, NS = ...

-- Les cartes de GloryCore : panneaux legers a liseré d'or (on voit le
-- parchemin dessous), anneaux d'avancement, petites tuiles de chiffres.
-- Les textes s'encrent sur le parchemin comme partout dans la suite ; seuls
-- les noms de personnage gardent leur couleur de classe.
-- La couleur dit l'etat, jamais la categorie : or en cours, vert fini,
-- gris rien a faire ; violet pour l'XP ; couleur de classe pour les noms.

NS.cartes = {}
local C = NS.cartes

local DISQUE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local MASQUE_ROND = "Interface\\Masks\\CircleMaskScalable"
local TEINTE = { 0.09, 0.066, 0.04 }
local BORD = { 0.55, 0.42, 0.2 }
local OR_JEU = { 1, 0.82, 0 }
local PAPIER = { 0.87, 0.79, 0.62 }

C.OR = OR_JEU
C.BLANC = { 1, 1, 1 }
C.GRIS = { 0.8, 0.8, 0.8 }
C.VERT = { 0.31, 0.82, 0.41 }
C.VIDE = { 0.6, 0.6, 0.6 }
C.VIOLET = { 0.71, 0.55, 0.85 }
C.ECART = 10

local function Parchemin() return NS.charte and NS.charte.Fond and NS.charte.Fond() == "parchemin" end

-- Couleur d'un avancement : or en cours, vert fini, gris sans rien.
function C.Etat(fait, total)
    if not total or total <= 0 then return C.VIDE end
    if fait >= total then return C.VERT end
    return OR_JEU
end

local function Texte(parent, police, couleur, justif)
    local fs = parent:CreateFontString(nil, "OVERLAY", police or "GameFontHighlightSmall")
    fs:SetJustifyH(justif or "LEFT")
    fs:SetWordWrap(false)
    local c = couleur or C.BLANC
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end
C.Texte = Texte

function C.Couleurer(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- Fond et liseré d'une carte selon le fond de la fenetre, allumee ou non.
local function Teinter(f)
    if not f.SetBackdropColor then return end
    local p = Parchemin()
    local a
    if f.allumee or f.actif then a = p and 0.26 or 0.35
    elseif f.tuile then a = 0.10
    else a = p and 0.12 or 0.20 end
    f:SetBackdropColor(TEINTE[1], TEINTE[2], TEINTE[3], a)
    if f.allumee or f.actif then
        f:SetBackdropBorderColor(OR_JEU[1], OR_JEU[2], OR_JEU[3], 1)
    else
        f:SetBackdropBorderColor(BORD[1], BORD[2], BORD[3], p and 0.7 or 1)
    end
end
C.Teinter = Teinter

local function Allumer(f) f.allumee = true Teinter(f) end
local function Eteindre(f) f.allumee = false Teinter(f) end

-- Un panneau : Button (cliquable a la souris et a la manette) ou Frame.
-- La carte ou l'on est (souris ou manette) s'allume : fond plus dense,
-- liseré d'or, lueur du jeu.
function C.Panneau(parent, cliquable, tuile)
    local ok, f = pcall(CreateFrame, cliquable and "Button" or "Frame", nil, parent, "BackdropTemplate")
    if not ok or not f then f = CreateFrame(cliquable and "Button" or "Frame", nil, parent) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    f.tuile = tuile
    Teinter(f)
    if cliquable then
        pcall(f.RegisterForClicks, f, "LeftButtonUp")
        f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local hl = f:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", 4, -4)
            hl:SetPoint("BOTTOMRIGHT", -4, 4)
            hl:SetAlpha(0.35)
        end
        if hooksecurefunc then
            hooksecurefunc(f, "LockHighlight", Allumer)
            hooksecurefunc(f, "UnlockHighlight", Eteindre)
        end
        f:SetScript("OnEnter", Allumer)
        f:SetScript("OnLeave", Eteindre)
    end
    return f
end

-- L'infobulle d'une carte, sans perdre son allumage.
function C.Survol(f, fn)
    f:SetScript("OnEnter", function(self) Allumer(self) if fn then fn(self) end end)
    f:SetScript("OnLeave", function(self) Eteindre(self) if fn then GameTooltip:Hide() end end)
end

-- Un anneau d'avancement de 36 : piste, arc (balayage d'un temps de
-- recharge arrete, comme les boutons d'action), grain leger du jeu,
-- pourcentage au milieu.
C.TAILLE_ANNEAU = 36
function C.Anneau(parent, taille)
    taille = taille or C.TAILLE_ANNEAU
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(taille, taille)
    a.piste = a:CreateTexture(nil, "BACKGROUND")
    a.piste:SetAllPoints()
    a.piste:SetTexture(DISQUE)
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
    -- Le grain : la texture des barres du jeu, en lumiere legere, en rond.
    local grain = CreateFrame("Frame", nil, a)
    grain:SetAllPoints()
    grain:SetFrameLevel(a:GetFrameLevel() + 3)
    a.grain = grain:CreateTexture(nil, "OVERLAY")
    a.grain:SetAllPoints()
    a.grain:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    a.grain:SetBlendMode("ADD")
    a.grain:SetAlpha(0.22)
    if grain.CreateMaskTexture then
        local m = grain:CreateMaskTexture()
        if m then
            pcall(m.SetTexture, m, MASQUE_ROND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(a.grain)
            pcall(a.grain.AddMaskTexture, a.grain, m)
        end
    end
    local centre = CreateFrame("Frame", nil, a)
    centre:SetPoint("CENTER")
    local trou = math.floor(taille * 0.74 + 0.5)
    centre:SetSize(trou, trou)
    centre:SetFrameLevel(a:GetFrameLevel() + 5)
    a.trou = centre:CreateTexture(nil, "ARTWORK")
    a.trou:SetAllPoints()
    a.trou:SetTexture(DISQUE)
    a.texte = Texte(centre, "GameFontHighlightSmall", C.BLANC, "CENTER")
    a.texte:SetPoint("CENTER", centre, "CENTER", 0, 0)
    if a.EnableMouse then a:EnableMouse(false) end
    if grain.EnableMouse then grain:EnableMouse(false) end
    if centre.EnableMouse then centre:EnableMouse(false) end
    return a
end

function C.PoserAnneau(a, v, couleur, texte)
    v = math.max(0, math.min(1, tonumber(v) or 0))
    local c = couleur or OR_JEU
    -- Piste et trou selon le fond : clairs sur le parchemin, sombres sinon.
    if Parchemin() then
        a.piste:SetVertexColor(0.36, 0.24, 0.10, 0.30)
        a.trou:SetVertexColor(PAPIER[1], PAPIER[2], PAPIER[3], 1)
    else
        a.piste:SetVertexColor(0.24, 0.18, 0.10, 1)
        a.trou:SetVertexColor(0.07, 0.05, 0.03, 1)
    end
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
    a.plein:SetShown(v >= 0.995)
end

-- La pastille des points : le ruban dans l'anneau dore du jeu (memes
-- proportions que les onglets ronds des suivis).
function C.Pastille(parent, taille)
    taille = taille or 20
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(taille, taille)
    p.fond = p:CreateTexture(nil, "BACKGROUND")
    p.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    p.fond:SetPoint("CENTER")
    p.fond:SetSize(taille * 16 / 20, taille * 16 / 20)
    p.icone = p:CreateTexture(nil, "ARTWORK")
    p.icone:SetPoint("CENTER")
    p.icone:SetSize(taille * 13 / 20, taille * 13 / 20)
    p.icone:SetTexture("Interface\\Icons\\INV_Misc_Ribbon_01")
    p.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if p.CreateMaskTexture then
        local m = p:CreateMaskTexture()
        if m then
            pcall(m.SetTexture, m, MASQUE_ROND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(p.icone)
            pcall(p.icone.AddMaskTexture, p.icone, m)
        end
    end
    p.bordure = p:CreateTexture(nil, "OVERLAY")
    p.bordure:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    p.bordure:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    p.bordure:SetSize(taille * 41 / 24, taille * 41 / 24)
    if p.EnableMouse then p:EnableMouse(false) end
    return p
end

-- Une barre fine dans un cadre d'or.
function C.Barre(parent, hauteur)
    local ok, b = pcall(CreateFrame, "StatusBar", nil, parent, "BackdropTemplate")
    b = ok and b or CreateFrame("StatusBar", nil, parent)
    b:SetHeight(hauteur or 6)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetColorTexture(0.03, 0.02, 0.01, 0.6)
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
    local c = couleur or OR_JEU
    b:SetValue(math.max(0, math.min(1, tonumber(v) or 0)))
    b:SetStatusBarColor(c[1], c[2], c[3])
end

-- Une icone carree dans le cadre du grimoire du jeu (comme toute la suite).
function C.Icone(parent, taille)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(taille, taille)
    f.icone = f:CreateTexture(nil, "ARTWORK")
    f.icone:SetAllPoints()
    f.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local S = _G.CoreSuite
    if S and S.HabillerIcone then pcall(S.HabillerIcone, f, f.icone) end
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
        if x.SetBackdrop then x.allumee = false x.actif = nil Teinter(x) end
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
