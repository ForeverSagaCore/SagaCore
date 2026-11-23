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

-- ===========================================================================
-- Sources d'equipement : d'ou peut venir un objet qui ameliore le personnage
-- ===========================================================================
--
-- Six origines :
--   possede      : deja chez un de ses personnages (sacs, banque) ;
--   craftInterne : un de ses personnages sait le faire, ou pourra (metier
--                  connu, recette a apprendre) ;
--   craftExterne : aucun de ses personnages n'a le metier : un artisan ;
--   monde        : laisse par une creature ou un objet, hors donjon et raid ;
--   quetes       : recompense de quete (camp, classe et niveau respectes) ;
--   donjons      : laisse par une creature de donjon ou de raid.
-- Les quatre dernieres viennent de la base QuestieDB installee avec QuestCore,
-- lue une fois, petit a petit, sans figer le jeu.

NS.sources = {}
local sources = NS.sources
sources.ORDRE = { "possede", "craftInterne", "craftExterne", "monde", "quetes", "donjons" }

local function Base(nom)
    local e = _G[nom]
    if type(e) == "table" and type(e.Get) == "function" then return e end
    return nil
end
local function Lire(nom, id, champ)
    local e = Base(nom)
    if not e or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end
sources.Lire = Lire

-- Zones des donjons et raids, d'apres la base (la meme table que QuestCore).
local zonesDonjon
local function ZonesDonjon()
    if zonesDonjon then return zonesDonjon end
    zonesDonjon = {}
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local brut = support and support.private and support.private.dungeons
    if type(brut) == "string" then
        local fn = loadstring(brut)
        local ok, t = false, nil
        if fn then ok, t = pcall(fn) end
        brut = ok and t or nil
    end
    -- Chaque zone (et ses sous-zones) pointe vers la zone du donjon.
    for zone, d in pairs(type(brut) == "table" and brut or {}) do
        zonesDonjon[zone] = zone
        for _, autre in ipairs(type(d) == "table" and type(d[2]) == "table" and d[2] or {}) do zonesDonjon[autre] = zone end
    end
    return zonesDonjon
end
sources.ZonesDonjon = ZonesDonjon

-- Index des objets equipables de la base, par emplacement.
local index, etatIndex = {}, "absent"
function sources.Etat() return etatIndex end

local function CodeEtClasse(id)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture then return nil end
    local ok, _, _, _, code, _, classe, sousClasse = pcall(lecture, id)
    if not ok or (classe ~= 2 and classe ~= 4) then return nil end
    local ref = NS.emplacements.DeLObjet(id)
    if not ref then return nil end
    return ref, classe, sousClasse, code
end

function sources.Construire(auFini)
    if etatIndex ~= "absent" then return end
    local base = Base("ItemDB")
    if not (base and base.GetAllIds) then etatIndex = "sansBase" return end
    local ok, ids = pcall(base.GetAllIds)
    if not ok or type(ids) ~= "table" then etatIndex = "sansBase" return end
    etatIndex = "construction"
    local donjons = ZonesDonjon()
    local rang, cadre = 1, CreateFrame("Frame")
    cadre:SetScript("OnUpdate", function(self)
        local fin = math.min(#ids, rang + 300)
        for i = rang, fin do
            local id = ids[i]
            local code, classe, sousClasse = CodeEtClasse(id)
            if code then
                local quetes = Lire("ItemDB", id, "questRewards")
                local pnjs = Lire("ItemDB", id, "npcDrops")
                local objets = Lire("ItemDB", id, "objectDrops")
                local e = { id = id, classe = classe, sous = sousClasse }
                if type(quetes) == "table" and #quetes > 0 then e.quetes = quetes end
                if type(pnjs) == "table" then
                    for _, pnj in ipairs(pnjs) do
                        local zone = tonumber(Lire("NpcDB", pnj, "zoneID"))
                        if zone and donjons[zone] then
                            e.donjon = e.donjon or { pnj = pnj, zone = zone }
                        else
                            e.monde = e.monde or { pnj = pnj, zone = zone }
                        end
                    end
                end
                if not e.monde and type(objets) == "table" and objets[1] then e.monde = { objet = objets[1] } end
                if e.quetes or e.donjon or e.monde then
                    index[code] = index[code] or {}
                    table.insert(index[code], e)
                end
            end
        end
        rang = fin + 1
        if rang > #ids then
            etatIndex = "pret"
            self:SetScript("OnUpdate", nil)
            if auFini then pcall(auFini) end
        end
    end)
end

-- Armes que chaque classe peut apprendre (sous-classes du jeu).
local ARMES = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID = { 4, 5, 10, 13, 15 },
}
local BOUCLIER = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIQUE = { PALADIN = 7, DRUID = 8, SHAMAN = 9 }

