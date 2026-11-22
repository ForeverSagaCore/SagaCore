local _, NS = ...
-- Un filet de separation : en apparence moderne, la couleur commune du theme
-- (repeinte quand il change) ; sinon la couleur donnee.
local function PeindreFilet(t, r, g, b, a)
    local S = _G.CoreSuite
    if S and S.PeindreFilet then S.PeindreFilet(t, r, g, b, a) else t:SetColorTexture(r, g, b, a) end
end

-- Ecran de CraftCore.
--
-- Rien n'est dessine a la main : la fenetre, la zone defilante, les boutons et
-- les polices sont ceux du jeu. Patron repris mot pour mot du journal de donjon
-- installe sur ce client : on essaie les modeles natifs dans l'ordre, chacun
-- sous filet, et on prend le premier qui repond.

NS.ecran = {}
local ecran = NS.ecran

-- Meme taille que QuestCore et MapCore : on passe de l'un a l'autre sans saut.
local LARGEUR, HAUTEUR = 1060, 740
local LARGEUR_MENU = 170
local HAUTEUR_BANDEAU = 118
local HAUTEUR_BARRE = 26
local HAUTEUR_PASTILLES = 34
local HAUTEUR_LIGNE = 20
local MARGE = 12
local ECART = 14
local RETRAIT_LIBELLE = 10
-- Retrait d'un niveau d'arborescence. Declare ici, avant toute page qui s'en
-- sert : declare plus bas, la page des caisses le lisait vide et plantait au
-- depli d'une caisse.
local RETRAIT_PAR_NIVEAU = 16
local ESPACE_SECTION = 14      -- avant chaque titre de section, dans toutes les pages

local L
local fenetre
local SynchroniserOnglets
-- Definie plus bas avec les projets, mais deja utilisee par les parametres.
local RendreChoixDeRecettes
local PoserChoixDeProjet
local PalierDeProgression, COULEURS_PALIER
local BoutonAction

-- Repere de selection, le meme partout : personnage, section et onglet.
-- Ce qui est choisi est eclaire de la couleur des titres du jeu, tout le
-- reste est estompe de moitie. On sait ainsi en un coup d'oeil ou l'on est.
local ALPHA_ESTOMPE = 0.5

local function CouleurSelection()
    -- Apparence moderne : la couleur d'accent du theme (voir la suite).
    local S = _G.CoreSuite
    if S and S.CouleurSelection then return S.CouleurSelection() end
    local c = _G.NORMAL_FONT_COLOR
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

-- Icone choisie ou non : portrait de personnage, onglet de metier, onglet
-- d'equipement ou de caisses. Halo de case cochee du jeu, teinte commune.
local function MarquerSelection(element, choisi, ancre)
    if not element then return end
    -- Onglet : en retrait (plus sombre) quand il n'est pas ouvert, comme les
    -- onglets de la suite ; pas de transparence.
    if element.estOnglet then
        element.choisi = choisi and true or false
        element:SetAlpha(1)
        if element.Icon then
            local v = choisi and 1 or 0.55
            element.Icon:SetVertexColor(v, v, v)
        end
        return
    end
    if not element.haloSelection and element.CreateTexture then
        local halo = element:CreateTexture(nil, "OVERLAY")
        halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        halo:SetBlendMode("ADD")
        halo:SetPoint("TOPLEFT", ancre or element, "TOPLEFT", -2, 2)
        halo:SetPoint("BOTTOMRIGHT", ancre or element, "BOTTOMRIGHT", 2, -2)
        element.haloSelection = halo
    end
    if element.haloSelection then
        element.haloSelection:SetVertexColor(CouleurSelection())
        element.haloSelection:SetShown(choisi and true or false)
    end
    element:SetAlpha(choisi and 1 or ALPHA_ESTOMPE)
end

-- Ligne du menu choisie ou non : meme teinte, meme regle d'estompe.
local function MarquerLigneDeMenu(bouton, choisi)
    local texte = bouton.text or bouton.Text or (bouton.GetFontString and bouton:GetFontString())
    if texte then texte:SetFontObject(choisi and "GameFontHighlight" or "GameFontNormal") end
    if bouton.fond then
        bouton.fond:SetVertexColor(CouleurSelection())
        bouton.fond:SetShown(choisi and true or false)
    end
    -- Brillance normale pour toutes les lignes, comme QuestCore et MapCore.
    bouton:SetAlpha(1)
end

-- Pages ou le metier choisi a droite agit sur le contenu : la son onglet est
-- eclaire, ailleurs tous les onglets de metier sont estompes.
local PAGES_PAR_METIER = { recettes = true, stocks = true, projets = true, progressions = true, commandes = true,
    monter = true }

-- Metiers du perimetre. Les identifiants de ligne sont ceux que le client a
-- renvoyes lors du releve en jeu ; leur nom n'etant pas lisible par ce client,
-- l'onglet porte le libelle traduit et non un nom invente.
-- Icones des metiers. Les identifiants de ligne sont ceux que le client a
-- renvoyes lors du releve en jeu, pas des valeurs supposees. Un metier absent
-- de cette table garde l'icone d'un de ses objets produits.
local ICONES_METIERS = {
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [182] = "Interface\\Icons\\Trade_Herbalism",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [186] = "Interface\\Icons\\Trade_Mining",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [356] = "Interface\\Icons\\Trade_Fishing",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}

NS.ICONES_METIERS = ICONES_METIERS

local METIERS = {
    { cle = "forge",  ligne = 164, libelle = "PROF_BLACKSMITHING", icone = ICONES_METIERS[164] },
    { cle = "minage", ligne = 186, libelle = "PROF_MINING",        icone = ICONES_METIERS[186] },
}

-- Pages, dans l'ordre du menu. Trois groupes separes par un filet :
-- l'atelier ; ce qui suit le metier choisi a droite ; ce qui couvre tous
-- les metiers ; puis les parametres. "filet" : un filet au-dessus.
local PAGES = {
    { cle = "atelier",     libelle = "NAV_DASHBOARD",    icone = "Interface\\Icons\\INV_Misc_Gear_01" },
    -- Le metier choisi a droite.
    { cle = "projets",     libelle = "NAV_PROJECTS",     icone = "Interface\\Icons\\INV_Scroll_03", filet = true },
    { cle = "commandes",   libelle = "NAV_ORDERS",       icone = "Interface\\Icons\\INV_Letter_15" },
    { cle = "recettes",    libelle = "NAV_RECIPES",      icone = "Interface\\Icons\\INV_Misc_Book_09" },
    { cle = "stocks",      libelle = "NAV_STOCKS",       icone = "Interface\\Icons\\INV_Misc_Bag_08" },
    { cle = "monter",      libelle = "NAV_LEVEL_UP_THIS", icone = "Interface\\Icons\\INV_Misc_Book_11" },
    -- Tous les metiers.
    { cle = "stocksTous",  libelle = "NAV_STOCKS_ALL",   icone = "Interface\\Icons\\INV_Misc_Bag_10", filet = true },
    { cle = "progression", libelle = "NAV_LEVEL_UP",     icone = "Interface\\Icons\\INV_Misc_Book_11" },
    -- L'equipement et les caisses ont leur onglet a droite, sous les metiers.
    { cle = "reglages",    libelle = "NAV_SETTINGS",     icone = "Interface\\Icons\\Trade_Engineering", filet = true },
}

-- ---------------------------------------------------------------------------
-- Construction, modeles natifs seulement
-- ---------------------------------------------------------------------------

local function CreerFenetre()
    -- La charte commune a toutes les fenetres de CraftCore.
    local win = NS.charte.Fenetre("CraftCoreWindow", LARGEUR, HAUTEUR)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetToplevel(true)
    if UISpecialFrames then tinsert(UISpecialFrames, "CraftCoreWindow") end
    if win.titre then win.titre:SetText(L.WINDOW_TITLE) end
    -- Les add-ons de la suite, en haut a droite : on bascule de l'un a l'autre.
    if NS.suite then pcall(NS.suite.Entete, win, "CraftCore", win.entete) end
    return win
end

-- Une ligne de menu. Modele de liste natif, repli sur un bouton simple.
local function CreerLigneDeMenu(parent, cheminIcone)
    local bouton
    local ok, cree = pcall(CreateFrame, "Button", nil, parent, "OptionsListButtonTemplate")
    if ok and cree then bouton = cree end
    if not bouton then
        bouton = CreateFrame("Button", nil, parent)
        local texte = bouton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bouton.text = texte
        bouton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    bouton:SetHeight(24)

    -- Fond de selection, la texture que le jeu emploie pour une ligne choisie.
    bouton.fond = bouton:CreateTexture(nil, "BACKGROUND")
    bouton.fond:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    bouton.fond:SetBlendMode("ADD")
    bouton.fond:SetPoint("TOPLEFT", bouton, "TOPLEFT", 0, 0)
    bouton.fond:SetPoint("BOTTOMRIGHT", bouton, "BOTTOMRIGHT", 0, 0)
    bouton.fond:Hide()

    bouton.icone = bouton:CreateTexture(nil, "ARTWORK")
    bouton.icone:SetSize(16, 16)
    bouton.icone:SetPoint("LEFT", bouton, "LEFT", RETRAIT_LIBELLE - 4, 0)
    if cheminIcone then bouton.icone:SetTexture(cheminIcone) end

    -- Le libelle se range derriere l'icone, dans les deux cas de figure.
    local texte = bouton.text or bouton.Text or (bouton.GetFontString and bouton:GetFontString())
    if texte then
        texte:ClearAllPoints()
        texte:SetPoint("LEFT", bouton.icone, "RIGHT", 6, 0)
        texte:SetJustifyH("LEFT")
    end
    return bouton
end

-- Onglet d'icone sur le bord droit : l'onglet du grimoire du jeu, de la
-- meme taille et du meme dessin que les onglets de la suite a gauche (qui
-- en sont le reflet). Celui qui n'est pas ouvert reste en retrait (plus
-- sombre), et s'eclaire au survol.
local TAILLE_ONGLET = 34
local function CreerOngletLateral(fenetreMere, precedent, icone, auClic)
    local onglet = CreateFrame("CheckButton", nil, fenetreMere)
    onglet:SetSize(TAILLE_ONGLET, TAILLE_ONGLET)
    local fond = onglet:CreateTexture(nil, "BACKGROUND")
    fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    do local S = NS.suite or _G.CoreSuite if S and S.TeinteOnglet then S.TeinteOnglet(fond) end end
    fond:SetSize(TAILLE_ONGLET * 2, TAILLE_ONGLET * 2)
    fond:SetPoint("TOPLEFT", -3, 12)
    local face = onglet:CreateTexture(nil, "ARTWORK")
    face:SetAllPoints()
    face:SetTexture(icone)
    onglet.Icon = face
    onglet.estOnglet = true
    onglet:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    onglet:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local halo = onglet:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    onglet:SetScript("OnClick", function(self)
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        self:SetChecked(self.choisi and true or false)
        auClic()
    end)
    onglet:SetScript("OnEnter", function(self)
        self.Icon:SetVertexColor(1, 1, 1)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText)
        GameTooltip:Show()
    end)
    onglet:SetScript("OnLeave", function(self)
        if not self.choisi then self.Icon:SetVertexColor(0.55, 0.55, 0.55) end
        GameTooltip:Hide()
    end)
    if precedent then
        onglet:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -((NS.suite and NS.suite.ECART_ENTRE_ONGLETS) or 14))
    elseif NS.suite and NS.suite.AncreHaut then
        local ancre, point = NS.suite.AncreHaut(fenetreMere, "droite")
        onglet:SetPoint("TOPLEFT", ancre, point, 0, NS.suite.HAUT_ONGLET or -7)
    else
        onglet:SetPoint("TOPLEFT", fenetreMere, "TOPRIGHT", 0, -60)
    end
    return onglet
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

-- Reservoir de lignes : on reutilise, on ne recree pas a chaque actualisation.
local function LigneDeTableau(contenu, index)
    contenu.lignes = contenu.lignes or {}
    local ligne = contenu.lignes[index]
    if ligne then return ligne end

    ligne = CreateFrame("Button", nil, contenu)
    ligne:SetHeight(HAUTEUR_LIGNE)
    -- Declare une fois pour toutes : certains clients ignorent un appel
    -- repete, et le clic droit ne passait pas.
    pcall(ligne.RegisterForClicks, ligne, "LeftButtonUp", "RightButtonUp")

    -- Marqueur de depliage : textures plus et moins du jeu. Patron repris du
    -- journal de donjon, qui s'en sert pour ses sections.
    ligne:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local surbrillance = ligne:GetHighlightTexture()
    if surbrillance then surbrillance:SetAlpha(0) end

    -- Coche de case du jeu, montree seulement pour ce qui est acquis.
    ligne.coche = ligne:CreateTexture(nil, "OVERLAY")
    ligne.coche:SetSize(16, 16)
    ligne.coche:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    ligne.coche:Hide()

    ligne.marqueur = ligne:CreateTexture(nil, "ARTWORK")
    ligne.marqueur:SetSize(14, 14)
    ligne.marqueur:SetPoint("LEFT", ligne, "LEFT", 2, 0)
    ligne.marqueur:Hide()

    ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
    ligne.icone:SetSize(16, 16)
    ligne.icone:SetPoint("LEFT", ligne, "LEFT", 2, 0)

    ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 6, 0)
    ligne.nom:SetJustifyH("LEFT")
    ligne.nom:SetWordWrap(false)
    ligne.nom.agrandir = true
    -- Les lignes servent tour a tour de titre et de ligne simple : changer de
    -- police efface aussi la taille posee a la main (sur parchemin), sinon un
    -- titre garde la taille de la ligne qu'il etait avant.
    local poserObjet = ligne.nom.SetFontObject
    ligne.nom.SetFontObject = function(fs, objet)
        poserObjet(fs, objet)
        local o = type(objet) == "string" and _G[objet] or objet
        if type(o) == "table" and o.GetFont then
            local fichier, taille, options = o:GetFont()
            if fichier then fs:SetFont(NS.Police(fichier), taille, options) end
        end
    end

    -- Filet sous un titre de section : en retrait des deux bords, un pixel
    -- d'ecran exact, le meme partout.
    ligne.filet = ligne:CreateTexture(nil, "ARTWORK")
    ligne.filet:SetPoint("BOTTOMLEFT", ligne, "BOTTOMLEFT", 8, 0)
    ligne.filet:SetPoint("BOTTOMRIGHT", ligne, "BOTTOMRIGHT", -8, 0)
    if _G.PixelUtil and _G.PixelUtil.SetHeight then
        _G.PixelUtil.SetHeight(ligne.filet, 1, 1)
    else
        ligne.filet:SetHeight(1)
    end
    ligne.filet:Hide()

    ligne.total = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne.total:SetPoint("RIGHT", ligne, "RIGHT", -8, 0)
    ligne.total:SetJustifyH("RIGHT")
    ligne.total:SetWidth(45)
    -- Jamais sur deux lignes.
    ligne.total:SetWordWrap(false)
    if ligne.total.SetMaxLines then ligne.total:SetMaxLines(1) end

    ligne.banque = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ligne.banque:SetPoint("RIGHT", ligne.total, "LEFT", -12, 0)
    ligne.banque:SetJustifyH("RIGHT")
    ligne.banque:SetWidth(45)

    ligne.coche:SetPoint("RIGHT", ligne.total, "LEFT", -4, 0)

    -- Colonne du courrier : seulement sur la page des stocks.
    ligne.courrier = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ligne.courrier:SetPoint("RIGHT", ligne.total, "LEFT", -12, 0)
    ligne.courrier:SetJustifyH("RIGHT")
    ligne.courrier:SetWidth(45)
    ligne.courrier:Hide()

    ligne.sacs = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ligne.sacs:SetPoint("RIGHT", ligne.banque, "LEFT", -12, 0)
    ligne.sacs:SetJustifyH("RIGHT")
    ligne.sacs:SetWidth(45)

    -- Le nom occupe toute la place restante : un libelle ne se coupe jamais,
    -- ce sont les colonnes de chiffres qui sont bornees.
    ligne.nom:SetPoint("RIGHT", ligne.sacs, "LEFT", -12, 0)

    -- Boutons de quantite, modele de bouton du jeu. Caches tant qu'une page ne
    -- les demande pas.
    ligne.moins = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
    ligne.moins:SetSize(18, 18)
    ligne.moins:SetText("-")
    ligne.moins:Hide()

    ligne.plus = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
    ligne.plus:SetSize(18, 18)
    ligne.plus:SetText("+")
    ligne.plus:Hide()

    ligne.quantite = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne.quantite:SetWidth(30)
    ligne.quantite:SetJustifyH("CENTER")
    ligne.quantite:Hide()

    if contenu.largeurChiffre then
        ligne.sacs:SetWidth(contenu.largeurChiffre)
        ligne.banque:SetWidth(contenu.largeurChiffre)
        ligne.total:SetWidth(contenu.largeurEtat or contenu.largeurChiffre)
        ligne.total:SetJustifyH(contenu.largeurEtat and "LEFT" or "RIGHT")
    end

    contenu.lignes[index] = ligne
    return ligne
end

-- Les lignes servent aux deux pages : la colonne de droite porte un chiffre
-- sur les stocks, un libelle entier sur les recettes.
local function LargeurDesColonnes(contenu, largeurChiffre, largeurEtat)
    for _, ligne in ipairs(contenu.lignes or {}) do
        ligne.sacs:SetWidth(largeurChiffre)
        ligne.banque:SetWidth(largeurChiffre)
        ligne.total:SetWidth(largeurEtat or largeurChiffre)
        ligne.total:SetJustifyH(largeurEtat and "LEFT" or "RIGHT")
    end
    contenu.largeurChiffre = largeurChiffre
    contenu.largeurEtat = largeurEtat
end

-- Couleurs. Les constantes du jeu sont utilisees si le client les expose,
-- sinon un repli explicite plutot qu'une teinte inventee ailleurs dans le code.
local function CouleurAcquis()
    local c = _G.GREEN_FONT_COLOR
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 0.12, 0.85, 0.30
end

local function CouleurManque()
    local c = _G.GRAY_FONT_COLOR
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 0.55, 0.55, 0.55
end

-- Vert et coche pour ce qui est acquis, gris pour ce qui manque. La couleur se
-- pose toujours apres la police, qui sinon la remettrait a zero.
local function Marquer(ligne, acquis, police, objet)
    ligne.nom:SetFontObject(police or "GameFontHighlightSmall")
    ligne.total:SetFontObject(police or "GameFontHighlightSmall")

    -- Un nom d'objet garde toujours sa couleur de qualite. Ce qu'on possede se
    -- lit a la coche et a la colonne d'etat, sinon tout se confondrait.
    if objet and NS.objets and NS.objets.CouleurDuNom then
        ligne.nom:SetTextColor(NS.objets.CouleurDuNom(objet))
    elseif acquis then
        ligne.nom:SetTextColor(CouleurAcquis())
    else
        ligne.nom:SetTextColor(CouleurManque())
    end

    if acquis then
        ligne.total:SetTextColor(CouleurAcquis())
        ligne.coche:Show()
    else
        ligne.total:SetTextColor(CouleurManque())
        ligne.coche:Hide()
    end
end

-- Prepare une ligne : retrait, marqueur de depliage, et clic s'il y a lieu.
-- Repose le libelle entre l'icone et la butee donnee. Toujours en effacant les
-- ancrages precedents : un element reutilise ne doit jamais les cumuler.
local function AncrerLibelle(ligne, butee)
    ligne.nom:ClearAllPoints()
    ligne.nom:SetPoint("LEFT", ligne.icone, "RIGHT", 6, 0)
    ligne.nom:SetPoint("RIGHT", butee, "LEFT", -8, 0)
end

-- La colonne du courrier, entre la banque et la colonne de droite.
local function ColonneCourrier(ligne, oui)
    if not ligne.courrier then return end
    ligne.courrier:SetText("")
    ligne.courrier:SetShown(oui == true)
    ligne.courrier:SetWidth(ligne.banque:GetWidth() or 45)
    ligne.banque:ClearAllPoints()
    if oui then
        ligne.banque:SetPoint("RIGHT", ligne.courrier, "LEFT", -12, 0)
    else
        ligne.banque:SetPoint("RIGHT", ligne.total, "LEFT", -12, 0)
    end
end

-- Cinquieme colonne (le total des stocks), tout a droite.
local function ColonneSomme(ligne, oui)
    if not ligne.somme then
        if not oui then return end
        ligne.somme = ligne:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ligne.somme:SetPoint("RIGHT", ligne, "RIGHT", -8, 0)
        ligne.somme:SetJustifyH("RIGHT")
    end
    ligne.somme:SetText("")
    ligne.somme:SetWidth(ligne.sacs:GetWidth() or 45)
    ligne.somme:SetShown(oui == true)
    ligne.total:ClearAllPoints()
    if oui then
        ligne.total:SetPoint("RIGHT", ligne.somme, "LEFT", -12, 0)
    else
        ligne.total:SetPoint("RIGHT", ligne, "RIGHT", -8, 0)
    end
end

-- Bande legere a la couleur de classe, derriere la ligne d'un personnage.
local function BandeDeClasse(ligne, c)
    if not ligne.bande then
        if not c then return end
        ligne.bande = ligne:CreateTexture(nil, "BACKGROUND")
        ligne.bande:SetAllPoints()
    end
    if c then
        ligne.bande:SetColorTexture(1, 1, 1, 1)
        local ok = ligne.bande.SetGradient and _G.CreateColor and pcall(ligne.bande.SetGradient, ligne.bande, "HORIZONTAL",
            _G.CreateColor(c.r, c.g, c.b, 0.3), _G.CreateColor(c.r, c.g, c.b, 0))
        if not ok then ligne.bande:SetColorTexture(c.r, c.g, c.b, 0.18) end
        ligne.bande:Show()
    else
        ligne.bande:Hide()
    end
end

local function PoserLigne(ligne, retrait, depliable, deplie, auClic)
    -- Une ligne reutilisee ne garde jamais l'infobulle de sa page precedente.
    ligne:SetScript("OnEnter", nil)
    ligne:SetScript("OnLeave", nil)
    ColonneCourrier(ligne, false)
    ColonneSomme(ligne, false)
    BandeDeClasse(ligne, nil)
    ligne.nom.couleurPropre = nil
    if ligne.cadreVisage then
        ligne.cadreVisage:Hide() ligne.visage:Hide() ligne.detail:Hide() ligne.droiteHaut:Hide()
    end
    ligne.filet:ClearAllPoints()
    ligne.filet:SetPoint("BOTTOMLEFT", ligne, "BOTTOMLEFT", 8, 0)
    ligne.filet:SetPoint("BOTTOMRIGHT", ligne, "BOTTOMRIGHT", -8, 0)
    ligne.moins:Hide()
    ligne.plus:Hide()
    if ligne.fabriquer then ligne.fabriquer:Hide() end
    if ligne.manque then ligne.manque:Hide() end
    if ligne.palier then ligne.palier:Hide() end
    ligne.quantite:Hide()
    AncrerLibelle(ligne, ligne.sacs)
    ligne.coche:Hide()
    ligne.filet:Hide()
    ligne:SetHeight(HAUTEUR_LIGNE)
    ligne.nom:SetFontObject("GameFontHighlightSmall")
    ligne.nom.agrandir = true
    ligne.nom:SetTextColor(1, 1, 1)
    ligne.total:SetTextColor(1, 1, 1)
    ligne.marqueur:ClearAllPoints()
    ligne.marqueur:SetPoint("LEFT", ligne, "LEFT", 2 + retrait, 0)
    ligne.icone:ClearAllPoints()
    if depliable then
        ligne.marqueur:SetTexture(deplie and "Interface\\Buttons\\UI-MinusButton-Up"
            or "Interface\\Buttons\\UI-PlusButton-Up")
        ligne.marqueur:Show()
        ligne.icone:SetPoint("LEFT", ligne.marqueur, "RIGHT", 4, 0)
    else
        ligne.marqueur:Hide()
        ligne.icone:SetPoint("LEFT", ligne, "LEFT", 2 + retrait, 0)
    end
    local surbrillance = ligne.GetHighlightTexture and ligne:GetHighlightTexture()
    if auClic then
        ligne:SetScript("OnClick", auClic)
        ligne:EnableMouse(true)
        if surbrillance then surbrillance:SetAlpha(1) end
    else
        ligne:SetScript("OnClick", nil)
        ligne:EnableMouse(false)
        if surbrillance then surbrillance:SetAlpha(0) end
    end
end

-- Montre les boutons de quantite sur une ligne, ou les retire. Ils se posent
-- a gauche de la colonne d'etat, jamais par dessus un libelle.
local function PoserQuantite(ligne, valeur, auMoins, auPlus)
    if not valeur then
        ligne.moins:Hide()
        ligne.plus:Hide()
        ligne.quantite:Hide()
        return
    end
    ligne.plus:SetWidth(18)
    ligne.plus:SetText("+")
    ligne.moins:ClearAllPoints()
    ligne.moins:SetPoint("RIGHT", ligne.total, "LEFT", -6, 0)
    ligne.quantite:ClearAllPoints()
    ligne.quantite:SetPoint("RIGHT", ligne.moins, "LEFT", -2, 0)
    ligne.plus:ClearAllPoints()
    ligne.plus:SetPoint("RIGHT", ligne.quantite, "LEFT", -2, 0)

    ligne.quantite:SetText("x" .. tostring(valeur))
    ligne.moins:SetScript("OnClick", auMoins)
    ligne.plus:SetScript("OnClick", auPlus)
    ligne.moins:Show()
    ligne.plus:Show()
    ligne.quantite:Show()
    -- Le libelle s'arrete avant les boutons.
    AncrerLibelle(ligne, ligne.plus)
end

-- Bouton d'action unique sur la ligne. Il porte un libelle plutot qu'un plus :
-- le marqueur de depliage en est deja un, deux plus se confondraient.
-- Bouton Fabriquer, a gauche du bouton Ajouter.
-- Bouton Creer, le meme partout ou l'on peut fabriquer : a gauche des autres
-- boutons de la ligne, ou de la colonne d'etat s'il n'y en a pas. Grise
-- quand il manque des composants dans les sacs, et le survol dit lesquels.
local function PoserBoutonFabriquer(ligne, recette, nombre)
    if not ligne.fabriquer then
        ligne.fabriquer = CreateFrame("Button", nil, ligne, "UIPanelButtonTemplate")
        ligne.fabriquer:SetSize(58, 18)
    end
    local b = ligne.fabriquer
    b:ClearAllPoints()
    local voisin = (ligne.plus:IsShown() and ligne.plus) or ligne.total
    b:SetPoint("RIGHT", voisin, "LEFT", voisin == ligne.total and -6 or -4, 0)
    b:SetText(L.CRAFT_BUTTON)
    -- Grise : ce qui manque dans les sacs, ecrit a cote, sans avoir a survoler.
    if not ligne.manque then
        ligne.manque = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ligne.manque:SetJustifyH("RIGHT")
        ligne.manque:SetWordWrap(false)
    end
    ligne.manque:Hide()
    local montre, pret, manques = NS.actions.PreparerBoutonFabriquer(b, recette, nombre)
    if montre then
        local butee = b
        if pret == false and type(manques) == "table" and #manques > 0 then
            local noms = {}
            for _, m in ipairs(manques) do
                table.insert(noms, NS.inventaire.NomDObjet(m.objet) .. (m.manque > 1 and (" x" .. m.manque) or ""))
            end
            ligne.manque:ClearAllPoints()
            ligne.manque:SetPoint("RIGHT", b, "LEFT", -6, 0)
            ligne.manque:SetText(L.GEAR_CRAFT_MISSING .. " " .. table.concat(noms, ", "))
            ligne.manque:SetTextColor(0.9, 0.3, 0.3)
            ligne.manque:Show()
            butee = ligne.manque
        end
        AncrerLibelle(ligne, butee)
    end
end

