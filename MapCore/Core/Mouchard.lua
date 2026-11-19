local NOM, NS = ...

-- Mouchard : le meme fichier dans chaque add-on de la suite. Il garde dans
-- les sauvegardes de l'add-on (<Nom>DB.mouchard) de quoi comprendre un
-- plantage :
--   - les erreurs Lua qui viennent de cet add-on (message, pile d'appels,
--     version, zone, combat, memoire), sans empecher l'affichage normal ;
--   - les avertissements du jeu et les actions bloquees qui le concernent ;
--   - les incidents deja notes par l'add-on (erreurs rattrapees) ;
--   - les dernieres actions (traces) avant chaque erreur ;
--   - la fin de la session precedente : si elle ne s'est pas terminee
--     normalement (deconnexion ou /reload), une entree "fin anormale" avec le
--     dernier releve de memoire.
-- Limite : si le jeu se ferme d'un coup, il n'ecrit pas les sauvegardes ;
-- seul ce qui avait ete ecrit a la derniere sauvegarde reste.

local MAX_ERREURS, MAX_TRACES, MAX_PILE = 40, 15, 2000
local CHEMIN = "AddOns[/\\]" .. NOM .. "[/\\]"

local mouchard = {}
NS.mouchard = mouchard
local enAttente, traces = {}, {}
local pret = false

local function Base()
    local nomDB = NOM .. "DB"
    if type(_G[nomDB]) ~= "table" then _G[nomDB] = {} end
    local d = _G[nomDB]
    if type(d.mouchard) ~= "table" then d.mouchard = {} end
    local m = d.mouchard
    if type(m.erreurs) ~= "table" then m.erreurs = {} end
    return m
end

local function Quand()
    local ok, t = pcall(date, "%Y-%m-%d %H:%M:%S")
    return ok and t or "?"
end

local function Version()
    if NS.VERSION then return NS.VERSION end
    local lire = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local ok, v = pcall(lire, NOM, "Version")
    return ok and v or "?"
end

local function Memoire()
    local lire = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
    local ok, ko = pcall(lire, NOM)
    return ok and tonumber(ko) and math.floor(ko) or nil
end

local function Contexte()
    local zone = _G.GetRealZoneText and select(2, pcall(_G.GetRealZoneText)) or nil
    local combat = _G.InCombatLockdown and select(2, pcall(_G.InCombatLockdown)) or nil
    local niveau = _G.UnitLevel and select(2, pcall(_G.UnitLevel, "player")) or nil
    return { zone = type(zone) == "string" and zone or nil, combat = combat == true or nil,
        niveau = tonumber(niveau), memoire = Memoire() }
end

-- Une trace : ce que l'add-on vient de faire (ouvrir une page, guider...).
function mouchard.Trace(texte)
    local t = (_G.GetTime and select(2, pcall(_G.GetTime))) or 0
    table.insert(traces, string.format("%.1f %s", tonumber(t) or 0, tostring(texte)))
    while #traces > MAX_TRACES do table.remove(traces, 1) end
end
NS.Trace = mouchard.Trace

local function Ecrire(e)
    local m = Base()
    -- Meme erreur deja notee : on compte, on garde la date et les traces.
    for _, x in ipairs(m.erreurs) do
        if x.genre == e.genre and x.message == e.message then
            x.fois = (x.fois or 1) + 1
            x.derniere = e.quand
            x.traces = e.traces
            x.version = e.version
            return
        end
    end
    table.insert(m.erreurs, e)
    while #m.erreurs > MAX_ERREURS do table.remove(m.erreurs, 1) end
end

function mouchard.Noter(genre, message, pile)
    local e = Contexte()
    e.genre, e.message, e.quand, e.version = genre, tostring(message), Quand(), Version()
    if pile then e.pile = string.sub(tostring(pile), 1, MAX_PILE) end
    local copie = {}
    for k, t in ipairs(traces) do copie[k] = t end
    e.traces = copie
    if pret then pcall(Ecrire, e) else table.insert(enAttente, e) end
