local _, NS = ...

-- Ce que MapCore dit dans la discussion (voir Messages.lua). L'arrivee et
-- l'arret du guidage sont annonces par la suite elle-meme (Suite.lua).

local function T(fr, en)
    local S = _G.CoreSuite
    local langue = S and S.Langue and S.Langue() or (GetLocale and GetLocale())
    return langue == "frFR" and fr or en
end

local function Definir()
    local M = NS.messages
    if not M then return end
    M.Definir("MapCore", {
        { cle = "arrivee", libelle = T("Arrivé à destination", "Arrived at destination"),
          texte = T("Tu es arrivé : {lieu}.", "You have arrived : {lieu}."),
          valeurs = { "lieu" }, exemples = { lieu = "Boîte aux lettres" }, delai = 5 },
        { cle = "reparation", libelle = T("Équipement abîmé", "Damaged equipment"),
          texte = T("Ton équipement est abîmé. Réparateur le plus proche : {nom}.", "Your gear is damaged. Nearest repair : {nom}."),
          valeurs = { "nom" }, exemples = { nom = "Rarc" }, actions = { T("Guider", "Guide") }, delai = 1800 },
        { cle = "voisin", libelle = T("Un autre de tes personnages est ici", "Another of your characters is here"),
          texte = T("{perso} est resté dans cette zone.", "{perso} was left in this zone."),
          valeurs = { "perso" }, exemples = { perso = "Elo" }, delai = 3600 },
        { cle = "arret", libelle = T("Guidage arrêté", "Guidance stopped"),
          texte = T("Guidage arrêté.", "Guidance stopped."), delai = 5, ou = "rien" },
        { cle = "atteint", libelle = T("Objectif atteint", "Goal reached"),
          texte = T("Objectif atteint : {quoi}.", "Goal reached : {quoi}."),
          valeurs = { "quoi" }, exemples = { quoi = "Vers le niveau 25" }, delai = 5 },
    })
end
Definir()

local function Dire(...)
    local M = NS.messages
    if M and M.Dire then return M.Dire("MapCore", ...) end
end

local function MaPosition()
    local carte = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not carte then return nil end
    local pos = C_Map.GetPlayerMapPosition(carte, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    return carte, x * 100, y * 100
end

local function Usure()
    local pire = 1
    for slot = 1, 18 do
        local actuel, maxi = GetInventoryItemDurability(slot)
        if actuel and maxi and maxi > 0 then pire = math.min(pire, actuel / maxi) end
    end
    return pire
end

local function Reparation()
    if Usure() >= 0.2 then return end
    local carte, x, y = MaPosition()
    local liste = carte and NS.SERVICES and NS.SERVICES[carte]
    if not liste then return end
    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
    local meilleur, d2
    for _, e in ipairs(liste) do
        if e[1] == "reparation" and (e[6] == "" or e[6] == "AH" or e[6] == faction) then
            local d = (e[2] - x) ^ 2 + (e[3] - y) ^ 2
            if not d2 or d < d2 then meilleur, d2 = e, d end
        end
    end
    if not meilleur then return end
    Dire("reparation", { nom = meilleur[4] }, { { T("Guider", "Guide"), function()
        if NS.pageCarte and NS.pageCarte.GuiderVers then
            NS.pageCarte.GuiderVers({ carte = carte, x = meilleur[2] / 100, y = meilleur[3] / 100, nom = meilleur[4],
                detail = meilleur[5], icone = "Interface\\Minimap\\Tracking\\Repair" })
        end
    end } }, carte)
end

local function Voisins()
    local carte = MaPosition()
    local d = MapCoreDB
    local moi = NS.ClePersonnage and NS.ClePersonnage()
    if not (carte and type(d) == "table" and type(d.persos) == "table") then return end
    for cle, p in pairs(d.persos) do
        if cle ~= moi and type(p) == "table" and p.carte == carte then
            Dire("voisin", { perso = (tostring(cle):match("^(.-) %- ")) or cle }, nil, cle .. ":" .. carte)
        end
    end
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
cadre:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_ENTERING_WORLD" then
        Definir()
        C_Timer.After(25, function() pcall(Reparation) end)
    elseif ev == "UPDATE_INVENTORY_DURABILITY" then
        pcall(Reparation)
    elseif ev == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(3, function() pcall(Voisins) pcall(Reparation) end)
    end
end)
