local _, NS = ...

-- Les talents, dans ClassCore, comme la fenetre de talents du jeu (WoW
-- Forever) : les trois arbres cote a cote sur le fond de la classe, chaque
-- talent a sa place exacte, avec les cadres, couleurs, chiffres et fleches
-- du jeu. Onglets Principale / Secondaire. Dessous : les modeles conseilles
-- (montee de niveau, groupe). Une seconde page, le simulateur, permet de
-- placer des points pour essayer, sans rien toucher au personnage.
--
-- WoW Forever donne les talents par le systeme des traits (C_Traits), comme
-- l'interface du jeu (Blizzard_PlayerSpells, version camelot).

NS.talents = {}
local Ta = NS.talents
local T = NS.T

local BOUTON = 40
local ICONE = 36
local MARGE_X, HAUT_ENTETE, MARGE_BAS = 34, 92, 26
local JAUNE = { 1, 0.82, 0 }
local VERT = { 0.12, 1, 0.12 }
local GRIS = { 0.5, 0.5, 0.5 }

local function Pc(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 20)
end

local function Atlas(nom)
    local C = _G.C_Texture
    if not (C and C.GetAtlasInfo) then return false end
    local ok, info = pcall(C.GetAtlasInfo, nom)
    return ok and info ~= nil
end

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

-- ---------------------------------------------------------------------------
-- Lecture : une structure { v = 2, arbres = { { nom, icone, points, talents } },
-- aretes = { { de, vers } }, restants, largeur, hauteur }. Chaque talent :
-- { id (noeud), nom, icone, sort, x, y (position du jeu), arbre, rangee,
--   colonne, rang, max }.
-- ---------------------------------------------------------------------------

-- Valeurs distinctes : la premiere et le pas le plus petit.
local function Grille(valeurs)
    local tri = {}
    for v in pairs(valeurs) do table.insert(tri, v) end
    table.sort(tri)
    local pas
    for i = 2, #tri do
        local d = tri[i] - tri[i - 1]
        if d > 0.5 and (not pas or d < pas) then pas = d end
    end
    return tri[1] or 0, pas or 1
end

function Ta.NombreDeGroupes()
    local n = Pc(_G.GetNumSpecGroups)
    return tonumber(n) or 1
end

function Ta.GroupeActif()
    local CS = _G.C_SpecializationInfo
    return tonumber(CS and Pc(CS.GetActiveSpecGroup)) or 1
end

local function ConfigDuGroupe(groupe)
    local CS, CC = _G.C_SpecializationInfo, _G.C_ClassTalents
    if groupe == Ta.GroupeActif() and CC then
        local c = Pc(CC.GetActiveConfigID)
        if c then return c end
    end
    return CS and Pc(CS.GetCombatConfigIDForSpecGroup, groupe) or nil
end

function Ta.Lire(groupe)
    groupe = groupe or Ta.GroupeActif()
    local CT = _G.C_Traits
    if type(CT) ~= "table" or not CT.GetTreeNodes or not CT.GetNodeInfo then return nil end
    local config = ConfigDuGroupe(groupe)
    if not config then return nil end
    local info = Pc(CT.GetConfigInfo, config)
    local arbreID = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if not arbreID then return nil end

    local s = { v = 2, arbres = {}, aretes = {} }
    local parGroupe, groupes = {}, {}
    local affichages = Pc(CT.GetGroupDisplayInfoByTreeID, arbreID)
    for _, d in ipairs(type(affichages) == "table" and affichages or {}) do
        if d.groupID then
            local a = { nom = d.displayName, icone = d.icon, points = 0, talents = {} }
            table.insert(s.arbres, a)
            a.rangArbre = #s.arbres
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
    if #s.arbres == 0 then
        seul = { nom = "", points = 0, talents = {}, rangArbre = 1 }
        table.insert(s.arbres, seul)
    end
    if CT.GetTreeCurrencyInfo then
        local m = Pc(CT.GetTreeCurrencyInfo, config, arbreID, false)
        local c = type(m) == "table" and m[1]
        if type(c) == "table" then s.restants = tonumber(c.quantity) end
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
                local sort = type(di) == "table" and (di.spellID or di.overriddenSpellID) or nil
                local nom = (type(di) == "table" and di.overrideName) or NomSort(sort)
                local t = { id = id, nom = nom or "?", icone = (type(di) == "table" and di.overrideIcon) or IconeSort(sort),
                    sort = sort, x = ni.posX / 10, y = ni.posY / 10, arbre = a.rangArbre,
                    rang = tonumber(ni.currentRank or ni.ranksPurchased) or 0, max = tonumber(ni.maxRanks) or 1 }
                table.insert(a.talents, t)
                xs[t.x] = true
                ys[t.y] = true
                for _, e in ipairs(type(ni.visibleEdges) == "table" and ni.visibleEdges or {}) do
                    if e.targetNode then table.insert(s.aretes, { de = id, vers = e.targetNode }) end
                end
            end
        end
    end
    -- Rangees et colonnes de la grille du jeu (4 colonnes par arbre).
    local _, pasX = Grille(xs)
    local y0, pasY = Grille(ys)
    for _, a in ipairs(s.arbres) do
        local x0
        for _, t in ipairs(a.talents) do if not x0 or t.x < x0 then x0 = t.x end end
        for _, t in ipairs(a.talents) do
            t.colonne = math.floor((t.x - (x0 or 0)) / pasX + 0.5) + 1
            t.rangee = math.floor((t.y - y0) / pasY + 0.5) + 1
        end
        table.sort(a.talents, function(p, q) if p.rangee ~= q.rangee then return p.rangee < q.rangee end return p.colonne < q.colonne end)
        if a.points == 0 then for _, t in ipairs(a.talents) do a.points = a.points + (t.rang or 0) end end
    end
    for i = #s.arbres, 1, -1 do if #s.arbres[i].talents == 0 then table.remove(s.arbres, i) end end
    if #s.arbres == 0 then return nil end
    for k, a in ipairs(s.arbres) do
        a.rangArbre = k
        for _, t in ipairs(a.talents) do t.arbre = k end
    end
    return s
