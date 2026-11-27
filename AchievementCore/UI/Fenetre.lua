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
    l.cadreVisage:SetColorTexture(0, 0, 0, 0) -- rond : l'anneau de classe remplace le cadre carre
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
    -- Un element ouvert, pour un personnage : le suivre comme objectif, et
    -- pour le personnage connecte, se faire guider vers ses quetes.
    local surPerso = portee:match("^perso:") ~= nil
    page.bSuivre:SetShown(element ~= nil and surPerso)
    page.bGuider:Hide()
    if element and surPerso then
        page.bSuivre:SetText(F.Suivi(portee, cat.cle, nav.sous, nav.element) and T("Ne plus suivre", "Stop tracking") or T("Suivre", "Track"))
        local api = _G.QuestCoreAPI
        if portee == "perso:" .. tostring(NS.ClePersonnage()) and api and api.GuiderQuetes then
            local ids = {}
            for _, c in ipairs(element.Detail and element.Detail() or {}) do
                if c.quete and not c.fait then table.insert(ids, c.quete) end
            end
            if #ids > 0 then
                page.idsAGuider = ids
                page.bGuider:SetText(T("Me guider", "Guide me"))
                page.bGuider:Show()
            end
        end
    end
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
    if not cat.plat then
        nt = nt + 1
        y = Titre(page, nt, y, T("Avancement", "Progress"))
        i, y = Resume(page, i, y, Lecteur(cat, nav))
    end
    if cat.plat then
        -- Une liste a plat (reputations) : chaque element sous le titre de
        -- son groupe, sa barre d'avancement dans le rang actuel, sans
        -- niveau a ouvrir.
        page.bRetour:Hide()
        nav.sous, nav.element = nil, nil
        if #res.sous == 0 then nn = nn + 1 y = Note(page, nn, y, T("Rien à montrer pour cette portée.", "Nothing to show for this scope.")) end
        for _, s in ipairs(res.sous) do
            nt = nt + 1
            y = Titre(page, nt, y, s.nom)
            for _, e in ipairs(s.elements) do
                i = i + 1
                local o = { icone = e.icone, texte = e.nom, droite = "", auClic = function() end }
                local rang = tonumber(e.rang) or 0
                local nomRang = rang > 0 and ref.NomDeRang and ref.NomDeRang(rang) or ""
                if e.valeur and e.mini and e.maxi and e.maxi > e.mini then
                    local dans, taille = e.valeur - e.mini, e.maxi - e.mini
                    if rang >= 8 then
                        o.fait, o.total, o.texteBarre = 1, 1, nomRang
                    else
                        o.fait, o.total = math.max(0, dans), taille
                        o.texteBarre = string.format("%s  %s / %s", nomRang, NS.Nombre(math.max(0, dans)), NS.Nombre(taille))
                    end
                    o.droite = rang >= 8 and "" or string.format("%d %%", math.floor(math.max(0, dans) / taille * 100))
                else
                    o.fait, o.total, o.texteBarre = rang >= 8 and 1 or 0, 1, nomRang
                end
                o.survol = function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(e.nom, 1, 0.82, 0)
                    if nomRang ~= "" then GameTooltip:AddLine(nomRang, 1, 1, 1) end
                    if e.valeur and e.mini and e.maxi and rang < 8 then
                        GameTooltip:AddLine(string.format(T("%s sur %s vers %s", "%s of %s to %s"), NS.Nombre(math.max(0, e.valeur - e.mini)),
                            NS.Nombre(e.maxi - e.mini), ref.NomDeRang(rang + 1)), 0.9, 0.9, 0.9)
                    end
                    GameTooltip:Show()
                end
                y = Poser(page, i, y, o)
            end
        end
        page.hauteur = page.yZone + y + 10
        return
    end
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
            page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -330, 0)
            page.bRetour = O.Bouton(page.cadre, 90, function()
                local nav = Nav(page)
                if nav.element then nav.element = nil else nav.sous = nil end
                nav.page = 1
                F.Defiler()
            end)
            page.bRetour:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
            page.bSuivre = O.Bouton(page.cadre, 90, function()
                local nav = Nav(page)
                F.BasculerSuivi(F.Portee(), cat.cle, nav.sous, nav.element)
            end)
            page.bSuivre:SetPoint("RIGHT", page.bRetour, "LEFT", -8, 0)
            page.bGuider = O.Bouton(page.cadre, 90, function()
                local api = _G.QuestCoreAPI
                if api and api.GuiderQuetes and page.idsAGuider then pcall(api.GuiderQuetes, page.idsAGuider) end
            end)
            page.bGuider:SetPoint("RIGHT", page.bSuivre, "LEFT", -8, 0)
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
-- Aller a un element, depuis n'importe quelle page
-- ---------------------------------------------------------------------------

