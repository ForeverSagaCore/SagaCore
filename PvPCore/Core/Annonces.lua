local _, NS = ...

-- Les annonces du champ de bataille : "Inc Ferme 3", "Ferme : dégagé"...
-- Rien ne part jamais tout seul : chaque annonce suit un clic ou une touche
-- du joueur (carte, raccourci, macro). Le canal est celui du champ de
-- bataille (instance, sinon raid), comme Capping sur les clients classiques.
-- Aussi : le bouton securise qui cible le porteur adverse (/targetexact),
-- cree et mis a jour hors combat seulement, et les macros toutes faites.

NS.annonces = {}
local A = NS.annonces
local T = NS.T

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Combat() return _G.InCombatLockdown and _G.InCombatLockdown() and true or false end

-- ---------------------------------------------------------------------------
-- Le canal
-- ---------------------------------------------------------------------------

-- Le type de discussion pour un envoi par l'add-on.
function A.Canal()
    local infos = _G.ChatTypeInfo or {}
    local instance = _G.LE_PARTY_CATEGORY_INSTANCE or 2
    if infos.INSTANCE_CHAT and NS.Appeler(_G.IsInGroup, instance) then return "INSTANCE_CHAT" end
    if infos.BATTLEGROUND and NS.honneur.EnChamp() then return "BATTLEGROUND" end
    if NS.Appeler(_G.IsInRaid) then return "RAID" end
    if NS.Appeler(_G.IsInGroup) then return "PARTY" end
    return nil
end

-- La commande du canal pour une macro : /i (instance), sinon /bg, sinon /raid.
local function Alias(prefixe)
    local premier
    for i = 1, 6 do
        local a = _G["SLASH_" .. prefixe .. i]
        if type(a) == "string" and a ~= "" then
            premier = premier or a
            if a == "/i" or a == "/bg" then return a end
        end
    end
    return premier
end
function A.CommandeCanal()
    local infos = _G.ChatTypeInfo or {}
    if infos.INSTANCE_CHAT then return Alias("INSTANCE_CHAT") or "/i" end
    if infos.BATTLEGROUND then return Alias("BATTLEGROUND") or "/bg" end
    return "/raid"
end

-- Envoie une annonce (toujours a la suite d'un clic ou d'une touche).
function A.Envoyer(texte)
    if type(texte) ~= "string" or texte == "" then return false end
    local verrou = NS.Lecture("C_ChatInfo.InChatMessagingLockdown")
    if verrou and NS.Appeler(verrou) == true then
        NS.Dire(T("Le jeu bloque les annonces des add-ons en ce moment : utilisez une macro (page Macros).",
            "The game blocks add-on messages right now : use a macro (Macros page)."))
        return false
    end
    local canal = A.Canal()
    if not canal then
        NS.Dire(T("Pas de groupe : rien n'est envoyé.", "No group : nothing is sent."))
        return false
    end
    local envoi = NS.Lecture("C_ChatInfo.SendChatMessage", "SendChatMessage")
    if not envoi then return false end
    local ok = pcall(envoi, texte, canal)
    return ok
end

-- ---------------------------------------------------------------------------
-- Les textes
-- ---------------------------------------------------------------------------

-- Les annonces possibles sur un lieu ; court : debut du nom de la macro.
A.VARIANTES = {
    { cle = "inc1", fr = "Inc %s 1", en = "Inc %s 1", court = "I1" },
    { cle = "inc2", fr = "Inc %s 2", en = "Inc %s 2", court = "I2" },
    { cle = "inc3", fr = "Inc %s 3", en = "Inc %s 3", court = "I3" },
    { cle = "inc5", fr = "Inc %s 5+", en = "Inc %s 5+", court = "I5" },
    { cle = "degage", fr = "%s : dégagé", en = "%s : clear", court = "OK" },
    { cle = "aide", fr = "%s : besoin d'aide", en = "%s : need help", court = "Aide" },
    { cle = "porteur", fr = "Porteur ennemi : %s", en = "Enemy carrier : %s", court = "EFC", goulet = true },
}
local PAR_VARIANTE = {}
for _, v in ipairs(A.VARIANTES) do PAR_VARIANTE[v.cle] = v end
A.PAR_VARIANTE = PAR_VARIANTE