end

-- Les rangs d'une structure : { [id] = rang }.
function Ta.Rangs(s)
    local r = {}
    for _, a in ipairs(s and s.arbres or {}) do for _, t in ipairs(a.talents) do r[t.id] = t.rang or 0 end end
    return r
end

local function Base()
    ClassCoreDB = type(ClassCoreDB) == "table" and ClassCoreDB or {}
    return ClassCoreDB
end

-- Releve du personnage connecte (ses deux specialisations) et de l'arbre de
-- sa classe (pour le simulateur, depuis n'importe quel personnage).
function Ta.Releve()
    local cle = NS.ClePersonnage()
    if not cle then return end
    local s1 = Ta.Lire(1)
    if not s1 then return end
    local db = Base()
    db.persos = type(db.persos) == "table" and db.persos or {}
    local p = db.persos[cle] or {}
    db.persos[cle] = p
    p.talents = { v = 2, groupes = { s1, Ta.NombreDeGroupes() > 1 and Ta.Lire(2) or nil }, actif = Ta.GroupeActif() }
    local classe = NS.etat and NS.etat.Classe and NS.etat.Classe()
    if classe then
        db.arbresClasse = type(db.arbresClasse) == "table" and db.arbresClasse or {}
        db.arbresClasse[classe] = s1
    end
end

-- La structure montree pour un profil et un groupe (1 principale, 2 secondaire).
function Ta.Structure(profil, groupe)
    if not profil then return nil end
    if profil.connecte then return Ta.Lire(groupe) end
    local p = NS.quetes.Persos()[profil.cle or ""]
    local tt = type(p) == "table" and p.talents
    if type(tt) == "table" and tt.v == 2 and type(tt.groupes) == "table" then return tt.groupes[groupe or 1] end
    return nil
end

function Ta.GroupesDuProfil(profil)
    if not profil then return 1 end
    if profil.connecte then return Ta.NombreDeGroupes() end
    local p = NS.quetes.Persos()[profil.cle or ""]
    local tt = type(p) == "table" and p.talents
    return (type(tt) == "table" and type(tt.groupes) == "table" and tt.groupes[2]) and 2 or 1
end

-- L'arbre d'une classe, sans les rangs d'un personnage (simulateur).
function Ta.ArbreDeClasse(classe, profil)
    if profil and profil.connecte and profil.classe == classe then
        local s = Ta.Lire(1)
        if s then return s end
    end
    local db = Base()
    return type(db.arbresClasse) == "table" and db.arbresClasse[classe or ""] or nil
end

-- ---------------------------------------------------------------------------
-- Regles : 5 points par rangee dans l'arbre, les fleches demandent le talent
-- de depart au maximum.
-- ---------------------------------------------------------------------------

local function Index(s)
    if s._index then return s._index, s._pre end
    local idx, pre = {}, {}
    for _, a in ipairs(s.arbres) do for _, t in ipairs(a.talents) do idx[t.id] = t end end
    for _, e in ipairs(s.aretes or {}) do
        pre[e.vers] = pre[e.vers] or {}
        table.insert(pre[e.vers], e.de)
    end
    s._index, s._pre = idx, pre
    return idx, pre
end

local function PointsAvant(s, rangs, k, rangee)
    local n = 0
    for _, t in ipairs(s.arbres[k] and s.arbres[k].talents or {}) do
        if t.rangee < rangee then n = n + (rangs[t.id] or 0) end
    end
    return n
end

function Ta.Ouvert(s, rangs, t)
    if PointsAvant(s, rangs, t.arbre, t.rangee) < (t.rangee - 1) * 5 then return false end
    local idx, pre = Index(s)
    for _, de in ipairs(pre[t.id] or {}) do
        local src = idx[de]
        if src and (rangs[de] or 0) < (src.max or 1) then return false end
    end
    return true
end

function Ta.Depenses(s, rangs)
    local n, parArbre = 0, {}
    for k, a in ipairs(s.arbres) do
        parArbre[k] = 0
        for _, t in ipairs(a.talents) do
            parArbre[k] = parArbre[k] + (rangs[t.id] or 0)
            n = n + (rangs[t.id] or 0)
        end
    end
    return n, parArbre
end

local function Valide(s, rangs)
    for _, a in ipairs(s.arbres) do
        for _, t in ipairs(a.talents) do
            if (rangs[t.id] or 0) > 0 and not Ta.Ouvert(s, rangs, t) then return false end
        end
    end
    return true
end

function Ta.Ajouter(s, rangs, t, budget)
    if (rangs[t.id] or 0) >= (t.max or 1) then return false end
    if budget and Ta.Depenses(s, rangs) >= budget then return false end
    if not Ta.Ouvert(s, rangs, t) then return false end
    rangs[t.id] = (rangs[t.id] or 0) + 1
    return true
end

function Ta.Retirer(s, rangs, t)
    if (rangs[t.id] or 0) <= 0 then return false end
    rangs[t.id] = rangs[t.id] - 1
    if not Valide(s, rangs) then rangs[t.id] = rangs[t.id] + 1 return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Modeles conseilles (Data/Modeles.lua)
-- ---------------------------------------------------------------------------

-- La suite des talents d'un code, ou nil si l'arbre du jeu ne le permet pas.
function Ta.Decoder(s, code)
    if not (s and type(code) == "string") then return nil end
    local parCase = {}
    for _, a in ipairs(s.arbres) do
        for _, t in ipairs(a.talents) do parCase[a.rangArbre .. ":" .. t.rangee .. ":" .. t.colonne] = t end
    end
    local arbre, suite, rangs = 1, {}, {}
    for c in code:gmatch(".") do
        local k = ({ A = 1, B = 2, C = 3 })[c]
        if k then arbre = k
        else
            local i = tonumber(c, 36)
            if not i then return nil end
            local t = parCase[arbre .. ":" .. (math.floor(i / 4) + 1) .. ":" .. (i % 4 + 1)]
            if not t or not Ta.Ajouter(s, rangs, t) then return nil end
            table.insert(suite, t)
        end
    end
    return suite, rangs
end

local ACTIVITES = {
    quetes = function() return T("Montée de niveau", "Levelling") end,
    groupe = function() return T("Donjons et raids", "Dungeons and raids") end,
}

-- { { nom, icone, suite, rangs, repartition, modele } } pour une structure.
function Ta.Modeles(classe, s)
    local liste = {}
    if not s then return liste end
    for _, m in ipairs(NS.MODELES and NS.MODELES[classe or ""] or {}) do
        local suite, rangs = Ta.Decoder(s, m.code)
        if suite then
            local _, parArbre = Ta.Depenses(s, rangs)
            local rep = {}
            for k = 1, #s.arbres do table.insert(rep, tostring(parArbre[k] or 0)) end
            local a = s.arbres[m.arbre] or s.arbres[1]
            local nom = (ACTIVITES[m.activite] or ACTIVITES.quetes)() .. " : " .. (a.nom or "")
            if m.variante == "saignement" then nom = nom .. " " .. T("(saignements)", "(bleeds)") end
            table.insert(liste, { nom = nom, icone = a.icone, suite = suite, rangs = rangs,
                repartition = table.concat(rep, "/"), modele = m })
        end
    end
    return liste
end

-- Le prochain talent du modele pour des rangs donnes, ou nil (suivi complet).
function Ta.Prochain(modele, rangs)
    local vus = {}
    for _, t in ipairs(modele.suite) do
        vus[t.id] = (vus[t.id] or 0) + 1
        if vus[t.id] > (rangs[t.id] or 0) then return t end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Le plateau : les arbres dessines comme dans le jeu
-- ---------------------------------------------------------------------------

local function Police(fs, nom, repli)
    local o = _G[nom]
    if o then fs:SetFontObject(o) else fs:SetFontObject(repli) end
    fs.couleurPropre = true
end

local function Plateau(page)
    if page.plateau then return page.plateau end
    local p = CreateFrame("Frame", nil, page.zone)
    p.fond = p:CreateTexture(nil, "BACKGROUND", nil, 0)
    p.fond:SetAllPoints()
    p.voile = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.voile:SetAllPoints()
    p.voile:SetColorTexture(0, 0, 0, 0.25)
    local okC, c = pcall(CreateFrame, "Frame", nil, p, "BackdropTemplate")
    if okC and c and c.SetBackdrop then
        c:SetPoint("TOPLEFT", p, "TOPLEFT", -6, 6)
        c:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 6, -6)
        c:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
        c:EnableMouse(false)
        p.cadre = c
    end
    -- Les points restants, en haut a droite, comme dans le jeu.
    p.boite = p:CreateTexture(nil, "ARTWORK")
    if Atlas("Talents-Square-Box-c60") then p.boite:SetAtlas("Talents-Square-Box-c60", true) else p.boite:SetSize(64, 46) p.boite:SetColorTexture(0, 0, 0, 0.5) end
    p.boite:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -12)
    p.restants = p:CreateFontString(nil, "OVERLAY")
    Police(p.restants, "Game32Font_Shadow2", "GameFontNormalHuge")
    p.restants:SetPoint("CENTER", p.boite, "CENTER", 0, 0)
    p.libRestants = p:CreateFontString(nil, "OVERLAY")
    Police(p.libRestants, "SystemFont_Shadow_Med1", "GameFontHighlight")
    p.libRestants:SetPoint("RIGHT", p.boite, "LEFT", -8, 0)
    p.entetes, p.boutons, p.lignes, p.pointes, p.separateurs = {}, {}, {}, {}, {}
    page.plateau = p
    return p
