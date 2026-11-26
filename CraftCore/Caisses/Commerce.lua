local _, NS = ...

-- Le commerce des caisses : la reputation du camp (Administration commerciale
-- d'Azeroth pour l'Alliance, Transports logistiques Durotar pour la Horde),
-- la faveur marchande, les ecrits d'artisan, les patrons et les recompenses
-- du camp. Les donnees fixes sont dans CommerceDonnees.lua ; tout ce que le
-- jeu sait dire (noms, rang requis, palier, prix, reputation, faveur) est lu
-- dans le jeu et garde, jamais suppose. Ce qui vient des guides web est
-- marque comme estime (« ~ ») tant que le jeu ne l'a pas donne.

NS.commerce = {}
local C = NS.commerce
local D = NS.commerceDonnees
local function L() return NS.L end

-- Prix publies par les guides, par metier : selon le palier requis (4 sans
-- reputation, 5 Amical, 6 Honore) et, a Honore, les recettes de rang 290 et
-- plus (« haut »).
local PRIX_WEB = {
    [171] = { [4] = 45, [5] = 120, [6] = 180, haut = 240 },
    [164] = { [4] = 30, [5] = 60, [6] = 90, haut = 120 },
    [333] = { [4] = 45, [5] = 120, [6] = 180, haut = 240 },
    [202] = { [4] = 45, [5] = 180, [6] = 270, haut = 360 },
    [165] = { [4] = 30, [5] = 60, [6] = 90 },
    [197] = { [4] = 30, [5] = 60, [6] = 90 },
    [185] = { [4] = 30, [5] = 60, [6] = 90 },
}

local function Base()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.commerce = type(d.commerce) == "table" and d.commerce or {}
    local b = d.commerce
    -- Ce que l'infobulle dit d'un patron, par langue du client.
    local langue = NS.Appeler(GetLocale) or "?"
    -- Version 2 : le niveau requis du personnage est lu aussi.
    -- Version 3 : un patron sans rang requis lu n'est plus garde tel quel.
    if b.langue ~= langue or b.version ~= 3 then b.langue = langue b.version = 3 b.patrons = {} end
    b.patrons = type(b.patrons) == "table" and b.patrons or {}
    b.prix = type(b.prix) == "table" and b.prix or {}
    return b
end

local function FicheDe(fiche)
    if type(fiche) ~= "table" then return nil end
    fiche.commerce = type(fiche.commerce) == "table" and fiche.commerce or {}
    return fiche.commerce
end

function C.Camp(fiche)
    if type(fiche) == "table" and fiche.cle ~= NS.ClePersonnage() then
        return (fiche.faction == "Alliance" or fiche.faction == "Horde") and fiche.faction or nil
    end
    local f = NS.Appeler(UnitFactionGroup, "player")
    return (f == "Alliance" or f == "Horde") and f or nil
end
function C.Faction(fiche)
    local camp = C.Camp(fiche)
    return camp and D.FACTIONS[camp], camp
end

-- ---------------------------------------------------------------------------
-- Reputation et faveur : lues pour le personnage connecte, gardees dans sa
-- fiche pour les autres.
-- ---------------------------------------------------------------------------

local function LireReputation(id)
    local moderne = NS.Lecture("C_Reputation.GetFactionDataByID")
    if moderne then
        local d = NS.Appeler(moderne, id)
        if type(d) == "table" and d.name then
            return { nom = d.name, rang = d.reaction, mini = d.currentReactionThreshold,
                maxi = d.nextReactionThreshold, valeur = d.currentStanding }
        end
    end
    local lire = NS.Lecture("GetFactionInfoByID")
    if not lire then return nil end
    local ok, nom, _, rang, mini, maxi, valeur = pcall(lire, id)
    if ok and type(nom) == "string" and nom ~= "" then
        return { nom = nom, rang = rang, mini = mini, maxi = maxi, valeur = valeur }
    end
    return nil
end

local function LireFaveur()
    local lire = NS.Lecture("C_CurrencyInfo.GetCurrencyInfo")
    local info = lire and NS.Appeler(lire, D.MONNAIE)
    if type(info) == "table" then
        return { quantite = tonumber(info.quantity) or 0, nom = info.name, icone = info.iconFileID }
    end
    return nil
end

