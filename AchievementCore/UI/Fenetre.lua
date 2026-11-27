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
-- ---------------------------------------------------------------------------
-- Les pages des hauts faits, en cartes : un tableau de bord. Un seul ecart
-- partout (10), cartes basses, anneaux de 36 (la taille des portraits).
-- ---------------------------------------------------------------------------

local C = NS.cartes
local ECART = C.ECART
local H_CAT, H_LIGNE = 48, 38

-- Les cartes de chaque page, gardees d'un rendu a l'autre.
local function Reserves(page)
    if page.r then return page.r end
    local z = page.zone
    local r = {}
    -- Carte de categorie : anneau, nom, detail.
    r.cat = C.Reserve(function()
        local f = C.Panneau(z, true)
        f.anneau = C.Anneau(f)
        f.anneau:SetPoint("LEFT", f, "LEFT", 6, 0)
        f.nom = C.Texte(f, "GameFontHighlight", C.BLANC)
        f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -9)
        f.nom:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        f.detail = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
        f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -4)
        f.detail:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        return f
    end)
    -- Carte de liste : icone (ou portrait), nom et valeur sur la ligne 1,
    -- detail et barre sur la ligne 2.
    r.ligne = C.Reserve(function()
        local f = C.Panneau(z, true)
        f.ic = C.Icone(f, 26)
        f.ic:SetPoint("LEFT", f, "LEFT", 6, 0)
        f.porteur = CreateFrame("Frame", nil, f)
        f.porteur:SetSize(26, 26)
        f.porteur:SetPoint("LEFT", f, "LEFT", 6, 0)
        f.visage = f.porteur:CreateTexture(nil, "ARTWORK")
        f.visage:SetAllPoints()
        f.droite = C.Texte(f, "GameFontNormal", C.OR, "RIGHT")
        f.droite:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
        f.nom = C.Texte(f, "GameFontHighlight", C.BLANC)
        f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -6)
        f.nom:SetPoint("RIGHT", f.droite, "LEFT", -8, 0)
        f.detail = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
        f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -3)
        f.barre = C.Barre(f, 6)
        f.barre:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        f.barre:SetPoint("TOP", f.detail, "TOP", 0, -2)
        return f
    end)
    r.titre = C.Reserve(function() return C.TitreDeColonne(z) end)
    page.r = r
    return r
end

local function CacherCartes(page)
    for _, x in pairs(page.r or {}) do x.Cacher() end
end

-- Une carte de liste. o : icone | perso, nom, couleurNom, detail, droite,
-- couleurDroite, barre (0..1), couleurBarre, auClic, survol.
local function CarteLigne(page, x, y, l, o)
    local f = Reserves(page).ligne.Prendre(page.zone)
    C.Placer(f, page.zone, x, y, l, H_LIGNE)
    if o.perso then
        f.ic:Hide()
        f.porteur:Show()
        persos.Visage(f.visage, o.perso, 26)
    else
        f.porteur:Hide()
        f.ic:Show()
        f.ic.icone:SetTexture(o.icone or ICONE_POINTS)
    end
    f.nom:SetText(o.nom or "")
    local cn = o.couleurNom or C.BLANC
    C.Couleurer(f.nom, cn)
    f.nom.couleurPropre = o.perso and true or nil
    f.nom.nomDePerso = o.perso and true or nil
    f.detail:SetText(o.detail or "")
    f.droite:SetText(o.droite or "")
    C.Couleurer(f.droite, o.couleurDroite or C.OR)
    f.barre:SetShown(o.barre ~= nil)
    f.detail:ClearAllPoints()
    f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -3)
    if o.barre then
        C.PoserBarre(f.barre, o.barre, o.couleurBarre)
        f.barre:SetWidth(math.floor(l / 2) - 8)
        f.detail:SetPoint("RIGHT", f.barre, "LEFT", -10, 0)
    else
        f.detail:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    end
    f:SetScript("OnClick", o.auClic)
    f:EnableMouse(true)
    C.Survol(f, o.survol)
    return y + H_LIGNE + ECART
end

-- La grille des categories d'une portee : quatre cartes par rangee.
local function GrilleDeCategories(page, y, portee)
    local L = page.zone:GetWidth()
    local cols = 4
    local l = math.floor((L - (cols - 1) * ECART) / cols)
    local k = 0
    for _, cat in ipairs(NS.categories) do
        if not (cat.Absente and cat.Absente()) or cat.cle == "quetes" or cat.cle == "objets" then
            local r = calcul.Resultat(cat.cle, portee)
            local f = Reserves(page).cat.Prendre(page.zone)
            local col, rang = k % cols, math.floor(k / cols)
            C.Placer(f, page.zone, col * (l + ECART), y + rang * (H_CAT + ECART), l, H_CAT)
            f.nom:SetText(cat.nom())
            if r and r.total > 0 then
                C.PoserAnneau(f.anneau, r.fait / r.total, C.Etat(r.fait, r.total))
                f.detail:SetText(NS.Nombre(r.fait) .. " / " .. NS.Nombre(r.total))
            else
                C.PoserAnneau(f.anneau, 0, C.VIDE, "")
                f.detail:SetText(not r and ((cat.Absente and cat.Absente()) and T("sans QuestieDB", "no QuestieDB") or T("en préparation", "preparing"))
                    or T("rien à faire", "nothing to do"))
            end
            local cle = cat.cle
            f:SetScript("OnClick", function() if F.w then F.PoserPortee(portee) F.w.page = cle F.Defiler() F.Rendre() end end)
            k = k + 1
        end
    end
    local rangs = math.ceil(k / cols)
    return y + rangs * (H_CAT + ECART)
end

local function TitreColonne(page, texte, x, y, l)
    local t = Reserves(page).titre.Prendre(page.zone)
    return C.PoserTitre(t, texte, x, y, l, page.zone)
end

local function NoteColonne(page, nn, texte, x, y, l)
    page.notes = page.notes or {}
    local n = page.notes[nn]
    if not n then
        n = page.zone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        n:SetJustifyH("LEFT")
        n:SetWordWrap(false)
        page.notes[nn] = n
    end
    n:ClearAllPoints()
    n:SetPoint("TOPLEFT", page.zone, "TOPLEFT", x + 4, -(y + 2))
    n:SetWidth(l - 8)
    n:SetText(texte)
    n:Show()
    return y + 26
