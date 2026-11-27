local _, NS = ...

-- Guidage de QuestCore : le catalogue de ses objectifs, declare au moteur de
-- la suite (Core/Suite.lua). Chaque bouton guide un objectif precis et s'y
-- tient :
--   rendus {}                 toutes les quetes terminees du journal, dans
--                             l'ordre le plus rapide ; une quete terminee en
--                             route s'ajoute, une quete prise en route n'a
--                             aucun effet ; atteint quand plus rien n'est a
--                             rendre ;
--   quetes { ids }            exactement ces quetes : leurs objectifs, puis
--                             leur rendu ; atteint quand elles ont toutes
--                             quitte le journal ;
--   niveau { niveau = N }     les quetes qui menent au niveau N ; atteint au
--                             niveau N ;
--   parcours { uid }          un parcours enregistre (kit de donjon, suite...) ;
--                             atteint quand il est fini ou qu'il disparait.

NS.guidage = NS.guidage or {}
local guidage = NS.guidage
local L = NS.L

local function S() return NS.suite or _G.CoreSuite end

local function Moi()
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    return cle and NS.base.Perso(cle), cle
end

-- Carte du continent ou se trouve le personnage.
local function Continent()
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    for _ = 1, 6 do
        local info = carte and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
        if type(info) ~= "table" then return nil end
        if info.mapType == 2 then return carte end
        carte = info.parentMapID
    end
    return nil
end

local function Titre(id, moi)
    local q = moi and moi.quetes and moi.quetes[id]
    return (q and q.titre) or (NS.ref.Lire and NS.ref.Lire("QuestDB", id, "name")) or ("#" .. tostring(id))
end

-- Ou aller quand la prochaine quete est hors de portee (autre continent) :
-- sa quete, puis la zone et le continent, sous "Hors de portee".
local function OuAller(moi, ids)
    local info = NS.Lecture("C_Map.GetMapInfo")
    for _, id in ipairs(ids or {}) do
        local ok, points = pcall(NS.carte.PointsPour, id, moi)
        local pt = ok and points and points[1]
        local titre = Titre(id, moi)
        if not (pt and pt.carte and info) then return titre end
        local zone = NS.Appeler(info, pt.carte)
        local nomZone = type(zone) == "table" and zone.name or nil
        local continent
        local parent = type(zone) == "table" and zone.parentMapID
        for _ = 1, 4 do
            local z = parent and NS.Appeler(info, parent)
            if type(z) ~= "table" then break end
            if z.mapType == 2 then continent = z.name break end
            parent = z.parentMapID
        end
        local ou = nomZone and (continent and string.format("%s (%s)", nomZone, continent) or nomZone)
        return ou and (titre .. "\n|cffb3b3b3" .. string.format(L.GUIDE_GO_TO, ou) .. "|r") or titre
    end
    return nil
end

-- Le lieu ou aller pour une quete, en coordonnees du continent : chez le
-- receveur si elle est terminee, la ou se fait l'objectif si elle est en
-- cours, chez le donneur sinon. Une quete prise et pas finie ne renvoie
-- jamais chez son donneur ni chez son receveur : pour une quete de donjon,
-- pas meme quand ses objectifs sans lieu connu renvoient au receveur. Un
-- point dans une instance n'est jamais vise : a la place, l'entree du donjon
-- (celui de la quete, ou celui de l'instance ou tombe le point).
-- Un point d'objectif deja visite (on y est arrive) ne revient pas tant
-- que la quete n'est pas finie : un objectif a plusieurs lieux (deux puits,
-- trois caisses...) mene au suivant au lieu de rester sur le premier.
local function CleDePoint(id, x, y)
    return tostring(id) .. ":" .. math.floor((x or 0) * 1000) .. ":" .. math.floor((y or 0) * 1000)
end

local function PointDeQuete(id, moi, continent, jx, jy, utilises)
    local meilleur, lieu
    local ok, points = pcall(NS.carte.PointsPour, id, moi)
    local q = moi.quetes and moi.quetes[id]
    local voulu = (q and q.complete == true) and "rendre" or (q and "objectif") or "prendre"
    local enCours = q ~= nil and q.complete ~= true
    local D = NS.donjons
    local donjon = D and D.DeQuete and D.DeQuete(id)
    local EstInstance = NS.carte.EstInstance
    local entreesVues, entrees = {}, {}
    for _, pt in ipairs(ok and points or {}) do
        if EstInstance and pt.carte and EstInstance(pt.carte) then
            local e = NS.carte.EntreeDInstance and NS.carte.EntreeDInstance(pt.carte)
            if e and not entreesVues[e] then entreesVues[e] = true table.insert(entrees, e) end
        elseif pt.genre == voulu and not (enCours and donjon and pt.parReceveur) then
            local x, y = NS.carte.Reporter(pt, continent)
            local deja = voulu == "objectif" and utilises and x and utilises[CleDePoint(id, x, y)]
            if x and not deja then
                local d = (x - jx) ^ 2 + (y - jy) ^ 2
                if not meilleur or d < meilleur then
                    meilleur, lieu = d, { x = x, y = y, qui = pt.quoi, objectif = voulu == "objectif" or nil,
                        butin = (voulu == "objectif" and pt.icone == "butin") or nil }
                end
            end
        end
    end
    if lieu then return lieu end
    -- La base ne sait pas ou se font ses objectifs (quete propre au serveur,
    -- par exemple) : le point que le jeu lui-meme montre sur sa carte.
    if q then
        local carte, gx, gy
        local suivant = NS.Lecture("C_QuestLog.GetNextWaypoint")
        if suivant then
            local okW, c, x, y = pcall(suivant, id)
            if okW and type(c) == "number" and type(x) == "number" then carte, gx, gy = c, x, y end
        end
        if not carte then
            local poi = NS.Lecture("QuestPOIGetIconInfo")
            local carteJoueur = NS.Lecture("C_Map.GetBestMapForUnit")
            local okC, c = pcall(carteJoueur or function() end, "player")
            if poi and okC and c then
                local okP, _, x, y = pcall(poi, id)
                if okP and type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then carte, gx, gy = c, x, y end
            end
        end
        if carte and not (_G.issecretvalue and (_G.issecretvalue(gx) or _G.issecretvalue(gy))) then
            local x, y = NS.carte.Reporter({ carte = carte, x = gx, y = gy }, continent)
            if x and not (utilises and utilises[CleDePoint(id, x, y)]) then return { x = x, y = y, qui = nil, objectif = true } end
        end
    end
    -- A defaut : l'entree du donjon. Celui de la quete quand elle est prise
    -- et pas finie (ses objectifs sont dedans) ; sinon celui de l'instance ou
    -- tombent ses points (donneur ou receveur dedans), jamais une entree au
    -- hasard pour un receveur simplement loin.
    local cibles = {}
    if enCours and donjon then
        for _, e in ipairs(donjon.entrees or {}) do table.insert(cibles, { carte = e.carte, x = e.x, y = e.y, nom = donjon.nom }) end
    end
    for _, e in ipairs(entrees) do
        table.insert(cibles, { carte = e.carte, x = e.x, y = e.y, nom = (donjon and donjon.nom) or e.nom })
    end
    for _, e in ipairs(cibles) do
        local x, y = NS.carte.Reporter({ carte = e.carte, x = e.x, y = e.y }, continent)
        -- Entree sur la carte d'une ville ou d'une grotte : par sa zone.
        if not x and S() and S().Lieux and S().Lieux.VersZone then
            local zc, zx, zy = S().Lieux.VersZone(e.carte, e.x, e.y)
            if zc and zc ~= e.carte then x, y = NS.carte.Reporter({ carte = zc, x = zx, y = zy }, continent) end
        end
        if x then
            local dd = (x - jx) ^ 2 + (y - jy) ^ 2
            if not meilleur or dd < meilleur then meilleur, lieu = dd, { x = x, y = y, qui = e.nom, entree = e.nom or "?" } end
        end
    end
    return lieu
end

-- Sous la fleche : la quete, puis quoi y faire.
local function Qui(id, moi, lieu)
    local q = moi.quetes and moi.quetes[id]
    local quoi
    if lieu.entree then
        quoi = string.format(L.GUIDE_ENTER_DUNGEON, lieu.entree)
    elseif q and q.complete == true then
        quoi = string.format(L.GUIDE_DO_TURNIN, lieu.qui or "?")
    elseif q then
        for _, o in ipairs(q.objectifs or {}) do
            if not o.fait then quoi = tostring(o.texte or "") break end
        end
        -- Un objet qu'aucun monstre ne donne : comment l'obtenir, en bref.
        local a = NS.ref.ObjetsAObtenir and NS.ref.ObjetsAObtenir(moi, id)
        local api = _G.CraftCoreAPI
        if a and a[1] and api and api.ObtenirCourt then
            local ok, court = pcall(api.ObtenirCourt, a[1].objet, a[1].nom, a[1].manque)
            if ok and type(court) == "string" and court ~= "" then quoi = (quoi or "") .. " (" .. court .. ")" end
        end
    else
        quoi = string.format(L.GUIDE_DO_PICKUP, lieu.qui or "?")
        -- Quete grise (bas niveau) : le jeu ne montre pas son point
        -- d'exclamation si son affichage est coupe. On le dit, pour aller
        -- la prendre quand meme.
        local niveau = tonumber(NS.ref.Lire and NS.ref.Lire("QuestDB", id, "questLevel"))
        if niveau and moi.niveau and NS.ref.CouleurDeNiveau then
            local r, v, b = NS.ref.CouleurDeNiveau(niveau, moi.niveau)
            if r == 0.5 and v == 0.5 and b == 0.5 then quoi = quoi .. "  " .. L.GUIDE_LOW_LEVEL end
        end
    end
    return Titre(id, moi) .. (quoi and quoi ~= "" and ("\n|cffb3b3b3" .. quoi .. "|r") or "")
end

local Ailleurs

-- Le continent d'une carte (mapType 2), en remontant ses parents.
local function ContinentDe(carte)
    local info = NS.Lecture("C_Map.GetMapInfo")
    for _ = 1, 6 do
        local i = carte and info and NS.Appeler(info, carte)
        if type(i) ~= "table" then return nil end
        if i.mapType == 2 then return carte end
        carte = i.parentMapID
    end
    return nil
end
local function NomCarte(carte)
    local i = carte and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
    return type(i) == "table" and i.name or nil
end

