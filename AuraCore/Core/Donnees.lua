local _, NS = ...

-- Ce que l'anneau reconnait (WoW Forever, contenu classique). Les sorts sont
-- donnes par un identifiant de rang 1 : seul leur nom compte (il est le meme
-- a tous les rangs, dans la langue du jeu).

NS.donnees = {}
local D = NS.donnees

-- Buffs de groupe : par classe qui peut les donner. Chaque entree est une
-- liste d'alternatives (le meme effet en version individuelle ou de groupe).
D.GROUPE = {
    PRIEST = { { 1243, 21562 }, { 14752, 27681 }, { 976, 27683 } },
    MAGE = { { 1459, 23028 } },
    DRUID = { { 1126, 21849 }, { 467 } },
    PALADIN = { { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890, 20911, 25899 } },
    WARRIOR = { { 6673 } },
    HUNTER = { { 19506 } },
}

-- Ce que chaque classe se met elle-meme : une famille par place (une seule
-- active a la fois dans une famille). Le premier rang suffit : le nom est
-- le meme pour tous les rangs.
D.SOI = {
    HUNTER = { { 13165, 13163, 5118, 13159, 13161, 20043 } },      -- Aspects (faucon, singe, guepard, meute, bete, nature)
    PALADIN = { { 465, 7294, 19746, 19876, 19888, 19891 } },        -- Auras
    PRIEST = { { 588 } },                                           -- Feu interieur
    MAGE = { { 168, 7302, 6117 } },                                 -- Armures (givre, glace, mage)
    WARLOCK = { { 687, 706 } },                                     -- Peau de demon, Armure demoniaque
    SHAMAN = { { 324 } },                                           -- Bouclier de foudre
}

-- Consommables : flacons et elixirs courants, nourriture.
D.FLACONS = { 17626, 17627, 17628, 17629, 17538, 11405, 11334, 11328, 3160, 3593, 11348, 11396, 17535, 11390, 11406, 17537, 17539 }
D.NOURRITURE = { 19705, 24799, 18191, 18192, 18193, 18194, 18222, 22730, 25661 }
-- Potions de soins et de mana, de la meilleure a la plus petite.
D.POTIONS = { 13446, 3928, 1710, 929, 858, 118, 13444, 13443, 6149, 3827, 3385, 2455 }

-- Nom d'un sort, dans la langue du jeu.
local noms = {}
function D.Nom(id)
    if noms[id] ~= nil then return noms[id] or nil end
    local nom
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then nom = n end
    end
    if not nom and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then nom = n end
    end
    noms[id] = nom or false
    return nom
end

function D.Icone(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and t then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok and t then return t end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
