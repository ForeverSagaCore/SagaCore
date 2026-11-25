local _, NS = ...

-- Carte de MapCore : la carte de la zone telle que le jeu la dessine, toute
-- la zone revelee a la demande, la position du personnage, vos reperes (icones
-- de cible du jeu, avec une note et une zone entouree), et les quetes de
-- QuestCore quand il est installe.
-- Molette : zoom sous le curseur. Glisser : deplacer. Clic droit : un repere.

NS.pageCarte = {}
local page = NS.pageCarte
local L = NS.L

local TUILE = 256
local ZOOM_MAX = 6
local HAUT_TITRE = 30
-- Sous la carte : la rangee de filtres (et des services), puis l'aide.
local BAS_CARTE = 50
local ALPHA_COURSE = 0.05
local COULEURS_TRAJET = { { 1, 0.82, 0 }, { 0.45, 0.8, 1 }, { 0.5, 0.95, 0.4 }, { 0.82, 0.55, 1 } }

local vue, menu, calque
local carteChoisie             -- uiMapID affiche, nil = la zone du personnage
local zoom, decX, decY = 1, 0, 0
local derniereCarte

local function Lecture(chemin) return NS.Lecture(chemin) end

local function Reglages()
    local g = NS.base.ReglagesGeneraux()
    g.cartePage = g.cartePage or {}
    local r = g.cartePage
    if r.reveler == nil then r.reveler = true end
    if r.autres == nil then r.autres = true end
    if r.fondu == nil then r.fondu = false end
    if r.quetes == nil then r.quetes = true end
    if r.recolte == nil then r.recolte = true end
    return r
end

page.Reglages = Reglages

local function NomDeCarte(id)
    local info = NS.Appeler(Lecture("C_Map.GetMapInfo"), id)
    return type(info) == "table" and info.name or ("#" .. tostring(id))
end

local function CarteDuPerso()
    return NS.Appeler(Lecture("C_Map.GetBestMapForUnit"), "player")
end

local function PositionJoueur(idCarte)
    local pos = NS.Appeler(Lecture("C_Map.GetPlayerMapPosition"), idCarte, "player")
    local x, y
    if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return x, y
end

local function Bouton(parent, texte, largeurMin)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    b:SetText(texte or "")
    b:SetWidth(math.max(largeurMin or 40, (b.GetTextWidth and b:GetTextWidth() or 40) + 24))
    return b
end

-- ---------------------------------------------------------------------------
-- Calque du trajet : au-dessus de la carte, mais pas dans la fenetre, pour
-- rester net quand la fenetre s'efface en course.
-- ---------------------------------------------------------------------------

local function Calque()
    if calque then return calque end
    calque = CreateFrame("Frame", nil, UIParent)
    calque:SetAllPoints(vue.clip)
    if calque.SetClipsChildren then calque:SetClipsChildren(true) end
    calque:EnableMouse(false)
    calque.fleche = calque:CreateTexture(nil, "OVERLAY")
    calque.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    calque.fleche:SetSize(30, 30)
    calque.fleche:Hide()
    calque:Hide()
    return calque
end

-- Position d'un point de la carte (0 a 1) dans le calque.
local function VersCalque(u, v)
    local k = (vue.clip:GetEffectiveScale() or 1) / (calque:GetEffectiveScale() or 1)
    return (decX + u * vue.largeur * vue.echelle) * k, (decY + v * vue.hauteur * vue.echelle) * k
end

-- Un point du chemin : petit rond du jeu.
local function Point(rang)
    calque.points = calque.points or {}
    local t = calque.points[rang]
    if not t then
        t = calque:CreateTexture(nil, "ARTWORK")
        if not (t.SetAtlas and pcall(t.SetAtlas, t, "WhiteCircle-RaidBlips") and t:GetAtlas()) then
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        calque.points[rang] = t
    end
    return t
end

local ESPACE_POINTS = 11

-- Pointilles d'un point a un autre, a pas reguliers a l'ecran.
local function Pointilles(rang, ax, ay, bx, by, c, taille, alpha)
    local dx, dy = bx - ax, by - ay
    local longueur = math.sqrt(dx * dx + dy * dy)
    local n = math.max(1, math.floor(longueur / ESPACE_POINTS))
    for i = 1, n do
        if rang >= 600 then return rang end
        local f = (i - 0.5) / n
        rang = rang + 1
        local t = Point(rang)
        t:ClearAllPoints()
        t:SetSize(taille, taille)
        t:SetPoint("CENTER", calque, "TOPLEFT", ax + dx * f, -(ay + dy * f))
        t:SetVertexColor(c[1], c[2], c[3], alpha)
        t:Show()
    end
    return rang
end

-- ---------------------------------------------------------------------------
-- Tournee de recolte : des lieux de recolte choisis sur la carte (clic droit
-- sur un lieu ; Maj + clic droit : tous ceux de la meme matiere), parcourus
-- du plus proche au suivant, puis guides par la fleche de la suite (objectif
-- "tournee", UI/Guidage.lua). Une tournee tourne en boucle : une fois tous
-- les lieux visites, on recommence (les noeuds repoussent). Chaque
-- personnage a la sienne.
-- ---------------------------------------------------------------------------

local tourneeVide = { points = {} }
local function Tournee()
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    local d = MapCoreDB
    if not cle or type(d) ~= "table" then return tourneeVide end
    d.persos = type(d.persos) == "table" and d.persos or {}
    local p = type(d.persos[cle]) == "table" and d.persos[cle] or {}
    d.persos[cle] = p
    -- Une fois : l'ancienne tournee, commune au compte, va au premier
    -- personnage qui se connecte.
    local r = Reglages()
    if not d.tourneeParPerso then
        d.tourneeParPerso = true
        if type(r.tournee) == "table" and type(p.tournee) ~= "table" then
            p.tournee = { carte = r.tournee.carte, points = r.tournee.points }
        end
    end
    r.tournee = nil
    p.tournee = type(p.tournee) == "table" and p.tournee or { points = {} }
    p.tournee.points = type(p.tournee.points) == "table" and p.tournee.points or {}
    p.tournee.faits = nil
    return p.tournee
end
page.Tournee = Tournee

