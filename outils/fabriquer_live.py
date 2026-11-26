#!/usr/bin/env python3
"""Forever SagaCore Live : la derniere version publiee de la suite, telle que
les joueurs l'ont telechargee, a cote de la suite normale et de la Dev.
Chaque add-on publie X devient XLive (dossier, toc, titre en bleu), avec ses
propres donnees (le fichier de sauvegarde suit le nom du dossier). Une seule
suite active a la fois : /sagalive y va, /sagalive ou /saganormal en revient,
/sagadev passe a la Dev.

Le contenu vient tel quel de l'etiquette git de la version publiee (vX.Y.Z),
et seulement les add-ons que cette publication contenait. Un seul fichier est
ajoute : SagaLive.lua, pour basculer d'une suite a l'autre (la version
publiee ne connait pas la suite Live) et couper les options privees, que les
joueurs n'ont pas.

Usage : outils/fabriquer_live.py <dossier de sortie> [etiquette]
"""
import io, os, re, shutil, subprocess, sys, tarfile

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Toutes les suites connues aujourd'hui : SagaLive.lua coupe ce qui n'est pas Live.
TOUS = ["CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore", "PvPCore", "AchievementCore", "ClassCore"]
PRIVES = ["TradeCore"]

def git(*args):
    return subprocess.run(["git", "-C", RACINE] + list(args), check=True, capture_output=True).stdout

sortie = sys.argv[1]
if len(sys.argv) > 2:
    etiquette = sys.argv[2]
else:
    etiquettes = [e for e in git("tag", "--sort=-v:refname").decode().split() if re.match(r"^v\d+\.\d+\.\d+$", e)]
    etiquette = etiquettes[0]
version = etiquette.lstrip("v")

# Les add-ons publies dans cette version : ceux que le zip de publication contenait.
flux = git("show", etiquette + ":.github/workflows/release.yml").decode()
m = re.search(r"cp -r ([A-Za-z ]+) build/", flux)
PUBLIES = m.group(1).split() if m else ["CraftCore", "QuestCore", "MapCore", "LegacyCore", "StuffCore", "FriendsCore", "AuraCore"]

def live(nom):
    return nom + "Live"

BASCULE = r'''-- Forever SagaCore Live : ajoute a la version publiee, rien d'autre.
-- Les options privees sont coupees (les joueurs ne les ont pas), et l'on
-- bascule d'une suite a l'autre : /sagalive ou /saganormal (suite normale),
-- /sagadev (suite d'essai).
local TOUS = { %(tous)s }
local PRIVES = { %(prives)s }
local MODES = { normale = "", dev = "Dev", live = "Live" }
local function Basculer(cible)
    local A = _G.C_AddOns or {}
    local activer = A.EnableAddOn or _G.EnableAddOn
    local couper = A.DisableAddOn or _G.DisableAddOn
    local info = A.GetAddOnInfo or _G.GetAddOnInfo
    if not (activer and couper and info) then return end
    local function Existe(n) local ok, nom = pcall(info, n) return ok and nom ~= nil end
    for _, n in ipairs(TOUS) do
        for mode, suffixe in pairs(MODES) do
            if Existe(n .. suffixe) then
                if mode == cible then pcall(activer, n .. suffixe) else pcall(couper, n .. suffixe) end
            end
        end
    end
    for _, n in ipairs(PRIVES) do
        if Existe(n) then if cible == "live" then pcall(couper, n) else pcall(activer, n) end end
    end
    local fr = (_G.GetLocale and _G.GetLocale() == "frFR")
    local textes = { normale = fr and "Retour à la suite normale." or "Back to the normal suite.",
        dev = fr and "Passage à Forever SagaCore Dev." or "Switching to Forever SagaCore Dev." }
    print("|cffffd100SagaCore|r " .. textes[cible])
    if _G.C_UI and _G.C_UI.Reload then _G.C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
end
if not _G.SagaCoreLiveBascule then
    _G.SagaCoreLiveBascule = true
    SLASH_SAGACORELIVE1 = "/sagalive"
    SLASH_SAGACORELIVE2 = "/saganormal"
    SlashCmdList["SAGACORELIVE"] = function() Basculer("normale") end
    SLASH_SAGACOREDEV1 = "/sagadev"
    SlashCmdList["SAGACOREDEV"] = function() Basculer("dev") end
    -- Ce que voient les joueurs : jamais les options privees.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if type(CoreSuiteDB) == "table" then CoreSuiteDB.prive = nil end
        local S = _G.CoreSuite
        if S then S.Prive = function() return false end end
    end)
    print("|cffffd100SagaCore|r |cff33ccffLive %(version)s|r : " .. ((_G.GetLocale and _G.GetLocale() == "frFR")
        and "la version publiée, telle que les joueurs l'ont. /sagalive pour revenir." or "the published version, as players have it. /sagalive to go back."))
end
''' % {"tous": ", ".join('"%s"' % n for n in TOUS), "prives": ", ".join('"%s"' % n for n in PRIVES), "version": version}

