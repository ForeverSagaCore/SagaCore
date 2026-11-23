local _, NS = ...

-- Les parties jouees : a la fin de chaque champ de bataille (le jeu annonce
-- un vainqueur), le resultat et vos chiffres du tableau des scores sont
-- gardes (50 dernieres parties par personnage), avec un resume dans votre
-- fenetre de discussion (visible de vous seul). Le bilan par champ de
-- bataille en est tire : victoires, defaites, duree et honneur moyens.

NS.parties = {}
local P = NS.parties
local T = NS.T
local MAXI = 50

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Nombre(v) if Secret(v) then return nil end return tonumber(v) end

function P.Liste()
    local perso = NS.victoires.Perso()
    perso.parties = type(perso.parties) == "table" and perso.parties or {}
    return perso.parties
end

-- Notre ligne du tableau des scores (le nom peut porter le royaume).
local function MaLigne(lignes)
    local moi = NS.Appeler(UnitName, "player")
    if type(moi) ~= "string" then return nil end
    for _, l in ipairs(lignes or {}) do
        if l.nom == moi or (type(l.nom) == "string" and l.nom:match("^([^%-]+)") == moi) then return l end
    end
end

-- Appele a chaque mise a jour du tableau des scores, en champ de bataille.
function P.Verifier(lignes)
    local etat = NS.champ.Etat()
    if etat.enregistre then return end
    local gagnant = Nombre(NS.Appeler(NS.Lecture("GetBattlefieldWinner")))
    if not gagnant then return end
    etat.enregistre = true
    local camp = NS.Appeler(UnitFactionGroup, "player")
    local nous = camp == "Horde" and 0 or 1
    local l = MaLigne(lignes) or {}
    local ms = Nombre(NS.Appeler(NS.Lecture("GetBattlefieldInstanceRunTime"))) or 0
    local nom = NS.Appeler(_G.GetRealZoneText)
    local partie = {
        quand = NS.Appeler(_G.time) or 0,
        champ = (type(nom) == "string" and nom ~= "") and nom or "?",
        duree = math.floor(ms / 1000),
        issue = (gagnant == 255 or gagnant == 2) and "nul" or (gagnant == nous and "victoire" or "defaite"),
        vh = Nombre(l.vh) or 0, cm = Nombre(l.cm) or 0, morts = Nombre(l.morts) or 0, honneur = Nombre(l.honneur) or 0,
    }
    -- Le score final (captures, ressources ou renforts), de notre cote d'abord.
    local okS, score = pcall(function() return NS.bataille and NS.bataille.Score() end)
    if okS and type(score) == "string" then partie.score = score end
    local liste = P.Liste()
    table.insert(liste, partie)
    while #liste > MAXI do table.remove(liste, 1) end
    if NS.victoires.Reglages().resume then NS.Dire(P.Resume(partie)) end
    return partie
end

function P.Issue(p)
    if p.issue == "victoire" then return T("Victoire", "Victory"), { 0.31, 0.82, 0.41 } end
    if p.issue == "defaite" then return T("Défaite", "Defeat"), { 0.9, 0.3, 0.3 } end
    return T("Égalité", "Draw"), { 0.8, 0.8, 0.8 }
end
local function Chiffres(p)
    local H = NS.honneur
    return string.format("%s  ·  %d %s  ·  %d %s  ·  %s %s", H.Duree(p.duree), p.vh or 0, T("VH", "HK"), p.cm or 0, T("CG", "KB"),
        H.Lisible(p.honneur or 0), T("honneur", "honour"))
end
function P.Resume(p)
    local issue = P.Issue(p)
    local morts = p.morts or 0
    return issue .. " (" .. p.champ .. (p.score and (", " .. p.score) or "") .. ") : " .. Chiffres(p) .. "  ·  " .. morts .. " "
        .. (morts > 1 and T("morts", "deaths") or T("mort", "death"))
end

