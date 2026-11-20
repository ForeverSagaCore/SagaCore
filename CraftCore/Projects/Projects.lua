local _, NS = ...

-- Projets de fabrication et fabrications rapides.
--
-- Deux listes distinctes, comme le demande le cahier des charges. Un projet est
-- nomme, ordonne et archivable. Une fabrication rapide est une simple envie,
-- sans ceremonie, et elle peut rejoindre un projet plus tard.
--
-- Les deux comptent dans le calcul global : ce qui est voulu est voulu, quelle
-- que soit la liste qui le porte.

NS.projets = {}
local projets = NS.projets

-- Les projets et les fabrications rapides appartiennent au personnage : le
-- chasseur n'a pas a voir ceux du paladin.
--
-- Les projets crees avant cette separation sont deplaces vers le personnage qui
-- se connecte en premier, jamais effaces.
local function Base()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    local fiche = NS.base.FicheAffichee and NS.base.FicheAffichee() or NS.base.Personnage()
    if not fiche then return nil end

    -- Reprise des anciennes listes du compte, une seule fois.
    if d.projets or d.rapides then
        local destinataire = NS.base.Personnage()
        if destinataire then
            destinataire.projets = destinataire.projets or {}
            destinataire.rapides = destinataire.rapides or {}
            for cle, projet in pairs(d.projets or {}) do
                if destinataire.projets[cle] == nil then
                    -- Repris du compte : on ne sait pas qui l'avait lance, et
                    -- on ne l'invente pas.
                    projet.repris = projet.repris or NS.Horodatage()
                    destinataire.projets[cle] = projet
                end
            end
            for _, entree in ipairs(d.rapides or {}) do
                table.insert(destinataire.rapides, entree)
            end
            destinataire.prochainProjet = math.max(tonumber(destinataire.prochainProjet) or 1,
                tonumber(d.prochainProjet) or 1)
            d.projets, d.rapides, d.prochainProjet = nil, nil, nil
        end
    end

    fiche.projets = fiche.projets or {}
    fiche.rapides = fiche.rapides or {}
    fiche.prochainProjet = tonumber(fiche.prochainProjet) or 1
    return fiche
end

-- ---------------------------------------------------------------------------
-- Projets
-- ---------------------------------------------------------------------------

function projets.Creer(nom)
    local d = Base()
    if not d then return nil end
    local id = d.prochainProjet
    d.prochainProjet = id + 1
    local projet = {
        id = id,
        nom = (type(nom) == "string" and nom ~= "" and nom) or nil,
        priorite = id,
        cree = NS.Horodatage(),
        -- Qui l'a lance : sans cela, un projet repris d'une autre version ou
        -- deplace ne dit plus d'ou il vient.
        creePar = NS.ClePersonnage(),
        statut = "actif",
        objets = {},
    }
    d.projets[tostring(id)] = projet
    return projet
end

-- Projet tire d'un plan de progression (page Progression) : marque a la
-- creation, ou reconnu a son nom pour ceux crees avant la marque.
function projets.EstDeProgression(projet)
    if type(projet) ~= "table" then return false end
    if projet.progression then return true end
    local modele = NS.L and NS.L.PROG_PROJECT_NAME
    if type(projet.nom) ~= "string" or type(modele) ~= "string" then return false end
    local motif = "^" .. modele:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+") .. "$"
    return string.find(projet.nom, motif) ~= nil
end

function projets.Supprimer(id)
    local d = Base()
    if not d then return false end
    if not d.projets[tostring(id)] then return false end
    d.projets[tostring(id)] = nil
    -- Le suivi a l'ecran le montre aussitot, sans attendre son prochain tour.
    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
    return true
end

function projets.Renommer(id, nom)
    local projet = projets.Par(id)
    if not projet then return false end
    projet.nom = (type(nom) == "string" and nom ~= "" and nom) or nil
    return true
end

function projets.Archiver(id, archive)
    local projet = projets.Par(id)
    if not projet then return false end
    projet.statut = archive and "archive" or "actif"
    projet.termine = archive and NS.Horodatage() or nil
    return true
end

function projets.Par(id)
    local d = Base()
    if not d then return nil end
    return d.projets[tostring(id)]
