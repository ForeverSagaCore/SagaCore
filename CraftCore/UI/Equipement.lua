local _, NS = ...

-- ===========================================================================
-- Page de l'equipement
-- ===========================================================================

-- Page de l'equipement, vue transverse du compte.
--
-- A gauche les emplacements du personnage regarde. A droite, pour l'emplacement
-- choisi, tout ce que le compte peut offrir : ce que ce personnage sait faire,
-- ce qu'un autre sait faire, et ce qui dort deja chez un autre. En bas, la
-- comparaison des objets retenus.
--
-- Aucun objet n'est declare meilleur : on rassemble, l'utilisateur tranche.

NS.equipement = {}
local equipement = NS.equipement

local LARGEUR_COLONNE = 186
local LARGEUR_CHOIX = 330
local HAUTEUR_CASE = 32
local HAUTEUR_CANDIDAT = 24
local LIGNES_PAR_COLONNE = 5

local L

-- ---------------------------------------------------------------------------
-- Navigation : trois scenarios a essayer (choisis dans le menu de gauche)
--   1 : les origines dans le menu de gauche, une a la fois ;
--   2 : les origines en onglets au-dessus des emplacements ;
--   3 : toutes les origines dans une seule liste, triee par gain, chaque
--       origine allumee ou eteinte dans le menu de gauche.
-- ---------------------------------------------------------------------------

local function Memoire()
    CraftCoreDB.memoire = type(CraftCoreDB.memoire) == "table" and CraftCoreDB.memoire or {}
    local m = CraftCoreDB.memoire
    m.equip = type(m.equip) == "table" and m.equip or {}
    return m.equip
end
function equipement.Scenario() return tonumber(Memoire().scenario) or 1 end
function equipement.PoserScenario(n) Memoire().scenario = n end
function equipement.Categorie() return Memoire().categorie or "craftInterne" end
function equipement.PoserCategorie(c) Memoire().categorie = c end
function equipement.FiltreActif(c)
    local f = Memoire().filtres
    return not (type(f) == "table" and f[c] == false)
end
function equipement.BasculerFiltre(c)
    local m = Memoire()
    m.filtres = type(m.filtres) == "table" and m.filtres or {}
    m.filtres[c] = not equipement.FiltreActif(c)
end

-- ---------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------

local function ObjetPorteDe(fiche, nomEmplacement, estConnecte)
    -- Pour le personnage connecte, on demande au client. Pour les autres, on
    -- se fie au dernier releve enregistre.
    if estConnecte then
        local j = NS.jeu
        local numero = NS.emplacements.Numero(nomEmplacement)
        if numero and j.objetEquipe then
            local id = tonumber(NS.Appeler(j.objetEquipe, "player", numero))
            if id then
                local lien = j.lienObjetEquipe and NS.Appeler(j.lienObjetEquipe, "player", numero)
                return id, type(lien) == "string" and lien or nil
            end
        end
    end
    local porte = fiche and fiche.equipement and fiche.equipement[nomEmplacement]
    return porte and porte.id or nil, porte and porte.lien or nil
end

-- Le nom ecrit dans le lien d'un objet porte : connu meme quand le jeu n'a
-- pas encore la fiche de l'objet (objets propres au serveur, par exemple).
local function NomDuLien(lien)
    return type(lien) == "string" and string.match(lien, "|h%[(.-)%]|h") or nil
end

local function InfosObjet(id, lien)
    if not id then return nil end
    local info = NS.objets.Info(id)
    local nom = (info and info.nom) or NomDuLien(lien)
    return {
        id = id,
        nom = nom,
        niveau = info and info.niveau,
        icone = (info and info.icone) or NS.Appeler(NS.jeu.iconeObjet, id),
        stats = NS.objets.Stats(id) or (lien and NS.objets.Stats(lien)),
    }
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function CreerCaseEmplacement(parent)
    local bouton = CreateFrame("Button", nil, parent)
    bouton:SetHeight(HAUTEUR_CASE)

    bouton.cadre = bouton:CreateTexture(nil, "BACKGROUND")
    bouton.cadre:SetSize(28, 28)
    bouton.cadre:SetPoint("LEFT", bouton, "LEFT", 2, 0)
    bouton.cadre:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")

    bouton.icone = bouton:CreateTexture(nil, "ARTWORK")
    bouton.icone:SetSize(24, 24)
    bouton.icone:SetPoint("CENTER", bouton.cadre, "CENTER", 0, 0)
    bouton.icone:Hide()

    bouton.ou = bouton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bouton.ou:SetPoint("TOPLEFT", bouton.cadre, "TOPRIGHT", 6, -1)
    bouton.ou:SetJustifyH("LEFT")
    bouton.ou:SetWordWrap(false)

    bouton.porte = bouton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bouton.porte:SetPoint("TOPLEFT", bouton.ou, "BOTTOMLEFT", 0, -1)
    bouton.porte:SetPoint("RIGHT", bouton, "RIGHT", -2, 0)
    bouton.porte:SetJustifyH("LEFT")
    bouton.porte:SetWordWrap(false)
    bouton.ou:SetPoint("RIGHT", bouton, "RIGHT", -2, 0)

    bouton.marque = bouton:CreateTexture(nil, "OVERLAY")
    bouton.marque:SetSize(12, 12)
    bouton.marque:SetPoint("BOTTOMRIGHT", bouton.cadre, "BOTTOMRIGHT", 2, -2)
    bouton.marque:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    bouton.marque:Hide()

    bouton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return bouton
end

local function CreerBoutonFiltre(parent)
    local bouton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    bouton:SetHeight(18)
    return bouton
end

