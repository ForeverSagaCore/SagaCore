local _, NS = ...

-- Guidage de CraftCore : le catalogue de ses objectifs, declare au moteur de
-- la suite (Core/Suite.lua). Chaque bouton guide un objectif precis :
--   recolte { onglet = vue }         les matieres de l'onglet du suivi ;
--   recolte { objectifs = { cle } }  les matieres de cet objectif (pion) ;
--   recolte { metier = ligne }       les matieres des rangs vises d'un metier ;
--   recolte { tout = true }          tout ce qui manque (raccourci) ;
--   marchand { objet = id }          le marchand le plus proche qui le vend.
-- La recolte ne vise que les matieres que le personnage sait recolter, la
-- zone actuelle d'abord, puis le reste du continent ; elle ne s'arrete que
-- quand plus rien ne manque, ou quand le joueur l'arrete.

NS.guidage = NS.guidage or {}
local guidage = NS.guidage

local function S() return NS.suite or _G.CoreSuite end
local function L() return NS.L or {} end

local function Dire(texte)
    if type(texte) ~= "string" or texte == "" then return end
    if NS.Dire then NS.Dire(texte) end
    if _G.UIErrorsFrame then pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, texte, 1, 0.82, 0) end
end

local function NomDObjet(objet)
    local nom = NS.inventaire and NS.inventaire.NomDObjet and NS.inventaire.NomDObjet(objet)
    return type(nom) == "string" and nom or ("#" .. tostring(objet))
end

-- ---------------------------------------------------------------------------
-- Recolte
-- ---------------------------------------------------------------------------

-- Les objectifs du suivi que vise la source cliquee.
local function ObjectifsVises(p)
    local suivi = NS.suivi
    local ok, tous = pcall(suivi.Objectifs)
    tous = ok and type(tous) == "table" and tous or {}
    if p.onglet then return suivi.DeLOnglet(tous, p.onglet) end
    local rendu = {}
    if p.objectifs then
        local voulus = {}
        for _, c in ipairs(p.objectifs) do voulus[c] = true end
        for _, o in ipairs(tous) do if voulus[o.cle] then table.insert(rendu, o) end end
        return rendu
    end
    if p.metier then
        local ligne = tonumber(p.metier)
        for _, o in ipairs(tous) do
            if o.groupe == "progression" and (o.ligne == ligne or o.ligneMetier == ligne) then table.insert(rendu, o) end
        end
        return rendu
    end
    return tous
end

-- Ce qui manque encore : { [objet] = quantite }.
local function Manques(p)
    local m = {}
    for _, o in ipairs(ObjectifsVises(p)) do
        for _, mat in ipairs(o.matieres or {}) do
            if (mat.manque or 0) > 0 then m[mat.objet] = (m[mat.objet] or 0) + mat.manque end
        end
    end
    return m
end

-- Seulement ce que le personnage sait recolter (herbes, minerais, peche).
local function Recoltables(m)
    local r = {}
    local api = _G.CraftCoreAPI
    for objet, n in pairs(m) do
        local metier = NS.suivi.MetierDeMatiere(objet)
        if metier and api and api.ARecolte and api.ARecolte(metier) then r[objet] = n end
    end
    return r
end

local function Noms(ensemble)
    local noms = {}
    for objet in pairs(ensemble) do table.insert(noms, NomDObjet(objet)) end
    table.sort(noms)
    return table.concat(noms, ", ")
end

-- Une fois par objectif, par zone et par matiere : la base du jeu dit que la
-- matiere pousse dans cette zone, mais rien n'y a encore ete releve.
local function PrevenirZoneVide(etat, voulus, releveZone, zone)
    if not zone then return end
    etat.prevenus = type(etat.prevenus) == "table" and etat.prevenus or {}
    for objet in pairs(voulus) do
        local cle = tostring(zone) .. ":" .. tostring(objet)
        if not releveZone[objet] and not etat.prevenus[cle] then
            local zonesJeu = NS.noeudsJeu and NS.noeudsJeu.Presence and NS.noeudsJeu.Presence(objet)
            if zonesJeu and zonesJeu[zone] then
                etat.prevenus[cle] = true
                local nom = NomDObjet(objet)
                nom = string.lower(string.sub(nom, 1, 1)) .. string.sub(nom, 2)
                Dire(string.format(L().GUIDE_GATHER_ZONE_EMPTY or "%s", nom))
            end
        end
    end