local function PoserBoutonDeLigne(ligne, libelle, auClic, largeur, bulle)
    ligne.plus:ClearAllPoints()
    ligne.plus:SetPoint("RIGHT", ligne.total, "LEFT", -6, 0)
    ligne.plus:SetWidth(largeur or 92)
    if bulle then
        ligne.plus:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(bulle, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ligne.plus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        ligne.plus:SetScript("OnEnter", nil)
        ligne.plus:SetScript("OnLeave", nil)
    end
    ligne.plus:SetText(libelle)
    ligne.plus:SetScript("OnClick", auClic)
    ligne.plus:Show()
    ligne.moins:Hide()
    ligne.quantite:Hide()
    AncrerLibelle(ligne, ligne.plus)
end

local function CacherLignesAuDela(contenu, depuis)
    if not contenu.lignes then return end
    for i = depuis, #contenu.lignes do
        contenu.lignes[i]:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Briques communes de mise en page : une section, une ligne. Toutes les pages
-- s'en servent, pour les memes espacements et les memes retraits partout.
-- ---------------------------------------------------------------------------


-- Titre de section. Un espace le precede, sauf en haut de page.
-- Decalage de tout un bloc sous une ligne depliee (le detail d'un metier dans
-- la progression) : titres, lignes et paragraphes descendent d'un cran.
local retraitCourant = 0

-- Police des titres de section sur parchemin : celle des titres du journal
-- de quetes, un peu plus petite (15) pour rester a l'echelle des lignes.
local TAILLE_TITRE = 15
local function PoliceDeTitre(fs)
    fs:SetFontObject(_G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
    local fichier, taille, options = fs:GetFont()
    if fichier and taille and taille > TAILLE_TITRE then fs:SetFont(NS.Police(fichier), TAILLE_TITRE, options) end
end

local function TitreDeSection(contenu, index, y, texte, droite)
    if y > 0 then y = y + ESPACE_SECTION end
    index = index + 1
    local titre = LigneDeTableau(contenu, index)
    titre:ClearAllPoints()
    titre:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    titre:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    PoserLigne(titre, retraitCourant, false, false, nil)
    titre.icone:Hide()
    titre.sacs:SetText("") titre.banque:SetText("")
    titre.total:SetFontObject("GameFontDisableSmall")
    titre.total.pasExplication = true
    -- "Fait", "A faire maintenant" : toujours tout a droite, a la meme place.
    titre.total:SetJustifyH("RIGHT")
    titre.total:SetWordWrap(false)
    titre.total:SetText(droite or "")
    titre:Show()
    if NS.charte.Fond() == "parchemin" then
        -- Sur parchemin : la police des titres du journal de quetes, et un
        -- filet d'encre dessous, comme une page du grimoire.
        titre:SetHeight(HAUTEUR_LIGNE + 6)
        PoliceDeTitre(titre.nom)
        titre.nom.agrandir = false
        titre.nom:SetTextColor(0.42, 0.18, 0.02)
        titre.nom:SetText(texte)
        titre.filet:SetColorTexture(0.42, 0.18, 0.02, 0.45)
        titre.filet:Show()
        return index, y + HAUTEUR_LIGNE + 6 + 6
    end
    titre.nom:SetFontObject("GameFontNormal")
    titre.nom:SetTextColor(1, 0.82, 0)
    titre.nom:SetText(texte)
    return index, y + HAUTEUR_LIGNE + 2
end

-- Titre de page : le titre dans la police des titres, et ses controles
-- d'action (bouton, case) cales a droite sur la meme ligne.
local function EnTeteDePage(contenu, index, y, texte, droite)
    index, y = TitreDeSection(contenu, index, y, texte, droite)
    return index, y, contenu.lignes and contenu.lignes[index]
end

-- Style de titre pour un texte isole (pages de reglages).
local function StyleDeTitre(fs)
    -- Le meme filet que sous les titres des autres pages.
    if not fs.filet then
        local parent = fs:GetParent()
        fs.filet = parent:CreateTexture(nil, "ARTWORK")
        fs.filet:SetHeight(1)
        fs.filet:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -5)
        fs.filet:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    end
    if NS.charte.Fond() == "parchemin" then
        PoliceDeTitre(fs)
        fs.agrandir = false
        fs:SetTextColor(0.42, 0.18, 0.02)
        fs.filet:SetColorTexture(0.42, 0.18, 0.02, 0.45)
    else
        fs:SetFontObject("GameFontNormal")
        fs:SetTextColor(1, 0.82, 0)
        PeindreFilet(fs.filet, 1, 0.82, 0, 0.25)
    end
    fs.filet:SetShown(fs:IsShown())
end

-- Ligne simple sous un titre, au premier retrait.
local function LigneSimple(contenu, index, y, icone, texte, droite, auClic, police)
    index = index + 1
    local ligne = LigneDeTableau(contenu, index)
    ligne:ClearAllPoints()
    ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    PoserLigne(ligne, RETRAIT_PAR_NIVEAU + retraitCourant, false, false, auClic)
    if icone then ligne.icone:SetTexture(icone) ligne.icone:Show() else ligne.icone:Hide() end
    ligne.nom:SetFontObject(police or "GameFontHighlightSmall")
    ligne.nom.agrandir = true
    ligne.nom:SetText(texte)
    ligne.sacs:SetText("") ligne.banque:SetText("")
    ligne.total:SetFontObject("GameFontHighlightSmall")
    ligne.total.pasExplication = nil
    -- La ligne a pu servir de titre (calee a droite) : calage de la page.
    ligne.total:SetJustifyH(contenu.largeurEtat and "LEFT" or "RIGHT")
    ligne.total:SetWordWrap(false)
    ligne.total:SetText(droite or "")
    ligne:Show()
    return index, y + HAUTEUR_LIGNE, ligne
end

-- Texte sur plusieurs lignes au besoin, jamais tronque. Meme retrait que les
-- lignes simples. `couleur` : { r, g, b } facultatif.
-- Texte explicatif (legendes, aides) : noir a 40 % sur le parchemin, blanc
-- a 40 % sur fond sombre. Partout le meme, avec les polices du jeu.
function NS.Explication(fs)
    if not fs then return end
    fs:SetFontObject("GameFontDisableSmall")
    local parchemin = NS.charte and NS.charte.Fond and NS.charte.Fond() == "parchemin"
    if parchemin then fs:SetTextColor(0, 0, 0, 0.4) else fs:SetTextColor(1, 1, 1, 0.4) end
end

local function Paragraphe(contenu, y, texte, police, couleur, x)
    contenu.paragraphes = contenu.paragraphes or {}
    contenu.nbParagraphes = (contenu.nbParagraphes or 0) + 1
    local p = contenu.paragraphes[contenu.nbParagraphes]
    if not p then
        p = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        p:SetJustifyH("LEFT")
        p:SetJustifyV("TOP")
        p:SetWordWrap(true)
        if p.SetNonSpaceWrap then p:SetNonSpaceWrap(false) end
        contenu.paragraphes[contenu.nbParagraphes] = p
    end
    local largeur = tonumber(contenu:GetWidth()) or 0
    if largeur < 100 then largeur = LARGEUR - LARGEUR_MENU - MARGE * 2 - ECART * 2 - 40 end
    p:SetFontObject(police or "GameFontHighlight")
    p:ClearAllPoints()
    local gaucheP = x or (RETRAIT_PAR_NIVEAU + retraitCourant + 2)
    p:SetPoint("TOPLEFT", contenu, "TOPLEFT", gaucheP, -(y + 2))
    p:SetWidth(largeur - gaucheP - 8)
    p:SetText(texte)
    if couleur then p:SetTextColor(couleur[1], couleur[2], couleur[3], 1) else p:SetTextColor(1, 1, 1, 1) end
    if police == "GameFontDisableSmall" then NS.Explication(p) end
    p:Show()
    local hauteur = p:GetStringHeight() or 14
    if hauteur < 12 then hauteur = 14 end
    return y + hauteur + 8
end

local function CacherParagraphes(contenu)
    for _, p in ipairs(contenu.paragraphes or {}) do p:Hide() end
    contenu.nbParagraphes = 0
end

-- Mon atelier : l'essentiel du personnage affiche, en un coup d'oeil. Chaque
-- ligne mene a la page qui en dit plus.
local function RendreAtelier(contenu)
    CacherLignesAuDela(contenu, 1)
    local index, y = 0, 0
    local fiche = NS.base.FicheAffichee()
    local cle = NS.base.CleAffichee()
    local catalogue = NS.recettes

    -- Metiers, avec leur niveau et ce qui est pret a fabriquer.
    local metiers = catalogue.MetiersDuPersonnage and catalogue.MetiersDuPersonnage() or {}
    index, y = TitreDeSection(contenu, index, y, L.DASH_TRADES)
    if #metiers == 0 then
        y = Paragraphe(contenu, y, L.DASH_NO_TRADE, "GameFontDisableSmall")
    end
    for _, metier in ipairs(metiers) do
        local prets = 0
        for _, recette in ipairs((catalogue.Pour(metier.ligne))) do
            if catalogue.EstApprise(recette.id) then
                local manques = catalogue.Manques(recette)
                if manques and #manques == 0 then prets = prets + 1 end
            end
        end
        local niveau = metier.rang and (metier.rangMax and metier.rangMax > 0
            and string.format("%d / %d", metier.rang, metier.rangMax) or tostring(metier.rang)) or ""
        local droite = niveau
        if prets > 0 then droite = droite .. "   |cff4fd16a" .. string.format(L.DASH_READY, prets) .. "|r" end
        local ligneMetier = metier.ligne
        index, y = LigneSimple(contenu, index, y, ICONES_METIERS[ligneMetier] or "Interface\\Icons\\INV_Misc_QuestionMark",
            metier.nom or tostring(ligneMetier), droite, function()
                for cleOnglet, onglet in pairs(fenetre.onglets or {}) do
                    if onglet.ligne == ligneMetier then ecran.metier = cleOnglet break end
                end
                ecran.Montrer("recettes")
            end)
    end

    -- Projets en cours, avec leur avancement.
    local projets = NS.projets.Tous(false) or {}
    index, y = TitreDeSection(contenu, index, y, L.DASH_PROJECTS)
    if #projets == 0 then
        index, y = LigneSimple(contenu, index, y, nil, L.DASH_NO_PROJECT, nil,
            function() ecran.Montrer("projets") end, "GameFontDisableSmall")
    end
    for _, projet in ipairs(projets) do
        local arbres = NS.projets.Calculer(projet.id)
        local part = arbres and NS.moteur.Couverture(arbres) or 0
        index, y = LigneSimple(contenu, index, y, "Interface\\Icons\\INV_Scroll_03", NS.projets.NomDe(projet),
            string.format(L.PROJECTS_COVERAGE, math.floor(part * 100 + 0.5)),
            function() ecran.Montrer("projets") end)
    end

    -- Caisses du personnage.
    local caisses = NS.caisses and NS.caisses.Connues and NS.caisses.Connues(cle, false) or {}
    if #caisses > 0 then
        index, y = TitreDeSection(contenu, index, y, L.DASH_CRATES)
        for _, caisse in ipairs(caisses) do
            local prets, total = NS.caisses.PacksPrets(caisse)
            local info = NS.objets.Info(caisse.id)
            index, y = LigneSimple(contenu, index, y, info and info.icone, caisse.nom or tostring(caisse.id),
                string.format(L.CRATES_READY, prets, total), function() ecran.Montrer("caisses") end)
        end
    end

    -- A faire a la banque et a la boite aux lettres, pour le personnage connecte.
    if cle == NS.ClePersonnage() and NS.courrier and NS.courrier.Plan then
        local ok, plan = pcall(NS.courrier.Plan)
        if ok and plan and (#plan.envois + #plan.sortir + #plan.demandes) > 0 then
            index, y = TitreDeSection(contenu, index, y, L.DASH_ERRANDS)
            if #plan.sortir > 0 then
                index, y = LigneSimple(contenu, index, y, "Interface\\Icons\\INV_Misc_Bag_08",
                    string.format(L.DASH_TAKE, #plan.sortir))
            end
            for _, envoi in ipairs(plan.envois) do
                index, y = LigneSimple(contenu, index, y, "Interface\\Icons\\INV_Letter_15",
                    string.format(L.DASH_SEND, envoi.nom, #envoi.lignes))
            end
            if #plan.demandes > 0 then
                index, y = LigneSimple(contenu, index, y, "Interface\\Icons\\INV_Letter_15",
                    string.format(L.DASH_ASK, #plan.demandes))
            end
        end
    end

    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end

-- Portrait d'un personnage (defini plus bas, avec la bande des personnages).
local PoserVisage

-- Couleur exacte de la classe d'un personnage (fiche), ou nil.
local function CouleurDeClasseDe(fiche)
    if type(fiche) ~= "table" then return nil end
    local jeton = fiche.jetonClasse
    if not jeton and type(fiche.classe) == "string" then
        for _, noms in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
            for cle, nom in pairs(type(noms) == "table" and noms or {}) do
                if nom == fiche.classe then jeton = cle break end
            end
            if jeton then break end
        end
    end
    return jeton and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[jeton] or nil
end

-- Ligne d'un personnage, reprise de LegacyCore : son portrait dans un cadre,
-- son nom a la couleur de sa classe, une ligne de detail dessous, et a
-- droite son niveau.
local function LigneDePersonnage(ligne, fiche, estConnecte, couleur, detail, droite)
    if not ligne.cadreVisage then
        ligne.cadreVisage = ligne:CreateTexture(nil, "BORDER")
        ligne.cadreVisage:SetSize(34, 34)
        ligne.cadreVisage:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
        ligne.visage = ligne:CreateTexture(nil, "ARTWORK")
        ligne.visage:SetPoint("TOPLEFT", ligne.cadreVisage, "TOPLEFT", 5, -5)
        ligne.visage:SetPoint("BOTTOMRIGHT", ligne.cadreVisage, "BOTTOMRIGHT", -5, 5)
        ligne.detail = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ligne.detail:SetJustifyH("LEFT")
        ligne.droiteHaut = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ligne.droiteHaut:SetJustifyH("RIGHT")
    end
    ligne.icone:Hide()
    ligne.cadreVisage:ClearAllPoints()
    ligne.cadreVisage:SetPoint("TOPLEFT", ligne, "TOPLEFT", 4, 1)
    ligne.cadreVisage:Show()
    ligne.visage:SetTexCoord(0, 1, 0, 1)
    PoserVisage(ligne.visage, fiche, estConnecte)
    ligne.visage:Show()
    ligne.nom:ClearAllPoints()
    ligne.nom:SetPoint("TOPLEFT", ligne, "TOPLEFT", 42, -4)
    ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -90, 0)
    ligne.nom:SetFontObject("GameFontNormal")
    ligne.nom.agrandir = false
    if couleur then
        ligne.nom:SetTextColor(couleur.r, couleur.g, couleur.b)
        ligne.nom.couleurPropre = true
    end
    ligne.nom:SetText(NS.inventaire.NomCourt(fiche.cle))
    ligne.detail:ClearAllPoints()
    ligne.detail:SetPoint("TOPLEFT", ligne, "TOPLEFT", 42, -(HAUTEUR_LIGNE - 2))
    ligne.detail:SetPoint("RIGHT", ligne, "RIGHT", -8, 0)
    ligne.detail:SetText(detail or "")
    ligne.detail:SetTextColor(0.8, 0.8, 0.8)
    ligne.detail:Show()
    ligne.droiteHaut:ClearAllPoints()
    ligne.droiteHaut:SetPoint("TOPRIGHT", ligne, "TOPRIGHT", -8, -4)
    ligne.droiteHaut:SetText(droite or "")
    ligne.droiteHaut:Show()
    ligne.sacs:SetText("") ligne.banque:SetText("") ligne.total:SetText("")
    ligne:SetHeight(38)
end

-- Texte ramene a une forme simple pour chercher : minuscules, sans accents.
local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e",
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["î"] = "i", ["ï"] = "i", ["Î"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Û"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["œ"] = "oe", ["’"] = "'" }
local function Simplifier(texte)
    texte = tostring(texte or "")
    for avec, sans in pairs(ACCENTS) do texte = string.gsub(texte, avec, sans) end
    return string.lower(texte)
end

local function RendreStocks(contenu, tous)
    local base = NS.base
    local inventaire = NS.inventaire

    -- Tout etat lu du disque est actualise avant d'etre montre.
    inventaire.Relever(ecran.banqueOuverte)

    -- Le metier choisi filtre les stocks : seuls ses composants et ses
    -- produits sont montres. Tant qu'aucune recette de ce metier n'a ete
    -- relevee, rien n'est filtre plutot que de tout cacher.
    local lies = (not tous) and NS.recettes and NS.recettes.ObjetsDuMetier
        and NS.recettes.ObjetsDuMetier(ecran.ongletCourantLigne) or nil
    -- Tous les metiers : les objets ranges sous chaque metier, dans l'ordre
    -- des onglets ; ce qui n'est a aucun metier, a la fin.
    local metiersDuRangement = {}
    if tous and NS.recettes and NS.recettes.ObjetsDuMetier then
        for _, cleO in ipairs((fenetre and fenetre.ordreOnglets) or {}) do
            local onglet = fenetre.onglets[cleO]
            local objets = onglet and NS.recettes.ObjetsDuMetier(onglet.ligne)
            if objets then
                local nom = (NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(onglet.ligne)) or onglet.libelleParDefaut or "?"
                table.insert(metiersDuRangement, { nom = nom, icone = ICONES_METIERS[onglet.ligne], objets = objets })
            end
        end
    end

    -- Tous mes stocks : seulement ce qui sert aux metiers (composants et
    -- produits), jamais l'equipement ni le reste des sacs.
    local function DeCraft(cle)
        local n = tonumber(cle)
        for _, m in ipairs(metiersDuRangement) do if m.objets[n] then return true end end
        return false
    end

    -- Choix du personnage. Le sien par defaut, les autres sur demande, sans
    -- quitter la page.
    local choix = base.PersonnageAffiche()
    local courant = NS.ClePersonnage()
    local index = 0
    local y = 0
    local pageStocks = ecran.page

    local tousLesPersos = base.TousLesPersonnages()
    local titre
    index, y, titre = EnTeteDePage(contenu, index, y, tous and L.NAV_STOCKS_ALL or L.NAV_STOCKS)
    if #tousLesPersos > 1 and titre and not ecran.objetStock then
        PoserBoutonDeLigne(titre, choix == "tous" and L.STOCKS_THIS_CHAR_SHORT or L.STOCKS_ALL_SHORT,
            function()
                if choix == "tous" then
                    base.PoserPersonnageAffiche(courant)
                else
                    base.PoserPersonnageAffiche("tous")
                end
                ecran.Montrer(pageStocks)
            end, 130)
    end
    if titre and titre.plus and titre.plus:IsShown() then
        -- Tout a droite, au bord de la page.
        titre.plus:ClearAllPoints()
        titre.plus:SetPoint("RIGHT", titre, "RIGHT", -4, 0)
    end

    -- Champ de recherche, sous le titre, avant le premier personnage.
    if not contenu.rechercheStock then
        local ok, champ = pcall(CreateFrame, "EditBox", nil, contenu, "SearchBoxTemplate")
        if not ok or not champ then champ = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate") end
        champ:SetSize(260, 20)
        champ:SetAutoFocus(false)
        champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        champ:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        champ:HookScript("OnTextChanged", function(self)
            local texte = self:GetText() or ""
            if texte == (ecran.rechercheStock or "") then return end
            ecran.rechercheStock = texte
            ecran.objetStock = nil
            ecran.Montrer(ecran.page)
        end)
        if champ.Instructions then champ.Instructions:SetText(L.STOCKS_SEARCH) end
        contenu.rechercheStock = champ
    end
    local champ = contenu.rechercheStock
    champ:ClearAllPoints()
    champ:SetPoint("TOPLEFT", contenu, "TOPLEFT", 8, -(y + 2))
    if (champ:GetText() or "") ~= (ecran.rechercheStock or "") then champ:SetText(ecran.rechercheStock or "") end
    champ:Show()
    y = y + 30
    local mots = {}
    for mot in string.gmatch(Simplifier(ecran.rechercheStock or ""), "%S+") do table.insert(mots, mot) end
    local function Garde(objet)
        if #mots == 0 then return true end
        local nom = Simplifier(inventaire.NomDObjet(objet))
        for _, mot in ipairs(mots) do if not string.find(nom, mot, 1, true) then return false end end
        return true
    end

    -- Un personnage : son nom a la couleur exacte de sa classe.
    local function CouleurDe(fiche)
        local jeton = fiche and fiche.jetonClasse
        -- Fiche sans jeton : sa classe retrouvee par son nom traduit.
        if not jeton and fiche and type(fiche.classe) == "string" then
            for _, noms in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
                for cle, nom in pairs(type(noms) == "table" and noms or {}) do
                    if nom == fiche.classe then jeton = cle break end
                end
                if jeton then break end
            end
        end
        return jeton and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[jeton] or nil
    end
    local function NommerPersonnage(fs, fiche, suite)
        local c = CouleurDe(fiche)
        local nom = NS.inventaire.NomCourt(fiche.cle)
        if c then
            fs:SetTextColor(c.r, c.g, c.b)
            fs.couleurPropre = true
        end
        fs:SetText(nom .. (suite and ("|cff8c8c8c" .. suite .. "|r") or ""))
    end
    local function Chiffre(n) return (n and n > 0) and tostring(n) or "" end
    -- Les cinq colonnes : sacs, banque, courrier, autres persos, total.
    local function Colonnes(l, sacs, banque, courrier, autres, somme)
        ColonneCourrier(l, true)
        ColonneSomme(l, true)
        l.sacs:SetText(Chiffre(sacs))
        l.banque:SetText(Chiffre(banque))
        l.courrier:SetText(Chiffre(courrier))
        l.total:SetText(Chiffre(autres))
        l.somme:SetText(Chiffre(somme))
    end
    local function EnTetesDeColonnes(l, avecAutres)
        ColonneCourrier(l, true)
        ColonneSomme(l, true)
        l.sacs:SetText(L.COL_BAGS)
        l.banque:SetText(L.COL_BANK)
        l.courrier:SetText(L.COL_MAIL)
        l.total:SetText(avecAutres and L.COL_OTHERS or "")
        l.somme:SetText(L.COL_TOTAL)
    end
    local function NouvelleLigne(retrait, auClic, decalage)
        index = index + 1
        local l = LigneDeTableau(contenu, index)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -(y + (decalage or 0)))
        l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -(y + (decalage or 0)))
        PoserLigne(l, retrait, false, false, auClic)
        return l
    end
    local function Message(texte, retrait)
        local l = NouvelleLigne(retrait, nil)
        l.icone:Hide()
        l.nom:SetFontObject("GameFontDisableSmall")
        l.nom:SetText(texte)
        l.sacs:SetText("") l.banque:SetText("") l.total:SetText("")
        l:Show()
        y = y + HAUTEUR_LIGNE
    end

    -- Un objet choisi (clic ou bouton A) : qui en a combien, et le total.
    if ecran.objetStock then
        local objet = ecran.objetStock
        local tete = NouvelleLigne(0, nil)
        local icone = NS.jeu.iconeObjet and NS.Appeler(NS.jeu.iconeObjet, tonumber(objet))
        if icone then tete.icone:SetTexture(icone) tete.icone:Show() else tete.icone:Hide() end
        tete.nom:SetFontObject("GameFontNormal")
        if NS.objets and NS.objets.CouleurDuNom then tete.nom:SetTextColor(NS.objets.CouleurDuNom(tonumber(objet))) end
        tete.nom:SetText(inventaire.NomDObjet(objet))
        tete.sacs:SetText("") tete.banque:SetText("") tete.total:SetText("")
        PoserBoutonDeLigne(tete, L.STOCKS_SHOW_ALL, function()
            ecran.objetStock = nil
            ecran.Montrer(pageStocks)
        end, 130)
        tete.plus:ClearAllPoints()
        tete.plus:SetPoint("RIGHT", tete, "RIGHT", -4, 0)
        tete:SetHeight(HAUTEUR_LIGNE + 4)
        tete:Show()
        y = y + HAUTEUR_LIGNE + 10
        local entete = NouvelleLigne(RETRAIT_PAR_NIVEAU, nil)
        entete.icone:Hide()
        entete.nom:SetText("")
        EnTetesDeColonnes(entete, false)
        entete:Show()
        y = y + HAUTEUR_LIGNE + 2
        local tS, tB, tC, n = 0, 0, 0, 0
        for _, fiche in ipairs(tousLesPersos) do
            local sacs, banque, courrier = inventaire.SacsEtBanque(fiche, objet)
            courrier = courrier or 0
            if sacs + banque + courrier > 0 then
                n = n + 1
                tS, tB, tC = tS + sacs, tB + banque, tC + courrier
                -- Le meme en-tete que dans la liste : portrait, nom, releve.
                local l = NouvelleLigne(0, nil)
                LigneDePersonnage(l, fiche, fiche.cle == courant, CouleurDe(fiche),
                    string.format(L.STOCKS_READ_ON, base.ReleveDe(fiche) or "?"), "")
                Colonnes(l, sacs, banque, courrier, 0, sacs + banque + courrier)
                l:Show()
                y = y + 38 + 6
            end
        end
        if n == 0 then
            Message(L.STOCKS_NOBODY, RETRAIT_PAR_NIVEAU)
        else
            local somme = NouvelleLigne(RETRAIT_PAR_NIVEAU, nil, 4)
            somme.icone:Hide()
            somme.nom:SetFontObject("GameFontNormal")
            somme.nom:SetTextColor(1, 0.82, 0)
            somme.nom:SetText(L.COL_TOTAL)
            Colonnes(somme, tS, tB, tC, 0, tS + tB + tC)
            somme.filet:ClearAllPoints()
            somme.filet:SetPoint("TOPLEFT", somme, "TOPLEFT", RETRAIT_PAR_NIVEAU, 2)
            somme.filet:SetPoint("TOPRIGHT", somme, "TOPRIGHT", -8, 2)
            PeindreFilet(somme.filet, 1, 0.82, 0, 0.25)
            somme.filet:Show()
            somme:Show()
            y = y + HAUTEUR_LIGNE + 8
        end
        CacherLignesAuDela(contenu, index + 1)
        contenu:SetHeight(math.max(y, 1))
        return
    end

    local fiches = {}
    for _, fiche in ipairs(tousLesPersos) do
        if choix == "tous" or fiche.cle == choix then
            table.insert(fiches, fiche)
        end
    end
    if #fiches == 0 then fiches = tousLesPersos end

    -- Retraits : le personnage, puis le metier, puis ses objets.
    local retraitObjet = tous and (RETRAIT_PAR_NIVEAU * 2) or RETRAIT_PAR_NIVEAU

    for rangFiche, fiche in ipairs(fiches) do
        -- En-tete du personnage, comme dans LegacyCore : portrait, nom a la
        -- couleur de sa classe, date du releve dessous, niveau a droite.
        local fiche_ = fiche
        local entete = NouvelleLigne(0, nil)
        LigneDePersonnage(entete, fiche_, fiche_.cle == courant, CouleurDe(fiche_),
            string.format(L.STOCKS_READ_ON, base.ReleveDe(fiche_) or "?"),
            fiche_.niveau and string.format(L.CHAR_LEVEL, fiche_.niveau) or "")
        entete:Show()
        y = y + 38 + 6
        -- Les titres des colonnes, sous le personnage.
        local titresCol = NouvelleLigne(0, nil)
        titresCol.icone:Hide()
        titresCol.nom:SetText("")
        EnTetesDeColonnes(titresCol, true)
        titresCol:Show()
        y = y + HAUTEUR_LIGNE + 2

        -- Sur un seul personnage, on montre aussi ce qu'il n'a pas mais que
        -- ses autres personnages detiennent : c'est ce qui se rapatrie. Vue
        -- de tous les personnages, chacun ne montre que ce qu'il a, sinon
        -- tout se repeterait d'un bloc a l'autre.
        local objetsVus = {}
        for cle in pairs(base.StocksDe(fiche)) do objetsVus[cle] = true end
        for cle in pairs(inventaire.ObjetsAuCourrier and inventaire.ObjetsAuCourrier(fiche) or {}) do objetsVus[cle] = true end
        if #fiches == 1 then
            for _, autre in ipairs(tousLesPersos) do
                if autre.cle ~= fiche.cle and ((not fiche.faction) or (not autre.faction) or autre.faction == fiche.faction) then
                    for cle in pairs(base.StocksDe(autre)) do objetsVus[cle] = true end
                    for cle in pairs(inventaire.ObjetsAuCourrier and inventaire.ObjetsAuCourrier(autre) or {}) do objetsVus[cle] = true end
                end
            end
        end

        local lignes = {}
        for cle in pairs(objetsVus) do
            if ((not lies) or lies[tonumber(cle)]) and (not tous or DeCraft(cle)) and Garde(cle) then
                local sacs, banque, courrier = inventaire.SacsEtBanque(fiche, cle)
                courrier = courrier or 0
                local autres, detail = inventaire.DetailChezLesAutres(fiche, cle)
                if sacs + banque + courrier + autres > 0 then
                    table.insert(lignes, { objet = cle, sacs = sacs, banque = banque, courrier = courrier,
                        autres = autres, detail = detail, total = sacs + banque + courrier })
                end
            end
        end
        table.sort(lignes, function(a, b)
            if a.total ~= b.total then return a.total > b.total end
            if a.autres ~= b.autres then return a.autres > b.autres end
            return a.objet < b.objet
        end)
        -- Tous les metiers : un intertitre par metier, ses objets dessous.
        if tous and #metiersDuRangement > 0 and #lignes > 0 then
            local ranges, pris = {}, {}
            for _, m in ipairs(metiersDuRangement) do
                local siens = {}
                for _, l in ipairs(lignes) do
                    if not pris[l.objet] and m.objets[tonumber(l.objet)] then table.insert(siens, l) pris[l.objet] = true end
                end
                if #siens > 0 then
                    table.insert(ranges, { intertitre = m.nom, icone = m.icone })
                    for _, l in ipairs(siens) do table.insert(ranges, l) end
                end
            end
            lignes = ranges
        end

        -- Un filtre qui ne laisse rien le dit, au lieu de laisser un blanc.
        if #lignes == 0 then
            Message((#mots > 0 and L.STOCKS_SEARCH_NONE) or (tous and L.STOCKS_NONE_CRAFT) or (lies and L.STOCKS_NONE_FOR_TRADE) or L.STOCKS_EMPTY, RETRAIT_PAR_NIVEAU)
        end

        local premierInter = true
        for _, l in ipairs(lignes) do
          if l.intertitre then
            -- Le metier : comme une categorie de Mes recettes, au retrait du
            -- personnage plus un cran, avec son filet.
            if not premierInter then y = y + 6 end
            premierInter = false
            local inter = NouvelleLigne(RETRAIT_PAR_NIVEAU, nil)
            if l.icone then inter.icone:SetTexture(l.icone) inter.icone:Show() else inter.icone:Hide() end
            inter.nom.agrandir = false
            if NS.charte.Fond() == "parchemin" then
                PoliceDeTitre(inter.nom)
                inter.nom:SetTextColor(0.42, 0.18, 0.02)
                inter.filet:SetColorTexture(0.42, 0.18, 0.02, 0.45)
            else
                inter.nom:SetFontObject("GameFontNormal")
                inter.nom:SetTextColor(1, 0.82, 0)
                PeindreFilet(inter.filet, 1, 0.82, 0, 0.25)
            end
            inter.nom:SetText(l.intertitre)
            inter.filet:ClearAllPoints()
            inter.filet:SetPoint("BOTTOMLEFT", inter, "BOTTOMLEFT", RETRAIT_PAR_NIVEAU, 0)
            inter.filet:SetPoint("BOTTOMRIGHT", inter, "BOTTOMRIGHT", -8, 0)
            inter.filet:Show()
            inter.sacs:SetText("") inter.banque:SetText("") inter.total:SetText("")
            inter:SetHeight(HAUTEUR_LIGNE + 6)
            inter:Show()
            y = y + HAUTEUR_LIGNE + 6 + 6
          else
            local objet, detail, nomFiche = tonumber(l.objet), l.detail, fiche.cle
            local cleObjet = l.objet
            -- Clic (ou bouton A) : cet objet chez tous les personnages.
            local ligne = NouvelleLigne(retraitObjet, function()
                ecran.objetStock = cleObjet
                ecran.Montrer(pageStocks)
            end)
            ligne.nom:SetFontObject("GameFontHighlightSmall")
            if NS.objets and NS.objets.CouleurDuNom then
                ligne.nom:SetTextColor(NS.objets.CouleurDuNom(objet))
            end
            ligne.nom:SetText(inventaire.NomDObjet(l.objet))
            local icone = NS.jeu.iconeObjet and NS.Appeler(NS.jeu.iconeObjet, objet)
            if icone then
                ligne.icone:SetTexture(icone)
                ligne.icone:Show()
            else
                ligne.icone:Hide()
            end
            Colonnes(ligne, l.sacs, l.banque, l.courrier, l.autres, l.total + l.autres)

            -- Au survol, qui detient combien, personnage par personnage, et
            -- dans quelle boite aux lettres.
            local sacsIci, banqueIci, courrierIci = l.sacs, l.banque, l.courrier
            ligne:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(inventaire.NomDObjet(objet))
                local function Ligne(cle, sacs, banque, courrier)
                    local nom = NS.inventaire.NomCourt(cle)
                    GameTooltip:AddDoubleLine(nom, NS.inventaire.TexteSacsBanque(sacs, banque, courrier),
                        1, 1, 1, 1, 1, 1)
                end
                if sacsIci + banqueIci + courrierIci > 0 then Ligne(nomFiche, sacsIci, banqueIci, courrierIci) end
                for _, d in ipairs(detail) do Ligne(d.cle, d.sacs, d.banque, d.courrier) end
                GameTooltip:Show()
            end)
            ligne:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ligne:Show()
            y = y + HAUTEUR_LIGNE
          end
        end

        if fiche.quantitesIncertaines then
            Message(L.STOCKS_UNCERTAIN, retraitObjet)
        end

        y = y + ESPACE_SECTION
    end

    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end

-- Message seul au milieu d'une page, pose toujours de la meme facon.
local function PoserMessage(contenu, texte, hauteur)
    contenu.aVenir = contenu.aVenir or contenu:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    contenu.aVenir:ClearAllPoints()
    contenu.aVenir:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, -(hauteur or 0) - 4)
    -- La largeur n'est pas forcement resolue au premier affichage : on retombe
    -- sur la largeur prevue plutot que de calculer une largeur negative.
    local largeur = tonumber(contenu:GetWidth()) or 0
    if largeur < 40 then largeur = LARGEUR - LARGEUR_MENU - MARGE - ECART * 2 - 40 end
    contenu.aVenir:SetWidth(largeur - 8)
    contenu.aVenir:SetJustifyH("LEFT")
    contenu.aVenir:SetText(texte)
    contenu.aVenir:Show()
end

-- Page des reglages. Case a cocher du jeu, libelle cliquable comme la case,
-- patron repris du journal de donjon.
-- Parametres de StuffCore : la presentation de Mon equipement et jusqu'a
-- quel niveau les objets sont proposes.
local function RendreReglagesStuff(contenu)
    -- Comme les Parametres de CraftCore : pas d'en-tete de page, la
    -- premiere section en haut, ses reglages au premier retrait.
    CacherLignesAuDela(contenu, 1)
    local yy = -18
    do
        -- Equipement : la presentation de Mon equipement (1, 2 ou 3, avec ce
        -- qu'elle montre), et jusqu'a quel niveau les objets sont proposes.
        local S2 = _G.CoreSuite
        if S2 and S2.Curseur and S2.ListeDeroulante and NS.equipement then
            local G = NS.base.ReglagesGeneraux()
            if not contenu.titreEquipReg then
                contenu.titreEquipReg = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                contenu.libellePresentation = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                contenu.listePresentation = S2.ListeDeroulante(contenu,
                    { { 1, L.GEAR_PRES_1 }, { 2, L.GEAR_PRES_2 }, { 3, L.GEAR_PRES_3 } },
                    function() return NS.equipement.Scenario() end,
                    function(v) NS.equipement.PoserScenario(tonumber(v) or 1) end,
                    function() ecran.Montrer("reglagesStuff") end)
                contenu.textePresentation = contenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                contenu.textePresentation:SetJustifyH("LEFT")
                contenu.textePresentation:SetWordWrap(false)
                contenu.libelleMarge = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                contenu.curseurMarge = S2.Curseur(contenu, 0, 60, 1,
                    function() return tonumber(NS.base.ReglagesGeneraux().margeEquipement) or 10 end,
                    function(v) NS.base.ReglagesGeneraux().margeEquipement = v ecran.Montrer("reglagesStuff") end,
                    nil, nil, 5)
                contenu.curseurMarge.surParchemin = function() return NS.charte.Fond and NS.charte.Fond() == "parchemin" end
                contenu.caseTousNiveaux = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
                contenu.caseTousNiveaux:SetSize(24, 24)
                contenu.caseTousNiveaux.libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                contenu.caseTousNiveaux:SetScript("OnClick", function(self)
                    NS.base.ReglagesGeneraux().tousNiveauxEquipement = self:GetChecked() and true or nil
                    ecran.Montrer("reglagesStuff")
                end)
            end
            contenu.titreEquipReg:SetText(L.SETTING_GEAR)
            contenu.titreEquipReg:ClearAllPoints()
            contenu.titreEquipReg:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, -(yy + 18))
            contenu.titreEquipReg:Show()
            StyleDeTitre(contenu.titreEquipReg)
            yy = yy + 18 + 40
            contenu.libellePresentation:SetText(L.GEAR_PRES_LABEL)
            contenu.libellePresentation:ClearAllPoints()
            contenu.libellePresentation:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 7))
            contenu.libellePresentation:Show()
            contenu.listePresentation:ClearAllPoints()
            contenu.listePresentation:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            contenu.listePresentation:Show()
            contenu.listePresentation.Rendre()
            yy = yy + 28
            contenu.textePresentation:SetText(L["GEAR_PRES_" .. NS.equipement.Scenario() .. "_TIP"])
            contenu.textePresentation:ClearAllPoints()
            contenu.textePresentation:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -yy)
            contenu.textePresentation:SetPoint("RIGHT", contenu, "RIGHT", -10, 0)
            contenu.textePresentation:Show()
            yy = yy + 24
            local tous = G.tousNiveauxEquipement == true
            contenu.libelleMarge:SetText(L.SETTING_GEAR_MARGIN)
            contenu.libelleMarge:ClearAllPoints()
            contenu.libelleMarge:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 7))
            contenu.libelleMarge:Show()
            contenu.libelleMarge:SetAlpha(tous and 0.4 or 1)
            contenu.curseurMarge:ClearAllPoints()
            contenu.curseurMarge:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            contenu.curseurMarge:SetShown(not tous)
            if contenu.curseurMarge.Rendre then contenu.curseurMarge.Rendre() end
            yy = yy + 32
            contenu.caseTousNiveaux.libelle:SetText(L.SETTING_GEAR_ALL_LEVELS)
            contenu.caseTousNiveaux.libelle:ClearAllPoints()
            contenu.caseTousNiveaux.libelle:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 6))
            contenu.caseTousNiveaux.libelle:Show()
            contenu.caseTousNiveaux:ClearAllPoints()
            contenu.caseTousNiveaux:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            contenu.caseTousNiveaux:SetChecked(tous)
            contenu.caseTousNiveaux:Show()
            contenu.dernierReglage = contenu.caseTousNiveaux
            yy = yy + 32
        end
    end
    contenu:SetHeight(math.max(yy + 20, 1))
