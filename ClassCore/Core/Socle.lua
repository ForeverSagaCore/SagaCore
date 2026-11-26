local _, NS = ...

-- Socle de ClassCore : ce que le socle de la suite (Suite.lua, Charte.lua)
-- attend de chaque add-on. ClassCore peut ainsi vivre seul, avec la meme
-- fenetre et les memes reglages que la suite complete.

NS.VERSION = "2.5.2"
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
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ClassCore|r " .. tostring(texte)) end
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
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.general = type(ClassCoreDB.general) == "table" and ClassCoreDB.general or {}
    return ClassCoreDB.general
end

function base.NoterIncident(quoi, souci)
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.incidents = type(ClassCoreDB.incidents) == "table" and ClassCoreDB.incidents or {}
    local l = ClassCoreDB.incidents
    table.insert(l, { quoi = quoi, souci = tostring(souci), quand = NS.Appeler(time) })
    while #l > 30 do table.remove(l, 1) end
end
