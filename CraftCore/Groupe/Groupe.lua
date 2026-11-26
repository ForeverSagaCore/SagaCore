local _, NS = ...

-- Avec mon groupe : ce que les membres du groupe savent fabriquer (leurs
-- vitrines), les commandes entre joueurs et l'echange prepare. Repris de
-- TradeCore, dans CraftCore : memes donnees (recettes, stocks, moteur), une
-- seule fenetre.
--
-- Messages d'add-on (invisibles dans le chat), prefixe "CraftCoreG" :
--   Q                         demande les vitrines du groupe
--   D|classe                  debut de ma vitrine (efface l'ancienne)
--   M|ligne|rang|rangMax|nom  un metier
--   R|ligne|rid:objet,...     ses recettes, par paquets
--   C|id|rid|objet|nombre     une commande (a l'artisan, en prive)
--   A|id|etat|objet:n,...     la reponse (au client, en prive)
--   X|id                      commande retiree
--   L|id                      commande livree (echange fait)
--
-- Les commandes sont rangees par personnage (CraftCoreDB.groupe.commandes
-- [cle]) : un autre de mes personnages ne voit pas celles-ci. Une commande
-- n'est acceptee que d'un membre du groupe. Les noms gardent leur royaume
-- (« Nom-Royaume ») : les messages prives arrivent aussi d'un autre royaume.

NS.groupe = {}
local groupe = NS.groupe
local L = setmetatable({}, { __index = function(_, k) return NS.L and NS.L[k] end })
local PREFIXE = "CraftCoreG"
local TAILLE = 230

local function Base()
    local d = CraftCoreDB
    if type(d) ~= "table" then return nil end
    d.groupe = type(d.groupe) == "table" and d.groupe or {}
    d.groupe.commandes = type(d.groupe.commandes) == "table" and d.groupe.commandes or {}
    return d.groupe
end

function groupe.Partage()
    local g = NS.base.ReglagesGeneraux()
    return g.partageVitrine ~= false
end
function groupe.Simulation()
    local g = NS.base.ReglagesGeneraux()
    return g.groupeSimule == true
end

-- ---------------------------------------------------------------------------
-- Noms et unites
-- ---------------------------------------------------------------------------

local function NomSeul(nom) return (string.match(tostring(nom or ""), "^([^%-%s]+)")) or tostring(nom or "") end
groupe.NomSeul = NomSeul

-- Le nom complet d'une unite : « Nom » sur mon royaume, « Nom-Royaume » sinon.
local function NomComplet(unite)
    local nom, royaume = NS.Appeler(UnitName, unite)
    if type(nom) ~= "string" then return nil end
    if type(royaume) == "string" and royaume ~= "" then return nom .. "-" .. royaume end
    return nom
end

-- Meme personnage ? Avec ou sans royaume : « Bob » et « Bob-MonRoyaume ».
local function Meme(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local monRoyaume = NS.Appeler(GetRealmName) or ""
    monRoyaume = tostring(monRoyaume):gsub("%s", "")
    local function Normal(n)
        n = tostring(n)
        if not n:find("%-") then return n .. "-" .. monRoyaume end
        return (n:gsub("%s", ""))
    end
    return Normal(a) == Normal(b)
end
groupe.Meme = Meme

function groupe.Unite(nom)
    for i = 1, 4 do if Meme(NomComplet("party" .. i), nom) then return "party" .. i end end
    for i = 1, 40 do if Meme(NomComplet("raid" .. i), nom) then return "raid" .. i end end
    return nil
end
function groupe.DansLeGroupe(nom) return groupe.Unite(nom) ~= nil end

local function Canal()
    if not NS.Appeler(NS.Lecture("IsInGroup")) then return nil end
    local enGroupe = NS.Lecture("IsInGroup")
    local instance, maison = _G.LE_PARTY_CATEGORY_INSTANCE, _G.LE_PARTY_CATEGORY_HOME
    if instance and NS.Appeler(enGroupe, instance) and not (maison and NS.Appeler(enGroupe, maison)) then
        return "INSTANCE_CHAT"
    end
    if NS.Appeler(NS.Lecture("IsInRaid")) then return "RAID" end
    return "PARTY"
end

-- ---------------------------------------------------------------------------
-- Vitrines
-- ---------------------------------------------------------------------------

-- Vitrines recues : [nom complet] = { classe, metiers = { [ligne] = { nom,
-- rang, rangMax, recettes = { [rid] = objet } } }, recue }.
groupe.recues = {}

local function Fiche(cle)
    local d = CraftCoreDB
    return type(d) == "table" and type(d.personnages) == "table" and d.personnages[cle] or nil
end

-- La vitrine d'un personnage du compte : ses recettes apprises qui
-- produisent un objet (un enchantement ne se donne pas dans un echange).
function groupe.VitrineDe(cle)
    local d, fiche = CraftCoreDB, Fiche(cle)
    local v = { metiers = {}, nombre = 0 }
    if not (type(d) == "table" and fiche and type(fiche.recettesApprises) == "table" and type(d.recettes) == "table") then return v end
    for rid, apprise in pairs(fiche.recettesApprises) do
        local r = apprise and d.recettes[tostring(rid)]
        local ligne = type(r) == "table" and r.objetProduit and NS.recettes.MetierDe and NS.recettes.MetierDe(r)
        if ligne then
            ligne = tostring(ligne)
            local m = v.metiers[ligne]
            if not m then
                local sien = type(fiche.metiers) == "table" and fiche.metiers[ligne] or {}
                m = { nom = sien.nom or (NS.recettes.NomDuMetier and NS.recettes.NomDuMetier(tonumber(ligne))), rang = sien.rang,
                    rangMax = sien.rangMax, recettes = {} }
                v.metiers[ligne] = m
            end
            m.recettes[tonumber(rid) or rid] = r.objetProduit
            v.nombre = v.nombre + 1
        end
    end
    return v
end

-- Ce qu'il faut pour `nombre` fabrications : { [objet] = n }.
function groupe.Composants(rid, nombre)
    local d = CraftCoreDB
    local r = type(d) == "table" and type(d.recettes) == "table" and d.recettes[tostring(rid)]
    if type(r) ~= "table" or type(r.composants) ~= "table" or #r.composants == 0 then return nil end
    local besoin = {}
    for _, c in ipairs(r.composants) do
        if c.objet and c.quantite then besoin[c.objet] = (besoin[c.objet] or 0) + c.quantite * (nombre or 1) end
    end
    return besoin
end

-- Ce que le personnage connecte a dans ses sacs (l'echange ne prend que la).
local function C(nom) return NS.Lecture("C_Container." .. nom, nom) end
local function Piles(objet)
    local piles = {}
    local nbCases, idCase = C("GetContainerNumSlots"), C("GetContainerItemID")
    local infoCase = NS.Lecture("C_Container.GetContainerItemInfo")
    if not (nbCases and idCase) then return piles end
    for sac = 0, 4 do
        for case = 1, (NS.Appeler(nbCases, sac) or 0) do
            if NS.Appeler(idCase, sac, case) == objet then
                local info = infoCase and NS.Appeler(infoCase, sac, case)
                if type(info) == "table" then
                    table.insert(piles, { sac = sac, case = case, nombre = info.stackCount or 1,
                        lie = info.isBound == true, bloque = info.isLocked == true })
                end
            end
        end
    end
    return piles
end
function groupe.DansLesSacs(objet)
    local n = 0
    for _, p in ipairs(Piles(objet)) do if not p.lie then n = n + p.nombre end end
    return n
end

-- Combien de fabrications le personnage connecte peut faire avec ses sacs.
function groupe.Faisables(rid)
    local besoin = groupe.Composants(rid, 1)
    if not besoin then return nil end
    local n
    for objet, q in pairs(besoin) do
        local k = math.floor(groupe.DansLesSacs(objet) / math.max(1, q))
        n = n and math.min(n, k) or k
    end
    return n or 0
end

-- Reponse suggeree a une commande : "peut", "manque" (avec ce qui manque,
-- d'apres les sacs : c'est ce que l'echange pourra prendre) ou "non".
function groupe.Suggestion(cle, rid, nombre, simule)
    local fiche = Fiche(cle)
    local apprise = fiche and type(fiche.recettesApprises) == "table" and fiche.recettesApprises[tostring(rid)]
    if not apprise then return "non", {} end
    local besoin = groupe.Composants(rid, nombre)
    if not besoin then return "peut", {} end
    local manques, rien = {}, true
    for objet, n in pairs(besoin) do
        local a
        if simule then
            local s = fiche.stocks and fiche.stocks[tostring(objet)]
            a = type(s) == "table" and tonumber(s.total) or 0
        else
            a = groupe.DansLesSacs(objet)
        end
        local reste = n - a
        if reste > 0 then manques[objet] = reste rien = false end
    end
    return rien and "peut" or "manque", manques
end

-- Groupe simule (reglage, pour essayer seul) : mes autres personnages du
-- meme camp, tous.
local function Simules()
    local moi = NS.ClePersonnage()
    local liste = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages() or {}) do
        if fiche.cle ~= moi and NS.inventaire.MemeCamp(fiche) then
            local v = groupe.VitrineDe(fiche.cle)
            if v.nombre > 0 then
                v.classe = fiche.jetonClasse
                table.insert(liste, { nom = NS.inventaire.NomCourt(fiche.cle), cle = fiche.cle, vitrine = v, simule = true })
            end
        end
    end
    table.sort(liste, function(a, b) return a.nom < b.nom end)
    return liste
end

-- Les membres a montrer : ceux dont la vitrine est arrivee et qui sont encore
-- dans le groupe (ou le groupe simule).
function groupe.Membres()
    if groupe.Simulation() then return Simules() end
    local liste = {}
    for nom, v in pairs(groupe.recues) do
        if groupe.DansLeGroupe(nom) then table.insert(liste, { nom = nom, vitrine = v }) end
    end
    table.sort(liste, function(a, b) return a.nom < b.nom end)
    return liste
end

-- ---------------------------------------------------------------------------
-- Reseau
-- ---------------------------------------------------------------------------

local file, active = {}, false
local function Vider()
    local m = table.remove(file, 1)
    if not m then active = false return end
    local envoyer = NS.Lecture("C_ChatInfo.SendAddonMessage", "SendAddonMessage")
    if envoyer then
        if m.cible then NS.Appeler(envoyer, PREFIXE, m.texte, "WHISPER", m.cible)
        else
            local canal = Canal()
            if canal then NS.Appeler(envoyer, PREFIXE, m.texte, canal) end
        end
    end
    local plusTard = NS.Lecture("C_Timer.After")
    if plusTard then plusTard(0.2, Vider) else Vider() end
end
local function Envoyer(texte, cible)
    table.insert(file, { texte = texte, cible = cible })
    if not active then active = true Vider() end
end

function groupe.EnvoyerVitrine()
    if not groupe.Partage() or not Canal() then return end
    local v = groupe.VitrineDe(NS.ClePersonnage())
    local _, classe = NS.Appeler(UnitClass, "player")
    Envoyer("D|" .. tostring(classe or ""))
    for ligne, m in pairs(v.metiers) do
        Envoyer(string.format("M|%s|%d|%d|%s", ligne, tonumber(m.rang) or 0, tonumber(m.rangMax) or 0,
            (tostring(m.nom or ""):gsub("|", ""))))
        local paquet = ""
        for rid, objet in pairs(m.recettes) do
            local morceau = tostring(rid) .. ":" .. tostring(objet)
            if #paquet + #morceau + 1 > TAILLE then
                Envoyer("R|" .. ligne .. "|" .. paquet)
                paquet = ""
            end
            paquet = (paquet == "") and morceau or (paquet .. "," .. morceau)
        end
        if paquet ~= "" then Envoyer("R|" .. ligne .. "|" .. paquet) end
    end
end

-- Ma vitrine, une seule fois apres plusieurs demandes rapprochees ; a un seul
-- nouveau venu, en prive, plutot qu'a tout le raid.
local prevu = false
function groupe.EnvoyerVitrineBientot()
    if prevu then return end
    prevu = true
    local plusTard = NS.Lecture("C_Timer.After")
    local function Go() prevu = false pcall(groupe.EnvoyerVitrine) end
    if plusTard then plusTard(2, Go) else Go() end
end
function groupe.Demander() if Canal() then Envoyer("Q") end end

local function Rafraichir()
    if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
    if NS.courrier and NS.courrier.Actualiser then pcall(NS.courrier.Actualiser) end
end

-- ---------------------------------------------------------------------------
-- Commandes entre joueurs
-- ---------------------------------------------------------------------------

function groupe.Commandes()
    local b = Base()
    local cle = NS.ClePersonnage()
    if not (b and cle) then return {} end
    b.commandes[cle] = type(b.commandes[cle]) == "table" and b.commandes[cle] or {}
    return b.commandes[cle]
end

local compteur = 0
local function NouvelId()
    compteur = compteur + 1
    return string.format("%s.%d.%d", NomSeul(NS.Appeler(UnitName, "player")) or "?", NS.Appeler(time) or 0, compteur)
end

local function Trouver(sens, nom, id)
    for rang, c in ipairs(groupe.Commandes()) do
        if c.sens == sens and c.id == id and Meme(c.qui, nom) then return c, rang end
    end
    return nil
end

local function NomObjet(objet) return NS.inventaire.NomDObjet(objet) end
local function Son()
    local jouer = NS.Lecture("PlaySound")
    local kit = _G.SOUNDKIT
    if jouer and kit and kit.TELL_MESSAGE then NS.Appeler(jouer, kit.TELL_MESSAGE) end
end

function groupe.Commander(membre, rid, objet, nombre)
    local c = { id = NouvelId(), sens = "envoyee", qui = membre.nom, cle = membre.cle, simule = membre.simule,
        rid = rid, objet = objet, nombre = nombre or 1, etat = "attente", quand = NS.Appeler(time) }
    table.insert(groupe.Commandes(), c)
    if membre.simule then
        local plusTard = NS.Lecture("C_Timer.After")
        local function Repondre()
            local etat, manques = groupe.Suggestion(membre.cle, rid, c.nombre, true)
            groupe.Reponse(c.qui, c.id, etat, manques)
            Rafraichir()
        end
        if plusTard then plusTard(1, Repondre) else Repondre() end
    else
        Envoyer(string.format("C|%s|%s|%s|%d", c.id, tostring(c.rid), tostring(c.objet), c.nombre), c.qui)
    end
    NS.Dire(string.format(L.GROUP_ORDER_SENT or "%d %s %s", c.nombre, NomObjet(objet), NomSeul(c.qui)))
    Rafraichir()
    return c
end

function groupe.Reponse(nom, id, etat, manques)
    local c = Trouver("envoyee", nom, id)
    if not c then return end
    if etat ~= "peut" and etat ~= "manque" and etat ~= "non" then return end
    c.etat, c.manques = etat, manques or {}
    local texte = etat == "peut" and L.GROUP_ANSWER_CAN or etat == "manque" and L.GROUP_ANSWER_MISSING or L.GROUP_ANSWER_NO
    NS.Dire(string.format(L.GROUP_ORDER_ANSWERED or "%s %s %s", NomSeul(c.qui), NomObjet(c.objet), tostring(texte)))
    Son()
end

function groupe.Recue(nom, id, rid, objet, nombre)
    if not (id and rid and objet) then return end
    -- Seulement d'un membre du groupe.
    if not groupe.DansLeGroupe(nom) then return end
    if Trouver("recue", nom, id) then return end
    local c = { id = id, sens = "recue", qui = nom, rid = rid, objet = objet, nombre = nombre or 1,
        etat = "attente", quand = NS.Appeler(time) }
    c.suggestion, c.manquesSuggeres = groupe.Suggestion(NS.ClePersonnage(), rid, c.nombre)
    table.insert(groupe.Commandes(), c)
    NS.Dire(string.format(L.GROUP_ORDER_RECEIVED or "%s %d %s", NomSeul(nom), c.nombre, NomObjet(objet)))
    Son()
end

-- Le projet qui porte une commande acceptee, dans Mes fabrications (onglet
-- des commandes), pour le joueur qui l'a demandee.
local function PoserProjet(c)
    if c.projet or not (NS.projets and NS.projets.Creer) then return end
    local nom = string.format(L.ORDER_PROJECT_NAME or "%s %s", NS.commandes.NomDeRecette(c.rid), NomSeul(c.qui))
    local projet = NS.projets.Creer(nom)
    if projet then
        projet.pourJoueur = c.qui
        projet.commandeGroupe = c.id
        NS.projets.Ajouter(projet.id, c.rid, c.nombre)
        c.projet = projet.id
    end
end
local function OterProjet(c)
    if not c.projet then return end
    local fiche = NS.base.Personnage and NS.base.Personnage()
    if fiche and type(fiche.projets) == "table" then fiche.projets[tostring(c.projet)] = nil end
    c.projet = nil
    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
end

function groupe.Repondre(c, etat)
    if c.sens ~= "recue" then return end
    c.etat = etat
    if etat == "non" then OterProjet(c) else PoserProjet(c) end
    if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
    c.manques = etat == "manque" and (c.manquesSuggeres or {}) or {}
    local morceaux = {}
    for objet, n in pairs(c.manques or {}) do table.insert(morceaux, objet .. ":" .. n) end
    Envoyer(string.format("A|%s|%s|%s", c.id, c.etat, table.concat(morceaux, ",")), c.qui)
    Rafraichir()
end

local function Enlever(c)
    OterProjet(c)
    for rang, autre in ipairs(groupe.Commandes()) do
        if autre == c then table.remove(groupe.Commandes(), rang) return end
    end
end
function groupe.Retirer(c)
    Enlever(c)
    if not c.simule then Envoyer("X|" .. c.id, c.qui) end
    Rafraichir()
end
local function Livree(c, prevenir)
    OterProjet(c)
    c.etat = "livree"
    c.livreeLe = NS.Appeler(time)
    if prevenir and not c.simule then Envoyer("L|" .. c.id, c.qui) end
    NS.Dire(string.format(L.GROUP_ORDER_DONE or "%s %s", NomObjet(c.objet), NomSeul(c.qui)))
end

-- L'etat d'une commande, en clair et en couleur.
function groupe.TexteEtat(c)
    if c.etat == "livree" then return "|cff4fd16a" .. (L.GROUP_STATE_DONE or "") .. "|r" end
    if c.etat == "non" then return "|cffff6060" .. (L.GROUP_STATE_NO or "") .. "|r" end
    if c.etat == "peut" then return "|cff4fd16a" .. (L.GROUP_STATE_CAN or "") .. "|r" end
    if c.etat == "manque" then return "|cffffd100" .. (L.GROUP_STATE_MISSING or "") .. "|r" end
    if c.sens == "recue" then return "|cffffd100" .. (L.GROUP_STATE_TO_ANSWER or "") .. "|r" end
    return "|cff8c8c8c" .. (L.GROUP_STATE_WAITING or "") .. "|r"
end

-- Effacer les commandes livrees ou refusees.
function groupe.EffacerTerminees()
    local liste = groupe.Commandes()
    for rang = #liste, 1, -1 do
        local c = liste[rang]
        if c.etat == "livree" or c.etat == "non" then OterProjet(c) table.remove(liste, rang) end
    end
end

-- Ce que j'apporte a l'echange pour cette commande : { { objet, nombre } }.
function groupe.AApporter(c)
    local liste = {}
    if c.sens == "recue" and c.etat ~= "non" then
        local n = math.min(c.nombre, groupe.DansLesSacs(c.objet))
        if n > 0 then table.insert(liste, { objet = c.objet, nombre = n }) end
    elseif c.sens == "envoyee" and c.etat == "manque" then
        for objet, manque in pairs(c.manques or {}) do
            local n = math.min(manque, groupe.DansLesSacs(objet))
            if n > 0 then table.insert(liste, { objet = objet, nombre = n }) end
        end
    end
    return liste
end

-- Les commandes encore ouvertes avec un joueur (pour le panneau d'echange).
function groupe.AvecJoueur(nom)
    local liste = {}
    for _, c in ipairs(groupe.Commandes()) do
        if Meme(c.qui, nom) and c.etat ~= "livree" and c.etat ~= "non" then table.insert(liste, c) end
    end
    return liste
end

-- ---------------------------------------------------------------------------
-- Echange prepare : les objets se posent un a un dans la fenetre d'echange
-- du jeu ; on valide soi-meme. Echange accepte : la commande est livree.
-- ---------------------------------------------------------------------------

groupe.partenaire = nil

-- Ce que chacun met dans l'echange, releve a chaque validation : { [objet] = n }.
local donne, recu = {}, {}
local function LireEchange()
    local function Cote(lien, info)
        local t = {}
        local lireLien, lireInfo = NS.Lecture(lien), NS.Lecture(info)
        if not (lireLien and lireInfo) then return t end
        for place = 1, 6 do
            local l = NS.Appeler(lireLien, place)
            local id = type(l) == "string" and tonumber(l:match("item:(%d+)"))
            if id then
                local _, _, n = NS.Appeler(lireInfo, place)
                t[id] = (t[id] or 0) + (tonumber(n) or 1)
            end
        end
        return t
    end
    donne = Cote("GetTradePlayerItemLink", "GetTradePlayerItemInfo")
    recu = Cote("GetTradeTargetItemLink", "GetTradeTargetItemInfo")
end

-- Echange accepte des deux cotes : chaque commande ouverte avec ce joueur
-- dont l'objet est passe de l'artisan au client est livree.
local function EchangeFait(qui)
    if not qui then return end
    local fait = false
    for _, c in ipairs(groupe.AvecJoueur(qui)) do
        local passe = (c.sens == "recue" and donne[c.objet]) or (c.sens == "envoyee" and recu[c.objet]) or 0
        if passe >= (c.nombre or 1) then
            Livree(c, true)
            fait = true
        end
    end
    if fait then Rafraichir() end
end

function groupe.Poser(c)
    local objets = groupe.AApporter(c)
    if #objets == 0 then NS.Dire(L.GROUP_TRADE_NOTHING or "") return end
    local prendre, couper = C("PickupContainerItem"), C("SplitContainerItem")
    local poser = NS.Lecture("ClickTradeButton")
    local plusTard = NS.Lecture("C_Timer.After")
    local rang, place, posees = 1, 1, 0
    -- Les cases deja prises dans l'echange ne sont pas reutilisees.
    local occupee = NS.Lecture("GetTradePlayerItemInfo")
    local function Libre()
        while place <= 6 do
            local nom = occupee and NS.Appeler(occupee, place)
            if not nom then return true end
            place = place + 1
        end
        return false
    end
    local reste = objets[1].nombre
    local function Etape()
        local o = objets[rang]
        if not o or not poser or not Libre() then
            NS.Dire(string.format(L.GROUP_TRADE_READY or "%d %s", posees, NomSeul(c.qui)))
            Rafraichir()
            return
        end
        if reste <= 0 then
            rang = rang + 1
            reste = objets[rang] and objets[rang].nombre or 0
            return Etape()
        end
        local pile
        for _, p in ipairs(Piles(o.objet)) do if not p.lie and not p.bloque then pile = p break end end
        if not pile then reste = 0 return Etape() end
        if pile.nombre <= reste then
            NS.Appeler(prendre, pile.sac, pile.case)
            reste = reste - pile.nombre
            posees = posees + pile.nombre
        else
            NS.Appeler(couper, pile.sac, pile.case, reste)
            posees = posees + reste
            reste = 0
        end
        NS.Appeler(poser, place)
        place = place + 1
        if plusTard then plusTard(0.3, Etape) else Etape() end
    end
    Etape()
end

-- Ouvrir l'echange avec le joueur d'une commande (il doit etre a portee).
function groupe.Echanger(c)
    if c.simule then NS.Dire(L.GROUP_TRADE_SIMULATED or "") return end
    local unite = groupe.Unite(c.qui)
    if not unite then NS.Dire(string.format(L.GROUP_TRADE_NOT_FOUND or "%s", NomSeul(c.qui))) return end
    local proche = NS.Lecture("CheckInteractDistance")
    if proche and not NS.Appeler(proche, unite, 2) then NS.Dire(string.format(L.GROUP_TRADE_TOO_FAR or "%s", NomSeul(c.qui))) return end
    groupe.aPoser = c
    local ouvrir = NS.Lecture("InitiateTrade")
    if ouvrir then NS.Appeler(ouvrir, unite) end
end

-- ---------------------------------------------------------------------------
-- Evenements
-- ---------------------------------------------------------------------------

local function Recevoir(texte, auteur)
    if Meme(auteur, NomComplet("player")) then return end
    local f = {}
    for champ in string.gmatch(texte .. "|", "([^|]*)|") do table.insert(f, champ) end
    local genre = f[1]
    if genre == "Q" then
        groupe.EnvoyerVitrineBientot()
    elseif genre == "D" then
        groupe.recues[auteur] = { classe = f[2] ~= "" and f[2] or nil, metiers = {}, recue = NS.Appeler(time) }
    elseif genre == "M" then
        local v = groupe.recues[auteur]
        if v then v.metiers[f[2]] = { rang = tonumber(f[3]), rangMax = tonumber(f[4]), nom = f[5], recettes = {} } end
    elseif genre == "R" then
        local v = groupe.recues[auteur]
        local m = v and v.metiers[f[2]]
        if m then
            for rid, objet in string.gmatch(f[3] or "", "(%d+):(%d+)") do m.recettes[tonumber(rid)] = tonumber(objet) end
        end
    elseif genre == "C" then
        groupe.Recue(auteur, f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]) or 1)
    elseif genre == "A" then
        local manques = {}
        for objet, n in string.gmatch(f[4] or "", "(%d+):(%d+)") do manques[tonumber(objet)] = tonumber(n) end
        groupe.Reponse(auteur, f[2], f[3], manques)
    elseif genre == "X" then
        for _, sens in ipairs({ "recue", "envoyee" }) do
            local c = Trouver(sens, auteur, f[2])
            if c then Enlever(c) end
        end
    elseif genre == "L" then
        for _, sens in ipairs({ "recue", "envoyee" }) do
            local c = Trouver(sens, auteur, f[2])
            if c and c.etat ~= "livree" then Livree(c, false) end
        end
    end
    Rafraichir()
end

local ecoute = CreateFrame("Frame")
local membresConnus = 0
local dernierPartenaire
for _, ev in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "TRADE_SHOW", "TRADE_CLOSED",
    "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "UI_INFO_MESSAGE" }) do
    pcall(ecoute.RegisterEvent, ecoute, ev)
end
ecoute:SetScript("OnEvent", function(_, evenement, a, b, c2, d)
    if evenement == "PLAYER_LOGIN" then
        local inscrire = NS.Lecture("C_ChatInfo.RegisterAddonMessagePrefix", "RegisterAddonMessagePrefix")
        if inscrire then NS.Appeler(inscrire, PREFIXE) end
        groupe.Demander()
        groupe.EnvoyerVitrineBientot()
    elseif evenement == "CHAT_MSG_ADDON" then
        if a ~= PREFIXE then return end
        local ok, souci = pcall(Recevoir, b, d)
        if not ok and NS.base.NoterIncident then NS.base.NoterIncident("groupe, reception", souci) end
    elseif evenement == "GROUP_ROSTER_UPDATE" then
        local n = NS.Appeler(NS.Lecture("GetNumGroupMembers")) or 0
        if n > membresConnus then
            groupe.Demander()
            groupe.EnvoyerVitrineBientot()
        end
        membresConnus = n
        Rafraichir()
    elseif evenement == "TRADE_SHOW" then
        groupe.partenaire = NomComplet("NPC")
        dernierPartenaire = groupe.partenaire
        donne, recu = {}, {}
        if NS.courrier and NS.courrier.Ouvert then NS.courrier.Ouvert("echange") end
        -- Ouvert depuis une commande : ses objets se posent tout seuls.
        local c = groupe.aPoser
        groupe.aPoser = nil
        if c and Meme(c.qui, groupe.partenaire) then
            local plusTard = NS.Lecture("C_Timer.After")
            if plusTard then plusTard(0.3, function() groupe.Poser(c) end) else groupe.Poser(c) end
        end
    elseif evenement == "TRADE_CLOSED" then
        if NS.courrier and NS.courrier.Ferme then NS.courrier.Ferme("echange") end
        groupe.partenaire = nil
    elseif evenement == "TRADE_ACCEPT_UPDATE" or evenement == "TRADE_PLAYER_ITEM_CHANGED" or evenement == "TRADE_TARGET_ITEM_CHANGED" then
        pcall(LireEchange)
        if evenement ~= "TRADE_ACCEPT_UPDATE" then Rafraichir() end
    elseif evenement == "UI_INFO_MESSAGE" then
        -- « Echange effectue » : arrive apres la fermeture de la fenetre.
        if _G.ERR_TRADE_COMPLETE and (b == _G.ERR_TRADE_COMPLETE or a == _G.ERR_TRADE_COMPLETE) then
            local qui = dernierPartenaire
            dernierPartenaire = nil
            pcall(EchangeFait, qui)
        end
    end
end)
