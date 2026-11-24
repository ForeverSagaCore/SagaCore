local _, NS = ...

-- Aide et didacticiel.
--
-- Trois choses, toutes faites avec les modeles du jeu, rien de dessine :
--   l'accueil, au milieu de la fenetre, a la toute premiere ouverture ;
--   l'aide de chaque page, a sa toute premiere visite, puis a la demande par
--   le bouton i ;
--   le didacticiel guide, pas a pas, desactive par defaut.
--
-- Ce qui a ete vu est retenu dans la sauvegarde, une fois pour toutes : une
-- mise a jour ne remontre rien. Le bouton i reste la pour relire.

NS.aide = {}
local aide = NS.aide
NS.didacticiel = {}
local didacticiel = NS.didacticiel

local L

-- ---------------------------------------------------------------------------
-- Etat retenu
-- ---------------------------------------------------------------------------

local function Etat()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { pages = {} } end
    d.aide = d.aide or {}
    d.aide.pages = d.aide.pages or {}
    return d.aide
end

function aide.GuideActif()
    return Etat().guide == true
end

function aide.PoserGuide(valeur)
    Etat().guide = valeur and true or nil
    if not valeur and didacticiel.EnCours() then didacticiel.Quitter() end
end

-- Deja vu, quelle que soit la version ou on l'a vu.
local function MemeVersion(vue)
    return type(vue) == "string" and vue ~= ""
end

-- L'accueil reste a montrer pour cette version ?
function aide.AccueilAMontrer()
    return not MemeVersion(Etat().accueil)
end

-- ---------------------------------------------------------------------------
-- Fenetre d'aide
-- ---------------------------------------------------------------------------

local LARGEUR, HAUTEUR = 580, 460
local fenetreAide

-- Meme fenetre que la principale : la charte commune.
local function CadreNatif(nom, largeur, hauteur)
    local cadre = NS.charte.Fenetre(nom, largeur, hauteur)
    cadre:SetToplevel(true)
    return cadre
end

-- Toujours au dessus de la fenetre principale, jamais dessous.
local function PasserDevant(cadre)
    local principale = NS.ecran.Fenetre and NS.ecran.Fenetre()
    if principale then
        cadre:SetFrameLevel(principale:GetFrameLevel() + 60)
    end
end

local function Construire()
    L = NS.L
    local cadre = CadreNatif("CraftCoreAide", LARGEUR, HAUTEUR)
    local zone = cadre.zone
    cadre.fermer:SetScript("OnClick", function() cadre:Hide() end)

    -- Texte dans une zone defilante du jeu : une aide longue ne deborde jamais.
    local defilement = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
    defilement:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, 0)
    defilement:SetPoint("BOTTOMRIGHT", zone, "BOTTOMRIGHT", -22, 0)
    local largeurTexte = LARGEUR - 2 * NS.charte.MARGE - 40
    local contenu = CreateFrame("Frame", nil, defilement)
    contenu:SetSize(largeurTexte, 1)
    defilement:SetScrollChild(contenu)
    cadre.defilement = defilement

    local texte = contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    texte:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, 0)
    texte:SetWidth(largeurTexte)
    texte:SetJustifyH("LEFT")
    texte:SetJustifyV("TOP")
    if texte.SetSpacing then texte:SetSpacing(3) end
    cadre.texte = texte
    cadre.contenu = contenu

    -- Pied, comme les fenetres du jeu : Fermer a droite, le lancement du
    -- didacticiel a cote, la case du didacticiel guide a gauche.
    local fermerBas = NS.charte.BoutonDePied(cadre, L.CLOSE, 110)
    fermerBas:SetScript("OnClick", function() cadre:Hide() end)
    cadre.boutonFermer = fermerBas

    local lancer = NS.charte.BoutonDePied(cadre, L.HELP_START_TUTORIAL, 180, fermerBas)
    lancer:SetScript("OnClick", function()
        local cle = cadre.didacticiel
        cadre:Hide()
        if cle then didacticiel.Lancer(cle) end
    end)
    cadre.boutonLancer = lancer

    local case = CreateFrame("CheckButton", nil, cadre.pied, "UICheckButtonTemplate")
    case:SetSize(22, 22)
    case:SetPoint("LEFT", cadre.pied, "LEFT", -4, 0)
    local libelle = cadre.pied:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    libelle:SetPoint("LEFT", case, "RIGHT", 2, 1)
    libelle:SetText(L.SETTING_GUIDE)
    case:SetHitRectInsets(0, -180, 0, 0)
    case:SetScript("OnClick", function(self)
        aide.PoserGuide(self:GetChecked() and true or false)
        aide.ActualiserPied()
    end)
    cadre.caseGuide = case

    cadre:Hide()
    return cadre
