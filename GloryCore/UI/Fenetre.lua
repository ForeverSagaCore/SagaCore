local _, NS = ...

-- La fenetre d'GloryCore, comme le journal des hauts faits du jeu mais
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
    local cat, sous, element = tostring(cle):match("^([^|]+)|([^|]*)|([^|]*)")
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

-- Les points obtenus, et sur combien (le maximum de la portee).
local function TextePoints(n, sur)
    if sur and sur > 0 then return string.format(T("%s / %s points", "%s / %s points"), NS.Nombre(n), NS.Nombre(sur)) end
    return string.format(T("%s points", "%s points"), NS.Nombre(n))
end

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
-- Les pages en cartes : UNE seule carte et UNE seule grille partout.
--   grille : 3 cartes par rangee au plus, toutes de la meme largeur (un
--            tiers) ; une ou deux cartes gardent cette largeur ;
--   carte  : une image ronde de 32 en haut a gauche (portrait dans son
--            cercle de classe, anneau d'avancement, ou icone dans l'anneau
--            dore), alignee sur le haut du nom ; ligne principale (12) et
--            valeur a droite (12) ; sous-ligne (10) ; barre pleine largeur
--            dessous si la carte en a une ;
--   marges : 10 partout, 10 entre les cartes, titres de section de la suite.
--   couleur des barres et anneaux : vert a 100 % ; pour un personnage, la
--            couleur de sa classe ; sinon par paliers (rouge, orange, or,
--            vert tendre).
-- Le personnage vient toujours en premier.
-- ---------------------------------------------------------------------------

local C = NS.cartes
local ECART, PAD, IMAGE, COLS = 10, 10, 32, 3
local X_TEXTE = PAD + IMAGE + 10
local H_CARTE, H_BARRE = 52, 66

-- La couleur d'un avancement pour une portee.
local PALIERS = { { 0.25, { 0.86, 0.36, 0.22 } }, { 0.5, { 0.96, 0.58, 0.16 } }, { 0.75, { 1, 0.82, 0 } }, { 1, { 0.74, 0.86, 0.28 } } }
local function Couleur(v, portee)
    v = tonumber(v) or 0
    if v >= 0.999 then return C.VERT end
    local cle = type(portee) == "string" and portee:match("^perso:(.+)$")
    local p = cle and persos.Par(cle)
    if p then return ref.CouleurDeClasse(p.classe) end
    for _, x in ipairs(PALIERS) do if v < x[1] then return x[2] end end
    return C.VERT
end

-- La carte unique.
local function Fabrique(z)
    local f = C.Panneau(z, true)
    f.porteur = CreateFrame("Frame", nil, f)
    f.porteur:SetSize(IMAGE, IMAGE)
    f.porteur:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    f.visage = f.porteur:CreateTexture(nil, "ARTWORK")
    f.visage:SetAllPoints()
    f.anneau = C.Anneau(f, IMAGE)
    f.anneau:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    -- L'icone ronde dans l'anneau dore, de la taille du cercle d'un portrait.
    f.rond = C.Pastille(f, 30)
    f.rond:SetPoint("CENTER", f, "TOPLEFT", PAD + IMAGE / 2, -(PAD + IMAGE / 2))
    f.droite = C.Texte(f, "GameFontHighlight", C.BLANC, "RIGHT")
    f.droite:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(PAD + 2))
    f.pastille = C.Pastille(f, 20)
    f.pastille:SetPoint("RIGHT", f.droite, "LEFT", -6, 0)
    f.nom = C.Texte(f, "GameFontHighlight", C.BLANC)
    f.nom:SetPoint("TOPLEFT", f, "TOPLEFT", X_TEXTE, -(PAD + 2))
    f.nom:SetPoint("RIGHT", f.droite, "LEFT", -10, 0)
    f.sous = C.Texte(f, "GameFontHighlightSmall", C.GRIS)
    f.sous:SetPoint("TOPLEFT", f, "TOPLEFT", X_TEXTE, -(PAD + 19))
    f.sous:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.barre = C.Barre(f, 6)
    f.barre:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    f.barre:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + IMAGE + 8))
    f.barre:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    return f
end

local function Reserves(page)
    if page.r then return page.r end
    page.r = {
        carte = C.Reserve(function() return Fabrique(page.zone) end),
        titre = C.Reserve(function() return C.TitreDeColonne(page.zone) end),
    }
    return page.r
end

local function CacherCartes(page)
    for _, x in pairs(page.r or {}) do x.Cacher() end
end

