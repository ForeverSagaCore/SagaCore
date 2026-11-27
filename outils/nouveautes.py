#!/usr/bin/env python3
"""Fabrique Core/Nouveautes.lua (fenetre Derniere mise a jour) depuis notes/*.md.

A relancer a chaque nouvelle version, apres avoir ecrit notes/X.Y.Z.md :
    python3 outils/nouveautes.py
Le fichier est copie dans chaque add-on qui porte Suite.lua. Les dates
viennent du commit qui a pose chaque numero dans VERSION (sinon aujourd'hui).
"""
import datetime
import os
import re
import subprocess

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTEURS = ["CraftCore", "QuestCore", "MapCore", "LegacyCore", "AuraCore", "PvPCore", "GloryCore", "ClassCore"]

# Les series, de la plus recente a la plus ancienne : un titre, un resume qui
# explique la serie apres coup, et les versions qui en font partie.
SERIES = [
    ("3.0", "3.0 : GloryCore et l'itinéraire qui choisit",
     "GloryCore rejoint la suite (des points pour chaque haut fait, des objectifs à votre rythme réel). "
     "L'itinéraire de QuestCore pèse les visites, les sacs et les rendus pour choisir le meilleur ordre. "
     "Toutes les fenêtres partagent le même pied : Commandes, Aide, Dernière mise à jour, Réglages, Fermer.",
     lambda v: v.startswith("3.0.")),
    ("2.5", "2.5 : ClassCore, les caisses et le commerce",
     "ClassCore arrive en bêta (quêtes de classe, sorts, talents, familiers). CraftCore gagne le rang visé refondu, "
     "l'hôtel des ventes à la manette, les formateurs, le commerce des caisses et le commerce entre joueurs ; "
     "QuestCore, les détours dans l'itinéraire.",
     lambda v: v.startswith("2.5.")),
    ("2.1", "2.1 : monter un métier, vraiment guidé",
     "Un plan figé pour monter un métier, proposé et jamais imposé, des séries de fabrication complètes, la vente à "
     "l'hôtel des ventes depuis CraftCore, et la manette dans toutes les petites fenêtres.",
     lambda v: v.startswith("2.1.")),
    ("2.0", "2.0 : une suite refondue",
     "Une seule interface pour tous les add-ons, un personnage égale une seule fiche, et un guidage qu'on comprend "
     "et qu'on peut toujours annuler.",
     lambda v: v.startswith("2.0.")),
    ("1.7", "1.7 : un seul guidage pour toute la suite",
     "Un seul bouton Guider partout, le choix de qui vous guide (la flèche de la suite ou un add-on d'itinéraire), "
     "et des correctifs autour du nom du royaume.",
     lambda v: v.startswith("1.7.")),
    ("1.6", "1.6 : StuffCore et FriendsCore",
     "Deux nouveaux add-ons : StuffCore (votre équipement et d'où vient ce qui l'améliore) et FriendsCore (les "
     "add-ons d'autres auteurs qui complètent la suite).",
     lambda v: v.startswith("1.6.")),
    ("1.5", "1.5 : fabriquer, et AuraCore",
     "CraftCore fabrique lui-même, étape par étape, et vise plusieurs rangs à la fois. AuraCore arrive en bêta : "
     "un anneau d'améliorations autour du personnage.",
     lambda v: v.startswith("1.5.")),
    ("1.1", "1.1 à 1.4 : services, messages, charte et itinéraires",
     "Les services sur la carte de MapCore, la page Monter un métier, les messages de la suite dans la discussion, "
     "une charte graphique commune et les itinéraires dans le suivi des quêtes.",
     lambda v: v.split(".")[0] == "1" and v.split(".")[1] in ("1", "2", "3", "4")),
    ("1.0", "1.0 : les débuts",
     "La première suite complète : CraftCore, QuestCore, MapCore et LegacyCore ensemble. Les versions 1.0.1 à 1.0.14 "
     "sont des corrections rapides après la sortie, puis le nouveau nom, Forever SagaCore, et sept langues.",
     lambda v: v.startswith("1.0.")),
]