end

local function Entete(p, i)
    local e = p.entetes[i]
    if e then return e end
    e = CreateFrame("Frame", nil, p)
    e:SetSize(48, 48)
    e.icone = e:CreateTexture(nil, "BORDER")
    e.icone:SetSize(36, 36)
    e.icone:SetPoint("CENTER", -3, 3)
    if e.CreateMaskTexture then
        local m = e:CreateMaskTexture()
        if m then m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetSize(40, 40)
        m:SetPoint("CENTER", -2, 2)
        e.icone:AddMaskTexture(m) end
    end
    e.anneau = e:CreateTexture(nil, "OVERLAY", nil, 1)
    if Atlas("Talents-Main-Ring-c60") then e.anneau:SetAtlas("Talents-Main-Ring-c60", true)
    else e.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder") e.anneau:SetSize(54, 54) end
    e.anneau:SetPoint("CENTER", e.icone, "CENTER", 0, 0)
    e.boite = e:CreateTexture(nil, "OVERLAY", nil, 2)
    if Atlas("talents-main-ring-box-c60") then e.boite:SetAtlas("talents-main-ring-box-c60", true) else e.boite:SetSize(26, 18) e.boite:SetColorTexture(0, 0, 0, 0.8) end
    e.boite:SetPoint("CENTER", 14, -12)
    e.points = e:CreateFontString(nil, "OVERLAY")
    e.points:SetDrawLayer("OVERLAY", 3)
    Police(e.points, "GameFontNormal", "GameFontNormal")
    e.points:SetPoint("CENTER", e.boite, "CENTER", 0, 0)
    e.nom = e:CreateFontString(nil, "OVERLAY")
    Police(e.nom, "GameFontHighlightLarge", "GameFontHighlightLarge")
    e.nom:SetPoint("LEFT", e, "LEFT", 54, 2)
    e.nom:SetWordWrap(false)
    p.entetes[i] = e
    return e
