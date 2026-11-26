local _, NS = ...

-- Assistant de banque et de boite aux lettres.
--
-- A l'ouverture de la banque ou de la boite aux lettres, un panneau du jeu se
-- pose a cote de la fenetre et dit, pour le personnage connecte :
--   a la banque : ce qu'il faut sortir pour ses projets et pour ses envois ;
--   au courrier : ce qu'il faut envoyer a chacun de ses autres personnages,
--                 et ce qu'il doit leur demander.
-- Deux actions, toujours sur clic du joueur, jamais hors de sa vue :
--   Tout sortir : deplace de la banque vers les sacs ce qui est liste ;
--   Preparer l'envoi : ouvre l'onglet d'envoi, remplit le destinataire et
--   joint les objets. L'envoi lui-meme reste au joueur : CraftCore ne clique
--   jamais sur Envoyer.
-- Rien n'est montre quand il n'y a rien a faire.

NS.courrier = {}
local courrier = NS.courrier

local PAUSE = 0.3          -- entre deux deplacements : le jeu verrouille la case un instant
local PAUSE_PIECE = 0.15   -- entre deux pieces jointes : plus court (une case verrouillee est reessayee)
local LARGEUR = 300
-- Largeur utile d'une colonne du panneau (la barre de defilement gardee).
local COLONNE = LARGEUR - 2 * 12 - 10 - 22
-- Un peu plus large a l'hotel des ventes : la place des deux boutons de vente.
-- Plus large encore depuis l'onglet Rentabilite (sa colonne de prix et de
-- quantites) : la meme largeur pour tous les onglets, rien ne bouge.
local function LargeurDuLieu(l) return l == "encheres" and (LARGEUR + 170) or LARGEUR end
-- A l'hotel des ventes : deux onglets sur le bord droit, en bas : acheter
-- (prix, achats, fabrications) et vendre (ce qu'il y a dans mes sacs).
local function OngletHV()
    local g = NS.base.ReglagesGeneraux()
    if g.ongletHV == "vendre" or g.ongletHV == "recettes" or g.ongletHV == "rentable" then return g.ongletHV end
    return "acheter"
end
local choixRentables = {}  -- onglet Rentabilite : recettes cochees pour un projet commercial
local statut               -- resultat de la derniere action, montre dans le panneau
local statutManette        -- indication manette (X : action suivante)
local panneau
local lieu                 -- "banque" ou "courrier", nil quand rien n'est ouvert
local enCours = false

local function L() return NS.L end

local function Lire(nom) return NS.Lecture(nom) end

local function Nom(cle)
    return NS.inventaire.NomCourt(cle)
end

local function MemeCamp(a, b)
    return (not a.faction) or (not b.faction) or a.faction == b.faction
end

local function Ajout(table_, cle, valeur)
    if valeur and valeur > 0 then table_[cle] = (table_[cle] or 0) + valeur end
end

-- ---------------------------------------------------------------------------
-- Ce qu'il y a a faire
-- ---------------------------------------------------------------------------

-- Ce que les projets d'un personnage doivent rapatrier, et ce qu'ils prennent
-- dans ses propres stocks.
local function BesoinsDe(cle)
    return NS.base.AvecPersonnage(cle, function()
        local _, _, rapatries, pris = NS.projets.CalculerTout(
            NS.projets.StocksDuPersonnage(), NS.projets.StocksDesAutres())
        rapatries = rapatries or {}
        -- Les rangs vises (Monter un metier) sans projet : ce que la
        -- progression prend dans les stocks du compte et qui n'est pas chez
        -- lui se rapatrie aussi.
        local fiche = NS.base.FicheAffichee()
        local catalogue = NS.recettes
        if fiche and catalogue and catalogue.MetiersVises then
            local avecProjet = {}
            for _, projet in ipairs(NS.projets.Tous and NS.projets.Tous(false) or {}) do
                if projet.progression then avecProjet[tostring(projet.progression)] = true end
            end
            local chezLui = NS.projets.StocksDuPersonnage()
            local deja = {}
            for _, cleM in ipairs(catalogue.MetiersVises(fiche)) do
                local ligne = tonumber(cleM)
                local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(cleM)]
                if ligne and type(sien) == "table" and sien.rang and not avecProjet[tostring(cleM)] then
                    for _, seg in ipairs(catalogue.PlansVises(fiche, cleM, sien.rang, sien.rangMax)) do
                        for objet, n in pairs(seg.plan.utilises or {}) do
                            objet = tonumber(objet)
                            if objet then deja[objet] = (deja[objet] or 0) + (tonumber(n) or 0) end
                        end
                    end
                end
            end
            for objet, total in pairs(deja) do
                local manque = total - (chezLui[objet] or 0)
                if manque > 0 then rapatries[objet] = math.max(rapatries[objet] or 0, manque) end
            end
        end
        return rapatries, pris or {}
    end)
end

local function APasDeProjets(fiche)
    if type(fiche.rapides) == "table" and #fiche.rapides > 0 then return false end
    for _, projet in pairs(fiche.projets or {}) do
        if type(projet) == "table" and projet.statut ~= "archive" then return false end
    end
    return true
end

-- Envois deja partis, pas encore recus : { [cle] = { [objet] = n } }, par
-- personnage qui envoie. Retires du plan, pour que l'envoi ne soit pas
-- repropose ; une ligne s'efface quand le destinataire n'en a plus besoin
-- (il a ouvert son courrier) ou au bout de 30 jours (courrier renvoye).
local function EnRoute()
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.courrierEnRoute = type(d.courrierEnRoute) == "table" and d.courrierEnRoute or {}
    return d.courrierEnRoute
end
local function EnRoutePour(cle)
    local e = EnRoute()[cle]
    if type(e) ~= "table" then return {} end
    local maintenant = NS.Appeler(_G.time) or 0
    if (e.quand or 0) > 0 and maintenant - e.quand > 30 * 86400 then EnRoute()[cle] = nil return {} end
    return e.objets or {}
end

-- ---------------------------------------------------------------------------
-- Banquiers : des personnages qui gardent chacun une famille de composants
-- (herbes, metaux, etoffes...). A la boite aux lettres, chaque personnage
-- envoie au bon banquier ce qui ne lui sert pas ; un banquier range en
-- banque ce qui est a lui et ressort ce qui ne l'est pas. Un registre garde
-- ses mouvements de banque et ses depenses.
-- ---------------------------------------------------------------------------
NS.banquiers = {}
local bq = NS.banquiers

