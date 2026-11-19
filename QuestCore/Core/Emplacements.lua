local _, NS = ...

-- Emplacements d'equipement.
--
-- La correspondance entre le code rendu par le client et un emplacement est
-- reprise de la table de Simulationcraft, installe sur ce client. Les libelles
-- ne sont pas traduits par QuestCore : on reprend ceux du jeu, qui sont deja
-- dans la langue du joueur.

NS.emplacements = {}
local emplacements = NS.emplacements

-- Code rendu par le client, puis nom de la globale du jeu qui porte le libelle.
local LIBELLE = {
    INVTYPE_HEAD = "HEADSLOT",
    INVTYPE_NECK = "NECKSLOT",
    INVTYPE_SHOULDER = "SHOULDERSLOT",
    INVTYPE_CLOAK = "BACKSLOT",
    INVTYPE_CHEST = "CHESTSLOT",
    INVTYPE_ROBE = "CHESTSLOT",
    INVTYPE_BODY = "SHIRTSLOT",
    INVTYPE_TABARD = "TABARDSLOT",
    INVTYPE_WRIST = "WRISTSLOT",
    INVTYPE_HAND = "HANDSSLOT",
    INVTYPE_WAIST = "WAISTSLOT",
    INVTYPE_LEGS = "LEGSSLOT",
    INVTYPE_FEET = "FEETSLOT",
    INVTYPE_FINGER = "FINGER0SLOT",
    INVTYPE_TRINKET = "TRINKET0SLOT",
    INVTYPE_WEAPON = "MAINHANDSLOT",
    INVTYPE_2HWEAPON = "MAINHANDSLOT",
    INVTYPE_WEAPONMAINHAND = "MAINHANDSLOT",
    INVTYPE_SHIELD = "SECONDARYHANDSLOT",
    INVTYPE_HOLDABLE = "SECONDARYHANDSLOT",
    INVTYPE_WEAPONOFFHAND = "SECONDARYHANDSLOT",
    INVTYPE_RANGED = "RANGEDSLOT",
    INVTYPE_RANGEDRIGHT = "RANGEDSLOT",
    INVTYPE_THROWN = "RANGEDSLOT",
}

-- Ordre d'affichage, celui de la feuille de personnage du jeu.
local ORDRE = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
    "INVTYPE_CHEST", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST",
    "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
    "INVTYPE_FINGER", "INVTYPE_TRINKET",
    "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_RANGED",
}

local rang = {}
for index, code in ipairs(ORDRE) do rang[code] = index end
-- Les codes qui partagent un emplacement partagent son rang.
for code, cible in pairs(LIBELLE) do
    if not rang[code] then
        for autre, autreCible in pairs(LIBELLE) do
            if autreCible == cible and rang[autre] then
                rang[code] = rang[autre]
                break
            end
        end
    end
end

-- Code de reference de chaque emplacement : celui de la feuille de personnage
-- qui porte le meme libelle. Une robe va au torse, une arme a deux mains en
-- main droite, un fusil ou une baguette a distance.
local REFERENCE = {}
for code, cible in pairs(LIBELLE) do
    for _, ref in ipairs(ORDRE) do
        if LIBELLE[ref] == cible then REFERENCE[code] = ref break end
    end
    REFERENCE[code] = REFERENCE[code] or code
end

-- Emplacement d'un objet, ramene a son code de reference. nil si l'objet n'est
-- pas equipable ou n'est pas encore connu du client. Rendre le code brut
-- ecartait les robes, les armes a deux mains, les objets tenus en main gauche
-- et les armes a feu des candidats de leur emplacement.
function emplacements.DeLObjet(objet)
    local lecture = NS.jeu.infoObjetImmediate
    if not lecture or not objet then return nil end
    local _, _, _, code = NS.Appeler(lecture, objet)
    if type(code) ~= "string" or code == "" or code == "INVTYPE_NON_EQUIP" then return nil end
    if not LIBELLE[code] then return nil end
    return REFERENCE[code]
end