-- La premiere quete qui a un lieu sur un autre continent : son point, en
-- coordonnees de ce continent, avec "Aller a : zone (continent)".
Ailleurs = function(ids, moi)
    for _, id in ipairs(ids) do
        local cartes = {}
        local ok, points = pcall(NS.carte.PointsPour, id, moi)
        for _, pt in ipairs(ok and points or {}) do if pt.carte then table.insert(cartes, pt.carte) end end
        local d = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
        for _, e in ipairs(d and d.entrees or {}) do table.insert(cartes, e.carte) end
        for _, pt in ipairs(ok and points or {}) do
            local e = pt.carte and NS.carte.EntreeDInstance and NS.carte.EntreeDInstance(pt.carte)
            if e then table.insert(cartes, e.carte) end
        end
        for _, carte in ipairs(cartes) do
            local continent = ContinentDe(carte)
            local lieu = continent and PointDeQuete(id, moi, continent, 0.5, 0.5)
            if lieu then
                local zone, nomC = NomCarte(carte), NomCarte(continent)
                local ou = zone and (nomC and string.format("%s (%s)", zone, nomC) or zone) or nomC
                return { carte = continent, x = lieu.x, y = lieu.y, cle = "q" .. id, id = id,
                    titre = Titre(id, moi), qui = ou and string.format(L.GUIDE_GO_TO, ou) or Qui(id, moi, lieu) }
            end
        end
    end
    return nil
end

-- Detours : des quetes a rendre ajoutees par le joueur a l'itineraire en
-- cours (petite carte sur la quete). Gardes par personnage, ils s'ajoutent
-- aux etapes de l'objectif guide, quel qu'il soit, et partent quand la quete
-- est rendue, quand le joueur les retire ou quand le guidage s'arrete.
local function Detours(moi)
    if type(moi) ~= "table" then return {} end
    moi.detours = type(moi.detours) == "table" and moi.detours or {}
    return moi.detours
end

-- Les etapes d'une liste de quetes, la plus proche d'abord, puis la plus
-- proche de la precedente.
-- Le compte montre (« Etape X sur Y ») : pour un itineraire, le numero de
-- l'etape visee dans l'itineraire, meme quand une autre etape passe avant
-- parce qu'elle est sur le chemin ; on sait toujours ou l'on en est.
local function Ajuster(ordre, compte)
    if type(compte) == "table" and compte.rangDe and type(ordre) == "table" and ordre[1] and ordre[1].id then
        local r = compte.rangDe(ordre[1].id)
        if r then return { fait = r - 1, total = compte.total } end
    end
    return compte
end

