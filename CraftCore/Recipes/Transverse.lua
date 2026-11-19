local _, NS = ...

-- Vue transverse de l'equipement.
--
-- Pour un emplacement donne, tout ce que le compte peut offrir : ce que le
-- personnage regarde sait fabriquer, ce qu'un autre de ses personnages sait
-- fabriquer, et ce qui dort deja dans les sacs ou la banque d'un autre.
--
-- Rien n'est declare meilleur : on rassemble, l'utilisateur compare.

NS.transverse = {}
local transverse = NS.transverse

-- Matiere d'une armure (tissu, cuir, mailles, plaques), telle que le client
-- la nomme. Seules les armures ont une matiere : une arme, un bandage, un
-- bijou n'en ont pas, et ne doivent pas devenir des filtres. On lit la classe
-- et la sous-classe rendues par le client (armure = 4, matieres = 1 a 4).
local MATIERES_D_ARMURE = { [1] = true, [2] = true, [3] = true, [4] = true }

function transverse.MatiereDe(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil end
    local ok, _, _, sousGenre, _, _, classe, sousClasse = pcall(lecture, objet)
    if not ok or classe ~= 4 or not MATIERES_D_ARMURE[sousClasse] then return nil end
    if type(sousGenre) == "string" and sousGenre ~= "" then return sousGenre end
    return nil
end

-- Matiere portee nativement par un personnage : la plus representee parmi ce
-- qu'il porte. Deduite de ses faits, jamais d'une table de classes qui serait
-- fausse des que le jeu change.
function transverse.MatiereNative(fiche)
    if not fiche then return nil end
    local comptes = {}
    local meilleure, meilleurCompte
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local porte = fiche.equipement and fiche.equipement[emplacement.nom]
        local objet = porte and porte.id
        if objet then
            local matiere = transverse.MatiereDe(objet)
            if matiere then
                comptes[matiere] = (comptes[matiere] or 0) + 1
                if not meilleurCompte or comptes[matiere] > meilleurCompte then
                    meilleure, meilleurCompte = matiere, comptes[matiere]
                end
            end
        end
    end
    return meilleure
end

-- Toutes les matieres rencontrees, pour proposer des filtres qui existent
-- vraiment chez ce joueur.
function transverse.MatieresConnues()
    local vues, liste = {}, {}
    local d = CraftCoreDB
    if type(d) ~= "table" then return liste end
    for cle, recette in pairs(d.recettes or {}) do
        if recette.objetProduit then
            local matiere = transverse.MatiereDe(recette.objetProduit)
            if matiere and not vues[matiere] then
                vues[matiere] = true
                table.insert(liste, matiere)
            end
        end
    end
    table.sort(liste)
    return liste
end

local function NomCourt(cle)
    return NS.inventaire.NomCourt(cle)
end

-- Recettes qu'un personnage donne sait fabriquer pour cet emplacement.
local function RecettesDe(fiche, code)
    local d = CraftCoreDB
    local trouvees = {}
    if type(d) ~= "table" or type(d.recettes) ~= "table" then return trouvees end
    local apprises = fiche and fiche.recettesApprises or {}
    for cle, recette in pairs(d.recettes) do
        if apprises[cle] and recette.objetProduit
            and NS.emplacements.DeLObjet(recette.objetProduit) == code then
            table.insert(trouvees, { id = tonumber(cle) or cle, recette = recette })
        end
    end
    return trouvees
end

-- Objets qu'un personnage detient et qui vont a cet emplacement.
local function ObjetsDe(fiche, code)
    local trouves = {}
    if not fiche then return trouves end
    local conteneurs = NS.base.ConteneursDe(fiche)
    for cle, ligne in pairs(NS.base.StocksDe(fiche)) do
        local objet = tonumber(cle)
        if objet and NS.emplacements.DeLObjet(objet) == code then
            -- Ou il se trouve, sacs ou banque, pour savoir quoi faire ensuite.
            local ou
            for idConteneur in pairs(ligne.parConteneur or {}) do
                local fc = conteneurs[idConteneur]
                if fc and fc.source == "banque" then ou = "banque" break end
                ou = ou or "sacs"
            end
            table.insert(trouves, { objet = objet, quantite = ligne.total or 0, ou = ou })
        end
    end
    return trouves
end

-- Tous les candidats pour un emplacement, groupes par origine.
function transverse.Candidats(code)
    local resultat = { moi = {}, autres = {}, possedes = {} }
    if not code then return resultat end

    local cleAffichee = NS.base.CleAffichee()
    local ficheAffichee = NS.base.FicheAffichee()

    for _, entree in ipairs(RecettesDe(ficheAffichee, code)) do
        local objet = entree.recette.objetProduit
        local manques = NS.recettes.Manques(entree.recette)
        table.insert(resultat.moi, {
            objet = objet,
            recette = entree.id,
            matiere = transverse.MatiereDe(objet),
            sousClasse = transverse.SousClasseDe(objet),
            pret = (manques ~= nil and #manques == 0),
            manques = manques,
            combien = NS.recettes.CombienFabricables and NS.recettes.CombienFabricables(entree.recette) or nil,
        })
    end

    local d = CraftCoreDB
    for cle, fiche in pairs((type(d) == "table" and d.personnages) or {}) do
        -- Un personnage de l'autre camp ne peut ni fabriquer pour celui-ci, ni
        -- lui envoyer quoi que ce soit.
        if cle ~= cleAffichee and NS.inventaire.MemeCamp(fiche) then
            for _, entree in ipairs(RecettesDe(fiche, code)) do
                local objet = entree.recette.objetProduit
                table.insert(resultat.autres, {
                    objet = objet,
                    recette = entree.id,
                    qui = cle,
                    nomCourt = NomCourt(cle),
                    matiere = transverse.MatiereDe(objet),
                    sousClasse = transverse.SousClasseDe(objet),
                })
            end
            for _, entree in ipairs(ObjetsDe(fiche, code)) do
                table.insert(resultat.possedes, {
                    objet = entree.objet,
                    qui = cle,
                    nomCourt = NomCourt(cle),
                    ou = entree.ou,
                    quantite = entree.quantite,
                    matiere = transverse.MatiereDe(entree.objet),
                    sousClasse = transverse.SousClasseDe(entree.objet),
                })
            end
        end
    end

    local function trier(liste)
        table.sort(liste, function(a, b)
            local na = NS.inventaire.NomDObjet(a.objet)
            local nb = NS.inventaire.NomDObjet(b.objet)
            return na < nb
        end)
    end
    trier(resultat.moi) trier(resultat.autres) trier(resultat.possedes)
    return resultat
end


-- ===========================================================================
-- Ce qu'un personnage peut porter, et ce qui vaut mieux pour lui
-- ===========================================================================
--
-- Armures portables selon la classe et le niveau, regles du jeu classique :
-- chasseurs et chamans passent du cuir a la maille au niveau 40, guerriers et
-- paladins de la maille a la plaque au niveau 40. La meilleure matiere
-- portable est la preference ; les autres restent possibles, en second plan.
-- Sous-classes d'armure du jeu : 1 tissu, 2 cuir, 3 mailles, 4 plaques.

local PORTABLES = {
    MAGE = { 1 }, PRIEST = { 1 }, WARLOCK = { 1 },
    ROGUE = { 1, 2 }, DRUID = { 1, 2 },
    HUNTER = { 1, 2, 3 }, SHAMAN = { 1, 2, 3 },
    WARRIOR = { 1, 2, 3, 4 }, PALADIN = { 1, 2, 3, 4 },
}
local NIVEAU_PALIER = 40
local PALIER = { HUNTER = 3, SHAMAN = 3, WARRIOR = 4, PALADIN = 4 }

function transverse.SousClasseDe(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil end
    local ok, _, _, _, _, _, classe, sousClasse = pcall(lecture, objet)
    if not ok or classe ~= 4 or not MATIERES_D_ARMURE[sousClasse] then return nil end
    return sousClasse
end

-- Rend { [sousClasse] = "prefere" | "possible" } pour une fiche de personnage.
-- Classe inconnue : tout est possible, rien n'est impose.
function transverse.ArmuresPortables(fiche)
    local classe = fiche and fiche.jetonClasse
    local niveau = tonumber(fiche and fiche.niveau) or 1
    local liste = PORTABLES[classe or ""]
    local resultat = {}
    if not liste then
        for sous in pairs(MATIERES_D_ARMURE) do resultat[sous] = "possible" end
        return resultat, nil
    end
    local meilleure = 0
    for _, sous in ipairs(liste) do
        if not (PALIER[classe] == sous and niveau < NIVEAU_PALIER) then
            resultat[sous] = "possible"
            if sous > meilleure then meilleure = sous end
        end
    end
    if meilleure > 0 then resultat[meilleure] = "prefere" end
    return resultat, meilleure
end

-- Poids des caracteristiques par classe, pour classer des objets entre eux.
-- Volontairement simples : la principale compte double, l'endurance compte,
-- le reste un peu. Sert a montrer une piste, pas a decider.
local POIDS = {
    WARRIOR = { STRENGTH = 2, STAMINA = 1.5, AGILITY = 1 },
    PALADIN = { STRENGTH = 2, STAMINA = 1.5, INTELLECT = 1 },
    HUNTER = { AGILITY = 2, STAMINA = 1, INTELLECT = 0.5 },
    ROGUE = { AGILITY = 2, STAMINA = 1, STRENGTH = 1 },
    SHAMAN = { INTELLECT = 1.5, AGILITY = 1.5, STRENGTH = 1, STAMINA = 1 },
    DRUID = { INTELLECT = 1.5, AGILITY = 1.5, STAMINA = 1, SPIRIT = 1 },
    PRIEST = { INTELLECT = 2, SPIRIT = 1.5, STAMINA = 1 },
    MAGE = { INTELLECT = 2, STAMINA = 1, SPIRIT = 1 },
    WARLOCK = { INTELLECT = 2, STAMINA = 1.5, SPIRIT = 0.5 },
}
local POIDS_ARMURE = 0.05

function transverse.Score(objet, fiche)
    if not objet then return 0 end
    local stats = NS.objets.Stats and NS.objets.Stats(objet) or {}
    local poids = POIDS[(fiche and fiche.jetonClasse) or ""] or { STAMINA = 1, STRENGTH = 1, AGILITY = 1, INTELLECT = 1, SPIRIT = 1 }
    local score = 0
    for cle, valeur in pairs(stats) do
        local cleTexte = tostring(cle)
        if string.find(cleTexte, "RESISTANCE0", 1, true) or string.find(cleTexte, "ARMOR", 1, true) then
            score = score + (tonumber(valeur) or 0) * POIDS_ARMURE
        else
            for nom, p in pairs(poids) do
                if string.find(cleTexte, nom, 1, true) then score = score + (tonumber(valeur) or 0) * p break end
            end
        end
    end
    return score
end

-- Un objet est il portable par ce personnage ? Rend aussi "prefere" ou
-- "possible" pour les armures.
function transverse.Portable(objet, fiche)
    local sous = transverse.SousClasseDe(objet)
    if not sous then return true, nil end
    local portables = transverse.ArmuresPortables(fiche)
    return portables[sous] ~= nil, portables[sous]
end

-- Les autres personnages du meme camp qui pourraient porter un objet, et si
-- ce serait mieux que ce qu'ils portent a cet emplacement.
function transverse.QuiPourraitLePorter(objet, saufCle)
    local resultat = {}
    local code = NS.emplacements and NS.emplacements.DeLObjet and NS.emplacements.DeLObjet(objet)
    if not code then return resultat end
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if fiche.cle ~= saufCle and NS.inventaire.MemeCamp(fiche) then
            local ok, rang = transverse.Portable(objet, fiche)
            if ok then
                local meilleurPorte
                for _, e in ipairs(NS.emplacements.DuPersonnage) do
                    if e.code == code then
                        local porte = fiche.equipement and fiche.equipement[e.nom]
                        local s = porte and porte.id and transverse.Score(porte.id, fiche) or 0
                        if not meilleurPorte or s < meilleurPorte then meilleurPorte = s end
                    end
                end
                local gain = transverse.Score(objet, fiche) - (meilleurPorte or 0)
                table.insert(resultat, {
                    nom = NS.inventaire.NomCourt(fiche.cle),
                    mieux = gain > 0, gain = gain, second = (rang == "possible"),
                })
            end
        end
    end
    table.sort(resultat, function(a, b) return a.gain > b.gain end)
    return resultat
end
