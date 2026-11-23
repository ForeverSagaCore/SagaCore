local _, NS = ...

-- Guidage de MapCore : le catalogue de ses objectifs, declare au moteur de la
-- suite (Core/Suite.lua).
--   tournee {}                         la tournee de recolte, en boucle :
--                                      seul le joueur l'arrete ;
--   service { carte, x, y, nom }       un point de la carte, atteint a
--                                      l'arrivee.

local function S() return NS.suite or _G.CoreSuite end
local page = NS.pageCarte

local TYPES = {}

TYPES.tournee = {
    icone = "Interface\\Icons\\INV_Misc_Map_01",
    AideClic = function() return NS.L and NS.L.FARM_CLICK end,
    Libelle = function()
        local t = page.Tournee()
        local info = t.carte and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), t.carte)
        local titre = NS.L and NS.L.FARM_TITLE or "?"
        if type(info) == "table" and info.name then return titre .. " (" .. info.name .. ")" end
        return titre
    end,
    Preparer = function(p, etat)
        local t = page.Tournee()
        if not t.carte or #t.points == 0 then return false end
        etat.faits, etat.chaine = {}, {}
        return true
    end,
    Etapes = function(p, etat)
        etat.faits = type(etat.faits) == "table" and etat.faits or {}
        etat.chaine = type(etat.chaine) == "table" and etat.chaine or {}
        local t = page.Tournee()
        if not t.carte or #t.points == 0 then return nil, "inconnu" end
        local Lx = S().Lieux
        local ici = Lx.Ici()
        local cc = _G.CraftCoreAPI
        for passe = 1, 2 do
            local reste = {}
            for _, pt in ipairs(t.points) do
                local cle = page.CleLieu(pt)
                if not etat.faits[cle] then
                    local wx, wy = Lx.Monde(t.carte, pt.x, pt.y)
                    local nom = cc and cc.Objet and cc.Objet(pt.objet)
                    table.insert(reste, { carte = t.carte, x = pt.x, y = pt.y, wx = wx, wy = wy, cle = cle,
                        qui = nom, titre = NS.L and NS.L.FARM_TITLE })
                end
            end
            if #reste > 0 then
                local ordre = Lx.Chaine(reste, (ici and ici.wx) and ici or nil, nil, etat.chaine)
                local fait = 0
                for _ in pairs(etat.faits) do fait = fait + 1 end
                return ordre, nil, nil, { fait = fait, total = #t.points }
            end
            -- Tous visites : un nouveau tour (les noeuds repoussent).
            etat.faits = {}
        end
        return nil, "inconnu"
    end,
    Arrivee = function(p, etat, etape)
        etat.faits = type(etat.faits) == "table" and etat.faits or {}
        if etape and etape.cle then etat.faits[etape.cle] = true end
        pcall(page.Rendre)
        return "suivante"
    end,
    Clic = function() if NS.fenetre and NS.fenetre.Basculer then NS.fenetre.Basculer() end end,
    Fin = function() pcall(page.Rendre) end,
}

TYPES.service = (function()
    local t = S().TypePoint({
        icone = "Interface\\Icons\\INV_Misc_Map_01",
        Clic = function() if NS.fenetre and NS.fenetre.Basculer then NS.fenetre.Basculer() end end,
        Fin = function() pcall(page.Rendre) end,
    })
    local Etapes = t.Etapes
    t.Etapes = function(p, etat)
        local e = Etapes(p, etat)
        e[1].titre = NS.L and NS.L.GO_TITLE or p.nom
        e[1].guidage = p.nom
        return e
    end
    return t
end)()

S().DeclarerObjectifs("MapCore", TYPES)