end

local function RendreReglages(contenu)
    CacherLignesAuDela(contenu, 1)

    if not contenu.caseNonApprises then
        -- Section "Affichage" : un titre, puis les cases au premier retrait,
        -- comme toutes les sections des autres pages.
        local titreAffichage = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titreAffichage:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, 0)
        titreAffichage:SetText(L.SETTING_DISPLAY)
        contenu.titreAffichage = titreAffichage
        local case = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
        case:SetSize(24, 24)
        case:SetPoint("TOPLEFT", titreAffichage, "BOTTOMLEFT", RETRAIT_PAR_NIVEAU - 4, -6)
        local libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        libelle:SetPoint("LEFT", case, "RIGHT", 2, 1)
        libelle:SetJustifyH("LEFT")
        libelle:SetText(L.SETTING_SHOW_UNLEARNED)
        -- Le libelle fait partie de la case : cliquer dessus coche aussi.
        case:SetHitRectInsets(0, -240, 0, 0)
        case:SetScript("OnClick", function(self)
            NS.base.Reglages().afficherNonApprises = self:GetChecked() and true or false
            NS.Dire(self:GetChecked() and L.SETTING_SHOW_UNLEARNED_ON or L.SETTING_SHOW_UNLEARNED_OFF)
        end)
        contenu.caseNonApprises = case
        contenu.libelleNonApprises = libelle
    end

    contenu.titreAffichage:Show()
    StyleDeTitre(contenu.titreAffichage)
    contenu.caseNonApprises:SetChecked(NS.base.Reglages().afficherNonApprises and true or false)
    contenu.caseNonApprises:Show()
    contenu.libelleNonApprises:Show()
    contenu.titreAffichage:Show()

    -- Didacticiel guide : desactive par defaut, il s'active ici.
    if not contenu.caseGuide then
        local case = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
        case:SetSize(24, 24)
        case:SetPoint("TOPLEFT", contenu.caseNonApprises, "BOTTOMLEFT", 0, -6)
        local libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        libelle:SetPoint("LEFT", case, "RIGHT", 2, 1)
        libelle:SetJustifyH("LEFT")
        libelle:SetText(L.SETTING_GUIDE)
        case:SetHitRectInsets(0, -240, 0, 0)
        case:SetScript("OnClick", function(self)
            if NS.aide then NS.aide.PoserGuide(self:GetChecked() and true or false) end
            ecran.Montrer("reglages")
        end)
        contenu.caseGuide = case
        contenu.libelleGuide = libelle

        -- Infobulles des objets et assistant de banque et de courrier :
        -- actifs par defaut, ils se coupent ici.
        local function Case(precedente, libelleTexte, cle)
            local c = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
            c:SetSize(24, 24)
            c:SetPoint("TOPLEFT", precedente, "BOTTOMLEFT", 0, -6)
            local l = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l:SetPoint("LEFT", c, "RIGHT", 2, 1)
            l:SetJustifyH("LEFT")
            l:SetText(libelleTexte)
            c:SetHitRectInsets(0, -260, 0, 0)
            c:SetScript("OnClick", function(self)
                NS.base.ReglagesGeneraux()[cle] = self:GetChecked() and true or false
                if NS.courrier then NS.courrier.Actualiser() end
            end)
            c.libelle = l
            c.cle = cle
            return c
        end
        contenu.caseInfobulles = Case(case, L.SETTING_TOOLTIPS, "infobulles")
        contenu.caseAssistant = Case(contenu.caseInfobulles, L.SETTING_ASSIST, "assistant")
        contenu.caseSuivi = Case(contenu.caseAssistant, L.SETTING_TRACK, "suiviRecolte")
        -- Ancrer le suivi : il ne bouge plus, sauf en mode Edition du jeu.
        contenu.casePermanent = Case(contenu.caseSuivi, L.SETTING_TRACK_ALWAYS, "suiviPermanent")
        contenu.casePermanent:HookScript("OnClick", function(self)
            if self:GetChecked() and NS.suivi then NS.suivi.Montrer() end
        end)
        contenu.caseAncre = Case(contenu.casePermanent, L.SETTING_TRACK_LOCK, "ancreSuivi")
        contenu.caseAncre:SetScript("OnClick", function(self)
            if NS.suite and NS.suite.PoserAncre then NS.suite.PoserAncre("CraftCoreSuivi", self:GetChecked() and true or false) end
        end)

        -- Fond de la fenetre : deux boutons, celui en place est grise.
        local libelleFond = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        libelleFond:SetPoint("TOPLEFT", contenu.caseAncre, "BOTTOMLEFT", 4, -10)
        libelleFond:SetText(L.SETTING_BACKGROUND)
        contenu.libelleFond = libelleFond

        -- Fond des petites fenetres de suivi (commun a la suite).
        local libelleFondSuivis = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        libelleFondSuivis:SetPoint("TOPLEFT", libelleFond, "BOTTOMLEFT", 0, -20)
        libelleFondSuivis:SetText(L.SETTING_TRACK_BG)
        contenu.libelleFondSuivis = libelleFondSuivis

        local titre = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        -- Ancre a la derniere ligne au-dessus (plus de calcul de position a
        -- refaire a chaque option ajoutee).
        titre:SetPoint("TOPLEFT", libelleFondSuivis, "BOTTOMLEFT", -RETRAIT_PAR_NIVEAU, -(14 + ESPACE_SECTION))
        titre:SetJustifyH("LEFT")
        contenu.titreTutos = titre
    end
    local guide = NS.aide and NS.aide.GuideActif() or false
    contenu.caseGuide:SetChecked(guide)
    contenu.caseGuide:Show()
    contenu.libelleGuide:Show()
    local generaux = NS.base.ReglagesGeneraux()
    if generaux.suiviRecolte == nil then generaux.suiviRecolte = true end
    for _, c in ipairs({ contenu.caseInfobulles, contenu.caseAssistant, contenu.caseSuivi, contenu.casePermanent }) do
        c:SetChecked(generaux[c.cle] and true or false)
        c:Show()
        c.libelle:Show()
    end
    contenu.caseAncre:SetChecked(NS.suite and NS.suite.Ancree and NS.suite.Ancree("CraftCoreSuivi") or false)
    contenu.caseAncre:Show()
    contenu.caseAncre.libelle:Show()
    contenu.libelleFond:Show()
    -- Les deux fonds : la liste deroulante commune de la suite.
    local S = _G.CoreSuite
    if S and S.ListeDeroulante then
        if not contenu.listeFond then
            contenu.listeFond = S.ListeDeroulante(contenu, function() return NS.charte.OptionsDeFond() end,
                function() return NS.charte.FondComplet() end, function(v) NS.charte.PoserFondComplet(v) end,
                function() ecran.Montrer("reglages") end)
            contenu.listeFond:SetPoint("LEFT", contenu.libelleFond, "RIGHT", 10, 0)
            contenu.listeFondSuivis = S.ListeDeroulante(contenu, { { "gris", L.SETTING_BG_GREY }, { "parchemin", L.SETTING_BG_PARCHMENT } },
                function() return NS.charte.FondDesSuivis and NS.charte.FondDesSuivis() or "gris" end,
                function(v) if NS.charte.PoserFondDesSuivis then NS.charte.PoserFondDesSuivis(v) end end,
                function() ecran.Montrer("reglages") end)
            contenu.listeFondSuivis:SetPoint("LEFT", contenu.libelleFondSuivis, "RIGHT", 10, 0)
            -- Le panneau du menu de gauche, commun a la suite.
            contenu.libellePanneau = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.listePanneau = S.ListeDeroulante(contenu, function() return S.OptionsPanneau() end,
                function() return S.PanneauChoisi() end, function(v) S.PoserPanneau(v) end,
                function() ecran.Montrer("reglages") end)
            -- Parametrage de l'interface : un titre, et la case du reglage par defaut.
            contenu.titreInterface = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            contenu.caseDefaut = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
            contenu.caseDefaut:SetSize(24, 24)
            contenu.caseDefaut.libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.caseDefaut:SetScript("OnClick", function(self)
                S.PoserParDefaut(self:GetChecked() and true or false)
                ecran.Montrer("reglages")
            end)
            -- Fenetres effacees quand on se deplace (jamais en vol).
            contenu.caseFondu = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
            contenu.caseFondu:SetSize(24, 24)
            contenu.caseFondu.libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.caseFondu:SetScript("OnClick", function(self)
                if S.PoserFonduEnMarche then S.PoserFonduEnMarche(self:GetChecked() and true or false) end
            end)
            -- Compositions : fond, fond des suivis et panneau, enregistres ensemble.
            contenu.libelleCompo = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.listeCompo = S.ListeDeroulante(contenu, function() return S.OptionsComposition() end,
                function() return S.CompositionChoisie() end, function(v) S.AppliquerComposition(v) end,
                function() ecran.Montrer("reglages") end)
            contenu.libelleSauver = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.sauverCompo = CreateFrame("Button", nil, contenu, "UIPanelButtonTemplate")
            contenu.sauverCompo:SetHeight(24)
            contenu.sauverCompo:SetScript("OnClick", function() S.SauverComposition() ecran.Montrer("reglages") end)
        end
        -- Apparence de toute la suite (jeu d'origine ou moderne), hors du
        -- parametrage par defaut : elle se choisit toujours.
        if not contenu.listeHabillage and S.OptionsHabillage then
            contenu.libelleHabillage = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.listeHabillage = S.ListeDeroulante(contenu, function() return S.OptionsHabillage() end,
                function() return S.Habillage() end, function(v) S.PoserHabillage(v) end,
                function() ecran.Montrer("reglages") end)
        end
        if contenu.listeHabillage then
            local fr = S.Langue and S.Langue() == "frFR"
            contenu.libelleHabillage:SetText(fr and "Apparence (recharge l'interface)" or "Look (reloads the interface)")
            contenu.libelleHabillage:Show()
            contenu.listeHabillage:Show()
            contenu.listeHabillage.Rendre()
        end
        -- Apparence moderne : son theme (pose tout de suite), puis la couleur
        -- des bordures en reglage fin.
        if not contenu.listeTheme and S.OptionsTheme then
            contenu.libelleTheme = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.listeTheme = S.ListeDeroulante(contenu, function() return S.OptionsTheme() end,
                function() return S.ThemeChoisi() end, function(v) S.PoserThemeModerne(v) end,
                function() ecran.Montrer("reglages") end)
        end
        if contenu.listeTheme then
            local moderne = S.UI and S.UI.EstModerne and S.UI.EstModerne()
            local fr = S.Langue and S.Langue() == "frFR"
            contenu.libelleTheme:SetText(fr and "Thème" or "Theme")
            contenu.libelleTheme:SetShown(moderne)
            contenu.listeTheme:SetShown(moderne)
            if moderne then contenu.listeTheme.Rendre() end
        end
        -- Apparence moderne : la couleur des bordures, au choix.
        if not contenu.listeBordure and S.OptionsCouleurBordure then
            contenu.libelleBordure = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            contenu.listeBordure = S.ListeDeroulante(contenu, function() return S.OptionsCouleurBordure() end,
                function() return S.CouleurBordureChoisie() end, function(v) S.PoserCouleurBordure(v) end,
                function() ecran.Montrer("reglages") end)
        end
        if contenu.listeBordure then
            local moderne = S.UI and S.UI.EstModerne and S.UI.EstModerne()
            local fr = S.Langue and S.Langue() == "frFR"
            contenu.libelleBordure:SetText(fr and "Couleur des bordures" or "Border colour")
            contenu.libelleBordure:SetShown(moderne)
            contenu.listeBordure:SetShown(moderne)
            if moderne then contenu.listeBordure.Rendre() end
        end
        contenu.listeFond:Show()
        contenu.listeFondSuivis:Show()
        contenu.listeFond.Rendre()
        contenu.listeFondSuivis.Rendre()
        if contenu.caseDefaut then
            local fr = S.Langue and S.Langue() == "frFR"
            contenu.titreInterface:SetText(fr and "Paramétrage de l'interface" or "Interface setup")
            contenu.titreInterface:Show()
            StyleDeTitre(contenu.titreInterface)
            contenu.caseDefaut.libelle:SetText(fr and "Paramétrage par défaut" or "Default setup")
            contenu.caseDefaut:SetChecked(S.ParDefaut())
            contenu.caseDefaut:Show()
            contenu.caseDefaut.libelle:Show()
            contenu.caseFondu.libelle:SetText(fr and "Effacer les fenêtres quand je me déplace (jamais en vol)" or "Fade windows while I move (never in flight)")
            contenu.caseFondu:SetChecked(not S.FonduEnMarche or S.FonduEnMarche())
            contenu.caseFondu:Show()
            contenu.caseFondu.libelle:Show()
        end
        if contenu.listeCompo then
            local fr = S.Langue and S.Langue() == "frFR"
            contenu.libelleCompo:SetText(fr and "Composition" or "Setup")
            contenu.libelleSauver:SetText(fr and "Fond et panneau actuels" or "Current background and panel")
            contenu.sauverCompo:SetText(fr and "Sauvegarder la configuration" or "Save the setup")
            contenu.sauverCompo:SetWidth((contenu.sauverCompo:GetTextWidth() or 180) + 28)
            for _, x in ipairs({ contenu.libelleCompo, contenu.listeCompo, contenu.libelleSauver, contenu.sauverCompo }) do x:Show() end
            contenu.listeCompo.Rendre()
        end
        if contenu.listePanneau then
            contenu.libellePanneau:SetText((S.Langue and S.Langue() == "frFR") and "Panneau du menu" or "Menu panel")
            contenu.libellePanneau:Show()
            contenu.listePanneau:Show()
            contenu.listePanneau.Rendre()
        end
        -- Parametrage par defaut : les choix sont grises ; decoche, ils s'ouvrent.
        local libre = not (S.ParDefaut and S.ParDefaut())
        for _, li in ipairs({ contenu.listeFond, contenu.listeFondSuivis, contenu.listePanneau, contenu.listeCompo }) do
            if li and S.ActiverListe then S.ActiverListe(li, libre) end
        end
        if contenu.sauverCompo then contenu.sauverCompo:SetEnabled(libre) end
        for _, l in ipairs({ contenu.libelleFond, contenu.libelleFondSuivis, contenu.libellePanneau, contenu.libelleCompo, contenu.libelleSauver }) do
            if l then l:SetAlpha(libre and 1 or 0.5) end
        end
        -- Apparence moderne : le fond de la fenetre et le panneau du menu
        -- viennent du theme ; leurs choix sont grises (ils reviennent avec
        -- l'apparence du jeu).
        if S.UI and S.UI.EstModerne and S.UI.EstModerne() then
            for _, pr in ipairs({ { contenu.listeFond, contenu.libelleFond }, { contenu.listePanneau, contenu.libellePanneau } }) do
                if pr[1] and S.ActiverListe then S.ActiverListe(pr[1], false) end
                if pr[2] then pr[2]:SetAlpha(0.5) end
            end
        end
    else
    local fondActuel = NS.charte.Fond()
    local precedentFond
    for _, choix in ipairs({ { "noir", L.SETTING_BG_DARK }, { "parchemin", L.SETTING_BG_PARCHMENT } }) do
        local valeur = choix[1]
        local b = BoutonAction(contenu, "fond:" .. valeur, choix[2])
        b:ClearAllPoints()
        if precedentFond then
            b:SetPoint("LEFT", precedentFond, "RIGHT", 6, 0)
        else
            b:SetPoint("LEFT", contenu.libelleFond, "RIGHT", 10, 0)
        end
        b:SetEnabled(fondActuel ~= valeur)
        b:SetScript("OnClick", function()
            NS.charte.PoserFond(valeur)
            ecran.Montrer("reglages")
        end)
        b:Show()
        precedentFond = b
    end
    contenu.libelleFondSuivis:Show()
    local fondSuivis = NS.charte.FondDesSuivis and NS.charte.FondDesSuivis() or "gris"
    local precedentSuivis
    for _, choix in ipairs({ { "gris", L.SETTING_BG_GREY }, { "parchemin", L.SETTING_BG_PARCHMENT },
        { "illustre", L.SETTING_BG_ILLUSTRATED } }) do
        local valeur = choix[1]
        local b = BoutonAction(contenu, "fondSuivis:" .. valeur, choix[2])
        b:ClearAllPoints()
        if precedentSuivis then
            b:SetPoint("LEFT", precedentSuivis, "RIGHT", 6, 0)
        else
            b:SetPoint("LEFT", contenu.libelleFondSuivis, "RIGHT", 10, 0)
        end
        b:SetEnabled(fondSuivis ~= valeur)
        b:SetScript("OnClick", function()
            if NS.charte.PoserFondDesSuivis then NS.charte.PoserFondDesSuivis(valeur) end
            ecran.Montrer("reglages")
        end)
        b:Show()
        precedentSuivis = b
    end
    end
    -- Mise en page : les textes a gauche, les cases et les listes calees au
    -- bord droit, a la meme hauteur que leur texte.
    do
        local largeur = (contenu:GetWidth() or 700)
        local yy = 0
        contenu.titreAffichage:ClearAllPoints()
        contenu.titreAffichage:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, 0)
        yy = yy + 40
        local paires = {
            { contenu.caseNonApprises, contenu.libelleNonApprises }, { contenu.caseGuide, contenu.libelleGuide },
            { contenu.caseInfobulles, contenu.caseInfobulles.libelle }, { contenu.caseAssistant, contenu.caseAssistant.libelle },
            { contenu.caseSuivi, contenu.caseSuivi.libelle }, { contenu.casePermanent, contenu.casePermanent.libelle },
            { contenu.caseAncre, contenu.caseAncre.libelle },
        }
        for _, pr in ipairs(paires) do
            local c, l = pr[1], pr[2]
            c:ClearAllPoints()
            c:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 6))
            l:SetWidth(math.max(200, largeur - RETRAIT_PAR_NIVEAU - 60))
            -- Le texte fait partie de la case : cliquer dessus coche aussi.
            c:SetHitRectInsets(-(largeur - RETRAIT_PAR_NIVEAU - 40), 0, 0, 0)
            yy = yy + 30
        end
        if contenu.titreInterface then
            contenu.titreInterface:ClearAllPoints()
            contenu.titreInterface:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, -(yy + 18))
            yy = yy + 18 + 40
            contenu.caseDefaut:ClearAllPoints()
            contenu.caseDefaut:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            contenu.caseDefaut.libelle:ClearAllPoints()
            contenu.caseDefaut.libelle:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 6))
            contenu.caseDefaut:SetHitRectInsets(-(largeur - RETRAIT_PAR_NIVEAU - 40), 0, 0, 0)
            yy = yy + 32
            contenu.caseFondu:ClearAllPoints()
            contenu.caseFondu:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            contenu.caseFondu.libelle:ClearAllPoints()
            contenu.caseFondu.libelle:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 6))
            contenu.caseFondu:SetHitRectInsets(-(largeur - RETRAIT_PAR_NIVEAU - 40), 0, 0, 0)
            yy = yy + 32
        end
        for _, pr in ipairs({ { contenu.libelleFond, contenu.listeFond }, { contenu.libelleFondSuivis, contenu.listeFondSuivis },
            { contenu.libellePanneau, contenu.listePanneau }, { contenu.libelleCompo, contenu.listeCompo },
            { contenu.libelleSauver, contenu.sauverCompo }, { contenu.libelleHabillage, contenu.listeHabillage },
            { (contenu.listeTheme and contenu.listeTheme:IsShown()) and contenu.libelleTheme or nil, contenu.listeTheme },
            { (contenu.listeBordure and contenu.listeBordure:IsShown()) and contenu.libelleBordure or nil, contenu.listeBordure } }) do
          if pr[1] then
            pr[1]:ClearAllPoints()
            pr[1]:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT_PAR_NIVEAU, -(yy + 7))
            if pr[2] then
                pr[2]:ClearAllPoints()
                pr[2]:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -10, -yy)
            end
            yy = yy + 32
          end
        end
    end
    -- Les didacticiels ne sont plus dans cette page (ils iront ailleurs).
    contenu.titreTutos:Hide()
    if contenu.titreTutos.filet then contenu.titreTutos.filet:Hide() end
    local precedent = (contenu.listeBordure and contenu.listeBordure:IsShown() and contenu.listeBordure)
        or (contenu.listeTheme and contenu.listeTheme:IsShown() and contenu.listeTheme) or contenu.listeHabillage or contenu.sauverCompo or contenu.listeFondSuivis or contenu.libelleFondSuivis
    local hauteur = 600
    -- Hauteur reelle quand le jeu la connait : le bas du dernier bloc.
    local haut, bas = contenu:GetTop(), precedent and precedent.GetBottom and precedent:GetBottom()
    if haut and bas and haut > bas then hauteur = haut - bas + 12 end
    contenu:SetHeight(hauteur)
end

-- Page des caisses. Ce que le client dit, rien de plus : la liste des packs
-- acceptes et, pour chacun, ce que vous possedez. Aucun remplissage n'est
-- montre car ce client ne le donne jamais.
-- Un objet retrouve par son nom aupres du jeu (seulement s'il est connu du
-- client) : sert a montrer l'icone d'un composant que personne n'a.
local function ObjetParNom(nom)
    if type(nom) ~= "string" or nom == "" then return nil end
    local lecture = NS.Lecture("C_Item.GetItemInfo") or NS.Lecture("GetItemInfo")
    if not lecture then return nil end
    -- Le libelle d'un pack est au pluriel ("peaux legeres traitees") : on
    -- essaie aussi la forme au singulier, avec une majuscule, comme le jeu.
    local singulier = {}
    for mot in string.gmatch(nom, "[^%s]+") do
        mot = string.gsub(mot, "aux$", "au")
        mot = string.gsub(mot, "([^s])s$", "%1")
        table.insert(singulier, mot)
    end
    local essai2 = table.concat(singulier, " ")
    for _, essai in ipairs({ nom, essai2, (string.gsub(essai2, "^%l", string.upper)) }) do
        local ok, _, lien = pcall(lecture, essai)
        if ok and type(lien) == "string" then
            local id = tonumber(string.match(lien, "item:(%d+)"))
            if id and NS.caisses.RetenirNom then NS.caisses.RetenirNom(nom, id) end
            return id
        end
    end
    return nil
end

-- Tous les personnages du meme camp qui detiennent un objet, proprietaire de
-- la caisse compris s'il en a, du plus fourni au moins fourni.
local function DetenteursDe(objet, proprietaire)
    local liste = NS.inventaire.Detenteurs(objet, NS.base.FicheAffichee())
    for _, d in ipairs(liste) do
        if d.cle == proprietaire then d.nom = d.nom .. " *" end
    end
    return liste
end

local function RendreCaisses(contenu)
    CacherLignesAuDela(contenu, 1)
    ecran.deplie = ecran.deplie or {}
    local index, y = 0, 0

    if not NS.caisses or not NS.caisses.Relever then
        PoserMessage(contenu, L.PAGE_SOON, 0)
        contenu:SetHeight(60)
        return
    end

    NS.caisses.Relever()
    local cle = NS.base.CleAffichee()
    local nomDe = function(c) return NS.inventaire.NomCourt(c) end

    -- Les caisses du personnage affiche ; celles des autres seulement si on
    -- le demande, chacune avec le nom de qui la detient.
    if not contenu.caseCaissesAutres then
        local case = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
        case:SetSize(20, 20)
        case.libelle = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        case.libelle:SetPoint("LEFT", case, "RIGHT", 1, 1)
        case:SetHitRectInsets(0, -260, 0, 0)
        case:SetScript("OnClick", function(self)
            ecran.caissesDesAutres = self:GetChecked() and true or nil
            ecran.Montrer(ecran.page)
        end)
        contenu.caseCaissesAutres = case
    end
    local case = contenu.caseCaissesAutres
    local ailleurs = NS.caisses.ChezLesAutres(cle)
    local titreC
    index, y, titreC = EnTeteDePage(contenu, index, y, L.NAV_CRATES)
    case.libelle:SetText(string.format(L.CRATES_SHOW_OTHERS, ailleurs))
    case:ClearAllPoints()
    if titreC then
        case:SetPoint("RIGHT", titreC, "RIGHT", -((case.libelle:GetStringWidth() or 100) + 8), 2)
    else
        case:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    end
    case:SetChecked(ecran.caissesDesAutres == true)
    case:SetEnabled(ailleurs > 0 or ecran.caissesDesAutres == true)
    case:Show() case.libelle:Show()
    y = y + 4

    local liste = NS.caisses.Connues(cle, ecran.caissesDesAutres == true)

    if #liste == 0 then
        PoserMessage(contenu, string.format(L.CRATES_NONE_FOR, nomDe(cle)), y)
        contenu:SetHeight(y + 60)
        return
    end

    for _, caisse in ipairs(liste) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)

        local cleDepli = "caisse:" .. tostring(caisse.id) .. ":" .. tostring(caisse.proprietaire)
        local deplie = ecran.deplie[cleDepli] == true
        PoserLigne(ligne, 0, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)

        local info = NS.objets.Info(caisse.id)
        if info and info.icone then ligne.icone:SetTexture(info.icone) ligne.icone:Show()
        else ligne.icone:Hide() end
        local titre = caisse.nom or tostring(caisse.id)
        if (caisse.exemplaires or 1) > 1 then
            titre = titre .. "  x" .. caisse.exemplaires
        end
        if caisse.proprietaire ~= cle then
            titre = titre .. "   |cff8c8c8c" .. string.format(L.CRATES_AT, nomDe(caisse.proprietaire)) .. "|r"
        end
        ligne.nom:SetText(titre)
        if NS.objets.CouleurDuNom then ligne.nom:SetTextColor(NS.objets.CouleurDuNom(caisse.id)) end
        ligne.nom:SetFontObject("GameFontHighlightSmall")
        ligne.sacs:SetText("")
        ligne.banque:SetText("")

        local prets, total = NS.caisses.PacksPrets(caisse)
        ligne.total:SetText(string.format(L.CRATES_READY, prets, total))
        ligne.total:SetTextColor(prets > 0 and 0.31 or 0.55, prets > 0 and 0.82 or 0.55, prets > 0 and 0.41 or 0.55)
        ligne:Show()
        y = y + HAUTEUR_LIGNE

        if deplie then
            local etat = NS.caisses.Etat(caisse)
            if #etat == 0 then
                index = index + 1
                local vide = LigneDeTableau(contenu, index)
                vide:ClearAllPoints()
                vide:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                vide:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(vide, RETRAIT_PAR_NIVEAU, false, false, nil)
                vide.icone:Hide()
                vide.nom:SetFontObject("GameFontDisableSmall")
                vide.nom:SetText(L.CRATES_NO_LIST)
                vide.sacs:SetText("") vide.banque:SetText("") vide.total:SetText("")
                vide:Show()
                y = y + HAUTEUR_LIGNE
            end
            for _, pack in ipairs(etat) do
                index = index + 1
                local l2 = LigneDeTableau(contenu, index)
                l2:ClearAllPoints()
                l2:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                l2:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(l2, RETRAIT_PAR_NIVEAU, false, false, nil)

                -- Objet du pack : reconnu dans les stocks, sinon retrouve par son
                -- nom aupres du jeu (pour l'icone, meme si personne n'en a).
                local objet = pack.objet or ObjetParNom(pack.libelle)
                local ic = objet and NS.Appeler(NS.jeu.iconeObjet, objet)
                l2.icone:SetTexture(ic or "Interface\\Icons\\INV_Misc_QuestionMark")
                l2.icone:Show()
                l2.nom:SetText(pack.libelle)
                l2.sacs:SetText("")
                l2.banque:SetText("")

                -- Qui en a, nom par nom, sur tout le compte : quel que soit le
                -- personnage affiche.
                local detenteurs = objet and DetenteursDe(objet, caisse.proprietaire) or {}
                -- Etat court, sur une ligne : le detail complet est au survol.
                if not pack.objet then
                    Marquer(l2, false, "GameFontHighlightSmall", objet)
                    l2.total:SetText(string.format(L.CRATES_HAVE, 0, pack.requis or 0))
                else
                    Marquer(l2, pack.manque == 0, "GameFontHighlightSmall", pack.objet)
                    local texte = string.format(L.CRATES_HAVE, pack.possede, pack.requis)
                    if pack.manque > 0 and #detenteurs > 0 then
                        local noms = {}
                        for rang, d in ipairs(detenteurs) do
                            if rang > 2 then table.insert(noms, "+" .. (#detenteurs - 2)) break end
                            table.insert(noms, d.nom .. " " .. d.total)
                        end
                        texte = texte .. "  |cff8c8c8c(" .. table.concat(noms, ", ") .. ")|r"
                    end
                    l2.total:SetText(texte)
                end
                l2.total:SetWordWrap(false)
                local objetSurvol = objet
                l2:EnableMouse(true)
                l2:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if objetSurvol and GameTooltip.SetItemByID then
                        pcall(GameTooltip.SetItemByID, GameTooltip, objetSurvol)
                    else
                        GameTooltip:SetText(pack.libelle)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L.CRATES_WHO_HAS, 1, 0.82, 0)
                    if #detenteurs == 0 then
                        GameTooltip:AddLine("  " .. L.CRATES_NOBODY, 0.6, 0.6, 0.6)
                    end
                    for _, d in ipairs(detenteurs) do
                        GameTooltip:AddDoubleLine("  " .. d.nom, string.format(L.TIP_LINE_SHORT, d.sacs, d.banque), 1, 1, 1, 1, 1, 1)
                    end
                    GameTooltip:Show()
                end)
                l2:SetScript("OnLeave", function() GameTooltip:Hide() end)
                l2:Show()
                y = y + HAUTEUR_LIGNE
            end
            y = y + 6
        end
    end

    index = index + 1
    local avis = LigneDeTableau(contenu, index)
    avis:ClearAllPoints()
    avis:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -(y + 6))
    avis:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -(y + 6))
    PoserLigne(avis, 0, false, false, nil)
    avis.icone:Hide()
    avis.nom:SetFontObject("GameFontDisableSmall")
    avis.nom:SetText(L.CRATES_NO_FILL)
    avis.sacs:SetText("") avis.banque:SetText("") avis.total:SetText("")
    avis:Show()
    y = y + HAUTEUR_LIGNE + 6

    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end

-- Page de l'approvisionnement : ce qu'il reste a obtenir, et par quel moyen.
-- A recuperer : la liste de courses de tous les projets et des fabrications
-- rapides reunis, en bas de Mes projets. Or : a rapatrier d'un autre
-- personnage ; rouge : personne du compte n'en a.
local function RendreBlocARecuperer(contenu, index, y, filtre)
    if not NS.approvisionnement then return index, y end
    local liste = NS.approvisionnement.Liste(filtre)
    local C = NS.inventaire.COULEURS
    index, y = TitreDeSection(contenu, index, y, string.format(filtre == "progressions" and L.SUPPLY_TITLE_PROG or L.SUPPLY_TITLE, #liste))
    if #liste == 0 then
        y = Paragraphe(contenu, y, L.SUPPLY_NONE, "GameFontDisableSmall")
        return index, y
    end
    local total, estime, totalHV, dernierHV
    for _, ligne in ipairs(liste) do
        index = index + 1
        local l = LigneDeTableau(contenu, index)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, nil)

        local info = NS.objets.Info(ligne.objet)
        if info and info.icone then l.icone:SetTexture(info.icone) l.icone:Show() else l.icone:Hide() end
        l.nom:SetText(NS.inventaire.NomDObjet(ligne.objet))
        if NS.objets.CouleurDuNom then l.nom:SetTextColor(NS.objets.CouleurDuNom(ligne.objet)) end
        l.sacs:SetText("")
        l.banque:SetText("")

        -- `ailleurs` est ce qu'il faut rapatrier, `manque` ce que personne
        -- du compte ne detient : les deux peuvent se cumuler.
        if ligne.ailleurs > 0 and ligne.manque > 0 then
            l.total:SetText(string.format(L.SUPPLY_FETCH, ligne.ailleurs) .. ", "
                .. string.format(L.SUPPLY_GET, ligne.manque))
            l.total:SetTextColor(unpack(C.manque))
        elseif ligne.ailleurs > 0 then
            l.total:SetText(string.format(L.SUPPLY_FETCH, ligne.ailleurs))
            l.total:SetTextColor(unpack(C.ailleurs))
        else
            l.total:SetText(string.format(L.SUPPLY_GET, ligne.manque))
            l.total:SetTextColor(unpack(C.manque))
        end
        -- Vendu par un marchand : le prix de ce qui manque, et le total.
        local m = NS.marchands
        local achetable = m and ligne.manque > 0 and m.Achetable(ligne.objet)
        if achetable then
            local prix, exact = m.Prix(ligne.objet)
            if prix then
                local cout = prix * ligne.manque
                total = (total or 0) + cout
                if not exact then estime = true end
                l.total:SetText(l.total:GetText() .. "  |cffffffff" .. (exact and "" or "~ ") .. m.Monnaie(cout) .. "|r")
            end
        elseif ligne.manque > 0 and NS.encheres then
            -- Sinon, le prix moyen du dernier releve a l'hotel des ventes.
            local prix, quand = NS.encheres.Prix(ligne.objet, ligne.manque)
            if prix then
                totalHV = (totalHV or 0) + prix * ligne.manque
                if not dernierHV or quand > dernierHV then dernierHV = quand end
                l.total:SetText(l.total:GetText() .. "  |cffffffff" .. string.format(L.AH_ON_LINE, m.Monnaie(prix * ligne.manque)) .. "|r")
            end
        end

        -- Au survol : qui a quoi.
        local objetSurvol = ligne.objet
        l:EnableMouse(true)
        l:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, objetSurvol) end
            local ou = NS.inventaire.TexteOuEst(objetSurvol)
            if ou ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ou, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if ligne.recette and ligne.recetteApprise then
            local objet = ligne.objet
            PoserBoutonDeLigne(l, ligne.telQuel and L.SUPPLY_MAKE_IT or L.SUPPLY_GET_IT, function()
                NS.approvisionnement.BasculerMethode(objet)
                ecran.Montrer(ecran.page)
            end)
        elseif achetable and m.Localisable(ligne.objet) then
            local objet = ligne.objet
            PoserBoutonDeLigne(l, L.VENDOR_LOCATE, function() m.Guider(objet) end, nil, L.VENDOR_LOCATE_HELP)
        end

        l:Show()
        y = y + HAUTEUR_LIGNE
    end
    if total then
        y = y + 4
        y = Paragraphe(contenu, y, string.format(L.VENDOR_TOTAL, (estime and "~ " or "") .. NS.marchands.Monnaie(total)),
            "GameFontHighlightSmall")
        if estime then y = Paragraphe(contenu, y, L.VENDOR_ESTIMATE_NOTE, "GameFontDisableSmall") end
    end
    if totalHV then
        y = y + 4
        y = Paragraphe(contenu, y, string.format(L.AH_TOTAL, NS.marchands.Monnaie(totalHV), NS.encheres.DateDe(dernierHV)),
            "GameFontHighlightSmall")
    end
    return index, y
