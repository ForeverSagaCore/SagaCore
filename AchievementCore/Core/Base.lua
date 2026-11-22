local _, NS = ...

-- Ce qui est faisable dans le jeu : lu dans QuestieDB (quetes, objets, PNJ,
-- donjons) et dans le jeu (zones des continents, morceaux de carte). Les
-- grandes listes s'indexent une fois par session, par petits morceaux (voir
-- Travail.lua), puis restent en memoire. Ce fichier ne dit rien de ce que
-- les personnages ont fait : c'est Persos.lua.

local base = NS.base
local ref = NS.ref
local etat = { quetes = nil, objets = nil, boss = nil, progresQuetes = 0, progresObjets = 0 }
base.etat = etat
local travail = NS.travail
local Jeu = NS.Jeu
local Pause = function() travail.Pause() end

-- ---------------------------------------------------------------------------
-- QuestieDB
-- ---------------------------------------------------------------------------

function base.QDB(entite)
    local e = _G[entite]
    if type(e) == "table" and type(e.Get) == "function" then return e end
    return nil
end

function base.Lire(entite, id, champ)
    local e = base.QDB(entite)
    if not e or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end
local Lire = base.Lire

local function TousLesIds(entite)
    local e = base.QDB(entite)
    if not (e and type(e.GetAllIds) == "function") then return nil end
    local ok, ids = pcall(e.GetAllIds)
    if ok and type(ids) == "table" and #ids > 0 then return ids end
    return nil
end

function base.QuestieDisponible() return TousLesIds("QuestDB") ~= nil end

-- Une table de la base des zones de QuestieDB (donjons...), ou nil.
local function TableDesZones(nom)
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and NS.Appeler(lib.Support.Get, "ZoneDB")
    local brut = type(support) == "table" and type(support.private) == "table" and support.private[nom]
    if type(brut) == "string" then
        local fn = loadstring(brut)
        local ok, t = false, nil
        if fn then ok, t = pcall(fn) end
        brut = ok and t or nil
    end
    return type(brut) == "table" and brut or nil
end

local function NomDeZone(zone)
    local nom = Jeu("C_Map.GetAreaInfo", zone)
    if type(nom) == "string" and nom ~= "" then return nom end
    return nil
end
base.NomDeZone = NomDeZone

-- ---------------------------------------------------------------------------
-- Zones des continents et morceaux de carte (exploration)
-- ---------------------------------------------------------------------------

function base.TailleCarte(carte)
    local couches = Jeu("C_Map.GetMapArtLayers", carte)
    local c = type(couches) == "table" and couches[1]
    if type(c) == "table" and tonumber(c.layerWidth) and tonumber(c.layerHeight) then
        return tonumber(c.layerWidth), tonumber(c.layerHeight)
    end
    return 1002, 668
end

-- Les morceaux d'une carte (par son dessin) : liste de cles "l:h:x:y".
local morceauxParArt = {}
function base.Morceaux(art)
    art = tonumber(art)
    if not art then return {} end
    if morceauxParArt[art] then return morceauxParArt[art] end
    local liste = {}
    local t = NS.reveleCarte and NS.reveleCarte[art]
    for cle in pairs(type(t) == "table" and t or {}) do table.insert(liste, cle) end
    table.sort(liste)
    morceauxParArt[art] = liste
    return liste
end

local zones
-- { { carte, nom, continent, nomContinent, art } } : les zones des
-- continents, par continent puis par nom. Gardees une fois trouvees.
function base.Zones()
    if zones then return zones end
    local liste = {}
    local continents = {}
    local enfants = Jeu("C_Map.GetMapChildrenInfo", 947, 2)
    for _, c in ipairs(type(enfants) == "table" and enfants or {}) do
        if type(c) == "table" and tonumber(c.mapID) then table.insert(continents, { id = tonumber(c.mapID), nom = c.name }) end
    end
    if #continents == 0 then continents = { { id = 1414 }, { id = 1415 } } end
    for _, c in ipairs(continents) do
        local infoC = Jeu("C_Map.GetMapInfo", c.id)
        local nomC = c.nom or (type(infoC) == "table" and infoC.name) or ("#" .. c.id)
        local z = Jeu("C_Map.GetMapChildrenInfo", c.id, 3)
        for _, info in ipairs(type(z) == "table" and z or {}) do
            if type(info) == "table" and tonumber(info.mapID) then
                local art = tonumber(Jeu("C_Map.GetMapArtID", info.mapID))
                table.insert(liste, { carte = tonumber(info.mapID), nom = info.name or ("#" .. info.mapID),
                    continent = c.id, nomContinent = nomC, art = art })
            end
        end
    end
    table.sort(liste, function(a, b)
        if a.nomContinent ~= b.nomContinent then return tostring(a.nomContinent) < tostring(b.nomContinent) end
        return tostring(a.nom) < tostring(b.nom)
    end)
    if #liste > 0 then zones = liste end
    return liste
