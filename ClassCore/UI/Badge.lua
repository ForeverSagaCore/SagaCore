local _, NS = ...

-- La pastille de classe, sous le portrait du personnage : ce qu'il faut
-- avoir sur soi (fragments d'ame, munitions, runes, ankhs...) ou, pour le
-- druide, le nombre de changements de forme que la mana permet encore (hors
-- combat). Rouge sous le seuil conseille. Le survol donne le detail.
-- Rien d'autre : pas de clic, pas de touche, aucune action du jeu.

NS.badge = {}
local B = NS.badge
local T = NS.T
local E = function() return NS.etat end

local cadre

function B.Reglages()
    local g = NS.base.ReglagesGeneraux()
    if g.badge == nil then g.badge = true end
    return g
end

local function Entrees()
    local classe = E().Classe()
    local d = E().Donnees(classe)
    local niveau = E().Niveau()
    local res = {}
    for _, b in ipairs(d.badge or {}) do
        if b.genre == "objet" and niveau >= (b.niveau or 1) then
            local n = E().Compte(b.id)
            local _, icone = E().Objet(b.id)
            local seuil
            for _, o in ipairs(d.objets or {}) do if o.id == b.id then seuil = o.seuil end end
            table.insert(res, { icone = icone, texte = tostring(n), bas = seuil and seuil > 0 and n < seuil })
        elseif b.genre == "munitions" then
            local n, icone = E().Munitions()
            if n then table.insert(res, { icone = icone or "Interface\\Icons\\INV_Ammo_Arrow_02", texte = tostring(n), bas = n < 200 }) end
        elseif b.genre == "formes" and niveau >= 10 then
            local n = E().FormesRestantes()
            local icone = select(2, E().Sort(768)) or select(2, E().Sort(5487))
            table.insert(res, { icone = icone, texte = n and tostring(n) or "-", bas = n ~= nil and n < 1 })
        end
    end
    return res
end

local function Infobulle(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("ClassCore")
    local classe = E().Classe()
    local niveau = E().Niveau()
    if classe == "DRUID" then
        local n = E().FormesRestantes()
        GameTooltip:AddLine(n and string.format(T("Changements de forme possibles : %d", "Shapeshifts left : %d"), n)
            or T("Changements de forme : affichés hors combat", "Shapeshifts : shown out of combat"), 1, 1, 1)
    elseif classe == "HUNTER" then
        local n = E().Munitions()
        if n then GameTooltip:AddLine(string.format(T("Munitions équipées : %d", "Equipped ammo : %d"), n), 1, 1, 1) end
        local f = E().Familier()
        if f and f.bonheur then
            local h = ({ T("Malheureux", "Unhappy"), T("Content", "Content"), T("Heureux", "Happy") })[f.bonheur]
            if h then GameTooltip:AddLine(string.format(T("Familier : %s", "Pet : %s"), h), 1, 1, 1) end
        end
    end
    for _, o in ipairs(E().ObjetsUtiles(classe, niveau)) do
        local nom = E().Objet(o.id)
        if nom then
            local sacs, banque = E().Compte(o.id)
            local droite = banque > 0 and string.format(T("%d (+%d en banque)", "%d (+%d in bank)"), sacs, banque) or tostring(sacs)
            local bas = (o.seuil or 0) > 0 and sacs < o.seuil
            GameTooltip:AddDoubleLine(nom, droite, 1, 1, 1, bas and 1 or 1, bas and 0.3 or 1, bas and 0.3 or 1)
        end
    end
    GameTooltip:Show()
end

local function Construire()
    if cadre then return cadre end
    local parent = _G.PlayerFrame or UIParent
    cadre = CreateFrame("Frame", "ClassCoreBadge", UIParent)
    cadre:SetSize(40, 20)
    cadre:SetFrameStrata("LOW")
    cadre:EnableMouse(true)
    cadre:SetScript("OnEnter", Infobulle)
    cadre:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cadre.cases = {}
    cadre.parent = parent
    return cadre
end

local function Poser()
    local c = Construire()
    c:ClearAllPoints()
    local p = c.parent
    if p and p ~= UIParent then
        c:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 46, 18)
    else
        c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -110)
    end
end

local function Case(i)
    local c = cadre.cases[i]
    if c then return c end
    c = CreateFrame("Frame", nil, cadre)
    c:SetSize(44, 20)
    c.bord = CreateFrame("Frame", nil, c)
    c.bord:SetSize(18, 18)
    c.bord:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.icone = c.bord:CreateTexture(nil, "ARTWORK")
    c.icone:SetPoint("TOPLEFT", c.bord, "TOPLEFT", 1, -1)
    c.icone:SetPoint("BOTTOMRIGHT", c.bord, "BOTTOMRIGHT", -1, 1)
    c.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- L'encadrement des icones du jeu (boutons d'action, grimoire).
    do local S = _G.CoreSuite if S and S.HabillerIcone then pcall(S.HabillerIcone, c.bord, c.icone) end end
    c.texte = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.texte:SetPoint("LEFT", c.bord, "RIGHT", 4, 0)
    c.texte:SetWordWrap(false)
    c:EnableMouse(false)
    cadre.cases[i] = c
    return c
end

function B.Actualiser()
    if not B.Reglages().badge then if cadre then cadre:Hide() end return end
    local ok, liste = pcall(Entrees)
    if not ok or #liste == 0 then if cadre then cadre:Hide() end return end
    Construire()
    local x = 0
    for i, e in ipairs(liste) do
        local c = Case(i)
        c:ClearAllPoints()
        c:SetPoint("LEFT", cadre, "LEFT", x, 0)
        c.icone:SetTexture(e.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.texte:SetText(e.texte)
        if e.bas then c.texte:SetTextColor(1, 0.3, 0.3) else c.texte:SetTextColor(1, 1, 1) end
        local l = 22 + math.ceil(c.texte:GetStringWidth() or 12) + 6
        c:SetWidth(l)
        c:Show()
        x = x + l
    end
    for i = #liste + 1, #cadre.cases do cadre.cases[i]:Hide() end
    cadre:SetWidth(math.max(x, 20))
    cadre:Show()
end

do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_LEVEL_UP",
        "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_PET", "UNIT_HAPPINESS",
        "GET_ITEM_INFO_RECEIVED", "SPELLS_CHANGED" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    local attente = 0
    f:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGIN" then Poser() end
        attente = 0.2
    end)
    -- Druide : la mana bouge sans evenement de sac ; une lecture par seconde.
    local tic = 0
    f:SetScript("OnUpdate", function(_, ecoule)
        tic = tic + (ecoule or 0)
        if attente > 0 then
            attente = attente - (ecoule or 0)
            if attente <= 0 then pcall(B.Actualiser) end
        elseif tic >= 1 then
            tic = 0
            if E().Classe() == "DRUID" then pcall(B.Actualiser) end
        end
    end)
end
