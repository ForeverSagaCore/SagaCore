local _, NS = ...
NS.LANGUES = NS.LANGUES or {}
local L = {}
NS.LANGUES.esES = L

L.LOADED = "LegacyCore %s cargado. /lc abre la ventana."
L.CLOSE = "Cerrar"
L.NAV_TREES = "Mis árboles"
L.NAV_CHALLENGES = "Desafíos"
L.NAV_CHARACTERS = "Personajes"
L.NAV_ADVICE = "Consejos"
L.TREE_PROFESSIONS = "Profesiones"
L.TREE_ADVENTURE = "Aventura"
L.TREE_RESOURCES = "Ingenio"
L.TREE_SPENT = "  (%d puntos)"
L.TIER = "Fila %d"
L.LEVEL = "Nivel %d"
L.LOCKED_LEVEL = "El Legado se desbloquea en el nivel %d (este personaje: %d)."
L.NO_DATA_HERE = "Aún no se ha leído nada de este personaje: abre una vez tu ventana de Legado y luego /reload."
L.NO_DATA_OTHER = "Aún no leído: conéctate una vez con este personaje con LegacyCore activado."
L.POINTS_SPENT = "Puntos gastados: %d / %d"
L.POINTS_FREE = "%d por gastar"
L.READ_ON = "Leído el %s"
L.DONE_MARK = "Hecho"
L.TODO_MARK = "Pendiente"
L.CHALLENGES_NOTE = "Calculado a partir de tus personajes conocidos (QuestCore, CraftCore, LegacyCore). La referencia es la ventana de Legado del juego."
L.CHALLENGES_CLASSES = "Clases: niveles 25, 45 y 60"
L.CHALLENGES_TRADES = "Profesiones de fabricación: 150, 225 y 300"
L.BEST_CHAR = "El más cercano: %s, nivel %d"
L.BEST_TRADE = "El más cercano: %s, habilidad %d"
L.NO_TRADE = "CraftCore no conoce ningún personaje con esta profesión."
L.PAD_PAGES = "Páginas"
L.PAD_CHARS = "Personajes"
L.PAD_SCROLL = "Desplazar"
L.PROF_164 = "Herrería"
L.PROF_165 = "Peletería"
L.PROF_171 = "Alquimia"
L.PROF_197 = "Sastrería"
L.PROF_202 = "Ingeniería"
L.PROF_333 = "Encantamiento"
L.ADVICE_NOTE = "Elecciones más habituales en las guías de la comunidad (lanzamiento de WoW Forever). Los nombres de talentos están traducidos; los del juego están en la página Mis árboles."
L.PAD_SUITE = "Accesorios"
L.CHALLENGE_CLICK_ROUTE = "Clic: ruta hasta el siguiente nivel (QuestCore)"
L.CHALLENGE_LOG_ON = "(conéctate con %s para una ruta)"
L.CHALLENGE_ROUTE_NONE = "No se encontró ninguna misión para una ruta de subida."
L.NAV_TIMELINE = "Cronología"
L.TREES_TITLE = "Mis árboles"
L.RANK_OF = "Rango %d / %d"
L.NO_CLASS = "Ningún personaje de esta clase."
L.PLAYED_TOTAL = "Jugado: %s"
L.LEVEL_TIME = "Tiempo dedicado: %s"
L.LEVEL_TIME_NOW = "En curso: %s"
L.LEVEL_TIME_UNKNOWN = "Alcanzado antes de instalar LegacyCore: tiempo desconocido."
L.LEVEL_TIME_LATER = "Aún no alcanzado."
L.TIMELINE_LEVELS = "Tiempo por nivel: %s"
L.LONGEST_LEVEL = "El más largo: nivel %d (%s)"
L.AVERAGE_LEVEL = "Media: %s por nivel"
L.TIMELINE_NO_TIME = "Aún no hay tiempo registrado para este personaje: conéctate una vez con él."
L.TIMELINE_NOTE = "Cada columna es un nivel, su altura el tiempo dedicado. Verde: el nivel actual; gris: niveles alcanzados antes de la instalación (tiempo desconocido)."
L.TIMELINE_ACCOUNT = "Cronología de la cuenta"
L.TIMELINE_EMPTY = "Nada todavía: cada nivel que ganen tus personajes aparecerá aquí."
L.TIMELINE_LEVEL_UP = "alcanzó el nivel %d"
L.TIMELINE_TOOK = "%s en el nivel %d"
L.DUR_DAYS = "%d d %d h"
L.DUR_HOURS = "%d h %02d"
L.DUR_MINUTES = "%d min"
L.CHAR_LEVEL_OF = "%s nivel %s"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "Abrir el Legado para gastar puntos"
L.OPEN_LEGACY_FAIL = "No se pudo abrir la ventana de Legado: usa su tecla (Y por defecto)."
L.OPEN_LEGACY_KEY = "El juego solo permite abrir el Legado desde su propia interfaz: pulsa %s."
L.UNLOCKED_LEVEL = "Legado desbloqueado (nivel %d)"
L.OPEN_LEGACY_OTHER = "Conéctate con %s para gastar sus puntos."
L.ADVICE = {
    { "Subir de nivel (Aventura)",
        { "Bien descansado 5/5", "La experiencia por descanso se acumula más rápido y guarda más. Necesario para Talentoso." },
        { "Talentoso 5/5", "Los puntos de talento empiezan en el nivel 5 en vez del 10: cinco puntos más mientras subes. Inútil a 60." },
        { "Emoción de la aventura", "Algo de salud y maná en cada muerte, solo al aire libre. Completa los puntos restantes." } },
    { "Alters que vuelan mucho",
        { "Guía de campo 3/3, luego Viajero frecuente", "Rutas de vuelo a mitad de precio y una montura voladora más rápida, en lugar de Emoción de la aventura." } },
    { "Profesiones y oro (a 60)",
        { "Horas extra 5/5", "Más probabilidad de subir la habilidad en todas las profesiones." },
        { "Cosecha abundante 5/5", "Más materiales raros en minería, herboristería y desuello." },
        { "Regateo, Estudio dedicado", "Objetos de vendedor más baratos y un punto más en tu profesión más baja." } },
    { "Mazmorras, bandas, JcJ (a 60)",
        { "Gourmet, Permanencia", "Los beneficios de comida y los beneficios de grupo largos duran más." },
        { "Reforzar", "Menos durabilidad perdida al morir." },
        { "Por un gran honor o Diplomático", "Más honor o más reputación." } },
    { "Recordatorio",
        { "Reinicia con tu instructor de clase", "Los puntos son de la cuenta pero se gastan por personaje: reinicia a 60 para pasar de la subida a tu configuración final." } },
}
