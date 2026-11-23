local _, NS = ...

-- FriendsCore : une petite aide de la suite, les add-ons amis.
--
-- D'autres auteurs font tres bien certaines choses (le chemin detaille
-- jusqu'a un point, le journal des donjons...). Plutot que de les refaire,
-- la suite les reconnait quand le joueur les a installes et leur confie la
-- tache : c'est leur interface qui s'affiche, sous leur nom. FriendsCore ne
-- reprend rien de leur code ni de leurs donnees ; il leur passe une
-- demande, comme le joueur le ferait avec leur commande.
--
-- Pour les autres add-ons de la suite : _G.FriendsCoreAPI.
--   Disponible() : vrai si un add-on de trajet est la (selon les reglages)
--   NomTrajet()  : son nom
--   Trajet({ carte, x, y, titre }) : lui demande le chemin jusqu'au point
--     (x, y de 0 a 1 sur la carte). Le guidage de la suite continue : seule
--     la suite decide de s'arreter (objectif atteint, arret demande, nouvel
--     objectif).

local FR = (GetLocale and GetLocale() == "frFR")
local function T(fr, en)
    local S = _G.CoreSuite
    if S and S.Langue then return S.Langue() == "frFR" and fr or en end
    return FR and fr or en
end

local function R()
    FriendsCoreDB = type(FriendsCoreDB) == "table" and FriendsCoreDB or {}
    local d = FriendsCoreDB
    if d.trajet ~= "spf" and d.trajet ~= "tomtom" and d.trajet ~= "aucun" then d.trajet = "auto" end
    -- Une fois : retour a "Me demander" (le choix d'un guidage ne devait pas
    -- devenir un reglage).
    if not d.choixParGuidage then d.choixParGuidage = true d.trajet = "auto" end
    return d
end

-- ---------------------------------------------------------------------------
-- Les add-ons connus
-- ---------------------------------------------------------------------------

local function Charge(nom)
    local f = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not f then return false end
    local ok, oui = pcall(f, nom)
    return ok and oui == true
end