end

-- ---------------------------------------------------------------------------
-- Donjons et raids
-- ---------------------------------------------------------------------------

local donjons, donjonParZone
-- { { zone, nom, nomBase, raid, autres = { zones } } }.
function base.Donjons()
    if donjons then return donjons end
    local liste, parZone = {}, {}
    local function Ajouter(zone, nomBase, autres)
        zone = tonumber(zone)
        if not zone or ref.PAS_DONJONS[zone] or parZone[zone] then return end
        local d = { zone = zone, nomBase = nomBase, nom = NomDeZone(zone) or nomBase or ("#" .. zone),
            raid = ref.RAIDS[zone] == true, autres = {} }
        for _, a in ipairs(type(autres) == "table" and autres or {}) do
            if tonumber(a) then table.insert(d.autres, tonumber(a)) parZone[tonumber(a)] = d end
        end
        table.insert(liste, d)
        parZone[zone] = d
    end
    local t = TableDesZones("dungeons")
    for zone, d in pairs(t or {}) do
        if type(d) == "table" then Ajouter(zone, d[1], d[2]) end
    end
    -- Sans la table de QuestieDB : la liste de reference.
    if not t then for _, zone in ipairs(ref.DONJONS) do Ajouter(zone) end end
    table.sort(liste, function(a, b)
        if a.raid ~= b.raid then return not a.raid end
        return tostring(a.nom) < tostring(b.nom)
    end)
    donjons, donjonParZone = liste, parZone
    return liste
end

function base.DonjonDeZone(zone)
    base.Donjons()
    return donjonParZone[tonumber(zone) or 0]
end

-- L'instance ou l'on est (nom et numero du jeu) : son donjon, ou nil.
function base.DonjonDeInstance(nom, idInstance)
    local t = TableDesZones("instanceIdToAreaId")
    local zone = t and tonumber(idInstance) and tonumber(t[tonumber(idInstance)])
    if zone and base.DonjonDeZone(zone) then return base.DonjonDeZone(zone) end
    local c = NS.Cle(nom)
    if c == "" then return nil end
    for _, d in ipairs(base.Donjons()) do
        if NS.Cle(d.nom) == c or (d.nomBase and NS.Cle(d.nomBase) == c) then return d end
    end
    return nil
end

-- Le champ de bataille ou l'on est (zone de reference), ou nil.
function base.ChampActuel()
    local nom = Jeu("GetInstanceInfo")
    local c = NS.Cle(nom)
    for _, ch in ipairs(ref.CHAMPS) do
        if NS.Cle(NomDeZone(ch.zone) or ch.en) == c or NS.Cle(ch.fr) == c or NS.Cle(ch.en) == c then return ch.zone end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Index des quetes faisables
