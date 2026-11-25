local _, NS = ...

-- La fenetre d'AchievementCore, comme le journal des hauts faits du jeu mais
-- avec les conventions de la suite : les categories a gauche (menu de la
-- fenetre a pages), l'avancement a droite. Chaque page descend sur trois
-- niveaux : la categorie (ses sous-categories), une sous-categorie (ses
-- elements), un element (ses criteres, faits ou non). A chaque niveau,
-- l'avancement de ce qu'on regarde pour le personnage, la Horde, l'Alliance
-- et les deux camps, puis le detail pour la portee choisie.

NS.fenetre = {}
local F = NS.fenetre
local T = NS.T
local ref = NS.ref
local calcul = NS.calcul
local persos = NS.persos

local HAUTEUR_LIGNE = 24
local RETRAIT = 16
local PAR_PAGE = 100
local VERT = { 0.31, 0.82, 0.41 }
local GRIS = { 0.6, 0.6, 0.6 }
local BLANC = { 1, 1, 1 }
local SECONDAIRE = { 0.8, 0.8, 0.8 }
local COCHE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local CROIX = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

-- ---------------------------------------------------------------------------
-- Portee affichee : un personnage, un camp, ou les deux
-- ---------------------------------------------------------------------------

local etat = { portee = nil, nav = {}, persoVu = nil }
F.etat = etat

local function PorteeParDefaut()
    local cle = NS.ClePersonnage()
    if cle and persos.Par(cle) then return "perso:" .. cle end
    local l = persos.Liste()
    if l[1] then return "perso:" .. l[1].cle end
    return "deux"
end

-- Le personnage choisi ailleurs dans la suite vaut ici aussi.
local function SuivreLaSuite()
    local S = _G.CoreSuite
    if not (S and S.Personnage) then return end
    local cle, version = S.Personnage()
    if version and version ~= etat.persoVu then
        etat.persoVu = version
        if cle and persos.Par(cle) then etat.portee = "perso:" .. cle end
    end
end

function F.Portee()
    SuivreLaSuite()
    if not etat.portee or not calcul.PorteeValide(etat.portee) then etat.portee = PorteeParDefaut() end
    return etat.portee
end

function F.PoserPortee(v)
    etat.portee = v
    local cle = type(v) == "string" and v:match("^perso:(.+)$")
    local S = _G.CoreSuite
    if cle and S and S.PoserPersonnage then etat.persoVu = S.PoserPersonnage(cle) end
    for _, n in pairs(etat.nav) do n.page = 1 end
end

local function OptionsPortee()
    local liste = {}
    for _, portee in ipairs(calcul.Portees()) do
        table.insert(liste, { portee, calcul.NomDePortee(portee, true) })
    end
    return liste
end

-- Le personnage du resume : celui choisi, sinon le personnage connecte.
local function PorteePerso()
    local p = F.Portee()
    if p:match("^perso:") then return p end
    return PorteeParDefaut():match("^perso:") and PorteeParDefaut() or nil
end

-- ---------------------------------------------------------------------------
-- Lignes : icone ou portrait, nom (et ligne de detail), barre, valeur
-- ---------------------------------------------------------------------------

local function CouleurBarre(v)
    local couleurs = _G.FACTION_BAR_COLORS
    local rang = (v >= 1 and 8) or (v >= 0.75 and 5) or (v >= 0.5 and 4) or (v >= 0.25 and 3) or 2
    local f = type(couleurs) == "table" and couleurs[rang]
    return f and { f.r, f.g, f.b } or { 0.2, 0.7, 0.2 }
end

