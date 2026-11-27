-- Aide de chaque add-on de la suite, montree par le bouton Aide du pied
-- (onglet Aide de la fenetre d'informations). Fichier commun, copie a
-- l'identique dans chaque add-on qui porte Suite.lua : la copie la plus
-- recente l'emporte.
--
-- Par add-on : intro, pages (l'aide de la page ouverte, par sa cle) et
-- sections (titre et lignes). Chaque texte : { francais, anglais }.

local VERSION = 1
if type(_G.CoreSuiteAidesVersion) == "number" and _G.CoreSuiteAidesVersion >= VERSION then return end
_G.CoreSuiteAidesVersion = VERSION

_G.CoreSuiteAides = {
    Suite = {
        lignes = {
            { "La colonne de gauche passe d'un add-on à l'autre ; le bouton du bas ouvre les compléments.",
              "The left column switches between add-ons ; the bottom button opens the companions." },
            { "La bande du haut choisit le personnage montré : le vôtre est toujours le premier.",
              "The top band picks the character shown : yours always comes first." },
            { "Un seul guidage pour toute la suite : la flèche dit où aller, « Arrêter » le coupe à tout moment.",
              "One guidance for the whole suite : the arrow tells where to go, « Stop » ends it at any time." },
            { "Réglages : langue, messages dans la discussion, fond, parchemin et panneau, communs à toute la suite.",
              "Settings : language, chat messages, background, parchment and panel, shared by the whole suite." },
            { "Dernière mise à jour : ce qui a changé, version par version, depuis la première.",
              "Latest update : what changed, version by version, since the first one." },
        },
    },
    CraftCore = {
        intro = { "Vos métiers de bout en bout : ce que vous savez fabriquer, ce qu'il vous manque, où le trouver, et le guidage jusqu'au rang visé.",
                  "Your professions from start to finish : what you can craft, what you lack, where to find it, and guidance to the rank you aim for." },
        sections = {
            { titre = { "Les pages", "The pages" }, lignes = {
                { "**Mes fabrications** : vos projets, ce qu'il manque pour chacun, et les étapes dans l'ordre (récupérer, acheter, récolter, fabriquer).",
                  "**My crafts** : your projects, what each one lacks, and the steps in order (retrieve, buy, gather, craft)." },
                { "**Monter un métier** : choisissez le rang visé, le plan se fige et chaque étape a son bouton.",
                  "**Level a profession** : pick the target rank, the plan is locked and each step has its button." },
                { "**Mes recettes** : triées par chance de faire monter le métier, avec ce qui manque et le prix de l'hôtel des ventes au survol.",
                  "**My recipes** : sorted by the chance to raise the profession, with what is missing and the auction price on hover." },
                { "**Caisses** : le commerce des caisses du camp, ses lots, ses patrons et ses récompenses.",
                  "**Crates** : the faction crate trade, its lots, its patterns and its rewards." },
                { "**Stocks** : ce que possèdent tous vos personnages, sacs, banque et courrier compris.",
                  "**Stocks** : what all your characters own, bags, bank and mail included." },
            } },
            { titre = { "Astuces", "Tips" }, lignes = {
                { "Le bouton Aide montre l'aide de la page ouverte ; le didacticiel se lance depuis elle.",
                  "The Help button shows the help of the open page ; the tutorial starts from there." },
                { "Au courrier, à la banque et à l'hôtel des ventes, le panneau de CraftCore s'ouvre à côté de la fenêtre du jeu.",
                  "At the mailbox, bank and auction house, the CraftCore panel opens next to the game window." },
            } },
        },
    },
    StuffCore = {
        intro = { "Votre équipement : ce qui l'améliore et d'où ça vient (fabrications, butins du monde, quêtes, donjons).",
                  "Your gear : what improves it and where it comes from (crafts, world drops, quests, dungeons)." },
        sections = {
            { titre = { "Les pages", "The pages" }, lignes = {
                { "**Mon équipement** : chaque emplacement, la pièce portée et les améliorations possibles, de la meilleure à la moins bonne.",
                  "**My gear** : each slot, the worn piece and the possible upgrades, best first." },
                { "**Origines** : fabrications, butins du monde, quêtes, donjons et raids, rangés par instance.",
                  "**Sources** : crafts, world drops, quests, dungeons and raids, sorted by instance." },
            } },
        },
    },
    QuestCore = {
        intro = { "Vos quêtes et vos trajets : ce qu'il y a à prendre, à faire et à rendre, et un itinéraire qui choisit pour vous le meilleur ordre.",
                  "Your quests and routes : what to pick up, do and turn in, and a route that picks the best order for you." },
        sections = {
            { titre = { "Les pages", "The pages" }, lignes = {
                { "**Mon histoire** : votre progression et les quêtes de vos zones.",
                  "**My story** : your progress and the quests of your zones." },
                { "**Quêtes disponibles** : l'XP à prendre par zone à votre niveau, et la suite complète d'une quête quand elle en fait partie.",
                  "**Available quests** : the XP to take per zone at your level, and the whole chain of a quest when it has one." },
                { "**Donjons** : les quêtes de chaque donjon, ses boss et son plan.",
                  "**Dungeons** : the quests of each dungeon, its bosses and its map." },
                { "**Itinéraires** : un parcours de zone ou vers un niveau ; « Me guider » le lance aussitôt.",
                  "**Routes** : a zone route or a route to a level ; « Guide me » starts it at once." },
            } },
            { titre = { "Le guidage d'un itinéraire", "Guiding a route" }, lignes = {
                { "La cible est choisie par rentabilité : visites regroupées, rendus qui ouvrent des suites, place dans les sacs et le journal, montée de niveau.",
                  "The target is picked by value : grouped visits, turn-ins that open chains, room in bags and log, levelling up." },
                { "En tête du suivi : Maintenant, puis Ensuite. Les quêtes à rendre passent sous celles à faire ; celles d'un autre continent sont mises de côté en bas.",
                  "At the top of the tracker : Now, then Next. Quests to turn in sit below those to do ; those on another continent are set aside at the bottom." },
                { "Sacs presque pleins : la suite propose d'aller rendre un groupe de quêtes, puis reprend la route.",
                  "Bags almost full : the suite offers to turn in a group of quests, then resumes the route." },
                { "Un clic sur la petite carte d'une quête à rendre l'ajoute en détour ; recliquer le retire.",
                  "A click on the small map of a quest to turn in adds it as a detour ; click again to remove it." },
            } },
        },
    },
    MapCore = {
        intro = { "Les cartes et les services : maîtres de classe et de métier, réparation, boîtes aux lettres, auberges, banques, maîtres de vol, vos repères et vos personnages.",
                  "Maps and services : class and profession trainers, repair, mailboxes, inns, banks, flight masters, your markers and your characters." },
        sections = {
            { titre = { "Utiliser la carte", "Using the map" }, lignes = {
                { "Les filtres sous la carte choisissent les services montrés ; les continents sont en onglets.",
                  "The filters under the map pick the services shown ; continents are tabs." },
                { "Un clic sur un service y guide ; la destination brille puis clignote.",
                  "A click on a service guides you there ; the destination glows, then blinks." },
                { "Dans un donjon, la carte montre son plan : salles, boss, entrée, étages.",
                  "In a dungeon, the map shows its layout : rooms, bosses, entrance, floors." },
            } },
        },
    },
    LegacyCore = {
        intro = { "L'héritage du compte : ses arbres, ses défis, et le temps passé sur chaque niveau.",
                  "The account legacy : its trees, its challenges, and the time spent on each level." },
        sections = {
            { titre = { "Les pages", "The pages" }, lignes = {
                { "**Arbres** : les points à dépenser et ce que chaque nœud apporte, comme dans le jeu.",
                  "**Trees** : the points to spend and what each node gives, as in the game." },
                { "**Défis** : les défis du compte, faits ou à faire.",
                  "**Challenges** : the account challenges, done or to do." },
                { "**Niveaux** : le temps passé sur chaque niveau, par personnage.",
                  "**Levels** : the time spent on each level, per character." },
            } },
        },
    },
    GloryCore = {
        intro = { "Finir le jeu : des points pour chaque haut fait, des objectifs à votre rythme réel, et votre avancement en pourcentage pour chaque personnage, la Horde, l'Alliance et les deux.",
                  "Finish the game : points for every feat, goals at your real pace, and your progress in percent for each character, the Horde, the Alliance and both." },
        pages = {
            compte = { "Vos points et vos derniers hauts faits, tous personnages confondus, puis chaque catégorie avec son anneau d'avancement.",
                       "Your points and latest feats, all characters together, then each category with its progress ring." },
            perso = { "Le personnage choisi dans la bande du haut : ses points, ses derniers hauts faits et ses catégories.",
                      "The character picked in the top band : their points, latest feats and categories." },
            objectifs = { "Le niveau visé avec l'estimation tirée de votre vrai rythme d'XP, puis vos objectifs et vos parcours, chacun avec son bouton pour être guidé.",
                          "The target level with an estimate from your real XP pace, then your goals and routes, each with its button to be guided." },
            reglages = { "L'annonce d'un haut fait (bandeau, son, points) et la petite danse, chacune avec sa case.",
                         "The feat announcement (banner, sound, points) and the little dance, each with its checkbox." },
        },
        sections = {
            { titre = { "Les catégories", "The categories" }, lignes = {
                { "Exploration, quêtes, donjons et raids (chaque boss, chaque rare), rares du monde, objets, métiers, races et classes, réputations, JcJ et héritage.",
                  "Exploration, quests, dungeons and raids (every boss, every rare), world rares, items, professions, races and classes, reputations, PvP and legacy." },
                { "En haut de chaque catégorie : tous vos personnages, votre camp, l'autre camp, puis la carte de votre personnage qui ouvre son détail.",
                  "At the top of each category : all your characters, your faction, the other faction, then your character's card that opens its detail." },
                { "Un haut fait par palier : rang de métier, niveau de classe (10 à 60).",
                  "One feat per step : profession rank, class level (10 to 60)." },
            } },
            { titre = { "Astuces", "Tips" }, lignes = {
                { "Les flèches en haut à droite reviennent sur ce que vous avez regardé.",
                  "The arrows at the top right go back over what you looked at." },
                { "À la manette, croix gauche et droite changent de personnage.",
                  "With a gamepad, D-pad left and right switch character." },
            } },
        },
    },
    ClassCore = {
        intro = { "Votre classe : quêtes de classe faites ou à faire, sorts du maître (niveau, coût), arbres de talents et modèles, objets de classe, et pour le chasseur le catalogue des familiers.",
                  "Your class : class quests done or to do, trainer spells (level, cost), talent trees and templates, class items, and for hunters the pet catalogue." },
        sections = {
            { titre = { "Astuces", "Tips" }, lignes = {
                { "Les talents se simulent sans rien dépenser ; un modèle s'enregistre et se partage.",
                  "Talents can be simulated without spending anything ; a template can be saved and shared." },
                { "Un sort à apprendre dit chez quel maître aller, et y guide.",
                  "A spell to learn tells which trainer to visit, and guides you there." },
            } },
        },
    },
    AuraCore = {
        intro = { "Un anneau discret autour du personnage : améliorations, procs, nourriture, flacon, potion, buffs de groupe, et les effets nuisibles sur leur propre cercle.",
                  "A discreet ring around the character : buffs, procs, food, flask, potion, group buffs, and harmful effects on their own circle." },
        sections = {
            { titre = { "Astuces", "Tips" }, lignes = {
                { "La disposition se règle dans ses pages ; en combat, seul ce qui a une place réservée reste caché.",
                  "The layout is set in its pages ; in combat, only what has a reserved spot stays hidden." },
                { "Le cor demande les buffs qui manquent au groupe, en messages courts.",
                  "The horn asks the group for missing buffs, in short messages." },
            } },
        },
    },
    PvPCore = {
        intro = { "Le JcJ : carte de champ de bataille flottante, honneur du jour, rang, files, objectifs, marques et quêtes JcJ.",
                  "PvP : floating battleground map, today's honor, rank, queues, objectives, marks and PvP quests." },
    },
    FriendsCore = {
        intro = { "Une petite aide : les add-ons d'autres auteurs qui complètent la suite, et les passerelles qui leur confient une tâche (itinéraires détaillés).",
                  "A little help : add-ons by other authors that complete the suite, and the bridges that hand them a task (detailed routes)." },
    },
}
