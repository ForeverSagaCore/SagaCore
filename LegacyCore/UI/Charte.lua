local _, NS = ...

-- Charte commune a toutes les fenetres de CraftCore.
--
-- Une seule facon de construire une fenetre, pour qu'elles se ressemblent
-- toutes : le modele du jeu a bord dore (celui des fenetres a portrait), une
-- zone de contenu a l'interieur du fond, avec la meme marge sur les quatre
-- cotes, et une bande de pied hors du fond, ou se posent les boutons, comme
-- dans les fenetres du jeu.
--
--   +--------------------------------------------+
--   | (portrait)        Titre                  X |
--   |            [ en-tete : sous le titre ]     |
--   |  +--------------------------------------+  |
--   |  |  MARGE                               |  |
--   |  |      zone de contenu                 |  |
--   |  |                               MARGE  |  |
--   |  +--------------------------------------+  |
--   |  pied : boutons                            |
--   +--------------------------------------------+

NS.charte = {}
local charte = NS.charte

charte.MARGE = 12              -- entre le bord du fond et le contenu, partout
charte.ECART = 8               -- entre deux elements voisins
charte.ESPACE_SECTION = 14     -- avant un titre de section
charte.HAUTEUR_BOUTON = 22
charte.RETRAIT = 16            -- un niveau de hierarchie
charte.ICONE_PORTRAIT = "Interface\\Icons\\INV_Misc_Gear_01"

local MODELES = { "ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset" }

-- Cree une fenetre a la charte.
--   options.portrait  (defaut vrai) : portrait a l'engrenage, comme la principale.
--   options.deplacable (defaut vrai)
--   options.strate    (defaut FULLSCREEN_DIALOG)
-- Rend le cadre, avec :
--   cadre.fond    le fond interieur du modele (ou le cadre lui-meme) ;
--   cadre.zone    la zone de contenu, marge comprise ;
--   cadre.entete  la bande sous le titre, a droite du portrait ;
--   cadre.pied    la bande des boutons, sous le fond ;
--   cadre.fermer  le bouton de fermeture du titre ;
--   cadre.titre   le texte du titre.
function charte.Fenetre(nom, largeur, hauteur, options)
    options = options or {}
    local avecPortrait = options.portrait ~= false
    local cadre
    for _, modele in ipairs(MODELES) do
        local ok, cree = pcall(CreateFrame, "Frame", nom, options.parent or UIParent, modele)
        if ok and cree then cadre = cree break end
    end
    cadre = cadre or CreateFrame("Frame", nom, options.parent or UIParent)

    cadre:SetSize(largeur, hauteur)
    cadre:SetFrameStrata(options.strate or "FULLSCREEN_DIALOG")
    cadre:EnableMouse(true)
    cadre:SetClampedToScreen(true)
    if options.deplacable ~= false then
        cadre:SetMovable(true)
        cadre:RegisterForDrag("LeftButton")
        cadre:SetScript("OnDragStart", cadre.StartMoving)
        cadre:SetScript("OnDragStop", cadre.StopMovingOrSizing)
    end

    local portrait = cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait)
    local fond = cadre.Inset
    if avecPortrait then
        if portrait then portrait:SetTexture(charte.ICONE_PORTRAIT) end
    else
        if _G.ButtonFrameTemplate_HidePortrait then pcall(_G.ButtonFrameTemplate_HidePortrait, cadre) end
        -- Sans portrait, le fond remonte juste sous la barre de titre.
        if fond and fond.ClearAllPoints then
            fond:ClearAllPoints()
            fond:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, -24)
            fond:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -6, options.sansPied and 4 or 26)
        end
    end
    if not fond then
        -- Modele sans fond interieur : on en pose les limites nous-memes.
        fond = CreateFrame("Frame", nil, cadre)
        fond:SetPoint("TOPLEFT", cadre, "TOPLEFT", 4, avecPortrait and -60 or -24)
        fond:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -6, options.sansPied and 4 or 26)
    end
    cadre.fond = fond


    local zone = CreateFrame("Frame", nil, cadre)
    zone:SetPoint("TOPLEFT", fond, "TOPLEFT", charte.MARGE, -charte.MARGE)
    zone:SetPoint("BOTTOMRIGHT", fond, "BOTTOMRIGHT", -charte.MARGE, charte.MARGE)
    cadre.zone = zone

    local entete = CreateFrame("Frame", nil, cadre)
    entete:SetPoint("TOPLEFT", cadre, "TOPLEFT", avecPortrait and 64 or charte.MARGE, -25)
    entete:SetPoint("BOTTOMRIGHT", fond, "TOPRIGHT", -charte.MARGE, 2)
    cadre.entete = entete

    -- Bande du pied un peu plus haute que les boutons : le fond s'arrete a
    -- 32 pixels du bas (au lieu de 26), les boutons de 22 pixels y tiennent
    -- avec de l'air au-dessus et au-dessous.
    if not options.sansPied and fond and fond.SetPoint then
        fond:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -6, 32)
    end
    local pied = CreateFrame("Frame", nil, cadre)
    pied:SetPoint("BOTTOMLEFT", cadre, "BOTTOMLEFT", charte.MARGE, 7)
    pied:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -charte.MARGE + 4, 7)
    pied:SetHeight(charte.HAUTEUR_BOUTON)
    cadre.pied = pied

    local fermer = cadre.CloseButton or cadre.closeButton
        or (cadre.TitleContainer and cadre.TitleContainer.CloseButton)
        or (cadre.BorderBox and cadre.BorderBox.CloseButton)
    if not fermer then
        fermer = CreateFrame("Button", nil, cadre, "UIPanelCloseButton")
        fermer:SetPoint("TOPRIGHT", cadre, "TOPRIGHT", -3, -3)
    end
    -- Fermeture simple : la fermeture native passe par un chemin bloque en combat.
    fermer:SetScript("OnClick", function() cadre:Hide() end)
    cadre.fermer = fermer

    local titre = cadre.TitleText or (cadre.TitleContainer and cadre.TitleContainer.TitleText)
    if not titre then
        titre = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titre:SetPoint("TOP", cadre, "TOP", 0, -6)
    end
    cadre.titre = titre
    return cadre
