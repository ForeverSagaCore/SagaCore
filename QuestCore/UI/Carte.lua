local _, NS = ...

-- Reperes de quetes, pour la page Carte de QuestCore.
--
-- Pour chaque quete en cours du personnage connecte :
--   a rendre      l'icone de quete a rendre du journal, sur celui qui la reprend ;
--   en cours      l'icone de quete en cours du journal, la ou se font les
--                 objectifs (creatures, objets, lieux), jamais pour un objectif
--                 deja rempli.
--
-- Les icones sont celles du journal de quetes du jeu, les memes que dans le
-- suivi. Les reperes sont de simples cadres : aucun modele protege du jeu
-- (celui des reperes de quete bloquait l'add-on).
-- Positions : base QuestieDB, en pourcentage de la carte de la zone.

NS.carte = {}
local carte = NS.carte
local L = NS.L

local TAILLE = 22
local CELLULE = 3          -- deux points a moins de 3 % l'un de l'autre n'en font qu'un
local MAX_PAR_OBJECTIF = 25

local PointsDePrise, Reporter
local versCarte              -- AreaID -> UiMapID, tire de QuestieDB

-- ---------------------------------------------------------------------------
-- Correspondance zone de la base -> carte du jeu
-- ---------------------------------------------------------------------------

local function TableDesCartes()
    if versCarte then return versCarte end
    versCarte = {}
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local prive = support and support.private
    for _, champ in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local brut = prive and prive[champ]
        local t = brut
        if type(brut) == "string" then
            local fn = loadstring(brut)
            local ok, rendu = false, nil
            if fn then ok, rendu = pcall(fn) end
            t = ok and rendu or nil
        end
        if type(t) == "table" then
            for zone, idCarte in pairs(t) do versCarte[zone] = idCarte end
        end
    end
    return versCarte
end

function carte.CarteDeZone(zone)
    local idCarte = TableDesCartes()[zone]
    if idCarte and idCarte > 0 then return idCarte end
    -- Sans Questie : la carte gardee par la base personnelle.
    idCarte = NS.memoire and NS.memoire.Carte and NS.memoire.Carte(zone)
    if idCarte and idCarte > 0 then return idCarte end
    return nil
end

-- Niveaux d'une carte de zone, estimes d'apres ses quetes (QuestieDB) :
-- du 15e au 85e centile de leurs niveaux. Calcule une fois, puis garde.
local niveauxParCarte
function carte.NiveauDeCarte(idCarte)
    if not niveauxParCarte then
        niveauxParCarte = {}
        local base = NS.ref.Base("QuestDB")
        local ids = base and base.GetAllIds and base.GetAllIds() or {}
        local listes = {}
        for _, id in ipairs(ids) do
            local zone = tonumber(NS.ref.Lire("QuestDB", id, "zoneOrSort"))
            local c = zone and zone > 0 and carte.CarteDeZone(zone)
            local niveau = c and tonumber(NS.ref.Lire("QuestDB", id, "questLevel"))
            if niveau and niveau > 0 then
                listes[c] = listes[c] or {}
                table.insert(listes[c], niveau)
            end
        end
        for c, l in pairs(listes) do
            if #l >= 3 then
                table.sort(l)
                niveauxParCarte[c] = { l[math.max(1, math.floor(#l * 0.15 + 0.5))], l[math.max(1, math.floor(#l * 0.85 + 0.5))] }
            end
        end
    end
    local n = niveauxParCarte[idCarte]
    -- Base de Questie pas encore prete : on recalculera au prochain appel.
    if not next(niveauxParCarte) then niveauxParCarte = nil end
    if n then return n[1], n[2] end
    return nil
end

-- ---------------------------------------------------------------------------
-- Points de chaque quete
-- ---------------------------------------------------------------------------

local Lire = function(...) return NS.ref.Lire(...) end

-- Ajoute les apparitions d'une entite ("NpcDB" ou "ObjectDB") a la liste.
local function Apparitions(entite, id, ajouter)
    -- Releve en jeu sur WoW Forever : il passe avant Questie.
    -- Un PNJ fixe (trois places au plus dans Questie) se montre la ou on
    -- l'a vu ; une cible qui apparait partout garde aussi les places Questie.
    local releves = NS.memoire and NS.memoire.Releves and NS.memoire.Releves(entite, id)
    local spawns = Lire(entite, id, "spawns")
    if releves then
        local nom = Lire(entite, id, "name")
        for _, pt in ipairs(releves) do ajouter(pt[1], pt[2], pt[3], nom) end
        local n = 0
        for _, points in pairs(type(spawns) == "table" and spawns or {}) do n = n + (type(points) == "table" and #points or 0) end
        if n <= 3 then return end
    end
    if type(spawns) ~= "table" then return end
    local nom = Lire(entite, id, "name")
    for zone, points in pairs(spawns) do
        local idCarte = carte.CarteDeZone(zone)
        if idCarte and type(points) == "table" then
            for _, pt in ipairs(points) do
                local x, y = tonumber(pt[1]), tonumber(pt[2])
                if x and y and x >= 0 and y >= 0 then ajouter(idCarte, x, y, nom) end
            end
        end
    end
end

-- Objectif du journal deja rempli, reconnu par le nom de ce qu'il demande.
local function Rempli(q, nom)
    if not nom then return false end
    for _, o in ipairs(q.objectifs or {}) do
        if o.fait and type(o.texte) == "string" and string.find(o.texte, nom, 1, true) then return true end
    end
    return false
end

-- Liste de points : { carte, x, y, genre = "rendre"|"objectif", quete, titre, quoi }.
local function PointsDeQuete(id, q)
    local points = {}
    local function Collecteur(genre, quoi, icone)
        local vus, n = {}, 0
        return function(idCarte, x, y, nom)
            if n >= MAX_PAR_OBJECTIF then return end
            local cle = idCarte .. ":" .. math.floor(x / CELLULE) .. ":" .. math.floor(y / CELLULE)
            if vus[cle] then return end
            vus[cle] = true
            n = n + 1
            table.insert(points, { carte = idCarte, x = x / 100, y = y / 100, genre = genre,
                quete = id, titre = q.titre, quoi = quoi or nom, icone = icone })
        end
    end

    if q.complete == true then
        local fin = Lire("QuestDB", id, "finishedBy")
        if type(fin) == "table" then
            for _, pnj in ipairs(fin[1] or {}) do Apparitions("NpcDB", pnj, Collecteur("rendre")) end
            for _, objet in ipairs(fin[2] or {}) do Apparitions("ObjectDB", objet, Collecteur("rendre")) end
        end
        return points
    end
    if q.complete == -1 then return points end

    local objectifs = Lire("QuestDB", id, "objectives")
    if type(objectifs) == "table" then
        for _, o in ipairs(objectifs[1] or {}) do
            local nom = Lire("NpcDB", o[1], "name")
            if not Rempli(q, o[2] or nom) then Apparitions("NpcDB", o[1], Collecteur("objectif", o[2] or nom, "tuer")) end
        end
        for _, o in ipairs(objectifs[2] or {}) do
            local nom = Lire("ObjectDB", o[1], "name")
            if not Rempli(q, o[2] or nom) then Apparitions("ObjectDB", o[1], Collecteur("objectif", o[2] or nom, "objet")) end
        end
        for _, o in ipairs(objectifs[3] or {}) do
            local nomObjet = Lire("ItemDB", o[1], "name")
            if not Rempli(q, nomObjet) then
                local c = Collecteur("objectif", nomObjet, "butin")
                for _, pnj in ipairs(Lire("ItemDB", o[1], "npcDrops") or {}) do Apparitions("NpcDB", pnj, c) end
                for _, objet in ipairs(Lire("ItemDB", o[1], "objectDrops") or {}) do Apparitions("ObjectDB", objet, c) end
            end
        end
    end
    -- Lieu a explorer : { texte, { [zone] = { {x, y} } } }.
    local lieu = Lire("QuestDB", id, "triggerEnd")
    if type(lieu) == "table" and type(lieu[2]) == "table" and not Rempli(q, lieu[1]) then
        local c = Collecteur("objectif", lieu[1], "lieu")
        for zone, pts in pairs(lieu[2]) do
            local idCarte = carte.CarteDeZone(zone)
            for _, pt in ipairs(idCarte and pts or {}) do
                local x, y = tonumber(pt[1]), tonumber(pt[2])
                if x and y then c(idCarte, x, y, lieu[1]) end
            end
        end
    end
    return points
end

-- Ou prendre une quete : ceux qui la donnent.
PointsDePrise = function(id, p)
    local points, vus = {}, {}
    local titre = NS.ref.NomDeQuete(id, p)
    local function ajouter(idCarte, x, y, nom)
        local cle = idCarte .. ":" .. math.floor(x / CELLULE) .. ":" .. math.floor(y / CELLULE)
        if vus[cle] or #points >= MAX_PAR_OBJECTIF then return end
        vus[cle] = true
        table.insert(points, { carte = idCarte, x = x / 100, y = y / 100, genre = "prendre",
            quete = id, titre = titre, quoi = nom })
    end
    local debut = Lire("QuestDB", id, "startedBy")
    if type(debut) == "table" then
        for _, pnj in ipairs(debut[1] or {}) do Apparitions("NpcDB", pnj, ajouter) end
        for _, objet in ipairs(debut[2] or {}) do Apparitions("ObjectDB", objet, ajouter) end
    end
    return points
end

-- Points de toutes les quetes du personnage connecte, gardes jusqu'au
-- prochain releve du journal.
local cache
function carte.Invalider() cache = nil end

local function TousLesPoints()
    if cache then return cache end
    cache = {}
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.PersoParCle(cle)
    -- Etapes des parcours affiches : un numero sur leurs reperes.
    local etapes = {}
    if p and NS.parcours then
        local ok, rendu = pcall(NS.parcours.EtapesSurCarte, cle, p)
        if ok then etapes = rendu else NS.base.NoterIncident("carte, parcours", rendu) end
    end
    local function Marquer(pts, id)
        local e = etapes[id]
        for _, pt in ipairs(pts) do
            if e then
                pt.numero, pt.parcours, pt.idParcours = e.numero, e.parcours, e.idParcours
                pt.attente = e.etat == "attente"
            end
            table.insert(cache, pt)
        end
    end
    for id, q in pairs(p and p.quetes or {}) do
        local ok, pts = pcall(PointsDeQuete, id, q)
        if ok then Marquer(pts, id) else NS.base.NoterIncident("carte, quete " .. tostring(id), pts) end
    end
    -- Etapes a prendre : chez celui qui donne la quete.
    for id, e in pairs(etapes) do
        if e.etat == "prendre" or e.etat == "attente" then
            local ok, pts = pcall(PointsDePrise, id, p)
            if ok then Marquer(pts, id) else NS.base.NoterIncident("carte, prise " .. tostring(id), pts) end
        end
    end
    -- Quetes disponibles (hors parcours), si demande : un ! chez le donneur.
    local options = NS.pageCarte and NS.pageCarte.Reglages and NS.pageCarte.Reglages()
    if p and NS.disponibles and options and options.disponibles then
        local ok, liste = pcall(NS.disponibles.Liste, p)
        for _, d in ipairs(ok and liste or {}) do
            if not d.gris and not etapes[d.id] then
                local okP, pts = pcall(PointsDePrise, d.id, p)
                if okP then
                    for _, pt in ipairs(pts) do
                        pt.dispo = true
                        table.insert(cache, pt)
                    end
                end
            end
        end
    end
    -- Un seul repere par lieu et par sorte : plusieurs quetes chez le meme
    -- donneur (ou sur les memes creatures) ne s'empilent plus. Les autres
    -- titres se lisent au survol. Les etapes numerotees restent toutes.
    local tries, places = {}, {}
    for _, pt in ipairs(cache) do
        if pt.numero then
            table.insert(tries, pt)
        else
            local cle = tostring(pt.carte) .. ":" .. math.floor(pt.x * 100 / CELLULE) .. ":"
                .. math.floor(pt.y * 100 / CELLULE) .. ":" .. tostring(pt.genre) .. ":" .. tostring(pt.icone) .. ":" .. tostring(pt.dispo)
            local deja = places[cle]
            if deja then
                if pt.titre and pt.titre ~= deja.titre then
                    deja.autres = deja.autres or {}
                    local vu = false
                    for _, t in ipairs(deja.autres) do if t == pt.titre then vu = true end end
                    if not vu then table.insert(deja.autres, pt.titre) end
                end
            else
                places[cle] = pt
                table.insert(tries, pt)
            end
        end
    end
    cache = tries
    return cache
end
carte.TousLesPoints = TousLesPoints

-- Points d'une quete : ses objectifs (ou son receveur) si elle est en cours,
-- sinon ceux qui la donnent.
function carte.PointsPour(id, p)
    local q = p and p.quetes and p.quetes[id]
    if q then return PointsDeQuete(id, q) end
    return PointsDePrise(id, p)
end

-- ---------------------------------------------------------------------------
-- Reperes
-- ---------------------------------------------------------------------------

local function Atlas(tex, nom)
    return tex.SetAtlas and pcall(tex.SetAtlas, tex, nom) and tex:GetAtlas() ~= nil
end

local function CreerRepere(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TAILLE, TAILLE)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetPoint("CENTER")
    b.fond:SetSize(TAILLE + 6, TAILLE + 6)
    b.symbole = b:CreateTexture(nil, "ARTWORK")
    b.symbole:SetPoint("CENTER")
    b.symbole:SetSize(TAILLE + 6, TAILLE + 6)
    -- Numero d'etape du parcours, en coin, sur une pastille sombre pour qu'il
    -- se lise sur toutes les cartes.
    b.pastille = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.pastille:SetSize(15, 15)
    b.pastille:SetPoint("CENTER", b, "BOTTOMRIGHT", 3, -1)
    b.pastille:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    b.pastille:SetVertexColor(0, 0, 0, 0.8)
    b.numero = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.numero:SetPoint("CENTER", b.pastille, "CENTER", 0, 0)
    local fichier, _, drapeaux = b.numero:GetFont()
    if fichier then b.numero:SetFont(NS.Police(fichier), 11, "OUTLINE") end
    b.numero:SetDrawLayer("OVERLAY", 2)
    b.pastille:Hide()
    local poser = b.numero.SetText
    b.numero.SetText = function(self, texte)
        poser(self, texte)
        b.pastille:SetShown(texte ~= nil and texte ~= "")
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        local pt = self.point
        if not pt then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(pt.titre or ("#" .. tostring(pt.quete)), 1, 0.82, 0)
        for _, autre in ipairs(pt.autres or {}) do GameTooltip:AddLine(autre, 1, 0.82, 0) end
        if pt.numero then
            GameTooltip:AddLine(string.format(L.MAP_ROUTE_STEP, pt.parcours or "", pt.numero), 1, 1, 1)
        end
        if pt.genre == "rendre" then
            GameTooltip:AddLine(string.format(L.MAP_TURN_IN, pt.quoi or "?"), 0.31, 0.82, 0.41)
        elseif pt.genre == "prendre" then
            GameTooltip:AddLine(string.format(L.MAP_PICK_UP, pt.quoi or "?"), 1, 0.82, 0)
            if pt.attente then GameTooltip:AddLine(L.MAP_NOT_YET, 0.6, 0.6, 0.6) end
            local cle = NS.ClePersonnage()
            local p = cle and NS.base.PersoParCle(cle)
            local xp = NS.ref.XPDeLaBase(pt.quete, p and p.niveau)
            if xp and xp > 0 then GameTooltip:AddLine(string.format(L.REWARD_XP, xp), 1, 1, 1) end
            local niveau = NS.ref.Lire("QuestDB", pt.quete, "questLevel")
            if niveau then GameTooltip:AddLine(string.format(L.LEVEL, niveau), 0.7, 0.7, 0.7) end
        elseif pt.quoi then
            GameTooltip:AddLine(pt.quoi, 1, 1, 1, true)
        end
        local modeTrajet = NS.pageCarte and NS.pageCarte.EnModeTrajet and NS.pageCarte.EnModeTrajet()
        if not modeTrajet then GameTooltip:AddLine(L.MAP_CLICK, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, bouton)
        -- Carte cloisonnee sur un trajet : les etapes se gerent dans la liste a
        -- gauche ; un clic sur un repere ne change pas de page.
        if bouton == "RightButton" then return end
        if NS.pageCarte and NS.pageCarte.EnModeTrajet and NS.pageCarte.EnModeTrajet() then return end
        if self.point and self.point.genre == "prendre" then
            NS.fenetre.OuvrirDisponible(self.point.quete)
        elseif self.point then
            NS.fenetre.OuvrirQuete(NS.ClePersonnage(), self.point.quete)
        end
    end)
    return b
end

-- Icones des objectifs, a la facon de Questie (icones de pfQuest, licence
-- MIT, dans Icons) : sacoche pour le butin, epee pour les creatures a tuer,
-- engrenage pour les objets a utiliser.
local ICONES_OBJECTIF = {
    butin = { "Interface\\AddOns\\QuestCore\\Icons\\loot_mono", 1, 0.82, 0 },
    tuer = { "Interface\\AddOns\\QuestCore\\Icons\\slay_mono", 1, 0.38, 0.32 },
    objet = { "Interface\\AddOns\\QuestCore\\Icons\\object_mono", 0.45, 0.8, 1 },
}

local function Habiller(b, genre, icone, attente)
    local cle = genre .. ":" .. tostring(icone) .. ":" .. tostring(attente)
    if b.habit == cle then return end
    b.habit = cle
    b.genre = genre
    -- Etape pas encore prenable : en gris, en retrait.
    b.symbole:SetDesaturated(attente == true)
    b.fond:SetDesaturated(attente == true)
    b:SetAlpha(attente and 0.6 or 1)
    b.symbole:SetVertexColor(1, 1, 1)
    b.symbole:SetTexCoord(0, 1, 0, 1)
    local mono = genre == "objectif" and ICONES_OBJECTIF[icone or ""]
    if mono then
        b.fond:Hide()
        b.symbole:SetTexture(mono[1])
        b.symbole:SetVertexColor(mono[2], mono[3], mono[4])
        b.symbole:SetSize(TAILLE - 4, TAILLE - 4)
        return
    end
    b.fond:Show()
    if not Atlas(b.fond, "UI-QuestPoi-QuestNumber") then b.fond:SetTexture(nil) end
    if genre == "prendre" then
        -- Le point d'exclamation des quetes a prendre, celui du jeu, seul et
        -- a sa taille (sur le rond, il debordait).
        b.fond:Hide()
        if Atlas(b.symbole, "QuestNormal") then
            b.symbole:SetSize(TAILLE - 2, TAILLE - 2)
        else
            b.symbole:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            b.symbole:SetTexCoord(0, 1, 0, 1)
            b.symbole:SetSize(TAILLE - 6, TAILLE - 6)
        end
        return
    end
    b.symbole:SetSize(TAILLE + 6, TAILLE + 6)
    local nom = (genre == "rendre") and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow"
    if not Atlas(b.symbole, nom) then
        b.symbole:SetTexture(genre == "rendre" and "Interface\\GossipFrame\\ActiveQuestIcon"
            or "Interface\\GossipFrame\\IncompleteQuestIcon")
    end
end

carte.CreerRepere = function(parent) return CreerRepere(parent) end
carte.Habiller = function(b, genre, icone, attente) return Habiller(b, genre, icone, attente) end

local rectangles = {}
local function Rectangle(zone, carteAffichee)
    local cle = zone .. ">" .. carteAffichee
    local r = rectangles[cle]
    if r == nil then
        r = false
        local lecture = NS.Lecture("C_Map.GetMapRectOnMap")
        if lecture then
            local ok, g, d, h, b = pcall(lecture, zone, carteAffichee)
            if ok and tonumber(g) and tonumber(d) and tonumber(h) and tonumber(b) and d > g and b > h then
                r = { g, d, h, b }
            end
        end
        rectangles[cle] = r
    end
    return r or nil
end

-- Position d'un point sur la carte affichee, ou nil s'il n'y est pas.
Reporter = function(pt, idCarte)
    if pt.carte == idCarte then return pt.x, pt.y end
    local r = Rectangle(pt.carte, idCarte)
    if not r then return nil end
    local x = r[1] + pt.x * (r[2] - r[1])
    local y = r[3] + pt.y * (r[4] - r[3])
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

carte.Reporter = function(pt, idCarte) return Reporter(pt, idCarte) end

-- Les reperes ne vont plus sur la carte du monde du jeu : tout passe par la
-- page Carte. Ces deux fonctions restent pour ceux qui les appellent.
function carte.Rendre() end
function carte.Installer() end

-- Pour les autres add-ons de la suite (MapCore) : les reperes de quetes.
_G.QuestCoreAPI = {
    -- Pour la vue d'ensemble de MapCore : le trajet de quetes du personnage
    -- connecte (nom, etapes restantes, total, guide ou non), ou nil.
    Circuit = function()
        local cle = NS.ClePersonnage()
        local moi = cle and NS.base.Perso(cle)
        if not moi or not NS.parcours then return nil end
        for _, pc in ipairs(NS.parcours.Liste(cle)) do
            if pc.genre == "rendu" then
                local reste = 0
                for _, id in ipairs(pc.etapes) do
                    if NS.parcours.EtatEtape(moi, id) ~= "faite" then reste = reste + 1 end
                end
                if reste == 0 then return nil end
                return { nom = pc.nom, reste = reste, total = #pc.etapes,
                    guide = NS.guidage and NS.guidage.Actif() or false }
            end
        end
        return nil
    end,
    Guider = function(oui) if NS.guidage then NS.guidage.Basculer(oui) end end,
    -- Le bandeau d'avancement, pour les autres add-ons de la suite (CraftCore :
    -- projet termine). Memes reglages, meme place que pour les quetes.
    Bandeau = function(titre, detail, terminee, detail2)
        if NS.bandeau and NS.bandeau.Montrer then NS.bandeau.Montrer(titre, detail, terminee, detail2) return true end
        return false
    end,
    Points = function() return carte.TousLesPoints() end,
    Reporter = function(pt, idCarte) return carte.Reporter(pt, idCarte) end,
    CreerRepere = function(parent) return carte.CreerRepere(parent) end,
    Habiller = function(b, genre, icone, attente) return carte.Habiller(b, genre, icone, attente) end,
    NiveauDeCarte = function(idCarte) return carte.NiveauDeCarte(idCarte) end,
    -- Parcours de progression vers le niveau suivant, pour le personnage
    -- connecte, puis ouverture de la page Parcours. Rend le parcours ou nil
    -- et la raison ("rien", "aucune").
    CreerProgression = function()
        local cle = NS.ClePersonnage()
        local p = cle and NS.base.PersoParCle(cle)
        if not p then return nil, "aucune" end
        local pc, raison = NS.disponibles.CreerProgression(cle, p)
        if pc then
            if NS.suivi and NS.suivi.Rendre then pcall(NS.suivi.Rendre) end
            if _G.CoreSuite and _G.CoreSuite.Ouvrir then pcall(_G.CoreSuite.Ouvrir, "QuestCore") end
            NS.fenetre.OuvrirParcours()
        end
        return pc, raison
    end,
}