local function CreerLigneCandidat(parent, index)
    parent.candidats = parent.candidats or {}
    local ligne = parent.candidats[index]
    if ligne then return ligne end

    ligne = CreateFrame("Button", nil, parent)
    ligne:SetHeight(HAUTEUR_CANDIDAT)

    ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
    ligne.fond:SetAllPoints()
    ligne.fond:SetColorTexture(0.35, 0.28, 0.12, 0.5)
    ligne.fond:Hide()

    ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
    ligne.icone:SetSize(18, 18)
    ligne.icone:SetPoint("TOPLEFT", ligne, "TOPLEFT", 2, -4)

    -- Deux lignes : le nom en entier, puis l'etat dessous. Rien n'est coupe
    -- par la largeur de la colonne.
    ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne.nom:SetPoint("TOPLEFT", ligne, "TOPLEFT", 25, -4)
    ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -20, 0)
    ligne.nom:SetJustifyH("LEFT")
    -- Jamais sur deux lignes.
    ligne.nom:SetWordWrap(false)
    if ligne.nom.SetMaxLines then ligne.nom:SetMaxLines(1) end

    ligne.etat = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ligne.etat:SetPoint("TOPLEFT", ligne.nom, "BOTTOMLEFT", 0, -2)
    ligne.etat:SetPoint("RIGHT", ligne, "RIGHT", -4, 0)
    ligne.etat:SetJustifyH("LEFT")
    ligne.etat:SetWordWrap(false)

    ligne:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    parent.candidats[index] = ligne
    return ligne
end

local function CreerLigneStat(bandeau, index)
    bandeau.stats = bandeau.stats or {}
    local ligne = bandeau.stats[index]
    if ligne then return ligne end

    ligne = CreateFrame("Frame", nil, bandeau)
    ligne:SetHeight(14)
    ligne.colonnes = {}

    ligne.cle = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ligne.cle:SetPoint("LEFT", ligne, "LEFT", 0, 0)
    ligne.cle:SetJustifyH("LEFT")
    ligne.cle:SetWordWrap(false)

    -- Trois colonnes alignees a gauche : porte, nouveau, ecart.
    for rang = 1, 3 do
        local colonne = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        colonne:SetWidth(58)
        colonne:SetJustifyH("LEFT")
        colonne:SetWordWrap(false)
        colonne:SetPoint("LEFT", ligne, "LEFT", 140 + (rang - 1) * 62, 0)
        ligne.colonnes[rang] = colonne
    end
    ligne.cle:SetPoint("RIGHT", ligne.colonnes[1], "LEFT", -6, 0)

    bandeau.stats[index] = ligne
    return ligne
end

