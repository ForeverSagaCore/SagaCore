local _, NS = ...

-- La fenetre de ClassCore, comme celles de la suite (menu a gauche) :
--   Ma classe        l'essentiel d'un coup d'oeil ;
--   Quetes de classe chaque chaine, faite ou non, etape par etape ;
--   Sorts de classe  appris, a apprendre, plus tard ;
--   Objets de classe reactifs, totems, fragments : sur soi et en banque ;
--   Familiers        (chasseur) le familier, les familles, les techniques ;
--   Parametres.

NS.fenetre = {}
local F = NS.fenetre
local T = NS.T
local E = function() return NS.etat end
local Q = function() return NS.quetes end

local HAUTEUR = 24
local RETRAIT = 16
local COCHE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local VERT = { 0.31, 0.82, 0.41 }
local GRIS = { 0.6, 0.6, 0.6 }
local OR = { 1, 0.82, 0 }
local BLANC = { 1, 1, 1 }
local ROUGE = { 1, 0.35, 0.35 }

local function S() return _G.CoreSuite end

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
    l.bord = l:CreateTexture(nil, "BORDER")
    l.bord:SetSize(18, 18)
    l.bord:SetColorTexture(0.75, 0.6, 0.35, 1)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetPoint("TOPLEFT", l.bord, "TOPLEFT", 1, -1)
    l.icone:SetPoint("BOTTOMRIGHT", l.bord, "BOTTOMRIGHT", -1, 1)
    l.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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