-- "actif", "desactive" (installe mais pas charge) ou "absent".
local function EtatDossier(nom)
    if Charge(nom) then return "actif" end
    local f = (_G.C_AddOns and _G.C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
    if not f then return "absent" end
    local ok, n, _, _, _, raison = pcall(f, nom)
    if not ok or not n or raison == "MISSING" then return "absent" end
    return "desactive"
end

-- La fonction d'une commande ("/PATH"), ou nil.
local function Commande(cmd)
    local h = _G.hash_SlashCmdList
    local f = type(h) == "table" and h[cmd] or nil
    if type(f) == "function" then return f end
    local bas = string.lower(cmd)
    for cle, fn in pairs(type(_G.SlashCmdList) == "table" and _G.SlashCmdList or {}) do
        for i = 1, 4 do
            local s = _G["SLASH_" .. cle .. i]
            if not s then break end
            if string.lower(s) == bas then return fn end
        end
    end
    return nil
end

NS.ADDONS = {
    { cle = "spf", nom = "Shortest Path Forever", dossiers = { "ShortestPathForever", "ShortestPath" }, commande = "/PATH",
      url = "https://www.curseforge.com/wow/addons/shortest-path-forever",
      role = function() return T("Le chemin détaillé jusqu'aux étapes : à pied en contournant les obstacles, en vol, en bateau, en zeppelin, par portail.",
          "The detailed way to each step: on foot around obstacles, by flight, ship, zeppelin or portal.") end,
      sert = function() return T("Le chemin détaillé jusqu'à l'étape guidée par la suite.", "The detailed way to the step the suite guides.") end },
    { cle = "tomtom", nom = "TomTom", dossiers = { "TomTom" },
      url = "https://www.curseforge.com/wow/addons/tomtom",
      role = function() return T("Des repères et une flèche ; la plupart des guides savent les suivre.",
          "Waypoints and an arrow; most guides can follow them.") end,
      sert = function() return T("Le chemin jusqu'à l'étape guidée, quand aucun autre add-on de trajet n'est là.", "The way to the guided step when no other route add-on is there.") end },
    { cle = "mapzeroth", nom = "Mapzeroth", dossiers = { "Mapzeroth" },
      url = "https://www.curseforge.com/wow/addons/mapzeroth",
      role = function() return T("Le trajet le plus rapide avec vos sorts, vos objets, la pierre de foyer et les transports.",
          "The fastest way with your spells, items, hearthstone and transports.") end,
      sert = function() return T("Suit les repères TomTom posés par la suite.", "Follows the TomTom waypoints the suite sets.") end },
    { cle = "journal", nom = "DungeonJournal", dossiers = { "ForeverDungeonJournal" },
      recherche = "DungeonJournal",
      role = function() return T("Le journal des donjons : boss, butin, quêtes, entrées.", "The dungeon journal: bosses, loot, quests, entrances.") end,
      sert = function() return T("Bouton « Journal des donjons » de la page Donjons de QuestCore.", "\"Dungeon journal\" button of QuestCore's Dungeons page.") end },
    { cle = "questiedb", nom = "QuestieDB", dossiers = { "QuestieDB" },
      recherche = "QuestieDB",
      role = function() return T("La base de toutes les quêtes du jeu.", "The database of every quest in the game.") end,
      sert = function() return T("QuestCore en a besoin pour les quêtes, les donneurs et les objectifs.", "QuestCore needs it for quests, givers and objectives.") end },
}

function NS.Etat(a)
    local meilleur = "absent"
    for _, d in ipairs(a.dossiers or {}) do
        local e = EtatDossier(d)
        if e == "actif" then return "actif" end
        if e == "desactive" then meilleur = "desactive" end
    end
    if a.commande and Commande(a.commande) then return "actif" end
    return meilleur
end

-- ---------------------------------------------------------------------------
-- Passerelle de trajet
-- ---------------------------------------------------------------------------

local function SPF() return Commande("/PATH") end
local function TomTomPret()
    local t = _G.TomTom
    return type(t) == "table" and type(t.AddWaypoint) == "function"
end

-- Les add-ons de trajet installes : { { cle, nom } }.
local function Moyens()
    local t = {}
    if SPF() then table.insert(t, { cle = "spf", nom = "Shortest Path Forever" }) end
    if TomTomPret() then table.insert(t, { cle = "tomtom", nom = "TomTom" }) end
    return t
end
-- Le moyen choisi : "spf", "tomtom" ou nil. Tant que le joueur n'a pas
-- choisi (reglage "auto"), aucun : c'est a lui de dire qui le guide.
-- Le choix fait pour le guidage en cours (reglage "Me demander") : oublie
-- au guidage suivant.
local choixDuGuidage
local function Moyen()
    local choix = R().trajet
    if choix == "auto" then choix = choixDuGuidage end
    if choix == "spf" and SPF() then return "spf" end
    if choix == "tomtom" and TomTomPret() then return "tomtom" end
    return nil
end

-- Les points poses dans TomTom par la suite, pour pouvoir les retirer.
local posesTomTom = {}

-- Efface ce que les add-ons de trajet guident encore : une seule fleche a
-- l'ecran quand la suite guide elle-meme, ou quand le guidage s'arrete.
local function Effacer()
    if SPF() then pcall(SPF(), "way reset all") end
    if TomTomPret() and type(_G.TomTom.RemoveWaypoint) == "function" then
        for _, uid in ipairs(posesTomTom) do pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid) end
    end
    posesTomTom = {}
end

local function Envoyer(dest)
    local moyen = Moyen()
    if not (moyen and type(dest) == "table" and dest.carte and dest.x and dest.y) then return false end
    local titre = string.gsub(tostring(dest.titre or ""), "[\r\n]", " ")
    if moyen == "spf" then
        local info = _G.C_Map and _G.C_Map.GetMapInfo and select(2, pcall(_G.C_Map.GetMapInfo, dest.carte))
        local zone = type(info) == "table" and info.name or nil
        local texte = string.format("way %s%.1f %.1f %s", zone and (zone .. " ") or "", dest.x * 100, dest.y * 100, titre)
        local ok = pcall(SPF(), texte)
        if not ok then return false end
    else
        -- Un seul point de la suite a la fois dans TomTom.
        if type(_G.TomTom.RemoveWaypoint) == "function" then
            for _, uid in ipairs(posesTomTom) do pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid) end
        end
        posesTomTom = {}
        local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, dest.carte, dest.x, dest.y,
            { title = titre ~= "" and titre or nil, from = "Forever SagaCore", persistent = false })
        if not ok then return false end
        if uid then table.insert(posesTomTom, uid) end
    end
    return true
end