-- Les lieux deja visites ce tour-ci (memoire de l'objectif guide).
local aucunFait = {}
local function Faits()
    local S = NS.suite or _G.CoreSuite
    local a = S and S.ObjectifActif and S.ObjectifActif()
    if a and a.proprietaire == "MapCore" and a.type == "tournee" and type(a.etat) == "table" then
        a.etat.faits = type(a.etat.faits) == "table" and a.etat.faits or {}
        return a.etat.faits
    end
    return aucunFait
end
page.FaitsTournee = Faits

local function CleLieu(l) return tostring(l.objet) .. ":" .. tostring(l.x) .. ":" .. tostring(l.y) end
page.CleLieu = CleLieu

local function RangDansTournee(l)
    local t = Tournee()
    if t.carte ~= (vue and vue.idCarte) then return nil end
    local cle = CleLieu(l)
    for rang, p in ipairs(t.points) do if CleLieu(p) == cle then return rang end end
    return nil
end

-- Remet la tournee dans l'ordre : depuis le personnage, le plus proche, puis
-- le plus proche du precedent.
local function Ordonner()
    local t = Tournee()
    if #t.points < 2 then return end
    local x, y = PositionJoueur(t.carte)
    local ici = { x = x or t.points[1].x, y = y or t.points[1].y }
    local reste, ordre = {}, {}
    for _, p in ipairs(t.points) do table.insert(reste, p) end
    while #reste > 0 do
        local meilleur, rang
        for k, p in ipairs(reste) do
            local d = (p.x - ici.x) ^ 2 + (p.y - ici.y) ^ 2
            if not meilleur or d < meilleur then meilleur, rang = d, k end
        end
        ici = table.remove(reste, rang)
        table.insert(ordre, ici)
    end
    t.points = ordre
end

function page.ChoisirLieu(l, toute)
    local t = Tournee()
    -- Une autre carte : on repart d'une tournee neuve.
    if t.carte ~= vue.idCarte then t.carte, t.points = vue.idCarte, {} end
    local deja = RangDansTournee(l)
    if toute then
        local cc = _G.CraftCoreAPI
        local ok, lieux = pcall(cc.Lieux, vue.idCarte)
        for _, x in ipairs(ok and lieux or {}) do
            if x.objet == l.objet then
                local r = RangDansTournee(x)
                if deja and r then table.remove(t.points, r)
                elseif not deja and not r then table.insert(t.points, { objet = x.objet, x = x.x, y = x.y }) end
            end
        end
    elseif deja then
        table.remove(t.points, deja)
    else
        table.insert(t.points, { objet = l.objet, x = l.x, y = l.y })
    end
    -- La tournee change : un nouveau tour commence.
    local faits = Faits()
    for k in pairs(faits) do faits[k] = nil end
    Ordonner()
    local S = NS.suite or _G.CoreSuite
    if S and S.Invalider then S.Invalider() end
    page.Rendre()
end

function page.EffacerTournee()
    local S = NS.suite or _G.CoreSuite
    if S and S.EstActif and S.EstActif("MapCore", "tournee", {}) then S.Arreter("joueur") end
    local t = Tournee()
    t.carte, t.points = nil, {}
    page.Rendre()
end

local COULEUR_TOURNEE = { 0.5, 0.95, 0.4 }

local function DessinerTrajet()
    if not calque or not vue or not vue.largeur then return end
    calque:SetFrameStrata((_G.MapCoreFenetre and _G.MapCoreFenetre:GetFrameStrata()) or "MEDIUM")
    calque:SetFrameLevel(math.min((vue.clip:GetFrameLevel() or 1) + 40, 9000))
    for _, t in ipairs(calque.points or {}) do t:Hide() end
    local t = Tournee()
    if t.carte ~= vue.idCarte or #t.points == 0 then
        -- Guidage vers un seul point (PNJ, service...) : des pointilles du
        -- personnage jusqu'a lui, pour le retrouver meme quand il ne
        -- clignote plus.
        local S = NS.suite or _G.CoreSuite
        local a = S and S.ObjectifActif and S.ObjectifActif()
        local c = a and a.proprietaire == "MapCore" and a.type == "service" and a.params or nil
        if c and c.carte == vue.idCarte and c.x and c.y then
            local jx, jy = PositionJoueur(vue.idCarte)
            if jx then
                local ax, ay = VersCalque(jx, jy)
                local bx, by = VersCalque(c.x, c.y)
                Pointilles(0, ax, ay, bx, by, COULEUR_TOURNEE, 7, 0.95)
            end
        end
        return
    end
    local chemin = {}
    local jx, jy = PositionJoueur(vue.idCarte)
    if jx then table.insert(chemin, { jx, jy }) end
    for _, p in ipairs(t.points) do
        if not Faits()[CleLieu(p)] then table.insert(chemin, { p.x, p.y }) end
    end
    local rang = 0
    for i = 2, #chemin do
        local ax, ay = VersCalque(chemin[i - 1][1], chemin[i - 1][2])
        local bx, by = VersCalque(chemin[i][1], chemin[i][2])
        rang = Pointilles(rang, ax, ay, bx, by, COULEUR_TOURNEE, i == 2 and 7 or 5, 0.95)
    end
end

-- Le guidage de la tournee : un objectif de la suite (UI/Guidage.lua).
function page.EnGuidage()
    local S = NS.suite or _G.CoreSuite
    return S and S.EstActif and S.EstActif("MapCore", "tournee", {}) or false
end
function page.BasculerTournee()
    local S = NS.suite or _G.CoreSuite
    if not (S and S.BasculerObjectif) then return end
    if NS.Trace then NS.Trace("guidage tournee") end
    S.BasculerObjectif("MapCore", "tournee", {})
    pcall(page.Rendre)
end

function page.PlacerJoueur()
    if not vue or not vue:IsVisible() or not vue.idCarte or not vue.echelle or not calque then return end
    local x, y = PositionJoueur(vue.idCarte)
    if not x then calque.fleche:Hide() return end
    local px, py = VersCalque(x, y)
    calque.fleche:ClearAllPoints()
    calque.fleche:SetPoint("CENTER", calque, "TOPLEFT", px, -py)
    local cap = NS.Appeler(Lecture("GetPlayerFacing"))
    if cap and calque.fleche.SetRotation then calque.fleche:SetRotation(cap) end
    calque.fleche:Show()
end

-- ---------------------------------------------------------------------------
-- Zoom et deplacement
-- ---------------------------------------------------------------------------

-- Cadre a la proportion exacte de la carte, centre dans la place ; puis la
-- toile : echelle d'ajustement x zoom, decalage borne.
-- ---------------------------------------------------------------------------
-- Services : maitres de classe et de metier, reparation, boites aux lettres...
-- Leur place vient de QuestieDB (Data/Services.lua). Seuls ceux de sa faction
-- (ou neutres) ; pour les maitres de classe, ceux de sa classe.
-- ---------------------------------------------------------------------------

local SERVICES = {
    { cle = "classe", libelle = "SVC_CLASS", fichiers = { "Interface\\Minimap\\Tracking\\Class" }, defaut = true },
    { cle = "metier", libelle = "SVC_PROF", fichiers = { "Interface\\Minimap\\Tracking\\Profession" }, defaut = true },
    { cle = "maitre", libelle = "SVC_OTHER", fichiers = { "Interface\\Minimap\\Tracking\\StableMaster" } },
    { cle = "reparation", libelle = "SVC_REPAIR", fichiers = { "Interface\\Minimap\\Tracking\\Repair" }, defaut = true },
    { cle = "courrier", libelle = "SVC_MAIL", fichiers = { "Interface\\Minimap\\Tracking\\Mailbox" }, defaut = true },
    { cle = "auberge", libelle = "SVC_INN", fichiers = { "Interface\\Minimap\\Tracking\\Innkeeper" } },
    { cle = "banque", libelle = "SVC_BANK", fichiers = { "Interface\\Minimap\\Tracking\\Banker" } },
    { cle = "vol", libelle = "SVC_FLIGHT", fichiers = { "Interface\\Minimap\\Tracking\\FlightMaster" } },
    -- Marchands de fleches et de balles (pour les classes qui tirent).
    { cle = "munitions", libelle = "SVC_AMMO", fichiers = { "Interface\\Icons\\INV_Ammo_Arrow_02" }, defaut = true, rond = true },
}
-- Les munitions ne concernent que les classes qui tirent.
local TIREURS = { HUNTER = true, WARRIOR = true, ROGUE = true }
page.SERVICES = SERVICES

-- Les services se filtrent comme le reste, dans la barre de la suite sous
-- la carte (cle "svc:..."). Les anciens reglages de MapCore sont repris une
-- fois.
local function ServicesReglages()
    local r = Reglages()
    r.services = type(r.services) == "table" and r.services or {}
    return r.services
end

function page.ServiceActif(cle)
    local S = NS.suite or _G.CoreSuite
    local service
    for _, sv in ipairs(SERVICES) do if sv.cle == cle then service = sv end end
    if not service then return false end
    if S and S.Filtre then
        S.defautsFiltres = S.defautsFiltres or {}
        if service.defaut ~= true then S.defautsFiltres["svc:" .. cle] = false end
        local ancien = ServicesReglages()[cle]
        if ancien ~= nil and S.PoserFiltre then
            ServicesReglages()[cle] = nil
            local d = S.Filtre("svc:" .. cle)
            if d ~= ancien then S.PoserFiltre("svc:" .. cle, ancien, true) end
        end
        return S.Filtre("svc:" .. cle)
    end
    local v = ServicesReglages()[cle]
    if v == nil then return service.defaut == true end
    return v == true
end

-- Les filtres de services, pour la barre de la suite.
local function FiltresDeServices()
    local liste = {}
    for _, sv in ipairs(SERVICES) do
        table.insert(liste, { cle = "svc:" .. sv.cle, fichier = sv.fichiers[1], nomTraduit = NS.L[sv.libelle],
            defaut = sv.defaut == true })
    end
    return liste
end

-- La premiere icone que ce client sait afficher.
-- Icone ronde : le masque rond du jeu (pas de coins noirs). Un masque
-- interdit ensuite SetTexCoord : on n'en pose jamais sur ces textures.
local function Arrondir(tex)
    if tex.arrondie then return end
    tex.arrondie = true
    if tex.SetMask then pcall(tex.SetMask, tex, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
end

local function PoserIcone(tex, service)
    service.fichierBon = service.fichierBon or service.fichiers[1]
    tex:SetTexture(service.fichierBon)
end

local ICONES_METIER = {
    ALCHEMY = "Interface\\Icons\\Trade_Alchemy", BLACKSMITHING = "Interface\\Icons\\Trade_BlackSmithing",
    ENCHANTING = "Interface\\Icons\\Trade_Engraving", ENGINEERING = "Interface\\Icons\\Trade_Engineering",
    HERBALISM = "Interface\\Icons\\Trade_Herbalism", LEATHERWORKING = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    MINING = "Interface\\Icons\\Trade_Mining", SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    TAILORING = "Interface\\Icons\\Trade_Tailoring", COOKING = "Interface\\Icons\\INV_Misc_Food_15",
    FIRSTAID = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", FISHING = "Interface\\Icons\\Trade_Fishing",
}

local function InfoService(cle)
    for _, s in ipairs(SERVICES) do if s.cle == cle then return s end end
end

-- L'icone d'une entree : celle de son metier pour un maitre de metier.
-- Deuxieme valeur : vrai pour une icone d'objet (carree), a arrondir.
local function IconeDe(e)
    if e[1] == "metier" and ICONES_METIER[e[7]] then return ICONES_METIER[e[7]], true end
    local service = InfoService(e[1])
    return service and service.fichiers[1], service and service.rond or false
end

-- Pose une icone sur une paire de textures : la normale (icones de suivi du
-- jeu, deja detourees) ou la ronde (icones d'objets).
local function PoserSur(porteur, icone, rond)
    porteur.icone:SetShown(not rond)
    porteur.iconeRonde:SetShown(rond == true)
    if rond then porteur.iconeRonde:SetTexture(icone) else porteur.icone:SetTexture(icone) end
end
page.IconeDe = IconeDe

-- Contour sombre et rond sous une icone ronde, plus net qu'un anneau.
local function Contour(parent, taille)
    local c = parent:CreateTexture(nil, "BACKGROUND")
    c:SetSize(taille + 3, taille + 3)
    c:SetPoint("CENTER")
    c:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    c:SetVertexColor(0.08, 0.06, 0.03, 0.9)
    return c
end

local function PinService(rang)
    vue.services = vue.services or {}
    local b = vue.services[rang]
    if b then return b end
    b = CreateFrame("Button", nil, vue.toile)
    b:SetSize(16, 16)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.iconeRonde = b:CreateTexture(nil, "ARTWORK")
    b.iconeRonde:SetPoint("CENTER")
    b.iconeRonde:SetSize(14, 14)
    Arrondir(b.iconeRonde)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local e = self.entree
        if e[1] == "courrier" then
            GameTooltip:SetText(NS.L.SVC_MAILBOX, 1, 0.82, 0)
        else
            GameTooltip:SetText(e[4], 1, 0.82, 0)
            if e[5] and e[5] ~= "" then GameTooltip:AddLine(e[5], 1, 1, 1) end
            for _, a in ipairs(self.autres or {}) do
                GameTooltip:AddLine(a[4] .. ((a[5] and a[5] ~= "") and ("  |cffbbbbbb" .. a[5] .. "|r") or ""), 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine(NS.L.GO_CLICK, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Clic : la fleche de guidage jusqu'a lui (et il clignote).
    b:SetScript("OnMouseUp", function(self, bouton)
        if bouton ~= "LeftButton" then return end
        local e = self.entree
        local service = InfoService(e[1])
        page.GuiderVers({ carte = vue.idCarte, x = e[2] / 100, y = e[3] / 100,
            nom = e[1] == "courrier" and NS.L.SVC_MAILBOX or e[4], detail = e[5] ~= "" and e[5] or nil,
            icone = (IconeDe(e)), rond = select(2, IconeDe(e)), petit = true })
    end)
    vue.services[rang] = b
    return b
end

-- Nouveau choix : un halo dore qui s'elargit et s'efface deux fois pour
-- dire "c'est ici", puis l'icone clignote (cible.debutClignote).
local function Halo(b, cible)
    if not b.ping then
        local f = CreateFrame("Frame", nil, b)
        f:SetPoint("CENTER")
        f:SetSize(44, 44)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        t:SetVertexColor(1, 0.82, 0)
        t:SetBlendMode("ADD")
        local ag = f:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local taille = ag:CreateAnimation("Scale")
        if taille.SetScaleFrom then taille:SetScaleFrom(0.3, 0.3) taille:SetScaleTo(1.4, 1.4)
        else taille:SetFromScale(0.3, 0.3) taille:SetToScale(1.4, 1.4) end
        taille:SetDuration(0.8)
        local fondu = ag:CreateAnimation("Alpha")
        fondu:SetFromAlpha(0.9)
        fondu:SetToAlpha(0)
        fondu:SetDuration(0.8)
        f.anim = ag
        b.ping = f
    end
    b.ping:Show()
    b.ping.anim:Play()
    cible.debutClignote = (GetTime and GetTime() or 0) + 1.6
    local ping = b.ping
    local plusTard = NS.Lecture("C_Timer.After")
    if plusTard then
        plusTard(1.6, function()
            ping.anim:Stop()
            ping:Hide()
            if page.cibleGuidee == cible and b:IsShown() and b.anim then b.anim:Play() end
        end)
    end
end

local function PoserServices(idCarte)
    for _, b in ipairs(vue.services or {}) do
        if b.anim then b.anim:Stop() end
        b:SetAlpha(1)
        b:Hide()
    end
    vue.nServices = 0
    vue.cibleSurCarte = false
    local liste = NS.SERVICES and NS.SERVICES[idCarte]
    if not liste then return end
    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
    local _, classe = NS.Appeler(UnitClass, "player")
    local c = page.cibleGuidee
    local poses = {}
    for _, e in ipairs(liste) do
        local ok = page.ServiceActif(e[1])
        if ok and e[6] ~= "" and e[6] ~= "AH" and e[6] ~= faction then ok = false end
        if ok and e[1] == "classe" and classe and e[7] ~= "" and e[7] ~= classe then ok = false end
        if ok and e[1] == "munitions" and classe and not TIREURS[classe] then ok = false end
        -- Deux icones identiques presque au meme endroit (deux maitres
        -- d'alchimie cote a cote) n'en font qu'une ; l'infobulle les nomme.
        if ok then
            for _, autre in ipairs(poses) do
                local ae = autre.entree
                if ae[1] == e[1] and ae[7] == e[7] and math.abs(ae[2] - e[2]) < 1.2 and math.abs(ae[3] - e[3]) < 1.2 then
                    if e[4] ~= "" and e[4] ~= ae[4] then
                        autre.autres = autre.autres or {}
                        table.insert(autre.autres, e)
                    end
                    -- Celui qu'on rejoint garde sa place exacte.
                    if c and math.abs(c.x - e[2] / 100) < 0.0005 and math.abs(c.y - e[3] / 100) < 0.0005 then
                        autre.ax, autre.ay = e[2] / 100, e[3] / 100
                    end
                    ok = false
                    break
                end
            end
        end
        if ok then
            vue.nServices = vue.nServices + 1
            local b = PinService(vue.nServices)
            b.autres = nil
            table.insert(poses, b)
            b.entree = e
            PoserSur(b, IconeDe(e))
            b.ax, b.ay = e[2] / 100, e[3] / 100
            b:Show()
        end
    end
    -- Chaque icone a son propre etage, toujours le meme : leur ordre ne
    -- change jamais d'un dessin a l'autre. Celle qu'on rejoint passe au-dessus
    -- et clignote, a sa place ; les autres ne bougent pas.
    local base = vue.toile:GetFrameLevel() + 3
    for rang, b in ipairs(poses) do
        local vise = c and c.carte == idCarte and math.abs(c.x - b.ax) < 0.0005 and math.abs(c.y - b.ay) < 0.0005
        b:SetFrameLevel(vise and (base + #poses + 1) or (base + rang))
        if vise then
                -- Nouveau choix : un halo dore qui s'elargit et s'efface deux
                -- fois pour dire "c'est ici", puis l'icone clignote.
                if c.halo ~= false then
                    c.halo = false
                    Halo(b, c)
                end
                if not b.anim then
                    b.anim = b:CreateAnimationGroup()
                    b.anim:SetLooping("BOUNCE")
                    local fondu = b.anim:CreateAnimation("Alpha")
                    fondu:SetFromAlpha(1)
                    fondu:SetToAlpha(0)
                    fondu:SetDuration(0.6)
                end
                local maintenant = GetTime and GetTime() or 0
                if not b.anim:IsPlaying() and maintenant >= (c.debutClignote or 0) then b.anim:Play() end
                vue.cibleSurCarte = true
            elseif b.anim and b.anim:IsPlaying() then
                b.anim:Stop()
            end
    end
end

-- Les services visibles de cette carte, pour la liste des plus proches.
function page.ServicesVisibles(idCarte)
    local liste = {}
    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
    local _, classe = NS.Appeler(UnitClass, "player")
    for _, e in ipairs(NS.SERVICES and NS.SERVICES[idCarte] or {}) do
        local ok = page.ServiceActif(e[1])
        if ok and e[6] ~= "" and e[6] ~= "AH" and e[6] ~= faction then ok = false end
        if ok and e[1] == "classe" and classe and e[7] ~= "" and e[7] ~= classe then ok = false end
        if ok and e[1] == "munitions" and classe and not TIREURS[classe] then ok = false end
        if ok then
            local icone, rond = IconeDe(e)
            table.insert(liste, { carte = idCarte, x = e[2] / 100, y = e[3] / 100,
                nom = e[1] == "courrier" and NS.L.SVC_MAILBOX or e[4],
                detail = e[5] ~= "" and e[5] or nil, icone = icone, rond = rond, petit = true })
        end
    end
    return liste
end

-- La destination guidee clignote sur la carte : son icone, a sa taille,
-- qui apparait et disparait.
function page.PoserClignote(idCarte)
    if not vue then return end
    if not vue.clignote then
        local b = CreateFrame("Frame", nil, vue.toile)
        b.icone = b:CreateTexture(nil, "OVERLAY")
        b.icone:SetAllPoints()
        b.iconeRonde = b:CreateTexture(nil, "OVERLAY")
        b.iconeRonde:SetPoint("CENTER")
        b.iconeRonde:SetSize(14, 14)
        Arrondir(b.iconeRonde)
        local ag = b:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fondu = ag:CreateAnimation("Alpha")
        fondu:SetFromAlpha(1)
        fondu:SetToAlpha(0)
        fondu:SetDuration(0.6)
        b.anim = ag
        vue.clignote = b
    end
    local b, c = vue.clignote, page.cibleGuidee
    -- Deja pose sur la carte (un service) : il clignote lui-meme.
    if c and c.carte == idCarte and not vue.cibleSurCarte then
        local taille = c.petit and 16 or 20
        b:SetSize(taille, taille)
        PoserSur(b, c.icone, c.rond)
        b.ax, b.ay = c.x, c.y
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 40)
        b:Show()
        if c.halo ~= false then
            c.halo = false
            Halo(b, c)
        end
        local maintenant = GetTime and GetTime() or 0
        if not b.anim:IsPlaying() and maintenant >= (c.debutClignote or 0) then b.anim:Play() end
    else
        b.anim:Stop()
        b:Hide()
    end
end

-- Localiser depuis un autre add-on (marchand, recolte, quete...) : la carte
-- s'ouvre sur la destination, qui clignote apres un halo. La fleche, elle,
-- est celle du guidage lance par cet add-on.
function page.Localiser(dst)
    if type(dst) ~= "table" or not dst.carte then return end
    carteChoisie, continentChoisi = dst.carte, nil
    page.cibleGuidee = { carte = dst.carte, x = dst.x, y = dst.y, nom = dst.nom,
        icone = dst.icone or "Interface\\Minimap\\Tracking\\Target", petit = true }
    local S = NS.suite or _G.CoreSuite
    local f = NS.fenetre and NS.fenetre.Cadre and NS.fenetre.Cadre()
    if f and f:IsShown() then
        page.Rendre()
    elseif S and S.Ouvrir and S.membres and S.membres.MapCore then
        S.Ouvrir("MapCore")
    elseif NS.fenetre and NS.fenetre.Ouvrir then
        NS.fenetre.Ouvrir()
    end
    -- La fenetre vient de s'ouvrir : sa vue a pu effacer la cible en se
    -- cachant auparavant ; on la repose.
    if not page.cibleGuidee then
        page.cibleGuidee = { carte = dst.carte, x = dst.x, y = dst.y, nom = dst.nom,
            icone = dst.icone or "Interface\\Minimap\\Tracking\\Target", petit = true }
        page.Rendre()
    end
end

function page.CompteServices() return vue and vue.nServices or 0 end

local function Disposer()
    if not vue or not vue.largeur then return end
    local placeL = (vue:GetWidth() or 0)
    local placeH = (vue:GetHeight() or 0) - HAUT_TITRE - BAS_CARTE
    if placeL <= 0 or placeH <= 0 then placeL, placeH = 780, 480 end
    local ajuste = math.min((placeL - 8) / vue.largeur, (placeH - 8) / vue.hauteur)
    local l0, h0 = vue.largeur * ajuste, vue.hauteur * ajuste
    vue.bord:ClearAllPoints()
    vue.bord:SetPoint("TOP", vue, "TOP", 0, -HAUT_TITRE)
    vue.bord:SetSize(l0 + 8, h0 + 8)

    local echelle = ajuste * zoom
    local l, h = vue.largeur * echelle, vue.hauteur * echelle
    decX = math.min(0, math.max(l0 - l, decX))
    decY = math.min(0, math.max(h0 - h, decY))
    vue.toile:SetScale(echelle)
    if page.Retenir then pcall(page.Retenir) end
    vue.toile:ClearAllPoints()
    vue.toile:SetPoint("TOPLEFT", vue.clip, "TOPLEFT", decX / echelle, -decY / echelle)
    vue.echelle = echelle
    -- Tous les reperes affiches, poses ensemble : ceux qui tombent au meme
    -- endroit sont mis cote a cote, jamais empiles.
    local poses = {}
    local function Prendre(b)
        if not (b and b.ax and b.ay) then return end
        b:SetScale(1 / echelle)
        table.insert(poses, { b = b, x = b.ax * vue.largeur * echelle, y = b.ay * vue.hauteur * echelle,
            taille = math.max(b:GetWidth() or 0, b:GetHeight() or 0, 16),
            ordre = b.point and b.point.numero or b.numeroEtape or nil })
    end
    for i = 1, vue.enService do Prendre(vue.reperes[i]) end
    for i = 1, (vue.nLieux or 0) do Prendre(vue.lieux[i]) end
    for i = 1, (vue.nPersos or 0) do Prendre(vue.persos[i]) end
    if vue.clignote and vue.clignote:IsShown() then Prendre(vue.clignote) end
    for i = 1, (vue.nServices or 0) do Prendre(vue.services[i]) end
    for i = 1, (vue.nMiens or 0) do Prendre(vue.miens[i]) end
    for i = 1, (vue.nPlan or 0) do Prendre(vue.pinsPlan[i]) end
    -- Recalcule seulement si le zoom ou les reperes changent (pas en glissant).
    local morceaux = { string.format("%.4f", echelle) }
    for _, e in ipairs(poses) do morceaux[#morceaux + 1] = string.format("%.3f,%.3f", e.b.ax, e.b.ay) end
    local cle = table.concat(morceaux, ":")
    if cle ~= vue.cleEcart then
        vue.cleEcart = cle
        local Suite = NS.suite or _G.CoreSuite
        if Suite and Suite.Ecarter then pcall(Suite.Ecarter, poses, 22) end
        for _, e in ipairs(poses) do e.b.ecartX, e.b.ecartY, e.b.ecartMasque, e.b.ecartGroupe = e.dx or 0, e.dy or 0, e.masque, e.groupe end
    end
    local SuiteE = NS.suite or _G.CoreSuite
    for _, e in ipairs(poses) do
        e.b:ClearAllPoints()
        e.b:SetPoint("CENTER", vue.toile, "TOPLEFT", e.x + (e.b.ecartX or 0), -(e.y + (e.b.ecartY or 0)))
        if SuiteE and SuiteE.PoserEcarte then pcall(SuiteE.PoserEcarte, e.b) end
    end
    page.PlacerJoueur()
end

local function CurseurDansClip()
    local x, y = GetCursorPosition()
    local s = vue.clip:GetEffectiveScale()
    return x / s - (vue.clip:GetLeft() or 0), (vue.clip:GetTop() or 0) - y / s
end

-- Carte parente (ville -> zone -> continent -> monde), ou nil.
local function CarteParente(id)
    local info = id and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), id)
    local parent = type(info) == "table" and info.parentMapID
    if not parent or parent == 0 then return nil end
    local infoP = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), parent)
    if type(infoP) ~= "table" or (infoP.mapType or 9) < 1 then return nil end
    return parent
end

local function Zoomer(facteur, autourX, autourY)
    if not vue.largeur then return end
    local ancien = zoom
    zoom = math.max(1, math.min(ZOOM_MAX, zoom * facteur))
    if zoom == ancien then return end
    autourX = autourX or (vue.clip:GetWidth() or 0) / 2
    autourY = autourY or (vue.clip:GetHeight() or 0) / 2
    local r = zoom / ancien
    decX = autourX - (autourX - decX) * r
    decY = autourY - (autourY - decY) * r
    Disposer()
end

-- La fenetre s'efface en course, si demande ; nette a l'arret ou au survol.
-- Le survol ne compte que si la souris a bouge depuis peu : a la manette,
-- le curseur cache reste pose sur la fenetre et l'empechait de s'effacer.
-- En avancant, la camera qui suit le personnage fait trembler le curseur
-- cache de quelques pixels : il passait pour "bouge" et la fenetre restait
-- nette (a reculons, la camera ne tourne pas, d'ou l'effet). Desormais : la
-- manette active ou la camera tenue a la souris ne comptent jamais comme un
-- survol, et seul un vrai deplacement de la souris (plus de 6 pixels) compte.
local curseurX, curseurY, dernierBouge = nil, nil, 0
local function SourisSur(fenetre)
    local pad = _G.C_GamePad
    if pad and pad.IsEnabled then
        local ok, actif = pcall(pad.IsEnabled)
        if ok and actif then return false end
    end
    if IsMouselooking and IsMouselooking() then return false end
    local x, y = GetCursorPosition()
    x, y = x or 0, y or 0
    local maintenant = GetTime and GetTime() or 0
    if not curseurX or math.abs(x - curseurX) + math.abs(y - curseurY) > 6 then
        curseurX, curseurY, dernierBouge = x, y, maintenant
    end
    return fenetre:IsMouseOver() and (maintenant - dernierBouge) < 2
end

local function Fondu(ecoule)
    -- La suite efface toutes ses fenetres quand on marche : rien a faire ici.
    do return end
    local fenetre = _G.MapCoreFenetre
    if not fenetre then return end
    local cible = 1
    if Reglages().fondu and not SourisSur(fenetre) then
        local vitesse = NS.Appeler(GetUnitSpeed, "player") or 0
    -- En combat, le jeu peut rendre une valeur secrete : on ne s'en sert pas.
    if _G.issecretvalue and _G.issecretvalue(vitesse) then vitesse = 0 end
        if vitesse > 0 then cible = ALPHA_COURSE end
    end
    local actuel = fenetre:GetAlpha() or 1
    if math.abs(actuel - cible) < 0.01 then return end
    local pas = 3 * (ecoule or 0.05)
    if actuel < cible then actuel = math.min(cible, actuel + pas) else actuel = math.max(cible, actuel - pas) end
    fenetre:SetAlpha(actuel)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function Construire(parent, basDroite)
    vue = CreateFrame("Frame", nil, parent)
    vue:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    vue:SetPoint("BOTTOMRIGHT", basDroite, "BOTTOMRIGHT", 0, 0)

    -- Nom de la zone, centre au-dessus de la carte, comme la carte du jeu.
    vue.titre = vue:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    vue.titre:SetPoint("TOP", vue, "TOP", 0, -4)

    local ok, bord = pcall(CreateFrame, "Frame", nil, vue, "BackdropTemplate")
    bord = ok and bord or CreateFrame("Frame", nil, vue)
    if bord.SetBackdrop then
        bord:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bord:SetBackdropColor(0, 0, 0, 1)
        bord:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
    end
    vue.bord = bord

    local clip = CreateFrame("Frame", nil, bord)
    clip:SetPoint("TOPLEFT", bord, "TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMRIGHT", bord, "BOTTOMRIGHT", -4, 4)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:EnableMouse(true)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(_, sens)
        local x, y = CurseurDansClip()
        Zoomer(sens > 0 and 1.12 or 1 / 1.12, x, y)
    end)
    clip:SetScript("OnMouseDown", function(_, bouton)
        if bouton ~= "LeftButton" then return end
        local x, y = CurseurDansClip()
        vue.saisie = { x = x, y = y, dx = decX, dy = decY }
    end)
    clip:SetScript("OnMouseUp", function(_, bouton)
        local saisie = vue.saisie
        vue.saisie = nil
        -- Simple clic gauche (sans glisser) sur un continent ou le monde : on
        -- descend dans la zone cliquee.
        if bouton == "LeftButton" and saisie and vue.largeur and vue.echelle then
            local x, y = CurseurDansClip()
            if math.abs(x - saisie.x) < 4 and math.abs(y - saisie.y) < 4 then
                local info = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), vue.idCarte)
                if type(info) == "table" and (info.mapType or 9) <= 2 then
                    local u = (x - decX) / (vue.largeur * vue.echelle)
                    local v = (y - decY) / (vue.hauteur * vue.echelle)
                    local sous = NS.Appeler(NS.Lecture("C_Map.GetMapInfoAtPosition"), vue.idCarte, u, v)
                    if type(sous) == "table" and sous.mapID and sous.mapID ~= vue.idCarte then
                        carteChoisie = sous.mapID
                        page.Rendre()
                        return
                    end
                end
            end
        end
        -- Clic droit : un repere, la ou l'on clique.
        if bouton == "RightButton" and vue.largeur and vue.echelle then
            local x, y = CurseurDansClip()
            local u = (x - decX) / (vue.largeur * vue.echelle)
            local v = (y - decY) / (vue.hauteur * vue.echelle)
            if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
                -- Un brouillon : rien n'est garde avant Enregistrer.
                page.Editer({ carte = vue.idCarte, x = u, y = v, icone = 1, rayon = 0, note = "", nouveau = true })
            end
        end
    end)
    vue.clip = clip

    local toile = CreateFrame("Frame", nil, clip)
    toile:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    vue.toile = toile
    toile.tuiles, toile.revelees, toile.explorees = {}, {}, {}
    vue.reperes, vue.enService = {}, 0

    vue.vide = bord:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    vue.vide:SetPoint("CENTER")
    vue.vide:Hide()

    -- En haut a gauche : revenir a sa position quand on regarde ailleurs.
    vue.allerA = Bouton(bord, "", 60)
    vue.allerA:SetPoint("TOPLEFT", bord, "TOPLEFT", 8, -8)
    vue.allerA:SetFrameLevel(toile:GetFrameLevel() + 30)
    vue.allerA:Hide()

    -- Dans un donjon : l'outil de donjon choisi (Donjon Journal...), ouvert
    -- seulement sur ce clic. "Changer d'outil" quand il y en a plusieurs.
    vue.outil = Bouton(bord, "", 60)
    vue.outil:SetPoint("TOPLEFT", bord, "TOPLEFT", 8, -34)
    vue.outil:SetFrameLevel(toile:GetFrameLevel() + 30)
    vue.outil:SetScript("OnClick", function() page.OuvrirOutilDonjon() end)
    vue.outil:Hide()
    vue.outilChanger = Bouton(bord, L.PLAN_TOOL_CHANGE, 60)
    vue.outilChanger:SetPoint("LEFT", vue.outil, "RIGHT", 4, 0)
    vue.outilChanger:SetFrameLevel(toile:GetFrameLevel() + 30)
    vue.outilChanger:SetScript("OnClick", function()
        local S = NS.suite or _G.CoreSuite
        if S and S.OutilDonjonSuivant then S.OutilDonjonSuivant() end
        page.Rendre()
    end)
    vue.outilChanger:Hide()

    -- Aide, sous la carte.
    vue.aide = vue:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    vue.aide:SetPoint("BOTTOM", vue, "BOTTOM", 0, 2)
    vue.aide:SetText(NS.L.HELP)

    -- Filtres de la suite, sous la carte : quetes, a tuer, butin, objets,
    -- recolte, reperes.
    local Suite = NS.suite or _G.CoreSuite
    if Suite and Suite.BarreFiltres then
        vue.filtres = Suite.BarreFiltres(vue, function() page.Rendre() end, function() return vue.idCarte end,
            FiltresDeServices())
        vue.filtres:Etendre(bord, 8)
    end

    local plus = Bouton(bord, "+", 24)
    plus:SetPoint("TOPRIGHT", bord, "TOPRIGHT", -8, -8)
    plus:SetFrameLevel(toile:GetFrameLevel() + 30)
    plus:SetScript("OnClick", function() Zoomer(1.25) end)
    local moins = Bouton(bord, "-", 24)
    moins:SetPoint("TOP", plus, "BOTTOM", 0, -2)
    moins:SetFrameLevel(toile:GetFrameLevel() + 30)
    moins:SetScript("OnClick", function() Zoomer(1 / 1.25) end)
    -- Remonter d'un echelon, explicitement : ville -> zone -> continent.
    vue.remonter = Bouton(bord, "", 60)
    vue.remonter:SetPoint("TOPRIGHT", plus, "TOPLEFT", -6, 0)
    vue.remonter:SetFrameLevel(toile:GetFrameLevel() + 30)
    vue.remonter:SetScript("OnClick", function() page.Remonter() end)

    vue:SetScript("OnSizeChanged", function() if vue:IsVisible() then Disposer() end end)
    Calque()
    vue:SetScript("OnShow", function() calque:Show() end)
    vue:SetScript("OnHide", function()
        page.cibleGuidee = nil
        calque:Hide()
        local fenetre = _G.MapCoreFenetre
        if fenetre then fenetre:SetAlpha(1) end
    end)

    local attente = 0
    vue:SetScript("OnUpdate", function(_, ecoule)
        if vue.saisie then
            if not IsMouseButtonDown or IsMouseButtonDown("LeftButton") then
                local x, y = CurseurDansClip()
                decX = vue.saisie.dx + (x - vue.saisie.x)
                decY = vue.saisie.dy + (y - vue.saisie.y)
                Disposer()
            else
                vue.saisie = nil
            end
        end
        Fondu(ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.15
        -- Le trajet part du personnage : il le suit.
        DessinerTrajet()
        page.PlacerJoueur()
    end)
    return vue
end

-- ---------------------------------------------------------------------------
-- Art de la zone
-- ---------------------------------------------------------------------------

local function Tuile(liste, rang, couche)
    local t = liste[rang]
    if not t then
        t = vue.toile:CreateTexture(nil, couche or "BACKGROUND")
        liste[rang] = t
    end
    return t
end

local function Cacher(liste) for _, t in ipairs(liste) do t:Hide() end end

local function PoserFond(idCarte)
    Cacher(vue.toile.tuiles)
    local couches = NS.Appeler(Lecture("C_Map.GetMapArtLayers"), idCarte)
    local couche = type(couches) == "table" and couches[1]
    if not couche then return nil end
    local textures = NS.Appeler(Lecture("C_Map.GetMapArtLayerTextures"), idCarte, 1)
    if type(textures) ~= "table" then return nil end
    local lignes = math.ceil(couche.layerHeight / couche.tileHeight)
    local colonnes = math.ceil(couche.layerWidth / couche.tileWidth)
    local rang = 0
    for i = 1, lignes do
        for j = 1, colonnes do
            rang = rang + 1
            local t = Tuile(vue.toile.tuiles, rang)
            t:ClearAllPoints()
            t:SetSize(couche.tileWidth, couche.tileHeight)
            t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", (j - 1) * couche.tileWidth, -(i - 1) * couche.tileHeight)
            t:SetTexture(textures[rang])
            t:Show()
        end
    end
    return couche.layerWidth, couche.layerHeight
end

-- Un morceau de carte decoupe en tuiles de 256, comme la carte du jeu.
local function PoserMorceau(liste, rang, largeur, hauteur, x, y, fichiers, couche, sousCouche, teinte)
    local large = math.ceil(largeur / TUILE)
    local haut = math.ceil(hauteur / TUILE)
    for j = 1, haut do
        local pxH, fichierH = TUILE, TUILE
        if j == haut then
            pxH = hauteur % TUILE
            if pxH == 0 then pxH = TUILE end
            fichierH = 16
            while fichierH < pxH do fichierH = fichierH * 2 end
        end
        for k = 1, large do
            local pxL, fichierL = TUILE, TUILE
            if k == large then
                pxL = largeur % TUILE
                if pxL == 0 then pxL = TUILE end
                fichierL = 16
                while fichierL < pxL do fichierL = fichierL * 2 end
            end
            local fichier = fichiers[(j - 1) * large + k]
            if fichier then
                rang = rang + 1
                local t = Tuile(liste, rang, couche)
                t:SetDrawLayer(couche, sousCouche)
                t:ClearAllPoints()
                t:SetSize(pxL, pxH)
                t:SetTexCoord(0, pxL / fichierL, 0, pxH / fichierH)
                t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", x + TUILE * (k - 1), -(y + TUILE * (j - 1)))
                t:SetTexture(fichier)
                t:SetVertexColor(teinte, teinte, teinte)
                t:Show()
            end
        end
    end
    return rang
end

local function PoserRevelees(idCarte)
    Cacher(vue.toile.revelees)
    if not Reglages().reveler then return 0 end
    local art = NS.Appeler(Lecture("C_Map.GetMapArtID"), idCarte)
    local morceaux = art and NS.reveleCarte and NS.reveleCarte[art]
    if type(morceaux) ~= "table" then return 0 end
    local rang = 0
    for cle, liste in pairs(morceaux) do
        local l, h, x, y = string.match(cle, "^(%d+):(%d+):(%d+):(%d+)$")
        if l then
            local fichiers = {}
            for id in string.gmatch(liste, "%d+") do table.insert(fichiers, tonumber(id)) end
            rang = PoserMorceau(vue.toile.revelees, rang, tonumber(l), tonumber(h), tonumber(x), tonumber(y),
                fichiers, "BORDER", 0, 0.6)
        end
    end
    return rang
end

local function PoserExplorees(idCarte)
    Cacher(vue.toile.explorees)
    local infos = NS.Appeler(Lecture("C_MapExplorationInfo.GetExploredMapTextures"), idCarte)
    if type(infos) ~= "table" then return 0 end
    local rang = 0
    for _, info in ipairs(infos) do
        rang = PoserMorceau(vue.toile.explorees, rang, info.textureWidth or 0, info.textureHeight or 0,
            info.offsetX or 0, info.offsetY or 0, info.fileDataIDs or {}, "BORDER", 1, 1)
    end
    return rang
end

-- ---------------------------------------------------------------------------
-- Reperes
-- ---------------------------------------------------------------------------

local function CoordsIcone(i)
    local c, l = (i - 1) % 4, math.floor((i - 1) / 4)
    return c * 0.25, (c + 1) * 0.25, l * 0.25, (l + 1) * 0.25
end
page.CoordsIcone = CoordsIcone

-- Couleur de chaque icone de cible : etoile, cercle, losange, triangle, lune,
-- carre, croix, crane.
local COULEURS = { { 1, 0.9, 0.2 }, { 1, 0.55, 0.1 }, { 0.75, 0.35, 1 }, { 0.3, 0.9, 0.3 },
    { 0.75, 0.85, 1 }, { 0.25, 0.55, 1 }, { 1, 0.25, 0.2 }, { 1, 1, 1 } }
local RAYONS = { 0.03, 0.06, 0.1 }

local function Repere(rang)
    vue.miens = vue.miens or {}
    local b = vue.miens[rang]
    if b then return b end
    b = CreateFrame("Button", nil, vue.toile)
    b:SetSize(20, 20)
    b:RegisterForClicks("LeftButtonUp")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.icone:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    b.zone = vue.toile:CreateTexture(nil, "ARTWORK", nil, -2)
    b.zone:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(NS.L.MARKER, 1, 0.82, 0)
        if self.repere.note and self.repere.note ~= "" then GameTooltip:AddLine(self.repere.note, 1, 1, 1, true) end
        GameTooltip:AddLine(NS.L.CLICK_EDIT, 0.6, 0.6, 0.6)
        GameTooltip:AddLine(NS.L.DRAG_MOVE, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) page.Editer(self.repere) end)
    -- Glisser : deplacer le repere.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) self.glisse = true GameTooltip:Hide() end)
    b:SetScript("OnDragStop", function(self)
        self.glisse = nil
        local r = self.repere
        if not (r and vue.largeur and vue.echelle) then return end
        local x, y = CurseurDansClip()
        local u = (x - decX) / (vue.largeur * vue.echelle)
        local v = (y - decY) / (vue.hauteur * vue.echelle)
        if u >= 0 and u <= 1 and v >= 0 and v <= 1 then r.x, r.y = u, v end
        page.Rendre()
    end)
    b:SetScript("OnUpdate", function(self)
        if not self.glisse or not vue.echelle then return end
        local x, y = CurseurDansClip()
        self:ClearAllPoints()
        self:SetPoint("CENTER", vue.clip, "TOPLEFT", x, -y)
    end)
    vue.miens[rang] = b
    return b
