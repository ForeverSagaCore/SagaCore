-- StuffCore : Mon equipement et les caisses, en add-on a part dans la
-- colonne de la suite. Pour l'instant servi par la fenetre et les releves de
-- CraftCore (objets, sacs, banque, recettes de vos personnages).

local NOM = ...

local Suite = _G.CoreSuite
if Suite and Suite.Annoncer then Suite.Annoncer("StuffCore") end

local function Inscrire()
    local S = _G.CoreSuite
    local api = _G.CraftCoreAPI
    if not (S and S.Inscrire and api and api.OuvrirStuff) then return false end
    S.Inscrire("StuffCore", {
        ouvrir = function() api.OuvrirStuff() end,
        fenetre = function() return api.FenetreStuff and api.FenetreStuff() end,
    })
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- Apres CraftCore (il s'inscrit au meme moment) : un tour plus tard.
    if not Inscrire() and C_Timer and C_Timer.After then
        C_Timer.After(0, Inscrire)
    end
end)

SLASH_STUFFCORE1 = "/stuffcore"
SLASH_STUFFCORE2 = "/stuff"
SlashCmdList.STUFFCORE = function()
    local S = _G.CoreSuite
    if S and S.Ouvrir and S.membres and S.membres.StuffCore then S.Ouvrir("StuffCore")
    elseif _G.CraftCoreAPI and _G.CraftCoreAPI.OuvrirStuff then _G.CraftCoreAPI.OuvrirStuff() end
end
