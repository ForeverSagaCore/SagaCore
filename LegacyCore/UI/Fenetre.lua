local _, NS = ...

-- Fenetre de LegacyCore : la meme charte et la meme taille que les autres
-- add-ons de la suite. En haut, les personnages (le connecte d'abord) ; a
-- gauche, les pages ; a droite, le contenu.
--
-- Pages :
--   Mes arbres     les trois arbres d'heritage du personnage choisi
--   Defis          ce que vos personnages ont atteint, et le plus proche
--   Personnages    tous vos personnages, points depenses par arbre
--   Conseils       les choix les plus repandus dans la communaute

NS.fenetre = {}
local fen = NS.fenetre
local L = NS.L

local LARGEUR, HAUTEUR = 1060, 740
local LARGEUR_MENU = 170
local ECART_MENU = 14
local HAUTEUR_LIGNE = 20
local RETRAIT = 16
local TAILLE_PORTRAIT = 30

local cadre
local etat = { page = "arbres", cle = nil, persoVu = nil }
local BrancherManette

local PAGES = {
    { cle = "arbres", section = "MENU_LEGACY", libelle = "NAV_TREES", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    { cle = "defis", libelle = "NAV_CHALLENGES", icone = "Interface\\Icons\\INV_Misc_Note_01" },
    { cle = "persos", section = "MENU_FAMILY", libelle = "NAV_CHARACTERS", icone = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
    { cle = "chrono", libelle = "NAV_TIMELINE", icone = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { cle = "conseils", section = "MENU_HELP", libelle = "NAV_ADVICE", icone = "Interface\\Icons\\INV_Misc_Book_09" },
}
fen.PAGES = PAGES

-- Les memes couleurs et polices que QuestCore et CraftCore (et donc les
-- memes encres sur le parchemin) : titres en or, texte en blanc, ce qui est
-- acquis en vert, le secondaire en gris clair, le verrouille en gris.
local ESPACE_SECTION = 14
local GRIS = { 0.6, 0.6, 0.6 }
local SECONDAIRE = { 0.8, 0.8, 0.8 }
local OR = { 1, 0.82, 0 }
local BLANC = { 1, 1, 1 }
local VERT = { 0.31, 0.82, 0.41 }

-- ---------------------------------------------------------------------------
-- Personnage choisi : le meme dans toute la suite
-- ---------------------------------------------------------------------------

-- Les personnages de la faction regardee (onglets Alliance / Horde).
local function PersosVisibles()
    local S, liste = NS.suite, {}
    for _, p in ipairs(NS.base.Personnages()) do
        if not (S and S.Visible) or S.Visible(p.cle) then table.insert(liste, p) end
    end
    return liste
end

local function ChoisirPerso(cle)
    etat.cle = cle
    local S = NS.suite
    if S and S.PoserPersonnage and cle then etat.persoVu = S.PoserPersonnage(cle) end
end

local function SuivreLaSuite()
    local S = NS.suite
    if not (S and S.Personnage) then return end
    local cle, version = S.Personnage()
    if version and version ~= etat.persoVu then
        etat.persoVu = version
        if cle and NS.base.Personnage(cle) then etat.cle = cle end
    end
end

-- ---------------------------------------------------------------------------
-- Lignes du contenu
-- ---------------------------------------------------------------------------

-- Un nom a la couleur de sa classe : la meme police et la meme taille que
-- le reste, la meme ombre douce (celle du parchemin), rien de plus.
local function NomLisible(fs)
    fs:SetShadowColor(0, 0, 0, 0.22)
    fs:SetShadowOffset(1, -1)
end

local function Ligne(contenu, index)
    contenu.lignes = contenu.lignes or {}
    local l = contenu.lignes[index]
    if l then return l end
    l = CreateFrame("Button", nil, contenu)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.gauche = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.gauche:SetJustifyH("LEFT")
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetJustifyH("RIGHT")
    l.droite:SetPoint("TOPRIGHT", l, "TOPRIGHT", -6, -4)
    l.filet = l:CreateTexture(nil, "ARTWORK")
    NS.charte.Filet(l.filet, l)
    l.filet:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    NS.charte.PoliceStable(l.gauche)
    l.detail = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.detail:SetJustifyH("LEFT")
    l.detail:SetWordWrap(true)
    -- Bandeau leger derriere un titre de categorie.
    l.bandeau = l:CreateTexture(nil, "BACKGROUND")
    l.bandeau:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    l.bandeau:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, 2)
    l.bandeau:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    l.bandeau:SetBlendMode("ADD")
    l.bandeau:SetAlpha(0.35)
    l.bandeau:Hide()
    -- Portrait d'un personnage, dans son cadre.
    l.cadreVisage = l:CreateTexture(nil, "BORDER")
    l.cadreVisage:SetSize(34, 34)
    l.cadreVisage:SetColorTexture(0, 0, 0, 0) -- rond : l'anneau de classe remplace le cadre carre
    l.cadreVisage:Hide()
    l.visage = l:CreateTexture(nil, "ARTWORK")
    l.visage:SetPoint("TOPLEFT", l.cadreVisage, "TOPLEFT", 5, -5)
    l.visage:SetPoint("BOTTOMRIGHT", l.cadreVisage, "BOTTOMRIGHT", -5, 5)
    l.visage:Hide()
    contenu.lignes[index] = l
    return l
end

-- options : retrait, icone, texte, couleur, droite, couleurDroite, detail,
-- police, desature, survol
local function Poser(contenu, index, y, o)
    local l = Ligne(contenu, index)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    local x = 2 + (o.retrait or 0)
    l.bandeau:SetShown(o.bandeau == true)
    l.cadreVisage:Hide()
    l.visage:Hide()
    if o.visage then
        l.cadreVisage:ClearAllPoints()
        l.cadreVisage:SetPoint("TOPLEFT", l, "TOPLEFT", x - 2, 1)
        l.cadreVisage:Show()
        l.visage:Show()
        o.visage(l.visage)
        x = x + 38
    end
    if o.icone then
        l.icone:ClearAllPoints()
        l.icone:SetPoint("TOPLEFT", l, "TOPLEFT", x, -1)
        l.icone:SetTexture(o.icone)
        l.icone:SetDesaturated(o.desature == true)
        l.icone:Show()
        x = x + 22
    else
        l.icone:Hide()
    end
    l.gauche:SetFontObject(o.police or "GameFontHighlightSmall")
    l.gauche:ClearAllPoints()
    l.gauche:SetPoint("TOPLEFT", l, "TOPLEFT", x, -4)
    l.gauche:SetPoint("RIGHT", l.droite, "LEFT", -8, 0)
    -- Une note peut passer a la ligne ; un nom reste sur une ligne.
    l.gauche:SetWordWrap(o.multi == true)
    l.gauche:SetText(o.texte or "")
    local c = o.couleur or BLANC
    l.gauche:SetTextColor(c[1], c[2], c[3])
    -- Couleur de classe : la vraie, jamais encree (le pretre reste blanc),
    -- cernee d'un trait fin et sans ombre pour se lire sur le parchemin.
    l.gauche.couleurPropre = c.classe or nil
    l.gauche.nomDePerso = c.classe or nil
    if c.classe then NomLisible(l.gauche) end
    if l.colNom then l.colNom:Hide() l.colNiv:Hide() l.colTemps:Hide() end
    l.droite:SetText(o.droite or "")
    local cd = o.couleurDroite or GRIS
    l.droite:SetTextColor(cd[1], cd[2], cd[3])
    local hauteur = HAUTEUR_LIGNE
    if o.section and NS.charte.TitreDeSection(l.gauche, l.filet) then hauteur = HAUTEUR_LIGNE + 6 end
    if o.couleurTitre then l.gauche:SetTextColor(o.couleurTitre[1], o.couleurTitre[2], o.couleurTitre[3]) end
    if o.multi then hauteur = math.max(HAUTEUR_LIGNE, (l.gauche:GetStringHeight() or 12) + 8) end
    if o.detail then
        l.detail:ClearAllPoints()
        l.detail:SetPoint("TOPLEFT", l, "TOPLEFT", x, -(HAUTEUR_LIGNE - 2))
        l.detail:SetPoint("RIGHT", l, "RIGHT", -8, 0)
        l.detail:SetText(o.detail)
        local cdet = o.couleurDetail or SECONDAIRE
        l.detail:SetTextColor(cdet[1], cdet[2], cdet[3])
        l.detail:Show()
        hauteur = hauteur + math.max(12, l.detail:GetStringHeight() or 12) + 2
    else
        l.detail:Hide()
    end
    if o.visage then hauteur = math.max(hauteur, 38) end
    l:SetHeight(hauteur)
    l.filet:SetShown(o.filet == true)
    l:EnableMouse(o.survol ~= nil)
    l:SetScript("OnEnter", o.survol)
    l:SetScript("OnLeave", o.survol and function() GameTooltip:Hide() end or nil)
    l:Show()
    return y + hauteur + (o.apres or 0)
end

-- Titre de section : comme QuestCore, en or, souligne d'un filet.
local function Titre(contenu, index, y, texte, bandeau)
    if y > 0 then y = y + ESPACE_SECTION end
    return Poser(contenu, index, y, { texte = texte, section = true, filet = true, apres = 6, bandeau = bandeau })
end

local function NomDeClasse(jeton)
    local noms = _G.LOCALIZED_CLASS_NAMES_MALE
    return (type(noms) == "table" and jeton and noms[jeton]) or tostring(jeton or "?")
end

local function NomDeMetier(ligne, nom)
    return nom or L["PROF_" .. tostring(ligne)] or ("#" .. tostring(ligne))
end

local NOMS_ARBRES = { metiers = "TREE_PROFESSIONS", aventure = "TREE_ADVENTURE", ressources = "TREE_RESOURCES" }

local DessinerArbres, PoserVisage
-- ---------------------------------------------------------------------------
-- Arbres dessines : une case par talent, a sa place
-- ---------------------------------------------------------------------------

-- Les trois arbres cote a cote, comme dans la fenetre d'heritage du jeu :
-- un carre par talent, bien espaces, son rang dans une case sombre bordee
-- d'or au coin, une fine fleche quand un talent en ouvre un autre. Tout
-- tient sur un ecran, sans defiler.
local TAILLE_MAX, ECART_ARBRES = 44, 24
local ESPACE = 1.8           -- pas entre deux talents, en tailles de talent (comme le jeu)
local COULEUR_FLECHE = { 0.30, 0.27, 0.23, 1 }
local VERT_VALIDE = { 0.18, 0.62, 0.24 }
local GRIS_CADRE = 0.62

-- Les cadres de talents du jeu (carre a coins coupes, ou octogone d'un
-- choix), s'ils existent dans ce client.
local function AtlasExiste(nom)
    local f = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if not f then return false end
    local ok, info = pcall(f, nom)
    return ok and info ~= nil
end
local atlasVus = {}
local function Atlas(forme, etat)
    local nom = "talents-node-" .. forme .. "-" .. etat
    if atlasVus[nom] == nil then atlasVus[nom] = AtlasExiste(nom) end
    return atlasVus[nom] and nom or nil
end

-- Un lien : un trait, et une pointe pleine faite de traits de plus en plus
-- courts.
local POINTE = 7
local function Lien(contenu, rang)
    contenu.liens = contenu.liens or {}
    local l = contenu.liens[rang]
    if l then return l end
    if not contenu.CreateLine then return nil end
    l = { trait = contenu:CreateLine(nil, "ARTWORK"), pointe = {} }
    for i = 0, POINTE do l.pointe[i] = contenu:CreateLine(nil, "ARTWORK") end
    contenu.liens[rang] = l
    return l
end
local function CacherLien(l)
    l.trait:Hide()
    for _, t in pairs(l.pointe) do t:Hide() end
end

local function Case(contenu, rang)
    contenu.cases = contenu.cases or {}
    local c = contenu.cases[rang]
    if c then return c end
    c = CreateFrame("Button", nil, contenu)
    c:SetFrameLevel(contenu:GetFrameLevel() + 2)
    c.fond = c:CreateTexture(nil, "BACKGROUND")
    c.fond:SetAllPoints()
    c.fond:SetColorTexture(0, 0, 0, 1)
    c.icone = c:CreateTexture(nil, "ARTWORK")
    c.icone:SetAllPoints()
    c.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.cadre = c:CreateTexture(nil, "OVERLAY", nil, -1)
    c.bord = c:CreateTexture(nil, "BORDER")
    c.bord:SetPoint("TOPLEFT", -2, 2)
    c.bord:SetPoint("BOTTOMRIGHT", 2, -2)
    -- Le rang, dans sa case au coin : fond sombre, fin liseré dore, coins
    -- arrondis, chiffres blancs.
    local okB, case = pcall(CreateFrame, "Frame", nil, c, "BackdropTemplate")
    if not okB then case = CreateFrame("Frame", nil, c) end
    case:SetFrameLevel(c:GetFrameLevel() + 3)
    if case.SetBackdrop then
        case:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        case:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
        case:SetBackdropBorderColor(0.62, 0.50, 0.28, 1)
    end
    c.caseRang = case
    -- Les chiffres sur un calque a part, au-dessus du fond de la case.
    local texte = CreateFrame("Frame", nil, case)
    texte:SetAllPoints()
    texte:SetFrameLevel(case:GetFrameLevel() + 2)
    c.rang = texte:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.rang:SetPoint("CENTER", case, "CENTER", 0, 0)
    c.rang:SetShadowOffset(1, -1)
    c.rang:SetShadowColor(0, 0, 0, 1)
    c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    contenu.cases[rang] = c
    return c
end

-- Taille d'un talent : tout son decor suit.
local function Dimensionner(c, n)
    if c.taille == n then return end
    c.taille = n
    c:SetSize(n, n)
    local d = math.floor(n * 0.15 + 0.5)
    c.cadre:ClearAllPoints()
    c.cadre:SetPoint("TOPLEFT", -d, d)
    c.cadre:SetPoint("BOTTOMRIGHT", d, -d)
    -- La case du rang deborde du coin bas droit, comme dans le jeu.
    c.caseRang:SetSize(math.max(30, math.floor(n * 0.86)), math.max(20, math.floor(n * 0.58)))
    c.caseRang:ClearAllPoints()
    c.caseRang:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", math.floor(n * 0.36 + 0.5), -math.floor(n * 0.28 + 0.5))
    local police = c.rang:GetFont()
    if police then c.rang:SetFont(NS.Police(police), math.max(12, math.floor(n * 0.37 + 0.5)), "") end
end

local function TitreDArbre(contenu, rang)
    contenu.titresArbres = contenu.titresArbres or {}
    local t = contenu.titresArbres[rang]
    if t then return t end
    t = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetJustifyH("CENTER")
    contenu.titresArbres[rang] = t
    return t
end

-- Une fleche de la case `depuis` a la case `vers`, bord a bord.
local function Fleche(l, depuis, vers, actif)
    CacherLien(l)
    local x1, y1 = depuis.gx, depuis.gy
    local x2, y2 = vers.gx, vers.gy
    local p1, p2, ux, uy
    if y1 == y2 then
        if x2 > x1 then p1, p2, ux, uy = "RIGHT", "LEFT", 1, 0 else p1, p2, ux, uy = "LEFT", "RIGHT", -1, 0 end
    elseif x1 == x2 then
        if y2 > y1 then p1, p2, ux, uy = "BOTTOM", "TOP", 0, -1 else p1, p2, ux, uy = "TOP", "BOTTOM", 0, 1 end
    else
        return
    end
    local k = actif and { VERT_VALIDE[1], VERT_VALIDE[2], VERT_VALIDE[3], 1 } or COULEUR_FLECHE
    local marge = 3
    -- Le trait, jusqu'a la base de la pointe.
    l.trait:SetThickness(2)
    l.trait:SetColorTexture(k[1], k[2], k[3], k[4])
    l.trait:SetStartPoint(p1, depuis, ux * marge, uy * marge)
    l.trait:SetEndPoint(p2, vers, -ux * (marge + POINTE), -uy * (marge + POINTE))
    l.trait:Show()
    -- La pointe : des traits perpendiculaires, du plus large au plus court.
    local px, py = -uy, ux
    for i = 0, POINTE do
        local t = l.pointe[i]
        local recul = marge + i
        local demi = (POINTE - i) * 4 / POINTE + 0.5
        local cx, cy = -ux * recul, -uy * recul
        t:SetThickness(1.5)
        t:SetColorTexture(k[1], k[2], k[3], k[4])
        t:SetStartPoint(p2, vers, cx + px * demi, cy + py * demi)
        t:SetEndPoint(p2, vers, cx - px * demi, cy - py * demi)
        t:Show()
    end
end

-- La charte des talents de la suite (ClassCore) : cadres carres du jeu
-- (jaune au maximum, vert ouvert ou en cours, gris ferme), le rang en
-- chiffre du jeu au coin, les fleches du jeu, un titre de rubrique par arbre.
local BOUTON_T, ICONE_T, PAS_T, HAUT_TITRE_T = 40, 36, 56, 34
local JAUNE_T, VERT_T, GRIS_T = { 1, 0.82, 0 }, { 0.12, 1, 0.12 }, { 0.5, 0.5, 0.5 }

local function GrilleTalents(contenu)
    if contenu.grilleTalents then return contenu.grilleTalents end
    local g = CreateFrame("Frame", nil, contenu)
    g:SetFrameLevel(contenu:GetFrameLevel() + 2)
    g.boutons, g.lignes, g.pointes, g.titres = {}, {}, {}, {}
    contenu.grilleTalents = g
    return g
end

local function TitreTalents(contenu, g, i)
    local t = g.titres[i]
    if t then return t end
    t = { fs = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = contenu:CreateTexture(nil, "ARTWORK"),
          droite = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
    t.fs:SetJustifyH("LEFT") t.fs:SetWordWrap(false)
    t.droite:SetJustifyH("RIGHT") t.droite:SetWordWrap(false)
    g.titres[i] = t
    return t
end

local function BoutonTalent(g, i)
    local b = g.boutons[i]
    if b then return b end
    b = CreateFrame("Button", nil, g)
    b:SetSize(BOUTON_T, BOUTON_T)
    b.icone = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.icone:SetSize(ICONE_T, ICONE_T)
    b.icone:SetPoint("CENTER")
    b.voile = b:CreateTexture(nil, "BORDER", nil, 1)
    b.voile:SetSize(ICONE_T, ICONE_T)
    b.voile:SetPoint("CENTER")
    b.voile:SetColorTexture(0, 0, 0, 1)
    b.bord = b:CreateTexture(nil, "ARTWORK")
    b.bord:SetPoint("CENTER")
    b.survol = b:CreateTexture(nil, "HIGHLIGHT")
    b.survol:SetPoint("CENTER")
    b.survol:SetBlendMode("ADD")
    b.survol:SetAlpha(0.5)
    b:SetHighlightTexture(b.survol)
    b.chiffre = b:CreateFontString(nil, "OVERLAY")
    b.chiffre:SetFontObject(_G.SystemFont16_Shadow_ThickOutline or _G.NumberFontNormal)
    b.chiffre.couleurPropre = true
    b.chiffre:SetPoint("BOTTOM", b, "BOTTOM", 11, 4)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() end)
    g.boutons[i] = b
    return b
end

local function HabillerTalent(b, etat, choix)
    local atlas = Atlas(choix and "choice" or "square", etat == "max" and "yellow" or (etat == "ouvert" and "green" or "gray"))
    if atlas then
        b.bord:SetAtlas(atlas, true)
        b.survol:SetAtlas(atlas, true)
    else
        b.bord:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.bord:SetSize(64, 64)
        b.survol:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        b.survol:SetSize(ICONE_T, ICONE_T)
    end
    local ferme = etat == "ferme"
    b.icone:SetDesaturated(ferme)
    b.voile:SetShown(ferme)
    b.voile:SetAlpha(ferme and 0.55 or 0)
end

DessinerArbres = function(contenu, arbres, y, disponibles)
    local g = GrilleTalents(contenu)
    for _, b in ipairs(g.boutons) do b:Hide() end
    for _, l in ipairs(g.lignes) do l:Hide() end
    for _, p in ipairs(g.pointes) do p:Hide() end
    for _, t in ipairs(g.titres) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
    local largeur = (contenu:GetWidth() or 760) - 8
    -- Dans l'ordre du jeu, sans les arbres vides.
    local ORDRE = { aventure = 1, ressources = 2, metiers = 3 }
    local tries = {}
    for _, a in ipairs(arbres) do if #(a.noeuds or {}) > 0 then table.insert(tries, a) end end
    table.sort(tries, function(p, q) return (ORDRE[p.genre] or 9) < (ORDRE[q.genre] or 9) end)
    if #tries == 0 then g:Hide() return y end
    -- Colonnes et rangees de chaque arbre.
    local plans, maxCol, maxRang = {}, 1, 1
    for _, a in ipairs(tries) do
        local xs, ys, vusX, vusY = {}, {}, {}, {}
        for _, n in ipairs(a.noeuds) do
            if not vusX[n.x] then vusX[n.x] = true table.insert(xs, n.x) end
            if not vusY[n.y] then vusY[n.y] = true table.insert(ys, n.y) end
        end
        table.sort(xs) table.sort(ys)
        local colonne, rangee = {}, {}
        for i, v in ipairs(xs) do colonne[v] = i end
        for i, v in ipairs(ys) do rangee[v] = i end
        maxCol, maxRang = math.max(maxCol, #xs), math.max(maxRang, #ys)
        table.insert(plans, { arbre = a, colonne = colonne, rangee = rangee, nCol = #xs, nRang = #ys })
    end
    local nb = #plans
    local colonnePage = math.floor((largeur - (nb - 1) * ECART_ARBRES) / nb)
    -- 80 % de la taille du jeu, moins si les arbres ne tiennent pas.
    local pas = math.min(PAS_T * 0.8, math.floor((colonnePage - 24 - BOUTON_T * 0.8) / math.max(maxCol - 1, 1)))
    local k = pas / PAS_T
    local hauteur = HAUT_TITRE_T + 10 + (maxRang - 1) * PAS_T * k + BOUTON_T * k + 14
    g:SetScale(k)
    g:SetSize(largeur / k, hauteur / k)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y / k)
    local n0, nl = 0, 0
    for rang, pl in ipairs(plans) do
        local a, parId = pl.arbre, {}
        local gauche = (rang - 1) * (colonnePage + ECART_ARBRES)
        -- Le titre de l'arbre et ses points, comme une rubrique.
        local t = TitreTalents(contenu, g, rang)
        t.fs:ClearAllPoints()
        t.fs:SetPoint("TOPLEFT", contenu, "TOPLEFT", gauche, -y)
        t.fs:SetWidth(colonnePage - 70)
        t.fs:SetText(a.nom or L[NOMS_ARBRES[a.genre] or ""] or "?")
        t.droite:ClearAllPoints()
        t.droite:SetPoint("TOPRIGHT", contenu, "TOPLEFT", gauche + colonnePage, -(y + 3))
        t.droite:SetWidth(70)
        t.droite:SetText((string.gsub(string.format(L.TREE_SPENT or "%d", NS.base.Depenses(a)), "^%s*%((.-)%)%s*$", "%1")))
        t.filet:ClearAllPoints()
        t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
        t.filet:SetSize(colonnePage, 1)
        if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet) end
        t.fs:Show() t.filet:Show() t.droite:Show()
        local largeurGrille = (pl.nCol - 1) * PAS_T * k + BOUTON_T * k
        local xg = gauche + math.floor((colonnePage - largeurGrille) / 2)
        for _, n in ipairs(a.noeuds) do
            n0 = n0 + 1
            local b = BoutonTalent(g, n0)
            local gx, gy = pl.colonne[n.x], pl.rangee[n.y]
            b.gx, b.gy = gx, gy
            b:ClearAllPoints()
            b:SetPoint("CENTER", g, "TOPLEFT", (xg + BOUTON_T * k / 2 + (gx - 1) * PAS_T * k) / k,
                -(HAUT_TITRE_T + 10 + BOUTON_T * k / 2 + (gy - 1) * PAS_T * k) / k)
            local r, maxi = tonumber(n.rang) or 0, tonumber(n.maxi) or 1
            local icone = n.icone or NS.IconeDeSort(n.sort)
            b.icone:SetTexCoord(0, 1, 0, 1)
            if icone then b.icone:SetTexture(icone)
            elseif not (n.atlas and pcall(b.icone.SetAtlas, b.icone, n.atlas)) then
                b.icone:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            local ouvrable = r == 0 and (disponibles or 0) > 0 and not (n.dispo == false or n.verrou)
            local etat = (r >= maxi) and "max" or ((r > 0 or ouvrable) and "ouvert" or "ferme")
            b.etat, b.rang = etat, r
            HabillerTalent(b, etat, n.choix)
            if etat == "ferme" and r == 0 then b.chiffre:SetText("")
            else
                b.chiffre:SetText(tostring(r))
                local c = etat == "max" and JAUNE_T or VERT_T
                b.chiffre:SetTextColor(c[1], c[2], c[3])
            end
            local noeud = n
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(noeud.nom or "?", 1, 0.82, 0)
                GameTooltip:AddLine(string.format(L.RANK_OF, tonumber(noeud.rang) or 0, tonumber(noeud.maxi) or 1), 1, 1, 1)
                if noeud.description then GameTooltip:AddLine(noeud.description, 0.9, 0.9, 0.9, true) end
                GameTooltip:Show()
            end)
            if n.id then parId[n.id] = b end
            b:Show()
        end
        -- Les fleches du jeu : jaunes depuis un talent pris, grises sinon,
        -- sombres vers un talent ferme.
        for _, n in ipairs(a.noeuds) do
            local b1 = n.id and parId[n.id]
            for _, cible in ipairs(n.liens or {}) do
                local b2 = parId[cible]
                if b1 and b2 and g.CreateLine then
                    nl = nl + 1
                    local l = g.lignes[nl]
                    if not l then
                        l = g:CreateLine(nil, "BORDER", nil, 2)
                        if l then l:SetThickness(6) end
                        g.lignes[nl] = l
                    end
                    local pt = g.pointes[nl]
                    if not pt then pt = g:CreateTexture(nil, "BORDER", nil, 3) g.pointes[nl] = pt end
                    if l then
                        local actif = (b1.rang or 0) > 0
                        local style = actif and "yellow" or (b2.etat == "ferme" and "locked" or "gray")
                        if AtlasExiste("talents-arrow-line-" .. style) then
                            l:SetAtlas("talents-arrow-line-" .. style)
                            pt:SetAtlas("talents-arrow-head-" .. style, true)
                        else
                            local c = actif and JAUNE_T or GRIS_T
                            l:SetColorTexture(c[1], c[2], c[3], 1)
                            pt:SetColorTexture(c[1], c[2], c[3], 1)
                            pt:SetSize(10, 10)
                        end
                        local angle = math.atan2((b2.gy or 1) - (b1.gy or 1), (b1.gx or 1) - (b2.gx or 1))
                        local dx, dy = math.cos(angle) * (BOUTON_T / 2 + 2), math.sin(angle) * (BOUTON_T / 2 + 2)
                        l:SetStartPoint("CENTER", b1)
                        l:SetEndPoint("CENTER", b2, dx, dy)
                        pt:ClearAllPoints()
                        pt:SetPoint("CENTER", b2, "CENTER", dx, dy)
                        pt:SetRotation(angle - math.pi / 2)
                        l:Show() pt:Show()
                    end
                end
            end
        end
    end
    g:Show()
    return y + hauteur + 10
end
NS.DessinerArbres = function(...) return DessinerArbres(...) end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local function RendreArbres(contenu, p, index, y)
    local releve = p.releve
    -- Toujours les memes trois lignes en tete, quel que soit le personnage :
    -- passer de l'un a l'autre ne fait rien bouger.
    local debloque = (p.niveau or 0) >= NS.base.NIVEAU_HERITAGE
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_TREES)
    index = index + 1
    y = Poser(contenu, index, y, { texte = debloque and string.format(L.UNLOCKED_LEVEL, p.niveau or 0)
        or string.format(L.LOCKED_LEVEL, NS.base.NIVEAU_HERITAGE, p.niveau or 0), couleur = debloque and VERT or BLANC })
    local arbres = releve and releve.arbres or {}
    local depenses, disponibles = 0, nil
    for _, a in ipairs(arbres) do
        depenses = depenses + NS.base.Depenses(a)
        if a.disponibles then disponibles = a.disponibles end
    end
    index = index + 1
    y = Poser(contenu, index, y, { texte = string.format(L.POINTS_SPENT, depenses, NS.base.POINTS_MAX),
        droite = string.format(L.POINTS_FREE, disponibles or 0),
        couleurDroite = (disponibles or 0) > 0 and VERT or GRIS })
    -- Des points a depenser, sur le personnage connecte : la fenetre du jeu,
    -- au bout de la ligne des points (rien ne se decale).
    local ligne = contenu.lignes[index]
    if not contenu.boutonHeritage then
        local b = CreateFrame("Button", nil, contenu, "UIPanelButtonTemplate")
        b:SetHeight(20)
        b:SetScript("OnClick", function()
            -- Le jeu reserve sa fenetre d'heritage a sa propre interface : y
            -- toucher (charger son module, la montrer) contamine l'interface et
            -- bloque ensuite d'autres actions (sacs...). On rappelle la touche.
            local touche = NS.ToucheHeritage()
            NS.Dire(touche and string.format(L.OPEN_LEGACY_KEY, touche) or L.OPEN_LEGACY_FAIL)
        end)
        contenu.boutonHeritage = b
    end
    local bouton = contenu.boutonHeritage
    bouton:SetText(L.OPEN_LEGACY)
    bouton:SetWidth((bouton:GetTextWidth() or 120) + 30)
    bouton:ClearAllPoints()
    bouton:SetPoint("RIGHT", ligne.droite, "LEFT", -12, 0)
    local moi = p.cle == NS.ClePersonnage()
    bouton:SetShown((disponibles or 0) > 0)
    bouton:SetEnabled(moi)
    bouton:SetScript("OnEnter", not moi and function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(string.format(L.OPEN_LEGACY_OTHER, NS.NomCourt(p.cle)), 1, 1, 1, true)
        GameTooltip:Show()
    end or nil)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if bouton.SetMotionScriptsWhileDisabled then bouton:SetMotionScriptsWhileDisabled(true) end
    -- Au clic de souris : un bouton securise du jeu pose par-dessus, qui
    -- clique le bouton Heritage du micro-menu, exactement comme le jeu.
    if NS.PoserHeritageSecurise then NS.PoserHeritageSecurise(bouton, moi and (disponibles or 0) > 0) end
    index = index + 1
    y = Poser(contenu, index, y, { texte = releve and releve.quand and string.format(L.READ_ON, releve.quand)
        or ((p.cle == NS.ClePersonnage()) and L.NO_DATA_HERE or L.NO_DATA_OTHER), couleur = SECONDAIRE, apres = 4 })
    if #arbres == 0 then return index, y end
    -- Les arbres, comme dans le jeu : chaque talent a sa place (colonne et
    -- rangee), les trois cote a cote.
    index = index + 1
    y = Titre(contenu, index, y, L.TREES_TITLE, true)
    y = DessinerArbres(contenu, releve.arbres, y + 4, disponibles)
    return index, y
end

-- Un palier : la coche du jeu quand il est atteint, le sablier sinon.
local function CouleurDeClasse(classe)
    local c = _G.RAID_CLASS_COLORS and classe and _G.RAID_CLASS_COLORS[classe]
    if c then return { c.r, c.g, c.b, classe = true } end
    return BLANC
end

-- Un palier : la coche du jeu quand il est atteint ; sinon ou en est le
-- plus avance, sur le palier (70/150).
local function Palier(fait, valeur, actuel)
    if fait then return "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t |cff4fd168" .. valeur .. "|r" end
    return "|cffffffff" .. (actuel or 0) .. "|r|cffb3b3b3/" .. valeur .. "|r"
end

local function Hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

-- Tous ceux qui avancent : le nom a la couleur de sa classe, la valeur en
-- clair. "Paltank 70   Elo 50"
local function Avancees(tous, gabarit)
    local morceaux = {}
    for k, t in ipairs(tous or {}) do
        if k > 6 then table.insert(morceaux, "...") break end
        table.insert(morceaux, string.format(gabarit, Hex(CouleurDeClasse(t.classe)) .. NS.NomCourt(t.cle) .. "|r",
            "|cffffd100" .. t.valeur .. "|r"))
    end
    return table.concat(morceaux, "     ")
end

local ICONES_METIERS = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving",
}

local function RendreDefis(contenu, index, y)
    local d = NS.base.Defis()
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_CHALLENGES)
    index = index + 1
    y = Poser(contenu, index, y, { texte = L.CHALLENGES_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    index = index + 1
    y = Titre(contenu, index, y, L.CHALLENGES_CLASSES, true)
    for _, c in ipairs(d.classes) do
        local morceaux = {}
        for _, pal in ipairs(c.paliers) do table.insert(morceaux, Palier(pal.fait, pal.palier, c.meilleur and c.meilleur.niveau)) end
        local detail
        if c.meilleur then
            detail = Avancees(c.tous, L.CHAR_LEVEL_OF)
        else
            detail = L.NO_CLASS
        end
        local prochain
        for _, pal in ipairs(c.paliers) do if not pal.fait then prochain = pal.palier break end end
        local estMoi = c.meilleur and c.meilleur.cle == NS.ClePersonnage()
        local api = _G.QuestCoreAPI
        if prochain and c.meilleur then
            if estMoi and api and api.GuiderNiveau then
                detail = detail .. "   |cffffd100" .. string.format(L.CHALLENGE_CLICK_ROUTE, prochain) .. "|r"
            elseif not estMoi then
                detail = detail .. "   " .. string.format(L.CHALLENGE_LOG_ON, NS.NomCourt(c.meilleur.cle))
            end
        end
        index = index + 1
        -- Meme retrait et meme place d'icone que les metiers : tout s'aligne.
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = "Interface\\TargetingFrame\\UI-Classes-Circles",
            desature = not c.meilleur, texte = NomDeClasse(c.classe),
            couleur = c.meilleur and CouleurDeClasse(c.classe) or GRIS, droite = table.concat(morceaux, "     "),
            detail = detail, apres = 4 })
        local l = contenu.lignes[index]
        local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[c.classe]
        if coords then l.icone:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
        if prochain and estMoi and api and api.GuiderNiveau then
            local palier = prochain
            l:EnableMouse(true)
            l:SetScript("OnClick", function()
                -- Le guidage de QuestCore vers ce palier (objectif "niveau").
                local ok, lance = pcall(api.GuiderNiveau, palier)
                if ok and not lance then NS.Dire(L.CHALLENGE_ROUTE_NONE) end
            end)
        end
    end
    index = index + 1
    y = Titre(contenu, index, y + 6, L.CHALLENGES_TRADES, true)
    for _, m in ipairs(d.metiers) do
        local morceaux = {}
        for _, pal in ipairs(m.paliers) do table.insert(morceaux, Palier(pal.fait, pal.palier, m.meilleur and m.meilleur.rang)) end
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = ICONES_METIERS[m.ligne], desature = not m.meilleur,
            texte = NomDeMetier(m.ligne, m.nom), couleur = m.meilleur and BLANC or GRIS,
            droite = table.concat(morceaux, "     "),
            detail = m.meilleur and Avancees(m.tous, L.CHAR_SKILL_OF) or L.NO_TRADE,
            apres = 4 })
    end
    return index, y