end

-- Quetes de QuestCore (si installe) et reperes de l'utilisateur.
local function PoserReperes(idCarte)
    for i = 1, vue.enService do vue.reperes[i]:Hide() end
    vue.enService = 0
    for _, b in ipairs(vue.miens or {}) do b:Hide() b.zone:Hide() end
    local Suite = NS.suite or _G.CoreSuite
    local function Montre(cle) return not (Suite and Suite.Filtre) or Suite.Filtre(cle) end
    local api = _G.QuestCoreAPI
    if api then
        local ok, points = pcall(api.Points)
        for _, pt in ipairs(ok and points or {}) do
            local x, y
            local garder = not (Suite and Suite.PointVisible) or Suite.PointVisible(pt)
            local guide = Suite and Suite.GuidageActif and Suite.GuidageActif("QuestCore")
            if guide then garder = pt.numero ~= nil end
            -- Zone par zone : le detail d'une zone ne s'additionne pas a celui
            -- des autres (sauf les etapes du trajet guide).
            if garder and not pt.numero and api.ParZone and not api.ParZone(pt, idCarte) then garder = false end
            if garder then x, y = api.Reporter(pt, idCarte) end
            if x then
                vue.enService = vue.enService + 1
                local b = vue.reperes[vue.enService]
                if not b then
                    b = api.CreerRepere(vue.toile)
                    vue.reperes[vue.enService] = b
                end
                api.Habiller(b, pt.genre, pt.icone, pt.attente)
                b.point, b.ax, b.ay = pt, x, y
                b:SetFrameLevel(vue.toile:GetFrameLevel() + 2)
                b.numero:SetText(pt.numero and tostring(pt.numero) or "")
                b:Show()
            end
        end
    end
    -- Lieux de recolte notes par CraftCore : l'icone de la matiere, ronde.
    for _, b in ipairs(vue.lieux or {}) do b:Hide() end
    vue.nLieux = 0
    local cc = _G.CraftCoreAPI
    -- Pendant le guidage d'un trajet de quetes : rien que le trajet.
    local guideQuetes = Suite and Suite.GuidageActif and Suite.GuidageActif("QuestCore")
    if cc and cc.Lieux and Suite and Suite.PionRecolte and not guideQuetes then
        local ok, lieux = pcall(cc.Lieux, idCarte)
        vue.lieux = vue.lieux or {}
        local garder = {}
        for _, l in ipairs(ok and lieux or {}) do
            if not Suite.LieuVisible or Suite.LieuVisible(l) then table.insert(garder, l) end
        end
        for _, l in ipairs(garder) do
            vue.nLieux = vue.nLieux + 1
            local b = vue.lieux[vue.nLieux]
            if not b then
                b = Suite.PionRecolte(vue.toile)
                -- Clic droit : ajouter a la tournee (Maj : toute la matiere).
                b:SetScript("OnMouseUp", function(self, bouton)
                    if bouton == "RightButton" and self.lieu then
                        page.ChoisirLieu(self.lieu, IsShiftKeyDown and IsShiftKeyDown())
                    end
                end)
                if Suite.PastilleNumero then
                    b.numero = Suite.PastilleNumero(b, 17)
                    b.numero:SetPoint("CENTER", b, "BOTTOMRIGHT", 2, 0)
                else
                    b.numero = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    b.numero:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -4)
                end
                vue.lieux[vue.nLieux] = b
            end
            b:Poser(l)
            local rangT = RangDansTournee(l)
            local fait = rangT and Faits()[CleLieu(l)]
            if rangT then b.cercle:SetVertexColor(COULEUR_TOURNEE[1], COULEUR_TOURNEE[2], COULEUR_TOURNEE[3], 1)
            else b.cercle:SetVertexColor(0.75, 0.6, 0.35, 1) end
            b.numero:SetText(rangT and tostring(rangT) or "")
            b:SetAlpha(fait and 0.5 or 1)
            b:SetFrameLevel(vue.toile:GetFrameLevel() + 1)
            b:Show()
        end
    end
    local rang = 0
    for _, r in ipairs(NS.base.Reperes()) do
        if r.carte == idCarte and Montre("reperes") then
            rang = rang + 1
            local b = Repere(rang)
            b.repere = r
            b.icone:SetTexCoord(CoordsIcone(r.icone or 1))
            local c = COULEURS[r.icone or 1] or COULEURS[1]
            local rayon = RAYONS[r.rayon or 0]
            if rayon then
                local d = rayon * 2 * vue.largeur
                b.zone:ClearAllPoints()
                b.zone:SetSize(d, d)
                b.zone:SetPoint("CENTER", vue.toile, "TOPLEFT", r.x * vue.largeur, -r.y * vue.hauteur)
                b.zone:SetVertexColor(c[1], c[2], c[3], 0.28)
                b.zone:Show()
            end
            b.ax, b.ay = r.x, r.y
            b:SetFrameLevel(vue.toile:GetFrameLevel() + 10)
            b:Show()
        end
    end
    vue.nMiens = rang
    -- Mes autres personnages laisses sur cette carte : leur classe, ronde.
    for _, b in ipairs(vue.persos or {}) do b:Hide() end
    vue.nPersos = 0
    vue.persos = vue.persos or {}
    for _, p in ipairs(NS.base.Positions and NS.base.Positions() or {}) do
        if not p.moi and p.carte == idCarte and p.x then
            vue.nPersos = vue.nPersos + 1
            local b = vue.persos[vue.nPersos]
            if not b then
                b = CreateFrame("Button", nil, vue.toile)
                b:SetSize(22, 22)
                b.icone = b:CreateTexture(nil, "ARTWORK")
                b.icone:SetAllPoints()
                b.anneau = b:CreateTexture(nil, "OVERLAY")
                b.anneau:SetPoint("TOPLEFT", -4, 4)
                b.anneau:SetPoint("BOTTOMRIGHT", 4, -4)
                b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                b.anneau:SetTexCoord(0, 0.6, 0, 0.6)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                vue.persos[vue.nPersos] = b
            end
            local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
            b.icone:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            if coords then b.icone:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
            local perso = p
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(NS.NomCourt(perso.cle), 1, 0.82, 0)
                if perso.niveau then GameTooltip:AddLine(string.format(NS.L.CHAR_LEVEL, perso.niveau), 1, 1, 1) end
                if perso.foyer then GameTooltip:AddLine(string.format(NS.L.CHAR_HEARTH, perso.foyer), 1, 1, 1) end
                if perso.quand then
                    GameTooltip:AddLine(string.format(NS.L.CHAR_SEEN, tostring(NS.Appeler(date, "%d/%m %H:%M", perso.quand) or "?")), 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            b.ax, b.ay = p.x, p.y
            b:SetFrameLevel(vue.toile:GetFrameLevel() + 8)
            b:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Menu de gauche : continents, zones, affichage
-- ---------------------------------------------------------------------------

local function Enfants(carte, genre, tous)
    local liste = NS.Appeler(Lecture("C_Map.GetMapChildrenInfo"), carte, genre, tous and true or nil)
    if type(liste) ~= "table" then return {} end
    if not tous then return liste end
    -- Toutes profondeurs : une seule fois chaque carte, et seulement celles
    -- du genre demande.
    local vues, res = {}, {}
    for _, z in ipairs(liste) do
        if z.mapID and not vues[z.mapID] and (not genre or z.mapType == genre) then
            vues[z.mapID] = true
            table.insert(res, z)
        end
    end
    return res
end

local function ContinentDe(carte)
    local garde = 0
    while carte and garde < 6 do
        local info = NS.Appeler(Lecture("C_Map.GetMapInfo"), carte)
        if type(info) ~= "table" then return nil end
        if info.mapType == 2 then return carte end
        carte = info.parentMapID
        garde = garde + 1
    end
    return nil
end

local continentChoisi

-- Pour la manette : zoom au centre, et les lignes du menu.
function page.Zoomer(facteur) if vue then Zoomer(facteur) end end

function page.Remonter()
    if page.EtagePrecedent and page.EtagePrecedent() then return end
    local parent = vue and CarteParente(vue.idCarte)
    if not parent then return end
    carteChoisie = parent
    page.Rendre()
end
function page.Menu() return menu end

local function LigneMenu(rang)
    menu.lignes = menu.lignes or {}
    local l = menu.lignes[rang]
    if l then return l end
    l = CreateFrame("Button", nil, menu.liste)
    l:SetHeight(22)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.fond = l:CreateTexture(nil, "BACKGROUND")
    l.fond:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    l.fond:SetBlendMode("ADD")
    l.fond:SetAllPoints()
    local ok, case = pcall(CreateFrame, "CheckButton", nil, l, "UICheckButtonTemplate")
    if ok and case then
        case:SetSize(18, 18)
        case:SetPoint("LEFT", l, "LEFT", 2, 0)
        case:EnableMouse(false)
        l.case = case
    end
    -- La meme taille que les lignes des autres menus de la suite.
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.texte:SetJustifyH("LEFT")
    l.texte:SetWordWrap(false)
    menu.lignes[rang] = l
    return l
end

-- Niveaux d'une zone : ceux du jeu s'il les donne, sinon estimes d'apres
-- ses quetes par QuestCore. Rien si aucun des deux ne sait.
local niveauxVus = {}
local function NiveauxDeZone(id)
    local vu = niveauxVus[id]
    if vu == false then return nil end
    if vu then return vu[1], vu[2] end
    local mini, maxi
    local lecture = NS.Lecture("C_Map.GetMapLevels")
    if lecture then
        local ok, a, b = pcall(lecture, id)
        if ok and tonumber(a) and tonumber(b) and tonumber(a) > 0 then mini, maxi = tonumber(a), tonumber(b) end
    end
    local api = _G.QuestCoreAPI
    if not mini and api and api.NiveauDeCarte then
        local ok, a, b = pcall(api.NiveauDeCarte, id)
        if ok and a then mini, maxi = a, b end
    end
    niveauxVus[id] = mini and { mini, maxi } or false
    return mini, maxi
end

local TrancheDeZone
-- Les tranches de difficulte d'une zone pour le personnage connecte, d'apres
-- ses niveaux (mini - maxi) : les couleurs du journal de quetes du jeu.
local function NiveauJoueur() return tonumber(NS.Appeler(NS.Lecture("UnitLevel"), "player")) or 1 end
local function EcartVert()
    local f = NS.Lecture("GetQuestGreenRange")
    local ok, v = pcall(f or function() end)
    return tonumber(ok and v) or 5
end
local TRANCHES = {
    { cle = "grise", couleur = { 0.62, 0.62, 0.62 }, nom = function() return NS.L.ZONES_GREY end },
    { cle = "verte", couleur = { 0.25, 0.75, 0.25 }, nom = function() return NS.L.ZONES_GREEN end },
    { cle = "jaune", couleur = { 1.00, 0.82, 0.00 }, nom = function() return NS.L.ZONES_YELLOW end },
    { cle = "orange", couleur = { 1.00, 0.50, 0.25 }, nom = function() return NS.L.ZONES_ORANGE end },
    { cle = "rouge", couleur = { 1.00, 0.10, 0.10 }, nom = function() return NS.L.ZONES_RED end },
    { cle = "aucun", couleur = { 0.75, 0.75, 0.75 }, nom = function() return NS.L.ZONES_NONE end },
}
-- Les couleurs exactes du jeu, si elles sont la.
do
    local Q = _G.QuestDifficultyColors
    local CLES = { grise = "trivial", verte = "standard", jaune = "difficult", orange = "verydifficult", rouge = "impossible" }
    if type(Q) == "table" then
        for _, t in ipairs(TRANCHES) do
            local c = CLES[t.cle] and Q[CLES[t.cle]]
            if type(c) == "table" and c.r then t.couleur = { c.r, c.g, c.b } end
        end
    end
end
local RANG_TRANCHE = {}
for rang, t in ipairs(TRANCHES) do RANG_TRANCHE[t.cle] = rang end
-- Le niveau qui represente la zone : son niveau d'entree, plus la moitie de
-- sa fourchette, plafonnee a 10 (Forever donne des fourchettes tres larges,
-- 15-60 : le haut ne dit pas pour qui est la zone).
local function NiveauTypique(id)
    local mini, maxi = NiveauxDeZone(id)
    if not mini then return nil end
    return mini + math.floor(math.min(10, (maxi or mini) - mini) / 2)
end
-- Les seuils du journal de quetes du jeu : rouge a 5 niveaux au-dessus,
-- orange a 3, jaune jusqu'a 2 en dessous, vert ensuite, gris au-dela de
-- l'ecart ou les quetes ne rapportent plus.
TrancheDeZone = function(id)
    local typique = NiveauTypique(id)
    if not typique then return TRANCHES[6] end
    local ecart = typique - NiveauJoueur()
    if ecart >= 5 then return TRANCHES[5] end
    if ecart >= 3 then return TRANCHES[4] end
    if ecart >= -2 then return TRANCHES[3] end
    if ecart >= -EcartVert() then return TRANCHES[2] end
    return TRANCHES[1]
end

-- Les zones par niveau : la plus basse d'abord (niveau mini, puis maxi,
-- puis nom) ; une zone sans niveau connu (capitale...) a la fin.
local function ParNiveau(a, b)
    local ta, tb = RANG_TRANCHE[TrancheDeZone(a.mapID).cle], RANG_TRANCHE[TrancheDeZone(b.mapID).cle]
    if ta ~= tb then return ta < tb end
    local amin, amax = NiveauxDeZone(a.mapID)
    local bmin, bmax = NiveauxDeZone(b.mapID)
    if (amin ~= nil) ~= (bmin ~= nil) then return amin ~= nil end
    if amin and bmin then
        if amin ~= bmin then return amin < bmin end
        if amax ~= bmax then return (amax or 0) < (bmax or 0) end
    end
    return tostring(a.name) < tostring(b.name)
