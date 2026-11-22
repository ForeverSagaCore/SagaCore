local _, NS = ...

-- PvPCore : demarrage, commande /pvpcore.
--   /pvpcore         la fenetre (honneur, reglages de la carte)
--   /pvpcore carte   la carte entierement visible (ou retour au reglage)
--   /pvpcore cacher  la carte cachee (ou retour au reglage)

local T = NS.T
local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_LOGIN")
cadre:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGIN" then
        if NS.fenetre then pcall(NS.fenetre.Construire) end
        if NS.carte then pcall(NS.carte.Demarrer) end
    end
end)

SLASH_PVPCORE1 = "/pvpcore"
SlashCmdList.PVPCORE = function(arg)
    arg = (arg or ""):lower()
    if arg:match("^carte") or arg:match("^map") then NS.carte.Forcer("opaque") return end
    if arg:match("^cach") or arg:match("^hide") then NS.carte.Forcer("cachee") return end
    if NS.fenetre and NS.fenetre.Ouvrir and NS.fenetre.Ouvrir() then return end
    NS.Dire(T("La fenêtre n'est pas encore prête.", "The window is not ready yet."))
end
