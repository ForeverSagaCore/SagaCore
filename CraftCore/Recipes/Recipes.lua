local _, NS = ...

-- Catalogue des recettes.
--
-- Le releve en jeu a confirme que ce client donne, pour chaque recette, son
-- nom, l'objet produit, les quantites produites et chaque composant avec sa
-- quantite requise. Rien n'est donc devine ici.
--
-- Le catalogue est commun a tout le compte : une recette est la meme pour tout
-- le monde. Seul l'etat appris est propre a chaque personnage.

NS.recettes = {}
local recettes = NS.recettes

-- Note la forme reelle d'une reponse, une seule fois, pour qu'elle soit
-- constatee plutot que supposee. Meme patron que pour les conteneurs.
local function NoterForme(cle, reponse)
    local dec = NS.base.Decouverte()
    if not dec then return end
    dec.formes = dec.formes or {}
    if dec.formes[cle] then return end
    if type(reponse) ~= "table" then
        dec.formes[cle] = { genre = type(reponse) }
        return
    end
    local champs = {}
    for champ, valeur in pairs(reponse) do
        champs[tostring(champ)] = type(valeur)
    end
    dec.formes[cle] = { genre = "table", champs = champs }
end

local function Catalogue()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.recettes = d.recettes or {}
    return d.recettes
end

-- Toutes les recettes connues du compte (pour retrouver qui produit quoi).
function recettes.Toutes() return Catalogue() or {} end

-- Composants d'une recette, lus dans son plan.
-- Famille d'un objet, telle que le client la rend. Elle servira a reconnaitre
-- les composants qui relevent d'une autre profession. On la releve telle
-- quelle, sans y plaquer de correspondance inventee.
local function FamilleDeLObjet(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil, nil end
    local _, genre, sousGenre = NS.Appeler(lecture, objet)
    if type(genre) ~= "string" then return nil, nil end
    return genre, (type(sousGenre) == "string" and sousGenre or nil)
end

local function LireComposants(plan)
    local liste = {}
    if type(plan) ~= "table" or type(plan.reagentSlotSchematics) ~= "table" then return liste end
    for _, emplacement in ipairs(plan.reagentSlotSchematics) do
        local quantite = tonumber(emplacement.quantityRequired)
        local objet
        if type(emplacement.reagents) == "table" and emplacement.reagents[1] then
            objet = tonumber(emplacement.reagents[1].itemID)
        end
        if objet and quantite and quantite > 0 then
            local genre, sousGenre = FamilleDeLObjet(objet)
            table.insert(liste, { objet = objet, quantite = quantite, genre = genre, sousGenre = sousGenre })
        end
    end
    return liste
end

-- Familles rencontrees, cumulees pour pouvoir constater ce que ce client rend.
function recettes.NoterFamilles()
    local d = CraftCoreDB
    if type(d) ~= "table" then return end
    d.decouverte = d.decouverte or {}
    d.decouverte.familles = d.decouverte.familles or {}
    for _, recette in pairs(d.recettes or {}) do
        for _, composant in ipairs(recette.composants or {}) do
            if composant.genre then
                local cle = composant.genre .. " / " .. tostring(composant.sousGenre or "?")
                d.decouverte.familles[cle] = (d.decouverte.familles[cle] or 0) + 1
            end
        end
    end
end

-- Metier actuellement ouvert, si le client sait le dire. Sinon nil, et les
-- recettes sont enregistrees sans metier plutot qu'avec un metier invente.
local function LigneDeMetierCourante()
    local j = NS.jeu
    if j.infoMetierDeBase then
        local info = NS.Appeler(j.infoMetierDeBase)
        NoterForme("infoMetierDeBase", info)
        if type(info) == "table" then
            local ligne = tonumber(info.professionID) or tonumber(info.skillLineID) or tonumber(info.parentProfessionID)
            if ligne and ligne > 0 then
                -- Le client donne aussi le nom et le rang : on les retient, ils
                -- valent mieux qu'un libelle traduit de notre cote.
                -- Le metier est note sur le personnage qui l'a ouvert : un
                -- herboriste n'a pas a voir les onglets d'un forgeron.
                local fichePerso = NS.base.Personnage()
                if fichePerso then
                    fichePerso.metiers = fichePerso.metiers or {}
                    local sien = fichePerso.metiers[tostring(ligne)] or {}
                    if type(info.professionName) == "string" and info.professionName ~= "" then
                        sien.nom = info.professionName
                    end
                    sien.rang = tonumber(info.skillLevel) or sien.rang
                    sien.rangMax = tonumber(info.maxSkillLevel) or sien.rangMax
                    sien.vuLe = NS.Horodatage()
                    fichePerso.metiers[tostring(ligne)] = sien
                end

                local d = CraftCoreDB
                if type(d) == "table" then
                    d.metiers = d.metiers or {}
                    local fiche = d.metiers[tostring(ligne)] or {}
                    if type(info.professionName) == "string" and info.professionName ~= "" then
                        fiche.nom = info.professionName
                    end
                    fiche.rang = tonumber(info.skillLevel) or fiche.rang
                    fiche.rangMax = tonumber(info.maxSkillLevel) or fiche.rangMax
                    fiche.vuLe = NS.Horodatage()
                    d.metiers[tostring(ligne)] = fiche
                end
                return ligne
            end
        end
    end
    return nil
end

-- Nom du metier tel que le client l'a donne, ou nil s'il ne l'a jamais dit.
function recettes.NomDuMetier(ligne)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.metiers) ~= "table" then return nil end
    local fiche = d.metiers[tostring(ligne)]
    return fiche and fiche.nom or nil
end

function recettes.RangDuMetier(ligne)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.metiers) ~= "table" then return nil end
    local fiche = d.metiers[tostring(ligne)]
    if not fiche or not fiche.rang then return nil end
    return fiche.rang, fiche.rangMax
end

-- Metiers reellement rencontres dans le catalogue, pour qu'aucune recette
-- relevee ne devienne invisible faute d'onglet.
function recettes.MetiersRencontres()
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.recettes) ~= "table" then return {} end
    local vus = {}
    for _, recette in pairs(d.recettes) do
        local ligne = recettes.MetierDe(recette)
        if ligne and ligne > 0 then vus[ligne] = (vus[ligne] or 0) + 1 end
    end
    return vus
end

-- Une recette deja connue n'est jamais appauvrie par une lecture moins
-- complete : on complete, on n'ecrase pas.
local function Enregistrer(id, nouveau)
    local catalogue = Catalogue()
    if not catalogue then return end
    local cle = tostring(id)
    local ancien = catalogue[cle]
    if not ancien then
        catalogue[cle] = nouveau
        return
    end
    for champ, valeur in pairs(nouveau) do
        if valeur ~= nil then
            if champ == "composants" then
                -- On ne remplace la liste que si la nouvelle en contient.
                if type(valeur) == "table" and #valeur > 0 then ancien.composants = valeur end
            else
                ancien[champ] = valeur
            end
        end
    end
end

-- Combien de recettes le jeu sait lister hors fenetre de metier ouverte. On
-- compte seulement : parcourir une liste de plusieurs milliers d'entrees a la
-- connexion ferait tiquer le jeu.
function recettes.Sonder()
    local j = NS.jeu
    if not j.toutesLesRecettes then return nil end
    local liste = NS.Appeler(j.toutesLesRecettes)
    if type(liste) ~= "table" then return nil end
    local dec = NS.base.Decouverte()
    if dec then dec.catalogueCompletDisponible = #liste end
    return #liste
