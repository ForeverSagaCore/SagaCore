local _, NS = ...

-- Mes modeles de talents : enregistrer la simulation (nom, activite),
-- l'exporter en code a copier, importer un code ou un lien de calculateur
-- (wowforevertalent, talentsforever, Warcraft Tavern), partager un modele
-- avec sa guilde ou son groupe (canal invisible des add-ons, sur clic du
-- joueur seulement) et garder ceux recus. Rien ne s'ajoute sans clic.
--
-- ClassCoreDB.mesModeles[classe] = { { nom, activite, code, quand } }
-- ClassCoreDB.modelesRecus[classe] = { { nom, activite, code, auteur, quand } }
-- code : l'ordre des points (voir Data/Modeles.lua).

NS.mesModeles = {}
local M = NS.mesModeles
local T = NS.T

local PREFIXE = "ClassCore"
local MAX_RECUS = 30
local LIEN_PROPOSER = "github.com/ForeverSagaCore/SagaCore/issues"

local function Ta() return NS.talents end

local function Base()
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    return ClassCoreDB
end

local function Liste(cle, classe)
    local db = Base()
    db[cle] = type(db[cle]) == "table" and db[cle] or {}
    db[cle][classe or ""] = type(db[cle][classe or ""]) == "table" and db[cle][classe or ""] or {}
    return db[cle][classe or ""]
end

local function Dire(texte) print("|cffffd100ClassCore|r " .. texte) end

local function Propre(nom)
    nom = tostring(nom or ""):gsub("[|;\n\r]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #nom > 40 then nom = nom:sub(1, 40) end
    return nom
end

local function CodeValide(code)
    return type(code) == "string" and #code > 0 and #code <= 160 and code:match("^[A-Ca-z0-9]+$") ~= nil
end

-- Pour Ta.Modeles : mes modeles puis ceux recus, chacun avec sa cle.
function M.Liste(classe)
    local l = {}
    for i, e in ipairs(Liste("mesModeles", classe)) do
        table.insert(l, { m = { code = e.code, nom = e.nom, activite = "mes", sousActivite = e.activite }, cle = "mes:" .. i, index = i })
    end
    for i, e in ipairs(Liste("modelesRecus", classe)) do
        table.insert(l, { m = { code = e.code, nom = e.nom, activite = "recus", auteur = e.auteur, sousActivite = e.activite }, cle = "recu:" .. i, index = i })
    end
    return l
end

local function Rafraichir()
    local F = NS.fenetre
    if F and F.w and F.w.Rendre then pcall(F.w.Rendre) end
end

-- La simulation en cours : structure, classe, ordre des points.
local function Simulation()
    local ta = Ta()
    local s = ta and ta.sim and ta.sim.structure
    if not s then return nil end
    local suite = ta.OrdreSimulation(s)
    return s, ta.sim.classe, suite
end

-- ---------------------------------------------------------------------------
-- La fenetre de dialogue (au-dessus de tout) : un titre, une explication,
-- un champ de texte, une liste d'activites (facultative), deux boutons.
-- ---------------------------------------------------------------------------

local dlg
local function Dialogue()
    if dlg then return dlg end
    local ok, f = pcall(CreateFrame, "Frame", "ClassCoreDialogueModele", UIParent, "BackdropTemplate")
    if not ok or not f then f = CreateFrame("Frame", "ClassCoreDialogueModele", UIParent) end
    f:SetSize(640, 170)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.titre:SetPoint("TOP", f, "TOP", 0, -18)
    f.texte = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.texte:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -42)
    f.texte:SetPoint("RIGHT", f, "RIGHT", -22, 0)
    f.texte:SetJustifyH("LEFT")
    f.texte:SetWordWrap(false)
    f.champ = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.champ:SetSize(584, 22)
    f.champ:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -66)
    f.champ:SetAutoFocus(false)
    f.champ:SetMaxLetters(400)
    f.champ:SetScript("OnEscapePressed", function() f:Hide() end)
    f.champ:SetScript("OnEnterPressed", function() if f.ok:IsEnabled() then f.ok:Click() end end)
    f.ligneActivite = CreateFrame("Frame", nil, f)
    f.ligneActivite:SetSize(590, 26)
    f.ligneActivite:SetPoint("TOPLEFT", f.champ, "BOTTOMLEFT", -6, -8)
    f.libActivite = f.ligneActivite:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.libActivite:SetPoint("LEFT", f.ligneActivite, "LEFT", 6, 0)
    f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.ok:SetSize(120, 22)
    f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
    f.annuler = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.annuler:SetSize(120, 22)
    f.annuler:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 18)
    f.annuler:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    table.insert(UISpecialFrames, "ClassCoreDialogueModele")
    dlg = f
    return f
