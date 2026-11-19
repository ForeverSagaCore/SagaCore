local _, NS = ...

-- Fenetre de LegacyCore : la meme charte et la meme taille que les autres
-- add-ons de la suite. En haut, les personnages (le connecte d'abord) ; a
-- gauche, les pages ; a droite, le contenu.
--
-- Pages :
--   Mes arbres     les trois arbres d'heritage du personnage choisi
--   Defis          ce que vos personnages ont atteint, et le plus proche
--   Personnages    tous vos personnages, points depenses par arbre
--   Conseils       les choix les plus repandus dans la communaute

NS.fenetre = {}
local fen = NS.fenetre
local L = NS.L

local LARGEUR, HAUTEUR = 1060, 740
local LARGEUR_MENU = 170
local ECART_MENU = 14
local HAUTEUR_LIGNE = 20
local RETRAIT = 16
local TAILLE_PORTRAIT = 30

local cadre
local etat = { page = "arbres", cle = nil, persoVu = nil }
local BrancherManette

local PAGES = {
    { cle = "arbres", libelle = "NAV_TREES", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    { cle = "defis", libelle = "NAV_CHALLENGES", icone = "Interface\\Icons\\INV_Misc_Note_01" },
    { cle = "persos", libelle = "NAV_CHARACTERS", icone = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
    { cle = "chrono", libelle = "NAV_TIMELINE", icone = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { cle = "conseils", libelle = "NAV_ADVICE", icone = "Interface\\Icons\\INV_Misc_Book_09" },
}
fen.PAGES = PAGES

-- Les memes couleurs et polices que QuestCore et CraftCore (et donc les
-- memes encres sur le parchemin) : titres en or, texte en blanc, ce qui est
-- acquis en vert, le secondaire en gris clair, le verrouille en gris.
local ESPACE_SECTION = 14
local GRIS = { 0.6, 0.6, 0.6 }
local SECONDAIRE = { 0.8, 0.8, 0.8 }
local OR = { 1, 0.82, 0 }
local BLANC = { 1, 1, 1 }
local VERT = { 0.31, 0.82, 0.41 }

-- ---------------------------------------------------------------------------
-- Personnage choisi : le meme dans toute la suite
-- ---------------------------------------------------------------------------

local function ChoisirPerso(cle)
    etat.cle = cle
    local S = NS.suite
    if S and S.PoserPersonnage and cle then etat.persoVu = S.PoserPersonnage(cle) end
end

local function SuivreLaSuite()
    local S = NS.suite
    if not (S and S.Personnage) then return end
    local cle, version = S.Personnage()
    if version and version ~= etat.persoVu then
        etat.persoVu = version
        if cle and NS.base.Personnage(cle) then etat.cle = cle end
    end
end

-- ---------------------------------------------------------------------------
-- Lignes du contenu
-- ---------------------------------------------------------------------------

local function Ligne(contenu, index)
    contenu.lignes = contenu.lignes or {}
    local l = contenu.lignes[index]
    if l then return l end
    l = CreateFrame("Button", nil, contenu)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.gauche = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.gauche:SetJustifyH("LEFT")
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetJustifyH("RIGHT")
    l.droite:SetPoint("TOPRIGHT", l, "TOPRIGHT", -6, -4)
    l.filet = l:CreateTexture(nil, "ARTWORK")
    NS.charte.Filet(l.filet, l)
    l.filet:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    NS.charte.PoliceStable(l.gauche)
    l.detail = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.detail:SetJustifyH("LEFT")
    l.detail:SetWordWrap(true)
    -- Bandeau leger derriere un titre de categorie.
    l.bandeau = l:CreateTexture(nil, "BACKGROUND")
    l.bandeau:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    l.bandeau:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, 2)
    l.bandeau:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    l.bandeau:SetBlendMode("ADD")
    l.bandeau:SetAlpha(0.35)
    l.bandeau:Hide()
    -- Portrait d'un personnage, dans son cadre.
    l.cadreVisage = l:CreateTexture(nil, "BORDER")
    l.cadreVisage:SetSize(34, 34)
    l.cadreVisage:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    l.cadreVisage:Hide()
    l.visage = l:CreateTexture(nil, "ARTWORK")
    l.visage:SetPoint("TOPLEFT", l.cadreVisage, "TOPLEFT", 5, -5)
    l.visage:SetPoint("BOTTOMRIGHT", l.cadreVisage, "BOTTOMRIGHT", -5, 5)
    l.visage:Hide()
    contenu.lignes[index] = l
    return l
end

-- options : retrait, icone, texte, couleur, droite, couleurDroite, detail,
-- police, desature, survol
local function Poser(contenu, index, y, o)
    local l = Ligne(contenu, index)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    local x = 2 + (o.retrait or 0)
    l.bandeau:SetShown(o.bandeau == true)
    l.cadreVisage:Hide()
    l.visage:Hide()
    if o.visage then
        l.cadreVisage:ClearAllPoints()
        l.cadreVisage:SetPoint("TOPLEFT", l, "TOPLEFT", x - 2, 1)
        l.cadreVisage:Show()
        l.visage:Show()
        o.visage(l.visage)
        x = x + 38
    end
    if o.icone then
        l.icone:ClearAllPoints()
        l.icone:SetPoint("TOPLEFT", l, "TOPLEFT", x, -1)
        l.icone:SetTexture(o.icone)
        l.icone:SetDesaturated(o.desature == true)
        l.icone:Show()
        x = x + 22
    else
        l.icone:Hide()
    end
    l.gauche:SetFontObject(o.police or "GameFontHighlightSmall")
    l.gauche:ClearAllPoints()
    l.gauche:SetPoint("TOPLEFT", l, "TOPLEFT", x, -4)
    l.gauche:SetPoint("RIGHT", l.droite, "LEFT", -8, 0)
    -- Une note peut passer a la ligne ; un nom reste sur une ligne.
    l.gauche:SetWordWrap(o.multi == true)
    l.gauche:SetText(o.texte or "")
    local c = o.couleur or BLANC
    l.gauche:SetTextColor(c[1], c[2], c[3])
    l.droite:SetText(o.droite or "")
    local cd = o.couleurDroite or GRIS
    l.droite:SetTextColor(cd[1], cd[2], cd[3])
    local hauteur = HAUTEUR_LIGNE
    if o.section and NS.charte.TitreDeSection(l.gauche, l.filet) then hauteur = HAUTEUR_LIGNE + 6 end
    if o.couleurTitre then l.gauche:SetTextColor(o.couleurTitre[1], o.couleurTitre[2], o.couleurTitre[3]) end
    if o.multi then hauteur = math.max(HAUTEUR_LIGNE, (l.gauche:GetStringHeight() or 12) + 8) end
    if o.detail then
        l.detail:ClearAllPoints()
        l.detail:SetPoint("TOPLEFT", l, "TOPLEFT", x, -(HAUTEUR_LIGNE - 2))
        l.detail:SetPoint("RIGHT", l, "RIGHT", -8, 0)
        l.detail:SetText(o.detail)
        local cdet = o.couleurDetail or SECONDAIRE
        l.detail:SetTextColor(cdet[1], cdet[2], cdet[3])
        l.detail:Show()
        hauteur = hauteur + math.max(12, l.detail:GetStringHeight() or 12) + 2
    else
        l.detail:Hide()
    end
    if o.visage then hauteur = math.max(hauteur, 38) end
    l:SetHeight(hauteur)
    l.filet:SetShown(o.filet == true)
    l:EnableMouse(o.survol ~= nil)
    l:SetScript("OnEnter", o.survol)
    l:SetScript("OnLeave", o.survol and function() GameTooltip:Hide() end or nil)
    l:Show()
    return y + hauteur + (o.apres or 0)
end

-- Titre de section : comme QuestCore, en or, souligne d'un filet.
local function Titre(contenu, index, y, texte, bandeau)
    if y > 0 then y = y + ESPACE_SECTION end
    return Poser(contenu, index, y, { texte = texte, section = true, filet = true, apres = 6, bandeau = bandeau })
end

local function NomDeClasse(jeton)
    local noms = _G.LOCALIZED_CLASS_NAMES_MALE
    return (type(noms) == "table" and jeton and noms[jeton]) or tostring(jeton or "?")
end

local function NomDeMetier(ligne, nom)
    return nom or L["PROF_" .. tostring(ligne)] or ("#" .. tostring(ligne))
end

local NOMS_ARBRES = { metiers = "TREE_PROFESSIONS", aventure = "TREE_ADVENTURE", ressources = "TREE_RESOURCES" }

local DessinerArbres, PoserVisage
-- ---------------------------------------------------------------------------
-- Arbres dessines : une case par talent, a sa place
-- ---------------------------------------------------------------------------

local CASE, ICONE, ECART_ARBRES = 50, 38, 28

-- Les cadres de talents du jeu (carre a coins coupes, ou octogone d'un
-- choix), s'ils existent dans ce client.
local function AtlasExiste(nom)
    local f = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if not f then return false end
    local ok, info = pcall(f, nom)
    return ok and info ~= nil
end
local atlasVus = {}
local function Atlas(forme, etat)
    local nom = "talents-node-" .. forme .. "-" .. etat
    if atlasVus[nom] == nil then atlasVus[nom] = AtlasExiste(nom) end
    return atlasVus[nom] and nom or nil
end

local function Lien(contenu, rang)
    contenu.liens = contenu.liens or {}
    local l = contenu.liens[rang]
    if l then return l end
    if not contenu.CreateLine then return nil end
    l = contenu:CreateLine(nil, "BACKGROUND")
    l:SetThickness(3)
    contenu.liens[rang] = l
    return l
end

local function Case(contenu, rang)
    contenu.cases = contenu.cases or {}
    local c = contenu.cases[rang]
    if c then return c end
    c = CreateFrame("Button", nil, contenu)
    c:SetSize(ICONE, ICONE)
    c.bord = c:CreateTexture(nil, "BACKGROUND")
    c.bord:SetPoint("TOPLEFT", -2, 2)
    c.bord:SetPoint("BOTTOMRIGHT", 2, -2)
    c.icone = c:CreateTexture(nil, "ARTWORK")
    c.icone:SetPoint("TOPLEFT", 3, -3)
    c.icone:SetPoint("BOTTOMRIGHT", -3, 3)
    c.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Le cadre du jeu (coins coupes), par-dessus l'icone.
    c.cadre = c:CreateTexture(nil, "OVERLAY", nil, -1)
    c.cadre:SetPoint("TOPLEFT", -7, 7)
    c.cadre:SetPoint("BOTTOMRIGHT", 7, -7)
    c.fondRang = c:CreateTexture(nil, "OVERLAY")
    c.fondRang:SetColorTexture(0, 0, 0, 0.75)
    c.fondRang:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -3)
    c.fondRang:SetSize(26, 13)
    c.rang = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.rang:SetPoint("CENTER", c.fondRang, "CENTER", 0, 0)
    c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    contenu.cases[rang] = c
    return c
end

local function TitreDArbre(contenu, rang)
    contenu.titresArbres = contenu.titresArbres or {}
    local t = contenu.titresArbres[rang]
    if t then return t end
    t = contenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetJustifyH("LEFT")
    contenu.titresArbres[rang] = t
    return t
end

DessinerArbres = function(contenu, arbres, y)
    local largeur = contenu:GetWidth() or 760
    local nCase, nTitre, nLien = 0, 0, 0
    local x, hauteurLigne = 0, 0
    -- Dans l'ordre du jeu, sans les arbres vides.
    local ORDRE = { aventure = 1, ressources = 2, metiers = 3 }
    local tries = {}
    for _, a in ipairs(arbres) do if #(a.noeuds or {}) > 0 then table.insert(tries, a) end end
    table.sort(tries, function(p, q) return (ORDRE[p.genre] or 9) < (ORDRE[q.genre] or 9) end)
    arbres = tries
    for _, a in ipairs(arbres) do
        local parId = {}
        -- Colonnes et rangees : les positions du jeu, dans l'ordre.
        local xs, ys, vusX, vusY = {}, {}, {}, {}
        for _, n in ipairs(a.noeuds) do
            if not vusX[n.x] then vusX[n.x] = true table.insert(xs, n.x) end
            if not vusY[n.y] then vusY[n.y] = true table.insert(ys, n.y) end
        end
        table.sort(xs) table.sort(ys)
        local colonne, rangee = {}, {}
        for i, v in ipairs(xs) do colonne[v] = i end
        for i, v in ipairs(ys) do rangee[v] = i end
        local largeurArbre = math.max(#xs * CASE, 170)
        local hauteurArbre = 26 + #ys * CASE
        if x > 0 and x + largeurArbre > largeur then
            y = y + hauteurLigne + 10
            x, hauteurLigne = 0, 0
        end
        nTitre = nTitre + 1
        local t = TitreDArbre(contenu, nTitre)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", contenu, "TOPLEFT", x, -y)
        t:SetText((a.nom or L[NOMS_ARBRES[a.genre] or ""] or "?") .. "  |cffffffff" .. NS.base.Depenses(a) .. "|r")
        t:Show()
        for _, n in ipairs(a.noeuds) do
            nCase = nCase + 1
            local c = Case(contenu, nCase)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", contenu, "TOPLEFT", x + (colonne[n.x] - 1) * CASE + 4, -(y + 26 + (rangee[n.y] - 1) * CASE))
            local r, maxi = tonumber(n.rang) or 0, tonumber(n.maxi) or 1
            c.icone:SetTexture(n.icone or NS.IconeDeSort(n.sort) or "Interface\\Icons\\INV_Misc_QuestionMark")
            c.icone:SetDesaturated(r == 0)
            -- Pris : vert. Prenable : or. Verrouille : gris.
            if r > 0 then
                c.bord:SetColorTexture(0.31, 0.82, 0.41, r >= maxi and 1 or 0.7)
                c.rang:SetTextColor(0.31, 0.82, 0.41)
            elseif n.dispo == false or n.verrou then
                c.bord:SetColorTexture(0.35, 0.35, 0.35, 0.8)
                c.rang:SetTextColor(0.6, 0.6, 0.6)
            else
                c.bord:SetColorTexture(1, 0.82, 0, 0.9)
                c.rang:SetTextColor(1, 0.82, 0)
            end
            c.icone:SetAlpha((r == 0 and (n.dispo == false or n.verrou)) and 0.5 or 1)
            -- Le cadre du jeu : vert pris, jaune prenable, gris verrouille.
            local etat = (r > 0 and "green") or ((n.dispo == false or n.verrou) and "gray") or "yellow"
            local atlas = Atlas(n.choix and "choice" or "square", etat)
            if atlas then
                c.cadre:SetAtlas(atlas)
                c.cadre:Show()
                c.bord:Hide()
            else
                c.cadre:Hide()
                c.bord:Show()
            end
            if n.id then parId[n.id] = c end
            c.rang:SetText(r .. "/" .. maxi)
            local noeud = n
            c:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(noeud.nom or "?", 1, 0.82, 0)
                GameTooltip:AddLine(string.format(L.RANK_OF, tonumber(noeud.rang) or 0, tonumber(noeud.maxi) or 1), 1, 1, 1)
                if noeud.description then GameTooltip:AddLine(noeud.description, 0.9, 0.9, 0.9, true) end
                GameTooltip:Show()
            end)
            c:Show()
        end
        -- Les liens entre talents, comme dans le jeu.
        for _, n in ipairs(a.noeuds) do
            local depuis = n.id and parId[n.id]
            for _, cible in ipairs(n.liens or {}) do
                local vers = parId[cible]
                if depuis and vers then
                    nLien = nLien + 1
                    local l = Lien(contenu, nLien)
                    if l then
                        l:SetStartPoint("CENTER", depuis)
                        l:SetEndPoint("CENTER", vers)
                        if (tonumber(n.rang) or 0) > 0 then l:SetColorTexture(0.31, 0.82, 0.41, 0.9)
                        else l:SetColorTexture(0.5, 0.5, 0.5, 0.7) end
                        l:Show()
                    end
                end
            end
        end
        x = x + largeurArbre + ECART_ARBRES
        hauteurLigne = math.max(hauteurLigne, hauteurArbre)
    end
    return y + hauteurLigne + 8
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local function RendreArbres(contenu, p, index, y)
    local releve = p.releve
    if (p.niveau or 0) < NS.base.NIVEAU_HERITAGE then
        index = index + 1
        y = Poser(contenu, index, y, { texte = string.format(L.LOCKED_LEVEL, NS.base.NIVEAU_HERITAGE, p.niveau or 0),
            couleur = BLANC, multi = true })
    end
    if not releve or not releve.arbres or #releve.arbres == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { texte = (p.cle == NS.ClePersonnage()) and L.NO_DATA_HERE or L.NO_DATA_OTHER,
            couleur = BLANC, multi = true })
        return index, y
    end
    -- Bilan : points depenses sur ce personnage, et disponibles si le jeu le dit.
    local depenses, disponibles = 0, nil
    for _, a in ipairs(releve.arbres) do
        depenses = depenses + NS.base.Depenses(a)
        if a.disponibles then disponibles = a.disponibles end
    end
    index = index + 1
    y = Poser(contenu, index, y, { texte = string.format(L.POINTS_SPENT, depenses, NS.base.POINTS_MAX),
        droite = disponibles and string.format(L.POINTS_FREE, disponibles) or nil,
        couleurDroite = (disponibles or 0) > 0 and VERT or GRIS, apres = 4 })
    -- Des points a depenser, sur le personnage connecte : la fenetre du jeu.
    if (disponibles or 0) > 0 and p.cle == NS.ClePersonnage() then
        if not contenu.boutonHeritage then
            local b = CreateFrame("Button", nil, contenu, "UIPanelButtonTemplate")
            b:SetHeight(22)
            b:SetScript("OnClick", function()
                if not NS.OuvrirHeritageDuJeu() then NS.Dire(L.OPEN_LEGACY_FAIL) end
            end)
            contenu.boutonHeritage = b
        end
        local b = contenu.boutonHeritage
        b:SetText(L.OPEN_LEGACY)
        b:SetWidth((b:GetTextWidth() or 120) + 30)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", contenu, "TOPLEFT", 2, -y)
        b:Show()
        y = y + 30
    end
    if releve.quand then
        index = index + 1
        y = Poser(contenu, index, y, { texte = string.format(L.READ_ON, releve.quand), couleur = SECONDAIRE,
            apres = 4 })
    end
    -- Les arbres, comme dans le jeu : chaque talent a sa place (colonne et
    -- rangee), cote a cote tant que la largeur le permet.
    index = index + 1
    y = Titre(contenu, index, y, L.TREES_TITLE, true)
    y = DessinerArbres(contenu, releve.arbres, y + 4)
    return index, y
