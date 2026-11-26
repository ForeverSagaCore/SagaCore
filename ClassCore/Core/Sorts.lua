local _, NS = ...

-- Les sorts de classe appris chez le maitre : chaque sort avec tous ses
-- rangs (niveau, cout), range par arbre de talents. Les noms et les icones
-- viennent du jeu (langue du client) ; un sort que le jeu ne connait pas
-- (retire de Forever) n'est pas montre. Chaque personnage garde la liste de
-- ses sorts appris (ClassCoreDB) : on voit aussi ceux des autres personnages.

NS.sorts = {}
local S = NS.sorts
local T = NS.T

NS.dataSorts = NS.dataSorts or {}

local ARBRES = {
    ["Beast Mastery"] = function() return T("Maîtrise des bêtes", "Beast Mastery") end,
    Marksmanship = function() return T("Précision", "Marksmanship") end,
    Survival = function() return T("Survie", "Survival") end,
    Arcane = function() return T("Arcanes", "Arcane") end,
    Fire = function() return T("Feu", "Fire") end,
    Frost = function() return T("Givre", "Frost") end,
    Arms = function() return T("Armes", "Arms") end,
    Fury = function() return T("Fureur", "Fury") end,
    Protection = function() return T("Protection", "Protection") end,
    Holy = function() return T("Sacré", "Holy") end,
    Retribution = function() return T("Vindicte", "Retribution") end,
    Assassination = function() return T("Assassinat", "Assassination") end,
    Combat = function() return T("Combat", "Combat") end,
    Subtlety = function() return T("Finesse", "Subtlety") end,
    Discipline = function() return T("Discipline", "Discipline") end,
    Shadow = function() return T("Ombre", "Shadow") end,
    ["Shadow Magic"] = function() return T("Ombre", "Shadow") end,
    Elemental = function() return T("Élémentaire", "Elemental") end,
    ["Elemental Combat"] = function() return T("Élémentaire", "Elemental") end,
    Enhancement = function() return T("Amélioration", "Enhancement") end,
    Restoration = function() return T("Restauration", "Restoration") end,
    Affliction = function() return T("Affliction", "Affliction") end,
    Demonology = function() return T("Démonologie", "Demonology") end,
    Destruction = function() return T("Destruction", "Destruction") end,
    Balance = function() return T("Équilibre", "Balance") end,
    ["Feral Combat"] = function() return T("Combat farouche", "Feral Combat") end,
    General = function() return T("Général", "General") end,
    Poisons = function() return T("Poisons", "Poisons") end,
}
function S.NomArbre(a) local f = ARBRES[a or ""] return f and f() or (a or T("Général", "General")) end

-- Les sorts d'une classe, regroupes : { { cle, nom, icone, arbre, rangs = { { id, rang, niveau, cout, talent, quete } } } }.
local cache = {}
function S.Liste(classe)
    if cache[classe] then return cache[classe] end
    local brut = NS.dataSorts[classe or ""]
    if type(brut) ~= "table" then return {} end
    local parNom, ordre = {}, {}
    for _, r in ipairs(brut) do
        local cle = r.name or tostring(r.id)
        local g = parNom[cle]
        if not g then
            g = { cle = cle, nomAnglais = r.name, arbre = r.tree, rangs = {} }
            parNom[cle] = g
            table.insert(ordre, g)
        end
        table.insert(g.rangs, { id = r.id, rang = r.rank or 0, niveau = r.level or 1, cout = r.cost, talent = r.talent, quete = r.quete })
        if r.races then g.races = r.races end
        if r.faction then g.faction = r.faction end
    end
    for _, g in ipairs(ordre) do
        table.sort(g.rangs, function(a, b) if a.niveau ~= b.niveau then return a.niveau < b.niveau end return a.rang < b.rang end)
        g.niveau = g.rangs[1].niveau
        g.talent = g.rangs[1].talent
    end
    table.sort(ordre, function(a, b) if a.niveau ~= b.niveau then return a.niveau < b.niveau end return a.cle < b.cle end)
    cache[classe] = ordre
    return ordre
end

