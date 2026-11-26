local _, NS = ...

-- Chasseur : la page Familiers. On y entre par les familles ; une famille
-- ouvre toutes ses betes du jeu (zone et position, niveaux, techniques
-- apprises en l'apprivoisant, elite ou rare) ; une bete choisie s'affiche en
-- 3D avec sa fiche. On y trouve aussi chaque technique rang par rang, et les
-- familiers rares. Lecture seule : rien n'est lance.

NS.familiers = {}
local M = NS.familiers
local T = NS.T
local E = function() return NS.etat end
local D = function() return NS.dataFamiliers end
local F = function() return NS.fenetre end

local function C(nom) return F()[nom] end

local function LireBase(entite, id, champ)
    local Q = NS.quetes
    return Q and Q.Lire and Q.Lire(entite, id, champ) or nil
end

-- Nom de la bete dans la langue du jeu (base de quetes), sinon l'anglais.
local function NomBete(b)
    local n = b.id and LireBase("NpcDB", b.id, "name")
    return type(n) == "string" and n or b.name
end

-- "Zone 45, 52" : la premiere position connue de la bete, sinon sa zone.
local function Lieu(b)
    local spawns = b.id and LireBase("NpcDB", b.id, "spawns")
    for zone, pts in pairs(type(spawns) == "table" and spawns or {}) do
        local nz = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone)
        local pt = type(pts) == "table" and pts[1]
        if nz then
            if type(pt) == "table" and tonumber(pt[1]) and pt[1] > 0 then
                return string.format("%s %d, %d", nz, math.floor(pt[1] + 0.5), math.floor(pt[2] + 0.5))
            end
            return nz
        end
    end
    if b.zoneId then
        local nz = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), b.zoneId)
        if nz then return nz end
    end
    return b.zone
end

local function Niveaux(b)
    if b.min and b.max and b.min ~= b.max then return string.format(T("niv. %d à %d", "lvl %d to %d"), b.min, b.max) end
    if b.min then return string.format(T("niv. %d", "lvl %d"), b.min) end
    return ""
end

local function Famille(cle)
    for _, f in ipairs(D().FAMILLES) do if f.cle == cle then return f end end
    return nil
end

local function NomTechnique(cle)
    local t = D().TECHNIQUES[cle]
    return t and t.nom() or cle
end

local function Regime(f)
    local l = {}
    for _, r in ipairs(f.regime or {}) do local fn = D().REGIMES[r] if fn then table.insert(l, fn()) end end
    return table.concat(l, ", ")
end

local function Enseigne(b)
    local l = {}
    for _, x in ipairs(b.teaches or {}) do table.insert(l, string.format(T("%s %d", "%s %d"), NomTechnique(x[1]), x[2])) end
    return table.concat(l, ", ")
end

-- Toutes les betes connues : le catalogue complet s'il est la, sinon les
-- enseignantes et les rares.
local function Betes()
    local d = D()
    if type(d.BETES) == "table" and #d.BETES > 0 then return d.BETES end
    if d.toutes then return d.toutes end
    local l, vus = {}, {}
    for _, src in ipairs({ d.DRESSEURS or {}, d.RARES or {} }) do
        for _, b in ipairs(src) do if not vus[b.id] then vus[b.id] = true table.insert(l, b) end end
    end
    d.toutes = l
    return l
end

-- Les rares : celles marquees rares dans le catalogue, avec la note des
-- rares connues (vitesse, quete qui les fait venir...).
local function Rares()
    local d = D()
    if d.raresCache then return d.raresCache end
    local notes = {}
    for _, r in ipairs(d.RARES or {}) do notes[r.id] = r end
    local l, vus = {}, {}
    for _, b in ipairs(Betes()) do
        if b.rare or notes[b.id] then
            if notes[b.id] and notes[b.id].note and not b.note then b.note = notes[b.id].note end
            table.insert(l, b) vus[b.id] = true
        end
    end
    for _, r in ipairs(d.RARES or {}) do if not vus[r.id] then table.insert(l, r) end end
    table.sort(l, function(a, c) return (a.min or 0) < (c.min or 0) end)
    d.raresCache = l
    return l
end

local function BetesDe(cle)
    local l = {}
    for _, b in ipairs(Betes()) do if b.family == cle then table.insert(l, b) end end
    table.sort(l, function(a, b) if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end return NomBete(a) < NomBete(b) end)
    return l
