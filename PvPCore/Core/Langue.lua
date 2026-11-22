local _, NS = ...

-- Langue de PvPCore : francais et anglais dans le code (T(fr, en)). La
-- langue est celle de la suite (reglages generaux), sinon celle du jeu.

local function Langue()
    local S = _G.CoreSuite
    if S and S.Langue then return S.Langue() end
    return (GetLocale and GetLocale()) or "enUS"
end

function NS.T(fr, en)
    if Langue() == "frFR" then return fr end
    return en or fr
end