end

-- Comment s'apprend une recette non apprise : le texte du jeu lui-meme, celui
-- que montre la fenetre des metiers (formateur, butin, vendeur, quete...).
-- Lu seulement quand le metier est ouvert, le seul moment ou le jeu le donne.
local function SourceDe(id, info)
    local j = NS.jeu
    if not j.sourceRecette or type(info) ~= "table" or info.learned ~= false then return nil end
    local texte = NS.Appeler(j.sourceRecette, id)
    if type(texte) == "string" and texte ~= "" then return texte end
    return nil
end

-- Ce que le jeu dit de la difficulte d'une recette au rang actuel : couleur
-- (0 orange, 1 jaune, 2 vert, 3 gris), rang ou elle devient grise, points
-- gagnes. Une couleur vue a un rang donne borne le palier jaune : orange au
-- rang r, le jaune commence apres r ; jaune ou plus facile au rang r, il
-- commence au plus tard a r.
local function NoterDifficulte(id, info, rang)
    if type(info) ~= "table" then return end
    local catalogue = Catalogue()
    local recette = catalogue and catalogue[tostring(id)]
    if not recette then return end
    local gris = tonumber(info.maxTrivialLevel)
    if gris and gris > 0 then recette.gris = gris end
    local ups = tonumber(info.numSkillUps)
    if ups and ups > 0 then recette.points = ups end
    local couleur = tonumber(info.relativeDifficulty)
    if couleur and rang then
        if couleur == 0 then
            recette.jauneMin = math.max(recette.jauneMin or 0, rang + 1)
        elseif couleur >= 1 then
            recette.jauneMax = math.min(recette.jauneMax or 9999, rang)
        end
    end
end

-- Au dela de cette borne, on ne parcourt pas d'un seul coup : la lecture d'un
-- plan de recette n'est pas gratuite.
local MAX_PAR_PASSAGE = 400

-- Releve. `origine` dit d'ou vient la lecture, pour que la date affichee ait un
-- sens. Renvoie le nombre de recettes vues, ou nil si rien n'a repondu.
function recettes.Relever(origine)
    local j = NS.jeu
    if not j.infoRecette or not j.planRecette then return nil end

    -- Deux listes, et elles ne disent pas la meme chose. La liste filtree ne
    -- contient que ce que le personnage a appris, mais on sait de quel metier
    -- il s'agit. La liste complete contient aussi le non appris, mais sans
    -- dire a quel metier chaque recette appartient.
    local identifiants, complete
    if j.recettesFiltrees then
        local liste = NS.Appeler(j.recettesFiltrees)
        if type(liste) == "table" and #liste > 0 then identifiants = liste end
    end
    if j.toutesLesRecettes then
        local liste = NS.Appeler(j.toutesLesRecettes)
        if type(liste) == "table" and #liste > 0 then
            complete = liste
            local dec = NS.base.Decouverte()
            if dec then dec.catalogueCompletDisponible = #liste end
        end
    end
    if not identifiants then identifiants = complete end
    if not identifiants then return nil end

    local ligneDeMetier = LigneDeMetierCourante()
    local fiche = NS.base.Personnage()
    if fiche then fiche.recettesApprises = fiche.recettesApprises or {} end
    local rangActuel = fiche and type(fiche.metiers) == "table" and ligneDeMetier
        and fiche.metiers[tostring(ligneDeMetier)] and fiche.metiers[tostring(ligneDeMetier)].rang

    local vues = 0
    local borne = math.min(#identifiants, MAX_PAR_PASSAGE)
    if #identifiants > borne then
        local dec = NS.base.Decouverte()
        if dec then dec.releveBorne = #identifiants end
    end
    for rang = 1, borne do
        local id = identifiants[rang]
        local info = NS.Appeler(j.infoRecette, id)
        NoterForme("infoRecette", info)
        if type(info) == "table" then
            local plan = NS.Appeler(j.planRecette, id, false)
            NoterForme("planRecette", plan)
            local composants = LireComposants(plan)

            Enregistrer(id, {
                nom = info.name,
                metier = ligneDeMetier,
                categorie = tonumber(info.categoryID),
                objetProduit = type(plan) == "table" and tonumber(plan.outputItemID) or nil,
                quantiteMin = type(plan) == "table" and tonumber(plan.quantityMin) or nil,
                quantiteMax = type(plan) == "table" and tonumber(plan.quantityMax) or nil,
                composants = composants,
                vueLe = NS.Horodatage(),
                origine = origine,
                source = SourceDe(id, info),
            })

            if fiche and info.learned ~= nil then
                fiche.recettesApprises[tostring(id)] = info.learned and true or nil
            end
            if info.learned then NoterDifficulte(id, info, rangActuel) end
            vues = vues + 1
        end
    end

    -- Les recettes que seule la liste complete connait sont enregistrees sans
    -- metier : leur attribuer celui de la fenetre ouverte serait faux.
    if complete and complete ~= identifiants then
        local deja = {}
        for _, id in ipairs(identifiants) do deja[id] = true end
        local ajoutees = 0
        for _, id in ipairs(complete) do
            if not deja[id] and ajoutees < MAX_PAR_PASSAGE then
                local info = NS.Appeler(j.infoRecette, id)
                if type(info) == "table" then
                    local plan = NS.Appeler(j.planRecette, id, false)
                    Enregistrer(id, {
                        nom = info.name,
                        categorie = tonumber(info.categoryID),
                        objetProduit = type(plan) == "table" and tonumber(plan.outputItemID) or nil,
                        quantiteMin = type(plan) == "table" and tonumber(plan.quantityMin) or nil,
                        quantiteMax = type(plan) == "table" and tonumber(plan.quantityMax) or nil,
                        composants = LireComposants(plan),
                        vueLe = NS.Horodatage(),
                        origine = "liste complète",
                        source = SourceDe(id, info),
                    })
                    if fiche and info.learned ~= nil then
                        fiche.recettesApprises[tostring(id)] = info.learned and true or nil
                    end
                    -- Une recette apprise peut n'etre que dans la liste complete
                    -- (filtre de la fenetre du metier) : sa couleur compte aussi.
                    if info.learned then NoterDifficulte(id, info, rangActuel) end
                    ajoutees = ajoutees + 1
                    vues = vues + 1
                end
            end
        end
    end

    local d = CraftCoreDB
    if type(d) == "table" then
        d.recettesReleveLe = NS.Horodatage()
    end
    recettes.ReleverLesCategoriesDuMetier(ligneDeMetier)
    recettes.ApprendreLesCategories()
    recettes.NoterFamilles()
    return vues
end

-- Recettes connues du catalogue, pour un metier donne. Si le client n'a jamais
-- su dire a quel metier appartient une recette, elles sont toutes rendues
-- plutot qu'aucune.
function recettes.Pour(ligneDeMetier)
    local catalogue = Catalogue()
    if not catalogue then return {}, false end
    local liste = {}
    local metierConnu = false
    for cle, recette in pairs(catalogue) do
        if recettes.MetierDe(recette) then metierConnu = true end
    end
    for cle, recette in pairs(catalogue) do
        if (not metierConnu) or (not ligneDeMetier) or recettes.MetierDe(recette) == ligneDeMetier then
            local copie = recette
            copie.id = tonumber(cle) or cle
            table.insert(liste, copie)
        end
    end
    table.sort(liste, function(a, b)
        local na, nb = a.nom or tostring(a.id), b.nom or tostring(b.id)
        if na == nb then return tostring(a.id) < tostring(b.id) end
        return na < nb
    end)
    return liste, metierConnu
end

-- Nature de la source, d'apres les mots du jeu lui-meme (ses chaines de
-- source, dans la langue du client) : rien de code en dur dans une langue.
-- Rend la cle d'un libelle court, ou nil si rien ne correspond.
local NATURES = {
    { globale = "TRAINER", cle = "RECIPES_HOW_TRAINER" },
    { globale = "BATTLE_PET_SOURCE_1", cle = "RECIPES_HOW_DROP" },
    { globale = "BATTLE_PET_SOURCE_3", cle = "RECIPES_HOW_VENDOR" },
    { globale = "BATTLE_PET_SOURCE_2", cle = "RECIPES_HOW_QUEST" },
    { globale = "BATTLE_PET_SOURCE_4", cle = "RECIPES_HOW_CRAFTED" },
    { globale = "BATTLE_PET_SOURCE_11", cle = "RECIPES_HOW_DISCOVERY" },
    { globale = "BATTLE_PET_SOURCE_6", cle = "RECIPES_HOW_ACHIEVEMENT" },
    { globale = "BATTLE_PET_SOURCE_7", cle = "RECIPES_HOW_EVENT" },
}

