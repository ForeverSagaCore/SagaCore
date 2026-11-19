local _, NS = ...
if GetLocale and GetLocale() ~= "frFR" then return end
local L = NS.L
L.TITLE = "LegacyCore"
L.LOADED = "LegacyCore %s chargé. /lc ouvre la fenêtre."
L.CLOSE = "Fermer"
L.NAV_TREES = "Mes arbres"
L.NAV_CHALLENGES = "Défis"
L.NAV_CHARACTERS = "Personnages"
L.NAV_ADVICE = "Conseils"
L.TREE_PROFESSIONS = "Métiers"
L.TREE_ADVENTURE = "Aventure"
L.TREE_RESOURCES = "Ingéniosité"
L.TREE_SPENT = "  (%d points)"
L.TIER = "Rangée %d"
L.LEVEL = "Niveau %d"
L.LOCKED_LEVEL = "L'héritage se débloque au niveau %d (ce personnage : %d)."
L.NO_DATA_HERE = "Rien de relevé pour ce personnage : ouvrez une fois votre fenêtre Héritage, puis /reload."
L.NO_DATA_OTHER = "Pas encore relevé : connectez-vous une fois sur ce personnage avec LegacyCore activé."
L.POINTS_SPENT = "Points dépensés : %d / %d"
L.POINTS_FREE = "%d à dépenser"
L.READ_ON = "Relevé le %s"
L.DONE_MARK = "Fait"
L.TODO_MARK = "À faire"
L.CHALLENGES_NOTE = "Calculé d'après vos personnages connus (QuestCore, CraftCore, LegacyCore). La fenêtre Héritage du jeu fait foi."
L.CHALLENGES_CLASSES = "Classes : niveaux 25, 45 et 60"
L.CHALLENGES_TRADES = "Métiers de fabrication : 150, 225 et 300"
L.BEST_CHAR = "Le plus proche : %s, niveau %d"
L.BEST_TRADE = "Le plus proche : %s, compétence %d"
L.NO_TRADE = "Aucun personnage connu de CraftCore avec ce métier."
L.PAD_PAGES = "Pages"
L.PAD_CHARS = "Personnages"
L.PAD_SCROLL = "Défiler"
L.PROF_164 = "Forge"
L.PROF_165 = "Travail du cuir"
L.PROF_171 = "Alchimie"
L.PROF_197 = "Couture"
L.PROF_202 = "Ingénierie"
L.PROF_333 = "Enchantement"
L.ADVICE_NOTE = "Les choix les plus répandus dans les guides de la communauté (lancement de WoW Forever). Noms des talents traduits par nos soins ; les vrais noms du jeu sont dans Mes arbres."
L.ADVICE = {
    { "Monter de niveau (Aventure)",
        { "Bien reposé 5/5", "L'XP de repos s'accumule plus vite et plus haut. Ouvre l'accès à Talentueux." },
        { "Talentueux 5/5", "Points de talent dès le niveau 5 au lieu de 10 : cinq points de talent de plus pendant la montée. Inutile au 60." },
        { "Frisson de l'aventure", "Un peu de vie et de mana à chaque ennemi tué, en extérieur seulement. Pour les points restants." } },
    { "Rerolls qui volent souvent",
        { "Guide de terrain 3/3, puis Grand voyageur", "Vols à moitié prix et monture de vol plus rapide, à la place de Frisson de l'aventure." } },
    { "Métiers et or (au 60)",
        { "Heures supplémentaires 5/5", "Plus de chances de gagner un point dans tous les métiers." },
        { "Récolte abondante 5/5", "Plus de matériaux rares en minage, herboristerie et dépeçage." },
        { "Marchandage, Étude assidue", "Achats chez les marchands moins chers, et un point de plus dans votre métier le plus bas." } },
    { "Donjons, raids, JcJ (au 60)",
        { "Gourmet, Permanence", "Nourriture et longs buffs de groupe qui durent plus longtemps." },
        { "Renfort", "Moins d'usure de l'équipement à la mort." },
        { "Pour l'honneur ou Diplomate", "Plus d'honneur, ou plus de réputation." } },
    { "À savoir",
        { "Réinitialisation chez le maître de classe", "Les points sont communs au compte mais dépensés par personnage : au 60, réinitialisez pour passer de la montée à votre arbre de fin de jeu." } },
}
L.PAD_SUITE = "Add-ons"
L.CHALLENGE_CLICK_ROUTE = "Clic : parcours vers le niveau suivant (QuestCore)"
L.CHALLENGE_LOG_ON = "(connectez-vous sur %s pour un parcours)"
L.CHALLENGE_ROUTE_NONE = "Aucune quête trouvée pour un parcours de progression."
L.NAV_TIMELINE = "Chronologie"
L.TREES_TITLE = "Mes arbres"
L.RANK_OF = "Rang %d / %d"
L.NO_CLASS = "Aucun personnage de cette classe."
L.PLAYED_TOTAL = "Temps de jeu : %s"
L.LEVEL_TIME = "Temps passé : %s"
L.LEVEL_TIME_NOW = "En cours : %s"
L.LEVEL_TIME_UNKNOWN = "Atteint avant l'installation de LegacyCore : temps inconnu."
L.LEVEL_TIME_LATER = "Pas encore atteint."
L.TIMELINE_LEVELS = "Temps par niveau : %s"
L.LONGEST_LEVEL = "Le plus long : niveau %d (%s)"
L.AVERAGE_LEVEL = "Moyenne : %s par niveau"
L.TIMELINE_NO_TIME = "Pas encore de temps relevé pour ce personnage : connectez-vous une fois dessus."
L.TIMELINE_NOTE = "Chaque colonne est un niveau, sa hauteur le temps passé dessus. En vert, le niveau en cours ; en gris, les niveaux atteints avant l'installation (temps inconnu)."
L.TIMELINE_ACCOUNT = "Chronologie du compte"
L.TIMELINE_EMPTY = "Rien encore : chaque niveau gagné par vos personnages viendra s'inscrire ici."
L.TIMELINE_LEVEL_UP = "atteint le niveau %d"
L.TIMELINE_TOOK = "%s au niveau %d"
L.DUR_DAYS = "%d j %d h"
L.DUR_HOURS = "%d h %02d"
L.DUR_MINUTES = "%d min"
L.CHAR_LEVEL_OF = "%s niveau %s"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "Ouvrir l'héritage pour dépenser les points"
L.OPEN_LEGACY_FAIL = "Impossible d'ouvrir la fenêtre d'héritage : utilisez son raccourci (Y par défaut)."
