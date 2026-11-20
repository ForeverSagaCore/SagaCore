local _, NS = ...

-- Quetes disponibles : celles que le personnage peut prendre maintenant
-- (race, classe, niveau, prerequis, pas deja faites ni en cours), lues dans
-- QuestieDB. Recalculees seulement quand une quete est prise, rendue ou
-- abandonnee, ou au passage de niveau.
--
-- Parcours de progression : un objectif d'experience (le niveau suivant),
-- atteint avec les quetes les plus rentables et les plus proches, puis
-- rangees dans l'ordre d'un trajet qui part du personnage.

NS.disponibles = {}
local dispo = NS.disponibles

local Lire = function(...) return NS.ref.Lire(...) end
local ECART_GRIS = 6

local cache, cleCache

-- Grise comme dans le journal du jeu (meme regle que la couleur de niveau).
local function Grise(niveau, niveauPerso)
    local r, v, b = NS.ref.CouleurDeNiveau(niveau, niveauPerso)
    return r == 0.5 and v == 0.5 and b == 0.5
end

function dispo.Invalider() cache = nil end

local function Exclue(p, id)
    for _, autre in ipairs(Lire("QuestDB", id, "exclusiveTo") or {}) do
        if p.faites and p.faites[autre] then return true end
        if p.quetes and p.quetes[autre] then return true end
    end
    local maxi = tonumber(Lire("QuestDB", id, "requiredMaxLevel")) or 0
    if maxi > 0 and p.niveau and p.niveau > maxi then return true end
    return false
end

-- Un donneur (PNJ ou objet du monde) qui a au moins une position connue.
local function Localisable(debut)
    for _, pnj in ipairs(type(debut[1]) == "table" and debut[1] or {}) do
        local positions = Lire("NpcDB", pnj, "spawns")
        if type(positions) == "table" and next(positions) then return true end
    end
    for _, objet in ipairs(type(debut[2]) == "table" and debut[2] or {}) do
        local positions = Lire("ObjectDB", objet, "spawns")
        if type(positions) == "table" and next(positions) then return true end
    end
    return false
end

-- Un objet qui lance la quete, present dans les sacs.
local function DansLesSacs(objets)
    local compter = _G.GetItemCount or (_G.C_Item and _G.C_Item.GetItemCount)
    if type(objets) ~= "table" or not compter then return false end
    for _, objet in ipairs(objets) do
        local ok, n = pcall(compter, objet)
        if ok and (tonumber(n) or 0) > 0 then return true end
    end
    return false
end

-- Liste { id, niveau, zone, gris } des quetes prenables, par zone puis niveau.
function dispo.Liste(p)
    if not p then return {} end
    local cle = p.cle .. ":" .. tostring(p.niveau)
    if cache and cleCache == cle then return cache end
    local base = NS.ref.Base("QuestDB")
    local ids = base and base.GetAllIds and base.GetAllIds() or {}
    local liste = {}
    for _, id in ipairs(ids) do
        if not (p.faites and p.faites[id]) and not (p.quetes and p.quetes[id])
            and NS.histoire.Admise(p, id) and NS.parcours.Prenable(p, id) and not Exclue(p, id) then
            local debut = Lire("QuestDB", id, "startedBy")
            -- Seulement ce qu'un PNJ ou un objet du monde donne, et qu'on peut
            -- placer sur la carte ; ou ce qu'un objet deja dans les sacs donne.
            -- (Ex. "Bienvenue !" : un bon cadeau de l'edition collector, sans
            -- PNJ pour la donner : elle ne s'affiche plus si on n'a pas le bon.)
            if type(debut) == "table" and (Localisable(debut) or DansLesSacs(debut[3])) then
                local niveau = tonumber(Lire("QuestDB", id, "questLevel")) or 0
                table.insert(liste, { id = id, niveau = niveau, zone = tonumber(Lire("QuestDB", id, "zoneOrSort")) or 0,
                    gris = Grise(niveau, p.niveau) })
            end
        end
    end
    table.sort(liste, function(a, b)
        if a.niveau ~= b.niveau then return a.niveau < b.niveau end
        return a.id < b.id
    end)
    if #ids > 0 then cache, cleCache = liste, cle end
    return liste
end

-- ---------------------------------------------------------------------------
-- Parcours de progression
-- ---------------------------------------------------------------------------

-- Carte du continent ou se trouve le personnage, pour mesurer les distances.
local function Continent()
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local garde = 0
    while carte and garde < 6 do
        local info = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
        if type(info) ~= "table" then return nil end
        if info.mapType == 2 then return carte end
        carte = info.parentMapID
        garde = garde + 1
    end
    return nil