-- Un objet est-il portable par ce personnage (matiere, arme, bouclier) ?
function sources.Portable(classe, sous, fiche)
    local jeton = fiche and fiche.jetonClasse
    if classe == 4 then
        if sous == 6 then return jeton == nil or BOUCLIER[jeton] == true end
        if sous == 7 or sous == 8 or sous == 9 or sous == 10 then return jeton == nil or RELIQUE[jeton] == sous end
        if sous >= 1 and sous <= 4 then
            local portables = transverse.ArmuresPortables(fiche)
            return portables[sous] ~= nil
        end
        return true
    end
    if classe == 2 then
        local liste = ARMES[jeton or ""]
        if not liste then return true end
        for _, s in ipairs(liste) do if s == sous then return true end end
        return false
    end
    return true
end

-- Niveau requis d'un objet : la base, sinon le jeu.
function sources.NiveauRequis(id)
    local n = tonumber(Lire("ItemDB", id, "requiredLevel"))
    if n then return n end
    local lecture = NS.Lecture("C_Item.GetItemInfo") or NS.Lecture("GetItemInfo")
    if lecture then
        local ok, _, _, _, _, minimum = pcall(lecture, id)
        if ok then return tonumber(minimum) end
    end
    return nil
end

-- Une quete peut-elle etre faite par ce personnage (camp, classe, niveau) ?
local function QueteFaisable(q, niveauMax)
    local races = tonumber(Lire("QuestDB", q, "requiredRaces")) or 0
    if races ~= 0 then
        local _, _, idRace = UnitRace("player")
        if idRace and bit and bit.band(races, 2 ^ (idRace - 1)) == 0 then return false end
    end
    local classes = tonumber(Lire("QuestDB", q, "requiredClasses")) or 0
    if classes ~= 0 then
        local _, _, idClasse = UnitClass("player")
        if idClasse and bit and bit.band(classes, 2 ^ (idClasse - 1)) == 0 then return false end
    end
    local minimum = tonumber(Lire("QuestDB", q, "requiredLevel")) or tonumber(Lire("QuestDB", q, "questLevel")) or 0
    return minimum <= niveauMax
end

local function NomDeZone(zone)
    if not zone then return nil end
    local lecture = NS.Lecture("C_Map.GetAreaInfo")
    if not lecture then return nil end
    local ok, nom = pcall(lecture, zone)
    if ok and type(nom) == "string" and nom ~= "" then return nom end
    return nil
end

-- Texte court de provenance pour une entree de la base.
function sources.Provenance(categorie, e)
    local L = NS.L
    if categorie == "quetes" and e.quete then
        local nom = Lire("QuestDB", e.quete, "name") or ("#" .. e.quete)
        local niveau = tonumber(Lire("QuestDB", e.quete, "questLevel"))
        return niveau and string.format(L.GEAR_SRC_QUEST, nom, niveau) or nom
    end
    local s = (categorie == "donjons") and e.donjon or e.monde
    if not s then return "" end
    if s.pnj then
        local nom = Lire("NpcDB", s.pnj, "name") or "?"
        local zone = NomDeZone(s.zone)
        return zone and (nom .. " (" .. zone .. ")") or nom
    end
    if s.objet then return Lire("ObjectDB", s.objet, "name") or "?" end
    return ""
