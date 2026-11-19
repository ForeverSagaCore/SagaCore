-- Langue : l'anglais (enUS.lua) sert de base ; chaque fichier de langue se
-- range dans NS.LANGUES. On applique celle du jeu tout de suite, puis celle
-- choisie dans les reglages generaux de la suite des que les reglages sont
-- charges. NS.L reste la meme table : les textes changent en place.
local nom, NS = ...

local base = {}
for cle, texte in pairs(NS.L) do base[cle] = texte end

local CORRESPONDANCE = { esMX = "esES", zhTW = "zhCN", enGB = "enUS" }
local function Code(code)
    code = code or (GetLocale and GetLocale()) or "enUS"
    return CORRESPONDANCE[code] or code
end

function NS.AppliquerLangue(code)
    code = Code(code)
    local L = NS.L
    for cle in pairs(L) do if base[cle] == nil then L[cle] = nil end end
    for cle, texte in pairs(base) do L[cle] = texte end
    local t = NS.LANGUES and NS.LANGUES[code]
    if t then for cle, texte in pairs(t) do L[cle] = texte end end
    NS.langue = (t or code == "enUS") and code or "enUS"
end

NS.AppliquerLangue()

local veille = CreateFrame("Frame")
veille:RegisterEvent("ADDON_LOADED")
veille:SetScript("OnEvent", function(self, _, qui)
    if qui ~= nom then return end
    self:UnregisterEvent("ADDON_LOADED")
    local choix = type(CoreSuiteDB) == "table" and CoreSuiteDB.langue or nil
    if choix and Code(choix) ~= NS.langue then NS.AppliquerLangue(choix) end
end)
