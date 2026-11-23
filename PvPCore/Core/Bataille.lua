local _, NS = ...

-- Ce que chaque champ de bataille a de propre, lu en direct :
--   Goulet des Chanteguerres : score des captures, retour des drapeaux ;
--   Bassin Arathi : bases et ressources de chaque camp, vitesse de gain,
--     vainqueur et score final prevus, bases a tenir pour gagner ;
--   Vallee d'Alterac : tours, fortins et cimetieres (a qui, attaques,
--     detruits), renforts, vie des capitaines et des generaux.
-- Tout est lu dans ce que le jeu affiche (objectifs du haut de l'ecran,
-- icones de la carte, unites visibles). Rien n'est envoye ni clique.

NS.bataille = {}
local B = NS.bataille
local T = NS.T

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Nombre(v) if Secret(v) then return nil end return tonumber(v) end
local function Lire(nom) return NS.Lecture(nom) end
local RENFORTS = { "renfort", "reinforc" }
local function Horloge() return (GetTime and GetTime()) or 0 end
local function Minutes(s) return NS.champ.Minutes(s) end

-- ---------------------------------------------------------------------------
-- Quel champ de bataille
-- ---------------------------------------------------------------------------

-- Cartes (uiMapID) et instances des trois champs de bataille de Classic.
B.CARTES = { goulet = 1460, arathi = 1461, alterac = 1459 }
local PAR_CARTE = { [1460] = "goulet", [1461] = "arathi", [1459] = "alterac" }
local PAR_INSTANCE = { [489] = "goulet", [529] = "arathi", [30] = "alterac" }

