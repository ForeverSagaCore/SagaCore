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
-- cours, chez le donneur sinon. Une quete prise et pas finie ne renvoie
-- jamais chez son donneur ni chez son receveur : pour une quete de donjon,
-- pas meme quand ses objectifs sans lieu connu renvoient au receveur. Un
-- point dans une instance n'est jamais vise : a la place, l'entree du donjon
-- (celui de la quete, ou celui de l'instance ou tombe le point).
-- Un point d'objectif deja visite (on y est arrive) ne revient pas tant
-- que la quete n'est pas finie : un objectif a plusieurs lieux (deux puits,
-- trois caisses...) mene au suivant au lieu de rester sur le premier.
local function CleDePoint(id, x, y)
    return tostring(id) .. ":" .. math.floor((x or 0) * 1000) .. ":" .. math.floor((y or 0) * 1000)
end

local function PointDeQuete(id, moi, continent, jx, jy, utilises)
    local meilleur, lieu
    local ok, points = pcall(NS.carte.PointsPour, id, moi)
    local q = moi.quetes and moi.quetes[id]
    local voulu = (q and q.complete == true) and "rendre" or (q and "objectif") or "prendre"
    local enCours = q ~= nil and q.complete ~= true
    local D = NS.donjons
    local donjon = D and D.DeQuete and D.DeQuete(id)
    local EstInstance = NS.carte.EstInstance
    local entreesVues, entrees = {}, {}
    for _, pt in ipairs(ok and points or {}) do
        if EstInstance and pt.carte and EstInstance(pt.carte) then
            local e = NS.carte.EntreeDInstance and NS.carte.EntreeDInstance(pt.carte)
            if e and not entreesVues[e] then entreesVues[e] = true table.insert(entrees, e) end
        elseif pt.genre == voulu and not (enCours and donjon and pt.parReceveur) then
            local x, y = NS.carte.Reporter(pt, continent)
            local deja = voulu == "objectif" and utilises and x and utilises[CleDePoint(id, x, y)]
            if x and not deja then
                local d = (x - jx) ^ 2 + (y - jy) ^ 2
                if not meilleur or d < meilleur then
                    meilleur, lieu = d, { x = x, y = y, qui = pt.quoi, objectif = voulu == "objectif" or nil }
                end
            end
        end
    end
    if lieu then return lieu end
    -- La base ne sait pas ou se font ses objectifs (quete propre au serveur,
    -- par exemple) : le point que le jeu lui-meme montre sur sa carte.
    if q then
        local carte, gx, gy
        local suivant = NS.Lecture("C_QuestLog.GetNextWaypoint")
        if suivant then
            local okW, c, x, y = pcall(suivant, id)
            if okW and type(c) == "number" and type(x) == "number" then carte, gx, gy = c, x, y end
        end
        if not carte then
            local poi = NS.Lecture("QuestPOIGetIconInfo")
            local carteJoueur = NS.Lecture("C_Map.GetBestMapForUnit")
            local okC, c = pcall(carteJoueur or function() end, "player")
            if poi and okC and c then
                local okP, _, x, y = pcall(poi, id)
                if okP and type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then carte, gx, gy = c, x, y end
            end
        end
        if carte and not (_G.issecretvalue and (_G.issecretvalue(gx) or _G.issecretvalue(gy))) then
            local x, y = NS.carte.Reporter({ carte = carte, x = gx, y = gy }, continent)
            if x and not (utilises and utilises[CleDePoint(id, x, y)]) then return { x = x, y = y, qui = nil, objectif = true } end
        end
    end
    -- A defaut : l'entree du donjon. Celui de la quete quand elle est prise
    -- et pas finie (ses objectifs sont dedans) ; sinon celui de l'instance ou
    -- tombent ses points (donneur ou receveur dedans), jamais une entree au
    -- hasard pour un receveur simplement loin.
    local cibles = {}
    if enCours and donjon then
        for _, e in ipairs(donjon.entrees or {}) do table.insert(cibles, { carte = e.carte, x = e.x, y = e.y, nom = donjon.nom }) end
    end
    for _, e in ipairs(entrees) do
        table.insert(cibles, { carte = e.carte, x = e.x, y = e.y, nom = (donjon and donjon.nom) or e.nom })
    end
    for _, e in ipairs(cibles) do
        local x, y = NS.carte.Reporter({ carte = e.carte, x = e.x, y = e.y }, continent)
        -- Entree sur la carte d'une ville ou d'une grotte : par sa zone.
        if not x and S() and S().Lieux and S().Lieux.VersZone then
            local zc, zx, zy = S().Lieux.VersZone(e.carte, e.x, e.y)
            if zc and zc ~= e.carte then x, y = NS.carte.Reporter({ carte = zc, x = zx, y = zy }, continent) end
        end
        if x then
            local dd = (x - jx) ^ 2 + (y - jy) ^ 2
            if not meilleur or dd < meilleur then meilleur, lieu = dd, { x = x, y = y, qui = e.nom, entree = e.nom or "?" } end
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
        -- Un objet qu'aucun monstre ne donne : comment l'obtenir, en bref.
        local a = NS.ref.ObjetsAObtenir and NS.ref.ObjetsAObtenir(moi, id)
        local api = _G.CraftCoreAPI
        if a and a[1] and api and api.ObtenirCourt then
            local ok, court = pcall(api.ObtenirCourt, a[1].objet, a[1].nom, a[1].manque)
            if ok and type(court) == "string" and court ~= "" then quoi = (quoi or "") .. " (" .. court .. ")" end
        end
    else
        quoi = string.format(L.GUIDE_DO_PICKUP, lieu.qui or "?")
        -- Quete grise (bas niveau) : le jeu ne montre pas son point
        -- d'exclamation si son affichage est coupe. On le dit, pour aller
        -- la prendre quand meme.
        local niveau = tonumber(NS.ref.Lire and NS.ref.Lire("QuestDB", id, "questLevel"))
        if niveau and moi.niveau and NS.ref.CouleurDeNiveau then
            local r, v, b = NS.ref.CouleurDeNiveau(niveau, moi.niveau)
            if r == 0.5 and v == 0.5 and b == 0.5 then quoi = quoi .. "  " .. L.GUIDE_LOW_LEVEL end
        end
    end
    return Titre(id, moi) .. (quoi and quoi ~= "" and ("\n|cffb3b3b3" .. quoi .. "|r") or "")
