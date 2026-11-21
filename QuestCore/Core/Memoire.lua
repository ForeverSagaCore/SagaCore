local _, NS = ...

-- La base personnelle du compte, a cote de Questie.
--
-- 1. Copie : chaque quete que le compte a touchee (prise, faite, guidee) est
--    recopiee depuis Questie, avec ses PNJ, objets et lieux. Si Questie
--    manque, QuestCore lit cette copie : ce qui a deja ete fait reste affiche.
-- 2. Marquage en jeu : ou l'on parle a un PNJ, ou l'on tue une cible ou
--    ramasse un objet d'objectif. Ces positions, relevees sur WoW Forever
--    meme, passent avant celles de Questie sur la carte.
--
-- Commune a tous les personnages du compte (QuestCoreDB.monde). Reservee pour
-- l'instant au poste de l'auteur (/sagacore prive).

NS.memoire = {}
local memoire = NS.memoire

local CELLULE = 2          -- deux releves a moins de 2 % l'un de l'autre n'en font qu'un
local MAX_POINTS = 25      -- releves gardes par PNJ ou objet
local PAR_TOUR = 20        -- quetes recopiees par tour, pour ne rien figer

function memoire.Active()
    local S = _G.CoreSuite
    return type(S) == "table" and type(S.Prive) == "function" and S.Prive() == true
end

local function Monde()
    QuestCoreDB = type(QuestCoreDB) == "table" and QuestCoreDB or {}
    local m = QuestCoreDB.monde
    if type(m) ~= "table" then
        m = {}
        QuestCoreDB.monde = m
    end
    m.bases = type(m.bases) == "table" and m.bases or {}
    m.cartes = type(m.cartes) == "table" and m.cartes or {}
    m.gravees = type(m.gravees) == "table" and m.gravees or {}
    m.releves = type(m.releves) == "table" and m.releves or {}
    return m
end

-- ---------------------------------------------------------------------------
-- La copie, lue a la place de Questie quand il manque
-- ---------------------------------------------------------------------------

local copies = {}
-- Une base au meme format que celles de Questie : Get(id, champ), GetAllIds().
function memoire.Base(entite)
    if not memoire.Active() then return nil end
    local b = Monde().bases[entite]
    if type(b) ~= "table" or not next(b) then return nil end
    if not copies[entite] then
        copies[entite] = {
            Get = function(id, champ)
                local e = Monde().bases[entite][id]
                if type(e) ~= "table" then return nil end
                return e[champ]
            end,
            GetAllIds = function()
                local ids = {}
                for id in pairs(Monde().bases[entite]) do table.insert(ids, id) end
                table.sort(ids)
                return ids
            end,
        }
    end
    return copies[entite]
end

function memoire.Carte(zone)
    if not memoire.Active() then return nil end
    return Monde().cartes[zone]
end

local CHAMPS = {
    QuestDB = { "name", "questLevel", "requiredLevel", "requiredMaxLevel", "requiredRaces", "requiredClasses",
        "zoneOrSort", "startedBy", "finishedBy", "objectives", "triggerEnd", "preQuestGroup", "preQuestSingle",
        "nextQuestInChain", "childQuests", "exclusiveTo", "specialFlags" },
    NpcDB = { "name", "spawns", "zoneID" },
    ObjectDB = { "name", "spawns" },
    ItemDB = { "name", "npcDrops", "objectDrops" },
}

local function Questie(entite)
    local e = _G[entite]
    if type(e) == "table" and type(e.Get) == "function" then return e end
    return nil
end

local function Copier(entite, id)
    local source = Questie(entite)
    if not source or type(id) ~= "number" then return nil end
    local m = Monde()
    m.bases[entite] = m.bases[entite] or {}
    local fiche = {}
    for _, champ in ipairs(CHAMPS[entite]) do
        local ok, v = pcall(source.Get, id, champ)
        if ok and v ~= nil then fiche[champ] = v end
    end
    if not next(fiche) then return nil end
    m.bases[entite][id] = fiche
    -- Les zones de ses apparitions : leur carte du jeu, pour s'en passer ensuite.
    if type(fiche.spawns) == "table" and NS.carte and NS.carte.CarteDeZone then
        for zone in pairs(fiche.spawns) do
            local c = NS.carte.CarteDeZone(zone)
            if c then m.cartes[zone] = c end
        end
    end
    return fiche
