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
-- du plus proche au suivant, puis guides par la fleche de la suite. Une
-- tournee tourne en boucle : une fois tous les lieux visites, on recommence
-- (les noeuds repoussent).
-- ---------------------------------------------------------------------------

local function Tournee()
    local r = Reglages()
    r.tournee = type(r.tournee) == "table" and r.tournee or { points = {}, faits = {} }
    r.tournee.points = r.tournee.points or {}
    r.tournee.faits = r.tournee.faits or {}
    return r.tournee
end
page.Tournee = Tournee

local function CleLieu(l) return tostring(l.objet) .. ":" .. tostring(l.x) .. ":" .. tostring(l.y) end

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
    if t.carte ~= vue.idCarte then t.carte, t.points, t.faits = vue.idCarte, {}, {} end
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
    t.faits = {}
    Ordonner()
    page.Rendre()
end

function page.EffacerTournee()
    local S = NS.suite or _G.CoreSuite
    if S and S.ArreterGuidage then S.ArreterGuidage("MapCore") end
    local r = Reglages()
    r.tournee = nil
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
        local c = page.cibleGuidee
        if c and c.carte == vue.idCarte and c.x and c.y and S and S.GuidageActif and S.GuidageActif() then
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
        if not t.faits[CleLieu(p)] then table.insert(chemin, { p.x, p.y }) end
    end
    local rang = 0
    for i = 2, #chemin do
        local ax, ay = VersCalque(chemin[i - 1][1], chemin[i - 1][2])
        local bx, by = VersCalque(chemin[i][1], chemin[i][2])
        rang = Pointilles(rang, ax, ay, bx, by, COULEUR_TOURNEE, i == 2 and 7 or 5, 0.95)
    end
end

