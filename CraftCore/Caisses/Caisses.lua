local _, NS = ...

-- Caisses.
--
-- Tout ce qui suit vient du relevé fait sur le client, jamais d'une supposition.
-- Ce que le client dit d'une caisse : son nom, et une ligne d'utilisation qui
-- enumere les packs acceptes, chacun sur sa propre ligne sous la forme
-- "- 20 doses de poussiere d'ame".
--
-- Ce que le client ne dit PAS : ce qu'il y a deja dedans. Aucun remplissage
-- n'est donc affiche, car il serait invente.

NS.caisses = {}
local caisses = NS.caisses

-- Une ligne de pack commence par un tiret, puis un nombre, puis un libelle.
local MOTIF_PACK = "^%s*%-%s*(%d+)%s+(.+)$"

-- Le client francais met une espace insecable entre le nombre et le mot
-- ("20 doses"), et parfois une espace fine ; ni l'une ni l'autre n'est une
-- espace pour Lua. L'apostrophe typographique vaut l'apostrophe droite. Tout
-- texte compare passe par ici, des deux cotes.
local function Normaliser(texte)
    if type(texte) ~= "string" then return texte end
    texte = string.gsub(texte, "\194\160", " ")          -- espace insecable
    texte = string.gsub(texte, "\226\128\175", " ")     -- espace fine insecable
    texte = string.gsub(texte, "\226\128\137", " ")     -- espace fine
    texte = string.gsub(texte, "\226\128\153", "'")     -- apostrophe typographique
    return texte
end

-- Minuscules, lettres accentuees comprises : string.lower laisse "É" en
-- majuscule, et "Étoffe de lin" ne se reconnaissait plus dans "unites
-- d'étoffe de lin". Les capitales latines accentuees (UTF-8 C3 80 a C3 9E,
-- sauf le signe multiplie) passent en minuscules.
local function Minuscules(texte)
    if type(texte) ~= "string" then return texte end
    texte = string.lower(texte)
    texte = string.gsub(texte, "\195([\128-\158])", function(c)
        local b = string.byte(c)
        if b == 151 then return "\195" .. c end
        return "\195" .. string.char(b + 32)
    end)
    texte = string.gsub(texte, "\197\146", "\197\147")   -- Œ
    return texte
end
caisses.Minuscules = Minuscules

-- Pour comparer, sans accents non plus : le client ecrit "Eglantine" et
-- "Etoffe de lin" sur l'objet, mais "pousses d'églantine" et "unités
-- d'étoffe de lin" dans la caisse.
local SANS_ACCENT = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
    ["ç"] = "c", ["ÿ"] = "y", ["œ"] = "oe", ["æ"] = "ae",
}
local function Plier(texte)
    texte = Minuscules(texte)
    if type(texte) ~= "string" then return texte end
    return (string.gsub(texte, "[\195\197][\128-\191]", function(c) return SANS_ACCENT[c] end))
end
caisses.Plier = Plier

-- Objets de base que les caisses demandent souvent : le jeu les nomme des
-- qu'on les lui demande, meme si personne n'en a et qu'aucune recette relevee
-- ne s'en sert (sinon le pack restait sans icone ni compte).
local OBJETS_DE_BASE = {
    -- etoffes et cuirs
    2589, 2592, 4306, 4338, 14047, 2318, 2319, 4234, 4304, 8170,
    -- plantes
    765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821,
    -- minerais, barres, pierres
    2770, 2771, 2772, 2775, 2776, 2840, 3576, 2841, 3575, 3577, 3859, 2835, 2836, 2838,
    -- pieces d'ingenieur
    4357, 4359, 4361, 4363, 4364, 4371, 4375, 4377, 4382,
}