end

local function RendrePersos(contenu, index, y)
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_CHARACTERS, true)
    local courant = NS.ClePersonnage()
    for _, p in ipairs(PersosVisibles()) do
        local debloque = (p.niveau or 0) >= NS.base.NIVEAU_HERITAGE
        local detail
        if p.releve and p.releve.arbres and #p.releve.arbres > 0 then
            local morceaux = {}
            local ORDRE = { aventure = 1, ressources = 2, metiers = 3 }
            local tries = {}
            for _, a in ipairs(p.releve.arbres) do if #(a.noeuds or {}) > 0 then table.insert(tries, a) end end
            table.sort(tries, function(u, v) return (ORDRE[u.genre] or 9) < (ORDRE[v.genre] or 9) end)
            for _, a in ipairs(tries) do
                table.insert(morceaux, (L[NOMS_ARBRES[a.genre] or ""] or "?") .. " |cffffffff" .. NS.base.Depenses(a) .. "|r")
            end
            detail = table.concat(morceaux, "     ")
        elseif debloque then
            detail = L.NO_DATA_OTHER
        else
            detail = string.format(L.LOCKED_LEVEL, NS.base.NIVEAU_HERITAGE, p.niveau or 0)
        end
        local temps = NS.base.TempsParNiveau(p.cle)
        if temps.total then detail = detail .. "     " .. string.format(L.PLAYED_TOTAL, NS.Duree(temps.total)) end
        index = index + 1
        local cle, perso = p.cle, p
        y = Poser(contenu, index, y + 2, { retrait = 4,
            visage = function(tex)
                PoserVisage(tex, perso, perso.cle == courant)
                tex:SetDesaturated(not debloque)
            end,
            -- La couleur dit deja la classe : le nom seul.
            texte = NS.NomCourt(p.cle),
            police = "GameFontNormal", couleur = CouleurDeClasse(p.classe),
            droite = p.niveau and string.format(L.LEVEL, p.niveau) or "", couleurDroite = BLANC,
            bandeau = p.cle == etat.cle,
            detail = detail, apres = 6 })
        local l = contenu.lignes[index]
        l:EnableMouse(true)
        l:SetScript("OnClick", function()
            ChoisirPerso(cle)
            etat.page = "arbres"
            fen.Rendre()
        end)
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Chronologie : le temps passe sur chaque niveau, et le journal du compte
-- ---------------------------------------------------------------------------

