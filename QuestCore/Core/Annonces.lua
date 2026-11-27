local _, NS = ...

-- Ce que QuestCore dit dans la discussion (voir Messages.lua).

local FR = (GetLocale and GetLocale() == "frFR")
local function T(fr, en)
    local S = _G.CoreSuite
    local langue = S and S.Langue and S.Langue()
    if langue then return langue == "frFR" and fr or en end
    return FR and fr or en
end

local function Definir()
    local M = NS.messages
    if not M then return end
    M.Definir("QuestCore", {
        { cle = "assez", libelle = T("Assez de quêtes pour monter", "Enough quests to level up"),
          texte = T("{quetes} quêtes à rendre : de quoi passer niveau {niveau}.", "{quetes} quests to turn in : enough for level {niveau}."),
          valeurs = { "quetes", "niveau" }, exemples = { quetes = 4, niveau = 18 }, actions = { string.format(T("Guider vers le niveau %d", "Guide to level %d"), 18), T("Plus tard", "Later") } },
        { cle = "proche", libelle = T("Niveau suivant en approche", "Next level close"),
          texte = T("Niveau {niveau} en approche : plus que {reste} % à faire.", "Level {niveau} is close : only {reste} % to go."),
          valeurs = { "niveau", "reste" }, exemples = { niveau = 18, reste = 8 }, delai = 3600 },
        { cle = "terminee", libelle = T("Quête terminée, à rendre", "Quest complete, to turn in"),
          texte = T("« {quete} » est terminée, à rendre.", "\"{quete}\" is complete, ready to turn in."),
          valeurs = { "quete" }, exemples = { quete = "Les loups affamés" }, actions = { T("Guider", "Guide") } },
        { cle = "rendreGroupe", libelle = T("Quêtes à rendre au même endroit", "Quests to turn in at the same place"),
          texte = T("{quetes} quêtes à rendre chez {qui}{sacs}.", "{quetes} quests to turn in to {qui}{sacs}."),
          valeurs = { "quetes", "qui", "sacs" }, exemples = { quetes = 3, qui = "Gryan Rudemanteau", sacs = "" },
          actions = { T("Aller les rendre", "Go turn them in"), T("Plus tard", "Later") } },
        { cle = "donjon", libelle = T("Donjon accessible", "Dungeon available"),
          texte = T("{donjon} est maintenant à ta portée.", "{donjon} is now within your reach."),
          valeurs = { "donjon" }, exemples = { donjon = "Les Mortemines" }, actions = { T("Voir le donjon", "See the dungeon") } },
        { cle = "sansQuestie", libelle = T("Questie absent", "Questie missing"),
          texte = T("Questie est absent : j'utilise ta base personnelle.", "Questie is missing : using your personal database."),
          delai = 3600 },
    })
end
Definir()

local function Dire(...)
    local M = NS.messages
    if M and M.Dire then return M.Dire("QuestCore", ...) end
end

local function Moi()
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    return cle and NS.base and NS.base.Perso(cle)
end

local function GuiderRendus()
    local api = _G.QuestCoreAPI
    if api and api.GuiderRendus then api.GuiderRendus() end
end

-- XP d'une quete du journal : le jeu d'abord, sinon la base.
local function XP(id)
    local f = _G.GetQuestLogRewardXP
    if type(f) == "function" then
        local ok, xp = pcall(f, id)
        if ok and tonumber(xp) and tonumber(xp) > 0 then return tonumber(xp) end
    end
    local niveau = UnitLevel and UnitLevel("player")
    return NS.ref and NS.ref.XPDeLaBase and tonumber((NS.ref.XPDeLaBase(id, niveau))) or 0
end

-- Places libres dans les sacs (sacs ordinaires seulement).
local function PlacesLibres()
    local f = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
    if not f then return nil end
    local n = 0
    for sac = 0, 4 do
        local ok, libres, famille = pcall(f, sac)
        if ok and tonumber(libres) and (famille == nil or famille == 0) then n = n + tonumber(libres) end
    end
    return n
end

