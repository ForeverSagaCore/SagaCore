local _, NS = ...

-- Donjons : la liste des donjons (et raids) de la base QuestieDB, avec leur
-- entree, les niveaux de leurs quetes, et pour un personnage les quetes qui
-- lui restent : ou les prendre, et ce qui les debloque. Rien sur le butin :
-- seulement les quetes.

NS.donjons = {}
local donjons = NS.donjons

-- Pas des donjons a quetes : tram, salles de champions, champs de bataille.
local EXCLUS = { [2257] = true, [2917] = true, [2918] = true, [2597] = true, [3277] = true, [3358] = true }
local RAIDS = { [1977] = true, [2159] = true, [2677] = true, [2717] = true, [3428] = true, [3429] = true,
    [3456] = true, [3457] = true, [3606] = true, [3607] = true }

local function Lire(...) return NS.ref.Lire(...) end

-- La table des donjons de QuestieDB : { [zone] = { nom, autresZones, zoneParente, entrees } }.
local function TableDeLaBase()
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local brut = support and support.private and support.private.dungeons
    if type(brut) == "string" then
        local fn = loadstring(brut)
        local ok, t = false, nil
        if fn then ok, t = pcall(fn) end
        brut = ok and t or nil
    end
    return type(brut) == "table" and brut or nil
end

-- Index (une fois) : chaque donjon et toutes ses quetes, avec ses niveaux.
local index
local function Index()
    if index then return index end
    local base = TableDeLaBase()
    local liste, parZone = {}, {}
    for zone, d in pairs(base or {}) do
        if not EXCLUS[zone] and type(d) == "table" then
            local entrees = {}
            for _, e in ipairs(type(d[4]) == "table" and d[4] or {}) do
                if type(e) == "table" then
                    local carte = NS.carte and NS.carte.CarteDeZone and NS.carte.CarteDeZone(e[1])
                    if carte and tonumber(e[2]) and tonumber(e[3]) then
                        table.insert(entrees, { carte = carte, x = e[2] / 100, y = e[3] / 100 })
                    end
                end
            end
            local nomJeu = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone)
            local entree = { zone = zone, nomBase = d[1], nom = (type(nomJeu) == "string" and nomJeu ~= "") and nomJeu or d[1],
                raid = RAIDS[zone] == true, entrees = entrees, ids = {}, niveaux = {} }
            table.insert(liste, entree)
            parZone[zone] = entree
            for _, autre in ipairs(type(d[2]) == "table" and d[2] or {}) do parZone[autre] = entree end
        end
    end
    local base = NS.ref.Base("QuestDB")
    local ids = base and base.GetAllIds and base.GetAllIds() or {}
    for _, id in ipairs(ids) do
        local zone = tonumber(Lire("QuestDB", id, "zoneOrSort"))
        local d = zone and parZone[zone]
        if d then
            table.insert(d.ids, id)
            local niveau = tonumber(Lire("QuestDB", id, "questLevel"))
            if niveau and niveau > 0 then table.insert(d.niveaux, niveau) end
        end
    end
    -- Niveaux du donjon : du 15e au 85e centile de ses quetes.
    local gardes = {}
    for _, d in ipairs(liste) do
        if #d.ids > 0 then
            table.sort(d.niveaux)
            local n = #d.niveaux
            if n > 0 then
                d.mini = d.niveaux[math.max(1, math.floor(n * 0.15 + 0.5))]
                d.maxi = d.niveaux[math.max(1, math.floor(n * 0.85 + 0.5))]
            end
            d.niveaux = nil
            table.insert(gardes, d)
        end
    end
    table.sort(gardes, function(a, b)
        if a.raid ~= b.raid then return not a.raid end
        if (a.mini or 0) ~= (b.mini or 0) then return (a.mini or 0) < (b.mini or 0) end
        return tostring(a.nom) < tostring(b.nom)
    end)
    -- Base de Questie pas encore prete : rien n'est garde, on relira.
    if #ids > 0 then index = gardes end
    return gardes
end

function donjons.Disponible() return TableDeLaBase() ~= nil end

-- Pour un personnage : chaque donjon, ses quetes admises (race, classe,
-- faction), celles qui restent (par niveau) et le compte des faites.
function donjons.Liste(p)
    local rendu = {}
    if not p then return rendu end
    local avecRetirees = NS.histoire and NS.histoire.AvecRetirees and NS.histoire.AvecRetirees()
    for _, d in ipairs(Index()) do
        local restantes, faites, total, faitesIds = {}, 0, 0, {}
        for _, id in ipairs(d.ids) do
            local admise = not NS.histoire or NS.histoire.Admise(p, id)
            local faite = p.faites and p.faites[id]
            local retiree = NS.histoire and NS.histoire.Retiree and NS.histoire.Retiree(id)
            if admise and (faite or avecRetirees or not retiree) then
                total = total + 1
                if faite then faites = faites + 1 table.insert(faitesIds, id) else table.insert(restantes, id) end
            end
        end
        if total > 0 then
            table.sort(restantes, function(a, b)
                local na = tonumber(Lire("QuestDB", a, "questLevel")) or 0
                local nb = tonumber(Lire("QuestDB", b, "questLevel")) or 0
                if na ~= nb then return na < nb end
                return a < b
            end)
            table.insert(rendu, { zone = d.zone, nom = d.nom, nomBase = d.nomBase, ids = d.ids, raid = d.raid, mini = d.mini, maxi = d.maxi,
                entrees = d.entrees, restantes = restantes, faites = faites, faitesIds = faitesIds, total = total })
        end
    end
    return rendu