end

-- Metiers des personnages du compte (meme camp) : ligne -> { fiche, ... }.
local function MetiersDuCompte()
    local t = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if NS.inventaire.MemeCamp(fiche) then
            for cle, sien in pairs(type(fiche.metiers) == "table" and fiche.metiers or {}) do
                local ligne = tonumber(cle)
                if ligne and type(sien) == "table" then
                    t[ligne] = t[ligne] or {}
                    table.insert(t[ligne], fiche)
                end
            end
        end
    end
    return t
end

-- Crafts d'artisans (metiers qu'aucun personnage n'a) : par emplacement, une fois.
local externes
local function Externes()
    if externes then return externes end
    externes = {}
    for objet, brut in pairs(NS.donnees.NIVEAUX or {}) do
        if objet > 0 then
            local code, classe, sous = CodeEtClasse(objet)
            if code then
                local metier = tonumber(string.match(brut, "/(%d+)$"))
                local orange = tonumber(string.match(brut, "^(%d+)/"))
                externes[code] = externes[code] or {}
                table.insert(externes[code], { id = objet, classe = classe, sous = sous, metier = metier, rangRequis = orange })
            end
        end
    end
    return externes
end

-- Tous les candidats d'un emplacement, par origine, deja filtres par ce que
-- le personnage peut porter et par le niveau (le sien plus la marge).
-- Chaque entree : { id, provenance, niveau, (recette, qui...) }.
function sources.Candidats(code, fiche, marge)
    local L = NS.L
    local r = {}
    for _, c in ipairs(sources.ORDRE) do r[c] = {} end
    if not code or not fiche then return r end
    local niveau = tonumber(fiche.niveau) or 1
    local niveauMax = niveau + (tonumber(marge) or 10)
    local vus = {}
    local function Garder(categorie, id, entree)
        vus[categorie] = vus[categorie] or {}
        if vus[categorie][id] then return end
        local code2, classe, sous = CodeEtClasse(id)
        if code2 ~= code or not sources.Portable(classe, sous, fiche) then return end
        local req = sources.NiveauRequis(id)
        if req and req > niveauMax then return end
        entree.id, entree.niveau = id, req
        vus[categorie][id] = true
        table.insert(r[categorie], entree)
    end
    -- Deja chez un de ses personnages, et les crafts de ses personnages.
    local candidats = transverse.Candidats(code)
    for _, c in ipairs(candidats.possedes) do
        Garder("possede", c.objet, { provenance = string.format(c.ou == "banque" and L.GEAR_IN_BANK or L.GEAR_IN_BAGS, c.nomCourt) })
    end
    for _, c in ipairs(candidats.moi) do
        Garder("craftInterne", c.objet, { recette = c.recette, groupe = "connue",
            provenance = c.pret and L.RECIPES_CAN_CRAFT or L.GEAR_SRC_MINE_MISSING, pret = c.pret })
    end
    for _, c in ipairs(candidats.autres) do
        Garder("craftInterne", c.objet, { recette = c.recette, groupe = "connue", provenance = string.format(L.GEAR_MAKER, c.nomCourt) })
    end
    -- Plus tard : une recette du metier d'un de ses personnages, pas encore apprise.
    local metiers = MetiersDuCompte()
    for cle, recette in pairs(CraftCoreDB.recettes or {}) do
        local objet = type(recette) == "table" and recette.objetProduit
        if objet and NS.emplacements.DeLObjet(objet) == code then
            local ligne = NS.recettes.MetierDe and NS.recettes.MetierDe(recette)
            local qui = ligne and metiers[ligne] and metiers[ligne][1]
            if qui then
                local rangR = NS.recettes.RangRequis and NS.recettes.RangRequis(recette)
                -- Comment l'apprendre : a looter (au hasard d'un butin), ou a
                -- apprendre (formateur, marchand, quete...), dit en clair.
                local nature, lignes
                if NS.recettes.CommentApprendre then
                    local okA, n, l = pcall(NS.recettes.CommentApprendre, recette)
                    if okA then nature, lignes = n, l end
                end
                local groupe = (nature == "RECIPES_HOW_DROP") and "looter" or "apprendre"
                local comment = nature and L[nature] or L.RECIPES_HOW_TRAINER
                -- Le detail (vendeur, monstre, quete), sauf la simple supposition du formateur.
                local detail = type(lignes) == "table" and lignes[1] or nil
                if detail == L.RECIPES_HOW_TRAINER_GUESS or nature == "RECIPES_HOW_TRAINER" then detail = nil end
                local quiNom = NS.inventaire.NomCourt(qui.cle)
                local texte = rangR and string.format(L.GEAR_SRC_HOW_RANK, quiNom, rangR, detail or comment)
                    or string.format(L.GEAR_SRC_HOW, quiNom, detail or comment)
                Garder("craftInterne", objet, { recette = tonumber(cle) or cle, plusTard = true, groupe = groupe,
                    provenance = texte })
            end
        end
    end
    -- Crafts d'artisans : un metier qu'aucun de ses personnages n'a.
    for _, e in ipairs(Externes()[code] or {}) do
        if not (e.metier and metiers[e.metier]) then
            local nomMetier = e.metier and ((NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(e.metier)) or L["TRADE_" .. e.metier])
            Garder("craftExterne", e.id, { provenance = nomMetier and string.format(L.GEAR_SRC_CRAFTER, nomMetier, e.rangRequis or 0)
                or L.GEAR_SRC_CRAFTER_ANY })
        end
    end
    -- La base : butins du monde, quetes, donjons.
    for _, e in ipairs(index[code] or {}) do
        if e.monde then Garder("monde", e.id, { monde = e.monde }) end
        if e.donjon then
            -- Range sous son donjon ou son raid.
            local principale = ZonesDonjon()[e.donjon.zone] or e.donjon.zone
            Garder("donjons", e.id, { donjon = e.donjon, groupe = "d" .. tostring(principale),
                groupeNom = NomDeZone(principale) or NomDeZone(e.donjon.zone) or "?" })
        end
        if e.quetes then
            for _, q in ipairs(e.quetes) do
                if QueteFaisable(q, niveauMax) then Garder("quetes", e.id, { quete = q }) break end
            end
        end
    end
    for categorie, liste in pairs(r) do
        for _, entree in ipairs(liste) do
            if not entree.provenance then entree.provenance = sources.Provenance(categorie, entree) end
        end
    end
    return r
