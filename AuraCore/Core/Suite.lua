local _, NS = ...

-- Suite Core : CraftCore, QuestCore, MapCore, LegacyCore.
--
-- Ce fichier est le meme dans tous les add-ons. Le premier charge installe
-- la suite ; les suivants ne font que s'y inscrire (la version la plus recente
-- gagne). Ce qu'elle apporte :
--   - un seul bouton de minicarte pour toute la suite : au survol, il s'etend
--     et montre tous les add-ons ; ceux qui ne sont pas installes sont grises ;
--   - une petite barre posee a l'ecran, deplacable ou l'on veut, avec les
--     memes icones ;
--   - dans chaque fenetre, les icones en haut a droite : on passe d'un
--     add-on a l'autre, la nouvelle fenetre prend la place exacte de l'ancienne.

-- Royaume du personnage. Depuis une mise a jour du jeu, GetRealmName() peut
-- rendre une chaine vide : on garde alors le dernier royaume connu, ou celui
-- d'un personnage deja enregistre sous le meme nom. Sans cela, toutes les
-- donnees rangees sous "Nom - Royaume" semblent disparaitre.
if not _G.SagaCoreRoyaume then
    local function Propre(r)
        if type(r) ~= "string" then return nil end
        r = r:match("^%s*(.-)%s*$")
        if r == "" or r == "?" then return nil end
        return r
    end
    -- Toutes les fonctions du jeu qui peuvent donner le royaume, dans l'ordre.
    local SOURCES = {
        function() return GetRealmName() end,
        function() return GetNormalizedRealmName() end,
        function() local _, r = UnitFullName("player") return r end,
        function() return select(7, GetPlayerInfoByGUID(UnitGUID("player"))) end,
        function() return GetCVar("realmName") end,
    }
    -- Dernier recours, quand le jeu ne donne le royaume nulle part : un nom
    -- fixe, pour que tout s'enregistre quand meme. Des que le vrai royaume
    -- arrive, les donnees rangees sous ce nom passent sous le vrai.
    local PROVISOIRE = "Forever"
    -- Les sauvegardes presentes (sans trou : ipairs s'arreterait au premier absent).
    local NOMS_BASES = { "QuestCoreDB", "CraftCoreDB", "MapCoreDB", "LegacyCoreDB", "TradeCoreDB",
        "FriendsCoreDB", "GloryCoreDB", "PvPCoreDB", "ClassCoreDB" }
    local BASES = function(db)
        local l = {}
        for _, n in ipairs(NOMS_BASES) do if type(_G[n]) == "table" then table.insert(l, _G[n]) end end
        if db then table.insert(l, db) end
        return l
    end
    local function Renommer(t, ancien, nouveau, prof)
        if type(t) ~= "table" or prof > 3 then return end
        local a_renommer = {}
        for cle, v in pairs(t) do
            if type(cle) == "string" and cle:sub(-#ancien) == ancien then
                local nom = cle:sub(1, -#ancien - 1)
                if nom:match(" %- $") then table.insert(a_renommer, cle) end
            end
            if type(v) == "table" then Renommer(v, ancien, nouveau, prof + 1) end
        end
        for _, cle in ipairs(a_renommer) do
            local neuve = cle:sub(1, -#ancien - 1) .. nouveau
            if t[neuve] == nil then t[neuve] = t[cle] t[cle] = nil end
        end
    end
    -- Les royaumes sous lesquels la suite a deja range des donnees, avec leur
    -- nombre de cles "Nom - Royaume" (le royaume provisoire mis a part).
    local function RoyaumesConnus(db)
        local compte = {}
        local function Parcourir(t, prof)
            if type(t) ~= "table" or prof > 3 then return end
            for cle, v in pairs(t) do
                if type(cle) == "string" then
                    local roy = Propre(cle:match("^[^%s]+ %- (.+)$"))
                    if roy and roy ~= PROVISOIRE then compte[roy] = (compte[roy] or 0) + 1 end
                end
                if type(v) == "table" then Parcourir(v, prof + 1) end
            end
        end
        for _, base in ipairs(BASES(db)) do pcall(Parcourir, base, 1) end
        local meilleur, n = nil, 0
        for roy, c in pairs(compte) do if c > n then meilleur, n = roy, c end end
        return meilleur
    end
    local retenu
    function _G.SagaCoreRoyaume()
        local db = type(_G.CoreSuiteDB) == "table" and _G.CoreSuiteDB or nil
        -- 0. Le royaume de la suite est fixe : le serveur Forever donne des
        -- noms de royaume changeants (« CAMWOW EU5 Realm 1 PvE », puis
        -- « Legacy », « Kity »...) pour un meme personnage. Des que la suite
        -- a des donnees, elle garde le royaume sous lequel elles sont
        -- rangees : un personnage n'a qu'une cle, jamais deux.
        if retenu then return retenu end
        if db and Propre(db.royaumeSuite) then retenu = db.royaumeSuite return retenu end
        local deja = RoyaumesConnus(db)
        if deja then
            if db then db.royaumeSuite = deja end
            retenu = deja
            return deja
        end
        -- 1. Installation neuve : le nom que le jeu donne d'habitude.
        local ok, r = pcall(GetRealmName)
        r = ok and not (_G.issecretvalue and _G.issecretvalue(r)) and Propre(r) or nil
        if r then
            if db then db.dernierRoyaume = r db.royaumeSuite = r end
            retenu = r
            return r
        end
        if retenu then return retenu end
        -- 2. Le jeu ne le donne pas : le royaume sous lequel la suite a deja
        -- ses donnees (jamais un autre nom du meme royaume, qui ferait croire
        -- a un nouveau personnage).
        local connu = RoyaumesConnus(db)
        if connu then
            if db then db.dernierRoyaume = connu end
            retenu = connu
            return connu
        end
        if db and Propre(db.dernierRoyaume) and db.dernierRoyaume ~= PROVISOIRE then
            retenu = db.dernierRoyaume
            return retenu
        end
        -- 3. Installation neuve : les autres fonctions du jeu.
        for k = 2, #SOURCES do
            local okS, v = pcall(SOURCES[k])
            v = okS and not (_G.issecretvalue and _G.issecretvalue(v)) and Propre(v) or nil
            if v then
                if db then
                    if db.royaumeProvisoire then
                        db.royaumeProvisoire = nil
                        for _, base in ipairs(BASES(db)) do pcall(Renommer, base, PROVISOIRE, v, 1) end
                    end
                    db.dernierRoyaume = v
                    retenu = v
                end
                return v
            end
        end
        -- 4. Rien nulle part : un nom provisoire, pour que tout s'enregistre.
        if db then db.royaumeProvisoire = true end
        return PROVISOIRE
    end

    -- Une fois toutes les sauvegardes chargees : les donnees d'un personnage
    -- rangees sous un autre nom de royaume rejoignent sa cle unique. Si la
    -- cle unique a deja ses donnees, l'autre copie part aux archives de la
    -- suite (CoreSuiteDB.archivesRoyaume), jamais effacee.
    function _G.SagaCoreUnifierRoyaume()
        local db = type(_G.CoreSuiteDB) == "table" and _G.CoreSuiteDB or nil
        local canon = _G.SagaCoreRoyaume()
        if not canon or canon == PROVISOIRE then return 0 end
        -- Les personnages connus (nom seul) et les royaumes sous lesquels ils
        -- ont ete ranges, d'apres les listes de personnages de la suite.
        local noms, royaumes = {}, {}
        local listes = {
            type(_G.CraftCoreDB) == "table" and _G.CraftCoreDB.personnages,
            type(_G.QuestCoreDB) == "table" and _G.QuestCoreDB.persos,
            type(_G.LegacyCoreDB) == "table" and _G.LegacyCoreDB.persos,
            type(_G.MapCoreDB) == "table" and _G.MapCoreDB.persos,
            type(_G.GloryCoreDB) == "table" and _G.GloryCoreDB.persos,
        }
        for i = 1, 5 do
            local l = listes[i]
            if type(l) == "table" then
                for cle in pairs(l) do
                    local nom, roy
                    if type(cle) == "string" then nom, roy = cle:match("^(%S+) %- ?(.*)$") end
                    if nom then noms[nom] = true royaumes[roy or ""] = true end
                end
            end
        end
        local function Autre(cle)
            if type(cle) ~= "string" then return nil end
            local nom, roy = cle:match("^(%S+) %- ?(.*)$")
            if not (nom and noms[nom] and royaumes[roy or ""]) or roy == canon then return nil end
            return nom .. " - " .. canon
        end
        local okJ, joueur = pcall(UnitName, "player")
        joueur = okJ and not (_G.issecretvalue and _G.issecretvalue(joueur)) and joueur or nil
        local okR, royaumeDuJeu = pcall(GetRealmName)
        royaumeDuJeu = okR and not (_G.issecretvalue and _G.issecretvalue(royaumeDuJeu)) and Propre(royaumeDuJeu) or nil
        local n = 0
        local function Parcourir(t, chemin, prof)
            if type(t) ~= "table" or prof > 4 then return end
            local cles, valeurs = {}, {}
            for cle, v in pairs(t) do
                if Autre(cle) then table.insert(cles, cle) end
                if type(v) == "string" and Autre(v) then table.insert(valeurs, cle) end
            end
            for _, cle in ipairs(valeurs) do t[cle] = Autre(t[cle]) n = n + 1 end
            for _, cle in ipairs(cles) do
                local neuve = Autre(cle)
                if t[neuve] == nil then
                    t[neuve] = t[cle]
                else
                    -- Deux copies : la plus fraiche reste. Celle du personnage
                    -- connecte, sous le royaume que le jeu donne en ce moment,
                    -- est celle ou il ecrit depuis : elle passe devant.
                    local nom, roy = cle:match("^(%S+) %- ?(.*)$")
                    local vivante = nom == joueur and roy == royaumeDuJeu
                    local perdue = vivante and t[neuve] or t[cle]
                    if vivante then t[neuve] = t[cle] end
                    if db then
                        db.archivesRoyaume = db.archivesRoyaume or {}
                        table.insert(db.archivesRoyaume, { ou = chemin, cle = vivante and neuve or cle, valeur = perdue })
                    end
                end
                t[cle] = nil
                n = n + 1
            end
            for cle, v in pairs(t) do
                if type(v) == "table" then Parcourir(v, chemin .. "." .. tostring(cle), prof + 1) end
            end
        end
        for _, nom in ipairs(NOMS_BASES) do
            if type(_G[nom]) == "table" then pcall(Parcourir, _G[nom], nom, 1) end
        end
        return n
    end
end

-- A la connexion (toutes les sauvegardes sont la) : une seule cle par
-- personnage dans toute la suite.
if not _G.SagaCoreUnifieur then
    local f = CreateFrame("Frame")
    _G.SagaCoreUnifieur = f
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if _G.SagaCoreUnifierRoyaume then pcall(_G.SagaCoreUnifierRoyaume) end
    end)
end

local VERSION = 154

local Suite = _G.CoreSuite
if Suite and (Suite.version or 0) >= VERSION then
    NS.suite = Suite
    return
end
Suite = Suite or { membres = {} }
Suite.version = VERSION
_G.CoreSuite = Suite
NS.suite = Suite

-- Les add-ons de la suite, dans l'ordre d'affichage, avec l'icone du jeu de
-- chacun. Un add-on absent reste montre, grise : on sait qu'il existe.
-- L'icone de MacroCore, la meme partout (colonne de gauche, fenetre,
-- pastille) : celle des macros du jeu.
Suite.ICONE_MACROCORE = "Interface\\MacroFrame\\MacroFrame-Icon"
Suite.ORDRE = {
    { cle = "CraftCore", icone = "Interface\\Icons\\INV_Misc_Gear_01" },
    { cle = "QuestCore", icone = "Interface\\Icons\\INV_Misc_Book_08" },
    { cle = "MapCore", icone = "Interface\\Icons\\INV_Misc_Map_01" },
    { cle = "LegacyCore", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    -- Les hauts faits (finir le jeu, des points pour chaque haut fait) :
    -- dans la colonne, au-dessus de StuffCore ; montre s'il est installe.
    { cle = "GloryCore", icone = "Interface\\Icons\\INV_Misc_Ribbon_01", discret = true },
    -- Mon equipement et les caisses : un add-on a part (servi par CraftCore).
    { cle = "StuffCore", icone = "Interface\\Icons\\INV_Chest_Chain" },
    -- Une petite aide : les add-ons amis (itineraires detailles...).
    { cle = "FriendsCore", icone = "Interface\\Icons\\Spell_Nature_FarSight", discret = true, complement = true },
    -- Discret : montre seulement s'il est installe (pas dans la premiere
    -- version publiee).
    { cle = "TradeCore", icone = "Interface\\Icons\\INV_Misc_Coin_02", discret = true, complement = true },
    -- Le JcJ (carte de champ de bataille, honneur) : discret tant qu'il n'est
    -- pas publie (montre seulement s'il est installe).
    { cle = "PvPCore", icone = "Interface\\Icons\\INV_BannerPVP_02", discret = true, complement = true },
    -- Ma classe (quetes de classe, sorts, talents, familiers) : en beta,
    -- publie avec la suite.
    { cle = "ClassCore", icone = "Interface\\Icons\\INV_Misc_Book_09", discret = true, complement = true },
}

-- ---------------------------------------------------------------------------
-- Les complements : les outils a part de la suite. Un seul bouton en bas de
-- la colonne de gauche (au-dessus d'Alliance / Horde) ; dans une fenetre de
-- complement, la colonne de droite montre tous les complements en onglets.
-- ---------------------------------------------------------------------------
Suite.ICONE_COMPLEMENTS = "Interface\\Icons\\INV_Misc_EngGizmos_01"
-- Le nom montre d'un add-on : son nom d'usage s'il en a un, sinon le nom
-- de son dossier.
function Suite.NomAffiche(cle)
    for _, info in ipairs(Suite.ORDRE or {}) do
        if info.cle == cle and info.nom then return info.nom end
    end
    return cle
end
function Suite.Complements()
    local liste = {}
    local function Ajouter(cle, icone, action)
        table.insert(liste, { cle = cle, icone = icone, action = action })
    end
    -- Les vrais outils d'abord (auras, macros, echanges, JcJ),
    -- FriendsCore, le petit plus, tout en bas.
    if Suite.membres.AuraCore or (_G.SlashCmdList and _G.SlashCmdList.AURACORE) then
        Ajouter("AuraCore", "Interface\\Icons\\Spell_Holy_AuraOfLight", function()
            if Suite.membres.AuraCore then Suite.Ouvrir("AuraCore")
            elseif SlashCmdList.AURACORE then SlashCmdList.AURACORE("") end
        end)
    end
    if Suite.Prive and Suite.Prive() then Ajouter("Macros", Suite.ICONE_MACROCORE, function() Suite.OuvrirMacros() end) end
    for _, cle in ipairs({ "ClassCore", "TradeCore", "PvPCore" }) do
        if Suite.membres[cle] then
            for _, info in ipairs(Suite.ORDRE) do if info.cle == cle then Ajouter(cle, info.icone) end end
        end
    end
    if Suite.membres.FriendsCore then
        Ajouter("FriendsCore", "Interface\\Icons\\Spell_Nature_FarSight")
        liste[#liste].apart = true
    end
    return liste
end
local CLES_COMPLEMENTS = { FriendsCore = true, AuraCore = true, Macros = true, TradeCore = true, PvPCore = true, ClassCore = true }
function Suite.EstComplement(cle) return cle ~= nil and CLES_COMPLEMENTS[cle] == true end
-- Ouvre un complement (et ferme la fenetre de complement d'ou l'on vient).
function Suite.OuvrirComplement(cle, depuis)
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.dernierComplement = cle
    -- La nouvelle fenetre prend exactement la place de celle qu'on quitte.
    local point
    if depuis and depuis.GetPoint and depuis:IsShown() then
        local a, rel, b, x, y = depuis:GetPoint(1)
        if a then point = { a, rel, b, x, y } end
    end
    if depuis and depuis.Hide then depuis:Hide() end
    for _, c in ipairs(Suite.Complements()) do
        if c.cle == cle then
            if c.action then c.action() else Suite.Ouvrir(cle) end
            local m = Suite.membres[cle]
            local f = m and m.fenetre and m.fenetre()
            if point and f and f.ClearAllPoints then
                f:ClearAllPoints()
                f:SetPoint(point[1], point[2], point[3], point[4], point[5])
            end
            return
        end
    end
end
-- Le bouton Complements : le dernier complement ouvert, sinon le premier.
function Suite.OuvrirComplements(depuis)
    local liste = Suite.Complements()
    if #liste == 0 then return end
    local cle = type(CoreSuiteDB) == "table" and CoreSuiteDB.dernierComplement
    local trouve
    for _, c in ipairs(liste) do if c.cle == cle then trouve = c.cle end end
    Suite.OuvrirComplement(trouve or liste[1].cle, depuis)
end
-- Les add-ons annonces des leur chargement (avant les fenetres).
Suite.presents = Suite.presents or {}
function Suite.Annoncer(cle) Suite.presents[cle] = true end

-- Complements de la suite (AuraCore) : publies aussi seuls. Sans aucun des
-- add-ons principaux, la suite se reduit a eux (fenetre generale, reglages,
-- langues), sans les onglets des add-ons absents.
function Suite.Seul()
    local charge = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    for _, info in ipairs(Suite.ORDRE) do
        if not info.discret then
            if Suite.presents[info.cle] or Suite.membres[info.cle] then return false end
            if charge then
                local ok, oui = pcall(charge, info.cle)
                if ok and oui then return false end
            end
        end
    end
    return true
end

-- Les add-ons a montrer : tous, sauf les discrets absents.
function Suite.Liste()
    if Suite.Seul() then return {} end
    local liste = {}
    for _, info in ipairs(Suite.ORDRE) do
        -- Les complements ont leur bouton a part, en bas de la colonne.
        if not info.complement and (not info.discret or Suite.presents[info.cle] or Suite.membres[info.cle]) then
            table.insert(liste, info)
        end
    end
    return liste
end
local function N() return #Suite.Liste() end

-- ---------------------------------------------------------------------------
-- Langue de la suite : celle du jeu par defaut, ou celle choisie dans les
-- reglages generaux (commune aux quatre add-ons). Les textes de ce fichier
-- se traduisent ici ; ceux de chaque add-on dans son dossier Locale.
-- ---------------------------------------------------------------------------

Suite.LANGUES = {
    { code = "enUS", nom = "English" }, { code = "frFR", nom = "Français" }, { code = "deDE", nom = "Deutsch" },
    { code = "esES", nom = "Español" }, { code = "itIT", nom = "Italiano" }, { code = "ruRU", nom = "Русский" },
    { code = "zhCN", nom = "简体中文" },
}
local CORRESPONDANCE = { esMX = "esES", zhTW = "zhCN", enGB = "enUS" }
function Suite.CodeLangue(code)
    code = code or (GetLocale and GetLocale()) or "enUS"
    code = CORRESPONDANCE[code] or code
    for _, l in ipairs(Suite.LANGUES) do if l.code == code then return code end end
    return "enUS"
end
-- La langue en vigueur : le choix des reglages generaux, sinon celle du jeu.
function Suite.Langue()
    local choix = type(CoreSuiteDB) == "table" and CoreSuiteDB.langue or nil
    return Suite.CodeLangue(choix)
end

local DICO = {
    frFR = {
        ["Show or hide everything"] = "Tout afficher ou tout masquer",
        ["Open"] = "Ouvrir",
        ["Change guide"] = "Changer de guide",
        ["Stop"] = "Arrêter",
        ["Cancel"] = "Annuler",
        ["Next"] = "Suivante",
        ["Level %d"] = "Niveau %d",
        ["Route add-ons"] = "Add-ons d'itinéraire",
        ["Shortest Path Forever and TomTom draw a detailed route. Install them with CurseForge or WowUp, then restart the game : they become available here."] = "Shortest Path Forever et TomTom tracent un itinéraire détaillé. Installez-les avec CurseForge ou WowUp, puis relancez le jeu : ils deviennent disponibles ici.",
        ["Greyed : add-on not installed (see the i)."] = "Grisé : add-on non installé (voir le i).",
        ["Who guides you?"] = "Qui vous guide ?",
        ["You can change it later in FriendsCore."] = "Vous pourrez changer dans FriendsCore.",
        ["Follow the route of"] = "Suivez l'itinéraire de",
        ["Step %d of %d"] = "Étape %d sur %d",
        ["Forever SagaCore Dev is not installed."] = "Forever SagaCore Dev n'est pas installé.",
        ["Back to the normal suite."] = "Retour à la suite normale.",
        ["Switching to Forever SagaCore Dev."] = "Passage à Forever SagaCore Dev.",
        ["Forever SagaCore Live is not installed."] = "Forever SagaCore Live n'est pas installé.",
        ["Switching to Forever SagaCore Live."] = "Passage à Forever SagaCore Live, la version publiée.",
        ["Click: show everything"] = "Clic : tout afficher",
        ["Click: hide everything"] = "Clic : tout masquer",
        ["Faction theme"] = "Thème de faction",
        ["Add-ons"] = "Compléments",
        ["The suite's other tools."] = "Les autres outils de la suite.",
        ["Character's faction"] = "Faction du personnage",
        ["Alliance theme"] = "Thème Alliance",
        ["Horde theme"] = "Thème Horde",
        ["Hover to pick an add-on"] = "Survolez pour choisir un add-on",
        ["Drag: move"] = "Glisser : déplacer",
        ["Right-click: show or hide the suite bar"] = "Clic droit : montrer ou cacher la barre de la suite",
        ["Not installed"] = "Pas installé",
        ["Click: open"] = "Clic : ouvrir",
        ["A: open"] = "A : ouvrir",
        ["(locked: moves only here)"] = "(ancrée : se déplace seulement ici)",
        ["Quests: pick up and turn in"] = "Quêtes : à prendre et à rendre",
        ["Creatures to kill"] = "Créatures à tuer",
        ["Loot to collect"] = "Butin à ramasser",
        ["Objects to use and places to visit"] = "Objets à utiliser et lieux à visiter",
        ["Herbalism: gathering spots"] = "Herboristerie : lieux de récolte",
        ["Mining: veins"] = "Minage : filons",
        ["Fishing: fishing spots"] = "Pêche : lieux de pêche",
        ["My markers"] = "Mes repères",
        ["Click: show or hide"] = "Clic : afficher ou masquer",
        ["Right-click: show only this"] = "Clic droit : n'afficher que ça",
        ["Right-click: show everything"] = "Clic droit : tout réafficher",
        ["Hidden"] = "Masqué",
        ["Click: pick the herbs or ores to show"] = "Clic : choisir les herbes ou minerais à montrer",
        ["From the GatherMate2 database"] = "D'après la base GatherMate2",
        ["Spotted here, not gathered yet"] = "Repéré ici, pas encore récolté",
        ["Gathered %d times here"] = "Récolté %d fois ici",
        ["Path guidance"] = "Guidage du trajet",
        ["Drag: move up or down. Right-click: stop guiding."] = "Glisser : monter ou descendre. Clic droit : arrêter le guidage.",
        ["Out of range"] = "Hors de portée",
        ["General settings"] = "Réglages généraux",
        ["Settings"] = "Réglages",
        ["Parameters"] = "Paramètres",
        ["Contents"] = "Contenu",
        ["Common to the whole suite."] = "Communs à toute la suite.",
        ["Language"] = "Langue",
        ["Game language"] = "Langue du jeu",
        ["Apply (reloads the interface)"] = "Appliquer (recharge l'interface)",
        ["Close"] = "Fermer",
        ["Gamepad : D-pad to move, A click, X right-click, Y stop guidance, B to exit"] = "Manette : croix pour se déplacer, A clic, X clic droit, Y arrête le guidage, B pour sortir",
        ["Not in combat."] = "Pas en combat.",
        ["No tracking window is open."] = "Aucune fenêtre de suivi n'est ouverte.",
    },
    deDE = {
        ["Show or hide everything"] = "Alles anzeigen oder ausblenden",
        ["Click: show everything"] = "Klick: alles anzeigen",
        ["Click: hide everything"] = "Klick: alles ausblenden",
        ["Faction theme"] = "Fraktionsdesign",
        ["Character's faction"] = "Fraktion des Charakters",
        ["Alliance theme"] = "Allianz-Design",
        ["Horde theme"] = "Horde-Design",
        ["Hover to pick an add-on"] = "Darüberfahren, um ein Add-on zu wählen",
        ["Drag: move"] = "Ziehen: verschieben",
        ["Right-click: show or hide the suite bar"] = "Rechtsklick: Leiste der Suite ein- oder ausblenden",
        ["Not installed"] = "Nicht installiert",
        ["Click: open"] = "Klick: öffnen",
        ["A: open"] = "A: öffnen",
        ["(locked: moves only here)"] = "(fixiert: nur hier verschiebbar)",
        ["Quests: pick up and turn in"] = "Quests: annehmen und abgeben",
        ["Creatures to kill"] = "Zu tötende Kreaturen",
        ["Loot to collect"] = "Zu sammelnde Beute",
        ["Objects to use and places to visit"] = "Zu benutzende Objekte und zu besuchende Orte",
        ["Herbalism: gathering spots"] = "Kräuterkunde: Fundorte",
        ["Mining: veins"] = "Bergbau: Vorkommen",
        ["Fishing: fishing spots"] = "Angeln: Angelplätze",
        ["My markers"] = "Meine Markierungen",
        ["Click: show or hide"] = "Klick: ein- oder ausblenden",
        ["Right-click: show only this"] = "Rechtsklick: nur dies anzeigen",
        ["Right-click: show everything"] = "Rechtsklick: alles wieder anzeigen",
        ["Hidden"] = "Ausgeblendet",
        ["Click: pick the herbs or ores to show"] = "Klick: anzuzeigende Kräuter oder Erze wählen",
        ["From the GatherMate2 database"] = "Aus der GatherMate2-Datenbank",
        ["Spotted here, not gathered yet"] = "Hier gesichtet, noch nicht gesammelt",
        ["Gathered %d times here"] = "Hier %d-mal gesammelt",
        ["Path guidance"] = "Wegführung",
        ["Drag: move up or down. Right-click: stop guiding."] = "Ziehen: nach oben oder unten. Rechtsklick: Führung beenden.",
        ["Out of range"] = "Außer Reichweite",
        ["General settings"] = "Allgemeine Einstellungen",
        ["Settings"] = "Einstellungen",
        ["Common to the whole suite."] = "Gelten für die ganze Suite.",
        ["Language"] = "Sprache",
        ["Game language"] = "Spielsprache",
        ["Apply (reloads the interface)"] = "Übernehmen (lädt die Oberfläche neu)",
        ["Close"] = "Schließen",
    },
    esES = {
        ["Show or hide everything"] = "Mostrar u ocultar todo",
        ["Click: show everything"] = "Clic: mostrar todo",
        ["Click: hide everything"] = "Clic: ocultar todo",
        ["Faction theme"] = "Tema de facción",
        ["Character's faction"] = "Facción del personaje",
        ["Alliance theme"] = "Tema de la Alianza",
        ["Horde theme"] = "Tema de la Horda",
        ["Hover to pick an add-on"] = "Pasa el ratón para elegir un accesorio",
        ["Drag: move"] = "Arrastrar: mover",
        ["Right-click: show or hide the suite bar"] = "Clic derecho: mostrar u ocultar la barra de la suite",
        ["Not installed"] = "No instalado",
        ["Click: open"] = "Clic: abrir",
        ["A: open"] = "A: abrir",
        ["(locked: moves only here)"] = "(anclado: solo se mueve aquí)",
        ["Quests: pick up and turn in"] = "Misiones: aceptar y entregar",
        ["Creatures to kill"] = "Criaturas que matar",
        ["Loot to collect"] = "Botín que recoger",
        ["Objects to use and places to visit"] = "Objetos que usar y lugares que visitar",
        ["Herbalism: gathering spots"] = "Herboristería: puntos de recolección",
        ["Mining: veins"] = "Minería: filones",
        ["Fishing: fishing spots"] = "Pesca: zonas de pesca",
        ["My markers"] = "Mis marcas",
        ["Click: show or hide"] = "Clic: mostrar u ocultar",
        ["Right-click: show only this"] = "Clic derecho: mostrar solo esto",
        ["Right-click: show everything"] = "Clic derecho: mostrarlo todo",
        ["Hidden"] = "Oculto",
        ["Click: pick the herbs or ores to show"] = "Clic: elegir las hierbas o minerales que mostrar",
        ["From the GatherMate2 database"] = "Según la base de datos de GatherMate2",
        ["Spotted here, not gathered yet"] = "Visto aquí, aún no recolectado",
        ["Gathered %d times here"] = "Recolectado %d veces aquí",
        ["Path guidance"] = "Guía de ruta",
        ["Drag: move up or down. Right-click: stop guiding."] = "Arrastrar: subir o bajar. Clic derecho: detener la guía.",
        ["Out of range"] = "Fuera de alcance",
        ["General settings"] = "Ajustes generales",
        ["Settings"] = "Ajustes",
        ["Common to the whole suite."] = "Comunes a toda la suite.",
        ["Language"] = "Idioma",
        ["Game language"] = "Idioma del juego",
        ["Apply (reloads the interface)"] = "Aplicar (recarga la interfaz)",
        ["Close"] = "Cerrar",
    },
    itIT = {
        ["Show or hide everything"] = "Mostra o nascondi tutto",
        ["Click: show everything"] = "Clic: mostra tutto",
        ["Click: hide everything"] = "Clic: nascondi tutto",
        ["Faction theme"] = "Tema di fazione",
        ["Character's faction"] = "Fazione del personaggio",
        ["Alliance theme"] = "Tema dell'Alleanza",
        ["Horde theme"] = "Tema dell'Orda",
        ["Hover to pick an add-on"] = "Passa sopra per scegliere un add-on",
        ["Drag: move"] = "Trascina: sposta",
        ["Right-click: show or hide the suite bar"] = "Clic destro: mostra o nascondi la barra della suite",
        ["Not installed"] = "Non installato",
        ["Click: open"] = "Clic: apri",
        ["A: open"] = "A: apri",
        ["(locked: moves only here)"] = "(bloccato: si sposta solo qui)",
        ["Quests: pick up and turn in"] = "Missioni: da prendere e da consegnare",
        ["Creatures to kill"] = "Creature da uccidere",
        ["Loot to collect"] = "Bottino da raccogliere",
        ["Objects to use and places to visit"] = "Oggetti da usare e luoghi da visitare",
        ["Herbalism: gathering spots"] = "Erbalismo: punti di raccolta",
        ["Mining: veins"] = "Estrazione: filoni",
        ["Fishing: fishing spots"] = "Pesca: zone di pesca",
        ["My markers"] = "I miei segnaposto",
        ["Click: show or hide"] = "Clic: mostra o nascondi",
        ["Right-click: show only this"] = "Clic destro: mostra solo questo",
        ["Right-click: show everything"] = "Clic destro: mostra tutto",
        ["Hidden"] = "Nascosto",
        ["Click: pick the herbs or ores to show"] = "Clic: scegli le erbe o i minerali da mostrare",
        ["From the GatherMate2 database"] = "Dal database di GatherMate2",
        ["Spotted here, not gathered yet"] = "Avvistato qui, non ancora raccolto",
        ["Gathered %d times here"] = "Raccolto %d volte qui",
        ["Path guidance"] = "Guida del percorso",
        ["Drag: move up or down. Right-click: stop guiding."] = "Trascina: sposta su o giù. Clic destro: ferma la guida.",
        ["Out of range"] = "Fuori portata",
        ["General settings"] = "Impostazioni generali",
        ["Settings"] = "Impostazioni",
        ["Common to the whole suite."] = "Comuni a tutta la suite.",
        ["Language"] = "Lingua",
        ["Game language"] = "Lingua del gioco",
        ["Apply (reloads the interface)"] = "Applica (ricarica l'interfaccia)",
        ["Close"] = "Chiudi",
    },
    ruRU = {
        ["Show or hide everything"] = "Показать или скрыть всё",
        ["Click: show everything"] = "Клик: показать всё",
        ["Click: hide everything"] = "Клик: скрыть всё",
        ["Faction theme"] = "Оформление фракции",
        ["Character's faction"] = "Фракция персонажа",
        ["Alliance theme"] = "Оформление Альянса",
        ["Horde theme"] = "Оформление Орды",
        ["Hover to pick an add-on"] = "Наведите, чтобы выбрать модификацию",
        ["Drag: move"] = "Перетащить: переместить",
        ["Right-click: show or hide the suite bar"] = "ПКМ: показать или скрыть панель набора",
        ["Not installed"] = "Не установлено",
        ["Click: open"] = "Щелчок: открыть",
        ["A: open"] = "A: открыть",
        ["(locked: moves only here)"] = "(закреплено: перемещается только здесь)",
        ["Quests: pick up and turn in"] = "Задания: взять и сдать",
        ["Creatures to kill"] = "Существа, которых нужно убить",
        ["Loot to collect"] = "Добыча, которую нужно собрать",
        ["Objects to use and places to visit"] = "Предметы для использования и места для посещения",
        ["Herbalism: gathering spots"] = "Травничество: места сбора",
        ["Mining: veins"] = "Горное дело: залежи",
        ["Fishing: fishing spots"] = "Рыбная ловля: места ловли",
        ["My markers"] = "Мои метки",
        ["Click: show or hide"] = "Щелчок: показать или скрыть",
        ["Right-click: show only this"] = "ПКМ: показать только это",
        ["Right-click: show everything"] = "ПКМ: показать всё",
        ["Hidden"] = "Скрыто",
        ["Click: pick the herbs or ores to show"] = "Щелчок: выбрать травы или руды",
        ["From the GatherMate2 database"] = "По базе данных GatherMate2",
        ["Spotted here, not gathered yet"] = "Замечено здесь, ещё не собрано",
        ["Gathered %d times here"] = "Собрано здесь %d раз",
        ["Path guidance"] = "Навигация по маршруту",
        ["Drag: move up or down. Right-click: stop guiding."] = "Перетащить: вверх или вниз. ПКМ: остановить навигацию.",
        ["Out of range"] = "Вне досягаемости",
        ["General settings"] = "Общие настройки",
        ["Settings"] = "Настройки",
        ["Common to the whole suite."] = "Общие для всего набора.",
        ["Language"] = "Язык",
        ["Game language"] = "Язык игры",
        ["Apply (reloads the interface)"] = "Применить (перезагрузка интерфейса)",
        ["Close"] = "Закрыть",
    },
    zhCN = {
        ["Show or hide everything"] = "全部显示或隐藏",
        ["Click: show everything"] = "点击：全部显示",
        ["Click: hide everything"] = "点击：全部隐藏",
        ["Faction theme"] = "阵营主题",
        ["Character's faction"] = "角色的阵营",
        ["Alliance theme"] = "联盟主题",
        ["Horde theme"] = "部落主题",
        ["Hover to pick an add-on"] = "悬停以选择插件",
        ["Drag: move"] = "拖动：移动",
        ["Right-click: show or hide the suite bar"] = "右键：显示或隐藏套件栏",
        ["Not installed"] = "未安装",
        ["Click: open"] = "点击：打开",
        ["A: open"] = "A：打开",
        ["(locked: moves only here)"] = "（已锁定：只能在此移动）",
        ["Quests: pick up and turn in"] = "任务：接取与交付",
        ["Creatures to kill"] = "需要击杀的生物",
        ["Loot to collect"] = "需要拾取的物品",
        ["Objects to use and places to visit"] = "需要使用的物体和需要前往的地点",
        ["Herbalism: gathering spots"] = "草药学：采集点",
        ["Mining: veins"] = "采矿：矿脉",
        ["Fishing: fishing spots"] = "钓鱼：钓鱼点",
        ["My markers"] = "我的标记",
        ["Click: show or hide"] = "点击：显示或隐藏",
        ["Right-click: show only this"] = "右键：只显示这一项",
        ["Right-click: show everything"] = "右键：全部显示",
        ["Hidden"] = "已隐藏",
        ["Click: pick the herbs or ores to show"] = "点击：选择要显示的草药或矿石",
        ["From the GatherMate2 database"] = "来自 GatherMate2 数据库",
        ["Spotted here, not gathered yet"] = "在此发现，尚未采集",
        ["Gathered %d times here"] = "在此采集了 %d 次",
        ["Path guidance"] = "路线指引",
        ["Drag: move up or down. Right-click: stop guiding."] = "拖动：上下移动。右键：停止指引。",
        ["Out of range"] = "超出范围",
        ["General settings"] = "通用设置",
        ["Settings"] = "设置",
        ["Common to the whole suite."] = "适用于整个套件。",
        ["Language"] = "语言",
        ["Game language"] = "游戏语言",
        ["Apply (reloads the interface)"] = "应用（重新载入界面）",
        ["Close"] = "关闭",
    },
}

-- Un texte de la suite, dans la langue en vigueur (anglais a defaut).
local function TX(texte)
    local d = DICO[Suite.Langue()]
    return (d and d[texte]) or texte
end
Suite.TX = TX

-- Table de textes traduits au moment ou on les lit (la langue choisie n'est
-- connue qu'une fois les reglages charges).
local function Paresseux(source)
    return setmetatable({}, { __index = function(_, cle)
        local texte = source[cle]
        return texte and TX(texte) or nil
    end })
end

-- ---------------------------------------------------------------------------
-- Theme de faction : le decor des zones sombres (suivis, menus de gauche)
-- porte l'embleme de l'Alliance ou de la Horde, gris et discret. Par defaut,
-- la faction du personnage connecte ; on peut en forcer une.
-- ---------------------------------------------------------------------------

-- Fonctions privees (theme force, TradeCore, mode developpeur) : visibles
-- seulement sur le poste de l'auteur, apres /sagacore prive. Les joueurs
-- n'en voient rien : le theme suit simplement la faction du personnage.
function Suite.Prive()
    return type(CoreSuiteDB) == "table" and CoreSuiteDB.prive == true
end

-- /sagacore : ouvre la suite la ou on l'avait laissee (dernier add-on,
-- derniere page), ou la referme. /sagacore prive : options privees.
SLASH_FOREVERSAGACORE1 = "/sagacore"
SlashCmdList.FOREVERSAGACORE = function(arg)
    arg = (arg or ""):lower()
    if arg:match("^%s*prive%s*$") then
        CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
        CoreSuiteDB.prive = not CoreSuiteDB.prive or nil
        if ReloadUI then ReloadUI() end
        return
    end
    -- /sagacore oui | non : la reponse au dernier message de la suite.
    local M = _G.SagaCoreMessages
    if M and (arg:match("^%s*oui%s*$") or arg:match("^%s*yes%s*$")) then M.Repondre(true) return end
    if M and (arg:match("^%s*non%s*$") or arg:match("^%s*no%s*$")) then M.Repondre(false) return end
    if M and arg:match("^%s*messages%s*$") then M.OuvrirReglages() return end
    -- /sagacore <raccourci> : chaque raccourci de la suite (voir plus bas).
    local r = Suite.Raccourci and Suite.Raccourci(arg:match("^%s*(%S+)%s*$"))
    if r then Suite.Lancer(r) return end
    -- /sagacore stop : arrete le guidage en cours (a mettre dans une macro).
    if arg:match("^%s*stop%s*$") then Suite.Arreter("joueur") return end
    -- /sagacore suivis : piloter les fenetres de suivi a la manette.
    if arg:match("^%s*suivis?%s*$") then Suite.Piloter() return end
    if arg:match("^%s*macros%s*$") then Suite.OuvrirMacros() return end
    if arg:match("^%s*$") then
        local S = _G.CoreSuite
        if S and S.BasculerDernier then
            local premier
            for _, info in ipairs(S.Liste()) do
                if S.Installe(info.cle) then premier = info.cle break end
            end
            S.BasculerDernier(premier)
        end
    end
end

-- Police d'une ecriture non latine. Le jeu sait afficher le chinois ou le
-- russe avec ses polices de base (elles ont une police de secours pour
-- chaque ecriture), mais une police posee a la main par son fichier perd ce
-- secours : les caracteres deviennent des carres. Pour ces langues, on prend
-- le fichier de la police de secours du jeu.
local ECRITURES = { zhCN = "simplifiedchinese", zhTW = "traditionalchinese", ruRU = "russian", koKR = "korean" }
function Suite.FichierPolice(fichier)
    local ecriture = ECRITURES[Suite.Langue and Suite.Langue() or ""]
    if not ecriture then return fichier end
    local base = _G.GameFontNormal
    if base and base.GetFontObjectForAlphabet then
        local ok, objet = pcall(base.GetFontObjectForAlphabet, base, ecriture)
        if ok and objet and objet.GetFont then
            local f = objet:GetFont()
            if f then return f end
        end
    end
    return fichier
end

-- Le theme suit la faction du personnage. Les onglets Alliance / Horde
-- (prives) permettent de voir l'autre le temps de la session.
function Suite.Theme()
    if Suite.themeSession then return Suite.themeSession end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Horde" and "horde" or "alliance"
end

-- Illustration de faction du jeu, pour les zones sombres : celles du
-- panneau JcJ du jeu (un nain sous la banniere de l'Alliance, un orc sous
-- celle de la Horde). Recadree pour remplir la zone sans deformer, assombrie
-- pour que le texte reste lisible. Rend faux si le client n'a pas l'image.
local ILLUSTRATIONS = {
    alliance = {
        { fichier = "Interface\\PVPFrame\\PvPQueueBackgroundAlliance", l = 324 / 512, h = 231 / 256, ratio = 324 / 231, foyer = 0.75 },
        { fichier = "Interface\\LFGFrame\\UI-PVP-BACKGROUND-Alliance", l = 1, h = 1, ratio = 2, foyer = 0.75 },
    },
    horde = {
        { fichier = "Interface\\PVPFrame\\PvPQueueBackgroundHorde", l = 324 / 512, h = 231 / 256, ratio = 324 / 231, foyer = 0.75 },
        { fichier = "Interface\\LFGFrame\\UI-PVP-BACKGROUND-Horde", l = 1, h = 1, ratio = 2, foyer = 0.75 },
    },
}
Suite.LUMIERE_FOND = 0.6
Suite.GRIS_FOND = 0.7

local function Recadrer(tex)
    local im = tex.suiteIllustration
    if not im then return end
    -- Un panneau entier, avec son cadre : jamais rogne.
    if im.etirer then tex:SetTexCoord(0, im.l, 0, im.h) return end
    local w, h = tex:GetWidth() or 0, tex:GetHeight() or 0
    if w <= 0 or h <= 0 then tex:SetTexCoord(0, im.l, 0, im.h) return end
    local zone = w / h
    if zone < im.ratio then
        -- Zone plus haute que l'image : on garde toute la hauteur, on coupe
        -- les cotes autour du foyer.
        local part = zone / im.ratio
        local g = math.max(0, math.min(1 - part, im.foyer - part / 2))
        tex:SetTexCoord(g * im.l, (g + part) * im.l, 0, im.h)
    else
        local part = im.ratio / zone
        local hautP = (1 - part) / 2
        tex:SetTexCoord(0, im.l, hautP * im.h, (hautP + part) * im.h)
    end
end

-- Le panneau du menu de gauche : "1", "2" (dessines) ou "jeu" (illustration
-- du jeu). Commun a la suite.
-- Panneaux dessines pour la suite (dossier Media de CraftCore), en couleur,
-- au choix quelle que soit la faction.
local MEDIA = "Interface\\AddOns\\CraftCore\\Media\\"
Suite.PANNEAUX = {
    { cle = "bleu", fr = "Bleu dépoli", en = "Matte blue", fichier = MEDIA .. "menu_bleu" },
    { cle = "bleuvif", fr = "Bleu vif", en = "Bright blue", fichier = MEDIA .. "menu_bleu_vif" },
    { cle = "rouge", fr = "Rouge dépoli", en = "Matte red", fichier = MEDIA .. "menu_rouge" },
    { cle = "rougevif", fr = "Rouge vif", en = "Bright red", fichier = MEDIA .. "menu_rouge_vif" },
}

-- Parametrage par defaut (case cochee par defaut) : parchemin gris de la
-- faction, panneau depoli de la faction, suivis gris. Decochee, les choix
-- de l'utilisateur s'appliquent.
function Suite.ParDefaut()
    return not (type(CoreSuiteDB) == "table" and CoreSuiteDB.interfaceParDefaut == false)
end
function Suite.PoserParDefaut(oui)
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    if oui then CoreSuiteDB.interfaceParDefaut = nil else CoreSuiteDB.interfaceParDefaut = false end
    Suite.RafraichirInterface()
end
-- Repose fond, parchemins, panneaux et suivis partout dans la suite.
function Suite.RafraichirInterface()
    local charte = NS.charte
    if charte and charte.RafraichirParchemins then pcall(charte.RafraichirParchemins) end
    pcall(Suite.AppliquerTheme)
    for _, t in ipairs(_G.SagaCoreMenus or {}) do if t.reappliquer then pcall(t.reappliquer) end end
    for _, f in ipairs(Suite.rappelsFondSuivis or {}) do pcall(f) end
    pcall(Suite.RedessinerTout)
end
-- Le fichier du panneau choisi, ou nil pour l'illustration du jeu.
function Suite.PanneauMenu()
    local choix = Suite.PanneauChoisi()
    for _, p in ipairs(Suite.PANNEAUX) do if p.cle == choix then return p.fichier end end
    return nil
end
function Suite.PanneauChoisi()
    if Suite.ParDefaut() then return Suite.Theme() == "horde" and "rouge" or "bleu" end
    local v = type(CoreSuiteDB) == "table" and CoreSuiteDB.panneauMenu or nil
    if v == "jeu" then return v end
    for _, p in ipairs(Suite.PANNEAUX) do if p.cle == v then return v end end
    -- Par defaut : le panneau 5 de la faction.
    return Suite.Theme() == "horde" and "rouge" or "bleu"
end
function Suite.OptionsPanneau()
    local fr = Suite.Langue() == "frFR"
    local o = {}
    for _, p in ipairs(Suite.PANNEAUX) do table.insert(o, { p.cle, fr and p.fr or p.en }) end
    table.insert(o, { "jeu", fr and "Illustration du jeu" or "Game artwork" })
    return o
end
function Suite.PoserPanneau(v)
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.panneauMenu = v
    pcall(Suite.AppliquerTheme)
    -- Les menus de gauche de toutes les fenetres de la suite.
    for _, t in ipairs(_G.SagaCoreMenus or {}) do if t.reappliquer then pcall(t.reappliquer) end end
end

-- Compositions : le fond de la fenetre, celui des suivis et le panneau du
-- menu, enregistres ensemble sous un nom, pour les remettre d'un coup.
function Suite.Compositions()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.compositions = type(CoreSuiteDB.compositions) == "table" and CoreSuiteDB.compositions or {}
    return CoreSuiteDB.compositions
end
function Suite.OptionsComposition()
    local fr = Suite.Langue() == "frFR"
    local o = {}
    for i, c in ipairs(Suite.Compositions()) do table.insert(o, { i, c.nom }) end
    if #o == 0 then table.insert(o, { 0, fr and "Aucune enregistrée" or "None saved" }) end
    return o
end
function Suite.CompositionChoisie()
    local v = type(CoreSuiteDB) == "table" and CoreSuiteDB.compositionActive or nil
    if v and Suite.Compositions()[v] then return v end
    return #Suite.Compositions() > 0 and 0 or 0
end
local function CharteDeLaSuite() return NS.charte end
function Suite.AppliquerComposition(i)
    local c = Suite.Compositions()[i]
    if not c then return end
    CoreSuiteDB.compositionActive = i
    CoreSuiteDB.interfaceParDefaut = false
    local charte = CharteDeLaSuite()
    if charte and charte.PoserFondComplet and c.fond then pcall(charte.PoserFondComplet, c.fond) end
    if charte and charte.PoserFondDesSuivis and c.suivis then pcall(charte.PoserFondDesSuivis, c.suivis) end
    if c.panneau then pcall(Suite.PoserPanneau, c.panneau) end
end
function Suite.SauverComposition()
    local charte = CharteDeLaSuite()
    local liste = Suite.Compositions()
    local fr = Suite.Langue() == "frFR"
    local c = {
        nom = string.format(fr and "Ma composition %d" or "My setup %d", #liste + 1),
        fond = charte and charte.FondComplet and charte.FondComplet() or nil,
        suivis = charte and charte.FondDesSuivis and charte.FondDesSuivis() or nil,
        panneau = Suite.PanneauChoisi(),
    }
    table.insert(liste, c)
    CoreSuiteDB.compositionActive = #liste
    return c
end

Suite.fondsFaction = Suite.fondsFaction or {}
function Suite.FondDeFaction(tex)
    if not tex then return false end
    if not tex.suiteFondFaction then
        tex.suiteFondFaction = true
        table.insert(Suite.fondsFaction, tex)
        local parent = tex:GetParent()
        if parent and parent.HookScript then
            pcall(parent.HookScript, parent, "OnSizeChanged", function() Recadrer(tex) end)
        end
    end
    local choix = Suite.PanneauChoisi()
    local ordre = {}
    for _, p in ipairs(Suite.PANNEAUX) do
        if p.cle == choix then
            table.insert(ordre, { fichier = p.fichier, l = 1, h = 1, ratio = 0.31, etirer = true, couleur = true })
        end
    end
    for _, im in ipairs(ILLUSTRATIONS[Suite.Theme()] or {}) do table.insert(ordre, im) end
    for _, im in ipairs(ordre) do
        -- Le jeu accepte n'importe quel chemin ; seul GetTexture dit si
        -- l'image existe vraiment dans ce client.
        if pcall(tex.SetTexture, tex, im.fichier) and tex:GetTexture() then
            tex.suiteIllustration = im
            if im.couleur then
                -- Panneau dessine : en pleine couleur, et son embleme remplace
                -- le demi-logo du menu.
                if tex.SetDesaturation then tex:SetDesaturation(0) else tex:SetDesaturated(false) end
                tex:SetVertexColor(1, 1, 1)
                if not Suite.panneauEnCouleur then
                    Suite.panneauEnCouleur = true
                    for _, lg in ipairs(Suite.logos) do pcall(Suite.Logo, lg) end
                end
            else
                -- A demi grise : l'image reste reconnaissable sans crier.
                if tex.SetDesaturation then tex:SetDesaturation(Suite.GRIS_FOND) else tex:SetDesaturated(true) end
                local v = Suite.LUMIERE_FOND
                tex:SetVertexColor(v, v, v)
            end
            tex:SetAlpha(1)
            Recadrer(tex)
            tex:Show()
            return true
        end
    end
    tex.suiteIllustration = nil
    return false
end

-- Logo de la faction, en couleur adoucie : le blason du jeu (celui du
-- chronometre des champs de bataille), pose sur les zones sombres.
local LOGOS = { alliance = "Interface\\Timer\\Alliance-Logo", horde = "Interface\\Timer\\Horde-Logo" }
Suite.ALPHA_LOGO = 0.25
Suite.GRIS_LOGO = 0.4
Suite.TAILLE_LOGO = 230
Suite.HAUT_LOGO = 70
Suite.ECART_TRAIT = 14
Suite.logos = Suite.logos or {}
-- moitie : seule la moitie gauche du blason, coupee net par un trait.
function Suite.Logo(tex, alpha, moitie)
    if not tex then return false end
    if not tex.suiteLogo then
        tex.suiteLogo = true
        tex.suiteAlpha = alpha
        tex.suiteMoitie = moitie
        table.insert(Suite.logos, tex)
    end
    local ok = pcall(tex.SetTexture, tex, LOGOS[Suite.Theme()] or LOGOS.alliance)
    -- Le blason occupe le centre du fichier : on rogne le vide autour.
    tex:SetTexCoord(0.17, tex.suiteMoitie and 0.5 or 0.83, 0.1, 0.9)
    if tex.SetDesaturation then tex:SetDesaturation(Suite.GRIS_LOGO) end
    tex:SetVertexColor(1, 1, 1)
    tex:SetAlpha(tex.suiteAlpha or Suite.ALPHA_LOGO)
    -- Le demi-logo du menu s'efface devant un panneau qui a deja son embleme.
    -- Plus de demi-logo de faction dans le menu (embleme de Blizzard).
    tex:SetShown(ok and not tex.suiteMasque and not tex.suiteMoitie)
    return ok
end

-- Logo en bas de la colonne de menu. Le menu peut naitre apres l'en-tete :
-- on reessaie a chaque actualisation.
function Suite.LogoDuMenu(cadre)
    if not cadre or cadre.suiteLogoMenu or not cadre.menu then return end
    -- A cheval sur le trait qui separe le menu du contenu : on n'en voit que
    -- la moitie gauche, en bas de la colonne.
    -- Dans le fond interieur, couche ARTWORK : au-dessus de l'illustration
    -- du menu et du trait, sous les lignes du menu.
    local porteur = CreateFrame("Frame", nil, cadre)
    porteur:SetAllPoints(cadre)
    porteur:SetFrameLevel(math.max(1, cadre.menu:GetFrameLevel()))
    local t = porteur:CreateTexture(nil, "BACKGROUND", nil, 7)
    t:SetSize(Suite.TAILLE_LOGO / 2, Suite.TAILLE_LOGO * 1.2)
    -- Le trait lui-meme quand la fenetre le garde (CraftCore), sinon le bord
    -- du menu plus l'ecart commun a la suite.
    if cadre.trait then
        t:SetPoint("BOTTOMRIGHT", cadre.trait, "BOTTOMLEFT", 1, Suite.HAUT_LOGO)
    else
        t:SetPoint("BOTTOMRIGHT", cadre.menu, "BOTTOMRIGHT", Suite.ECART_TRAIT, Suite.HAUT_LOGO)
    end
    cadre.suiteLogoMenu = t
    Suite.Logo(t, nil, true)
end

-- Redessine toutes les fenetres ouvertes de la suite (changement de fond).
function Suite.RedessinerTout()
    for _, m in pairs(Suite.membres or {}) do
        local f = m.fenetre and m.fenetre()
        if f and f:IsShown() and m.ouvrir then
            -- Rouvrir sans fermer : chaque add-on se redessine a l'ouverture.
            if f.Rendre then pcall(f.Rendre) end
        end
    end
    for _, w in pairs(Suite.fenetresAPages or {}) do if w.Rendre then pcall(w.Rendre) end end
end

function Suite.AppliquerTheme()
    -- Les fonds d'abord : ils disent si le demi-logo doit s'effacer.
    Suite.panneauEnCouleur = false
    for _, tex in ipairs(Suite.fondsFaction) do
        if not Suite.FondDeFaction(tex) and NS.charte and NS.charte.FondDuJournal then
            pcall(NS.charte.FondDuJournal, tex)
        end
    end
    for _, tex in ipairs(Suite.logos) do pcall(Suite.Logo, tex) end
    for _, rappel in ipairs(Suite.rappelsFondSuivis or {}) do pcall(rappel) end
    Suite.RendreFactions()
end

-- Onglets Alliance / Horde : celui de la faction regardee s'allume.
function Suite.RendreFactions()
    for _, rangee in ipairs(Suite.entetes or {}) do
        for _, b in ipairs(rangee.factions or {}) do
            local actif = b.faction == Suite.Theme()
            -- Sans personnage de cette faction : grise, sans effet.
            local possible = actif or b.faction == Suite.FactionDuJoueur() or #Suite.PersosDeFaction(b.faction) > 0
            b:SetChecked(actif)
            b:SetEnabled(possible)
            b.icone:SetDesaturated(not possible)
            local v = actif and 1 or 0.55
            b.icone:SetVertexColor(v, v, v)
        end
    end
end

-- Faction d'un personnage connu de la suite ("alliance", "horde" ou nil).
local function SourcesDePersos()
    local cc = type(_G.CraftCoreDB) == "table" and _G.CraftCoreDB.personnages
    local qc = type(_G.QuestCoreDB) == "table" and _G.QuestCoreDB.persos
    local lc = type(_G.LegacyCoreDB) == "table" and _G.LegacyCoreDB.persos
    return { type(cc) == "table" and cc or {}, type(qc) == "table" and qc or {}, type(lc) == "table" and lc or {} }
end

function Suite.FactionDe(cle)
    for _, src in ipairs(SourcesDePersos()) do
        local f = type(src[cle]) == "table" and src[cle].faction
        if f == "Alliance" or f == "Horde" then return f:lower() end
    end
    return nil
end

function Suite.FactionDuJoueur()
    return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "horde" or "alliance"
end

-- Un personnage se montre-t-il ? Ceux de la faction regardee, et ceux dont
-- la faction n'est pas encore connue.
function Suite.Visible(cle)
    local f = Suite.FactionDe(cle)
    return f == nil or f == Suite.Theme()
end

-- Les personnages d'une faction, le connecte d'abord, puis par nom.
function Suite.PersosDeFaction(faction)
    local vus, liste = {}, {}
    for _, src in ipairs(SourcesDePersos()) do
        for cle in pairs(src) do
            if type(cle) == "string" and cle:find(" %- ") and not vus[cle] and Suite.FactionDe(cle) == faction then
                vus[cle] = true
                table.insert(liste, cle)
            end
        end
    end
    local courant = NS.ClePersonnage and NS.ClePersonnage()
    table.sort(liste, function(a, b)
        if (a == courant) ~= (b == courant) then return a == courant end
        return a < b
    end)
    return liste
end

-- ---------------------------------------------------------------------------
-- La barre des personnages : une seule pour toute la suite
-- ---------------------------------------------------------------------------
-- Une liste (Suite.ListePersos), un portrait (Suite.PoserVisagePerso), une
-- barre (Suite.BandePersos). Chaque add-on la pose dans son en-tete et dit
-- seulement quoi faire au clic : memes personnages, meme ordre, meme
-- aspect partout.

local function JetonDe(f)
    if type(f) ~= "table" then return nil end
    if type(f.jetonClasse) == "string" then return f.jetonClasse end
    local c = f.classe
    if type(c) == "string" and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[c] then return c end
    if type(c) == "string" then
        for _, noms in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
            for jeton, nom in pairs(type(noms) == "table" and noms or {}) do if nom == c then return jeton end end
        end
    end
    return nil
end

-- Tous les personnages connus de la suite (une entree par nom), de la
-- faction regardee : le connecte d'abord, puis par nom.
function Suite.ListePersos()
    local parNom, ordre = {}, {}
    for _, src in ipairs(SourcesDePersos()) do
        for cle, f in pairs(src) do
            local nom = type(cle) == "string" and cle:match("^(%S+) %- .")
            if nom and type(f) == "table" then
                local p = parNom[nom]
                if not p then
                    p = { cle = cle, nom = nom }
                    parNom[nom] = p
                    table.insert(ordre, p)
                end
                p.classe = p.classe or JetonDe(f)
                local n = tonumber(f.niveau)
                if n and n > (p.niveau or 0) then p.niveau = n end
            end
        end
    end
    local courant = NS.ClePersonnage and NS.ClePersonnage()
    local nomCourant = courant and courant:match("^(%S+) %- ")
    local liste = {}
    for _, p in ipairs(ordre) do
        if p.nom == nomCourant then p.cle = courant end
        p.moi = p.nom == nomCourant
        if Suite.Visible(p.cle) then table.insert(liste, p) end
    end
    table.sort(liste, function(a, b)
        if a.moi ~= b.moi then return a.moi end
        return a.nom < b.nom
    end)
    return liste
end

-- Le portrait d'un personnage, en trois calques : l'icone de classe, le
-- vrai portrait du personnage connecte, l'image deposee dans
-- SagaCorePortraits (un fichier absent ne dessine rien).
local function Calque(texture, cle, rang)
    local c = texture[cle]
    if c then return c end
    local couche, sous = texture:GetDrawLayer()
    c = texture:GetParent():CreateTexture(nil, couche or "ARTWORK", nil, math.min(7, (sous or 0) + rang))
    c:SetAllPoints(texture)
    texture[cle] = c
    if hooksecurefunc then hooksecurefunc(texture, "Hide", function() c:Hide() end) end
    return c
end
-- Le seul endroit de la suite qui pose un portrait de personnage : partout
-- (bande, lignes, cartes, banniere), le vrai portrait est pose dans le
-- cercle de sa classe, un peu plus petit, et le cercle de couleur en fait
-- le tour, de la meme epaisseur. taille : la largeur de la texture, si elle
-- n'est pas encore mesurable.
function Suite.PoserVisagePerso(texture, p, taille)
    local vivant = Calque(texture, "calqueVivant", 1)
    local depose = Calque(texture, "calqueDepose", 2)
    vivant:Hide() depose:Hide()
    local w = taille or texture:GetWidth()
    if not w or w <= 0 then w = texture:GetHeight() end
    if not w or w <= 0 then w = 29 end
    local r = math.floor(w * 0.2 + 0.5)
    for _, c in ipairs({ vivant, depose }) do
        if c.SetMask and not c.rond then c.rond = true pcall(c.SetMask, c, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", texture, "TOPLEFT", r, -r)
        c:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", -r, r)
    end
    pcall(texture.SetTexCoord, texture, 0, 1, 0, 1)
    -- L'icone ronde de la classe, celle du jeu (recherche de groupe, cadre
    -- de cible), dans un anneau a la couleur de la classe.
    local rond = Suite.IconeRondeDeClasse(texture, p.classe)
    local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
    if not rond then
        if coords then
            texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        else
            texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    -- L'anneau de couleur : seulement autour du vrai portrait (l'icone ronde
    -- du jeu a deja le sien).
    local anneau = texture:GetParent() and texture:GetParent().anneauClasse
    if anneau then
        local c = _G.RAID_CLASS_COLORS and p.classe and _G.RAID_CLASS_COLORS[p.classe]
        anneau:SetDesaturated(c ~= nil)
        if c then anneau:SetVertexColor(c.r, c.g, c.b) else anneau:SetVertexColor(1, 1, 1) end
        anneau:SetShown(p.moi == true or not rond)
    end
    if p.moi and SetPortraitTexture and pcall(SetPortraitTexture, vivant, "player") then vivant:Show() end
    local ok, reussi = pcall(depose.SetTexture, depose, "Interface\\AddOns\\SagaCorePortraits\\" .. tostring(p.nom))
    if ok and reussi ~= false then depose:Show() end
end

-- L'icone ronde de classe du jeu, celle de la recherche de groupe : un
-- cercle a la couleur de la classe, son embleme dedans. Rend true si le
-- client la connait (atlas), et la pose.
local ATLAS_CLASSE = { "groupfinder-icon-class-%s", "classicon-%s", "GarrMission_ClassIcon-%s" }
function Suite.IconeRondeDeClasse(texture, classe)
    if not (texture and texture.SetAtlas and type(classe) == "string") then return false end
    local info = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    local noms = {}
    for _, modele in ipairs(ATLAS_CLASSE) do table.insert(noms, string.format(modele, string.lower(classe))) end
    -- Le nom que le client donne lui-meme pour cette classe.
    local okA, duJeu = pcall(_G.GetClassAtlas or function() end, classe)
    if okA and type(duJeu) == "string" then table.insert(noms, 2, duJeu) end
    for _, nom in ipairs(noms) do
        local a = info and info(nom)
        if a and a.file and a.leftTexCoord then
            texture:SetTexture(a.file)
            texture:SetTexCoord(a.leftTexCoord, a.rightTexCoord, a.topTexCoord, a.bottomTexCoord)
            -- Le liseré sombre du bord ote par un masque rond un peu plus
            -- petit : un vrai cercle, sans bord plat, juste la couleur.
            Suite.ArrondirSansBord(texture)
            return true
        elseif not info then
            local ok, pose = pcall(texture.SetAtlas, texture, nom)
            if ok and pose ~= false then return true end
        end
    end
    return false
end

-- Masque rond pose un peu en dedans du bord (ote le liseré sombre).
-- Suite.RetirerRond le retire quand la texture sert a autre chose.
function Suite.ArrondirSansBord(texture)
    local parent = texture.GetParent and texture:GetParent()
    if not (parent and parent.CreateMaskTexture and texture.AddMaskTexture) then return end
    local m = texture.masqueRond
    if not m then
        local ok, cree = pcall(parent.CreateMaskTexture, parent)
        if not ok or not cree then return end
        m = cree
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture.masqueRond = m
    end
    local w = texture:GetWidth()
    if not w or w <= 0 then w = 18 end
    local r = math.max(1, w * 0.08)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", texture, "TOPLEFT", r, -r)
    m:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", -r, r)
    if not texture.masqueRondActif then
        pcall(texture.AddMaskTexture, texture, m)
        texture.masqueRondActif = true
    end
end
function Suite.RetirerRond(texture)
    if texture and texture.masqueRond and texture.masqueRondActif and texture.RemoveMaskTexture then
        pcall(texture.RemoveMaskTexture, texture, texture.masqueRond)
        texture.masqueRondActif = false
    end
end

-- Un visage rond : la texture masquee en cercle et un anneau a la couleur
-- de la classe autour (le meme que la bande des personnages). Pour les
-- lignes de personnage des fenetres.
function Suite.AnneauDeClasse(texture, classe)
    if not (texture and texture.GetParent) then return end
    if texture.anneauRond then texture.anneauRond:Hide() end
    if Suite.IconeRondeDeClasse(texture, classe) then return true end
    local a = texture.anneauRond
    if not a then
        a = texture:GetParent():CreateTexture(nil, "OVERLAY")
        a:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        texture.anneauRond = a
        if hooksecurefunc then
            hooksecurefunc(texture, "Hide", function() a:Hide() end)
            hooksecurefunc(texture, "Show", function() a:Show() end)
        end
    end
    local w = texture:GetWidth()
    if not w or w <= 0 then w = 24 end
    a:ClearAllPoints()
    a:SetSize(w * 1.7, w * 1.7)
    a:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
    local c = _G.RAID_CLASS_COLORS and classe and _G.RAID_CLASS_COLORS[classe]
    a:SetDesaturated(c ~= nil)
    if c then a:SetVertexColor(c.r, c.g, c.b) else a:SetVertexColor(1, 1, 1) end
    a:SetShown(texture:IsShown())
end

local TAILLE_PORTRAIT_BANDE = 29
local function PortraitDeBande(bande)
    local b = CreateFrame("Button", nil, bande)
    b:SetSize(TAILLE_PORTRAIT_BANDE, TAILLE_PORTRAIT_BANDE)
    -- Rond, comme les classes de la recherche de groupe : le visage dans un
    -- cercle, un anneau a la couleur de la classe.
    b.cadre = b:CreateTexture(nil, "BACKGROUND")
    b.cadre:SetAllPoints()
    b.cadre:SetColorTexture(0, 0, 0, 0)
    -- Tous de la meme taille : le cercle de classe remplit le bouton ; le
    -- vrai portrait se pose dedans, un peu plus petit, et le cercle de
    -- couleur en fait le tour.
    b.visage = b:CreateTexture(nil, "ARTWORK")
    b.visage:SetAllPoints()
    b.portraitDansCercle = true
    b.halo = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.halo:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b.halo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
    b.halo:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.halo:SetBlendMode("ADD")
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- La barre, dans `bande` (un cadre de l'en-tete). o.choisi : la cle
-- montree ; o.auClic(cle) ; o.infobulle(cle, GameTooltip) pour ajouter des
-- lignes. Rend la liste des cles (ordre de la croix gauche / droite) et le
-- dernier portrait.
function Suite.BandePersos(bande, o)
    o = o or {}
    bande.boutonsSuite = bande.boutonsSuite or {}
    for _, b in ipairs(bande.boutonsSuite) do b:Hide() end
    local liste, cles = Suite.ListePersos(), {}
    local choisi = o.choisi
    local nomChoisi = type(choisi) == "string" and choisi:match("^(%S+) %- ")
    local dernier
    for rang, p in ipairs(liste) do
        local b = bande.boutonsSuite[rang]
        if not b then b = PortraitDeBande(bande) bande.boutonsSuite[rang] = b end
        b:ClearAllPoints()
        b:SetPoint("LEFT", bande, "LEFT", 2 + (rang - 1) * (TAILLE_PORTRAIT_BANDE + 6), 0)
        Suite.PoserVisagePerso(b.visage, p)
        -- Le personnage choisi en couleur ; les autres en gris, en
        -- sous-brillance. Pas de halo.
        local estChoisi = p.nom == nomChoisi
        b.halo:Hide()
        b:SetAlpha(estChoisi and 1 or 0.6)
        for _, t in ipairs({ b.visage, b.visage.calqueVivant, b.visage.calqueDepose }) do
            if t then t:SetDesaturated(not estChoisi) end
        end
        local perso = p
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local c = _G.RAID_CLASS_COLORS and perso.classe and _G.RAID_CLASS_COLORS[perso.classe]
            GameTooltip:SetText(perso.nom, c and c.r or 1, c and c.g or 0.82, c and c.b or 0)
            if perso.niveau then GameTooltip:AddLine(string.format(TX("Level %d"), perso.niveau), 1, 1, 1) end
            if o.infobulle then pcall(o.infobulle, perso.cle, GameTooltip) end
            GameTooltip:Show()
        end)
        b:SetScript("OnClick", function()
            if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            if o.auClic then o.auClic(perso.cle) end
        end)
        b.cle = perso.cle
        b:Show()
        table.insert(cles, perso.cle)
        dernier = b
    end
    -- A la manette : la croix gauche / droite passe d'un personnage a
    -- l'autre, dit juste apres le dernier portrait.
    if not bande.indicePad then bande.indicePad = bande:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
    bande.indicePad:ClearAllPoints()
    if dernier then bande.indicePad:SetPoint("LEFT", dernier, "RIGHT", 10, 0) end
    local G = Suite.GlyphePad or function(t) return t end
    bande.indicePad:SetText(G("PADDLEFT") .. " " .. G("PADDRIGHT"))
    bande.indicePad:SetShown(dernier ~= nil and Suite.ManetteActive and Suite.ManetteActive() and true or false)
    return cles, dernier
end

-- Le personnage a montrer pour la faction regardee.
function Suite.PersoDeLaFaction()
    local courant = NS.ClePersonnage and NS.ClePersonnage()
    if Suite.Theme() == Suite.FactionDuJoueur() then return courant end
    return Suite.PersosDeFaction(Suite.Theme())[1]
end

-- Pour la session seulement : a la prochaine connexion, la faction du
-- personnage reprend la main. nil : la faction du personnage. Les fenetres
-- ouvertes passent sur un personnage de la faction regardee.
function Suite.PoserTheme(v)
    if v == Suite.FactionDuJoueur() then v = nil end
    Suite.themeSession = (v == "alliance" or v == "horde") and v or nil
    local cle = Suite.PersoDeLaFaction()
    if cle and Suite.PoserPersonnage then Suite.PoserPersonnage(cle) end
    Suite.AppliquerTheme()
    for _, m in pairs(Suite.membres or {}) do
        local f = m.fenetre and m.fenetre()
        if f and f:IsShown() then
            f:Hide()
            pcall(m.ouvrir)
        end
    end
end

local T = Paresseux({
    survol = "Hover to pick an add-on",
    deplacer = "Drag: move",
    barre = "Right-click: show or hide the suite bar",
    absent = "Not installed",
    ouvrir = "Click: open",
    manette = "A: open",
    ancree = "(locked: moves only here)",
})

local function Reglages()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    local d = CoreSuiteDB
    if type(d.angle) ~= "number" then d.angle = 215 end
    if d.barreAffichee == nil then d.barreAffichee = true end
    -- AchievementCore s'appelle desormais GloryCore (dossier et cle).
    if d.dernierComplement == "AchievementCore" then d.dernierComplement = nil end
    if d.dernier == "AchievementCore" then d.dernier = "GloryCore" end
    return d
end

-- ---------------------------------------------------------------------------
-- Inscription et ouverture
-- ---------------------------------------------------------------------------

-- membre : { titre, ouvrir = fonction, fenetre = fonction rendant le cadre,
--            boutonMinicarte = son ancien bouton (cache par la suite) }
function Suite.Inscrire(cle, membre)
    Suite.membres[cle] = membre
    if membre.boutonMinicarte then
        local b = membre.boutonMinicarte
        b:Hide()
        b:HookScript("OnShow", function(self) self:Hide() end)
    end
    if Suite.Actualiser then Suite.Actualiser() end
end

function Suite.Installe(cle) return Suite.membres[cle] ~= nil end

-- ---------------------------------------------------------------------------
-- Ancrage des fenetres de suivi, et mode Edition du jeu
-- ---------------------------------------------------------------------------
--
-- Une fenetre ancree ne se deplace ni ne se redimensionne plus. En mode
-- Edition du jeu (Echap, Mode Edition), toutes les fenetres de la suite se
-- deverrouillent et s'entourent de bleu, comme celles du jeu : on les place,
-- puis en quittant le mode Edition, celles qui sont ancrees se refigent.
-- Chaque add-on garde la position comme d'habitude.

Suite.ancrables = Suite.ancrables or {}

function Suite.EnEdition()
    local e = _G.EditModeManagerFrame
    return e ~= nil and e.IsShown ~= nil and e:IsShown() == true
end

function Suite.Ancree(cle)
    local d = Reglages()
    return type(d.ancres) == "table" and d.ancres[cle] == true
end

-- Peut-on deplacer ou redimensionner cette fenetre maintenant ?
function Suite.Libre(cle) return not Suite.Ancree(cle) or Suite.EnEdition() end

local function Habiller(a)
    if not a.cadre then return end
    local enEdition = Suite.EnEdition() and a.cadre:IsShown()
    if enEdition and not a.voile then
        local v = CreateFrame("Frame", nil, a.cadre)
        v:SetAllPoints()
        v:SetFrameLevel(a.cadre:GetFrameLevel() + 30)
        v.fond = v:CreateTexture(nil, "OVERLAY")
        v.fond:SetAllPoints()
        v.fond:SetColorTexture(0.25, 0.6, 1, 0.22)
        v.texte = v:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v.texte:SetPoint("CENTER")
        v:EnableMouse(false)
        a.voile = v
    end
    if a.voile then
        a.voile.texte:SetText(a.libelle .. (Suite.Ancree(a.cle) and ("\n" .. T.ancree) or ""))
        a.voile:SetShown(enEdition)
    end
    if a.apres then pcall(a.apres) end
end

function Suite.AppliquerAncres()
    for _, a in pairs(Suite.ancrables) do pcall(Habiller, a) end
end

function Suite.PoserAncre(cle, valeur)
    local d = Reglages()
    d.ancres = d.ancres or {}
    d.ancres[cle] = valeur and true or nil
    Suite.AppliquerAncres()
end

-- `apres` : appele quand l'etat change (pour montrer ou cacher une poignee).
function Suite.Ancrable(cle, cadre, libelle, apres)
    Suite.ancrables[cle] = { cle = cle, cadre = cadre, libelle = libelle, apres = apres }
    local e = _G.EditModeManagerFrame
    if e and not Suite.editionSuivie then
        Suite.editionSuivie = true
        e:HookScript("OnShow", function() Suite.AppliquerAncres() end)
        e:HookScript("OnHide", function() Suite.AppliquerAncres() end)
    end
    cadre:HookScript("OnShow", function() pcall(Habiller, Suite.ancrables[cle]) end)
    pcall(Habiller, Suite.ancrables[cle])
end

-- ---------------------------------------------------------------------------
-- Personnage affiche, le meme dans toute la suite
-- ---------------------------------------------------------------------------
--
-- Garde pour la session seulement : a chaque connexion, chaque add-on repart
-- sur le personnage connecte. Un choix fait dans un add-on vaut pour les
-- autres. `persoVersion` change a chaque choix : un add-on n'applique le
-- choix commun que s'il est plus recent que le sien.

function Suite.Personnage() return Suite.perso, Suite.persoVersion end

function Suite.PoserPersonnage(cle)
    Suite.perso = cle
    Suite.persoVersion = (Suite.persoVersion or 0) + 1
    return Suite.persoVersion
end

-- Une seule fenetre de la suite a la fois : celle qui s'ouvre prend la place
-- exacte d'une autre deja ouverte, qui se ferme. Appele a chaque ouverture,
-- quel que soit le chemin (bouton, commande, clic sur un repere...).
function Suite.PrendrePlace(cle, cadre)
    if not cadre then return end
    for autre, m in pairs(Suite.membres) do
        local f = autre ~= cle and m.fenetre and m.fenetre()
        if f and f ~= cadre and f:IsShown() then
            local point, relatif, pointRelatif, x, y = f:GetPoint(1)
            f:Hide()
            if point then
                cadre:ClearAllPoints()
                cadre:SetPoint(point, relatif or UIParent, pointRelatif or point, x or 0, y or 0)
            end
        end
    end
    Reglages().dernier = cle
end

-- Raccourci de la suite : ferme la fenetre ouverte, sinon rouvre le dernier
-- add-on utilise (la ou on l'avait laisse), a defaut `defaut`.
function Suite.BasculerDernier(defaut)
    for _, m in pairs(Suite.membres) do
        local f = m.fenetre and m.fenetre()
        if f and f:IsShown() then f:Hide() return end
    end
    local d = Reglages()
    local cible = (d.dernier and Suite.Installe(d.dernier)) and d.dernier or defaut
    if cible then Suite.Ouvrir(cible) end
end

-- Ouvre un add-on (ou le ferme s'il est deja seul ouvert).
function Suite.Ouvrir(cle)
    local cible = Suite.membres[cle]
    if not cible then return end
    local f = cible.fenetre and cible.fenetre()
    if f and f:IsShown() then
        f:Hide()
        return
    end
    pcall(cible.ouvrir)
    f = cible.fenetre and cible.fenetre()
    if f then Suite.PrendrePlace(cle, f) end
    if Suite.Actualiser then Suite.Actualiser() end
end

-- ---------------------------------------------------------------------------
-- Icones des add-ons (rond de minicarte du jeu)
-- ---------------------------------------------------------------------------

local function IconeRonde(parent, taille, info)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(taille, taille)
    b:RegisterForClicks("LeftButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(taille * 0.65, taille * 0.65)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(taille * 0.6, taille * 0.6)
    b.icone:SetPoint("CENTER")
    b.icone:SetTexture(info.icone)
    if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(taille * 1.7, taille * 1.7)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.cle = info.cle
    b:SetScript("OnClick", function(self) Suite.Ouvrir(self.cle) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Suite.NomAffiche(self.cle), 1, 0.82, 0)
        if Suite.Installe(self.cle) then
            GameTooltip:AddLine(T.ouvrir, 1, 1, 1)
        else
            GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Grise ce qui n'est pas installe, eclaire l'add-on ouvert.
local function Teinter(b)
    local installe = Suite.Installe(b.cle)
    b.icone:SetDesaturated(not installe)
    b:SetAlpha(installe and 1 or 0.45)
    b:SetEnabled(installe)
end

-- Icones carrees, pour l'en-tete des fenetres.
local function IconeCarree(parent, info)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.icone:SetTexture(info.icone)
    b.halo = b:CreateTexture(nil, "OVERLAY")
    b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.halo:SetBlendMode("ADD")
    b.halo:SetPoint("TOPLEFT", -2, 2)
    b.halo:SetPoint("BOTTOMRIGHT", 2, -2)
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.cle = info.cle
    b:SetScript("OnClick", function(self) Suite.Ouvrir(self.cle) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(Suite.NomAffiche(self.cle), 1, 0.82, 0)
        if not self.extra and not Suite.Installe(self.cle) then GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- ---------------------------------------------------------------------------
-- Dans chaque fenetre : les icones, en haut a droite de l'en-tete
-- ---------------------------------------------------------------------------

Suite.entetes = Suite.entetes or {}

-- Contour des onglets lateraux (dessin du grimoire, gris de lui-meme) :
-- teinte au brun des fenetres du jeu. Le meme partout dans la suite.
function Suite.TeinteOnglet(texture)
    if texture and texture.SetVertexColor then texture:SetVertexColor(0.95, 0.74, 0.5) end
end

local function OngletLateral(parent, info, auClic)
    -- L'onglet du grimoire du jeu, dessin retourne pour le bord gauche :
    -- c'est un fichier (pas un atlas), le retournement tient. Meme dessin
    -- que les onglets des membres du groupe, a cote du suivi des quetes.
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(34, 34)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    b.fond:SetTexCoord(1, 0, 0, 1)
    Suite.TeinteOnglet(b.fond)
    b.fond:SetSize(68, 68)
    b.fond:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 12)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.icone:SetTexture(info.icone)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local halo = b:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    b:SetScript("OnClick", function(self)
        self:SetChecked(self.cle == self.courante)
        auClic()
    end)
    b.cle = info.cle
    b:HookScript("OnEnter", function(self)
        self.survol = true
        if self.icone then self.icone:SetVertexColor(1, 1, 1) end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(Suite.NomAffiche(self.cle), 1, 0.82, 0)
        if not Suite.Installe(self.cle) then GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function(self)
        self.survol = false
        if self.icone and self.cle ~= self.courante then self.icone:SetVertexColor(0.55, 0.55, 0.55) end
        GameTooltip:Hide()
    end)
    return b
end

-- ---------------------------------------------------------------------------
-- Acces direct depuis les fenetres du jeu (essai, mode prive seulement) : dans
-- chaque fenetre officielle liee a un add-on de la suite, un onglet du jeu en
-- bas a droite ouvre cet add-on. Metiers et fenetre d'un metier : CraftCore ;
-- fiche du personnage : StuffCore ; journal de quetes : QuestCore ; carte du
-- monde : MapCore (et QuestCore quand le journal y est ouvert).
-- ---------------------------------------------------------------------------
Suite.ACCES_JEU = {
    { fenetres = { "ProfessionsBookFrame", "ProfessionsFrame", "TradeSkillFrame" }, cles = { "CraftCore" } },
    { fenetres = { "CharacterFrame" }, cles = { "StuffCore" } },
    { fenetres = { "QuestLogFrame" }, cles = { "QuestCore" } },
    { fenetres = { "WorldMapFrame" }, cles = { "MapCore", "QuestCore" } },
}
local function IconeDe(cle)
    for _, info in ipairs(Suite.ORDRE) do if info.cle == cle then return info.icone end end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function OngletJeu(fenetre, cle, rang)
    fenetre.suiteAcces = fenetre.suiteAcces or {}
    local b = fenetre.suiteAcces[cle]
    if not b then
        b = CreateFrame("Button", nil, fenetre)
        b:SetSize(32, 32)
        -- L'onglet lateral du grimoire du jeu, tel quel (bord droit).
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        b.fond:SetSize(64, 64)
        b.fond:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 11)
        b.icone = b:CreateTexture(nil, "ARTWORK")
        b.icone:SetAllPoints()
        b.icone:SetTexture(IconeDe(cle))
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() Suite.Ouvrir(cle) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Suite.NomAffiche(cle), 1, 0.82, 0)
            GameTooltip:AddLine(TX("Open") .. " " .. Suite.NomAffiche(cle), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fenetre.suiteAcces[cle] = b
    end
    b:ClearAllPoints()
    -- En bas a droite, le premier tout en bas, les suivants au-dessus.
    b:SetPoint("BOTTOMLEFT", fenetre, "BOTTOMRIGHT", 0, 40 + (rang - 1) * 48)
    return b
end
function Suite.PoserAccesJeu()
    if not Suite.Prive() then return end
    for _, a in ipairs(Suite.ACCES_JEU) do
        for _, nom in ipairs(a.fenetres) do
            local f = _G[nom]
            if f and f.HookScript and not f.suiteAccesBranche then
                f.suiteAccesBranche = true
                local liste = a.cles
                local function Mettre(self)
                    local rang = 0
                    for _, cle in ipairs(liste) do
                        local b = OngletJeu(self, cle, rang + 1)
                        local ok = Suite.Installe(cle) and Suite.Prive()
                        b:SetShown(ok and true or false)
                        if ok then rang = rang + 1 end
                    end
                end
                pcall(f.HookScript, f, "OnShow", Mettre)
                if f:IsShown() then pcall(Mettre, f) end
            end
        end
    end
end
do
    -- Certaines fenetres du jeu se chargent a la demande : on reessaie a
    -- chaque add-on charge.
    local ecoute = CreateFrame("Frame")
    ecoute:RegisterEvent("PLAYER_LOGIN")
    ecoute:RegisterEvent("ADDON_LOADED")
    ecoute:SetScript("OnEvent", function()
        if _G.CoreSuite ~= Suite then return end
        pcall(Suite.PoserAccesJeu)
    end)
end

-- ---------------------------------------------------------------------------
-- Forever SagaCore Dev (mode prive) : /sagadev passe de la suite normale a sa
-- copie d'essai (dossiers XDev), ou l'inverse, puis recharge l'interface.
-- Jamais les deux suites actives a la fois.
-- ---------------------------------------------------------------------------
Suite.ADDONS_SUITE = { "CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore", "PvPCore", "GloryCore", "ClassCore" }
-- Trois suites cote a cote, une seule active :
--   normale  : les dossiers X ;
--   Dev      : les dossiers XDev, la version d'essai (/sagadev) ;
--   Live     : les dossiers XLive, la derniere version publiee, telle que
--              les joueurs l'ont (/sagalive).
-- Chaque commande bascule vers sa suite, ou revient a la normale si on y est
-- deja. TradeCore (prive, jamais publie) reste coupe en Live.
local MODES_SUITE = { normale = "", dev = "Dev", live = "Live" }
local PRIVES_HORS_LIVE = { "TradeCore" }
function Suite.ModeSuite()
    local A = _G.C_AddOns or {}
    local charge = A.IsAddOnLoaded or _G.IsAddOnLoaded
    if not charge then return "normale" end
    for mode, suffixe in pairs(MODES_SUITE) do
        if suffixe ~= "" then
            for _, n in ipairs(Suite.ADDONS_SUITE) do
                local ok, oui = pcall(charge, n .. suffixe)
                if ok and oui then return mode end
            end
        end
    end
    return "normale"
end
function Suite.BasculerSuite(cible)
    local A = _G.C_AddOns or {}
    local activer = A.EnableAddOn or _G.EnableAddOn
    local couper = A.DisableAddOn or _G.DisableAddOn
    local info = A.GetAddOnInfo or _G.GetAddOnInfo
    if not (activer and couper and info) then return end
    if Suite.ModeSuite() == cible then cible = "normale" end
    local function Existe(n) local ok, nom = pcall(info, n) return ok and nom ~= nil end
    local present = 0
    for _, n in ipairs(Suite.ADDONS_SUITE) do
        if Existe(n .. MODES_SUITE[cible]) then present = present + 1 end
    end
    if present == 0 then
        print("|cffffd100SagaCore|r " .. (cible == "live" and TX("Forever SagaCore Live is not installed.") or TX("Forever SagaCore Dev is not installed.")))
        return
    end
    for _, n in ipairs(Suite.ADDONS_SUITE) do
        for mode, suffixe in pairs(MODES_SUITE) do
            if Existe(n .. suffixe) then
                if mode == cible then pcall(activer, n .. suffixe) else pcall(couper, n .. suffixe) end
            end
        end
    end
    for _, n in ipairs(PRIVES_HORS_LIVE) do
        if Existe(n) then
            if cible == "live" then pcall(couper, n) else pcall(activer, n) end
        end
    end
    local textes = { normale = "Back to the normal suite.", dev = "Switching to Forever SagaCore Dev.",
        live = "Switching to Forever SagaCore Live." }
    print("|cffffd100SagaCore|r " .. TX(textes[cible]))
    if _G.C_UI and _G.C_UI.Reload then _G.C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
end
function Suite.BasculerDev()
    if not Suite.Prive() then return end
    Suite.BasculerSuite("dev")
end
SLASH_SAGACOREDEV1 = "/sagadev"
SlashCmdList["SAGACOREDEV"] = function() Suite.BasculerDev() end
SLASH_SAGACORELIVE1 = "/sagalive"
SlashCmdList["SAGACORELIVE"] = function() if Suite.Prive() then Suite.BasculerSuite("live") end end

-- Point d'attache des onglets lateraux : au ras du bord de la fenetre, a la
-- hauteur du trait qui separe l'en-tete du contenu. Les deux colonnes
-- (suite a gauche, add-on a droite) partent de la meme ligne.
-- Le dessin de l'onglet depasse de 7 points au-dessus de son icone.
Suite.HAUT_ONGLET = -7
Suite.ECART_ENTRE_ONGLETS = 14
function Suite.AncreHaut(cadre, cote)
    cadre.suiteAncres = cadre.suiteAncres or {}
    local a = cadre.suiteAncres[cote]
    if a then return a, cote == "gauche" and "BOTTOMLEFT" or "BOTTOMRIGHT" end
    local ref = cadre.fond or cadre.zone or cadre
    a = CreateFrame("Frame", nil, cadre)
    if cote == "gauche" then
        a:SetPoint("TOPLEFT", cadre, "TOPLEFT", 0, 0)
        a:SetPoint("BOTTOMRIGHT", ref, "TOPLEFT", 0, 0)
    else
        a:SetPoint("TOPRIGHT", cadre, "TOPRIGHT", 0, 0)
        a:SetPoint("BOTTOMLEFT", ref, "TOPRIGHT", 0, 0)
    end
    cadre.suiteAncres[cote] = a
    return a, cote == "gauche" and "BOTTOMLEFT" or "BOTTOMRIGHT"
end

-- Icone d'un bouton de la manette : celle du jeu, a defaut son nom en or.
local GLYPHES_PAD = { PADLSTICK = { "LStickIn", "L3" }, PADRSTICK = { "RStickIn", "R3" } }
local function GlyphePad(touche)
    local g = GLYPHES_PAD[touche] or { touche, touche }
    if GetBindingText then
        local ok, texte = pcall(GetBindingText, touche)
        if ok and type(texte) == "string" and string.find(texte, "|A:", 1, true) then
            return (string.gsub(texte, "|A:([^:|]+)[^|]*|a", "|A:%1:20:20|a"))
        end
    end
    local info = C_Texture and C_Texture.GetAtlasInfo
    if info then
        for _, nom in ipairs({ "Gamepad_Gen_" .. g[1] .. "_64", "Gamepad_Ltr_" .. g[1] .. "_64",
            "Gamepad_Shp_" .. g[1] .. "_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":20:20|a" end
        end
    end
    return "|cffffd100" .. g[2] .. "|r"
end
Suite.GlyphePad = function(t) return GlyphePad(t) end

-- L'encadrement des icones carrees, le meme partout dans la suite : celui
-- du grimoire du jeu (cadre biseaute et sa petite feuille a gauche), sinon
-- celui des boutons d'action. Seulement les images du jeu, rien de dessine.
-- porteur : le cadre de l'icone ; icone : sa texture ; inactif : sort pas
-- appris (le cadre eteint du grimoire). Se rappelle a chaque rendu.
local function AtlasExiste(nom)
    local info = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    local ok, existe = pcall(info or function() end, nom)
    return ok and existe ~= nil
end
function Suite.HabillerIcone(porteur, icone, inactif)
    if not porteur then return end
    local c = porteur.cadreIcone
    if not c then
        c = porteur:CreateTexture(nil, "OVERLAY", nil, 6)
        porteur.cadreIcone = c
    end
    local cible = icone or porteur
    local w = (porteur.GetWidth and porteur:GetWidth()) or 0
    if w <= 0 and cible.GetWidth then w = cible:GetWidth() or 0 end
    if w <= 0 then w = 18 end
    local k = w / 40
    c:ClearAllPoints()
    local nom = inactif and "spellbook-item-iconframe-inactive" or "spellbook-item-iconframe"
    if AtlasExiste(nom) then
        -- Le cadre du grimoire (bouton de 40, icone de 36 au centre) : memes
        -- proportions, a la taille du porteur.
        c:SetAtlas(nom)
        if inactif then
            c:SetPoint("TOPLEFT", porteur, "TOPLEFT", -10 * k, 1 * k)
            c:SetPoint("BOTTOMRIGHT", porteur, "BOTTOMRIGHT", 2 * k, -5 * k)
        else
            c:SetPoint("TOPLEFT", porteur, "TOPLEFT", -11 * k, 1 * k)
            c:SetPoint("BOTTOMRIGHT", porteur, "BOTTOMRIGHT", 1 * k, -7 * k)
        end
        if icone and icone ~= porteur then
            icone:ClearAllPoints()
            -- Un peu en retrait : le bord du cadre reste visible, meme sur
            -- une icone claire.
            icone:SetPoint("TOPLEFT", porteur, "TOPLEFT", 3 * k, -3.5 * k)
            icone:SetPoint("BOTTOMRIGHT", porteur, "BOTTOMRIGHT", -3 * k, 3 * k)
            if icone.SetTexCoord then pcall(icone.SetTexCoord, icone, 0, 1, 0, 1) end
            if not porteur.masqueIcone and porteur.CreateMaskTexture and AtlasExiste("spellbook-item-spellicon-mask") then
                local okM, m = pcall(porteur.CreateMaskTexture, porteur)
                if okM and m then
                    m:SetAtlas("spellbook-item-spellicon-mask")
                    m:SetAllPoints(icone)
                    pcall(icone.AddMaskTexture, icone, m)
                    porteur.masqueIcone = m
                end
            end
        end
    elseif AtlasExiste("UI-HUD-ActionBar-IconFrame") then
        c:SetAtlas("UI-HUD-ActionBar-IconFrame")
        if icone and icone.SetTexCoord then pcall(icone.SetTexCoord, icone, 0.07, 0.93, 0.07, 0.93) end
        c:SetPoint("TOPLEFT", cible, "TOPLEFT", -1, 1)
        c:SetPoint("BOTTOMRIGHT", cible, "BOTTOMRIGHT", 1, -1)
    else
        -- Ancien client : le cadre des boutons d'action classiques.
        if icone and icone.SetTexCoord then pcall(icone.SetTexCoord, icone, 0.07, 0.93, 0.07, 0.93) end
        c:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        c:SetPoint("CENTER", cible, "CENTER", 0, 0)
        c:SetSize(w * 1.78, w * 1.78)
    end
    c:Show()
    return c
end
-- La croix entiere (une seule icone), sinon la fleche du haut.
local function GlypheCroix()
    local info = C_Texture and C_Texture.GetAtlasInfo
    if info then
        for _, nom in ipairs({ "Gamepad_Gen_DPad_64", "Gamepad_Gen_Dpad_64", "Gamepad_Ltr_DPad_64", "Gamepad_Shp_DPad_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":20:20|a" end
        end
    end
    return GlyphePad("PADDUP")
end
Suite.GlypheCroix = GlypheCroix
local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end
Suite.ManetteActive = function() return ManetteActive() end

-- ---------------------------------------------------------------------------
-- Reglages generaux : communs a toute la suite (pour l'instant la langue).
-- Une petite roue dans le pied de chaque fenetre, a gauche de Fermer.
-- ---------------------------------------------------------------------------

function Suite.OuvrirReglagesGeneraux()
    local c = Suite.reglagesGeneraux
    if not c then
        local charte = NS.charte
        if charte and charte.Fenetre then
            c = charte.Fenetre("CoreSuiteReglages", 360, 460, { portrait = false })
        else
            c = CreateFrame("Frame", "CoreSuiteReglages", UIParent, "BasicFrameTemplateWithInset")
            c:SetSize(360, 500)
            c:SetFrameStrata("FULLSCREEN_DIALOG")
        end
        c:SetPoint("CENTER")
        c:SetToplevel(true)
        table.insert(UISpecialFrames, "CoreSuiteReglages")
        local zone = c.zone or c
        c.description = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.description:SetPoint("TOPLEFT", zone, "TOPLEFT", 4, -4)
        c.titreLangue = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        c.titreLangue:SetPoint("TOPLEFT", c.description, "BOTTOMLEFT", 0, -16)
        c.choix = {}
        local options = { { code = nil } }
        for _, l in ipairs(Suite.LANGUES) do table.insert(options, { code = l.code, nom = l.nom }) end
        local precedent = c.titreLangue
        for rang, o in ipairs(options) do
            local okR, b = pcall(CreateFrame, "CheckButton", nil, c, "UIRadioButtonTemplate")
            if not okR or not b then
                -- Sans le modele : le bouton rond du jeu, pose a la main.
                b = CreateFrame("CheckButton", nil, c)
                b:SetSize(16, 16)
                b:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
                b:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
                b:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
                b:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
                b:SetHighlightTexture("Interface\\Buttons\\UI-RadioButton", "ADD")
                b:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
            end
            b:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", rang == 1 and 4 or 0, rang == 1 and -10 or -6)
            b.code = o.code
            b.nom = o.nom
            b.texte = b.text or b.Text or b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.texte:ClearAllPoints()
            b.texte:SetPoint("LEFT", b, "RIGHT", 6, 0)
            b:SetScript("OnClick", function(self)
                c.enAttente = self.code or false
                Suite.RendreReglagesGeneraux()
            end)
            table.insert(c.choix, b)
            precedent = b
        end
        -- Fond : celui que le joueur a choisi (parchemin ou roche grise),
        -- rogne a la taille de la fenetre, jamais etire.
        pcall(Suite.FondChoisi, c)
        local function Bouton(libelle, largeur, voisin)
            if charte and charte.BoutonDePied and c.pied then return charte.BoutonDePied(c, libelle, largeur, voisin) end
            local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
            b:SetSize(largeur, 22)
            if voisin then b:SetPoint("RIGHT", voisin, "LEFT", -6, 0) else b:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -12, 10) end
            b:SetText(libelle)
            return b
        end
        c.fermerBas = Bouton(TX("Close"), 110)
        c.fermerBas:SetScript("OnClick", function() c:Hide() end)
        -- Les messages de la suite dans la discussion.
        c.messages = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        c.messages:SetSize(220, 22)
        c.messages:SetPoint("TOPLEFT", c.choix[#c.choix], "BOTTOMLEFT", -4, -24)
        c.messages:SetScript("OnClick", function()
            local M = _G.SagaCoreMessages
            if M and M.OuvrirReglages then c:Hide() M.OuvrirReglages() end
        end)
        c.macros = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        c.macros:SetSize(220, 22)
        c.macros:SetPoint("TOPLEFT", c.messages, "BOTTOMLEFT", 0, -8)
        c.macros:SetScript("OnClick", function() c:Hide() Suite.OuvrirMacros() end)
        -- Reglage de l'interface : fonds et panneau, pour toute la suite.
        c.interface = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        c.interface:SetSize(220, 22)
        c.interface:SetScript("OnClick", function() c:Hide() Suite.OuvrirInterface() end)
        c.appliquer = Bouton(TX("Apply (reloads the interface)"), 220, c.fermerBas)
        c.appliquer:SetScript("OnClick", function()
            CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
            CoreSuiteDB.langue = c.enAttente or nil
            if ReloadUI then ReloadUI() end
        end)
        -- Manette : croix haut / bas pour choisir, A pour valider, B pour fermer.
        if c.EnableGamePadButton and pcall(c.EnableGamePadButton, c, true) then
            c.focus = 1
            local function Elements()
                local liste = {}
                for _, b in ipairs(c.choix) do table.insert(liste, b) end
                table.insert(liste, c.messages)
                if c.macros:IsShown() then table.insert(liste, c.macros) end
                table.insert(liste, c.interface)
                table.insert(liste, c.appliquer)
                table.insert(liste, c.fermerBas)
                return liste
            end
            c.MarquerFocus = function()
                for rang, b in ipairs(Elements()) do
                    if rang == c.focus then b:LockHighlight() else b:UnlockHighlight() end
                end
            end
            c:SetScript("OnGamePadButtonDown", function(_, bouton)
                local liste = Elements()
                if bouton == "PADDDOWN" then c.focus = math.min(#liste, c.focus + 1)
                elseif bouton == "PADDUP" then c.focus = math.max(1, c.focus - 1)
                elseif bouton == "PAD1" then
                    local b = liste[c.focus]
                    if b and (not b.IsEnabled or b:IsEnabled()) then b:Click() end
                elseif bouton == "PAD2" then c:Hide() return end
                c.MarquerFocus()
            end)
        end
        Suite.reglagesGeneraux = c
    end
    c.focus = 1
    if c.MarquerFocus then c.MarquerFocus() end
    c.enAttente = nil
    c:SetHeight(500)
    Suite.RendreReglagesGeneraux()
    c:Show()
    if c.Raise then c:Raise() end
end

function Suite.RendreReglagesGeneraux()
    local c = Suite.reglagesGeneraux
    if not c then return end
    if c.titre then c.titre:SetText(TX("General settings")) end
    if c.TitleText then c.TitleText:SetText(TX("General settings")) end
    c.description:SetText(TX("Common to the whole suite."))
    c.titreLangue:SetText(TX("Language"))
    if c.messages then
        local M = _G.SagaCoreMessages
        c.messages:SetText(M and M.TX and M.TX("titre") or "Chat messages")
        if M then c.messages:Show() else c.messages:Hide() end
    end
    if c.macros then
        c.macros:SetText(Suite.Langue() == "frFR" and "Macros et raccourcis" or "Macros and shortcuts")
        -- Les macros restent privees pour l'instant.
        c.macros:SetShown(Suite.Prive())
    end
    if c.interface then
        c.interface:SetText(Suite.Langue() == "frFR" and "Réglage de l'interface" or "Interface setup")
        c.interface:ClearAllPoints()
        c.interface:SetPoint("TOPLEFT", (c.macros and c.macros:IsShown()) and c.macros or c.messages, "BOTTOMLEFT", 0, -8)
    end
    local enregistre = type(CoreSuiteDB) == "table" and CoreSuiteDB.langue or nil
    local choisi = enregistre
    if c.enAttente ~= nil then choisi = c.enAttente or nil end
    for _, b in ipairs(c.choix) do
        if b.code then
            b.texte:SetText(b.nom)
        else
            local jeu = Suite.CodeLangue(nil)
            local nomJeu = jeu
            for _, l in ipairs(Suite.LANGUES) do if l.code == jeu then nomJeu = l.nom end end
            b.texte:SetText(TX("Game language") .. " (" .. nomJeu .. ")")
        end
        b:SetChecked(b.code == choisi)
    end
    c.appliquer:SetEnabled(c.enAttente ~= nil and (c.enAttente or nil) ~= enregistre)
    -- Les textes a l'encre sur le parchemin (les boutons gardent les leurs).
    local okF, parchemin = pcall(Suite.MontrerFondChoisi, c)
    local charte = NS.charte
    if okF and c.parchemin and charte and charte.EncrerTextes then
        local textes = { c.description, c.titreLangue }
        for _, b in ipairs(c.choix) do table.insert(textes, b.texte) end
        pcall(charte.EncrerTextes, textes, parchemin == true)
    end
end

-- Bouton Reglages dans le pied, a gauche de Fermer : le meme bouton du jeu.
local function BoutonReglages(cadre)
    if not cadre.pied or cadre.suiteReglages then return end
    local charte = NS.charte
    local b = CreateFrame("Button", nil, cadre.pied, "UIPanelButtonTemplate")
    b:SetSize(110, charte and charte.HAUTEUR_BOUTON or 22)
    b:SetPoint("RIGHT", cadre.pied, "RIGHT", -(110 + (charte and charte.ECART or 8)), 0)
    b:SetText(TX("Settings"))
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(TX("General settings"), 1, 0.82, 0)
        GameTooltip:AddLine(TX("Common to the whole suite."), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() Suite.OuvrirReglagesGeneraux() end)
    cadre.suiteReglages = b
end

-- ---------------------------------------------------------------------------
-- Pied commun a toutes les fenetres de la suite : Commandes et Aide a
-- gauche, Derniere mise a jour au milieu, Reglages et Fermer a droite.
-- Les trois premiers ouvrent la fenetre d'informations de la suite, sur
-- l'onglet voulu (Aide, Commandes, Derniere mise a jour), au-dessus de tout.
-- Une fenetre peut donner sa propre aide (cadre.aideDeLaPage) et ses propres
-- commandes (cadre.lignesDeCommandes : { { touche, ce que ca fait } }).
-- ---------------------------------------------------------------------------
do
    local function TRi(fr, en) return Suite.Langue() == "frFR" and fr or en end
    local function T2(t)
        if type(t) ~= "table" then return t or "" end
        return Suite.Langue() == "frFR" and (t.fr or t[1] or "") or (t.en or t[2] or t.fr or t[1] or "")
    end
    Suite.ONGLETS_INFO = { "aide", "commandes", "nouveautes" }
    local function LibelleInfo(onglet)
        if onglet == "aide" then return TRi("Aide", "Help") end
        if onglet == "commandes" then return TRi("Commandes", "Controls") end
        return TRi("Dernière mise à jour", "Latest update")
    end
    Suite.LibelleInfo = LibelleInfo

    -- Un parchemin du dossier Media (2048 x 1024) pose sans etre etire ni
    -- tasse : la zone garde sa forme, l'image est rognee au centre.
    function Suite.RognerParchemin(p)
        local charte = NS.charte
        if not (p and p.grain and charte and charte.TextureChoisie) then return end
        local def = charte.TextureChoisie()
        if not (def and def.fichier) then return end
        local w, h = p.grain:GetWidth() or 0, p.grain:GetHeight() or 0
        if w <= 0 or h <= 0 then return end
        local ratio = def.ratio or 2
        local zone = w / h
        if zone < ratio then
            local part = zone / ratio
            local g = (1 - part) / 2
            p.grain:SetTexCoord(g, g + part, 0, 1)
        else
            local part = ratio / zone
            local hh = (1 - part) / 2
            p.grain:SetTexCoord(0, 1, hh, hh + part)
        end
    end

    -- Le fond choisi par le joueur (parchemin ou roche grise) dans une petite
    -- fenetre de la suite.
    function Suite.FondChoisi(c)
        local charte = NS.charte
        if not (charte and charte.Parchemin and c and c.fond) then return nil end
        local p = c.parchemin or charte.Parchemin(c, { "TOPLEFT", c.fond, "TOPLEFT", 3, -3 },
            { "BOTTOMRIGHT", c.fond, "BOTTOMRIGHT", -3, 3 }, c.fond)
        if not c.suiteRognage then
            c.suiteRognage = true
            c.fond:HookScript("OnSizeChanged", function() Suite.RognerParchemin(p) end)
        end
        return p
    end
    function Suite.MontrerFondChoisi(c)
        local charte = NS.charte
        local p = c and c.parchemin
        if not (p and charte) then return false end
        local parchemin = charte.Fond and charte.Fond() == "parchemin"
        if parchemin and charte.PoserTextureDeParchemin then
            if not charte.PoserTextureDeParchemin(p.grain, charte.TextureChoisie()) then
                charte.PoserTextureDeParchemin(p.grain, charte.TEXTURES_PARCHEMIN[1])
            end
        end
        p.Montrer(parchemin)
        Suite.RognerParchemin(p)
        return parchemin
    end

    -- -----------------------------------------------------------------------
    -- Les commandes : la fenetre d'abord, puis la manette et la discussion.
    -- -----------------------------------------------------------------------
    local SLASH = {
        CraftCore = { { "/cc", { "Ouvre CraftCore (ou /craftcore)", "Opens CraftCore (or /craftcore)" } },
            { "/cc trouver ...", { "Cherche une recette ou un objet", "Finds a recipe or an item" } } },
        StuffCore = { { "/stuff", { "Ouvre Mon équipement (ou /stuffcore)", "Opens My gear (or /stuffcore)" } } },
        QuestCore = { { "/qc", { "Ouvre QuestCore (ou /questcore)", "Opens QuestCore (or /questcore)" } } },
        MapCore = { { "/mc", { "Ouvre MapCore (ou /mapcore)", "Opens MapCore (or /mapcore)" } } },
        LegacyCore = { { "/lc", { "Ouvre LegacyCore (ou /legacycore)", "Opens LegacyCore (or /legacycore)" } } },
        GloryCore = { { "/glorycore", { "Ouvre GloryCore (ou /ach)", "Opens GloryCore (or /ach)" } },
            { "/ach releve", { "Refait tous les relevés du personnage", "Refreshes all of the character's records" } } },
        ClassCore = { { "/classcore", { "Ouvre ClassCore", "Opens ClassCore" } } },
        AuraCore = { { "/auracore", { "Ouvre AuraCore", "Opens AuraCore" } } },
        PvPCore = { { "/pvpcore", { "Ouvre PvPCore", "Opens PvPCore" } } },
    }
    local function LignesManette()
        local G = GlyphePad
        local l = {}
        local function A(touches, fr, en)
            local t = {}
            for _, k in ipairs(touches) do table.insert(t, G(k)) end
            table.insert(l, { table.concat(t, " "), TRi(fr, en) })
        end
        A({ "PADLSHOULDER", "PADRSHOULDER" }, "Page précédente, page suivante", "Previous page, next page")
        A({ "PADBACK" }, "Entrer dans la page (liseré doré), puis en sortir", "Enter the page (gold border), then leave it")
        A({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }, "Dans la page : choisir ; hors de la page : faire défiler", "In the page : choose ; outside : scroll")
        A({ "PAD1" }, "Valider", "Select")
        A({ "PAD3" }, "Clic droit", "Right click")
        A({ "PADLSTICK", "PADRSTICK" }, "Add-on précédent, add-on suivant (colonne de gauche)", "Previous add-on, next add-on (left column)")
        A({ "PADLTRIGGER", "PADRTRIGGER" }, "Onglet ou complément précédent, suivant (colonne de droite)", "Previous, next tab or companion (right column)")
        A({ "PAD4" }, "Aide", "Help")
        A({ "PADFORWARD" }, "Réglages généraux", "General settings")
        A({ "PAD2" }, "Retour, puis fermer", "Back, then close")
        return l
    end

    -- -----------------------------------------------------------------------
    -- La fenetre d'informations
    -- -----------------------------------------------------------------------
    -- Plus grande que les reglages generaux (360 x 500), plus petite que les
    -- fenetres des add-ons (1060 x 740).
    local LARGEUR_I, HAUTEUR_I = 640, 620
    local LARGEUR_T = LARGEUR_I - 2 * 12 - 2 * 10 - 30

    local function Prendre(f, sorte)
        f.pool[sorte] = f.pool[sorte] or {}
        f.rang[sorte] = (f.rang[sorte] or 0) + 1
        local l = f.pool[sorte][f.rang[sorte]]
        if l then return l end
        local c = f.contenu
        if sorte == "repli" then
            l = CreateFrame("Button", nil, c)
            l:SetHeight(22)
            l.signe = l:CreateTexture(nil, "ARTWORK")
            l.signe:SetSize(14, 14)
            l.signe:SetPoint("LEFT", l, "LEFT", 0, 0)
            l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l.texte:SetPoint("LEFT", l.signe, "RIGHT", 6, 0)
            l.texte:SetJustifyH("LEFT")
            l.texte:SetWordWrap(false)
            l.date = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            l.date:SetPoint("RIGHT", l, "RIGHT", -4, 0)
            l.date:SetJustifyH("RIGHT")
            l.date:SetWordWrap(false)
            l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            l:SetScript("OnClick", function(self)
                f.ouverts[self.cle] = not f.ouverts[self.cle]
                f.focusCle = self.cle
                Suite.RendreInfo()
            end)
        elseif sorte == "deux" then
            l = CreateFrame("Frame", nil, c)
            l.gauche = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            l.gauche:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
            l.gauche:SetWidth(150)
            l.gauche:SetJustifyH("LEFT")
            l.gauche:SetWordWrap(false)
            l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            l.droite:SetPoint("TOPLEFT", l, "TOPLEFT", 160, 0)
            l.droite:SetJustifyH("LEFT")
            l.droite:SetWordWrap(true)
        else
            l = CreateFrame("Frame", nil, c)
            local police = (sorte == "titre" and "GameFontNormal") or (sorte == "detail" and "GameFontDisableSmall") or "GameFontHighlight"
            l.texte = l:CreateFontString(nil, "OVERLAY", police)
            l.texte:SetJustifyH("LEFT")
            l.texte:SetWordWrap(true)
            if l.texte.SetSpacing then l.texte:SetSpacing(2) end
            if sorte == "puce" then
                l.puce = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                l.puce:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
                l.puce:SetText("•")
                l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 14, 0)
            else
                l.texte:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
            end
            if sorte == "titre" then
                l.filet = l:CreateTexture(nil, "ARTWORK")
                l.filet:SetHeight(1)
                l.filet:SetPoint("TOPLEFT", l.texte, "BOTTOMLEFT", 0, -3)
                l.filet:SetPoint("RIGHT", l, "RIGHT", 0, 0)
            end
        end
        l.sorte = sorte
        f.pool[sorte][f.rang[sorte]] = l
        return l
    end

    -- Pose une ligne a la suite. retrait : decalage a gauche (replis).
    local function Poser(f, sorte, a, b, retrait, ecart)
        local l = Prendre(f, sorte)
        retrait = retrait or 0
        f.y = f.y + (ecart or 0)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", f.contenu, "TOPLEFT", retrait, -f.y)
        local largeur = LARGEUR_T - retrait
        l:SetWidth(largeur)
        local h
        if sorte == "repli" then
            l.texte:SetFontObject(a.groupe and "GameFontNormal" or "GameFontHighlight")
            l.texte:SetText(a.texte)
            l.texte:SetWidth(largeur - 30 - (a.date and 90 or 0))
            l.date:SetText(a.date or "")
            l.cle = a.cle
            local ouvert = f.ouverts[a.cle]
            l.signe:SetTexture(ouvert and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            h = 22
            table.insert(f.focusables, l)
        elseif sorte == "deux" then
            l.gauche:SetText(a or "")
            l.droite:SetWidth(largeur - 160)
            l.droite:SetText(b or "")
            h = math.max(l.gauche:GetStringHeight() or 14, l.droite:GetStringHeight() or 14)
        else
            l.texte:SetWidth(largeur - (sorte == "puce" and 14 or 0))
            if sorte == "titre" then
                -- Le titre de rubrique de la suite (police et filet du fond).
                local charte = NS.charte
                if not (charte and charte.TitreDeSection and pcall(charte.TitreDeSection, l.texte, l.filet)) then
                    l.filet:SetColorTexture(1, 0.82, 0, 0.25)
                end
            end
            l.texte:SetText(a or "")
            h = l.texte:GetStringHeight() or 14
            if sorte == "titre" then h = h + 6 end
        end
        l:SetHeight(math.max(1, h))
        l.y = f.y
        l:Show()
        f.y = f.y + h
        return l
    end

    -- Le texte des notes : **gras** passe en or, les liens gardent leur texte.
    local function Mise(texte)
        texte = tostring(texte or "")
        texte = texte:gsub("%*%*(.-)%*%*", "|cffffd100%1|r")
        texte = texte:gsub("%[(.-)%]%((.-)%)", "%1")
        texte = texte:gsub("`(.-)`", "%1")
        return texte
    end

    local function Blocs(f, blocs, retrait)
        for _, b in ipairs(blocs or {}) do
            local sorte, texte = b[1], Mise(T2(b[2]))
            if sorte == "h" then Poser(f, "titre", texte, nil, retrait, 10)
            elseif sorte == "li" then Poser(f, "puce", texte, nil, retrait + 6, 4)
            elseif sorte == "d" then Poser(f, "detail", texte, nil, retrait, 4)
            else Poser(f, "texte", texte, nil, retrait, 6) end
        end
    end

    local function VersionInstallee()
        local lire = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
        if not lire then return nil end
        for _, cle in ipairs(Suite.ADDONS_SUITE or {}) do
            local ok, v = pcall(lire, cle, "X-SagaCore-Version")
            if ok and type(v) == "string" and v ~= "" then return v end
        end
        return nil
    end

    local function RendreNouveautes(f)
        local donnees = _G.CoreSuiteNouveautes
        local v = VersionInstallee()
        Poser(f, "detail", TRi("Toutes les versions de Forever SagaCore, de la plus récente à la première. Cliquez sur une version pour la déplier.",
            "Every version of Forever SagaCore, newest first. Click a version to unfold it. The notes are written in French.")
            .. (v and ("  " .. TRi("Version installée : ", "Installed version : ") .. v) or ""), nil, 0, 0)
        if type(donnees) ~= "table" then return end
        if not f.ouvertsPoses then
            f.ouvertsPoses = true
            local g = donnees[1]
            if g then
                f.ouverts[g.cle] = true
                if g.versions and g.versions[1] then f.ouverts["v" .. g.versions[1].v] = true end
            end
        end
        for _, g in ipairs(donnees) do
            Poser(f, "repli", { cle = g.cle, texte = Mise(T2(g.titre)), groupe = true, date = g.periode }, nil, 0, 10)
            if f.ouverts[g.cle] then
                if g.resume then Poser(f, "texte", Mise(T2(g.resume)), nil, 20, 4) end
                for _, ver in ipairs(g.versions or {}) do
                    local cle = "v" .. ver.v
                    Poser(f, "repli", { cle = cle, texte = ver.v .. "  " .. Mise(T2(ver.titre)), date = ver.date }, nil, 20, 4)
                    if f.ouverts[cle] then
                        Blocs(f, ver.blocs, 40)
                        f.y = f.y + 6
                    end
                end
            end
        end
    end

    local function RendreCommandes(f)
        local cle, depuis = Suite.infoCle, Suite.infoDepuis
        local propres
        if depuis and depuis.lignesDeCommandes then
            local ok, l = pcall(depuis.lignesDeCommandes)
            if ok and type(l) == "table" and #l > 0 then propres = l end
        end
        if propres then
            Poser(f, "titre", TRi("Dans cette fenêtre", "In this window") .. " (" .. Suite.NomAffiche(cle or "") .. ")", nil, 0, 0)
            for _, l in ipairs(propres) do Poser(f, "deux", l[1], l[2], 6, 4) end
        end
        Poser(f, "titre", TRi("Manette, dans toute la suite", "Gamepad, everywhere in the suite"), nil, 0, propres and 14 or 0)
        for _, l in ipairs(LignesManette()) do Poser(f, "deux", l[1], l[2], 6, 4) end
        Poser(f, "titre", TRi("Clavier et souris", "Keyboard and mouse"), nil, 0, 14)
        Poser(f, "deux", TRi("Échap", "Escape"), TRi("Ferme la fenêtre du dessus", "Closes the window on top"), 6, 4)
        Poser(f, "deux", TRi("Molette", "Wheel"), TRi("Fait défiler la page", "Scrolls the page"), 6, 4)
        Poser(f, "deux", TRi("Raccourcis", "Key bindings"), TRi("Options du jeu › Raccourcis › AddOns : une touche pour ouvrir chaque add-on", "Game options › Keybindings › AddOns : a key to open each add-on"), 6, 4)
        Poser(f, "titre", TRi("Discussion", "Chat"), nil, 0, 14)
        local vus = {}
        local function Slash(c)
            if vus[c] or not SLASH[c] then return end
            vus[c] = true
            for _, l in ipairs(SLASH[c]) do Poser(f, "deux", l[1], T2(l[2]), 6, 4) end
        end
        if cle then Slash(cle) end
        Poser(f, "deux", "/sagacore", TRi("Rouvre la suite là où vous l'aviez laissée", "Reopens the suite where you left it"), 6, 4)
        Poser(f, "deux", "/sagacore stop", TRi("Arrête le guidage en cours", "Stops the current guidance"), 6, 4)
        Poser(f, "deux", "/sagacore messages", TRi("Réglages des messages de la suite dans la discussion", "Settings of the suite's chat messages"), 6, 4)
        for _, info in ipairs(Suite.ORDRE or {}) do
            if Suite.Installe(info.cle) then Slash(info.cle) end
        end
    end

    local function RendreAide(f)
        local cle, depuis = Suite.infoCle, Suite.infoDepuis
        local aides = _G.CoreSuiteAides
        local a = type(aides) == "table" and (aides[cle or ""] or aides.Suite) or nil
        if not a then
            Poser(f, "texte", TRi("Pas encore d'aide pour cette fenêtre.", "No help for this window yet."), nil, 0, 0)
            return
        end
        Poser(f, "titre", Suite.NomAffiche(cle or ""), nil, 0, 0)
        if a.intro then Poser(f, "texte", Mise(T2(a.intro)), nil, 0, 6) end
        -- La page ouverte d'abord, si l'aide en parle.
        local page, libelle
        if depuis and depuis.suitePage then
            local ok, p, l = pcall(depuis.suitePage)
            if ok then page, libelle = p, l end
        end
        if page and a.pages and a.pages[page] then
            Poser(f, "titre", TRi("Cette page", "This page") .. (libelle and (" : " .. libelle) or ""), nil, 0, 14)
            Poser(f, "texte", Mise(T2(a.pages[page])), nil, 0, 6)
        end
        for _, s in ipairs(a.sections or {}) do
            Poser(f, "titre", Mise(T2(s.titre)), nil, 0, 14)
            for _, l in ipairs(s.lignes or {}) do Poser(f, "puce", Mise(T2(l)), nil, 6, 4) end
        end
        if aides.Suite and a ~= aides.Suite then
            local s = aides.Suite
            Poser(f, "titre", TRi("Toute la suite", "The whole suite"), nil, 0, 14)
            for _, l in ipairs(s.lignes or {}) do Poser(f, "puce", Mise(T2(l)), nil, 6, 4) end
        end
    end

    function Suite.RendreInfo()
        local f = Suite.fenetreInfo
        if not (f and f:IsShown()) then return end
        local onglet = Suite.infoOnglet or "aide"
        if f.titre then f.titre:SetText(LibelleInfo(onglet)) end
        local pad = ManetteActive()
        for rang, b in ipairs(f.onglets) do
            local choisi = b.onglet == onglet
            local glyphe = ""
            if pad and rang == 1 then glyphe = GlyphePad("PADLSHOULDER") .. " " end
            b:SetText(glyphe .. LibelleInfo(b.onglet) .. ((pad and rang == #f.onglets) and (" " .. GlyphePad("PADRSHOULDER")) or ""))
            b:SetWidth(math.floor((b:GetTextWidth() or 80) + 30))
            if choisi then b:LockHighlight() else b:UnlockHighlight() end
            local fs = b:GetFontString()
            if fs then
                if choisi then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(1, 1, 1) end
            end
        end
        for sorte, liste in pairs(f.pool) do
            for _, l in ipairs(liste) do l:Hide() end
            f.rang[sorte] = 0
        end
        f.y, f.focusables = 0, {}
        if onglet == "nouveautes" then RendreNouveautes(f)
        elseif onglet == "commandes" then RendreCommandes(f)
        else RendreAide(f) end
        f.contenu:SetHeight(math.max(1, f.y + 10))
        local parchemin = Suite.MontrerFondChoisi(f)
        local charte = NS.charte
        if charte and charte.Encrer then pcall(charte.Encrer, f.contenu, parchemin) end
        -- Manette : la ligne choisie garde sa surbrillance.
        f.focus = nil
        for rang, l in ipairs(f.focusables) do
            if l.cle == f.focusCle then f.focus = rang end
            l:UnlockHighlight()
        end
        if pad and f.focus and f.focusables[f.focus] then f.focusables[f.focus]:LockHighlight() end
    end

    local function Construire()
        local charte = NS.charte
        if not (charte and charte.Fenetre) then return nil end
        local f = charte.Fenetre("CoreSuiteInfo", LARGEUR_I, HAUTEUR_I, { portrait = false, surgit = true })
        f:SetPoint("CENTER")
        f:SetToplevel(true)
        table.insert(UISpecialFrames, "CoreSuiteInfo")
        Suite.FondChoisi(f)
        f.pool, f.rang, f.ouverts, f.focusables = {}, {}, {}, {}
        f.onglets = {}
        local precedent
        for _, o in ipairs(Suite.ONGLETS_INFO) do
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetHeight(22)
            b.onglet = o
            b:SetScript("OnClick", function(self) Suite.infoOnglet = self.onglet Suite.RendreInfo() end)
            if precedent then b:SetPoint("LEFT", precedent, "RIGHT", 6, 0)
            else b:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, 0) end
            table.insert(f.onglets, b)
            precedent = b
        end
        local okD, defil = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        if not okD or not defil then defil = CreateFrame("ScrollFrame", nil, f) end
        defil:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, -34)
        defil:SetPoint("BOTTOMRIGHT", f.zone, "BOTTOMRIGHT", -24, 0)
        local contenu = CreateFrame("Frame", nil, defil)
        contenu:SetSize(LARGEUR_T, 1)
        defil:SetScrollChild(contenu)
        f.defilement, f.contenu = defil, contenu
        local fermer = charte.BoutonDePied(f, TX("Close"), 110)
        fermer:SetScript("OnClick", function() f:Hide() end)
        f.fermerBas = fermer
        f:SetScript("OnShow", function() Suite.RendreInfo() end)
        -- Manette : LB / RB changent d'onglet, la croix choisit une version
        -- (ou fait defiler), A deplie, B ferme.
        if f.EnableGamePadButton and pcall(f.EnableGamePadButton, f, true) then
            local function Defiler(pas)
                local max = defil:GetVerticalScrollRange() or 0
                defil:SetVerticalScroll(math.max(0, math.min(max, (defil:GetVerticalScroll() or 0) + pas)))
            end
            local function Montrer(l)
                if not l then return end
                local haut = defil:GetVerticalScroll() or 0
                local h = defil:GetHeight() or 400
                if l.y < haut then defil:SetVerticalScroll(l.y)
                elseif l.y + 22 > haut + h then
                    local max = defil:GetVerticalScrollRange() or 0
                    defil:SetVerticalScroll(math.min(max, l.y + 22 - h + 40))
                end
            end
            f:SetScript("OnGamePadButtonDown", function(_, bouton)
                if bouton == "PAD2" then f:Hide() return end
                if bouton == "PADLSHOULDER" or bouton == "PADRSHOULDER" then
                    local rang = 1
                    for i, o in ipairs(Suite.ONGLETS_INFO) do if o == Suite.infoOnglet then rang = i end end
                    rang = math.max(1, math.min(#Suite.ONGLETS_INFO, rang + (bouton == "PADRSHOULDER" and 1 or -1)))
                    Suite.infoOnglet = Suite.ONGLETS_INFO[rang]
                    defil:SetVerticalScroll(0)
                    Suite.RendreInfo()
                    return
                end
                local liste = f.focusables
                if bouton == "PADDUP" or bouton == "PADDDOWN" then
                    if #liste == 0 then Defiler(bouton == "PADDUP" and -60 or 60) return end
                    local rang = f.focus or 0
                    rang = math.max(1, math.min(#liste, rang + (bouton == "PADDDOWN" and 1 or -1)))
                    if f.focus and liste[f.focus] then liste[f.focus]:UnlockHighlight() end
                    f.focus = rang
                    f.focusCle = liste[rang].cle
                    liste[rang]:LockHighlight()
                    Montrer(liste[rang])
                    return
                end
                if bouton == "PADDLEFT" or bouton == "PADDRIGHT" then Defiler(bouton == "PADDLEFT" and -120 or 120) return end
                if bouton == "PAD1" and f.focus and liste[f.focus] then liste[f.focus]:Click() return end
            end)
        end
        f:Hide()
        return f
    end

    -- Ouvre la fenetre d'informations sur un onglet, pour l'add-on `cle`
    -- (depuis : la fenetre d'ou l'on vient, pour sa page et ses commandes).
    function Suite.OuvrirInfo(onglet, cle, depuis)
        local f = Suite.fenetreInfo
        if not f then
            f = Construire()
            if not f then return end
            Suite.fenetreInfo = f
        end
        Suite.infoOnglet = onglet or Suite.infoOnglet or "aide"
        if cle then Suite.infoCle = cle end
        if depuis then Suite.infoDepuis = depuis end
        f.defilement:SetVerticalScroll(0)
        if f:IsShown() then Suite.RendreInfo() else f:Show() end
        if f.Raise then f:Raise() end
    end
    function Suite.InfoOuverte()
        return Suite.fenetreInfo ~= nil and Suite.fenetreInfo:IsShown()
    end

    -- Les trois boutons du pied (Reglages et Fermer y sont deja).
    function Suite.PiedCommun(cadre, cle)
        if not (cadre and cadre.pied) or cadre.suitePied then return end
        local charte = NS.charte
        local H = charte and charte.HAUTEUR_BOUTON or 22
        local ECART = charte and charte.ECART or 8
        local function CleCourante()
            local r = cadre.suiteEntete
            return (r and r.courante) or cle
        end
        local function Bouton(auClic)
            local b = CreateFrame("Button", nil, cadre.pied, "UIPanelButtonTemplate")
            b:SetHeight(H)
            b:SetScript("OnClick", auClic)
            return b
        end
        local p = {}
        p.commandes = Bouton(function() Suite.OuvrirInfo("commandes", CleCourante(), cadre) end)
        p.commandes:SetPoint("LEFT", cadre.pied, "LEFT", 0, 0)
        p.aide = Bouton(function()
            if cadre.aideDeLaPage then
                local ok = pcall(cadre.aideDeLaPage)
                if ok then return end
            end
            Suite.OuvrirInfo("aide", CleCourante(), cadre)
        end)
        p.aide:SetPoint("LEFT", p.commandes, "RIGHT", ECART, 0)
        p.nouveautes = Bouton(function() Suite.OuvrirInfo("nouveautes", CleCourante(), cadre) end)
        p.nouveautes:SetPoint("CENTER", cadre.pied, "CENTER", 0, 0)
        cadre.suitePied = p
        cadre.suiteAide = p.aide
        cadre.suiteNouveautes = p.nouveautes
        Suite.LibellesDuPied(cadre)
    end

    -- Libelles du pied (glyphe de la manette sur Aide quand elle est branchee).
    function Suite.LibellesDuPied(cadre)
        local p = cadre and cadre.suitePied
        if not p then return end
        local pad = ManetteActive()
        local function Poser(b, texte)
            b:SetText(texte)
            b:SetWidth(math.max(90, math.floor((b:GetTextWidth() or 60) + 28)))
        end
        Poser(p.commandes, LibelleInfo("commandes"))
        Poser(p.aide, (pad and (GlyphePad("PAD4") .. " ") or "") .. LibelleInfo("aide"))
        Poser(p.nouveautes, LibelleInfo("nouveautes"))
    end
end

-- Les complements en onglets sur le bord DROIT d'une fenetre de complement,
-- comme les metiers dans CraftCore : celui qui est ouvert s'allume.
function Suite.OngletsComplements(cadre, cleCourante)
    cadre.suiteComplements = cadre.suiteComplements or {}
    for _, b in ipairs(cadre.suiteComplements) do b:Hide() end
    local precedent
    for rang, c in ipairs(Suite.Complements()) do
        local b = cadre.suiteComplements[rang]
        if not b then
            b = CreateFrame("CheckButton", nil, cadre)
            b:SetSize(34, 34)
            -- L'onglet du grimoire du jeu, tel quel pour le bord droit.
            b.fond = b:CreateTexture(nil, "BACKGROUND")
            b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
            Suite.TeinteOnglet(b.fond)
            b.fond:SetSize(68, 68)
            b.fond:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 12)
            b.icone = b:CreateTexture(nil, "ARTWORK")
            b.icone:SetAllPoints()
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
            local halo = b:GetCheckedTexture()
            if halo then halo:SetBlendMode("ADD") end
            b:HookScript("OnEnter", function(self)
                self.icone:SetVertexColor(1, 1, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(Suite.NomAffiche(self.cle), 1, 0.82, 0)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function(self)
                if self.cle ~= self.courante then self.icone:SetVertexColor(0.55, 0.55, 0.55) end
                GameTooltip:Hide()
            end)
            cadre.suiteComplements[rang] = b
        end
        b.cle, b.courante = c.cle, cleCourante
        b.icone:SetTexture(c.icone)
        local v = (c.cle == cleCourante) and 1 or 0.55
        b.icone:SetVertexColor(v, v, v)
        b:SetChecked(c.cle == cleCourante)
        b:SetScript("OnClick", function(self)
            self:SetChecked(self.cle == self.courante)
            if self.cle ~= self.courante then Suite.OuvrirComplement(self.cle, cadre) end
        end)
        b:ClearAllPoints()
        -- Le complement "a part" (FriendsCore) un peu detache des autres.
        if precedent then b:SetPoint("TOPLEFT", precedent, "BOTTOMLEFT", 0, -Suite.ECART_ENTRE_ONGLETS - (c.apart and Suite.ECART_ONGLETS or 0))
        else
            local a, point = Suite.AncreHaut(cadre, "droite")
            b:SetPoint("TOPLEFT", a, point, 0, Suite.HAUT_ONGLET)
        end
        b:Show()
        precedent = b
    end
    -- Comme L3 / R3 pour la colonne de gauche : LT au-dessus des
    -- complements, RT dessous. Les complements se parcourent avec eux seuls.
    local premier, dernier = cadre.suiteComplements[1], precedent
    if premier and dernier then
        if not cadre.suiteLT then
            cadre.suiteLT = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cadre.suiteRT = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        end
        cadre.suiteLT:ClearAllPoints()
        cadre.suiteLT:SetPoint("BOTTOM", premier, "TOP", 0, 12)
        cadre.suiteRT:ClearAllPoints()
        cadre.suiteRT:SetPoint("TOP", dernier, "BOTTOM", 0, -10)
        local pad = ManetteActive() and true or false
        cadre.suiteLT:SetText(GlyphePad("PADLTRIGGER"))
        cadre.suiteRT:SetText(GlyphePad("PADRTRIGGER"))
        cadre.suiteLT:SetShown(pad)
        cadre.suiteRT:SetShown(pad)
    end
end

-- Les add-ons de la suite en onglets lateraux, sur le bord GAUCHE de la
-- fenetre : le bord droit reste aux onglets propres a chaque add-on
-- (metiers, equipement, carte...). LT / RT passent d'un add-on a l'autre au
-- bout de la colonne de droite (voir Suite.Voisin).
function Suite.Entete(cadre, cleCourante)
    if not cadre or cadre.suiteEntete then return end
    local rangee = { boutons = {}, courante = cleCourante }
    local precedent
    for _, info in ipairs(Suite.Liste()) do
        local cle = info.cle
        local b = OngletLateral(cadre, info, function()
            -- L'add-on allume peut changer (une fenetre en sert deux).
            if cle ~= rangee.courante and Suite.Installe(cle) then Suite.Ouvrir(cle) end
        end)
        b.courante = cleCourante
        b:ClearAllPoints()
        -- Toutes les icones a la suite, sans espace entre les blocs : la
        -- colonne tient dans la fenetre et la manette les voit toutes.
        if precedent then b:SetPoint("TOPRIGHT", precedent, "BOTTOMRIGHT", 0, -Suite.ECART_ENTRE_ONGLETS)
        else
            local a, point = Suite.AncreHaut(cadre, "gauche")
            b:SetPoint("TOPRIGHT", a, point, 0, Suite.HAUT_ONGLET)
        end
        table.insert(rangee.boutons, b)
        precedent = b
    end
    -- L3 au-dessus de la colonne, R3 dessous : add-on precedent / suivant.
    rangee.l3 = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if rangee.boutons[1] then rangee.l3:SetPoint("BOTTOM", rangee.boutons[1], "TOP", 0, 12) end
    rangee.r3 = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if rangee.boutons[#rangee.boutons] then rangee.r3:SetPoint("TOP", rangee.boutons[#rangee.boutons], "BOTTOM", 0, -10) end
    pcall(BoutonReglages, cadre)
    pcall(Suite.PiedCommun, cadre, cleCourante)
    -- Tout en bas de la colonne : Alliance et Horde, pour le theme.
    rangee.factions = {}
    local dessous
    for _, faction in ipairs({ "horde", "alliance" }) do
        local b = OngletLateral(cadre, { cle = faction == "horde" and "Horde" or "Alliance",
            icone = faction == "horde" and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02" }, function() end)
        b.faction = faction
        b.estFaction = true
        b:SetScript("OnClick", function(self) Suite.PoserTheme(self.faction) end)
        b:SetScript("OnEnter", function(self)
            self.icone:SetVertexColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(TX(self.faction == "horde" and "Horde theme" or "Alliance theme"), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            if self.faction ~= Suite.Theme() then self.icone:SetVertexColor(0.55, 0.55, 0.55) end
            GameTooltip:Hide()
        end)
        b:ClearAllPoints()
        if dessous then b:SetPoint("BOTTOMRIGHT", dessous, "TOPRIGHT", 0, Suite.ECART_ENTRE_ONGLETS)
        else b:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMLEFT", 0, 46) end
        table.insert(rangee.factions, b)
        dessous = b
    end
    -- R3 tout en bas, sous la Horde : il ne prend plus la place d'une icone.
    if rangee.factions[1] then
        rangee.r3:ClearAllPoints()
        rangee.r3:SetPoint("TOP", rangee.factions[1], "BOTTOM", 0, -6)
    end
    -- Au-dessus d'Alliance / Horde : le bouton Complements (les outils a
    -- part), un peu detache de la faction.
    do
        local b = OngletLateral(cadre, { cle = "Complements", icone = Suite.ICONE_COMPLEMENTS }, function()
            Suite.OuvrirComplements(Suite.EstComplement(rangee.courante) and cadre or nil)
        end)
        b.courante = cleCourante
        b.estComplements = true
        b:SetScript("OnEnter", function(self)
            self.survol = true
            self.icone:SetVertexColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(TX("Add-ons"), 1, 0.82, 0)
            GameTooltip:AddLine(TX("The suite's other tools."), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:ClearAllPoints()
        local haut = rangee.factions[#rangee.factions]
        if haut then b:SetPoint("BOTTOMRIGHT", haut, "TOPRIGHT", 0, Suite.ECART_ENTRE_ONGLETS + 14)
        else b:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMLEFT", 0, 46) end
        rangee.complements = b
    end
    -- Dans une fenetre de complement : les complements en onglets a droite.
    if Suite.EstComplement(cleCourante) then pcall(Suite.OngletsComplements, cadre, cleCourante) end
    rangee.cadre = cadre
    pcall(Suite.LogoDuMenu, cadre)
    cadre.suiteEntete = rangee
    cadre:HookScript("OnShow", function(self)
        Suite.PrendrePlace(rangee.courante or cleCourante, self)
        Suite.Actualiser()
    end)
    cadre:HookScript("OnHide", function() Suite.Actualiser() end)
    table.insert(Suite.entetes, rangee)
    Suite.Actualiser()
end

-- Pastille sur l'onglet d'un add-on (texte court), nil pour l'enlever.
-- Plus de pastille : elle collait a l'onglet sans apporter grand-chose.
function Suite.PoserBadge(cle, texte)
    Suite.badges = {}
end

-- Ecart entre les onglets de la suite et ceux de l'add-on.
Suite.ECART_ONGLETS = 22

-- LT / RT au bout des onglets d'un add-on : l'add-on voisin s'ouvre, sur son
-- premier onglet (en avancant) ou son dernier (en reculant).
-- Depuis une fenetre de reglages ouverte par la colonne : l'onglet suivant.
function Suite.ContinuerColonne(pas)
    local d = Suite.dernierVoisin
    if not d then return end
    Suite.Voisin(d.depuis, pas)
end

function Suite.Voisin(cleCourante, pas)
    -- Dans l'ordre de la colonne : les add-ons installes, puis (poste de
    -- l'auteur) AuraCore et Macros, qui ouvrent leurs reglages.
    local liste = {}
    for _, info in ipairs(Suite.Liste()) do
        if Suite.Installe(info.cle) then table.insert(liste, { cle = info.cle }) end
    end
    -- Au bout de la colonne de gauche : le bouton Complements (il ouvre le
    -- dernier complement). Entre complements, c'est LT / RT, a droite.
    table.insert(liste, { cle = "Complements", complements = true })
    if #liste < 2 then return false end
    if Suite.EstComplement(cleCourante) then cleCourante = "Complements" end
    local index = Suite.dernierVoisin and Suite.dernierVoisin.depuis == cleCourante and Suite.dernierVoisin.rang or nil
    if not index then
        index = 1
        for rang, e in ipairs(liste) do if e.cle == cleCourante then index = rang end end
    end
    local rang = ((index - 1 + pas) % #liste) + 1
    local e = liste[rang]
    if e.complements then
        Suite.dernierVoisin = nil
        Suite.OuvrirComplements(nil)
        return true
    end
    if e.action then
        -- Une fenetre de reglages : on retient ou l'on en est dans la colonne.
        Suite.dernierVoisin = { depuis = cleCourante, rang = rang }
        e.action()
    else
        Suite.dernierVoisin = nil
        Suite.Ouvrir(e.cle)
    end
    return true
end

-- Manette, la meme dans toute la suite :
--   LB / RB : menu de gauche de l'add-on (s'arrete aux bouts) ;
--   LT / RT : onglets de droite de l'add-on (s'arrete aux bouts) ;
--   clic du stick gauche / droit (L3 / R3) : add-on precedent / suivant.
-- Chaque fenetre appelle ManetteBas a l'appui : vrai si la suite a pris le
-- bouton.
function Suite.ManetteBas(cleCourante, bouton)
    -- Reglages generaux ouverts : la manette est a eux.
    local r = Suite.reglagesGeneraux
    if r and r:IsShown() then return true end
    local m = _G.SagaCoreMessages and _G.SagaCoreMessages.fenetre
    if m and m:IsShown() then return true end
    if Suite.fenetreMacros and Suite.fenetreMacros:IsShown() then return true end
    local ic = _G.AuraCoreReglages
    if ic and ic:IsShown() then return true end
    -- Aide, commandes et nouveautes ouvertes : la manette est a elles.
    if Suite.InfoOuverte and Suite.InfoOuverte() then return true end
    -- Y : l'aide de la fenetre (si la fenetre ne l'a pas deja prise).
    if bouton == "PAD4" then
        local m = Suite.membres[cleCourante]
        local f = m and m.fenetre and m.fenetre()
        if f and f.IsShown and f:IsShown() and f.suiteAide then f.suiteAide:Click() return true end
    end
    -- Menu (Start) : les reglages generaux.
    if bouton == "PADFORWARD" then
        Suite.OuvrirReglagesGeneraux()
        return true
    end
    if bouton == "PADLSTICK" or bouton == "PADRSTICK" then
        Suite.Voisin(cleCourante, bouton == "PADLSTICK" and -1 or 1)
        return true
    end
    -- LT / RT dans un complement, quelle que soit sa fenetre : le complement
    -- precedent / suivant (onglets de droite). Une seule regle pour tous.
    if (bouton == "PADLTRIGGER" or bouton == "PADRTRIGGER") and Suite.EstComplement(cleCourante) then
        local liste = Suite.Complements()
        local rang
        for i, c in ipairs(liste) do if c.cle == cleCourante then rang = i end end
        if not rang then return false end
        local cible = liste[math.max(1, math.min(#liste, rang + (bouton == "PADRTRIGGER" and 1 or -1)))]
        if cible and cible.cle ~= cleCourante then
            local m = Suite.membres[cleCourante]
            local depuis = m and m.fenetre and m.fenetre()
            Suite.OuvrirComplement(cible.cle, depuis)
        end
        return true
    end
    return false
end

-- Plus de combinaison : garde pour les fenetres qui l'appellent encore.
function Suite.ManetteHaut() return false end

-- "debut" ou "fin" : ou l'add-on qui s'ouvre doit se poser, une seule fois.
function Suite.PrendreEntree()
    local e = Suite.entree
    Suite.entree = nil
    return e
end

-- ---------------------------------------------------------------------------
-- Manette : l'ancien curseur de l'en-tete n'existe plus (LT / RT passent par
-- les onglets lateraux). Gardes pour les add-ons qui l'appellent encore.
-- ---------------------------------------------------------------------------

function Suite.CurseurActif() return false end
function Suite.CurseurEntrer() return false end
function Suite.CurseurQuitter() end
function Suite.CurseurDeplacer() end
function Suite.CurseurValider() end

-- ---------------------------------------------------------------------------
--
-- Le curseur se pose sur une icone sans rien ouvrir ; seul A ouvre l'add-on.
-- On ne change donc jamais d'add-on par erreur.

local function Choisissables(rangee)
    local liste = {}
    for _, b in ipairs(rangee and rangee.boutons or {}) do
        if Suite.Installe(b.cle) and b.cle ~= rangee.courante then table.insert(liste, b) end
    end
    return liste
end

local function Eclairer(rangee)
    for _, b in ipairs(rangee.boutons) do
        if b.UnlockHighlight then b:UnlockHighlight() end
    end
    GameTooltip:Hide()
    local b = rangee.curseur and Choisissables(rangee)[rangee.curseur]
    if b then
        if b.LockHighlight then b:LockHighlight() end
        local survol = b:GetScript("OnEnter")
        if survol then pcall(survol, b) end
        if GameTooltip:IsShown() then GameTooltip:AddLine(T.manette, 1, 1, 1) GameTooltip:Show() end
    end
end

-- Une fenetre qui sert deux add-ons (CraftCore et StuffCore) : celui
-- qu'elle montre devient l'onglet allume de sa colonne.
function Suite.ChangerCourant(cadre, cle)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or rangee.courante == cle then return end
    rangee.courante = cle
    rangee.sansCourant = nil
    pcall(Suite.Actualiser)
end

-- Met l'onglet de l'add-on courant en retrait (oui) ou le rallume (non).
function Suite.CourantEnRetrait(cadre, oui)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or rangee.sansCourant == (oui == true) then return end
    rangee.sansCourant = oui == true
    pcall(Suite.Actualiser)
end

function Suite.CurseurActif(cadre)
    local rangee = cadre and cadre.suiteEntete
    return rangee ~= nil and rangee.curseur ~= nil
end

-- Entre sur la premiere icone choisissable. Faux s'il n'y en a aucune.
function Suite.CurseurEntrer(cadre)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or #Choisissables(rangee) == 0 then return false end
    rangee.curseur = 1
    Eclairer(rangee)
    return true
end

function Suite.CurseurQuitter(cadre)
    local rangee = cadre and cadre.suiteEntete
    if not rangee then return end
    rangee.curseur = nil
    Eclairer(rangee)
end

-- Deplace le curseur ; avant la premiere icone, on sort (retour aux portraits).
function Suite.CurseurDeplacer(cadre, pas)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or not rangee.curseur then return end
    local n = #Choisissables(rangee)
    local rang = rangee.curseur + pas
    if rang < 1 then rangee.curseur = nil
    else rangee.curseur = math.min(rang, n) end
    Eclairer(rangee)
end

function Suite.CurseurValider(cadre)
    local rangee = cadre and cadre.suiteEntete
    local b = rangee and rangee.curseur and Choisissables(rangee)[rangee.curseur]
    if not b then return end
    rangee.curseur = nil
    Eclairer(rangee)
    Suite.Ouvrir(b.cle)
end

-- ---------------------------------------------------------------------------
-- Bouton de minicarte unique, qui s'etend au survol
-- ---------------------------------------------------------------------------

local atan2 = math.atan2 or math.atan

local function PlacerSurMinicarte(bouton)
    local angle = math.rad(Reglages().angle)
    local demi = Minimap:GetWidth() / 2 + 5
    local forme = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = math.cos(angle), math.sin(angle)
    if forme == "ROUND" then
        x, y = x * demi, y * demi
    else
        local portee = demi * 1.4142
        x = math.max(-demi, math.min(x * portee, demi))
        y = math.max(-demi, math.min(y * portee, demi))
    end
    bouton:ClearAllPoints()
    bouton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function IconeDuBouton()
    local d = Reglages()
    if d.dernier and Suite.Installe(d.dernier) then
        for _, info in ipairs(Suite.Liste()) do if info.cle == d.dernier then return info.icone end end
    end
    for _, info in ipairs(Suite.Liste()) do if Suite.Installe(info.cle) then return info.icone end end
    if Suite.Seul() and SlashCmdList.AURACORE then return "Interface\\Icons\\Spell_Holy_AuraOfLight" end
    return Suite.ORDRE[1].icone
end

function Suite.ConstruireMinicarte()
    if Suite.bouton or not Minimap then return end
    local bouton = IconeRonde(Minimap, 31, { cle = "CoreSuite", icone = IconeDuBouton() })
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bouton:RegisterForDrag("LeftButton")
    bouton:SetScript("OnClick", function(_, souris)
        if souris == "RightButton" then return end
        -- Clic : le dernier add-on utilise, sinon le premier installe.
        local d = Reglages()
        local cible = (d.dernier and Suite.Installe(d.dernier)) and d.dernier or nil
        if not cible then
            for _, info in ipairs(Suite.Liste()) do
                if Suite.Installe(info.cle) then cible = info.cle break end
            end
        end
        if cible then Suite.Ouvrir(cible)
        elseif Suite.membres.AuraCore then Suite.Ouvrir("AuraCore")
        elseif SlashCmdList.AURACORE then SlashCmdList.AURACORE("") end
    end)
    bouton:SetScript("OnDragStart", function(self)
        Suite.eventail:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local echelle = Minimap:GetEffectiveScale()
            Reglages().angle = math.deg(atan2(py / echelle - my, px / echelle - mx)) % 360
            PlacerSurMinicarte(self)
        end)
    end)
    bouton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    -- L'eventail : les add-ons, en ligne a cote du bouton.
    local eventail = CreateFrame("Frame", nil, bouton)
    eventail:SetSize(N() * 30, 30)
    eventail:SetPoint("RIGHT", bouton, "LEFT", -2, 0)
    eventail.boutons = {}
    for rang, info in ipairs(Suite.Liste()) do
        local b = IconeRonde(eventail, 28, info)
        b:SetPoint("RIGHT", eventail, "RIGHT", -(N() - rang) * 30, 0)
        eventail.boutons[rang] = b
    end
    eventail:Hide()
    Suite.eventail = eventail

    -- Au survol : l'eventail s'ouvre, et se referme un instant apres que la
    -- souris a quitte le bouton et l'eventail.
    local delai = 0
    bouton:SetScript("OnEnter", function(self)
        eventail:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever SagaCore", 1, 0.82, 0)
        GameTooltip:AddLine(T.survol, 1, 1, 1)
        GameTooltip:AddLine(T.deplacer, 1, 1, 1)
        GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    eventail:SetScript("OnUpdate", function(self, ecoule)
        if self:IsMouseOver(4, -4, -4, 4) or bouton:IsMouseOver() then delai = 0 return end
        delai = delai + (ecoule or 0)
        if delai > 0.4 then self:Hide() delai = 0 end
    end)

    Suite.bouton = bouton
    PlacerSurMinicarte(bouton)
    bouton:SetShown(not Reglages().minicarteCachee)
end

-- ---------------------------------------------------------------------------
-- Barre posee a l'ecran, deplacable
-- ---------------------------------------------------------------------------

-- La petite barre posee a l'ecran n'existe plus : les icones en haut de
-- chaque fenetre et le bouton de minicarte suffisent. Une barre deja creee
-- par une ancienne copie de ce fichier est cachee.
function Suite.ConstruireBarre()
    if Suite.barre then Suite.barre:Hide() end
end

-- ---------------------------------------------------------------------------
-- Mise a jour de tout ce qui montre la suite
-- ---------------------------------------------------------------------------

function Suite.Actualiser()
    local ouvert
    for cle, m in pairs(Suite.membres) do
        local f = m.fenetre and m.fenetre()
        if f and f:IsShown() then ouvert = cle end
    end
    local function Rangee(boutons)
        for _, b in ipairs(boutons or {}) do Teinter(b) end
    end
    if Suite.eventail then Rangee(Suite.eventail.boutons) end
    if Suite.bouton then Suite.bouton.icone:SetTexture(IconeDuBouton()) end
    if Suite.barre then
        Suite.barre:Hide()
    end
    pcall(Suite.RendreFactions)
    for _, rangee in ipairs(Suite.entetes) do
        if rangee.cadre then
            local ok, souci = pcall(Suite.LogoDuMenu, rangee.cadre)
            if not ok and Suite.Prive() then print("|cffffd100SagaCore logo erreur|r", tostring(souci)) end
        end
    end
    local pad = ManetteActive()
    for _, rangee in ipairs(Suite.entetes) do
        if rangee.l3 then
            rangee.l3:SetText(GlyphePad("PADLSTICK"))
            rangee.r3:SetText(GlyphePad("PADRSTICK"))
            rangee.l3:SetShown(pad)
            rangee.r3:SetShown(pad)
            local cc = rangee.cadre
            if cc and cc.suiteLT then cc.suiteLT:SetShown(pad) cc.suiteRT:SetShown(pad) end
            local reg = rangee.cadre and rangee.cadre.suiteReglages
            if reg then reg:SetText((pad and (GlyphePad("PADFORWARD") .. " ") or "") .. TX("Settings")) end
            if rangee.cadre then pcall(Suite.LibellesDuPied, rangee.cadre) end
        end
        for _, b in ipairs(rangee.boutons) do
            local installe = Suite.Installe(b.cle)
            -- Une page a part (l'equipement de CraftCore) : l'add-on courant
            -- passe en retrait, comme les autres.
            local courant = b.cle == rangee.courante and not rangee.sansCourant
            b.icone:SetDesaturated(not installe)
            b:SetAlpha(installe and 1 or 0.5)
            if b.SetChecked then b:SetChecked(courant) end
            -- Comme les onglets de metier : celui qui n'est pas ouvert reste
            -- en retrait ; il s'eclaire au survol.
            local v = (courant or b.survol) and 1 or 0.55
            b.icone:SetVertexColor(v, v, v)
            -- Pastille (ex. points d'heritage a depenser) dans le coin de l'icone.
            local pastille = Suite.badges and Suite.badges[b.cle]
            if pastille and not b.badge then
                b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                b.badge:SetPoint("BOTTOMRIGHT", b.icone, "BOTTOMRIGHT", 1, 0)
                b.badge:SetTextColor(0.31, 0.82, 0.41)
            end
            if b.badge then
                b.badge:SetText(pastille or "")
                b.badge:SetShown(pastille ~= nil)
            end
        end
        -- Complements : allume dans une fenetre de complement ; cache s'il
        -- n'y en a aucun.
        local bc = rangee.complements
        if bc then
            local n = #Suite.Complements()
            bc:SetShown(n > 0)
            local courant = Suite.EstComplement(rangee.courante)
            if bc.SetChecked then bc:SetChecked(courant) end
            local v = (courant or bc.survol) and 1 or 0.55
            bc.icone:SetVertexColor(v, v, v)
        end
        if rangee.cadre and rangee.cadre.suiteComplements and Suite.EstComplement(rangee.courante) then
            pcall(Suite.OngletsComplements, rangee.cadre, rangee.courante)
        end
        -- AuraCore et Macros : jamais "ouverts", en retrait sauf au survol.
        for _, b in ipairs(rangee.extras or {}) do
            local courant = b.cle == rangee.courante
            if b.SetChecked then b:SetChecked(courant) end
            local v = (courant or b.survol) and 1 or 0.55
            b.icone:SetVertexColor(v, v, v)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Filtres des cartes : une rangee de boutons ronds sous chaque carte de la
-- suite (MapCore, QuestCore). Les memes filtres partout, et partages : ce
-- qu'on masque sur une carte est masque sur les autres.
-- Clic : afficher ou masquer. Clic droit : n'afficher que ca (encore une
-- fois : tout reafficher).
-- ---------------------------------------------------------------------------

local QC = "Interface\\AddOns\\QuestCore\\Icons\\"
local function AvecQuestCore() return _G.QuestCoreAPI ~= nil end
local function AvecRecolte(metier)
    return function()
        local api = _G.CraftCoreAPI
        if not (api and api.Lieux) then return false end
        if not api.MetierDeRecolte then return metier == "herbes" end
        local ok, oui = pcall(api.MetierDeRecolte, metier)
        return ok and oui == true
    end
end
local function AvecReperes() return _G.MapCoreAPI ~= nil end

Suite.FILTRES = {
    { cle = "quetes", atlas = "QuestNormal", fichier = "Interface\\GossipFrame\\AvailableQuestIcon",
      nom = "Quests: pick up and turn in", dispo = AvecQuestCore },
    { cle = "tuer", fichier = QC .. "slay_mono", teinte = { 1, 0.38, 0.32 },
      nom = "Creatures to kill", dispo = AvecQuestCore },
    { cle = "butin", fichier = QC .. "loot_mono", teinte = { 1, 0.82, 0 },
      nom = "Loot to collect", dispo = AvecQuestCore },
    { cle = "objet", fichier = QC .. "object_mono", teinte = { 0.45, 0.8, 1 },
      nom = "Objects to use and places to visit", dispo = AvecQuestCore },
    { cle = "herbes", droite = true, fichier = "Interface\\Icons\\Trade_Herbalism", rond = true,
      nom = "Herbalism: gathering spots", dispo = AvecRecolte("herbes") },
    { cle = "minerais", droite = true, fichier = "Interface\\Icons\\Trade_Mining", rond = true,
      nom = "Mining: veins", dispo = AvecRecolte("minerais") },
    { cle = "peche", droite = true, fichier = "Interface\\Icons\\Trade_Fishing", rond = true,
      nom = "Fishing: fishing spots", dispo = AvecRecolte("peche") },
    { cle = "reperes", fichier = "Interface\\TargetingFrame\\UI-RaidTargetingIcons", coords = { 0, 0.25, 0, 0.25 },
      nom = "My markers", dispo = AvecReperes },
}

local T_FILTRE = Paresseux({
    clic = "Click: show or hide",
    seul = "Right-click: show only this",
    tout = "Right-click: show everything",
    masque = "Hidden",
    titreTout = "Show or hide everything",
    afficherTout = "Click: show everything",
    masquerTout = "Click: hide everything",
})

local function Filtres()
    local d = Reglages()
    d.filtresCarte = type(d.filtresCarte) == "table" and d.filtresCarte or {}
    return d.filtresCarte
end

-- Le filtre est-il actif (montre) ? Par defaut, tout est montre.
function Suite.Filtre(cle)
    local v = Filtres()[cle]
    if v == nil then return (Suite.defautsFiltres or {})[cle] ~= false end
    return v ~= false
end

-- Un lieu de recolte est-il montre ? Selon le filtre de son metier.
-- Un lieu de recolte est-il montre ? Seulement si le personnage a le metier,
-- si le filtre du metier est actif, et si le type (herbe, minerai precis)
-- n'est pas masque dans la liste du filtre.
function Suite.LieuVisible(lieu)
    if type(lieu) ~= "table" then return true end
    local metier = lieu.metier or "herbes"
    local api = _G.CraftCoreAPI
    if api and api.ARecolte then
        local ok, oui = pcall(api.ARecolte, metier)
        if ok and oui == false then return false end
    end
    if not Suite.Filtre(metier) then return false end
    return true
end

-- Categorie d'un point de quete de QuestCore.
function Suite.FiltreDuPoint(pt)
    if type(pt) ~= "table" then return nil end
    if pt.genre == "prendre" or pt.genre == "rendre" then return "quetes" end
    if pt.icone == "tuer" then return "tuer" end
    if pt.icone == "butin" then return "butin" end
    return "objet"
end

function Suite.PointVisible(pt)
    local cle = Suite.FiltreDuPoint(pt)
    return cle == nil or Suite.Filtre(cle)
end

-- Numero d'etape d'un itineraire, pose sur un repere de carte : un petit
-- rond sombre, cercle comme les filtres sous la carte, le numero au centre.
-- f:SetText(texte) le montre ; sans texte, il se cache.
function Suite.PastilleNumero(parent, taille)
    taille = taille or 18
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(taille, taille)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 4)
    f.fond = f:CreateTexture(nil, "BACKGROUND")
    f.fond:SetSize(taille * 0.84, taille * 0.84)
    f.fond:SetPoint("CENTER")
    f.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    f.fond:SetVertexColor(0.55, 0.55, 0.55, 1)
    f.anneau = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.anneau:SetSize(taille * 1.7, taille * 1.7)
    f.anneau:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    f.texte = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.texte:SetDrawLayer("OVERLAY", 2)
    f.texte:SetPoint("CENTER", f, "CENTER", 0.5, 0)
    local fichier = f.texte:GetFont()
    if fichier then f.texte:SetFont(Suite.FichierPolice and Suite.FichierPolice(fichier) or fichier, math.floor(taille * 0.58 + 0.5), "OUTLINE") end
    -- Jaune vif, jamais passe a l'encre du parchemin : lisible sur le rond sombre.
    f.texte:SetTextColor(1, 0.86, 0.1)
    f.texte:SetShadowColor(0, 0, 0, 1)
    f.texte:SetShadowOffset(1, -1)
    f.sansEncre = true
    f.SetText = function(self, texte)
        self.texte:SetText(texte or "")
        self:SetShown(texte ~= nil and texte ~= "")
    end
    f:Hide()
    return f
end

-- Reperes au meme endroit d'une carte : jamais empiles. Ceux qui se
-- touchent sont poses cote a cote, en cercle autour de leur centre commun
-- (deux : l'un a cote de l'autre). Positions en pixels a l'ecran, y vers le
-- bas ; chaque element recoit e.dx, e.dy, le decalage a appliquer.
-- elements : { { x, y, taille, ordre } } ; ordre : le plus petit a gauche.
-- Au-dela de ce nombre, un paquet de reperes au meme endroit (une zone vue
-- de tres loin) ne s'etale plus en cercle : il devient un seul repere, avec
-- le nombre de ceux qu'il regroupe.
Suite.ECART_MAX = 5
function Suite.Ecarter(elements, tailleParDefaut)
    local n = #elements
    for _, e in ipairs(elements) do e.dx, e.dy, e.masque, e.groupe = 0, 0, nil, nil end
    if n < 2 then return end
    tailleParDefaut = tailleParDefaut or 22
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function Racine(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end
        return i
    end
    for i = 1, n - 1 do
        local a = elements[i]
        local ta = a.taille or tailleParDefaut
        for j = i + 1, n do
            local b = elements[j]
            local seuil = (ta + (b.taille or tailleParDefaut)) * 0.42
            if math.abs(a.x - b.x) < seuil and math.abs(a.y - b.y) < seuil then
                local ra, rb = Racine(i), Racine(j)
                if ra ~= rb then parent[rb] = ra end
            end
        end
    end
    local paquets = {}
    for i = 1, n do
        local r = Racine(i)
        paquets[r] = paquets[r] or {}
        table.insert(paquets[r], elements[i])
    end
    for _, p in pairs(paquets) do
        local m = #p
        if m > 1 then
            local cx, cy, t = 0, 0, 0
            for _, e in ipairs(p) do
                cx, cy = cx + e.x, cy + e.y
                t = math.max(t, e.taille or tailleParDefaut)
            end
            cx, cy = cx / m, cy / m
            table.sort(p, function(a, b)
                local oa, ob = a.ordre or 1000, b.ordre or 1000
                if oa ~= ob then return oa < ob end
                if a.x ~= b.x then return a.x < b.x end
                return a.y < b.y
            end)
            if m > Suite.ECART_MAX then
                -- Trop pour un cercle lisible : le premier au centre, avec le
                -- compte ; les autres caches jusqu'a ce qu'on zoome.
                for k, e in ipairs(p) do
                    e.dx, e.dy = cx - e.x, cy - e.y
                    if k == 1 then e.groupe = m else e.masque = true end
                end
            else
                -- Rayon : voisins qui se touchent a peine.
                local r = (m == 2) and (t * 0.55) or ((t * 1.05) / (2 * math.sin(math.pi / m)))
                for k, e in ipairs(p) do
                    local angle = math.pi + (k - 1) * 2 * math.pi / m
                    e.dx = cx + r * math.cos(angle) - e.x
                    e.dy = cy + r * math.sin(angle) - e.y
                end
            end
        end
    end
end

-- Titre de categorie d'un menu de gauche, le meme partout : la police
-- stylisee des titres du parchemin, en or, plus grande que les lignes ;
-- les lignes de la categorie sont en retrait dessous (Suite.RETRAIT_MENU).
Suite.RETRAIT_MENU = 12
Suite.HAUTEUR_TITRE_MENU = 24
function Suite.TitreDeMenu(fs)
    if not fs then return end
    local ok = pcall(fs.SetFontObject, fs, _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormal")
    local fichier, _, options = fs:GetFont()
    if fichier then pcall(fs.SetFont, fs, fichier, 15, options) end
    fs:SetTextColor(1, 0.82, 0)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
end

-- ---------------------------------------------------------------------------
-- Les modeles communs des menus de gauche (une seule definition, partout)
-- ---------------------------------------------------------------------------
-- Une ligne : icone 16, texte blanc, sur une ligne ; au survol, la lueur
-- du jeu seule (le texte ne change jamais de couleur au survol) ; choisie :
-- texte en or et la meme lueur, fixe.
Suite.ICONE_PARAMETRES = "Interface\\Icons\\Trade_Engineering"
Suite.HAUTEUR_LIGNE_MENU = 24
Suite.PAS_LIGNE_MENU = 26
function Suite.LigneDeMenu(parent, icone)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Suite.HAUTEUR_LIGNE_MENU)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.fond:SetBlendMode("ADD")
    b.fond:SetAllPoints()
    b.fond:Hide()
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(16, 16)
    b.icone:SetPoint("LEFT", b, "LEFT", 8, 0)
    if icone then b.icone:SetTexture(icone) end
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.texte = b.text
    b.text:SetPoint("LEFT", b.icone, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    -- Les add-ons qui ecrivent par SetText sur le bouton.
    b.SetText = function(self, t) self.text:SetText(t) end
    b.GetFontString = function(self) return self.text end
    return b
end
function Suite.MarquerLigneDeMenu(b, choisi)
    if not b then return end
    local t = b.text or (b.GetFontString and b:GetFontString())
    if t then t:SetFontObject(choisi and "GameFontNormal" or "GameFontHighlight") end
    if b.fond then b.fond:SetShown(choisi and true or false) end
    b:SetAlpha(1)
end

-- Pose un repere apres Ecarter : masque s'il est regroupe, le compte du
-- paquet sur celui qui le represente.
function Suite.PoserEcarte(b)
    if not b then return end
    if b.ecartMasque then
        if not b.alphaEcart then b.alphaEcart = b:GetAlpha() end
        b:SetAlpha(0)
    elseif b.alphaEcart then
        b:SetAlpha(b.alphaEcart)
        b.alphaEcart = nil
    end
    if b.EnableMouse then b:EnableMouse(not b.ecartMasque) end
    if b.ecartGroupe and not b.compteGroupe then
        b.compteGroupe = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.compteGroupe:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -2)
    end
    if b.compteGroupe then
        b.compteGroupe:SetText(b.ecartGroupe and tostring(b.ecartGroupe) or "")
        b.compteGroupe:SetShown(b.ecartGroupe ~= nil)
    end
end

Suite.barresFiltres = Suite.barresFiltres or {}

local function Prevenir()
    for _, barre in ipairs(Suite.barresFiltres) do
        pcall(barre.Actualiser, barre)
        if barre:IsVisible() and barre.auChangement then pcall(barre.auChangement) end
    end
end

function Suite.PoserFiltre(cle, actif, silencieux)
    Filtres()[cle] = actif and true or false
    if not silencieux then Prevenir() end
end

-- Les filtres d'une barre qu'on peut voir (le personnage a le metier...).
local function Presents(barre)
    local liste = {}
    for _, b in ipairs(barre.boutons) do
        if b.cle ~= "tout" and b.dispo() then table.insert(liste, b.cle) end
    end
    return liste
end

local function ToutMontre(barre)
    for _, cle in ipairs(Presents(barre)) do if not Suite.Filtre(cle) then return false end end
    return true
end

local function Seul(barre, cle)
    for _, c in ipairs(Presents(barre)) do
        if Suite.Filtre(c) ~= (c == cle) then return false end
    end
    return true
end

-- Un bouton, une regle pour tous : clic, afficher ou masquer ; clic droit,
-- n'afficher que lui (encore une fois : tout reafficher). Le bouton "tout"
-- affiche ou masque tout d'un coup.
local function BoutonFiltre(barre, info)
    local taille = 26
    local b = CreateFrame("Button", nil, barre)
    b:SetSize(taille, taille)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(taille * 0.8, taille * 0.8)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetPoint("CENTER")
    local cote = info.rond and taille * 0.62 or taille * 0.66
    b.icone:SetSize(cote, cote)
    if not (info.atlas and b.icone.SetAtlas and pcall(b.icone.SetAtlas, b.icone, info.atlas) and b.icone:GetAtlas()) then
        b.icone:SetTexture(info.fichier)
    end
    if info.coords then b.icone:SetTexCoord(unpack(info.coords)) end
    if info.rond and b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.teinte = info.teinte
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(taille * 1.7, taille * 1.7)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.cle, b.nom, b.groupe = info.cle, info.nomTraduit or TX(info.nom or ""), info.groupe
    b.dispo = info.dispo or function() return true end
    b:SetScript("OnClick", function(self, bouton)
        if self.cle == "tout" then
            local montrer = not ToutMontre(barre)
            for _, c in ipairs(Presents(barre)) do Filtres()[c] = montrer end
        elseif bouton == "RightButton" then
            local tout = Seul(barre, self.cle)
            for _, c in ipairs(Presents(barre)) do Filtres()[c] = tout or c == self.cle end
        else
            Filtres()[self.cle] = not Suite.Filtre(self.cle)
        end
        Prevenir()
        if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.cle == "tout" then
            GameTooltip:SetText(T_FILTRE.titreTout, 1, 0.82, 0)
            GameTooltip:AddLine(ToutMontre(barre) and T_FILTRE.masquerTout or T_FILTRE.afficherTout, 1, 1, 1)
        else
            GameTooltip:SetText(self.nom, 1, 0.82, 0)
            if not Suite.Filtre(self.cle) then GameTooltip:AddLine(T_FILTRE.masque, 0.6, 0.6, 0.6) end
            GameTooltip:AddLine(T_FILTRE.clic, 1, 1, 1)
            GameTooltip:AddLine(Seul(barre, self.cle) and T_FILTRE.tout or T_FILTRE.seul, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Lieu de recolte sur une carte : l'icone de la matiere, dans un rond cercle
-- d'or (comme le bord des cartes). lieu = { objet, x, y, n } de CraftCore.
function Suite.PionRecolte(parent, taille)
    taille = taille or 16
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(taille, taille)
    b.cercle = b:CreateTexture(nil, "BORDER")
    b.cercle:SetPoint("CENTER")
    b.cercle:SetSize(taille + 3, taille + 3)
    b.cercle:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    b.cercle:SetVertexColor(0.75, 0.6, 0.35, 1)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        local cc = _G.CraftCoreAPI
        local l = self.lieu
        local nom = l.nom or (l.objet and cc and cc.Objet and cc.Objet(l.objet))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(nom or ("#" .. tostring(l.objet)), 1, 1, 1)
        if l.base then
            GameTooltip:AddLine(TX("From the GatherMate2 database"), 0.8, 0.8, 0.8)
        elseif l.repere then
            -- Noeud vu par un personnage sans le metier : a venir recolter.
            GameTooltip:AddLine(TX("Spotted here, not gathered yet"), 1, 0.82, 0)
        else
            GameTooltip:AddLine(string.format(TX("Gathered %d times here"),
                tonumber(l.n) or 1), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Sur la minicarte : l'interieur gris et translucide, le contour en anneau
    -- dore bien visible (celui des totems du jeu), creux au milieu : le point
    -- jaune du jeu (le noeud reellement present) se voit au travers. La
    -- souris passe au jeu, qui donne le nom du noeud au survol.
    function b.Discret(self)
        local cote = self:GetWidth() or 13
        self.icone:SetDesaturated(true)
        self.icone:SetAlpha(0.4)
        self.cercle:SetTexture("Interface\\CharacterFrame\\TotemBorder")
        self.cercle:SetVertexColor(1, 1, 1, 1)
        self.cercle:SetSize(cote * 1.75, cote * 1.75)
        self.cercle:SetDrawLayer("OVERLAY")
        self:SetAlpha(1)
        self:EnableMouse(false)
    end
    function b.Poser(self, lieu)
        self.lieu = lieu
        local cc = _G.CraftCoreAPI
        local icone = lieu.icone
        if not icone and lieu.objet and cc and cc.Objet then icone = select(2, cc.Objet(lieu.objet)) end
        self.icone:SetTexture(icone or "Interface\\Icons\\INV_Misc_Herb_01")
        self.ax, self.ay = lieu.x, lieu.y
    end
    return b
end

-- Rangee de filtres sous une carte, sur toute sa largeur. A gauche : "tout",
-- puis les quetes, les reperes et la recolte ; a droite, les filtres propres
-- a l'add-on (`extras`, les services de MapCore). auChangement redessine.
local TOUT_FILTRE = { cle = "tout", fichier = "Interface\\Minimap\\Tracking\\None" }
local ORDRE_FILTRES = { "quetes", "tuer", "butin", "objet", "reperes", "herbes", "minerais", "peche" }

function Suite.BarreFiltres(parent, auChangement, carteFn, extras)
    local barre = CreateFrame("Frame", nil, parent)
    barre:SetHeight(28)
    barre.auChangement = auChangement
    barre.carteFn = carteFn
    barre.boutons = {}
    table.insert(barre.boutons, BoutonFiltre(barre, TOUT_FILTRE))
    local parCle = {}
    for _, info in ipairs(Suite.FILTRES) do parCle[info.cle] = info end
    for _, cle in ipairs(ORDRE_FILTRES) do
        if parCle[cle] then table.insert(barre.boutons, BoutonFiltre(barre, parCle[cle])) end
    end
    Suite.defautsFiltres = Suite.defautsFiltres or {}
    for _, info in ipairs(extras or {}) do
        if info.defaut == false then Suite.defautsFiltres[info.cle] = false end
        local b = BoutonFiltre(barre, info)
        b.droite = true
        table.insert(barre.boutons, b)
    end
    function barre.Actualiser(self)
        local x, PAS = 0, 34
        local avant
        -- La droite d'abord, de droite a gauche.
        local xd = 0
        for k = #self.boutons, 1, -1 do
            local b = self.boutons[k]
            if b.droite then
                local dispo = b.dispo()
                b:SetShown(dispo)
                if dispo then
                    b:ClearAllPoints()
                    b:SetPoint("RIGHT", self, "RIGHT", -xd, 0)
                    xd = xd + PAS
                end
            end
        end
        for _, b in ipairs(self.boutons) do
            if not b.droite then
                local dispo = b.dispo()
                b:SetShown(dispo)
                if dispo then
                    -- Un petit ecart entre les groupes : tout | quetes | reperes et recolte.
                    if avant and (b.cle == "quetes" or b.cle == "reperes") then x = x + 10 end
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", self, "LEFT", x, 0)
                    x = x + PAS
                    avant = b
                end
            end
        end
        for _, b in ipairs(self.boutons) do
            if b:IsShown() then
                local actif = (b.cle == "tout") or Suite.Filtre(b.cle)
                b.icone:SetDesaturated(not actif)
                if b.teinte and actif then b.icone:SetVertexColor(b.teinte[1], b.teinte[2], b.teinte[3])
                else b.icone:SetVertexColor(1, 1, 1) end
                b.icone:SetAlpha(actif and 1 or 0.4)
                b.anneau:SetDesaturated(not actif)
            end
        end
        if not self.etendue then self:SetWidth(math.max(1, x + xd)) end
    end
    -- Sur toute la largeur d'un cadre (la carte), sous lui.
    function barre.Etendre(self, cadre, ecart)
        self.etendue = true
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 4, -(ecart or 8))
        self:SetPoint("TOPRIGHT", cadre, "BOTTOMRIGHT", -4, -(ecart or 8))
    end
    barre:SetScript("OnShow", function(self) self:Actualiser() end)
    barre:Actualiser()
    table.insert(Suite.barresFiltres, barre)
    return barre
end

-- ---------------------------------------------------------------------------
-- Guidage, commun a la suite : une fleche au milieu du haut de l'ecran qui
-- montre la direction de la prochaine etape d'un objectif, avec la distance.
-- Un seul objectif guide a la fois.
--
-- Un objectif est une valeur : un proprietaire (l'add-on qui le declare), un
-- type de son catalogue et des parametres. Son identite en decoule. Chaque
-- bouton guide un objectif precis et s'y tient : il n'affiche "Arreter" que
-- si cette identite exacte est guidee.
--
-- Le guidage ne s'arrete que pour trois raisons : "atteint" (le type le dit),
-- "joueur" (arret demande) ou "remplace" (un autre objectif est lance).
-- L'objectif en cours est garde par personnage et repris apres /reload.
--
--   Suite.DeclarerObjectifs(proprietaire, { [type] = def })
--   Suite.LancerObjectif(proprietaire, type, params) -> vrai si lance
--   Suite.BasculerObjectif(proprietaire, type, params)
--   Suite.Arreter(raison) ; Suite.EstActif(proprietaire, type, params)
--   Suite.ObjectifActif() ; Suite.EtatGuidage() ; Suite.Invalider()
--   Suite.Lieux (outils geographiques) ; Suite.TypePoint(o)
--
-- def = {
--   icone, AideClic, nonPersiste,
--   Cle(params) -> texte (facultatif : identite par les parametres),
--   Libelle(params, etat) -> le nom de l'objectif,
--   Preparer(params, etat) -> false, message : pas de lancement,
--   Reprendre(params, etat) -> false : objectif oublie a la reprise,
--   Etapes(params, etat) -> etapes, raison, detail, compte
--       etapes : { { carte, x, y, titre, qui, cle }, ... }, la premiere visee ;
--       raison : nil, "atteint" (seule raison d'arret), "loin", "inconnu" ;
--       detail : texte sous "Hors de portee" ;
--       compte : { fait, total } pour "Etape X sur Y",
--   Arrivee(params, etat, etape) -> "suivante" (defaut) ou "atteint",
--   Evenements = { ... } (invalident le calcul),
--   Clic(params, etat), Fin(params, etat, raison) }
--
-- Compatibilite (TradeCore, hors depot) : Suite.Guider(cle, fournisseur),
-- Suite.ArreterGuidage(cle), Suite.GuidageActif(cle).
-- ---------------------------------------------------------------------------

local TG = Paresseux({
    titre = "Path guidance",
    aide = "Drag: move up or down. Right-click: stop guiding.",
    loin = "Out of range",
})

Suite.guide = Suite.guide or {}
Suite.catalogues = Suite.catalogues or {}

-- Le personnage connecte ("Nom - Royaume"), ou nil tant qu'il n'est pas sur.
local function ClePersoGuidage()
    local okN, nom = pcall(UnitName, "player")
    local royaume = _G.SagaCoreRoyaume and _G.SagaCoreRoyaume() or ""
    if not okN or type(nom) ~= "string" or nom == "" or type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

-- L'objectif garde de chaque personnage : CoreSuiteDB.guidage.persos.
local function Persos()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    local g = type(CoreSuiteDB.guidage) == "table" and CoreSuiteDB.guidage or {}
    CoreSuiteDB.guidage = g
    g.persos = type(g.persos) == "table" and g.persos or {}
    return g.persos
end

local function DefDe(proprietaire, nom)
    local c = Suite.catalogues[proprietaire]
    return c and c[nom]
end
local function Def(inst) return inst and DefDe(inst.proprietaire, inst.type) end

local function Identite(proprietaire, nom, params)
    local def = DefDe(proprietaire, nom)
    local s = ""
    if def and def.Cle then
        local ok, r = pcall(def.Cle, params or {})
        if ok and r ~= nil then s = tostring(r) end
    end
    return tostring(proprietaire) .. ":" .. tostring(nom) .. (s ~= "" and (":" .. s) or "")
end

function Suite.DeclarerObjectifs(proprietaire, catalogue)
    if type(proprietaire) ~= "string" or type(catalogue) ~= "table" then return end
    local c = Suite.catalogues[proprietaire] or {}
    Suite.catalogues[proprietaire] = c
    for nom, def in pairs(catalogue) do
        if type(def) == "table" then c[nom] = def end
    end
end

function Suite.ObjectifActif() return Suite.guide.actif end

function Suite.EstActif(proprietaire, nom, params)
    local a = Suite.guide.actif
    return a ~= nil and a.cle == Identite(proprietaire, nom, params)
end

-- ---------------------------------------------------------------------------
-- Outils geographiques, communs a tous les types
-- ---------------------------------------------------------------------------

local function Lire(chemin)
    local t = _G
    for morceau in string.gmatch(chemin, "[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[morceau]
    end
    return t
end

local function InfoCarte(carte)
    local f = Lire("C_Map.GetMapInfo")
    if not (f and carte) then return nil end
    local ok, info = pcall(f, carte)
    return ok and type(info) == "table" and info or nil
end

local zones = {}
Suite.Lieux = {}
local Lieux = Suite.Lieux

-- La zone (carte de type 3) d'une carte : une grotte ou une mine qui a sa
-- propre carte compte dans sa zone. Un continent reste un continent.
function Lieux.ZoneDe(carte)
    if not carte then return nil end
    if zones[carte] ~= nil then return zones[carte] end
    local c, trouve = carte, nil
    for _ = 1, 8 do
        local info = InfoCarte(c)
        if not info then break end
        if info.mapType == 3 then trouve = c break end
        if (info.mapType or 0) < 3 then break end
        c = info.parentMapID
        if not c or c == 0 then break end
    end
    zones[carte] = trouve or carte
    return zones[carte]
end

-- Un point d'une sous-carte (grotte, mine) en coordonnees de sa zone.
function Lieux.VersZone(carte, x, y)
    local zone = Lieux.ZoneDe(carte)
    if not (zone and zone ~= carte and x and y) then return carte, x, y end
    local f = Lire("C_Map.GetMapRectOnMap")
    if not f then return carte, x, y end
    local ok, minX, maxX, minY, maxY = pcall(f, carte, zone)
    if not (ok and minX and maxX and minY and maxY) or maxX == minX or maxY == minY then return carte, x, y end
    return zone, minX + x * (maxX - minX), minY + y * (maxY - minY)
end

-- Position dans le monde (yards) et continent d'un point d'une carte. Une
-- sous-carte sans position dans le monde passe par sa zone.
local function PositionMonde(carte, x, y)
    local f, V = Lire("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if not (f and V and carte and x) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        local secret = _G.issecretvalue
        if a and not (secret and (secret(a) or secret(b) or secret(continent))) then return a, b, continent end
    end
    return nil
end
function Lieux.Monde(carte, x, y)
    local a, b, c = PositionMonde(carte, x, y)
    if a then return a, b, c end
    local zc, zx, zy = Lieux.VersZone(carte, x, y)
    if zc ~= carte then return PositionMonde(zc, zx, zy) end
    return nil
end

-- Ou est le personnage : { carte, x, y, zone, continent, wx, wy }, ou nil.
function Lieux.Ici()
    local f, g = Lire("C_Map.GetBestMapForUnit"), Lire("C_Map.GetPlayerMapPosition")
    if not (f and g) then return nil end
    local secret = _G.issecretvalue
    local okC, carte = pcall(f, "player")
    if not okC or not carte or (secret and secret(carte)) then return nil end
    local okP, pos = pcall(g, carte, "player")
    if not (okP and type(pos) == "table" and pos.GetXY) then return nil end
    local okX, x, y = pcall(pos.GetXY, pos)
    if not okX or not x or (secret and (secret(x) or secret(y))) then return nil end
    local wx, wy, continent = Lieux.Monde(carte, x, y)
    return { carte = carte, x = x, y = y, zone = Lieux.ZoneDe(carte), continent = continent, wx = wx, wy = wy }
end

local function Coord(p)
    if p.wx then return p.wx, p.wy end
    return p.x, p.y
end
local function Ecart(a, b)
    local ax, ay = Coord(a)
    local bx, by = Coord(b)
    if not (ax and bx) then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
Lieux.Distance = Ecart

-- Le plus proche du depart, puis le plus proche du precedent, et ainsi de
-- suite (au plus `maxi` points). `memoire` (facultatif) garde la cible
-- visee : elle reste la premiere tant qu'une autre n'est pas au moins 20 %
-- plus proche, pour que la fleche ne saute pas d'un point a l'autre.
function Lieux.Chaine(points, depart, maxi, memoire)
    local reste, ordre = {}, {}
    for _, p in ipairs(points or {}) do table.insert(reste, p) end
    local ici = depart
    maxi = maxi or math.huge
    while #reste > 0 and #ordre < maxi do
        local meilleur, rang
        for k, p in ipairs(reste) do
            local d = ici and Ecart(ici, p) or 0
            if not meilleur or d < meilleur then meilleur, rang = d, k end
        end
        if #ordre == 0 and memoire and memoire.visee and ici then
            for k, p in ipairs(reste) do
                if p.cle ~= nil and p.cle == memoire.visee and k ~= rang then
                    if meilleur >= Ecart(ici, p) * 0.8 then rang = k end
                    break
                end
            end
        end
        local p = table.remove(reste, rang)
        table.insert(ordre, p)
        ici = p
    end
    if memoire then memoire.visee = ordre[1] and ordre[1].cle end
    return ordre
end

-- 2-opt : retourne un morceau du trajet tant que cela le raccourcit.
function Lieux.Decroiser(trajet, depart)
    local ameliore, tours = true, 0
    while ameliore and tours < 50 do
        ameliore, tours = false, tours + 1
        for i = 1, #trajet - 1 do
            for j = i + 1, #trajet do
                local a = (i == 1) and depart or trajet[i - 1]
                local b, c, d = trajet[i], trajet[j], trajet[j + 1]
                if a then
                    local avant = Ecart(a, b) + (d and Ecart(c, d) or 0)
                    local apres = Ecart(a, c) + (d and Ecart(b, d) or 0)
                    if apres + 1e-6 < avant then
                        local g, h = i, j
                        while g < h do
                            trajet[g], trajet[h] = trajet[h], trajet[g]
                            g, h = g + 1, h - 1
                        end
                        ameliore = true
                    end
                end
            end
        end
    end
    return trajet
end

-- Un type "un point" : guide jusqu'a lui, atteint a l'arrivee.
function Suite.TypePoint(o)
    o = o or {}
    return {
        icone = o.icone, AideClic = o.AideClic, Clic = o.Clic, Fin = o.Fin,
        Cle = function(p)
            return string.format("%s:%d:%d", tostring(p.carte), math.floor((tonumber(p.x) or 0) * 1000),
                math.floor((tonumber(p.y) or 0) * 1000))
        end,
        Libelle = function(p) return p.nom end,
        Preparer = function(p)
            if not (p.carte and tonumber(p.x) and tonumber(p.y)) then return false end
            return true
        end,
        Etapes = function(p)
            return { { carte = p.carte, x = p.x, y = p.y, titre = p.nom, qui = p.nom, cle = "point" } }
        end,
        Arrivee = function() return "atteint" end,
    }
end

-- ---------------------------------------------------------------------------
-- La fleche
-- ---------------------------------------------------------------------------

-- La fleche de l'add-on d'itineraire choisi, s'il en montre une : Shortest
-- Path Forever (cadre sans nom, reconnu a ses elements), TomTom (nomme).
-- Cherchee une fois, puis gardee.
local flecheExterne, dernierEssaiFleche = nil, 0
local function FlecheExterne()
    if flecheExterne then return flecheExterne end
    local maintenant = GetTime and GetTime() or 0
    if maintenant - dernierEssaiFleche < 5 then return nil end
    dernierEssaiFleche = maintenant
    if _G.TomTomCrazyArrow then flecheExterne = _G.TomTomCrazyArrow return flecheExterne end
    if not _G.EnumerateFrames then return nil end
    local ok, trouve = pcall(function()
        local f = _G.EnumerateFrames()
        while f do
            if f.Icon and f.Distance and f.Progress and f.Lines and f.ArrivalTitle and f:GetParent() == UIParent then return f end
            f = _G.EnumerateFrames(f)
        end
    end)
    if ok and trouve then flecheExterne = trouve end
    return flecheExterne
end
-- La marge fixe entre nos lignes et le haut du cadre de l'add-on de trajet.
local MARGE_FLECHE_EXTERNE = 24

-- Ce que l'add-on de trajet pose a la place de sa fleche quand l'etape est
-- un objet a utiliser (Shortest Path Forever : l'icone de l'objet et son
-- action, « Utiliser Pierre de foyer »). Cree tard : cherche toutes les 5 s.
local invite, dernierEssaiInvite = nil, 0
local function InviteExterne()
    if invite then return invite end
    local maintenant = GetTime and GetTime() or 0
    if maintenant - dernierEssaiInvite < 1 then return nil end
    dernierEssaiInvite = maintenant
    if not _G.EnumerateFrames then return nil end
    local ok, trouve = pcall(function()
        local f = _G.EnumerateFrames()
        while f do
            if f.Icon and f.Action and not f.Distance and f:GetParent() == UIParent then return f end
            f = _G.EnumerateFrames(f)
        end
    end)
    if ok and trouve then invite = trouve end
    return invite
end

-- Tout ce que l'add-on de trajet montre en ce moment : sa fleche, son
-- invite d'objet.
local function AffichageExterne()
    local liste = {}
    for _, f in ipairs({ FlecheExterne() or false, InviteExterne() or false }) do
        if f and f.IsShown and f:IsShown() then table.insert(liste, f) end
    end
    return liste
end

-- L'encombrement reel de l'add-on de trajet a l'ecran : son cadre, tout ce
-- qu'il dessine (textes, icones) et ses sous-cadres visibles, quels que
-- soient leurs noms. En pixels d'ecran : gauche, droite, bas, haut.
local function EncombrementDe(f)
    local g, d, b, h
    local function Prendre(e)
        if not (e and e.IsVisible and e:IsVisible() and e.GetLeft) then return end
        if e.GetText and not e.GetChildren and (e:GetText() or "") == "" then return end
        if e.GetAlpha and (e:GetAlpha() or 1) <= 0.01 then return end
        local l, r, bo, t = e:GetLeft(), e:GetRight(), e:GetBottom(), e:GetTop()
        if not (l and r and bo and t) then return end
        local k = e.GetEffectiveScale and e:GetEffectiveScale() or 1
        l, r, bo, t = l * k, r * k, bo * k, t * k
        g = g and math.min(g, l) or l
        d = d and math.max(d, r) or r
        b = b and math.min(b, bo) or bo
        h = h and math.max(h, t) or t
    end
    local function Parcourir(e, profondeur)
        Prendre(e)
        if e.GetRegions then for _, r in ipairs({ e:GetRegions() }) do Prendre(r) end end
        if profondeur > 0 and e.GetChildren then
            for _, enfant in ipairs({ e:GetChildren() }) do
                if enfant.IsVisible and enfant:IsVisible() then Parcourir(enfant, profondeur - 1) end
            end
        end
    end
    Parcourir(f, 3)
    return g, d, b, h
end

local Finir, Calculer

local function CadreObjectifs()
    local g = Suite.guide
    if g.cadreObjectifs then return g.cadreObjectifs end
    local c = CreateFrame("Button", "CoreSuiteGuidage", UIParent)
    c:SetSize(64, 64)
    c:SetFrameStrata("HIGH")
    c:SetClampedToScreen(true)
    c:SetMovable(true)
    c:RegisterForDrag("LeftButton")
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:SetPoint("TOP", UIParent, "TOP", 0, Reglages().guidageY or -110)
    c:SetScript("OnDragStart", function(self) self:StartMoving() end)
    c:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Le clic qui suit tout juste un glisser ne compte pas.
        self.finGlisser = GetTime and GetTime() or 0
        -- Toujours au milieu de l'ecran : on ne la deplace qu'en hauteur.
        local echelle = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local y = math.min(0, (self:GetTop() or 0) * echelle - (UIParent:GetHeight() or 0))
        Reglages().guidageY = math.floor(y + 0.5)
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "TOP", 0, Reglages().guidageY)
    end)
    c:SetScript("OnClick", function(self, bouton)
        if self.finGlisser and GetTime and GetTime() - self.finGlisser < 0.3 then return end
        if bouton == "RightButton" then Suite.Arreter("joueur") return end
        local inst = Suite.guide.actif
        local def = Def(inst)
        if def and def.Clic then pcall(def.Clic, inst.params, inst.etat) end
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(TG.titre, 1, 0.82, 0)
        if self.titre then GameTooltip:AddLine(self.titre, 1, 1, 1) end
        local def = Def(Suite.guide.actif)
        local aideClic = def and def.AideClic
        if type(aideClic) == "function" then local okA, t = pcall(aideClic) aideClic = okA and t or nil end
        if type(aideClic) == "string" then GameTooltip:AddLine(aideClic, 0.7, 0.7, 0.7, true) end
        GameTooltip:AddLine(TG.aide, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Une boussole : un anneau au centre, et la fleche qui tourne autour vers
    -- la destination. Anneau et fleche de la meme couleur (doree, verte
    -- quand on va droit dessus).
    c.boussole = c:CreateTexture(nil, "ARTWORK")
    c.boussole:SetSize(54, 54)
    c.boussole:SetPoint("TOPLEFT", c, "CENTER", -16, 16)
    c.boussole:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    c.fondBoussole = c:CreateTexture(nil, "BACKGROUND")
    c.fondBoussole:SetSize(25, 25)
    c.fondBoussole:SetPoint("CENTER")
    c.fondBoussole:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    -- Dans l'anneau, l'icone de ce qu'on guide (quete, recolte, carte...).
    c.icone = c:CreateTexture(nil, "ARTWORK", nil, -1)
    c.icone:SetSize(22, 22)
    c.icone:SetPoint("CENTER")
    if c.icone.SetMask then pcall(c.icone.SetMask, c.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    c.fleche = c:CreateTexture(nil, "OVERLAY")
    c.fleche:SetSize(30, 30)
    c.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    c.fleche:SetPoint("CENTER")
    c.arrivee = c:CreateTexture(nil, "OVERLAY")
    c.arrivee:SetSize(22, 22)
    c.arrivee:SetPoint("CENTER")
    c.arrivee:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    c.distance = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.distance:SetPoint("TOP", c, "BOTTOM", 0, -2)
    -- Duree estimee, en petit, sous la distance.
    c.temps = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.temps:SetPoint("TOP", c.distance, "BOTTOM", 0, -1)
    c.temps:SetTextColor(0.8, 0.8, 0.8)
    c.qui = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.qui:SetPoint("TOP", c.temps, "BOTTOM", 0, -1)
    -- Sous la fleche d'un add-on d'itineraire, de haut en bas : l'add-on de
    -- la suite et son objectif (QuestCore : Vers le niveau 25), le compte des
    -- etapes quand il y en a plusieurs (Etape 2 sur 6), puis Changer de guide.
    -- Toujours sur une ligne : un libelle trop long est coupe.
    c.etape = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.etape:SetWidth(320)
    c.etape:SetJustifyH("CENTER")
    c.etape:SetWordWrap(false)
    c.etape:SetShadowOffset(1, -1)
    c.etape:Hide()
    c.compte = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.compte:SetWidth(320)
    c.compte:SetJustifyH("CENTER")
    c.compte:SetWordWrap(false)
    c.compte:SetShadowOffset(1, -1)
    c.compte:Hide()
    -- Ce qu'il faut faire a l'etape visee (prendre chez, objectif, rendre a),
    -- sous le compte : on sait toujours ou on en est.
    c.action = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.action:SetWidth(420)
    c.action:SetJustifyH("CENTER")
    c.action:SetWordWrap(false)
    c.action:SetShadowOffset(1, -1)
    c.action:Hide()
    -- Sous la boussole, pour tous les guidages : changer de guide en route
    -- (quand un add-on d'itineraire est installe).
    -- Une rangee de deux boutons, toujours la pendant un guidage :
    -- « Changer de guide » (si un add-on de trajet est installe) et
    -- « Arreter », qui coupe le guidage en cours, d'ou qu'il vienne.
    c.changer = CreateFrame("Frame", nil, c)
    c.changer:SetSize(130 + 4 + 90, 20)
    c.changer:SetPoint("TOP", c.qui, "BOTTOM", 0, -6)
    c.btnChanger = CreateFrame("Button", "CoreSuiteGuidageChanger", c.changer, "UIPanelButtonTemplate")
    c.btnChanger:SetSize(130, 20)
    c.btnChanger:SetText(TX("Change guide"))
    c.btnChanger:SetScript("OnClick", function() Suite.ChangerDeGuide() end)
    c.btnSuivante = CreateFrame("Button", "CoreSuiteGuidageSuivante", c.changer, "UIPanelButtonTemplate")
    c.btnSuivante:SetSize(90, 20)
    c.btnSuivante:SetText(TX("Next"))
    c.btnSuivante:SetScript("OnClick", function() Suite.EtapeSuivante() end)
    c.btnArreter = CreateFrame("Button", "CoreSuiteGuidageArreter", c.changer, "UIPanelButtonTemplate")
    c.btnArreter:SetSize(90, 20)
    c.btnArreter:SetText(TX("Stop"))
    c.btnArreter:SetScript("OnClick", function() Suite.Arreter("joueur") end)
    -- Les boutons visibles, cote a cote et centres : Changer de guide (si un
    -- add-on de trajet est installe), Suivante (s'il y a plusieurs etapes),
    -- Arreter (toujours).
    function c.changer.Poser(peutChanger, plusieurs)
        local vus = {}
        c.btnChanger:SetShown(peutChanger and true or false)
        c.btnSuivante:SetShown(plusieurs and true or false)
        if peutChanger then table.insert(vus, c.btnChanger) end
        if plusieurs then table.insert(vus, c.btnSuivante) end
        table.insert(vus, c.btnArreter)
        local largeur = 0
        for _, b in ipairs(vus) do largeur = largeur + b:GetWidth() end
        largeur = largeur + 4 * (#vus - 1)
        c.changer:SetWidth(largeur)
        local x = 0
        for _, b in ipairs(vus) do
            b:ClearAllPoints()
            b:SetPoint("LEFT", c.changer, "LEFT", x, 0)
            x = x + b:GetWidth() + 4
        end
    end
    c.changer.Poser(false, false)
    c.changer:Hide()
    local attente = 0
    c:SetScript("OnUpdate", function(self, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.05
        local inst = Suite.guide.actif
        if not inst then self:Hide() return end
        local peutChanger = Suite.PeutChangerDeGuide and Suite.PeutChangerDeGuide() or false
        local calculVu = Suite.guide.calcul
        local plusieurs = type(calculVu) == "table" and (calculVu.total or 0) > 1 and Def(inst) and Def(inst).Passer ~= nil or false
        if self.changer.peut ~= peutChanger or self.changer.plusieurs ~= plusieurs then
            self.changer.peut, self.changer.plusieurs = peutChanger, plusieurs
            self.changer.Poser(peutChanger, plusieurs)
        end
        self.changer:Show()
        -- En marche, le bouton s'efface presque (10 %) : on sait qu'il est
        -- la ; a l'arret, il revient et se clique.
        local vM = Suite.VitesseJoueur()
        local enMarche = vM ~= nil and vM > 0
        local vise = enMarche and 0.1 or 1
        local a = self.changer:GetAlpha() or 1
        if a ~= vise then
            a = (a < vise) and math.min(vise, a + 0.15) or math.max(vise, a - 0.15)
            self.changer:SetAlpha(a)
        end
        self.btnChanger:EnableMouse(not enMarche)
        self.btnSuivante:EnableMouse(not enMarche)
        self.btnArreter:EnableMouse(not enMarche)
        local calcul = Calculer()
        -- Objectif atteint pendant le calcul : tout est deja range.
        if Suite.guide.actif ~= inst then return end
        local cible = calcul and type(calcul.etapes) == "table" and calcul.etapes[1] or nil
        local hub = _G.FriendsCoreAPI
        if not cible then
            -- Rien a viser pour l'instant (autre continent, aucun lieu
            -- connu...) : le guidage reste, la boussole dit ou aller ; l'add-on
            -- de trajet n'a plus rien a suivre (une seule fleche a l'ecran).
            -- Toujours effacer la fleche de l'add-on de trajet : sinon elle
            -- reste sous la boussole de la suite (deux affichages superposes).
            -- Pas tout de suite : une cible qui manque un instant (calcul en
            -- cours, position pas encore lue) ne doit pas effacer le trajet
            -- de l'add-on, sinon il recalcule sans fin et ne s'affiche jamais.
            local maintenantSC = (_G.GetTime and _G.GetTime()) or 0
            Suite.guide.sansCibleDepuis = Suite.guide.sansCibleDepuis or maintenantSC
            local longtemps = maintenantSC - Suite.guide.sansCibleDepuis > 3
            if longtemps and hub and hub.Effacer and (Suite.guide.envoye or not Suite.guide.effaceSansCible) then
                Suite.guide.envoye = nil
                Suite.guide.effaceSansCible = true
                pcall(hub.Effacer)
            end
            for _, e in ipairs({ self.boussole, self.fondBoussole, self.icone, self.distance, self.temps, self.qui }) do e:Show() end
            self:EnableMouse(true)
            self.etape:Hide() self.compte:Hide() self.action:Hide()
            self.changer:ClearAllPoints()
            self.changer:SetPoint("TOP", self.qui, "BOTTOM", 0, -6)
            self.fleche:Hide() self.arrivee:Hide() self.temps:SetText("")
            self.distance:SetText(TG.loin)
            self.qui:SetText(type(calcul and calcul.detail) == "string" and calcul.detail or "")
            return
        end
        Suite.guide.effaceSansCible = nil
        Suite.guide.sansCibleDepuis = nil
        self.titre = cible.titre
        local rang, total = calcul.rang or 1, calcul.total or 1
        if total > 1 then
            self.qui:SetText(string.format("%d/%d  %s", rang, total, cible.qui or ""))
        else
            self.qui:SetText(cible.qui or "")
        end
        -- Un add-on de trajet installe (reconnu par FriendsCore) : c'est lui qui
        -- donne le chemin. La suite lui passe chaque etape et n'affiche plus
        -- de fleche. Sans lui, la fleche de la suite. Jamais les deux.
        -- Les deux sont la et rien n'est choisi pour cet objectif : on demande.
        if hub and hub.ADecider and not inst.guide and hub.ADecider() then Suite.ChoisirGuide() end
        local externe = hub and hub.Disponible and hub.NomTrajet and hub.Disponible() and hub.NomTrajet() or nil
        self.modeExterne = externe and true or false
        for _, e in ipairs({ self.boussole, self.fondBoussole, self.icone, self.distance, self.temps, self.qui }) do
            e:SetShown(not externe)
        end
        self:EnableMouse(not externe)
        -- La fleche de l'add-on d'itineraire met un instant a paraitre : en
        -- attendant (au plus 2 s), rien sous elle, pour ne pas s'afficher au
        -- milieu de sa boussole puis sauter dessous.
        local vus = externe and AffichageExterne() or {}
        local maintenant = (_G.GetTime and _G.GetTime()) or 0
        if not externe then self.debutExterne = nil
        elseif not self.debutExterne then self.debutExterne = maintenant end
        -- Plus d'attente : la place de nos lignes est connue d'avance (le
        -- haut du cadre de l'add-on, montre ou pas), elles s'y posent tout
        -- de suite et n'en bougent plus quand ses elements paraissent.
        local enAttenteFleche = false
        self.etape:ClearAllPoints()
        self.compte:ClearAllPoints()
        self.changer:ClearAllPoints()
        if externe and not enAttenteFleche then
            -- Nos lignes en une colonne, au-dessus de TOUT ce que l'add-on
            -- de trajet dessine (sous lui s'il touche le haut de l'ecran) :
            -- jamais sur ses textes, jamais l'une sur l'autre.
            local dessus = true
            local g, d, b, h
            for _, f in ipairs(vus) do
                local g2, d2, b2, h2 = EncombrementDe(f)
                if g2 then
                    g = g and math.min(g, g2) or g2
                    d = d and math.max(d, d2) or d2
                    b = b and math.min(b, b2) or b2
                    h = h and math.max(h, h2) or h2
                end
            end
            -- La place reservee : le cadre de la fleche et celui de l'invite
            -- d'objet, meme caches (tout ce que l'add-on dessine pend sous
            -- leur haut), plus une marge fixe. Toujours la meme hauteur.
            for _, f in ipairs({ FlecheExterne() or false, InviteExterne() or false }) do
                if f and f.GetTop and f:GetTop() and f:GetLeft() and f:GetRight() then
                    local k = f.GetEffectiveScale and f:GetEffectiveScale() or 1
                    local t, l, r, bo = f:GetTop() * k, f:GetLeft() * k, f:GetRight() * k, (f:GetBottom() or f:GetTop()) * k
                    t = t + MARGE_FLECHE_EXTERNE * k
                    g = g and math.min(g, l) or l
                    d = d and math.max(d, r) or r
                    b = b and math.min(b, bo) or bo
                    h = h and math.max(h, t) or t
                end
            end
            local kU = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local kC = self.changer.GetEffectiveScale and self.changer:GetEffectiveScale() or kU
            if g then
                local ecran = ((UIParent.GetTop and UIParent:GetTop()) or 768) * kU
                local x = (g + d) / 2
                dessus = h + 70 * kC < ecran
                if dessus then
                    self.changer:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / kC, (h + 8 * kC) / kC)
                else
                    self.etape:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / kC, (b - 8 * kC) / kC)
                end
            else
                self.changer:SetPoint("BOTTOM", self, "TOP", 0, MARGE_FLECHE_EXTERNE)
            end
            local nomP = Def(inst) and Def(inst).nomProprietaire or inst.proprietaire
            local quoi = inst.libelle
            if type(quoi) ~= "string" or quoi == "" then quoi = cible.guidage or cible.titre end
            quoi = type(quoi) == "string" and quoi:gsub("[\r\n].*$", "") or ""
            local ligne = "|cffffd100" .. tostring(nomP) .. "|r"
            if quoi ~= "" then ligne = ligne .. " : " .. quoi end
            self.etape:SetText(ligne)
            self.etape:Show()
            if total > 1 then
                self.compte:SetText(string.format(TX("Step %d of %d"), rang, total))
                self.compte:Show()
            else
                self.compte:Hide()
            end
            -- L'action de l'etape visee : « Titre : prendre chez X », sur une
            -- ligne (le titre et l'action de la cible, sans retour a la ligne).
            local action = type(cible.qui) == "string" and cible.qui or ""
            action = action:gsub("\n", " : ")
            if action ~= "" and action ~= quoi then
                self.action:SetText(action)
                self.action:Show()
            else
                self.action:Hide()
            end
            -- Les lignes affichees, de haut en bas.
            local colonne = { self.etape }
            if self.compte:IsShown() then table.insert(colonne, self.compte) end
            if self.action:IsShown() then table.insert(colonne, self.action) end
            self.action:ClearAllPoints()
            if dessus then
                -- De bas en haut : bouton, puis les lignes.
                local dessous = self.changer
                for k = #colonne, 1, -1 do
                    colonne[k]:SetPoint("BOTTOM", dessous, "TOP", 0, dessous == self.changer and 4 or 2)
                    dessous = colonne[k]
                end
            else
                for k = 2, #colonne do colonne[k]:SetPoint("TOP", colonne[k - 1], "BOTTOM", 0, -2) end
                self.changer:SetPoint("TOP", colonne[#colonne], "BOTTOM", 0, -6)
            end
        else
            self.etape:Hide()
            self.compte:Hide()
            self.action:Hide()
            if externe then
                self.changer:SetPoint("TOP", self, "CENTER", 0, 0)
                self.changer:Hide()
            else
                self.changer:SetPoint("TOP", self.qui, "BOTTOM", 0, -6)
            end
        end
        -- Plus d'add-on de trajet pour ce guidage : ce qu'on lui avait envoye
        -- s'efface, la fleche de la suite reste seule.
        -- Une fois au moins, meme sans rien envoye : une fleche restee d'un
        -- guidage precedent ne doit jamais se superposer a celle-ci.
        if not externe and hub and hub.Effacer and (Suite.guide.envoye or not Suite.guide.effaceInterne) then
            Suite.guide.envoye = nil
            Suite.guide.effaceInterne = true
            pcall(hub.Effacer)
        end
        if externe then Suite.guide.effaceInterne = nil end
        if externe then
            self.fleche:Hide() self.arrivee:Hide()
            -- Un point sous la carte d'une grotte part avec sa zone.
            local zc, zx, zy = Lieux.VersZone(cible.carte, cible.x, cible.y)
            local cleE = tostring(zc) .. ":" .. math.floor((zx or 0) * 1000) .. ":" .. math.floor((zy or 0) * 1000)
            if Suite.guide.envoye ~= cleE and hub.Trajet then
                Suite.guide.envoye = cleE
                pcall(hub.Trajet, { carte = zc, x = zx, y = zy, titre = cible.titre or cible.qui, depuisSuite = true })
            end
            self.temps:SetText("")
            self.distance:SetText(TX("Follow the route of") .. " " .. externe)
        end
        local ici = Lieux.Ici()
        local ax, ay, ca
        if ici then ax, ay, ca = ici.wx, ici.wy, ici.continent end
        local bx, by, cb = Lieux.Monde(cible.carte, cible.x, cible.y)
        if externe and not (ax and bx and (not (ca and cb) or ca == cb)) then return end
        if not (ax and bx) or (ca and cb and ca ~= cb) then
            self.fleche:Hide() self.arrivee:Hide() self.temps:SetText("")
            self.distance:SetText(TG.loin)
            return
        end
        local nord, ouest = bx - ax, by - ay
        local yards = math.sqrt(nord * nord + ouest * ouest)
        if externe and yards >= 12 then self.arrivee:Hide() return end
        if not externe then self.distance:SetText(string.format("%d m", math.floor(yards * 0.9144 + 0.5))) end
        -- Duree estimee : a la vitesse actuelle (monture comprise), sinon a
        -- la vitesse de course a pied (7 yards par seconde).
        local vitesse = Suite.VitesseJoueur() or 0
        if vitesse < 1 then vitesse = 7 end
        local sec = math.floor(yards / vitesse + 0.5)
        if sec >= 60 then
            self.temps:SetText(string.format("%d min %02d s", math.floor(sec / 60), sec % 60))
        else
            self.temps:SetText(string.format("%d s", sec))
        end
        if yards < 12 then
            self.fleche:Hide()
            self.arrivee:SetShown(not externe)
            self.temps:SetText("")
            self.boussole:SetVertexColor(0.4, 1, 0.4)
            -- Une fois par destination : le type dit si l'objectif est
            -- atteint ; sinon la cible suivante est calculee tout de suite.
            local cleA = cible.cle and (tostring(inst.cle) .. "|" .. tostring(cible.cle))
                or (tostring(cible.carte) .. ":" .. math.floor((cible.x or 0) * 1000) .. ":" .. math.floor((cible.y or 0) * 1000))
            if Suite.guide.arrivee ~= cleA then
                Suite.guide.arrivee = cleA
                local def = Def(inst)
                local res = "suivante"
                if def and def.Arrivee then
                    local okA, r = pcall(def.Arrivee, inst.params, inst.etat, cible)
                    if okA and r then res = r end
                end
                local M = _G.SagaCoreMessages
                if M and M.Dire then pcall(M.Dire, "MapCore", "arrivee", { lieu = cible.qui or cible.titre or "" }, nil, cleA) end
                if res == "atteint" then Finir("atteint") return end
                Suite.Invalider()
            end
            return
        end
        self.arrivee:Hide()
        self.fleche:Show()
        local face = tonumber(_G.GetPlayerFacing and _G.GetPlayerFacing()) or 0
        local angle = math.atan2(ouest, nord) - face
        if self.fleche.SetRotation then self.fleche:SetRotation(angle) end
        -- La fleche tourne autour de l'anneau, du cote de la destination.
        self.fleche:ClearAllPoints()
        self.fleche:SetPoint("CENTER", self, "CENTER", -math.sin(angle) * 24, math.cos(angle) * 24)
        -- Verte quand on va droit dessus, doree sinon (anneau et fleche).
        local ecart = math.abs(((angle + math.pi) % (2 * math.pi)) - math.pi)
        if ecart < 0.35 then
            self.fleche:SetVertexColor(0.4, 1, 0.4)
            self.boussole:SetVertexColor(0.4, 1, 0.4)
        else
            self.fleche:SetVertexColor(1, 0.82, 0)
            self.boussole:SetVertexColor(1, 1, 1)
        end
    end)
    c:Hide()
    g.cadreObjectifs = c
    return c
end

-- La fleche de la suite choisie pour l'objectif en cours (le choix est garde
-- dans l'objectif, donc apres /reload) : l'add-on de trajet n'a plus rien a
-- guider. Le guidage continue.
local function ChoisirFlecheSuite()
    local hub = _G.FriendsCoreAPI
    local a = Suite.guide.actif
    if a then a.guide = "aucun" end
    if hub and hub.Choisir then pcall(hub.Choisir, "aucun") end
    if hub and hub.Effacer then pcall(hub.Effacer) end
    Suite.guide.envoye = nil
end

-- Qui guide ? Un add-on de trajet est installe (Shortest Path Forever...) et
-- le joueur n'a pas encore choisi pour cet objectif : une petite fenetre
-- propose l'un ou la fleche de la suite. Fermer sans choisir garde la fleche
-- de la suite, sans arreter le guidage.
function Suite.ChoisirGuide()
    local hub = _G.FriendsCoreAPI
    if not (hub and hub.Moyens and hub.Choisir) then return end
    local f = Suite.choixGuide
    if f and f:IsShown() then return end
    if not f then
        -- Une fenetre de la suite, a sa charte (comme MacroCore).
        local charte = NS.charte
        if not (charte and charte.Fenetre) then return end
        f = charte.Fenetre("CoreSuiteQuiGuide", 260, 160, { portrait = false, strate = "DIALOG", sansPied = true })
        f.texte = f.zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.texte:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, 0)
        f.texte:SetPoint("RIGHT", f.zone, "RIGHT", 0, 0)
        f.texte:SetJustifyH("LEFT")
        f.texte:SetWordWrap(false)
        f.boutons = {}
        -- Le petit i : comment ajouter les add-ons d'itineraire qui manquent.
        local info = CreateFrame("Button", nil, f)
        info:SetSize(16, 16)
        info:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
        info:SetFrameLevel(f:GetFrameLevel() + 20)
        info:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
        info:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        info:SetScript("OnEnter", function()
            -- Toujours au meme endroit : contre le bord droit de la fenetre.
            GameTooltip:SetOwner(f, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
            GameTooltip:SetText(TX("Route add-ons"), 1, 0.82, 0)
            GameTooltip:AddLine(TX("Shortest Path Forever and TomTom draw a detailed route. Install them with CurseForge or WowUp, then restart the game : they become available here."), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        info:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.note = f.zone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.note:SetJustifyH("LEFT")
        f.note:SetWordWrap(false)
        -- Fermer sans choisir (croix, B, Echap) : la fleche de la suite.
        if f.fermer then f.fermer:SetScript("OnClick", function() f:Hide() end) end
        -- Fermer sans choisir (croix, B, Echap, Annuler) annule la manoeuvre :
        -- au lancement, le guidage n'a pas lieu ; en changeant de guide, le
        -- guide d'avant reste.
        f:HookScript("OnHide", function(self)
            if not self.choisi and Suite.guide.actif then Suite.AnnulerChoixDuGuide() end
            self.choisi = true
        end)
        f.annuler = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.annuler:SetSize(100, 22)
        f.annuler:SetText(TX("Cancel"))
        f.annuler:SetScript("OnClick", function() f:Hide() end)
        -- Manette : la croix haut / bas passe d'un choix a l'autre (le choix
        -- s'allume), A valide, B ferme (fleche de la suite).
        function f.Allumer(i)
            local vus = {}
            for _, b in ipairs(f.boutons) do if b:IsShown() and b:IsEnabled() then table.insert(vus, b) end end
            if f.annuler and f.annuler:IsShown() then table.insert(vus, f.annuler) end
            if #vus == 0 then return end
            i = math.max(1, math.min(#vus, i or 1))
            f.rang = i
            for k, b in ipairs(vus) do if k == i then b:LockHighlight() else b:UnlockHighlight() end end
            f.vus = vus
        end
        if f.EnableGamePadButton then
            f:SetScript("OnGamePadButtonDown", function(_, bouton)
                if bouton == "PADDUP" then f.Allumer((f.rang or 1) - 1)
                elseif bouton == "PADDDOWN" then f.Allumer((f.rang or 1) + 1)
                elseif bouton == "PAD1" then local b = f.vus and f.vus[f.rang or 1] if b then b:Click("LeftButton") end
                elseif bouton == "PAD2" then f:Hide()
                end
            end)
            f:HookScript("OnShow", function(self) pcall(self.EnableGamePadButton, self, true) end)
            f:HookScript("OnHide", function(self) pcall(self.EnableGamePadButton, self, false) end)
        end
        f.choisi = true
        f:Hide()
        Suite.choixGuide = f
    end
    -- Tous les add-ons d'itineraire connus : ceux qui manquent, grises.
    local choix, manque = {}, false
    local tous = hub.Tous and hub.Tous() or hub.Moyens()
    for _, m in ipairs(tous) do
        table.insert(choix, { cle = m.cle, nom = m.nom, absent = m.installe == false })
        if m.installe == false then manque = true end
    end
    table.insert(choix, { cle = "aucun", nom = "Forever SagaCore" })
    if f.titre then f.titre:SetText(TX("Who guides you?")) end
    f.texte:SetText(TX("You can change it later in FriendsCore."))
    for _, b in ipairs(f.boutons) do b:Hide() end
    local largeur = 260 - 2 * ((NS.charte and NS.charte.MARGE) or 12) - 10
    for k, ch in ipairs(choix) do
        local b = f.boutons[k]
        if not b then
            b = CreateFrame("Button", "CoreSuiteQuiGuide" .. k, f.zone, "UIPanelButtonTemplate")
            b:SetSize(largeur, 22)
            f.boutons[k] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, -22 - (k - 1) * 28)
        b:SetText(ch.nom)
        b:SetEnabled(not ch.absent)
        local cle = ch.cle
        b:SetScript("OnClick", function()
            f.choisi = true
            Suite.guideAvantChangement = nil
            if cle == "aucun" then
                ChoisirFlecheSuite()
            else
                hub.Choisir(cle)
                if Suite.guide.actif then Suite.guide.actif.guide = cle end
                Suite.guide.envoye = nil
            end
            f:Hide()
        end)
        b:Show()
    end
    -- Sous les boutons : ce que veut dire un choix grise.
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, -22 - #choix * 28 - 2)
    f.note:SetPoint("RIGHT", f.zone, "RIGHT", 0, 0)
    f.note:SetText(manque and TX("Greyed : add-on not installed (see the i).") or "")
    f.note:SetShown(manque)
    -- Annuler, sous tout le reste, a droite.
    f.annuler:ClearAllPoints()
    f.annuler:SetPoint("TOPRIGHT", f.zone, "TOPRIGHT", 0, -22 - #choix * 28 - (manque and 16 or 0) - 6)
    f.annuler:Show()
    -- Barre de titre, marge, texte, boutons, note, Annuler, marge.
    f:SetHeight(24 + 12 + 22 + #choix * 28 + (manque and 16 or 0) + 28 + 12 + 8)
    f:ClearAllPoints()
    -- Toujours au meme endroit, au milieu de l'ecran : on ne peut pas la rater.
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f.choisi = false
    f:Show()
    f.Allumer(1)
end

-- Changer de guide en cours de route (le guidage continue) : la question
-- "Qui vous guide ?" revient tout de suite.
function Suite.PeutChangerDeGuide()
    local hub = _G.FriendsCoreAPI
    return hub and hub.Moyens and #hub.Moyens() > 0 and Suite.guide.actif ~= nil or false
end
-- Annuler « Qui vous guide ? » : au lancement, le guidage s'arrete ; en
-- changeant de guide, l'ancien guide reprend.
function Suite.AnnulerChoixDuGuide()
    local ancien = Suite.guideAvantChangement
    Suite.guideAvantChangement = nil
    local hub = _G.FriendsCoreAPI
    if ancien == nil then Suite.Arreter("joueur") return end
    if ancien == "aucun" then ChoisirFlecheSuite() return end
    if hub and hub.Choisir then pcall(hub.Choisir, ancien) end
    if Suite.guide.actif then Suite.guide.actif.guide = ancien end
    Suite.guide.envoye = nil
end

function Suite.ChangerDeGuide()
    local hub = _G.FriendsCoreAPI
    Suite.guideAvantChangement = Suite.guide.actif and Suite.guide.actif.guide or "aucun"
    if Suite.guide.actif then Suite.guide.actif.guide = nil end
    if hub and hub.Oublier then pcall(hub.Oublier) end
    Suite.guide.envoye = nil
    pcall(Suite.ChoisirGuide)
end

-- ---------------------------------------------------------------------------
-- Lancer, calculer, arreter
-- ---------------------------------------------------------------------------

-- Les evenements du type guide invalident le calcul (un seul cadre).
local function EcouterEvenements(liste)
    local f = Suite.cadreEvenementsGuidage
    if not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            local S = _G.CoreSuite
            if S and S.Invalider then S.Invalider() end
        end)
        Suite.cadreEvenementsGuidage = f
    end
    if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
    for _, e in ipairs(type(liste) == "table" and liste or {}) do pcall(f.RegisterEvent, f, e) end
end

Finir = function(raison)
    local g = Suite.guide
    local inst = g.actif
    if not inst then return end
    local def = Def(inst)
    g.actif, g.calcul, g.arrivee, g.atteintDepuis = nil, nil, nil, nil
    -- Les dernieres fins de guidage (quoi, pourquoi, quand) : pour comprendre
    -- un arret inattendu.
    pcall(function()
        CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
        local h = type(CoreSuiteDB.finsDeGuidage) == "table" and CoreSuiteDB.finsDeGuidage or {}
        CoreSuiteDB.finsDeGuidage = h
        table.insert(h, { quoi = tostring(inst.proprietaire) .. ":" .. tostring(inst.type) .. " " .. tostring(inst.libelle or ""),
            raison = tostring(raison), quand = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "",
            origine = _G.debugstack and string.sub(tostring(_G.debugstack(3, 4, 0) or ""), 1, 400) or nil,
            niveau = _G.UnitLevel and _G.UnitLevel("player") or nil })
        while #h > 20 do table.remove(h, 1) end
    end)
    local cle = ClePersoGuidage()
    if cle and Persos()[cle] == inst then Persos()[cle] = nil end
    EcouterEvenements(nil)
    if Suite.choixGuide then Suite.choixGuide:Hide() end
    -- Le guidage s'arrete : l'add-on de trajet aussi, s'il suivait nos etapes.
    if g.envoye then
        g.envoye = nil
        local hub = _G.FriendsCoreAPI
        if hub and hub.Effacer then pcall(hub.Effacer) end
    end
    if g.cadreObjectifs then g.cadreObjectifs:Hide() end
    if def and def.Fin then pcall(def.Fin, inst.params, inst.etat, raison) end
    local M = _G.SagaCoreMessages
    if M and M.Dire and raison == "atteint" then
        pcall(M.Dire, "MapCore", "atteint", { quoi = inst.libelle or "" })
    elseif M and M.Dire and raison == "joueur" then
        pcall(M.Dire, "MapCore", "arret")
    end
end

-- « Suivante » : la cible visee est passee a la main (le type dit comment),
-- la suivante est calculee tout de suite.
function Suite.EtapeSuivante()
    local inst = Suite.guide.actif
    local def = inst and Def(inst)
    local calcul = Suite.guide.calcul
    local cible = type(calcul) == "table" and type(calcul.etapes) == "table" and calcul.etapes[1] or nil
    if not (def and def.Passer and cible) then return end
    pcall(def.Passer, inst.params, inst.etat, cible)
    Suite.guide.envoye = nil
    Suite.guide.arrivee = nil
    if Suite.Invalider then Suite.Invalider() end
end

-- Arreter le guidage : "joueur" (par defaut), "atteint" ou "remplace".
function Suite.Arreter(raison)
    if raison ~= "atteint" and raison ~= "remplace" then raison = "joueur" end
    Finir(raison)
end

-- Lance un objectif (il remplace celui en cours). `reprise` : l'objectif
-- garde, repris tel quel (memes parametres, meme memoire, meme guide).
function Suite.LancerObjectif(proprietaire, nom, params, reprise)
    local def = DefDe(proprietaire, nom)
    if not def then return false end
    local inst = reprise
    if not inst then
        params = type(params) == "table" and params or {}
        inst = { v = 1, proprietaire = proprietaire, type = nom, params = params,
            cle = Identite(proprietaire, nom, params), etat = {}, depuis = (_G.time and _G.time()) or 0 }
        if def.Preparer then
            local ok, pret, message = pcall(def.Preparer, inst.params, inst.etat)
            if not ok or pret == false then
                if ok and type(message) == "string" and message ~= "" then
                    print("|cffffd100" .. tostring(def.nomProprietaire or proprietaire) .. "|r " .. message)
                end
                return false
            end
        end
    end
    inst.params = type(inst.params) == "table" and inst.params or {}
    inst.etat = type(inst.etat) == "table" and inst.etat or {}
    if Suite.guide.actif then Finir("remplace") end
    if def.Libelle then
        local okL, lib = pcall(def.Libelle, inst.params, inst.etat)
        if okL and type(lib) == "string" then inst.libelle = lib end
    end
    local g = Suite.guide
    g.actif, g.calcul, g.arrivee, g.envoye = inst, nil, nil, nil
    if not def.nonPersiste then
        local cle = ClePersoGuidage()
        if cle then Persos()[cle] = inst end
    end
    -- Le guide choisi pour cet objectif (garde), sinon on redemandera.
    local hub = _G.FriendsCoreAPI
    if hub then
        if inst.guide and hub.Choisir then pcall(hub.Choisir, inst.guide)
        elseif hub.Oublier then pcall(hub.Oublier) end
    end
    EcouterEvenements(def.Evenements)
    local cadre = CadreObjectifs()
    if cadre.icone then cadre.icone:SetTexture(def.icone or "Interface\\Icons\\INV_Misc_Map_01") end
    cadre:Show()
    return true
end

-- Meme objectif deja guide : arret ; sinon il est lance.
function Suite.BasculerObjectif(proprietaire, nom, params)
    if Suite.EstActif(proprietaire, nom, params) then Suite.Arreter("joueur") return false end
    return Suite.LancerObjectif(proprietaire, nom, params)
end

-- Le prochain passage recalcule les etapes.
function Suite.Invalider()
    if Suite.guide.calcul then Suite.guide.calcul.quand = -100 end
end

-- Les etapes de l'objectif, recalculees au plus toutes les 4 secondes ou
-- des qu'elles sont invalidees.
Calculer = function()
    local g = Suite.guide
    local inst = g.actif
    local def = Def(inst)
    if not def then return nil end
    if g.enCalcul then return g.calcul end
    local maintenant = (_G.GetTime and _G.GetTime()) or 0
    if g.calcul and maintenant - g.calcul.quand < 4 and maintenant >= g.calcul.quand then return g.calcul end
    g.enCalcul = true
    local ok, etapes, raison, detail, compte = pcall(def.Etapes, inst.params, inst.etat)
    g.enCalcul = false
    if not ok then
        if Suite.Prive and Suite.Prive() then print("|cffffd100SagaCore|r " .. tostring(etapes)) end
        etapes, raison, detail, compte = nil, "loin", nil, nil
    end
    if g.actif ~= inst then return nil end
    -- « Atteint » doit se confirmer : un etat passager (journal en cours de
    -- relecture apres un niveau gagne, une quete rendue) ne coupe jamais un
    -- guidage. Le meme verdict, 3 secondes plus tard, termine l'objectif.
    if raison == "atteint" then
        if not g.atteintDepuis then
            g.atteintDepuis = maintenant
            if g.calcul then g.calcul.quand = maintenant - 1 return g.calcul end
            return nil
        end
        if maintenant - g.atteintDepuis < 3 then
            if g.calcul then g.calcul.quand = maintenant - 1 return g.calcul end
            return nil
        end
        g.atteintDepuis = nil
        Finir("atteint")
        return nil
    end
    g.atteintDepuis = nil
    if def.Libelle then
        local okL, lib = pcall(def.Libelle, inst.params, inst.etat)
        if okL and type(lib) == "string" then inst.libelle = lib end
    end
    if type(etapes) ~= "table" then etapes = nil end
    local n = etapes and #etapes or 0
    local fait = type(compte) == "table" and tonumber(compte.fait) or 0
    local total = type(compte) == "table" and tonumber(compte.total) or (fait + n)
    local premiere = n > 0 and etapes[1] or nil
    -- La destination change : la coche d'arrivee repart a zero.
    local cleCible = premiere and (premiere.cle or (tostring(premiere.carte) .. ":" .. tostring(premiere.x) .. ":" .. tostring(premiere.y)))
    if not g.calcul or g.calcul.cleCible ~= cleCible then g.arrivee = nil end
    g.calcul = { quand = maintenant, etapes = etapes, raison = raison, detail = detail,
        rang = math.max(1, math.min(fait + 1, math.max(total, 1))), total = math.max(total or 0, 0), cleCible = cleCible }
    return g.calcul
end

-- Ce que guide la suite : { objectif, etapes, rang, total, raison, detail },
-- ou nil.
function Suite.EtatGuidage()
    local inst = Suite.guide.actif
    if not inst then return nil end
    local c = Calculer() or {}
    if Suite.guide.actif ~= inst then return nil end
    return { objectif = inst, etapes = c.etapes, rang = c.rang, total = c.total, raison = c.raison, detail = c.detail }
end

-- ---------------------------------------------------------------------------
-- Compatibilite : les anciens fournisseurs (TradeCore, hors depot) deviennent
-- des objectifs "Suite:<cle>", non gardes d'une session a l'autre.
-- ---------------------------------------------------------------------------

function Suite.Guider(cle, fournisseur)
    if type(cle) ~= "string" or type(fournisseur) ~= "table" or type(fournisseur.Cible) ~= "function" then return end
    Suite.catalogues.Suite = Suite.catalogues.Suite or {}
    local ancien = Suite.catalogues.Suite[cle]
    local a = Suite.guide.actif
    -- La meme destination qui se met a jour : rien a relancer.
    if ancien and ancien.fournisseur == fournisseur and a and a.proprietaire == "Suite" and a.type == cle then
        Suite.Invalider()
        return
    end
    Suite.catalogues.Suite[cle] = {
        fournisseur = fournisseur, nonPersiste = true, nomProprietaire = cle,
        icone = fournisseur.icone, AideClic = fournisseur.AideClic,
        Libelle = function()
            local n = fournisseur.nom
            if type(n) == "function" then local ok, v = pcall(n) n = ok and v or nil end
            return type(n) == "string" and n or nil
        end,
        Etapes = function()
            local c, r, d = fournisseur.Cible()
            if not c then return nil, (r == "fini") and "atteint" or r, d end
            return { c }, nil, nil, (c.rang and c.total) and { fait = c.rang - 1, total = c.total } or nil
        end,
        Arrivee = function(_, _, e) if fournisseur.Arrivee then fournisseur.Arrivee(e) end return "suivante" end,
        Clic = fournisseur.Clic and function() fournisseur.Clic() end or nil,
        Fin = function() if fournisseur.Fin then fournisseur.Fin() end end,
    }
    Suite.LancerObjectif("Suite", cle, {})
end

function Suite.ArreterGuidage(cle)
    local a = Suite.guide.actif
    if a and (cle == nil or a.proprietaire == cle or a.type == cle) then Suite.Arreter("joueur") end
end

function Suite.GuidageActif(cle)
    local a = Suite.guide.actif
    return a ~= nil and (cle == nil or a.proprietaire == cle or a.type == cle)
end

-- Reprise apres /reload ou connexion : le meme objectif exactement, pour ce
-- personnage seulement. Une seconde apres l'entree dans le monde, quand tous
-- les add-ons ont declare leur catalogue.
if not Suite.cadreRepriseGuidage then
    local f = CreateFrame("Frame")
    Suite.cadreRepriseGuidage = f
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, evenement)
        if evenement ~= "PLAYER_ENTERING_WORLD" then return end
        if self.UnregisterAllEvents then pcall(self.UnregisterAllEvents, self) end
        local function Reprendre()
            local S = _G.CoreSuite
            if not (S and S.ReprendreObjectif) then return end
            pcall(S.ReprendreObjectif)
        end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(1, Reprendre) else Reprendre() end
    end)
end

function Suite.ReprendreObjectif()
    if Suite.guide.actif then return end
    local cle = ClePersoGuidage()
    local inst = cle and Persos()[cle]
    if type(inst) ~= "table" or inst.v ~= 1 then return end
    local def = Def(inst)
    -- Son add-on n'est pas charge : l'objectif reste garde, sans guider.
    if not def then return end
    if def.Reprendre then
        local ok, oui = pcall(def.Reprendre, inst.params or {}, inst.etat or {})
        if not ok or oui == false then Persos()[cle] = nil return end
    end
    Suite.LancerObjectif(inst.proprietaire, inst.type, inst.params, inst)
end

-- Une fois tous les add-ons charges : bouton de minicarte et barre.
if not Suite.cadreDemarrage then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        pcall(_G.CoreSuite.ConstruireMinicarte)
        pcall(_G.CoreSuite.ConstruireBarre)
        pcall(_G.CoreSuite.Actualiser)
        -- La faction n'est sure qu'une fois connecte : on repose les fonds.
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() pcall(_G.CoreSuite.AppliquerTheme) end)
        end
    end)
    Suite.cadreDemarrage = f
end

-- ---------------------------------------------------------------------------
-- Nouvelle version de la suite : chaque copie dit discretement son numero
-- (messages d'add-on, invisibles dans la discussion) au groupe, au raid et a
-- la guilde. Une copie qui voit un numero plus recent previent son joueur,
-- chez lui seulement, une fois par session. Jamais rien d'ecrit dans un canal.
-- Le numero vient des fichiers publies (ligne X-SagaCore-Version ajoutee a la
-- publication) : une copie sans numero ecoute sans rien annoncer.
-- ---------------------------------------------------------------------------
if not Suite.cadreVersion then
    local PREFIXE = "SagaCoreVer"
    local f = CreateFrame("Frame")
    Suite.cadreVersion = f
    local function Meta(nom, champ)
        local A = _G.C_AddOns
        local lire = (A and A.GetAddOnMetadata) or _G.GetAddOnMetadata
        if not lire then return nil end
        local ok, v = pcall(lire, nom, champ)
        return ok and type(v) == "string" and v ~= "" and v or nil
    end
    local function MaVersion()
        for _, nom in ipairs(Suite.ADDONS_SUITE or {}) do
            local v = Meta(nom, "X-SagaCore-Version")
            if v then return v end
        end
        return nil
    end
    -- Vrai si a est plus recent que b ("1.10.0" apres "1.9.2").
    local function PlusRecente(a, b)
        local ta, tb = {}, {}
        for n in tostring(a):gmatch("%d+") do table.insert(ta, tonumber(n)) end
        for n in tostring(b):gmatch("%d+") do table.insert(tb, tonumber(n)) end
        for i = 1, math.max(#ta, #tb) do
            local x, y = ta[i] or 0, tb[i] or 0
            if x ~= y then return x > y end
        end
        return false
    end
    local prevenu = false
    local derniers = {}
    local function Envoyer(canal, cible)
        local v = MaVersion()
        local C = _G.C_ChatInfo
        if not (v and C and C.SendAddonMessage) then return end
        local cle = canal .. (cible or "")
        local maintenant = (_G.GetTime and _G.GetTime()) or 0
        if derniers[cle] and maintenant - derniers[cle] < 300 then return end
        derniers[cle] = maintenant
        pcall(C.SendAddonMessage, PREFIXE, v, canal, cible)
    end
    local function Annoncer()
        if _G.IsInGuild and _G.IsInGuild() then Envoyer("GUILD") end
        if _G.IsInRaid and _G.IsInRaid() then Envoyer("RAID")
        elseif _G.IsInGroup and _G.IsInGroup() then Envoyer("PARTY") end
    end
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, ev, prefixe, message, canal, auteur)
        if ev == "PLAYER_LOGIN" then
            local C = _G.C_ChatInfo
            if C and C.RegisterAddonMessagePrefix then pcall(C.RegisterAddonMessagePrefix, PREFIXE) end
            if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(20, Annoncer) end
        elseif ev == "GROUP_ROSTER_UPDATE" then
            Annoncer()
        elseif ev == "CHAT_MSG_ADDON" and prefixe == PREFIXE and type(message) == "string" then
            local mienne = MaVersion()
            if not mienne then return end
            if PlusRecente(message, mienne) then
                if prevenu then return end
                prevenu = true
                local fr = Suite.Langue and Suite.Langue() == "frFR"
                local texte = string.format(fr and "une nouvelle version (%s) est disponible sur CurseForge."
                    or "a new version (%s) is available on CurseForge.", message)
                if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Forever SagaCore|r : " .. texte) end
            elseif PlusRecente(mienne, message) and type(auteur) == "string" and auteur ~= "" then
                -- Il a une version plus ancienne : on lui dit la notre, en prive.
                Envoyer("WHISPER", auteur)
            end
        end
    end)
end


-- ---------------------------------------------------------------------------
-- Prendre la main sur une fenetre de suivi a la manette (macros « Piloter
-- mes fabrications » et « Piloter le suivi des quetes »), hors combat. La
-- manette ne pilote plus que cette fenetre, comme un panneau du jeu :
--   croix              se deplacer (haut, bas, gauche, droite, d'apres l'ecran)
--   LB / RB            onglet precedent / suivant
--   A                  valider (clic) ; X : clic droit ; Y : arreter le guidage
--   Vue (deux carres)  montrer ou cacher la barre des commandes
--   B                  liberer : la manette revient au jeu
-- ---------------------------------------------------------------------------

local function TR(fr, en) return Suite.Langue() == "frFR" and fr or en end
local SUIVIS = { "CraftCoreSuivi", "QuestCoreSuivi", "TradeCoreSuivi" }
local OUVRIR_SUIVI = {
    CraftCoreSuivi = function() local a = _G.CraftCoreAPI if a and a.BasculerSuivi then pcall(a.BasculerSuivi) end end,
    QuestCoreSuivi = function() local a = _G.QuestCoreAPI if a and a.BasculerSuivi then pcall(a.BasculerSuivi) end end,
}

local function Cliquables(cadre, liste)
    if not cadre or not cadre.IsVisible or not cadre:IsVisible() then return liste end
    for _, enfant in ipairs({ cadre:GetChildren() }) do
        if enfant:IsVisible() then
            local clic = enfant.GetScript and (enfant:GetScript("OnClick") or enfant:GetScript("OnMouseUp") or enfant:GetScript("OnMouseDown"))
            local actif = not (enfant.IsEnabled and not enfant:IsEnabled()) or enfant:GetScript("OnEnter") ~= nil
            if clic and actif and enfant:GetObjectType() ~= "ScrollFrame" and (enfant:GetWidth() or 0) > 4 then
                table.insert(liste, enfant)
            end
            Cliquables(enfant, liste)
        end
    end
    return liste
end

local function Elements(nom)
    local liste = Cliquables(_G[nom], {})
    -- Boutons poses hors de la fenetre mais qui en font partie (MacroCore).
    local f = _G[nom]
    if f and f.elementsPilote then
        for _, e in ipairs(f.elementsPilote()) do if e:IsVisible() then table.insert(liste, e) end end
    end
    table.sort(liste, function(a, b)
        local ya, yb = a:GetTop() or 0, b:GetTop() or 0
        if math.abs(ya - yb) > 3 then return ya > yb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    return liste
end

-- Les onglets d'un suivi : marques par la fenetre elle-meme, ongletPilote =
-- 1 pour les onglets principaux (LB / RB), 2 pour les sous-onglets (LT / RT).
local function Onglets(liste, niveau)
    local t = {}
    for _, e in ipairs(liste) do
        local n = e.ongletPilote == true and 1 or e.ongletPilote
        if n == niveau then table.insert(t, e) end
    end
    return t
end

local function Boite(e)
    local g, h, l, ht = e:GetLeft(), e:GetTop(), e:GetWidth(), e:GetHeight()
    if not (g and h and l and ht) then return nil end
    return { x = g + l / 2, y = h - ht / 2, h = ht }
end

local function Pilote()
    local p = Suite.pilote
    if p then return p end
    p = CreateFrame("Frame", "CoreSuitePilote", UIParent)
    p:SetAllPoints(UIParent)
    p:SetFrameStrata("TOOLTIP")
    p:EnableMouse(false)
    local okB, avecBord = pcall(CreateFrame, "Frame", nil, p, "BackdropTemplate")
    p.cadre = okB and avecBord or CreateFrame("Frame", nil, p)
    p.cadre:SetFrameStrata("TOOLTIP")
    if p.cadre.SetBackdrop then
        p.cadre:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
        p.cadre:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    -- La barre des commandes, comme sous les fenetres du jeu.
    local okBarre, barre = pcall(CreateFrame, "Frame", nil, p, "TooltipBackdropTemplate")
    p.barre = okBarre and barre or CreateFrame("Frame", nil, p)
    p.barre:SetFrameStrata("TOOLTIP")
    p.barre:SetHeight(34)
    p.barre.texte = p.barre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.barre.texte:SetPoint("LEFT", p.barre, "LEFT", 12, 0)
    p.barreVisible = true

    function p.Liste() return Elements(p.nom) end
    -- L'element choisi ; s'il a disparu (le suivi s'est redessine), le plus
    -- proche de sa derniere place.
    function p.Courant()
        local liste = p.Liste()
        for _, e in ipairs(liste) do if e == p.choix then return e, liste end end
        local meilleur, dMin
        for _, e in ipairs(liste) do
            local bx = Boite(e)
            if bx and p.pos and not e.ongletPilote and not e.pasPilote then
                local d = (bx.x - p.pos.x) ^ 2 + (bx.y - p.pos.y) ^ 2
                if not dMin or d < dMin then meilleur, dMin = e, d end
            end
        end
        if not meilleur then
            for _, e in ipairs(liste) do if not e.ongletPilote and not e.pasPilote then meilleur = e break end end
        end
        p.choix = meilleur or liste[1]
        return p.choix, liste
    end
    -- L'element choisi est montre comme au survol de la souris (sa propre
    -- surbrillance, son infobulle), sans cadre ajoute, comme dans les menus de
    -- la suite. La fenetre reste en pleine couleur tant qu'on la pilote.
    -- L'element choisi clignote doucement (sa propre surbrillance), pour bien
    -- le voir.
    local function Clignoter(e, oui)
        local h = e.GetHighlightTexture and e:GetHighlightTexture()
        if not (h and h.CreateAnimationGroup) then return end
        if oui then
            if not h.suiteClignote then
                local g = h:CreateAnimationGroup()
                g:SetLooping("BOUNCE")
                local a = g:CreateAnimation("Alpha")
                a:SetFromAlpha(1)
                a:SetToAlpha(0.15)
                a:SetDuration(0.45)
                h.suiteClignote = g
            end
            h.suiteClignote:Play()
        elseif h.suiteClignote then
            h.suiteClignote:Stop()
        end
    end
    function p.Eteindre()
        local e = p.eclaire
        p.eclaire = nil
        if not e then return end
        pcall(Clignoter, e, false)
        if e.UnlockHighlight then pcall(e.UnlockHighlight, e) end
        local quitte = e.GetScript and e:GetScript("OnLeave")
        if quitte then pcall(quitte, e) end
    end
    function p.Marquer()
        p.cadre:Hide()
        local e = p.Courant()
        if e ~= p.eclaire then p.Eteindre() end
        if not e then return end
        p.pos = Boite(e) or p.pos
        p.eclaire = e
        if e.LockHighlight then pcall(e.LockHighlight, e) end
        pcall(Clignoter, e, true)
        local survol = e:GetScript("OnEnter")
        if survol then pcall(survol, e) end
    end
    function p.Deplacer(dx, dy)
        local depart, liste = p.Courant()
        local d = depart and Boite(depart)
        if not d then return end
        local meilleur, scoreMin
        -- Les onglets ont aussi leur navigation (LB / RB, LT / RT). La croix
        -- y va quand rien d'autre n'est dans cette direction (en haut de la
        -- liste), et passe d'un onglet a l'autre quand on y est.
        local function Chercher(avecOnglets)
            for _, e in ipairs(liste) do
                local b = e ~= depart and (avecOnglets or not e.ongletPilote) and not e.pasPilote and Boite(e)
                if b then
                    local score
                    if dy ~= 0 then
                        local avance = (dy > 0) and (d.y - b.y) or (b.y - d.y)
                        if avance > 4 then score = avance * 4 + math.abs(b.x - d.x) * 0.5 end
                    else
                        local memeLigne = math.abs(b.y - d.y) < math.max(d.h, b.h) / 2 + 2
                        local avance = (dx > 0) and (b.x - d.x) or (d.x - b.x)
                        if memeLigne and avance > 2 then score = avance end
                    end
                    if score and (not scoreMin or score < scoreMin) then meilleur, scoreMin = e, score end
                end
            end
        end
        Chercher(depart.ongletPilote and dx ~= 0)
        if not meilleur then Chercher(true) end
        if meilleur then p.choix = meilleur end
    end
    function p.Onglet(pas, niveau)
        local onglets = Onglets(p.Liste(), niveau or 1)
        if #onglets == 0 then return end
        local rang = 1
        for i, o in ipairs(onglets) do
            if o.choisi or (o.GetChecked and o:GetChecked()) then rang = i end
        end
        local cible = onglets[((rang - 1 + pas) % #onglets) + 1]
        if cible and cible.Click then pcall(cible.Click, cible, "LeftButton") end
        p.choix, p.pos = nil, nil
    end
    -- Une glyphe de touche posee contre un onglet.
    p.glyphes = {}
    local function Glyphe(k, touche)
        local g = p.glyphes[k]
        if not g then
            g = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            p.glyphes[k] = g
        end
        g:SetText(GlyphePad(touche))
        g:ClearAllPoints()
        g:Show()
        return g
    end
    -- La croix entiere (une seule icone), sinon la fleche du haut.
    local function Croix()
        local info = C_Texture and C_Texture.GetAtlasInfo
        for _, nom in ipairs({ "Gamepad_Gen_DPad_64", "Gamepad_Gen_Dpad_64", "Gamepad_Ltr_DPad_64", "Gamepad_Shp_DPad_64" }) do
            local ok, existe = pcall(info or function() end, nom)
            if ok and existe then return "|A:" .. nom .. ":20:20|a" end
        end
        return GlyphePad("PADDUP")
    end
    -- Les commandes : au-dessus de la fenetre, a gauche, seulement Se deplacer,
    -- Valider et Liberer. LB / RB contre les onglets du cote (au-dessus du
    -- premier, sous le dernier), LT / RT sur la ligne des sous-onglets.
    function p.Barre()
        for _, g in pairs(p.glyphes) do g:Hide() end
        local f = _G[p.nom]
        if not (p.barreVisible and f) then p.barre:Hide() return end
        local esp = "      "
        p.barre.texte:SetText(Croix() .. "  " .. TR("Se déplacer", "Move") .. esp
            .. GlyphePad("PAD1") .. "  " .. TR("Valider", "Select") .. esp
            .. GlyphePad("PAD2") .. "  " .. TR("Libérer", "Release"))
        -- De la largeur de la fenetre pilotee, posee juste au-dessus.
        -- Exactement la largeur du cadre visible de la fenetre (le bord
        -- dessine du jeu commence un peu apres le bord gauche du cadre).
        p.barre:ClearAllPoints()
        p.barre:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 3.5, 4)
        p.barre:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
        if p.barre.SetClampedToScreen then p.barre:SetClampedToScreen(true) end
        p.barre:Show()
        local liste = p.Liste()
        local un = Onglets(liste, 1)
        if #un > 1 then
            local premier, dernier = un[1], un[#un]
            local vertical = math.abs((premier:GetLeft() or 0) - (dernier:GetLeft() or 0)) < 8
            if vertical then
                Glyphe("lb", "PADLSHOULDER"):SetPoint("BOTTOM", premier, "TOP", 0, 2)
                Glyphe("rb", "PADRSHOULDER"):SetPoint("TOP", dernier, "BOTTOM", 0, -2)
            end
        end
        local deux = Onglets(liste, 2)
        if #deux > 1 then
            table.sort(deux, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
            -- LT et RT cote a cote, dans la fenetre, au bout de la ligne des
            -- sous-onglets.
            local _, yOnglet = deux[#deux]:GetCenter()
            local haut = f:GetTop()
            if yOnglet and haut then
                local g = Glyphe("lt", "PADLTRIGGER")
                g:SetText(GlyphePad("PADLTRIGGER") .. " " .. GlyphePad("PADRTRIGGER"))
                g:SetPoint("RIGHT", f, "TOPRIGHT", -10, yOnglet - haut)
            end
        end
    end
    p:SetScript("OnGamePadButtonDown", function(self, bouton)
        local e = p.Courant()
        if bouton == "PADDDOWN" then p.Deplacer(0, 1)
        elseif bouton == "PADDUP" then p.Deplacer(0, -1)
        elseif bouton == "PADDLEFT" then p.Deplacer(-1, 0)
        elseif bouton == "PADDRIGHT" then p.Deplacer(1, 0)
        elseif bouton == "PADLSHOULDER" then p.Onglet(-1)
        elseif bouton == "PADRSHOULDER" then p.Onglet(1)
        elseif bouton == "PADLTRIGGER" then p.Onglet(-1, 2)
        elseif bouton == "PADRTRIGGER" then p.Onglet(1, 2)
        elseif bouton == "PAD1" or bouton == "PAD3" then
            local cote = bouton == "PAD1" and "LeftButton" or "RightButton"
            if e then
                -- Pastille de MacroCore : on lance le raccourci directement.
                local r = e.e and e.e.cle and Suite.Raccourci(e.e.cle)
                if r then
                    if p.nom == "CoreSuiteMacroCore" and Suite.LancerDepuisMacroCore then Suite.LancerDepuisMacroCore(r)
                    else Suite.Lancer(r) end
                elseif e.Click and e:GetScript("OnClick") then pcall(e.Click, e, cote)
                else
                    local f = e:GetScript("OnMouseUp") or e:GetScript("OnMouseDown")
                    if f then pcall(f, e, cote) end
                end
            end
        -- Y n'arrete plus le guidage : une touche cachee ne coupe jamais ce
        -- que le joueur a lance (le guidage a son bouton Arreter).
        elseif bouton == "PADBACK" then p.barreVisible = not p.barreVisible
        elseif bouton == "PAD2" then
            local f = _G[p.nom]
            if f and f.piloteSurB then f.piloteSurB() return end
            if f and f.piloteFermerSurB then f:Hide() end
            Suite.Piloter(false)
            return
        end
        -- Le suivi se redessine souvent apres un clic : on remarque un peu apres.
        p.Marquer()
        p.Barre()
        if C_Timer and C_Timer.After then C_Timer.After(0.15, function() if p:IsShown() then p.Marquer() p.Barre() end end) end
    end)
    -- Le suivi ferme : on libere. (Plus de remise a pleine opacite a chaque
    -- image : elle se battait avec le fondu du suivi et le faisait clignoter.)
    local attente = 0
    p:SetScript("OnUpdate", function(_, ecoule)
        attente = attente + (ecoule or 0)
        if attente < 0.25 then return end
        attente = 0
        local f = _G[p.nom]
        if not (f and f:IsShown()) then Suite.Piloter(false) end
    end)
    p:RegisterEvent("PLAYER_REGEN_DISABLED")
    p:SetScript("OnEvent", function() Suite.Piloter(false) end)
    p:Hide()
    Suite.pilote = p
    return p
end

local TP = Paresseux({
    combat = "Not in combat.",
    rien = "This tracker is not open.",
})

-- Touche du jeu (Echap, Options, Raccourcis, Add-ons) : piloter un suivi.
-- Entrer dans une petite fenetre de la suite a la manette (courrier, banque,
-- hotel des ventes, consigne, nouveau plan), sans rien regler : tant qu'elle
-- est ouverte, un appui sur le double carre (bouton Vue) y entre ; on y
-- navigue ensuite comme dans les autres fenetres (croix, A, B pour sortir).
-- Aucune touche n'est posee (plus de SetOverrideBinding : il faisait bloquer
-- une action du jeu au courrier) et aucune entree n'est prise au jeu : la
-- manette est seulement LUE (etat des boutons), quelques fois par seconde,
-- jamais en combat. Le jeu garde toutes ses touches.
local function IndexDuBouton(nomBouton)
    local gp = _G.C_GamePad
    if not (gp and gp.ButtonIndexToConfigName) then return nil end
    for i = 0, 40 do
        local ok, n = pcall(gp.ButtonIndexToConfigName, i)
        if ok and n == nomBouton then
            -- Indices du jeu a partir de 0, tableau Lua a partir de 1.
            local okZ, z = pcall(gp.ButtonIndexToConfigName, 0)
            return (okZ and z ~= nil) and (i + 1) or i
        end
    end
    return nil
end
local function BoutonAppuye(index)
    local gp = _G.C_GamePad
    if not (index and gp and gp.GetDeviceMappedState) then return false end
    local okI, id = pcall(gp.GetActiveDeviceID or function() return nil end)
    local okS, etat = pcall(gp.GetDeviceMappedState, okI and id or nil)
    if not (okS and type(etat) == "table" and type(etat.buttons) == "table") then return false end
    return etat.buttons[index] == true
end
local function ManetteActive()
    local gp = _G.C_GamePad
    local ok, actif = pcall(gp and gp.IsEnabled or function() return false end)
    return ok and actif and true or false
end

function Suite.ToucheDEntree(f, nom)
    if not f or f.toucheDEntree then return end
    f.toucheDEntree = true
    f.nomDEntree = nom or (f.GetName and f:GetName())
    -- Comme le jeu : l'icone du double carre a cheval sur le bas de la
    -- fenetre, au milieu (visible meme quand la liste defile).
    if not f.badgeEntree then
        local b = CreateFrame("Frame", nil, f)
        b:SetSize(30, 30)
        b:SetPoint("CENTER", f, "BOTTOM", 0, 4)
        -- Au-dessus du cadre de la fenetre (son bord est un cadre enfant).
        b:SetFrameLevel((f:GetFrameLevel() or 1) + 500)
        -- Une pastille sombre sous l'icone : elle se detache du bord.
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetSize(30, 30)
        b.fond:SetPoint("CENTER")
        b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        b.fond:SetVertexColor(0, 0, 0, 0.9)
        b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.texte:SetPoint("CENTER", 0, 0)
        b:Hide()
        f.badgeEntree = b
    end
    local function Badge(self)
        if ManetteActive() then
            self.badgeEntree.texte:SetText((string.gsub(GlyphePad("PADBACK"), ":20:20|a", ":26:26|a")))
            self.badgeEntree:Show()
        else
            self.badgeEntree:Hide()
        end
    end
    f:HookScript("OnShow", Badge)
    if f:IsShown() then Badge(f) end
    -- La lecture du double carre : un appui (pas la touche tenue) entre.
    local veille = CreateFrame("Frame", nil, f)
    local attente, avant, index = 0, true, nil
    veille:SetScript("OnUpdate", function(_, ecoule)
        attente = attente + (ecoule or 0)
        if attente < 0.05 then return end
        attente = 0
        if not f:IsShown() or not ManetteActive() then avant = true return end
        if InCombatLockdown and InCombatLockdown() then avant = true return end
        local p = Suite.pilote
        if p and p:IsShown() then avant = true return end
        index = index or IndexDuBouton("PADBACK")
        local appuye = BoutonAppuye(index)
        if appuye and not avant then
            local n = (f.GetName and f:GetName()) or f.nomDEntree
            if n and _G[n] then pcall(Suite.Piloter, nil, n) end
        end
        avant = appuye
    end)
end

function CoreSuite_PiloterSuivi(nom)
    local S = _G.CoreSuite
    if S and S.Piloter then S.Piloter(nil, nom) end
end

function Suite.Piloter(oui, nom)
    local p = Pilote()
    if oui == nil then oui = not (p:IsShown() and (not nom or p.nom == nom)) end
    if not oui then
        pcall(p.EnableGamePadButton, p, false)
        if p.Eteindre then p.Eteindre() end
        if p:IsShown() then
            local f = p.nom and _G[p.nom]
            if f and p.alphaAvant then f:SetAlpha(p.alphaAvant) end
        end
        -- La fenetre retrouve son opacite normale.
        local fl = p.figee
        p.figee = nil
        if fl then
            fl.SetAlpha = nil
            if p.alphaAvant then fl:SetAlpha(p.alphaAvant) end
        end
        p.alphaAvant = nil
        p:Hide()
        GameTooltip:Hide()
        -- Remis dans l'etat d'avant : ferme s'il l'etait.
        local aFermer = p.refermer and _G[p.refermer]
        p.refermer = nil
        if aFermer and aFermer:IsShown() then aFermer:Hide() end
        if Suite.ReprendrePanneau then Suite.ReprendrePanneau() end
        -- La fenetre des macros reprend la main si elle est encore ouverte.
        local retour = p.retour
        p.retour = nil
        local fr = retour and _G[retour]
        if fr and fr:IsShown() and retour ~= p.nom and not (fr.piloteGarderAlpha and (not fr.active or fr.figee)) then
            Suite.Piloter(true, retour)
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then print("|cffffd100SagaCore|r " .. TP.combat) return end
    -- Depuis la fenetre des macros : elle reste ouverte, et reprendra la main.
    local retour = (p:IsShown() and (p.nom == "CoreSuiteMacros" or p.nom == "CoreSuiteMacroCore") and nom ~= p.nom) and p.nom or nil
    if p:IsShown() then p.retour = nil Suite.Piloter(false) end
    -- Sans nom : d'abord une petite fenetre de la suite ouverte (question,
    -- consigne, panneau de la banque, du courrier ou de l'hotel des ventes),
    -- puis le premier suivi ouvert. La meme touche entre partout.
    if not nom then
        for _, n in ipairs({ "CraftCoreProjetCommercial", "CraftCoreNouveauPlan", "CraftCoreConsigne", "CraftCoreAssistant" }) do
            if _G[n] and _G[n]:IsShown() then nom = n break end
        end
    end
    if not nom then
        for _, n in ipairs(SUIVIS) do if _G[n] and _G[n]:IsShown() then nom = n break end end
        nom = nom or SUIVIS[1]
    end
    local f = _G[nom]
    -- Ferme avant d'en prendre le controle : il se referme quand on le libere.
    local ouvertIci = false
    if not (f and f:IsShown()) and OUVRIR_SUIVI[nom] then OUVRIR_SUIVI[nom]() f = _G[nom] ouvertIci = true end
    if not (f and f:IsShown()) then print("|cffffd100SagaCore|r " .. TP.rien) return end
    p.nom, p.choix, p.pos = nom, nil, nil
    p.retour = retour
    p.refermer = ouvertIci and f and f:IsShown() and nom or nil
    if f.piloteDepart then p.choix = f.piloteDepart() end
    if f.piloteGarderAlpha then
        if Suite.SuspendrePanneau then Suite.SuspendrePanneau() end
        p:Show()
        pcall(p.EnableGamePadButton, p, true)
        p.Marquer()
        p.Barre()
        return
    end
    p.alphaAvant = f:GetAlpha()
    f:SetAlpha(1)
    -- Pleine couleur tant qu'on la pilote : son propre fondu (survol,
    -- deplacement) ne la touche plus jusqu'a ce qu'on libere.
    f.SetAlpha = nil
    local original = f.SetAlpha
    if type(original) == "function" then
        f.SetAlpha = function(self) original(self, 1) end
        p.figee = f
    end
    if Suite.SuspendrePanneau then Suite.SuspendrePanneau() end
    p:Show()
    pcall(p.EnableGamePadButton, p, true)
    p.Marquer()
    p.Barre()
end


-- ---------------------------------------------------------------------------
-- Raccourcis et macros
-- ---------------------------------------------------------------------------
-- Chaque raccourci est une commande /sagacore <cle>. La fenetre Macros les
-- montre tous et cree les macros du jeu qui les lancent (a poser ou l'on veut).
-- Un petit bouton rond, deplacable, ouvre le panneau des raccourcis : un clic
-- (ou A) lance l'action, sans macro.

local function TR(fr, en) return Suite.Langue() == "frFR" and fr or en end

local function Api(nom, fonction, ...)
    local api = _G[nom]
    if type(api) == "table" and type(api[fonction]) == "function" then return pcall(api[fonction], ...) end
    return false
end
local function Messages(fonction, ...)
    local M = _G.SagaCoreMessages
    if M and M[fonction] then return pcall(M[fonction], ...) end
end

Suite.RACCOURCIS = {
    { cle = "pilotefab", desc = "Prend le contrôle à la manette du suivi Mes fabrications, en l'ouvrant s'il est fermé. La croix se déplace, A valide, B rend la main.", descEn = "Takes gamepad control of the My crafts tracker, opening it if needed. D-pad moves, A confirms, B releases.",
      fr = "Piloter mes fabrications", en = "Drive my crafts", icone = "Trade_BlackSmithing",
      action = function() Suite.Piloter(nil, "CraftCoreSuivi") end, dispo = function() return _G.CraftCoreAPI ~= nil end },
    { cle = "pilotequetes", desc = "Prend le contrôle à la manette du suivi des quêtes, en l'ouvrant s'il est fermé. La croix se déplace, A valide, B rend la main.", descEn = "Takes gamepad control of the quest tracker, opening it if needed. D-pad moves, A confirms, B releases.",
      fr = "Piloter les quêtes", en = "Drive the quests", icone = "INV_Letter_15",
      action = function() Suite.Piloter(nil, "QuestCoreSuivi") end, dispo = function() return _G.QuestCoreAPI ~= nil end },
    { cle = "ouvrir", desc = "Ouvre ou ferme la dernière fenêtre de la suite que tu as utilisée.", descEn = "Opens or closes the last suite window you used.",
      fr = "Ouvrir la suite", en = "Open the suite", icone = "INV_Misc_Book_11",
      action = function()
          local premier
          for _, info in ipairs(Suite.Liste()) do if Suite.Installe(info.cle) then premier = info.cle break end end
          Suite.BasculerDernier(premier)
      end },
    { cle = "fabrications", desc = "Affiche ou cache le suivi Mes fabrications.", descEn = "Shows or hides the My crafts tracker.",
      fr = "Suivi des fabrications", en = "Crafting tracker", icone = "Trade_BlackSmithing",
      action = function() Api("CraftCoreAPI", "BasculerSuivi") end, dispo = function() return _G.CraftCoreAPI ~= nil end },
    { cle = "quetes", desc = "Affiche ou cache le suivi des quêtes.", descEn = "Shows or hides the quest tracker.",
      fr = "Suivi des quêtes", en = "Quest tracker", icone = "INV_Letter_15",
      action = function() Api("QuestCoreAPI", "BasculerSuivi") end, dispo = function() return _G.QuestCoreAPI ~= nil end },
    { cle = "stop", desc = "Arrête le guidage en cours.", descEn = "Stops the current guidance.",
      fr = "Arrêter le guidage", en = "Stop guidance", icone = "Spell_Holy_Silence",
      action = function() Suite.Arreter("joueur") end },
    { cle = "rendus", desc = "Te guide vers les personnages où rendre tes quêtes terminées.", descEn = "Guides you to where your completed quests are turned in.",
      fr = "Guider les quêtes à rendre", en = "Guide quest turn-ins", icone = "INV_Misc_Note_02",
      action = function() Api("QuestCoreAPI", "GuiderRendus") end, dispo = function() return _G.QuestCoreAPI ~= nil end },
    { cle = "recolte", desc = "Te guide vers les points de récolte des ressources qui manquent à tes fabrications.", descEn = "Guides you to gathering spots for the resources your crafts still need.",
      fr = "Guider la récolte", en = "Guide gathering", icone = "INV_Misc_Herb_01",
      action = function() Api("CraftCoreAPI", "GuiderRecolte") end, dispo = function() return _G.CraftCoreAPI ~= nil end },
    { cle = "metier", desc = "Ouvre la page Monter un métier de CraftCore.", descEn = "Opens the CraftCore Level a profession page.",
      fr = "Monter un métier", en = "Level a profession", icone = "INV_Misc_Book_09",
      action = function() Api("CraftCoreAPI", "MonterUnMetier") end, dispo = function() return _G.CraftCoreAPI ~= nil end },
    { cle = "oui", desc = "Répond oui à la dernière question que la suite t'a posée dans la discussion.", descEn = "Answers yes to the last question the suite asked you in chat.",
      fr = "Répondre oui", en = "Answer yes", icone = "Spell_ChargePositive",
      action = function() Messages("Repondre", true) end, dispo = function() return _G.SagaCoreMessages ~= nil end },
    { cle = "non", desc = "Répond non à la dernière question que la suite t'a posée dans la discussion.", descEn = "Answers no to the last question the suite asked you in chat.",
      fr = "Répondre non", en = "Answer no", icone = "Spell_ChargeNegative",
      action = function() Messages("Repondre", false) end, dispo = function() return _G.SagaCoreMessages ~= nil end },
    { cle = "messages", desc = "Ouvre les réglages des messages que la suite écrit dans la discussion.", descEn = "Opens the settings for the messages the suite writes in chat.",
      fr = "Messages dans la discussion", en = "Chat messages", icone = "INV_Letter_02",
      action = function() Messages("OuvrirReglages") end, dispo = function() return _G.SagaCoreMessages ~= nil end },
    { cle = "reglages", desc = "Ouvre les réglages communs à toute la suite.", descEn = "Opens the settings shared by the whole suite.",
      fr = "Réglages de la suite", en = "Suite settings", icone = "Trade_Engineering",
      action = function() Suite.OuvrirReglagesGeneraux() end },
    { cle = "improve", desc = "Ouvre les réglages d'AuraCore.", descEn = "Opens the AuraCore settings.",
      fr = "Réglages AuraCore", en = "AuraCore settings", icone = "Spell_Holy_AuraOfLight",
      action = function() if SlashCmdList.AURACORE then SlashCmdList.AURACORE("") end end,
      dispo = function() return SlashCmdList.AURACORE ~= nil end },
    { cle = "buffs", desc = "Demande au groupe, en un seul message, les buffs qui manquent et qui peut les donner. Hors combat seulement ; rien n'est envoyé s'il ne manque rien.", descEn = "Asks your group, in a single message, for the missing buffs and who can give them. Out of combat only ; nothing is sent when nothing is missing.",
      fr = "Demander les buffs", en = "Ask for buffs", icone = "INV_Misc_Horn_01", famille = "repondre",
      action = function() if _G.AuraCore_DemanderBuffs then _G.AuraCore_DemanderBuffs() end end,
      dispo = function() return _G.AuraCore_DemanderBuffs ~= nil end },
    { cle = "raccourcis", fr = "Panneau des raccourcis", en = "Shortcut panel", icone = "INV_Misc_Book_11",
      action = function() Suite.BasculerRaccourcis() end },
}

-- Les familles de raccourcis : une ligne chacune dans le panneau, un groupe
-- dans la page des macros. Un nouveau raccourci prend sa famille ici.
Suite.FAMILLES = {
    { cle = "manette", fr = "Prendre le contrôle d'une fenêtre", en = "Take control of a window" },
    { cle = "ouvrir", fr = "Ouvrir une fenêtre", en = "Open a window" },
    { cle = "guider", fr = "Guider", en = "Guide" },
    { cle = "repondre", fr = "Répondre aux messages", en = "Answer messages" },
    { cle = "perso", fr = "Mes macros", en = "My macros" },
}
local FAMILLE_DE = {
    pilotefab = "manette", pilotequetes = "manette",
    ouvrir = "ouvrir", craftcore = "ouvrir", questcore = "ouvrir", mapcore = "ouvrir", legacycore = "ouvrir",
    fabrications = "ouvrir", quetes = "ouvrir", metier = "ouvrir", reglages = "ouvrir", improve = "ouvrir",
    messages = "ouvrir", raccourcis = "ouvrir",
    rendus = "guider", recolte = "guider", stop = "guider",
    oui = "repondre", non = "repondre",
}
-- Un raccourci par add-on de la suite, tire de sa liste (Suite.ORDRE) :
-- un add-on ajoute a la suite a son raccourci partout, sans rien oublier.
do
    local rang = 1
    for k2, r in ipairs(Suite.RACCOURCIS) do if r.cle == "ouvrir" then rang = k2 + 1 end end
    for _, info in ipairs(Suite.ORDRE) do
        local nom = info.cle
        local cle = string.lower(nom)
        local montre = info.nom or nom
        local deja = false
        for _, r in ipairs(Suite.RACCOURCIS) do if r.cle == cle then deja = true end end
        if not deja then
            table.insert(Suite.RACCOURCIS, rang, {
                cle = cle, fr = montre, en = montre,
                desc = "Ouvre ou ferme la fenêtre principale de " .. montre .. ".",
                descEn = "Opens or closes the " .. montre .. " main window.",
                icone = (string.gsub(info.icone or "INV_Misc_QuestionMark", "^[Ii]nterface\\[Ii]cons\\", "")),
                action = function() Suite.Ouvrir(nom) end,
                dispo = function() return Suite.Installe(nom) end,
            })
            rang = rang + 1
        end
    end
end

function Suite.FamilleDe(r) return r.famille or FAMILLE_DE[r.cle] or "ouvrir" end

function Suite.Raccourci(cle)
    if not cle then return nil end
    cle = cle:lower()
    for _, r in ipairs(Suite.RACCOURCIS) do if r.cle == cle then return r end end
    return nil
end

function Suite.NomRaccourci(r) return TR(r.fr, r.en) end

local function Dispo(r) return not r.dispo or r.dispo() end

function Suite.Lancer(r)
    if not Dispo(r) then return end
    local ok, souci = pcall(r.action)
    if not ok and Suite.Prive() then print("|cffffd100SagaCore|r " .. tostring(souci)) end
end

-- Les macros du jeu, communes au compte : un nom de 3 lettres au plus (il
-- s'affiche sur le bouton), l'icone du raccourci, et en premiere ligne une
-- explication que le jeu n'execute pas (#), puis la commande.
local COURTS = {
    pilotefab = "PFa", pilotequetes = "PQu", ouvrir = "Sui", craftcore = "CrC", questcore = "QuC",
    mapcore = "MaC", legacycore = "LeC", stuffcore = "StC", tradecore = "TrC", pvpcore = "PvP", glorycore = "GlC", fabrications = "SFa", quetes = "SQu", suivis = "PSu",
    stop = "Stp", rendus = "Ren", recolte = "Rec", metier = "Met", oui = "Oui", non = "Non",
    messages = "Msg", reglages = "Rgl", improve = "IC", raccourcis = "Pan",
}
local function NomDeMacro(r) return COURTS[r.cle] or r.cle:sub(1, 3) end
-- Une macro du jeu est a nous seulement si elle lance ce raccourci : une
-- macro du joueur qui porte le meme nom n'est jamais touchee.
local function IndexANous(r, nom)
    local index = _G.GetMacroIndexByName and _G.GetMacroIndexByName(nom)
    if not (index and index > 0) then return nil end
    local _, _, corps = _G.GetMacroInfo(index)
    if type(corps) == "string" and corps:find("/sagacore " .. r.cle, 1, true) then return index end
    return nil
end
local function AncienNom(r) return ("SC " .. Suite.NomRaccourci(r)):sub(1, 16) end
-- L'icone d'une macro doit venir du catalogue des icones de macro du jeu
-- (celui de la fenetre Macros) : une image hors catalogue laisse la macro
-- sans icone, impossible a glisser. On prend le numero de l'icone voulue s'il
-- est au catalogue, sinon le point d'interrogation.
local catalogue
local function Catalogue()
    if catalogue then return catalogue end
    catalogue = {}
    for _, lire in ipairs({ _G.GetMacroIcons, _G.GetMacroItemIcons }) do
        if lire then
            local liste = {}
            local ok = pcall(lire, liste)
            if ok then for _, v in ipairs(liste) do catalogue[v] = true end end
        end
    end
    return catalogue
end
local sonde
local function IconeDeMacro(r)
    local chemin = "Interface\\Icons\\" .. r.icone
    local numero = _G.GetFileIDFromPath and _G.GetFileIDFromPath(chemin)
    if not (type(numero) == "number" and numero > 0) then
        sonde = sonde or UIParent:CreateTexture(nil, "BACKGROUND")
        sonde:SetTexture(chemin)
        numero = sonde.GetTextureFileID and sonde:GetTextureFileID()
    end
    -- Le catalogue rend des numeros ou des noms selon le client : on verifie
    -- l'un ou l'autre ; un catalogue illisible ne bloque rien.
    local cat = Catalogue()
    local avecNumeros, avecNoms = false, false
    for k in pairs(cat) do
        if type(k) == "number" then avecNumeros = true else avecNoms = true end
        if avecNumeros and avecNoms then break end
    end
    local present = (not avecNumeros and not avecNoms)
        or (avecNumeros and cat[numero])
        or (avecNoms and (cat[r.icone] or cat[r.icone:lower()] or cat[r.icone:upper()]))
    if type(numero) == "number" and numero > 0 and present then return numero end
    if avecNoms and present then return r.icone end
    return 134400
end
Suite.IconeDeMacro = IconeDeMacro

function Suite.CreerMacro(r)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not (_G.CreateMacro and _G.GetMacroIndexByName) then return false end
    local nom = NomDeMacro(r)
    local corps = "#SagaCore : " .. Suite.NomRaccourci(r) .. "\n/sagacore " .. r.cle
    -- Deja la (sous ce nom ou l'ancien "SC ...") : mise a jour, la macro garde
    -- sa place sur les barres.
    local index = IndexANous(r, nom) or IndexANous(r, AncienNom(r))
    if index then
        pcall(_G.EditMacro, index, nom, IconeDeMacro(r), corps)
        return true, index
    end
    -- Le nom est deja pris par une macro du joueur : on ne cree rien.
    if (_G.GetMacroIndexByName(nom) or 0) > 0 then return false end
    local ok, nouvel = pcall(_G.CreateMacro, nom, IconeDeMacro(r), corps, nil)
    return ok and nouvel ~= nil, nouvel
end

-- Supprime la macro du jeu d'un raccourci (son nom court, ou l'ancien "SC ...").
function Suite.SupprimerMacro(r)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not (_G.DeleteMacro and _G.GetMacroIndexByName) then return false end
    for _, nom in ipairs({ NomDeMacro(r), AncienNom(r) }) do
        local index = IndexANous(r, nom)
        if index then pcall(_G.DeleteMacro, index) end
    end
    return true
end

function Suite.MacroExiste(r)
    if not (_G.GetMacroIndexByName and _G.GetMacroInfo) then return false end
    return IndexANous(r, NomDeMacro(r)) ~= nil
end

-- ---------------------------------------------------------------------------
-- Fenetre Macros
-- ---------------------------------------------------------------------------

local function Bouton(parent, largeur, texte)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(largeur, 22)
    b:SetText(texte or "")
    return b
end

local function Voile(f)
    local voile = CreateFrame("Frame", nil, UIParent)
    voile:SetAllPoints(UIParent)
    voile:SetFrameStrata("FULLSCREEN_DIALOG")
    voile:SetFrameLevel(110)
    voile:EnableMouse(true)
    local t = voile:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0, 0, 0, 0.55)
    voile:Hide()
    f:HookScript("OnShow", function() voile:Show() end)
    f:HookScript("OnHide", function() voile:Hide() end)
end


Suite.ICONES_PERSO = { "INV_Misc_QuestionMark", "INV_Misc_Rune_01", "Ability_Mount_RidingHorse", "INV_Misc_Bag_08",
    "Spell_Holy_HolyBolt", "Ability_Warrior_BattleShout", "INV_Potion_54", "INV_Misc_Food_14", "Spell_Nature_Polymorph",
    "INV_Misc_Note_01", "Ability_Hunter_Pet_Wolf", "Spell_Fire_FlameBolt", "INV_Sword_04", "Trade_Mining",
    "Spell_Holy_Heal", "Spell_Nature_Rejuvenation", "Ability_Stealth", "INV_Misc_Head_Dragon_01" }

-- Actif dans le panneau, pour ce personnage (par defaut : oui).
local function ClePersoSuite()
    local nom, royaume = UnitName("player"), _G.SagaCoreRoyaume()
    return (nom or "?") .. " - " .. (royaume or "?")
end
-- Une fois : la macro « CC » du joueur (/sagacore), effacee par erreur, est
-- recreee a la connexion si elle n'existe plus.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UPDATE_MACROS")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not Suite.Prive() then return end
        local r = Reglages()
        if InCombatLockdown and InCombatLockdown() then return end
        if not (_G.GetMacroIndexByName and _G.CreateMacro) then return end
        -- Nos macros restees avec le point d'interrogation : leur vraie icone.
        if _G.GetMacroInfo and _G.EditMacro then
            for _, rac in ipairs(Suite.RACCOURCIS) do
                local index = IndexANous(rac, NomDeMacro(rac))
                if index then
                    local nomM, icone, corps = _G.GetMacroInfo(index)
                    local bonne = IconeDeMacro(rac)
                    if (icone == 134400 or icone == "INV_MISC_QUESTIONMARK") and bonne ~= 134400 then
                        pcall(_G.EditMacro, index, nomM, bonne, corps)
                    end
                end
            end
        end
        -- Ses macros CC (/sagacore) et RLD (/reload), effacees par erreur.
        for _, m in ipairs({ { "CC", 132279, "/sagacore", "macroCCRecreee" },
                             { "RLD", 1029581, "/reload", "macroRLDRecreee" } }) do
            if not r[m[4]] then
                if (_G.GetMacroIndexByName(m[1]) or 0) == 0 then
                    local ok, index = pcall(_G.CreateMacro, m[1], m[2], m[3], nil)
                    if not (ok and index) then ok, index = pcall(_G.CreateMacro, m[1], 134400, m[3], nil) end
                    if ok and index then
                        r[m[4]] = true
                        print("|cffffd100SagaCore|r " .. TR("Macro recréée : ", "Macro recreated : ") .. m[1])
                    else
                        print("|cffffd100SagaCore|r " .. TR("Impossible de recréer la macro ", "Could not recreate macro ") .. m[1] .. " : " .. tostring(index))
                    end
                else
                    r[m[4]] = true
                end
            end
        end
    end)
end

-- Par defaut, seuls les deux pilotages sont dans le panneau. Les anciens
-- reglages (ou tout etait coche pour essayer) repartent une fois de la.
local ACTIFS_DEFAUT = { ["r:pilotefab"] = true, ["r:pilotequetes"] = true }
local function MigrerRaccourcis()
    local r = Reglages()
    -- Remise a zero demandee (une fois) : gestionnaire de macros comme neuf.
    if Suite.Prive() and not r.macrosRemisesAZero then
        r.macrosRemisesAZero = true
        r.macrosPerso = {}
        r.raccourcisOff = {}
        r.raccourcisMigres = {}
    end
    local cle = ClePersoSuite()
    r.raccourcisMigres = type(r.raccourcisMigres) == "table" and r.raccourcisMigres or {}
    if r.raccourcisMigres[cle] then return end
    r.raccourcisMigres[cle] = 1
    r.raccourcisOff = type(r.raccourcisOff) == "table" and r.raccourcisOff or {}
    local t = {}
    for _, rac in ipairs(Suite.RACCOURCIS) do
        if not ACTIFS_DEFAUT["r:" .. rac.cle] then t["r:" .. rac.cle] = true end
    end
    for _, m in ipairs(type(r.macrosPerso) == "table" and r.macrosPerso or {}) do
        if type(m) == "table" and m.id then t["m:" .. m.id] = true end
    end
    r.raccourcisOff[cle] = t
end
function Suite.RaccourciActif(id)
    pcall(MigrerRaccourcis)
    local r = Reglages()
    local t = type(r.raccourcisOff) == "table" and r.raccourcisOff[ClePersoSuite()]
    return not (t and t[id])
end
function Suite.ToutDecocher()
    local r = Reglages()
    r.raccourcisOff = type(r.raccourcisOff) == "table" and r.raccourcisOff or {}
    local t = {}
    for _, rac in ipairs(Suite.RACCOURCIS) do t["r:" .. rac.cle] = true end
    for _, m in ipairs(Suite.MacrosPerso and Suite.MacrosPerso() or {}) do
        if type(m) == "table" and m.id then t["m:" .. m.id] = true end
    end
    r.raccourcisOff[ClePersoSuite()] = t
end
function Suite.ToutCocher()
    local r = Reglages()
    r.raccourcisOff = type(r.raccourcisOff) == "table" and r.raccourcisOff or {}
    r.raccourcisOff[ClePersoSuite()] = {}
end
function Suite.PoserRaccourciActif(id, oui)
    local r = Reglages()
    r.raccourcisOff = type(r.raccourcisOff) == "table" and r.raccourcisOff or {}
    local cle = ClePersoSuite()
    r.raccourcisOff[cle] = r.raccourcisOff[cle] or {}
    r.raccourcisOff[cle][id] = (not oui) or nil
end
local function IdPerso(m)
    if not m.id then
        local r = Reglages()
        r.prochaineMacro = (r.prochaineMacro or 0) + 1
        m.id = r.prochaineMacro
    end
    return "m:" .. m.id
end
Suite.IdPerso = IdPerso

-- Mise en page : une colonne de libelles a gauche, une colonne de boutons
-- a droite, les memes tailles partout (celles des reglages de la suite).
local LARGEUR_M, MARGE_M = 500, 16
local X_CHOIX, L_CHOIX, L_PETIT = 190, 140, 80

local function FenetreMacros()
    local f = Suite.fenetreMacros
    if f then return f end
    local charte = NS.charte
    if charte and charte.Fenetre then
        f = charte.Fenetre("CoreSuiteMacros", LARGEUR_M, 760, { portrait = false })
    else
        f = CreateFrame("Frame", "CoreSuiteMacros", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(LARGEUR_M, 760)
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(120)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    table.insert(UISpecialFrames, "CoreSuiteMacros")
    Voile(f)
    local zone = f.zone or f
    local LARGEUR_UTILE = LARGEUR_M - 2 * MARGE_M

    local y = 8
    local function Poser(objet, hauteur, ecartAvant)
        y = y + (ecartAvant or 0)
        objet:ClearAllPoints()
        objet:SetPoint("TOPLEFT", zone, "TOPLEFT", MARGE_M - 8, -y)
        y = y + hauteur
        return objet
    end
    local function Titre()
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetJustifyH("LEFT")
        return t
    end
    local function Texte()
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetWidth(LARGEUR_UTILE - 24)
        t:SetJustifyH("LEFT")
        return t
    end
    -- Une ligne de reglage : libelle a gauche, bouton (ou - valeur +) a droite.
    local function Ligne(auClic, avecPlusMoins, auPlus)
        local l = CreateFrame("Frame", nil, f)
        l:SetSize(LARGEUR_UTILE, 22)
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.nom:SetPoint("LEFT", 0, 0)
        if avecPlusMoins then
            l.moins = Bouton(l, 26, "-")
            l.moins:SetPoint("LEFT", l, "LEFT", X_CHOIX, 0)
            l.moins:SetScript("OnClick", function() auClic() Suite.RendreMacros() Suite.RafraichirRaccourcis() end)
            l.valeur = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            l.valeur:SetPoint("LEFT", l.moins, "RIGHT", 0, 0)
            l.valeur:SetWidth(L_CHOIX - 52)
            l.valeur:SetJustifyH("CENTER")
            l.plus = Bouton(l, 26, "+")
            l.plus:SetPoint("LEFT", l.valeur, "RIGHT", 0, 0)
            l.plus:SetScript("OnClick", function() auPlus() Suite.RendreMacros() Suite.RafraichirRaccourcis() end)
        else
            l.choix = Bouton(l, L_CHOIX)
            l.choix:SetPoint("LEFT", l, "LEFT", X_CHOIX, 0)
            l.choix:SetScript("OnClick", function() auClic() Suite.RendreMacros() Suite.RafraichirRaccourcis() end)
        end
        return l
    end

    f.intro = Poser(Texte(), 28)

    f.sectionPanneau = Poser(Titre(), 18, 6)
    f.macroPanneau = Poser(Texte(), 16, 4)
    f.rRond = Poser(Ligne(function()
        local r = Reglages()
        r.raccourcisCache = not r.raccourcisCache or nil
        Suite.PlacerBoutonRaccourcis()
    end), 22, 6)
    f.replacer = Bouton(f.rRond, L_PETIT)
    f.replacer:SetPoint("LEFT", f.rRond.choix, "RIGHT", 6, 0)
    f.replacer:SetScript("OnClick", function()
        local r = Reglages()
        r.raccourcisX, r.raccourcisY = nil, nil
        Suite.PlacerBoutonRaccourcis()
        Suite.RafraichirRaccourcis()
    end)
    f.replacer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR("Remettre le bouton à côté du suivi des quêtes", "Put the button back next to the quest tracker"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.replacer:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rOuverture = Poser(Ligne(function()
        local ordre = { "gauche", "droite", "haut", "bas" }
        local r = Reglages()
        local rang = 1
        for i, d in ipairs(ordre) do if d == (r.raccourcisOuverture or "gauche") then rang = i end end
        r.raccourcisOuverture = ordre[rang % #ordre + 1]
    end), 22, 4)
    f.rForme = Poser(Ligne(function()
        local r = Reglages()
        r.raccourcisRonds = not r.raccourcisRonds or nil
    end), 22, 4)
    f.rParLigne = Poser(Ligne(
        function() local r = Reglages() r.raccourcisParLigne = math.max(1, (r.raccourcisParLigne or 6) - 1) end, true,
        function() local r = Reglages() r.raccourcisParLigne = math.min(12, (r.raccourcisParLigne or 6) + 1) end), 22, 4)
    f.rLignes = Poser(Ligne(
        function() local r = Reglages() r.raccourcisLignes = math.max(1, (r.raccourcisLignes or 3) - 1) end, true,
        function() local r = Reglages() r.raccourcisLignes = math.min(6, (r.raccourcisLignes or 3) + 1) end), 22, 4)

    f.sectionMacros = Poser(Titre(), 18, 16)
    f.texteMacros = Poser(Texte(), 28, 4)
    -- Trois boutons sur une ligne, dans la largeur utile (468).
    f.tout = Poser(Bouton(f, 180), 22, 4)
    f.decocher = Bouton(f, 136)
    f.decocher:SetPoint("LEFT", f.tout, "RIGHT", 8, 0)
    f.decocher:SetScript("OnClick", function()
        Suite.ToutDecocher()
        Suite.RendreMacros()
        Suite.RafraichirRaccourcis()
    end)
    f.cocher = Bouton(f, 136)
    f.cocher:SetPoint("LEFT", f.decocher, "RIGHT", 8, 0)
    f.cocher:SetScript("OnClick", function()
        Suite.ToutCocher()
        Suite.RendreMacros()
        Suite.RafraichirRaccourcis()
    end)
    f.lignes = {}
    for i = 1, #Suite.RACCOURCIS do
        local l = CreateFrame("Button", nil, f)
        l:SetSize(LARGEUR_UTILE, 20)
        -- Case : dans le panneau de ce personnage, ou non.
        l.actif = CreateFrame("CheckButton", nil, l, "UICheckButtonTemplate")
        l.actif:SetSize(20, 20)
        l.actif:SetPoint("LEFT", -3, 0)
        l.actif:SetScript("OnClick", function(self)
            Suite.PoserRaccourciActif("r:" .. l.r.cle, self:GetChecked())
            Suite.RafraichirRaccourcis()
        end)
        l.icone = l:CreateTexture(nil, "ARTWORK")
        l.icone:SetSize(16, 16)
        l.icone:SetPoint("LEFT", l.actif, "RIGHT", 2, 0)
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
        l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.etat:SetPoint("LEFT", l, "LEFT", X_CHOIX, 0)
        l.creer = Bouton(l, L_PETIT)
        l.creer:SetHeight(18)
        l.creer:SetPoint("LEFT", l, "LEFT", X_CHOIX + L_CHOIX + 6, 0)
        l.creer:SetScript("OnClick", function(self) Suite.CreerMacro(self.r) Suite.RendreMacros() end)
        -- Au survol : la commande que lance la macro.
        l:SetScript("OnEnter", function(self)
            if not self.r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Suite.NomRaccourci(self.r), 1, 0.82, 0)
            GameTooltip:AddLine("/sagacore " .. self.r.cle, 1, 1, 1)
            GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.lignes[i] = Poser(l, 20, i == 1 and 6 or 0)
    end

    f.sectionPerso = Poser(Titre(), 18, 16)
    f.titrePerso = Poser(Texte(), 42, 4)
    -- Rapatrier une macro du jeu.
    f.choixJeu = Poser(Bouton(f, L_CHOIX + 52), 22, 6)
    f.choixJeu:SetScript("OnClick", function()
        local liste = Suite.MacrosDuJeu()
        if #liste == 0 then return end
        f.jeu = (f.jeu or 0) % #liste + 1
        Suite.RendreMacros()
    end)
    f.iconeJeu = f:CreateTexture(nil, "ARTWORK")
    f.iconeJeu:SetSize(20, 20)
    f.iconeJeu:SetPoint("LEFT", f.choixJeu, "RIGHT", 8, 0)
    f.ajouter = Bouton(f, L_PETIT + 30)
    f.ajouter:SetPoint("LEFT", f.choixJeu, "LEFT", X_CHOIX + L_CHOIX + 6 - 30, 0)
    f.ajouter:SetScript("OnClick", function()
        local m = Suite.MacrosDuJeu()[f.jeu or 1]
        if not m then return end
        for _, deja in ipairs(Suite.MacrosPerso()) do if deja.jeu ~= false and deja.nom == m.nom and not deja.texte then return end end
        local nouvelle = { nom = m.nom }
        IdPerso(nouvelle)
        table.insert(Suite.MacrosPerso(), nouvelle)
        Suite.RendreMacros()
        Suite.RafraichirRaccourcis()
    end)
    -- Ecrire une macro ici, sans passer par le jeu.
    f.nouvelle = Poser(Bouton(f, L_CHOIX + 52), 22, 6)
    f.nouvelle:SetScript("OnClick", function()
        local m = { nom = TR("Ma macro", "My macro"), icone = "INV_Misc_QuestionMark", texte = "" }
        IdPerso(m)
        table.insert(Suite.MacrosPerso(), m)
        f.edition = m
        Suite.RendreMacros()
    end)
    -- La liste de mes macros.
    f.persos = {}
    for i = 1, 8 do
        local l = CreateFrame("Frame", nil, f)
        l:SetSize(LARGEUR_UTILE, 20)
        l.actif = CreateFrame("CheckButton", nil, l, "UICheckButtonTemplate")
        l.actif:SetSize(20, 20)
        l.actif:SetPoint("LEFT", -3, 0)
        l.actif:SetScript("OnClick", function(self)
            Suite.PoserRaccourciActif(IdPerso(l.m), self:GetChecked())
            Suite.RafraichirRaccourcis()
        end)
        l.icone = l:CreateTexture(nil, "ARTWORK")
        l.icone:SetSize(16, 16)
        l.icone:SetPoint("LEFT", l.actif, "RIGHT", 2, 0)
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.nom:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
        l.nom:SetWidth(150)
        l.nom:SetJustifyH("LEFT")
        l.genre = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        l.genre:SetPoint("LEFT", l, "LEFT", X_CHOIX - 20, 0)
        l.modifier = Bouton(l, L_PETIT)
        l.modifier:SetHeight(18)
        l.modifier:SetPoint("LEFT", l, "LEFT", X_CHOIX + 60, 0)
        l.modifier:SetScript("OnClick", function() f.edition = (f.edition ~= l.m) and l.m or nil Suite.RendreMacros() end)
        l.retirer = Bouton(l, L_PETIT)
        l.retirer:SetHeight(18)
        l.retirer:SetPoint("LEFT", l.modifier, "RIGHT", 6, 0)
        l.retirer:SetScript("OnClick", function()
            local liste = Suite.MacrosPerso()
            for k, m in ipairs(liste) do if m == l.m then table.remove(liste, k) break end end
            if f.edition == l.m then f.edition = nil end
            Suite.RendreMacros()
            Suite.RafraichirRaccourcis()
        end)
        f.persos[i] = Poser(l, 20, i == 1 and 6 or 0)
    end
    -- Edition d'une macro de la suite : nom, icone, texte.
    f.edNom = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.edNom:SetSize(L_CHOIX + 40, 20)
    Poser(f.edNom, 20, 8)
    f.edNom:SetPoint("TOPLEFT", f.zone or f, "TOPLEFT", MARGE_M - 2, -(y - 20))
    f.edNom:SetAutoFocus(false)
    f.edNom:SetMaxLetters(24)
    f.edIcone = Bouton(f, L_PETIT)
    f.edIcone:SetPoint("LEFT", f.edNom, "RIGHT", 10, 0)
    f.edIcone:SetScript("OnClick", function()
        local m = f.edition
        if not m then return end
        local rang = 1
        for k, ic in ipairs(Suite.ICONES_PERSO) do if ic == m.icone then rang = k end end
        m.icone = Suite.ICONES_PERSO[rang % #Suite.ICONES_PERSO + 1]
        Suite.RendreMacros()
        Suite.RafraichirRaccourcis()
    end)
    f.edApercu = f:CreateTexture(nil, "ARTWORK")
    f.edApercu:SetSize(20, 20)
    f.edApercu:SetPoint("LEFT", f.edIcone, "RIGHT", 8, 0)
    f.edTexte = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.edTexte:SetSize(LARGEUR_UTILE - 30, 20)
    Poser(f.edTexte, 20, 8)
    f.edTexte:SetPoint("TOPLEFT", f.zone or f, "TOPLEFT", MARGE_M - 2, -(y - 20))
    f.edTexte:SetAutoFocus(false)
    f.edTexte:SetMaxLetters(255)
    f.edAide = Poser(Texte(), 16, 4)
    local function Garder()
        local m = f.edition
        if not m then return end
        local nom = f.edNom:GetText()
        if nom ~= "" then m.nom = nom end
        m.texte = f.edTexte:GetText()
        Suite.RafraichirRaccourcis()
    end
    for _, e in ipairs({ f.edNom, f.edTexte }) do
        e:SetScript("OnEnterPressed", function(self) Garder() self:ClearFocus() Suite.RendreMacros() end)
        e:SetScript("OnEditFocusLost", function() Garder() end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() Suite.RendreMacros() end)
    end

    -- La hauteur suit le contenu, le pied en dessous.
    f:SetHeight(y + 80)

    if charte and charte.BoutonDePied and f.pied then
        f.fermerBas = charte.BoutonDePied(f, TX("Close"), 110)
    else
        f.fermerBas = Bouton(f, 110, TX("Close"))
        f.fermerBas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    end
    f.fermerBas:SetScript("OnClick", function() f:Hide() end)
    if f.EnableGamePadButton and pcall(f.EnableGamePadButton, f, true) then
        f.focus = 1
        f.Elements = function()
            local liste = { f.rRond.choix, f.replacer, f.rOuverture.choix, f.rForme.choix,
                f.rParLigne.moins, f.rParLigne.plus, f.rLignes.moins, f.rLignes.plus, f.tout, f.decocher, f.cocher }
            for _, l in ipairs(f.lignes) do
                if l:IsShown() then
                    table.insert(liste, l.actif)
                    if l.creer:IsShown() then table.insert(liste, l.creer) end
                end
            end
            for _, b in ipairs({ f.choixJeu, f.ajouter, f.nouvelle }) do table.insert(liste, b) end
            for _, l in ipairs(f.persos) do
                if l:IsShown() then
                    table.insert(liste, l.actif)
                    if l.modifier:IsShown() then table.insert(liste, l.modifier) end
                    table.insert(liste, l.retirer)
                end
            end
            for _, b in ipairs({ f.edNom, f.edIcone, f.edTexte, f.fermerBas }) do
                if b:IsShown() then table.insert(liste, b) end
            end
            return liste
        end
        f:SetScript("OnGamePadButtonDown", function(_, bouton)
            if f.edNom:HasFocus() or f.edTexte:HasFocus() then
                if bouton == "PAD2" then f.edNom:ClearFocus() f.edTexte:ClearFocus() end
                return
            end
            -- L3 / R3 : on continue dans la colonne des onglets.
            if bouton == "PADLSTICK" or bouton == "PADRSTICK" then
                f:Hide()
                Suite.ContinuerColonne(bouton == "PADLSTICK" and -1 or 1)
                return
            end
            local liste = f.Elements()
            if bouton == "PADDDOWN" then f.focus = math.min(#liste, f.focus + 1)
            elseif bouton == "PADDUP" then f.focus = math.max(1, f.focus - 1)
            elseif bouton == "PAD1" then
                local b = liste[f.focus]
                if b and b:GetObjectType() == "EditBox" then b:SetFocus()
                elseif b and b:IsEnabled() then b:Click() end
            elseif bouton == "PAD2" then f:Hide() return end
            Suite.RendreMacros()
        end)
    end
    Suite.fenetreMacros = f
    return f
end

function Suite.RendreMacros()
    local f = Suite.fenetreMacros
    if not f then return end
    local titre = TR("Macros et raccourcis", "Macros and shortcuts")
    if f.titre then f.titre:SetText(titre) end
    if f.TitleText then f.TitleText:SetText(titre) end
    local r = Reglages()
    f.intro:SetText(TR("Le bouton rond ouvre le panneau des raccourcis. Les macros se posent où vous voulez (Échap, Macros), et sont communes à tous vos personnages.",
        "The round button opens the shortcut panel. Macros go wherever you like (Esc, Macros) and are shared by all your characters."))
    f.sectionPanneau:SetText(TR("Le panneau des raccourcis", "The shortcut panel"))
    f.macroPanneau:SetText(TR("Macro qui l'ouvre et le ferme (manette) : |cffffd100/sagacore raccourcis|r", "Macro that opens and closes it (gamepad) : |cffffd100/sagacore raccourcis|r"))
    local OUV = { gauche = TR("Vers la gauche", "To the left"), droite = TR("Vers la droite", "To the right"),
        haut = TR("Vers le haut", "Upwards"), bas = TR("Vers le bas", "Downwards") }
    f.rRond.nom:SetText(TR("Bouton rond à l'écran :", "Round button on screen :"))
    f.rRond.choix:SetText(r.raccourcisCache and TR("Caché", "Hidden") or TR("Affiché", "Shown"))
    f.replacer:SetText(TR("Replacer", "Reset"))
    f.rOuverture.nom:SetText(TR("Les icônes s'ouvrent :", "Icons open :"))
    f.rOuverture.choix:SetText(OUV[r.raccourcisOuverture or "gauche"])
    f.rForme.nom:SetText(TR("Forme des icônes :", "Icon shape :"))
    f.rForme.choix:SetText(r.raccourcisRonds and TR("Rondes", "Round") or TR("Carrées", "Square"))
    f.rParLigne.nom:SetText(TR("Icônes par ligne :", "Icons per row :"))
    f.rParLigne.valeur:SetText(tostring(r.raccourcisParLigne or 6))
    f.rLignes.nom:SetText(TR("Lignes au maximum :", "Rows at most :"))
    f.rLignes.valeur:SetText(tostring(r.raccourcisLignes or 3))
    f.sectionMacros:SetText(TR("Les macros de la suite", "The suite's macros"))
    f.texteMacros:SetText(TR("Une macro par raccourci, nommée « SC ... ». Survolez une ligne pour voir sa commande. Pas en combat.",
        "One macro per shortcut, named \"SC ...\". Hover a row to see its command. Not in combat."))
    f.tout:SetText(TR("Créer toutes les macros", "Create all macros"))
    f.decocher:SetText(TR("Tout décocher", "Uncheck all"))
    f.cocher:SetText(TR("Tout cocher", "Check all"))
    local rang = 0
    for _, l in ipairs(f.lignes) do l:Hide() end
    for _, rac in ipairs(Suite.RACCOURCIS) do
        if Dispo(rac) then
            rang = rang + 1
            local l = f.lignes[rang]
            l.r = rac
            l.creer.r = rac
            l.icone:SetTexture("Interface\\Icons\\" .. rac.icone)
            l.nom:SetText(Suite.NomRaccourci(rac))
            l.actif:SetChecked(Suite.RaccourciActif("r:" .. rac.cle))
            l.actif:SetShown(rac.cle ~= "raccourcis")
            local existe = Suite.MacroExiste(rac)
            l.etat:SetText(existe and ("|cff4fd16a" .. TR("Macro créée", "Macro created") .. "|r") or ("|cff888888" .. TR("Pas encore créée", "Not created yet") .. "|r"))
            l.creer:SetText(TR("Créer", "Create"))
            l.creer:SetShown(not existe)
            l:Show()
        end
    end
    f.sectionPerso:SetText(TR("Mes macros", "My macros"))
    f.titrePerso:SetText(TR("Rapatriez vos macros du jeu, ou écrivez-en ici. Celles écrites ici restent dans la suite : pour les avoir aussi dans le jeu, créez-les dans le jeu. Communes au compte ; la case coche ce qui va dans le panneau de ce personnage.",
        "Bring in your game macros, or write some here. Those written here stay in the suite : to have them in the game too, create them in the game. Shared by the account ; the box ticks what goes in this character's panel."))
    local jeu = Suite.MacrosDuJeu()
    if f.jeu and not jeu[f.jeu] then f.jeu = nil end
    if not f.jeu and #jeu > 0 then f.jeu = 1 end
    local j = f.jeu and jeu[f.jeu]
    f.choixJeu:SetText(j and (TR("Macro du jeu : ", "Game macro : ") .. j.nom) or TR("Aucune macro dans le jeu", "No macro in the game"))
    f.iconeJeu:SetTexture(j and j.icone or nil)
    f.ajouter:SetText(TR("Rapatrier", "Bring in"))
    f.ajouter:SetEnabled(j ~= nil)
    f.nouvelle:SetText(TR("Écrire une nouvelle macro", "Write a new macro"))
    local perso = Suite.MacrosPerso()
    for i, l in ipairs(f.persos) do
        local m = perso[i]
        if m then
            l.m = m
            IdPerso(m)
            local suite = m.texte ~= nil
            local icone = suite and ("Interface\\Icons\\" .. (m.icone or "INV_Misc_QuestionMark")) or select(2, _G.GetMacroInfo and _G.GetMacroInfo(m.nom))
            l.icone:SetTexture(icone or "Interface\\Icons\\INV_Misc_QuestionMark")
            l.nom:SetText(m.nom or "?")
            l.genre:SetText(suite and TR("de la suite", "suite") or TR("du jeu", "game"))
            l.actif:SetChecked(Suite.RaccourciActif(IdPerso(m)))
            l.modifier:SetText(f.edition == m and TR("Fermer", "Close") or TR("Modifier", "Edit"))
            l.modifier:SetShown(suite)
            l.retirer:SetText(TR("Retirer", "Remove"))
            l:Show()
        else
            l:Hide()
        end
    end
    local m = f.edition
    for _, w in ipairs({ f.edNom, f.edIcone, f.edApercu, f.edTexte, f.edAide }) do w:SetShown(m ~= nil) end
    if m then
        if not f.edNom:HasFocus() then f.edNom:SetText(m.nom or "") end
        if not f.edTexte:HasFocus() then f.edTexte:SetText(m.texte or "") f.edTexte:SetCursorPosition(0) end
        f.edIcone:SetText(TR("Icône", "Icon"))
        f.edApercu:SetTexture("Interface\\Icons\\" .. (m.icone or "INV_Misc_QuestionMark"))
        f.edAide:SetText(TR("Ligne du dessus : le nom. Ligne du dessous : le texte de la macro (/cast, /use...). Entrée pour garder.",
            "Top line : the name. Bottom line : the macro text (/cast, /use...). Enter to keep."))
    end
    if f.Elements then
        for i, b in ipairs(f.Elements()) do if i == f.focus then b:LockHighlight() else b:UnlockHighlight() end end
    end
end

function Suite.OuvrirMacros()
    local f = FenetreMacros()
    f.focus = 1
    Suite.RendreMacros()
    f:Show()
    f:SetFrameLevel(120)
    f:Raise()
end

-- ---------------------------------------------------------------------------
-- Le bouton rond et le panneau des raccourcis
-- ---------------------------------------------------------------------------

-- Mes macros : le nom d'une macro du jeu (son icone et son texte viennent du
-- jeu, a jour). Communes au compte.
function Suite.MacrosPerso()
    local r = Reglages()
    r.macrosPerso = type(r.macrosPerso) == "table" and r.macrosPerso or {}
    return r.macrosPerso
end

-- Les macros du jeu (communes et du personnage), sauf celles de la suite.
function Suite.MacrosDuJeu()
    local liste = {}
    if not (_G.GetNumMacros and _G.GetMacroInfo) then return liste end
    local communes, perso = _G.GetNumMacros()
    local function Prendre(i)
        local nom, icone = _G.GetMacroInfo(i)
        if nom and not nom:find("^SC ") then table.insert(liste, { nom = nom, icone = icone }) end
    end
    for i = 1, communes or 0 do Prendre(i) end
    for i = 1, perso or 0 do Prendre((_G.MAX_ACCOUNT_MACROS or 120) + i) end
    return liste
end

-- Le panneau : des boutons officiels du jeu (un clic lance), carres comme
-- ceux des barres manette, ou ronds en arc de cercle. La croix s'y deplace ;
-- A lance ; la macro /sagacore raccourcis (ou B) referme et rend la manette.
local function Panneau()
    local p = Suite.panneauRaccourcis
    if p then return p end
    p = CreateFrame("Frame", "CoreSuiteRaccourcis", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    if p.SetToplevel then p:SetToplevel(true) end
    p:HookScript("OnShow", function(self) self:Raise() end)
    p:SetClampedToScreen(true)
    p.boutons = {}
    p.focus = 1
    local function Nav(nom, auClic)
        local b = CreateFrame("Button", nom, p)
        b:SetScript("OnClick", auClic)
        return b
    end
    Nav("CoreSuiteRaccourcisHaut", function() Suite.BougerRaccourci(0, -1) end)
    Nav("CoreSuiteRaccourcisBas", function() Suite.BougerRaccourci(0, 1) end)
    Nav("CoreSuiteRaccourcisGauche", function() Suite.BougerRaccourci(-1, 0) end)
    Nav("CoreSuiteRaccourcisDroite", function() Suite.BougerRaccourci(1, 0) end)
    Nav("CoreSuiteRaccourcisFermer", function() Suite.FermerRaccourcis() end)
    table.insert(UISpecialFrames, "CoreSuiteRaccourcis")
    -- Une petite fenetre discrete autour des icones, ouverte a la manette :
    -- les commandes en haut, dedans, les icones dessous.
    local okA, fond = pcall(CreateFrame, "Frame", nil, p, "TooltipBackdropTemplate")
    p.aide = okA and fond or CreateFrame("Frame", nil, p)
    p.aide:SetFrameLevel(math.max(0, p:GetFrameLevel() - 1))
    p.aide:SetClampedToScreen(true)
    p.aide.texte = p.aide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.aide.texte:SetPoint("TOPLEFT", 10, -8)
    p:SetScript("OnHide", function(self)
        GameTooltip:Hide()
        local rond = Suite.boutonRaccourcis
        if rond then
            rond:SetAlpha(1)
            if rond.icone and rond.icone.SetDesaturated then rond.icone:SetDesaturated(false) end
        end
        if not (InCombatLockdown and InCombatLockdown()) then ClearOverrideBindings(self) end
    end)
    p:RegisterEvent("PLAYER_REGEN_DISABLED")
    p:SetScript("OnEvent", function(self) self:Hide() end)
    p:Hide()
    Suite.panneauRaccourcis = p
    return p
end

local function LierManette(p)
    if InCombatLockdown and InCombatLockdown() then return end
    if p.suspendu then return end
    ClearOverrideBindings(p)
    local manette = _G.C_GamePad and _G.C_GamePad.IsEnabled and select(2, pcall(_G.C_GamePad.IsEnabled)) == true
    if not manette then return end
    SetOverrideBindingClick(p, true, "PADDUP", "CoreSuiteRaccourcisHaut")
    SetOverrideBindingClick(p, true, "PADDDOWN", "CoreSuiteRaccourcisBas")
    SetOverrideBindingClick(p, true, "PADDLEFT", "CoreSuiteRaccourcisGauche")
    SetOverrideBindingClick(p, true, "PADDRIGHT", "CoreSuiteRaccourcisDroite")
    -- Echappe : B, et aussi Vue, Menu et la touche du jeu au centre.
    for _, touche in ipairs({ "PAD2", "PADBACK", "PADFORWARD", "PADSYSTEM" }) do
        SetOverrideBindingClick(p, true, touche, "CoreSuiteRaccourcisFermer")
    end
    if p.focus == 0 then
        -- Sur le bouton rond : A referme le panneau.
        SetOverrideBindingClick(p, true, "PAD1", "CoreSuiteRaccourcisFermer")
    else
        local b = p.boutons[p.focus]
        if b and b:IsShown() then SetOverrideBindingClick(p, true, "PAD1", b:GetName()) end
    end
end

-- Pendant qu'on pilote un suivi lance depuis le panneau, le panneau rend
-- ses touches (son aide passe en gris) ; liberer le suivi les lui rend.
function Suite.SuspendrePanneau()
    local p = Suite.panneauRaccourcis
    if not (p and p:IsShown()) then return end
    p.suspendu = true
    if not (InCombatLockdown and InCombatLockdown()) then ClearOverrideBindings(p) end
    if p.aide then p.aide:SetAlpha(0.4) end
end
function Suite.ReprendrePanneau()
    local p = Suite.panneauRaccourcis
    if not (p and p.suspendu) then return end
    p.suspendu = nil
    if p.aide then p.aide:SetAlpha(1) end
    if p:IsShown() then Suite.MarquerRaccourci() end
end

function Suite.MarquerRaccourci()
    local p = Suite.panneauRaccourcis
    if not p then return end
    GameTooltip:Hide()
    -- Tout a 40 %, sauf l'element choisi, en pleine couleur.
    -- Les autres en gris (icone desaturee, liseré gris), le choisi en couleur.
    local function Teinter(b, choisi)
        if not b then return end
        b:SetAlpha(choisi and 1 or 0.75)
        if b.icone and b.icone.SetDesaturated then b.icone:SetDesaturated(not choisi) end
        if b.bordure then
            if choisi then b.bordure:SetVertexColor(0.72, 0.6, 0.32, 1) else b.bordure:SetVertexColor(0.45, 0.45, 0.45, 1) end
        end
    end
    local rond = Suite.boutonRaccourcis
    Teinter(rond, p.focus == 0)
    for i, b in ipairs(p.boutons) do
        if b.lisere then b.lisere:SetShown(i == p.focus and b:IsShown()) end
        Teinter(b, i == p.focus)
        if i == p.focus and b:IsShown() then
            local survol = b:GetScript("OnEnter")
            if survol then survol(b) end
        end
    end
    -- L'aide : ce que fait chaque touche, a la manette seulement.
    local manette = _G.C_GamePad and _G.C_GamePad.IsEnabled and select(2, pcall(_G.C_GamePad.IsEnabled)) == true
    if p.aide then
        if manette then
            local esp = "    "
            local function G(t) return (string.gsub(t, ":20:20|a", ":16:16|a")) end
            p.aide.texte:SetText(G(GlypheCroix()) .. " " .. TR("Se déplacer", "Move") .. esp
                .. G(GlyphePad("PAD1")) .. " " .. (p.focus == 0 and TR("Fermer", "Close") or TR("Lancer", "Launch")) .. esp
                .. G(GlyphePad("PAD2")) .. " " .. TR("Rendre la manette", "Release the gamepad"))
            local largeur = math.max(p:GetWidth() + 20, (p.aide.texte:GetStringWidth() or 200) + 20)
            p.aide:ClearAllPoints()
            local gauche = (Reglages().raccourcisOuverture or "gauche") == "gauche"
            local ancre = gauche and "RIGHT" or "LEFT"
            local dx = gauche and 10 or -10
            p.aide:SetPoint("TOP" .. ancre, p, "TOP" .. ancre, dx, 30)
            p.aide:SetPoint("BOTTOM" .. ancre, p, "BOTTOM" .. ancre, dx, -10)
            p.aide:SetWidth(largeur)
            p.aide:Show()
        else
            p.aide:Hide()
        end
    end
    LierManette(p)
end

-- Deplacement dans le panneau : en ligne, gauche / droite (haut / bas aussi) ;
-- en carre, les quatre directions ; en arc, gauche / droite le long de l'arc.
function Suite.BougerRaccourci(dx, dy)
    local p = Suite.panneauRaccourcis
    if not p or not p.n or p.n == 0 then return end
    local ouverture = Reglages().raccourcisOuverture or "gauche"
    local rond = Suite.boutonRaccourcis
    local avecRond = rond and rond:IsShown()
    -- Depuis le bouton rond : on entre dans le panneau par la premiere icone.
    if p.focus == 0 then
        p.focus = 1
        Suite.MarquerRaccourci()
        return
    end
    -- Ouvert vers la gauche, les colonnes avancent vers la gauche a l'ecran.
    if ouverture == "gauche" then dx = -dx end
    local ici = p.places and p.places[p.focus]
    if not ici then return end
    local x, y = ici.col + dx, ici.lig + dy
    local ligne = p.grille and p.grille[y]
    local cible
    if ligne then
        if dy ~= 0 then
            -- Ligne plus courte : la derniere icone de cette ligne.
            local dernier = 0
            for k in pairs(ligne) do dernier = math.max(dernier, k) end
            cible = ligne[math.min(math.max(x, 0), dernier)]
        elseif x >= 0 then
            cible = ligne[x]
        end
    end
    if cible then
        p.focus = cible
    elseif avecRond and ((x < 0 and (ouverture == "gauche" or ouverture == "droite"))
        or (y < 0 and (ouverture == "haut" or ouverture == "bas"))) then
        -- Sortie du cote du bouton rond : retour sur lui.
        p.focus = 0
    end
    Suite.MarquerRaccourci()
end

function Suite.RafraichirRaccourcis()
    pcall(Suite.PlacerBoutonRaccourcis)
    local p = Suite.panneauRaccourcis
    if p and p:IsShown() then p:Hide() Suite.BasculerRaccourcis() end
end

function Suite.FermerRaccourcis()
    local p = Suite.panneauRaccourcis
    if p then p:Hide() end
end

local function Entrees()
    local liste = {}
    for _, r in ipairs(Suite.RACCOURCIS) do
        if Dispo(r) and r.cle ~= "raccourcis" and Suite.RaccourciActif("r:" .. r.cle) then
            table.insert(liste, { nom = Suite.NomRaccourci(r), icone = "Interface\\Icons\\" .. r.icone, texte = "/sagacore " .. r.cle, famille = Suite.FamilleDe(r), cle = r.cle,
                desc = r.desc and TR(r.desc, r.descEn or r.desc) or nil })
        end
    end
    for _, m in ipairs(Suite.MacrosPerso()) do
        if type(m) == "table" and Suite.RaccourciActif(IdPerso(m)) then
            if m.texte then
                if m.texte ~= "" then
                    table.insert(liste, { nom = m.nom or "?", icone = Suite.IconeDe and Suite.IconeDe(m.icone) or m.icone, texte = m.texte, famille = "perso" })
                end
            elseif m.nom and _G.GetMacroInfo then
                local nom, icone, corps = _G.GetMacroInfo(m.nom)
                if nom then table.insert(liste, { nom = nom, icone = icone, macro = nom, corps = corps, famille = "perso" }) end
            end
        end
    end
    return liste
end

-- Taille unique : le bouton rond (ou carre) et toutes les icones du panneau.
Suite.TAILLE_RACCOURCI = 28

-- Habille un bouton : icone carree ou ronde, liseré fin couleur or terni.
-- b.icone (texture) et b.masque (masque rond) existent deja.
local function Habiller(b, taille, rond)
    b:SetSize(taille, taille)
    if not b.bordure then
        b.bordure = b:CreateTexture(nil, "BACKGROUND")
        b.bordure:SetPoint("CENTER")
    end
    if b.cadre then b.cadre:Hide() end
    b.icone:ClearAllPoints()
    b.icone:SetPoint("TOPLEFT", 1.5, -1.5)
    b.icone:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    b.bordure:SetSize(taille, taille)
    if rond then
        b.bordure:SetTexture("Interface\\Masks\\CircleMaskScalable")
        b.bordure:SetVertexColor(0.72, 0.6, 0.32, 1)
        -- Le bord carre dessine dans les icones du jeu ne doit pas se voir
        -- dans le rond : on ne garde que le coeur de l'icone.
        b.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        b.bordure:SetColorTexture(0.72, 0.6, 0.32, 1)
        b.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if b.masque then
        if rond and not b.masqueActif then b.icone:AddMaskTexture(b.masque) b.masqueActif = true
        elseif not rond and b.masqueActif then b.icone:RemoveMaskTexture(b.masque) b.masqueActif = nil end
    end
    if b.lisere then
        b.lisere:SetTexture(rond and "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight" or "Interface\\Buttons\\CheckButtonHilight")
    end
    -- Survol : un voile clair de la forme de l'icone (pas de carre bleu).
    if b.SetHighlightTexture and not b.voileSurvol then
        pcall(b.SetHighlightTexture, b, "")
        b.voileSurvol = b:CreateTexture(nil, "HIGHLIGHT")
        b.voileSurvol:SetBlendMode("ADD")
    end
    if b.voileSurvol then
        b.voileSurvol:ClearAllPoints()
        b.voileSurvol:SetAllPoints(b.icone)
        if rond then
            b.voileSurvol:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            b.voileSurvol:SetVertexColor(1, 1, 1, 0.25)
        else
            b.voileSurvol:SetColorTexture(1, 1, 1, 0.18)
        end
    end
end
Suite.HabillerRaccourci = Habiller

function Suite.BasculerRaccourcis()
    if not Suite.Prive() then return end
    if Suite.BasculerMacroCore and Suite.BasculerMacroCore() then return end
    local p = Panneau()
    if p:IsShown() then p:Hide() return end
    if InCombatLockdown and InCombatLockdown() then return end
    local r = Reglages()
    local brute = Entrees()
    local parLigne = r.raccourcisParLigne or 6
    local T, ECART = Suite.TAILLE_RACCOURCI, 6
    local ouverture = r.raccourcisOuverture or "gauche"
    -- Une ligne par famille (coupee si elle depasse le nombre par ligne).
    local liste, places = {}, {}
    local lig = -1
    p.grille = {}
    for _, fam in ipairs(Suite.FAMILLES) do
        local col = parLigne
        for _, e in ipairs(brute) do
            if e.famille == fam.cle then
                if col >= parLigne then lig = lig + 1 col = 0 p.grille[lig] = {} end
                table.insert(liste, e)
                places[#liste] = { col = col, lig = lig }
                p.grille[lig][col] = #liste
                col = col + 1
            end
        end
    end
    local n = #liste
    p.n = n
    p.places = places
    p.colonnes = 1
    for _, ligne in pairs(p.grille) do
        local c = 0
        for k in pairs(ligne) do c = math.max(c, k + 1) end
        p.colonnes = math.max(p.colonnes, c)
    end
    for i, e in ipairs(liste) do
        local b = p.boutons[i]
        if not b then
            b = CreateFrame("Button", "CoreSuiteRaccourci" .. i, p, "SecureActionButtonTemplate")
            b:RegisterForClicks("AnyUp", "AnyDown")
            b.icone = b:CreateTexture(nil, "ARTWORK")
            b.icone:SetAllPoints()
            if b.CreateMaskTexture then
                b.masque = b:CreateMaskTexture()
                if b.masque then
                    b.masque:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    b.masque:SetAllPoints(b.icone)
                end
            end
            b.cadre = b:CreateTexture(nil, "OVERLAY")
            b.lisere = b:CreateTexture(nil, "OVERLAY", nil, 2)
            b.lisere:SetAllPoints()
            b.lisere:SetBlendMode("ADD")
            b.lisere:Hide()
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.e.nom, 1, 0.82, 0)
                local detail = self.e.texte or self.e.corps
                if detail then GameTooltip:AddLine(detail, 0.7, 0.7, 0.7, true) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Lancer une action ne ferme pas le panneau : il reste ouvert jusqu'a
            -- ce qu'on le ferme (B, ou le bouton rond).
            p.boutons[i] = b
        end
        b.e = e
        if e.macro then
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", nil)
            b:SetAttribute("macro", e.macro)
        else
            b:SetAttribute("type", "macro")
            b:SetAttribute("macro", nil)
            b:SetAttribute("macrotext", e.texte)
        end
        b.icone:SetTexture(e.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
        Habiller(b, T, r.raccourcisRonds)
        b:ClearAllPoints()
        -- Vers la gauche, les icones partent du bouton rond vers la gauche
        -- (la premiere tout contre lui) ; les autres sens de meme.
        local col, lig = places[i].col, places[i].lig
        if ouverture == "gauche" then
            b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(col * (T + ECART)), -(lig * (T + ECART)))
        else
            b:SetPoint("TOPLEFT", p, "TOPLEFT", col * (T + ECART), -(lig * (T + ECART)))
        end
        b:Show()
    end
    for i = n + 1, #p.boutons do p.boutons[i]:Hide() end
    local nbLignes = math.max(1, lig + 1)
    p:SetSize(p.colonnes * (T + ECART) - ECART, nbLignes * (T + ECART) - ECART)
    p:ClearAllPoints()
    local rond = Suite.boutonRaccourcis
    if rond and rond:IsShown() then
        if ouverture == "gauche" then p:SetPoint("TOPRIGHT", rond, "TOPLEFT", -8, 0)
        elseif ouverture == "droite" then p:SetPoint("TOPLEFT", rond, "TOPRIGHT", 8, 0)
        elseif ouverture == "haut" then p:SetPoint("BOTTOMLEFT", rond, "TOPLEFT", 0, 8)
        else p:SetPoint("TOPLEFT", rond, "BOTTOMLEFT", 0, -8) end
    else
        p:SetPoint("CENTER")
    end
    -- A l'ouverture, on reste sur le bouton rond ; on entre en se deplacant.
    p.focus = (rond and rond:IsShown()) and 0 or 1
    p:Show()
    Suite.MarquerRaccourci()
end

-- ---------------------------------------------------------------------------
-- Fenetre « Macros de la suite » : une petite fenetre comme les suivis
-- (Mes fabrications, Quetes), ouverte par le bouton rond. Un groupe repliable
-- par famille, une ligne par raccourci ; on la pilote a la manette des
-- qu'elle s'ouvre. Lancer un pilotage depuis elle la laisse ouverte : la
-- manette passe a la fenetre pilotee, puis lui revient quand on libere.
-- ---------------------------------------------------------------------------

local LARGEUR_MACROS = 290
local fenM

local function FenetreMacrosSuite()
    if fenM then return fenM end
    local C = NS.charte
    if not (C and C.Fenetre) then return nil end
    local f = C.Fenetre("CoreSuiteMacros", LARGEUR_MACROS, 120, { portrait = false, strate = "MEDIUM", sansPied = true })
    f.titre:SetText(TR("Macros de la suite", "Suite macros"))
    f.fermer:SetScript("OnClick", function() f:Hide() end)
    f.lignes, f.titres = {}, {}
    f.piloteFermerSurB = true
    -- Replier : seulement le titre.
    local replier = CreateFrame("Button", nil, f)
    replier:SetFrameLevel((f.fermer:GetFrameLevel() or f:GetFrameLevel()) + 1)
    replier:SetSize(16, 16)
    replier:SetPoint("RIGHT", f.fermer, "LEFT", -2, 0)
    replier:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    replier:SetScript("OnClick", function()
        local r = Reglages()
        r.macrosReplie = not r.macrosReplie or nil
        Suite.DessinerFenetreMacros()
    end)
    f.replier = replier
    f:SetScript("OnHide", function()
        if Suite.pilote and Suite.pilote:IsShown() and Suite.pilote.nom == "CoreSuiteMacros" then Suite.Piloter(false) end
        if Suite.boutonRaccourcis and Suite.boutonRaccourcis.icone then Suite.boutonRaccourcis.icone:SetDesaturated(false) end
    end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self) if self:IsShown() then Suite.Piloter(false) end end)
    fenM = f
    return f
end

local function LigneM(f, i, secure)
    local pool = secure and "lignesS" or "lignes"
    f[pool] = f[pool] or {}
    local b = f[pool][i]
    if b then return b end
    if secure then
        b = CreateFrame("Button", "CoreSuiteMacrosS" .. i, f.zone, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
    else
        b = CreateFrame("Button", nil, f.zone)
    end
    b:SetHeight(20)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(16, 16)
    b.icone:SetPoint("LEFT", 18, 0)
    if b.CreateMaskTexture then
        local m = b:CreateMaskTexture()
        if m then
            m:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(b.icone)
            b.icone:AddMaskTexture(m)
        end
    end
    b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nom:SetPoint("LEFT", b.icone, "RIGHT", 6, 0)
    b.nom:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.nom:SetJustifyH("LEFT")
    b.nom:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.e and self.e.nom or "", 1, 0.82, 0)
        local detail = self.e and (self.e.texte or self.e.corps)
        if detail then GameTooltip:AddLine(detail, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f[pool][i] = b
    return b
end

local function TitreM(f, i)
    local t = f.titres[i]
    if t then return t end
    t = CreateFrame("Button", nil, f.zone)
    t:SetHeight(20)
    t.marque = t:CreateTexture(nil, "ARTWORK")
    t.marque:SetSize(14, 14)
    t.marque:SetPoint("LEFT", 0, 0)
    t.nom = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.nom:SetPoint("LEFT", t.marque, "RIGHT", 4, 0)
    t.nom:SetJustifyH("LEFT")
    t.filet = t:CreateTexture(nil, "ARTWORK")
    t.filet:SetHeight(1)
    t.filet:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    t.filet:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
    t.filet:SetColorTexture(1, 0.82, 0, 0.25)
    t:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    t:SetScript("OnClick", function(self)
        local r = Reglages()
        r.famillesRepliees = type(r.famillesRepliees) == "table" and r.famillesRepliees or {}
        r.famillesRepliees[self.cle] = not r.famillesRepliees[self.cle] or nil
        Suite.DessinerFenetreMacros()
    end)
    f.titres[i] = t
    return t
end

function Suite.DessinerFenetreMacros()
    local f = fenM
    if not (f and f:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local r = Reglages()
    local replie = r.macrosReplie
    f.replier:SetNormalTexture(replie and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    for _, l in ipairs(f.lignes or {}) do l:Hide() end
    for _, l in ipairs(f.lignesS or {}) do l:Hide() end
    for _, t in ipairs(f.titres) do t:Hide() end
    local y, nT, nL, nS = 0, 0, 0, 0
    if not replie then
        local entrees = Entrees()
        local repliees = type(r.famillesRepliees) == "table" and r.famillesRepliees or {}
        local largeur = LARGEUR_MACROS - 2 * ((NS.charte and NS.charte.MARGE) or 12)
        for _, fam in ipairs(Suite.FAMILLES) do
            local membres = {}
            for _, e in ipairs(entrees) do if e.famille == fam.cle then table.insert(membres, e) end end
            if #membres > 0 then
                nT = nT + 1
                local t = TitreM(f, nT)
                t.cle = fam.cle
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, -y)
                t:SetWidth(largeur)
                t.marque:SetTexture(repliees[fam.cle] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                t.nom:SetText(TR(fam.fr, fam.en) .. "  |cff9d9d9d" .. #membres .. "|r")
                t:Show()
                y = y + 24
                if not repliees[fam.cle] then
                    for _, e in ipairs(membres) do
                        local b
                        if e.macro or fam.cle == "perso" then
                            nS = nS + 1
                            b = LigneM(f, nS, true)
                            b:SetAttribute("type", "macro")
                            if e.macro then b:SetAttribute("macrotext", nil) b:SetAttribute("macro", e.macro)
                            else b:SetAttribute("macro", nil) b:SetAttribute("macrotext", e.texte) end
                        else
                            nL = nL + 1
                            b = LigneM(f, nL, false)
                            b:SetScript("OnClick", function(self)
                                local rac = self.e and self.e.cle and Suite.Raccourci(self.e.cle)
                                if rac then Suite.Lancer(rac) end
                            end)
                        end
                        b.e = e
                        b.icone:SetTexture(e.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
                        b.nom:SetText(e.nom)
                        b:ClearAllPoints()
                        b:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, -y)
                        b:SetWidth(largeur)
                        b:Show()
                        y = y + 22
                    end
                end
                y = y + 4
            end
        end
    end
    local haut = (f:GetHeight() or 0) - (f.zone:GetHeight() or 0)
    f:SetHeight(math.max(60, (replie and 0 or y) + math.max(haut, 40)))
    if Suite.pilote and Suite.pilote:IsShown() and Suite.pilote.nom == "CoreSuiteMacros" then
        Suite.pilote.Marquer()
        Suite.pilote.Barre()
    end
end

-- Ouvrir / fermer : pres du bouton rond, puis pilotee a la manette.
function Suite.BasculerFenetreMacros()
    local f = FenetreMacrosSuite()
    if not f then return false end
    if f:IsShown() then f:Hide() return true end
    if InCombatLockdown and InCombatLockdown() then return true end
    if Suite.panneauRaccourcis then Suite.panneauRaccourcis:Hide() end
    f:ClearAllPoints()
    local rond = Suite.boutonRaccourcis
    local ouverture = Reglages().raccourcisOuverture or "gauche"
    if rond and rond:IsShown() then
        if ouverture == "droite" then f:SetPoint("TOPLEFT", rond, "TOPRIGHT", 8, 0)
        elseif ouverture == "haut" then f:SetPoint("BOTTOMLEFT", rond, "TOPLEFT", 0, 8)
        elseif ouverture == "bas" then f:SetPoint("TOPLEFT", rond, "BOTTOMLEFT", 0, -8)
        else f:SetPoint("TOPRIGHT", rond, "TOPLEFT", -8, 0) end
    else
        f:SetPoint("CENTER")
    end
    f:SetClampedToScreen(true)
    f:Show()
    Suite.DessinerFenetreMacros()
    local manette = _G.C_GamePad and _G.C_GamePad.IsEnabled and select(2, pcall(_G.C_GamePad.IsEnabled)) == true
    if manette then Suite.Piloter(true, "CoreSuiteMacros") end
    return true
end

-- ---------------------------------------------------------------------------
-- MacroCore : une fenetre comme le suivi Mes fabrications. Pour l'instant,
-- seulement la rangee du haut (l'icone au clavier, comme un onglet du suivi)
-- et le filet dessous.
local ICONE_MACROCORE = Suite.ICONE_MACROCORE
local ALPHA_EN_COURSE = 0.25
local HAUT_ONGLETS = 38
local fenMC

local function MacroCore()
    if fenMC then return fenMC end
    local charte = NS.charte
    if not (charte and charte.Fenetre) then return nil end
    local cadre = charte.Fenetre("CoreSuiteMacroCore", 300, 100,
        { portrait = false, strate = "MEDIUM", sansPied = true })
    if cadre.titre then cadre.titre:SetText("MacroCore") end
    cadre.fermer:SetScript("OnClick", function() Suite.ActiverMacroCore(false) end)
    -- Ses reglages, en haut a gauche, comme les suivis : la petite roue.
    do
        local roue = CreateFrame("Button", nil, cadre)
        roue:SetSize(14, 14)
        roue:SetPoint("TOPLEFT", cadre, "TOPLEFT", 19, -5)
        local fermer = cadre.fermer or cadre.CloseButton
        roue:SetFrameLevel(math.max(cadre:GetFrameLevel() + 20, (fermer and fermer:GetFrameLevel() or 0) + 2))
        roue:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
        roue:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        roue:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Réglages de MacroCore", "MacroCore settings"), 1, 1, 1)
            GameTooltip:Show()
        end)
        roue:SetScript("OnLeave", function() GameTooltip:Hide() end)
        roue:SetScript("OnClick", function() Suite.OuvrirMacros() end)
        cadre.boutonReglages = roue
    end

    -- Place retenue.
    local r = Reglages()
    cadre:ClearAllPoints()
    if type(r.macroCorePlace) == "table" then
        cadre:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r.macroCorePlace[1], r.macroCorePlace[2])
    else
        cadre:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    cadre:SetScript("OnDragStart", function(self)
        if Suite.Libre and not Suite.Libre("CoreSuiteMacroCore") then return end
        self:StartMoving()
    end)
    cadre:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        if x and y then Reglages().macroCorePlace = { math.floor(x + 0.5), math.floor(y + 0.5) } end
    end)
    if Suite.Ancrable then pcall(Suite.Ancrable, "CoreSuiteMacroCore", cadre, "MacroCore") end

    -- L'icone au clavier : meme bouton que les onglets du suivi.
    -- Pose sur l'ecran (pas dans la fenetre) : il reste net quand la
    -- fenetre devient invisible, et suit sa place.
    local b = CreateFrame("Button", nil, UIParent)
    b:SetFrameStrata(cadre:GetFrameStrata())
    b:SetFrameLevel(cadre:GetFrameLevel() + 10)
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 2, 0)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(19, 19)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.image = b:CreateTexture(nil, "ARTWORK")
    b.image:SetPoint("CENTER")
    b.image:SetSize(16, 16)
    b.image:SetTexture(ICONE_MACROCORE)
    if b.image.SetMask then pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(41, 41)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("MacroCore", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() Suite.ActiverMacroCore(not cadre.active) end)
    b.infobulleDe = "CoreSuiteMacroCore"
    cadre.icone = b

    -- A droite de l'icone : les deux suivis. Un clic les montre ou les cache.
    cadre.suivis = {}
    for rang, v in ipairs({
        { "CraftCoreSuivi", "CraftCoreAPI", TR("Mes fabrications", "My crafts"), nil, "Interface\\Icons\\Trade_BlackSmithing",
          TR("Affiche ou cache le suivi Mes fabrications.", "Shows or hides the My crafts tracker.") },
        { "QuestCoreSuivi", "QuestCoreAPI", TR("Quêtes", "Quests"), "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon",
          TR("Affiche ou cache le suivi des quêtes.", "Shows or hides the quest tracker.") } }) do
        local s = CreateFrame("Button", nil, UIParent)
        s:SetFrameStrata(cadre:GetFrameStrata())
        s:SetFrameLevel(cadre:GetFrameLevel() + 10)
        s:SetSize(24, 24)
        -- Tout au bord droit, pour ne pas les confondre avec l'icone de MacroCore.
        s:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", -2 - (2 - rang) * (24 + 8), 0)
        s.fond = s:CreateTexture(nil, "BACKGROUND")
        s.fond:SetSize(19, 19)
        s.fond:SetPoint("CENTER")
        s.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        s.image = s:CreateTexture(nil, "ARTWORK")
        s.image:SetPoint("CENTER")
        s.image:SetSize(16, 16)
        if not (v[4] and s.image.SetAtlas and pcall(s.image.SetAtlas, s.image, v[4]) and s.image:GetAtlas()) then
            s.image:SetTexture(v[5])
        end
        if not v[4] and s.image.SetMask then pcall(s.image.SetMask, s.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        s.anneau = s:CreateTexture(nil, "OVERLAY")
        s.anneau:SetSize(41, 41)
        s.anneau:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
        s.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        s:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        s.nomSuivi, s.api, s.nom, s.desc = v[1], v[2], v[3], v[6]
        s.infobulleDe = "CoreSuiteMacroCore"
        s:SetAlpha(ALPHA_EN_COURSE)
        s:SetScript("OnClick", function(self)
            local a = _G[self.api]
            if a and a.BasculerSuivi then pcall(a.BasculerSuivi) end
        end)
        s:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            if Reglages().macroCoreSansInfobulle then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.nom, 1, 0.82, 0)
            GameTooltip:AddLine(self.desc, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function(self)
            self:SetAlpha(ALPHA_EN_COURSE)
            GameTooltip:Hide()
        end)
        s:Hide()
        table.insert(cadre.suivis, s)
    end

    local filet = cadre:CreateTexture(nil, "ARTWORK")
    filet:SetHeight(1)
    filet:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -HAUT_ONGLETS + 6)
    filet:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", 0, -HAUT_ONGLETS + 6)
    filet:SetColorTexture(0.8, 0.65, 0.35, 0.35)
    cadre.filet = filet

    -- Pilote : garde l'opacite d'activation ; B referme (rend la manette).
    cadre.piloteGarderAlpha = true
    cadre.piloteSurB = function() Suite.ActiverMacroCore(false) end
    cadre.elementsPilote = function()
        local t = {}
        for _, s in ipairs(cadre.suivis or {}) do table.insert(t, s) end
        for _, b in ipairs(cadre.pastilles or {}) do table.insert(t, b) end
        return t
    end
    -- La manette reprend sur la derniere pastille choisie, sinon la premiere.
    cadre.piloteDepart = function()
        local d = cadre.dernierePastille
        if d and d.e and d:IsShown() then return d end
        for _, b in ipairs(cadre.pastilles or {}) do if b.e and b:IsShown() then return b end end
    end
    fenMC = cadre
    Suite.ActiverMacroCore(false)
    return cadre
end

-- Inactive : la fenetre est invisible (et ne gene pas les clics), seul le
-- bouton se voit. Active : la fenetre apparait a l'opacite des suivis en
-- sous-brillance.
function Suite.ActiverMacroCore(oui)
    local f = fenMC
    if not f then return end
    if f.figee then return end
    f.active = oui and true or nil
    f:SetAlpha(oui and ALPHA_EN_COURSE or 0)
    f:EnableMouse(oui and true or false)
    if f.fermer then f.fermer:SetShown(oui and true or false) end
    -- Les pastilles ne se cliquent que fenetre active (hors combat : le jeu
    -- interdit de montrer ou cacher ces boutons pendant un combat).
    local combat = InCombatLockdown and InCombatLockdown()
    -- A chaque ouverture, la liste est refaite : au premier chargement, des
    -- add-ons de la suite s'inscrivent apres le premier remplissage (il
    -- manquait alors des pastilles).
    if oui and not combat and Suite.RemplirMacroCore then pcall(Suite.RemplirMacroCore) end
    if not combat then
        for _, b in ipairs(f.pastilles or {}) do b:SetShown(oui and b.e ~= nil) end
    end
    for _, sv in ipairs(f.suivis or {}) do sv:SetShown(oui and _G[sv.api] ~= nil) end
    -- Ouverte : la manette pilote MacroCore. Refermee : elle reprend son cours.
    local p = Suite.pilote
    if oui then
        if not combat then Suite.Piloter(true, "CoreSuiteMacroCore") end
    elseif p and p:IsShown() and p.nom == "CoreSuiteMacroCore" then
        Suite.Piloter(false)
    end
end

-- Sous le filet : une ligne par famille de raccourcis (manette, ouvrir,
-- guider, repondre, mes macros), avec seulement les raccourcis choisis.
-- Une famille sans raccourci choisi n'apparait pas. Un filet entre deux.
local PASTILLE, ECART_P, ECART_L = 24, 8, 8
function Suite.RemplirMacroCore()
    local f = fenMC
    if not f or (InCombatLockdown and InCombatLockdown()) then return end
    f.pastilles = f.pastilles or {}
    f.filets = f.filets or {}
    f.titres = f.titres or {}
    local nt = 0
    local parFamille = {}
    for _, e in ipairs(Entrees()) do
        parFamille[e.famille] = parFamille[e.famille] or {}
        table.insert(parFamille[e.famille], e)
    end
    local largeur = f.zone:GetWidth()
    if not largeur or largeur < 50 then largeur = 300 - 10 - 2 * ((NS.charte and NS.charte.MARGE) or 12) end
    local parLigne = math.max(1, math.floor((largeur - 2 + ECART_P) / (PASTILLE + ECART_P)))
    local n, nf = 0, 0
    local y = -HAUT_ONGLETS + 6
    local premiere = true
    for _, fam in ipairs(Suite.FAMILLES) do
        local liste = parFamille[fam.cle]
        if liste and #liste > 0 then
            if not premiere then
                -- Filet entre deux familles.
                y = y - ECART_L
                nf = nf + 1
                local t = f.filets[nf]
                if not t then
                    t = f:CreateTexture(nil, "ARTWORK")
                    t:SetHeight(1)
                    t:SetColorTexture(0.8, 0.65, 0.35, 0.35)
                    f.filets[nf] = t
                end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, y)
                t:SetPoint("TOPRIGHT", f.zone, "TOPRIGHT", 0, y)
                t:Show()
            end
            premiere = false
            -- Titre de la famille, comme un en-tete du suivi.
            y = y - 6
            nt = nt + 1
            local tt = f.titres[nt]
            if not tt then
                tt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                tt:SetTextColor(1, 0.82, 0)
                tt:SetJustifyH("LEFT")
                f.titres[nt] = tt
            end
            -- Meme police et meme taille que les en-tetes de groupe des suivis
            -- (Fabrications rapides, Projets) : taille du suivi des quetes + 3.
            do
                tt:SetFontObject("GameFontNormal")
                local fichier, _, drapeaux = tt:GetFont()
                local d = _G.QuestCoreDB
                local sv = type(d) == "table" and type(d.reglages) == "table" and type(d.reglages.general) == "table" and d.reglages.general.suivi
                local taille = tonumber(type(sv) == "table" and sv.taille) or 12
                if fichier then tt:SetFont(Suite.FichierPolice and Suite.FichierPolice(fichier) or fichier, taille + 3, drapeaux) end
            end
            tt:ClearAllPoints()
            tt:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 0, y - 2)
            tt:SetText(TR(fam.fr, fam.en))
            tt:Show()
            y = y - 24
            for i, e in ipairs(liste) do
                local col = (i - 1) % parLigne
                if i > 1 and col == 0 then y = y - PASTILLE - ECART_L end
                n = n + 1
                local b = f.pastilles[n]
                if not b then
                    -- Posee sur l'ecran (pas dans la fenetre) : la pastille
                    -- selectionnee passe a pleine opacite, les autres restent
                    -- a celle de la fenetre.
                    b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
                    b:SetFrameStrata(f:GetFrameStrata())
                    b:SetFrameLevel(f:GetFrameLevel() + 10)
                    b:SetAlpha(ALPHA_EN_COURSE)
                    b.infobulleDe = "CoreSuiteMacroCore"
                    b:RegisterForClicks("AnyUp", "AnyDown")
                    b:SetSize(PASTILLE, PASTILLE)
                    b.fond = b:CreateTexture(nil, "BACKGROUND")
                    b.fond:SetSize(19, 19)
                    b.fond:SetPoint("CENTER")
                    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
                    b.image = b:CreateTexture(nil, "ARTWORK")
                    b.image:SetPoint("CENTER")
                    b.image:SetSize(16, 16)
                    b.anneau = b:CreateTexture(nil, "OVERLAY")
                    b.anneau:SetSize(41, 41)
                    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
                    b:SetScript("OnEnter", function(self)
                        if not self.e then return end
                        self:SetAlpha(1)
                        f.dernierePastille = self
                        -- Infobulles : reglage de la suite (actives par defaut).
                        if Reglages().macroCoreSansInfobulle then return end
                        -- Toujours au meme endroit, contre la fenetre (voir
                        -- les infobulles fixes).
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.e.nom, 1, 0.82, 0)
                        local d = self.e.desc
                        if not d and (self.e.corps or self.e.texte) then
                            d = TR("Lance ta macro : ", "Runs your macro : ") .. (self.e.corps or self.e.texte)
                        end
                        if d then GameTooltip:AddLine(d, 1, 1, 1, true) end
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function(self)
                        self:SetAlpha(ALPHA_EN_COURSE)
                        GameTooltip:Hide()
                    end)
                    -- Clic souris : meme regle que la manette (la macro du
                    -- bouton lance l'action, on observe ce qui s'ouvre).
                    b:SetScript("PreClick", function(self)
                        Suite.AvantLancementMacroCore()
                        if self.e and Suite.FigerAvantMacroCore then Suite.FigerAvantMacroCore(self.e.famille) end
                    end)
                    b:SetScript("PostClick", function(self)
                        if self.e then Suite.ApresLancementMacroCore(self.e.famille) end
                    end)
                    f.pastilles[n] = b
                end
                b.e = e
                b:SetAttribute("type", "macro")
                if e.macro then b:SetAttribute("macrotext", nil) b:SetAttribute("macro", e.macro)
                else b:SetAttribute("macro", nil) b:SetAttribute("macrotext", e.texte) end
                b.image:SetTexture(e.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
                if b.image.SetMask and not b.masquee then
                    pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
                    b.masquee = true
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f.zone, "TOPLEFT", 2 + col * (PASTILLE + ECART_P), y)
                b:SetShown(f.active and true or false)
            end
            y = y - PASTILLE
        end
    end
    for i = n + 1, #f.pastilles do f.pastilles[i].e = nil f.pastilles[i]:Hide() end
    for i = nf + 1, #f.filets do f.filets[i]:Hide() end
    for i = nt + 1, #f.titres do f.titres[i]:Hide() end
    -- Hauteur : barre de titre, marges, contenu (jamais sous 100 : le cadre
    -- du jeu se deforme en dessous).
    local charte = NS.charte
    local marge = (charte and charte.MARGE) or 12
    local contenu = premiere and (HAUT_ONGLETS - 6) or (-y + ECART_L)
    f:SetHeight(math.max(100, 24 + marge + contenu + marge + 4))
end

-- Ce que MacroCore ouvre le remplace : tant que cette fenetre est ouverte,
-- MacroCore n'existe plus (ni bouton, ni commande). Elle revient quand
-- la fenetre se ferme.
-- Chaque fenetre est notee avec ce qu'elle montre : une meme fenetre peut
-- servir deux add-ons (CraftCore et StuffCore). Passer de l'un a l'autre
-- compte comme une nouvelle fenetre.
local function FenetresVisibles()
    local vues = {}
    local function Ajouter(c, cle)
        if c and c.IsShown and c:IsShown() then vues[c] = cle or true end
    end
    for cle, m in pairs(Suite.membres or {}) do
        if m.fenetre then local ok, c = pcall(m.fenetre) if ok then Ajouter(c, tostring(cle)) end end
    end
    for _, n in ipairs(SUIVIS) do Ajouter(_G[n]) end
    for _, n in ipairs(UISpecialFrames or {}) do Ajouter(_G[n]) end
    Ajouter(Suite.reglagesGeneraux)
    Ajouter(Suite.fenetreMacros)
    Ajouter(_G.SagaCoreMessages and _G.SagaCoreMessages.fenetre)
    Ajouter(_G.AuraCoreReglages)
    return vues
end
local avantLancement
function Suite.AvantLancementMacroCore() avantLancement = FenetresVisibles() end
local veille
-- Figee : MacroCore reste a l'ecran telle quelle, mais ne recoit plus rien
-- (ni souris, ni manette, ni macro).
local function Figer(f, oui)
    f.figee = oui and true or nil
    local combat = InCombatLockdown and InCombatLockdown()
    f:EnableMouse((not oui) and f.active and true or false)
    if f.fermer then f.fermer:EnableMouse(not oui) end
    if f.icone then f.icone:EnableMouse(not oui) end
    for _, sv in ipairs(f.suivis or {}) do sv:EnableMouse(not oui) end
    if not combat then
        for _, b in ipairs(f.pastilles or {}) do b:EnableMouse(not oui) end
    end
    if oui then
        local p = Suite.pilote
        if p and p:IsShown() and p.nom == "CoreSuiteMacroCore" then Suite.Piloter(false) end
        GameTooltip:Hide()
    end
end
local function Debloquer()
    local f = fenMC
    if not f then return end
    f.bloquants = nil
    f.blocPilote = nil
    f.avantLancement = nil
    if veille then veille:Hide() end
    Figer(f, false)
    -- Ouverte, elle reprend la manette.
    if f.active and not (InCombatLockdown and InCombatLockdown()) then Suite.Piloter(true, "CoreSuiteMacroCore") end
end
function Suite.ApresLancementMacroCore(famille)
    local f = fenMC
    if not f then return end
    local avant = avantLancement or {}
    avantLancement = nil
    local plusTard = _G.C_Timer and _G.C_Timer.After
    local function Regarder()
        local nouvelles = {}
        -- Prise de controle d'une fenetre (piloter un suivi) : MacroCore est
        -- figee tant que la manette pilote cette fenetre, et reprend la main
        -- des qu'on la libere (meme si la fenetre reste ouverte).
        local pl = Suite.pilote
        f.blocPilote = nil
        if pl and pl:IsShown() and pl.nom and pl.nom ~= "CoreSuiteMacroCore" then
            f.blocPilote = pl.nom
            table.insert(nouvelles, _G[pl.nom] or f)
        else
            for c, cle in pairs(FenetresVisibles()) do
                if c ~= f and avant[c] ~= cle then table.insert(nouvelles, c) end
            end
        end
        if #nouvelles == 0 then
            -- Rien ne s'est ouvert : MacroCore reprend ses commandes.
            if f.figee and not f.bloquants then Debloquer() end
            return
        end
        f.bloquants = nouvelles
        -- Ce qui etait ouvert avant le lancement : tout ce qui s'ouvre ensuite
        -- (un autre add-on par L3 / R3, par exemple) la garde figee.
        f.avantLancement = avant
        Figer(f, true)
        if not veille then
            veille = CreateFrame("Frame")
            local attente = 0
            veille:SetScript("OnUpdate", function(_, ecoule)
                attente = attente - (ecoule or 0)
                if attente > 0 then return end
                attente = 0.25
                local encore = false
                local fm = fenMC
                if fm and fm.blocPilote then
                    local pp = Suite.pilote
                    encore = pp and pp:IsShown() and pp.nom == fm.blocPilote or false
                else
                    for _, c in ipairs((fm and fm.bloquants) or {}) do if c:IsShown() then encore = true end end
                    -- Passee d'un add-on a l'autre : la nouvelle fenetre compte
                    -- aussi, MacroCore ne reprend pas la manette.
                    if not encore and fm then
                        local avantL = fm.avantLancement or {}
                        for c, cle in pairs(FenetresVisibles()) do
                            if c ~= fm and avantL[c] ~= cle then encore = true break end
                        end
                    end
                end
                if not encore then Debloquer() end
            end)
        end
        veille:Show()
    end
    if plusTard then plusTard(0.2, Regarder) else Regarder() end
end
-- Ouvrir ou piloter une fenetre : MacroCore se fige tout de suite (elle
-- rend la manette), le temps de voir ce qui s'ouvre.
local function FigerAvant(famille)
    if fenMC and (famille == "ouvrir" or famille == "manette") then Figer(fenMC, true) end
end
Suite.FigerAvantMacroCore = FigerAvant
function Suite.LancerDepuisMacroCore(r)
    Suite.AvantLancementMacroCore()
    FigerAvant(Suite.FamilleDe(r))
    Suite.Lancer(r)
    Suite.ApresLancementMacroCore(Suite.FamilleDe(r))
end

function Suite.BasculerMacroCore()
    local f = MacroCore()
    if not f then return false end
    -- Figee par une fenetre qu'elle a ouverte : aucune commande.
    if f.figee then return true end
    f:Show()
    Suite.ActiverMacroCore(not f.active)
    return true
end

-- ---------------------------------------------------------------------------
-- Suivis replies : un suivi cache (croix, macro, MacroCore) laisse a l'ecran
-- sa premiere icone, a sa place. Un clic dessus le rouvre.
-- ---------------------------------------------------------------------------

local OUVRIR_PAR_API = { CraftCoreSuivi = "CraftCoreAPI", QuestCoreSuivi = "QuestCoreAPI" }
local icones = {}

-- La premiere icone ronde de la ligne du haut (onglet affiche en premier).
local function PremiereIcone(f)
    local meilleur, mh, mg
    local function Voir(c, prof)
        if prof > 4 then return end
        for _, e in ipairs({ c:GetChildren() }) do
            if e:IsShown() and e.anneau and e.image and e.GetCenter then
                local x, y = e:GetCenter()
                if x and y and (not meilleur or y > mh + 3 or (math.abs(y - mh) <= 3 and x < mg)) then
                    meilleur, mh, mg = e, y, x
                end
            end
            Voir(e, prof + 1)
        end
    end
    Voir(f, 1)
    return meilleur
end

local function PlacesIcones()
    local r = Reglages()
    r.iconesSuivis = type(r.iconesSuivis) == "table" and r.iconesSuivis or {}
    return r.iconesSuivis
end

local function IconeDeSuivi(nom)
    local b = icones[nom]
    if b then return b end
    b = CreateFrame("Button", nil, UIParent)
    b:SetSize(24, 24)
    b:SetFrameStrata("MEDIUM")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(19, 19)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.image = b:CreateTexture(nil, "ARTWORK")
    b.image:SetPoint("CENTER")
    b.image:SetSize(16, 16)
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(41, 41)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:SetScript("OnClick", function()
        local a = _G[OUVRIR_PAR_API[nom]]
        if a and a.BasculerSuivi then pcall(a.BasculerSuivi) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.titre or nom, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    icones[nom] = b
    return b
end

local function HabillerIcone(b, info, nom)
    local atlasPose = false
    if info.atlas and info.atlas ~= "" and b.image.SetAtlas and pcall(b.image.SetAtlas, b.image, info.atlas)
        and (b.image:GetAtlas() or "") ~= "" then
        atlasPose = true
    end
    if not atlasPose then
        -- Repli : l'icone connue du suivi.
        local connue = nom == "QuestCoreSuivi" and "Interface\\GossipFrame\\AvailableQuestIcon" or "Interface\\Icons\\Trade_BlackSmithing"
        b.image:SetTexture(info.texture or connue)
    end
    -- Toujours en pleine couleur, comme l'onglet choisi, meme si l'onglet
    -- copie etait gris.
    b.image:SetDesaturated(false)
    b.image:SetVertexColor(1, 1, 1)
    b.image:SetAlpha(1)
    b.anneau:SetDesaturated(false)
    b:SetAlpha(1)
    if info.masque and b.image.SetMask and not b.masquee then
        pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        b.masquee = true
    end
    b.titre = info.titre
end

-- Le suivi se cache : on retient son icone et sa place, et on la montre.
local function SuiviCache(nom)
    local f = _G[nom]
    if not f then return end
    local e = PremiereIcone(f)
    local info = PlacesIcones()[nom]
    if e then
        local x, y = e:GetCenter()
        local k = (e:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        -- GetAtlas rend "" (et non nil) pour une image sans atlas.
        local atlas = e.image.GetAtlas and e.image:GetAtlas()
        if atlas == "" then atlas = nil end
        local tex = e.image:GetTexture()
        -- Une image arrondie par un masque se renomme "maskNNNN" : illisible.
        if tex == "" or tex == 0 or (type(tex) == "string" and tex:find("^mask")) then tex = nil end
        info = { x = x * k, y = y * k, atlas = atlas, texture = (not atlas) and tex or nil,
            -- Les icones d'objet sont arrondies ; les atlas du jeu le sont deja.
            masque = not atlas,
            titre = (f.titre and f.titre.GetText and f.titre:GetText()) or e.nom }
        -- Image illisible : celle, connue, de l'onglet copie.
        if not info.atlas and not info.texture then
            if nom == "QuestCoreSuivi" then
                local route = f.vuesRoute and f.vuesRoute.divers
                if route and route:IsShown() then
                    info.texture, info.masque = "Interface\\Icons\\INV_Misc_Map_01", true
                else
                    info.atlas, info.texture, info.masque = "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon", false
                end
            else
                info.texture, info.masque = "Interface\\Icons\\Trade_BlackSmithing", true
            end
        end
        PlacesIcones()[nom] = info
    end
    -- Ancienne image retenue illisible ("maskNNNN") : on l'oublie.
    if info and type(info.texture) == "string" and info.texture:find("^mask") then info.texture = nil end
    if not info then return end
    local b = IconeDeSuivi(nom)
    HabillerIcone(b, info, nom)
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", info.x, info.y)
    b:Show()
end

local function SuiviMontre(nom)
    if icones[nom] then icones[nom]:Hide() end
end

local function BrancherSuivis()
    for nom in pairs(OUVRIR_PAR_API) do
        local f = _G[nom]
        if f and not f.suiteIconeBranchee then
            f.suiteIconeBranchee = true
            f:HookScript("OnHide", function() pcall(SuiviCache, nom) end)
            f:HookScript("OnShow", function() pcall(SuiviMontre, nom) end)
            if f:IsShown() then SuiviMontre(nom) else pcall(SuiviCache, nom) end
        end
    end
end
Suite.BrancherIconesSuivis = BrancherSuivis

-- ---------------------------------------------------------------------------
-- Infobulles fixes : dans MacroCore, Mes fabrications et Quetes, l'infobulle
-- est toujours au meme endroit, contre le haut de la fenetre, a droite ou a
-- gauche (reglable). Par defaut : MacroCore et Mes fabrications a droite,
-- Quetes a gauche.
-- ---------------------------------------------------------------------------

local FENETRES_INFOBULLE = { CoreSuiteMacroCore = "droite", CraftCoreSuivi = "droite", QuestCoreSuivi = "gauche",
    GloryCoreFenetre = "droite" }
Suite.FENETRES_INFOBULLE = FENETRES_INFOBULLE

function Suite.CoteInfobulle(nom)
    local r = Reglages()
    local t = type(r.coteInfobulles) == "table" and r.coteInfobulles or {}
    return t[nom] or FENETRES_INFOBULLE[nom]
end
function Suite.PoserCoteInfobulle(nom, cote)
    local r = Reglages()
    r.coteInfobulles = type(r.coteInfobulles) == "table" and r.coteInfobulles or {}
    r.coteInfobulles[nom] = cote
end

local function FenetreDInfobulle(o)
    local n = 0
    while o and n < 20 do
        if o.infobulleDe then return o.infobulleDe end
        local nom = o.GetName and o:GetName()
        if nom and FENETRES_INFOBULLE[nom] then return nom end
        o = o.GetParent and o:GetParent()
        n = n + 1
    end
end

if not Suite.crochetInfobulles and hooksecurefunc then
    Suite.crochetInfobulles = true
    local enCours = false
    hooksecurefunc(GameTooltip, "SetOwner", function(tt, owner)
        if enCours or not owner then return end
        local S = _G.CoreSuite
        local ok, nom = pcall(FenetreDInfobulle, owner)
        if not ok or not nom then return end
        local f = _G[nom]
        if not f then return end
        enCours = true
        pcall(tt.SetOwner, tt, owner, "ANCHOR_NONE")
        enCours = false
        tt:ClearAllPoints()
        local cote = (S and S.CoteInfobulle and S.CoteInfobulle(nom)) or FENETRES_INFOBULLE[nom]
        -- Collee a la fenetre, sans espace, partout pareil.
        if cote == "gauche" then
            tt:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
        else
            tt:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
        end
    end)
end

-- Plus de bouton rond : seule la fenetre MacroCore.
function Suite.PlacerBoutonRaccourcis()
    if Suite.boutonRaccourcis then Suite.boutonRaccourcis:Hide() end
    if not Suite.Prive() then
        if fenMC then
            Suite.ActiverMacroCore(false)
            fenMC:Hide() fenMC.icone:Hide()
            for _, sv in ipairs(fenMC.suivis or {}) do sv:Hide() end
        end
        return
    end
    local f = MacroCore()
    if f then
        f:Show()
        f.icone:Show()
        pcall(Suite.RemplirMacroCore)
        if f.figee then Figer(f, true) end
    end
    pcall(BrancherSuivis)
end

do
    local depart = CreateFrame("Frame")
    depart:RegisterEvent("PLAYER_LOGIN")
    depart:SetScript("OnEvent", function()
        if _G.CoreSuite ~= Suite then return end
        pcall(Suite.PlacerBoutonRaccourcis)
        -- Le suivi des quetes arrive un peu apres : on se recale contre lui.
        if _G.C_Timer then _G.C_Timer.After(4, function()
            pcall(Suite.PlacerBoutonRaccourcis)
            pcall(Suite.AideDesSuivis)
        end) end
    end)
end


-- Sous chaque fenetre de suivi : comment la piloter a la manette.
function Suite.AideDesSuivis()
    for _, nom in ipairs(SUIVIS) do
        local cadre = _G[nom]
        if cadre and not cadre.aidePilote then
            cadre.aidePilote = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            cadre:HookScript("OnShow", function() pcall(Suite.AideDesSuivis) end)
            cadre:HookScript("OnSizeChanged", function() pcall(Suite.AideDesSuivis) end)
        end
        if cadre and cadre.aidePilote then
            local t = cadre.aidePilote
            local manette = _G.C_GamePad and _G.C_GamePad.IsEnabled and select(2, pcall(_G.C_GamePad.IsEnabled)) == true
            t:SetText(TR("Manette : touche « Piloter » (Raccourcis, Add-ons)", "Gamepad : \"Drive\" key (Key Bindings, AddOns)"))
            t:ClearAllPoints()
            -- Colle au bas de l'ecran : l'aide passe au-dessus de la fenetre.
            if (cadre:GetBottom() or 100) < 24 then t:SetPoint("BOTTOM", cadre, "TOP", 0, 2)
            else t:SetPoint("TOP", cadre, "BOTTOM", 0, -2) end
            t:SetShown(false)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Fenetre a pages, comme celles des add-ons de la suite : menu a gauche,
-- parchemin a droite, pied avec Fermer, onglets de la suite sur le bord.
-- Sert aux Macros et a AuraCore.
--
-- o = { nom, cle, titre = fonction, icone, pages = { { cle, libelle = fonction,
--       icone, construire = fonction(page, O), rendre = fonction(page, O) } } }
-- Manette : LB / RB pages, croix haut / bas element suivant, A, B fermer,
-- L3 / R3 onglet voisin de la colonne.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Controles modernes, communs aux fenetres et aux options du jeu
-- ---------------------------------------------------------------------------
-- Choix : une liste deroulante, dessinee ici (la liste du jeu provoquait
-- des erreurs et grisait ses textes).
-- Valeur : le curseur du jeu (glissiere avec ses fleches), sinon la valeur
-- suivie de - et +, colles.

local function TxtC(t) if type(t) == "function" then local ok, v = pcall(t) return ok and v or "" end return t or "" end

-- La liste ouverte, commune a toutes les listes deroulantes de la suite.
-- Manette sur une liste ouverte : elle prend la croix (haut / bas), A
-- choisit l'option allumee, B referme. Commun a toutes les listes de la suite.
local function ManetteDeListe(l, capteur)
    function l.Allumer(i)
        local visibles = {}
        for _, it in ipairs(l.items) do if it:IsShown() then table.insert(visibles, it) end end
        if #visibles == 0 then return end
        i = math.max(1, math.min(#visibles, i or 1))
        l.index = i
        for k, it in ipairs(visibles) do
            if k == i then it:LockHighlight() else it:UnlockHighlight() end
        end
        l.visibles = visibles
    end
    if l.EnableGamePadButton then
        l:SetScript("OnGamePadButtonDown", function(_, bouton)
            if bouton == "PADDUP" then l.Allumer((l.index or 1) - 1)
            elseif bouton == "PADDDOWN" then l.Allumer((l.index or 1) + 1)
            elseif bouton == "PAD1" then
                local it = l.visibles and l.visibles[l.index or 1]
                if it then it:Click("LeftButton") end
            elseif bouton == "PAD2" or bouton == "PADBACK" then l:Hide()
            end
        end)
    end
    l:SetScript("OnShow", function()
        capteur:Show()
        if l.EnableGamePadButton then pcall(l.EnableGamePadButton, l, true) end
    end)
    l:SetScript("OnHide", function()
        capteur:Hide()
        if l.EnableGamePadButton then pcall(l.EnableGamePadButton, l, false) end
    end)
end

local function ListeCommune()
    if Suite.liste then return Suite.liste end
    local capteur = CreateFrame("Button", nil, UIParent)
    capteur:SetAllPoints(UIParent)
    capteur:SetFrameStrata("FULLSCREEN_DIALOG")
    capteur:SetFrameLevel(200)
    capteur:RegisterForClicks("AnyUp")
    capteur:Hide()
    local l = CreateFrame("Frame", "CoreSuiteListe", UIParent)
    l:SetFrameStrata("FULLSCREEN_DIALOG")
    l:SetFrameLevel(210)
    l:EnableMouse(true)
    l:Hide()
    l.fond = l:CreateTexture(nil, "BACKGROUND")
    l.fond:SetAllPoints()
    l.fond:SetColorTexture(0.06, 0.05, 0.04, 0.96)
    for _, cote in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = l:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.55, 0.45, 0.25, 1)
        t:SetPoint(cote[1])
        t:SetPoint(cote[2])
        if cote[3] then t:SetHeight(1) else t:SetWidth(1) end
    end
    l.items = {}
    capteur:SetScript("OnClick", function() l:Hide() end)
    ManetteDeListe(l, capteur)
    table.insert(UISpecialFrames, "CoreSuiteListe")
    Suite.liste = l
    return l
end

-- Liste deroulante, dessinee ici : le texte du choix en place, une fleche ;
-- au clic, la liste des options en blanc, celle en place en or et cochee.
local function ListeDeroulante(f, Options, lire, Choisir)
    local d = CreateFrame("Button", nil, f)
    d:SetSize(180, 24)
    d:SetPoint("RIGHT", 0, 0)
    d.fond = d:CreateTexture(nil, "BACKGROUND")
    d.fond:SetAllPoints()
    d.fond:SetColorTexture(0.06, 0.05, 0.04, 0.88)
    d.bords = {}
    for _, cote in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = d:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.55, 0.45, 0.25, 1)
        t:SetPoint(cote[1])
        t:SetPoint(cote[2])
        if cote[3] then t:SetHeight(1) else t:SetWidth(1) end
        table.insert(d.bords, t)
    end
    d:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    d:GetHighlightTexture():SetAlpha(0.35)
    d.texte = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.texte:SetPoint("LEFT", 10, 0)
    d.texte:SetPoint("RIGHT", -24, 0)
    d.texte:SetJustifyH("LEFT")
    d.texte:SetWordWrap(false)
    d.fleche = d:CreateTexture(nil, "OVERLAY")
    d.fleche:SetSize(14, 14)
    d.fleche:SetPoint("RIGHT", -6, 0)
    d.fleche:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    if d.fleche.SetRotation then pcall(d.fleche.SetRotation, d.fleche, -math.pi / 2) end
    local function Ouvrir()
        local l = ListeCommune()
        if l:IsShown() and l.proprietaire == d then l:Hide() return end
        l.proprietaire = d
        local opts = Options()
        local ok, actuel = pcall(lire)
        for i, o in ipairs(opts) do
            local it = l.items[i]
            if not it then
                it = CreateFrame("Button", nil, l)
                it:SetHeight(22)
                it:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                it.coche = it:CreateTexture(nil, "OVERLAY")
                it.coche:SetSize(16, 16)
                it.coche:SetPoint("LEFT", 6, 0)
                it.coche:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                it.texte = it:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                it.texte:SetPoint("LEFT", 26, 0)
                it.texte:SetPoint("RIGHT", -8, 0)
                it.texte:SetJustifyH("LEFT")
                it.texte:SetWordWrap(false)
                it:SetScript("OnClick", function(self) local fct = self.choisir l:Hide() if fct then fct() end end)
                l.items[i] = it
            end
            local choisi = ok and o[1] == actuel
            it.texte:SetText(TxtC(o[2]))
            if choisi then it.texte:SetTextColor(1, 0.82, 0) else it.texte:SetTextColor(1, 1, 1) end
            it.coche:SetShown(choisi)
            local valeur = o[1]
            it.choisir = function() Choisir(valeur) end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", l, "TOPLEFT", 1, -4 - (i - 1) * 22)
            it:SetPoint("RIGHT", l, "RIGHT", -1, 0)
            it:Show()
            if f.focus and not it.dansFocus then it.dansFocus = true f.focus(it) end
        end
        for i = #opts + 1, #l.items do l.items[i]:Hide() end
        l:SetSize(d:GetWidth(), #opts * 22 + 8)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
        l:Show()
        -- La croix part de l'option en place.
        local rangActuel = 1
        for i, o in ipairs(opts) do if ok and o[1] == actuel then rangActuel = i end end
        l.Allumer(rangActuel)
    end
    d:SetScript("OnClick", Ouvrir)
    d:HookScript("OnHide", function() local l = Suite.liste if l and l.proprietaire == d then l:Hide() end end)
    return d
end

-- Grise ou rend actif une liste deroulante de la suite.
function Suite.ActiverListe(f, actif)
    if not f then return end
    local li = f.liste or f
    local b = li.bouton
    if b and b.SetEnabled then b:SetEnabled(actif and true or false) end
    f:SetAlpha(actif and 1 or 0.45)
end

function Suite.Segments(parent, options, lire, poser, apres)
    -- Les choix passent tous par la liste deroulante validee.
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 26)
    local li
    function f.Rendre()
        if not li then
            li = Suite.ListeDeroulante(f, options, lire, poser, apres, f.focus)
            li:SetPoint("RIGHT", 0, 0)
            f.liste = li
        end
        li.Rendre()
    end
    return f
end


-- Liste deroulante a l'apparence de celle du jeu : le bouton du jeu
-- (WowStyle1) pour le dessin seulement, et notre propre liste, au fond
-- d'infobulle, textes blancs. Le menu du jeu n'est jamais ouvert.
local function FenetreDeListe()
    if Suite.liste2 then return Suite.liste2 end
    local capteur = CreateFrame("Button", nil, UIParent)
    capteur:SetAllPoints(UIParent)
    capteur:SetFrameStrata("TOOLTIP")
    capteur:SetFrameLevel(5)
    capteur:RegisterForClicks("AnyUp")
    capteur:Hide()
    local okB, l = pcall(CreateFrame, "Frame", "CoreSuiteListe2", UIParent, "BackdropTemplate")
    if not okB or not l then l = CreateFrame("Frame", "CoreSuiteListe2", UIParent) end
    -- Au-dessus des fenetres de la suite (FULLSCREEN_DIALOG, remontees au clic).
    l:SetFrameStrata("TOOLTIP")
    l:SetFrameLevel(20)
    l:EnableMouse(true)
    l:Hide()
    if l.SetBackdrop then
        l:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        l:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
        l:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    else
        local t = l:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetColorTexture(0.04, 0.04, 0.05, 0.96)
    end
    l.items = {}
    capteur:SetScript("OnClick", function() l:Hide() end)
    ManetteDeListe(l, capteur)
    table.insert(UISpecialFrames, "CoreSuiteListe2")
    Suite.liste2 = l
    return l
end

function Suite.ListeDeroulante(parent, options, lire, poser, apres, focus)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 26)
    local function Options() return type(options) == "function" and options() or options end
    local function Choisir(v) pcall(poser, v) if apres then pcall(apres) end f.Rendre() end
    local okD, d = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if not (okD and d) then
        d = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        d:SetHeight(22)
    end
    d:SetPoint("RIGHT", 0, 0)
    d:SetWidth(200)
    -- Rien du menu du jeu : nos propres clics.
    pcall(d.SetScript, d, "OnMouseDown", nil)
    pcall(d.SetScript, d, "OnMouseUp", nil)
    d.libelle = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.libelle:SetPoint("LEFT", 12, 0)
    d.libelle:SetPoint("RIGHT", -28, 0)
    d.libelle:SetJustifyH("LEFT")
    d.libelle:SetWordWrap(false)
    if d.Text and d.Text.Hide then d.Text:Hide() end
    -- Le texte est celui du bouton : l'encre du parchemin n'y touche pas.
    if d.SetFontString then pcall(d.SetFontString, d, d.libelle) end
    local function Ouvrir()
        local l = FenetreDeListe()
        if l:IsShown() and l.proprietaire == d then l:Hide() return end
        l.proprietaire = d
        local opts = Options()
        local ok, actuel = pcall(lire)
        for i, o in ipairs(opts) do
            local it = l.items[i]
            if not it then
                it = CreateFrame("Button", nil, l)
                it:SetHeight(22)
                it:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                it.coche = it:CreateTexture(nil, "OVERLAY")
                it.coche:SetSize(16, 16)
                it.coche:SetPoint("LEFT", 8, 0)
                it.coche:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                it.texte = it:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                it.texte:SetPoint("LEFT", 28, 0)
                it.texte:SetPoint("RIGHT", -8, 0)
                it.texte:SetJustifyH("LEFT")
                it:SetScript("OnClick", function(self) local fct = self.choisir l:Hide() if fct then fct() end end)
                l.items[i] = it
            end
            local choisi = ok and o[1] == actuel
            it.texte:SetText(TxtC(o[2]))
            if choisi then it.texte:SetTextColor(1, 0.82, 0) else it.texte:SetTextColor(1, 1, 1) end
            it.coche:SetShown(choisi)
            local valeur = o[1]
            it.choisir = function() Choisir(valeur) end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", l, "TOPLEFT", 4, -6 - (i - 1) * 22)
            it:SetPoint("RIGHT", l, "RIGHT", -4, 0)
            it:Show()
            if focus and not it.dansFocus then it.dansFocus = true focus(it) end
        end
        for i = #opts + 1, #l.items do l.items[i]:Hide() end
        l:SetSize(d:GetWidth(), #opts * 22 + 12)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
        l:Show()
        -- La croix part de l'option en place.
        local rangActuel = 1
        for i, o in ipairs(opts) do if ok and o[1] == actuel then rangActuel = i end end
        l.Allumer(rangActuel)
    end
    f.bouton = d
    d:SetScript("OnClick", Ouvrir)
    d:HookScript("OnHide", function() local l = Suite.liste2 if l and l.proprietaire == d then l:Hide() end end)
    if focus then focus(d) end
    function f.Rendre()
        local ok, actuel = pcall(lire)
        for _, o in ipairs(Options()) do
            if ok and o[1] == actuel then d.libelle:SetText(TxtC(o[2])) end
        end
        d.libelle:SetTextColor(1, 1, 1)
    end
    return f
end

function Suite.Curseur(parent, mini, maxi, pas, lire, poser, format, boutons, grandPas)
    -- La valeur entre deux fleches, comme les pages du grimoire du jeu. Avec
    -- grandPas : une fleche double de chaque cote, qui avance d'autant.
    local f = CreateFrame("Frame", nil, parent)
    -- Meme largeur que les listes : les bords des controles s'alignent.
    f:SetSize(200, 26)
    pas = pas or 1
    -- Quantites limitees a 999 : les fleches restent pres du chiffre.
    maxi = math.min(maxi or 999, 999)
    local function Arrondir(v) return mini + math.floor((v - mini) / pas + 0.5) * pas end
    local function Ecrire(v) return format and format(v) or tostring(v) end
    local function Fleche(sens, saut)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(26, 26)
        local nom = sens < 0 and "PrevPage" or "NextPage"
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        if grandPas and grandPas ~= pas and b.GetNormalTexture then
            -- Avec une fleche double : les quatre boutons sont dessines pareil,
            -- le cadre du bouton du grimoire et une ou deux pointes dorees,
            -- toutes dans le meme carre.
            -- Les fleches du jeu (celles des pages de l'interface moderne,
            -- a defaut celles de la saisie de monnaie), toutes de la meme
            -- taille : une pour avancer de 1, deux qui se chevauchent pour
            -- avancer d'un grand pas.
            local fond = b:CreateTexture(nil, "OVERLAY", nil, 0)
            fond:SetPoint("TOPLEFT", 6, -6)
            fond:SetPoint("BOTTOMRIGHT", -6, 6)
            fond:SetColorTexture(0.11, 0.1, 0.09, 1)
            local atlas = sens > 0 and "common-icon-forwardarrow" or "common-icon-backarrow"
            local fichier = sens > 0 and "Interface\\MoneyFrame\\Arrow-Right-Up" or "Interface\\MoneyFrame\\Arrow-Left-Up"
            b.pointes = {}
            local n = (saut ~= pas) and 2 or 1
            for k = 1, n do
                local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
                if not (t.SetAtlas and pcall(t.SetAtlas, t, atlas) and t:GetAtlas()) then t:SetTexture(fichier) end
                t:SetSize(12, 12)
                t.dx = (n == 2) and ((k == 1) and -3 or 3) or 0
                t:SetPoint("CENTER", t.dx, 0)
                table.insert(b.pointes, t)
            end
            hooksecurefunc(b, "SetEnabled", function(self, oui)
                for _, t in ipairs(self.pointes) do
                    t:SetDesaturated(not oui)
                    t:SetAlpha(oui and 1 or 0.45)
                end
            end)
            b:HookScript("OnMouseDown", function(self)
                if not self:IsEnabled() then return end
                for _, t in ipairs(self.pointes) do t:SetPoint("CENTER", t.dx + 1, -1) end
            end)
            b:HookScript("OnMouseUp", function(self)
                for _, t in ipairs(self.pointes) do t:SetPoint("CENTER", t.dx, 0) end
            end)
        end
        b:SetScript("OnClick", function()
            local okL, v = pcall(lire)
            v = (tonumber(okL and v) or mini) + sens * saut
            if saut == pas then v = Arrondir(v) end
            pcall(poser, math.max(mini, math.min(maxi, v)))
            f.Rendre()
        end)
        return b
    end
    local moins, plus = Fleche(-1, pas), Fleche(1, pas)
    local moinsVite, plusVite
    if grandPas and grandPas ~= pas then
        moinsVite, plusVite = Fleche(-1, grandPas), Fleche(1, grandPas)
        moinsVite:SetPoint("LEFT", 0, 0)
        moins:SetPoint("LEFT", moinsVite, "RIGHT", 0, 0)
        plusVite:SetPoint("RIGHT", 0, 0)
        plus:SetPoint("RIGHT", plusVite, "LEFT", 0, 0)
    else
        moins:SetPoint("LEFT", 0, 0)
        plus:SetPoint("RIGHT", 0, 0)
    end
    local valeur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valeur:SetPoint("LEFT", moins, "RIGHT", 0, 0)
    valeur:SetPoint("RIGHT", plus, "LEFT", 0, 0)
    valeur:SetJustifyH("CENTER")
    -- Meme place partout entre les fleches (assez pour 100 %, sur une seule
    -- ligne) : toutes les fleches des reglages restent alignees.
    valeur:SetWordWrap(false)
    local place = 56
    f:SetWidth((moinsVite and 4 or 2) * 26 + place)
    f.boutonsPM = { moins, plus, moinsVite, plusVite }
    function f.Rendre()
        local okL, v = pcall(lire)
        v = tonumber(okL and v)
        valeur:SetText(v and Ecrire(v) or "")
        -- Encre sur le parchemin, blanc sur fond sombre.
        if f.surParchemin and f.surParchemin() then valeur:SetTextColor(0.24, 0.14, 0.06) else valeur:SetTextColor(1, 1, 1) end
        local basOk = v == nil or v > mini + pas / 2
        local hautOk = v == nil or v < maxi - pas / 2
        moins:SetEnabled(basOk)
        plus:SetEnabled(hautOk)
        if moinsVite then moinsVite:SetEnabled(basOk) plusVite:SetEnabled(hautOk) end
    end
    return f
end


-- Memes dimensions que les fenetres des add-ons (1060 x 740, menu de 170).
local LARGEUR_P, HAUTEUR_P, MENU_P, ECART_P = 1060, 740, 170, 14

function Suite.FenetreAPages(o)
    local charte = NS.charte
    if not (charte and charte.Fenetre) then return nil end
    local w = { o = o, page = o.pages[1].cle }
    Suite.fenetresAPages = Suite.fenetresAPages or {}
    table.insert(Suite.fenetresAPages, w)
    local cadre = charte.Fenetre(o.nom, LARGEUR_P, HAUTEUR_P, {})
    cadre:SetPoint("CENTER")
    cadre:Hide()
    table.insert(UISpecialFrames, o.nom)
    w.cadre = cadre
    local portrait = cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait)
    if portrait then portrait:SetTexture(o.icone) end
    -- La bande des personnages en haut, la meme dans toutes les fenetres de
    -- la suite (o.sansBande : la fenetre pose la sienne).
    if not o.sansBande then
        local bande = CreateFrame("Frame", nil, cadre)
        bande:SetPoint("LEFT", cadre.entete or cadre, "LEFT", 0, 0)
        bande:SetPoint("RIGHT", cadre.entete or cadre, "RIGHT", 0, 0)
        bande:SetHeight(34)
        w.bande = bande
    end
    -- Precedent / suivant, tout a droite de l'en-tete (o.historique : la
    -- fenetre tient l'historique de ce qu'on a regarde). Les fleches de page
    -- du grimoire, comme les valeurs entre fleches.
    if o.historique then
        local function Fleche(sens)
            local b = CreateFrame("Button", nil, cadre)
            b:SetSize(26, 26)
            local nom = sens < 0 and "PrevPage" or "NextPage"
            b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Up")
            b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Down")
            b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. nom .. "-Disabled")
            b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            b:SetScript("OnClick", function()
                if sens < 0 then pcall(o.historique.Reculer) else pcall(o.historique.Avancer) end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local ok, texte = pcall(o.historique.Libelle, sens)
                GameTooltip:SetText((sens < 0 and TR("Précédent", "Back") or TR("Suivant", "Forward"))
                    .. ((ok and texte) and (" : " .. texte) or ""), 1, 0.82, 0)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return b
        end
        w.suivant = Fleche(1)
        w.suivant:SetPoint("RIGHT", cadre.entete or cadre, "RIGHT", -4, 0)
        w.precedent = Fleche(-1)
        w.precedent:SetPoint("RIGHT", w.suivant, "LEFT", 0, 0)
        if w.bande then
            w.bande:SetPoint("RIGHT", w.precedent, "LEFT", -12, 0)
        end
    end

    local menu = CreateFrame("Frame", nil, cadre)
    menu:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    menu:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    menu:SetWidth(MENU_P)
    local trait = cadre:CreateTexture(nil, "ARTWORK")
    -- Plus de trait visible entre le menu et le contenu : il ne sert que de repere.
    trait:SetColorTexture(0, 0, 0, 0)
    trait:SetWidth(1)
    trait:SetPoint("TOPLEFT", menu, "TOPRIGHT", ECART_P, 0)
    trait:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", ECART_P, 0)
    -- Comme les autres fenetres : le logo de la suite (Alliance ou Horde)
    -- a cheval sur le trait, et le fond du journal sous le menu.
    cadre.menu, cadre.trait = menu, trait
    local fondMenu = cadre.fond:CreateTexture(nil, "BACKGROUND", nil, 5)
    fondMenu:SetPoint("TOPLEFT", cadre.fond, "TOPLEFT", 3, -3)
    fondMenu:SetPoint("BOTTOMRIGHT", trait, "BOTTOMLEFT", -1, -(charte.MARGE - 3))
    fondMenu:Hide()
    cadre.fondMenu = fondMenu

    -- Les rubriques du menu : le contenu sous le nom de l'add-on, puis ses
    -- reglages a part, en dernier (sauf rubriques donnees par l'add-on).
    do
        local REGLAGES = { reglages = true, suite = true, parametres = true, options = true }
        -- Les reglages d'un add-on : partout le meme nom (Parametres) et la
        -- meme icone.
        for _, page in ipairs(o.pages) do
            if REGLAGES[page.cle] then
                page.libelle = function() return TX("Parameters") end
                page.icone = Suite.ICONE_PARAMETRES
            end
        end
        local donnees = false
        for _, page in ipairs(o.pages) do if page.section then donnees = true end end
        if not donnees and #o.pages > 1 then
            local contenu, reglages = {}, {}
            for _, page in ipairs(o.pages) do table.insert(REGLAGES[page.cle] and reglages or contenu, page) end
            if #contenu > 0 and #reglages > 0 then
                -- Comme les piliers : le contenu, puis une rubrique au nom
                -- de l'add-on avec ses Parametres, en dernier.
                local nom = o.cle
                contenu[1].section = function() return TX("Contents") end
                reglages[1].section = nom
                o.pages = {}
                for _, page in ipairs(contenu) do table.insert(o.pages, page) end
                for _, page in ipairs(reglages) do table.insert(o.pages, page) end
                w.page = o.pages[1].cle
            end
        end
    end
    w.boutonsMenu = {}
    local yMenu = 0
    for rang, page in ipairs(o.pages) do
        -- Un titre par categorie (page.section : texte ou fonction), comme
        -- dans toute la suite.
        if page.section then
            if rang > 1 then yMenu = yMenu + 8 end
            local t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            Suite.TitreDeMenu(t)
            t:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(yMenu + 2))
            t:SetText(type(page.section) == "function" and page.section() or tostring(page.section))
            yMenu = yMenu + Suite.HAUTEUR_TITRE_MENU
        end
        local b = Suite.LigneDeMenu(menu, page.icone)
        local avecSections = o.pages[1] and o.pages[1].section ~= nil
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", avecSections and Suite.RETRAIT_MENU or 0, -yMenu)
        yMenu = yMenu + Suite.PAS_LIGNE_MENU
        b:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        local cle = page.cle
        b:SetScript("OnClick", function() w.page = cle w.Rendre() end)
        w.boutonsMenu[cle] = b
    end

    local okD, defilement = pcall(CreateFrame, "ScrollFrame", nil, cadre, "ScrollFrameTemplate")
    if not okD or not defilement then defilement = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate") end
    defilement:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_P, 0)
    defilement:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", -18, 0)
    local LARGEUR_C = LARGEUR_P - MENU_P - 2 * charte.MARGE - 60
    local contenu = CreateFrame("Frame", nil, defilement)
    contenu:SetSize(LARGEUR_C, 1)
    defilement:SetScrollChild(contenu)
    w.contenu, w.defilement = contenu, defilement
    charte.Parchemin(cadre, { "TOPLEFT", trait, "TOPRIGHT", 2, charte.MARGE - 4 },
        { "BOTTOMRIGHT", cadre.fond, "BOTTOMRIGHT", -4, 4 }, cadre.fond)
    local fermer = charte.BoutonDePied(cadre, TX("Close"), 110)
    fermer:SetScript("OnClick", function() cadre:Hide() end)

    -- Outils de mise en page, pour chaque page : une colonne de libelles a
    -- gauche, une colonne de boutons a droite, des sections espacees.
    local X_DROITE = 300
    local function Outils(page)
        local O = {}
        O.LARGEUR = LARGEUR_C
        O.X = X_DROITE
        local function Focus(objet) table.insert(page.focus, objet) return objet end
        function O.Placer(objet, hauteur, ecart)
            page.y = page.y + (ecart or 0)
            objet:ClearAllPoints()
            objet:SetPoint("TOPLEFT", page.cadre, "TOPLEFT", 0, -page.y)
            page.y = page.y + hauteur
            return objet
        end
        -- Comme les parametres de QuestCore et CraftCore : le titre de
        -- rubrique (police des titres de la suite), son filet 22 points plus
        -- bas, 34 points en tout, 8 de plus entre deux rubriques.
        function O.Section()
            local t = page.cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            t:SetJustifyH("LEFT")
            local filet = page.cadre:CreateTexture(nil, "ARTWORK")
            O.Placer(t, 22, page.y > 0 and 8 or 0)
            filet:ClearAllPoints()
            filet:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -22)
            filet:SetSize(LARGEUR_C - 10, 1)
            page.y = page.y + 12
            table.insert(page.sections, { t, filet })
            return t
        end
        function O.Texte(hauteur, police)
            local t = page.cadre:CreateFontString(nil, "OVERLAY", police or "GameFontHighlightSmall")
            t:SetWidth(LARGEUR_C - 20)
            t:SetJustifyH("LEFT")
            t:SetWordWrap(true)
            return O.Placer(t, hauteur or 18, 6)
        end
        -- Explication sous un reglage : plus petite, en retrait.
        function O.Detail(hauteur)
            -- Police des textes explicatifs : la charte les met a 40 %.
            local t = page.cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            t:SetWidth(LARGEUR_C - 60)
            t:SetJustifyH("LEFT")
            t:SetWordWrap(true)
            O.Placer(t, hauteur or 28, 2)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", page.cadre, "TOPLEFT", 16, -(page.y - (hauteur or 28)))
            return t
        end
        -- Une ligne de reglage : libelle en petit, en retrait de 16 (comme
        -- les parametres de QuestCore), controle cale a droite ; 30 points.
        O.RETRAIT = 16
        function O.Rangee(hauteur, police)
            local r = CreateFrame("Frame", nil, page.cadre)
            r:SetSize(LARGEUR_C - 10, hauteur or 24)
            r.nom = r:CreateFontString(nil, "OVERLAY", police or "GameFontHighlightSmall")
            r.nom:SetPoint("LEFT", O.RETRAIT, 0)
            r.nom:SetJustifyH("LEFT")
            return O.Placer(r, hauteur or 24, 6)
        end
        function O.Bouton(parent, largeur, auClic)
            local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            b:SetSize(largeur, 22)
            -- Largeur a la mesure du texte, avec la meme marge de chaque cote.
            local poser = b.SetText
            b.SetText = function(self, texte)
                poser(self, texte)
                local l = self.GetTextWidth and self:GetTextWidth() or 0
                self:SetWidth(math.max(30, math.floor(l + 28)))
            end
            b:SetScript("OnClick", function(self) auClic(self) w.Rendre() end)
            return Focus(b)
        end
        function O.Case(parent, auClic)
            local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            c:SetSize(22, 22)
            c:SetScript("OnClick", function(self) auClic(self:GetChecked()) w.Rendre() end)
            return Focus(c)
        end
        function O.Saisie(parent, largeur, auValider)
            local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            e:SetSize(largeur, 20)
            e:SetAutoFocus(false)
            local function Garder(self) auValider(self:GetText()) end
            e:SetScript("OnEnterPressed", function(self) Garder(self) self:ClearFocus() w.Rendre() end)
            e:SetScript("OnEditFocusLost", function(self) Garder(self) end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() w.Rendre() end)
            return Focus(e)
        end
        -- Moins, valeur, plus : cales a droite, les memes ecarts partout.
        function O.PlusMoins(r, moins, plus)
            plus:SetSize(30, 22)
            moins:SetSize(30, 22)
            plus:ClearAllPoints()
            plus:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            moins:ClearAllPoints()
            moins:SetPoint("RIGHT", plus, "LEFT", -4, 0)
            r.valeurPM = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.valeurPM:SetWidth(60)
            r.valeurPM:SetJustifyH("RIGHT")
            r.valeurPM:SetPoint("RIGHT", moins, "LEFT", -10, 0)
            return r.valeurPM
        end
        -- Controles cales au bord droit (O.COLONNE reste pour les anciens appels).
        O.COLONNE = LARGEUR_C - 10 - 230
        -- Choix et valeur modernes, dans la colonne des controles.
        function O.Segments(r, options, lire, poser, apres)
            local sg = Suite.Segments(r, options, lire, poser, function() if apres then apres() end w.Rendre() end)
            sg.focus = Focus
            sg:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            table.insert(page.controles, sg)
            return sg
        end
        -- Liste deroulante a l'apparence du jeu.
        function O.Liste(r, options, lire, poser, apres)
            local li = Suite.ListeDeroulante(r, options, lire, poser, function() if apres then apres() end w.Rendre() end, Focus)
            li:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            table.insert(page.controles, li)
            return li
        end
        function O.Curseur(r, mini, maxi, pas, lire, poser, format, boutons, grandPas)
            local c = Suite.Curseur(r, mini, maxi, pas, lire, poser, format, boutons, grandPas)
            c.surParchemin = function() return charte.Fond and charte.Fond() == "parchemin" end
            c:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            for _, b in ipairs(c.boutonsPM or {}) do Focus(b) end
            if c.glissiere then
                if c.glissiere.Back then Focus(c.glissiere.Back) end
                if c.glissiere.Forward then Focus(c.glissiere.Forward) end
            end
            table.insert(page.controles, c)
            return c
        end
        function O.Icone(parent, taille)
            local t = parent:CreateTexture(nil, "ARTWORK")
            t:SetSize(taille or 18, taille or 18)
            return t
        end
        return O
    end

    for _, page in ipairs(o.pages) do
        page.cadre = CreateFrame("Frame", nil, contenu)
        page.cadre:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, 0)
        page.cadre:SetSize(LARGEUR_C, 1)
        page.cadre:Hide()
        page.focus, page.y, page.sections, page.controles = {}, 0, {}, {}
        page.O = Outils(page)
        page.construire(page, page.O)
        page.hauteur = page.y
    end

    local function PageCourante()
        for _, page in ipairs(o.pages) do if page.cle == w.page then return page end end
        return o.pages[1]
    end
    local function Focusables(page)
        local liste = {}
        for _, f in ipairs(page.focus) do
            if f:IsVisible() and (not f.IsEnabled or f:IsEnabled() or f:GetObjectType() == "EditBox") then table.insert(liste, f) end
        end
        return liste
    end

    function w.Rendre()
        if not cadre:IsShown() then return end
        if o.historique then pcall(o.historique.Noter) end
        if not fondMenu:IsShown() then pcall(charte.FondDuJournal, fondMenu) end
        if w.bande and not o.sansBande then
            pcall(function()
                local choisi = o.persoChoisi and o.persoChoisi()
                if not choisi then
                    for _, p in ipairs(Suite.ListePersos()) do if p.moi then choisi = p.cle end end
                end
                w.bande.ordre = Suite.BandePersos(w.bande, { choisi = choisi, auClic = o.choisirPerso and function(cle)
                    o.choisirPerso(cle)
                    w.Rendre()
                end or nil })
            end)
        end
        local page = PageCourante()
        if cadre.titre then cadre.titre:SetText(o.titre()) end
        for cle, b in pairs(w.boutonsMenu) do
            local choisi = cle == w.page
            for _, p in ipairs(o.pages) do if p.cle == cle and b.texte then b.texte:SetText(p.libelle()) end end
            Suite.MarquerLigneDeMenu(b, choisi)
        end
        for _, p in ipairs(o.pages) do p.cadre:SetShown(p == page) end
        local ok, souci = pcall(page.rendre, page, page.O)
        if not ok and Suite.Prive() then print("|cffffd100SagaCore|r " .. tostring(souci)) end
        contenu:SetHeight(math.max(page.hauteur + 10, 1))
        page.cadre:SetHeight(math.max(page.hauteur + 10, 1))
        local parchemin = charte.Fond and charte.Fond() == "parchemin"
        if cadre.parchemin then cadre.parchemin.Montrer(parchemin) end
        if charte.Encrer then pcall(charte.Encrer, contenu, parchemin) end
        for _, s in ipairs(page.sections) do
            if charte.TitreDeSection then pcall(charte.TitreDeSection, s[1], s[2]) end
        end
        -- Les controles se dessinent apres l'encre du parchemin : leurs
        -- couleurs (listes, panneaux sombres) restent les leurs.
        for _, c in ipairs(page.controles or {}) do pcall(c.Rendre) end
        if o.historique then
            local okR, r = pcall(o.historique.PeutReculer)
            local okA, a = pcall(o.historique.PeutAvancer)
            w.precedent:SetEnabled(okR and r == true)
            w.suivant:SetEnabled(okA and a == true)
        end
        if w.ApresRendu then w.ApresRendu() end
    end

    -- Manette, comme les fenetres des add-ons : Vue entre dans la page (un
    -- liseré d'or entoure la zone centrale), la croix y choisit un element
    -- (sa surbrillance du jeu), A appuie, X clic droit, B ressort. Hors de la
    -- page : LB / RB changent de page, la croix fait defiler, B ferme.
    local enZone, focus = false, nil
    local okL, lisere = pcall(CreateFrame, "Frame", nil, cadre, "BackdropTemplate")
    lisere = okL and lisere or CreateFrame("Frame", nil, cadre)
    if lisere.SetBackdrop then
        lisere:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
        lisere:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    lisere:EnableMouse(false)
    lisere:SetPoint("TOPLEFT", defilement, "TOPLEFT", -6, 6)
    lisere:SetPoint("BOTTOMRIGHT", defilement, "BOTTOMRIGHT", 6, -6)
    lisere:SetFrameLevel(defilement:GetFrameLevel() + 20)
    lisere:Hide()

    local function Atteignable(f)
        if not f or not f:IsVisible() then return false end
        if f:IsObjectType("EditBox") then return true end
        if not f:IsObjectType("Button") then return false end
        if f.IsEnabled and not f:IsEnabled() then return false end
        return f:GetScript("OnClick") ~= nil
    end
    local function Parcourir(c, liste, prof)
        if not c or prof > 8 then return end
        for _, e in ipairs({ c:GetChildren() }) do
            if e:IsVisible() then
                if Atteignable(e) then table.insert(liste, e) end
                Parcourir(e, liste, prof + 1)
            end
        end
    end
    local function Elements()
        local liste = {}
        -- Les fleches precedent / suivant d'abord : croix haut y mene.
        for _, f in ipairs({ w.precedent, w.suivant }) do
            if f and f:IsVisible() and f:IsEnabled() then table.insert(liste, f) end
        end
        Parcourir(contenu, liste, 1)
        return liste
    end
    local function Relacher()
        if focus then
            if focus.UnlockHighlight then focus:UnlockHighlight() end
            local q = focus:GetScript("OnLeave")
            if q then pcall(q, focus) end
        end
        focus = nil
    end
    local function Boite(e)
        local l, b, wd, h = e:GetLeft(), e:GetBottom(), e:GetWidth(), e:GetHeight()
        if not (l and b and wd and h) then return nil end
        return { l = l, r = l + wd, x = l + wd / 2, y = b + h / 2, h = h }
    end
    local function Defiler(pas)
        local maxi = (defilement.GetVerticalScrollRange and defilement:GetVerticalScrollRange()) or 0
        defilement:SetVerticalScroll(math.max(0, math.min(maxi, (defilement:GetVerticalScroll() or 0) + pas * 80)))
    end
    local function Visible(e)
        local haut = (contenu:GetTop() or 0) - (e:GetTop() or 0)
        local vue, actuel = defilement:GetHeight() or 400, defilement:GetVerticalScroll() or 0
        local maxi = (defilement.GetVerticalScrollRange and defilement:GetVerticalScrollRange()) or 0
        if haut < actuel then defilement:SetVerticalScroll(math.max(0, haut - 10))
        elseif haut + 30 > actuel + vue then defilement:SetVerticalScroll(math.min(maxi, haut + 30 - vue + 10)) end
    end
    local function Choisir(e)
        Relacher()
        focus = e
        if not e then return end
        if e.LockHighlight then e:LockHighlight() end
        Visible(e)
        local survol = e:GetScript("OnEnter")
        if survol then pcall(survol, e) end
    end
    local function Deplacer(dx, dy)
        local liste = Elements()
        if #liste == 0 then Relacher() return end
        local depart = focus and focus:IsVisible() and Boite(focus)
        if not depart then
            table.sort(liste, function(a, b)
                local ha, hb = a:GetTop() or 0, b:GetTop() or 0
                if math.abs(ha - hb) > 4 then return ha > hb end
                return (a:GetLeft() or 0) < (b:GetLeft() or 0)
            end)
            Choisir(liste[1])
            return
        end
        local meilleur, scoreMin
        for _, e in ipairs(liste) do
            local b = e ~= focus and Boite(e)
            if b then
                local score
                if dy ~= 0 then
                    local avance = (dy > 0) and (depart.y - b.y) or (b.y - depart.y)
                    if avance > 4 then score = avance * 4 + math.abs(b.x - depart.x) * 0.5 end
                else
                    local memeLigne = math.abs(b.y - depart.y) < math.max(depart.h, b.h) / 2 + 2
                    local avance = (dx > 0) and (b.x - depart.x) or (depart.x - b.x)
                    if memeLigne and avance > 2 then score = avance end
                end
                if score and (not scoreMin or score < scoreMin) then meilleur, scoreMin = e, score end
            end
        end
        if meilleur then Choisir(meilleur) elseif dy ~= 0 then Defiler(dy) end
    end
    local function Entrer(oui)
        enZone = oui
        Relacher()
        if oui then Deplacer(0, 1) end
        if w.ApresRendu then w.ApresRendu() end
    end

    -- Glyphes LB / RB sur le menu, barre des touches sous la fenetre.
    local function Glyphe(t) return Suite.GlyphePad and Suite.GlyphePad(t) or t end
    local premier, dernier = w.boutonsMenu[o.pages[1].cle], w.boutonsMenu[o.pages[#o.pages].cle]
    for _, paire in ipairs({ { premier, "PADLSHOULDER" }, { dernier, "PADRSHOULDER" } }) do
        local b = paire[1]
        b.glyphe = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.glyphe:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        b.touche = paire[2]
    end
    local okB, barre = pcall(CreateFrame, "Frame", nil, cadre, "TooltipBackdropTemplate")
    barre = okB and barre or CreateFrame("Frame", nil, cadre)
    barre:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 10, 2)
    barre:SetHeight(38)
    barre:SetFrameLevel(cadre:GetFrameLevel() + 10)
    barre.texte = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    barre.texte:SetPoint("LEFT", barre, "LEFT", 12, 0)
    function w.ApresRendu()
        local pad = ManetteActive()
        -- LB / RB : dits dans la barre du bas, plus sur les lignes du menu.
        for _, b in ipairs({ premier, dernier }) do
            if b.glyphe then b.glyphe:Hide() end
        end
        if not pad then barre:Hide() lisere:Hide() return end
        local esp = "      "
        if enZone then
            barre.texte:SetText(Glyphe("PADDUP") .. " " .. Glyphe("PADDDOWN") .. " " .. Glyphe("PADDLEFT") .. " " .. Glyphe("PADDRIGHT") .. "  " .. TR("Choisir", "Choose") .. esp
                .. Glyphe("PAD1") .. "  " .. TR("Valider", "Select") .. esp
                .. Glyphe("PADBACK") .. "  " .. TR("Sortir de la page", "Leave the page") .. esp
                .. Glyphe("PAD2") .. "  " .. TR("Retour", "Back"))
        else
            barre.texte:SetText(Glyphe("PADLSHOULDER") .. " " .. Glyphe("PADRSHOULDER") .. "  " .. TR("Pages", "Pages") .. esp
                .. Glyphe("PADBACK") .. "  " .. TR("Naviguer dans la page", "Navigate the page") .. esp
                .. Glyphe("PADDUP") .. " " .. Glyphe("PADDDOWN") .. "  " .. TR("Défiler", "Scroll") .. esp
                .. Glyphe("PADLSTICK") .. " " .. Glyphe("PADRSTICK") .. "  " .. TR("Add-ons", "Add-ons") .. esp
                .. Glyphe("PAD2") .. "  " .. TX("Close"))
        end
        barre:SetWidth((barre.texte:GetStringWidth() or 400) + 24)
        barre:Show()
        lisere:SetShown(enZone)
        if enZone and focus and focus:IsVisible() and focus.LockHighlight then focus:LockHighlight() end
    end

    if cadre.EnableGamePadButton and pcall(cadre.EnableGamePadButton, cadre, true) then
        cadre:SetScript("OnGamePadButtonDown", function(_, bouton)
            local saisie = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
            if saisie then
                if bouton == "PAD2" then saisie:ClearFocus() end
                return
            end
            if Suite.ManetteBas then
                local okS, pris = pcall(Suite.ManetteBas, o.cle, bouton)
                if okS and pris then return end
            end
            if bouton == "PADBACK" then Entrer(not enZone) return end
            -- Hors de la page : l'add-on peut prendre une touche (croix
            -- gauche / droite : personnage precedent / suivant).
            if not enZone and o.manette then
                local okM, pris = pcall(o.manette, bouton)
                if okM and pris then return end
            end
            if enZone then
                if bouton == "PAD2" then Entrer(false) return end
                if bouton == "PADDUP" then Deplacer(0, -1) return end
                if bouton == "PADDDOWN" then Deplacer(0, 1) return end
                if bouton == "PADDLEFT" then Deplacer(-1, 0) return end
                if bouton == "PADDRIGHT" then Deplacer(1, 0) return end
                if bouton == "PAD1" or bouton == "PAD3" then
                    local f = focus
                    if f and f:IsVisible() then
                        if f:IsObjectType("EditBox") then f:SetFocus()
                        else pcall(f.Click, f, bouton == "PAD1" and "LeftButton" or "RightButton") end
                    end
                    return
                end
            end
            if bouton == "PADLSHOULDER" or bouton == "PADRSHOULDER" then
                local page = PageCourante()
                local rang = 1
                for i, p in ipairs(o.pages) do if p == page then rang = i end end
                rang = math.max(1, math.min(#o.pages, rang + (bouton == "PADRSHOULDER" and 1 or -1)))
                Entrer(false)
                w.page = o.pages[rang].cle
                defilement:SetVerticalScroll(0)
                w.Rendre()
            elseif (bouton == "PADLTRIGGER" or bouton == "PADRTRIGGER") and Suite.EstComplement(o.cle) then
                -- LT / RT : le complement precedent / suivant (onglets de droite).
                local liste = Suite.Complements()
                local rang = 1
                for i, c in ipairs(liste) do if c.cle == o.cle then rang = i end end
                local cible = liste[math.max(1, math.min(#liste, rang + (bouton == "PADRTRIGGER" and 1 or -1)))]
                if cible and cible.cle ~= o.cle then Suite.OuvrirComplement(cible.cle, cadre) end
            elseif bouton == "PADDUP" then Defiler(-1)
            elseif bouton == "PADDDOWN" then Defiler(1)
            elseif bouton == "PAD2" then cadre:Hide() end
        end)
    end

    cadre:SetScript("OnShow", function() w.Rendre() end)
    cadre:HookScript("OnHide", function() Entrer(false) end)
    pcall(Suite.Entete, cadre, o.cle)
    -- L'aide de la suite commence par la page ouverte.
    cadre.suitePage = function()
        local page = PageCourante()
        local ok, libelle = pcall(page.libelle)
        return page.cle, ok and libelle or nil
    end
    Suite.Inscrire(o.cle, { ouvrir = function() cadre:Show() end, fenetre = function() return cadre end })
    return w
end

-- ---------------------------------------------------------------------------
-- La fenetre Macros
-- ---------------------------------------------------------------------------

-- Macros propres a chaque personnage : relevees a la connexion, pour les
-- montrer depuis les autres personnages (et les reprendre dans la suite).
local function ReleverMacrosDuPerso()
    if not (_G.GetNumMacros and _G.GetMacroInfo) then return end
    local r = Reglages()
    r.macrosDesPersos = type(r.macrosDesPersos) == "table" and r.macrosDesPersos or {}
    local _, perso = _G.GetNumMacros()
    local liste = {}
    for i = 1, perso or 0 do
        local nom, icone, corps = _G.GetMacroInfo((_G.MAX_ACCOUNT_MACROS or 120) + i)
        if nom then table.insert(liste, { nom = nom, icone = icone, corps = corps }) end
    end
    r.macrosDesPersos[ClePersoSuite()] = liste
end

local function IconeDe(icone)
    if type(icone) == "number" then return icone end
    if type(icone) == "string" and icone ~= "" then
        if icone:find("\\") then return icone end
        return "Interface\\Icons\\" .. icone
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
Suite.IconeDe = IconeDe

local fenetreM
local function FenetreMacrosPages()
    if fenetreM then return fenetreM end
    local edition, choixJeu
    local MAX_PERSO, MAX_AUTRES, MAX_JEU = 24, 30, 40
    fenetreM = Suite.FenetreAPages({
        nom = "CoreSuiteMacrosPages", cle = "Macros", icone = Suite.ICONE_MACROCORE,
        titre = function() return TR("Macros", "Macros") end,
        pages = {
            { cle = "panneau", icone = "Interface\\Icons\\INV_Misc_Book_11",
              libelle = function() return TR("Le panneau", "The panel") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Texte(36)
                  page.rRond = O.Rangee()
                  local function Maj() Suite.PlacerBoutonRaccourcis() Suite.RafraichirRaccourcis() end
                  page.bReplacer = O.Bouton(page.rRond, 100, function()
                      local r = Reglages() r.raccourcisX, r.raccourcisY = nil, nil Maj()
                  end)
                  page.bReplacer:SetPoint("RIGHT", page.rRond, "RIGHT", -10, 0)
                  page.cRond = O.Case(page.rRond, function(oui) Reglages().raccourcisCache = (not oui) or nil Maj() end)
                  page.cRond:SetPoint("RIGHT", page.bReplacer, "LEFT", -16, 0)
                  -- Infobulles des raccourcis de MacroCore (actives par defaut).
                  page.rInfo = O.Rangee()
                  page.cInfo = O.Case(page.rInfo, function(oui) Reglages().macroCoreSansInfobulle = (not oui) or nil end)
                  page.cInfo:SetPoint("RIGHT", page.rInfo, "RIGHT", -10, 0)
                  -- Cote des infobulles, par fenetre.
                  page.rCotes = {}
                  for _, nom in ipairs({ "CoreSuiteMacroCore", "CraftCoreSuivi", "QuestCoreSuivi" }) do
                      local rg = O.Rangee()
                      rg.cle = nom
                      O.Liste(rg, function() return { { "gauche", TR("À gauche", "On the left") }, { "droite", TR("À droite", "On the right") } } end,
                          function() return Suite.CoteInfobulle(nom) end, function(v) Suite.PoserCoteInfobulle(nom, v) end)
                      table.insert(page.rCotes, rg)
                  end
                  page.rOuv = O.Rangee()
                  page.sOuv = O.Segments(page.rOuv, function() return {
                      { "gauche", TR("Gauche", "Left") }, { "droite", TR("Droite", "Right") },
                      { "haut", TR("Haut", "Up") }, { "bas", TR("Bas", "Down") } } end,
                      function() return Reglages().raccourcisOuverture or "gauche" end,
                      function(v) Reglages().raccourcisOuverture = v Maj() end)
                  page.rForme = O.Rangee()
                  page.sForme = O.Segments(page.rForme, function() return { { true, TR("Rondes", "Round") }, { false, TR("Carrées", "Square") } } end,
                      function() return Reglages().raccourcisRonds == true end,
                      function(v) Reglages().raccourcisRonds = v or nil Maj() end)
                  page.rParLigne = O.Rangee()
                  O.Curseur(page.rParLigne, 1, 12, 1, function() return Reglages().raccourcisParLigne or 6 end,
                      function(v) Reglages().raccourcisParLigne = v Maj() end)
                  page.rLignes = O.Rangee()
                  O.Curseur(page.rLignes, 1, 6, 1, function() return Reglages().raccourcisLignes or 3 end,
                      function(v) Reglages().raccourcisLignes = v Maj() end)
                  page.t2 = O.Section()
                  page.manette = O.Texte(54)
              end,
              rendre = function(page)
                  local r = Reglages()
                  local OUV = { gauche = TR("Vers la gauche", "To the left"), droite = TR("Vers la droite", "To the right"),
                      haut = TR("Vers le haut", "Upwards"), bas = TR("Vers le bas", "Downwards") }
                  page.t1:SetText(TR("Le panneau des raccourcis", "The shortcut panel"))
                  page.intro:SetText(TR("Un petit bouton à l'écran ouvre le panneau : vos raccourcis et vos macros, en icônes, lancés d'un clic. Faites glisser le bouton où vous voulez.",
                      "A small button on screen opens the panel : your shortcuts and macros as icons, launched with one click. Drag the button wherever you like."))
                  page.rRond.nom:SetText(TR("Bouton à l'écran", "Button on screen"))
                  page.cRond:SetChecked(not r.raccourcisCache)
                  page.rInfo.nom:SetText(TR("Infobulles des raccourcis", "Shortcut tooltips"))
                  page.cInfo:SetChecked(not r.macroCoreSansInfobulle)
                  local NOMS = { CoreSuiteMacroCore = TR("Infobulles de MacroCore", "MacroCore tooltips"),
                      CraftCoreSuivi = TR("Infobulles de Mes fabrications", "My crafts tooltips"),
                      QuestCoreSuivi = TR("Infobulles des quêtes", "Quest tooltips") }
                  for _, rg in ipairs(page.rCotes or {}) do rg.nom:SetText(NOMS[rg.cle]) end
                  page.bReplacer:SetText(TR("Replacer", "Reset"))
                  page.rOuv.nom:SetText(TR("Les icônes s'ouvrent", "Icons open"))
                  page.rForme.nom:SetText(TR("Forme des icônes", "Icon shape"))
                  page.rParLigne.nom:SetText(TR("Icônes par ligne", "Icons per row"))
                  page.rLignes.nom:SetText(TR("Lignes au maximum", "Rows at most"))
                  page.t2:SetText(TR("À la manette", "With a gamepad"))
                  page.manette:SetText(TR("Une seule macro ouvre et ferme le panneau : |cffffd100/sagacore raccourcis|r (dans la liste : « SC Panneau des... »). Ouvert, la croix choisit une icône, A la lance, B referme.",
                      "One macro opens and closes the panel : |cffffd100/sagacore raccourcis|r. Once open, the D-pad picks an icon, A launches it, B closes."))
              end },

            { cle = "suite", icone = "Interface\\Icons\\INV_Misc_Book_11",
              libelle = function() return TR("Macros de la suite", "Suite macros") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Texte(36)
                  page.rTout = O.Rangee()
                  page.bTout = O.Bouton(page.rTout, 200, function()
                      for _, r in ipairs(Suite.RACCOURCIS) do if Dispo(r) then Suite.CreerMacro(r) end end
                  end)
                  page.bTout:SetPoint("LEFT", page.rTout, "LEFT", O.RETRAIT, 0)
                  page.bDecocher = O.Bouton(page.rTout, 140, function()
                      Suite.ToutDecocher()
                      Suite.RafraichirRaccourcis()
                      for _, w in ipairs(Suite.fenetresAPages or {}) do
                          if w.cadre and w.cadre:IsShown() and w.Rendre then pcall(w.Rendre) end
                      end
                  end)
                  page.bDecocher:SetPoint("LEFT", page.bTout, "RIGHT", 8, 0)
                  page.bCocher = O.Bouton(page.rTout, 140, function()
                      Suite.ToutCocher()
                      Suite.RafraichirRaccourcis()
                      for _, w in ipairs(Suite.fenetresAPages or {}) do
                          if w.cadre and w.cadre:IsShown() and w.Rendre then pcall(w.Rendre) end
                      end
                  end)
                  page.bCocher:SetPoint("LEFT", page.bDecocher, "RIGHT", 8, 0)
                  page.lignes = {}
                  for i = 1, #Suite.RACCOURCIS + #Suite.FAMILLES do
                      local l = O.Rangee(24)
                      l.case = O.Case(l, function(oui) if l.r then Suite.PoserRaccourciActif("r:" .. l.r.cle, oui) Suite.RafraichirRaccourcis() end end)
                      l.case:SetPoint("LEFT", l, "LEFT", O.RETRAIT - 3, 0)
                      l.icone = O.Icone(l)
                      l.icone:SetPoint("LEFT", l.case, "RIGHT", 4, 0)
                      l.nom:ClearAllPoints()
                      l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                      l.commande = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                      l.commande:SetPoint("LEFT", l, "LEFT", O.X - 40, 0)
                      -- Un seul bouton : Creer, ou Supprimer une fois la macro creee.
                      l.creer = O.Bouton(l, 110, function()
                          if not l.r then return end
                          if Suite.MacroExiste(l.r) then Suite.SupprimerMacro(l.r) else Suite.CreerMacro(l.r) end
                      end)
                      l.creer:SetPoint("RIGHT", l, "RIGHT", -10, 0)
                      l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                      l.etat:SetPoint("RIGHT", l.creer, "LEFT", -8, 0)
                      page.lignes[i] = l
                  end
              end,
              rendre = function(page)
                  page.t1:SetText(TR("Les raccourcis de la suite", "The suite's shortcuts"))
                  page.intro:SetText(TR("La case met le raccourci dans le panneau de ce personnage. « Créer » en fait aussi une macro du jeu, nommée en 3 lettres (PFa, PQu...) avec l'icône du raccourci : elle se trouve dans la fenêtre Macros du jeu (/macro), onglet Général, d'où on la fait glisser sur une barre.",
                      "The box puts the shortcut in this character's panel. \"Create\" also makes it a game macro, with a 3-letter name (PFa, PQu...) and the shortcut's icon : find it in the game's Macros window (/macro), General tab, and drag it onto a bar."))
                  page.bTout:SetText(TR("Créer toutes les macros", "Create all macros"))
                  page.bDecocher:SetText(TR("Tout décocher", "Uncheck all"))
                  page.bCocher:SetText(TR("Tout cocher", "Check all"))
                  local rang = 0
                  for _, l in ipairs(page.lignes) do l:Hide() end
                  -- Par famille : un titre, puis ses raccourcis.
                  for _, fam in ipairs(Suite.FAMILLES) do
                      local membres = {}
                      for _, r in ipairs(Suite.RACCOURCIS) do
                          if Dispo(r) and Suite.FamilleDe(r) == fam.cle then table.insert(membres, r) end
                      end
                      if #membres > 0 then
                          rang = rang + 1
                          local t = page.lignes[rang]
                          t.r = nil
                          t.case:Hide() t.icone:Hide() t.commande:Hide() t.creer:Hide() t.etat:Hide()
                          t.nom:ClearAllPoints()
                          t.nom:SetPoint("LEFT", t, "LEFT", 0, 0)
                          t.nom:SetFontObject("GameFontNormal")
                          t.nom:SetText(TR(fam.fr, fam.en))
                          t:Show()
                          for _, r in ipairs(membres) do
                              rang = rang + 1
                              local l = page.lignes[rang]
                              l.r = r
                              l.case:Show() l.icone:Show() l.commande:Show()
                              l.nom:ClearAllPoints()
                              l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                              l.nom:SetFontObject("GameFontHighlightSmall")
                              l.icone:SetTexture("Interface\\Icons\\" .. r.icone)
                              l.nom:SetText(Suite.NomRaccourci(r))
                              l.commande:SetText("/sagacore " .. r.cle)
                              l.case:SetChecked(Suite.RaccourciActif("r:" .. r.cle))
                              l.case:SetShown(r.cle ~= "raccourcis")
                              local existe = Suite.MacroExiste(r)
                              l.creer:SetText(existe and TR("Supprimer", "Delete") or TR("Créer", "Create"))
                              l.creer:Show()
                              l.etat:SetText(existe and ("|cff4fd16a" .. TR("Macro créée", "Macro created") .. "|r") or "")
                              l.etat:SetShown(existe)
                              l:Show()
                          end
                      end
                  end
              end },

            { cle = "miennes", icone = "Interface\\Icons\\INV_Misc_Note_01",
              libelle = function() return TR("Mes macros", "My macros") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Texte(54)
                  -- Dans le gestionnaire.
                  page.lignes = {}
                  for i = 1, MAX_PERSO do
                      local l = O.Rangee(24)
                      l.case = O.Case(l, function(oui) if l.m then Suite.PoserRaccourciActif(IdPerso(l.m), oui) Suite.RafraichirRaccourcis() end end)
                      l.case:SetPoint("LEFT", l, "LEFT", O.RETRAIT - 3, 0)
                      l.icone = O.Icone(l)
                      l.icone:SetPoint("LEFT", l.case, "RIGHT", 4, 0)
                      l.nom:ClearAllPoints()
                      l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                      l.genre = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                      l.genre:SetPoint("LEFT", l, "LEFT", O.X - 40, 0)
                      -- Supprimer : la macro quitte la suite, et la macro du jeu qui
                      -- va avec est supprimee aussi.
                      l.retirer = O.Bouton(l, 90, function()
                          local liste = Suite.MacrosPerso()
                          local m = l.m
                          if m and not m.texte and m.nom and _G.GetMacroIndexByName and _G.DeleteMacro
                              and not (InCombatLockdown and InCombatLockdown()) then
                              local index = _G.GetMacroIndexByName(m.nom)
                              if index and index > 0 then pcall(_G.DeleteMacro, index) end
                          end
                          for k, mm in ipairs(liste) do if mm == m then table.remove(liste, k) break end end
                          if edition == l.m then edition = nil end
                          Suite.RafraichirRaccourcis()
                      end)
                      l.retirer:SetPoint("RIGHT", l, "RIGHT", -10, 0)
                      l.modifier = O.Bouton(l, 90, function() edition = (edition ~= l.m) and l.m or nil end)
                      l.modifier:SetPoint("RIGHT", l.retirer, "LEFT", -6, 0)
                      page.lignes[i] = l
                  end
                  page.vide = O.Texte(18)
                  -- Ecrire une macro ici.
                  page.t2 = O.Section()
                  page.rNouvelle = O.Rangee()
                  page.bNouvelle = O.Bouton(page.rNouvelle, 200, function()
                      local m = { nom = TR("Ma macro", "My macro"), icone = "INV_Misc_QuestionMark", texte = "" }
                      IdPerso(m)
                      table.insert(Suite.MacrosPerso(), m)
                      edition = m
                  end)
                  page.bNouvelle:SetPoint("RIGHT", page.rNouvelle, "RIGHT", -10, 0)
                  page.rNom = O.Rangee()
                  page.eNom = O.Saisie(page.rNom, 220, function(t) if edition and t ~= "" then edition.nom = t Suite.RafraichirRaccourcis() end end)
                  page.eNom:SetMaxLetters(24)
                  page.eNom:SetPoint("RIGHT", page.rNom, "RIGHT", -10, 0)
                  page.rIcone = O.Rangee()
                  page.bIcone = O.Bouton(page.rIcone, 140, function()
                      if not edition then return end
                      local rang = 1
                      for k, ic in ipairs(Suite.ICONES_PERSO) do if ic == edition.icone then rang = k end end
                      edition.icone = Suite.ICONES_PERSO[rang % #Suite.ICONES_PERSO + 1]
                      Suite.RafraichirRaccourcis()
                  end)
                  page.iIcone = O.Icone(page.rIcone, 22)
                  page.iIcone:SetPoint("RIGHT", page.rIcone, "RIGHT", -10, 0)
                  page.bIcone:SetPoint("RIGHT", page.iIcone, "LEFT", -8, 0)
                  page.rTexte = O.Rangee()
                  page.eTexte = O.Saisie(page.rTexte, O.LARGEUR - 200, function(t) if edition then edition.texte = t Suite.RafraichirRaccourcis() end end)
                  page.eTexte:SetMaxLetters(255)
                  page.eTexte:SetPoint("RIGHT", page.rTexte, "RIGHT", -10, 0)
                  -- Toutes les macros du jeu, a rapatrier.
                  page.t3 = O.Section()
                  page.introJeu = O.Texte(18)
                  page.jeu = {}
                  for i = 1, MAX_JEU do
                      local l = O.Rangee(24)
                      l.icone = O.Icone(l)
                      l.icone:SetPoint("LEFT", l, "LEFT", O.RETRAIT, 0)
                      l.nom:ClearAllPoints()
                      l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                      l.corps = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                      l.corps:SetPoint("LEFT", l, "LEFT", O.X - 40, 0)
                      l.corps:SetWidth(260)
                      l.corps:SetJustifyH("LEFT")
                      l.corps:SetWordWrap(false)
                      l.rapatrier = O.Bouton(l, 110, function()
                          if not l.j then return end
                          local nouvelle = { nom = l.j.nom }
                          IdPerso(nouvelle)
                          table.insert(Suite.MacrosPerso(), nouvelle)
                          Suite.RafraichirRaccourcis()
                      end)
                      l.rapatrier:SetPoint("RIGHT", l, "RIGHT", -10, 0)
                      l.deja = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                      l.deja:SetPoint("RIGHT", l, "RIGHT", -10, 0)
                      page.jeu[i] = l
                  end
              end,
              rendre = function(page)
                  page.t1:SetText(TR("Dans le gestionnaire", "In the manager"))
                  page.intro:SetText(TR("Vos macros : rapatriées du jeu, ou écrites ici. Communes au compte ; la case choisit ce qui va dans le panneau de ce personnage. Celles écrites ici restent dans la suite : pour les avoir aussi dans la fenêtre Macros du jeu, créez-les dans le jeu.",
                      "Your macros : brought in from the game, or written here. Account-wide ; the box picks what goes in this character's panel. Those written here stay in the suite."))
                  local perso = Suite.MacrosPerso()
                  local rapatriees = {}
                  for i, l in ipairs(page.lignes) do
                      local mm = perso[i]
                      if mm then
                          l.m = mm
                          local ecrite = mm.texte ~= nil
                          if not ecrite then rapatriees[mm.nom] = true end
                          local icone = ecrite and IconeDe(mm.icone) or (_G.GetMacroInfo and select(2, _G.GetMacroInfo(mm.nom)))
                          l.icone:SetTexture(icone or IconeDe(nil))
                          l.nom:SetText(mm.nom or "?")
                          l.genre:SetText(ecrite and TR("écrite ici", "written here") or TR("du jeu", "game"))
                          l.case:SetChecked(Suite.RaccourciActif(IdPerso(mm)))
                          l.modifier:SetText(edition == mm and TR("Fermer", "Close") or TR("Modifier", "Edit"))
                          l.modifier:SetShown(ecrite)
                          l.retirer:SetText(TR("Supprimer", "Delete"))
                          l:Show()
                      else
                          l.m = nil
                          l:Hide()
                      end
                  end
                  page.vide:SetText(#perso == 0 and TR("Aucune macro pour l'instant : rapatriez-en une plus bas, ou écrivez-en une.", "No macro yet : bring one in below, or write one.") or "")
                  page.t2:SetText(TR("Écrire une macro ici", "Write a macro here"))
                  page.rNouvelle.nom:SetText(TR("Nouvelle macro", "New macro"))
                  page.bNouvelle:SetText(TR("Écrire", "Write"))
                  local m = edition
                  for _, wd in ipairs({ page.eNom, page.bIcone, page.iIcone, page.eTexte }) do wd:SetShown(m ~= nil) end
                  page.rNom.nom:SetText(m and TR("Nom", "Name") or TR("« Modifier » sur une macro écrite ici pour la changer.", "\"Edit\" on a macro written here to change it."))
                  page.rIcone.nom:SetText(m and TR("Icône", "Icon") or "")
                  page.rTexte.nom:SetText(m and TR("Texte", "Text") or "")
                  if m then
                      if not page.eNom:HasFocus() then page.eNom:SetText(m.nom or "") end
                      if not page.eTexte:HasFocus() then page.eTexte:SetText(m.texte or "") page.eTexte:SetCursorPosition(0) end
                      page.bIcone:SetText(TR("Icône suivante", "Next icon"))
                      page.iIcone:SetTexture(IconeDe(m.icone))
                  end
                  page.t3:SetText(TR("Les macros du jeu", "The game's macros"))
                  local jeu = Suite.MacrosDuJeu()
                  page.introJeu:SetText(#jeu > 0 and TR("Celles de la fenêtre Macros du jeu (communes et de ce personnage).", "Those of the game's Macros window (shared and this character's).")
                      or TR("Aucune macro dans le jeu.", "No macro in the game."))
                  for i, l in ipairs(page.jeu) do
                      local j = jeu[i]
                      if j then
                          l.j = j
                          l.icone:SetTexture(j.icone or IconeDe(nil))
                          l.nom:SetText(j.nom)
                          local _, _, corps = _G.GetMacroInfo(j.nom)
                          l.corps:SetText(corps and corps:gsub("\n", "  ") or "")
                          local deja = rapatriees[j.nom]
                          l.rapatrier:SetText(TR("Rapatrier", "Bring in"))
                          l.rapatrier:SetShown(not deja)
                          l.deja:SetText(deja and ("|cff4fd16a" .. TR("Dans le gestionnaire", "In the manager") .. "|r") or "")
                          l:Show()
                      else
                          l.j = nil
                          l:Hide()
                      end
                  end
              end },

            { cle = "persos", icone = "Interface\\Icons\\INV_Misc_GroupNeedMore",
              libelle = function() return TR("Mes personnages", "My characters") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Texte(54)
                  page.lignes = {}
                  for i = 1, MAX_AUTRES do
                      local l = O.Rangee(24)
                      l.icone = O.Icone(l)
                      l.icone:SetPoint("LEFT", l, "LEFT", O.RETRAIT, 0)
                      l.nom:ClearAllPoints()
                      l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                      l.qui = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                      l.qui:SetPoint("LEFT", l, "LEFT", O.X - 40, 0)
                      l.prendre = O.Bouton(l, 140, function()
                          if not l.e then return end
                          local m = { nom = l.e.nom, icone = l.e.icone, texte = l.e.corps or "" }
                          IdPerso(m)
                          table.insert(Suite.MacrosPerso(), m)
                          Suite.RafraichirRaccourcis()
                      end)
                      l.prendre:SetPoint("RIGHT", l, "RIGHT", -10, 0)
                      page.lignes[i] = l
                  end
              end,
              rendre = function(page)
                  page.t1:SetText(TR("Les macros de mes personnages", "My characters' macros"))
                  page.intro:SetText(TR("Les macros propres à chaque personnage, relevées à sa dernière connexion. « Reprendre ici » en fait une macro écrite ici : elle devient disponible pour tous vos personnages, dans le panneau.",
                      "Each character's own macros, read at its last login. \"Take here\" makes it a macro written here : it becomes available to all your characters, in the panel."))
                  local liste = {}
                  local r = Reglages()
                  for cle, macros in pairs(type(r.macrosDesPersos) == "table" and r.macrosDesPersos or {}) do
                      for _, m in ipairs(macros) do table.insert(liste, { perso = cle, nom = m.nom, icone = m.icone, corps = m.corps }) end
                  end
                  table.sort(liste, function(a, b) if a.perso ~= b.perso then return a.perso < b.perso end return a.nom < b.nom end)
                  for i, l in ipairs(page.lignes) do
                      local e = liste[i]
                      if e then
                          l.e = e
                          l.icone:SetTexture(IconeDe(e.icone))
                          l.nom:SetText(e.nom)
                          l.qui:SetText((e.perso:match("^(.-) %- ")) or e.perso)
                          l.prendre:SetText(TR("Reprendre ici", "Take here"))
                          l:Show()
                      else
                          l.e = nil
                          l:Hide()
                      end
                  end
              end },
        },
    })
    return fenetreM
end

function Suite.OuvrirMacros()
    local w = FenetreMacrosPages()
    if w then Suite.Ouvrir("Macros") end
end

-- Fenetre "Reglage de l'interface" : les memes reglages que la section
-- Parametrage de l'interface des Parametres de CraftCore, pour toute la suite.
local fenetreI
local function FenetreInterface()
    if fenetreI then return fenetreI end
    local function C() return NS.charte end
    fenetreI = Suite.FenetreAPages({
        nom = "CoreSuiteInterface", cle = "Interface", icone = "Interface\\Icons\\INV_Misc_Book_11",
        titre = function() return TR("Réglage de l'interface", "Interface setup") end,
        pages = {
            { cle = "interface", icone = "Interface\\Icons\\INV_Misc_Book_11",
              libelle = function() return TR("L'interface", "The interface") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Detail(40)
                  page.rDefaut = O.Rangee()
                  page.cDefaut = O.Case(page.rDefaut, function(oui) Suite.PoserParDefaut(oui and true or false) end)
                  page.cDefaut:SetPoint("RIGHT", page.rDefaut, "RIGHT", -8, 0)
                  page.rFonduM = O.Rangee()
                  page.cFonduM = O.Case(page.rFonduM, function(oui) Suite.PoserFonduEnMarche(oui and true or false) end)
                  page.cFonduM:SetPoint("RIGHT", page.rFonduM, "RIGHT", -8, 0)
                  page.rFond = O.Rangee()
                  page.lFond = O.Liste(page.rFond, function() return C() and C().OptionsDeFond() or {} end,
                      function() return C() and C().FondComplet() end, function(v) if C() then C().PoserFondComplet(v) end end)
                  page.rSuivis = O.Rangee()
                  page.lSuivis = O.Liste(page.rSuivis, function() return { { "gris", TR("Gris", "Grey") }, { "parchemin", TR("Parchemin", "Parchment") } } end,
                      function() return C() and C().FondDesSuivis() end, function(v) if C() then C().PoserFondDesSuivis(v) end end)
                  page.rPanneau = O.Rangee()
                  page.lPanneau = O.Liste(page.rPanneau, function() return Suite.OptionsPanneau() end,
                      function() return Suite.PanneauChoisi() end, function(v) Suite.PoserPanneau(v) end)
                  page.rCompo = O.Rangee()
                  page.lCompo = O.Liste(page.rCompo, function() return Suite.OptionsComposition() end,
                      function() return Suite.CompositionChoisie() end, function(v) Suite.AppliquerComposition(v) end)
                  page.rSauver = O.Rangee()
                  page.bSauver = O.Bouton(page.rSauver, 200, function() Suite.SauverComposition() end)
                  page.bSauver:SetPoint("RIGHT", page.rSauver, "RIGHT", -10, 0)
              end,
              rendre = function(page)
                  local libre = not Suite.ParDefaut()
                  page.t1:SetText(TR("Paramétrage de l'interface", "Interface setup"))
                  page.intro:SetText(TR("Le fond des fenêtres, celui des suivis et le panneau du menu, pour toute la suite. Décochez le paramétrage par défaut pour choisir les vôtres.",
                      "Window and tracker backgrounds and the menu panel, for the whole suite. Untick the default setup to choose your own."))
                  page.rFonduM.nom:SetText(TR("Effacer les fenêtres quand je me déplace (jamais en vol)", "Fade windows while I move (never in flight)"))
                  page.cFonduM:SetChecked(Suite.FonduEnMarche())
                  page.rDefaut.nom:SetText(TR("Paramétrage par défaut", "Default setup"))
                  page.cDefaut:SetChecked(not libre)
                  page.rFond.nom:SetText(TR("Fond de la fenêtre", "Window background"))
                  page.rSuivis.nom:SetText(TR("Fond des suivis", "Trackers background"))
                  page.rPanneau.nom:SetText(TR("Panneau du menu", "Menu panel"))
                  page.rCompo.nom:SetText(TR("Composition", "Setup"))
                  page.rSauver.nom:SetText(TR("Fond et panneau actuels", "Current background and panel"))
                  page.bSauver:SetText(TR("Sauvegarder la configuration", "Save the setup"))
                  page.bSauver:SetEnabled(libre)
                  for _, li in ipairs({ page.lFond, page.lSuivis, page.lPanneau, page.lCompo }) do Suite.ActiverListe(li, libre) end
                  for _, r in ipairs({ page.rFond, page.rSuivis, page.rPanneau, page.rCompo, page.rSauver }) do r.nom:SetAlpha(libre and 1 or 0.5) end
              end },
        },
    })
    return fenetreI
end

function Suite.OuvrirInterface()
    local w = FenetreInterface()
    if w then Suite.Ouvrir("Interface") end
end

do
    local releve = CreateFrame("Frame")
    releve:RegisterEvent("PLAYER_LOGIN")
    releve:RegisterEvent("UPDATE_MACROS")
    releve:SetScript("OnEvent", function(_, ev)
        if _G.CoreSuite ~= Suite then return end
        pcall(ReleverMacrosDuPerso)
        -- La fenetre existe des la connexion : la colonne d'onglets la connait.
        if ev == "PLAYER_LOGIN" and Suite.Prive() then pcall(FenetreMacrosPages) end
    end)
end


-- ---------------------------------------------------------------------------
-- Profils, export et import des reglages
-- ---------------------------------------------------------------------------
-- Un profil garde les reglages de la suite et de chaque add-on (pas les
-- donnees : recettes, quetes, personnages). L'export laisse de cote ce qui
-- est prive (TradeCore, AuraCore, le mode prive).

local BASES = { CraftCore = "CraftCoreDB", QuestCore = "QuestCoreDB", MapCore = "MapCoreDB",
    LegacyCore = "LegacyCoreDB", TradeCore = "TradeCoreDB" }
local PRIVES = { TradeCore = true }
-- Cles de la suite qui ne voyagent pas : propres au compte ou au personnage.
local HORS_PROFIL = { profils = true, prive = true, macrosDesPersos = true, raccourcisOff = true, guidage = true }

local function Copier(v, profondeur)
    profondeur = profondeur or 0
    if type(v) ~= "table" then return v end
    if profondeur > 20 then return nil end
    local t = {}
    for k, x in pairs(v) do
        if (type(k) == "string" or type(k) == "number") and type(x) ~= "function" and type(x) ~= "userdata" then
            t[k] = Copier(x, profondeur + 1)
        end
    end
    return t
end

function Suite.Photographier(pourExport)
    local photo = { suite = {}, addons = {} }
    for k, v in pairs(type(CoreSuiteDB) == "table" and CoreSuiteDB or {}) do
        if not HORS_PROFIL[k] then photo.suite[k] = Copier(v) end
    end
    for cle, base in pairs(BASES) do
        local d = _G[base]
        if type(d) == "table" and type(d.reglages) == "table" and not (pourExport and PRIVES[cle]) then
            photo.addons[cle] = Copier(d.reglages)
        end
    end
    if not pourExport and type(_G.AuraCoreDB) == "table" then
        photo.improve = Copier(_G.AuraCoreDB)
        photo.improve.diag = nil
    end
    return photo
end

-- Remet une photo en place ; l'interface se recharge ensuite pour que chaque
-- add-on relise ses reglages.
function Suite.Appliquer(photo)
    if type(photo) ~= "table" then return false end
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    if type(photo.suite) == "table" then
        for k in pairs(CoreSuiteDB) do if not HORS_PROFIL[k] then CoreSuiteDB[k] = nil end end
        for k, v in pairs(photo.suite) do if not HORS_PROFIL[k] then CoreSuiteDB[k] = Copier(v) end end
    end
    for cle, reglages in pairs(type(photo.addons) == "table" and photo.addons or {}) do
        local base = BASES[cle]
        if base and type(_G[base]) == "table" and type(reglages) == "table" then
            _G[base].reglages = Copier(reglages)
        end
    end
    if type(photo.improve) == "table" and type(_G.AuraCoreDB) == "table" then
        local diag = _G.AuraCoreDB.diag
        _G.AuraCoreDB = Copier(photo.improve)
        _G.AuraCoreDB.diag = diag
    end
    return true
end

function Suite.Profils()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    CoreSuiteDB.profils = type(CoreSuiteDB.profils) == "table" and CoreSuiteDB.profils or {}
    return CoreSuiteDB.profils
end

function Suite.NomsDeProfils()
    local noms = {}
    for nom in pairs(Suite.Profils()) do table.insert(noms, nom) end
    table.sort(noms)
    return noms
end

-- Texte d'export : un format simple, relu par un lecteur ecrit ici (le texte
-- colle n'est jamais execute).
local ENTETE = "SagaCore1:"

local function Ecrire(v, morceaux)
    local t = type(v)
    if t == "string" then
        table.insert(morceaux, '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\%03d", c:byte()) end) .. '"')
    elseif t == "number" then
        table.insert(morceaux, string.format("%.14g", v))
    elseif t == "boolean" then
        table.insert(morceaux, v and "true" or "false")
    elseif t == "table" then
        table.insert(morceaux, "{")
        local cles = {}
        for k in pairs(v) do if type(k) == "string" or type(k) == "number" then table.insert(cles, k) end end
        table.sort(cles, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(cles) do
            local x = v[k]
            local tx = type(x)
            if tx == "string" or tx == "number" or tx == "boolean" or tx == "table" then
                table.insert(morceaux, "[")
                Ecrire(k, morceaux)
                table.insert(morceaux, "]=")
                Ecrire(x, morceaux)
                table.insert(morceaux, ",")
            end
        end
        table.insert(morceaux, "}")
    else
        table.insert(morceaux, "false")
    end
end

function Suite.Exporter()
    local morceaux = {}
    Ecrire(Suite.Photographier(true), morceaux)
    return ENTETE .. table.concat(morceaux)
end

local function Lire(texte)
    local pos, n = 1, #texte
    local function Blancs() pos = texte:find("[^%s]", pos) or (n + 1) end
    local Valeur
    function Valeur(profondeur)
        if profondeur > 20 then error("trop profond") end
        Blancs()
        local c = texte:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            while true do
                Blancs()
                local d = texte:sub(pos, pos)
                if d == "}" then pos = pos + 1 return t end
                if d ~= "[" then error("format") end
                pos = pos + 1
                local k = Valeur(profondeur + 1)
                Blancs()
                if texte:sub(pos, pos + 1) ~= "]=" then error("format") end
                pos = pos + 2
                local v = Valeur(profondeur + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("format") end
                t[k] = v
                Blancs()
                if texte:sub(pos, pos) == "," then pos = pos + 1 end
            end
        elseif c == '"' then
            local fin = texte:find('"', pos + 1, true)
            if not fin then error("format") end
            local brut = texte:sub(pos + 1, fin - 1)
            pos = fin + 1
            return (brut:gsub("\\(%d%d%d)", function(d) return string.char(tonumber(d)) end))
        elseif texte:sub(pos, pos + 3) == "true" then
            pos = pos + 4 return true
        elseif texte:sub(pos, pos + 4) == "false" then
            pos = pos + 5 return false
        else
            local nombre = texte:match("^%-?[%d%.]+[eE]?[%-%+]?%d*", pos)
            if not nombre or not tonumber(nombre) then error("format") end
            pos = pos + #nombre
            return tonumber(nombre)
        end
    end
    local v = Valeur(0)
    Blancs()
    if pos <= n then error("format") end
    return v
end

-- Rend la photo lue, ou nil si le texte n'est pas un export de la suite.
function Suite.LireExport(texte)
    if type(texte) ~= "string" then return nil end
    texte = texte:gsub("^%s+", ""):gsub("%s+$", "")
    if texte:sub(1, #ENTETE) ~= ENTETE or #texte > 500000 then return nil end
    local ok, photo = pcall(Lire, texte:sub(#ENTETE + 1))
    if not ok or type(photo) ~= "table" then return nil end
    -- Rien de prive ne rentre par un import.
    if type(photo.addons) == "table" then for cle in pairs(PRIVES) do photo.addons[cle] = nil end end
    photo.improve = nil
    if type(photo.suite) == "table" then for k in pairs(HORS_PROFIL) do photo.suite[k] = nil end end
    return photo
end

-- ---------------------------------------------------------------------------
-- Options, Add-ons : Forever SagaCore, et une sous-page par module
-- ---------------------------------------------------------------------------
-- Chaque module declare ses reglages dans _G.SagaCoreOptions (table commune,
-- quelle que soit la copie de ce fichier qui gagne) :
--   SagaCoreOptions[cle] = { titre = "CraftCore", ordre = 1, elements = fonction }
-- elements() rend une liste de lignes :
--   { "section", texte }                     sous-titre or
--   { "case", texte, lire, poser }           case a cocher
--   { "choix", texte, options, lire, poser } options = { { valeur, libelle }, ... }
--   { "valeur", texte, lire, poser, pas, mini, maxi, format }
--   { "bouton", texte, libelleDuBouton, action }
--   { "note", texte }                        texte gris, sur toute la largeur
-- Les textes peuvent etre des fonctions. Rien ici n'ouvre une autre fenetre
-- ni ne ferme les options.

_G.SagaCoreOptions = type(_G.SagaCoreOptions) == "table" and _G.SagaCoreOptions or {}

local function Txt(t) if type(t) == "function" then local ok, v = pcall(t) return ok and v or "" end return t or "" end

-- Construit une page de reglages dans un cadre des options du jeu.
function Suite.PageDOptions(f, elements, extra)
    local defil = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    defil:SetPoint("TOPLEFT", 0, -8)
    defil:SetPoint("BOTTOMRIGHT", -28, 8)
    local c = CreateFrame("Frame", nil, defil)
    c:SetSize(600, 10)
    defil:SetScrollChild(c)
    defil:SetScript("OnSizeChanged", function(self, l) c:SetWidth(math.max(300, (l or 600))) end)
    local rendus = {}
    local y = 8
    local function Rendre() for _, r in ipairs(rendus) do pcall(r) end end
    f.Rendre = Rendre
    local function Bouton(parent, action)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetHeight(24)
        b:SetScript("OnClick", function(self) pcall(action, self) Rendre() end)
        function b.Texte(t) b:SetText(t) b:SetWidth(math.max(40, (b:GetTextWidth() or 0) + 28)) end
        return b
    end
    local function Rangee(h)
        local r = CreateFrame("Frame", nil, c)
        r:SetHeight(h or 28)
        r:SetPoint("TOPLEFT", 20, -y)
        r:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        y = y + (h or 28) + 6
        r.nom = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.nom:SetPoint("LEFT", 0, 0)
        r.nom:SetJustifyH("LEFT")
        r.nom:SetWordWrap(false)
        return r
    end
    -- Colonne des controles, alignes a gauche.
    local COL = 280
    local function Ajouter(e)
        local genre = e[1]
        if genre == "section" then
            y = y + (y > 8 and 14 or 0)
            local t = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            t:SetPoint("TOPLEFT", 10, -y)
            local trait = c:CreateTexture(nil, "ARTWORK")
            trait:SetColorTexture(1, 0.82, 0, 0.25)
            trait:SetHeight(1)
            trait:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
            trait:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            y = y + 28
            table.insert(rendus, function() t:SetText(Txt(e[2])) end)
        elseif genre == "note" then
            local t = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            t:SetPoint("TOPLEFT", 20, -y)
            t:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            t:SetJustifyH("LEFT")
            y = y + 30
            table.insert(rendus, function() t:SetText(Txt(e[2])) end)
        elseif genre == "case" then
            local r = Rangee()
            local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
            cb:SetSize(26, 26)
            cb:SetPoint("RIGHT", r, "RIGHT", 2, 0)
            cb:SetScript("OnClick", function(self) pcall(e[4], self:GetChecked() and true or false) Rendre() end)
            r.nom:SetPoint("RIGHT", cb, "LEFT", -12, 0)
            table.insert(rendus, function()
                r.nom:SetText(Txt(e[2]))
                local ok, v = pcall(e[3])
                cb:SetChecked(ok and v and true or false)
            end)
        elseif genre == "choix" then
            local r = Rangee()
            local sg = Suite.Segments(r, e[3], e[4], e[5], Rendre)
            sg:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            r.nom:SetPoint("RIGHT", sg, "LEFT", -12, 0)
            table.insert(rendus, function()
                r.nom:SetText(Txt(e[2]))
                sg.Rendre()
                if e[6] then
                    local okA, actif = pcall(e[6])
                    Suite.ActiverListe(sg, okA and actif)
                    r.nom:SetAlpha((okA and actif) and 1 or 0.5)
                end
            end)
        elseif genre == "valeur" then
            local r = Rangee()
            local cu = Suite.Curseur(r, e[6] or 0, e[7] or 100, e[5] or 1, e[3], e[4], e[8])
            cu:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            r.nom:SetPoint("RIGHT", cu, "LEFT", -12, 0)
            table.insert(rendus, function() r.nom:SetText(Txt(e[2])) cu.Rendre() end)
        elseif genre == "bouton" then
            local r = Rangee()
            local b = Bouton(r, function() e[4]() end)
            b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            r.nom:SetPoint("RIGHT", b, "LEFT", -12, 0)
            table.insert(rendus, function()
                r.nom:SetText(Txt(e[2]))
                b.Texte(Txt(e[3]))
                if e[5] then local ok, actif = pcall(e[5]) b:SetEnabled(ok and actif and true or false) end
            end)
        elseif genre == "cadre" then
            -- { "cadre", hauteur, construire(parent) -> fonction de rendu }
            local r = CreateFrame("Frame", nil, c)
            r:SetHeight(e[2] or 100)
            r:SetPoint("TOPLEFT", 20, -y)
            r:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            y = y + (e[2] or 100) + 6
            local ok, rendu = pcall(e[3], r)
            if ok and type(rendu) == "function" then table.insert(rendus, rendu) end
        elseif genre == "saisie" then
            -- { "saisie", texte, libelleDuBouton, action(texteSaisi, case), largeur }
            local r = Rangee()
            local b
            local s = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
            s:SetSize(e[5] or 220, 22)
            s:SetAutoFocus(false)
            s:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            s:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            b = Bouton(r, function() e[4](s:GetText() or "", s) end)
            b:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            s:SetPoint("RIGHT", b, "LEFT", -12, 0)
            r.nom:SetPoint("RIGHT", s, "LEFT", -14, 0)
            table.insert(rendus, function()
                r.nom:SetText(Txt(e[2]))
                b.Texte(Txt(e[3]))
            end)
        end
    end
    local ok, liste = pcall(elements)
    for _, e in ipairs(ok and type(liste) == "table" and liste or {}) do Ajouter(e) end
    c:SetHeight(y + 20)
    f:HookScript("OnShow", Rendre)
    Rendre()
end

-- La page principale : affichage, langue, profils, partage.
local function ElementsPrincipaux()
    local etat = {}
    local L = {
        { "section", function() return TR("Affichage", "Display") end },
        { "case", function() return TR("Bouton de la minicarte", "Minimap button") end,
          function() return not Reglages().minicarteCachee end,
          function(v) Reglages().minicarteCachee = (not v) or nil if Suite.bouton then Suite.bouton:SetShown(v) end end },
        { "section", function() return TR("Paramétrage de l'interface", "Interface setup") end },
        { "case", function() return TR("Paramétrage par défaut", "Default setup") end,
          function() return Suite.ParDefaut() end, function(v) Suite.PoserParDefaut(v) end },
        { "choix", function() return TR("Fond de la fenêtre", "Window background") end,
          function() return NS.charte and NS.charte.OptionsDeFond and NS.charte.OptionsDeFond() or {} end,
          function() return NS.charte and NS.charte.FondComplet and NS.charte.FondComplet() end,
          function(v) if NS.charte then NS.charte.PoserFondComplet(v) end end, function() return not Suite.ParDefaut() end },
        { "choix", function() return TR("Fond des suivis", "Trackers background") end,
          function() return { { "gris", TR("Gris", "Grey") }, { "parchemin", TR("Parchemin", "Parchment") } } end,
          function() return NS.charte and NS.charte.FondDesSuivis and NS.charte.FondDesSuivis() end,
          function(v) if NS.charte then NS.charte.PoserFondDesSuivis(v) end end, function() return not Suite.ParDefaut() end },
        { "choix", function() return TR("Panneau du menu", "Menu panel") end,
          function() return Suite.OptionsPanneau() end,
          function() return Suite.PanneauChoisi() end, function(v) Suite.PoserPanneau(v) end, function() return not Suite.ParDefaut() end },
        { "choix", function() return TR("Composition", "Setup") end,
          function() return Suite.OptionsComposition() end,
          function() return Suite.CompositionChoisie() end, function(v) Suite.AppliquerComposition(v) end, function() return not Suite.ParDefaut() end },
        { "bouton", function() return TR("Fond et panneau actuels", "Current background and panel") end,
          function() return TR("Sauvegarder la configuration", "Save the setup") end, function() Suite.SauverComposition() end,
          function() return not Suite.ParDefaut() end },
        { "section", function() return TR("Langue", "Language") end },
    }
    local langues = { { false, function() return TR("Celle du jeu", "Game language") end } }
    for _, l in ipairs(Suite.LANGUES) do table.insert(langues, { l.code, l.nom }) end
    table.insert(L, { "choix", function() return TR("Langue de la suite", "Suite language") end, langues,
        function() return type(CoreSuiteDB) == "table" and CoreSuiteDB.langue or false end,
        function(v) CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {} CoreSuiteDB.langue = v or nil etat.langue = true end })
    table.insert(L, { "bouton", function() return TR("Appliquer la langue", "Apply the language") end,
        function() return TR("Recharger", "Reload") end, function() if ReloadUI then ReloadUI() end end })

    table.insert(L, { "section", function() return TR("Profils", "Profiles") end })
    table.insert(L, { "choix", function() return TR("Profil enregistré", "Saved profile") end,
        function()
            local noms = Suite.NomsDeProfils()
            if #noms == 0 then return { { false, TR("Aucun", "None") } } end
            local o = {}
            for _, n in ipairs(noms) do table.insert(o, { n, n }) end
            return o
        end,
        function()
            local noms = Suite.NomsDeProfils()
            if not etat.profil or not Suite.Profils()[etat.profil] then etat.profil = noms[1] or false end
            return etat.profil
        end,
        function(v) etat.profil = v end })
    table.insert(L, { "bouton", function() return TR("Appliquer ce profil", "Apply this profile") end,
        function() return TR("Appliquer", "Apply") end,
        function()
            local photo = etat.profil and Suite.Profils()[etat.profil]
            if photo and Suite.Appliquer(photo) and ReloadUI then ReloadUI() end
        end, function() return etat.profil and Suite.Profils()[etat.profil] ~= nil end })
    table.insert(L, { "bouton", function() return TR("Supprimer ce profil", "Delete this profile") end,
        function() return TR("Supprimer", "Delete") end,
        function() if etat.profil then Suite.Profils()[etat.profil] = nil etat.profil = nil end end,
        function() return etat.profil and Suite.Profils()[etat.profil] ~= nil end })
    table.insert(L, { "saisie", function() return TR("Nouveau profil", "New profile") end,
        function() return TR("Enregistrer", "Save") end,
        function(texte, saisie)
            local nom = texte:gsub("^%s+", ""):gsub("%s+$", "")
            if nom == "" then return end
            Suite.Profils()[nom] = Suite.Photographier(false)
            etat.profil = nom
            saisie:SetText("")
            saisie:ClearFocus()
        end })

    table.insert(L, { "section", function() return TR("Partager", "Share") end })
    table.insert(L, { "saisie", function() return TR("Exporter mes réglages", "Export my settings") end,
        function() return TR("Exporter", "Export") end,
        function(_, saisie)
            saisie:SetText(Suite.Exporter())
            saisie:SetCursorPosition(0)
            saisie:SetFocus()
            saisie:HighlightText()
        end })
    table.insert(L, { "saisie", function() return TR("Importer des réglages", "Import settings") end,
        function() return TR("Importer", "Import") end,
        function(texte)
            local photo = Suite.LireExport(texte)
            if photo and Suite.Appliquer(photo) then if ReloadUI then ReloadUI() end return end
            etat.erreur = true
        end })
    table.insert(L, { "note", function()
        if etat.erreur then etat.erreur = nil return TR("Ce texte n'est pas un export de Forever SagaCore.", "This text is not a Forever SagaCore export.") end
        return TR("Appliquer un profil, importer ou changer de langue recharge l'interface. Exporter remplit la case : copiez le texte sélectionné.",
            "Applying a profile, importing or changing language reloads the interface. Export fills the box : copy the selected text.")
    end })
    return L
end

function Suite.InscrireDansOptions()
    local S = _G.Settings
    if Suite.pageOptions or not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return end
    local f = CreateFrame("Frame")
    f:Hide()
    local ok, categorie = pcall(S.RegisterCanvasLayoutCategory, f, "Forever SagaCore")
    if not (ok and categorie) then return end
    Suite.pageOptions = categorie
    local construite
    f:SetScript("OnShow", function() if not construite then construite = true Suite.PageDOptions(f, ElementsPrincipaux) end end)

    -- Les sous-pages, dans l'ordre des modules.
    local liste = {}
    for cle, o in pairs(_G.SagaCoreOptions) do
        local prive = (cle == "Macros") and not Suite.Prive()
        if type(o) == "table" and type(o.elements) == "function" and not prive then table.insert(liste, { cle = cle, o = o }) end
    end
    table.sort(liste, function(a, b) return (a.o.ordre or 99) < (b.o.ordre or 99) end)
    for _, x in ipairs(liste) do
        local sf = CreateFrame("Frame")
        sf:Hide()
        local faite
        sf:SetScript("OnShow", function() if not faite then faite = true Suite.PageDOptions(sf, x.o.elements) end end)
        if S.RegisterCanvasLayoutSubcategory then
            pcall(S.RegisterCanvasLayoutSubcategory, categorie, sf, Txt(x.o.titre))
        end
    end
    pcall(S.RegisterAddOnCategory, categorie)
end

-- Les macros : la disposition du panneau.
_G.SagaCoreOptions.Macros = { titre = function() return TR("Macros", "Macros") end, ordre = 5, elements = function()
    local function R() return Reglages() end
    local function Maj() pcall(Suite.PlacerBoutonRaccourcis) if Suite.RafraichirRaccourcis then pcall(Suite.RafraichirRaccourcis) end end
    return {
        { "section", function() return TR("Panneau des macros", "Macro panel") end },
        { "case", function() return TR("Bouton rond affiché", "Round button shown") end,
          function() return not R().raccourcisCache end, function(v) R().raccourcisCache = (not v) or nil Maj() end },
        { "choix", function() return TR("Forme des icônes", "Icon shape") end,
          { { true, function() return TR("Rondes", "Round") end }, { false, function() return TR("Carrées", "Square") end } },
          function() return R().raccourcisRonds == true end, function(v) R().raccourcisRonds = v or nil Maj() end },
        { "choix", function() return TR("Le panneau s'ouvre", "Panel opens") end,
          { { "gauche", function() return TR("À gauche", "To the left") end }, { "droite", function() return TR("À droite", "To the right") end },
            { "haut", function() return TR("Vers le haut", "Upwards") end }, { "bas", function() return TR("Vers le bas", "Downwards") end } },
          function() return R().raccourcisOuverture or "gauche" end, function(v) R().raccourcisOuverture = v Maj() end },
        { "valeur", function() return TR("Icônes par ligne", "Icons per row") end,
          function() return R().raccourcisParLigne or 6 end, function(v) R().raccourcisParLigne = v Maj() end, 1, 1, 12 },
        { "valeur", function() return TR("Nombre de lignes", "Number of rows") end,
          function() return R().raccourcisLignes or 3 end, function(v) R().raccourcisLignes = v Maj() end, 1, 1, 6 },
        { "bouton", function() return TR("Position du bouton rond", "Round button position") end,
          function() return TR("Remettre à sa place", "Reset") end,
          function() local r = R() r.raccourcisX, r.raccourcisY = nil, nil Maj() end },
    }
end }

-- Les messages dans la discussion : chaque message, coupe ou non, et ou il va.
_G.SagaCoreOptions.Messages = { titre = function() return TR("Messages", "Messages") end, ordre = 4, elements = function()
    local M = _G.SagaCoreMessages
    if not (M and M.ordre and M.defs) then return {} end
    local L = {}
    local dest = {}
    for _, d in ipairs(M.DESTINATIONS or { "onglet", "general", "deux", "rien" }) do
        table.insert(dest, { d, function() return M.NomDestination and M.NomDestination(d) or d end })
    end
    for _, info in ipairs(Suite.Liste()) do
        local addon = info.cle
        local ordre = M.ordre[addon]
        if ordre and #ordre > 0 then
            table.insert(L, { "section", addon })
            for _, cle in ipairs(ordre) do
                local def = M.defs[addon][cle]
                table.insert(L, { "choix", function() return def.libelle or cle end,
                    { { "onglet", function() return TR("Onglet", "Tab") end }, { "general", function() return TR("Général", "General") end },
                      { "deux", function() return TR("Les deux", "Both") end }, { "coupe", function() return TR("Coupé", "Off") end } },
                    function()
                        local ou = M.Destination(addon, cle)
                        if not M.Actif(addon, cle) or ou == "rien" then return "coupe" end
                        return ou
                    end,
                    function(v)
                        local r = M.Reglage(addon, cle)
                        if v == "coupe" then r.coupe = true else r.coupe = nil r.ou = v end
                    end })
            end
        end
    end
    table.insert(L, { "note", function() return TR("Le texte de chaque message se change dans la fenêtre Messages de la suite.",
        "Each message's text is changed in the suite's Messages window.") end })
    return L
end }

-- ---------------------------------------------------------------------------
-- Fenetres en sous-brillance quand le personnage se deplace : toutes les
-- fenetres de la suite ouvertes s'effacent presque entierement des qu'il
-- marche, et reviennent des qu'il s'arrete. Jamais en vol (trajet d'un maitre
-- de vol, monture volante) : c'est justement le moment de s'en servir.
-- Desactivable dans les reglages de l'interface. Les suivis gardent leur
-- propre regle (sauf en vol, la meme exception).
-- ---------------------------------------------------------------------------

Suite.FENETRES_FONDU = { "CraftCoreWindow", "QuestCoreFenetre", "MapCoreFenetre", "LegacyCoreFenetre",
    "TradeCoreFenetre", "AuraCoreFenetre", "GloryCoreFenetre", "CoreSuiteReglages", "CoreSuiteMacros", "SagaCoreMessages" }
local ALPHA_MARCHE = 0.1

-- En vol : trajet de maitre de vol ou monture volante.
-- Dans un donjon : le plan du donjon (salles, boss, entree, etages), lu dans
-- les donnees du Donjon Journal de Forever quand il en a un. Rend la cle du
-- donjon, ses donnees de plan et son nom dans la langue du jeu, ou nil. Rien
-- ne s'ouvre ici : c'est la carte de MapCore qui l'affiche.
function Suite.PlanDuDonjon()
    if type(_G.IsInInstance) ~= "function" then return nil end
    local okI, dedans, genre = pcall(_G.IsInInstance)
    if not (okI and dedans) or genre == "pvp" or genre == "arena" then return nil end
    local FDJ = _G.ForeverDungeonJournal_NS
    if type(FDJ) ~= "table" or type(FDJ.DUNGEON_MAPS) ~= "table" or type(FDJ.CurrentDungeon) ~= "function" then return nil end
    local ok, donjon = pcall(FDJ.CurrentDungeon)
    if not ok or not donjon or type(FDJ.DUNGEON_MAPS[donjon]) ~= "table" then return nil end
    if FDJ.IsDungeonMapLocked then
        local okV, ferme = pcall(FDJ.IsDungeonMapLocked, donjon)
        if okV and ferme then return nil end
    end
    local nom
    if _G.GetInstanceInfo then
        local okN, n = pcall(_G.GetInstanceInfo)
        if okN then nom = n end
    end
    if type(nom) ~= "string" or nom == "" or (_G.issecretvalue and _G.issecretvalue(nom)) then nom = donjon end
    return donjon, FDJ.DUNGEON_MAPS[donjon], nom
end

-- Ouvre la carte de MapCore sur le plan du donjon. Vrai si c'est fait.
function Suite.OuvrirPlanDuDonjon()
    if not Suite.PlanDuDonjon() then return false end
    local api = _G.MapCoreAPI
    if type(api) == "table" and type(api.Ouvrir) == "function" then return (pcall(api.Ouvrir)) end
    return false
end

-- Outils de donjon d'autres add-ons, comme les guides : un catalogue, le
-- joueur choisit le sien, et l'outil ne s'ouvre QUE sur son clic explicite.
-- Jamais d'ouverture automatique, quelle que soit la situation.
local function OuvrirFDJ(donjon)
    local FDJ = _G.ForeverDungeonJournal_NS
    if type(FDJ) ~= "table" then return false end
    local cadre = _G.ForeverDungeonJournalFrame
    if not (cadre and cadre:IsShown()) and type(_G.ForeverDungeonJournal_Toggle) == "function" then
        pcall(_G.ForeverDungeonJournal_Toggle)
    end
    local function Page()
        if donjon and type(FDJ.OpenDungeonMap) == "function" then pcall(FDJ.OpenDungeonMap, donjon) end
        local f = _G.ForeverDungeonJournalFrame
        if f and f.Raise then pcall(f.Raise, f) end
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.2, Page) else Page() end
    return true
end
Suite.OUTILS_DONJON = {
    { cle = "fdj", nom = "Donjon Journal", addon = "ForeverDungeonJournal",
      present = function() return type(_G.ForeverDungeonJournal_NS) == "table" end,
      ouvrir = OuvrirFDJ },
}
-- Les outils installes, dans l'ordre du catalogue.
function Suite.OutilsDonjon()
    local l = {}
    for _, o in ipairs(Suite.OUTILS_DONJON) do
        local ok, oui = pcall(o.present)
        if ok and oui then table.insert(l, o) end
    end
    return l
end
-- L'outil choisi par le joueur (le premier installe tant qu'il n'a rien choisi).
function Suite.OutilDonjon()
    local l = Suite.OutilsDonjon()
    local voulu = type(CoreSuiteDB) == "table" and CoreSuiteDB.outilDonjon
    for _, o in ipairs(l) do if o.cle == voulu then return o, #l end end
    return l[1], #l
end
-- Passer a l'outil suivant (seulement s'il y en a plusieurs d'installes).
function Suite.OutilDonjonSuivant()
    local l = Suite.OutilsDonjon()
    if #l < 2 then return Suite.OutilDonjon() end
    local o = Suite.OutilDonjon()
    local i = 1
    for k, x in ipairs(l) do if x == o then i = k end end
    local suivant = l[i % #l + 1]
    if type(CoreSuiteDB) == "table" then CoreSuiteDB.outilDonjon = suivant.cle end
    return suivant, #l
end
-- Ouvrir l'outil choisi sur ce donjon : a n'appeler que depuis un clic du joueur.
function Suite.OuvrirOutilDonjon(donjon)
    local o = Suite.OutilDonjon()
    if not o then return false end
    local ok, fait = pcall(o.ouvrir, donjon)
    return ok and fait or false
end

-- La vitesse du personnage, ou nil quand le jeu la cache (valeur secrete en
-- champ de bataille ou en combat : on ne la compare jamais).
function Suite.VitesseJoueur()
    if not _G.GetUnitSpeed then return nil end
    local ok, v = pcall(_G.GetUnitSpeed, "player")
    if not ok or v == nil then return nil end
    if _G.issecretvalue and _G.issecretvalue(v) then return nil end
    return tonumber(v)
end

function Suite.EnVol()
    if _G.UnitOnTaxi then local ok, oui = pcall(_G.UnitOnTaxi, "player") if ok and oui then return true end end
    if _G.IsFlying then local ok, oui = pcall(_G.IsFlying) if ok and oui then return true end end
    return false
end
-- Le reglage : vrai par defaut.
function Suite.FonduEnMarche()
    return not (type(CoreSuiteDB) == "table" and CoreSuiteDB.fonduMarche == false)
end
function Suite.PoserFonduEnMarche(oui)
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    if oui then CoreSuiteDB.fonduMarche = nil else CoreSuiteDB.fonduMarche = false end
end

local function FenetresAFondre()
    local liste, vues = {}, {}
    for _, nom in ipairs(Suite.FENETRES_FONDU) do
        local f = _G[nom]
        if f and f.IsShown and f:IsShown() and not vues[f] then vues[f] = true table.insert(liste, f) end
    end
    for _, w in ipairs(Suite.fenetresAPages or {}) do
        local f = w.cadre
        if f and f:IsShown() and not vues[f] then vues[f] = true table.insert(liste, f) end
    end
    return liste
end

do
    local veille = CreateFrame("Frame")
    local attente = 0
    veille:SetScript("OnUpdate", function(_, ecoule)
        if _G.CoreSuite ~= Suite then return end
        attente = attente - (ecoule or 0)
        local fenetres
        -- Toutes les 0,1 s : la vitesse ; a chaque image : le fondu lui-meme.
        local ok, vitesse = pcall(GetUnitSpeed, "player")
        if not ok or (_G.issecretvalue and _G.issecretvalue(vitesse)) then vitesse = 0 end
        local bouge = (tonumber(vitesse) or 0) > 0 and Suite.FonduEnMarche() and not Suite.EnVol()
        local cible = bouge and ALPHA_MARCHE or 1
        if attente > 0 and veille.cible == cible and not veille.enCours then return end
        attente = 0.1
        veille.cible = cible
        fenetres = FenetresAFondre()
        local enCours = false
        local pas = 4 * (ecoule or 0.05)
        for _, f in ipairs(fenetres) do
            local actuel = f:GetAlpha() or 1
            if math.abs(actuel - cible) >= 0.01 then
                if actuel < cible then actuel = math.min(cible, actuel + pas) else actuel = math.max(cible, actuel - pas) end
                f:SetAlpha(actuel)
                enCours = true
            end
        end
        veille.enCours = enCours
    end)
end

do
    local depart = CreateFrame("Frame")
    depart:RegisterEvent("PLAYER_LOGIN")
    depart:SetScript("OnEvent", function()
        -- Une seule page, par la copie la plus recente de ce fichier.
        if _G.CoreSuite ~= Suite then return end
        pcall(Suite.InscrireDansOptions)
    end)
end
