local _, NS = ...

-- Ce que l'anneau reconnait (WoW Forever, contenu classique). Les sorts sont
-- donnes par un identifiant de rang 1 : seul leur nom compte (il est le meme
-- a tous les rangs, dans la langue du jeu).

NS.donnees = {}
local D = NS.donnees

-- Les vrais buffs de groupe : longs, donnes a tout le monde, par classe
-- qui peut les donner. Chaque entree est une liste d'alternatives (le meme
-- effet en version individuelle ou de groupe).
D.GROUPE = {
    PRIEST = { { 1243, 21562 } },                                   -- Robustesse
    MAGE = { { 1459, 23028 } },                                     -- Intelligence des Arcanes
    DRUID = { { 1126, 21849 } },                                    -- Marque du fauve
    PALADIN = { { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890, 20911, 25899 } }, -- Benedictions
}

-- Les petits sorts des autres : courts, de situation ou de talent. Caches
-- par defaut ; chacun se choisit dans la page "Petits sorts".
D.PETITS = {
    { cle = "ombre", ids = { 976, 27683 } },    -- Protection contre l'Ombre
    { cle = "esprit", ids = { 14752, 27681 } }, -- Esprit divin
    { cle = "epines", ids = { 467 } },          -- Epines
    { cle = "cri", ids = { 6673 } },            -- Cri de guerre
    { cle = "precision", ids = { 19506 } },     -- Aura de precision
}

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
        table.insert(liste, { unite = unite, nom = Court(nom), classe = classe })
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
    local donneursPar, auras = {}, {}
    for _, m in ipairs(membres) do
        if m.classe then
            donneursPar[m.classe] = donneursPar[m.classe] or {}
            table.insert(donneursPar[m.classe], m.nom)
        end
        auras[m.nom] = NomsDAuras(m.unite)
    end
    local resultat = {}
    for _, f in ipairs(FAMILLES) do
        local donneurs = donneursPar[f.classe]
        if donneurs then
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
                    local buff = f.benediction and T("une bénédiction", "a blessing") or (D.Nom(f.ids[1]) or "?")
                    table.insert(resultat, { buff = buff, manquants = manquants, donneurs = donneurs,
                        tous = #manquants == #membres and #membres > 1 })
                end
            end
        end
    end
    return resultat
end

-- Le texte du message, en morceaux de moins de 255 caracteres.
function M.Messages(analyse)
    local parts = {}
    for _, a in ipairs(analyse) do
        local qui = a.tous and T("tout le groupe", "the whole group") or table.concat(a.manquants, ", ")
        table.insert(parts, string.format("%s %s %s (%s)", a.buff, T("pour", "for"), qui, table.concat(a.donneurs, ", ")))
    end
    if #parts == 0 then return {} end
    local messages, courant = {}, T("Buffs manquants : ", "Missing buffs : ")
    for k, p in ipairs(parts) do
        local suite = (k == #parts) and (p .. ". " .. T("Merci !", "Thanks!")) or (p .. " ; ")
        if #courant + #suite > 250 then
            table.insert(messages, courant)
            courant = ""
        end
        courant = courant .. suite
    end
    table.insert(messages, courant)
    return messages
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
    local messages = M.Messages(M.Analyser())
    if #messages == 0 then return T("Rien à demander : chacun a les buffs que le groupe peut donner.", "Nothing to ask : everyone has the buffs your group can give.") end
    return table.concat(messages, " ")
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
    local messages = M.Messages(M.Analyser())
    if #messages == 0 then
        NS.Dire(T("Rien à demander : chacun a les buffs que le groupe peut donner.", "Nothing to ask : everyone has the buffs your group can give."))
        return
    end
    dernier = maintenant
    local envoyer = (_G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    for _, texte in ipairs(messages) do pcall(envoyer, texte, canal) end
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
        ["Ask the group for missing buffs"] = "Gruppe um fehlende Stärkungen bitten", ["Ask"] = "Bitten", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off blendet alles aus, /auracore on zeigt es wieder, /auracore buffs bittet um fehlende Stärkungen.", ["Minor spells"] = "Kleine Zauber", ["Other players' minor spells"] = "Kleine Zauber der anderen", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Echte Stärkungen (Segen, Seelenstärke, Arkane Intelligenz, Mal der Wildnis) haben immer ihren Platz in ihrem Viertel. Kleine Zauber, kurz oder situativ, sind ausgeblendet : hake die an, die du im Ring sehen willst." },
    esES = { ["a blessing"] = "una bendición", ["the whole group"] = "todo el grupo", ["for"] = "para",
        ["Missing buffs : "] = "Beneficios que faltan : ", ["Thanks!"] = "¡Gracias!", ["You are not in a group."] = "No estás en un grupo.",
        ["Out of combat only."] = "Solo fuera de combate.", ["Nothing to ask : everyone has the buffs your group can give."] = "Nada que pedir : todos tienen los beneficios que tu grupo puede dar.",
        ["Wait a few seconds before asking again."] = "Espera unos segundos antes de volver a pedir.",
        ["Ask the group for missing buffs"] = "Pedir al grupo los beneficios que faltan", ["Ask"] = "Pedir", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off lo oculta todo, /auracore on lo vuelve a mostrar, /auracore buffs pide los beneficios que faltan.", ["Minor spells"] = "Hechizos menores", ["Other players' minor spells"] = "Hechizos menores de los demás", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Los beneficios reales (bendiciones, Entereza, Intelecto Arcano, Marca de lo Salvaje) siempre tienen su lugar en su cuarto. Los hechizos menores, cortos o de situación, están ocultos : marca los que quieras ver en el anillo." },
    itIT = { ["a blessing"] = "una benedizione", ["the whole group"] = "tutto il gruppo", ["for"] = "per",
        ["Missing buffs : "] = "Benefici mancanti : ", ["Thanks!"] = "Grazie!", ["You are not in a group."] = "Non sei in un gruppo.",
        ["Out of combat only."] = "Solo fuori dal combattimento.", ["Nothing to ask : everyone has the buffs your group can give."] = "Niente da chiedere : tutti hanno i benefici che il gruppo può dare.",
        ["Wait a few seconds before asking again."] = "Attendi qualche secondo prima di chiedere di nuovo.",
        ["Ask the group for missing buffs"] = "Chiedi al gruppo i benefici mancanti", ["Ask"] = "Chiedi", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off nasconde tutto, /auracore on lo mostra di nuovo, /auracore buffs chiede i benefici mancanti.", ["Minor spells"] = "Incantesimi minori", ["Other players' minor spells"] = "Incantesimi minori degli altri", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "I veri benefici (benedizioni, Tempra, Intelletto Arcano, Marchio della Natura) hanno sempre il loro posto nel loro quarto. Gli incantesimi minori, brevi o di situazione, sono nascosti : spunta quelli che vuoi vedere nell'anello." },
    ruRU = { ["a blessing"] = "благословение", ["the whole group"] = "вся группа", ["for"] = "для",
        ["Missing buffs : "] = "Не хватает эффектов : ", ["Thanks!"] = "Спасибо!", ["You are not in a group."] = "Вы не в группе.",
        ["Out of combat only."] = "Только вне боя.", ["Nothing to ask : everyone has the buffs your group can give."] = "Нечего просить : у всех есть эффекты, которые может дать группа.",
        ["Wait a few seconds before asking again."] = "Подождите несколько секунд перед новой просьбой.",
        ["Ask the group for missing buffs"] = "Попросить группу о недостающих эффектах", ["Ask"] = "Попросить", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off скрывает всё, /auracore on показывает снова, /auracore buffs просит недостающие эффекты.", ["Minor spells"] = "Малые заклинания", ["Other players' minor spells"] = "Малые заклинания других", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "Настоящие эффекты (благословения, Стойкость, Чародейский интеллект, Знак дикой природы) всегда на своём месте в своей четверти. Малые заклинания, короткие или ситуативные, скрыты : отметьте те, что хотите видеть в кольце." },
    zhCN = { ["a blessing"] = "一个祝福", ["the whole group"] = "全队", ["for"] = "给",
        ["Missing buffs : "] = "缺少的增益 : ", ["Thanks!"] = "谢谢！", ["You are not in a group."] = "你不在队伍中。",
        ["Out of combat only."] = "仅限非战斗中。", ["Nothing to ask : everyone has the buffs your group can give."] = "无需请求 : 每个人都有队伍能给的增益。",
        ["Wait a few seconds before asking again."] = "请稍等几秒再请求。",
        ["Ask the group for missing buffs"] = "向队伍请求缺少的增益", ["Ask"] = "请求", ["/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."] = "/auracore off 隐藏全部，/auracore on 重新显示，/auracore buffs 请求缺少的增益。", ["Minor spells"] = "次要法术", ["Other players' minor spells"] = "他人的次要法术", ["Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."] = "真正的增益（祝福、坚韧、奥术智慧、野性印记）始终在各自的四分之一处。次要法术（短时或特定情况）默认隐藏 : 勾选你想在圆环中看到的。" },
}
for code, t in pairs(AJOUTS) do
    NS.TRAD[code] = NS.TRAD[code] or {}
    for k, v in pairs(t) do NS.TRAD[code][k] = v end
end
