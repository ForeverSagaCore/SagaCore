local _, NS = ...

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

-- Tout ce que le client dit d'un objet, infobulle comprise. Sert a constater
-- un contenu qu'on ne connait pas encore, au lieu de le supposer.
-- Deux voies : la lecture structuree du client, et a defaut une infobulle
-- cachee. Patron repris du journal de donjon, qui emploie les deux.
local infobulleCachee

-- L'objet est-il deja en memoire du client ? Lire son infobulle avant qu'il
-- le soit ne rend qu'une ligne d'attente, ce qui ferait conclure a tort.
function objets.EstCharge(identifiant)
    local id = tonumber(identifiant)
    if not id then return false end
    local enCache = NS.Lecture("C_Item.IsItemDataCachedByID")
    if enCache then
        local reponse = NS.Appeler(enCache, id)
        if reponse == false then return false end
        if reponse == true then return true end
    end
    local info = objets.Info(id)
    return (info and info.nom) and true or false
end

function objets.LignesDInfobulle(identifiant)
    local id = tonumber(identifiant)
    if not id then return nil end

    -- Pas encore charge : on demande, et on ne conclut pas. Le rafraichissement
    -- viendra quand le client aura repondu.
    if not objets.EstCharge(id) then
        objets.Info(id)
        return nil, "en attente"
    end

    local parDonnees = NS.Lecture("C_TooltipInfo.GetItemByID")
    if parDonnees then
        local donnees = NS.Appeler(parDonnees, id)
        if type(donnees) == "table" and type(donnees.lines) == "table" then
            local lignes = {}
            for _, ligne in ipairs(donnees.lines) do
                local texte = ligne.leftText
                if type(texte) == "string" and texte ~= "" then
                    local droite = ligne.rightText
                    if type(droite) == "string" and droite ~= "" then
                        texte = texte .. "   |   " .. droite
                    end
                    table.insert(lignes, texte)
                end
            end
            -- Une infobulle reduite a une seule ligne qui n'est meme pas le
            -- nom de l'objet est une ligne d'attente, pas une reponse.
            if #lignes == 1 then
                local nom = (objets.Info(id) or {}).nom
                if not nom or lignes[1] ~= nom then return nil, "en attente" end
            end
            if #lignes > 0 then return lignes, "lecture structurée" end
        end
    end

    if not infobulleCachee then
        local ok, cree = pcall(CreateFrame, "GameTooltip", "CraftCoreScanTooltip", UIParent, "GameTooltipTemplate")
        infobulleCachee = ok and cree or nil
    end
    if not infobulleCachee then return nil end

    infobulleCachee:Hide()
    infobulleCachee:SetOwner(UIParent, "ANCHOR_NONE")
    if infobulleCachee.ClearLines then infobulleCachee:ClearLines() end
    local info = objets.Info(id)
    local cible = (info and info.lien) or id
    local ok = pcall(infobulleCachee.SetHyperlink, infobulleCachee, cible)
    if not ok then return nil end

    local lignes = {}
    for rang = 1, (infobulleCachee:NumLines() or 0) do
        local gauche = _G["CraftCoreScanTooltipTextLeft" .. rang]
        local droite = _G["CraftCoreScanTooltipTextRight" .. rang]
        local texte = gauche and gauche:GetText()
        if type(texte) == "string" and texte ~= "" then
            local td = droite and droite:GetText()
            if type(td) == "string" and td ~= "" then texte = texte .. "   |   " .. td end
            table.insert(lignes, texte)
        end
    end
    infobulleCachee:Hide()
    if #lignes > 0 then return lignes, "infobulle" end
    return nil
end

-- Cherche dans les conteneurs les objets dont le nom contient un mot, et note
-- tout ce que le client en dit. Resultat ecrit dans les donnees enregistrees.
local TROUVES_MAX = 6

function objets.Chercher(mot)
    if type(mot) ~= "string" or mot == "" then return 0 end
    local recherche = string.lower(mot)
    local j = NS.jeu
    if not j.nombreEmplacements or not j.objetDeLEmplacement then return 0 end

    local d = CraftCoreDB
    if type(d) ~= "table" then return 0 end
    d.recherches = d.recherches or {}
    local resultat = { mot = mot, quand = NS.Horodatage(), objets = {} }

    local vus, trouves = {}, 0
    for conteneur = -5, 20 do
        local emplacements = tonumber(NS.Appeler(j.nombreEmplacements, conteneur)) or 0
        for emplacement = 1, emplacements do
            if trouves >= TROUVES_MAX then break end
            local id = tonumber(NS.Appeler(j.objetDeLEmplacement, conteneur, emplacement))
            if id and not vus[id] then
                vus[id] = true
                local info = objets.Info(id)
                local nom = info and info.nom
                if nom and string.find(string.lower(nom), recherche, 1, true) then
                    trouves = trouves + 1
                    local lignes, voie = objets.LignesDInfobulle(id)
                    table.insert(resultat.objets, {
                        id = id,
                        nom = nom,
                        conteneur = conteneur,
                        emplacement = emplacement,
                        niveau = info.niveau,
                        qualite = info.qualite,
                        voie = voie,
                        infobulle = lignes,
                    })
                end
            end
        end
    end

    table.insert(d.recherches, resultat)
    while #d.recherches > 5 do table.remove(d.recherches, 1) end
    return trouves
end