local function SansCodes(texte)
    texte = string.gsub(texte, "|c%x%x%x%x%x%x%x%x", "")
    texte = string.gsub(texte, "|cn[^:]*:", "")
    texte = string.gsub(texte, "|r", "")
    texte = string.gsub(texte, "|T.-|t", "")
    return texte
end

function recettes.NatureDeLaSource(source)
    if type(source) ~= "string" then return nil end
    local propre = string.lower(SansCodes(source))
    for _, nature in ipairs(NATURES) do
        local mot = _G[nature.globale]
        if type(mot) == "string" and mot ~= "" and string.find(propre, string.lower(mot), 1, true) then
            return nature.cle
        end
    end
    return nil
end

-- Texte de la source, sans les codes de couleur, ligne par ligne.
function recettes.LignesDeSource(source)
    local lignes = {}
    if type(source) ~= "string" then return lignes end
    local texte = string.gsub(SansCodes(source), "|n", "\n")
    for ligne in string.gmatch(texte, "[^\n]+") do
        ligne = string.gsub(ligne, "^%s+", "")
        if ligne ~= "" then table.insert(lignes, ligne) end
    end
    return lignes
end

function recettes.EstApprise(id)
    local fiche = NS.base.FicheAffichee()
    if not fiche or type(fiche.recettesApprises) ~= "table" then return false end
    return fiche.recettesApprises[tostring(id)] == true
end

-- Ce qui manque pour une recette, et si elle est realisable tout de suite.
-- `possede` compte tout ce que le compte detient, banque comprise.
-- `sousLaMain` ne compte que ce que le personnage connecte peut atteindre.
function recettes.Manques(recette)
    local manques = {}
    local realisableMaintenant = true
    for _, composant in ipairs(recette.composants or {}) do
        local possede = NS.inventaire.TotalPossede(composant.objet)
        local sousLaMain = NS.inventaire.DisponibleDansLesSacs(composant.objet)
        if sousLaMain < composant.quantite then realisableMaintenant = false end
        if possede < composant.quantite then
            table.insert(manques, {
                objet = composant.objet,
                manque = composant.quantite - possede,
            })
        end
    end
    if #(recette.composants or {}) == 0 then
        -- Aucun composant connu : on ne peut rien affirmer.
        return nil, false
    end
    return manques, realisableMaintenant
end

-- Combien d'exemplaires sont fabricables avec ce qui est possede, banque
-- comprise. Repond 0 si un composant manque, et nil si les composants ne sont
-- pas connus, ce qui n'est pas la meme chose que zero.
function recettes.CombienFabricables(recette)
    local composants = recette.composants
    if type(composants) ~= "table" or #composants == 0 then return nil end
    local possible
    for _, composant in ipairs(composants) do
        if not composant.quantite or composant.quantite <= 0 then return nil end
        local possede = NS.inventaire.TotalPossede(composant.objet)
        local fois = math.floor(possede / composant.quantite)
        if possible == nil or fois < possible then possible = fois end
    end
    return possible or 0
end

-- Objets lies a un metier : ceux qu'il consomme et ceux qu'il produit. Rien
-- d'autre, et surtout aucune famille devinee.
function recettes.ObjetsDuMetier(ligneDeMetier)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.recettes) ~= "table" then return nil end
    if not ligneDeMetier then return nil end

    local lies = {}
    local trouve = false
    for _, recette in pairs(d.recettes) do
        if recettes.MetierDe(recette) == ligneDeMetier then
            trouve = true
            if recette.objetProduit then lies[tonumber(recette.objetProduit)] = true end
            for _, composant in ipairs(recette.composants or {}) do
                if composant.objet then lies[tonumber(composant.objet)] = true end
            end
        end
    end
    if not trouve then return nil end
    return lies
end

-- Correspondance categorie vers metier.
--
-- Elle n'est jamais devinee : elle s'apprend des recettes dont le client a
-- deja dit le metier, et des categories que le client declare pour le metier
-- ouvert quand il sait les donner. Une categorie inconnue reste inconnue.

local function TableDesCategories()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.categoriesParMetier = d.categoriesParMetier or {}
    return d.categoriesParMetier
end

-- Apprend depuis les recettes dont le metier est connu.
function recettes.ApprendreLesCategories()
    local table_ = TableDesCategories()
    local d = CraftCoreDB
    if not table_ or type(d.recettes) ~= "table" then return 0 end
    local appris = 0
    for _, recette in pairs(d.recettes) do
        local metier, categorie = tonumber(recette.metier), tonumber(recette.categorie)
        if metier and metier > 0 and categorie then
            if table_[tostring(categorie)] == nil then
                table_[tostring(categorie)] = metier
                appris = appris + 1
            end
        end
    end
    return appris
end

-- Demande au client les categories du metier ouvert, quand il sait les donner.
function recettes.ReleverLesCategoriesDuMetier(ligneDeMetier)
    local j = NS.jeu
    if not ligneDeMetier or not j.categoriesDuMetier then return 0 end
    local liste = NS.Appeler(j.categoriesDuMetier)
    if type(liste) ~= "table" then return 0 end
    local table_ = TableDesCategories()
    if not table_ then return 0 end
    local appris = 0
    for _, categorie in ipairs(liste) do
        local id = tonumber(categorie)
        if id and table_[tostring(id)] == nil then
            table_[tostring(id)] = ligneDeMetier
            appris = appris + 1
        end
    end
    return appris
end

-- Metier d'une recette : celui que le client a dit, sinon celui que sa
-- categorie permet de deduire, sinon rien.
function recettes.MetierDe(recette)
    local metier = tonumber(recette.metier)
    if metier and metier > 0 then return metier end
    local table_ = TableDesCategories()
    local categorie = tonumber(recette.categorie)
    if table_ and categorie then
        local deduit = table_[tostring(categorie)]
        if deduit then return tonumber(deduit) end
    end
    return nil