-- Plusieurs quetes finies se rendent au meme endroit : on propose d'aller
-- les rendre (trois ou plus, ou deux avec les sacs presque pleins). Accepte,
-- le guidage y mene, puis reprend celui d'avant la ou il en etait. Une seule
-- fois par groupe de quetes.
local proposes = {}
local function ProposerRendus(p)
    local Lire = NS.ref and NS.ref.Lire
    if not Lire then return end
    local parReceveur = {}
    for id, q in pairs(p.quetes or {}) do
        if type(q) == "table" and q.complete == true then
            local fin = Lire("QuestDB", id, "finishedBy")
            local pnj = type(fin) == "table" and type(fin[1]) == "table" and fin[1][1]
            if pnj then
                parReceveur[pnj] = parReceveur[pnj] or {}
                table.insert(parReceveur[pnj], id)
            end
        end
    end
    local libres = PlacesLibres()
    local pleins = libres ~= nil and libres <= 2
    for pnj, ids in pairs(parReceveur) do
        if #ids >= 3 or (#ids >= 2 and pleins) then
            table.sort(ids)
            local signature = pnj .. ":" .. table.concat(ids, ",")
            if not proposes[signature] then
                proposes[signature] = true
                local qui = Lire("NpcDB", pnj, "name") or "?"
                local liste = ids
                Dire("rendreGroupe", { quetes = #ids, qui = qui, sacs = pleins and T(", sacs presque pleins", ", bags almost full") or "" },
                    { { T("Aller les rendre", "Go turn them in"), function()
                        local api = _G.QuestCoreAPI
                        if api and api.RendreEtReprendre then api.RendreEtReprendre(liste) end
                    end }, { T("Plus tard", "Later"), function() end, non = true } }, signature)
            end
        end
    end
end

local completes = nil
local function Examiner()
    local p = Moi()
    if not p or type(p.quetes) ~= "table" then return end
    local niveau = UnitLevel("player") or 0
    local total, n = 0, 0
    local maintenant = {}
    for id, q in pairs(p.quetes) do
        if type(q) == "table" and q.complete == true then
            maintenant[id] = true
            n = n + 1
            total = total + XP(id)
            if completes and not completes[id] then
                local idQ = id
                Dire("terminee", { quete = q.titre or (NS.ref and NS.ref.NomDeQuete(id, p)) or id },
                    { { T("Guider", "Guide"), function()
                        local api = _G.QuestCoreAPI
                        if api and api.GuiderQuetes then api.GuiderQuetes({ idQ }) end
                    end } }, id)
            end
        end
    end
    completes = maintenant
    pcall(ProposerRendus, p)
    local reste = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local maxi = _G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel() or 60
    if n > 0 and reste > 0 and total >= reste and niveau < maxi then
        local vise = niveau + 1
        Dire("assez", { quetes = n, niveau = vise },
            { { string.format(T("Guider vers le niveau %d", "Guide to level %d"), vise), function()
                local api = _G.QuestCoreAPI
                if api and api.GuiderNiveau then api.GuiderNiveau(vise) end
            end }, { T("Plus tard", "Later"), function() end, non = true } },
            niveau)
    end
end

local enAttente = false
local function ExaminerBientot()
    if enAttente then return end
    enAttente = true
    C_Timer.After(2, function() enAttente = false pcall(Examiner) end)
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
cadre:SetScript("OnEvent", function(_, ev, a1)
    if ev == "PLAYER_ENTERING_WORLD" then
        Definir()
        C_Timer.After(15, function()
            if not (type(_G.QuestDB) == "table" and _G.QuestDB.Get) and NS.ref and NS.ref.Disponible and NS.ref.Disponible() then
                Dire("sansQuestie")
            end
            pcall(Examiner)
        end)
    elseif ev == "QUEST_LOG_UPDATE" or ev == "BAG_UPDATE_DELAYED" then
        ExaminerBientot()
    elseif ev == "PLAYER_XP_UPDATE" then
        local xp, maxi = UnitXP("player") or 0, UnitXPMax("player") or 0
        local niveau = UnitLevel("player") or 0
        if maxi > 0 and xp / maxi >= 0.9 then
            Dire("proche", { niveau = niveau + 1, reste = math.max(1, math.floor((1 - xp / maxi) * 100 + 0.5)) }, nil, niveau)
        end
        ExaminerBientot()
    elseif ev == "PLAYER_LEVEL_UP" then
        local niveau = tonumber(a1)
        local p = Moi()
        if niveau and p and NS.donjons and NS.donjons.Liste then
            local ok, liste = pcall(NS.donjons.Liste, p)
            for _, d in ipairs(ok and liste or {}) do
                if not d.raid and tonumber(d.mini) == niveau then
                    Dire("donjon", { donjon = d.nom or d.nomBase or "?" },
                        { { T("Voir le donjon", "See the dungeon"), function() NS.fenetre.OuvrirPage("donjons") end } }, d.zone)
                end
            end
        end
    end
end)

-- Nom de la touche (Echap, Options, Raccourcis, Add-ons).
BINDING_HEADER_QUESTCORE = "QuestCore"
BINDING_NAME_QUESTCORE_PILOTER_SUIVI = (GetLocale and GetLocale() == "frFR") and "Naviguer dans le suivi" or "Navigate the tracker"