# Le titre de chaque version : ce qu'elle a apporte, en quelques mots.
TITRES = {
    "1.0.0": "Première version de la suite complète",
    "1.0.1": "LegacyCore : arbres comme dans le jeu",
    "1.0.2": "Corrections de CraftCore, QuestCore et LegacyCore",
    "1.0.3": "Corrections de CraftCore, QuestCore et LegacyCore",
    "1.0.4": "Onglets de la suite remplis par leur icône",
    "1.0.5": "Corrections de CraftCore, QuestCore et LegacyCore",
    "1.0.6": "Corrections dans les quatre add-ons",
    "1.0.7": "Nouveau nom : Forever SagaCore",
    "1.0.8": "Corrections dans les quatre add-ons",
    "1.0.9": "Corrections dans les quatre add-ons",
    "1.0.10": "Corrections dans les quatre add-ons",
    "1.0.11": "QuestCore : bouton Donner",
    "1.0.12": "Corrections de QuestCore et LegacyCore",
    "1.0.13": "Corrections de QuestCore et LegacyCore",
    "1.0.14": "Sept langues au choix",
    "1.1.0": "MapCore : les services sur la carte",
    "1.1.1": "QuestCore attend Questie",
    "1.1.2": "CraftCore : page Monter un métier",
    "1.2.0": "Publication automatique sur CurseForge",
    "1.2.1": "La suite vous parle dans la discussion",
    "1.3.0": "Charte graphique, fonds et réglage de l'interface",
    "1.3.1": "Personnage retrouvé quand le royaume arrive vide",
    "1.4.0": "Itinéraires dans le suivi des quêtes",
    "1.5.0": "CraftCore fabrique et vise plusieurs rangs",
    "1.5.1": "Nouveau : AuraCore (bêta)",
    "1.5.2": "AuraCore : demander les buffs",
    "1.5.3": "Petits ajustements",
    "1.6.0": "StuffCore et FriendsCore, guidage plus simple",
    "1.7.0": "Un seul guidage, clair",
    "1.7.1": "Guidage sans erreur en champ de bataille",
    "1.7.2": "Royaume cherché partout",
    "1.7.3": "Royaume des données déjà enregistrées",
    "2.0.0": "Une suite refondue",
    "2.0.1": "Guidage des suites de quêtes",
    "2.1.0": "CraftCore et guidage nettement améliorés",
    "2.1.1": "Manette libre au courrier et à la banque",
    "2.5.0": "ClassCore (bêta) et icônes encadrées",
    "2.5.1": "ClassCore et CraftCore enrichis",
    "2.5.2": "Modèles de talents personnels",
    "2.5.3": "Plus de blocage à l'hôtel des ventes",
    "2.5.4": "Rang visé et hôtel des ventes refondus",
    "2.5.5": "Où apprendre une recette",
    "2.5.6": "Détours, commerce des caisses et entre joueurs",
    "3.0.0": "GloryCore, itinéraire qui choisit, pied commun",
    "3.0.1": "Itinéraire de zone et GloryCore plus justes",
}

# Versions sans fichier de notes : ce qu'elles ont apporte.
SANS_NOTES = {
    "1.2.0": [("li", "La suite part sur CurseForge à chaque nouvelle version, en même temps que sur GitHub."),
              ("li", "CraftCore : la touche A de la manette marche à la banque avec ConsolePort.")],
}


def cle_version(v):
    return tuple(int(x) for x in v.split("."))


def dates():
    d = {}
    try:
        sortie = subprocess.check_output(["git", "log", "--reverse", "--format=%H %ad", "--date=short", "--", "VERSION"],
                                         cwd=RACINE, text=True)
    except Exception:
        return d
    for ligne in sortie.splitlines():
        h, jour = ligne.split()
        try:
            v = subprocess.check_output(["git", "show", h + ":VERSION"], cwd=RACINE, text=True).split()[0].strip()
        except Exception:
            continue
        if v not in d:
            d[v] = jour
    return d


