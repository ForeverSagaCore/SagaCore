local _, NS = ...

-- Socle d'AuraCore : ce que le socle de la suite (Suite.lua, Charte.lua)
-- attend de chaque add-on. AuraCore peut ainsi vivre seul, avec la meme
-- fenetre et les memes reglages que la suite complete.

NS.VERSION = "0.9.0-beta"
NS.base = {}
local base = NS.base

function NS.Lecture(...)
    for i = 1, select("#", ...) do
        local chemin = select(i, ...)
        local valeur = _G
        for morceau in string.gmatch(chemin, "[^%.]+") do
            if type(valeur) ~= "table" then valeur = nil break end
            valeur = valeur[morceau]
        end
        if type(valeur) == "function" then return valeur end
    end
    return nil
end

function NS.Appeler(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 15)
end

function NS.Dire(texte)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100AuraCore|r " .. tostring(texte)) end
end

-- "Nom - Royaume", la meme cle que les autres add-ons de la suite.
function NS.ClePersonnage()
    local nom = NS.Appeler(UnitName, "player")
    local royaume = NS.Appeler(_G.SagaCoreRoyaume or GetRealmName)
    if type(nom) ~= "string" or nom == "" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

function base.ReglagesGeneraux()
    AuraCoreDB = type(AuraCoreDB) == "table" and AuraCoreDB or {}
    AuraCoreDB.general = type(AuraCoreDB.general) == "table" and AuraCoreDB.general or {}
    return AuraCoreDB.general
end

function base.NoterIncident(quoi, souci)
    AuraCoreDB = type(AuraCoreDB) == "table" and AuraCoreDB or {}
    AuraCoreDB.incidents = type(AuraCoreDB.incidents) == "table" and AuraCoreDB.incidents or {}
    local l = AuraCoreDB.incidents
    table.insert(l, { quoi = quoi, souci = tostring(souci), quand = NS.Appeler(time) })
    while #l > 30 do table.remove(l, 1) end
end
