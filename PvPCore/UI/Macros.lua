local _, NS = ...

-- La page Macros : des macros toutes faites pour chaque champ de bataille,
-- annonces d'inc par lieu et appels d'objectif. Le joueur choisit l'annonce
-- de chaque lieu dans une liste, puis "Creer" : la macro du jeu est creee
-- (hors combat), dans le compte ou ce personnage, la place restante comptee.
-- Les lignes sont disposees a chaque affichage, comme les rubriques.

NS.pageMacros = {}
local M = NS.pageMacros
local T = NS.T

local BATAILLES = {
    { cle = "goulet", fr = "Goulet des Chanteguerres", en = "Warsong Gulch" },
    { cle = "arathi", fr = "Bassin Arathi", en = "Arathi Basin" },
    { cle = "alterac", fr = "Vallée d'Alterac", en = "Alterac Valley" },
}

function M.Reglages()
    PvPCoreDB = type(PvPCoreDB) == "table" and PvPCoreDB or {}
    PvPCoreDB.macros = type(PvPCoreDB.macros) == "table" and PvPCoreDB.macros or {}
    local r = PvPCoreDB.macros
    r.variantes = type(r.variantes) == "table" and r.variantes or {}
    if r.ou ~= "perso" then r.ou = "compte" end
    return r
end

local function Rendre()
    local w = NS.fenetre and NS.fenetre.w
    if w and w.Rendre then w.Rendre() end
end

-- Les variantes proposees pour un lieu de ce champ de bataille.
local function OptionsVariantes(quel)
    return function()
        local o = {}
        for _, v in ipairs(NS.annonces.VARIANTES) do
            if not v.goulet or quel == "goulet" then table.insert(o, { v.cle, NS.annonces.LibelleVariante(v.cle) }) end
        end
        return o
    end
end

-- Un bouton de la suite : largeur a la mesure du texte.
local function Bouton(parent, auClic)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    local poser = b.SetText
    b.SetText = function(self, texte)
        poser(self, texte)
        local l = self.GetTextWidth and self:GetTextWidth() or 0
        self:SetWidth(math.max(30, math.floor(l + 28)))
    end
    b:SetScript("OnClick", function(self) auClic(self) Rendre() end)
    return b
end

-- Une ligne : libelle a gauche ; a droite, l'etat, la liste, le bouton.
local function Ligne(page, i)
    local l = page.lignes[i]
    if l then return l end
    l = CreateFrame("Frame", nil, page.zone)
    l:SetHeight(24)
    l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.nom:SetPoint("LEFT", l, "LEFT", page.O.RETRAIT, 0)
    l.nom:SetJustifyH("LEFT")
    l.nom:SetWordWrap(false)
    l.bouton = Bouton(l, function()
        local m = l.m
        if not m then return end
        local A = NS.annonces
        if A.Existe(m.cle) then
            local ok, raison = A.SupprimerMacro(m)
            if not ok and raison then NS.Dire(raison) end
        else
            local ok, raison = A.CreerMacro(m, M.Reglages().ou == "perso")
            if ok then NS.Dire(string.format(T("Macro « %s » créée : fenêtre Macros du jeu (/macro).", "Macro \"%s\" created : game Macros window (/macro)."), m.nom))
            elseif raison then NS.Dire(raison) end
        end
    end)
    l.bouton:SetPoint("RIGHT", l, "RIGHT", -10, 0)
    l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.etat:SetWordWrap(false)
    page.lignes[i] = l
    return l
end

-- La liste des variantes d'une ligne de lieu, creee une fois par ligne.
local function ListeDe(page, l)
    if l.liste then return l.liste end
    local S = _G.CoreSuite
    l.liste = S.ListeDeroulante(l, function() return l.options and l.options() or {} end,
        function() return l.variante end,
        function(v) if l.cleVariante then M.Reglages().variantes[l.cleVariante] = v end end,
        Rendre, function(o) table.insert(page.focus, o) end)
    l.liste:SetPoint("RIGHT", l.bouton, "LEFT", -8, 0)
    table.insert(page.controles, l.liste)
    return l.liste
end

local function Titre(page, n, y, texte)
    local t = page.titres[n]
    if not t then
        t = { fs = page.zone:CreateFontString(nil, "OVERLAY", "GameFontNormal"), filet = page.zone:CreateTexture(nil, "ARTWORK") }
        t.fs:SetJustifyH("LEFT")
        page.titres[n] = t
    end
    t.fs:ClearAllPoints()
    t.fs:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
    t.fs:SetText(texte)
    t.filet:ClearAllPoints()
    t.filet:SetPoint("TOPLEFT", t.fs, "TOPLEFT", 0, -22)
    t.filet:SetSize(page.O.LARGEUR - 10, 1)
    if NS.charte and NS.charte.TitreDeSection then pcall(NS.charte.TitreDeSection, t.fs, t.filet)
    else t.filet:SetColorTexture(0.8, 0.65, 0.35, 0.35) end
    t.fs:Show() t.filet:Show()
    return y + 34
end

local function Detail(page, n, y, texte)
    local d = page.details[n]
    if not d then
        d = page.zone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d:SetJustifyH("LEFT")
        d:SetWordWrap(false)
        page.details[n] = d
    end
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", page.zone, "TOPLEFT", page.O.RETRAIT, -y)
    d:SetText(texte)
    d:Show()
    return y + 22
end