end

local function RendrePageAVenir(contenu)
    CacherLignesAuDela(contenu, 1)
    if contenu.caseNonApprises then
        contenu.caseNonApprises:Hide()
        contenu.libelleNonApprises:Hide()
    end
    PoserMessage(contenu, L.PAGE_SOON, 0)
    contenu:SetHeight(40)
end

-- Ou se trouve un objet : sacs et banque du personnage affiche, puis chacun
-- de ses autres personnages du meme camp. "sacs 3, banque 2, Thrall 6".
local function Repartition(objet)
    return NS.inventaire.TexteOuEst(objet)
end

-- Les autres personnages qui detiennent au moins un composant d'une recette.
local function DetenteursDesComposants(recette)
    local fiche = NS.base.FicheAffichee()
    local noms, vus = {}, {}
    if not fiche then return "" end
    for _, composant in ipairs(recette.composants or {}) do
        for _, d in ipairs(NS.inventaire.Detenteurs(composant.objet, fiche)) do
            if not d.estRef and not vus[d.nom] then vus[d.nom] = true table.insert(noms, d.nom) end
        end
    end
    return table.concat(noms, ", ")
end

-- Affiche les composants d'un noeud de decomposition, un retrait par niveau.
local function RendreNoeud(contenu, noeud, niveau, index, y)
    local inventaire = NS.inventaire
    for _, composant in ipairs(noeud.composants or {}) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        PoserLigne(ligne, niveau * RETRAIT_PAR_NIVEAU, false, false, nil)

        local icone = NS.jeu.iconeObjet and NS.Appeler(NS.jeu.iconeObjet, composant.objet)
        if icone then
            ligne.icone:SetTexture(icone)
            ligne.icone:Show()
        else
            ligne.icone:Hide()
        end

        Marquer(ligne, composant.manque <= 0, "GameFontHighlightSmall", composant.objet)
        ligne.nom:SetText(inventaire.NomDObjet(composant.objet))
        ligne.sacs:SetText("")
        ligne.banque:SetText("")

        local etat
        if composant.cycle then
            etat = L.COMP_CYCLE
        elseif composant.tropProfond then
            etat = L.COMP_TOO_DEEP
        elseif composant.manque <= 0 then
            -- Ce qu'il faut, puis ce qu'on a. Et si une partie dort chez un
            -- autre personnage, on le dit : elle ne sert a rien tant qu'elle
            -- n'est pas rapatriee.
            -- Combien il en faut, et qui les a : rien n'est plus utile
            -- qu'un total dont on ne sait pas ou il se trouve.
            etat = string.format(L.COMP_AVAILABLE, composant.besoin, Repartition(composant.objet))
        elseif composant.sous and not composant.sous.transformationIndisponible then
            etat = string.format(L.COMP_MISSING_CRAFTABLE_RUNS, composant.manque, composant.besoin,
                composant.sous.executions or composant.manque)
        elseif composant.sous then
            etat = string.format(L.COMP_MISSING, composant.manque, composant.besoin) .. ", " .. L.COMP_NOT_LEARNED
        else
            etat = string.format(L.COMP_MISSING, composant.manque, composant.besoin)
        end
        if composant.manque > 0 then
            local ou = Repartition(composant.objet)
            if ou ~= "" then etat = etat .. "  |cff8c8c8c(" .. ou .. ")|r" end
        end
        ligne.total:SetText(etat)
        ligne:Show()
        y = y + HAUTEUR_LIGNE

        -- Ce qui fabrique ce composant : ses propres composants, un cran
        -- plus loin (le nombre de fois est dans l'etat du composant).
        if composant.sous and not composant.sous.transformationIndisponible then
            index, y = RendreNoeud(contenu, composant.sous, niveau + 1, index, y)
        end
    end
    return index, y
end

-- Deux cases a cocher, pas de menu : le contenu d'un menu contextuel est
-- execute par le jeu hors de notre portee, donc hors de tout filet.
-- Patron repris du journal de donjon, le meme que dans les reglages.
local function CasesDeFiltre(contenu)
    if contenu.caseConnues then return contenu.caseConnues, contenu.caseNonConnues end

    local function CreerCase(libelle, largeurClic)
        local case = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
        case:SetSize(20, 20)
        local texte = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        texte:SetPoint("LEFT", case, "RIGHT", 1, 1)
        texte:SetJustifyH("LEFT")
        texte:SetText(libelle)
        -- Le libelle fait partie de la case : cliquer dessus coche aussi.
        case:SetHitRectInsets(0, -largeurClic, 0, 0)
        case.libelle = texte
        return case
    end

    contenu.caseConnues = CreerCase(L.FILTER_KNOWN_BOX, 110)
    contenu.caseNonConnues = CreerCase(L.FILTER_UNKNOWN_BOX, 130)
    return contenu.caseConnues, contenu.caseNonConnues
end

-- ---------------------------------------------------------------------------
-- Projets et fabrications rapides
-- ---------------------------------------------------------------------------

-- Champ de saisie pose dans la fenetre, jamais une boite du jeu : le contenu
-- d'une boite est execute par le jeu, hors de toute protection de notre cote.
-- Patron repris du journal de donjon et de la bibliotheque de reglages.
local function ChampDeSaisie(contenu)
    if contenu.champ then return contenu.champ end
    local champ = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate")
    champ:SetHeight(22)
    champ:SetAutoFocus(false)
    champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
    contenu.champ = champ
    return champ
end

-- Un bouton d'action, cree a la demande et reutilise.
-- Champ de recherche, distinct de celui qui sert a renommer : les deux peuvent
-- etre a l'ecran en meme temps.
local function ChampDeRecherche(contenu)
    if contenu.champRecherche then return contenu.champRecherche end
    local champ = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate")
    champ:SetHeight(22)
    champ:SetAutoFocus(false)
    champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    contenu.champRecherche = champ
    return champ
end

BoutonAction = function(contenu, cle, libelle)
    contenu.actions = contenu.actions or {}
    local bouton = contenu.actions[cle]
    if not bouton then
        bouton = CreateFrame("Button", nil, contenu, "UIPanelButtonTemplate")
        bouton:SetHeight(20)
        contenu.actions[cle] = bouton
    end
    bouton:SetText(libelle)
    bouton:SetWidth(math.max(90, bouton:GetTextWidth() + 24))
    return bouton
end

local function CacherActions(contenu, gardees)
    for cle, bouton in pairs(contenu.actions or {}) do
        if not (gardees and gardees[cle]) then bouton:Hide() end
    end
end

-- Dessine le contenu d'une liste, projet ou fabrications rapides.
local function RendreEntrees(contenu, cible, index, y, niveau)
    local catalogue = NS.recettes
    local entrees = NS.projets.Contenu(cible)
    local arbres = NS.projets.Calculer(cible)
    local parRecette = {}
    for rang, arbre in ipairs(arbres or {}) do
        parRecette[rang] = arbre
    end

    for rang, entree in ipairs(entrees) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)

        local recette = (CraftCoreDB.recettes or {})[tostring(entree.recette)]
        local cleDepli = tostring(cible) .. ":" .. tostring(entree.recette)
        local deplie = ecran.deplie[cleDepli] == true
        PoserLigne(ligne, niveau * RETRAIT_PAR_NIVEAU, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)

        local objetProduit = recette and recette.objetProduit
        local info = objetProduit and NS.objets.Info(objetProduit)
        local icone = info and info.icone
        if icone then ligne.icone:SetTexture(icone) ligne.icone:Show() else ligne.icone:Hide() end
        ligne.nom:SetText((info and info.nom) or (recette and recette.nom) or tostring(entree.recette))

        PoserQuantite(ligne, entree.quantite,
            function() NS.projets.ChangerQuantite(cible, entree.recette, -1) ecran.Montrer(ecran.page) end,
            function() NS.projets.ChangerQuantite(cible, entree.recette, 1) ecran.Montrer(ecran.page) end)
        -- Creer, directement depuis le projet : la quantite du projet.
        do
            PoserBoutonFabriquer(ligne, recette, entree.quantite)
        end

        local arbre = parRecette[rang]
        local manque = 0
        for _, composant in ipairs(arbre and arbre.composants or {}) do
            manque = manque + (composant.manque or 0)
        end
        local acquis = (arbre ~= nil and manque == 0)
        Marquer(ligne, acquis, "GameFontHighlightSmall", objetProduit)
        ligne.sacs:SetText("")
        ligne.banque:SetText("")
        ligne.total:SetText(acquis and L.RECIPES_CAN_CRAFT or
            (arbre and string.format(L.RECIPES_MISSING_SHORT, #(arbre.composants or {})) or ""))
        ligne:Show()
        y = y + HAUTEUR_LIGNE

        if deplie and arbre then
            index, y = RendreNoeud(contenu, arbre, niveau + 1, index, y)
        end
    end
    return index, y
end

-- En-tete d'un bloc de Mes projets (Fabrications rapides, un projet) : le
-- titre colle a son [+]/[-] (pas de place d'icone vide), la police des
-- titres de section, et le meme filet dessous. Rend la hauteur prise.
local function EnTeteDeBloc(ligne)
    ligne.icone:Hide()
    ligne.nom:ClearAllPoints()
    ligne.nom:SetPoint("LEFT", ligne.marqueur, "RIGHT", 6, 0)
    ligne.nom:SetPoint("RIGHT", ligne.total, "LEFT", -8, 0)
    ligne.nom.agrandir = false
    if NS.charte.Fond() == "parchemin" then
        PoliceDeTitre(ligne.nom)
        ligne.nom:SetTextColor(0.42, 0.18, 0.02)
        ligne.filet:SetColorTexture(0.42, 0.18, 0.02, 0.45)
    else
        ligne.nom:SetFontObject("GameFontNormal")
        ligne.nom:SetTextColor(1, 0.82, 0)
        PeindreFilet(ligne.filet, 1, 0.82, 0, 0.25)
    end
    ligne.filet:Show()
    ligne:SetHeight(HAUTEUR_LIGNE + 6)
    return HAUTEUR_LIGNE + 6 + 6
end

-- Une rangee de boutons d'action sous un bloc, qui revient a la ligne quand
-- la largeur est pleine. Rend le nouveau y.
local function RangeeDeBoutons(contenu, boutons, y, retrait)
    local largeurMax = (tonumber(contenu:GetWidth()) or 0) - 8
    if largeurMax < 200 then largeurMax = LARGEUR - LARGEUR_MENU - MARGE - ECART * 2 - 40 end
    local x = retrait
    for _, b in ipairs(boutons) do
        local largeur = b:GetWidth() or 120
        if x > retrait and x + largeur > largeurMax then
            x = retrait
            y = y + 26
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", x, -y)
        b:Show()
        x = x + largeur + 6
    end
    return y + 26
end

-- Fabrications rapides : un projet permanent, toujours en haut de Mes projets.
local function RendreBlocRapides(contenu, index, y, gardees)
    local entrees = NS.projets.Contenu("rapides") or {}
    index = index + 1
    local ligne = LigneDeTableau(contenu, index)
    ligne:ClearAllPoints()
    ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    local cleDepli = "projet:rapides"
    if ecran.deplie[cleDepli] == nil then ecran.deplie[cleDepli] = true end
    local deplie = ecran.deplie[cleDepli] == true
    PoserLigne(ligne, 0, true, deplie, function()
        ecran.deplie[cleDepli] = not deplie
        ecran.Montrer(ecran.page)
    end)
    local hauteur = EnTeteDeBloc(ligne)
    ligne.nom:SetText(L.NAV_QUICK)
    ligne.sacs:SetText("")
    ligne.banque:SetText("")
    ligne.total:SetText(#entrees > 0 and string.format(L.PROJECTS_PICK_COUNT, #entrees) or "")
    ligne.total:SetTextColor(0.55, 0.55, 0.55)
    ligne:Show()
    y = y + hauteur

    if not deplie then return index, y + 4 end
    if #entrees == 0 then
        y = Paragraphe(contenu, y, L.QUICK_NONE, "GameFontDisableSmall")
        return index, y + 4
    end
    index, y = RendreEntrees(contenu, "rapides", index, y, 1)

    y = y + 4
    local verser = BoutonAction(contenu, "verser", L.QUICK_TO_PROJECT)
    verser:SetScript("OnClick", function()
        local projet = NS.projets.Creer(nil)
        if not projet then return end
        local versees = NS.projets.VerserLesRapidesDans(projet.id)
        NS.projets.PoserDestination(projet.id)
        ecran.deplie["projet:" .. tostring(projet.id)] = true
        ecran.nommageEnCours = projet.id
        NS.Dire(string.format(L.QUICK_MOVED, versees, NS.projets.NomDe(projet)))
        ecran.Montrer("projets")
    end)
    verser:Show()
    local estDestination = NS.projets.Destination() == "rapides"
    local cibler = BoutonAction(contenu, "ciblerRapides",
        estDestination and L.PROJECTS_TARGET_ON or L.PROJECTS_TARGET)
    cibler:SetScript("OnClick", function()
        NS.projets.PoserDestination("rapides")
        ecran.Montrer("projets")
    end)
    cibler:SetEnabled(not estDestination)
    -- Suppression en deux temps, comme pour un projet : le bouton demande
    -- confirmation avant d'agir.
    local aConfirmer = (ecran.suppressionEnCours == "rapides")
    local supprimer = BoutonAction(contenu, "supprimerRapides",
        aConfirmer and L.PROJECTS_CONFIRM or L.PROJECTS_DELETE)
    supprimer:SetScript("OnClick", function()
        if ecran.suppressionEnCours == "rapides" then
            ecran.suppressionEnCours = nil
            NS.projets.ViderRapides()
        else
            ecran.suppressionEnCours = "rapides"
        end
        ecran.Montrer(ecran.page)
    end)
    supprimer:Show()
    y = RangeeDeBoutons(contenu, { verser, cibler, supprimer }, y, RETRAIT_PAR_NIVEAU)
    gardees.verser, gardees.ciblerRapides, gardees.supprimerRapides = true, true, true
    return index, y + 4
end

-- Qui, parmi les personnages du meme camp, connait chaque recette.
local function ConnaisseursDesRecettes()
    local par = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if NS.inventaire.MemeCamp(fiche) and type(fiche.recettesApprises) == "table" then
            local nom = NS.inventaire.NomCourt(fiche.cle)
            for id, apprise in pairs(fiche.recettesApprises) do
                if apprise then
                    par[id] = par[id] or {}
                    table.insert(par[id], nom)
                end
            end
        end
    end
    return par
end

-- Choix de recettes pour un projet : tout ce que vos personnages savent
-- fabriquer, range par metier. Un metier se deplie ; chaque recette dit qui la
-- connait et si elle est realisable, et un bouton l'ajoute au projet.
RendreChoixDeRecettes = function(contenu, idProjet, index, y)
    local catalogue = NS.recettes
    local connaisseurs = ConnaisseursDesRecettes()
    local parMetier, ordre = {}, {}
    for cle, recette in pairs(CraftCoreDB.recettes or {}) do
        local qui = connaisseurs[tostring(cle)]
        if qui and type(recette) == "table" then
            local ligneMetier = catalogue.MetierDe(recette) or 0
            if not parMetier[ligneMetier] then
                parMetier[ligneMetier] = {}
                table.insert(ordre, ligneMetier)
            end
            local fabricables = catalogue.CombienFabricables(recette)
            table.insert(parMetier[ligneMetier], { id = tonumber(cle) or cle, recette = recette,
                qui = qui, fabricables = fabricables })
        end
    end
    local function NomMetier(ligneMetier)
        if ligneMetier == 0 then return L.SLOT_OTHER end
        return catalogue.NomDuMetier(ligneMetier) or tostring(ligneMetier)
    end
    table.sort(ordre, function(a, b) return NomMetier(a) < NomMetier(b) end)

    y = Paragraphe(contenu, y, L.PROJECTS_PICK_HINT, "GameFontDisableSmall")
    if #ordre == 0 then
        y = Paragraphe(contenu, y, L.PROJECTS_PICK_NONE, "GameFontDisableSmall")
    end

    for _, ligneMetier in ipairs(ordre) do
        local liste = parMetier[ligneMetier]
        table.sort(liste, function(a, b)
            local fa, fb = (a.fabricables or 0) > 0, (b.fabricables or 0) > 0
            if fa ~= fb then return fa end
            return (a.recette.nom or "") < (b.recette.nom or "")
        end)
        local cleDepli = "choix:" .. tostring(idProjet) .. ":" .. tostring(ligneMetier)
        local deplie = ecran.deplie[cleDepli] == true
        index = index + 1
        local titre = LigneDeTableau(contenu, index)
        titre:ClearAllPoints()
        titre:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        titre:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        PoserLigne(titre, RETRAIT_PAR_NIVEAU, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)
        local icone = ICONES_METIERS[ligneMetier]
        if icone then titre.icone:SetTexture(icone) titre.icone:Show() else titre.icone:Hide() end
        titre.nom:SetFontObject("GameFontNormal")
        titre.nom:SetTextColor(1, 0.82, 0)
        titre.nom:SetText(NomMetier(ligneMetier))
        titre.sacs:SetText("") titre.banque:SetText("")
        titre.total:SetFontObject("GameFontDisableSmall") titre.total.pasExplication = true
        titre.total:SetText(string.format(L.PROJECTS_PICK_COUNT, #liste))
        titre:Show()
        y = y + HAUTEUR_LIGNE

        if deplie then
            for _, entree in ipairs(liste) do
                index = index + 1
                local l = LigneDeTableau(contenu, index)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(l, RETRAIT_PAR_NIVEAU * 2 + 18, false, false, nil)
                local objet = entree.recette.objetProduit
                local ic = objet and NS.Appeler(NS.jeu.iconeObjet, objet)
                if ic then l.icone:SetTexture(ic) l.icone:Show() else l.icone:Hide() end
                l.nom:SetFontObject("GameFontHighlightSmall")
                l.nom:SetText(entree.recette.nom or tostring(entree.id))
                if objet and NS.objets.CouleurDuNom then l.nom:SetTextColor(NS.objets.CouleurDuNom(objet)) end
                l.sacs:SetText("") l.banque:SetText("")
                local etat = table.concat(entree.qui, ", ")
                if (entree.fabricables or 0) > 0 then
                    etat = etat .. "   |cff4fd16a" .. string.format(L.READY_HERE, entree.fabricables) .. "|r"
                else
                    local manques = catalogue.Manques(entree.recette)
                    if manques and #manques > 0 then
                        etat = etat .. "   |cff8c8c8c" .. string.format(L.RECIPES_MISSING_SHORT, #manques) .. "|r"
                    end
                end
                l.total:SetFontObject("GameFontHighlightSmall")
                l.total:SetTextColor(1, 1, 1)
                l.total:SetText(etat)
                local id = entree.id
                PoserBoutonDeLigne(l, L.PROJECTS_ADD_ONE, function()
                    NS.projets.Ajouter(idProjet, id, 1)
                    NS.Dire(string.format(L.ADDED_TO, entree.recette.nom or tostring(id), NS.projets.NomDe(
                        (function() for _, p in ipairs(NS.projets.Tous(true)) do if p.id == idProjet then return p end end end)() or {})))
                    ecran.Montrer("projets")
                end)
                l:Show()
                y = y + HAUTEUR_LIGNE
            end
            y = y + 4
        end
    end
    return index, y + 6
end

-- Mes fabrications (progressions = nil) et Mes progressions (true) : la
-- meme page. Les projets tires d'un plan de progression vont dans la seconde,
-- avec les rangs vises ; les fabrications rapides et les projets nommes dans
-- la premiere.
local RendreRangsVises
local function RendreListeDeProjets(contenu, progressions)
    CacherLignesAuDela(contenu, 1)
    ecran.deplie = ecran.deplie or {}
    local index, y = 0, 0
    local gardees = {}
    if progressions then
        local titreG
        index, y, titreG = EnTeteDePage(contenu, index, y, L.NAV_PROGRESSIONS)
        local ouvrir = BoutonAction(contenu, "ouvrirProgression", L.PROGRESSIONS_OPEN)
        ouvrir:ClearAllPoints()
        if titreG then ouvrir:SetPoint("RIGHT", titreG, "RIGHT", -4, 2) else ouvrir:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y) end
        ouvrir:SetScript("OnClick", function() ecran.Montrer("progression") end)
        ouvrir:Show()
        gardees.ouvrirProgression = true
        y = y + 4
        y = Paragraphe(contenu, y, L.PROGRESSIONS_INTRO, "GameFontDisableSmall")
        y = y + ESPACE_SECTION - 6
        index, y = RendreRangsVises(contenu, index, y, gardees)
    else

    local titreP
    index, y, titreP = EnTeteDePage(contenu, index, y, L.NAV_PROJECTS)
    local nouveau = BoutonAction(contenu, "nouveau", L.PROJECTS_NEW)
    nouveau:ClearAllPoints()
    if titreP then nouveau:SetPoint("RIGHT", titreP, "RIGHT", -4, 2) else nouveau:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y) end
    nouveau:SetScript("OnClick", function()
        local projet = NS.projets.Creer(nil)
        if projet then
            -- Le nouveau projet devient la destination des ajouts : sinon il
            -- resterait vide sans qu'on sache comment le remplir.
            NS.projets.PoserDestination(projet.id)
            ecran.deplie["projet:" .. tostring(projet.id)] = true
            ecran.nommageEnCours = projet.id
            -- Et la liste des recettes s'ouvre aussitot sous lui.
            ecran.rechercheProjet = projet.id
        end
        ecran.Montrer("projets")
    end)
    nouveau:Show()
    gardees.nouveau = true
    y = y + 4
    -- Ce qui distingue les deux, dit une fois en haut de la page.
    y = Paragraphe(contenu, y, L.PROJECTS_INTRO, "GameFontDisableSmall")
    y = y + ESPACE_SECTION - 6

    index, y = RendreBlocRapides(contenu, index, y, gardees)
    end

    local liste = {}
    for _, projet in ipairs(NS.projets.Tous(true)) do
        if (NS.projets.EstDeProgression(projet) == true) == (progressions == true)
            and not (NS.commandes and NS.commandes.EstCommande(projet)) then table.insert(liste, projet) end
    end
    if #liste == 0 then
        y = Paragraphe(contenu, y, progressions and L.PROGRESSIONS_NO_PROJECT or L.PROJECTS_NONE, "GameFontDisableSmall")
    end

    for _, projet in ipairs(liste) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)

        local cleDepli = "projet:" .. tostring(projet.id)
        local deplie = ecran.deplie[cleDepli] == true
        PoserLigne(ligne, 0, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)
        y = y + ESPACE_SECTION
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        local hauteurTitre = EnTeteDeBloc(ligne)
        local titre = NS.projets.NomDe(projet)
        if projet.statut == "archive" then titre = titre .. " (" .. L.PROJECTS_ARCHIVE .. ")" end
        -- Projet de progression : son metier et son rang suffisent, sans
        -- "lance par" qui n'apprend rien ici.
        local deProgression = projet.progression ~= nil
        local lanceur = not deProgression and NS.projets.LanceePar and NS.projets.LanceePar(projet)
        if lanceur then
            titre = titre .. "   |cff8c8c8c" .. string.format(L.PROJECTS_BY, lanceur) .. "|r"
        elseif projet.repris then
            titre = titre .. "   |cff8c8c8c" .. L.PROJECTS_BY_UNKNOWN .. "|r"
        end
        ligne.nom:SetText(titre)
        ligne.sacs:SetText("")
        ligne.banque:SetText("")

        local arbres = NS.projets.Calculer(projet.id)
        if arbres then
            local part = NS.moteur.Couverture(arbres)
            ligne.total:SetText(string.format(L.PROJECTS_COVERAGE, math.floor(part * 100 + 0.5)))
            ligne.total:SetTextColor(part >= 1 and 0.31 or 0.55, part >= 1 and 0.82 or 0.55, part >= 1 and 0.41 or 0.55)
        else
            ligne.total:SetText("")
        end
        ligne:Show()
        y = y + hauteurTitre
        -- Sous le titre d'un projet de progression : ou en est le metier.
        if deProgression then
            local fiche = NS.base.FicheAffichee()
            local sien = fiche and type(fiche.metiers) == "table" and fiche.metiers[tostring(projet.progression)]
            local tousVises = NS.recettes.RangsVises(fiche, projet.progression)
            local vise = projet.rangVise or tousVises[#tousVises]
            if type(sien) == "table" and sien.rang then
                local texte = vise and string.format(L.GOAL_PROG_DETAIL, sien.rang, vise)
                    or string.format(L.PROG_CURRENT_RANK, sien.rang)
                y = Paragraphe(contenu, y + 2, texte, "GameFontHighlightSmall")
            end
        end

        -- Renommer : le champ prend la place du titre, sur sa ligne, sans rien
        -- recouvrir. Entree garde le nom, Echap annule.
        local function OuvrirLeNom()
            local champ = ChampDeSaisie(contenu)
            champ:ClearAllPoints()
            champ:SetPoint("LEFT", ligne.marqueur, "RIGHT", 10, 0)
            champ:SetWidth(260)
            champ:SetFrameLevel(ligne:GetFrameLevel() + 5)
            ligne.nom:SetText("")
            champ:SetText(projet.nom or NS.projets.NomDe(projet))
            champ:Show()
            champ:SetFocus()
            champ:HighlightText()
            champ:SetScript("OnEnterPressed", function(self)
                NS.projets.Renommer(projet.id, self:GetText())
                self:ClearFocus()
                self:Hide()
                ecran.Montrer(ecran.page)
            end)
            champ:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                self:Hide()
                ecran.Montrer(ecran.page)
            end)
        end

        if deplie then
            if #(projet.objets or {}) == 0 then
                index = index + 1
                local vide = LigneDeTableau(contenu, index)
                vide:ClearAllPoints()
                vide:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                vide:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(vide, RETRAIT_PAR_NIVEAU, false, false, nil)
                vide.icone:Hide()
                vide.nom:SetFontObject("GameFontDisableSmall")
                vide.nom:SetText(L.PROJECTS_EMPTY)
                vide.sacs:SetText("") vide.banque:SetText("") vide.total:SetText("")
                vide:Show()
                y = y + HAUTEUR_LIGNE
            else
                index, y = RendreEntrees(contenu, projet.id, index, y, 1)
            end

            -- Actions du projet, sur leur propre ligne.
            local cles = { "renommer" .. projet.id, "archiver" .. projet.id, "supprimer" .. projet.id }
            local rangee = {}
            y = y + 4
            local renommer = BoutonAction(contenu, cles[1], L.PROJECTS_RENAME)
            renommer:SetScript("OnClick", OuvrirLeNom)
            table.insert(rangee, renommer)

            -- A la creation, le nom s'ouvre tout de suite : on nomme son projet
            -- au moment ou on le cree, sans avoir a chercher le bouton.
            if ecran.nommageEnCours == projet.id then
                ecran.nommageEnCours = nil
                OuvrirLeNom()
            end

            local archiver = BoutonAction(contenu, cles[2],
                projet.statut == "archive" and L.PROJECTS_UNARCHIVE or L.PROJECTS_ARCHIVE)
            table.insert(rangee, archiver)
            archiver:SetScript("OnClick", function()
                NS.projets.Archiver(projet.id, projet.statut ~= "archive")
                ecran.Montrer(ecran.page)
            end)

            -- Suppression en deux temps : le bouton demande confirmation
            -- avant d'agir, sans boite de dialogue.
            local aConfirmer = (ecran.suppressionEnCours == projet.id)
            local supprimer = BoutonAction(contenu, cles[3],
                aConfirmer and L.PROJECTS_CONFIRM or L.PROJECTS_DELETE)
            table.insert(rangee, supprimer)
            supprimer:SetScript("OnClick", function()
                if ecran.suppressionEnCours == projet.id then
                    ecran.suppressionEnCours = nil
                    -- Un projet de progression et son rang vise ne font qu'un :
                    -- on supprime les deux, sinon l'objectif reapparait seul.
                    if projet.progression then
                        local fiche = NS.base.FicheAffichee()
                        if fiche and type(fiche.objectifsProgression) == "table" then
                            fiche.objectifsProgression[tostring(projet.progression)] = nil
                        end
                    end
                    NS.projets.Supprimer(projet.id)
                else
                    ecran.suppressionEnCours = projet.id
                end
                ecran.Montrer(ecran.page)
            end)

            -- Destination des clics droits faits dans les recettes.
            local estDestination = tostring(NS.projets.Destination()) == tostring(projet.id)
            local cibler = BoutonAction(contenu, "cibler" .. projet.id,
                estDestination and L.PROJECTS_TARGET_ON or L.PROJECTS_TARGET)
            table.insert(rangee, cibler)
            cibler:SetScript("OnClick", function()
                NS.projets.PoserDestination(projet.id)
                ecran.Montrer(ecran.page)
            end)
            cibler:SetEnabled(not estDestination)
            gardees["cibler" .. projet.id] = true

            -- Suivi de recolte : ce projet y figure (onglet Objectifs) ou non.
            local suivi = not projet.horsSuivi
            local suivre = BoutonAction(contenu, "suivre" .. projet.id,
                suivi and L.PROJECTS_UNTRACK or L.PROJECTS_TRACK)
            table.insert(rangee, suivre)
            suivre:SetScript("OnClick", function()
                projet.horsSuivi = suivi or nil
                if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                ecran.Montrer(ecran.page)
            end)
            gardees["suivre" .. projet.id] = true

            -- Ajout sur place : la liste de tout ce que vos personnages savent
            -- fabriquer, par metier, sous le projet. On ne quitte jamais cette
            -- page et on n'a rien a taper.
            local chercher = BoutonAction(contenu, "chercher" .. projet.id, L.PROJECTS_SEARCH)
            table.insert(rangee, chercher)
            chercher:SetScript("OnClick", function()
                if ecran.rechercheProjet == projet.id then
                    ecran.rechercheProjet = nil
                    ecran.texteRecherche = nil
                else
                    ecran.rechercheProjet = projet.id
                    ecran.texteRecherche = ""
                end
                ecran.Montrer(ecran.page)
            end)
            gardees["chercher" .. projet.id] = true

            -- Quand on regarde un autre personnage, on peut recuperer un de
            -- ses projets : c'est ce qui repare une attribution erronee.
            local connecte = NS.ClePersonnage()
            if NS.base.CleAffichee() ~= connecte then
                local nomConnecte = NS.inventaire.NomCourt(connecte)
                local donner = BoutonAction(contenu, "donner" .. projet.id,
                    string.format(L.PROJECTS_GIVE, nomConnecte))
                table.insert(rangee, donner)
                donner:SetScript("OnClick", function()
                    NS.projets.Donner(projet.id, connecte)
                    ecran.Montrer(ecran.page)
                end)
                gardees["donner" .. projet.id] = true
            end

            for _, cle in ipairs(cles) do gardees[cle] = true end
            y = RangeeDeBoutons(contenu, rangee, y, RETRAIT_PAR_NIVEAU)

            if ecran.rechercheProjet == projet.id then
                index, y = RendreChoixDeRecettes(contenu, projet.id, index, y)
            end
        end
        y = y + 4
    end

    index, y = RendreBlocARecuperer(contenu, index, y, progressions and "progressions" or "fabrications")

    CacherActions(contenu, gardees)
    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end

local function RendreProjets(contenu) RendreListeDeProjets(contenu, nil) end
local function RendreProgressions(contenu) RendreListeDeProjets(contenu, true) end

-- Rangs vises (page Progression, "Viser un rang") : un bloc chacun, comme un
-- projet. Deplie : le rang, les matieres, et de quoi revoir le plan ou
-- arreter de viser.
RendreRangsVises = function(contenu, index, y, gardees)
    local rangs = NS.suivi and NS.suivi.RangsVises and NS.suivi.RangsVises() or {}
    for _, o in ipairs(rangs) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        local cleDepli = "rang:" .. tostring(o.ligne)
        local deplie = ecran.deplie[cleDepli] == true
        PoserLigne(ligne, 0, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)
        y = y + ESPACE_SECTION
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        local hauteurTitre = EnTeteDeBloc(ligne)
        ligne.nom:SetText(o.nom)
        ligne.sacs:SetText("")
        ligne.banque:SetText("")
        ligne.total:SetText(o.atteint and L.PROGRESSIONS_REACHED
            or string.format(L.PROJECTS_COVERAGE, math.floor(o.pct * 100 + 0.5)))
        ligne.total:SetTextColor(o.atteint and 0.31 or 0.55, o.atteint and 0.82 or 0.55, o.atteint and 0.41 or 0.55)
        ligne:Show()
        y = y + hauteurTitre
        if deplie then
            y = Paragraphe(contenu, y, o.detail, "GameFontHighlightSmall")
            if #o.matieres == 0 then
                y = Paragraphe(contenu, y, L.GOAL_NOTHING_TO_GATHER, "GameFontDisableSmall")
            end
            for _, m in ipairs(o.matieres) do
                index = index + 1
                local l = LigneDeTableau(contenu, index)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, nil)
                local icone = NS.jeu.iconeObjet and NS.Appeler(NS.jeu.iconeObjet, m.objet)
                if icone then l.icone:SetTexture(icone) l.icone:Show() else l.icone:Hide() end
                Marquer(l, m.manque <= 0, "GameFontHighlightSmall", m.objet)
                l.nom:SetText(NS.inventaire.NomDObjet(m.objet))
                l.sacs:SetText("")
                l.banque:SetText("")
                local texte = m.manque <= 0 and string.format(L.COMP_AVAILABLE, m.requis, Repartition(m.objet))
                    or string.format(L.COMP_MISSING, m.manque, m.requis)
                local prixHV = m.manque > 0 and NS.encheres and NS.encheres.Prix(m.objet, m.manque)
                if prixHV then
                    texte = texte .. "  |cffffffff" .. string.format(L.AH_ON_LINE, NS.marchands.Monnaie(prixHV * m.manque)) .. "|r"
                end
                l.total:SetText(texte)
                l:Show()
                y = y + HAUTEUR_LIGNE
            end
            -- A acheter chez un marchand : ce qui manque encore, son prix, et
            -- de quoi aller au marchand le plus proche.
            local achats, total, estime = {}, nil, false
            for objet, n in pairs(o.achats or {}) do
                local reste = n - (NS.inventaire.TotalPossede(objet) or 0)
                if reste > 0 then table.insert(achats, { objet = objet, n = reste }) end
            end
            table.sort(achats, function(a, b) return a.n > b.n end)
            if #achats > 0 then
                y = y + 4
                y = Paragraphe(contenu, y, L.PROG_BUY, "GameFontNormalSmall")
            end
            for _, a in ipairs(achats) do
                index = index + 1
                local l = LigneDeTableau(contenu, index)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, nil)
                local icone = NS.jeu.iconeObjet and NS.Appeler(NS.jeu.iconeObjet, a.objet)
                if icone then l.icone:SetTexture(icone) l.icone:Show() else l.icone:Hide() end
                Marquer(l, false, "GameFontHighlightSmall", a.objet)
                l.nom:SetText(NS.inventaire.NomDObjet(a.objet))
                l.sacs:SetText("")
                l.banque:SetText("")
                local texte = string.format(L.SUPPLY_GET, a.n)
                local prix, exact = NS.marchands.Prix(a.objet)
                if prix then
                    total = (total or 0) + prix * a.n
                    if not exact then estime = true end
                    texte = texte .. "  |cffffffff" .. (exact and "" or "~ ") .. NS.marchands.Monnaie(prix * a.n) .. "|r"
                end
                l.total:SetText(texte)
                if NS.marchands.Localisable(a.objet) then
                    local objet = a.objet
                    PoserBoutonDeLigne(l, L.VENDOR_LOCATE, function() NS.marchands.Guider(objet) end, nil, L.VENDOR_LOCATE_HELP)
                end
                l:Show()
                y = y + HAUTEUR_LIGNE
            end
            if total then
                y = y + 4
                y = Paragraphe(contenu, y, string.format(L.VENDOR_TOTAL, (estime and "~ " or "") .. NS.marchands.Monnaie(total)),
                    "GameFontHighlightSmall")
                if estime then y = Paragraphe(contenu, y, L.VENDOR_ESTIMATE_NOTE, "GameFontDisableSmall") end
            end
            y = y + 4
            local ligneMetier = o.ligne
            local voir = BoutonAction(contenu, "voirPlan" .. o.cle, L.PROGRESSIONS_SEE_PLAN)
            voir:SetScript("OnClick", function()
                ecran.progOuvert = ligneMetier
                ecran.Montrer("progression")
            end)
            local arreter = BoutonAction(contenu, "arreter" .. o.cle, L.PROGRESSIONS_STOP)
            arreter:SetScript("OnClick", function()
                local fiche = NS.base.FicheAffichee()
                if fiche and o.vise then
                    NS.recettes.Viser(fiche, ligneMetier, o.vise, false)
                elseif fiche and type(fiche.objectifsProgression) == "table" then
                    fiche.objectifsProgression[tostring(ligneMetier)] = nil
                end
                if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                ecran.Montrer(ecran.page)
            end)
            gardees["voirPlan" .. o.cle], gardees["arreter" .. o.cle] = true, true
            y = RangeeDeBoutons(contenu, { voir, arreter }, y, RETRAIT_PAR_NIVEAU)
        end
        y = y + 4
    end
    return index, y
end

-- Palier de progression : meme regle que l'equipement, tenue par les recettes.
COULEURS_PALIER = NS.recettes.COULEURS_PALIER
PalierDeProgression = function(recette) return NS.recettes.Palier(recette) end

-- Rangee de boutons : ou ajouter une recette. Revient a la ligne quand la
-- largeur est pleine. Rend le nouveau y.
PoserChoixDeProjet = function(contenu, idRecette, nomRecette, y, retrait)
    local choix = NS.actions.Destinations(idRecette)
    local largeurMax = (tonumber(contenu:GetWidth()) or 0)
    if largeurMax < 200 then largeurMax = LARGEUR - LARGEUR_MENU - MARGE - ECART * 2 - 40 end
    local x = retrait
    y = y + 2
    for rang, c in ipairs(choix) do
        local b = BoutonAction(contenu, "ajout:" .. rang, c.libelle)
        local largeur = b:GetWidth() or 120
        if x > retrait and x + largeur > largeurMax then
            x = retrait
            y = y + 24
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", x, -y)
        b:SetScript("OnClick", function()
            NS.actions.AjouterA(c, idRecette, nomRecette, 1)
            ecran.choixAjout = nil
            ecran.Montrer(ecran.page)
        end)
        b:Show()
        x = x + largeur + 6
    end
    return y + 24 + 4
end

-- ---------------------------------------------------------------------------
-- Progression d'un metier
-- ---------------------------------------------------------------------------

local function ListeDObjets(contenu, index, y, objets, droite)
    local liste = {}
    for objet, n in pairs(objets) do table.insert(liste, { objet = objet, n = n }) end
    table.sort(liste, function(a, b) return a.n > b.n end)
    for _, e in ipairs(liste) do
        local icone = NS.Appeler(NS.jeu.iconeObjet, e.objet)
        local _, _, l = nil, nil, nil
        index, y, l = LigneSimple(contenu, index, y, icone, NS.inventaire.NomDObjet(e.objet), droite(e))
        if l and NS.objets.CouleurDuNom then l.nom:SetTextColor(NS.objets.CouleurDuNom(e.objet)) end
    end
    return index, y, #liste
end

-- Monter un metier : une seule page, guidee comme une recette. On choisit le
-- rang vise, puis les etapes s'enchainent dans l'ordre, chacune avec son
-- bouton. Une etape faite se coche et se replie ; la suivante est mise en
-- avant. Le rang vise est garde dans la fiche : le suivi de recolte et la
-- banque l'accompagnent.
local function RendreProgressionDuMetier(contenu, index, y, ligneMetier, sien)
    local catalogue = NS.recettes
    local rang, rangMax = sien.rang, sien.rangMax
    local VERT, OR, GRIS = { 0.31, 0.82, 0.41 }, { 1, 0.82, 0 }, { 0.62, 0.62, 0.62 }
    local fiche = NS.base.FicheAffichee()
    local cleObjectif = tostring(ligneMetier)
    -- Trois rangs vises cumulables : assure (coche d'office), atteignable
    -- avec les recettes, et un rang au choix. Un rang choisi atteint s'efface.
    local emp = catalogue.Emplacements(fiche, cleObjectif)
    if emp.choix and emp.choix <= rang and fiche then
        catalogue.PoserEmplacement(fiche, cleObjectif, "choix", nil)
        emp.choix = nil
    end
    local function Basculer(nom, valeur)
        if not fiche then return end
        catalogue.PoserEmplacement(fiche, cleObjectif, nom, valeur)
        if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
        ecran.Montrer(ecran.page)
    end
    local plafondMetier = rangMax or (rang + 75)
    ecran.choixRang = ecran.choixRang or {}
    local choix = emp.choix or tonumber(ecran.choixRang[cleObjectif]) or math.min(rang + 10, plafondMetier)
    choix = math.max(rang + 1, math.min(plafondMetier, choix))
    local gauche = RETRAIT_PAR_NIVEAU + retraitCourant

    -- Tout le bloc s'aligne sur le nom du metier (apres son marqueur et son
    -- icone), dans une seule taille de texte.
    local aligne = 2 + 14 + 4 + 16 + 6
    local POLICE = "GameFontHighlightSmall"

    -- Les trois lignes, au meme pas que les lignes des etapes, chacune avec
    -- sa case a cocher au bord droit : cochee, le rang est vise.
    contenu.casesVise = contenu.casesVise or {}
    local function LigneAViser(k, texte, couleur, coche, auClic)
        local l
        index, y, l = LigneSimple(contenu, index, y, nil, texte, "")
        if not l then return nil end
        l.nom.agrandir = false
        l.nom:SetFontObject(POLICE)
        if couleur then l.nom:SetTextColor(couleur[1], couleur[2], couleur[3]) end
        -- Le texte va jusqu'a la case, jamais coupe par la colonne de droite.
        l.nom:ClearAllPoints()
        l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
        l.nom:SetPoint("RIGHT", l, "RIGHT", -40, 0)
        local case = contenu.casesVise[k]
        if not case then
            case = CreateFrame("CheckButton", nil, contenu, "UICheckButtonTemplate")
            case:SetSize(24, 24)
            contenu.casesVise[k] = case
        end
        l.case = nil
        if auClic then
            case:ClearAllPoints()
            case:SetPoint("RIGHT", contenu, "TOPRIGHT", -8, -(y - HAUTEUR_LIGNE / 2))
            case:SetFrameLevel(l:GetFrameLevel() + 2)
            case:SetChecked(coche and true or false)
            case:SetScript("OnClick", auClic)
            case:Show()
            l.case = case
        else
            case:Hide()
        end
        return l
    end

    y = y + 4
    local assure, atteignable, probable = catalogue.Cibles(fiche, cleObjectif)
    assure, atteignable, probable = assure or rang, atteignable or rang, probable or rang
    -- 1. Ce que les composants du compte (sacs, banque, autres personnages)
    -- donnent deja, a coup sur.
    if assure > rang then
        LigneAViser(1, string.format(L.GUIDE_ALREADY, assure), VERT, emp.sur,
            function() Basculer("sur", not emp.sur) end)
    elseif probable > rang then
        -- Pas de point sur, mais des points probables : le dire, comme le
        -- resume de la ligne du metier.
        LigneAViser(1, string.format(L.GUIDE_ALREADY_PROBABLE, probable), GRIS, false, nil)
    else
        LigneAViser(1, L.GUIDE_ALREADY_NONE, GRIS, false, nil)
    end
    -- 2. Ce que les recettes connues permettent, composants a reunir.
    if atteignable > rang then
        LigneAViser(2, string.format(L.GUIDE_RECIPES, atteignable), OR, emp.recettes,
            function() Basculer("recettes", not emp.recettes) end)
    else
        LigneAViser(2, L.GUIDE_RECIPES_NONE, GRIS, false, nil)
    end
    -- 3. Un rang de son choix, juste avant sa case. Coche, il suit les
    -- fleches sans avoir a recocher.
    if contenu.libelleObjectif then contenu.libelleObjectif:Hide() end
    local ligneChoix = LigneAViser(3, L.GUIDE_CHOICE, nil, emp.choix ~= nil,
        function() Basculer("choix", (not emp.choix) and choix or nil) end)
    contenu.etatObjectif = { valeur = choix, mini = rang + 1, maxi = plafondMetier }
    local S = NS.suite or _G.CoreSuite
    if S and S.Curseur and ligneChoix then
        if not contenu.curseurObjectif then
            contenu.curseurObjectif = S.Curseur(contenu, 0, 1000, 1,
                function() return contenu.etatObjectif and contenu.etatObjectif.valeur end,
                function(v)
                    local e = contenu.etatObjectif
                    if not e then return end
                    v = math.max(e.mini, math.min(e.maxi, v))
                    e.valeur = v
                    if e.poser then e.poser(v) end
                    ecran.Montrer(ecran.page)
                end, nil, nil, 5)
            contenu.curseurObjectif.surParchemin = function() return NS.charte.Fond and NS.charte.Fond() == "parchemin" end
        end
        contenu.etatObjectif.poser = function(v)
            ecran.choixRang[cleObjectif] = v
            if emp.choix and fiche then
                catalogue.PoserEmplacement(fiche, cleObjectif, "choix", v)
                if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
            end
        end
        local c = contenu.curseurObjectif
        c:ClearAllPoints()
        c:SetPoint("RIGHT", ligneChoix.case or ligneChoix, ligneChoix.case and "LEFT" or "RIGHT", -6, 0)
        c:SetFrameLevel(ligneChoix:GetFrameLevel() + 2)
        c:Show()
        c.Rendre()
        if c.boutonsPM then
            local bas, haut = choix > contenu.etatObjectif.mini, choix < contenu.etatObjectif.maxi
            c.boutonsPM[1]:SetEnabled(bas)
            c.boutonsPM[2]:SetEnabled(haut)
            if c.boutonsPM[3] then c.boutonsPM[3]:SetEnabled(bas) c.boutonsPM[4]:SetEnabled(haut) end
        end
    end

    -- Rien de vise : pas d'etapes. Elles suivent tous les rangs vises.
    local vises = {}
    for _, v in ipairs(catalogue.RangsVises(fiche, cleObjectif)) do if v > rang then table.insert(vises, v) end end
    if #vises == 0 then return index, y + 6 end
    -- Les rangs vises, sur une ligne, au-dessus des etapes.
    local noms = {}
    for _, v in ipairs(vises) do table.insert(noms, string.format(L.GUIDE_TARGET_ONE, v)) end
    local segments = catalogue.PlansVises(fiche, cleObjectif, rang, rangMax, vises)
    -- Vert seulement si tout se fait en points surs (recettes oranges).
    -- Sinon, dit clairement jusqu'ou c'est sur, et comment le reste est prevu.
    local auHasard, rangSur = false, rang
    for k, seg in ipairs(segments) do
        if seg.plan.probable then auHasard = true end
        if k == 1 or not auHasard then rangSur = math.max(rangSur, seg.plan.rangSur or seg.de) end
    end
    y = Paragraphe(contenu, y + 6, string.format(L.GUIDE_TARGETS, table.concat(noms, ", ")), POLICE, auHasard and OR or VERT, aligne)
    if auHasard then
        local texteSur = (rangSur > rang) and string.format(L.GUIDE_SURE_UNTIL, rangSur) or L.GUIDE_SURE_NONE
        y = Paragraphe(contenu, y, texteSur .. " " .. L.GUIDE_LUCK_PLANNED, "GameFontDisableSmall", nil, aligne)
    end
    local objectif = segments[#segments] and segments[#segments].vise or choix
    local plan = { utilises = {}, achats = {}, manques = {}, intermediaires = {}, etapes = {}, estime = false }
    for _, seg in ipairs(segments) do
        for _, champ in ipairs({ "utilises", "achats", "manques", "intermediaires" }) do
            for objet, n in pairs(seg.plan[champ] or {}) do plan[champ][objet] = (plan[champ][objet] or 0) + n end
        end
        if seg.plan.estime then plan.estime = true end
    end
    -- Tant que la recolte n'est pas faite pour tous les rangs vises, rien ne
    -- se cree : pas de fabrication partielle. Pour avancer rang par rang, on
    -- decoche les rangs plus hauts.
    -- Meme chose tant que les achats et la recuperation ne sont pas faits :
    -- tout doit etre dans les sacs avant la premiere fabrication.
    local bloque
    if next(plan.manques) ~= nil then bloque = L.GUIDE_GATHER_FIRST end
    if not bloque then
        for objet, n in pairs(plan.achats) do
            if (NS.inventaire.DisponibleDansLesSacs(objet) or 0) < n then bloque = L.GUIDE_BUY_FIRST break end
        end
    end
    if not bloque then
        for objet, n in pairs(plan.utilises) do
            if (NS.inventaire.DisponibleDansLesSacs(objet) or 0) < n then bloque = L.GUIDE_FETCH_FIRST break end
        end
    end
    local function Creer(l, recette, n)
        PoserBoutonFabriquer(l, recette, n)
        if bloque and l.fabriquer then
            l.fabriquer:SetEnabled(false)
            if l.manque then
                l.manque:ClearAllPoints()
                l.manque:SetPoint("RIGHT", l.fabriquer, "LEFT", -6, 0)
                l.manque:SetText(bloque)
                l.manque:SetTextColor(0.9, 0.3, 0.3)
                l.manque:Show()
                AncrerLibelle(l, l.manque)
            end
        end
    end
    local function ParRang(champ, objet)
        if #segments < 2 then return "" end
        local morceaux = {}
        for _, seg in ipairs(segments) do
            local n = seg.plan[champ] and seg.plan[champ][objet]
            if n and n > 0 then table.insert(morceaux, string.format(L.GUIDE_SPLIT, seg.vise, n)) end
        end
        return (#morceaux > 0) and ("  |cff9d9d9d(" .. table.concat(morceaux, ", ") .. ")|r") or ""
    end
    local dernier = segments[#segments]
    if dernier and dernier.plan.atteint < dernier.vise then
        y = Paragraphe(contenu, y, string.format(L.PROG_GOAL_PARTIAL, dernier.vise, dernier.plan.atteint), POLICE, OR, aligne)
        local raisons = { aucuneRecette = L.PROG_STOP_NORECIPE, plusRien = L.PROG_STOP_NOORANGE,
            plafond = string.format(L.PROG_STOP_CAP, rangMax or 0) }
        if dernier.plan.arret and raisons[dernier.plan.arret] then
            y = Paragraphe(contenu, y, raisons[dernier.plan.arret], POLICE, GRIS, aligne)
        end
    end

    -- Les etapes. Chacune dit si elle est faite ; la premiere qui ne l'est
    -- pas est celle a faire maintenant.
    local numero, courante = 0, false
    local function Etape(libelle, faite)
        numero = numero + 1
        local droite
        if faite then
            droite = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. L.GUIDE_DONE
        elseif not courante then
            courante = true
            droite = "|cffffd100" .. L.GUIDE_NOW .. "|r"
        end
        index, y = TitreDeSection(contenu, index, y, string.format(L.GUIDE_STEP, numero, libelle), droite)
        return not faite
    end
    local function BoutonDEtape(cle, libelle, auClic)
        y = y + 4
        local b = BoutonAction(contenu, cle, libelle)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", gauche + RETRAIT_PAR_NIVEAU, -y)
        b:SetScript("OnClick", auClic)
        b:Show()
        y = y + 26
    end
    local function Icone(objet) return NS.Appeler(NS.jeu.iconeObjet, objet) end
    local function Nom(objet) return NS.inventaire.NomDObjet(objet) end
    local function Trie(t)
        local liste = {}
        for objet, n in pairs(t or {}) do if n > 0 then table.insert(liste, { objet = objet, n = n }) end end
        table.sort(liste, function(a, b) if a.n ~= b.n then return a.n > b.n end return tostring(a.objet) < tostring(b.objet) end)
        return liste
    end

    -- 1. Recolter d'abord ce qui manque encore au compte.
    if next(plan.manques) then
        if Etape(L.GUIDE_GATHER, false) then
            for _, e in ipairs(Trie(plan.manques)) do
                index, y = LigneSimple(contenu, index, y, Icone(e.objet), "x" .. e.n .. "  " .. Nom(e.objet), ParRang("manques", e.objet))
            end
            BoutonDEtape("progRecolte", L.GUIDE_GATHER_GO, function()
                if NS.suivi and NS.suivi.Guider then NS.suivi.Guider(true) end
                ecran.Montrer(ecran.page)
            end)
        end
    end

    -- 2. Acheter chez un marchand, apres la recolte. Toujours la liste, chaque ligne cochee
    -- quand ce personnage l'a dans ses sacs : c'est la qu'il en a besoin
    -- pour fabriquer (ce qu'un autre personnage detient ne compte pas).
    if next(plan.achats) then
        local liste, manque = {}, 0
        for _, e in ipairs(Trie(plan.achats)) do
            local reste = e.n - (NS.inventaire.DisponibleDansLesSacs(e.objet) or 0)
            if reste > 0 then manque = manque + 1 end
            table.insert(liste, { objet = e.objet, n = e.n, reste = reste })
        end
        Etape(L.GUIDE_BUY, manque == 0)
        for _, e in ipairs(liste) do
            local droite = e.reste > 0 and string.format(L.GUIDE_BUY_LEFT, e.reste)
                or ("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. L.GUIDE_BUY_OK)
            local l
            index, y, l = LigneSimple(contenu, index, y, Icone(e.objet), "x" .. e.n .. "  " .. Nom(e.objet), droite)
            if l then
                if e.reste > 0 then l.total:SetTextColor(0.9, 0.3, 0.3) else l.total:SetTextColor(0.31, 0.82, 0.41) end
                if e.reste > 0 and NS.marchands and NS.marchands.Localisable and NS.marchands.Localisable(e.objet) then
                    local objet = e.objet
                    PoserBoutonDeLigne(l, L.VENDOR_LOCATE, function() NS.marchands.Guider(objet) end, nil, L.VENDOR_LOCATE_HELP)
                end
            end
        end
    end

    -- 3. Recuperer en dernier : ce qui dort en banque ou chez mes autres
    -- personnages, on l'a deja ; on le sort une fois le reste reuni.
    local function ARecupererParRang(objet, enSacs)
        if #segments < 2 then return "" end
        local morceaux, sacs = {}, enSacs or 0
        for _, seg in ipairs(segments) do
            local u = seg.plan.utilises and seg.plan.utilises[objet] or 0
            local deSacs = math.min(sacs, u)
            sacs = sacs - deSacs
            if u - deSacs > 0 then table.insert(morceaux, string.format(L.GUIDE_SPLIT, seg.vise, u - deSacs)) end
        end
        return (#morceaux > 0) and ("  |cff9d9d9d(" .. table.concat(morceaux, ", ") .. ")|r") or ""
    end
    -- A recuperer : une ligne par objet, "x32 Terrestrine", et a droite s'il
    -- est disponible. Un clic deroule ou sont les quantites (sacs, banque,
    -- autres personnages), une ligne chacun.
    local aRecuperer = {}
    for _, e in ipairs(Trie(plan.utilises)) do
        local enSacs = NS.inventaire.DisponibleDansLesSacs(e.objet)
        if enSacs < e.n then
            -- Une ligne par personnage qui en a : son nom a la couleur de sa
            -- classe, et ce qu'il a, en sacs, en banque, au courrier.
            local ou, reste = {}, e.n - enSacs
            local sacsM, banqueM, courrierM = NS.inventaire.SacsEtBanque(fiche, e.objet)
            courrierM = courrierM or 0
            if sacsM + banqueM + courrierM > 0 then
                table.insert(ou, { fiche = fiche, n = sacsM + banqueM + courrierM,
                    texte = NS.inventaire.TexteSacsBanque(sacsM, banqueM, courrierM) })
            end
            reste = reste - banqueM - courrierM
            local parCle = {}
            for _, f in ipairs(NS.base.TousLesPersonnages()) do parCle[f.cle] = f end
            local _, detail = NS.inventaire.DetailChezLesAutres(fiche, e.objet)
            for _, d in ipairs(detail) do
                table.insert(ou, { fiche = parCle[d.cle] or { cle = d.cle }, n = d.total,
                    texte = NS.inventaire.TexteSacsBanque(d.sacs, d.banque, d.courrier) })
                reste = reste - d.total
            end
            if #detail > 0 or banqueM + courrierM > 0 then
                table.insert(aRecuperer, { objet = e.objet, n = e.n - enSacs, ou = ou, complet = reste <= 0 })
            end
        end
    end
    if next(plan.utilises or {}) then
        if Etape(L.GUIDE_FETCH, #aRecuperer == 0) then
            ecran.deplieRecup = ecran.deplieRecup or {}
            for _, e in ipairs(aRecuperer) do
                local cleD = tostring(e.objet)
                local deplie = ecran.deplieRecup[cleD] == true
                index = index + 1
                local l = LigneDeTableau(contenu, index)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
                l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
                PoserLigne(l, RETRAIT_PAR_NIVEAU + retraitCourant, true, deplie, function()
                    ecran.deplieRecup[cleD] = (not deplie) or nil
                    ecran.Montrer(ecran.page)
                end)
                local ic = Icone(e.objet)
                if ic then l.icone:SetTexture(ic) l.icone:Show() else l.icone:Hide() end
                l.nom:SetFontObject("GameFontHighlightSmall")
                l.nom:SetText("x" .. e.n .. "  " .. Nom(e.objet))
                l.sacs:SetText("") l.banque:SetText("")
                l.total:SetFontObject("GameFontHighlightSmall")
                l.total:SetJustifyH(contenu.largeurEtat and "LEFT" or "RIGHT")
                l.total:SetText(e.complet and L.GUIDE_AVAILABLE or L.GUIDE_AVAILABLE_PART)
                if e.complet then l.total:SetTextColor(0.31, 0.82, 0.41) else l.total:SetTextColor(1, 0.82, 0) end
                l:Show()
                y = y + HAUTEUR_LIGNE
                if deplie then
                    retraitCourant = retraitCourant + RETRAIT_PAR_NIVEAU
                    for _, o in ipairs(e.ou) do
                        local lo
                        index, y, lo = LigneSimple(contenu, index, y, nil, NS.inventaire.NomCourt(o.fiche.cle),
                            o.n .. "  (" .. o.texte .. ")")
                        local c = lo and CouleurDeClasseDe(o.fiche)
                        if c then
                            lo.nom:SetTextColor(c.r, c.g, c.b)
                            lo.nom.couleurPropre = true
                        end
                    end
                    retraitCourant = retraitCourant - RETRAIT_PAR_NIVEAU
                end
            end
            y = Paragraphe(contenu, y + 2, L.GUIDE_FETCH_HELP, "GameFontDisableSmall")
        end
    end

    -- 4. Fabriquer d'abord les composants qu'on fait soi-meme.
    if next(plan.intermediaires or {}) then
        if Etape(L.PROG_CRAFT_FIRST, false) then
            local producteurs = {}
            for _, r in pairs(catalogue.Toutes and catalogue.Toutes() or {}) do
                if type(r) == "table" and r.objetProduit and catalogue.EstApprise(r.id) then producteurs[r.objetProduit] = r end
            end
            -- Dans l'ordre de fabrication : ce qui sert a fabriquer le reste d'abord.
            local profondeurs = {}
            for _, seg in ipairs(segments) do
                for objet, pr in pairs(seg.plan.profondeurs or {}) do profondeurs[objet] = math.max(profondeurs[objet] or 0, pr) end
            end
            local inter = Trie(plan.intermediaires)
            table.sort(inter, function(a, b)
                local pa, pb = profondeurs[a.objet] or 0, profondeurs[b.objet] or 0
                if pa ~= pb then return pa > pb end
                return a.n > b.n
            end)
            for _, e in ipairs(inter) do
                local r = producteurs[e.objet]
                local l
                index, y, l = LigneSimple(contenu, index, y, Icone(e.objet), "x" .. e.n .. "  " .. Nom(e.objet), "")
                if l and r then Creer(l, r, e.n) end
            end
        end
    end

    -- 5. Monter le metier : les recettes, dans l'ordre.
    local nbEtapes = 0
    for _, seg in ipairs(segments) do nbEtapes = nbEtapes + #(seg.plan.etapes or {}) end
    if nbEtapes > 0 then
        if Etape(L.GUIDE_LEVEL, false) then
            for _, seg in ipairs(segments) do
            if #segments > 1 then
                y = Paragraphe(contenu, y + 4, string.format(L.GUIDE_SEGMENT, seg.de, seg.vise), "GameFontNormalSmall", nil, aligne)
            end
            for _, etape in ipairs(seg.plan.etapes or {}) do
              if etape.apprendre then
                -- Apprendre la recette, a son tour dans le parcours : ou, et a
                -- quel rang. Au survol, toutes les sources connues.
                local nature, lignesSrc = catalogue.CommentApprendre(etape.recette)
                local l
                index, y, l = LigneSimple(contenu, index, y, "Interface\\Icons\\INV_Misc_Book_09",
                    string.format(L.GUIDE_LEARN, etape.recette.nom or "?"),
                    string.format(L.GUIDE_LEARN_AT, etape.rangRequis or etape.de) .. "  " .. (L[nature or ""] or ""))
                if l then
                    l.total:SetTextColor(0.31, 0.82, 0.41)
                    l:EnableMouse(true)
                    local titreA = etape.recette.nom
                    l:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(titreA or "", 1, 0.82, 0)
                        for _, t in ipairs(lignesSrc or {}) do GameTooltip:AddLine(t, 1, 1, 1, true) end
                        GameTooltip:Show()
                    end)
                    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
              else
                local objet = etape.recette.objetProduit
                local rangs = string.format(L.PROG_RANKS, etape.de, etape.a)
                if etape.probable then
                    rangs = rangs .. "  " .. (etape.moyenne and etape.moyenne < etape.fois
                        and string.format(L.PROG_PROBABLE_PLANNED, etape.moyenne) or L.PROG_PROBABLE_TAG)
                end
                local l
                index, y, l = LigneSimple(contenu, index, y, objet and Icone(objet),
                    (etape.recette.nom or "?") .. "  |cffffffffx" .. etape.fois .. "|r", rangs)
                if l then
                    if etape.probable then l.total:SetTextColor(1, 0.82, 0) else l.total:SetTextColor(0.31, 0.82, 0.41) end
                    Creer(l, etape.recette, etape.fois)
                    if objet then
                        l:EnableMouse(true)
                        l:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, objet) end
                            GameTooltip:Show()
                        end)
                        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end
                end
              end
            end
            end
            y = Paragraphe(contenu, y + 2, L.GUIDE_LEVEL_HELP, "GameFontDisableSmall")
        end
    end

    if plan.estime then
        y = y + 10
        y = Paragraphe(contenu, y, L.PROG_ESTIMATE, "GameFontDisableSmall")
    end

    return index, y + 6
end

-- Progression : tous les metiers du personnage affiche, un par ligne, avec
-- jusqu'ou ses composants le menent. Un metier se deplie pour le detail ;
-- un seul a la fois, pour que la page reste lisible.
local RECOLTE = { [182] = true, [356] = true, [393] = true }

-- Les anciens projets de progression deviennent des rangs vises : la page
-- Monter un metier les reprend, sans projet a part.
local function MigrerProjetsDeProgression()
    if not (NS.projets and NS.projets.Tous) then return end
    for _, projet in ipairs(NS.projets.Tous(true)) do
        if projet.progression then
            local fiche = NS.base.Personnage and NS.base.Personnage()
            local cle = tostring(projet.progression)
            if fiche and tonumber(projet.rangVise) then
                fiche.objectifsProgression = type(fiche.objectifsProgression) == "table" and fiche.objectifsProgression or {}
                fiche.objectifsProgression[cle] = fiche.objectifsProgression[cle] or tonumber(projet.rangVise)
            end
            NS.projets.Supprimer(projet.id)
        end
    end
end

local function RendreProgression(contenu, seulLigne)
    CacherLignesAuDela(contenu, 1)
    CacherActions(contenu)
    CacherParagraphes(contenu)
    if contenu.valeurObjectif then contenu.valeurObjectif:Hide() end
    if contenu.libelleObjectif then contenu.libelleObjectif:Hide() end
    if contenu.curseurObjectif then contenu.curseurObjectif:Hide() end
    for _, c in pairs(contenu.casesVise or {}) do c:Hide() end
    MigrerProjetsDeProgression()
    ecran.deplie = ecran.deplie or {}
    local catalogue = NS.recettes
    local C = NS.inventaire.COULEURS
    local index, y = 0, 0
    local fiche = NS.base.FicheAffichee()

    local metiers = {}
    for _, m in ipairs(catalogue.MetiersDuPersonnage and catalogue.MetiersDuPersonnage() or {}) do
        -- Seuls les metiers qui fabriquent : la cueillette ne se monte pas ici.
        if m.rang and not RECOLTE[m.ligne] and #(catalogue.Pour(m.ligne) or {}) > 0
            and (seulLigne == nil or m.ligne == seulLigne) then table.insert(metiers, m) end
    end
    if #metiers == 0 then
        PoserMessage(contenu, seulLigne and L.PROG_THIS_NONE or L.PROG_NO_TRADE, 0)
        contenu:SetHeight(60)
        return
    end
    -- Par defaut, tout est replie : on ouvre le metier qu'on veut.

    -- Monter ce metier : le metier choisi a droite, deja ouvert.
    index, y = TitreDeSection(contenu, index, y, seulLigne and L.NAV_LEVEL_UP_THIS or L.PROG_ALL_TITLE)
    for _, m in ipairs(metiers) do
        local sien = fiche.metiers[tostring(m.ligne)]
        local ouvert = seulLigne ~= nil or ecran.progOuvert == m.ligne
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        local ligneMetier = m.ligne
        PoserLigne(ligne, RETRAIT_PAR_NIVEAU, seulLigne == nil, ouvert, seulLigne == nil and function()
            ecran.progOuvert = (ecran.progOuvert ~= ligneMetier) and ligneMetier or false
            ecran.Montrer(ecran.page)
        end or nil)
        local icone = ICONES_METIERS[m.ligne]
        if icone then ligne.icone:SetTexture(icone) ligne.icone:Show() else ligne.icone:Hide() end
        ligne.nom:SetFontObject("GameFontNormal")
        ligne.nom:SetTextColor(1, 0.82, 0)
        ligne.nom:SetText(catalogue.LibelleAvecNiveau(m.nom or catalogue.NomDuMetier(m.ligne) or "", m.rang, m.rangMax))
        ligne.sacs:SetText("")
        ligne.banque:SetText("")
        -- En resume, les memes chiffres que le detail : le rang assure, sinon
        -- le rang probable avec les composants du compte.
        local surR, _, probR = catalogue.Cibles(fiche, m.ligne)
        surR, probR = surR or m.rang, probR or m.rang
        if m.rangMax and m.rang >= m.rangMax then
            ligne.total:SetText(L.PROG_SUMMARY_CAP)
            ligne.total:SetTextColor(0.55, 0.55, 0.55)
        elseif surR > m.rang then
            ligne.total:SetText(string.format(L.PROG_SUMMARY, surR))
            ligne.total:SetTextColor(unpack(C.sacs))
        elseif probR > m.rang then
            ligne.total:SetText(string.format(L.PROG_SUMMARY_PROBABLE, probR))
            ligne.total:SetTextColor(0.55, 0.55, 0.55)
        else
            ligne.total:SetText(L.PROG_SUMMARY_NONE)
            ligne.total:SetTextColor(0.55, 0.55, 0.55)
        end
        ligne:Show()
        y = y + HAUTEUR_LIGNE + 2
        if ouvert and sien then
            retraitCourant = RETRAIT_PAR_NIVEAU * 2
            local okD, iD, yD = pcall(RendreProgressionDuMetier, contenu, index, y, m.ligne, sien)
            retraitCourant = 0
            if not okD then error(iD, 0) end
            index, y = iD, yD
        end
    end

    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end


-- Mots qui ne font pas une famille de recettes (adjectifs, liaisons).
local MOTS_NEUTRES = {}
for mot in string.gmatch("de du des la le les un une et a au aux en sur pour avec d l of the and to "
    .. "grande grand grandes petite petit petites mineure mineur inferieure inferieur superieure superieur "
    .. "majeure majeur puissante puissant forte fort excellente excellent lourde lourd legere leger "
    .. "lesser greater minor major superior heavy light strong mighty", "%S+") do
    MOTS_NEUTRES[mot] = true
end

-- Famille d'une recette d'apres son nom : le premier mot du nom qui revient
-- dans au moins trois recettes du metier (potion, elixir, flacon, huile,
-- transmutation...). Chaque metier trouve ainsi ses propres familles.
local function Familles(recettes)
    local function Mots(nom)
        local mots = {}
        for mot in string.gmatch(Simplifier(nom), "[%a]+") do
            if #mot >= 4 and not MOTS_NEUTRES[mot] then table.insert(mots, mot) end
        end
        return mots
    end
    local frequence = {}
    for _, r in ipairs(recettes) do
        local vus = {}
        for _, mot in ipairs(Mots(r.nom)) do
            if not vus[mot] then vus[mot] = true frequence[mot] = (frequence[mot] or 0) + 1 end
        end
    end
    local famille, libelle = {}, {}
    for _, r in ipairs(recettes) do
        -- Le mot tel qu'ecrit dans le nom (accents compris) pour le titre.
        local choisi
        for _, mot in ipairs(Mots(r.nom)) do
            if frequence[mot] >= 3 then choisi = mot break end
        end
        famille[r] = choisi
        if choisi and not libelle[choisi] then
            for brut in string.gmatch(tostring(r.nom or ""), "[^%s%p]+") do
                if Simplifier(brut) == choisi then libelle[choisi] = brut break end
            end
            libelle[choisi] = libelle[choisi] or choisi
        end
    end
    return famille, libelle
end

-- Titre de famille : la majuscule, et le pluriel simple (Potion : Potions).
local function TitreDeFamille(mot)
    local premier = string.match(mot, "^[%z\1-\127\194-\244][\128-\191]*") or ""
    local reste = string.sub(mot, #premier + 1)
    local titre = string.upper(premier) .. reste
    if premier == "é" then titre = "É" .. reste end
    if not string.match(titre, "[sxz]$") then titre = titre .. "s" end
    return titre
end

local function RendreRecettes(contenu)
    local base = NS.base
    local inventaire = NS.inventaire
    local catalogue = NS.recettes

    -- Sans catalogue, la page le dit au lieu de faire tomber tout l'ecran.
    if not catalogue or not catalogue.Pour then
        RendrePageAVenir(contenu)
        return
    end

    inventaire.Relever(ecran.banqueOuverte)

    local onglet = fenetre and fenetre.onglets and fenetre.onglets[ecran.metier]
    local liste, metierConnu = catalogue.Pour(onglet and onglet.ligne or nil)
    local index = 0
    local y = 0

    local caseConnues, caseNonConnues = CasesDeFiltre(contenu)
    local ligneMetierCourant = ecran.ongletCourantLigne
    local filtreCourant = base.FiltreDuMetier and base.FiltreDuMetier(ligneMetierCourant) or "toutes"

    caseConnues:SetChecked(filtreCourant ~= "nonConnues")
    caseNonConnues:SetChecked(filtreCourant ~= "connues")

    local function Appliquer()
        local connues = caseConnues:GetChecked() and true or false
        local nonConnues = caseNonConnues:GetChecked() and true or false
        -- Tout decocher ne montrerait rien : on garde au moins l'autre coche.
        if not connues and not nonConnues then
            connues = true
            caseConnues:SetChecked(true)
        end
        local valeur = "toutes"
        if connues and not nonConnues then valeur = "connues" end
        if nonConnues and not connues then valeur = "nonConnues" end
        base.PoserFiltreDuMetier(ligneMetierCourant, valeur)
        ecran.Montrer(ecran.page)
    end
    caseConnues:SetScript("OnClick", Appliquer)
    caseNonConnues:SetScript("OnClick", Appliquer)
    caseConnues:Show()
    caseConnues.libelle:Show()
    caseNonConnues:Show()
    caseNonConnues.libelle:Show()

    -- Le metier choisi et son niveau en titre ; la date du releve a droite.
    local ongletChoisi = fenetre and ecran.metier and fenetre.onglets[ecran.metier]
    local releve = string.format(L.RECIPES_READ_AT, (CraftCoreDB and CraftCoreDB.recettesReleveLe) or "?")
    local titreMetier = (ongletChoisi and ongletChoisi.tooltipText and ongletChoisi.tooltipText ~= "") and ongletChoisi.tooltipText or L.NAV_RECIPES
    index, y = EnTeteDePage(contenu, index, y, titreMetier, releve)

    -- Les cases sur leur propre ligne, a gauche : un libelle entier ne se
    -- coupe jamais, et il y a toute la largeur pour les deux.
    caseConnues:ClearAllPoints()
    caseConnues:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, -y)
    caseNonConnues:ClearAllPoints()
    caseNonConnues:SetPoint("TOPLEFT", caseConnues, "TOPLEFT", 130, 0)
    -- Recherche, a droite des cases : quelques lettres ou mots du nom.
    if not contenu.recherche then
        local ok, champ = pcall(CreateFrame, "EditBox", nil, contenu, "SearchBoxTemplate")
        if not ok or not champ then champ = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate") end
        champ:SetSize(170, 20)
        champ:SetAutoFocus(false)
        champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        champ:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        champ:HookScript("OnTextChanged", function(self, parUtilisateur)
            local texte = self:GetText() or ""
            if texte == (ecran.rechercheRecettes or "") then return end
            ecran.rechercheRecettes = texte
            ecran.Montrer(ecran.page)
        end)
        if champ.Instructions then champ.Instructions:SetText(L.RECIPES_SEARCH) end
        contenu.recherche = champ
    end
    local recherche = contenu.recherche
    recherche:ClearAllPoints()
    recherche:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", -4, -y)
    if (recherche:GetText() or "") ~= (ecran.rechercheRecettes or "") then recherche:SetText(ecran.rechercheRecettes or "") end
    recherche:Show()
    local motsCherches = {}
    for mot in string.gmatch(Simplifier(ecran.rechercheRecettes or ""), "%S+") do table.insert(motsCherches, mot) end
    y = y + 22

    -- Rappel de la destination du clic droit, toujours visible.
    index = index + 1
    local destination = LigneDeTableau(contenu, index)
    destination:ClearAllPoints()
    destination:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    destination:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    PoserLigne(destination, 0, false, false, nil)
    destination.icone:Hide()
    destination.nom:SetFontObject("GameFontDisableSmall")
    destination.nom:SetText(L.RECIPES_TARGET)
    -- Les boutons de choix d'un rendu precedent disparaissent ; ceux de la
    -- recette en cours d'ajout sont reposes plus bas.
    CacherActions(contenu)
    destination.sacs:SetText("") destination.banque:SetText("") destination.total:SetText("")
    destination:Show()
    y = y + HAUTEUR_LIGNE

    -- Legende des coches de progression, toujours sous les yeux.
    index = index + 1
    local legende = LigneDeTableau(contenu, index)
    legende:ClearAllPoints()
    legende:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    legende:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    PoserLigne(legende, 0, false, false, nil)
    legende.icone:Hide()
    legende.nom:SetFontObject("GameFontDisableSmall")
    legende.nom:SetText(NS.recettes.LegendeDesPaliers())
    legende.sacs:SetText("") legende.banque:SetText("") legende.total:SetText("")
    legende:Show()
    y = y + HAUTEUR_LIGNE

    if #liste == 0 then
        CacherLignesAuDela(contenu, index + 1)
        PoserMessage(contenu, L.RECIPES_NONE, y)
        contenu:SetHeight(y + 60)
        return
    end

    if not metierConnu then
        index = index + 1
        local avis = LigneDeTableau(contenu, index)
        avis:ClearAllPoints()
        avis:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        avis:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        PoserLigne(avis, 0, false, false, nil)
        avis.icone:Hide()
        avis.nom:SetFontObject("GameFontDisableSmall")
        avis.nom:SetText(L.RECIPES_ALL_PROFESSIONS)
        avis.sacs:SetText("")
        avis.banque:SetText("")
        avis.total:SetText("")
        avis:Show()
        y = y + HAUTEUR_LIGNE
    end

    ecran.deplie = ecran.deplie or {}

    -- Regroupement par emplacement d'equipement. Ce qui ne s'equipe pas passe
    -- en dernier, dans un groupe a part.
    local ligneMetier = ecran.ongletCourantLigne
    local filtre = base.FiltreDuMetier and base.FiltreDuMetier(ligneMetier) or "toutes"
    if not (base.Reglages and base.Reglages().afficherNonApprises) and filtre == "toutes" then
        filtre = "connues"
    end

    local groupes, ordre = {}, {}
    for _, recette in ipairs(liste) do
      local apprise = catalogue.EstApprise(recette.id)
      local garder = (filtre == "toutes")
        or (filtre == "connues" and apprise)
        or (filtre == "nonConnues" and not apprise)
      if garder and #motsCherches > 0 then
          local nom = Simplifier(recette.nom)
          for _, mot in ipairs(motsCherches) do
              if not string.find(nom, mot, 1, true) then garder = false break end
          end
      end
      if garder then
        local code = NS.emplacements and NS.emplacements.DeLObjet(recette.objetProduit) or nil
        local cle = code or "AUTRES"
        if not groupes[cle] then
            groupes[cle] = { code = code, recettes = {} }
            table.insert(ordre, cle)
        end
        table.insert(groupes[cle].recettes, recette)
      end
    end
    -- Ce qui ne s'equipe pas : en familles d'apres le nom (potions, elixirs,
    -- flacons, huiles...), le reste dans "Autres".
    if groupes.AUTRES then
        local famille, libelle = Familles(groupes.AUTRES.recettes)
        local restes = {}
        for _, recette in ipairs(groupes.AUTRES.recettes) do
            local mot = famille[recette]
            if mot then
                local cle = "FAMILLE:" .. mot
                if not groupes[cle] then
                    groupes[cle] = { famille = TitreDeFamille(libelle[mot] or mot), recettes = {} }
                    table.insert(ordre, cle)
                end
                table.insert(groupes[cle].recettes, recette)
            else
                table.insert(restes, recette)
            end
        end
        groupes.AUTRES.recettes = restes
        if #restes == 0 then
            groupes.AUTRES = nil
            for k = #ordre, 1, -1 do if ordre[k] == "AUTRES" then table.remove(ordre, k) end end
        end
    end
    for _, groupe in pairs(groupes) do
        table.sort(groupe.recettes, function(a, b)
            local aa, ab = catalogue.EstApprise(a.id), catalogue.EstApprise(b.id)
            if aa ~= ab then return aa end
            return (a.nom or "") < (b.nom or "")
        end)
    end

    table.sort(ordre, function(a, b)
        local function Rang(cle)
            if cle == "AUTRES" then return 2000 end
            if groupes[cle].famille then return 1000 end
            return NS.emplacements and NS.emplacements.Rang(groupes[cle].code) or 999
        end
        local ra, rb = Rang(a), Rang(b)
        if ra == rb then
            if ra == 1000 then return Simplifier(groupes[a].famille) < Simplifier(groupes[b].famille) end
            return a < b
        end
        return ra < rb
    end)

    for _, cleGroupe in ipairs(ordre) do
        local groupe = groupes[cleGroupe]

        index, y = TitreDeSection(contenu, index, y,
            groupe.famille or (groupe.code and NS.emplacements.Libelle(groupe.code)) or L.SLOT_OTHER)

    for _, recette in ipairs(groupe.recettes) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)

        local appris = catalogue.EstApprise(recette.id)
        local cleDepli = tostring(recette.id)
        local retraitRecette = RETRAIT_PAR_NIVEAU
        local depliable = #(recette.composants or {}) > 0 and NS.moteur ~= nil
        local deplie = depliable and ecran.deplie[cleDepli] == true
        local idRecette = recette.id
        -- Clic gauche : deplier. Clic droit : ajouter a la destination, le
        -- projet designe ou les fabrications rapides.
        PoserLigne(ligne, retraitRecette, depliable, deplie, function(_, bouton)
            if bouton == "RightButton" then
                if catalogue.EstApprise(idRecette) then
                    ecran.choixAjout = (ecran.choixAjout ~= idRecette) and idRecette or nil
                    ecran.Montrer(ecran.page)
                end
                return
            end
            if not depliable then return end
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)
        ligne.nom:SetText(recette.nom or ("recette " .. tostring(recette.id)))

        local icone = recette.objetProduit and NS.jeu.iconeObjet
            and NS.Appeler(NS.jeu.iconeObjet, recette.objetProduit)
        if icone then
            ligne.icone:SetTexture(icone)
            ligne.icone:Show()
        else
            ligne.icone:Hide()
        end

        -- L'etat occupe les colonnes de chiffres, reunies : un libelle entier,
        -- jamais coupe.
        ligne.sacs:SetText("")
        ligne.banque:SetText("")
        local manques, realisable = catalogue.Manques(recette)
        -- Signal court seulement : le detail des manques se lit en depliant,
        -- sinon il mange la place du nom et le fait couper.
        local etat = ""
        if not appris then
            -- Comment elle s'apprend, en un mot, quand le jeu l'a dit.
            local nature = catalogue.CommentApprendre and catalogue.CommentApprendre(recette)
            etat = nature and L[nature] or L.RECIPES_NOT_LEARNED
        elseif manques == nil then
            etat = L.RECIPES_UNKNOWN_SHORT
        elseif #manques > 0 then
            etat = string.format(L.RECIPES_MISSING_SHORT, #manques)
        else
            -- Deux chiffres quand ils different : ce qu'on peut faire tout de
            -- suite, et ce qu'on pourrait faire en rapatriant ce qui dort
            -- chez les autres personnages.
            local total = catalogue.CombienFabricables and catalogue.CombienFabricables(recette)
            local ici = catalogue.CombienFabricablesAPortee and catalogue.CombienFabricablesAPortee(recette)
            if ici and total and total > ici then
                local qui = DetenteursDesComposants(recette)
                if ici > 0 then
                    etat = string.format(L.READY_HERE_AND_MORE, ici, total, qui)
                else
                    etat = string.format(L.READY_ELSEWHERE, total, qui)
                end
            elseif total and total > 0 then
                etat = string.format(L.READY_HERE, total)
            else
                etat = L.RECIPES_CAN_CRAFT
            end
        end
        Marquer(ligne, appris and manques ~= nil and #manques == 0, "GameFontHighlightSmall",
            recette.objetProduit)
        ligne.total:SetText(etat)
        -- Palier de progression, aux couleurs du jeu, en coin de l'icone :
        -- orange point sur, jaune probable, vert peu probable, gris plus rien.
        local palier = appris and PalierDeProgression(recette)
        if palier then
            -- La coche du jeu en coin d'icone, comme sur les emplacements
            -- d'equipement, teintee a la couleur du palier. Rien en gris.
            if not ligne.palier then
                ligne.palier = ligne:CreateTexture(nil, "OVERLAY")
                ligne.palier:SetSize(12, 12)
                ligne.palier:SetPoint("BOTTOMRIGHT", ligne.icone, "BOTTOMRIGHT", 4, -3)
                ligne.palier:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            end
            local c = COULEURS_PALIER[palier]
            ligne.palier:SetVertexColor(c[1], c[2], c[3])
            ligne.palier:SetShown(palier ~= "rien")
        end
        -- Un bouton visible pour ajouter, en plus du clic droit : on doit voir
        -- comment mettre une recette dans un projet.
        if appris then
            -- Boutons courts, le detail est au survol : le nom reste lisible.
            PoserBoutonDeLigne(ligne, "+", function()
                ecran.choixAjout = (ecran.choixAjout ~= idRecette) and idRecette or nil
                ecran.Montrer(ecran.page)
            end, 22, L.RECIPES_ADD_TIP)
            -- Creer : tout ce que les sacs permettent, pour tous les metiers.
            PoserBoutonFabriquer(ligne, recette, "tout")
        end
        -- Au survol : l'objet fabrique, et pour une recette non apprise, comment
        -- l'apprendre, avec les mots du jeu.
        local recetteSurvol = recette
        ligne:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local objet = recetteSurvol.objetProduit
            if objet and GameTooltip.SetItemByID then
                pcall(GameTooltip.SetItemByID, GameTooltip, objet)
            else
                GameTooltip:SetText(recetteSurvol.nom or "")
            end
            local palierSurvol = catalogue.EstApprise(recetteSurvol.id) and PalierDeProgression(recetteSurvol)
            if palierSurvol then
                local c = COULEURS_PALIER[palierSurvol]
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["PALIER_" .. string.upper(palierSurvol)], c[1], c[2], c[3])
            end
            -- Qui, parmi vos autres personnages, pourrait le porter, et si ce
            -- serait mieux que ce qu'il porte.
            if objet and NS.transverse.QuiPourraitLePorter then
                local porteurs = NS.transverse.QuiPourraitLePorter(objet, NS.base.CleAffichee())
                if #porteurs > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L.RECIPES_WEARERS, 1, 0.82, 0)
                    for _, p in ipairs(porteurs) do
                        if p.mieux then
                            GameTooltip:AddDoubleLine("  " .. p.nom, L.RECIPES_WEARER_BETTER, 1, 1, 1, 0.31, 0.82, 0.41)
                        else
                            GameTooltip:AddDoubleLine("  " .. p.nom, L.RECIPES_WEARER_CAN, 1, 1, 1, 0.6, 0.6, 0.6)
                        end
                    end
                end
            end
            -- Ce qu'elle rapporte a l'hotel des ventes, si on le sait.
            local texteValeur = NS.encheres and NS.encheres.TexteDeValeur(NS.encheres.Valeur(recetteSurvol))
            if texteValeur then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(texteValeur, 1, 1, 1, true)
            end
            -- Composants pas tous dans les sacs : ou ils sont, et chez qui.
            if catalogue.EstApprise(recetteSurvol.id) then
                NS.inventaire.ComposantsDansLInfobulle(GameTooltip, recetteSurvol, true)
            end
            if not catalogue.EstApprise(recetteSurvol.id) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L.RECIPES_HOW_TITLE, 1, 0.82, 0)
                local _, lignes = catalogue.CommentApprendre(recetteSurvol)
                lignes = lignes or {}
                if #lignes == 0 then
                    GameTooltip:AddLine(L.RECIPES_HOW_UNKNOWN, 0.6, 0.6, 0.6, true)
                else
                    for _, texte in ipairs(lignes) do GameTooltip:AddLine(texte, 1, 1, 1, true) end
                end
            end
            GameTooltip:Show()
        end)
        ligne:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ligne:Show()
        y = y + HAUTEUR_LIGNE

        -- Ajouter : on choisit ici, sous la recette, dans quel projet elle va.
        -- Un bouton par projet en cours, les fabrications rapides, ou un
        -- nouveau projet. Rien n'est ajoute sans ce choix.
        if ecran.choixAjout == idRecette then
            y = PoserChoixDeProjet(contenu, idRecette, recette.nom, y, retraitRecette + 22)
        end

        if deplie and appris and NS.encheres then
            -- Ce qu'elle rapporte, d'apres le dernier releve de l'hotel des ventes.
            local texte = NS.encheres.TexteDeValeur(NS.encheres.Valeur(recette))
            if texte then y = Paragraphe(contenu, y + 2, texte, "GameFontHighlightSmall") end
        end
        if deplie then
            -- Les stocks de tous les personnages servent au calcul : c'est le
            -- besoin reel qui compte, pas seulement ce qu'on a sous la main.
            -- Du meme camp seulement, comme partout.
            local stocks = NS.projets.StocksDuCompte()
            local arbre = NS.moteur and NS.moteur.Decomposer
                and NS.moteur.Decomposer(CraftCoreDB.recettes, stocks, recette.id, 1,
                    function(id) return catalogue.EstApprise(id) end)
            if arbre then
                -- La recette est deja au premier retrait, sous son emplacement :
                -- ses composants commencent donc au deuxieme.
                index, y = RendreNoeud(contenu, arbre, 2, index, y)
            end
            y = y + 6
        end
    end
    end

    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y, 1))
end


-- ---------------------------------------------------------------------------
-- Commandes : ce qu'un personnage demande, qui le fabrique, ou ca en est
-- ---------------------------------------------------------------------------

local function NomPerso(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

local function EtatDeCommande(c)
    if c.etat == "demandee" then return string.format(L.ORDER_STATE_CRAFT, NomPerso(c.fabricant)), { 1, 0.82, 0 } end
    if c.etat == "envoyer" then return string.format(L.ORDER_STATE_SEND, NomPerso(c.fabricant)), { 0.45, 0.8, 1 } end
    if c.etat == "envoyee" then return L.ORDER_STATE_SENT, { 0.45, 0.8, 1 } end
    return L.ORDER_STATE_DONE, { 0.31, 0.82, 0.41 }
end

local function RendreCommandes(contenu)
    CacherLignesAuDela(contenu, 1)
    ecran.deplie = ecran.deplie or {}
    local index, y = 0, 0
    local gardees = {}
    local commandes = NS.commandes
    y = Paragraphe(contenu, y, L.ORDERS_INTRO, "GameFontDisableSmall")
    y = y + 6

    -- Nouvelle commande : chercher l'objet parmi les recettes connues d'au
    -- moins un personnage, puis pour qui et combien.
    index, y = TitreDeSection(contenu, index, y, L.ORDER_NEW)
    if not contenu.rechercheCommande then
        local ok, champ = pcall(CreateFrame, "EditBox", nil, contenu, "SearchBoxTemplate")
        if not ok or not champ then champ = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate") end
        champ:SetSize(260, 20)
        champ:SetAutoFocus(false)
        champ:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        champ:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        champ:HookScript("OnTextChanged", function(self)
            local texte = self:GetText() or ""
            if texte == (ecran.rechercheCommande or "") then return end
            ecran.rechercheCommande = texte
            ecran.Montrer(ecran.page)
        end)
        if champ.Instructions then champ.Instructions:SetText(L.ORDER_SEARCH) end
        contenu.rechercheCommande = champ
    end
    local champ = contenu.rechercheCommande
    champ:ClearAllPoints()
    champ:SetPoint("TOPLEFT", contenu, "TOPLEFT", 8, -y)
    if (champ:GetText() or "") ~= (ecran.rechercheCommande or "") then champ:SetText(ecran.rechercheCommande or "") end
    champ:Show()
    y = y + 26
    local mots = {}
    for mot in string.gmatch(Simplifier(ecran.rechercheCommande or ""), "%S+") do table.insert(mots, mot) end
    if #mots > 0 and not ecran.commandeChoisie then
        local trouvees = {}
        for cle, r in pairs(CraftCoreDB.recettes or {}) do
            local nom = Simplifier(r.nom or "")
            local garder = r.objetProduit ~= nil
            for _, mot in ipairs(mots) do if not string.find(nom, mot, 1, true) then garder = false break end end
            if garder then
                local qui = commandes.Connaisseurs(cle)
                if #qui > 0 then table.insert(trouvees, { cle = cle, recette = r, qui = qui }) end
            end
        end
        table.sort(trouvees, function(a, b) return (a.recette.nom or "") < (b.recette.nom or "") end)
        if #trouvees == 0 then y = Paragraphe(contenu, y, L.ORDER_SEARCH_NONE, "GameFontDisableSmall") end
        for k, t in ipairs(trouvees) do
            if k > 8 then break end
            index = index + 1
            local l = LigneDeTableau(contenu, index)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
            l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
            local cleRecette = t.cle
            PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, function()
                ecran.commandeChoisie = cleRecette
                ecran.commandePour = ecran.commandePour or NS.ClePersonnage()
                ecran.commandeQuantite = 1
                ecran.Montrer(ecran.page)
            end)
            local icone = NS.Appeler(NS.jeu.iconeObjet, t.recette.objetProduit)
            if icone then l.icone:SetTexture(icone) l.icone:Show() else l.icone:Hide() end
            Marquer(l, false, "GameFontHighlightSmall", t.recette.objetProduit)
            l.nom:SetText(t.recette.nom or tostring(cleRecette))
            l.sacs:SetText("") l.banque:SetText("")
            local noms = {}
            for _, f in ipairs(t.qui) do table.insert(noms, NomPerso(f.cle)) end
            l.total:SetText(string.format(L.ORDER_KNOWN_BY, table.concat(noms, ", ")))
            l:Show()
            y = y + HAUTEUR_LIGNE
        end
    end
    if ecran.commandeChoisie then
        local cleRecette = ecran.commandeChoisie
        index = index + 1
        local l = LigneDeTableau(contenu, index)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, nil)
        local r = CraftCoreDB.recettes[tostring(cleRecette)] or {}
        local icone = NS.Appeler(NS.jeu.iconeObjet, r.objetProduit)
        if icone then l.icone:SetTexture(icone) l.icone:Show() else l.icone:Hide() end
        Marquer(l, true, "GameFontHighlightSmall", r.objetProduit)
        l.nom:SetText(r.nom or tostring(cleRecette))
        l.sacs:SetText("") l.banque:SetText("") l.total:SetText("")
        PoserQuantite(l, ecran.commandeQuantite or 1,
            function() ecran.commandeQuantite = math.max(1, (ecran.commandeQuantite or 1) - 1) ecran.Montrer(ecran.page) end,
            function() ecran.commandeQuantite = (ecran.commandeQuantite or 1) + 1 ecran.Montrer(ecran.page) end)
        l:Show()
        y = y + HAUTEUR_LIGNE + 4
        -- Pour qui : un bouton par personnage, le choisi coche.
        y = Paragraphe(contenu, y, L.ORDER_FOR, "GameFontNormalSmall")
        local boutons = {}
        for _, f in ipairs(NS.base.TousLesPersonnages()) do
            local cle = f.cle
            if type(cle) == "string" and cle:find(" %- ") then
                local choisi = ecran.commandePour == cle
                local b = BoutonAction(contenu, "pour:" .. cle, (choisi and "|TInterface\\Buttons\\UI-CheckBox-Check:14|t " or "") .. NomPerso(cle))
                b:SetScript("OnClick", function() ecran.commandePour = cle ecran.Montrer(ecran.page) end)
                gardees["pour:" .. cle] = true
                table.insert(boutons, b)
            end
        end
        y = RangeeDeBoutons(contenu, boutons, y, RETRAIT_PAR_NIVEAU)
        local fabricant = commandes.MeilleurFabricant(cleRecette, ecran.commandeQuantite or 1, ecran.commandePour)
        if fabricant then
            y = Paragraphe(contenu, y, string.format(L.ORDER_MAKER, NomPerso(fabricant),
                math.floor(commandes.Part(CraftCoreDB.personnages[fabricant] or {}, cleRecette,
                    ecran.commandeQuantite or 1) * 100 + 0.5)), "GameFontHighlightSmall")
        end
        local commander = BoutonAction(contenu, "commander", L.ORDER_PLACE)
        commander:SetScript("OnClick", function()
            local c = commandes.Creer(cleRecette, ecran.commandeQuantite or 1, ecran.commandePour or NS.ClePersonnage())
            if c then NS.Dire(string.format(L.ORDER_PLACED, commandes.NomDeRecette(c.recette), NomPerso(c.fabricant))) end
            ecran.commandeChoisie, ecran.rechercheCommande = nil, ""
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
            ecran.Montrer(ecran.page)
        end)
        local renoncer = BoutonAction(contenu, "renoncer", L.ORDER_CANCEL_NEW)
        renoncer:SetScript("OnClick", function() ecran.commandeChoisie = nil ecran.Montrer(ecran.page) end)
        gardees.commander, gardees.renoncer = true, true
        y = RangeeDeBoutons(contenu, { commander, renoncer }, y + 2, RETRAIT_PAR_NIVEAU)
    end

    -- En cours, puis terminees.
    local enCours, finies = {}, {}
    for _, c in ipairs(commandes.Liste()) do
        if c.etat == "recue" then table.insert(finies, c) else table.insert(enCours, c) end
    end
    y = y + ESPACE_SECTION
    index, y = TitreDeSection(contenu, index, y, string.format(L.ORDERS_ACTIVE, #enCours))
    if #enCours == 0 then y = Paragraphe(contenu, y, L.ORDERS_NONE, "GameFontDisableSmall") end
    local moi = NS.ClePersonnage()
    for _, c in ipairs(enCours) do
        index = index + 1
        local ligne = LigneDeTableau(contenu, index)
        local cleDepli = "commande:" .. tostring(c.id)
        local deplie = ecran.deplie[cleDepli] == true
        PoserLigne(ligne, 0, true, deplie, function()
            ecran.deplie[cleDepli] = (not deplie) or nil
            ecran.Montrer(ecran.page)
        end)
        y = y + 6
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
        local hauteur = EnTeteDeBloc(ligne)
        ligne.nom:SetText(string.format(L.ORDER_TITLE, commandes.NomDeRecette(c.recette), c.quantite or 1, NomPerso(c.demandeur)))
        ligne.sacs:SetText("") ligne.banque:SetText("")
        local etat, couleur = EtatDeCommande(c)
        ligne.total:SetText(etat)
        ligne.total:SetTextColor(couleur[1], couleur[2], couleur[3])
        ligne:Show()
        y = y + hauteur
        if deplie and c.etat == "demandee" then
            -- Ce qu'il faut au fabricant, calcule chez lui.
            local ok, arbres = pcall(NS.base.AvecPersonnage, c.fabricant, function()
                return c.projet and NS.projets.Calculer(c.projet) or nil
            end)
            for _, arbre in ipairs(ok and arbres or {}) do
                index, y = RendreNoeud(contenu, arbre, 1, index, y)
            end
        end
        local boutons = {}
        local id = c.id
        if c.etat == "demandee" then
            for _, f in ipairs(commandes.Connaisseurs(c.recette)) do
                if f.cle ~= c.fabricant then
                    local cle = f.cle
                    local b = BoutonAction(contenu, "confier:" .. id .. ":" .. cle, string.format(L.ORDER_GIVE_TO, NomPerso(cle)))
                    b:SetScript("OnClick", function()
                        commandes.ConfierA(id, cle)
                        if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                        ecran.Montrer(ecran.page)
                    end)
                    gardees["confier:" .. id .. ":" .. cle] = true
                    table.insert(boutons, b)
                end
            end
            local fait = BoutonAction(contenu, "faite:" .. id, L.ORDER_MARK_CRAFTED)
            fait:SetScript("OnClick", function()
                commandes.Marquer(id, c.fabricant == c.demandeur and "recue" or "envoyer")
                if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
                ecran.Montrer(ecran.page)
            end)
            gardees["faite:" .. id] = true
            table.insert(boutons, fait)
        elseif c.etat == "envoyer" then
            y = Paragraphe(contenu, y, c.fabricant == moi and L.ORDER_SEND_HINT
                or string.format(L.ORDER_SEND_HINT_OTHER, NomPerso(c.fabricant)), "GameFontHighlightSmall")
            local envoye = BoutonAction(contenu, "envoyee:" .. id, L.ORDER_MARK_SENT)
            envoye:SetScript("OnClick", function() commandes.Marquer(id, "envoyee") ecran.Montrer(ecran.page) end)
            gardees["envoyee:" .. id] = true
            table.insert(boutons, envoye)
        elseif c.etat == "envoyee" then
            local recue = BoutonAction(contenu, "recue:" .. id, L.ORDER_MARK_RECEIVED)
            recue:SetScript("OnClick", function() commandes.Marquer(id, "recue") ecran.Montrer(ecran.page) end)
            gardees["recue:" .. id] = true
            table.insert(boutons, recue)
        end
        local annuler = BoutonAction(contenu, "annuler:" .. id, L.ORDER_CANCEL)
        annuler:SetScript("OnClick", function()
            commandes.Annuler(id)
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
            ecran.Montrer(ecran.page)
        end)
        gardees["annuler:" .. id] = true
        table.insert(boutons, annuler)
        y = RangeeDeBoutons(contenu, boutons, y + 2, RETRAIT_PAR_NIVEAU)
    end
    if #finies > 0 then
        y = y + ESPACE_SECTION
        index, y = TitreDeSection(contenu, index, y, string.format(L.ORDERS_DONE, #finies))
        for _, c in ipairs(finies) do
            index = index + 1
            local l = LigneDeTableau(contenu, index)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
            l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
            PoserLigne(l, RETRAIT_PAR_NIVEAU, false, false, nil)
            local icone = c.objet and NS.Appeler(NS.jeu.iconeObjet, c.objet)
            if icone then l.icone:SetTexture(icone) l.icone:Show() else l.icone:Hide() end
            Marquer(l, true, "GameFontHighlightSmall", c.objet)
            l.nom:SetText(string.format(L.ORDER_TITLE, commandes.NomDeRecette(c.recette), c.quantite or 1, NomPerso(c.demandeur)))
            l.sacs:SetText("") l.banque:SetText("")
            l.total:SetText(L.ORDER_STATE_DONE)
            l:Show()
            y = y + HAUTEUR_LIGNE
        end
        local effacer = BoutonAction(contenu, "effacerCommandes", L.ORDERS_CLEAR)
        effacer:SetScript("OnClick", function() commandes.EffacerTerminees() ecran.Montrer(ecran.page) end)
        gardees.effacerCommandes = true
        y = RangeeDeBoutons(contenu, { effacer }, y + 4, RETRAIT_PAR_NIVEAU)
    end
    CacherActions(contenu, gardees)
    CacherLignesAuDela(contenu, index + 1)
    contenu:SetHeight(math.max(y + 20, 1))
end

-- ---------------------------------------------------------------------------
-- Assemblage
-- ---------------------------------------------------------------------------

-- Metiers a presenter : les deux du perimetre, toujours, puis ceux que le
-- client a reellement declares dans le catalogue, pour qu'aucune recette
-- relevee ne reste sans onglet.
local function MetiersAPresenter()
    local liste = {}
    local vus = {}

    -- Les metiers du personnage connecte, et eux seuls. Un herboriste ne voit
    -- pas les onglets d'un forgeron.
    local siens = NS.recettes and NS.recettes.MetiersDuPersonnage and NS.recettes.MetiersDuPersonnage() or {}
    for _, sien in ipairs(siens) do
        local icone = ICONES_METIERS[sien.ligne]
        if not icone then
            for cle, recette in pairs(CraftCoreDB.recettes or {}) do
                if NS.recettes.MetierDe(recette) == sien.ligne and recette.objetProduit then
                    local info = NS.objets and NS.objets.Info(recette.objetProduit)
                    if info and info.icone then icone = info.icone break end
                end
            end
        end
        table.insert(liste, {
            cle = "metier" .. sien.ligne,
            ligne = sien.ligne,
            libelle = sien.nom or tostring(sien.ligne),
            icone = icone,
            rang = sien.rang,
            rangMax = sien.rangMax,
        })
        vus[sien.ligne] = true
    end

    -- Un personnage sans metier n'a aucun onglet de metier : on ne montre
    -- jamais ceux des autres personnages du compte.
    local rencontres = {}
    local autres = {}
    for ligne in pairs(rencontres) do
        if not vus[ligne] then table.insert(autres, ligne) end
    end
    table.sort(autres)
    for _, ligne in ipairs(autres) do
        -- Faute d'icone connue pour ce metier, on prend celle d'un de ses
        -- objets produits : constate, jamais invente.
        local icone = ICONES_METIERS[ligne]
        if not icone then
            for cle, recette in pairs(CraftCoreDB.recettes or {}) do
                if NS.recettes.MetierDe(recette) == ligne and recette.objetProduit then
                    local info = NS.objets and NS.objets.Info(recette.objetProduit)
                    if info and info.icone then icone = info.icone break end
                end
            end
        end
        table.insert(liste, {
            cle = "metier" .. ligne,
            ligne = ligne,
            libelle = (NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(ligne)) or tostring(ligne),
            icone = icone or "Interface\\Icons\\INV_Misc_Note_01",
        })
    end
    return liste
end

-- Cree les onglets manquants, dans l'ordre, sans jamais en recreer un existant.
SynchroniserOnglets = function(win)
    local liste = MetiersAPresenter()
    local attendus = {}
    for _, metier in ipairs(liste) do attendus[metier.cle] = true end

    -- Les onglets qui ne correspondent plus au personnage disparaissent : on
    -- change de personnage, on change de metiers.
    for cle, onglet in pairs(win.onglets) do
        if not attendus[cle] then onglet:Hide() end
    end

    win.ordreOnglets = {}
    local precedent
    for _, metier in ipairs(liste) do
        local onglet = win.onglets[metier.cle]
        if not onglet then
            onglet = CreerOngletLateral(win, precedent, metier.icone, function()
                -- Double clic : relit ce metier (ouvert un instant, puis
                -- referme). Le clic simple affiche ses recettes.
                local maintenant = GetTime and GetTime() or 0
                local ligneOnglet = metier.ligne
                if onglet.dernierClic and maintenant - onglet.dernierClic < 0.4 then
                    onglet.dernierClic = nil
                    if NS.inventaire and NS.inventaire.Relever then
                        pcall(NS.inventaire.Relever, ecran.banqueOuverte == true)
                    end
                    local nom = (NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(ligneOnglet)) or metier.libelle
                    if NS.recettes.ActualiserMetier(ligneOnglet, function()
                        NS.Dire(string.format(L.REFRESH_DONE, nom or ""))
                        ecran.Actualiser()
                    end) then
                        return
                    end
                    NS.Dire(L.REFRESH_LIMITED)
                    return
                end
                onglet.dernierClic = maintenant
                ecran.metier = metier.cle
                -- Un metier ne filtre que certaines pages ; ailleurs (equipement,
                -- caisses, approvisionnement...), choisir un metier ouvre ses
                -- recettes au lieu de ne rien changer a l'ecran.
                -- Depuis une page de tous les metiers, sa version pour ce metier.
                local versMetier = { stocksTous = "stocks", progression = "monter" }
                ecran.Montrer(PAGES_PAR_METIER[ecran.page] and ecran.page or versMetier[ecran.page] or "recettes")
            end)
            onglet.cle = metier.cle
            onglet.ligne = metier.ligne
            win.onglets[metier.cle] = onglet
        end
        -- Reancrage a chaque fois : un onglet retire ne doit pas laisser de
        -- trou dans la colonne.
        if onglet.ClearAllPoints then
            onglet:ClearAllPoints()
            if precedent then
                onglet:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -((NS.suite and NS.suite.ECART_ENTRE_ONGLETS) or 14))
            elseif NS.suite and NS.suite.AncreHaut then
                -- Le premier : a la hauteur du premier onglet de la suite, a
                -- gauche, au ras du trait sous l'en-tete.
                local ancre, point = NS.suite.AncreHaut(win, "droite")
                onglet:SetPoint("TOPLEFT", ancre, point, 0, NS.suite.HAUT_ONGLET or -7)
            else
                onglet:SetPoint("TOPLEFT", win, "TOPRIGHT", 0, -60)
            end
        end
        onglet.libelleParDefaut = metier.libelle
        -- Au survol, le metier et son niveau pour le personnage affiche.
        onglet.tooltipText = NS.recettes.LibelleAvecNiveau(metier.libelle, metier.rang, metier.rangMax)
        if metier.icone and onglet.Icon then
            onglet.Icon:SetTexture(metier.icone)
            onglet.Icon:SetTexCoord(0, 1, 0, 1)
        end
        onglet:Show()
        table.insert(win.ordreOnglets, metier.cle)
        precedent = onglet
    end

    -- La progression, l'equipement et les caisses ne sont pas des metiers :
    -- leurs onglets se posent plus bas, separes, pour qu'on ne les confonde
    -- pas avec eux. La progression couvre tous les metiers a la fois.
    -- Monter un metier est dans le menu de gauche : plus d'onglet a droite.
    if win.ongletEquipement and precedent and win.ongletEquipement.ClearAllPoints then
        win.ongletEquipement:ClearAllPoints()
        win.ongletEquipement:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -30)
    end
    -- Cree meme sans metier : il sert StuffCore.
    if not win.ongletEquipement then
        local onglet = CreerOngletLateral(win, precedent,
            "Interface\\Icons\\INV_Chest_Chain", function()
                ecran.Montrer("equipement")
            end)
        if onglet.ClearAllPoints and precedent then
            onglet:ClearAllPoints()
            onglet:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -30)
        end
        onglet.libelleParDefaut = L.NAV_EQUIPMENT
        onglet.tooltipText = L.NAV_EQUIPMENT
        win.ongletEquipement = onglet
    end

    if not win.ongletCaisses and win.ongletEquipement then
        local onglet = CreerOngletLateral(win, win.ongletEquipement,
            "Interface\\Icons\\INV_Crate_02", function()
                ecran.Montrer("caisses")
            end)
        onglet.libelleParDefaut = L.NAV_CRATES
        onglet.tooltipText = L.NAV_CRATES
        win.ongletCaisses = onglet
    end
end

-- Choix du personnage : une bande dediee en haut de la fenetre, avec un
-- portrait encadre par personnage.
--
-- Pas de masque sur ces images : ce client refuse de decouper une texture
-- masquee, et les icones de classe sont des decoupes. Le cadre d'emplacement du
-- jeu donne la forme, comme sur la page de l'equipement.
local TAILLE_PORTRAIT = 30

PoserVisage = function(texture, fiche, estConnecte)
    -- Le vrai portrait pour le personnage connecte, quand le client le donne.
    if estConnecte and SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, texture, "player")
        if ok then return end
    end

    -- Sinon son icone de classe, decoupee dans la planche du jeu.
    local jeton = fiche and fiche.jetonClasse
    -- Fiche relevee avant que l'addon note la classe du jeu : on la retrouve
    -- par son nom traduit, dans les tables de noms de classes du jeu.
    if not jeton and fiche and type(fiche.classe) == "string" then
        for _, table_ in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
            if type(table_) == "table" then
                for cle, nom in pairs(table_) do
                    if nom == fiche.classe then jeton = cle break end
                end
            end
            if jeton then break end
        end
        if jeton then fiche.jetonClasse = jeton end
    end
    local coords = CLASS_ICON_TCOORDS and jeton and CLASS_ICON_TCOORDS[jeton]
    if coords then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        return
    end

    -- Classe pas encore connue : l'icone de secours du jeu, celle qui existe
    -- depuis toujours.
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    pcall(texture.SetTexCoord, texture, 0, 1, 0, 1)
end

local function CreerPortraitDePersonnage(parent)
    local bouton = CreateFrame("Button", nil, parent)
    bouton:SetSize(TAILLE_PORTRAIT, TAILLE_PORTRAIT)

    -- Cadre d'emplacement du jeu, le meme que sur la page de l'equipement.
    bouton.cadre = bouton:CreateTexture(nil, "BACKGROUND")
    bouton.cadre:SetAllPoints()
    bouton.cadre:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")

    bouton.visage = bouton:CreateTexture(nil, "ARTWORK")
    bouton.visage:SetPoint("TOPLEFT", 4, -4)
    bouton.visage:SetPoint("BOTTOMRIGHT", -4, 4)

    bouton.halo = bouton:CreateTexture(nil, "OVERLAY")
    bouton.halo:SetAllPoints()
    bouton.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    bouton.halo:SetBlendMode("ADD")
    bouton.halo:Hide()

    bouton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bouton
end

-- Les portraits suivent les personnages connus, le connecte en premier.
local function SynchroniserOngletsDePersonnage(win)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return end
    if not win.bandePersos then return end

    local courant = NS.ClePersonnage()
    -- Seulement la faction regardee (onglets Alliance / Horde de la suite).
    local S = NS.suite
    local function Visible(cle) return not (S and S.Visible) or S.Visible(cle) end
    local liste = {}
    if d.personnages[courant] and Visible(courant) then table.insert(liste, courant) end
    local autres = {}
    for cle in pairs(d.personnages) do
        if cle ~= courant and Visible(cle) then table.insert(autres, cle) end
    end
    table.sort(autres)
    for _, cle in ipairs(autres) do table.insert(liste, cle) end
    -- Ordre retenu pour passer d'un personnage a l'autre a la manette.
    win.ordrePersos = liste

    win.ongletsPersos = win.ongletsPersos or {}
    local affiche = NS.base.PersonnageAffiche()
    local precedent

    for _, cle in ipairs(liste) do
        local fiche = d.personnages[cle]
        local portrait = win.ongletsPersos[cle]
        if not portrait then
            portrait = CreerPortraitDePersonnage(win.bandePersos)
            portrait.cle = cle
            portrait:SetScript("OnClick", function()
                NS.base.PoserPersonnageAffiche(cle)
                if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
                end
                ecran.Montrer(ecran.page)
            end)
            win.ongletsPersos[cle] = portrait
        end

        PoserVisage(portrait.visage, fiche, cle == courant)

        local nom = NS.inventaire.NomCourt(cle)
        local detail = nom
        if fiche and fiche.niveau then detail = detail .. "  " .. fiche.niveau end
        if fiche and fiche.classe then detail = detail .. "  " .. fiche.classe end
        portrait.tooltipText = detail
        -- Au survol aussi : chacun de ses metiers avec son niveau.
        local metiersDuPerso = {}
        for cleMetier, sien in pairs((fiche and fiche.metiers) or {}) do
            if type(sien) == "table" and (tonumber(cleMetier) or 0) > 0 and sien.nom then
                table.insert(metiersDuPerso, sien)
            end
        end
        table.sort(metiersDuPerso, function(a, b) return (a.nom or "") < (b.nom or "") end)
        portrait:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipText)
            for _, sien in ipairs(metiersDuPerso) do
                GameTooltip:AddLine(NS.recettes.LibelleAvecNiveau(sien.nom, sien.rang, sien.rangMax), 1, 1, 1)
            end
            GameTooltip:Show()
        end)

        local choisi = (cle == affiche)
        portrait.halo:Hide()
        portrait.visage:SetDesaturated(false)
        MarquerSelection(portrait, choisi, portrait)

        portrait:ClearAllPoints()
        if precedent then
            portrait:SetPoint("LEFT", precedent, "RIGHT", 6, 0)
        else
            portrait:SetPoint("LEFT", win.bandePersos, "LEFT", 2, 0)
        end
        portrait:Show()
        precedent = portrait
    end
    win.dernierPortrait = precedent

    for cle, portrait in pairs(win.ongletsPersos) do
        if not d.personnages[cle] or not Visible(cle) then portrait:Hide() end
    end