function C.Relever()
    local fiche = NS.base.Personnage and NS.base.Personnage()
    local f = C.Faction(fiche)
    if not (fiche and f) then return end
    local c = FicheDe(fiche)
    local rep = LireReputation(f.id)
    if rep then rep.vuLe = NS.Appeler(time) c.rep = rep end
    local fav = LireFaveur()
    if fav then fav.vuLe = NS.Appeler(time) c.faveur = fav end
    -- Les quetes uniques du camp.
    local faite = NS.Lecture("C_QuestLog.IsQuestFlaggedCompleted", "IsQuestFlaggedCompleted")
    local _, camp = C.Faction(fiche)
    local q = D.ETIQUETTE[camp]
    if faite and q then c.etiquette = NS.Appeler(faite, q) == true end
end

function C.Reputation(fiche) local c = FicheDe(fiche) return c and c.rep end
function C.Faveur(fiche) local c = FicheDe(fiche) return c and c.faveur and c.faveur.quantite, c and c.faveur end
function C.EtiquetteFaite(fiche) local c = FicheDe(fiche) return c and c.etiquette end

function C.NomDuPalier(rang)
    return _G["FACTION_STANDING_LABEL" .. tostring(rang or 4)] or tostring(rang)
end

-- ---------------------------------------------------------------------------
-- Les patrons : ce que l'infobulle du jeu dit (nom, rang requis, palier).
-- ---------------------------------------------------------------------------

local function Motif(format)
    if type(format) ~= "string" then return nil end
    local m = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    m = m:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. m .. "$"
end

local scanneur
local function LignesDe(objet)
    local lignes = {}
    local info = NS.Lecture("C_TooltipInfo.GetItemByID")
    if info then
        local d = NS.Appeler(info, objet)
        if type(d) == "table" and type(d.lines) == "table" then
            for _, l in ipairs(d.lines) do if l.leftText then table.insert(lignes, l.leftText) end end
            if #lignes > 0 then return lignes end
        end
    end
    if not scanneur then
        scanneur = CreateFrame("GameTooltip", "CraftCoreScanCommerce", UIParent, "GameTooltipTemplate")
        scanneur:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanneur:ClearLines()
    scanneur:SetOwner(UIParent, "ANCHOR_NONE")
    if not pcall(scanneur.SetItemByID, scanneur, objet) then return lignes end
    for i = 1, scanneur:NumLines() or 0 do
        local t = _G["CraftCoreScanCommerceTextLeft" .. i]
        local texte = t and t:GetText()
        if texte then table.insert(lignes, texte) end
    end
    return lignes
end

local function PalierDuLibelle(libelle)
    for rang = 1, 8 do
        if _G["FACTION_STANDING_LABEL" .. rang] == libelle then return rang end
    end
    return nil
end

local demandes, essais = {}, {}
local function Demander(objet)
    if demandes[objet] then return end
    demandes[objet] = true
    local charger = NS.Lecture("C_Item.RequestLoadItemDataByID")
    if charger then NS.Appeler(charger, objet) end
end
C.Demander = Demander

local function Lire(objet)
    local b = Base()
    if not b then return nil end
    local deja = b.patrons[objet]
    if deja then return deja end
    local nom = NS.Appeler(NS.jeu.infoObjet, objet)
    if type(nom) ~= "string" or nom == "" then Demander(objet) return nil end
    local lignes = LignesDe(objet)
    -- Une infobulle incomplete (objet pas encore charge) n'est pas gardee.
    if #lignes < 2 then Demander(objet) return nil end
    local p = { nom = nom }
    local mCompetence, mReputation, mNiveau = Motif(_G.ITEM_REQ_SKILL), Motif(_G.ITEM_REQ_REPUTATION), Motif(_G.ITEM_MIN_LEVEL)
    for _, texte in ipairs(lignes) do
        if mNiveau and not p.niveau then
            local n = texte:match(mNiveau)
            if n then p.niveau = tonumber(n) end
        end
        if mCompetence and not p.rang then
            local _, rang = texte:match(mCompetence)
            if rang then p.rang = tonumber(rang) end
        end
        local faction, palier = nil, nil
        if mReputation then faction, palier = texte:match(mReputation) end
        if palier and not p.palier then p.palier = PalierDuLibelle(palier) or 4 end
    end
    p.palier = p.palier or 4
    -- Le rang requis manque : l'infobulle n'etait pas complete (objet
    -- fabrique pas encore charge). On relira, trois fois au plus.
    if not p.rang then
        essais[objet] = (essais[objet] or 0) + 1
        Demander(objet)
        if essais[objet] < 3 then return p end
    end
    b.patrons[objet] = p
    return p
