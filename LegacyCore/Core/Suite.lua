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

local VERSION = 27

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
Suite.ORDRE = {
    { cle = "CraftCore", icone = "Interface\\Icons\\INV_Misc_Gear_01" },
    { cle = "QuestCore", icone = "Interface\\Icons\\INV_Misc_Book_08" },
    { cle = "MapCore", icone = "Interface\\Icons\\INV_Misc_Map_01" },
    { cle = "LegacyCore", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    -- Discret : montre seulement s'il est installe (pas dans la premiere
    -- version publiee).
    { cle = "TradeCore", icone = "Interface\\Icons\\INV_Misc_Coin_02", discret = true },
}
-- Les add-ons annonces des leur chargement (avant les fenetres).
Suite.presents = Suite.presents or {}
function Suite.Annoncer(cle) Suite.presents[cle] = true end

-- Les add-ons a montrer : tous, sauf les discrets absents.
function Suite.Liste()
    local liste = {}
    for _, info in ipairs(Suite.ORDRE) do
        if not info.discret or Suite.presents[info.cle] or Suite.membres[info.cle] then table.insert(liste, info) end
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
        ["Click: show everything"] = "Clic : tout afficher",
        ["Click: hide everything"] = "Clic : tout masquer",
        ["Faction theme"] = "Thème de faction",
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
        ["Common to the whole suite."] = "Communs à toute la suite.",
        ["Language"] = "Langue",
        ["Game language"] = "Langue du jeu",
        ["Apply (reloads the interface)"] = "Appliquer (recharge l'interface)",
        ["Close"] = "Fermer",
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
    for _, im in ipairs(ILLUSTRATIONS[Suite.Theme()] or {}) do
        -- Le jeu accepte n'importe quel chemin ; seul GetTexture dit si
        -- l'image existe vraiment dans ce client.
        if pcall(tex.SetTexture, tex, im.fichier) and tex:GetTexture() then
            tex.suiteIllustration = im
            -- A demi grise : l'image reste reconnaissable sans crier.
            if tex.SetDesaturation then tex:SetDesaturation(Suite.GRIS_FOND) else tex:SetDesaturated(true) end
            local v = Suite.LUMIERE_FOND
            tex:SetVertexColor(v, v, v)
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
    tex:SetShown(ok and not tex.suiteMasque)
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

function Suite.AppliquerTheme()
    for _, tex in ipairs(Suite.logos) do pcall(Suite.Logo, tex) end
    for _, tex in ipairs(Suite.fondsFaction) do
        if not Suite.FondDeFaction(tex) and NS.charte and NS.charte.FondDuJournal then
            pcall(NS.charte.FondDuJournal, tex)
        end
    end
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
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
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
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
        if not Suite.Installe(self.cle) then GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- ---------------------------------------------------------------------------
-- Dans chaque fenetre : les icones, en haut a droite de l'en-tete
-- ---------------------------------------------------------------------------

Suite.entetes = Suite.entetes or {}

local function OngletLateral(parent, info, auClic)
    -- L'onglet du grimoire du jeu, dessin retourne pour le bord gauche :
    -- c'est un fichier (pas un atlas), le retournement tient. Meme dessin
    -- que les onglets des membres du groupe, a cote du suivi des quetes.
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(34, 34)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    b.fond:SetTexCoord(1, 0, 0, 1)
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
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
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
local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