-- Barre d'avancement a la facon des reputations du jeu (comme QuestCore).
local function Barre(parent)
    local ok, b = pcall(CreateFrame, "StatusBar", nil, parent, "BackdropTemplate")
    b = ok and b or CreateFrame("StatusBar", nil, parent)
    b:SetSize(200, 12)
    b:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    b:SetMinMaxValues(0, 1)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetColorTexture(0, 0, 0, 0.65)
    local okC, cadre = pcall(CreateFrame, "Frame", nil, b, "BackdropTemplate")
    cadre = okC and cadre or CreateFrame("Frame", nil, b)
    cadre:SetPoint("TOPLEFT", -2, 2)
    cadre:SetPoint("BOTTOMRIGHT", 2, -2)
    if cadre.SetBackdrop then
        cadre:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
        cadre:SetBackdropBorderColor(0.8, 0.65, 0.35, 1)
    end
    cadre:SetFrameLevel(b:GetFrameLevel() + 2)
    b.texte = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.texte:SetPoint("CENTER", b, "CENTER", 0, 0)
    local fichier, _, drapeaux = b.texte:GetFont()
    if fichier then b.texte:SetFont(NS.Police(fichier), 9, drapeaux) end
    b.texte:SetShadowOffset(1, -1)
    -- Texte blanc sur la barre, jamais a l'encre du parchemin.
    b.texte.couleurPropre = true
    return b
end

local function Ligne(page, i)
    page.lignes = page.lignes or {}
    local l = page.lignes[i]
    if l then return l end
    l = CreateFrame("Button", nil, page.zone)
    pcall(l.RegisterForClicks, l, "LeftButtonUp")
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.cadreVisage = l:CreateTexture(nil, "BORDER")
    l.cadreVisage:SetSize(34, 34)
    l.cadreVisage:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    l.visage = l:CreateTexture(nil, "ARTWORK")
    l.visage:SetPoint("TOPLEFT", l.cadreVisage, "TOPLEFT", 5, -5)
    l.visage:SetPoint("BOTTOMRIGHT", l.cadreVisage, "BOTTOMRIGHT", -5, 5)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(18, 18)
    l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.nom:SetJustifyH("LEFT")
    l.nom:SetWordWrap(false)
    NS.charte.PoliceStable(l.nom)
    l.detail = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.detail:SetJustifyH("LEFT")
    l.detail:SetWordWrap(false)
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetJustifyH("RIGHT")
    l.droite:SetWordWrap(false)
    l.barre = Barre(l)
    page.lignes[i] = l
    return l
end

-- options : retrait, visage (perso), icone, coords, desature, texte, couleur,
-- police, detail, fait / total (barre), droite, couleurDroite, auClic, survol
local function Poser(page, i, y, o)
    local l = Ligne(page, i)
    local zone = page.zone
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
    l:SetPoint("TOPRIGHT", zone, "TOPRIGHT", 0, -y)
    local hauteur = (o.visage or o.detail) and 40 or HAUTEUR_LIGNE
    l:SetHeight(hauteur)
    local x = 2 + (o.retrait or RETRAIT)
    l.cadreVisage:Hide() l.visage:Hide() l.icone:Hide()
    if o.visage then
        l.cadreVisage:ClearAllPoints()
        l.cadreVisage:SetPoint("LEFT", l, "LEFT", x - 2, 0)
        l.cadreVisage:Show()
        l.visage:Show()
        persos.Visage(l.visage, o.visage)
        x = x + 38
    elseif o.icone then
        l.icone:ClearAllPoints()
        l.icone:SetPoint("LEFT", l, "LEFT", x, 0)
        l.icone:SetTexture(o.icone)
        if o.coords then l.icone:SetTexCoord(o.coords[1], o.coords[2], o.coords[3], o.coords[4]) else l.icone:SetTexCoord(0, 1, 0, 1) end
        l.icone:SetDesaturated(o.desature == true)
        l.icone:SetAlpha(o.desature and 0.6 or 1)
        l.icone:Show()
        x = x + 24
    end
    -- A droite : la valeur, puis la barre devant elle.
    l.droite:ClearAllPoints()
    l.droite:SetPoint("RIGHT", l, "RIGHT", -8, 0)
    l.droite:SetText(o.droite or "")
    local cd = o.couleurDroite or BLANC
    l.droite:SetTextColor(cd[1], cd[2], cd[3])
    l.droite.couleurPropre = o.droitePropre or nil
    local bord = l.droite
    if o.total then
        l.barre:ClearAllPoints()
        l.barre:SetPoint("RIGHT", l, "RIGHT", -58, 0)
        local v = (o.total > 0) and math.min(1, (o.fait or 0) / o.total) or 0
        l.barre:SetValue(v)
        local c = CouleurBarre(v)
        l.barre:SetStatusBarColor(c[1], c[2], c[3])
        l.barre.texte:SetText(o.texteBarre or (NS.Nombre(o.fait or 0) .. " / " .. NS.Nombre(o.total)))
        l.barre.texte:SetTextColor(1, 1, 1)
        l.barre:Show()
        bord = l.barre
        if not o.droite then l.droite:SetText(NS.TextePct(o.fait, o.total)) end
    else
        l.barre:Hide()
    end
    l.nom:SetFontObject(o.police or "GameFontHighlightSmall")
    l.nom:ClearAllPoints()
    if o.detail then l.nom:SetPoint("TOPLEFT", l, "TOPLEFT", x, -6) else l.nom:SetPoint("LEFT", l, "LEFT", x, 0) end
    l.nom:SetPoint("RIGHT", bord, "LEFT", -12, 0)
    l.nom:SetText(o.texte or "")
    local c = o.couleur or BLANC
    l.nom:SetTextColor(c[1], c[2], c[3], 1)
    -- Couleur de classe : la vraie, jamais a l'encre (le pretre reste blanc).
    l.nom.couleurPropre = c.classe or nil
    l.nom.nomDePerso = c.classe or nil
    if o.detail then
        l.detail:ClearAllPoints()
        l.detail:SetPoint("TOPLEFT", l.nom, "BOTTOMLEFT", 0, -4)
        l.detail:SetPoint("RIGHT", bord, "LEFT", -12, 0)
        l.detail:SetText(o.detail)
        l.detail:SetTextColor(SECONDAIRE[1], SECONDAIRE[2], SECONDAIRE[3])
        l.detail:Show()
    else
        l.detail:Hide()
    end
    l:SetScript("OnClick", o.auClic)
    l:SetScript("OnEnter", o.survol)
    l:SetScript("OnLeave", o.survol and function() GameTooltip:Hide() end or nil)
    l:EnableMouse(o.auClic ~= nil or o.survol ~= nil)
    local hl = l:GetHighlightTexture()
    if hl then hl:SetAlpha((o.auClic or o.survol) and 1 or 0) end
    l:Show()
    return y + hauteur + 2
