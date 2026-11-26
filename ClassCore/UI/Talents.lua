local _, NS = ...

-- Les talents, dans ClassCore : les trois arbres cote a cote sur le
-- parchemin, chaque talent a sa place, avec les cadres, chiffres et fleches
-- de la fenetre de talents du jeu. En haut a droite, une liste : Principale,
-- Secondaire (une fois debloquee), Simulation (un essai sur le meme arbre).
-- Dessous : les modeles conseilles qui vont a l'arbre du jeu.
--
-- WoW Forever donne les talents par le systeme des traits (C_Traits), comme
-- l'interface du jeu (Blizzard_PlayerSpells, version camelot).

NS.talents = {}
local Ta = NS.talents
local T = NS.T

local BOUTON = 40
local ICONE = 36
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
    -- Rangees et colonnes de la grille du jeu (4 colonnes par arbre). Les
    -- noeuds isoles, loin de leur arbre (noeuds techniques du jeu), sont
    -- ecartes : ils ne sont pas des talents a placer.
    local _, pasX = Grille(xs)
    local _, pasY = Grille(ys)
    local pas = math.max(pasX, pasY)
    for _, a in ipairs(s.arbres) do
        local gardes = {}
        for _, t in ipairs(a.talents) do
            local proche = false
            for _, u in ipairs(a.talents) do
                if u ~= t and math.sqrt((u.x - t.x) ^ 2 + (u.y - t.y) ^ 2) <= 2.3 * pas then proche = true break end
            end
            if proche then table.insert(gardes, t) end
        end
        a.talents = gardes
    end
    local y0
    for _, a in ipairs(s.arbres) do for _, t in ipairs(a.talents) do if not y0 or t.y < y0 then y0 = t.y end end end
    y0 = y0 or 0
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
            if not i then return nil, "caractere " .. c end
            local case = arbre .. ":" .. (math.floor(i / 4) + 1) .. ":" .. (i % 4 + 1)
            local t = parCase[case]
            if not t then return nil, "point " .. (#suite + 1) .. " case vide " .. case end
            if not Ta.Ajouter(s, rangs, t) then return nil, "point " .. (#suite + 1) .. " refuse " .. case .. " " .. tostring(t.nom) end
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
    local diag = {}
    for _, m in ipairs(NS.MODELES and NS.MODELES[classe or ""] or {}) do
        local suite, rangs = Ta.Decoder(s, m.code)
        if not suite then table.insert(diag, m.code:sub(1, 12) .. " : " .. tostring(rangs)) end
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
    -- Ce qui n'a pas pu se lire, garde pour corriger (sauvegardes).
    if #diag > 0 then
        local db = Base()
        db.diagModeles = type(db.diagModeles) == "table" and db.diagModeles or {}
        local grille = {}
        for _, a in ipairs(s.arbres) do
            for _, t in ipairs(a.talents) do table.insert(grille, a.rangArbre .. ":" .. t.rangee .. ":" .. t.colonne .. "=" .. tostring(t.nom) .. "/" .. tostring(t.max)) end
        end
        db.diagModeles[classe or "?"] = { echecs = diag, grille = table.concat(grille, ", ") }
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
-- Les arbres, sur le parchemin : un titre par arbre (comme les rubriques de
-- la suite), puis ses talents a leur place, avec les cadres, chiffres et
-- fleches de la fenetre de talents du jeu.
-- ---------------------------------------------------------------------------

local function Police(fs, nom, repli)
    local o = _G[nom]
    if o then fs:SetFontObject(o) else fs:SetFontObject(repli) end
    fs.couleurPropre = true
end

local PAS = 56        -- ecart entre deux talents, comme dans le jeu
local HAUT_TITRE = 34 -- titre de l'arbre et son filet

local function Grille2(page)
    if page.grille then return page.grille end
    local g = CreateFrame("Frame", nil, page.zone)
    g:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, 0)
    g.boutons, g.lignes, g.pointes, g.titres = {}, {}, {}, {}
    page.grille = g
    return g
end

local function TitreArbre(page, g, i)
    local t = g.titres[i]
    if t then return t end
    t = { fs = page.zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = page.zone:CreateTexture(nil, "ARTWORK"),
          droite = page.zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
    t.fs:SetJustifyH("LEFT") t.fs:SetWordWrap(false)
    t.droite:SetJustifyH("RIGHT") t.droite:SetWordWrap(false)
    g.titres[i] = t
    return t
end

local function BoutonTalent(g, i)
    local b = g.boutons[i]
    if b then return b end
    b = CreateFrame("Button", nil, g)
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
    g.boutons[i] = b
    return b
end

local ART = {
    max = "talents-node-square-yellow",
    ouvert = "talents-node-square-green",
    ferme = "talents-node-square-gray",
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
    b.voile:SetAlpha(ferme and 0.55 or 0)
end

-- Dessine une structure dans la zone de la page. o = { auClic, aide }.
-- Rend la hauteur occupee.
local function Dessiner(page, s, rangs, o)
    o = o or {}
    local zone = page.zone
    local g = Grille2(page)
    for _, b in ipairs(g.boutons) do b:Hide() end
    for _, l in ipairs(g.lignes) do l:Hide() end
    for _, a in ipairs(g.pointes) do a:Hide() end
    for _, t in ipairs(g.titres) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
    if not s or #s.arbres == 0 then g:Hide() return 0 end

    local largeur = (zone:GetWidth() or 780)
    local nA = #s.arbres
    local colonneL = math.floor(largeur / nA)
    local maxRangee, maxCol = 1, 4
    for _, a in ipairs(s.arbres) do
        for _, t in ipairs(a.talents) do
            maxRangee = math.max(maxRangee, t.rangee or 1)
            maxCol = math.max(maxCol, t.colonne or 1)
        end
    end
    -- Le pas du jeu, reduit seulement si les arbres ne tiennent pas.
    local pas = math.min(PAS, math.floor((colonneL - 24 - BOUTON) / math.max(maxCol - 1, 1)))
    local k = math.min(1, pas / PAS)
    g:SetScale(k)
    local hauteur = HAUT_TITRE + 10 + (maxRangee - 1) * PAS * k + BOUTON * k + 12
    g:SetSize(largeur / k, hauteur / k)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, 0)

    local _, parArbre = Ta.Depenses(s, rangs)
    local parId, n = {}, 0
    for i, a in ipairs(s.arbres) do
        local x0 = (i - 1) * colonneL
        -- Le titre de l'arbre et ses points, comme une rubrique.
        local t = TitreArbre(page, g, i)
        t.fs:ClearAllPoints()
        t.fs:SetPoint("TOPLEFT", zone, "TOPLEFT", x0, 0)
        t.fs:SetWidth(colonneL - 90)
        t.fs:SetText(a.nom or "")
        t.droite:ClearAllPoints()
        t.droite:SetPoint("TOPRIGHT", zone, "TOPLEFT", x0 + colonneL - 16, -3)
        t.droite:SetWidth(80)
        local pts = parArbre[i] or 0
        t.droite:SetText(string.format(pts > 1 and T("%d points", "%d points") or T("%d point", "%d point"), pts))
        t.filet:ClearAllPoints()
        t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
        t.filet:SetSize(colonneL - 16, 1)
        if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet) end
        t.fs:Show() t.filet:Show() t.droite:Show()
        -- Les talents, centres dans la colonne de l'arbre.
        local largeurGrille = (maxCol - 1) * PAS * k + BOUTON * k
        local xg = x0 + math.floor((colonneL - 16 - largeurGrille) / 2)
        for _, ta in ipairs(a.talents) do
            n = n + 1
            local b = BoutonTalent(g, n)
            b:ClearAllPoints()
            local x = (xg + BOUTON * k / 2 + (ta.colonne - 1) * PAS * k) / k
            local y = (HAUT_TITRE + 10 + BOUTON * k / 2 + (ta.rangee - 1) * PAS * k) / k
            b:SetPoint("CENTER", g, "TOPLEFT", x, -y)
            b.t, b.rang, b.auClic, b.aide = ta, rangs[ta.id] or 0, o.auClic, o.aide
            b.icone:SetTexture(ta.icone or "Interface\\Icons\\INV_Misc_QuestionMark")
            local r = rangs[ta.id] or 0
            local etat = (r >= (ta.max or 1)) and "max" or (Ta.Ouvert(s, rangs, ta) and "ouvert" or "ferme")
            b.etat = etat
            Habiller(b, etat)
            if etat == "ferme" and r == 0 then b.chiffre:SetText("")
            else
                b.chiffre:SetText(tostring(r))
                local c = etat == "max" and JAUNE or (etat == "ouvert" and VERT or GRIS)
                b.chiffre:SetTextColor(c[1], c[2], c[3])
            end
            b:Show()
            parId[ta.id] = b
        end
    end

    -- Les fleches du jeu : jaunes une fois le depart au maximum, grises sinon.
    local nl = 0
    for _, e in ipairs(s.aretes or {}) do
        local b1, b2 = parId[e.de], parId[e.vers]
        if b1 and b2 and g.CreateLine then
            nl = nl + 1
            local l = g.lignes[nl]
            if not l then
                l = g:CreateLine(nil, "BORDER", nil, 2)
                if l then l:SetThickness(6) end
                g.lignes[nl] = l
            end
            local pt = g.pointes[nl]
            if not pt then
                pt = g:CreateTexture(nil, "BORDER", nil, 3)
                g.pointes[nl] = pt
            end
            if l then
                local actif = (b1.rang or 0) >= (b1.t.max or 1)
                local style = actif and "yellow" or (b2.etat == "ferme" and "locked" or "gray")
                if Atlas("talents-arrow-line-" .. style) then
                    l:SetAtlas("talents-arrow-line-" .. style)
                    pt:SetAtlas("talents-arrow-head-" .. style, true)
                else
                    local c = actif and JAUNE or GRIS
                    l:SetColorTexture(c[1], c[2], c[3], 1)
                    pt:SetColorTexture(c[1], c[2], c[3], 1)
                    pt:SetSize(10, 10)
                end
                local dc = (b1.t.colonne or 1) - (b2.t.colonne or 1)
                local dr = (b2.t.rangee or 1) - (b1.t.rangee or 1)
                local angle = math.atan2(dr, dc) -- de la fin vers le depart (haut positif)
                local dx, dy = math.cos(angle) * (BOUTON / 2 + 2), math.sin(angle) * (BOUTON / 2 + 2)
                l:SetStartPoint("CENTER", b1)
                l:SetEndPoint("CENTER", b2, dx, dy)
                pt:ClearAllPoints()
                pt:SetPoint("CENTER", b2, "CENTER", dx, dy)
                pt:SetRotation(angle - math.pi / 2)
                l:Show() pt:Show()
            end
        end
    end
    g:Show()
    return hauteur
end

-- ---------------------------------------------------------------------------
-- Les modeles, sous les arbres (lignes communes de ClassCore)
-- ---------------------------------------------------------------------------

Ta.sim = Ta.sim or { niveau = 60, rangs = {} }

local function Sous(page)
    if page.sous then return page.sous end
    local z = CreateFrame("Frame", nil, page.cadre)
    z:SetSize(page.zone:GetWidth() or 780, 20)
    page.sous = { zone = z }
    return page.sous
end

local function ChargerModele(m, classe)
    local budget = math.max(0, (Ta.sim.niveau or 60) - 9)
    Ta.sim.classe, Ta.sim.rangs = classe, {}
    for i, t in ipairs(m.suite) do
        if i > budget then break end
        Ta.sim.rangs[t.id] = (Ta.sim.rangs[t.id] or 0) + 1
    end
end

-- nil quand aucun modele ne va a cet arbre : rien n'est montre.
local function BlocModeles(page, s, classe, rangs, simulation)
    local lignes = {}
    for _, m in ipairs(Ta.Modeles(classe, s)) do
        local droite
        if not simulation then
            local t = Ta.Prochain(m, rangs)
            droite = t and string.format(T("Prochain point : %s", "Next point : %s"), t.nom) or T("Suivi en entier", "Fully followed")
        end
        table.insert(lignes, { icone = m.icone, texte = m.nom .. "  (" .. m.repartition .. ")", droite = droite, largeurDroite = 240,
            bouton = { texte = simulation and T("Charger", "Load") or T("Essayer", "Try"), action = function()
                ChargerModele(m, classe)
                page.mode = "simulation"
            end } })
    end
    if #lignes == 0 then return nil end
    return { titre = T("Modèles conseillés", "Suggested builds"), lignes = lignes }
end

local function RendreSous(page, y, bloc)
    local sous = Sous(page)
    sous.zone:ClearAllPoints()
    sous.zone:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
    sous.zone:SetWidth(page.zone:GetWidth() or 780)
    local F = NS.fenetre
    local h = (F and F.RendreBlocs) and F.RendreBlocs(sous, bloc and { bloc } or {}) or 0
    sous.zone:SetHeight(math.max(h, 1))
    return h
end

-- ---------------------------------------------------------------------------
-- La page Talents : une liste en haut a droite (Principale, Secondaire
-- quand elle est debloquee, Simulation). La simulation se fait sur le meme
-- arbre : clic pour un point, clic droit pour le retirer.
-- ---------------------------------------------------------------------------

-- Moins de points (niveau baisse) : les derniers talents partent, du haut de l'arbre.
local function Ajuster(s, budget)
    local garde = 0
    while Ta.Depenses(s, Ta.sim.rangs) > budget and garde < 200 do
        garde = garde + 1
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

function Ta.Page()
    local F = NS.fenetre
    return { cle = "talents", icone = "Interface\\Icons\\Ability_Marksmanship",
        libelle = function() return T("Talents", "Talents") end,
        construire = function(page, O)
            page.t1 = O.Section()
            -- La liste sur la ligne du titre, calee a droite.
            local r = CreateFrame("Frame", nil, page.cadre)
            r:SetSize(O.LARGEUR - 10, 22)
            r:SetPoint("TOPLEFT", page.cadre, "TOPLEFT", 0, 2)
            page.choix = O.Segments(r, function()
                local p = NS.fenetre.Profil() or {}
                local l = { { "principale", T("Principale", "Primary") } }
                if Ta.GroupesDuProfil(p) > 1 then table.insert(l, { "secondaire", T("Secondaire", "Secondary") }) end
                table.insert(l, { "simulation", T("Simulation", "Simulation") })
                return l
            end, function() return page.mode or "principale" end, function(v) page.mode = v end)
            page.intro = O.Detail(36)
            page.yAvant = page.y
            -- Simulation seulement : le niveau, puis les points et deux actions.
            page.rNiveau = O.Rangee(24)
            O.Curseur(page.rNiveau, 10, 60, 1, function() return Ta.sim.niveau or 60 end, function(v)
                Ta.sim.niveau = math.floor(tonumber(v) or 60)
                if Ta.sim.structure then Ajuster(Ta.sim.structure, Ta.sim.niveau - 9) end
            end)
            page.rPoints = O.Rangee(24)
            page.vider = O.Bouton(page.rPoints, 90, function() Ta.sim.rangs = {} end)
            page.vider:SetPoint("RIGHT", page.rPoints, "RIGHT", -10, 0)
            page.miens = O.Bouton(page.rPoints, 90, function()
                local p = NS.fenetre.Profil() or {}
                Ta.sim.rangs = Ta.Rangs(Ta.Structure(p, 1))
                Ta.sim.classe = p.classe
                if Ta.sim.structure then Ajuster(Ta.sim.structure, (Ta.sim.niveau or 60) - 9) end
            end)
            page.miens:SetPoint("RIGHT", page.vider, "LEFT", -6, 0)
            page.zone = O.Rangee(20)
            page.yZone = page.y - 20
        end,
        rendre = function(page)
            F = NS.fenetre
            local p = F.Profil() or {}
            local nom = (F.Cle() or ""):match("^(.-) %- ") or ""
            page.t1:SetText(string.format(T("Les talents de %s", "%s's talents"), nom))
            local groupes = Ta.GroupesDuProfil(p)
            if page.mode == "secondaire" and groupes < 2 then page.mode = "principale" end
            page.mode = page.mode or "principale"
            local simulation = page.mode == "simulation"
            page.rNiveau:SetShown(simulation)
            page.rPoints:SetShown(simulation)
            -- Hors simulation, les arbres montent a la place des deux rangees.
            local yZone = simulation and page.yZone or page.yAvant + 6
            page.zone:ClearAllPoints()
            page.zone:SetPoint("TOPLEFT", page.cadre, "TOPLEFT", 0, -yZone)

            local s, rangs, o
            if simulation then
                local classe = p.classe
                if Ta.sim.classe ~= classe then Ta.sim.classe, Ta.sim.rangs = classe, {} end
                s = Ta.ArbreDeClasse(classe, p)
                Ta.sim.structure = s
                rangs = Ta.sim.rangs
                local budget = math.max(0, (Ta.sim.niveau or 60) - 9)
                local depenses = s and Ta.Depenses(s, rangs) or 0
                page.rNiveau.nom:SetText(T("Niveau du personnage", "Character level"))
                page.rPoints.nom:SetText(string.format(T("%d points placés sur %d, niveau %d requis", "%d points placed of %d, level %d needed"),
                    depenses, budget, depenses > 0 and depenses + 9 or 10))
                page.vider:SetText(T("Tout effacer", "Clear all"))
                page.miens:SetText(T("Mes talents", "My talents"))
                page.miens:SetEnabled(Ta.Structure(p, 1) ~= nil)
                page.intro:SetText(s and T("Un essai, sans rien apprendre : clic pour placer un point, clic droit pour le retirer.",
                    "A trial, nothing is learned : click to place a point, right-click to remove it.")
                    or T("Connecte une fois un personnage de cette classe pour relever son arbre.", "Log in a character of this class once to read its tree."))
                o = { aide = T("Clic : un point. Clic droit : le retirer.", "Click : one point. Right-click : remove it."),
                    auClic = function(t, droit)
                        if not s then return end
                        if droit then Ta.Retirer(s, Ta.sim.rangs, t) else Ta.Ajouter(s, Ta.sim.rangs, t, budget) end
                        if F.w then F.w.Rendre() end
                    end }
            else
                s = Ta.Structure(p, page.mode == "secondaire" and 2 or 1)
                rangs = Ta.Rangs(s)
                if s then
                    local _, parArbre = Ta.Depenses(s, rangs)
                    local spe, maxi = nil, -1
                    for k, a in ipairs(s.arbres) do if (parArbre[k] or 0) > maxi then spe, maxi = a.nom, parArbre[k] or 0 end end
                    local rep = {}
                    for k = 1, #s.arbres do table.insert(rep, tostring(parArbre[k] or 0)) end
                    local texte = maxi > 0 and string.format(T("Spécialisation : %s (%s).", "Specialisation : %s (%s)."), spe, table.concat(rep, " / "))
                        or T("Aucun point placé.", "No point placed.")
                    if s.restants and s.restants > 0 then
                        texte = texte .. " " .. string.format(s.restants > 1 and T("%d points à placer.", "%d points to place.") or T("%d point à placer.", "%d point to place."), s.restants)
                    end
                    page.intro:SetText(texte .. " " .. T("Le survol d'un talent le décrit.", "Hover a talent to read it."))
                else
                    page.intro:SetText(p.connecte and T("Le jeu ne donne pas encore les talents de ce personnage.", "The game does not give this character's talents yet.")
                        or T("Connecte ce personnage une fois pour relever ses talents.", "Log in this character once to read its talents."))
                end
                o = {}
            end
            local h = Dessiner(page, s, rangs, o)
            local h2 = RendreSous(page, h + 10, s and BlocModeles(page, s, p.classe, rangs, simulation) or nil)
            local total = h + (h2 > 0 and (h2 + 10) or 0)
            page.zone:SetHeight(math.max(total, 20))
            page.hauteur = yZone + math.max(total, 20)
        end }
end

-- L'ancienne page a part n'existe plus : tout est sur la page Talents.
function Ta.PageSimulateur() return nil end

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