_G.FriendsCoreAPI = {
    Disponible = function() return Moyen() ~= nil end,
    NomTrajet = function()
        local m = Moyen()
        return (m == "spf" and "Shortest Path Forever") or (m == "tomtom" and "TomTom") or nil
    end,
    Trajet = function(dest) return Envoyer(dest) end,
    Effacer = function() Effacer() end,
    -- Un add-on de trajet est installe mais le joueur n'a pas encore choisi
    -- qui le guide : la suite lui pose la question.
    -- Reglage "Me demander", un add-on de trajet installe, et rien de choisi
    -- pour ce guidage : la suite pose la question.
    -- Sans add-on de trajet installe, aucune question.
    ADecider = function() return R().trajet == "auto" and choixDuGuidage == nil and #Moyens() > 0 end,
    Moyens = function() return Moyens() end,
    -- Tous les add-ons de trajet connus, installes ou non.
    Tous = function()
        return { { cle = "spf", nom = "Shortest Path Forever", installe = SPF() ~= nil },
            { cle = "tomtom", nom = "TomTom", installe = TomTomPret() } }
    end,
    -- Pour ce guidage seulement : "spf", "tomtom" ou "aucun" (la fleche).
    Choisir = function(cle) choixDuGuidage = (cle == "spf" or cle == "tomtom") and cle or "aucun" end,
    -- Nouveau guidage : on redemandera.
    Oublier = function() choixDuGuidage = nil end,
}

-- ---------------------------------------------------------------------------
-- Fenetre : les add-ons recommandes, et les reglages des passerelles
-- ---------------------------------------------------------------------------

local ETATS = {
    actif = function() return T("Installé et actif", "Installed and enabled"), { 0.31, 0.82, 0.41 } end,
    desactive = function() return T("Installé, désactivé", "Installed, disabled"), { 1, 0.82, 0 } end,
    absent = function() return T("Non installé", "Not installed"), { 0.6, 0.6, 0.6 } end,
}

NS.fenetre = {}
local F = NS.fenetre

