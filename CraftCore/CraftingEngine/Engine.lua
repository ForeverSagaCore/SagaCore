local _, NS = ...

-- Moteur de decomposition.
--
-- Aucune lecture du jeu ici, aucun affichage : ce fichier ne travaille que sur
-- le catalogue et sur un etat de stock qu'on lui passe. C'est ce qui permet de
-- le verifier par des cas de test, comme le demande le cahier des charges.

NS.moteur = {}
local moteur = NS.moteur

-- Quelle recette fabrique quel objet. Une recette apprise a la priorite sur
-- une recette non apprise qui produirait le meme objet.
function moteur.IndexDesProductions(catalogue, estApprise)
    local index = {}
    for cle, recette in pairs(catalogue or {}) do
        local produit = tonumber(recette.objetProduit)
        if produit then
            local id = tonumber(cle) or cle
            local actuel = index[produit]
            if not actuel then
                index[produit] = id
            elseif estApprise and estApprise(id) and not estApprise(actuel) then
                index[produit] = id
            end
        end
    end
    return index
end

-- Quantite produite par execution. On retient le minimum garanti : promettre
-- le maximum ferait sous-estimer ce qu'il reste a recolter.
local function ProduitParExecution(recette)
    local mini = tonumber(recette.quantiteMin)
    if mini and mini > 0 then return mini end
    return 1
end

local function Plafond(valeur)
    return math.ceil(valeur)
end

local function Copier(source)
    local copie = {}
    for cle, valeur in pairs(source or {}) do copie[cle] = valeur end
    return copie
end

-- Decompose une recette en ce qu'il faut reellement obtenir.
--
-- `contexte` porte :
--   catalogue    le catalogue des recettes
--   disponible   table objet vers quantite encore libre, decrementee au fil du
--                parcours pour qu'un meme objet ne serve jamais deux fois
--   index        objet produit vers recette, voir plus haut
--   estApprise   fonction optionnelle
--   enCours      recettes de la branche courante, pour couper les cycles
--   profondeur   garde-fou supplementaire
local PROFONDEUR_MAX = 12

local function Descendre(contexte, idRecette, quantiteVoulue, profondeur)
    local recette = contexte.catalogue[tostring(idRecette)]
    if not recette then return nil end

    local parExecution = ProduitParExecution(recette)
    local executions = math.max(1, Plafond(quantiteVoulue / parExecution))

    local noeud = {
        recette = idRecette,
        nom = recette.nom,
        objetProduit = tonumber(recette.objetProduit),
        quantiteVoulue = quantiteVoulue,
        executions = executions,
        produite = executions * parExecution,
        apprise = contexte.estApprise and contexte.estApprise(idRecette) or false,
        composants = {},
    }

    -- Un lot produit plus que demande : le surplus reste disponible pour une
    -- autre branche, sinon on ferait recolter deux fois la meme matiere.
    local surplus = noeud.produite - quantiteVoulue
    if surplus > 0 and noeud.objetProduit then
        contexte.disponible[noeud.objetProduit] = (contexte.disponible[noeud.objetProduit] or 0) + surplus
    end

    for _, composant in ipairs(recette.composants or {}) do
        local besoin = composant.quantite * executions
        local libre = contexte.disponible[composant.objet] or 0
        local pris = math.min(libre, besoin)
        contexte.disponible[composant.objet] = libre - pris
        -- Ce qui est pris dans les stocks du personnage lui-meme : c'est ce
        -- qui doit passer de sa banque a ses sacs pour fabriquer.
        if pris > 0 then
            contexte.prisPropres[composant.objet] = (contexte.prisPropres[composant.objet] or 0) + pris
        end

        -- Puis chez les autres personnages, quand on les distingue : ce qui y
        -- est pris compte comme possede, mais se rapatrie.
        local rapatrie = 0
        if contexte.ailleurs and pris < besoin then
            local la = contexte.ailleurs[composant.objet] or 0
            rapatrie = math.min(la, besoin - pris)
            contexte.ailleurs[composant.objet] = la - rapatrie
            if rapatrie > 0 then
                contexte.rapatries[composant.objet] = (contexte.rapatries[composant.objet] or 0) + rapatrie
            end
            pris = pris + rapatrie
        end
        local manque = besoin - pris

        local ligne = {
            objet = composant.objet,
            besoin = besoin,
            pris = pris,
            rapatrie = rapatrie > 0 and rapatrie or nil,
            manque = manque,
        }

        if manque > 0 then
            local sousRecette = contexte.index[composant.objet]
            -- Choix de l'utilisateur : obtenir cet objet tel quel plutot que
            -- de le fabriquer. On s'arrete donc la, et il compte comme matiere
            -- a se procurer.
            if contexte.obtenirTelQuel and contexte.obtenirTelQuel[composant.objet] then
                sousRecette = nil
                ligne.obtenirTelQuel = true
            end
            if sousRecette then
                if contexte.enCours[sousRecette] then
                    -- Dependance circulaire : on s'arrete et on le dit.
                    ligne.cycle = true
                elseif profondeur >= PROFONDEUR_MAX then
                    ligne.tropProfond = true
                else
                    -- Une transformation que ce personnage ne sait pas faire
                    -- est montree, mais elle ne doit rien reserver : on la
                    -- calcule sur une copie des stocks, sinon ses composants
                    -- manqueraient a tort aux autres branches.
                    local apprise = contexte.estApprise and contexte.estApprise(sousRecette) or false
                    local sauvegarde
                    if not apprise then
                        sauvegarde = { contexte.disponible, contexte.ailleurs, contexte.rapatries, contexte.prisPropres }
                        contexte.disponible = Copier(contexte.disponible)
                        contexte.ailleurs = contexte.ailleurs and Copier(contexte.ailleurs) or nil
                        contexte.rapatries = Copier(contexte.rapatries)
                        contexte.prisPropres = Copier(contexte.prisPropres)
                    end
                    contexte.enCours[sousRecette] = true
                    ligne.sous = Descendre(contexte, sousRecette, manque, profondeur + 1)
                    contexte.enCours[sousRecette] = nil
                    if sauvegarde then
                        contexte.disponible, contexte.ailleurs, contexte.rapatries, contexte.prisPropres =
                            sauvegarde[1], sauvegarde[2], sauvegarde[3], sauvegarde[4]
                    end
                    if ligne.sous and not ligne.sous.apprise then
                        -- Transformation possible sur le papier mais pas par ce
                        -- personnage : elle ne compte pas comme realisable.
                        ligne.sous.transformationIndisponible = true
                    end
                end
            end
        end

        table.insert(noeud.composants, ligne)
    end

    return noeud
