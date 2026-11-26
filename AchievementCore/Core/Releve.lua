local _, NS = ...

-- Releves du personnage connecte, lus dans le jeu : identite, zones
-- explorees, instances, boss, reputations, JcJ, objets eus. Les quetes, les
-- metiers et les recettes ne sont releves ici que si QuestCore ou CraftCore
-- manquent (sinon ce sont les leurs). Chaque releve est court, sous filet,
-- et ne fait monter la version de sa categorie que s'il a change quelque chose.

NS.releve = {}
local releve = NS.releve
local Jeu = NS.Jeu

local function Fiche()
    local cle = NS.ClePersonnage()
    return cle and NS.base.Fiche(cle) or nil
end

-- ---------------------------------------------------------------------------
-- Identite
-- ---------------------------------------------------------------------------

function releve.Identite()
    local f = Fiche()
    if not f then return end
    local avant = tostring(f.niveau) .. tostring(f.race) .. tostring(f.classe) .. tostring(f.faction)
    local _, classe = Jeu("UnitClass", "player")
    local _, raceJeton, race = Jeu("UnitRace", "player")
    f.nom = NS.NomCourt(f.cle)
    f.classe = type(classe) == "string" and classe or f.classe
    f.race = tonumber(race) or f.race
    f.raceJeton = type(raceJeton) == "string" and raceJeton or f.raceJeton
    local faction = Jeu("UnitFactionGroup", "player")
    if faction == "Alliance" or faction == "Horde" then f.faction = faction end
    f.niveau = tonumber(Jeu("UnitLevel", "player")) or f.niveau
    f.sexe = tonumber(Jeu("UnitSex", "player")) or f.sexe
    f.vu = NS.Appeler(time)
    if avant ~= tostring(f.niveau) .. tostring(f.race) .. tostring(f.classe) .. tostring(f.faction) then
        NS.Changer("persos", "races")
    end
end

-- ---------------------------------------------------------------------------
-- Exploration : les morceaux de carte decouverts de chaque zone
-- ---------------------------------------------------------------------------

local function CleMorceau(info)
    return string.format("%d:%d:%d:%d", tonumber(info.textureWidth) or 0, tonumber(info.textureHeight) or 0,
        tonumber(info.offsetX) or 0, tonumber(info.offsetY) or 0)
end

-- Nom d'un morceau explore : la zone du jeu a son centre, gardee pour le compte.
local function NommerMorceau(carte, art, cle, info)
    local d = NS.base.DB()
    d.lieux[art] = type(d.lieux[art]) == "table" and d.lieux[art] or {}
    if d.lieux[art][cle] then return end
    local creer = _G.CreateVector2D
    local lire = NS.Lecture("C_MapExplorationInfo.GetExploredAreaIDsAtPosition")
    if not (creer and lire) then return end
    local l, h = NS.base.TailleCarte(carte)
    local ox, oy = tonumber(info.offsetX) or 0, tonumber(info.offsetY) or 0
    local tl, th = tonumber(info.textureWidth) or 0, tonumber(info.textureHeight) or 0
    -- Le centre d'abord, puis quatre points autour (un morceau n'est pas
    -- un rectangle plein : son centre peut tomber a cote).
    for _, p in ipairs({ { 0.5, 0.5 }, { 0.3, 0.3 }, { 0.7, 0.3 }, { 0.3, 0.7 }, { 0.7, 0.7 } }) do
        local okV, pos = pcall(creer, (ox + tl * p[1]) / l, (oy + th * p[2]) / h)
        if okV then
            local ok, ids = pcall(lire, carte, pos)
            local zone = ok and type(ids) == "table" and tonumber(NS.Sur(ids[1]))
            if zone then d.lieux[art][cle] = zone return end
        end
    end
end

