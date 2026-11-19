local _, NS = ...

-- Mon histoire : pour chaque zone, toutes les quetes que ce personnage peut
-- y faire (tous niveaux, selon sa race et sa classe), combien il en a deja
-- rendu, et lesquelles restent. Lu dans QuestieDB, une fois par race et
-- classe, puis garde.

NS.histoire = {}
local histoire = NS.histoire

local Lire = function(...) return NS.ref.Lire(...) end

local CLASSES = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7,
    MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11 }
local RACES_CAMP = { Alliance = 1 + 4 + 8 + 64, Horde = 2 + 16 + 32 + 128 }
local REPETABLE = 1

local cache = {}

local function Bit(masque, rang)
    if not bit or not bit.band then return true end
    return bit.band(masque, 2 ^ (rang - 1)) ~= 0
end

local function Admise(p, id)
    local races = tonumber(Lire("QuestDB", id, "requiredRaces")) or 0
    if races ~= 0 then
        if p.race then
            if not Bit(races, p.race) then return false end
        elseif p.faction and RACES_CAMP[p.faction] and bit and bit.band then
            if bit.band(races, RACES_CAMP[p.faction]) == 0 then return false end
        end
    end
    local classes = tonumber(Lire("QuestDB", id, "requiredClasses")) or 0
    local classe = CLASSES[p.classe or ""]
    if classes ~= 0 and classe and not Bit(classes, classe) then return false end
    local special = tonumber(Lire("QuestDB", id, "specialFlags")) or 0
    if special ~= 0 and bit and bit.band(special, REPETABLE) ~= 0 then return false end
    return true
end

histoire.Admise = Admise

-- ---------------------------------------------------------------------------
-- Quetes retirees : qu'on ne peut plus prendre dans WoW Forever
-- ---------------------------------------------------------------------------
--
-- Aucun donneur (PNJ ou objet du monde) avec une position connue, et pas
-- d'objet de depart qu'on puisse obtenir (lache par un monstre, trouve dans
-- un objet, vendu). Exemple : "Bienvenue !", lancee par le bon cadeau de
-- l'edition collector de 2004.

local function APosition(base, id)
    local positions = Lire(base, id, "spawns")
    return type(positions) == "table" and next(positions) ~= nil
end

local function Obtenable(objet)
    for _, champ in ipairs({ "npcDrops", "objectDrops", "itemDrops", "vendors" }) do
        local sources = Lire("ItemDB", objet, champ)
        if type(sources) == "table" and next(sources) ~= nil then return true end
    end
    return false
end

local retireesVues = {}
function histoire.Retiree(id)
    local vu = retireesVues[id]
    if vu ~= nil then return vu end
    local debut = Lire("QuestDB", id, "startedBy")
    local retiree = true
    if type(debut) ~= "table" then
        retiree = false   -- rien dans la base : on ne juge pas
    else
        for _, pnj in ipairs(type(debut[1]) == "table" and debut[1] or {}) do
            if APosition("NpcDB", pnj) then retiree = false break end
        end
        if retiree then
            for _, objet in ipairs(type(debut[2]) == "table" and debut[2] or {}) do
                if APosition("ObjectDB", objet) then retiree = false break end
            end
        end
        if retiree then
            for _, objet in ipairs(type(debut[3]) == "table" and debut[3] or {}) do
                if Obtenable(objet) then retiree = false break end
            end
        end
    end
    retireesVues[id] = retiree
    return retiree
end

-- Reglage : compter aussi les quetes retirees (non par defaut).
function histoire.AvecRetirees() return NS.base.ReglagesGeneraux().histoireRetirees == true end
function histoire.PoserAvecRetirees(v) NS.base.ReglagesGeneraux().histoireRetirees = v and true or nil end

-- { [zone] = { ids = {...}, niveau = niveau typique } } pour ce personnage.
local function Zones(p)
    local cle = tostring(p.race) .. ":" .. tostring(p.classe) .. ":" .. tostring(p.faction)
    if cache[cle] then return cache[cle] end
    local base = _G.QuestDB
    local ids = base and base.GetAllIds and base.GetAllIds() or {}
    local zones = {}
    for _, id in ipairs(ids) do
        local zone = tonumber(Lire("QuestDB", id, "zoneOrSort"))
        if zone and zone > 0 and Admise(p, id) then
            local z = zones[zone]
            if not z then
                z = { ids = {}, niveaux = {} }
                zones[zone] = z
            end
            table.insert(z.ids, id)
            local niveau = tonumber(Lire("QuestDB", id, "questLevel")) or 0
            if niveau > 0 then table.insert(z.niveaux, niveau) end
        end
    end
    -- Niveau typique : la mediane des quetes de la zone.
    for _, z in pairs(zones) do
        table.sort(z.niveaux)
        z.niveau = z.niveaux[math.max(1, math.floor(#z.niveaux / 2))] or 0
        z.niveaux = nil
    end
    cache[cle] = zones
    return zones
end

local function NomDeZone(zone)
    local info = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone)
    return type(info) == "string" and info or ("#" .. tostring(zone))
end

-- Experience encore a prendre dans une zone du bilan : les quetes restantes
-- (celles du journal avec leur vraie recompense, les autres estimees par la
-- base selon le niveau du personnage). Gardee tant que rien ne change.
local xpVue = {}
function histoire.XPRestante(p, z)
    if not p or not z then return 0 end
    local cle = tostring(p.cle) .. ":" .. tostring(z.zone) .. ":" .. #z.restantes .. ":" .. tostring(p.niveau)
    if xpVue[cle] then return xpVue[cle] end
    local total = 0
    for _, id in ipairs(z.restantes) do
        local q = p.quetes and p.quetes[id]
        local connue = q and q.recompenses and tonumber(q.recompenses.xp)
        total = total + (connue or NS.ref.XPDeLaBase(id, p.niveau) or 0)
    end
    xpVue[cle] = total
    return total
end

-- Liste des zones, dans l'ordre de l'histoire (niveau typique), avec pour
-- chacune : nom, total, faites, pourcentage, ids restantes. Sans le reglage
-- "quetes retirees", celles qu'on ne peut plus prendre ne comptent pas
-- (sauf si ce personnage les a faites, ou les a en cours).
function histoire.Bilan(p, toutes)
    local liste = {}
    local totalTout, faitesTout = 0, 0
    local avecRetirees = histoire.AvecRetirees()
    for zone, z in pairs(Zones(p)) do
        local faites, restantes, total = 0, {}, 0
        for _, id in ipairs(z.ids) do
            if p.faites and p.faites[id] then
                faites, total = faites + 1, total + 1
            elseif avecRetirees or (p.quetes and p.quetes[id]) or not histoire.Retiree(id) then
                total = total + 1
                table.insert(restantes, id)
            end
        end
        if (faites > 0 or toutes) and total > 0 then
            table.insert(liste, { zone = zone, nom = NomDeZone(zone), total = total, faites = faites,
                pct = total > 0 and math.floor(faites * 100 / total) or 0, restantes = restantes, niveau = z.niveau })
            totalTout, faitesTout = totalTout + total, faitesTout + faites
        end
    end
    table.sort(liste, function(a, b)
        if a.niveau ~= b.niveau then return a.niveau < b.niveau end
        return a.nom < b.nom
    end)
    return liste, faitesTout, totalTout
end