end

-- Titre de section dans la zone : police et filet des parametres de la suite.
local function Titre(page, i, y, texte)
    page.titres = page.titres or {}
    local t = page.titres[i]
    if not t then
        t = { fs = page.zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = page.zone:CreateTexture(nil, "ARTWORK") }
        t.fs:SetJustifyH("LEFT")
        t.fs:SetWordWrap(false)
        page.titres[i] = t
    end
    if y > 0 then y = y + 14 end
    t.fs:ClearAllPoints()
    t.fs:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
    t.fs:SetPoint("RIGHT", page.zone, "RIGHT", -10, 0)
    t.fs:SetText(texte)
    t.filet:ClearAllPoints()
    t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
    t.filet:SetSize(math.max(100, (page.zone:GetWidth() or 600) - 10), 1)
    if NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet)
    else t.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
    t.fs:Show() t.filet:Show()
    return y + 34
end

-- Une ligne de texte simple (attente, absence de donnees).
local function Note(page, i, y, texte)
    page.notes = page.notes or {}
    local n = page.notes[i]
    if not n then
        n = page.zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n:SetJustifyH("LEFT")
        n:SetWordWrap(false)
        page.notes[i] = n
    end
    n:ClearAllPoints()
    n:SetPoint("TOPLEFT", page.zone, "TOPLEFT", RETRAIT, -(y + 4))
    n:SetPoint("RIGHT", page.zone, "RIGHT", -10, 0)
    n:SetText(texte)
    n:SetTextColor(SECONDAIRE[1], SECONDAIRE[2], SECONDAIRE[3])
    n:Show()
    return y + HAUTEUR_LIGNE
end

local function ToutCacher(page)
    for _, l in ipairs(page.lignes or {}) do l:Hide() end
    for _, t in ipairs(page.titres or {}) do t.fs:Hide() t.filet:Hide() end
    for _, n in ipairs(page.notes or {}) do n:Hide() end
    for _, r in ipairs(page.rangeesZone or {}) do r:Hide() end
end

