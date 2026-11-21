local _, NS = ...

-- Langues d'AuraCore : francais et anglais dans le code (T(fr, en)), les
-- cinq autres ici, cherchees par le texte anglais. La langue est celle de la
-- suite (reglages generaux), sinon celle du jeu.

local TRAD = {}
NS.TRAD = TRAD

local CORRESPONDANCE = { esMX = "esES", zhTW = "zhCN", enGB = "enUS" }
local function Langue()
    local S = _G.CoreSuite
    if S and S.Langue then return S.Langue() end
    local code = (GetLocale and GetLocale()) or "enUS"
    return CORRESPONDANCE[code] or code
end

function NS.T(fr, en)
    local code = Langue()
    if code == "frFR" then return fr end
    local t = TRAD[code]
    return (t and t[en]) or en
end

TRAD.deDE = {
    ["beta"] = "Beta",
    ["Food"] = "Essen", ["Flask or elixir"] = "Fläschchen oder Elixier", ["Debuff"] = "Schwächung", ["Buff"] = "Stärkung",
    ["Potion"] = "Trank", ["In your bags : "] = "In deinen Taschen : ", ["Given by : "] = "Gewirkt von : ",
    ["Active"] = "Aktiv", ["Missing"] = "Fehlt", ["Active : "] = "Aktiv : ", ["State read before combat."] = "Zustand vor dem Kampf gelesen.",
    ["Balanced"] = "Ausgewogen", ["In a row"] = "Hintereinander", ["Reserved places"] = "Feste Plätze",
    ["Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes."] = "Aktive Symbole verteilen sich über den ganzen freien Bogen. Zwei Symbole : einander gegenüber. Alle verschieben sich, wenn eines kommt oder geht.",
    ["Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active."] = "Aktive Symbole folgen nebeneinander ab dem Startpunkt. Nichts ist reserviert : dein Aspekt erscheint nur, wenn er aktiv ist.",
    ["What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place."] = "Was du dir selbst gibst (Aspekt, Aura, Rüstung) hat einen festen Platz, grau wenn es fehlt. Procs folgen, jeder an seinem Platz.",
    ["Activate"] = "Aktivieren", ["Layout"] = "Anordnung", ["Top"] = "Oben", ["Right"] = "Rechts", ["Bottom"] = "Unten", ["Left"] = "Links",
    ["Clockwise"] = "Im Uhrzeigersinn", ["Counterclockwise"] = "Gegen den Uhrzeigersinn", ["Icon layout"] = "Anordnung der Symbole",
    ["How the icons outside the reserved quarters are placed : what you put on yourself and what procs."] = "Wie die Symbole außerhalb der reservierten Viertel angeordnet werden : was du dir selbst gibst und was auslöst.",
    ["Starting point"] = "Startpunkt", ["Direction"] = "Richtung", ["The ring"] = "Der Ring", ["Small"] = "Klein", ["Medium"] = "Mittel", ["Large"] = "Groß",
    ["Inside the icon"] = "Im Symbol", ["Outside the icon"] = "Außerhalb des Symbols", ["Hidden"] = "Ausgeblendet",
    ["Decreasing"] = "Abnehmend", ["Increasing"] = "Zunehmend", ["Top quarter"] = "Oberes Viertel", ["Right quarter"] = "Rechtes Viertel",
    ["Bottom quarter"] = "Unteres Viertel", ["Left quarter"] = "Linkes Viertel", ["The ring around your character"] = "Der Ring um deinen Charakter",
    ["Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."] = "Sechzehn feste Plätze im Kreis um deinen Charakter. Farbig, was aktiv ist, grau, was fehlt. Fahre über ein Symbol, um zu sehen, was es ist.",
    ["Show the ring"] = "Ring anzeigen", ["Icon size"] = "Symbolgröße", ["Height on screen"] = "Höhe auf dem Bildschirm", ["Minimum radius"] = "Mindestradius",
    ["Ring opacity"] = "Deckkraft des Rings", ["Time left"] = "Restzeit", ["Duration circle"] = "Dauerkreis", ["Food, flask and potion"] = "Essen, Fläschchen und Trank",
    ["Their place"] = "Ihr Platz", ["Buffs your group can give"] = "Stärkungen deiner Gruppe",
    ["/auracore off hides everything, /auracore on shows it again."] = "/auracore off blendet alles aus, /auracore on zeigt es wieder.",
    ["Debuffs"] = "Schwächungen", ["Inside the ring"] = "Innerhalb des Rings", ["Outside the ring"] = "Außerhalb des Rings", ["Smaller"] = "Kleiner",
    ["Same as the ring"] = "Wie der Ring", ["Larger"] = "Größer", ["Top right"] = "Oben rechts", ["Bottom right"] = "Unten rechts",
    ["Bottom left"] = "Unten links", ["Top left"] = "Oben links",
    ["On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."] = "Auf einem eigenen Kreis, um den Ring oder in ihm, ohne ihn je zu berühren. Die erste nimmt Platz 1, die nächste Platz 2 und so weiter.",
    ["Separate circle"] = "Eigener Kreis", ["Position"] = "Position", ["Ring shown"] = "Ring angezeigt", ["Layout of the other icons"] = "Anordnung der übrigen Symbole",
    ["The suite"] = "Die Suite", ["Get the complete suite on CurseForge :"] = "Die komplette Suite gibt es auf CurseForge :",
    ["Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."] = "Klicke auf die Adresse und kopiere sie mit Strg+C (Cmd+C auf dem Mac).",
    ["AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."] = "AuraCore gehört zu Forever SagaCore, einer Add-on-Suite für WoW Forever : Herstellung und Berufe (CraftCore), Quests und Routen (QuestCore), Karte und Dienste (MapCore), Vermächtnis (LegacyCore). Zusammen installiert teilen sie ein Fenster, dieselben Einstellungen und dieselbe Gamepad-Steuerung.",
    ["in combat"] = "im Kampf", ["out of combat"] = "außerhalb des Kampfes", ["not read yet"] = "noch nicht gelesen",
}