end

-- o = { titre, texte, valeur, selectionner, activite (valeur de depart, ou
-- nil : pas de liste), ok, annuler, auValider(texte, activite) }
local function Ouvrir(o)
    local f = Dialogue()
    f.titre:SetText(o.titre or "")
    f.texte:SetText(o.texte or "")
    f.champ:SetText(o.valeur or "")
    f.activite = o.activite
    if o.activite then
        f.libActivite:SetText(T("Activité", "Activity"))
        local S = _G.CoreSuite
        if S and S.ListeDeroulante and not f.liste then
            local ta = Ta()
            local options = {}
            for _, a in ipairs({ "solo", "donjons", "groupe", "jce", "jcj", "farm" }) do
                table.insert(options, { a, ta.ACTIVITES[a]() })
            end
            local okL, li = pcall(S.ListeDeroulante, f.ligneActivite, options,
                function() return f.activite end, function(v) f.activite = v end)
            if okL and li then
                li:SetPoint("RIGHT", f.ligneActivite, "RIGHT", 0, 0)
                f.liste = li
            end
        end
        if f.liste and f.liste.Rendre then pcall(f.liste.Rendre) end
        f.ligneActivite:Show()
    else
        f.ligneActivite:Hide()
    end
    f.ok:SetText(o.ok or T("Valider", "OK"))
    f.annuler:SetText(o.annuler or T("Annuler", "Cancel"))
    f.ok:SetShown(o.auValider ~= nil)
    f.ok:SetScript("OnClick", function()
        if o.auValider then
            local fermer = o.auValider(f.champ:GetText(), f.activite)
            if fermer ~= false then f:Hide() end
        end
    end)
    f:Show()
    f:Raise()
    f.champ:SetFocus()
    if o.selectionner then f.champ:HighlightText() end
end

-- ---------------------------------------------------------------------------
-- Enregistrer, supprimer, garder
-- ---------------------------------------------------------------------------