-- Guidage : le lieu non visite le plus proche ; arrive a moins de 12 m, il
-- est visite. Tous visites : la tournee recommence.
local fournisseur = {
    Cible = function()
        local t = Tournee()
        if not t.carte or #t.points == 0 then return nil, "fini" end
        local x, y = PositionJoueur(t.carte)
        local meilleur, cible
        local restants = 0
        for _, p in ipairs(t.points) do
            if not t.faits[CleLieu(p)] then
                restants = restants + 1
                local d = x and ((p.x - x) ^ 2 + (p.y - y) ^ 2) or 0
                if not meilleur or d < meilleur then meilleur, cible = d, p end
            end
        end
        if not cible then
            t.faits = {}
            return nil
        end
        local cc = _G.CraftCoreAPI
        local nom = cc and cc.Objet and cc.Objet(cible.objet)
        return { carte = t.carte, x = cible.x, y = cible.y, qui = nom, cle = CleLieu(cible),
            rang = #t.points - restants + 1, total = #t.points, titre = NS.L.FARM_TITLE }
    end,
    Arrivee = function(cible)
        local t = Tournee()
        if cible.cle and not t.faits[cible.cle] then
            t.faits[cible.cle] = true
            pcall(page.Rendre)
        end
    end,
    Clic = function() if NS.fenetre and NS.fenetre.Basculer then NS.fenetre.Basculer() end end,
    AideClic = NS.L.FARM_CLICK,
    Fin = function() pcall(page.Rendre) end,
}

function page.Guider(oui)
    if NS.Trace then NS.Trace("guidage tournee : " .. tostring(oui)) end
    local S = NS.suite or _G.CoreSuite
    if not (S and S.Guider) then return end
    if oui == nil then oui = not S.GuidageActif("MapCore") end
    if oui then
        Tournee().faits = {}
        Ordonner()
        fournisseur.carte = false
        S.Guider("MapCore", fournisseur)
    else
        S.ArreterGuidage("MapCore")
    end
    pcall(page.Rendre)
end

function page.EnGuidage()
    local S = NS.suite or _G.CoreSuite
    return S and S.GuidageActif and S.GuidageActif("MapCore") or false
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
    -- Recalcule seulement si le zoom ou les reperes changent (pas en glissant).
    local morceaux = { string.format("%.4f", echelle) }
    for _, e in ipairs(poses) do morceaux[#morceaux + 1] = string.format("%.3f,%.3f", e.b.ax, e.b.ay) end
    local cle = table.concat(morceaux, ":")
    if cle ~= vue.cleEcart then
        vue.cleEcart = cle
        local Suite = NS.suite or _G.CoreSuite
        if Suite and Suite.Ecarter then pcall(Suite.Ecarter, poses, 22) end
        for _, e in ipairs(poses) do e.b.ecartX, e.b.ecartY = e.dx or 0, e.dy or 0 end
    end
    for _, e in ipairs(poses) do
        e.b:ClearAllPoints()
        e.b:SetPoint("CENTER", vue.toile, "TOPLEFT", e.x + (e.b.ecartX or 0), -(e.y + (e.b.ecartY or 0)))
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
            local fait = rangT and Tournee().faits[CleLieu(l)]
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

local function Enfants(carte, genre)
    local liste = NS.Appeler(Lecture("C_Map.GetMapChildrenInfo"), carte, genre)
    return type(liste) == "table" and liste or {}
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
    l:SetHeight(18)
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
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

-- La fleche de la suite vers une destination ; arrive, elle s'arrete.
function page.GuiderVers(dst)
    local S = NS.suite or _G.CoreSuite
    if not (S and S.Guider and dst) then return end
    local point = { carte = dst.carte, x = dst.x, y = dst.y, titre = NS.L.GO_TITLE, qui = dst.nom }
    page.cibleGuidee = dst
    S.Guider("MapCore", {
        carte = false,
        Cible = function() return point end,
        Arrivee = function()
            local plusTard = NS.Lecture("C_Timer.After")
            if plusTard then plusTard(0, function() S.ArreterGuidage("MapCore") end) end
        end,
        Clic = function() if NS.fenetre and NS.fenetre.Basculer then NS.fenetre.Basculer() end end,
        -- Arrive ou arrete : la fleche s'en va, l'icone continue de clignoter
        -- jusqu'au prochain choix ou a la fermeture de la fenetre.
        Fin = function() end,
    })
    pcall(page.Rendre)
end

local function RendreMenu(idCarte)
    if not menu then return end
    for _, l in ipairs(menu.lignes or {}) do l:Hide() end
    for _, t in ipairs(menu.titres or {}) do t:Hide() end
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
        -- La police des titres de la suite.
        if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t) end
        t:Show()
        y = y + 24
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
        y = y + 19
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
    -- (Ou aller : retire du menu, jugé confus. Gardé ici, désactivé.)
    if false then
    Titre(L0.GO_TITLE)
    local actuel = page.ModeAffiche()
    for _, m in ipairs(page.MODES) do
        local mode = m
        Ligne(L0[m.libelle], actuel == m.cle, false, function()
            page.PoserMode(mode.cle)
            page.Rendre()
        end)
    end
    y = y + 4
    local destinations = page.Destinations(idCarte)
    if #destinations == 0 then
        Ligne(L0.GO_NONE, nil, false, nil, { 0.6, 0.6, 0.6 })
    end
    for k, dst in ipairs(destinations) do
        if k > 7 then break end
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
    -- Itineraires de toute la suite, en un coup d'oeil : le trajet de quetes
    -- (QuestCore), le circuit de recolte de ce qui manque (CraftCore) et la
    -- tournee de recolte (MapCore). Chacun garde son add-on ; ici on les voit,
    -- on lance ou arrete leur guidage, on ouvre l'add-on concerne.
    local Suite = NS.suite or _G.CoreSuite
    local L = NS.L
    -- (Itineraires : retire du menu, juge hors de propos ici. Garde, desactive.)
    if false then
    Titre(L.ROUTES_TITLE)
    local GRIS, BLANC = { 0.6, 0.6, 0.6 }, { 0.9, 0.9, 0.9 }
    local function Guidage(actif, basculer)
        Ligne(actif and L.ROUTES_STOP or L.ROUTES_GUIDE, nil, false, function()
            pcall(basculer)
            page.Rendre()
        end, COULEUR_TOURNEE)
    end
    local function Ouvrir(cle)
        Ligne(string.format(L.ROUTES_OPEN, cle), nil, false, function()
            if Suite and Suite.Ouvrir then pcall(Suite.Ouvrir, cle) end
        end, GRIS)
    end
    local aucun = true
    local qc = _G.QuestCoreAPI
    local okQ, cq = false, nil
    if qc and qc.Circuit then okQ, cq = pcall(qc.Circuit) end
    if okQ and cq then
        aucun = false
        Ligne(string.format(L.ROUTES_QUESTS, cq.reste, cq.total), nil, cq.guide == true, nil, BLANC)
        Guidage(cq.guide, function() qc.Guider(not cq.guide) end)
        Ouvrir("QuestCore")
        y = y + 4
    end
    local cc = _G.CraftCoreAPI
    local okC, cr = false, nil
    if cc and cc.CircuitRecolte then okC, cr = pcall(cc.CircuitRecolte) end
    if okC and cr then
        aucun = false
        Ligne(string.format(L.ROUTES_GATHER, cr.matieres, cr.lieux), nil, cr.guide == true, nil, BLANC)
        Guidage(cr.guide, function() cc.GuiderRecolte(not cr.guide) end)
        Ouvrir("CraftCore")
        y = y + 4
    end
    local t = Tournee()
    local nT = (t.carte == idCarte) and #t.points or 0
    if nT > 0 then
        aucun = false
        Ligne(string.format(L.ROUTES_FARM, nT), nil, page.EnGuidage(), nil, BLANC)
        Guidage(page.EnGuidage(), function() page.Guider() end)
        Ligne(L.FARM_CLEAR, nil, false, function() page.EffacerTournee() end, GRIS)
        y = y + 4
    end
    if aucun then Ligne(L.ROUTES_NONE, nil, false, nil, GRIS) end
    if nT == 0 then Ligne(L.FARM_HELP, nil, false, nil, GRIS) end
    y = y + 8
    end
    -- Recherche : toutes les zones de tous les continents dont le nom
    -- contient le texte tape.
    local function LigneZone(z)
        local id = z.mapID
        local mini, maxi = NiveauxDeZone(id)
        local texte, couleur = "   " .. z.name, nil
        if mini then
            texte = string.format("   [%s] %s", mini == maxi and mini or (mini .. "-" .. maxi), z.name)
            couleur = CouleurDeNiveau(math.floor((mini + maxi) / 2))
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
            for _, z in ipairs(Enfants(c.mapID, 3)) do
                if string.find(string.lower(tostring(z.name)), filtre, 1, true) then table.insert(trouvees, z) end
            end
        end
        table.sort(trouvees, function(a, b) return tostring(a.name) < tostring(b.name) end)
        for _, z in ipairs(trouvees) do LigneZone(z) end
        if #trouvees == 0 then Ligne("   " .. NS.L.SEARCH_NONE, nil, false, nil, { 0.6, 0.6, 0.6 }) end
        menu.liste:SetHeight(math.max(y, 1))
        return
    end
    -- Les zones du continent choisi (onglets a droite de la fenetre).
    local continent = continentChoisi or ContinentDe(idCarte)
    if continent then
        Titre(NomDeCarte(continent) or NS.L.ZONES)
        local zones = Enfants(continent, 3)
        table.sort(zones, function(a, b) return tostring(a.name) < tostring(b.name) end)
        for _, z in ipairs(zones) do LigneZone(z) end
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

local function RendrePortraits()
    local f = fenetreMere
    if not f or not f.entete then return end
    if not f.bandePersos then
        local bande = CreateFrame("Frame", nil, f)
        bande:SetPoint("LEFT", f.entete, "LEFT", 0, 0)
        bande:SetPoint("RIGHT", f.entete, "RIGHT", 0, 0)
        bande:SetHeight(TAILLE_PORTRAIT + 4)
        bande.boutons = {}
        f.bandePersos = bande
    end
    local bande = f.bandePersos
    local L0 = NS.L
    local S = NS.suite or _G.CoreSuite
    local liste = {}
    for _, p in ipairs(NS.base.Positions and NS.base.Positions() or {}) do
        if not (S and S.Visible) or S.Visible(p.cle) then table.insert(liste, p) end
    end
    for _, b in ipairs(bande.boutons) do b:Hide() end
    local vu = persoVu
    if not vu then for _, p in ipairs(liste) do if p.moi then vu = p.cle end end end
    for rang, p in ipairs(liste) do
        local b = bande.boutons[rang]
        if not b then b = Portrait(bande) bande.boutons[rang] = b end
        b:ClearAllPoints()
        b:SetPoint("LEFT", bande, "LEFT", 2 + (rang - 1) * (TAILLE_PORTRAIT + 6), 0)
        PoserVisage(b.visage, p)
        b.halo:SetShown(p.cle == vu)
        b:SetAlpha(p.cle == vu and 1 or 0.7)
        local perso = p
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local couleur = _G.RAID_CLASS_COLORS and perso.classe and _G.RAID_CLASS_COLORS[perso.classe]
            GameTooltip:SetText(NS.NomCourt(perso.cle) .. (perso.niveau and ("  " .. string.format(L0.CHAR_LVL, perso.niveau)) or ""),
                couleur and couleur.r or 1, couleur and couleur.g or 0.82, couleur and couleur.b or 0)
            local lieu = tostring(perso.zone or "?")
            if perso.sousZone and perso.sousZone ~= "" and perso.sousZone ~= perso.zone then
                lieu = lieu .. ", " .. perso.sousZone
            end
            GameTooltip:AddLine(lieu, 1, 1, 1)
            if perso.foyer then GameTooltip:AddLine(string.format(L0.CHAR_HEARTH, perso.foyer), 1, 1, 1) end
            if perso.quand and not perso.moi then
                GameTooltip:AddLine(string.format(L0.CHAR_SEEN, tostring(NS.Appeler(date, "%d/%m %H:%M", perso.quand) or "?")), 0.6, 0.6, 0.6)
            end
            if perso.carte then GameTooltip:AddLine(L0.CHAR_CLICK, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:SetScript("OnClick", function()
            persoVu = perso.cle
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            if perso.carte then carteChoisie, continentChoisi = perso.carte, nil end
            page.Rendre()
        end)
        b:Show()
    end
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
    for rang, c in ipairs(Enfants(947, 2)) do
        local o = f.ongletsContinents[rang]
        if not o then o = Onglet(f) f.ongletsContinents[rang] = o end
        local id = c.mapID
        o.libelle, o.id = c.name, id
        o.Icon:SetTexture(IconeContinent(id, c.name))
        o.choisi = (id == actuel)
        o:SetChecked(o.choisi)
        local v = o.choisi and 1 or 0.55
        o.Icon:SetVertexColor(v, v, v)
        o:SetScript("OnClick", function(self)
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            self:SetChecked(self.choisi)
            continentChoisi, carteChoisie = id, id
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
    for _, b in ipairs(fenetreMere and fenetreMere.bandePersos and fenetreMere.bandePersos.boutons or {}) do
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
        menu:SetPoint("TOPLEFT", menuParent, "TOPLEFT", 0, -28)
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
        vue.titre:SetTextColor(0.42, 0.18, 0.02)
        vue.titre:SetShadowColor(0, 0, 0, 0)
    else
        vue.titre:SetTextColor(1, 0.82, 0)
        vue.titre:SetShadowColor(0, 0, 0, 1)
    end
    RendreMenu(idCarte)
    pcall(RendrePortraits)
    pcall(RendreOnglets, idCarte)
    if NS.fenetre and NS.fenetre.ApresRendu then pcall(NS.fenetre.ApresRendu) end
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