function equipement.Construire(contenu, bandeau)
    L = NS.L
    if contenu.equipement then return contenu.equipement end

    local vue = CreateFrame("Frame", nil, contenu)
    vue:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, 0)
    vue:SetPoint("BOTTOMRIGHT", contenu, "BOTTOMRIGHT", 0, 0)
    vue.bandeau = bandeau

    -- Emplacements, deux colonnes aerees.
    vue.cases = {}
    local precedents = {}
    local hauteurColonnes = 0
    local rangBas = 0
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local bouton = CreerCaseEmplacement(vue)
        local cote = emplacement.cote
        if cote == "bas" then
            bouton:SetWidth((LARGEUR_COLONNE * 2 + 8) / 3 - 4)
            bouton.rang = rangBas
            rangBas = rangBas + 1
        else
            bouton:SetWidth(LARGEUR_COLONNE)
            if precedents[cote] then
                bouton:SetPoint("TOPLEFT", precedents[cote], "BOTTOMLEFT", 0, -2)
            elseif cote == "g" then
                bouton:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, 0)
                vue.premierG = bouton
            else
                bouton:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE + 8, 0)
                vue.premierD = bouton
            end
            precedents[cote] = bouton
            if cote == "g" then hauteurColonnes = hauteurColonnes + HAUTEUR_CASE + 2 end
        end
        bouton.emplacement = emplacement
        bouton:SetScript("OnClick", function()
            vue.choisi = emplacement.nom
            NS.ecran.selectionObjets = {}
            equipement.Rendre(contenu, bandeau)
        end)
        vue.cases[emplacement.nom] = bouton
    end

    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        if emplacement.cote == "bas" then
            local bouton = vue.cases[emplacement.nom]
            bouton:SetPoint("TOPLEFT", vue, "TOPLEFT",
                bouton.rang * ((LARGEUR_COLONNE * 2 + 8) / 3), -(hauteurColonnes + 8))
        end
    end
    vue.hauteurColonnes = hauteurColonnes

    -- Zone de choix, a droite.
    local choix = CreateFrame("Frame", nil, vue)
    choix:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE * 2 + 18, 0)
    choix:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)
    vue.choix = choix

    choix.titre = choix:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    choix.titre:SetPoint("TOPLEFT", choix, "TOPLEFT", 0, 0)
    choix.sousTitre = choix:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    choix.sousTitre:SetPoint("TOPLEFT", choix.titre, "BOTTOMLEFT", 0, -2)
    choix.sousTitre:SetPoint("RIGHT", choix, "RIGHT", 0, 0)
    choix.sousTitre:SetJustifyH("LEFT")
    choix.sousTitre:SetWordWrap(false)

    choix.filtres = {}

    -- Case d'accueil : une vraie case d'objet du jeu, vide, ou l'on glisse
    -- un objet de ses sacs pour le comparer. Clic droit : la vider.
    local depot
    -- Elle vit dans la bande de comparaison, en bas a droite : on y glisse un
    -- objet ramasse, CraftCore trouve son emplacement et le compare a ce qui
    -- est porte. Elle ne se confond pas avec la liste des objets fabricables.
    local okCase, cree = pcall(CreateFrame, "Button", nil, bandeau, "ItemButtonTemplate")
    depot = okCase and cree or CreateFrame("Button", nil, bandeau)
    depot:SetPoint("TOPRIGHT", bandeau, "TOPRIGHT", -14, -26)
    depot:SetSize(37, 37)
    depot:EnableMouse(true)
    depot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    depot.vide = depot:CreateTexture(nil, "BACKGROUND")
    depot.vide:SetAllPoints()
    depot.vide:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    depot.image = depot.icon or depot.Icon or depot:CreateTexture(nil, "ARTWORK")
    if not (depot.icon or depot.Icon) then depot.image:SetAllPoints() end
    depot.texte = depot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    depot.texte:SetPoint("BOTTOMRIGHT", depot, "TOPRIGHT", 0, 4)
    depot.texte:SetJustifyH("RIGHT")
    depot:SetScript("OnReceiveDrag", function()
        equipement.RecevoirObjet(contenu, bandeau)
    end)
    depot:SetScript("OnClick", function(_, bouton)
        if bouton == "RightButton" then
            NS.ecran.objetDepose = nil
            NS.ecran.selectionObjets = {}
            equipement.Rendre(contenu, bandeau)
            return
        end
        equipement.RecevoirObjet(contenu, bandeau)
    end)
    depot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local montre = NS.ecran.objetDepose or next(NS.ecran.selectionObjets or {})
        if montre and GameTooltip.SetItemByID then
            pcall(GameTooltip.SetItemByID, GameTooltip, montre)
            GameTooltip:AddLine(L.GEAR_DROP_CLEAR, 0.6, 0.6, 0.6)
        else
            GameTooltip:SetText(L.GEAR_DROP_TITLE)
            GameTooltip:AddLine(L.GEAR_DROP_TIP, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    depot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    vue.depot = depot

    -- La liste defile : un emplacement peut compter des dizaines d'objets.
    local defilement = CreateFrame("ScrollFrame", nil, choix, "UIPanelScrollFrameTemplate")
    defilement:SetPoint("TOPLEFT", choix.sousTitre, "BOTTOMLEFT", 0, -6)
    defilement:SetPoint("BOTTOMRIGHT", choix, "BOTTOMRIGHT", -24, 0)
    vue.defilement = defilement

    local liste = CreateFrame("Frame", nil, defilement)
    liste:SetSize(LARGEUR_CHOIX - 26, 1)
    defilement:SetScrollChild(liste)
    vue.liste = liste

    contenu.equipement = vue
    return vue
end

-- Recoit un objet depose ou tenu par le curseur.
function equipement.RecevoirObjet(contenu, bandeau)
    local info = NS.Lecture("GetCursorInfo")
    if not info then return end
    local genre, id, lien = NS.Appeler(info, nil)
    if genre ~= "item" then return end
    local objet = tonumber(id) or tonumber(string.match(tostring(lien or ""), "item:(%d+)"))
    if not objet then return end

    local vider = NS.Lecture("ClearCursor")
    if vider then NS.Appeler(vider) end

    -- L'objet va a un emplacement : on y passe, au lieu de l'ignorer parce
    -- qu'un autre emplacement etait choisi.
    local code = NS.emplacements.DeLObjet(objet)
    if not code then
        NS.Dire(L.GEAR_DROP_NOT_GEAR)
        return
    end
    local vue = contenu.equipement
    for _, e in ipairs(NS.emplacements.DuPersonnage) do
        if e.code == code then
            if vue then vue.choisi = e.nom end
            break
        end
    end
    NS.ecran.objetDepose = objet
    -- L'objet glisse est celui qu'on compare, seul.
    NS.ecran.selectionObjets = {}
    equipement.Rendre(contenu, bandeau)
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

local function RendreBandeau(bandeau, porte, choisis)
    if #choisis == 0 then
        bandeau:Show()
        if not bandeau.titre then
            bandeau.titre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            bandeau.titre:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8, -6)
            bandeau.titre:SetPoint("RIGHT", bandeau, "RIGHT", -120, 0)
            bandeau.titre:SetJustifyH("LEFT")
            bandeau.contre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            bandeau.contre:SetPoint("TOPLEFT", bandeau.titre, "BOTTOMLEFT", 0, -2)
        end
        bandeau.titre:SetText("")
        bandeau.contre:SetText(L.GEAR_PICK)
        for _, ligne in ipairs(bandeau.stats or {}) do ligne:Hide() end
        for _, t in ipairs(bandeau.titresCol or {}) do for _, fs in ipairs(t) do fs:Hide() end end
        return
    end
    bandeau:Show()

    if not bandeau.titre then
        bandeau.titre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bandeau.titre:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8, -6)
        bandeau.titre:SetPoint("RIGHT", bandeau, "RIGHT", -120, 0)
        bandeau.titre:SetJustifyH("LEFT")
        bandeau.contre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bandeau.contre:SetPoint("TOPLEFT", bandeau.titre, "BOTTOMLEFT", 0, -2)
    end

    local noms = {}
    for _, c in ipairs(choisis) do table.insert(noms, c.nom or "") end
    bandeau.titre:SetText(table.concat(noms, "     "))
    bandeau.contre:SetText(porte and porte.nom
        and string.format(L.EQUIP_AGAINST, porte.nom) or L.EQUIP_AGAINST_NOTHING)

    local cles, vues = {}, {}
    local function ajouter(stats)
        for cle in pairs(stats or {}) do
            if not vues[cle] then vues[cle] = true table.insert(cles, cle) end
        end
    end
    ajouter(porte and porte.stats)
    for _, c in ipairs(choisis) do ajouter(c.stats) end
    NS.objets.OrdonnerStats(cles)

    -- Le niveau d'objet en premier, il se lit comme une statistique.
    table.insert(cles, 1, "__niveau")

    -- Un chiffre au plus apres la virgule (les degats par seconde).
    local function Chiffre(v)
        v = tonumber(v) or 0
        local arrondi = math.floor(math.abs(v) * 10 + 0.5) / 10
        if v < 0 then arrondi = -arrondi end
        if arrondi == math.floor(arrondi) then return string.format("%d", arrondi) end
        return string.format("%.1f", arrondi)
    end
    local index = 0
    for _, cle in ipairs(cles) do
        index = index + 1
        local ligne = CreerLigneStat(bandeau, index)
        local colonne = math.floor((index - 1) / LIGNES_PAR_COLONNE)
        local rang = (index - 1) % LIGNES_PAR_COLONNE
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8 + colonne * 345, -50 - rang * 13)
        ligne:SetWidth(330)

        local libelle = (cle == "__niveau") and L.EQUIP_LEVEL:gsub("%%d", ""):gsub("%s+$", "")
            or NS.objets.LibelleDeStat(cle)
        ligne.cle:SetText(libelle)

        local base = (cle == "__niveau") and (porte and porte.niveau or 0)
            or ((porte and porte.stats and porte.stats[cle]) or 0)
        ligne.colonnes[1]:SetText(Chiffre(base))
        ligne.colonnes[1]:SetTextColor(0.55, 0.55, 0.55)

        local c = choisis[1]
        local valeur = c and ((cle == "__niveau") and (c.niveau or 0) or ((c.stats and c.stats[cle]) or 0)) or 0
        local ecart = valeur - base
        ligne.colonnes[2]:SetText(Chiffre(valeur))
        ligne.colonnes[3]:SetText((ecart > 0 and "+" or "") .. Chiffre(ecart))
        local r, g, b = 0.55, 0.55, 0.55
        if ecart > 0 then r, g, b = 0.31, 0.82, 0.41 elseif ecart < 0 then r, g, b = 0.85, 0.40, 0.37 end
        ligne.colonnes[2]:SetTextColor(r, g, b)
        ligne.colonnes[3]:SetTextColor(r, g, b)
        ligne.colonnes[2]:Show()
        ligne.colonnes[3]:Show()
        ligne:Show()
    end
    for suite = index + 1, #(bandeau.stats or {}) do bandeau.stats[suite]:Hide() end
    -- Titres des colonnes, au-dessus de chaque bloc de statistiques.
    bandeau.titresCol = bandeau.titresCol or {}
    local blocs = math.max(1, math.ceil(index / LIGNES_PAR_COLONNE))
    for bloc = 1, 2 do
        local t = bandeau.titresCol[bloc]
        if not t then
            t = {}
            for rang = 1, 3 do
                local fs = bandeau:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetJustifyH("LEFT")
                fs:SetWidth(58)
                fs:SetWordWrap(false)
                t[rang] = fs
            end
            bandeau.titresCol[bloc] = t
        end
        for rang, fs in ipairs(t) do
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8 + (bloc - 1) * 345 + 140 + (rang - 1) * 62, -36)
            fs:SetText(({ L.GEAR_COL_WORN, L.GEAR_COL_NEW, L.GEAR_COL_DIFF })[rang])
            fs:SetShown(bloc <= blocs)
        end
    end
