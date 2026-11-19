local _, NS = ...

-- Releve du journal de quetes du personnage connecte : quetes en cours,
-- objectifs et progression, et quetes deja rendues. Rien n'est devine : ce
-- que le jeu montre, a l'instant du releve.

NS.journal = {}
local journal = NS.journal

-- Objectifs d'une quete du journal : { texte, type, fait, n, requis }.
local function Objectifs(id, index)
    local liste = {}
    local lire = NS.Lecture("C_QuestLog.GetQuestObjectives")
    local brut = lire and NS.Appeler(lire, id)
    if type(brut) == "table" then
        for _, o in ipairs(brut) do
            table.insert(liste, { texte = o.text, type = o.type, fait = o.finished and true or false,
                n = tonumber(o.numFulfilled) or 0, requis = tonumber(o.numRequired) or 0 })
        end
        return liste
    end
    -- Ancienne interface : une ligne de texte "Nom : 3/10" par objectif.
    local nb = NS.Appeler(NS.Lecture("GetNumQuestLeaderBoards"), index) or 0
    for i = 1, nb do
        local texte, genre, fait = NS.Appeler(NS.Lecture("GetQuestLogLeaderBoard"), i, index)
        local n, requis = string.match(texte or "", "(%d+)%s*/%s*(%d+)")
        table.insert(liste, { texte = texte, type = genre, fait = fait and true or false,
            n = tonumber(n) or 0, requis = tonumber(requis) or 0 })
    end
    return liste
end

-- Recompenses d'une quete du journal : argent (en cuivre), experience, objets
-- donnes et objets au choix. Le jeu ne les donne que pour la quete
-- selectionnee dans le journal : on la selectionne le temps de lire, puis on
-- remet la selection du joueur.
local function IdDuLien(lien)
    return lien and tonumber(string.match(lien, "item:(%d+)")) or nil
end

local function Recompenses(id, index)
    local r = { objets = {}, choix = {} }
    local moderne = NS.Lecture("C_QuestLog.SetSelectedQuest")
    local avant
    if moderne then
        avant = NS.Appeler(NS.Lecture("C_QuestLog.GetSelectedQuest"))
        NS.Appeler(moderne, id)
    else
        avant = NS.Appeler(NS.Lecture("GetQuestLogSelection"))
        NS.Appeler(NS.Lecture("SelectQuestLogEntry"), index)
    end
    -- Texte de la quete (ce qu'il faut faire), pour l'infobulle du suivi.
    local description, but = NS.Appeler(NS.Lecture("GetQuestLogQuestText"), index)
    r.description = type(description) == "string" and description ~= "" and description or nil
    r.but = type(but) == "string" and but ~= "" and but or nil
    r.argent = tonumber((NS.Appeler(NS.Lecture("GetQuestLogRewardMoney"), id))) or 0
    r.xp = tonumber((NS.Appeler(NS.Lecture("GetQuestLogRewardXP"), id))) or 0
    local lien = NS.Lecture("GetQuestLogItemLink")
    local info = NS.Lecture("GetQuestLogRewardInfo")
    for i = 1, tonumber((NS.Appeler(NS.Lecture("GetNumQuestLogRewards"), id))) or 0 do
        local _, _, n = NS.Appeler(info, i, id)
        local objet = IdDuLien(NS.Appeler(lien, "reward", i, id))
        if objet then table.insert(r.objets, { objet = objet, n = tonumber(n) or 1 }) end
    end
    local infoChoix = NS.Lecture("GetQuestLogChoiceInfo")
    for i = 1, tonumber((NS.Appeler(NS.Lecture("GetNumQuestLogChoices"), id))) or 0 do
        local _, _, n = NS.Appeler(infoChoix, i)
        local objet = IdDuLien(NS.Appeler(lien, "choice", i, id))
        if objet then table.insert(r.choix, { objet = objet, n = tonumber(n) or 1 }) end
    end
    if moderne then
        if avant then NS.Appeler(moderne, avant) end
    elseif avant then
        NS.Appeler(NS.Lecture("SelectQuestLogEntry"), avant)
    end
    return r
end

-- Les recompenses ne doivent jamais empecher le releve du journal.
local function LireRecompenses(id, index)
    local ok, r = pcall(Recompenses, id, index)
    if ok then return r end
    NS.base.NoterIncident("recompenses de la quete " .. tostring(id), r)
    return nil
end

-- Quete de donjon ou de raid : le nom de l'instance (d'apres la base, sinon
-- le jeu), et le genre. Le jeu marque ces quetes (tag 81 donjon, 62 raid,
-- 88 et 89 raid 10 et 25, 85 heroique).
local TAGS_INSTANCE = { [81] = "donjon", [85] = "donjon", [62] = "raid", [88] = "raid", [89] = "raid" }
local function Instance(id)
    local tag
    local moderne = NS.Lecture("C_QuestLog.GetQuestTagInfo")
    if moderne then
        local info = NS.Appeler(moderne, id)
        if type(info) == "table" then tag = tonumber(info.tagID) end
    end
    if not tag then
        local ancien = NS.Lecture("GetQuestTagInfo")
        if ancien then tag = tonumber((NS.Appeler(ancien, id))) end
    end
    local genre = tag and TAGS_INSTANCE[tag]
    if not genre then return nil end
    local zone = tonumber(NS.ref.Lire("QuestDB", id, "zoneOrSort"))
    local nom = zone and zone > 0 and NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), zone)
    if type(nom) ~= "string" or nom == "" then return nil end
    return nom, genre