function F.Aller(cleCat, sous, element, portee)
    if not F.w then return end
    if portee then F.PoserPortee(portee) end
    etat.nav[cleCat] = { page = 1, filtre = "tout", sous = sous, element = element }
    F.w.page = cleCat
    F.Defiler()
    F.Rendre()
end

local function Morceaux(cle)
    local cat, sous, element = tostring(cle):match("^([^|]+)|([^|]*)|(.*)$")
    return cat, tonumber(sous) or sous, tonumber(element) or element
end

local ICONE_POINTS = "Interface\\Icons\\INV_Misc_Ribbon_01"

-- Il y a combien de temps, en mots.
local function Depuis(quand)
    local maintenant = NS.Appeler(time) or quand
    local jours = math.floor((maintenant - quand) / 86400)
    if jours <= 0 then return T("aujourd'hui", "today") end
    if jours == 1 then return T("hier", "yesterday") end
    return string.format(T("il y a %d jours", "%d days ago"), jours)
end

local function TextePoints(n) return string.format(T("%s points", "%s points"), NS.Nombre(n)) end

-- La ligne d'un personnage : portrait, nom a sa couleur, niveau et race.
local function DetailPerso(p)
    local morceaux = {}
    if p.niveau then table.insert(morceaux, string.format(T("Niveau %d", "Level %d"), p.niveau)) end
    if p.race then table.insert(morceaux, ref.NomDeRace(p.race)) end
    if p.classe and ref.NomDeClasse then table.insert(morceaux, ref.NomDeClasse(p.classe)) end
    return table.concat(morceaux, "  ")
end

-- Les categories pour une portee, chacune ouvre sa page.
local function LignesDeCategories(page, i, y, portee)
    for _, cat in ipairs(NS.categories) do
        if not (cat.Absente and cat.Absente()) or cat.cle == "quetes" or cat.cle == "objets" then
            local r = calcul.Resultat(cat.cle, portee)
            local cle = cat.cle
            local o = { icone = cat.icone, texte = cat.nom(),
                auClic = function() if F.w then F.PoserPortee(portee) F.w.page = cle F.Defiler() F.Rendre() end end }
            if r then o.fait, o.total = r.fait, r.total
            else o.fait, o.total, o.texteBarre, o.droite = 0, 1, (cat.Absente and cat.Absente()) and T("sans QuestieDB", "no QuestieDB") or T("en préparation", "preparing"), "" end
            if r and r.total == 0 then o.texteBarre, o.droite = T("rien à faire", "nothing to do"), "" end
            i = i + 1
            y = Poser(page, i, y, o)
        end
    end
    return i, y
end

local function Attente(page, nn, y)
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
    return nn, y
end

-- Une page des hauts faits : titre, explication, zone (et ses boutons).
local function PageHautsFaits(cle, icone, libelle, rendre, section, avant)
    return { cle = cle, icone = icone, libelle = libelle, section = section,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
            page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -260, 0)
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            if avant then avant(page, O) end
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 12)
            page.yZone = page.y - 1
        end,
        rendre = function(page)
            if NS.base.Preparer then NS.base.Preparer() end
            ToutCacher(page)
            rendre(page)
        end }
end

-- ---------------------------------------------------------------------------
-- Mon compte
-- ---------------------------------------------------------------------------