end

local function TexteAttente()
    local attente = {}
    for _, cat in ipairs(NS.categories) do
        if cat.Pret and not cat.Pret() and not (cat.Absente and cat.Absente()) then
            table.insert(attente, string.format("%s %d %%", cat.nom(), math.floor(((cat.Progres and cat.Progres()) or 0) * 100)))
        end
    end
    return #attente > 0 and (T("En préparation : ", "Preparing : ") .. table.concat(attente, "   ")) or nil
end

-- Les points en haut a droite : la pastille doree, puis le total.
local function PoserPoints(page, texte)
    page.points:SetText(texte or "")
    page.pastille:SetShown(texte ~= nil and texte ~= "")
end

-- Une page des hauts faits : titre (points ou bouton a droite), explication,
-- zone des cartes.
local function PageHautsFaits(cle, icone, libelle, rendre, section, avant)
    return { cle = cle, icone = icone, libelle = libelle, section = section,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
            page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -260, 0)
            page.points = page.cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            page.points:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, -2)
            page.points:SetJustifyH("RIGHT")
            page.points:SetWordWrap(false)
            page.pastille = C.Pastille(page.cadre, 20)
            page.pastille:SetPoint("RIGHT", page.points, "LEFT", -8, 4)
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 14)
            page.yZone = page.y - 1
            if avant then avant(page, O) end
        end,
        rendre = function(page)
            if NS.base.Preparer then NS.base.Preparer() end
            ToutCacher(page)
            CacherCartes(page)
            PoserPoints(page, nil)
            rendre(page)
            F.NommerEntree(page.t1:GetText())
        end }
end

-- ---------------------------------------------------------------------------
-- Mon compte
-- ---------------------------------------------------------------------------

local function RendreCompte(page)
    page.t1:SetText(T("Mon compte", "My account"))
    page.intro:SetText(T("Tout ce que le compte a fait, et tout ce qui reste, Alliance et Horde.",
        "Everything the account did, and everything left, Alliance and Horde."))
    local pts = calcul.Points("deux")
    PoserPoints(page, TextePoints(pts))
    local L = page.zone:GetWidth()
    local y = GrilleDeCategories(page, 0, "deux")
    local attente = TexteAttente()
    local nn = 0
    if attente then nn = nn + 1 y = NoteColonne(page, nn, attente, 0, y, L) end
    y = y + 4
    -- Deux colonnes : les derniers hauts faits, puis chaque personnage.
    local lG = math.floor((L - ECART) * 0.55)
    local xD = lG + ECART
    local lD = L - xD
    local yG = TitreColonne(page, T("Derniers hauts faits", "Latest feats"), 0, y, lG)
    local derniers = calcul.Derniers(8)
    if #derniers == 0 then
        nn = nn + 1
        yG = NoteColonne(page, nn, T("Les prochains hauts faits obtenus s'afficheront ici.", "The next feats you earn will show here."), 0, yG, lG)
    end
    for _, x in ipairs(derniers) do
        local cat, sous, element = Morceaux(x.cle)
        local p = x.perso
        local c = calcul.Categorie(cat)
        yG = CarteLigne(page, 0, yG, lG, { icone = c and c.icone, nom = x.nom,
            detail = ref.Hex(ref.CouleurDeClasse(p.classe)) .. p.nom .. "|r, " .. Depuis(x.quand),
            droite = "+" .. tostring(x.pts or 0), couleurDroite = C.VERT,
            auClic = function() F.Aller(cat, sous, element, "perso:" .. p.cle) end })
    end
    local yD = TitreColonne(page, T("Par personnage", "By character"), xD, y, lD)
    for _, p in ipairs(persos.Liste()) do
        local pp = "perso:" .. p.cle
        local ptsP, possibleP = calcul.Points(pp)
        local v = possibleP > 0 and ptsP / possibleP or 0
        yD = CarteLigne(page, xD, yD, lD, { perso = p, nom = p.nom, couleurNom = ref.CouleurDeClasse(p.classe),
            detail = DetailPerso(p), droite = NS.Nombre(ptsP), barre = v,
            auClic = function() F.PoserPortee(pp) if F.w then F.w.page = "perso" end F.Defiler() F.Rendre() end })
    end
    page.hauteur = page.yZone + math.max(yG, yD) + 10
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

-- La banniere du personnage, basse : portrait dans son cercle de classe,
-- nom, detail, barre d'XP ; a droite les points et l'anneau du jeu fini.
local H_BANNIERE = 64
local function Banniere(page)
    if page.banniere then return page.banniere end
    local f = C.Panneau(page.zone, false)
    f.fond = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.fond:SetPoint("TOPLEFT", 4, -4)
    f.fond:SetPoint("BOTTOMRIGHT", -4, 4)
    f.fond:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.porteur = CreateFrame("Frame", nil, f)
    f.porteur:SetSize(36, 36)
    f.porteur:SetPoint("LEFT", f, "LEFT", 14, 0)
    f.visage = f.porteur:CreateTexture(nil, "ARTWORK")
    f.visage:SetAllPoints()
    f.nom = C.Texte(f, "GameFontNormal", C.OR)
    f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 62, -10)
    f.nom.couleurPropre = true
    f.detail = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
    f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -4)
    f.barre = C.Barre(f, 8)
    f.barre:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -7)
    f.barre:SetWidth(260)
    f.texteBarre = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
    f.texteBarre:SetPoint("LEFT", f.barre, "RIGHT", 10, 0)
    f.anneau = C.Anneau(f)
    f.anneau:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.points = C.Texte(f, "GameFontNormal", C.OR, "RIGHT")
    f.points:SetPoint("BOTTOMRIGHT", f.anneau, "LEFT", -12, 2)
    f.pastille = C.Pastille(f, 20)
    f.pastille:SetPoint("RIGHT", f.points, "LEFT", -8, 4)
    f.duJeu = C.Texte(f, "GameFontDisableSmall", C.GRIS, "RIGHT")
    f.duJeu:SetPoint("TOPRIGHT", f.anneau, "LEFT", -12, -4)
    page.banniere = f
    return f
