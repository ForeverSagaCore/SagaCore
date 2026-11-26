local _, NS = ...

-- Ce que ClassCore sait de chaque classe : ses objets de classe (reactifs,
-- totems, fragments), ses sorts a suivre par famille, et ce que la pastille
-- pres du portrait compte. Les noms et les icones viennent du jeu (dans la
-- langue du client) : un sort ou un objet que le jeu ne connait pas n'est
-- jamais affiche.
--
-- Sorts : { id, niveau, camp = "A" | "H" (sinon les deux), talent = vrai }.
-- Objets : { id, niveau (a partir duquel il sert), seuil (conseille) }.

local T = NS.T

NS.classes = {}
local C = NS.classes

-- Identifiants des classes dans la base de quetes (masque requiredClasses).
C.ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

C.ORDRE = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

C.ICONE = {
    WARRIOR = "Interface\\Icons\\INV_Sword_27",
    PALADIN = "Interface\\Icons\\Spell_Holy_HolyBolt",
    HUNTER = "Interface\\Icons\\INV_Weapon_Bow_07",
    ROGUE = "Interface\\Icons\\INV_ThrowingKnife_04",
    PRIEST = "Interface\\Icons\\INV_Staff_30",
    SHAMAN = "Interface\\Icons\\Spell_Nature_BloodLust",
    MAGE = "Interface\\Icons\\INV_Staff_13",
    WARLOCK = "Interface\\Icons\\Spell_Nature_FaerieFire",
    DRUID = "Interface\\Icons\\Ability_Druid_Maul",
}

local D = {}
C.donnees = D

D.WARRIOR = {
    objets = {},
    sorts = {
        { titre = function() return T("Postures", "Stances") end, liste = {
            { 2457, 1 }, { 71, 10 }, { 2458, 30 } } },
        { titre = function() return T("Cris", "Shouts") end, liste = {
            { 6673, 1 }, { 1160, 14 }, { 5246, 22 }, { 1161, 26 } } },
        { titre = function() return T("Déplacements et contrôle", "Movement and control") end, liste = {
            { 100, 4 }, { 20252, 30 }, { 355, 10 }, { 694, 16 }, { 676, 18 }, { 18499, 32 } } },
        { titre = function() return T("Grandes recharges", "Major cooldowns") end, liste = {
            { 871, 28 }, { 1719, 50 }, { 20230, 20 } } },
    },
}

D.PALADIN = {
    objets = {
        { id = 21177, niveau = 52, seuil = 20 },
        { id = 17033, niveau = 30, seuil = 2 },
    },
    sorts = {
        { titre = function() return T("Auras", "Auras") end, liste = {
            { 465, 1 }, { 7294, 16 }, { 19746, 22 }, { 19876, 28 }, { 19888, 32 }, { 19891, 36 } } },
        { titre = function() return T("Bénédictions", "Blessings") end, liste = {
            { 19740, 4 }, { 1022, 10 }, { 19742, 14 }, { 1044, 18 }, { 20217, 20 }, { 6940, 46 },
            { 25782, 52 }, { 25894, 54 }, { 25898, 60 } } },
        { titre = function() return T("Sceaux", "Seals") end, liste = {
            { 20154, 1 }, { 21082, 6 }, { 20164, 22 }, { 20165, 30 }, { 20166, 38 }, { 20375, 20, talent = true } } },
        { titre = function() return T("Montures et utilitaires", "Mounts and utility") end, liste = {
            { 7328, 12 }, { 5502, 20 }, { 13819, 40, camp = "A" }, { 23214, 60, camp = "A" },
            { 1279399, 40, camp = "H" }, { 1296534, 60, camp = "H" }, { 19752, 30 } } },
    },
    badge = { { genre = "objet", id = 21177, niveau = 52 } },
}