end

local function Liste(t, rang)
    return type(t) == "table" and type(t[rang]) == "table" and t[rang] or {}
end

-- Recopie une quete, et ce qu'il faut pour l'afficher sans Questie.
function memoire.Graver(id)
    if not memoire.Active() or type(id) ~= "number" or not Questie("QuestDB") then return end
    local q = Copier("QuestDB", id)
    if not q then return end
    for _, champ in ipairs({ "startedBy", "finishedBy" }) do
        for _, pnj in ipairs(Liste(q[champ], 1)) do Copier("NpcDB", pnj) end
        for _, objet in ipairs(Liste(q[champ], 2)) do Copier("ObjectDB", objet) end
        for _, objet in ipairs(Liste(q[champ], 3)) do Copier("ItemDB", objet) end
    end
    for _, o in ipairs(Liste(q.objectives, 1)) do Copier("NpcDB", o[1]) end
    for _, o in ipairs(Liste(q.objectives, 2)) do Copier("ObjectDB", o[1]) end
    for _, o in ipairs(Liste(q.objectives, 3)) do
        local objet = Copier("ItemDB", o[1])
        for _, pnj in ipairs(objet and type(objet.npcDrops) == "table" and objet.npcDrops or {}) do Copier("NpcDB", pnj) end
        for _, obj in ipairs(objet and type(objet.objectDrops) == "table" and objet.objectDrops or {}) do Copier("ObjectDB", obj) end
    end
    if type(q.triggerEnd) == "table" and type(q.triggerEnd[2]) == "table" and NS.carte and NS.carte.CarteDeZone then
        for zone in pairs(q.triggerEnd[2]) do
            local c = NS.carte.CarteDeZone(zone)
            if c then Monde().cartes[zone] = c end
        end
    end
    Monde().gravees[id] = true
end