end

-- Centre des points d'une quete sur le continent, ou nil, et son etendue :
-- le chemin a faire sur place (aller-retour moyen entre ses points).
local function Position(id, p, continent)
    if not continent or not NS.carte then return nil end
    local ok, points = pcall(NS.carte.PointsPour, id, p)
    if not ok or type(points) ~= "table" then return nil end
    local liste = {}
    local sx, sy = 0, 0
    for _, pt in ipairs(points) do
        local x, y = NS.carte.Reporter(pt, continent)
        if x then
            table.insert(liste, { x, y })
            sx, sy = sx + x, sy + y
        end
    end
    local n = #liste
    if n == 0 then return nil end
    local cx, cy = sx / n, sy / n
    local etendue = 0
    for _, v in ipairs(liste) do etendue = etendue + math.sqrt((v[1] - cx) ^ 2 + (v[2] - cy) ^ 2) end
    return cx, cy, 2 * etendue / n
end

local function XP(id, p)
    local q = p.quetes and p.quetes[id]
    local connue = q and q.recompenses and tonumber(q.recompenses.xp)
    return connue or NS.ref.XPDeLaBase(id, p.niveau) or 0
end

-- Experience qui manque au personnage connecte pour le niveau suivant.
function dispo.XPManquante()
    local maxi = tonumber((NS.Appeler(UnitXPMax, "player"))) or 0
    local actuelle = tonumber((NS.Appeler(UnitXP, "player"))) or 0
    return math.max(0, maxi - actuelle)
end

-- Cree le parcours : rendre ce qui est fini, puis les quetes qui rapportent
-- le plus d'experience pour le moins de chemin, jusqu'a l'objectif.
--
-- Le chemin compte vraiment : chaque quete est jugee sur ce qu'elle ajoute
-- au trajet deja prevu (insertion a la meilleure place), plus le chemin a
-- faire sur place. Des quetes groupees au meme endroit passent donc avant
-- une quete plus riche a l'autre bout de la carte, meme s'il en faut plus.
-- Le trajet est ensuite raccourci (on decroise les allers-retours).
local function Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Ce que coute l'ajout de `c` au trajet : detour minimal et sa place.
local function Insertion(trajet, depart, c)
    local meilleur, place
    for i = 1, #trajet + 1 do
        local a = (i == 1) and depart or trajet[i - 1]
        local b = trajet[i]
        local detour = Distance(a, c) + (b and (Distance(c, b) - Distance(a, b)) or 0)
        if not meilleur or detour < meilleur then meilleur, place = detour, i end
    end
    return meilleur, place
end

-- 2-opt : retourne un morceau du trajet tant que cela le raccourcit.
local function Decroiser(trajet, depart)
    local ameliore, tours = true, 0
    while ameliore and tours < 50 do
        ameliore, tours = false, tours + 1
        for i = 1, #trajet - 1 do
            for j = i + 1, #trajet do
                local a = (i == 1) and depart or trajet[i - 1]
                local b, c, d = trajet[i], trajet[j], trajet[j + 1]
                local avant = Distance(a, b) + (d and Distance(c, d) or 0)
                local apres = Distance(a, c) + (d and Distance(b, d) or 0)
                if apres + 1e-6 < avant then
                    local g, h = i, j
                    while g < h do
                        trajet[g], trajet[h] = trajet[h], trajet[g]
                        g, h = g + 1, h - 1
                    end
                    ameliore = true
                end
            end
        end
    end
end