D.HUNTER = {
    objets = {},
    sorts = {
        { titre = function() return T("Familier", "Pet") end, liste = {
            { 1515, 10 }, { 883, 10 }, { 6991, 10 }, { 5149, 12 }, { 982, 10 }, { 136, 12 }, { 1002, 14 }, { 1462, 24 } } },
        { titre = function() return T("Aspects", "Aspects") end, liste = {
            { 13163, 4 }, { 13165, 10 }, { 5118, 20 }, { 13159, 30 }, { 13161, 30 }, { 20043, 46 } } },
        { titre = function() return T("Pistages", "Tracking") end, liste = {
            { 1494, 1 }, { 19883, 10 }, { 19884, 18 }, { 19885, 26 }, { 19880, 34 }, { 19878, 32 }, { 19882, 40 }, { 19879, 50 } } },
        { titre = function() return T("Pièges", "Traps") end, liste = {
            { 13795, 16 }, { 1499, 20 }, { 13809, 28 }, { 13813, 34 } } },
    },
    badge = { { genre = "munitions" } },
}

D.ROGUE = {
    objets = {
        { id = 5140, niveau = 22, seuil = 10 },
        { id = 5530, niveau = 34, seuil = 5 },
        { id = 5060, niveau = 16, seuil = 1 },
        { id = 3371, niveau = 20, seuil = 0 },
        { id = 3372, niveau = 30, seuil = 0 },
        { id = 8925, niveau = 50, seuil = 0 },
        { id = 2928, niveau = 20, seuil = 0 },
        { id = 8924, niveau = 30, seuil = 0 },
        { id = 2930, niveau = 30, seuil = 0 },
        { id = 8923, niveau = 40, seuil = 0 },
        { id = 5173, niveau = 30, seuil = 0 },
    },
    sorts = {
        { titre = function() return T("Discrétion", "Stealth") end, liste = {
            { 1784, 1 }, { 1856, 22 }, { 2983, 10 }, { 5277, 8 }, { 2836, 24 } } },
        { titre = function() return T("Contrôle", "Control") end, liste = {
            { 6770, 10 }, { 1776, 6 }, { 2094, 34 }, { 408, 30 }, { 1766, 12 } } },
        { titre = function() return T("Utilitaires", "Utility") end, liste = {
            { 921, 4 }, { 1804, 16 }, { 1842, 30 } } },
    },
    badge = { { genre = "objet", id = 5140, niveau = 22 } },
}

D.PRIEST = {
    objets = {
        { id = 17028, niveau = 48, seuil = 10 },
        { id = 17029, niveau = 56, seuil = 10 },
        { id = 17056, niveau = 34, seuil = 5 },
    },
    sorts = {
        { titre = function() return T("Bénédictions du groupe", "Group buffs") end, liste = {
            { 1243, 1 }, { 21562, 48 }, { 14752, 30, talent = true }, { 27681, 60, talent = true },
            { 976, 30 }, { 27683, 56 }, { 588, 12 } } },
        { titre = function() return T("Sorts de race", "Racial spells") end, liste = {
            { 13908, 10 }, { 2652, 10 }, { 2944, 20 }, { 6346, 20 }, { 9035, 10 }, { 18137, 20 },
            { 2651, 20 }, { 10797, 10 }, { 13896, 20 } } },
        { titre = function() return T("Utilitaires", "Utility") end, liste = {
            { 1706, 34 }, { 2006, 10 }, { 527, 18 }, { 15473, 40, talent = true } } },
    },
    badge = { { genre = "objet", id = 17028, niveau = 48 } },
}

