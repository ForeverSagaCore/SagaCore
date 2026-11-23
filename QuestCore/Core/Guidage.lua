local _, NS = ...

-- Guidage de QuestCore : le catalogue de ses objectifs, declare au moteur de
-- la suite (Core/Suite.lua). Chaque bouton guide un objectif precis et s'y
-- tient :
--   rendus {}                 toutes les quetes terminees du journal, dans
--                             l'ordre le plus rapide ; une quete terminee en
--                             route s'ajoute, une quete prise en route n'a
--                             aucun effet ; atteint quand plus rien n'est a
--                             rendre ;
--   quetes { ids }            exactement ces quetes : leurs objectifs, puis
--                             leur rendu ; atteint quand elles ont toutes
--                             quitte le journal ;
--   niveau { niveau = N }     les quetes qui menent au niveau N ; atteint au
--                             niveau N ;
--   parcours { uid }          un parcours enregistre (kit de donjon, suite...) ;
--                             atteint quand il est fini ou qu'il disparait.

NS.guidage = NS.guidage or {}
local guidage = NS.guidage
local L = NS.L

local function S() return NS.suite or _G.CoreSuite end

local function Moi()
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    return cle and NS.base.Perso(cle), cle
end

-- Carte du continent ou se trouve le personnage.
local function Continent()
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    for _ = 1, 6 do
        local info = carte and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
        if type(info) ~= "table" then return nil end
        if info.mapType == 2 then return carte end
        carte = info.parentMapID
    end
    return nil
end

local function Titre(id, moi)
    local q = moi and moi.quetes and moi.quetes[id]
    return (q and q.titre) or (NS.ref.Lire and NS.ref.Lire("QuestDB", id, "name")) or ("#" .. tostring(id))
end

-- Ou aller quand la prochaine quete est hors de portee (autre continent) :
-- sa quete, puis la zone et le continent, sous "Hors de portee".
local function OuAller(moi, ids)
    local info = NS.Lecture("C_Map.GetMapInfo")
    for _, id in ipairs(ids or {}) do
        local ok, points = pcall(NS.carte.PointsPour, id, moi)
        local pt = ok and points and points[1]
        local titre = Titre(id, moi)
        if not (pt and pt.carte and info) then return titre end
        local zone = NS.Appeler(info, pt.carte)
        local nomZone = type(zone) == "table" and zone.name or nil
        local continent
        local parent = type(zone) == "table" and zone.parentMapID
        for _ = 1, 4 do
            local z = parent and NS.Appeler(info, parent)
            if type(z) ~= "table" then break end
            if z.mapType == 2 then continent = z.name break end
            parent = z.parentMapID
        end
        local ou = nomZone and (continent and string.format("%s (%s)", nomZone, continent) or nomZone)
        return ou and (titre .. "\n|cffb3b3b3" .. string.format(L.GUIDE_GO_TO, ou) .. "|r") or titre
    end
    return nil
end

-- Le lieu ou aller pour une quete, en coordonnees du continent : chez le
-- receveur si elle est terminee, la ou se fait l'objectif si elle est en
-- cours, chez le donneur sinon ; a defaut, ses autres points, puis l'entree
-- du donjon ou elle se fait.
local function PointDeQuete(id, moi, continent, jx, jy)
    local meilleur, lieu
    local ok, points = pcall(NS.carte.PointsPour, id, moi)
    local q = moi.quetes and moi.quetes[id]
    local voulu = (q and q.complete == true) and "rendre" or (q and "objectif") or "prendre"
    for passe = 1, 2 do
        for _, pt in ipairs(ok and points or {}) do
            if (passe == 1 and pt.genre == voulu) or (passe == 2 and pt.genre ~= "prendre") then
                local x, y = NS.carte.Reporter(pt, continent)
                if x then
                    local d = (x - jx) ^ 2 + (y - jy) ^ 2
                    if not meilleur or d < meilleur then meilleur, lieu = d, { x = x, y = y, qui = pt.quoi } end
                end
            end
        end
        if lieu then break end
    end
    if not lieu and NS.donjons and NS.donjons.DeQuete then
        local d = NS.donjons.DeQuete(id)
        for _, e in ipairs(d and d.entrees or {}) do
            local x, y = NS.carte.Reporter({ carte = e.carte, x = e.x, y = e.y }, continent)
            if x then
                local dd = (x - jx) ^ 2 + (y - jy) ^ 2
                if not meilleur or dd < meilleur then meilleur, lieu = dd, { x = x, y = y, qui = d.nom, entree = d.nom } end
            end
        end
    end
    return lieu