end

local function LireQuetes()
    local quetes = {}
    local nombre = NS.Lecture("C_QuestLog.GetNumQuestLogEntries", "GetNumQuestLogEntries")
    local total = NS.Appeler(nombre) or 0
    local infoModerne = NS.Lecture("C_QuestLog.GetInfo")
    local zone
    for i = 1, total do
        local titre, niveau, entete, complete, id
        if infoModerne then
            local info = NS.Appeler(infoModerne, i)
            if type(info) == "table" then
                titre, niveau, entete, id = info.title, info.level, info.isHeader, info.questID
                complete = NS.Appeler(NS.Lecture("C_QuestLog.IsComplete"), id)
                if NS.Appeler(NS.Lecture("C_QuestLog.IsFailed"), id) then complete = -1 end
            end
        else
            local t = { NS.Appeler(NS.Lecture("GetQuestLogTitle"), i) }
            titre, niveau, entete, complete, id = t[1], t[2], t[4], t[6], t[8]
        end
        if entete then
            zone = titre
        elseif id and id ~= 0 then
            local instance, genreInstance = Instance(id)
            quetes[id] = { titre = titre, niveau = tonumber(niveau) or 0, zone = zone,
                instance = instance, genreInstance = genreInstance,
                complete = (complete == -1 and -1) or (complete and complete ~= 0 and true) or false,
                objectifs = Objectifs(id, i), recompenses = LireRecompenses(id, i) }
        end
    end
    return quetes
end

-- Quetes deja rendues, telles que le serveur les donne.
local function LireFaites()
    local faites = {}
    local moderne = NS.Lecture("C_QuestLog.GetAllCompletedQuestIDs")
    local liste = moderne and NS.Appeler(moderne)
    if type(liste) == "table" then
        for _, id in ipairs(liste) do faites[id] = true end
        return faites, true
    end
    local ancien = NS.Lecture("GetQuestsCompleted")
    local table_ = ancien and NS.Appeler(ancien)
    if type(table_) == "table" then
        for id, v in pairs(table_) do if v then faites[tonumber(id)] = true end end
        return faites, true
    end
    return faites, false
end

