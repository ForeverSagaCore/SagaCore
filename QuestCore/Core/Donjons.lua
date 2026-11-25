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

-- Niveaux conseilles des donjons : ceux du Journal des donjons de Forever
-- (ForeverDungeonJournal), la reference du serveur. Lus en direct dans le
-- journal quand il est installe (il reste ainsi a jour), sinon cette copie,
-- par zone de la base QuestieDB. Les ailes (Monastere, Hache-tripes,
-- Stratholme, Rochenoire) sont reunies : du plus bas au plus haut.
local NIVEAUX_REFERENCE = {
    [2437] = { 13, 18 }, [718] = { 15, 24 }, [1581] = { 17, 26 }, [209] = { 20, 30 },
    [719] = { 24, 32 }, [717] = { 24, 32 }, [721] = { 29, 38 }, [491] = { 29, 38 },
    [796] = { 30, 46 }, [722] = { 37, 46 }, [1337] = { 41, 51 }, [1176] = { 44, 54 },
    [2100] = { 46, 55 }, [1477] = { 50, 60 }, [1584] = { 52, 60 }, [1583] = { 55, 60 },
    [7307] = { 59, 60 }, [2557] = { 54, 60 }, [2057] = { 58, 60 }, [6066] = { 58, 60 },
    [2017] = { 58, 60 }, [10001] = { 58, 60 },
    [10022] = { 54, 60 }, [10023] = { 54, 60 }, [10024] = { 54, 60 }, [10025] = { 54, 60 },
    [10026] = { 54, 60 }, [10027] = { 54, 60 },
    -- Donjons propres a Forever.
    [16919] = { 13, 20 }, [16611] = { 15, 22 }, [16732] = { 26, 33 }, [16544] = { 28, 35 },
}
-- Meme donjon, autre nom selon la source.
local ALIAS = { ["sunken temple"] = "temple of atal'hakkar", ["upper blackrock spire"] = "blackrock spire",
    ["lower blackrock spire"] = "blackrock spire" }
local function Cle(nom)
    nom = string.lower(tostring(nom or ""))
    nom = string.gsub(nom, "^the ", "")
    nom = string.match(nom, "^([^:]+)") or nom          -- "scarlet monastery: library" -> l'ensemble
    nom = string.gsub(nom, "%s+$", "")
    return ALIAS[nom] or nom
end
-- Les niveaux du journal en direct : { [cle] = { mini, maxi } }, ou nil.
local function NiveauxDuJournal()
    local fdj = _G.FDJ or _G.ForeverDungeonJournal_NS
    local db = type(fdj) == "table" and fdj.DB
    if type(db) ~= "table" then return nil end
    local t = {}
    for nom, d in pairs(db) do
        local mini, maxi = string.match(type(d) == "table" and tostring(d.level or "") or "", "(%d+)%s*%-%s*(%d+)")
        mini, maxi = tonumber(mini), tonumber(maxi)
        if mini and maxi then
            local c = Cle(nom)
            local e = t[c]
            if e then e[1] = math.min(e[1], mini) e[2] = math.max(e[2], maxi) else t[c] = { mini, maxi } end
        end
    end
    return t
end

-- Index (une fois) : chaque donjon et toutes ses quetes, avec ses niveaux.
local index
local queteVersDonjon = {}
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
            queteVersDonjon[id] = d
            local niveau = tonumber(Lire("QuestDB", id, "questLevel"))
            if niveau and niveau > 0 then table.insert(d.niveaux, niveau) end
        end
    end
    -- Niveaux du donjon : ceux du Journal des donjons (en direct, sinon sa
    -- copie) ; a defaut seulement, ceux de ses quetes (15e au 85e centile).
    local journal = NiveauxDuJournal()
    local gardes = {}
    for _, d in ipairs(liste) do
        if #d.ids > 0 then
            local ref = (journal and journal[Cle(d.nomBase)]) or NIVEAUX_REFERENCE[d.zone]
            if ref then
                d.mini, d.maxi = ref[1], ref[2]
            else
                table.sort(d.niveaux)
                local n = #d.niveaux
                if n > 0 then
                    d.mini = d.niveaux[math.max(1, math.floor(n * 0.15 + 0.5))]
                    d.maxi = d.niveaux[math.max(1, math.floor(n * 0.85 + 0.5))]
                end
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