end

-- Bouton du jeu pose dans le pied, de droite a gauche.
function charte.BoutonDePied(cadre, libelle, largeur, voisin)
    local b = CreateFrame("Button", nil, cadre.pied, "UIPanelButtonTemplate")
    b:SetSize(largeur or 110, charte.HAUTEUR_BOUTON)
    if voisin then
        b:SetPoint("RIGHT", voisin, "LEFT", -charte.ECART, 0)
    else
        b:SetPoint("RIGHT", cadre.pied, "RIGHT", 0, 0)
    end
    b:SetText(libelle)
    return b
end

-- ---------------------------------------------------------------------------
-- Fond de la zone de contenu : noir (le fond du jeu, par defaut) ou parchemin
-- (comme le grimoire et le journal de quetes). Au choix dans Parametres.
--
-- Sur le parchemin, le texte passe a l'encre : chaque couleur claire du code
-- a sa teinte sombre lisible sur le papier, sans ombre portee, comme les
-- textes du jeu sur parchemin. Les infobulles, les boutons et les zones de
-- saisie ne changent pas.
-- ---------------------------------------------------------------------------

-- Le fond est commun a toute la suite (CraftCore, QuestCore, MapCore) : choisi
-- dans l'un, il vaut pour les autres. Sans choix commun, celui de l'add-on.
function charte.Fond()
    local g = NS.base and NS.base.ReglagesGeneraux and NS.base.ReglagesGeneraux() or {}
    local suite = _G.CoreSuiteDB
    if type(suite) == "table" then
        if suite.fond ~= "noir" and suite.fond ~= "parchemin" and g.fond then
            suite.fond = (g.fond == "parchemin") and "parchemin" or "noir"
        end
        if suite.fond == "noir" or suite.fond == "parchemin" then return suite.fond end
    end
    return g.fond == "parchemin" and "parchemin" or "noir"
end

function charte.PoserFond(valeur)
    local g = NS.base.ReglagesGeneraux()
    g.fond = (valeur == "parchemin") and "parchemin" or "noir"
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.fond = g.fond
end

-- Teintes claires du code, et leur encre sur parchemin.
local ENCRES = {
    { { 1, 1, 1 },          { 0.20, 0.12, 0.05 } }, -- blanc : encre
    { { 0.8, 0.8, 0.8 },    { 0.25, 0.17, 0.08 } },
    { { 1, 0.82, 0 },       { 0.42, 0.18, 0.02 } }, -- or du jeu : brun rouge
    { { 0.31, 0.82, 0.41 }, { 0.07, 0.36, 0.06 } }, -- vert : dans les sacs
    { { 0.1, 1, 0.1 },      { 0.07, 0.36, 0.06 } },
    { { 0.12, 1, 0 },       { 0.05, 0.38, 0.0 } },  -- qualite inhabituelle
    { { 0, 0.44, 0.87 },    { 0.0, 0.24, 0.58 } },  -- rare
    { { 0.64, 0.21, 0.93 }, { 0.40, 0.08, 0.60 } }, -- epique
    { { 1, 0.5, 0 },        { 0.60, 0.27, 0.0 } },  -- legendaire, orange
    { { 0.9, 0.3, 0.3 },    { 0.60, 0.07, 0.04 } }, -- rouge : manque
    { { 1, 0.1, 0.1 },      { 0.60, 0.07, 0.04 } },
    { { 0.55, 0.55, 0.55 }, { 0.40, 0.30, 0.20 } }, -- gris
    { { 0.62, 0.62, 0.62 }, { 0.40, 0.30, 0.20 } },
    { { 0.7, 0.7, 0.7 },    { 0.36, 0.27, 0.17 } },
    { { 0.5, 0.5, 0.5 },    { 0.42, 0.32, 0.22 } },
}

