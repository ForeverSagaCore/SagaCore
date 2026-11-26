local _, NS = ...

-- Socle de LegacyCore : lectures sous filet, base de sauvegarde, releve de
-- l'heritage (systeme Legacy de WoW Forever) du personnage connecte.
-- Lecture seule : LegacyCore ne depense ni ne modifie jamais rien.

NS.VERSION = "0.6.0"
NS.base = {}
local base = NS.base

-- Niveau qui debloque l'heritage, et plafond de points par personnage
-- (d'apres le jeu au lancement ; le releve du jeu fait foi s'il dit autre chose).
base.NIVEAU_HERITAGE = 25
base.POINTS_MAX = 16

function NS.Lecture(...)
    for i = 1, select("#", ...) do
        local chemin = select(i, ...)
        local valeur = _G
        for morceau in string.gmatch(chemin, "[^%.]+") do
            if type(valeur) ~= "table" then valeur = nil break end
            valeur = valeur[morceau]
        end
        if type(valeur) == "function" then return valeur end
    end
    return nil
end

function NS.Appeler(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 15)
end

function NS.Dire(texte)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100LegacyCore|r " .. tostring(texte)) end
end

-- "Nom - Royaume", la meme cle que CraftCore et QuestCore.
function NS.ClePersonnage()
    local nom = NS.Appeler(UnitName, "player")
    local royaume = NS.Appeler(_G.SagaCoreRoyaume or GetRealmName)
    if type(nom) ~= "string" or nom == "" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" then return nil end
    return nom .. " - " .. royaume
end

function NS.NomCourt(cle) return (tostring(cle or "?"):match("^(.-) %- ")) or tostring(cle) end

-- Icone d'un sort, par l'interface du jeu qui existe dans ce client.
function NS.IconeDeSort(id)
    id = tonumber(id)
    if not id then return nil end
    local C = _G.C_Spell
    if C and C.GetSpellTexture then
        local ok, t = pcall(C.GetSpellTexture, id)
        if ok and t then return t end
    end
    if C and C.GetSpellInfo then
        local ok, info = pcall(C.GetSpellInfo, id)
        if ok and type(info) == "table" and (info.iconID or info.originalIconID) then return info.iconID or info.originalIconID end
    end
    if _G.GetSpellTexture then
        local ok, t = pcall(_G.GetSpellTexture, id)
        if ok and t then return t end
    end
    if _G.GetSpellInfo then
        local ok, _, _, t = pcall(_G.GetSpellInfo, id)
        if ok and t then return t end
    end
    return nil
end

function base.Init()
    LegacyCoreDB = type(LegacyCoreDB) == "table" and LegacyCoreDB or {}
    local d = LegacyCoreDB
    d.persos = d.persos or {}
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    d.incidents = d.incidents or {}
end

function base.ReglagesGeneraux()
    local d = LegacyCoreDB
    if type(d) ~= "table" then return {} end
    d.reglages = d.reglages or {}
    d.reglages.general = d.reglages.general or {}
    return d.reglages.general
end

function base.NoterIncident(quoi, souci)
    local d = LegacyCoreDB
    if type(d) ~= "table" then return end
    d.incidents = d.incidents or {}
    table.insert(d.incidents, { quoi = quoi, souci = tostring(souci), quand = NS.Appeler(time) })
    while #d.incidents > 20 do table.remove(d.incidents, 1) end
end

-- ---------------------------------------------------------------------------
-- Releve des arbres d'heritage du personnage connecte
-- ---------------------------------------------------------------------------

local function NomDeSort(id)
    if not id then return nil end
    local spell = _G.C_Spell
    if spell and spell.GetSpellInfo then
        local ok, info = pcall(spell.GetSpellInfo, id)
        if ok and type(info) == "table" then return info.name end
    end
    return (NS.Appeler(_G.GetSpellInfo, id))
end

local function DescriptionDeSort(id)
    if not id then return nil end
    local f = (_G.C_Spell and _G.C_Spell.GetSpellDescription) or _G.GetSpellDescription
    local texte = NS.Appeler(f, id)
    if type(texte) == "string" and texte ~= "" then return texte end
    return nil
end

-- Genre d'un arbre d'apres le nom de sa constante.
-- Dans l'ordre de la fenetre du jeu : Aventure, Ingeniosite, Metiers.
local function GenreArbre(nom)
    nom = string.upper(tostring(nom))
    if string.find(nom, "PROFESSION") then return "metiers", 3 end
    if string.find(nom, "ADVENTURE") then return "aventure", 1 end
    return "ressources", 2
end

