local _, NS = ...

-- Ce que CraftCore dit dans la discussion (voir Messages.lua).

local function T(fr, en)
    local S = _G.CoreSuite
    local langue = S and S.Langue and S.Langue() or (GetLocale and GetLocale())
    return langue == "frFR" and fr or en
end

local function Definir()
    local M = NS.messages
    if not M then return end
    M.Definir("CraftCore", {
        { cle = "commande", libelle = T("Commande reçue", "Order received"),
          texte = T("{perso} t'a commandé {quantite} {objet}.", "{perso} ordered {quantite} {objet} from you."),
          valeurs = { "perso", "quantite", "objet" }, exemples = { perso = "Elo", quantite = 1, objet = "Épée lourde" },
          actions = { T("Ouvrir", "Open") }, delai = 86400 },
        { cle = "pret", libelle = T("Composants réunis pour un objectif", "Materials ready for a goal"),
          texte = T("Tout est dans tes sacs pour monter {metier} au rang {rang} : tu peux fabriquer.", "Everything is in your bags to raise {metier} to {rang} : you can craft."),
          valeurs = { "metier", "rang" }, exemples = { metier = "Forge", rang = 80 },
          actions = { T("Monter le métier", "Level the profession") }, delai = 3600 },
        { cle = "banque", libelle = T("Composants à sortir de la banque", "Materials to take from the bank"),
          texte = T("{nombre} composants en banque pour tes projets.", "{nombre} materials in the bank for your projects."),
          valeurs = { "nombre" }, exemples = { nombre = 12 }, actions = { T("Tout sortir", "Take all out") }, delai = 60 },
        { cle = "envoi", libelle = T("Envoi prêt à la boîte aux lettres", "Shipment ready at the mailbox"),
          texte = T("Un envoi attend {perso} : le panneau CraftCore le prépare.", "A shipment is waiting for {perso} : the CraftCore panel prepares it."),
          valeurs = { "perso" }, exemples = { perso = "Elo" }, delai = 300 },
        { cle = "rang", libelle = T("Rang visé atteint", "Target rank reached"),
          texte = T("{metier} rang {rang} : objectif atteint !", "{metier} rank {rang} : goal reached !"),
          valeurs = { "metier", "rang" }, exemples = { metier = "Forge", rang = 80 }, delai = 86400 },
        { cle = "recolte", libelle = T("Composants de récolte manquants", "Gathering materials missing"),
          texte = T("Il te manque des composants de récolte pour {metier}.", "You are missing gathered materials for {metier}."),
          valeurs = { "metier" }, exemples = { metier = "Forge" }, actions = { T("Guider la récolte", "Guide the gathering") }, delai = 7200 },
        { cle = "faite", libelle = T("Commande fabriquée", "Order crafted"),
          texte = T("{objet} fabriqué pour {perso}.", "{objet} crafted for {perso}."),
          valeurs = { "objet", "perso" }, exemples = { objet = "Épée lourde", perso = "Elo" }, delai = 5 },
    })
end
Definir()

local function Dire(...)
    local M = NS.messages
    if M and M.Dire then return M.Dire("CraftCore", ...) end
end

local function NomCourt(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

local function Ouvrir(page, metier)
    local ecran = NS.ecran
    if not ecran then return end
    if metier then ecran.progOuvert = metier end
    ecran.Montrer(page)
end

local function NomDuMetier(fiche, ligne)
    local m = fiche and type(fiche.metiers) == "table" and fiche.metiers[tostring(ligne)]
    return (m and m.nom) or tostring(ligne)
end

-- Commandes que ce personnage doit fabriquer, pas encore annoncees.
local function Commandes()
    local moi = NS.ClePersonnage and NS.ClePersonnage()
    if not (moi and NS.commandes) then return end
    for _, c in ipairs(NS.commandes.Liste()) do
        if c.etat == "demandee" and c.fabricant == moi and c.demandeur ~= moi and not c.annoncee then
            if Dire("commande", { perso = NomCourt(c.demandeur), quantite = c.quantite or 1, objet = NS.commandes.NomDeRecette(c.recette) },
                { { T("Ouvrir", "Open"), function() Ouvrir("commandes") end } }, c.id) then
                c.annoncee = true
            end
        end
    end
end

-- Les rangs vises : atteint, pret a fabriquer, ou recolte a faire.
local function Objectifs(avecRecolte)
    local fiche = NS.base and NS.base.Personnage and NS.base.Personnage()
    if not (fiche and NS.recettes and NS.recettes.MetiersVises) then return end
    for _, cle in ipairs(NS.recettes.MetiersVises(fiche)) do
        local ligne = tonumber(cle)
        local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
        if ligne and type(sien) == "table" and sien.rang then
            local nom = NomDuMetier(fiche, ligne)
            local plans = {}
            for _, seg in ipairs(NS.recettes.PlansVises(fiche, cle, sien.rang, sien.rangMax)) do plans[seg.vise] = seg.plan end
            for _, rangVise in ipairs(NS.recettes.RangsVises(fiche, cle)) do
            if sien.rang >= rangVise then
                Dire("rang", { metier = nom, rang = rangVise }, nil, ligne .. ":" .. rangVise)
            else
                local plan = plans[rangVise]
                local ok = plan ~= nil
                if ok and plan then
                    if next(plan.manques or {}) then
                        if avecRecolte then
                            Dire("recolte", { metier = nom },
                                { { T("Guider la récolte", "Guide the gathering"), function() if NS.guidage and NS.guidage.Lancer then NS.guidage.Lancer({ metier = ligne }) end end } }, ligne)
                        end
                    elseif plan.atteint >= rangVise then
                        local tout = true
                        for objet, n in pairs(plan.utilises or {}) do
                            if NS.inventaire.DisponibleDansLesSacs(objet) < n then tout = false break end
                        end
                        for objet, n in pairs(plan.achats or {}) do
                            if NS.inventaire.DisponibleDansLesSacs(objet) < n then tout = false break end
                        end
                        if tout then
                            Dire("pret", { metier = nom, rang = rangVise },
                                { { T("Monter le métier", "Level the profession"), function() Ouvrir("progression", ligne) end } }, ligne .. ":" .. rangVise)
                        end
                    end
                end
            end
            end
        end
    end
end

-- Une commande fabriquee : le message de la suite en plus de l'ancien.
if NS.commandes and NS.commandes.ProjetVide and not NS.commandes.annonceBranchee then
    NS.commandes.annonceBranchee = true
    local original = NS.commandes.ProjetVide
    NS.commandes.ProjetVide = function(projet)
        local c = projet and projet.commande and NS.commandes.Par(projet.commande)
        local avant = c and c.etat
        original(projet)
        if c and avant == "demandee" and c.etat ~= "demandee" then
            Dire("faite", { objet = NS.commandes.NomDeRecette(c.recette), perso = NomCourt(c.demandeur) }, nil, c.id)
        end
    end
end

local enAttente = false
local function ObjectifsBientot()
    if enAttente then return end
    enAttente = true
    C_Timer.After(3, function() enAttente = false pcall(Objectifs, false) end)
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "BANKFRAME_OPENED", "MAIL_SHOW" }) do
    pcall(cadre.RegisterEvent, cadre, e)
