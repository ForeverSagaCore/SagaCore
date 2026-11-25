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
