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
-- connecte seulement) : un parcours vers un niveau deja atteint. Les
-- anciennes tournees de rendu (genre "rendu") disparaissent : rendre les
-- quetes terminees est un objectif de guidage, sans parcours enregistre.
-- Kit de donjon : il se complete tout seul. Une quete du donjon qui devient
-- prenable (son prerequis fait, comme Boissons fortes apres les cornes de
-- raptors) ou qu'on prend s'y ajoute, a la suite. Au plus toutes les 5 s.
local derniereCompletion = 0
local function CompleterKits(p, liste)
    local maintenant = (GetTime and GetTime()) or 0
    if maintenant - derniereCompletion < 5 then return end
    derniereCompletion = maintenant
    if not (NS.donjons and NS.donjons.Liste and NS.donjons.DeQuete) then return end
    local donjons
    for _, pc in ipairs(liste) do
        if pc.genre == "kit" and type(pc.etapes) == "table" then
            -- Son donjon : celui de la plupart de ses etapes.
            local zone = pc.donjon
            if not zone then
                local compte, meilleur = {}, 0
                for _, id in ipairs(pc.etapes) do
                    local d = NS.donjons.DeQuete(id)
                    if d then
                        compte[d.zone] = (compte[d.zone] or 0) + 1
                        if compte[d.zone] > meilleur then meilleur, zone = compte[d.zone], d.zone end
                    end
                end
                pc.donjon = zone
            end
            if zone then
                donjons = donjons or NS.donjons.Liste(p)
                for _, d in ipairs(donjons) do
                    if d.zone == zone then
                        local deja = {}
                        for _, id in ipairs(pc.etapes) do deja[id] = true end
                        for _, id in ipairs(d.restantes or {}) do
                            local e = parcours.EtatEtape(p, id)
                            if not deja[id] and (e == "cours" or e == "rendre" or e == "prendre") then
                                table.insert(pc.etapes, id)
                                deja[id] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

local function Nettoyer(cle, liste)
    if cle ~= NS.ClePersonnage() then return end
    local pP = NS.base.Perso(cle)
    if pP then pcall(CompleterKits, pP, liste) end
    local niveau = tonumber(NS.Appeler(UnitLevel, "player")) or 0
    local p = NS.base.Perso(cle)
    for i = #liste, 1, -1 do
        local pc = liste[i]
        local vise = pc.genre == "progression" and (pc.niveauVise or tonumber(string.match(tostring(pc.nom), "(%d+)")))
        if (vise and niveau >= vise) or pc.genre == "rendu" then table.remove(liste, i) end
    end
end

-- Anciens noms des kits ("Prerequis : X", "Avant d'y aller : X") : ils
-- contiennent les quetes du donjon (chacune dit si elle se fait dedans) et
-- leurs prerequis, d'ou le nom "Quetes du donjon : X".
local ANCIENS_KITS = { "^Prérequis : (.+)$", "^Prerequisites: (.+)$", "^Voraussetzungen: (.+)$", "^Requisitos: (.+)$",
    "^Prerequisiti: (.+)$", "^Предварительные задания: (.+)$", "^前置任务：(.+)$",
    -- "Avant d'y aller" laissait croire que tout se faisait avant le donjon.
    "^Avant d'y aller : (.+)$", "^Before you go : (.+)$", "^Vor dem Besuch: (.+)$", "^Antes de ir: (.+)$",
    "^Prima di andare: (.+)$", "^Перед походом: (.+)$", "^出发前：(.+)$" }
local function Renommer(liste)
    for _, pc in ipairs(liste) do
        if pc.genre == "kit" and type(pc.nom) == "string" then
            for _, motif in ipairs(ANCIENS_KITS) do
                local nom = pc.nom:match(motif)
                if nom then pc.nom = string.format(NS.L.DUNGEON_KIT_NAME, nom) break end
            end
        end
    end
end

-- Identifiant unique d'un parcours, jamais reutilise (l'id d'ordre peut
-- l'etre apres une suppression) : c'est lui que guide un objectif.
local function NouvelUid()
    local t = tonumber(NS.Appeler(time)) or 0
    return string.format("p%d:%d", t, math.random(1000, 9999))
end
local function PoserUids(liste)
    for _, pc in ipairs(liste) do
        if type(pc) == "table" and type(pc.uid) ~= "string" then pc.uid = NouvelUid() end
    end
end

function parcours.Liste(cle)
    local d = QuestCoreDB
    if type(d) ~= "table" or not cle then return {} end
    d.parcours = d.parcours or {}
    d.parcours[cle] = d.parcours[cle] or {}
    pcall(Renommer, d.parcours[cle])
    pcall(Nettoyer, cle, d.parcours[cle])
    pcall(PoserUids, d.parcours[cle])
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

