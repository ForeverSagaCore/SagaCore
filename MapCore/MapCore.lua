local _, NS = ...

-- Demarrage de MapCore, commande /mc.

local L = NS.L
local evenements = CreateFrame("Frame")
evenements:RegisterEvent("PLAYER_LOGIN")
evenements:SetScript("OnEvent", function(_, evenement)
    if evenement == "PLAYER_LOGIN" then
        NS.base.Init()
        if NS.suite then
            pcall(NS.suite.Inscrire, "MapCore", {
                ouvrir = function() NS.fenetre.Ouvrir() end,
                fenetre = function() return NS.fenetre.Cadre() end,
            })
        end
        for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "HEARTHSTONE_BOUND", "PLAYER_LOGOUT",
            "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
            pcall(evenements.RegisterEvent, evenements, e)
        end
        NS.Dire(string.format(L.LOADED, NS.VERSION))
    elseif evenement == "PLAYER_LOGOUT" then
        pcall(NS.base.NoterPosition)
    else
        pcall(NS.base.NoterPosition)
        NS.fenetre.Rendre()
    end
end)

SLASH_MAPCORE1 = "/mc"
SLASH_MAPCORE2 = "/mapcore"
SlashCmdList.MAPCORE = function() NS.fenetre.Basculer() end
