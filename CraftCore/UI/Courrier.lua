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
local LARGEUR = 300
local statut               -- resultat de la derniere action, montre dans le panneau
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
        return rapatries or {}, pris or {}
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

function courrier.Plan()
    local moi = NS.base.Personnage()
    if not moi then return nil end
    local plan = { envois = {}, demandes = {}, sortir = {} }

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
                    local sacs, banque = NS.inventaire.SacsEtBanque(moi, objet)
                    local donner = math.min(quantite, sacs + banque)
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
            local sacs, banque = NS.inventaire.SacsEtBanque(moi, objet)
            disponible[objet] = (sacs + banque) - (dansMesSacsPourEnvoi[objet] or 0)
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
        if famille == nil or famille == 0 then table.insert(liste, id) end
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

local function CaseLibre(reservees)
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
local function Enchainer(etapes, fin)
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
        if continuer == "vite" or not plusTard then Suivante() else NS.Appeler(plusTard, PAUSE, Suivante) end
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
                local bac, case = CaseLibre(reservees)
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
    if _G.SendMailNameEditBox then pcall(_G.SendMailNameEditBox.SetText, _G.SendMailNameEditBox, envoi.nom) end
    if _G.SendMailSubjectEditBox then
        pcall(_G.SendMailSubjectEditBox.SetText, _G.SendMailSubjectEditBox, L().ASSIST_SUBJECT)
    end

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
        local essais = 0
        for _ = 1, 16 do
            table.insert(etapes, function()
                if reste <= 0 then return true end
                local case = CaseDePieceLibre()
                if not case then NS.Dire(L().ASSIST_MAIL_FULL) return false end
                local part = Prendre(sacs, ligne.objet, reste)
                if part == 0 then
                    -- Case encore verrouillee par le deplacement d'avant : on
                    -- reessaie au pas suivant, trois fois au plus.
                    essais = essais + 1
                    if essais >= 3 then nonJoints[ligne.objet] = reste reste = 0 end
                    return true
                end
                NS.Appeler(joindre, case)
                if CurseurPlein() then
                    -- Piece refusee : l'objet retourne dans son sac, on continue.
                    Lacher()
                    essais = essais + 1
                    if essais >= 3 then nonJoints[ligne.objet] = reste reste = 0 end
                    return true
                end
                reste = reste - part
                jointes = jointes + 1
                return true
            end)
        end
        if (ligne.enBanque or 0) > 0 then nonJoints[ligne.objet] = (nonJoints[ligne.objet] or 0) + ligne.enBanque end
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
    end)
end

-- Completer les piles : ce que j'ai dans mes sacs et qui est deja en banque
-- (sauf ce que mes projets me font sortir). Un objet par ligne, avec la
-- quantite dans les sacs ; choisi par defaut.
local pilesChoisies = {}
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
            if objet and enBanque[objet] and not aSortir[objet] then
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
function courrier.ChoisirPile(objet, oui) pilesChoisies[objet] = oui and nil or false end

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
local LIGNES_MAX = 8              -- par section ; au-dela, "et N autres"
-- Fenetres du jeu que le panneau accompagne, selon le lieu, et l'ecart a
-- laisser a leur droite (la banque a des onglets lateraux).
local FENETRES = {
    banque = { "BankFrame", "BankPanel", "AccountBankPanel", "BankSlotsFrame", "ReagentBankFrame" },
    courrier = { "MailFrame", "OpenMailFrame" },
    encheres = { "AuctionHouseFrame" },
}
local ECART = { banque = 48, courrier = 8, encheres = 8 }

local function Construire()
    -- La charte commune, sans portrait ni pied : un panneau.
    local cadre = NS.charte.Fenetre("CraftCoreAssistant", LARGEUR, 100,
        { portrait = false, deplacable = false, strate = "MEDIUM", sansPied = true })
    if cadre.titre then cadre.titre:SetText("CraftCore") end
    local contenu = CreateFrame("Frame", nil, cadre)
    contenu:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    contenu:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", 0, 0)
    contenu:SetHeight(1)
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
    cadre:HookScript("OnHide", function(self) pcall(_G.ClearOverrideBindings, self) end)
    cadre:Hide()
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

