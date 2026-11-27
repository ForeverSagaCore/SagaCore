local _, NS = ...

-- Reperes de quetes, pour la page Carte de QuestCore.
--
-- Pour chaque quete en cours du personnage connecte :
--   a rendre      l'icone de quete a rendre du journal, sur celui qui la reprend ;
--   en cours      l'icone de quete en cours du journal, la ou se font les
--                 objectifs (creatures, objets, lieux), jamais pour un objectif
--                 deja rempli.
--
-- Les icones sont celles du journal de quetes du jeu, les memes que dans le
-- suivi. Les reperes sont de simples cadres : aucun modele protege du jeu
-- (celui des reperes de quete bloquait l'add-on).
-- Positions : base QuestieDB, en pourcentage de la carte de la zone.

NS.carte = {}
local carte = NS.carte
local L = NS.L

local TAILLE = 22
local CELLULE = 3          -- deux points a moins de 3 % l'un de l'autre n'en font qu'un
local MAX_PAR_OBJECTIF = 25

local PointsDePrise, Reporter
local versCarte              -- AreaID -> UiMapID, tire de QuestieDB

-- ---------------------------------------------------------------------------
-- Correspondance zone de la base -> carte du jeu
-- ---------------------------------------------------------------------------

local function TableDesCartes()
    if versCarte then return versCarte end
    versCarte = {}
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local prive = support and support.private
    for _, champ in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local brut = prive and prive[champ]
        local t = brut
        if type(brut) == "string" then
            local fn = loadstring(brut)
            local ok, rendu = false, nil
            if fn then ok, rendu = pcall(fn) end
            t = ok and rendu or nil
        end
        if type(t) == "table" then
            for zone, idCarte in pairs(t) do versCarte[zone] = idCarte end
        end
    end
    return versCarte
end

function carte.CarteDeZone(zone)
    local idCarte = TableDesCartes()[zone]
    if idCarte and idCarte > 0 then return idCarte end
    -- Sans Questie : la carte gardee par la base personnelle.
    idCarte = NS.memoire and NS.memoire.Carte and NS.memoire.Carte(zone)
    if idCarte and idCarte > 0 then return idCarte end
    return nil
end

-- Cartes d'instance (donjons, raids de la base) et leur entree dehors.
local instances
local function Instances()
    if instances then return instances end
    local t = {}
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local brut = support and support.private and support.private.dungeons
    if type(brut) == "string" then
        local fn = loadstring(brut)
        local ok, r = false, nil
        if fn then ok, r = pcall(fn) end
        brut = ok and r or nil
    end
    if type(brut) ~= "table" then return t end
    -- Cartes de dehors : celles des entrees et des zones parentes. Une
    -- sous-zone d'un donjon peut tomber sur la carte de sa zone (les Tarides
    -- pour Kraal de Tranchebauge) : celle-la n'est jamais une instance.
    local dehors = {}
    for _, d in pairs(brut) do
        if type(d) == "table" then
            local c = tonumber(d[3]) and carte.CarteDeZone(d[3])
            if c then dehors[c] = true end
            for _, e in ipairs(type(d[4]) == "table" and d[4] or {}) do
                local ce = type(e) == "table" and carte.CarteDeZone(e[1])
                if ce then dehors[ce] = true end
            end
        end
    end
    local function Dehors(c)
        if dehors[c] then return true end
        local info = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), c)
        -- Monde, continent, zone : jamais une instance.
        return type(info) == "table" and tonumber(info.mapType) ~= nil and info.mapType <= 3
    end
    for zone, d in pairs(brut) do
        if type(d) == "table" then
            local entree
            for _, e in ipairs(type(d[4]) == "table" and d[4] or {}) do
                local c = type(e) == "table" and carte.CarteDeZone(e[1])
                if c and tonumber(e[2]) and tonumber(e[3]) then
                    entree = { carte = c, x = e[2] / 100, y = e[3] / 100, nom = d[1] }
                    break
                end
            end
            local zones = { zone }
            for _, autre in ipairs(type(d[2]) == "table" and d[2] or {}) do table.insert(zones, autre) end
            for _, z in ipairs(zones) do
                local c = carte.CarteDeZone(z)
                if c and not Dehors(c) then t[c] = entree or false end
            end
        end
    end
    instances = t
    return t
