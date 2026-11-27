local _, NS = ...

-- Calcul de l'avancement, pour une portee :
--   "perso:<cle>"  un personnage, seulement ce qui lui est possible
--                  (sa faction, sa race, sa classe) ;
--   "Horde", "Alliance"  le compte, d'un cote : tout ce que ce camp peut
--                  faire, fait par au moins un de ses personnages ;
--   "deux"         Horde + Alliance : les deux camps additionnes (une quete
--                  neutre compte une fois de chaque cote).
-- Chaque resultat est garde tant que les donnees de sa categorie ne changent
-- pas (versions, voir Socle.lua) : rien n'est recalcule a chaque image.
--
-- Resultat d'une categorie :
--   { fait, total, sous = { { cle, nom, fait, total, elements = {
--       { cle, nom, icone, couleur, fait, total, Detail = function() -> criteres } } } } }
-- Critere : { cle, nom, icone, couleur, fait, qui = { cles }, niveau }
-- (portee "deux" : faitH / faitA, nil quand le critere n'existe pas de ce cote).

NS.calcul = {}
local calcul = NS.calcul
local persos = NS.persos

NS.categories = {}
function calcul.Categorie(cle)
    for _, c in ipairs(NS.categories) do if c.cle == cle then return c end end
    return nil
end

-- Le contexte d'une portee simple (un personnage ou un camp).
function calcul.Contexte(portee)
    if portee == "Horde" or portee == "Alliance" then
        return { genre = "camp", faction = portee, persos = persos.DeFaction(portee) }
    end
    local cle = type(portee) == "string" and portee:match("^perso:(.+)$")
    local p = cle and persos.Par(cle)
    if p then return { genre = "perso", perso = p, faction = p.faction, persos = { p } } end
    return nil
end

-- Une portee existe-t-elle encore (personnage connu) ?
function calcul.PorteeValide(portee)
    return portee == "deux" or calcul.Contexte(portee) ~= nil
end

local function CleVersion(cat)
    local morceaux = { NS.Version("persos") }
    for _, v in ipairs(cat.versions or {}) do table.insert(morceaux, NS.Version(v)) end
    return table.concat(morceaux, ".")
end

-- Deux resultats (Horde, Alliance) additionnes, element par element.
local function Fusion(h, a)
    local r = { fait = (h.fait or 0) + (a.fait or 0), total = (h.total or 0) + (a.total or 0), sous = {} }
    local sousParCle = {}
    for cote, res in pairs({ H = h, A = a }) do
        for _, s in ipairs(res.sous or {}) do
            local rs = sousParCle[s.cle]
            if not rs then
                rs = { cle = s.cle, nom = s.nom, icone = s.icone, ordre = s.ordre, fait = 0, total = 0, elements = {}, parCle = {} }
                sousParCle[s.cle] = rs
                table.insert(r.sous, rs)
            end
            rs.fait, rs.total = rs.fait + s.fait, rs.total + s.total
            for _, e in ipairs(s.elements or {}) do
                local re = rs.parCle[e.cle]
                if not re then
                    re = { cle = e.cle, nom = e.nom, icone = e.icone, coords = e.coords, couleur = e.couleur, ordre = e.ordre,
                        fait = 0, total = 0, cotes = {} }
                    rs.parCle[e.cle] = re
                    table.insert(rs.elements, re)
                end
                re.fait, re.total = re.fait + e.fait, re.total + e.total
                re.cotes[cote] = e
            end
        end
    end
    -- L'ordre de la Horde d'abord, puis ce que seule l'Alliance a.
    local function Ordre(liste)
        table.sort(liste, function(x, y)
            if (x.ordre or 0) ~= (y.ordre or 0) then return (x.ordre or 0) < (y.ordre or 0) end
            return tostring(x.nom) < tostring(y.nom)
        end)
    end
    Ordre(r.sous)
    for _, rs in ipairs(r.sous) do
        rs.parCle = nil
        Ordre(rs.elements)
        for _, re in ipairs(rs.elements) do
            local cotes = re.cotes
            re.cotes = nil
            re.Detail = function()
                local liste, parCle = {}, {}
                for _, cote in ipairs({ "H", "A" }) do
                    local e = cotes[cote]
                    for _, c in ipairs(e and e.Detail and e.Detail() or {}) do
                        local x = parCle[c.cle]
                        if not x then
                            x = { cle = c.cle, nom = c.nom, icone = c.icone, coords = c.coords, couleur = c.couleur, niveau = c.niveau,
                                info = c.info, qui = {} }
                            parCle[c.cle] = x
                            table.insert(liste, x)
                        end
                        if cote == "H" then x.faitH = c.fait and true or false else x.faitA = c.fait and true or false end
                        for _, q in ipairs(c.qui or {}) do table.insert(x.qui, q) end
                    end
                end
                return liste
            end
        end
    end
    return r
end

local memo = {}

-- Le resultat d'une categorie pour une portee, ou nil (donnees pas pretes).
function calcul.Resultat(cleCat, portee)
    local cat = calcul.Categorie(cleCat)
    if not cat then return nil end
    if cat.Pret and not cat.Pret() then return nil end
    local version = CleVersion(cat)
    local m = memo[cleCat]
    if not m or m.version ~= version then m = { version = version, parPortee = {} } memo[cleCat] = m end
    local r = m.parPortee[portee]
    if r then return r end
    if portee == "deux" then
        local h, a = calcul.Resultat(cleCat, "Horde"), calcul.Resultat(cleCat, "Alliance")
        if not (h and a) then return nil end
        r = Fusion(h, a)
    else
        local ctx = calcul.Contexte(portee)
        if not ctx then return nil end
        local ok, res = pcall(cat.Calculer, ctx)
        if not ok then
            NS.base.NoterIncident("calcul " .. cleCat, res)
            return nil
        end
        r = res
    end
    m.parPortee[portee] = r
    return r
end

-- Avancement global : la moyenne des categories (chacune pese autant), sur
-- celles qui ont quelque chose a faire. Rend fait (0..1), nombre pretes, total.
function calcul.Global(portee)
    local somme, n, attendues = 0, 0, 0
    for _, cat in ipairs(NS.categories) do
        if not cat.Absente or not cat.Absente() then
            attendues = attendues + 1
            local r = calcul.Resultat(cat.cle, portee)
            if r and (r.total or 0) > 0 then
                somme = somme + math.min(1, r.fait / r.total)
                n = n + 1
            end
        end
    end
    return n > 0 and (somme / n) or 0, n, attendues
end

-- Les portees a proposer : chaque personnage, puis les camps.
function calcul.Portees()
    local liste = {}
    for _, p in ipairs(persos.Liste()) do table.insert(liste, "perso:" .. p.cle) end
    table.insert(liste, "Horde")
    table.insert(liste, "Alliance")
    table.insert(liste, "deux")
    return liste
end

function calcul.NomDePortee(portee, colore)
    local T = NS.T
    -- Les camps : ce que l'ensemble de ces personnages a fait.
    if portee == "Horde" then return T("Mes persos Horde", "My Horde characters") end
    if portee == "Alliance" then return T("Mes persos Alliance", "My Alliance characters") end
    if portee == "deux" then return T("Tous mes persos", "All my characters") end
    local cle = type(portee) == "string" and portee:match("^perso:(.+)$")
    local p = cle and persos.Par(cle)
    if not p then return "?" end
    if colore then return NS.ref.Hex(NS.ref.CouleurDeClasse(p.classe)) .. p.nom .. "|r" end
    return p.nom
end

-- Oublie tout ce qui est garde (essais, changement de langue).
function calcul.Oublier() memo = {} end

-- ---------------------------------------------------------------------------
-- Points : chaque element fini est un haut fait, qui vaut selon le bareme
-- (5 petit, 10 courant, 25 gros, 50 rare). Un personnage a ses points ; le
-- compte compte chaque haut fait une fois, des qu'un personnage l'a.
-- ---------------------------------------------------------------------------

local BAREME = {
    quetes = { zones = 25, suites = 10, themes = 10, camps = 0 },
    exploration = 10,
    donjons = { donjons = 10, raids = 25 },
    rares = 10,
    objets = 50,
    metiers = 25,
    races = 10,
    reputations = 25,
    jcj = 25,
    heritage = 10,
}
function calcul.Valeur(cleCat, cleSous)
    local b = BAREME[cleCat]
    if type(b) == "table" then return b[cleSous] or 10 end
    return b or 10
end

local function Fini(e) return (e.total or 0) > 0 and (e.fait or 0) >= e.total end

-- Les hauts faits d'un resultat : { [cle] = { pts, nom, cat, sous, element } }
-- et le total possible.
local function HautsFaits(cleCat, r, faits, possibles)
    for _, s in ipairs(r and r.sous or {}) do
        local v = calcul.Valeur(cleCat, s.cle)
        if v > 0 then
            for _, e in ipairs(s.elements or {}) do
                local k = cleCat .. "|" .. tostring(s.cle) .. "|" .. tostring(e.cle)
                possibles[k] = v
                -- Les paliers d'un metier : un petit haut fait chacun (5).
                for _, palier in ipairs(e.paliers or {}) do
                    local nom = e.formatPalier and string.format(e.formatPalier, tostring(e.nom), palier) or (tostring(e.nom) .. " " .. palier)
                    faits[k .. "|" .. palier] = { pts = 5, nom = nom, icone = e.icone, cat = cleCat, sous = s.cle, element = e.cle }
                end
                for n = 1, (e.paliers and (e.nbPaliers or 0) or 0) do possibles[k .. "|p" .. n] = 5 end
                if Fini(e) then
                    faits[k] =
                        { pts = v, nom = e.nom, icone = e.icone, cat = cleCat, sous = s.cle, element = e.cle }
                end
            end
        end
    end
end

-- Les dates d'obtention, dans la fiche du personnage : ce qui etait deja
-- fini au premier releve d'une categorie n'a pas de date (0).
-- Un nouveau releve d'une categorie (nouvelle facon de compter) repart
-- comme un premier releve : rien n'est annonce d'un coup.
local VERSION_HF = 3
calcul.nouveaux = {}
local function Dater(cle, cleCat, faits)
    local f = NS.base.Fiche(cle)
    if not f then return end
    local hf = NS.base.Table(f, "hautsFaits")
    local init = NS.base.Table(f, "hautsFaitsInit")
    local maintenant = NS.Appeler(time) or 0
    local deja = init[cleCat] == VERSION_HF
    for k, x in pairs(faits) do
        if x.cat == cleCat and hf[k] and not hf[k].icone then hf[k].icone = x.icone end
        if x.cat == cleCat and not hf[k] then
            hf[k] = { t = deja and maintenant or 0, nom = x.nom, pts = x.pts, icone = x.icone }
            -- Obtenu a l'instant par le personnage connecte : a annoncer.
            if deja and cle == NS.ClePersonnage() then
                table.insert(calcul.nouveaux, { cle = k, nom = x.nom, pts = x.pts, icone = x.icone })
            end
        end
    end
    init[cleCat] = VERSION_HF
end

local memoPoints = {}
-- Points d'une portee : gagnes, possibles, et la liste des hauts faits.
function calcul.Points(portee)
    local version = NS.Version("tout")
    local m = memoPoints[portee]
    if m and m.version == version then return m.pts, m.possible, m.faits end
    local faits, possibles = {}, {}
    local cleP = type(portee) == "string" and portee:match("^perso:(.+)$")
    local portees = (portee == "deux") and { "Horde", "Alliance" } or { portee }
    for _, cat in ipairs(NS.categories) do
        if not (cat.Absente and cat.Absente()) then
            for _, pp in ipairs(portees) do
                local r = calcul.Resultat(cat.cle, pp)
                if r then
                    HautsFaits(cat.cle, r, faits, possibles)
                    if cleP then Dater(cleP, cat.cle, faits) end
                end
            end
        end
    end
    local pts, possible = 0, 0
    for _, x in pairs(faits) do pts = pts + x.pts end
    for _, v in pairs(possibles) do possible = possible + v end
    memoPoints[portee] = { version = version, pts = pts, possible = possible, faits = faits }
    return pts, possible, faits
end

-- Les derniers hauts faits du compte : { nom, pts, quand, perso }, du plus
-- recent au plus ancien (seulement ceux dates).
function calcul.Derniers(max)
    local liste = {}
    for _, p in ipairs(persos.Liste()) do
        local f = NS.base.DB().persos[p.cle]
        for k, x in pairs(type(f) == "table" and type(f.hautsFaits) == "table" and f.hautsFaits or {}) do
            if type(x) == "table" and (x.t or 0) > 0 then
                table.insert(liste, { cle = k, nom = x.nom, pts = x.pts, quand = x.t, perso = p, icone = x.icone })
            end
        end
    end
    table.sort(liste, function(a, b) return a.quand > b.quand end)
    while #liste > (max or 6) do table.remove(liste) end
    return liste
end

-- ---------------------------------------------------------------------------
-- Estimation du temps pour atteindre un niveau, au rythme reel : celui du
-- personnage a ces niveaux, sinon celui de ses autres personnages (un
-- reroll profite du chemin deja fait), sinon son rythme le plus proche.
-- Rend { xp, secondes (ou nil), source (nom d'un autre personnage ou nil) }.
-- ---------------------------------------------------------------------------

local MESURE_MINI = 300 -- secondes de jeu mesurees pour qu'un rythme compte

local function RythmeDe(cle, niveau, ecart)
    local r = persos.Rythme(cle)
    local xp, s = 0, 0
    for n = niveau - (ecart or 0), niveau + (ecart or 0) do
        local x = r[n]
        if type(x) == "table" then xp, s = xp + (x.xp or 0), s + (x.s or 0) end
    end
    if s >= MESURE_MINI and xp > 0 then return xp / s end
    return nil
end

local function RythmeAuNiveau(p, niveau)
    local v = RythmeDe(p.cle, niveau, 0)
    if v then return v end
    -- Les autres personnages, au meme niveau puis tout pres.
    for _, ecart in ipairs({ 0, 2 }) do
        local meilleur, nom
        for _, autre in ipairs(persos.Liste()) do
            if autre.cle ~= p.cle then
                local w = RythmeDe(autre.cle, niveau, ecart)
                if w and (not meilleur or w > meilleur) then meilleur, nom = w, autre.nom end
            end
        end
        if meilleur then return meilleur, nom end
    end
    return RythmeDe(p.cle, niveau, 3)
end

function calcul.Estimation(p, cible)
    local ref = NS.ref
    local niveau = p.niveau or 1
    local xp = 0
    local moi = p.cle == NS.ClePersonnage()
    local secondes, source, inconnu = 0, nil, false
    for n = niveau, cible - 1 do
        local besoin = ref.XP_NIVEAU[n] or 0
        if n == niveau and moi then
            local actuel = tonumber(NS.Sur(NS.Jeu("UnitXP", "player"))) or 0
            local maxi = tonumber(NS.Sur(NS.Jeu("UnitXPMax", "player"))) or besoin
            besoin = math.max(0, maxi - actuel)
        end
        xp = xp + besoin
        local v, nom = RythmeAuNiveau(p, n)
        if v then
            secondes = secondes + besoin / v
            if nom and not source then source = nom end
        else
            inconnu = true
        end
    end
    return { xp = xp, secondes = (not inconnu) and secondes or nil, source = source }
end