-- Touche A de la manette sur la premiere action du panneau (Tout sortir,
-- Preparer l'envoi), le temps que le panneau est ouvert. Une liaison
-- prioritaire, retiree des que le panneau se ferme ; jamais en combat.
function courrier.ToucheManette()
    local gp = _G.C_GamePad
    if not (gp and gp.IsEnabled) then return false end
    local ok, actif = pcall(gp.IsEnabled)
    return ok and actif == true
end

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
        local b = panneau and panneau.boutons[1]
        if b and b:IsShown() and b:IsEnabled() then b:Click("LeftButton") end
    end)
    return relaisManette
end

local function LierManette(actif)
    if not panneau then return end
    if NS.Appeler(NS.Lecture("InCombatLockdown")) then return end
    pcall(_G.ClearOverrideBindings, panneau)
    if actif and courrier.ToucheManette() and panneau.boutons[1] and panneau.boutons[1]:IsShown()
        and panneau.boutons[1]:IsEnabled() then
        Relais()
        pcall(_G.SetOverrideBindingClick, panneau, true, "PAD1", "CraftCoreAssistantManette", "LeftButton")
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
    local y, nt, ni, nb, nc = 0, 0, 0, 0, 0
    local largeur = panneau.contenu:GetWidth()
    if not largeur or largeur < 50 then largeur = LARGEUR - 2 * NS.charte.MARGE - 10 end

    local function Titre(texte)
        nt = nt + 1
        local t = Texte(nt, "GameFontNormal")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 0, -y)
        t:SetWidth(largeur)
        t:SetText(texte)
        y = y + 18
    end
    local function Ligne(objet, droite)
        ni, nt = ni + 1, nt + 1
        local icone = Icone(ni)
        icone:ClearAllPoints()
        icone:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 2, -y)
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
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 24, -y)
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
    local function Action(libelle, auClic)
        nb = nb + 1
        local b = Bouton(nb)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 0, -(y + 4))
        -- La premiere action se fait aussi a la manette (touche A) : l'icone
        -- du jeu devant le libelle.
        if nb == 1 and courrier.ToucheManette() then
            local ok, g = pcall(NS.manette.Glyphe, "PAD1", 14)
            if ok and g then libelle = g .. " " .. libelle end
        end
        b:SetText(libelle)
        -- Toute la largeur du panneau : le texte (icone de la manette et
        -- nombre compris) y tient toujours, et les boutons s'alignent.
        b:SetWidth(largeur)
        b:SetScript("OnClick", auClic)
        b:SetEnabled(not enCours)
        y = y + 32
    end

    -- Une ligne avec sa case a cocher (completer les piles).
    local function LigneACocher(objet, droite)
        nc, nt = nc + 1, nt + 1
        local c = Case(nc)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", -2, -(y - 2))
        c:SetChecked(courrier.PileChoisie(objet))
        c:SetScript("OnClick", function(self)
            courrier.ChoisirPile(objet, self:GetChecked() and true or false)
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
        for rang, envoi in ipairs(plan.envois) do
            if rang > 1 then y = y + 6 end
            vide = false
            Titre(string.format(L().ASSIST_SEND_TO, envoi.nom))
            Lignes(envoi.lignes, function(l)
                local droite = "x" .. l.quantite
                if l.enBanque > 0 then droite = droite .. "  " .. string.format(L().ASSIST_IN_BANK, l.enBanque) end
                if l.caisse then droite = droite .. "  |cff8c8c8c" .. L().ASSIST_FOR_CRATE .. "|r" end
                if l.commande then droite = droite .. "  |cff8c8c8c" .. L().ASSIST_FOR_ORDER .. "|r" end
                return droite
            end)
            if Lire("ClickSendMailItemButton") then
                Action(L().ASSIST_PREPARE, function() courrier.PreparerEnvoi(envoi) end)
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
    if lieu == "encheres" and NS.encheres and NS.encheres.Disponible() then
        -- Hotel des ventes : le releve des prix de ce qui manque.
        vide = false
        Titre(L().AH_TITLE)
        local objets = NS.encheres.ObjetsARelever()
        if #objets == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_NOTHING)
            y = y + 16
        else
            local liste = {}
            for _, objet in ipairs(objets) do table.insert(liste, { objet = objet }) end
            Lignes(liste, function(l)
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
                    if k > 6 then Reste(#aChercher - 6) break end
                    local o = objet
                    Action(string.format(L().AH_FIND, NS.inventaire.NomDObjet(o), manques[o]), function()
                        NS.encheres.Chercher(o)
                    end)
                end
            end
        end
        -- Ce qu'on peut fabriquer tout de suite et vendre : prix, benefice.
        local okR, rentables = pcall(NS.encheres.Rentables)
        rentables = okR and rentables or {}
        y = y + 6
        Titre(L().AH_CRAFT_TITLE)
        if #rentables == 0 then
            nt = nt + 1
            local t = Texte(nt, "GameFontDisableSmall")
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 0, -y)
            t:SetWidth(largeur)
            t:SetText(L().AH_CRAFT_NONE)
            y = y + 16
        else
            local liste = {}
            for _, r in ipairs(rentables) do table.insert(liste, { objet = r.recette.objetProduit, r = r }) end
            Lignes(liste, function(l)
                local v = l.r.valeur
                if v.benefice then
                    local signe = v.benefice >= 0 and "|cff4fd16a" or "|cffff6060"
                    return "x" .. l.r.n .. "  " .. signe .. string.format(L().AH_PROFIT, v.benefice >= 0 and "+" or "-",
                        NS.marchands.Monnaie(math.abs(v.benefice))) .. "|r"
                end
                return "x" .. l.r.n .. "  " .. string.format(L().AH_SELLS, NS.marchands.Monnaie(v.vente))
            end)
        end
        -- Les releves : ce qui manque, puis ce qu'on peut fabriquer.
        local aFabriquer = NS.encheres.ObjetsDesFabrications()
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
            if #aFabriquer > 0 then
                Action(string.format(L().AH_SCAN_CRAFTS, #aFabriquer), function()
                    statut = nil
                    NS.encheres.Relever(NS.encheres.ObjetsDesFabrications())
                    courrier.Actualiser()
                end)
            end
        end
    end
    -- Resultat de la derniere action, ici meme : pas seulement dans la discussion.
    if statut and not vide then
        nt = nt + 1
        local t = Texte(nt, "GameFontHighlightSmall")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.contenu, "TOPLEFT", 0, -(y + 2))
        t:SetWidth(largeur)
        t:SetWordWrap(true)
        t:SetText("|cff80ff80" .. statut .. "|r")
        y = y + (t:GetStringHeight() or 14) + 6
    end
    panneau.contenu:SetHeight(math.max(1, y))
    LierManetteBientot(nb > 0)
    -- Hauteur exacte du contenu : ni vide, ni debordement.
    panneau:SetHeight(HAUT_DU_CONTENU + y + BAS_DU_CONTENU)
    return not vide
end

-- Bords de la fenetre du jeu reellement visible, en coordonnees de l'ecran
-- de l'interface. Plusieurs cadres peuvent la composer (banque de compte,
-- onglets) : on prend leur enveloppe.
local function Bornes(noms)
    local gauche, droite, bas
    local echelleUI = UIParent:GetEffectiveScale()
    for _, nom in ipairs(noms) do
        local f = _G[nom]
        if f and f.IsVisible and f:IsVisible() then
            local l, r, b = f:GetLeft(), f:GetRight(), f:GetBottom()
            if l and r and b then
                local s = f:GetEffectiveScale() / echelleUI
                l, r, b = l * s, r * s, b * s
                gauche = gauche and math.min(gauche, l) or l
                droite = droite and math.max(droite, r) or r
                bas = bas and math.min(bas, b) or b
            end
        end
    end
    return gauche, droite, bas
end

-- A droite de la fenetre accompagnee, aligne sur son bas.
local Placer
local function Replacer()
    if panneau and panneau:IsShown() then pcall(Placer) end
end
Placer = function()
    panneau:ClearAllPoints()
    panneau:SetWidth(LARGEUR)
    if panneau.cuir then panneau.cuir:SetShown(lieu == "banque") end
    local gauche, droite, bas = Bornes(FENETRES[lieu] or {})
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
    return lieu == "banque" or lieu == "encheres"
end

-- Redessine le panneau, ou le cache s'il n'y a rien a faire ici.
function courrier.Actualiser()
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

function courrier.Ouvert(nouveauLieu)
    lieu = nouveauLieu
    statut = nil
    Brancher()
    courrier.Actualiser()
end

function courrier.Ferme(ancienLieu)
    if lieu == ancienLieu then lieu = nil end
    if panneau and not lieu then panneau:Hide() end
end
