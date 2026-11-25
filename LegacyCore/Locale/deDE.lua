local _, NS = ...
NS.LANGUES = NS.LANGUES or {}
local L = {}
NS.LANGUES.deDE = L

L.LOADED = "LegacyCore %s geladen. /lc öffnet das Fenster."
L.CLOSE = "Schließen"
L.NAV_TREES = "Meine Bäume"
L.NAV_CHALLENGES = "Herausforderungen"
L.NAV_CHARACTERS = "Charaktere"
L.NAV_ADVICE = "Tipps"
L.TREE_PROFESSIONS = "Berufe"
L.TREE_ADVENTURE = "Abenteuer"
L.TREE_RESOURCES = "Einfallsreichtum"
L.TREE_SPENT = "  (%d Punkte)"
L.TIER = "Reihe %d"
L.LEVEL = "Stufe %d"
L.LOCKED_LEVEL = "Das Vermächtnis wird auf Stufe %d freigeschaltet (dieser Charakter: %d)."
L.NO_DATA_HERE = "Für diesen Charakter noch nichts gelesen: öffne einmal dein Vermächtnis-Fenster, dann /reload."
L.NO_DATA_OTHER = "Noch nicht gelesen: melde dich einmal mit diesem Charakter und aktiviertem LegacyCore an."
L.POINTS_SPENT = "Ausgegebene Punkte: %d / %d"
L.POINTS_FREE = "%d zu vergeben"
L.READ_ON = "Gelesen am %s"
L.DONE_MARK = "Erledigt"
L.TODO_MARK = "Offen"
L.CHALLENGES_NOTE = "Berechnet aus deinen bekannten Charakteren (QuestCore, CraftCore, LegacyCore). Maßgeblich ist das Vermächtnis-Fenster des Spiels."
L.CHALLENGES_CLASSES = "Klassen: Stufe 25, 45 und 60"
L.CHALLENGES_TRADES = "Herstellungsberufe: 150, 225 und 300"
L.BEST_CHAR = "Am nächsten: %s, Stufe %d"
L.BEST_TRADE = "Am nächsten: %s, Fertigkeit %d"
L.NO_TRADE = "Kein Charakter mit diesem Beruf ist CraftCore bekannt."
L.PAD_PAGES = "Seiten"
L.PAD_CHARS = "Charaktere"
L.PAD_SCROLL = "Blättern"
L.PROF_164 = "Schmiedekunst"
L.PROF_165 = "Lederverarbeitung"
L.PROF_171 = "Alchemie"
L.PROF_197 = "Schneiderei"
L.PROF_202 = "Ingenieurskunst"
L.PROF_333 = "Verzauberkunst"
L.ADVICE_NOTE = "Häufigste Wahl in Community-Guides (Start von WoW Forever). Talentnamen sind übersetzt; die Namen des Spiels stehen auf der Seite Meine Bäume."
L.PAD_SUITE = "Add-ons"
L.CHALLENGE_CLICK_ROUTE = "Klick: Route zur nächsten Stufe (QuestCore)"
L.CHALLENGE_LOG_ON = "(melde dich mit %s an für eine Route)"
L.CHALLENGE_ROUTE_NONE = "Keine Quest für eine Levelroute gefunden."
L.NAV_TIMELINE = "Chronik"
L.TREES_TITLE = "Meine Bäume"
L.RANK_OF = "Rang %d / %d"
L.NO_CLASS = "Kein Charakter dieser Klasse."
L.PLAYED_TOTAL = "Gespielt: %s"
L.LEVEL_TIME = "Verbrachte Zeit: %s"
L.LEVEL_TIME_NOW = "Laufend: %s"
L.LEVEL_TIME_UNKNOWN = "Vor der Installation von LegacyCore erreicht: Zeit unbekannt."
L.LEVEL_TIME_LATER = "Noch nicht erreicht."
L.TIMELINE_LEVELS = "Zeit pro Stufe: %s"
L.LONGEST_LEVEL = "Am längsten: Stufe %d (%s)"
L.AVERAGE_LEVEL = "Durchschnitt: %s pro Stufe"
L.TIMELINE_NO_TIME = "Für diesen Charakter noch keine Zeit erfasst: melde dich einmal mit ihm an."
L.TIMELINE_NOTE = "Jede Säule ist eine Stufe, ihre Höhe die darauf verbrachte Zeit. Grün: abgeschlossene Stufen; blau: die aktuelle Stufe; grau: vor der Installation erreichte Stufen (Zeit unbekannt)."
L.TIMELINE_ACCOUNT = "Chronik des Accounts"
L.TIMELINE_EMPTY = "Noch nichts: jede Stufe, die deine Charaktere erreichen, erscheint hier."
L.LEVELS_TWO = "Stufen %d und %d"
L.LEVELS_RANGE = "Stufen %d bis %d"
L.TIMELINE_LEVEL_UP = "erreicht Stufe %d"
L.TIMELINE_TOOK = "%s auf Stufe %d"
L.DUR_DAYS = "%d T %d Std"
L.DUR_HOURS = "%d Std %02d"
L.DUR_MINUTES = "%d Min"
L.CHAR_LEVEL_OF = "%s Stufe %s"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "Vermächtnis öffnen, um Punkte zu vergeben"
L.OPEN_LEGACY_FAIL = "Das Vermächtnis-Fenster ließ sich nicht öffnen: nutze seine Taste (standardmäßig Y)."
L.OPEN_LEGACY_KEY = "Das Spiel lässt nur seine eigene Oberfläche das Vermächtnis öffnen: drücken Sie %s."
L.UNLOCKED_LEVEL = "Vermächtnis freigeschaltet (Stufe %d)"
L.OPEN_LEGACY_OTHER = "Melde dich mit %s an, um seine Punkte zu vergeben."
L.ADVICE = {
    { "Leveln (Abenteuer)",
        { "Gut ausgeruht 5/5", "Erholungserfahrung baut sich schneller auf und hält mehr. Nötig für Talentiert." },
        { "Talentiert 5/5", "Talentpunkte ab Stufe 5 statt 10: fünf Talentpunkte mehr beim Leveln. Auf 60 nutzlos." },
        { "Abenteuerlust", "Etwas Gesundheit und Mana bei jedem Kill, nur im Freien. Füllt die restlichen Punkte." } },
    { "Twinks, die viel fliegen",
        { "Feldhandbuch 3/3, dann Vielflieger", "Flugrouten zum halben Preis und ein schnelleres Flugreittier, statt Abenteuerlust." } },
    { "Berufe und Gold (auf 60)",
        { "Überstunden 5/5", "Höhere Chance auf Fertigkeitsanstieg in jedem Beruf." },
        { "Reiche Ernte 5/5", "Mehr seltene Materialien bei Bergbau, Kräuterkunde und Kürschnerei." },
        { "Feilschen, Fleißiges Lernen", "Günstigere Händlerwaren und ein Punkt mehr im niedrigsten Beruf." } },
    { "Dungeons, Schlachtzüge, PvP (auf 60)",
        { "Feinschmecker, Beständigkeit", "Essens-Buffs und lange Gruppen-Buffs halten länger." },
        { "Verstärken", "Weniger Haltbarkeitsverlust beim Tod." },
        { "Für große Ehre oder Diplomat", "Mehr Ehre oder mehr Ruf." } },
    { "Erinnerung",
        { "Beim Klassenlehrer neu verteilen", "Punkte gehören dem Account, werden aber pro Charakter vergeben: auf 60 zurücksetzen, um vom Leveln zum Endgame-Build zu wechseln." } },
}