-- Les arbres que le jeu declare : constantes, sinon la table de l'interface.
local function Arbres()
    local liste = {}
    local consts = _G.Constants and _G.Constants.LegacyConsts
    if type(consts) == "table" then
        for k, v in pairs(consts) do
            if type(k) == "string" and string.find(k, "TREE") and type(v) == "number" then
                local genre, ordre = GenreArbre(k)
                table.insert(liste, { treeID = v, genre = genre, ordre = ordre })
            end
        end
    end
    if #liste == 0 and type(_G.LegacyTreeData) == "table" then
        for i, t in pairs(_G.LegacyTreeData) do
            if type(t) == "table" and t.treeID then
                local genre, ordre = GenreArbre(t.name or t.key or i)
                table.insert(liste, { treeID = t.treeID, genre = genre, ordre = ordre, nom = t.name })
            end
        end
    end
    table.sort(liste, function(a, b)
        if a.ordre ~= b.ordre then return a.ordre < b.ordre end
        return a.treeID < b.treeID
    end)
    return liste
end

function base.Releve()
    local d = LegacyCoreDB
    local cle = NS.ClePersonnage()
    if type(d) ~= "table" or not cle then return end
    local _, classe = NS.Appeler(UnitClass, "player")
    local r = { cle = cle, niveau = NS.Appeler(UnitLevel, "player"), classe = classe,
        quand = NS.Appeler(date, "%d/%m %H:%M"), arbres = {} }
    local traits = _G.C_Traits
    if type(traits) == "table" and traits.GetConfigIDByTreeID then
        for _, a in ipairs(Arbres()) do
            local configID = NS.Appeler(traits.GetConfigIDByTreeID, a.treeID)
            local arbre = { treeID = a.treeID, genre = a.genre, nom = a.nom, noeuds = {} }
            if configID then
                local monnaies = NS.Appeler(traits.GetTreeCurrencyInfo, configID, a.treeID, false)
                if type(monnaies) == "table" and type(monnaies[1]) == "table" then
                    arbre.disponibles = monnaies[1].quantity
                    arbre.depensesJeu = monnaies[1].spent
                    arbre.maxi = monnaies[1].maxQuantity
                end
                for _, nodeID in ipairs(NS.Appeler(traits.GetTreeNodes, a.treeID) or {}) do
                    local info = NS.Appeler(traits.GetNodeInfo, configID, nodeID)
                    if type(info) == "table" and info.isVisible ~= false and info.entryIDs and #info.entryIDs > 0 then
                        local n = { id = nodeID, x = info.posX or 0, y = info.posY or 0, rang = info.currentRank or info.ranksPurchased or 0,
                            maxi = info.maxRanks or 1, dispo = info.isAvailable, verrou = info.isLocked,
                            choix = info.type == 2 or nil, liens = {} }
                        -- Les liens vers les talents suivants, comme les traits du jeu.
                        for _, lien in ipairs(type(info.visibleEdges) == "table" and info.visibleEdges or {}) do
                            if type(lien) == "table" and lien.targetNode then table.insert(n.liens, lien.targetNode) end
                        end
                        -- L'entree choisie d'abord, puis les autres : la premiere qui
                        -- a un sort (nom, description, icone). Un choix de sous-arbre
                        -- donne son icone par son atlas.
                        local entrees = {}
                        if info.activeEntry and info.activeEntry.entryID then table.insert(entrees, info.activeEntry.entryID) end
                        for _, e in ipairs(info.entryIDs) do table.insert(entrees, e) end
                        for _, entryID in ipairs(entrees) do
                            local entree = NS.Appeler(traits.GetEntryInfo, configID, entryID)
                            if type(entree) == "table" then
                                local def = entree.definitionID and NS.Appeler(traits.GetDefinitionInfo, entree.definitionID)
                                if type(def) == "table" and not n.sort then
                                    n.sort = def.spellID
                                    n.nom = def.overrideName or NomDeSort(def.spellID)
                                    n.description = def.overrideDescription or DescriptionDeSort(def.spellID)
                                    n.icone = def.overrideIcon or NS.IconeDeSort(def.spellID)
                                end
                                if not n.icone and entree.subTreeID and traits.GetSubTreeInfo then
                                    local sous = NS.Appeler(traits.GetSubTreeInfo, configID, entree.subTreeID)
                                    if type(sous) == "table" then
                                        n.atlas = sous.iconElementID
                                        n.nom = n.nom or sous.name
                                        n.description = n.description or sous.description
                                    end
                                end
                                if n.icone or n.atlas then break end
                            end
                        end
                        table.insert(arbre.noeuds, n)
                    end
                end
            end
            table.sort(arbre.noeuds, function(p, q)
                if p.y ~= q.y then return p.y < q.y end
                return p.x < q.x
            end)
            -- Un identifiant d'arbre sans aucun talent (une constante du jeu qui
            -- n'est pas un arbre) n'est pas garde.
            if #arbre.noeuds > 0 then table.insert(r.arbres, arbre) end
        end
    end
    -- Un releve vide (jeu pas encore pret) n'efface pas le precedent.
    local ancien = d.persos[cle]
    if #r.arbres == 0 and ancien and ancien.arbres and #ancien.arbres > 0 then
        ancien.niveau, ancien.classe = r.niveau, r.classe
        return
    end
    d.persos[cle] = r
