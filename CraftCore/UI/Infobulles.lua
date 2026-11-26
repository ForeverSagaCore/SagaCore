local _, NS = ...

-- Infobulles des objets, partout dans le jeu.
--
-- Au survol d'un objet, ou qu'il soit (sacs, banque, butin, hotel des ventes,
-- lien de discussion), CraftCore ajoute ce que le compte en possede et les
-- projets qui l'attendent. Chiffres du personnage connecte : c'est lui qui
-- regarde l'objet.
--
-- Branchement repris de ForeverDungeonJournal, installe sur ce client : le
-- crochet moderne des infobulles s'il existe, sinon l'ancien. Jamais les deux.

NS.infobulles = {}
local infobulles = NS.infobulles

local DUREE_CACHE = 10          -- secondes avant de refaire le calcul des projets
local PROJETS_MAX = 3           -- au-dela, "et N autres"

local cache, cacheLe
local dejaMis = setmetatable({}, { __mode = "k" })

local function Maintenant()
    local temps = NS.Lecture("GetTime")
    local ok, valeur = pcall(temps or os.time)
    return ok and valeur or 0
end

-- Les projets du personnage connecte qui utilisent chaque objet, quelque part
-- dans leur chaine, avec ce qu'il en manque encore.
local function Index()
    local maintenant = Maintenant()
    if cache and cacheLe and maintenant - cacheLe < DUREE_CACHE then return cache end
    local index = {}
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    local ok = pcall(NS.base.AvecPersonnage, cle, function()
        local listes = {}
        for _, projet in ipairs(NS.projets.Tous(false)) do
            table.insert(listes, { id = projet.id, nom = NS.projets.NomDe(projet) })
        end
        table.insert(listes, { id = "rapides", nom = NS.L.NAV_QUICK })
        for _, liste in ipairs(listes) do
            local arbres = NS.projets.Calculer(liste.id)
            local function Parcourir(noeud)
                for _, ligne in ipairs(noeud.composants or {}) do
                    local objet = tonumber(ligne.objet)
                    if objet then
                        index[objet] = index[objet] or {}
                        local deja = index[objet][liste.nom] or 0
                        index[objet][liste.nom] = deja + (ligne.manque or 0)
                    end
                    if ligne.sous and not ligne.sous.transformationIndisponible then
                        Parcourir(ligne.sous)
                    end
                end
            end
            for _, arbre in ipairs(arbres or {}) do Parcourir(arbre) end
        end
    end)
    if not ok then index = {} end
    cache, cacheLe = index, maintenant
    return index
end

-- A appeler quand les stocks ou les projets changent.
function infobulles.Invalider()
    cache, cacheLe = nil, nil
end

-- Recettes qui consomment chaque objet, tirees du catalogue releve. Refait
-- quand le catalogue grandit.
local parComposant, tailleCatalogue

local function RecettesQuiUtilisent(objet)
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return {} end
    local n = 0
    for _ in pairs(catalogue) do n = n + 1 end
    if not parComposant or n ~= tailleCatalogue then
        parComposant, tailleCatalogue = {}, n
        for cle, recette in pairs(catalogue) do
            if type(recette) == "table" then
                for _, comp in ipairs(recette.composants or {}) do
                    local o = tonumber(comp.objet)
                    if o then
                        parComposant[o] = parComposant[o] or {}
                        table.insert(parComposant[o], { id = cle, recette = recette })
                    end
                end
            end
        end
    end
    return parComposant[objet] or {}
end

-- Qui, parmi les personnages du meme camp, connait une recette.
local function QuiConnait(id)
    local noms = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if NS.inventaire.MemeCamp(fiche) and type(fiche.recettesApprises) == "table"
            and fiche.recettesApprises[tostring(id)] then
            table.insert(noms, NS.inventaire.NomCourt(fiche.cle))
        end
    end
    return noms
end

local RECETTES_MAX = 4

-- Les personnages du meme camp qui ont un metier, avec leur rang.
local function QuiALeMetier(ligneMetier)
    local noms = {}
    if not ligneMetier then return noms end
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(ligneMetier)]
        if NS.inventaire.MemeCamp(fiche) and type(sien) == "table" then
            local nom = NS.inventaire.NomCourt(fiche.cle)
            table.insert(noms, sien.rang and (nom .. " " .. sien.rang) or nom)
        end
    end
    return noms
end

-- Objet de la classe artisanat, d'apres le jeu.
local function EstDArtisanat(objet)
    local lecture = NS.jeu and NS.jeu.infoObjetImmediate
    if not lecture then return false end
    -- La classe est la sixieme valeur : appel direct, sous filet.
    local ok, _, _, _, _, _, classe = pcall(lecture, objet)
    return ok and tonumber(classe) == 7