end

-- Ce que le client dit d'une recette non apprise. On releve pour constater si
-- la source d'apprentissage y figure, avant d'afficher quoi que ce soit.
-- Borne a quelques recettes : lire une infobulle n'est pas gratuit.
local SONDAGES_MAX = 4

function recettes.SonderDesNonApprises()
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.recettes) ~= "table" then return 0 end
    d.decouverte = d.decouverte or {}
    -- Un sondage qui n'a rien obtenu ne compte pas : on recommencera quand le
    -- client aura charge les objets.
    if d.decouverte.sourcesSondees and d.decouverte.sourcesCompletes then return 0 end

    local j = NS.jeu
    local sondages = {}
    local faits = 0
    for cle, recette in pairs(d.recettes) do
        if faits >= SONDAGES_MAX then break end
        if not recettes.EstApprise(cle) then
            local entree = { id = tonumber(cle), nom = recette.nom }

            -- Le lien de la recette, s'il existe.
            if j.lienRecette then
                local lien = NS.Appeler(j.lienRecette, tonumber(cle))
                if type(lien) == "string" and lien ~= "" then
                    entree.lien = lien
                    local parLien = NS.Lecture("C_TooltipInfo.GetHyperlink")
                    -- Meme garde que partout ailleurs : sans l objet en memoire,
                    -- le client ne rend qu une ligne d attente.
                    if parLien and NS.objets.EstCharge(recette.objetProduit) then
                        local donnees = NS.Appeler(parLien, lien)
                        if type(donnees) == "table" and type(donnees.lines) == "table" then
                            entree.infobulleRecette = {}
                            for _, ligne in ipairs(donnees.lines) do
                                if type(ligne.leftText) == "string" and ligne.leftText ~= "" then
                                    table.insert(entree.infobulleRecette, ligne.leftText)
                                end
                            end
                        end
                    end
                end
            end

            -- L'objet produit, dont l'infobulle mentionne parfois la source.
            if recette.objetProduit and NS.objets.LignesDInfobulle then
                entree.infobulleObjet = NS.objets.LignesDInfobulle(recette.objetProduit)
            end

            table.insert(sondages, entree)
            faits = faits + 1
        end
    end

    local complet = false
    for _, entree in ipairs(sondages) do
        if entree.infobulleRecette or entree.infobulleObjet then complet = true end
    end
    d.decouverte.sourcesSondees = sondages
    d.decouverte.sourcesCompletes = complet or nil
    return faits
end

-- Metiers du personnage connecte, ceux dont il a ouvert la fenetre. Vide tant
-- qu'il n'en a ouvert aucun : on ne suppose pas ses metiers.
-- Niveau de chaque metier du personnage connecte, sans ouvrir les metiers.
-- Le jeu donne le niveau a tout moment ; seules les recettes demandent la
-- fenetre du metier. Deux lectures, selon ce que le client offre :
--   GetProfessions + GetProfessionInfo : identifiant, nom et niveau ;
--   GetSkillLineInfo : nom et niveau seulement, rapproche par le nom d'un
--   metier deja connu, jamais d'un identifiant invente.
function recettes.ReleverNiveaux()
    local fiche = NS.base.Personnage()
    if not fiche then return 0 end
    fiche.metiers = fiche.metiers or {}
    local notes = 0

    local function Noter(ligne, nom, rang, rangMax)
        rang, rangMax = tonumber(rang), tonumber(rangMax)
        if not ligne or not rang then return end
        local sien = fiche.metiers[tostring(ligne)] or {}
        if type(nom) == "string" and nom ~= "" then sien.nom = nom end
        sien.rang, sien.rangMax = rang, rangMax or sien.rangMax
        sien.niveauLuLe = NS.Horodatage()
        fiche.metiers[tostring(ligne)] = sien
        notes = notes + 1
    end

    local liste = NS.Lecture("GetProfessions")
    local info = NS.Lecture("GetProfessionInfo")
    if liste and info then
        local ok, a, b, c, d, e, f = pcall(liste)
        if ok then
            for _, index in pairs({ a, b, c, d, e, f }) do
                local okI, nom, _, rang, rangMax, _, _, ligne = pcall(info, index)
                if okI then Noter(tonumber(ligne), nom, rang, rangMax) end
            end
        end
        if notes > 0 then return notes end
    end

    local nombre = NS.Lecture("GetNumSkillLines")
    local ligneInfo = NS.Lecture("GetSkillLineInfo")
    if nombre and ligneInfo then
        local parNom = {}
        for cle, sien in pairs(fiche.metiers) do
            if type(sien) == "table" and sien.nom then parNom[sien.nom] = tonumber(cle) end
        end
        local ok, total = pcall(nombre)
        for i = 1, (ok and tonumber(total)) or 0 do
            local okI, nom, enTete, _, rang, _, _, rangMax = pcall(ligneInfo, i)
            if okI and not enTete and parNom[nom] then Noter(parNom[nom], nom, rang, rangMax) end
        end
    end
    return notes
end

-- Libelle d'un metier avec son niveau, pour les onglets et les infobulles.
-- Sans niveau connu, le nom seul.
function recettes.LibelleAvecNiveau(nom, rang, rangMax)
    if not rang then return nom or "" end
    if rangMax and rangMax > 0 then
        return string.format(NS.L.PROF_LEVEL, nom or "", rang, rangMax)
    end
    return string.format(NS.L.PROF_LEVEL_NOMAX, nom or "", rang)
end

function recettes.MetiersDuPersonnage()
    local fiche = NS.base.FicheAffichee()
    if not fiche or type(fiche.metiers) ~= "table" then return {} end
    local liste = {}
    for cle, sien in pairs(fiche.metiers) do
        local ligne = tonumber(cle)
        if ligne and ligne > 0 then
            table.insert(liste, { ligne = ligne, nom = sien.nom, rang = sien.rang, rangMax = sien.rangMax })
        end
    end
    -- Toujours le meme ordre, pour tous les personnages : les metiers
    -- principaux d'abord (par nom), puis cuisine, peche et secourisme.
    local SECONDAIRES = { [185] = 1, [356] = 2, [129] = 3 }
    table.sort(liste, function(a, b)
        local sa, sb = SECONDAIRES[tonumber(a.ligne) or 0] or 0, SECONDAIRES[tonumber(b.ligne) or 0] or 0
        if sa ~= sb then return sa < sb end
        return (a.nom or "") < (b.nom or "")
    end)
    return liste
end

-- Combien d'exemplaires avec ce que le personnage a reellement sous la main.
-- Distinct du compte total : ce qui dort chez un autre personnage ne se
-- fabrique pas tant qu'on ne l'a pas rapatrie.
function recettes.CombienFabricablesAPortee(recette)
    local composants = recette.composants
    if type(composants) ~= "table" or #composants == 0 then return nil end
    local possible
    for _, composant in ipairs(composants) do
        if not composant.quantite or composant.quantite <= 0 then return nil end
        local possede = NS.inventaire.APortee(composant.objet)
        local fois = math.floor(possede / composant.quantite)
        if possible == nil or fois < possible then possible = fois end
    end
    return possible or 0
end