end

-- Points depenses dans un arbre (somme des rangs).
function base.Depenses(arbre)
    local total = 0
    for _, n in ipairs(arbre and arbre.noeuds or {}) do total = total + (tonumber(n.rang) or 0) end
    return total
end

-- ---------------------------------------------------------------------------
-- Personnages connus de la suite
-- ---------------------------------------------------------------------------

-- Tous les personnages du compte que la suite connait : releve d'heritage,
-- QuestCore, CraftCore. Le personnage connecte d'abord.
function base.Personnages()
    local parCle = {}
    local function Ajouter(cle, niveau, classe)
        if type(cle) ~= "string" or not cle:find(" %- ") then return end
        local p = parCle[cle] or { cle = cle }
        parCle[cle] = p
        if tonumber(niveau) and (not p.niveau or tonumber(niveau) > p.niveau) then p.niveau = tonumber(niveau) end
        if type(classe) == "string" and classe ~= "" and not p.classe then p.classe = classe end
    end
    for cle, r in pairs((LegacyCoreDB or {}).persos or {}) do Ajouter(cle, r.niveau, r.classe) end
    local qc = type(_G.QuestCoreDB) == "table" and _G.QuestCoreDB.persos
    for cle, p in pairs(type(qc) == "table" and qc or {}) do
        if type(p) == "table" then Ajouter(cle, p.niveau, p.classe) end
    end
    local cc = type(_G.CraftCoreDB) == "table" and _G.CraftCoreDB.personnages
    for cle, f in pairs(type(cc) == "table" and cc or {}) do
        if type(f) == "table" then Ajouter(cle, f.niveau, f.jetonClasse) end
    end
    local courant = NS.ClePersonnage()
    local liste = {}
    for cle, p in pairs(parCle) do
        p.releve = LegacyCoreDB and LegacyCoreDB.persos[cle]
        table.insert(liste, p)
    end
    table.sort(liste, function(a, b)
        if (a.cle == courant) ~= (b.cle == courant) then return a.cle == courant end
        return a.cle < b.cle
    end)
    return liste
end

function base.Personnage(cle)
    for _, p in ipairs(base.Personnages()) do if p.cle == cle then return p end end
    return nil
end

-- ---------------------------------------------------------------------------
-- Defis : ce que vos personnages ont deja atteint (calcule, le jeu fait foi)
-- ---------------------------------------------------------------------------

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local PALIERS_CLASSE = { 25, 45, 60 }
-- Les six metiers de fabrication (pas la recolte), par ligne de metier du jeu.
local METIERS = { 164, 165, 171, 197, 202, 333 }
local PALIERS_METIER = { 150, 225, 300 }

-- { classes = { { classe, paliers = { {palier, fait, meilleur = {cle, niveau}} } } },
--   metiers = { { ligne, nom, paliers = {...} } } }
function base.Defis()
    local persos = base.Personnages()
    local r = { classes = {}, metiers = {} }
    for _, classe in ipairs(CLASSES) do
        local meilleur, tous = nil, {}
        for _, p in ipairs(persos) do
            if p.classe == classe and p.niveau then
                table.insert(tous, { cle = p.cle, valeur = p.niveau, classe = p.classe })
                if not meilleur or p.niveau > meilleur.niveau then meilleur = p end
            end
        end
        table.sort(tous, function(a, b) return a.valeur > b.valeur end)
        local ligne = { classe = classe, meilleur = meilleur, tous = tous, paliers = {} }
        for _, palier in ipairs(PALIERS_CLASSE) do
            table.insert(ligne.paliers, { palier = palier, fait = meilleur and meilleur.niveau >= palier or false })
        end
        table.insert(r.classes, ligne)
    end
    local cc = type(_G.CraftCoreDB) == "table" and _G.CraftCoreDB.personnages or {}
    for _, metier in ipairs(METIERS) do
        local meilleur, nom, tous = nil, nil, {}
        for cle, f in pairs(cc) do
            local m = type(f) == "table" and type(f.metiers) == "table"
                and (f.metiers[metier] or f.metiers[tostring(metier)])
            if type(m) == "table" and tonumber(m.rang) then
                nom = nom or m.nom
                table.insert(tous, { cle = cle, valeur = tonumber(m.rang), classe = f.jetonClasse })
                if not meilleur or tonumber(m.rang) > meilleur.rang then meilleur = { cle = cle, rang = tonumber(m.rang) } end
            end
        end
        table.sort(tous, function(a, b) return a.valeur > b.valeur end)
        local ligne = { ligne = metier, nom = nom, meilleur = meilleur, tous = tous, paliers = {} }
        for _, palier in ipairs(PALIERS_METIER) do
            table.insert(ligne.paliers, { palier = palier, fait = meilleur and meilleur.rang >= palier or false })
        end
        table.insert(r.metiers, ligne)
    end
    return r