end

-- Sous la fleche : la quete, puis quoi y faire.
local function Qui(id, moi, lieu)
    local q = moi.quetes and moi.quetes[id]
    local quoi
    if lieu.entree then
        quoi = string.format(L.GUIDE_ENTER_DUNGEON, lieu.entree)
    elseif q and q.complete == true then
        quoi = string.format(L.GUIDE_DO_TURNIN, lieu.qui or "?")
    elseif q then
        for _, o in ipairs(q.objectifs or {}) do
            if not o.fait then quoi = tostring(o.texte or "") break end
        end
    else
        quoi = string.format(L.GUIDE_DO_PICKUP, lieu.qui or "?")
    end
    return Titre(id, moi) .. (quoi and quoi ~= "" and ("\n|cffb3b3b3" .. quoi .. "|r") or "")
end

-- Les etapes d'une liste de quetes, la plus proche d'abord, puis la plus
-- proche de la precedente.
local function EtapesDeQuetes(ids, moi, etat, compte)
    if #ids == 0 then return nil, "loin" end
    local continent = Continent()
    if not continent then return nil, "loin", OuAller(moi, ids) end
    local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil, "loin", OuAller(moi, ids) end
    local jx, jy = pos:GetXY()
    -- Position cachee par le jeu (valeur secrete) : jamais comparee.
    local secret = _G.issecretvalue
    if not jx or (secret and (secret(jx) or secret(jy))) then return nil, "loin", OuAller(moi, ids) end
    local points = {}
    for _, id in ipairs(ids) do
        local lieu = PointDeQuete(id, moi, continent, jx, jy)
        if lieu then
            table.insert(points, { carte = continent, x = lieu.x, y = lieu.y, cle = "q" .. id, id = id,
                titre = Titre(id, moi), qui = Qui(id, moi, lieu) })
        end
    end
    if #points == 0 then return nil, "loin", OuAller(moi, ids) end
    etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
    local ordre = S().Lieux.Chaine(points, { x = jx, y = jy }, nil, etat.chaine)
    return ordre, nil, nil, compte
end

-- Une quete de la liste est finie : rendue (faite), ou sortie du journal
-- apres y avoir ete vue (rendue sans etre encore notee, ou abandonnee), ou
-- echouee.
local function Finie(id, moi, etat)
    local q = moi.quetes and moi.quetes[id]
    if q then
        etat.vues = type(etat.vues) == "table" and etat.vues or {}
        etat.vues[id] = true
        return q.complete == -1
    end
    if moi.faites and moi.faites[id] then return true end
    return type(etat.vues) == "table" and etat.vues[id] == true
end

local function Reste(ids, moi, etat)
    local reste, fait = {}, 0
    for _, id in ipairs(ids) do
        if Finie(id, moi, etat) then fait = fait + 1 else table.insert(reste, id) end
    end
    return reste, fait
end

local function Copie(ids)
    local t = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        id = tonumber(id)
        if id then table.insert(t, id) end
    end
    table.sort(t)
    return t
end