end

local function LibelleRecolte(p, etat)
    local l = L()
    if p.onglet then
        local onglets = { fabrications = l.TRACK_TAB_CRAFTS, progressions = l.TRACK_TAB_PROGRESSIONS, commandes = l.TRACK_TAB_ORDERS }
        return string.format(l.GUIDE_OBJ_GATHER_TAB or "%s", onglets[p.onglet] or tostring(p.onglet))
    end
    if p.objectifs then
        if not etat.nom then
            for _, o in ipairs(ObjectifsVises(p)) do etat.nom = o.titreAnnonce or o.nom break end
        end
        local nom = type(etat.nom) == "string" and etat.nom:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or "?"
        return string.format(l.GUIDE_OBJ_GATHER_GOAL or "%s", nom)
    end
    if p.metier then
        if not etat.nom then
            local fiche = NS.base and NS.base.Personnage and NS.base.Personnage()
            local m = fiche and type(fiche.metiers) == "table" and fiche.metiers[tostring(p.metier)]
            etat.nom = (type(m) == "table" and m.nom) or (NS.recettes and NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(tonumber(p.metier)))
        end
        return string.format(l.GUIDE_OBJ_GATHER_GOAL or "%s", tostring(etat.nom or p.metier))
    end
    return l.GUIDE_OBJ_GATHER_ALL
end

local TYPES = {}