local NIVEAU_MAX = 60
-- Teintes des colonnes : { bas, haut } du degrade.
local COULEURS_HISTO = {
    fini    = { { 0.16, 0.42, 0.16 }, { 0.30, 0.66, 0.28 } },
    enCours = { { 0.12, 0.30, 0.62 }, { 0.26, 0.52, 0.90 } },
    inconnu = { { 0.45, 0.45, 0.45 }, { 0.60, 0.60, 0.60 } },
}
local HAUTEUR_HISTO = 96

local function Histogramme(contenu)
    if contenu.histo then return contenu.histo end
    local h = CreateFrame("Frame", nil, contenu)
    h.barres, h.reperes = {}, {}
    for n = 1, NIVEAU_MAX do
        local b = CreateFrame("Frame", nil, h)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetAllPoints()
        b.fond:SetColorTexture(1, 1, 1, 0)
        -- Une colonne fine et nette : un degrade vertical (plus clair en
        -- haut), un liseré plus sombre sur les cotes, un trait clair au
        -- sommet. Centree dans sa case, avec de l'air entre deux niveaux.
        b.plein = b:CreateTexture(nil, "ARTWORK")
        b.plein:SetPoint("BOTTOM")
        b.plein:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.bord = b:CreateTexture(nil, "BORDER")
        b.bord:SetPoint("TOPLEFT", b.plein, "TOPLEFT", -1, 1)
        b.bord:SetPoint("BOTTOMRIGHT", b.plein, "BOTTOMRIGHT", 1, 0)
        b.sommet = b:CreateTexture(nil, "OVERLAY")
        b.sommet:SetPoint("TOPLEFT", b.plein, "TOPLEFT", 0, 0)
        b.sommet:SetPoint("TOPRIGHT", b.plein, "TOPRIGHT", 0, 0)
        b.sommet:SetHeight(1)
        b:EnableMouse(true)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        h.barres[n] = b
    end
    -- Une ligne de base sous les colonnes, plutot que des fonds pleins.
    h.base = h:CreateTexture(nil, "ARTWORK")
    h.base:SetColorTexture(0.8, 0.65, 0.35, 0.5)
    h.base:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 15)
    h.base:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 15)
    h.base:SetHeight(1)
    for _, n in ipairs({ 1, 10, 20, 30, 40, 50, 60 }) do
        local t = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetText(tostring(n))
        h.reperes[n] = t
    end
    contenu.histo = h
    return h
