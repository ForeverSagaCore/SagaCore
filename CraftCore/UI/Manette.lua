local _, NS = ...

-- Navigation a la manette.
--
-- Les boutons de la manette n'arrivent jamais par le clavier : la fenetre
-- les recoit elle-meme quand elle est ouverte. Patron repris de Questie,
-- installe sur ce client : la fenetre declare les recevoir, traite ceux qu'elle
-- connait, et laisse passer tous les autres au jeu en repondant vrai.
--
--   LB / RB          section precedente / suivante
--   LT / RT          metier precedent / suivant
--   croix gauche/droite  personnage precedent / suivant
--   croix haut/bas   fait defiler la page
--   Vue (deux rectangles)  entre dans la zone centrale, ou en sort
--
-- Dans la zone centrale (liseree d'or), la croix se deplace dans les quatre
-- directions d'apres ce qui est a l'ecran :
--   haut / bas       ligne precedente / suivante, dans la meme colonne
--   gauche / droite  element voisin sur la meme ligne
--   A                valider l'element choisi (clic gauche)
--   X                action secondaire (clic droit : ajouter une recette)
--   Y                aide de la page, ou etape suivante du didacticiel
--   B                sortir de la zone centrale ; sinon fermer l'aide,
--                    quitter le didacticiel, fermer la fenetre
--
-- L'element choisi est eclaire par la surbrillance du jeu, comme au survol.

NS.manette = {}
local manette = NS.manette

local focus          -- element choisi
local Defiler, Repeter, ArreterRepetition, repetition, Traiter
local rangFocus = 0  -- son rang dans la page, retenu d'un dessin a l'autre
local enZone = false -- navigation dans la zone centrale

function manette.EnZone() return enZone end

-- Une manette est-elle branchee et activee dans le jeu ?
function manette.Active()
    local pad = _G.C_GamePad
    if type(pad) ~= "table" or type(pad.IsEnabled) ~= "function" then return false end
    local ok, actif = pcall(pad.IsEnabled)
    return ok and actif == true
end

-- ---------------------------------------------------------------------------
-- Icones des boutons de la manette
-- ---------------------------------------------------------------------------
--
-- Les icones sont celles du jeu, jamais dessinees par nous. Dans l'ordre :
--   1. le texte de touche du jeu, s'il contient deja l'icone (il suit alors le
--      modele de manette choisi dans les options) ;
--   2. les atlas d'icones de manette du jeu, s'ils existent sur ce client ;
--   3. a defaut, le nom de la touche en clair, en or.
-- Ce qui a ete trouve est note dans la decouverte, pour le verifier.

local NOMS = {
    PAD1 = { ltr = "A", shp = "Cross", court = "A" },
    PAD2 = { ltr = "B", shp = "Circle", court = "B" },
    PAD3 = { ltr = "X", shp = "Square", court = "X" },
    PAD4 = { ltr = "Y", shp = "Triangle", court = "Y" },
    PADLSHOULDER = { gen = "LShoulder", court = "LB" },
    PADRSHOULDER = { gen = "RShoulder", court = "RB" },
    PADLTRIGGER = { gen = "LTrigger", court = "LT" },
    PADRTRIGGER = { gen = "RTrigger", court = "RT" },
    PADDLEFT = { gen = "Left", court = "<" },
    PADDRIGHT = { gen = "Right", court = ">" },
    PADDUP = { gen = "Up", court = "^" },
    PADDDOWN = { gen = "Down", court = "v" },
    -- Le bouton aux deux rectangles des manettes Xbox (Vue), Share ailleurs.
    PADBACK = { ltr = "View", shp = "Share", gen = "Back", court = "Vue" },
    -- Clic des sticks : add-on precedent / suivant.
    PADLSTICK = { gen = "LStickIn", court = "L3" },
    PADRSTICK = { gen = "RStickIn", court = "R3" },
}

local cacheGlyphes = {}

local function AtlasExiste(nom)
    local info = NS.Lecture("C_Texture.GetAtlasInfo")
    if not info then return false end
    local ok, resultat = pcall(info, nom)
    return ok and resultat ~= nil
end

-- Texte a afficher pour une touche, icone comprise quand le jeu en a une.
function manette.Glyphe(touche, taille)
    taille = taille or 20
    local cle = touche .. ":" .. taille
    if cacheGlyphes[cle] then return cacheGlyphes[cle] end
    local nom = NOMS[touche] or { court = touche }
    local rendu, source

    local texteDeTouche = NS.Lecture("GetBindingText")
    if texteDeTouche then
        local ok, texte = pcall(texteDeTouche, touche)
        if ok and type(texte) == "string" and (string.find(texte, "|A:", 1, true) or string.find(texte, "|T", 1, true)) then
            -- Le texte de touche du jeu porte sa propre taille : on la ramene
            -- a celle demandee.
            texte = string.gsub(texte, "|A:([^:|]+)[^|]*|a", "|A:%1:" .. taille .. ":" .. taille .. "|a")
            texte = string.gsub(texte, "|T([^:|]+)[^|]*|t", "|T%1:" .. taille .. ":" .. taille .. "|t")
            rendu, source = texte, "texte de touche"
        end
    end
    if not rendu then
        local candidats = {}
        for _, famille in ipairs({ "Ltr", "Shp", "Gen", "Rev" }) do
            local partie = (famille == "Ltr" and (nom.ltr or nom.gen))
                or (famille == "Shp" and (nom.shp or nom.gen)) or nom.gen
            if partie then
                table.insert(candidats, "Gamepad_" .. famille .. "_" .. partie .. "_64")
                table.insert(candidats, "Gamepad_" .. famille .. "_" .. partie .. "_32")
            end
        end
        for _, atlas in ipairs(candidats) do
            if AtlasExiste(atlas) then
                rendu = "|A:" .. atlas .. ":" .. taille .. ":" .. taille .. "|a"
                source = atlas
                break
            end
        end
    end
    if not rendu then
        rendu, source = "|cffffd100" .. nom.court .. "|r", "texte"
    end
    cacheGlyphes[cle] = rendu
    local dec = NS.base.Decouverte and NS.base.Decouverte()
    if dec then
        dec.glyphesManette = dec.glyphesManette or {}
        dec.glyphesManette[touche] = source
    end
    return rendu
end

-- Releve, une fois, ce que le client offre pour l'interface manette : noms
-- globaux qui en parlent. Sert a reprendre ses propres cadres si le jeu en a.
function manette.Sonder()
    local dec = NS.base.Decouverte and NS.base.Decouverte()
    if not dec or dec.sondeManette then return end
    local trouves = {}
    for nom in pairs(_G) do
        if type(nom) == "string" and #trouves < 80 then
            local bas = string.lower(nom)
            if (string.find(bas, "hint", 1, true) or string.find(bas, "prompt", 1, true))
                and (string.find(bas, "pad", 1, true) or string.find(bas, "controller", 1, true)
                or string.find(bas, "bar", 1, true)) then
                table.insert(trouves, nom)
            end
        end
    end
    table.sort(trouves)
    dec.sondeManette = trouves
    local texteDeTouche = NS.Lecture("GetBindingText")
    if texteDeTouche then
        local ok, texte = pcall(texteDeTouche, "PAD1")
        dec.texteToucheA = ok and tostring(texte) or nil
    end
end

-- ---------------------------------------------------------------------------
-- Elements atteignables dans la page
-- ---------------------------------------------------------------------------

-- Un element se choisit s'il est montre, actif, et qu'il fait quelque chose
-- au clic ou au survol. Rien d'autre : un libelle seul ne se choisit pas.
local function Atteignable(objet)
    if not objet or not objet.IsObjectType or not objet:IsObjectType("Button") then return false end
    if not objet:IsVisible() then return false end
    if objet.IsMouseEnabled and not objet:IsMouseEnabled() then return false end
    if objet.IsEnabled and not objet:IsEnabled() then return false end
    return objet:GetScript("OnClick") ~= nil or objet:GetScript("OnEnter") ~= nil
end

local function Parcourir(cadre, liste, profondeur)
    -- Assez profond pour les listes defilantes dans un panneau (equipement).
    if not cadre or not cadre.GetChildren or profondeur > 9 then return end
    for _, enfant in ipairs({ cadre:GetChildren() }) do
        if enfant:IsVisible() then
            if Atteignable(enfant) then table.insert(liste, enfant) end
            Parcourir(enfant, liste, profondeur + 1)
        end
    end
end

-- Dans l'ordre de lecture : de haut en bas, puis de gauche a droite.
local function ElementsDeLaPage(win)
    local liste = {}
    if NS.ecran.page == "equipement" then
        -- Son menu de gauche (scenarios, origines) fait partie de la page.
        Parcourir(win.menu, liste, 1)
        Parcourir(win.zoneFixe, liste, 1)
        Parcourir(win.bandeau, liste, 1)
    else
        Parcourir(win.contenu, liste, 1)
    end
    table.sort(liste, function(a, b)
        local ha, hb = a:GetTop() or 0, b:GetTop() or 0
        if math.abs(ha - hb) > 4 then return ha > hb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    return liste
end

manette.ElementsDeLaPage = ElementsDeLaPage

-- ---------------------------------------------------------------------------
-- Choix de l'element
-- ---------------------------------------------------------------------------

local function Relacher()
    if focus then
        if focus.UnlockHighlight then focus:UnlockHighlight() end
        -- Une ligne qu'on ne clique pas (stocks) retrouve sa surbrillance eteinte.
        if focus.alphaAvantManette then
            local s = focus.GetHighlightTexture and focus:GetHighlightTexture()
            if s then s:SetAlpha(focus.alphaAvantManette) end
            focus.alphaAvantManette = nil
        end
        local quitter = focus:GetScript("OnLeave")
        if quitter then pcall(quitter, focus) end
    end
    focus = nil
end

-- Garde l'element choisi dans la partie visible de la zone defilante.
local function Rendrevisible(win, element)
    -- La zone qui defile est le premier cadre defilant au-dessus de l'element :
    -- la page, ou une liste dans un panneau (les objets de l'equipement).
    local zone, enfant
    local parent = element.GetParent and element:GetParent()
    local garde = 0
    while parent and garde < 12 do
        if parent.IsObjectType and parent:IsObjectType("ScrollFrame") then zone = parent break end
        parent = parent.GetParent and parent:GetParent()
        garde = garde + 1
    end
    if not zone then return end
    enfant = zone.GetScrollChild and zone:GetScrollChild()
    if not zone:IsShown() or not enfant then return end
    local haut, bas = enfant:GetTop(), element:GetTop()
    if not haut or not bas then return end
    local position = haut - bas
    local vue = zone:GetHeight() or 0
    local actuel = zone:GetVerticalScroll() or 0
    local maximum = (zone.GetVerticalScrollRange and zone:GetVerticalScrollRange()) or 0
    local hauteur = element:GetHeight() or 20
    local cible = actuel
    if position < actuel then
        cible = position - 10
    elseif position + hauteur > actuel + vue then
        cible = position + hauteur - vue + 10
    end
    cible = math.max(0, math.min(maximum, cible))
    if cible ~= actuel then zone:SetVerticalScroll(cible) end
end

local function Choisir(win, element)
    Relacher()
    focus = element
    if not element then return end
    if element.LockHighlight then element:LockHighlight() end
    -- Une ligne qu'on ne fait que survoler (stocks) a sa surbrillance eteinte :
    -- on l'allume le temps du choix, pour voir ou l'on est.
    local s = element.GetHighlightTexture and element:GetHighlightTexture()
    if s and s.GetAlpha and (s:GetAlpha() or 1) < 0.5 then
        element.alphaAvantManette = s:GetAlpha()
        s:SetAlpha(1)
    end
    Rendrevisible(win, element)
    -- Le survol se joue aussi a la manette : l'infobulle d'une ligne de stock
    -- dit qui detient combien.
    local survol = element:GetScript("OnEnter")
    if survol then pcall(survol, element) end
end

-- Fait defiler la zone centrale d'un pas, dans les bornes.
local PAS_DE_DEFILEMENT = 80
Defiler = function(win, pas)
    local zone = win.defilement
    if not zone or not zone:IsShown() then return end
    local maximum = (zone.GetVerticalScrollRange and zone:GetVerticalScrollRange()) or 0
    local cible = (zone:GetVerticalScroll() or 0) + pas * PAS_DE_DEFILEMENT
    zone:SetVerticalScroll(math.max(0, math.min(maximum, cible)))
end

-- Repetition tant que la croix reste enfoncee : un premier delai, puis un
-- pas regulier. S'arrete au relachement, ou si la fenetre se ferme.
local DELAI_AVANT_REPETITION, INTERVALLE = 0.35, 0.07
repetition = { bouton = nil, attente = 0 }
local horloge

ArreterRepetition = function()
    repetition.bouton = nil
    if horloge then horloge:SetScript("OnUpdate", nil) end
end

Repeter = function(win, bouton)
    horloge = horloge or CreateFrame("Frame")
    repetition.bouton = bouton
    repetition.attente = DELAI_AVANT_REPETITION
    horloge:SetScript("OnUpdate", function(_, ecoule)
        if not repetition.bouton or not win:IsShown() then ArreterRepetition() return end
        repetition.attente = repetition.attente - (ecoule or 0)
        if repetition.attente <= 0 then
            repetition.attente = INTERVALLE
            local ok, souci = pcall(Traiter, win, repetition.bouton)
            if not ok then NS.base.NoterIncident("manette", souci) ArreterRepetition() end
        end
    end)
end

-- Centre et taille d'un element a l'ecran.
local function Boite(e)
    local l, b, w, h = e:GetLeft(), e:GetBottom(), e:GetWidth(), e:GetHeight()
    if not l or not b or not w or not h then return nil end
    return { l = l, r = l + w, b = b, t = b + h, x = l + w / 2, y = b + h / 2, h = h }
end

-- La zone ou l'on navigue : la page qui defile, ou la page fixe de l'equipement.
local function ZoneDe(win)
    if NS.ecran.page == "equipement" then return win.zoneFixe end
    return win.defilement
end

-- Premier element visible dans la zone, dans l'ordre de lecture.
local function PremierVisible(win, liste)
    local zone = Boite(ZoneDe(win) or win)
    if zone then
        for _, e in ipairs(liste) do
            local b = Boite(e)
            if b and b.t <= zone.t + 2 and b.b >= zone.b - 2 then return e end
        end
    end
    return liste[1]
end

-- Deplacement dans une direction, d'apres les positions a l'ecran.
-- dx, dy : -1, 0 ou 1 (dy = 1 vers le bas).
local function DeplacerVers(win, dx, dy)
    local liste = ElementsDeLaPage(win)
    if #liste == 0 then Relacher() rangFocus = 0 return end
    local depart = focus and focus:IsVisible() and Boite(focus)
    if not depart then
        local premier = PremierVisible(win, liste)
        for rang, e in ipairs(liste) do if e == premier then rangFocus = rang end end
        Choisir(win, premier)
        return
    end
    local meilleur, scoreMin
    for rang, e in ipairs(liste) do
        local b = e ~= focus and Boite(e)
        if b then
            local score
            if dy ~= 0 then
                -- Ligne du dessus ou du dessous, au plus pres, puis la meme
                -- colonne : chevauchement horizontal d'abord, centre ensuite.
                local avance = (dy > 0) and (depart.y - b.y) or (b.y - depart.y)
                if avance > 4 then
                    local ecart = math.max(0, math.max(depart.l, b.l) - math.min(depart.r, b.r))
                    score = avance * 4 + ecart * 2 + math.abs(b.x - depart.x) * 0.01
                    -- Equipement : on monte et descend dans sa colonne seulement
                    -- (cases de gauche, cases de droite, objets a comparer) ;
                    -- pour changer de colonne, gauche ou droite.
                    if NS.ecran.page == "equipement" and ecart > 0 then score = nil end
                end
            else
                -- Meme ligne seulement, l'element le plus proche dans le sens.
                -- La meme ligne d'abord ; sinon l'element le plus proche dans ce
                -- sens (d'une case d'equipement a la liste d'objets, par exemple).
                local ecartV = math.abs(b.y - depart.y)
                local memeLigne = ecartV < math.max(depart.h, b.h) / 2 + 2
                local avance = (dx > 0) and (b.x - depart.x) or (depart.x - b.x)
                if avance > 2 then
                    score = memeLigne and avance or (10000 + avance + ecartV * 2)
                end
            end
            if score and (not scoreMin or score < scoreMin) then
                meilleur, scoreMin = { e, rang }, score
            end
        end
    end
    if not meilleur then
        -- Plus rien dans ce sens : en haut ou en bas, la page defile.
        if dy ~= 0 then Defiler(win, dy) end
        return
    end
    rangFocus = meilleur[2]
    Choisir(win, meilleur[1])
end

-- Le liseré d'or autour de la zone centrale, bordure d'infobulle du jeu.
local function Lisere(win)
    if not win.lisereZone then
        local ok, cadre = pcall(CreateFrame, "Frame", nil, win, "BackdropTemplate")
        cadre = ok and cadre or CreateFrame("Frame", nil, win)
        if cadre.SetBackdrop then
            cadre:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
            cadre:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        cadre:EnableMouse(false)
        win.lisereZone = cadre
    end
    return win.lisereZone
end

local function MontrerZone(win)
    local cadre = Lisere(win)
    local zone = ZoneDe(win)
    if not enZone or not zone or not zone:IsShown() then cadre:Hide() return end
    cadre:ClearAllPoints()
    cadre:SetPoint("TOPLEFT", zone, "TOPLEFT", -6, 6)
    cadre:SetPoint("BOTTOMRIGHT", zone, "BOTTOMRIGHT", 6, -6)
    cadre:SetFrameLevel((zone:GetFrameLevel() or 1) + 20)
    cadre:Show()
end

local function SortirDeLaZone(win)
    if not enZone then return end
    enZone = false
    Relacher()
    rangFocus = 0
    MontrerZone(win)
    NS.ecran.Actualiser()
end

local function BasculerZone(win)
    if enZone then SortirDeLaZone(win) return end
    enZone = true
    rangFocus = 0
    NS.ecran.Actualiser()
    DeplacerVers(win, 0, 1)
    MontrerZone(win)
end

-- Apres chaque dessin : les lignes sont reutilisees, l'element choisi est
-- donc retrouve par son rang, borne a ce qui existe encore.
function manette.ApresRendu(win)
    manette.Brancher(win)
    if not manette.Active() then enZone = false Relacher() MontrerZone(win) return end
    MontrerZone(win)
    -- Hors de la zone centrale, rien n'est choisi : la croix fait defiler.
    if not enZone then Relacher() return end
    if rangFocus == 0 then Relacher() return end
    local liste = ElementsDeLaPage(win)
    if #liste == 0 then Relacher() rangFocus = 0 return end
    rangFocus = math.min(rangFocus, #liste)
    Choisir(win, liste[rangFocus])
end

-- Changer de section ou de personnage repart du haut de la page.
local function Repartir()
    Relacher()
    rangFocus = 0
    enZone = false
end

-- ---------------------------------------------------------------------------
-- Boutons
-- ---------------------------------------------------------------------------

local function Cliquer(bouton)
    if not focus or not focus:IsVisible() then return end
    if focus.Click then focus:Click(bouton) end
end

-- Renvoie vrai pour laisser le bouton au jeu, faux s'il est traite ici.
Traiter = function(win, bouton)
    local ecran = NS.ecran
    local aide, didacticiel = NS.aide, NS.didacticiel

    -- L'aide ouverte passe avant tout.
    if aide and aide.EstOuverte() then
        if bouton == "PAD2" or bouton == "PAD1" then aide.Cacher() return false end
        if bouton == "PAD4" then aide.LancerDidacticielAffiche() return false end
        if bouton == "PAD3" then aide.BasculerGuide() return false end
        if bouton == "PADDUP" then aide.Defiler(-1) return false end
        if bouton == "PADDDOWN" then aide.Defiler(1) return false end
        return true
    end

    if bouton == "PADBACK" then BasculerZone(win) return false end
    if enZone then
        if bouton == "PAD2" then SortirDeLaZone(win) return false end
        if bouton == "PADDUP" then DeplacerVers(win, 0, -1) return false end
        if bouton == "PADDDOWN" then DeplacerVers(win, 0, 1) return false end
        if bouton == "PADDLEFT" then DeplacerVers(win, -1, 0) return false end
        if bouton == "PADDRIGHT" then DeplacerVers(win, 1, 0) return false end
        if bouton == "PAD1" then Cliquer("LeftButton") return false end
        if bouton == "PAD3" then Cliquer("RightButton") return false end
        -- Toute autre navigation fait sortir de la zone (Repartir).
    end

    -- Curseur sur les add-ons de la suite (en haut a droite) : la croix s'y
    -- deplace, A ouvre, B ou la croix gauche au bout revient aux portraits.
    local S = NS.suite
    if S and S.CurseurActif and S.CurseurActif(win) then
        if bouton == "PADDLEFT" then S.CurseurDeplacer(win, -1) return false end
        if bouton == "PADDRIGHT" then S.CurseurDeplacer(win, 1) return false end
        if bouton == "PAD1" then S.CurseurValider(win) return false end
        if bouton == "PAD2" then S.CurseurQuitter(win) return false end
        S.CurseurQuitter(win)
    end

    if bouton == "PAD2" then
        if didacticiel and didacticiel.EnCours() then didacticiel.Quitter() return false end
        win:Hide()
        return false
    end
    if bouton == "PAD4" then
        if didacticiel and didacticiel.EnCours() then didacticiel.Pas(1) return false end
        if aide then aide.Basculer(ecran.page) end
        return false
    end
    if bouton == "PADLSHOULDER" then Repartir() ecran.PageVoisine(-1) return false end
    if bouton == "PADRSHOULDER" then Repartir() ecran.PageVoisine(1) return false end
    if bouton == "PADLTRIGGER" then Repartir() ecran.MetierVoisin(-1) return false end
    if bouton == "PADRTRIGGER" then Repartir() ecran.MetierVoisin(1) return false end
    if bouton == "PADDLEFT" then Repartir() ecran.PersonnageVoisin(-1) return false end
    if bouton == "PADDRIGHT" then Repartir() ecran.PersonnageVoisin(1) return false end
    -- Hors de la zone centrale, la croix haut / bas fait defiler la page.
    if bouton == "PADDUP" then Defiler(win, -1) return false end
    if bouton == "PADDDOWN" then Defiler(win, 1) return false end
    return true
end

-- Branche la fenetre une seule fois. Sans lecture de manette dans ce client,
-- rien n'est branche et le reste de l'addon ne change pas.
function manette.Brancher(win)
    if not win or win.craftCoreManette then return end
    if not win.EnableGamePadButton or not win.SetScript then return end
    win.craftCoreManette = true
    local ok = pcall(win.EnableGamePadButton, win, true)
    if not ok then return end
    win:SetScript("OnGamePadButtonDown", function(self, bouton)
        -- Vue tenue + LB / RB : add-on voisin (la suite s'en charge).
        local S = NS.suite
        if S and S.ManetteBas then
            local okS, pris = pcall(S.ManetteBas, (NS.ecran.EstStuff and NS.ecran.EstStuff(NS.ecran.page)) and "StuffCore" or "CraftCore", bouton)
            if okS and pris then return false end
        end
        local okT, laisser = pcall(Traiter, self, bouton)
        if not okT then
            NS.base.NoterIncident("manette", laisser)
            return true
        end
        -- Croix haut / bas maintenue : le pas se repete, comme une touche de
        -- clavier qu'on garde enfoncee.
        if laisser == false and (bouton == "PADDUP" or bouton == "PADDDOWN"
            or (enZone and (bouton == "PADDLEFT" or bouton == "PADDRIGHT"))) then
            Repeter(self, bouton)
        end
        return laisser
    end)
    pcall(win.SetScript, win, "OnGamePadButtonUp", function(self, bouton)
        if bouton == repetition.bouton then ArreterRepetition() end
        -- Vue relachee sans LB / RB : son action habituelle (entrer dans la page).
        local S = NS.suite
        if S and S.ManetteHaut and S.ManetteHaut(bouton) then
            local okT, souci = pcall(Traiter, self, "PADBACK")
            if not okT then NS.base.NoterIncident("manette", souci) end
        end
    end)
    win:HookScript("OnHide", function() Repartir() MontrerZone(win) end)
    win:HookScript("OnHide", function() ArreterRepetition() end)
end