TRAD.esES = {
    ["beta"] = "beta",
    ["Food"] = "Comida", ["Flask or elixir"] = "Frasco o elixir", ["Debuff"] = "Perjuicio", ["Buff"] = "Beneficio",
    ["Potion"] = "Poción", ["In your bags : "] = "En tus bolsas : ", ["Given by : "] = "Lo da : ",
    ["Active"] = "Activo", ["Missing"] = "Falta", ["Active : "] = "Activo : ", ["State read before combat."] = "Estado leído antes del combate.",
    ["Balanced"] = "Equilibrada", ["In a row"] = "En fila", ["Reserved places"] = "Lugares reservados",
    ["Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes."] = "Los iconos activos se reparten por todo el arco libre. Dos iconos : uno frente al otro. Todos se mueven cuando uno llega o se va.",
    ["Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active."] = "Los iconos activos se siguen, uno al lado del otro, desde el punto de partida. Nada está reservado : tu aspecto solo aparece si está activo.",
    ["What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place."] = "Lo que te pones tú mismo (aspecto, aura, armadura) tiene su lugar, en gris si falta. Los procs siguen, cada uno en su sitio.",
    ["Activate"] = "Activar", ["Layout"] = "Disposición", ["Top"] = "Arriba", ["Right"] = "Derecha", ["Bottom"] = "Abajo", ["Left"] = "Izquierda",
    ["Clockwise"] = "Horario", ["Counterclockwise"] = "Antihorario", ["Icon layout"] = "Disposición de los iconos",
    ["How the icons outside the reserved quarters are placed : what you put on yourself and what procs."] = "Cómo se colocan los iconos fuera de los cuartos reservados : lo que te pones tú mismo y lo que se activa.",
    ["Starting point"] = "Punto de partida", ["Direction"] = "Sentido", ["The ring"] = "El anillo", ["Small"] = "Pequeño", ["Medium"] = "Mediano", ["Large"] = "Grande",
    ["Inside the icon"] = "Dentro del icono", ["Outside the icon"] = "Fuera del icono", ["Hidden"] = "Oculta",
    ["Decreasing"] = "Decreciente", ["Increasing"] = "Creciente", ["Top quarter"] = "Cuarto superior", ["Right quarter"] = "Cuarto derecho",
    ["Bottom quarter"] = "Cuarto inferior", ["Left quarter"] = "Cuarto izquierdo", ["The ring around your character"] = "El anillo alrededor de tu personaje",
    ["Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."] = "Dieciséis lugares fijos en círculo alrededor de tu personaje. En color lo activo, en gris lo que falta. Pasa el ratón por un icono para ver qué es.",
    ["Show the ring"] = "Mostrar el anillo", ["Icon size"] = "Tamaño de los iconos", ["Height on screen"] = "Altura en pantalla", ["Minimum radius"] = "Radio mínimo",
    ["Ring opacity"] = "Opacidad del anillo", ["Time left"] = "Tiempo restante", ["Duration circle"] = "Círculo de duración", ["Food, flask and potion"] = "Comida, frasco y poción",
    ["Their place"] = "Su lugar", ["Buffs your group can give"] = "Beneficios de tu grupo",
    ["/auracore off hides everything, /auracore on shows it again."] = "/auracore off lo oculta todo, /auracore on lo vuelve a mostrar.",
    ["Debuffs"] = "Perjuicios", ["Inside the ring"] = "Dentro del anillo", ["Outside the ring"] = "Fuera del anillo", ["Smaller"] = "Más pequeños",
    ["Same as the ring"] = "Como el anillo", ["Larger"] = "Más grandes", ["Top right"] = "Arriba a la derecha", ["Bottom right"] = "Abajo a la derecha",
    ["Bottom left"] = "Abajo a la izquierda", ["Top left"] = "Arriba a la izquierda",
    ["On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."] = "En su propio círculo, alrededor o dentro del anillo, sin tocarlo nunca. El primero ocupa el lugar 1, el siguiente el 2, y así sucesivamente.",
    ["Separate circle"] = "Círculo aparte", ["Position"] = "Posición", ["Ring shown"] = "Anillo visible", ["Layout of the other icons"] = "Disposición de los demás iconos",
    ["The suite"] = "La suite", ["Get the complete suite on CurseForge :"] = "Consigue la suite completa en CurseForge :",
    ["Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."] = "Haz clic en la dirección y pulsa Ctrl+C (Cmd+C en Mac) para copiarla.",
    ["AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."] = "AuraCore forma parte de Forever SagaCore, una suite de addons para WoW Forever : fabricación y profesiones (CraftCore), misiones y rutas (QuestCore), mapa y servicios (MapCore), legado (LegacyCore). Instalados juntos, comparten una ventana, los mismos ajustes y los mismos controles de mando.",
    ["in combat"] = "en combate", ["out of combat"] = "fuera de combate", ["not read yet"] = "aún no leído",
}

