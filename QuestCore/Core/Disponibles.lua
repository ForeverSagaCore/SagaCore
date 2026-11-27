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

-- Le suivi des quetes de bas niveau du jeu (minicarte : Suivi) : allume, les
-- quetes grises comptent comme les autres, partout dans QuestCore. Lu au plus
-- une fois toutes les 2 secondes ; lecture seule.
local basNiveau, luBasNiveau = false, -10
local function SuiviBasNiveau(nom, texture)
    local n = type(nom) == "string" and nom:lower() or ""
    if n:find("bas niveau", 1, true) or n:find("low level", 1, true) or n:find("trivial", 1, true) then return true end
    return type(texture) == "string" and texture:lower():find("trivial", 1, true) ~= nil
end
function dispo.BasNiveau()
    local maintenant = (_G.GetTime and _G.GetTime()) or 0
    if maintenant - luBasNiveau < 2 then return basNiveau end
    luBasNiveau = maintenant
    local actif = false
    local M = _G.C_Minimap
    local nombre = (M and M.GetNumTrackingTypes) or _G.GetNumTrackingTypes
    local lire = (M and M.GetTrackingInfo) or _G.GetTrackingInfo
    local okN, n = pcall(nombre or function() return 0 end)
    for i = 1, (okN and tonumber(n) or 0) do
        local ok, a, b, c = pcall(lire, i)
        if ok then
            if type(a) == "table" then
                if a.active and SuiviBasNiveau(a.name, a.texture) then actif = true end
            elseif c and SuiviBasNiveau(a, b) then
                actif = true
            end
        end
    end
    basNiveau = actif
    return actif
end

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
    local bas = dispo.BasNiveau()
    local cle = p.cle .. ":" .. tostring(p.niveau) .. ":" .. tostring(bas)
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
                    gris = (not bas) and Grise(niveau, p.niveau) })
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

