local _, NS = ...

-- Socle de MapCore : lectures sous filet, base de sauvegarde.

NS.VERSION = "0.6.6"
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
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100MapCore|r " .. tostring(texte)) end
end

-- "Nom - Royaume", la meme cle que les autres add-ons de la suite.
function NS.ClePersonnage()
    local nom = NS.Appeler(UnitName, "player")
    local royaume = NS.Appeler(GetRealmName)
    if type(nom) ~= "string" or nom == "" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

function NS.NomCourt(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

function base.Init()
    MapCoreDB = type(MapCoreDB) == "table" and MapCoreDB or {}
    local d = MapCoreDB
    d.reperes = d.reperes or {}
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    d.incidents = d.incidents or {}
end

function base.ReglagesGeneraux()
    local d = MapCoreDB
    if type(d) ~= "table" then return {} end
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    return d.reglages.general
end

function base.NoterIncident(quoi, souci)
    local d = MapCoreDB
    if type(d) ~= "table" then return end
    d.incidents = d.incidents or {}
    table.insert(d.incidents, { quoi = quoi, souci = tostring(souci), quand = NS.Appeler(time) })
    while #d.incidents > 20 do table.remove(d.incidents, 1) end
end

-- Reperes de l'utilisateur : { id, carte, x, y, icone (1 a 8), note, rayon (0 a 3) }.
function base.Reperes()
    local d = MapCoreDB
    if type(d) ~= "table" then return {} end
    d.reperes = d.reperes or {}
    return d.reperes
end

function base.NouveauRepere(carte, x, y)
    local liste = base.Reperes()
    local maxi = 0
    for _, r in ipairs(liste) do maxi = math.max(maxi, r.id or 0) end
    local r = { id = maxi + 1, carte = carte, x = x, y = y, icone = 1, note = "", rayon = 0 }
    table.insert(liste, r)
    return r
end

function base.SupprimerRepere(id)
    local liste = base.Reperes()
    for rang, r in ipairs(liste) do
        if r.id == id then table.remove(liste, rang) return end
    end
end

-- Pour les autres add-ons de la suite : les reperes poses sur une carte.
_G.MapCoreAPI = {
    Reperes = function(carte)
        local liste = {}
        for _, r in ipairs(base.Reperes()) do
            if r.carte == carte then table.insert(liste, r) end
        end
        return liste
    end,
}

-- ---------------------------------------------------------------------------
-- Ou sont mes personnages : derniere position connue et foyer
-- ---------------------------------------------------------------------------
-- Note a la connexion, a chaque changement de zone, quand le foyer change et
-- a la deconnexion. Pour les autres personnages, c'est la ou on les a laisses.

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) end

function base.NoterPosition()
    local d = MapCoreDB
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    if type(d) ~= "table" or not cle then return end
    d.persos = type(d.persos) == "table" and d.persos or {}
    local p = d.persos[cle] or {}
    d.persos[cle] = p
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    if carte and not Secret(carte) then
        local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
        if type(pos) == "table" and pos.GetXY then
            local ok, x, y = pcall(pos.GetXY, pos)
            if ok and x and y and not Secret(x) and not Secret(y) and (x ~= 0 or y ~= 0) then
                p.carte, p.x, p.y = carte, x, y
            end
        end
    end
    local zone = NS.Appeler(NS.Lecture("GetRealZoneText"))
    if type(zone) == "string" and zone ~= "" then p.zone = zone end
    local foyer = NS.Appeler(NS.Lecture("GetBindLocation"))
    if type(foyer) == "string" and foyer ~= "" then p.foyer = foyer end
    local niveau = NS.Appeler(NS.Lecture("UnitLevel"), "player")
    if tonumber(niveau) then p.niveau = tonumber(niveau) end
    local _, classe = NS.Appeler(NS.Lecture("UnitClass"), "player")
    if type(classe) == "string" then p.classe = classe end
    p.quand = NS.Appeler(NS.Lecture("time"))
end

-- Tous les personnages notes, le connecte d'abord.
function base.Positions()
    local d = MapCoreDB
    local liste = {}
    local moi = NS.ClePersonnage and NS.ClePersonnage()
    for cle, p in pairs(type(d) == "table" and type(d.persos) == "table" and d.persos or {}) do
        if type(p) == "table" then
            local copie = { cle = cle, moi = cle == moi }
            for k, v in pairs(p) do copie[k] = v end
            table.insert(liste, copie)
        end
    end
    table.sort(liste, function(a, b)
        if a.moi ~= b.moi then return a.moi end
        return a.cle < b.cle
    end)
    return liste
end
