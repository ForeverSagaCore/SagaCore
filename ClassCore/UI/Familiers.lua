local _, NS = ...

-- Chasseur : la page Familiers. Le familier actuel (bonheur, loyaute, points
-- de dressage, regime), les familles (regime, techniques), chaque technique
-- rang par rang avec les betes qui l'enseignent (zone, niveaux, position),
-- et les familiers rares. Lecture seule : rien n'est lance.

NS.familiers = {}
local M = NS.familiers
local T = NS.T
local E = function() return NS.etat end
local D = function() return NS.dataFamiliers end

local GRIS = { 0.6, 0.6, 0.6 }
local OR = { 1, 0.82, 0 }
local VERT = { 0.31, 0.82, 0.41 }
local ROUGE = { 1, 0.35, 0.35 }
local BLANC = { 1, 1, 1 }

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
    return b.zone
end

local function Niveaux(b)
    if b.min and b.max and b.min ~= b.max then return string.format(T("niv. %d à %d", "lvl %d to %d"), b.min, b.max) end
    if b.min then return string.format(T("niv. %d", "lvl %d"), b.min) end
    return ""
end

local function NomFamille(cle)
    for _, f in ipairs(D().FAMILLES) do if f.cle == cle then return f.nom(), f end end
    return cle
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

local function InfobulleBete(b)
    return function(tt)
        tt:AddLine(NomBete(b))
        local fam = NomFamille(b.family)
        tt:AddLine(string.format("%s  ·  %s", fam, Niveaux(b)), 1, 1, 1)
        local lieu = Lieu(b)
        if lieu then tt:AddLine(lieu, 0.8, 0.8, 0.8) end
        if b.elite then tt:AddLine(T("Élite", "Elite"), 1, 0.5, 0.25) end
        if b.rare then tt:AddLine(T("Rare", "Rare"), 0.75, 0.75, 1) end
        if b.teaches and #b.teaches > 0 then
            tt:AddLine(T("En l'apprivoisant, ton familier apprend :", "Taming it teaches your pet :"), 1, 0.82, 0)
            for _, x in ipairs(b.teaches) do
                tt:AddLine(string.format(T("%s rang %d", "%s rank %d"), NomTechnique(x[1]), x[2]), 0.9, 0.9, 0.9)
            end
        end
        if b.note then tt:AddLine(b.note, 0.8, 0.8, 0.8) end
        tt:AddLine(T("Apprivoise-la, puis fais-la combattre : la technique s'apprend en combat, ensuite elle s'enseigne à tous tes familiers par le dressage des bêtes.",
            "Tame it, then fight with it : the ability is learned in combat, then Beast Training teaches it to all your pets."), 0.6, 0.6, 0.6, true)
    end
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
    table.insert(b.lignes, { icone = icone, texte = f.famille or T("Familier", "Pet"),
        droite = f.niveau and string.format(T("Niveau %d", "Level %d"), f.niveau) or "", couleurDroite = BLANC })
    if f.bonheur and BONHEUR[f.bonheur] then
        table.insert(b.lignes, { texte = T("Bonheur", "Happiness"), droite = BONHEUR[f.bonheur](),
            couleurDroite = f.bonheur == 3 and VERT or (f.bonheur == 2 and OR or ROUGE) })
    end
    if f.loyaute then table.insert(b.lignes, { texte = T("Loyauté", "Loyalty"), droite = f.loyaute, couleurDroite = BLANC }) end
    if f.points then table.insert(b.lignes, { texte = T("Points de dressage libres", "Free training points"), droite = tostring(f.points), couleurDroite = BLANC }) end
    if f.regime then
        local l = {}
        for i = 1, 6 do if f.regime[i] then table.insert(l, f.regime[i]) end end
        if #l > 0 then table.insert(b.lignes, { texte = T("Il mange", "It eats"), droite = table.concat(l, ", "), couleurDroite = BLANC }) end
    end
    return b
end

-- ---------------------------------------------------------------------------
-- La page
-- ---------------------------------------------------------------------------

local vue = { technique = "Bite" }

local function OptionsTechniques()
    local l = { { "familles", T("Les familles", "Families") } }
    for _, cle in ipairs(D().ORDRE_TECHNIQUES) do table.insert(l, { cle, NomTechnique(cle) }) end
    table.insert(l, { "rares", T("Familiers rares", "Rare pets") })
    return l
end