end

function equipement.Rendre(contenu, bandeau)
    L = NS.L
    local vue = equipement.Construire(contenu, bandeau)
    vue:Show()

    -- Vue "tous les personnages" (stocks) : l'equipement reste celui du
    -- personnage connecte.
    local cleAffichee = NS.base.CleAffichee() or NS.ClePersonnage() or "?"
    local estConnecte = (cleAffichee == NS.ClePersonnage())
    local fiche = NS.base.FicheAffichee()

    -- Scenario 2 : les origines en onglets tout en haut ; le reste descend.
    local scenario = equipement.Scenario()
    local decalage = (scenario == 2) and 36 or 0
    vue.premierG:ClearAllPoints()
    vue.premierG:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, -decalage)
    vue.premierD:ClearAllPoints()
    vue.premierD:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE + 8, -decalage)
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        if emplacement.cote == "bas" then
            local bouton = vue.cases[emplacement.nom]
            bouton:ClearAllPoints()
            bouton:SetPoint("TOPLEFT", vue, "TOPLEFT",
                bouton.rang * ((LARGEUR_COLONNE * 2 + 8) / 3), -(vue.hauteurColonnes + 8 + decalage))
        end
    end
    vue.choix:ClearAllPoints()
    vue.choix:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE * 2 + 34, -decalage)
    vue.choix:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)
    -- Un separateur leger entre la poupee et la liste.
    if not vue.separateur then
        vue.separateur = vue:CreateTexture(nil, "ARTWORK")
        vue.separateur:SetColorTexture(0.42, 0.18, 0.02, 0.18)
        if vue.separateur.SetSnapToPixelGrid then vue.separateur:SetSnapToPixelGrid(false) vue.separateur:SetTexelSnappingBias(0) end
    end
    vue.separateur:ClearAllPoints()
    local PU = _G.PixelUtil
    if PU and PU.SetWidth then PU.SetWidth(vue.separateur, 1, 1) else vue.separateur:SetWidth(1) end
    vue.separateur:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE * 2 + 22, -(decalage + 4))
    vue.separateur:SetPoint("BOTTOMLEFT", vue, "BOTTOMLEFT", LARGEUR_COLONNE * 2 + 22, 8)
    vue.separateur:Show()
    vue.onglets = vue.onglets or {}
    equipement.onglets = vue.onglets
    -- Onglets tous de la meme largeur, celle du libelle le plus long : jamais
    -- coupes.
    local largeurOnglet = 0
    do
        local mesure = vue.mesureOnglet or vue:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        vue.mesureOnglet = mesure
        mesure:Hide()
        for _, cat in ipairs(NS.sources.ORDRE) do
            mesure:SetText(L["GEAR_CAT_" .. cat])
            largeurOnglet = math.max(largeurOnglet, mesure:GetStringWidth() or 80)
        end
        largeurOnglet = math.floor(largeurOnglet + 44)
    end
    local precedentOnglet
    for rang, cat in ipairs(NS.sources.ORDRE) do
        local o = vue.onglets[rang]
        if not o then
            local ok, cree = pcall(CreateFrame, "Button", nil, vue, "PanelTopTabButtonTemplate")
            if not ok or not cree then ok, cree = pcall(CreateFrame, "Button", nil, vue, "PanelTabButtonTemplate") end
            if not ok or not cree then cree = CreateFrame("Button", nil, vue, "UIPanelButtonTemplate") end
            o = cree
            o:SetHeight(28)
            vue.onglets[rang] = o
        end
        o:SetText(L["GEAR_CAT_" .. cat])
        o:ClearAllPoints()
        if precedentOnglet then o:SetPoint("LEFT", precedentOnglet, "RIGHT", 2, 0)
        else o:SetPoint("TOPLEFT", vue, "TOPLEFT", 28, 0) end -- la place de LT
        precedentOnglet = o
        local actif = equipement.Categorie() == cat
        if actif then
            if _G.PanelTemplates_SelectTab then pcall(_G.PanelTemplates_SelectTab, o) end
            o:SetAlpha(1)
        else
            if _G.PanelTemplates_DeselectTab then pcall(_G.PanelTemplates_DeselectTab, o) end
            o:SetAlpha(0.75)
        end
        -- Apres le jeu (qui retaille ses onglets au plus juste) : notre largeur,
        -- et le libelle en entier.
        o:SetWidth(largeurOnglet)
        local fs = o.GetFontString and o:GetFontString()
        if fs then fs:SetWidth(largeurOnglet - 16) fs:SetWordWrap(false) end
        o:SetScript("OnClick", function()
            equipement.PoserCategorie(cat)
            NS.ecran.selectionObjets = {}
            equipement.Rendre(contenu, bandeau)
        end)
        o:SetShown(scenario == 2)
    end

    -- Emplacements.
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local bouton = vue.cases[emplacement.nom]
        local objet, lienObjet = ObjetPorteDe(fiche, emplacement.nom, estConnecte)
        local info = objet and InfosObjet(objet, lienObjet)

        bouton.ou:SetText(NS.emplacements.LibelleDuSlot(emplacement))
        if info and info.nom then
            bouton.porte:SetText(info.nom)
            bouton.porte:SetTextColor(NS.objets.CouleurDuNom(objet))
        elseif objet then
            bouton.porte:SetText(L.EQUIP_NOT_READ)
            bouton.porte:SetTextColor(0.55, 0.55, 0.55)
        else
            bouton.porte:SetText(L.EQUIP_EMPTY)
            bouton.porte:SetTextColor(0.55, 0.55, 0.55)
        end
        if info and info.icone then
            bouton.icone:SetTexture(info.icone)
            bouton.icone:Show()
        else
            bouton.icone:Hide()
        end

        local candidats = NS.transverse.Candidats(emplacement.code)
        local combien = #candidats.moi + #candidats.autres + #candidats.possedes
        bouton.marque:SetShown(combien > 0)

        if emplacement.nom == vue.choisi then
            bouton.ou:SetTextColor(1, 0.82, 0)
        else
            bouton.ou:SetTextColor(0.82, 0.69, 0.4)
        end
        bouton:Show()
    end

    vue.choisi = vue.choisi or NS.emplacements.DuPersonnage[1].nom
    local emplacementChoisi
    for _, e in ipairs(NS.emplacements.DuPersonnage) do
        if e.nom == vue.choisi then emplacementChoisi = e break end
    end

    local objetPorte, lienPorte = ObjetPorteDe(fiche, vue.choisi, estConnecte)
    local porte = InfosObjet(objetPorte, lienPorte)

    local choix = vue.choix
    choix.titre:SetText(NS.emplacements.LibelleDuSlot(emplacementChoisi))
    choix.sousTitre:SetText(porte and (porte.nom or L.EQUIP_NOT_READ) or L.EQUIP_EMPTY)

    -- Filtres de matiere : seulement les armures que ce personnage peut porter.
    -- La meilleure pour sa classe et son niveau est la preference, active par
    -- defaut ; une matiere encore portable mais depassee reste proposee, en
    -- retrait. Le reste n'est meme pas montre. Un emplacement d'arme ou de
    -- bijou n'a pas de matiere : la rangee disparait.
    local portables = NS.transverse.ArmuresPortables(fiche)
    NS.ecran.filtresParPerso = NS.ecran.filtresParPerso or {}
    local filtresPerso = NS.ecran.filtresParPerso[cleAffichee]
    if not filtresPerso then
        filtresPerso = {}
        for sous, rang in pairs(portables) do
            if rang == "prefere" then filtresPerso[sous] = true end
        end
        NS.ecran.filtresParPerso[cleAffichee] = filtresPerso
    end

    -- Toutes les sources de cet emplacement, deja filtrees par ce que le
    -- personnage peut porter et par son niveau (plus la marge reglee).
    local G = NS.base.ReglagesGeneraux()
    local marge = G.tousNiveauxEquipement and 999 or (tonumber(G.margeEquipement) or 10)
    if NS.sources.Etat() == "absent" then
        NS.sources.Construire(function()
            if NS.ecran.page == "equipement" and contenu:IsVisible() then equipement.Rendre(contenu, bandeau) end
        end)
    end
    local toutes = NS.sources.Candidats(emplacementChoisi.code, fiche, marge)
    local presentes, matieres, nomsMatieres = {}, {}, {}
    for _, cat in ipairs(NS.sources.ORDRE) do
        for _, c in ipairs(toutes[cat]) do
            local sous = NS.transverse.SousClasseDe(c.id)
            if sous and portables[sous] and not presentes[sous] then
                presentes[sous] = true
                nomsMatieres[sous] = NS.transverse.MatiereDe(c.id) or tostring(sous)
                table.insert(matieres, sous)
            end
        end
    end
    -- La preference d'abord, puis les autres de la plus lourde a la plus legere.
    table.sort(matieres, function(a, b)
        if (portables[a] == "prefere") ~= (portables[b] == "prefere") then return portables[a] == "prefere" end
        return a > b
    end)
    local precedentFiltre
    for rang, sous in ipairs(matieres) do
        local bouton = choix.filtres[rang]
        if not bouton then
            bouton = CreerBoutonFiltre(choix)
            choix.filtres[rang] = bouton
        end
        local actif = filtresPerso[sous] == true
        bouton:SetText(nomsMatieres[sous])
        bouton:SetWidth(math.max(54, (bouton.GetTextWidth and bouton:GetTextWidth() or 40) + 16))
        -- Preference pleine ; matiere depassee en retrait, meme active.
        if portables[sous] == "prefere" then
            bouton:SetAlpha(actif and 1 or 0.6)
        else
            bouton:SetAlpha(actif and 0.75 or 0.4)
        end
        bouton:SetScript("OnClick", function()
            filtresPerso[sous] = (not filtresPerso[sous]) or nil
            equipement.Rendre(contenu, bandeau)
        end)
        bouton:ClearAllPoints()
        if precedentFiltre then
            bouton:SetPoint("LEFT", precedentFiltre, "RIGHT", 3, 0)
        else
            bouton:SetPoint("TOPLEFT", choix.sousTitre, "BOTTOMLEFT", 0, -6)
        end
        bouton:Show()
        precedentFiltre = bouton
    end
    for rang = #matieres + 1, #choix.filtres do choix.filtres[rang]:Hide() end

    -- Haut de la liste : sous les filtres, ou sous le titre s'il n'y en a pas.
    -- Toujours le premier filtre, aligne a gauche sous le titre : jamais le
    -- dernier, qui decalerait la liste vers la droite.
    local ancreHaut = (#matieres > 0 and choix.filtres[1]) or choix.sousTitre
    vue.depot:Show()
    -- Dans la case : l'objet depose, sinon celui choisi dans la liste.
    local montre = NS.ecran.objetDepose or next(NS.ecran.selectionObjets or {})
    if montre then
        vue.depot.image:SetTexture(NS.Appeler(NS.jeu.iconeObjet, montre))
        vue.depot.image:Show()
    else
        vue.depot.image:Hide()
    end
    vue.depot.texte:SetText(L.GEAR_DROP)

    -- Les candidats : seulement ce qui ameliore ce qui est porte (au moins +1
    -- dans une statistique, meme si d'autres baissent). Selon le scenario de
    -- navigation : une origine choisie (menu ou onglets), ou toutes a la fois.
    local aucunFiltre = (next(filtresPerso) == nil)
    local function garde(id)
        local sous = NS.transverse.SousClasseDe(id)
        if not sous then return true end
        if not portables[sous] then return false end
        if aucunFiltre then return true end
        return filtresPerso[sous] == true
    end
    local categories = {}
    if scenario == 3 then
        for _, cat in ipairs(NS.sources.ORDRE) do
            if equipement.FiltreActif(cat) then table.insert(categories, cat) end
        end
    else
        categories = { equipement.Categorie() }
    end
    local statsPorte = porte and porte.stats or {}
    local retenus, enAttente = {}, 0
    local dejaVu = {}
    for _, cat in ipairs(categories) do
        for _, c in ipairs(toutes[cat] or {}) do
            if garde(c.id) and not dejaVu[cat .. ":" .. c.id] then
                local mieux, gains = NS.sources.Ameliore(c.id, statsPorte)
                if mieux == nil then
                    enAttente = enAttente + 1
                    NS.sources.Charger(c.id)
                elseif mieux then
                    dejaVu[cat .. ":" .. c.id] = true
                    local total = 0
                    for _, g in ipairs(gains) do total = total + (g.poids or g.ecart) end
                    table.insert(retenus, { c = c, cat = cat, gains = gains, total = total })
                end
            end
        end
    end
    -- Presentation 3 : toutes les origines, les unes sous les autres, chacune
    -- avec son titre ; dans chaque origine, le plus gros gain d'abord.
    local rangCat = {}
    for k, cat in ipairs(NS.sources.ORDRE) do rangCat[cat] = k end
    table.sort(retenus, function(a, b)
        if a.cat ~= b.cat then return rangCat[a.cat] < rangCat[b.cat] end
        if a.total ~= b.total then return a.total > b.total end
        return a.c.id < b.c.id
    end)
    -- L'objet porte pas encore lu : la page se redessinera a son arrivee.
    if objetPorte and not (porte and porte.nom and porte.stats) then
        enAttente = enAttente + 1
        NS.sources.Charger(objetPorte)
    end
    vue.enAttente = enAttente

    -- Legende : ce qui est en cours de lecture, ou l'etat de la base.
    if not vue.legende then
        vue.legende = vue.choix:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        vue.legende:SetJustifyH("LEFT")
    end
    vue.legende:ClearAllPoints()
    vue.legende:SetPoint("TOPLEFT", ancreHaut, "BOTTOMLEFT", 0, -6)
    vue.legende:SetWidth(LARGEUR_CHOIX - 10)
    vue.legende:SetWordWrap(false)
    local etat = NS.sources.Etat()
    local texteLegende
    if etat == "construction" then texteLegende = L.GEAR_INDEXING
    elseif etat == "sansBase" then texteLegende = L.GEAR_NODB
    elseif enAttente > 0 then texteLegende = string.format(L.GEAR_LOADING, enAttente) end
    vue.legende:SetText(texteLegende or "")
    vue.legende:SetShown(texteLegende ~= nil)
    vue.defilement:ClearAllPoints()
    vue.defilement:SetPoint("TOPLEFT", texteLegende and vue.legende or ancreHaut, "BOTTOMLEFT", 0, -6)
    vue.defilement:SetPoint("BOTTOMRIGHT", vue.choix, "BOTTOMRIGHT", -24, 0)

    NS.ecran.selectionObjets = NS.ecran.selectionObjets or {}
    local liste = vue.liste
    local index, y = 0, 0
    local choisis = {}
    local rien = #retenus == 0

    -- Gains en court : les deux plus forts, "+3 Agilite, +2 Endurance".
    local function TexteGains(gains)
        local morceaux = {}
        for k, g in ipairs(gains) do
            if k > 2 then break end
            local v = math.floor(g.ecart * 10 + 0.5) / 10
            local texteV = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v)
            table.insert(morceaux, "+" .. texteV .. " " .. (NS.objets.LibelleDeStat(g.cle) or tostring(g.cle)))
        end
        return table.concat(morceaux, ", ")
    end

    local catPrecedente
    for _, r in ipairs(retenus) do
        local c = r.c
        if scenario == 3 and r.cat ~= catPrecedente then
            catPrecedente = r.cat
            index = index + 1
            local titreCat = CreerLigneCandidat(liste, index)
            titreCat:ClearAllPoints()
            titreCat:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -(y + (index > 1 and 6 or 0)))
            titreCat:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -(y + (index > 1 and 6 or 0)))
            titreCat.icone:Hide()
            if titreCat.gains then titreCat.gains:Hide() end
            if titreCat.coche then titreCat.coche:Hide() end
            if titreCat.palier then titreCat.palier:Hide() end
            titreCat.fond:Hide()
            titreCat.nom:ClearAllPoints()
            titreCat.nom:SetPoint("TOPLEFT", titreCat, "TOPLEFT", 2, -4)
            titreCat.nom:SetPoint("RIGHT", titreCat, "RIGHT", -4, 0)
            titreCat.nom:SetFontObject("GameFontNormal")
            titreCat.nom:SetTextColor(1, 0.82, 0)
            titreCat.nom:SetText(L["GEAR_CAT_" .. r.cat])
            titreCat.etat:SetText("")
            titreCat:SetScript("OnEnter", nil)
            titreCat:SetScript("OnLeave", nil)
            titreCat:SetScript("OnClick", nil)
            titreCat:EnableMouse(false)
            titreCat:SetHeight(22)
            titreCat:Show()
            y = y + 22 + (index > 1 and 6 or 0)
        end
        index = index + 1
        local ligne = CreerLigneCandidat(liste, index)
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
        ligne:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)
        local info = NS.objets.Info(c.id)
        if info and info.icone then ligne.icone:SetTexture(info.icone) ligne.icone:Show() else ligne.icone:Hide() end
        ligne.nom:SetFontObject("GameFontHighlightSmall")
        local niveauTexte = ""
        if c.niveau and c.niveau > (tonumber(fiche and fiche.niveau) or 0) then
            niveauTexte = "  |cffff4040" .. string.format(L.LEVEL_SHORT or "niv. %d", c.niveau) .. "|r"
        end
        ligne.nom:SetText(((info and info.nom) or ("objet " .. tostring(c.id))) .. niveauTexte)
        ligne.nom:SetTextColor(NS.objets.CouleurDuNom(c.id))
        local prov = c.provenance or ""
        ligne.etat:SetText(prov)
        ligne.etat:SetTextColor(0.62, 0.62, 0.62)
        -- Le nom en entier : les gains se lisent en bas, a la comparaison.
        if ligne.gains then ligne.gains:Hide() end
        ligne.nom:ClearAllPoints()
        ligne.nom:SetPoint("TOPLEFT", ligne, "TOPLEFT", 25, -4)
        ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -4, 0)
        ligne:EnableMouse(true)
        if ligne.coche then ligne.coche:Hide() end
        if ligne.palier then ligne.palier:Hide() end

        local cleChoix = c.id
        local choisi = NS.ecran.selectionObjets[cleChoix] == true
        ligne.fond:SetShown(choisi)
        if choisi then
            local ficheObjet = InfosObjet(c.id)
            if ficheObjet then
                ficheObjet.source = { origine = (r.cat == "craftInterne" and not c.plusTard) and "moi" or r.cat,
                    objet = c.id, recette = c.recette }
                table.insert(choisis, ficheObjet)
            end
        end
        ligne:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, cleChoix) end
            local recette = c.recette and (CraftCoreDB.recettes or {})[tostring(c.recette)]
            if recette then NS.inventaire.ComposantsDansLInfobulle(GameTooltip, recette) end
            GameTooltip:Show()
        end)
        ligne:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Un seul objet compare a la fois : plus lisible.
        ligne:SetScript("OnClick", function()
            if NS.ecran.selectionObjets[cleChoix] then
                NS.ecran.selectionObjets = {}
            else
                NS.ecran.selectionObjets = { [cleChoix] = true }
                NS.ecran.objetDepose = nil
            end
            equipement.Rendre(contenu, bandeau)
        end)
        -- Toujours la meme hauteur : le nom sur une ligne, la provenance dessous.
        ligne:SetHeight(36)
        ligne:Show()
        y = y + 36 + 2
    end

    -- L'objet depose par glisser, s'il va a cet emplacement.
    if NS.ecran.objetDepose then
        local objet = NS.ecran.objetDepose
        if NS.emplacements.DeLObjet(objet) == emplacementChoisi.code then
            local fiche = InfosObjet(objet)
            if fiche then
                fiche.source = { origine = "depose" }
                table.insert(choisis, fiche)
                rien = false
            end
        else
            NS.ecran.objetDepose = nil
        end
    end

    if rien then
        index = index + 1
        local vide = CreerLigneCandidat(liste, index)
        vide:ClearAllPoints()
        vide:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
        vide:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)
        vide.fond:Hide()
        vide.icone:Hide()
        vide.nom:SetFontObject("GameFontDisableSmall")
        vide.nom:SetText(L.GEAR_NO_UPGRADE)
        if vide.gains then vide.gains:Hide() end
        vide.nom:SetTextColor(0.55, 0.55, 0.55)
        vide.etat:SetText("")
        if vide.coche then vide.coche:Hide() end
        if vide.palier then vide.palier:Hide() end
        vide:SetScript("OnEnter", nil)
        vide:SetScript("OnLeave", nil)
        vide:SetScript("OnClick", nil)
        vide:SetHeight(HAUTEUR_CANDIDAT)
        vide:Show()
        y = y + HAUTEUR_CANDIDAT
    end

    for suite = index + 1, #(liste.candidats or {}) do liste.candidats[suite]:Hide() end
    liste:SetHeight(math.max(y, 1))

    -- Au plus deux objets compares a la fois.
    while #choisis > 1 do table.remove(choisis) end
    RendreBandeau(bandeau, porte, choisis)
    equipement.PoserBoutonDeProjet(bandeau, choisis, emplacementChoisi, contenu)
