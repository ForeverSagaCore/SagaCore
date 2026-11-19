local _, NS = ...

-- Approvisionnement.
--
-- Ce que tout ce qui est planifie reclame encore, une fois les stocks deduits
-- et la chaine descendue. Pour chaque matiere, ce qu'on sait d'elle et rien de
-- plus : nulle part on ne dit ou la recolter ni a quel prix, le client ne le
-- donne pas et l'inventer serait pire que se taire.

NS.approvisionnement = {}
local approvisionnement = NS.approvisionnement

local function Fiche()
    return NS.base.FicheAffichee()
end

-- Choix de methode, retenu par personnage : fabriquer la matiere, ou se la
-- procurer telle quelle.
function approvisionnement.ObtenirTelQuel()
    local fiche = Fiche()
    if not fiche then return {} end
    fiche.obtenirTelQuel = fiche.obtenirTelQuel or {}
    return fiche.obtenirTelQuel
end

function approvisionnement.EstObtenuTelQuel(objet)
    return approvisionnement.ObtenirTelQuel()[tostring(objet)] == true
end

function approvisionnement.BasculerMethode(objet)
    local choix = approvisionnement.ObtenirTelQuel()
    local cle = tostring(objet)
    if choix[cle] then choix[cle] = nil else choix[cle] = true end
end

-- Transmet les choix au moteur avant un calcul.
local function PoserLesChoix()
    local choix = approvisionnement.ObtenirTelQuel()
    local parIdentifiant = {}
    for cle in pairs(choix) do
        local id = tonumber(cle)
        if id then parIdentifiant[id] = true end
    end
    NS.moteur.PoserObtenirTelQuel(parIdentifiant)
end

-- Tout ce qu'il reste a obtenir, projets actifs et fabrications rapides
-- confondus. C'est la liste de courses.
--
-- Le calcul puise d'abord dans les stocks du personnage, puis chez ses autres
-- personnages, et note ce qu'il y a pris : c'est ce qu'il faut rapatrier. Ce
-- que personne n'a reste a obtenir. Avant, tout le compte etait verse dans un
-- seul stock : ce qu'il fallait rapatrier n'apparaissait pas, et ce qui
-- manquait a tout le monde etait annonce comme a rapatrier.
function approvisionnement.Liste(filtre)
    PoserLesChoix()
    local _, matieres, rapatries = NS.projets.CalculerTout(
        NS.projets.StocksDuPersonnage(), NS.projets.StocksDesAutres(), filtre)
    NS.moteur.PoserObtenirTelQuel(nil)
    if not matieres then return {} end
    rapatries = rapatries or {}

    local objets = {}
    for objet, quantite in pairs(matieres) do
        if quantite > 0 then objets[objet] = true end
    end
    for objet, quantite in pairs(rapatries) do
        if quantite > 0 then objets[objet] = true end
    end

    local liste = {}
    for objet in pairs(objets) do
        do
            local ligne = {
                objet = objet,
                manque = matieres[objet] or 0,
                ailleurs = rapatries[objet] or 0,
                telQuel = approvisionnement.EstObtenuTelQuel(objet),
            }

            -- Une recette connue produit elle cette matiere ? Si oui, on peut
            -- proposer de la fabriquer plutot que de la chercher.
            local catalogue = CraftCoreDB and CraftCoreDB.recettes
            if type(catalogue) == "table" then
                for cle, recette in pairs(catalogue) do
                    if tonumber(recette.objetProduit) == objet then
                        ligne.recette = tonumber(cle) or cle
                        ligne.recetteApprise = NS.recettes.EstApprise(cle)
                        if ligne.recetteApprise then break end
                    end
                end
            end

            table.insert(liste, ligne)
        end
    end

    table.sort(liste, function(a, b)
        -- Ce qui dort chez un autre personnage en premier : c'est le plus
        -- rapide a regler.
        local ra = (a.ailleurs > 0) and 0 or 1
        local rb = (b.ailleurs > 0) and 0 or 1
        if ra ~= rb then return ra < rb end
        local ta, tb = a.manque + a.ailleurs, b.manque + b.ailleurs
        if ta ~= tb then return ta > tb end
        return tostring(a.objet) < tostring(b.objet)
    end)
    return liste
end

-- Decompte rapide pour le reste de l'ecran.
function approvisionnement.Resume()
    local liste = approvisionnement.Liste()
    local aRapatrier, aObtenir = 0, 0
    for _, ligne in ipairs(liste) do
        if ligne.ailleurs > 0 then aRapatrier = aRapatrier + 1 else aObtenir = aObtenir + 1 end
    end
    return #liste, aRapatrier, aObtenir
end
