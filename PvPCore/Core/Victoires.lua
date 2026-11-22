local _, NS = ...

-- Victoires honorables de la journee, cible par cible : chaque victoire lue
-- dans les messages d'honneur du jeu (ceux qui s'affichent dans la
-- discussion), l'honneur estime avec le rendement decroissant (meme cible le
-- meme jour : 100, 75, 50, 25 puis 0 %), l'honneur bonus (objectifs, fin de
-- partie), l'honneur par heure de la session et l'objectif de la semaine.
-- Rien n'est envoye : on lit seulement ce que le jeu affiche deja.
-- Les messages sont lus avec les textes du jeu lui-meme (COMBATLOG_*) : la
-- lecture marche dans toutes les langues du client.

NS.victoires = {}
local V = NS.victoires
local T = NS.T

-- Rendement decroissant : la n-ieme victoire sur la meme cible le meme jour.
local PALIERS = { 1, 0.75, 0.5, 0.25 }
function V.Rendement(n)
    return PALIERS[n] or 0
end

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Maintenant() return (NS.Appeler(_G.time)) or 0 end

-- Un texte du jeu ("%s meurt, ... %d") devenu motif de lecture. Les
-- positions explicites (%2$s) sont respectees : on rend les valeurs dans
-- l'ordre des arguments du texte, pas dans l'ordre de la phrase.
local motifs = {}
function V.Motif(format)
    if type(format) ~= "string" or format == "" then return nil end
    if motifs[format] then return motifs[format] end
    local ordre, rang = {}, 0
    local p = format:gsub("%%(%d?)%$?([sd])", function(pos, genre)
        rang = rang + 1
        table.insert(ordre, tonumber(pos) or rang)
        return "\001" .. genre
    end)
    p = p:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\001s", "(.-)"):gsub("\001d", "([%%d%%s%%.,]+)")
    local m = { motif = "^" .. p .. "$", ordre = ordre }
    motifs[format] = m
    return m
end
function V.Lire(format, texte)
    local m = V.Motif(format)
    if not m or type(texte) ~= "string" then return nil end
    local trouves = { texte:match(m.motif) }
    if #trouves == 0 then return nil end
    local r = {}
    for i, pos in ipairs(m.ordre) do r[pos] = trouves[i] end
    return r
end
local function Entier(v)
    if type(v) ~= "string" then return tonumber(v) end
    return tonumber((v:gsub("[%s%.,]", "")))
end

-- Les donnees de la journee, par personnage, remises a zero a la
-- reinitialisation quotidienne du jeu (celle du rendement decroissant).
local function FinDuJour()
    local ref = Maintenant()
    local reste = NS.Appeler(NS.Lecture("C_DateAndTime.GetSecondsUntilDailyReset"))
    if not tonumber(reste) then reste = NS.Appeler(_G.GetQuestResetTime) end
    reste = tonumber(reste)
    if reste and reste > 0 then return ref + reste end
    return nil
end
local function DateDuJour() return NS.Appeler(_G.date, "%Y%m%d") end

function V.Perso()
    PvPCoreDB = type(PvPCoreDB) == "table" and PvPCoreDB or {}
    PvPCoreDB.persos = type(PvPCoreDB.persos) == "table" and PvPCoreDB.persos or {}
    local cle = NS.ClePersonnage() or "?"
    local p = PvPCoreDB.persos[cle]
    if type(p) ~= "table" then p = {} PvPCoreDB.persos[cle] = p end
    return p
end
function V.Jour()
    local p = V.Perso()
    local j = p.jour
    local ref = Maintenant()
    local perime = type(j) ~= "table"
        or (j.fin and ref >= j.fin)
        or (not j.fin and j.date ~= DateDuJour())
    if perime then
        j = { cibles = {}, honneur = 0, bonus = 0, vh = 0, fin = FinDuJour(), date = DateDuJour() }
        p.jour = j
    end
    j.cibles = type(j.cibles) == "table" and j.cibles or {}
    return j
end

-- La session (depuis la connexion) : honneur et victoires, pour l'honneur
-- par heure. Jamais sauvegardee.
local session = { honneur = 0, vh = 0, debut = nil }
function V.Session() return session end

-- Une victoire honorable lue dans un message du jeu.
function V.Victoire(nom, estime)
    if type(nom) ~= "string" or nom == "" then return end
    local j = V.Jour()
    local n = (tonumber(j.cibles[nom]) or 0) + 1
    j.cibles[nom] = n
    local gagne = math.floor((tonumber(estime) or 0) * V.Rendement(n) + 0.5)
    j.honneur = (j.honneur or 0) + gagne
    j.vh = (j.vh or 0) + 1
    session.honneur = session.honneur + gagne
    session.vh = session.vh + 1
    session.debut = session.debut or (GetTime and GetTime()) or 0
    return gagne, n
end
function V.Bonus(points)
    points = tonumber(points)
    if not points or points <= 0 then return end
    local j = V.Jour()
    j.bonus = (j.bonus or 0) + points
    session.honneur = session.honneur + points
    session.debut = session.debut or (GetTime and GetTime()) or 0
end

-- Un message d'honneur du jeu : victoire (avec ou sans rang) ou honneur bonus.
function V.Message(texte)
    if type(texte) ~= "string" or Secret(texte) then return end
    local r = V.Lire(_G.COMBATLOG_HONORGAIN, texte)
    if r and r[1] then return V.Victoire(r[1], Entier(r[3])) end
    r = V.Lire(_G.COMBATLOG_HONORGAIN_NO_RANK, texte)
    if r and r[1] then return V.Victoire(r[1], Entier(r[2])) end
    r = V.Lire(_G.COMBATLOG_HONORAWARD, texte)
    if r and r[1] then return V.Bonus(Entier(r[1])) end