-- Commun a tous les types : la carte en filigrane au clic, et la fin du
-- guidage qui remet la carte et le suivi a jour.
local function Commun(def)
    def.icone = "Interface\\GossipFrame\\AvailableQuestIcon"
    def.AideClic = function() return L.GUIDE_CLICK end
    def.Evenements = def.Evenements or { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA" }
    def.Clic = function()
        if NS.pageCarte and NS.pageCarte.Filigrane then pcall(NS.pageCarte.Filigrane) end
    end
    def.Fin = function()
        if NS.carte then NS.carte.Invalider() end
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then
            pcall(NS.pageCarte.Filigrane, false)
        end
        if NS.fenetre and NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
        if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    end
    return def
end

local TYPES = {}

-- Les quetes a rendre : l'ensemble suivi est celui des quetes terminees a
-- chaque instant.
TYPES.rendus = Commun({
    Libelle = function() return L.GUIDE_OBJ_TURNIN end,
    Preparer = function(p, etat)
        local moi = Moi()
        if not moi then return false end
        etat.rendues = {}
        for _, q in pairs(moi.quetes or {}) do if q.complete == true then return true end end
        return false, L.GUIDE_TURNIN_NONE
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        etat.rendues = type(etat.rendues) == "table" and etat.rendues or {}
        local ids = {}
        for id, q in pairs(moi.quetes or {}) do
            if q.complete == true then
                table.insert(ids, id)
                etat.rendues[id] = false
            end
        end
        -- Une quete vue terminee et sortie du journal : rendue.
        local fait = 0
        for id, v in pairs(etat.rendues) do
            if not (moi.quetes and moi.quetes[id]) then etat.rendues[id] = true end
            if etat.rendues[id] == true then fait = fait + 1 end
        end
        if #ids == 0 then return nil, "atteint" end
        table.sort(ids)
        return EtapesDeQuetes(ids, moi, etat, { fait = fait, total = fait + #ids })
    end,
})

-- Des quetes precises, figees au clic.
TYPES.quetes = Commun({
    Cle = function(p) return table.concat(Copie(p.ids), ",") end,
    Libelle = function(p)
        local ids = Copie(p.ids)
        if #ids == 1 then return Titre(ids[1], (Moi())) end
        return string.format(L.GUIDE_OBJ_QUESTS, #ids)
    end,
    Preparer = function(p, etat)
        local moi = Moi()
        if not moi then return false end
        p.ids = Copie(p.ids)
        if #p.ids == 0 then return false end
        etat.vues = {}
        local reste = Reste(p.ids, moi, etat)
        return #reste > 0
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        local ids = Copie(p.ids)
        local reste, fait = Reste(ids, moi, etat)
        if #reste == 0 then return nil, "atteint" end
        return EtapesDeQuetes(reste, moi, etat, { fait = fait, total = #ids })
    end,
})

-- Vers un niveau : les quetes du calcul de QuestCore (les terminees si leur
-- XP suffit, sinon la progression), recalculees a chaque niveau pris.
local function Calculer(etat, moi)
    local d = NS.disponibles
    local ids = d and d.EtapesPourNiveau and d.EtapesPourNiveau(moi)
    etat.ids = type(ids) == "table" and Copie(ids) or {}
    etat.pour = tonumber(NS.Appeler(UnitLevel, "player")) or 0
    etat.vues = {}
    for _, id in ipairs(etat.ids) do Finie(id, moi, etat) end
    return #etat.ids > 0
end

TYPES.niveau = Commun({
    Evenements = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA" },
    Cle = function(p) return tostring(tonumber(p.niveau) or 0) end,
    Libelle = function(p) return string.format(L.ROUTE_LEVEL_NAME, tonumber(p.niveau) or 0) end,
    Preparer = function(p, etat)
        local moi = Moi()
        p.niveau = tonumber(p.niveau)
        if not (moi and p.niveau) then return false end
        if (tonumber(NS.Appeler(UnitLevel, "player")) or 0) >= p.niveau then return false end
        if not Calculer(etat, moi) then return false, L.ROUTE_LEVEL_NONE end
        return true
    end,
    Etapes = function(p, etat)
        local moi = Moi()
        if not moi then return nil, "loin" end
        local niveau = tonumber(NS.Appeler(UnitLevel, "player")) or 0
        if niveau >= (tonumber(p.niveau) or 0) then return nil, "atteint" end
        etat.ids = type(etat.ids) == "table" and etat.ids or {}
        local reste, fait = Reste(etat.ids, moi, etat)
        -- Un niveau pris, ou toutes les quetes prevues faites sans l'atteindre :
        -- le calcul repart d'ici.
        if etat.pour ~= niveau or #reste == 0 then
            if not Calculer(etat, moi) then return nil, "inconnu", L.ROUTE_LEVEL_NONE end
            reste, fait = Reste(etat.ids, moi, etat)
            if #reste == 0 then return nil, "inconnu", L.ROUTE_LEVEL_NONE end
        end
        return EtapesDeQuetes(reste, moi, etat, { fait = fait, total = #etat.ids })
    end,
})

-- Un parcours enregistre : seules les etapes faisables maintenant (a
-- prendre, en cours, a rendre) sont visees, la plus proche d'abord.
TYPES.parcours = Commun({
    Cle = function(p) return tostring(p.uid) end,
    Libelle = function(p)
        local _, cle = Moi()
        local pc = cle and NS.parcours.TrouverUid(cle, p.uid)
        return pc and pc.nom or nil
    end,
    Preparer = function(p)
        local _, cle = Moi()
        return cle ~= nil and NS.parcours.TrouverUid(cle, p.uid) ~= nil
    end,
    Reprendre = function(p)
        local _, cle = Moi()
        return cle ~= nil and NS.parcours.TrouverUid(cle, p.uid) ~= nil
    end,
    Etapes = function(p, etat)
        local moi, cle = Moi()
        if not moi then return nil, "loin" end
        local pc = NS.parcours.TrouverUid(cle, p.uid)
        if not pc then return nil, "atteint" end
        local faites, total = NS.parcours.Avancement(moi, pc)
        if total > 0 and faites >= total then return nil, "atteint" end
        local ids, enAttente = {}, 0
        for _, id in ipairs(pc.etapes or {}) do
            local e = NS.parcours.EtatEtape(moi, id)
            if e == "attente" then enAttente = enAttente + 1
            elseif e ~= "faite" then table.insert(ids, id) end
        end
        if #ids == 0 then return nil, "loin", OuAller(moi, pc.etapes) end
        return EtapesDeQuetes(ids, moi, etat, { fait = faites, total = total })
    end,
})

if S() and S().DeclarerObjectifs then S().DeclarerObjectifs("QuestCore", TYPES) end

-- Une fois les sauvegardes chargees : l'ancien etat du guidage, commun au
-- compte, n'a plus cours (l'objectif est garde par personnage par la suite).
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, evenement)
        if evenement ~= "PLAYER_LOGIN" then return end
        local ok, g = pcall(NS.base.ReglagesGeneraux)
        if ok and type(g) == "table" then g.guidage = nil g.ajustementAuto = nil end
    end)
end

-- ---------------------------------------------------------------------------
-- Pour les boutons de QuestCore et les autres add-ons
-- ---------------------------------------------------------------------------

-- Apres un lancement : la carte ne montre plus que l'objectif guide.
local function Apres(lance, trajet)
    if lance then
        if trajet and NS.pageCarte and NS.pageCarte.ModeTrajet then NS.pageCarte.ModeTrajet(true) end
        if NS.carte then NS.carte.Invalider() end
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then pcall(NS.pageCarte.Rendre)
        elseif NS.fenetre and NS.fenetre.Visible() and NS.fenetre.Page() == "carte" then pcall(NS.fenetre.Rendre) end
    end
    if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    return lance
end

function guidage.Lancer(nom, params)
    return Apres(S().LancerObjectif("QuestCore", nom, params), nom ~= "parcours")
end
function guidage.Basculer(nom, params)
    if nom == false then S().Arreter("joueur") return Apres(false) end
    return Apres(S().BasculerObjectif("QuestCore", nom, params), nom ~= "parcours")
end
function guidage.EstActif(nom, params) return S().EstActif("QuestCore", nom, params) end
-- Un guidage de QuestCore, quel qu'il soit.
function guidage.Actif() return S().GuidageActif("QuestCore") end
-- L'objectif QuestCore guide (instance), ou nil.
function guidage.Objectif()
    local a = S().ObjectifActif()
    return (a and a.proprietaire == "QuestCore") and a or nil
end
-- L'uid du parcours guide, ou nil.
function guidage.ParcoursGuide()
    local a = guidage.Objectif()
    return a and a.type == "parcours" and a.params.uid or nil
end
-- Les quetes de l'objectif guide, dans l'ordre vise (pour la carte).
function guidage.Etapes()
    if not guidage.Objectif() then return nil end
    local e = S().EtatGuidage()
    return e and e.etapes
end

_G.QuestCoreAPI = _G.QuestCoreAPI or {}
local api = _G.QuestCoreAPI
api.GuiderRendus = function() return guidage.Lancer("rendus", {}) end
api.GuiderQuetes = function(ids) return guidage.Lancer("quetes", { ids = Copie(ids) }) end
api.GuiderNiveau = function(n) return guidage.Lancer("niveau", { niveau = tonumber(n) }) end
api.GuiderParcours = function(uid) return guidage.Lancer("parcours", { uid = uid }) end
-- Ancien appel : guider les quetes a rendre, ou arreter le guidage de QuestCore.
api.Guider = function(oui)
    if oui == false then
        if guidage.Actif() then S().Arreter("joueur") end
        return false
    end
    return api.GuiderRendus()
end