end

-- Couleur de difficulte du jeu, comme dans le journal de quetes : rouge,
-- orange, jaune, vert, gris (trop bas).
local function CouleurDeNiveau(niveau)
    local f = _G.GetQuestDifficultyColor
    if f then
        local ok, c = pcall(f, niveau)
        if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    local moi = tonumber((NS.Appeler(UnitLevel, "player"))) or 1
    local ecart = niveau - moi
    if ecart >= 5 then return { 1, 0.1, 0.1 } end
    if ecart >= 3 then return { 1, 0.5, 0.25 } end
    if ecart >= -2 then return { 1, 1, 0 } end
    if ecart >= -8 then return { 0.25, 0.75, 0.25 } end
    return { 0.5, 0.5, 0.5 }
end

-- ---------------------------------------------------------------------------
-- Ou aller : ce qu'on montre, et les destinations les plus proches
-- ---------------------------------------------------------------------------

local QUETES = { "quetes", "tuer", "butin", "objet" }
local RECOLTE = { "herbes", "minerais", "peche" }
page.MODES = {
    { cle = "tout", libelle = "GO_ALL" },
    { cle = "quetes", libelle = "GO_QUESTS" },
    { cle = "recolte", libelle = "GO_GATHER" },
    { cle = "reperes", libelle = "GO_MARKERS" },
}

