local _, NS = ...

-- Les maitres de classe (et de familiers) : le plus proche du personnage,
-- sur son continent. Avec MapCore, on le montre sur sa carte ; sinon, le
-- guidage de la suite y mene (une fleche, la distance).

NS.maitres = {}
local M = NS.maitres
local T = NS.T

local function S() return _G.CoreSuite end

local function Lettre()
    local ok, camp = pcall(UnitFactionGroup, "player")
    camp = ok and camp or nil
    return camp == "Alliance" and "A" or (camp == "Horde" and "H" or nil)
end

-- { carte, x (0-1), y (0-1), nom, zone } ou nil.
function M.PlusProche(classe)
    local Lx = S() and S().Lieux
    if not (Lx and Lx.Ici and Lx.Monde and NS.MAITRES and classe) then return nil end
    local ici = Lx.Ici()
    if not (ici and ici.wx) then return nil end
    local lettre = Lettre()
    local meilleur, cible
    for carte, liste in pairs(NS.MAITRES) do
        for _, e in ipairs(liste) do
            local fac = e[5] or ""
            if e[1] == classe and (fac == "" or not lettre or fac:find(lettre, 1, true)) then
                local x, y = (tonumber(e[2]) or 0) / 100, (tonumber(e[3]) or 0) / 100
                local wx, wy, c = Lx.Monde(carte, x, y)
                if wx and c == ici.continent then
                    local d = (wx - ici.wx) ^ 2 + (wy - ici.wy) ^ 2
                    if not meilleur or d < meilleur then
                        meilleur = d
                        cible = { carte = carte, x = x, y = y, nom = e[4], distance = math.sqrt(d) }
                    end
                end
            end
        end
    end
    if cible and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, cible.carte)
        cible.zone = ok and type(info) == "table" and info.name or nil
    end
    return cible
end

function M.AvecMapCore()
    local api = _G.MapCoreAPI
    return type(api) == "table" and type(api.Montrer) == "function"
end

-- Sur la carte de MapCore.
function M.Montrer(pt)
    local api = _G.MapCoreAPI
    if not (pt and api and api.Montrer) then return end
    if api.Ouvrir then pcall(api.Ouvrir) end
    pcall(api.Montrer, { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.nom, icone = "Interface\\Minimap\\Tracking\\Class" })
end

-- Le guidage de la suite (objectif "maitre", par classe).
local TYPE = {
    icone = "Interface\\Minimap\\Tracking\\Class",
    Cle = function(p) return tostring(p.classe) end,
    Libelle = function(p) return p.classe == "PET" and T("Maître des familiers", "Pet trainer") or T("Maître de classe", "Class trainer") end,
    Preparer = function(p, etat)
        local pt = M.PlusProche(p.classe)
        if not pt then
            print("|cffffd100ClassCore|r " .. T("Aucun maître connu sur ce continent.", "No known trainer on this continent."))
            return false
        end
        etat.point = { carte = pt.carte, x = pt.x, y = pt.y, nom = pt.nom }
        return true
    end,
    Reprendre = function(p, etat) return type(etat.point) == "table" and etat.point.carte ~= nil end,
    Etapes = function(p, etat)
        local pt = etat.point
        if type(pt) ~= "table" then return nil, "atteint" end
        local quoi = p.classe == "PET" and T("Maître des familiers", "Pet trainer") or T("Maître de classe", "Class trainer")
        return { { carte = pt.carte, x = pt.x, y = pt.y, titre = quoi, guidage = quoi,
            qui = tostring(pt.nom or "?") .. "\n|cffb3b3b3" .. quoi .. "|r", cle = "maitre" } }
    end,
    Arrivee = function() return "atteint" end,
}

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if S() and S().DeclarerObjectifs then pcall(S().DeclarerObjectifs, "ClassCore", { maitre = TYPE }) end
    end)
end

function M.EstGuide(classe) return S() and S().EstActif and S().EstActif("ClassCore", "maitre", { classe = classe }) or false end
function M.Basculer(classe)
    if not (S() and S().BasculerObjectif) then return end
    if S().DeclarerObjectifs then pcall(S().DeclarerObjectifs, "ClassCore", { maitre = TYPE }) end
    pcall(S().BasculerObjectif, "ClassCore", "maitre", { classe = classe })
end