-- Libelle du jeu pour cet emplacement, ou le code brut si le jeu ne le donne pas.
function emplacements.Libelle(code)
    local nom = LIBELLE[code]
    if not nom then return code end
    local valeur = _G[nom]
    if type(valeur) == "string" and valeur ~= "" then return valeur end
    return code
end

-- Deux emplacements se comparent dans l'ordre de la feuille de personnage ;
-- ce qui n'est pas equipable passe apres tout le reste.
function emplacements.Rang(code)
    if not code then return 999 end
    return rang[code] or 998
end

-- Emplacements de la feuille de personnage, dans l'ordre et le cote de la
-- fenetre de personnage du jeu. Le nom est celui que le client attend pour
-- rendre le numero d'emplacement.
emplacements.DuPersonnage = {
    { nom = "HeadSlot",          code = "INVTYPE_HEAD",      cote = "g", libelle = "HEADSLOT" },
    { nom = "NeckSlot",          code = "INVTYPE_NECK",      cote = "g", libelle = "NECKSLOT" },
    { nom = "ShoulderSlot",      code = "INVTYPE_SHOULDER",  cote = "g", libelle = "SHOULDERSLOT" },
    { nom = "BackSlot",          code = "INVTYPE_CLOAK",     cote = "g", libelle = "BACKSLOT" },
    { nom = "ChestSlot",         code = "INVTYPE_CHEST",     cote = "g", libelle = "CHESTSLOT" },
    { nom = "ShirtSlot",         code = "INVTYPE_BODY",      cote = "g", libelle = "SHIRTSLOT" },
    { nom = "TabardSlot",        code = "INVTYPE_TABARD",    cote = "g", libelle = "TABARDSLOT" },
    { nom = "WristSlot",         code = "INVTYPE_WRIST",     cote = "g", libelle = "WRISTSLOT" },

    { nom = "HandsSlot",         code = "INVTYPE_HAND",      cote = "d", libelle = "HANDSSLOT" },
    { nom = "WaistSlot",         code = "INVTYPE_WAIST",     cote = "d", libelle = "WAISTSLOT" },
    { nom = "LegsSlot",          code = "INVTYPE_LEGS",      cote = "d", libelle = "LEGSSLOT" },
    { nom = "FeetSlot",          code = "INVTYPE_FEET",      cote = "d", libelle = "FEETSLOT" },
    { nom = "Finger0Slot",       code = "INVTYPE_FINGER",    cote = "d", libelle = "FINGER0SLOT" },
    { nom = "Finger1Slot",       code = "INVTYPE_FINGER",    cote = "d", libelle = "FINGER1SLOT" },
    { nom = "Trinket0Slot",      code = "INVTYPE_TRINKET",   cote = "d", libelle = "TRINKET0SLOT" },
    { nom = "Trinket1Slot",      code = "INVTYPE_TRINKET",   cote = "d", libelle = "TRINKET1SLOT" },

    -- Les armes en ligne sous les deux colonnes, comme la feuille de
    -- personnage du jeu.
    { nom = "MainHandSlot",      code = "INVTYPE_WEAPON",    cote = "bas", libelle = "MAINHANDSLOT" },
    { nom = "SecondaryHandSlot", code = "INVTYPE_SHIELD",    cote = "bas", libelle = "SECONDARYHANDSLOT" },
    { nom = "RangedSlot",        code = "INVTYPE_RANGED",    cote = "bas", libelle = "RANGEDSLOT" },
}

-- Libelle propre a un emplacement, qui distingue les deux doigts et les deux
-- bijoux la ou le code seul ne le ferait pas.
function emplacements.LibelleDuSlot(emplacement)
    local valeur = emplacement.libelle and _G[emplacement.libelle]
    if type(valeur) == "string" and valeur ~= "" then return valeur end
    return emplacements.Libelle(emplacement.code)
end


-- Numero d'emplacement, demande au client. nil s'il ne le connait pas.
function emplacements.Numero(nom)
    local lecture = NS.Lecture("GetInventorySlotInfo")
    if not lecture then return nil end
    local numero = NS.Appeler(lecture, nom)
    return tonumber(numero)
end
