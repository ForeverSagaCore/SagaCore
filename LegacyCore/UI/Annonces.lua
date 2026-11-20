local _, NS = ...

-- Ce que LegacyCore dit dans la discussion (voir Messages.lua).

local function T(fr, en)
    local S = _G.CoreSuite
    local langue = S and S.Langue and S.Langue() or (GetLocale and GetLocale())
    return langue == "frFR" and fr or en
end

local function Definir()
    local M = NS.messages
    if not M then return end
    M.Definir("LegacyCore", {
        { cle = "defi", libelle = T("Défi de classe accompli", "Class challenge done"),
          texte = T("Défi accompli : {classe} niveau {niveau} !", "Challenge done : {classe} level {niveau} !"),
          valeurs = { "classe", "niveau" }, exemples = { classe = "Paladin", niveau = 25 }, actions = { T("Voir", "See") }, delai = 60 },
        { cle = "heritage", libelle = T("Points d'héritage à dépenser", "Legacy points to spend"),
          texte = T("{points} point(s) d'héritage à dépenser.", "{points} legacy point(s) to spend."),
          valeurs = { "points" }, exemples = { points = 1 }, actions = { T("Ouvrir", "Open") }, delai = 3600 },
        { cle = "metier", libelle = T("Palier de métier atteint", "Profession milestone reached"),
          texte = T("{metier} atteint {palier} !", "{metier} reached {palier} !"),
          valeurs = { "metier", "palier" }, exemples = { metier = "Forge", palier = 150 }, delai = 60 },
        { cle = "classe", libelle = T("Nouvelle classe sur le compte", "New class on the account"),
          texte = T("Première fois que tu joues {classe} sur ce compte. Bonne aventure !", "First time playing {classe} on this account. Have fun !"),
          valeurs = { "classe" }, exemples = { classe = "Druide" }, delai = 86400 },
    })
end
Definir()

local function Dire(...)
    local M = NS.messages
    if M and M.Dire then return M.Dire("LegacyCore", ...) end
end

local PALIERS_CLASSE = { [25] = true, [45] = true, [60] = true }
local PALIERS_METIER = { 75, 150, 225, 300 }

local function NomDeClasse(jeton)
    local noms = _G.LOCALIZED_CLASS_NAMES_MALE
    return noms and noms[jeton] or jeton
end

local function AutresDeLaClasse(classe, niveauMin)
    local moi = NS.ClePersonnage()
    for _, p in ipairs(NS.base.Personnages()) do
        if p.cle ~= moi and p.classe == classe and (p.niveau or 0) >= niveauMin then return true end
    end
    return false
end

local rangs = nil
local function Metiers()
    local n = _G.GetNumSkillLines and _G.GetNumSkillLines() or 0
    local nouveaux = {}
    for i = 1, n do
        local nom, entete, _, rang = _G.GetSkillLineInfo(i)
        if nom and not entete and tonumber(rang) then nouveaux[nom] = tonumber(rang) end
    end
    if rangs then
        for nom, rang in pairs(nouveaux) do
            local avant = rangs[nom]
            if avant then
                for _, palier in ipairs(PALIERS_METIER) do
                    if avant < palier and rang >= palier then Dire("metier", { metier = nom, palier = palier }, nil, nom .. palier) end
                end
            end
        end
    end
    rangs = nouveaux
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
cadre:SetScript("OnEvent", function(_, ev, a1)
    if ev == "PLAYER_ENTERING_WORLD" then
        Definir()
        pcall(Metiers)
        C_Timer.After(20, function()
            local _, classe = UnitClass("player")
            if classe and not AutresDeLaClasse(classe, 1) then
                Dire("classe", { classe = NomDeClasse(classe) }, nil, NS.ClePersonnage())
            end
            -- Points d'heritage libres sur ce personnage.
            local d = LegacyCoreDB
            local releve = type(d) == "table" and d.persos and d.persos[NS.ClePersonnage() or ""]
            local libres = 0
            for _, a in ipairs(releve and releve.arbres or {}) do libres = math.max(libres, tonumber(a.disponibles) or 0) end
            if libres > 0 then
                Dire("heritage", { points = libres }, { { T("Ouvrir", "Open"), function() NS.fenetre.Ouvrir() end } }, libres)
            end
        end)
    elseif ev == "PLAYER_LEVEL_UP" then
        local niveau = tonumber(a1)
        local _, classe = UnitClass("player")
        if niveau and PALIERS_CLASSE[niveau] and classe and not AutresDeLaClasse(classe, niveau) then
            Dire("defi", { classe = NomDeClasse(classe), niveau = niveau },
                { { T("Voir", "See"), function() NS.fenetre.Ouvrir() end } }, classe .. niveau)
        end
    else
        C_Timer.After(1, function() pcall(Metiers) end)
    end
end)