end

-- Bouton de projet transverse, quand l'objet retenu est fabricable par un autre.
function equipement.PoserBoutonDeProjet(bandeau, choisis, emplacement, contenu)
    local transverse
    for _, c in ipairs(choisis) do
        if c.source and c.source.qui and c.source.recette then transverse = c break end
    end

    if not bandeau.boutonProjet then
        bandeau.boutonProjet = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonProjet:SetHeight(20)
        bandeau.boutonProjet:SetPoint("BOTTOMRIGHT", bandeau, "BOTTOMRIGHT", -8, 4)
    end

    -- Fabriquer : un objet que le personnage connecte sait faire, et qu'il
    -- peut faire maintenant. Meme bouton que dans les recettes.
    local aFaire
    for _, c in ipairs(choisis) do
        if c.source and c.source.origine == "moi" and c.source.recette then aFaire = c break end
    end
    if not bandeau.boutonFabriquer then
        bandeau.boutonFabriquer = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonFabriquer:SetHeight(20)
    end
    local fabriquer = bandeau.boutonFabriquer
    -- Ajouter : en projet ou en fabrication rapide, sans quitter la page.
    if not bandeau.boutonAjouter then
        bandeau.boutonAjouter = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonAjouter:SetHeight(20)
    end
    local ajouter = bandeau.boutonAjouter
    ajouter:ClearAllPoints()
    if transverse then
        ajouter:SetPoint("BOTTOMRIGHT", bandeau.boutonProjet, "BOTTOMLEFT", -6, 0)
    else
        ajouter:SetPoint("BOTTOMRIGHT", bandeau, "BOTTOMRIGHT", -8, 4)
    end
    fabriquer:ClearAllPoints()
    fabriquer:SetPoint("BOTTOMRIGHT", ajouter, "BOTTOMLEFT", -6, 0)
    if aFaire and NS.base.CleAffichee() == NS.ClePersonnage() then
        local idRecette, nomObjet = aFaire.source.recette, aFaire.nom
        -- Un clic, une action : l'objet part dans les fabrications rapides.
        ajouter:SetText(L.GEAR_ADD)
        ajouter:SetWidth(math.max(90, (ajouter.GetTextWidth and ajouter:GetTextWidth() or 70) + 24))
        ajouter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.GEAR_ADD_TIP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ajouter:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ajouter:SetScript("OnClick", function()
            NS.actions.AjouterA({ cible = "rapides", nom = L.NAV_QUICK }, idRecette, nomObjet, 1)
            NS.ecran.Montrer(NS.ecran.page)
        end)
        ajouter:Show()
    else
        ajouter:Hide()
    end
    if aFaire and NS.base.CleAffichee() == NS.ClePersonnage() then
        local recette = CraftCoreDB.recettes and CraftCoreDB.recettes[tostring(aFaire.source.recette)]
        fabriquer:SetText(L.GEAR_CRAFT)
        fabriquer:SetWidth(math.max(90, (fabriquer.GetTextWidth and fabriquer:GetTextWidth() or 70) + 24))
        -- Toujours la, grise s'il manque des composants ; le survol dit
        -- lesquels et ou ils sont.
        NS.actions.PreparerBoutonFabriquer(fabriquer, recette, 1)
    else
        fabriquer:Hide()
    end

    -- Plus de rangee de destinations : on cache celle d'une ancienne version.
    for _, b in ipairs(bandeau.choixAjout or {}) do b:Hide() end

    if not transverse then
        bandeau.boutonProjet:Hide()
        return
    end

    local libelle = string.format(L.GEAR_MAKE_PROJECT, transverse.nom or "", transverse.source.nomCourt)
    bandeau.boutonProjet:SetText(libelle)
    bandeau.boutonProjet:SetWidth(math.max(200,
        (bandeau.boutonProjet.GetTextWidth and bandeau.boutonProjet:GetTextWidth() or 180) + 24))
    bandeau.boutonProjet:SetScript("OnClick", function()
        NS.projets.CreerTransverse(transverse.source.qui, NS.base.CleAffichee(),
            transverse.source.recette, transverse.nom)
        NS.ecran.Montrer("projets")
    end)
    bandeau.boutonProjet:Show()