-- Le catalogue des specialites (classe:sous-classe d'objet du jeu). "reste" :
-- tout composant qu'aucun autre banquier ne prend. "vendus" : ce qui se vend
-- chez tous les marchands (fioles, fils, sel...).
bq.TYPES = {
    { cle = "reserve",  nom = "Mulgore",     icone = "Interface\\Icons\\INV_Misc_Bag_10", reste = true },
    { cle = "herbes",   nom = "Fleuralas",   icone = "Interface\\Icons\\INV_Misc_Herb_07", classes = { "7:9" } },
    { cle = "metaux",   nom = "Lingotar",    icone = "Interface\\Icons\\INV_Ingot_03", classes = { "7:7", "7:1", "7:2", "7:3", "7:4" } },
    { cle = "etoffes",  nom = "Tannaris",    icone = "Interface\\Icons\\INV_Fabric_Linen_01", classes = { "7:5", "7:6" } },
    { cle = "cuisine",  nom = "Gargotzan",   icone = "Interface\\Icons\\INV_Misc_Food_15", classes = { "7:8" } },
    { cle = "enchant",  nom = "Azsharme",    icone = "Interface\\Icons\\INV_Enchant_DustStrange", classes = { "7:12", "7:10" } },
    { cle = "marchand", nom = "Plandrassil", icone = "Interface\\Icons\\INV_Scroll_03", classes = { "9", "5" }, vendus = true },
}
bq.PAR_CLE = {}
for _, t in ipairs(bq.TYPES) do bq.PAR_CLE[t.cle] = t end

local function DonneesBq()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.banquiers = type(d.banquiers) == "table" and d.banquiers or {}
    d.registre = type(d.registre) == "table" and d.registre or {}
    return d
end

-- Le nom de famille commun, ajoute au nom affiche.
function bq.Famille()
    local d = DonneesBq()
    return d and type(d.banquiersFamille) == "string" and d.banquiersFamille or "des Sept Nains"
end

-- La specialite d'un objet, d'apres sa classe dans le jeu ; nil : ce n'est
-- pas un composant (equipement, quete...), aucun banquier ne le prend.
function bq.TypeDe(objet)
    objet = tonumber(objet)
    if not objet then return nil end
    if NS.recettes and NS.recettes.EstVenduPartout and NS.recettes.EstVenduPartout(objet) then return "marchand" end
    local lecture = NS.jeu and NS.jeu.infoObjetImmediate
    if not lecture then return nil end
    local ok, _, _, _, _, _, classe, sous = pcall(lecture, objet)
    classe, sous = tonumber(classe), tonumber(sous)
    if not (ok and classe) then return nil end
    local avec, seule = classe .. ":" .. tostring(sous), tostring(classe)
    for _, t in ipairs(bq.TYPES) do
        for _, c in ipairs(t.classes or {}) do
            if c == avec or c == seule then return t.cle end
        end
    end
    if classe == 7 then return "reserve" end
    return nil
end

-- Les banquiers, dans l'ordre ou ils ont ete nommes.
function bq.Liste()
    local d = DonneesBq()
    local liste = {}
    if not d then return liste end
    local fiches = {}
    for _, f in ipairs(NS.base.TousLesPersonnages()) do fiches[f.cle] = f end
    for cle, b in pairs(d.banquiers) do
        if type(b) == "table" and fiches[cle] then
            table.insert(liste, { cle = cle, fiche = fiches[cle], types = type(b.types) == "table" and b.types or {}, ordre = b.ordre or 0 })
        end
    end
    table.sort(liste, function(a, b) return a.ordre < b.ordre end)
    return liste
end
function bq.Est(cle)
    local d = DonneesBq()
    return d and type(d.banquiers[cle]) == "table" or false
end
function bq.Nommer(cle)
    local d = DonneesBq()
    if not d or not cle or d.banquiers[cle] then return end
    local n = 0
    for _, b in pairs(d.banquiers) do if type(b) == "table" and (b.ordre or 0) > n then n = b.ordre end end
    -- Le premier banquier garde tout ; les suivants, rien tant qu'on ne
    -- leur a pas choisi de specialite.
    d.banquiers[cle] = { ordre = n + 1, types = next(d.banquiers) == nil and { reserve = true } or {} }
end
function bq.Retirer(cle)
    local d = DonneesBq()
    if d then d.banquiers[cle] = nil end
end
function bq.Basculer(cle, typ)
    local d = DonneesBq()
    local b = d and d.banquiers[cle]
    if type(b) ~= "table" then return end
    b.types = type(b.types) == "table" and b.types or {}
    b.types[typ] = (not b.types[typ]) or nil
end

-- Le banquier d'un objet : celui de sa specialite, sinon celui de la
-- reserve. nil : aucun banquier ne le prend.
function bq.Pour(objet)
    local typ = bq.TypeDe(objet)
    if not typ then return nil end
    local reserve
    for _, b in ipairs(bq.Liste()) do
        if b.types[typ] then return b.cle end
        if b.types.reserve and not reserve then reserve = b.cle end
    end
    return reserve
end

-- Registre : les mouvements et les depenses d'un banquier, les plus recents
-- d'abord (300 au plus).
function bq.Noter(cle, genre, objet, n, cuivre)
    local d = DonneesBq()
    if not (d and cle and bq.Est(cle)) then return end
    d.registre[cle] = type(d.registre[cle]) == "table" and d.registre[cle] or {}
    local r = d.registre[cle]
    table.insert(r, 1, { quand = NS.Appeler(_G.time) or 0, genre = genre, objet = objet, n = n, cuivre = cuivre })
    while #r > 300 do table.remove(r) end
end
function bq.Registre(cle)
    local d = DonneesBq()
    return d and type(d.registre[cle]) == "table" and d.registre[cle] or {}
end

-- La banque d'un personnage, objet par objet, telle que vue la derniere fois.
function bq.Banque(fiche)
    local t = {}
    if type(fiche) ~= "table" then return t end
    local conteneurs = NS.base.ConteneursDe(fiche)
    for objet, ligne in pairs(NS.base.StocksDe(fiche) or {}) do
        for id, q in pairs(type(ligne) == "table" and ligne.parConteneur or {}) do
            local fc = conteneurs[id]
            if fc and fc.source == "banque" then
                local o = tonumber(objet)
                if o then t[o] = (t[o] or 0) + (tonumber(q) or 0) end
            end
        end
    end
    return t
end

-- Apres un releve, banque ouverte : ce qui est entre ou sorti de la banque
-- du banquier connecte va au registre.
function bq.ApresReleve(banqueOuverte)
    if not banqueOuverte then return end
    local moi = NS.base.Personnage()
    if not (moi and bq.Est(moi.cle)) then return end
    local d = DonneesBq()
    d.banqueVue = type(d.banqueVue) == "table" and d.banqueVue or {}
    local avant = d.banqueVue[moi.cle]
    local maintenant = bq.Banque(moi)
    if type(avant) == "table" then
        local vus = {}
        for objet, n in pairs(maintenant) do
            vus[objet] = true
            local ecart = n - (avant[objet] or 0)
            if ecart > 0 then bq.Noter(moi.cle, "depot", objet, ecart) elseif ecart < 0 then bq.Noter(moi.cle, "retrait", objet, -ecart) end
        end
        for objet, n in pairs(avant) do
            if not vus[objet] and n > 0 then bq.Noter(moi.cle, "retrait", objet, n) end
        end
    end
    d.banqueVue[moi.cle] = maintenant
end

-- Les depenses et les recettes d'un banquier chez un marchand ou a l'hotel
-- des ventes (l'or gagne ou perdu pendant que la fenetre est ouverte).
do
    local f = CreateFrame("Frame")
    local chez, argent
    local function Argent() return tonumber(NS.Appeler(_G.GetMoney)) or 0 end
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_MONEY" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, e)
        if e == "MERCHANT_SHOW" then chez, argent = "marchand", Argent()
        elseif e == "AUCTION_HOUSE_SHOW" then chez, argent = "hv", Argent()
        elseif e == "MERCHANT_CLOSED" or e == "AUCTION_HOUSE_CLOSED" then chez = nil
        elseif e == "PLAYER_MONEY" and chez and argent then
            local now = Argent()
            local ecart = now - argent
            argent = now
            local moi = NS.base.Personnage()
            if moi and ecart ~= 0 then
                pcall(bq.Noter, moi.cle, (ecart < 0 and "achat_" or "vente_") .. chez, nil, nil, math.abs(ecart))
            end
        end
    end)
end

function courrier.Plan()
    local moi = NS.base.Personnage()
    if not moi then return nil end
    local plan = { envois = {}, demandes = {}, sortir = {} }

    -- Mes propres besoins passent avant tout envoi : ce que mes projets et
    -- mes rangs vises prennent chez moi n'est jamais propose a un autre
    -- personnage, ni a un banquier (sinon il faudrait le redemander ensuite).
    local mesBesoins = {}
    do
        local okB, _, prisB = pcall(BesoinsDe, moi.cle)
        if okB and type(prisB) == "table" then for objet, q in pairs(prisB) do Ajout(mesBesoins, objet, q) end end
        local okO, objectifsB = pcall(NS.recettes.BesoinsDesObjectifs, moi)
        if okO and type(objectifsB) == "table" then for objet, q in pairs(objectifsB) do Ajout(mesBesoins, objet, q) end end
    end
    local function ADonner(objet, dejaPris)
        local sacs, banque = NS.inventaire.SacsEtBanque(moi, objet)
        return math.max(0, (sacs or 0) + (banque or 0) - (mesBesoins[objet] or 0) - (dejaPris or 0))
    end

    -- Ce que chacun de mes autres personnages attend, et que je detiens.
    local dansMesSacsPourEnvoi = {}
    for _, autre in ipairs(NS.base.TousLesPersonnages()) do
        if autre.cle ~= moi.cle and MemeCamp(moi, autre) and not APasDeProjets(autre) then
            local ok, rapatries = pcall(BesoinsDe, autre.cle)
            if ok then
                local lignes = {}
                local enRoute = EnRoutePour(autre.cle)
                -- Le destinataire s'est connecte depuis l'envoi et n'en a plus
                -- besoin : il a ouvert son courrier, on oublie la ligne.
                local e = EnRoute()[autre.cle]
                local releve = NS.base.ReleveDe(autre)
                if e and e.horodatage and releve and tostring(releve) > tostring(e.horodatage) then
                    for objet in pairs(enRoute) do
                        if not rapatries[objet] or rapatries[objet] <= 0 then enRoute[objet] = nil end
                    end
                end
                for objet, besoin in pairs(rapatries) do
                    local quantite = besoin - (enRoute[objet] or 0)
                    local sacs = NS.inventaire.SacsEtBanque(moi, objet)
                    local donner = math.min(quantite, ADonner(objet, dansMesSacsPourEnvoi[objet]))
                    if donner > 0 then
                        table.insert(lignes, { objet = objet, quantite = donner, enBanque = math.max(0, donner - sacs) })
                        Ajout(dansMesSacsPourEnvoi, objet, donner)
                    end
                end
                if #lignes > 0 then
                    table.sort(lignes, function(a, b) return a.quantite > b.quantite end)
                    table.insert(plan.envois, { cle = autre.cle, nom = Nom(autre.cle), lignes = lignes })
                end
            end
        end
    end

    -- Les caisses de mes autres personnages. Une caisse se remplit avec UN
    -- pack de sa liste, au choix : on retient le pack que je peux completer
    -- en envoyant le moins, et seulement s'il devient complet.
    local disponible = {}
    local function Dispo(objet)
        if disponible[objet] == nil then
            disponible[objet] = ADonner(objet, dansMesSacsPourEnvoi[objet])
        end
        return disponible[objet]
    end
    if NS.caisses and NS.caisses.Connues then
        for _, autre in ipairs(NS.base.TousLesPersonnages()) do
            if autre.cle ~= moi.cle and MemeCamp(moi, autre) then
                local ajouts = {}
                local okC, liste = pcall(NS.caisses.Connues, autre.cle, false)
                for _, caisse in ipairs(okC and liste or {}) do
                    local meilleur
                    for _, pack in ipairs(NS.caisses.Etat(caisse)) do
                        if pack.objet and pack.requis and pack.requis > 0 then
                            local n = caisse.exemplaires or 1
                            local lui = (pack.possede or 0) + (EnRoutePour(autre.cle)[pack.objet] or 0)
                            local complets = math.min(n, math.floor((lui + math.max(0, Dispo(pack.objet))) / pack.requis))
                            local envoyer = math.max(0, complets * pack.requis - lui)
                            if complets > 0 and envoyer > 0 and (not meilleur or envoyer < meilleur.quantite) then
                                meilleur = { objet = pack.objet, quantite = envoyer, caisse = caisse.nom }
                            end
                        end
                    end
                    if meilleur then
                        disponible[meilleur.objet] = Dispo(meilleur.objet) - meilleur.quantite
                        Ajout(dansMesSacsPourEnvoi, meilleur.objet, meilleur.quantite)
                        table.insert(ajouts, meilleur)
                    end
                end
                if #ajouts > 0 then
                    local envoi
                    for _, e in ipairs(plan.envois) do if e.cle == autre.cle then envoi = e break end end
                    if not envoi then
                        envoi = { cle = autre.cle, nom = Nom(autre.cle), lignes = {} }
                        table.insert(plan.envois, envoi)
                    end
                    for _, a in ipairs(ajouts) do
                        local sacs = NS.inventaire.SacsEtBanque(moi, a.objet)
                        table.insert(envoi.lignes, { objet = a.objet, quantite = a.quantite,
                            enBanque = math.max(0, a.quantite - sacs), caisse = a.caisse })
                    end
                end
            end
        end
    end

    -- Les commandes fabriquees ici, a envoyer a leur demandeur.
    if NS.commandes then
        for dest, objets in pairs(NS.commandes.AEnvoyer(moi.cle)) do
            local envoi
            for _, e in ipairs(plan.envois) do if e.cle == dest then envoi = e break end end
            if not envoi then
                envoi = { cle = dest, nom = Nom(dest), lignes = {} }
                table.insert(plan.envois, envoi)
            end
            for _, o in ipairs(objets) do
                local sacs, banque = NS.inventaire.SacsEtBanque(moi, o.objet)
                local donner = math.min(o.quantite, (sacs or 0) + (banque or 0))
                if donner > 0 then
                    table.insert(envoi.lignes, 1, { objet = o.objet, quantite = donner,
                        enBanque = math.max(0, donner - (sacs or 0)), commande = true })
                    Ajout(dansMesSacsPourEnvoi, o.objet, donner)
                end
            end
            if #envoi.lignes == 0 then
                for k = #plan.envois, 1, -1 do if plan.envois[k] == envoi then table.remove(plan.envois, k) end end
            end
        end
    end

    -- Ce que mes projets prennent chez moi, et ce que je dois demander.
    local okMoi, rapatries, pris = pcall(BesoinsDe, moi.cle)
    if okMoi then
        for objet, quantite in pairs(rapatries) do
            local _, detail = NS.inventaire.DetailChezLesAutres(moi, objet)
            local reste = quantite
            for _, chez in ipairs(detail) do
                if reste <= 0 then break end
                local part = math.min(reste, chez.sacs + chez.banque)
                if part > 0 then
                    table.insert(plan.demandes, { objet = objet, quantite = part, chez = Nom(chez.cle) })
                    reste = reste - part
                end
            end
        end
        -- A sortir de la banque : ce que mes projets et mes envois prennent,
        -- moins ce qui est deja dans mes sacs.
        local besoinEnSacs = {}
        for objet, quantite in pairs(pris) do Ajout(besoinEnSacs, objet, quantite) end
        for objet, quantite in pairs(dansMesSacsPourEnvoi) do Ajout(besoinEnSacs, objet, quantite) end
        -- Les rangs vises (Monter un metier) : leurs composants sortent aussi.
        local okObj, objectifs = pcall(NS.recettes.BesoinsDesObjectifs, moi)
        if okObj then for objet, quantite in pairs(objectifs) do Ajout(besoinEnSacs, objet, quantite) end end
        plan.garder = besoinEnSacs
        for objet, quantite in pairs(besoinEnSacs) do
            local sacs, banque = NS.inventaire.SacsEtBanque(moi, objet)
            local sortir = math.min(banque, math.max(0, quantite - sacs))
            if sortir > 0 then table.insert(plan.sortir, { objet = objet, quantite = sortir }) end
        end
    end
    -- Les banquiers : ce qui ne sert pas ici part chez le banquier de sa
    -- specialite ; un banquier ressort ce qui n'est pas a lui.
    if NS.banquiers.AjouterEnvois then
        local okB, souciB = pcall(NS.banquiers.AjouterEnvois, plan, moi)
        if not okB then NS.base.NoterIncident("banquiers", souciB) end
    end
    table.sort(plan.demandes, function(a, b) return a.quantite > b.quantite end)
    table.sort(plan.sortir, function(a, b) return a.quantite > b.quantite end)
    table.sort(plan.envois, function(a, b) return a.nom < b.nom end)
    return plan
end

-- ---------------------------------------------------------------------------
-- Deplacer des objets
-- ---------------------------------------------------------------------------

local function Conteneur(nom) return Lire("C_Container." .. nom) or Lire(nom) end

local function ContenuDe(id, emplacement)
    local info = NS.Appeler(Conteneur("GetContainerItemInfo"), id, emplacement)
    local objet = NS.Appeler(Conteneur("GetContainerItemID"), id, emplacement)
    if not objet then return nil end
    local nombre, verrou = 1, false
    if type(info) == "table" then
        nombre = tonumber(info.stackCount) or 1
        verrou = info.isLocked and true or false
    end
    return objet, nombre, verrou
end

local function NombreDEmplacements(id)
    return tonumber(NS.Appeler(Conteneur("GetContainerNumSlots"), id)) or 0
end

-- Sacs du personnage connecte : tous ceux que le releve connait hors banque,
-- y compris un sac au-dela du quatrieme (celui des composants). Ne compter que
-- les sacs 0 a 4 faisait ignorer ce qui y etait range.
local function TousLesSacs()
    local liste, vus = {}, {}
    local moi = NS.base.Personnage()
    for id, fc in pairs(NS.base.ConteneursDe(moi) or {}) do
        local n = tonumber(id)
        if n and n >= 0 and not vus[n] and type(fc) == "table" and fc.source ~= "banque" then
            vus[n] = true
            table.insert(liste, n)
        end
    end
    local dernier = (tonumber(_G.NUM_BAG_SLOTS) or 4) + (tonumber(_G.NUM_REAGENTBAG_SLOTS) or 0)
    for id = 0, dernier do
        if not vus[id] then vus[id] = true table.insert(liste, id) end
    end
    table.sort(liste)
    return liste
end

-- Sacs ordinaires, pour y deposer : un sac specialise refuse la plupart des
-- objets, on ne le vise pas comme destination.
local function SacsOrdinaires()
    local liste = {}
    local libres = Conteneur("GetContainerNumFreeSlots")
    for _, id in ipairs(TousLesSacs()) do
        local _, famille = NS.Appeler(libres, id)
        local reactif = id > (tonumber(_G.NUM_BAG_SLOTS) or 4)
        if not reactif and (famille == nil or famille == 0) then table.insert(liste, id) end
    end
    return liste
end

local function ConteneursDeBanque()
    local liste = {}
    for id in pairs(NS.base.Decouverte().conteneursDeBanque or {}) do
        local n = tonumber(id)
        if n then table.insert(liste, n) end
    end
    table.sort(liste)
    return liste
end

-- Banquiers : les envois vers chacun, d'apres les sacs tels qu'ils sont
-- (jamais un objet lie, qui ne peut pas partir par courrier).
function bq.AjouterEnvois(plan, moi)
    local liste = bq.Liste()
    if #liste == 0 or not moi then return end
    local garder = plan.garder or {}
    local prevus = {}
    for _, e in ipairs(plan.envois) do
        for _, l in ipairs(e.lignes) do prevus[l.objet] = (prevus[l.objet] or 0) + (l.quantite or 0) end
    end
    local dispo = {}
    for _, id in ipairs(TousLesSacs()) do
        for emplacement = 1, NombreDEmplacements(id) do
            local info = NS.Appeler(Conteneur("GetContainerItemInfo"), id, emplacement)
            local objet = type(info) == "table" and tonumber(info.itemID)
            if objet and not info.isBound then dispo[objet] = (dispo[objet] or 0) + (tonumber(info.stackCount) or 1) end
        end
    end
    local function EnvoiPour(cle)
        for _, e in ipairs(plan.envois) do if e.cle == cle then return e end end
        local e = { cle = cle, nom = Nom(cle), lignes = {}, banquier = true }
        table.insert(plan.envois, e)
        return e
    end
    -- Ce que le personnage utilise lui-meme ne part jamais chez un
    -- banquier : munitions (fleches, balles), carquois, consommables
    -- (nourriture, boissons, potions, parchemins).
    local instantane = Lire("C_Item.GetItemInfoInstant") or Lire("GetItemInfoInstant")
    local GARDES = { [0] = true, [6] = true, [11] = true }
    local function Utilise(objet)
        if not instantane then return false end
        local ok, _, _, _, _, _, classe = pcall(instantane, objet)
        return ok and GARDES[tonumber(classe) or -1] or false
    end
    for objet, n in pairs(dispo) do
        local dest = not Utilise(objet) and bq.Pour(objet)
        if dest and dest ~= moi.cle then
            local reste = n - (garder[objet] or 0) - (prevus[objet] or 0)
            if reste > 0 then
                table.insert(EnvoiPour(dest).lignes, { objet = objet, quantite = reste, enBanque = 0, banquier = true })
            end
        end
    end
    -- Un banquier ressort de sa banque ce qui revient a un autre banquier.
    if bq.Est(moi.cle) then
        local deja = {}
        for _, l in ipairs(plan.sortir) do deja[l.objet] = true end
        for objet, n in pairs(bq.Banque(moi)) do
            local dest = bq.Pour(objet)
            if dest and dest ~= moi.cle and not deja[objet] and n > 0 then
                table.insert(plan.sortir, { objet = objet, quantite = n, banquier = true })
            end
        end
    end
end
function bq.EstAMoi(objet)
    local moi = NS.base.Personnage()
    return moi and bq.Est(moi.cle) and bq.Pour(objet) == moi.cle or false
end

-- Un sac specialise (composants, herbes, minerais...) qui accepte cet
-- objet : par la famille de l'objet, ou, pour le sac de composants, parce
-- que c'est un composant d'artisanat.
local function Accepte(id, objet)
    local _, famille = NS.Appeler(Conteneur("GetContainerNumFreeSlots"), id)
    famille = tonumber(famille) or 0
    local reactif = id > (tonumber(_G.NUM_BAG_SLOTS) or 4) and id <= (tonumber(_G.NUM_BAG_SLOTS) or 4) + (tonumber(_G.NUM_REAGENTBAG_SLOTS) or 0)
    if reactif then
        local info = { NS.Appeler(Lire("C_Item.GetItemInfo") or Lire("GetItemInfo"), objet) }
        return info[17] == true
    end
    if famille == 0 then return false end
    local f = tonumber(NS.Appeler(Lire("C_Item.GetItemFamily") or Lire("GetItemFamily"), objet)) or 0
    local et = Lire("bit.band")
    return f > 0 and et and NS.Appeler(et, f, famille) ~= 0 or false
end
local function SacsSpecialises(objet)
    local liste = {}
    if not objet then return liste end
    for _, id in ipairs(TousLesSacs()) do
        if NombreDEmplacements(id) > 0 and Accepte(id, objet) then table.insert(liste, id) end
    end
    return liste
end

-- Une case libre : d'abord dans un sac specialise qui accepte l'objet,
-- sinon dans un sac ordinaire.
local function CaseLibre(reservees, objet)
    for _, id in ipairs(SacsSpecialises(objet)) do
        for emplacement = 1, NombreDEmplacements(id) do
            local cle = id .. ":" .. emplacement
            if not reservees[cle] and not ContenuDe(id, emplacement) then
                reservees[cle] = true
                return id, emplacement
            end
        end
    end
    for _, id in ipairs(SacsOrdinaires()) do
        for emplacement = 1, NombreDEmplacements(id) do
            local cle = id .. ":" .. emplacement
            if not reservees[cle] and not ContenuDe(id, emplacement) then
                reservees[cle] = true
                return id, emplacement
            end
        end
    end
    return nil
end

-- Prend `quantite` d'un objet dans une case de `sources` et le met sur le
-- curseur. Rend la quantite prise, 0 si rien n'est disponible maintenant.
local function Prendre(sources, objet, quantite)
    for _, id in ipairs(sources) do
        for emplacement = 1, NombreDEmplacements(id) do
            local present, nombre, verrou = ContenuDe(id, emplacement)
            if present == objet and not verrou then
                local part = math.min(nombre, quantite)
                if part < nombre then
                    NS.Appeler(Conteneur("SplitContainerItem"), id, emplacement, part)
                else
                    NS.Appeler(Conteneur("PickupContainerItem"), id, emplacement)
                end
                return part
            end
        end
    end
    return 0
end

local function CurseurPlein()
    local f = Lire("CursorHasItem")
    return f and NS.Appeler(f) and true or false
end

local function Lacher()
    local f = Lire("ClearCursor")
    if f then NS.Appeler(f) end
end

-- Execute les etapes une par une, avec une pause entre deux : chaque objet
-- deplace verrouille sa case le temps que le serveur reponde.
local function Enchainer(etapes, fin, pause)
    enCours = true
    local plusTard = Lire("C_Timer.After")
    local rang = 0
    local function Suivante()
        rang = rang + 1
        local etape = etapes[rang]
        if not etape then
            enCours = false
            if fin then fin() end
            return
        end
        local ok, continuer = pcall(etape)
        if not ok or continuer == false then
            Lacher()
            enCours = false
            if fin then fin(not ok and continuer or nil) end
            return
        end
        -- Etape sans deplacement ("vite") : pas de pause, on enchaine.
        if continuer == "vite" or not plusTard then Suivante() else NS.Appeler(plusTard, pause or PAUSE, Suivante) end
    end
    Suivante()
end

local function EnCombat()
    local f = Lire("InCombatLockdown")
    return f and NS.Appeler(f) and true or false
end

local function ToutSortir()
    if enCours or lieu ~= "banque" then return end
    if EnCombat() then NS.Dire(L().ASSIST_COMBAT) return end
    local plan = courrier.Plan()
    if not plan then return end
    local banque = ConteneursDeBanque()
    local reservees, etapes, piles = {}, {}, 0
    for _, ligne in ipairs(plan.sortir) do
        local reste = ligne.quantite
        -- Une etape par pile deplacee ; le nombre de piles se decouvre en route.
        for _ = 1, 40 do
            table.insert(etapes, function()
                if reste <= 0 then return "vite" end
                local bac, case = CaseLibre(reservees, ligne.objet)
                if not bac then NS.Dire(L().ASSIST_NO_ROOM) return false end
                local part = Prendre(banque, ligne.objet, reste)
                if part == 0 then reste = 0 return "vite" end
                NS.Appeler(Conteneur("PickupContainerItem"), bac, case)
                if CurseurPlein() then return false end
                reste = reste - part
                piles = piles + 1
                return true
            end)
        end
    end
    Enchainer(etapes, function(souci)
        if souci then NS.base.NoterIncident("sortie de banque", souci) end
        statut = string.format(L().ASSIST_TAKEN, piles)
        NS.Dire(statut)
        courrier.Actualiser()
    end)
end

local function PreparerEnvoi(envoi)
    if enCours or lieu ~= "courrier" or not envoi then return end
    if EnCombat() then NS.Dire(L().ASSIST_COMBAT) return end
    local joindre = Lire("ClickSendMailItemButton")
    local pieceJointe = Lire("GetSendMailItem")
    if not joindre then return end

    -- Onglet d'envoi, destinataire, objet du courrier.
    if _G.MailFrameTab2 and _G.MailFrameTab2.Click then pcall(_G.MailFrameTab2.Click, _G.MailFrameTab2) end
    -- Le champ du destinataire n'a pas le meme nom selon les versions du
    -- jeu : on cherche le premier qui existe, et on le remplit comme si on
    -- l'avait tape (le jeu verifie le nom a la saisie).
    local function Champ(noms)
        for _, chemin in ipairs(noms) do
            local c = _G
            for morceau in string.gmatch(chemin, "[^%.]+") do c = type(c) == "table" and c[morceau] or nil end
            if type(c) == "table" and c.SetText then return c end
        end
        return nil
    end
    local function Remplir(champ, texte)
        if not champ then return end
        pcall(champ.SetText, champ, texte)
        if champ.SetCursorPosition then pcall(champ.SetCursorPosition, champ, #texte) end
        local quandChange = champ.GetScript and champ:GetScript("OnTextChanged")
        if quandChange then pcall(quandChange, champ, true) end
    end
    Remplir(Champ({ "SendMailNameEditBox", "SendMailFrame.SendMailNameEditBox", "SendMailFrame.NameEditBox" }), envoi.nom)
    Remplir(Champ({ "SendMailSubjectEditBox", "SendMailFrame.SendMailSubjectEditBox", "SendMailFrame.SubjectEditBox" }), L().ASSIST_SUBJECT)

    local maximum = tonumber(_G.ATTACHMENTS_MAX_SEND) or 12
    local function CaseDePieceLibre()
        for i = 1, maximum do
            if not pieceJointe or not NS.Appeler(pieceJointe, i) then return i end
        end
        return nil
    end

    local sacs = TousLesSacs()
    local etapes, jointes = {}, 0
    local nonJoints = {}
    for _, ligne in ipairs(envoi.lignes) do
        local reste = ligne.quantite - (ligne.enBanque or 0)
        if not courrier.ObjetEnvoye(envoi, ligne.objet) then reste = 0 end
        local essais = 0
        for _ = 1, 16 do
            table.insert(etapes, function()
                -- Ligne finie : les pas restants passent sans attendre (avant,
                -- chacun attendait sa pause : 16 pauses par objet).
                if reste <= 0 then return "vite" end
                local case = CaseDePieceLibre()
                if not case then NS.Dire(L().ASSIST_MAIL_FULL) return false end
                local part = Prendre(sacs, ligne.objet, reste)
                if part == 0 then
                    -- Case encore verrouillee par le deplacement d'avant : on
                    -- reessaie au pas suivant, six fois au plus.
                    essais = essais + 1
                    if essais >= 6 then nonJoints[ligne.objet] = reste reste = 0 end
                    return true
                end
                NS.Appeler(joindre, case)
                if CurseurPlein() then
                    -- Piece refusee : l'objet retourne dans son sac, on continue.
                    Lacher()
                    essais = essais + 1
                    if essais >= 6 then nonJoints[ligne.objet] = reste reste = 0 end
                    return true
                end
                reste = reste - part
                jointes = jointes + 1
                return true
            end)
        end
        if (ligne.enBanque or 0) > 0 and courrier.ObjetEnvoye(envoi, ligne.objet) then nonJoints[ligne.objet] = (nonJoints[ligne.objet] or 0) + ligne.enBanque end
    end
    Enchainer(etapes, function(souci)
        if souci then NS.base.NoterIncident("preparation d'envoi", souci) end
        if jointes == 0 then
            statut = L().ASSIST_NOTHING_IN_BAGS
        else
            statut = string.format(L().ASSIST_PREPARED, envoi.nom, jointes)
        end
        -- Ce qui n'a pas pu partir, et pourquoi (en banque, ou introuvable).
        local manque = {}
        for objet, n in pairs(nonJoints) do
            table.insert(manque, NS.inventaire.NomDObjet(objet) .. " x" .. n)
        end
        if #manque > 0 then statut = statut .. " " .. string.format(L().ASSIST_NOT_ATTACHED, table.concat(manque, ", ")) end
        NS.Dire(statut)
        courrier.Actualiser()
    end, PAUSE_PIECE)
end

-- ---------------------------------------------------------------------------
-- Chez un marchand : ce que mes objectifs demandent d'acheter et qu'il vend
-- (fioles, plans...), a la quantite exacte qui manque dans les sacs. L'achat
-- se fait sur clic, un lot apres l'autre, en recomptant les sacs a chaque fois.
-- ---------------------------------------------------------------------------

local function BesoinsDAchat()
    -- Ce qui manque encore a chaque objectif (matieres, achats compris), et
    -- les plans a apprendre maintenant pas encore en main.
    local besoins = {}
    local ok, objectifs = pcall(NS.suivi.Objectifs)
    for _, o in ipairs(ok and objectifs or {}) do
        for _, m in ipairs(o.matieres or {}) do
            local objet = tonumber(m.objet)
            if objet and (m.manque or 0) > 0 then besoins[objet] = (besoins[objet] or 0) + m.manque end
        end
        for _, a in ipairs(o.aApprendre or {}) do
            if not a.appris and not a.plusTard then
                local okO, plan = pcall(NS.recettes.ObjetDuPlan, a.recette)
                local okP, _, possede = pcall(NS.recettes.PlanPossede, a.recette)
                plan = okO and tonumber(plan)
                if plan and not (okP and possede) then besoins[plan] = math.max(besoins[plan] or 0, 1) end
            end
        end
    end
    return besoins
end

-- { { index, objet, reste (objets), lot (objets par achat), prix (par lot) } }
function courrier.AchatsMarchand()
    local liste = {}
    local nombre, idDe = Lire("GetMerchantNumItems"), Lire("GetMerchantItemID")
    local infoDe = NS.marchands.InfoArticle
    if not (nombre and idDe) then return liste end
    local besoins = BesoinsDAchat()
    for i = 1, tonumber(NS.Appeler(nombre)) or 0 do
        local objet = tonumber(NS.Appeler(idDe, i))
        local besoin = objet and besoins[objet]
        if besoin and besoin > 0 then
            local prix, lot, dispo, achetable, coutSpecial = infoDe(i)
            prix, lot = tonumber(prix), math.max(1, tonumber(lot) or 1)
            if prix and prix > 0 and not coutSpecial and achetable ~= false then
                local reste = besoin
                if reste > 0 then
                    table.insert(liste, { index = i, objet = objet, reste = reste, lot = lot, prix = prix,
                        lots = math.ceil(reste / lot), dispo = tonumber(dispo) })
                end
            end
        end
    end
    return liste
end

local achatEnCours = false
function courrier.Acheter(lignes)
    if achatEnCours or lieu ~= "marchand" then return end
    if EnCombat() then NS.Dire(L().ASSIST_COMBAT) return end
    local acheter = Lire("BuyMerchantItem")
    local plusTard = Lire("C_Timer.After")
    if not (acheter and plusTard) then return end
    -- Un lot a la fois : file des achats a faire.
    -- Vendu a l'unite : par piles entieres (le maximum que le jeu accepte
    -- d'un coup) ; vendu par lots : un lot a la fois.
    local file = {}
    local pileMax = Lire("GetMerchantItemMaxStack")
    for _, l in ipairs(lignes) do
        if l.lot == 1 then
            local maxi = math.max(1, tonumber(pileMax and NS.Appeler(pileMax, l.index)) or 1)
            local reste = l.lots
            while reste > 0 do
                local q = math.min(reste, maxi)
                table.insert(file, { index = l.index, q = q, prix = l.prix * q })
                reste = reste - q
            end
        else
            -- Comme un clic sur l'article : un lot entier, sans quantite.
            for _ = 1, l.lots do table.insert(file, { index = l.index, lot = l.lot, prix = l.prix }) end
        end
    end
    if #file == 0 then return end
    achatEnCours = true
    local faits = 0
    local function Suivant()
        local l = table.remove(file, 1)
        if not l or lieu ~= "marchand" then
            achatEnCours = false
            NS.Dire(string.format(L().MERCHANT_BOUGHT or "%d", faits))
            courrier.Actualiser()
            return
        end
        if (tonumber(NS.Appeler(_G.GetMoney)) or 0) < l.prix then
            file = {}
            NS.Dire(L().MERCHANT_NO_MONEY or "")
        else
            if l.lot then
                NS.Appeler(acheter, l.index)
                faits = faits + l.lot
            else
                NS.Appeler(acheter, l.index, l.q)
                faits = faits + l.q
            end
        end
        NS.Appeler(plusTard, 0.25, Suivant)
    end
    Suivant()
    courrier.Actualiser()
end

do
    local attente = false
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, e)
        if e == "MERCHANT_SHOW" then courrier.Ouvert("marchand")
        elseif e == "MERCHANT_CLOSED" then courrier.Ferme("marchand")
        elseif lieu == "marchand" and not achatEnCours then
            -- Le marchand envoie ses mises a jour en rafale (stocks, objets
            -- qui finissent de charger) : un seul recalcul, une demi-seconde
            -- apres la derniere, au lieu d'un par evenement.
            if attente then return end
            local plusTard = Lire("C_Timer.After")
            if not plusTard then courrier.Actualiser() return end
            attente = true
            NS.Appeler(plusTard, 0.5, function()
                attente = false
                if lieu == "marchand" and not achatEnCours then courrier.Actualiser() end
            end)
        end
    end)