function dispo.CreerProgression(cle, p)
    local besoin = dispo.XPManquante()
    if besoin <= 0 then return nil, "rien" end
    local continent = Continent()
    local px, py
    if continent then
        local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
        if type(pos) == "table" and pos.GetXY then px, py = pos:GetXY() end
    end
    local depart = { x = px or 0.5, y = py or 0.5 }

    local candidats = {}
    local function Ajouter(id, prioritaire)
        local xp = XP(id, p)
        if xp <= 0 then return end
        local x, y, etendue = Position(id, p, continent)
        table.insert(candidats, { id = id, xp = xp, x = x, y = y, etendue = etendue or 0, prioritaire = prioritaire })
    end
    for id, q in pairs(p.quetes or {}) do
        if q.complete ~= -1 then Ajouter(id, q.complete == true) end
    end
    for _, d in ipairs(dispo.Liste(p)) do
        if not d.gris then Ajouter(d.id, false) end
    end

    -- Un plan : les quetes finies (a rendre de toute facon), puis l'ancre si
    -- on en donne une, puis tant qu'il manque de l'experience, la meilleure
    -- experience par detour. Rend le trajet, les quetes sans position, l'XP
    -- et le cout (chemin total, sur place compris).
    local function Plan(ancre)
        local reste, trajet, sansPosition, total = {}, {}, {}, 0
        for _, c in ipairs(candidats) do table.insert(reste, c) end
        local function Prendre(rang, place)
            local c = table.remove(reste, rang)
            if c.x then table.insert(trajet, place or (#trajet + 1), c) else table.insert(sansPosition, c) end
            total = total + c.xp
        end
        local rang = 1
        while rang <= #reste do
            local c = reste[rang]
            if c.prioritaire or c == ancre then
                local place
                if c.x then local _d _d, place = Insertion(trajet, depart, c) end
                Prendre(rang, place)
            else
                rang = rang + 1
            end
        end
        while total < besoin and #reste > 0 do
            local meilleur, sonRang, saPlace
            for r, c in ipairs(reste) do
                local detour, place = 0.5, nil
                if c.x then detour, place = Insertion(trajet, depart, c) end
                local valeur = c.xp / (detour + c.etendue + 0.01)
                if not meilleur or valeur > meilleur then meilleur, sonRang, saPlace = valeur, r, place end
            end
            Prendre(sonRang, saPlace)
        end
        Decroiser(trajet, depart)
        local cout, a = 0.5 * #sansPosition, depart
        for _, c in ipairs(trajet) do cout, a = cout + Distance(a, c) + c.etendue, c end
        return trajet, sansPosition, total, cout
    end

    -- Le premier choix decide de la region : un plan par point de depart
    -- possible (les endroits ou l'experience est la plus groupee, et les
    -- quetes les plus riches), et on garde le chemin le plus court.
    local ancres = {}
    for _, c in ipairs(candidats) do
        if c.x and not c.prioritaire then
            local groupe = 0
            for _, o in ipairs(candidats) do
                if o.x and math.abs(o.x - c.x) < 0.08 and math.abs(o.y - c.y) < 0.08 then groupe = groupe + o.xp end
            end
            table.insert(ancres, { c = c, groupe = groupe })
        end
    end
    local essais = { false }
    table.sort(ancres, function(a, b) return a.groupe > b.groupe end)
    for r = 1, math.min(20, #ancres) do table.insert(essais, ancres[r].c) end
    table.sort(ancres, function(a, b) return a.c.xp > b.c.xp end)
    for r = 1, math.min(5, #ancres) do table.insert(essais, ancres[r].c) end

    local trajet, sansPosition, total, meilleurCout
    for _, ancre in ipairs(essais) do
        local t, sp, xp, cout = Plan(ancre or nil)
        local atteint = xp >= besoin
        local mieux = not meilleurCout
            or (atteint and total < besoin)
            or ((atteint == (total >= besoin)) and cout < meilleurCout)
        if mieux then trajet, sansPosition, total, meilleurCout = t, sp, xp, cout end
    end
    if #trajet + #sansPosition == 0 then return nil, "aucune" end

    -- Temps estime a pied (7 yards par seconde) : le trajet et le chemin sur
    -- place, convertis en yards avec la taille du continent dans le monde.
    local tempsPrevu
    local versMonde, V = NS.Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if continent and versMonde and V then
        local function Monde(x, y)
            local ok, _, pos = pcall(versMonde, continent, V(x, y))
            if ok and pos and pos.GetXY then return pos:GetXY() end
        end
        local x0, y0 = Monde(0, 0)
        local x1, y1 = Monde(1, 0)
        local x2, y2 = Monde(0, 1)
        if x0 and x1 and x2 then
            local largeur = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            local hauteur = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
            local yards, a = 0, depart
            for _, c in ipairs(trajet) do
                yards = yards + math.sqrt(((c.x - a.x) * largeur) ^ 2 + ((c.y - a.y) * hauteur) ^ 2)
                    + c.etendue * (largeur + hauteur) / 2
                a = c
            end
            if yards > 0 then tempsPrevu = math.floor(yards / 7) end
        end
    end

    local etapes = {}
    for _, c in ipairs(trajet) do table.insert(etapes, c.id) end
    for _, c in ipairs(sansPosition) do table.insert(etapes, c.id) end
    local liste = NS.parcours.Liste(cle)
    local maxi = 0
    for _, pc in ipairs(liste) do maxi = math.max(maxi, pc.id or 0) end
    local pc = { id = maxi + 1, genre = "progression", carte = true, etapes = etapes,
        nom = string.format(NS.L.ROUTE_LEVEL_NAME, (p.niveau or 0) + 1),
        objectifXP = besoin, xpPrevue = total, tempsPrevu = tempsPrevu, niveauVise = (p.niveau or 0) + 1 }
    table.insert(liste, pc)
    return pc
end

-- Itineraire pour rendre des quetes terminees : depuis la position du
-- personnage, le plus proche d'abord, puis sans croisement. Un seul
-- itineraire de rendu a la fois : le nouveau remplace l'ancien.
function dispo.CreerTournee(cle, p, ids)
    local continent = Continent()
    local px, py
    if continent then
        local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
        if type(pos) == "table" and pos.GetXY then px, py = pos:GetXY() end
    end
    local depart = { x = px or 0.5, y = py or 0.5 }
    local restants, sansLieu = {}, {}
    for _, id in ipairs(ids) do
        local x, y = Position(id, p, continent)
        if x then table.insert(restants, { id = id, x = x, y = y }) else table.insert(sansLieu, id) end
    end
    local trajet, ici = {}, depart
    while #restants > 0 do
        local meilleur, rang = nil, nil
        for i, c in ipairs(restants) do
            local d = Distance(ici, c)
            if not meilleur or d < meilleur then meilleur, rang = d, i end
        end
        ici = table.remove(restants, rang)
        table.insert(trajet, ici)
    end
    Decroiser(trajet, depart)
    local etapes = {}
    for _, c in ipairs(trajet) do table.insert(etapes, c.id) end
    for _, id in ipairs(sansLieu) do table.insert(etapes, id) end
    local liste = NS.parcours.Liste(cle)
    for i = #liste, 1, -1 do if liste[i].genre == "rendu" then table.remove(liste, i) end end
    local maxi = 0
    for _, pc in ipairs(liste) do maxi = math.max(maxi, pc.id or 0) end
    local pc = { id = maxi + 1, genre = "rendu", carte = true, etapes = etapes, nom = NS.L.ROUTE_TURNIN_NAME }
    table.insert(liste, pc)
    return pc
end

-- Trajet le plus court pour monter de niveau en rendant des quetes
-- terminees : parmi les quetes a rendre, le groupe dont l'XP suffit et dont
-- le chemin (depuis le personnage, sans croisement) est le plus court.
-- Jusqu'a 12 quetes : on essaie toutes les combinaisons ; au-dela, les plus
-- proches d'abord. Rend la liste des quetes, dans l'ordre, ou nil.
function dispo.QuetesPourNiveau(p)
    local besoin = dispo.XPManquante()
    if besoin <= 0 then return nil end
    local continent = Continent()
    local px, py
    if continent then
        local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
        if type(pos) == "table" and pos.GetXY then px, py = pos:GetXY() end
    end
    local depart = { x = px or 0.5, y = py or 0.5 }
    local candidats = {}
    for id, q in pairs(p.quetes or {}) do
        if q.complete == true then
            local xp = XP(id, p)
            local x, y = Position(id, p, continent)
            -- Lieu inconnu : tenu pour lointain, choisi en dernier recours.
            if not x then x, y = 9, 9 end
            if xp > 0 then table.insert(candidats, { id = id, xp = xp, x = x, y = y }) end
        end
    end
    local total = 0
    for _, c in ipairs(candidats) do total = total + c.xp end
    if total < besoin then return nil end
    table.sort(candidats, function(a, b) return Distance(depart, a) < Distance(depart, b) end)
    while #candidats > 10 do table.remove(candidats) end
    local function Longueur(liste)
        local trajet, ici, restants = {}, depart, {}
        for _, c in ipairs(liste) do table.insert(restants, c) end
        while #restants > 0 do
            local meilleur, rang
            for i, c in ipairs(restants) do
                local d = Distance(ici, c)
                if not meilleur or d < meilleur then meilleur, rang = d, i end
            end
            ici = table.remove(restants, rang)
            table.insert(trajet, ici)
        end
        local l, prec = 0, depart
        for _, c in ipairs(trajet) do l = l + Distance(prec, c) prec = c end
        return l, trajet
    end
    local meilleur, meilleurTrajet
    local n = #candidats
    for masque = 1, (2 ^ n) - 1 do
        local xp, liste, m = 0, {}, masque
        for i = 1, n do
            if m % 2 == 1 then xp = xp + candidats[i].xp table.insert(liste, candidats[i]) end
            m = math.floor(m / 2)
        end
        if xp >= besoin then
            local l, trajet = Longueur(liste)
            if not meilleur or l < meilleur then meilleur, meilleurTrajet = l, trajet end
        end
    end
    if not meilleurTrajet then return nil end
    Decroiser(meilleurTrajet, depart)
    local ids = {}
    for _, c in ipairs(meilleurTrajet) do table.insert(ids, c.id) end
    return ids
end