-- blocs : { { titre, droite, lignes = { { icone, texte, droite, couleur,
--   couleurDroite, coche, infobulle(tt), bouton = { texte, action }, retrait } } } }
local function Rendre(page, blocs)
    local zone = page.zone
    local largeur = zone:GetWidth() or 780
    for _, t in ipairs(page.titres or {}) do t.fs:Hide() t.filet:Hide() t.droite:Hide() end
    for _, l in ipairs(page.lignes or {}) do l:Hide() end
    local y, nT, nL = 0, 0, 0
    for k, b in ipairs(blocs) do
        if k > 1 then y = y + 10 end
        if b.titre then
            nT = nT + 1
            local t = Titre(page, nT)
            t.fs:ClearAllPoints()
            t.fs:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            t.fs:SetPoint("RIGHT", zone, "RIGHT", -200, 0)
            t.fs:SetText(b.titre)
            t.droite:ClearAllPoints()
            t.droite:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -10, -y - 2)
            t.droite:SetWidth(190)
            t.droite:SetText(b.droite or "")
            t.filet:ClearAllPoints()
            t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
            t.filet:SetSize(largeur - 10, 1)
            if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet)
            else t.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
            t.fs:Show() t.filet:Show() t.droite:Show()
            y = y + 30
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
            if e.icone then
                l.icone:SetTexture(e.icone)
                if e.gris then l.icone:SetDesaturated(true) else l.icone:SetDesaturated(false) end
                l.bord:Show() l.icone:Show()
                x = x + 24
            else
                l.bord:Hide() l.icone:Hide()
            end
            l.coche:ClearAllPoints()
            if e.coche then
                l.coche:SetPoint("LEFT", l, "LEFT", x, 0)
                l.coche:Show()
                x = x + 18
            else
                l.coche:Hide()
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
            l.droite:ClearAllPoints()
            l.droite:SetPoint("RIGHT", l, "RIGHT", droiteX, 0)
            l.droite:SetWidth(200)
            l.droite:SetText(e.droite or "")
            local cd = e.couleurDroite or GRIS
            l.droite:SetTextColor(cd[1], cd[2], cd[3])
            l.droite.couleurPropre = true
            l.nom:SetPoint("RIGHT", l.droite, "LEFT", -8, 0)
            l.nom:SetText(e.texte or "")
            local c = e.couleur or BLANC
            l.nom:SetTextColor(c[1], c[2], c[3])
            l.nom.couleurPropre = e.couleur ~= nil
            l.infobulle = e.infobulle
            -- Une ligne avec infobulle se choisit a la manette (son survol
            -- s'affiche) ; un clic n'y fait rien d'autre.
            l:SetScript("OnClick", (e.infobulle or e.clic) and function() if e.clic then pcall(e.clic) if F.w then pcall(F.w.Rendre) end end end or nil)
            l:Show()
            y = y + HAUTEUR
        end
        if b.vide then
            nL = nL + 1
            local l = Ligne(page, nL)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
            l:SetPoint("RIGHT", zone, "RIGHT", -10, 0)
            l.bord:Hide() l.icone:Hide() l.coche:Hide() l.bouton:Hide()
            l.nom:ClearAllPoints()
            l.nom:SetPoint("LEFT", l, "LEFT", RETRAIT, 0)
            l.nom:SetPoint("RIGHT", l, "RIGHT", -8, 0)
            l.nom:SetText(b.vide)
            l.nom:SetTextColor(GRIS[1], GRIS[2], GRIS[3])
            l.droite:SetText("")
            l.infobulle = nil
            l:SetScript("OnClick", nil)
            l:Show()
            y = y + HAUTEUR
        end
    end
    return y
end

-- Une page de blocs, avec une rangee optionnelle en haut (choix).
local function Page(cle, icone, libelle, titre, intro, blocs, haut)
    return { cle = cle, icone = icone, libelle = libelle,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(36)
            if haut then haut(page, O) end
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

-- ---------------------------------------------------------------------------
-- Les quetes
-- ---------------------------------------------------------------------------

local ICONES_ETAT = {
    faite = COCHE,
    cours = "Interface\\GossipFrame\\IncompleteQuestIcon",
    prendre = "Interface\\GossipFrame\\AvailableQuestIcon",
    niveau = "Interface\\GossipFrame\\AvailableQuestIcon",
    bloquee = "Interface\\GossipFrame\\AvailableQuestIcon",
}

local vue = { perso = nil }
local function Perso()
    local moi, cleMoi = Q().Moi()
    local cle = vue.perso or cleMoi
    local p = Q().Persos()[cle or ""] or moi
    return p, cle == cleMoi, cle
end

local function Guider(ids)
    local api = _G.QuestCoreAPI
    if api and api.GuiderQuetes and #ids > 0 then return api.GuiderQuetes(ids) end
end

local function InfobulleEtape(e)
    return function(tt)
        tt:AddLine(e.nom)
        tt:AddLine(Q().LibelleEtat(e), 1, 1, 1)
        if (e.niveau or 0) > 0 then tt:AddLine(string.format(T("Quête de niveau %d", "Level %d quest"), e.niveau), 0.8, 0.8, 0.8) end
        local d = Q().Donneur(e.id)
        if d then tt:AddLine(string.format(T("Donnée par %s", "Given by %s"), d), 0.8, 0.8, 0.8) end
    end
end

local function LigneEtape(e)
    local couleur = (e.etat == "faite" and GRIS) or ((e.etat == "cours" or e.etat == "prendre") and OR) or BLANC
    local cd = (e.etat == "faite" and VERT) or ((e.etat == "cours" or e.etat == "prendre") and OR) or GRIS
    return { coche = e.etat == "faite", icone = e.etat ~= "faite" and ICONES_ETAT[e.etat] or nil,
        gris = e.etat == "niveau" or e.etat == "bloquee",
        texte = e.nom, couleur = couleur, droite = Q().LibelleEtat(e), couleurDroite = cd,
        infobulle = InfobulleEtape(e), retrait = 8 }
end

local function BlocsQuetes()
    if not Q().BaseDisponible() then
        return { { titre = T("Quêtes de classe", "Class quests"), vide = T("Il faut QuestieDB, la base de quêtes : installe-le avec la suite.", "QuestieDB, the quest database, is needed : install it with the suite.") } }
    end
    if not Q().Pret() then
        Q().Indexer()
        Q().QuandPret(function() if F.w then pcall(F.w.Rendre) end end)
        return { { titre = T("Quêtes de classe", "Class quests"), vide = T("Lecture de la base de quêtes...", "Reading the quest database...") } }
    end
    local p, connecte = Perso()
    local chaines = Q().Chaines(p, connecte)
    local blocs, finies = {}, {}
    for _, c in ipairs(chaines) do
        if c.etat == "faite" then
            table.insert(finies, { coche = true, texte = c.titre, couleur = GRIS, droite = string.format("%d / %d", c.faites, c.total),
                couleurDroite = VERT, infobulle = function(tt)
                    tt:AddLine(c.titre)
                    for _, e in ipairs(c.etapes) do tt:AddLine(e.nom, 0.8, 0.8, 0.8) end
                end })
        else
            local b = { titre = c.titre, droite = string.format(T("niv. %d  ·  %d / %d", "lvl %d  ·  %d / %d"), c.niveau, c.faites, c.total), lignes = {} }
            local aGuider = Q().AGuider(c)
            local guidable = connecte and #aGuider > 0 and _G.QuestCoreAPI and _G.QuestCoreAPI.GuiderQuetes
            -- Les etapes faites en une ligne, les autres une par une.
            if c.faites > 0 then
                local noms = {}
                for _, e in ipairs(c.etapes) do if e.etat == "faite" then table.insert(noms, e.nom) end end
                table.insert(b.lignes, { coche = true, retrait = 8, couleur = GRIS, couleurDroite = VERT,
                    texte = c.faites == 1 and T("1 étape faite", "1 step done") or string.format(T("%d étapes faites", "%d steps done"), c.faites), droite = T("Faites", "Done"),
                    infobulle = function(tt) tt:AddLine(T("Étapes faites", "Steps done")) for _, n in ipairs(noms) do tt:AddLine(n, 0.8, 0.8, 0.8) end end })
            end
            local premiere = true
            for _, e in ipairs(c.etapes) do
                if e.etat ~= "faite" then
                    local l = LigneEtape(e)
                    if premiere and guidable then
                        l.bouton = { texte = T("Guider", "Guide"), action = function() Guider(aGuider) end }
                    end
                    premiere = false
                    table.insert(b.lignes, l)
                end
            end
            table.insert(blocs, b)
        end
    end
    if #finies > 0 then table.insert(blocs, { titre = T("Chaînes terminées", "Finished chains"), droite = tostring(#finies), lignes = finies }) end
    if #blocs == 0 then table.insert(blocs, { titre = T("Quêtes de classe", "Class quests"), vide = T("Aucune quête de classe connue pour ce personnage.", "No class quest known for this character.") }) end
    return blocs
end

local function OptionsPersos()
    local l = {}
    for _, x in ipairs(Q().ListePersos()) do
        local nom = x.cle:match("^(.-) %- ") or x.cle
        local classe = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[x.p.classe] or x.p.classe
        table.insert(l, { x.cle, string.format("%s (%s %d)", nom, classe or "", x.p.niveau or 0) })
    end
    return l
end

local function PageQuetes()
    return Page("quetes", "Interface\\Icons\\INV_Misc_Book_08",
        function() return T("Quêtes de classe", "Class quests") end,
        function() return T("Les quêtes de classe", "Class quests") end,
        function() return T("Chaque chaîne de quêtes de la classe, pour la race et le camp du personnage : ce qui est fait, ce qui se prend maintenant, et ce qui vient plus tard. Le survol d'une étape dit qui la donne et où.",
            "Every class quest chain for the character's race and faction : what is done, what can be taken now, and what comes later. Hover a step to see who gives it and where.") end,
        BlocsQuetes,
        function(page, O)
            page.rPerso = O.Rangee()
            O.Liste(page.rPerso, OptionsPersos,
                function() local _, _, cle = Perso() return cle end,
                function(v) vue.perso = v end)
            page.rPerso.nom:SetText(T("Personnage", "Character"))
        end)
end

-- ---------------------------------------------------------------------------
-- Sorts et objets
-- ---------------------------------------------------------------------------

local function LigneSort(s)
    local nom, icone = E().Sort(s[1])
    if not nom then return nil end
    local niveau = E().Niveau()
    local connu = E().SortConnu(s[1])
    local droite, cd, couleur
    if connu then droite, cd, couleur = T("Appris", "Learned"), VERT, BLANC
    elseif s.talent then droite, cd, couleur = T("Talent", "Talent"), GRIS, GRIS
    elseif niveau >= (s[2] or 1) then droite, cd, couleur = T("À apprendre", "To learn"), OR, OR
    else droite, cd, couleur = string.format(T("Niveau %d", "Level %d"), s[2] or 1), GRIS, GRIS end
    return { icone = icone, gris = not connu, coche = connu, texte = nom, couleur = couleur, droite = droite, couleurDroite = cd,
        infobulle = function(tt)
            if tt.SetSpellByID then pcall(tt.SetSpellByID, tt, s[1]) else tt:AddLine(nom) end
        end }
end

local function BlocsSorts()
    local d = E().Donnees()
    local camp = E().Camp()
    local blocs = {}
    for _, section in ipairs(d.sorts or {}) do
        local b = { titre = section.titre(), lignes = {} }
        local appris, total = 0, 0
        for _, s in ipairs(section.liste) do
            if E().PourLeCamp(s, camp) then
                local l = LigneSort(s)
                if l then
                    table.insert(b.lignes, l)
                    total = total + 1
                    if l.coche then appris = appris + 1 end
                end
            end
        end
        b.droite = string.format(T("%d appris sur %d", "%d of %d learned"), appris, total)
        if #b.lignes > 0 then table.insert(blocs, b) end
    end
    if #blocs == 0 then table.insert(blocs, { titre = T("Sorts de classe", "Class spells"), vide = T("Rien à suivre pour cette classe.", "Nothing to track for this class.") }) end
    return blocs
end

local function LigneObjet(o)
    local nom, icone = E().Objet(o.id)
    if not nom then return nil end
    local sacs, banque = E().Compte(o.id)
    local bas = (o.seuil or 0) > 0 and sacs < o.seuil
    local droite = banque > 0 and string.format(T("%d sur toi, %d en banque", "%d on you, %d in bank"), sacs, banque)
        or string.format(T("%d sur toi", "%d on you"), sacs)
    return { icone = icone, texte = nom, droite = droite, couleurDroite = bas and ROUGE or BLANC,
        infobulle = function(tt)
            if tt.SetItemByID then pcall(tt.SetItemByID, tt, o.id) else tt:AddLine(nom) end
            if (o.seuil or 0) > 0 then tt:AddLine(string.format(T("Conseillé : %d sur toi", "Advised : %d on you"), o.seuil), 1, 0.82, 0) end
        end }
end

local function BlocsObjets()
    local classe = E().Classe()
    local niveau = E().Niveau()
    local b = { titre = T("Sur toi et en banque", "On you and in bank"), lignes = {} }
    for _, o in ipairs(E().ObjetsUtiles(classe, niveau)) do
        local l = LigneObjet(o)
        if l then table.insert(b.lignes, l) end
    end
    local blocs = { b }
    if classe == "HUNTER" then
        local n, icone = E().Munitions()
        if n then
            table.insert(b.lignes, 1, { icone = icone or "Interface\\Icons\\INV_Ammo_Arrow_02", texte = T("Munitions équipées", "Equipped ammo"),
                droite = tostring(n), couleurDroite = n < 200 and ROUGE or BLANC })
        end
    end
    -- Plus tard : ce qui servira aux niveaux suivants.
    local plusTard = { titre = T("Plus tard", "Later"), lignes = {} }
    for _, o in ipairs(E().Donnees(classe).objets or {}) do
        if niveau < (o.niveau or 1) then
            local nom, icone = E().Objet(o.id)
            if nom then
                table.insert(plusTard.lignes, { icone = icone, gris = true, texte = nom, couleur = GRIS,
                    droite = string.format(T("Niveau %d", "Level %d"), o.niveau), couleurDroite = GRIS,
                    infobulle = function(tt) if tt.SetItemByID then pcall(tt.SetItemByID, tt, o.id) end end })
            end
        end
    end
    if #b.lignes == 0 then b.vide = T("Aucun objet de classe à ce niveau.", "No class item at this level.") end
    if #plusTard.lignes > 0 then table.insert(blocs, plusTard) end
    return blocs
end

-- ---------------------------------------------------------------------------
-- Ma classe : l'essentiel
-- ---------------------------------------------------------------------------

local function NomDeClasse(classe)
    local t = _G.LOCALIZED_CLASS_NAMES_MALE
    return (t and t[classe]) or classe or ""
end

local function BlocsClasse()
    local classe = E().Classe()
    local niveau = E().Niveau()
    local blocs = {}
    -- Quetes
    local bq = { titre = T("Quêtes de classe", "Class quests"), lignes = {} }
    if Q().BaseDisponible() and Q().Pret() then
        local p = Q().Moi()
        local r = Q().Resume(p, true)
        bq.droite = string.format(r.finies <= 1 and T("%d chaîne finie sur %d", "%d of %d chains finished") or T("%d chaînes finies sur %d", "%d of %d chains finished"), r.finies, r.total)
        for i, c in ipairs(r.maintenant) do
            if i > 5 then break end
            local aGuider = Q().AGuider(c)
            local l = { icone = c.etat == "cours" and ICONES_ETAT.cours or ICONES_ETAT.prendre, texte = c.titre, couleur = OR,
                droite = string.format("%d / %d", c.faites, c.total), couleurDroite = GRIS,
                clic = function() if F.w then F.w.page = "quetes" end end,
                infobulle = function(tt)
                    tt:AddLine(c.titre)
                    for _, e in ipairs(c.etapes) do
                        local col = e.etat == "faite" and VERT or (e.etat == "cours" or e.etat == "prendre") and OR or GRIS
                        tt:AddDoubleLine(e.nom, Q().LibelleEtat(e), 0.9, 0.9, 0.9, col[1], col[2], col[3])
                    end
                end }
            if #aGuider > 0 and _G.QuestCoreAPI and _G.QuestCoreAPI.GuiderQuetes then
                l.bouton = { texte = T("Guider", "Guide"), action = function() Guider(aGuider) end }
            end
            table.insert(bq.lignes, l)
        end
        if #bq.lignes == 0 then bq.vide = T("Rien à prendre pour le moment.", "Nothing to take for now.") end
    elseif Q().BaseDisponible() then
        Q().Indexer()
        Q().QuandPret(function() if F.w then pcall(F.w.Rendre) end end)
        bq.vide = T("Lecture de la base de quêtes...", "Reading the quest database...")
    else
        bq.vide = T("Il faut QuestieDB, la base de quêtes.", "QuestieDB, the quest database, is needed.")
    end
    table.insert(blocs, bq)
    -- Sorts a apprendre maintenant
    local bs = { titre = T("À apprendre chez le maître", "To learn at the trainer"), lignes = {} }
    local camp = E().Camp()
    for _, section in ipairs(E().Donnees(classe).sorts or {}) do
        for _, s in ipairs(section.liste) do
            if E().PourLeCamp(s, camp) and not s.talent and niveau >= (s[2] or 1) and not E().SortConnu(s[1]) then
                local l = LigneSort(s)
                if l then table.insert(bs.lignes, l) end
            end
        end
    end
    if #bs.lignes == 0 then bs.vide = T("Tout est appris pour ton niveau.", "Everything is learned for your level.") end
    table.insert(blocs, bs)
    -- Objets
    local bo = { titre = T("Objets de classe", "Class items"), lignes = {} }
    for _, o in ipairs(E().ObjetsUtiles(classe, niveau)) do
        local l = LigneObjet(o)
        if l then table.insert(bo.lignes, l) end
    end
    if classe == "HUNTER" then
        local n, icone = E().Munitions()
        if n then table.insert(bo.lignes, 1, { icone = icone or "Interface\\Icons\\INV_Ammo_Arrow_02", texte = T("Munitions équipées", "Equipped ammo"),
            droite = tostring(n), couleurDroite = n < 200 and ROUGE or BLANC }) end
    end
    if #bo.lignes > 0 then table.insert(blocs, bo) end
    -- Familier
    if classe == "HUNTER" and NS.familiers then
        local b = NS.familiers.BlocMonFamilier()
        if b then table.insert(blocs, b) end
    end
    -- Druide : formes
    if classe == "DRUID" then
        local n = E().FormesRestantes()
        table.insert(blocs, { titre = T("Changements de forme", "Shapeshifts"), lignes = { {
            icone = select(2, E().Sort(768)) or select(2, E().Sort(5487)),
            texte = T("Possibles avec ta mana", "Possible with your mana"),
            droite = n and tostring(n) or T("Hors combat", "Out of combat"), couleurDroite = (n and n < 1) and ROUGE or BLANC } } })
    end
    return blocs
end

local function PageClasse()
    return Page("classe", "Interface\\Icons\\INV_Misc_Book_09",
        function() return T("Ma classe", "My class") end,
        function()
            local c, n = NomDeClasse(E().Classe()), E().Niveau()
            return T(string.format("%s de niveau %d", c, n), string.format("Level %d %s", n, c))
        end,
        function() return T("L'essentiel de ta classe : les quêtes à faire maintenant, les sorts à apprendre chez le maître et ce qu'il faut avoir sur toi.",
            "Your class at a glance : quests to do now, spells to learn at the trainer and what to carry.") end,
        BlocsClasse)
end

local function PageSorts()
    return Page("sorts", "Interface\\Icons\\INV_Misc_Book_11",
        function() return T("Sorts de classe", "Class spells") end,
        function() return T("Les sorts de ta classe", "Your class spells") end,
        function() return T("Par famille : appris, à apprendre chez le maître (ton niveau suffit), ou plus tard. Le survol montre le sort du jeu.",
            "By family : learned, to learn at the trainer (your level is enough), or later. Hover to see the game's spell.") end,
        BlocsSorts)
end

local function PageObjets()
    return Page("objets", "Interface\\Icons\\INV_Misc_Bag_10",
        function() return T("Objets de classe", "Class items") end,
        function() return T("Ce qu'il faut avoir sur toi", "What to carry") end,
        function() return T("Réactifs et objets de classe : combien sur toi, combien en banque. En rouge sous la quantité conseillée.",
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

-- La page de la suite complete (ClassCore installe seul).
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

function F.Construire()
    local Su = S()
    if F.w or not (Su and Su.FenetreAPages) then return F.w end
    local pages = { PageClasse(), PageQuetes(), PageSorts(), PageObjets() }
    if E().Classe() == "HUNTER" and NS.familiers then table.insert(pages, NS.familiers.Page(Page)) end
    table.insert(pages, PageReglages())
    if Su.Seul and Su.Seul() then table.insert(pages, PageSuite()) end
    F.w = Su.FenetreAPages({
        nom = "ClassCoreFenetre", cle = "ClassCore", icone = NS.classes.ICONE[E().Classe() or ""] or "Interface\\Icons\\INV_Misc_Book_09",
        titre = function() return "ClassCore" end,
        pages = pages,
    })
    return F.w
end

function F.Ouvrir()
    local Su = S()
    if F.Construire() and Su and Su.Ouvrir then Su.Ouvrir("ClassCore") return true end
    return false
end

function F.Actualiser()
    if F.w and F.w.cadre and F.w.cadre:IsShown() then pcall(F.w.Rendre) end
end

-- La fenetre ouverte se tient a jour (sacs, sorts appris, noms charges).
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