-- Le donjon d'une quete (une quete qui se fait dans l'instance), ou nil.
function donjons.DeQuete(id)
    Index()
    return queteVersDonjon[id]
end

-- Quete qui se prend dans le donjon : un objet ramasse qui la donne, ou
-- un donneur qu'on ne trouve que dans l'instance.
-- Garde la reponse (donnees fixes de la base) : appelee a chaque calcul du
-- guidage d'un trajet de donjon.
local dedansConnu = {}
function donjons.SePrendDedans(id)
    if dedansConnu[id] ~= nil then return dedansConnu[id] end
    local debut = Lire("QuestDB", id, "startedBy")
    if type(debut) ~= "table" then return false end
    if type(debut[3]) == "table" and #debut[3] > 0 then dedansConnu[id] = true return true end
    local dehors, dedans = false, false
    for _, source in ipairs({ { 1, "NpcDB" }, { 2, "ObjectDB" } }) do
        for _, ent in ipairs(type(debut[source[1]]) == "table" and debut[source[1]] or {}) do
            for zone in pairs(type(Lire(source[2], ent, "spawns")) == "table" and Lire(source[2], ent, "spawns") or {}) do
                local c = NS.carte and NS.carte.CarteDeZone and NS.carte.CarteDeZone(zone)
                if c and NS.carte.EstInstance and NS.carte.EstInstance(c) then dedans = true elseif c then dehors = true end
            end
        end
    end
    -- Rien trouve (cartes pas encore connues) : pas garde, on relira.
    if dedans or dehors then dedansConnu[id] = dedans and not dehors end
    return dedans and not dehors
end

-- Pour un personnage, un donjon de l'index : ses quetes admises (race,
-- classe, faction), celles qui restent (par niveau) et le compte des faites.
-- nil s'il n'a aucune quete pour lui.
local function PourLePerso(p, d, avecRetirees)
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
    if total == 0 then return nil end
    table.sort(restantes, function(a, b)
        local na = tonumber(Lire("QuestDB", a, "questLevel")) or 0
        local nb = tonumber(Lire("QuestDB", b, "questLevel")) or 0
        if na ~= nb then return na < nb end
        return a < b
    end)
    return { zone = d.zone, nom = d.nom, nomBase = d.nomBase, ids = d.ids, raid = d.raid, mini = d.mini, maxi = d.maxi,
        entrees = d.entrees, restantes = restantes, faites = faites, faitesIds = faitesIds, total = total }
end

local function AvecRetirees() return NS.histoire and NS.histoire.AvecRetirees and NS.histoire.AvecRetirees() end

-- Pour un personnage : chaque donjon, ses quetes admises (race, classe,
-- faction), celles qui restent (par niveau) et le compte des faites.
function donjons.Liste(p)
    local rendu = {}
    if not p then return rendu end
    local avecRetirees = AvecRetirees()
    for _, d in ipairs(Index()) do
        local r = PourLePerso(p, d, avecRetirees)
        if r then table.insert(rendu, r) end
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