end

local Ailleurs

-- Le continent d'une carte (mapType 2), en remontant ses parents.
local function ContinentDe(carte)
    local info = NS.Lecture("C_Map.GetMapInfo")
    for _ = 1, 6 do
        local i = carte and info and NS.Appeler(info, carte)
        if type(i) ~= "table" then return nil end
        if i.mapType == 2 then return carte end
        carte = i.parentMapID
    end
    return nil
end
local function NomCarte(carte)
    local i = carte and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), carte)
    return type(i) == "table" and i.name or nil
end

-- La premiere quete qui a un lieu sur un autre continent : son point, en
-- coordonnees de ce continent, avec "Aller a : zone (continent)".
Ailleurs = function(ids, moi)
    for _, id in ipairs(ids) do
        local cartes = {}
        local ok, points = pcall(NS.carte.PointsPour, id, moi)
        for _, pt in ipairs(ok and points or {}) do if pt.carte then table.insert(cartes, pt.carte) end end
        local d = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
        for _, e in ipairs(d and d.entrees or {}) do table.insert(cartes, e.carte) end
        for _, pt in ipairs(ok and points or {}) do
            local e = pt.carte and NS.carte.EntreeDInstance and NS.carte.EntreeDInstance(pt.carte)
            if e then table.insert(cartes, e.carte) end
        end
        for _, carte in ipairs(cartes) do
            local continent = ContinentDe(carte)
            local lieu = continent and PointDeQuete(id, moi, continent, 0.5, 0.5)
            if lieu then
                local zone, nomC = NomCarte(carte), NomCarte(continent)
                local ou = zone and (nomC and string.format("%s (%s)", zone, nomC) or zone) or nomC
                return { carte = continent, x = lieu.x, y = lieu.y, cle = "q" .. id, id = id,
                    titre = Titre(id, moi), qui = ou and string.format(L.GUIDE_GO_TO, ou) or Qui(id, moi, lieu) }
            end
        end
    end
    return nil
end

-- Detours : des quetes a rendre ajoutees par le joueur a l'itineraire en
-- cours (petite carte sur la quete). Gardes par personnage, ils s'ajoutent
-- aux etapes de l'objectif guide, quel qu'il soit, et partent quand la quete
-- est rendue, quand le joueur les retire ou quand le guidage s'arrete.
local function Detours(moi)
    if type(moi) ~= "table" then return {} end
    moi.detours = type(moi.detours) == "table" and moi.detours or {}
    return moi.detours
end