TRAD.itIT = {
    ["beta"] = "beta",
    ["Food"] = "Cibo", ["Flask or elixir"] = "Tonico o elisir", ["Debuff"] = "Penalità", ["Buff"] = "Beneficio",
    ["Potion"] = "Pozione", ["In your bags : "] = "Nelle tue borse : ", ["Given by : "] = "Dato da : ",
    ["Active"] = "Attivo", ["Missing"] = "Mancante", ["Active : "] = "Attivo : ", ["State read before combat."] = "Stato letto prima del combattimento.",
    ["Balanced"] = "Equilibrata", ["In a row"] = "In fila", ["Reserved places"] = "Posti riservati",
    ["Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes."] = "Le icone attive si distribuiscono su tutto l'arco libero. Due icone : una di fronte all'altra. Si spostano tutte quando una arriva o se ne va.",
    ["Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active."] = "Le icone attive si seguono, una accanto all'altra, dal punto di partenza. Niente è riservato : il tuo aspetto appare solo se attivo.",
    ["What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place."] = "Ciò che ti applichi da solo (aspetto, aura, armatura) ha il suo posto, grigio se manca. I proc seguono, ognuno al suo posto.",
    ["Activate"] = "Attiva", ["Layout"] = "Disposizione", ["Top"] = "Alto", ["Right"] = "Destra", ["Bottom"] = "Basso", ["Left"] = "Sinistra",
    ["Clockwise"] = "Orario", ["Counterclockwise"] = "Antiorario", ["Icon layout"] = "Disposizione delle icone",
    ["How the icons outside the reserved quarters are placed : what you put on yourself and what procs."] = "Come si dispongono le icone fuori dai quarti riservati : ciò che ti applichi da solo e ciò che si attiva.",
    ["Starting point"] = "Punto di partenza", ["Direction"] = "Senso", ["The ring"] = "L'anello", ["Small"] = "Piccola", ["Medium"] = "Media", ["Large"] = "Grande",
    ["Inside the icon"] = "Nell'icona", ["Outside the icon"] = "Fuori dall'icona", ["Hidden"] = "Nascosta",
    ["Decreasing"] = "Decrescente", ["Increasing"] = "Crescente", ["Top quarter"] = "Quarto superiore", ["Right quarter"] = "Quarto destro",
    ["Bottom quarter"] = "Quarto inferiore", ["Left quarter"] = "Quarto sinistro", ["The ring around your character"] = "L'anello intorno al tuo personaggio",
    ["Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."] = "Sedici posti fissi in cerchio intorno al tuo personaggio. A colori ciò che è attivo, in grigio ciò che manca. Passa il mouse su un'icona per vedere cos'è.",
    ["Show the ring"] = "Mostra l'anello", ["Icon size"] = "Dimensione delle icone", ["Height on screen"] = "Altezza sullo schermo", ["Minimum radius"] = "Raggio minimo",
    ["Ring opacity"] = "Opacità dell'anello", ["Time left"] = "Tempo restante", ["Duration circle"] = "Cerchio di durata", ["Food, flask and potion"] = "Cibo, tonico e pozione",
    ["Their place"] = "Il loro posto", ["Buffs your group can give"] = "Benefici del tuo gruppo",
    ["/auracore off hides everything, /auracore on shows it again."] = "/auracore off nasconde tutto, /auracore on lo mostra di nuovo.",
    ["Debuffs"] = "Penalità", ["Inside the ring"] = "Dentro l'anello", ["Outside the ring"] = "Fuori dall'anello", ["Smaller"] = "Più piccole",
    ["Same as the ring"] = "Come l'anello", ["Larger"] = "Più grandi", ["Top right"] = "In alto a destra", ["Bottom right"] = "In basso a destra",
    ["Bottom left"] = "In basso a sinistra", ["Top left"] = "In alto a sinistra",
    ["On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."] = "Su un cerchio proprio, intorno o dentro l'anello, senza mai toccarlo. La prima prende il posto 1, la successiva il 2, e così via.",
    ["Separate circle"] = "Cerchio separato", ["Position"] = "Posizione", ["Ring shown"] = "Anello visibile", ["Layout of the other icons"] = "Disposizione delle altre icone",
    ["The suite"] = "La suite", ["Get the complete suite on CurseForge :"] = "Trova la suite completa su CurseForge :",
    ["Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."] = "Clicca sull'indirizzo, poi Ctrl+C (Cmd+C su Mac) per copiarlo.",
    ["AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."] = "AuraCore fa parte di Forever SagaCore, una suite di addon per WoW Forever : creazione e professioni (CraftCore), missioni e percorsi (QuestCore), mappa e servizi (MapCore), eredità (LegacyCore). Installati insieme, condividono una finestra, le stesse impostazioni e gli stessi comandi del controller.",
    ["in combat"] = "in combattimento", ["out of combat"] = "fuori combattimento", ["not read yet"] = "non ancora letto",
}

