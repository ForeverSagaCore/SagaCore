local _, NS = ...

-- Les categories d'AchievementCore : ce qu'il faut faire pour finir le jeu,
-- et ce qui est deja fait, pour un contexte (un personnage ou un camp, voir
-- Calcul.lua). Une categorie rend des sous-categories, chacune ses elements,
-- chaque element ses criteres (a la demande : Detail). Tout est compte en
-- criteres : un element a 3 / 12 a fait 3 de ses 12 criteres.

local T = NS.T
local ref = NS.ref
local base = NS.base
local persos = NS.persos
local Lire = base.Lire

-- ---------------------------------------------------------------------------
-- Outils communs
-- ---------------------------------------------------------------------------

local function Sous(res, cle, nom, ordre, icone)
    res.parCle = res.parCle or {}
    local s = res.parCle[cle]
    if not s then
        s = { cle = cle, nom = nom, ordre = ordre or (#res.sous + 1), icone = icone, fait = 0, total = 0, elements = {} }
        res.parCle[cle] = s
        table.insert(res.sous, s)
    end
    return s
end

local function Ajouter(res, s, e)
    table.insert(s.elements, e)
    s.fait, s.total = s.fait + e.fait, s.total + e.total
end

-- Range et nettoie un resultat : sous-categories et elements par ordre,
-- sans ce qui n'a rien a faire ; le total de la categorie.
local function Finir(res, sansSomme)
    res.parCle = nil
    local function Ordre(liste)
        table.sort(liste, function(a, b)
            if (a.ordre or 0) ~= (b.ordre or 0) then return (a.ordre or 0) < (b.ordre or 0) end
            return tostring(a.nom) < tostring(b.nom)
        end)
    end
    local gardees = {}
    for _, s in ipairs(res.sous) do
        local el = {}
        for _, e in ipairs(s.elements) do if e.total > 0 then table.insert(el, e) end end
        s.elements = el
        Ordre(el)
        if s.total > 0 then table.insert(gardees, s) end
    end
    res.sous = gardees
    Ordre(res.sous)
    if not sansSomme then
        res.fait, res.total = 0, 0
        for _, s in ipairs(res.sous) do res.fait, res.total = res.fait + s.fait, res.total + s.total end
    end
    return res
end

-- Pour un detail : l'ensemble de chaque personnage du contexte, lu une fois.
local function Ensembles(ctx, lecture)
    local t = {}
    if ctx.genre == "camp" then for _, p in ipairs(ctx.persos) do t[p.cle] = lecture(p.cle) end end
    return t
end

-- Les cles des personnages du contexte pour qui test(p) est vrai.
local function Qui(ctx, test)
    local l = {}
    if ctx.genre ~= "camp" then return l end
    for _, p in ipairs(ctx.persos) do if test(p) then table.insert(l, p.cle) end end
    return l
end

local function Critere(cle, nom, fait, extra)
    local c = extra or {}
    c.cle, c.nom, c.fait = cle, nom, fait and true or false
    return c
end

-- Noms gardes (zones, quetes, objets) : lus une fois par session.
local noms = { zone = {}, quete = {}, objet = {} }
local function NomDeZone(zone)
    local n = noms.zone[zone]
    if n == nil then
        n = base.NomDeZone(zone) or false
        if n then noms.zone[zone] = n end
    end
    return n or ("#" .. tostring(zone))
end
local function NomDeQuete(id)
    local n = noms.quete[id]
    if not n then
        n = Lire("QuestDB", id, "name")
        if type(n) ~= "string" then n = "#" .. tostring(id) else noms.quete[id] = n end
    end
    return n
end
local function NomDObjet(id)
    local n = noms.objet[id]
    if n then return n end
    n = NS.Jeu("C_Item.GetItemNameByID", id) or NS.Jeu("GetItemInfo", id)
    if type(n) == "string" and n ~= "" then noms.objet[id] = n return n end
    n = Lire("ItemDB", id, "name")
    return type(n) == "string" and n or ("#" .. tostring(id))
end
NS.NomDObjet, NS.NomDeQuete, NS.NomDeZoneGarde = NomDObjet, NomDeQuete, NomDeZone

local function IconeDObjet(id)
    return NS.Jeu("C_Item.GetItemIconByID", id) or NS.Jeu("GetItemIcon", id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ---------------------------------------------------------------------------
-- Quetes : qui peut faire quoi
-- ---------------------------------------------------------------------------

local function QueteAdmise(ctx, q)
    if ctx.genre == "camp" then
        if ctx.faction == "Alliance" then return q.okA == true end
        return q.okH == true
    end
    local p = ctx.perso
    if p.faction == "Alliance" and not q.okA then return false end
    if p.faction == "Horde" and not q.okH then return false end
    if p.race and (q.races or 0) ~= 0 and not NS.Bit(q.races, p.race) then return false end
    local idClasse = ref.ID_CLASSE[p.classe or ""]
    if idClasse and (q.classes or 0) ~= 0 and not NS.Bit(q.classes, idClasse) then return false end
    return true
end

-- Les quetes faites du contexte : { [id] = true }.
local function QuetesFaites(ctx)
    if ctx.genre ~= "camp" then return persos.Quetes(ctx.perso.cle) end
    return persos.Union("quetes" .. ctx.faction, ctx.persos, persos.Quetes, NS.Version("quetes"))
end

local function QueteFaite(faites, q)
    return faites[q.id] or (q.cible and faites[q.cible]) or false
end

-- Un groupe (quetes exclusives) : admis, fait, et sa quete de reference.
local function Groupe(ctx, idx, g, faites)
    local premier, faite
    for _, id in ipairs(g.ids) do
        local q = idx.Q[id]
        if q and QueteAdmise(ctx, q) then
            local f = QueteFaite(faites, q)
            if not premier or (f and not faite) then premier = q end
            if f then faite = true end
        end
    end
    return premier, faite == true
end

-- Criteres de quetes d'une liste de groupes.
local function CriteresDeQuetes(ctx, idx, groupes)
    local faites = QuetesFaites(ctx)
    local parPerso = Ensembles(ctx, persos.Quetes)
    local liste = {}
    for _, g in ipairs(groupes) do
        local q, faite = Groupe(ctx, idx, g, faites)
        if q then
            local c = Critere("q" .. q.id, NomDeQuete(q.id), faite, { quete = q.id, niveau = q.niveau,
                icone = "Interface\\GossipFrame\\AvailableQuestIcon" })
            if #g.ids > 1 then c.auChoix = true end
            c.qui = Qui(ctx, function(p)
                local f = parPerso[p.cle]
                for _, id in ipairs(g.ids) do if idx.Q[id] and QueteFaite(f, idx.Q[id]) then return true end end
                return false
            end)
            table.insert(liste, c)
        end
    end
    table.sort(liste, function(a, b)
        if (a.niveau or 0) ~= (b.niveau or 0) then return (a.niveau or 0) < (b.niveau or 0) end
        return a.nom < b.nom
    end)
    return liste
end

local ICONE_QUETES = "Interface\\Icons\\INV_Misc_Book_08"

local function CategorieQuetes()
    return { cle = "quetes", icone = ICONE_QUETES, versions = { "quetes" },
        nom = function() return T("Quêtes", "Quests") end,
        intro = function() return T("Toutes les quêtes faisables ; les répétables et les retirées ne comptent pas, deux quêtes au choix comptent pour une.",
            "Every quest you can do ; repeatable and retired quests do not count, two either-or quests count as one.") end,
        Absente = function() return base.Quetes() == false end,
        Pret = function() return type(base.Quetes()) == "table" end,
        Progres = function() return base.etat.progresQuetes end,
        Calculer = function(ctx)
            local idx = base.Quetes()
            local faites = QuetesFaites(ctx)
            local res = { sous = {} }
            local sZones = Sous(res, "zones", T("Par zone", "By zone"), 1, "Interface\\Icons\\INV_Misc_Map_01")
            local sSuites = Sous(res, "suites", T("Suites de quêtes", "Quest chains"), 2, "Interface\\Icons\\INV_Misc_Book_09")
            local sThemes = Sous(res, "themes", T("Classes, métiers et fêtes", "Classes, professions and holidays"), 3, "Interface\\Icons\\INV_Misc_Note_01")
            local sCamps = Sous(res, "camps", T("Par camp", "By side"), 4, "Interface\\Icons\\INV_BannerPVP_02")
            local parZone, parChaine, parCamp = {}, {}, {}
            local total, fait = 0, 0
            local function Element(s, table_, cle, nom, ordre, icone)
                local e = table_[cle]
                if not e then
                    e = { cle = cle, nom = nom, ordre = ordre, icone = icone, fait = 0, total = 0, groupes = {} }
                    table_[cle] = e
                    table.insert(s.elements, e)
                end
                return e
            end
            for _, g in ipairs(idx.groupes) do
                local q, faite = Groupe(ctx, idx, g, faites)
                if q then
                    total = total + 1
                    if faite then fait = fait + 1 end
                    local function Compter(e)
                        e.total = e.total + 1
                        if faite then e.fait = e.fait + 1 end
                        table.insert(e.groupes, g)
                    end
                    local zone = q.zone or 0
                    if zone > 0 then
                        Compter(Element(sZones, parZone, zone, NomDeZone(zone), idx.niveauZone[zone] or 999, ICONE_QUETES))
                    else
                        local th = ref.THEMES[zone]
                        local ordre = (th and th.classe and 1) or (th and th.metier and 2) or (th and th.fete and 3) or 4
                        Compter(Element(sThemes, parZone, zone, ref.NomDeTheme(zone), ordre, "Interface\\Icons\\INV_Misc_Note_01"))
                    end
                    if q.chaine and idx.chaines[q.chaine] then
                        local c = idx.chaines[q.chaine]
                        Compter(Element(sSuites, parChaine, q.chaine, NomDeQuete(c.premiere), c.niveau or 0, "Interface\\Icons\\INV_Misc_Book_09"))
                    end
                    local camp = q.camp or "N"
                    local nomCamp = (camp == "A" and T("Quêtes de l'Alliance", "Alliance quests"))
                        or (camp == "H" and T("Quêtes de la Horde", "Horde quests")) or T("Quêtes des deux camps", "Quests for both sides")
                    Compter(Element(sCamps, parCamp, camp, nomCamp, (camp == "N") and 3 or (camp == "A" and 1 or 2), "Interface\\Icons\\INV_BannerPVP_02"))
                end
            end
            for _, s in ipairs(res.sous) do
                for _, e in ipairs(s.elements) do
                    s.fait, s.total = s.fait + e.fait, s.total + e.total
                    local groupes = e.groupes
                    e.groupes = nil
                    local nz = s.cle == "zones" and idx.niveauZone[e.cle]
                    if nz then e.detail = string.format(T("Niveau %d  %d / %d", "Level %d  %d / %d"), nz, e.fait, e.total) end
                    e.Detail = function() return CriteresDeQuetes(ctx, idx, groupes) end
                end
            end
            Finir(res, true)
            res.fait, res.total = fait, total
            return res
        end }
end

-- ---------------------------------------------------------------------------
-- Exploration
-- ---------------------------------------------------------------------------

local DIRECTIONS = {
    { "nord-ouest", "north-west" }, { "nord", "north" }, { "nord-est", "north-east" },
    { "ouest", "west" }, { "centre", "centre" }, { "est", "east" },
    { "sud-ouest", "south-west" }, { "sud", "south" }, { "sud-est", "south-east" },
}
local function Direction(cle)
    local l, h, x, y = string.match(cle, "^(%d+):(%d+):(%d+):(%d+)$")
    if not l then return T("centre", "centre") end
    local cx = (tonumber(x) + tonumber(l) / 2) / 1002
    local cy = (tonumber(y) + tonumber(h) / 2) / 668
    local col = math.max(0, math.min(2, math.floor(cx * 3)))
    local lig = math.max(0, math.min(2, math.floor(cy * 3)))
    local d = DIRECTIONS[lig * 3 + col + 1]
    return T(d[1], d[2])
end

local function NomDeMorceau(art, cle)
    local d = base.DB()
    local zone = type(d.lieux[art]) == "table" and d.lieux[art][cle]
    local nom = zone and base.NomDeZone(zone)
    if nom then return nom, true end
    return string.format(T("Lieu inconnu (%s)", "Unknown place (%s)"), Direction(cle)), false
end

local function CategorieExploration()
    return { cle = "exploration", icone = "Interface\\Icons\\INV_Misc_Map_01", versions = { "exploration" },
        nom = function() return T("Exploration", "Exploration") end,
        intro = function() return T("Chaque zone : y être allé, et chacun de ses lieux découvert sur la carte (nommé dès qu'un personnage l'a découvert).",
            "Every zone : having been there, and each of its places discovered on the map (named once a character has found it).") end,
        Calculer = function(ctx)
            local res = { sous = {} }
            for rang, z in ipairs(base.Zones()) do
                local s = Sous(res, "c" .. tostring(z.continent), z.nomContinent, z.continent)
                local morceaux = base.Morceaux(z.art)
                local function Explore(p, cle)
                    local e = persos.Exploration(p.cle)[z.carte]
                    return type(e) == "table" and e[cle] == true
                end
                local function Visite(p)
                    local e = persos.Exploration(p.cle)[z.carte]
                    return persos.Visites(p.cle)[z.carte] == true or (type(e) == "table" and next(e) ~= nil)
                end
                local function Un(test)
                    for _, p in ipairs(ctx.persos) do if test(p) then return true end end
                    return false
                end
                local fait = Un(Visite) and 1 or 0
                for _, m in ipairs(morceaux) do
                    if Un(function(p) return Explore(p, m) end) then fait = fait + 1 end
                end
                Ajouter(res, s, { cle = "z" .. z.carte, nom = z.nom, ordre = rang, icone = "Interface\\Icons\\INV_Misc_Map_01",
                    fait = fait, total = 1 + #morceaux,
                    Detail = function()
                        local liste = { Critere("visite", T("Y être allé", "Been there"), Un(Visite),
                            { qui = Qui(ctx, Visite), icone = "Interface\\Icons\\INV_Misc_Map_01" }) }
                        local lieux = {}
                        for _, m in ipairs(morceaux) do
                            local nom, connu = NomDeMorceau(z.art, m)
                            table.insert(lieux, Critere("m" .. m, nom, Un(function(p) return Explore(p, m) end),
                                { qui = Qui(ctx, function(p) return Explore(p, m) end), connu = connu,
                                  icone = "Interface\\Icons\\INV_Misc_Spyglass_02" }))
                        end
                        table.sort(lieux, function(a, b)
                            if a.connu ~= b.connu then return a.connu end
                            return a.nom < b.nom
                        end)
                        -- Deux lieux inconnus du meme cote : numerotes.
                        local vus = {}
                        for _, c in ipairs(lieux) do
                            vus[c.nom] = (vus[c.nom] or 0) + 1
                            if vus[c.nom] > 1 then c.nom = c.nom .. " " .. vus[c.nom] end
                            table.insert(liste, c)
                        end
                        return liste
                    end })
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Donjons et raids
-- ---------------------------------------------------------------------------

-- Un rare : tue par un personnage ?
local function RareTue(p, id) return persos.Rares(p.cle)[id] ~= nil end

-- Les criteres de rares d'une liste (sans ceux dont le nom est un boss).
local function CriteresDeRares(ctx, liste, exclus)
    local crit = {}
    for _, r in ipairs(liste or {}) do
        if not (exclus and exclus[NS.Cle(r.nom)]) then
            local id = r.id
            local function Tue(p) return RareTue(p, id) end
            local un = false
            for _, p in ipairs(ctx.persos) do if Tue(p) then un = true break end end
            table.insert(crit, Critere("rare:" .. id, r.nom, un, { qui = Qui(ctx, Tue), niveau = r.niveau,
                icone = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", pnj = id }))
        end
    end
    return crit
end

local function NomDeBoss(b)
    local n = base.DB().nomsBoss
    return (type(n) == "table" and n[b.cle]) or b.nom
end

local function CategorieDonjons()
    return { cle = "donjons", icone = "Interface\\Icons\\INV_Misc_Key_14", versions = { "donjons", "quetes", "rares" },
        nom = function() return T("Donjons et raids", "Dungeons and raids") end,
        intro = function() return T("Un donjon n'est fini qu'avec tous ses boss, tous ses rares et toutes ses quêtes.",
            "A dungeon is only done with all its bosses, all its rares and all its quests.") end,
        Calculer = function(ctx)
            local res = { sous = {} }
            local idx = type(base.Quetes()) == "table" and base.Quetes() or nil
            local groupesDe = {}
            if idx then
                for _, g in ipairs(idx.groupes) do
                    local d = base.DonjonDeZone(g.zone)
                    if d then groupesDe[d.zone] = groupesDe[d.zone] or {} table.insert(groupesDe[d.zone], g) end
                end
            end
            local faites = idx and QuetesFaites(ctx) or {}
            local dbRencontres = base.DB().rencontres
            local rares = type(base.Rares()) == "table" and base.Rares() or nil
            local rencontres = base.Rencontres()
            -- Les donjons de la base, puis ceux que seul le journal connait.
            local liste = {}
            for _, d in ipairs(base.Donjons()) do table.insert(liste, d) end
            local nomsDonjons = type(base.DB().nomsDonjons) == "table" and base.DB().nomsDonjons or {}
            for zone, nom in pairs(rencontres and rencontres.extra or {}) do
                table.insert(liste, { zone = zone, nom = nomsDonjons[zone] or nom, raid = false, autres = {}, forever = true, horsBase = true })
            end
            for rang, d in ipairs(liste) do
                local s = d.raid and Sous(res, "raids", T("Raids", "Raids"), 2, "Interface\\Icons\\INV_Misc_Head_Dragon_01")
                    or Sous(res, "donjons", T("Donjons", "Dungeons"), 1, "Interface\\Icons\\INV_Misc_Key_14")
                -- Boss : ceux du journal des donjons (numeros de rencontre),
                -- sinon ceux de la base (raids), sinon ceux deja rencontres.
                local boss, vus, nomsBoss = {}, {}, {}
                local duJournal = rencontres and rencontres.parZone[d.zone]
                if duJournal then
                    for _, b in ipairs(duJournal) do
                        table.insert(boss, { cle = b.cle, nom = NomDeBoss(b), ids = b.ids })
                        nomsBoss[NS.Cle(b.nom)] = true
                    end
                else
                    for _, b in ipairs(base.BossDeZone(d.zone) or {}) do
                        table.insert(boss, { cle = "pnj:" .. b.id, nom = b.nom }) vus["pnj:" .. b.id] = true
                        nomsBoss[NS.Cle(b.nom)] = true
                    end
                    for cle, nom in pairs(type(dbRencontres[d.zone]) == "table" and dbRencontres[d.zone] or {}) do
                        if not vus[cle] then table.insert(boss, { cle = cle, nom = tostring(nom) }) vus[cle] = true end
                    end
                end
                table.sort(boss, function(a, b) return a.nom < b.nom end)
                -- Les rares de l'instance (et de ses autres zones).
                local raresIci = {}
                if rares then
                    for _, z in ipairs({ d.zone, unpack(d.autres or {}) }) do
                        for _, r in ipairs(rares.parZone[z] or {}) do table.insert(raresIci, r) end
                    end
                end
                local groupes = groupesDe[d.zone] or {}
                if d.forever or #boss > 0 or #groupes > 0 then
                    local function Entre(p) return persos.Instances(p.cle)[d.zone] == true end
                    local function Battu(p, b)
                        local t = persos.Boss(p.cle)[d.zone]
                        if type(t) ~= "table" then return false end
                        if t[b.cle] then return true end
                        for id in pairs(b.ids or {}) do if t["renc:" .. id] then return true end end
                        return false
                    end
                    local function Un(test) for _, p in ipairs(ctx.persos) do if test(p) then return true end end return false end
                    local avecEntree = not d.horsBase
                    local fait, total = 0, 0
                    if avecEntree then total = 1 if Un(Entre) then fait = 1 end end
                    total = total + #boss
                    local bossFaits, raresFaits, quetes, quetesFaites = 0, 0, 0, 0
                    for _, b in ipairs(boss) do if Un(function(p) return Battu(p, b) end) then fait = fait + 1 bossFaits = bossFaits + 1 end end
                    local critRares = CriteresDeRares(ctx, raresIci, nomsBoss)
                    total = total + #critRares
                    for _, c in ipairs(critRares) do if c.fait then fait = fait + 1 raresFaits = raresFaits + 1 end end
                    for _, g in ipairs(groupes) do
                        local q, faite = Groupe(ctx, idx, g, faites)
                        if q then
                            total = total + 1
                            quetes = quetes + 1
                            if faite then fait = fait + 1 quetesFaites = quetesFaites + 1 end
                        end
                    end
                    -- Le detail de la carte : boss, rares et quetes.
                    local morceaux = {}
                    if #boss > 0 then table.insert(morceaux, string.format(T("Boss %d/%d", "Bosses %d/%d"), bossFaits, #boss)) end
                    if #critRares > 0 then table.insert(morceaux, string.format(T("Rares %d/%d", "Rares %d/%d"), raresFaits, #critRares)) end
                    if quetes > 0 then table.insert(morceaux, string.format(T("Quêtes %d/%d", "Quests %d/%d"), quetesFaites, quetes)) end
                    if avecEntree and not Un(Entre) and fait == 0 then morceaux = { T("Jamais entré", "Never entered") } end
                    Ajouter(res, s, { cle = "d" .. tostring(d.zone), nom = d.nom, ordre = rang, detail = table.concat(morceaux, "  "),
                        icone = d.raid and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_14",
                        fait = fait, total = total,
                        Detail = function()
                            local liste = {}
                            if avecEntree then
                                table.insert(liste, Critere("entre", T("Y être entré", "Entered"), Un(Entre),
                                    { qui = Qui(ctx, Entre), icone = "Interface\\Icons\\INV_Misc_Key_14" }))
                            end
                            for _, b in ipairs(boss) do
                                local bb = b
                                table.insert(liste, Critere(b.cle, b.nom, Un(function(p) return Battu(p, bb) end),
                                    { qui = Qui(ctx, function(p) return Battu(p, bb) end), icone = "Interface\\Icons\\INV_Misc_Head_Dragon_01" }))
                            end
                            for _, c in ipairs(critRares) do table.insert(liste, c) end
                            if idx then
                                for _, c in ipairs(CriteresDeQuetes(ctx, idx, groupes)) do table.insert(liste, c) end
                            end
                            return liste
                        end })
                end
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Rares du monde (ceux des instances comptent dans leur donjon)
-- ---------------------------------------------------------------------------

local function CategorieRares()
    return { cle = "rares", icone = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", versions = { "rares" },
        nom = function() return T("Rares", "Rares") end,
        intro = function() return T("Chaque monstre rare du monde, zone par zone : il compte quand toi ou ton groupe l'avez tué.",
            "Every rare monster of the world, zone by zone : it counts once you or your group killed it.") end,
        Absente = function() return base.Rares() == false end,
        Pret = function() return type(base.Rares()) == "table" end,
        Calculer = function(ctx)
            local res = { sous = {} }
            local rares = base.Rares()
            for zone, liste in pairs(rares.parZone) do
                if not base.DonjonDeZone(zone) then
                    local c = base.ContinentDeZone(zone)
                    local s = Sous(res, c and ("c" .. c.id) or "autres", c and c.nom or T("Autres lieux", "Other places"),
                        c and c.id or 99999, "Interface\\Icons\\INV_Misc_Map_01")
                    local crit = CriteresDeRares(ctx, liste)
                    local fait = 0
                    for _, x in ipairs(crit) do if x.fait then fait = fait + 1 end end
                    local niveau = liste[1] and liste[1].niveau or 0
                    Ajouter(res, s, { cle = zone, nom = NomDeZone(zone), ordre = niveau, zone = zone,
                        detail = string.format(T("Niveau %d  %d / %d", "Level %d  %d / %d"), niveau, fait, #crit),
                        icone = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", fait = fait, total = #crit,
                        Detail = function() return CriteresDeRares(ctx, liste) end })
                end
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Objets
-- ---------------------------------------------------------------------------

local function NomDeFamille(famille)
    local n = NS.Jeu("C_Item.GetItemClassInfo", famille) or NS.Jeu("GetItemClassInfo", famille)
    if type(n) == "string" and n ~= "" then return n end
    return T("Famille ", "Class ") .. tostring(famille)
end
local function NomDeSousFamille(famille, sous)
    local n = NS.Jeu("C_Item.GetItemSubClassInfo", famille, sous) or NS.Jeu("GetItemSubClassInfo", famille, sous)
    if type(n) == "string" and n ~= "" then return n end
    return NomDeFamille(famille) .. " " .. tostring(sous)
end
local ICONES_FAMILLE = { [0] = "Interface\\Icons\\INV_Potion_51", [1] = "Interface\\Icons\\INV_Misc_Bag_08",
    [2] = "Interface\\Icons\\Trade_BlackSmithing", [4] = "Interface\\Icons\\INV_Chest_Chain", [5] = "Interface\\Icons\\INV_Misc_Herb_01",
    [6] = "Interface\\Icons\\INV_Ammo_Arrow_02", [7] = "Interface\\Icons\\INV_Misc_Herb_01", [9] = "Interface\\Icons\\INV_Scroll_03",
    [11] = "Interface\\Icons\\INV_Misc_Bag_10", [12] = "Interface\\Icons\\INV_Letter_15", [13] = "Interface\\Icons\\INV_Misc_Key_14",
    [15] = "Interface\\Icons\\INV_Misc_Gift_02" }

local function ObjetsEus(ctx)
    if ctx.genre ~= "camp" then return persos.Objets(ctx.perso.cle) end
    return persos.Union("objets" .. ctx.faction, ctx.persos, persos.Objets, NS.Version("objets"))
end

local function CategorieObjets()
    return { cle = "objets", icone = "Interface\\Icons\\INV_Misc_Bag_10", versions = { "objets" },
        nom = function() return T("Objets", "Items") end,
        intro = function() return T("Chaque objet obtenable (butin, marchand, quête, fabrication), eu au moins une fois dans les sacs, la banque ou sur soi.",
            "Every item you can get (loot, vendor, quest, crafting), held at least once in bags, bank or worn.") end,
        Absente = function() return base.Objets() == false end,
        Pret = function() return type(base.Objets()) == "table" end,
        Progres = function() return base.etat.progresObjets end,
        Calculer = function(ctx)
            local idx = base.Objets()
            local eus = ObjetsEus(ctx)
            local faitPar = {}
            for id in pairs(eus) do
                local cle = idx.de[tonumber(id) or id]
                if cle then faitPar[cle] = (faitPar[cle] or 0) + 1 end
            end
            local res = { sous = {} }
            for famille, cles in pairs(idx.familles) do
                local s = Sous(res, "f" .. famille, NomDeFamille(famille), famille, ICONES_FAMILLE[famille])
                for _, cle in ipairs(cles) do
                    local ps = idx.parSous[cle]
                    Ajouter(res, s, { cle = "s" .. cle, nom = NomDeSousFamille(ps.famille, ps.sous), ordre = ps.sous,
                        icone = ICONES_FAMILLE[famille] or "Interface\\Icons\\INV_Misc_Gift_02",
                        fait = faitPar[cle] or 0, total = #ps.ids,
                        Detail = function()
                            local liste = {}
                            local parPerso = Ensembles(ctx, persos.Objets)
                            for _, id in ipairs(ps.ids) do
                                table.insert(liste, Critere("o" .. id, NomDObjet(id), eus[id] == true,
                                    { objet = id, qui = Qui(ctx, function(p) return parPerso[p.cle][id] == true end) }))
                            end
                            table.sort(liste, function(a, b) return a.nom < b.nom end)
                            return liste
                        end })
                end
            end
            return Finir(res)
        end }
end
NS.IconeDObjet = IconeDObjet

-- ---------------------------------------------------------------------------
-- Metiers : les quatre rangs et toutes les recettes de chaque metier
-- ---------------------------------------------------------------------------

local function CategorieMetiers()
    return { cle = "metiers", icone = "Interface\\Icons\\Trade_BlackSmithing", versions = { "metiers" },
        nom = function() return T("Métiers", "Professions") end,
        intro = function() return T("Chaque métier jusqu'à Artisan et toutes ses recettes ; un personnage compte ses deux métiers principaux.",
            "Every profession up to Artisan and all its recipes ; a character counts their two main professions.") end,
        Calculer = function(ctx)
            local catalogue = persos.Catalogue()
            local parLigne = {}
            for id, r in pairs(catalogue) do
                parLigne[r.ligne] = parLigne[r.ligne] or {}
                table.insert(parLigne[r.ligne], { id = id, nom = r.nom or ("#" .. tostring(id)) })
            end
            for _, l in pairs(parLigne) do table.sort(l, function(a, b) return a.nom < b.nom end) end
            local metiersDe, recettesDe = {}, {}
            for _, p in ipairs(ctx.persos) do metiersDe[p.cle] = persos.Metiers(p.cle) recettesDe[p.cle] = persos.Recettes(p.cle) end
            -- Les metiers a compter.
            local lignes = {}
            if ctx.genre == "camp" then
                for _, m in ipairs(ref.METIERS) do table.insert(lignes, m.ligne) end
                local vus = {}
                for _, l in ipairs(lignes) do vus[l] = true end
                for _, p in ipairs(ctx.persos) do
                    for l in pairs(metiersDe[p.cle]) do if not vus[l] then vus[l] = true table.insert(lignes, l) end end
                end
            else
                local principaux = 0
                for l in pairs(metiersDe[ctx.perso.cle]) do
                    local m = ref.METIER[l]
                    if not (m and m.secondaire) then table.insert(lignes, l) principaux = principaux + 1 end
                end
                for k = principaux + 1, ref.METIERS_PRINCIPAUX_MAX do table.insert(lignes, "libre" .. k) end
                for _, m in ipairs(ref.METIERS) do if m.secondaire then table.insert(lignes, m.ligne) end end
            end
            local res = { sous = {} }
            for rang, ligne in ipairs(lignes) do
                local m = ref.METIER[ligne]
                local s = (m and m.secondaire) and Sous(res, "secondaires", T("Métiers secondaires", "Secondary professions"), 2, "Interface\\Icons\\INV_Misc_Food_15")
                    or Sous(res, "principaux", T("Métiers principaux", "Main professions"), 1, "Interface\\Icons\\Trade_BlackSmithing")
                local libre = type(ligne) == "string"
                local nomConnu
                local function Rang(p)
                    local x = not libre and metiersDe[p.cle][ligne]
                    if x and x.nom then nomConnu = nomConnu or x.nom end
                    return x and x.rang or 0
                end
                local meilleur = 0
                for _, p in ipairs(ctx.persos) do meilleur = math.max(meilleur, Rang(p)) end
                local recettes = (not libre) and parLigne[ligne] or {}
                local function Apprise(p, id) return recettesDe[p.cle][id] == true end
                local fait, paliers, apprises = 0, {}, 0
                for _, r in ipairs(ref.RANGS_METIER) do if meilleur >= r.rang then fait = fait + 1 table.insert(paliers, r.rang) end end
                for _, r in ipairs(recettes) do
                    for _, p in ipairs(ctx.persos) do if Apprise(p, r.id) then fait = fait + 1 apprises = apprises + 1 break end end
                end
                local nom = libre and T("Métier principal à apprendre", "Main profession to learn") or ref.NomDeMetier(ligne, nomConnu)
                -- Chaque palier atteint (75, 150, 225, 300) est un haut fait a part.
                Ajouter(res, s, { cle = "m" .. tostring(ligne), nom = nom, ordre = rang, paliers = paliers,
                    detail = libre and T("À apprendre", "To learn") or string.format(T("Rang %d  Recettes %d / %d", "Rank %d  Recipes %d / %d"), meilleur, apprises, #recettes),
                    icone = m and m.icone or "Interface\\Icons\\INV_Misc_QuestionMark",
                    fait = fait, total = #ref.RANGS_METIER + #recettes,
                    Detail = function()
                        local liste = {}
                        for _, r in ipairs(ref.RANGS_METIER) do
                            local palier = r.rang
                            table.insert(liste, Critere("rang" .. palier, T(r.fr, r.en) .. " (" .. palier .. ")", meilleur >= palier,
                                { qui = Qui(ctx, function(p) return Rang(p) >= palier end), icone = m and m.icone }))
                        end
                        for _, r in ipairs(recettes) do
                            local id = r.id
                            table.insert(liste, Critere("r" .. tostring(id), r.nom, (function()
                                for _, p in ipairs(ctx.persos) do if Apprise(p, id) then return true end end
                                return false
                            end)(), { qui = Qui(ctx, function(p) return Apprise(p, id) end), icone = "Interface\\Icons\\INV_Scroll_03" }))
                        end
                        return liste
                    end })
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Races et classes : chaque classe, chaque race, chaque combinaison
-- ---------------------------------------------------------------------------

local function PaliersNiveau()
    local maxi = ref.NiveauMax()
    local l = {}
    for n = 10, maxi, 10 do table.insert(l, n) end
    if l[#l] ~= maxi then table.insert(l, maxi) end
    return l
end

local function IconeDeRace(race, sexe)
    local r = ref.RACE[race]
    local coords = _G.RACE_ICON_TCOORDS
    if r and type(coords) == "table" then
        local c = coords[string.upper(r.jeton) .. "_" .. ((sexe == 3) and "FEMALE" or "MALE")]
        if c then return "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races", c end
    end
    return "Interface\\Icons\\INV_Misc_GroupNeedMore", nil
end
local function IconeDeClasse(classe)
    local c = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classe]
    if c then return "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", c end
    return "Interface\\Icons\\INV_Misc_QuestionMark", nil
end

local function CategorieRaces()
    return { cle = "races", icone = "Interface\\Icons\\INV_Misc_GroupNeedMore", versions = { "races" },
        nom = function() return T("Races et classes", "Races and classes") end,
        intro = function() return T("Chaque classe et chaque race jusqu'au niveau maximum, et chaque combinaison possible menée au niveau maximum.",
            "Every class and race up to the maximum level, and every possible combination taken to the maximum level.") end,
        Calculer = function(ctx)
            local paliers = PaliersNiveau()
            local maxi = paliers[#paliers]
            local combos = base.Combinaisons()
            local classes, races, couples = {}, {}, {}
            if ctx.genre == "camp" then
                local vusC, vusR = {}, {}
                for _, c in ipairs(combos[ctx.faction] or {}) do
                    if not vusC[c.classe] then vusC[c.classe] = true table.insert(classes, c.classe) end
                    if not vusR[c.race] then vusR[c.race] = true table.insert(races, c.race) end
                    table.insert(couples, c)
                end
            else
                local p = ctx.perso
                if p.classe then table.insert(classes, p.classe) end
                if p.race then table.insert(races, p.race) end
                if p.classe and p.race then table.insert(couples, { race = p.race, classe = p.classe }) end
            end
            local function Meilleur(test)
                local n = 0
                for _, p in ipairs(ctx.persos) do if test(p) then n = math.max(n, p.niveau or 0) end end
                return n
            end
            local res = { sous = {} }
            local sC = Sous(res, "classes", T("Classes", "Classes"), 1, "Interface\\Icons\\INV_Misc_Book_11")
            local sR = Sous(res, "races", T("Races", "Races"), 2, "Interface\\Icons\\INV_Misc_GroupNeedMore")
            local sK = Sous(res, "combinaisons", T("Combinaisons", "Combinations"), 3, "Interface\\Icons\\INV_Misc_GroupNeedMore")
            local function Paliers(e, test)
                local n = Meilleur(test)
                e.fait, e.total = 0, #paliers
                for _, pal in ipairs(paliers) do if n >= pal then e.fait = e.fait + 1 end end
                e.Detail = function()
                    local liste = {}
                    for _, pal in ipairs(paliers) do
                        table.insert(liste, Critere("n" .. pal, string.format(T("Niveau %d", "Level %d"), pal), n >= pal,
                            { qui = Qui(ctx, function(p) return test(p) and (p.niveau or 0) >= pal end) }))
                    end
                    return liste
                end
                return e
            end
            for rang, classe in ipairs(classes) do
                local icone, coords = IconeDeClasse(classe)
                Ajouter(res, sC, Paliers({ cle = "c" .. classe, nom = ref.NomDeClasse(classe), ordre = ref.ID_CLASSE[classe] or rang,
                    icone = icone, coords = coords, couleur = ref.CouleurDeClasse(classe) }, function(p) return p.classe == classe end))
            end
            for rang, race in ipairs(races) do
                local icone, coords = IconeDeRace(race)
                Ajouter(res, sR, Paliers({ cle = "r" .. race, nom = ref.NomDeRace(race), ordre = race, icone = icone, coords = coords },
                    function(p) return p.race == race end))
            end
            local parRace = {}
            for _, c in ipairs(couples) do
                parRace[c.race] = parRace[c.race] or {}
                table.insert(parRace[c.race], c.classe)
            end
            for race, liste in pairs(parRace) do
                table.sort(liste, function(a, b) return (ref.ID_CLASSE[a] or 0) < (ref.ID_CLASSE[b] or 0) end)
                local icone, coords = IconeDeRace(race)
                local function Mene(classe) return Meilleur(function(p) return p.race == race and p.classe == classe end) >= maxi end
                local fait = 0
                for _, classe in ipairs(liste) do if Mene(classe) then fait = fait + 1 end end
                Ajouter(res, sK, { cle = "k" .. race, nom = ref.NomDeRace(race), ordre = race, icone = icone, coords = coords,
                    fait = fait, total = #liste,
                    Detail = function()
                        local l = {}
                        for _, classe in ipairs(liste) do
                            local ic, co = IconeDeClasse(classe)
                            table.insert(l, Critere("k" .. classe, string.format(T("%s au niveau %d", "%s at level %d"), ref.NomDeClasse(classe), maxi),
                                Mene(classe), { qui = Qui(ctx, function(p) return p.race == race and p.classe == classe and (p.niveau or 0) >= maxi end),
                                icone = ic, coords = co, couleur = ref.CouleurDeClasse(classe) }))
                        end
                        return l
                    end })
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Reputations
-- ---------------------------------------------------------------------------

local function NomDeRang(rang)
    local n = _G["FACTION_STANDING_LABEL" .. rang]
    if type(n) == "string" then return n end
    local noms = { [5] = T("Amical", "Friendly"), [6] = T("Honoré", "Honored"), [7] = T("Révéré", "Revered"), [8] = T("Exalté", "Exalted") }
    return noms[rang] or tostring(rang)
end

ref.NomDeRang = function(r) return NomDeRang(r) end

local function CategorieReputations()
    return { cle = "reputations", icone = "Interface\\Icons\\INV_Misc_Note_01", versions = { "reputations" }, plat = true,
        nom = function() return T("Réputations", "Reputations") end,
        intro = function() return T("Chaque faction, son rang et l'avancement vers le suivant. Les capitales de l'autre camp ne comptent pas.",
            "Every faction, its standing and the progress to the next. The other side's capitals do not count.") end,
        Calculer = function(ctx)
            local d = base.DB()
            local res = { sous = {} }
            for id in pairs(base.Factions()) do
                local function Rang(p) return tonumber(persos.Reputations(p.cle)[id]) end
                local ouverte, meilleur = false, 0
                for _, p in ipairs(ctx.persos) do
                    local r = Rang(p)
                    if r and r > 0 then ouverte = true meilleur = math.max(meilleur, r) end
                end
                if ouverte then
                    local info = type(d.factions[id]) == "table" and d.factions[id] or {}
                    local entete = info.entete or T("Autres", "Other")
                    local s = Sous(res, "e" .. entete, entete, info.entete and 1 or 2, "Interface\\Icons\\INV_Misc_Note_01")
                    local fait = 0
                    for _, r in ipairs(ref.PALIERS_REPUTATION) do if meilleur >= r then fait = fait + 1 end end
                    -- L'avancement actuel : celui du personnage le plus avance.
                    local rep
                    for _, p in ipairs(ctx.persos) do
                        local dd = persos.ReputationsDetail(p.cle)[id]
                        if type(dd) == "table" and tonumber(dd[1]) and (not rep or dd[1] > rep[1] or (dd[1] == rep[1] and (dd[2] or 0) > (rep[2] or 0))) then rep = dd end
                    end
                    Ajouter(res, s, { cle = "f" .. id, nom = info.nom or ("#" .. id), icone = "Interface\\Icons\\INV_Misc_Note_01",
                        fait = fait, total = #ref.PALIERS_REPUTATION, rang = rep and rep[1] or meilleur,
                        valeur = rep and rep[2], mini = rep and rep[3], maxi = rep and rep[4],
                        Detail = function()
                            local l = {}
                            for _, r in ipairs(ref.PALIERS_REPUTATION) do
                                table.insert(l, Critere("p" .. r, NomDeRang(r), meilleur >= r,
                                    { qui = Qui(ctx, function(p) return (Rang(p) or 0) >= r end) }))
                            end
                            return l
                        end })
                end
            end
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- JcJ : rangs d'honneur et une victoire dans chaque champ de bataille
-- ---------------------------------------------------------------------------

local function CategorieJcJ()
    return { cle = "jcj", icone = "Interface\\Icons\\INV_BannerPVP_02", versions = { "jcj" },
        nom = function() return T("JcJ", "PvP") end,
        intro = function() return T("Chaque rang d'honneur, du premier au quatorzième, et une victoire dans chaque champ de bataille.",
            "Every honour rank, from the first to the fourteenth, and a win in each battleground.") end,
        Calculer = function(ctx)
            local res = { sous = {} }
            local s = Sous(res, "jcj", T("Honneur", "Honour"), 1, "Interface\\Icons\\INV_BannerPVP_02")
            local function Rang(p) return tonumber(persos.JcJ(p.cle).rang) or 0 end
            local meilleur = 0
            for _, p in ipairs(ctx.persos) do meilleur = math.max(meilleur, Rang(p)) end
            Ajouter(res, s, { cle = "rangs", nom = T("Rangs d'honneur", "Honour ranks"), ordre = 1, icone = "Interface\\Icons\\INV_BannerPVP_02",
                fait = math.min(meilleur, ref.RANGS_JCJ), total = ref.RANGS_JCJ,
                Detail = function()
                    local l = {}
                    for r = 1, ref.RANGS_JCJ do
                        table.insert(l, Critere("r" .. r, string.format(T("Rang %d", "Rank %d"), r), meilleur >= r,
                            { qui = Qui(ctx, function(p) return Rang(p) >= r end) }))
                    end
                    return l
                end })
            local function Gagne(p, zone)
                local v = persos.JcJ(p.cle).victoires
                return type(v) == "table" and (tonumber(v[zone]) or 0) > 0
            end
            local fait = 0
            for _, ch in ipairs(ref.CHAMPS) do
                for _, p in ipairs(ctx.persos) do if Gagne(p, ch.zone) then fait = fait + 1 break end end
            end
            Ajouter(res, s, { cle = "champs", nom = T("Champs de bataille", "Battlegrounds"), ordre = 2, icone = "Interface\\Icons\\INV_BannerPVP_01",
                fait = fait, total = #ref.CHAMPS,
                Detail = function()
                    local l = {}
                    for _, ch in ipairs(ref.CHAMPS) do
                        local zone = ch.zone
                        local oui = false
                        for _, p in ipairs(ctx.persos) do if Gagne(p, zone) then oui = true end end
                        table.insert(l, Critere("b" .. zone, string.format(T("Une victoire : %s", "A win : %s"), base.NomDeZone(zone) or T(ch.fr, ch.en)), oui,
                            { qui = Qui(ctx, function(p) return Gagne(p, zone) end) }))
                    end
                    return l
                end })
            return Finir(res)
        end }
end

-- ---------------------------------------------------------------------------
-- Heritage (releve de LegacyCore) : tous les talents d'heritage
-- ---------------------------------------------------------------------------

local GENRES_ARBRE = { aventure = { 1, "Aventure", "Adventure" }, ressources = { 2, "Ingéniosité", "Ingenuity" },
    metiers = { 3, "Métiers", "Professions" } }

local function ArbresDe(cle)
    local f = persos.LC(cle)
    return f and type(f.arbres) == "table" and f.arbres or {}
end

local function CategorieHeritage()
    return { cle = "heritage", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom", versions = { "heritage" },
        nom = function() return T("Héritage", "Legacy") end,
        intro = function() return T("Chaque talent des arbres d'héritage à son rang maximum, d'après LegacyCore.",
            "Every legacy talent at its maximum rank, from LegacyCore.") end,
        Absente = function()
            local d = _G.LegacyCoreDB
            if type(d) ~= "table" or type(d.persos) ~= "table" then return true end
            for _, f in pairs(d.persos) do if type(f) == "table" and type(f.arbres) == "table" and #f.arbres > 0 then return false end end
            return true
        end,
        Calculer = function(ctx)
            local res = { sous = {} }
            local s = Sous(res, "arbres", T("Arbres d'héritage", "Legacy trees"), 1, "Interface\\Icons\\Spell_Holy_SealOfWisdom")
            local parGenre = {}
            for _, p in ipairs(ctx.persos) do
                for _, a in ipairs(ArbresDe(p.cle)) do
                    local g = parGenre[a.genre or "aventure"]
                    if not g then g = { noeuds = {}, ordre = {} } parGenre[a.genre or "aventure"] = g end
                    for _, n in ipairs(type(a.noeuds) == "table" and a.noeuds or {}) do
                        if n.id then
                            local x = g.noeuds[n.id]
                            if not x then x = { id = n.id, nom = n.nom or ("#" .. n.id), icone = n.icone, maxi = tonumber(n.maxi) or 1, qui = {} } g.noeuds[n.id] = x table.insert(g.ordre, x) end
                            if (tonumber(n.rang) or 0) >= x.maxi then x.fait = true table.insert(x.qui, p.cle) end
                        end
                    end
                end
            end
            for genre, g in pairs(parGenre) do
                local def = GENRES_ARBRE[genre] or { 9, genre, genre }
                local fait = 0
                for _, x in ipairs(g.ordre) do if x.fait then fait = fait + 1 end end
                Ajouter(res, s, { cle = "a" .. genre, nom = T(def[2], def[3]), ordre = def[1], icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
                    fait = fait, total = #g.ordre,
                    Detail = function()
                        local l = {}
                        for _, x in ipairs(g.ordre) do
                            table.insert(l, Critere("n" .. x.id, x.nom, x.fait, { icone = x.icone, qui = ctx.genre == "camp" and x.qui or {} }))
                        end
                        return l
                    end })
            end
            return Finir(res)
        end }
end

-- L'ordre des pages : celui du journal des hauts faits.
NS.categories = {
    CategorieExploration(), CategorieQuetes(), CategorieDonjons(), CategorieRares(), CategorieObjets(), CategorieMetiers(),
    CategorieRaces(), CategorieReputations(), CategorieJcJ(), CategorieHeritage(),
}
