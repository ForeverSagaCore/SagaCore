local _, NS = ...

-- Messages de la suite dans la discussion du jeu.
--
-- Le meme fichier dans chaque add-on de la suite ; la version la plus recente
-- gagne (comme Suite.lua). Chaque add-on y declare ses messages types ; quand
-- une situation se produit, il appelle Dire. Le message part :
--   - au nom de l'add-on, entre crochets, dans sa couleur, avec son icone ;
--   - avec le texte du joueur s'il l'a reecrit, sinon le texte d'origine ;
--   - suivi de mots cliquables ([Oui], [Guider]...) qui lancent l'action ;
--   - dans l'onglet SagaCore, la discussion generale, les deux ou nulle part.
-- Pas d'IA : des situations reconnues et des textes prets. Rien en combat
-- (sauf l'urgent) : le message attend la fin du combat. Un meme message ne
-- revient pas avant son delai.

local VERSION = 3

local M = _G.SagaCoreMessages
if M and (M.version or 0) >= VERSION then
    NS.messages = M
    return
end
M = M or { defs = {}, ordre = {} }
M.version = VERSION
_G.SagaCoreMessages = M
NS.messages = M

M.ADDONS = {
    QuestCore = { couleur = "4fa3ff", icone = "Interface\\Icons\\INV_Misc_Book_08" },
    CraftCore = { couleur = "ff9a2e", icone = "Interface\\Icons\\INV_Misc_Gear_01" },
    MapCore = { couleur = "5fd35f", icone = "Interface\\Icons\\INV_Misc_Map_01" },
    LegacyCore = { couleur = "b57cff", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    TradeCore = { couleur = "ffd100", icone = "Interface\\Icons\\INV_Misc_Coin_02" },
}
local NOM_ONGLET = "SagaCore"
local DESTINATIONS = { "onglet", "general", "deux", "rien" }

-- ---------------------------------------------------------------------------
-- Textes de la fenetre (francais ou anglais : les messages eux-memes sont
-- donnes par chaque add-on dans sa langue)
-- ---------------------------------------------------------------------------

local TEXTES = {
    frFR = {
        titre = "Messages dans la discussion",
        intro = "Ce que la suite vous dit dans la discussion, et où.",
        onglet = "Onglet SagaCore", general = "Discussion générale", deux = "Les deux", rien = "Nulle part",
        ongletOuvert = "Onglet SagaCore dans la discussion",
        oui = "Oui", non = "Non",
        actif = "Actif", inactif = "Coupé",
        ou = "Où : %s",
        texte = "Texte du message :",
        origine = "Texte d'origine",
        essai = "Essayer",
        valeurs = "Valeurs possibles : %s",
        aucune = "aucune",
        fermer = "Fermer",
        rienAFaire = "Plus rien à faire pour ce message.",
        aide = "Les mots cliquables s'ajoutent toujours après le texte. À la manette : /sagacore oui répond au dernier message.",
    },
    enUS = {
        titre = "Chat messages",
        intro = "What the suite tells you in the chat, and where.",
        onglet = "SagaCore tab", general = "General chat", deux = "Both", rien = "Nowhere",
        ongletOuvert = "SagaCore tab in the chat",
        oui = "Yes", non = "No",
        actif = "On", inactif = "Off",
        ou = "Where : %s",
        texte = "Message text :",
        origine = "Original text",
        essai = "Try",
        valeurs = "Possible values : %s",
        aucune = "none",
        fermer = "Close",
        rienAFaire = "Nothing left to do for this message.",
        aide = "Clickable words are always added after the text. With a gamepad : /sagacore yes answers the last message.",
    },
}
local function TX(cle)
    local S = _G.CoreSuite
    local langue = S and S.Langue and S.Langue() or "enUS"
    local t = TEXTES[langue] or TEXTES.enUS
    return t[cle] or TEXTES.enUS[cle] or cle
end
M.TX = TX

-- ---------------------------------------------------------------------------
-- Reglages (CoreSuiteDB.messages, communs au compte)
-- ---------------------------------------------------------------------------

local function Base()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    local d = CoreSuiteDB.messages
    if type(d) ~= "table" then d = {} CoreSuiteDB.messages = d end
    d.reglages = type(d.reglages) == "table" and d.reglages or {}
    d.ongletCree = type(d.ongletCree) == "table" and d.ongletCree or {}
    if d.onglet == nil then d.onglet = true end
    return d
end

local function Reglage(addon, cle)
    local r = Base().reglages
    local k = addon .. ":" .. cle
    r[k] = type(r[k]) == "table" and r[k] or {}
    return r[k]
end
M.Reglage = Reglage

local function Def(addon, cle)
    local d = M.defs[addon]
    return d and d[cle]
end

-- Declare les messages d'un add-on : liste de
-- { cle, libelle (pour les reglages), texte (d'origine), valeurs = {"niveau", ...},
--   delai (secondes avant de pouvoir revenir), urgent, ou (destination par defaut) }.
function M.Definir(addon, liste)
    M.defs[addon] = {}
    M.ordre[addon] = {}
    for _, def in ipairs(liste or {}) do
        M.defs[addon][def.cle] = def
        table.insert(M.ordre[addon], def.cle)
    end
end

function M.Texte(addon, cle)
    local def = Def(addon, cle)
    local r = Reglage(addon, cle)
    if type(r.texte) == "string" and r.texte ~= "" then return r.texte end
    return def and def.texte or ""
end

function M.Destination(addon, cle)
    local r = Reglage(addon, cle)
    local def = Def(addon, cle)
    return r.ou or (def and def.ou) or "onglet"
end

function M.Actif(addon, cle)
    return Reglage(addon, cle).coupe ~= true
end

-- ---------------------------------------------------------------------------
-- L'onglet SagaCore
-- ---------------------------------------------------------------------------

local function ClePerso()
    local nom = UnitName and UnitName("player")
    local royaume = GetRealmName and GetRealmName()
    if not nom or not royaume then return nil end
    return nom .. " - " .. royaume
end

local function CadreOnglet()
    for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do
        local ok, nom, _, _, _, _, _, visible, _, docke = pcall(GetChatWindowInfo, i)
        local cadre = _G["ChatFrame" .. i]
        if ok and nom == NOM_ONGLET and cadre and (visible or docke) then return cadre end
    end
    return nil
end
M.CadreOnglet = CadreOnglet

-- Ouvre l'onglet une fois par personnage (les fenetres de discussion sont
-- propres a chacun). Ferme par le joueur, il ne revient pas tout seul.
function M.PreparerOnglet(force)
    local d = Base()
    if not d.onglet then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local cle = ClePerso()
    if not cle or (d.ongletCree[cle] and not force) then return end
    if CadreOnglet() then d.ongletCree[cle] = true return end
    local ouvrir = _G.FCF_OpenNewWindow
    if type(ouvrir) ~= "function" then return end
    local ok, cadre = pcall(ouvrir, NOM_ONGLET)
    if ok and cadre then
        -- Seulement la suite : aucun canal, aucun groupe de messages du jeu.
        if _G.ChatFrame_RemoveAllMessageGroups then pcall(_G.ChatFrame_RemoveAllMessageGroups, cadre) end
        if _G.ChatFrame_RemoveAllChannels then pcall(_G.ChatFrame_RemoveAllChannels, cadre) end
        d.ongletCree[cle] = true
        -- La discussion generale reste au premier plan.
        if _G.FCF_SelectDockFrame and _G.DEFAULT_CHAT_FRAME then pcall(_G.FCF_SelectDockFrame, _G.DEFAULT_CHAT_FRAME) end
    end
end

-- ---------------------------------------------------------------------------
-- Mots cliquables
-- ---------------------------------------------------------------------------

M.actions = M.actions or {}
M.compteur = M.compteur or 0
local function Lien(libelle, fn)
    M.compteur = M.compteur + 1
    local id = M.compteur
    M.actions[id] = fn
    -- On ne garde que les plus recents.
    M.actions[id - 200] = nil
    return "|cffffd100|Haddon:sagacore:" .. id .. "|h[" .. libelle .. "]|h|r", id
end

function M.Agir(id)
    local fn = M.actions[tonumber(id)]
    if type(fn) ~= "function" then
        print("|cffffd100SagaCore|r " .. TX("rienAFaire"))
        return
    end
    M.actions[tonumber(id)] = nil
    if M.derniere and M.derniere.oui == tonumber(id) then M.derniere = nil end
    local ok, souci = pcall(fn)
    if not ok and _G.CoreSuite and _G.CoreSuite.Prive and _G.CoreSuite.Prive() then
        print("|cffffd100SagaCore|r erreur : " .. tostring(souci))
    end
end

-- Le clic sur un lien "addon:sagacore:<n>". Le jeu reconnait lui-meme les
-- liens "addon:" et les signale par l'evenement SetItemRef : on l'ecoute,
-- sans jamais remplacer une fonction du jeu (ce qui "salirait" l'interface
-- et bloquerait les barres d'action de la manette).
if not M.lienPose then
    M.lienPose = true
    local function SurLien(_, lien)
        if type(lien) ~= "string" then return end
        local id = lien:match("^addon:sagacore:(%d+)")
        if id then M.Agir(id) end
    end
    local registre = _G.EventRegistry
    if registre and registre.RegisterCallback then
        pcall(registre.RegisterCallback, registre, "SetItemRef", SurLien, M)
    elseif _G.hooksecurefunc and type(_G.SetItemRef) == "function" then
        pcall(_G.hooksecurefunc, "SetItemRef", function(lien) SurLien(nil, lien) end)
    end
end

-- /sagacore oui (ou non) : la reponse au dernier message qui pose une question.
function M.Repondre(oui)
    local q = M.derniere
    if not q then print("|cffffd100SagaCore|r " .. TX("rienAFaire")) return end
    local id = oui and q.oui or q.non
    M.derniere = nil
    if id then M.Agir(id) end
end

-- ---------------------------------------------------------------------------
-- Dire
-- ---------------------------------------------------------------------------

M.vus = M.vus or {}
M.enAttente = M.enAttente or {}

local function Remplir(texte, valeurs)
    return (string.gsub(texte, "{(%w+)}", function(nom)
        local v = valeurs and valeurs[nom]
        if v == nil then return "{" .. nom .. "}" end
        return tostring(v)
    end))
end

local function Ecrire(cadre, ligne)
    if cadre and cadre.AddMessage then cadre:AddMessage(ligne) end
end

-- addon, cle : le message declare ; valeurs : { nom = valeur } pour le texte ;
-- actions : { { libelle, fonction }, ... } (la premiere repond Oui, une
-- action nommee "non" repond Non) ; unique : ce qui distingue deux messages
-- du meme type (une quete, un metier) pour le delai.
function M.Dire(addon, cle, valeurs, actions, unique)
    local def = Def(addon, cle)
    if not def or not M.Actif(addon, cle) then return false end
    local ou = M.Destination(addon, cle)
    if ou == "rien" then return false end
    local k = addon .. ":" .. cle .. ":" .. tostring(unique or "")
    local maintenant = GetTime and GetTime() or 0
    if M.vus[k] and maintenant - M.vus[k] < (def.delai or 600) then return false end
    if not def.urgent and InCombatLockdown and InCombatLockdown() then
        M.enAttente[k] = { addon, cle, valeurs, actions, unique }
        return false
    end
    M.vus[k] = maintenant
    local info = M.ADDONS[addon] or { couleur = "ffd100" }
    local ligne = (info.icone and ("|T" .. info.icone .. ":14:14:0:0|t ") or "")
        .. "|cff" .. info.couleur .. "[" .. addon .. "]|r |cffffffff" .. Remplir(M.Texte(addon, cle), valeurs) .. "|r"
    local question
    for rang, a in ipairs(actions or {}) do
        local lien, id = Lien(a[1], a[2])
        ligne = ligne .. " " .. lien
        question = question or {}
        if rang == 1 then question.oui = id end
        if a.non then question.non = id end
    end
    if question then M.derniere = question end
    local onglet = CadreOnglet()
    if ou == "onglet" or ou == "deux" then Ecrire(onglet or _G.DEFAULT_CHAT_FRAME, ligne) end
    if (ou == "general" or ou == "deux") and _G.DEFAULT_CHAT_FRAME ~= onglet then Ecrire(_G.DEFAULT_CHAT_FRAME, ligne) end
    return true
end

-- Un essai avec des valeurs d'exemple, depuis les reglages.
function M.Essayer(addon, cle)
    local def = Def(addon, cle)
    if not def then return end
    local valeurs = {}
    for _, v in ipairs(def.valeurs or {}) do valeurs[v] = def.exemples and def.exemples[v] or ("<" .. v .. ">") end
    M.vus[addon .. ":" .. cle .. ":essai"] = nil
    local actions
    if def.actions then
        actions = {}
        for _, libelle in ipairs(def.actions) do table.insert(actions, { libelle, function() end }) end
    end
    M.Dire(addon, cle, valeurs, actions, "essai")
    M.vus[addon .. ":" .. cle .. ":essai"] = nil
end

local cadre = M.cadre or CreateFrame("Frame")
M.cadre = cadre
cadre:RegisterEvent("PLAYER_ENTERING_WORLD")
cadre:RegisterEvent("PLAYER_REGEN_ENABLED")
cadre:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_ENTERING_WORLD" then
        if _G.C_Timer then _G.C_Timer.After(4, function() pcall(M.PreparerOnglet) end) end
    elseif ev == "PLAYER_REGEN_ENABLED" then
        local attente = M.enAttente
        M.enAttente = {}
        for _, m in pairs(attente) do pcall(M.Dire, m[1], m[2], m[3], m[4], m[5]) end
    end
end)

-- ---------------------------------------------------------------------------
-- Fenetre des reglages : un add-on a la fois, ses messages en liste, le
-- message choisi en detail dessous. Manette : haut / bas, A, B pour fermer,
-- LB / RB pour changer d'add-on.
-- ---------------------------------------------------------------------------

local LARGEUR, HAUTEUR = 560, 600
local LIGNES = 8

local function Bouton(parent, largeur, texte)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(largeur, 22)
    b:SetText(texte or "")
    return b
end

local function AddonsDeclares()
    local liste = {}
    local S = _G.CoreSuite
    for _, info in ipairs(S and S.ORDRE or {}) do
        if M.ordre[info.cle] and #M.ordre[info.cle] > 0 then table.insert(liste, info.cle) end
    end
    return liste
end

local function Fenetre()
    local f = M.fenetre
    if f then return f end
    local S = _G.CoreSuite
    local charte = NS.charte
    if charte and charte.Fenetre then
        f = charte.Fenetre("SagaCoreMessages", LARGEUR, HAUTEUR, { portrait = false })
    else
        f = CreateFrame("Frame", "SagaCoreMessages", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(LARGEUR, HAUTEUR)
    end
    -- Devant tout : au-dessus des fenetres de la suite, qui passent dans
    -- l'ombre derriere un voile sombre tant qu'elle est ouverte.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(120)
    f:SetPoint("CENTER")
    f:SetToplevel(true)
    local voile = CreateFrame("Frame", nil, UIParent)
    voile:SetAllPoints(UIParent)
    voile:SetFrameStrata("FULLSCREEN_DIALOG")
    voile:SetFrameLevel(110)
    voile:EnableMouse(true)
    voile.fond = voile:CreateTexture(nil, "BACKGROUND")
    voile.fond:SetAllPoints()
    voile.fond:SetColorTexture(0, 0, 0, 0.55)
    voile:Hide()
    f.voile = voile
    f:HookScript("OnShow", function() voile:Show() end)
    f:HookScript("OnHide", function() voile:Hide() end)
    table.insert(UISpecialFrames, "SagaCoreMessages")
    local zone = f.zone or f
    f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.intro:SetPoint("TOPLEFT", zone, "TOPLEFT", 8, -8)

    -- L'onglet SagaCore : ouvert ou non.
    f.onglet = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.onglet:SetSize(24, 24)
    f.onglet:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", -4, -10)
    f.onglet.texte = f.onglet.text or f.onglet.Text or f.onglet:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.onglet.texte:ClearAllPoints()
    f.onglet.texte:SetPoint("LEFT", f.onglet, "RIGHT", 4, 0)
    f.onglet:SetScript("OnClick", function(self)
        local d = Base()
        d.onglet = self:GetChecked() and true or false
        if d.onglet then M.PreparerOnglet(true) end
    end)

    -- Les add-ons.
    f.addons = {}
    f.lignes = {}
    for i = 1, LIGNES do
        local l = CreateFrame("Button", nil, f)
        l:SetSize(LARGEUR - 40, 20)
        l:SetPoint("TOPLEFT", f.onglet, "BOTTOMLEFT", 4, -46 - (i - 1) * 21)
        l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.etat:SetPoint("LEFT", 4, 0)
        l.etat:SetWidth(60)
        l.etat:SetJustifyH("LEFT")
        l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l.nom:SetPoint("LEFT", l.etat, "RIGHT", 6, 0)
        l.ou = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.ou:SetPoint("RIGHT", -6, 0)
        l:SetScript("OnClick", function(self) f.choisi = self.cle M.RendreReglages() end)
        f.lignes[i] = l
    end

    -- Le detail du message choisi.
    f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.detail:SetPoint("TOPLEFT", f.lignes[LIGNES], "BOTTOMLEFT", 0, -18)
    f.actif = Bouton(f, 110)
    f.actif:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -8)
    f.actif:SetScript("OnClick", function()
        local r = Reglage(f.addon, f.choisi)
        r.coupe = not r.coupe or nil
        M.RendreReglages()
    end)
    f.ou = Bouton(f, 200)
    f.ou:SetPoint("LEFT", f.actif, "RIGHT", 8, 0)
    f.ou:SetScript("OnClick", function()
        local r = Reglage(f.addon, f.choisi)
        local actuel = M.Destination(f.addon, f.choisi)
        local rang = 1
        for i, d in ipairs(DESTINATIONS) do if d == actuel then rang = i end end
        r.ou = DESTINATIONS[rang % #DESTINATIONS + 1]
        M.RendreReglages()
    end)
    f.essayer = Bouton(f, 110)
    f.essayer:SetPoint("LEFT", f.ou, "RIGHT", 8, 0)
    f.essayer:SetScript("OnClick", function() M.Essayer(f.addon, f.choisi) end)
    f.libelleTexte = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.libelleTexte:SetPoint("TOPLEFT", f.actif, "BOTTOMLEFT", 0, -12)
    f.saisie = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.saisie:SetSize(LARGEUR - 60, 22)
    f.saisie:SetPoint("TOPLEFT", f.libelleTexte, "BOTTOMLEFT", 6, -4)
    f.saisie:SetAutoFocus(false)
    f.saisie:SetMaxLetters(240)
    f.saisie:SetScript("OnEnterPressed", function(self)
        local r = Reglage(f.addon, f.choisi)
        local t = self:GetText()
        local def = Def(f.addon, f.choisi)
        r.texte = (t ~= "" and def and t ~= def.texte) and t or nil
        self:ClearFocus()
        M.RendreReglages()
    end)
    f.saisie:SetScript("OnEscapePressed", function(self) self:ClearFocus() M.RendreReglages() end)
    f.saisie:SetScript("OnEditFocusLost", function(self)
        local r = Reglage(f.addon, f.choisi)
        local t = self:GetText()
        local def = Def(f.addon, f.choisi)
        r.texte = (t ~= "" and def and t ~= def.texte) and t or nil
    end)
    f.valeurs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.valeurs:SetPoint("TOPLEFT", f.saisie, "BOTTOMLEFT", -6, -6)
    f.origine = Bouton(f, 140)
    f.origine:SetPoint("TOPLEFT", f.valeurs, "BOTTOMLEFT", 0, -8)
    f.origine:SetScript("OnClick", function()
        Reglage(f.addon, f.choisi).texte = nil
        M.RendreReglages()
    end)
    f.aide = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.aide:SetPoint("TOPLEFT", f.origine, "BOTTOMLEFT", 0, -12)
    f.aide:SetWidth(LARGEUR - 60)
    f.aide:SetWordWrap(true)
    f.aide:SetJustifyH("LEFT")

    if charte and charte.BoutonDePied and f.pied then
        f.fermerBas = charte.BoutonDePied(f, TX("fermer"), 110)
    else
        f.fermerBas = Bouton(f, 110, TX("fermer"))
        f.fermerBas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    end
    f.fermerBas:SetScript("OnClick", function() f:Hide() end)

    -- Manette.
    if f.EnableGamePadButton and pcall(f.EnableGamePadButton, f, true) then
        f.focus = 1
        local function Elements()
            local liste = { f.onglet }
            for _, b in ipairs(f.addons) do if b:IsShown() then table.insert(liste, b) end end
            for _, l in ipairs(f.lignes) do if l:IsShown() then table.insert(liste, l) end end
            for _, b in ipairs({ f.actif, f.ou, f.essayer, f.saisie, f.origine, f.fermerBas }) do table.insert(liste, b) end
            return liste
        end
        f.Elements = Elements
        f:SetScript("OnGamePadButtonDown", function(self, bouton)
            if f.saisie:HasFocus() then
                if bouton == "PAD2" then f.saisie:ClearFocus() end
                return
            end
            local liste = Elements()
            if bouton == "PADDDOWN" then f.focus = math.min(#liste, f.focus + 1)
            elseif bouton == "PADDUP" then f.focus = math.max(1, f.focus - 1)
            elseif bouton == "PADLSHOULDER" or bouton == "PADRSHOULDER" then
                local a = AddonsDeclares()
                local rang = 1
                for i, cle in ipairs(a) do if cle == f.addon then rang = i end end
                rang = ((rang - 1 + (bouton == "PADRSHOULDER" and 1 or -1)) % #a) + 1
                f.addon, f.choisi = a[rang], nil
                M.RendreReglages()
            elseif bouton == "PAD1" then
                local b = liste[f.focus]
                if b == f.saisie then f.saisie:SetFocus()
                elseif b and (not b.IsEnabled or b:IsEnabled()) then b:Click() end
            elseif bouton == "PAD2" then f:Hide() return end
            M.MarquerFocus()
        end)
    end
    M.fenetre = f
    return f
end

function M.MarquerFocus()
    local f = M.fenetre
    if not (f and f.Elements) then return end
    for rang, b in ipairs(f.Elements()) do
        if b.LockHighlight then
            if rang == f.focus then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
end

function M.RendreReglages()
    local f = M.fenetre
    if not f then return end
    if f.titre then f.titre:SetText(TX("titre")) end
    if f.TitleText then f.TitleText:SetText(TX("titre")) end
    f.intro:SetText(TX("intro"))
    f.onglet.texte:SetText(TX("ongletOuvert"))
    f.onglet:SetChecked(Base().onglet == true)

    local a = AddonsDeclares()
    if not f.addon or not M.ordre[f.addon] then f.addon = a[1] end
    for i, cle in ipairs(a) do
        local b = f.addons[i]
        if not b then
            b = Bouton(f, 110)
            b:SetPoint("TOPLEFT", f.onglet, "BOTTOMLEFT", 4 + (i - 1) * 116, -8)
            b:SetScript("OnClick", function(self) f.addon, f.choisi = self.cle, nil M.RendreReglages() end)
            f.addons[i] = b
        end
        b.cle = cle
        local info = M.ADDONS[cle] or {}
        b:SetText(cle == f.addon and ("|cff" .. (info.couleur or "ffd100") .. cle .. "|r") or cle)
        b:Show()
    end
    for i = #a + 1, #f.addons do f.addons[i]:Hide() end

    local ordre = f.addon and M.ordre[f.addon] or {}
    if not f.choisi or not Def(f.addon, f.choisi) then f.choisi = ordre[1] end
    for i, l in ipairs(f.lignes) do
        local cle = ordre[i]
        local def = cle and Def(f.addon, cle)
        if def then
            l.cle = cle
            local actif = M.Actif(f.addon, cle)
            l.etat:SetText(actif and ("|cff4fd16a" .. TX("actif") .. "|r") or ("|cff888888" .. TX("inactif") .. "|r"))
            l.nom:SetText(def.libelle or cle)
            if cle == f.choisi then l.nom:SetTextColor(1, 1, 1) else l.nom:SetTextColor(1, 0.82, 0) end
            l.ou:SetText(TX(M.Destination(f.addon, cle)))
            l:Show()
        else
            l:Hide()
        end
    end

    local def = f.choisi and Def(f.addon, f.choisi)
    local montrer = def ~= nil
    for _, w in ipairs({ f.detail, f.actif, f.ou, f.essayer, f.libelleTexte, f.saisie, f.valeurs, f.origine }) do
        if montrer then w:Show() else w:Hide() end
    end
    if def then
        f.detail:SetText(def.libelle or f.choisi)
        f.actif:SetText(M.Actif(f.addon, f.choisi) and TX("actif") or TX("inactif"))
        f.ou:SetText(string.format(TX("ou"), TX(M.Destination(f.addon, f.choisi))))
        f.essayer:SetText(TX("essai"))
        f.libelleTexte:SetText(TX("texte"))
        if not f.saisie:HasFocus() then f.saisie:SetText(M.Texte(f.addon, f.choisi)) f.saisie:SetCursorPosition(0) end
        local noms = {}
        for _, v in ipairs(def.valeurs or {}) do table.insert(noms, "{" .. v .. "}") end
        f.valeurs:SetText(string.format(TX("valeurs"), #noms > 0 and table.concat(noms, ", ") or TX("aucune")))
        f.origine:SetText(TX("origine"))
        f.origine:SetEnabled(Reglage(f.addon, f.choisi).texte ~= nil)
    end
    f.aide:SetText(TX("aide"))
    M.MarquerFocus()
end

function M.OuvrirReglages(addon)
    local f = Fenetre()
    if addon and M.ordre[addon] then f.addon, f.choisi = addon, nil end
    f.focus = 1
    M.RendreReglages()
    f:Show()
    f:SetFrameLevel(120)
    if f.Raise then f:Raise() end
end