-- Reconnait une caisse du systeme a sa ligne d'utilisation. Le nom seul ne
-- suffirait pas : un vieil objet de quete peut s'appeler caisse aussi.
local function LignesDePacks(lignes)
    local packs = {}
    for _, ligne in ipairs(lignes or {}) do
        for morceau in string.gmatch(Normaliser(ligne), "[^\r\n]+") do
            local quantite, libelle = string.match(morceau, MOTIF_PACK)
            if quantite and libelle then
                -- Les codes de couleur du client ne font pas partie du libelle.
                libelle = string.gsub(libelle, "|c%x%x%x%x%x%x%x%x", "")
                libelle = string.gsub(libelle, "|cnIQ%d+:?", "")
                libelle = string.gsub(libelle, "|r", "")
                libelle = string.gsub(libelle, "^%s+", "")
                libelle = string.gsub(libelle, "%s+$", "")
                if libelle ~= "" then
                    table.insert(packs, { quantite = tonumber(quantite), libelle = libelle })
                end
            end
        end
    end
    return packs
end

-- Objets du compte, nom en minuscules vers identifiant et quantite. Sert a
-- rapprocher un libelle de pack de ce qu'on possede reellement.
local parNomMemo, parNomQuand
local function StocksParNomBrut()
    local parNom = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        -- L'autre camp ne peut rien fournir : meme regle que partout.
        for cle, entree in pairs(NS.inventaire.MemeCamp(fiche) and NS.base.StocksDe(fiche) or {}) do
            local id = tonumber(cle)
            if id then
                local info = NS.objets.Info(id)
                if info and info.nom then
                    local nom = Minuscules(info.nom)
                    parNom[nom] = parNom[nom] or { id = id, total = 0 }
                    parNom[nom].total = parNom[nom].total + (entree.total or 0)
                end
            end
        end
    end
    -- Les objets que personne n'a encore mais que le compte connait : ce que
    -- les recettes relevees fabriquent ou consomment. Un pack de rouleaux de
    -- lin est ainsi reconnu (icone, nom) meme a zero.
    local function Connu(id, nomDeSecours)
        id = tonumber(id)
        if not id then return end
        local info = NS.objets.Info(id)
        local nom = (info and info.nom) or nomDeSecours
        if nom then
            nom = Minuscules(nom)
            if not parNom[nom] then parNom[nom] = { id = id, total = 0 } end
        end
    end
    for _, recette in pairs((CraftCoreDB and CraftCoreDB.recettes) or {}) do
        if type(recette) == "table" then
            -- Le nom de la recette vaut celui de l'objet tant que le jeu ne l'a
            -- pas encore en memoire ("Rouleau d'etoffe de lin").
            Connu(recette.objetProduit, recette.nom)
            for _, comp in ipairs(recette.composants or {}) do Connu(comp.objet) end
        end
    end
    for _, id in ipairs(OBJETS_DE_BASE) do Connu(id) end
    -- Les objets deja retrouves une fois par leur nom (au survol, ou le jeu
    -- les avait en memoire) : reconnus ensuite meme hors de la memoire du jeu.
    for nom, id in pairs((CraftCoreDB and CraftCoreDB.objetsParNom) or {}) do
        if type(nom) == "string" and tonumber(id) and not parNom[Minuscules(nom)] then
            parNom[Minuscules(nom)] = { id = tonumber(id), total = 0 }
        end
    end
    return parNom
end
local function StocksParNom()
    local maintenant = (NS.Appeler(_G.GetTime) or 0)
    if parNomMemo and parNomQuand and maintenant - parNomQuand < 2 then return parNomMemo end
    parNomMemo, parNomQuand = StocksParNomBrut(), maintenant
    return parNomMemo
end
function caisses.OublierNoms() parNomMemo = nil end

-- Un objet retrouve par son nom : garde pour la suite.
function caisses.RetenirNom(nom, id)
    if type(nom) ~= "string" or not tonumber(id) or type(CraftCoreDB) ~= "table" then return end
    CraftCoreDB.objetsParNom = CraftCoreDB.objetsParNom or {}
    nom = Minuscules(nom)
    if CraftCoreDB.objetsParNom[nom] ~= tonumber(id) then
        CraftCoreDB.objetsParNom[nom] = tonumber(id)
        parNomMemo = nil
    end