TRAD.ruRU = {
    ["beta"] = "бета",
    ["Food"] = "Еда", ["Flask or elixir"] = "Настой или эликсир", ["Debuff"] = "Отрицательный эффект", ["Buff"] = "Положительный эффект",
    ["Potion"] = "Зелье", ["In your bags : "] = "В сумках : ", ["Given by : "] = "Даёт : ",
    ["Active"] = "Активно", ["Missing"] = "Отсутствует", ["Active : "] = "Активно : ", ["State read before combat."] = "Состояние до начала боя.",
    ["Balanced"] = "Равномерно", ["In a row"] = "Подряд", ["Reserved places"] = "Закреплённые места",
    ["Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes."] = "Активные значки распределяются по всей свободной дуге. Два значка : друг напротив друга. Все сдвигаются, когда один появляется или исчезает.",
    ["Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active."] = "Активные значки идут друг за другом от начальной точки. Ничего не закреплено : дух показан, только если он активен.",
    ["What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place."] = "То, что вы накладываете на себя (дух, аура, доспех), имеет своё место, серое, если отсутствует. Срабатывания идут следом, каждое на своём месте.",
    ["Activate"] = "Включить", ["Layout"] = "Расположение", ["Top"] = "Сверху", ["Right"] = "Справа", ["Bottom"] = "Снизу", ["Left"] = "Слева",
    ["Clockwise"] = "По часовой", ["Counterclockwise"] = "Против часовой", ["Icon layout"] = "Расположение значков",
    ["How the icons outside the reserved quarters are placed : what you put on yourself and what procs."] = "Как располагаются значки вне закреплённых четвертей : то, что вы накладываете на себя, и срабатывания.",
    ["Starting point"] = "Начальная точка", ["Direction"] = "Направление", ["The ring"] = "Кольцо", ["Small"] = "Маленький", ["Medium"] = "Средний", ["Large"] = "Большой",
    ["Inside the icon"] = "Внутри значка", ["Outside the icon"] = "Снаружи значка", ["Hidden"] = "Скрыто",
    ["Decreasing"] = "Убывающий", ["Increasing"] = "Возрастающий", ["Top quarter"] = "Верхняя четверть", ["Right quarter"] = "Правая четверть",
    ["Bottom quarter"] = "Нижняя четверть", ["Left quarter"] = "Левая четверть", ["The ring around your character"] = "Кольцо вокруг персонажа",
    ["Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."] = "Шестнадцать постоянных мест по кругу вокруг персонажа. Цветом показано активное, серым отсутствующее. Наведите на значок, чтобы узнать, что это.",
    ["Show the ring"] = "Показывать кольцо", ["Icon size"] = "Размер значков", ["Height on screen"] = "Высота на экране", ["Minimum radius"] = "Минимальный радиус",
    ["Ring opacity"] = "Прозрачность кольца", ["Time left"] = "Оставшееся время", ["Duration circle"] = "Круг длительности", ["Food, flask and potion"] = "Еда, настой и зелье",
    ["Their place"] = "Их место", ["Buffs your group can give"] = "Эффекты от группы",
    ["/auracore off hides everything, /auracore on shows it again."] = "/auracore off скрывает всё, /auracore on показывает снова.",
    ["Debuffs"] = "Отрицательные эффекты", ["Inside the ring"] = "Внутри кольца", ["Outside the ring"] = "Снаружи кольца", ["Smaller"] = "Меньше",
    ["Same as the ring"] = "Как у кольца", ["Larger"] = "Больше", ["Top right"] = "Сверху справа", ["Bottom right"] = "Снизу справа",
    ["Bottom left"] = "Снизу слева", ["Top left"] = "Сверху слева",
    ["On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."] = "На отдельном круге, вокруг или внутри кольца, никогда его не касаясь. Первый занимает место 1, следующий место 2 и так далее.",
    ["Separate circle"] = "Отдельный круг", ["Position"] = "Положение", ["Ring shown"] = "Кольцо показано", ["Layout of the other icons"] = "Расположение остальных значков",
    ["The suite"] = "Набор", ["Get the complete suite on CurseForge :"] = "Полный набор на CurseForge :",
    ["Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."] = "Нажмите на адрес, затем Ctrl+C (Cmd+C на Mac), чтобы скопировать его.",
    ["AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."] = "AuraCore входит в Forever SagaCore, набор модификаций для WoW Forever : ремёсла и профессии (CraftCore), задания и маршруты (QuestCore), карта и услуги (MapCore), наследие (LegacyCore). Вместе они используют одно окно, общие настройки и одинаковое управление с геймпада.",
    ["in combat"] = "в бою", ["out of combat"] = "вне боя", ["not read yet"] = "ещё не прочитано",
}

