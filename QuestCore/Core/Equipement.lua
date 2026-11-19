local _, NS = ...

-- Equipement : ce que porte un personnage, et ce que ses quetes en cours
-- peuvent lui apporter, emplacement par emplacement.
--
-- Matieres portables et poids des caracteristiques repris de CraftCore, a
-- l'identique, pour que les deux pages d'equipement jugent pareil.

NS.equip = {}
local equip = NS.equip

local MATIERES_D_ARMURE = { [1] = true, [2] = true, [3] = true, [4] = true }

-- ---------------------------------------------------------------------------
-- Ce que porte un personnage
-- ---------------------------------------------------------------------------

-- Releve de ce que porte le personnage connecte, a chaque releve du journal.
function equip.Relever(p)
    if not p then return end
    local j = NS.jeu
    if not j.objetEquipe then return end
    local porte = {}
    for _, e in ipairs(NS.emplacements.DuPersonnage) do
        local numero = NS.emplacements.Numero(e.nom)
        local id = numero and tonumber((NS.Appeler(j.objetEquipe, "player", numero)))
        if id then porte[e.nom] = { id = id } end
    end
    p.equipement = porte
end

-- Fiche d'un personnage pour la page d'equipement : classe, niveau et ce
-- qu'il porte. QuestCore d'abord, CraftCore a defaut.
function equip.Fiche(cle)
    local p = cle and NS.base.PersoParCle(cle)
    local cc = type(CraftCoreDB) == "table" and type(CraftCoreDB.personnages) == "table"
        and CraftCoreDB.personnages[cle or ""] or nil
    local fiche = {
        cle = cle,
        jetonClasse = (p and p.classe) or (cc and cc.jetonClasse),
        niveau = tonumber(p and p.niveau) or tonumber(cc and cc.niveau),
        equipement = (p and p.equipement) or (cc and cc.equipement),
    }
    -- CraftCore peut avoir un releve plus recent ou plus complet.
    if (not fiche.equipement or next(fiche.equipement) == nil) and cc and cc.equipement then
        fiche.equipement = cc.equipement
    end
    return fiche
end

-- ---------------------------------------------------------------------------
-- Matieres et score (repris de CraftCore)
-- ---------------------------------------------------------------------------

function equip.MatiereDe(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil end
    local ok, _, _, sousGenre, _, _, classe, sousClasse = pcall(lecture, objet)
    if not ok or classe ~= 4 or not MATIERES_D_ARMURE[sousClasse] then return nil end
    if type(sousGenre) == "string" and sousGenre ~= "" then return sousGenre end
    return nil
end

function equip.SousClasseDe(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil end
    local ok, _, _, _, _, _, classe, sousClasse = pcall(lecture, objet)
    if not ok or classe ~= 4 or not MATIERES_D_ARMURE[sousClasse] then return nil end
    return sousClasse
end

local PORTABLES = {
    MAGE = { 1 }, PRIEST = { 1 }, WARLOCK = { 1 },
    ROGUE = { 1, 2 }, DRUID = { 1, 2 },
    HUNTER = { 1, 2, 3 }, SHAMAN = { 1, 2, 3 },
    WARRIOR = { 1, 2, 3, 4 }, PALADIN = { 1, 2, 3, 4 },
}
local NIVEAU_PALIER = 40
local PALIER = { HUNTER = 3, SHAMAN = 3, WARRIOR = 4, PALADIN = 4 }

function equip.ArmuresPortables(fiche)
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

function equip.Score(objet, fiche)
    if not objet then return 0 end
    local stats = NS.objets.Stats(objet) or {}
    local poids = POIDS[(fiche and fiche.jetonClasse) or ""]
        or { STAMINA = 1, STRENGTH = 1, AGILITY = 1, INTELLECT = 1, SPIRIT = 1 }
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

-- ---------------------------------------------------------------------------
-- Recompenses de quetes, par emplacement
-- ---------------------------------------------------------------------------

-- Les quetes en cours de ce personnage qui donnent un objet pour cet
-- emplacement. Une entree par quete, avec ses objets pour cet emplacement :
-- { id, titre, niveau, complete, objets = { { objet, auChoix, n } } }.
-- Rangees par niveau de quete, puis par nom.
function equip.QuetesPour(cle, code)
    local p = cle and NS.base.PersoParCle(cle)
    local resultat = {}
    if not p or not code then return resultat end
    for id, q in pairs(p.quetes or {}) do
        local r = q.recompenses
        if type(r) == "table" then
            local entree
            local vus = {}
            local function voir(liste, auChoix)
                for _, o in ipairs(liste or {}) do
                    if o.objet and not vus[o.objet] and NS.emplacements.DeLObjet(o.objet) == code then
                        vus[o.objet] = true
                        entree = entree or { id = id, titre = q.titre, niveau = q.niveau,
                            complete = q.complete, objets = {} }
                        table.insert(entree.objets, {
                            objet = o.objet, auChoix = auChoix, n = o.n,
                            matiere = equip.MatiereDe(o.objet),
                            sousClasse = equip.SousClasseDe(o.objet),
                        })
                    end
                end
            end
            voir(r.objets, false)
            voir(r.choix, true)
            if entree then table.insert(resultat, entree) end
        end
    end
    table.sort(resultat, function(a, b)
        local na, nb = tonumber(a.niveau) or 0, tonumber(b.niveau) or 0
        if na ~= nb then return na < nb end
        return tostring(a.titre or "") < tostring(b.titre or "")
    end)
    return resultat
end