-- Bilan par champ de bataille, puis les dix dernieres parties.
function P.Rubriques()
    local r = {}
    local liste = P.Liste()
    if #liste == 0 then
        table.insert(r, { titre = T("Parties", "Matches"), lignes = { { texte = T("Aucune partie terminée pour l'instant", "No finished match yet"), couleur = { 0.6, 0.6, 0.6 } } } })
        return r
    end
    local parChamp, ordre = {}, {}
    for _, p in ipairs(liste) do
        local b = parChamp[p.champ]
        if not b then b = { v = 0, d = 0, n = 0, duree = 0, honneur = 0 } parChamp[p.champ] = b table.insert(ordre, p.champ) end
        b.n = b.n + 1
        if p.issue == "victoire" then b.v = b.v + 1 elseif p.issue == "defaite" then b.d = b.d + 1 end
        b.duree = b.duree + (p.duree or 0)
        b.honneur = b.honneur + (p.honneur or 0)
    end
    table.sort(ordre)
    local H = NS.honneur
    local bilan = { titre = T("Bilan", "Record"), lignes = {} }
    for _, champ in ipairs(ordre) do
        local b = parChamp[champ]
        table.insert(bilan.lignes, { texte = champ, droite = string.format("%d %s  ·  %d %s  ·  %d %%", b.v, T("V", "W"), b.d, T("D", "L"),
            math.floor(b.v * 100 / b.n + 0.5)) })
        table.insert(bilan.lignes, { texte = "   " .. T("En moyenne", "On average"), couleur = { 0.75, 0.75, 0.75 },
            droite = H.Duree(b.duree / b.n) .. "  ·  " .. H.Lisible(b.honneur / b.n) .. " " .. T("honneur", "honour") })
    end
    table.insert(r, bilan)
    local dernieres = { titre = T("Dernières parties", "Last matches"), lignes = {} }
    for i = #liste, math.max(1, #liste - 9), -1 do
        local p = liste[i]
        local issue, couleur = P.Issue(p)
        table.insert(dernieres.lignes, { texte = issue .. "  ·  " .. p.champ .. (p.score and ("  ·  " .. p.score) or ""), couleur = couleur, droite = Chiffres(p) })
    end
    table.insert(r, dernieres)
    local rec = P.Records(liste)
    if rec then table.insert(r, rec) end
    return r
end

-- Les records des parties gardees : series de victoires, meilleure partie.
function P.Records(liste)
    liste = liste or P.Liste()
    if #liste == 0 then return nil end
    local H = NS.honneur
    local serie, meilleure, enCours = 0, 0, 0
    for _, p in ipairs(liste) do
        if p.issue == "victoire" then serie = serie + 1 else serie = 0 end
        if serie > meilleure then meilleure = serie end
    end
    enCours = serie
    local function Plus(champ)
        local m
        for _, p in ipairs(liste) do if (p[champ] or 0) > 0 and (not m or p[champ] > m[champ]) then m = p end end
        return m
    end
    local plusCourte
    for _, p in ipairs(liste) do
        if p.issue == "victoire" and (p.duree or 0) > 0 and (not plusCourte or p.duree < plusCourte.duree) then plusCourte = p end
    end
    local function Fois(n) return n .. " " .. (n > 1 and T("victoires", "wins") or T("victoire", "win")) end
    local x = { titre = T("Records", "Records"), lignes = {} }
    table.insert(x.lignes, { texte = T("Série de victoires en cours", "Current winning streak"), droite = Fois(enCours) })
    table.insert(x.lignes, { texte = T("Meilleure série", "Best streak"), droite = Fois(meilleure) })
    local vh = Plus("vh")
    if vh then table.insert(x.lignes, { texte = T("Le plus de VH en une partie", "Most HK in a match"), droite = vh.vh .. "  ·  " .. vh.champ }) end
    local cm = Plus("cm")
    if cm then table.insert(x.lignes, { texte = T("Le plus de CG en une partie", "Most KB in a match"), droite = cm.cm .. "  ·  " .. cm.champ }) end
    local hon = Plus("honneur")
    if hon then table.insert(x.lignes, { texte = T("Le plus d'honneur en une partie", "Most honour in a match"), droite = H.Lisible(hon.honneur) .. "  ·  " .. hon.champ }) end
    if plusCourte then table.insert(x.lignes, { texte = T("Victoire la plus rapide", "Fastest win"), droite = H.Duree(plusCourte.duree) .. "  ·  " .. plusCourte.champ }) end
    return x
end