end

-- Le bouton du didacticiel n'est actif que si le mode guide l'est.
function aide.ActualiserPied()
    if not fenetreAide then return end
    -- A la manette, la meme barre que sous la fenetre principale.
    if NS.ecran and NS.ecran.BarreManette then
        local actions = { { "PAD1", NS.L.CLOSE } }
        if fenetreAide.didacticiel and aide.GuideActif() then
            table.insert(actions, { "PAD4", NS.L.HELP_START_TUTORIAL })
        end
        table.insert(actions, { "PAD3", NS.L.SETTING_GUIDE })
        table.insert(actions, { "PAD2", NS.L.PAD_BACK })
        pcall(NS.ecran.BarreManette, fenetreAide, actions)
    end
    local actif = aide.GuideActif()
    fenetreAide.caseGuide:SetChecked(actif)
    fenetreAide.boutonLancer:SetEnabled(actif and fenetreAide.didacticiel ~= nil)
    fenetreAide.boutonLancer:SetShown(fenetreAide.didacticiel ~= nil)
end

-- Didacticiel associe a chaque aide.
local DIDACTICIEL_DE = {
    accueil = "premiers", atelier = "premiers", stocks = "stocks", recettes = "recettes",
    projets = "projets", equipement = "equipement",
    caisses = "caisses", reglages = "manette", banquiers = "banquiers",
}

-- Cles de traduction d'une aide : HELP_<CLE>_TITLE et HELP_<CLE>_TEXT.
local function Textes(cle)
    L = NS.L or L
    if not L then return nil end
    local base = "HELP_" .. string.upper(cle)
    return L[base .. "_TITLE"], L[base .. "_TEXT"]
end

function aide.Montrer(cle)
    if not NS.L then return end
    L = NS.L
    local titre, texte = Textes(cle or "accueil")
    if not titre or not texte then
        cle = "accueil"
        titre, texte = Textes(cle)
    end
    fenetreAide = fenetreAide or Construire()
    fenetreAide.cle = cle
    fenetreAide.didacticiel = DIDACTICIEL_DE[cle]
    fenetreAide.titre:SetText(titre)
    fenetreAide.texte:SetText(texte)
    fenetreAide.contenu:SetHeight(math.max(1, (fenetreAide.texte:GetStringHeight() or 0) + 10))
    fenetreAide.defilement:SetVerticalScroll(0)
    aide.ActualiserPied()

    -- Au milieu de la fenetre principale, ou de l'ecran si elle est fermee.
    fenetreAide:ClearAllPoints()
    local principale = NS.ecran.Fenetre and NS.ecran.Fenetre()
    if principale and principale:IsShown() then
        fenetreAide:SetPoint("CENTER", principale, "CENTER", 0, 0)
    else
        fenetreAide:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    PasserDevant(fenetreAide)
    fenetreAide:Show()

    -- Montree, donc vue pour cette version.
    local etat = Etat()
    if cle == "accueil" then etat.accueil = NS.VERSION else etat.pages[cle] = NS.VERSION end
end

function aide.Cacher()
    if fenetreAide then fenetreAide:Hide() end
end

