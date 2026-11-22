local _, NS = ...

-- Ce que l'anneau reconnait (WoW Forever, contenu classique). Les sorts sont
-- donnes par un identifiant de rang 1 : seul leur nom compte (il est le meme
-- a tous les rangs, dans la langue du jeu).

NS.donnees = {}
local D = NS.donnees

-- Tous les buffs que les autres peuvent donner, par classe. "vrai" : les
-- longs buffs donnes a tout le monde (cochés par defaut, ils ont leur quart
-- dans l'anneau) ; les autres (courts, de situation, de talent, totems) sont
-- decoches par defaut. Chaque buff se coche ou se decoche dans la page
-- "Buffs suivis". Les identifiants (rang 1) sont dans la partie liste de
-- chaque entree : seul leur nom compte.
D.SUIVIS = {
    { classe = "PRIEST", cle = "robustesse", vrai = true, 1243, 21562 },
    { classe = "PRIEST", cle = "esprit", 14752, 27681 },
    { classe = "PRIEST", cle = "ombre", 976, 27683 },
    { classe = "PRIEST", cle = "gardien", 6346 },
    { classe = "PRIEST", cle = "bouclier", 17 },
    { classe = "PRIEST", cle = "renovation", 139 },
    { classe = "PRIEST", cle = "inspiration", 14893 },
    { classe = "PRIEST", cle = "infusion", 10060 },
    { classe = "PRIEST", cle = "abolirmaladie", 552 },
    { classe = "MAGE", cle = "intelligence", vrai = true, 1459, 23028 },
    { classe = "MAGE", cle = "amplifier", 1008 },
    { classe = "MAGE", cle = "attenuer", 604 },
    { classe = "DRUID", cle = "fauve", vrai = true, 1126, 21849 },
    { classe = "DRUID", cle = "epines", 467 },
    { classe = "DRUID", cle = "recuperation", 774 },
    { classe = "DRUID", cle = "retablissement", 8936 },
    { classe = "DRUID", cle = "innervation", 29166 },
    { classe = "DRUID", cle = "abolirpoison", 2893 },
    { classe = "PALADIN", cle = "benediction", vrai = true, 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890, 20911, 25899 },
    { classe = "PALADIN", cle = "protection", 1022 },
    { classe = "PALADIN", cle = "liberte", 1044 },
    { classe = "PALADIN", cle = "sacrifice", 6940 },
    { classe = "PALADIN", cle = "auras", 465, 7294, 19746, 19876, 19888, 19891, 20218 },
    { classe = "SHAMAN", cle = "forceterre", 8076 },
    { classe = "SHAMAN", cle = "graceair", 8836 },
    { classe = "SHAMAN", cle = "peaupierre", 8072 },
    { classe = "SHAMAN", cle = "fontainemana", 5677 },
    { classe = "SHAMAN", cle = "guerison", 5672 },
    { classe = "SHAMAN", cle = "airtranquille", 25909 },
    { classe = "SHAMAN", cle = "resistances", 8185, 8182, 10596 },
    { classe = "SHAMAN", cle = "marchesurleau", 546, 131 },
    { classe = "WARRIOR", cle = "cri", 6673 },
    { classe = "HUNTER", cle = "precision", 19506 },
    { classe = "HUNTER", cle = "meute", 13159, 20043 },
    { classe = "WARLOCK", cle = "respiration", 5697 },
    { classe = "WARLOCK", cle = "invisibilite", 132, 2970 },
    { classe = "WARLOCK", cle = "pierredame", 20707 },
}

-- Coche (reglage du joueur, sinon : vrai buff coche, les autres non).
function D.Choisi(e)
    local r = NS.anneau and NS.anneau.Reglages and NS.anneau.Reglages() or {}
    local s = type(r.suivis) == "table" and r.suivis or {}
    if s[e.cle] ~= nil then return s[e.cle] == true end
    -- Ancien reglage des petits sorts.
    if type(r.petits) == "table" and r.petits[e.cle] then return true end
    return e.vrai == true
end

-- Les vrais buffs, par classe (leur quart) ; les autres (la file s'ils
-- sont coches).
D.GROUPE, D.PETITS = {}, {}
for _, e in ipairs(D.SUIVIS) do
    e.ids = e.ids or {}
    for _, id in ipairs(e) do table.insert(e.ids, id) end
    if e.vrai then
        D.GROUPE[e.classe] = D.GROUPE[e.classe] or {}
        table.insert(D.GROUPE[e.classe], e)
    else
        table.insert(D.PETITS, e)
    end
end

-- Ce que chaque classe se met elle-meme : une famille par place (une seule
-- active a la fois dans une famille). Le premier rang suffit : le nom est
-- le meme pour tous les rangs.
D.SOI = {
    HUNTER = { { 13165, 13163, 5118, 13159, 13161, 20043 } },      -- Aspects (faucon, singe, guepard, meute, bete, nature)
    PALADIN = { { 465, 7294, 19746, 19876, 19888, 19891 } },        -- Auras
    PRIEST = { { 588 } },                                           -- Feu interieur
    MAGE = { { 168, 7302, 6117 } },                                 -- Armures (givre, glace, mage)
    WARLOCK = { { 687, 706 } },                                     -- Peau de demon, Armure demoniaque
    SHAMAN = { { 324 } },                                           -- Bouclier de foudre
}

-- Consommables : flacons et elixirs courants, nourriture.
D.FLACONS = { 17626, 17627, 17628, 17629, 17538, 11405, 11334, 11328, 3160, 3593, 11348, 11396, 17535, 11390, 11406, 17537, 17539 }
D.NOURRITURE = { 19705, 24799, 18191, 18192, 18193, 18194, 18222, 22730, 25661 }

-- Tous les elixirs et flacons, pas seulement ceux de la liste : chaque objet
-- de vos sacs dont le nom dit Elixir ou Flacon donne le nom de son effet
-- (GetItemSpell). Appris une fois, garde pour toujours (AuraCoreDB), meme
-- quand le dernier a ete bu.
-- (string.lower ne touche pas aux lettres accentuees : "Élixir" a sa propre entree.)
local MOTS_CONSO = { "élixir", "Élixir", "elixir", "flacon", "flask" }
local function ConsoApprises()
    AuraCoreDB = type(AuraCoreDB) == "table" and AuraCoreDB or {}
    AuraCoreDB.elixirs = type(AuraCoreDB.elixirs) == "table" and AuraCoreDB.elixirs or {}
    return AuraCoreDB.elixirs
end
D.ConsoApprises = ConsoApprises
local function EstElixir(nomObjet)
    local brut = nomObjet or ""
    local bas = string.lower(brut)
    for _, m in ipairs(MOTS_CONSO) do
        if string.find(bas, m, 1, true) or string.find(brut, m, 1, true) then return true end
    end
    return false
end
function D.ApprendreDesSacs()
    local C = _G.C_Container
    local nbCases = (C and C.GetContainerNumSlots) or _G.GetContainerNumSlots
    local idDe = (C and C.GetContainerItemID) or _G.GetContainerItemID
    local sortDe = (_G.C_Item and _G.C_Item.GetItemSpell) or _G.GetItemSpell
    local infoDe = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if not (nbCases and idDe and sortDe and infoDe) then return 0 end
    local apprises, nouvelles = ConsoApprises(), 0
    for sac = 0, 4 do
        local okN, n = pcall(nbCases, sac)
        for case = 1, (okN and tonumber(n)) or 0 do
            local okI, id = pcall(idDe, sac, case)
            if okI and id then
                local okNom, nomObjet = pcall(infoDe, id)
                if okNom and nomObjet and EstElixir(nomObjet) then
                    local okS, effet = pcall(sortDe, id)
                    if okS and type(effet) == "string" and effet ~= "" and not apprises[effet] then
                        apprises[effet] = id
                        nouvelles = nouvelles + 1
                    end
                end
            end
        end
    end
    return nouvelles
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    local attente = false
    f:SetScript("OnEvent", function()
        -- Regroupe les mises a jour des sacs (elles arrivent par rafales).
        if attente then return end
        attente = true
        local function Faire() attente = false pcall(D.ApprendreDesSacs) end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(1, Faire) else Faire() end
    end)
end
-- Potions de soins et de mana, de la meilleure a la plus petite.
D.POTIONS = { 13446, 3928, 1710, 929, 858, 118, 13444, 13443, 6149, 3827, 3385, 2455 }

-- Nom d'un sort, dans la langue du jeu.
local noms = {}
function D.Nom(id)
    if noms[id] ~= nil then return noms[id] or nil end
    local nom
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then nom = n end
    end
    if not nom and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then nom = n end
    end
    noms[id] = nom or false
    return nom
end

function D.Icone(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and t then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok and t then return t end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ===========================================================================

-- Demander au groupe les buffs qui manquent. Les buffs se donnent a la main :
-- un retardataire, un buff oublie... Un clic (bouton de la fenetre, raccourci
-- clavier ou manette, /auracore buffs) regarde, hors combat, qui manque de
-- quoi parmi ce que les classes du groupe peuvent donner, et l'ecrit en un
-- seul message au groupe : le buff, qui en manque, qui peut le donner.
-- Rien n'est envoye sans ce clic, et jamais en combat.

NS.demande = {}
local M = NS.demande
local T = function(...) return NS.T(...) end

-- Ce que l'on demande : les vrais buffs seulement, jamais les petits sorts.
local FAMILLES = {
    { classe = "PRIEST", ids = { 1243, 21562 } },                         -- Robustesse
    { classe = "MAGE", ids = { 1459, 23028 }, mana = true },              -- Intelligence des arcanes
    { classe = "DRUID", ids = { 1126, 21849 } },                          -- Marque du fauve
    { classe = "PALADIN", ids = D.GROUPE.PALADIN[1], benediction = true }, -- une benediction par paladin
    -- Ce qui agit sur tout le groupe sans se lancer sur chacun : une aura de
    -- paladin, le cri de guerre, un totem de chaman. Demande seulement a la
    -- classe presente dans le groupe, pour ceux qui n'en ont aucun.
    { classe = "PALADIN", ids = { 465, 7294, 19746, 19876, 19888, 19891, 20218 }, libelle = function() return T("une aura", "an aura") end },
    { classe = "WARRIOR", ids = { 6673 } },                                -- Cri de guerre
    { classe = "SHAMAN", ids = { 8076, 8836, 5677, 8072, 8185, 8182, 10596, 25909 }, libelle = function() return T("un totem", "a totem") end },
    -- Auras de talent ou de haut niveau : seulement si quelqu'un l'a deja
    -- (preuve que le joueur la possede), pour ceux qui sont hors de portee.
    { classe = "HUNTER", ids = { 19506 }, siVu = true },                   -- Aura de precision
    { classe = "HUNTER", ids = { 20043 }, siVu = true },                   -- Aspect de la nature
    { classe = "DRUID", ids = { 17007 }, siVu = true },                    -- Chef de la meute
    { classe = "DRUID", ids = { 24907 }, siVu = true },                    -- Aura de selenien
}
local MANA = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) end

local function Court(nom)
    if type(nom) ~= "string" then return "?" end
    return (nom:match("^([^%-]+)")) or nom
end

-- Les membres du groupe, nous compris, vivants et connectes.
local function Membres()
    local liste, vus = {}, {}
    local function Ajouter(unite)
        if not UnitExists(unite) then return end
        local nom = UnitName(unite)
        if not nom or vus[nom] then return end
        vus[nom] = true
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unite) then return end
        if UnitIsConnected and not UnitIsConnected(unite) then return end
        local _, classe = UnitClass(unite)
        -- Le nom complet (avec le royaume s'il est autre) : pour chuchoter.
        local complet = (_G.GetUnitName and _G.GetUnitName(unite, true)) or nom
        table.insert(liste, { unite = unite, nom = Court(nom), complet = complet, classe = classe })
    end
    Ajouter("player")
    local raid = _G.IsInRaid and _G.IsInRaid()
    for i = 1, (_G.GetNumGroupMembers and _G.GetNumGroupMembers()) or 0 do
        Ajouter(raid and ("raid" .. i) or ("party" .. i))
    end
    return liste
end

-- Noms des ameliorations d'une unite (hors combat : lisibles).
local function NomsDAuras(unite)
    local noms = {}
    local C = _G.C_UnitAuras
    for i = 1, 40 do
        local nom
        if C and C.GetAuraDataByIndex then
            local ok, a = pcall(C.GetAuraDataByIndex, unite, i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            nom = a.name
        elseif _G.UnitBuff then
            local ok, n = pcall(_G.UnitBuff, unite, i)
            if not ok or not n then break end
            nom = n
        else
            break
        end
        if nom and not Secret(nom) then noms[nom] = true end
    end
    return noms
end

-- Ce qui manque : { { buff, manquants = {noms}, donneurs = {noms} }, ... }.
function M.Analyser()
    local membres = Membres()
    local donneursPar, auras, complets = {}, {}, {}
    for _, m in ipairs(membres) do
        complets[m.nom] = m.complet or m.nom
        if m.classe then
            donneursPar[m.classe] = donneursPar[m.classe] or {}
            table.insert(donneursPar[m.classe], m.nom)
        end
        auras[m.nom] = NomsDAuras(m.unite)
    end
    local resultat = {}
    for _, f in ipairs(FAMILLES) do
        local donneurs = donneursPar[f.classe]
        local entree
        for _, e in ipairs(D.GROUPE[f.classe] or {}) do if e.ids[1] == f.ids[1] then entree = e end end
        if donneurs and (not entree or D.Choisi(entree)) then
            local noms = {}
            for _, id in ipairs(f.ids) do
                local n = D.Nom(id)
                if n then noms[n] = true end
            end
            local function Compte(m)
                local n = 0
                for nom in pairs(noms) do if auras[m.nom][nom] then n = n + 1 end end
                return n
            end
            local vu = not f.siVu
            if f.siVu then
                for _, m in ipairs(membres) do if Compte(m) > 0 then vu = true end end
            end
            if vu then
                local manquants = {}
                for _, m in ipairs(membres) do
                    local concerne = (not f.mana) or MANA[m.classe or ""]
                    local besoin = f.benediction and #donneurs or 1
                    if concerne and Compte(m) < besoin then table.insert(manquants, m.nom) end
                end
                if #manquants > 0 then
                    local buff = (f.libelle and f.libelle()) or (f.benediction and T("une bénédiction", "a blessing")) or (D.Nom(f.ids[1]) or "?")
                    table.insert(resultat, { buff = buff, manquants = manquants, donneurs = donneurs, complets = complets,
                        tous = #manquants == #membres and #membres > 1 })
                end
            end
        end
    end
    return resultat
end

-- Met des morceaux de texte bout a bout en messages de moins de 250
-- caracteres (la limite du jeu est 255). Un morceau trop long a lui seul
-- (beaucoup de noms) est coupe entre deux noms, jamais au milieu d'un nom.
local LIMITE = 250
local function Decouper(entete, morceaux, fin)
    local messages, courant = {}, entete
    local function Pousser(texte)
        if #courant + #texte > LIMITE and courant ~= "" and courant ~= entete then
            table.insert(messages, courant)
            courant = ""
        end
        courant = courant .. texte
    end
    for k, m in ipairs(morceaux) do
        local dernier = k == #morceaux
        if #m.tete + #m.queue + #table.concat(m.noms, ", ") <= LIMITE - #entete then
            Pousser(m.tete .. table.concat(m.noms, ", ") .. m.queue .. (dernier and fin or " ; "))
        else
            -- Les noms par paquets : chaque paquet repete le debut du morceau.
            local paquet = {}
            local function Vider(estDernier)
                if #paquet == 0 then return end
                Pousser(m.tete .. table.concat(paquet, ", ") .. m.queue .. (estDernier and dernier and fin or " ; "))
                paquet = {}
            end
            for i, nom in ipairs(m.noms) do
                if #m.tete + #m.queue + #table.concat(paquet, ", ") + #nom + 6 > LIMITE - #entete then Vider(false) end
                table.insert(paquet, nom)
                if i == #m.noms then Vider(true) end
            end
        end
    end
    if courant ~= "" and courant ~= entete then table.insert(messages, courant) end
    return messages
end

-- Le message au groupe, en autant de morceaux que necessaire.
function M.Messages(analyse)
    local morceaux = {}
    for _, a in ipairs(analyse) do
        local noms = a.tous and { T("tout le groupe", "the whole group") } or a.manquants
        table.insert(morceaux, { tete = a.buff .. " " .. T("pour", "for") .. " ", noms = noms,
            queue = " (" .. table.concat(a.donneurs, ", ") .. ")" })
    end
    if #morceaux == 0 then return {} end
    return Decouper(T("Buffs manquants : ", "Missing buffs : "), morceaux, ". " .. T("Merci !", "Thanks!"))
end

-- Un chuchotement a chaque joueur qui peut donner un buff manquant : ce
-- qu'il doit lancer et sur qui. Jamais a soi-meme. { {cible, messages} }.
function M.Chuchotements(analyse)
    local moi = _G.UnitName and _G.UnitName("player")
    local parDonneur, ordre = {}, {}
    for _, a in ipairs(analyse) do
        for _, d in ipairs(a.donneurs) do
            if d ~= moi then
                if not parDonneur[d] then
                    parDonneur[d] = { cible = (a.complets and a.complets[d]) or d, morceaux = {} }
                    table.insert(ordre, d)
                end
                local noms = a.tous and { T("tout le groupe", "the whole group") } or a.manquants
                table.insert(parDonneur[d].morceaux, { tete = a.buff .. " " .. T("pour", "for") .. " ", noms = noms, queue = "" })
            end
        end
    end
    local liste = {}
    for _, d in ipairs(ordre) do
        local e = parDonneur[d]
        table.insert(liste, { cible = e.cible, nom = d,
            messages = Decouper(T("Peux-tu lancer : ", "Could you cast : "), e.morceaux, ". " .. T("Merci !", "Thanks!")) })
    end
    return liste
end

local function Canal()
    if _G.IsInGroup and _G.LE_PARTY_CATEGORY_INSTANCE and _G.IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE)
        and not (_G.LE_PARTY_CATEGORY_HOME and _G.IsInGroup(_G.LE_PARTY_CATEGORY_HOME)) then
        return "INSTANCE_CHAT"
    end
    if _G.IsInRaid and _G.IsInRaid() then return "RAID" end
    if (_G.IsInGroup and _G.IsInGroup()) or ((_G.GetNumGroupMembers and _G.GetNumGroupMembers()) or 0) > 0 then return "PARTY" end
    return nil
end

local function EnCombat() return _G.InCombatLockdown and _G.InCombatLockdown() end

-- Ce qui serait envoye, pour la fenetre (ou pourquoi rien).
function M.Apercu()
    if not Canal() then return T("Vous n'êtes pas en groupe.", "You are not in a group.") end
    if EnCombat() then return T("Hors combat seulement.", "Out of combat only.") end
    local analyse = M.Analyser()
    local messages = M.Messages(analyse)
    if #messages == 0 then return T("Rien à demander : chacun a les buffs que le groupe peut donner.", "Nothing to ask : everyone has the buffs your group can give.") end
    local qui = {}
    for _, c in ipairs(M.Chuchotements(analyse)) do table.insert(qui, c.nom) end
    local texte = table.concat(messages, " ")
    if #qui > 0 then texte = texte .. "  " .. T("Chuchoté aussi à : ", "Also whispered to : ") .. table.concat(qui, ", ") end
    return texte
end

local dernier = 0
function M.Envoyer()
    local canal = Canal()
    if not canal then NS.Dire(T("Vous n'êtes pas en groupe.", "You are not in a group.")) return end
    if EnCombat() then NS.Dire(T("Hors combat seulement.", "Out of combat only.")) return end
    local maintenant = (_G.GetTime and _G.GetTime()) or 0
    if maintenant - dernier < 20 then
        NS.Dire(T("Attendez quelques secondes avant de redemander.", "Wait a few seconds before asking again."))
        return
    end
    local analyse = M.Analyser()
    local messages = M.Messages(analyse)
    if #messages == 0 then
        NS.Dire(T("Rien à demander : chacun a les buffs que le groupe peut donner.", "Nothing to ask : everyone has the buffs your group can give."))
        return
    end
    dernier = maintenant
    local envoyer = (_G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    -- Tout part tout de suite, pendant le clic : le jeu n'autorise un add-on a
    -- ecrire dans la discussion que sur une action du joueur (en champ de
    -- bataille et en instance surtout) ; un message differe (minuterie) y est
    -- refuse, avec le message d'echec d'interface. Le groupe d'abord, puis
    -- chaque donneur en chuchotement.
    -- Un envoi refuse par le jeu est dit dans la discussion (une fois), avec
    -- sa raison : on sait ainsi ce qui bloque.
    local signale = false
    local function Envoi(texte, genre, cible)
        local ok, err = pcall(envoyer, texte, genre, nil, cible)
        if not ok and not signale then
            signale = true
            NS.Dire(T("Envoi refusé par le jeu (", "Sending refused by the game (") .. tostring(genre) .. ") : " .. tostring(err))
        end
    end
    for _, texte in ipairs(messages) do Envoi(texte, canal) end
    for _, c in ipairs(M.Chuchotements(analyse)) do
        for _, texte in ipairs(c.messages) do Envoi(texte, "WHISPER", c.cible) end
    end
end

-- ---------------------------------------------------------------------------
-- Le bouton : rond, a l'icone de Robustesse, au-dessus du portrait du
-- personnage par defaut (Maj + glisser pour le deplacer). Visible en groupe ;
-- eteint et inactif tant que rien ne manque, illumine des qu'un buff manque.
-- ---------------------------------------------------------------------------

local function R() return NS.anneau and NS.anneau.Reglages and NS.anneau.Reglages() or {} end
local bouton
local function Placer(b)
    b:ClearAllPoints()
    local pos = R().boutonBuffs
    if type(pos) == "table" and pos[1] then
        b:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    elseif _G.PlayerFrame then
        -- Au-dessus du cadre du personnage, a droite, un peu plus pres.
        -- Bord droit aligne sur celui du cadre (barre du nom).
        b:SetPoint("BOTTOMRIGHT", _G.PlayerFrame, "TOPRIGHT", -22, -16)
    else
        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 180, -10)
    end
end

local function Construire()
    if bouton then return bouton end
    local b = CreateFrame("Button", "AuraCoreBoutonBuffs", UIParent)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp")
    -- Exactement une pastille de l'anneau (meme taille, meme habillage),
    -- avec l'icone de Robustesse. Les clics vont au bouton.
    b.p = NS.anneau.Pastille(b)
    b.p:SetPoint("CENTER")
    b.p:EnableMouse(false)
    b.p:Show()
    -- Un cor : l'appel au groupe, lisible, en couleur.
    b.p.icone:SetTexture("Interface\\Icons\\INV_Misc_Horn_01")
    -- Illumine : une lueur qui pulse doucement autour de l'icone.
    b.lueur = b.p:CreateTexture(nil, "OVERLAY", nil, 2)
    b.lueur:SetPoint("CENTER", b.p.icone, "CENTER", 0, 0)
    b.lueur:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.lueur:SetBlendMode("ADD")
    b.pulse = b.lueur:CreateAnimationGroup()
    b.pulse:SetLooping("BOUNCE")
    local a = b.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.2)
    a:SetDuration(0.8)
    b:SetScript("OnClick", function(self)
        if self.actif then M.Envoyer() M.MettreAJour() end
    end)
    b:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() then self:StartMoving() end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        R().boutonBuffs = { point, rel, x, y }
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(T("Demander les buffs manquants", "Ask for missing buffs"), 1, 0.82, 0)
        GameTooltip:AddLine(M.Apercu(), 1, 1, 1, true)
        GameTooltip:AddLine(T("Maj + glisser : déplacer le bouton.", "Shift + drag : move the button."), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Placer(b)
    bouton = b
    return b
end

function M.ReplacerBouton()
    R().boutonBuffs = nil
    if bouton then Placer(bouton) end
end

-- Etat du bouton : toujours visible (sauf option decochee) ; eteint (gris,
-- inactif) hors groupe, en combat ou quand rien ne manque ; illumine sinon.
function M.MettreAJour()
    local b = Construire()
    if R().boutonBuffsCache then b:Hide() return end
    b:Show()
    -- La taille des icones de l'anneau.
    local t = tonumber(R().taille) or 30
    if b.taille ~= t then
        b.taille = t
        b:SetSize(t, t)
        b.p:Taille(t)
        b.lueur:SetSize(t * 0.95, t * 0.95)
    end
    local manque = Canal() ~= nil and (not EnCombat()) and #M.Analyser() > 0
    b.actif = manque
    -- Comme une place de l'anneau : grise quand rien ne manque, en couleur
    -- (et qui pulse) des qu'un buff manque.
    NS.anneau.Cercler(b.p, manque and "actif" or "absent")
    NS.anneau.Opacite(b.p, not manque)
    b.lueur:SetShown(manque)
    if manque then
        if not b.pulse:IsPlaying() then b.pulse:Play() end
    else
        b.pulse:Stop()
    end
end

do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    local attente = 0
    f:SetScript("OnEvent", function(_, ev, unite)
        if ev == "UNIT_AURA" and EnCombat() then return end
        attente = 0
    end)
    -- Au plus deux fois par seconde : la lecture des auras du groupe reste legere.
    f:SetScript("OnUpdate", function(_, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.5
        local ok, souci = pcall(M.MettreAJour)
        if not ok then
            local r = R()
            r.diag = type(r.diag) == "table" and r.diag or {}
            r.diag.bouton = tostring(souci)
        end
    end)
end

-- Raccourci (Options, Raccourcis, AuraCore) : utilisable a la manette.
_G.BINDING_HEADER_AURACORE = "AuraCore"
_G.BINDING_NAME_AURACORE_DEMANDE = T("Demander au groupe les buffs manquants", "Ask the group for missing buffs")
function _G.AuraCore_DemanderBuffs() M.Envoyer() end

-- Traductions des textes ci-dessus.
local AJOUTS = {
    deDE = { ["a blessing"] = "einen Segen", ["the whole group"] = "die ganze Gruppe", ["for"] = "für",
        ["Missing buffs : "] = "Fehlende Stärkungen : ", ["Thanks!"] = "Danke!", ["You are not in a group."] = "Du bist in keiner Gruppe.",
        ["Out of combat only."] = "Nur außerhalb des Kampfes.", ["Nothing to ask : everyone has the buffs your group can give."] = "Nichts zu erbitten : alle haben die Stärkungen, die eure Gruppe geben kann.",
        ["Wait a few seconds before asking again."] = "Warte ein paar Sekunden, bevor du erneut fragst.",
        ["Ask the group for missing buffs"] = "Gruppe um fehlende Stärkungen bitten", ["Ask"] = "Bitten", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off blendet alles aus, /auracore on zeigt es wieder, /auracore buffs bittet um fehlende Stärkungen.", ["Minor spells"] = "Kleine Zauber", ["Other players' minor spells"] = "Kleine Zauber der anderen", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Echte Stärkungen (Segen, Seelenstärke, Arkane Intelligenz, Mal der Wildnis) haben immer ihren Platz in ihrem Viertel. Kleine Zauber, kurz oder situativ, sind ausgeblendet : hake die an, die du im Ring sehen willst.", ["Ask for missing buffs"] = "Fehlende Stärkungen erbitten", ["Shift + drag : move the button."] = "Umschalt + ziehen : Knopf verschieben.", ["Button above the portrait"] = "Knopf über dem Porträt", ["Reset"] = "Zurücksetzen", ["Tracked buffs"] = "Verfolgte Stärkungen", ["The buffs you track"] = "Die Stärkungen, die du verfolgst", ["Everything each class can give you. Tick what you want to see in the ring. Real buffs (ticked by default) have their place in the group quarter ; the others follow the other icons."] = "Alles, was jede Klasse dir geben kann. Hake an, was du im Ring sehen willst. Echte Stärkungen (standardmäßig angehakt) haben ihren Platz im Gruppenviertel ; die anderen folgen den übrigen Symbolen.", ["Blessings"] = "Segen", ["Paladin auras"] = "Paladinauren", ["Resistance totems"] = "Widerstandstotems", ["Missing : inner opacity"] = "Fehlend : Deckkraft innen", ["Ring linked to the inside"] = "Ring an das Innere gekoppelt", ["Missing : ring opacity"] = "Fehlend : Deckkraft des Rings", ["Display"] = "Anzeige", ["Missing icons"] = "Fehlende Symbole", ["Reserved quarters"] = "Reservierte Viertel", ["Ask for buffs"] = "Stärkungen erbitten", ["Where to show it"] = "Wo anzeigen", ["The circle"] = "Der Kreis", ["Arrival order"] = "Reihenfolge" },
    esES = { ["a blessing"] = "una bendición", ["the whole group"] = "todo el grupo", ["for"] = "para",
        ["Missing buffs : "] = "Beneficios que faltan : ", ["Thanks!"] = "¡Gracias!", ["You are not in a group."] = "No estás en un grupo.",
        ["Out of combat only."] = "Solo fuera de combate.", ["Nothing to ask : everyone has the buffs your group can give."] = "Nada que pedir : todos tienen los beneficios que tu grupo puede dar.",
        ["Wait a few seconds before asking again."] = "Espera unos segundos antes de volver a pedir.",
        ["Ask the group for missing buffs"] = "Pedir al grupo los beneficios que faltan", ["Ask"] = "Pedir", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off lo oculta todo, /auracore on lo vuelve a mostrar, /auracore buffs pide los beneficios que faltan.", ["Minor spells"] = "Hechizos menores", ["Other players' minor spells"] = "Hechizos menores de los demás", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Los beneficios reales (bendiciones, Entereza, Intelecto Arcano, Marca de lo Salvaje) siempre tienen su lugar en su cuarto. Los hechizos menores, cortos o de situación, están ocultos : marca los que quieras ver en el anillo.", ["Ask for missing buffs"] = "Pedir los beneficios que faltan", ["Shift + drag : move the button."] = "Mayús + arrastrar : mover el botón.", ["Button above the portrait"] = "Botón sobre el retrato", ["Reset"] = "Restablecer", ["Tracked buffs"] = "Beneficios seguidos", ["The buffs you track"] = "Los beneficios que sigues", ["Everything each class can give you. Tick what you want to see in the ring. Real buffs (ticked by default) have their place in the group quarter ; the others follow the other icons."] = "Todo lo que cada clase puede darte. Marca lo que quieras ver en el anillo. Los beneficios reales (marcados por defecto) tienen su sitio en el cuarto del grupo ; los demás siguen a los otros iconos.", ["Blessings"] = "Bendiciones", ["Paladin auras"] = "Auras de paladín", ["Resistance totems"] = "Tótems de resistencia", ["Missing : inner opacity"] = "Ausentes : opacidad interior", ["Ring linked to the inside"] = "Anillo ligado al interior", ["Missing : ring opacity"] = "Ausentes : opacidad del anillo", ["Display"] = "Visualización", ["Missing icons"] = "Iconos ausentes", ["Reserved quarters"] = "Cuartos reservados", ["Ask for buffs"] = "Pedir beneficios", ["Where to show it"] = "Dónde mostrarla", ["The circle"] = "El círculo", ["Arrival order"] = "Orden de llegada" },
    itIT = { ["a blessing"] = "una benedizione", ["the whole group"] = "tutto il gruppo", ["for"] = "per",
        ["Missing buffs : "] = "Benefici mancanti : ", ["Thanks!"] = "Grazie!", ["You are not in a group."] = "Non sei in un gruppo.",
        ["Out of combat only."] = "Solo fuori dal combattimento.", ["Nothing to ask : everyone has the buffs your group can give."] = "Niente da chiedere : tutti hanno i benefici che il gruppo può dare.",
        ["Wait a few seconds before asking again."] = "Attendi qualche secondo prima di chiedere di nuovo.",
        ["Ask the group for missing buffs"] = "Chiedi al gruppo i benefici mancanti", ["Ask"] = "Chiedi", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off nasconde tutto, /auracore on lo mostra di nuovo, /auracore buffs chiede i benefici mancanti.", ["Minor spells"] = "Incantesimi minori", ["Other players' minor spells"] = "Incantesimi minori degli altri", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "I veri benefici (benedizioni, Tempra, Intelletto Arcano, Marchio della Natura) hanno sempre il loro posto nel loro quarto. Gli incantesimi minori, brevi o di situazione, sono nascosti : spunta quelli che vuoi vedere nell'anello.", ["Ask for missing buffs"] = "Chiedi i benefici mancanti", ["Shift + drag : move the button."] = "Maiusc + trascina : sposta il pulsante.", ["Button above the portrait"] = "Pulsante sopra il ritratto", ["Reset"] = "Ripristina", ["Tracked buffs"] = "Benefici seguiti", ["The buffs you track"] = "I benefici che segui", ["Everything each class can give you. Tick what you want to see in the ring. Real buffs (ticked by default) have their place in the group quarter ; the others follow the other icons."] = "Tutto ciò che ogni classe può darti. Spunta ciò che vuoi vedere nell'anello. I veri benefici (spuntati di base) hanno il loro posto nel quarto del gruppo ; gli altri seguono le altre icone.", ["Blessings"] = "Benedizioni", ["Paladin auras"] = "Aure del paladino", ["Resistance totems"] = "Totem di resistenza", ["Missing : inner opacity"] = "Mancanti : opacità interna", ["Ring linked to the inside"] = "Anello legato all'interno", ["Missing : ring opacity"] = "Mancanti : opacità dell'anello", ["Display"] = "Visualizzazione", ["Missing icons"] = "Icone mancanti", ["Reserved quarters"] = "Quarti riservati", ["Ask for buffs"] = "Chiedi benefici", ["Where to show it"] = "Dove mostrarla", ["The circle"] = "Il cerchio", ["Arrival order"] = "Ordine di arrivo" },
    ruRU = { ["a blessing"] = "благословение", ["the whole group"] = "вся группа", ["for"] = "для",
        ["Missing buffs : "] = "Не хватает эффектов : ", ["Thanks!"] = "Спасибо!", ["You are not in a group."] = "Вы не в группе.",
        ["Out of combat only."] = "Только вне боя.", ["Nothing to ask : everyone has the buffs your group can give."] = "Нечего просить : у всех есть эффекты, которые может дать группа.",
        ["Wait a few seconds before asking again."] = "Подождите несколько секунд перед новой просьбой.",
        ["Ask the group for missing buffs"] = "Попросить группу о недостающих эффектах", ["Ask"] = "Попросить", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off скрывает всё, /auracore on показывает снова, /auracore buffs просит недостающие эффекты.", ["Minor spells"] = "Малые заклинания", ["Other players' minor spells"] = "Малые заклинания других", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Настоящие эффекты (благословения, Стойкость, Чародейский интеллект, Знак дикой природы) всегда на своём месте в своей четверти. Малые заклинания, короткие или ситуативные, скрыты : отметьте те, что хотите видеть в кольце.", ["Ask for missing buffs"] = "Попросить недостающие эффекты", ["Shift + drag : move the button."] = "Shift + перетаскивание : переместить кнопку.", ["Button above the portrait"] = "Кнопка над портретом", ["Reset"] = "Сбросить", ["Tracked buffs"] = "Отслеживаемые эффекты", ["The buffs you track"] = "Эффекты, которые вы отслеживаете", ["Everything each class can give you. Tick what you want to see in the ring. Real buffs (ticked by default) have their place in the group quarter ; the others follow the other icons."] = "Всё, что вам может дать каждый класс. Отметьте, что хотите видеть в кольце. Настоящие эффекты (отмечены по умолчанию) стоят в четверти группы ; остальные идут следом за другими значками.", ["Blessings"] = "Благословения", ["Paladin auras"] = "Ауры паладина", ["Resistance totems"] = "Тотемы сопротивления", ["Missing : inner opacity"] = "Отсутствующие : непрозрачность внутри", ["Ring linked to the inside"] = "Кольцо связано с серединой", ["Missing : ring opacity"] = "Отсутствующие : непрозрачность кольца", ["Display"] = "Отображение", ["Missing icons"] = "Отсутствующие значки", ["Reserved quarters"] = "Зарезервированные четверти", ["Ask for buffs"] = "Попросить эффекты", ["Where to show it"] = "Где показывать", ["The circle"] = "Круг", ["Arrival order"] = "Порядок появления" },
    zhCN = { ["a blessing"] = "一个祝福", ["the whole group"] = "全队", ["for"] = "给",
        ["Missing buffs : "] = "缺少的增益 : ", ["Thanks!"] = "谢谢！", ["You are not in a group."] = "你不在队伍中。",
        ["Out of combat only."] = "仅限非战斗中。", ["Nothing to ask : everyone has the buffs your group can give."] = "无需请求 : 每个人都有队伍能给的增益。",
        ["Wait a few seconds before asking again."] = "请稍等几秒再请求。",
        ["Ask the group for missing buffs"] = "向队伍请求缺少的增益", ["Ask"] = "请求", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off 隐藏全部，/auracore on 重新显示，/auracore buffs 请求缺少的增益。", ["Minor spells"] = "次要法术", ["Other players' minor spells"] = "他人的次要法术", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "真正的增益（祝福、坚韧、奥术智慧、野性印记）始终在各自的四分之一处。次要法术（短时或特定情况）默认隐藏 : 勾选你想在圆环中看到的。", ["Ask for missing buffs"] = "请求缺少的增益", ["Shift + drag : move the button."] = "Shift + 拖动 : 移动按钮。", ["Button above the portrait"] = "头像上方的按钮", ["Reset"] = "重置", ["Tracked buffs"] = "追踪的增益", ["The buffs you track"] = "你追踪的增益", ["Everything each class can give you. Tick what you want to see in the ring. Real buffs (ticked by default) have their place in the group quarter ; the others follow the other icons."] = "每个职业能给你的一切。勾选你想在圆环中看到的。真正的增益（默认勾选）位于队伍的四分之一处；其他的排在其他图标之后。", ["Blessings"] = "祝福", ["Paladin auras"] = "圣骑士光环", ["Resistance totems"] = "抗性图腾", ["Missing : inner opacity"] = "缺少 : 内部不透明度", ["Ring linked to the inside"] = "圆圈与内部联动", ["Missing : ring opacity"] = "缺少 : 圆圈不透明度", ["Display"] = "显示", ["Missing icons"] = "缺少的图标", ["Reserved quarters"] = "保留的四分之一", ["Ask for buffs"] = "请求增益", ["Where to show it"] = "显示位置", ["The circle"] = "圆圈", ["Arrival order"] = "出现顺序" },
}
for code, t in pairs(AJOUTS) do
    NS.TRAD[code] = NS.TRAD[code] or {}
    for k, v in pairs(t) do NS.TRAD[code][k] = v end
end