end

-- ---------------------------------------------------------------------------
-- Indications manette, a la facon des fenetres du jeu
-- ---------------------------------------------------------------------------
--
-- Comme la fenetre des metiers du jeu a la manette : une barre sous la
-- fenetre avec les actions et leur bouton (A Selectionner, B Retour...), et
-- l'icone de chaque gachette pres de ce qu'elle fait defiler. Montre seulement
-- quand la manette est active.

-- Barre d'actions sous un cadre. `actions` : liste de { touche, libelle }.
function ecran.BarreManette(cadre, actions)
    if not cadre then return end
    local barre = cadre.barreManette
    if not barre then
        local ok, cree = pcall(CreateFrame, "Frame", nil, cadre, "TooltipBackdropTemplate")
        barre = ok and cree or CreateFrame("Frame", nil, cadre)
        barre:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 10, 2)
        barre:SetHeight(38)
        barre:SetFrameLevel(cadre:GetFrameLevel() + 10)
        barre.textes = {}
        cadre.barreManette = barre
    end
    if not (NS.manette and NS.manette.Active()) or not actions or #actions == 0 then
        barre:Hide()
        return
    end
    local x = 12
    for rang, action in ipairs(actions) do
        local t = barre.textes[rang]
        if not t then
            t = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            barre.textes[rang] = t
        end
        t:ClearAllPoints()
        t:SetPoint("LEFT", barre, "LEFT", x, 0)
        -- Une action peut porter deux boutons (croix haut et bas).
        local touches = type(action[1]) == "table" and action[1] or { action[1] }
        local glyphes = {}
        for _, touche in ipairs(touches) do
            table.insert(glyphes, touche == "+" and "+" or NS.manette.Glyphe(touche, 22))
        end
        t:SetText(table.concat(glyphes, " ") .. "  " .. action[2])
        t:Show()
        x = x + (t:GetStringWidth() or 100) + 26
    end
    for rang = #actions + 1, #barre.textes do barre.textes[rang]:Hide() end
    barre:SetWidth(x - 14)
    barre:Show()
