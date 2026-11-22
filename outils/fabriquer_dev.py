#!/usr/bin/env python3
"""Forever SagaCore Dev : une copie de la suite pour les essais, a cote de
la vraie. Chaque add-on X devient XDev (dossier, toc, titre en orange), avec
ses propres donnees (le fichier de sauvegarde suit le nom du dossier). On
active l'une ou l'autre suite, jamais les deux (/sagadev bascule).

Usage : outils/fabriquer_dev.py <dossier de sortie>
"""
import os, re, shutil, sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = ["CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore", "PvPCore", "AchievementCore"]
sortie = sys.argv[1]

def dev(nom):
    return nom + "Dev"

for a in ADDONS:
    src, dst = os.path.join(RACINE, a), os.path.join(sortie, dev(a))
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    # Le toc : nouveau nom de fichier, titre marque Dev, dependances vers les Dev.
    ancien = os.path.join(dst, a + ".toc")
    toc = open(ancien, encoding="utf-8").read()
    os.remove(ancien)
    toc = re.sub(r"^## Title: (.*)$", lambda m: "## Title: " + m.group(1) + " |cffff8000Dev|r", toc, flags=re.M)
    def deps(m):
        noms = [n.strip() for n in m.group(2).split(",")]
        return m.group(1) + ", ".join(dev(n) if n in ADDONS else n for n in noms)
    toc = re.sub(r"^(## (?:RequiredDeps|Dependencies|OptionalDeps): )(.*)$", deps, toc, flags=re.M)
    # Desactive tant qu'on ne bascule pas (/sagadev) : jamais deux suites a la fois.
    if "## DefaultState:" not in toc:
        toc = toc.replace("## Title:", "## DefaultState: disabled\n## Title:", 1)
    open(os.path.join(dst, dev(a) + ".toc"), "w", encoding="utf-8").write(toc)
    # Les rares endroits qui nomment un dossier d'add-on en dur.
    for dossier, _, fichiers in os.walk(dst):
        for f in fichiers:
            if not f.endswith(".lua"):
                continue
            p = os.path.join(dossier, f)
            s = open(p, encoding="utf-8").read()
            t = s
            t = t.replace('if qui ~= "CraftCore" then return end', 'if qui ~= "CraftCoreDev" then return end')
            t = t.replace('NS.Appeler(charge, "MapCore")', 'NS.Appeler(charge, "MapCoreDev")')
            t = t.replace("local ok, oui = pcall(charge, info.cle)", 'local ok, oui = pcall(charge, info.cle .. "Dev")')
            if t != s:
                open(p, "w", encoding="utf-8").write(t)
print("Dev fabrique dans", sortie)