local function Groupe(mode)
    if mode == "quetes" then return QUETES end
    if mode == "recolte" then return RECOLTE end
    if mode == "reperes" then return { "reperes" } end
    return nil
end

-- Le mode d'apres les filtres de la suite : tout, un seul groupe, ou rien
-- de reconnu (un melange choisi sous la carte).
function page.ModeAffiche()
    local S = NS.suite or _G.CoreSuite
    if not (S and S.Filtre and S.FILTRES) then return "tout" end
    local actifs = {}
    for _, f in ipairs(S.FILTRES) do if f.dispo() then actifs[f.cle] = S.Filtre(f.cle) end end
    local tout = true
    for _, v in pairs(actifs) do if not v then tout = false end end
    if tout then return "tout" end
    for _, m in ipairs({ "quetes", "recolte", "reperes" }) do
        local dans = {}
        for _, c in ipairs(Groupe(m)) do dans[c] = true end
        local ok = true
        for cle, v in pairs(actifs) do
            if (dans[cle] and not v) or (not dans[cle] and v) then ok = false end
        end
        if ok then return m end
    end
    return nil
end

function page.PoserMode(mode)
    local S = NS.suite or _G.CoreSuite
    if not (S and S.PoserFiltre and S.FILTRES) then return end
    local dans = {}
    for _, c in ipairs(Groupe(mode) or {}) do dans[c] = true end
    for _, f in ipairs(S.FILTRES) do S.PoserFiltre(f.cle, mode == "tout" or dans[f.cle] == true) end
end

local function Yards(carte, x, y)
    local f, V = NS.Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if not (f and V and carte and tonumber(x) and tonumber(y)) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        return a, b, continent
    end
    return nil
end

local ICONES_POINT = {
    prendre = "Interface\\GossipFrame\\AvailableQuestIcon",
    rendre = "Interface\\GossipFrame\\ActiveQuestIcon",
}

-- Les destinations montrees sur cette carte, la plus proche d'abord.
function page.Destinations(idCarte)
    local liste = {}
    if not idCarte then return liste end
    local S = NS.suite or _G.CoreSuite
    local L0 = NS.L
    local api = _G.QuestCoreAPI
    if api and api.Points then
        local ok, points = pcall(api.Points)
        local vues = {}
        for _, pt in ipairs(ok and points or {}) do
            if (not (S and S.PointVisible) or S.PointVisible(pt)) and (not api.ParZone or api.ParZone(pt, idCarte)) then
                local x, y = api.Reporter(pt, idCarte)
                local cle = tostring(pt.quete) .. ":" .. tostring(pt.genre)
                if x and not vues[cle] then
                    vues[cle] = true
                    local detail = pt.quoi
                    if pt.genre == "prendre" then detail = L0.GO_PICK_UP .. (pt.quoi and (" : " .. pt.quoi) or "")
                    elseif pt.genre == "rendre" then detail = L0.GO_TURN_IN .. (pt.quoi and (" : " .. pt.quoi) or "") end
                    table.insert(liste, { carte = idCarte, x = x, y = y, nom = pt.titre or "?", detail = detail,
                        icone = ICONES_POINT[pt.genre] or "Interface\\GossipFrame\\IncompleteQuestIcon" })
                end
            end
        end
    end
    local cc = _G.CraftCoreAPI
    if cc and cc.Lieux then
        local ok, lieux = pcall(cc.Lieux, idCarte)
        for _, l in ipairs(ok and lieux or {}) do
            if (l.x and l.y) and (not (S and S.LieuVisible) or S.LieuVisible(l)) then
                local nom = l.nomType or (NS.Appeler(NS.Lecture("C_Item.GetItemNameByID"), l.objet)) or "?"
                local icone = NS.Appeler(NS.Lecture("C_Item.GetItemIconByID", "GetItemIcon"), l.objet)
                table.insert(liste, { carte = idCarte, x = l.x, y = l.y, nom = nom, detail = L0.GO_GATHER_SPOT,
                    icone = icone or "Interface\\Icons\\Trade_Herbalism" })
            end
        end
    end
    if not (S and S.Filtre) or S.Filtre("reperes") then
        for _, r in ipairs(NS.base.Reperes()) do
            if r.carte == idCarte then
                local nom = (r.note and r.note ~= "") and r.note or L0.MARKER
                table.insert(liste, { carte = idCarte, x = r.x, y = r.y, nom = nom,
                    icone = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(r.icone or 1) })
            end
        end
    end
    -- Distance au personnage, s'il est sur cette carte (ou son continent).
    local carteJ = CarteDuPerso()
    local jx, jy = carteJ and PositionJoueur(carteJ)
    local wx, wy, wc
    if jx then wx, wy, wc = Yards(carteJ, jx, jy) end
    for _, dst in ipairs(liste) do
        if wx then
            local x, y, c = Yards(dst.carte, dst.x, dst.y)
            if x and c == wc then dst.distance = math.floor(math.sqrt((x - wx) ^ 2 + (y - wy) ^ 2) + 0.5) end
        end
    end
    table.sort(liste, function(a, b)
        if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
        if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
        return tostring(a.nom) < tostring(b.nom)
    end)
    return liste
end

-- La fleche de la suite vers une destination (objectif "service") ; arrive,
-- l'objectif est atteint. L'icone continue de clignoter jusqu'au prochain
-- choix ou a la fermeture de la fenetre.
function page.GuiderVers(dst)
    local S = NS.suite or _G.CoreSuite
    if not (S and S.LancerObjectif and dst) then return end
    if S.LancerObjectif("MapCore", "service", { carte = dst.carte, x = dst.x, y = dst.y, nom = dst.nom }) then
        page.cibleGuidee = dst
    end
    pcall(page.Rendre)
end

