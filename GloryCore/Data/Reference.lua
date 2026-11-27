local _, NS = ...

-- Donnees de reference d'GloryCore : ce que le jeu ne dit pas aux
-- add-ons (combinaisons de races et classes, metiers, themes de quetes).
-- Tout ce que les releves decouvrent en plus (une combinaison propre a
-- WoW Forever, un metier, une faction) s'y ajoute de lui-meme.

NS.ref = {}
local ref = NS.ref
local T = NS.T

-- Classes : jeton du jeu et numero (bit des masques de la base de quetes).
ref.CLASSES = {
    { jeton = "WARRIOR", id = 1 }, { jeton = "PALADIN", id = 2 }, { jeton = "HUNTER", id = 3 },
    { jeton = "ROGUE", id = 4 }, { jeton = "PRIEST", id = 5 }, { jeton = "SHAMAN", id = 7 },
    { jeton = "MAGE", id = 8 }, { jeton = "WARLOCK", id = 9 }, { jeton = "DRUID", id = 11 },
}
ref.ID_CLASSE = {}
for _, c in ipairs(ref.CLASSES) do ref.ID_CLASSE[c.jeton] = c.id end
ref.ID_CLASSE.DEATHKNIGHT, ref.ID_CLASSE.MONK = 6, 10

-- Races du jeu d'origine : numero (bit des masques), jeton, faction.
ref.RACES = {
    { id = 1, jeton = "Human", faction = "Alliance", atlas = "human" },
    { id = 3, jeton = "Dwarf", faction = "Alliance", atlas = "dwarf" },
    { id = 4, jeton = "NightElf", faction = "Alliance", atlas = "nightelf" },
    { id = 7, jeton = "Gnome", faction = "Alliance", atlas = "gnome" },
    { id = 2, jeton = "Orc", faction = "Horde", atlas = "orc" },
    { id = 5, jeton = "Scourge", faction = "Horde", atlas = "undead" },
    { id = 6, jeton = "Tauren", faction = "Horde", atlas = "tauren" },
    { id = 8, jeton = "Troll", faction = "Horde", atlas = "troll" },
}
ref.RACE = {}
for _, r in ipairs(ref.RACES) do ref.RACE[r.id] = r end

-- Combinaisons possibles du jeu d'origine. Une combinaison propre a WoW
-- Forever (un chaman de l'Alliance...) s'ajoute des qu'un personnage du
-- compte l'a.
ref.COMBINAISONS = {
    [1] = { "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "MAGE", "WARLOCK" },
    [3] = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST" },
    [4] = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "DRUID" },
    [7] = { "WARRIOR", "ROGUE", "MAGE", "WARLOCK" },
    [2] = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "WARLOCK" },
    [5] = { "WARRIOR", "ROGUE", "PRIEST", "MAGE", "WARLOCK" },
    [6] = { "WARRIOR", "HUNTER", "SHAMAN", "DRUID" },
    [8] = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE" },
}

-- Paliers de niveau des races et des classes.
ref.PALIERS_NIVEAU = { 10, 20, 30, 40, 50, 60 }
function ref.NiveauMax()
    local n = tonumber(NS.Jeu("GetMaxPlayerLevel"))
    return (n and n > 0) and n or 60
end