-- ---------------------------------------------------------------------------
-- Infobulles (a l'endroit fixe de la fenetre, voir Suite.lua)
-- ---------------------------------------------------------------------------

local function NomsDe(cles, max)
    local morceaux = {}
    for k, cle in ipairs(cles or {}) do
        if k > (max or 3) then table.insert(morceaux, "+" .. (#cles - (max or 3))) break end
        local p = persos.Par(cle)
        local c = ref.CouleurDeClasse(p and p.classe)
        table.insert(morceaux, ref.Hex(c) .. NS.NomCourt(cle) .. "|r")
    end
    return table.concat(morceaux, "  ")
end

local function Infobulle(c)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if c.objet and GameTooltip.SetItemByID then
            if not pcall(GameTooltip.SetItemByID, GameTooltip, c.objet) then GameTooltip:SetText(c.nom, 1, 0.82, 0) end
        else
            GameTooltip:SetText(c.nom, 1, 0.82, 0)
            if c.quete then
                local q = NS.base.Quetes()
                q = type(q) == "table" and q.Q[c.quete]
                if c.niveau and c.niveau > 0 then GameTooltip:AddLine(string.format(T("Niveau %d", "Level %d"), c.niveau), 0.8, 0.8, 0.8) end
                if q and q.zone and q.zone > 0 then GameTooltip:AddLine(NS.NomDeZoneGarde(q.zone), 0.8, 0.8, 0.8) end
                if c.auChoix then GameTooltip:AddLine(T("Une quête au choix parmi plusieurs", "One quest to choose among several"), 0.8, 0.8, 0.8) end
            end
        end
        if c.qui and #c.qui > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(T("Fait par :", "Done by :"), 1, 0.82, 0)
            GameTooltip:AddLine(NomsDe(c.qui, 8), 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Resume : l'avancement de ce qu'on regarde, sur les quatre portees
-- ---------------------------------------------------------------------------

-- lire(portee) -> fait, total (ou nil si pas pret)
local function Resume(page, i, y, lire)
    local lignes = {}
    local pp = PorteePerso()
    if pp then table.insert(lignes, pp) end
    table.insert(lignes, "Horde")
    table.insert(lignes, "Alliance")
    table.insert(lignes, "deux")
    for _, portee in ipairs(lignes) do
        local fait, total = lire(portee)
        local o = { texte = calcul.NomDePortee(portee) }
        if portee:match("^perso:") then
            local p = persos.Par(portee:match("^perso:(.+)$"))
            o.couleur = ref.CouleurDeClasse(p and p.classe)
            o.icone, o.coords = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
                _G.CLASS_ICON_TCOORDS and p and _G.CLASS_ICON_TCOORDS[p.classe]
            if not o.coords then o.icone = "Interface\\Icons\\INV_Misc_GroupNeedMore" end
        elseif portee == "Horde" then o.icone = "Interface\\Icons\\INV_BannerPVP_01"
        elseif portee == "Alliance" then o.icone = "Interface\\Icons\\INV_BannerPVP_02"
        else o.icone = "Interface\\Icons\\INV_Misc_GroupNeedMore" end
        if total then
            o.fait, o.total = fait, total
            if total == 0 then o.texteBarre, o.droite = T("rien à faire", "nothing to do"), "" end
        else
            o.fait, o.total, o.texteBarre, o.droite = 0, 1, T("en préparation", "preparing"), ""
        end
        local cible = portee
        o.auClic = function() F.PoserPortee(cible) F.Rendre() end
        i = i + 1
        y = Poser(page, i, y, o)
    end
    return i, y
end

-- ---------------------------------------------------------------------------
-- Pages des categories
-- ---------------------------------------------------------------------------

local function Nav(page)
    etat.nav[page.cle] = etat.nav[page.cle] or { page = 1, filtre = "tout" }
    return etat.nav[page.cle]
end

local function Trouver(res, sousCle, elementCle)
    if not res then return nil end
    for _, s in ipairs(res.sous or {}) do
        if s.cle == sousCle then
            if not elementCle then return s end
            for _, e in ipairs(s.elements or {}) do if e.cle == elementCle then return e, s end end
            return nil
        end
    end
    return nil
end

-- Fait et total de ce qu'on regarde (categorie, sous-categorie, element).
local function Lecteur(cat, nav)
    return function(portee)
        local r = calcul.Resultat(cat.cle, portee)
        if not r then return nil end
        if not nav.sous then return r.fait, r.total end
        local x = Trouver(r, nav.sous, nav.element)
        if not x then return 0, 0 end
        return x.fait, x.total
    end
end

-- Les rangees de controles du dernier niveau : filtre et page.
local function Controles(page)
    if page.rFiltre then return end
    page.rangeesZone = {}
    local function Rangee()
        local r = CreateFrame("Frame", nil, page.zone)
        r:SetHeight(26)
        r.nom = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.nom:SetPoint("LEFT", RETRAIT, 0)
        r.nom:SetJustifyH("LEFT")
        table.insert(page.rangeesZone, r)
        return r
    end
    local S = _G.CoreSuite
    page.rFiltre = Rangee()
    page.lFiltre = S.ListeDeroulante(page.rFiltre, function() return {
            { "tout", T("Tout", "Everything") }, { "reste", T("Reste à faire", "Left to do") }, { "fait", T("Déjà fait", "Already done") } } end,
        function() return Nav(page).filtre end,
        function(v) Nav(page).filtre = v Nav(page).page = 1 end,
        function() F.Rendre() end)
    page.lFiltre:SetPoint("RIGHT", page.rFiltre, "RIGHT", -10, 0)
    table.insert(page.controles, page.lFiltre)
    page.rPage = Rangee()
    page.cPage = S.Curseur(page.rPage, 1, 999, 1, function() return Nav(page).page end,
        function(v) Nav(page).page = math.max(1, math.min(page.nbPages or 1, v)) F.Rendre() end,
        function(v) return string.format("%d / %d", v, page.nbPages or 1) end)
    page.cPage:SetPoint("RIGHT", page.rPage, "RIGHT", -10, 0)
    table.insert(page.controles, page.cPage)
end

local function PoserRangee(page, r, y, texte)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", page.zone, "TOPRIGHT", 0, -y)
    r.nom:SetText(texte)
    r:Show()
    return y + 32
end

-- Etat d'un critere a droite : coche, ou qui l'a fait (camp), ou les deux camps.
local function DroiteDeCritere(c, portee)
    if portee == "deux" then
        local morceaux = {}
        if c.faitH ~= nil then table.insert(morceaux, (c.faitH and COCHE or CROIX) .. " " .. T("Horde", "Horde")) end
        if c.faitA ~= nil then table.insert(morceaux, (c.faitA and COCHE or CROIX) .. " " .. T("Alliance", "Alliance")) end
        return table.concat(morceaux, "     ")
    end
    if c.fait then
        if c.qui and #c.qui > 0 then return NomsDe(c.qui, 3) .. "  " .. COCHE end
        return COCHE
    end
    return ""
end

local function CritereFait(c, portee)
    if portee == "deux" then
        if c.faitH == false or c.faitA == false then return false end
        return true
    end
    return c.fait == true
end

local function RendreCategorie(page, cat)
    local nav = Nav(page)
    local portee = F.Portee()
    if NS.base.Preparer then NS.base.Preparer() end
    ToutCacher(page)
    local res = calcul.Resultat(cat.cle, portee)
    -- Ce qu'on regarde existe-t-il encore (autre portee, donnees changees) ?
    if res and nav.sous and not Trouver(res, nav.sous) then nav.sous, nav.element = nil, nil end
    if res and nav.element and not Trouver(res, nav.sous, nav.element) then nav.element = nil end
    local sous = res and nav.sous and Trouver(res, nav.sous)
    local element = res and nav.element and Trouver(res, nav.sous, nav.element)
    page.t1:SetText((element and element.nom) or (sous and sous.nom) or cat.nom())
    page.bRetour:SetText(T("Retour", "Back"))
    page.bRetour:SetShown(nav.sous ~= nil)
    page.intro:SetText(cat.intro())
    page.rPortee.nom:SetText(T("Avancement affiché", "Progress shown"))
    local i, y, nt, nn = 0, 0, 0, 0
    if cat.Absente and cat.Absente() then
        nn = nn + 1
        y = Note(page, nn, y, T("La base QuestieDB n'est pas installée : cette catégorie n'a pas de liste à suivre.",
            "The QuestieDB database is not installed : this category has no list to follow."))
        page.hauteur = page.yZone + y + 10
        return
    end
    if not res then
        nn = nn + 1
        local pr = cat.Progres and cat.Progres() or 0
        y = Note(page, nn, y, string.format(T("Préparation de la liste : %d %%", "Preparing the list : %d %%"), math.floor((pr or 0) * 100)))
        page.hauteur = page.yZone + y + 10
        return
    end
    -- L'avancement de ce qu'on regarde, sur les quatre portees.
    nt = nt + 1
    y = Titre(page, nt, y, T("Avancement", "Progress"))
    i, y = Resume(page, i, y, Lecteur(cat, nav))
    if not sous then
        nt = nt + 1
        y = Titre(page, nt, y, string.format(T("Pour %s", "For %s"), calcul.NomDePortee(portee)))
        if #res.sous == 0 then nn = nn + 1 y = Note(page, nn, y, T("Rien à faire ici pour cette portée.", "Nothing to do here for this scope.")) end
        for _, s in ipairs(res.sous) do
            local cle = s.cle
            i = i + 1
            y = Poser(page, i, y, { icone = s.icone or cat.icone, texte = s.nom, fait = s.fait, total = s.total,
                auClic = function() nav.sous, nav.element, nav.page = cle, nil, 1 F.Defiler() F.Rendre() end })
        end
    else
        -- Elements d'une sous-categorie, ou criteres d'un element : la meme
        -- liste, filtree (tout, reste a faire, deja fait), par pages de 100.
        local liste = {}
        if element then
            for _, c in ipairs(element.Detail and element.Detail() or {}) do
                local f = CritereFait(c, portee)
                if nav.filtre == "tout" or (nav.filtre == "fait" and f) or (nav.filtre == "reste" and not f) then table.insert(liste, c) end
            end
        else
            for _, e in ipairs(sous.elements) do
                local f = e.fait >= e.total
                if nav.filtre == "tout" or (nav.filtre == "fait" and f) or (nav.filtre == "reste" and not f) then table.insert(liste, e) end
            end
        end
        Controles(page)
        y = y + 8
        y = PoserRangee(page, page.rFiltre, y, T("Afficher", "Show"))
        page.nbPages = math.max(1, math.ceil(#liste / PAR_PAGE))
        if nav.page > page.nbPages then nav.page = page.nbPages end
        if page.nbPages > 1 then y = PoserRangee(page, page.rPage, y, T("Page", "Page")) end
        nt = nt + 1
        y = Titre(page, nt, y, string.format(T("Pour %s", "For %s"), calcul.NomDePortee(portee)))
        if #liste == 0 then nn = nn + 1 y = Note(page, nn, y, T("Aucun élément à montrer.", "Nothing to show.")) end
        local debut = (nav.page - 1) * PAR_PAGE + 1
        for k = debut, math.min(#liste, debut + PAR_PAGE - 1) do
            local x = liste[k]
            i = i + 1
            if element then
                local f = CritereFait(x, portee)
                local icone = x.icone
                if x.objet then icone = NS.IconeDObjet(x.objet) end
                local nom = x.nom
                if x.niveau and x.niveau > 0 then nom = "[" .. x.niveau .. "] " .. nom end
                y = Poser(page, i, y, { icone = icone or cat.icone, coords = x.coords, desature = not f, texte = nom,
                    couleur = f and VERT or GRIS, droite = DroiteDeCritere(x, portee), droitePropre = true,
                    survol = Infobulle(x), auClic = function() end })
            else
                local cle = x.cle
                y = Poser(page, i, y, { icone = x.icone, coords = x.coords, texte = x.nom, couleur = x.couleur,
                    fait = x.fait, total = x.total,
                    auClic = function() nav.element, nav.page = cle, 1 F.Defiler() F.Rendre() end })
            end
        end
    end
    page.hauteur = page.yZone + y + 10
end

local function PageCategorie(cat)
    return { cle = cat.cle, icone = cat.icone, libelle = function() return cat.nom() end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
            page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -120, 0)
            page.bRetour = O.Bouton(page.cadre, 90, function()
                local nav = Nav(page)
                if nav.element then nav.element = nil else nav.sous = nil end
                nav.page = 1
                F.Defiler()
            end)
            page.bRetour:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.rPortee = O.Rangee()
            O.Liste(page.rPortee, OptionsPortee, F.Portee, F.PoserPortee)
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 12)
            page.yZone = page.y - 1
        end,
        rendre = function(page) RendreCategorie(page, cat) end }
end

-- ---------------------------------------------------------------------------
-- Vue d'ensemble : toutes les categories et tous les personnages
-- ---------------------------------------------------------------------------

local function RendreEnsemble(page)
    local portee = F.Portee()
    if NS.base.Preparer then NS.base.Preparer() end
    ToutCacher(page)
    page.t1:SetText(T("Vue d'ensemble", "Overview"))
    page.intro:SetText(T("Tout ce qui est faisable pour finir le jeu : par personnage, pour la Horde, pour l'Alliance et pour les deux camps.",
        "Everything you can do to finish the game : by character, for the Horde, for the Alliance and for both sides."))
    page.rPortee.nom:SetText(T("Avancement affiché", "Progress shown"))
    local i, y, nt, nn = 0, 0, 0, 0
    nt = nt + 1
    y = Titre(page, nt, y, T("Avancement général", "Overall progress"))
    i, y = Resume(page, i, y, function(p)
        local v, n, attendues = calcul.Global(p)
        if n == 0 then return nil end
        local r = math.floor(v * 1000 + 0.5)
        return r, 1000
    end)
    for k = 1, i do
        local l = page.lignes[k]
        if l and l.barre:IsShown() then
            -- Une moyenne : la barre dit le pourcentage, pas un nombre.
            l.barre.texte:SetText(l.droite:GetText() or "")
        end
    end
    -- Ce qui se prepare encore.
    local attente = {}
    for _, cat in ipairs(NS.categories) do
        if cat.Pret and not cat.Pret() and not (cat.Absente and cat.Absente()) then
            table.insert(attente, string.format("%s %d %%", cat.nom(), math.floor(((cat.Progres and cat.Progres()) or 0) * 100)))
        end
    end
    if #attente > 0 then
        nn = nn + 1
        y = Note(page, nn, y, T("En préparation : ", "Preparing : ") .. table.concat(attente, "   "))
    end
    nt = nt + 1
    y = Titre(page, nt, y, string.format(T("Catégories pour %s", "Categories for %s"), calcul.NomDePortee(portee)))
    for _, cat in ipairs(NS.categories) do
        if not (cat.Absente and cat.Absente()) or cat.cle == "quetes" or cat.cle == "objets" then
            local r = calcul.Resultat(cat.cle, portee)
            local cle = cat.cle
            local o = { icone = cat.icone, texte = cat.nom(),
                auClic = function() if F.w then F.w.page = cle F.Defiler() F.Rendre() end end }
            if r then o.fait, o.total = r.fait, r.total
            else o.fait, o.total, o.texteBarre, o.droite = 0, 1, (cat.Absente and cat.Absente()) and T("sans QuestieDB", "no QuestieDB") or T("en préparation", "preparing"), "" end
            if r and r.total == 0 then o.texteBarre, o.droite = T("rien à faire", "nothing to do"), "" end
            i = i + 1
            y = Poser(page, i, y, o)
        end
    end
    nt = nt + 1
    y = Titre(page, nt, y, T("Personnages", "Characters"))
    for _, p in ipairs(persos.Liste()) do
        local pp = "perso:" .. p.cle
        local v, n = calcul.Global(pp)
        local morceaux = {}
        if p.niveau then table.insert(morceaux, string.format(T("Niveau %d", "Level %d"), p.niveau)) end
        if p.race then table.insert(morceaux, ref.NomDeRace(p.race)) end
        if p.faction then table.insert(morceaux, p.faction == "Horde" and T("Horde", "Horde") or T("Alliance", "Alliance")) end
        local pct = math.floor(v * 100)
        local o = { retrait = 4, visage = p, texte = p.nom, police = "GameFontNormal", couleur = ref.CouleurDeClasse(p.classe),
            detail = table.concat(morceaux, "     "),
            auClic = function() F.PoserPortee(pp) F.Rendre() end }
        if n > 0 then o.fait, o.total, o.texteBarre, o.droite = pct, 100, pct .. " %", pct .. " %" end
        i = i + 1
        y = Poser(page, i, y, o)
    end
    page.hauteur = page.yZone + y + 10
end

local function PageEnsemble()
    return { cle = "ensemble", icone = "Interface\\Icons\\INV_Misc_Ribbon_01",
        libelle = function() return T("Vue d'ensemble", "Overview") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.rPortee = O.Rangee()
            O.Liste(page.rPortee, OptionsPortee, F.Portee, F.PoserPortee)
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 12)
            page.yZone = page.y - 1
        end,
        rendre = RendreEnsemble }
end

-- ---------------------------------------------------------------------------
-- La page de la suite complete (AchievementCore installe seul)
-- ---------------------------------------------------------------------------

local ADRESSE_SUITE = "https://www.curseforge.com/projects/1817365"
local function PageSuite()
    return { cle = "suite", icone = "Interface\\Icons\\INV_Misc_Book_11",
        libelle = function() return T("La suite", "The suite") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(70)
            page.t2 = O.Texte(20)
            page.rLien = O.Rangee(28)
            local e = CreateFrame("EditBox", nil, page.rLien, "InputBoxTemplate")
            e:SetSize(420, 24)
            e:SetPoint("LEFT", page.rLien, "LEFT", 6, 0)
            e:SetAutoFocus(false)
            e:SetText(ADRESSE_SUITE)
            e:SetCursorPosition(0)
            e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            e:SetScript("OnTextChanged", function(self, parUtilisateur)
                if parUtilisateur then self:SetText(ADRESSE_SUITE) self:HighlightText() end
            end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            table.insert(page.focus, e)
            page.aide = O.Detail(30)
        end,
        rendre = function(page)
            page.t1:SetText("Forever SagaCore")
            page.intro:SetText(T("AchievementCore fait partie de Forever SagaCore, une suite d'add-ons pour WoW Forever : fabrications et métiers (CraftCore), quêtes et trajets (QuestCore), carte et services (MapCore), héritage (LegacyCore). Installés ensemble, ils partagent la même fenêtre, les mêmes réglages et la même manette, et AchievementCore lit leurs relevés.",
                "AchievementCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls, and AchievementCore reads their records."))
            page.t2:SetText(T("Retrouvez la suite complète sur CurseForge :", "Get the complete suite on CurseForge :"))
            page.rLien.nom:SetText("")
            page.aide:SetText(T("Cliquez sur l'adresse, puis Ctrl+C (Cmd+C sur Mac) pour la copier.", "Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."))
        end }
end

-- ---------------------------------------------------------------------------
-- Construction, ouverture, rafraichissement
-- ---------------------------------------------------------------------------

function F.Construire()
    local S = _G.CoreSuite
    if F.w or not (S and S.FenetreAPages) then return F.w end
    local pages = { PageEnsemble() }
    for _, cat in ipairs(NS.categories) do
        -- L'heritage seulement quand LegacyCore a des releves.
        if not (cat.cle == "heritage" and cat.Absente and cat.Absente()) then table.insert(pages, PageCategorie(cat)) end
    end
    if S.Seul and S.Seul() then table.insert(pages, PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "AchievementCoreFenetre", cle = "AchievementCore", icone = "Interface\\Icons\\INV_Misc_Ribbon_01",
        titre = function() return "AchievementCore" end,
        pages = pages,
    })
    if F.w and F.w.cadre then
        -- A chaque ouverture : les releves des autres add-ons ont pu changer.
        F.w.cadre:HookScript("OnShow", function()
            NS.Changer("heritage", "metiers", "objets")
        end)
    end
    return F.w
end

function F.Ouvrir()
    local S = _G.CoreSuite
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("AchievementCore") return true end
    return false
end

function F.Visible() return F.w ~= nil and F.w.cadre ~= nil and F.w.cadre:IsShown() end

function F.Rendre() if F.w and F.w.Rendre then F.w.Rendre() end end

-- Remonte en haut de la page (nouveau niveau).
function F.Defiler()
    if F.w and F.w.defilement then pcall(F.w.defilement.SetVerticalScroll, F.w.defilement, 0) end
end

-- Les donnees ont change : un seul rendu, un peu plus tard.
local prevu = false
function F.Signaler()
    if not F.Visible() or prevu then return end
    prevu = true
    local apres = NS.Lecture("C_Timer.After")
    local function Faire() prevu = false if F.Visible() then F.Rendre() end end
    if apres then apres(0.5, Faire) else Faire() end
end