end

local function DessinerHistogramme(contenu, p, y)
    local h = Histogramme(contenu)
    local largeur = contenu:GetWidth() or 760
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    h:SetSize(largeur, HAUTEUR_HISTO + 16)
    local t = NS.base.TempsParNiveau(p.cle)
    local plusLong = 1
    for _, s in pairs(t.durees) do plusLong = math.max(plusLong, s) end
    if t.enCours then plusLong = math.max(plusLong, t.enCours) end
    local pas = largeur / NIVEAU_MAX
    local niveauPerso = p.niveau or t.niveau or 1
    for n = 1, NIVEAU_MAX do
        local b = h.barres[n]
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", (n - 1) * pas + 1, 16)
        b:SetSize(math.max(2, pas - 2), HAUTEUR_HISTO)
        b.plein:SetWidth(math.max(2, math.floor(pas * 0.55)))
        local duree = t.durees[n]
        local enCours = (n == niveauPerso) and t.enCours or nil
        local valeur = duree or enCours
        -- Vert : niveau termine. Bleu : niveau en cours. Gris : atteint
        -- avant l'installation (temps inconnu).
        local teinte
        if valeur then
            b.plein:SetHeight(math.max(3, HAUTEUR_HISTO * valeur / plusLong))
            teinte = (enCours and not duree) and COULEURS_HISTO.enCours or COULEURS_HISTO.fini
        elseif n < niveauPerso then
            b.plein:SetHeight(3)
            teinte = COULEURS_HISTO.inconnu
        end
        if teinte then
            local bas, haut = teinte[1], teinte[2]
            b.plein:SetVertexColor(1, 1, 1, 1)
            local ok = b.plein.SetGradient and _G.CreateColor and pcall(b.plein.SetGradient, b.plein, "VERTICAL",
                _G.CreateColor(bas[1], bas[2], bas[3], 1), _G.CreateColor(haut[1], haut[2], haut[3], 1))
            if not ok then b.plein:SetVertexColor(haut[1], haut[2], haut[3], 1) end
            b.bord:SetColorTexture(bas[1] * 0.55, bas[2] * 0.55, bas[3] * 0.55, 0.9)
            b.sommet:SetColorTexture(math.min(1, haut[1] + 0.25), math.min(1, haut[2] + 0.25), math.min(1, haut[3] + 0.25), 1)
            b.plein:Show() b.bord:Show() b.sommet:Show()
        else
            b.plein:Hide() b.bord:Hide() b.sommet:Hide()
        end
        local niveau = n
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(string.format(L.LEVEL, niveau), 1, 0.82, 0)
            if duree then GameTooltip:AddLine(string.format(L.LEVEL_TIME, NS.Duree(duree)), 1, 1, 1)
            elseif enCours then GameTooltip:AddLine(string.format(L.LEVEL_TIME_NOW, NS.Duree(enCours)), 0.26, 0.52, 0.90)
            elseif niveau < niveauPerso then GameTooltip:AddLine(L.LEVEL_TIME_UNKNOWN, 0.6, 0.6, 0.6)
            else GameTooltip:AddLine(L.LEVEL_TIME_LATER, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:Show()
    end
    for n, rep in pairs(h.reperes) do
        rep:ClearAllPoints()
        rep:SetPoint("TOP", h, "BOTTOMLEFT", (n - 0.5) * pas, 14)
    end
    h:Show()
    return y + HAUTEUR_HISTO + 22, t
end

local COL_HEURE, COL_NOM, COL_NIVEAU, COL_TEMPS = 44, 130, 130, 220

local function RendreChrono(contenu, p, index, y)
    if p then
        index = index + 1
        y = Titre(contenu, index, y, string.format(L.TIMELINE_LEVELS, NS.NomCourt(p.cle)), true)
        local t
        y, t = DessinerHistogramme(contenu, p, y + 4)
        -- En une ligne : le total, le niveau le plus long, la moyenne.
        local n, somme, long, niveauLong = 0, 0, 0, nil
        for niveau, s in pairs(t.durees) do
            n, somme = n + 1, somme + s
            if s > long then long, niveauLong = s, niveau end
        end
        local morceaux = {}
        if t.total then table.insert(morceaux, string.format(L.PLAYED_TOTAL, NS.Duree(t.total))) end
        if niveauLong then table.insert(morceaux, string.format(L.LONGEST_LEVEL, niveauLong, NS.Duree(long))) end
        if n > 0 then table.insert(morceaux, string.format(L.AVERAGE_LEVEL, NS.Duree(somme / n))) end
        index = index + 1
        y = Poser(contenu, index, y, { texte = #morceaux > 0 and table.concat(morceaux, "     ") or L.TIMELINE_NO_TIME,
            couleur = #morceaux > 0 and BLANC or SECONDAIRE, multi = true, apres = 2 })
        index = index + 1
        y = Poser(contenu, index, y, { texte = L.TIMELINE_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    end
    -- Plus de journal du compte : une liste de toutes les montees de niveau
    -- de tous les personnages devient illisible et n'apprend rien de plus
    -- que les colonnes ci-dessus, personnage par personnage.
    return index, y
end

-- Les choix les plus repandus, d'apres les guides de la communaute.
local function RendreConseils(contenu, index, y)
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_ADVICE)
    index = index + 1
    y = Poser(contenu, index, y, { texte = L.ADVICE_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    for _, bloc in ipairs(L.ADVICE) do
        index = index + 1
        y = Titre(contenu, index, y, bloc[1])
        for i = 2, #bloc do
            index = index + 1
            y = Poser(contenu, index, y, { retrait = RETRAIT, texte = bloc[i][1], couleur = BLANC, detail = bloc[i][2],
                apres = 2 })
        end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Bande des personnages
-- ---------------------------------------------------------------------------

PoserVisage = function(texture, p, estConnecte)
    -- Rond, dans un anneau a la couleur de la classe (comme la recherche de groupe).
    if _G.CoreSuite and _G.CoreSuite.AnneauDeClasse then _G.CoreSuite.AnneauDeClasse(texture, p and p.classe) end

    texture:SetTexCoord(0, 1, 0, 1)
    if estConnecte and SetPortraitTexture and pcall(SetPortraitTexture, texture, "player") then return end
    local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
    if coords then
        texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        return
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function CreerPortrait(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TAILLE_PORTRAIT, TAILLE_PORTRAIT)
    b.cadre = b:CreateTexture(nil, "BACKGROUND")
    b.cadre:SetAllPoints()
    b.cadre:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    b.visage = b:CreateTexture(nil, "ARTWORK")
    b.visage:SetPoint("TOPLEFT", 4, -4)
    b.visage:SetPoint("BOTTOMRIGHT", -4, 4)
    b.halo = b:CreateTexture(nil, "OVERLAY")
    b.halo:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.halo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.halo:SetBlendMode("ADD")
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- La barre des personnages : celle de la suite, la meme partout.
local function RendreBande(persos)
    local S = NS.suite or _G.CoreSuite
    local cles = S.BandePersos(cadre.bande, { choisi = etat.cle, auClic = function(cle)
        ChoisirPerso(cle)
        fen.Rendre()
    end })
    cadre.bande.ordre = cles
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- Une ligne de menu : le modele commun de la suite (meme aspect, meme
-- survol, meme selection partout).
local function CreerLigneDeMenu(parent, icone)
    return (NS.suite or _G.CoreSuite).LigneDeMenu(parent, icone)
end

local function MarquerMenu()
    for cle, b in pairs(cadre.boutonsMenu) do
        local choisi = cle == etat.page
        local SuiteM = NS.suite or _G.CoreSuite SuiteM.MarquerLigneDeMenu(b, choisi)
    end
end

local function Construire()
    cadre = NS.charte.Fenetre("LegacyCoreFenetre", LARGEUR, HAUTEUR, {})
    cadre:SetPoint("CENTER")
    cadre:Hide()
    table.insert(UISpecialFrames, "LegacyCoreFenetre")
    local portrait = cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait)
    if portrait then portrait:SetTexture("Interface\\Icons\\Spell_Holy_SealOfWisdom") end
    if cadre.titre then cadre.titre:SetText(L.TITLE) end

    local bande = CreateFrame("Frame", nil, cadre)
    bande:SetPoint("LEFT", cadre.entete, "LEFT", 0, 0)
    bande:SetPoint("RIGHT", cadre.entete, "RIGHT", 0, 0)
    bande:SetHeight(TAILLE_PORTRAIT + 4)
    cadre.bande = bande

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

    cadre.boutonsMenu = {}
    local yMenu = 0
    for rang, page in ipairs(PAGES) do
        -- Un titre par categorie, comme dans toute la suite.
        if page.section then
            if rang > 1 then yMenu = yMenu + 8 end
            local t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local S = _G.CoreSuite
            if S and S.TitreDeMenu then S.TitreDeMenu(t) end
            t:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(yMenu + 2))
            t:SetText(L[page.section])
            yMenu = yMenu + 24
        end
        local b = CreerLigneDeMenu(menu, page.icone)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -yMenu)
        yMenu = yMenu + 26
        b:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
        if texte then texte:SetText(L[page.libelle]) end
        local cle = page.cle
        b:SetScript("OnClick", function()
            etat.page = cle
            fen.Rendre()
        end)
        cadre.boutonsMenu[cle] = b
    end

    local okD, defilement = pcall(CreateFrame, "ScrollFrame", nil, cadre, "ScrollFrameTemplate")
    if not okD or not defilement then
        defilement = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
    end
    defilement:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_MENU, 0)
    defilement:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", -18, 0)
    local contenu = CreateFrame("Frame", nil, defilement)
    contenu:SetSize(LARGEUR - LARGEUR_MENU - 2 * NS.charte.MARGE - 60, 1)
    defilement:SetScrollChild(contenu)
    cadre.contenu = contenu
    cadre.defilement = defilement

    NS.charte.Parchemin(cadre, { "TOPLEFT", trait, "TOPRIGHT", 2, NS.charte.MARGE - 4 },
        { "BOTTOMRIGHT", cadre.fond, "BOTTOMRIGHT", -4, 4 }, cadre.fond)

    local fermer = NS.charte.BoutonDePied(cadre, L.CLOSE, 110)
    fermer:SetScript("OnClick", function() cadre:Hide() end)

    if NS.suite then pcall(NS.suite.Entete, cadre, "LegacyCore", cadre.entete) end
    pcall(BrancherManette)
    cadre:SetScript("OnShow", function() fen.Rendre() end)
end

-- Memoire : on rouvre la page ou on s'etait arrete, meme apres /reload.
local pageRestauree = false
local function Memoire()
    if type(LegacyCoreDB) ~= "table" then return nil end
    LegacyCoreDB.memoire = type(LegacyCoreDB.memoire) == "table" and LegacyCoreDB.memoire or {}
    return LegacyCoreDB.memoire
end

function fen.Rendre()
    if not cadre or not cadre:IsShown() then return end
    local m = Memoire()
    if m and not pageRestauree then
        pageRestauree = true
        if m.page then etat.page = m.page end
    end
    local ok, souci = pcall(function()
        local persos = PersosVisibles()
        SuivreLaSuite()
        local trouve = false
        for _, p in ipairs(persos) do if p.cle == etat.cle then trouve = true end end
        if not trouve then etat.cle = persos[1] and persos[1].cle end
        RendreBande(persos)
        MarquerMenu()
        if not cadre.fondMenu:IsShown() then pcall(NS.charte.FondDuJournal, cadre.fondMenu) end
        local parchemin = NS.charte.Fond() == "parchemin"
        if cadre.parchemin then cadre.parchemin.Montrer(parchemin) end

        local contenu = cadre.contenu
        for _, l in ipairs(contenu.lignes or {}) do
            l:Hide()
            l:SetScript("OnClick", nil)
            if l.icone then l.icone:SetTexCoord(0, 1, 0, 1) end
        end
        for _, c in ipairs(contenu.cases or {}) do c:Hide() end
        for _, l in ipairs(contenu.liens or {}) do CacherLien(l) end
        for _, t in ipairs(contenu.titresArbres or {}) do t:Hide() if t.bandeau then t.bandeau:Hide() end end
        if contenu.grilleTalents then
            local g = contenu.grilleTalents
            g:Hide()
            for _, t in ipairs(g.titres) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
        end
        if contenu.histo then contenu.histo:Hide() end
        if contenu.boutonHeritage then contenu.boutonHeritage:Hide() end
        local p = etat.cle and NS.base.Personnage(etat.cle)
        local index, y = 0, 0
        if cadre.titre then
            cadre.titre:SetText(L.TITLE .. (p and (" : " .. NS.NomCourt(p.cle)) or ""))
        end
        if etat.page == "defis" then
            index, y = RendreDefis(contenu, index, y)
        elseif etat.page == "persos" then
            index, y = RendrePersos(contenu, index, y)
        elseif etat.page == "conseils" then
            index, y = RendreConseils(contenu, index, y)
        elseif etat.page == "chrono" then
            index, y = RendreChrono(contenu, p, index, y)
        elseif p then
            index, y = RendreArbres(contenu, p, index, y)
        end
        contenu:SetHeight(math.max(y + 8, 1))
        NS.charte.Encrer(contenu, parchemin)
        if fen.ApresRendu then fen.ApresRendu() end
    end)
    if m and etat.page then m.page = etat.page end
    if not ok then NS.base.NoterIncident("fenetre", souci) end
end

function fen.Ouvrir()
    if not cadre then Construire() end
    if not cadre:IsShown() then cadre:Show() end
end

function fen.Basculer()
    if not cadre then Construire() end
    if cadre:IsShown() then cadre:Hide() else cadre:Show() end
end

function fen.Cadre() return cadre end
function fen.Visible() return cadre and cadre:IsShown() end

-- ---------------------------------------------------------------------------
-- Manette, comme les autres add-ons de la suite
-- ---------------------------------------------------------------------------
--
--   LB / RB            page precedente / suivante
--   croix gauche/droite  personnage precedent / suivant
--   LT / RT            add-on voisin de la suite (onglets lateraux)
--   croix haut / bas   fait defiler la page
--   B                  fermer

local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

local GLYPHES = { PAD1 = { "A", "Cross" }, PAD2 = { "B", "Circle" }, PADLSHOULDER = { "LShoulder", "LShoulder", "LB" },
    PADRSHOULDER = { "RShoulder", "RShoulder", "RB" }, PADDUP = { "Up", "Up", "^" }, PADDDOWN = { "Down", "Down", "v" },
    PADDLEFT = { "Left", "Left", "<" }, PADDRIGHT = { "Right", "Right", ">" },
    PADLTRIGGER = { "LTrigger", "LTrigger", "LT" }, PADRTRIGGER = { "RTrigger", "RTrigger", "RT" },
    PADBACK = { "View", "Share", "Vue" },
    PADLSTICK = { "LStickIn", "LStickIn", "L3" }, PADRSTICK = { "RStickIn", "RStickIn", "R3" } }
local function Glyphe(touche, taille)
    local g = GLYPHES[touche] or { touche }
    local info = NS.Lecture("C_Texture.GetAtlasInfo")
    if info then
        for _, nom in ipairs({ "Gamepad_Ltr_" .. g[1] .. "_64", "Gamepad_Shp_" .. (g[2] or g[1]) .. "_64",
            "Gamepad_Gen_" .. g[1] .. "_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":" .. (taille or 22) .. ":" .. (taille or 22) .. "|a" end
        end
    end
    return "|cffffd100" .. (g[3] or g[1]) .. "|r"
end

function fen.ApresRendu()
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
    if not ManetteActive() then barre:Hide() return end
    local bh = cadre.contenu and cadre.contenu.boutonHeritage
    if bh then
        bh:SetText((bh:IsShown() and bh:IsEnabled() and (Glyphe("PAD1", 14) .. " ") or "") .. L.OPEN_LEGACY)
        bh:SetWidth((bh:GetTextWidth() or 120) + 30)
    end
    barre.texte:SetText(Glyphe("PADLSHOULDER") .. " " .. Glyphe("PADRSHOULDER") .. "  " .. L.PAD_PAGES .. "      "
        .. Glyphe("PADDLEFT") .. " " .. Glyphe("PADDRIGHT") .. "  " .. L.PAD_CHARS .. "      "
        .. Glyphe("PADDUP") .. " " .. Glyphe("PADDDOWN") .. "  " .. L.PAD_SCROLL .. "      "
        .. Glyphe("PADLSTICK") .. " " .. Glyphe("PADRSTICK") .. "  " .. L.PAD_SUITE .. "      "
        .. Glyphe("PAD2") .. "  " .. L.CLOSE)
    barre:SetWidth((barre.texte:GetStringWidth() or 400) + 24)
    barre:Show()
end

local function PageVoisine(pas)
    local index = 1
    for rang, page in ipairs(PAGES) do if page.cle == etat.page then index = rang end end
    local suivant = math.max(1, math.min(#PAGES, index + pas))
    if suivant == index then return end
    etat.page = PAGES[suivant].cle
    fen.Rendre()
end

local function PersoVoisin(pas)
    local persos = cadre and cadre.bande and cadre.bande.ordre or {}
    if #persos == 0 then return end
    local index = 1
    for rang, cle in ipairs(persos) do if cle == etat.cle then index = rang end end
    ChoisirPerso(persos[((index - 1 + pas) % #persos) + 1])
    fen.Rendre()
end

local function Defiler(sens)
    local d = cadre.defilement
    local maxi = math.max(0, (cadre.contenu:GetHeight() or 0) - (d:GetHeight() or 0))
    d:SetVerticalScroll(math.max(0, math.min(maxi, (d:GetVerticalScroll() or 0) + sens * 60)))
end

local function Traiter(bouton)
    local S = NS.suite
    if S and S.CurseurActif and S.CurseurActif(cadre) then
        if bouton == "PADDLEFT" then S.CurseurDeplacer(cadre, -1) return false end
        if bouton == "PADDRIGHT" then S.CurseurDeplacer(cadre, 1) return false end
        if bouton == "PAD1" then S.CurseurValider(cadre) return false end
        if bouton == "PAD2" then S.CurseurQuitter(cadre) return false end
        S.CurseurQuitter(cadre)
    end
    if bouton == "PADDRIGHT" then PersoVoisin(1) return false end
    if bouton == "PADDLEFT" then PersoVoisin(-1) return false end
    if bouton == "PADLSHOULDER" then PageVoisine(-1) return false end
    if bouton == "PADRSHOULDER" then PageVoisine(1) return false end
    -- A : le bouton de la page (ouvrir l'heritage), quand il est la.
    if bouton == "PAD1" then
        local b = cadre.contenu and cadre.contenu.boutonHeritage
        if b and b:IsShown() and b:IsEnabled() then b:Click() end
        return false
    end
    if bouton == "PADDUP" then Defiler(-1) return false end
    if bouton == "PADDDOWN" then Defiler(1) return false end
    if bouton == "PAD2" then cadre:Hide() return false end
    return true
end

BrancherManette = function()
    if not cadre.EnableGamePadButton then return end
    if not pcall(cadre.EnableGamePadButton, cadre, true) then return end
    cadre:SetScript("OnGamePadButtonDown", function(_, bouton)
        -- Vue tenue + LB / RB : add-on voisin (la suite s'en charge).
        local S = NS.suite
        if S and S.ManetteBas then
            local okS, pris = pcall(S.ManetteBas, "LegacyCore", bouton)
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
end
