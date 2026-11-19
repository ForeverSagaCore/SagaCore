local _, NS = ...

-- Suite Core : CraftCore, QuestCore, MapCore, LegacyCore.
--
-- Ce fichier est le meme dans tous les add-ons. Le premier charge installe
-- la suite ; les suivants ne font que s'y inscrire (la version la plus recente
-- gagne). Ce qu'elle apporte :
--   - un seul bouton de minicarte pour toute la suite : au survol, il s'etend
--     et montre tous les add-ons ; ceux qui ne sont pas installes sont grises ;
--   - une petite barre posee a l'ecran, deplacable ou l'on veut, avec les
--     memes icones ;
--   - dans chaque fenetre, les icones en haut a droite : on passe d'un
--     add-on a l'autre, la nouvelle fenetre prend la place exacte de l'ancienne.

local VERSION = 18

local Suite = _G.CoreSuite
if Suite and (Suite.version or 0) >= VERSION then
    NS.suite = Suite
    return
end
Suite = Suite or { membres = {} }
Suite.version = VERSION
_G.CoreSuite = Suite
NS.suite = Suite

-- Les add-ons de la suite, dans l'ordre d'affichage, avec l'icone du jeu de
-- chacun. Un add-on absent reste montre, grise : on sait qu'il existe.
Suite.ORDRE = {
    { cle = "CraftCore", icone = "Interface\\Icons\\INV_Misc_Gear_01" },
    { cle = "QuestCore", icone = "Interface\\Icons\\INV_Misc_Book_08" },
    { cle = "MapCore", icone = "Interface\\Icons\\INV_Misc_Map_01" },
    { cle = "LegacyCore", icone = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
}
local N = #Suite.ORDRE

local FR = GetLocale and GetLocale() == "frFR"
local T = {
    survol = FR and "Survolez pour choisir un add-on" or "Hover to pick an add-on",
    deplacer = FR and "Glisser : déplacer" or "Drag: move",
    barre = FR and "Clic droit : montrer ou cacher la barre de la suite" or "Right-click: show or hide the suite bar",
    absent = FR and "Pas installé" or "Not installed",
    ouvrir = FR and "Clic : ouvrir" or "Click: open",
    manette = FR and "A : ouvrir" or "A: open",
    ancree = FR and "(ancrée : se déplace seulement ici)" or "(locked: moves only here)",
}

local function Reglages()
    CoreSuiteDB = type(CoreSuiteDB) == "table" and CoreSuiteDB or {}
    local d = CoreSuiteDB
    if type(d.angle) ~= "number" then d.angle = 215 end
    if d.barreAffichee == nil then d.barreAffichee = true end
    return d
end

-- ---------------------------------------------------------------------------
-- Inscription et ouverture
-- ---------------------------------------------------------------------------

-- membre : { titre, ouvrir = fonction, fenetre = fonction rendant le cadre,
--            boutonMinicarte = son ancien bouton (cache par la suite) }
function Suite.Inscrire(cle, membre)
    Suite.membres[cle] = membre
    if membre.boutonMinicarte then
        local b = membre.boutonMinicarte
        b:Hide()
        b:HookScript("OnShow", function(self) self:Hide() end)
    end
    if Suite.Actualiser then Suite.Actualiser() end
end

function Suite.Installe(cle) return Suite.membres[cle] ~= nil end

-- ---------------------------------------------------------------------------
-- Ancrage des fenetres de suivi, et mode Edition du jeu
-- ---------------------------------------------------------------------------
--
-- Une fenetre ancree ne se deplace ni ne se redimensionne plus. En mode
-- Edition du jeu (Echap, Mode Edition), toutes les fenetres de la suite se
-- deverrouillent et s'entourent de bleu, comme celles du jeu : on les place,
-- puis en quittant le mode Edition, celles qui sont ancrees se refigent.
-- Chaque add-on garde la position comme d'habitude.

Suite.ancrables = Suite.ancrables or {}

function Suite.EnEdition()
    local e = _G.EditModeManagerFrame
    return e ~= nil and e.IsShown ~= nil and e:IsShown() == true
end

function Suite.Ancree(cle)
    local d = Reglages()
    return type(d.ancres) == "table" and d.ancres[cle] == true
end

-- Peut-on deplacer ou redimensionner cette fenetre maintenant ?
function Suite.Libre(cle) return not Suite.Ancree(cle) or Suite.EnEdition() end

local function Habiller(a)
    if not a.cadre then return end
    local enEdition = Suite.EnEdition() and a.cadre:IsShown()
    if enEdition and not a.voile then
        local v = CreateFrame("Frame", nil, a.cadre)
        v:SetAllPoints()
        v:SetFrameLevel(a.cadre:GetFrameLevel() + 30)
        v.fond = v:CreateTexture(nil, "OVERLAY")
        v.fond:SetAllPoints()
        v.fond:SetColorTexture(0.25, 0.6, 1, 0.22)
        v.texte = v:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v.texte:SetPoint("CENTER")
        v:EnableMouse(false)
        a.voile = v
    end
    if a.voile then
        a.voile.texte:SetText(a.libelle .. (Suite.Ancree(a.cle) and ("\n" .. T.ancree) or ""))
        a.voile:SetShown(enEdition)
    end
    if a.apres then pcall(a.apres) end
end

function Suite.AppliquerAncres()
    for _, a in pairs(Suite.ancrables) do pcall(Habiller, a) end
end

function Suite.PoserAncre(cle, valeur)
    local d = Reglages()
    d.ancres = d.ancres or {}
    d.ancres[cle] = valeur and true or nil
    Suite.AppliquerAncres()
end

-- `apres` : appele quand l'etat change (pour montrer ou cacher une poignee).
function Suite.Ancrable(cle, cadre, libelle, apres)
    Suite.ancrables[cle] = { cle = cle, cadre = cadre, libelle = libelle, apres = apres }
    local e = _G.EditModeManagerFrame
    if e and not Suite.editionSuivie then
        Suite.editionSuivie = true
        e:HookScript("OnShow", function() Suite.AppliquerAncres() end)
        e:HookScript("OnHide", function() Suite.AppliquerAncres() end)
    end
    cadre:HookScript("OnShow", function() pcall(Habiller, Suite.ancrables[cle]) end)
    pcall(Habiller, Suite.ancrables[cle])
end

-- ---------------------------------------------------------------------------
-- Personnage affiche, le meme dans toute la suite
-- ---------------------------------------------------------------------------
--
-- Garde pour la session seulement : a chaque connexion, chaque add-on repart
-- sur le personnage connecte. Un choix fait dans un add-on vaut pour les
-- autres. `persoVersion` change a chaque choix : un add-on n'applique le
-- choix commun que s'il est plus recent que le sien.

function Suite.Personnage() return Suite.perso, Suite.persoVersion end

function Suite.PoserPersonnage(cle)
    Suite.perso = cle
    Suite.persoVersion = (Suite.persoVersion or 0) + 1
    return Suite.persoVersion
end

-- Une seule fenetre de la suite a la fois : celle qui s'ouvre prend la place
-- exacte d'une autre deja ouverte, qui se ferme. Appele a chaque ouverture,
-- quel que soit le chemin (bouton, commande, clic sur un repere...).
function Suite.PrendrePlace(cle, cadre)
    if not cadre then return end
    for autre, m in pairs(Suite.membres) do
        local f = autre ~= cle and m.fenetre and m.fenetre()
        if f and f ~= cadre and f:IsShown() then
            local point, relatif, pointRelatif, x, y = f:GetPoint(1)
            f:Hide()
            if point then
                cadre:ClearAllPoints()
                cadre:SetPoint(point, relatif or UIParent, pointRelatif or point, x or 0, y or 0)
            end
        end
    end
    Reglages().dernier = cle
end

-- Ouvre un add-on (ou le ferme s'il est deja seul ouvert).
function Suite.Ouvrir(cle)
    local cible = Suite.membres[cle]
    if not cible then return end
    local f = cible.fenetre and cible.fenetre()
    if f and f:IsShown() then
        f:Hide()
        return
    end
    pcall(cible.ouvrir)
    f = cible.fenetre and cible.fenetre()
    if f then Suite.PrendrePlace(cle, f) end
    if Suite.Actualiser then Suite.Actualiser() end
end

-- ---------------------------------------------------------------------------
-- Icones des add-ons (rond de minicarte du jeu)
-- ---------------------------------------------------------------------------

local function IconeRonde(parent, taille, info)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(taille, taille)
    b:RegisterForClicks("LeftButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(taille * 0.65, taille * 0.65)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(taille * 0.6, taille * 0.6)
    b.icone:SetPoint("CENTER")
    b.icone:SetTexture(info.icone)
    if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(taille * 1.7, taille * 1.7)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.cle = info.cle
    b:SetScript("OnClick", function(self) Suite.Ouvrir(self.cle) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
        if Suite.Installe(self.cle) then
            GameTooltip:AddLine(T.ouvrir, 1, 1, 1)
        else
            GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Grise ce qui n'est pas installe, eclaire l'add-on ouvert.
local function Teinter(b)
    local installe = Suite.Installe(b.cle)
    b.icone:SetDesaturated(not installe)
    b:SetAlpha(installe and 1 or 0.45)
    b:SetEnabled(installe)
end

-- Icones carrees, pour l'en-tete des fenetres.
local function IconeCarree(parent, info)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    b.icone:SetTexture(info.icone)
    b.halo = b:CreateTexture(nil, "OVERLAY")
    b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.halo:SetBlendMode("ADD")
    b.halo:SetPoint("TOPLEFT", -2, 2)
    b.halo:SetPoint("BOTTOMRIGHT", 2, -2)
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.cle = info.cle
    b:SetScript("OnClick", function(self) Suite.Ouvrir(self.cle) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
        if not Suite.Installe(self.cle) then GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- ---------------------------------------------------------------------------
-- Dans chaque fenetre : les icones, en haut a droite de l'en-tete
-- ---------------------------------------------------------------------------

Suite.entetes = Suite.entetes or {}

-- Onglet lateral du jeu (celui des fenetres de metier), a defaut un onglet
-- du grimoire.
local function OngletLateral(parent, info, auClic)
    local ok, b = pcall(CreateFrame, "Frame", nil, parent, "LargeSideTabButtonTemplate")
    if ok and b and b.Icon and b.SetChecked and b.SetCustomOnMouseUpHandler then
        b.Icon:SetTexture(info.icone)
        b:SetCustomOnMouseUpHandler(function(_, bouton, dedans)
            if bouton == "LeftButton" and dedans then auClic() end
        end)
        b.natif = true
        b.icone = b.Icon
    else
        if ok and b then b:Hide() end
        b = CreateFrame("CheckButton", nil, parent)
        b:SetSize(32, 32)
        local fond = b:CreateTexture(nil, "BACKGROUND")
        fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        fond:SetSize(64, 64)
        fond:SetPoint("TOPLEFT", -3, 11)
        b.icone = b:CreateTexture(nil, "ARTWORK")
        b.icone:SetAllPoints()
        b.icone:SetTexture(info.icone)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
        local halo = b:GetCheckedTexture()
        if halo then halo:SetBlendMode("ADD") end
        b:SetScript("OnClick", function(self)
            self:SetChecked(self.cle == self.courante)
            auClic()
        end)
    end
    b.cle = info.cle
    -- Pose sur le bord gauche : le dessin de l'onglet est retourne (l'icone
    -- reste a l'endroit).
    -- Le modele du jeu remet son dessin (SetAtlas) a chaque changement
    -- d'etat, ce qui annulait le retournement : on retourne de nouveau apres
    -- chaque SetAtlas, et les angles coupes restent du cote exterieur.
    local function Retourner(r)
        local ulx, uly, llx, lly, urx, ury, lrx, lry = r:GetTexCoord()
        if ulx then r:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= b.icone and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexCoord then
            Retourner(r)
            if hooksecurefunc and r.SetAtlas then
                pcall(hooksecurefunc, r, "SetAtlas", function(self) Retourner(self) end)
            end
            if hooksecurefunc and r.SetTexture then
                pcall(hooksecurefunc, r, "SetTexture", function(self) Retourner(self) end)
            end
        end
    end
    -- L'icone : exactement comme les onglets de droite (FillToInterior, qui
    -- remplit l'interieur de l'onglet), puis son rectangle est retourne
    -- autour du dessin de l'onglet, retourne lui aussi.
    if b.natif and b.icone then
        if b.SetFillToInterior then pcall(b.SetFillToInterior, b, true) end
        local function Retourner(self)
            local fond = self.Background
            if not (fond and fond.GetLeft) then
                local aire = 0
                for _, r in ipairs({ self:GetRegions() }) do
                    if r ~= self.icone and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetWidth then
                        local a2 = (r:GetWidth() or 0) * (r:GetHeight() or 0)
                        if a2 > aire then aire, fond = a2, r end
                    end
                end
            end
            local ic = self.icone
            local lb, tb = self:GetLeft(), self:GetTop()
            local lf, rf = fond and fond:GetLeft(), fond and fond:GetRight()
            local li, ri, ti, bi = ic:GetLeft(), ic:GetRight(), ic:GetTop(), ic:GetBottom()
            if not (lb and tb and lf and rf and li and ri and ti and bi) then return false end
            local gauche = lf + rf - ri
            ic:ClearAllPoints()
            ic:SetPoint("TOPLEFT", self, "TOPLEFT", gauche - lb, ti - tb)
            ic:SetSize(ri - li, ti - bi)
            self.iconeRetournee = true
            return true
        end
        b:HookScript("OnShow", function(self)
            if self.iconeRetournee then return end
            if not Retourner(self) and C_Timer and C_Timer.After then
                C_Timer.After(0, function() if not self.iconeRetournee then Retourner(self) end end)
            end
        end)
    end
    b:HookScript("OnEnter", function(self)
        self.survol = true
        if self.icone then self.icone:SetVertexColor(1, 1, 1) end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.cle, 1, 0.82, 0)
        if not Suite.Installe(self.cle) then GameTooltip:AddLine(T.absent, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function(self)
        self.survol = false
        if self.icone and self.cle ~= self.courante then self.icone:SetVertexColor(0.55, 0.55, 0.55) end
        GameTooltip:Hide()
    end)
    return b
end

-- Les add-ons de la suite en onglets lateraux, sur le bord GAUCHE de la
-- fenetre : le bord droit reste aux onglets propres a chaque add-on
-- (metiers, equipement, carte...). LT / RT passent d'un add-on a l'autre au
-- bout de la colonne de droite (voir Suite.Voisin).
function Suite.Entete(cadre, cleCourante)
    if not cadre or cadre.suiteEntete then return end
    local rangee = { boutons = {}, courante = cleCourante }
    local precedent
    for _, info in ipairs(Suite.ORDRE) do
        local cle = info.cle
        local b = OngletLateral(cadre, info, function()
            if cle ~= cleCourante and Suite.Installe(cle) then Suite.Ouvrir(cle) end
        end)
        b.courante = cleCourante
        b:ClearAllPoints()
        if precedent then b:SetPoint("TOPRIGHT", precedent, "BOTTOMRIGHT", 0, -2)
        else b:SetPoint("TOPRIGHT", cadre, "TOPLEFT", 0, -60) end
        table.insert(rangee.boutons, b)
        precedent = b
    end
    cadre.suiteEntete = rangee
    cadre:HookScript("OnShow", function(self)
        Suite.PrendrePlace(cleCourante, self)
        Suite.Actualiser()
    end)
    cadre:HookScript("OnHide", function() Suite.Actualiser() end)
    table.insert(Suite.entetes, rangee)
    Suite.Actualiser()
end

-- Pastille sur l'onglet d'un add-on (texte court), nil pour l'enlever.
function Suite.PoserBadge(cle, texte)
    Suite.badges = Suite.badges or {}
    Suite.badges[cle] = texte and tostring(texte) or nil
    Suite.Actualiser()
end

-- Ecart entre les onglets de la suite et ceux de l'add-on.
Suite.ECART_ONGLETS = 22

-- LT / RT au bout des onglets d'un add-on : l'add-on voisin s'ouvre, sur son
-- premier onglet (en avancant) ou son dernier (en reculant).
function Suite.Voisin(cleCourante, pas)
    local liste = {}
    for _, info in ipairs(Suite.ORDRE) do
        if Suite.Installe(info.cle) then table.insert(liste, info.cle) end
    end
    if #liste < 2 then return false end
    local index = 1
    for rang, cle in ipairs(liste) do if cle == cleCourante then index = rang end end
    Suite.Ouvrir(liste[((index - 1 + pas) % #liste) + 1])
    return true
end

-- Manette, la meme dans toute la suite :
--   LB / RB : menu de gauche de l'add-on (s'arrete aux bouts) ;
--   LT / RT : onglets de droite de l'add-on (s'arrete aux bouts) ;
--   clic du stick gauche / droit (L3 / R3) : add-on precedent / suivant.
-- Chaque fenetre appelle ManetteBas a l'appui : vrai si la suite a pris le
-- bouton.
function Suite.ManetteBas(cleCourante, bouton)
    if bouton == "PADLSTICK" or bouton == "PADRSTICK" then
        Suite.Voisin(cleCourante, bouton == "PADLSTICK" and -1 or 1)
        return true
    end
    return false
end

-- Plus de combinaison : garde pour les fenetres qui l'appellent encore.
function Suite.ManetteHaut() return false end

-- "debut" ou "fin" : ou l'add-on qui s'ouvre doit se poser, une seule fois.
function Suite.PrendreEntree()
    local e = Suite.entree
    Suite.entree = nil
    return e
end

-- ---------------------------------------------------------------------------
-- Manette : l'ancien curseur de l'en-tete n'existe plus (LT / RT passent par
-- les onglets lateraux). Gardes pour les add-ons qui l'appellent encore.
-- ---------------------------------------------------------------------------

function Suite.CurseurActif() return false end
function Suite.CurseurEntrer() return false end
function Suite.CurseurQuitter() end
function Suite.CurseurDeplacer() end
function Suite.CurseurValider() end

-- ---------------------------------------------------------------------------
--
-- Le curseur se pose sur une icone sans rien ouvrir ; seul A ouvre l'add-on.
-- On ne change donc jamais d'add-on par erreur.

local function Choisissables(rangee)
    local liste = {}
    for _, b in ipairs(rangee and rangee.boutons or {}) do
        if Suite.Installe(b.cle) and b.cle ~= rangee.courante then table.insert(liste, b) end
    end
    return liste
end

local function Eclairer(rangee)
    for _, b in ipairs(rangee.boutons) do
        if b.UnlockHighlight then b:UnlockHighlight() end
    end
    GameTooltip:Hide()
    local b = rangee.curseur and Choisissables(rangee)[rangee.curseur]
    if b then
        if b.LockHighlight then b:LockHighlight() end
        local survol = b:GetScript("OnEnter")
        if survol then pcall(survol, b) end
        if GameTooltip:IsShown() then GameTooltip:AddLine(T.manette, 1, 1, 1) GameTooltip:Show() end
    end
end

function Suite.CurseurActif(cadre)
    local rangee = cadre and cadre.suiteEntete
    return rangee ~= nil and rangee.curseur ~= nil
end

-- Entre sur la premiere icone choisissable. Faux s'il n'y en a aucune.
function Suite.CurseurEntrer(cadre)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or #Choisissables(rangee) == 0 then return false end
    rangee.curseur = 1
    Eclairer(rangee)
    return true
end

function Suite.CurseurQuitter(cadre)
    local rangee = cadre and cadre.suiteEntete
    if not rangee then return end
    rangee.curseur = nil
    Eclairer(rangee)
end

-- Deplace le curseur ; avant la premiere icone, on sort (retour aux portraits).
function Suite.CurseurDeplacer(cadre, pas)
    local rangee = cadre and cadre.suiteEntete
    if not rangee or not rangee.curseur then return end
    local n = #Choisissables(rangee)
    local rang = rangee.curseur + pas
    if rang < 1 then rangee.curseur = nil
    else rangee.curseur = math.min(rang, n) end
    Eclairer(rangee)
end

function Suite.CurseurValider(cadre)
    local rangee = cadre and cadre.suiteEntete
    local b = rangee and rangee.curseur and Choisissables(rangee)[rangee.curseur]
    if not b then return end
    rangee.curseur = nil
    Eclairer(rangee)
    Suite.Ouvrir(b.cle)
end

-- ---------------------------------------------------------------------------
-- Bouton de minicarte unique, qui s'etend au survol
-- ---------------------------------------------------------------------------

local atan2 = math.atan2 or math.atan

local function PlacerSurMinicarte(bouton)
    local angle = math.rad(Reglages().angle)
    local demi = Minimap:GetWidth() / 2 + 5
    local forme = GetMinimapShape and GetMinimapShape() or "ROUND"
    local x, y = math.cos(angle), math.sin(angle)
    if forme == "ROUND" then
        x, y = x * demi, y * demi
    else
        local portee = demi * 1.4142
        x = math.max(-demi, math.min(x * portee, demi))
        y = math.max(-demi, math.min(y * portee, demi))
    end
    bouton:ClearAllPoints()
    bouton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function IconeDuBouton()
    local d = Reglages()
    if d.dernier and Suite.Installe(d.dernier) then
        for _, info in ipairs(Suite.ORDRE) do if info.cle == d.dernier then return info.icone end end
    end
    for _, info in ipairs(Suite.ORDRE) do if Suite.Installe(info.cle) then return info.icone end end
    return Suite.ORDRE[1].icone
end

function Suite.ConstruireMinicarte()
    if Suite.bouton or not Minimap then return end
    local bouton = IconeRonde(Minimap, 31, { cle = "CoreSuite", icone = IconeDuBouton() })
    bouton:SetFrameStrata("MEDIUM")
    bouton:SetFrameLevel(8)
    bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bouton:RegisterForDrag("LeftButton")
    bouton:SetScript("OnClick", function(_, souris)
        if souris == "RightButton" then return end
        -- Clic : le dernier add-on utilise, sinon le premier installe.
        local d = Reglages()
        local cible = (d.dernier and Suite.Installe(d.dernier)) and d.dernier or nil
        if not cible then
            for _, info in ipairs(Suite.ORDRE) do
                if Suite.Installe(info.cle) then cible = info.cle break end
            end
        end
        if cible then Suite.Ouvrir(cible) end
    end)
    bouton:SetScript("OnDragStart", function(self)
        Suite.eventail:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local echelle = Minimap:GetEffectiveScale()
            Reglages().angle = math.deg(atan2(py / echelle - my, px / echelle - mx)) % 360
            PlacerSurMinicarte(self)
        end)
    end)
    bouton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    -- L'eventail : les add-ons, en ligne a cote du bouton.
    local eventail = CreateFrame("Frame", nil, bouton)
    eventail:SetSize(N * 30, 30)
    eventail:SetPoint("RIGHT", bouton, "LEFT", -2, 0)
    eventail.boutons = {}
    for rang, info in ipairs(Suite.ORDRE) do
        local b = IconeRonde(eventail, 28, info)
        b:SetPoint("RIGHT", eventail, "RIGHT", -(N - rang) * 30, 0)
        eventail.boutons[rang] = b
    end
    eventail:Hide()
    Suite.eventail = eventail

    -- Au survol : l'eventail s'ouvre, et se referme un instant apres que la
    -- souris a quitte le bouton et l'eventail.
    local delai = 0
    bouton:SetScript("OnEnter", function(self)
        eventail:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever SagaCore", 1, 0.82, 0)
        GameTooltip:AddLine(T.survol, 1, 1, 1)
        GameTooltip:AddLine(T.deplacer, 1, 1, 1)
        GameTooltip:Show()
    end)
    bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    eventail:SetScript("OnUpdate", function(self, ecoule)
        if self:IsMouseOver(4, -4, -4, 4) or bouton:IsMouseOver() then delai = 0 return end
        delai = delai + (ecoule or 0)
        if delai > 0.4 then self:Hide() delai = 0 end
    end)

    Suite.bouton = bouton
    PlacerSurMinicarte(bouton)
end

-- ---------------------------------------------------------------------------
-- Barre posee a l'ecran, deplacable
-- ---------------------------------------------------------------------------

-- La petite barre posee a l'ecran n'existe plus : les icones en haut de
-- chaque fenetre et le bouton de minicarte suffisent. Une barre deja creee
-- par une ancienne copie de ce fichier est cachee.
function Suite.ConstruireBarre()
    if Suite.barre then Suite.barre:Hide() end
end

-- ---------------------------------------------------------------------------
-- Mise a jour de tout ce qui montre la suite
-- ---------------------------------------------------------------------------

function Suite.Actualiser()
    local ouvert
    for cle, m in pairs(Suite.membres) do
        local f = m.fenetre and m.fenetre()
        if f and f:IsShown() then ouvert = cle end
    end
    local function Rangee(boutons)
        for _, b in ipairs(boutons or {}) do Teinter(b) end
    end
    if Suite.eventail then Rangee(Suite.eventail.boutons) end
    if Suite.bouton then Suite.bouton.icone:SetTexture(IconeDuBouton()) end
    if Suite.barre then
        Suite.barre:Hide()
    end
    for _, rangee in ipairs(Suite.entetes) do
        for _, b in ipairs(rangee.boutons) do
            local installe = Suite.Installe(b.cle)
            local courant = b.cle == rangee.courante
            b.icone:SetDesaturated(not installe)
            b:SetAlpha(installe and 1 or 0.5)
            if b.SetChecked then b:SetChecked(courant) end
            -- Comme les onglets de metier : celui qui n'est pas ouvert reste
            -- en retrait ; il s'eclaire au survol.
            local v = (courant or b.survol) and 1 or 0.55
            b.icone:SetVertexColor(v, v, v)
            -- Pastille (ex. points d'heritage a depenser) dans le coin de l'icone.
            local pastille = Suite.badges and Suite.badges[b.cle]
            if pastille and not b.badge then
                b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                b.badge:SetPoint("BOTTOMRIGHT", b.icone, "BOTTOMRIGHT", 1, 0)
                b.badge:SetTextColor(0.31, 0.82, 0.41)
            end
            if b.badge then
                b.badge:SetText(pastille or "")
                b.badge:SetShown(pastille ~= nil)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Filtres des cartes : une rangee de boutons ronds sous chaque carte de la
-- suite (MapCore, QuestCore). Les memes filtres partout, et partages : ce
-- qu'on masque sur une carte est masque sur les autres.
-- Clic : afficher ou masquer. Clic droit : n'afficher que ca (encore une
-- fois : tout reafficher).
-- ---------------------------------------------------------------------------

local QC = "Interface\\AddOns\\QuestCore\\Icons\\"
local function AvecQuestCore() return _G.QuestCoreAPI ~= nil end
local function AvecRecolte(metier)
    return function()
        local api = _G.CraftCoreAPI
        if not (api and api.Lieux) then return false end
        if not api.MetierDeRecolte then return metier == "herbes" end
        local ok, oui = pcall(api.MetierDeRecolte, metier)
        return ok and oui == true
    end
end
local function AvecReperes() return _G.MapCoreAPI ~= nil end

Suite.FILTRES = {
    { cle = "quetes", atlas = "QuestNormal", fichier = "Interface\\GossipFrame\\AvailableQuestIcon",
      nom = FR and "Quêtes : à prendre et à rendre" or "Quests: pick up and turn in", dispo = AvecQuestCore },
    { cle = "tuer", fichier = QC .. "slay_mono", teinte = { 1, 0.38, 0.32 },
      nom = FR and "Créatures à tuer" or "Creatures to kill", dispo = AvecQuestCore },
    { cle = "butin", fichier = QC .. "loot_mono", teinte = { 1, 0.82, 0 },
      nom = FR and "Butin à ramasser" or "Loot to collect", dispo = AvecQuestCore },
    { cle = "objet", fichier = QC .. "object_mono", teinte = { 0.45, 0.8, 1 },
      nom = FR and "Objets à utiliser et lieux à visiter" or "Objects to use and places to visit", dispo = AvecQuestCore },
    { cle = "herbes", droite = true, fichier = "Interface\\Icons\\Trade_Herbalism", rond = true,
      nom = FR and "Herboristerie : lieux de récolte" or "Herbalism: gathering spots", dispo = AvecRecolte("herbes") },
    { cle = "minerais", droite = true, fichier = "Interface\\Icons\\Trade_Mining", rond = true,
      nom = FR and "Minage : filons" or "Mining: veins", dispo = AvecRecolte("minerais") },
    { cle = "peche", droite = true, fichier = "Interface\\Icons\\Trade_Fishing", rond = true,
      nom = FR and "Pêche : lieux de pêche" or "Fishing: fishing spots", dispo = AvecRecolte("peche") },
    { cle = "reperes", fichier = "Interface\\TargetingFrame\\UI-RaidTargetingIcons", coords = { 0, 0.25, 0, 0.25 },
      nom = FR and "Mes repères" or "My markers", dispo = AvecReperes },
}

local T_FILTRE = {
    clic = FR and "Clic : afficher ou masquer" or "Click: show or hide",
    seul = FR and "Clic droit : n'afficher que ça" or "Right-click: show only this",
    tout = FR and "Clic droit : tout réafficher" or "Right-click: show everything",
    masque = FR and "Masqué" or "Hidden",
    liste = FR and "Clic : choisir les herbes ou minerais à montrer" or "Click: pick the herbs or ores to show",
}

local function Filtres()
    local d = Reglages()
    d.filtresCarte = type(d.filtresCarte) == "table" and d.filtresCarte or {}
    return d.filtresCarte
end

-- Le filtre est-il actif (montre) ? Par defaut, tout est montre.
function Suite.Filtre(cle) return Filtres()[cle] ~= false end

-- Un lieu de recolte est-il montre ? Selon le filtre de son metier.
-- Un lieu de recolte est-il montre ? Seulement si le personnage a le metier,
-- si le filtre du metier est actif, et si le type (herbe, minerai precis)
-- n'est pas masque dans la liste du filtre.
function Suite.LieuVisible(lieu)
    if type(lieu) ~= "table" then return true end
    local metier = lieu.metier or "herbes"
    local api = _G.CraftCoreAPI
    if api and api.ARecolte then
        local ok, oui = pcall(api.ARecolte, metier)
        if ok and oui == false then return false end
    end
    if not Suite.Filtre(metier) then return false end
    if lieu.nomType and Filtres()["type:" .. lieu.nomType] == false then return false end
    return true
end

-- Categorie d'un point de quete de QuestCore.
function Suite.FiltreDuPoint(pt)
    if type(pt) ~= "table" then return nil end
    if pt.genre == "prendre" or pt.genre == "rendre" then return "quetes" end
    if pt.icone == "tuer" then return "tuer" end
    if pt.icone == "butin" then return "butin" end
    return "objet"
end

function Suite.PointVisible(pt)
    local cle = Suite.FiltreDuPoint(pt)
    return cle == nil or Suite.Filtre(cle)
end

Suite.barresFiltres = Suite.barresFiltres or {}

local function Seul(cle)
    for _, f in ipairs(Suite.FILTRES) do
        if f.dispo() and f.cle ~= cle and Suite.Filtre(f.cle) then return false end
    end
    return Suite.Filtre(cle)
end

local function Prevenir()
    for _, barre in ipairs(Suite.barresFiltres) do
        pcall(barre.Actualiser, barre)
        if barre:IsVisible() and barre.auChangement then pcall(barre.auChangement) end
    end
end

function Suite.PoserFiltre(cle, actif)
    if actif then Filtres()[cle] = nil else Filtres()[cle] = false end
    Prevenir()
end

local function BoutonFiltre(barre, info)
    local taille = 26
    local b = CreateFrame("Button", nil, barre)
    b:SetSize(taille, taille)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetSize(taille * 0.8, taille * 0.8)
    b.fond:SetPoint("CENTER")
    b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetPoint("CENTER")
    local cote = info.rond and taille * 0.62 or taille * 0.66
    b.icone:SetSize(cote, cote)
    if not (info.atlas and b.icone.SetAtlas and pcall(b.icone.SetAtlas, b.icone, info.atlas) and b.icone:GetAtlas()) then
        b.icone:SetTexture(info.fichier)
    end
    if info.coords then b.icone:SetTexCoord(unpack(info.coords)) end
    if info.rond and b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.teinte = info.teinte
    b.anneau = b:CreateTexture(nil, "OVERLAY")
    b.anneau:SetSize(taille * 1.7, taille * 1.7)
    b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.cle, b.nom = info.cle, info.nom
    b:SetScript("OnClick", function(self, bouton)
        if bouton == "RightButton" then
            local tout = Seul(self.cle)
            for _, f in ipairs(Suite.FILTRES) do
                if tout or f.cle == self.cle then Filtres()[f.cle] = nil else Filtres()[f.cle] = false end
            end
            Prevenir()
        else
            Suite.PoserFiltre(self.cle, not Suite.Filtre(self.cle))
        end
        if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.nom, 1, 0.82, 0)
        if not Suite.Filtre(self.cle) then GameTooltip:AddLine(T_FILTRE.masque, 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(self.droite and T_FILTRE.liste or T_FILTRE.clic, 1, 1, 1)
        GameTooltip:AddLine(Seul(self.cle) and T_FILTRE.tout or T_FILTRE.seul, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Lieu de recolte sur une carte : l'icone de la matiere, dans un rond cercle
-- d'or (comme le bord des cartes). lieu = { objet, x, y, n } de CraftCore.
function Suite.PionRecolte(parent, taille)
    taille = taille or 16
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(taille, taille)
    b.cercle = b:CreateTexture(nil, "BORDER")
    b.cercle:SetPoint("CENTER")
    b.cercle:SetSize(taille + 3, taille + 3)
    b.cercle:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    b.cercle:SetVertexColor(0.75, 0.6, 0.35, 1)
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetAllPoints()
    if b.icone.SetMask then pcall(b.icone.SetMask, b.icone, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        local cc = _G.CraftCoreAPI
        local l = self.lieu
        local nom = l.nom or (l.objet and cc and cc.Objet and cc.Objet(l.objet))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(nom or ("#" .. tostring(l.objet)), 1, 1, 1)
        if l.base then
            GameTooltip:AddLine(FR and "D'après la base GatherMate2" or "From the GatherMate2 database", 0.8, 0.8, 0.8)
        elseif l.repere then
            -- Noeud vu par un personnage sans le metier : a venir recolter.
            GameTooltip:AddLine(FR and "Repéré ici, pas encore récolté" or "Spotted here, not gathered yet", 1, 0.82, 0)
        else
            GameTooltip:AddLine(string.format(FR and "Récolté %d fois ici" or "Gathered %d times here",
                tonumber(l.n) or 1), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Sur la minicarte : l'interieur gris et translucide, le contour en anneau
    -- dore bien visible (celui des totems du jeu), creux au milieu : le point
    -- jaune du jeu (le noeud reellement present) se voit au travers. La
    -- souris passe au jeu, qui donne le nom du noeud au survol.
    function b.Discret(self)
        local cote = self:GetWidth() or 13
        self.icone:SetDesaturated(true)
        self.icone:SetAlpha(0.4)
        self.cercle:SetTexture("Interface\\CharacterFrame\\TotemBorder")
        self.cercle:SetVertexColor(1, 1, 1, 1)
        self.cercle:SetSize(cote * 1.75, cote * 1.75)
        self.cercle:SetDrawLayer("OVERLAY")
        self:SetAlpha(1)
        self:EnableMouse(false)
    end
    function b.Poser(self, lieu)
        self.lieu = lieu
        local cc = _G.CraftCoreAPI
        local icone = lieu.icone
        if not icone and lieu.objet and cc and cc.Objet then icone = select(2, cc.Objet(lieu.objet)) end
        self.icone:SetTexture(icone or "Interface\\Icons\\INV_Misc_Herb_01")
        self.ax, self.ay = lieu.x, lieu.y
    end
    return b
end

-- Rangee de filtres, centree ; auChangement redessine la carte.
-- La barre se pose ensuite par l'add-on (barre:SetPoint).
-- Liste au-dessus d'un filtre de metier : chaque herbe ou minerai de la
-- carte, a cocher ou decocher, et le metier entier en tete.
local function ListeDesTypes(barre, bouton)
    local l = barre.liste
    if not l then
        local ok, f = pcall(CreateFrame, "Frame", nil, barre, "BackdropTemplate")
        l = ok and f or CreateFrame("Frame", nil, barre)
        if l.SetBackdrop then
            l:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            l:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            l:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
        end
        l:SetFrameStrata("DIALOG")
        l:EnableMouse(true)
        l.lignes = {}
        barre.liste = l
    end
    if l:IsShown() and l.cle == bouton.cle then l:Hide() return end
    l.cle = bouton.cle
    -- Les types presents sur la carte affichee, avec leur nombre.
    local types, ordre = {}, {}
    local api = _G.CraftCoreAPI
    local carte = barre.carteFn and barre.carteFn()
    if api and api.Lieux and carte then
        local ok, lieux = pcall(api.Lieux, carte)
        for _, x in ipairs(ok and lieux or {}) do
            if x.metier == bouton.cle and x.nomType then
                if not types[x.nomType] then
                    types[x.nomType] = { nom = x.nomType, n = 0, icone = x.icone }
                    if not x.icone and x.objet and api.Objet then types[x.nomType].icone = select(2, api.Objet(x.objet)) end
                    table.insert(ordre, types[x.nomType])
                end
                types[x.nomType].n = types[x.nomType].n + 1
            end
        end
    end
    table.sort(ordre, function(a, b) return a.nom < b.nom end)
    local function Ligne(rang)
        local r = l.lignes[rang]
        if r then return r end
        r = CreateFrame("CheckButton", nil, l, "UICheckButtonTemplate")
        r:SetSize(22, 22)
        r.icone = r:CreateTexture(nil, "ARTWORK")
        r.icone:SetSize(14, 14)
        r.icone:SetPoint("LEFT", r, "RIGHT", 2, 0)
        r.nom = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.nom:SetPoint("LEFT", r.icone, "RIGHT", 4, 0)
        r.nom:SetJustifyH("LEFT")
        l.lignes[rang] = r
        return r
    end
    for _, r in ipairs(l.lignes) do r:Hide() end
    local largeur = 140
    local entete = Ligne(1)
    entete:ClearAllPoints()
    entete:SetPoint("TOPLEFT", l, "TOPLEFT", 8, -6)
    entete.icone:SetTexture(bouton.fichier)
    entete.nom:SetText(bouton.nom)
    entete.nom:SetFontObject("GameFontNormalSmall")
    entete:SetChecked(Suite.Filtre(bouton.cle))
    entete:SetScript("OnClick", function(self)
        Suite.PoserFiltre(bouton.cle, self:GetChecked() and true or false)
    end)
    entete:Show()
    largeur = math.max(largeur, (entete.nom:GetStringWidth() or 0) + 60)
    for k, t in ipairs(ordre) do
        local r = Ligne(k + 1)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", l, "TOPLEFT", 20, -6 - k * 20)
        r.icone:SetTexture(t.icone or bouton.fichier)
        r.nom:SetFontObject("GameFontHighlightSmall")
        r.nom:SetText(string.format("%s  |cff999999%d|r", t.nom, t.n))
        r:SetChecked(Filtres()["type:" .. t.nom] ~= false)
        local nomType = t.nom
        r:SetScript("OnClick", function(self)
            if self:GetChecked() then Filtres()["type:" .. nomType] = nil else Filtres()["type:" .. nomType] = false end
            Prevenir()
        end)
        r:Show()
        largeur = math.max(largeur, (r.nom:GetStringWidth() or 0) + 72)
    end
    if #ordre == 0 then
        local r = Ligne(2)
        r:Hide()
    end
    l:SetSize(largeur, 12 + (#ordre + 1) * 20)
    l:ClearAllPoints()
    l:SetPoint("BOTTOMRIGHT", bouton, "TOPRIGHT", 0, 6)
    l:Show()
end

function Suite.BarreFiltres(parent, auChangement, carteFn)
    local barre = CreateFrame("Frame", nil, parent)
    barre:SetHeight(28)
    barre.auChangement = auChangement
    barre.carteFn = carteFn
    barre.boutons = {}
    for _, info in ipairs(Suite.FILTRES) do
        local b = BoutonFiltre(barre, info)
        b.dispo = info.dispo
        b.droite, b.fichier = info.droite, info.fichier
        -- Metiers : un clic ouvre la liste des herbes / minerais de la carte.
        if info.droite then
            b:SetScript("OnClick", function(self, bouton)
                if bouton == "RightButton" then
                    local tout = Seul(self.cle)
                    for _, f in ipairs(Suite.FILTRES) do
                        if tout or f.cle == self.cle then Filtres()[f.cle] = nil else Filtres()[f.cle] = false end
                    end
                    Prevenir()
                else
                    ListeDesTypes(barre, self)
                end
            end)
        end
        table.insert(barre.boutons, b)
    end
    barre:SetScript("OnHide", function(self) if self.liste then self.liste:Hide() end end)
    -- A gauche : quetes, a tuer, butin, objets, reperes ; a droite : les
    -- metiers de recolte du personnage.
    function barre.Actualiser(self)
        local x, xd = 0, 0
        for _, b in ipairs(self.boutons) do
            local dispo = b.dispo()
            b:SetShown(dispo)
            if dispo then
                b:ClearAllPoints()
                if b.droite then
                    b:SetPoint("RIGHT", self, "RIGHT", -xd - 6, 0)
                    xd = xd + 34
                else
                    b:SetPoint("LEFT", self, "LEFT", x, 0)
                    x = x + 34
                end
                local actif = Suite.Filtre(b.cle)
                b.icone:SetDesaturated(not actif)
                if b.teinte and actif then b.icone:SetVertexColor(b.teinte[1], b.teinte[2], b.teinte[3])
                else b.icone:SetVertexColor(1, 1, 1) end
                b.icone:SetAlpha(actif and 1 or 0.4)
                b.anneau:SetDesaturated(not actif)
            end
        end
        if not self.etendue then self:SetWidth(math.max(1, x + xd)) end
        if self.liste and self.liste:IsShown() then
            local cle = self.liste.cle
            for _, b in ipairs(self.boutons) do
                if b.cle == cle and b:IsShown() then self.liste:Hide() ListeDesTypes(self, b) end
            end
        end
    end
    -- Sur toute la largeur d'un cadre (la carte), sous lui.
    function barre.Etendre(self, cadre, ecart)
        self.etendue = true
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 4, -(ecart or 8))
        self:SetPoint("TOPRIGHT", cadre, "BOTTOMRIGHT", -4, -(ecart or 8))
    end
    barre:SetScript("OnShow", function(self) self:Actualiser() end)
    barre:Actualiser()
    table.insert(Suite.barresFiltres, barre)
    return barre
end

-- ---------------------------------------------------------------------------
-- Guidage, commun a la suite : une fleche au milieu du haut de l'ecran qui
-- montre la direction de la prochaine etape d'un trajet (tournee de rendu de
-- QuestCore, tournee de recolte de MapCore...), avec la distance. Un seul
-- guidage a la fois : en lancer un arrete le precedent.
--   Suite.Guider(cle, fournisseur) ; Suite.ArreterGuidage(cle) ;
--   Suite.GuidageActif(cle).
-- fournisseur = {
--   Cible = function() -> { carte, x, y, qui, rang, total, titre } ou nil, raison
--           (raison "fini" : le trajet est termine, le guidage s'arrete),
--   Arrivee = function(cible) (facultatif : le personnage est arrive),
--   Clic = function() (facultatif : clic sur la fleche),
--   Fin = function() (le guidage s'arrete, quelle qu'en soit la raison) }
-- ---------------------------------------------------------------------------

local TG = {
    titre = FR and "Guidage du trajet" or "Path guidance",
    aide = FR and "Glisser : monter ou descendre. Clic droit : arrêter le guidage." or "Drag: move up or down. Right-click: stop guiding.",
    loin = FR and "Hors de portée" or "Out of range",
}

Suite.guide = Suite.guide or {}

function Suite.GuidageActif(cle)
    local g = Suite.guide
    return g.cle ~= nil and (cle == nil or g.cle == cle)
end

local function PositionMonde(carte, x, y)
    local f, V = _G.C_Map and _G.C_Map.GetWorldPosFromMapPos, _G.CreateVector2D
    if not (f and V and carte and x) then return nil end
    local ok, continent, p = pcall(f, carte, V(x, y))
    if ok and p and p.GetXY then
        local a, b = p:GetXY()
        return a, b, continent
    end
    return nil
end

local function PositionJoueur()
    local carte = _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetBestMapForUnit("player")
    local pos = carte and _G.C_Map.GetPlayerMapPosition and _G.C_Map.GetPlayerMapPosition(carte, "player")
    if not (pos and pos.GetXY) then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    return PositionMonde(carte, x, y)
end

local function CadreGuidage()
    local g = Suite.guide
    if g.cadre then return g.cadre end
    local c = CreateFrame("Button", "CoreSuiteGuidage", UIParent)
    c:SetSize(64, 64)
    c:SetFrameStrata("HIGH")
    c:SetClampedToScreen(true)
    c:SetMovable(true)
    c:RegisterForDrag("LeftButton")
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:SetPoint("TOP", UIParent, "TOP", 0, Reglages().guidageY or -110)
    c:SetScript("OnDragStart", function(self) self:StartMoving() end)
    c:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Le clic qui suit tout juste un glisser ne compte pas.
        self.finGlisser = GetTime and GetTime() or 0
        -- Toujours au milieu de l'ecran : on ne la deplace qu'en hauteur.
        local echelle = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        local y = math.min(0, (self:GetTop() or 0) * echelle - (UIParent:GetHeight() or 0))
        Reglages().guidageY = math.floor(y + 0.5)
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "TOP", 0, Reglages().guidageY)
    end)
    c:SetScript("OnClick", function(self, bouton)
        if self.finGlisser and GetTime and GetTime() - self.finGlisser < 0.3 then return end
        if bouton == "RightButton" then Suite.ArreterGuidage() return end
        local f = Suite.guide.fournisseur
        if f and f.Clic then pcall(f.Clic) end
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(TG.titre, 1, 0.82, 0)
        if self.titre then GameTooltip:AddLine(self.titre, 1, 1, 1) end
        local f = Suite.guide.fournisseur
        if f and f.AideClic then GameTooltip:AddLine(f.AideClic, 0.7, 0.7, 0.7, true) end
        GameTooltip:AddLine(TG.aide, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- La fleche seule (celle du personnage sur la minicarte), bien centree.
    c.fleche = c:CreateTexture(nil, "ARTWORK")
    c.fleche:SetSize(56, 56)
    c.fleche:SetPoint("CENTER")
    c.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    c.arrivee = c:CreateTexture(nil, "ARTWORK")
    c.arrivee:SetSize(32, 32)
    c.arrivee:SetPoint("CENTER")
    c.arrivee:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    c.distance = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.distance:SetPoint("TOP", c, "BOTTOM", 0, -2)
    c.qui = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.qui:SetPoint("TOP", c.distance, "BOTTOM", 0, -1)
    local attente = 0
    c:SetScript("OnUpdate", function(self, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.05
        local f = Suite.guide.fournisseur
        if not f then self:Hide() return end
        local ok, cible, raison = pcall(f.Cible)
        if not ok then return end
        if not cible then
            if raison == "fini" then Suite.ArreterGuidage() return end
            self.fleche:Hide() self.arrivee:Hide()
            self.distance:SetText(TG.loin)
            self.qui:SetText("")
            return
        end
        self.titre = cible.titre
        if cible.rang and cible.total then
            self.qui:SetText(string.format("%d/%d  %s", cible.rang, cible.total, cible.qui or ""))
        else
            self.qui:SetText(cible.qui or "")
        end
        local ax, ay, ca = PositionJoueur()
        local bx, by, cb = PositionMonde(cible.carte, cible.x, cible.y)
        if not (ax and bx) or (ca and cb and ca ~= cb) then
            self.fleche:Hide() self.arrivee:Hide()
            self.distance:SetText(TG.loin)
            return
        end
        local nord, ouest = bx - ax, by - ay
        local yards = math.sqrt(nord * nord + ouest * ouest)
        self.distance:SetText(string.format("%d m", math.floor(yards * 0.9144 + 0.5)))
        if yards < 12 then
            self.fleche:Hide()
            self.arrivee:Show()
            if f.Arrivee then pcall(f.Arrivee, cible) end
            return
        end
        self.arrivee:Hide()
        self.fleche:Show()
        local face = tonumber(_G.GetPlayerFacing and _G.GetPlayerFacing()) or 0
        local angle = math.atan2(ouest, nord) - face
        if self.fleche.SetRotation then self.fleche:SetRotation(angle) end
        -- Verte quand on va droit dessus, doree sinon.
        local ecart = math.abs(((angle + math.pi) % (2 * math.pi)) - math.pi)
        if ecart < 0.35 then self.fleche:SetVertexColor(0.4, 1, 0.4) else self.fleche:SetVertexColor(1, 0.82, 0) end
    end)
    c:Hide()
    g.cadre = c
    return c
end

function Suite.Guider(cle, fournisseur)
    local g = Suite.guide
    if g.cle and g.cle ~= cle and g.fournisseur and g.fournisseur.Fin then
        local ancien = g.fournisseur
        g.cle, g.fournisseur = nil, nil
        pcall(ancien.Fin)
    end
    g.cle, g.fournisseur = cle, fournisseur
    CadreGuidage():Show()
end

function Suite.ArreterGuidage(cle)
    local g = Suite.guide
    if cle and g.cle ~= cle then return end
    local f = g.fournisseur
    g.cle, g.fournisseur = nil, nil
    if g.cadre then g.cadre:Hide() end
    if f and f.Fin then pcall(f.Fin) end
end

-- Une fois tous les add-ons charges : bouton de minicarte et barre.
if not Suite.cadreDemarrage then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        pcall(_G.CoreSuite.ConstruireMinicarte)
        pcall(_G.CoreSuite.ConstruireBarre)
        pcall(_G.CoreSuite.Actualiser)
    end)
    Suite.cadreDemarrage = f
end
