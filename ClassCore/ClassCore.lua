local _, NS = ...

-- ClassCore : demarrage, commande /classcore, rappel chez le marchand.

local T = NS.T

local cadre = CreateFrame("Frame")
cadre:RegisterEvent("PLAYER_LOGIN")
cadre:RegisterEvent("MERCHANT_SHOW")
cadre:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGIN" then
        if NS.fenetre then pcall(NS.fenetre.Construire) end
        return
    end
    if ev == "MERCHANT_SHOW" then pcall(NS.RappelMarchand) end
end)

-- Chez un marchand : les reactifs de la classe qu'il vend et qui manquent,
-- en une ligne dans la discussion (le joueur seul). Rien n'est achete.
function NS.RappelMarchand()
    if NS.base.ReglagesGeneraux().marchand == false then return end
    local E = NS.etat
    local utiles = {}
    for _, o in ipairs(E.ObjetsUtiles(E.Classe(), E.Niveau())) do
        if (o.seuil or 0) > 0 then utiles[o.id] = o end
    end
    if not next(utiles) or not GetMerchantNumItems or not GetMerchantItemID then return end
    local manques = {}
    for i = 1, (GetMerchantNumItems() or 0) do
        local ok, id = pcall(GetMerchantItemID, i)
        local o = ok and id and utiles[id]
        if o then
            local n = E.Compte(id)
            if n < o.seuil then
                local nom = E.Objet(id) or ("#" .. id)
                table.insert(manques, string.format(T("%s : %d sur toi (conseillé %d)", "%s : %d on you (advised %d)"), nom, n, o.seuil))
            end
        end
    end
    if #manques > 0 then NS.Dire(T("En vente ici : ", "Sold here : ") .. table.concat(manques, " ; ")) end
end

SLASH_CLASSCORE1 = "/classcore"
SlashCmdList.CLASSCORE = function()
    if NS.fenetre and NS.fenetre.Ouvrir and NS.fenetre.Ouvrir() then return end
    NS.Dire(T("La fenêtre n'est pas encore prête.", "The window is not ready yet."))
end

_G.ClassCoreAPI = {
    Ouvrir = function() return NS.fenetre and NS.fenetre.Ouvrir and NS.fenetre.Ouvrir() end,
}