function M.Page()
    return { cle = "macros", icone = "Interface\\Icons\\Ability_Warrior_BattleShout",
        libelle = function() return T("Macros", "Macros") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(18)
            page.intro:SetWordWrap(false)
            page.sReglages = O.Section()
            page.rOu = O.Rangee()
            O.Liste(page.rOu, function() return { { "compte", T("Le compte", "The account") }, { "perso", T("Ce personnage", "This character") } } end,
                function() return M.Reglages().ou end, function(v) M.Reglages().ou = v end)
            page.rPlace = O.Rangee()
            page.place = page.rPlace:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            page.place:SetPoint("RIGHT", page.rPlace, "RIGHT", -10, 0)
            page.rCanal = O.Rangee()
            page.canal = page.rCanal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            page.canal:SetPoint("RIGHT", page.rCanal, "RIGHT", -10, 0)
            page.dRaccourcis = O.Detail(18)
            page.dRaccourcis:SetWordWrap(false)
            page.zone = CreateFrame("Frame", nil, page.cadre)
            page.zone:SetSize(O.LARGEUR - 10, 10)
            O.Placer(page.zone, 1, 12)
            page.yZone = page.y - 1
            page.titres, page.lignes, page.details = {}, {}, {}
        end,
        rendre = function(page)
            local A = NS.annonces
            page.t1:SetText(T("Macros toutes faites", "Ready-made macros"))
            page.intro:SetText(T("Choisissez l'annonce de chaque lieu, puis « Créer » : la macro écrit sur le canal du champ de bataille.",
                "Pick the call for each place, then \"Create\" : the macro writes in the battleground channel."))
            page.sReglages:SetText(T("Création", "Creation"))
            page.rOu.nom:SetText(T("Créer les macros dans", "Create macros in"))
            local compte, mc, perso, mp = A.Place()
            page.rPlace.nom:SetText(T("Place utilisée", "Room used"))
            page.place:SetText(string.format(T("Compte %d / %d  ·  Personnage %d / %d", "Account %d / %d  ·  Character %d / %d"), compte, mc, perso, mp))
            page.rCanal.nom:SetText(T("Canal des annonces", "Channel for calls"))
            page.canal:SetText(A.CommandeCanal())
            page.dRaccourcis:SetText(T("Raccourcis (Options, Raccourcis, PvPCore) : Inc 1, 2, 3, 5+ et dégagé au lieu le plus proche, cibler le porteur.",
                "Key bindings (Options, Key Bindings, PvPCore) : Inc 1, 2, 3, 5+ and clear at the nearest place, target the carrier."))
            for _, t in ipairs(page.titres) do t.fs:Hide() t.filet:Hide() end
            for _, d in ipairs(page.details) do d:Hide() end
            for _, l in ipairs(page.lignes) do l:Hide() end
            local reglages = M.Reglages()
            local y, nT, nL, nD = 0, 0, 0, 0
            for k, b in ipairs(BATAILLES) do
                if k > 1 then y = y + 8 end
                nT = nT + 1
                y = Titre(page, nT, y, T(b.fr, b.en))
                if b.cle == "alterac" and #NS.bataille.LieuxConnus(NS.bataille.CARTES.alterac) == 0 then
                    nD = nD + 1
                    y = Detail(page, nD, y, T("Entrez une fois dans la Vallée d'Alterac : ses tours et cimetières viendront ici, avec les noms du jeu.",
                        "Enter Alterac Valley once : its towers and graveyards will appear here, with the game's names."))
                end
                for _, m in ipairs(A.Catalogue(b.cle, reglages.variantes)) do
                    nL = nL + 1
                    local l = Ligne(page, nL)
                    l.m = m
                    l:ClearAllPoints()
                    l:SetPoint("TOPLEFT", page.zone, "TOPLEFT", 0, -y)
                    l:SetPoint("RIGHT", page.zone, "RIGHT", 0, 0)
                    l.nom:SetText(m.libelle)
                    local existe = A.Existe(m.cle)
                    l.bouton:SetText(existe and T("Supprimer", "Delete") or T("Créer", "Create"))
                    l.etat:SetText(existe and ("|cff4fd16a" .. T("Macro créée", "Macro created") .. "|r") or "")
                    l.etat:ClearAllPoints()
                    if m.variante then
                        l.options = OptionsVariantes(b.cle)
                        l.variante = m.variante
                        l.cleVariante = b.cle .. ":" .. m.lieu
                        local li = ListeDe(page, l)
                        li:Show()
                        l.etat:SetPoint("RIGHT", li, "LEFT", -12, 0)
                    else
                        l.options, l.variante, l.cleVariante = nil, nil, nil
                        if l.liste then l.liste:Hide() end
                        l.etat:SetPoint("RIGHT", l.bouton, "LEFT", -12, 0)
                    end
                    -- Le libelle s'arrete avant les controles : jamais sur deux lignes.
                    l.nom:SetPoint("RIGHT", l, "RIGHT", -440, 0)
                    l:Show()
                    y = y + 30
                end
            end
            page.zone:SetHeight(math.max(y, 20))
            page.hauteur = page.yZone + math.max(y, 20)
        end }
end

-- La page se tient a jour quand les macros du jeu changent.
local cadre = CreateFrame("Frame")
pcall(cadre.RegisterEvent, cadre, "UPDATE_MACROS")
cadre:SetScript("OnEvent", function()
    local w = NS.fenetre and NS.fenetre.w
    if w and w.cadre and w.cadre:IsShown() and w.page == "macros" then pcall(w.Rendre) end
end)