end

local function RendrePerso(page)
    local portee = PorteePerso()
    page.t1:SetText(T("Mon personnage", "My character"))
    page.intro:SetText(T("Ce que ce personnage a fait, ce qui l'attend autour de lui, et ce qu'il a presque fini.",
        "What this character did, what awaits around him, and what he has almost finished."))
    local b = Banniere(page)
    local L = page.zone:GetWidth()
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    if not p then
        b:Hide()
        NoteColonne(page, 1, T("Aucun personnage connu pour l'instant.", "No known character yet."), 0, 0, L)
        page.hauteur = page.yZone + 40
        return
    end
    local moi = p.cle == NS.ClePersonnage()
    C.Placer(b, page.zone, 0, 0, L, H_BANNIERE)
    b:Show()
    C.Teinter(b)
    local c = ref.CouleurDeClasse(p.classe)
    -- Un voile leger de la couleur de la classe, qui s'efface vers la droite.
    local okG = _G.CreateColor and pcall(b.fond.SetGradient, b.fond, "HORIZONTAL",
        _G.CreateColor(c[1], c[2], c[3], 0.20), _G.CreateColor(c[1], c[2], c[3], 0))
    if not okG then b.fond:SetColorTexture(c[1], c[2], c[3], 0.08) end
    persos.Visage(b.visage, p, 36)
    b.nom:SetText(p.nom)
    C.Couleurer(b.nom, c)
    b.nom.nomDePerso = true
    local morceaux = {}
    if p.classe and ref.NomDeClasse then table.insert(morceaux, ref.NomDeClasse(p.classe)) end
    if p.race then table.insert(morceaux, ref.NomDeRace(p.race)) end
    if p.niveau then table.insert(morceaux, string.format(T("niveau %d", "level %d"), p.niveau)) end
    if moi then
        local _, zone = IciMaintenant()
        if zone then table.insert(morceaux, NS.NomDeZoneGarde(zone)) end
    end
    b.detail:SetText(table.concat(morceaux, ", "))
    local xp, maxi = moi and tonumber(NS.Sur(NS.Jeu("UnitXP", "player"))), moi and tonumber(NS.Sur(NS.Jeu("UnitXPMax", "player")))
    if xp and maxi and maxi > 0 then
        C.PoserBarre(b.barre, xp / maxi, C.VIOLET)
        b.texteBarre:SetText(string.format(T("%d %% du niveau %d", "%d %% of level %d"), math.floor(xp / maxi * 100), p.niveau or 0))
        b.barre:Show() b.texteBarre:Show()
    else
        b.barre:Hide() b.texteBarre:Hide()
    end
    local v, n = calcul.Global(portee)
    C.PoserAnneau(b.anneau, n > 0 and v or 0, n > 0 and C.Etat(v, 1) or C.VIDE, n > 0 and (math.floor(v * 100) .. "%") or "")
    b.points:SetText(TextePoints((calcul.Points(portee))))
    b.duJeu:SetText(T("du jeu fini", "of the game done"))
    local y = GrilleDeCategories(page, H_BANNIERE + ECART, portee)
    local nn = 0
    local attente = TexteAttente()
    if attente then nn = nn + 1 y = NoteColonne(page, nn, attente, 0, y, L) end
    y = y + 4
    local lG = math.floor((L - ECART) * 0.55)
    local xD = lG + ECART
    local lD = L - xD
    local yG = y
    if moi then
        yG = TitreColonne(page, T("Autour de toi, ce qui reste à faire", "Around you, what is left"), 0, y, lG)
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
            yG = NoteColonne(page, nn, zone and T("Rien qui reste à faire dans cette zone.", "Nothing left to do in this zone.")
                or T("Cette zone n'a pas de liste à suivre.", "This zone has no list to follow."), 0, yG, lG)
        end
        for _, z in ipairs(ici) do
            local cat = calcul.Categorie(z[1])
            local x = z[2]
            local sCle, eCle, cc = x.s.cle, x.e.cle, z[1]
            yG = CarteLigne(page, 0, yG, lG, { icone = cat.icone, nom = cat.nom(),
                detail = string.format(T("%d sur %d", "%d of %d"), x.e.fait, x.e.total),
                droite = string.format(T("encore %d", "%d left"), x.e.total - x.e.fait), barre = x.e.fait / x.e.total,
                auClic = function() F.Aller(cc, sCle, eCle, portee) end })
        end
    end
    local xP, lP = moi and xD or 0, moi and lD or L
    local yD = TitreColonne(page, T("Presque fini", "Almost done"), xP, y, lP)
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
    table.sort(presque, function(a, b2)
        local ra, rb = a.e.total - a.e.fait, b2.e.total - b2.e.fait
        if ra ~= rb then return ra < rb end
        return a.e.fait / a.e.total > b2.e.fait / b2.e.total
    end)
    if #presque == 0 then
        nn = nn + 1
        yD = NoteColonne(page, nn, T("Rien n'est encore à moitié fait.", "Nothing is half done yet."), xP, yD, lP)
    end
    for k = 1, math.min(8, #presque) do
        local x = presque[k]
        local cc, sCle, eCle = x.cat, x.s.cle, x.e.cle
        local cat = calcul.Categorie(cc)
        yD = CarteLigne(page, xP, yD, lP, { icone = x.e.icone or cat.icone, nom = x.e.nom, detail = cat.nom(),
            droite = string.format(T("encore %d", "%d left"), x.e.total - x.e.fait), barre = x.e.fait / x.e.total,
            auClic = function() F.Aller(cc, sCle, eCle, portee) end })
    end
    page.hauteur = page.yZone + math.max(yG, yD) + 10
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
    if minutes < 60 then return string.format("≈ %d min", math.max(1, minutes)) end
    return string.format("≈ %d h %02d", math.floor(minutes / 60), minutes % 60)
end

local function NiveauVise(portee, p)
    local f = FicheDe(portee)
    local n = f and tonumber(f.niveauVise)
    local actuel = p and p.niveau or 1
    if not n or n <= actuel then n = actuel + 1 end
    return math.min(60, n)
end

-- La carte du niveau vise, sous les objectifs : anneau du chemin, temps
-- estime, trois tuiles de chiffres, et le niveau vise entre ses fleches.
local H_NIVEAU = 132
local function AvantObjectifs(page, O)
    local f = C.Panneau(page.zone, false)
    f:SetSize(O.LARGEUR - 10, H_NIVEAU)
    page.carteNiveau = f
    f.anneau = C.Anneau(f)
    f.anneau:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    f.nom = C.Texte(f, "GameFontNormal", C.OR)
    f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 56, -12)
    f.detail = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
    f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -4)
    f.temps = C.Texte(f, "GameFontNormal", C.BLANC, "RIGHT")
    f.temps:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
    f.sousTemps = C.Texte(f, "GameFontHighlightSmall", C.GRIS, "RIGHT")
    f.sousTemps:SetPoint("TOPRIGHT", f.temps, "BOTTOMRIGHT", 0, -4)
    f.tuiles = {}
    local largeur = O.LARGEUR - 10 - 20
    local lt = math.floor((largeur - 2 * ECART) / 3)
    for k = 1, 3 do
        local t = C.Panneau(f, false, true)
        t:SetSize(lt, 34)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + (k - 1) * (lt + ECART), -54)
        t.libelle = C.Texte(t, "GameFontHighlightSmall", C.GRIS)
        t.libelle:SetPoint("LEFT", t, "LEFT", 8, 0)
        t.valeur = C.Texte(t, "GameFontNormal", C.BLANC, "RIGHT")
        t.valeur:SetPoint("RIGHT", t, "RIGHT", -8, 0)
        t.valeur:SetPoint("LEFT", t.libelle, "RIGHT", 8, 0)
        f.tuiles[k] = t
    end
    f.source = C.Texte(f, "GameFontHighlightSmall", C.VERT)
    f.source:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 16)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(330, 26)
    r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 8)
    r.nom = C.Texte(r, "GameFontHighlightSmall", C.BLANC)
    r.nom:SetPoint("LEFT", r, "LEFT", 0, 0)
    page.rNiveau = r
    O.Curseur(r, 2, 60, 1, function()
        local portee = PorteePerso()
        local p = portee and persos.Par(portee:match("^perso:(.+)$"))
        return NiveauVise(portee, p)
    end, function(v)
        local fiche = FicheDe(PorteePerso())
        if fiche then fiche.niveauVise = v end
        F.Rendre()
    end, nil, nil, 5)
    -- Me guider vers ce niveau : sur la ligne du titre, a droite.
    page.bGuiderNiveau = O.Bouton(page.cadre, 90, function()
        local portee = PorteePerso()
        local p = portee and persos.Par(portee:match("^perso:(.+)$"))
        local api = _G.QuestCoreAPI
        if p and api and api.GuiderNiveau then pcall(api.GuiderNiveau, NiveauVise(portee, p)) end
    end)
    page.bGuiderNiveau:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