end

-- Un palier : la coche du jeu quand il est atteint, le sablier sinon.
local function CouleurDeClasse(classe)
    local c = _G.RAID_CLASS_COLORS and classe and _G.RAID_CLASS_COLORS[classe]
    if c then return { c.r, c.g, c.b } end
    return BLANC
end

-- Un palier : la coche du jeu quand il est atteint ; sinon ou en est le
-- plus avance, sur le palier (70/150).
local function Palier(fait, valeur, actuel)
    if fait then return "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t |cff4fd168" .. valeur .. "|r" end
    return "|cffffffff" .. (actuel or 0) .. "|r|cffb3b3b3/" .. valeur .. "|r"
end

local function Hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

-- Tous ceux qui avancent : le nom a la couleur de sa classe, la valeur en
-- clair. "Paltank 70   Elo 50"
local function Avancees(tous, gabarit)
    local morceaux = {}
    for k, t in ipairs(tous or {}) do
        if k > 6 then table.insert(morceaux, "...") break end
        table.insert(morceaux, string.format(gabarit, Hex(CouleurDeClasse(t.classe)) .. NS.NomCourt(t.cle) .. "|r",
            "|cffffd100" .. t.valeur .. "|r"))
    end
    return table.concat(morceaux, "     ")
end

local ICONES_METIERS = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving",
}