local function RendreCompte(page)
    page.t1:SetText(T("Mon compte", "My account"))
    page.intro:SetText(T("Tous tes personnages, Horde et Alliance : chaque haut fait compte une fois pour le compte.",
        "All your characters, Horde and Alliance : each feat counts once for the account."))
    local i, y, nt, nn = 0, 0, 0, 0
    nt = nt + 1
    y = Titre(page, nt, y, T("Points", "Points"))
    local pts, possible = calcul.Points("deux")
    i = i + 1
    y = Poser(page, i, y, { icone = ICONE_POINTS, texte = T("Le compte", "The account"), police = "GameFontNormal",
        fait = pts, total = math.max(1, possible), texteBarre = string.format("%s / %s", NS.Nombre(pts), NS.Nombre(possible)),
        droite = TextePoints(pts) })
    for _, p in ipairs(persos.Liste()) do
        local pp = "perso:" .. p.cle
        local ptsP, possibleP = calcul.Points(pp)
        i = i + 1
        y = Poser(page, i, y, { retrait = 4, visage = p, texte = p.nom, couleur = ref.CouleurDeClasse(p.classe),
            detail = DetailPerso(p), fait = ptsP, total = math.max(1, possibleP),
            texteBarre = string.format("%s / %s", NS.Nombre(ptsP), NS.Nombre(possibleP)), droite = TextePoints(ptsP),
            auClic = function() F.PoserPortee(pp) if F.w then F.w.page = "perso" end F.Defiler() F.Rendre() end })
    end
    nn, y = Attente(page, nn, y)
    nt = nt + 1
    y = Titre(page, nt, y, T("Catégories", "Categories"))
    i, y = LignesDeCategories(page, i, y, "deux")
    nt = nt + 1
    y = Titre(page, nt, y, T("Derniers hauts faits", "Latest feats"))
    local derniers = calcul.Derniers(8)
    if #derniers == 0 then
        nn = nn + 1
        y = Note(page, nn, y, T("Les prochains hauts faits obtenus s'afficheront ici.", "The next feats you earn will show here."))
    end
    for _, x in ipairs(derniers) do
        local cat, sous, element = Morceaux(x.cle)
        local p = x.perso
        i = i + 1
        y = Poser(page, i, y, { icone = ICONE_POINTS, texte = x.nom,
            detail = ref.Hex(ref.CouleurDeClasse(p.classe)) .. p.nom .. "|r  " .. Depuis(x.quand),
            droite = "+" .. tostring(x.pts or 0), couleurDroite = { 1, 0.82, 0 },
            auClic = function() F.Aller(cat, sous, element, "perso:" .. p.cle) end })
    end
    page.hauteur = page.yZone + y + 10
end

-- ---------------------------------------------------------------------------
-- Mon personnage
-- ---------------------------------------------------------------------------

-- La zone ou l'on est : sa carte de zone (pas un sous-niveau) et sa zone de la base.
local function IciMaintenant()
    local carte = tonumber(NS.Jeu("C_Map.GetBestMapForUnit", "player"))
    local garde = 0
    while carte and garde < 6 do
        local info = NS.Jeu("C_Map.GetMapInfo", carte)
        if type(info) ~= "table" then break end
        if info.mapType == 3 or info.mapType == 4 then return carte, NS.base.ZoneDeCarte(carte) end
        carte = info.parentMapID
        garde = garde + 1
    end
    return nil, nil
end

local function Chercher(cleCat, portee, test)
    local r = calcul.Resultat(cleCat, portee)
    local trouves = {}
    for _, s in ipairs(r and r.sous or {}) do
        for _, e in ipairs(s.elements or {}) do
            if test(s, e) then table.insert(trouves, { s = s, e = e }) end
        end
    end
    return trouves
end

local function LigneElement(page, i, y, cleCat, x, portee, detail)
    local cat = calcul.Categorie(cleCat)
    local sCle, eCle = x.s.cle, x.e.cle
    i = i + 1
    y = Poser(page, i, y, { icone = x.e.icone or (cat and cat.icone), coords = x.e.coords, texte = x.e.nom,
        detail = detail or (cat and cat.nom()), fait = x.e.fait, total = x.e.total,
        auClic = function() F.Aller(cleCat, sCle, eCle, portee) end })
    return i, y
end