end

-- ---------------------------------------------------------------------------
-- Temps de jeu par niveau, et chronologie du compte
-- ---------------------------------------------------------------------------
-- Le jeu donne, sur demande, le temps de jeu total et celui passe au niveau
-- actuel : leur difference est le temps de jeu au moment ou ce niveau a ete
-- atteint. Garde pour chaque niveau, le temps passe sur un niveau en decoule.
-- Rien n'existe avant l'installation : les niveaux plus anciens restent
-- inconnus. Chaque passage de niveau entre dans la chronologie.

local function Temps(cle)
    local d = LegacyCoreDB
    if type(d) ~= "table" or not cle then return nil end
    d.temps = type(d.temps) == "table" and d.temps or {}
    local t = d.temps[cle]
    if type(t) ~= "table" then t = { debuts = {} } d.temps[cle] = t end
    t.debuts = type(t.debuts) == "table" and t.debuts or {}
    return t
end

function base.NoterTempsDeJeu(total, ceNiveau)
    total, ceNiveau = tonumber(total), tonumber(ceNiveau)
    local cle = NS.ClePersonnage()
    local niveau = tonumber(NS.Appeler(UnitLevel, "player"))
    local t = Temps(cle)
    if not (t and total and ceNiveau and niveau) then return end
    t.debuts[niveau] = total - ceNiveau
    t.total, t.ceNiveau, t.niveau, t.quand = total, ceNiveau, niveau, NS.Appeler(time)
end

function base.NoterNiveau(niveau)
    local d = LegacyCoreDB
    local cle = NS.ClePersonnage()
    niveau = tonumber(niveau)
    if type(d) ~= "table" or not cle or not niveau then return end
    d.chrono = type(d.chrono) == "table" and d.chrono or {}
    local _, classe = NS.Appeler(UnitClass, "player")
    table.insert(d.chrono, { quand = NS.Appeler(time), cle = cle, classe = classe, genre = "niveau", niveau = niveau })
    while #d.chrono > 500 do table.remove(d.chrono, 1) end
end

-- Pour un personnage : { [niveau] = secondes } (niveaux termines et connus),
-- le niveau actuel et le temps deja passe dessus, le temps de jeu total.
function base.TempsParNiveau(cle)
    local d = LegacyCoreDB
    local t = type(d) == "table" and type(d.temps) == "table" and d.temps[cle]
    local r = { durees = {} }
    if type(t) ~= "table" then return r end
    for niveau, debut in pairs(t.debuts or {}) do
        local suivant = t.debuts[niveau + 1]
        if suivant and suivant >= debut then r.durees[niveau] = suivant - debut end
    end
    r.niveau, r.enCours, r.total, r.quand = t.niveau, t.ceNiveau, t.total, t.quand
    return r
end

-- Les evenements de tous les personnages, le plus recent d'abord.
function base.Chronologie()
    local d = LegacyCoreDB
    local liste = {}
    for _, e in ipairs(type(d) == "table" and type(d.chrono) == "table" and d.chrono or {}) do
        if type(e) == "table" and e.quand then table.insert(liste, e) end
    end
    table.sort(liste, function(a, b) return a.quand > b.quand end)
    return liste
end

-- "3 j 4 h", "2 h 05", "45 min".
function NS.Duree(secondes)
    secondes = math.max(0, math.floor(tonumber(secondes) or 0))
    local j, h, m = math.floor(secondes / 86400), math.floor(secondes / 3600) % 24, math.floor(secondes / 60) % 60
    if j > 0 then return string.format(NS.L.DUR_DAYS, j, h) end
    if h > 0 then return string.format(NS.L.DUR_HOURS, h, m) end
    return string.format(NS.L.DUR_MINUTES, math.max(m, secondes > 0 and 1 or 0))