-- ---------------------------------------------------------------------------
-- Itineraires : les donnees (QuestCore pour les quetes, la tournee de
-- recolte ici) et le panneau central qui les liste.
-- ---------------------------------------------------------------------------
function page.EnItineraires() return page.itineraires == true end
function page.DonneesItin()
    local L0 = NS.L
    local api = _G.QuestCoreAPI
    local liste = {}
    if api and api.Itineraires then
        local ok, l = pcall(api.Itineraires)
        if ok and type(l) == "table" then liste = l end
    end
    local t0 = Tournee()
    local tournee = (type(t0) == "table" and type(t0.points) == "table" and #t0.points > 0) and t0 or nil
    -- Le guidage de recolte en cours, d'ou qu'il vienne (CraftCore...) : il
    -- est un itineraire de recolte comme les autres.
    local S = NS.suite or _G.CoreSuite
    local actif = S and S.ObjectifActif and S.ObjectifActif()
    local recolteEnCours = type(actif) == "table" and actif.type == "recolte" and actif or nil
    local function Compter(valeur)
        local n = 0
        for _, it in ipairs(liste) do if it.type == valeur then n = n + 1 end end
        return n
    end
    local types = {
        { cle = "suite", nom = L0.ROUTES_CHAINS, n = Compter("suite"), icone = "Interface\\Icons\\INV_Scroll_03" },
        { cle = "donjon", nom = L0.ROUTES_DUNGEONS, n = Compter("donjon"), icone = "Interface\\Icons\\INV_Misc_Key_14" },
        { cle = "zone", nom = L0.ROUTES_ZONES, n = Compter("zone"), icone = "Interface\\Icons\\INV_Misc_Map_02" },
        { cle = "niveau", nom = L0.ROUTES_LEVEL, n = 1, icone = "Interface\\Icons\\Spell_Holy_SurgeOfLight" },
        { cle = "recolte", nom = L0.ROUTES_FARM, n = (tournee and 1 or 0) + (recolteEnCours and 1 or 0), icone = "Interface\\Icons\\Trade_Herbalism" },
    }
    local parZone, zones = {}, {}
    for _, it in ipairs(liste) do
        if it.zone then
            if not parZone[it.zone] then parZone[it.zone] = { nom = it.zone, n = 0 } table.insert(zones, parZone[it.zone]) end
            parZone[it.zone].n = parZone[it.zone].n + 1
        end
    end
    table.sort(zones, function(a, b) return a.nom < b.nom end)
    -- Par defaut : le premier type qui a des itineraires.
    local filtre = page.filtreItin
    if not filtre then
        filtre = (recolteEnCours and { type = "recolte" }) or (types[1].n > 0 and { type = "suite" }) or (types[2].n > 0 and { type = "donjon" })
            or (tournee and { type = "recolte" }) or { type = "niveau" }
    end
    return { liste = liste, tournee = tournee, recolteEnCours = recolteEnCours, types = types, zones = zones, filtre = filtre, api = api }
end

-- LB / RB dans les itineraires : le type ou la zone precedent / suivant.
function page.ItinVoisin(pas)
    local choix = page.choixItin or {}
    if #choix == 0 then return end
    local f = page.filtreItin or page.DonneesItin().filtre
    local rang = 1
    for i, c in ipairs(choix) do
        if (c.type and c.type == f.type) or (c.zone and c.zone == f.zone) then rang = i end
    end
    rang = math.max(1, math.min(#choix, rang + pas))
    page.filtreItin = choix[rang]
    page.Rendre()
end

-- Le panneau central : les itineraires du type ou de la zone choisis.
local function PanneauItin()
    if not vue then return nil end
    local p = vue.panneauItin
    if p then return p end
    -- Au-dessus de la carte, hors de l'encrage du parchemin : un fond plein
    -- et des textes clairs, lisibles quel que soit le theme.
    p = CreateFrame("Frame", nil, vue:GetParent() or vue)
    p:SetAllPoints(vue.clip)
    p:SetFrameStrata(vue:GetFrameStrata() or "MEDIUM")
    p:SetFrameLevel((vue:GetFrameLevel() or 1) + 200)
    p.fond = p:CreateTexture(nil, "BACKGROUND")
    p.fond:SetAllPoints()
    p.fond:SetColorTexture(0.06, 0.05, 0.04, 0.97)
    p.sansEncre = true
    vue:HookScript("OnHide", function() p:Hide() end)
    p.titre = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.titre:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -20)
    local S = NS.suite or _G.CoreSuite
    if S and S.TitreDeMenu then S.TitreDeMenu(p.titre) end
    p.aide = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.aide:SetTextColor(0.7, 0.7, 0.7)
    p.aide:SetPoint("TOPLEFT", p.titre, "BOTTOMLEFT", 0, -6)
    p.lignes = {}
    p:EnableMouse(true)
    vue.panneauItin = p
    return p
end
local function LignePanneau(p, rang)
    local l = p.lignes[rang]
    if l then return l end
    l = CreateFrame("Button", nil, p)
    l:SetHeight(26)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.icone:SetPoint("LEFT", l, "LEFT", 4, 0)
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.texte:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
    l.texte:SetJustifyH("LEFT")
    l.texte:SetWordWrap(false)
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetPoint("RIGHT", l, "RIGHT", -6, 0)
    l.texte:SetPoint("RIGHT", l.droite, "LEFT", -10, 0)
    p.lignes[rang] = l
    return l
end
function page.RendrePanneauItin()
    if not vue then return end
    if not page.itineraires then
        if vue.panneauItin then vue.panneauItin:Hide() end
        return
    end
    local L0 = NS.L
    local p = PanneauItin()
    local d = page.DonneesItin()
    local f = d.filtre
    for _, l in ipairs(p.lignes) do l:Hide() end
    local titre = f.zone or ((f.type == "suite" and L0.ROUTES_CHAINS) or (f.type == "donjon" and L0.ROUTES_DUNGEONS)
        or (f.type == "zone" and L0.ROUTES_ZONES)
        or (f.type == "niveau" and L0.ROUTES_LEVEL) or L0.ROUTES_FARM)
    p.titre:SetText(titre)
    p.aide:SetText(L0.ROUTES_HELP)
    local n = 0
    local function Ajouter(icone, texte, droite, guide, auClic)
        n = n + 1
        local l = LignePanneau(p, n)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -(56 + (n - 1) * 28))
        l:SetPoint("RIGHT", p, "RIGHT", -20, 0)
        l.icone:SetTexture(icone)
        l.texte:SetText(texte)
        if guide then l.texte:SetTextColor(1, 0.82, 0) else l.texte:SetTextColor(1, 1, 1) end
        l.droite:SetText(droite or "")
        l:SetScript("OnClick", auClic)
        l:Show()
    end
    local api = d.api
    if f.type == "niveau" then
        local niv = (UnitLevel and UnitLevel("player") or 0) + 1
        Ajouter("Interface\\Icons\\Spell_Holy_SurgeOfLight", string.format(L0.ROUTES_TO_LEVEL, niv), L0.ROUTES_CLICK_GUIDE, false, function()
            if api and api.GuiderNiveau then pcall(api.GuiderNiveau, niv) end
            page.Rendre()
        end)
    elseif f.type == "recolte" then
        if d.recolteEnCours then
            local a = d.recolteEnCours
            local S = NS.suite or _G.CoreSuite
            local qui = a.proprietaire or ""
            local libelle = type(a.libelle) == "string" and a.libelle or L0.ROUTES_FARM
            Ajouter("Interface\\Icons\\Trade_Herbalism", qui .. " : " .. libelle, L0.ROUTES_CLICK_STOP, true, function()
                if S and S.Arreter then S.Arreter("joueur") end
                page.Rendre()
            end)
        end
        if d.tournee then
            local enCours = page.EnGuidage and page.EnGuidage() or false
            Ajouter("Interface\\Icons\\Trade_Herbalism", L0.ROUTES_FARM_ROUND,
                enCours and L0.ROUTES_CLICK_STOP or L0.ROUTES_CLICK_GUIDE, enCours, function() page.BasculerTournee() end)
        end
    else
        for _, it in ipairs(d.liste) do
            if (f.type and it.type == f.type) or (f.zone and it.zone == f.zone) then
                local uid = it.uid
                local icone = (it.type == "donjon" and "Interface\\Icons\\INV_Misc_Key_14")
                    or (it.type == "zone" and "Interface\\Icons\\INV_Misc_Map_02") or "Interface\\Icons\\INV_Misc_Map_01"
                local droite = it.faites .. " / " .. it.total .. (it.zone and ("   " .. it.zone) or "")
                Ajouter(icone, it.nom, droite, it.guide, function()
                    if api and api.GuiderItineraire then pcall(api.GuiderItineraire, uid) end
                    page.Rendre()
                end)
            end
        end
    end
    if n == 0 then Ajouter("Interface\\Icons\\INV_Misc_QuestionMark", L0.ROUTES_NONE, nil, false, function() end) end
    p:Show()
end

local function RendreMenu(idCarte)
    if not menu then return end
    for _, l in ipairs(menu.lignes or {}) do l:Hide() end
    for _, t in ipairs(menu.titres or {}) do t:Hide() if t.trait then t.trait:Hide() end end
    local y, n, nt = 0, 0, 0
    local function Titre(texte)
        nt = nt + 1
        menu.titres = menu.titres or {}
        local t = menu.titres[nt]
        if not t then
            t = menu.liste:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            menu.titres[nt] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", menu.liste, "TOPLEFT", 6, -y)
        t:SetText(texte)
        -- La police des titres de menu de la suite (stylisee, en or).
        local S = NS.suite or _G.CoreSuite
        if S and S.TitreDeMenu then pcall(S.TitreDeMenu, t)
        elseif NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t) end
        t:Show()
        y = y + 24
    end
    -- Un separateur fin : un libelle a la couleur de sa tranche, suivi d'un
    -- trait de la meme couleur jusqu'au bord.
    local function Separateur(texte, couleur)
        nt = nt + 1
        menu.titres = menu.titres or {}
        local t = menu.titres[nt]
        if not t then
            t = menu.liste:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            menu.titres[nt] = t
        end
        -- Meme police que les zones (jamais plus petite), a la couleur de
        -- sa tranche, et le trait dessous, sur toute la largeur.
        t:SetFontObject("GameFontNormal")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", menu.liste, "TOPLEFT", 12, -(y + 4))
        t:SetText(texte)
        t:SetTextColor(couleur[1], couleur[2], couleur[3])
        t:Show()
        if not t.trait then t.trait = menu.liste:CreateTexture(nil, "ARTWORK") end
        t.trait:ClearAllPoints()
        t.trait:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
        t.trait:SetPoint("RIGHT", menu.liste, "RIGHT", -8, 0)
        t.trait:SetHeight(1)
        t.trait:SetColorTexture(couleur[1], couleur[2], couleur[3], 0.5)
        t.trait:Show()
        y = y + 26
    end
    local function Ligne(texte, case, choisie, auClic, couleur, survol)
        n = n + 1
        local l = LigneMenu(n)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", menu.liste, "TOPLEFT", 0, -y)
        l:SetPoint("RIGHT", menu.liste, "RIGHT", 0, 0)
        l.texte:ClearAllPoints()
        if l.case and case ~= nil then
            l.case:Show()
            l.case:SetChecked(case)
            l.texte:SetPoint("LEFT", l, "LEFT", 22, 0)
        else
            if l.case then l.case:Hide() end
            l.texte:SetPoint("LEFT", l, "LEFT", 10, 0)
        end
        l.texte:SetPoint("RIGHT", l, "RIGHT", -2, 0)
        l.texte:SetText(texte)
        local c = couleur or (choisie and { 1, 0.82, 0 } or { 0.9, 0.9, 0.9 })
        l.texte:SetTextColor(c[1], c[2], c[3])
        l.fond:SetShown(choisie == true)
        l:SetScript("OnClick", auClic)
        l:SetScript("OnEnter", survol)
        l:SetScript("OnLeave", survol and function() GameTooltip:Hide() end or nil)
        l:Show()
        y = y + 23
    end
    -- Onglet Itineraires : a gauche, les itineraires par type puis par zone ;
    -- au centre, ceux du type ou de la zone choisis ; un clic sur l'un d'eux
    -- le guide (ou l'arrete).
    if page.itineraires then
        local L0 = NS.L
        local donnees = page.DonneesItin()
        local filtre = donnees.filtre
        page.choixItin = {}
        Titre(L0.ROUTES_BY_TYPE)
        for _, t in ipairs(donnees.types) do
            local cleT = t.cle
            table.insert(page.choixItin, { type = cleT })
            Ligne("|T" .. t.icone .. ":16|t  " .. t.nom .. "  |cff8c8c8c" .. t.n .. "|r", nil, filtre.type == cleT, function()
                page.filtreItin = { type = cleT }
                page.Rendre()
            end)
        end
        if #donnees.zones > 0 then
            y = y + 8
            Titre(L0.ROUTES_BY_ZONE)
            for _, z in ipairs(donnees.zones) do
                local cleZ = z.nom
                table.insert(page.choixItin, { zone = cleZ })
                Ligne("|TInterface\\Icons\\INV_Misc_Map_01:16|t  " .. z.nom .. "  |cff8c8c8c" .. z.n .. "|r", nil, filtre.zone == cleZ, function()
                    page.filtreItin = { zone = cleZ }
                    page.Rendre()
                end)
            end
        end
        menu.liste:SetHeight(math.max(y, 1))
        return
    end
    -- Affichage, en tete : toujours au meme endroit.
    local r = Reglages()
    Titre(NS.L.OPTIONS)
    Ligne(NS.L.OPT_REVEAL, r.reveler == true, false, function() r.reveler = not r.reveler page.Rendre() end)
    -- Effacer d'un coup les reperes de cette carte : un clic pour demander,
    -- un second pour confirmer (rien ne se recupere).
    local mesReperes = {}
    for _, rp in ipairs(NS.base.Reperes()) do if rp.carte == idCarte then table.insert(mesReperes, rp) end end
    if #mesReperes > 0 then
        local confirmer = page.effacerDemande == idCarte
        Ligne(confirmer and string.format(NS.L.MARKERS_CLEAR_CONFIRM, #mesReperes)
            or string.format(NS.L.MARKERS_CLEAR, #mesReperes), nil, false, function()
            if confirmer then
                for _, rp in ipairs(mesReperes) do NS.base.SupprimerRepere(rp.id) end
                page.effacerDemande = nil
            else
                page.effacerDemande = idCarte
            end
            page.Rendre()
        end, confirmer and { 1, 0.35, 0.3 } or { 0.9, 0.9, 0.9 })
    end
    y = y + 8
    -- Ou aller : une seule couche. On choisit ce qu'on montre (tout, les
    -- quetes, la recolte, ses reperes), puis les destinations les plus
    -- proches ; un clic lance la fleche.
    local L0 = NS.L
    -- Les services affiches sur la carte, les plus proches d'abord.
    local proches = page.ServicesVisibles(idCarte or 0)
    if #proches > 0 then
        local carteJ = CarteDuPerso()
        local jx, jy = carteJ and PositionJoueur(carteJ)
        local wx, wy, wc
        if jx then wx, wy, wc = Yards(carteJ, jx, jy) end
        for _, dst in ipairs(proches) do
            if wx then
                local x, yy, c = Yards(dst.carte, dst.x, dst.y)
                if x and c == wc then dst.distance = math.floor(math.sqrt((x - wx) ^ 2 + (yy - wy) ^ 2) + 0.5) end
            end
        end
        table.sort(proches, function(a, b)
            if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
            if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
            return tostring(a.nom) < tostring(b.nom)
        end)
        y = y + 8
        Titre(L0.SVC_NEAREST)
        for k, dst in ipairs(proches) do
            if k > 5 then break end
            local cible = dst
            local texte = "|T" .. tostring(dst.icone) .. ":14|t " .. tostring(dst.nom)
            if dst.distance then texte = texte .. "  |cff8c8c8c" .. string.format(L0.GO_YARDS, dst.distance) .. "|r" end
            Ligne(texte, nil, false, function() page.GuiderVers(cible) end, { 0.9, 0.9, 0.9 }, function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tostring(cible.nom), 1, 0.82, 0)
                if cible.detail then GameTooltip:AddLine(cible.detail, 1, 1, 1, true) end
                GameTooltip:AddLine(L0.GO_CLICK, 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
        end
    end
    y = y + 8
    -- Recherche : toutes les zones de tous les continents dont le nom
    -- contient le texte tape.
    local function LigneZone(z)
        local id = z.mapID
        local mini, maxi = NiveauxDeZone(id)
        local texte, couleur = "   " .. z.name, nil
        if mini then
            texte = string.format("   [%s] %s", mini == maxi and mini or (mini .. "-" .. maxi), z.name)
            -- La couleur de sa tranche : la ligne et son titre disent pareil.
            couleur = TrancheDeZone(id).couleur
        end
        Ligne(texte, nil, idCarte == id, function()
            carteChoisie = id
            page.Rendre()
        end, couleur)
    end
    local filtre = menu.filtre and string.lower(menu.filtre) or ""
    if filtre ~= "" then
        Titre(NS.L.ZONES)
        local trouvees = {}
        for _, c in ipairs(Enfants(947, 2)) do
            for _, z in ipairs(Enfants(c.mapID, 3, true)) do
                if string.find(string.lower(tostring(z.name)), filtre, 1, true) then table.insert(trouvees, z) end
            end
        end
        table.sort(trouvees, ParNiveau)
        for _, z in ipairs(trouvees) do LigneZone(z) end
        if #trouvees == 0 then Ligne("   " .. NS.L.SEARCH_NONE, nil, false, nil, { 0.6, 0.6, 0.6 }) end
        menu.liste:SetHeight(math.max(y, 1))
        return
    end
    -- Les zones du continent choisi (onglets a droite de la fenetre).
    local continent = continentChoisi or ContinentDe(idCarte)
    if continent then
        Titre(NomDeCarte(continent) or NS.L.ZONES)
        -- Toutes les zones du continent, meme rangees sous une autre carte.
        local zones = Enfants(continent, 3, true)
        table.sort(zones, ParNiveau)
        -- Par tranche de difficulte pour le personnage, comme le journal de
        -- quetes : grises, vertes, jaunes, orange, rouges, puis sans niveau.
        local tranchePrecedente
        for _, z in ipairs(zones) do
            local tranche = TrancheDeZone(z.mapID)
            if tranche ~= tranchePrecedente then
                if tranchePrecedente then y = y + 4 end
                Separateur(tranche.nom(), tranche.couleur)
                tranchePrecedente = tranche
            end
            LigneZone(z)
        end
    end
    menu.liste:SetHeight(math.max(y, 1))
end

-- ---------------------------------------------------------------------------
-- Haut et droite de la fenetre : les personnages en portraits (comme dans
-- CraftCore et QuestCore) et les continents en onglets lateraux.
-- ---------------------------------------------------------------------------

local fenetreMere, persoVu
local TAILLE_PORTRAIT, TAILLE_ONGLET = 30, 34

local function PoserVisage(texture, p)
    texture:SetTexCoord(0, 1, 0, 1)
    if p.moi and SetPortraitTexture and pcall(SetPortraitTexture, texture, "player") then return end
    local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
    if coords then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        return
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function Portrait(parent)
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

-- La barre des personnages : celle de la suite, la meme partout. MapCore
-- y ajoute ou se trouve chaque personnage (infobulle, clic).
local function RendrePortraits()
    local f = fenetreMere
    if not f or not f.entete then return end
    if not f.bandePersos then
        local bande = CreateFrame("Frame", nil, f)
        bande:SetPoint("LEFT", f.entete, "LEFT", 0, 0)
        bande:SetPoint("RIGHT", f.entete, "RIGHT", 0, 0)
        bande:SetHeight(TAILLE_PORTRAIT + 4)
        f.bandePersos = bande
    end
    local bande = f.bandePersos
    local L0 = NS.L
    local S = NS.suite or _G.CoreSuite
    local positions = {}
    local NomC = function(c) return tostring(c):match("^(%S+) %- ") or c end
    for _, p in ipairs(NS.base.Positions and NS.base.Positions() or {}) do positions[NomC(p.cle)] = p end
    local vu = persoVu
    if not vu then for _, p in pairs(positions) do if p.moi then vu = p.cle end end end
    if not vu then vu = NS.ClePersonnage and NS.ClePersonnage() end
    S.BandePersos(bande, { choisi = vu,
        infobulle = function(cle, tip)
            local perso = positions[NomC(cle)]
            if not perso then return end
            local lieu = tostring(perso.zone or "?")
            if perso.sousZone and perso.sousZone ~= "" and perso.sousZone ~= perso.zone then
                lieu = lieu .. ", " .. perso.sousZone
            end
            tip:AddLine(lieu, 1, 1, 1)
            if perso.foyer then tip:AddLine(string.format(L0.CHAR_HEARTH, perso.foyer), 1, 1, 1) end
            if perso.quand and not perso.moi then
                tip:AddLine(string.format(L0.CHAR_SEEN, tostring(NS.Appeler(date, "%d/%m %H:%M", perso.quand) or "?")), 0.6, 0.6, 0.6)
            end
            if perso.carte then tip:AddLine(L0.CHAR_CLICK, 0.6, 0.6, 0.6) end
        end,
        auClic = function(cle)
            persoVu = cle
            local perso = positions[NomC(cle)]
            if perso and perso.carte then carteChoisie, continentChoisi = perso.carte, nil end
            page.Rendre()
        end })
end

-- Icone d'un continent : la teleportation de mage vers une capitale de ce
-- continent, du camp du joueur. Un continent inconnu garde la carte.
local function IconeContinent(id, nom)
    local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
    if id == 1414 then return horde and "Interface\\Icons\\Spell_Arcane_TeleportOrgrimmar" or "Interface\\Icons\\Spell_Arcane_TeleportDarnassus" end
    if id == 1415 then return horde and "Interface\\Icons\\Spell_Arcane_TeleportUnderCity" or "Interface\\Icons\\Spell_Arcane_TeleportStormWind" end
    return "Interface\\Icons\\INV_Misc_Map_01"
end

local function Onglet(f)
    local o = CreateFrame("CheckButton", nil, f)
    o:SetSize(TAILLE_ONGLET, TAILLE_ONGLET)
    local fond = o:CreateTexture(nil, "BACKGROUND")
    fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    do local S = NS.suite or _G.CoreSuite if S and S.TeinteOnglet then S.TeinteOnglet(fond) end end
    fond:SetSize(TAILLE_ONGLET * 2, TAILLE_ONGLET * 2)
    fond:SetPoint("TOPLEFT", -3, 12)
    o.Icon = o:CreateTexture(nil, "ARTWORK")
    o.Icon:SetAllPoints()
    o:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    o:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local halo = o:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    o:SetScript("OnEnter", function(self)
        self.Icon:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.libelle or "")
        GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function(self)
        if not self.choisi then self.Icon:SetVertexColor(0.55, 0.55, 0.55) end
        GameTooltip:Hide()
    end)
    return o
end

local function RendreOnglets(idCarte)
    local f = fenetreMere
    if not f then return end
    f.ongletsContinents = f.ongletsContinents or {}
    local actuel = continentChoisi or ContinentDe(idCarte)
    local precedent
    local S = NS.suite or _G.CoreSuite
    for _, o in ipairs(f.ongletsContinents) do o:Hide() end
    f.ordreContinents = {}
    -- Azeroth, puis ses continents, puis les itineraires.
    local cartes = { { mapID = 947, name = NomDeCarte(947) or "Azeroth", azeroth = true } }
    for _, c in ipairs(Enfants(947, 2)) do table.insert(cartes, c) end
    table.insert(cartes, { mapID = "itin", name = NS.L.TAB_ROUTES, itin = true })
    for rang, c in ipairs(cartes) do
        local o = f.ongletsContinents[rang]
        if not o then o = Onglet(f) f.ongletsContinents[rang] = o end
        local id = c.mapID
        o.libelle, o.id = c.name, id
        o.Icon:SetTexture(c.itin and "Interface\\Icons\\Ability_Hunter_Pathfinding"
            or (c.azeroth and "Interface\\Icons\\INV_Misc_Map02") or IconeContinent(id, c.name))
        if c.itin then o.choisi = page.itineraires == true
        else o.choisi = not page.itineraires and (id == actuel or (c.azeroth and carteChoisie == 947)) end
        o:SetChecked(o.choisi)
        local v = o.choisi and 1 or 0.55
        o.Icon:SetVertexColor(v, v, v)
        o:SetScript("OnClick", function(self)
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            self:SetChecked(self.choisi)
            if c.itin then
                -- Les itineraires : le menu de gauche les montre ; la carte reste.
                page.itineraires = true
            else
                page.itineraires = nil
                continentChoisi, carteChoisie = id, id
            end
            if menu then menu:SetVerticalScroll(0) end
            page.Rendre()
        end)
        o:ClearAllPoints()
        if precedent then
            o:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -((S and S.ECART_ENTRE_ONGLETS) or 14))
        elseif S and S.AncreHaut then
            local ancre, point = S.AncreHaut(f, "droite")
            o:SetPoint("TOPLEFT", ancre, point, 0, S.HAUT_ONGLET or -7)
        else
            o:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -60)
        end
        o:Show()
        table.insert(f.ordreContinents, o)
        precedent = o
    end
