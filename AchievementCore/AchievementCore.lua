local _, NS = ...

-- AchievementCore (nom d'usage : GloryCore) : demarrage, evenements, commandes.
--   /glorycore, /achievementcore (ou /ach)   la fenetre
--   /ach releve                  refait tous les releves du personnage

local T = NS.T
local releve = NS.releve
local Proteger = NS.Proteger

if NS.suite and NS.suite.Annoncer then NS.suite.Annoncer("AchievementCore") end

local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_LOGIN")

-- Un releve differe d'un instant, jamais deux fois de suite pour rien.
local prevus = {}
local function Bientot(cle, delai, fn)
    if prevus[cle] then return end
    prevus[cle] = true
    local apres = NS.Lecture("C_Timer.After")
    local function Faire() prevus[cle] = nil Proteger(cle, fn) end
    if apres then apres(delai, Faire) else Faire() end
end

-- Le journal de combat, toujours lu, le plus vite possible :
--   boss des raids : la mort d'un PNJ boss de la base, dans son instance ;
--   rares : la mort d'un rare que le joueur, son familier ou son groupe a
--   touche (ou dont il a donne le coup fatal).
local journalOuvert = false
local function SuivreLeJournal()
    if not journalOuvert then journalOuvert = pcall(cadre.RegisterEvent, cadre, "COMBAT_LOG_EVENT_UNFILTERED") end
end

local AFFILIATION = 0x7 -- moi, mon groupe, mon raid (COMBATLOG_OBJECT_AFFILIATION_*)
local idDe, nIds = {}, 0
local touches = {}
local function IdDe(guid)
    local id = idDe[guid]
    if id == nil then
        id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or false
        nIds = nIds + 1
        if nIds > 3000 then idDe, nIds, touches = {}, 0, {} end
        idDe[guid] = id
    end
    return id
end

local function RareTue(id)
    local f = NS.base.Fiche(NS.ClePersonnage())
    if not f then return end
    local rares = NS.base.Table(f, "rares")
    if rares[id] then return end
    rares[id] = NS.Appeler(time) or true
    NS.Changer("rares", "donjons")
end

local band = _G.bit and _G.bit.band
local function MortDansLeJournal()
    local lire = _G.CombatLogGetCurrentEventInfo
    if not lire then return end
    local _, sousEvenement, _, _, _, drapeauxSource, _, guid = lire()
    sousEvenement = NS.Sur(sousEvenement)
    guid = NS.Sur(guid)
    if type(guid) ~= "string" then return end
    if sousEvenement ~= "UNIT_DIED" and sousEvenement ~= "PARTY_KILL" then
        -- Un coup porte par moi ou mon groupe sur un rare : il compte a sa mort.
        drapeauxSource = NS.Sur(drapeauxSource)
        if band and type(drapeauxSource) == "number" and band(drapeauxSource, AFFILIATION) ~= 0 then
            local id = IdDe(guid)
            if id and NS.base.EstRare(id) then touches[guid] = true end
        end
        return
    end
    local id = IdDe(guid)
    if not id then return end
    if NS.base.EstRare(id) and (touches[guid] or sousEvenement == "PARTY_KILL") then
        touches[guid] = nil
        RareTue(id)
    end
    local zone = releve.instance
    if not zone then return end
    for _, b in ipairs(NS.base.BossDeZone(zone) or {}) do
        if b.id == id then
            local f = NS.base.Fiche(NS.ClePersonnage())
            local boss = NS.base.Table(f, "boss")
            boss[zone] = type(boss[zone]) == "table" and boss[zone] or {}
            if not boss[zone]["pnj:" .. id] then
                boss[zone]["pnj:" .. id] = true
                NS.Changer("donjons")
            end
            return
        end
    end
end

local EVENEMENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED",
    "UPDATE_FACTION", "PLAYER_LEVEL_UP", "ENCOUNTER_END", "BOSS_KILL",
    "PLAYER_PVP_RANK_CHANGED", "PLAYER_PVP_KILLS_CHANGED", "UPDATE_BATTLEFIELD_STATUS", "UPDATE_BATTLEFIELD_SCORE",
    "PLAYER_XP_UPDATE",
}

cadre:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4, a5)
    if ev == "COMBAT_LOG_EVENT_UNFILTERED" then pcall(MortDansLeJournal) return end
    if ev == "PLAYER_LOGIN" then
        NS.base.Init()
        for _, e in ipairs(EVENEMENTS) do pcall(cadre.RegisterEvent, cadre, e) end
        Proteger("fenetre", NS.fenetre.Construire)
        SuivreLeJournal()
        Proteger("rythme", releve.Rythme)
        -- Les releves un peu apres la connexion (le jeu doit etre pret), les
        -- grandes listes ensuite, par petits morceaux.
        Bientot("tout", 4, releve.Tout)
        Bientot("preparer", 15, NS.base.Preparer)
        return
    end
    if ev == "PLAYER_ENTERING_WORLD" or ev:find("^ZONE_CHANGED") then
        Bientot("zone", 1, function() releve.ZoneActuelle() SuivreLeJournal() end)
    elseif ev == "QUEST_TURNED_IN" then
        Proteger("quete rendue", releve.QueteRendue, a1)
    elseif ev == "BAG_UPDATE_DELAYED" then
        Bientot("sacs", 1, releve.Sacs)
    elseif ev == "PLAYER_EQUIPMENT_CHANGED" then
        Bientot("equipement", 1, releve.Equipement)
    elseif ev == "BANKFRAME_OPENED" or ev == "PLAYERBANKSLOTS_CHANGED" then
        Bientot("banque", 1, releve.Banque)
    elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_LIST_UPDATE" or ev == "NEW_RECIPE_LEARNED" then
        Bientot("recettes", 2, function() releve.Recettes() NS.Changer("metiers") end)
    elseif ev == "SKILL_LINES_CHANGED" then
        Bientot("metiers", 2, function() releve.NiveauxDesMetiers() NS.Changer("metiers") end)
    elseif ev == "UPDATE_FACTION" then
        Bientot("reputations", 3, releve.Reputations)
    elseif ev == "PLAYER_LEVEL_UP" then
        Bientot("niveau", 1, releve.Identite)
    elseif ev == "PLAYER_XP_UPDATE" then
        Proteger("rythme", releve.Rythme)
    elseif ev == "ENCOUNTER_END" then
        Proteger("rencontre", releve.Rencontre, a1, a2, a5)
    elseif ev == "BOSS_KILL" then
        Proteger("rencontre", releve.Rencontre, a1, a2, 1)
    elseif ev == "PLAYER_PVP_RANK_CHANGED" or ev == "PLAYER_PVP_KILLS_CHANGED" then
        Bientot("jcj", 2, releve.JcJ)
    elseif ev == "UPDATE_BATTLEFIELD_STATUS" or ev == "UPDATE_BATTLEFIELD_SCORE" then
        Proteger("champ", releve.FinDeChamp)
    end
end)

SLASH_ACHIEVEMENTCORE1 = "/achievementcore"
SLASH_ACHIEVEMENTCORE2 = "/ach"
SLASH_ACHIEVEMENTCORE3 = "/glorycore"
SlashCmdList.ACHIEVEMENTCORE = function(arg)
    arg = (arg or ""):lower()
    if arg:match("^rel") or arg:match("^scan") then
        releve.Tout()
        NS.Dire(T("Relevés refaits.", "Records refreshed."))
        return
    end
    if NS.fenetre and NS.fenetre.Ouvrir and NS.fenetre.Ouvrir() then return end
    NS.Dire(T("La fenêtre n'est pas encore prête.", "The window is not ready yet."))
end