local function Clarte(r, g, b) return 0.299 * r + 0.587 * g + 0.114 * b end

-- L'encre d'une couleur : la plus proche du tableau, sinon la couleur
-- assombrie. Une couleur deja sombre reste telle quelle.
function charte.Encre(r, g, b)
    if Clarte(r, g, b) < 0.32 then return r, g, b end
    local meilleure, distance
    for _, paire in ipairs(ENCRES) do
        local c = paire[1]
        local d = (c[1] - r) ^ 2 + (c[2] - g) ^ 2 + (c[3] - b) ^ 2
        if not distance or d < distance then meilleure, distance = paire[2], d end
    end
    if distance and distance < 0.06 then return meilleure[1], meilleure[2], meilleure[3] end
    return r * 0.42, g * 0.42, b * 0.42
end

local function EncreHexa(rr, gg, bb)
    local r, g, b = tonumber(rr, 16) / 255, tonumber(gg, 16) / 255, tonumber(bb, 16) / 255
    r, g, b = charte.Encre(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function Proche(a, b, c, x, y, z)
    return math.abs(a - x) < 0.01 and math.abs(b - y) < 0.01 and math.abs(c - z) < 0.01
end

-- Une ligne de texte : a l'encre sur parchemin, rendue a sa couleur sur noir.
local function EncrerTexte(fs, parchemin)
    local r, g, b, a = fs:GetTextColor()
    if not r then return end
    local texte = fs:GetText()
    if parchemin then
        if not (fs.encre and Proche(r, g, b, fs.encre[1], fs.encre[2], fs.encre[3])) then
            fs.couleurOrigine = { r, g, b, a }
            local er, eg, eb = charte.Encre(r, g, b)
            fs:SetTextColor(er, eg, eb, a)
            fs.encre = { er, eg, eb }
        end
        if type(texte) == "string" and texte ~= fs.texteEncre and string.find(texte, "|c%x%x") then
            local encre = string.gsub(texte, "|c(%x%x)(%x%x)(%x%x)(%x%x)", function(aa, rr, gg, bb)
                return "|c" .. aa .. EncreHexa(rr, gg, bb)
            end)
            fs.texteOrigine = texte
            fs:SetText(encre)
            fs.texteEncre = encre
        end
        -- Une ombre portee legere sur tous les textes : lisibles sur le
        -- papier, et tous du meme relief.
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.4) end
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        -- Le nom d'une ligne gagne un point : plus lisible sur le papier.
        if fs.agrandir and fs.GetFont then
            local fichier, taille, options = fs:GetFont()
            if fichier and taille and taille < 12 then fs:SetFont(fichier, 12, options) end
        end
    else
        if fs.encre and Proche(r, g, b, fs.encre[1], fs.encre[2], fs.encre[3]) and fs.couleurOrigine then
            local o = fs.couleurOrigine
            fs:SetTextColor(o[1], o[2], o[3], o[4])
        end
        fs.encre = nil
        if fs.texteEncre and texte == fs.texteEncre and fs.texteOrigine then fs:SetText(fs.texteOrigine) end
        fs.texteEncre = nil
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    end
end