function parcours.TrouverUid(cle, uid)
    if not uid then return nil end
    for rang, pc in ipairs(parcours.Liste(cle)) do
        if pc.uid == uid then return pc, rang end
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

-- Un parcours dont toutes les etapes sont faites n'a plus rien a montrer :
-- il disparait tout seul, rien a gerer a la main. Seulement quand
-- l'historique des quetes rendues est connu (sinon rien ne parait fait).
-- Rend les identifiants retires.
function parcours.Nettoyer(cle, p)
    local retires = {}
    if not (p and type(p.faites) == "table" and next(p.faites)) then return retires end
    local liste = parcours.Liste(cle)
    for i = #liste, 1, -1 do
        local pc = liste[i]
        local total = type(pc.etapes) == "table" and #pc.etapes or 0
        if total > 0 then
            local faites = parcours.Avancement(p, pc)
            if faites >= total then
                table.insert(retires, pc.id)
                table.remove(liste, i)
            end
        end
    end
    return retires
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

-- Le chemin faisable des maintenant jusqu'a une quete : ses prerequis pas
-- encore faits (a prendre, en cours ou a rendre), dans l'ordre, puis elle.
-- nil si un maillon demande un niveau plus haut ou n'est pas pour sa race.
function parcours.CheminVers(p, id)
    local liste, vus = {}, {}
    Avant(p, id, liste, vus, 0)
    local res = {}
    for _, q in ipairs(liste) do
        if not Faite(p, q) then
            if not RaceAdmise(p, q) then return nil end
            local niveau = tonumber(Lire("QuestDB", q, "requiredLevel")) or 0
            if p and p.niveau and niveau > p.niveau and not EnCours(p, q) then return nil end
            table.insert(res, q)
        end
    end
    return res
end

function parcours.CreerSuite(cle, p, id)
    local etapes = parcours.Suite(p, id)
    if #etapes == 0 then return nil end
    local liste = parcours.Liste(cle)
    local derniere = etapes[#etapes]
    local pc = { id = NouvelId(liste), uid = NouvelUid(), genre = "suite", carte = true, etapes = etapes,
        nom = NS.ref.NomDeQuete(derniere, p) }
    table.insert(liste, pc)
    return pc
end

function parcours.CreerSelection(cle, p, premiere)
    local liste = parcours.Liste(cle)
    local pc = { id = NouvelId(liste), uid = NouvelUid(), genre = "selection", carte = true, etapes = { premiere },
        nom = string.format(NS.L.ROUTE_DEFAULT_NAME, NouvelId(liste)) }
    table.insert(liste, pc)
    return pc
end

-- Kit de donjon : les quetes a prendre avant d'y aller, dans l'ordre donne.
-- Un kit du meme nom deja la est remplace.
function parcours.CreerKit(cle, ids, nom, zone)
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local liste = parcours.Liste(cle)
    for i = #liste, 1, -1 do
        if liste[i].genre == "kit" and liste[i].nom == nom then table.remove(liste, i) end
    end
    local etapes = {}
    for _, id in ipairs(ids) do table.insert(etapes, id) end
    local pc = { id = NouvelId(liste), uid = NouvelUid(), genre = "kit", carte = true, etapes = etapes, nom = nom, donjon = zone }
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
-- Pendant le guidage d'un objectif de QuestCore, seules ses etapes sont
-- montrees, numerotees dans l'ordre vise : pas de conflit de numeros ni de
-- pointilles avec un parcours.
function parcours.EtapesSurCarte(cle, p)
    local numeros = {}
    local g = NS.guidage
    local objectif = g and g.Objectif and g.Objectif()
    local uidGuide = objectif and objectif.type == "parcours" and objectif.params.uid or nil
    if objectif and not uidGuide then
        local etapes = g.Etapes and g.Etapes() or {}
        local rang = 0
        for _, e in ipairs(etapes) do
            if e.id and not numeros[e.id] then
                rang = rang + 1
                numeros[e.id] = { numero = rang, etat = parcours.EtatEtape(p, e.id), parcours = objectif.libelle, idParcours = "objectif" }
            end
        end
        return numeros
    end
    local liste = {}
    for _, pc in ipairs(parcours.Liste(cle)) do
        if uidGuide then
            if pc.uid == uidGuide then table.insert(liste, pc) end
        else
            table.insert(liste, pc)
        end
    end
    for _, pc in ipairs(liste) do
        if pc.carte or pc.uid == uidGuide then
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