local function RendreDefis(contenu, index, y)
    local d = NS.base.Defis()
    index = index + 1
    y = Poser(contenu, index, y, { texte = L.CHALLENGES_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    index = index + 1
    y = Titre(contenu, index, y, L.CHALLENGES_CLASSES, true)
    for _, c in ipairs(d.classes) do
        local morceaux = {}
        for _, pal in ipairs(c.paliers) do table.insert(morceaux, Palier(pal.fait, pal.palier, c.meilleur and c.meilleur.niveau)) end
        local detail
        if c.meilleur then
            detail = Avancees(c.tous, L.CHAR_LEVEL_OF)
        else
            detail = L.NO_CLASS
        end
        local prochain
        for _, pal in ipairs(c.paliers) do if not pal.fait then prochain = pal.palier break end end
        local estMoi = c.meilleur and c.meilleur.cle == NS.ClePersonnage()
        local api = _G.QuestCoreAPI
        if prochain and c.meilleur then
            if estMoi and api and api.CreerProgression then
                detail = detail .. "   |cffffd100" .. L.CHALLENGE_CLICK_ROUTE .. "|r"
            elseif not estMoi then
                detail = detail .. "   " .. string.format(L.CHALLENGE_LOG_ON, NS.NomCourt(c.meilleur.cle))
            end
        end
        index = index + 1
        -- Meme retrait et meme place d'icone que les metiers : tout s'aligne.
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
            desature = not c.meilleur, texte = NomDeClasse(c.classe),
            couleur = c.meilleur and CouleurDeClasse(c.classe) or GRIS, droite = table.concat(morceaux, "     "),
            detail = detail, apres = 4 })
        local l = contenu.lignes[index]
        local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[c.classe]
        if coords then l.icone:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
        if prochain and estMoi and api and api.CreerProgression then
            l:EnableMouse(true)
            l:SetScript("OnClick", function()
                local ok, pc = pcall(api.CreerProgression)
                if ok and not pc then NS.Dire(L.CHALLENGE_ROUTE_NONE) end
            end)
        end
    end
    index = index + 1
    y = Titre(contenu, index, y + 6, L.CHALLENGES_TRADES, true)
    for _, m in ipairs(d.metiers) do
        local morceaux = {}
        for _, pal in ipairs(m.paliers) do table.insert(morceaux, Palier(pal.fait, pal.palier, m.meilleur and m.meilleur.rang)) end
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = ICONES_METIERS[m.ligne], desature = not m.meilleur,
            texte = NomDeMetier(m.ligne, m.nom), couleur = m.meilleur and BLANC or GRIS,
            droite = table.concat(morceaux, "     "),
            detail = m.meilleur and Avancees(m.tous, L.CHAR_SKILL_OF) or L.NO_TRADE,
            apres = 4 })
    end
    return index, y