TYPES.recolte = {
    icone = "Interface\\Icons\\INV_Misc_Herb_01",
    AideClic = nil,
    Cle = function(p)
        if p.onglet then return "onglet:" .. tostring(p.onglet) end
        if p.objectifs then return "obj:" .. table.concat(p.objectifs, ",") end
        if p.metier then return "metier:" .. tostring(p.metier) end
        return "tout"
    end,
    Libelle = LibelleRecolte,
    Evenements = { "BAG_UPDATE_DELAYED", "LOOT_CLOSED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" },
    Preparer = function(p, etat)
        local brut = Manques(p)
        if not next(brut) then Dire(L().GUIDE_GATHER_NOTHING) return false end
        if not next(Recoltables(brut)) then Dire(L().GUIDE_GATHER_NO_PROFESSION) return false end
        etat.visites, etat.prevenus, etat.chaine = {}, {}, {}
        return true
    end,
    Reprendre = function(p, etat)
        etat.visites = type(etat.visites) == "table" and etat.visites or {}
        etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
        return true
    end,
    Etapes = function(p, etat)
        local Lx = S().Lieux
        etat.visites = type(etat.visites) == "table" and etat.visites or {}
        etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
        local voulus = Recoltables(Manques(p))
        if not next(voulus) then return nil, "atteint" end
        local ici = Lx.Ici()
        if not (ici and ici.wx) then return nil, "loin" end
        local lieux = NS.suivi.LieuxDe(voulus)
        local releveZone = {}
        for passe = 1, 2 do
            local zone, continent = {}, {}
            for _, l in ipairs(lieux) do
                local z = Lx.ZoneDe(l.carte)
                l.zone = z
                if z == ici.zone then releveZone[l.objet] = true end
                if not etat.visites[l.cle] then
                    local wx, wy, c = Lx.Monde(l.carte, l.x, l.y)
                    if wx and c == ici.continent then
                        l.wx, l.wy = wx, wy
                        table.insert(z == ici.zone and zone or continent, l)
                    end
                end
            end
            if #zone + #continent > 0 then
                PrevenirZoneVide(etat, voulus, releveZone, ici.zone)
                -- D'abord la zone, depuis le personnage ; puis, depuis le
                -- dernier lieu de la zone, les plus proches du continent.
                local ordre = Lx.Chaine(zone, ici, nil, etat.chaine)
                local depuis = ordre[#ordre] or ici
                local suite = Lx.Chaine(continent, depuis, 30)
                for _, l in ipairs(suite) do table.insert(ordre, l) end
                if #zone == 0 then etat.chaine.visee = ordre[1] and ordre[1].cle end
                for _, l in ipairs(ordre) do
                    l.qui = NomDObjet(l.objet)
                    l.titre = l.qui
                end
                -- "Etape X sur Y" : les lieux de la zone de la cible visee.
                local zc, fait, reste = ordre[1].zone, 0, 0
                for _, zv in pairs(etat.visites) do if zv == zc then fait = fait + 1 end end
                for _, l in ipairs(ordre) do if l.zone == zc then reste = reste + 1 end end
                return ordre, nil, nil, { fait = fait, total = fait + reste }
            end
            -- Tout le continent visite : le circuit recommence (les noeuds
            -- repoussent).
            if passe == 1 and next(etat.visites) then etat.visites = {} else break end
        end
        PrevenirZoneVide(etat, voulus, releveZone, ici.zone)
        -- Aucun lieu connu : le guidage reste, il partira au premier releve.
        return nil, "inconnu", string.format(L().GUIDE_GATHER_NONE_CONTINENT or "%s", Noms(voulus))
    end,
    Arrivee = function(p, etat, etape)
        etat.visites = type(etat.visites) == "table" and etat.visites or {}
        if etape and etape.cle then etat.visites[etape.cle] = etape.zone or true end
        return "suivante"
    end,
    Clic = function() if NS.suivi and NS.suivi.Montrer then pcall(NS.suivi.Montrer) end end,
    Fin = function() if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end end,
}

-- ---------------------------------------------------------------------------
-- Marchand : un point, atteint a l'arrivee ; le drapeau de la carte part avec.
-- ---------------------------------------------------------------------------

TYPES.marchand = (function()
    local t = S().TypePoint({ icone = "Interface\\Minimap\\Tracking\\Reagents" })
    t.Cle = function(p) return tostring(p.objet) end
    t.Libelle = function(p) return string.format(L().VENDOR_GUIDE_WHAT or "%s", NomDObjet(p.objet)) end
    t.Preparer = function(p, etat)
        local m = NS.marchands
        local pt = m and m.PlusProche and m.PlusProche(p.objet)
        if not pt then Dire(string.format(L().VENDOR_NONE_HERE or "%s", NomDObjet(p.objet))) return false end
        etat.point = { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.nom }
        return true
    end
    t.Reprendre = function(p, etat) return type(etat.point) == "table" and etat.point.carte ~= nil end
    t.Etapes = function(p, etat)
        local pt = etat.point
        if type(pt) ~= "table" then return nil, "atteint" end
        local quoi = string.format(L().VENDOR_GUIDE_WHAT or "%s", NomDObjet(p.objet))
        return { { carte = pt.carte, x = pt.x, y = pt.y, titre = L().VENDOR_GUIDE_TITLE, guidage = quoi,
            qui = tostring(pt.nom or "?") .. "\n|cffb3b3b3" .. quoi .. "|r", cle = "marchand" } }
    end
    t.Fin = function()
        if NS.marchands and NS.marchands.OterDrapeau then pcall(NS.marchands.OterDrapeau) end
        if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
    end
    return t
end)()

-- ---------------------------------------------------------------------------
-- Maitre de metier : le plus proche du metier bloque a son rang maximum.
-- ---------------------------------------------------------------------------

TYPES.maitreMetier = (function()
    local t = S().TypePoint({ icone = "Interface\\Minimap\\Tracking\\Profession" })
    t.Cle = function(p) return tostring(p.ligne) .. (type(p.cible) == "table" and (":" .. tostring(p.cible.id or p.cible.nom)) or "") end
    t.Libelle = function(p) return string.format(L().RANK_MAX_GUIDE_WHAT or "%s", tostring(p.nom or "?")) end
    t.Preparer = function(p, etat)
        local a = NS.avisRang
        local pt = (type(p.cible) == "table" and p.cible.carte and p.cible)
            or (a and a.MaitrePlusProche and a.MaitrePlusProche(tonumber(p.ligne), tonumber(p.rangMax)))
        if not pt then Dire(L().RANK_MAX_GUIDE_NONE) return false end
        etat.point = { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.nom }
        return true
    end
    t.Reprendre = function(p, etat) return type(etat.point) == "table" and etat.point.carte ~= nil end
    t.Etapes = function(p, etat)
        local pt = etat.point
        if type(pt) ~= "table" then return nil, "atteint" end
        local quoi = t.Libelle(p)
        return { { carte = pt.carte, x = pt.x, y = pt.y, titre = quoi, guidage = quoi,
            qui = tostring(pt.nom or "?") .. "\n|cffb3b3b3" .. quoi .. "|r", cle = "maitreMetier" } }
    end
    return t
end)()

-- ---------------------------------------------------------------------------
-- Service : la banque ou la boite aux lettres la plus proche (lieux de
-- MapCore), pour une etape de la feuille de route.
-- ---------------------------------------------------------------------------

local SERVICES = {
    banque = { icone = "Interface\\Minimap\\Tracking\\Banker", libelle = "ROUTE_GUIDE_BANK" },
    courrier = { icone = "Interface\\Minimap\\Tracking\\Mailbox", libelle = "ROUTE_GUIDE_MAIL" },
}
TYPES.service = (function()
    local t = S().TypePoint({ icone = "Interface\\Minimap\\Tracking\\Mailbox" })
    t.Cle = function(p) return tostring(p.categorie) end
    t.Libelle = function(p) return L()[(SERVICES[p.categorie] or {}).libelle or ""] or tostring(p.categorie) end
    t.Preparer = function(p, etat)
        local api = _G.MapCoreAPI
        local pt = api and api.ServicePlusProche and api.ServicePlusProche(p.categorie)
        if not pt then Dire(L().ROUTE_GUIDE_NONE) return false end
        etat.point = { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.nom }
        return true
    end
    t.Reprendre = function(p, etat) return type(etat.point) == "table" and etat.point.carte ~= nil end
    t.Etapes = function(p, etat)
        local pt = etat.point
        if type(pt) ~= "table" then return nil, "atteint" end
        local quoi = t.Libelle(p)
        return { { carte = pt.carte, x = pt.x, y = pt.y, titre = quoi, guidage = quoi,
            qui = pt.nom and (pt.nom .. "\n|cffb3b3b3" .. quoi .. "|r") or quoi, cle = "service" } }
    end
    return t
end)()

S().DeclarerObjectifs("CraftCore", TYPES)

-- ---------------------------------------------------------------------------
-- Pour les boutons et les autres add-ons
-- ---------------------------------------------------------------------------

function guidage.EstActif(params) return S().EstActif("CraftCore", "recolte", params) end
function guidage.Basculer(params)
    local r = S().BasculerObjectif("CraftCore", "recolte", params)
    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
    return r
end
function guidage.Lancer(params)
    local r = S().LancerObjectif("CraftCore", "recolte", params)
    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
    return r
end
function guidage.MaitreDeMetier(ligne, nom, rangMax, cible)
    local c = type(cible) == "table" and { id = cible.id, carte = cible.carte, x = cible.x, y = cible.y, nom = cible.nom } or nil
    return S().LancerObjectif("CraftCore", "maitreMetier", { ligne = ligne, nom = nom, rangMax = rangMax, cible = c })
end

function guidage.Marchand(objet)
    local r = S().LancerObjectif("CraftCore", "marchand", { objet = objet })
    if r and NS.marchands then
        local etat = S().ObjectifActif() and S().ObjectifActif().etat
        local pt = etat and etat.point
        if pt and NS.marchands.PoserDrapeau then pcall(NS.marchands.PoserDrapeau, pt) end
        if pt then Dire(string.format(L().VENDOR_GUIDING or "%s %s", tostring(pt.nom or "?"), NomDObjet(objet))) end
    end
    return r
end

-- Une etape de la feuille de route : { service = "banque" | "courrier" },
-- { marchand = objet } ou { recolte = params }.
function guidage.Etape(g)
    if type(g) ~= "table" then return nil end
    if g.service then return S().LancerObjectif("CraftCore", "service", { categorie = g.service }) end
    if g.marchand then return guidage.Marchand(g.marchand) end
    if g.recolte then return guidage.Lancer(g.recolte) end
    return nil
end

_G.CraftCoreAPI = _G.CraftCoreAPI or {}
-- Raccourci "Guider la recolte" : toutes les fabrications suivies.
_G.CraftCoreAPI.GuiderRecolte = function() return guidage.Lancer({ tout = true }) end
