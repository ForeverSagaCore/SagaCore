local _, NS = ...

-- Parcours : une suite de quetes a faire dans un ordre, comme un projet de
-- CraftCore. Deux genres :
--   "suite"      toute la chaine d'une quete : prerequis manquants, la quete,
--                puis ses suites jusqu'a la derniere, dans l'ordre ;
--   "selection"  des quetes choisies une a une, dans l'ordre voulu.
-- Chaque personnage a ses parcours, gardes a part (QuestCoreDB.parcours).

NS.parcours = {}
local parcours = NS.parcours

local Lire = function(...) return NS.ref.Lire(...) end
local MAX_ETAPES = 40

-- ---------------------------------------------------------------------------
-- Rangement
-- ---------------------------------------------------------------------------

-- Parcours qui n'ont plus lieu d'etre, retires d'eux-memes (personnage
-- connecte seulement) : un parcours vers un niveau deja atteint, une tournee
-- de rendu dont toutes les quetes sont rendues.
local function Nettoyer(cle, liste)
    if cle ~= NS.ClePersonnage() then return end
    local niveau = tonumber(NS.Appeler(UnitLevel, "player")) or 0
    local p = NS.base.Perso(cle)
    for i = #liste, 1, -1 do
        local pc = liste[i]
        local vise = (pc.genre == "progression" and (pc.niveauVise or tonumber(string.match(tostring(pc.nom), "(%d+)"))))
            or (pc.genre == "rendu" and pc.niveauVise)
        local fini = false
        if pc.genre == "rendu" and p then
            fini = true
            for _, id in ipairs(pc.etapes or {}) do
                if not (p.faites and p.faites[id]) then fini = false break end
            end
        end
        if (vise and niveau >= vise) or fini then table.remove(liste, i) end
    end
end

function parcours.Liste(cle)
    local d = QuestCoreDB
    if type(d) ~= "table" or not cle then return {} end
    d.parcours = d.parcours or {}
    d.parcours[cle] = d.parcours[cle] or {}
    pcall(Nettoyer, cle, d.parcours[cle])
    return d.parcours[cle]
end

local function NouvelId(liste)
    local maxi = 0
    for _, pc in ipairs(liste) do maxi = math.max(maxi, pc.id or 0) end
    return maxi + 1
end

function parcours.Trouver(cle, id)
    for rang, pc in ipairs(parcours.Liste(cle)) do
        if pc.id == id then return pc, rang end
    end
    return nil
end