os.makedirs(sortie, exist_ok=True)
for a in PUBLIES:
    dst = os.path.join(sortie, live(a))
    if os.path.exists(dst):
        shutil.rmtree(dst)
    archive = git("archive", "--format=tar", etiquette, a)
    with tarfile.open(fileobj=io.BytesIO(archive)) as t:
        t.extractall(sortie)  # archive git locale, sure
    os.rename(os.path.join(sortie, a), dst)
    ancien = os.path.join(dst, a + ".toc")
    toc = open(ancien, encoding="utf-8").read()
    os.remove(ancien)
    toc = re.sub(r"^## Title: (.*)$", lambda m: "## Title: " + m.group(1) + " |cff33ccffLive|r", toc, flags=re.M)
    def deps(m):
        noms = [n.strip() for n in m.group(2).split(",")]
        return m.group(1) + ", ".join(live(n) if n in PUBLIES else n for n in noms)
    toc = re.sub(r"^(## (?:RequiredDeps|Dependencies|OptionalDeps): )(.*)$", deps, toc, flags=re.M)
    if "## DefaultState:" not in toc:
        toc = toc.replace("## Title:", "## DefaultState: disabled\n## Title:", 1)
    # Le numero de la version publiee, lisible sans charger l'add-on.
    toc = re.sub(r"^## X-SagaCore-Version:.*\n", "", toc, flags=re.M)
    toc = toc.replace("## Title:", "## X-SagaCore-Version: " + version + "\n## Title:", 1)
    # La bascule, chargee en dernier.
    toc = toc.rstrip("\n") + "\nSagaLive.lua\n"
    open(os.path.join(dst, live(a) + ".toc"), "w", encoding="utf-8").write(toc)
    open(os.path.join(dst, "SagaLive.lua"), "w", encoding="utf-8").write(BASCULE)
    # Les rares endroits qui nomment un dossier d'add-on en dur (comme pour la Dev).
    for dossier, _, fichiers in os.walk(dst):
        for f in fichiers:
            if not f.endswith(".lua"):
                continue
            p = os.path.join(dossier, f)
            s = open(p, encoding="utf-8").read()
            t = s
            t = t.replace('if qui ~= "CraftCore" then return end', 'if qui ~= "CraftCoreLive" then return end')
            t = t.replace('NS.Appeler(charge, "MapCore")', 'NS.Appeler(charge, "MapCoreLive")')
            t = t.replace("local ok, oui = pcall(charge, info.cle)", 'local ok, oui = pcall(charge, info.cle .. "Live")')
            t = t.replace('if addon ~= "CraftCore" or', 'if addon ~= "CraftCoreLive" or')
            if t != s:
                open(p, "w", encoding="utf-8").write(t)
print("Live", version, "fabrique dans", sortie, ":", ", ".join(live(a) for a in PUBLIES))