end

-- Pour la manette : les portraits, et LT / RT d'un continent a l'autre.
function page.Portraits()
    local liste = {}
    for _, b in ipairs(fenetreMere and fenetreMere.bandePersos and fenetreMere.bandePersos.boutonsSuite or {}) do
        if b:IsShown() then table.insert(liste, b) end
    end
    return liste
end
function page.Toile() return vue and vue.toile end
function page.PersoVoisin(pas)
    local liste = page.Portraits()
    if #liste < 2 then return end
    local rang = 1
    for i, b in ipairs(liste) do if b.halo:IsShown() then rang = i end end
    local cible = liste[math.max(1, math.min(#liste, rang + pas))]
    if cible and cible ~= liste[rang] then cible:Click("LeftButton") end
end
function page.ContinentVoisin(pas)
    local liste = fenetreMere and fenetreMere.ordreContinents or {}
    if #liste == 0 then return end
    local rang = 0
    for i, o in ipairs(liste) do if o.choisi then rang = i end end
    local cible = liste[math.max(1, math.min(#liste, rang + pas))]
    if cible and not cible.choisi then cible:Click("LeftButton") end
end

-- Memoire : on retrouve la carte, le continent, le personnage regarde et le
-- zoom ou on les avait laisses, meme apres /reload.
local restaure = false
local function Memoire()
    local r = Reglages()
    r.memoire = type(r.memoire) == "table" and r.memoire or {}
    return r.memoire
end
local function Restaurer()
    if restaure then return end
    restaure = true
    local m = Memoire()
    carteChoisie, continentChoisi, persoVu = m.carte, m.continent, m.perso
    if m.zoom then
        zoom, decX, decY = m.zoom, m.decX or 0, m.decY or 0
        derniereCarte = carteChoisie or CarteDuPerso()
    end
end
function page.Retenir()
    if not restaure then return end
    local m = Memoire()
    m.carte, m.continent, m.perso = carteChoisie, continentChoisi, persoVu
    m.zoom, m.decX, m.decY = zoom, decX, decY
end

-- ---------------------------------------------------------------------------
-- Plan du donjon : dans une instance, la carte de MapCore montre le plan du
-- donjon (salles, boss, entree, PNJ de quetes, etages), lu dans les donnees
-- du Donjon Journal de Forever. Zoom et glisser comme une carte ; un etage a
-- la fois, choisi par "Etage precedent / suivant". Le personnage n'y est
-- place que si le jeu donne sa position dans ce donjon.
-- ---------------------------------------------------------------------------
local etagePlan = {}
local function PlanCourant()
    if carteChoisie then return nil end
    local S = NS.suite or _G.CoreSuite
    if not (S and S.PlanDuDonjon) then return nil end
    local ok, cle, donnees, nom = pcall(S.PlanDuDonjon)
    if ok and cle and type(donnees) == "table" and type(donnees.floors) == "table" and #donnees.floors > 0 then
        return cle, donnees, nom
    end
    return nil
end

local ICONES_PLAN = {
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    entree = "Interface\\Icons\\INV_Misc_Map_01",
    quete = "Interface\\GossipFrame\\ActiveQuestIcon",
    passage = "Interface\\Icons\\Spell_Arcane_PortalUndercity",
    joueur = "Interface\\WorldMap\\WorldMapArrow",
}
-- Un repere du plan qu'on range : son portrait retourne au journal.
local function RangerPinPlan(b)
    if b.portrait then
        local FDJ = _G.ForeverDungeonJournal_NS
        if type(FDJ) == "table" and FDJ.ReleasePortrait then pcall(FDJ.ReleasePortrait, b.icone) end
        b.portrait = nil
    end
    b:Hide()
end
local function PinPlan(rang)
    vue.pinsPlan = vue.pinsPlan or {}
    local b = vue.pinsPlan[rang]
    if b then return b end
    b = CreateFrame("Frame", nil, vue.toile)
    b:SetSize(20, 20)
    b:SetFrameLevel((vue.toile:GetFrameLevel() or 1) + 5)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    -- Portrait de boss : rond, dans l'anneau d'or du jeu.
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetPoint("TOPLEFT", -5, 5)
    b.anneau:SetPoint("BOTTOMRIGHT", 5, -5)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.anneau:SetTexCoord(0, 0.6, 0, 0.6)
    b.anneau:Hide()
    -- Le nom, lisible sur n'importe quel plan : sur un bandeau sombre.
    b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.nom:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.nom:SetWordWrap(false)
    b.nom:SetShadowOffset(1, -1)
    b.nom:SetShadowColor(0, 0, 0, 1)
    b.fondNom = b:CreateTexture(nil, "BORDER")
    b.fondNom:SetColorTexture(0, 0, 0, 0.72)
    b.fondNom:SetPoint("TOPLEFT", b.nom, "TOPLEFT", -3, 2)
    b.fondNom:SetPoint("BOTTOMRIGHT", b.nom, "BOTTOMRIGHT", 3, -2)
    vue.pinsPlan[rang] = b
    return b
end

-- Pose le plan ; rend largeur, hauteur, etage, nombre d'etages.
local function PoserPlan(cle, d)
    Cacher(vue.toile.tuiles) Cacher(vue.toile.revelees) Cacher(vue.toile.explorees)
    for i = 1, vue.enService do vue.reperes[i]:Hide() end
    vue.enService = 0
    for _, b in ipairs(vue.services or {}) do b:Hide() end
    vue.nServices = 0
    for _, b in ipairs(vue.miens or {}) do b:Hide() if b.zone then b.zone:Hide() end end
    vue.nMiens = 0
    for i = 1, (vue.nLieux or 0) do if vue.lieux[i] then vue.lieux[i]:Hide() end end
    vue.nLieux = 0
    for i = 1, (vue.nPersos or 0) do if vue.persos[i] then vue.persos[i]:Hide() end end
    vue.nPersos = 0
    if vue.clignote then vue.clignote:Hide() end
    if calque then calque.fleche:Hide() for _, t in ipairs(calque.points or {}) do t:Hide() end end
    local n = #d.floors
    -- L'etage ou est le personnage, quand le jeu le dit.
    local ici = NS.Appeler(Lecture("C_Map.GetBestMapForUnit"), "player")
    if not etagePlan[cle] then
        for i, f in ipairs(d.floors) do if f.uiMapID and f.uiMapID == ici then etagePlan[cle] = i end end
    end
    local etage = math.min(math.max(etagePlan[cle] or (d.entrance and d.entrance.floor) or 1, 1), n)
    etagePlan[cle] = etage
    local f = d.floors[etage]
    local L0, H0
    if f.tiles then
        L0, H0 = 1002, 668
        for i = 1, 12 do
            local t = Tuile(vue.toile.tuiles, i)
            t:ClearAllPoints()
            t:SetSize(256, 256)
            t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", ((i - 1) % 4) * 256, -math.floor((i - 1) / 4) * 256)
            t:SetTexture(f.tiles .. i)
            t:SetTexCoord(0, 1, 0, 1)
            t:Show()
        end
    elseif f.texture then
        local droite, bas = f.texRight or 1, f.texBottom or 1
        L0, H0 = 1024 * droite, 1024 * bas
        local t = Tuile(vue.toile.tuiles, 1)
        t:ClearAllPoints()
        t:SetSize(L0, H0)
        t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", 0, 0)
        t:SetTexture(f.texture)
        t:SetTexCoord(0, droite, 0, bas)
        t:Show()
    else
        return nil
    end
    -- Les retouches du journal (symboles de la carte d'origine effaces).
    for k, pa in ipairs(type(f.patches) == "table" and f.patches or {}) do
        local t = Tuile(vue.toile.tuiles, 12 + k, "BORDER")
        t:ClearAllPoints()
        t:SetSize(math.max(1, (pa.x1 - pa.x0) * L0), math.max(1, (pa.y1 - pa.y0) * H0))
        t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", pa.x0 * L0, -pa.y0 * H0)
        t:SetTexture(pa.tex)
        t:SetTexCoord(0, 1, 0, 1)
        t:Show()
    end
    -- Reperes : boss, entree, PNJ de quetes, passages vers un autre etage.
    local rang = 0
    local FDJ = _G.ForeverDungeonJournal_NS
    -- La fiche du boss dans le journal (son portrait), sinon son PNJ.
    local function FicheBoss(mb)
        local dj = type(FDJ) == "table" and type(FDJ.DB) == "table" and FDJ.DB[cle]
        for _, c in ipairs(type(dj) == "table" and type(dj.bosses) == "table" and dj.bosses or {}) do
            if c.name == mb.name then return c end
        end
        if mb.npcID then return { name = mb.name, npcID = mb.npcID } end
        return nil
    end
    local function Poser(genre, x, y, nom, fiche)
        if not (tonumber(x) and tonumber(y)) then return end
        rang = rang + 1
        local b = PinPlan(rang)
        -- Un portrait pris au journal se rend avant de reservir le repere.
        if b.portrait and type(FDJ) == "table" and FDJ.ReleasePortrait then pcall(FDJ.ReleasePortrait, b.icone) end
        b.portrait = nil
        if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "") end
        b.icone:SetTexture(ICONES_PLAN[genre])
        b.icone:SetTexCoord(0, 1, 0, 1)
        b.anneau:Hide()
        local taille = 18
        if genre == "boss" then
            taille = 26
            -- Le vrai portrait du boss, rendu par le Donjon Journal (une simple
            -- texture : le journal ne s'ouvre pas) ; la tete de mort sinon.
            if fiche and type(FDJ) == "table" and type(FDJ.SetBossPortrait) == "function" then
                local ok, oui = pcall(FDJ.SetBossPortrait, b.icone, cle, fiche)
                if ok and oui then
                    b.portrait = true
                    if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
                    b.anneau:Show()
                else
                    b.icone:SetTexture(ICONES_PLAN.boss)
                    b.icone:SetTexCoord(0, 1, 0, 1)
                end
            end
            if type(FDJ) == "table" and FDJ.LocalizeBossName then
                local okN, n = pcall(FDJ.LocalizeBossName, nom)
                if okN and type(n) == "string" and n ~= "" then nom = n end
            end
        end
        b:SetSize(taille, taille)
        b.nom:SetText(nom or "")
        -- Boss en or, le reste en blanc ; bandeau seulement s'il y a un nom.
        if genre == "boss" then b.nom:SetTextColor(1, 0.82, 0) else b.nom:SetTextColor(1, 1, 1) end
        b.fondNom:SetShown((nom or "") ~= "")
        b.ax, b.ay = x, y
        b:Show()
    end
    local surEtage = function(e) return (tonumber(e.floor) or 1) == etage end
    for _, b in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
        if surEtage(b) then Poser("boss", b.x, b.y, b.name, FicheBoss(b)) end
    end
    if type(d.entrance) == "table" and surEtage(d.entrance) then Poser("entree", d.entrance.x, d.entrance.y, L.PLAN_ENTRANCE) end
    for _, q in ipairs(type(d.turnins) == "table" and d.turnins or {}) do
        if surEtage(q) then Poser("quete", q.x, q.y, q.npc) end
    end
    for _, tr in ipairs(type(d.transitions) == "table" and d.transitions or {}) do
        if surEtage(tr) and tr.to then Poser("passage", tr.x, tr.y, string.format(L.PLAN_FLOOR_TO, tr.to)) end
    end
    -- Le personnage, si le jeu donne sa position sur cet etage.
    if f.uiMapID and f.uiMapID == ici then
        local pos = NS.Appeler(Lecture("C_Map.GetPlayerMapPosition"), f.uiMapID, "player")
        local okXY, x, y = false, nil, nil
        if type(pos) == "table" and pos.GetXY then okXY, x, y = pcall(pos.GetXY, pos) end
        local secret = _G.issecretvalue
        if okXY and x and y and not (secret and (secret(x) or secret(y))) and x > 0 then
            Poser("joueur", x, y, "")
            local b = vue.pinsPlan[rang]
            local cap = NS.Appeler(Lecture("GetPlayerFacing"))
            if cap and b.icone.SetRotation then pcall(b.icone.SetRotation, b.icone, cap) end
        end
    end
    for i = rang + 1, #(vue.pinsPlan or {}) do RangerPinPlan(vue.pinsPlan[i]) end
    vue.nPlan = rang
    return L0, H0, etage, n
end

local function RendrePlan(cle, d, nom)
    local L0, H0, etage, n = PoserPlan(cle, d)
    if not L0 then return false end
    vue.idCarte = nil
    vue.plan = cle
    vue.titre:SetText((nom or cle) .. (n > 1 and ("  " .. string.format(L.PLAN_FLOOR, etage, n)) or ""))
    -- Etages : precedent et suivant, a la place de "Voir ..." et "Revenir".
    vue.remonter:SetShown(n > 1)
    vue.allerA:SetShown(n > 1)
    if n > 1 then
        vue.remonter:SetText(L.PLAN_FLOOR_PREV)
        vue.remonter:SetWidth((vue.remonter.GetTextWidth and vue.remonter:GetTextWidth() or 100) + 24)
        vue.remonter:SetEnabled(etage > 1)
        vue.allerA:SetText(L.PLAN_FLOOR_NEXT)
        vue.allerA:SetWidth((vue.allerA.GetTextWidth and vue.allerA:GetTextWidth() or 100) + 24)
        vue.allerA:SetEnabled(etage < n)
        vue.allerA:SetScript("OnClick", function()
            etagePlan[cle] = math.min(n, (etagePlan[cle] or 1) + 1)
            zoom, decX, decY = 1, 0, 0
            page.Rendre()
        end)
    end
    -- L'outil de donjon choisi : un bouton, rien ne s'ouvre sans ce clic.
    local S = NS.suite or _G.CoreSuite
    local o, nb
    if S and S.OutilDonjon then o, nb = S.OutilDonjon() end
    if o then
        vue.outil:SetText(string.format(L.PLAN_TOOL_OPEN, o.nom))
        vue.outil:SetWidth((vue.outil.GetTextWidth and vue.outil:GetTextWidth() or 100) + 24)
        vue.outil:Show()
        vue.outilChanger:SetShown((nb or 0) > 1)
    else
        vue.outil:Hide()
        vue.outilChanger:Hide()
    end
    vue.vide:Hide()
    if derniereCarte ~= "plan:" .. cle then zoom, decX, decY = 1, 0, 0 derniereCarte = "plan:" .. cle end
    vue.largeur, vue.hauteur = L0, H0
    vue.toile:SetSize(L0, H0)
    Disposer()
    return true
end
-- Le clic explicite du joueur (bouton ou Y a la manette) : seul chemin vers
-- l'outil de donjon d'un autre add-on.
function page.OuvrirOutilDonjon()
    if not (vue and vue.plan) then return false end
    local S = NS.suite or _G.CoreSuite
    if not (S and S.OuvrirOutilDonjon) then return false end
    return S.OuvrirOutilDonjon(vue.plan)
end
function page.EnPlan() return vue ~= nil and vue.plan ~= nil end
page.EtagePrecedent = function()
    if vue and vue.plan then
        etagePlan[vue.plan] = math.max(1, (etagePlan[vue.plan] or 1) - 1)
        zoom, decX, decY = 1, 0, 0
        page.Rendre()
        return true
    end
    return false
end

function page.Rendre(parent, basDroite, menuParent, menuHaut, mere)
    if mere then fenetreMere = mere end
    Restaurer()
    if not vue then
        if not parent then return end
        Construire(parent, basDroite)
    end
    if not menu and menuParent then
        -- Le menu defile : un continent compte plus de zones que la hauteur.
        -- Defile a la molette, sans ascenseur : meme largeur que les autres menus.
        -- Recherche d'une zone par son nom, au-dessus du menu.
        local okR, recherche = pcall(CreateFrame, "EditBox", nil, menuParent, "SearchBoxTemplate")
        if not okR or not recherche then recherche = CreateFrame("EditBox", nil, menuParent, "InputBoxTemplate") end
        -- Plus de champ de recherche : le menu commence tout en haut.
        recherche:Hide()
        recherche:SetHeight(20)
        recherche:SetPoint("TOPLEFT", menuParent, "TOPLEFT", 8, 0)
        recherche:SetPoint("RIGHT", menuParent, "RIGHT", -4, 0)
        recherche:SetAutoFocus(false)
        if recherche.Instructions then recherche.Instructions:SetText(NS.L.SEARCH_ZONE) end
        recherche:HookScript("OnTextChanged", function(self)
            if not menu then return end
            menu.filtre = self:GetText() or ""
            menu:SetVerticalScroll(0)
            RendreMenu(vue and vue.idCarte)
        end)
        recherche:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
        recherche:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        menu = CreateFrame("ScrollFrame", nil, menuParent)
        menu.recherche = recherche
        menu:SetPoint("TOPLEFT", menuParent, "TOPLEFT", 0, 0)
        menu:SetPoint("BOTTOMRIGHT", menuParent, "BOTTOMRIGHT", 0, 0)
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, sens)
            local maxi = math.max(0, (self.liste:GetHeight() or 0) - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.max(0, math.min(maxi, (self:GetVerticalScroll() or 0) - sens * 40)))
        end)
        menu.liste = CreateFrame("Frame", nil, menu)
        menu.liste:SetSize(menuParent:GetWidth() or 170, 1)
        menu:SetScrollChild(menu.liste)
    end
    vue:Show()
    -- A la creation la vue est deja visible : son OnShow ne part pas, et le
    -- calque (fleche du personnage, trajet) restait cache.
    if calque and vue:IsVisible() then calque:Show() end
    if menu then menu:Show() end
    local idCarte = carteChoisie or CarteDuPerso()
    if idCarte ~= derniereCarte then zoom, decX, decY = 1, 0, 0 derniereCarte = idCarte end
    vue.idCarte = idCarte
    vue.titre:SetText(idCarte and NomDeCarte(idCarte) or L.TITLE)
    -- Le nom de la zone, le meme dans QuestCore et MapCore : encre sur le
    -- parchemin, or sur le fond sombre.
    if NS.charte.Fond() == "parchemin" then
        vue.titre:SetTextColor(0.14, 0.08, 0.03)
        vue.titre:SetShadowColor(0, 0, 0, 0)
    else
        vue.titre:SetTextColor(1, 0.82, 0)
        vue.titre:SetShadowColor(0, 0, 0, 1)
    end
    RendreMenu(idCarte)
    pcall(page.RendrePanneauItin)
    pcall(RendrePortraits)
    pcall(RendreOnglets, idCarte)
    if NS.fenetre and NS.fenetre.ApresRendu then pcall(NS.fenetre.ApresRendu) end
    -- Dans un donjon qui a un plan : le plan, a la place de la carte.
    vue.plan = nil
    local cleP, donneesP, nomP = PlanCourant()
    if cleP and RendrePlan(cleP, donneesP, nomP) then return end
    for _, pin in ipairs(vue.pinsPlan or {}) do RangerPinPlan(pin) end
    vue.nPlan = 0
    vue.outil:Hide()
    vue.outilChanger:Hide()
    vue.remonter:SetEnabled(true)
    vue.allerA:SetEnabled(true)
    -- L'echelon du dessus, nomme : "Voir Dun Morogh".
    local parent = CarteParente(idCarte)
    if parent then
        vue.remonter:SetText(string.format(NS.L.MAP_UP, NomDeCarte(parent) or "?"))
        vue.remonter:SetWidth((vue.remonter.GetTextWidth and vue.remonter:GetTextWidth() or 100) + 24)
        vue.remonter:Show()
    else
        vue.remonter:Hide()
    end
    -- Ailleurs que chez soi : un bouton pour revenir a sa position.
    if carteChoisie then
        vue.allerA:SetText(NS.L.BACK_HERE)
        vue.allerA:SetWidth((vue.allerA.GetTextWidth and vue.allerA:GetTextWidth() or 120) + 24)
        vue.allerA:SetScript("OnClick", function()
            carteChoisie, continentChoisi = nil, nil
            page.Rendre()
        end)
        vue.allerA:Show()
    else
        vue.allerA:Hide()
    end
    local largeur, hauteur
    if idCarte then largeur, hauteur = PoserFond(idCarte) end
    vue.compte = {}
    if not largeur then
        Cacher(vue.toile.tuiles) Cacher(vue.toile.revelees) Cacher(vue.toile.explorees)
        for i = 1, vue.enService do vue.reperes[i]:Hide() end
        vue.enService = 0
        for _, b in ipairs(vue.services or {}) do b:Hide() end
        vue.nServices = 0
        if calque then calque.fleche:Hide() for _, t in ipairs(calque.points or {}) do t:Hide() end end
        vue.vide:SetText(L.NO_MAP)
        vue.vide:Show()
        vue.largeur = nil
        return
    end
    vue.vide:Hide()
    vue.largeur, vue.hauteur = largeur, hauteur
    vue.toile:SetSize(largeur, hauteur)
    vue.compte.revelees = PoserRevelees(idCarte)
    vue.compte.explorees = PoserExplorees(idCarte)
    local okR, souciR = pcall(PoserReperes, idCarte)
    if not okR then NS.base.NoterIncident("reperes", souciR) end
    pcall(PoserServices, idCarte)
    pcall(page.PoserClignote, idCarte)
    Disposer()
end

function page.Cacher()
    if vue then vue:Hide() end
    if menu then menu:Hide() end
end


-- ---------------------------------------------------------------------------
-- Modifier un repere : note, icone, zone entouree
-- ---------------------------------------------------------------------------

local editeur

local function ConstruireEditeur()
    local ok, f = pcall(CreateFrame, "Frame", nil, vue, "BackdropTemplate")
    f = ok and f or CreateFrame("Frame", nil, vue)
    f:SetSize(380, 214)
    f:SetPoint("CENTER", vue.bord, "CENTER", 0, 0)
    f:SetFrameLevel(vue.toile:GetFrameLevel() + 60)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    local MARGE = 24
    f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.titre:SetPoint("TOP", f, "TOP", 0, -18)
    f.titre:SetText(NS.L.MARKER)

    local libelle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    libelle:SetPoint("TOPLEFT", f, "TOPLEFT", MARGE, -48)
    libelle:SetText(NS.L.NOTE)
    local okS, saisie = pcall(CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
    saisie = okS and saisie or CreateFrame("EditBox", nil, f)
    saisie:SetHeight(20)
    saisie:SetPoint("LEFT", libelle, "RIGHT", 14, 0)
    saisie:SetPoint("RIGHT", f, "RIGHT", -MARGE, 0)
    saisie:SetAutoFocus(false)
    saisie:SetMaxLetters(120)
    saisie:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    saisie:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.saisie = saisie

    -- Les huit icones de cible du jeu, reparties sur la largeur.
    f.icones = {}
    local largeurUtile = 380 - 2 * MARGE
    local pas = (largeurUtile - 24) / 7
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(24, 24)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", MARGE + (i - 1) * pas, -80)
        b.t = b:CreateTexture(nil, "ARTWORK")
        b.t:SetAllPoints()
        b.t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        b.t:SetTexCoord(page.CoordsIcone(i))
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() f.icone = i page.MarquerEditeur() end)
        f.icones[i] = b
    end

    -- Zone entouree : aucune, petite, moyenne, grande.
    local zone = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zone:SetPoint("TOPLEFT", f, "TOPLEFT", MARGE, -118)
    zone:SetText(NS.L.CIRCLE)
    f.rayons = {}
    local largeurB = (largeurUtile - 3 * 6) / 4
    for rang, texte in ipairs({ NS.L.CIRCLE_NONE, NS.L.CIRCLE_S, NS.L.CIRCLE_M, NS.L.CIRCLE_L }) do
        local b = Bouton(f, texte, largeurB)
        b:SetWidth(largeurB)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", MARGE + (rang - 1) * (largeurB + 6), -136)
        b:SetScript("OnClick", function() f.rayon = rang - 1 page.MarquerEditeur() end)
        f.rayons[rang] = b
    end

    local largeurP = (largeurUtile - 2 * 6) / 3
    local fermer = Bouton(f, NS.L.CLOSE, largeurP)
    fermer:SetWidth(largeurP)
    fermer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MARGE, 20)
    -- Fermer sans enregistrer : un nouveau repere n'est pas garde.
    fermer:SetScript("OnClick", function() f:Hide() page.Rendre() end)
    local supprimer = Bouton(f, NS.L.DELETE, largeurP)
    supprimer:SetWidth(largeurP)
    supprimer:SetPoint("LEFT", fermer, "RIGHT", 6, 0)
    supprimer:SetScript("OnClick", function()
        if f.repere and not f.repere.nouveau then NS.base.SupprimerRepere(f.repere.id) end
        f:Hide()
        page.Rendre()
    end)
    f.supprimer = supprimer
    local enregistrer = Bouton(f, NS.L.SAVE, largeurP)
    enregistrer:SetWidth(largeurP)
    enregistrer:SetPoint("LEFT", supprimer, "RIGHT", 6, 0)
    enregistrer:SetScript("OnClick", function()
        local r = f.repere
        if r then
            if r.nouveau then r = NS.base.NouveauRepere(r.carte, r.x, r.y) end
            r.note = f.saisie:GetText() or ""
            r.icone, r.rayon = f.icone or 1, f.rayon or 0
        end
        f:Hide()
        page.Rendre()
    end)
    -- Apercu du brouillon, la ou l'on a clique.
    f.apercu = vue.toile:CreateTexture(nil, "OVERLAY", nil, 6)
    f.apercu:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.apercu:Hide()
    f:SetScript("OnHide", function(self) self.apercu:Hide() self.repere = nil end)
    f:Hide()
    return f
end

function page.MarquerEditeur()
    if not editeur then return end
    for i, b in ipairs(editeur.icones) do
        b.t:SetDesaturated(i ~= editeur.icone)
        b.t:SetAlpha(i == editeur.icone and 1 or 0.45)
    end
    for rang, b in ipairs(editeur.rayons) do b:SetEnabled((rang - 1) ~= editeur.rayon) end
    local r = editeur.repere
    editeur.supprimer:SetEnabled(r ~= nil and not r.nouveau)
    -- L'apercu du nouveau repere suit l'icone choisie.
    if r and r.nouveau and vue.largeur and vue.echelle then
        local a = editeur.apercu
        a:SetTexCoord(page.CoordsIcone(editeur.icone or 1))
        a:SetSize(20 / vue.echelle, 20 / vue.echelle)
        a:ClearAllPoints()
        a:SetPoint("CENTER", vue.toile, "TOPLEFT", r.x * vue.largeur, -r.y * vue.hauteur)
        a:Show()
    else
        editeur.apercu:Hide()
    end
end

function page.Editer(r)
    if not vue or not r then return end
    editeur = editeur or ConstruireEditeur()
    editeur.repere = r
    editeur.icone, editeur.rayon = r.icone or 1, r.rayon or 0
    editeur.saisie:SetText(r.note or "")
    page.MarquerEditeur()
    editeur:Show()
end

-- Reglages de MapCore dans Options, Add-ons, Forever SagaCore.
do
    _G.SagaCoreOptions = type(_G.SagaCoreOptions) == "table" and _G.SagaCoreOptions or {}
    _G.SagaCoreOptions.MapCore = { titre = "MapCore", ordre = 3, elements = function()
        return {
            { "section", NS.L.OPTIONS },
            { "case", NS.L.OPT_REVEAL, function() return Reglages().reveler end,
              function(v) Reglages().reveler = v pcall(page.Rendre) end },
        }
    end }
end