end

-- Le libelle d'un pack est au pluriel et porte une unite : "4 essences
-- astrales superieures" face a l'objet "Essence astrale superieure". On compare
-- donc des formes sans marque de pluriel, des deux cotes.
local function SansPluriel(texte)
    local sortie = {}
    for brut in string.gmatch(Plier(Normaliser(texte)), "[^%s]+") do
        local mot = string.gsub(brut, "s$", "")
        mot = string.gsub(mot, "x$", "")
        table.insert(sortie, mot)
    end
    return table.concat(sortie, " ")
end

-- Rapproche un libelle de pack d'un objet possede, en cherchant le nom d'objet
-- contenu dans le libelle. Sans correspondance nette, on ne devine pas : nil.
local FORMES = {}
local RapprocherCalcul
local DEJA = {}
local function RapprocherDUnObjet(libelle, parNom)
    -- Meme liste de noms, meme libelle : meme reponse (le panneau le demande
    -- pour chaque caisse de chaque personnage a chaque rafraichissement).
    parNom[DEJA] = parNom[DEJA] or {}
    local deja = parNom[DEJA][libelle]
    if deja ~= nil then return deja or nil end
    local r = RapprocherCalcul(libelle, parNom)
    parNom[DEJA][libelle] = r or false
    return r
end
RapprocherCalcul = function(libelle, parNom)
    local recherche = SansPluriel(libelle)
    local meilleur, meilleureLongueur
    -- Les formes sans pluriel sont calculees une fois par liste de noms.
    if not parNom[FORMES] then
        local formes = {}
        for nom, entree in pairs(parNom) do
            if type(nom) == "string" then table.insert(formes, { SansPluriel(nom), entree }) end
        end
        parNom[FORMES] = formes
    end
    for _, f in ipairs(parNom[FORMES]) do
        local compare, entree = f[1], f[2]
        if #compare >= 4 and string.find(recherche, compare, 1, true) then
            if not meilleureLongueur or #compare > meilleureLongueur then
                meilleur, meilleureLongueur = entree, #compare
            end
        end
    end
    return meilleur
end

-- Prefixe d'une famille de caisses, la partie avant le deux points.
-- "Caisse detournee : etoffes d'apprenti" donne "Caisse detournee".
local function PrefixeDe(nom)
    if type(nom) ~= "string" then return nil end
    local prefixe = string.match(Normaliser(nom), "^(.-)%s*:")
    if prefixe and #prefixe >= 4 then return string.lower(prefixe) end
    return nil
end

-- Prefixes appris des caisses reconnues a coup sur, c'est a dire celles dont
-- l'infobulle liste des packs. Ils servent ensuite a reconnaitre les caisses
-- de la meme famille dont l'infobulle ne dit rien, sans coder de nom en dur ni
-- dependre de la langue.
local function PrefixesConnus()
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.prefixesDeCaisses = d.prefixesDeCaisses or {}
    return d.prefixesDeCaisses
end

-- Lire l'infobulle de chaque objet coute cher. On ne refait le tour que
-- lorsque les sacs ont change, pas a chaque affichage de la page.
local dernierTour
-- Infobulle deja lue d'un objet charge : on ne la relit plus.
local analyses = {}

function caisses.MarquerARelever()
    dernierTour = nil
    parNomMemo = nil
end