function A.Texte(lieu, variante)
    local v = PAR_VARIANTE[variante]
    if not v or type(lieu) ~= "string" then return nil end
    return string.format(T(v.fr, v.en), lieu)
end
-- Libelle d'une variante dans une liste ("Inc 3", "Dégagé"...).
function A.LibelleVariante(cle)
    local libelles = { inc1 = "Inc 1", inc2 = "Inc 2", inc3 = "Inc 3", inc5 = "Inc 5+",
        degage = T("Dégagé", "Clear"), aide = T("Besoin d'aide", "Need help"), porteur = T("Porteur ennemi ici", "Enemy carrier here") }
    return libelles[cle] or cle
end

-- Les lieux de chaque champ de bataille. Goulet : des reperes sans icone
-- sur la carte. Arathi : les cinq bases. Alterac : les noms du jeu, appris
-- a la premiere partie (les icones de la carte).
A.GOULET = {
    { cle = "base", fr = "Base", en = "Base" },
    { cle = "tunnel", fr = "Tunnel", en = "Tunnel" },
    { cle = "rampe", fr = "Rampe", en = "Ramp" },
    { cle = "toit", fr = "Toit", en = "Roof" },
    { cle = "milieu", fr = "Milieu", en = "Mid" },
}
A.ARATHI = {
    { cle = "ecuries", fr = "Écuries", en = "Stables" },
    { cle = "ferme", fr = "Ferme", en = "Farm" },
    { cle = "forge", fr = "Forge", en = "Blacksmith" },
    { cle = "scierie", fr = "Scierie", en = "Lumber Mill" },
    { cle = "mine", fr = "Mine d'or", en = "Gold Mine" },
}

-- Les appels sans lieu, par champ de bataille.
A.APPELS = {
    goulet = {
        { cle = "aideporteur", fr = "Notre porteur a besoin d'aide", en = "Our carrier needs help" },
        { cle = "drapeausol", fr = "Notre drapeau est au sol", en = "Our flag is on the ground" },
        { cle = "defbase", fr = "Défendez la base", en = "Defend the base" },
    },
    arathi = {
        { cle = "gardez", fr = "Restez défendre vos bases", en = "Stay and defend your bases" },
        { cle = "poursuite", fr = "Ne poursuivez pas, revenez", en = "Do not chase, come back" },
    },
    alterac = {
        { cle = "general", fr = "Tous sur le général", en = "Everyone on the general" },
        { cle = "deftours", fr = "Défendez nos tours", en = "Defend our towers" },
    },
}

-- Les lieux d'un champ de bataille : { cle, nom }.
function A.Lieux(quel)
    local r = {}
    if quel == "goulet" then
        for _, l in ipairs(A.GOULET) do table.insert(r, { cle = l.cle, nom = T(l.fr, l.en) }) end
    elseif quel == "arathi" then
        for _, l in ipairs(A.ARATHI) do table.insert(r, { cle = l.cle, nom = T(l.fr, l.en) }) end
    elseif quel == "alterac" then
        for _, l in ipairs(NS.bataille.LieuxConnus(NS.bataille.CARTES.alterac)) do
            table.insert(r, { cle = "p" .. l.id, nom = l.nom })
        end
        for _, c in ipairs(NS.bataille.CHEFS) do table.insert(r, { cle = "c" .. c.id, nom = T(c.fr, c.en) }) end
    end
    return r
end

-- ---------------------------------------------------------------------------
-- Annonces rapides : le lieu le plus proche, ou un lieu de la carte
-- ---------------------------------------------------------------------------

