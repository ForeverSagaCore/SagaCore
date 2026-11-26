local _, NS = ...

-- Les arbres de talents, dans ClassCore : les trois arbres de la classe
-- cote a cote, chaque talent a sa place (rang, colonne) avec l'encadrement
-- des icones du jeu et ses points. Les points de chaque arbre disent la
-- specialisation. Lecture seule : on regarde, rien n'est appris ici.
-- Le personnage connecte est lu en direct ; les autres, d'apres leur
-- derniere connexion avec ClassCore.

NS.talents = {}
local Ta = NS.talents
local T = NS.T

local TAILLE = 30
local PAS_X, PAS_Y = 50, 46

-- ---------------------------------------------------------------------------
-- Lecture (personnage connecte) et releve
-- ---------------------------------------------------------------------------

local function Appel(nom, ...)
    local f = _G[nom]
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 20)
end

local function Groupe()
    local g = Appel("GetActiveTalentGroup")
    return tonumber(g) or 1
end

-- { { nom, icone, points, talents = { { nom, icone, rangee, colonne, rang, max, index } } } }
function Ta.Lire()
    local n = tonumber(Appel("GetNumTalentTabs")) or 0
    local arbres = {}
    local groupe = Groupe()
    for tab = 1, n do
        local a, b, c, d, e = Appel("GetTalentTabInfo", tab, false, false, groupe)
        local nom, icone, points
        if type(a) == "number" and type(b) == "string" then
            -- id, nom, description, icone, points
            nom, icone, points = b, d, e
        else
            nom, icone, points = a, b, c
        end
        local arbre = { nom = nom, icone = icone, points = tonumber(points) or 0, talents = {} }
        local nt = tonumber(Appel("GetNumTalents", tab, false, false)) or 0
        for i = 1, nt do
            local tn, ti, rangee, colonne, rang, max = Appel("GetTalentInfo", tab, i, false, false, groupe)
            if tn then
                table.insert(arbre.talents, { nom = tn, icone = ti, rangee = tonumber(rangee) or 1, colonne = tonumber(colonne) or 1,
                    rang = tonumber(rang) or 0, max = tonumber(max) or 1, index = i })
            end
        end
        table.insert(arbres, arbre)
    end
    return arbres
end

function Ta.Releve()
    local cle = NS.ClePersonnage()
    if not cle then return end
    local arbres = Ta.Lire()
    if #arbres == 0 then return end
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.persos = type(ClassCoreDB.persos) == "table" and ClassCoreDB.persos or {}
    local p = ClassCoreDB.persos[cle] or {}
    ClassCoreDB.persos[cle] = p
    p.talents = arbres
end

-- Les arbres du profil montre : en direct pour le connecte.
function Ta.Arbres(profil)
    if not profil then return {} end
    if profil.connecte then return Ta.Lire() end
    local p = NS.quetes.Persos()[profil.cle or ""]
    return type(p) == "table" and type(p.talents) == "table" and p.talents or {}
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