local function RendrePerso(page)
    local portee = PorteePerso()
    page.t1:SetText(T("Mon personnage", "My character"))
    page.intro:SetText(T("Ce que ce personnage a fait, ce qui l'attend autour de lui, et ce qu'il a presque fini.",
        "What this character did, what awaits around him, and what he has almost finished."))
    local i, y, nt, nn = 0, 0, 0, 0
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    if not p then
        nn = nn + 1
        y = Note(page, nn, y, T("Aucun personnage connu pour l'instant.", "No known character yet."))
        page.hauteur = page.yZone + y + 10
        return
    end
    local v, n = calcul.Global(portee)
    local pts = calcul.Points(portee)
    local pct = math.floor(v * 100)
    i = i + 1
    y = Poser(page, i, y, { retrait = 4, visage = p, texte = p.nom, police = "GameFontNormal", couleur = ref.CouleurDeClasse(p.classe),
        detail = DetailPerso(p), fait = n > 0 and pct or 0, total = 100,
        texteBarre = n > 0 and string.format(T("%d %% du jeu", "%d %% of the game"), pct) or T("en préparation", "preparing"),
        droite = TextePoints(pts), couleurDroite = { 1, 0.82, 0 } })
    nn, y = Attente(page, nn, y)
    nt = nt + 1
    y = Titre(page, nt, y, T("Catégories", "Categories"))
    i, y = LignesDeCategories(page, i, y, portee)
    -- Autour de toi : seulement pour le personnage connecte.
    if p.cle == NS.ClePersonnage() then
        nt = nt + 1
        y = Titre(page, nt, y, T("Autour de toi", "Around you"))
        local carte, zone = IciMaintenant()
        local ici = {}
        local function Pas(x) return x.e.fait < x.e.total end
        for _, x in ipairs(Chercher("quetes", portee, function(s, e) return s.cle == "zones" and zone and e.cle == zone end)) do
            if Pas(x) then table.insert(ici, { "quetes", x }) end
        end
        for _, x in ipairs(Chercher("exploration", portee, function(_, e) return carte and e.cle == "z" .. carte end)) do
            if Pas(x) then table.insert(ici, { "exploration", x }) end
        end
        for _, x in ipairs(Chercher("rares", portee, function(_, e) return zone and e.cle == zone end)) do
            if Pas(x) then table.insert(ici, { "rares", x }) end
        end
        if #ici == 0 then
            nn = nn + 1
            y = Note(page, nn, y, zone and T("Rien qui reste à faire dans cette zone.", "Nothing left to do in this zone.")
                or T("Cette zone n'a pas de liste à suivre.", "This zone has no list to follow."))
        end
        for _, z in ipairs(ici) do
            local cat = calcul.Categorie(z[1])
            local reste = z[2].e.total - z[2].e.fait
            i, y = LigneElement(page, i, y, z[1], z[2], portee, string.format(T("%s : encore %d", "%s : %d left"), cat.nom(), reste))
        end
    end
    -- Presque fini : ce qui demande le moins pour un haut fait.
    nt = nt + 1
    y = Titre(page, nt, y, T("Presque fini", "Almost done"))
    local presque = {}
    for _, cat in ipairs(NS.categories) do
        if cat.cle ~= "objets" then
            for _, x in ipairs(Chercher(cat.cle, portee, function(s, e)
                return calcul.Valeur(cat.cle, s.cle) > 0 and e.total > 0 and e.fait < e.total and e.fait / e.total >= 0.5
            end)) do
                x.cat = cat.cle
                table.insert(presque, x)
            end
        end
    end
    table.sort(presque, function(a, b)
        local ra, rb = a.e.total - a.e.fait, b.e.total - b.e.fait
        if ra ~= rb then return ra < rb end
        return a.e.fait / a.e.total > b.e.fait / b.e.total
    end)
    if #presque == 0 then
        nn = nn + 1
        y = Note(page, nn, y, T("Rien n'est encore à moitié fait.", "Nothing is half done yet."))
    end
    for k = 1, math.min(8, #presque) do
        local x = presque[k]
        local cat = calcul.Categorie(x.cat)
        i, y = LigneElement(page, i, y, x.cat, x, portee, string.format(T("%s : encore %d", "%s : %d left"), cat.nom(), x.e.total - x.e.fait))
    end
    page.hauteur = page.yZone + y + 10
end

-- ---------------------------------------------------------------------------
-- Objectifs et parcours
-- ---------------------------------------------------------------------------

local function FicheDe(portee)
    local cle = type(portee) == "string" and portee:match("^perso:(.+)$")
    return cle and NS.base.Fiche(cle) or nil, cle
end

function F.Objectifs(portee)
    local f = FicheDe(portee)
    return f and NS.base.Table(f, "objectifs") or {}
end

local function CleObjectif(cat, sous, element) return cat .. "|" .. tostring(sous) .. "|" .. tostring(element) end

function F.Suivi(portee, cat, sous, element)
    return F.Objectifs(portee)[CleObjectif(cat, sous, element)] ~= nil
end

function F.BasculerSuivi(portee, cat, sous, element)
    local o = F.Objectifs(portee)
    local k = CleObjectif(cat, sous, element)
    if o[k] then o[k] = nil else o[k] = { depuis = NS.Appeler(time) or 0 } end
end

local function Duree(secondes)
    local minutes = math.floor(secondes / 60 + 0.5)
    if minutes < 60 then return string.format(T("≈ %d min", "≈ %d min"), math.max(1, minutes)) end
    return string.format(T("≈ %d h %02d", "≈ %d h %02d"), math.floor(minutes / 60), minutes % 60)
end

local function NiveauVise(portee, p)
    local f = FicheDe(portee)
    local n = f and tonumber(f.niveauVise)
    local actuel = p and p.niveau or 1
    if not n or n <= actuel then n = actuel + 1 end
    return math.min(60, n)
end

local function RendreObjectifs(page)
    local portee = PorteePerso()
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    page.t1:SetText(T("Objectifs et parcours", "Goals and routes"))
    page.intro:SetText(T("Ce que tu vises, estimé à ton rythme réel ; ce que QuestCore et CraftCore suivent déjà.",
        "What you aim for, estimated at your real pace ; what QuestCore and CraftCore already track."))
    local moi = p and p.cle == NS.ClePersonnage()
    local api = _G.QuestCoreAPI
    page.bGuiderNiveau:SetShown(moi == true and api ~= nil and api.GuiderNiveau ~= nil and (p.niveau or 60) < 60)
    page.bGuiderNiveau:SetText(T("Me guider", "Guide me"))
    page.rNiveau:SetShown(p ~= nil and (p.niveau or 60) < 60)
    page.rNiveau.nom:SetText(T("Niveau visé", "Target level"))
    local i, y, nt, nn = 0, 0, 0, 0
    if not p then
        nn = nn + 1
        y = Note(page, nn, y, T("Aucun personnage connu pour l'instant.", "No known character yet."))
        page.hauteur = page.yZone + y + 10
        return
    end
    -- Le niveau vise : l'XP qui manque, le temps a ton rythme, les quetes
    -- de ton niveau.
    nt = nt + 1
    y = Titre(page, nt, y, string.format(T("Niveau %d", "Level %d"), NiveauVise(portee, p)))
    if (p.niveau or 60) >= 60 then
        nn = nn + 1
        y = Note(page, nn, y, T("Niveau maximum atteint.", "Maximum level reached."))
    else
        local e = calcul.Estimation(p, NiveauVise(portee, p))
        i = i + 1
        y = Poser(page, i, y, { icone = "Interface\\Icons\\INV_Misc_Book_07", texte = string.format(T("Il manque %s XP", "%s XP missing"), NS.Nombre(e.xp)),
            droite = "" })
        local source
        if e.secondes and e.source then source = string.format(T("D'après le rythme de %s à ces niveaux", "From %s's pace at these levels"), e.source)
        elseif e.secondes then source = T("D'après ton rythme mesuré", "From your measured pace")
        else source = T("Ton rythme se mesure en jouant : quelques minutes suffisent", "Your pace is measured as you play : a few minutes are enough") end
        i = i + 1
        y = Poser(page, i, y, { icone = "Interface\\Icons\\INV_Misc_PocketWatch_01", texte = e.secondes and string.format(T("À ton rythme : %s", "At your pace : %s"), Duree(e.secondes)) or T("Temps estimé : pas encore mesuré", "Estimated time : not measured yet"),
            detail = source, droite = "" })
        -- Les quetes qui restent dans les zones de ton niveau.
        local zones, n = {}, 0
        local idx = NS.base.Quetes()
        for _, x in ipairs(Chercher("quetes", portee, function(s, el)
            local nz = type(idx) == "table" and idx.niveauZone[el.cle]
            return s.cle == "zones" and nz and math.abs(nz - (p.niveau or 1)) <= 3 and el.fait < el.total
        end)) do
            n = n + x.e.total - x.e.fait
            table.insert(zones, x)
        end
        table.sort(zones, function(a, b) return (a.e.total - a.e.fait) > (b.e.total - b.e.fait) end)
        local noms = {}
        for k = 1, math.min(3, #zones) do table.insert(noms, string.format("%s (%d)", zones[k].e.nom, zones[k].e.total - zones[k].e.fait)) end
        i = i + 1
        y = Poser(page, i, y, { icone = "Interface\\GossipFrame\\AvailableQuestIcon", texte = string.format(T("%d quêtes de ton niveau à faire", "%d quests of your level to do"), n),
            detail = #noms > 0 and table.concat(noms, "  ") or nil, droite = "",
            auClic = zones[1] and function() F.Aller("quetes", "zones", zones[1].e.cle, portee) end or nil })
    end
    -- Mes objectifs : ce que tu as choisi de suivre.
    nt = nt + 1
    y = Titre(page, nt, y, T("Mes objectifs", "My goals"))
    local liste = {}
    for k, o in pairs(F.Objectifs(portee)) do
        local cat, sous, element = Morceaux(k)
        local r = calcul.Resultat(cat, portee)
        local e = r and Trouver(r, sous, element)
        table.insert(liste, { k = k, cat = cat, sous = sous, element = element, e = e, depuis = type(o) == "table" and o.depuis or 0 })
    end
    table.sort(liste, function(a, b) return (a.depuis or 0) > (b.depuis or 0) end)
    if #liste == 0 then
        nn = nn + 1
        y = Note(page, nn, y, T("Aucun objectif : ouvre un élément d'une catégorie, puis Suivre.", "No goal : open an element of a category, then Track."))
    end
    for _, x in ipairs(liste) do
        local cat = calcul.Categorie(x.cat)
        local fini = x.e and x.e.fait >= x.e.total
        i = i + 1
        y = Poser(page, i, y, { icone = (x.e and x.e.icone) or (cat and cat.icone), texte = x.e and x.e.nom or T("En préparation", "Preparing"),
            detail = fini and T("Fini !", "Done !") or (cat and string.format(T("%s : encore %d", "%s : %d left"), cat.nom(), x.e and (x.e.total - x.e.fait) or 0)),
            fait = x.e and x.e.fait or 0, total = x.e and math.max(1, x.e.total) or 1,
            auClic = function() F.Aller(x.cat, x.sous, x.element, portee) end })
    end
    -- Deja suivis ailleurs : seulement pour le personnage connecte (QuestCore
    -- et CraftCore suivent le personnage connecte).
    if moi then
        nt = nt + 1
        y = Titre(page, nt, y, T("Déjà suivis ailleurs", "Already tracked elsewhere"))
        local S = _G.CoreSuite
        local ailleurs = 0
        local function Ouvrir(cle) return function() if S and S.Ouvrir then S.Ouvrir(cle) end end end
        if api and api.Circuit then
            local ok, c = pcall(api.Circuit)
            if ok and type(c) == "table" and (c.total or 0) > 0 then
                ailleurs = ailleurs + 1
                i = i + 1
                y = Poser(page, i, y, { icone = "Interface\\Icons\\INV_Misc_Map_01", texte = tostring(c.nom or "?"),
                    detail = T("QuestCore : guidage en cours", "QuestCore : guidance running"), fait = c.total - c.reste, total = c.total,
                    auClic = Ouvrir("QuestCore") })
            end
        end
        if api and api.Itineraires then
            local ok, l = pcall(api.Itineraires)
            for _, it in ipairs(ok and type(l) == "table" and l or {}) do
                if not it.guide then
                    ailleurs = ailleurs + 1
                    i = i + 1
                    y = Poser(page, i, y, { icone = "Interface\\Icons\\INV_Misc_Book_09", texte = tostring(it.nom or "?"),
                        detail = T("QuestCore : itinéraire", "QuestCore : route"), fait = it.faites or 0, total = math.max(1, it.total or 1),
                        auClic = Ouvrir("QuestCore") })
                end
            end
        end
        local capi = _G.CraftCoreAPI
        if capi and capi.Suivis then
            local ok, l = pcall(capi.Suivis)
            for _, o in ipairs(ok and type(l) == "table" and l or {}) do
                ailleurs = ailleurs + 1
                local pctO = math.floor((tonumber(o.pct) or 0) * 100 + 0.5)
                i = i + 1
                y = Poser(page, i, y, { icone = "Interface\\Icons\\Trade_BlackSmithing", texte = tostring(o.nom or "?"),
                    detail = "CraftCore" .. (o.detail and (" : " .. tostring(o.detail)) or ""), fait = pctO, total = 100,
                    texteBarre = pctO .. " %", auClic = Ouvrir("CraftCore") })
            end
        end
        if ailleurs == 0 then
            nn = nn + 1
            y = Note(page, nn, y, T("Ni QuestCore ni CraftCore ne suivent rien en ce moment.", "Neither QuestCore nor CraftCore tracks anything right now."))
        end
    end
    page.hauteur = page.yZone + y + 10
end

local function AvantObjectifs(page, O)
    page.bGuiderNiveau = O.Bouton(page.cadre, 90, function()
        local portee = PorteePerso()
        local p = portee and persos.Par(portee:match("^perso:(.+)$"))
        local api = _G.QuestCoreAPI
        if p and api and api.GuiderNiveau then pcall(api.GuiderNiveau, NiveauVise(portee, p)) end
    end)
    page.bGuiderNiveau:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
    page.rNiveau = O.Rangee()
    O.Curseur(page.rNiveau, 2, 60, 1, function()
        local portee = PorteePerso()
        local p = portee and persos.Par(portee:match("^perso:(.+)$"))
        return NiveauVise(portee, p)
    end, function(v)
        local f = FicheDe(PorteePerso())
        if f then f.niveauVise = v end
        F.Rendre()
    end, nil, nil, 5)
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
    local hautsFaits = function() return T("Hauts faits", "Feats") end
    local pages = {
        PageHautsFaits("compte", "Interface\\Icons\\INV_Misc_Ribbon_01", function() return T("Mon compte", "My account") end, RendreCompte, hautsFaits),
        PageHautsFaits("perso", "Interface\\Icons\\INV_Misc_GroupNeedMore", function() return T("Mon personnage", "My character") end, RendrePerso),
        PageHautsFaits("objectifs", "Interface\\Icons\\INV_Misc_Map_01", function() return T("Objectifs et parcours", "Goals and routes") end, RendreObjectifs, nil, AvantObjectifs),
    }
    local premiere = true
    for _, cat in ipairs(NS.categories) do
        -- L'heritage seulement quand LegacyCore a des releves.
        if not (cat.cle == "heritage" and cat.Absente and cat.Absente()) then
            local pc = PageCategorie(cat)
            if premiere then pc.section = function() return T("Catégories", "Categories") end premiere = false end
            table.insert(pages, pc)
        end
    end
    if S.Seul and S.Seul() then table.insert(pages, PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "AchievementCoreFenetre", cle = "AchievementCore", icone = "Interface\\Icons\\INV_Misc_Ribbon_01",
        titre = function() return "GloryCore" end,
        pages = pages,
        -- La bande des personnages choisit le personnage montre.
        persoChoisi = function()
            local p = PorteePerso()
            return p and p:match("^perso:(.+)$") or nil
        end,
        choisirPerso = function(cle) F.PoserPortee("perso:" .. cle) end,
        -- B hors de la page : remonte d'un niveau avant de fermer.
        manette = function(bouton)
            if bouton ~= "PAD2" or not F.w then return false end
            local nav = etat.nav[F.w.page]
            if not nav or not nav.sous then return false end
            if nav.element then nav.element = nil else nav.sous = nil end
            nav.page = 1
            F.Defiler()
            F.Rendre()
            return true
        end,
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