-- ===========================================================================
-- Comment s'apprend une recette non apprise
-- ===========================================================================
--
-- Deux sources, dans cet ordre :
--   1. ce que le jeu dit lui-meme, releve a l'ouverture du metier ;
--   2. la base de donnees du jeu, extraite de QuestieDB pour WoW Forever (les
--      plans, patrons, formules et recettes, avec leurs vendeurs, ce qui les
--      laisse tomber et les quetes qui les donnent). Les noms sont ceux du
--      client francais, les zones sont traduites par le jeu au moment de
--      l'affichage.
-- Une recette sans plan connu s'apprend en general chez le formateur.
-- Donnees dans Recipes/Sources.lua.

local SOURCES = NS.donnees.SOURCES

local function Cle(texte)
    if type(texte) ~= "string" then return nil end
    texte = string.lower(texte)
    texte = string.gsub(texte, "\226\128\153", "'")
    texte = string.gsub(texte, "\194\160", " ")
    return texte
end

local function Zone(id)
    if not id or id == 0 then return nil end
    local lecture = NS.Lecture("C_Map.GetAreaInfo")
    if not lecture then return nil end
    local ok, nom = pcall(lecture, id)
    if ok and type(nom) == "string" and nom ~= "" then return nom end
    return nil
end

local function AvecZone(entree)
    local nom, zone = entree[1], Zone(entree[2])
    return zone and (nom .. " (" .. zone .. ")") or nom
end

-- Rend la cle du libelle court et les lignes a montrer au survol.
function recettes.CommentApprendre(recette)
    local L = NS.L
    if type(recette) ~= "table" then return nil, {} end
    if recette.source then
        local lignes = recettes.LignesDeSource(recette.source)
        if #lignes > 0 then return recettes.NatureDeLaSource(recette.source), lignes end
    end
    local donnee = SOURCES[Cle(recette.nom) or ""]
    if not donnee and recette.objetProduit then
        local info = NS.objets.Info(recette.objetProduit)
        donnee = info and SOURCES[Cle(info.nom) or ""]
    end
    if not donnee then
        return "RECIPES_HOW_TRAINER", { L.RECIPES_HOW_TRAINER_GUESS }
    end
    local lignes, nature = {}, nil
    for _, v in ipairs(donnee.v or {}) do
        table.insert(lignes, string.format(L.RECIPES_SRC_VENDOR, AvecZone(v)))
        nature = nature or "RECIPES_HOW_VENDOR"
    end
    for _, q in ipairs(donnee.q or {}) do
        table.insert(lignes, string.format(L.RECIPES_SRC_QUEST, q))
        nature = nature or "RECIPES_HOW_QUEST"
    end
    if donnee.d then
        local noms = {}
        for rang, d in ipairs(donnee.d) do
            if rang > 4 then break end
            table.insert(noms, AvecZone(d))
        end
        table.insert(lignes, string.format(L.RECIPES_SRC_DROP, table.concat(noms, ", ")))
        nature = nature or "RECIPES_HOW_DROP"
    end
    if donnee.o then
        table.insert(lignes, L.RECIPES_SRC_WORLD)
        nature = nature or "RECIPES_HOW_DROP"
    end
    table.insert(lignes, L.RECIPES_SRC_ORIGIN)
    return nature, lignes
end


-- ===========================================================================
-- Progression d'un metier
-- ===========================================================================
--
-- Simule la montee d'un metier, recette par recette, avec ce que possedent
-- tous les personnages du meme camp. Seules comptent les recettes apprises
-- par le personnage affiche et oranges au rang simule : elles font gagner un
-- point a coup sur. A chaque pas, on prend celle qui consomme le moins de
-- composants de recolte, puis celle qui cessera la premiere d'etre orange.
--
-- Les composants vendus partout par les marchands (epices, fioles, fils,
-- teintures, flux...) ne limitent rien : ils sont comptes a part, a acheter.
-- Liste tiree de QuestieDB : les objets vendus par au moins vingt marchands.
--
-- Le palier orange/jaune n'est pas donne par le jeu pour les rangs futurs.
-- Il est estime : le jeu donne le rang ou la recette devient grise, et le
-- jaune commence en general quarante points plus tot. Chaque ouverture du
-- metier recale l'estimation sur les couleurs reellement vues.

local VENDUS_PARTOUT = NS.donnees.VENDUS_PARTOUT

local CHANCE_MINIMUM = 0.5   -- en dessous, trop de composants pour un point
local PAS_MAX = 600

function recettes.EstVenduPartout(objet)
    return VENDUS_PARTOUT[tonumber(objet) or 0] == true or VENDUS_PARTOUT[tonumber(objet) or 0] == 1
end

-- Ecart entre le rang gris et le debut du jaune, appris par metier sur les
-- recettes dont le jeu a montre le passage orange -> jaune. A defaut, 25 :
-- la valeur la plus courante.
local ECART_PAR_DEFAUT = 25
local ecartsAppris, ecartsLe