end

local function RendrePersos(contenu, index, y)
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_CHARACTERS, true)
    local courant = NS.ClePersonnage()
    for _, p in ipairs(NS.base.Personnages()) do
        local debloque = (p.niveau or 0) >= NS.base.NIVEAU_HERITAGE
        local detail
        if p.releve and p.releve.arbres and #p.releve.arbres > 0 then
            local morceaux = {}
            local ORDRE = { aventure = 1, ressources = 2, metiers = 3 }
            local tries = {}
            for _, a in ipairs(p.releve.arbres) do if #(a.noeuds or {}) > 0 then table.insert(tries, a) end end
            table.sort(tries, function(u, v) return (ORDRE[u.genre] or 9) < (ORDRE[v.genre] or 9) end)
            for _, a in ipairs(tries) do
                table.insert(morceaux, (L[NOMS_ARBRES[a.genre] or ""] or "?") .. " |cffffffff" .. NS.base.Depenses(a) .. "|r")
            end
            detail = table.concat(morceaux, "     ")
        elseif debloque then
            detail = L.NO_DATA_OTHER
        else
            detail = string.format(L.LOCKED_LEVEL, NS.base.NIVEAU_HERITAGE, p.niveau or 0)
        end
        local temps = NS.base.TempsParNiveau(p.cle)
        if temps.total then detail = detail .. "     " .. string.format(L.PLAYED_TOTAL, NS.Duree(temps.total)) end
        index = index + 1
        local cle, perso = p.cle, p
        y = Poser(contenu, index, y + 2, { retrait = 4,
            visage = function(tex)
                PoserVisage(tex, perso, perso.cle == courant)
                tex:SetDesaturated(not debloque)
            end,
            texte = NS.NomCourt(p.cle) .. "  |cffb3b3b3" .. NomDeClasse(p.classe) .. "|r",
            police = "GameFontNormal", couleur = CouleurDeClasse(p.classe),
            droite = p.niveau and string.format(L.LEVEL, p.niveau) or "", couleurDroite = BLANC,
            bandeau = p.cle == etat.cle,
            detail = detail, apres = 6 })
        local l = contenu.lignes[index]
        l:EnableMouse(true)
        l:SetScript("OnClick", function()
            ChoisirPerso(cle)
            etat.page = "arbres"
            fen.Rendre()
        end)
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Chronologie : le temps passe sur chaque niveau, et le journal du compte
-- ---------------------------------------------------------------------------

