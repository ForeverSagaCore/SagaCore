local _, NS = ...
NS.LANGUES = NS.LANGUES or {}
local L = {}
NS.LANGUES.itIT = L

L.LOADED = "LegacyCore %s caricato. /lc apre la finestra."
L.CLOSE = "Chiudi"
L.NAV_TREES = "I miei alberi"
L.NAV_CHALLENGES = "Sfide"
L.NAV_CHARACTERS = "Personaggi"
L.NAV_ADVICE = "Consigli"
L.TREE_PROFESSIONS = "Professioni"
L.TREE_ADVENTURE = "Avventura"
L.TREE_RESOURCES = "Ingegno"
L.TREE_SPENT = "  (%d punti)"
L.TIER = "Fila %d"
L.LEVEL = "Livello %d"
L.LOCKED_LEVEL = "L'Eredità si sblocca al livello %d (questo personaggio: %d)."
L.NO_DATA_HERE = "Ancora niente letto per questo personaggio: apri una volta la finestra Eredità, poi /reload."
L.NO_DATA_OTHER = "Non ancora letto: accedi una volta con questo personaggio con LegacyCore attivo."
L.POINTS_SPENT = "Punti spesi: %d / %d"
L.POINTS_FREE = "%d da spendere"
L.READ_ON = "Letto il %s"
L.DONE_MARK = "Fatto"
L.TODO_MARK = "Da fare"
L.CHALLENGES_NOTE = "Calcolato dai tuoi personaggi conosciuti (QuestCore, CraftCore, LegacyCore). Il riferimento è la finestra Eredità del gioco."
L.CHALLENGES_CLASSES = "Classi: livelli 25, 45 e 60"
L.CHALLENGES_TRADES = "Professioni di creazione: 150, 225 e 300"
L.BEST_CHAR = "Il più vicino: %s, livello %d"
L.BEST_TRADE = "Il più vicino: %s, abilità %d"
L.NO_TRADE = "CraftCore non conosce nessun personaggio con questa professione."
L.PAD_PAGES = "Pagine"
L.PAD_CHARS = "Personaggi"
L.PAD_SCROLL = "Scorri"
L.PROF_164 = "Forgiatura"
L.PROF_165 = "Conciatura"
L.PROF_171 = "Alchimia"
L.PROF_197 = "Sartoria"
L.PROF_202 = "Ingegneria"
L.PROF_333 = "Incantamento"
L.ADVICE_NOTE = "Scelte più comuni nelle guide della community (lancio di WoW Forever). I nomi dei talenti sono tradotti; quelli del gioco sono nella pagina I miei alberi."
L.PAD_SUITE = "Add-on"
L.CHALLENGE_CLICK_ROUTE = "Clic: percorso fino al livello successivo (QuestCore)"
L.CHALLENGE_LOG_ON = "(accedi con %s per un percorso)"
L.CHALLENGE_ROUTE_NONE = "Nessuna missione trovata per un percorso di livellamento."
L.NAV_TIMELINE = "Cronologia"
L.TREES_TITLE = "I miei alberi"
L.RANK_OF = "Grado %d / %d"
L.NO_CLASS = "Nessun personaggio di questa classe."
L.PLAYED_TOTAL = "Giocato: %s"
L.LEVEL_TIME = "Tempo impiegato: %s"
L.LEVEL_TIME_NOW = "In corso: %s"
L.LEVEL_TIME_UNKNOWN = "Raggiunto prima dell'installazione di LegacyCore: tempo sconosciuto."
L.LEVEL_TIME_LATER = "Non ancora raggiunto."
L.TIMELINE_LEVELS = "Tempo per livello: %s"
L.LONGEST_LEVEL = "Il più lungo: livello %d (%s)"
L.AVERAGE_LEVEL = "Media: %s per livello"
L.TIMELINE_NO_TIME = "Nessun tempo ancora registrato per questo personaggio: accedi una volta con lui."
L.TIMELINE_NOTE = "Ogni colonna è un livello, la sua altezza il tempo impiegato. Verde: livelli completati; blu: il livello attuale; grigio: livelli raggiunti prima dell'installazione (tempo sconosciuto)."
L.TIMELINE_ACCOUNT = "Cronologia dell'account"
L.TIMELINE_EMPTY = "Ancora niente: ogni livello guadagnato dai tuoi personaggi comparirà qui."
L.LEVELS_TWO = "Livelli %d e %d"
L.LEVELS_RANGE = "Livelli %d a %d"
L.TIMELINE_LEVEL_UP = "ha raggiunto il livello %d"
L.TIMELINE_TOOK = "%s al livello %d"
L.DUR_DAYS = "%d g %d h"
L.DUR_HOURS = "%d h %02d"
L.DUR_MINUTES = "%d min"
L.CHAR_LEVEL_OF = "%s livello %s"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "Apri l'Eredità per spendere punti"
L.OPEN_LEGACY_FAIL = "Impossibile aprire la finestra Eredità: usa il suo tasto (Y di default)."
L.OPEN_LEGACY_KEY = "Il gioco lascia aprire l'Eredità solo alla propria interfaccia: premi %s."
L.UNLOCKED_LEVEL = "Eredità sbloccata (livello %d)"
L.OPEN_LEGACY_OTHER = "Accedi con %s per spendere i suoi punti."
L.ADVICE = {
    { "Livellamento (Avventura)",
        { "Ben riposato 5/5", "L'esperienza di riposo si accumula più in fretta e ne contiene di più. Necessario per Talentuoso." },
        { "Talentuoso 5/5", "I punti talento iniziano al livello 5 invece che al 10: cinque punti in più durante il livellamento. Inutile a 60." },
        { "Brivido dell'avventura", "Un po' di salute e mana a ogni uccisione, solo all'aperto. Completa i punti rimanenti." } },
    { "Alt che volano molto",
        { "Guida da campo 3/3, poi Viaggiatore frequente", "Rotte di volo a metà prezzo e una cavalcatura volante più veloce, al posto di Brivido dell'avventura." } },
    { "Professioni e oro (a 60)",
        { "Straordinari 5/5", "Più probabilità di aumentare l'abilità in ogni professione." },
        { "Raccolto abbondante 5/5", "Più materiali rari da estrazione, erbalismo e scuoiatura." },
        { "Contrattazione, Studio dedicato", "Oggetti dei mercanti più economici e un punto in più nella professione più bassa." } },
    { "Spedizioni, incursioni, PvP (a 60)",
        { "Buongustaio, Permanenza", "I benefici del cibo e quelli lunghi di gruppo durano di più." },
        { "Rinforzo", "Meno durabilità persa alla morte." },
        { "Per il grande onore o Diplomatico", "Più onore o più reputazione." } },
    { "Promemoria",
        { "Riassegna dal tuo istruttore di classe", "I punti sono dell'account ma si spendono per personaggio: azzera a 60 per passare dal livellamento alla build di fine gioco." } },
}
