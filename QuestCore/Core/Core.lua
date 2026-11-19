local _, NS = ...

-- Socle : lectures sous filet, base de sauvegarde, cle du personnage.

NS.VERSION = "0.29.11"
NS.base = {}
local base = NS.base

-- Une fonction du jeu par son chemin ("C_QuestLog.GetInfo"), ou nil.
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

-- Appel sous filet : nil si la fonction manque ou leve une erreur.
function NS.Appeler(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 15)
end

-- MapCore (l'add-on de carte) est-il installe et actif ?
function NS.MapCorePresent()
    local charge = NS.Lecture("C_AddOns.IsAddOnLoaded", "IsAddOnLoaded")
    return charge and NS.Appeler(charge, "MapCore") and true or false
end

function NS.Dire(texte)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100QuestCore|r " .. tostring(texte)) end
end

-- "Nom - Royaume", la meme cle que CraftCore.
function NS.ClePersonnage()
    local nom = NS.Appeler(UnitName, "player")
    local royaume = NS.Appeler(GetRealmName)
    if type(nom) ~= "string" or nom == "" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

function NS.NomCourt(cle)
    return string.match(cle or "", "^(.-)%s*%-") or cle or "?"
end

function base.Init()
    QuestCoreDB = type(QuestCoreDB) == "table" and QuestCoreDB or {}
    local d = QuestCoreDB
    d.persos = d.persos or {}
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    d.incidents = d.incidents or {}
    -- Rapports de diagnostic de l'ancienne carte du monde : plus utilises.
    d.constatCarte, d.constatPage = nil, nil
end

function base.Perso(cle)
    local d = QuestCoreDB
    if type(d) ~= "table" or not cle then return nil end
    d.persos[cle] = d.persos[cle] or { cle = cle, quetes = {}, faites = {} }
    return d.persos[cle]
end

-- Jeton de classe ("HUNTER") d'une fiche de CraftCore, qui note le nom traduit.
local function JetonDeClasse(fiche)
    if fiche.jetonClasse then return fiche.jetonClasse end
    if type(fiche.classe) ~= "string" then return nil end
    for _, noms in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(noms) == "table" then
            for jeton, nom in pairs(noms) do if nom == fiche.classe then return jeton end end
        end
    end
    if _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[fiche.classe] then return fiche.classe end
    return nil
end

-- Tous les personnages du compte : ceux que QuestCore a releves, plus ceux
-- que CraftCore connait (sans quetes tant qu'ils ne se sont pas connectes
-- avec QuestCore). Le courant en premier, puis par nom.
function base.Persos()
    local liste, courant, vus = {}, NS.ClePersonnage(), {}
    for cle, p in pairs((QuestCoreDB or {}).persos or {}) do
        if type(p) == "table" then table.insert(liste, p) vus[cle] = true end
    end
    local craft = type(_G.CraftCoreDB) == "table" and _G.CraftCoreDB.personnages
    if type(craft) == "table" then
        for cle, fiche in pairs(craft) do
            if type(fiche) == "table" and not vus[cle] and type(cle) == "string" and cle:find(" %- ") then
                table.insert(liste, { cle = cle, niveau = fiche.niveau, classe = JetonDeClasse(fiche),
                    faction = fiche.faction, quetes = {}, faites = {}, nonReleve = true })
            end
        end
    end
    base.cacheParCle = {}
    for _, p in ipairs(liste) do base.cacheParCle[p.cle] = p end
    table.sort(liste, function(a, b)
        if a.cle == courant then return true end
        if b.cle == courant then return false end
        return tostring(a.cle) < tostring(b.cle)
    end)
    return liste
end

-- Reglages communs (la charte y lit le fond de fenetre).
function base.ReglagesGeneraux()
    local d = QuestCoreDB
    if type(d) ~= "table" then return {} end
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    return d.reglages.general
end

-- Filtre "a rendre" : partage par le suivi, la fenetre et la carte.
function base.FiltreARendre() return base.ReglagesGeneraux().aRendre == true end

function base.NombreARendre(p)
    local n = 0
    for _, q in pairs(p and p.quetes or {}) do if q.complete == true then n = n + 1 end end
    return n
end

function base.PoserFiltreARendre(actif)
    base.ReglagesGeneraux().aRendre = actif and true or nil
    if NS.carte and NS.carte.Invalider then pcall(NS.carte.Invalider) end
    if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    if NS.fenetre and NS.fenetre.Rendre then pcall(NS.fenetre.Rendre) end
end

-- Journal d'incidents, borne : une erreur ne casse jamais la fenetre.
function base.NoterIncident(quoi, souci)
    local d = QuestCoreDB
    if type(d) ~= "table" then return end
    d.incidents = d.incidents or {}
    table.insert(d.incidents, { quoi = tostring(quoi), souci = tostring(souci), quand = NS.Appeler(time) })
    while #d.incidents > 50 do table.remove(d.incidents, 1) end
end

-- Un personnage par sa cle, releve ou seulement connu de CraftCore.
function base.PersoParCle(cle)
    local d = QuestCoreDB
    if type(d) == "table" and d.persos and d.persos[cle] then return d.persos[cle] end
    if not base.cacheParCle then base.Persos() end
    return base.cacheParCle and base.cacheParCle[cle]
end