end

-- Combien de victoires aujourd'hui sur ce nom (avec ou sans royaume).
function V.VictoiresSur(nom, royaume)
    if type(nom) ~= "string" or Secret(nom) then return 0 end
    local c = V.Jour().cibles
    local n = tonumber(c[nom]) or 0
    if type(royaume) == "string" and royaume ~= "" and not Secret(royaume) then
        n = n + (tonumber(c[nom .. "-" .. royaume]) or 0)
    end
    return n
end

-- Honneur du jour : la valeur du jeu quand il la donne, sinon la notre.
function V.HonneurDuJour()
    local _, jeu = NS.Appeler(NS.Lecture("GetPVPSessionStats"))
    if not Secret(jeu) and tonumber(jeu) and tonumber(jeu) > 0 then return tonumber(jeu), true end
    local j = V.Jour()
    return (j.honneur or 0) + (j.bonus or 0), false
end
function V.HonneurParHeure()
    if not session.debut or session.honneur <= 0 then return nil end
    local duree = ((GetTime and GetTime()) or 0) - session.debut
    if duree < 300 then return nil end
    return math.floor(session.honneur * 3600 / duree + 0.5)
end

-- Les cibles du jour, les plus souvent vaincues d'abord.
function V.Cibles(maxi)
    local l = {}
    for nom, n in pairs(V.Jour().cibles) do table.insert(l, { nom = nom, n = tonumber(n) or 0 }) end
    table.sort(l, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.nom < b.nom end)
    while maxi and #l > maxi do table.remove(l) end
    return l
end

-- Reglages (pour tous les personnages) et objectif de la semaine (par personnage).
local DEFAUTS = { infobulle = true, resume = true }
function V.Reglages()
    PvPCoreDB = type(PvPCoreDB) == "table" and PvPCoreDB or {}
    PvPCoreDB.reglages = type(PvPCoreDB.reglages) == "table" and PvPCoreDB.reglages or {}
    local r = PvPCoreDB.reglages
    for k, v in pairs(DEFAUTS) do if r[k] == nil then r[k] = v end end
    return r
end
-- En milliers d'honneur (0 : pas d'objectif).
function V.Objectif() return tonumber(V.Perso().objectif) or 0 end
function V.PoserObjectif(milliers) V.Perso().objectif = math.max(0, math.floor(tonumber(milliers) or 0)) end

-- La semaine en cours : ce que le jeu a deja compte, plus la journee.
function V.Semaine()
    local hk, honneur = NS.Appeler(NS.Lecture("GetPVPThisWeekStats"))
    hk = (not Secret(hk) and tonumber(hk)) or 0
    honneur = (not Secret(honneur) and tonumber(honneur)) or 0
    local jour = V.HonneurDuJour()
    local hkJour = NS.Appeler(NS.Lecture("GetPVPSessionStats"))
    hkJour = (not Secret(hkJour) and tonumber(hkJour)) or V.Jour().vh or 0
    return honneur + jour, hk + hkJour
end

-- Une ligne dans l'infobulle des joueurs adverses : victoires du jour et
-- rendement de la prochaine.
function V.TexteInfobulle(n)
    return T("Victoires du jour : ", "Kills today : ") .. n .. T("  ·  prochaine à ", "  ·  next at ") .. math.floor(V.Rendement(n + 1) * 100) .. " %"
end
local function SurUnite(tooltip)
    if not V.Reglages().infobulle or not tooltip or not tooltip.GetUnit then return end
    local ok, _, unite = pcall(tooltip.GetUnit, tooltip)
    if not ok or type(unite) ~= "string" or Secret(unite) then return end
    if not NS.Appeler(UnitIsPlayer, unite) then return end
    local adverse = NS.Appeler(_G.UnitCanAttack, "player", unite)
    if Secret(adverse) or not adverse then return end
    local nom, royaume = NS.Appeler(UnitName, unite)
    local n = V.VictoiresSur(nom, royaume)
    if n <= 0 then return end
    local r = V.Rendement(n + 1)
    if r > 0 then tooltip:AddLine(V.TexteInfobulle(n), 1, 0.82, 0)
    else tooltip:AddLine(V.TexteInfobulle(n), 0.6, 0.6, 0.6) end
    if tooltip.Show then tooltip:Show() end
end
function V.InstallerInfobulle()
    if V.infobulleInstallee then return end
    V.infobulleInstallee = true
    local function SansRisque(tooltip)
        local ok, souci = pcall(SurUnite, tooltip)
        if not ok then NS.base.NoterIncident("infobulle", souci) end
    end
    local processeur = _G.TooltipDataProcessor
    local types = _G.Enum and _G.Enum.TooltipDataType
    if processeur and processeur.AddTooltipPostCall and types and types.Unit then
        if pcall(processeur.AddTooltipPostCall, types.Unit, SansRisque) then return end
    end
    if _G.GameTooltip and _G.GameTooltip.HookScript then
        pcall(_G.GameTooltip.HookScript, _G.GameTooltip, "OnTooltipSetUnit", SansRisque)
    end
end

-- Les evenements : messages d'honneur.
local cadre = CreateFrame("Frame")
V.cadre = cadre
cadre:RegisterEvent("PLAYER_LOGIN")
cadre:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
cadre:SetScript("OnEvent", function(_, ev, texte)
    if ev == "PLAYER_LOGIN" then
        pcall(V.InstallerInfobulle)
        pcall(V.Jour)
    elseif ev == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local ok, souci = pcall(V.Message, texte)
        if not ok then NS.base.NoterIncident("honneur", souci) end
    end
end)
