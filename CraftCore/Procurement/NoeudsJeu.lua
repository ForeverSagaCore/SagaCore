local _, NS = ...

-- Noeuds de recolte d'apres la base du jeu (QuestieDB, si elle est la) : dans
-- quelles zones une matiere se recolte. Rien n'est affiche ni guide d'apres
-- cette base : elle sert seulement a dire au joueur qu'une matiere existe
-- dans sa zone alors qu'il n'y a encore rien releve.

NS.noeudsJeu = {}
local noeudsJeu = NS.noeudsJeu

-- Secours, si ItemDB n'a pas d'objectDrops pour une matiere : les noeuds
-- (identifiants ObjectDB) qui la donnent. Vide tant que ce n'est pas verifie
-- en jeu.
local NOEUDS = {}

local presence = {}

-- Les zones (cartes de type zone) ou la matiere se recolte, { [zone] = true },
-- ou false si la base n'en sait rien. Garde pour la session.
function noeudsJeu.Presence(objet)
    objet = tonumber(objet)
    if not objet then return false end
    if presence[objet] ~= nil then return presence[objet] end
    local m = NS.marchands
    local S = NS.suite or _G.CoreSuite
    if not (m and m.Lire and m.CarteDeZone and S and S.Lieux) then return false end
    local zones = false
    local liste = m.Lire("ItemDB", objet, "objectDrops")
    if type(liste) ~= "table" or #liste == 0 then liste = NOEUDS[objet] end
    for _, ob in ipairs(type(liste) == "table" and liste or {}) do
        local spawns = m.Lire("ObjectDB", ob, "spawns")
        for area, pts in pairs(type(spawns) == "table" and spawns or {}) do
            local carte = m.CarteDeZone(area)
            local z = carte and S.Lieux.ZoneDe(carte)
            if z and type(pts) == "table" and #pts > 0 then
                zones = zones or {}
                zones[z] = true
            end
        end
    end
    presence[objet] = zones
    return zones
end
