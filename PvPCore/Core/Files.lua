local _, NS = ...

-- Les files d'attente : quand un champ de bataille est pret, une ligne dans
-- votre discussion (visible de vous seul) dit combien de temps il reste pour
-- entrer, puis un rappel sonore 15 secondes avant la fin. Rien n'est clique
-- pour vous : vous entrez avec la fenetre du jeu.

NS.files = {}
local F = NS.files
local T = NS.T
local RAPPEL = 15

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) or false end
local function Nombre(v) if Secret(v) then return nil end return tonumber(v) end

local vus = {}   -- statut connu de chaque file
local tour = 0   -- change a chaque nouvelle invitation : un rappel perime ne dit rien

local function Rappel(i, cle)
    if vus[i] ~= cle then return end
    local statut = NS.Appeler(NS.Lecture("GetBattlefieldStatus"), i)
    if statut ~= "confirm" then return end
    local reste = Nombre(NS.Appeler(NS.Lecture("GetBattlefieldPortExpiration"), i)) or 0
    if reste <= 0 then return end
    local _, nom = NS.Appeler(NS.Lecture("GetBattlefieldStatus"), i)
    NS.Dire(string.format(T("%s : plus que %d s pour entrer.", "%s : only %d s left to enter."), tostring(nom or "?"), math.floor(reste)))
    if _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING then pcall(_G.PlaySound, _G.SOUNDKIT.RAID_WARNING) end
end

function F.Verifier()
    local lire = NS.Lecture("GetBattlefieldStatus")
    if not lire then return end
    local maxi = Nombre(NS.Appeler(NS.Lecture("GetMaxBattlefieldID"))) or 0
    for i = 1, math.min(maxi, 5) do
        local statut, nom = NS.Appeler(lire, i)
        if statut == "confirm" then
            if not (vus[i] and vus[i]:find("^confirm")) then
                tour = tour + 1
                local cle = "confirm" .. tour
                vus[i] = cle
                local reste = Nombre(NS.Appeler(NS.Lecture("GetBattlefieldPortExpiration"), i)) or 0
                if NS.victoires.Reglages().files ~= false and reste > 0 then
                    NS.Dire(string.format(T("%s est prêt : %d s pour entrer.", "%s is ready : %d s to enter."), tostring(nom or "?"), math.floor(reste)))
                    if reste > RAPPEL and _G.C_Timer and _G.C_Timer.After then
                        pcall(_G.C_Timer.After, reste - RAPPEL, function() pcall(Rappel, i, cle) end)
                    end
                end
            end
        else
            vus[i] = statut
        end
    end
end

local cadre = CreateFrame("Frame")
F.cadre = cadre
pcall(cadre.RegisterEvent, cadre, "UPDATE_BATTLEFIELD_STATUS")
cadre:SetScript("OnEvent", function()
    local ok, souci = pcall(F.Verifier)
    if not ok then NS.base.NoterIncident("files", souci) end
end)