function journal.Relever()
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.Perso(cle)
    if not p then return end
    p.niveau = NS.Appeler(UnitLevel, "player") or p.niveau
    local _, classe = NS.Appeler(UnitClass, "player")
    p.classe = classe or p.classe
    p.faction = NS.Appeler(UnitFactionGroup, "player") or p.faction
    local _, _, race = NS.Appeler(UnitRace, "player")
    p.race = tonumber(race) or p.race
    local anciennes = p.quetes
    p.quetes = LireQuetes()
    -- Quetes qui viennent d'avancer : le suivi les fait clignoter un instant.
    if journal.dejaReleve then
        local ok, souci = pcall(journal.NoterAvancees, anciennes, p.quetes)
        if not ok then NS.base.NoterIncident("avancee des quetes", souci) end
    end
    if NS.groupe then
        local ok, souci = pcall(NS.groupe.ApresReleve, journal.dernieresAvancees)
        if not ok then NS.base.NoterIncident("groupe, envoi", souci) end
        journal.dernieresAvancees = nil
    end
    journal.dejaReleve = true
    -- Les quetes rendues s'ajoutent, ne s'effacent jamais : le serveur peut
    -- repondre avant d'avoir compte la toute derniere.
    local faites, lues = LireFaites()
    p.faites = p.faites or {}
    if lues then for id in pairs(faites) do p.faites[id] = true end end
    -- Ce qu'il porte, pour la page d'equipement ; jamais bloquant.
    if NS.equip then
        local ok, souci = pcall(NS.equip.Relever, p)
        if not ok then NS.base.NoterIncident("releve de l'equipement", souci) end
    end
    p.releve = NS.Appeler(date, "%d/%m %H:%M")
end

-- Avancee d'une quete entre deux releves : un objectif de plus rempli (ou
-- son texte "3/7" qui change), ou la quete devenue terminee.
journal.avancees = {}

function journal.NoterAvancees(anciennes, nouvelles)
    if type(anciennes) ~= "table" or type(nouvelles) ~= "table" then return end
    local maintenant = NS.Appeler(GetTime) or 0
    for id, q in pairs(nouvelles) do
        local a = anciennes[id]
        if type(a) == "table" then
            local terminee = q.complete == true and a.complete ~= true
            local avance = terminee
            local textes = {}
            for rang, o in ipairs(q.objectifs or {}) do
                local ao = (a.objectifs or {})[rang]
                if ao and (o.texte ~= ao.texte or (o.fait and not ao.fait)) then
                    avance = true
                    if o.texte and o.texte ~= "" then table.insert(textes, o.texte) end
                end
            end
            if avance then
                journal.avancees[id] = maintenant
                journal.dernieresAvancees = journal.dernieresAvancees or {}
                table.insert(journal.dernieresAvancees, id)
                -- Bandeau a l'ecran, et annonce au groupe quand elle est terminee.
                if NS.bandeau then pcall(NS.bandeau.Annoncer, q, textes, terminee, id) end
            end
        end
    end
end

-- Une quete rendue : notee tout de suite, sans attendre le releve suivant.
function journal.Rendue(id)
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.Perso(cle)
    if not p or not id then return end
    p.faites = p.faites or {}
    p.faites[id] = true
    if p.quetes then p.quetes[id] = nil end
end

-- ---------------------------------------------------------------------------
-- Groupe : les membres du groupe qui ont QuestCore s'echangent l'avancement
-- de leurs quetes (messages d'add-on, invisibles dans la discussion). Sert au
-- bandeau (un membre avance sur une quete que vous avez aussi) et au suivi
-- (avancement de chacun sous les objectifs).
--   R          : on repart de zero pour cet envoyeur
--   E|...      : etat complet, quete par quete
--   U|...      : quetes qui viennent d'avancer (bandeau chez les autres)
--   ?          : demande d'etat (a l'arrivee dans le groupe, au /reload)
--   T|id|niveau|titre|obj~obj : titre et objectifs (sans les comptes), pour
--                afficher les quetes d'un membre qu'on n'a pas soi-meme
-- Une quete : id:etat:n/r,n/r...  (etat 1 terminee, 0 en cours, -1 echouee)
-- ---------------------------------------------------------------------------

local groupe = { etats = {} }
NS.groupe = groupe
local PREFIXE = "QuestCore"

function groupe.Actif() return NS.base.ReglagesGeneraux().groupe ~= false end
function groupe.PoserActif(v)
    NS.base.ReglagesGeneraux().groupe = v and true or false
    if v then groupe.EnvoyerTout() groupe.Demander() end
    if NS.suivi then pcall(NS.suivi.Rendre) end
end

function groupe.MonNom() return NS.Appeler(UnitName, "player") or "" end

local function NomCourt(nom)
    nom = tostring(nom or "")
    -- "Nom-Royaume" ou "Nom Royaume" : le nom seul.
    return (string.match(nom, "^([^%-%s]+)")) or nom
end