end

-- Erreurs Lua : on note celles de cet add-on, puis le gestionnaire d'avant
-- (celui du jeu, ou d'un autre add-on) fait son travail habituel.
local avant = _G.geterrorhandler and _G.geterrorhandler()
if _G.seterrorhandler then
    _G.seterrorhandler(function(message, ...)
        local ok = pcall(function()
            local pile = _G.debugstack and _G.debugstack(2, 20, 10) or ""
            -- La pile contient aussi les mouchards des autres add-ons (ils
            -- s'enchainent) : on les retire avant de chercher le nom.
            local sansMouchards = string.gsub(pile, "[^\n]*Mouchard%.lua[^\n]*", "")
            local msg = tostring(message)
            local autreAddon = string.find(msg, "AddOns[/\\]") and not string.find(msg, CHEMIN)
            if string.find(msg, CHEMIN) or (not autreAddon and string.find(sansMouchards, CHEMIN)) then
                mouchard.Noter("erreur", message, pile)
            end
        end)
        if avant then return avant(message, ...) end
    end)
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "LUA_WARNING",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
local releve = 0
cadre:SetScript("OnEvent", function(_, evenement, a1, a2)
    if evenement == "ADDON_LOADED" then
        if a1 ~= NOM then return end
        pret = true
        local m = Base()
        -- Session precedente : terminee proprement ?
        local s = m.session
        if type(s) == "table" and not s.fin then
            local e = { genre = "fin anormale", message = "Session interrompue sans deconnexion ni /reload",
                quand = s.dernier or s.debut or "?", version = s.version, memoire = s.memoire,
                zone = s.zone, traces = s.traces, fois = 1 }
            pcall(Ecrire, e)
        end
        m.session = { debut = Quand(), version = Version() }
        for _, e in ipairs(enAttente) do pcall(Ecrire, e) end
        enAttente = {}
    elseif evenement == "PLAYER_LOGIN" then
        -- Les incidents deja rattrapes par l'add-on passent aussi ici.
        local base = NS.base
        if base and type(base.NoterIncident) == "function" and not base.mouchardBranche then
            base.mouchardBranche = true
            local origine = base.NoterIncident
            base.NoterIncident = function(quoi, souci, ...)
                pcall(mouchard.Noter, "incident", tostring(quoi) .. " : " .. tostring(souci))
                return origine(quoi, souci, ...)
            end
        end
    elseif evenement == "PLAYER_LOGOUT" then
        local m = Base()
        if type(m.session) == "table" then m.session.fin = Quand() end
    elseif evenement == "LUA_WARNING" then
        if string.find(tostring(a2), CHEMIN) then mouchard.Noter("avertissement", a2) end
    elseif a1 == NOM then
        -- Action protegee bloquee : a2 est la fonction refusee.
        mouchard.Noter(evenement == "ADDON_ACTION_FORBIDDEN" and "action interdite" or "action bloquee", a2,
            _G.debugstack and _G.debugstack(2, 20, 10) or nil)
    end
end)

-- Toutes les 30 secondes : un releve de la session (heure, memoire, zone,
-- traces). Il part avec la prochaine sauvegarde ; apres une fin anormale,
-- c'est le dernier etat connu.
cadre:SetScript("OnUpdate", function(_, ecoule)
    releve = releve - (ecoule or 0)
    if releve > 0 or not pret then return end
    releve = 30
    local ok = pcall(function()
        local maj = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
        if maj then maj() end
        local m = Base()
        local s = type(m.session) == "table" and m.session or {}
        m.session = s
        local c = Contexte()
        if s.memoire and c.memoire and c.memoire > s.memoire * 2 and c.memoire > 20000 then
            mouchard.Trace(string.format("memoire %d Ko (avant %d Ko)", c.memoire, s.memoire))
        end
        s.dernier, s.memoire, s.zone = Quand(), c.memoire, c.zone
        local copie = {}
        for k, t in ipairs(traces) do copie[k] = t end
        s.traces = copie
    end)
end)