end

-- Ouvre la fenetre d'heritage du jeu (pour depenser les points) : par le
-- raccourci du jeu qui l'ouvre, sinon par sa fonction d'ouverture.
function NS.OuvrirHeritageDuJeu()
    -- Comme la touche du jeu : la fonction que l'interface d'heritage de
    -- WoW Forever donne elle-meme (Blizzard_LegacySystem, ToggleLegacySystemUI),
    -- puis la page des arbres (onglet 3). Rien d'autre n'est appele : ni
    -- touche simulee, ni chargement d'add-on du jeu a la main.
    if NS.Appeler(_G.InCombatLockdown) then return false end
    local cadre = _G.LegacySystemFrame
    if not (cadre and cadre.IsShown and cadre:IsShown()) then
        local basculer = _G.ToggleLegacySystemUI
        if type(basculer) ~= "function" then return false end
        local ok = pcall(basculer)
        if not ok then return false end
        cadre = _G.LegacySystemFrame
    end
    if not (cadre and cadre.IsShown and cadre:IsShown()) then return false end
    local registre = _G.EventRegistry
    if registre and registre.TriggerEvent then pcall(registre.TriggerEvent, registre, "Legacy.SelectPage", 3) end
    return true
end

-- La touche qui ouvre l'heritage dans les raccourcis du joueur, ou nil.
function NS.ToucheHeritage()
    local nombre = NS.Appeler(_G.GetNumBindings) or 0
    for i = 1, nombre do
        local commande, _, touche = NS.Appeler(_G.GetBinding, i)
        if type(commande) == "string" and string.find(string.upper(commande), "LEGACY") and type(touche) == "string" then
            local lisible = NS.Appeler(_G.GetBindingText, touche) or touche
            return lisible
        end
    end
    return nil
end


-- ---------------------------------------------------------------------------
-- Ouvrir l'heritage sans toucher a l'interface du jeu : un bouton securise
-- du jeu (SecureActionButtonTemplate, type "click") clique le bouton
-- Heritage du micro-menu (LegacyMicroButton), comme le joueur le ferait.
-- Il est pose a l'ecran, sans ancrage, par-dessus le bouton de LegacyCore ;
-- il disparait des le combat (rien ne bouge alors) et quand on ne le voit pas.
-- ---------------------------------------------------------------------------

local securise, cible
local function Securise()
    if securise then return securise end
    if NS.Appeler(_G.InCombatLockdown) or not _G.LegacyMicroButton then return nil end
    local ok, b = pcall(CreateFrame, "Button", "LegacyCoreHeritageSecurise", UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return nil end
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "click")
    b:SetAttribute("clickbutton", _G.LegacyMicroButton)
    b:SetFrameStrata("DIALOG")
    local surbrillance = b:CreateTexture(nil, "HIGHLIGHT")
    surbrillance:SetAllPoints()
    surbrillance:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    surbrillance:SetTexCoord(0, 0.625, 0, 0.6875)
    surbrillance:SetBlendMode("ADD")
    b:Hide()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then b:Hide()
        elseif cible and NS.PoserHeritageSecurise then NS.PoserHeritageSecurise(cible.bouton, cible.actif) end
    end)
    securise = b
    return b
end

local function Placer()
    local b = securise
    if not b or NS.Appeler(_G.InCombatLockdown) then return end
    local v = cible and cible.bouton
    if not (cible and cible.actif and v and v:IsVisible()) then b:Hide() return end
    local l, bas, w, h = v:GetLeft(), v:GetBottom(), v:GetWidth(), v:GetHeight()
    if not (l and bas and w and h) then b:Hide() return end
    local k = v:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bas * k)
    b:SetSize(w * k, h * k)
    b:Show()
end

function NS.PoserHeritageSecurise(bouton, actif)
    cible = { bouton = bouton, actif = actif }
    local b = Securise()
    if not b then return end
    if not bouton.heritageSuivi then
        -- Le bouton visible bouge (defilement, fenetre) ou se cache : le
        -- bouton securise suit, hors combat.
        bouton.heritageSuivi = true
        bouton:HookScript("OnHide", function() if securise and not NS.Appeler(_G.InCombatLockdown) then securise:Hide() end end)
        local suivi = CreateFrame("Frame", nil, bouton)
        local attente = 0
        suivi:SetScript("OnUpdate", function(_, e)
            attente = attente - (e or 0)
            if attente > 0 then return end
            attente = 0.2
            Placer()
        end)
    end
    Placer()
end