end

-- La classification du jeu, en couleur de son cadre de portrait : argent
-- pour une rare, or pour une elite, blanc sinon.
local ARGENT, OR = { 0.78, 0.8, 0.86 }, { 1, 0.82, 0 }
local function Classement(b)
    if b.rare and b.elite then return T("Rare élite", "Rare elite"), ARGENT end
    if b.rare then return T("Rare", "Rare"), ARGENT end
    if b.elite then return T("Élite", "Elite"), OR end
    return nil
end

local function Marques(b)
    local l = {}
    if b.dungeon then table.insert(l, T("En donjon", "In a dungeon")) end
    if b.summoned then table.insert(l, T("Invoquée", "Summoned")) end
    return table.concat(l, ", ")
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

local vue = { mode = "familles" }
function M.Reinitialiser() end

local function Aller(mode, cle, bete)
    vue.mode, vue.cle, vue.bete = mode, cle, bete
    local w = F().w
    if w and w.defilement then pcall(w.defilement.SetVerticalScroll, w.defilement, 0) end
end

local function LigneRetour(texte, mode, cle)
    return { icone = "Interface\\Icons\\Ability_Hunter_BeastTaming", texte = texte, droite = T("Retour", "Back"),
        couleurDroite = C("NORMAL"), clic = function() Aller(mode, cle) end, infobulle = function(tt) tt:AddLine(texte) end }
end

-- ---------------------------------------------------------------------------
-- Le familier actuel
-- ---------------------------------------------------------------------------

local BONHEUR = {
    function() return T("Malheureux (75 % des dégâts)", "Unhappy (75 % damage)") end,
    function() return T("Content (100 % des dégâts)", "Content (100 % damage)") end,
    function() return T("Heureux (125 % des dégâts)", "Happy (125 % damage)") end,
}

function M.BlocMonFamilier()
    local f = E().Familier()
    local b = { titre = T("Mon familier", "My pet"), lignes = {} }
    if not f then
        b.vide = T("Pas de familier appelé.", "No pet called.")
        return b
    end
    b.droite = f.nom or ""
    local icone
    for _, x in ipairs(D().FAMILLES) do if x.nom() == f.famille then icone = x.icone end end
    local N = C("NORMAL")
    table.insert(b.lignes, { icone = icone, texte = f.famille or T("Familier", "Pet"),
        droite = f.niveau and string.format(T("Niveau %d", "Level %d"), f.niveau) or "" })
    if f.bonheur and BONHEUR[f.bonheur] then
        table.insert(b.lignes, { texte = T("Bonheur", "Happiness"), droite = BONHEUR[f.bonheur](),
            couleurDroite = f.bonheur == 3 and C("VERT") or (f.bonheur == 2 and N or C("ROUGE")) })
    end
    if f.loyaute then table.insert(b.lignes, { texte = T("Loyauté", "Loyalty"), droite = f.loyaute }) end
    if f.points then table.insert(b.lignes, { texte = T("Points de dressage libres", "Free training points"), droite = tostring(f.points) }) end
    if f.regime then
        local l = {}
        for i = 1, 6 do if f.regime[i] then table.insert(l, f.regime[i]) end end
        if #l > 0 then table.insert(b.lignes, { texte = T("Il mange", "It eats"), droite = table.concat(l, ", ") }) end
    end
    return b
end

-- ---------------------------------------------------------------------------
-- Les vues
-- ---------------------------------------------------------------------------

local function InfobulleBete(b)
    return function(tt)
        tt:AddLine(NomBete(b))
        local f = Famille(b.family)
        tt:AddLine(string.format("%s, %s", f and f.nom() or b.family, Niveaux(b)), 1, 1, 1)
        local lieu = Lieu(b)
        if lieu then tt:AddLine(lieu, 0.8, 0.8, 0.8) end
        local classe, teinte = Classement(b)
        if classe then tt:AddLine(classe, teinte[1], teinte[2], teinte[3]) end
        local m = Marques(b)
        if m ~= "" then tt:AddLine(m, 0.8, 0.8, 0.8) end
        if b.teaches and #b.teaches > 0 then tt:AddLine(string.format(T("Apprend : %s", "Teaches : %s"), Enseigne(b)), 1, 0.82, 0, true) end
        if b.note then tt:AddLine(b.note, 0.8, 0.8, 0.8, true) end
    end