def blocs_de(texte):
    lignes = texte.splitlines()
    blocs = []
    contenu = []
    dans_contenu = False
    resume_saute = False
    for i, l in enumerate(lignes):
        l = l.rstrip()
        if l.startswith("# "):
            continue
        if not l.strip():
            continue
        s = l.strip()
        if s.startswith("Contenu"):
            dans_contenu = True
            reste = s.split(":", 1)[1].strip() if ":" in s else ""
            if reste:
                contenu.append(reste)
            continue
        if dans_contenu:
            if s.startswith("- "):
                contenu.append(s[2:].strip())
                continue
            dans_contenu = False
        if s.startswith("## "):
            blocs.append(("h", s[3:].strip()))
        elif s.startswith("### "):
            blocs.append(("h", s[4:].strip()))
        elif s.startswith("- ") or s.startswith("* "):
            blocs.append(("li", s[2:].strip()))
        elif re.match(r"^\d+\. ", s):
            blocs.append(("li", re.sub(r"^\d+\. ", "", s)))
        else:
            suivante = ""
            for k in lignes[i + 1:]:
                if k.strip():
                    suivante = k.strip()
                    break
            court = len(s) < 70 and not s.endswith(".") and not s.endswith(":")
            if re.match(r"^([A-Za-z]+Core [0-9.]+(, )?)+\.?$", s):
                pass  # une simple liste de numeros : le Contenu la redit
            elif court and suivante.startswith("- "):
                blocs.append(("h", s))
            else:
                blocs.append(("p", s))
        resume_saute = True
    if contenu:
        blocs.append(("d", "Contenu : " + ", ".join(contenu)))
    return blocs


def lua(t):
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def main():
    notes = {}
    for nom in os.listdir(os.path.join(RACINE, "notes")):
        m = re.match(r"^(\d+\.\d+\.\d+)\.md$", nom)
        if m:
            with open(os.path.join(RACINE, "notes", nom), encoding="utf-8") as f:
                notes[m.group(1)] = f.read()
    versions = set(notes) | set(SANS_NOTES)
    jours = dates()
    aujourdhui = datetime.date.today().isoformat()

    def date(v):
        j = jours.get(v, aujourdhui)
        a, m, d = j.split("-")
        return "%s/%s/%s" % (d, m, a)

    sortie = []
    sortie.append("-- Fabrique par outils/nouveautes.py depuis notes/*.md : ne pas modifier a la main.")
    sortie.append("-- Fenetre Derniere mise a jour de la suite. Copie identique dans chaque add-on qui")
    sortie.append("-- porte Suite.lua : la copie la plus recente l'emporte.")
    sortie.append("")
    plus_recente = max(versions, key=cle_version)
    numero = int("".join("%03d" % int(x) for x in plus_recente.split(".")))
    sortie.append("local VERSION = %d" % numero)
    sortie.append("if type(_G.CoreSuiteNouveautesVersion) == \"number\" and _G.CoreSuiteNouveautesVersion >= VERSION then return end")
    sortie.append("_G.CoreSuiteNouveautesVersion = VERSION")
    sortie.append("")
    sortie.append("_G.CoreSuiteNouveautes = {")
    pris = set()
    for cle, titre, resume, test in SERIES:
        membres = sorted([v for v in versions if test(v)], key=cle_version, reverse=True)
        if not membres:
            continue
        pris.update(membres)
        periode = date(membres[-1]) if len(membres) == 1 else "%s au %s" % (date(membres[-1])[:5], date(membres[0]))
        sortie.append("    { cle = %s, titre = %s, periode = %s, resume = %s, versions = {" % (lua("s" + cle), lua(titre), lua(periode), lua(resume)))
        for v in membres:
            blocs = SANS_NOTES.get(v) or blocs_de(notes[v])
            sortie.append("        { v = %s, date = %s, titre = %s, blocs = {" % (lua(v), lua(date(v)), lua(TITRES.get(v, v))))
            for sorte, texte in blocs:
                sortie.append("            { %s, %s }," % (lua(sorte), lua(texte)))
            sortie.append("        } },")
        sortie.append("    } },")
    sortie.append("}")
    reste = versions - pris
    if reste:
        raise SystemExit("Versions sans serie : " + ", ".join(sorted(reste, key=cle_version)))
    texte = "\n".join(sortie) + "\n"
    for porteur in PORTEURS:
        chemin = os.path.join(RACINE, porteur, "Core", "Nouveautes.lua")
        if os.path.isdir(os.path.dirname(chemin)):
            with open(chemin, "w", encoding="utf-8") as f:
                f.write(texte)
    print("Nouveautes.lua : %d versions, la plus recente %s" % (len(versions), plus_recente))


if __name__ == "__main__":
    main()
