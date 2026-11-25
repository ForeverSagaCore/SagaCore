local _, NS = ...

-- Persistance. Le jeu remplace la table enregistree APRES le chargement des
-- fichiers : on ne garde donc jamais de reference prise ici, on relit toujours
-- la table au moment de s'en servir. Patron repris du journal de donjon.
CraftCoreDB = CraftCoreDB or {}

local SCHEMA = 1

NS.base = {}
local base = NS.base

-- Migrations. Chacune ajoute ou complete, aucune ne retire jamais rien : une
-- mise a jour de l'addon ne doit pas pouvoir rendre un historique illisible.
local migrations = {}

-- Appelee a chaque connexion. Cree ce qui manque, migre si besoin, et ne
-- touche a rien d'autre.
function base.Preparer()
    local d = CraftCoreDB
    if type(d) ~= "table" then
        d = {}
        CraftCoreDB = d
    end

    local depuis = tonumber(d.schema) or 0
    local premiereFois = (depuis == 0 and d.personnages == nil)

    for cible = depuis + 1, SCHEMA do
        local migrer = migrations[cible]
        if migrer then migrer(d) end
    end
    d.schema = SCHEMA
    d.version = NS.VERSION

    -- Structures attendues, creees seulement si absentes.
    d.personnages = d.personnages or {}
    -- Fiches fantomes, creees quand le nom n'etait pas encore connu : on les
    -- retire, elles n'ont jamais designe un vrai personnage.
    for cle in pairs(d.personnages) do
        if type(cle) ~= "string" or string.find(cle, "^%?%s%-") or string.find(cle, "%-%s%?$") then
            d.personnages[cle] = nil
        end
    end
    if type(d.personnageAffiche) == "string" and not d.personnages[d.personnageAffiche]
        and d.personnageAffiche ~= "tous" then
        d.personnageAffiche = nil
    end
    d.decouverte = d.decouverte or {}
    d.decouverte.conteneursDeBanque = d.decouverte.conteneursDeBanque or {}

    return premiereFois
end

-- Fiche du personnage courant. Toujours lue, jamais memorisee.
function base.Personnage()
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return nil end
    local cle = NS.ClePersonnage()
    -- Nom pas encore connu : une fiche jetable, jamais enregistree.
    if not cle then return { cle = "?", temporaire = true } end
    local fiche = d.personnages[cle]
    if not fiche then
        fiche = { cle = cle }
        d.personnages[cle] = fiche
    end
    return fiche
end

function base.Decouverte()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.decouverte = d.decouverte or {}
    d.decouverte.conteneursDeBanque = d.decouverte.conteneursDeBanque or {}
    return d.decouverte
end

-- Un conteneur de banque reste connu une fois decouvert, meme banque fermee.
function base.NoterConteneurDeBanque(id)
    local dec = base.Decouverte()
    if not dec then return false end
    if dec.conteneursDeBanque[tostring(id)] then return false end
    dec.conteneursDeBanque[tostring(id)] = true
    return true
end

function base.EstConteneurDeBanque(id)
    local dec = base.Decouverte()
    if not dec then return false end
    return dec.conteneursDeBanque[tostring(id)] == true
end

-- Lectures tolerantes : une fiche ecrite par une version qui ne connaissait pas
-- encore un champ doit rester lisible sans lui.
function base.StocksDe(fiche)
    if type(fiche) ~= "table" or type(fiche.stocks) ~= "table" then return {} end
    return fiche.stocks
end

function base.ConteneursDe(fiche)
    if type(fiche) ~= "table" or type(fiche.conteneurs) ~= "table" then return {} end
    return fiche.conteneurs
end

function base.ReleveDe(fiche)
    if type(fiche) ~= "table" then return nil end
    return fiche.releveLe
end

-- Tous les personnages connus, le courant en premier.
-- Un meme personnage releve sous deux cles (ancienne fiche au royaume mal
-- lu, « Nom - Legacy »...) n'est montre et compte qu'une fois : la fiche du
-- personnage connecte, sinon celle du royaume courant, sinon la plus haute
-- en niveau, sinon la premiere dans l'ordre des cles. Les autres sont des
-- doublons, gardees sur le disque mais jamais affichees ni additionnees.
local function RoyaumeDe(cle) return string.match(cle or "", "%-%s*(.-)%s*$") or "" end
function base.EstDoublon(cle)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" or type(cle) ~= "string" then return false end
    local nom = NS.inventaire.NomCourt(cle)
    local courant = NS.ClePersonnage()
    local royaume = RoyaumeDe(courant)
    local function Rang(c, f)
        if c == courant then return 4 end
        local r = (royaume ~= "" and RoyaumeDe(c) == royaume) and 2 or 0
        return r + (tonumber(type(f) == "table" and f.niveau) or 0) / 1000
    end
    local moi = Rang(cle, d.personnages[cle])
    for autre, f in pairs(d.personnages) do
        if autre ~= cle and NS.inventaire.NomCourt(autre) == nom then
            local r = Rang(autre, f)
            if r > moi or (r == moi and autre < cle) then return true end
        end
    end
    return false
end

function base.TousLesPersonnages()
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return {} end
    local courant = NS.ClePersonnage()
    local liste = {}
    if d.personnages[courant] then table.insert(liste, d.personnages[courant]) end
    local autres = {}
    for cle in pairs(d.personnages) do
        if cle ~= courant and not base.EstDoublon(cle) then table.insert(autres, cle) end
    end
    table.sort(autres)
    for _, cle in ipairs(autres) do table.insert(liste, d.personnages[cle]) end
    return liste