local NIVEAU_MAX = 60
local HAUTEUR_HISTO = 96

local function Histogramme(contenu)
    if contenu.histo then return contenu.histo end
    local h = CreateFrame("Frame", nil, contenu)
    h.barres, h.reperes = {}, {}
    for n = 1, NIVEAU_MAX do
        local b = CreateFrame("Frame", nil, h)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetAllPoints()
        b.fond:SetColorTexture(1, 1, 1, 0)
        b.plein = b:CreateTexture(nil, "ARTWORK")
        b.plein:SetPoint("BOTTOMLEFT")
        b.plein:SetPoint("BOTTOMRIGHT")
        b:EnableMouse(true)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        h.barres[n] = b
    end
    -- Une ligne de base sous les colonnes, plutot que des fonds pleins.
    h.base = h:CreateTexture(nil, "ARTWORK")
    h.base:SetColorTexture(0.8, 0.65, 0.35, 0.5)
    h.base:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 15)
    h.base:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 15)
    h.base:SetHeight(1)
    for _, n in ipairs({ 1, 10, 20, 30, 40, 50, 60 }) do
        local t = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetText(tostring(n))
        h.reperes[n] = t
    end
    contenu.histo = h
    return h
end

local function DessinerHistogramme(contenu, p, y)
    local h = Histogramme(contenu)
    local largeur = contenu:GetWidth() or 760
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    h:SetSize(largeur, HAUTEUR_HISTO + 16)
    local t = NS.base.TempsParNiveau(p.cle)
    local plusLong = 1
    for _, s in pairs(t.durees) do plusLong = math.max(plusLong, s) end
    if t.enCours then plusLong = math.max(plusLong, t.enCours) end
    local pas = largeur / NIVEAU_MAX
    local niveauPerso = p.niveau or t.niveau or 1
    for n = 1, NIVEAU_MAX do
        local b = h.barres[n]
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", (n - 1) * pas + 1, 16)
        b:SetSize(math.max(2, pas - 2), HAUTEUR_HISTO)
        local duree = t.durees[n]
        local enCours = (n == niveauPerso) and t.enCours or nil
        local valeur = duree or enCours
        if valeur then
            b.plein:SetHeight(math.max(3, HAUTEUR_HISTO * valeur / plusLong))
            if enCours and not duree then b.plein:SetColorTexture(0.31, 0.82, 0.41, 0.9)
            else b.plein:SetColorTexture(1, 0.82, 0, 0.85) end
            b.plein:Show()
        elseif n < niveauPerso then
            -- Atteint, mais avant l'installation : inconnu.
            b.plein:SetHeight(3)
            b.plein:SetColorTexture(0.6, 0.6, 0.6, 0.6)
            b.plein:Show()
        else
            b.plein:Hide()
        end
        local niveau = n
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(string.format(L.LEVEL, niveau), 1, 0.82, 0)
            if duree then GameTooltip:AddLine(string.format(L.LEVEL_TIME, NS.Duree(duree)), 1, 1, 1)
            elseif enCours then GameTooltip:AddLine(string.format(L.LEVEL_TIME_NOW, NS.Duree(enCours)), 0.31, 0.82, 0.41)
            elseif niveau < niveauPerso then GameTooltip:AddLine(L.LEVEL_TIME_UNKNOWN, 0.6, 0.6, 0.6)
            else GameTooltip:AddLine(L.LEVEL_TIME_LATER, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:Show()
    end
    for n, rep in pairs(h.reperes) do
        rep:ClearAllPoints()
        rep:SetPoint("TOP", h, "BOTTOMLEFT", (n - 0.5) * pas, 14)
    end
    h:Show()
    return y + HAUTEUR_HISTO + 22, t
end

local function RendreChrono(contenu, p, index, y)
    if p then
        index = index + 1
        y = Titre(contenu, index, y, string.format(L.TIMELINE_LEVELS, NS.NomCourt(p.cle)), true)
        local t
        y, t = DessinerHistogramme(contenu, p, y + 4)
        -- En une ligne : le total, le niveau le plus long, la moyenne.
        local n, somme, long, niveauLong = 0, 0, 0, nil
        for niveau, s in pairs(t.durees) do
            n, somme = n + 1, somme + s
            if s > long then long, niveauLong = s, niveau end
        end
        local morceaux = {}
        if t.total then table.insert(morceaux, string.format(L.PLAYED_TOTAL, NS.Duree(t.total))) end
        if niveauLong then table.insert(morceaux, string.format(L.LONGEST_LEVEL, niveauLong, NS.Duree(long))) end
        if n > 0 then table.insert(morceaux, string.format(L.AVERAGE_LEVEL, NS.Duree(somme / n))) end
        index = index + 1
        y = Poser(contenu, index, y, { texte = #morceaux > 0 and table.concat(morceaux, "     ") or L.TIMELINE_NO_TIME,
            couleur = #morceaux > 0 and BLANC or SECONDAIRE, multi = true, apres = 2 })
        index = index + 1
        y = Poser(contenu, index, y, { texte = L.TIMELINE_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    end
    index = index + 1
    y = Titre(contenu, index, y, L.TIMELINE_ACCOUNT, true)
    local evenements = NS.base.Chronologie()
    if #evenements == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { texte = L.TIMELINE_EMPTY, couleur = SECONDAIRE, multi = true })
        return index, y
    end
    local jour
    local persos = {}
    for _, q in ipairs(NS.base.Personnages()) do persos[q.cle] = q end
    local temps = {}
    for k, e in ipairs(evenements) do
        if k > 150 then break end
        local ceJour = tostring(NS.Appeler(date, "%d/%m/%Y", e.quand) or "?")
        if ceJour ~= jour then
            jour = ceJour
            index = index + 1
            y = Poser(contenu, index, y + 6, { texte = ceJour, police = "GameFontNormalSmall", couleur = OR })
        end
        local detail
        if e.genre == "niveau" then
            temps[e.cle] = temps[e.cle] or NS.base.TempsParNiveau(e.cle)
            local avant = temps[e.cle].durees[(e.niveau or 0) - 1]
            if avant then detail = string.format(L.TIMELINE_TOOK, NS.Duree(avant), (e.niveau or 0) - 1) end
        end
        local q = persos[e.cle] or { cle = e.cle, classe = e.classe }
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
            texte = tostring(NS.Appeler(date, "%H:%M", e.quand) or "") .. "   " .. "|cff" .. string.format("%02x%02x%02x",
                math.floor(CouleurDeClasse(q.classe)[1] * 255), math.floor(CouleurDeClasse(q.classe)[2] * 255),
                math.floor(CouleurDeClasse(q.classe)[3] * 255)) .. NS.NomCourt(e.cle) .. "|r  "
                .. string.format(L.TIMELINE_LEVEL_UP, e.niveau or 0),
            couleur = BLANC, droite = detail, couleurDroite = SECONDAIRE })
        local l = contenu.lignes[index]
        local coords = _G.CLASS_ICON_TCOORDS and q.classe and _G.CLASS_ICON_TCOORDS[q.classe]
        if coords then l.icone:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else l.icone:Hide() end
    end
    return index, y
end

-- Les choix les plus repandus, d'apres les guides de la communaute.
local function RendreConseils(contenu, index, y)
    index = index + 1
    y = Poser(contenu, index, y, { texte = L.ADVICE_NOTE, couleur = SECONDAIRE, multi = true, apres = 4 })
    for _, bloc in ipairs(L.ADVICE) do
        index = index + 1
        y = Titre(contenu, index, y, bloc[1])
        for i = 2, #bloc do
            index = index + 1
            y = Poser(contenu, index, y, { retrait = RETRAIT, texte = bloc[i][1], couleur = BLANC, detail = bloc[i][2],
                apres = 2 })
        end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Bande des personnages
-- ---------------------------------------------------------------------------

PoserVisage = function(texture, p, estConnecte)
    texture:SetTexCoord(0, 1, 0, 1)
    if estConnecte and SetPortraitTexture and pcall(SetPortraitTexture, texture, "player") then return end
    local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
    if coords then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        return
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function CreerPortrait(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TAILLE_PORTRAIT, TAILLE_PORTRAIT)
    b.cadre = b:CreateTexture(nil, "BACKGROUND")
    b.cadre:SetAllPoints()
    b.cadre:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    b.visage = b:CreateTexture(nil, "ARTWORK")
    b.visage:SetPoint("TOPLEFT", 4, -4)
    b.visage:SetPoint("BOTTOMRIGHT", -4, 4)
    b.halo = b:CreateTexture(nil, "OVERLAY")
    b.halo:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.halo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.halo:SetBlendMode("ADD")
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function RendreBande(persos)
    local bande = cadre.bande
    local courant = NS.ClePersonnage()
    bande.boutons = bande.boutons or {}
    for _, b in ipairs(bande.boutons) do b:Hide() end
    for rang, p in ipairs(persos) do
        local b = bande.boutons[rang]
        if not b then
            b = CreerPortrait(bande)
            bande.boutons[rang] = b
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", bande, "LEFT", 2 + (rang - 1) * (TAILLE_PORTRAIT + 6), 0)
        PoserVisage(b.visage, p, p.cle == courant)
        -- Grise tant que le personnage n'a pas le niveau de l'heritage.
        b.visage:SetDesaturated((p.niveau or 0) < NS.base.NIVEAU_HERITAGE)
        b.halo:SetShown(p.cle == etat.cle)
        b:SetAlpha(p.cle == etat.cle and 1 or 0.7)
        local cle, perso = p.cle, p
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(NS.NomCourt(cle), 1, 0.82, 0)
            if perso.niveau then GameTooltip:AddLine(string.format(L.LEVEL, perso.niveau), 1, 1, 1) end
            if (perso.niveau or 0) < NS.base.NIVEAU_HERITAGE then
                GameTooltip:AddLine(string.format(L.LOCKED_LEVEL, NS.base.NIVEAU_HERITAGE, perso.niveau or 0), 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnClick", function()
            ChoisirPerso(cle)
            fen.Rendre()
        end)
        b:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function CreerLigneDeMenu(parent, icone)
    local b
    local ok, cree = pcall(CreateFrame, "Button", nil, parent, "OptionsListButtonTemplate")
    if ok and cree then b = cree end
    if not b then
        b = CreateFrame("Button", nil, parent)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    b:SetHeight(24)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.fond:SetBlendMode("ADD")
    b.fond:SetAllPoints()
    b.fond:Hide()
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(16, 16)
    b.icone:SetPoint("LEFT", b, "LEFT", 8, 0)
    b.icone:SetTexture(icone)
    local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
    if texte then
        texte:ClearAllPoints()
        texte:SetPoint("LEFT", b.icone, "RIGHT", 6, 0)
        texte:SetJustifyH("LEFT")
    end
    return b
end

local function MarquerMenu()
    for cle, b in pairs(cadre.boutonsMenu) do
        local choisi = cle == etat.page
        local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
        if texte then texte:SetFontObject(choisi and "GameFontHighlight" or "GameFontNormal") end
        b.fond:SetShown(choisi)
    end
end

local function Construire()
    cadre = NS.charte.Fenetre("LegacyCoreFenetre", LARGEUR, HAUTEUR, {})
    cadre:SetPoint("CENTER")
    cadre:Hide()
    table.insert(UISpecialFrames, "LegacyCoreFenetre")
    local portrait = cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait)
    if portrait then portrait:SetTexture("Interface\\Icons\\Spell_Holy_SealOfWisdom") end
    if cadre.titre then cadre.titre:SetText(L.TITLE) end

    local bande = CreateFrame("Frame", nil, cadre)
    bande:SetPoint("LEFT", cadre.entete, "LEFT", 0, 0)
    bande:SetPoint("RIGHT", cadre.entete, "RIGHT", 0, 0)
    bande:SetHeight(TAILLE_PORTRAIT + 4)
    cadre.bande = bande

    local menu = CreateFrame("Frame", nil, cadre)
    menu:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    menu:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    menu:SetWidth(LARGEUR_MENU)
    cadre.menu = menu
    local trait = cadre:CreateTexture(nil, "ARTWORK")
    trait:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    trait:SetWidth(1)
    trait:SetPoint("TOPLEFT", menu, "TOPRIGHT", ECART_MENU, 0)
    trait:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", ECART_MENU, 0)

    local fondMenu = cadre.fond:CreateTexture(nil, "BACKGROUND", nil, 5)
    fondMenu:SetPoint("TOPLEFT", cadre.fond, "TOPLEFT", 3, -3)
    fondMenu:SetPoint("BOTTOMRIGHT", trait, "BOTTOMLEFT", -1, -(NS.charte.MARGE - 3))
    fondMenu:Hide()
    cadre.fondMenu = fondMenu

    cadre.boutonsMenu = {}
    for rang, page in ipairs(PAGES) do
        local b = CreerLigneDeMenu(menu, page.icone)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(rang - 1) * 26)
        b:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
        if texte then texte:SetText(L[page.libelle]) end
        local cle = page.cle
        b:SetScript("OnClick", function()
            etat.page = cle
            fen.Rendre()
        end)
        cadre.boutonsMenu[cle] = b
    end

    local okD, defilement = pcall(CreateFrame, "ScrollFrame", nil, cadre, "ScrollFrameTemplate")
    if not okD or not defilement then
        defilement = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
    end
    defilement:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_MENU, 0)
    defilement:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", -18, 0)
    local contenu = CreateFrame("Frame", nil, defilement)
    contenu:SetSize(LARGEUR - LARGEUR_MENU - 2 * NS.charte.MARGE - 60, 1)
    defilement:SetScrollChild(contenu)
    cadre.contenu = contenu
    cadre.defilement = defilement

    NS.charte.Parchemin(cadre, { "TOPLEFT", trait, "TOPRIGHT", 2, NS.charte.MARGE - 4 },
        { "BOTTOMRIGHT", cadre.fond, "BOTTOMRIGHT", -4, 4 }, cadre.fond)

    local fermer = NS.charte.BoutonDePied(cadre, L.CLOSE, 110)
    fermer:SetScript("OnClick", function() cadre:Hide() end)

    if NS.suite then pcall(NS.suite.Entete, cadre, "LegacyCore", cadre.entete) end
    pcall(BrancherManette)
    cadre:SetScript("OnShow", function() fen.Rendre() end)