end

local function BoutonTalent(p, i)
    local b = p.boutons[i]
    if b then return b end
    b = CreateFrame("Button", nil, p)
    b:SetSize(BOUTON, BOUTON)
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    b.icone = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.icone:SetSize(ICONE, ICONE)
    b.icone:SetPoint("CENTER")
    b.voile = b:CreateTexture(nil, "BORDER", nil, 1)
    b.voile:SetSize(ICONE, ICONE)
    b.voile:SetPoint("CENTER")
    b.voile:SetColorTexture(0, 0, 0, 1)
    b.bord = b:CreateTexture(nil, "ARTWORK")
    b.bord:SetPoint("CENTER")
    b.survol = b:CreateTexture(nil, "HIGHLIGHT")
    b.survol:SetPoint("CENTER")
    b.survol:SetBlendMode("ADD")
    b.survol:SetAlpha(0.5)
    b:SetHighlightTexture(b.survol)
    b.chiffre = b:CreateFontString(nil, "OVERLAY")
    Police(b.chiffre, "SystemFont16_Shadow_ThickOutline", "NumberFontNormal")
    b.chiffre:SetPoint("BOTTOM", b, "BOTTOM", 11, 4)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = false
        if self.t and self.t.sort and GameTooltip.SetSpellByID then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.t.sort) end
        if not ok or GameTooltip:NumLines() == 0 then GameTooltip:AddLine(self.t and self.t.nom or "") end
        GameTooltip:AddLine(string.format(T("Rang %d sur %d", "Rank %d of %d"), self.rang or 0, self.t and self.t.max or 1), 1, 1, 1)
        if self.aide then GameTooltip:AddLine(self.aide, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self, souris) if self.auClic then self.auClic(self.t, souris == "RightButton") end end)
    p.boutons[i] = b
    return b