-- Passe sur tous les textes d'un cadre et de ses enfants.
function charte.Encrer(racine, parchemin)
    if not racine or not racine.GetRegions then return end
    if parchemin == nil then parchemin = charte.Fond() == "parchemin" end
    local texteDuBouton
    if racine.IsObjectType and racine:IsObjectType("Button") and not racine:IsObjectType("CheckButton")
        and racine.GetFontString then
        texteDuBouton = racine:GetFontString()
    end
    for _, region in ipairs({ racine:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region ~= texteDuBouton then
            EncrerTexte(region, parchemin)
        end
    end
    if racine.GetChildren then
        for _, enfant in ipairs({ racine:GetChildren() }) do
            local saisie = enfant.IsObjectType and enfant:IsObjectType("EditBox")
            if not saisie and not enfant.sansEncre then charte.Encrer(enfant, parchemin) end
        end
    end
end

-- Une liste de textes, a l'encre ou non (pour les suivis).
function charte.EncrerTextes(liste, parchemin)
    for _, fs in pairs(liste) do
        if fs and fs.GetTextColor then EncrerTexte(fs, parchemin) end
    end
end

-- ---------------------------------------------------------------------------
-- Fond des petites fenetres de suivi (quetes, recolte) : le meme pour toute
-- la suite. "gris" (le fond du jeu), "parchemin" (textes a l'encre) ou
-- "illustre" (le fond illustre du journal de quetes du jeu).
-- ---------------------------------------------------------------------------

function charte.FondDesSuivis()
    local d = _G.CoreSuiteDB
    local v = type(d) == "table" and d.fondSuivis
    if v == "parchemin" or v == "illustre" then return v end
    return "gris"
end

-- Chaque add-on y inscrit le rendu de son suivi.
function charte.SurFondDesSuivis(fonction)
    local suite = _G.CoreSuite
    if type(suite) ~= "table" then return end
    suite.rappelsFondSuivis = suite.rappelsFondSuivis or {}
    table.insert(suite.rappelsFondSuivis, fonction)
end

function charte.PoserFondDesSuivis(valeur)
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.fondSuivis = (valeur == "parchemin" or valeur == "illustre") and valeur or nil
    local suite = _G.CoreSuite
    for _, f in ipairs(type(suite) == "table" and suite.rappelsFondSuivis or {}) do pcall(f) end
end

-- Pose le fond choisi sur une fenetre de suivi. Rend vrai si parchemin (les
-- textes passent alors a l'encre).
function charte.HabillerSuivi(cadre)
    local fond = cadre and cadre.fond
    if not fond then return false end
    local choix = charte.FondDesSuivis()
    if choix == "parchemin" and not cadre.parchemin then
        charte.Parchemin(cadre, { "TOPLEFT", fond, "TOPLEFT", 3, -3 }, { "BOTTOMRIGHT", fond, "BOTTOMRIGHT", -3, 3 }, fond)
    end
    if cadre.parchemin then cadre.parchemin.Montrer(choix == "parchemin") end
    if choix == "illustre" and not cadre.illustration then
        local t = fond:CreateTexture(nil, "BACKGROUND", nil, 5)
        t:SetPoint("TOPLEFT", fond, "TOPLEFT", 3, -3)
        t:SetPoint("BOTTOMRIGHT", fond, "BOTTOMRIGHT", -3, 3)
        cadre.illustration = t
    end
    if cadre.illustration then
        if choix == "illustre" then charte.FondDuJournal(cadre.illustration) else cadre.illustration:Hide() end
    end
    return choix == "parchemin"
end

-- Le parchemin derriere une zone (entre deux ancres). Un aplat couleur
-- papier dessous : lisible meme si la texture manque au client.
local PAPIER = { 0.87, 0.79, 0.62 }
local FICHIERS_PARCHEMIN = {
    "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
    "Interface\\QuestFrame\\QuestBG",
}

-- `porteur` : le cadre qui porte les textures, celui du fond interieur, pour
-- que le parchemin se dessine par dessus son fond sombre et sous le contenu.
function charte.Parchemin(cadre, haut, bas, porteur)
    if cadre.parchemin then return cadre.parchemin end
    porteur = porteur or cadre
    local p = {}
    p.aplat = porteur:CreateTexture(nil, "BACKGROUND", nil, 6)
    p.aplat:SetColorTexture(PAPIER[1], PAPIER[2], PAPIER[3], 1)
    p.grain = porteur:CreateTexture(nil, "BACKGROUND", nil, 7)
    local atlas = "QuestBG-Parchment"
    local ok = false
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        ok = pcall(p.grain.SetAtlas, p.grain, atlas)
    end
    if not ok then
        for _, fichier in ipairs(FICHIERS_PARCHEMIN) do
            if pcall(p.grain.SetTexture, p.grain, fichier) and type(p.grain:GetTexture()) == "number" then
                ok = true
                break
            end
        end
    end
    if not ok then p.grain:SetTexture(nil) end
    for _, t in ipairs({ p.aplat, p.grain }) do
        t:SetPoint(haut[1], haut[2], haut[3], haut[4], haut[5])
        t:SetPoint(bas[1], bas[2], bas[3], bas[4], bas[5])
    end
    -- Un liseré brun autour, comme le bord d'une page.
    p.bords = {}
    for _, cote in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local b = porteur:CreateTexture(nil, "BORDER")
        b:SetColorTexture(0.36, 0.24, 0.10, 0.9)
        if cote == "TOP" or cote == "BOTTOM" then
            b:SetHeight(1)
            b:SetPoint(cote .. "LEFT", p.aplat, cote .. "LEFT", 0, 0)
            b:SetPoint(cote .. "RIGHT", p.aplat, cote .. "RIGHT", 0, 0)
        else
            b:SetWidth(1)
            b:SetPoint("TOP" .. cote, p.aplat, "TOP" .. cote, 0, 0)
            b:SetPoint("BOTTOM" .. cote, p.aplat, "BOTTOM" .. cote, 0, 0)
        end
        table.insert(p.bords, b)
    end
    function p.Montrer(visible)
        for _, t in ipairs({ p.aplat, p.grain }) do t:SetShown(visible) end
        for _, b in ipairs(p.bords) do b:SetShown(visible) end
    end
    cadre.parchemin = p
    return p
end

-- ---------------------------------------------------------------------------
-- Fond du journal de quetes de la carte du monde (gris sombre en relief),
-- pose sur une texture. Lu sur la carte du jeu elle-meme si elle est chargee
-- (son atlas ou son fichier), sinon par les noms d'atlas connus. Rend vrai
-- si un fond a ete trouve ; sinon la texture reste cachee.
-- ---------------------------------------------------------------------------
local ATLAS_JOURNAL = { "QuestLog-main-background", "questlog-main-background", "QuestLogBackground" }

local function AtlasExiste(nom)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(nom) ~= nil
end

function charte.FondDuJournal(texture)
    -- 1. Le fond tel que la carte l'affiche.
    local sources = {}
    local qs = _G.QuestScrollFrame
    if qs then table.insert(sources, qs.Background) end
    local qm = _G.QuestMapFrame
    if qm then
        table.insert(sources, qm.Background)
        if qm.QuestsFrame then table.insert(sources, qm.QuestsFrame.Background) end
    end
    for _, source in pairs(sources) do
        if source and source.GetAtlas then
            local atlas = source:GetAtlas()
            if atlas and atlas ~= "" and AtlasExiste(atlas) then
                texture:SetAtlas(atlas)
                texture:Show()
                return true
            end
        end
        if source and source.GetTexture then
            local fichier = source:GetTexture()
            if fichier then
                texture:SetTexture(fichier)
                if source.GetTexCoord then texture:SetTexCoord(source:GetTexCoord()) end
                texture:Show()
                return true
            end
        end
    end
    -- 2. Par les noms d'atlas connus du journal de quetes.
    for _, nom in ipairs(ATLAS_JOURNAL) do
        if AtlasExiste(nom) then
            texture:SetAtlas(nom)
            texture:Show()
            return true
        end
    end
    texture:Hide()
    return false
end

-- ---------------------------------------------------------------------------
-- Titre de section, le meme dans toute la suite : sur parchemin, la police
-- des titres du journal de quetes (taille 15) a l'encre ; sur fond sombre,
-- GameFontNormal en or. Le filet dessous : en retrait de 8 des deux bords,
-- un pixel d'ecran exact.
-- ---------------------------------------------------------------------------

charte.TAILLE_TITRE = 15

-- Une ligne reutilisee change de police : sa taille posee a la main part avec.
function charte.PoliceStable(fs)
    if not fs or fs.policeStable then return end
    fs.policeStable = true
    local poser = fs.SetFontObject
    fs.SetFontObject = function(self, objet)
        poser(self, objet)
        local o = type(objet) == "string" and _G[objet] or objet
        if type(o) == "table" and o.GetFont then
            local fichier, taille, options = o:GetFont()
            if fichier then self:SetFont(fichier, taille, options) end
        end
    end
end

function charte.Filet(tex, parent)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 0)
    tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 0)
    if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(tex, 1, 1) else tex:SetHeight(1) end
end

-- Rend true sur parchemin (le titre y prend 6 points de plus en hauteur).
function charte.TitreDeSection(fs, filet)
    local parchemin = charte.Fond() == "parchemin"
    if parchemin then
        fs:SetFontObject(_G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
        local fichier, taille, options = fs:GetFont()
        if fichier and taille and taille > charte.TAILLE_TITRE then fs:SetFont(fichier, charte.TAILLE_TITRE, options) end
        fs:SetTextColor(0.42, 0.18, 0.02)
        if filet then filet:SetColorTexture(0.42, 0.18, 0.02, 0.45) end
    else
        fs:SetFontObject("GameFontNormal")
        fs:SetTextColor(1, 0.82, 0)
        if filet then filet:SetColorTexture(1, 0.82, 0, 0.25) end
    end
    return parchemin
end