-- ---------------------------------------------------------------------------
-- Preparation d'un donjon : le meme modele pour la fenetre, le trajet et le
-- guidage, pour tous les donjons et toutes les quetes.
--   suites   : les suites de quetes prerequis qui se font avant le donjon
--              (hors instance, ou qu'elles se trouvent), chaque suite dans
--              son ordre : c'est le plus long, donc en premier ;
--   avant    : les quetes du donjon a prendre avant d'y aller (donneur
--              dehors), faisables des maintenant ou au bout de leur suite ;
--   dedans   : les quetes qui se prennent dans l'instance : seulement
--              indiquees, jamais guidees avant ;
--   plusTard : ce qui ne se fera pas cette fois : un niveau plus haut (la
--              quete ou un maillon de sa suite), ou une quete qui attend une
--              autre quete de donjon (elle se fait dedans, on la rendra
--              d'abord) ;
--   trajet   : les quetes du trajet, dans l'ordre : suites, avant, puis
--              celles de "dedans" deja dans le journal ;
--   kit      : suites + avant + dedans (compatibilite) ;
--   enPoche  : les quetes de "avant" deja dans le journal.
-- Chaque entree : { id, etat } (etat de parcours.EtatEtape) ; une suite
-- porte aussi `pour` (la quete du donjon qu'elle debloque), une quete de
-- "plus tard" `niveau` (le niveau a atteindre, s'il manque).
-- ---------------------------------------------------------------------------

local function Requis(id) return tonumber(Lire("QuestDB", id, "requiredLevel")) or 0 end

function donjons.Preparation(p, d)
    local P = NS.parcours
    local res = { suites = {}, avant = {}, dedans = {}, plusTard = {}, kit = {}, trajet = {}, enPoche = 0 }
    if not (p and d) then return res end
    local dansSuites = {}
    for _, id in ipairs(d.restantes or {}) do
        local e = P.EtatEtape(p, id)
        if e ~= "faite" then
            local chemin = P.CheminVers(p, id)
            -- Un maillon qui est lui-meme une quete de donjon (pas encore a
            -- rendre) se fait dans une instance : la quete attendra.
            local attendDonjon = false
            for _, q in ipairs(chemin or {}) do
                if q ~= id and donjons.DeQuete(q) and P.EtatEtape(p, q) ~= "rendre" then attendDonjon = true break end
            end
            if not chemin or attendDonjon then
                -- Le niveau a atteindre : le plus haut de la quete et de sa suite.
                local niveau = 0
                for _, q in ipairs(P.CheminVers(p, id, true) or { id }) do
                    if not (p.quetes and p.quetes[q]) then niveau = math.max(niveau, Requis(q)) end
                end
                table.insert(res.plusTard, { id = id, etat = e,
                    niveau = (p.niveau and niveau > p.niveau) and niveau or nil })
            else
                for _, q in ipairs(chemin) do
                    if q ~= id and not dansSuites[q] then
                        dansSuites[q] = true
                        table.insert(res.suites, { id = q, etat = P.EtatEtape(p, q), pour = id })
                    end
                end
                local entree = { id = id, etat = e }
                if donjons.SePrendDedans(id) then
                    table.insert(res.dedans, entree)
                else
                    table.insert(res.avant, entree)
                    if e == "cours" or e == "rendre" then res.enPoche = res.enPoche + 1 end
                end
            end
        end
    end
    for _, q in ipairs(res.suites) do table.insert(res.trajet, q.id) table.insert(res.kit, q) end
    for _, q in ipairs(res.avant) do table.insert(res.trajet, q.id) table.insert(res.kit, q) end
    for _, q in ipairs(res.dedans) do
        if q.etat == "cours" or q.etat == "rendre" then table.insert(res.trajet, q.id) end
        table.insert(res.kit, q)
    end
    return res
end

-- Ce que guide le trajet du donjon maintenant, dans l'ordre des rubriques :
--   1. "suites"  : les maillons faisables des suites (a prendre, a faire, a
--                  rendre ; la suivante vient quand la precedente est rendue) ;
--   2. "avant"   : les quetes du donjon a prendre dehors (et celles deja
--                  terminees, a rendre) ;
--   3. "donjon"  : tout est pris : les quetes du donjon dans le journal (leurs
--                  objectifs hors de l'instance, sinon l'entree du donjon).
-- Jamais un donneur pour une quete deja prise, jamais une etape faite ni une
-- etape retiree a la main (pc.ignorees). Rend ids, phase ; {} si rien.
function donjons.AGuider(p, d, pc)
    local prep = donjons.Preparation(p, d)
    local ignorees = pc and pc.ignorees or {}
    local function Garder(listes, etats)
        local ids = {}
        for _, liste in ipairs(listes) do
            for _, q in ipairs(liste) do
                if etats[q.etat] and not ignorees[q.id] then table.insert(ids, q.id) end
            end
        end
        return ids
    end
    local ids = Garder({ prep.suites }, { prendre = true, cours = true, rendre = true })
    if #ids > 0 then return ids, "suites", prep end
    ids = Garder({ prep.avant, prep.dedans }, { rendre = true })
    for _, id in ipairs(Garder({ prep.avant }, { prendre = true })) do table.insert(ids, id) end
    if #ids > 0 then return ids, "avant", prep end
    ids = Garder({ prep.avant, prep.dedans }, { cours = true })
    if #ids > 0 then return ids, "donjon", prep end
    return {}, nil, prep
end

-- Le trajet deja cree pour ce donjon suit tout seul : ses etapes sont
-- refaites dans l'ordre des rubriques (suites, avant, dedans), ce qui s'est
-- debloque depuis y entre a sa place. Les etapes faites restent en tete
-- (l'avancement les compte) et ne reviennent jamais ; une etape retiree a la
-- main n'y revient pas.
function donjons.MettreAJourKit(p, d, pc)
    -- Sans la liste des quetes du donjon (base pas encore lue), rien ne bouge.
    if not (p and d and type(d.restantes) == "table") then return end
    local nomKit = string.format(NS.L.DUNGEON_KIT_NAME, d.nom)
    local prep
    for _, x in ipairs(pc and { pc } or NS.parcours.Liste(p.cle)) do
        if x.genre == "kit" and type(x.etapes) == "table" and (pc or x.donjon == d.zone or x.nom == nomKit) then
            prep = prep or donjons.Preparation(p, d)
            local ignorees = x.ignorees or {}
            local etapes, deja = {}, {}
            for _, id in ipairs(x.etapes) do
                if not deja[id] and NS.parcours.EtatEtape(p, id) == "faite" then
                    table.insert(etapes, id)
                    deja[id] = true
                end
            end
            -- Ce qui a deja ete fait pour ce donjon (maillons des suites, quetes
            -- rendues) reste visible, meme dans un trajet recree.
            local vus = {}
            local function Faites(id, prof)
                prof = prof or 0
                if not id or vus[id] or prof > 25 then return end
                vus[id] = true
                -- Les prealables d'abord, faits ou non : toute la suite.
                local groupe, une = NS.ref.Prerequis(id)
                for _, pre in ipairs(groupe or {}) do Faites(pre, prof + 1) end
                for _, pre in ipairs(une or {}) do
                    if NS.parcours.EtatEtape(p, pre) == "faite" then Faites(pre, prof + 1) break end
                end
                if not deja[id] and not ignorees[id] and NS.parcours.EtatEtape(p, id) == "faite" then
                    table.insert(etapes, id)
                    deja[id] = true
                end
            end
            for _, id in ipairs(prep.trajet) do Faites(id) end
            for _, id in ipairs(d.faitesIds or {}) do Faites(id) end
            for _, id in ipairs(prep.trajet) do
                if not deja[id] and not ignorees[id] then
                    table.insert(etapes, id)
                    deja[id] = true
                end
            end
            -- Sur place : la table des etapes peut etre tenue ailleurs.
            for i = #x.etapes, 1, -1 do x.etapes[i] = nil end
            for i, id in ipairs(etapes) do x.etapes[i] = id end
            x.donjon = x.donjon or d.zone
        end
    end
end

-- Le donjon d'un trajet (kit), pour le personnage : celui qu'il a retenu a
-- sa creation, sinon (anciens trajets) celui de la plupart de ses etapes.
function donjons.DuKit(p, pc)
    if not (p and pc and pc.genre == "kit") then return nil end
    Index()
    local zone = pc.donjon
    if not zone then
        local compte, meilleur = {}, 0
        for _, id in ipairs(pc.etapes or {}) do
            local d = queteVersDonjon[id]
            if d then
                compte[d.zone] = (compte[d.zone] or 0) + 1
                if compte[d.zone] > meilleur then meilleur, zone = compte[d.zone], d.zone end
            end
        end
        if not zone then return nil end
        pc.donjon = zone
    end
    for _, d in ipairs(Index()) do
        if d.zone == zone then return PourLePerso(p, d, AvecRetirees()) end
    end
    return nil
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