function releve.ExplorerCarte(carte)
    local f = Fiche()
    carte = tonumber(carte)
    if not f or not carte then return false end
    local infos = Jeu("C_MapExplorationInfo.GetExploredMapTextures", carte)
    if type(infos) ~= "table" then return false end
    local explore = NS.base.Table(f, "explore")
    local t = type(explore[carte]) == "table" and explore[carte] or {}
    local art = tonumber(Jeu("C_Map.GetMapArtID", carte))
    local change = false
    for _, info in ipairs(infos) do
        if type(info) == "table" then
            local cle = CleMorceau(info)
            if not t[cle] then t[cle] = true change = true end
            if art then pcall(NommerMorceau, carte, art, cle, info) end
        end
    end
    if next(t) then explore[carte] = t end
    return change
end

-- Toutes les zones des continents (une quarantaine de lectures).
function releve.Exploration()
    local change = false
    for _, z in ipairs(NS.base.Zones()) do
        if releve.ExplorerCarte(z.carte) then change = true end
    end
    if change then NS.Changer("exploration") end
end

-- La zone ou l'on est : visitee, et ses morceaux decouverts.
function releve.ZoneActuelle()
    local f = Fiche()
    if not f then return end
    local carte = tonumber(Jeu("C_Map.GetBestMapForUnit", "player"))
    local change = false
    if carte then
        -- La zone elle-meme (pas un sous-niveau de ville ou de grotte).
        local garde, c = 0, carte
        while c and garde < 6 do
            local info = Jeu("C_Map.GetMapInfo", c)
            if type(info) ~= "table" then break end
            if info.mapType == 3 or info.mapType == 4 then
                local visites = NS.base.Table(f, "visites")
                if not visites[c] then visites[c] = true change = true end
                if releve.ExplorerCarte(c) then change = true end
                break
            end
            c = info.parentMapID
            garde = garde + 1
        end
    end
    if change then NS.Changer("exploration") end
    releve.Instance()
end

-- ---------------------------------------------------------------------------
-- Instances et boss
-- ---------------------------------------------------------------------------

-- Dans une instance : laquelle (zone de la base), notee comme visitee.
function releve.Instance()
    local f = Fiche()
    if not f then return nil end
    local dedans, genre = Jeu("IsInInstance")
    if not dedans or (genre ~= "party" and genre ~= "raid") then releve.instance = nil return nil end
    local nom, _, _, _, _, _, _, idInstance = Jeu("GetInstanceInfo")
    local d = NS.base.DonjonDeInstance(nom, idInstance)
    releve.instance = d and d.zone or nil
    if d then
        local instances = NS.base.Table(f, "instances")
        if not instances[d.zone] then
            instances[d.zone] = true
            NS.Changer("donjons")
        end
    end
    return releve.instance
end

-- Une rencontre gagnee : le boss, pour ce personnage et pour le compte.
function releve.Rencontre(idRencontre, nom, reussi)
    if reussi ~= 1 and reussi ~= true then return end
    local f = Fiche()
    if not f then return end
    local zone = releve.instance or releve.Instance()
    if not zone then return end
    local cleBoss = NS.base.CleBoss(zone, idRencontre, nom)
    if not cleBoss then return end
    local d = NS.base.DB()
    d.rencontres[zone] = type(d.rencontres[zone]) == "table" and d.rencontres[zone] or {}
    if not d.rencontres[zone][cleBoss] then d.rencontres[zone][cleBoss] = type(nom) == "string" and nom or tostring(cleBoss) end
    local boss = NS.base.Table(f, "boss")
    boss[zone] = type(boss[zone]) == "table" and boss[zone] or {}
    if not boss[zone][cleBoss] then
        boss[zone][cleBoss] = true
        NS.Changer("donjons")
    end
end

-- ---------------------------------------------------------------------------
-- Objets eus : sacs, banque, equipement
-- ---------------------------------------------------------------------------

local function NoterObjet(objets, id)
    id = tonumber(NS.Sur(id))
    if id and id > 0 and not objets[id] then objets[id] = true return true end
    return false