local function BlocsFamilles()
    local b = { titre = T("Les familles", "Families"), droite = tostring(#D().FAMILLES), lignes = {} }
    for _, f in ipairs(D().FAMILLES) do
        local noms = {}
        for _, t in ipairs(f.techniques) do table.insert(noms, NomTechnique(t)) end
        table.insert(b.lignes, { icone = f.icone, texte = f.nom(), droite = Regime(f), couleurDroite = GRIS,
            infobulle = function(tt)
                tt:AddLine(f.nom())
                tt:AddLine(string.format(T("Mange : %s", "Eats : %s"), Regime(f)), 1, 1, 1)
                tt:AddLine(string.format(T("Techniques : %s", "Abilities : %s"), table.concat(noms, ", ")), 0.9, 0.9, 0.9, true)
                if f.unique then tt:AddLine(string.format(T("Sur Forever, technique propre : %s", "On Forever, own ability : %s"), f.unique), 1, 0.82, 0, true) end
                if f.forever then tt:AddLine(T("Famille ajoutée par Forever.", "Family added by Forever."), 0.75, 0.75, 1) end
            end })
    end
    return { b }
end

local function BlocsTechnique(cle)
    local t = D().TECHNIQUES[cle]
    local blocs = {}
    local parRang = {}
    for _, b in ipairs(D().DRESSEURS) do
        for _, x in ipairs(b.teaches or {}) do
            if x[1] == cle then
                parRang[x[2]] = parRang[x[2]] or {}
                table.insert(parRang[x[2]], b)
            end
        end
    end
    local maxi = 0
    for r in pairs(parRang) do maxi = math.max(maxi, r) end
    if t and t.rangs then maxi = math.max(maxi, #t.rangs) end
    -- Les familles qui peuvent l'apprendre.
    local familles = {}
    for _, f in ipairs(D().FAMILLES) do
        for _, x in ipairs(f.techniques) do if x == cle then table.insert(familles, f.nom()) end end
    end
    local liste = table.concat(familles, ", ")
    local entete = { titre = NomTechnique(cle), droite = string.format(#familles == 1 and T("%d famille", "%d family") or T("%d familles", "%d families"), #familles), lignes = {} }
    if #familles > 0 then
        table.insert(entete.lignes, { icone = t and t.icone, texte = string.format(T("Apprise par : %s", "Learned by : %s"), liste),
            infobulle = function(tt) tt:AddLine(NomTechnique(cle)) tt:AddLine(liste, 1, 1, 1, true) end })
    end
    table.insert(blocs, entete)
    for r = 1, maxi do
        local info = t and t.rangs and t.rangs[r]
        local titre = string.format(T("Rang %d", "Rank %d"), r)
        local droite = ""
        if info and info[1] then
            droite = info[2] and string.format(info[2] == 1 and T("familier niv. %d, %d point", "pet lvl %d, %d point") or T("familier niv. %d, %d points", "pet lvl %d, %d points"), info[1], info[2])
                or string.format(T("familier niv. %d", "pet lvl %d"), info[1])
        end
        local b = { titre = titre, droite = droite, lignes = {} }
        for _, bete in ipairs(parRang[r] or {}) do
            table.insert(b.lignes, { icone = select(2, NomFamille(bete.family)) and select(2, NomFamille(bete.family)).icone or nil,
                texte = NomBete(bete), droite = (Lieu(bete) or "") .. "  ·  " .. Niveaux(bete), couleurDroite = GRIS,
                couleur = bete.elite and { 1, 0.5, 0.25 } or nil, infobulle = InfobulleBete(bete) })
        end
        if #b.lignes == 0 then b.vide = T("Enseigné par le maître des familiers, ou bête non répertoriée.", "Taught by the pet trainer, or no beast listed.") end
        table.insert(blocs, b)
    end
    if maxi == 0 then blocs[1].vide = T("Aucune bête répertoriée pour cette technique.", "No beast listed for this ability.") end
    return blocs
end

local function BlocsRares()
    local b = { titre = T("Familiers rares", "Rare pets"), droite = tostring(#D().RARES), lignes = {} }
    for _, bete in ipairs(D().RARES) do
        table.insert(b.lignes, { icone = select(2, NomFamille(bete.family)) and select(2, NomFamille(bete.family)).icone or nil,
            texte = NomBete(bete), droite = (Lieu(bete) or "") .. "  ·  " .. Niveaux(bete), couleurDroite = GRIS,
            infobulle = InfobulleBete(bete) })
    end
    if #b.lignes == 0 then b.vide = T("Liste en préparation.", "List in preparation.") end
    return { b }
end

local function Blocs()
    local blocs = { M.BlocMonFamilier() }
    local v = vue.technique
    local suite
    if v == "familles" then suite = BlocsFamilles()
    elseif v == "rares" then suite = BlocsRares()
    else suite = BlocsTechnique(v) end
    for _, b in ipairs(suite) do table.insert(blocs, b) end
    return blocs
end

function M.Page(Page)
    return Page("familiers", "Interface\\Icons\\Ability_Hunter_BeastTaming",
        function() return T("Familiers", "Pets") end,
        function() return T("Le catalogue des familiers", "The pet catalogue") end,
        function() return T("Ton familier, les familles et ce qu'elles mangent, chaque technique rang par rang avec les bêtes qui l'enseignent et où les trouver, et les familiers rares.",
            "Your pet, the families and what they eat, every ability rank by rank with the beasts that teach it and where to find them, and rare pets.") end,
        Blocs,
        function(page, O)
            page.rVue = O.Rangee()
            O.Liste(page.rVue, OptionsTechniques, function() return vue.technique end, function(v) vue.technique = v end)
            page.rVue.nom:SetText(T("Afficher", "Show"))
        end)
end