-- ---------------------------------------------------------------------------
--
-- Pour chaque quete gardee : zone (ou theme), niveau, masques de races et de
-- classes, camp ("A", "H" ou "N" pour les deux), quete visee (si c'est une
-- quete d'introduction), suivante. Ecartees : les repetables et celles qu'on
-- ne peut plus prendre (aucun donneur place, aucun objet de depart
-- obtenable). Deux quetes exclusives (on ne peut en faire qu'une) comptent
-- pour une : elles forment un groupe.


-- Un PNJ ou un objet place dans le monde ? (garde : beaucoup de quetes
-- partagent leurs donneurs).
local places = {}
local function APosition(entite, id)
    local cle = entite .. id
    if places[cle] == nil then
        local s = Lire(entite, id, "spawns")
        places[cle] = type(s) == "table" and next(s) ~= nil
    end
    return places[cle]
end

-- L'avancement d'un index, montre par la fenetre ouverte (tous les 10 %).
local function Avancer(champ, v)
    local avant = math.floor((etat[champ] or 0) * 10)
    etat[champ] = v
    if math.floor(v * 10) ~= avant and NS.fenetre and NS.fenetre.Signaler then NS.fenetre.Signaler() end
end
local function Obtenable(objet)
    for _, champ in ipairs({ "npcDrops", "objectDrops", "itemDrops", "vendors" }) do
        local s = Lire("ItemDB", objet, champ)
        if type(s) == "table" and next(s) ~= nil then return true end
    end
    return false
end

-- Les combinaisons de chaque camp : celles du jeu, plus celles des personnages.
function base.Combinaisons()
    local parCamp = { Alliance = {}, Horde = {} }
    local vus = {}
    local function Ajouter(race, classe, faction)
        local cle = tostring(race) .. ":" .. tostring(classe)
        if vus[cle] or not ref.ID_CLASSE[classe] or not parCamp[faction] then return end
        vus[cle] = true
        table.insert(parCamp[faction], { race = race, classe = classe, id = ref.ID_CLASSE[classe] })
    end
    for _, r in ipairs(ref.RACES) do
        for _, classe in ipairs(ref.COMBINAISONS[r.id] or {}) do Ajouter(r.id, classe, r.faction) end
    end
    for _, p in ipairs(NS.persos.Liste()) do
        if p.race and p.classe and p.faction then Ajouter(p.race, p.classe, p.faction) end
    end
    return parCamp
end

-- Races de chaque camp (celles du jeu et celles des personnages).
function base.RacesDuCamp()
    local camps = { Alliance = {}, Horde = {} }
    for camp, liste in pairs(base.Combinaisons()) do
        local vus = {}
        for _, c in ipairs(liste) do if not vus[c.race] then vus[c.race] = true table.insert(camps[camp], c.race) end end
        table.sort(camps[camp])
    end
    return camps
end

local function CampDesDonneurs(debut)
    local a, h, autre = false, false, false
    for _, pnj in ipairs(type(debut) == "table" and type(debut[1]) == "table" and debut[1] or {}) do
        local f = Lire("NpcDB", pnj, "friendlyToFaction")
        if f == "A" then a = true elseif f == "H" then h = true else autre = true end
    end
    if type(debut) == "table" and ((type(debut[2]) == "table" and #debut[2] > 0) or (type(debut[3]) == "table" and #debut[3] > 0)) then autre = true end
    if a and not h and not autre then return "A" end
    if h and not a and not autre then return "H" end
    return "N"
end

local function Retiree(debut)
    if type(debut) ~= "table" then return false end
    for _, pnj in ipairs(type(debut[1]) == "table" and debut[1] or {}) do if APosition("NpcDB", pnj) then return false end end
    for _, ob in ipairs(type(debut[2]) == "table" and debut[2] or {}) do if APosition("ObjectDB", ob) then return false end end
    for _, it in ipairs(type(debut[3]) == "table" and debut[3] or {}) do if Obtenable(it) then return false end end
    return true
end

-- La quete convient-elle a une race et une classe (masques de la base) ?
local function Convient(q, race, idClasse)
    if (q.races or 0) ~= 0 and race and not NS.Bit(q.races, race) then return false end
    if (q.classes or 0) ~= 0 and idClasse and not NS.Bit(q.classes, idClasse) then return false end
    return true
end
base.Convient = Convient

local function ConstruireQuetes()
    local ids = TousLesIds("QuestDB")
    if not ids then etat.quetes = false return end
    local combos = base.Combinaisons()
    local Q, gardees = {}, {}
    for rang, id in ipairs(ids) do
        Pause()
        if rang % 100 == 0 then Avancer("progresQuetes", rang / #ids * 0.95) end
        local special = tonumber(Lire("QuestDB", id, "specialFlags")) or 0
        if not NS.Bit(special, 1) then
            local debut = Lire("QuestDB", id, "startedBy")
            if not Retiree(debut) then
                local races = tonumber(Lire("QuestDB", id, "requiredRaces")) or 0
                local classes = tonumber(Lire("QuestDB", id, "requiredClasses")) or 0
                local q = { id = id, races = races, classes = classes,
                    zone = tonumber(Lire("QuestDB", id, "zoneOrSort")) or 0,
                    niveau = tonumber(Lire("QuestDB", id, "questLevel")) or 0 }
                -- Le camp : celui des races demandees, sinon celui des donneurs.
                local camp = "N"
                if races ~= 0 then camp = nil else camp = CampDesDonneurs(debut) end
                for _, faction in ipairs({ "Alliance", "Horde" }) do
                    local ok = false
                    if camp == nil or camp == "N" or camp == faction:sub(1, 1) then
                        for _, c in ipairs(combos[faction]) do
                            if Convient(q, c.race, c.id) then ok = true break end
                        end
                    end
                    if faction == "Alliance" then q.okA = ok else q.okH = ok end
                end
                if q.okA or q.okH then
                    q.camp = (q.okA and q.okH) and "N" or (q.okA and "A" or "H")
                    local cible = tonumber(Lire("QuestDB", id, "breadcrumbForQuestId"))
                    if cible and cible > 0 then q.cible = cible end
                    local suivante = tonumber(Lire("QuestDB", id, "nextQuestInChain"))
                    if suivante and suivante > 0 then q.suivante = suivante end
                    local excl = Lire("QuestDB", id, "exclusiveTo")
                    if type(excl) == "table" and #excl > 0 then q.exclusives = excl end
                    local reps = Lire("QuestDB", id, "reputationReward")
                    if type(reps) == "table" then
                        for _, r in ipairs(reps) do
                            if type(r) == "table" and tonumber(r[1]) and (tonumber(r[2]) or 0) > 0 then
                                etat.factions = etat.factions or {}
                                etat.factions[tonumber(r[1])] = true
                            end
                        end
                    end
                    Q[id] = q
                    table.insert(gardees, id)
                end
            end
        end
    end
    -- Groupes de quetes exclusives (union des liens, dans les deux sens).
    local parent = {}
    local function Racine(x)
        while parent[x] and parent[x] ~= x do x = parent[x] end
        return x
    end
    for rang, id in ipairs(gardees) do
        if rang % 50 == 0 then Pause() end
        for _, autre in ipairs(Q[id].exclusives or {}) do
            if Q[autre] then
                local a, b = Racine(id), Racine(autre)
                if a ~= b then parent[math.max(a, b)] = math.min(a, b) end
            end
        end
    end
    local groupes, groupeDe = {}, {}
    for rang, id in ipairs(gardees) do
        if rang % 50 == 0 then Pause() end
        local r = Racine(id)
        local g = groupeDe[r]
        if not g then
            g = { ids = {}, zone = Q[r] and Q[r].zone or Q[id].zone }
            groupeDe[r] = g
            table.insert(groupes, g)
        end
        table.insert(g.ids, id)
        groupeDe[id] = g
        Q[id].exclusives = nil
    end
    -- Suites : de la premiere quete a la derniere, par la quete suivante.
    local avant = {}
    for _, id in ipairs(gardees) do
        local s = Q[id].suivante
        if s and Q[s] then avant[s] = id end
    end
    local chaines = {}
    for rang, id in ipairs(gardees) do
        if rang % 50 == 0 then Pause() end
        if Q[id].suivante and Q[Q[id].suivante] and not avant[id] then
            local suite, vu, x = {}, {}, id
            while x and Q[x] and not vu[x] and #suite < 60 do
                vu[x] = true
                table.insert(suite, x)
                x = Q[x].suivante
            end
            if #suite >= 3 then
                local c = { premiere = id, ids = suite, zone = Q[id].zone, niveau = Q[id].niveau }
                table.insert(chaines, c)
                for _, q in ipairs(suite) do Q[q].chaine = #chaines end
            end
        end
    end
    -- Niveau typique de chaque zone (la mediane), pour les ranger.
    local niveaux = {}
    for _, id in ipairs(gardees) do
        local q = Q[id]
        if q.niveau > 0 then
            niveaux[q.zone] = niveaux[q.zone] or {}
            table.insert(niveaux[q.zone], q.niveau)
        end
    end
    local niveauZone = {}
    for z, l in pairs(niveaux) do
        table.sort(l)
        niveauZone[z] = l[math.max(1, math.floor(#l / 2))]
    end
    etat.progresQuetes = 1
    etat.quetes = { Q = Q, groupes = groupes, groupeDe = groupeDe, chaines = chaines, niveauZone = niveauZone, total = #gardees }
    NS.Changer("quetes", "donjons", "reputations")
end

-- Index des PNJ boss (rang "boss" de la base) par zone, seulement dans les
-- raids (la base n'a qu'une partie des boss de donjon) et seulement les PNJ
-- hostiles qui ne donnent ni ne reprennent de quete (pas les dragons amis
-- de la fin d'Ahn'Qiraj, ni Malfurion dans le temple).
local function ConstruireBoss()
    local ids = TousLesIds("NpcDB")
    if not ids then etat.boss = false return end
    local parZone = {}
    for rang, id in ipairs(ids) do
        if rang % 5 == 0 then Pause() end
        if tonumber(Lire("NpcDB", id, "rank")) == 3 then
            local zone = tonumber(Lire("NpcDB", id, "zoneID"))
            local d = zone and base.DonjonDeZone(zone)
            local ami = Lire("NpcDB", id, "friendlyToFaction")
            local parle = Lire("NpcDB", id, "questStarts") or Lire("NpcDB", id, "questEnds")
            if d and d.raid and ami == nil and not (type(parle) == "table" and #parle > 0) then
                parZone[d.zone] = parZone[d.zone] or {}
                table.insert(parZone[d.zone], { id = id, nom = Lire("NpcDB", id, "name") or ("#" .. id) })
            end
        end
    end
    for _, l in pairs(parZone) do table.sort(l, function(a, b) return tostring(a.nom) < tostring(b.nom) end) end
    etat.boss = parZone
    NS.Changer("donjons")
end

-- ---------------------------------------------------------------------------
-- Index des objets obtenables, par famille et sous-famille du jeu
-- ---------------------------------------------------------------------------

local function ConstruireObjets()
    local ids = TousLesIds("ItemDB")
    if not ids then etat.objets = false return end
    local parSous, de, familles = {}, {}, {}
    local n = 0
    local fabriques = base.ObjetsFabriques()
    for rang, id in ipairs(ids) do
        Pause()
        if rang % 200 == 0 then Avancer("progresObjets", rang / #ids) end
        local ok = false
        for _, champ in ipairs({ "npcDrops", "objectDrops", "itemDrops", "vendors", "questRewards" }) do
            local s = Lire("ItemDB", id, champ)
            if type(s) == "table" and next(s) ~= nil then ok = true break end
        end
        if not ok and fabriques[id] then ok = true end
        if ok then
            local famille = tonumber(Lire("ItemDB", id, "class"))
            local sous = tonumber(Lire("ItemDB", id, "subClass"))
            if not famille then
                -- La famille selon le jeu, si la base ne la donne pas.
                local _, _, _, _, _, f, sf = NS.Jeu("C_Item.GetItemInfoInstant", id)
                famille, sous = tonumber(f), tonumber(sf)
            end
            famille, sous = famille or 15, sous or 0
            local cle = famille * 1000 + sous
            if not parSous[cle] then
                parSous[cle] = { famille = famille, sous = sous, ids = {} }
                familles[famille] = familles[famille] or {}
                table.insert(familles[famille], cle)
            end
            table.insert(parSous[cle].ids, id)
            de[id] = cle
            n = n + 1
        end
    end
    etat.progresObjets = 1
    etat.objets = { parSous = parSous, de = de, familles = familles, total = n }
    NS.Changer("objets")
end

-- Lance les index manquants, l'un apres l'autre (quetes d'abord).
function base.Preparer()
    if etat.quetes == nil and not travail.EnCours("quetes") then
        if not base.QuestieDisponible() then etat.quetes = false
        else travail.Lancer("quetes", ConstruireQuetes, nil, function() etat.quetes = false end) end
    end
    if etat.boss == nil and not travail.EnCours("boss") then
        if not base.QDB("NpcDB") then etat.boss = false
        else travail.Lancer("boss", ConstruireBoss, nil, function() etat.boss = false end) end
    end
    if etat.objets == nil and not travail.EnCours("objets") then
        if not base.QDB("ItemDB") then etat.objets = false
        else travail.Lancer("objets", ConstruireObjets, nil, function() etat.objets = false end) end
    end
end

function base.Quetes() return etat.quetes end
function base.Objets() return etat.objets end
function base.BossDeZone(zone) return type(etat.boss) == "table" and etat.boss[zone] or nil end

-- Les objets fabriques par une recette connue du compte comptent aussi.
function base.ObjetsFabriques()
    local t = {}
    local d = _G.CraftCoreDB
    for _, r in pairs(type(d) == "table" and type(d.recettes) == "table" and d.recettes or {}) do
        local o = type(r) == "table" and tonumber(r.objetProduit)
        if o then t[o] = true end
    end
    return t
end

-- Les factions dont la reputation se monte : celles que les quetes donnent,
-- et celles que les personnages ont vues dans le jeu.
function base.Factions()
    local t = {}
    for id in pairs(etat.factions or {}) do t[id] = true end
    for id in pairs(base.DB().factions or {}) do t[tonumber(id) or id] = true end
    return t
end

-- Cle d'un boss vaincu : le PNJ de la base s'il est connu, sinon la rencontre.
function base.CleBoss(zone, idRencontre, nom)
    local c = NS.Cle(nom)
    local connus = base.BossDeZone(zone)
    for _, b in ipairs(connus or {}) do
        if c ~= "" and NS.Cle(b.nom) == c then return "pnj:" .. b.id end
    end
    -- Les boss de la base se suivent par le journal de combat : une
    -- rencontre qui ne porte pas leur nom ne s'ajoute pas en double.
    if connus then return nil end
    if tonumber(idRencontre) then return "renc:" .. tonumber(idRencontre) end
    if c ~= "" then return "nom:" .. c end
    return nil
end
