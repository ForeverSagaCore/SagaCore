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

local function Pc(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 20)
end

local function Groupe()
    local g = Appel("GetActiveTalentGroup")
    return tonumber(g) or 1
end

-- Ce que le jeu offre pour lire les talents (diagnostic, garde dans les
-- sauvegardes quand rien n'est lu) : les fonctions presentes et leurs reponses.
local function Diagnostic(n)
    local d = { quand = (_G.time and _G.time()) or 0, onglets = tostring(n) }
    for _, nom in ipairs({ "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "GetActiveTalentGroup",
        "GetNumSpecializations", "GetSpecialization", "GetSpecializationInfo", "GetNumTalentGroups", "UnitCharacterPoints" }) do
        d[nom] = type(_G[nom])
    end
    for _, ns in ipairs({ "C_SpecializationInfo", "C_ClassTalents", "C_Traits", "C_Talent" }) do
        local t = _G[ns]
        if type(t) == "table" then
            local cles = {}
            for k in pairs(t) do table.insert(cles, k) end
            table.sort(cles)
            d[ns] = table.concat(cles, ",")
        else
            d[ns] = type(t)
        end
    end
    local ok1, a1, b1, c1, d1, e1 = pcall(_G.GetTalentTabInfo or function() end, 1)
    d.tab1 = table.concat({ tostring(ok1), tostring(a1), tostring(b1), tostring(c1), tostring(d1), tostring(e1) }, " | ")
    local ok2, a2, b2, c2, d2, e2, f2 = pcall(_G.GetTalentInfo or function() end, 1, 1)
    d.talent11 = table.concat({ tostring(ok2), tostring(a2), tostring(b2), tostring(c2), tostring(d2), tostring(e2), tostring(f2) }, " | ")
    local CT, CS, CC = _G.C_Traits, _G.C_SpecializationInfo, _G.C_ClassTalents
    local cfg = CC and Pc(CC.GetActiveConfigID)
    d.configActive = tostring(cfg)
    if CS then d.configGroupe = tostring(Pc(CS.GetCombatConfigIDForSpecGroup, Pc(CS.GetActiveSpecGroup) or 1)) end
    cfg = cfg or (CS and Pc(CS.GetCombatConfigIDForSpecGroup, Pc(CS.GetActiveSpecGroup) or 1))
    local info = cfg and CT and Pc(CT.GetConfigInfo, cfg)
    local arbre = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    d.arbre = tostring(arbre)
    local noeuds = arbre and Pc(CT.GetTreeNodes, arbre)
    d.noeuds = tostring(type(noeuds) == "table" and #noeuds or noeuds)
    local ni = type(noeuds) == "table" and noeuds[1] and Pc(CT.GetNodeInfo, cfg, noeuds[1])
    if type(ni) == "table" then
        local cles = {}
        for k, v in pairs(ni) do table.insert(cles, k .. "=" .. tostring(v)) end
        table.sort(cles)
        d.noeud1 = table.concat(cles, ",")
    end
    local aff = arbre and Pc(CT.GetGroupDisplayInfoByTreeID, arbre)
    d.groupes = tostring(type(aff) == "table" and #aff or aff)
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    ClassCoreDB.diagTalents = d
end

-- Une reponse de C_SpecializationInfo.GetTalentInfo (clients recents) :
-- une table, ou les memes valeurs que l'ancienne fonction.
local function InfoTalent(tab, i, groupe)
    local tn, ti, rangee, colonne, rang, max = Appel("GetTalentInfo", tab, i, false, false, groupe)
    if tn then return tn, ti, rangee, colonne, rang, max end
    local C = _G.C_SpecializationInfo
    if C and C.GetTalentInfo then
        for _, q in ipairs({ { specializationIndex = tab, talentIndex = i, isInspect = false, isPet = false, groupIndex = groupe },
            { tabIndex = tab, talentIndex = i, groupIndex = groupe } }) do
            local ok, r = pcall(C.GetTalentInfo, q)
            if ok and type(r) == "table" and r.name then
                return r.name, r.icon or r.iconTexture or r.fileID, r.tier or r.row, r.column, r.rank or r.currentRank, r.maxRank
            end
        end
    end
    return nil
end

-- WoW Forever : les talents passent par le systeme des traits (C_Traits),
-- comme l'interface du jeu (Blizzard_PlayerSpells, version camelot) : une
-- configuration active, un arbre, trois groupes (les trois arbres de la classe).
local function NomSort(id)
    if not id then return nil end
    local CSp = _G.C_Spell
    local n = CSp and Pc(CSp.GetSpellName, id)
    if not n and _G.GetSpellInfo then n = Pc(_G.GetSpellInfo, id) end
    return n
end

local function IconeSort(id)
    if not id then return nil end
    local CSp = _G.C_Spell
    local i = CSp and Pc(CSp.GetSpellTexture, id)
    if not i and _G.GetSpellTexture then i = Pc(_G.GetSpellTexture, id) end
    return i
end

-- Valeurs distinctes -> numero de rangee ou de colonne, au pas le plus petit.
local function Grille(valeurs)
    local tri = {}
    for v in pairs(valeurs) do table.insert(tri, v) end
    table.sort(tri)
    local pas
    for i = 2, #tri do
        local d = tri[i] - tri[i - 1]
        if d > 0 and (not pas or d < pas) then pas = d end
    end
    return tri[1] or 0, pas or 1
end

local function LireTraits()
    local CT, CS, CC = _G.C_Traits, _G.C_SpecializationInfo, _G.C_ClassTalents
    if type(CT) ~= "table" or not CT.GetTreeNodes or not CT.GetNodeInfo then return {} end
    local config = CC and Pc(CC.GetActiveConfigID)
    if not config and CS then
        local g = Pc(CS.GetActiveSpecGroup) or 1
        config = Pc(CS.GetCombatConfigIDForSpecGroup, g)
    end
    if not config then return {} end
    local info = Pc(CT.GetConfigInfo, config)
    local arbreID = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if not arbreID then return {} end

    local arbres, parGroupe, groupes = {}, {}, {}
    local affichages = Pc(CT.GetGroupDisplayInfoByTreeID, arbreID)
    for _, d in ipairs(type(affichages) == "table" and affichages or {}) do
        if d.groupID then
            local a = { nom = d.displayName, icone = d.icon, points = 0, talents = {} }
            table.insert(arbres, a)
            parGroupe[d.groupID] = a
            table.insert(groupes, d.groupID)
        end
    end
    if #groupes > 0 and CT.GetGroupCurrencyInfo then
        local monnaies = Pc(CT.GetGroupCurrencyInfo, config, groupes)
        for _, gi in ipairs(type(monnaies) == "table" and monnaies or {}) do
            local a = parGroupe[gi.traitNodeGroupID]
            local c = a and type(gi.currencyInfos) == "table" and gi.currencyInfos[1]
            if c then a.points = tonumber(c.spent) or 0 end
        end
    end
    local seul
    if #arbres == 0 then
        seul = { nom = "", points = 0, talents = {} }
        table.insert(arbres, seul)
    end

    local noeuds = Pc(CT.GetTreeNodes, arbreID)
    local xs, ys = {}, {}
    for _, id in ipairs(type(noeuds) == "table" and noeuds or {}) do
        local ni = Pc(CT.GetNodeInfo, config, id)
        if type(ni) == "table" and (ni.ID or 0) ~= 0 and ni.isVisible ~= false and ni.posX and ni.posY then
            local a = seul
            for _, g in ipairs(type(ni.groupIDs) == "table" and ni.groupIDs or {}) do
                if parGroupe[g] then a = parGroupe[g] break end
            end
            if a then
                local entree = (type(ni.activeEntry) == "table" and ni.activeEntry.entryID)
                    or (type(ni.entryIDs) == "table" and ni.entryIDs[1])
                local ei = entree and Pc(CT.GetEntryInfo, config, entree)
                local di = type(ei) == "table" and ei.definitionID and Pc(CT.GetDefinitionInfo, ei.definitionID)
                local sort = type(di) == "table" and (di.spellID or di.overriddenSpellID)
                local nom = (type(di) == "table" and di.overrideName) or NomSort(sort)
                if nom then
                    local t = { nom = nom, icone = (type(di) == "table" and di.overrideIcon) or IconeSort(sort),
                        x = ni.posX, y = ni.posY, rang = tonumber(ni.currentRank or ni.ranksPurchased) or 0,
                        max = tonumber(ni.maxRanks) or 1, sort = sort }
                    table.insert(a.talents, t)
                    xs[ni.posX] = true
                    ys[ni.posY] = true
                end
            end
        end
    end
    -- Rangees et colonnes : au pas de la grille du jeu, chaque arbre depuis
    -- sa colonne la plus a gauche.
    local _, pasX = Grille(xs)
    local y0, pasY = Grille(ys)
    for _, a in ipairs(arbres) do
        local x0
        for _, t in ipairs(a.talents) do if not x0 or t.x < x0 then x0 = t.x end end
        for _, t in ipairs(a.talents) do
            t.colonne = math.floor((t.x - (x0 or 0)) / pasX + 0.5) + 1
            t.rangee = math.floor((t.y - y0) / pasY + 0.5) + 1
            t.x, t.y = nil, nil
        end
        table.sort(a.talents, function(p, q) if p.rangee ~= q.rangee then return p.rangee < q.rangee end return p.colonne < q.colonne end)
        if a.points == 0 then
            for _, t in ipairs(a.talents) do a.points = a.points + (t.rang or 0) end
        end
    end
    for i = #arbres, 1, -1 do if #arbres[i].talents == 0 then table.remove(arbres, i) end end
    return arbres
end

-- { { nom, icone, points, talents = { { nom, icone, rangee, colonne, rang, max, index } } } }
function Ta.Lire()
    local traits = LireTraits()
    if #traits > 0 then return traits end
    return Ta.LireAncien()
end

function Ta.LireAncien()
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
            local tn, ti, rangee, colonne, rang, max = InfoTalent(tab, i, groupe)
            if tn then
                table.insert(arbre.talents, { nom = tn, icone = ti, rangee = tonumber(rangee) or 1, colonne = tonumber(colonne) or 1,
                    rang = tonumber(rang) or 0, max = tonumber(max) or 1, index = i })
            end
        end
        table.insert(arbres, arbre)
    end
    if #arbres == 0 or #(arbres[1].talents or {}) == 0 then pcall(Diagnostic, n) end
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
        if self.t.sort and GameTooltip.SetSpellByID then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.t.sort)
        elseif self.direct and self.index and GameTooltip.SetTalent then ok = pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index) end
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
        page.vide:SetText(profil.connecte and T("Le jeu ne donne pas encore les talents de ce personnage.", "The game does not give this character's talents yet.")
            or T("Connecte ce personnage une fois pour relever ses talents.", "Log in this character once to read its talents."))
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
        local cols = 4
        for _, ta in ipairs(a.talents or {}) do if (ta.colonne or 1) > cols then cols = ta.colonne end end
        local pasX = math.min(PAS_X, math.floor((colonneL - 16 - TAILLE) / math.max(cols - 1, 1)))
        local xGrille = x0 + math.floor((colonneL - 16 - ((cols - 1) * pasX + TAILLE)) / 2)
        for _, ta in ipairs(a.talents or {}) do
            n = n + 1
            local b = Bouton(page, n)
            b:ClearAllPoints()
            local y = 36 + (ta.rangee - 1) * PAS_Y
            b:SetPoint("TOPLEFT", zone, "TOPLEFT", xGrille + (ta.colonne - 1) * pasX, -y)
            b.icone:SetTexture(ta.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icone:SetDesaturated((ta.rang or 0) == 0)
            do local S = _G.CoreSuite if S and S.HabillerIcone then pcall(S.HabillerIcone, b, b.icone, (ta.rang or 0) == 0) end end
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
    for _, ev in ipairs({ "PLAYER_LOGIN", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
        "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
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