local function Canal()
    if (tonumber(NS.base.ReglagesGeneraux().simuGroupe) or 0) > 0
        and not NS.Appeler(NS.Lecture("IsInGroup")) then return "SIMU" end
    if not NS.Appeler(NS.Lecture("IsInGroup")) then return nil end
    local enGroupe = NS.Lecture("IsInGroup")
    local instance, maison = _G.LE_PARTY_CATEGORY_INSTANCE, _G.LE_PARTY_CATEGORY_HOME
    if instance and NS.Appeler(enGroupe, instance) and not (maison and NS.Appeler(enGroupe, maison)) then
        return "INSTANCE_CHAT"
    end
    if NS.Appeler(NS.Lecture("IsInRaid")) then return "RAID" end
    return "PARTY"
end

-- File d'envoi : un message tous les 0,2 s, pour rester sous la limite du
-- serveur quand l'etat complet part (titres compris).
local file, fileActive = {}, false
local function Vider()
    local message = table.remove(file, 1)
    if not message then fileActive = false return end
    local canal = Canal()
    local envoyer = NS.Lecture("C_ChatInfo.SendAddonMessage", "SendAddonMessage")
    if canal and canal ~= "SIMU" and envoyer and groupe.Actif() then NS.Appeler(envoyer, PREFIXE, message, canal) end
    local plusTard = NS.Lecture("C_Timer.After")
    if plusTard then plusTard(0.2, Vider) else Vider() end
end
local function Envoyer(message)
    if not Canal() or not groupe.Actif() then return end
    table.insert(file, message)
    if not fileActive then
        fileActive = true
        Vider()
    end
end

