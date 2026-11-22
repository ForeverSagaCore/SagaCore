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

local function Relever()
    local prix = Base()
    local nombre = NS.Lecture("GetMerchantNumItems")
    local idDe = NS.Lecture("GetMerchantItemID")
    local infoDe = NS.Lecture("GetMerchantItemInfo")
    if not (prix and nombre and idDe and infoDe) then return end
    for i = 1, tonumber(NS.Appeler(nombre)) or 0 do
        local id = tonumber(NS.Appeler(idDe, i))
        local ok, _, _, cout, quantite, _, _, _, coutSpecial = pcall(infoDe, i)
        cout, quantite = tonumber(cout), tonumber(quantite)
        if ok and id and cout and cout > 0 and quantite and quantite > 0 and not coutSpecial then
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

-- La fleche de la suite jusqu'au marchand le plus proche, et le drapeau sur
-- la carte. Arrive : le guidage s'arrete et le drapeau s'en va.
function marchands.Guider(objet)
    local L = NS.L
    local S = NS.suite or _G.CoreSuite
    local cible = marchands.PlusProche(objet)
    if not cible then
        NS.Dire(string.format(L.VENDOR_NONE_HERE, NS.inventaire.NomDObjet(objet)))
        return false
    end
    if not (S and S.Guider) then return false end
    if NS.Trace then NS.Trace("guidage marchand : " .. tostring(objet)) end
    local point = { carte = cible.carte, x = cible.x, y = cible.y, titre = L.VENDOR_GUIDE_TITLE,
        qui = tostring(cible.nom or "?") .. "\n|cffb3b3b3" .. string.format(L.VENDOR_GUIDE_WHAT, NS.inventaire.NomDObjet(objet)) .. "|r" }
    S.Guider("CraftCore", {
        icone = "Interface\\Minimap\\Tracking\\Reagents",
        Cible = function() return point end,
        Arrivee = function()
            local apres = _G.C_Timer and _G.C_Timer.After
            if apres then apres(0, function() if S.ArreterGuidage then S.ArreterGuidage("CraftCore") end end) end
        end,
        Fin = function()
            OterDrapeau()
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
        end,
    })
    PoserDrapeau(cible)
    NS.Dire(string.format(L.VENDOR_GUIDING, tostring(cible.nom or "?"), NS.inventaire.NomDObjet(objet)))
    return true
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
    return liste
end

-- Combien il manque de chaque objet a relever (fabrications et progressions).
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
    cadreA:Hide()
    return cadreA
end

local enCours           -- le metier montre
local rappelLe = {}     -- dernier rappel, par metier (pres d'un maitre)

local function Montrer(m, pres)
    Construire()
    enCours = m
    local L = NS.L
    local icones = NS.ICONES_METIERS or {}
    cadreA.rond.icone:SetTexture(icones[m.ligne] or "Interface\\Icons\\INV_Misc_QuestionMark")
    cadreA.titre:SetText(string.format(L.RANK_MAX_TITLE, m.nom or "?", m.rang, m.rangMax))
    cadreA.texte:SetText(pres and string.format(L.RANK_MAX_NEAR, pres) or L.RANK_MAX_TEXT)
    cadreA.ok:SetText(L.RANK_MAX_OK)
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
local function LireMaitres()
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
local function MaitreProche(ligne, jx, jy, jc)
    for _, id in ipairs((maitres and maitres[ligne]) or {}) do
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
                local okP, nom = pcall(MaitreProche, m.ligne, jx, jy, jc)
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