end

function fen.Rendre()
    if not cadre or not cadre:IsShown() then return end
    local ok, souci = pcall(function()
        local persos = NS.base.Personnages()
        SuivreLaSuite()
        local trouve = false
        for _, p in ipairs(persos) do if p.cle == etat.cle then trouve = true end end
        if not trouve then etat.cle = persos[1] and persos[1].cle end
        RendreBande(persos)
        MarquerMenu()
        if not cadre.fondMenu:IsShown() then pcall(NS.charte.FondDuJournal, cadre.fondMenu) end
        local parchemin = NS.charte.Fond() == "parchemin"
        if cadre.parchemin then cadre.parchemin.Montrer(parchemin) end

        local contenu = cadre.contenu
        for _, l in ipairs(contenu.lignes or {}) do
            l:Hide()
            l:SetScript("OnClick", nil)
            if l.icone then l.icone:SetTexCoord(0, 1, 0, 1) end
        end
        for _, c in ipairs(contenu.cases or {}) do c:Hide() end
        for _, l in ipairs(contenu.liens or {}) do l:Hide() end
        for _, t in ipairs(contenu.titresArbres or {}) do t:Hide() end
        if contenu.histo then contenu.histo:Hide() end
        if contenu.boutonHeritage then contenu.boutonHeritage:Hide() end
        local p = etat.cle and NS.base.Personnage(etat.cle)
        local index, y = 0, 0
        if cadre.titre then
            cadre.titre:SetText(L.TITLE .. (p and (" : " .. NS.NomCourt(p.cle)) or ""))
        end
        if etat.page == "defis" then
            index, y = RendreDefis(contenu, index, y)
        elseif etat.page == "persos" then
            index, y = RendrePersos(contenu, index, y)
        elseif etat.page == "conseils" then
            index, y = RendreConseils(contenu, index, y)
        elseif etat.page == "chrono" then
            index, y = RendreChrono(contenu, p, index, y)
        elseif p then
            index, y = RendreArbres(contenu, p, index, y)
        end
        contenu:SetHeight(math.max(y + 8, 1))
        NS.charte.Encrer(contenu, parchemin)
        if fen.ApresRendu then fen.ApresRendu() end
    end)
    if not ok then NS.base.NoterIncident("fenetre", souci) end