-- Toutes les quetes connues du compte, peu a peu : celles de chaque
-- personnage, prises ou faites, pas encore recopiees.
local enCours = false
function memoire.Rattraper()
    if enCours or not memoire.Active() or not Questie("QuestDB") then return end
    local a, m = {}, Monde()
    for _, p in pairs(type(QuestCoreDB.persos) == "table" and QuestCoreDB.persos or {}) do
        for _, t in ipairs({ p.quetes, p.faites }) do
            for id in pairs(type(t) == "table" and t or {}) do
                if type(id) == "number" and not m.gravees[id] then a[#a + 1] = id end
            end
        end
    end
    if #a == 0 then return end
    enCours = true
    local rang, cadre = 1, CreateFrame("Frame")
    cadre:SetScript("OnUpdate", function(self)
        for i = rang, math.min(#a, rang + PAR_TOUR - 1) do pcall(memoire.Graver, a[i]) end
        rang = rang + PAR_TOUR
        if rang > #a then
            enCours = false
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Marquage en jeu
-- ---------------------------------------------------------------------------

-- Valeur cachee par le jeu (combat, instance) : illisible, on n'y touche pas.
local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) end

local function Position()
    local cm = _G.C_Map
    if not (cm and cm.GetBestMapForUnit and cm.GetPlayerMapPosition) then return nil end
    local idCarte = cm.GetBestMapForUnit("player")
    if not idCarte or Secret(idCarte) then return nil end
    local pos = cm.GetPlayerMapPosition(idCarte, "player")
    if not pos or Secret(pos) then return nil end
    local x, y = pos:GetXY()
    if Secret(x) or Secret(y) or not x or not y or (x == 0 and y == 0) then return nil end
    return idCarte, x * 100, y * 100
end

local function DeGUID(guid)
    if Secret(guid) or type(guid) ~= "string" then return nil end
    local ok, genre, id = pcall(string.match, guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if not ok then return nil end
    id = tonumber(id)
    if not id then return nil end
    if genre == "Creature" or genre == "Vehicle" then return "NpcDB", id end
    if genre == "GameObject" then return "ObjectDB", id end
    return nil
end

function memoire.Noter(entite, id)
    if not memoire.Active() or not entite or not id then return end
    local idCarte, x, y = Position()
    if not idCarte then return end
    local m = Monde()
    m.releves[entite] = m.releves[entite] or {}
    local liste = m.releves[entite][id] or {}
    m.releves[entite][id] = liste
    for _, pt in ipairs(liste) do
        if pt[1] == idCarte and math.abs(pt[2] - x) < CELLULE and math.abs(pt[3] - y) < CELLULE then
            pt[4] = (pt[4] or 1) + 1
            return
        end
    end
    if #liste >= MAX_POINTS then return end
    table.insert(liste, { idCarte, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10, 1 })
end

-- Releves d'un PNJ ou d'un objet : { { carte, x, y, fois }, ... } ou nil.
function memoire.Releves(entite, id)
    if not memoire.Active() then return nil end
    local r = Monde().releves[entite]
    local liste = r and r[id]
    if type(liste) == "table" and #liste > 0 then return liste end
    return nil
end

-- Cibles des quetes en cours : on ne releve que ce qui sert.
local cibles, ciblesAJour = { NpcDB = {}, ObjectDB = {} }, false
local function Cibles()
    if ciblesAJour then return cibles end
    cibles = { NpcDB = {}, ObjectDB = {} }
    local p = NS.base and NS.base.Perso and NS.ClePersonnage and NS.base.Perso(NS.ClePersonnage())
    local Lire = NS.ref and NS.ref.Lire
    for id in pairs(p and type(p.quetes) == "table" and p.quetes or {}) do
        local o = Lire and Lire("QuestDB", id, "objectives")
        for _, c in ipairs(Liste(o, 1)) do cibles.NpcDB[c[1]] = true end
        for _, c in ipairs(Liste(o, 2)) do cibles.ObjectDB[c[1]] = true end
        for _, c in ipairs(Liste(o, 3)) do
            for _, pnj in ipairs(Lire("ItemDB", c[1], "npcDrops") or {}) do cibles.NpcDB[pnj] = true end
            for _, obj in ipairs(Lire("ItemDB", c[1], "objectDrops") or {}) do cibles.ObjectDB[obj] = true end
        end
    end
    ciblesAJour = true
    return cibles
end

local function NoterInterlocuteur()
    local entite, id = DeGUID(_G.UnitGUID and _G.UnitGUID("npc"))
    if entite then memoire.Noter(entite, id) end
end

local cadre = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING",
    "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE",
    "LOOT_OPENED" }) do
    pcall(cadre.RegisterEvent, cadre, ev)
end
cadre:SetScript("OnEvent", function(_, ev, a1, a2)
    if not memoire.Active() then return end
    if ev == "PLAYER_LOGIN" then
        -- Questie charge sa base apres la connexion : on attend un peu.
        if _G.C_Timer then
            _G.C_Timer.After(20, function() pcall(memoire.Rattraper) end)
            _G.C_Timer.After(90, function() pcall(memoire.Rattraper) end)
        end
    elseif ev == "QUEST_ACCEPTED" or ev == "QUEST_TURNED_IN" then
        NoterInterlocuteur()
        -- QUEST_ACCEPTED donne (index, id) sur certains clients, (id) sur d'autres.
        local id = (ev == "QUEST_ACCEPTED" and type(a2) == "number" and a2 > 0) and a2 or a1
        pcall(memoire.Graver, tonumber(id))
        ciblesAJour = false
    elseif ev == "QUEST_LOG_UPDATE" then
        ciblesAJour = false
    elseif ev == "LOOT_OPENED" then
        if type(_G.GetNumLootItems) ~= "function" or type(_G.GetLootSourceInfo) ~= "function" then return end
        -- Le journal de combat est interdit aux add-ons sur ce client : une
        -- cible tuee se note quand on fouille son corps.
        for i = 1, _G.GetNumLootItems() do
            local entite, id = DeGUID((_G.GetLootSourceInfo(i)))
            if entite and Cibles()[entite] and Cibles()[entite][id] then memoire.Noter(entite, id) break end
        end
    else
        NoterInterlocuteur()
    end
end)