end

-- Completer les piles : ce que j'ai dans mes sacs et qui est deja en banque
-- (sauf ce que mes projets me font sortir). Un objet par ligne, avec la
-- quantite dans les sacs ; choisi par defaut.
local pilesChoisies = {}

-- Envoi a un autre personnage : chaque objet est coche par defaut ; decoche,
-- il ne se joint pas (le temps de la session).
local envoiExclus = {}
local function CleEnvoi(envoi, objet) return tostring(envoi and envoi.cle) .. ":" .. tostring(objet) end
function courrier.ObjetEnvoye(envoi, objet) return envoiExclus[CleEnvoi(envoi, objet)] ~= true end
function courrier.ChoisirObjetEnvoye(envoi, objet, oui)
    if oui then envoiExclus[CleEnvoi(envoi, objet)] = nil else envoiExclus[CleEnvoi(envoi, objet)] = true end
end
function courrier.PilesACompleter(plan)
    local enBanque = {}
    for _, id in ipairs(ConteneursDeBanque()) do
        for emplacement = 1, NombreDEmplacements(id) do
            local objet = ContenuDe(id, emplacement)
            if objet then enBanque[objet] = true end
        end
    end
    -- Jamais ce que mes projets ou mes envois demandent d'avoir en sacs :
    -- on vient de le sortir pour fabriquer, on ne le propose pas de le ranger.
    local aSortir = {}
    for _, l in ipairs(plan and plan.sortir or {}) do aSortir[l.objet] = true end
    for objet in pairs(plan and plan.garder or {}) do aSortir[objet] = true end
    local parObjet, liste = {}, {}
    for _, id in ipairs(TousLesSacs()) do
        for emplacement = 1, NombreDEmplacements(id) do
            local objet, nombre = ContenuDe(id, emplacement)
            if objet and (enBanque[objet] or bq.EstAMoi(objet)) and not aSortir[objet] then
                if not parObjet[objet] then
                    parObjet[objet] = { objet = objet, quantite = 0 }
                    table.insert(liste, parObjet[objet])
                end
                parObjet[objet].quantite = parObjet[objet].quantite + (nombre or 1)
            end
        end
    end
    table.sort(liste, function(a, b) return a.quantite > b.quantite end)
    return liste