-- o : perso | anneau { v, couleur, texte } | icone ; nom, couleurNom, sous,
-- droite, points (pastille), barre, couleurBarre, desature, actif, auClic,
-- survol. Rend la carte.
local function Carte(page, x, y, l, o, h)
    local f = Reserves(page).carte.Prendre(page.zone)
    C.Placer(f, page.zone, x, y, l, h or (o.barre and H_BARRE or H_CARTE))
    f.porteur:Hide() f.anneau:Hide() f.rond:Hide()
    if o.perso then
        f.porteur:Show()
        persos.Visage(f.visage, o.perso, IMAGE)
    elseif o.anneau then
        f.anneau:Show()
        C.PoserAnneau(f.anneau, o.anneau.v, o.anneau.couleur, o.anneau.texte)
    else
        local ic = f.rond.icone
        -- Un portrait pris au journal des donjons se rend avant de reservir.
        local FDJ = _G.ForeverDungeonJournal_NS
        if f.rond.portrait then
            if type(FDJ) == "table" and FDJ.ReleasePortrait then pcall(FDJ.ReleasePortrait, ic) end
            if ic.SetMask then pcall(ic.SetMask, ic, "") end
            f.rond.portrait = nil
        end
        ic:SetTexture(o.icone or ICONE_POINTS)
        ic:SetDesaturated(o.desature == true)
        -- Les icones de quete du jeu (le point d'exclamation) ont leur propre
        -- rond : plus petites dans l'anneau, entieres.
        local taille = f.rond:GetWidth() or IMAGE
        local gossip = type(o.icone) == "string" and o.icone:find("GossipFrame", 1, true) ~= nil
        ic:SetSize(taille * (gossip and 0.5 or 13 / 20), taille * (gossip and 0.5 or 13 / 20))
        if gossip then ic:SetTexCoord(0, 1, 0, 1) else ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        -- Le vrai portrait du boss, rendu par le journal des donjons (une
        -- simple texture : le journal ne s'ouvre pas) ; l'icone sinon.
        if o.portrait and type(FDJ) == "table" and type(FDJ.SetBossPortrait) == "function" then
            local ok, oui = pcall(FDJ.SetBossPortrait, ic, o.portrait.donjon, o.portrait.fiche)
            if ok and oui then
                f.rond.portrait = true
                ic:SetTexCoord(0, 1, 0, 1)
                if ic.SetMask then pcall(ic.SetMask, ic, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
            else
                ic:SetTexture(o.icone or ICONE_POINTS)
            end
        end
        f.rond:Show()
    end
    f.nom:SetText(o.nom or "")
    C.Couleurer(f.nom, o.couleurNom or (o.desature and C.VIDE) or C.BLANC)
    f.nom.nomDePerso = o.perso and true or nil
    f.sous:SetText(o.sous or "")
    f.droite:SetText(o.droite or "")
    f.pastille:SetShown(o.points == true)
    f.barre:SetShown(o.barre ~= nil)
    if o.barre then C.PoserBarre(f.barre, o.barre, o.couleurBarre) end
    f:SetScript("OnClick", o.auClic or function() end)
    C.Survol(f, o.survol)
    f.actif = o.actif or nil
    C.Teinter(f)
    return f
end

-- La grille : liste d'options de cartes, 3 par rangee, largeur d'un tiers.
local function Grille(page, y, liste)
    local L = page.zone:GetWidth()
    local l = math.floor((L - (COLS - 1) * ECART) / COLS)
    local h = H_CARTE
    for _, o in ipairs(liste) do if o.barre then h = H_BARRE end end
    for k, o in ipairs(liste) do
        local col, rang = (k - 1) % COLS, math.floor((k - 1) / COLS)
        Carte(page, col * (l + ECART), y + rang * (h + ECART), l, o, h)
    end
    if #liste == 0 then return y end
    return y + math.ceil(#liste / COLS) * (h + ECART)
end

-- Une carte pleine largeur (bannieres).
local function Banniere(page, y, o)
    Carte(page, 0, y, page.zone:GetWidth(), o, H_BARRE)
    return y + H_BARRE + ECART
end

local function Titre2(page, texte, y)
    local t = Reserves(page).titre.Prendre(page.zone)
    if y > 0 then y = y + 6 end
    return C.PoserTitre(t, texte, 0, y, page.zone:GetWidth(), page.zone)
end

local function Note2(page, nn, texte, y)
    page.notes = page.notes or {}
    local n = page.notes[nn]
    if not n then
        n = page.zone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        n:SetJustifyH("LEFT")
        n:SetWordWrap(false)
        page.notes[nn] = n
    end
    n:ClearAllPoints()
    n:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 4, -(y + 2))
    n:SetWidth(page.zone:GetWidth() - 8)
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

-- Les cartes des categories d'une portee (anneau, nom, fait / total).
local function CartesDeCategories(portee)
    local liste = {}
    for _, cat in ipairs(NS.categories) do
        if not (cat.Absente and cat.Absente()) or cat.cle == "quetes" or cat.cle == "objets" then
            local r = calcul.Resultat(cat.cle, portee)
            local cle = cat.cle
            local o = { nom = cat.nom(), auClic = function() if F.w then F.PoserPortee(portee) F.w.page = cle F.Defiler() F.Rendre() end end }
            if r and r.total > 0 then
                local v = r.fait / r.total
                o.anneau = { v = v, couleur = Couleur(v, portee) }
                o.sous = NS.Nombre(r.fait) .. " / " .. NS.Nombre(r.total)
            else
                o.anneau = { v = 0, couleur = C.VIDE, texte = "" }
                o.sous = not r and ((cat.Absente and cat.Absente()) and T("sans QuestieDB", "no QuestieDB") or T("en préparation", "preparing"))
                    or T("rien à faire", "nothing to do")
            end
            table.insert(liste, o)
        end
    end
    return liste
end

local function PoserPoints(page, texte)
    page.points:SetText(texte or "")
    page.pastille:SetShown(texte ~= nil and texte ~= "")
end

-- Une page des hauts faits : titre, explication (et les points a sa
-- droite, sous le filet), zone des cartes.
local function PageHautsFaits(cle, icone, libelle, rendre, section, avant)
    return { cle = cle, icone = icone, libelle = libelle, section = section,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
            page.t1:SetPoint("RIGHT", page.cadre, "RIGHT", -260, 0)
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.intro:SetWidth(O.LARGEUR - 240)
            page.points = C.Texte(page.cadre, "GameFontNormal", C.OR, "RIGHT")
            page.points.couleurPropre = nil
            page.points:SetPoint("RIGHT", page.cadre, "RIGHT", -10, 0)
            page.points:SetPoint("TOP", page.intro, "TOP", 0, 1)
            page.pastille = C.Pastille(page.cadre, 20)
            page.pastille:SetPoint("RIGHT", page.points, "LEFT", -6, 0)
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
-- Mon compte : chaque personnage, les categories, les derniers hauts faits
-- ---------------------------------------------------------------------------

local function RendreCompte(page)
    page.t1:SetText(T("Mon compte", "My account"))
    page.intro:SetText(T("Tout ce que le compte a fait, et tout ce qui reste, Alliance et Horde.",
        "Everything the account did, and everything left, Alliance and Horde."))
    PoserPoints(page, TextePoints(calcul.Points("deux")))
    local y, nn = 0, 0
    y = Titre2(page, T("Mes personnages", "My characters"), y)
    local liste = {}
    for _, p in ipairs(persos.Liste()) do
        local pp = "perso:" .. p.cle
        local ptsP, possibleP = calcul.Points(pp)
        local v = possibleP > 0 and ptsP / possibleP or 0
        table.insert(liste, { perso = p, nom = p.nom, couleurNom = ref.CouleurDeClasse(p.classe), sous = DetailPerso(p),
            droite = NS.Nombre(ptsP) .. " / " .. NS.Nombre(possibleP), barre = v, couleurBarre = Couleur(v, pp),
            auClic = function() F.PoserPortee(pp) if F.w then F.w.page = "perso" end F.Defiler() F.Rendre() end })
    end
    y = Grille(page, y, liste)
    y = Titre2(page, T("Catégories", "Categories"), y)
    local attente = TexteAttente()
    if attente then nn = nn + 1 y = Note2(page, nn, attente, y) end
    y = Grille(page, y, CartesDeCategories("deux"))
    y = Titre2(page, T("Derniers hauts faits", "Latest feats"), y)
    local derniers = calcul.Derniers(9)
    if #derniers == 0 then
        nn = nn + 1
        y = Note2(page, nn, T("Les prochains hauts faits obtenus s'afficheront ici.", "The next feats you earn will show here."), y)
    end
    liste = {}
    for _, x in ipairs(derniers) do
        local cat, sous, element = Morceaux(x.cle)
        local p = x.perso
        local c = calcul.Categorie(cat)
        table.insert(liste, { icone = x.icone or (c and c.icone), nom = x.nom,
            sous = ref.Hex(ref.CouleurDeClasse(p.classe)) .. p.nom .. "|r, " .. Depuis(x.quand),
            droite = "+" .. tostring(x.pts or 0), auClic = function() F.Aller(cat, sous, element, "perso:" .. p.cle) end })
    end
    y = Grille(page, y, liste)
    page.hauteur = page.yZone + y + 10
end

-- ---------------------------------------------------------------------------
-- Mon personnage
-- ---------------------------------------------------------------------------

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

local function OptionElement(cleCat, x, portee, nom, sous)
    local cat = calcul.Categorie(cleCat)
    local v = x.e.total > 0 and x.e.fait / x.e.total or 0
    local sCle, eCle = x.s.cle, x.e.cle
    return { icone = x.e.icone or (cat and cat.icone), nom = nom, sous = sous,
        droite = string.format(T("encore %d", "%d left"), x.e.total - x.e.fait),
        barre = v, couleurBarre = Couleur(v, portee), auClic = function() F.Aller(cleCat, sCle, eCle, portee) end }
end

local function RendrePerso(page)
    local portee = PorteePerso()
    page.t1:SetText(T("Mon personnage", "My character"))
    page.intro:SetText(T("Ce que ce personnage a fait, ce qui l'attend autour de lui, et ce qu'il a presque fini.",
        "What this character did, what awaits around him, and what he has almost finished."))
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    local y, nn = 0, 0
    if not p then
        Note2(page, 1, T("Aucun personnage connu pour l'instant.", "No known character yet."), 0)
        page.hauteur = page.yZone + 40
        return
    end
    local moi = p.cle == NS.ClePersonnage()
    -- La banniere : le personnage, et l'avancement du jeu a la couleur de sa classe.
    local morceaux = {}
    if p.classe and ref.NomDeClasse then table.insert(morceaux, ref.NomDeClasse(p.classe)) end
    if p.race then table.insert(morceaux, ref.NomDeRace(p.race)) end
    if p.niveau then table.insert(morceaux, string.format(T("niveau %d", "level %d"), p.niveau)) end
    if moi then
        local _, zone = IciMaintenant()
        if zone then table.insert(morceaux, NS.NomDeZoneGarde(zone)) end
    end
    local v, n = calcul.Global(portee)
    if n > 0 then table.insert(morceaux, string.format(T("%d %% du jeu", "%d %% of the game"), math.floor(v * 100))) end
    y = Banniere(page, y, { perso = p, nom = p.nom, couleurNom = ref.CouleurDeClasse(p.classe), sous = table.concat(morceaux, ", "),
        droite = TextePoints(calcul.Points(portee)), points = true, barre = n > 0 and v or 0, couleurBarre = Couleur(v, portee) })
    local attente = TexteAttente()
    if attente then nn = nn + 1 y = Note2(page, nn, attente, y) end
    y = Titre2(page, T("Catégories", "Categories"), y)
    y = Grille(page, y, CartesDeCategories(portee))
    if moi then
        y = Titre2(page, T("Autour de toi, ce qui reste à faire", "Around you, what is left"), y)
        local carte, zone = IciMaintenant()
        local liste = {}
        local function Pas(x) return x.e.fait < x.e.total end
        for _, c in ipairs({ { "quetes", function(s, e) return s.cle == "zones" and zone and e.cle == zone end },
            { "exploration", function(_, e) return carte and e.cle == "z" .. carte end },
            { "rares", function(_, e) return zone and e.cle == zone end } }) do
            for _, x in ipairs(Chercher(c[1], portee, c[2])) do
                if Pas(x) then
                    local cat = calcul.Categorie(c[1])
                    table.insert(liste, OptionElement(c[1], x, portee, cat.nom(), string.format("%s  %d / %d", tostring(x.e.nom), x.e.fait, x.e.total)))
                end
            end
        end
        if #liste == 0 then
            nn = nn + 1
            y = Note2(page, nn, zone and T("Rien qui reste à faire dans cette zone.", "Nothing left to do in this zone.")
                or T("Cette zone n'a pas de liste à suivre.", "This zone has no list to follow."), y)
        end
        y = Grille(page, y, liste)
    end
    y = Titre2(page, T("Presque fini", "Almost done"), y)
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
        y = Note2(page, nn, T("Rien n'est encore à moitié fait.", "Nothing is half done yet."), y)
    end
    local liste = {}
    for k = 1, math.min(9, #presque) do
        local x = presque[k]
        local cat = calcul.Categorie(x.cat)
        table.insert(liste, OptionElement(x.cat, x, portee, x.e.nom, cat.nom()))
    end
    y = Grille(page, y, liste)
    page.hauteur = page.yZone + y + 10
end

-- ---------------------------------------------------------------------------
-- Mes objectifs : mon niveau, mes objectifs, mes parcours
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

-- Le niveau vise entre ses fleches (une rangee de reglage, comme partout)
-- et Me guider sur la ligne du titre.
local function AvantObjectifs(page, O)
    local r = CreateFrame("Frame", nil, page.zone)
    r:SetSize(O.LARGEUR - 10, 26)
    r.nom = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nom:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.nom:SetJustifyH("LEFT")
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
    page.bGuiderNiveau = O.Bouton(page.cadre, 90, function()
        local portee = PorteePerso()
        local p = portee and persos.Par(portee:match("^perso:(.+)$"))
        local api = _G.QuestCoreAPI
        if p and api and api.GuiderNiveau then pcall(api.GuiderNiveau, NiveauVise(portee, p)) end
    end)
    page.bGuiderNiveau:SetHeight(18)
    page.bGuiderNiveau:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 0)
end

local function RendreObjectifs(page)
    local portee = PorteePerso()
    local p = portee and persos.Par(portee:match("^perso:(.+)$"))
    page.t1:SetText(T("Objectifs et parcours", "Goals and routes"))
    page.intro:SetText(T("Ce que tu vises, estimé à ton rythme réel ; ce que QuestCore et CraftCore suivent déjà.",
        "What you aim for, estimated at your real pace ; what QuestCore and CraftCore already track."))
    local moi = p and p.cle == NS.ClePersonnage()
    local api = _G.QuestCoreAPI
    local maxi = p and (p.niveau or 60) >= 60
    page.bGuiderNiveau:SetText(T("Me guider", "Guide me"))
    page.bGuiderNiveau:SetShown(moi == true and api ~= nil and api.GuiderNiveau ~= nil and not maxi)
    page.rNiveau:Hide()
    local y, nn = 0, 0
    if not p then
        Note2(page, 1, T("Aucun personnage connu pour l'instant.", "No known character yet."), 0)
        page.hauteur = page.yZone + 40
        return
    end
    -- 1. Mon niveau.
    y = Titre2(page, T("Mon niveau", "My level"), y)
    if maxi then
        nn = nn + 1
        y = Note2(page, nn, T("Niveau maximum atteint.", "Maximum level reached."), y)
    else
        page.rNiveau:ClearAllPoints()
        page.rNiveau:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
        page.rNiveau.nom:SetText(T("Niveau visé", "Target level"))
        page.rNiveau:Show()
        y = y + 26 + ECART
        local cible = NiveauVise(portee, p)
        local e = calcul.Estimation(p, cible)
        local deja = moi and tonumber(NS.Sur(NS.Jeu("UnitXP", "player"))) or 0
        local v = (deja + e.xp) > 0 and deja / (deja + e.xp) or 0
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
        local source
        if e.secondes and e.source then source = string.format(T("rythme de %s", "%s's pace"), e.source)
        elseif e.secondes then source = T("ton rythme mesuré", "your measured pace")
        else source = T("rythme pas encore mesuré", "pace not measured yet") end
        y = Grille(page, y, {
            { anneau = { v = v, couleur = Couleur(v, portee), texte = tostring(cible) }, nom = string.format(T("Niveau %d", "Level %d"), cible),
              sous = source, droite = e.secondes and Duree(e.secondes) or "?" },
            { icone = "Interface\\Icons\\INV_Misc_Book_07", nom = T("Il manque", "Missing"), sous = string.format(T("du niveau %d au niveau %d", "from level %d to %d"), p.niveau or 1, cible),
              droite = NS.Nombre(e.xp) .. " XP" },
            { icone = "Interface\\Icons\\INV_Misc_Book_08", nom = T("Quêtes de ton niveau", "Quests of your level"),
              sous = zones[1] and string.format("%s (%d)", zones[1].e.nom, zones[1].e.total - zones[1].e.fait) or "-", droite = tostring(nq),
              auClic = zones[1] and function() F.Aller("quetes", "zones", zones[1].e.cle, portee) end or nil },
        })
    end
    -- 2. Mes objectifs.
    y = Titre2(page, T("Mes objectifs", "My goals"), y)
    local objectifs = {}
    for k, o in pairs(F.Objectifs(portee)) do
        local cat, sous, element = Morceaux(k)
        local r = calcul.Resultat(cat, portee)
        local e = r and Trouver(r, sous, element)
        table.insert(objectifs, { cat = cat, sous = sous, element = element, e = e, depuis = type(o) == "table" and o.depuis or 0 })
    end
    table.sort(objectifs, function(a, b) return (a.depuis or 0) > (b.depuis or 0) end)
    if #objectifs == 0 then
        nn = nn + 1
        y = Note2(page, nn, T("Ouvre un élément d'une catégorie, puis Suivre.", "Open an element of a category, then Track."), y)
    end
    local liste = {}
    for _, x in ipairs(objectifs) do
        local cat = calcul.Categorie(x.cat)
        local vO = x.e and x.e.total > 0 and x.e.fait / x.e.total or 0
        table.insert(liste, { icone = (x.e and x.e.icone) or (cat and cat.icone), nom = x.e and x.e.nom or T("En préparation", "Preparing"),
            sous = cat and cat.nom() or "", droite = (x.e and vO >= 1) and T("Fini !", "Done !") or (x.e and string.format(T("encore %d", "%d left"), x.e.total - x.e.fait) or ""),
            barre = vO, couleurBarre = Couleur(vO, portee), auClic = function() F.Aller(x.cat, x.sous, x.element, portee) end })
    end
    y = Grille(page, y, liste)
    -- 3. Mes parcours : ce que QuestCore et CraftCore suivent (personnage connecte).
    y = Titre2(page, T("Mes parcours", "My routes"), y)
    liste = {}
    if moi then
        local S = _G.CoreSuite
        local function Ouvrir(cle) return function() if S and S.Ouvrir then S.Ouvrir(cle) end end end
        local function Ajouter(nom, source, fait, total)
            local vP = total > 0 and fait / total or 0
            table.insert(liste, { icone = source == "CraftCore" and "Interface\\Icons\\Trade_BlackSmithing" or "Interface\\Icons\\INV_Misc_Book_09",
                nom = nom, sous = source, droite = math.floor(vP * 100 + 0.5) .. " %", barre = vP, couleurBarre = Couleur(vP, portee),
                auClic = Ouvrir(source) })
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
            for _, o in ipairs(ok and type(l) == "table" and l or {}) do Ajouter(tostring(o.nom or "?"), "CraftCore", tonumber(o.pct) or 0, 1) end
        end
    end
    if #liste == 0 then
        nn = nn + 1
        y = Note2(page, nn, moi and T("Rien n'est suivi en ce moment.", "Nothing is tracked right now.")
            or T("Seulement pour le personnage connecté.", "Only for the connected character."), y)
    end
    y = Grille(page, y, liste)
    page.hauteur = page.yZone + y + 10
end

-- ---------------------------------------------------------------------------
-- Pages des categories : banniere, portees (le personnage d'abord), puis
-- sous-categories, elements ou criteres, toujours dans la meme grille.
-- ---------------------------------------------------------------------------

local function PointsDe(cleCat, portee)
    local _, _, faits, possibles = calcul.Points(portee)
    local n, sur = 0, 0
    for _, x in pairs(faits or {}) do if x.cat == cleCat then n = n + x.pts end end
    for k, v in pairs(possibles or {}) do if k:match("^([^|]+)") == cleCat then sur = sur + v end end
    return n, sur
end

local function IconeDePortee(portee)
    if portee == "Horde" then return "Interface\\Icons\\INV_BannerPVP_01" end
    if portee == "Alliance" then return "Interface\\Icons\\INV_BannerPVP_02" end
    return "Interface\\Icons\\INV_Misc_GroupNeedMore"
end

local function OptionPortee(portee, lire)
    local fait, total = lire(portee)
    local o = { nom = calcul.NomDePortee(portee), auClic = function() F.PoserPortee(portee) F.Rendre() end }
    local cle = portee:match("^perso:(.+)$")
    local p = cle and persos.Par(cle)
    if p then o.perso, o.couleurNom = p, ref.CouleurDeClasse(p.classe) else o.icone = IconeDePortee(portee) end
    if total and total > 0 then
        o.sous = NS.Nombre(fait) .. " / " .. NS.Nombre(total)
        o.droite = NS.Pct(fait, total) .. " %"
        o.barre = fait / total
        o.couleurBarre = Couleur(fait / total, portee)
    else
        o.sous = total and T("rien à faire", "nothing to do") or T("en préparation", "preparing")
        o.barre = 0
    end
    return o
end

-- Ce que compte une sous-categorie, dit sur sa carte.
local AIDES = {
    quetes = { zones = { "quêtes par zone", "quests by zone" }, suites = { "suites menées au bout", "chains completed" },
        themes = { "quêtes de classe, métier, fête", "class, profession, holiday quests" }, camps = { "quêtes par camp", "quests by side" } },
    donjons = { donjons = { "boss, rares et quêtes", "bosses, rares and quests" }, raids = { "boss, rares et quêtes", "bosses, rares and quests" } },
    metiers = { principaux = { "paliers et recettes", "ranks and recipes" }, secondaires = { "paliers et recettes", "ranks and recipes" } },
    races = { classes = { "paliers de niveau 10 à 60", "level steps 10 to 60" }, races = { "paliers de niveau 10 à 60", "level steps 10 to 60" },
        combinaisons = { "race et classe au niveau maximum", "race and class at max level" } },
    jcj = { jcj = { "rangs et champs de bataille", "ranks and battlegrounds" } },
    heritage = { arbres = { "paliers d'héritage", "legacy steps" } },
    exploration = { "zones et lieux découverts", "zones and places discovered" },
    rares = { "rares tués", "rares killed" },
    objets = { "objets obtenus", "items obtained" },
}
local function AideDe(cleCat, cleSous)
    local a = AIDES[cleCat]
    if type(a) == "table" and type(a[1]) == "string" then return T(a[1], a[2]) end
    a = type(a) == "table" and a[cleSous]
    return a and T(a[1], a[2]) or nil
end

local function DetailCritere(c, portee)
    local morceaux = {}
    if c.niveau and c.niveau > 0 then table.insert(morceaux, string.format(T("Niveau %d", "Level %d"), c.niveau)) end
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
    local res = calcul.Resultat(cat.cle, portee)
    if res and nav.sous and not Trouver(res, nav.sous) then nav.sous, nav.element = nil, nil end
    if res and nav.element and not Trouver(res, nav.sous, nav.element) then nav.element = nil end
    local sous = res and nav.sous and Trouver(res, nav.sous)
    local element = res and nav.element and Trouver(res, nav.sous, nav.element)
    local titre = (element and element.nom) or (sous and sous.nom) or cat.nom()
    page.t1:SetText(titre)
    F.NommerEntree(titre)
    local intro = cat.intro()
    if sous then intro = cat.nom() .. (element and ("  >  " .. tostring(sous.nom)) or "") end
    page.intro:SetText(intro)
    -- Les actions du titre (deux au plus) : Suivre, Me guider.
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
        Note2(page, 1, T("La base QuestieDB n'est pas installée : cette catégorie n'a pas de liste à suivre.",
            "The QuestieDB database is not installed : this category has no list to follow."), 0)
        page.hauteur = page.yZone + 40
        return
    end
    if not res then
        local pr = cat.Progres and cat.Progres() or 0
        Note2(page, 1, string.format(T("Préparation de la liste : %d %%", "Preparing the list : %d %%"), math.floor((pr or 0) * 100)), 0)
        page.hauteur = page.yZone + 40
        return
    end
    -- La banniere : ce qu'on regarde, pour la portee choisie, ses points.
    local x = element or sous or res
    local v = (x.total or 0) > 0 and x.fait / x.total or 0
    y = Banniere(page, y, { icone = (element and element.icone) or (sous and sous.icone) or cat.icone, nom = titre,
        sous = string.format(T("%s critères remplis sur %s, pour %s", "%s criteria met out of %s, for %s"), NS.Nombre(x.fait or 0), NS.Nombre(x.total or 0), calcul.NomDePortee(portee)),
        droite = TextePoints(PointsDe(cat.cle, portee)), points = true, barre = v, couleurBarre = Couleur(v, portee) })
    -- Les camps (tous, le camp du personnage, l'autre), puis le personnage :
    -- sa carte ouvre le detail de ce qu'on regarde, pour lui.
    local carteDuPerso
    if not cat.plat then
        local lire = Lecteur(cat, nav)
        local pp = PorteePerso()
        local pPerso = pp and persos.Par(pp:match("^perso:(.+)$"))
        local monCamp = (pPerso and pPerso.faction == "Horde") and "Horde" or "Alliance"
        local autre = monCamp == "Horde" and "Alliance" or "Horde"
        y = Titre2(page, T("Tous mes personnages", "All my characters"), y)
        y = Grille(page, y, { OptionPortee("deux", lire), OptionPortee(monCamp, lire), OptionPortee(autre, lire) })
        if pp then carteDuPerso = OptionPortee(pp, lire) end
    end
    if cat.plat then
        -- Reputations : chaque groupe sous son titre ; la barre a la couleur du rang du jeu.
        nav.sous, nav.element = nil, nil
        if #res.sous == 0 then nn = nn + 1 y = Note2(page, nn, T("Rien à montrer pour cette portée.", "Nothing to show for this scope."), y) end
        for _, s in ipairs(res.sous) do
            y = Titre2(page, s.nom, y)
            local liste = {}
            for _, e in ipairs(s.elements) do
                local rang = tonumber(e.rang) or 0
                local nomRang = rang > 0 and ref.NomDeRang and ref.NomDeRang(rang) or ""
                local couleurs = _G.FACTION_BAR_COLORS
                local fc = type(couleurs) == "table" and couleurs[math.max(1, math.min(8, rang))]
                local o = { icone = cat.icone, nom = e.nom, sous = nomRang, couleurBarre = fc and { fc.r, fc.g, fc.b } or C.OR }
                if e.valeur and e.mini and e.maxi and e.maxi > e.mini and rang < 8 then
                    local dans, taille = math.max(0, e.valeur - e.mini), e.maxi - e.mini
                    o.barre = dans / taille
                    o.droite = NS.Nombre(dans) .. " / " .. NS.Nombre(taille)
                else
                    o.barre = rang >= 8 and 1 or 0
                end
                table.insert(liste, o)
            end
            y = Grille(page, y, liste)
        end
        page.hauteur = page.yZone + y + 10
        return
    end
    -- Le detail : sous la carte du personnage (ou le nom du camp choisi).
    local function EnTete()
        if carteDuPerso then
            local pp = PorteePerso()
            local estMoi = pp == "perso:" .. tostring(NS.ClePersonnage())
            y = Titre2(page, estMoi and T("Mon personnage", "My character") or T("Personnage choisi", "Chosen character"), y)
            y = Grille(page, y, { carteDuPerso })
        end
        if not portee:match("^perso:") then y = Titre2(page, string.format(T("Pour %s", "For %s"), calcul.NomDePortee(portee)), y) end
    end
    if not sous then
        EnTete()
        if #res.sous == 0 then nn = nn + 1 y = Note2(page, nn, T("Rien à faire ici pour cette portée.", "Nothing to do here for this scope."), y) end
        local liste = {}
        for _, s in ipairs(res.sous) do
            local cle = s.cle
            local vS = s.total > 0 and s.fait / s.total or 0
            local aide = AideDe(cat.cle, s.cle)
            table.insert(liste, { anneau = { v = vS, couleur = Couleur(vS, portee) }, nom = s.nom,
                sous = NS.Nombre(s.fait) .. " / " .. NS.Nombre(s.total) .. (aide and ("   " .. aide) or ""),
                auClic = function() nav.sous, nav.element, nav.page = cle, nil, 1 F.Defiler() F.Rendre() end })
        end
        y = Grille(page, y, liste)
        page.hauteur = page.yZone + y + 10
        return
    end
    -- Elements ou criteres : filtre (tout, reste a faire, deja fait) et pages de 100.
    local brut = {}
    if element then
        for _, c in ipairs(element.Detail and element.Detail() or {}) do
            local f = CritereFait(c, portee)
            if nav.filtre == "tout" or (nav.filtre == "fait" and f) or (nav.filtre == "reste" and not f) then table.insert(brut, c) end
        end
    else
        for _, e in ipairs(sous.elements) do
            local f = e.fait >= e.total
            if nav.filtre == "tout" or (nav.filtre == "fait" and f) or (nav.filtre == "reste" and not f) then table.insert(brut, e) end
        end
    end
    Controles(page)
    y = PoserRangee(page, page.rFiltre, y, T("Afficher", "Show"))
    page.nbPages = math.max(1, math.ceil(#brut / PAR_PAGE))
    if nav.page > page.nbPages then nav.page = page.nbPages end
    if page.nbPages > 1 then y = PoserRangee(page, page.rPage, y, T("Page", "Page")) end
    EnTete()
    if #brut == 0 then nn = nn + 1 y = Note2(page, nn, T("Aucun élément à montrer.", "Nothing to show."), y) end
    local debut = (nav.page - 1) * PAR_PAGE + 1
    local liste = {}
    for k = debut, math.min(#brut, debut + PAR_PAGE - 1) do
        local it = brut[k]
        if element then
            local f = CritereFait(it, portee)
            local icone = it.icone
            if it.objet then icone = NS.IconeDObjet(it.objet) end
            table.insert(liste, { icone = icone or cat.icone, portrait = it.portrait, desature = not f, nom = it.nom, sous = DetailCritere(it, portee),
                droite = (portee == "deux") and DroiteDeCritere(it, portee) or (f and COCHE or ""), survol = Infobulle(it) })
        else
            local cle = it.cle
            local vE = it.total > 0 and it.fait / it.total or 0
            table.insert(liste, { anneau = { v = vE, couleur = Couleur(vE, portee) }, nom = it.nom,
                sous = it.detail or (NS.Nombre(it.fait) .. " / " .. NS.Nombre(it.total)),
                auClic = function() nav.element, nav.page = cle, 1 F.Defiler() F.Rendre() end })
        end
    end
    y = Grille(page, y, liste)
    page.hauteur = page.yZone + y + 10
end

local function PageCategorie(cat)
    return { cle = cat.cle, icone = cat.icone, libelle = function() return cat.nom() end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.t1:SetWordWrap(false)
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
-- La page de la suite complete (GloryCore installe seul)
-- ---------------------------------------------------------------------------

-- Les Parametres : l'annonce des hauts faits, la danse.
local function PageReglages()
    return { cle = "reglages", section = "GloryCore",
        construire = function(page, O)
            page.t1 = O.Section()
            page.rAnnonce = O.Rangee()
            O.Case(page.rAnnonce, function(v) NS.base.Reglages().annoncerHautsFaits = v and true or false end)
                :SetPoint("RIGHT", page.rAnnonce, "RIGHT", -10, 0)
            page.dAnnonce = O.Detail(18)
            page.rDanse = O.Rangee()
            O.Case(page.rDanse, function(v) NS.base.Reglages().danserHautFait = v and true or false end)
                :SetPoint("RIGHT", page.rDanse, "RIGHT", -10, 0)
            page.dDanse = O.Detail(18)
        end,
        rendre = function(page)
            local r = NS.base.Reglages()
            page.t1:SetText(T("Hauts faits obtenus", "Feats earned"))
            page.rAnnonce.nom:SetText(T("Annoncer chaque haut fait", "Announce each feat"))
            page.dAnnonce:SetText(T("Le bandeau du milieu de l'écran et le son du passage de niveau, avec les points gagnés.", "The banner in the middle of the screen and the level up sound, with the points earned."))
            page.rDanse.nom:SetText(T("Faire danser mon personnage", "Make my character dance"))
            page.dDanse:SetText(T("Une petite danse à chaque haut fait, une fois arrêté, jamais en combat.", "A little dance at each feat, once standing still, never in combat."))
            for _, x in ipairs({ { page.rAnnonce, r.annoncerHautsFaits ~= false }, { page.rDanse, r.danserHautFait ~= false } }) do
                for _, enfant in ipairs({ x[1]:GetChildren() }) do
                    if enfant.SetChecked then enfant:SetChecked(x[2]) end
                end
            end
        end }
end

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
            page.intro:SetText(T("GloryCore fait partie de Forever SagaCore, une suite d'add-ons pour WoW Forever : fabrications et métiers (CraftCore), quêtes et trajets (QuestCore), carte et services (MapCore), héritage (LegacyCore). Installés ensemble, ils partagent la même fenêtre, les mêmes réglages et la même manette, et GloryCore lit leurs relevés.",
                "GloryCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls, and GloryCore reads their records."))
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
        PageHautsFaits("objectifs", "Interface\\Icons\\INV_Misc_Map_01", function() return T("Mes objectifs", "My goals") end, RendreObjectifs, nil, AvantObjectifs),
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
    table.insert(pages, PageReglages())
    if S.Seul and S.Seul() then table.insert(pages, PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "GloryCoreFenetre", cle = "GloryCore", icone = "Interface\\Icons\\INV_Misc_Ribbon_01",
        titre = function() return T("GloryCore (bêta)", "GloryCore (beta)") end,
        pages = pages,
        -- La bande des personnages choisit le personnage montre.
        persoChoisi = function()
            local p = PorteePerso()
            return p and p:match("^perso:(.+)$") or nil
        end,
        choisirPerso = function(cle) F.PoserPortee("perso:" .. cle) end,
        historique = F.historique,
        -- Hors de la page : B remonte d'un niveau dans une categorie, sinon
        -- ferme, comme dans toute la suite (l'historique, ce sont les fleches
        -- de l'en-tete) ; croix gauche / droite : personnage precedent /
        -- suivant (comme la bande l'indique).
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
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("GloryCore") return true end
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