end

local function LireSacs(liste)
    local f = Fiche()
    if not f then return false end
    local objets = NS.base.Table(f, "objets")
    local change = false
    for _, sac in ipairs(liste) do
        local n = tonumber(Jeu("C_Container.GetContainerNumSlots", sac)) or tonumber(Jeu("GetContainerNumSlots", sac)) or 0
        for emplacement = 1, n do
            local id = Jeu("C_Container.GetContainerItemID", sac, emplacement) or Jeu("GetContainerItemID", sac, emplacement)
            if NoterObjet(objets, id) then change = true end
        end
    end
    return change
end

function releve.Sacs()
    local liste = {}
    for sac = 0, tonumber(_G.NUM_BAG_SLOTS) or 4 do table.insert(liste, sac) end
    if LireSacs(liste) then NS.Changer("objets") end
end

function releve.Banque()
    local liste = { -1 }
    local premier = (tonumber(_G.NUM_BAG_SLOTS) or 4) + 1
    for sac = premier, premier + (tonumber(_G.NUM_BANKBAGSLOTS) or 6) - 1 do table.insert(liste, sac) end
    if LireSacs(liste) then NS.Changer("objets") end
end

function releve.Equipement()
    local f = Fiche()
    if not f then return end
    local objets = NS.base.Table(f, "objets")
    local change = false
    for emplacement = 1, 19 do
        if NoterObjet(objets, Jeu("GetInventoryItemID", "player", emplacement)) then change = true end
    end
    if change then NS.Changer("objets") end
end

-- ---------------------------------------------------------------------------
-- Quetes (sans QuestCore)
-- ---------------------------------------------------------------------------

function releve.QuetesAPrendre()
    return not NS.AddOnCharge("QuestCore")
end

function releve.Quetes()
    if not releve.QuetesAPrendre() then return end
    local f = Fiche()
    if not f then return end
    local quetes = NS.base.Table(f, "quetes")
    local change = false
    local liste = Jeu("C_QuestLog.GetAllCompletedQuestIDs")
    if type(liste) == "table" then
        for _, id in ipairs(liste) do
            id = tonumber(id)
            if id and not quetes[id] then quetes[id] = true change = true end
        end
    else
        local t = Jeu("GetQuestsCompleted")
        for id, oui in pairs(type(t) == "table" and t or {}) do
            id = tonumber(id)
            if oui and id and not quetes[id] then quetes[id] = true change = true end
        end
    end
    if change then NS.Changer("quetes", "donjons") end
end

function releve.QueteRendue(id)
    id = tonumber(NS.Sur(id))
    if not id then return end
    if releve.QuetesAPrendre() then
        local f = Fiche()
        if f then NS.base.Table(f, "quetes")[id] = true end
    end
    NS.Changer("quetes", "donjons")
end

-- ---------------------------------------------------------------------------
-- Metiers et recettes (sans CraftCore)
-- ---------------------------------------------------------------------------

function releve.MetiersAPrendre()
    return not NS.AddOnCharge("CraftCore")
end

function releve.NiveauxDesMetiers()
    if not releve.MetiersAPrendre() then return end
    local f = Fiche()
    if not f then return end
    local metiers = NS.base.Table(f, "metiers")
    local change = false
    local function Noter(ligne, nom, rang, rangMax)
        ligne, rang = tonumber(ligne), tonumber(rang)
        if not (ligne and rang) then return end
        local m = type(metiers[ligne]) == "table" and metiers[ligne] or {}
        if m.rang ~= rang then change = true end
        m.rang, m.rangMax = rang, tonumber(rangMax) or m.rangMax
        if type(nom) == "string" and nom ~= "" then m.nom = nom end
        metiers[ligne] = m
    end
    local liste = NS.Lecture("GetProfessions")
    local info = NS.Lecture("GetProfessionInfo")
    if liste and info then
        local r = { pcall(liste) }
        if r[1] then
            for i = 2, 7 do
                local index = NS.Sur(r[i])
                if index then
                    local nom, _, rang, rangMax, _, _, ligne = Jeu("GetProfessionInfo", index)
                    Noter(ligne, nom, rang, rangMax)
                end
            end
        end
    end
    if change then NS.Changer("metiers") end