end
cadre:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_ENTERING_WORLD" then
        Definir()
        C_Timer.After(20, function() pcall(Commandes) pcall(Objectifs, true) end)
    elseif ev == "BAG_UPDATE_DELAYED" or ev == "SKILL_LINES_CHANGED" then
        ObjectifsBientot()
    elseif ev == "BANKFRAME_OPENED" then
        C_Timer.After(1.5, function()
            local ok, plan = pcall(NS.courrier and NS.courrier.Plan)
            local n = 0
            for _, l in ipairs(ok and plan and plan.sortir or {}) do n = n + (l.quantite or 0) end
            if n > 0 then
                Dire("banque", { nombre = n }, { { T("Tout sortir", "Take all out"), function() NS.courrier.ToutSortir() end } })
            end
        end)
    elseif ev == "MAIL_SHOW" then
        C_Timer.After(1, function()
            local moi = NS.ClePersonnage and NS.ClePersonnage()
            local ok, a = pcall(NS.commandes.AEnvoyer, moi)
            for demandeur in pairs(ok and a or {}) do
                Dire("envoi", { perso = NomCourt(demandeur) }, nil, demandeur)
            end
        end)
    end
end)

-- Nom de la touche (Echap, Options, Raccourcis, Add-ons).
BINDING_HEADER_CRAFTCORE = "CraftCore"
BINDING_NAME_CRAFTCORE_PILOTER_SUIVI = (GetLocale and GetLocale() == "frFR") and "Naviguer dans la fenêtre CraftCore (suivi, banque, courrier, hôtel des ventes)" or "Navigate the CraftCore window (tracker, bank, mail, auction house)"

-- Reglages de CraftCore dans Options, Add-ons, Forever SagaCore.
do
    local function T(fr, en)
        local S = _G.CoreSuite
        local langue = (S and S.Langue and S.Langue()) or (GetLocale and GetLocale())
        return langue == "frFR" and fr or en
    end
    local function G() return NS.base.ReglagesGeneraux() end
    _G.SagaCoreOptions = type(_G.SagaCoreOptions) == "table" and _G.SagaCoreOptions or {}
    _G.SagaCoreOptions.CraftCore = { titre = "CraftCore", ordre = 1, elements = function()
        return {
            { "section", function() return T("Affichage et aides", "Display and help") end },
            { "case", function() return T("Recettes non apprises", "Unlearned recipes") end,
              function() return NS.base.Reglages().afficherNonApprises end,
              function(v) NS.base.Reglages().afficherNonApprises = v end },
            { "case", function() return T("Didacticiel guidé", "Guided tutorial") end,
              function() return NS.aide and NS.aide.GuideActif() end,
              function(v) if NS.aide then NS.aide.PoserGuide(v) end end },
            { "case", function() return T("Infobulles sur les objets", "Item tooltips") end,
              function() return G().infobulles end, function(v) G().infobulles = v end },
            { "case", function() return T("Assistant banque et courrier", "Bank and mail assistant") end,
              function() return G().assistant end,
              function(v) G().assistant = v if NS.courrier then pcall(NS.courrier.Actualiser) end end },
            { "section", function() return T("Suivi des fabrications", "Crafting tracker") end },
            { "case", function() return T("Afficher le suivi", "Show the tracker") end,
              function() return G().suiviRecolte ~= false end, function(v) G().suiviRecolte = v end },
            { "case", function() return T("Toujours visible", "Always visible") end,
              function() return G().suiviPermanent end,
              function(v) G().suiviPermanent = v if v and NS.suivi then pcall(NS.suivi.Montrer) end end },
            { "case", function() return T("Ancré", "Locked") end,
              function() return NS.suite and NS.suite.Ancree and NS.suite.Ancree("CraftCoreSuivi") end,
              function(v) if NS.suite and NS.suite.PoserAncre then NS.suite.PoserAncre("CraftCoreSuivi", v) end end },
        }
    end }
end