function B.Quel()
    if not NS.honneur.EnChamp() then return nil end
    local r = { NS.Appeler(Lire("GetInstanceInfo")) }
    local instance = Nombre(r[8])
    if instance and PAR_INSTANCE[instance] then return PAR_INSTANCE[instance] end
    local carte = Nombre(NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
    return carte and PAR_CARTE[carte] or nil
end

local function NotreCamp()
    local camp = NS.Appeler(UnitFactionGroup, "player")
    return camp == "Horde" and "Horde" or "Alliance"
end
local function Autre(camp) return camp == "Horde" and "Alliance" or "Horde" end
B.NotreCamp, B.Autre = NotreCamp, Autre

-- ---------------------------------------------------------------------------
-- Les objectifs du haut de l'ecran, avec leur camp
-- ---------------------------------------------------------------------------

-- Le camp d'un texte d'objectif : nomme dans le texte, sinon par son rang
-- (le jeu montre l'Alliance a gauche, puis la Horde).
local function CampDuTexte(texte, rang)
    local bas = texte:lower()
    local a = (_G.FACTION_ALLIANCE or "Alliance"):lower()
    local h = (_G.FACTION_HORDE or "Horde"):lower()
    if bas:find(a, 1, true) and not bas:find(h, 1, true) then return "Alliance" end
    if bas:find(h, 1, true) and not bas:find(a, 1, true) then return "Horde" end
    return rang == 1 and "Alliance" or (rang == 2 and "Horde" or nil)
end

-- Les deux compteurs "N/M" (captures du Goulet, ressources d'Arathi) ou les
-- deux nombres seuls (renforts d'Alterac), par camp.
-- Avec un filtre (mots cherches en minuscules), seuls ces textes comptent.
function B.Compteurs(filtre)
    local r = {}
    local rang = 0
    for _, texte in ipairs(NS.honneur.Objectifs()) do
        local garde = type(texte) == "string" and not Secret(texte)
        if garde and filtre then
            garde = false
            local bas = texte:lower()
            for _, mot in ipairs(filtre) do if bas:find(mot, 1, true) then garde = true end end
        end
        if garde then
            local bases, n, m = texte:match("(%d)[^%d]+(%d+)%s*/%s*(%d+)")
            if not n then n, m = texte:match("(%d+)%s*/%s*(%d+)") end
            local seul = (not n) and texte:match(":%s*(%d+)%s*$")
            if n or seul then
                rang = rang + 1
                local camp = CampDuTexte(texte, rang)
                if camp and not r[camp] then
                    r[camp] = { n = tonumber(n or seul), m = tonumber(m), bases = tonumber(bases) }
                end
            end
        end
    end
    return r
end

-- ---------------------------------------------------------------------------
-- Bassin Arathi : bases, ressources et prevision
-- ---------------------------------------------------------------------------

-- Ressources gagnees par seconde selon le nombre de bases tenues (10 points
-- toutes les 12, 9, 6, 3 s, puis 30 par seconde avec les cinq bases).
B.VITESSE = { 10 / 12, 10 / 9, 10 / 6, 10 / 3, 30 }
local TICS = { { 10, 12 }, { 10, 9 }, { 10, 6 }, { 10, 3 }, { 30, 1 } }
local MAXI_ARATHI = 2000

-- Les objectifs d'Arathi : ceux du jeu (1893 Alliance, 1894 Horde, comme
-- Capping), sinon les textes du haut de l'ecran.
function B.LireArathi()
    local W = _G.C_UIWidgetManager
    local lire = W and W.GetIconAndTextWidgetVisualizationInfo
    local r = {}
    if lire then
        for camp, id in pairs({ Alliance = 1893, Horde = 1894 }) do
            local ok, info = pcall(lire, id)
            local texte = ok and type(info) == "table" and info.text
            if type(texte) == "string" and not Secret(texte) then
                local b, n, m = texte:match("(%d)[^%d]+(%d+)%s*/%s*(%d+)")
                if b then r[camp] = { bases = tonumber(b), n = tonumber(n), m = tonumber(m) } end
            end
        end
    end
    if not (r.Alliance and r.Horde) then
        local c = B.Compteurs()
        if c.Alliance and c.Horde and c.Alliance.bases and c.Horde.bases then r = c end
    end
    if not (r.Alliance and r.Horde) then return nil end
    return r
end

-- Temps pour finir (en secondes) avec tant de bases, depuis tant de ressources.
local function TempsPourFinir(bases, n, maxi)
    local v = B.VITESSE[bases]
    if not v then return math.huge end
    return math.max(0, (maxi - n) / v)
end

-- La prevision : { vainqueur, dans, finalPerdant, basesPourNous }, ou nil.
function B.PrevisionArathi(r)
    r = r or B.LireArathi()
    if not r then return nil end
    local maxi = r.Alliance.m or r.Horde.m or MAXI_ARATHI
    local tA = TempsPourFinir(r.Alliance.bases, r.Alliance.n, maxi)
    local tH = TempsPourFinir(r.Horde.bases, r.Horde.n, maxi)
    local p = { maxi = maxi }
    if tA < tH then p.vainqueur, p.dans = "Alliance", tA
    elseif tH < tA then p.vainqueur, p.dans = "Horde", tH end
    if p.vainqueur then
        local perdant = r[Autre(p.vainqueur)]
        local v = B.VITESSE[perdant.bases] or 0
        -- Arrondi a la dizaine, comme les tics du jeu, et jamais le maximum.
        p.final = math.min(maxi - 10, 10 * math.floor((perdant.n + v * p.dans) / 10))
    end
    -- Bases a tenir pour gagner : le moins possible, l'adversaire tenant le reste.
    local nous = NotreCamp()
    local a, e = r[nous], r[Autre(nous)]
    for k = 1, 5 do
        if TempsPourFinir(k, a.n, maxi) < TempsPourFinir(5 - k, e.n, maxi) then p.basesPourNous = k break end
    end
    return p
end

local function Tic(bases)
    local t = TICS[bases]
    if not t then return T("aucun gain", "no gain") end
    return string.format("+%d / %d s", t[1], t[2])
end

-- ---------------------------------------------------------------------------
-- Points d'interet : a qui, attaques, detruits
-- ---------------------------------------------------------------------------

-- L'etat de chaque icone (index de POIIcons) : genre, camp qui tient, camp
-- qui attaque, detruit. Bases d'Arathi : le meme ordre pour chaque base
-- (neutre, attaquee par l'Alliance, Alliance, attaquee par la Horde, Horde).
local ETATS = {}
local function Base(n, genre)
    ETATS[n] = { genre = genre }
    ETATS[n + 1] = { genre = genre, attaque = "Alliance" }
    ETATS[n + 2] = { genre = genre, camp = "Alliance" }
    ETATS[n + 3] = { genre = genre, attaque = "Horde" }
    ETATS[n + 4] = { genre = genre, camp = "Horde" }
end
Base(16, "base") Base(21, "base") Base(26, "base") Base(31, "base") Base(36, "base")
-- Alterac : les memes icones decalees d'un rang sur les clients classiques.
local d = NS.champ.Moderne() and 0 or -1
ETATS[2 + d] = { genre = "mine", camp = "Horde" }
ETATS[3 + d] = { genre = "mine", camp = "Alliance" }
ETATS[4 + d] = { genre = "cimetiere", attaque = "Alliance" }
ETATS[6 + d] = { genre = "tour", detruite = true }
ETATS[7 + d] = { genre = "cimetiere" }
ETATS[9 + d] = { genre = "tour", attaque = "Alliance" }
ETATS[10 + d] = { genre = "tour", camp = "Horde" }
ETATS[11 + d] = { genre = "tour", camp = "Alliance" }
ETATS[12 + d] = { genre = "tour", attaque = "Horde" }
ETATS[13 + d] = { genre = "cimetiere", camp = "Horde" }
ETATS[14 + d] = { genre = "cimetiere", attaque = "Horde" }
ETATS[15 + d] = { genre = "cimetiere", camp = "Alliance" }
B.ETATS = ETATS

-- Les noms et positions des lieux, gardes d'une partie a l'autre (par
-- carte) : les macros prennent ainsi les noms exacts du jeu.
local function Lieux()
    PvPCoreDB = type(PvPCoreDB) == "table" and PvPCoreDB or {}
    PvPCoreDB.lieux = type(PvPCoreDB.lieux) == "table" and PvPCoreDB.lieux or {}
    return PvPCoreDB.lieux
end
function B.LieuxConnus(carte)
    local l = Lieux()[carte]
    local r = {}
    for id, e in pairs(type(l) == "table" and l or {}) do
        if type(e) == "table" and type(e.nom) == "string" then table.insert(r, { id = id, nom = e.nom, genre = e.genre, x = e.x, y = e.y }) end
    end
    table.sort(r, function(a, b) return a.nom < b.nom end)
    return r
end

-- Les points de la carte en cours : { id, nom, x, y, icone, genre, camp, attaque, detruite }.
function B.Points(carte)
    carte = Nombre(carte or NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
    local pourCarte, info = Lire("C_AreaPoiInfo.GetAreaPOIForMap"), Lire("C_AreaPoiInfo.GetAreaPOIInfo")
    local r = {}
    if not (carte and pourCarte and info) then return r end
    local ids = NS.Appeler(pourCarte, carte)
    local garde = PAR_CARTE[carte] and Lieux() or nil
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local poi = NS.Appeler(info, carte, id)
        if type(poi) == "table" and type(poi.name) == "string" and not Secret(poi.name) and poi.name ~= "" then
            local icone = Nombre(poi.textureIndex)
            local x, y
            if type(poi.position) == "table" then
                local ok, a, b = pcall(function() if poi.position.GetXY then return poi.position:GetXY() end return poi.position.x, poi.position.y end)
                if ok then x, y = Nombre(a), Nombre(b) end
            end
            local e = icone and ETATS[icone] or {}
            local p = { id = id, nom = poi.name, x = x, y = y, icone = icone, genre = e.genre, camp = e.camp,
                attaque = e.attaque, detruite = e.detruite }
            table.insert(r, p)
            if garde and p.genre and p.genre ~= "mine" then
                garde[carte] = type(garde[carte]) == "table" and garde[carte] or {}
                garde[carte][id] = { nom = p.nom, genre = p.genre, x = x, y = y }
            end
        end
    end
    table.sort(r, function(a, b) return a.nom < b.nom end)
    return r
end

-- Le lieu connu le plus proche du joueur (bases, tours, cimetieres).
function B.LieuProche()
    local carte = Nombre(NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
    local position = Lire("C_Map.GetPlayerMapPosition")
    if not (carte and position) then return nil end
    local pos = NS.Appeler(position, carte, "player")
    local px, py
    if type(pos) == "table" then
        local ok, a, b = pcall(function() if pos.GetXY then return pos:GetXY() end return pos.x, pos.y end)
        if ok then px, py = Nombre(a), Nombre(b) end
    end
    if not (px and py) then return nil end
    local meilleur, dMin
    for _, p in ipairs(B.Points(carte)) do
        if p.x and p.y and p.genre and p.genre ~= "mine" then
            local dist = (p.x - px) ^ 2 + (p.y - py) ^ 2
            if not dMin or dist < dMin then meilleur, dMin = p, dist end
        end
    end
    return meilleur
end

-- ---------------------------------------------------------------------------
-- Alterac : capitaines et generaux (vie lue sur les unites visibles)
-- ---------------------------------------------------------------------------

-- Numeros des PNJ (ceux de Capping), camp et noms du jeu.
B.CHEFS = {
    { id = 11948, camp = "Alliance", fr = "Vanndar Foudrepique", en = "Vanndar Stormpike", general = true },
    { id = 11949, camp = "Alliance", fr = "Capitaine Balinda Gîtepierre", en = "Captain Balinda Stonehearth" },
    { id = 11946, camp = "Horde", fr = "Drek'Thar", en = "Drek'Thar", general = true },
    { id = 11947, camp = "Horde", fr = "Capitaine Galvangar", en = "Captain Galvangar" },
}
local PAR_ID = {}
for _, c in ipairs(B.CHEFS) do PAR_ID[c.id] = c end

local function NumeroPNJ(unite)
    local guid = NS.Appeler(UnitGUID, unite)
    if type(guid) ~= "string" or Secret(guid) then return nil end
    local genre, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
    if genre ~= "Creature" and genre ~= "Vehicle" then return nil end
    return tonumber(id)
end

local function Unites()
    local l = { "target", "focus", "mouseover" }
    for i = 1, 40 do l[#l + 1] = "nameplate" .. i end
    if NS.Appeler(_G.IsInRaid) then
        local n = Nombre(NS.Appeler(_G.GetNumGroupMembers)) or 0
        for i = 1, math.min(n, 40) do l[#l + 1] = "raid" .. i .. "target" end
    end
    return l
end

-- Un passage sur les unites visibles : la vie des chefs vus.
function B.ScruterChefs()
    local chefs = NS.champ.Etat().chefs
    local maintenant = Horloge()
    local vus = {}
    for _, u in ipairs(Unites()) do
        local id = NumeroPNJ(u)
        local c = id and PAR_ID[id]
        if c and not vus[id] then
            local mort = NS.Appeler(UnitIsDead, u)
            local v, m = Nombre(NS.Appeler(UnitHealth, u)), Nombre(NS.Appeler(UnitHealthMax, u))
            local e = chefs[id] or {}
            if not Secret(mort) and mort then
                e.mort, e.pct, e.quand = true, 0, maintenant
                vus[id] = true
            elseif v and m and m > 0 then
                e.mort, e.pct, e.quand = false, math.floor(v * 100 / m + 0.5), maintenant
                vus[id] = true
            end
            local nom = NS.Appeler(UnitName, u)
            if type(nom) == "string" and not Secret(nom) and nom ~= "" then e.nom = nom end
            chefs[id] = e
        end
    end
end

local function NomChef(c)
    local e = NS.champ.Etat().chefs[c.id]
    return (e and e.nom) or T(c.fr, c.en)
end
local function EtatChef(c)
    local e = NS.champ.Etat().chefs[c.id]
    if not e or not e.quand then return T("pas encore vu", "not seen yet"), { 0.6, 0.6, 0.6 } end
    if e.mort then return T("mort", "dead"), { 0.6, 0.6, 0.6 } end
    local age = Horloge() - e.quand
    local texte = e.pct .. " %"
    if age >= 5 then texte = texte .. T("  ·  il y a ", "  ·  ") .. Minutes(age) .. T("", " ago") end
    return texte, nil
end

-- ---------------------------------------------------------------------------
-- Lignes sous la carte et rubriques (fenetre, suivi de QuestCore)
-- ---------------------------------------------------------------------------

local function Couleur(camp) return NS.champ.CouleurCamp(camp) end
local function Camp(camp) return NS.champ.NomCamp(camp) end

-- Vrai pour un objectif du jeu deja dit, mieux, par nos lignes (compteurs
-- du Goulet, bases d'Arathi, renforts d'Alterac) : on ne le repete pas.
function B.DejaDit(texte, quel)
    quel = quel or B.Quel()
    if type(texte) ~= "string" or Secret(texte) then return false end
    if quel == "goulet" then
        local c = B.Compteurs()
        return (c.Alliance and c.Horde and texte:match("^%s*%d+%s*/%s*%d+%s*$")) and true or false
    elseif quel == "arathi" then
        return (B.LireArathi() and texte:match("%d[^%d]+%d+%s*/%s*%d+")) and true or false
    elseif quel == "alterac" then
        local c = B.Compteurs(RENFORTS)
        local bas = texte:lower()
        return (c.Alliance and c.Horde and (bas:find("renfort", 1, true) or bas:find("reinforc", 1, true))) and true or false
    end
    return false
end

-- Lignes courtes, sous la carte : ce que les objectifs du jeu ne disent pas.
function B.Lignes()
    local quel = B.Quel()
    local l = {}
    if quel == "goulet" then
        local c = B.Compteurs()
        if c.Alliance and c.Horde then
            local function Teinte(camp)
                local k = Couleur(camp)
                return string.format("|cff%02x%02x%02x", math.floor(k[1] * 255), math.floor(k[2] * 255), math.floor(k[3] * 255))
            end
            table.insert(l, { texte = T("Captures : ", "Captures : ") .. Teinte("Alliance") .. Camp("Alliance") .. " " .. c.Alliance.n .. "|r  ·  "
                .. Teinte("Horde") .. Camp("Horde") .. " " .. c.Horde.n .. "|r", couleur = { 1, 1, 1 } })
        end
        local reste = NS.champ.ResteRetourDrapeaux()
        if reste then table.insert(l, { texte = T("Drapeaux de retour dans ", "Flags back in ") .. Minutes(reste), couleur = { 1, 0.82, 0 } }) end
    elseif quel == "arathi" then
        local p = B.PrevisionArathi()
        if p and p.vainqueur then
            table.insert(l, { texte = T("Victoire ", "") .. Camp(p.vainqueur) .. T(" prévue dans ", " wins in ") .. Minutes(p.dans)
                .. "  ·  " .. p.maxi .. T(" à ", " to ") .. p.final, couleur = Couleur(p.vainqueur) })
        end
        if p and p.basesPourNous then
            table.insert(l, { texte = T("Bases à tenir pour gagner : ", "Bases to hold to win : ") .. p.basesPourNous, couleur = { 1, 0.82, 0 } })
        end
    elseif quel == "alterac" then
        for _, c in ipairs(B.CHEFS) do
            local e = NS.champ.Etat().chefs[c.id]
            if e and e.quand and not e.mort and e.pct < 100 and Horloge() - e.quand < 60 then
                table.insert(l, { texte = NomChef(c) .. "  " .. e.pct .. " %", couleur = Couleur(c.camp) })
            end
        end
    end
    return l
end

-- L'etat d'un point d'Alterac, en clair (texte, couleur).
local function EtatPoint(p)
    local reste, camp = NS.champ.ResteCapture(p.id)
    if p.detruite then return T("détruite", "destroyed"), { 0.6, 0.6, 0.6 } end
    if p.attaque then
        -- Une tour attaquee est detruite au bout du minuteur ; une base ou un
        -- cimetiere passe a l'attaquant.
        local texte
        if p.genre == "tour" then texte = T("détruite", "destroyed")
        else texte = p.attaque == "Horde" and T("à la Horde", "Horde") or T("à l'Alliance", "Alliance") end
        if reste then texte = texte .. T(" dans ", " in ") .. Minutes(reste) end
        return texte, Couleur(camp or p.attaque)
    end
    if p.camp then return Camp(p.camp), Couleur(p.camp) end
    return T("neutre", "neutral"), { 0.8, 0.8, 0.8 }
end

function B.Rubriques()
    local quel = B.Quel()
    local r = {}
    if quel == "goulet" then
        local x = { titre = T("Drapeaux", "Flags"), lignes = {} }
        local c = B.Compteurs()
        for _, camp in ipairs({ "Alliance", "Horde" }) do
            if c[camp] then
                table.insert(x.lignes, { texte = T("Captures ", "Captures ") .. Camp(camp), couleur = Couleur(camp),
                    droite = c[camp].n .. " / " .. (c[camp].m or 3) })
            end
        end
        local reste = NS.champ.ResteRetourDrapeaux()
        if reste then table.insert(x.lignes, { texte = T("Retour des drapeaux", "Flags back"), droite = Minutes(reste) }) end
        local adverse = NS.champ.PorteurAdverse()
        if adverse and NS.annonces and NS.annonces.CibleAJour then
            local ok = NS.annonces.CibleAJour()
            table.insert(x.lignes, { texte = T("Ciblage du porteur", "Carrier targeting"),
                droite = ok and T("prêt", "ready") or T("à jour hors combat", "updates out of combat"),
                couleur = ok and nil or { 0.6, 0.6, 0.6 } })
        end
        if #x.lignes > 0 then table.insert(r, x) end
    elseif quel == "arathi" then
        local a = B.LireArathi()
        if a then
            local x = { titre = T("Bases et ressources", "Bases and resources"), lignes = {} }
            for _, camp in ipairs({ "Alliance", "Horde" }) do
                local e = a[camp]
                table.insert(x.lignes, { texte = Camp(camp) .. "  ·  " .. e.bases .. " " .. (e.bases > 1 and T("bases", "bases") or T("base", "base")),
                    couleur = Couleur(camp), droite = e.n .. " / " .. (e.m or MAXI_ARATHI) .. "  ·  " .. Tic(e.bases) })
            end
            local p = B.PrevisionArathi(a)
            if p and p.vainqueur then
                table.insert(x.lignes, { texte = T("Vainqueur prévu", "Expected winner"), couleur = Couleur(p.vainqueur),
                    droite = Camp(p.vainqueur) .. T(" dans ", " in ") .. Minutes(p.dans) })
                table.insert(x.lignes, { texte = T("Score final prévu", "Expected final score"), droite = p.maxi .. T(" à ", " to ") .. p.final })
            end
            if p and p.basesPourNous then
                table.insert(x.lignes, { texte = T("Bases à tenir pour gagner", "Bases to hold to win"), droite = tostring(p.basesPourNous),
                    couleur = { 1, 0.82, 0 } })
            end
            table.insert(r, x)
        end
        local bases = { titre = T("Les bases", "The bases"), lignes = {} }
        for _, p in ipairs(B.Points(B.CARTES.arathi)) do
            if p.genre == "base" then
                local texte, couleur = EtatPoint(p)
                table.insert(bases.lignes, { texte = p.nom, couleur = couleur, droite = texte })
            end
        end
        if #bases.lignes > 0 then table.insert(r, bases) end
    elseif quel == "alterac" then
        local c = B.Compteurs(RENFORTS)
        if c.Alliance or c.Horde then
            local x = { titre = T("Renforts", "Reinforcements"), lignes = {} }
            for _, camp in ipairs({ "Alliance", "Horde" }) do
                if c[camp] then table.insert(x.lignes, { texte = Camp(camp), couleur = Couleur(camp), droite = tostring(c[camp].n) }) end
            end
            table.insert(r, x)
        end
        local tours = { titre = T("Tours et fortins", "Towers and bunkers"), lignes = {} }
        local cimetieres = { titre = T("Cimetières", "Graveyards"), lignes = {} }
        for _, p in ipairs(B.Points(B.CARTES.alterac)) do
            local cible = (p.genre == "tour" and tours) or (p.genre == "cimetiere" and cimetieres) or nil
            if cible then
                local texte, couleur = EtatPoint(p)
                table.insert(cible.lignes, { texte = p.nom, couleur = couleur, droite = texte })
            end
        end
        if #tours.lignes > 0 then table.insert(r, tours) end
        if #cimetieres.lignes > 0 then table.insert(r, cimetieres) end
        local chefs = { titre = T("Capitaines et généraux", "Captains and generals"), lignes = {} }
        for _, ch in ipairs(B.CHEFS) do
            local texte, couleur = EtatChef(ch)
            table.insert(chefs.lignes, { texte = NomChef(ch), couleur = couleur or Couleur(ch.camp), droite = texte })
        end
        table.insert(r, chefs)
    end
    return r
end

-- Le score de fin de partie, de notre point de vue : "3 a 1", ou nil.
function B.Score()
    local quel = B.Quel()
    if not quel then return nil end
    local c = (quel == "arathi" and B.LireArathi()) or (quel == "alterac" and B.Compteurs(RENFORTS)) or B.Compteurs()
    if not (c and c.Alliance and c.Horde) then return nil end
    local nous = NotreCamp()
    return c[nous].n .. T(" à ", " to ") .. c[Autre(nous)].n
end

-- La veille : en Alterac, une fois par seconde, la vie des chefs visibles.
local cadre = CreateFrame("Frame")
B.cadre = cadre
local attente = 0
cadre:SetScript("OnUpdate", function(_, ecoule)
    attente = attente - (ecoule or 0)
    if attente > 0 then return end
    attente = 1
    if B.Quel() ~= "alterac" then return end
    local ok, souci = pcall(B.ScruterChefs)
    if not ok then NS.base.NoterIncident("chefs", souci) end
end)