local function EcartDuMetier(ligneMetier)
    local maintenant = NS.Horodatage()
    if not ecartsAppris or ecartsLe ~= maintenant then
        ecartsAppris, ecartsLe = {}, maintenant
        local valeurs = {}
        for _, r in pairs(Catalogue() or {}) do
            if type(r) == "table" and r.gris and r.jauneMin and r.jauneMax and r.jauneMax - r.jauneMin <= 2 then
                local m = tostring(r.metier or "?")
                valeurs[m] = valeurs[m] or {}
                table.insert(valeurs[m], r.gris - r.jauneMax)
            end
        end
        for m, liste in pairs(valeurs) do
            table.sort(liste)
            ecartsAppris[m] = liste[math.floor((#liste + 1) / 2)]
        end
    end
    return ecartsAppris[tostring(ligneMetier or "?")] or ECART_PAR_DEFAUT
end

-- Rang ou la recette cesse d'etre orange, estime ; nil si rien n'est connu.
function recettes.FinDuOrange(recette)
    local estime
    if recette.gris then estime = recette.gris - EcartDuMetier(recette.metier or recettes.MetierDe(recette)) end
    if recette.jauneMin then estime = math.max(estime or recette.jauneMin, recette.jauneMin) end
    if recette.jauneMax then estime = math.min(estime or recette.jauneMax, recette.jauneMax) end
    return estime
end

-- Chance de gagner un point a un rang : 1 en orange ; en jaune et en vert,
-- elle baisse jusqu'a 0 au gris, comme dans le jeu.
function recettes.ChanceDePoint(recette, rang)
    local fin = recettes.FinDuOrange(recette)
    if not fin then return 0 end
    -- Orange seulement d'apres une estimation (le jeu n'a jamais montre ou
    -- elle passe au jaune) : tres probable, mais pas compte comme sur.
    if rang < fin then return (recette.jauneMin or recette.jauneMax) and 1 or 0.95 end
    local gris = recette.gris
    if not gris or rang >= gris or gris <= fin then return 0 end
    return (gris - rang) / (gris - fin)
end

-- `objectif` : rang vise, ou nil pour aller aussi loin que les stocks le
-- permettent. Sans objectif, une recette ne se fait que si tous ses
-- composants de recolte sont la ; avec un objectif, ce qui manque est compte.
-- Ce que les rangs vises du personnage prennent dans ses stocks, objet par
-- objet : la banque le propose a la sortie, comme pour un projet.
-- Trois rangs vises possibles par metier, cumulables :
--   sur      : ce que les composants du compte donnent a coup sur (suit les stocks)
--   recettes : ce que les recettes connues permettent (suit les recettes)
--   choix    : un rang fixe, choisi aux fleches
-- Les anciens formats (un nombre, ou une liste de rangs) sont oublies.
-- Rien de regle : le rang assure est vise d'office, pour qu'il y ait
-- toujours un objectif a portee.
local function Emplacements(fiche, cle)
    local v = type(fiche) == "table" and type(fiche.objectifsProgression) == "table"
        and fiche.objectifsProgression[tostring(cle)]
    if type(v) == "table" and (v.sur ~= nil or v.recettes ~= nil or v.choix ~= nil) then
        return { sur = v.sur == true, recettes = v.recettes == true, choix = tonumber(v.choix) }
    end
    -- Rien de regle, ou un ancien format (rangs empiles) : on repart propre.
    return { sur = true }
end
recettes.Emplacements = Emplacements

function recettes.PoserEmplacement(fiche, cle, nom, valeur)
    if type(fiche) ~= "table" then return end
    local e = Emplacements(fiche, cle)
    if nom == "choix" then e.choix = tonumber(valeur) else e[nom] = valeur and true or false end
    fiche.objectifsProgression = type(fiche.objectifsProgression) == "table" and fiche.objectifsProgression or {}
    -- Garde aussi les cases decochees : sinon le rang assure revient d'office.
    fiche.objectifsProgression[tostring(cle)] = { sur = e.sur, recettes = e.recettes, choix = e.choix }
end

-- Les metiers qui se montent (ceux qui fabriquent), pour les rangs vises.
local RECOLTE_SEULE = { [182] = true, [356] = true, [393] = true }
function recettes.MetiersVises(fiche)
    local t = {}
    if type(fiche) ~= "table" or type(fiche.metiers) ~= "table" then return t end
    for cle, sien in pairs(fiche.metiers) do
        local ligne = tonumber(cle)
        if ligne and type(sien) == "table" and sien.rang and not RECOLTE_SEULE[ligne]
            and #(recettes.Pour(ligne) or {}) > 0 then
            table.insert(t, tostring(cle))
        end
    end
    table.sort(t)
    return t
end

-- Rang assure par les stocks, et rang atteignable avec les recettes. Garde
-- deux secondes : le suivi et la page les demandent souvent.
local cibles = {}
function recettes.Cibles(fiche, cle)
    local sien = type(fiche) == "table" and type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
    if type(sien) ~= "table" or not sien.rang then return nil, nil end
    local rang, rangMax = sien.rang, sien.rangMax
    local maintenant = (GetTime and GetTime()) or 0
    local k = tostring(fiche) .. ":" .. tostring(cle)
    local c = cibles[k]
    if c and c.rang == rang and maintenant - c.quand < 2 then return c.sur, c.recettes end
    local okS, planS = pcall(recettes.Progression, tonumber(cle), rang, rangMax, nil)
    local sur = okS and planS and rang + (planS.pointsSurs or 0) or rang
    local okR, planR = pcall(recettes.Progression, tonumber(cle), rang, rangMax, rangMax or (rang + 75))
    local rec = okR and planR and planR.atteint or rang
    cibles[k] = { rang = rang, quand = maintenant, sur = sur, recettes = rec }
    return sur, rec
end

-- Les rangs vises, tries : les rangs assure et atteignable seulement s'ils
-- sont au-dessus du rang actuel ; le rang choisi toujours (atteint, il
-- s'annonce puis s'efface).
function recettes.RangsVises(fiche, cle)
    local e = Emplacements(fiche, cle)
    local sien = type(fiche) == "table" and type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
    local rang = type(sien) == "table" and sien.rang or 0
    local t, vus = {}, {}
    local function Ajouter(r)
        if r and not vus[r] then vus[r] = true table.insert(t, r) end
    end
    if e.sur or e.recettes then
        local sur, rec = recettes.Cibles(fiche, cle)
        if e.sur and sur and sur > rang then Ajouter(sur) end
        if e.recettes and rec and rec > rang then Ajouter(rec) end
    end
    Ajouter(e.choix)
    table.sort(t)
    return t
end

-- Ne plus viser un rang (depuis le suivi) : l'emplacement qui le donne.
function recettes.Viser(fiche, cle, rang, oui)
    rang = tonumber(rang)
    if not rang or oui then return end
    local e = Emplacements(fiche, cle)
    local sur, rec = recettes.Cibles(fiche, cle)
    if e.choix == rang then recettes.PoserEmplacement(fiche, cle, "choix", nil) end
    if e.sur and sur == rang then recettes.PoserEmplacement(fiche, cle, "sur", nil) end
    if e.recettes and rec == rang then recettes.PoserEmplacement(fiche, cle, "recettes", nil) end
end

-- Les rangs vises d'un metier, a la suite : chacun part du precedent, et ce
-- que le precedent prend dans les stocks n'est pas compte deux fois.
-- Rend { { vise, de, plan }, ... }, du plus bas au plus haut.
function recettes.PlansVises(fiche, cle, rang, rangMax, liste)
    local res, pris, de = {}, {}, rang
    for _, vise in ipairs(liste or recettes.RangsVises(fiche, cle)) do
        if de and vise > de then
            local ok, plan = pcall(recettes.Progression, tonumber(cle), de, rangMax, vise, pris)
            if ok and plan then
                table.insert(res, { vise = vise, de = de, plan = plan })
                for objet, n in pairs(plan.utilises or {}) do pris[objet] = (pris[objet] or 0) + n end
            end
            de = vise
        end
    end
    return res
end

function recettes.BesoinsDesObjectifs(fiche)
    local besoins = {}
    fiche = fiche or (NS.base and NS.base.Personnage and NS.base.Personnage())
    if type(fiche) ~= "table" then return besoins end
    for _, cle in ipairs(recettes.MetiersVises(fiche)) do
        local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
        if type(sien) == "table" and sien.rang then
            for _, seg in ipairs(recettes.PlansVises(fiche, cle, sien.rang, sien.rangMax)) do
                for objet, n in pairs(seg.plan.utilises or {}) do besoins[objet] = (besoins[objet] or 0) + n end
                for objet, n in pairs(seg.plan.achats or {}) do besoins[objet] = (besoins[objet] or 0) + n end
            end
        end
    end
    return besoins
end

function recettes.Progression(ligneDeMetier, rangDepart, rangMax, objectif, dejaPris)
    local resultat = { depart = rangDepart, atteint = rangDepart, etapes = {}, achats = {}, manques = {},
        estime = false, arret = nil }
    if not ligneDeMetier or not rangDepart then resultat.arret = "inconnu" return resultat end

    local candidates = {}
    for _, recette in ipairs((recettes.Pour(ligneDeMetier))) do
        if recettes.EstApprise(recette.id) and type(recette.composants) == "table" and #recette.composants > 0
            and recettes.FinDuOrange(recette) then
            table.insert(candidates, recette)
        end
    end

    local stock = {}
    local function Stock(objet)
        if stock[objet] == nil then
            stock[objet] = math.max(0, (NS.inventaire.TotalPossede(objet) or 0) - (dejaPris and dejaPris[objet] or 0))
        end
        return stock[objet]
    end

    -- Composants qu'on fabrique soi-meme (le silex a aiguiser brut, fait de
    -- pierre brute) : une recette apprise qui les produit. Ce qui en manque se
    -- fabrique d'abord, avec ses propres composants.
    resultat.intermediaires = {}
    -- Ce que le plan prend dans le stock du compte, objet par objet : le
    -- guide dit ensuite ce qu'il faut aller chercher en banque ou ailleurs.
    resultat.utilises = {}
    local function Utiliser(objet, n)
        if n > 0 then resultat.utilises[objet] = (resultat.utilises[objet] or 0) + n end
    end
    local producteurs = {}
    for _, r in pairs(Catalogue() or {}) do
        if type(r) == "table" and r.objetProduit and type(r.composants) == "table" and #r.composants > 0
            and recettes.EstApprise(r.id) then
            producteurs[r.objetProduit] = producteurs[r.objetProduit] or r
        end
    end
    -- Combien de cet objet on peut encore fabriquer avec le stock.
    local function Fabricables(objet)
        local r = producteurs[objet]
        if not r then return 0 end
        local n
        for _, c in ipairs(r.composants) do
            if not recettes.EstVenduPartout(c.objet) and c.objet ~= objet then
                local k = math.floor(Stock(c.objet) / math.max(1, c.quantite))
                n = n and math.min(n, k) or k
            end
        end
        return (n or 0) * math.max(1, tonumber(r.quantiteMin) or 1)
    end
    local function Disponible(objet) return Stock(objet) + Fabricables(objet) end
    -- Prend `quantite` d'un composant : le stock d'abord, puis ce qu'on
    -- fabrique, puis le reste manque.
    local function Prendre(objet, quantite, profondeur)
        profondeur = profondeur or 0
        local dispo = Stock(objet)
        local pris = math.min(dispo, quantite)
        stock[objet] = dispo - pris
        Utiliser(objet, pris)
        local reste = quantite - pris
        local r = producteurs[objet]
        if reste > 0 and r and profondeur < 5 then
            local parFois = math.max(1, tonumber(r.quantiteMin) or 1)
            local fois = math.ceil(reste / parFois)
            resultat.intermediaires[objet] = (resultat.intermediaires[objet] or 0) + fois
            -- Plus c'est profond, plus ca se fabrique tot (barre de cuivre avant bronze).
            resultat.profondeurs = resultat.profondeurs or {}
            resultat.profondeurs[objet] = math.max(resultat.profondeurs[objet] or 0, profondeur)
            for _, c in ipairs(r.composants) do
                local besoin = c.quantite * fois
                if recettes.EstVenduPartout(c.objet) then
                    resultat.achats[c.objet] = (resultat.achats[c.objet] or 0) + besoin
                elseif c.objet ~= objet then
                    -- Un composant qu'on fabrique aussi (barre de cuivre pour la
                    -- barre de bronze) : on remonte jusqu'a ce qui se recolte
                    -- (le minerai), au lieu de demander la barre a la recolte.
                    Prendre(c.objet, besoin, profondeur + 1)
                end
            end
            return
        end
        if reste > 0 then resultat.manques[objet] = (resultat.manques[objet] or 0) + reste end
    end

    -- Une fabrication a la fois. Les recettes oranges donnent un point sur ;
    -- les jaunes, un point probable (la chance du jeu, comptee en moyenne).
    local plafond = objectif and math.min(objectif, rangMax or objectif) or (rangMax or 9999)
    local progres, pas = rangDepart, 0
    local derniere
    resultat.pointsSurs, resultat.pointsProbables = 0, 0
    while math.floor(progres) < plafond and pas < PAS_MAX do
        pas = pas + 1
        local rang = math.floor(progres)
        local meilleur, meilleurScore, meilleureChance
        for _, recette in ipairs(candidates) do
            local chance = recettes.ChanceDePoint(recette, rang)
            if chance >= CHANCE_MINIMUM then
                local recolte, manque = 0, 0
                for _, comp in ipairs(recette.composants) do
                    if not recettes.EstVenduPartout(comp.objet) then
                        recolte = recolte + comp.quantite
                        manque = manque + math.max(0, comp.quantite - Disponible(comp.objet))
                    end
                end
                if objectif or manque == 0 then
                    -- Les oranges d'abord, toujours : un point sur vaut mieux
                    -- qu'un point espere, meme s'il coute plus de composants.
                    -- Puis ce qu'on a deja, puis le moins de recolte par point.
                    local score = (chance < 1 and 1e12 or 0) + (manque * 100000 + recolte * 1000 + 1) / chance + (1 - chance)
                    if not meilleurScore or score < meilleurScore then
                        meilleur, meilleurScore, meilleureChance = recette, score, chance
                    end
                end
            end
        end
        if not meilleur then
            resultat.arret = (#candidates == 0) and "aucuneRecette" or "plusRien"
            break
        end
        for _, comp in ipairs(meilleur.composants) do
            if recettes.EstVenduPartout(comp.objet) then
                resultat.achats[comp.objet] = (resultat.achats[comp.objet] or 0) + comp.quantite
            else
                Prendre(comp.objet, comp.quantite)
            end
        end
        local gain = (meilleur.points or 1) * meilleureChance
        if meilleureChance >= 1 then
            resultat.pointsSurs = resultat.pointsSurs + gain
        else
            resultat.pointsProbables = resultat.pointsProbables + gain
        end
        local avant = rang
        progres = progres + gain
        if rangMax then progres = math.min(progres, rangMax) end
        if derniere and derniere.recette == meilleur then
            derniere.fois = derniere.fois + 1
            derniere.a = math.floor(progres)
            derniere.probable = derniere.probable or meilleureChance < 1
        else
            derniere = { recette = meilleur, fois = 1, de = avant, a = math.floor(progres), probable = meilleureChance < 1 }
            table.insert(resultat.etapes, derniere)
        end
        if not (meilleur.jauneMin and meilleur.jauneMax) then resultat.estime = true end
    end
    local rang = math.floor(progres)
    if rang >= plafond and not resultat.arret then
        resultat.arret = (rangMax and rang >= rangMax and (not objectif or objectif > rangMax)) and "plafond" or "objectif"
    end
    resultat.pointsSurs = math.floor(resultat.pointsSurs + 0.5)
    resultat.pointsProbables = math.floor(resultat.pointsProbables + 0.5)
    resultat.atteint = rang
    return resultat
end


-- ===========================================================================
-- Fabriquer depuis CraftCore
-- ===========================================================================
--
-- Le jeu ne fabrique que pour le metier ouvert, sur le personnage connecte,
-- et seulement sur un vrai clic (souris ou manette). Donc :
--   metier deja ouvert : on lance la fabrication tout de suite ;
--   sinon : on demande au jeu de l'ouvrir, et on le dit ; le clic suivant
--   fabrique (le premier clic a servi a ouvrir, le jeu n'en accepte qu'un).
-- Les conditions restent celles du jeu (feu de camp, enclume, composants
-- dans les sacs) : s'il refuse, c'est son propre message qui s'affiche.
-- Chaque essai est note dans la decouverte, pour verifier ce que le client
-- accepte reellement.

local function MetierOuvert()
    local j = NS.jeu
    if not j.infoMetierDeBase then return nil end
    local info = NS.Appeler(j.infoMetierDeBase)
    if type(info) ~= "table" then return nil end
    local ligne = tonumber(info.professionID) or tonumber(info.skillLineID) or tonumber(info.parentProfessionID)
    return (ligne and ligne > 0) and ligne or nil
end

local function FenetreDuJeuVisible()
    for _, nom in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local f = _G[nom]
        if f and f.IsShown and f:IsShown() then return nom end
    end
    return nil
end

local function Noter(essai)
    local dec = NS.base.Decouverte and NS.base.Decouverte()
    if not dec then return end
    dec.essaisFabrication = dec.essaisFabrication or {}
    table.insert(dec.essaisFabrication, essai)
    while #dec.essaisFabrication > 10 do table.remove(dec.essaisFabrication, 1) end
end

-- Rend "fabrique", "ouverture", "impossible" ou "refus", et un detail.
-- Le metier de la recette est-il deja ouvert ? Alors un clic sur le bouton
-- lance la fabrication (sinon, le premier clic ouvre le metier).
function recettes.PretALancer(recette)
    local ligne = recettes.MetierDe and recettes.MetierDe(recette)
    return ligne ~= nil and MetierOuvert() == ligne
end

function recettes.Fabriquer(recette, nombre)
    local j = NS.jeu
    nombre = math.max(1, tonumber(nombre) or 1)
    local ligne = recettes.MetierDe and recettes.MetierDe(recette)
    local essai = { quand = NS.Horodatage(), recette = recette and recette.id, metier = ligne, nombre = nombre,
        fabriquerExiste = j.fabriquer ~= nil, ouvrirExiste = j.ouvrirMetier ~= nil,
        ouvertAvant = MetierOuvert(), fenetreAvant = FenetreDuJeuVisible() }
    -- Enchantement (aucun objet fabrique) : le metier s'ouvre comme pour le
    -- reste, puis l'objet a enchanter se choisit (voir Actions, Enchanter).
    if not recette or not j.fabriquer then
        essai.resultat = "impossible"
        Noter(essai)
        return "impossible"
    end
    if essai.ouvertAvant ~= ligne then
        if not j.ouvrirMetier or not ligne then
            essai.resultat = "impossible"
            Noter(essai)
            return "impossible"
        end
        local ok, souci = pcall(j.ouvrirMetier, ligne)
        essai.ouverture = ok and "ok" or tostring(souci)
        essai.ouvertApres = MetierOuvert()
        essai.fenetreApres = FenetreDuJeuVisible()
        essai.resultat = "ouverture"
        Noter(essai)
        return "ouverture"
    end
    if not recette.objetProduit then
        if ligne ~= 333 then essai.resultat = "impossible" Noter(essai) return "impossible" end
        essai.resultat = "enchantement"
        Noter(essai)
        return "enchantement"
    end
    local ok, souci = pcall(j.fabriquer, tonumber(recette.id) or recette.id, nombre)
    essai.fabrication = ok and "ok" or tostring(souci)
    essai.resultat = ok and "fabrique" or "refus"
    Noter(essai)
    return essai.resultat, souci
end


-- ===========================================================================
-- Recette apprise, et actualisation de tous les metiers
-- ===========================================================================

-- Note une recette que le jeu vient d'annoncer comme apprise.
function recettes.NoterApprise(id)
    id = tonumber(id)
    if not id then return end
    local fiche = NS.base.Personnage()
    if fiche then
        fiche.recettesApprises = fiche.recettesApprises or {}
        fiche.recettesApprises[tostring(id)] = true
    end
    local catalogue = Catalogue()
    if catalogue and not catalogue[tostring(id)] and NS.jeu.infoRecette then
        local info = NS.Appeler(NS.jeu.infoRecette, id)
        if type(info) == "table" and info.name then
            local plan = NS.jeu.planRecette and NS.Appeler(NS.jeu.planRecette, id, false)
            Enregistrer(id, {
                nom = info.name,
                categorie = tonumber(info.categoryID),
                objetProduit = type(plan) == "table" and tonumber(plan.outputItemID) or nil,
                composants = LireComposants(plan),
                vueLe = NS.Horodatage(),
                origine = "apprise",
            })
        end
    end
end

-- Metiers de recolte : rien a fabriquer, inutile de les ouvrir.
local SANS_RECETTES = { [182] = true, [393] = true, [356] = true }

local actualisationEnCours = false

-- Relit un metier : l'ouvre, le relit, le referme. Appele depuis un vrai
-- clic (double clic sur son onglet) : le jeu n'accepte d'ouvrir un metier que
-- sur une action du joueur. Si la fenetre du metier etait deja ouverte, elle
-- reste ouverte. Rend false si ce n'est pas possible maintenant.
function recettes.ActualiserMetier(ligne, fin)
    local j = NS.jeu
    ligne = tonumber(ligne)
    if actualisationEnCours or not ligne or SANS_RECETTES[ligne] then return false end
    local enCombat = NS.Lecture("InCombatLockdown")
    if enCombat and enCombat() then return false end
    if not j.ouvrirMetier then return false end
    pcall(recettes.ReleverNiveaux)
    local dejaOuvert = MetierOuvert() == ligne
    if not dejaOuvert then
        local ok = pcall(j.ouvrirMetier, ligne)
        if not ok then return false end
    end
    actualisationEnCours = true
    local function Lire()
        pcall(recettes.Relever, "actualisation")
        if not dejaOuvert and j.fermerMetier then pcall(j.fermerMetier) end
        actualisationEnCours = false
        if fin then pcall(fin) end
    end
    local plusTard = NS.Lecture("C_Timer.After")
    if plusTard then NS.Appeler(plusTard, 1, Lire) else Lire() end
    return true
end


-- ===========================================================================
-- Palier de progression d'une recette, pour le personnage affiche
-- ===========================================================================
-- Meme regle partout (Recettes, Equipement) : orange point sur, jaune point
-- probable, vert peu probable, gris plus rien. Couleurs de difficulte du jeu.

recettes.COULEURS_PALIER = {
    sur = { 1, 0.5, 0.25 }, probable = { 1, 1, 0 }, peu = { 0.25, 0.75, 0.25 }, rien = { 0.5, 0.5, 0.5 },
}

function recettes.Palier(recette)
    if type(recette) ~= "table" or not recettes.FinDuOrange(recette) then return nil end
    local ligneMetier = recette.metier or recettes.MetierDe(recette)
    local fiche = NS.base.FicheAffichee()
    local sien = fiche and type(fiche.metiers) == "table" and ligneMetier and fiche.metiers[tostring(ligneMetier)]
    if not sien or not sien.rang then return nil end
    local chance = recettes.ChanceDePoint(recette, sien.rang)
    if chance >= 1 then return "sur" end
    if chance >= 0.5 then return "probable" end
    if chance > 0 then return "peu" end
    return "rien"
end

-- La coche du jeu teintee, a inserer dans un texte (legendes).
function recettes.CocheTexte(palier)
    local c = recettes.COULEURS_PALIER[palier] or recettes.COULEURS_PALIER.rien
    return string.format("|TInterface\\Buttons\\UI-CheckBox-Check:14:14:0:0:32:32:0:32:0:32:%d:%d:%d|t",
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- Legende complete des paliers.
function recettes.LegendeDesPaliers()
    return string.format(NS.L.RECIPES_LEGEND, recettes.CocheTexte("sur"), recettes.CocheTexte("probable"),
        recettes.CocheTexte("peu"))
end