function A.Annoncer(lieu, variante)
    local texte = A.Texte(lieu, variante)
    if not texte then return false end
    return A.Envoyer(texte)
end

-- Raccourci : annonce sur le lieu le plus proche de vous.
function A.IncProche(variante)
    if not NS.honneur.EnChamp() then NS.Dire(T("Hors champ de bataille : rien n'est envoyé.", "Not in a battleground : nothing is sent.")) return false end
    local p = NS.bataille.LieuProche()
    if not p then NS.Dire(T("Aucun lieu connu près de vous sur la carte.", "No known place near you on the map.")) return false end
    return A.Annoncer(p.nom, variante)
end

-- Clic sur un lieu de la carte : la liste des annonces, a l'aspect des
-- listes de la suite, ouverte sur le lieu.
local menu
function A.Menu(ancre, lieu)
    local S = _G.CoreSuite
    if not (S and S.ListeDeroulante and ancre and type(lieu) == "string") then return end
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetSize(170, 1)
        menu:SetFrameStrata("TOOLTIP")
        menu.liste = S.ListeDeroulante(menu, function()
            local o = {}
            for _, v in ipairs(A.VARIANTES) do
                if v.cle ~= "porteur" and v.cle ~= "aide" then table.insert(o, { v.cle, A.LibelleVariante(v.cle) }) end
            end
            return o
        end, function() return nil end, function(v) A.Annoncer(menu.lieu, v) end)
        menu.liste:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
        menu.liste:SetAlpha(0)
        -- Invisible et sans souris : seule la liste ouverte se voit.
        if menu.liste.bouton and menu.liste.bouton.EnableMouse then menu.liste.bouton:EnableMouse(false) end
        menu:Show()
    end
    menu.lieu = lieu
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", ancre, "BOTTOMLEFT", 0, 0)
    local b = menu.liste.bouton
    if b and b.Click then b:Click("LeftButton") end
end

-- ---------------------------------------------------------------------------
-- Cibler le porteur adverse : un bouton securise, sans action protegee en
-- combat. Il ne se cree et ne change que hors combat ; en combat, il garde
-- le dernier porteur connu hors combat, et se met a jour a la sortie.
-- ---------------------------------------------------------------------------

A.NOM_BOUTON = "PvPCoreCiblePorteur"
local bouton, cibleDuBouton, enAttente = nil, nil, false

