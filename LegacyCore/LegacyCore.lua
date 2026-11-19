local _, NS = ...

-- Demarrage de LegacyCore, commande /lc.

local L = NS.L
local evenements = CreateFrame("Frame")
evenements:RegisterEvent("PLAYER_LOGIN")

local function ReleverBientot()
    local plusTard = NS.Lecture("C_Timer.After")
    local function Faire()
        local ok, souci = pcall(NS.base.Releve)
        if not ok then NS.base.NoterIncident("releve", souci) end
        -- Points a depenser sur ce personnage : pastille verte sur l'onglet
        -- LegacyCore, dans toute la suite.
        local d = LegacyCoreDB
        local releve = type(d) == "table" and d.persos and d.persos[NS.ClePersonnage() or ""]
        local libres = 0
        for _, a in ipairs(releve and releve.arbres or {}) do libres = math.max(libres, tonumber(a.disponibles) or 0) end
        if NS.suite and NS.suite.PoserBadge then pcall(NS.suite.PoserBadge, "LegacyCore", libres > 0 and libres or nil) end
        if NS.fenetre.Visible() then NS.fenetre.Rendre() end
    end
    if plusTard then plusTard(3, Faire) else Faire() end
end

-- Temps de jeu : demande au jeu sans afficher sa reponse dans la discussion
-- (seulement pour nos demandes ; un /played tape par le joueur s'affiche).
local enAttente, muets = false, {}
local function DemanderTempsDeJeu()
    local demander = NS.Lecture("RequestTimePlayed")
    if not demander or enAttente then return end
    enAttente = true
    muets = {}
    for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do
        local f = _G["ChatFrame" .. i]
        if f and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
            f:UnregisterEvent("TIME_PLAYED_MSG")
            table.insert(muets, f)
        end
    end
    pcall(demander)
    local plusTard = NS.Lecture("C_Timer.After")
    -- Filet de securite : la discussion retrouve toujours l'evenement.
    if plusTard then plusTard(5, function()
        for _, f in ipairs(muets) do pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG") end
        muets, enAttente = {}, false
    end) end
end

local function TempsRecu(total, ceNiveau)
    pcall(NS.base.NoterTempsDeJeu, total, ceNiveau)
    if enAttente then
        local plusTard = NS.Lecture("C_Timer.After")
        local function Rendre()
            for _, f in ipairs(muets) do pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG") end
            muets, enAttente = {}, false
        end
        if plusTard then plusTard(0, Rendre) else Rendre() end
    end
    if NS.fenetre.Visible() then NS.fenetre.Rendre() end
end

evenements:SetScript("OnEvent", function(_, evenement, a1, a2)
    if evenement == "TIME_PLAYED_MSG" then TempsRecu(a1, a2) return end
    if evenement == "PLAYER_LEVEL_UP" then
        pcall(NS.base.NoterNiveau, a1)
        local plusTard = NS.Lecture("C_Timer.After")
        if plusTard then plusTard(2, DemanderTempsDeJeu) end
    end
    if evenement == "PLAYER_LOGIN" then
        NS.base.Init()
        if NS.suite then
            pcall(NS.suite.Inscrire, "LegacyCore", {
                ouvrir = function() NS.fenetre.Ouvrir() end,
                fenetre = function() return NS.fenetre.Cadre() end,
            })
        end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
            "PLAYER_LEVEL_UP", "TIME_PLAYED_MSG" }) do
            pcall(evenements.RegisterEvent, evenements, e)
        end
        local plusTard = NS.Lecture("C_Timer.After")
        if plusTard then plusTard(8, DemanderTempsDeJeu) end
        NS.Dire(string.format(L.LOADED, NS.VERSION))
    end
    ReleverBientot()
end)

SLASH_LEGACYCORE1 = "/lc"
SLASH_LEGACYCORE2 = "/legacycore"
SlashCmdList.LEGACYCORE = function() NS.fenetre.Basculer() end