function aide.EstOuverte()
    return fenetreAide ~= nil and fenetreAide:IsShown()
end

-- Le bouton i : ouvre l'aide de la page, ou la referme si c'est deja elle.
function aide.Basculer(page)
    if aide.EstOuverte() and fenetreAide.cle == page then
        fenetreAide:Hide()
        return
    end
    aide.Montrer(page)
end

-- Fait defiler le texte, pour la manette.
function aide.Defiler(pas)
    if not aide.EstOuverte() then return end
    local d = fenetreAide.defilement
    local maximum = (d.GetVerticalScrollRange and d:GetVerticalScrollRange()) or 0
    local valeur = math.max(0, math.min(maximum, d:GetVerticalScroll() + pas * 40))
    d:SetVerticalScroll(valeur)
end

function aide.LancerDidacticielAffiche()
    if not aide.EstOuverte() then return end
    if fenetreAide.boutonLancer:IsShown() and fenetreAide.boutonLancer:IsEnabled() then
        fenetreAide.boutonLancer:Click()
    end
end

function aide.BasculerGuide()
    if not aide.EstOuverte() then return end
    fenetreAide.caseGuide:Click()
end

-- Appelee apres chaque affichage de page : l'accueil d'abord s'il n'a pas
-- ete vu dans cette version, sinon l'aide de la page a sa premiere visite.
-- Jamais par dessus une aide deja ouverte ni pendant un didacticiel.
function aide.ApresMontrer(page)
    didacticiel.SuivreFenetre(NS.ecran.Fenetre and NS.ecran.Fenetre())
    if didacticiel.EnCours() then
        didacticiel.Actualiser()
        return
    end
    if aide.EstOuverte() then return end
    if aide.AccueilAMontrer() then
        aide.Montrer("accueil")
        return
    end
    if page and not MemeVersion(Etat().pages[page]) then
        local titre = Textes(page)
        if titre then aide.Montrer(page) end
    end
end

-- ---------------------------------------------------------------------------
-- Didacticiel guide
-- ---------------------------------------------------------------------------

-- Chaque etape : la page a ouvrir pour la montrer (facultatif), l'element a
-- designer (facultatif), et son texte. Les textes sont dans les traductions,
-- TUTO_<CLE>_<N>.
local PARCOURS = {
    { cle = "premiers", etapes = {
        { cible = "persos" },
        { cible = "menu" },
        { cible = "metiers" },
        { page = "stocks", cible = "menu:stocks" },
        { cible = "aide" },
    } },
    { cle = "stocks", etapes = {
        { page = "stocks", cible = "persos" },
        { page = "stocks", cible = "contenu" },
        { page = "stocks", cible = "ligne:3" },
        { page = "stocks", cible = "metiers" },
    } },
    { cle = "recettes", etapes = {
        { cible = "metiers" },
        { page = "recettes", cible = "filtres" },
        { page = "recettes", cible = "contenu" },
        { page = "recettes", cible = "contenu" },
    } },
    { cle = "projets", etapes = {
        { cible = "menu:projets" },
        { page = "projets", cible = "action:nouveau" },
        { page = "projets", cible = "action:chercher" },
        { page = "projets", cible = "action:cibler" },
        { page = "projets", cible = "contenu" },
    } },
    { cle = "rapides", etapes = {
        { page = "projets", cible = "action:ciblerRapides" },
        { cible = "menu:recettes" },
        { page = "projets", cible = "action:verser" },
    } },
    { cle = "approv", etapes = {
        { page = "projets", cible = "contenu" },
        { page = "projets", cible = "contenu" },
        { page = "projets", cible = "contenu" },
    } },
    { cle = "equipement", etapes = {
        { cible = "onglet:equipement" },
        { page = "equipement", cible = "contenu" },
        { page = "equipement", cible = "contenu" },
    } },
    { cle = "banquiers", etapes = {
        { cible = "menu:banquiers" },
        { page = "banquiers", cible = "bq:liste" },
        { page = "banquiers", cible = "bq:nouveau" },
        { page = "banquiers", cible = "contenu" },
    } },
    { cle = "caisses", etapes = {
        { cible = "onglet:caisses" },
        { page = "caisses", cible = "contenu" },
    } },
    { cle = "manette", etapes = {
        { cible = "menu" },
        { cible = "metiers" },
        { cible = "persos" },
        { cible = "contenu" },
        { cible = "barre" },
    } },
}