function F.Construire()
    local S = _G.CoreSuite
    if F.w or not (S and S.FenetreAPages) then return F.w end
    F.w = S.FenetreAPages({
        nom = "FriendsCoreFenetre", cle = "FriendsCore", icone = "Interface\\Icons\\Spell_Nature_FarSight",
        titre = function() return "FriendsCore" end,
        pages = {
            { cle = "addons", icone = "Interface\\Icons\\Spell_Nature_FarSight",
              libelle = function() return T("Add-ons recommandés", "Recommended add-ons") end,
              construire = function(page, O)
                  page.titre = O.Section()
                  page.intro = O.Detail(40)
                  page.blocs = {}
                  -- Par add-on : son nom, son adresse, ce qu'il fait, son etat,
                  -- puis un filet avant le suivant.
                  for rang, a in ipairs(NS.ADDONS) do
                      local b = { a = a }
                      b.rang = O.Rangee(24, "GameFontNormal")
                      b.rLien = O.Rangee(24, "GameFontHighlightSmall")
                      b.lien = O.Saisie(b.rLien, 360, function() end)
                      b.lien:ClearAllPoints()
                      b.lien:SetPoint("LEFT", b.rLien, "LEFT", 16, 0)
                      b.lien:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
                      -- Le jeu ne laisse pas un add-on ecrire dans le presse-papiers :
                      -- Copier selectionne l'adresse, Cmd+C (ou Ctrl+C) la copie.
                      local champ = b.lien
                      b.copier = O.Bouton(b.rLien, 80, function()
                          champ:SetFocus()
                          champ:HighlightText()
                          print("|cffffd100FriendsCore|r " .. T("Adresse sélectionnée : Cmd+C (ou Ctrl+C) pour la copier.",
                              "Address selected: Cmd+C (or Ctrl+C) to copy it."))
                      end)
                      b.copier:ClearAllPoints()
                      b.copier:SetPoint("LEFT", b.lien, "RIGHT", 10, 0)
                      b.role = O.Detail(30)
                      b.etat = O.Detail(16)
                      if rang < #NS.ADDONS then
                          local f = CreateFrame("Frame", nil, page.cadre)
                          f:SetSize(O.LARGEUR - 10, 12)
                          O.Placer(f, 12, 4)
                          local filet = f:CreateTexture(nil, "ARTWORK")
                          filet:SetHeight(1)
                          filet:SetPoint("LEFT", f, "LEFT", 0, 0)
                          filet:SetPoint("RIGHT", f, "RIGHT", 0, 0)
                          -- Le filet des pages de LegacyCore : brun, bien visible.
                          filet:SetColorTexture(0.54, 0.39, 0.17, 0.8)
                      end
                      table.insert(page.blocs, b)
                  end
              end,
              rendre = function(page)
                  page.titre:SetText(T("Add-ons recommandés", "Recommended add-ons"))
                  page.intro:SetText(T("Des add-ons d'autres auteurs que la suite sait utiliser. Installés, ils prennent le relais avec leur propre interface ; absents, rien ne change. Le jeu ne peut pas ouvrir de lien : copiez l'adresse, ou cherchez le nom dans l'app CurseForge.",
                      "Add-ons by other authors that the suite can use. Installed, they take over with their own interface; missing, nothing changes. The game cannot open links: copy the address, or search the name in the CurseForge app."))
                  for _, b in ipairs(page.blocs) do
                      local etat = NS.Etat(b.a)
                      local texte, couleur = ETATS[etat]()
                      -- Installe et actif : le nom en vert, une coche a cote.
                      if etat == "actif" then
                          b.rang.nom:SetText(b.a.nom .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t")
                          b.rang.nom:SetTextColor(0.31, 0.82, 0.41)
                      else
                          b.rang.nom:SetText(b.a.nom)
                          b.rang.nom:SetTextColor(1, 0.82, 0)
                      end
                      b.copier:SetText(T("Copier", "Copy"))
                      b.rLien.nom:SetText("")
                      if b.a.url then
                          b.lien:SetText(b.a.url)
                      else
                          b.lien:SetText(T("Dans l'app CurseForge : ", "In the CurseForge app: ") .. (b.a.recherche or b.a.nom))
                      end
                      b.lien:SetCursorPosition(0)
                      b.role:SetText(b.a.role() .. "\n" .. b.a.sert())
                      b.etat:SetText(etat == "actif" and "" or texte)
                      b.etat:SetTextColor(couleur[1], couleur[2], couleur[3])
                  end
              end },
            { cle = "trajets", icone = "Interface\\Icons\\INV_Misc_Map_01",
              libelle = function() return T("Itinéraires", "Routes") end,
              construire = function(page, O)
                  page.titre = O.Section()
                  page.intro = O.Detail(40)
                  page.rMoyen = O.Rangee()
                  O.Liste(page.rMoyen, function()
                      return { { "auto", T("Me demander", "Ask me") }, { "spf", "Shortest Path Forever" },
                          { "tomtom", "TomTom" }, { "aucun", T("Forever SagaCore (sa flèche)", "Forever SagaCore (its arrow)") } }
                  end, function() return R().trajet end, function(v) R().trajet = v end)
                  page.rActuel = O.Rangee()
                  page.actuel = page.rActuel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                  page.actuel:SetPoint("RIGHT", page.rActuel, "RIGHT", -10, 0)
                  page.aide = O.Detail(40)
              end,
              rendre = function(page)
                  page.titre:SetText(T("Itinéraires détaillés", "Detailed routes"))
                  page.intro:SetText(T("La suite sait quoi faire et dans quel ordre. Pour le chemin lui-même, elle passe la main à un add-on de trajet : chaque étape guidée lui est envoyée.",
                      "The suite knows what to do and in which order. For the way itself, it hands over to a route add-on : each guided step is sent to it."))
                  page.rMoyen.nom:SetText(T("Add-on de trajet", "Route add-on"))
                  page.rActuel.nom:SetText(T("Utilisé maintenant", "Used now"))
                  local nom = _G.FriendsCoreAPI.NomTrajet()
                  page.actuel:SetText(nom or T("Aucun : la flèche de la suite", "None : the suite's arrow"))
                  page.aide:SetText(T("Me demander : la question est posée au début de chaque guidage, et le choix est gardé pour cet objectif.",
                      "Ask me : the question comes at the start of each guidance, and the choice is kept for that goal."))
              end },
        },
    })
    return F.w
end

function F.Ouvrir()
    local S = _G.CoreSuite
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("FriendsCore") return true end
    return false
end

-- Une icone dans la suite (minicarte, en-tetes des fenetres), comme les
-- autres modules : montree des que FriendsCore est installe.
local function Rejoindre()
    local S = _G.CoreSuite
    if not (S and type(S.ORDRE) == "table") then return end
    for _, info in ipairs(S.ORDRE) do if info.cle == "FriendsCore" then return end end
    table.insert(S.ORDRE, { cle = "FriendsCore", icone = "Interface\\Icons\\Spell_Nature_FarSight", discret = true })
    if S.Annoncer then S.Annoncer("FriendsCore") end
end

pcall(Rejoindre)

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        R()
        pcall(Rejoindre)
        pcall(F.Construire)
        local S = _G.CoreSuite
        if S and S.Actualiser then pcall(S.Actualiser) end
    end)
end

SLASH_HUBCORE1 = "/hub"
SLASH_HUBCORE2 = "/hubcore"
SlashCmdList.HUBCORE = function()
    if not F.Ouvrir() then
        print("|cffffd100FriendsCore|r " .. T("a besoin d'un module de la suite (CraftCore, QuestCore, MapCore ou LegacyCore).",
            "needs one module of the suite (CraftCore, QuestCore, MapCore or LegacyCore)."))
    end
end
