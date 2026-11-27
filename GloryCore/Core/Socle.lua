local _, NS = ...

-- Socle d'GloryCore : ce que le socle de la suite (Suite.lua,
-- Charte.lua) attend de chaque add-on, la base de sauvegarde et les lectures
-- sous filet. GloryCore peut ainsi vivre seul, avec la meme fenetre et
-- les memes reglages que la suite complete.

NS.VERSION = "0.1.0"
NS.base = {}
local base = NS.base

-- Une fonction du jeu par son chemin ("C_Map.GetMapInfo"), ou nil.
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

-- Une valeur secrete (le jeu la cache aux add-ons) ne sert jamais : nil.
function NS.Sur(v)
    if v ~= nil and _G.issecretvalue then
        local ok, secret = pcall(_G.issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

-- Appel par chemin, valeurs secretes ecartees (les dix premieres).
function NS.Jeu(chemin, ...)
    local fn = NS.Lecture(chemin)
    if not fn then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    local S = NS.Sur
    return S(r[2]), S(r[3]), S(r[4]), S(r[5]), S(r[6]), S(r[7]), S(r[8]), S(r[9]), S(r[10]), S(r[11])
end

function NS.Dire(texte)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100GloryCore|r " .. tostring(texte)) end
end

-- "Nom - Royaume", la meme cle que les autres add-ons de la suite.
function NS.ClePersonnage()
    local nom = NS.Sur(NS.Appeler(UnitName, "player"))
    local royaume = NS.Sur(NS.Appeler(_G.SagaCoreRoyaume or GetRealmName))
    if type(nom) ~= "string" or nom == "" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

function NS.NomCourt(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

-- Un bit d'un masque (races, classes, drapeaux) sans bibliotheque : les
-- masques de la base depassent 32 bits.
function NS.Bit(masque, rang)
    masque = tonumber(masque) or 0
    if rang < 1 then return false end
    return math.floor(masque / 2 ^ (rang - 1)) % 2 == 1
end

-- 12450 -> "12 450".
function NS.Nombre(n)
    local texte = tostring(math.floor(tonumber(n) or 0))
    while true do
        local suite, k = texte:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        texte = suite
        if k == 0 then break end
    end
    return texte
end

-- Pourcentage arrondi vers le bas : 100 % seulement quand tout est fait.
function NS.Pct(fait, total)
    fait, total = tonumber(fait) or 0, tonumber(total) or 0
    if total <= 0 then return 0 end
    if fait >= total then return 100 end
    return math.floor(fait * 100 / total)
end

function NS.TextePct(fait, total) return NS.Pct(fait, total) .. " %" end

-- Un add-on de la suite est-il charge ?
function NS.AddOnCharge(nom)
    local charge = NS.Lecture("C_AddOns.IsAddOnLoaded", "IsAddOnLoaded")
    return charge and NS.Appeler(charge, nom) and true or false
end

-- Un mot sans accents ni majuscules, pour rapprocher deux noms.
function NS.Cle(texte)
    texte = string.lower(tostring(texte or ""))
    texte = string.gsub(texte, "^the ", "")
    texte = string.gsub(texte, "^l[ae] ", "")
    texte = string.gsub(texte, "%s+$", "")
    return texte
end

-- ---------------------------------------------------------------------------
-- Base de sauvegarde
-- ---------------------------------------------------------------------------

function base.Init()
    GloryCoreDB = type(GloryCoreDB) == "table" and GloryCoreDB or {}
    local d = GloryCoreDB
    d.persos = type(d.persos) == "table" and d.persos or {}
    d.reglages = type(d.reglages) == "table" and d.reglages or {}
    d.reglages.general = type(d.reglages.general) == "table" and d.reglages.general or {}
    d.incidents = type(d.incidents) == "table" and d.incidents or {}
    -- Ce que le compte apprend en jeu : recettes vues (sans CraftCore), noms
    -- des lieux explores, boss rencontres, factions.
    d.recettes = type(d.recettes) == "table" and d.recettes or {}
    d.lieux = type(d.lieux) == "table" and d.lieux or {}
    d.rencontres = type(d.rencontres) == "table" and d.rencontres or {}
    d.factions = type(d.factions) == "table" and d.factions or {}
    d.version = NS.VERSION
    return d
end

function base.DB()
    if type(GloryCoreDB) ~= "table" then return base.Init() end
    return GloryCoreDB
end

function base.ReglagesGeneraux()
    local d = base.DB()
    d.reglages = type(d.reglages) == "table" and d.reglages or {}
    d.reglages.general = type(d.reglages.general) == "table" and d.reglages.general or {}
    return d.reglages.general
end

function base.Reglages()
    local d = base.DB()
    d.reglages = type(d.reglages) == "table" and d.reglages or {}
    return d.reglages
end

-- La fiche du personnage dans notre base (creee au besoin).
function base.Fiche(cle)
    if type(cle) ~= "string" then return nil end
    local d = base.DB()
    local f = d.persos[cle]
    if type(f) ~= "table" then f = { cle = cle } d.persos[cle] = f end
    return f
end

-- Une table de la fiche, creee au besoin.
function base.Table(fiche, champ)
    if type(fiche) ~= "table" then return {} end
    if type(fiche[champ]) ~= "table" then fiche[champ] = {} end
    return fiche[champ]
end

function base.NoterIncident(quoi, souci)
    local d = base.DB()
    d.incidents = type(d.incidents) == "table" and d.incidents or {}
    table.insert(d.incidents, { quoi = tostring(quoi), souci = tostring(souci), quand = NS.Appeler(time) })
    while #d.incidents > 30 do table.remove(d.incidents, 1) end
end

-- Un appel qui ne casse jamais rien : l'erreur va dans le journal.
function NS.Proteger(quoi, fn, ...)
    local ok, souci = pcall(fn, ...)
    if not ok then base.NoterIncident(quoi, souci) end
    return ok
end

-- ---------------------------------------------------------------------------
-- Versions des donnees : chaque releve qui change quelque chose fait monter
-- la version de sa categorie ; les calculs gardes d'une version plus
-- ancienne sont refaits a la demande, jamais avant.
-- ---------------------------------------------------------------------------

NS.versions = { tout = 1 }
function NS.Changer(...)
    local n = select("#", ...)
    if n == 0 then
        for cle in pairs(NS.versions) do NS.versions[cle] = NS.versions[cle] + 1 end
    else
        for i = 1, n do
            local cle = select(i, ...)
            NS.versions[cle] = (NS.versions[cle] or 1) + 1
        end
    end
    NS.versions.tout = NS.versions.tout + 1
    if NS.fenetre and NS.fenetre.Signaler then NS.fenetre.Signaler() end
end
function NS.Version(cle) return NS.versions[cle] or 1 end