end

-- La fenetre d'un metier ouverte : toutes ses recettes, apprises ou non.
function releve.Recettes()
    if not releve.MetiersAPrendre() then return end
    local f = Fiche()
    if not f then return end
    local base = Jeu("C_TradeSkillUI.GetBaseProfessionInfo")
    local ligne = type(base) == "table" and (tonumber(base.professionID) or tonumber(base.skillLineID)) or nil
    if not ligne then return end
    local ids = Jeu("C_TradeSkillUI.GetAllRecipeIDs")
    if type(ids) ~= "table" then return end
    local d = NS.base.DB()
    local apprises = NS.base.Table(f, "recettes")
    local change = false
    for _, id in ipairs(ids) do
        local info = Jeu("C_TradeSkillUI.GetRecipeInfo", id)
        if type(info) == "table" then
            if type(d.recettes[id]) ~= "table" then
                d.recettes[id] = { ligne = ligne, nom = info.name }
                change = true
            end
            if info.learned and not apprises[id] then apprises[id] = true change = true end
        end
    end
    if type(base.skillLevel) == "number" then
        local metiers = NS.base.Table(f, "metiers")
        local m = type(metiers[ligne]) == "table" and metiers[ligne] or {}
        if m.rang ~= base.skillLevel then change = true end
        m.rang, m.rangMax = base.skillLevel, tonumber(base.maxSkillLevel) or m.rangMax
        if type(base.professionName) == "string" then m.nom = base.professionName end
        metiers[ligne] = m
    end
    if change then NS.Changer("metiers") end
end

-- ---------------------------------------------------------------------------
-- Reputations : par identifiant, meme quand l'en-tete est replie
-- ---------------------------------------------------------------------------

local function InfoFaction(id)
    local C = _G.C_Reputation
    if C and C.GetFactionDataByID then
        local ok, d = pcall(C.GetFactionDataByID, id)
        if ok and type(d) == "table" and d.name then
            return NS.Sur(d.name), NS.Sur(d.reaction), NS.Sur(d.atWarWith), NS.Sur(d.canToggleAtWar),
                NS.Sur(d.currentReactionThreshold), NS.Sur(d.nextReactionThreshold), NS.Sur(d.currentStanding)
        end
    end
    local nom, _, rang, mini, maxi, valeur, guerre, basculable = Jeu("GetFactionInfoByID", id)
    return nom, rang, guerre, basculable, mini, maxi, valeur
end

-- Les en-tetes visibles de la liste du jeu (pour ranger les factions).
local function LireListe(d)
    local C = _G.C_Reputation
    local n = tonumber((C and C.GetNumFactions and NS.Appeler(C.GetNumFactions)) or Jeu("GetNumFactions")) or 0
    local entete
    for i = 1, math.min(n, 200) do
        local nom, estEntete, id
        if C and C.GetFactionDataByIndex then
            local data = NS.Appeler(C.GetFactionDataByIndex, i)
            if type(data) == "table" then nom, estEntete, id = NS.Sur(data.name), NS.Sur(data.isHeader), NS.Sur(data.factionID) end
        else
            local r = { NS.Appeler(_G.GetFactionInfo, i) }
            nom, estEntete, id = NS.Sur(r[1]), NS.Sur(r[9]), NS.Sur(r[14])
        end
        id = tonumber(id)
        if estEntete then
            entete = nom
        elseif id and nom then
            d.factions[id] = type(d.factions[id]) == "table" and d.factions[id] or {}
            d.factions[id].nom = nom
            if entete then d.factions[id].entete = entete end
        end
    end
