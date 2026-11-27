local _, NS = ...

-- Travaux de fond : les grandes listes (milliers de quetes et d'objets) se
-- lisent par petits morceaux, quelques millisecondes par image, jamais tout
-- d'un coup. Chaque travail est une coroutine qui appelle travail.Pause()
-- dans ses boucles : la pause ne cede la main que si le temps de l'image est
-- ecoule. Jamais de pause a l'interieur d'un pcall (Lua 5.1 l'interdit).

NS.travail = {}
local travail = NS.travail

local file = {}          -- { cle, co, rappel }
local enCours = {}       -- [cle] = true
local cadre
local finImage = 0
local BUDGET_FOND, BUDGET_OUVERT = 2, 6   -- millisecondes par image
local compteur = 0

local function Maintenant()
    local f = _G.debugprofilestop
    if f then
        local ok, t = pcall(f)
        if ok and type(t) == "number" then return t end
    end
    return nil
end

local function Budget()
    local f = NS.fenetre and NS.fenetre.Visible and NS.fenetre.Visible()
    return f and BUDGET_OUVERT or BUDGET_FOND
end

-- Dans une boucle de travail : cede la main si l'image est pleine.
function travail.Pause()
    if not coroutine.running() then return end
    compteur = compteur + 1
    local t = Maintenant()
    if t then
        if t < finImage then return end
    elseif compteur % 300 ~= 0 then
        return
    end
    coroutine.yield()
end

local function Image()
    local t = Maintenant()
    finImage = (t or 0) + Budget()
    local garde = 0
    while #file > 0 and garde < 50 do
        garde = garde + 1
        local j = file[1]
        local ok, souci = coroutine.resume(j.co)
        if not ok then
            NS.base.NoterIncident("travail " .. tostring(j.cle), souci)
            table.remove(file, 1)
            enCours[j.cle] = nil
            if j.echec then NS.Proteger("echec " .. tostring(j.cle), j.echec, souci) end
        elseif coroutine.status(j.co) == "dead" then
            table.remove(file, 1)
            enCours[j.cle] = nil
            if j.rappel then NS.Proteger("rappel " .. tostring(j.cle), j.rappel) end
        else
            -- Image pleine : la suite a la prochaine.
            local t2 = Maintenant()
            if not t2 or t2 >= finImage then break end
        end
    end
    if #file == 0 and cadre then cadre:SetScript("OnUpdate", nil) end
end

-- Lance un travail (une seule fois par cle tant qu'il tourne). `echec` :
-- appele si le travail s'arrete sur une erreur (il n'est pas relance).
function travail.Lancer(cle, fn, rappel, echec)
    if enCours[cle] then return false end
    enCours[cle] = true
    table.insert(file, { cle = cle, co = coroutine.create(fn), rappel = rappel, echec = echec })
    if not cadre then cadre = CreateFrame("Frame") end
    cadre:SetScript("OnUpdate", Image)
    return true
end

function travail.EnCours(cle) return enCours[cle] == true end

-- Pour les essais hors du jeu : tout finir d'un coup.
function travail.ToutFinir()
    local garde = 0
    while #file > 0 and garde < 100000 do
        garde = garde + 1
        finImage = math.huge
        Image()
    end
end