end

function fen.Ouvrir()
    if not cadre then Construire() end
    if not cadre:IsShown() then cadre:Show() end
end

function fen.Basculer()
    if not cadre then Construire() end
    if cadre:IsShown() then cadre:Hide() else cadre:Show() end
end

function fen.Cadre() return cadre end
function fen.Visible() return cadre and cadre:IsShown() end

-- ---------------------------------------------------------------------------
-- Manette, comme les autres add-ons de la suite
-- ---------------------------------------------------------------------------
--
--   LB / RB            page precedente / suivante
--   croix gauche/droite  personnage precedent / suivant
--   LT / RT            add-on voisin de la suite (onglets lateraux)
--   croix haut / bas   fait defiler la page
--   B                  fermer

local function ManetteActive()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

local GLYPHES = { PAD1 = { "A", "Cross" }, PAD2 = { "B", "Circle" }, PADLSHOULDER = { "LShoulder", "LShoulder", "LB" },
    PADRSHOULDER = { "RShoulder", "RShoulder", "RB" }, PADDUP = { "Up", "Up", "^" }, PADDDOWN = { "Down", "Down", "v" },
    PADDLEFT = { "Left", "Left", "<" }, PADDRIGHT = { "Right", "Right", ">" },
    PADLTRIGGER = { "LTrigger", "LTrigger", "LT" }, PADRTRIGGER = { "RTrigger", "RTrigger", "RT" },
    PADBACK = { "View", "Share", "Vue" },
    PADLSTICK = { "LStickIn", "LStickIn", "L3" }, PADRSTICK = { "RStickIn", "RStickIn", "R3" } }