end

local ART = {
    max = "talents-node-square-yellow",
    ouvert = "talents-node-square-green",
    ferme = "talents-node-square-locked",
}

local function Habiller(b, etat)
    local atlas = ART[etat]
    if Atlas(atlas) then
        b.bord:SetAtlas(atlas, true)
        b.survol:SetAtlas(atlas, true)
    else
        b.bord:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.bord:SetSize(64, 64)
        b.survol:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        b.survol:SetSize(ICONE, ICONE)
    end
    local ferme = etat == "ferme"
    b.icone:SetDesaturated(ferme)
    b.voile:SetShown(ferme)
    b.voile:SetAlpha(ferme and 0.7 or 0)
end

-- Dessine une structure : rangs { [id] = rang }, o = { restants, auClic, aide }.
-- Rend la hauteur occupee dans la zone.
local function Dessiner(page, s, rangs, o)
    o = o or {}
    local zone = page.zone
    local p = Plateau(page)
    for _, b in ipairs(p.boutons) do b:Hide() end
    for _, e in ipairs(p.entetes) do e:Hide() end
    for _, l in ipairs(p.lignes) do l:Hide() end
    for _, a in ipairs(p.pointes) do a:Hide() end
    for _, d in ipairs(p.separateurs) do d:Hide() end
    if not s then p:Hide() return 0 end

    local minX, maxX, minY, maxY
    for _, a in ipairs(s.arbres) do
        for _, t in ipairs(a.talents) do
            minX = math.min(minX or t.x, t.x) maxX = math.max(maxX or t.x, t.x)
            minY = math.min(minY or t.y, t.y) maxY = math.max(maxY or t.y, t.y)
        end
    end
    if not minX then p:Hide() return 0 end
    local largeur = (maxX - minX) + BOUTON + 2 * MARGE_X
    local hauteur = (maxY - minY) + BOUTON + HAUT_ENTETE + MARGE_BAS
    local dispo = (zone:GetWidth() or 780) - 12
    local k = math.min(1, dispo / largeur)
    p:SetScale(k)
    p:SetSize(largeur, hauteur)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", zone, "TOPLEFT", 6 / k, -8 / k)

    -- Le fond de la classe, comme la fenetre du jeu.
    local classe = (o.classe or ""):lower()
    if classe ~= "" and Atlas("talent-background-" .. classe) then
        p.fond:SetAtlas("talent-background-" .. classe)
        p.fond:SetTexCoord(0, 1, 0, 1)
    else
        p.fond:SetColorTexture(0.06, 0.05, 0.04, 1)
    end

    local function Place(t) return (t.x - minX) + MARGE_X + BOUTON / 2, (t.y - minY) + HAUT_ENTETE + BOUTON / 2 end

    -- Les en-tetes : icone dans l'anneau, points, nom ; un separateur entre
    -- deux arbres.
    local bornes = {}
    for i, a in ipairs(s.arbres) do
        local g, d
        for _, t in ipairs(a.talents) do local x = Place(t) g = math.min(g or x, x) d = math.max(d or x, x) end
        bornes[i] = { g = g or 0, d = d or 0 }
        local e = Entete(p, i)
        e.icone:SetTexture(a.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
        e.nom:SetText(a.nom or "")
        e.nom:SetTextColor(1, 1, 1)
        local _, parArbre = Ta.Depenses(s, rangs)
        e.points:SetText(tostring(parArbre[i] or 0))
        e.points:SetTextColor(JAUNE[1], JAUNE[2], JAUNE[3])
        local largeurNom = (e.nom:GetStringWidth() or 100)
        local centre = ((g or 0) + (d or 0)) / 2
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", p, "TOPLEFT", centre - (54 + largeurNom) / 2, -26)
        e:Show()
    end
    for i = 1, #s.arbres - 1 do
        local sep = p.separateurs[i]
        if not sep then
            sep = p:CreateTexture(nil, "BORDER")
            if Atlas("Talents-divider-vertical-c60") then sep:SetAtlas("Talents-divider-vertical-c60") sep:SetWidth(16)
            else sep:SetColorTexture(0.8, 0.65, 0.35, 0.35) sep:SetWidth(2) end
            p.separateurs[i] = sep
        end
        local x = (bornes[i].d + bornes[i + 1].g) / 2
        sep:ClearAllPoints()
        sep:SetPoint("TOP", p, "TOPLEFT", x, -8)
        sep:SetPoint("BOTTOM", p, "BOTTOMLEFT", x, 8)
        sep:Show()
    end

    -- Les talents.
    local n, parId = 0, {}
    for _, a in ipairs(s.arbres) do
        for _, t in ipairs(a.talents) do
            n = n + 1
            local b = BoutonTalent(p, n)
            local x, y = Place(t)
            b:ClearAllPoints()
            b:SetPoint("CENTER", p, "TOPLEFT", x, -y)
            b.t, b.rang, b.auClic, b.aide = t, rangs[t.id] or 0, o.auClic, o.aide
            b.icone:SetTexture(t.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
            local r = rangs[t.id] or 0
            local etat = (r >= (t.max or 1)) and "max" or (Ta.Ouvert(s, rangs, t) and "ouvert" or "ferme")
            b.etat = etat
            Habiller(b, etat)
            if etat == "ferme" and r == 0 then b.chiffre:SetText("")
            else
                b.chiffre:SetText(tostring(r))
                local c = etat == "max" and JAUNE or (etat == "ouvert" and VERT or GRIS)
                b.chiffre:SetTextColor(c[1], c[2], c[3])
            end
            b:Show()
            parId[t.id] = b
        end
    end

    -- Les fleches : jaunes une fois le depart au maximum, grises sinon,
    -- sombres vers un talent ferme.
    local nl = 0
    for _, e in ipairs(s.aretes or {}) do
        local b1, b2 = parId[e.de], parId[e.vers]
        if b1 and b2 and p.CreateLine then
            nl = nl + 1
            local l = p.lignes[nl]
            if not l then
                l = p:CreateLine(nil, "BORDER", nil, 2)
                l:SetThickness(6)
                p.lignes[nl] = l
            end
            local pt = p.pointes[nl]
            if not pt then
                pt = p:CreateTexture(nil, "BORDER", nil, 3)
                p.pointes[nl] = pt
            end
            local actif = (b1.rang or 0) >= (b1.t.max or 1)
            local style = (b2.etat == "ferme" and not actif) and "locked" or (actif and "yellow" or "gray")
            if Atlas("talents-arrow-line-" .. style) then
                l:SetAtlas("talents-arrow-line-" .. style)
                pt:SetAtlas("talents-arrow-head-" .. style, true)
            else
                local c = actif and JAUNE or GRIS
                l:SetColorTexture(c[1], c[2], c[3], 1)
                pt:SetColorTexture(c[1], c[2], c[3], 1)
                pt:SetSize(10, 10)
            end
            local x1, y1 = Place(b1.t)
            local x2, y2 = Place(b2.t)
            local angle = math.atan2(y2 - y1, x1 - x2) -- de la fin vers le depart (haut positif)
            local dx, dy = math.cos(angle) * (BOUTON / 2 + 2), math.sin(angle) * (BOUTON / 2 + 2)
            l:SetStartPoint("CENTER", b1)
            l:SetEndPoint("CENTER", b2, dx, dy)
            pt:ClearAllPoints()
            pt:SetPoint("CENTER", b2, "CENTER", dx, dy)
            pt:SetRotation(angle - math.pi / 2)
            l:Show() pt:Show()
        end
    end

    if o.restants then
        p.restants:SetText(tostring(o.restants))
        p.restants:SetTextColor(VERT[1], VERT[2], VERT[3])
        p.libRestants:SetText(o.libRestants or T("Talents restants", "Talents left"))
        p.libRestants:SetTextColor(1, 1, 1)
        p.boite:Show() p.restants:Show() p.libRestants:Show()
    else
        p.boite:Hide() p.restants:Hide() p.libRestants:Hide()
    end
    p:Show()
    return (hauteur + 14) * k + 8
end

-- ---------------------------------------------------------------------------
-- Les modeles, sous l'arbre (lignes communes de ClassCore)
-- ---------------------------------------------------------------------------

Ta.sim = Ta.sim or { niveau = 60, rangs = {} }

local function Sous(page)
    if page.sous then return page.sous end
    local z = CreateFrame("Frame", nil, page.cadre)
    z:SetSize(page.zone:GetWidth() or 780, 20)
    page.sous = { zone = z }
    return page.sous
end

local function BlocModeles(s, classe, rangs, simulateur)
    local lignes = {}
    for _, m in ipairs(Ta.Modeles(classe, s)) do
        local droite
        if not simulateur then
            local t = Ta.Prochain(m, rangs)
            droite = t and string.format(T("Prochain : %s", "Next : %s"), t.nom) or T("Suivi en entier", "Fully followed")
        else
            droite = m.repartition
        end
        table.insert(lignes, { icone = m.icone, texte = m.nom .. "  (" .. m.repartition .. ")", droite = droite, largeurDroite = 220,
            bouton = { texte = simulateur and T("Charger", "Load") or T("Simuler", "Simulate"), action = function()
                local budget = math.max(0, (Ta.sim.niveau or 60) - 9)
                Ta.sim.classe, Ta.sim.rangs = classe, {}
                for i, t in ipairs(m.suite) do
                    if i > budget then break end
                    Ta.sim.rangs[t.id] = (Ta.sim.rangs[t.id] or 0) + 1
                end
                local F = NS.fenetre
                if F and F.w then F.w.page = "simulateur" end
            end } })
    end
    if #lignes == 0 then
        return { titre = T("Modèles conseillés", "Suggested builds"),
            vide = T("Pas encore de modèle pour cette classe.", "No build yet for this class.") }
    end
    return { titre = T("Modèles conseillés", "Suggested builds"), lignes = lignes }
end

local function RendreSous(page, y, bloc)
    local sous = Sous(page)
    sous.zone:ClearAllPoints()
    sous.zone:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
    sous.zone:SetWidth(page.zone:GetWidth() or 780)
    local F = NS.fenetre
    local h = (F and F.RendreBlocs) and F.RendreBlocs(sous, { bloc }) or 0
    sous.zone:SetHeight(math.max(h, 1))
    return h
end

-- ---------------------------------------------------------------------------
-- Page Talents
-- ---------------------------------------------------------------------------

local function Onglet(O, page, groupe)
    local b = O.Bouton(page.cadre, 90, function() page.groupe = groupe end)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(T("Se débloque avec la double spécialisation.", "Unlocks with dual specialisation."))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pcall(b.SetMotionScriptsWhileDisabled, b, true)
    return b
end

local COCHE = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14:0:0|t"

function Ta.Page()
    local F = NS.fenetre
    return { cle = "talents", icone = "Interface\\Icons\\Ability_Marksmanship",
        libelle = function() return T("Talents", "Talents") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.o2 = Onglet(O, page, 2)
            page.o2:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 2)
            page.o1 = Onglet(O, page, 1)
            page.o1:SetPoint("RIGHT", page.o2, "LEFT", -6, 0)
            page.intro = O.Detail(36)
            page.zone = O.Rangee(20)
            page.yZone = page.y - 20
        end,
        rendre = function(page)
            F = NS.fenetre
            local p = F.Profil() or {}
            local nom = (F.Cle() or ""):match("^(.-) %- ") or ""
            page.t1:SetText(string.format(T("Les talents de %s", "%s's talents"), nom))
            local groupes = Ta.GroupesDuProfil(p)
            if (page.groupe or 1) > groupes then page.groupe = 1 end
            local actif = p.connecte and Ta.GroupeActif() or 1
            page.groupe = page.groupe or actif
            page.o1:SetText(T("Principale", "Primary") .. (actif == 1 and (" " .. COCHE) or ""))
            page.o2:SetText(T("Secondaire", "Secondary") .. (actif == 2 and (" " .. COCHE) or ""))
            page.o2:SetEnabled(groupes > 1)
            page.o1:SetEnabled(page.groupe ~= 1)
            if groupes > 1 then page.o2:SetEnabled(page.groupe ~= 2) end
            page.o1:SetPoint("RIGHT", page.o2, "LEFT", -6, 0)
            local s = Ta.Structure(p, page.groupe)
            local rangs = Ta.Rangs(s)
            if s then
                local _, parArbre = Ta.Depenses(s, rangs)
                local spe, maxi = nil, -1
                for k, a in ipairs(s.arbres) do if (parArbre[k] or 0) > maxi then spe, maxi = a.nom, parArbre[k] or 0 end end
                local rep = {}
                for k = 1, #s.arbres do table.insert(rep, tostring(parArbre[k] or 0)) end
                page.intro:SetText(maxi > 0
                    and string.format(T("Spécialisation : %s (%s). Le survol d'un talent le décrit. Pour essayer d'autres choix : le simulateur.",
                        "Specialisation : %s (%s). Hover a talent to read it. To try other choices : the simulator."), spe, table.concat(rep, " / "))
                    or T("Les trois arbres de la classe. Le survol d'un talent le décrit.", "The class's three trees. Hover a talent to read it."))
            else
                page.intro:SetText(p.connecte and T("Le jeu ne donne pas encore les talents de ce personnage.", "The game does not give this character's talents yet.")
                    or T("Connecte ce personnage une fois pour relever ses talents.", "Log in this character once to read its talents."))
            end
            local restants = s and (s.restants or (p.connecte and nil))
            local h = Dessiner(page, s, rangs, { classe = p.classe, restants = restants })
            local h2 = s and RendreSous(page, h + 6, BlocModeles(s, p.classe, rangs, false)) or 0
            if not s and page.sous then RendreSous(page, 0, { lignes = {} }) end
            local total = h + (s and (h2 + 6) or 0)
            page.zone:SetHeight(math.max(total, 20))
            page.hauteur = page.yZone + math.max(total, 20)
        end }
end

-- ---------------------------------------------------------------------------
-- Page Simulateur
-- ---------------------------------------------------------------------------

function Ta.PageSimulateur()
    local F = NS.fenetre
    return { cle = "simulateur", icone = "Interface\\Icons\\INV_Misc_Book_11",
        libelle = function() return T("Simulateur", "Simulator") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.vider = O.Bouton(page.cadre, 90, function() Ta.sim.rangs = {} end)
            page.vider:SetPoint("TOPRIGHT", page.cadre, "TOPRIGHT", -10, 2)
            page.miens = O.Bouton(page.cadre, 90, function()
                local p = NS.fenetre.Profil() or {}
                local s = Ta.Structure(p, 1)
                Ta.sim.rangs = Ta.Rangs(s)
                Ta.sim.classe = p.classe
            end)
            page.miens:SetPoint("RIGHT", page.vider, "LEFT", -6, 0)
            page.intro = O.Detail(36)
            page.rNiveau = O.Rangee(24)
            O.Curseur(page.rNiveau, 10, 60, 1, function() return Ta.sim.niveau or 60 end, function(v)
                Ta.sim.niveau = math.floor(tonumber(v) or 60)
                -- Moins de points : on retire les derniers talents, du haut de l'arbre.
                local s = Ta.sim.structure
                if s then
                    local budget = Ta.sim.niveau - 9
                    local guard = 0
                    while Ta.Depenses(s, Ta.sim.rangs) > budget and guard < 200 do
                        guard = guard + 1
                        local retire = false
                        for k = #s.arbres, 1, -1 do
                            local liste = s.arbres[k].talents
                            for i = #liste, 1, -1 do
                                if Ta.Retirer(s, Ta.sim.rangs, liste[i]) then retire = true break end
                            end
                            if retire then break end
                        end
                        if not retire then break end
                    end
                end
            end)
            page.zone = O.Rangee(20)
            page.yZone = page.y - 20
        end,
        rendre = function(page)
            F = NS.fenetre
            local p = F.Profil() or {}
            page.t1:SetText(T("Simulateur de talents", "Talent simulator"))
            page.vider:SetText(T("Tout effacer", "Clear all"))
            page.miens:SetText(T("Mes talents", "My talents"))
            page.rNiveau.nom:SetText(T("Niveau du personnage", "Character level"))
            local classe = p.classe
            if Ta.sim.classe ~= classe then Ta.sim.classe, Ta.sim.rangs = classe, {} end
            local s = Ta.ArbreDeClasse(classe, p)
            Ta.sim.structure = s
            local budget = math.max(0, (Ta.sim.niveau or 60) - 9)
            local depenses = s and Ta.Depenses(s, Ta.sim.rangs) or 0
            page.intro:SetText(s and string.format(T("Clic : un point. Clic droit : le retirer. Rien n'est appris : c'est un essai. %d points placés sur %d, niveau %d requis.",
                "Click : one point. Right-click : remove it. Nothing is learned : it is a trial. %d points placed of %d, level %d needed."),
                depenses, budget, depenses > 0 and depenses + 9 or 10)
                or T("Connecte une fois un personnage de cette classe pour relever son arbre.", "Log in a character of this class once to read its tree."))
            page.miens:SetEnabled(Ta.Structure(p, 1) ~= nil)
            local h = Dessiner(page, s, Ta.sim.rangs, { classe = classe, restants = s and (budget - depenses) or nil,
                libRestants = T("Points restants", "Points left"),
                aide = T("Clic : un point. Clic droit : le retirer.", "Click : one point. Right-click : remove it."),
                auClic = function(t, droit)
                    if not s then return end
                    if droit then Ta.Retirer(s, Ta.sim.rangs, t) else Ta.Ajouter(s, Ta.sim.rangs, t, budget) end
                    if F.w then F.w.Rendre() end
                end })
            local h2 = s and RendreSous(page, h + 6, BlocModeles(s, classe, Ta.sim.rangs, true)) or 0
            local total = h + (s and (h2 + 6) or 0)
            page.zone:SetHeight(math.max(total, 20))
            page.hauteur = page.yZone + math.max(total, 20)
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