end

-- Ce qui manque pour prendre une quete : les quetes prealables pas encore faites.
function donjons.PrealablesManquants(p, id)
    local groupe, une = NS.ref.Prerequis(id)
    local manque = {}
    for _, pre in ipairs(groupe) do
        if not (p.faites and p.faites[pre]) then table.insert(manque, pre) end
    end
    if #une > 0 then
        local unFait = false
        for _, pre in ipairs(une) do if p.faites and p.faites[pre] then unFait = true break end end
        if not unFait then table.insert(manque, une[1]) end
    end
    return manque
end

-- Le journal de donjons (add-on DungeonJournal, s'il est installe) : son nom
-- pour ce donjon, trouve par les quetes en commun, sinon par le nom anglais.
local journal = {}
function donjons.NomDansLeJournal(d)
    local FDJ = _G.ForeverDungeonJournal_NS
    local base = FDJ and FDJ.DB
    if type(base) ~= "table" or not d then return nil end
    if journal[d.zone] ~= nil then return journal[d.zone] or nil end
    local miens = {}
    for _, id in ipairs(d.ids or {}) do miens[id] = true end
    local meilleur, score = nil, 0
    for nom, info in pairs(base) do
        local n = 0
        for _, q in ipairs(type(info) == "table" and type(info.quests) == "table" and info.quests or {}) do
            if type(q) == "table" and miens[q.id] then n = n + 1 end
        end
        if n > score then meilleur, score = nom, n end
    end
    if not meilleur and d.nomBase and base[d.nomBase] then meilleur = d.nomBase end
    journal[d.zone] = meilleur or false
    return meilleur
end

-- Ouvre le journal sur ce donjon : ses boss et leur butin, ou son plan.
function donjons.OuvrirJournal(d, plan)
    local FDJ = _G.ForeverDungeonJournal_NS
    local nom = donjons.NomDansLeJournal(d)
    if not (FDJ and nom) then return false end
    -- Le journal se construit a sa premiere ouverture : on l'ouvre, puis on
    -- choisit la page un instant apres.
    local cadre = _G.ForeverDungeonJournalFrame
    if not (cadre and cadre:IsShown()) and _G.ForeverDungeonJournal_Toggle then
        pcall(_G.ForeverDungeonJournal_Toggle)
    end
    -- Le journal passe devant notre fenetre, qui reste ouverte, estompee
    -- derriere ; a la fermeture du journal, tout revient comme avant.
    local nous = NS.fenetre and NS.fenetre.Cadre and NS.fenetre.Cadre()
    local function Choisir()
        if plan and FDJ.OpenDungeonMap then pcall(FDJ.OpenDungeonMap, nom)
        elseif FDJ.OpenBossPage then pcall(FDJ.OpenBossPage, nom, 1) end
        local f = _G.ForeverDungeonJournalFrame
        if not f then return end
        if nous and nous:IsShown() then
            -- Le journal garde sa strate d'origine ; c'est notre fenetre qui
            -- passe juste en dessous, estompee, le temps qu'il reste ouvert.
            if not nous.questCoreStrate then nous.questCoreStrate = nous:GetFrameStrata() end
            pcall(nous.SetFrameStrata, nous, "HIGH")
            nous:SetAlpha(0.35)
            if not f.questCoreRendu then
                f.questCoreRendu = true
                f:HookScript("OnHide", function()
                    local n = NS.fenetre and NS.fenetre.Cadre and NS.fenetre.Cadre()
                    if n then
                        n:SetAlpha(1)
                        if n.questCoreStrate then pcall(n.SetFrameStrata, n, n.questCoreStrate) end
                    end
                end)
            end
        end
        if f.Raise then pcall(f.Raise, f) end
    end
    local apres = _G.C_Timer and _G.C_Timer.After
    if apres then apres(0.2, Choisir) else Choisir() end
    return true
end

-- Ou prendre une quete : le premier PNJ qui la donne, sa carte et sa place.
-- Ou se prend une quete : son PNJ, ou l'objet qui la donne (un panneau, un
-- mur...). Le premier emplacement qui tombe sur une carte du jeu.
function donjons.LieuDuDonneur(id)
    local debut = NS.ref.Lire("QuestDB", id, "startedBy")
    if type(debut) ~= "table" then return nil end
    for _, source in ipairs({ { 1, "NpcDB" }, { 2, "ObjectDB" } }) do
        for _, ent in ipairs(type(debut[source[1]]) == "table" and debut[source[1]] or {}) do
            local nom = NS.ref.Lire(source[2], ent, "name")
            local spawns = NS.ref.Lire(source[2], ent, "spawns")
            for zone, liste in pairs(type(spawns) == "table" and spawns or {}) do
                local carte = NS.carte and NS.carte.CarteDeZone and NS.carte.CarteDeZone(zone)
                local p = type(liste) == "table" and liste[1]
                if carte and type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 then
                    return { carte = carte, x = p[1] / 100, y = p[2] / 100, nom = nom }
                end
            end
        end
    end
    return nil
end