-- Le calcul de la progression vers le niveau suivant, sans rien enregistrer :
-- rend les etapes (quetes, dans l'ordre), l'XP prevue, le besoin et le temps
-- estime, ou nil et la raison ("rien", "aucune").
function dispo.CalculerProgression(p)
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
    return etapes, total, besoin, tempsPrevu
end

-- Cree le parcours de progression (genre "progression") vers le niveau
-- suivant.
function dispo.CreerProgression(cle, p)
    local etapes, total, besoin, tempsPrevu = dispo.CalculerProgression(p)
    if not etapes then return nil, total end
    local liste = NS.parcours.Liste(cle)
    local maxi = 0
    for _, pc in ipairs(liste) do maxi = math.max(maxi, pc.id or 0) end
    local pc = { id = maxi + 1, genre = "progression", carte = true, etapes = etapes,
        nom = string.format(NS.L.ROUTE_LEVEL_NAME, (p.niveau or 0) + 1),
        objectifXP = besoin, xpPrevue = total, tempsPrevu = tempsPrevu, niveauVise = (p.niveau or 0) + 1 }
    table.insert(liste, pc)
    pcall(NS.parcours.Liste, cle)
    return pc
end

-- Les quetes d'un trajet vers le niveau suivant : les terminees si leur XP
-- suffit (le plus court), sinon le calcul de la progression.
function dispo.EtapesPourNiveau(p)
    local ok, ids = pcall(dispo.QuetesPourNiveau, p)
    if ok and type(ids) == "table" and #ids > 0 then return ids end
    local ok2, etapes = pcall(dispo.CalculerProgression, p)
    if ok2 and type(etapes) == "table" and #etapes > 0 then return etapes end
    return nil
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

-- ---------------------------------------------------------------------------
-- Progression : l'experience par niveau, les zones et un objectif de niveau.
-- Tout ne compte que l'XP des recompenses de quetes (les monstres tues en
-- route raccourcissent d'autant).
-- ---------------------------------------------------------------------------

-- XP pour passer du niveau n au suivant (table du jeu d'origine) ; le
-- niveau en cours se lit dans le jeu.
local XP_NIVEAU = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
    117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
    202300, 209800 }
dispo.NIVEAU_MAX = #XP_NIVEAU + 1

-- Le point de depart d'un personnage : son niveau, son XP dans le niveau et
-- l'XP de ce niveau (le jeu pour le personnage connecte).
local function Depart(p)
    local niveau = tonumber(p and p.niveau) or 1
    local dans, taille = 0, XP_NIVEAU[niveau] or 0
    if p and p.cle == NS.ClePersonnage() then
        dans = tonumber((NS.Appeler(UnitXP, "player"))) or 0
        taille = tonumber((NS.Appeler(UnitXPMax, "player"))) or taille
    end
    return niveau, dans, taille
end

-- XP qui manque pour atteindre le niveau vise.
function dispo.XPJusquA(p, vise)
    local niveau, dans, taille = Depart(p)
    if vise <= niveau then return 0 end
    local besoin = math.max(0, taille - dans)
    for n = niveau + 1, math.min(vise - 1, #XP_NIVEAU) do besoin = besoin + XP_NIVEAU[n] end
    return besoin
end

-- Le niveau atteint (avec sa part du suivant) en gagnant `xp`.
function dispo.NiveauApres(p, xp)
    local niveau, dans, taille = Depart(p)
    local reste = (tonumber(xp) or 0) + dans
    while niveau < dispo.NIVEAU_MAX and taille > 0 and reste >= taille do
        reste = reste - taille
        niveau = niveau + 1
        taille = XP_NIVEAU[niveau] or 0
    end
    return niveau + ((taille > 0) and (reste / taille) or 0)
end

-- Les zones des quetes a prendre, avec ce que chacune represente : quetes,
-- part deja faite, XP de ce qui reste et distance (la zone ou l'on est en
-- premier, puis les plus proches sur le continent, puis les autres).
-- La regle de niveau, la meme partout : "pour vous" jusqu'a niveau + 3
-- (pas grises) ; au-dessus, "plus tard" ; les grises a part.
dispo.ECART_PLUS_TARD = 3
function dispo.PlusTard(p, d) return (d.niveau or 0) > (tonumber(p.niveau) or 0) + dispo.ECART_PLUS_TARD end

-- Les quetes au-dessus du niveau, a part (pour la rubrique Plus tard).
function dispo.ListePlusTard(p)
    local res = {}
    for _, d in ipairs(dispo.Liste(p)) do if dispo.PlusTard(p, d) then table.insert(res, d) end end
    table.sort(res, function(a, b) if a.niveau ~= b.niveau then return a.niveau < b.niveau end return a.id < b.id end)
    return res
end

function dispo.Zones(p, avecGrises)
    local liste = dispo.Liste(p)
    local parZone, zones = {}, {}
    for _, d in ipairs(liste) do
        if (avecGrises or not d.gris) and not dispo.PlusTard(p, d) then
            local z = parZone[d.zone]
            if not z then
                z = { zone = d.zone, ids = {}, xp = 0, faites = 0, enCours = 0, niveauMin = d.niveau, niveauMax = d.niveau }
                parZone[d.zone] = z
                table.insert(zones, z)
            end
            table.insert(z.ids, d)
            z.xp = z.xp + (tonumber((XP(d.id, p))) or 0)
            z.niveauMin = math.min(z.niveauMin, d.niveau)
            z.niveauMax = math.max(z.niveauMax, d.niveau)
        end
    end
    -- Part faite : les quetes rendues et en cours de la zone.
    for id in pairs(p.faites or {}) do
        local z = parZone[tonumber(Lire("QuestDB", id, "zoneOrSort")) or 0]
        if z then z.faites = z.faites + 1 end
    end
    for id in pairs(p.quetes or {}) do
        local z = parZone[tonumber(Lire("QuestDB", id, "zoneOrSort")) or 0]
        if z then z.enCours = z.enCours + 1 end
    end
    local continent = Continent()
    local px, py
    if continent then
        local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
        if type(pos) == "table" and pos.GetXY then px, py = pos:GetXY() end
    end
    local ici = NS.Appeler(NS.Lecture("GetRealZoneText"))
    for _, z in ipairs(zones) do
        z.nom = (z.zone > 0 and NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), z.zone)) or NS.L.ZONE_OTHER
        z.ici = z.nom == ici
        local total = #z.ids + z.faites + z.enCours
        z.pct = total > 0 and math.floor(z.faites * 100 / total + 0.5) or 0
        z.distance = 99
        if px then
            for k = 1, math.min(3, #z.ids) do
                local x, y = Position(z.ids[k].id, p, continent)
                if x then z.distance = math.min(z.distance, math.sqrt((x - px) ^ 2 + (y - py) ^ 2)) end
            end
        end
    end
    -- Le classement selon le niveau : l'ecart moyen des quetes au niveau du
    -- personnage (les plus adaptees d'abord), la zone ou l'on est en tete si
    -- elle en a ; a ecart egal, la plus proche. Dans chaque zone, les quetes
    -- de son niveau d'abord.
    local niv = tonumber(p.niveau) or 0
    for _, z in ipairs(zones) do
        local somme = 0
        for _, d in ipairs(z.ids) do somme = somme + math.abs(niv - d.niveau) end
        z.ecart = math.floor(somme / math.max(1, #z.ids) + 0.5)
        table.sort(z.ids, function(a, b)
            local ea, eb = math.abs(niv - a.niveau), math.abs(niv - b.niveau)
            if ea ~= eb then return ea < eb end
            return a.id < b.id
        end)
    end
    table.sort(zones, function(a, b)
        if a.ici ~= b.ici then return a.ici end
        if a.ecart ~= b.ecart then return a.ecart < b.ecart end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.niveauMin < b.niveauMin
    end)
    return zones
end

-- La part du niveau suivant qu'apporte une quantite d'XP (1 = atteint).
function dispo.PartDuSuivant(p, xp)
    local besoin = dispo.XPJusquA(p, (tonumber(p.niveau) or 0) + 1)
    if besoin <= 0 then return 1 end
    return (tonumber(xp) or 0) / besoin
end

-- Le plan vers un niveau, niveau par niveau : pour chaque niveau gagne, les
-- zones qui y menent (les plus adaptees et proches d'abord, sans les grises).
-- Renvoie { { niveau, jusqua, zones = { z... }, quetes, xp } }, XP manquante.
function dispo.PlanVers(p, vise)
    local besoin = dispo.XPJusquA(p, vise)
    local plan = {}
    if besoin <= 0 then return plan, 0 end
    local actuel = tonumber(p.niveau) or 0
    local cumul, paquet = 0, { zones = {}, quetes = 0, xp = 0 }
    for _, z in ipairs(dispo.Zones(p, false)) do
        if z.xp > 0 then
            table.insert(paquet.zones, z)
            paquet.quetes = paquet.quetes + #z.ids
            paquet.xp = paquet.xp + z.xp
            cumul = cumul + z.xp
            local atteint = math.min(math.floor(dispo.NiveauApres(p, cumul)), vise)
            if atteint > actuel then
                paquet.niveau, paquet.jusqua = actuel + 1, atteint
                table.insert(plan, paquet)
                paquet = { zones = {}, quetes = 0, xp = 0 }
                actuel = atteint
            end
            if actuel >= vise then break end
        end
    end
    return plan, math.max(0, besoin - cumul)
end