end

-- Journal d'incidents. Borne aux derniers, et jamais au detriment du reste de
-- la base : un incident est une information, pas une raison de tout perdre.
local INCIDENTS_MAX = 10

function base.NoterIncident(ou, souci)
    local d = CraftCoreDB
    if type(d) ~= "table" then return end
    d.incidents = d.incidents or {}
    table.insert(d.incidents, {
        quand = NS.Horodatage(),
        ou = tostring(ou),
        souci = tostring(souci),
        version = NS.VERSION,
    })
    while #d.incidents > INCIDENTS_MAX do
        table.remove(d.incidents, 1)
    end
end

-- Reglages de l'utilisateur. Crees avec leurs valeurs par defaut s'ils
-- manquent : une base ecrite avant leur existence reste lisible.
function base.Reglages()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { afficherNonApprises = true } end
    d.reglages = d.reglages or {}
    d.reglages.recettes = d.reglages.recettes or {}
    local r = d.reglages.recettes
    if r.afficherNonApprises == nil then r.afficherNonApprises = true end
    return r
end

-- Filtre d'affichage des recettes, retenu par metier. Valeurs : "connues",
-- "nonConnues", "toutes". Absent vaut "toutes".
function base.FiltreDuMetier(ligne)
    local d = CraftCoreDB
    if type(d) ~= "table" or not ligne then return "toutes" end
    d.reglages = d.reglages or {}
    d.reglages.recettes = d.reglages.recettes or {}
    d.reglages.recettes.parMetier = d.reglages.recettes.parMetier or {}
    return d.reglages.recettes.parMetier[tostring(ligne)] or "toutes"
end

function base.PoserFiltreDuMetier(ligne, valeur)
    local d = CraftCoreDB
    if type(d) ~= "table" or not ligne then return end
    d.reglages = d.reglages or {}
    d.reglages.recettes = d.reglages.recettes or {}
    d.reglages.recettes.parMetier = d.reglages.recettes.parMetier or {}
    d.reglages.recettes.parMetier[tostring(ligne)] = valeur
end

-- Fiche du personnage dont l'ecran montre les donnees. Distincte de la fiche
-- du personnage connecte, qui reste la seule ou l'on ecrit les releves.
function base.FicheAffichee()
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return nil end
    local cle = base.PersonnageAffiche()
    if cle == "tous" then return base.Personnage() end
    return d.personnages[cle] or base.Personnage()
end

function base.CleAffichee()
    local cle = base.PersonnageAffiche()
    if cle == "tous" then return NS.ClePersonnage() end
    return cle
end

-- Personnage dont on regarde les stocks. Par defaut celui qui joue.
function base.PersonnageAffiche()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    local choix = d.personnageAffiche
    if choix == "tous" then return "tous" end
    local S = NS.suite
    local visible = not (S and S.Visible) or not choix or S.Visible(choix)
    if choix and d.personnages and d.personnages[choix] and visible then return choix end
    -- Faction regardee differente de celle du personnage connecte.
    local autre = S and S.PersoDeLaFaction and S.PersoDeLaFaction()
    if autre and d.personnages and d.personnages[autre] then return autre end
    return NS.ClePersonnage()
end

function base.PoserPersonnageAffiche(cle)
    local d = CraftCoreDB
    if type(d) ~= "table" then return end
    d.personnageAffiche = cle
    -- Le meme personnage dans toute la suite (QuestCore suit ce choix).
    -- "Tous les personnages" reste propre a CraftCore.
    local S = NS.suite
    if S and S.PoserPersonnage and type(cle) == "string" and cle ~= "tous" then
        base.persoSuiteVu = S.PoserPersonnage(cle)
    end
end

-- Applique le personnage choisi dans un autre add-on de la suite, s'il est
-- plus recent que le dernier vu ici.
function base.SuivreLaSuite()
    local S = NS.suite
    local d = CraftCoreDB
    if not (S and S.Personnage) or type(d) ~= "table" then return end
    local cle, version = S.Personnage()
    if version and version ~= base.persoSuiteVu then
        base.persoSuiteVu = version
        if cle and d.personnages and d.personnages[cle] then d.personnageAffiche = cle end
    end
end

-- Execute `fonction` comme si `cle` etait le personnage affiche, puis remet
-- le choix d'avant, quoi qu'il arrive. Les calculs de projets suivent le
-- personnage affiche : c'est ainsi qu'on calcule pour un autre personnage
-- sans toucher a ce que l'ecran montre.
function base.AvecPersonnage(cle, fonction, ...)
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    local avant = d.personnageAffiche
    d.personnageAffiche = cle
    local resultats = { pcall(fonction, ...) }
    d.personnageAffiche = avant
    if not resultats[1] then error(resultats[2], 0) end
    return unpack(resultats, 2, 5)
end

-- Reglages generaux, crees avec leurs valeurs par defaut s'ils manquent.
function base.ReglagesGeneraux()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { infobulles = true, assistant = true } end
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    local g = d.reglages.general
    if g.infobulles == nil then g.infobulles = true end
    if g.assistant == nil then g.assistant = true end
    return g
end