function M.Enregistrer(nomDeDepart, activiteDeDepart)
    local s, classe, suite = Simulation()
    if not s or #suite == 0 then Dire(T("Place d'abord des points dans la simulation.", "Place some points in the simulation first.")) return end
    local code = Ta().Coder(suite)
    if not code then Dire(T("Cet arbre ne peut pas s'enregistrer.", "This tree cannot be saved.")) return end
    Ouvrir({ titre = T("Enregistrer le modèle", "Save the build"),
        texte = T("Son nom et son activité. Il rejoint « Mes modèles », pour tous tes personnages de cette classe.",
            "Its name and activity. It joins « My builds », for all your characters of this class."),
        valeur = nomDeDepart or "", activite = activiteDeDepart or "solo", ok = T("Enregistrer", "Save"),
        auValider = function(texte, activite)
            local nom = Propre(texte)
            if nom == "" then Dire(T("Donne-lui un nom.", "Give it a name.")) return false end
            local l = Liste("mesModeles", classe)
            table.insert(l, { nom = nom, activite = activite or "solo", code = code, quand = time and time() or 0 })
            local ta = Ta()
            ta.choix[classe or ""] = { activite = "mes", cle = "mes:" .. #l }
            Dire(string.format(T("modèle « %s » enregistré.", "build « %s » saved."), nom))
            Rafraichir()
        end })
end

function M.Supprimer(m)
    local classe = Ta().sim.classe or (NS.fenetre and NS.fenetre.Profil() or {}).classe
    local cle = m.modele.activite == "recus" and "modelesRecus" or "mesModeles"
    local l = Liste(cle, classe)
    if m.index and l[m.index] then
        local nom = l[m.index].nom
        table.remove(l, m.index)
        Ta().choix[classe or ""] = {}
        Dire(string.format(T("modèle « %s » supprimé.", "build « %s » deleted."), nom or "?"))
    end
    Rafraichir()
end

function M.Garder(m)
    local classe = Ta().sim.classe or (NS.fenetre and NS.fenetre.Profil() or {}).classe
    local recus = Liste("modelesRecus", classe)
    local e = m.index and recus[m.index]
    if not e then return end
    local l = Liste("mesModeles", classe)
    table.insert(l, { nom = e.nom, activite = e.activite or "solo", code = e.code, auteur = e.auteur, quand = time and time() or 0 })
    table.remove(recus, m.index)
    Ta().choix[classe or ""] = { activite = "mes", cle = "mes:" .. #l }
    Dire(string.format(T("modèle « %s » gardé dans Mes modèles.", "build « %s » kept in My builds."), e.nom or "?"))
    Rafraichir()
end

-- ---------------------------------------------------------------------------
-- Exporter, importer
-- ---------------------------------------------------------------------------

-- Code d'echange : CCM1;CLASSE;activite;nom;ordre
local function CodeEchange(classe, activite, nom, code)
    return "CCM1;" .. tostring(classe) .. ";" .. tostring(activite or "solo") .. ";" .. Propre(nom) .. ";" .. code
end

function M.Exporter()
    local s, classe, suite = Simulation()
    if not s or #suite == 0 then Dire(T("Place d'abord des points dans la simulation.", "Place some points in the simulation first.")) return end
    local code = Ta().Coder(suite)
    if not code then return end
    local c = Ta().choix[classe or ""] or {}
    local nom, activite = T("Mon modèle", "My build"), c.activite
    -- Le modele choisi, s'il est exactement la simulation : son nom et son activite.
    local choisi = Ta().pageActive and Ta().pageActive.modeleChoisi
    if choisi and choisi.modele and choisi.modele.code == code then
        nom = choisi.modele.nom or nom
        activite = choisi.modele.sousActivite or activite
    end
    if activite == "mes" or activite == "recus" or not activite then activite = "solo" end
    Ouvrir({ titre = T("Exporter la simulation", "Export the simulation"),
        texte = string.format(T("Copie ce code (Cmd+C). Pour le proposer à tous : %s, « Proposer un modèle ».",
            "Copy this code (Cmd+C). To suggest it to everyone : %s, « Suggest a build »."), LIEN_PROPOSER),
        valeur = CodeEchange(classe, activite, nom, code), selectionner = true,
        annuler = T("Fermer", "Close") })
end

local CLASSES = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }

-- Un code ou un lien : { classe, activite, nom, code (ordre) } ou { classe, rangs }.
local function Lire(texte)
    texte = tostring(texte or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if texte == "" then return nil end
    local classe, activite, nom, code = texte:match("^CCM1;(%u+);(%w+);([^;]*);([%w]+)$")
    if classe then return { classe = classe, activite = activite, nom = nom, code = code } end
    local bas = texte:lower()
    -- Warcraft Tavern : .../talent-calculator/<classe>#?t=<ordre>
    local cl, ordre = texte:match("talent%-calculator/(%a+)#%?t=([%w]+)")
    if cl then return { classe = CLASSES[cl:lower()], code = ordre } end
    -- talentsforever : .../<classe>/<niveau>/<rangs>-<version>
    cl, code = bas:match("talentsforever%.com/(%a+)/%d+/([%d%-]+)")
    if cl then
        local rangs = code:match("^(.*)%-%d+$") or code
        return { classe = CLASSES[cl], rangs = rangs }
    end
    -- wowforevertalent : ...~<classe>~<niveau>~<rangs>
    cl, code = bas:match("~(%a+)~%d+~([%d%-]+)")
    if cl then return { classe = CLASSES[cl], rangs = code } end
    if texte:match("^[%d%-]+$") then return { rangs = texte } end
    if texte:match("^[A-C][%w]+$") then return { code = texte } end
    return nil
end

function M.Importer()
    local s, classe = Simulation()
    if not s then Dire(T("Ouvre la simulation d'abord.", "Open the simulation first.")) return end
    Ouvrir({ titre = T("Importer un modèle", "Import a build"),
        texte = T("Colle un code ClassCore ou un lien wowforevertalent, talentsforever ou Warcraft Tavern (Cmd+V).",
            "Paste a ClassCore code or a wowforevertalent, talentsforever or Warcraft Tavern link (Cmd+V)."),
        valeur = "", ok = T("Importer", "Import"),
        auValider = function(texte)
            local e = Lire(texte)
            if not e then Dire(T("code ou lien non reconnu.", "code or link not recognised.")) return false end
            if e.classe and e.classe ~= classe then
                Dire(T("ce modèle est pour une autre classe : ouvre un personnage de cette classe.", "this build is for another class : open a character of that class."))
                return false
            end
            local ta = Ta()
            local suite, raison
            if e.code then suite, raison = ta.Decoder(s, e.code) else suite, raison = ta.DecoderRangs(s, e.rangs) end
            if not suite then
                Dire(string.format(T("ce modèle ne va pas à l'arbre du jeu (%s).", "this build does not fit the game's tree (%s)."), tostring(raison)))
                return false
            end
            ta.ChargerModele({ suite = suite }, classe)
            if ta.pageActive then ta.pageActive.mode = "simulation" end
            Rafraichir()
            -- Puis l'enregistrer, nom et activite deja remplis s'ils sont connus.
            M.Enregistrer(e.nom or T("Modèle importé", "Imported build"), e.activite)
            return false
        end })
end

-- ---------------------------------------------------------------------------
-- Partage en jeu (guilde, sinon groupe), sur clic du joueur
-- ---------------------------------------------------------------------------

function M.CanalDePartage()
    if IsInGuild and IsInGuild() then return "GUILD" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function Envoyer(message, canal)
    local C = _G.C_ChatInfo
    local envoyer = C and C.SendAddonMessage or _G.SendAddonMessage
    if not envoyer then return false end
    return pcall(envoyer, PREFIXE, message, canal)
end

function M.Partager(m)
    local canal = M.CanalDePartage()
    if not canal then Dire(T("ni guilde ni groupe : personne avec qui partager.", "no guild nor group : nobody to share with.")) return end
    local code = m.modele.code
    if not CodeValide(code) then return end
    local classe = Ta().sim.classe or (NS.fenetre and NS.fenetre.Profil() or {}).classe
    local message = "M1;" .. tostring(classe) .. ";" .. tostring(m.modele.sousActivite or "solo") .. ";" .. Propre(m.modele.nom) .. ";" .. code
    if #message > 250 then Dire(T("modèle trop long pour être partagé.", "build too long to share.")) return end
    if Envoyer(message, canal) then
        local qui = canal == "GUILD" and T("ta guilde", "your guild") or T("ton groupe", "your group")
        Dire(string.format(T("modèle « %s » partagé avec %s.", "build « %s » shared with %s."), m.modele.nom or "?", qui))
    end
end

do
    local f = CreateFrame("Frame")
    local C = _G.C_ChatInfo
    if C and C.RegisterAddonMessagePrefix then pcall(C.RegisterAddonMessagePrefix, PREFIXE)
    elseif _G.RegisterAddonMessagePrefix then pcall(_G.RegisterAddonMessagePrefix, PREFIXE) end
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefixe, message, _, auteur)
        if prefixe ~= PREFIXE or type(message) ~= "string" then return end
        local classe, activite, nom, code = message:match("^M1;(%u+);(%w+);([^;]*);([%w]+)$")
        if not classe or not CodeValide(code) then return end
        local moi = UnitName and UnitName("player")
        local court = tostring(auteur or "?"):match("^([^%-]+)") or "?"
        if moi and court == moi then return end
        local l = Liste("modelesRecus", classe)
        for _, e in ipairs(l) do if e.code == code then return end end
        table.insert(l, 1, { nom = Propre(nom), activite = activite, code = code, auteur = court, quand = time and time() or 0 })
        while #l > MAX_RECUS do table.remove(l) end
        Dire(string.format(T("modèle de talents « %s » reçu de %s : page Talents, Modèles reçus.", "talent build « %s » received from %s : Talents page, Received builds."), Propre(nom), court))
    end)
end
