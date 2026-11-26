local _, NS = ...

-- Les quetes de classe : toutes celles de la base QuestieDB reservees a une
-- classe (masque requiredClasses), lues une fois, peu a peu, sans bloquer le
-- jeu. Pour un personnage, elles sont filtrees par race et par camp, puis
-- reunies en chaines (prerequis et suites), avec l'etat de chaque etape :
-- faite, en cours, a prendre, plus tard (niveau), bloquee (une etape avant).
--
-- Chaque personnage garde sa liste de quetes de classe faites (ClassCoreDB),
-- pour voir aussi celles de ses autres personnages.

NS.quetes = {}
local Q = NS.quetes
local T = NS.T

local index           -- { [id] = fiche }
local enCours, pret = false, false
local surPret = {}

local function Base(nom)
    local e = _G[nom]
    if type(e) == "table" and type(e.Get) == "function" then return e end
    return nil
end
local function Lire(entite, id, champ)
    local e = Base(entite)
    if not e or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end
Q.Lire = Lire

function Q.BaseDisponible() return Base("QuestDB") ~= nil end
function Q.Pret() return pret end
function Q.QuandPret(fn) if pret then pcall(fn) else table.insert(surPret, fn) end end

-- Un bit d'un masque (sans dependre de la bibliotheque bit).
local function Bit(masque, rang)
    masque = tonumber(masque) or 0
    return math.floor(masque / 2 ^ (rang - 1)) % 2 == 1
end
local function UnBitCommun(a, b)
    for r = 1, 24 do if Bit(a, r) and Bit(b, r) then return true end end
    return false
end

-- Une quete qu'on ne peut plus prendre : aucun donneur avec une position.
local function APosition(entite, id)
    local p = Lire(entite, id, "spawns")
    return type(p) == "table" and next(p) ~= nil