end

function equipement.Cacher(contenu, bandeau)
    if contenu.equipement then
        contenu.equipement:Hide()
        if contenu.equipement.depot then contenu.equipement.depot:Hide() end
    end
    if bandeau then
        bandeau:Hide()
        if bandeau.boutonProjet then bandeau.boutonProjet:Hide() end
        if bandeau.boutonFabriquer then bandeau.boutonFabriquer:Hide() end
        if bandeau.boutonAjouter then bandeau.boutonAjouter:Hide() end
        for _, b in ipairs(bandeau.choixAjout or {}) do b:Hide() end
    end
end

-- Chaque redessin de la page (choix d'un emplacement, d'un objet a comparer)
-- repasse les textes a l'encre sur parchemin, comme le dessin complet de la
-- fenetre : sinon les couleurs redeviennent claires et sans ombre.
do
    local rendreBrut = equipement.Rendre
    equipement.Rendre = function(contenu, bandeau, ...)
        local resultat = { rendreBrut(contenu, bandeau, ...) }
        pcall(function()
            local parchemin = NS.charte.Fond() == "parchemin"
            if contenu then NS.charte.Encrer(contenu, parchemin) end
            if bandeau then NS.charte.Encrer(bandeau, parchemin) end
        end)
        return unpack(resultat)
    end
end

-- Objets lus par le jeu apres coup (stats inconnues au premier affichage) :
-- la page se redessine, au plus deux fois par seconde, tant qu'il en manque.
do
    local derniers
    local rendreAvant = equipement.Rendre
    equipement.Rendre = function(contenu, bandeau, ...)
        derniers = { contenu, bandeau }
        return rendreAvant(contenu, bandeau, ...)
    end
    local attente = false
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function()
        if attente or not derniers then return end
        local vue = derniers[1] and derniers[1].equipement
        if not (vue and vue:IsVisible() and (vue.enAttente or 0) > 0) then return end
        attente = true
        C_Timer.After(0.5, function()
            attente = false
            local v = derniers[1] and derniers[1].equipement
            if v and v:IsVisible() then pcall(equipement.Rendre, derniers[1], derniers[2]) end
        end)
    end)
end
