local _, NS = ...

-- AuraCore : demarrage et commande /auracore (reglages).

local T = NS.T
local cadre = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
cadre:SetScript("OnEvent", function(_, ev, unite)
    if ev == "PLAYER_LOGIN" and NS.fenetre then pcall(NS.fenetre.Construire) end
    if ev == "UNIT_AURA" and unite ~= "player" then return end
    pcall(NS.anneau.Dessiner)
end)

SLASH_AURACORE1 = "/auracore"
-- /auracore : les reglages ; /auracore off (ou on) : cacher ou montrer l'anneau ;
-- /auracore diag : ce que l'anneau a pu lire, en combat et hors combat.
SlashCmdList.AURACORE = function(arg)
    arg = (arg or ""):lower()
    if arg:match("diag") then
        local d = NS.anneau.Reglages().diag or {}
        for _, cle in ipairs({ "horsCombat", "combat" }) do
            local x = d[cle]
            local quand = cle == "combat" and T("en combat", "in combat") or T("hors combat", "out of combat")
            if x then
                NS.Dire(string.format("%s : api %d, %d / %d, %s%s", quand, x.api or 0, x.montres or 0, x.natifs or 0,
                    tostring(x.source), x.erreur and (", " .. tostring(x.erreur)) or ""))
            else
                NS.Dire(quand .. " : " .. T("pas encore relevé", "not read yet"))
            end
        end
        return
    end
    if arg:match("^off") then NS.anneau.Reglages().cache = true pcall(NS.anneau.Dessiner) return end
    if arg:match("^on") then NS.anneau.Reglages().cache = nil pcall(NS.anneau.Dessiner) return end
    if NS.fenetre and NS.fenetre.Ouvrir then NS.fenetre.Ouvrir() end
end
