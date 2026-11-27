# Forever SagaCore

**La suite complète pour World of Warcraft : Forever** : des add-ons qui suivent toute l'aventure de vos personnages et fonctionnent ensemble, en un seul téléchargement.

| Add-on | Ce qu'il fait |
|---|---|
| **QuestCore** | Suivi des quêtes, trajets guidés, progression de niveau, donjons, quêtes de groupe. |
| **CraftCore** | Métiers, recettes, projets, progression, commandes entre vos personnages, prix et bénéfices. |
| **MapCore** | Cartes, services (maîtres, réparation, boîtes aux lettres...), vos repères, où sont vos personnages. |
| **LegacyCore** | Arbres d'héritage, défis du compte, temps passé sur chaque niveau. |
| **StuffCore** | Votre équipement : ce qui l'améliore et d'où ça vient (crafts, butins du monde, quêtes, donjons). Demande CraftCore. |
| **FriendsCore** | Une petite aide : les add-ons d'autres auteurs qui complètent la suite, et les passerelles qui leur confient une tâche (itinéraires détaillés). |
| **ClassCore** *(bêta)* | Votre classe : quêtes de classe faites ou à faire, sorts du maître (niveau, coût), arbres de talents, objets de classe, et pour le chasseur le catalogue complet des familiers. |
| **GloryCore** *(bêta)* | Finir le jeu : des points pour chaque haut fait (zones, quêtes, donjons avec tous leurs boss et leurs rares, objets, métiers, races et classes, réputations, JcJ, héritage), des objectifs à votre rythme réel, l'avancement de chaque personnage, de chaque camp et des deux. |
| **AuraCore** *(bêta)* | Un anneau discret autour du personnage : améliorations, procs, nourriture, flacon, potion, buffs de groupe, et les effets nuisibles sur leur propre cercle. Aussi publié seul. |

Chaque add-on s'installe aussi seul (StuffCore demande CraftCore). Installés ensemble, ils partagent la même interface (barre des personnages, menus, paramètres), le même personnage choisi et le même guidage, toujours annulable. Tout se joue aussi à la manette, en 7 langues.

**Nouveautés de la 3.0** : GloryCore rejoint la suite en bêta, l'itinéraire de QuestCore choisit lui-même le meilleur ordre (visites regroupées, sacs, rendus, suites), et toutes les fenêtres partagent le même pied : Commandes, Aide, Dernière mise à jour (l'histoire de chaque version, à déplier), Réglages, Fermer. Le détail : [notes de la 3.0.0](notes/3.0.0.md).

**Nouveautés de la 2.5** : ClassCore rejoint les compléments en bêta (quêtes de classe, sorts, talents, familiers), manette au courrier, à la banque et à l'hôtel des ventes, icônes encadrées comme dans le jeu. Le détail : [notes de la 2.5.0](notes/2.5.0.md). La 2.5.1 enrichit ClassCore (talents, simulation, modèles, maîtres) et CraftCore (marchands, paliers de métier) : [notes de la 2.5.1](notes/2.5.1.md). La 2.5.2 ajoute les modèles de talents personnels et partagés, et corrige CraftCore : [notes de la 2.5.2](notes/2.5.2.md). La 2.5.3 corrige un blocage du jeu à l'hôtel des ventes : [notes de la 2.5.3](notes/2.5.3.md). La 2.5.4 refond le rang visé de CraftCore et le panneau de l'hôtel des ventes : [notes de la 2.5.4](notes/2.5.4.md). La 2.5.5 dit chez quel formateur apprendre et y guide, et règle les quantités des projets commerciaux : [notes de la 2.5.5](notes/2.5.5.md). La 2.5.6 ajoute les détours dans l'itinéraire de QuestCore, le commerce des caisses et le commerce entre joueurs (bêta) dans CraftCore : [notes de la 2.5.6](notes/2.5.6.md).

**Nouveautés de la 2.1** : monter un métier vraiment guidé (plan figé, proposé jamais imposé), séries de fabrication complètes, vente à l'hôtel des ventes depuis CraftCore, quêtes et métiers reliés, guidage plus sûr, manette dans toutes les petites fenêtres. Le détail : [notes de la 2.1.0](notes/2.1.0.md), correctif [2.1.1](notes/2.1.1.md).

**Nouveautés de la 2.0** : interface commune à toute la suite, un personnage = une seule fiche, guidage annulable qui ne chevauche jamais un add-on d'itinéraire, feuille de route et banquiers dans CraftCore, itinéraires dans MapCore, donjons réécrits dans QuestCore. Le détail : [notes de la 2.0.0](notes/2.0.0.md).

Ouvrir la suite là où on l'avait laissée : `/sagacore`.

> **La version la plus à jour est toujours celle de GitHub.** CurseForge et Wago la reçoivent ensuite, avec parfois un peu de retard.

## Prérequis et compléments

| Add-on | | Pourquoi |
|---|---|---|
| [Questie](https://www.curseforge.com/wow/addons/questie) | **Fortement conseillé** | Il installe **QuestieDB**, la base des quêtes, des PNJ et des marchands. Sans lui, tout le reste marche, mais pas les positions des quêtes, les trajets, les donjons ni la localisation des marchands. |
| **DungeonJournal** (cherchez « DungeonJournal » dans CurseForge ou WowUp) | Conseillé | Le détail et le plan de chaque donjon (boss, butin), ouverts depuis la page Donjons de QuestCore. |

## Installation

### Avec WowUp (mises à jour automatiques, conseillé)

1. Installez [WowUp](https://wowup.io) et laissez-le trouver votre jeu.
2. Dans WowUp, choisissez la version **Forever**, puis **Get Addons** > **Install from URL**.
3. Collez l'adresse : `https://github.com/ForeverSagaCore/SagaCore`
4. Installez. WowUp proposera ensuite chaque nouvelle version de la suite.

Si vous aviez déjà installé un des add-ons seul, retirez-le de WowUp avant : la suite le contient.

### À la main

1. Téléchargez `ForeverSagaCore-X.Y.Z-forever.zip` depuis la [dernière version](https://github.com/ForeverSagaCore/SagaCore/releases/latest).
2. Décompressez-le dans `World of Warcraft/_forever_/Interface/AddOns/` : vous obtenez les dossiers `CraftCore`, `QuestCore`, `MapCore`, `LegacyCore`, `StuffCore`, `FriendsCore`, `AuraCore`, `ClassCore` et `GloryCore`.

## Signaler un problème

Ouvrez un ticket dans l'onglet **Issues** avec une capture et ce que vous faisiez juste avant.

## Me croiser en jeu

Mes principaux personnages sont **Beurkman** et **Paltank**, côté Alliance. Côté Horde, à venir. Pour les bugs, passez plutôt par l'onglet **Issues** : c'est là que je peux les suivre.

## Soutenir le projet

Forever SagaCore est et restera gratuit, sans rien à acheter dans le jeu. Si la suite vous rend service, un café sur Ko-fi m'aide à y passer plus de temps.

[![Soutenir sur Ko-fi](https://img.shields.io/badge/Soutenir%20sur-Ko--fi-72A4F2?style=for-the-badge&logo=kofi&logoColor=white)](https://ko-fi.com/foreversagacore)
