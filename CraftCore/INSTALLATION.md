# Installer CraftCore, étape par étape

Ce guide vous fait installer **CraftCore** pour **World of Warcraft : Forever**, puis recevoir ses mises à jour sans rien télécharger à la main.

Il y a deux façons de faire :

- **Avec WowUp (conseillé)** : un petit logiciel gratuit qui installe l'add-on et le met à jour pour vous. Comptez 10 minutes, une seule fois.
- **À la main** : vous téléchargez un fichier et vous le copiez au bon endroit. Il faudra recommencer à chaque nouvelle version.

---

## Méthode 1 : avec WowUp (conseillé)

### Étape 1. Fermer le jeu

Quittez complètement World of Warcraft avant de commencer.

### Étape 2. Télécharger WowUp

1. Ouvrez la page **[wowup.io](https://wowup.io)**.
2. Sur Windows, cliquez sur le bouton de téléchargement.
   Sur Mac (ou Linux), ouvrez la page des **[téléchargements de WowUp](https://github.com/WowUp/WowUp/releases/latest)** et prenez le fichier qui correspond à votre système (sur Mac, le fichier `.dmg`).
3. Si on vous propose deux éditions (Wago ou CurseForge), prenez **Wago** : c'est celle qui sait installer depuis GitHub.

### Étape 3. Installer WowUp

- **Windows** : lancez le fichier téléchargé et suivez l'installation.
- **Mac** : ouvrez le fichier `.dmg`, puis faites glisser WowUp dans le dossier Applications.
  Si le Mac refuse de l'ouvrir la première fois, faites un clic droit sur WowUp, puis **Ouvrir**, et confirmez.

### Étape 4. Lancer WowUp et trouver le jeu

1. Lancez WowUp. Il cherche tout seul vos jeux installés.
2. En haut de la fenêtre, une liste permet de choisir la version du jeu. Vérifiez que **Forever** y figure.
3. **Si Forever n'apparaît pas** :
   1. Ouvrez **Options**, puis **Clients**.
   2. Cliquez sur **Add New**.
   3. Allez dans votre dossier **World of Warcraft**, puis dans le dossier **`_forever_`**, et choisissez l'application du jeu qui s'y trouve.
   4. Revenez à l'écran principal : Forever doit maintenant être dans la liste.

### Étape 5. Installer CraftCore

1. Dans WowUp, ouvrez l'onglet **Get Addons**.
2. En haut, choisissez la version **Forever**.
3. Cliquez sur **Install from URL**.
4. Collez cette adresse :

   ```
   https://github.com/Kyudan-zz/CraftCore
   ```

5. Validez, puis cliquez sur **Install**.

CraftCore apparaît alors dans l'onglet **My Addons**.

### Étape 6. Lancer le jeu

1. Lancez World of Warcraft : Forever.
2. Sur l'écran de choix des personnages, cliquez sur **AddOns** (en bas à gauche) et vérifiez que **CraftCore** est coché.
3. Entrez en jeu. Pour ouvrir CraftCore : le bouton en forme d'engrenage autour de la minicarte, ou tapez **`/cc`** dans la fenêtre de discussion.

### Étape 7. Les mises à jour

Il n'y a rien à télécharger. Ouvrez WowUp de temps en temps (idéalement avant de lancer le jeu) :

1. Allez dans **My Addons**.
2. Si une nouvelle version de CraftCore existe, un bouton **Update** apparaît sur sa ligne. Cliquez dessus.

Faites les mises à jour **jeu fermé**.

---

## Méthode 2 : à la main

1. Quittez complètement le jeu.
2. Ouvrez la page de la **[dernière version de CraftCore](https://github.com/Kyudan-zz/CraftCore/releases/latest)**.
3. Dans la partie **Assets**, cliquez sur le fichier **`CraftCore-X.Y.Z-forever.zip`** pour le télécharger (X.Y.Z est le numéro de version).
4. Décompressez-le : vous obtenez un dossier **`CraftCore`**.
5. Copiez ce dossier dans :

   ```
   World of Warcraft/_forever_/Interface/AddOns/
   ```

   Si le dossier `AddOns` n'existe pas, créez-le.
6. Vérifiez le chemin final. Il doit être exactement :

   ```
   World of Warcraft/_forever_/Interface/AddOns/CraftCore/CraftCore.toc
   ```

   Pas de dossier en double (`CraftCore/CraftCore/...`) ni de numéro de version dans le nom du dossier, sinon le jeu ne voit pas l'add-on.
7. Lancez le jeu et suivez l'**étape 6** de la méthode 1.

**Pour mettre à jour à la main** : jeu fermé, supprimez l'ancien dossier `CraftCore` et remplacez-le par le nouveau. Vos données ne sont pas perdues : elles sont rangées ailleurs, dans le dossier `WTF` du jeu.

---

## Premiers pas dans CraftCore

CraftCore apprend ce que le jeu lui montre. Pour **chacun de vos personnages**, une seule fois :

1. Connectez-vous et ouvrez vos sacs.
2. Ouvrez votre banque une fois.
3. Ouvrez une fois la fenêtre de chacun de vos métiers.

Ensuite, depuis n'importe quel personnage, vous voyez tout votre compte. Le petit **« i »** en haut à gauche de la fenêtre explique chaque page.

Le mode d'emploi complet est dans le fichier **[README.txt](README.txt)**, inclus dans l'add-on.

---

## En cas de problème

**CraftCore n'apparaît pas dans la liste AddOns du jeu.**
Le dossier n'est pas au bon endroit. Vérifiez le chemin donné à l'étape 6 de la méthode 2.

**WowUp ne trouve pas Forever.**
Suivez le point 3 de l'étape 4 (Options, Clients, Add New).

**WowUp refuse l'adresse GitHub.**
Vérifiez que vous avez choisi **Forever** en haut de l'onglet Get Addons, et que l'adresse est exactement `https://github.com/Kyudan-zz/CraftCore`.

**Autre souci.**
Ouvrez un ticket dans l'onglet **[Issues](https://github.com/Kyudan-zz/CraftCore/issues)** de la page du projet, avec :

1. une capture d'écran du problème ;
2. ce que vous faisiez juste avant ;
3. si possible, le fichier `World of Warcraft/_forever_/WTF/Account/<VOTRE_COMPTE>/SavedVariables/CraftCore.lua` (après avoir quitté le jeu). Il contient un journal des incidents, les noms de vos personnages et leurs inventaires, rien d'autre.

---

CraftCore est gratuit et libre (licence GPL-3.0). Il n'envoie jamais de courrier et n'achète jamais rien à votre place.