function A.CreerBouton()
    if bouton then return bouton end
    if Combat() then enAttente = true return nil end
    local ok, b = pcall(CreateFrame, "Button", A.NOM_BOUTON, UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return nil end
    -- Clic au relachement (macro /click et raccourci), jamais visible.
    pcall(b.RegisterForClicks, b, "AnyUp", "AnyDown")
    pcall(b.SetAttribute, b, "useOnKeyDown", false)
    pcall(b.SetAttribute, b, "type", "macro")
    pcall(b.SetAttribute, b, "macrotext", "")
    b:Hide()
    bouton = b
    A.bouton = b
    return b
end

-- Le nom vise par le bouton suit le porteur adverse, hors combat.
function A.MajCible()
    local nom = NS.champ and NS.champ.PorteurAdverse() or nil
    if type(nom) ~= "string" or Secret(nom) or nom:find("[%c/;\n]") then nom = nil end
    if Combat() then enAttente = true return false end
    if not bouton and not A.CreerBouton() then return false end
    if nom == cibleDuBouton then enAttente = false return true end
    pcall(bouton.SetAttribute, bouton, "macrotext", nom and ("/targetexact " .. nom) or "")
    cibleDuBouton = nom
    enAttente = false
    return true
end
-- Vrai si le bouton vise bien le porteur adverse actuel.
function A.CibleAJour()
    local nom = NS.champ and NS.champ.PorteurAdverse() or nil
    return bouton ~= nil and nom ~= nil and nom == cibleDuBouton
end
function A.CibleDuBouton() return cibleDuBouton end

-- ---------------------------------------------------------------------------
-- Les macros toutes faites
-- ---------------------------------------------------------------------------

-- Chaque macro porte en premiere ligne sa cle (#PvPCore cle) : c'est ainsi
-- qu'on la retrouve, jamais par son nom. Une macro du joueur n'est jamais
-- touchee.
local ICONES = {
    inc1 = "Ability_Warrior_BattleShout", inc2 = "Ability_Warrior_BattleShout", inc3 = "Ability_Warrior_BattleShout",
    inc5 = "Ability_Warrior_BattleShout", degage = "Spell_Holy_SealOfProtection", aide = "Ability_Warrior_Rampage",
    porteur = "INV_BannerPVP_01", appel = "Ability_Warrior_RallyingCry", cible = "Ability_Hunter_SniperShot",
}

-- Coupe un texte a tant d'octets sans couper une lettre accentuee.
local function Couper(texte, maxi)
    if #texte <= maxi then return texte end
    local fin = maxi
    while fin > 0 do
        local octet = texte:byte(fin + 1)
        if not octet or octet < 128 or octet >= 192 then break end
        fin = fin - 1
    end
    return (texte:sub(1, fin):gsub("%s+$", ""))
end
A.Couper = Couper

-- Le catalogue d'un champ de bataille : { cle, nom, texte, corps, icone, libelle }.
function A.Catalogue(quel, variantes)
    variantes = variantes or {}
    local canal = A.CommandeCanal()
    local r = {}
    local function Ajouter(cle, nomMacro, texte, icone, libelle, commande)
        local corps = "#PvPCore " .. cle .. "\n" .. (commande or (canal .. " " .. texte))
        table.insert(r, { cle = cle, nom = Couper(nomMacro, 16), texte = texte, corps = corps, icone = icone, libelle = libelle })
    end
    for _, l in ipairs(A.Lieux(quel)) do
        local v = variantes[quel .. ":" .. l.cle]
        if not PAR_VARIANTE[v] or (PAR_VARIANTE[v].goulet and quel ~= "goulet") then v = "inc3" end
        local def = PAR_VARIANTE[v]
        Ajouter(quel .. ":" .. l.cle .. ":" .. v, def.court .. " " .. l.nom, A.Texte(l.nom, v), ICONES[v], l.nom)
        r[#r].lieu, r[#r].variante = l.cle, v
    end
    for _, a in ipairs(A.APPELS[quel] or {}) do
        local texte = T(a.fr, a.en)
        Ajouter(quel .. ":" .. a.cle, texte, texte, ICONES.appel, texte)
    end
    if quel == "goulet" then
        Ajouter("goulet:cible", T("Cibler porteur", "Target carrier"), nil, ICONES.cible, T("Cibler le porteur ennemi", "Target the enemy carrier"),
            "/click " .. A.NOM_BOUTON)
    end
    -- Deux noms identiques (noms coupes) : un numero les separe.
    local vus = {}
    for _, m in ipairs(r) do
        local n = vus[m.nom] or 0
        vus[m.nom] = n + 1
        if n > 0 then m.nom = Couper(m.nom, 13) .. " " .. (n + 1) end
    end
    return r
end

-- Les macros du jeu : (index, corps) de toutes, communes puis du personnage.
local function MAXIS() return _G.MAX_ACCOUNT_MACROS or 120, _G.MAX_CHARACTER_MACROS or 18 end
A.MAXIS = MAXIS
function A.Place()
    local compte, perso = NS.Appeler(_G.GetNumMacros)
    local mc, mp = MAXIS()
    return tonumber(compte) or 0, mc, tonumber(perso) or 0, mp
end
-- L'index de notre macro (par sa cle), ou nil.
function A.IndexDe(cle)
    if not _G.GetMacroInfo then return nil end
    local compte, mc, perso = A.Place()
    local marque = "#PvPCore " .. cle .. "\n"
    local function Voir(i)
        local _, _, corps = NS.Appeler(_G.GetMacroInfo, i)
        if type(corps) == "string" and corps:sub(1, #marque) == marque then return i end
    end
    for i = 1, compte do local x = Voir(i) if x then return x end end
    for i = 1, perso do local x = Voir(mc + i) if x then return x end end
    return nil
end
function A.Existe(cle) return A.IndexDe(cle) ~= nil end

-- Cree (ou remet a jour) une macro du catalogue, hors combat ; parPerso :
-- dans les macros du personnage. Rend vrai, ou faux et la raison.
function A.CreerMacro(m, parPerso)
    if Combat() then return false, T("Impossible en combat.", "Not possible in combat.") end
    if not (_G.CreateMacro and _G.GetMacroInfo) then return false, T("Macros indisponibles.", "Macros unavailable.") end
    local S = _G.CoreSuite
    local icone = (S and S.IconeDeMacro) and S.IconeDeMacro({ icone = m.icone }) or 134400
    local index = A.IndexDe(m.cle)
    if index then
        local ok = pcall(_G.EditMacro, index, m.nom, icone, m.corps)
        return ok, nil
    end
    local compte, mc, perso, mp = A.Place()
    if parPerso and perso >= mp then
        return false, string.format(T("Plus de place dans les macros du personnage (%d / %d).", "No room left in character macros (%d / %d)."), perso, mp)
    end
    if not parPerso and compte >= mc then
        return false, string.format(T("Plus de place dans les macros du compte (%d / %d).", "No room left in account macros (%d / %d)."), compte, mc)
    end
    local ok, nouvel = pcall(_G.CreateMacro, m.nom, icone, m.corps, parPerso and true or nil)
    if not (ok and nouvel) then return false, T("Le jeu a refusé la macro.", "The game refused the macro.") end
    return true, nil
end
function A.SupprimerMacro(m)
    if Combat() then return false, T("Impossible en combat.", "Not possible in combat.") end
    local index = A.IndexDe(m.cle)
    if index and _G.DeleteMacro then pcall(_G.DeleteMacro, index) end
    return true
end

-- ---------------------------------------------------------------------------
-- Evenements et raccourcis
-- ---------------------------------------------------------------------------

local cadre = CreateFrame("Frame")
A.cadre = cadre
for _, ev in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED" }) do pcall(cadre.RegisterEvent, cadre, ev) end
cadre:SetScript("OnEvent", function(_, ev)
    local ok, souci = pcall(function()
        if ev == "PLAYER_LOGIN" then A.CreerBouton() A.MajCible()
        elseif ev == "PLAYER_REGEN_ENABLED" and enAttente then A.MajCible() end
    end)
    if not ok then NS.base.NoterIncident("annonces " .. tostring(ev), souci) end
end)

-- Raccourcis clavier ou manette (Options, Raccourcis, PvPCore).
_G["BINDING_NAME_PVPCORE_INC1"] = T("Inc 1 au lieu le plus proche", "Inc 1 at the nearest place")
_G["BINDING_NAME_PVPCORE_INC2"] = T("Inc 2 au lieu le plus proche", "Inc 2 at the nearest place")
_G["BINDING_NAME_PVPCORE_INC3"] = T("Inc 3 au lieu le plus proche", "Inc 3 at the nearest place")
_G["BINDING_NAME_PVPCORE_INC5"] = T("Inc 5+ au lieu le plus proche", "Inc 5+ at the nearest place")
_G["BINDING_NAME_PVPCORE_DEGAGE"] = T("Lieu le plus proche dégagé", "Nearest place clear")
_G["BINDING_NAME_CLICK " .. A.NOM_BOUTON .. ":LeftButton"] = T("Cibler le porteur ennemi", "Target the enemy carrier")
function _G.PvPCore_Inc(variante) A.IncProche(variante) end