-- Caisses actuellement dans les conteneurs, avec leurs packs.
function caisses.Relever(forcer)
    if dernierTour and not forcer then return dernierTour end
    local j = NS.jeu
    if not j.nombreEmplacements or not j.objetDeLEmplacement then return {} end

    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.caissesConnues = d.caissesConnues or {}

    local prefixes = PrefixesConnus()
    -- Compte rendu du tour : quand rien n'est trouve, il dit a quelle etape ca
    -- s'arrete, au lieu de laisser deviner.
    local bilan = { quand = NS.Horodatage(), objets = 0, charges = 0,
        avecInfobulle = 0, avecPacks = 0, exemples = {} }
    -- Objets a examiner : ceux des conteneurs qui repondent maintenant, plus
    -- ceux du dernier releve enregistre. Une banque fermee ne repond plus, mais
    -- son contenu reste connu : sans cela une caisse rangee en banque serait
    -- invisible.
    local aExaminer, ordre = {}, {}
    for conteneur = -5, 20 do
        local emplacements = tonumber(NS.Appeler(j.nombreEmplacements, conteneur)) or 0
        for emplacement = 1, emplacements do
            local id = tonumber(NS.Appeler(j.objetDeLEmplacement, conteneur, emplacement))
            if id then
                if aExaminer[id] then
                    aExaminer[id].exemplaires = aExaminer[id].exemplaires + 1
                else
                    aExaminer[id] = { conteneur = conteneur, exemplaires = 1 }
                    table.insert(ordre, id)
                end
            end
        end
    end

    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        for cle, entree in pairs(NS.base.StocksDe(fiche)) do
            local id = tonumber(cle)
            if id and not aExaminer[id] then
                aExaminer[id] = { conteneur = nil, exemplaires = tonumber(entree.total) or 1, memorise = true }
                table.insert(ordre, id)
            end
        end
    end

    local candidats, vues = {}, {}
    do
        for _, id in ipairs(ordre) do
            local ou = aExaminer[id]
            local conteneur, emplacement = ou.conteneur, 0
            if id and vues[id] then
                -- Deja rencontree : on compte un exemplaire de plus, sans
                -- creer une seconde ligne.
                vues[id].exemplaires = vues[id].exemplaires + 1
            elseif id then
                local deja = analyses[id]
                local info, charge, lignes, voie, packs
                if deja then
                    info, charge, lignes, voie, packs = deja.info, true, deja.lignes, deja.voie, deja.packs
                else
                    info = NS.objets.Info(id)
                    charge = NS.objets.EstCharge(id)
                    lignes, voie = NS.objets.LignesDInfobulle(id)
                    packs = LignesDePacks(lignes)
                    if charge and lignes and info and info.nom then
                        analyses[id] = { info = info, lignes = lignes, voie = voie, packs = packs }
                    end
                end
                bilan.objets = bilan.objets + 1
                if charge then bilan.charges = bilan.charges + 1 end
                if lignes then bilan.avecInfobulle = bilan.avecInfobulle + 1 end
                if #packs > 0 then bilan.avecPacks = bilan.avecPacks + 1 end
                if #bilan.exemples < 5 then
                    table.insert(bilan.exemples, {
                        id = id,
                        nom = info and info.nom,
                        charge = charge,
                        voie = voie,
                        nbLignes = lignes and #lignes or 0,
                        premiereLigne = lignes and lignes[1] or nil,
                        nbPacks = #packs,
                    })
                end
                local candidat = {
                    id = id,
                    nom = (info and info.nom) or tostring(id),
                    qualite = info and info.qualite,
                    conteneur = conteneur,
                    packs = packs,
                    exemplaires = 1,
                }
                candidat.exemplaires = ou.exemplaires
                candidat.memorise = ou.memorise
                vues[id] = candidat
                table.insert(candidats, candidat)
                if #packs > 0 then
                    local prefixe = PrefixeDe(info and info.nom)
                    if prefixe then prefixes[prefixe] = true end
                end
            end
        end
    end

    -- Second passage : une caisse de la meme famille qu'une caisse certaine est
    -- retenue meme si son infobulle ne liste rien.
    local trouvees = {}
    for _, candidat in ipairs(candidats) do
        local prefixe = PrefixeDe(candidat.nom)
        if #candidat.packs > 0 or (prefixe and prefixes[prefixe]) then
            candidat.vueLe = NS.Horodatage()
            table.insert(trouvees, candidat)
            d.caissesConnues[tostring(candidat.id)] = candidat
        end
    end

    bilan.caissesRetenues = #trouvees
    d.bilanDesCaisses = bilan

    table.sort(trouvees, function(a, b) return a.nom < b.nom end)
    dernierTour = trouvees
    return trouvees