end
C.LirePatron = Lire

-- Le sort que le patron apprend : la recette du catalogue au meme nom (le
-- patron s'appelle « Recette : <nom> », « Formule : <nom> », ...).
local index, tailleIndex
local function Recette(objet, metier)
    local p = Lire(objet)
    if not p then return nil end
    if p.recette then return p.recette end
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return nil end
    local n = 0
    for _ in pairs(catalogue) do n = n + 1 end
    if not index or tailleIndex ~= n then
        index, tailleIndex = {}, n
        local Plier = NS.caisses.Plier
        for id, r in pairs(catalogue) do
            if type(r) == "table" and type(r.nom) == "string" then
                local m = NS.recettes.MetierDe(r)
                index[tostring(m) .. ":" .. Plier(r.nom)] = tonumber(id) or id
            end
        end
    end
    local apres = p.nom:match(":%s*(.+)$") or p.nom
    local r = index[tostring(metier) .. ":" .. NS.caisses.Plier(apres)]
    if r then p.recette = r end
    return r
end

local function Fiche(cle)
    return CraftCoreDB and CraftCoreDB.personnages and CraftCoreDB.personnages[cle]
end

local function Possede(fiche, objet)
    local sacs, banque = NS.inventaire.SacsEtBanque(fiche, objet)
    return (sacs or 0) + (banque or 0)
end
C.Possede = Possede

-- Le prix d'un patron ou d'une recompense : lu chez le vendeur, sinon celui
-- des guides (estime). Rend prix, estime.
function C.Prix(objet, metier, p)
    local b = Base()
    local lu = b and b.prix[objet]
    if lu then return lu, false end
    local web = D.PRIX_WEB_RECOMPENSES[objet]
    if web then return web, true end
    local t = PRIX_WEB[metier]
    if t and p then
        if p.palier and p.palier >= 6 and t.haut and (p.rang or 0) >= 290 then return t.haut, true end
        local prix = t[math.min(6, math.max(4, p.palier or 4))]
        if prix then return prix, true end
    end
    return nil, true
end

-- L'etat d'un patron pour un personnage : "appris", "possede" (achete, pas
-- encore appris), "achetable", "faveur" (pas assez), "palier" (reputation
-- trop basse), "rang" (metier trop bas), ou "inconnu" (le jeu n'a pas encore
-- donne l'objet).
function C.Patrons(fiche, metier)
    local liste = {}
    local rep = C.Reputation(fiche)
    local monRang = rep and rep.rang or 4
    local faveur = C.Faveur(fiche) or 0
    local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(metier)] or {}
    local rangMetier = tonumber(sien.rang) or 0
    local _, camp = C.Faction(fiche)
    for objet, m in pairs(D.PATRONS) do
        if m == metier and (not D.PATRONS_CAMP[objet] or D.PATRONS_CAMP[objet] == camp) then
            local p = Lire(objet)
            local e = { objet = objet, p = p, rang = p and p.rang or 0, palier = p and p.palier or 4, niveau = p and p.niveau or 0 }
            e.prix, e.estime = C.Prix(objet, metier, p)
            if not p then
                e.etat = "inconnu"
            else
                local r = Recette(objet, metier)
                e.recette = r
                -- La recette connue du catalogue : rang requis (si l'infobulle
                -- ne l'a pas dit) et chance de faire monter le metier.
                local rec = r and CraftCoreDB.recettes[tostring(r)]
                local R2 = NS.recettes
                if type(rec) == "table" then
                    if e.rang == 0 and R2.RangRequis then e.rang = tonumber(R2.RangRequis(rec)) or 0 end
                    if R2.FinDuOrange and R2.FinDuOrange(rec) and R2.ChanceDePoint and rangMetier > 0 then
                        local ok, chance = pcall(R2.ChanceDePoint, rec, rangMetier)
                        if ok and chance then
                            e.point = (chance >= 1 and "sur") or (chance >= 0.5 and "probable") or (chance > 0 and "peu") or "rien"
                        end
                    end
                end
                if r and type(fiche.recettesApprises) == "table" and fiche.recettesApprises[tostring(r)] then
                    e.etat = "appris"
                elseif Possede(fiche, objet) > 0 then
                    e.etat = "possede"
                elseif e.palier > monRang then
                    e.etat = "palier"
                elseif e.prix and e.prix > faveur then
                    e.etat = "faveur"
                elseif e.rang > rangMetier then
                    e.etat = "rang"

                else
                    e.etat = "achetable"
                end
            end
            table.insert(liste, e)
        end
    end
    table.sort(liste, function(a, b)
        if a.rang ~= b.rang then return a.rang < b.rang end
        if a.niveau ~= b.niveau then return a.niveau < b.niveau end
        return a.objet < b.objet
    end)
    return liste
end

-- Le vendeur d'un metier (ou d'un role) dans le camp du personnage.
function C.PNJ(camp, metier, role)
    for id, n in pairs(D.PNJ) do
        if n.camp == camp and ((metier and n.metier == metier) or (role and n.role == role)) then return id, n end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Caisses et ecrits
-- ---------------------------------------------------------------------------

function C.FaveurDeCaisse(objet)
    local c = D.CAISSES[objet]
    local t = c and D.FAVEUR_WEB[c.palier]
    return t and t[c.groupe] or nil
end

-- Les ecrits d'artisan que le personnage a sur lui : l'objet a fabriquer,
-- combien il en a, la reputation, la recette s'il la connait.
function C.Ecrits(fiche)
    local liste = {}
    local catalogue = CraftCoreDB and CraftCoreDB.recettes or {}
    for quete, e in pairs(D.ECRITS) do
        if Possede(fiche, e.ecrit) > 0 then
            local recette
            for id, r in pairs(catalogue) do
                if type(r) == "table" and r.objetProduit == e.objet then recette = tonumber(id) or id break end
            end
            local apprise = recette and type(fiche.recettesApprises) == "table" and fiche.recettesApprises[tostring(recette)]
            table.insert(liste, { quete = quete, ecrit = e.ecrit, objet = e.objet, rep = e.rep,
                possede = Possede(fiche, e.objet), recette = recette, apprise = apprise and true or false })
        end
    end
    table.sort(liste, function(a, b) return a.rep > b.rep end)
    return liste
end

-- Les ecrits scelles (a ouvrir) en sac : objet -> nombre.
C.ECRITS_SCELLES = { 262887, 262888, 262889, 262890 }

-- Les recompenses du camp, avec leur etat.
function C.Recompenses(fiche)
    local _, camp = C.Faction(fiche)
    local rep = C.Reputation(fiche)
    local monRang = rep and rep.rang or 4
    local liste = {}
    for objet, r in pairs(D.RECOMPENSES) do
        if not r.camp or r.camp == camp then
            local prix, estime = C.Prix(objet)
            local e = { objet = objet, genre = r.genre, palier = r.palier or 4, metier = r.metier, prix = prix, estime = estime }
            local sien = r.metier and type(fiche.metiers) == "table" and fiche.metiers[tostring(r.metier)]
            if Possede(fiche, objet) > 0 then e.etat = "possede"
            elseif e.palier > monRang then e.etat = "palier"
            elseif r.metier and not (sien and (tonumber(sien.rang) or 0) >= 300) then e.etat = "rang"
            elseif prix and prix > (C.Faveur(fiche) or 0) then e.etat = "faveur"
            else e.etat = "achetable" end
            table.insert(liste, e)
        end
    end
    table.sort(liste, function(a, b)
        if a.palier ~= b.palier then return a.palier < b.palier end
        return a.objet < b.objet
    end)
    return liste
end

-- ---------------------------------------------------------------------------
-- Ce qu'il y a de mieux a faire, une seule chose.
-- ---------------------------------------------------------------------------

function C.Conseil(fiche)
    local _, camp = C.Faction(fiche)
    if not camp then return nil end
    -- 1. Des caisses pretes : les remplir et les rendre.
    local pretes = 0
    for _, caisse in ipairs(NS.caisses.Connues(fiche.cle, false) or {}) do
        local prets = NS.caisses.PacksPrets(caisse)
        if prets > 0 then pretes = pretes + (caisse.exemplaires or 1) end
    end
    local scellees = 0
    for objet in pairs(D.SCELLEES) do scellees = scellees + Possede(fiche, objet) end
    if scellees > 0 or pretes > 0 then
        local id, n = C.PNJ(camp, nil, "remise")
        return { texte = string.format(L().TRADEHUB_TIP_CRATES, scellees + pretes, n and n.nom or "?"), pnj = id }
    end
    -- 2. Un ecrit dont l'objet est pret : le livrer.
    for _, e in ipairs(C.Ecrits(fiche)) do
        if e.possede > 0 then
            return { texte = string.format(L().TRADEHUB_TIP_WRIT, NS.inventaire.NomDObjet(e.objet), e.rep) }
        end
    end
    -- 3. Le patron achetable le moins cher d'un de ses metiers.
    local meilleur
    for metier in pairs(PRIX_WEB) do
        if type(fiche.metiers) == "table" and fiche.metiers[tostring(metier)] then
            for _, p in ipairs(C.Patrons(fiche, metier)) do
                if p.etat == "achetable" and (not meilleur or (p.prix or 0) < (meilleur.prix or 0)) then
                    meilleur = p
                    meilleur.metier = metier
                end
            end
        end
    end
    if meilleur then
        local id, n = C.PNJ(camp, meilleur.metier)
        return { texte = string.format(L().TRADEHUB_TIP_PATTERN, NS.inventaire.NomDObjet(meilleur.objet),
            (meilleur.estime and "~" or "") .. tostring(meilleur.prix or "?"), n and n.nom or "?"), pnj = id }
    end
    -- 4. Monter la reputation : les ecrits d'artisan.
    local rep = C.Reputation(fiche)
    if rep and rep.maxi and rep.valeur and rep.rang and rep.rang < 8 then
        return { texte = string.format(L().TRADEHUB_TIP_REP, rep.maxi - rep.valeur, C.NomDuPalier(rep.rang + 1)) }
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Releves : chez un vendeur du camp, ses prix ; la reputation et la faveur a
-- chaque changement.
-- ---------------------------------------------------------------------------

local function IdDuPNJ()
    local guid = NS.Appeler(UnitGUID, "npc")
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function ReleverMarchand()
    local b = Base()
    local id = IdDuPNJ()
    if not (b and id and D.PNJ[id]) then return end
    local nombre = NS.Appeler(NS.Lecture("GetMerchantNumItems")) or 0
    local lien, cout, element = NS.Lecture("GetMerchantItemLink"), NS.Lecture("GetMerchantItemCostInfo"), NS.Lecture("GetMerchantItemCostItem")
    if not (lien and cout and element) then return end
    for i = 1, nombre do
        local l = NS.Appeler(lien, i)
        local objet = type(l) == "string" and tonumber(l:match("item:(%d+)"))
        if objet then
            for k = 1, NS.Appeler(cout, i) or 0 do
                local _, valeur, lienCout = NS.Appeler(element, i, k)
                if type(lienCout) == "string" and lienCout:find("currency:" .. D.MONNAIE, 1, true) and tonumber(valeur) then
                    b.prix[objet] = tonumber(valeur)
                end
            end
        end
    end
end

-- Redessine la page des caisses seulement si la fenetre est ouverte et sur
-- cette page : jamais la rouvrir (elle se rouvrait a chaque releve).
local function Rafraichir()
    if NS.ecran and NS.ecran.page == "caisses" and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
end

local prevu = false
local function RafraichirBientot()
    if prevu then return end
    prevu = true
    local plusTard = NS.Lecture("C_Timer.After")
    local function Go() prevu = false Rafraichir() end
    if plusTard then plusTard(1, Go) else Go() end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE",
    "QUEST_TURNED_IN", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, ev, a)
    if ev == "GET_ITEM_INFO_RECEIVED" then
        if a and demandes[tonumber(a)] then demandes[tonumber(a)] = nil RafraichirBientot() end
        return
    end
    if ev == "MERCHANT_SHOW" or ev == "MERCHANT_UPDATE" then
        local ok, souci = pcall(ReleverMarchand)
        if not ok and NS.base.NoterIncident then NS.base.NoterIncident("commerce, vendeur", souci) end
    end
    local ok, souci = pcall(C.Relever)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("commerce, releve", souci) end
    RafraichirBientot()
end)
