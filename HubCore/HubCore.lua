local _, NS = ...

-- HubCore : le carrefour de la suite.
--
-- D'autres auteurs font tres bien certaines choses (le chemin detaille
-- jusqu'a un point, le journal des donjons...). Plutot que de les refaire,
-- la suite les reconnait quand le joueur les a installes et leur confie la
-- tache : c'est leur interface qui s'affiche, sous leur nom. HubCore ne
-- reprend rien de leur code ni de leurs donnees ; il leur passe une
-- demande, comme le joueur le ferait avec leur commande.
--
-- Pour les autres add-ons de la suite : _G.HubCoreAPI.
--   Disponible() : vrai si un add-on de trajet est la (selon les reglages)
--   NomTrajet()  : son nom
--   Trajet({ carte, x, y, titre }) : lui demande le chemin jusqu'au point
--     (x, y de 0 a 1 sur la carte), et coupe la fleche de la suite s'il le
--     faut, pour n'avoir qu'une fleche a l'ecran.

local FR = (GetLocale and GetLocale() == "frFR")
local function T(fr, en)
    local S = _G.CoreSuite
    if S and S.Langue then return S.Langue() == "frFR" and fr or en end
    return FR and fr or en
end

local function R()
    HubCoreDB = type(HubCoreDB) == "table" and HubCoreDB or {}
    local d = HubCoreDB
    if d.trajet ~= "spf" and d.trajet ~= "tomtom" and d.trajet ~= "aucun" then d.trajet = "auto" end
    if d.couperFleche == nil then d.couperFleche = true end
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
      sert = function() return T("Bouton « Itinéraire détaillé » du suivi des quêtes.", "\"Detailed route\" button of the quest tracker.") end },
    { cle = "tomtom", nom = "TomTom", dossiers = { "TomTom" },
      url = "https://www.curseforge.com/wow/addons/tomtom",
      role = function() return T("Des repères et une flèche ; la plupart des guides savent les suivre.",
          "Waypoints and an arrow; most guides can follow them.") end,
      sert = function() return T("Itinéraire détaillé quand aucun autre add-on de trajet n'est là.", "Detailed route when no other route add-on is there.") end },
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

-- Le moyen choisi : "spf", "tomtom" ou nil.
local function Moyen()
    local choix = R().trajet
    if choix == "aucun" then return nil end
    if (choix == "auto" or choix == "spf") and SPF() then return "spf" end
    if (choix == "auto" or choix == "tomtom") and TomTomPret() then return "tomtom" end
    return nil
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
        local ok = pcall(_G.TomTom.AddWaypoint, _G.TomTom, dest.carte, dest.x, dest.y,
            { title = titre ~= "" and titre or nil, from = "Forever SagaCore", persistent = false })
        if not ok then return false end
    end
    -- Une seule fleche a l'ecran : celle de l'add-on de trajet.
    local S = _G.CoreSuite
    if R().couperFleche and S and S.ArreterGuidage and S.GuidageActif and S.GuidageActif() then pcall(S.ArreterGuidage) end
    return true
end

_G.HubCoreAPI = {
    Disponible = function() return Moyen() ~= nil end,
    NomTrajet = function()
        local m = Moyen()
        return (m == "spf" and "Shortest Path Forever") or (m == "tomtom" and "TomTom") or nil
    end,
    Trajet = function(dest) return Envoyer(dest) end,
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
        nom = "HubCoreFenetre", cle = "HubCore", icone = "Interface\\Icons\\Spell_Nature_FarSight",
        titre = function() return "HubCore" end,
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
                          print("|cffffd100HubCore|r " .. T("Adresse sélectionnée : Cmd+C (ou Ctrl+C) pour la copier.",
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
                      return { { "auto", T("Automatique", "Automatic") }, { "spf", "Shortest Path Forever" },
                          { "tomtom", "TomTom" }, { "aucun", T("Aucun", "None") } }
                  end, function() return R().trajet end, function(v) R().trajet = v end)
                  page.rActuel = O.Rangee()
                  page.actuel = page.rActuel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                  page.actuel:SetPoint("RIGHT", page.rActuel, "RIGHT", -10, 0)
                  page.rCouper = O.Rangee()
                  page.cCouper = O.Case(page.rCouper, function(oui) R().couperFleche = oui end)
                  page.cCouper:SetPoint("RIGHT", page.rCouper, "RIGHT", -8, 0)
                  page.aide = O.Detail(40)
              end,
              rendre = function(page)
                  page.titre:SetText(T("Itinéraires détaillés", "Detailed routes"))
                  page.intro:SetText(T("Le suivi des quêtes sait quoi faire et dans quel ordre. Pour le chemin lui-même, il passe la main à un add-on de trajet : le bouton « Itinéraire détaillé » lui envoie la prochaine étape.",
                      "The quest tracker knows what to do and in which order. For the way itself, it hands over to a route add-on: the \"Detailed route\" button sends it the next step."))
                  page.rMoyen.nom:SetText(T("Add-on de trajet", "Route add-on"))
                  page.rActuel.nom:SetText(T("Utilisé maintenant", "Used now"))
                  local nom = _G.HubCoreAPI.NomTrajet()
                  page.actuel:SetText(nom or T("Aucun : le bouton est caché", "None: the button is hidden"))
                  page.rCouper.nom:SetText(T("Couper la flèche de la suite", "Turn off the suite's arrow"))
                  page.cCouper:SetChecked(R().couperFleche)
                  page.aide:SetText(T("Quand l'add-on de trajet prend la main, la flèche de la suite s'arrête : une seule flèche à l'écran.",
                      "When the route add-on takes over, the suite's arrow stops: a single arrow on screen."))
              end },
        },
    })
    return F.w
end

function F.Ouvrir()
    local S = _G.CoreSuite
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("HubCore") return true end
    return false
end

-- Une icone dans la suite (minicarte, en-tetes des fenetres), comme les
-- autres modules : montree des que HubCore est installe.
local function Rejoindre()
    local S = _G.CoreSuite
    if not (S and type(S.ORDRE) == "table") then return end
    for _, info in ipairs(S.ORDRE) do if info.cle == "HubCore" then return end end
    table.insert(S.ORDRE, { cle = "HubCore", icone = "Interface\\Icons\\Spell_Nature_FarSight", discret = true })
    if S.Annoncer then S.Annoncer("HubCore") end
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
        print("|cffffd100HubCore|r " .. T("a besoin d'un module de la suite (CraftCore, QuestCore, MapCore ou LegacyCore).",
            "needs one module of the suite (CraftCore, QuestCore, MapCore or LegacyCore)."))
    end
end
