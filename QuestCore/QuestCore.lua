local _, NS = ...

-- Demarrage, evenements du journal de quetes, commande /qc.

local L = NS.L
local evenements = CreateFrame("Frame")

-- Un seul releve pour une rafale d'evenements du journal.
local relevePrevu = false
local function ReleverBientot()
    if relevePrevu then return end
    relevePrevu = true
    local plusTard = NS.Lecture("C_Timer.After")
    local function Faire()
        relevePrevu = false
        local ok, souci = pcall(NS.journal.Relever)
        if not ok then NS.base.NoterIncident("releve du journal", souci) end
        if NS.carte then
            NS.carte.Invalider()
            local okC, souciC = pcall(NS.carte.Rendre)
            if not okC then NS.base.NoterIncident("carte", souciC) end
        end
        -- Guidage d'un trajet de niveau : il s'adapte aux quetes du moment.
        if NS.guidage and NS.guidage.Actif() and NS.suivi.AdapterTrajetNiveau then
            local okA, souciA = pcall(NS.suivi.AdapterTrajetNiveau)
            if not okA then NS.base.NoterIncident("trajet de niveau", souciA) end
            local okB, souciB = pcall(NS.suivi.AdapterTrajet)
            if not okB then NS.base.NoterIncident("trajet, quete en route", souciB) end
        end
        if NS.fenetre.Visible() then NS.fenetre.Rendre() end
        if NS.suivi then NS.suivi.Rendre() end
    end
    if plusTard then plusTard(0.5, Faire) else Faire() end
end

-- Objets arrives du serveur : on redessine la fenetre, une fois pour la rafale.
local dessinPrevu = false
local function RendreBientot()
    if dessinPrevu or not NS.fenetre.Visible() then return end
    dessinPrevu = true
    local plusTard = NS.Lecture("C_Timer.After")
    local function Faire()
        dessinPrevu = false
        if NS.fenetre.Visible() then NS.fenetre.Rendre() end
    end
    if plusTard then plusTard(0.3, Faire) else Faire() end
end

evenements:RegisterEvent("PLAYER_LOGIN")
evenements:SetScript("OnEvent", function(_, evenement, ...)
    if evenement == "PLAYER_LOGIN" then
        NS.base.Init()
        if not NS.ref.Disponible() then NS.Dire(L.NO_DB) end
        pcall(NS.infobulles.Installer)
        local okS, souciS = pcall(NS.suivi.Installer)
        if not okS then NS.base.NoterIncident("suivi", souciS) end
        local okB, souciB = pcall(NS.ConstruireBoutonDeMinicarte)
        if not okB then NS.base.NoterIncident("bouton de minicarte", souciB) end
        -- Suite Core : un seul bouton de minicarte pour CraftCore, QuestCore, MapCore.
        if NS.suite then
            pcall(NS.suite.Inscrire, "QuestCore", {
                ouvrir = function() NS.fenetre.Ouvrir() end,
                fenetre = function() return NS.fenetre.Cadre() end,
                boutonMinicarte = _G.QuestCoreMinimapButton,
            })
        end
        for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
            "PLAYER_LEVEL_UP" }) do
            pcall(evenements.RegisterEvent, evenements, e)
        end
        pcall(evenements.RegisterEvent, evenements, "QUEST_TURNED_IN")
        pcall(evenements.RegisterEvent, evenements, "PLAYER_EQUIPMENT_CHANGED")
        pcall(evenements.RegisterEvent, evenements, "GET_ITEM_INFO_RECEIVED")
        pcall(evenements.RegisterEvent, evenements, "PLAYER_XP_UPDATE")
        pcall(evenements.RegisterEvent, evenements, "ZONE_CHANGED_NEW_AREA")
        ReleverBientot()
        pcall(NS.ref.ConstruireIndexRecompenses)
        local okC, souciC = pcall(NS.courrier.Installer)
        if not okC then NS.base.NoterIncident("courrier", souciC) end
        NS.Dire(string.format(L.LOADED, NS.VERSION))
    elseif evenement == "QUEST_TURNED_IN" then
        local id = ...
        pcall(NS.journal.Rendue, tonumber(id))
        NS.disponibles.Invalider()
        ReleverBientot()
    elseif evenement == "ZONE_CHANGED_NEW_AREA" then
        -- Nouvelle zone : la page Carte suit le personnage.
        if NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
    elseif evenement == "PLAYER_XP_UPDATE" then
        -- XP gagnee : le bilan (prochain niveau) suit.
        RendreBientot()
    elseif evenement == "GET_ITEM_INFO_RECEIVED" then
        RendreBientot()
    elseif evenement == "UNIT_QUEST_LOG_CHANGED" then
        if ... == "player" then ReleverBientot() end
    else
        -- Quete prise, abandonnee, niveau gagne : les disponibles changent.
        if evenement == "QUEST_ACCEPTED" or evenement == "QUEST_REMOVED" or evenement == "PLAYER_LEVEL_UP" then
            NS.disponibles.Invalider()
        end
        ReleverBientot()
    end
end)

SLASH_QUESTCORE1 = "/qc"
SLASH_QUESTCORE2 = "/questcore"
SlashCmdList.QUESTCORE = function(texte)
    texte = string.lower(texte or "")
    if string.find(texte, "bandeau") or string.find(texte, "banner") then
        if NS.bandeau then NS.bandeau.Placer() end
    elseif string.find(texte, "suivi") or string.find(texte, "track") then
        NS.suivi.Basculer()
    else
        NS.fenetre.Basculer()
    end
end