end

-- Point d'entree. `stocks` est une table objet vers quantite possedee.
function moteur.Decomposer(catalogue, stocks, idRecette, quantite, estApprise)
    if type(catalogue) ~= "table" then return nil end
    local disponible = {}
    for objet, quantitePossedee in pairs(stocks or {}) do
        disponible[tonumber(objet) or objet] = quantitePossedee
    end
    local contexte = {
        catalogue = catalogue,
        disponible = disponible,
        rapatries = {},
        prisPropres = {},
        index = moteur.IndexDesProductions(catalogue, estApprise),
        estApprise = estApprise,
        enCours = { [idRecette] = true },
        obtenirTelQuel = moteur.obtenirTelQuel,
    }
    return Descendre(contexte, idRecette, quantite or 1, 1)
end

-- Matieres a obtenir au bout de la chaine, c'est a dire ce qui n'est fabrique
-- par aucune recette connue, ou ce dont la fabrication est hors de portee.
function moteur.MatieresAObtenir(noeud, cumul)
    cumul = cumul or {}
    if not noeud then return cumul end
    for _, ligne in ipairs(noeud.composants or {}) do
        if ligne.manque > 0 then
            if ligne.sous and not ligne.sous.transformationIndisponible and not ligne.cycle and not ligne.tropProfond then
                moteur.MatieresAObtenir(ligne.sous, cumul)
            else
                cumul[ligne.objet] = (cumul[ligne.objet] or 0) + ligne.manque
            end
        end
    end
    return cumul
end

-- Calcul global : plusieurs fabrications d'un coup, en partageant le meme
-- stock. C'est ce partage qui mutualise les composants communs : une barre
-- servie a la premiere fabrication n'est plus disponible pour la suivante.
--
-- `lignes` est une liste de { recette = id, quantite = n }.
-- `stocksAilleurs`, optionnel, est puise apres `stocks` ; ce qui y est pris est
-- rendu en troisieme resultat, objet vers quantite a rapatrier. Le quatrieme
-- dit ce qui est pris dans `stocks` lui-meme, objet vers quantite.
function moteur.DecomposerPlusieurs(catalogue, stocks, lignes, estApprise, stocksAilleurs)
    if type(catalogue) ~= "table" or type(lignes) ~= "table" then return nil end

    local function Normaliser(source)
        local t = {}
        for objet, quantite in pairs(source or {}) do
            t[tonumber(objet) or objet] = quantite
        end
        return t
    end

    -- Un seul contexte pour toutes les lignes : les stocks y sont partages,
    -- et une copie faite pour une branche non apprise y est restauree.
    local contexte = {
        catalogue = catalogue,
        disponible = Normaliser(stocks),
        ailleurs = stocksAilleurs and Normaliser(stocksAilleurs) or nil,
        rapatries = {},
        prisPropres = {},
        index = moteur.IndexDesProductions(catalogue, estApprise),
        estApprise = estApprise,
        obtenirTelQuel = moteur.obtenirTelQuel,
    }
    local arbres = {}
    for _, ligne in ipairs(lignes) do
        contexte.enCours = { [ligne.recette] = true }
        local arbre = Descendre(contexte, ligne.recette, ligne.quantite or 1, 1)
        if arbre then table.insert(arbres, arbre) end
    end

    -- Ce qu'il faut obtenir au total, une fois tout mutualise.
    local matieres = {}
    for _, arbre in ipairs(arbres) do
        moteur.MatieresAObtenir(arbre, matieres)
    end

    return arbres, matieres, contexte.rapatries, contexte.prisPropres
end

-- Part des besoins deja couverte par ce qu'on possede, entre 0 et 1.
-- Definition : sur l'ensemble des composants directs de toutes les
-- fabrications, la part des unites deja disponibles. Un besoin nul vaut 1.
function moteur.Couverture(arbres)
    local besoin, couvert = 0, 0
    local function Parcourir(noeud)
        for _, ligne in ipairs(noeud.composants or {}) do
            besoin = besoin + ligne.besoin
            couvert = couvert + ligne.pris
            -- Une transformation que ce personnage ne sait pas faire ne couvre
            -- rien : ses composants ne comptent pas.
            if ligne.sous and not ligne.sous.transformationIndisponible then
                Parcourir(ligne.sous)
            end
        end
    end
    for _, arbre in ipairs(arbres or {}) do Parcourir(arbre) end
    if besoin == 0 then return 1, 0, 0 end
    return couvert / besoin, couvert, besoin
end

-- Objets que l'utilisateur a decide d'obtenir tel quel. Pose avant un calcul,
-- il coupe la descente sur ces objets.
function moteur.PoserObtenirTelQuel(table_)
    moteur.obtenirTelQuel = table_
end
