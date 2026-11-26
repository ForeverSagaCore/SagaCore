local _, NS = ...

-- Ce que ClassCore lit du jeu : la classe, la race et le camp du personnage,
-- les sorts qu'il connait, les objets qu'il a sur lui et en banque. Rien
-- n'est calcule a partir d'une valeur secrete (en combat, sur Forever) :
-- chaque lecture le verifie et rend nil.

NS.etat = {}
local E = NS.etat

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
E.Secret = Secret

function E.Classe()
    local ok, _, fichier = pcall(UnitClass, "player")
    return ok and fichier or nil
end

function E.Race()
    local ok, _, _, id = pcall(UnitRace, "player")
    return ok and tonumber(id) or nil
end

function E.Camp()
    local ok, camp = pcall(UnitFactionGroup, "player")
    return ok and camp or nil
end

function E.Niveau()
    local ok, n = pcall(UnitLevel, "player")
    if not ok or Secret(n) then return 1 end
    return tonumber(n) or 1
end

-- Sorts : nom et icone dans la langue du jeu ; nil si le jeu ne le connait pas.
function E.Sort(id)
    local C = _G.C_Spell
    if C and C.GetSpellInfo then
        local ok, info = pcall(C.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then return info.name, info.iconID or info.originalIconID end
    end
    if _G.GetSpellInfo then
        local ok, nom, _, icone = pcall(_G.GetSpellInfo, id)
        if ok and nom then return nom, icone end
    end
    return nil
end

function E.SortConnu(id)
    for _, f in ipairs({ _G.IsPlayerSpell, _G.C_SpellBook and _G.C_SpellBook.IsSpellKnown, _G.IsSpellKnown }) do
        if type(f) == "function" then
            local ok, oui = pcall(f, id)
            if ok and oui == true then return true end
        end
    end
    return false
end

-- Objets : nom, icone et qualite ; demande au jeu de les charger s'ils ne
-- sont pas encore connus (la fenetre se redessine quand ils arrivent).
local demandes = {}
function E.Objet(id)
    local I = _G.C_Item
    local nom, _, qualite, _, _, _, _, _, _, icone
    if I and I.GetItemInfo then
        local ok, a, b, c, d, e, f, g, h, i, j = pcall(I.GetItemInfo, id)
        if ok then nom, qualite, icone = a, c, j end
    end
    if not nom and _G.GetItemInfo then
        local ok, a, b, c, d, e, f, g, h, i, j = pcall(_G.GetItemInfo, id)
        if ok then nom, qualite, icone = a, c, j end
    end
    if not icone then
        local f = (I and I.GetItemIconByID) or _G.GetItemIcon
        if f then local ok, ic = pcall(f, id) if ok then icone = ic end end
    end
    if not nom and not demandes[id] then
        demandes[id] = true
        if I and I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
    end
    return nom, icone, qualite
end

-- Combien sur soi, et combien en banque en plus.
function E.Compte(id)
    local I = _G.C_Item
    local f = (I and I.GetItemCount) or _G.GetItemCount
    if not f then return 0, 0 end
    local ok1, sacs = pcall(f, id, false)
    local ok2, tout = pcall(f, id, true)
    sacs = (ok1 and not Secret(sacs) and tonumber(sacs)) or 0
    tout = (ok2 and not Secret(tout) and tonumber(tout)) or sacs
    return sacs, math.max(0, tout - sacs)
end

-- Les munitions equipees (chasseur), ou nil.
function E.Munitions()
    local okS, place = pcall(GetInventorySlotInfo, "AmmoSlot")
    if not okS or not place then return nil end
    local okI, id = pcall(GetInventoryItemID, "player", place)
    if not okI or not id then return 0, nil end
    local okC, n = pcall(GetInventoryItemCount, "player", place)
    if not okC or Secret(n) then return nil end
    local _, icone = E.Objet(id)
    return tonumber(n) or 0, icone
end

-- Druide en forme : combien de changements de forme la mana permet encore.
-- Seulement hors combat (la mana est secrete en combat sur Forever).
function E.FormesRestantes()
    if InCombatLockdown and InCombatLockdown() then return nil end
    local okM, mana = pcall(UnitPower, "player", 0)
    if not okM or Secret(mana) then return nil end
    local cout
    local C = _G.C_Spell
    local f = (C and C.GetSpellPowerCost) or _G.GetSpellPowerCost
    if f then
        local id = E.SortConnu(768) and 768 or (E.SortConnu(9634) and 9634) or (E.SortConnu(5487) and 5487) or nil
        if not id then return nil end
        local ok, couts = pcall(f, id)
        if ok and type(couts) == "table" then
            for _, c in ipairs(couts) do
                if (c.type == 0 or c.name == "MANA") and tonumber(c.cost) and not Secret(c.cost) then cout = tonumber(c.cost) end
            end
        end
    end
    if not cout or cout <= 0 then return nil end
    return math.floor((tonumber(mana) or 0) / cout)
end

-- Le familier (chasseur) : bonheur (1 a 3), loyaute, points de dressage.
function E.Familier()
    local okE, existe = pcall(UnitExists, "pet")
    if not okE or not existe then return nil end
    local f = {}
    local okN, nom = pcall(UnitName, "pet")
    if okN and not Secret(nom) then f.nom = nom end
    if _G.GetPetHappiness then
        local ok, h = pcall(_G.GetPetHappiness)
        if ok and not Secret(h) then f.bonheur = tonumber(h) end
    end
    if _G.GetPetLoyalty then
        local ok, l = pcall(_G.GetPetLoyalty)
        if ok and type(l) == "string" then f.loyaute = l end
    end
    if _G.GetPetTrainingPoints then
        local ok, total, depenses = pcall(_G.GetPetTrainingPoints)
        if ok and tonumber(total) and not Secret(total) then f.points = (tonumber(total) or 0) - (tonumber(depenses) or 0) end
    end
    if _G.GetPetFoodTypes then
        local ok, a, b, c, d, e2, g = pcall(_G.GetPetFoodTypes)
        if ok then f.regime = { a, b, c, d, e2, g } end
    end
    local okF, famille = pcall(UnitCreatureFamily, "pet")
    if okF and not Secret(famille) then f.famille = famille end
    local okL, niv = pcall(UnitLevel, "pet")
    if okL and not Secret(niv) then f.niveau = tonumber(niv) end
    return f
end

-- Les donnees de la classe du personnage.
function E.Donnees(classe)
    return NS.classes.donnees[classe or E.Classe() or ""] or { objets = {}, sorts = {} }
end

-- Un sort est-il pour ce camp ?
function E.PourLeCamp(s, camp)
    if not s.camp then return true end
    return (camp == "Alliance" and s.camp == "A") or (camp == "Horde" and s.camp == "H")
end

-- Les objets de classe qui servent a ce niveau.
function E.ObjetsUtiles(classe, niveau)
    local res = {}
    for _, o in ipairs(E.Donnees(classe).objets or {}) do
        if niveau >= (o.niveau or 1) and (not o.jusqua or niveau <= o.jusqua) then table.insert(res, o) end
    end
    return res
end
