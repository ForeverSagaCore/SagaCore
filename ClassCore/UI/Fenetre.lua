local _, NS = ...

-- La fenetre de ClassCore, comme celles de la suite : la barre des
-- personnages en haut (la meme partout : un clic montre ce personnage, sans
-- changer de personnage en jeu), le menu a gauche :
--   Ma classe        l'essentiel d'un coup d'oeil ;
--   Quetes de classe chaque suite de quetes, etape par etape, numerotee ;
--   Sorts de classe  tous les sorts du maitre, par arbre, rang, niveau, cout ;
--   Objets de classe reactifs, totems, fragments : sur soi et en banque ;
--   Familiers        (chasseurs du compte) les familles, chaque bete ;
--   Parametres.
--
-- Une seule regle de couleur partout (a l'encre sur le parchemin) :
--   vert   fait, appris ;
--   encre  a faire maintenant (le texte ordinaire) ;
--   gris   plus tard (niveau, etape d'avant, talent).

NS.fenetre = {}
local F = NS.fenetre
local T = NS.T
local E = function() return NS.etat end
local Q = function() return NS.quetes end

local HAUTEUR = 24
local RETRAIT = 16
local COCHE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local VERT = { 0.31, 0.82, 0.41 }
local GRIS = { 0.55, 0.55, 0.55 }
local NORMAL = { 1, 1, 1 }
local ROUGE = { 0.9, 0.3, 0.3 }
F.VERT, F.GRIS, F.NORMAL, F.ROUGE = VERT, GRIS, NORMAL, ROUGE

local function Su() return _G.CoreSuite end

-- ---------------------------------------------------------------------------
-- Le personnage montre
-- ---------------------------------------------------------------------------

local vue = { cle = nil }
F.vue = vue

local function ClesConnues()
    local l = {}
    local S = Su()
    for _, p in ipairs(S and S.ListePersos and S.ListePersos() or {}) do table.insert(l, p.cle) end
    return l
end

function F.Cle()
    local S = Su()
    if not vue.cle and S and S.Personnage then
        local c = S.Personnage()
        if c then vue.cle = c end
    end
    local moi = NS.ClePersonnage()
    if vue.cle then
        for _, c in ipairs(ClesConnues()) do if c == vue.cle then return vue.cle end end
    end
    return moi
end

function F.Profil()
    return Q().Profil(F.Cle())
end

local function ChoisirPerso(cle)
    vue.cle = cle
    local S = Su()
    if S and S.PoserPersonnage then pcall(S.PoserPersonnage, cle) end
    if NS.familiers and NS.familiers.Reinitialiser then NS.familiers.Reinitialiser() end
end

local function NomDeClasse(classe)
    local t = _G.LOCALIZED_CLASS_NAMES_MALE
    return (t and t[classe or ""]) or classe or ""
end
F.NomDeClasse = NomDeClasse

-- ---------------------------------------------------------------------------
-- Icones : rond de quete du jeu, ou icone carree a fin liseré
-- ---------------------------------------------------------------------------

local function AtlasExiste(nom)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(nom) ~= nil
end

-- Le rond du journal de quetes du jeu, comme dans QuestCore : fond
-- "UI-QuestPoi-QuestNumber", dessus le point d'exclamation (a prendre), le
-- symbole en cours, ou le point d'interrogation vert (faite). Gris : plus tard.
local function Rond(l, etat)
    local r = l.rond
    if not r then
        r = CreateFrame("Frame", nil, l)
        r:SetSize(18, 18)
        r.fond = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.fond:SetSize(24, 24)
        r.fond:SetPoint("CENTER")
        r.symbole = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.symbole:SetPoint("CENTER")
        l.rond = r
    end
    if AtlasExiste("UI-QuestPoi-QuestNumber") then
        r.fond:SetAtlas("UI-QuestPoi-QuestNumber")
        r.fond:Show()
    else
        r.fond:Hide()
    end
    local suite = etat == "niveau" or etat == "bloquee"
    if etat == "faite" and AtlasExiste("UI-QuestIcon-TurnIn-Normal") then
        r.symbole:SetAtlas("UI-QuestIcon-TurnIn-Normal")
        r.symbole:SetSize(24, 24)
    elseif etat == "cours" and AtlasExiste("Quest-In-Progress-Icon-yellow") then
        r.symbole:SetAtlas("Quest-In-Progress-Icon-yellow")
        r.symbole:SetSize(24, 24)
    else
        r.symbole:SetTexture(etat == "cours" and "Interface\\GossipFrame\\IncompleteQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
        r.symbole:SetTexCoord(0, 1, 0, 1)
        r.symbole:SetSize(12, 12)
    end
    r.symbole:SetDesaturated(etat == "faite" or suite)
    if etat == "faite" then r.symbole:SetVertexColor(0.3, 1, 0.3)
    elseif suite then r.symbole:SetVertexColor(0.55, 0.55, 0.55)
    else r.symbole:SetVertexColor(1, 1, 1) end
    r.fond:SetDesaturated(suite)
    return r
end

-- ---------------------------------------------------------------------------
-- Rendu commun : des blocs (titre de section, puis lignes)
-- ---------------------------------------------------------------------------

local function Titre(page, i)
    page.titres = page.titres or {}
    local t = page.titres[i]
    if t then return t end
    t = { fs = page.zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = page.zone:CreateTexture(nil, "ARTWORK"),
          droite = page.zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
    t.fs:SetJustifyH("LEFT")
    t.fs:SetWordWrap(false)
    t.droite:SetJustifyH("RIGHT")
    t.droite:SetWordWrap(false)
    page.titres[i] = t
    return t
end

local function Ligne(page, i)
    page.lignes = page.lignes or {}
    local l = page.lignes[i]
    if l then return l end
    l = CreateFrame("Button", nil, page.zone)
    l:SetHeight(HAUTEUR)
    pcall(l.RegisterForClicks, l, "LeftButtonUp")
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.bord = CreateFrame("Frame", nil, l)
    l.bord:SetSize(18, 18)
    l.icone = l.bord:CreateTexture(nil, "ARTWORK")
    l.icone:SetPoint("TOPLEFT", l.bord, "TOPLEFT", 1, -1)
    l.icone:SetPoint("BOTTOMRIGHT", l.bord, "BOTTOMRIGHT", -1, 1)
    l.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- L'encadrement des icones du jeu (boutons d'action, grimoire).
    do local S = _G.CoreSuite if S and S.HabillerIcone then pcall(S.HabillerIcone, l.bord, l.icone) end end
    l.coche = l:CreateTexture(nil, "OVERLAY")
    l.coche:SetSize(14, 14)
    l.coche:SetTexture(COCHE)
    l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.nom:SetJustifyH("LEFT")
    l.nom:SetWordWrap(false)
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetJustifyH("RIGHT")
    l.droite:SetWordWrap(false)
    l.bouton = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
    l.bouton:SetHeight(20)
    local fs = l.bouton.GetFontString and l.bouton:GetFontString()
    if fs then fs:SetFontObject("GameFontNormalSmall") end
    l.bouton:SetScript("OnClick", function(b) if b.action then pcall(b.action) end if F.w then pcall(F.w.Rendre) end end)
    l:SetScript("OnEnter", function(self)
        if not (self.infobulle and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(self.infobulle, GameTooltip)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    l:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    page.lignes[i] = l
    return l
end

-- Le cadre d'apercu 3D (familiers) : une seule fois par page.
local function Apercu(page)
    if page.apercu then return page.apercu end
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, page.zone)
    if not ok or not m then return nil end
    m:SetSize(220, 200)
    m.fond = m:CreateTexture(nil, "BACKGROUND")
    m.fond:SetAllPoints()
    m.fond:SetColorTexture(0, 0, 0, 0.55)
    m:EnableMouse(false)
    -- Le cadre des fenetres du jeu (bord metallique), autour de l'apercu.
    local okC, c = pcall(CreateFrame, "Frame", nil, m, "BackdropTemplate")
    if okC and c and c.SetBackdrop then
        c:SetPoint("TOPLEFT", m, "TOPLEFT", -6, 6)
        c:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 6, -6)
        c:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
        c:SetFrameLevel(m:GetFrameLevel() + 2)
        m.cadre = c
    end
    page.apercu = m
    return m
end

-- Colonnes alignees a droite (largeurs donnees par le bloc) : une police
-- par colonne, creee a la demande.
local function Colonne(porteur, cle, i)
    porteur[cle] = porteur[cle] or {}
    local fs = porteur[cle][i]
    if fs then return fs end
    local parent = porteur.CreateFontString and porteur or porteur.zone
    fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    porteur[cle][i] = fs
    return fs
end

-- Place les colonnes de droite a gauche ; rend la position x (depuis la
-- droite) ou s'arrete le texte de gauche.
local ECART_COL = 12
local function PoserColonnes(ancre, fontes, defs, textes, couleur)
    local x = -8
    for i = #defs, 1, -1 do
        local fs = fontes[i]
        fs:ClearAllPoints()
        fs:SetPoint("RIGHT", ancre, "RIGHT", x, 0)
        fs:SetWidth(defs[i].largeur)
        local t = textes[i]
        fs:SetText(type(t) == "table" and (t[1] or "") or (t or ""))
        local c = (type(t) == "table" and t[2]) or couleur or NORMAL
        fs:SetTextColor(c[1], c[2], c[3])
        fs.couleurPropre = nil
        fs:Show()
        x = x - defs[i].largeur - ECART_COL
    end
    return x
end

-- blocs : { { titre, droite, lignes = { ligne }, vide, apercu = { display, id, lignes = { textes } } } }
--         colonnes = { { titre, largeur } } : en-tete sous le titre, et
--         chaque ligne donne ses textes dans ligne.colonnes (texte ou { texte, couleur }).
-- ligne : { quete = etat | icone | coche, texte, droite, couleur, couleurDroite,
--           infobulle(tt), bouton = { texte, action }, clic, retrait }
local function Rendre(page, blocs)
    local zone = page.zone
    local largeur = zone:GetWidth() or 780
    for _, t in ipairs(page.titres or {}) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
    for _, l in ipairs(page.lignes or {}) do l:Hide() for _, fs in ipairs(l.cols or {}) do fs:Hide() end end
    page.entetes = page.entetes or {}
    for _, e in ipairs(page.entetes) do e.pris = false for _, fs in ipairs(e.cols or {}) do fs:Hide() end end
    if page.apercu then page.apercu:Hide() end
    for _, t in ipairs(page.textesApercu or {}) do t:Hide() end
    local y, nT, nL = 0, 0, 0
    for k, b in ipairs(blocs) do
        if k > 1 then y = y + 10 end
        if b.titre then
            nT = nT + 1
            local t = Titre(page, nT)
            t.fs:ClearAllPoints()
            t.fs:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            t.fs:SetPoint("RIGHT", zone, "RIGHT", -260, 0)
            t.fs:SetText(b.titre)
            t.droite:ClearAllPoints()
            t.droite:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -10, -y - 3)
            t.droite:SetWidth(250)
            t.droite:SetText(b.droite or "")
            t.filet:ClearAllPoints()
            t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
            t.filet:SetSize(largeur - 10, 1)
            if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet)
            else t.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
            t.fs:Show() t.filet:Show() t.droite:Show()
            y = y + 30
        end
        if b.colonnes then
            -- L'en-tete des colonnes : en legende, au-dessus des valeurs.
            local k2 = #page.entetes + 1
            for i2, e2 in ipairs(page.entetes) do if not e2.pris then k2 = i2 break end end
            local e = page.entetes[k2] or { zone = page.zone, ancre = CreateFrame("Frame", nil, page.zone) }
            page.entetes[k2] = e
            e.pris = true
            e.ancre:ClearAllPoints()
            e.ancre:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            e.ancre:SetPoint("RIGHT", zone, "RIGHT", -10, 0)
            e.ancre:SetHeight(16)
            local textes = {}
            for i, c in ipairs(b.colonnes) do Colonne(e, "cols", i) textes[i] = c.titre end
            PoserColonnes(e.ancre, e.cols, b.colonnes, textes, GRIS)
            y = y + 18
        end
        if b.apercu then
            local m = Apercu(page)
            if m then
                m:ClearAllPoints()
                m:SetPoint("TOPLEFT", zone, "TOPLEFT", RETRAIT + 6, -y - 8)
                local okM = false
                if b.apercu.display and m.SetDisplayInfo then okM = pcall(m.SetDisplayInfo, m, b.apercu.display) end
                if not okM and b.apercu.id and m.SetCreature then okM = pcall(m.SetCreature, m, b.apercu.id) end
                if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
                if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, 1.2) end
                if m.SetRotation then pcall(m.SetRotation, m, 0.6) end
                m:Show()
            end
            page.textesApercu = page.textesApercu or {}
            local yy = y + 10
            for i, txt in ipairs(b.apercu.lignes or {}) do
                local fs = page.textesApercu[i]
                if not fs then
                    fs = zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)
                    page.textesApercu[i] = fs
                end
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", zone, "TOPLEFT", RETRAIT + 252, -yy)
                fs:SetPoint("RIGHT", zone, "RIGHT", -10, 0)
                fs:SetText(txt[1] or "")
                local c = txt[2] or NORMAL
                fs:SetTextColor(c[1], c[2], c[3])
                fs.couleurPropre = nil
                fs:Show()
                yy = yy + 20
            end
            y = y + 226
        end
        for _, e in ipairs(b.lignes or {}) do
            nL = nL + 1
            local l = Ligne(page, nL)
            local x = RETRAIT + (e.retrait or 0)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            l:SetPoint("RIGHT", zone, "RIGHT", -10, 0)
            l.bord:ClearAllPoints()
            l.bord:SetPoint("LEFT", l, "LEFT", x, 0)
            if l.rond then l.rond:Hide() end
            l.bord:Hide() l.icone:Hide() l.coche:Hide()
            if e.quete then
                local r = Rond(l, e.quete)
                r:ClearAllPoints()
                r:SetPoint("LEFT", l, "LEFT", x, 0)
                r:Show()
                x = x + 24
            elseif e.icone then
                l.icone:SetTexture(e.icone)
                l.icone:SetDesaturated(e.gris and true or false)
                do local S = _G.CoreSuite if S and S.HabillerIcone then pcall(S.HabillerIcone, l.bord, l.icone, e.gris and true or false) end end
                l.bord:Show() l.icone:Show()
                x = x + 24
            elseif e.coche then
                l.coche:ClearAllPoints()
                l.coche:SetPoint("LEFT", l, "LEFT", x + 2, 0)
                l.coche:Show()
                x = x + 24
            end
            l.nom:ClearAllPoints()
            l.nom:SetPoint("LEFT", l, "LEFT", x, 0)
            local droiteX = -8
            if e.bouton then
                l.bouton:SetText(e.bouton.texte)
                local w = math.max(60, math.floor((l.bouton:GetTextWidth() or 40) + 24))
                l.bouton:SetWidth(w)
                l.bouton:ClearAllPoints()
                l.bouton:SetPoint("RIGHT", l, "RIGHT", -8, 0)
                l.bouton.action = e.bouton.action
                l.bouton:Show()
                droiteX = -8 - w - 8
            else
                l.bouton:Hide()
            end
            if b.colonnes and e.colonnes then
                for i = 1, #b.colonnes do Colonne(l, "cols", i) end
                droiteX = PoserColonnes(l, l.cols, b.colonnes, e.colonnes, e.couleur)
            end
            l.droite:ClearAllPoints()
            l.droite:SetPoint("RIGHT", l, "RIGHT", droiteX, 0)
            -- Sans texte a droite, le nom va jusqu'aux colonnes.
            l.droite:SetWidth((e.droite and e.droite ~= "") and (e.largeurDroite or 260) or 1)
            l.droite:SetText(e.droite or "")
            local cd = e.couleurDroite or e.couleur or NORMAL
            l.droite:SetTextColor(cd[1], cd[2], cd[3])
            l.droite.couleurPropre = nil
            l.nom:SetPoint("RIGHT", l.droite, "LEFT", -8, 0)
            l.nom:SetText(e.texte or "")
            local c = e.couleur or NORMAL
            l.nom:SetTextColor(c[1], c[2], c[3])
            l.nom.couleurPropre = nil
            l.infobulle = e.infobulle
            -- Une ligne avec infobulle se choisit aussi a la manette (son
            -- survol s'affiche) ; un clic ne fait que ce que la ligne dit.
            l:SetScript("OnClick", (e.infobulle or e.clic) and function()
                if e.clic then pcall(e.clic) if F.w then pcall(F.w.Rendre) end end
            end or nil)
            l:Show()
            y = y + HAUTEUR
        end
        if b.vide then
            nL = nL + 1
            local l = Ligne(page, nL)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            l:SetPoint("RIGHT", zone, "RIGHT", -10, 0)
            if l.rond then l.rond:Hide() end
            l.bord:Hide() l.icone:Hide() l.coche:Hide() l.bouton:Hide()
            l.nom:ClearAllPoints()
            l.nom:SetPoint("LEFT", l, "LEFT", RETRAIT, 0)
            l.nom:SetPoint("RIGHT", l, "RIGHT", -8, 0)
            l.nom:SetText(b.vide)
            l.nom:SetTextColor(GRIS[1], GRIS[2], GRIS[3])
            l.nom.couleurPropre = nil
            l.droite:SetText("")
            l.infobulle = nil
            l:SetScript("OnClick", nil)
            l:Show()
            y = y + HAUTEUR
        end
    end
    return y
end
F.RendreBlocs = Rendre

-- Une page de blocs : titre, explication, puis les blocs.
local function Page(cle, icone, libelle, titre, intro, blocs)
    return { cle = cle, icone = icone, libelle = libelle,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(36)
            page.zone = O.Rangee(20)
            page.yZone = page.y - 20
        end,
        rendre = function(page)
            page.t1:SetText(titre())
            page.intro:SetText(intro())
            local h = Rendre(page, blocs(page))
            page.zone:SetHeight(math.max(h, 20))
            page.hauteur = page.yZone + math.max(h, 20)
        end }
end
F.Page = Page

-- ---------------------------------------------------------------------------
-- Les quetes
-- ---------------------------------------------------------------------------

local function Guider(ids)
    local api = _G.QuestCoreAPI
    if api and api.GuiderQuetes and #ids > 0 then return api.GuiderQuetes(ids) end
end

local function CouleurEtape(etat)
    if etat == "faite" then return VERT end
    if etat == "cours" or etat == "prendre" then return NORMAL end
    return GRIS
end

local function InfobulleEtape(e, c)
    return function(tt)
        tt:AddLine(e.nom)
        if c then tt:AddLine(string.format(T("%s, étape %d sur %d", "%s, step %d of %d"), c.titre, e.numero or 1, c.total), 1, 1, 1) end
        tt:AddLine(Q().LibelleEtat(e), 0.9, 0.9, 0.9)
        if (e.niveau or 0) > 0 then tt:AddLine(string.format(T("Quête de niveau %d", "Level %d quest"), e.niveau), 0.8, 0.8, 0.8) end
        local d = Q().Donneur(e.id)
        if d then tt:AddLine(string.format(T("Donnée par %s", "Given by %s"), d), 0.8, 0.8, 0.8) end
    end
end

local function ChargementQuetes()
    if not Q().BaseDisponible() then
        return T("Il faut QuestieDB, la base de quêtes : installe-le avec la suite.", "QuestieDB, the quest database, is needed : install it with the suite.")
    end
    if not Q().Pret() then
        Q().Indexer()
        Q().QuandPret(function() if F.w then pcall(F.w.Rendre) end end)
        return T("Lecture de la base de quêtes...", "Reading the quest database...")
    end
    return nil
end

local function BlocsQuetes()
    local attente = ChargementQuetes()
    if attente then return { { titre = T("Quêtes de classe", "Class quests"), vide = attente } } end
    local p = F.Profil()
    local chaines = Q().Chaines(p, p and p.connecte)
    local blocs, finies = {}, {}
    for _, c in ipairs(chaines) do
        if c.etat == "faite" then
            table.insert(finies, { quete = "faite", texte = c.titre, couleur = VERT,
                droite = c.total == 1 and T("Faite", "Done") or string.format(T("%d étapes faites", "%d steps done"), c.total),
                infobulle = function(tt)
                    tt:AddLine(c.titre)
                    for _, e in ipairs(c.etapes) do tt:AddLine(string.format("%d. %s", e.numero or 0, e.nom), 0.31, 0.82, 0.41) end
                end })
        else
            local b = { titre = c.titre, lignes = {},
                droite = c.total == 1 and string.format(T("Quête de niveau %d", "Level %d quest"), c.niveau)
                    or string.format(c.faites <= 1 and T("Suite de %d quêtes, %d faite", "Chain of %d quests, %d done") or T("Suite de %d quêtes, %d faites", "Chain of %d quests, %d done"), c.total, c.faites) }
            local aGuider = Q().AGuider(c)
            local guidable = p and p.connecte and #aGuider > 0 and _G.QuestCoreAPI and _G.QuestCoreAPI.GuiderQuetes
            local bouton = false
            for _, e in ipairs(c.etapes) do
                local l = { quete = e.etat, couleur = CouleurEtape(e.etat), droite = Q().LibelleEtat(e),
                    texte = c.total > 1 and string.format("%d. %s", e.numero or 0, e.nom) or e.nom,
                    infobulle = InfobulleEtape(e, c.total > 1 and c or nil) }
                if not bouton and guidable and (e.etat == "cours" or e.etat == "prendre") then
                    l.bouton = { texte = T("Guider", "Guide"), action = function() Guider(aGuider) end }
                    bouton = true
                end
                table.insert(b.lignes, l)
            end
            table.insert(blocs, b)
        end
    end
    if #finies > 0 then
        table.insert(blocs, { titre = T("Quêtes de classe terminées", "Finished class quests"),
            droite = string.format(#finies == 1 and T("%d suite", "%d chain") or T("%d suites", "%d chains"), #finies), lignes = finies })
    end
    if #blocs == 0 then table.insert(blocs, { titre = T("Quêtes de classe", "Class quests"), vide = T("Aucune quête de classe connue pour ce personnage.", "No class quest known for this character.") }) end
    return blocs
end

-- ---------------------------------------------------------------------------
-- Sorts
-- ---------------------------------------------------------------------------

-- Une ligne par rang, dans l'ordre d'apprentissage : niveau, cout,
-- maniere de l'apprendre et etat, en colonnes.
local COLONNES_SORTS = {
    { titre = T("Niveau", "Level"), largeur = 50 },
    { titre = T("Coût", "Cost"), largeur = 100 },
    { titre = T("Apprentissage", "Learned from"), largeur = 110 },
    { titre = T("État", "Status"), largeur = 90 },
}

local function LignesDeSort(g, p, sortie)
    local nom, icone = NS.sorts.NomIcone(g)
    if not nom then return 0, 0, 0 end
    local total = #g.rangs
    -- Un rang superieur connu vaut pour les rangs d'avant.
    local dernierConnu = 0
    for i, r in ipairs(g.rangs) do if p.connait(r.id) then dernierConnu = i end end
    local appris, aApprendre, cout = 0, 0, 0
    for i, r in ipairs(g.rangs) do
        local connu = i <= dernierConnu
        local niveauOk = (p.niveau or 1) >= r.niveau
        local etat, couleur
        if connu then etat, couleur = T("Appris", "Learned"), VERT appris = appris + 1
        elseif niveauOk then etat, couleur = T("À apprendre", "To learn"), NORMAL aApprendre = aApprendre + 1
            if not r.quete then cout = cout + (r.cout or 0) end
        else etat, couleur = T("Plus tard", "Later"), GRIS end
        local parTalent = r.talent and (tonumber(r.cout) or 0) == 0
        local source = parTalent and T("Talent", "Talent") or (r.quete and T("Quête de classe", "Class quest")) or T("Maître", "Trainer")
        local prix = (parTalent or r.quete) and "" or NS.sorts.Cout(r.cout)
        local rangN = r.rang and r.rang > 0 and r.rang or i
        local texte = total > 1 and string.format(T("%s (rang %d)", "%s (rank %d)"), nom, rangN) or nom
        table.insert(sortie, { icone = icone, gris = not connu, texte = texte, couleur = couleur, niveau = r.niveau, nomTri = nom, rangTri = rangN,
            colonnes = { tostring(r.niveau), prix, source, etat },
            infobulle = function(tt)
                if tt.SetSpellByID then pcall(tt.SetSpellByID, tt, r.id) end
                if tt:NumLines() == 0 then tt:AddLine(texte) end
            end })
    end
    return appris, total, cout
end

local function BlocsSorts()
    local p = F.Profil()
    if not p then return {} end
    local liste = NS.sorts.Liste(p.classe)
    if not p.releve then
        return { { titre = T("Sorts de classe", "Class spells"), vide = T("Connecte ce personnage une fois pour relever ses sorts.", "Log in this character once to read its spells.") } }
    end
    if #liste == 0 then
        return { { titre = T("Sorts de classe", "Class spells"), vide = T("Pas de liste de sorts pour cette classe.", "No spell list for this class.") } }
    end
    local parArbre, ordre = {}, {}
    for _, g in ipairs(liste) do
      if NS.sorts.PourProfil(g, p) then
        local a = g.arbre or "General"
        if not parArbre[a] then parArbre[a] = { lignes = {}, appris = 0, total = 0 } table.insert(ordre, a) end
        local b = parArbre[a]
        local ap, tot = LignesDeSort(g, p, b.lignes)
        b.appris, b.total = b.appris + ap, b.total + tot
      end
    end
    -- Le general (armures, armes) en dernier.
    for i, a in ipairs(ordre) do if a == "General" then table.remove(ordre, i) table.insert(ordre, a) break end end
    local blocs = {}
    -- Les maitres les plus proches (connecte seulement) : sur la carte de
    -- MapCore s'il est la, sinon le guidage de la suite.
    if p.connecte and NS.maitres then
        local M = NS.maitres
        local lignes = {}
        for _, c in ipairs({ p.classe, p.classe == "HUNTER" and "PET" or nil }) do
            local pt = M.PlusProche(c)
            local libelle = c == "PET" and T("Maître des familiers le plus proche", "Nearest pet trainer") or T("Maître de classe le plus proche", "Nearest class trainer")
            local bouton
            if pt and M.AvecMapCore() then
                bouton = { texte = T("Voir sur la carte", "Show on map"), action = function() M.Montrer(pt) end }
            elseif pt then
                bouton = { texte = M.EstGuide(c) and T("Arrêter", "Stop") or T("Guider", "Guide"), action = function() M.Basculer(c) end }
            end
            local icone = c == "PET" and "Interface\\Icons\\Ability_Hunter_BeastCall" or (NS.classes.ICONE and NS.classes.ICONE[c]) or "Interface\\Icons\\INV_Misc_Book_09"
            table.insert(lignes, { icone = icone, texte = libelle, couleur = NORMAL,
                droite = pt and (pt.nom .. (pt.zone and (", " .. pt.zone) or "")) or T("Aucun sur ce continent", "None on this continent"),
                couleurDroite = pt and NORMAL or GRIS, largeurDroite = 260, bouton = bouton })
        end
        table.insert(blocs, { titre = T("Où apprendre", "Where to learn"), lignes = lignes })
    end
    for _, a in ipairs(ordre) do
        local b = parArbre[a]
        table.sort(b.lignes, function(x, y)
            if x.niveau ~= y.niveau then return x.niveau < y.niveau end
            if x.nomTri ~= y.nomTri then return x.nomTri < y.nomTri end
            return x.rangTri < y.rangTri
        end)
        if #b.lignes > 0 then
            table.insert(blocs, { titre = NS.sorts.NomArbre(a), lignes = b.lignes, colonnes = COLONNES_SORTS,
                droite = string.format(b.appris > 1 and T("%d rangs appris sur %d", "%d of %d ranks learned") or T("%d rang appris sur %d", "%d of %d rank learned"), b.appris, b.total) })
        end
    end
    return blocs
end

-- ---------------------------------------------------------------------------
-- Objets
-- ---------------------------------------------------------------------------

local function LigneObjet(o, p)
    local nom, icone = E().Objet(o.id)
    if not nom then return nil end
    local sacs, banque = p.compte(o.id)
    local bas = (o.seuil or 0) > 0 and sacs < o.seuil
    local droite = banque > 0 and string.format(T("%d sur toi, %d en banque", "%d on you, %d in bank"), sacs, banque)
        or string.format(T("%d sur toi", "%d on you"), sacs)
    return { icone = icone, texte = nom, droite = droite, couleur = NORMAL, couleurDroite = bas and ROUGE or NORMAL,
        infobulle = function(tt)
            if tt.SetItemByID then pcall(tt.SetItemByID, tt, o.id) else tt:AddLine(nom) end
            if (o.seuil or 0) > 0 then tt:AddLine(string.format(T("Conseillé : %d sur toi", "Advised : %d on you"), o.seuil), 1, 0.82, 0) end
        end }
end

local function ObjetsUtiles(p)
    local res = {}
    for _, o in ipairs(E().Donnees(p.classe).objets or {}) do
        if (p.niveau or 1) >= (o.niveau or 1) and (not o.jusqua or (p.niveau or 1) <= o.jusqua) then table.insert(res, o) end
    end
    return res
end

local function BlocsObjets()
    local p = F.Profil()
    if not p then return {} end
    local b = { titre = T("Sur toi et en banque", "On you and in bank"), lignes = {} }
    if p.releve then
        for _, o in ipairs(ObjetsUtiles(p)) do
            local l = LigneObjet(o, p)
            if l then table.insert(b.lignes, l) end
        end
    end
    if p.connecte and p.classe == "HUNTER" then
        local n, icone = E().Munitions()
        if n then
            table.insert(b.lignes, 1, { icone = icone or "Interface\\Icons\\INV_Ammo_Arrow_02", texte = T("Munitions équipées", "Equipped ammo"),
                droite = tostring(n), couleurDroite = n < 200 and ROUGE or NORMAL })
        end
    end
    local blocs = { b }
    local plusTard = { titre = T("Plus tard", "Later"), lignes = {} }
    for _, o in ipairs(E().Donnees(p.classe).objets or {}) do
        if (p.niveau or 1) < (o.niveau or 1) then
            local nom, icone = E().Objet(o.id)
            if nom then
                table.insert(plusTard.lignes, { icone = icone, gris = true, texte = nom, couleur = GRIS,
                    droite = string.format(T("Niveau %d", "Level %d"), o.niveau), couleurDroite = GRIS,
                    infobulle = function(tt) if tt.SetItemByID then pcall(tt.SetItemByID, tt, o.id) end end })
            end
        end
    end
    if #b.lignes == 0 then
        b.vide = p.releve and T("Aucun objet de classe à ce niveau.", "No class item at this level.")
            or T("Connecte ce personnage une fois pour relever ses objets.", "Log in this character once to read its items.")
    end
    if #plusTard.lignes > 0 then table.insert(blocs, plusTard) end
    return blocs
end

-- ---------------------------------------------------------------------------
-- Ma classe : l'essentiel
-- ---------------------------------------------------------------------------

local function BlocsClasse()
    local p = F.Profil()
    if not p then return {} end
    local blocs = {}
    -- Quetes a faire maintenant
    local bq = { titre = T("Quêtes de classe à faire", "Class quests to do"), lignes = {} }
    local attente = ChargementQuetes()
    if attente then bq.vide = attente
    else
        local r = Q().Resume(p, p.connecte)
        bq.droite = string.format(r.finies <= 1 and T("%d suite finie sur %d", "%d of %d chains finished") or T("%d suites finies sur %d", "%d of %d chains finished"), r.finies, r.total)
        for i, c in ipairs(r.maintenant) do
            if i > 6 then break end
            local suivante
            for _, e in ipairs(c.etapes) do if e.etat == "cours" or e.etat == "prendre" then suivante = e break end end
            local aGuider = Q().AGuider(c)
            local l = { quete = c.etat == "cours" and "cours" or "prendre", texte = c.titre, couleur = NORMAL,
                droite = c.total > 1 and string.format(T("Étape %d sur %d", "Step %d of %d"), suivante and suivante.numero or c.faites + 1, c.total)
                    or (c.etat == "cours" and T("En cours", "In progress") or T("À prendre", "Available")),
                clic = function() if F.w then F.w.page = "quetes" end end,
                infobulle = function(tt)
                    tt:AddLine(c.titre)
                    for _, e in ipairs(c.etapes) do
                        local col = CouleurEtape(e.etat)
                        tt:AddDoubleLine(string.format("%d. %s", e.numero or 0, e.nom), Q().LibelleEtat(e), col[1], col[2], col[3], col[1], col[2], col[3])
                    end
                end }
            if p.connecte and #aGuider > 0 and _G.QuestCoreAPI and _G.QuestCoreAPI.GuiderQuetes then
                l.bouton = { texte = T("Guider", "Guide"), action = function() Guider(aGuider) end }
            end
            table.insert(bq.lignes, l)
        end
        if #bq.lignes == 0 then bq.vide = T("Rien à prendre pour le moment.", "Nothing to take for now.") end
    end
    table.insert(blocs, bq)
    -- Sorts a apprendre maintenant : un resume (la liste est dans Sorts de classe).
    local bs = { titre = T("Chez le maître", "At the trainer"), lignes = {} }
    if p.releve then
        local total, n, icone = 0, 0, nil
        for _, g in ipairs(NS.sorts.Liste(p.classe)) do
            if NS.sorts.PourProfil(g, p) then
                local etat, _, _, _, cout = NS.sorts.Etat(g, p)
                if etat == "apprendre" then
                    n = n + 1
                    total = total + (cout or 0)
                    if not icone then local _, ic = NS.sorts.NomIcone(g) icone = ic end
                end
            end
        end
        if n > 0 then
            table.insert(bs.lignes, { icone = icone, texte = string.format(n == 1 and T("%d sort à apprendre", "%d spell to learn") or T("%d sorts à apprendre", "%d spells to learn"), n),
                droite = NS.sorts.Cout(total), clic = function() if F.w then F.w.page = "sorts" end end,
                infobulle = function(tt) tt:AddLine(T("Le détail est dans Sorts de classe.", "Details in Class spells.")) end })
        else
            bs.vide = T("Tout est appris pour ce niveau.", "Everything is learned for this level.")
        end
    else
        bs.vide = T("Connecte ce personnage une fois pour relever ses sorts.", "Log in this character once to read its spells.")
    end
    table.insert(blocs, bs)
    -- Objets
    if p.releve then
        local bo = { titre = T("Objets de classe", "Class items"), lignes = {} }
        for _, o in ipairs(ObjetsUtiles(p)) do
            local l = LigneObjet(o, p)
            if l then table.insert(bo.lignes, l) end
        end
        if #bo.lignes > 0 then table.insert(blocs, bo) end
    end
    if p.connecte and p.classe == "HUNTER" and NS.familiers then
        local b = NS.familiers.BlocMonFamilier()
        if b then table.insert(blocs, b) end
    end
    if p.connecte and p.classe == "DRUID" then
        local n = E().FormesRestantes()
        table.insert(blocs, { titre = T("Changements de forme", "Shapeshifts"), lignes = { {
            icone = select(2, E().Sort(768)) or select(2, E().Sort(5487)),
            texte = T("Possibles avec ta mana", "Possible with your mana"),
            droite = n and tostring(n) or T("Hors combat", "Out of combat"), couleurDroite = (n and n < 1) and ROUGE or NORMAL } } })
    end
    return blocs
end

local function NomDuPerso()
    local cle = F.Cle() or ""
    return cle:match("^(.-) %- ") or cle
end

local function PageClasse()
    return Page("classe", "Interface\\Icons\\INV_Misc_Book_09",
        function() return T("Ma classe", "My class") end,
        function()
            local p = F.Profil() or {}
            local c, n = NomDeClasse(p.classe), p.niveau or 1
            return T(string.format("%s, %s de niveau %d", NomDuPerso(), c, n), string.format("%s, level %d %s", NomDuPerso(), n, c))
        end,
        function() return T("Les quêtes de classe à faire maintenant, les sorts à apprendre chez le maître et ce qu'il faut avoir sur soi.",
            "Class quests to do now, spells to learn at the trainer and what to carry.") end,
        BlocsClasse)
end

local function PageQuetes()
    return Page("quetes", "Interface\\Icons\\INV_Misc_Book_08",
        function() return T("Quêtes de classe", "Class quests") end,
        function() return string.format(T("Les quêtes de classe de %s", "%s's class quests"), NomDuPerso()) end,
        function() return T("Chaque suite de quêtes de la classe, étape par étape. En vert : fait. Texte normal : à faire maintenant. En gris : plus tard.",
            "Every class quest chain, step by step. Green : done. Normal text : to do now. Grey : later.") end,
        BlocsQuetes)
end

local function PageSorts()
    return Page("sorts", "Interface\\Icons\\INV_Misc_Book_11",
        function() return T("Sorts de classe", "Class spells") end,
        function() return string.format(T("Les sorts de %s", "%s's spells"), NomDuPerso()) end,
        function() return T("Chaque rang de sort, par arbre, dans l'ordre où il s'apprend. En vert : appris. Texte normal : à apprendre maintenant. En gris : plus tard.",
            "Every spell rank, by tree, in learning order. Green : learned. Normal text : to learn now. Grey : later.") end,
        BlocsSorts)
end

local function PageObjets()
    return Page("objets", "Interface\\Icons\\INV_Misc_Bag_10",
        function() return T("Objets de classe", "Class items") end,
        function() return string.format(T("Ce que %s doit avoir sur soi", "What %s should carry"), NomDuPerso()) end,
        function() return T("Réactifs et objets de classe : combien sur soi, combien en banque. En rouge sous la quantité conseillée.",
            "Reagents and class items : how many on you, how many in the bank. Red below the advised amount.") end,
        BlocsObjets)
end

-- ---------------------------------------------------------------------------
-- Parametres
-- ---------------------------------------------------------------------------

local function PageReglages()
    return { cle = "reglages", icone = "Interface\\Icons\\INV_Misc_Gear_01",
        libelle = function() return T("Paramètres", "Settings") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.rBadge = O.Rangee()
            page.cBadge = O.Case(page.rBadge, function(oui) NS.badge.Reglages().badge = oui and true or false pcall(NS.badge.Actualiser) end)
            page.cBadge:SetPoint("RIGHT", page.rBadge, "RIGHT", -8, 0)
            page.dBadge = O.Detail(28)
            page.rMarchand = O.Rangee()
            page.cMarchand = O.Case(page.rMarchand, function(oui) NS.base.ReglagesGeneraux().marchand = oui and true or false end)
            page.cMarchand:SetPoint("RIGHT", page.rMarchand, "RIGHT", -8, 0)
            page.dMarchand = O.Detail(28)
        end,
        rendre = function(page)
            page.t1:SetText(T("Affichage", "Display"))
            page.rBadge.nom:SetText(T("Pastille de classe sous ton portrait", "Class badge under your portrait"))
            page.cBadge:SetChecked(NS.badge.Reglages().badge ~= false)
            page.dBadge:SetText(T("Fragments d'âme, munitions, runes, ankhs, ou changements de forme possibles : en rouge quand il en manque.",
                "Soul shards, ammo, runes, ankhs, or shapeshifts left : red when running low."))
            page.rMarchand.nom:SetText(T("Rappel chez le marchand quand un réactif manque", "Reminder at the vendor when a reagent runs low"))
            page.cMarchand:SetChecked(NS.base.ReglagesGeneraux().marchand ~= false)
            page.dMarchand:SetText(T("Une ligne dans ta discussion (toi seul). Rien n'est acheté.", "One line in your chat (only you). Nothing is bought."))
        end }
end

local ADRESSE_SUITE = "https://www.curseforge.com/projects/1817365"
local function PageSuite()
    return { cle = "suite", icone = "Interface\\Icons\\INV_Misc_Book_11",
        libelle = function() return T("La suite", "The suite") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(70)
            page.rLien = O.Rangee(28)
            local e = CreateFrame("EditBox", nil, page.rLien, "InputBoxTemplate")
            e:SetSize(420, 24)
            e:SetPoint("LEFT", page.rLien, "LEFT", 6, 0)
            e:SetAutoFocus(false)
            e:SetText(ADRESSE_SUITE)
            e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            e:SetScript("OnTextChanged", function(self, parUtilisateur) if parUtilisateur then self:SetText(ADRESSE_SUITE) self:HighlightText() end end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            table.insert(page.focus, e)
        end,
        rendre = function(page)
            page.t1:SetText("Forever SagaCore")
            page.intro:SetText(T("ClassCore fait partie de Forever SagaCore, une suite d'add-ons pour WoW Forever. Installés ensemble, ils partagent la même fenêtre, les mêmes réglages et la même manette.",
                "ClassCore is part of Forever SagaCore, a suite of add-ons for WoW Forever. Installed together, they share one window, the same settings and the same gamepad controls."))
            page.rLien.nom:SetText("")
        end }
end

-- ---------------------------------------------------------------------------
-- La fenetre
-- ---------------------------------------------------------------------------

local TAILLE_PORTRAIT = 30
local function RendreBande()
    local w = F.w
    local S = Su()
    if not (w and w.bande and S and S.BandePersos) then return end
    local cles = S.BandePersos(w.bande, { choisi = F.Cle(), auClic = function(cle)
        ChoisirPerso(cle)
        if F.w then F.w.Rendre() end
    end })
    w.bande.ordre = cles
end

-- Croix gauche / droite (hors de la page) : personnage precedent / suivant.
local function Manette(bouton)
    if bouton ~= "PADDLEFT" and bouton ~= "PADDRIGHT" then return false end
    local ordre = F.w and F.w.bande and F.w.bande.ordre or {}
    if #ordre < 2 then return true end
    local actuel = F.Cle()
    local rang = 1
    for i, c in ipairs(ordre) do if c == actuel then rang = i end end
    rang = rang + (bouton == "PADDRIGHT" and 1 or -1)
    if rang < 1 then rang = #ordre elseif rang > #ordre then rang = 1 end
    ChoisirPerso(ordre[rang])
    if F.w then F.w.Rendre() end
    return true
end

local function AvecChasseur()
    if E().Classe() == "HUNTER" then return true end
    local S = Su()
    for _, p in ipairs(S and S.ListePersos and S.ListePersos() or {}) do if p.classe == "HUNTER" then return true end end
    for _, p in pairs(Q().Persos()) do if type(p) == "table" and p.classe == "HUNTER" then return true end end
    return false
end

function F.Construire()
    local S = Su()
    if F.w or not (S and S.FenetreAPages) then return F.w end
    local pages = { PageClasse(), PageQuetes(), PageSorts() }
    if NS.talents then table.insert(pages, NS.talents.Page()) table.insert(pages, NS.talents.PageSimulateur()) end
    table.insert(pages, PageObjets())
    if NS.familiers and AvecChasseur() then table.insert(pages, NS.familiers.Page(Page)) end
    table.insert(pages, PageReglages())
    if S.Seul and S.Seul() then table.insert(pages, PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "ClassCoreFenetre", cle = "ClassCore", icone = NS.classes.ICONE[E().Classe() or ""] or "Interface\\Icons\\INV_Misc_Book_09",
        titre = function() return T("ClassCore (bêta)", "ClassCore (beta)") end,
        pages = pages,
        manette = Manette,
    })
    local w = F.w
    if w and w.cadre then
        local cadre = w.cadre
        local bande = CreateFrame("Frame", nil, cadre)
        bande:SetPoint("LEFT", cadre.entete or cadre, "LEFT", 0, 0)
        bande:SetPoint("RIGHT", cadre.entete or cadre, "RIGHT", 0, 0)
        bande:SetHeight(TAILLE_PORTRAIT + 4)
        w.bande = bande
        local rendre = w.Rendre
        w.Rendre = function(...)
            pcall(RendreBande)
            return rendre(...)
        end
    end
    return w
end

function F.Ouvrir()
    local S = Su()
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("ClassCore") return true end
    return false
end

function F.Actualiser()
    if F.w and F.w.cadre and F.w.cadre:IsShown() then pcall(F.w.Rendre) end
end

do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "GET_ITEM_INFO_RECEIVED", "QUEST_LOG_UPDATE", "UNIT_PET" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    local attente = 0
    f:SetScript("OnEvent", function() attente = 0.5 end)
    f:SetScript("OnUpdate", function(_, ecoule)
        if attente <= 0 then return end
        attente = attente - (ecoule or 0)
        if attente <= 0 then F.Actualiser() end
    end)
end