-- ---------------------------------------------------------------------------
-- Itineraire : la prochaine visite la plus rentable
-- ---------------------------------------------------------------------------
-- Les points faisables sont groupes en visites : tout ce qui se fait a moins
-- de PLAN.RAYON du meme endroit (rendre, prendre la suite, un autre donneur,
-- un objectif voisin) compte pour une seule visite. Chaque action a une
-- valeur ; une valeur obtenue plus tard compte moins (demi-vie
-- PLAN.DEMI_VIE). On essaie tous les enchainements de PLAN.HORIZON visites
-- parmi les PLAN.LARGEUR meilleures ; la premiere visite du meilleur est
-- visee. La cible d'avant compte 20 % plus pres (la meme regle que la
-- chaine) : elle ne change que pour nettement mieux, ou si quelque chose a
-- change (quete prise, rendue, objectif fini, lieu visite, sacs, journal).
--
-- Ce que le jeu impose, compte le long de chaque enchainement :
--   les sacs : places libres, objets gris (a vendre ou a jeter), butin
--   ordinaire a vendre, composants a poster ; chaque objectif prend la place
--   de ses objets de quete restants et du butin des monstres a tuer ; sans
--   la place, on jette du gris, sinon c'est un aller-retour chez le vendeur
--   le plus proche (ou, sans vendeur connu, l'objectif vaut moins) ;
--   les services pres d'une visite (QuestieDB : vendeur, reparation,
--   aubergiste, banquier, maitre de vol ; boites aux lettres) : on y vend et
--   on y poste dans la meme visite que les rendus ;
--   le temps d'un objectif : monstres a tuer, objets a ramasser ; sa valeur
--   compte quand il est fini, et son rendu compte la ou se trouve son
--   receveur (dans la suite de l'enchainement, ou apres) ;
--   une quete a un ou deux objets pres, sur place, vaut plus d'etre finie
--   maintenant ;
--   les vols connus du personnage (relus a l'ouverture de la carte des vols)
--   raccourcissent les longs trajets.
-- Rien n'est jamais appele qui agisse : ce n'est que de la lecture.
local PLAN = {
    VITESSE = 7,        -- yards par seconde, a pied (comme la duree de la fleche)
    RAYON = 40,         -- une meme visite : un camp, le centre d'un village
    T_VISITE = 5,       -- secondes sur place par visite
    T_ACTION = 3,       -- et par action (parler, accepter, rendre)
    T_DONJON = 900,     -- un donjon : un quart d'heure au moins
    DEMI_VIE = 180,     -- une action dans 3 minutes vaut moitie moins
    HORIZON = 3,        -- visites planifiees a l'avance
    LARGEUR = 6,        -- parmi les 6 meilleures visites prises seules
    GARDE = 0.8,        -- le trajet vers la cible d'avant compte 20 % de moins
    V_RENDRE = 1.0, V_OBJECTIF = 0.7, V_PRENDRE = 0.5, V_DONJON = 0.5,
    V_SUITE = 0.3,      -- par suite debloquee : la chaine continue
    V_SUITE_ICI = 0.5,  -- et sa prise sur place, dans la meme visite
    V_ORDRE = 0.2,      -- la visite qui porte l'etape suivante de l'itineraire
    V_SAC = 0.5,        -- par place liberee par un rendu, sacs presque pleins (sacs illisibles)
    V_PLACE = 0.25,     -- par place de marge regagnee dans une visite, sacs presque pleins
    SAC_SEUIL = 6,      -- la pression des sacs commence sous 6 places libres
    BUTIN_PLEIN = 0.3,  -- un objectif a ramasser, sacs pleins (sacs illisibles)
    V_JOURNAL = 0.3,    -- un rendu, journal presque plein
    JOURNAL_MAX = 20,
    V_NIVEAU = 0.5,     -- par etape que le niveau gagne rend prenable (2 au plus)
    ECHELLE = 30000,    -- yards par unite de carte de continent, si le jeu ne le dit pas
    -- Le temps d'un objectif.
    T_TUER = 20,        -- secondes par monstre : le trouver, le tuer, le depouiller
    TAUX_BUTIN = 0.5,   -- un monstre sur deux donne l'objet de quete
    T_RAMASSER = 12,    -- secondes par objet ramasse ou utilise dans le monde
    T_OBJ_MAX = 600,    -- un objectif ne compte jamais plus de 10 minutes
    PRESQUE = 2,        -- « presque fini » : 2 unites ou moins
    V_PRESQUE = 1.0,    -- et sur place (premiere visite) : il vaut un rendu de plus
    SUR_PLACE = 100,    -- yards
    -- Les sacs.
    BRIC = 0.25,        -- places prises par le butin ordinaire, par monstre tue
    EMPILE = 20,        -- empilement d'un objet de quete inconnu du jeu
    T_JETER = 4,        -- secondes par objet gris jete
    PERTE_JETER = 0.03, -- et ce qu'on y perd (argent)
    FACT_GRIS = 0.6,    -- une place grise vaut 60 % d'une place libre
    PEN_SAC = 0.5,      -- finir l'enchainement les sacs pleins (marge nulle)
    SACS_TTL = 1,       -- secondes de relecture des sacs
    -- Les services.
    RAYON_SERVICE = 60, -- un service a moins de 60 yards fait partie de la visite
    VENDEUR_LOIN = 1500,-- au-dela, pas d'aller-retour chez le vendeur
    CELLULE = 150,      -- grille des services, en yards
    LOT = 300,          -- PNJ lus par image pendant la lecture des services
    VENTE_SOUS = 12,    -- on vend quand il reste moins de 12 places libres
    T_VENTE = 10, T_POSTER = 25, T_REPARER = 5,
    USURE = 0.25,       -- reparer sous 25 % de durabilite
    V_REPARER = 0.4,
    VOL_VITESSE = 25,   -- yards par seconde en vol, detours compris
    T_VOL = 30,         -- parler, decoller, atterrir
    VOL_MIN = 700,      -- pas de vol pour moins de 700 yards
    -- Ce qui reste apres l'enchainement : il faudra y aller. Les RESIDU_N
    -- meilleures visites non faites comptent depuis le dernier lieu atteint,
    -- a RESIDU de leur valeur : partir loin pour une seule action coute le
    -- retour vers tout le reste.
    RESIDU = 0.5, RESIDU_N = 4,
    -- Itineraire de zone : un rendu hors de la zone attend que la zone soit
    -- finie (il est fait en la quittant), meme s'il debloque une suite.
    F_HORS_ZONE = 0.02,
}

-- Yards par unite de la carte du continent, en x et en y.
local echelles = {}
local function Echelle(continent)
    local e = echelles[continent]
    if e then return e[1], e[2] end
    local Li = S() and S().Lieux
    if Li and Li.Monde then
        local ok0, a0, b0 = pcall(Li.Monde, continent, 0, 0)
        local ok1, a1, b1 = pcall(Li.Monde, continent, 1, 0)
        local ok2, a2, b2 = pcall(Li.Monde, continent, 0, 1)
        if ok0 and ok1 and ok2 and a0 and a1 and a2 then
            local sx = math.sqrt((a1 - a0) ^ 2 + (b1 - b0) ^ 2)
            local sy = math.sqrt((a2 - a0) ^ 2 + (b2 - b0) ^ 2)
            if sx > 0 and sy > 0 then echelles[continent] = { sx, sy } return sx, sy end
        end
    end
    return PLAN.ECHELLE, PLAN.ECHELLE
end

local function Yards(a, b, sx, sy)
    return math.sqrt(((a.x - b.x) * sx) ^ 2 + ((a.y - b.y) * sy) ^ 2)
end

-- XP d'une quete : celle du journal, sinon la base.
local function XPDe(id, moi)
    local q = moi.quetes and moi.quetes[id]
    local connue = q and q.recompenses and tonumber(q.recompenses.xp)
    if connue and connue > 0 then return connue end
    local ok, xp = pcall(NS.ref.XPDeLaBase, id, moi.niveau)
    return ok and tonumber(xp) or nil
end

-- Le poids d'une quete : son XP rapportee a la mediane des quetes visees,
-- entre 0,5 et 2 (1 si elle est inconnue).
local function Poids(xp, ref)
    if not (xp and ref and ref > 0) then return 1 end
    return math.max(0.5, math.min(2, xp / ref))
end

-- Une suite que le rendu de `rendue` rend prenable (et qui ne l'est pas deja).
local function PrenableApres(moi, s, rendue)
    if (moi.faites and moi.faites[s]) or (moi.quetes and moi.quetes[s]) then return false end
    if NS.parcours.Prenable(moi, s) then return false end
    local niveau = tonumber(NS.ref.Lire("QuestDB", s, "requiredLevel")) or 0
    if moi.niveau and niveau > moi.niveau then return false end
    local groupe, une = NS.ref.Prerequis(s)
    local function Fait(x) return x == rendue or (moi.faites and moi.faites[x] == true) end
    for _, x in ipairs(groupe) do if not Fait(x) then return false end end
    if #une > 0 then
        for _, x in ipairs(une) do if Fait(x) then return true end end
        return false
    end
    return true
end

-- Les suites debloquees par un rendu, et si leur donneur est sur place.
local function SuitesDebloquees(pt, moi, continent, sx, sy, cache)
    if cache[pt.id] then return cache[pt.id] end
    local res = {}
    local ok, suites = pcall(NS.ref.Suites, pt.id)
    for _, s in ipairs(ok and suites or {}) do
        if #res >= 3 then break end
        if PrenableApres(moi, s, pt.id) then
            local ici = false
            local okP, dons = pcall(NS.carte.PointsPour, s, moi)
            for _, d in ipairs(okP and dons or {}) do
                if d.genre == "prendre" then
                    local x, y = NS.carte.Reporter(d, continent)
                    if x and Yards({ x = x, y = y }, pt, sx, sy) <= PLAN.RAYON then ici = true break end
                end
            end
            table.insert(res, { id = s, ici = ici, xp = XPDe(s, moi) })
        end
    end
    cache[pt.id] = res
    return res
end

-- ---------------------------------------------------------------------------
-- Services : vendeurs, reparation, aubergistes, banquiers, maitres de vol
-- (drapeaux des PNJ de QuestieDB) et boites aux lettres (objets de la base).
-- Lus une fois, par lots, la premiere fois qu'un itineraire est guide ; puis
-- reportes sur chaque continent, dans une grille.
-- ---------------------------------------------------------------------------
local DRAPEAUX = { { "vendeur", 4 }, { "vol", 8 }, { "auberge", 128 }, { "banque", 256 }, { "reparation", 16384 } }
-- Les boites aux lettres de la base de WoW Forever (ObjectDB, nom « Mailbox »).
local BOITES = {
    32349, 142075, 142089, 142093, 142094, 142095, 142102, 142103, 142109, 142110, 142111, 142117,
    142119, 143981, 143982, 143983, 143984, 143985, 143986, 143987, 143988, 143989, 143990, 144011,
    144112, 144125, 144126, 144127, 144128, 144129, 144130, 144131, 144179, 153578, 153716, 157637,
    163313, 163645, 164618, 164840, 171556, 171699, 171752, 173047, 173221, 176319, 176324, 176404,
    177044, 178864, 179895, 179896, 180451, 181236, 181380, 181381, 181639, 182567, 182939, 182946,
    183167, 184085, 184147, 184148, 184652, 184944, 185477, 186230, 186629, 556646, 556693, 560880,
    560881, 560883, 560884, 560885, 560886, 560887, 560888, 560901, 561073, 561074, 561075, 602722,
    642744, 642745, 644436, 644437, 644438, 644439, 644440, 644441, 644488, 650428, 650577, 650593,
    650666, 651604, 652323, 652324, 655669, 656700, 656748, 658827, 658919, 658920, 658921, 658922,
    658923, 658924, 658925, 658926, 658927, 658970, 659159, 659816, 659829, 659837, 696264, 696265,
    696266, 696267, 696268, 696269, 696270, 696271, 696272, 696273, 696274, 696275, 696276, 696277,
    696278, 696279, 696280, 696281, 696374, 696434, 696607, 696751, 703257, 703896,
}
local services = { liste = nil, file = nil, rang = 1, continents = {} }

local function ADrapeau(f, b) return math.floor(f / b) % 2 == 1 end

local function MonCamp()
    local camp = NS.Appeler(NS.Lecture("UnitFactionGroup"), "player")
    return camp == "Alliance" and "A" or (camp == "Horde" and "H" or nil)
end

-- Les lieux d'une fiche de la base ({ [zone] = { { x, y }, ... } }).
local function AjouterLieux(liste, lieux, genres)
    if type(lieux) ~= "table" or not (NS.carte and NS.carte.CarteDeZone) then return end
    for zone, pts in pairs(lieux) do
        local carte = tonumber(zone) and NS.carte.CarteDeZone(tonumber(zone))
        if carte and type(pts) == "table" then
            for _, p in ipairs(pts) do
                local x, y = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
                if x and y and x >= 0 and y >= 0 then
                    table.insert(liste, { carte = carte, x = x / 100, y = y / 100, g = genres })
                end
            end
        end
    end
end

-- Un PNJ : ses services, s'il en rend et qu'il est amical (nil : hostile aux deux).
local function LirePNJ(liste, id, camp)
    local f = tonumber(NS.ref.Lire("NpcDB", id, "npcFlags"))
    if not f or f < 4 then return end
    local genres
    for _, d in ipairs(DRAPEAUX) do
        if ADrapeau(f, d[2]) then genres = genres or {} genres[d[1]] = true end
    end
    if not genres then return end
    local amical = NS.ref.Lire("NpcDB", id, "friendlyToFaction")
    if type(amical) ~= "string" or (camp and not string.find(amical, camp, 1, true)) then return end
    AjouterLieux(liste, NS.ref.Lire("NpcDB", id, "spawns"), genres)
end

-- Lit `n` PNJ de plus ; vrai quand tout est lu.
local function Avancer(n)
    local s = services
    if s.liste then return true end
    if not s.file then
        s.file, s.lu, s.rang, s.camp = {}, {}, 1, MonCamp()
        local base = NS.ref.Base and NS.ref.Base("NpcDB")
        local ok, ids = false, nil
        if type(base) == "table" and type(base.GetAllIds) == "function" then ok, ids = pcall(base.GetAllIds) end
        for k, v in pairs(ok and type(ids) == "table" and ids or {}) do
            local id = type(v) == "number" and v or (type(k) == "number" and k) or nil
            if id then table.insert(s.file, id) end
        end
        table.sort(s.file)
        for _, id in ipairs(BOITES) do
            pcall(AjouterLieux, s.lu, NS.ref.Lire("ObjectDB", id, "spawns"), { courrier = true })
        end
    end
    local fin = math.min(#s.file, s.rang + n - 1)
    for i = s.rang, fin do pcall(LirePNJ, s.lu, s.file[i], s.camp) end
    s.rang = fin + 1
    if s.rang > #s.file then s.liste, s.file, s.lu = s.lu, nil, nil return true end
    return false
end

-- La lecture par lots, hors combat, une seule fois.
local function DemarrerServices()
    if services.liste or services.cadre then return end
    local CF = _G.CreateFrame
    if type(CF) ~= "function" then return end
    local ok, cadre = pcall(CF, "Frame")
    if not ok or type(cadre) ~= "table" or not cadre.SetScript then return end
    services.cadre = cadre
    cadre:SetScript("OnUpdate", function(self)
        local combat = NS.Lecture("InCombatLockdown")
        if combat and combat() then return end
        local okA, fini = pcall(Avancer, PLAN.LOT)
        if not okA then services.liste = services.liste or {} end
        if not okA or fini then self:SetScript("OnUpdate", nil) end
    end)
end

local function Grille(liste, sx, sy)
    local cell = PLAN.CELLULE
    local gr = { cell = cell, sx = sx, sy = sy, cases = {} }
    for _, e in ipairs(liste) do
        local k = math.floor(e.x * sx / cell) .. ":" .. math.floor(e.y * sy / cell)
        gr.cases[k] = gr.cases[k] or {}
        table.insert(gr.cases[k], e)
    end
    return gr
end

-- Les services du continent, en grille (nil tant qu'ils ne sont pas lus).
local function ServicesDuContinent(continent, sx, sy)
    if not services.liste then DemarrerServices() return nil end
    local c = services.continents[continent]
    if c then return c end
    local liste = {}
    for _, e in ipairs(services.liste) do
        local x, y = NS.carte.Reporter(e, continent)
        if x then table.insert(liste, { x = x, y = y, g = e.g }) end
    end
    table.sort(liste, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    c = Grille(liste, sx, sy)
    services.continents[continent] = c
    return c
end

-- La distance (yards) du service `genre` le plus proche de `p`, a moins de
-- `rayon`, ou nil.
local function Proche(gr, p, genre, rayon)
    if not gr then return nil end
    local cell = gr.cell
    local cx, cy = math.floor(p.x * gr.sx / cell), math.floor(p.y * gr.sy / cell)
    local r = math.ceil(rayon / cell)
    local best
    for dx = -r, r do
        for dy = -r, r do
            local case = gr.cases[(cx + dx) .. ":" .. (cy + dy)]
            for _, e in ipairs(case or {}) do
                if e.g[genre] then
                    local d = Yards(p, e, gr.sx, gr.sy)
                    if d <= rayon and (not best or d < best) then best = d end
                end
            end
        end
    end
    return best
end

-- Les vols connus du personnage, notes a chaque ouverture de la carte des vols.
local function NoterVols()
    local moi = Moi()
    if type(moi) ~= "table" then return end
    local carte = NS.Appeler(NS.Lecture("GetTaxiMapID"))
    if not carte then return end
    moi.volsConnus = type(moi.volsConnus) == "table" and moi.volsConnus or {}
    local tous = NS.Lecture("C_TaxiMap.GetAllTaxiNodes")
    local noeuds = tous and NS.Appeler(tous, carte)
    if type(noeuds) == "table" then
        for _, n in ipairs(noeuds) do
            local pos = type(n) == "table" and n.position
            local x, y = type(pos) == "table" and tonumber(pos.x), type(pos) == "table" and tonumber(pos.y)
            if n.nodeID and x and y and n.state ~= 2 then
                moi.volsConnus[n.nodeID] = { carte = carte, x = x, y = y, nom = n.name }
            end
        end
        return
    end
    local nb = tonumber((NS.Appeler(NS.Lecture("NumTaxiNodes")))) or 0
    for i = 1, nb do
        local genre = NS.Appeler(NS.Lecture("TaxiNodeGetType"), i)
        local x, y = NS.Appeler(NS.Lecture("TaxiNodePosition"), i)
        local nom = NS.Appeler(NS.Lecture("TaxiNodeName"), i)
        if (genre == "CURRENT" or genre == "REACHABLE") and tonumber(x) and tonumber(y) and nom then
            moi.volsConnus[nom] = { carte = carte, x = tonumber(x), y = tonumber(y), nom = nom }
        end
    end
end
pcall(function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("TAXIMAP_OPENED")
    f:SetScript("OnEvent", function() pcall(NoterVols) end)
end)

local function VolsDuContinent(moi, continent)
    local res = {}
    for _, v in pairs(type(moi.volsConnus) == "table" and moi.volsConnus or {}) do
        local x, y = NS.carte.Reporter(v, continent)
        if x then table.insert(res, { x = x, y = y }) end
    end
    table.sort(res, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    return #res >= 2 and res or nil
end

-- Le temps d'un trajet : a pied, ou par deux vols connus si c'est plus court.
local function VolProche(p, ctx)
    if p.volPour ~= ctx.vols then
        local best, bd
        for _, v in ipairs(ctx.vols) do
            local d = Yards(p, v, ctx.sx, ctx.sy)
            if not bd or d < bd then best, bd = v, d end
        end
        p.volPour, p.vol, p.volD = ctx.vols, best, bd
    end
    return p.vol, p.volD
end
local function Trajet(a, b, ctx)
    local d = Yards(a, b, ctx.sx, ctx.sy)
    local t = d / PLAN.VITESSE
    if ctx.vols and d > PLAN.VOL_MIN then
        local va, da = VolProche(a, ctx)
        local vb, db = VolProche(b, ctx)
        if va and vb and va ~= vb then
            local tv = (da + db) / PLAN.VITESSE + Yards(va, vb, ctx.sx, ctx.sy) / PLAN.VOL_VITESSE + PLAN.T_VOL
            if tv < t then return tv end
        end
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Les sacs et l'equipement (lecture seule)
-- ---------------------------------------------------------------------------
-- { libres, gris (qualite 0 : a vendre ou a jeter), divers (butin ordinaire
-- blanc a vendre), marchandises (composants non lies : a poster ou a mettre
-- en banque), parObjet = { [objet] = { places, n } } }, ou nil.
local sacsMemo, sacsQuand
local function LireSacs()
    local maintenant = tonumber((NS.Appeler(NS.Lecture("GetTime")))) or 0
    if sacsMemo and sacsQuand and maintenant >= sacsQuand and maintenant - sacsQuand < PLAN.SACS_TTL then return sacsMemo end
    local libresF = NS.Lecture("C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots")
    local placesF = NS.Lecture("C_Container.GetContainerNumSlots", "GetContainerNumSlots")
    local infoF = NS.Lecture("C_Container.GetContainerItemInfo", "GetContainerItemInfo")
    if not (libresF and placesF and infoF) then return nil end
    local instant = NS.Lecture("C_Item.GetItemInfoInstant", "GetItemInfoInstant")
    local s = { libres = 0, gris = 0, divers = 0, marchandises = 0, parObjet = {} }
    for sac = 0, 4 do
        local ok, libres, famille = pcall(libresF, sac)
        if ok and tonumber(libres) and (famille == nil or famille == 0) then
            s.libres = s.libres + tonumber(libres)
            local okN, n = pcall(placesF, sac)
            for place = 1, (okN and tonumber(n)) or 0 do
                local okI, a, b, _, d, _, _, _, _, i9, i10 = pcall(infoF, sac, place)
                local id, nb, qualite, sansValeur, lie
                if okI and type(a) == "table" then
                    id, nb, qualite, sansValeur, lie = a.itemID, a.stackCount, a.quality, a.hasNoValue, a.isBound
                elseif okI and a ~= nil then
                    id, nb, qualite, sansValeur = i10, b, d, i9
                end
                id = tonumber(id)
                if id then
                    local o = s.parObjet[id] or { places = 0, n = 0 }
                    s.parObjet[id] = o
                    o.places, o.n = o.places + 1, o.n + (tonumber(nb) or 1)
                    local classe = instant and select(6, NS.Appeler(instant, id))
                    if qualite == 0 then s.gris = s.gris + 1
                    elseif classe == 12 then -- objet de quete : il part au rendu
                    elseif classe == 7 and not lie then s.marchandises = s.marchandises + 1
                    elseif classe == 15 and (tonumber(qualite) or 1) <= 1 and not sansValeur then s.divers = s.divers + 1 end
                end
            end
        end
    end
    sacsMemo, sacsQuand = s, maintenant
    return s
end

-- La plus basse durabilite de l'equipement porte (0 a 1), ou nil.
local function LireUsure()
    local f = NS.Lecture("GetInventoryItemDurability")
    if not f then return nil end
    local mini
    for place = 1, 18 do
        local ok, c, m = pcall(f, place)
        c, m = ok and tonumber(c), ok and tonumber(m)
        if c and m and m > 0 and (not mini or c / m < mini) then mini = c / m end
    end
    return mini
end
guidage.LireSacs, guidage.LireUsure = LireSacs, LireUsure

-- Combien d'un objet tiennent dans une place (nil si le jeu ne le sait pas).
local function Empile(objet)
    if not objet then return nil end
    local n = tonumber((NS.Appeler(NS.Lecture("C_Item.GetItemMaxStackCount"), objet)))
    if not n then n = tonumber((select(8, NS.Appeler(NS.Lecture("C_Item.GetItemInfo", "GetItemInfo"), objet)))) end
    return (n and n > 0) and n or nil
end

-- ---------------------------------------------------------------------------
-- Les points : genre, valeur, temps, place dans les sacs
-- ---------------------------------------------------------------------------

-- Le receveur d'une quete, en coordonnees du continent (le plus pres du point).
local function Receveur(pt, continent, ctx, cache)
    if cache[pt.id] ~= nil then return cache[pt.id] or nil end
    local best, bd
    local fin = NS.ref.Lire("QuestDB", pt.id, "finishedBy")
    for k, base in ipairs({ "NpcDB", "ObjectDB" }) do
        for _, qui in ipairs(type(fin) == "table" and type(fin[k]) == "table" and fin[k] or {}) do
            local lieux = {}
            AjouterLieux(lieux, NS.ref.Lire(base, qui, "spawns"), {})
            for _, l in ipairs(lieux) do
                local x, y = NS.carte.Reporter(l, continent)
                if x then
                    local d = Yards({ x = x, y = y }, pt, ctx.sx, ctx.sy)
                    if not bd or d < bd then best, bd = { x = x, y = y }, d end
                end
            end
        end
    end
    cache[pt.id] = best or false
    return best
end

-- Ce qu'il reste a faire d'une quete en cours : unites, temps, places.
local function Besoins(pt, moi, ctx)
    local q = moi.quetes and moi.quetes[pt.id]
    if type(q) ~= "table" or type(q.objectifs) ~= "table" then return end
    local sac = ctx.sac
    local okB, base = pcall(NS.ref.ObjetsRequis, moi, pt.id)
    base = okB and type(base) == "table" and base or {}
    local rangObjet, tuer, ramasser, places, restant, placesQ = 0, 0, 0, 0, 0, 0
    for _, o in ipairs(q.objectifs) do
        local req, n = tonumber(o.requis) or 0, tonumber(o.n) or 0
        local objet
        if o.type == "item" then
            rangObjet = rangObjet + 1
            objet = tonumber(o.objet) or (base[rangObjet] and tonumber(base[rangObjet].objet))
        end
        if not o.fait and req > n then
            local r = req - n
            restant = restant + r
            if o.type == "item" then
                local pile = Empile(objet) or (req == 1 and 1) or PLAN.EMPILE
                local tenu = sac and objet and sac.parObjet[objet]
                local deja = tenu and tenu.places or math.ceil(n / pile)
                placesQ = placesQ + math.max(deja, math.ceil(req / pile))
                places = places + math.max(0, math.ceil(req / pile) - deja)
                local pnj = objet and NS.ref.Lire("ItemDB", objet, "npcDrops")
                local obj = objet and NS.ref.Lire("ItemDB", objet, "objectDrops")
                if type(pnj) == "table" and #pnj > 0 then tuer = tuer + r / PLAN.TAUX_BUTIN
                elseif type(obj) == "table" and #obj > 0 then ramasser = ramasser + r end
            elseif o.type == "monster" then tuer = tuer + r
            else ramasser = ramasser + r end
        end
    end
    pt.restant, pt.placesQ = restant, placesQ
    pt.besoin = places + math.ceil(tuer * PLAN.BRIC - 1e-9)
    -- Du butin sans quantite connue : une place au moins.
    if restant == 0 and pt.butin then pt.besoin = 1 end
    pt.temps = math.min(PLAN.T_OBJ_MAX, tuer * PLAN.T_TUER + ramasser * PLAN.T_RAMASSER)
    pt.presque = restant > 0 and restant <= PLAN.PRESQUE or nil
end

-- Les places que libere un rendu : celles de ses objets de quete.
local function Liberees(pt, moi, ctx)
    local q = moi.quetes and moi.quetes[pt.id]
    local okB, base = pcall(NS.ref.ObjetsRequis, moi, pt.id)
    base = okB and type(base) == "table" and base or {}
    local n, rang = 0, 0
    for _, o in ipairs(q and q.objectifs or {}) do
        if o.type == "item" then
            rang = rang + 1
            local objet = tonumber(o.objet) or (base[rang] and tonumber(base[rang].objet))
            local tenu = ctx.sac and objet and ctx.sac.parObjet[objet]
            if tenu then n = n + tenu.places
            elseif not ctx.sac then n = n + 1 end
        end
    end
    return n
end

-- Ce que chaque point fait, et son identite (stable quand le lieu bouge).
local function Qualifier(points, moi, ctx)
    for _, pt in ipairs(points) do
        if pt.entree then pt.genre = "entree"
        elseif pt.objectif then pt.genre = "objectif"
        elseif pt.etatQuete == "rendre" then pt.genre = "rendre"
        else pt.genre = "prendre" end
        pt.ident = pt.entree and pt.cle or ("q" .. tostring(pt.id) .. ":" .. pt.genre)
        pt.xp = XPDe(pt.id, moi)
        pt.rang = ctx.rangDe and ctx.rangDe(pt.id) or nil
        if pt.genre == "rendre" then
            pt.libere = Liberees(pt, moi, ctx)
        elseif pt.genre == "objectif" then
            pcall(Besoins, pt, moi, ctx)
        elseif pt.genre == "prendre" then
            -- Une quete qui donne son objet en la prenant : une place.
            pt.besoin = NS.ref.Lire("QuestDB", pt.id, "sourceItemId") and 1 or 0
        end
    end
end

-- Sacs, journal, niveau : ce qui pese sur toutes les visites.
local function Contexte(moi, points, compte)
    local ctx = { rangDe = type(compte) == "table" and compte.rangDe or nil }
    local okS, sac = pcall(guidage.LireSacs)
    ctx.sac = okS and type(sac) == "table" and sac or nil
    local okU, usure = pcall(guidage.LireUsure)
    ctx.usure = okU and tonumber(usure) or nil
    Qualifier(points, moi, ctx)
    local xps = {}
    for _, pt in ipairs(points) do
        if pt.xp and pt.xp > 0 then table.insert(xps, pt.xp) end
        if pt.rang and (not ctx.rangMin or pt.rang < ctx.rangMin) then ctx.rangMin = pt.rang end
    end
    table.sort(xps)
    ctx.xpRef = xps[math.floor((#xps + 1) / 2)]
    local libres = ctx.sac and ctx.sac.libres or (NS.PlacesLibres and NS.PlacesLibres())
    ctx.pression = libres and math.max(0, (PLAN.SAC_SEUIL - libres) / PLAN.SAC_SEUIL) or 0
    ctx.sacsPleins = libres == 0
    local function Palier(n) return (n == nil and "?") or (n == 0 and "0") or (n <= 2 and "2") or (n < PLAN.SAC_SEUIL and "6") or "+" end
    ctx.palierSacs = Palier(libres) .. "/" .. Palier(libres and libres + (ctx.sac and ctx.sac.gris or 0))
    local n = 0
    for _ in pairs(moi.quetes or {}) do n = n + 1 end
    local maxi = tonumber((NS.Appeler(NS.Lecture("C_QuestLog.GetMaxNumQuestsCanAccept")))) or PLAN.JOURNAL_MAX
    ctx.journalPlein = n >= maxi
    ctx.journalPresquePlein = n >= maxi - 2
    ctx.palierJournal = ctx.journalPlein and "plein" or (ctx.journalPresquePlein and "presque" or "ok")
    -- Le niveau que les rendus feraient gagner : les etapes qu'il ouvre.
    ctx.xpManquante = NS.disponibles and NS.disponibles.XPManquante and NS.disponibles.XPManquante() or nil
    ctx.debloqueNiveau = 0
    if type(compte) == "table" and type(compte.etapes) == "table" and moi.niveau then
        for k, id in ipairs(compte.etapes) do
            if k > 40 then break end
            if NS.parcours.EtatEtape(moi, id) == "attente"
                and tonumber(NS.ref.Lire("QuestDB", id, "requiredLevel")) == moi.niveau + 1
                and NS.parcours.PrerequisRemplis(moi, id) then
                ctx.debloqueNiveau = ctx.debloqueNiveau + 1
            end
        end
    end
    return ctx
end

local function ValeurAction(pt, ctx)
    if pt.horsZone and ctx.zoneActive then return PLAN.F_HORS_ZONE end
    local b = Poids(pt.xp, ctx.xpRef)
    if pt.genre == "rendre" then
        local v = PLAN.V_RENDRE * b
        -- Sacs illisibles : l'ancienne estimation (sinon, les sacs se comptent
        -- le long de l'enchainement).
        if not ctx.sac then v = v + ctx.pression * PLAN.V_SAC * (pt.libere or 0) end
        if ctx.journalPresquePlein then v = v + PLAN.V_JOURNAL end
        for _, s in ipairs(pt.suites or {}) do
            v = v + PLAN.V_SUITE
            if s.ici then v = v + PLAN.V_SUITE_ICI * Poids(s.xp, ctx.xpRef) end
        end
        return v
    elseif pt.genre == "prendre" then
        return ctx.journalPlein and 0 or PLAN.V_PRENDRE * b
    elseif pt.genre == "objectif" then
        local v = PLAN.V_OBJECTIF * b
        if pt.butin and ctx.sacsPleins and not ctx.sac then v = v * PLAN.BUTIN_PLEIN end
        return v
    end
    return PLAN.V_DONJON * math.max(1, #(pt.ids or {}))
end

-- Dans une visite : rendre, puis prendre (la suite est prenable une fois
-- rendue), puis les objectifs ; puis l'ordre de l'itineraire.
local ORDRE_GENRE = { rendre = 1, prendre = 2, objectif = 3, entree = 4 }
local function AvantDans(a, b)
    local ga, gb = ORDRE_GENRE[a.genre] or 9, ORDRE_GENRE[b.genre] or 9
    if ga ~= gb then return ga < gb end
    local ra, rb = a.rang or 1e9, b.rang or 1e9
    if ra ~= rb then return ra < rb end
    return a.ident < b.ident
end

local function Demi(t) return 0.5 ^ (t / PLAN.DEMI_VIE) end

local function Grappes(points, ctx)
    local tries = {}
    for _, pt in ipairs(points) do table.insert(tries, pt) end
    table.sort(tries, AvantDans)
    local grappes = {}
    for _, pt in ipairs(tries) do
        local g
        if pt.genre ~= "entree" then
            for _, h in ipairs(grappes) do
                if not h.entree and Yards(h, pt, ctx.sx, ctx.sy) <= PLAN.RAYON then g = h break end
            end
        end
        if not g then
            g = { x = pt.x, y = pt.y, actions = {}, entree = (pt.genre == "entree") or nil, cle = pt.ident }
            table.insert(grappes, g)
        end
        table.insert(g.actions, pt)
    end
    for _, g in ipairs(grappes) do
        local vA, xpRendue, suivante = 0, 0, false
        g.objs, g.libere, g.prise = {}, 0, 0
        for _, a in ipairs(g.actions) do
            local v = ValeurAction(a, ctx)
            if a.genre == "objectif" then
                local b = Poids(a.xp, ctx.xpRef)
                table.insert(g.objs, { v = v, temps = a.temps or 0, besoin = a.besoin or (a.butin and 1 or 0),
                    presque = a.presque, poids = b, recv = a.receveur, vRendu = PLAN.V_RENDRE * b, ident = a.ident,
                    placesQ = a.placesQ or 0 })
            else
                vA = vA + v
                if a.genre == "rendre" then g.libere = g.libere + (a.libere or 0) end
                if a.genre == "prendre" and not ctx.journalPlein then g.prise = g.prise + (a.besoin or 0) end
            end
            if a.genre == "rendre" then xpRendue = xpRendue + (a.xp or 0) end
            if ctx.rangMin and a.rang == ctx.rangMin then suivante = true end
        end
        if suivante then vA = vA + PLAN.V_ORDRE end
        if ctx.xpManquante and xpRendue > 0 and xpRendue >= ctx.xpManquante then
            vA = vA + PLAN.V_NIVEAU * math.min(2, ctx.debloqueNiveau or 0)
        end
        g.vA = vA
        local vO, tO = 0, 0
        for _, o in ipairs(g.objs) do tO = tO + o.temps vO = vO + o.v * Demi(tO) end
        g.valeur = vA + vO
        g.duree = PLAN.T_VISITE + PLAN.T_ACTION * #g.actions + (g.entree and PLAN.T_DONJON or 0)
        if not g.entree and ctx.grille then
            local R = PLAN.RAYON_SERVICE
            g.vendeur = Proche(ctx.grille, g, "vendeur", R) ~= nil
            g.courrier = Proche(ctx.grille, g, "courrier", R) ~= nil
            g.banque = Proche(ctx.grille, g, "banque", R) ~= nil
            g.reparation = Proche(ctx.grille, g, "reparation", R) ~= nil
        end
    end
    return grappes
end

-- Le vendeur le plus proche d'une visite, pour un aller-retour (yards ou nil).
local function VendeurLoin(g, ctx)
    if g.loin == nil then g.loin = Proche(ctx.grille, g, "vendeur", PLAN.VENDEUR_LOIN) or false end
    return g.loin or nil
end

-- Une visite a l'instant `arrivee`, sacs `s` (nil : sacs illisibles) et
-- objectifs finis plus tot dont le rendu attend (`attente`). Rend les sacs
-- apres, la duree, le gain, les objectifs en attente et ce qui s'y fait.
local function Visiter(g, arrivee, s, attente, ctx, surPlace)
    local duree = g.duree
    local gain = g.vA * Demi(arrivee)
    local fait = {}
    -- Les rendus d'objectifs finis plus tot dans l'enchainement.
    local reste = {}
    for _, o in ipairs(attente) do
        if o.recv and Yards(o.recv, g, ctx.sx, ctx.sy) <= PLAN.RAYON then
            gain = gain + o.vRendu * Demi(arrivee)
            duree = duree + PLAN.T_ACTION
            if s then s = { l = s.l + o.placesQ, gr = s.gr, dv = s.dv, mc = s.mc, repare = s.repare } end
        else
            table.insert(reste, o)
        end
    end
    local n
    if s then
        n = { l = math.max(0, s.l + g.libere - g.prise), gr = s.gr, dv = s.dv, mc = s.mc, repare = s.repare }
        local avant = n.l
        local pression = math.max(0, PLAN.SAC_SEUIL - (s.l + s.gr * PLAN.FACT_GRIS)) / PLAN.SAC_SEUIL
        if g.vendeur and n.gr + n.dv > 0 and n.l < PLAN.VENTE_SOUS then
            n.l, n.gr, n.dv = n.l + n.gr + n.dv, 0, 0
            duree = duree + PLAN.T_VENTE
            fait.vendre = true
        end
        if (g.courrier or g.banque) and n.mc > 0 and n.l < PLAN.SAC_SEUIL then
            n.l, n.mc = n.l + n.mc, 0
            duree = duree + PLAN.T_POSTER
            fait.poster = g.courrier and "courrier" or "banque"
        end
        if g.reparation and ctx.usure and ctx.usure < PLAN.USURE and not n.repare then
            n.repare = true
            gain = gain + PLAN.V_REPARER * Demi(arrivee)
            duree = duree + PLAN.T_REPARER
            fait.reparer = true
        end
        -- Sacs presque pleins : chaque place de marge regagnee vaut (le gris
        -- vendu un peu moins : on aurait pu le jeter).
        local rendues = (n.l - avant) - (fait.vendre and s.gr * PLAN.FACT_GRIS or 0) + g.libere
        if pression > 0 and rendues > 0 then
            gain = gain + PLAN.V_PLACE * pression * math.min(PLAN.SAC_SEUIL, rendues) * Demi(arrivee)
        end
    end
    local tO = 0
    for _, o in ipairs(g.objs) do
        local part = 1
        if n and o.besoin > n.l then
            local manque = o.besoin - n.l
            local jete = math.min(manque, n.gr)
            if jete > 0 then
                n.gr, n.l, manque = n.gr - jete, n.l + jete, manque - jete
                duree, tO = duree + jete * PLAN.T_JETER, tO + jete * PLAN.T_JETER
                gain = gain - jete * PLAN.PERTE_JETER
                fait.jeter = (fait.jeter or 0) + jete
            end
            if manque > 0 then
                local d = ctx.grille and VendeurLoin(g, ctx)
                if d then
                    local t = 2 * d / PLAN.VITESSE + PLAN.T_VENTE
                    duree, tO = duree + t, tO + t
                    n.l, n.dv = n.l + manque + n.dv, 0
                    fait.allerRetour = true
                else
                    part = n.l / o.besoin
                    fait.sansPlace = true
                end
            end
        end
        if n then n.l = math.max(0, n.l - o.besoin * part) end
        duree, tO = duree + o.temps, tO + o.temps
        local v = o.v * part
        if surPlace and o.presque then v = v + PLAN.V_PRESQUE * o.poids end
        gain = gain + v * Demi(arrivee + tO)
        if part >= 1 then table.insert(reste, o) end
    end
    return n, duree, gain, reste, fait
end

-- Le meilleur enchainement de visites depuis `ici`. La cible d'avant
-- (plan.visee) y est comptee 20 % plus pres (PLAN.GARDE), comme dans la chaine.
-- Rend la liste des visites, ou nil.
local function Planifier(points, ici, plan, ctx)
    local vivantes = {}
    for _, g in ipairs(Grappes(points, ctx)) do
        if g.valeur > 0 then
            g.seule = g.valeur * Demi(Trajet(ici, g, ctx))
            table.insert(vivantes, g)
        end
    end
    if #vivantes == 0 then return nil end
    table.sort(vivantes, function(a, b)
        if a.seule ~= b.seule then return a.seule > b.seule end
        return a.cle < b.cle
    end)
    local cand = {}
    for k = 1, math.min(PLAN.LARGEUR, #vivantes) do cand[k] = vivantes[k] end
    local gVisee
    if plan.visee then
        for _, g in ipairs(vivantes) do
            for _, a in ipairs(g.actions) do if a.ident == plan.visee then gVisee = g end end
        end
        local dedans = false
        for _, g in ipairs(cand) do if g == gVisee then dedans = true end end
        if gVisee and not dedans then table.insert(cand, gVisee) end
    end
    local h = math.min(PLAN.HORIZON, #cand)
    local s0 = ctx.sac and { l = ctx.sac.libres or 0, gr = ctx.sac.gris or 0, dv = ctx.sac.divers or 0,
        mc = ctx.sac.marchandises or 0 } or nil
    local meilleur
    local chemin, pris, faits = {}, {}, {}
    local function Explorer(pos, t, score, s, attente)
        if #chemin == h then
            local fin = score
            -- Le reste de l'itineraire, vu depuis le dernier lieu atteint.
            local vus, restes = {}, {}
            for _, g in ipairs(chemin) do vus[g] = true end
            for _, g in ipairs(vivantes) do
                if not vus[g] then table.insert(restes, g.valeur * Demi(t + Trajet(pos, g, ctx))) end
            end
            table.sort(restes, function(a, b) return a > b end)
            for k = 1, math.min(PLAN.RESIDU_N, #restes) do fin = fin + PLAN.RESIDU * restes[k] end
            -- Les rendus qui restent : apres l'enchainement, chez leur receveur.
            for _, o in ipairs(attente) do
                if o.recv then fin = fin + o.vRendu * Demi(t + Trajet(pos, o.recv, ctx)) end
            end
            if s then
                local marge = s.l + s.gr * PLAN.FACT_GRIS
                fin = fin - PLAN.PEN_SAC * math.max(0, PLAN.SAC_SEUIL - marge) / PLAN.SAC_SEUIL
            end
            if not meilleur or fin > meilleur.score then
                meilleur = { score = fin, chemin = { unpack(chemin) }, fait = faits[1] }
            end
            return
        end
        for k, g in ipairs(cand) do
            if not pris[k] then
                local trajet = Trajet(pos, g, ctx)
                -- La cible d'avant compte 20 % plus pres : elle ne cede la
                -- place qu'a un enchainement nettement meilleur.
                if #chemin == 0 and g == gVisee then trajet = trajet * PLAN.GARDE end
                local arrivee = t + trajet
                local surPlace = #chemin == 0 and Yards(ici, g, ctx.sx, ctx.sy) <= PLAN.SUR_PLACE
                local s2, duree, gain, attente2, fait = Visiter(g, arrivee, s, attente, ctx, surPlace)
                pris[k] = true
                table.insert(chemin, g)
                faits[#chemin] = fait
                Explorer(g, arrivee + duree, score + gain, s2, attente2)
                faits[#chemin] = nil
                table.remove(chemin)
                pris[k] = nil
            end
        end
    end
    Explorer(ici, 0, 0, s0, {})
    plan.visee = meilleur.chemin[1].actions[1].ident
    plan.score = meilleur.score
    plan.fait = meilleur.fait
    return meilleur.chemin
end

-- Ce qui a change depuis le dernier choix : la cible se rechoisit librement.
local function Signature(points, moi, ctx)
    local m = {}
    for _, pt in ipairs(points) do
        local q = moi.quetes and moi.quetes[pt.id]
        local f = 0
        for _, o in ipairs(q and q.objectifs or {}) do if o.fait then f = f + 1 end end
        table.insert(m, pt.ident .. "=" .. f)
    end
    table.sort(m)
    return table.concat(m, ",") .. "|" .. ctx.palierSacs .. "|" .. ctx.palierJournal .. "|" .. (ctx.grille and "s" or "-")
end

-- L'ordre des etapes d'un itineraire : les visites planifiees, puis le
-- reste, le plus proche du precedent d'abord.
local function OrdreDItineraire(points, ici, moi, continent, etat, compte)
    local ctx = Contexte(moi, points, compte)
    ctx.sx, ctx.sy = Echelle(continent)
    -- Itineraire de zone : les rendus hors de la zone attendent qu'elle soit
    -- finie, tant qu'il y reste quelque chose a faire.
    if type(compte) == "table" and compte.carteZone then
        for _, pt in ipairs(points) do
            if pt.genre == "rendre" then
                local okH, hors = pcall(guidage.RenduHorsZone, moi, pt.id, compte.carteZone)
                pt.horsZone = okH and hors ~= nil or nil
            end
            if not pt.horsZone then ctx.zoneActive = true end
        end
    end
    local okG, grille = pcall(ServicesDuContinent, continent, ctx.sx, ctx.sy)
    ctx.grille = okG and grille or nil
    local okV, vols = pcall(VolsDuContinent, moi, continent)
    ctx.vols = okV and vols or nil
    local sig = Signature(points, moi, ctx)
    if type(etat.plan) ~= "table" or etat.plan.signature ~= sig then
        etat.plan = { signature = sig, suites = {}, receveurs = {}, visee = nil }
    end
    etat.plan.receveurs = etat.plan.receveurs or {}
    for _, pt in ipairs(points) do
        if pt.genre == "rendre" then pt.suites = SuitesDebloquees(pt, moi, continent, ctx.sx, ctx.sy, etat.plan.suites) end
        if pt.genre == "objectif" and not pt.receveur then
            local okR, r = pcall(Receveur, pt, continent, ctx, etat.plan.receveurs)
            pt.receveur = okR and r or nil
        end
    end
    local chemin = Planifier(points, ici, etat.plan, ctx)
    if not chemin then return nil end
    local ordre, pris = {}, {}
    for _, g in ipairs(chemin) do
        for _, a in ipairs(g.actions) do table.insert(ordre, a) pris[a] = true end
    end
    local reste = {}
    for _, pt in ipairs(points) do if not pris[pt] then table.insert(reste, pt) end end
    if #reste > 0 then
        for _, pt in ipairs(S().Lieux.Chaine(reste, ordre[#ordre])) do table.insert(ordre, pt) end
    end
    return ordre
end

-- Une carte, ou l'une de ses sous-cartes (grotte, quartier) : dans `racine` ?
local function DansLaCarte(carte, racine)
    local info = NS.Lecture("C_Map.GetMapInfo")
    for _ = 1, 6 do
        if not carte then return false end
        if carte == racine then return true end
        local i = info and NS.Appeler(info, carte)
        if type(i) ~= "table" then return false end
        carte = i.parentMapID
    end
    return false
end
-- Le rendu d'une quete finie se fait hors de la carte `carteZone` : rend le
-- nom de la carte ou il se fait (et si ce rendu debloque une suite), sinon nil.
function guidage.RenduHorsZone(moi, id, carteZone)
    local q = moi and moi.quetes and moi.quetes[id]
    if not (q and q.complete == true and carteZone) then return nil end
    local ok, pts = pcall(NS.carte.PointsPour, id, moi)
    local carte
    for _, pt in ipairs(ok and type(pts) == "table" and pts or {}) do
        if pt.carte then
            if DansLaCarte(pt.carte, carteZone) then return nil end
            carte = carte or pt.carte
        end
    end
    if not carte then return nil end
    local info = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
    local okS, suites = pcall(NS.ref.Suites, id)
    local suite = false
    for _, sId in ipairs(okS and suites or {}) do
        if not (moi.faites and moi.faites[sId]) then suite = true end
    end
    return (type(info) == "table" and info.name) or "?", suite
end

-- Pour les essais hors du jeu.
guidage.PLAN, guidage.Planifier, guidage.OrdreDItineraire = PLAN, Planifier, OrdreDItineraire
guidage.Grille, guidage.ServicesEtat = Grille, services
guidage.ServicesSynchrones = function() while not Avancer(100000) do end return services.liste end

local function EtapesDeQuetes(ids, moi, etat, compte, suite)
    -- Les detours encore a rendre s'ajoutent (une seule fois chacun).
    local d = Detours(moi)
    if next(d) then
        local deja, avec = {}, {}
        for _, id in ipairs(ids) do deja[id] = true table.insert(avec, id) end
        for id in pairs(d) do
            local q = moi.quetes and moi.quetes[id]
            if not q or q.complete ~= true then d[id] = nil
            elseif not deja[id] then table.insert(avec, id) end
        end
        ids = avec
    end
    if #ids == 0 then return nil, "loin" end
    local continent = Continent()
    if not continent then return nil, "loin", OuAller(moi, ids) end
    local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil, "loin", OuAller(moi, ids) end
    local jx, jy = pos:GetXY()
    -- Position cachee par le jeu (valeur secrete) : jamais comparee.
    local secret = _G.issecretvalue
    if not jx or (secret and (secret(jx) or secret(jy))) then return nil, "loin", OuAller(moi, ids) end
    local points, entrees = {}, {}
    etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
    -- Une quete finie (ou sortie du journal) libere ses points visites.
    for cleU in pairs(etat.utilises) do
        local idU = tonumber(cleU:match("^(%d+):"))
        local qU = idU and moi.quetes and moi.quetes[idU]
        if not qU or qU.complete == true then etat.utilises[cleU] = nil end
    end
    for _, id in ipairs(ids) do
        local lieu = PointDeQuete(id, moi, continent, jx, jy, etat.utilises)
        if lieu and lieu.entree then
            -- Plusieurs quetes du meme donjon : une seule etape, son entree.
            if not entrees[lieu.entree] then
                entrees[lieu.entree] = { carte = continent, x = lieu.x, y = lieu.y, cle = "entree:" .. lieu.entree, id = id,
                    titre = lieu.entree, qui = string.format(L.GUIDE_ENTER_DUNGEON, lieu.entree), entree = lieu.entree, ids = { id } }
                table.insert(points, entrees[lieu.entree])
            else
                table.insert(entrees[lieu.entree].ids, id)
            end
        elseif lieu then
            local cleP = "q" .. id .. (lieu.objectif and (":" .. CleDePoint(id, lieu.x, lieu.y)) or "")
            local etatQ = NS.parcours.EtatEtape(moi, id)
            -- Passee a la main : ignoree tant que sa quete n'a pas change.
            local sautee = type(etat.sautees) == "table" and etat.sautees[cleP]
            if sautee and sautee ~= etatQ then etat.sautees[cleP] = nil sautee = nil end
            if not sautee then
                table.insert(points, { carte = continent, x = lieu.x, y = lieu.y, cle = cleP, id = id,
                    titre = Titre(id, moi), qui = Qui(id, moi, lieu), objectif = lieu.objectif, etatQuete = etatQ,
                    butin = lieu.butin })
            end
        end
    end
    if #points == 0 then
        -- Rien sur ce continent : on vise quand meme la premiere quete sur
        -- son continent (l'add-on d'itineraire sait y mener ; la fleche de la
        -- suite dit ou aller).
        local ailleurs = Ailleurs(ids, moi)
        if ailleurs then return { ailleurs }, nil, nil, Ajuster({ ailleurs }, compte) end
        return nil, "loin", OuAller(moi, ids)
    end
    etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
    local ici = { x = jx, y = jy }
    if suite then
        -- Un itineraire : la visite la plus rentable (OrdreDItineraire). En
        -- cas d'erreur, l'ordre simple ci-dessous.
        local ok, ordre = pcall(OrdreDItineraire, points, ici, moi, continent, etat, compte)
        if ok and type(ordre) == "table" and ordre[1] then return ordre, nil, nil, Ajuster(ordre, compte) end
    end
    local ordre = S().Lieux.Chaine(points, ici, nil, etat.chaine)
    return ordre, nil, nil, Ajuster(ordre, compte)
end

-- Une quete de la liste est finie : rendue (faite), ou sortie du journal
-- apres y avoir ete vue (rendue sans etre encore notee, ou abandonnee), ou
-- echouee.
local function Finie(id, moi, etat)
    local q = moi.quetes and moi.quetes[id]
    if q then
        etat.vues = type(etat.vues) == "table" and etat.vues or {}
        etat.vues[id] = true
        return q.complete == -1
    end
    if moi.faites and moi.faites[id] then return true end
    return type(etat.vues) == "table" and etat.vues[id] == true
end

local function Reste(ids, moi, etat)
    local reste, fait = {}, 0
    for _, id in ipairs(ids) do
        if Finie(id, moi, etat) then fait = fait + 1 else table.insert(reste, id) end
    end
    return reste, fait
end

local function Copie(ids)
    local t = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        id = tonumber(id)
        if id then table.insert(t, id) end
    end
    table.sort(t)
    return t
end

-- Commun a tous les types : la carte en filigrane au clic, et la fin du
-- guidage qui remet la carte et le suivi a jour.
local function Commun(def)
    def.icone = "Interface\\GossipFrame\\AvailableQuestIcon"
    def.AideClic = function() return L.GUIDE_CLICK end
    -- « Suivante » (bouton du guidage) : la cible visee est passee ; elle ne
    -- revient que si l'etat de sa quete change.
    def.Passer = def.Passer or function(_, etat, cible)
        if type(cible) ~= "table" or type(etat) ~= "table" then return end
        if cible.objectif and cible.id then
            etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
            etat.utilises[CleDePoint(cible.id, cible.x, cible.y)] = true
        elseif cible.cle then
            etat.sautees = type(etat.sautees) == "table" and etat.sautees or {}
            etat.sautees[cible.cle] = cible.etatQuete or true
        end
        etat.plan = nil
    end
    -- Arrive sur un lieu d'objectif : il est fait, le suivant est vise.
    def.Arrivee = def.Arrivee or function(_, etat, cible)
        if type(cible) == "table" and cible.objectif and cible.id and type(etat) == "table" then
            etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
            etat.utilises[CleDePoint(cible.id, cible.x, cible.y)] = true
        end
        if type(etat) == "table" then etat.plan = nil end
        return "suivante"
    end
    def.Evenements = def.Evenements or { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA" }
    def.Clic = function()
        if S() and S().OuvrirPlanDuDonjon and S().OuvrirPlanDuDonjon() then return end
        if NS.pageCarte and NS.pageCarte.Filigrane then pcall(NS.pageCarte.Filigrane) end
    end
    def.Fin = function(_, _, raison)
        -- Un passage pour rendre des quetes, demande au milieu d'un autre
        -- guidage : une fois tout rendu, le guidage d'avant reprend la ou il
        -- en etait. Arrete a la main : rien ne reprend.
        local reprise = NS.repriseApres
        if reprise and reprise.par == def then
            NS.repriseApres = nil
            if raison == "atteint" and reprise.inst then
                local inst = reprise.inst
                local apres = NS.Lecture and NS.Lecture("C_Timer.After")
                local function Reprendre() pcall(S().LancerObjectif, inst.proprietaire, inst.type, inst.params, inst) end
                if apres then apres(1, Reprendre) else Reprendre() end
            end
        end
        -- Les detours etaient pour cet itineraire : ils partent avec lui.
        local moi = Moi()
        if moi then moi.detours = nil end
        if NS.carte then NS.carte.Invalider() end
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then
            pcall(NS.pageCarte.Filigrane, false)
        end
        if NS.fenetre and NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
        if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    end
    return def
end

local TYPES = {}

-- Les quetes a rendre : l'ensemble suivi est celui des quetes terminees a
-- chaque instant.
TYPES.rendus = Commun({
    Libelle = function() return L.GUIDE_OBJ_TURNIN end,
    Preparer = function(p, etat)
        local moi = Moi()
        if not moi then return false end
        etat.rendues = {}
        for _, q in pairs(moi.quetes or {}) do if q.complete == true then return true end end
        return false, L.GUIDE_TURNIN_NONE
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        etat.rendues = type(etat.rendues) == "table" and etat.rendues or {}
        local ids = {}
        for id, q in pairs(moi.quetes or {}) do
            if q.complete == true then
                table.insert(ids, id)
                etat.rendues[id] = false
            end
        end
        -- Une quete vue terminee et sortie du journal : rendue.
        local fait = 0
        for id, v in pairs(etat.rendues) do
            if not (moi.quetes and moi.quetes[id]) then etat.rendues[id] = true end
            if etat.rendues[id] == true then fait = fait + 1 end
        end
        if #ids == 0 then return nil, "atteint" end
        table.sort(ids)
        return EtapesDeQuetes(ids, moi, etat, { fait = fait, total = fait + #ids })
    end,
})

-- Des quetes precises, figees au clic.
TYPES.quetes = Commun({
    Cle = function(p) return table.concat(Copie(p.ids), ",") end,
    Libelle = function(p)
        local ids = Copie(p.ids)
        if #ids == 1 then return Titre(ids[1], (Moi())) end
        return string.format(L.GUIDE_OBJ_QUESTS, #ids)
    end,
    Preparer = function(p, etat)
        local moi = Moi()
        if not moi then return false end
        p.ids = Copie(p.ids)
        if #p.ids == 0 then return false end
        etat.vues = {}
        local reste = Reste(p.ids, moi, etat)
        return #reste > 0
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        local ids = Copie(p.ids)
        local reste, fait = Reste(ids, moi, etat)
        if #reste == 0 then return nil, "atteint" end
        return EtapesDeQuetes(reste, moi, etat, { fait = fait, total = #ids })
    end,
})

-- Vers un niveau : les quetes du calcul de QuestCore (les terminees si leur
-- XP suffit, sinon la progression), recalculees a chaque niveau pris.
local function Calculer(etat, moi)
    local d = NS.disponibles
    local ids = d and d.EtapesPourNiveau and d.EtapesPourNiveau(moi)
    etat.ids = type(ids) == "table" and Copie(ids) or {}
    etat.pour = tonumber(NS.Appeler(UnitLevel, "player")) or 0
    etat.vues = {}
    for _, id in ipairs(etat.ids) do Finie(id, moi, etat) end
    return #etat.ids > 0
end

TYPES.niveau = Commun({
    Evenements = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA" },
    Cle = function(p) return tostring(tonumber(p.niveau) or 0) end,
    Libelle = function(p) return string.format(L.ROUTE_LEVEL_NAME, tonumber(p.niveau) or 0) end,
    Preparer = function(p, etat)
        local moi = Moi()
        p.niveau = tonumber(p.niveau)
        if not (moi and p.niveau) then return false end
        if (tonumber(NS.Appeler(UnitLevel, "player")) or 0) >= p.niveau then return false end
        if not Calculer(etat, moi) then return false, L.ROUTE_LEVEL_NONE end
        return true
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        local niveau = tonumber(NS.Appeler(UnitLevel, "player")) or 0
        if niveau >= (tonumber(p.niveau) or 0) then return nil, "atteint" end
        etat.ids = type(etat.ids) == "table" and etat.ids or {}
        local reste, fait = Reste(etat.ids, moi, etat)
        -- Un niveau pris, ou toutes les quetes prevues faites sans l'atteindre :
        -- le calcul repart d'ici.
        if etat.pour ~= niveau or #reste == 0 then
            if not Calculer(etat, moi) then return nil, "inconnu", L.ROUTE_LEVEL_NONE end
            reste, fait = Reste(etat.ids, moi, etat)
            if #reste == 0 then return nil, "inconnu", L.ROUTE_LEVEL_NONE end
        end
        return EtapesDeQuetes(reste, moi, etat, { fait = fait, total = #etat.ids })
    end,
})

-- Un parcours enregistre : seules les etapes faisables maintenant (a
-- prendre, en cours, a rendre) sont visees, la plus proche d'abord.
-- Trajet de donjon : il suit tout seul (ce qui se debloque s'y ajoute) et
-- se guide rubrique par rubrique (NS.donjons.AGuider) : les suites de
-- quetes, puis les quetes a prendre dehors, puis, tout etant pris, l'entree
-- du donjon ; jamais une etape faite ni un donneur de quete deja prise.
local function EtapesDuKit(moi, pc, etat)
    local D = NS.donjons
    local d = D and D.DuKit and D.DuKit(moi, pc)
    if not d then return false end
    D.MettreAJourKit(moi, d, pc)
    local ids, phase = D.AGuider(moi, d, pc)
    local faites, total = NS.parcours.AvancementGestes(moi, pc)
    if #ids == 0 then
        -- Rien a guider maintenant : fini seulement si toutes les etapes du
        -- trajet sont faites ; sinon le guidage reste et dit ou aller.
        local f, t = NS.parcours.Avancement(moi, pc)
        if t == 0 or f >= t then return true, nil, "atteint" end
        return true, nil, "loin", OuAller(moi, pc.etapes)
    end
    -- Nouvelle rubrique : la cible d'avant ne compte plus.
    if etat.phase ~= phase then etat.phase, etat.chaine, etat.plan = phase, {}, nil end
    return true, EtapesDeQuetes(ids, moi, etat, { fait = faites, total = math.max(total, faites + 1) }, true)
end

-- Un itineraire : les quetes a prendre visees a la fois, dans son ordre.
local A_PRENDRE = 4

TYPES.parcours = Commun({
    Cle = function(p) return tostring(p.uid) end,
    Libelle = function(p)
        local _, cle = Moi()
        local pc = cle and NS.parcours.TrouverUid(cle, p.uid)
        return pc and pc.nom or nil
    end,
    Preparer = function(p)
        local _, cle = Moi()
        return cle ~= nil and NS.parcours.TrouverUid(cle, p.uid) ~= nil
    end,
    Reprendre = function(p)
        local _, cle = Moi()
        return cle ~= nil and NS.parcours.TrouverUid(cle, p.uid) ~= nil
    end,
    Etapes = function(p, etat)
        local moi, cle = Moi()
        if not moi then return nil, "loin" end
        local pc = NS.parcours.TrouverUid(cle, p.uid)
        if not pc then return nil, "atteint" end
        if pc.genre == "kit" then
            local retour = { EtapesDuKit(moi, pc, etat) }
            if retour[1] then return unpack(retour, 2, 5) end
        end
        local faites, total = NS.parcours.Avancement(moi, pc)
        if total > 0 and faites >= total then return nil, "atteint" end
        -- Le compte affiche, lui, avance a chaque geste (prendre, faire, rendre).
        faites, total = NS.parcours.AvancementGestes(moi, pc)
        -- Ce qui est vise : tout ce qui est commence (objectifs, rendus), et
        -- seulement les prochaines quetes a prendre dans l'ordre de
        -- l'itineraire (jamais une quete de la fin avant celles du debut).
        -- Un itineraire de zone n'a pas d'ordre impose : toutes ses quetes a
        -- prendre sont visees, l'itineraire choisit les plus rentables.
        local zone = pc.genre == "zone" and pc.zone or nil
        local maxPrises = zone and 1000 or A_PRENDRE
        local ids, prises = {}, 0
        for _, id in ipairs(pc.etapes or {}) do
            local e = NS.parcours.EtatEtape(moi, id)
            if e == "cours" or e == "rendre" then table.insert(ids, id)
            elseif e == "prendre" and prises < maxPrises then prises = prises + 1 table.insert(ids, id) end
        end
        if #ids == 0 then return nil, "loin", OuAller(moi, pc.etapes) end
        local rangs = {}
        for k, id in ipairs(pc.etapes or {}) do rangs[id] = k end
        local carteZone = zone and NS.carte and NS.carte.CarteDeZone and NS.carte.CarteDeZone(zone) or nil
        return EtapesDeQuetes(ids, moi, etat, { fait = faites, total = #(pc.etapes or {}),
            rangDe = function(id) return rangs[id] end, etapes = pc.etapes, carteZone = carteZone }, true)
    end,
})

if S() and S().DeclarerObjectifs then S().DeclarerObjectifs("QuestCore", TYPES) end

-- Une fois les sauvegardes chargees : l'ancien etat du guidage, commun au
-- compte, n'a plus cours (l'objectif est garde par personnage par la suite).
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, evenement)
        if evenement ~= "PLAYER_LOGIN" then return end
        local ok, g = pcall(NS.base.ReglagesGeneraux)
        if ok and type(g) == "table" then g.guidage = nil g.ajustementAuto = nil end
    end)
end

-- ---------------------------------------------------------------------------
-- Pour les boutons de QuestCore et les autres add-ons
-- ---------------------------------------------------------------------------

-- Apres un lancement : la carte ne montre plus que l'objectif guide.
local function Apres(lance, trajet)
    if lance then
        if trajet and NS.pageCarte and NS.pageCarte.ModeTrajet then NS.pageCarte.ModeTrajet(true) end
        if NS.carte then NS.carte.Invalider() end
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then pcall(NS.pageCarte.Rendre)
        elseif NS.fenetre and NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
    end
    if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    return lance
end

function guidage.Lancer(nom, params)
    return Apres(S().LancerObjectif("QuestCore", nom, params), nom ~= "parcours")
end
function guidage.Basculer(nom, params)
    if nom == false then S().Arreter("joueur") return Apres(false) end
    return Apres(S().BasculerObjectif("QuestCore", nom, params), nom ~= "parcours")
end
function guidage.EstActif(nom, params) return S().EstActif("QuestCore", nom, params) end
-- Un guidage de QuestCore, quel qu'il soit.
function guidage.Actif() return S().GuidageActif("QuestCore") end
-- L'objectif QuestCore guide (instance), ou nil.
function guidage.Objectif()
    local a = S().ObjectifActif()
    return (a and a.proprietaire == "QuestCore") and a or nil
end
-- L'uid du parcours guide, ou nil.
function guidage.ParcoursGuide()
    local a = guidage.Objectif()
    return a and a.type == "parcours" and a.params.uid or nil
end
-- Les quetes de l'objectif guide, dans l'ordre vise (pour la carte).
function guidage.Etapes()
    if not guidage.Objectif() then return nil end
    local e = S().EtatGuidage()
    return e and e.etapes
end

-- Detours : une quete a rendre ajoutee a l'itineraire en cours, ou retiree.
function guidage.EstDetour(id)
    local moi = Moi()
    return moi ~= nil and Detours(moi)[tonumber(id)] == true
end
-- La quete fait-elle deja partie de l'objectif guide (hors detour) ?
function guidage.DansLObjectif(id)
    local a = guidage.Objectif()
    if not a then return false end
    if a.type == "rendus" then return true end
    id = tonumber(id)
    if guidage.EstDetour(id) then return false end
    for _, e in ipairs(guidage.Etapes() or {}) do
        if e.id == id then return true end
    end
    if a.type == "quetes" then
        for _, x in ipairs(a.params.ids or {}) do if tonumber(x) == id then return true end end
    end
    return false
end
function guidage.BasculerDetour(id)
    local moi = Moi()
    id = tonumber(id)
    if not (moi and id and guidage.Objectif()) then return false end
    local d = Detours(moi)
    d[id] = (not d[id]) or nil
    S().Invalider()
    if NS.carte then NS.carte.Invalider() end
    if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    return d[id] == true
end

_G.QuestCoreAPI = _G.QuestCoreAPI or {}
local api = _G.QuestCoreAPI
api.GuiderRendus = function() return guidage.Lancer("rendus", {}) end
api.GuiderQuetes = function(ids) return guidage.Lancer("quetes", { ids = Copie(ids) }) end
-- Pour le releve de l'hotel des ventes (CraftCore) : les objets que les quetes
-- en cours demandent et qu'aucun monstre ne donne. { objet, nom, manque }.
api.ObjetsAObtenir = function()
    local moi = Moi()
    local res = {}
    for id in pairs(moi and moi.quetes or {}) do
        for _, o in ipairs(NS.ref.ObjetsAObtenir(moi, id)) do table.insert(res, o) end
    end
    return res
end
-- Pour CraftCore : les quetes qui demandent cet objet.
api.QuetesDemandant = function(objet) return NS.ref.QuetesDemandant(objet) end
api.GuiderNiveau = function(n) return guidage.Lancer("niveau", { niveau = tonumber(n) }) end
-- Aller rendre ces quetes, puis reprendre le guidage en cours (s'il y en a
-- un) la ou il en etait.
api.RendreEtReprendre = function(ids)
    local avant = S().ObjectifActif and S().ObjectifActif()
    local lance = guidage.Lancer("quetes", { ids = Copie(ids) })
    if lance and avant then NS.repriseApres = { inst = avant, par = TYPES.quetes } end
    return lance
end
api.GuiderParcours = function(uid) return guidage.Lancer("parcours", { uid = uid }) end
-- Ancien appel : guider les quetes a rendre, ou arreter le guidage de QuestCore.
api.Guider = function(oui)
    if oui == false then
        if guidage.Actif() then S().Arreter("joueur") end
        return false
    end
    return api.GuiderRendus()
end