local function Bouton(page, i)
    page.talents = page.talents or {}
    local b = page.talents[i]
    if b then return b end
    b = CreateFrame("Button", nil, page.zone)
    b:SetSize(TAILLE, TAILLE)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    local S = _G.CoreSuite
    if S and S.HabillerIcone then pcall(S.HabillerIcone, b, b.icone) end
    b.rang = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.rang:SetPoint("TOPLEFT", b, "BOTTOMRIGHT", -12, 4)
    b.rang:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = false
        if self.direct and GameTooltip.SetTalent then ok = pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index) end
        if not ok or GameTooltip:NumLines() == 0 then
            GameTooltip:AddLine(self.t.nom or "")
            GameTooltip:AddLine(string.format(T("Rang %d sur %d", "Rank %d of %d"), self.t.rang, self.t.max), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- Choisi a la manette : son infobulle s'affiche. Rien d'autre.
    b:SetScript("OnClick", function() end)
    page.talents[i] = b
    return b
end

local function Rendre(page, profil)
    local zone = page.zone
    local largeur = zone:GetWidth() or 800
    for _, b in ipairs(page.talents or {}) do b:Hide() end
    for _, t in ipairs(page.titresArbres or {}) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
    if page.vide then page.vide:Hide() end
    local arbres = Ta.Arbres(profil)
    if #arbres == 0 then
        page.vide = page.vide or zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        page.vide:ClearAllPoints()
        page.vide:SetPoint("TOPLEFT", zone, "TOPLEFT", 16, 0)
        page.vide:SetText(T("Connecte ce personnage une fois pour relever ses talents.", "Log in this character once to read its talents."))
        page.vide:SetTextColor(0.55, 0.55, 0.55)
        page.vide:Show()
        return 30
    end
    page.titresArbres = page.titresArbres or {}
    local colonneL = math.floor(largeur / #arbres)
    local n, hauteur = 0, 0
    for k, a in ipairs(arbres) do
        local x0 = (k - 1) * colonneL
        local t = page.titresArbres[k]
        if not t then
            t = { fs = zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = zone:CreateTexture(nil, "ARTWORK"),
                  droite = zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
            t.fs:SetJustifyH("LEFT") t.fs:SetWordWrap(false)
            t.droite:SetJustifyH("RIGHT") t.droite:SetWordWrap(false)
            page.titresArbres[k] = t
        end
        t.fs:ClearAllPoints()
        t.fs:SetPoint("TOPLEFT", zone, "TOPLEFT", x0, 0)
        t.fs:SetWidth(colonneL - 90)
        t.fs:SetText(a.nom or "")
        t.droite:ClearAllPoints()
        t.droite:SetPoint("TOPRIGHT", zone, "TOPLEFT", x0 + colonneL - 16, -3)
        t.droite:SetWidth(80)
        t.droite:SetText(string.format(a.points == 1 and T("%d point", "%d point") or T("%d points", "%d points"), a.points or 0))
        t.filet:ClearAllPoints()
        t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
        t.filet:SetSize(colonneL - 16, 1)
        if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet) end
        t.fs:Show() t.filet:Show() t.droite:Show()
        -- Quatre colonnes de talents, centrees dans la colonne de l'arbre.
        local xGrille = x0 + math.floor((colonneL - 16 - (3 * PAS_X + TAILLE)) / 2)
        for _, ta in ipairs(a.talents or {}) do
            n = n + 1
            local b = Bouton(page, n)
            b:ClearAllPoints()
            local y = 36 + (ta.rangee - 1) * PAS_Y
            b:SetPoint("TOPLEFT", zone, "TOPLEFT", xGrille + (ta.colonne - 1) * PAS_X, -y)
            b.icone:SetTexture(ta.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icone:SetDesaturated((ta.rang or 0) == 0)
            b.rang:SetText(string.format("%d/%d", ta.rang or 0, ta.max or 1))
            if (ta.rang or 0) >= (ta.max or 1) then b.rang:SetTextColor(1, 0.82, 0)
            elseif (ta.rang or 0) > 0 then b.rang:SetTextColor(0.31, 0.82, 0.41)
            else b.rang:SetTextColor(0.55, 0.55, 0.55) end
            b.t, b.tab, b.index, b.direct = ta, k, ta.index, profil.connecte
            b:Show()
            hauteur = math.max(hauteur, y + TAILLE + 14)
        end
    end
    return hauteur
end

function Ta.Page()
    local F = NS.fenetre
    return { cle = "talents", icone = "Interface\\Icons\\Ability_Marksmanship",
        libelle = function() return T("Talents", "Talents") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(36)
            page.zone = O.Rangee(20)
            page.yZone = page.y - 20
        end,
        rendre = function(page)
            local p = F.Profil()
            local nom = (F.Cle() or ""):match("^(.-) %- ") or ""
            page.t1:SetText(string.format(T("Les talents de %s", "%s's talents"), nom))
            local arbres = Ta.Arbres(p)
            local spe, maxi = nil, -1
            for _, a in ipairs(arbres) do if (a.points or 0) > maxi then spe, maxi = a.nom, a.points or 0 end end
            local resume = {}
            for _, a in ipairs(arbres) do table.insert(resume, tostring(a.points or 0)) end
            page.intro:SetText(#arbres > 0 and maxi > 0
                and string.format(T("Spécialisation : %s (%s). Le survol d'un talent le décrit.", "Specialisation : %s (%s). Hover a talent to read it."), spe, table.concat(resume, " / "))
                or T("Les trois arbres de la classe. Le survol d'un talent le décrit.", "The class's three trees. Hover a talent to read it."))
            local h = Rendre(page, p or {})
            page.zone:SetHeight(math.max(h, 20))
            page.hauteur = page.yZone + math.max(h, 20)
        end }
end

do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "PLAYER_LOGIN", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    local attente = 0
    f:SetScript("OnEvent", function() attente = 2 end)
    f:SetScript("OnUpdate", function(_, e)
        if attente <= 0 then return end
        attente = attente - (e or 0)
        if attente <= 0 then pcall(Ta.Releve) if NS.fenetre and NS.fenetre.Actualiser then NS.fenetre.Actualiser() end end
    end)
end