end
function courrier.PileChoisie(objet) return pilesChoisies[objet] ~= false end
-- (Coche : retirer la marque ; decoche : la poser. "oui and nil or false"
-- donnait toujours false : une case decochee ne se recochait plus.)
function courrier.ChoisirPile(objet, oui)
    if oui then pilesChoisies[objet] = nil else pilesChoisies[objet] = false end
end

-- Range en banque, case par case, ce qui est choisi : le jeu complete les
-- piles deja en banque (comme un clic droit sur l'objet, banque ouverte).
local function RangerLesPiles()
    if enCours or lieu ~= "banque" then return end
    if EnCombat() then NS.Dire(L().ASSIST_COMBAT) return end
    local utiliser = Conteneur("UseContainerItem")
    if not utiliser then return end
    local liste = courrier.PilesACompleter(courrier.Plan())
    local choisis = {}
    for _, l in ipairs(liste) do if courrier.PileChoisie(l.objet) then choisis[l.objet] = true end end
    local etapes, rangees = {}, 0
    for _, id in ipairs(TousLesSacs()) do
        for emplacement = 1, NombreDEmplacements(id) do
            local bac, case = id, emplacement
            local present = ContenuDe(bac, case)
            if present and choisis[present] then table.insert(etapes, function()
                local objet, _, verrou = ContenuDe(bac, case)
                if objet and choisis[objet] and not verrou then
                    NS.Appeler(utiliser, bac, case)
                    rangees = rangees + 1
                end
                return true
            end) end
        end
    end
    Enchainer(etapes, function(souci)
        if souci then NS.base.NoterIncident("ranger en banque", souci) end
        statut = string.format(L().ASSIST_STACKED, rangees)
        NS.Dire(statut)
        courrier.Actualiser()
    end)
end
function courrier.RangerLesPiles()
    local ok, souci = pcall(RangerLesPiles)
    if not ok then enCours = false NS.base.NoterIncident("ranger en banque", souci) end
end

-- Sous filet : une erreur est notee dans les incidents au lieu de rester muette.
function courrier.ToutSortir()
    local ok, souci = pcall(ToutSortir)
    if not ok then enCours = false Lacher() NS.base.NoterIncident("sortie de banque", souci) end
end

-- Choisir le bouton ou la case suivant / precedent du panneau (manette).
function courrier.Deplacer(pas)
    local liste = panneau and panneau.elements or {}
    if #liste < 2 then return end
    local rang = 1
    for k, e in ipairs(liste) do if e == panneau.choix then rang = k end end
    rang = ((rang - 1 + pas) % #liste) + 1
    courrier.focusCle = liste[rang].cle
    if liste[rang].envoi then courrier.envoiChoisi = liste[rang].envoi end
    if courrier.Actualiser then courrier.Actualiser() end
end

function courrier.PreparerEnvoi(envoi)
    local ok, souci = pcall(PreparerEnvoi, envoi)
    if not ok then enCours = false Lacher() NS.base.NoterIncident("preparation d'envoi", souci) end
end

-- ---------------------------------------------------------------------------
-- Panneau
-- ---------------------------------------------------------------------------
--
-- A cote de la fenetre du jeu, aligne sur son bas, jamais dessous : sous la
-- fenetre se trouvent ses onglets et, a la manette, la barre des boutons.
--   banque   : a droite de la banque, apres ses onglets lateraux ; seulement
--              ce qu'il faut en sortir ;
--   courrier : a droite de la boite aux lettres, seulement sur l'onglet
--              d'envoi.
-- Il se ferme avec la fenetre qu'il accompagne.
-- A la manette, le curseur du jeu clique ses boutons comme les autres : le
-- panneau ne prend aucun bouton de la manette pour lui.

local HAUT_DU_CONTENU = 24 + 12  -- barre de titre, puis la marge de la charte
local BAS_DU_CONTENU = 12 + 4
local LIGNES_MAX = 500            -- tout est montre ; le panneau defile au besoin
-- Fenetres du jeu que le panneau accompagne, selon le lieu, et l'ecart a
-- laisser a leur droite (la banque a des onglets lateraux).
local FENETRES = {
    banque = { "BankFrame", "BankPanel", "AccountBankPanel", "BankSlotsFrame", "ReagentBankFrame" },
    courrier = { "MailFrame", "OpenMailFrame" },
    encheres = { "AuctionHouseFrame" },
    marchand = { "MerchantFrame" },
}
local ECART = { banque = 48, courrier = 8, encheres = 8, marchand = 8 }

local function Construire()
    -- La charte commune, sans portrait ni pied : un panneau.
    local cadre = NS.charte.Fenetre("CraftCoreAssistant", LARGEUR, 100,
        { portrait = false, deplacable = false, strate = "MEDIUM", sansPied = true })
    if cadre.titre then cadre.titre:SetText("CraftCore") end
    -- Le contenu defile quand il depasse la hauteur du panneau (toute la
    -- hauteur de l'hotel des ventes, ou celle de la fenetre accompagnee).
    local defil = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
    defil:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    defil:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    local contenu = CreateFrame("Frame", nil, defil)
    -- La place de la barre de defilement est toujours gardee : rien ne bouge
    -- quand elle apparait.
    contenu:SetSize(LARGEUR - 2 * NS.charte.MARGE - 10 - 22, 1)
    defil:SetScrollChild(contenu)
    cadre.defil = defil
    cadre.contenu = contenu
    cadre.textes, cadre.icones, cadre.boutons = {}, {}, {}
    -- A la banque : le fond cuir de la banque du jeu, en mosaique.
    local cuir = cadre:CreateTexture(nil, "BACKGROUND", nil, 7)
    cuir:SetAllPoints(cadre.fond)
    cuir:SetTexture("Interface\\BankFrame\\Bank-Background", "REPEAT", "REPEAT")
    if cuir.SetHorizTile then cuir:SetHorizTile(true) cuir:SetVertTile(true) end
    cuir:Hide()
    cadre.cuir = cuir
    -- Panneau ferme : la touche A rend sa place au jeu.

    cadre:Hide()
    -- Le double carre de la manette entre dans le panneau.
    local S = NS.suite or _G.CoreSuite
    if S and S.ToucheDEntree then S.ToucheDEntree(cadre, "CraftCoreAssistant") end
    -- Ferme, il rend Y et X au jeu ; en combat, des la fin du combat.
    cadre:HookScript("OnHide", function() if courrier.LierManette then courrier.LierManette(false) end end)
    pcall(cadre.RegisterEvent, cadre, "PLAYER_REGEN_ENABLED")
    cadre:HookScript("OnEvent", function(self, e)
        if e == "PLAYER_REGEN_ENABLED" and not self:IsShown() and courrier.LierManette then courrier.LierManette(false) end
    end)
    return cadre
end

local function Texte(rang, police)
    local t = panneau.textes[rang]
    if not t then
        t = panneau.contenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        panneau.textes[rang] = t
    end
    t:SetFontObject(police or "GameFontHighlightSmall")
    t:SetWordWrap(false)
    t:Show()
    return t
end

local function Icone(rang)
    local i = panneau.icones[rang]
    if not i then
        i = panneau.contenu:CreateTexture(nil, "ARTWORK")
        i:SetSize(16, 16)
        panneau.icones[rang] = i
    end
    i:Show()
    return i
end

local function Case(rang)
    panneau.cases = panneau.cases or {}
    local c = panneau.cases[rang]
    if not c then
        c = CreateFrame("CheckButton", nil, panneau.contenu, "UICheckButtonTemplate")
        c:SetSize(20, 20)
        panneau.cases[rang] = c
    end
    c:Show()
    return c
end

local function Bouton(rang)
    local b = panneau.boutons[rang]
    if not b then
        -- Nomme : la touche de la manette le declenche par son nom.
        b = CreateFrame("Button", "CraftCoreAssistantBouton" .. rang, panneau.contenu, "UIPanelButtonTemplate")
        b:SetSize(170, 22)
        panneau.boutons[rang] = b
    end
    b:Show()
    return b
end

-- Touche Y de la manette sur la premiere action du panneau (Tout sortir,
-- Preparer l'envoi), le temps que le panneau est ouvert. Une liaison
-- prioritaire, retiree des que le panneau se ferme ; jamais en combat.
-- Plus aucune touche prise par le panneau : modifier les liaisons de touches
-- pendant que la manette du jeu est active derangeait sa gestion des touches
-- (actions bloquees par le jeu, jusqu'a ne plus pouvoir quitter). Le curseur
-- de la manette du jeu clique les boutons du panneau comme les autres.
function courrier.ToucheManette() return false end

-- La touche passe par un bouton cache, inscrit pour l'appui : le jeu
-- declenche une touche liee a l'appui, et un bouton du jeu qui n'ecoute que le
-- relachement (comme ceux du panneau) ne recevait rien.
local relaisManette
local function Relais()
    if relaisManette then return relaisManette end
    relaisManette = CreateFrame("Button", "CraftCoreAssistantManette", UIParent)
    relaisManette:Hide()
    pcall(relaisManette.RegisterForClicks, relaisManette, "AnyDown", "AnyUp")
    local dernier = -1
    relaisManette:SetScript("OnClick", function()
        -- Appui et relachement : une seule action.
        local maintenant = NS.Appeler(_G.GetTime) or 0
        if maintenant - dernier < 0.4 then return end
        dernier = maintenant
        local b = panneau and panneau.choix and panneau.choix.cadre
        if b and b:IsShown() and b:IsEnabled() then b:Click("LeftButton") end
    end)
    return relaisManette
end

local relaisSuivant
local function RelaisSuivant()
    if relaisSuivant then return relaisSuivant end
    relaisSuivant = CreateFrame("Button", "CraftCoreAssistantSuivant", UIParent)
    relaisSuivant:Hide()
    pcall(relaisSuivant.RegisterForClicks, relaisSuivant, "AnyDown", "AnyUp")
    local dernier = -1
    relaisSuivant:SetScript("OnClick", function()
        local maintenant = NS.Appeler(_G.GetTime) or 0
        if maintenant - dernier < 0.4 then return end
        dernier = maintenant
        courrier.Deplacer(1)
    end)
    return relaisSuivant
end

local function LierManette(actif)
    if not panneau then return end
    if NS.Appeler(NS.Lecture("InCombatLockdown")) then return end
    -- Toujours repartir de zero : sans cela Y et X restaient pris par le
    -- panneau apres la fermeture de l'hotel des ventes, de la banque ou du
    -- courrier, et ne repondaient plus en jeu.
    pcall(_G.ClearOverrideBindings, panneau)
    if actif and courrier.ToucheManette() and #(panneau.elements or {}) > 0 then
        Relais()
        RelaisSuivant()
        -- Y, pas A : A reste au jeu pour prendre et poser les objets de la
        -- banque et des sacs.
        pcall(_G.SetOverrideBindingClick, panneau, true, "PAD4", "CraftCoreAssistantManette", "LeftButton")
        -- X : l'action suivante du panneau (d'un envoi a l'autre).
        if #(panneau.elements or {}) > 1 then
            pcall(_G.SetOverrideBindingClick, panneau, true, "PAD3", "CraftCoreAssistantSuivant", "LeftButton")
        end
        -- Plus de LB / RB : Y fait l'action principale (le premier bouton du
        -- panneau) ; les cases et les autres boutons se touchent au curseur.

    end
end
courrier.LierManette = LierManette

-- ConsolePort prend la touche A pour son curseur quand la banque s'ouvre, et
-- peut passer apres nous : la liaison est reposee un peu plus tard, et le
-- panneau est donne a son curseur, qui peut alors y aller.
local function LierManetteBientot(actif)
    LierManette(actif)
    if not actif then return end
    local CP = _G.ConsolePort
    if panneau and type(CP) == "table" and type(CP.AddInterfaceCursorFrame) == "function" and not panneau.dansConsolePort then
        panneau.dansConsolePort = pcall(CP.AddInterfaceCursorFrame, CP, panneau)
    end
    if _G.C_Timer and _G.C_Timer.After then
        for _, delai in ipairs({ 0.3, 1 }) do
            _G.C_Timer.After(delai, function()
                if panneau and panneau:IsShown() then LierManette(true) end
            end)
        end
    end
end

local function Remplir(plan)
    for _, t in ipairs(panneau.textes) do t:Hide() end
    for _, i in ipairs(panneau.icones) do i:Hide() end
    for _, b in ipairs(panneau.boutons) do b:Hide() end
    for _, c in ipairs(panneau.cases or {}) do c:Hide() end
    for _, v in ipairs(panneau.ventes or {}) do v:Hide() end
    if panneau.trait then panneau.trait:Hide() end
    local y, nt, ni, nb, nc = 0, 0, 0, 0, 0
    -- x0 : le bord gauche de la colonne en cours (deux colonnes a l'hotel
    -- des ventes : acheter a gauche, vendre a droite).
    local x0 = 0
    local largeur = COLONNE + (LargeurDuLieu(lieu) - LARGEUR)

    local function Titre(texte)
        nt = nt + 1
        local t = Texte(nt, "GameFontNormal")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -y)
        t:SetWidth(largeur)
        t:SetText(texte)
        y = y + 18
    end
    local function Ligne(objet, droite)
        ni, nt = ni + 1, nt + 1
        local icone = Icone(ni)
        icone:ClearAllPoints()
        icone:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 2, -y)
        icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local t = Texte(nt)
        t:ClearAllPoints()
        t:SetPoint("LEFT", icone, "RIGHT", 6, 0)
        t:SetWidth(largeur - 26)
        t:SetText(NS.inventaire.NomDObjet(objet) .. "  |cffffffff" .. droite .. "|r")
        y = y + 18
    end
    local function Reste(nombre)
        nt = nt + 1
        local t = Texte(nt, "GameFontDisableSmall")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 24, -y)
        t:SetWidth(largeur - 24)
        t:SetText(string.format(L().ASSIST_MORE, nombre))
        y = y + 16
    end
    local function Lignes(liste, texteDe)
        for rang, l in ipairs(liste) do
            if rang > LIGNES_MAX then Reste(#liste - LIGNES_MAX) break end
            Ligne(l.objet, texteDe(l))
        end
    end
    -- Ce qui se choisit a la manette (LB / RB) et se declenche par Y : les
    -- boutons et les cases, dans l'ordre du panneau.
    local elements = {}
    -- Y ne vise que les boutons d'action, jamais les cases : la premiere
    -- action du panneau (Tout sortir, Ranger, Preparer l'envoi).
    local function Choisissable(cadre, cle)
        if cadre:IsObjectType("CheckButton") then return end
        table.insert(elements, { cadre = cadre, cle = cle })
    end

    local function Action(libelle, auClic, cle)
        nb = nb + 1
        local b = Bouton(nb)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -(y + 4))
        b.libelle = libelle
        b:SetText(libelle)
        b:SetAlpha(1)
        b:UnlockHighlight()
        Choisissable(b, cle or ("action:" .. (string.gsub(libelle, "%d", ""))))
        -- Toute la largeur du panneau : le texte (icone de la manette et
        -- nombre compris) y tient toujours, et les boutons s'alignent.
        b:SetWidth(largeur)
        b:SetScript("OnClick", auClic)
        b:SetEnabled(not enCours)
        y = y + 32
    end

    -- Une ligne d'objet avec un petit bouton a droite : le nom s'arrete
    -- avant le bouton, jamais par-dessus.
    local function LigneAvecBouton(objet, droite, libelle, auClic)
        ni, nt, nb = ni + 1, nt + 1, nb + 1
        local icone = Icone(ni)
        icone:ClearAllPoints()
        icone:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 2, -(y + 3))
        icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local b = Bouton(nb)
        b:ClearAllPoints()
        b:SetSize(76, 20)
        b:SetPoint("TOPRIGHT", panneau.contenu, "TOPLEFT", x0 + largeur, -y)
        b.libelle = libelle
        b:SetText(libelle)
        b:SetAlpha(1)
        b:UnlockHighlight()
        b:SetScript("OnClick", auClic)
        b:SetEnabled(not enCours)
        Choisissable(b, "ligne:" .. tostring(objet))
        local t = Texte(nt)
        t:ClearAllPoints()
        t:SetPoint("LEFT", icone, "RIGHT", 6, 0)
        t:SetWidth(largeur - 26 - 82)
        t:SetText(NS.inventaire.NomDObjet(objet) .. "  |cffffffff" .. droite .. "|r")
        y = y + 24
    end

    -- Une ligne a vendre : toute la ligne se clique (souris ou manette) et
    -- met l'objet en vente dans la fenetre du jeu.
    local nv = 0
    local function LigneVente(v)
        nv = nv + 1
        panneau.ventes = panneau.ventes or {}
        local l = panneau.ventes[nv]
        if not l then
            l = CreateFrame("Button", "CraftCoreAssistantVente" .. nv, panneau.contenu)
            l:SetHeight(20)
            l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            l.icone = l:CreateTexture(nil, "ARTWORK")
            l.icone:SetSize(16, 16)
            l.icone:SetPoint("LEFT", l, "LEFT", 2, 0)
            -- Deux petits boutons au bout de la ligne : Voir (apercu de la
            -- vente, a valider) et Vendre (vente directe).
            l.vendre = CreateFrame("Button", "CraftCoreAssistantVendre" .. nv, l, "UIPanelButtonTemplate")
            l.vendre:SetSize(52, 18)
            l.vendre:SetPoint("RIGHT", l, "RIGHT", 0, 0)
            l.voir = CreateFrame("Button", "CraftCoreAssistantVoir" .. nv, l, "UIPanelButtonTemplate")
            l.voir:SetSize(64, 18)
            l.voir:SetPoint("RIGHT", l.vendre, "LEFT", -2, 0)
            -- Texte des petits boutons a la taille du texte des lignes.
            for _, bt in ipairs({ l.voir, l.vendre }) do
                pcall(bt.SetNormalFontObject, bt, "GameFontNormalSmall")
                pcall(bt.SetHighlightFontObject, bt, "GameFontHighlightSmall")
                pcall(bt.SetDisabledFontObject, bt, "GameFontDisableSmall")
            end
            l.prix = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l.prix:SetPoint("RIGHT", l.voir, "LEFT", -6, 0)
            l.prix:SetJustifyH("RIGHT")
            l.prix:SetWordWrap(false)
            l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
            l.nom:SetPoint("RIGHT", l.prix, "LEFT", -6, 0)
            l.nom:SetJustifyH("LEFT")
            l.nom:SetWordWrap(false)
            panneau.ventes[nv] = l
        end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0, -y)
        l:SetWidth(largeur)
        l.icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, v.objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
        l.nom:SetText(NS.inventaire.NomDObjet(v.objet) .. (v.nombre > 1 and ("  |cffb3b3b3x" .. v.nombre .. "|r") or ""))
        local prixV = NS.encheres.PrixDeVente(v.objet)
        if prixV then
            -- Le total d'abord (ce que rapporte la pile), l'unite en gris.
            -- Le prix a l'unite en gris clair, puis le total.
            l.prix:SetText((v.nombre > 1 and ("|cffb3b3b3" .. NS.marchands.Monnaie(prixV) .. "|r   ") or "")
                .. NS.marchands.Monnaie(prixV * v.nombre))
        elseif v.marchand and v.marchand > 0 then
            l.prix:SetText("|cff8c8c8c" .. string.format(L().AH_SELL_VENDOR, NS.marchands.Monnaie(v.marchand)) .. "|r")
        else
            l.prix:SetText("|cff8c8c8c" .. L().AH_NEVER .. "|r")
        end
        l.prix:SetWidth(math.min(150, (l.prix:GetStringWidth() or 60) + 4))
        local vv = v
        -- La ligne : rien a cliquer (le survol montre l'objet) ; le bouton vend.
        l:SetScript("OnClick", nil)
        local prixVente = NS.encheres.PrixDeVente(v.objet)
        l.vendre:SetText(L().AH_SELL_BUTTON)
        l.vendre:SetEnabled(prixVente ~= nil and not enCours)
        if l.vendre.SetMotionScriptsWhileDisabled then pcall(l.vendre.SetMotionScriptsWhileDisabled, l.vendre, true) end
        l.vendre:SetScript("OnClick", function()
            local ok, detail = NS.encheres.Vendre(vv)
            if ok then
                statut = string.format(L().AH_SOLD, NS.inventaire.NomDObjet(vv.objet), NS.marchands.Monnaie(detail))
            else
                statut = L().AH_SELL_FAIL
            end
            courrier.Actualiser()
        end)
        l.vendre:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if prixVente then
                GameTooltip:SetText(string.format(L().AH_SELL_AT, vv.nombre, NS.marchands.Monnaie(prixVente)), 1, 1, 1, 1, true)
            else
                GameTooltip:SetText(L().AH_SELL_NEED_SCAN, 1, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        l.vendre:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l.voir:SetText(L().AH_PREVIEW_BUTTON)
        l.voir:SetEnabled(prixVente ~= nil and not enCours)
        -- Preparer : la vente se pose dans la fenetre de l'hotel des ventes ;
        -- on y regle la quantite et on valide soi-meme.
        l.voir:SetScript("OnClick", function()
            if NS.encheres.PreparerVente(vv) then
                statut = string.format(L().AH_SELL_PREPARED, NS.inventaire.NomDObjet(vv.objet))
            else
                statut = L().AH_SELL_FAIL
            end
            courrier.Actualiser()
        end)
        l.voir:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L().AH_PREVIEW_TIP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        l.voir:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, vv.objet) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L().AH_SELL_TIP, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l:Show()

        y = y + 20
    end

    -- Une ligne avec sa case a cocher (completer les piles).
    local function LigneACocher(objet, droite, coche, auClic)
        nc, nt = nc + 1, nt + 1
        local c = Case(nc)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + -2, -(y - 2))
        if coche == nil then coche = courrier.PileChoisie(objet) end
        c:SetChecked(coche)
        c:UnlockHighlight()
        Choisissable(c, "pile:" .. tostring(objet))
        c:SetScript("OnClick", function(self)
            if auClic then auClic(self:GetChecked() and true or false)
            else courrier.ChoisirPile(objet, self:GetChecked() and true or false) end
            courrier.Actualiser()
        end)
        ni = ni + 1
        local icone = Icone(ni)
        icone:ClearAllPoints()
        icone:SetPoint("LEFT", c, "RIGHT", 2, 0)
        icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local t = Texte(nt)
        t:ClearAllPoints()
        t:SetPoint("LEFT", icone, "RIGHT", 6, 0)
        t:SetWidth(largeur - 48)
        t:SetText(NS.inventaire.NomDObjet(objet) .. "  |cffffffff" .. droite .. "|r")
        y = y + 20
    end

    local vide = true
    if lieu == "banque" and #plan.sortir > 0 then
        vide = false
        Titre(L().ASSIST_TAKE_TITLE)
        Lignes(plan.sortir, function(l) return "x" .. l.quantite end)
        if Lire("C_Container.PickupContainerItem") or Lire("PickupContainerItem") then
            Action(L().ASSIST_TAKE_ALL, courrier.ToutSortir)
        end
    end
    if lieu == "banque" then
        local okP, piles = pcall(courrier.PilesACompleter, plan)
        if okP and piles and #piles > 0 then
            if not vide then y = y + 6 end
            vide = false
            Titre(L().ASSIST_STACK_TITLE)
            local n = 0
            for rang, l in ipairs(piles) do
                if rang > 12 then Reste(#piles - 12) break end
                LigneACocher(l.objet, "x" .. l.quantite)
            end
            for _, l in ipairs(piles) do if courrier.PileChoisie(l.objet) then n = n + 1 end end
            if Lire("C_Container.UseContainerItem") or Lire("UseContainerItem") then
                Action(string.format(L().ASSIST_STACK_DO, n), courrier.RangerLesPiles)
                if n == 0 then panneau.boutons[nb]:SetEnabled(false) end
            end
        end
    elseif lieu == "courrier" then
        -- Seul ce qui est dans les sacs se joint ; ce qui est en banque est
        -- indique a cote, a sortir a la prochaine visite. Un envoi sans rien
        -- dans les sacs ne se prepare pas. Plusieurs envois : on choisit
        -- lequel (clic, ou LB / RB a la manette), Y le prepare.
        local preparables = {}
        for _, envoi in ipairs(plan.envois) do
            local enSacs = 0
            local coches = 0
            for _, l in ipairs(envoi.lignes) do
                local n = math.max(0, l.quantite - (l.enBanque or 0))
                enSacs = enSacs + n
                if courrier.ObjetEnvoye(envoi, l.objet) then coches = coches + n end
            end
            envoi.enSacs = enSacs
            envoi.coches = coches
            if enSacs > 0 then table.insert(preparables, envoi) end
        end
        local cleChoisie = courrier.envoiChoisi
        local choisi
        for _, e in ipairs(preparables) do if e.cle == cleChoisie then choisi = e end end
        choisi = choisi or preparables[1]
        courrier.envoiChoisi = choisi and choisi.cle or nil
        courrier.preparables = preparables
        for rang, envoi in ipairs(plan.envois) do
            if rang > 1 then y = y + 6 end
            vide = false
            local estChoisi = (envoi == choisi)
            Titre(string.format(L().ASSIST_SEND_TO, envoi.nom))
            local titre = panneau.textes[nt]
            if titre and #preparables > 1 and not estChoisi then titre:SetFontObject("GameFontDisable") end
            -- Chaque objet a joindre : une case, cochee par defaut ; decochee,
            -- l'objet reste dans les sacs.
            for _, l in ipairs(envoi.lignes) do
                local enSacs = math.max(0, l.quantite - (l.enBanque or 0))
                local droite = enSacs > 0 and ("x" .. enSacs) or ""
                if (l.enBanque or 0) > 0 then
                    droite = droite .. (enSacs > 0 and "  " or "") .. "|cff8c8c8c" .. string.format(L().ASSIST_ALSO_BANK, l.enBanque) .. "|r"
                end
                if l.caisse then droite = droite .. "  |cff8c8c8c" .. L().ASSIST_FOR_CRATE .. "|r" end
                if l.commande then droite = droite .. "  |cff8c8c8c" .. L().ASSIST_FOR_ORDER .. "|r" end
                if enSacs > 0 then
                    local e, objet = envoi, l.objet
                    LigneACocher(objet, droite, courrier.ObjetEnvoye(e, objet), function(oui) courrier.ChoisirObjetEnvoye(e, objet, oui) end)
                else
                    Ligne(l.objet, droite)
                end
            end
            if envoi.enSacs > 0 and Lire("ClickSendMailItemButton") then
                local e = envoi
                Action(L().ASSIST_PREPARE, function()
                    courrier.envoiChoisi = e.cle
                    courrier.PreparerEnvoi(e)
                end, "envoi:" .. tostring(e.cle))
                elements[#elements].envoi = e.cle
                if (envoi.coches or 0) == 0 then panneau.boutons[nb]:SetEnabled(false) end
                if #preparables > 1 and not estChoisi then panneau.boutons[nb]:SetAlpha(0.6) end
            elseif envoi.enSacs == 0 then
                nt = nt + 1
                local t = Texte(nt, "GameFontDisableSmall")
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -y)
                t:SetWidth(largeur)
                t:SetText(L().ASSIST_NOTHING_IN_BAGS)
                y = y + 16
            end
        end
        if #plan.demandes > 0 then
            if not vide then y = y + 6 end
            vide = false
            Titre(L().ASSIST_ASK_TITLE)
            Lignes(plan.demandes, function(l)
                return "x" .. l.quantite .. "  " .. string.format(L().ASSIST_FROM, l.chez)
            end)
        end
    end
    if lieu == "encheres" and NS.encheres and NS.encheres.Disponible() and OngletHV() == "acheter" then
        -- Hotel des ventes : le releve des prix de ce qui manque.
        vide = false
        local objets = NS.encheres.ObjetsARelever()
        -- Les releves en haut, sous la main : ce qui manque, puis ce qu'on
        -- peut fabriquer.
        if NS.encheres.EnCours() then
            local r, total = NS.encheres.Avancement()
            Action(string.format(L().AH_SCANNING, math.min(r, total), total), function() end)
            panneau.boutons[nb]:SetEnabled(false)
        else
            if #objets > 0 then
                Action(string.format(L().AH_SCAN, #objets), function()
                    statut = nil
                    NS.encheres.Relever()
                    courrier.Actualiser()
                end)
            end
            -- Le releve de mes fabrications est dans l'onglet Rentabilite.
        end
        Titre(L().AH_TITLE)
        if #objets == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_NOTHING)
            y = y + 16
        else
            local liste = {}
            for _, objet in ipairs(objets) do table.insert(liste, { objet = objet }) end
            Lignes(liste, function(l)
                local enRoute = NS.encheres.EnRoute and NS.encheres.EnRoute(l.objet) or 0
                if enRoute > 0 then return "|cff4fd16a" .. string.format(L().AH_IN_MAIL or "%d", enRoute) .. "|r" end
                local prix, quand, absent = NS.encheres.Prix(l.objet, 1)
                if prix then return string.format(L().AH_UNIT, NS.marchands.Monnaie(prix)) .. "  |cff8c8c8c" .. NS.encheres.DateDe(quand) .. "|r" end
                if absent then return "|cff8c8c8c" .. string.format(L().AH_ABSENT, NS.encheres.DateDe(quand)) .. "|r" end
                return "|cff8c8c8c" .. L().AH_NEVER .. "|r"
            end)
            -- A acheter : un bouton par objet qui manque, qui le cherche dans
            -- l'hotel des ventes. L'achat reste a faire soi-meme.
            local manques = NS.encheres.Manques and NS.encheres.Manques() or {}
            local aChercher = {}
            for _, objet in ipairs(objets) do
                if (manques[objet] or 0) > 0 then table.insert(aChercher, objet) end
            end
            if #aChercher > 0 then
                y = y + 4
                Titre(L().AH_BUY_TITLE)
                for k, objet in ipairs(aChercher) do
                    local o = objet
                    LigneAvecBouton(o, string.format(L().AH_MISSING, manques[o]), L().AH_FIND_SHORT, function()
                        NS.encheres.Chercher(o)
                    end)
                end
            end
        end

    end
    if lieu == "encheres" and NS.encheres and NS.encheres.Disponible() and OngletHV() == "rentable" then
        -- Onglet Rentabilite : tout ce que je sais fabriquer, ce qui rapporte
        -- le plus d'abord, avec ce que je peux deja faire. On coche ce qui
        -- interesse : un projet commercial se cree dans Mes fabrications.
        vide = false
        local okT, toutes = pcall(NS.encheres.ToutesMesFabrications)
        toutes = okT and toutes or {}
        local coches = {}
        for _, f in ipairs(toutes) do if choixRentables[tostring(f.recette.id)] then table.insert(coches, f) end end
        if NS.encheres.EnCours() then
            local r, total = NS.encheres.Avancement()
            Action(string.format(L().AH_SCANNING, math.min(r, total), total), function() end)
            panneau.boutons[nb]:SetEnabled(false)
        else
            local aRelever = NS.encheres.ObjetsDeToutesMesFabrications()
            if #aRelever > 0 then
                Action(string.format(L().AH_SCAN_CRAFTS, #aRelever), function()
                    statut = nil
                    NS.encheres.Relever(aRelever)
                    courrier.Actualiser()
                end)
            end
        end
        Action(string.format(L().AH_TRADE_PROJECT or "%d", #coches), function()
            if #coches == 0 then return end
            local n = 1
            for _, p in ipairs(NS.projets.Tous and NS.projets.Tous(true) or {}) do if p.commercial then n = n + 1 end end
            local projet = NS.projets.Creer(string.format(L().AH_TRADE_NAME or "%d", n))
            if not projet then return end
            projet.commercial = true
            for _, f in ipairs(coches) do NS.projets.Ajouter(projet.id, f.recette.id, 1) end
            for k in pairs(choixRentables) do choixRentables[k] = nil end
            statut = string.format(L().AH_TRADE_DONE or "%s", NS.projets.NomDe(projet))
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
            if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
            courrier.Actualiser()
        end, "projetCommercial")
        panneau.boutons[nb]:SetEnabled(#coches > 0)
        Titre(L().AH_TRADE_TITLE or "")
        if #toutes == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_TRADE_NONE or "")
            y = y + 16
        else
            for _, f in ipairs(toutes) do
                local droite
                if f.rapporte then
                    droite = NS.marchands.Monnaie(f.rapporte)
                    if f.benefice then
                        local signe = f.benefice >= 0 and "|cff4fd16a+" or "|cffff6060-"
                        droite = droite .. "  " .. signe .. NS.marchands.Monnaie(math.abs(f.benefice)) .. "|r"
                    end
                else
                    droite = "|cff8c8c8c" .. (L().AH_NEVER or "") .. "|r"
                end
                droite = droite .. "  " .. (f.n > 0 and "|cffffffff" or "|cff8c8c8c") .. string.format(L().AH_TRADE_CAN or "(%d)", f.n) .. "|r"
                local id = tostring(f.recette.id)
                LigneACocher(f.recette.objetProduit, droite, choixRentables[id] == true, function(oui)
                    choixRentables[id] = oui or nil
                end)
            end
        end
    end
    if lieu == "encheres" and NS.encheres and NS.encheres.Disponible() and OngletHV() == "vendre" then
        -- Onglet Vendre : ce que j'ai dans mes sacs et qui peut se vendre.
        vide = false
        local okV, aVendre = pcall(NS.encheres.AVendre)
        aVendre = okV and aVendre or {}
        -- Le prix de ce qui n'a pas encore ete releve : le bouton en haut.
        do
            local sansPrix = {}
            for _, v in ipairs(aVendre) do if not v.unite and not v.releve then table.insert(sansPrix, v.objet) end end
            if #sansPrix > 0 and not NS.encheres.EnCours() then
                Action(string.format(L().AH_SCAN_BAGS, #sansPrix), function()
                    statut = nil
                    NS.encheres.Relever(sansPrix)
                    courrier.Actualiser()
                end)
            elseif NS.encheres.EnCours() then
                local r, total = NS.encheres.Avancement()
                Action(string.format(L().AH_SCANNING, math.min(r, total), total), function() end)
                panneau.boutons[nb]:SetEnabled(false)
            end
        end
        Titre(L().AH_SELL_TITLE)
        if #aVendre == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_SELL_NONE)
            y = y + 16
        else
            for rang, v in ipairs(aVendre) do
                LigneVente(v)
            end
        end
    end
    if lieu == "encheres" and NS.encheres and NS.encheres.Disponible() and OngletHV() == "recettes" then
        -- Onglet Recettes : les plans a apprendre tout de suite, leur prix
        -- releve, et un bouton pour les chercher dans l'hotel des ventes.
        vide = false
        local okP, plans = pcall(NS.encheres.PlansAApprendre)
        plans = okP and plans or {}
        do
            local sansPrix = {}
            for _, p in ipairs(plans) do
                local prix, _, absent = NS.encheres.Prix(p.objet, 1)
                if not prix and not absent then table.insert(sansPrix, p.objet) end
            end
            if #sansPrix > 0 and not NS.encheres.EnCours() then
                Action(string.format(L().AH_RECIPES_SCAN, #sansPrix), function()
                    statut = nil
                    NS.encheres.Relever(sansPrix)
                    courrier.Actualiser()
                end)
            elseif NS.encheres.EnCours() then
                local r, total = NS.encheres.Avancement()
                Action(string.format(L().AH_SCANNING, math.min(r, total), total), function() end)
                panneau.boutons[nb]:SetEnabled(false)
            end
        end
        Titre(L().AH_RECIPES_TITLE)
        if #plans == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_RECIPES_NONE)
            y = y + 16
        else
            for k, p in ipairs(plans) do
                local prix, quand, absent = NS.encheres.Prix(p.objet, 1)
                do
                    local droite = string.format(L().AH_RECIPES_RANK, p.rang)
                    if prix then droite = droite .. "  " .. NS.marchands.Monnaie(prix)
                    elseif absent then droite = droite .. "  |cff8c8c8c" .. L().AH_RECIPES_ABSENT .. "|r" end
                    local o = p.objet
                    LigneAvecBouton(o, droite, L().AH_FIND_SHORT, function() NS.encheres.Chercher(o) end)
                end
            end
        end
    end
    if lieu == "marchand" then
        local okA, achats = pcall(courrier.AchatsMarchand)
        achats = okA and achats or {}
        if #achats > 0 then
            vide = false
            local total = 0
            for _, a in ipairs(achats) do total = total + a.lots * a.prix end
            -- L'action en haut, sous la main : tout acheter, juste ce qui manque.
            Action(string.format(L().MERCHANT_BUY_ALL or "%s", NS.marchands.Monnaie(total)), function() courrier.Acheter(achats) end)
            if achatEnCours then panneau.boutons[nb]:SetEnabled(false) end
            Titre(L().MERCHANT_TITLE or "")
            for _, a in ipairs(achats) do
                local ligne = a
                local n = a.lots * a.lot
                LigneAvecBouton(a.objet, "x" .. n .. "  " .. NS.marchands.Monnaie(a.lots * a.prix), L().MERCHANT_BUY or "", function()
                    courrier.Acheter({ ligne })
                end)
                if achatEnCours then panneau.boutons[nb]:SetEnabled(false) end
            end
        end
    end
    -- Les onglets de l'hotel des ventes, sur le bord droit, en bas.
    if panneau.onglets then for _, o in pairs(panneau.onglets) do o:Hide() end end
    if lieu == "encheres" and NS.CreerOngletLateral then
        panneau.onglets = panneau.onglets or {}
        local defs = {
            -- Dans l'ordre d'une visite : acheter ce qui manque, vendre ce
            -- qu'on a, voir ce qui rapporte a fabriquer, les recettes a apprendre.
            { cle = "acheter", icone = "Interface\\Icons\\INV_Misc_Coin_02", aide = L().AH_TAB_BUY },
            { cle = "vendre", icone = "Interface\\Icons\\INV_Misc_Bag_08", aide = L().AH_TAB_SELL },
            { cle = "rentable", icone = "Interface\\Icons\\INV_Misc_Coin_17", aide = L().AH_TAB_TRADE or "" },
            { cle = "recettes", icone = "Interface\\Icons\\INV_Scroll_03", aide = L().AH_TAB_RECIPES },
        }
        local precedent
        for k = #defs, 1, -1 do
            local d = defs[k]
            local o = panneau.onglets[d.cle]
            if not o then
                o = NS.CreerOngletLateral(panneau, nil, d.icone, function()
                    NS.base.ReglagesGeneraux().ongletHV = d.cle
                    statut = nil
                    courrier.Actualiser()
                end)
                panneau.onglets[d.cle] = o
            end
            o.tooltipText = d.aide
            o:ClearAllPoints()
            if precedent then
                o:SetPoint("BOTTOMLEFT", precedent, "TOPLEFT", 0, (NS.suite and NS.suite.ECART_ENTRE_ONGLETS) or 14)
            else
                o:SetPoint("BOTTOMLEFT", panneau, "BOTTOMRIGHT", -2, 24)
            end
            precedent = o
            -- A la manette : LB / RB d'un onglet a l'autre.
            o.ongletPilote = 1
            local choisi = OngletHV() == d.cle
            o.choisi = choisi
            o:SetChecked(choisi)
            if o.Icon then o.Icon:SetVertexColor(choisi and 1 or 0.55, choisi and 1 or 0.55, choisi and 1 or 0.55) end
            o:Show()
        end
    end
    -- L'element choisi a la manette : celui d'avant s'il est encore la, sinon
    -- l'envoi choisi, sinon le premier. Il s'eclaire et porte l'icone Y.
    local actifs = {}
    for _, e in ipairs(elements) do if e.cadre:IsEnabled() then table.insert(actifs, e) end end
    panneau.elements = actifs
    local choix
    for _, e in ipairs(actifs) do if courrier.focusCle and e.cle == courrier.focusCle then choix = e end end
    if not choix then
        for _, e in ipairs(actifs) do if e.envoi and e.envoi == courrier.envoiChoisi then choix = e end end
    end
    choix = choix or actifs[1]
    panneau.choix = choix
    courrier.focusCle = choix and choix.cle or nil
    if choix and courrier.ToucheManette() then
        choix.cadre:LockHighlight()
        if choix.cadre.libelle then
            local ok, g = pcall(NS.manette.Glyphe, "PAD4", 14)
            if ok and g then choix.cadre:SetText(g .. " " .. choix.cadre.libelle) end
        end
        -- Plusieurs actions (plusieurs envois) : X passe a la suivante, dit
        -- sous le panneau.
        if #actifs > 1 then
            local okX, gx = pcall(NS.manette.Glyphe, "PAD3", 14)
            statutManette = (okX and gx or "X") .. " " .. L().ASSIST_PAD_NEXT
        else
            statutManette = nil
        end
    end

    if statutManette and courrier.ToucheManette() and #actifs > 1 then
        nt = nt + 1
        local t = Texte(nt, "GameFontHighlightSmall")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -(y + 2))
        t:SetWidth(largeur)
        t:SetText(statutManette)
        y = y + 18
    end
    -- Resultat de la derniere action, ici meme : pas seulement dans la discussion.
    if statut and not vide then
        nt = nt + 1
        local t = Texte(nt, "GameFontHighlightSmall")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", x0 + 0, -(y + 2))
        t:SetWidth(largeur)
        t:SetWordWrap(true)
        t:SetText("|cff80ff80" .. statut .. "|r")
        y = y + (t:GetStringHeight() or 14) + 6
    end
    panneau.contenu:SetHeight(math.max(1, y))
    LierManetteBientot(#actifs > 0)
    -- Hauteur : a l'hotel des ventes, toute la sienne ; ailleurs, celle du
    -- contenu, sans depasser la fenetre accompagnee. Au-dela, ca defile.
    -- Jamais plus petit que ce que le cadre du jeu demande : en dessous,
    -- ses bords debordaient.
    local voulu = math.max(120, HAUT_DU_CONTENU + y + BAS_DU_CONTENU)
    local cible = panneau.hauteurCible
    local hauteur = voulu
    if cible and cible > 120 then
        hauteur = (lieu == "encheres") and cible or math.min(voulu, cible)
    else
        hauteur = math.min(voulu, (UIParent:GetHeight() or 800) * 0.8)
    end
    panneau:SetHeight(hauteur)
    local defile = voulu > hauteur + 1
    -- Les boutons Vendre au bord droit du panneau : dans la place de la barre
    -- de defilement quand elle n'est pas la.
    for _, l in ipairs(panneau.ventes or {}) do
        if l.vendre then
            l.vendre:ClearAllPoints()
            l.vendre:SetPoint("RIGHT", l, "RIGHT", defile and 0 or 18, 0)
        end
    end
    if panneau.defil then
        panneau.defil:ClearAllPoints()
        panneau.defil:SetPoint("TOPLEFT", panneau.zone, "TOPLEFT", 0, 0)
        panneau.defil:SetPoint("BOTTOMRIGHT", panneau.zone, "BOTTOMRIGHT", defile and -22 or 0, 0)
        local barre = panneau.defil.ScrollBar
        if barre then barre:SetShown(defile) end
        if not defile then panneau.defil:SetVerticalScroll(0) end
    end
    return not vide
end

-- Bords de la fenetre du jeu reellement visible, en coordonnees de l'ecran
-- de l'interface. Plusieurs cadres peuvent la composer (banque de compte,
-- onglets) : on prend leur enveloppe.
local function Bornes(noms)
    local gauche, droite, bas, haut
    local echelleUI = UIParent:GetEffectiveScale()
    for _, nom in ipairs(noms) do
        local f = _G[nom]
        if f and f.IsVisible and f:IsVisible() then
            local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
            if l and r and b then
                local s = f:GetEffectiveScale() / echelleUI
                l, r, b = l * s, r * s, b * s
                gauche = gauche and math.min(gauche, l) or l
                droite = droite and math.max(droite, r) or r
                bas = bas and math.min(bas, b) or b
                if t then t = t * s haut = haut and math.max(haut, t) or t end
            end
        end
    end
    return gauche, droite, bas, haut
end

-- A droite de la fenetre accompagnee, aligne sur son bas.
local Placer
local function Replacer()
    if panneau and panneau:IsShown() then pcall(Placer) end
end
Placer = function()
    panneau:ClearAllPoints()
    panneau:SetWidth(LargeurDuLieu(lieu))
    if panneau.contenu then panneau.contenu:SetWidth(LargeurDuLieu(lieu) - 2 * NS.charte.MARGE - 10 - 22) end
    -- Le meme fond partout (banque, courrier, encheres).
    if panneau.cuir then panneau.cuir:Hide() end
    local gauche, droite, bas, haut = Bornes(FENETRES[lieu] or {})
    panneau.hauteurCible = (haut and bas) and (haut - bas) or nil
    if not gauche then
        panneau:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
        -- La fenetre du jeu s'affiche parfois juste apres l'evenement
        -- d'ouverture : on reessaie un instant plus tard pour s'y coller.
        -- On guette sa venue jusqu'a 3 secondes.
        local attente = 0
        panneau:SetScript("OnUpdate", function(self, ecoule)
            attente = attente + (ecoule or 0)
            local g = Bornes(FENETRES[lieu] or {})
            if g or attente > 3 then
                self:SetScript("OnUpdate", nil)
                if g then pcall(Placer) end
            end
        end)
        return
    end
    panneau:SetScript("OnUpdate", nil)
    panneau:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", droite + (ECART[lieu] or 8), bas)
end

-- Le panneau a-t-il lieu d'etre la, maintenant ?
local function Pertinent()
    if lieu == "courrier" then
        -- Seulement sur l'onglet d'envoi : jamais par-dessus la boite de
        -- reception ni la lecture d'un courrier.
        local envoi = _G.SendMailFrame
        return envoi and envoi.IsVisible and envoi:IsVisible()
    end
    return lieu == "banque" or lieu == "encheres" or lieu == "marchand"
end

-- Redessine le panneau, ou le cache s'il n'y a rien a faire ici.
-- Le panneau se recalcule au plus une fois toutes les 0,7 seconde : le
-- releve des prix de l'hotel des ventes, les sacs et le courrier le
-- demandaient en rafale, et chaque calcul (plans de tous les personnages)
-- s'empilait jusqu'a bloquer le jeu. Le dernier appel est toujours fait.
local ActualiserMaintenant
local dernierCalcul, calculPrevu = -10, false
function courrier.Actualiser()
    local maintenant = NS.Appeler(_G.GetTime) or 0
    local plusTard = Lire("C_Timer.After")
    if not plusTard or maintenant - dernierCalcul >= 0.7 then
        local r = courrier.Chronometrer(ActualiserMaintenant)
        -- Compte a partir de la fin du calcul : un calcul long ne s'enchaine
        -- jamais avec le suivant.
        dernierCalcul = NS.Appeler(_G.GetTime) or maintenant
        return r
    end
    if calculPrevu then return end
    calculPrevu = true
    NS.Appeler(plusTard, 0.7 - (maintenant - dernierCalcul), function()
        calculPrevu = false
        pcall(courrier.Chronometrer, ActualiserMaintenant)
        dernierCalcul = NS.Appeler(_G.GetTime) or 0
    end)
end
-- Mouchard de lenteur : un calcul du panneau qui depasse un quart de
-- seconde est note (incidents, lus apres un /reload) et signale dans la
-- discussion, au plus une fois par minute. Un blocage laisse ainsi une trace
-- visible avant de figer le jeu.
local dernierAvis = -100
function courrier.Chronometrer(fn)
    local chrono = _G.debugprofilestop
    local debut = chrono and chrono()
    local r = fn()
    if debut then
        local ms = chrono() - debut
        if ms > 250 then
            local quoi = string.format("panneau %s : %d ms", tostring(lieu), ms)
            if NS.base.NoterIncident then pcall(NS.base.NoterIncident, "lenteur", quoi) end
            local maintenant = NS.Appeler(_G.GetTime) or 0
            if maintenant - dernierAvis > 60 then
                dernierAvis = maintenant
                print("|cffffd100CraftCore|r calcul lent du panneau (" .. math.floor(ms) .. " ms), noté pour analyse.")
            end
        end
    end
    return r
end
ActualiserMaintenant = function()
    if not lieu or not NS.base.ReglagesGeneraux().assistant or not Pertinent() then
        if panneau then panneau:Hide() end
        return
    end
    local ok, plan = pcall(courrier.Plan)
    if not ok then
        NS.base.NoterIncident("assistant de banque et de courrier", plan)
        return
    end
    if not plan then return end
    panneau = panneau or Construire()
    -- Placer d'abord : la largeur decide de celle des lignes.
    Placer()
    if Remplir(plan) then
        panneau:Show()
    else
        panneau:Hide()
    end
end

-- Branchements faits une fois, la premiere fois qu'un lieu s'ouvre : suivre
-- l'onglet d'envoi, et se fermer avec la fenetre qu'on prolonge.
local branche = false
local function Brancher()
    if branche then return end
    branche = true
    local function Suivre(nom, script, fn)
        local f = _G[nom]
        if f and f.HookScript then pcall(f.HookScript, f, script, fn) end
    end
    local function Rafraichir() courrier.Actualiser() end
    Suivre("SendMailFrame", "OnShow", Rafraichir)
    Suivre("SendMailFrame", "OnHide", Rafraichir)
    Suivre("OpenMailFrame", "OnShow", Rafraichir)
    Suivre("OpenMailFrame", "OnHide", Rafraichir)
    Suivre("MailFrame", "OnHide", function() courrier.Ferme("courrier") end)
    Suivre("BankFrame", "OnHide", function() courrier.Ferme("banque") end)
    -- La banque (ou un de ses onglets) s'affiche ou bouge : on s'y recolle.
    for _, nom in ipairs(FENETRES.banque) do Suivre(nom, "OnShow", Replacer) end
end

-- Ce qui part a l'envoi d'un courrier : note juste avant, garde si l'envoi
-- reussit, pour un de mes personnages connus.
local enAttente
local function CleDe(nom)
    nom = string.lower(tostring(nom or ""))
    nom = string.match(nom, "^([^%-%s]+)") or nom
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if string.lower(Nom(fiche.cle) or "") == nom then return fiche.cle end
    end
end
local function AvantEnvoi(destinataire)
    enAttente = nil
    local cle = CleDe(destinataire)
    local lire = Lire("GetSendMailItem")
    if not cle or not lire then return end
    local objets = {}
    for i = 1, tonumber(_G.ATTACHMENTS_MAX_SEND) or 12 do
        local _, objet, _, nombre = NS.Appeler(lire, i)
        objet = tonumber(objet)
        if objet then objets[objet] = (objets[objet] or 0) + (tonumber(nombre) or 1) end
    end
    if next(objets) then enAttente = { cle = cle, objets = objets } end
end
local function EnvoiReussi()
    if not enAttente then return end
    local e = EnRoute()[enAttente.cle]
    if type(e) ~= "table" then e = { objets = {} } EnRoute()[enAttente.cle] = e end
    e.quand = NS.Appeler(_G.time) or 0
    e.horodatage = NS.Horodatage and NS.Horodatage() or nil
    e.objets = e.objets or {}
    for objet, n in pairs(enAttente.objets) do e.objets[objet] = (e.objets[objet] or 0) + n end
    if NS.commandes then pcall(NS.commandes.Envoye, enAttente.cle, enAttente.objets) end
    -- Compte dans les stocks du destinataire, au courrier, jusqu'a ce qu'il
    -- ouvre sa boite.
    if NS.inventaire.NoterEnvoi then pcall(NS.inventaire.NoterEnvoi, enAttente.cle, enAttente.objets) end
    -- Feuille de route : la part de ce reroll est-elle faite ? Qui ensuite ?
    if NS.suivi and NS.suivi.EnvoiFait then pcall(NS.suivi.EnvoiFait, enAttente.cle, enAttente.objets) end
    enAttente = nil
    statut = nil
    courrier.Actualiser()
end
if _G.hooksecurefunc and _G.SendMail then
    pcall(_G.hooksecurefunc, "SendMail", function(dest) pcall(AvantEnvoi, dest) end)
end
do
    local ecoute = CreateFrame("Frame")
    pcall(ecoute.RegisterEvent, ecoute, "MAIL_SEND_SUCCESS")
    pcall(ecoute.RegisterEvent, ecoute, "MAIL_FAILED")
    ecoute:SetScript("OnEvent", function(_, evenement)
        if evenement == "MAIL_SEND_SUCCESS" then pcall(EnvoiReussi) else enAttente = nil end
    end)
end

-- Resultat d'une action menee ailleurs (releve de l'hotel des ventes).
function courrier.Statut(texte)
    statut = texte
    courrier.Actualiser()
end

-- Ce qui sort de la banque ou arrive du courrier va dans le sac specialise
-- ad hoc (composants, herbes...) s'il y a de la place : une pile a la fois,
-- hors combat, seulement banque ou boite aux lettres ouverte.
local rangement
local refuses = {}
local function RangerDansSacsSpecialises()
    rangement = nil
    if enCours or not lieu or EnCombat() or CurseurPlein() then return end
    local specialises = {}
    for _, id in ipairs(TousLesSacs()) do
        local _, famille = NS.Appeler(Conteneur("GetContainerNumFreeSlots"), id)
        local reactif = id > (tonumber(_G.NUM_BAG_SLOTS) or 4)
        if (reactif or (tonumber(famille) or 0) ~= 0) and NombreDEmplacements(id) > 0 then specialises[id] = true end
    end
    if not next(specialises) then return end
    for _, id in ipairs(SacsOrdinaires()) do
        if not specialises[id] then
            for emplacement = 1, NombreDEmplacements(id) do
                local objet, _, verrou = ContenuDe(id, emplacement)
                if objet and not verrou and not refuses[objet] and #SacsSpecialises(objet) > 0 then
                    local bac, case = CaseLibre({}, objet)
                    if bac and specialises[bac] then
                        NS.Appeler(Conteneur("PickupContainerItem"), id, emplacement)
                        NS.Appeler(Conteneur("PickupContainerItem"), bac, case)
                        if CurseurPlein() then refuses[objet] = true Lacher() return end
                        -- La suivante, quand la case est deverrouillee.
                        local plusTard = Lire("C_Timer.After")
                        if plusTard then rangement = true NS.Appeler(plusTard, PAUSE, RangerDansSacsSpecialises) end
                        return
                    end
                end
            end
        end
    end
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function()
        if rangement or not lieu then return end
        local plusTard = Lire("C_Timer.After")
        if plusTard then rangement = true NS.Appeler(plusTard, PAUSE, function() pcall(RangerDansSacsSpecialises) end) end
    end)
end

function courrier.Ouvert(nouveauLieu)
    lieu = nouveauLieu
    statut = nil
    Brancher()
    courrier.Actualiser()
end

function courrier.Ferme(ancienLieu)
    if lieu == ancienLieu then lieu = nil end
    if panneau and not lieu then
        panneau:Hide()
        LierManette(false)
    end
end