D.SHAMAN = {
    objets = {
        { id = 17030, niveau = 30, seuil = 5 },
        { id = 5175, niveau = 4, seuil = 1 },
        { id = 5176, niveau = 10, seuil = 1 },
        { id = 5177, niveau = 20, seuil = 1 },
        { id = 5178, niveau = 30, seuil = 1 },
    },
    sorts = {
        { titre = function() return T("Totems de terre", "Earth totems") end, liste = {
            { 8071, 4 }, { 2484, 6 }, { 5730, 8 }, { 8075, 10 }, { 8143, 18 } } },
        { titre = function() return T("Totems de feu", "Fire totems") end, liste = {
            { 3599, 10 }, { 1535, 12 }, { 8181, 24 }, { 8190, 26 }, { 8227, 28 } } },
        { titre = function() return T("Totems d'eau", "Water totems") end, liste = {
            { 5394, 20 }, { 8166, 22 }, { 8170, 38 }, { 8184, 28 }, { 5675, 26 }, { 16190, 40, talent = true } } },
        { titre = function() return T("Totems d'air", "Air totems") end, liste = {
            { 8177, 30 }, { 8512, 32 }, { 6495, 34 }, { 10595, 30 }, { 15107, 36 }, { 8835, 42 } } },
        { titre = function() return T("Armes et utilitaires", "Weapons and utility") end, liste = {
            { 8017, 1 }, { 8024, 10 }, { 8033, 20 }, { 8232, 30 }, { 324, 8 }, { 2645, 20 },
            { 20608, 30 }, { 556, 30 }, { 2008, 12 }, { 131, 22 }, { 546, 28 } } },
    },
    badge = { { genre = "objet", id = 17030, niveau = 30 } },
}

D.MAGE = {
    objets = {
        { id = 17031, niveau = 20, seuil = 5 },
        { id = 17032, niveau = 40, seuil = 5 },
        { id = 17020, niveau = 56, seuil = 20 },
        { id = 17056, niveau = 12, seuil = 5 },
    },
    sorts = {
        { titre = function() return T("Téléportations", "Teleports") end, liste = {
            { 3561, 20, camp = "A" }, { 3562, 20, camp = "A" }, { 3565, 30, camp = "A" },
            { 3567, 20, camp = "H" }, { 3563, 20, camp = "H" }, { 3566, 30, camp = "H" } } },
        { titre = function() return T("Portails", "Portals") end, liste = {
            { 10059, 40, camp = "A" }, { 11416, 40, camp = "A" }, { 11419, 50, camp = "A" },
            { 11417, 40, camp = "H" }, { 11418, 40, camp = "H" }, { 11420, 50, camp = "H" } } },
        { titre = function() return T("Eau, nourriture et gemmes", "Water, food and gems") end, liste = {
            { 5504, 4 }, { 587, 6 }, { 759, 28 }, { 3552, 38 }, { 10053, 48 }, { 10054, 58 } } },
        { titre = function() return T("Buffs et utilitaires", "Buffs and utility") end, liste = {
            { 1459, 1 }, { 23028, 56 }, { 604, 12 }, { 1008, 18 }, { 130, 12 }, { 475, 18 }, { 118, 8 }, { 12051, 20 } } },
    },
    badge = { { genre = "objet", id = 17031, niveau = 20 } },
}

D.WARLOCK = {
    objets = {
        { id = 6265, niveau = 10, seuil = 5 },
        { id = 5565, niveau = 50, seuil = 1 },
        { id = 16583, niveau = 60, seuil = 1 },
    },
    sorts = {
        { titre = function() return T("Démons", "Demons") end, liste = {
            { 688, 1 }, { 697, 10 }, { 712, 20 }, { 713, 20 }, { 691, 30 }, { 1122, 50 }, { 18540, 60 } } },
        { titre = function() return T("Pierres", "Stones") end, liste = {
            { 6201, 10 }, { 693, 18 }, { 6366, 28 }, { 2362, 36 } } },
        { titre = function() return T("Montures et utilitaires", "Mounts and utility") end, liste = {
            { 5784, 40 }, { 23161, 60 }, { 698, 20 }, { 1098, 30 }, { 710, 28 }, { 5697, 16 } } },
    },
    badge = { { genre = "objet", id = 6265, niveau = 1 } },
}