-- Passer une etape : elle sort du parcours et n'y revient plus d'elle-meme
-- (ni l'ajustement en route, ni le recalcul du trajet de niveau).
function parcours.PasserEtape(cle, idParcours, quete)
    local pc = parcours.Trouver(cle, idParcours)
    if not pc then return false end
    for rang = #pc.etapes, 1, -1 do
        if pc.etapes[rang] == quete then table.remove(pc.etapes, rang) end
    end
    pc.ignorees = pc.ignorees or {}
    pc.ignorees[quete] = true
    if pc.vus then pc.vus[quete] = true end
    if NS.Trace then NS.Trace("etape passee : " .. tostring(quete)) end
    return true
end

-- Remettre une etape retiree (case cochee de nouveau).
function parcours.RemettreEtape(cle, idParcours, quete)
    local pc = parcours.Trouver(cle, idParcours)
    if not pc then return false end
    if pc.ignorees then pc.ignorees[quete] = nil end
    for _, id in ipairs(pc.etapes) do if id == quete then return true end end
    table.insert(pc.etapes, quete)
    return true
end

function parcours.Supprimer(cle, id)
    local liste = parcours.Liste(cle)
    local _, rang = parcours.Trouver(cle, id)
    if rang then table.remove(liste, rang) end
end

-- ---------------------------------------------------------------------------
-- Ce que le personnage peut prendre
-- ---------------------------------------------------------------------------

local function RaceAdmise(p, id)
    local masque = tonumber(Lire("QuestDB", id, "requiredRaces"))
    if not masque or masque == 0 or not p or not p.race then return true end
    if not bit or not bit.band then return true end
    return bit.band(masque, 2 ^ (p.race - 1)) ~= 0
end

local function Faite(p, id) return p and p.faites and p.faites[id] == true end
local function EnCours(p, id) return p and p.quetes and p.quetes[id] ~= nil end

-- Les prerequis de la quete sont-ils remplis pour ce personnage ?
function parcours.PrerequisRemplis(p, id)
    local groupe, une = NS.ref.Prerequis(id)
    for _, pre in ipairs(groupe) do
        if not Faite(p, pre) then return false end
    end
    if #une > 0 then
        local ok = false
        for _, pre in ipairs(une) do if Faite(p, pre) then ok = true break end end
        if not ok then return false end
    end
    return true
end

-- Une quete pas encore prise que ce personnage peut prendre maintenant.
function parcours.Prenable(p, id)
    if Faite(p, id) or EnCours(p, id) then return false end
    if not RaceAdmise(p, id) then return false end
    local niveau = tonumber(Lire("QuestDB", id, "requiredLevel")) or 0
    if p and p.niveau and niveau > p.niveau then return false end
    return parcours.PrerequisRemplis(p, id)
end

-- ---------------------------------------------------------------------------
-- Toute la suite d'une quete
-- ---------------------------------------------------------------------------

-- Ajoute a `liste`, avant elle, les prerequis de la quete encore utiles.
local function Avant(p, id, liste, vus, profondeur)
    if not id or vus[id] or profondeur > 25 or #liste >= MAX_ETAPES then return end
    vus[id] = true
    -- Une quete faite garde sa place, mais ce qui la precede est forcement fait.
    if not Faite(p, id) then
        local groupe, une = NS.ref.Prerequis(id)
        for _, pre in ipairs(groupe) do Avant(p, pre, liste, vus, profondeur + 1) end
        if #une > 0 then
            local choisie
            for _, pre in ipairs(une) do
                if Faite(p, pre) or EnCours(p, pre) then choisie = pre break end
            end
            if not choisie then
                for _, pre in ipairs(une) do
                    if RaceAdmise(p, pre) then choisie = pre break end
                end
            end
            if choisie then Avant(p, choisie, liste, vus, profondeur + 1) end
        end
    end
    table.insert(liste, id)
end

function parcours.Suite(p, id)
    local liste, vus = {}, {}
    Avant(p, id, liste, vus, 0)
    local suivante = tonumber(Lire("QuestDB", id, "nextQuestInChain"))
    local garde = 0
    while suivante and suivante > 0 and not vus[suivante] and garde < 30 and #liste < MAX_ETAPES do
        Avant(p, suivante, liste, vus, 0)
        suivante = tonumber(Lire("QuestDB", suivante, "nextQuestInChain"))
        garde = garde + 1
    end
    return liste
end

function parcours.CreerSuite(cle, p, id)
    local etapes = parcours.Suite(p, id)
    if #etapes == 0 then return nil end
    local liste = parcours.Liste(cle)
    local derniere = etapes[#etapes]
    local pc = { id = NouvelId(liste), genre = "suite", carte = true, etapes = etapes,
        nom = NS.ref.NomDeQuete(derniere, p) }
    table.insert(liste, pc)
    return pc
end

function parcours.CreerSelection(cle, p, premiere)
    local liste = parcours.Liste(cle)
    local pc = { id = NouvelId(liste), genre = "selection", carte = true, etapes = { premiere },
        nom = string.format(NS.L.ROUTE_DEFAULT_NAME, NouvelId(liste)) }
    table.insert(liste, pc)
    return pc
end

-- Kit de donjon : les quetes a prendre avant d'y aller, dans l'ordre donne.
-- Un kit du meme nom deja la est remplace.
function parcours.CreerKit(cle, ids, nom)
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local liste = parcours.Liste(cle)
    for i = #liste, 1, -1 do
        if liste[i].genre == "kit" and liste[i].nom == nom then table.remove(liste, i) end
    end
    local etapes = {}
    for _, id in ipairs(ids) do table.insert(etapes, id) end
    local pc = { id = NouvelId(liste), genre = "kit", carte = true, etapes = etapes, nom = nom }
    table.insert(liste, pc)
    return pc
end

function parcours.Ajouter(cle, idParcours, quete)
    local pc = parcours.Trouver(cle, idParcours)
    if not pc then return end
    for _, e in ipairs(pc.etapes) do if e == quete then return end end
    table.insert(pc.etapes, quete)
end

function parcours.Deplacer(cle, idParcours, rang, sens)
    local pc = parcours.Trouver(cle, idParcours)
    if not pc then return end
    local cible = rang + sens
    if cible < 1 or cible > #pc.etapes then return end
    pc.etapes[rang], pc.etapes[cible] = pc.etapes[cible], pc.etapes[rang]
end

function parcours.Retirer(cle, idParcours, rang)
    local pc = parcours.Trouver(cle, idParcours)
    if pc then table.remove(pc.etapes, rang) end
end

-- ---------------------------------------------------------------------------
-- Avancement
-- ---------------------------------------------------------------------------

-- Etat d'une etape : "faite", "rendre", "cours", "prendre" (disponible
-- maintenant) ou "attente" (pas encore prenable).
function parcours.EtatEtape(p, id)
    if Faite(p, id) then return "faite" end
    local q = p and p.quetes and p.quetes[id]
    if q then return (q.complete == true) and "rendre" or "cours" end
    if parcours.Prenable(p, id) then return "prendre" end
    return "attente"
end

function parcours.Avancement(p, pc)
    local faites = 0
    for _, id in ipairs(pc.etapes) do if Faite(p, id) then faites = faites + 1 end end
    local total = #pc.etapes
    local pct = total > 0 and math.floor(faites * 100 / total + 0.5) or 0
    return faites, total, pct
end

-- Premiere etape pas encore faite : la prochaine chose a faire.
function parcours.Prochaine(p, pc)
    for rang, id in ipairs(pc.etapes) do
        if not Faite(p, id) then return rang, id end
    end
    return nil
end

-- Pour la carte : etapes a montrer, { [quete] = numero }, des parcours
-- affiches du personnage. Une etape faite n'a rien a montrer ; une etape pas
-- encore prenable est montree en retrait, chez son donneur.
-- Pendant le guidage, seul le trajet guide est montre : pas de conflit de
-- numeros ni de pointilles avec un autre parcours. Sinon, la tournee de rendu
-- passe d'abord (une quete presente dans deux parcours garde son numero).
function parcours.EtapesSurCarte(cle, p)
    local numeros = {}
    local guide = (NS.guidage and NS.guidage.Actif and NS.guidage.Actif())
        or (NS.pageCarte and NS.pageCarte.EnModeTrajet and NS.pageCarte.EnModeTrajet())
    -- Un parcours precis guide (kit de donjon...) : lui seul.
    local idGuide = NS.guidage and NS.guidage.Actif and NS.guidage.Actif()
        and NS.guidage.ParcoursGuide and NS.guidage.ParcoursGuide()
    local liste = {}
    for _, pc in ipairs(parcours.Liste(cle)) do
        if idGuide then
            if pc.id == idGuide then table.insert(liste, pc) end
        elseif pc.genre == "rendu" then table.insert(liste, 1, pc)
        elseif not guide then table.insert(liste, pc) end
    end
    for _, pc in ipairs(liste) do
        if pc.carte or (guide and (pc.genre == "rendu" or pc.id == idGuide)) then
            -- Numerotees dans l'ordre de ce qui reste a faire : 1, 2, 3...
            local rang = 0
            for _, id in ipairs(pc.etapes) do
                local e = parcours.EtatEtape(p, id)
                if e ~= "faite" then
                    rang = rang + 1
                    if not numeros[id] then
                        numeros[id] = { numero = rang, etat = e, parcours = pc.nom, idParcours = pc.id }
                    end
                end
            end
        end
    end
    return numeros
end