-- Les etapes d'une liste de quetes, la plus proche d'abord, puis la plus
-- proche de la precedente.
-- Le compte montre (« Etape X sur Y ») : pour un itineraire, le numero de
-- l'etape visee dans l'itineraire, meme quand une autre etape passe avant
-- parce qu'elle est sur le chemin ; on sait toujours ou l'on en est.
local function Ajuster(ordre, compte)
    if type(compte) == "table" and compte.rangDe and type(ordre) == "table" and ordre[1] and ordre[1].id then
        local r = compte.rangDe(ordre[1].id)
        if r then return { fait = r - 1, total = compte.total } end
    end
    return compte
end

local function EtapesDeQuetes(ids, moi, etat, compte, suite)
    -- Les detours encore a rendre s'ajoutent (une seule fois chacun).
    local d = Detours(moi)
    if next(d) then
        local deja, avec = {}, {}
        for _, id in ipairs(ids) do deja[id] = true table.insert(avec, id) end
        for id in pairs(d) do
            local q = moi.quetes and moi.quetes[id]
            if not q or q.complete ~= true then d[id] = nil
            elseif not deja[id] then table.insert(avec, id) end
        end
        ids = avec
    end
    if #ids == 0 then return nil, "loin" end
    local continent = Continent()
    if not continent then return nil, "loin", OuAller(moi, ids) end
    local pos = NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), continent, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil, "loin", OuAller(moi, ids) end
    local jx, jy = pos:GetXY()
    -- Position cachee par le jeu (valeur secrete) : jamais comparee.
    local secret = _G.issecretvalue
    if not jx or (secret and (secret(jx) or secret(jy))) then return nil, "loin", OuAller(moi, ids) end
    local points, entrees = {}, {}
    etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
    -- Une quete finie (ou sortie du journal) libere ses points visites.
    for cleU in pairs(etat.utilises) do
        local idU = tonumber(cleU:match("^(%d+):"))
        local qU = idU and moi.quetes and moi.quetes[idU]
        if not qU or qU.complete == true then etat.utilises[cleU] = nil end
    end
    for _, id in ipairs(ids) do
        local lieu = PointDeQuete(id, moi, continent, jx, jy, etat.utilises)
        if lieu and lieu.entree then
            -- Plusieurs quetes du meme donjon : une seule etape, son entree.
            if not entrees[lieu.entree] then
                entrees[lieu.entree] = true
                table.insert(points, { carte = continent, x = lieu.x, y = lieu.y, cle = "entree:" .. lieu.entree, id = id,
                    titre = lieu.entree, qui = string.format(L.GUIDE_ENTER_DUNGEON, lieu.entree), entree = lieu.entree })
            end
        elseif lieu then
            local cleP = "q" .. id .. (lieu.objectif and (":" .. CleDePoint(id, lieu.x, lieu.y)) or "")
            local etatQ = NS.parcours.EtatEtape(moi, id)
            -- Passee a la main : ignoree tant que sa quete n'a pas change.
            local sautee = type(etat.sautees) == "table" and etat.sautees[cleP]
            if sautee and sautee ~= etatQ then etat.sautees[cleP] = nil sautee = nil end
            if not sautee then
                table.insert(points, { carte = continent, x = lieu.x, y = lieu.y, cle = cleP, id = id,
                    titre = Titre(id, moi), qui = Qui(id, moi, lieu), objectif = lieu.objectif, etatQuete = etatQ })
            end
        end
    end
    if #points == 0 then
        -- Rien sur ce continent : on vise quand meme la premiere quete sur
        -- son continent (l'add-on d'itineraire sait y mener ; la fleche de la
        -- suite dit ou aller).
        local ailleurs = Ailleurs(ids, moi)
        if ailleurs then return { ailleurs }, nil, nil, Ajuster({ ailleurs }, compte) end
        return nil, "loin", OuAller(moi, ids)
    end
    etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
    local ici = { x = jx, y = jy }
    if suite then
        -- Une suite de quetes, la meme regle pour toutes : d'abord finir ce
        -- qui est commence (quetes de la suite dans le journal : objectifs
        -- ou rendu), la plus proche ; une quete de la suite a prendre n'est
        -- un detour que si elle est sur le chemin (deux fois plus pres que
        -- cette cible). Rien de commence : la plus proche a prendre.
        local P = NS.parcours
        local commences, aPrendre = {}, {}
        for _, pt in ipairs(points) do
            local e = P.EtatEtape(moi, pt.id)
            if e == "cours" or e == "rendre" then table.insert(commences, pt) else table.insert(aPrendre, pt) end
        end
        if #commences > 0 then
            local ordre = S().Lieux.Chaine(commences, ici, nil, etat.chaine)
            local cible = ordre[1]
            local dCible = S().Lieux.Distance(ici, cible)
            local detours = {}
            for _, pt in ipairs(aPrendre) do
                if S().Lieux.Distance(ici, pt) * 2 < dCible then table.insert(detours, pt) end
            end
            if #detours > 0 then
                local avant = S().Lieux.Chaine(detours, ici)
                for k = #avant, 1, -1 do table.insert(ordre, 1, avant[k]) end
            end
            return ordre, nil, nil, Ajuster(ordre, compte)
        end
    end
    local ordre = S().Lieux.Chaine(points, ici, nil, etat.chaine)
    return ordre, nil, nil, Ajuster(ordre, compte)
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
    -- « Suivante » (bouton du guidage) : la cible visee est passee ; elle ne
    -- revient que si l'etat de sa quete change.
    def.Passer = def.Passer or function(_, etat, cible)
        if type(cible) ~= "table" or type(etat) ~= "table" then return end
        if cible.objectif and cible.id then
            etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
            etat.utilises[CleDePoint(cible.id, cible.x, cible.y)] = true
        elseif cible.cle then
            etat.sautees = type(etat.sautees) == "table" and etat.sautees or {}
            etat.sautees[cible.cle] = cible.etatQuete or true
        end
    end
    -- Arrive sur un lieu d'objectif : il est fait, le suivant est vise.
    def.Arrivee = def.Arrivee or function(_, etat, cible)
        if type(cible) == "table" and cible.objectif and cible.id and type(etat) == "table" then
            etat.utilises = type(etat.utilises) == "table" and etat.utilises or {}
            etat.utilises[CleDePoint(cible.id, cible.x, cible.y)] = true
        end
        return "suivante"
    end
    def.Evenements = def.Evenements or { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA" }
    def.Clic = function()
        if S() and S().OuvrirPlanDuDonjon and S().OuvrirPlanDuDonjon() then return end
        if NS.pageCarte and NS.pageCarte.Filigrane then pcall(NS.pageCarte.Filigrane) end
    end
    def.Fin = function(_, _, raison)
        -- Un passage pour rendre des quetes, demande au milieu d'un autre
        -- guidage : une fois tout rendu, le guidage d'avant reprend la ou il
        -- en etait. Arrete a la main : rien ne reprend.
        local reprise = NS.repriseApres
        if reprise and reprise.par == def then
            NS.repriseApres = nil
            if raison == "atteint" and reprise.inst then
                local inst = reprise.inst
                local apres = NS.Lecture and NS.Lecture("C_Timer.After")
                local function Reprendre() pcall(S().LancerObjectif, inst.proprietaire, inst.type, inst.params, inst) end
                if apres then apres(1, Reprendre) else Reprendre() end
            end
        end
        -- Les detours etaient pour cet itineraire : ils partent avec lui.
        local moi = Moi()
        if moi then moi.detours = nil end
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
-- Trajet de donjon : il suit tout seul (ce qui se debloque s'y ajoute) et
-- se guide rubrique par rubrique (NS.donjons.AGuider) : les suites de
-- quetes, puis les quetes a prendre dehors, puis, tout etant pris, l'entree
-- du donjon ; jamais une etape faite ni un donneur de quete deja prise.
local function EtapesDuKit(moi, pc, etat)
    local D = NS.donjons
    local d = D and D.DuKit and D.DuKit(moi, pc)
    if not d then return false end
    D.MettreAJourKit(moi, d, pc)
    local ids, phase = D.AGuider(moi, d, pc)
    local faites, total = NS.parcours.AvancementGestes(moi, pc)
    if #ids == 0 then
        -- Rien a guider maintenant : fini seulement si toutes les etapes du
        -- trajet sont faites ; sinon le guidage reste et dit ou aller.
        local f, t = NS.parcours.Avancement(moi, pc)
        if t == 0 or f >= t then return true, nil, "atteint" end
        return true, nil, "loin", OuAller(moi, pc.etapes)
    end
    -- Nouvelle rubrique : la cible d'avant ne compte plus.
    if etat.phase ~= phase then etat.phase, etat.chaine = phase, {} end
    return true, EtapesDeQuetes(ids, moi, etat, { fait = faites, total = math.max(total, faites + 1) }, true)
end

-- Un itineraire : les quetes a prendre visees a la fois, dans son ordre.
local A_PRENDRE = 4

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
        if pc.genre == "kit" then
            local retour = { EtapesDuKit(moi, pc, etat) }
            if retour[1] then return unpack(retour, 2, 5) end
        end
        local faites, total = NS.parcours.Avancement(moi, pc)
        if total > 0 and faites >= total then return nil, "atteint" end
        -- Le compte affiche, lui, avance a chaque geste (prendre, faire, rendre).
        faites, total = NS.parcours.AvancementGestes(moi, pc)
        -- Ce qui est vise : tout ce qui est commence (objectifs, rendus), et
        -- seulement les prochaines quetes a prendre dans l'ordre de
        -- l'itineraire (jamais une quete de la fin avant celles du debut).
        local ids, prises = {}, 0
        for _, id in ipairs(pc.etapes or {}) do
            local e = NS.parcours.EtatEtape(moi, id)
            if e == "cours" or e == "rendre" then table.insert(ids, id)
            elseif e == "prendre" and prises < A_PRENDRE then prises = prises + 1 table.insert(ids, id) end
        end
        if #ids == 0 then return nil, "loin", OuAller(moi, pc.etapes) end
        local rangs = {}
        for k, id in ipairs(pc.etapes or {}) do rangs[id] = k end
        return EtapesDeQuetes(ids, moi, etat, { fait = faites, total = #(pc.etapes or {}),
            rangDe = function(id) return rangs[id] end }, true)
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

-- Detours : une quete a rendre ajoutee a l'itineraire en cours, ou retiree.
function guidage.EstDetour(id)
    local moi = Moi()
    return moi ~= nil and Detours(moi)[tonumber(id)] == true
end
-- La quete fait-elle deja partie de l'objectif guide (hors detour) ?
function guidage.DansLObjectif(id)
    local a = guidage.Objectif()
    if not a then return false end
    if a.type == "rendus" then return true end
    id = tonumber(id)
    if guidage.EstDetour(id) then return false end
    for _, e in ipairs(guidage.Etapes() or {}) do
        if e.id == id then return true end
    end
    if a.type == "quetes" then
        for _, x in ipairs(a.params.ids or {}) do if tonumber(x) == id then return true end end
    end
    return false
end
function guidage.BasculerDetour(id)
    local moi = Moi()
    id = tonumber(id)
    if not (moi and id and guidage.Objectif()) then return false end
    local d = Detours(moi)
    d[id] = (not d[id]) or nil
    S().Invalider()
    if NS.carte then NS.carte.Invalider() end
    if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
    return d[id] == true
end

_G.QuestCoreAPI = _G.QuestCoreAPI or {}
local api = _G.QuestCoreAPI
api.GuiderRendus = function() return guidage.Lancer("rendus", {}) end
api.GuiderQuetes = function(ids) return guidage.Lancer("quetes", { ids = Copie(ids) }) end
-- Pour le releve de l'hotel des ventes (CraftCore) : les objets que les quetes
-- en cours demandent et qu'aucun monstre ne donne. { objet, nom, manque }.
api.ObjetsAObtenir = function()
    local moi = Moi()
    local res = {}
    for id in pairs(moi and moi.quetes or {}) do
        for _, o in ipairs(NS.ref.ObjetsAObtenir(moi, id)) do table.insert(res, o) end
    end
    return res
end
-- Pour CraftCore : les quetes qui demandent cet objet.
api.QuetesDemandant = function(objet) return NS.ref.QuetesDemandant(objet) end
api.GuiderNiveau = function(n) return guidage.Lancer("niveau", { niveau = tonumber(n) }) end
-- Aller rendre ces quetes, puis reprendre le guidage en cours (s'il y en a
-- un) la ou il en etait.
api.RendreEtReprendre = function(ids)
    local avant = S().ObjectifActif and S().ObjectifActif()
    local lance = guidage.Lancer("quetes", { ids = Copie(ids) })
    if lance and avant then NS.repriseApres = { inst = avant, par = TYPES.quetes } end
    return lance
end
api.GuiderParcours = function(uid) return guidage.Lancer("parcours", { uid = uid }) end
-- Ancien appel : guider les quetes a rendre, ou arreter le guidage de QuestCore.
api.Guider = function(oui)
    if oui == false then
        if guidage.Actif() then S().Arreter("joueur") end
        return false
    end
    return api.GuiderRendus()
end