local PAR_CLE = {}
for _, parcours in ipairs(PARCOURS) do PAR_CLE[parcours.cle] = parcours end

function didacticiel.Liste()
    L = NS.L or L
    local liste = {}
    for _, parcours in ipairs(PARCOURS) do
        table.insert(liste, { cle = parcours.cle,
            titre = (L and L["TUTO_" .. string.upper(parcours.cle) .. "_TITLE"]) or parcours.cle })
    end
    return liste
end

local boite, repere
local enCours, rang

function didacticiel.EnCours()
    return enCours ~= nil
end

-- Repere pose sur l'element designe : le halo de case cochee du jeu, qui
-- pulse avec une animation du jeu. Il ne capte pas la souris.
local function Repere()
    if repere then return repere end
    repere = CreateFrame("Frame", nil, UIParent)
    repere:SetFrameStrata("FULLSCREEN_DIALOG")
    repere:EnableMouse(false)
    local halo = repere:CreateTexture(nil, "OVERLAY")
    halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    halo:SetBlendMode("ADD")
    halo:SetAllPoints()
    local c = _G.NORMAL_FONT_COLOR
    if type(c) == "table" and c.r then halo:SetVertexColor(c.r, c.g, c.b) end
    repere.halo = halo
    if repere.CreateAnimationGroup then
        local groupe = repere:CreateAnimationGroup()
        groupe:SetLooping("BOUNCE")
        local fondu = groupe:CreateAnimation("Alpha")
        fondu:SetFromAlpha(1)
        fondu:SetToAlpha(0.3)
        fondu:SetDuration(0.7)
        repere.animation = groupe
    end
    repere:Hide()
    return repere
end

local function ConstruireBoite()
    L = NS.L
    local cadre = CadreNatif("CraftCoreDidacticiel", 440, 250)
    local zone = cadre.zone
    cadre.fermer:SetScript("OnClick", function() didacticiel.Quitter() end)

    cadre.etape = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cadre.etape:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, 0)
    cadre.etape:SetPoint("RIGHT", zone, "RIGHT", 0, 0)
    cadre.etape:SetJustifyH("LEFT")

    cadre.texte = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cadre.texte:SetPoint("TOPLEFT", cadre.etape, "BOTTOMLEFT", 0, -NS.charte.ECART)
    cadre.texte:SetPoint("RIGHT", zone, "RIGHT", 0, 0)
    cadre.texte:SetJustifyH("LEFT")
    cadre.texte:SetJustifyV("TOP")

    cadre.manette = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cadre.manette:SetPoint("BOTTOMLEFT", zone, "BOTTOMLEFT", 0, 0)
    cadre.manette:SetJustifyH("LEFT")

    local suivant = NS.charte.BoutonDePied(cadre, "", 110)
    suivant:SetScript("OnClick", function() didacticiel.Pas(1) end)
    cadre.suivant = suivant

    local precedent = NS.charte.BoutonDePied(cadre, L.TUTO_PREVIOUS, 110, suivant)
    precedent:SetScript("OnClick", function() didacticiel.Pas(-1) end)
    cadre.precedent = precedent

    local quitter = CreateFrame("Button", nil, cadre.pied, "UIPanelButtonTemplate")
    quitter:SetSize(100, NS.charte.HAUTEUR_BOUTON)
    quitter:SetPoint("LEFT", cadre.pied, "LEFT", 0, 0)
    quitter:SetText(L.TUTO_QUIT)
    quitter:SetScript("OnClick", function() didacticiel.Quitter() end)

    cadre:Hide()
    return cadre