-- ---------------------------------------------------------------------------
-- Reglages generaux : communs a toute la suite (pour l'instant la langue).
-- Une petite roue dans le pied de chaque fenetre, a gauche de Fermer.
-- ---------------------------------------------------------------------------

function Suite.OuvrirReglagesGeneraux()
    local c = Suite.reglagesGeneraux
    if not c then
        local charte = NS.charte
        if charte and charte.Fenetre then
            c = charte.Fenetre("CoreSuiteReglages", 360, 380, { portrait = false })
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
        -- Fond : l'illustration de la faction, sur la zone sombre.
        local zoneFond = c.Inset or c.fond
        if zoneFond and zoneFond.CreateTexture then
            local t = zoneFond:CreateTexture(nil, "BACKGROUND", nil, 5)
            t:SetPoint("TOPLEFT", zoneFond, "TOPLEFT", 3, -3)
            t:SetPoint("BOTTOMRIGHT", zoneFond, "BOTTOMRIGHT", -3, 3)
            if not Suite.FondDeFaction(t) then t:Hide() end
        end
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
    c:SetHeight(380)
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
            if cle ~= cleCourante and Suite.Installe(cle) then Suite.Ouvrir(cle) end
        end)
        b.courante = cleCourante
        b:ClearAllPoints()
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
    rangee.l3:SetPoint("BOTTOM", rangee.boutons[1], "TOP", 0, 12)
    rangee.r3 = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rangee.r3:SetPoint("TOP", rangee.boutons[#rangee.boutons], "BOTTOM", 0, -10)
    pcall(BoutonReglages, cadre)
    -- Tout en bas de la colonne : Alliance et Horde, pour le theme.
    rangee.factions = {}
    local dessous
    for _, faction in ipairs(Suite.Prive() and { "horde", "alliance" } or {}) do
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
    rangee.cadre = cadre
    pcall(Suite.LogoDuMenu, cadre)
    cadre.suiteEntete = rangee
    cadre:HookScript("OnShow", function(self)
        Suite.PrendrePlace(cleCourante, self)
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
function Suite.Voisin(cleCourante, pas)
    local liste = {}
    for _, info in ipairs(Suite.Liste()) do
        if Suite.Installe(info.cle) then table.insert(liste, info.cle) end
    end
    if #liste < 2 then return false end
    local index = 1
    for rang, cle in ipairs(liste) do if cle == cleCourante then index = rang end end
    Suite.Ouvrir(liste[((index - 1 + pas) % #liste) + 1])
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
    -- Menu (Start) : les reglages generaux.
    if bouton == "PADFORWARD" then
        Suite.OuvrirReglagesGeneraux()
        return true
    end
    if bouton == "PADLSTICK" or bouton == "PADRSTICK" then
        Suite.Voisin(cleCourante, bouton == "PADLSTICK" and -1 or 1)
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
        if cible then Suite.Ouvrir(cible) end
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
            local reg = rangee.cadre and rangee.cadre.suiteReglages
            if reg then reg:SetText((pad and (GlyphePad("PADFORWARD") .. " ") or "") .. TX("Settings")) end
        end
        for _, b in ipairs(rangee.boutons) do
            local installe = Suite.Installe(b.cle)
            local courant = b.cle == rangee.courante
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
-- montre la direction de la prochaine etape d'un trajet (tournee de rendu de
-- QuestCore, tournee de recolte de MapCore...), avec la distance. Un seul
-- guidage a la fois : en lancer un arrete le precedent.
--   Suite.Guider(cle, fournisseur) ; Suite.ArreterGuidage(cle) ;
--   Suite.GuidageActif(cle).
-- fournisseur = {
--   Cible = function() -> { carte, x, y, qui, rang, total, titre } ou nil, raison
--           (raison "fini" : le trajet est termine, le guidage s'arrete),
--   Arrivee = function(cible) (facultatif : le personnage est arrive),
--   Clic = function() (facultatif : clic sur la fleche),
--   Fin = function() (le guidage s'arrete, quelle qu'en soit la raison) }
-- ---------------------------------------------------------------------------

local TG = Paresseux({
    titre = "Path guidance",
    aide = "Drag: move up or down. Right-click: stop guiding.",
    loin = "Out of range",
})

Suite.guide = Suite.guide or {}

function Suite.GuidageActif(cle)
    local g = Suite.guide
    return g.cle ~= nil and (cle == nil or g.cle == cle)
end

local function PositionMonde(carte, x, y)
    local f, V = _G.C_Map and _G.C_Map.GetWorldPosFromMapPos, _G.CreateVector2D
    if not (f and V and carte and x) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        return a, b, continent
    end
    return nil
end

local function PositionJoueur()
    local carte = _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetBestMapForUnit("player")
    local pos = carte and _G.C_Map.GetPlayerMapPosition and _G.C_Map.GetPlayerMapPosition(carte, "player")
    if not (pos and pos.GetXY) then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    return PositionMonde(carte, x, y)
end

local function CadreGuidage()
    local g = Suite.guide
    if g.cadre then return g.cadre end
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
        if bouton == "RightButton" then Suite.ArreterGuidage() return end
        local f = Suite.guide.fournisseur
        if f and f.Clic then pcall(f.Clic) end
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(TG.titre, 1, 0.82, 0)
        if self.titre then GameTooltip:AddLine(self.titre, 1, 1, 1) end
        local f = Suite.guide.fournisseur
        if f and f.AideClic then GameTooltip:AddLine(f.AideClic, 0.7, 0.7, 0.7, true) end
        GameTooltip:AddLine(TG.aide, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- La fleche seule (celle du personnage sur la minicarte), bien centree.
    c.fleche = c:CreateTexture(nil, "ARTWORK")
    c.fleche:SetSize(56, 56)
    c.fleche:SetPoint("CENTER")
    c.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    c.arrivee = c:CreateTexture(nil, "ARTWORK")
    c.arrivee:SetSize(32, 32)
    c.arrivee:SetPoint("CENTER")
    c.arrivee:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    c.distance = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.distance:SetPoint("TOP", c, "BOTTOM", 0, -2)
    c.qui = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.qui:SetPoint("TOP", c.distance, "BOTTOM", 0, -1)
    local attente = 0
    c:SetScript("OnUpdate", function(self, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.05
        local f = Suite.guide.fournisseur
        if not f then self:Hide() return end
        local ok, cible, raison = pcall(f.Cible)
        if not ok then return end
        if not cible then
            if raison == "fini" then Suite.ArreterGuidage() return end
            self.fleche:Hide() self.arrivee:Hide()
            self.distance:SetText(TG.loin)
            self.qui:SetText("")
            return
        end
        self.titre = cible.titre
        if cible.rang and cible.total then
            self.qui:SetText(string.format("%d/%d  %s", cible.rang, cible.total, cible.qui or ""))
        else
            self.qui:SetText(cible.qui or "")
        end
        local ax, ay, ca = PositionJoueur()
        local bx, by, cb = PositionMonde(cible.carte, cible.x, cible.y)
        if not (ax and bx) or (ca and cb and ca ~= cb) then
            self.fleche:Hide() self.arrivee:Hide()
            self.distance:SetText(TG.loin)
            return
        end
        local nord, ouest = bx - ax, by - ay
        local yards = math.sqrt(nord * nord + ouest * ouest)
        self.distance:SetText(string.format("%d m", math.floor(yards * 0.9144 + 0.5)))
        if yards < 12 then
            self.fleche:Hide()
            self.arrivee:Show()
            if f.Arrivee then pcall(f.Arrivee, cible) end
            return
        end
        self.arrivee:Hide()
        self.fleche:Show()
        local face = tonumber(_G.GetPlayerFacing and _G.GetPlayerFacing()) or 0
        local angle = math.atan2(ouest, nord) - face
        if self.fleche.SetRotation then self.fleche:SetRotation(angle) end
        -- Verte quand on va droit dessus, doree sinon.
        local ecart = math.abs(((angle + math.pi) % (2 * math.pi)) - math.pi)
        if ecart < 0.35 then self.fleche:SetVertexColor(0.4, 1, 0.4) else self.fleche:SetVertexColor(1, 0.82, 0) end
    end)
    c:Hide()
    g.cadre = c
    return c
end

function Suite.Guider(cle, fournisseur)
    local g = Suite.guide
    if g.cle and g.cle ~= cle and g.fournisseur and g.fournisseur.Fin then
        local ancien = g.fournisseur
        g.cle, g.fournisseur = nil, nil
        pcall(ancien.Fin)
    end
    g.cle, g.fournisseur = cle, fournisseur
    CadreGuidage():Show()
    -- Partout ou l'on guide, la carte de MapCore s'ouvre sur la destination,
    -- qui y clignote. Sauf si le guidage part deja d'une carte (carte = false).
    if fournisseur and fournisseur.carte ~= false then
        local api = _G.MapCoreAPI
        if api and api.Montrer and fournisseur.Cible then
            local ok, pt = pcall(fournisseur.Cible)
            if ok and type(pt) == "table" and pt.carte and pt.x and pt.y then
                pcall(api.Montrer, { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.qui or pt.titre,
                    icone = fournisseur.icone })
            end
        end
    end
end

function Suite.ArreterGuidage(cle)
    local g = Suite.guide
    if cle and g.cle ~= cle then return end
    local f = g.fournisseur
    g.cle, g.fournisseur = nil, nil
    if g.cadre then g.cadre:Hide() end
    if f and f.Fin then pcall(f.Fin) end
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
