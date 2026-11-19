local _, NS = ...

-- Infobulle d'un objet : les quetes en cours (de tous les personnages) qui
-- le demandent, avec la progression de chacune.

NS.infobulles = {}
local L = NS.L
local dejaMis = {}

local function ObjetDe(tooltip, donnees)
    if donnees and donnees.id then return donnees.id end
    if tooltip.GetItem then
        local _, lien = tooltip:GetItem()
        local id = lien and tonumber(string.match(lien, "item:(%d+)"))
        return id
    end
end

local function Ajouter(tooltip, donnees)
    if not tooltip or dejaMis[tooltip] then return end
    local objet = ObjetDe(tooltip, donnees)
    if not objet then return end
    local courant = NS.ClePersonnage()
    local lignes = {}
    for _, b in ipairs(NS.ref.Besoins()) do
        if b.objet == objet then
            local nom = NS.ref.NomDeQuete(b.quete, b.perso)
            if b.cle == courant then
                table.insert(lignes, string.format(L.TIP_QUEST, nom) .. string.format(" (%d/%d)", b.n, b.requis))
            else
                table.insert(lignes, string.format(L.TIP_QUEST_OTHER, NS.NomCourt(b.cle), nom, b.n, b.requis))
            end
        end
    end
    if #lignes == 0 then return end
    dejaMis[tooltip] = true
    tooltip:AddLine(" ")
    for _, ligne in ipairs(lignes) do tooltip:AddLine(ligne, 1, 0.82, 0) end
    if tooltip.Show then tooltip:Show() end
end

local function SansRisque(tooltip, donnees)
    local ok, souci = pcall(Ajouter, tooltip, donnees)
    if not ok then NS.base.NoterIncident("infobulle", souci) end
end

function NS.infobulles.Installer()
    local processeur = _G.TooltipDataProcessor
    local types = _G.Enum and _G.Enum.TooltipDataType
    local viaProcesseur = false
    if processeur and processeur.AddTooltipPostCall and types and types.Item then
        viaProcesseur = pcall(processeur.AddTooltipPostCall, types.Item, SansRisque)
    end
    for _, tooltip in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            if not viaProcesseur then
                pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self) SansRisque(self) end)
            end
            local function Oublier(self) dejaMis[self] = nil end
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", Oublier)
            pcall(tooltip.HookScript, tooltip, "OnHide", Oublier)
        end
    end
end