local function Glyphe(touche)
    local g = GLYPHES[touche] or { touche }
    local info = NS.Lecture("C_Texture.GetAtlasInfo")
    if info then
        for _, nom in ipairs({ "Gamepad_Ltr_" .. g[1] .. "_64", "Gamepad_Shp_" .. (g[2] or g[1]) .. "_64",
            "Gamepad_Gen_" .. g[1] .. "_64" }) do
            local ok, existe = pcall(info, nom)
            if ok and existe then return "|A:" .. nom .. ":22:22|a" end
        end
    end
    return "|cffffd100" .. (g[3] or g[1]) .. "|r"
end

function fen.ApresRendu()
    local barre = cadre.barreManette
    if not barre then
        local ok, cree = pcall(CreateFrame, "Frame", nil, cadre, "TooltipBackdropTemplate")
        barre = ok and cree or CreateFrame("Frame", nil, cadre)
        barre:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 10, 2)
        barre:SetHeight(38)
        barre:SetFrameLevel(cadre:GetFrameLevel() + 10)
        barre.texte = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        barre.texte:SetPoint("LEFT", barre, "LEFT", 12, 0)
        cadre.barreManette = barre
    end
    if not ManetteActive() then barre:Hide() return end
    barre.texte:SetText(Glyphe("PADLSHOULDER") .. " " .. Glyphe("PADRSHOULDER") .. "  " .. L.PAD_PAGES .. "      "
        .. Glyphe("PADDLEFT") .. " " .. Glyphe("PADDRIGHT") .. "  " .. L.PAD_CHARS .. "      "
        .. Glyphe("PADDUP") .. " " .. Glyphe("PADDDOWN") .. "  " .. L.PAD_SCROLL .. "      "
        .. Glyphe("PADLSTICK") .. " " .. Glyphe("PADRSTICK") .. "  " .. L.PAD_SUITE .. "      "
        .. Glyphe("PAD2") .. "  " .. L.CLOSE)
    barre:SetWidth((barre.texte:GetStringWidth() or 400) + 24)
    barre:Show()
end

local function PageVoisine(pas)
    local index = 1
    for rang, page in ipairs(PAGES) do if page.cle == etat.page then index = rang end end
    local suivant = math.max(1, math.min(#PAGES, index + pas))
    if suivant == index then return end
    etat.page = PAGES[suivant].cle
    fen.Rendre()
end

local function PersoVoisin(pas)
    local persos = NS.base.Personnages()
    if #persos == 0 then return end
    local index = 1
    for rang, p in ipairs(persos) do if p.cle == etat.cle then index = rang end end
    ChoisirPerso(persos[((index - 1 + pas) % #persos) + 1].cle)
    fen.Rendre()
end

local function Defiler(sens)
    local d = cadre.defilement
    local maxi = math.max(0, (cadre.contenu:GetHeight() or 0) - (d:GetHeight() or 0))
    d:SetVerticalScroll(math.max(0, math.min(maxi, (d:GetVerticalScroll() or 0) + sens * 60)))
end

local function Traiter(bouton)
    local S = NS.suite
    if S and S.CurseurActif and S.CurseurActif(cadre) then
        if bouton == "PADDLEFT" then S.CurseurDeplacer(cadre, -1) return false end
        if bouton == "PADDRIGHT" then S.CurseurDeplacer(cadre, 1) return false end
        if bouton == "PAD1" then S.CurseurValider(cadre) return false end
        if bouton == "PAD2" then S.CurseurQuitter(cadre) return false end
        S.CurseurQuitter(cadre)
    end
    if bouton == "PADDRIGHT" then PersoVoisin(1) return false end
    if bouton == "PADDLEFT" then PersoVoisin(-1) return false end
    if bouton == "PADLSHOULDER" then PageVoisine(-1) return false end
    if bouton == "PADRSHOULDER" then PageVoisine(1) return false end
    if bouton == "PADDUP" then Defiler(-1) return false end
    if bouton == "PADDDOWN" then Defiler(1) return false end
    if bouton == "PAD2" then cadre:Hide() return false end
    return true
end

BrancherManette = function()
    if not cadre.EnableGamePadButton then return end
    if not pcall(cadre.EnableGamePadButton, cadre, true) then return end
    cadre:SetScript("OnGamePadButtonDown", function(_, bouton)
        -- Vue tenue + LB / RB : add-on voisin (la suite s'en charge).
        local S = NS.suite
        if S and S.ManetteBas then
            local okS, pris = pcall(S.ManetteBas, "LegacyCore", bouton)
            if okS and pris then return false end
        end
        local ok, laisser = pcall(Traiter, bouton)
        if not ok then NS.base.NoterIncident("manette", laisser) return true end
        return laisser
    end)
    pcall(cadre.SetScript, cadre, "OnGamePadButtonUp", function(_, bouton)
        local S = NS.suite
        if S and S.ManetteHaut then pcall(S.ManetteHaut, bouton) end
    end)
end