end

local function LigneBete(b, choisie, retour)
    local N, G = C("NORMAL"), C("GRIS")
    local f = Famille(b.family)
    return { icone = f and f.icone, texte = NomBete(b), couleur = N,
        droite = (Lieu(b) or "") .. "  ·  " .. Niveaux(b), couleurDroite = G, largeurDroite = 330,
        clic = function() Aller("famille", b.family, b) end, infobulle = InfobulleBete(b) }
end

local function VueFamilles()
    local blocs = {}
    local b = { titre = T("Les familles", "Families"), droite = string.format(T("%d familles", "%d families"), #D().FAMILLES), lignes = {} }
    for _, f in ipairs(D().FAMILLES) do
        local n = #BetesDe(f.cle)
        table.insert(b.lignes, { icone = f.icone, texte = f.nom(),
            droite = string.format(n == 1 and T("%d bête  ·  %s", "%d beast  ·  %s") or T("%d bêtes  ·  %s", "%d beasts  ·  %s"), n, Regime(f)),
            couleurDroite = C("GRIS"), largeurDroite = 380,
            clic = function() Aller("famille", f.cle) end,
            infobulle = function(tt)
                tt:AddLine(f.nom())
                tt:AddLine(string.format(T("Mange : %s", "Eats : %s"), Regime(f)), 1, 1, 1)
                local noms = {}
                for _, t in ipairs(f.techniques) do table.insert(noms, NomTechnique(t)) end
                tt:AddLine(string.format(T("Techniques : %s", "Abilities : %s"), table.concat(noms, ", ")), 0.9, 0.9, 0.9, true)
            end })
    end
    table.insert(blocs, b)
    local bt = { titre = T("Les techniques", "Abilities"), lignes = {} }
    for _, cle in ipairs(D().ORDRE_TECHNIQUES) do
        local t = D().TECHNIQUES[cle]
        table.insert(bt.lignes, { icone = t.icone, texte = t.nom(), droite = T("Rangs et bêtes qui l'enseignent", "Ranks and beasts that teach it"),
            couleurDroite = C("GRIS"), clic = function() Aller("technique", cle) end, infobulle = function(tt) tt:AddLine(t.nom()) end })
    end
    table.insert(blocs, bt)
    table.insert(blocs, { titre = T("Familiers rares", "Rare pets"), lignes = { { icone = "Interface\\Icons\\INV_Misc_Head_Tiger_01",
        texte = T("Les familiers rares et uniques", "Rare and unique pets"), droite = string.format(T("%d bêtes", "%d beasts"), #Rares()),
        couleurDroite = C("GRIS"), clic = function() Aller("rares") end, infobulle = function(tt) tt:AddLine(T("Familiers rares", "Rare pets")) end } } })
    return blocs
end

local function VueFamille(cle)
    local f = Famille(cle)
    local blocs = {}
    if not f then return VueFamilles() end
    local betes = BetesDe(cle)
    local choisie = vue.bete
    if not choisie or choisie.family ~= cle then choisie = betes[1] end
    local entete = { titre = f.nom(), droite = string.format(#betes == 1 and T("%d bête", "%d beast") or T("%d bêtes", "%d beasts"), #betes),
        lignes = { LigneRetour(T("Toutes les familles", "All families"), "familles") } }
    table.insert(blocs, entete)
    local noms = {}
    for _, t in ipairs(f.techniques) do table.insert(noms, NomTechnique(t)) end
    if choisie then
        local lignes = {
            { NomBete(choisie), C("NORMAL") },
            { string.format(T("%s, %s", "%s, %s"), f.nom(), Niveaux(choisie)), C("NORMAL") },
            { Lieu(choisie) or "", C("NORMAL") },
        }
        if choisie.teaches and #choisie.teaches > 0 then table.insert(lignes, { string.format(T("Apprend : %s", "Teaches : %s"), Enseigne(choisie)), C("VERT") }) end
        local classe, teinte = Classement(choisie)
        if classe then table.insert(lignes, { classe, teinte }) end
        local m = Marques(choisie)
        if m ~= "" then table.insert(lignes, { m, C("NORMAL") }) end
        if choisie.speed then table.insert(lignes, { (string.gsub(string.format(T("Vitesse d'attaque : %.1f s", "Attack speed : %.1f s"), choisie.speed), "(%d)%.(%d)", T("%1,%2", "%1.%2"))), C("NORMAL") }) end
        table.insert(lignes, { string.format(T("Mange : %s", "Eats : %s"), Regime(f)), C("GRIS") })
        table.insert(lignes, { string.format(T("Techniques de la famille : %s", "Family abilities : %s"), table.concat(noms, ", ")), C("GRIS") })
        table.insert(blocs, { apercu = { display = choisie.display, id = choisie.id, lignes = lignes, bordure = teinte } })
    end
    local lb = { titre = T("Où les trouver", "Where to find them"), lignes = {} }
    for _, b in ipairs(betes) do table.insert(lb.lignes, LigneBete(b, b == choisie)) end
    if #lb.lignes == 0 then lb.vide = T("Aucune bête répertoriée.", "No beast listed.") end
    table.insert(blocs, lb)
    return blocs
end

local function VueTechnique(cle)
    local t = D().TECHNIQUES[cle]
    local blocs = {}
    local familles = {}
    for _, f in ipairs(D().FAMILLES) do
        for _, x in ipairs(f.techniques) do if x == cle then table.insert(familles, f.nom()) end end
    end
    table.insert(blocs, { titre = NomTechnique(cle), droite = string.format(#familles == 1 and T("%d famille", "%d family") or T("%d familles", "%d families"), #familles),
        lignes = { LigneRetour(T("Les familles et les techniques", "Families and abilities"), "familles"),
            { icone = t and t.icone, texte = string.format(T("Apprise par : %s", "Learned by : %s"), table.concat(familles, ", ")),
              infobulle = function(tt) tt:AddLine(NomTechnique(cle)) tt:AddLine(table.concat(familles, ", "), 1, 1, 1, true) end } } })
    local parRang, maxi = {}, 0
    for _, b in ipairs(Betes()) do
        for _, x in ipairs(b.teaches or {}) do
            if x[1] == cle then
                parRang[x[2]] = parRang[x[2]] or {}
                table.insert(parRang[x[2]], b)
                maxi = math.max(maxi, x[2])
            end
        end
    end
    if t and t.rangs then maxi = math.max(maxi, #t.rangs) end
    for r = 1, maxi do
        local info = t and t.rangs and t.rangs[r]
        local droite = ""
        if info and info[1] then
            droite = info[2] and string.format(info[2] == 1 and T("familier niv. %d, %d point", "pet lvl %d, %d point") or T("familier niv. %d, %d points", "pet lvl %d, %d points"), info[1], info[2])
                or string.format(T("familier niv. %d", "pet lvl %d"), info[1])
        end
        local b = { titre = string.format(T("Rang %d", "Rank %d"), r), droite = droite, lignes = {} }
        local liste = parRang[r] or {}
        table.sort(liste, function(a, c) return (a.min or 0) < (c.min or 0) end)
        for i, bete in ipairs(liste) do
            if i > 6 then break end
            table.insert(b.lignes, LigneBete(bete))
        end
        if #b.lignes == 0 then b.vide = T("Aucune bête connue ne l'enseigne.", "No known beast teaches it.") end
        table.insert(blocs, b)
    end
    return blocs
end

local function VueRares()
    local liste = Rares()
    local b = { titre = T("Familiers rares", "Rare pets"), droite = string.format(T("%d bêtes", "%d beasts"), #liste),
        lignes = { LigneRetour(T("Les familles", "Families"), "familles") } }
    for _, bete in ipairs(liste) do table.insert(b.lignes, LigneBete(bete)) end
    return { b }
end

local function Blocs()
    if vue.mode == "famille" then return VueFamille(vue.cle) end
    if vue.mode == "technique" then return VueTechnique(vue.cle) end
    if vue.mode == "rares" then return VueRares() end
    return VueFamilles()
end

function M.Page(Page)
    return Page("familiers", "Interface\\Icons\\Ability_Hunter_BeastTaming",
        function() return T("Familiers", "Pets") end,
        function() return T("Le catalogue des familiers", "The pet catalogue") end,
        function() return T("Choisis une famille : chacune de ses bêtes, où la trouver, son niveau et ce qu'elle apprend à ton familier. Une bête choisie s'affiche en 3D.",
            "Pick a family : each of its beasts, where to find it, its level and what it teaches your pet. A chosen beast is shown in 3D.") end,
        Blocs)
end