end

-- Ameliore-t-il ce qui est porte ? Vrai des qu'une statistique gagne au moins
-- 1, meme si d'autres baissent. nil tant que le jeu n'a pas lu l'objet.
function sources.Ameliore(id, statsPorte)
    local stats = NS.objets.Stats(id)
    if not stats then
        local info = NS.objets.Info(id)
        if info and info.nom then return false, nil end
        return nil
    end
    local gains = {}
    for cle, v in pairs(stats) do
        local ecart = (tonumber(v) or 0) - (tonumber(statsPorte and statsPorte[cle]) or 0)
        if ecart >= 1 then table.insert(gains, { cle = cle, ecart = ecart }) end
    end
    -- L'armure apres les caracteristiques : ses chiffres sont bien plus gros.
    local function Armure(cle)
        local t = tostring(cle)
        return string.find(t, "RESISTANCE0", 1, true) ~= nil or string.find(t, "ARMOR", 1, true) ~= nil
    end
    for _, g in ipairs(gains) do g.armure = Armure(g.cle) g.poids = g.armure and g.ecart / 10 or g.ecart end
    table.sort(gains, function(a, b)
        if a.armure ~= b.armure then return not a.armure end
        return a.ecart > b.ecart
    end)
    return #gains > 0, gains
end

-- Demande au jeu de lire un objet pas encore connu (reponse asynchrone).
function sources.Charger(id)
    local C = _G.C_Item
    if C and C.RequestLoadItemDataByID then pcall(C.RequestLoadItemDataByID, id) end
end