end

-- Icone de gachette posee pres d'un element.
local function Marque(win, cle, touche, ancre, point, relatif, dx, dy)
    win.marquesManette = win.marquesManette or {}
    local m = win.marquesManette[cle]
    if not m then
        m = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        win.marquesManette[cle] = m
    end
    if not ancre then m:Hide() return end
    m:ClearAllPoints()
    m:SetPoint(point, ancre, relatif, dx, dy)
    m:SetText(NS.manette.Glyphe(touche, 20))
    m:Show()
end

local function PoserIndicesManette(win)
    local actif = NS.manette and NS.manette.Active()
    if not actif then
        for _, m in pairs(win.marquesManette or {}) do m:Hide() end
        ecran.BarreManette(win, nil)
        return
    end
    -- LB / RB : au bout de la premiere et de la derniere ligne du menu.
    local premiere = win.boutons[PAGES[1].cle]
    local derniere = win.boutons[PAGES[#PAGES].cle]
    -- Mon equipement : son propre menu, LB / RB y ramenent aux pages.
    if ecran.EstStuff(ecran.page) and win.menuEquip then
        premiere, derniere = nil, nil
        for _, b in ipairs(win.menuEquip) do
            if b:IsShown() then premiere = premiere or b derniere = b end
        end
    end
    if ecran.page == "caisses" then premiere, derniere = nil, nil end
    Marque(win, "lb", "PADLSHOULDER", premiere, "RIGHT", "RIGHT", -2, 0)
    Marque(win, "rb", "PADRSHOULDER", derniere, "RIGHT", "RIGHT", -2, 0)
    -- LT / RT : au dessus du premier onglet de droite, sous le dernier.
    local premierOnglet = win.onglets and win.ordreOnglets and win.onglets[win.ordreOnglets[1] or ""]
    premierOnglet = premierOnglet or win.ongletCaisses
    local dernierOnglet = win.ongletCaisses
    -- StuffCore n'a pas d'onglet a droite : LT / RT seulement en
    -- presentation 2, de part et d'autre des onglets d'origine.
    if ecran.EstStuff(ecran.page) then
        -- LT / RT des onglets d'origine : dans la barre du bas, pas a cote.
        Marque(win, "lt", "PADLTRIGGER", nil)
        Marque(win, "rt", "PADRTRIGGER", nil)
    else
        Marque(win, "lt", "PADLTRIGGER", premierOnglet, "BOTTOM", "TOP", 0, 12)
        Marque(win, "rt", "PADRTRIGGER", dernierOnglet, "TOP", "BOTTOM", 0, -10)
    end
    -- Croix gauche / droite : apres le dernier portrait de personnage.
    Marque(win, "dg", "PADDLEFT", win.dernierPortrait, "LEFT", "RIGHT", 10, 0)
    Marque(win, "dd", "PADDRIGHT", win.marquesManette.dg, "LEFT", "RIGHT", 2, 0)

    local actions
    if NS.manette.EnZone and NS.manette.EnZone() then
        actions = { { { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }, L.PAD_MOVE }, { "PAD1", L.PAD_SELECT } }
        if ecran.page == "recettes" then table.insert(actions, { "PAD3", L.PAD_ADD }) end
        if ecran.page == "equipement" and NS.equipement and NS.equipement.Scenario() == 2 then
            table.insert(actions, { { "PADLTRIGGER", "PADRTRIGGER" }, L.PAD_ORIGINS })
        end
        table.insert(actions, { { "PADBACK", "PAD2" }, L.PAD_ZONE_OUT })
    else
        actions = { { { "PADDUP", "PADDDOWN" }, L.PAD_SCROLL }, { "PADBACK", L.PAD_ZONE_IN } }
        table.insert(actions, { { "PADLSTICK", "PADRSTICK" }, L.PAD_SUITE })
        table.insert(actions, { "PAD4", L.PAD_HELP })
        table.insert(actions, { "PAD2", L.PAD_BACK })
    end
    ecran.BarreManette(win, actions)
end

local function Construire()
    L = NS.L
    local win = CreerFenetre()
    local inset = win.fond

    -- Bande des personnages, dans l'en-tete sous le titre, a droite du
    -- portrait : la place que les fenetres du jeu donnent a leurs filtres.
    local bande = CreateFrame("Frame", nil, win)
    bande:SetPoint("LEFT", win.entete, "LEFT", 0, 0)
    bande:SetPoint("RIGHT", win.entete, "RIGHT", 0, 0)
    bande:SetHeight(HAUTEUR_PASTILLES)
    win.bandePersos = bande

    -- Menu de gauche : une liste verticale de lignes, jamais de pastilles.
    local menu = CreateFrame("Frame", nil, win)
    menu:SetPoint("TOPLEFT", inset, "TOPLEFT", MARGE, -MARGE)
    menu:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", MARGE, MARGE)
    menu:SetWidth(LARGEUR_MENU)
    win.menu = menu

    -- Trait de separation entre le menu et le contenu. Texture d'un pixel,
    -- patron repris du journal de donjon qui separe ainsi sa liste de son detail.
    local trait = win:CreateTexture(nil, "ARTWORK")
    -- Plus de trait visible entre le menu et le contenu : il ne sert que de repere.
    trait:SetColorTexture(0, 0, 0, 0)
    trait:SetWidth(1)
    trait:SetPoint("TOPLEFT", inset, "TOPLEFT", MARGE + LARGEUR_MENU + ECART, -MARGE)
    trait:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", MARGE + LARGEUR_MENU + ECART, MARGE)
    win.trait = trait

    win.boutons = {}
    win.filetsMenu = {}
    local precedent
    for _, page in ipairs(PAGES) do
        local bouton = CreerLigneDeMenu(menu, page.icone)
        bouton:SetPoint("LEFT", menu, "LEFT", 0, 0)
        bouton:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        if precedent and page.filet then
            -- Filet entre deux groupes, avec de l'air de part et d'autre.
            -- Un pixel d'ecran exact, cale sur la grille : tous les filets
            -- ont la meme epaisseur, ou qu'ils tombent.
            local filet = menu:CreateTexture(nil, "ARTWORK")
            table.insert(win.filetsMenu, filet)
            PeindreFilet(filet, 0.8, 0.65, 0.35, 0.35)
            if filet.SetSnapToPixelGrid then filet:SetSnapToPixelGrid(false) filet:SetTexelSnappingBias(0) end
            local PU = _G.PixelUtil
            if PU and PU.SetHeight and PU.SetPoint then
                PU.SetHeight(filet, 1, 1)
                PU.SetPoint(filet, "TOPLEFT", precedent, "BOTTOMLEFT", 6, -6)
                PU.SetPoint(filet, "TOPRIGHT", precedent, "BOTTOMRIGHT", -6, -6)
            else
                filet:SetHeight(1)
                filet:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 6, -6)
                filet:SetPoint("TOPRIGHT", precedent, "BOTTOMRIGHT", -6, -6)
            end
            bouton:SetPoint("TOP", precedent, "BOTTOM", 0, -13)
        elseif precedent then
            bouton:SetPoint("TOP", precedent, "BOTTOM", 0, -2)
        else
            bouton:SetPoint("TOP", menu, "TOP", 0, 0)
        end
        local texte = bouton.text or bouton.Text or (bouton.GetFontString and bouton:GetFontString())
        if texte then texte:SetText(L[page.libelle]) end
        bouton.cle = page.cle
        bouton:SetScript("OnClick", function() ecran.Montrer(page.cle) end)
        win.boutons[page.cle] = bouton
        precedent = bouton
    end

    -- Menu de la page Mon equipement : les trois scenarios de navigation a
    -- essayer, un filet, puis les origines (scenarios 1 et 3).
    win.menuEquip = {}
    local function LigneEquip(icone, auClic)
        local b = CreerLigneDeMenu(menu, icone)
        b:SetPoint("LEFT", menu, "LEFT", 0, 0)
        b:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        b:SetScript("OnClick", auClic)
        b:Hide()
        table.insert(win.menuEquip, b)
        return b
    end
    -- La presentation (1, 2 ou 3) se choisit dans les Parametres.
    win.scenariosEquip = {}
    local precedentE
    local ICONES_ORIGINE = {
        possede = "Interface\\Icons\\INV_Misc_Bag_08", craftInterne = "Interface\\Icons\\Trade_BlackSmithing",
        craftExterne = "Interface\\Icons\\INV_Misc_Coin_02", monde = "Interface\\Icons\\INV_Misc_Map_01",
        quetes = "Interface\\GossipFrame\\AvailableQuestIcon", donjons = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    }
    -- Presentation 2 (origines en onglets sur la page) : une seule ligne,
    -- Mon equipement, pour y aller depuis les Parametres.
    win.ligneMonEquip = LigneEquip("Interface\\Icons\\INV_Chest_Chain", function()
        ecran.Montrer("equipement")
    end)
    win.ligneMonEquip:SetPoint("TOP", menu, "TOP", 0, 0)
    win.originesEquip = {}
    local premiereOrigine = true
    for _, cat in ipairs(NS.sources and NS.sources.ORDRE or {}) do
        local b = LigneEquip(ICONES_ORIGINE[cat], function()
            if not NS.equipement then return end
            if NS.equipement.Scenario() == 3 then NS.equipement.BasculerFiltre(cat)
            else NS.equipement.PoserCategorie(cat) end
            NS.ecran.selectionObjets = {}
            ecran.Montrer("equipement")
        end)
        if precedentE then b:SetPoint("TOP", precedentE, "BOTTOM", 0, -2) else b:SetPoint("TOP", menu, "TOP", 0, 0) end
        premiereOrigine = false
        b.origine = cat
        win.originesEquip[cat] = b
        precedentE = b
    end

    win.reglagesStuff = LigneEquip("Interface\\Icons\\Trade_Engineering", function()
        ecran.Montrer("reglagesStuff")
    end)
    win.filetStuff = menu:CreateTexture(nil, "ARTWORK")
    PeindreFilet(win.filetStuff, 0.8, 0.65, 0.35, 0.35)
    if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(win.filetStuff, 1, 1) else win.filetStuff:SetHeight(1) end
    if win.filetStuff.SetSnapToPixelGrid then win.filetStuff:SetSnapToPixelGrid(false) win.filetStuff:SetTexelSnappingBias(0) end
    win.filetStuff:Hide()

    -- Onglets de metier sur le bord droit.
    win.onglets = {}
    win.ordreOnglets = {}
    SynchroniserOnglets(win)

    -- Barre du bas : le pied de la charte, hors du fond, comme les fenetres
    -- du jeu. Fermer a droite, le i des commandes a gauche.
    local barre = win.pied
    win.barre = barre

    local fermerBas = NS.charte.BoutonDePied(win, L.CLOSE, 110)
    fermerBas:SetScript("OnClick", function() win:Hide() end)


    -- Fabrication en cours : la fenetre couvre souvent la barre d'incantation
    -- du jeu, alors on la redit ici, dans le pied, avec la texture du jeu.
    -- La meme barre que QuestCore : texture des competences du jeu, fine
    -- bordure d'infobulle aux coins arrondis, texte dedans. 12 pixels de haut
    -- (16 avec la bordure) : elle tient dans le pied sans en deborder.
    local okF, fab = pcall(CreateFrame, "StatusBar", nil, barre, "BackdropTemplate")
    fab = okF and fab or CreateFrame("StatusBar", nil, barre)
    fab.sansEncre = true
    fab:SetSize(260, 12)
    fab:SetPoint("CENTER", barre, "CENTER", 0, 0)
    fab:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    fab:SetStatusBarColor(1, 0.7, 0)
    fab:SetMinMaxValues(0, 1)
    fab.fond = fab:CreateTexture(nil, "BACKGROUND")
    fab.fond:SetAllPoints()
    fab.fond:SetColorTexture(0, 0, 0, 0.65)
    local okB, bordure = pcall(CreateFrame, "Frame", nil, fab, "BackdropTemplate")
    bordure = okB and bordure or CreateFrame("Frame", nil, fab)
    bordure:SetPoint("TOPLEFT", -2, 2)
    bordure:SetPoint("BOTTOMRIGHT", 2, -2)
    if bordure.SetBackdrop then
        bordure:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
        bordure:SetBackdropBorderColor(0.8, 0.65, 0.35, 1)
    end
    bordure:SetFrameLevel(fab:GetFrameLevel() + 2)
    fab.texte = bordure:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fab.texte:SetPoint("CENTER", fab, "CENTER", 0, 0)
    fab.texte:SetWordWrap(false)
    fab.texte:SetWidth(250)
    local fichier, _, drapeaux = fab.texte:GetFont()
    if fichier then fab.texte:SetFont(NS.Police(fichier), 9, drapeaux) end
    fab.texte:SetShadowOffset(1, -1)
    fab:Hide()
    win.barreFabrication = fab
    local function Suivre()
        local lecture = NS.Lecture("UnitCastingInfo")
        if not lecture then return end
        local ok, nom, _, _, debut, fin, metier = pcall(lecture, "player")
        if ok and nom and metier and debut and fin and fin > debut then
            fab.debut, fab.fin = debut, fin
            -- Dans une serie : le rang de la fabrication en cours, "3 / 12".
            local serie = NS.actions and NS.actions.serie
            if serie and serie.total > 1 and serie.faits < serie.total then
                serie.faits = serie.faits + 1
                fab.texte:SetText(string.format(L.CRAFT_IN_PROGRESS_N, nom, serie.faits, serie.total))
            else
                fab.texte:SetText(string.format(L.CRAFT_IN_PROGRESS, nom))
            end
            fab:SetValue(0)
            fab:Show()
        end
    end
    fab:SetScript("OnUpdate", function(self)
        if not self.fin then return end
        local temps = NS.Lecture("GetTime")
        local maintenant = temps and (temps() * 1000) or self.fin
        local part = (maintenant - self.debut) / (self.fin - self.debut)
        self:SetValue(math.max(0, math.min(1, part)))
    end)
    local ecoute = CreateFrame("Frame", nil, win)
    for _, evenement in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(ecoute.RegisterUnitEvent or ecoute.RegisterEvent, ecoute, evenement, "player")
    end
    ecoute:SetScript("OnEvent", function(_, evenement, unite)
        if unite and unite ~= "player" then return end
        if evenement == "UNIT_SPELLCAST_START" then
            Suivre()
        elseif evenement == "UNIT_SPELLCAST_STOP" then
            -- Une serie enchaine les incantations : la suivante relance la barre.
            fab.fin = nil
            fab:Hide()
        else
            -- Echec ou interruption : la serie s'arrete.
            if NS.actions then NS.actions.serie = nil end
            fab.fin = nil
            fab:Hide()
        end
    end)
    barre.fermer = fermerBas

    -- Commandes : un petit i du jeu, le detail dans son infobulle. Le texte
    -- complet dans la barre etait trop long et paraissait pose sur la page.
    local info = CreateFrame("Button", nil, barre)
    info:SetSize(18, 18)
    info:SetPoint("LEFT", barre, "LEFT", 0, 0)
    info:SetNormalTexture("Interface\\Common\\help-i")
    info:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    info:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(L.CONTROLS_TITLE)
        for _, ligne in ipairs(self.lignes or {}) do
            GameTooltip:AddDoubleLine(ligne[1], ligne[2], 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    info:SetScript("OnLeave", function() GameTooltip:Hide() end)
    barre.info = info

    barre.touches = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    barre.touches.pasExplication = true
    barre.touches:SetPoint("LEFT", info, "RIGHT", 4, 0)
    barre.depart = 2
    barre.touches:SetJustifyH("LEFT")
    barre.touches:SetWordWrap(false)

    -- Aide de la page : un bouton du jeu, en bas, a cote des commandes.
    local aide = CreateFrame("Button", nil, barre, "UIPanelButtonTemplate")
    aide:SetHeight(20)
    aide:SetText(L.PAD_HELP)
    aide:SetWidth((aide.GetTextWidth and aide:GetTextWidth() or 40) + 24)
    aide:SetPoint("LEFT", barre.touches, "RIGHT", 12, 0)
    aide:SetScript("OnClick", function()
        if NS.aide then NS.aide.Basculer(ecran.page) end
    end)
    aide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.HELP_BUTTON_TIP)
        GameTooltip:Show()
    end)
    aide:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.boutonAide = aide

    -- Bandeau du bas, hors de la zone defilante : il ne bouge pas quand on fait
    -- defiler, et la place lui est reservee avant d'etre occupee, donc il ne
    -- peut rien recouvrir.
    local bandeau = CreateFrame("Frame", nil, win)
    bandeau:SetPoint("BOTTOMLEFT", trait, "BOTTOMRIGHT", ECART, 0)
    bandeau:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -MARGE, MARGE)
    bandeau:SetHeight(HAUTEUR_BANDEAU)
    bandeau:Hide()
    win.bandeau = bandeau

    local traitBandeau = win:CreateTexture(nil, "ARTWORK")
    traitBandeau:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    traitBandeau:SetHeight(1)
    traitBandeau:SetPoint("BOTTOMLEFT", bandeau, "TOPLEFT", 0, 4)
    traitBandeau:SetPoint("BOTTOMRIGHT", bandeau, "TOPRIGHT", 0, 4)
    traitBandeau:Hide()
    bandeau.trait = traitBandeau

    -- Zone de droite, defilante, modele natif.
    -- Ascenseur fin du jeu recent (celui des grimoires), sinon le classique.
    local okD, defilement = pcall(CreateFrame, "ScrollFrame", nil, win, "ScrollFrameTemplate")
    if not okD or not defilement then
        defilement = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    end
    defilement:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART, 0)
    defilement:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, MARGE)
    -- Zone fixe, pour les pages qui ne doivent jamais defiler.
    local zoneFixe = CreateFrame("Frame", nil, win)
    zoneFixe:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART, 0)
    zoneFixe:SetPoint("BOTTOMRIGHT", bandeau, "TOPRIGHT", 0, 8)
    zoneFixe:Hide()
    win.zoneFixe = zoneFixe

    -- Fond du menu de gauche : celui du journal de quetes de la carte du monde
    -- (gris sombre en relief). Repris de la carte elle-meme quand elle est
    -- chargee, sinon par son nom ; rien trouve, le fond reste sombre.
    local fondMenu = inset:CreateTexture(nil, "BACKGROUND", nil, 5)
    fondMenu:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3)
    fondMenu:SetPoint("BOTTOMRIGHT", trait, "BOTTOMLEFT", -1, -(MARGE - 3))
    fondMenu:Hide()
    win.fondMenu = fondMenu

    -- Le parchemin couvre toute la zone de droite, du filet du menu au bord.
    NS.charte.Parchemin(win, { "TOPLEFT", trait, "TOPRIGHT", 2, MARGE - 4 },
        { "BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4 }, inset)

    local contenu = CreateFrame("Frame", nil, defilement)
    contenu:SetSize(LARGEUR - LARGEUR_MENU - MARGE - ECART * 2 - 40, 1)
    defilement:SetScrollChild(contenu)
    win.defilement = defilement
    win.contenu = contenu


    return win
end

-- La zone defilante s'arrete au dessus du bandeau quand il est montre.
local function ReglerPlaceDuBandeau(win, visible)
    win.bandeau:SetShown(visible)
    win.bandeau.trait:SetShown(visible)
    local inset = win.fond or win.Inset or win
    win.defilement:ClearAllPoints()
    win.defilement:SetPoint("TOPLEFT", win.trait, "TOPRIGHT", ECART, 0)
    if visible then
        win.defilement:SetPoint("BOTTOMRIGHT", win.bandeau, "TOPRIGHT", -18, 10)
    else
        win.defilement:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, MARGE)
    end
end

-- Pages de StuffCore (un add-on a part, servi par cette fenetre).
local PAGES_STUFF = { equipement = true, reglagesStuff = true }
function ecran.EstStuff(page) return PAGES_STUFF[page or ""] == true end

_G.CraftCoreAPI = _G.CraftCoreAPI or {}
-- Ouvre StuffCore : sa derniere page, ou la premiere / la derniere en
-- arrivant par LT / RT.
_G.CraftCoreAPI.OuvrirStuff = function()
    local entree = NS.suite and NS.suite.PrendreEntree and NS.suite.PrendreEntree()
    local page = (entree and "equipement") or ecran.pageStuff or "equipement"
    ecran.Montrer(page)
end
-- La fenetre, seulement quand elle montre StuffCore.
_G.CraftCoreAPI.FenetreStuff = function()
    if fenetre and fenetre:IsShown() and ecran.EstStuff(ecran.page) then return fenetre end
    return nil
end

function ecran.Montrer(cle)
    if not fenetre then fenetre = Construire() end
    -- Anciennes pages, desormais dans Mes projets.
    if cle == "rapides" or cle == "approv" then cle = "projets" end
    -- Mes progressions et l'onglet Progression ne font plus qu'une page.
    if cle == "progressions" then cle = "progression" end
    -- Memoire : on rouvre la ou on s'etait arrete, meme apres /reload.
    local memoire
    if type(CraftCoreDB) == "table" then
        CraftCoreDB.memoire = type(CraftCoreDB.memoire) == "table" and CraftCoreDB.memoire or {}
        memoire = CraftCoreDB.memoire
    end
    if not ecran.page and memoire then
        ecran.page = (memoire.page == "progressions") and "progression" or memoire.page
        ecran.metier = ecran.metier or memoire.metier
    end
    ecran.page = cle or ecran.page or "stocks"
    -- L'objet choisi dans les stocks ne suit pas sur une autre page.
    if ecran.page ~= "stocks" and ecran.page ~= "stocksTous" then ecran.objetStock = nil end
    for _, p in ipairs(PAGES) do if p.cle == ecran.page then ecran.pageMenu = ecran.page end end
    if NS.base.SuivreLaSuite then pcall(NS.base.SuivreLaSuite) end
    -- Arrive par LT / RT depuis un autre add-on : premier ou dernier onglet
    -- de la colonne (premier metier, ou caisses).
    local entree = NS.suite and NS.suite.PrendreEntree and NS.suite.PrendreEntree()
    if entree == "debut" then
        local premier = fenetre and fenetre.ordreOnglets and fenetre.ordreOnglets[1]
        if premier then
            ecran.metier = premier
            ecran.page = PAGES_PAR_METIER[ecran.page] and ecran.page or "recettes"
        end
    elseif entree == "fin" then
        local ordre = fenetre and fenetre.ordreOnglets or {}
        local dernier = ordre[#ordre]
        if dernier then
            ecran.metier = dernier
            ecran.page = PAGES_PAR_METIER[ecran.page] and ecran.page or "recettes"
        end
        -- Le dernier onglet de droite : les caisses.
        ecran.page = "caisses"
    end
    if ecran.EstStuff(ecran.page) then ecran.pageStuff = ecran.page end

    for autre, bouton in pairs(fenetre.boutons) do
        MarquerLigneDeMenu(bouton, autre == ecran.page)
    end
    -- StuffCore (Mon equipement, Caisses, ses Parametres) : un add-on a part
    -- dans la colonne de gauche. Meme fenetre, mais son titre, son onglet
    -- allume a gauche, son menu et ses seuls onglets a droite.
    do
        local stuff = ecran.EstStuff(ecran.page)
        if fenetre.titre then fenetre.titre:SetText(stuff and "StuffCore" or L.WINDOW_TITLE) end
        -- Les caisses sont seules : pas de menu de CraftCore a cote.
        local seul = stuff or ecran.page == "caisses"
        for _, b in pairs(fenetre.boutons) do b:SetShown(not seul) end
        for _, f in ipairs(fenetre.filetsMenu or {}) do f:SetShown(not seul) end
        local scen = NS.equipement and NS.equipement.Scenario() or 1
        -- Les origines (presentations 1 et 3) restent dans le menu sur toutes
        -- les pages de StuffCore : c'est par elles qu'on va a l'equipement.
        local avecOrigines = stuff and scen ~= 2
        local dernierE
        local monEquip = fenetre.ligneMonEquip
        if monEquip then
            local texte = monEquip.text or monEquip.Text or (monEquip.GetFontString and monEquip:GetFontString())
            if texte then texte:SetText(L.NAV_EQUIPMENT) end
            local avec = stuff and scen == 2
            monEquip:SetShown(avec)
            MarquerLigneDeMenu(monEquip, ecran.page == "equipement")
            if avec then dernierE = monEquip end
        end
        for _, cat in ipairs(NS.sources and NS.sources.ORDRE or {}) do
            local b = fenetre.originesEquip and fenetre.originesEquip[cat]
            if b then
                local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
                if texte then texte:SetText(L["GEAR_CAT_" .. cat]) end
                b:SetShown(avecOrigines)
                local choisi = (scen == 3) and NS.equipement.FiltreActif(cat)
                    or (scen == 1 and ecran.page == "equipement" and NS.equipement.Categorie() == cat)
                MarquerLigneDeMenu(b, choisi)
                if avecOrigines then dernierE = b end
            end
        end
        -- Parametres de StuffCore : en bas du menu, sous un filet.
        local reg = fenetre.reglagesStuff
        if reg then
            local texte = reg.text or reg.Text or (reg.GetFontString and reg:GetFontString())
            if texte then texte:SetText(L.NAV_SETTINGS) end
            reg:ClearAllPoints()
            reg:SetPoint("LEFT", fenetre.menu, "LEFT", 0, 0)
            reg:SetPoint("RIGHT", fenetre.menu, "RIGHT", 0, 0)
            if dernierE then reg:SetPoint("TOP", dernierE, "BOTTOM", 0, -13)
            else reg:SetPoint("TOP", fenetre.menu, "TOP", 0, 0) end
            reg:SetShown(stuff)
            MarquerLigneDeMenu(reg, ecran.page == "reglagesStuff")
            fenetre.filetStuff:ClearAllPoints()
            fenetre.filetStuff:SetPoint("BOTTOMLEFT", reg, "TOPLEFT", 6, 6)
            fenetre.filetStuff:SetPoint("BOTTOMRIGHT", reg, "TOPRIGHT", -6, 6)
            fenetre.filetStuff:SetShown(stuff and dernierE ~= nil)
        end
        local S = NS.suite or _G.CoreSuite
        if S and S.ChangerCourant then S.ChangerCourant(fenetre, stuff and "StuffCore" or "CraftCore") end
    end

    -- Libelles de la barre, relus a chaque fois : l'utilisateur peut assigner
    -- une touche pendant la session.
    fenetre.barre.fermer:SetText(L.CLOSE)
    local tTogg = NS.ToucheDe and NS.ToucheDe("TOGGLE")
    local tPages = NS.ToucheDe and NS.ToucheDe("NEXTPAGE")
    local tMetiers = NS.ToucheDe and NS.ToucheDe("NEXTTRADE")
    local morceaux = {}
    if tTogg then table.insert(morceaux, tTogg) end
    if tPages then table.insert(morceaux, string.format(L.KEYS_PAGES, tPages)) end
    if tMetiers then table.insert(morceaux, string.format(L.KEYS_TRADES, tMetiers)) end
    -- Dans la barre, un seul mot ; le detail dans l'infobulle du i : les
    -- boutons de la manette quand elle est branchee, puis les touches.
    -- Manette active : ses touches en clair dans le pied, comme la barre que le
    -- jeu affiche sous ses propres fenetres. Sinon, un seul mot.
    if NS.manette and NS.manette.Active() then
        -- La barre manette, sous la fenetre, dit deja tout : le pied reste sobre.
        fenetre.barre.touches:SetFontObject("GameFontDisableSmall")
        fenetre.barre.touches:SetText(L.CONTROLS_TITLE)
    else
        fenetre.barre.touches:SetFontObject("GameFontDisableSmall")
        fenetre.barre.touches:SetText(L.CONTROLS_TITLE)
    end
    local lignes = {}
    if NS.manette and NS.manette.Active() then
        for i = 1, 9 do
            local gauche, droite = L["PAD_LINE_" .. i .. "_KEY"], L["PAD_LINE_" .. i .. "_WHAT"]
            if gauche and droite then table.insert(lignes, { gauche, droite }) end
        end
    end
    if tTogg then table.insert(lignes, { tTogg, L.KEYS_TOGGLE_WHAT }) end
    if tPages then table.insert(lignes, { tPages, L.KEYS_PAGES_WHAT }) end
    if tMetiers then table.insert(lignes, { tMetiers, L.KEYS_TRADES_WHAT }) end
    if #lignes == 0 then table.insert(lignes, { L.KEYS_UNSET, "" }) end
    table.insert(lignes, { "/cc", L.KEYS_SLASH_WHAT })
    fenetre.barre.info.lignes = lignes

    local okPersos, souciPersos = pcall(SynchroniserOngletsDePersonnage, fenetre)
    if not okPersos then
        NS.base.NoterIncident("onglets de personnage", souciPersos)
    end

    local okOnglets, souciOnglets = pcall(SynchroniserOnglets, fenetre)
    -- A droite, pour CraftCore seulement : les metiers, et tout en bas les
    -- caisses, en face de l'onglet Horde de la colonne de gauche. StuffCore
    -- n'a aucun onglet a droite.
    local modeStuff = ecran.EstStuff(ecran.page)
    for _, onglet in pairs(fenetre.onglets or {}) do onglet:SetShown(not modeStuff) end
    if fenetre.ongletEquipement then fenetre.ongletEquipement:Hide() end
    local caisses = fenetre.ongletCaisses
    if caisses then
        if caisses.ClearAllPoints then
            caisses:ClearAllPoints()
            caisses:SetPoint("BOTTOMLEFT", fenetre, "BOTTOMRIGHT", 0, 46)
        end
        local choisi = (ecran.page == "caisses")
        if caisses.SetChecked then caisses:SetChecked(choisi) end
        MarquerSelection(caisses, choisi, caisses.Icon)
        caisses:SetShown(not modeStuff)
    end
    if not okOnglets then
        NS.base.NoterIncident("onglets de métier", souciOnglets)
    end
    if not ecran.metier or not fenetre.onglets[ecran.metier] then
        ecran.metier = (fenetre.ordreOnglets and fenetre.ordreOnglets[1]) or nil
    end
    if memoire then memoire.page, memoire.metier = ecran.page, ecran.metier end
    local metierActif = PAGES_PAR_METIER[ecran.page] == true
    for cle, onglet in pairs(fenetre.onglets) do
        local choisi = metierActif and cle == ecran.metier
        if onglet.SetChecked then onglet:SetChecked(choisi) end
        MarquerSelection(onglet, choisi, onglet.Icon)
        -- Des que le client a donne le vrai nom du metier, l'onglet le porte.
        if cle == ecran.metier then ecran.ongletCourantLigne = onglet.ligne end
        local nom = NS.recettes and NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(onglet.ligne)
        -- Le niveau est celui du personnage affiche. Le niveau du compte
        -- etait celui du dernier personnage a avoir ouvert le metier.
        local fiche = NS.base.FicheAffichee()
        local sien = fiche and type(fiche.metiers) == "table" and fiche.metiers[tostring(onglet.ligne)]
        if type(sien) == "table" then
            onglet.tooltipText = NS.recettes.LibelleAvecNiveau(nom or sien.nom or onglet.libelleParDefaut,
                sien.rang, sien.rangMax)
        else
            onglet.tooltipText = nom or onglet.libelleParDefaut
        end
        onglet.tooltipText = onglet.tooltipText .. "\n|cff8c8c8c" .. L.REFRESH_TAB_HINT .. "|r"
    end

    if fenetre.contenu.aVenir then fenetre.contenu.aVenir:Hide() end

    local ok, souci = pcall(function()
        ReglerPlaceDuBandeau(fenetre, ecran.page == "equipement")
        -- La page de l'equipement tient entierement a l'ecran : elle occupe la
        -- zone fixe, et la zone defilante se retire.
        local surEquipement = (ecran.page == "equipement")
        fenetre.zoneFixe:SetShown(surEquipement)
        fenetre.defilement:SetShown(not surEquipement)
        if ecran.page ~= "equipement" and NS.equipement then
            NS.equipement.Cacher(fenetre.zoneFixe, fenetre.bandeau)
        end
        if ecran.page ~= "projets" and ecran.page ~= "progressions" and ecran.page ~= "commandes" then
            for _, bouton in pairs(fenetre.contenu.actions or {}) do bouton:Hide() end
            if fenetre.contenu.champ then fenetre.contenu.champ:Hide() end
            if fenetre.contenu.champRecherche then fenetre.contenu.champRecherche:Hide() end
            ecran.suppressionEnCours = nil
            ecran.rechercheProjet = nil
        end
        if fenetre.contenu.valeurObjectif and ecran.page ~= "progression" then
            fenetre.contenu.valeurObjectif:Hide()
        end
        if fenetre.contenu.libelleObjectif and ecran.page ~= "progression" then
            fenetre.contenu.libelleObjectif:Hide()
        end
        if fenetre.contenu.curseurObjectif and ecran.page ~= "progression" then
            fenetre.contenu.curseurObjectif:Hide()
        end
        if ecran.page ~= "progression" then
            for _, c in pairs(fenetre.contenu.casesVise or {}) do c:Hide() end
        end
        -- Les paragraphes sont reposes par chaque page qui en a besoin.
        CacherParagraphes(fenetre.contenu)
        if fenetre.contenu.caseCaissesAutres and ecran.page ~= "caisses" then
            fenetre.contenu.caseCaissesAutres:Hide()
            fenetre.contenu.caseCaissesAutres.libelle:Hide()
        end
        if fenetre.contenu.recherche and ecran.page ~= "recettes" then fenetre.contenu.recherche:Hide() end
        if fenetre.contenu.rechercheCommande and ecran.page ~= "commandes" then fenetre.contenu.rechercheCommande:Hide() end
        if fenetre.contenu.rechercheStock and ecran.page ~= "stocks" and ecran.page ~= "stocksTous" then fenetre.contenu.rechercheStock:Hide() end
        if fenetre.contenu.caseConnues and ecran.page ~= "recettes" then
            fenetre.contenu.caseConnues:Hide()
            fenetre.contenu.caseConnues.libelle:Hide()
            fenetre.contenu.caseNonConnues:Hide()
            fenetre.contenu.caseNonConnues.libelle:Hide()
        end
        if fenetre.contenu.titreAffichage and ecran.page ~= "reglages" then
            fenetre.contenu.titreAffichage:Hide()
            if fenetre.contenu.titreAffichage.filet then fenetre.contenu.titreAffichage.filet:Hide() end
        end
        if fenetre.contenu.caseNonApprises and ecran.page ~= "reglages" then
            fenetre.contenu.caseNonApprises:Hide()
            fenetre.contenu.libelleNonApprises:Hide()
        end
        if fenetre.contenu.caseGuide and ecran.page ~= "reglages" then
            fenetre.contenu.caseGuide:Hide()
            fenetre.contenu.libelleGuide:Hide()
            fenetre.contenu.titreTutos:Hide()
            if fenetre.contenu.titreTutos.filet then fenetre.contenu.titreTutos.filet:Hide() end
            if fenetre.contenu.libelleFond then fenetre.contenu.libelleFond:Hide() end
            if fenetre.contenu.libelleFondSuivis then fenetre.contenu.libelleFondSuivis:Hide() end
            if fenetre.contenu.listeFond then fenetre.contenu.listeFond:Hide() end
            if fenetre.contenu.listePanneau then fenetre.contenu.listePanneau:Hide() fenetre.contenu.libellePanneau:Hide() end
            if fenetre.contenu.titreInterface then
                fenetre.contenu.titreInterface:Hide()
                if fenetre.contenu.titreInterface.filet then fenetre.contenu.titreInterface.filet:Hide() end
            end
            for _, x in ipairs({ fenetre.contenu.libelleCompo, fenetre.contenu.listeCompo, fenetre.contenu.libelleSauver, fenetre.contenu.sauverCompo,
                fenetre.contenu.caseDefaut, fenetre.contenu.caseDefaut and fenetre.contenu.caseDefaut.libelle }) do
                if x then x:Hide() end
            end
            if fenetre.contenu.listeFondSuivis then fenetre.contenu.listeFondSuivis:Hide() end
        end
        if ecran.page ~= "reglagesStuff" then
            local cc = fenetre.contenu
            for _, x in ipairs({ cc.titreEquipReg, cc.titreEquipReg and cc.titreEquipReg.filet, cc.libelleMarge, cc.curseurMarge,
                cc.libellePresentation, cc.listePresentation, cc.textePresentation, cc.caseTousNiveaux,
                cc.caseTousNiveaux and cc.caseTousNiveaux.libelle }) do
                if x then x:Hide() end
            end
        end
        if fenetre.contenu.caseGuide and ecran.page ~= "reglages" then
            for _, c in ipairs({ fenetre.contenu.caseInfobulles, fenetre.contenu.caseAssistant, fenetre.contenu.caseSuivi,
                fenetre.contenu.casePermanent, fenetre.contenu.caseAncre }) do
                c:Hide()
                c.libelle:Hide()
            end
        end
        if ecran.page == "stocks" or ecran.page == "stocksTous" then
            -- Assez large pour l'en-tete "Autres persos" sur une ligne.
            LargeurDesColonnes(fenetre.contenu, 80)
            RendreStocks(fenetre.contenu, ecran.page == "stocksTous")
        elseif ecran.page == "progression" then
            LargeurDesColonnes(fenetre.contenu, 0, 260)
            RendreProgression(fenetre.contenu)
        elseif ecran.page == "monter" then
            LargeurDesColonnes(fenetre.contenu, 0, 260)
            RendreProgression(fenetre.contenu, ecran.ongletCourantLigne)
        elseif ecran.page == "recettes" then
            -- Etat court, le detail est au survol : le nom des recettes a la place.
            LargeurDesColonnes(fenetre.contenu, 0, 190)
            RendreRecettes(fenetre.contenu)
        elseif ecran.page == "equipement" then
            CacherLignesAuDela(fenetre.contenu, 1)
            NS.equipement.Rendre(fenetre.zoneFixe, fenetre.bandeau)
        elseif ecran.page == "projets" then
            LargeurDesColonnes(fenetre.contenu, 0, 330)
            RendreProjets(fenetre.contenu)
        elseif ecran.page == "progressions" then
            LargeurDesColonnes(fenetre.contenu, 0, 330)
            RendreProgressions(fenetre.contenu)
        elseif ecran.page == "commandes" then
            LargeurDesColonnes(fenetre.contenu, 0, 330)
            RendreCommandes(fenetre.contenu)
        elseif ecran.page == "caisses" then
            LargeurDesColonnes(fenetre.contenu, 0, 150)
            RendreCaisses(fenetre.contenu)
        elseif ecran.page == "reglages" then
            RendreReglages(fenetre.contenu)
        elseif ecran.page == "reglagesStuff" then
            RendreReglagesStuff(fenetre.contenu)
        elseif ecran.page == "atelier" then
            LargeurDesColonnes(fenetre.contenu, 0, 220)
            RendreAtelier(fenetre.contenu)
        else
            RendrePageAVenir(fenetre.contenu)
        end
    end)
    if not ok then
        NS.base.NoterIncident("affichage de la page " .. tostring(ecran.page), souci)
        CacherLignesAuDela(fenetre.contenu, 1)
        PoserMessage(fenetre.contenu, L.PAGE_FAILED, 0)
        fenetre.contenu:SetHeight(60)
        NS.Dire(L.PAGE_FAILED)
    end

    if fenetre.fondMenu and not fenetre.fondMenu:IsShown() then
        pcall(NS.charte.FondDuJournal, fenetre.fondMenu)
    end

    -- Fond choisi dans Parametres, et textes a l'encre sur le parchemin.
    local okF, souciF = pcall(function()
        local parchemin = NS.charte.Fond() == "parchemin"
        if fenetre.parchemin then fenetre.parchemin.Montrer(parchemin) end
        -- Les libelles poses directement sur la page (Parametres, cases a
        -- cocher) ont la taille des lignes, partout la meme.
        for _, region in ipairs({ fenetre.contenu:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetFontObject
                and region:GetFontObject() == _G.GameFontHighlightSmall then region.agrandir = true end
        end
        for _, zone in ipairs({ fenetre.contenu, fenetre.zoneFixe, fenetre.bandeau }) do
            NS.charte.Encrer(zone, parchemin)
        end
        for _, ligne in ipairs(fenetre.contenu.lignes or {}) do
            local s = ligne.GetHighlightTexture and ligne:GetHighlightTexture()
            if s then
                if parchemin then s:SetVertexColor(0.55, 0.35, 0.1) else s:SetVertexColor(1, 1, 1) end
            end
        end
    end)
    if not okF then NS.base.NoterIncident("fond", souciF) end

    fenetre:Show()

    local okI, souciI = pcall(PoserIndicesManette, fenetre)
    if not okI then NS.base.NoterIncident("indications manette", souciI) end

    -- Apres le dessin : la manette retrouve sa selection, l'aide de la page
    -- s'ouvre a sa premiere visite, le didacticiel suit la page.
    if NS.manette and NS.manette.ApresRendu then
        local okM, souciM = pcall(NS.manette.ApresRendu, fenetre)
        if not okM then NS.base.NoterIncident("manette", souciM) end
    end
    if NS.aide and NS.aide.ApresMontrer then
        local okA, souciA = pcall(NS.aide.ApresMontrer, ecran.page)
        if not okA then NS.base.NoterIncident("aide", souciA) end
    end
end

-- Fenetre principale, pour l'aide et la manette. nil tant qu'elle n'existe pas.
function ecran.Fenetre()
    return fenetre
end

-- Ordre de toutes les sections : celles du menu, puis l'equipement et les
-- caisses, qui ont leur onglet a droite.
function ecran.OrdreDesPages()
    local ordre = {}
    for _, page in ipairs(PAGES) do table.insert(ordre, page.cle) end
    table.insert(ordre, "progression")
    table.insert(ordre, "equipement")
    table.insert(ordre, "caisses")
    return ordre
end

-- Ce que le didacticiel montre du doigt, par un nom stable. nil si l'element
-- n'existe pas ou n'est pas a l'ecran.
function ecran.Cible(nom)
    local win = fenetre
    if not win or type(nom) ~= "string" then return nil end
    local cible
    local genre, cle = string.match(nom, "^(%a+):(.+)$")
    if nom == "persos" then cible = win.bandePersos
    elseif nom == "menu" then cible = win.menu
    elseif nom == "metiers" then cible = win.onglets[(win.ordreOnglets or {})[1] or ""]
    elseif nom == "aide" then cible = win.boutonAide
    elseif nom == "barre" then cible = win.barre
    elseif nom == "contenu" then cible = (ecran.page == "equipement") and win.zoneFixe or win.defilement
    elseif nom == "filtres" then cible = win.contenu.caseConnues
    elseif genre == "menu" then cible = win.boutons[cle]
    elseif genre == "onglet" then
        cible = (cle == "equipement" and win.ongletEquipement) or (cle == "caisses" and win.ongletCaisses)
            or nil
    elseif genre == "action" then
        -- Le premier bouton d'action dont la cle commence ainsi.
        for cleAction, bouton in pairs(win.contenu.actions or {}) do
            if string.sub(cleAction, 1, #cle) == cle and bouton:IsShown() then cible = bouton break end
        end
    elseif genre == "ligne" then
        cible = win.contenu.lignes and win.contenu.lignes[tonumber(cle) or 0]
    end
    if cible and cible.IsVisible and cible:IsVisible() then return cible end
    return nil
end

-- Le personnage affiche est-il le dernier de la bande ? (la croix droite
-- passe alors aux add-ons de la suite, en haut a droite)
function ecran.DernierPersonnage()
    local ordre = fenetre and fenetre.ordrePersos or {}
    return #ordre == 0 or ordre[#ordre] == NS.base.PersonnageAffiche()
end

-- Personnage voisin dans la bande du haut, pour la manette.
function ecran.PersonnageVoisin(pas)
    if not fenetre then ecran.Montrer() return end
    local ordre = fenetre.ordrePersos or {}
    if #ordre == 0 then return end
    local affiche = NS.base.PersonnageAffiche()
    local index = 1
    for rang, cle in ipairs(ordre) do
        if cle == affiche then index = rang break end
    end
    local suivant = ((index - 1 + pas) % #ordre) + 1
    NS.base.PoserPersonnageAffiche(ordre[suivant])
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end
    ecran.Montrer(ecran.page)
end

function ecran.Basculer(cle)
    if fenetre and fenetre:IsShown() and (not cle or cle == ecran.page) then
        fenetre:Hide()
        return
    end
    ecran.Montrer(cle)
end

-- Actualise seulement si la fenetre est ouverte : pas de calcul pour rien.
-- Page voisine dans l'ordre du menu. Ouvre la fenetre si elle est fermee.
-- LB / RB : seulement le menu de gauche, et on s'arrete aux bouts. Depuis un
-- onglet de droite, on revient a la section du menu qu'on avait quittee.
function ecran.PageVoisine(pas)
    if not fenetre then ecran.Montrer() return end
    -- Les caisses n'ont pas de menu : LB / RB n'y font rien.
    if ecran.page == "caisses" then return end
    -- StuffCore : ses trois pages.
    if ecran.EstStuff(ecran.page) then
        -- Presentation 1 : les origines du menu, puis les Parametres.
        if NS.equipement and NS.equipement.Scenario() == 1 and fenetre.originesEquip then
            local liste = {}
            for _, cat in ipairs(NS.sources and NS.sources.ORDRE or {}) do table.insert(liste, cat) end
            table.insert(liste, "reglagesStuff")
            local rang = #liste
            if ecran.page == "equipement" then
                for k, c in ipairs(liste) do if c == NS.equipement.Categorie() then rang = k end end
            end
            local suivant = math.max(1, math.min(#liste, rang + pas))
            if suivant == rang then return end
            if liste[suivant] == "reglagesStuff" then ecran.Montrer("reglagesStuff") return end
            NS.equipement.PoserCategorie(liste[suivant])
            NS.ecran.selectionObjets = {}
            ecran.Montrer("equipement")
            return
        end
        local liste = { "equipement", "reglagesStuff" }
        local rang = 1
        for k, p in ipairs(liste) do if p == ecran.page then rang = k end end
        local suivant = math.max(1, math.min(#liste, rang + pas))
        if suivant ~= rang then ecran.Montrer(liste[suivant]) end
        return
    end
    local index
    for rang, p in ipairs(PAGES) do
        if p.cle == ecran.page then index = rang break end
    end
    if not index then
        ecran.Montrer(ecran.pageMenu or PAGES[1].cle)
        return
    end
    local suivant = math.max(1, math.min(#PAGES, index + pas))
    if suivant ~= index then ecran.Montrer(PAGES[suivant].cle) end
end

-- Onglet voisin sur le bord droit : les metiers, puis tous les metiers,
-- l'equipement et les caisses, dans l'ordre ou ils sont poses. LT / RT les
-- parcourt et s'arrete aux bouts (les add-ons : Vue + LB / RB).
function ecran.MetierVoisin(pas)
    if not fenetre then ecran.Montrer() end
    local ordre = {}
    -- StuffCore n'a pas d'onglet a droite. En presentation 2, LT / RT passent
    -- d'une origine a l'autre (onglets au-dessus des emplacements).
    if ecran.EstStuff(ecran.page) then
        if ecran.page == "equipement" and NS.equipement and NS.equipement.Scenario() == 2 then
            local ordre = NS.sources.ORDRE
            local rang = 1
            for k, c in ipairs(ordre) do if c == NS.equipement.Categorie() then rang = k end end
            local suivant = math.max(1, math.min(#ordre, rang + pas))
            if suivant ~= rang then
                NS.equipement.PoserCategorie(ordre[suivant])
                NS.ecran.selectionObjets = {}
                ecran.Montrer("equipement")
            end
        end
        return
    end
    for _, cle in ipairs(fenetre and fenetre.ordreOnglets or {}) do
        table.insert(ordre, { metier = cle })
    end
    table.insert(ordre, { page = "caisses" })
    local index
    for rang, entree in ipairs(ordre) do
        if (entree.page and entree.page == ecran.page)
            or (entree.metier and not index and entree.metier == ecran.metier) then
            index = rang
            if entree.page then break end
        end
    end
    local rangSuivant = index and math.max(1, math.min(#ordre, index + pas)) or 1
    if rangSuivant == index and (ordre[index].page or PAGES_PAR_METIER[ecran.page]) then return end
    local suivant = ordre[rangSuivant]
    if suivant.page then
        ecran.Montrer(suivant.page)
    else
        ecran.metier = suivant.metier
        local retour = PAGES_PAR_METIER[ecran.page] and ecran.page
            or (ecran.pageMenu and PAGES_PAR_METIER[ecran.pageMenu] and ecran.pageMenu) or "recettes"
        ecran.Montrer(retour)
    end
end

function ecran.Actualiser()
    if fenetre and fenetre:IsShown() then
        ecran.Montrer(ecran.page)
    end
end