-- Titre et objectifs d'une quete, sans les comptes : "Relique : 3/7" -> "Relique".
local function SansCompte(texte)
    texte = tostring(texte or ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*", "")
    return (texte:gsub("[|~]", ""))
end
local function EnvoyerTitre(id, q)
    local objs = {}
    for _, o in ipairs(q.objectifs or {}) do table.insert(objs, SansCompte(o.texte)) end
    local message = "T|" .. id .. "|" .. (tonumber(q.niveau) or 0) .. "|" .. tostring(q.titre or ""):gsub("|", "")
        .. "|" .. table.concat(objs, "~")
    Envoyer(string.sub(message, 1, 250))
end

local function EtatQuete(id, q)
    local morceaux = {}
    for _, o in ipairs(q.objectifs or {}) do
        table.insert(morceaux, (tonumber(o.n) or 0) .. "/" .. (tonumber(o.requis) or 0))
    end
    local etat = (q.complete == true and 1) or (q.complete == -1 and -1) or 0
    return id .. ":" .. etat .. ":" .. table.concat(morceaux, ",")
end

-- Envoi en morceaux de moins de 250 caracteres.
local function EnvoyerQuetes(entete, quetes, ids)
    local morceau = entete
    for _, id in ipairs(ids) do
        local e = EtatQuete(id, quetes[id])
        if #morceau + #e + 1 > 240 then Envoyer(morceau) morceau = entete end
        morceau = morceau .. e .. ";"
    end
    if morceau ~= entete then Envoyer(morceau) end
end

local function MesQuetes()
    local cle = NS.ClePersonnage()
    local p = cle and NS.base.Perso(cle)
    return p and p.quetes or {}
end

function groupe.EnvoyerTout()
    if not Canal() or not groupe.Actif() then return end
    local quetes, ids = MesQuetes(), {}
    for id in pairs(quetes) do table.insert(ids, id) end
    table.sort(ids)
    Envoyer("R")
    EnvoyerQuetes("E|", quetes, ids)
    for _, id in ipairs(ids) do EnvoyerTitre(id, quetes[id]) end
    groupe.EnvoyerFavoris()
end

-- Favoris : "F|id,id,id" (vide : plus aucun).
function groupe.EnvoyerFavoris()
    local ids = {}
    for id in pairs(NS.suivi and NS.suivi.ListeFavoris and NS.suivi.ListeFavoris() or {}) do table.insert(ids, id) end
    table.sort(ids)
    Envoyer("F|" .. table.concat(ids, ","))
end

function groupe.Demander() Envoyer("?") end

-- Apres un releve : les quetes qui ont avance partent tout de suite ; si la
-- liste des quetes a change (prise, abandon), l'etat complet repart.
local derniereListe
function groupe.ApresReleve(avancees)
    if not Canal() or not groupe.Actif() then derniereListe = nil return end
    local quetes, ids = MesQuetes(), {}
    for id in pairs(quetes) do table.insert(ids, id) end
    table.sort(ids)
    local liste = table.concat(ids, ",")
    if liste ~= derniereListe then
        derniereListe = liste
        groupe.EnvoyerTout()
    elseif avancees and #avancees > 0 then
        EnvoyerQuetes("U|", quetes, avancees)
    end
end

-- Le texte de mon objectif avec les comptes d'un autre : "Relique : 3/7".
function groupe.TexteAvec(texte, ob)
    texte = tostring(texte or "")
    local compte = ob.n .. "/" .. ob.r
    local remplace, n = string.gsub(texte, "%d+%s*/%s*%d+", compte, 1)
    if n > 0 then return remplace end
    return texte .. " : " .. compte
end

-- Membres du groupe qui ont cette quete : { { nom, etat, objs = { {n, r} } } }.
function groupe.Membres(id)
    local liste = {}
    if not groupe.Actif() or not Canal() then return liste end
    for nom, e in pairs(groupe.etats) do
        local q = e.quetes[id]
        if q then table.insert(liste, { nom = nom, etat = q.etat, objs = q.objs }) end
    end
    table.sort(liste, function(a, b) return a.nom < b.nom end)
    return liste
end

local function Lire(texte)
    local quetes = {}
    for bloc in string.gmatch(texte, "[^;]+") do
        local id, etat, objs = string.match(bloc, "^(%d+):(%-?%d+):(.*)$")
        if id then
            local q = { etat = tonumber(etat), objs = {} }
            for n, r in string.gmatch(objs, "(%d+)/(%d+)") do
                table.insert(q.objs, { n = tonumber(n), r = tonumber(r) })
            end
            quetes[tonumber(id)] = q
        end
    end
    return quetes
end

-- Un membre a avance sur une quete que j'ai aussi : le bandeau le dit.
local function Annoncer(nom, id, avant, apres)
    local moi = MesQuetes()[id]
    if not moi or not NS.bandeau then return end
    if apres.etat == 1 and (not avant or avant.etat ~= 1) then
        pcall(NS.bandeau.Montrer, moi.titre or "?", nom .. " : " .. NS.L.BANNER_DONE, true)
        return
    end
    local textes = {}
    for rang, ob in ipairs(apres.objs) do
        local ancien = avant and avant.objs[rang]
        if not ancien or ob.n > ancien.n then
            local o = (moi.objectifs or {})[rang]
            table.insert(textes, groupe.TexteAvec(o and o.texte or "", ob))
        end
    end
    if #textes > 0 then
        pcall(NS.bandeau.Montrer, moi.titre or "?", nom .. " : " .. table.concat(textes, "   "), false)
    end
end

local function Recevoir(texte, envoyeur)
    local nom = NomCourt(envoyeur)
    if nom == "" or nom == NomCourt(groupe.MonNom()) or not groupe.Actif() then return end
    if texte == "?" then
        groupe.aRepondre = true
        return
    end
    groupe.etats[nom] = groupe.etats[nom] or { quetes = {} }
    local e = groupe.etats[nom]
    if texte == "R" then
        e.quetes = {}
        return
    end
    local favoris = string.match(texte, "^F|(.*)$")
    if favoris then
        e.favoris = {}
        for id in string.gmatch(favoris, "%d+") do e.favoris[tonumber(id)] = true end
        if NS.suivi then pcall(NS.suivi.Rendre) end
        return
    end
    local tid, niveau, titre, objs = string.match(texte, "^T|(%d+)|(%d+)|([^|]*)|(.*)$")
    if tid then
        e.titres = e.titres or {}
        local t = { niveau = tonumber(niveau), titre = titre, objs = {} }
        for o in string.gmatch(objs, "[^~]+") do table.insert(t.objs, o) end
        e.titres[tonumber(tid)] = t
        if NS.suivi then pcall(NS.suivi.Rendre) end
        return
    end
    local genre, corps = string.match(texte, "^(%a)|(.*)$")
    if not genre then return end
    for id, q in pairs(Lire(corps)) do
        if genre == "U" then pcall(Annoncer, nom, id, e.quetes[id], q) end
        e.quetes[id] = q
    end
    if NS.suivi then pcall(NS.suivi.Rendre) end
end

-- Membres du groupe qui ont QuestCore (ceux dont on a recu l'etat).
function groupe.Noms()
    local noms = {}
    if not groupe.Actif() or not Canal() then return noms end
    for nom in pairs(groupe.etats) do table.insert(noms, nom) end
    table.sort(noms)
    return noms
end

function groupe.Etat(nom) return groupe.etats[nom] end

-- Classe d'un membre (jeton du jeu : "MAGE"...), nil si inconnue.
function groupe.Classe(nom)
    local simule = groupe.Simule(nom)
    if simule then return simule end
    local unite = groupe.Unite(nom)
    if not unite then return nil end
    local _, classe = NS.Appeler(UnitClass, unite)
    return classe
end

-- Unite du jeu d'un membre ("party1"...), pour sa classe.
function groupe.Unite(nom)
    for i = 1, 4 do
        if NS.Appeler(UnitName, "party" .. i) == nom then return "party" .. i end
    end
    for i = 1, 40 do
        if NS.Appeler(UnitName, "raid" .. i) == nom then return "raid" .. i end
    end
    return nil
end

-- Ceux qui ont quitte le groupe disparaissent du suivi.
local function Elaguer()
    local dans = NS.Lecture("UnitInParty")
    local raid = NS.Lecture("UnitInRaid")
    for nom in pairs(groupe.etats) do
        if not (NS.Appeler(dans, nom) or NS.Appeler(raid, nom) or groupe.Simule(nom)) then groupe.etats[nom] = nil end
    end
    if not Canal() then groupe.etats = {} end
end

local ecouteGroupe = CreateFrame("Frame")
do
    local inscrire = NS.Lecture("C_ChatInfo.RegisterAddonMessagePrefix", "RegisterAddonMessagePrefix")
    if inscrire then NS.Appeler(inscrire, PREFIXE) end
    for _, ev in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(ecouteGroupe.RegisterEvent, ecouteGroupe, ev)
    end
end
local envoiPrevu = false
local function EnvoyerBientot()
    if envoiPrevu then return end
    envoiPrevu = true
    local plusTard = NS.Lecture("C_Timer.After")
    local function Faire()
        envoiPrevu = false
        pcall(groupe.EnvoyerTout)
    end
    if plusTard then plusTard(2, Faire) else Faire() end
end
ecouteGroupe:SetScript("OnEvent", function(_, evenement, a, b, c, d)
    if evenement == "CHAT_MSG_ADDON" then
        if a ~= PREFIXE then return end
        local ok, souci = pcall(Recevoir, b, d)
        if not ok then NS.base.NoterIncident("groupe, reception", souci) end
        if groupe.aRepondre then
            groupe.aRepondre = false
            EnvoyerBientot()
        end
    elseif evenement == "GROUP_ROSTER_UPDATE" then
        pcall(Elaguer)
        local avant = groupe.dansGroupe
        groupe.dansGroupe = Canal() ~= nil
        if groupe.dansGroupe and not avant then groupe.Demander() end
        if groupe.dansGroupe then EnvoyerBientot() end
        if NS.suivi then pcall(NS.suivi.Rendre) end
    else
        groupe.dansGroupe = Canal() ~= nil
        if groupe.dansGroupe then
            groupe.Demander()
            EnvoyerBientot()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Mode developpeur : un groupe simule (1 a 4 membres), pour voir tout ce que
-- l'interface montre en groupe sans avoir de partenaire. Les membres
-- simules passent par la meme reception que les vrais ; rien ne part sur le
-- reseau.
-- ---------------------------------------------------------------------------

local SIMULES = { { "Aelis", "PRIEST" }, { "Borgrim", "WARRIOR" }, { "Cylia", "MAGE" }, { "Darok", "HUNTER" } }

function groupe.Simulation()
    if not (NS.suite and NS.suite.Prive and NS.suite.Prive()) then return 0 end
    return tonumber(NS.base.ReglagesGeneraux().simuGroupe) or 0
end

-- Classe d'un membre simule, nil pour un vrai.
function groupe.Simule(nom)
    local n = groupe.Simulation()
    for rang, m in ipairs(SIMULES) do
        if rang <= n and m[1] == nom then return m[2] end
    end
    return nil
end

local function RemplirSimule(rang)
    local nom = SIMULES[rang][1]
    local quetes, ids = MesQuetes(), {}
    for id in pairs(quetes) do table.insert(ids, id) end
    table.sort(ids)
    Recevoir("R", nom)
    local etats, favoris = {}, {}
    for k, id in ipairs(ids) do
        -- Chacun a une partie de mes quetes, plus ou moins avancees.
        if (k + rang) % 3 ~= 0 then
            local q = quetes[id]
            local fini = (k + rang) % 5 == 0
            local objs = {}
            for r, o in ipairs(q.objectifs or {}) do
                local requis = tonumber(o.requis) or 0
                local n = fini and requis or math.floor(requis * ((k * 7 + rang * 3 + r) % 5) / 4)
                table.insert(objs, n .. "/" .. requis)
            end
            table.insert(etats, id .. ":" .. (fini and 1 or 0) .. ":" .. table.concat(objs, ","))
            if #favoris < 2 and k % 2 == rang % 2 then table.insert(favoris, id) end
        end
    end
    -- Et une quete que je n'ai pas.
    local autre = 990000 + rang
    Recevoir("T|" .. autre .. "|" .. (10 + rang * 4) .. "|" .. string.format(NS.L.DEV_SIM_QUEST, nom)
        .. "|" .. NS.L.DEV_SIM_OBJ1 .. "~" .. NS.L.DEV_SIM_OBJ2, nom)
    table.insert(etats, autre .. ":0:" .. rang .. "/6,0/1")
    table.insert(favoris, autre)
    local morceau = "E|"
    for _, e in ipairs(etats) do
        if #morceau + #e + 1 > 240 then Recevoir(morceau, nom) morceau = "E|" end
        morceau = morceau .. e .. ";"
    end
    if morceau ~= "E|" then Recevoir(morceau, nom) end
    Recevoir("F|" .. table.concat(favoris, ","), nom)
end

function groupe.PoserSimulation(n)
    n = math.max(0, math.min(#SIMULES, tonumber(n) or 0))
    for _, m in ipairs(SIMULES) do groupe.etats[m[1]] = nil end
    NS.base.ReglagesGeneraux().simuGroupe = n
    for rang = 1, n do pcall(RemplirSimule, rang) end
    if NS.suivi then pcall(NS.suivi.Rendre) end
end

-- Un membre simule avance sur une quete que j'ai aussi : bandeau et suivi
-- reagissent comme pour un vrai.
function groupe.SimulerAvancee()
    local n = groupe.Simulation()
    if n == 0 then return false end
    local mes = MesQuetes()
    for essai = 1, n * 4 do
        local rang = ((groupe.prochainSimule or 0) % n) + 1
        groupe.prochainSimule = rang
        local nom = SIMULES[rang][1]
        local e = groupe.etats[nom]
        for id, q in pairs(e and e.quetes or {}) do
            if mes[id] and q.etat ~= 1 then
                local objs, avance, tous = {}, false, true
                for _, ob in ipairs(q.objs) do
                    local nouveau = ob.n
                    if not avance and ob.n < ob.r then nouveau, avance = ob.n + 1, true end
                    if nouveau < ob.r then tous = false end
                    table.insert(objs, nouveau .. "/" .. ob.r)
                end
                if avance or #q.objs == 0 then
                    Recevoir("U|" .. id .. ":" .. (tous and 1 or 0) .. ":" .. table.concat(objs, ","), nom)
                    return true
                end
            end
        end
    end
    return false
end

-- Au chargement : le groupe simule reprend s'il etait en place.
do
    local apres = NS.Lecture("C_Timer.After")
    local function Reprendre()
        local n = groupe.Simulation()
        if n > 0 then groupe.PoserSimulation(n) end
    end
    if apres then apres(3, Reprendre) end
end

-- ---------------------------------------------------------------------------
-- Don : donner a un membre du groupe les objets de quete qu'on a en trop.
-- Le clic ouvre l'echange et y pose la quantite ; il ne reste qu'a valider
-- l'echange soi-meme (le jeu le demande).
-- ---------------------------------------------------------------------------

local don = {}
NS.don = don

local function C(nom, global) return NS.Lecture("C_Container." .. nom, global or nom) end

-- Les piles de cet objet dans les sacs : { sac, case, nombre, lie, bloque }.
local function Piles(objet)
    local piles = {}
    local nbCases = C("GetContainerNumSlots")
    local infoCase = NS.Lecture("C_Container.GetContainerItemInfo")
    local idCase = C("GetContainerItemID")
    if not nbCases then return piles end
    for sac = 0, 4 do
        for case = 1, (NS.Appeler(nbCases, sac) or 0) do
            local id = idCase and NS.Appeler(idCase, sac, case)
            if id == objet then
                local info = infoCase and NS.Appeler(infoCase, sac, case)
                if type(info) == "table" then
                    table.insert(piles, { sac = sac, case = case, nombre = info.stackCount or 1,
                        lie = info.isBound == true, bloque = info.isLocked == true })
                else
                    local _, nombre, bloque = NS.Appeler(_G.GetContainerItemInfo, sac, case)
                    table.insert(piles, { sac = sac, case = case, nombre = nombre or 1, bloque = bloque == true })
                end
            end
        end
    end
    return piles
end

-- Combien on peut donner de cet objet en gardant `garder` pour soi.
function don.EnTrop(objet, garder)
    if not objet then return 0 end
    local total, echangeable = 0, 0
    for _, p in ipairs(Piles(objet)) do
        total = total + p.nombre
        if not p.lie then echangeable = echangeable + p.nombre end
    end
    return math.max(0, math.min(total - (garder or 0), echangeable))
end

local attente

local function Placer()
    if not attente then return end
    local reste, place = attente.quantite, 1
    local prendre = C("PickupContainerItem")
    local couper = C("SplitContainerItem")
    local poser = NS.Lecture("ClickTradeButton")
    local plusTard = NS.Lecture("C_Timer.After")
    local function Etape()
        if not attente then return end
        if reste <= 0 or place > 6 then
            NS.Dire(string.format(NS.L.GIVE_READY, attente.quantite - reste, attente.nom))
            attente = nil
            return
        end
        local pile
        for _, p in ipairs(Piles(attente.objet)) do
            if not p.lie and not p.bloque then pile = p break end
        end
        if not (pile and poser) then
            NS.Dire(string.format(NS.L.GIVE_READY, attente.quantite - reste, attente.nom))
            attente = nil
            return
        end
        if pile.nombre <= reste then
            NS.Appeler(prendre, pile.sac, pile.case)
            reste = reste - pile.nombre
        else
            NS.Appeler(couper, pile.sac, pile.case, reste)
            reste = 0
        end
        NS.Appeler(poser, place)
        place = place + 1
        if plusTard then plusTard(0.3, Etape) else Etape() end
    end
    Etape()
end

function don.Donner(nom, objet, quantite)
    if not (objet and quantite and quantite > 0) then return end
    if NS.groupe.Simule and NS.groupe.Simule(nom) then NS.Dire(NS.L.GIVE_SIMULATED) return end
    local unite = NS.groupe.Unite(nom)
    if not unite then NS.Dire(string.format(NS.L.GIVE_NOT_FOUND, nom)) return end
    local proche = NS.Lecture("CheckInteractDistance")
    if proche and not NS.Appeler(proche, unite, 2) then NS.Dire(string.format(NS.L.GIVE_TOO_FAR, nom)) return end
    attente = { nom = nom, objet = objet, quantite = quantite }
    local ouvrir = NS.Lecture("InitiateTrade")
    if not ouvrir then attente = nil return end
    NS.Appeler(ouvrir, unite)
end

local ecouteEchange = CreateFrame("Frame")
pcall(ecouteEchange.RegisterEvent, ecouteEchange, "TRADE_SHOW")
pcall(ecouteEchange.RegisterEvent, ecouteEchange, "TRADE_CLOSED")
ecouteEchange:SetScript("OnEvent", function(_, evenement)
    if evenement == "TRADE_SHOW" then
        local plusTard = NS.Lecture("C_Timer.After")
        if plusTard then plusTard(0.2, Placer) else Placer() end
    else
        attente = nil
    end
end)