D.DRUID = {
    objets = {
        { id = 17034, niveau = 20, seuil = 3, jusqua = 29 },
        { id = 17035, niveau = 30, seuil = 3, jusqua = 39 },
        { id = 17036, niveau = 40, seuil = 3, jusqua = 49 },
        { id = 17037, niveau = 50, seuil = 3, jusqua = 59 },
        { id = 17038, niveau = 60, seuil = 3 },
        { id = 17021, niveau = 50, seuil = 10, jusqua = 59 },
        { id = 17026, niveau = 60, seuil = 10 },
    },
    sorts = {
        { titre = function() return T("Formes", "Forms") end, liste = {
            { 5487, 10 }, { 1066, 16 }, { 768, 20 }, { 783, 30 }, { 9634, 40 }, { 24858, 40, talent = true } } },
        { titre = function() return T("Utilitaires", "Utility") end, liste = {
            { 18960, 10 }, { 20484, 20 }, { 29166, 40 }, { 8946, 14 }, { 2782, 24 }, { 2893, 26 } } },
        { titre = function() return T("Buffs", "Buffs") end, liste = {
            { 1126, 1 }, { 21849, 50 }, { 467, 6 }, { 16864, 20, talent = true } } },
    },
    badge = { { genre = "formes" } },
}

-- Le nom de certaines chaines de quetes : ce qu'elles apportent. Cle : une
-- quete de la chaine (n'importe laquelle). Les autres chaines prennent le
-- nom de leur derniere quete.
C.CHAINES = {
    -- Druide
    [5921] = function() return T("Forme d'ours", "Bear Form") end, [5922] = function() return T("Forme d'ours", "Bear Form") end,
    [6121] = function() return T("Guérison du poison", "Cure Poison") end, [6126] = function() return T("Guérison du poison", "Cure Poison") end,
    [26] = function() return T("Forme aquatique", "Aquatic Form") end, [27] = function() return T("Forme aquatique", "Aquatic Form") end,
    [98405] = function() return T("Forme de félin", "Cat Form") end,
    -- Demoniste
    [1598] = function() return T("Diablotin", "Imp") end, [1599] = function() return T("Diablotin", "Imp") end,
    [1485] = function() return T("Diablotin", "Imp") end, [1470] = function() return T("Diablotin", "Imp") end,
    [1685] = function() return T("Marcheur du Vide", "Voidwalker") end, [1478] = function() return T("Marcheur du Vide", "Voidwalker") end,
    [1506] = function() return T("Marcheur du Vide", "Voidwalker") end,
    [1716] = function() return T("Succube", "Succubus") end, [1472] = function() return T("Succube", "Succubus") end,
    [1507] = function() return T("Succube", "Succubus") end,
    [65602] = function() return T("Incube", "Incubus") end, [65593] = function() return T("Incube", "Incubus") end,
    [65601] = function() return T("Incube", "Incubus") end,
    [1795] = function() return T("Chasseur corrompu", "Felhunter") end,
    [4490] = function() return T("Destrier corrompu", "Felsteed") end,
    [7601] = function() return T("Infernal", "Infernal") end,
    [7583] = function() return T("Garde funeste", "Doomguard") end,
    [7631] = function() return T("Destrier de l'effroi", "Dreadsteed") end,
    [1740] = function() return T("Orbe de Soran'ruk", "Orb of Soran'ruk") end,
    -- Paladin
    [1661] = function() return T("Destrier", "Warhorse") end,
    [7647] = function() return T("Destrier de guerre", "Charger") end,
    [1654] = function() return T("Poing de Verigan", "Verigan's Fist") end,
    -- Chasseur
    [7636] = function() return T("Rhok'delar", "Rhok'delar") end,
    [8232] = function() return T("Temple englouti", "Sunken Temple") end,
    -- Mage
    [1952] = function() return T("Baguette de mage", "Mage's Wand") end,
    [1958] = function() return T("Puissance céleste", "Celestial Power") end,
    [8253] = function() return T("Temple englouti", "Sunken Temple") end,
    [7463] = function() return T("Eau cristalline", "Crystal Water") end,
    -- Guerrier
    [1719] = function() return T("Posture berserker", "Berserker Stance") end,
    [1792] = function() return T("Hache tourbillonnante", "Whirlwind Axe") end,
}