end

local function RendreObjectifs(page)
    local portee = PorteePerso()
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    page.t1:SetText(T("Objectifs et parcours", "Goals and routes"))
    page.intro:SetText(T("Ce que tu vises, estimé à ton rythme réel ; ce que QuestCore et CraftCore suivent déjà.",
        "What you aim for, estimated at your real pace ; what QuestCore and CraftCore already track."))
    local L = page.zone:GetWidth()
    local f = page.carteNiveau
    local moi = p and p.cle == NS.ClePersonnage()
    local api = _G.QuestCoreAPI
    local maxi = p and (p.niveau or 60) >= 60
    page.bGuiderNiveau:SetText(T("Me guider", "Guide me"))
    page.bGuiderNiveau:SetShown(moi == true and api ~= nil and api.GuiderNiveau ~= nil and not maxi)
    if not p then
        f:Hide()
        NoteColonne(page, 1, T("Aucun personnage connu pour l'instant.", "No known character yet."), 0, 0, L)
        page.hauteur = page.yZone + 40
        return
    end
    -- Deux colonnes d'abord : mes objectifs, ce qui est deja suivi ailleurs.
    local lG = math.floor((L - ECART) * 0.55)
    local xD = lG + ECART
    local lD = L - xD
    local nn = 0
    local yG = TitreColonne(page, T("Mes objectifs", "My goals"), 0, 0, lG)
    local liste = {}
    for k, o in pairs(F.Objectifs(portee)) do
        local cat, sous, element = Morceaux(k)
        local r = calcul.Resultat(cat, portee)
        local e = r and Trouver(r, sous, element)
        table.insert(liste, { cat = cat, sous = sous, element = element, e = e, depuis = type(o) == "table" and o.depuis or 0 })
    end
    table.sort(liste, function(a, b) return (a.depuis or 0) > (b.depuis or 0) end)
    if #liste == 0 then
        nn = nn + 1
        yG = NoteColonne(page, nn, T("Ouvre un élément d'une catégorie, puis Suivre.", "Open an element of a category, then Track."), 0, yG, lG)
    end
    for _, x in ipairs(liste) do
        local cat = calcul.Categorie(x.cat)
        local fini = x.e and x.e.fait >= x.e.total
        yG = CarteLigne(page, 0, yG, lG, { icone = (x.e and x.e.icone) or (cat and cat.icone), nom = x.e and x.e.nom or T("En préparation", "Preparing"),
            detail = cat and cat.nom() or "",
            droite = fini and T("Fini !", "Done !") or (x.e and string.format(T("encore %d", "%d left"), x.e.total - x.e.fait) or ""),
            couleurDroite = fini and C.VERT or C.OR, barre = x.e and x.e.total > 0 and x.e.fait / x.e.total or 0,
            couleurBarre = fini and C.VERT or C.OR, auClic = function() F.Aller(x.cat, x.sous, x.element, portee) end })
    end
    local yD = TitreColonne(page, T("Déjà suivis ailleurs", "Already tracked elsewhere"), xD, 0, lD)
    if not moi then
        nn = nn + 1
        yD = NoteColonne(page, nn, T("Seulement pour le personnage connecté.", "Only for the connected character."), xD, yD, lD)
    else
        local S = _G.CoreSuite
        local n = 0
        local function Ouvrir(cle) return function() if S and S.Ouvrir then S.Ouvrir(cle) end end end
        local function Ajouter(nom, source, fait, total)
            n = n + 1
            local v = total > 0 and fait / total or 0
            yD = CarteLigne(page, xD, yD, lD, { icone = source == "CraftCore" and "Interface\\Icons\\Trade_BlackSmithing" or "Interface\\Icons\\INV_Misc_Book_09",
                nom = nom, detail = source, droite = math.floor(v * 100 + 0.5) .. "%", couleurDroite = C.Etat(fait, total),
                barre = v, couleurBarre = C.Etat(fait, total), auClic = Ouvrir(source) })
        end
        if api and api.Circuit then
            local ok, c = pcall(api.Circuit)
            if ok and type(c) == "table" and (c.total or 0) > 0 then Ajouter(tostring(c.nom or "?"), "QuestCore", c.total - c.reste, c.total) end
        end
        if api and api.Itineraires then
            local ok, l = pcall(api.Itineraires)
            for _, it in ipairs(ok and type(l) == "table" and l or {}) do
                if not it.guide then Ajouter(tostring(it.nom or "?"), "QuestCore", it.faites or 0, it.total or 0) end
            end
        end
        local capi = _G.CraftCoreAPI
        if capi and capi.Suivis then
            local ok, l = pcall(capi.Suivis)
            for _, o in ipairs(ok and type(l) == "table" and l or {}) do
                Ajouter(tostring(o.nom or "?"), "CraftCore", tonumber(o.pct) or 0, 1)
            end
        end
        if n == 0 then
            nn = nn + 1
            yD = NoteColonne(page, nn, T("Rien n'est suivi en ce moment.", "Nothing is tracked right now."), xD, yD, lD)
        end
    end
    -- Puis le niveau vise, en pleine largeur.
    local y = math.max(yG, yD) + 4
    y = TitreColonne(page, T("Mon niveau", "My level"), 0, y, L)
    C.Placer(f, page.zone, 0, y, L, H_NIVEAU)
    f:Show()
    C.Teinter(f)
    for _, t in ipairs(f.tuiles) do C.Teinter(t) end
    page.rNiveau:SetShown(not maxi)
    page.rNiveau.nom:SetText(T("Niveau visé", "Target level"))
    if maxi then
        C.PoserAnneau(f.anneau, 1, C.VIOLET, tostring(p.niveau or 60))
        f.nom:SetText(T("Niveau maximum", "Maximum level"))
        f.detail:SetText(T("Plus rien à viser de ce côté.", "Nothing left to aim for here."))
        f.temps:SetText("") f.sousTemps:SetText("") f.source:SetText("")
        for _, t in ipairs(f.tuiles) do t:Hide() end
    else
        local cible = NiveauVise(portee, p)
        local e = calcul.Estimation(p, cible)
        local deja = moi and tonumber(NS.Sur(NS.Jeu("UnitXP", "player"))) or 0
        local v = (deja + e.xp) > 0 and deja / (deja + e.xp) or 0
        C.PoserAnneau(f.anneau, v, C.VIOLET, tostring(cible))
        f.nom:SetText(string.format(T("Niveau %d", "Level %d"), cible))
        f.detail:SetText(string.format(T("Depuis le niveau %d", "From level %d"), p.niveau or 1))
        f.temps:SetText(e.secondes and Duree(e.secondes) or "?")
        f.sousTemps:SetText(e.secondes and T("estimé à ton rythme", "estimated at your pace") or T("rythme pas encore mesuré", "pace not measured yet"))
        local zones, nq = {}, 0
        local idx = NS.base.Quetes()
        for _, x in ipairs(Chercher("quetes", portee, function(s, el)
            local nz = type(idx) == "table" and idx.niveauZone[el.cle]
            return s.cle == "zones" and nz and math.abs(nz - (p.niveau or 1)) <= 3 and el.fait < el.total
        end)) do
            nq = nq + x.e.total - x.e.fait
            table.insert(zones, x)
        end
        table.sort(zones, function(a, b) return (a.e.total - a.e.fait) > (b.e.total - b.e.fait) end)
        for _, t in ipairs(f.tuiles) do t:Show() end
        f.tuiles[1].libelle:SetText(T("Il manque", "Missing"))
        f.tuiles[1].valeur:SetText(NS.Nombre(e.xp) .. " XP")
        f.tuiles[2].libelle:SetText(T("Quêtes de ton niveau", "Quests of your level"))
        f.tuiles[2].valeur:SetText(tostring(nq))
        f.tuiles[3].libelle:SetText(T("Zone", "Zone"))
        f.tuiles[3].valeur:SetText(zones[1] and string.format("%s (%d)", zones[1].e.nom, zones[1].e.total - zones[1].e.fait) or "-")
        if e.secondes and e.source then
            f.source:SetText(string.format(T("%s a déjà fait ce chemin : son rythme sert de base.", "%s already went this way : his pace is the base."), e.source))
        elseif e.secondes then
            f.source:SetText(T("Ton rythme mesuré sur ce personnage.", "Your pace measured on this character."))
        else
            f.source:SetText(T("Ton rythme se mesure en jouant : quelques minutes suffisent.", "Your pace is measured as you play : a few minutes are enough."))
        end
    end
    page.hauteur = page.yZone + y + H_NIVEAU + 10