end

function carte.EstInstance(idCarte)
    if not idCarte then return false end
    local info = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), idCarte)
    if type(info) == "table" and tonumber(info.mapType) and info.mapType <= 3 then return false end
    if Instances()[idCarte] ~= nil then return true end
    return type(info) == "table" and info.mapType == 4
end

-- Entree (dehors) du donjon d'une carte d'instance, ou nil.
function carte.EntreeDInstance(idCarte)
    return Instances()[idCarte] or nil
end

-- Niveaux d'une carte de zone, estimes d'apres ses quetes (QuestieDB) :
-- du 15e au 85e centile de leurs niveaux. Calcule une fois, puis garde.
local niveauxParCarte
function carte.NiveauDeCarte(idCarte)
    if not niveauxParCarte then
        niveauxParCarte = {}
        local base = NS.ref.Base("QuestDB")
        local ids = base and base.GetAllIds and base.GetAllIds() or {}
        local listes = {}
        for _, id in ipairs(ids) do
            local zone = tonumber(NS.ref.Lire("QuestDB", id, "zoneOrSort"))
            local c = zone and zone > 0 and carte.CarteDeZone(zone)
            local niveau = c and tonumber(NS.ref.Lire("QuestDB", id, "questLevel"))
            if niveau and niveau > 0 then
                listes[c] = listes[c] or {}
                table.insert(listes[c], niveau)
            end
        end
        for c, l in pairs(listes) do
            if #l >= 3 then
                table.sort(l)
                niveauxParCarte[c] = { l[math.max(1, math.floor(#l * 0.15 + 0.5))], l[math.max(1, math.floor(#l * 0.85 + 0.5))] }
            end
        end
    end
    local n = niveauxParCarte[idCarte]
    -- Base de Questie pas encore prete : on recalculera au prochain appel.
    if not next(niveauxParCarte) then niveauxParCarte = nil end
    if n then return n[1], n[2] end
    return nil
end

-- ---------------------------------------------------------------------------
-- Points de chaque quete
-- ---------------------------------------------------------------------------

local Lire = function(...) return NS.ref.Lire(...) end

-- Ajoute les apparitions d'une entite ("NpcDB" ou "ObjectDB") a la liste.
local function Apparitions(entite, id, ajouter)
    -- Releve en jeu sur WoW Forever : il passe avant Questie.
    -- Un PNJ fixe (trois places au plus dans Questie) se montre la ou on
    -- l'a vu ; une cible qui apparait partout garde aussi les places Questie.
    local releves = NS.memoire and NS.memoire.Releves and NS.memoire.Releves(entite, id)
    local spawns = Lire(entite, id, "spawns")
    if releves then
        local nom = Lire(entite, id, "name")
        for _, pt in ipairs(releves) do ajouter(pt[1], pt[2], pt[3], nom) end
        local n = 0
        for _, points in pairs(type(spawns) == "table" and spawns or {}) do n = n + (type(points) == "table" and #points or 0) end
        if n <= 3 then return end
    end
    if type(spawns) ~= "table" then return end
    local nom = Lire(entite, id, "name")
    for zone, points in pairs(spawns) do
        local idCarte = carte.CarteDeZone(zone)
        if idCarte and type(points) == "table" then
            for _, pt in ipairs(points) do
                local x, y = tonumber(pt[1]), tonumber(pt[2])
                if x and y and x >= 0 and y >= 0 then ajouter(idCarte, x, y, nom) end
            end
        end
    end
end

-- Objectif du journal deja rempli, reconnu par le nom de ce qu'il demande.
local function Rempli(q, nom)
    if not nom then return false end
    for _, o in ipairs(q.objectifs or {}) do
        if o.fait and type(o.texte) == "string" and string.find(o.texte, nom, 1, true) then return true end
    end
    return false
end

-- Liste de points : { carte, x, y, genre = "rendre"|"objectif", quete, titre, quoi }.
local function PointsDeQuete(id, q)
    local points = {}
    local function Collecteur(genre, quoi, icone, parReceveur)
        local vus, n = {}, 0
        return function(idCarte, x, y, nom)
            if n >= MAX_PAR_OBJECTIF then return end
            local cle = idCarte .. ":" .. math.floor(x / CELLULE) .. ":" .. math.floor(y / CELLULE)
            if vus[cle] then return end
            vus[cle] = true
            n = n + 1
            table.insert(points, { carte = idCarte, x = x / 100, y = y / 100, genre = genre,
                quete = id, titre = q.titre, quoi = quoi or nom, icone = icone, parReceveur = parReceveur })
        end
    end

    if q.complete == true then
        local fin = Lire("QuestDB", id, "finishedBy")
        if type(fin) == "table" then
            for _, pnj in ipairs(fin[1] or {}) do Apparitions("NpcDB", pnj, Collecteur("rendre")) end
            for _, objet in ipairs(fin[2] or {}) do Apparitions("ObjectDB", objet, Collecteur("rendre")) end
        end
        return points
    end
    if q.complete == -1 then return points end

    local objectifs = Lire("QuestDB", id, "objectives")
    if type(objectifs) == "table" then
        for _, o in ipairs(objectifs[1] or {}) do
            local nom = Lire("NpcDB", o[1], "name")
            if not Rempli(q, o[2] or nom) then Apparitions("NpcDB", o[1], Collecteur("objectif", o[2] or nom, "tuer")) end
        end
        for _, o in ipairs(objectifs[2] or {}) do
            local nom = Lire("ObjectDB", o[1], "name")
            if not Rempli(q, o[2] or nom) then Apparitions("ObjectDB", o[1], Collecteur("objectif", o[2] or nom, "objet")) end
        end
        for _, o in ipairs(objectifs[3] or {}) do
            local nomObjet = Lire("ItemDB", o[1], "name")
            if not Rempli(q, nomObjet) then
                local c = Collecteur("objectif", nomObjet, "butin")
                for _, pnj in ipairs(Lire("ItemDB", o[1], "npcDrops") or {}) do Apparitions("NpcDB", pnj, c) end
                for _, objet in ipairs(Lire("ItemDB", o[1], "objectDrops") or {}) do Apparitions("ObjectDB", objet, c) end
            end
        end
    end
    -- Lieu a explorer : { texte, { [zone] = { {x, y} } } }.
    local lieu = Lire("QuestDB", id, "triggerEnd")
    if type(lieu) == "table" and type(lieu[2]) == "table" and not Rempli(q, lieu[1]) then
        local c = Collecteur("objectif", lieu[1], "lieu")
        for zone, pts in pairs(lieu[2]) do
            local idCarte = carte.CarteDeZone(zone)
            for _, pt in ipairs(idCarte and pts or {}) do
                local x, y = tonumber(pt[1]), tonumber(pt[2])
                if x and y then c(idCarte, x, y, lieu[1]) end
            end
        end
    end
    -- Objectif sans lieu connu (parler a quelqu'un, livrer...) : celui qui
    -- reprend la quete, la ou il faut aller. Marque (parReceveur) : pour une
    -- quete de donjon, ce n'est pas la qu'elle se fait (le guidage vise
    -- alors l'entree du donjon).
    if #points == 0 then
        local fin = Lire("QuestDB", id, "finishedBy")
        if type(fin) == "table" then
            local c = Collecteur("objectif", nil, nil, true)
            for _, pnj in ipairs(fin[1] or {}) do Apparitions("NpcDB", pnj, c) end
            for _, objet in ipairs(fin[2] or {}) do Apparitions("ObjectDB", objet, c) end
        end
    end
    return points
end

-- Ou prendre une quete : ceux qui la donnent.
PointsDePrise = function(id, p)
    local points, vus = {}, {}
    local titre = NS.ref.NomDeQuete(id, p)
    local function ajouter(idCarte, x, y, nom)
        local cle = idCarte .. ":" .. math.floor(x / CELLULE) .. ":" .. math.floor(y / CELLULE)
        if vus[cle] or #points >= MAX_PAR_OBJECTIF then return end
        vus[cle] = true
        table.insert(points, { carte = idCarte, x = x / 100, y = y / 100, genre = "prendre",
            quete = id, titre = titre, quoi = nom })
    end
    local debut = Lire("QuestDB", id, "startedBy")
    if type(debut) == "table" then
        for _, pnj in ipairs(debut[1] or {}) do Apparitions("NpcDB", pnj, ajouter) end
        for _, objet in ipairs(debut[2] or {}) do Apparitions("ObjectDB", objet, ajouter) end
    end
    return points
end

-- Points de toutes les quetes du personnage connecte, gardes jusqu'au
-- prochain releve du journal.
local cache
function carte.Invalider() cache = nil end

local function TousLesPoints()
    if cache then return cache end
    cache = {}
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.PersoParCle(cle)
    -- Etapes des parcours affiches : un numero sur leurs reperes.
    local etapes = {}
    if p and NS.parcours then
        local ok, rendu = pcall(NS.parcours.EtapesSurCarte, cle, p)
        if ok then etapes = rendu else NS.base.NoterIncident("carte, parcours", rendu) end
    end
    local function Marquer(pts, id)
        local e = etapes[id]
        for _, pt in ipairs(pts) do
            if e then
                pt.numero, pt.parcours, pt.idParcours = e.numero, e.parcours, e.idParcours
                pt.attente = e.etat == "attente"
            end
            table.insert(cache, pt)
        end
    end
    for id, q in pairs(p and p.quetes or {}) do
        local ok, pts = pcall(PointsDeQuete, id, q)
        if ok then Marquer(pts, id) else NS.base.NoterIncident("carte, quete " .. tostring(id), pts) end
    end
    -- Etapes a prendre : chez celui qui donne la quete.
    for id, e in pairs(etapes) do
        if e.etat == "prendre" or e.etat == "attente" then
            local ok, pts = pcall(PointsDePrise, id, p)
            if ok then Marquer(pts, id) else NS.base.NoterIncident("carte, prise " .. tostring(id), pts) end
        end
    end
    -- Quetes disponibles (hors parcours), si demande : un ! chez le donneur.
    local options = NS.pageCarte and NS.pageCarte.Reglages and NS.pageCarte.Reglages()
    if p and NS.disponibles and options and options.disponibles then
        local ok, liste = pcall(NS.disponibles.Liste, p)
        for _, d in ipairs(ok and liste or {}) do
            if not d.gris and not etapes[d.id] then
                local okP, pts = pcall(PointsDePrise, d.id, p)
                if okP then
                    for _, pt in ipairs(pts) do
                        pt.dispo = true
                        table.insert(cache, pt)
                    end
                end
            end
        end
    end
    -- Un seul repere par lieu et par sorte : plusieurs quetes chez le meme
    -- donneur (ou sur les memes creatures) ne s'empilent plus. Les autres
    -- titres se lisent au survol. Les etapes numerotees restent toutes.
    local tries, places = {}, {}
    for _, pt in ipairs(cache) do
        if pt.numero then
            table.insert(tries, pt)
        else
            local cle = tostring(pt.carte) .. ":" .. math.floor(pt.x * 100 / CELLULE) .. ":"
                .. math.floor(pt.y * 100 / CELLULE) .. ":" .. tostring(pt.genre) .. ":" .. tostring(pt.icone) .. ":" .. tostring(pt.dispo)
            local deja = places[cle]
            if deja then
                if pt.titre and pt.titre ~= deja.titre then
                    deja.autres = deja.autres or {}
                    local vu = false
                    for _, t in ipairs(deja.autres) do if t == pt.titre then vu = true end end
                    if not vu then table.insert(deja.autres, pt.titre) end
                end
            else
                places[cle] = pt
                table.insert(tries, pt)
            end
        end
    end
    cache = tries
    return cache
end
carte.TousLesPoints = TousLesPoints

-- Points d'une quete : ses objectifs (ou son receveur) si elle est en cours,
-- sinon ceux qui la donnent.
function carte.PointsPour(id, p)
    local q = p and p.quetes and p.quetes[id]
    if q then return PointsDeQuete(id, q) end
    return PointsDePrise(id, p)
end

-- ---------------------------------------------------------------------------
-- Reperes
-- ---------------------------------------------------------------------------

local function Atlas(tex, nom)
    return tex.SetAtlas and pcall(tex.SetAtlas, tex, nom) and tex:GetAtlas() ~= nil
end

local function CreerRepere(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TAILLE, TAILLE)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetPoint("CENTER")
    b.fond:SetSize(TAILLE + 6, TAILLE + 6)
    b.symbole = b:CreateTexture(nil, "ARTWORK")
    b.symbole:SetPoint("CENTER")
    b.symbole:SetSize(TAILLE + 6, TAILLE + 6)
    -- Numero d'etape du parcours, en coin : un petit rond cercle comme les
    -- filtres sous la carte (celui de la suite).
    local S = NS.suite or _G.CoreSuite
    if S and S.PastilleNumero then
        b.numero = S.PastilleNumero(b, 17)
        b.numero:SetPoint("CENTER", b, "BOTTOMRIGHT", 2, 0)
    else
        b.numero = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.numero:SetPoint("CENTER", b, "BOTTOMRIGHT", 2, 0)
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        local pt = self.point
        if not pt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(pt.titre or ("#" .. tostring(pt.quete)), 1, 0.82, 0)
        for _, autre in ipairs(pt.autres or {}) do GameTooltip:AddLine(autre, 1, 0.82, 0) end
        if pt.numero then
            GameTooltip:AddLine(string.format(L.MAP_ROUTE_STEP, pt.parcours or "", pt.numero), 1, 1, 1)
        end
        if pt.genre == "rendre" then
            GameTooltip:AddLine(string.format(L.MAP_TURN_IN, pt.quoi or "?"), 0.31, 0.82, 0.41)
        elseif pt.genre == "prendre" then
            GameTooltip:AddLine(string.format(L.MAP_PICK_UP, pt.quoi or "?"), 1, 0.82, 0)
            if pt.attente then GameTooltip:AddLine(L.MAP_NOT_YET, 0.6, 0.6, 0.6) end
            local cle = NS.ClePersonnage()
            local p = cle and NS.base.PersoParCle(cle)
            local xp, estimee = NS.ref.XPDeLaBase(pt.quete, p and p.niveau)
            if xp and xp > 0 then GameTooltip:AddLine(string.format(estimee and L.REWARD_XP_ESTIMATED or L.REWARD_XP, xp), 1, 1, 1) end
            local niveau = NS.ref.Lire("QuestDB", pt.quete, "questLevel")
            if niveau then GameTooltip:AddLine(string.format(L.LEVEL, niveau), 0.7, 0.7, 0.7) end
        elseif pt.quoi then
            GameTooltip:AddLine(pt.quoi, 1, 1, 1, true)
        end
        local modeTrajet = NS.pageCarte and NS.pageCarte.EnModeTrajet and NS.pageCarte.EnModeTrajet()
        if not modeTrajet then GameTooltip:AddLine(L.MAP_CLICK, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, bouton)
        -- Carte cloisonnee sur un trajet : les etapes se gerent dans la liste a
        -- gauche ; un clic sur un repere ne change pas de page.
        if bouton == "RightButton" then return end
        if NS.pageCarte and NS.pageCarte.EnModeTrajet and NS.pageCarte.EnModeTrajet() then return end
        if self.point and self.point.genre == "prendre" then
            NS.fenetre.OuvrirDisponible(self.point.quete)
        elseif self.point then
            NS.fenetre.OuvrirQuete(NS.ClePersonnage(), self.point.quete)
        end
    end)
    return b
end

-- Icones des objectifs, a la facon de Questie (icones de pfQuest, licence
-- MIT, dans Icons) : sacoche pour le butin, epee pour les creatures a tuer,
-- engrenage pour les objets a utiliser.
local ICONES_OBJECTIF = {
    butin = { "Interface\\AddOns\\QuestCore\\Icons\\loot_mono", 1, 0.82, 0 },
    tuer = { "Interface\\AddOns\\QuestCore\\Icons\\slay_mono", 1, 0.38, 0.32 },
    objet = { "Interface\\AddOns\\QuestCore\\Icons\\object_mono", 0.45, 0.8, 1 },
}

local function Habiller(b, genre, icone, attente)
    local cle = genre .. ":" .. tostring(icone) .. ":" .. tostring(attente)
    if b.habit == cle then return end
    b.habit = cle
    b.genre = genre
    -- Etape pas encore prenable : en gris, en retrait.
    b.symbole:SetDesaturated(attente == true)
    b.fond:SetDesaturated(attente == true)
    b:SetAlpha(attente and 0.6 or 1)
    b.symbole:SetVertexColor(1, 1, 1)
    b.symbole:SetTexCoord(0, 1, 0, 1)
    local mono = genre == "objectif" and ICONES_OBJECTIF[icone or ""]
    if mono then
        b.fond:Hide()
        b.symbole:SetTexture(mono[1])
        b.symbole:SetVertexColor(mono[2], mono[3], mono[4])
        b.symbole:SetSize(TAILLE - 4, TAILLE - 4)
        return
    end
    b.fond:Show()
    if not Atlas(b.fond, "UI-QuestPoi-QuestNumber") then b.fond:SetTexture(nil) end
    if genre == "prendre" then
        -- Le point d'exclamation des quetes a prendre, celui du jeu, seul et
        -- a sa taille (sur le rond, il debordait).
        b.fond:Hide()
        if Atlas(b.symbole, "QuestNormal") then
            b.symbole:SetSize(TAILLE - 2, TAILLE - 2)
        else
            b.symbole:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            b.symbole:SetTexCoord(0, 1, 0, 1)
            b.symbole:SetSize(TAILLE - 6, TAILLE - 6)
        end
        return
    end
    b.symbole:SetSize(TAILLE + 6, TAILLE + 6)
    local nom = (genre == "rendre") and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow"
    if not Atlas(b.symbole, nom) then
        b.symbole:SetTexture(genre == "rendre" and "Interface\\GossipFrame\\ActiveQuestIcon"
            or "Interface\\GossipFrame\\IncompleteQuestIcon")
    end
end

carte.CreerRepere = function(parent) return CreerRepere(parent) end
carte.Habiller = function(b, genre, icone, attente) return Habiller(b, genre, icone, attente) end

-- Report d'une carte sur une autre, verrouille. Une zone n'est reportee que
-- si le jeu la connait, si elle est bien dans la carte affichee (en
-- remontant ses parents), et si sa place est vraisemblable : dans le cadre
-- de sa carte parente, et jamais plus de 15 % de la carte affichee (sauf un
-- continent sur la carte du monde). Sinon, ses reperes ne s'y dessinent
-- pas : plus d'anneaux ni de quetes au milieu de la mer (donjons, zones
-- ajoutees par Forever).
local rectangles = {}
local Rectangle
local function Brut(zone, carteAffichee)
    local lecture = NS.Lecture("C_Map.GetMapRectOnMap")
    if not lecture then return nil end
    local ok, g, d, h, b = pcall(lecture, zone, carteAffichee)
    if not (ok and tonumber(g) and tonumber(d) and tonumber(h) and tonumber(b) and d > g and b > h) then return nil end
    if g == 0 and d == 1 and h == 0 and b == 1 then return nil end
    return { g, d, h, b }
end
Rectangle = function(zone, carteAffichee)
    local cle = zone .. ">" .. carteAffichee
    local r = rectangles[cle]
    if r ~= nil then return r or nil end
    rectangles[cle] = false
    r = false
    local Info = NS.Lecture("C_Map.GetMapInfo")
    local info = NS.Appeler(Info, zone)
    if type(info) == "table" and not carte.EstInstance(zone) then
        -- La carte affichee doit etre un de ses parents.
        local parent, trouve = tonumber(info.parentMapID), false
        local garde = 0
        local cur = parent
        while cur and cur > 0 and garde < 8 do
            if cur == carteAffichee then trouve = true break end
            local ic = NS.Appeler(Info, cur)
            cur = type(ic) == "table" and tonumber(ic.parentMapID) or nil
            garde = garde + 1
        end
        local brut = trouve and Brut(zone, carteAffichee)
        if brut then
            local aire = (brut[2] - brut[1]) * (brut[4] - brut[3])
            local continent = info.mapType == 2
            local ok = continent or aire <= 0.15
            -- Dans le cadre de sa carte parente (si ce n'est pas la carte
            -- affichee elle-meme).
            if ok and parent ~= carteAffichee then
                local pr = Rectangle(parent, carteAffichee)
                local tol = 0.02
                ok = pr ~= nil and brut[1] >= pr[1] - tol and brut[2] <= pr[2] + tol
                    and brut[3] >= pr[3] - tol and brut[4] <= pr[4] + tol
            end
            if ok then r = brut end
        end
    end
    rectangles[cle] = r
    return r or nil
end

-- Position d'un point sur la carte affichee, ou nil s'il n'y est pas.
Reporter = function(pt, idCarte)
    if pt.carte == idCarte then return pt.x, pt.y end
    local r = Rectangle(pt.carte, idCarte)
    if not r then return nil end
    local x = r[1] + pt.x * (r[2] - r[1])
    local y = r[3] + pt.y * (r[4] - r[3])
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

carte.Reporter = function(pt, idCarte) return Reporter(pt, idCarte) end

-- Le detail (quetes, creatures, objets) ne se voit que zone par zone. Sur
-- la carte d'une zone : ce qui est dans cette zone. Sur un continent ou le
-- monde : seulement ce qui est dans la zone du personnage. Rien ne
-- s'additionne d'une zone a l'autre.
local zonesDe = {}
local function ZoneDe(idCarte)
    if not idCarte then return nil end
    if zonesDe[idCarte] ~= nil then return zonesDe[idCarte] or nil end
    local Info = NS.Lecture("C_Map.GetMapInfo")
    local cur, garde, zone = idCarte, 0, nil
    while cur and garde < 8 do
        local i = NS.Appeler(Info, cur)
        if type(i) ~= "table" then break end
        if i.mapType == 3 then zone = cur break end
        if i.mapType and i.mapType <= 2 then break end
        cur = tonumber(i.parentMapID)
        garde = garde + 1
    end
    zonesDe[idCarte] = zone or false
    return zone
end
carte.ZoneDe = ZoneDe

function carte.ParZone(pt, idCarte)
    if not pt or not pt.carte then return false end
    if pt.carte == idCarte then return true end
    local affichee = ZoneDe(idCarte)
    if affichee == idCarte then return ZoneDe(pt.carte) == affichee end
    -- Continent ou monde : la zone du personnage seule.
    local ici = ZoneDe(NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player"))
    return ici ~= nil and ZoneDe(pt.carte) == ici
end

-- Les reperes ne vont plus sur la carte du monde du jeu : tout passe par la
-- page Carte. Ces deux fonctions restent pour ceux qui les appellent.
function carte.Rendre() end
function carte.Installer() end

-- Pour les autres add-ons de la suite (MapCore) : les reperes de quetes.
_G.QuestCoreAPI = {
    -- L'objectif de QuestCore guide (nom, etapes restantes, total), ou nil.
    Circuit = function()
        local a = NS.guidage and NS.guidage.Objectif and NS.guidage.Objectif()
        if not a then return nil end
        local e = (NS.suite or _G.CoreSuite).EtatGuidage()
        if not e then return nil end
        local total = e.total or 0
        return { nom = a.libelle, reste = math.max(0, total - (e.rang or 1) + 1), total = total, guide = true }
    end,
    -- Le bandeau d'avancement, pour les autres add-ons de la suite (CraftCore :
    -- projet termine). Memes reglages, meme place que pour les quetes.
    -- opts (facultatif) : { clignote = true, icone = texture } pour un haut fait.
    Bandeau = function(titre, detail, terminee, detail2, opts)
        if NS.bandeau and NS.bandeau.Montrer then NS.bandeau.Montrer(titre, detail, terminee, detail2, opts) return true end
        return false
    end,
    Points = function() return carte.TousLesPoints() end,
    Reporter = function(pt, idCarte) return carte.Reporter(pt, idCarte) end,
    ParZone = function(pt, idCarte) return carte.ParZone(pt, idCarte) end,
    CreerRepere = function(parent) return carte.CreerRepere(parent) end,
    Habiller = function(b, genre, icone, attente) return carte.Habiller(b, genre, icone, attente) end,
    NiveauDeCarte = function(idCarte) return carte.NiveauDeCarte(idCarte) end,
    -- Les itineraires de quetes du personnage connecte, pour l'onglet
    -- Itineraires de MapCore : { uid, nom, type ("suite" | "donjon" |
    -- "parcours"), faites, total, zone (de la prochaine etape), guide }.
    Itineraires = function()
        local cle = NS.ClePersonnage()
        local p = cle and NS.base.PersoParCle(cle)
        local res = {}
        if not (p and NS.parcours) then return res end
        local S = NS.suite or _G.CoreSuite
        for _, pc in ipairs(NS.parcours.Liste(cle)) do
            local faites, total = NS.parcours.Avancement(p, pc)
            if faites < total then
                local _, id = NS.parcours.Prochaine(p, pc)
                local zone = id and tonumber(NS.ref.Lire("QuestDB", id, "zoneOrSort")) or 0
                local nomZone = zone > 0 and NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone) or nil
                local genre = (pc.genre == "kit" and "donjon") or (pc.genre == "zone" and "zone") or "suite"
                local guide = NS.guidage and NS.guidage.EstActif and NS.guidage.EstActif("parcours", { uid = pc.uid }) or false
                table.insert(res, { uid = pc.uid, nom = pc.nom, type = genre, faites = faites, total = total,
                    zone = nomZone, guide = guide })
            end
        end
        return res
    end,
    -- Guider un itineraire (ou l'arreter s'il est deja guide).
    GuiderItineraire = function(uid)
        if not (NS.guidage and NS.guidage.Lancer) then return false end
        if NS.guidage.EstActif and NS.guidage.EstActif("parcours", { uid = uid }) then
            return pcall(NS.guidage.Basculer, "parcours", { uid = uid })
        end
        return pcall(NS.guidage.Lancer, "parcours", { uid = uid })
    end,
    -- Parcours de progression vers le niveau suivant, pour le personnage
    -- connecte, puis ouverture de la page Parcours. Rend le parcours ou nil
    -- et la raison ("rien", "aucune"). (Les boutons guident plutot vers un
    -- niveau : QuestCoreAPI.GuiderNiveau, Core/Guidage.lua.)
    CreerProgression = function()
        local cle = NS.ClePersonnage()
        local p = cle and NS.base.PersoParCle(cle)
        if not p then return nil, "aucune" end
        local pc, raison = NS.disponibles.CreerProgression(cle, p)
        if pc then
            if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
            if _G.CoreSuite and _G.CoreSuite.Ouvrir then pcall(_G.CoreSuite.Ouvrir, "QuestCore") end
            NS.fenetre.OuvrirParcours()
        end
        return pc, raison
    end,
}