end

local function AjouterRecettes(tooltip, objet)
    local L = NS.L
    local liste = {}
    for _, e in ipairs(RecettesQuiUtilisent(objet)) do
        local qui = QuiConnait(e.id)
        local metier = NS.recettes.MetierDe and NS.recettes.MetierDe(e.recette)
        table.insert(liste, { recette = e.recette, qui = qui, metier = metier,
            apprenants = (#qui == 0) and QuiALeMetier(metier) or {} })
    end
    if #liste == 0 then
        -- Composant d'artisanat qu'aucun metier releve n'utilise : on le dit,
        -- plutot que de laisser croire qu'il ne sert a rien.
        if EstDArtisanat(objet) then
            tooltip:AddLine(L.TIP_REAGENT_UNKNOWN, 0.6, 0.6, 0.6, true)
            return true
        end
        return false
    end
    table.sort(liste, function(a, b)
        local ra = (#a.qui > 0 and 0) or (#a.apprenants > 0 and 1) or 2
        local rb = (#b.qui > 0 and 0) or (#b.apprenants > 0 and 1) or 2
        if ra ~= rb then return ra < rb end
        return (a.recette.nom or "") < (b.recette.nom or "")
    end)
    tooltip:AddLine(L.TIP_USED_FOR, 1, 0.82, 0)
    for rang, e in ipairs(liste) do
        if rang > RECETTES_MAX then
            tooltip:AddLine(string.format(L.TIP_MORE_RECIPES, #liste - RECETTES_MAX), 0.6, 0.6, 0.6)
            break
        end
        local nomMetier = e.metier and NS.recettes.NomDuMetier(e.metier)
        local gauche = "  " .. (e.recette.nom or "?") .. (nomMetier and ("  |cff8c8c8c(" .. nomMetier .. ")|r") or "")
        if #e.qui > 0 then
            tooltip:AddDoubleLine(gauche, string.format(L.TIP_KNOWN_BY, table.concat(e.qui, ", ")),
                1, 1, 1, 0.31, 0.82, 0.41)
        elseif #e.apprenants > 0 then
            -- Plus tard : un de vos personnages a le metier, la recette reste a apprendre.
            tooltip:AddDoubleLine(gauche, string.format(L.TIP_TO_LEARN, table.concat(e.apprenants, ", ")),
                1, 1, 1, 1, 0.82, 0)
        else
            tooltip:AddDoubleLine(gauche, L.TIP_NOT_KNOWN, 1, 1, 1, 0.55, 0.55, 0.55)
        end
    end
    return true
end

local function IdentifiantDe(tooltip, donnees)
    if type(donnees) == "table" and type(donnees.id) == "number" then return donnees.id end
    if tooltip and tooltip.GetItem then
        local ok, _, lien = pcall(tooltip.GetItem, tooltip)
        if ok and type(lien) == "string" then
            local id = string.match(lien, "item:(%d+)")
            if id then return tonumber(id) end
        end
    end
    return nil
end

local function Ajouter(tooltip, donnees)
    if not NS.base.ReglagesGeneraux().infobulles then return end
    local objet = IdentifiantDe(tooltip, donnees)
    if not objet or not tooltip or not tooltip.AddLine then return end
    -- Un meme affichage peut prevenir deux fois : une seule fois nos lignes.
    if dejaMis[tooltip] == objet then return end

    local L = NS.L
    local fiche = NS.base.Personnage()
    if not fiche then return end
    local sacs, banque = NS.inventaire.SacsEtBanque(fiche, objet)
    local autres = NS.inventaire.DetailChezLesAutres(fiche, objet)
    local projets = Index()[objet]
    local sertA = #RecettesQuiUtilisent(objet) > 0 or EstDArtisanat(objet)
    if sacs + banque + autres == 0 and not projets and not sertA then return end

    dejaMis[tooltip] = objet
    tooltip:AddDoubleLine("CraftCore", string.format(L.TIP_LINE, sacs, banque, autres),
        1, 0.82, 0, 1, 1, 1)
    if projets then
        local noms = {}
        for nom, manque in pairs(projets) do table.insert(noms, { nom = nom, manque = manque }) end
        table.sort(noms, function(a, b)
            if a.manque ~= b.manque then return a.manque > b.manque end
            return a.nom < b.nom
        end)
        for rang, entree in ipairs(noms) do
            if rang > PROJETS_MAX then
                tooltip:AddLine(string.format(L.TIP_MORE, #noms - PROJETS_MAX), 0.6, 0.6, 0.6)
                break
            end
            if entree.manque > 0 then
                tooltip:AddLine(string.format(L.TIP_USEFUL_MISSING, entree.nom, entree.manque), 0.25, 0.85, 0.35)
            else
                tooltip:AddLine(string.format(L.TIP_USEFUL, entree.nom), 0.25, 0.85, 0.35)
            end
        end
    end
    -- A quoi il sert : chaque recette qui le consomme, et qui la connait.
    AjouterRecettes(tooltip, objet)
    if tooltip.Show then tooltip:Show() end
end

local function SansRisque(tooltip, donnees)
    local ok, souci = pcall(Ajouter, tooltip, donnees)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("infobulle d'objet", souci) end
end

local installe = false
function infobulles.Installer()
    if installe then return end
    installe = true

    local processeur = _G.TooltipDataProcessor
    local types = _G.Enum and _G.Enum.TooltipDataType
    local viaProcesseur = false
    if processeur and processeur.AddTooltipPostCall and types and types.Item then
        viaProcesseur = pcall(processeur.AddTooltipPostCall, types.Item, SansRisque)
    end

    for _, tooltip in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            if not viaProcesseur then
                pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self) SansRisque(self) end)
            end
            local function Oublier(self) dejaMis[self] = nil end
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Oublier)
            pcall(tooltip.HookScript, tooltip, "OnHide", Oublier)
        end
    end
end

-- Index des projets par objet, partage avec le suivi de recolte.
infobulles.Index = function() return Index() end

-- ---------------------------------------------------------------------------
-- Sacs (essai, mode prive) : une petite marque sur un objet qui sert a un de
-- vos objectifs (rang vise, projet, fabrication rapide). Au survol, l'objectif
-- est dans l'infobulle comme d'habitude.
-- ---------------------------------------------------------------------------
do
    local utiles = {}
    local function Prive()
        local S = NS.suite or _G.CoreSuite
        return S and S.Prive and S.Prive() or false
    end
    local function Recalculer()
        utiles = {}
        if not (NS.suivi and NS.suivi.Objectifs) then return end
        local ok, liste = pcall(NS.suivi.Objectifs)
        for _, o in ipairs(ok and liste or {}) do
            for _, m in ipairs(o.matieres or {}) do
                if m.objet and (m.requis or 0) > 0 then utiles[tonumber(m.objet)] = true end
            end
        end
    end
    local LireId = NS.Lecture("C_Container.GetContainerItemID") or NS.Lecture("GetContainerItemID")
    local function Marquer(bouton, sac, case)
        if not bouton then return end
        local id = LireId and sac and case and tonumber(NS.Appeler(LireId, sac, case))
        local oui = Prive() and id and utiles[id] or false
        if oui and not bouton.craftCoreMarque then
            -- Une pastille ronde comme celles de la minicarte, un peu en retrait
            -- du coin : fond sombre, roue dentee, anneau dore du jeu.
            local m = CreateFrame("Frame", nil, bouton)
            m:SetSize(14, 14)
            m:SetPoint("TOPLEFT", bouton, "TOPLEFT", 3, -3)
            m:SetFrameLevel(bouton:GetFrameLevel() + 5)
            m.fond = m:CreateTexture(nil, "BACKGROUND")
            m.fond:SetSize(12, 12)
            m.fond:SetPoint("CENTER")
            m.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
            m.fond:SetVertexColor(0, 0, 0, 0.85)
            m.image = m:CreateTexture(nil, "ARTWORK")
            m.image:SetSize(9, 9)
            m.image:SetPoint("CENTER")
            m.image:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
            if m.image.SetMask then pcall(m.image.SetMask, m.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
            m.anneau = m:CreateTexture(nil, "OVERLAY")
            m.anneau:SetSize(24, 24)
            m.anneau:SetPoint("TOPLEFT", m, "TOPLEFT", 0, 0)
            m.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            m:EnableMouse(false)
            bouton.craftCoreMarque = m
        end
        if bouton.craftCoreMarque then bouton.craftCoreMarque:SetShown(oui and true or false) end
    end
    local function ParcourirSacs()
        local function Cadre(f)
            if not (f and f.IsShown and f:IsShown()) then return end
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do
                    local sac = b.GetBagID and b:GetBagID()
                    pcall(Marquer, b, sac, b:GetID())
                end
            else
                local nom = f.GetName and f:GetName()
                for j = 1, 40 do
                    local b = nom and _G[nom .. "Item" .. j]
                    if not b then break end
                    pcall(Marquer, b, f:GetID(), b:GetID())
                end
            end
        end
        Cadre(_G.ContainerFrameCombinedBags)
        for i = 1, 13 do Cadre(_G["ContainerFrame" .. i]) end
    end
    local f = CreateFrame("Frame")
    local attente
    local function Bientot()
        if attente then return end
        attente = true
        local plusTard = NS.Lecture("C_Timer.After")
        local faire = function() attente = false Recalculer() ParcourirSacs() end
        if plusTard then NS.Appeler(plusTard, 0.5, faire) else faire() end
    end
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LOGIN", "BAG_OPEN", "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", Bientot)
    -- A l'ouverture d'un sac du jeu.
    local function Brancher(cadre)
        if cadre and cadre.HookScript and not cadre.craftCoreBranche then
            cadre.craftCoreBranche = true
            pcall(cadre.HookScript, cadre, "OnShow", Bientot)
        end
    end
    Brancher(_G.ContainerFrameCombinedBags)
    for i = 1, 13 do Brancher(_G["ContainerFrame" .. i]) end
end

-- ---------------------------------------------------------------------------
-- L'enveloppe de la minicarte : ce que CraftCore sait du courrier qui attend,
-- sans ouvrir la boite. Le jeu n'en dit que les expediteurs ; CraftCore
-- ajoute ce que vos personnages ont envoye et ce qui restait a la derniere
-- visite. Le reste ne se lit qu'a l'ouverture.
-- ---------------------------------------------------------------------------

do
    local function Ajouter(tt)
        if NS.base.ReglagesGeneraux().infobulles == false then return end
        local cle = NS.ClePersonnage()
        if not (cle and NS.inventaire.BoiteConnue) then return end
        local envoyes, restes, releve = NS.inventaire.BoiteConnue(cle)
        local L = NS.L
        tt:AddLine(" ")
        tt:AddLine("CraftCore", 1, 0.82, 0)
        local rien = true
        if #envoyes > 0 then
            rien = false
            tt:AddLine(L.MAIL_TIP_SENT, 1, 1, 1)
            table.sort(envoyes, function(a, b) return NS.inventaire.NomDObjet(a.objet) < NS.inventaire.NomDObjet(b.objet) end)
            for _, e in ipairs(envoyes) do
                local icone = NS.Appeler(NS.jeu.iconeObjet, e.objet)
                tt:AddDoubleLine("  " .. (icone and ("|T" .. icone .. ":12:12:0:0|t ") or "") .. NS.inventaire.NomDObjet(e.objet) .. " x" .. e.n,
                    e.de and NS.inventaire.NomCourt(e.de) or "", 1, 1, 1, 0.6, 0.6, 0.6)
            end
        end
        local liste = {}
        for id, n in pairs(restes) do table.insert(liste, { objet = id, n = n }) end
        if #liste > 0 then
            rien = false
            local depuis = ""
            local maintenant = NS.Appeler(_G.time) or 0
            if releve and releve > 0 then
                local h = math.floor((maintenant - releve) / 3600)
                depuis = h >= 24 and string.format(L.MAIL_TIP_DAYS, math.floor(h / 24)) or string.format(L.MAIL_TIP_HOURS, h)
            end
            tt:AddLine(string.format(L.MAIL_TIP_LEFT, depuis), 1, 1, 1)
            table.sort(liste, function(a, b) return NS.inventaire.NomDObjet(a.objet) < NS.inventaire.NomDObjet(b.objet) end)
            for _, e in ipairs(liste) do
                local icone = NS.Appeler(NS.jeu.iconeObjet, e.objet)
                tt:AddLine("  " .. (icone and ("|T" .. icone .. ":12:12:0:0|t ") or "") .. NS.inventaire.NomDObjet(e.objet) .. " x" .. e.n, 0.85, 0.85, 0.85)
            end
        end
        if rien then tt:AddLine(L.MAIL_TIP_NOTHING, 0.6, 0.6, 0.6, true) end
        tt:Show()
    end
    local branche = false
    local function Brancher()
        if branche then return end
        local cadre = _G.MiniMapMailFrame
            or (_G.MinimapCluster and _G.MinimapCluster.IndicatorFrame and _G.MinimapCluster.IndicatorFrame.MailFrame)
        if not (cadre and cadre.HookScript) then return end
        branche = true
        cadre:HookScript("OnEnter", function(self)
            if GameTooltip:IsOwned(self) then pcall(Ajouter, GameTooltip) end
        end)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() pcall(Brancher) end)
end
