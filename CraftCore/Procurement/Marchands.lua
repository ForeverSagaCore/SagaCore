local _, NS = ...

-- Marchands : ce qui s'achete, a quel prix, et ou.
--   - Le prix exact est releve chez chaque marchand qu'on visite (fenetre du
--     marchand ouverte) et garde pour tout le compte.
--   - A defaut, une estimation : quatre fois le prix de revente donne par le
--     jeu, la regle la plus courante. Elle est toujours signalee comme telle.
--   - Les marchands qui vendent un objet viennent de QuestieDB (s'il est la) :
--     le guidage mene au plus proche, sur le meme continent.

NS.marchands = {}
local marchands = NS.marchands

local function Base()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    if type(d.prixMarchand) ~= "table" then d.prixMarchand = {} end
    return d.prixMarchand
end

-- ---------------------------------------------------------------------------
-- Releve des prix chez le marchand
-- ---------------------------------------------------------------------------

-- Un article du marchand : prix (par lot), objets par lot, disponibles,
-- achetable, cout special (autre monnaie). Les deux formes du jeu : la
-- fonction d'origine, ou C_MerchantFrame.GetItemInfo (une table).
function marchands.InfoArticle(i)
    local C = _G.C_MerchantFrame
    if C and C.GetItemInfo then
        local ok, t = pcall(C.GetItemInfo, i)
        if ok and type(t) == "table" then
            return tonumber(t.price), tonumber(t.stackCount) or 1, tonumber(t.numAvailable), t.isPurchasable, t.hasExtendedCost
        end
    end
    local f = NS.Lecture("GetMerchantItemInfo")
    if f then
        local ok, _, _, cout, quantite, dispo, achetable, _, coutSpecial = pcall(f, i)
        if ok then return tonumber(cout), tonumber(quantite) or 1, tonumber(dispo), achetable, coutSpecial end
    end
    return nil
end

local function Relever()
    local prix = Base()
    local nombre = NS.Lecture("GetMerchantNumItems")
    local idDe = NS.Lecture("GetMerchantItemID")
    if not (prix and nombre and idDe) then return end
    for i = 1, tonumber(NS.Appeler(nombre)) or 0 do
        local id = tonumber(NS.Appeler(idDe, i))
        local cout, quantite, _, _, coutSpecial = marchands.InfoArticle(i)
        if id and cout and cout > 0 and quantite and quantite > 0 and not coutSpecial then
            prix[id] = cout / quantite
        end
    end
end

local cadre = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do pcall(cadre.RegisterEvent, cadre, e) end
cadre:SetScript("OnEvent", function() pcall(Relever) end)

-- Prix d'une unite, en pieces de cuivre, et s'il est exact (vu chez un
-- marchand) ou estime. nil si on ne sait rien.
function marchands.Prix(objet)
    objet = tonumber(objet)
    if not objet then return nil end
    local prix = Base()
    if prix and prix[objet] then return prix[objet], true end
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    local revente
    if info then
        local ok, _, _, _, _, _, _, _, _, _, _, r = pcall(info, objet)
        if ok then revente = tonumber(r) end
    end
    if revente and revente > 0 then return revente * 4, false end
    return nil
end

-- Somme en pieces, avec les icones des pieces du jeu (jamais "po/pa/pc").
local PIECES = {
    { 10000, "Interface\\MoneyFrame\\UI-GoldIcon" },
    { 100, "Interface\\MoneyFrame\\UI-SilverIcon" },
    { 1, "Interface\\MoneyFrame\\UI-CopperIcon" },
}
function marchands.Monnaie(cuivre)
    cuivre = math.floor((tonumber(cuivre) or 0) + 0.5)
    local f = NS.Lecture("C_CurrencyInfo.GetCoinTextureString", "GetCoinTextureString")
    local texte = f and NS.Appeler(f, cuivre)
    if type(texte) == "string" and texte ~= "" then return texte end
    local morceaux = {}
    for _, p in ipairs(PIECES) do
        local n = math.floor(cuivre / p[1])
        if p[1] < 10000 then n = n % 100 end
        if n > 0 or (p[1] == 1 and #morceaux == 0) then
            table.insert(morceaux, n .. "|T" .. p[2] .. ":0:0:2:0|t")
        end
    end
    return table.concat(morceaux, " ")
end

-- ---------------------------------------------------------------------------
-- Ou acheter : les marchands de QuestieDB
-- ---------------------------------------------------------------------------

local function Lire(entite, id, champ)
    local e = _G[entite]
    if type(e) ~= "table" or type(e.Get) ~= "function" or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end

local versCarte
local function CarteDeZone(zone)
    if not versCarte then
        versCarte = {}
        local lib = _G.LibQuestieDB
        local support = lib and lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
        local prive = support and support.private
        for _, champ in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
            local t = prive and prive[champ]
            if type(t) == "string" then
                local fn = loadstring(t)
                local ok, rendu = false, nil
                if fn then ok, rendu = pcall(fn) end
                t = ok and rendu or nil
            end
            if type(t) == "table" then
                for z, idCarte in pairs(t) do versCarte[z] = idCarte end
            end
        end
    end
    local c = versCarte[zone]
    return (c and c > 0) and c or nil
end

-- Pour les noeuds de recolte de la base du jeu (NoeudsJeu.lua).
marchands.Lire = Lire
marchands.CarteDeZone = CarteDeZone

local function MonCamp()
    local camp = NS.Appeler(NS.Lecture("UnitFactionGroup"), "player")
    return camp == "Horde" and "H" or "A"
end

-- Les points de vente d'un objet : { nom, carte, x, y } pour chaque marchand
-- amical envers notre camp.
local function PointsDeVente(objet)
    local points = {}
    local vendeurs = Lire("ItemDB", tonumber(objet), "vendors")
    if type(vendeurs) ~= "table" then return points end
    local camp = MonCamp()
    for _, pnj in ipairs(vendeurs) do
        local amical = Lire("NpcDB", pnj, "friendlyToFaction")
        if type(amical) == "string" and string.find(amical, camp, 1, true) then
            local nom = Lire("NpcDB", pnj, "name")
            local spawns = Lire("NpcDB", pnj, "spawns")
            for zone, liste in pairs(type(spawns) == "table" and spawns or {}) do
                local carte = CarteDeZone(zone)
                for _, p in ipairs(carte and type(liste) == "table" and liste or {}) do
                    if tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 then
                        table.insert(points, { nom = nom, carte = carte, x = p[1] / 100, y = p[2] / 100 })
                    end
                end
            end
        end
    end
    return points
end

-- Un marchand le vend-il ? (QuestieDB, ou la liste des objets vendus partout.)
function marchands.Achetable(objet)
    if NS.recettes and NS.recettes.EstVenduPartout and NS.recettes.EstVenduPartout(objet) then return true end
    local vendeurs = Lire("ItemDB", tonumber(objet), "vendors")
    return type(vendeurs) == "table" and #vendeurs > 0
end

-- On sait ou le guider ?
function marchands.Localisable(objet)
    return type(_G.ItemDB) == "table" and #PointsDeVente(objet) > 0
end

local function Monde(carte, x, y)
    local f, V = NS.Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if not (f and V) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        return a, b, continent
    end
    return nil
end

-- Le marchand le plus proche du personnage, sur son continent.
function marchands.PlusProche(objet)
    local carteJ = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carteJ and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carteJ, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil end
    local jx, jy, jc = Monde(carteJ, pos:GetXY())
    if not jx then return nil end
    local meilleur, cible
    for _, p in ipairs(PointsDeVente(objet)) do
        local x, y, c = Monde(p.carte, p.x, p.y)
        if x and c == jc then
            local d = (x - jx) ^ 2 + (y - jy) ^ 2
            if not meilleur or d < meilleur then meilleur, cible = d, p end
        end
    end
    return cible
end

-- Le drapeau sur la carte et la minicarte, comme celui que pose un garde
-- quand on lui demande son chemin. Pose par la bibliotheque de reperes que
-- Questie apporte (HereBeDragons) : la carte du jeu, OpenMap et la minicarte
-- l'affichent. Sans elle, notre propre drapeau sur la carte du jeu.
-- L'icone se choisit une fois (/cc drapeau) parmi celles du jeu.
local DRAPEAU_DEFAUT = { poi = 7 }

local function Habiller(tex)
    local choix = (CraftCoreDB and type(CraftCoreDB.drapeau) == "table") and CraftCoreDB.drapeau or DRAPEAU_DEFAUT
    tex:SetVertexColor(1, 1, 1)
    local coords = _G.GetPOITextureCoords
    if choix.poi and coords then
        tex:SetTexture("Interface\\Minimap\\POIIcons")
        tex:SetTexCoord(coords(choix.poi))
    elseif choix.chemin then
        tex:SetTexture(choix.chemin)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexture("Interface\\WorldStateFrame\\HordeFlag")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function Pin(taille)
    local f = CreateFrame("Frame")
    f:SetSize(taille, taille)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    return f
end

local pinCarte, pinMini, drapeau
local function HBD()
    local lib = _G.LibStub
    return lib and lib("HereBeDragons-Pins-2.0", true)
end

local function DrapeauMaison()
    local carteJeu = _G.WorldMapFrame
    local toile = carteJeu and carteJeu.ScrollContainer and carteJeu.ScrollContainer.Child
    if not toile then return nil end
    if not drapeau then
        drapeau = CreateFrame("Frame", nil, toile)
        drapeau:SetSize(20, 20)
        drapeau:SetFrameStrata("HIGH")
        drapeau.tex = drapeau:CreateTexture(nil, "OVERLAY")
        drapeau.tex:SetAllPoints()
        local function Placer()
            local p = drapeau.point
            if not p or not carteJeu.GetMapID or carteJeu:GetMapID() ~= p.carte then drapeau:Hide() return end
            drapeau:ClearAllPoints()
            drapeau:SetPoint("CENTER", toile, "TOPLEFT", p.x * toile:GetWidth(), -p.y * toile:GetHeight())
            drapeau:Show()
        end
        drapeau.Placer = Placer
        if carteJeu.HookScript then carteJeu:HookScript("OnShow", Placer) end
        if _G.hooksecurefunc and carteJeu.OnMapChanged then pcall(_G.hooksecurefunc, carteJeu, "OnMapChanged", Placer) end
    end
    Habiller(drapeau.tex)
    return drapeau
end

local drapeauPose
local function PoserDrapeau(p)
    drapeauPose = p
    local hbd = HBD()
    if hbd then
        pinCarte = pinCarte or Pin(18)
        pinMini = pinMini or Pin(14)
        Habiller(pinCarte.tex)
        Habiller(pinMini.tex)
        pcall(hbd.RemoveAllWorldMapIcons, hbd, marchands)
        pcall(hbd.RemoveAllMinimapIcons, hbd, marchands)
        local ok = pcall(hbd.AddWorldMapIconMap, hbd, marchands, pinCarte, p.carte, p.x, p.y,
            _G.HBD_PINS_WORLDMAP_SHOW_WORLD or 3)
        pcall(hbd.AddMinimapIconMap, hbd, marchands, pinMini, p.carte, p.x, p.y, false, true)
        if ok then return end
    end
    local d = DrapeauMaison()
    if d then d.point = p d.Placer() end
end

local function OterDrapeau()
    drapeauPose = nil
    local hbd = HBD()
    if hbd then
        pcall(hbd.RemoveAllWorldMapIcons, hbd, marchands)
        pcall(hbd.RemoveAllMinimapIcons, hbd, marchands)
    end
    if drapeau then drapeau.point = nil drapeau:Hide() end
end

-- Choix de l'icone du drapeau : toutes les icones de carte du jeu, et deux
-- drapeaux ; un clic garde le choix (pour tout le compte).
local choix
function marchands.ChoisirDrapeau()
    local L = NS.L
    if not choix then
        choix = NS.charte.Fenetre("CraftCoreChoixDrapeau", 8 * 34 + 40, 9 * 34 + 90,
            { portrait = false, sansPied = true, strate = "DIALOG" })
        if choix.titre then choix.titre:SetText(L.FLAG_PICK_TITLE) end
        choix:SetPoint("CENTER")
        if choix.fermer then choix.fermer:SetScript("OnClick", function() choix:Hide() end) end
        local aide = choix:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        aide:SetPoint("TOPLEFT", choix.zone, "TOPLEFT", 0, 0)
        aide:SetPoint("RIGHT", choix.zone, "RIGHT", 0, 0)
        aide:SetJustifyH("LEFT")
        aide:SetText(L.FLAG_PICK_HELP)
        local entrees = {}
        if _G.GetPOITextureCoords then
            for i = 0, 63 do table.insert(entrees, { poi = i, nom = tostring(i) }) end
        end
        table.insert(entrees, { chemin = "Interface\\WorldStateFrame\\HordeFlag", nom = "H" })
        table.insert(entrees, { chemin = "Interface\\WorldStateFrame\\AllianceFlag", nom = "A" })
        for rang, e in ipairs(entrees) do
            local b = CreateFrame("Button", nil, choix)
            b:SetSize(30, 30)
            local col, lig = (rang - 1) % 8, math.floor((rang - 1) / 8)
            b:SetPoint("TOPLEFT", choix.zone, "TOPLEFT", col * 34, -(28 + lig * 34))
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetPoint("TOPLEFT", 2, -2)
            b.tex:SetPoint("BOTTOMRIGHT", -2, 8)
            local c = { poi = e.poi, chemin = e.chemin }
            local avant = CraftCoreDB and CraftCoreDB.drapeau
            CraftCoreDB.drapeau = c
            Habiller(b.tex)
            CraftCoreDB.drapeau = avant
            b.num = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            b.num:SetPoint("BOTTOM", 0, 0)
            b.num:SetText(e.nom)
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnClick", function()
                CraftCoreDB.drapeau = c
                NS.Dire(string.format(L.FLAG_PICKED, e.nom))
                if drapeauPose then PoserDrapeau(drapeauPose) end
                choix:Hide()
            end)
        end
    end
    choix:Show()
end

marchands.OterDrapeau = OterDrapeau

marchands.PoserDrapeau = PoserDrapeau

-- La fleche de la suite jusqu'au marchand le plus proche, et le drapeau sur
-- la carte : l'objectif "marchand" de CraftCore (UI/Guidage.lua). Arrive,
-- l'objectif est atteint et le drapeau s'en va.
function marchands.Guider(objet)
    if NS.Trace then NS.Trace("guidage marchand : " .. tostring(objet)) end
    return NS.guidage and NS.guidage.Marchand and NS.guidage.Marchand(objet) or false
end

-- ---------------------------------------------------------------------------
-- Hotel des ventes : releve des prix, a la demande, quand il est ouvert
-- ---------------------------------------------------------------------------
-- Le jeu ne donne aucun prix d'encheres hors de l'hotel des ventes : on garde
-- le dernier releve de chaque objet (les offres les moins cheres), avec sa
-- date. Le prix moyen est celui des unites les moins cheres, pour la quantite
-- qu'il faut.

NS.encheres = {}
local encheres = NS.encheres

local function Releves()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    if type(d.prixEncheres) ~= "table" then d.prixEncheres = {} end
    return d.prixEncheres
end

-- Ce qui merite un releve : ce qui manque aux fabrications et aux
-- progressions, sauf ce que les marchands vendent.
function encheres.ObjetsARelever()
    local vus, liste = {}, {}
    local function Ajouter(objet)
        objet = tonumber(objet)
        if objet and not vus[objet] and not marchands.Achetable(objet) then
            vus[objet] = true
            table.insert(liste, objet)
        end
    end
    if NS.approvisionnement then
        local ok, l = pcall(NS.approvisionnement.Liste)
        for _, ligne in ipairs(ok and l or {}) do if ligne.manque > 0 then Ajouter(ligne.objet) end end
    end
    if NS.suivi and NS.suivi.RangsVises then
        local ok, rangs = pcall(NS.suivi.RangsVises)
        for _, o in ipairs(ok and rangs or {}) do
            for _, m in ipairs(o.matieres or {}) do if m.manque > 0 then Ajouter(m.objet) end end
        end
    end
    -- Les objets que demandent les quetes en cours (QuestCore) et qu'aucun
    -- monstre ne donne : a fabriquer, echanger ou acheter.
    for objet in pairs(encheres.ObjetsDeQuetes()) do Ajouter(objet) end
    -- Les plans d'une voie plus courte proposee dans le guide d'un metier
    -- (vendus par un marchand ou non : on veut leur prix a l'hotel des ventes).
    local g = NS.base.ReglagesGeneraux()
    for cle in pairs(type(g.plansARelever) == "table" and g.plansARelever or {}) do
        local objet = tonumber(cle)
        if objet and not vus[objet] then vus[objet] = true table.insert(liste, objet) end
    end
    return liste
end

function encheres.ObjetsDeQuetes()
    local api = _G.QuestCoreAPI
    local ok, t = false, nil
    if api and api.ObjetsAObtenir then ok, t = pcall(api.ObjetsAObtenir) end
    local res = {}
    for _, o in ipairs(ok and type(t) == "table" and t or {}) do
        local objet = tonumber(o.objet) or encheres.IdParNom(o.nom)
        if objet and (o.manque or 0) > 0 then res[objet] = (res[objet] or 0) + o.manque end
    end
    return res
end

-- ---------------------------------------------------------------------------
-- En route : ce qui est achete a l'hotel des ventes et attend au courrier.
-- Un achat compte des la confirmation ; a l'ouverture de la boite, son
-- contenu remplace ce compte (ce qui en est sorti est dans les sacs).
-- CraftCoreDB.enRoute[perso] = { [objet] = { n, quand } }
-- ---------------------------------------------------------------------------

local function EnRouteDuPerso()
    local d = CraftCoreDB
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    if type(d) ~= "table" or not cle then return nil end
    d.enRoute = type(d.enRoute) == "table" and d.enRoute or {}
    d.enRoute[cle] = type(d.enRoute[cle]) == "table" and d.enRoute[cle] or {}
    return d.enRoute[cle]
end

-- Combien d'un objet attend au courrier (achats recents compris).
function encheres.EnRoute(objet)
    local t = EnRouteDuPerso()
    local e = t and t[tonumber(objet) or 0]
    if type(e) ~= "table" then return 0 end
    -- Le courrier garde 30 jours ; au-dela, on oublie.
    local maintenant = NS.Appeler(_G.time) or 0
    if maintenant - (tonumber(e[2]) or 0) > 30 * 86400 then return 0 end
    return tonumber(e[1]) or 0
end

local function AjouterEnRoute(objet, n)
    objet, n = tonumber(objet), tonumber(n)
    local t = EnRouteDuPerso()
    if not (t and objet and n and n > 0) then return end
    local e = type(t[objet]) == "table" and t[objet] or { 0, 0 }
    t[objet] = { (tonumber(e[1]) or 0) + n, NS.Appeler(_G.time) or 0 }
    if NS.courrier and NS.courrier.Actualiser then pcall(NS.courrier.Actualiser) end
end

-- La boite ouverte : son contenu exact remplace le compte.
local function LireBoite()
    local nb, piece = NS.Lecture("GetInboxNumItems"), NS.Lecture("GetInboxItem")
    if not (nb and piece) then return end
    local n = tonumber(NS.Appeler(nb)) or 0
    local maxi = tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16
    local compte = {}
    for i = 1, n do
        for j = 1, maxi do
            local ok, _, objet, _, quantite = pcall(piece, i, j)
            objet = ok and tonumber(objet)
            if objet then compte[objet] = (compte[objet] or 0) + (tonumber(quantite) or 1) end
        end
    end
    local t = EnRouteDuPerso()
    if not t then return end
    local maintenant = NS.Appeler(_G.time) or 0
    for objet in pairs(t) do t[objet] = nil end
    for objet, q in pairs(compte) do t[objet] = { q, maintenant } end
end

do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MAIL_INBOX_UPDATE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local attente      -- achat de marchandise confirme, en attente du succes
    local derniereCle  -- la derniere recherche d'objet (pour un achat d'objet)
    f:SetScript("OnEvent", function(_, evenement, a1)
        if evenement == "MAIL_INBOX_UPDATE" then pcall(LireBoite)
        elseif evenement == "COMMODITY_PURCHASE_SUCCEEDED" then
            if attente then AjouterEnRoute(attente[1], attente[2]) attente = nil end
        elseif evenement == "COMMODITY_PURCHASE_FAILED" then attente = nil
        elseif evenement == "ITEM_SEARCH_RESULTS_UPDATED" then
            if type(a1) == "table" then derniereCle = a1 end
        end
    end)
    -- On regarde les achats du joueur (sans rien changer a ses gestes).
    local ah = _G.C_AuctionHouse
    if type(ah) == "table" and _G.hooksecurefunc then
        if ah.ConfirmCommoditiesPurchase then
            pcall(hooksecurefunc, ah, "ConfirmCommoditiesPurchase", function(objet, quantite)
                attente = { objet, quantite }
            end)
        end
        if ah.PlaceBid then
            pcall(hooksecurefunc, ah, "PlaceBid", function(enchere, montant)
                if not derniereCle then return end
                local n = tonumber(NS.Appeler(ah.GetNumItemSearchResults, derniereCle)) or 0
                for i = 1, n do
                    local info = NS.Appeler(ah.GetItemSearchResultInfo, derniereCle, i)
                    if type(info) == "table" and info.auctionID == enchere then
                        -- Un achat immediat seulement (une offre peut etre depassee).
                        if tonumber(info.buyoutAmount) and tonumber(montant) and montant >= info.buyoutAmount then
                            AjouterEnRoute(type(info.itemKey) == "table" and info.itemKey.itemID or derniereCle.itemID, info.quantity or 1)
                        end
                        break
                    end
                end
            end)
        end
    end
end

-- Combien il manque de chaque objet a relever (fabrications et progressions).
-- Ce qui attend au courrier n'y manque plus.
function encheres.Manques()
    local manques = {}
    local function Ajouter(objet, n)
        objet = tonumber(objet)
        if objet and n and n > 0 and not marchands.Achetable(objet) then manques[objet] = (manques[objet] or 0) + n end
    end
    if NS.approvisionnement then
        local ok, l = pcall(NS.approvisionnement.Liste)
        for _, ligne in ipairs(ok and l or {}) do Ajouter(ligne.objet, ligne.manque) end
    end
    if NS.suivi and NS.suivi.RangsVises then
        local ok, rangs = pcall(NS.suivi.RangsVises)
        for _, o in ipairs(ok and rangs or {}) do
            for _, m in ipairs(o.matieres or {}) do Ajouter(m.objet, m.manque) end
        end
    end
    for objet, n in pairs(encheres.ObjetsDeQuetes()) do Ajouter(objet, n) end
    for objet, n in pairs(manques) do
        local reste = n - encheres.EnRoute(objet)
        manques[objet] = reste > 0 and reste or nil
    end
    return manques
end

-- Lance la recherche d'un objet dans la fenetre de l'hotel des ventes : ses
-- offres s'affichent, et l'achat se fait a la main, comme d'habitude.
function encheres.Chercher(objet)
    local f = _G.AuctionHouseFrame
    local nom = NS.inventaire and NS.inventaire.NomDObjet and NS.inventaire.NomDObjet(objet)
    if not (f and f.SearchBar and nom) then return false end
    local mode = _G.AuctionHouseFrameDisplayMode
    if mode and mode.Buy and f.SetDisplayMode then pcall(f.SetDisplayMode, f, mode.Buy) end
    local boite = f.SearchBar.SearchBox
    if boite and boite.SetText then pcall(boite.SetText, boite, nom) end
    if f.SearchBar.StartSearch then pcall(f.SearchBar.StartSearch, f.SearchBar) end
    return true
end

-- Prix moyen d'une unite pour n unites (les moins cheres du releve), la date
-- du releve, et si l'objet etait absent. nil si jamais releve.
function encheres.Prix(objet, n)
    local r = Releves()
    r = r and r[tonumber(objet) or 0]
    if type(r) ~= "table" then return nil end
    if r.absent then return nil, r.quand, true end
    n = math.max(1, tonumber(n) or 1)
    local reste, cout, pris = n, 0, 0
    for _, o in ipairs(r.offres or {}) do
        local q = math.min(reste, o[2])
        cout, pris, reste = cout + q * o[1], pris + q, reste - q
        if reste <= 0 then break end
    end
    if pris == 0 then return nil, r.quand, true end
    return cout / pris, r.quand, false
end

function encheres.DateDe(quand)
    local ok, t = pcall(date, "%d/%m %H:%M", tonumber(quand) or 0)
    return ok and t or "?"
end

-- Le releve en cours : une file d'objets, une requete a la fois.
local file, rang, attendu, delai = nil, 0, nil, 0
local trouves, absents = 0, 0
local ecoute = CreateFrame("Frame")

local function AH() return _G.C_AuctionHouse end

function encheres.Disponible()
    local ah = AH()
    return ah and ah.SendSearchQuery and ah.MakeItemKey and true or false
end

function encheres.EnCours() return file ~= nil end
function encheres.Avancement() return rang, file and #file or 0, trouves, absents end

local function Noter(objet, offres)
    local r = Releves()
    if not r then return end
    table.sort(offres, function(a, b) return a[1] < b[1] end)
    while #offres > 12 do table.remove(offres) end
    local quand = NS.Appeler(_G.time) or 0
    if #offres == 0 then
        r[objet] = { absent = true, quand = quand }
        absents = absents + 1
    else
        r[objet] = { offres = offres, quand = quand }
        trouves = trouves + 1
    end
end

local function Lire(objet, cle)
    local ah = AH()
    local offres = {}
    local n = NS.Appeler(ah.GetNumCommoditySearchResults, objet)
    if tonumber(n) and n > 0 then
        for i = 1, math.min(n, 30) do
            local info = NS.Appeler(ah.GetCommoditySearchResultInfo, objet, i)
            if type(info) == "table" and tonumber(info.unitPrice) and tonumber(info.quantity) then
                table.insert(offres, { info.unitPrice, info.quantity })
            end
        end
        return offres
    end
    n = cle and NS.Appeler(ah.GetNumItemSearchResults, cle)
    for i = 1, math.min(tonumber(n) or 0, 30) do
        local info = NS.Appeler(ah.GetItemSearchResultInfo, cle, i)
        local q = type(info) == "table" and math.max(1, tonumber(info.quantity) or 1)
        if q and tonumber(info.buyoutAmount) and info.buyoutAmount > 0 then
            table.insert(offres, { info.buyoutAmount / q, q })
        end
    end
    return offres
end

local Suivant
local function Fini()
    file, attendu = nil, nil
    ecoute:SetScript("OnUpdate", nil)
    if NS.courrier and NS.courrier.Statut then
        NS.courrier.Statut(string.format(NS.L.AH_SCAN_DONE, trouves, absents))
    end
    if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
end

Suivant = function()
    if not file then return end
    if attendu then
        pcall(Noter, attendu.objet, Lire(attendu.objet, attendu.cle) or {})
        attendu = nil
    end
    rang = rang + 1
    if rang > #file then Fini() return end
    local ah = AH()
    local objet = file[rang]
    local cle = NS.Appeler(ah.MakeItemKey, objet)
    attendu = { objet = objet, cle = cle }
    delai = 3
    local tri = { { sortOrder = (_G.Enum and _G.Enum.AuctionHouseSortOrder and _G.Enum.AuctionHouseSortOrder.Price) or 0,
        reverseSort = false } }
    if not pcall(ah.SendSearchQuery, cle, tri, false) then attendu.echec = true end
    if NS.courrier and NS.courrier.Actualiser then pcall(NS.courrier.Actualiser) end
end

for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
    pcall(ecoute.RegisterEvent, ecoute, e)
end
ecoute:SetScript("OnEvent", function(_, evenement, a1)
    if evenement == "AUCTION_HOUSE_SHOW" then
        if NS.courrier and NS.courrier.Ouvert then NS.courrier.Ouvert("encheres") end
    elseif evenement == "AUCTION_HOUSE_CLOSED" then
        file, attendu = nil, nil
        ecoute:SetScript("OnUpdate", nil)
        if NS.courrier and NS.courrier.Ferme then NS.courrier.Ferme("encheres") end
    elseif attendu then
        -- La reponse a notre requete : la suivante, un instant apres (le jeu
        -- limite le rythme des requetes).
        local objet = tonumber(type(a1) == "table" and a1.itemID or a1)
        if objet == attendu.objet then delai = 0.3 end
    end
end)

local function Attendre(_, ecoule)
    if not file then return end
    delai = delai - (ecoule or 0)
    if delai > 0 then return end
    local ah = AH()
    -- Le jeu n'accepte une requete que lorsque son systeme est pret.
    if ah.IsThrottledMessageSystemReady and not NS.Appeler(ah.IsThrottledMessageSystemReady) then
        delai = 0.2
        return
    end
    Suivant()
end

function encheres.Relever(liste)
    if file or not encheres.Disponible() then return end
    liste = liste or encheres.ObjetsARelever()
    if #liste == 0 then return end
    if NS.Trace then NS.Trace("releve hv : " .. #liste) end
    file, rang, attendu, trouves, absents = liste, 0, nil, 0, 0
    delai = 0
    ecoute:SetScript("OnUpdate", Attendre)
end

-- ---------------------------------------------------------------------------
-- Ce que rapporte une recette, d'apres les prix connus
-- ---------------------------------------------------------------------------
-- Vente : le prix moyen d'une unite au dernier releve de l'hotel des ventes,
-- moins la commission de 5 %. Cout : chaque composant au prix du marchand
-- s'il en vend, sinon a celui de l'hotel des ventes. Benefice : la
-- difference, seulement si tous les prix sont connus.

local COMMISSION = 0.05

local function Lie(objet)
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    if not info then return false end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, lien = pcall(info, objet)
    return ok and lien == 1
end

function encheres.Valeur(recette)
    if type(recette) ~= "table" or not recette.objetProduit then return nil end
    local v = {}
    local prix, quand = encheres.Prix(recette.objetProduit, 1)
    if prix then v.vente, v.quand = prix * (1 - COMMISSION), quand end
    local cout, complet = 0, true
    for _, c in ipairs(recette.composants or {}) do
        local unite
        if marchands.Achetable(c.objet) then unite = marchands.Prix(c.objet) end
        if not unite then unite = encheres.Prix(c.objet, c.quantite) end
        if unite then cout = cout + unite * (c.quantite or 1) else complet = false end
    end
    if #(recette.composants or {}) == 0 then complet = false end
    if complet then v.cout = cout end
    if v.vente and v.cout then v.benefice = v.vente - v.cout end
    return v
end

-- Les recettes apprises du personnage connecte qu'il peut fabriquer tout de
-- suite, et dont l'objet se vend (pas lie quand ramasse).
local function Fabricables()
    local rendu = {}
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    pcall(NS.base.AvecPersonnage, cle, function()
        local liste = NS.recettes.Pour(nil)
        for _, r in ipairs(liste) do
            if r.objetProduit and NS.recettes.EstApprise(r.id) and not Lie(r.objetProduit) then
                local n = NS.recettes.CombienFabricablesAPortee(r)
                if n and n > 0 then table.insert(rendu, { recette = r, n = n }) end
            end
        end
    end)
    return rendu
end

-- A relever pour estimer ce qu'on fabrique : les objets et leurs composants
-- (hors marchands).
function encheres.ObjetsDesFabrications()
    local vus, liste = {}, {}
    local function Ajouter(objet)
        objet = tonumber(objet)
        if objet and not vus[objet] and not marchands.Achetable(objet) then
            vus[objet] = true
            table.insert(liste, objet)
        end
    end
    for _, f in ipairs(Fabricables()) do
        Ajouter(f.recette.objetProduit)
        for _, c in ipairs(f.recette.composants or {}) do Ajouter(c.objet) end
    end
    return liste
end

-- Ce qu'on peut fabriquer maintenant et vendre, le plus rentable d'abord.
function encheres.Rentables()
    local rendu = {}
    for _, f in ipairs(Fabricables()) do
        local v = encheres.Valeur(f.recette)
        if v and v.vente then
            table.insert(rendu, { recette = f.recette, n = f.n, valeur = v })
        end
    end
    table.sort(rendu, function(a, b)
        local ba, bb = a.valeur.benefice or -math.huge, b.valeur.benefice or -math.huge
        if ba ~= bb then return ba > bb end
        return (a.valeur.vente or 0) > (b.valeur.vente or 0)
    end)
    return rendu
end

-- Ce que le personnage connecte detient (sacs et banque) et qui a un prix
-- releve a l'hotel des ventes : prix net d'une unite (commission deduite).
function encheres.EnStock()
    local rendu = {}
    local moi = NS.base.Personnage and NS.base.Personnage()
    if not moi then return rendu end
    for cle in pairs(NS.base.StocksDe(moi) or {}) do
        local objet = tonumber(cle)
        if objet and not Lie(objet) then
            local prix, quand = encheres.Prix(objet, 1)
            if prix then
                local sacs, banque = NS.inventaire.SacsEtBanque(moi, objet)
                if sacs + banque > 0 then
                    local net = prix * (1 - COMMISSION)
                    table.insert(rendu, { objet = objet, sacs = sacs, banque = banque, unite = net,
                        total = net * (sacs + banque), quand = quand })
                end
            end
        end
    end
    table.sort(rendu, function(a, b) return a.total > b.total end)
    return rendu
end

-- Ce qui, dans les sacs, peut se vendre a l'hotel des ventes : ni lie, ni
-- gris, ni objet de quete, et rien dont un projet ou un rang vise a besoin.
-- { objet, nombre, sac, case, unite (net, au dernier releve), marchand,
--   releve (prix deja cherche) }, les plus rentables d'abord.
-- Onglet Recettes : les plans (recette, formule, patron...) des metiers du
-- personnage, pas encore appris, qu'il pourrait apprendre tout de suite
-- (rang du metier suffisant), et qu'il n'a pas deja en main. Le plus haut
-- rang d'abord. { objet, recette, rang, metier }.
function encheres.PlansAApprendre()
    local R = NS.recettes
    local fiche = NS.base.Personnage and NS.base.Personnage()
    if not (R and fiche and type(fiche.metiers) == "table") then return {} end
    local res, vus = {}, {}
    for _, r in pairs(R.Toutes() or {}) do
        if type(r) == "table" and r.id and not R.EstApprise(r.id) then
            local ligne = R.MetierDe and R.MetierDe(r)
            local sien = ligne and fiche.metiers[tostring(ligne)]
            local requis = R.RangRequis and R.RangRequis(r)
            if type(sien) == "table" and tonumber(sien.rang) and requis and requis <= sien.rang then
                local okO, objet = pcall(R.ObjetDuPlan, r)
                if okO and objet and not vus[objet] then
                    vus[objet] = true
                    local okP, possede = pcall(R.PlanPossede, r)
                    if not (okP and possede) then
                        table.insert(res, { objet = objet, recette = r, rang = requis, metier = ligne })
                    end
                end
            end
        end
    end
    table.sort(res, function(a, b)
        if a.rang ~= b.rang then return a.rang > b.rang end
        return tostring(a.recette.nom) < tostring(b.recette.nom)
    end)
    return res
end

-- Les objets propres a une classe (munitions, carquois, composants de sorts) :
-- jamais proposes a la vente.
local DE_CLASSE = {}
for _, id in ipairs({ 17033, 21177, 17029, 17028, 17056, 17030, 17020, 17031, 17032, 6265, 5565, 16583,
    17026, 17021, 17034, 17035, 17036, 17037, 17038, 5175, 5176, 5177, 5178, 5140, 5530, 17057, 17058 }) do DE_CLASSE[id] = true end

function encheres.AVendre()
    local C = function(nom) return NS.Lecture("C_Container." .. nom, nom) end
    local nbCases, contenu, idObjet = C("GetContainerNumSlots"), C("GetContainerItemInfo"), C("GetContainerItemID")
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    if not (nbCases and idObjet and info) then return {} end
    -- Ce dont les fabrications et les rangs vises ont besoin : on le garde.
    local garde = {}
    local okB, besoins = pcall(NS.recettes.BesoinsDesObjectifs)
    for objet, n in pairs(okB and besoins or {}) do garde[tonumber(objet) or 0] = n end
    -- Les composants des projets et des fabrications rapides.
    local cibles = { "rapides" }
    local okP, projets = pcall(NS.projets.Tous, false)
    for _, projet in ipairs(okP and projets or {}) do table.insert(cibles, projet.id) end
    for _, cible in ipairs(cibles) do
        local okC, entrees = pcall(NS.projets.Contenu, cible)
        for _, e in ipairs(okC and entrees or {}) do
            local r = CraftCoreDB and CraftCoreDB.recettes and CraftCoreDB.recettes[tostring(e.recette)]
            for _, c in ipairs(r and r.composants or {}) do
                local o = tonumber(c.objet)
                if o then garde[o] = (garde[o] or 0) + (tonumber(c.quantite) or 1) * (tonumber(e.quantite) or 1) end
            end
        end
    end
    local parObjet, liste = {}, {}
    for sac = 0, 5 do
        for case = 1, tonumber(NS.Appeler(nbCases, sac)) or 0 do
            local objet = tonumber(NS.Appeler(idObjet, sac, case))
            local d = objet and NS.Appeler(contenu, sac, case)
            local lie = type(d) == "table" and d.isBound
            if objet and not lie then
                local v = parObjet[objet]
                if not v then
                    local ok, _, _, qualite, _, _, _, _, _, _, _, prixMarchand, classe = pcall(info, objet)
                    local vendable = ok and (tonumber(qualite) or 0) >= 1 and classe ~= 12 and classe ~= 6 and classe ~= 11
                        and not DE_CLASSE[objet] and not Lie(objet)
                    if vendable then
                        v = { objet = objet, nombre = 0, sac = sac, case = case, marchand = tonumber(prixMarchand) or 0 }
                        parObjet[objet] = v
                        table.insert(liste, v)
                    else
                        parObjet[objet] = false
                    end
                end
                if v then v.nombre = v.nombre + (type(d) == "table" and tonumber(d.stackCount) or 1) end
            end
        end
    end
    local rendu = {}
    for _, v in ipairs(liste) do
        local reste = v.nombre - (garde[v.objet] or 0)
        if reste > 0 then
            v.nombre = reste
            local prix, quand = encheres.Prix(v.objet, reste)
            v.releve = quand ~= nil
            if prix then v.unite = prix * (1 - COMMISSION) end
            table.insert(rendu, v)
        end
    end
    table.sort(rendu, function(a, b)
        local va, vb = (a.unite or 0) * a.nombre, (b.unite or 0) * b.nombre
        if va ~= vb then return va > vb end
        return (a.marchand or 0) * a.nombre > (b.marchand or 0) * b.nombre
    end)
    return rendu
end

-- Met l'objet de cette case en vente dans la fenetre de l'hotel des ventes :
-- le jeu propose son prix, le joueur verifie et valide lui-meme.
-- Vendre directement depuis le panneau (clic du joueur) : au prix le plus bas
-- du dernier releve, arrondi a l'argent (le jeu ne prend pas les
-- pieces de cuivre), pour 24 heures. Par les fonctions de l'hotel des ventes,
-- comme les add-ons de vente : jamais par sa fenetre.
local DUREE_24H = 2
function encheres.PrixDeVente(objet)
    local r = Releves()
    r = r and r[tonumber(objet) or 0]
    local plus = type(r) == "table" and type(r.offres) == "table" and r.offres[1] and tonumber(r.offres[1][1])
    if not plus then return nil, r and r.quand end
    -- Le meme prix que l'offre la moins chere, arrondi a l'argent en dessous
    -- (le jeu ne prend que l'argent) : jamais une baisse d'une piece entiere.
    local prix = math.floor(plus / 100) * 100
    return math.max(100, prix), r.quand
end
-- Le depot que le jeu prendra pour cette vente, s'il le dit.
function encheres.DepotDeVente(v)
    local ah = AH()
    local Loc = _G.ItemLocation
    if not (ah and Loc and Loc.CreateFromBagAndSlot) then return nil end
    local okL, loc = pcall(Loc.CreateFromBagAndSlot, Loc, v.sac, v.case)
    if not okL or not loc then return nil end
    local statut = ah.GetItemCommodityStatus and NS.Appeler(ah.GetItemCommodityStatus, loc)
    local enum = _G.Enum and _G.Enum.ItemCommodityStatus
    if enum and statut == enum.Commodity and ah.CalculateCommodityDeposit then
        return tonumber(NS.Appeler(ah.CalculateCommodityDeposit, v.objet, DUREE_24H, v.nombre))
    elseif ah.CalculateItemDeposit then
        return tonumber(NS.Appeler(ah.CalculateItemDeposit, loc, DUREE_24H, v.nombre))
    end
    return nil
end

-- Preparer : l'objet dans la vente de la fenetre de l'hotel des ventes, comme
-- un clic droit sur l'objet dans le sac. La mise en vente reste au joueur.
function encheres.PreparerVente(v)
    local f = _G.AuctionHouseFrame
    local Loc = _G.ItemLocation
    if not (f and f.SetPostItem and Loc and Loc.CreateFromBagAndSlot) then return false end
    if NS.Appeler(NS.Lecture("InCombatLockdown")) then return false end
    local okL, loc = pcall(Loc.CreateFromBagAndSlot, Loc, v.sac, v.case)
    if not okL or not loc then return false end
    if not pcall(f.SetPostItem, f, loc) then return false end
    -- Toute la pile, comme demande ; le joueur ajuste ensuite dans la fenetre.
    for _, nom in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local sf = f[nom]
        if sf and sf.IsShown and sf:IsShown() and sf.SetToMaxQuantity then pcall(sf.SetToMaxQuantity, sf) end
    end
    return true
end

function encheres.Vendre(v)
    local ah = AH()
    local Loc = _G.ItemLocation
    if not (ah and Loc and Loc.CreateFromBagAndSlot) then return false, "indisponible" end
    if NS.Appeler(NS.Lecture("InCombatLockdown")) then return false, "combat" end
    local prix = encheres.PrixDeVente(v.objet)
    if not prix then return false, "prix" end
    local okL, loc = pcall(Loc.CreateFromBagAndSlot, Loc, v.sac, v.case)
    if not okL or not loc then return false, "objet" end
    local statut = ah.GetItemCommodityStatus and NS.Appeler(ah.GetItemCommodityStatus, loc)
    local enum = _G.Enum and _G.Enum.ItemCommodityStatus
    local ok
    if enum and statut == enum.Commodity and ah.PostCommodity then
        ok = pcall(ah.PostCommodity, loc, DUREE_24H, v.nombre, prix)
    elseif ah.PostItem then
        -- Un objet unique : une vente par emplacement (la pile de cette case).
        local d = NS.Appeler(NS.Lecture("C_Container.GetContainerItemInfo"), v.sac, v.case)
        local n = type(d) == "table" and tonumber(d.stackCount) or 1
        ok = pcall(ah.PostItem, loc, DUREE_24H, math.min(n, v.nombre), nil, prix)
    end
    return ok and true or false, ok and prix or "refus"
end

-- On ne touche jamais aux fenetres du jeu (cela les « salirait » et la mise
-- en vente pourrait etre bloquee) : l'objet est pris en main, le joueur le
-- pose dans la case de vente de l'hotel des ventes.
function encheres.MettreEnVente(sac, case)
    local prendre = NS.Lecture("C_Container.PickupContainerItem", "PickupContainerItem")
    if not prendre then return false end
    if NS.Appeler(NS.Lecture("InCombatLockdown")) then return false end
    local ok = pcall(prendre, sac, case)
    return ok
end

-- Pour les autres add-ons de la suite (TradeCore) : ce qu'on peut fabriquer
-- et vendre, et ce qu'on a a vendre, avec les prix releves.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
_G.CraftCoreAPI.Rentables = function()
    local liste = {}
    for _, r in ipairs(encheres.Rentables()) do
        table.insert(liste, { objet = r.recette.objetProduit, n = r.n, vente = r.valeur.vente, cout = r.valeur.cout,
            benefice = r.valeur.benefice, quand = r.valeur.quand })
    end
    return liste
end
_G.CraftCoreAPI.EnStock = function() return encheres.EnStock() end
_G.CraftCoreAPI.Monnaie = function(cuivre) return marchands.Monnaie(cuivre) end
_G.CraftCoreAPI.DateDe = function(quand) return encheres.DateDe(quand) end

-- "A l'HV : se vend X, composants Y, benefice Z (releve du ...)" ou nil.
function encheres.TexteDeValeur(v)
    if not v or not v.vente then return nil end
    local L = NS.L
    local morceaux = { string.format(L.AH_VALUE_SELLS, marchands.Monnaie(v.vente)) }
    if v.cout then table.insert(morceaux, string.format(L.AH_VALUE_COST, marchands.Monnaie(v.cout))) end
    if v.benefice then
        local couleur = v.benefice >= 0 and "|cff4fd16a" or "|cffff6060"
        table.insert(morceaux, couleur .. string.format(L.AH_VALUE_PROFIT, (v.benefice < 0 and "-" or ""),
            marchands.Monnaie(math.abs(v.benefice))) .. "|r")
    else
        table.insert(morceaux, "|cff8c8c8c" .. L.AH_VALUE_NO_COST .. "|r")
    end
    return string.format(L.AH_VALUE, table.concat(morceaux, ", "), encheres.DateDe(v.quand))
end

-- ---------------------------------------------------------------------------
-- Rang maximum atteint : il faut aller voir le maitre du metier
-- ---------------------------------------------------------------------------
-- Un metier arrive au bout de son rang (75/75, 150/150...) alors qu'un rang
-- superieur existe et que le niveau du personnage le permet : un avis
-- s'affiche a l'endroit du bandeau des quetes de QuestCore (la ou le joueur
-- l'a place), et reste jusqu'a ce qu'on clique "J'ai compris". Ensuite, s'il
-- passe pres d'un maitre de ce metier (QuestieDB), l'avis revient pour le
-- lui rappeler, une fois par passage.

NS.avisRang = {}
-- Lecture de QuestieDB (le nom Lire est repris plus haut pour autre chose).
local function LireDB(entite, id, champ)
    local e = _G[entite]
    if type(e) ~= "table" or type(e.Get) ~= "function" or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end
local avisRang = NS.avisRang

-- Rangs et niveau demande pour le rang suivant.
local PALIERS = { [75] = 10, [150] = 20, [225] = 35, [300] = 50, [375] = 65 }
local function Plafond()
    local maxi = tonumber(NS.Appeler(NS.Lecture("GetMaxPlayerLevel"))) or 60
    if maxi >= 80 then return 450 elseif maxi >= 70 then return 375 end
    return 300
end

-- Racines des titres des maitres (sans accents), francais et anglais.
local RACINES = {
    [171] = { "alchim" }, [164] = { "forge", "blacksmith" }, [333] = { "enchant" },
    [202] = { "ingenieur", "ingenierie", "engineer" }, [165] = { "cuir", "leather" },
    [197] = { "coutur", "tailor" }, [185] = { "cuisin", "cook", "chef" },
    [129] = { "secour", "first aid" }, [186] = { "mine", "mining" },
    [182] = { "herbor", "herbalis" }, [393] = { "depec", "skinn" }, [356] = { "pech", "fish" },
}
local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["à"] = "a", ["â"] = "a",
    ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["û"] = "u", ["ù"] = "u", ["ç"] = "c" }
local function Simple(texte)
    texte = string.lower(tostring(texte or ""))
    for a, b in pairs(ACCENTS) do texte = string.gsub(texte, a, b) end
    return texte
end

local function Memoire()
    if type(CraftCoreDB) ~= "table" then return {} end
    CraftCoreDB.avisRang = type(CraftCoreDB.avisRang) == "table" and CraftCoreDB.avisRang or {}
    local cle = NS.ClePersonnage and NS.ClePersonnage() or "?"
    CraftCoreDB.avisRang[cle] = type(CraftCoreDB.avisRang[cle]) == "table" and CraftCoreDB.avisRang[cle] or {}
    return CraftCoreDB.avisRang[cle]
end

-- Les metiers du personnage connecte bloques au bout de leur rang.
function avisRang.Bloques()
    local fiche = NS.base.Personnage()
    local liste = {}
    if not fiche or type(fiche.metiers) ~= "table" then return liste end
    local niveau = tonumber(NS.Appeler(NS.Lecture("UnitLevel"), "player")) or 1
    local plafond = Plafond()
    for cle, sien in pairs(fiche.metiers) do
        local ligne = tonumber(cle)
        local rang, rangMax = tonumber(sien.rang), tonumber(sien.rangMax)
        if ligne and rang and rangMax and rang >= rangMax and rangMax < plafond
            and PALIERS[rangMax] and niveau >= PALIERS[rangMax] then
            table.insert(liste, { ligne = ligne, nom = sien.nom, rang = rang, rangMax = rangMax })
        end
    end
    table.sort(liste, function(a, b) return a.ligne < b.ligne end)
    return liste
end

-- La fenetre : l'habit du bandeau des quetes, a sa place.
local cadreA
local function Placer()
    cadreA:ClearAllPoints()
    local qb = _G.QuestCoreBandeau
    if qb and qb:IsShown() then
        cadreA:SetPoint("TOP", qb, "BOTTOM", 0, -4)
        return
    end
    local d = _G.QuestCoreDB
    local r = type(d) == "table" and type(d.reglages) == "table" and type(d.reglages.general) == "table"
        and type(d.reglages.general.bandeau) == "table" and d.reglages.general.bandeau or {}
    cadreA:SetPoint("TOP", UIParent, "TOP", tonumber(r.x) or 0, tonumber(r.y) or -30)
end

local function Construire()
    if cadreA then return cadreA end
    local ok, f = pcall(CreateFrame, "Frame", "CraftCoreAvisRang", UIParent, "BackdropTemplate")
    cadreA = ok and f or CreateFrame("Frame", "CraftCoreAvisRang", UIParent)
    if cadreA.SetBackdrop then
        cadreA:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        cadreA:SetBackdropColor(0.09, 0.09, 0.09, 0.9)
        cadreA:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
    end
    cadreA:SetFrameStrata("HIGH")
    cadreA:SetSize(380, 84)
    cadreA:SetClampedToScreen(true)
    cadreA:EnableMouse(true)
    -- L'icone du metier dans le cercle dore du jeu.
    local rond = CreateFrame("Frame", nil, cadreA)
    rond:SetSize(32, 32)
    rond:SetPoint("TOPLEFT", cadreA, "TOPLEFT", 10, -10)
    rond.icone = rond:CreateTexture(nil, "ARTWORK")
    rond.icone:SetSize(24, 24)
    rond.icone:SetPoint("CENTER")
    if rond.icone.SetMask then pcall(rond.icone.SetMask, rond.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    rond.anneau = rond:CreateTexture(nil, "OVERLAY")
    rond.anneau:SetSize(54, 54)
    rond.anneau:SetPoint("TOPLEFT", rond, "TOPLEFT", -1, 1)
    rond.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    cadreA.rond = rond
    cadreA.titre = cadreA:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cadreA.titre:SetPoint("TOPLEFT", rond, "TOPRIGHT", 10, -2)
    cadreA.titre:SetPoint("RIGHT", cadreA, "RIGHT", -10, 0)
    cadreA.titre:SetJustifyH("LEFT")
    cadreA.titre:SetWordWrap(false)
    cadreA.texte = cadreA:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cadreA.texte:SetPoint("TOPLEFT", cadreA.titre, "BOTTOMLEFT", 0, -4)
    cadreA.texte:SetPoint("RIGHT", cadreA, "RIGHT", -10, 0)
    cadreA.texte:SetJustifyH("LEFT")
    cadreA.texte:SetWordWrap(false)
    -- Le seul moyen de le fermer : l'acquitter.
    local b = CreateFrame("Button", "CraftCoreAvisRangOK", cadreA, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetPoint("BOTTOMRIGHT", cadreA, "BOTTOMRIGHT", -10, 10)
    cadreA.ok = b
    -- Me guider : vers le maitre le plus proche ; ferme l'avis aussi.
    local g = CreateFrame("Button", "CraftCoreAvisRangGuider", cadreA, "UIPanelButtonTemplate")
    g:SetSize(120, 22)
    g:SetPoint("RIGHT", b, "LEFT", -8, 0)
    cadreA.guider = g
    cadreA:Hide()
    return cadreA
end

local enCours           -- le metier montre
local rappelLe = {}     -- dernier rappel, par metier (pres d'un maitre)

-- Les maitres qui enseignent les paliers Expert (au-dela de 150) et Artisan
-- (au-dela de 225) dans WoW Forever : tous les maitres ne les enseignent
-- pas. Source : Warcraft Tavern, maitres de metier de Forever. Par numero de
-- PNJ et camp ("A", "H", "AH"). Recolte (herboristerie, minage, depecage) :
-- les maitres hors des zones de depart enseignent tous les paliers.
local PALIERS_MAITRES = {
    [171] = { expert = { { 4160, "A" }, { 246795, "A" }, { 275322, "A" }, { 11042, "A" }, { 4611, "H" } },
              artisan = { { 1386, "H" }, { 259585, "AH" } } },
    [164] = { expert = { { 28694, "A" }, { 4258, "A" }, { 3355, "H" } }, artisan = { { 2836, "AH" } } },
    [333] = { expert = { { 11072, "A" }, { 259287, "A" }, { 251978, "A" }, { 11074, "H" } }, artisan = {} },
    [202] = { expert = { { 5174, "A" }, { 11017, "H" } }, artisan = { { 8736, "AH" } } },
    [165] = { expert = { { 4212, "A" }, { 3007, "H" } }, artisan = { { 11098, "H" } } },
    [197] = { expert = { { 251972, "A" }, { 1346, "A" }, { 1300, "A" }, { 4576, "H" } }, artisan = { { 2399, "H" } } },
}
do
    local recolte = {
        [182] = { { 812, "A" }, { 3965, "A" }, { 275321, "A" }, { 4204, "A" }, { 908, "AH" }, { 257021, "AH" }, { 1218, "A" },
            { 1473, "A" }, { 3604, "A" }, { 12025, "AH" }, { 5137, "A" }, { 5502, "A" }, { 254345, "AH" }, { 5566, "A" },
            { 1458, "A" }, { 2856, "H" }, { 2390, "H" }, { 2114, "H" }, { 3404, "H" }, { 3013, "H" }, { 4614, "H" }, { 3185, "H" }, { 8146, "H" } },
        [186] = { { 1681, "A" }, { 1701, "A" }, { 5513, "A" }, { 4254, "A" }, { 255891, "AH" }, { 252388, "AH" }, { 6297, "A" }, { 3137, "A" },
            { 257022, "AH" }, { 8128, "AH" }, { 5392, "A" }, { 3001, "H" }, { 4598, "H" }, { 3555, "H" }, { 3175, "H" }, { 3357, "H" } },
        [393] = { { 6291, "A" }, { 6292, "A" }, { 6306, "A" }, { 257003, "AH" }, { 6288, "A" }, { 1292, "A" }, { 257024, "AH" }, { 6287, "A" },
            { 6295, "A" }, { 6387, "H" }, { 7087, "H" }, { 8144, "H" }, { 12030, "H" }, { 7089, "H" }, { 6289, "H" }, { 7088, "H" }, { 6290, "H" } },
    }
    for ligne, liste in pairs(recolte) do PALIERS_MAITRES[ligne] = { expert = liste, artisan = liste } end
end
-- Cuisine, peche, secourisme : un livre ou une quete, pas un maitre.
local PALIERS_LIVRES = { [185] = true, [356] = true, [129] = true }

-- Les maitres qui peuvent apprendre le palier au-dela de rangMax : leurs
-- numeros (nil : n'importe quel maitre du metier).
local function MaitresDuPalier(ligne, rangMax)
    local t = PALIERS_MAITRES[ligne]
    if not t or not rangMax or rangMax < 150 then return nil end
    local liste = rangMax >= 225 and t.artisan or t.expert
    local camp = MonCamp()
    local ids = {}
    for _, e in ipairs(liste or {}) do
        if string.find(e[2], camp, 1, true) then table.insert(ids, e[1]) end
    end
    return ids
end
function avisRang.PalierParLivre(ligne) return PALIERS_LIVRES[tonumber(ligne) or 0] == true end
local LireMaitres       -- plus bas : la lecture des maitres de chaque metier

local function Montrer(m, pres)
    Construire()
    enCours = m
    local L = NS.L
    local icones = NS.ICONES_METIERS or {}
    cadreA.rond.icone:SetTexture(icones[m.ligne] or "Interface\\Icons\\INV_Misc_QuestionMark")
    cadreA.titre:SetText(string.format(L.RANK_MAX_TITLE, m.nom or "?", m.rang, m.rangMax))
    cadreA.texte:SetText(pres and string.format(L.RANK_MAX_NEAR, pres) or L.RANK_MAX_TEXT)
    cadreA.ok:SetText(L.RANK_MAX_OK)
    LireMaitres()
    cadreA.guider:SetText(L.RANK_MAX_GUIDE or "Guide me")
    cadreA.guider:SetScript("OnClick", function()
        local ok = NS.guidage and NS.guidage.MaitreDeMetier and NS.guidage.MaitreDeMetier(m.ligne, m.nom, m.rangMax)
        if ok then
            Memoire()[tostring(m.ligne)] = m.rangMax
            cadreA:Hide()
            enCours = nil
        end
    end)
    cadreA.ok:SetScript("OnClick", function()
        Memoire()[tostring(m.ligne)] = m.rangMax
        cadreA:Hide()
        enCours = nil
        avisRang.Verifier()
    end)
    Placer()
    cadreA:Show()
end

-- Un avis pour le premier metier bloque pas encore acquitte a ce rang.
function avisRang.Verifier()
    if enCours and cadreA and cadreA:IsShown() then
        -- Le metier montre a-t-il ete debloque entre-temps ?
        local encore = false
        for _, m in ipairs(avisRang.Bloques()) do if m.ligne == enCours.ligne then encore = true end end
        if not encore then cadreA:Hide() enCours = nil else return end
    end
    local vus = Memoire()
    for _, m in ipairs(avisRang.Bloques()) do
        if vus[tostring(m.ligne)] ~= m.rangMax then Montrer(m) return end
    end
end

-- Les maitres de chaque metier, d'apres QuestieDB (lus une fois, par lots).
local maitres, lectureMaitres
LireMaitres = function()
    if maitres or lectureMaitres then return end
    local base = _G.NpcDB
    if type(base) ~= "table" or type(base.GetAllIds) ~= "function" then return end
    local ok, ids = pcall(base.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    local liste = {}
    for _, id in pairs(ids) do table.insert(liste, id) end
    lectureMaitres = {}
    local camp = MonCamp()
    local rang, cadre = 1, CreateFrame("Frame")
    local band = _G.bit and _G.bit.band
    cadre:SetScript("OnUpdate", function(self)
        local fin = math.min(#liste, rang + 400)
        for i = rang, fin do
            local id = liste[i]
            local drapeaux = tonumber(LireDB("NpcDB", id, "npcFlags"))
            if drapeaux and band and band(drapeaux, 16) ~= 0 then
                local amical = LireDB("NpcDB", id, "friendlyToFaction")
                if type(amical) ~= "string" or string.find(amical, camp, 1, true) then
                    local titre = Simple(LireDB("NpcDB", id, "subName"))
                    for ligne, racines in pairs(RACINES) do
                        for _, r in ipairs(racines) do
                            if titre ~= "" and string.find(titre, r, 1, true) then
                                lectureMaitres[ligne] = lectureMaitres[ligne] or {}
                                table.insert(lectureMaitres[ligne], id)
                                break
                            end
                        end
                    end
                end
            end
        end
        rang = fin + 1
        if rang > #liste then
            maitres = lectureMaitres
            lectureMaitres = nil
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Le maitre le plus proche d'un metier, s'il est a moins de 60 metres.
local function MaitreProche(ligne, jx, jy, jc, rangMax)
    for _, id in ipairs(MaitresDuPalier(ligne, rangMax) or (maitres and maitres[ligne]) or {}) do
        local spawns = LireDB("NpcDB", id, "spawns")
        for zone, points in pairs(type(spawns) == "table" and spawns or {}) do
            local carte = CarteDeZone(zone)
            for _, p in ipairs(carte and type(points) == "table" and points or {}) do
                if tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 then
                    local x, y, c = Monde(carte, p[1] / 100, p[2] / 100)
                    if x and c == jc and ((x - jx) ^ 2 + (y - jy) ^ 2) < 60 * 60 then
                        return LireDB("NpcDB", id, "name") or "?"
                    end
                end
            end
        end
    end
end

-- Le palier suivant d'un metier bloque a son rang maximum : { rang (le
-- nouveau maximum), niveau (niveau du personnage requis pour l'apprendre) },
-- ou nil si c'est deja le dernier palier.
function avisRang.PalierSuivant(rangMax)
    rangMax = tonumber(rangMax)
    if not rangMax or rangMax >= Plafond() then return nil end
    return { rang = rangMax + 75, niveau = PALIERS[rangMax] }
end

-- Le maitre d'un metier le plus proche, sur le continent du personnage :
-- { carte, x (0-1), y (0-1), nom }, ou nil (maitres pas encore lus, aucun).
function avisRang.MaitrePlusProche(ligne, rangMax)
    local duPalier = MaitresDuPalier(ligne, rangMax)
    if not duPalier then
        LireMaitres()
        if not maitres then return nil end
    end
    local carteJ = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carteJ and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carteJ, "player")
    if type(pos) ~= "table" or not pos.GetXY then return nil end
    local jx, jy, jc = Monde(carteJ, pos:GetXY())
    if not jx then return nil end
    local meilleur, cible
    for _, id in ipairs(duPalier or maitres[ligne] or {}) do
        local spawns = LireDB("NpcDB", id, "spawns")
        for zone, points in pairs(type(spawns) == "table" and spawns or {}) do
            local carte = CarteDeZone(zone)
            for _, p in ipairs(carte and type(points) == "table" and points or {}) do
                if tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 then
                    local x, y, c = Monde(carte, p[1] / 100, p[2] / 100)
                    if x and c == jc then
                        local d = (x - jx) ^ 2 + (y - jy) ^ 2
                        if not meilleur or d < meilleur then
                            meilleur = d
                            cible = { carte = carte, x = p[1] / 100, y = p[2] / 100, nom = LireDB("NpcDB", id, "name") or "?" }
                        end
                    end
                end
            end
        end
    end
    return cible
end

-- Toutes les 3 secondes, tant qu'un metier attend son maitre : est-on pres
-- de l'un d'eux ? Un rappel par metier toutes les 10 minutes au plus.
do
    local veille = CreateFrame("Frame")
    local attente = 5
    veille:SetScript("OnUpdate", function(_, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 3
        if cadreA and cadreA:IsShown() then return end
        if NS.Appeler(NS.Lecture("InCombatLockdown")) then return end
        local ok, bloques = pcall(avisRang.Bloques)
        if not ok or #bloques == 0 then return end
        LireMaitres()
        if not maitres then return end
        local carteJ = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
        local pos = carteJ and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carteJ, "player")
        if type(pos) ~= "table" or not pos.GetXY then return end
        local jx, jy, jc = Monde(carteJ, pos:GetXY())
        if not jx then return end
        local maintenant = NS.Appeler(_G.GetTime) or 0
        for _, m in ipairs(bloques) do
            if maintenant - (rappelLe[m.ligne] or -1e9) > 600 then
                local okP, nom = pcall(MaitreProche, m.ligne, jx, jy, jc, m.rangMax)
                if okP and nom then
                    rappelLe[m.ligne] = maintenant
                    Montrer(m, nom)
                    return
                end
            end
        end
    end)
end

-- Apres chaque releve des niveaux de metier (connexion, point gagne, rang
-- appris) : l'avis apparait, ou disparait si le rang a ete monte.
if NS.recettes and NS.recettes.ReleverNiveaux then
    local brut = NS.recettes.ReleverNiveaux
    NS.recettes.ReleverNiveaux = function(...)
        local r = brut(...)
        pcall(avisRang.Verifier)
        return r
    end
end

-- ---------------------------------------------------------------------------
-- Comment obtenir un objet : pour les quetes de QuestCore qui demandent un
-- objet qu'aucun monstre ne donne. Ce que CraftCore sait : qui en a deja, qui
-- sait le fabriquer, s'il se vend chez un marchand, et son prix au dernier
-- releve de l'hotel des ventes.
-- ---------------------------------------------------------------------------

-- L'objet d'apres son nom : un produit de recette connue, un objet deja
-- releve a l'hotel des ventes, sinon ce que le jeu en sait.
function encheres.IdParNom(nom)
    if type(nom) ~= "string" or nom == "" then return nil end
    local bas = string.lower(nom)
    local function Pareil(objet)
        local n = NS.inventaire.NomDObjet(objet)
        return type(n) == "string" and string.lower(n) == bas
    end
    for _, r in pairs(NS.recettes and NS.recettes.Toutes() or {}) do
        if type(r) == "table" and r.objetProduit and Pareil(r.objetProduit) then return tonumber(r.objetProduit) end
    end
    for objet in pairs(Releves() or {}) do
        if Pareil(objet) then return tonumber(objet) end
    end
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    local _, lien = NS.Appeler(info, nom)
    local id = type(lien) == "string" and tonumber(string.match(lien, "item:(%d+)"))
    return id
end

-- { possede = texte, fabricants = { "Paltank (Ingenierie)" }, metier = nom,
--   marchand = bool, prix = cuivre, quand = date, absent = bool }
function encheres.Obtenir(objet, n)
    objet = tonumber(objet)
    if not objet then return nil end
    local r = {}
    if (NS.inventaire.TotalPossede(objet) or 0) > 0 then r.possede = NS.inventaire.TexteOuEst(objet) end
    r.fabricants = {}
    local vus = {}
    for _, rec in pairs(NS.recettes and NS.recettes.Toutes() or {}) do
        if type(rec) == "table" and tonumber(rec.objetProduit) == objet then
            local ligne = NS.recettes.MetierDe(rec)
            local metier = ligne and NS.recettes.NomDuMetier(ligne)
            r.metier = r.metier or metier
            for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
                if NS.inventaire.MemeCamp(fiche) and type(fiche.recettesApprises) == "table"
                    and fiche.recettesApprises[tostring(rec.id)] and not vus[fiche.cle] then
                    vus[fiche.cle] = true
                    table.insert(r.fabricants, NS.inventaire.NomCourt(fiche.cle) .. (metier and (" (" .. metier .. ")") or ""))
                end
            end
        end
    end
    r.marchand = marchands.Achetable(objet) and true or false
    r.prix, r.quand, r.absent = encheres.Prix(objet, n)
    return r
end

-- Les lignes pour une infobulle : { texte, r, g, b }.
function encheres.LignesObtenir(objet, n)
    local L = NS.L
    local o = encheres.Obtenir(objet, n)
    if not o then return { { L.OBTAIN_UNKNOWN, 0.6, 0.6, 0.6 } } end
    local lignes = {}
    if o.possede then table.insert(lignes, { string.format(L.OBTAIN_OWNED, o.possede), 0.31, 0.82, 0.41 }) end
    if #o.fabricants > 0 then
        table.insert(lignes, { string.format(L.OBTAIN_CRAFT, table.concat(o.fabricants, ", ")), 1, 1, 1 })
    elseif o.metier then
        table.insert(lignes, { string.format(L.OBTAIN_CRAFT_PROF, o.metier), 0.8, 0.8, 0.8 })
    end
    if o.marchand then table.insert(lignes, { L.OBTAIN_VENDOR, 1, 1, 1 }) end
    if o.prix then
        table.insert(lignes, { string.format(L.OBTAIN_AH, marchands.Monnaie(o.prix), encheres.DateDe(o.quand)), 1, 1, 1 })
    elseif o.quand then
        table.insert(lignes, { string.format(L.OBTAIN_AH_NONE, encheres.DateDe(o.quand)), 0.8, 0.8, 0.8 })
    else
        table.insert(lignes, { L.OBTAIN_AH_UNKNOWN, 0.6, 0.6, 0.6 })
    end
    return lignes
end

-- Le plus simple, en quelques mots, pour le guidage : en stock, a fabriquer
-- par qui, chez un marchand, sinon a l'hotel des ventes.
function encheres.ObtenirCourt(objet, n)
    local L = NS.L
    local o = encheres.Obtenir(objet, n)
    if not o then return L.OBTAIN_SHORT_AH end
    if o.possede then return string.format(L.OBTAIN_SHORT_OWNED, o.possede) end
    if #o.fabricants > 0 then return string.format(L.OBTAIN_SHORT_CRAFT, o.fabricants[1]) end
    if o.marchand then return L.OBTAIN_SHORT_VENDOR end
    return L.OBTAIN_SHORT_AH
end

_G.CraftCoreAPI.IdParNom = function(nom) return encheres.IdParNom(nom) end
_G.CraftCoreAPI.LignesObtenir = function(objet, nom, n)
    objet = tonumber(objet) or encheres.IdParNom(nom)
    return encheres.LignesObtenir(objet, n)
end
_G.CraftCoreAPI.ObtenirCourt = function(objet, nom, n)
    objet = tonumber(objet) or encheres.IdParNom(nom)
    return encheres.ObtenirCourt(objet, n)
end
