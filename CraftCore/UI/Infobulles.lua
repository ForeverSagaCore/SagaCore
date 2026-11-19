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