end

-- Pose la boite sous la fenetre principale, sans jamais la recouvrir : le
-- contenu designe reste visible et utilisable.
local function PlacerBoite()
    boite:ClearAllPoints()
    local principale = NS.ecran.Fenetre and NS.ecran.Fenetre()
    if principale and principale:IsShown() then
        boite:SetPoint("TOP", principale, "BOTTOM", 0, -6)
    else
        boite:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
    PasserDevant(boite)
end

local function Designer(nom)
    local r = Repere()
    local cible = nom and NS.ecran.Cible and NS.ecran.Cible(nom) or nil
    if not cible then
        r:Hide()
        if r.animation then r.animation:Stop() end
        return
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", cible, "TOPLEFT", -6, 6)
    r:SetPoint("BOTTOMRIGHT", cible, "BOTTOMRIGHT", 6, -6)
    PasserDevant(r)
    r:Show()
    if r.animation then r.animation:Play() end
end

-- Redessine l'etape courante, sans changer de page.
function didacticiel.Actualiser()
    if not enCours or not boite then return end
    L = NS.L or L
    local etape = enCours.etapes[rang]
    local prefixe = "TUTO_" .. string.upper(enCours.cle)
    boite.titre:SetText(L[prefixe .. "_TITLE"] or enCours.cle)
    boite.etape:SetText(string.format(L.TUTO_STEP, rang, #enCours.etapes))
    boite.texte:SetText(L[prefixe .. "_" .. rang] or "")
    boite.precedent:SetEnabled(rang > 1)
    boite.suivant:SetText(rang < #enCours.etapes and L.TUTO_NEXT or L.TUTO_DONE)
    boite.manette:SetText((NS.manette and NS.manette.Active()) and L.TUTO_PAD or "")
    -- Hauteur selon le texte, pour qu'il ne deborde jamais.
    local hauteur = 110 + (boite.texte:GetStringHeight() or 0)
    boite:SetHeight(math.max(170, hauteur))
    PlacerBoite()
    boite:Show()
    Designer(etape.cible)
end

-- Montre une etape : ouvre sa page si elle en a une, puis la designe.
local function MontrerEtape()
    local etape = enCours.etapes[rang]
    local ecran = NS.ecran
    -- Changer de page redessine la fenetre, et ApresMontrer actualise alors
    -- l'etape ; sinon on l'actualise ici.
    if etape.page and ecran.page ~= etape.page then
        ecran.Montrer(etape.page)
    elseif not (ecran.Fenetre() and ecran.Fenetre():IsShown()) then
        ecran.Montrer()
    else
        didacticiel.Actualiser()
    end
end

function didacticiel.Lancer(cle)
    local parcours = PAR_CLE[cle]
    if not parcours then return end
    L = NS.L
    -- Lancer un didacticiel suppose le mode guide : on l'active.
    if not aide.GuideActif() then aide.PoserGuide(true) end
    aide.Cacher()
    boite = boite or ConstruireBoite()
    enCours, rang = parcours, 1
    MontrerEtape()
end

function didacticiel.Pas(pas)
    if not enCours then return end
    local cible = rang + pas
    if cible < 1 then return end
    if cible > #enCours.etapes then
        didacticiel.Quitter()
        return
    end
    rang = cible
    MontrerEtape()
end

function didacticiel.Quitter()
    enCours, rang = nil, nil
    if boite then boite:Hide() end
    if repere then
        repere:Hide()
        if repere.animation then repere.animation:Stop() end
    end
end

-- La fenetre principale fermee, le didacticiel n'a plus rien a montrer.
function didacticiel.SuivreFenetre(principale)
    if not principale or principale.craftCoreSuiviAide then return end
    principale.craftCoreSuiviAide = true
    principale:HookScript("OnHide", function()
        didacticiel.Quitter()
        aide.Cacher()
    end)
end