end
local function Retiree(debut)
    if type(debut) ~= "table" then return false end
    for _, pnj in ipairs(type(debut[1]) == "table" and debut[1] or {}) do if APosition("NpcDB", pnj) then return false end end
    for _, ob in ipairs(type(debut[2]) == "table" and debut[2] or {}) do if APosition("ObjectDB", ob) then return false end end
    if type(debut[3]) == "table" and #debut[3] > 0 then return false end
    return (type(debut[1]) == "table" and #debut[1] > 0) or (type(debut[2]) == "table" and #debut[2] > 0)
end

local function Liste(v)
    local r = {}
    for _, x in ipairs(type(v) == "table" and v or {}) do if tonumber(x) then table.insert(r, tonumber(x)) end end
    return r
end

-- L'index, construit a la premiere demande (300 quetes par image).
function Q.Indexer()
    if enCours or pret then return end
    local base = Base("QuestDB")
    if not (base and base.GetAllIds) then return end
    local ok, ids = pcall(base.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    enCours = true
    index = {}
    local rang, cadre = 1, CreateFrame("Frame")
    cadre:SetScript("OnUpdate", function(self)
        local fin = math.min(#ids, rang + 300)
        for i = rang, fin do
            local id = ids[i]
            local classes = tonumber(Lire("QuestDB", id, "requiredClasses")) or 0
            if classes ~= 0 then
                local special = tonumber(Lire("QuestDB", id, "specialFlags")) or 0
                local debut = Lire("QuestDB", id, "startedBy")
                if not Bit(special, 1) and not Retiree(debut) then
                    index[id] = {
                        id = id, classes = classes,
                        races = tonumber(Lire("QuestDB", id, "requiredRaces")) or 0,
                        niveau = tonumber(Lire("QuestDB", id, "questLevel")) or 0,
                        requis = tonumber(Lire("QuestDB", id, "requiredLevel")) or 0,
                        groupe = Liste(Lire("QuestDB", id, "preQuestGroup")),
                        une = Liste(Lire("QuestDB", id, "preQuestSingle")),
                        suivante = tonumber(Lire("QuestDB", id, "nextQuestInChain")),
                        exclusives = Liste(Lire("QuestDB", id, "exclusiveTo")),
                    }
                end
            end
        end
        rang = fin + 1
        if rang > #ids then
            self:SetScript("OnUpdate", nil)
            enCours, pret = false, true
            for _, fn in ipairs(surPret) do pcall(fn) end
            surPret = {}
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Les personnages
-- ---------------------------------------------------------------------------

local function Persos()
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.persos = type(ClassCoreDB.persos) == "table" and ClassCoreDB.persos or {}
    return ClassCoreDB.persos
end
Q.Persos = Persos

local function FaiteEnJeu(id)
    local C = _G.C_QuestLog
    local f = (C and C.IsQuestFlaggedCompleted) or _G.IsQuestFlaggedCompleted
    if not f then return false end
    local ok, oui = pcall(f, id)
    return ok and oui == true
end
local function DansLeJournal(id)
    local C = _G.C_QuestLog
    if C and C.GetLogIndexForQuestID then
        local ok, i = pcall(C.GetLogIndexForQuestID, id)
        return ok and i ~= nil and i ~= 0
    end
    return false
end

-- Le personnage connecte : sa fiche, mise a jour (quetes de classe faites).
function Q.Moi()
    local cle = NS.ClePersonnage()
    if not cle then return nil end
    local E = NS.etat
    local p = Persos()[cle] or {}
    Persos()[cle] = p
    p.classe = E.Classe() or p.classe
    p.race = E.Race() or p.race
    p.camp = E.Camp() or p.camp
    p.niveau = E.Niveau()
    p.faites = type(p.faites) == "table" and p.faites or {}
    if pret then
        local idClasse = NS.classes.ID[p.classe or ""]
        for id, f in pairs(index) do
            if idClasse and Bit(f.classes, idClasse) and FaiteEnJeu(id) then p.faites[id] = true end
        end
    end
    p.maj = (_G.time and _G.time()) or 0
    return p, cle
end

-- La liste des personnages connus, le connecte d'abord.
function Q.ListePersos()
    local moi = NS.ClePersonnage()
    local l = {}
    for cle, p in pairs(Persos()) do
        if type(p) == "table" and NS.classes.ID[p.classe or ""] then table.insert(l, { cle = cle, p = p }) end
    end
    table.sort(l, function(a, b)
        if (a.cle == moi) ~= (b.cle == moi) then return a.cle == moi end
        return a.cle < b.cle
    end)
    return l
end

-- ---------------------------------------------------------------------------
-- Chaines et etats
-- ---------------------------------------------------------------------------

function Q.Nom(id)
    local C = _G.C_QuestLog
    if C and C.GetTitleForQuestID then
        local ok, t = pcall(C.GetTitleForQuestID, id)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
    local n = Lire("QuestDB", id, "name")
    return type(n) == "string" and n or ("#" .. id)
end

local CAMPS = { Alliance = 1 + 4 + 8 + 64, Horde = 2 + 16 + 32 + 128 }
local function Admise(f, p)
    local idClasse = NS.classes.ID[p.classe or ""]
    if not idClasse or not Bit(f.classes, idClasse) then return false end
    if f.races ~= 0 then
        if p.race then return Bit(f.races, p.race) end
        if p.camp and CAMPS[p.camp] then return UnBitCommun(f.races, CAMPS[p.camp]) end
    end
    return true
end

-- Etat d'une quete pour un personnage (connecte : journal en direct).
local function Etat(f, p, connecte, faites)
    if faites[f.id] then return "faite" end
    if connecte and DansLeJournal(f.id) then return "cours" end
    for _, pre in ipairs(f.groupe) do
        if index[pre] and not faites[pre] then return "bloquee" end
    end
    if #f.une > 0 then
        local ok, connue = false, false
        for _, pre in ipairs(f.une) do
            if index[pre] then connue = true end
            if faites[pre] then ok = true end
        end
        if connue and not ok then return "bloquee" end
    end
    if (p.niveau or 1) < (f.requis > 0 and f.requis or 1) then return "niveau" end
    return "prendre"
end

-- Les chaines du personnage : { titre, niveau, etapes = { {id, nom, etat, requis} }, faites, total, etat }.
function Q.Chaines(p, connecte)
    if not pret or not p then return {} end
    local faites = {}
    for id in pairs(p.faites or {}) do faites[id] = true end
    if connecte then for id in pairs(index) do if FaiteEnJeu(id) then faites[id] = true end end end
    -- Quetes du personnage, sans celles remplacees par une autre deja faite.
    local miennes = {}
    for id, f in pairs(index) do
        if Admise(f, p) then
            local remplacee = false
            if not faites[id] then
                for _, x in ipairs(f.exclusives) do if faites[x] then remplacee = true end end
            end
            if not remplacee then miennes[id] = f end
        end
    end
    -- Reunir : prerequis et suites (union des liens).
    local parent = {}
    local function Racine(x)
        while parent[x] and parent[x] ~= x do x = parent[x] end
        return x
    end
    local function Unir(a, b)
        if not (miennes[a] and miennes[b]) then return end
        local ra, rb = Racine(a), Racine(b)
        if ra ~= rb then parent[ra] = rb end
    end
    for id in pairs(miennes) do parent[id] = id end
    for id, f in pairs(miennes) do
        for _, pre in ipairs(f.groupe) do Unir(id, pre) end
        for _, pre in ipairs(f.une) do Unir(id, pre) end
        if f.suivante then Unir(id, f.suivante) end
    end
    local groupes = {}
    for id in pairs(miennes) do
        local r = Racine(id)
        groupes[r] = groupes[r] or {}
        table.insert(groupes[r], id)
    end
    -- Profondeur de chaque etape (nombre de prerequis en amont).
    local prof = {}
    local function Profondeur(id, vus)
        if prof[id] then return prof[id] end
        vus = vus or {}
        if vus[id] then return 0 end
        vus[id] = true
        local f, d = miennes[id], 0
        for _, pre in ipairs(f and f.groupe or {}) do if miennes[pre] then d = math.max(d, Profondeur(pre, vus) + 1) end end
        for _, pre in ipairs(f and f.une or {}) do if miennes[pre] then d = math.max(d, Profondeur(pre, vus) + 1) end end
        prof[id] = d
        return d
    end
    local chaines = {}
    for _, ids in pairs(groupes) do
        table.sort(ids, function(a, b)
            local pa, pb = Profondeur(a), Profondeur(b)
            if pa ~= pb then return pa < pb end
            local fa, fb = miennes[a], miennes[b]
            if fa.requis ~= fb.requis then return fa.requis < fb.requis end
            return a < b
        end)
        local c = { etapes = {}, faites = 0, total = #ids, niveau = 99 }
        local titre
        for _, id in ipairs(ids) do
            local f = miennes[id]
            local e = Etat(f, p, connecte, faites)
            table.insert(c.etapes, { id = id, nom = Q.Nom(id), etat = e, requis = f.requis, niveau = f.niveau })
            if e == "faite" then c.faites = c.faites + 1 end
            c.niveau = math.min(c.niveau, f.requis > 0 and f.requis or f.niveau)
            if not titre and NS.classes.CHAINES[id] then titre = NS.classes.CHAINES[id]() end
        end
        c.titre = titre or c.etapes[#c.etapes].nom
        if c.faites >= c.total then c.etat = "faite"
        else
            c.etat = "plus tard"
            for _, e in ipairs(c.etapes) do
                if e.etat == "cours" then c.etat = "cours" break end
                if e.etat == "prendre" then c.etat = "prendre" end
            end
        end
        c.cle = ids[1]
        table.insert(chaines, c)
    end
    local RANG = { cours = 1, prendre = 2, ["plus tard"] = 3, faite = 4 }
    table.sort(chaines, function(a, b)
        if RANG[a.etat] ~= RANG[b.etat] then return RANG[a.etat] < RANG[b.etat] end
        if a.niveau ~= b.niveau then return a.niveau < b.niveau end
        return a.cle < b.cle
    end)
    return chaines
end

-- Les etapes a guider d'une chaine : celles en cours, sinon celles a prendre.
function Q.AGuider(c)
    local cours, prendre = {}, {}
    for _, e in ipairs(c.etapes) do
        if e.etat == "cours" then table.insert(cours, e.id) elseif e.etat == "prendre" then table.insert(prendre, e.id) end
    end
    return #cours > 0 and cours or prendre
end

-- Qui donne la quete, et ou : "Nom (Zone 45, 52)".
function Q.Donneur(id)
    local debut = Lire("QuestDB", id, "startedBy")
    if type(debut) ~= "table" then return nil end
    for _, pnj in ipairs(type(debut[1]) == "table" and debut[1] or {}) do
        local nom = Lire("NpcDB", pnj, "name")
        if nom then
            local lieu
            local spawns = Lire("NpcDB", pnj, "spawns")
            for zone, pts in pairs(type(spawns) == "table" and spawns or {}) do
                local nz = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone)
                local pt = type(pts) == "table" and pts[1]
                if nz then
                    lieu = (type(pt) == "table" and pt[1] and pt[1] > 0)
                        and string.format("%s %d, %d", nz, math.floor(pt[1] + 0.5), math.floor(pt[2] + 0.5)) or nz
                    break
                end
            end
            return lieu and (nom .. " (" .. lieu .. ")") or nom
        end
    end
    for _, ob in ipairs(type(debut[2]) == "table" and debut[2] or {}) do
        local nom = Lire("ObjectDB", ob, "name")
        if nom then return nom end
    end
    for _, it in ipairs(type(debut[3]) == "table" and debut[3] or {}) do
        local nom = Lire("ItemDB", it, "name")
        if nom then return nom end
    end
    return nil
end

function Q.LibelleEtat(e)
    if e.etat == "faite" then return T("Faite", "Done") end
    if e.etat == "cours" then return T("En cours", "In progress") end
    if e.etat == "prendre" then return T("À prendre", "Available") end
    if e.etat == "niveau" then return string.format(T("Niveau %d", "Level %d"), e.requis or 0) end
    return T("Après l'étape d'avant", "After the previous step")
end

-- Resume : chaines finies sur le total, et les chaines a faire maintenant.
function Q.Resume(p, connecte)
    local chaines = Q.Chaines(p, connecte)
    local r = { finies = 0, total = #chaines, maintenant = {}, chaines = chaines }
    for _, c in ipairs(chaines) do
        if c.etat == "faite" then r.finies = r.finies + 1
        elseif c.etat == "cours" or c.etat == "prendre" then table.insert(r.maintenant, c) end
    end
    return r
end

-- Au fil du jeu : la fiche du personnage reste a jour.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:SetScript("OnEvent", function(_, ev, id)
        if ev == "PLAYER_LOGIN" then
            Q.QuandPret(function() pcall(Q.Moi) end)
            if C_Timer and C_Timer.After then C_Timer.After(5, Q.Indexer) else Q.Indexer() end
            return
        end
        local moi = Q.Moi()
        if ev == "QUEST_TURNED_IN" and moi and index and index[tonumber(id) or 0] then moi.faites[tonumber(id)] = true end
        if NS.fenetre and NS.fenetre.Actualiser then pcall(NS.fenetre.Actualiser) end
    end)
end
