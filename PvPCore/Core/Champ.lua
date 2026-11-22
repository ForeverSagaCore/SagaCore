local _, NS = ...

-- Le champ de bataille en cours, en direct :
--   porteurs de drapeau (lus dans les annonces du champ de bataille), avec
--   leur classe (tableau des scores, groupe) et le temps depuis la prise ;
--   minuteurs de capture des bases, tours et cimetieres (le changement
--   d'icone des points d'interet de la carte, comme Capping) ;
--   compte a rebours du debut de la partie ;
--   fin estimee des ressources (vitesse mesuree sur les chiffres affiches).
-- Tout est lu, rien n'est envoye ni clique. Les annonces cachees par le jeu
-- (valeurs secretes) sont simplement ignorees.

NS.champ = {}
local C = NS.champ
local T = NS.T

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Nombre(v) if Secret(v) then return nil end return tonumber(v) end
local function Lire(nom) return NS.Lecture(nom) end
local function Horloge() return (GetTime and GetTime()) or 0 end
local function Minutes(s)
    s = math.max(0, math.floor((tonumber(s) or 0) + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
C.Minutes = Minutes

-- Icones "en conflit" des points d'interet (index de POIIcons) et le camp
-- qui attaque, comme Capping : cimetieres et tours d'Alterac, bases d'Arathi.
local CONFLIT = {
    [4] = "Alliance", [14] = "Horde", [9] = "Alliance", [12] = "Horde",
    [17] = "Alliance", [19] = "Horde", [22] = "Alliance", [24] = "Horde",
    [27] = "Alliance", [29] = "Horde", [32] = "Alliance", [34] = "Horde",
    [37] = "Alliance", [39] = "Horde",
}
C.CONFLIT = CONFLIT
-- Duree d'une capture, par carte : Vallee d'Alterac 4 minutes, Bassin
-- Arathi 1 minute ; une minute ailleurs.
local DUREES = { [1459] = 240, [1461] = 60 }
C.DUREES = DUREES

local etat
function C.Remettre()
    etat = { porteurs = {}, icones = {}, captures = {}, classes = {}, debutFin = nil, ressources = {}, enregistre = false }
end
C.Remettre()
function C.Etat() return etat end

function C.CouleurCamp(camp)
    local c = _G.PLAYER_FACTION_COLORS and _G.PLAYER_FACTION_COLORS[camp == "Horde" and 0 or 1]
    if c then return { c.r, c.g, c.b } end
    return camp == "Horde" and { 0.9, 0.2, 0.2 } or { 0.25, 0.55, 1 }
end
function C.NomCamp(camp) return camp == "Horde" and T("Horde", "Horde") or T("Alliance", "Alliance") end

-- Les annonces des drapeaux : prise, chute, capture. Le nom du joueur est un
-- seul mot (les noms n'ont pas d'espace). Anglais et francais.
local PRISE = { "picked up by ()", "ramassé par ()", "pris par ()" }
local CHUTE = { "dropped by ()", "lâché par ()", "tomber par ()" }
local CAPTURE = { "captured the", "a capturé", "a pris le drapeau", "s'est emparé" }
-- Cherche dans le texte en minuscules, lit le nom dans le texte d'origine
-- (memes positions : seules les lettres simples changent de casse).
local function Position(motifs, bas)
    for _, m in ipairs(motifs) do
        local pos = bas:match(m)
        if pos then return pos end
    end
end
local function Contient(motifs, bas)
    for _, m in ipairs(motifs) do if bas:find(m, 1, true) then return true end end
    return false
end
function C.Annonce(camp, texte)
    if type(texte) ~= "string" or Secret(texte) then return end
    local bas = texte:lower()
    local pos = Position(PRISE, bas)
    local nom = pos and texte:match("^([^%s!%.]+)", pos)
    if nom then
        etat.porteurs[camp] = { nom = nom, depuis = Horloge() }
        if _G.RequestBattlefieldScoreData then pcall(_G.RequestBattlefieldScoreData) end
        return "prise", nom
    end
    if Position(CHUTE, bas) then etat.porteurs[camp] = nil return "chute" end
    if Contient(CAPTURE, bas) then etat.porteurs = {} return "capture" end
end

-- Le compte a rebours du debut : l'evenement du jeu, sinon l'annonce
-- ("commence dans 1 minute", "begins in 30 seconds").
function C.Debut(reste)
    reste = tonumber(reste)
    if reste and reste > 0 then etat.debutFin = Horloge() + reste end
end
function C.AnnonceNeutre(texte)
    if type(texte) ~= "string" or Secret(texte) then return end
    local bas = texte:lower()
    local n, unite = bas:match("(%d+)%s*(%a+)")
    n = tonumber(n)
    if not n then return end
    -- Seulement un compte a rebours plausible (deux minutes au plus).
    if unite:find("^min") and n <= 2 then C.Debut(n * 60)
    elseif unite:find("^sec") and n <= 120 then C.Debut(n) end
end

-- La classe d'un joueur par son nom : le tableau des scores, le groupe, ou
-- une unite visible (cible, survol, focalisation, barres de nom).
function C.LireScores()
    local n = Nombre(NS.Appeler(Lire("GetNumBattlefieldScores"))) or 0
    local info = Lire("C_PvP.GetScoreInfo")
    local ancien = Lire("GetBattlefieldScore")
    local lignes = {}
    for i = 1, math.min(n, 80) do
        local l
        local s = info and NS.Appeler(info, i)
        if type(s) == "table" then
            l = { nom = s.name, cm = s.killingBlows, vh = s.honorableKills, morts = s.deaths, honneur = s.honorGained,
                  camp = s.faction, classe = s.classToken }
        elseif ancien then
            local nom, cm, vh, morts, honneur, camp, _, _, _, classe = NS.Appeler(ancien, i)
            l = { nom = nom, cm = cm, vh = vh, morts = morts, honneur = honneur, camp = camp, classe = classe }
        end
        if l and type(l.nom) == "string" and not Secret(l.nom) then
            if type(l.classe) == "string" and not Secret(l.classe) then
                etat.classes[l.nom] = l.classe
                local court = l.nom:match("^([^%-]+)%-")
                if court then etat.classes[court] = l.classe end
            end
            table.insert(lignes, l)
        end
    end
    return lignes
end
-- Vos chiffres de la partie en cours (tableau des scores), relus au plus
-- toutes les 20 secondes : le jeu met le tableau a jour de lui-meme.
local derniereDemande = -100
function C.MesChiffres()
    local maintenant = Horloge()
    if maintenant - derniereDemande >= 20 and _G.RequestBattlefieldScoreData then
        derniereDemande = maintenant
        pcall(_G.RequestBattlefieldScoreData)
    end
    local moi = NS.Appeler(UnitName, "player")
    if type(moi) ~= "string" then return nil end
    for _, l in ipairs(C.LireScores()) do
        if l.nom == moi or l.nom:match("^([^%-]+)") == moi then
            return { cm = Nombre(l.cm), vh = Nombre(l.vh), morts = Nombre(l.morts), honneur = Nombre(l.honneur) }
        end
    end
end

-- Le porteur de notre camp (il est dans notre groupe : sa position est connue).
function C.PorteurAllie()
    local camp = NS.Appeler(UnitFactionGroup, "player")
    local p = etat.porteurs[camp == "Horde" and "Horde" or "Alliance"]
    return p and p.nom, camp
end
-- Le minuteur de capture d'un point d'interet, en secondes restantes.
function C.ResteCapture(id)
    local c = etat.captures[id]
    if not c then return nil end
    local reste = c.fin - Horloge()
    if reste <= 0 then return nil end
    return reste, c.camp
end

local UNITES = { "target", "focus", "mouseover" }
local function UniteDe(nom)
    local raid = NS.Appeler(_G.IsInRaid)
    local n = NS.Appeler(_G.GetNumGroupMembers) or 0
    for i = 1, math.min(n, 40) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        local nu = NS.Appeler(UnitName, u)
        if not Secret(nu) and nu == nom then return u end
    end
    for _, u in ipairs(UNITES) do
        local nu = NS.Appeler(UnitName, u)
        if not Secret(nu) and nu == nom then return u end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        local existe = NS.Appeler(UnitExists, u)
        if not Secret(existe) and existe then
            local nu = NS.Appeler(UnitName, u)
            if not Secret(nu) and nu == nom then return u end
        end
    end
end
function C.ClasseDe(nom)
    if etat.classes[nom] then return etat.classes[nom] end
    local u = UniteDe(nom)
    if u then
        local _, classe = NS.Appeler(UnitClass, u)
        if type(classe) == "string" and not Secret(classe) then etat.classes[nom] = classe return classe end
    end
end
local function Vie(nom)
    local u = UniteDe(nom)
    if not u then return nil end
    local v, m = Nombre(NS.Appeler(UnitHealth, u)), Nombre(NS.Appeler(UnitHealthMax, u))
    if v and m and m > 0 then return math.floor(v * 100 / m + 0.5) end
end

-- Les points d'interet : un changement d'icone vers "en conflit" lance un
-- minuteur (la duree donnee par le jeu s'il la donne, sinon celle de la
-- carte) ; un autre changement l'arrete (prise ou defense).
function C.PointsDInteret(carte)
    local pourCarte, info = Lire("C_AreaPoiInfo.GetAreaPOIForMap"), Lire("C_AreaPoiInfo.GetAreaPOIInfo")
    carte = Nombre(carte)
    if not (pourCarte and info and carte) then return end
    local ids = NS.Appeler(pourCarte, carte)
    local restant = Lire("C_AreaPoiInfo.GetAreaPOISecondsLeft")
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local poi = NS.Appeler(info, carte, id)
        if type(poi) == "table" then
            local icone = Nombre(poi.textureIndex)
            local avant = etat.icones[id]
            etat.icones[id] = icone or false
            if icone and avant ~= nil and avant ~= icone then
                local camp = CONFLIT[icone]
                if camp then
                    local duree = Nombre(restant and NS.Appeler(restant, id))
                    if not duree or duree <= 0 then duree = DUREES[carte] or 60 end
                    local nom = (type(poi.name) == "string" and not Secret(poi.name)) and poi.name or "?"
                    etat.captures[id] = { nom = nom, camp = camp, fin = Horloge() + duree }
                else
                    etat.captures[id] = nil
                end
            end
        end
    end
end

-- Les chiffres "N/M" des objectifs : vitesse mesuree (sur une minute au
-- plus) et temps restant jusqu'au maximum.
function C.Annoter(textes)
    local maintenant = Horloge()
    local r = {}
    for i, texte in ipairs(textes) do
        local n, m = texte:match("(%d+)%s*/%s*(%d+)")
        n, m = tonumber(n), tonumber(m)
        local ligne = texte
        if n and m and m > n then
            local cle = i .. ":" .. (texte:gsub("%d", ""))
            local h = etat.ressources[cle]
            if not h or n < h.n then h = { t = maintenant, n = n } etat.ressources[cle] = h end
            local duree = maintenant - h.t
            if duree >= 20 and n > h.n then
                local vitesse = (n - h.n) / duree
                ligne = ligne .. "  ·  " .. m .. T(" dans ", " in ") .. Minutes((m - n) / vitesse)
            end
            -- Fenetre glissante : on ne garde pas un depart trop ancien.
            if duree > 60 then h.t, h.n = maintenant - 30, h.n + (n - h.n) * (duree - 30) / duree end
        end
        table.insert(r, ligne)
    end
    return r
end

-- Les lignes en direct (sous la carte, dans les rubriques), dans l'ordre :
-- debut, porteurs, captures. { texte, couleur }.
function C.Lignes(options)
    options = options or {}
    local l = {}
    local maintenant = Horloge()
    if options.minuteurs ~= false and etat.debutFin then
        local reste = etat.debutFin - maintenant
        if reste > 0 then table.insert(l, { texte = T("Début dans ", "Starts in ") .. Minutes(reste), couleur = { 1, 0.82, 0 } })
        else etat.debutFin = nil end
    end
    if options.porteurs ~= false then
        for _, camp in ipairs({ "Alliance", "Horde" }) do
            local p = etat.porteurs[camp]
            if p then
                local classe = C.ClasseDe(p.nom)
                local cc = classe and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classe]
                local couleur = cc and { cc.r, cc.g, cc.b } or C.CouleurCamp(camp)
                local vie = Vie(p.nom)
                table.insert(l, { texte = T("Porteur " .. C.NomCamp(camp) .. " : ", C.NomCamp(camp) .. " carrier : ") .. p.nom .. (vie and ("  " .. vie .. " %") or "") .. "  ·  " .. Minutes(maintenant - p.depuis),
                    couleur = couleur, nom = p.nom })
            end
        end
    end
    if options.minuteurs ~= false then
        local liste = {}
        for id, c in pairs(etat.captures) do
            if c.fin > maintenant then table.insert(liste, c) else etat.captures[id] = nil end
        end
        table.sort(liste, function(a, b) return a.fin < b.fin end)
        for _, c in ipairs(liste) do
            table.insert(l, { texte = c.nom .. "  ·  " .. C.NomCamp(c.camp) .. "  " .. Minutes(c.fin - maintenant), couleur = C.CouleurCamp(c.camp) })
        end
    end
    return l
end

-- Les evenements, legers : rien ne se fait hors des champs de bataille.
local cadre = CreateFrame("Frame")
C.cadre = cadre
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL", "START_TIMER", "AREA_POIS_UPDATED", "UPDATE_BATTLEFIELD_SCORE" }) do
    pcall(cadre.RegisterEvent, cadre, ev)
end
cadre:SetScript("OnEvent", function(_, ev, a, b)
    local ok, souci = pcall(function()
        if ev == "PLAYER_ENTERING_WORLD" then
            C.Remettre()
            if NS.honneur.EnChamp() and _G.RequestBattlefieldScoreData then pcall(_G.RequestBattlefieldScoreData) end
            return
        end
        if not NS.honneur.EnChamp() then return end
        if ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then C.Annonce("Alliance", a)
        elseif ev == "CHAT_MSG_BG_SYSTEM_HORDE" then C.Annonce("Horde", a)
        elseif ev == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then C.AnnonceNeutre(a)
        elseif ev == "START_TIMER" then C.Debut(b)
        elseif ev == "AREA_POIS_UPDATED" then
            C.PointsDInteret(NS.Appeler(Lire("C_Map.GetBestMapForUnit"), "player"))
        elseif ev == "UPDATE_BATTLEFIELD_SCORE" then
            local lignes = C.LireScores()
            if NS.parties then NS.parties.Verifier(lignes) end
        end
    end)
    if not ok then NS.base.NoterIncident("champ " .. tostring(ev), souci) end
end)