end

-- ---------------------------------------------------------------------------
-- Pages des categories, en cartes : une banniere (la categorie ou ce qu'on
-- regarde), les quatre portees en tuiles, puis les sous-categories, les
-- elements ou les criteres en cartes.
-- ---------------------------------------------------------------------------

local function CarteAnneau(page, x, y, l, o)
    local f = Reserves(page).cat.Prendre(page.zone)
    C.Placer(f, page.zone, x, y, l, H_CAT)
    f.nom:SetText(o.nom or "")
    f.detail:SetText(o.detail or "")
    C.PoserAnneau(f.anneau, o.v or 0, o.couleur or C.Etat(o.v or 0, 1), o.texteAnneau)
    f:SetScript("OnClick", o.auClic or function() end)
    C.Survol(f, o.survol)
    return f
end

-- Une grille de cartes a anneau : n colonnes.
local function Grille(page, y, cols, liste, poser)
    local L = page.zone:GetWidth()
    local l = math.floor((L - (cols - 1) * ECART) / cols)
    for k, x in ipairs(liste) do
        local col, rang = (k - 1) % cols, math.floor((k - 1) / cols)
        poser(x, col * (l + ECART), y + rang * (H_CAT + ECART), l)
    end
    return y + math.ceil(#liste / cols) * (H_CAT + ECART)
end

-- Les points gagnes d'une categorie, pour une portee.
local function PointsDe(cleCat, portee)
    local _, _, faits = calcul.Points(portee)
    local n = 0
    for _, x in pairs(faits or {}) do if x.cat == cleCat then n = n + x.pts end end
    return n
end

-- La banniere d'une page de categorie : icone, nom, fait / total, points,
-- anneau.
local function BanniereCat(page)
    if page.banCat then return page.banCat end
    local f = C.Panneau(page.zone, false)
    f.ic = C.Icone(f, 36)
    f.ic:SetPoint("LEFT", f, "LEFT", 14, 0)
    f.nom = C.Texte(f, "GameFontNormal", C.OR)
    f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", 62, -14)
    f.nom:SetPoint("RIGHT", f, "RIGHT", -230, 0)
    f.detail = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
    f.detail:SetPoint("TOPLEFT", f.nom, "BOTTOMLEFT", 0, -6)
    f.detail:SetPoint("RIGHT", f, "RIGHT", -230, 0)
    f.anneau = C.Anneau(f)
    f.anneau:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.points = C.Texte(f, "GameFontNormal", C.OR, "RIGHT")
    f.points:SetPoint("RIGHT", f.anneau, "LEFT", -12, 0)
    f.pastille = C.Pastille(f, 20)
    f.pastille:SetPoint("RIGHT", f.points, "LEFT", -8, 4)
    page.banCat = f
    return f
end

local function IconeDePortee(portee)
    if portee == "Horde" then return "Interface\\Icons\\INV_BannerPVP_01" end
    if portee == "Alliance" then return "Interface\\Icons\\INV_BannerPVP_02" end
    return "Interface\\Icons\\INV_Misc_GroupNeedMore"
end

-- Les quatre portees en tuiles : la choisie a le liseré d'or.
local function TuilesDePortee(page, y, lire)
    local lignes = {}
    local pp = PorteePerso()
    if pp then table.insert(lignes, pp) end
    table.insert(lignes, "Horde")
    table.insert(lignes, "Alliance")
    table.insert(lignes, "deux")
    local L = page.zone:GetWidth()
    local cols = #lignes
    local l = math.floor((L - (cols - 1) * ECART) / cols)
    local choisie = F.Portee()
    for k, portee in ipairs(lignes) do
        local fait, total = lire(portee)
        local o = { nom = calcul.NomDePortee(portee), auClic = function() F.PoserPortee(portee) F.Rendre() end }
        local cle = portee:match("^perso:(.+)$")
        local p = cle and persos.Par(cle)
        if p then o.perso, o.couleurNom = p, ref.CouleurDeClasse(p.classe) else o.icone = IconeDePortee(portee) end
        if total and total > 0 then
            o.barre = fait / total
            o.couleurBarre = C.Etat(fait, total)
            o.droite = NS.Pct(fait, total) .. "%"
            o.couleurDroite = C.Etat(fait, total)
        else
            o.detail = total and T("rien à faire", "nothing to do") or T("en préparation", "preparing")
            o.droite = ""
        end
        CarteLigne(page, (k - 1) * (l + ECART), y, l, o)
        local f = Reserves(page).ligne.liste[Reserves(page).ligne.n]
        f.actif = portee == choisie or nil
        C.Teinter(f)
    end
    return y + H_LIGNE + ECART
end

-- Le detail a droite d'un critere : coche, ou qui l'a fait, ou les deux camps.
local function DroiteCarte(c, portee)
    if portee == "deux" then return DroiteDeCritere(c, portee) end
    if c.fait then return COCHE end
    return ""
end

local function DetailCritere(c, portee)
    local morceaux = {}
    if c.auChoix then table.insert(morceaux, T("Une au choix", "One to choose")) end
    if c.quete then
        local q = NS.base.Quetes()
        q = type(q) == "table" and q.Q[c.quete]
        if q and q.zone and q.zone > 0 then table.insert(morceaux, NS.NomDeZoneGarde(q.zone)) end
    end
    if portee ~= "deux" and c.qui and #c.qui > 0 then table.insert(morceaux, NomsDe(c.qui, 3)) end
    return table.concat(morceaux, "  ")
end

local function RendreCategorie(page, cat)
    local nav = Nav(page)
    local portee = F.Portee()
    if NS.base.Preparer then NS.base.Preparer() end
    ToutCacher(page)
    CacherCartes(page)
    local L = page.zone:GetWidth()
    local res = calcul.Resultat(cat.cle, portee)
    if res and nav.sous and not Trouver(res, nav.sous) then nav.sous, nav.element = nil, nil end
    if res and nav.element and not Trouver(res, nav.sous, nav.element) then nav.element = nil end
    local sous = res and nav.sous and Trouver(res, nav.sous)
    local element = res and nav.element and Trouver(res, nav.sous, nav.element)
    -- Le titre, et ses actions a droite (deux au plus) : Suivre, Me guider.
    local titre = (element and element.nom) or (sous and sous.nom) or cat.nom()
    page.t1:SetText(titre)
    F.NommerEntree(titre)
    local intro = cat.intro()
    if sous then intro = cat.nom() .. (element and ("  >  " .. tostring(sous.nom)) or "") end
    page.intro:SetText(intro)
    local surPerso = portee:match("^perso:") ~= nil
    page.bSuivre:SetShown(element ~= nil and surPerso)
    page.bGuider:Hide()
    page.idsAGuider = nil
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
    page.bGuider:ClearAllPoints()
    if page.bSuivre:IsShown() then page.bGuider:SetPoint("RIGHT", page.bSuivre, "LEFT", -8, 0)
    else page.bGuider:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0) end
    local gauche = (page.bGuider:IsShown() and page.bGuider) or (page.bSuivre:IsShown() and page.bSuivre) or nil
    page.t1:ClearAllPoints()
    page.t1:SetPoint("TOPLEFT", page.cadre, "TOPLEFT", 0, 0)
    if gauche then page.t1:SetPoint("RIGHT", gauche, "LEFT", -12, 0) else page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -10, 0) end
    local y, nn = 0, 0
    if cat.Absente and cat.Absente() then
        NoteColonne(page, 1, T("La base QuestieDB n'est pas installée : cette catégorie n'a pas de liste à suivre.",
            "The QuestieDB database is not installed : this category has no list to follow."), 0, 0, L)
        if page.banCat then page.banCat:Hide() end
        page.hauteur = page.yZone + 40
        return
    end
    if not res then
        local pr = cat.Progres and cat.Progres() or 0
        NoteColonne(page, 1, string.format(T("Préparation de la liste : %d %%", "Preparing the list : %d %%"), math.floor((pr or 0) * 100)), 0, 0, L)
        if page.banCat then page.banCat:Hide() end
        page.hauteur = page.yZone + 40
        return
    end
    -- La banniere : ce qu'on regarde, pour la portee choisie.
    local x = element or sous or res
    local b = BanniereCat(page)
    C.Placer(b, page.zone, 0, 0, L, H_BANNIERE)
    b:Show()
    C.Teinter(b)
    b.ic.icone:SetTexture((element and element.icone) or (sous and sous.icone) or cat.icone)
    b.nom:SetText(titre)
    b.detail:SetText(string.format("%s / %s  %s", NS.Nombre(x.fait or 0), NS.Nombre(x.total or 0), calcul.NomDePortee(portee)))
    C.PoserAnneau(b.anneau, (x.total or 0) > 0 and x.fait / x.total or 0, C.Etat(x.fait or 0, x.total or 0))
    b.points:SetText(TextePoints(PointsDe(cat.cle, portee)))
    y = H_BANNIERE + ECART
    -- Les portees en tuiles (pas pour une liste a plat).
    if not cat.plat then y = TuilesDePortee(page, y, Lecteur(cat, nav)) end
    y = y + 4
    if cat.plat then
        -- Reputations : chaque groupe sous son titre, deux colonnes de cartes,
        -- la barre a la couleur du rang du jeu.
        nav.sous, nav.element = nil, nil
        if #res.sous == 0 then nn = nn + 1 y = NoteColonne(page, nn, T("Rien à montrer pour cette portée.", "Nothing to show for this scope."), 0, y, L) end
        local l = math.floor((L - ECART) / 2)
        for _, s in ipairs(res.sous) do
            y = TitreColonne(page, s.nom, 0, y, L)
            local yy = y
            for k, e in ipairs(s.elements) do
                local col = (k - 1) % 2
                if col == 0 and k > 1 then yy = yy + H_LIGNE + ECART end
                local rang = tonumber(e.rang) or 0
                local nomRang = rang > 0 and ref.NomDeRang and ref.NomDeRang(rang) or ""
                local couleurs = _G.FACTION_BAR_COLORS
                local fc = type(couleurs) == "table" and couleurs[math.max(1, math.min(8, rang))]
                local o = { icone = e.icone, nom = e.nom, detail = nomRang, couleurBarre = fc and { fc.r, fc.g, fc.b } or C.OR, auClic = function() end }
                if e.valeur and e.mini and e.maxi and e.maxi > e.mini and rang < 8 then
                    local dans, taille = math.max(0, e.valeur - e.mini), e.maxi - e.mini
                    o.barre = dans / taille
                    o.droite = NS.Nombre(dans) .. " / " .. NS.Nombre(taille)
                    o.couleurDroite = C.OR
                else
                    o.barre = rang >= 8 and 1 or 0
                    o.droite = rang >= 8 and nomRang or ""
                    o.couleurDroite = C.VERT
                end
                CarteLigne(page, col * (l + ECART), yy, l, o)
            end
            if #s.elements > 0 then y = yy + H_LIGNE + ECART end
        end
        page.hauteur = page.yZone + y + 10
        return
    end
    if not sous then
        -- Les sous-categories, en cartes a anneau.
        y = TitreColonne(page, string.format(T("Pour %s", "For %s"), calcul.NomDePortee(portee)), 0, y, L)
        if #res.sous == 0 then nn = nn + 1 y = NoteColonne(page, nn, T("Rien à faire ici pour cette portée.", "Nothing to do here for this scope."), 0, y, L) end
        y = Grille(page, y, 3, res.sous, function(s, xx, yy, l)
            local cle = s.cle
            CarteAnneau(page, xx, yy, l, { nom = s.nom, detail = NS.Nombre(s.fait) .. " / " .. NS.Nombre(s.total),
                v = s.total > 0 and s.fait / s.total or 0, couleur = C.Etat(s.fait, s.total),
                auClic = function() nav.sous, nav.element, nav.page = cle, nil, 1 F.Defiler() F.Rendre() end })
        end)
        page.hauteur = page.yZone + y + 10
        return
    end
    -- Elements d'une sous-categorie, ou criteres d'un element : filtres
    -- (tout, reste a faire, deja fait) et pages de 100.
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
    y = PoserRangee(page, page.rFiltre, y, T("Afficher", "Show"))
    page.nbPages = math.max(1, math.ceil(#liste / PAR_PAGE))
    if nav.page > page.nbPages then nav.page = page.nbPages end
    if page.nbPages > 1 then y = PoserRangee(page, page.rPage, y, T("Page", "Page")) end
    y = y + 4
    if #liste == 0 then nn = nn + 1 y = NoteColonne(page, nn, T("Aucun élément à montrer.", "Nothing to show."), 0, y, L) end
    local debut = (nav.page - 1) * PAR_PAGE + 1
    local morceau = {}
    for k = debut, math.min(#liste, debut + PAR_PAGE - 1) do table.insert(morceau, liste[k]) end
    if element then
        -- Les criteres : deux colonnes de cartes.
        local l = math.floor((L - ECART) / 2)
        local yy = y
        for k, c in ipairs(morceau) do
            local col = (k - 1) % 2
            if col == 0 and k > 1 then yy = yy + H_LIGNE + ECART end
            local f = CritereFait(c, portee)
            local icone = c.icone
            if c.objet then icone = NS.IconeDObjet(c.objet) end
            local nom = c.nom
            if c.niveau and c.niveau > 0 then nom = "[" .. c.niveau .. "] " .. nom end
            CarteLigne(page, col * (l + ECART), yy, l, { icone = icone or cat.icone, nom = nom,
                couleurNom = f and C.BLANC or C.VIDE, detail = DetailCritere(c, portee),
                droite = DroiteCarte(c, portee), couleurDroite = C.VERT,
                survol = Infobulle(c), auClic = function() end })
            local carte = Reserves(page).ligne.liste[Reserves(page).ligne.n]
            carte.ic.icone:SetDesaturated(not f)
        end
        if #morceau > 0 then y = yy + H_LIGNE + ECART end
    else
        -- Les elements : trois colonnes de cartes a anneau.
        y = Grille(page, y, 3, morceau, function(e, xx, yy, l)
            local cle = e.cle
            local detail = e.detail or (NS.Nombre(e.fait) .. " / " .. NS.Nombre(e.total))
            CarteAnneau(page, xx, yy, l, { nom = e.nom, detail = detail,
                v = e.total > 0 and e.fait / e.total or 0, couleur = C.Etat(e.fait, e.total),
                auClic = function() nav.element, nav.page = cle, 1 F.Defiler() F.Rendre() end })
        end)
    end
    page.hauteur = page.yZone + y + 10
end

local function PageCategorie(cat)
    return { cle = cat.cle, icone = cat.icone, libelle = function() return cat.nom() end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
            -- Deux actions au plus, sur la ligne du titre, a droite, moins
            -- hautes que le titre (le filet reste libre).
            page.bSuivre = O.Bouton(page.cadre, 90, function()
                local nav = Nav(page)
                F.BasculerSuivi(F.Portee(), cat.cle, nav.sous, nav.element)
            end)
            page.bSuivre:SetHeight(18)
            page.bSuivre:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
            page.bGuider = O.Bouton(page.cadre, 90, function()
                local api = _G.QuestCoreAPI
                if api and api.GuiderQuetes and page.idsAGuider then pcall(api.GuiderQuetes, page.idsAGuider) end
            end)
            page.bGuider:SetHeight(18)
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 14)
            page.yZone = page.y - 1
        end,
        rendre = function(page) RendreCategorie(page, cat) end }
end

-- ---------------------------------------------------------------------------
-- Historique : precedent / suivant (fleches de l'en-tete, B a la manette)
-- ---------------------------------------------------------------------------

local histo = { pile = {}, rang = 0, rejeu = false }

local function EntreeActuelle()
    if not F.w then return nil end
    local nav = etat.nav[F.w.page] or {}
    return { page = F.w.page, sous = nav.sous, element = nav.element, portee = etat.portee }
end

local function Meme(a, b)
    return a and b and a.page == b.page and a.sous == b.sous and a.element == b.element and a.portee == b.portee
end

function F.NommerEntree(texte)
    local x = histo.pile[histo.rang]
    if x then x.nom = texte end
end

local function Rejouer(x)
    histo.rejeu = true
    if x.portee then etat.portee = x.portee end
    etat.nav[x.page] = etat.nav[x.page] or { page = 1, filtre = "tout" }
    etat.nav[x.page].sous, etat.nav[x.page].element, etat.nav[x.page].page = x.sous, x.element, 1
    F.w.page = x.page
    F.Defiler()
    F.w.Rendre()
    histo.rejeu = false
end

F.historique = {
    Noter = function()
        if histo.rejeu then return end
        local x = EntreeActuelle()
        if not x or Meme(histo.pile[histo.rang], x) then return end
        for k = #histo.pile, histo.rang + 1, -1 do table.remove(histo.pile, k) end
        table.insert(histo.pile, x)
        while #histo.pile > 30 do table.remove(histo.pile, 1) end
        histo.rang = #histo.pile
    end,
    Reculer = function()
        if histo.rang <= 1 then return end
        histo.rang = histo.rang - 1
        Rejouer(histo.pile[histo.rang])
    end,
    Avancer = function()
        if histo.rang >= #histo.pile then return end
        histo.rang = histo.rang + 1
        Rejouer(histo.pile[histo.rang])
    end,
    PeutReculer = function() return histo.rang > 1 end,
    PeutAvancer = function() return histo.rang < #histo.pile end,
    Libelle = function(sens)
        local x = histo.pile[histo.rang + (sens < 0 and -1 or 1)]
        if not x then return nil end
        if x.nom then return x.nom end
        for _, p in ipairs(F.w and F.w.o.pages or {}) do if p.cle == x.page then return p.libelle() end end
        return nil
    end,
    Vider = function() histo.pile, histo.rang = {}, 0 end,
}

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
        historique = F.historique,
        -- Hors de la page : B revient en arriere (historique), sinon remonte
        -- d'un niveau, sinon ferme ; croix gauche / droite : personnage
        -- precedent / suivant (comme la bande l'indique).
        manette = function(bouton)
            if not F.w then return false end
            if bouton == "PADDLEFT" or bouton == "PADDRIGHT" then
                local liste = persos.Liste()
                if #liste == 0 then return false end
                local actuel = PorteePerso()
                local rang = 1
                for k, p in ipairs(liste) do if "perso:" .. p.cle == actuel then rang = k end end
                rang = ((rang - 1 + (bouton == "PADDRIGHT" and 1 or -1)) % #liste) + 1
                F.PoserPortee("perso:" .. liste[rang].cle)
                F.Rendre()
                return true
            end
            if bouton ~= "PAD2" then return false end
            if F.historique.PeutReculer() then F.historique.Reculer() return true end
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
        -- A la fermeture, l'historique repart de zero : B finit par fermer.
        F.w.cadre:HookScript("OnHide", function() F.historique.Vider() end)
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