end

-- Projets, les actifs d'abord, puis par priorite.
function projets.Tous(avecArchives)
    local d = Base()
    if not d then return {} end
    local liste = {}
    for _, projet in pairs(d.projets) do
        if avecArchives or projet.statut ~= "archive" then
            table.insert(liste, projet)
        end
    end
    table.sort(liste, function(a, b)
        local aa, ab = (a.statut == "archive"), (b.statut == "archive")
        if aa ~= ab then return ab end
        local pa, pb = tonumber(a.priorite) or 0, tonumber(b.priorite) or 0
        if pa ~= pb then return pa < pb end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    return liste
end

function projets.NomDe(projet)
    if not projet then return "" end
    if projet.nom and projet.nom ~= "" then return projet.nom end
    return string.format(NS.L and NS.L.PROJECT_DEFAULT_NAME or "Project %d", projet.id or 0)
end

-- Monte ou descend un projet dans l'ordre de priorite.
function projets.Deplacer(id, pas)
    local liste = projets.Tous(false)
    local rang
    for index, projet in ipairs(liste) do
        if tostring(projet.id) == tostring(id) then rang = index break end
    end
    if not rang then return false end
    local cible = rang + pas
    if cible < 1 or cible > #liste then return false end
    liste[rang].priorite, liste[cible].priorite = liste[cible].priorite, liste[rang].priorite
    return true
end

-- ---------------------------------------------------------------------------
-- Contenu d'une liste, projet ou fabrications rapides
-- ---------------------------------------------------------------------------

local function Entrees(cible)
    if cible == "rapides" then
        local d = Base()
        return d and d.rapides or nil
    end
    local projet = projets.Par(cible)
    return projet and projet.objets or nil
end

function projets.Ajouter(cible, recette, quantite)
    local entrees = Entrees(cible)
    if not entrees or not recette then return false end
    quantite = tonumber(quantite) or 1
    for _, entree in ipairs(entrees) do
        if tostring(entree.recette) == tostring(recette) then
            entree.quantite = (tonumber(entree.quantite) or 0) + quantite
            return true
        end
    end
    table.insert(entrees, { recette = recette, quantite = quantite })
    return true
end

function projets.ChangerQuantite(cible, recette, delta)
    local entrees = Entrees(cible)
    if not entrees then return false end
    for index, entree in ipairs(entrees) do
        if tostring(entree.recette) == tostring(recette) then
            local nouvelle = (tonumber(entree.quantite) or 0) + delta
            if nouvelle <= 0 then
                table.remove(entrees, index)
            else
                entree.quantite = nouvelle
            end
            return true
        end
    end
    return false
end

function projets.Retirer(cible, recette)
    local entrees = Entrees(cible)
    if not entrees then return false end
    for index, entree in ipairs(entrees) do
        if tostring(entree.recette) == tostring(recette) then
            table.remove(entrees, index)
            return true
        end
    end
    return false
end

function projets.Contenu(cible)
    return Entrees(cible) or {}
end

-- Verse les fabrications rapides dans un projet, sans rien perdre en route.
function projets.VerserLesRapidesDans(id)
    local d = Base()
    local projet = projets.Par(id)
    if not d or not projet then return 0 end
    local versees = 0
    for _, entree in ipairs(d.rapides) do
        projets.Ajouter(id, entree.recette, entree.quantite)
        versees = versees + 1
    end
    d.rapides = {}
    return versees
end

-- ---------------------------------------------------------------------------
-- Calcul
-- ---------------------------------------------------------------------------

-- Stocks de tout le compte, du cote de la faction du personnage affiche, dans
-- la forme attendue par le moteur. Meme regle que partout : l'autre camp ne
-- peut rien fournir, il n'entre donc pas dans le calcul.
function projets.StocksDuCompte()
    local stocks = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if NS.inventaire.MemeCamp(fiche) then
            for cle, entree in pairs(NS.base.StocksDe(fiche)) do
                local objet = tonumber(cle)
                if objet then stocks[objet] = (stocks[objet] or 0) + (entree.total or 0) end
            end
        end
    end
    return stocks
end

-- Stocks du seul personnage affiche, sacs et banque : ce qu'il a lui-meme,
-- sans rien rapatrier.
function projets.StocksDuPersonnage()
    local stocks = {}
    for cle, entree in pairs(NS.base.StocksDe(NS.base.FicheAffichee())) do
        local objet = tonumber(cle)
        if objet then stocks[objet] = (stocks[objet] or 0) + (entree.total or 0) end
    end
    return stocks
end

-- Stocks de ses autres personnages du meme camp : ce qui se rapatrie.
function projets.StocksDesAutres()
    local stocks = {}
    local courant = NS.base.CleAffichee()
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if fiche.cle ~= courant and NS.inventaire.MemeCamp(fiche) then
            for cle, entree in pairs(NS.base.StocksDe(fiche)) do
                local objet = tonumber(cle)
                if objet then stocks[objet] = (stocks[objet] or 0) + (entree.total or 0) end
            end
        end
    end
    return stocks
end

local function EstApprise(id)
    return NS.recettes and NS.recettes.EstApprise and NS.recettes.EstApprise(id) or false
end

-- Decompose une liste, projet ou rapides, avec son propre stock.
function projets.Calculer(cible)
    local entrees = Entrees(cible)
    if not entrees or #entrees == 0 then return nil end
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return nil end
    local lignes = {}
    for _, entree in ipairs(entrees) do
        table.insert(lignes, { recette = tonumber(entree.recette) or entree.recette,
            quantite = tonumber(entree.quantite) or 1 })
    end
    return NS.moteur.DecomposerPlusieurs(catalogue, projets.StocksDuCompte(), lignes, EstApprise)
end

-- Tout ce qui est voulu, projets actifs et fabrications rapides reunis. C'est
-- le calcul global du cahier des charges. `stocks` est optionnel : par defaut,
-- ceux du compte. `stocksAilleurs`, optionnel aussi, est puise apres `stocks`
-- et ce qu'on y prend est rendu a part : c'est ce qui se rapatrie.
-- filtre : nil (tout), "fabrications" (rapides et projets nommes) ou
-- "progressions" (projets tires d'un plan de progression).
function projets.CalculerTout(stocks, stocksAilleurs, filtre)
    local d = Base()
    if not d then return nil end
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return nil end

    local lignes = {}
    for _, projet in ipairs(projets.Tous(false)) do
        local deProg = projets.EstDeProgression(projet)
        local garde = not filtre or (filtre == "progressions") == deProg
        for _, entree in ipairs(garde and projet.objets or {}) do
            table.insert(lignes, { recette = tonumber(entree.recette) or entree.recette,
                quantite = tonumber(entree.quantite) or 1 })
        end
    end
    for _, entree in ipairs(filtre ~= "progressions" and d.rapides or {}) do
        table.insert(lignes, { recette = tonumber(entree.recette) or entree.recette,
            quantite = tonumber(entree.quantite) or 1 })
    end
    if #lignes == 0 then return nil end
    return NS.moteur.DecomposerPlusieurs(catalogue, stocks or projets.StocksDuCompte(), lignes,
        EstApprise, stocksAilleurs)
end

-- Destination des ajouts par clic droit : un projet, ou les fabrications
-- rapides quand aucun projet n'est designe.
function projets.Destination()
    local d = Base()
    if not d then return "rapides" end
    local cible = d.destination
    if cible and projets.Par(cible) then return cible end
    return "rapides"
end

function projets.PoserDestination(cible)
    local d = Base()
    if not d then return end
    if cible == nil or cible == "rapides" then
        d.destination = nil
    else
        d.destination = cible
    end
end

function projets.NomDeLaDestination()
    local cible = projets.Destination()
    if cible == "rapides" then
        return NS.L and NS.L.NAV_QUICK or "Quick crafts"
    end
    return projets.NomDe(projets.Par(cible))
end

-- Donne un projet a un autre personnage, sans rien perdre en route.
function projets.Donner(id, cleDestinataire)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return false end
    local source = NS.base.FicheAffichee()
    local cible = d.personnages[cleDestinataire]
    if not source or not cible or source == cible then return false end

    local projet = source.projets and source.projets[tostring(id)]
    if not projet then return false end

    cible.projets = cible.projets or {}
    cible.prochainProjet = tonumber(cible.prochainProjet) or 1
    -- Nouveau numero chez le destinataire, pour ne pas ecraser un des siens.
    local nouvelId = cible.prochainProjet
    cible.prochainProjet = nouvelId + 1
    projet.id = nouvelId
    projet.priorite = nouvelId
    cible.projets[tostring(nouvelId)] = projet

    source.projets[tostring(id)] = nil
    return true
end

-- Nom lisible du personnage qui a lance un projet, ou nil si on l'ignore.
function projets.LanceePar(projet)
    if not projet or not projet.creePar then return nil end
    return NS.inventaire.NomCourt(projet.creePar)
end

-- Projet transverse : fabrique par un personnage, destine a un autre.
-- Il est range chez celui qui doit le fabriquer, puisque c'est lui qui aura
-- besoin des matieres et qui verra la liste d'approvisionnement.
function projets.CreerTransverse(cleFabricant, cleDestinataire, recette, nom)
    local d = CraftCoreDB
    if type(d) ~= "table" or type(d.personnages) ~= "table" then return nil end
    local fabricant = d.personnages[cleFabricant]
    if not fabricant then return nil end

    fabricant.projets = fabricant.projets or {}
    fabricant.prochainProjet = tonumber(fabricant.prochainProjet) or 1
    local id = fabricant.prochainProjet
    fabricant.prochainProjet = id + 1

    local projet = {
        id = id,
        nom = nom,
        priorite = id,
        cree = NS.Horodatage(),
        creePar = NS.ClePersonnage(),
        pour = cleDestinataire,
        statut = "actif",
        objets = { { recette = recette, quantite = 1 } },
    }
    fabricant.projets[tostring(id)] = projet
    return projet
end

-- Pour qui ce projet est fait, quand ce n'est pas pour celui qui le fabrique.
function projets.Pour(projet)
    if not projet or not projet.pour then return nil end
    return NS.inventaire.NomCourt(projet.pour)
end

-- Projets actifs qui attendent encore cet objet, et qui ne sont pas complets.
-- Un projet couvert n'a plus besoin de rien, on ne previent donc pas pour lui.
function projets.QuiAttendent(objet)
    local resultat = {}
    local cible = tonumber(objet)
    if not cible then return resultat end

    for _, projet in ipairs(projets.Tous(false)) do
        local arbres = projets.Calculer(projet.id)
        if arbres then
            local part = NS.moteur.Couverture(arbres)
            if part < 1 then
                -- L'objet est il reclame quelque part dans la chaine ?
                local attendu = false
                local function Parcourir(noeud)
                    if attendu then return end
                    for _, ligne in ipairs(noeud.composants or {}) do
                        if ligne.objet == cible and ligne.manque > 0 then attendu = true return end
                        if ligne.sous then Parcourir(ligne.sous) end
                    end
                end
                for _, arbre in ipairs(arbres) do Parcourir(arbre) end
                if attendu then
                    table.insert(resultat, { projet = projet, couverture = part })
                end
            end
        end
    end
    return resultat
end

-- ---------------------------------------------------------------------------
-- Commandes : un personnage demande un objet, un autre le fabrique
-- ---------------------------------------------------------------------------
-- Une commande est portee par un projet chez le fabricant : son suivi, ses
-- besoins, ce que les autres doivent lui envoyer et la fabrication qui
-- decompte marchent comme pour tout projet. Etats : "demandee" (a fabriquer),
-- "envoyer" (fabriquee, a envoyer), "envoyee", "recue".

NS.commandes = {}
local commandes = NS.commandes

local function Toutes()
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.commandes = type(d.commandes) == "table" and d.commandes or {}
    return d.commandes
end

local function Fiche(cle)
    local d = CraftCoreDB
    return type(d) == "table" and type(d.personnages) == "table" and d.personnages[cle] or nil
end

function commandes.Liste()
    local liste = {}
    for _, c in pairs(Toutes()) do table.insert(liste, c) end
    table.sort(liste, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return liste
end

function commandes.Par(id) return Toutes()[tostring(id)] end

-- Les personnages qui connaissent la recette.
function commandes.Connaisseurs(recette)
    local liste = {}
    for _, f in ipairs(NS.base.TousLesPersonnages()) do
        if type(f.recettesApprises) == "table" and f.recettesApprises[tostring(recette)] == true then
            table.insert(liste, f)
        end
    end
    return liste
end

-- Part des composants deja chez ce personnage (sacs et banque), de 0 a 1.
local function Part(fiche, recette, quantite)
    local r = CraftCoreDB and CraftCoreDB.recettes and CraftCoreDB.recettes[tostring(recette)]
    local total, la = 0, 0
    for _, c in ipairs(r and r.composants or {}) do
        local besoin = (c.quantite or 1) * quantite
        local sacs, banque = NS.inventaire.SacsEtBanque(fiche, c.objet)
        total = total + besoin
        la = la + math.min(besoin, (sacs or 0) + (banque or 0))
    end
    return total > 0 and (la / total) or 0
end
commandes.Part = Part

-- Le mieux place : celui qui a le plus de composants ; a egalite, le
-- demandeur lui-meme, puis le personnage connecte.
function commandes.MeilleurFabricant(recette, quantite, demandeur)
    local meilleur, score
    local moi = NS.ClePersonnage()
    for _, f in ipairs(commandes.Connaisseurs(recette)) do
        local s = Part(f, recette, quantite) + ((f.cle == demandeur) and 0.002 or 0) + ((f.cle == moi) and 0.001 or 0)
        if not score or s > score then meilleur, score = f, s end
    end
    return meilleur and meilleur.cle or nil
end

local function NomDeRecette(recette)
    local r = CraftCoreDB and CraftCoreDB.recettes and CraftCoreDB.recettes[tostring(recette)]
    local objet = r and r.objetProduit
    local info = objet and NS.objets and NS.objets.Info(objet)
    return (info and info.nom) or (r and r.nom) or tostring(recette)
end
commandes.NomDeRecette = NomDeRecette

local function NomCourt(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

-- Le projet qui porte la commande, chez le fabricant.
local function PoserProjet(c)
    if not c.fabricant then return end
    NS.base.AvecPersonnage(c.fabricant, function()
        local projet = projets.Creer(string.format(NS.L.ORDER_PROJECT_NAME, NomDeRecette(c.recette), NomCourt(c.demandeur)))
        if projet then
            projet.commande = c.id
            projets.Ajouter(projet.id, c.recette, c.quantite)
            c.projet = projet.id
        end
    end)
end

local function OterProjet(c)
    if not (c.fabricant and c.projet) then return end
    local fiche = Fiche(c.fabricant)
    if fiche and type(fiche.projets) == "table" then fiche.projets[tostring(c.projet)] = nil end
    c.projet = nil
end

function commandes.ProjetDe(c)
    local fiche = c and c.fabricant and Fiche(c.fabricant)
    return fiche and type(fiche.projets) == "table" and c.projet and fiche.projets[tostring(c.projet)] or nil
end

function commandes.Creer(recette, quantite, demandeur)
    local d = CraftCoreDB
    if type(d) ~= "table" or not recette or not demandeur then return nil end
    quantite = math.max(1, tonumber(quantite) or 1)
    d.prochaineCommande = (tonumber(d.prochaineCommande) or 1)
    local id = d.prochaineCommande
    d.prochaineCommande = id + 1
    local r = d.recettes and d.recettes[tostring(recette)]
    local c = { id = id, recette = tonumber(recette) or recette, objet = r and r.objetProduit, quantite = quantite,
        demandeur = demandeur, fabricant = commandes.MeilleurFabricant(recette, quantite, demandeur),
        etat = "demandee", cree = NS.Appeler(_G.time) }
    Toutes()[tostring(id)] = c
    PoserProjet(c)
    return c
end

function commandes.ConfierA(id, cle)
    local c = commandes.Par(id)
    if not c or c.etat ~= "demandee" or c.fabricant == cle then return end
    OterProjet(c)
    c.fabricant = cle
    PoserProjet(c)
end

function commandes.Annuler(id)
    local c = commandes.Par(id)
    if not c then return end
    OterProjet(c)
    Toutes()[tostring(id)] = nil
end

function commandes.Marquer(id, etat)
    local c = commandes.Par(id)
    if not c then return end
    if etat ~= "demandee" then OterProjet(c) end
    c.etat = etat
    c[etat] = NS.Appeler(_G.time)
end

function commandes.EffacerTerminees()
    for cle, c in pairs(Toutes()) do if c.etat == "recue" then Toutes()[cle] = nil end end
end

-- Une fabrication a vide le projet d'une commande : elle est faite. Pour soi,
-- c'est deja recu ; sinon, c'est a envoyer.
function commandes.ProjetVide(projet)
    local c = projet and projet.commande and commandes.Par(projet.commande)
    if not c then return end
    if #(projet.objets or {}) > 0 then return end
    commandes.Marquer(c.id, c.fabricant == c.demandeur and "recue" or "envoyer")
    NS.Dire(string.format(NS.L.ORDER_CRAFTED, NomDeRecette(c.recette), NomCourt(c.demandeur)))
end

-- Une fabrication faite pour un autre personnage, dans un projet qui lui
-- est destine (sans commande en bonne et due forme) : l'objet est a lui
-- envoyer. Le courrier le proposera, comme pour une commande.
function commandes.AEnvoyerPour(demandeur, recette, quantite)
    local moi = NS.ClePersonnage()
    local d = CraftCoreDB
    if type(d) ~= "table" or not demandeur or not moi or demandeur == moi then return end
    local r = d.recettes and d.recettes[tostring(recette)]
    local objet = r and r.objetProduit
    if not objet then return end
    quantite = math.max(1, tonumber(quantite) or 1)
    for _, c in pairs(Toutes()) do
        if c.etat == "envoyer" and c.fabricant == moi and c.demandeur == demandeur and c.objet == objet then
            c.quantite = (c.quantite or 0) + quantite
            return c
        end
    end
    d.prochaineCommande = (tonumber(d.prochaineCommande) or 1)
    local id = d.prochaineCommande
    d.prochaineCommande = id + 1
    local c = { id = id, recette = tonumber(recette) or recette, objet = objet, quantite = quantite,
        demandeur = demandeur, fabricant = moi, etat = "envoyer", cree = NS.Appeler(_G.time) }
    c.envoyer = c.cree
    Toutes()[tostring(id)] = c
    NS.Dire(string.format(NS.L.ORDER_CRAFTED, NomDeRecette(c.recette), NomCourt(demandeur)))
    return c
end

-- Un courrier est parti vers `cle` avec ces objets : les commandes qu'il
-- contient sont envoyees.
function commandes.Envoye(cle, objets)
    local moi = NS.ClePersonnage()
    for _, c in pairs(Toutes()) do
        if c.etat == "envoyer" and c.fabricant == moi and c.demandeur == cle and c.objet and (objets[c.objet] or 0) > 0 then
            commandes.Marquer(c.id, "envoyee")
        end
    end
end

-- Le demandeur a l'objet : la commande est recue.
function commandes.VerifierReception()
    local moi = NS.base.Personnage()
    if not moi then return end
    for _, c in pairs(Toutes()) do
        if c.etat == "envoyee" and c.demandeur == moi.cle and c.objet then
            local sacs, banque = NS.inventaire.SacsEtBanque(moi, c.objet)
            if (sacs or 0) + (banque or 0) >= (c.quantite or 1) then commandes.Marquer(c.id, "recue") end
        end
    end
end

-- A envoyer par ce personnage : { [demandeur] = { {objet, quantite, id} } }.
function commandes.AEnvoyer(cle)
    local rendu = {}
    for _, c in pairs(Toutes()) do
        if c.etat == "envoyer" and c.fabricant == cle and c.objet then
            rendu[c.demandeur] = rendu[c.demandeur] or {}
            table.insert(rendu[c.demandeur], { objet = c.objet, quantite = c.quantite, id = c.id })
        end
    end
    return rendu
end

function commandes.EstCommande(projet) return type(projet) == "table" and projet.commande ~= nil end
