local _, NS = ...

-- Lectures du client pour les objets, sous filet. Memes noms que CraftCore,
-- pour que les modules d'equipement repris de lui fonctionnent tels quels.
NS.jeu = NS.jeu or {}
do
    local j = NS.jeu
    j.infoObjet = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    j.infoObjetImmediate = NS.Lecture("C_Item.GetItemInfoInstant", "GetItemInfoInstant")
    j.iconeObjet = NS.Lecture("C_Item.GetItemIconByID", "GetItemIcon")
    j.objetEquipe = NS.Lecture("GetInventoryItemID")
    j.statsObjet = NS.Lecture("C_Item.GetItemStats", "GetItemStats")
end


-- Lecture des objets.
--
-- Le client ne repond sur un objet que s'il l'a deja en memoire. Quand il ne
-- repond pas, on lui demande de le charger et on redemandera plus tard, au
-- lieu d'afficher un trou ou d'inventer une valeur.

NS.objets = {}
local objets = NS.objets

local enAttente = {}

-- Tout ce qu'on sait d'un objet. Les champs absents restent absents.
function objets.Info(identifiant)
    local id = tonumber(identifiant)
    if not id then return nil end
    local j = NS.jeu

    local info = { id = id }
    if j.infoObjet then
        local nom, lien, qualite, niveau = NS.Appeler(j.infoObjet, id)
        if type(nom) == "string" and nom ~= "" then info.nom = nom end
        if type(lien) == "string" and lien ~= "" then info.lien = lien end
        info.qualite = tonumber(qualite)
        info.niveau = tonumber(niveau)
    end
    if j.iconeObjet then info.icone = NS.Appeler(j.iconeObjet, id) end

    if not info.nom then
        -- Pas encore en memoire : on demande, et l'avis de reception fera
        -- redessiner l'ecran.
        local demander = NS.Lecture("C_Item.RequestLoadItemDataByID")
        if demander and not enAttente[id] then
            enAttente[id] = true
            NS.Appeler(demander, id)
        end
        return info
    end

    enAttente[id] = nil
    return info
end

-- Statistiques d'un objet. Le client les rend a partir du lien, pas de
-- l'identifiant : c'est pour cela qu'elles manquaient sur les objets fabriques.
-- Les cles rendues sont des noms de libelles du jeu, on reprend les siens.
function objets.Stats(identifiantOuLien)
    local lecture = NS.jeu.statsObjet
    if not lecture or not identifiantOuLien then return nil end

    -- Le client repond le plus souvent au lien. On l'essaie d'abord, puis
    -- l'identifiant : selon la version, l'un ou l'autre repond.
    local essais = {}
    if type(identifiantOuLien) == "number" then
        local info = objets.Info(identifiantOuLien)
        if info and info.lien then table.insert(essais, info.lien) end
        table.insert(essais, identifiantOuLien)
    else
        table.insert(essais, identifiantOuLien)
    end

    local brut
    for _, cible in ipairs(essais) do
        local reponse = NS.Appeler(lecture, cible)
        if type(reponse) == "table" and next(reponse) ~= nil then
            brut = reponse
            break
        end
    end
    if type(brut) ~= "table" then return nil end
    local propres, vide = {}, true
    for cle, valeur in pairs(brut) do
        local nombre = tonumber(valeur)
        if nombre and nombre ~= 0 then
            propres[cle] = nombre
            vide = false
        end
    end
    if vide then return nil end
    return propres
end

-- Libelle d'une statistique, pris dans les libelles du jeu.
function objets.LibelleDeStat(cle)
    local valeur = _G[cle]
    if type(valeur) == "string" and valeur ~= "" then return valeur end
    return cle
end

-- Ordre d'affichage : l'armure d'abord, puis les caracteristiques, puis le
-- reste par ordre alphabetique, pour que deux objets se lisent pareil.
local PRIORITE = {
    RESISTANCE0_NAME = 1,
    ITEM_MOD_STRENGTH_SHORT = 2,
    ITEM_MOD_AGILITY_SHORT = 3,
    ITEM_MOD_STAMINA_SHORT = 4,
    ITEM_MOD_INTELLECT_SHORT = 5,
    ITEM_MOD_SPIRIT_SHORT = 6,
}

function objets.OrdonnerStats(cles)
    table.sort(cles, function(a, b)
        local pa, pb = PRIORITE[a] or 50, PRIORITE[b] or 50
        if pa == pb then return objets.LibelleDeStat(a) < objets.LibelleDeStat(b) end
        return pa < pb
    end)
    return cles
end

function objets.ObjetsEnAttente()
    local combien = 0
    for _ in pairs(enAttente) do combien = combien + 1 end
    return combien
end

-- Couleur de qualite d'un objet, celle du jeu. Un nom d'objet garde toujours
-- sa couleur de qualite : ce qu'on possede se signale autrement, par la coche
-- et par la colonne d'etat, sinon tout se confondrait.
function objets.CouleurDeQualite(qualite)
    local q = tonumber(qualite)
    if not q then return nil end

    local table_ = _G.ITEM_QUALITY_COLORS
    if type(table_) == "table" and type(table_[q]) == "table" then
        local c = table_[q]
        if c.r then return c.r, c.g, c.b end
    end

    local lecture = NS.Lecture("C_Item.GetItemQualityColor", "GetItemQualityColor")
    if lecture then
        local r, v, b = NS.Appeler(lecture, q)
        if tonumber(r) then return r, v, b end
    end
    return nil
end

-- Couleur du nom d'un objet, sa qualite si le client la donne, blanc sinon.
function objets.CouleurDuNom(identifiant)
    local info = objets.Info(identifiant)
    if info and info.qualite then
        local r, v, b = objets.CouleurDeQualite(info.qualite)
        if r then return r, v, b end
    end
    return 1, 1, 1
end