TRAD.zhCN = {
    ["beta"] = "测试版",
    ["Food"] = "食物", ["Flask or elixir"] = "合剂或药剂", ["Debuff"] = "减益效果", ["Buff"] = "增益效果",
    ["Potion"] = "药水", ["In your bags : "] = "背包中 : ", ["Given by : "] = "来源 : ",
    ["Active"] = "生效中", ["Missing"] = "缺少", ["Active : "] = "生效中 : ", ["State read before combat."] = "战斗前读取的状态。",
    ["Balanced"] = "均匀分布", ["In a row"] = "依次排列", ["Reserved places"] = "固定位置",
    ["Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes."] = "生效的图标分布在整个空闲弧线上。两个图标 : 彼此相对。有图标出现或消失时全部移动。",
    ["Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active."] = "生效的图标从起点开始依次相邻排列。没有固定位置 : 守护只在生效时显示。",
    ["What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place."] = "你给自己施加的效果（守护、光环、护甲）有固定位置，缺少时显示为灰色。触发效果随后，各占其位。",
    ["Activate"] = "启用", ["Layout"] = "布局", ["Top"] = "上", ["Right"] = "右", ["Bottom"] = "下", ["Left"] = "左",
    ["Clockwise"] = "顺时针", ["Counterclockwise"] = "逆时针", ["Icon layout"] = "图标布局",
    ["How the icons outside the reserved quarters are placed : what you put on yourself and what procs."] = "固定四分区以外的图标如何排列 : 你给自己施加的效果和触发效果。",
    ["Starting point"] = "起点", ["Direction"] = "方向", ["The ring"] = "圆环", ["Small"] = "小", ["Medium"] = "中", ["Large"] = "大",
    ["Inside the icon"] = "图标内", ["Outside the icon"] = "图标外", ["Hidden"] = "隐藏",
    ["Decreasing"] = "递减", ["Increasing"] = "递增", ["Top quarter"] = "上四分区", ["Right quarter"] = "右四分区",
    ["Bottom quarter"] = "下四分区", ["Left quarter"] = "左四分区", ["The ring around your character"] = "角色周围的圆环",
    ["Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."] = "角色周围一圈十六个固定位置。彩色表示生效，灰色表示缺少。将鼠标移到图标上查看详情。",
    ["Show the ring"] = "显示圆环", ["Icon size"] = "图标大小", ["Height on screen"] = "屏幕高度", ["Minimum radius"] = "最小半径",
    ["Ring opacity"] = "圆环透明度", ["Time left"] = "剩余时间", ["Duration circle"] = "持续时间圈", ["Food, flask and potion"] = "食物、合剂和药水",
    ["Their place"] = "位置", ["Buffs your group can give"] = "队伍可提供的增益",
    ["/auracore off hides everything, /auracore on shows it again."] = "/auracore off 隐藏全部，/auracore on 重新显示。",
    ["Debuffs"] = "减益效果", ["Inside the ring"] = "圆环内", ["Outside the ring"] = "圆环外", ["Smaller"] = "较小",
    ["Same as the ring"] = "与圆环相同", ["Larger"] = "较大", ["Top right"] = "右上", ["Bottom right"] = "右下",
    ["Bottom left"] = "左下", ["Top left"] = "左上",
    ["On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."] = "位于单独的圆圈上，在圆环外侧或内侧，绝不相碰。第一个占据位置 1，下一个位置 2，依此类推。",
    ["Separate circle"] = "单独圆圈", ["Position"] = "位置", ["Ring shown"] = "显示圆环", ["Layout of the other icons"] = "其他图标的布局",
    ["The suite"] = "整套插件", ["Get the complete suite on CurseForge :"] = "在 CurseForge 获取完整套件 :",
    ["Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."] = "点击地址，然后按 Ctrl+C（Mac 上为 Cmd+C）复制。",
    ["AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."] = "AuraCore 是 Forever SagaCore 的一部分，这是一套 WoW Forever 插件 : 制造与专业（CraftCore）、任务与路线（QuestCore）、地图与服务（MapCore）、传承（LegacyCore）。一起安装时，它们共用一个窗口、相同的设置和相同的手柄操作。",
    ["in combat"] = "战斗中", ["out of combat"] = "非战斗", ["not read yet"] = "尚未读取",
}