-- Le sort est-il pour ce personnage (race, camp) ?
local RACES = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Scourge", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }
function S.PourProfil(g, p)
    if g.faction and p.camp and g.faction ~= p.camp then return false end
    if g.races and p.race then
        local nom = RACES[p.race]
        if not nom then return false end
        for _, r in ipairs(g.races) do if r == nom then return true end end
        return false
    end
    return true
end

-- Nom et icone dans la langue du jeu (le premier rang que le jeu connait).
function S.NomIcone(g)
    for _, r in ipairs(g.rangs) do
        local nom, icone = NS.etat.Sort(r.id)
        if nom then return nom, icone end
    end
    return nil
end

-- Etat d'un sort pour un profil : appris (tous les rangs), a apprendre (un
-- rang disponible a son niveau), plus tard. Rend etat, rangs appris, total,
-- prochain rang (table) et le cout des rangs a apprendre maintenant.
function S.Etat(g, profil)
    local appris, prochain, cout = 0, nil, 0
    local total = #g.rangs
    for _, r in ipairs(g.rangs) do
        if profil.connait(r.id) then appris = appris + 1
        elseif not prochain then prochain = r end
        if not profil.connait(r.id) and not r.talent and not r.quete and (profil.niveau or 1) >= r.niveau then cout = cout + (r.cout or 0) end
    end
    if appris >= total then return "appris", appris, total, nil, 0 end
    if prochain and prochain.quete and (profil.niveau or 1) >= prochain.niveau then return "quete", appris, total, prochain, cout end
    if prochain and (profil.niveau or 1) >= prochain.niveau and not prochain.talent then return "apprendre", appris, total, prochain, cout end
    if prochain and prochain.talent and appris == 0 then return "talent", appris, total, prochain, 0 end
    return "plus tard", appris, total, prochain, 0
end

-- Releve des sorts appris du personnage connecte (pour le voir depuis un autre).
function S.Releve()
    local cle = NS.ClePersonnage()
    local classe = NS.etat.Classe()
    if not cle or not classe then return end
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.persos = type(ClassCoreDB.persos) == "table" and ClassCoreDB.persos or {}
    local p = ClassCoreDB.persos[cle] or {}
    ClassCoreDB.persos[cle] = p
    p.classe = classe
    local connus = {}
    for _, g in ipairs(S.Liste(classe)) do
        for _, r in ipairs(g.rangs) do if NS.etat.SortConnu(r.id) then connus[r.id] = true end end
    end
    for _, sec in ipairs(NS.etat.Donnees(classe).sorts or {}) do
        for _, s in ipairs(sec.liste) do if NS.etat.SortConnu(s[1]) then connus[s[1]] = true end end
    end
    p.sorts = connus
    -- Objets de classe : sur soi et en banque.
    local objets = {}
    for _, o in ipairs(NS.etat.Donnees(classe).objets or {}) do
        local sacs, banque = NS.etat.Compte(o.id)
        objets[o.id] = { sacs, banque }
    end
    p.objets = objets
end

-- Le cout d'apprentissage au format du jeu (pieces).
function S.Cout(cuivre)
    cuivre = tonumber(cuivre) or 0
    if cuivre <= 0 then return T("Gratuit", "Free") end
    if _G.GetCoinTextureString then
        local ok, t = pcall(_G.GetCoinTextureString, cuivre)
        if ok and t then return t end
    end
    local po, pa, pc = math.floor(cuivre / 10000), math.floor(cuivre / 100) % 100, cuivre % 100
    local l = {}
    if po > 0 then table.insert(l, po .. " po") end
    if pa > 0 then table.insert(l, pa .. " pa") end
    if pc > 0 then table.insert(l, pc .. " pc") end
    return table.concat(l, " ")
end

do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "BAG_UPDATE_DELAYED", "BANKFRAME_CLOSED" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    local attente = 0
    f:SetScript("OnEvent", function() attente = 2 end)
    f:SetScript("OnUpdate", function(_, e)
        if attente <= 0 then return end
        attente = attente - (e or 0)
        if attente <= 0 then pcall(S.Releve) end
    end)
end