end

-- Qui detient une caisse, et combien, d'apres le releve de chaque personnage.
local function Detenteurs(id)
    local chez = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        local entree = NS.base.StocksDe(fiche)[tostring(id)]
        local n = type(entree) == "table" and tonumber(entree.total) or 0
        if fiche.cle and n > 0 then chez[fiche.cle] = n end
    end
    return chez
end

-- Caisses d'un personnage. Chaque caisse appartient a qui la porte ou la
-- range : avec `avecAutres`, celles des autres personnages s'ajoutent, chacune
-- avec son proprietaire. Une caisse presente chez deux personnages donne deux
-- lignes.
function caisses.Connues(cle, avecAutres)
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    local liste = {}
    for _, caisse in pairs(d.caissesConnues or {}) do
        for proprietaire, n in pairs(Detenteurs(caisse.id)) do
            if proprietaire == cle or avecAutres then
                local ligne = {}
                for k, v in pairs(caisse) do ligne[k] = v end
                ligne.proprietaire = proprietaire
                ligne.exemplaires = n
                table.insert(liste, ligne)
            end
        end
    end
    table.sort(liste, function(a, b)
        local sa, sb = a.proprietaire == cle and 0 or 1, b.proprietaire == cle and 0 or 1
        if sa ~= sb then return sa < sb end
        if a.proprietaire ~= b.proprietaire then return (a.proprietaire or "") < (b.proprietaire or "") end
        return (a.nom or "") < (b.nom or "")
    end)
    return liste
end

-- Nombre de caisses chez les autres personnages, pour le dire quand on ne
-- les montre pas.
function caisses.ChezLesAutres(cle)
    local n = 0
    for _, ligne in ipairs(caisses.Connues(cle, true)) do
        if ligne.proprietaire ~= cle then n = n + 1 end
    end
    return n
end

-- Pour chaque pack d'une caisse, ce qu'on possede et ce qui manque. Quand le
-- libelle ne se rapproche d'aucun objet possede, on le dit au lieu d'afficher
-- un zero qui ferait croire a un manque constate.
function caisses.Etat(caisse)
    local parNom = StocksParNom()
    local resultat = {}
    local ficheLui
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if fiche.cle == caisse.proprietaire then ficheLui = fiche break end
    end
    for _, pack in ipairs(caisse.packs or {}) do
        local objet = RapprocherDUnObjet(pack.libelle, parNom)
        local ligne = { libelle = pack.libelle, requis = pack.quantite }
        if objet then
            -- Ce que le proprietaire de la caisse detient lui-meme ; le reste
            -- du compte est dit a part, il faudrait le lui envoyer.
            local lui = objet.total
            if ficheLui then
                local entree = NS.base.StocksDe(ficheLui)[tostring(objet.id)]
                lui = type(entree) == "table" and tonumber(entree.total) or 0
            end
            ligne.objet = objet.id
            ligne.possede = lui
            ligne.ailleurs = math.max(0, objet.total - lui)
            ligne.manque = math.max(0, pack.quantite - lui)
        end
        table.insert(resultat, ligne)
    end
    table.sort(resultat, function(a, b)
        local fa = (a.manque == 0 and a.possede) and 0 or 1
        local fb = (b.manque == 0 and b.possede) and 0 or 1
        if fa ~= fb then return fa < fb end
        return a.libelle < b.libelle
    end)
    return resultat
end

-- Combien de packs sont fournissables tout de suite.
function caisses.PacksPrets(caisse)
    local prets, total = 0, 0
    for _, ligne in ipairs(caisses.Etat(caisse)) do
        total = total + 1
        if ligne.possede and ligne.manque == 0 then prets = prets + 1 end
    end
    return prets, total
end