end

function releve.Reputations()
    local f = Fiche()
    if not f then return end
    local d = NS.base.DB()
    pcall(LireListe, d)
    local reps = NS.base.Table(f, "reputations")
    -- L'avancement actuel dans le rang : { rang, valeur, mini, maxi }.
    local detail = NS.base.Table(f, "reputationsDetail")
    local change = false
    for id in pairs(NS.base.Factions()) do
        local nom, rang, guerre, basculable, mini, maxi, valeur = InfoFaction(id)
        rang = tonumber(rang)
        if nom and rang and rang > 0 and tonumber(valeur) and tonumber(mini) and tonumber(maxi) then
            local avantD = detail[id]
            local nouveau = { rang, tonumber(valeur), tonumber(mini), tonumber(maxi) }
            if type(avantD) ~= "table" or avantD[1] ~= nouveau[1] or avantD[2] ~= nouveau[2] then change = true end
            detail[id] = nouveau
        end
        if nom and rang and rang > 0 then
            -- Une faction ennemie qu'on ne peut pas monter (capitales de
            -- l'autre camp) ne compte pas pour ce personnage.
            -- Le meilleur rang atteint reste (-1 : fermee).
            local fermee = guerre == true and basculable == false and rang <= 3
            local maintenant = fermee and -1 or rang
            local avant = tonumber(reps[id])
            if not avant or maintenant > avant then reps[id] = maintenant change = true end
            d.factions[id] = type(d.factions[id]) == "table" and d.factions[id] or {}
            d.factions[id].nom = nom
        end
    end
    if change then NS.Changer("reputations") end
end

-- ---------------------------------------------------------------------------
-- JcJ : meilleur rang, victoires dans chaque champ de bataille
-- ---------------------------------------------------------------------------

function releve.JcJ()
    local f = Fiche()
    if not f then return end
    local jcj = NS.base.Table(f, "jcj")
    local change = false
    local _, _, plusHaut = Jeu("GetPVPLifetimeStats")
    local actuel = Jeu("UnitPVPRank", "player")
    for _, r in ipairs({ plusHaut, actuel }) do
        r = tonumber(r)
        if r and r > 0 then
            local _, numero = Jeu("GetPVPRankInfo", r)
            numero = tonumber(numero)
            if numero and numero > (tonumber(jcj.rang) or 0) then jcj.rang = numero change = true end
        end
    end
    if change then NS.Changer("jcj") end
end

-- Fin d'un champ de bataille : une victoire de notre camp y est notee.
function releve.FinDeChamp()
    local gagnant = tonumber(Jeu("GetBattlefieldWinner"))
    if not gagnant then releve.champNote = nil return end
    if releve.champNote then return end
    releve.champNote = true
    local faction = Jeu("UnitFactionGroup", "player")
    local nous = faction == "Horde" and 0 or 1
    if gagnant ~= nous then return end
    local f = Fiche()
    if not f then return end
    local zone = NS.base.ChampActuel()
    if not zone then return end
    local victoires = NS.base.Table(NS.base.Table(f, "jcj"), "victoires")
    victoires[zone] = (tonumber(victoires[zone]) or 0) + 1
    NS.Changer("jcj")
end

-- ---------------------------------------------------------------------------
-- Tout a la connexion (court : quelques dizaines de lectures)
-- ---------------------------------------------------------------------------

function releve.Tout()
    NS.Proteger("identite", releve.Identite)
    NS.Proteger("exploration", releve.Exploration)
    NS.Proteger("zone", releve.ZoneActuelle)
    NS.Proteger("quetes", releve.Quetes)
    NS.Proteger("metiers", releve.NiveauxDesMetiers)
    NS.Proteger("sacs", releve.Sacs)
    NS.Proteger("equipement", releve.Equipement)
    NS.Proteger("reputations", releve.Reputations)
    NS.Proteger("jcj", releve.JcJ)
end