-- Metiers : ligne du jeu, nom (si le jeu ne l'a pas encore donne), icone.
ref.METIERS = {
    { ligne = 171, fr = "Alchimie", en = "Alchemy", icone = "Interface\\Icons\\Trade_Alchemy" },
    { ligne = 164, fr = "Forge", en = "Blacksmithing", icone = "Interface\\Icons\\Trade_BlackSmithing" },
    { ligne = 333, fr = "Enchantement", en = "Enchanting", icone = "Interface\\Icons\\Trade_Engraving" },
    { ligne = 202, fr = "Ingénierie", en = "Engineering", icone = "Interface\\Icons\\Trade_Engineering" },
    { ligne = 182, fr = "Herboristerie", en = "Herbalism", icone = "Interface\\Icons\\Trade_Herbalism" },
    { ligne = 165, fr = "Travail du cuir", en = "Leatherworking", icone = "Interface\\Icons\\Trade_LeatherWorking" },
    { ligne = 186, fr = "Minage", en = "Mining", icone = "Interface\\Icons\\Trade_Mining" },
    { ligne = 393, fr = "Dépeçage", en = "Skinning", icone = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
    { ligne = 197, fr = "Couture", en = "Tailoring", icone = "Interface\\Icons\\Trade_Tailoring" },
    { ligne = 185, fr = "Cuisine", en = "Cooking", icone = "Interface\\Icons\\INV_Misc_Food_15", secondaire = true },
    { ligne = 129, fr = "Secourisme", en = "First Aid", icone = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", secondaire = true },
    { ligne = 356, fr = "Pêche", en = "Fishing", icone = "Interface\\Icons\\Trade_Fishing", secondaire = true },
}
ref.METIER = {}
for _, m in ipairs(ref.METIERS) do ref.METIER[m.ligne] = m end
ref.METIERS_PRINCIPAUX_MAX = 2

-- Rangs des metiers : Apprenti, Compagnon, Expert, Artisan.
ref.RANGS_METIER = {
    { rang = 75, fr = "Apprenti", en = "Apprentice" },
    { rang = 150, fr = "Compagnon", en = "Journeyman" },
    { rang = 225, fr = "Expert", en = "Expert" },
    { rang = 300, fr = "Artisan", en = "Artisan" },
}

-- Themes des quetes (zoneOrSort negatif de la base) : nom, ou la classe et
-- le metier qu'ils designent.
ref.THEMES = {
    [-61] = { classe = "WARLOCK" }, [-81] = { classe = "WARRIOR" }, [-82] = { classe = "SHAMAN" },
    [-141] = { classe = "PALADIN" }, [-161] = { classe = "MAGE" }, [-162] = { classe = "ROGUE" },
    [-261] = { classe = "HUNTER" }, [-262] = { classe = "PRIEST" }, [-263] = { classe = "DRUID" },
    [-24] = { metier = 182 }, [-101] = { metier = 356 }, [-121] = { metier = 164 }, [-181] = { metier = 171 },
    [-182] = { metier = 165 }, [-201] = { metier = 202 }, [-264] = { metier = 197 }, [-304] = { metier = 185 },
    [-324] = { metier = 129 },
    [-1] = { fr = "Épiques", en = "Epic" },
    [-22] = { fr = "Saisonnières", en = "Seasonal", fete = true },
    [-25] = { fr = "Champs de bataille", en = "Battlegrounds" },
    [-41] = { fr = "Jour des morts", en = "Day of the Dead", fete = true },
    [-221] = { fr = "Cartes au trésor", en = "Treasure maps" },
    [-284] = { fr = "Spéciales", en = "Special" },
    [-344] = { fr = "Légendaires", en = "Legendary" },
    [-364] = { fr = "Foire de Sombrelune", en = "Darkmoon Faire", fete = true },
    [-365] = { fr = "Guerre d'Ahn'Qiraj", en = "Ahn'Qiraj War" },
    [-366] = { fr = "Fête lunaire", en = "Lunar Festival", fete = true },
    [-367] = { fr = "Réputation", en = "Reputation" },
    [-368] = { fr = "Invasion", en = "Invasion" },
    [-369] = { fr = "Solstice d'été", en = "Midsummer", fete = true },
    [-370] = { fr = "Fête des Brasseurs", en = "Brewfest", fete = true },
    [-374] = { fr = "Jardin des nobles", en = "Noblegarden", fete = true },
    [-375] = { fr = "Bienfaits du pèlerin", en = "Pilgrim's Bounty", fete = true },
    [-376] = { fr = "De l'amour dans l'air", en = "Love is in the Air", fete = true },
}

-- Donjons et raids du jeu d'origine et de Forever (zones de la base), au cas
-- ou la table des donjons de QuestieDB manque. Les memes que QuestCore.
ref.DONJONS = { 2437, 718, 1581, 209, 719, 717, 721, 491, 796, 722, 1337, 1176, 2100, 1477, 1584, 1583,
    7307, 2557, 2057, 2017, 16919, 16611, 16732, 16544 }
ref.RAIDS = { [1977] = true, [2159] = true, [2677] = true, [2717] = true, [3428] = true, [3429] = true,
    [3456] = true, [3457] = true, [3606] = true, [3607] = true }
for zone in pairs(ref.RAIDS) do table.insert(ref.DONJONS, zone) end
-- Pas des donjons a faire : tram, salles de champions, champs de bataille.
ref.PAS_DONJONS = { [2257] = true, [2917] = true, [2918] = true, [2597] = true, [3277] = true, [3358] = true }

-- Champs de bataille (zones de la base) : une victoire dans chacun.
ref.CHAMPS = {
    { zone = 3277, fr = "Goulet des Chanteguerres", en = "Warsong Gulch" },
    { zone = 3358, fr = "Bassin Arathi", en = "Arathi Basin" },
    { zone = 2597, fr = "Vallée d'Alterac", en = "Alterac Valley" },
}

-- Rangs JcJ du jeu d'origine (1 a 14).
ref.RANGS_JCJ = 14

-- Paliers de reputation comptes (Amical a Exalte).
ref.PALIERS_REPUTATION = { 5, 6, 7, 8 }

-- Nom d'une classe, d'une race, d'un metier, dans la langue du jeu.
function ref.NomDeClasse(jeton)
    local noms = _G.LOCALIZED_CLASS_NAMES_MALE
    return (type(noms) == "table" and jeton and noms[jeton]) or tostring(jeton or "?")
end

function ref.NomDeRace(id)
    local info = NS.Jeu("C_CreatureInfo.GetRaceInfo", id)
    if type(info) == "table" and type(info.raceName) == "string" then return info.raceName end
    local r = ref.RACE[id]
    return r and r.jeton or ("#" .. tostring(id))
end

function ref.NomDeMetier(ligne, connu)
    if type(connu) == "string" and connu ~= "" then return connu end
    local m = ref.METIER[tonumber(ligne) or 0]
    if m then return T(m.fr, m.en) end
    return "#" .. tostring(ligne)
end

function ref.NomDeTheme(sort)
    local t = ref.THEMES[sort]
    if not t then return T("Autres", "Other") end
    if t.classe then return ref.NomDeClasse(t.classe) end
    if t.metier then return ref.NomDeMetier(t.metier) end
    return T(t.fr, t.en)
end

-- Couleur exacte d'une classe ({ r, g, b, classe = true }), blanc sinon.
function ref.CouleurDeClasse(jeton)
    local c = _G.RAID_CLASS_COLORS and jeton and _G.RAID_CLASS_COLORS[jeton]
    if c then return { c.r, c.g, c.b, classe = true } end
    return { 1, 1, 1 }
end

function ref.Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- XP pour passer du niveau n au suivant (jeu d'origine, 1 a 59).
ref.XP_NIVEAU = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500,
    123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
