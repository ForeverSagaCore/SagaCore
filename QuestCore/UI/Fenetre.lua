local _, NS = ...

-- Les boutons d'une quete : sans "Toute la suite" quand la suite n'a qu'une
-- quete (le premier bouton).
local function SansSuiteSiSeule(n, boutons)
    if (n or 0) <= 1 then table.remove(boutons, 1) end
    return boutons
end

-- Fenetre principale : les personnages a gauche, a droite les quetes en
-- cours du personnage choisi (par zone, comme le journal du jeu), puis ce
-- qu'il peut fournir aux autres et ce que les autres peuvent lui fournir.

NS.fenetre = {}
local fen = NS.fenetre
local L = NS.L

-- Meme taille que la fenetre de CraftCore : la page d'equipement est la sienne.
local LARGEUR, HAUTEUR = 1060, 740
local HAUTEUR_BANDEAU = 118
local LARGEUR_LISTE = 170
-- Ecart du menu au filet, et du filet au contenu : le meme que CraftCore.
local ECART_MENU = 14
local HAUTEUR_LIGNE = 20
local RETRAIT = 16
local ESPACE_SECTION = 14

local cadre
local etat = { cle = nil, ouvertes = {} }

-- Personnage choisi : le meme dans toute la suite (CraftCore, QuestCore).
-- Les personnages de la faction regardee (onglets Alliance / Horde).
local function PersosVisibles()
    local S, liste = NS.suite, {}
    for _, p in ipairs(NS.base.Persos()) do
        if not (S and S.Visible) or S.Visible(p.cle) then table.insert(liste, p) end
    end
    return liste
end

local function ChoisirPerso(cle)
    etat.cle = cle
    local S = NS.suite
    if S and S.PoserPersonnage and cle then etat.persoVu = S.PoserPersonnage(cle) end
end

-- Applique le choix fait dans un autre add-on, s'il est plus recent.
local function SuivreLaSuite()
    local S = NS.suite
    if not (S and S.Personnage) then return end
    local cle, version = S.Personnage()
    if version and version ~= etat.persoVu then
        etat.persoVu = version
        if cle and NS.base.PersoParCle(cle) then etat.cle = cle end
    end
end

-- ---------------------------------------------------------------------------
-- Lignes : une seule fabrique, reutilisee d'un dessin a l'autre.
-- ---------------------------------------------------------------------------

local function Ligne(contenu, index)
    contenu.lignes = contenu.lignes or {}
    local l = contenu.lignes[index]
    if l then return l end
    l = CreateFrame("Button", nil, contenu)
    l:SetHeight(HAUTEUR_LIGNE)
    pcall(l.RegisterForClicks, l, "LeftButtonUp")
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.marqueur = l:CreateTexture(nil, "ARTWORK")
    l.marqueur:SetSize(14, 14)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.droite = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.droite:SetPoint("RIGHT", l, "RIGHT", -6, 0)
    l.droite:SetJustifyH("RIGHT")
    l.gauche = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.gauche:SetJustifyH("LEFT")
    l.gauche:SetWordWrap(false)
    l.gauche:SetPoint("RIGHT", l.droite, "LEFT", -12, 0)
    l.filet = l:CreateTexture(nil, "ARTWORK")
    NS.charte.Filet(l.filet, l)
    l.filet:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    NS.charte.PoliceStable(l.gauche)
    contenu.lignes[index] = l
    return l
end

-- Pose une ligne : retrait, marqueur de depliage, icone, textes, clic.
local function Poser(contenu, index, y, options)
    local l = Ligne(contenu, index)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, -y)
    l:SetPoint("TOPRIGHT", contenu, "TOPRIGHT", 0, -y)
    local x = 2 + (options.retrait or 0)
    l.marqueur:ClearAllPoints()
    l.marqueur:SetPoint("LEFT", l, "LEFT", x, 0)
    if options.depliable then
        l.marqueur:SetTexture(options.deplie and "Interface\\Buttons\\UI-MinusButton-Up"
            or "Interface\\Buttons\\UI-PlusButton-Up")
        l.marqueur:Show()
        x = x + 18
    else
        l.marqueur:Hide()
    end
    if l.rond then l.rond:Hide() end
    l.icone:ClearAllPoints()
    l.icone:SetPoint("LEFT", l, "LEFT", x, 0)
    if options.etatQuete ~= nil then
        -- Le rond du journal de quetes du jeu, comme dans le suivi.
        if options.etatQuete == -1 or not (NS.suivi and NS.suivi.Rond and NS.suivi.Rond(l, options.etatQuete, x - 1, -1)) then
            NS.suivi.Icone(l.icone, options.etatQuete)
            l.icone:Show()
        else
            l.icone:Hide()
        end
        x = x + 20
    elseif options.icone then
        l.icone:SetTexture(options.icone)
        l.icone:Show()
        x = x + 20
    else
        l.icone:Hide()
    end
    l.gauche:ClearAllPoints()
    l.gauche:SetPoint("LEFT", l, "LEFT", x, 0)
    l.gauche:SetPoint("RIGHT", l.droite, "LEFT", -12, 0)
    l.gauche:SetFontObject(options.police or "GameFontHighlightSmall")
    l.gauche:SetText(options.texte or "")
    local c = options.couleur or { 1, 1, 1 }
    -- Pleine opacite : une ligne reprise d'un texte explicatif (40 %) ne
    -- doit pas le rester.
    l.gauche:SetTextColor(c[1], c[2], c[3], 1)
    local hauteurLigne = HAUTEUR_LIGNE
    if options.section and NS.charte.TitreDeSection(l.gauche, l.filet) then hauteurLigne = HAUTEUR_LIGNE + 6 end
    l:SetHeight(hauteurLigne)
    l.droite:ClearAllPoints()
    l.droite:SetPoint("RIGHT", l, "RIGHT", -(options.decalageDroite or 6), 0)
    l.droite:SetText(options.droite or "")
    -- Ligne mise en avant (zone ou l'on se trouve).
    if options.surligne then
        if not l.surligne then
            l.surligne = l:CreateTexture(nil, "BACKGROUND")
            l.surligne:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            l.surligne:SetBlendMode("ADD")
            l.surligne:SetAllPoints()
        end
        l.surligne:Show()
    elseif l.surligne then
        l.surligne:Hide()
    end
    local cd = options.couleurDroite or { 0.6, 0.6, 0.6 }
    l.droite:SetTextColor(cd[1], cd[2], cd[3])
    l.filet:SetShown(options.filet == true)
    -- Barre d'avancement a la facon des reputations du jeu : barre des
    -- competences et reputations de la fiche de personnage, cadre dore,
    -- texte blanc dessus ; couleur selon l'avancement, comme les niveaux de
    -- reputation (rouge, orange, jaune, vert).
    if options.barre then
        if not l.barre then
            local ok, b = pcall(CreateFrame, "StatusBar", nil, l, "BackdropTemplate")
            b = ok and b or CreateFrame("StatusBar", nil, l)
            b.sansEncre = true
            b:SetSize(170, 10)
            b:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
            b:SetMinMaxValues(0, 1)
            b.fond = b:CreateTexture(nil, "BACKGROUND")
            b.fond:SetAllPoints()
            b.fond:SetColorTexture(0, 0, 0, 0.65)
            local okC, cadreBarre = pcall(CreateFrame, "Frame", nil, b, "BackdropTemplate")
            cadreBarre = okC and cadreBarre or CreateFrame("Frame", nil, b)
            cadreBarre:SetPoint("TOPLEFT", -2, 2)
            cadreBarre:SetPoint("BOTTOMRIGHT", 2, -2)
            if cadreBarre.SetBackdrop then
                -- Bordure d'infobulle du jeu : coins arrondis.
                cadreBarre:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
                cadreBarre:SetBackdropBorderColor(0.8, 0.65, 0.35, 1)
            end
            cadreBarre:SetFrameLevel(b:GetFrameLevel() + 2)
            b.texte = cadreBarre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.texte:SetPoint("CENTER", b, "CENTER", 0, 0)
            local fichier, _, drapeaux = b.texte:GetFont()
            if fichier then b.texte:SetFont(NS.Police(fichier), 9, drapeaux) end
            b.texte:SetShadowOffset(1, -1)
            l.barre = b
        end
        l.barre:ClearAllPoints()
        l.barre:SetPoint("RIGHT", l, "RIGHT", -28, 0)
        l.barre:SetSize(options.barreHaute and 200 or 170, options.barreHaute and 12 or 10)
        l.barre:SetValue(options.barre)
        local c = options.couleurBarre
        if not c then
            local couleurs = _G.FACTION_BAR_COLORS
            local rang = (options.barre >= 1 and 8) or (options.barre >= 0.75 and 5) or (options.barre >= 0.5 and 4)
                or (options.barre >= 0.25 and 3) or 2
            local f = type(couleurs) == "table" and couleurs[rang]
            c = f and { f.r, f.g, f.b } or { 0.2, 0.7, 0.2 }
        end
        l.barre:SetStatusBarColor(c[1], c[2], c[3])
        l.barre.texte:SetText(options.texteBarre or "")
        l.barre.texte:SetTextColor(1, 1, 1)
        l.barre:Show()
        l.droite:SetText("")
        l.gauche:SetPoint("RIGHT", l.barre, "LEFT", -12, 0)
    elseif l.barre then
        l.barre:Hide()
    end
    if l.journal then l.journal:Hide() end
    -- Rangee de boutons du jeu, de gauche a droite, a la place du texte.
    l.boutons = l.boutons or {}
    for _, b in ipairs(l.boutons) do b:Hide() end
    local bx = x
    local defs = options.boutons or {}
    -- A droite (sur la ligne d'un titre) : du dernier au premier.
    local aDroite = options.boutonsADroite == true
    local suivant
    for rang, def in ipairs(defs) do
        local b = l.boutons[rang]
        if not b then
            b = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
            b:SetHeight(18)
            l.boutons[rang] = b
        end
        b:SetText(def[1])
        b:SetWidth(math.max(60, (b.GetTextWidth and b:GetTextWidth() or 50) + 24))
        b:ClearAllPoints()
        b:SetScript("OnClick", def[2])
        b:SetEnabled(def[3] ~= false)
        b:Show()
        bx = bx + b:GetWidth() + 6
    end
    -- Placement : de gauche a droite, ou cale a droite en partant du dernier.
    if aDroite then
        for rang = #defs, 1, -1 do
            local b = l.boutons[rang]
            if suivant then b:SetPoint("RIGHT", suivant, "LEFT", -6, 0) else b:SetPoint("RIGHT", l, "RIGHT", -4, 2) end
            suivant = b
        end
        l.gauche:SetPoint("RIGHT", suivant or l.droite, "LEFT", -12, 0)
    else
        local px = x
        for rang = 1, #defs do
            local b = l.boutons[rang]
            b:SetPoint("LEFT", l, "LEFT", px, 0)
            px = px + b:GetWidth() + 6
        end
    end
    l:SetScript("OnClick", options.auClic)
    l:EnableMouse(options.auClic ~= nil or options.survol ~= nil)
    local hl = l:GetHighlightTexture()
    if hl then hl:SetAlpha(options.auClic and 1 or 0) end
    l:SetScript("OnEnter", options.survol)
    l:SetScript("OnLeave", options.survol and function() GameTooltip:Hide() end or nil)
    l:Show()
    return y + hauteurLigne
end

-- Titre de page ou de section, dans la police des titres ; ses boutons
-- d'action (un a trois) sur la meme ligne, cales a droite.
local function Titre(contenu, index, y, texte, boutons)
    if y > 0 then y = y + ESPACE_SECTION end
    y = Poser(contenu, index, y, { texte = texte, section = true, filet = true, boutons = boutons, boutonsADroite = true })
    return y + 6
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

local function Etat(p, id)
    local e = NS.ref.Etat(p, id)
    if e == "faite" then return L.STATE_DONE, { 0.31, 0.82, 0.41 } end
    if e == "en cours" then return L.STATE_ACTIVE, { 1, 0.82, 0 } end
    return L.STATE_TODO, { 0.6, 0.6, 0.6 }
end

-- Apres un changement de parcours : fenetre, suivi et carte a jour.
local function ParcoursChange()
    if NS.carte then
        NS.carte.Invalider()
        pcall(NS.carte.Rendre)
    end
    if NS.suivi then pcall(NS.suivi.Rendre) end
    fen.Rendre()
end

local function SurvolObjet(objet)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, objet) end
        GameTooltip:Show()
    end
end

local function RendreQuetes(contenu, p, index, y)
    -- Par zone, comme les en-tetes du journal du jeu ; dans une zone, par niveau.
    local parZone, zones = {}, {}
    local total = 0
    -- Filtre : toutes les quetes, ou seulement celles a rendre.
    local filtre = NS.base.FiltreARendre()
    local nRendre = NS.base.NombreARendre(p)
    local boutonsTitre = {
        { L.TURNIN_ALL, function() NS.base.PoserFiltreARendre(false) end, filtre },
        { string.format(L.TURNIN_TAB, nRendre), function() NS.base.PoserFiltreARendre(true) end, not filtre },
        -- Le meme bouton Guider que le suivi (personnage connecte seulement).
        (p.cle == NS.ClePersonnage()) and { NS.guidage.EstActif("rendus", {}) and L.GUIDE_STOP or L.GUIDE_START, function()
            NS.guidage.Basculer("rendus", {})
            fen.Rendre()
        end, nRendre > 0 or NS.guidage.EstActif("rendus", {}) } or nil,
    }
    for id, q in pairs(p.quetes or {}) do
      if not filtre or q.complete == true then
        local zone = q.zone or L.ZONE_OTHER
        if not parZone[zone] then parZone[zone] = {} table.insert(zones, zone) end
        table.insert(parZone[zone], id)
        total = total + 1
      end
    end
    table.sort(zones)
    index = index + 1
    y = Titre(contenu, index, y, string.format(filtre and L.TURNIN_TITLE or L.ACTIVE, total), boutonsTitre)
    if total == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = filtre and L.TURNIN_NONE or L.NONE_ACTIVE,
            couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    for _, zone in ipairs(zones) do
        -- Zone repliable, son + au bord gauche du filet, comme les disponibles.
        local cleZ = "qz" .. zone
        local fermeeZ = etat.ouvertes[cleZ] == false
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = not fermeeZ, texte = zone,
            police = "GameFontNormalSmall", couleur = { 1, 0.82, 0 },
            auClic = function()
                if etat.ouvertes[cleZ] == false then etat.ouvertes[cleZ] = nil else etat.ouvertes[cleZ] = false end
                fen.Rendre()
            end })
        local ids = fermeeZ and {} or parZone[zone]
        table.sort(ids, function(a, b)
            local qa, qb = p.quetes[a], p.quetes[b]
            if (qa.niveau or 0) ~= (qb.niveau or 0) then return (qa.niveau or 0) < (qb.niveau or 0) end
            return tostring(qa.titre) < tostring(qb.titre)
        end)
        for _, id in ipairs(ids) do
            local q = p.quetes[id]
            local ouverte = etat.ouvertes[id] == true
            local r, g, b = NS.ref.CouleurDeNiveau(q.niveau, p.niveau)
            local droite, couleurDroite
            if q.complete == true then
                local receveurs = filtre and NS.ref.Receveurs(id) or {}
                droite = receveurs[1] and string.format(L.TRACK_TURN_IN, receveurs[1]) or L.DONE
                couleurDroite = { 0.31, 0.82, 0.41 }
            elseif q.complete == -1 then
                droite, couleurDroite = L.FAILED, { 0.9, 0.3, 0.3 }
            else
                local faits = 0
                for _, o in ipairs(q.objectifs or {}) do if o.fait then faits = faits + 1 end end
                droite = string.format(L.OBJ_COUNT, faits, #(q.objectifs or {}))
            end
            local idQuete = id
            index = index + 1
            local qSurvol = q
            y = Poser(contenu, index, y, { retrait = RETRAIT,
                etatQuete = (q.complete == true) and true or (q.complete == -1 and -1 or false),
                survol = function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    NS.ref.InfobulleDeQuete(GameTooltip, qSurvol, idQuete, p)
                    GameTooltip:Show()
                end,
                texte = string.format("[%d] %s", q.niveau or 0, q.titre or ("#" .. id)), couleur = { r, g, b },
                droite = droite, couleurDroite = couleurDroite,
                auClic = function()
                    etat.ouvertes[idQuete] = not etat.ouvertes[idQuete] or nil
                    fen.Rendre()
                end })
            if ouverte then
                local retrait2 = RETRAIT * 2 + 18
                for _, o in ipairs(q.objectifs or {}) do
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2, texte = "- " .. tostring(o.texte or ""),
                        couleur = o.fait and { 0.31, 0.82, 0.41 } or { 0.85, 0.85, 0.85 } })
                end
                -- Ce que rapporte la quete : argent et experience, puis les objets.
                local resume = NS.ref.ResumeRecompenses(q)
                if resume then
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2, texte = string.format(L.REWARD_LINE, resume),
                        couleur = { 1, 0.82, 0 } })
                end
                local r = q.recompenses
                for _, o in ipairs(r and r.objets or {}) do
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2, icone = NS.ref.IconeDObjet(o.objet),
                        texte = NS.ref.NomDObjet(o.objet) .. ((o.n or 1) > 1 and (" x" .. o.n) or ""),
                        couleur = { 1, 1, 1 }, survol = SurvolObjet(o.objet) })
                end
                for rang, o in ipairs(r and r.choix or {}) do
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2, icone = NS.ref.IconeDObjet(o.objet),
                        texte = (rang == 1 and (L.REWARD_CHOICE .. " ") or "") .. NS.ref.NomDObjet(o.objet)
                            .. ((o.n or 1) > 1 and (" x" .. o.n) or ""),
                        couleur = { 0.85, 0.85, 0.85 }, survol = SurvolObjet(o.objet) })
                end
                -- Parcours : toute la suite, ou cette quete dans un parcours libre.
                if NS.parcours then
                    local suite = NS.parcours.Suite(p, id)
                    local cleP = p.cle
                    index = index + 1
                    -- Une seule quete : pas de "toute la suite".
                    y = Poser(contenu, index, y + 2, { retrait = retrait2, boutons = SansSuiteSiSeule(#suite, {
                        { string.format(L.ROUTE_MAKE_CHAIN, #suite), function()
                            local pc = NS.parcours.CreerSuite(cleP, p, idQuete)
                            if pc then
                                etat.page = "parcours"
                                etat.ouvertes["pc" .. pc.id] = true
                            end
                            ParcoursChange()
                        end, #suite > 0 },
                        { L.ROUTE_ADD, function()
                            etat.ajoutParcours = (etat.ajoutParcours ~= idQuete) and idQuete or nil
                            fen.Rendre()
                        end },
                    }) }) + 2
                    if etat.ajoutParcours == idQuete then
                        local choix = {}
                        for _, pc in ipairs(NS.parcours.Liste(cleP)) do
                            if pc.genre == "selection" then
                                local idP = pc.id
                                table.insert(choix, { pc.nom, function()
                                    NS.parcours.Ajouter(cleP, idP, idQuete)
                                    etat.ajoutParcours = nil
                                    ParcoursChange()
                                end })
                            end
                        end
                        table.insert(choix, { L.ROUTE_NEW, function()
                            NS.parcours.CreerSelection(cleP, p, idQuete)
                            etat.ajoutParcours = nil
                            ParcoursChange()
                        end })
                        index = index + 1
                        y = Poser(contenu, index, y, { retrait = retrait2 + 12, boutons = choix }) + 2
                    end
                end
                local donneurs = NS.ref.Donneurs(id)
                if #donneurs > 0 then
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2,
                        texte = string.format(L.GIVEN_BY, table.concat(donneurs, ", ")), couleur = { 0.7, 0.7, 0.7 } })
                end
                local receveurs = NS.ref.Receveurs(id)
                if #receveurs > 0 then
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2,
                        texte = string.format(L.TURN_IN, table.concat(receveurs, ", ")), couleur = { 0.7, 0.7, 0.7 } })
                end
                local groupe, une = NS.ref.Prerequis(id)
                for _, pre in ipairs(groupe) do
                    local texteEtat, c = Etat(p, pre)
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2,
                        texte = string.format(L.PREREQ, NS.ref.NomDeQuete(pre, p)), couleur = { 0.7, 0.7, 0.7 },
                        droite = texteEtat, couleurDroite = c })
                end
                for _, pre in ipairs(une) do
                    local texteEtat, c = Etat(p, pre)
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2,
                        texte = string.format(L.PREREQ, NS.ref.NomDeQuete(pre, p)), couleur = { 0.7, 0.7, 0.7 },
                        droite = texteEtat, couleurDroite = c })
                end
                for _, suite in ipairs(NS.ref.Suites(id)) do
                    local texteEtat, c = Etat(p, suite)
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = retrait2,
                        texte = string.format(L.NEXT, NS.ref.NomDeQuete(suite, p)), couleur = { 0.7, 0.7, 0.7 },
                        droite = texteEtat, couleurDroite = c })
                end
                y = y + 4
            end
        end
    end
    return index, y
end

local function Origine(sacs, banque)
    if sacs > 0 and banque > 0 then return L.BAGS .. ", " .. L.BANK end
    return banque > 0 and L.BANK or L.BAGS
end

local function RendreEchanges(contenu, p, index, y)
    if not NS.ref.StocksDisponibles() then
        index = index + 1
        y = Titre(contenu, index, y, string.format(L.CAN_GIVE, 0))
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.NEED_CRAFTCORE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    local donner = NS.ref.CePeutFournir(p)
    index = index + 1
    y = Titre(contenu, index, y, string.format(L.CAN_GIVE, #donner))
    if #donner == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.CAN_GIVE_NONE, couleur = { 0.6, 0.6, 0.6 } })
    end
    for _, b in ipairs(donner) do
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = NS.ref.IconeDObjet(b.objet),
            texte = string.format(L.FOR_QUEST, NS.ref.NomDObjet(b.objet), NS.NomCourt(b.cle),
                NS.ref.NomDeQuete(b.quete, b.perso), b.n, b.requis),
            droite = (b.sacs + b.banque) .. " (" .. Origine(b.sacs, b.banque) .. ")",
            couleurDroite = { 0.31, 0.82, 0.41 }, survol = SurvolObjet(b.objet) })
    end
    local recevoir = NS.ref.CeQuOnPeutLuiFournir(p)
    index = index + 1
    y = Titre(contenu, index, y, string.format(L.CAN_GET, #recevoir))
    if #recevoir == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.CAN_GET_NONE, couleur = { 0.6, 0.6, 0.6 } })
    end
    for _, b in ipairs(recevoir) do
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, icone = NS.ref.IconeDObjet(b.objet),
            texte = NS.ref.NomDObjet(b.objet) .. " : " .. NS.ref.NomDeQuete(b.quete, p) .. " ("
                .. b.n .. "/" .. b.requis .. ")",
            droite = string.format(L.FROM_CHAR, NS.NomCourt(b.cle), b.sacs + b.banque, Origine(b.sacs, b.banque)),
            couleurDroite = { 1, 0.82, 0 }, survol = SurvolObjet(b.objet) })
    end
    return index, y
end

-- Personnages en haut, comme dans CraftCore : un portrait encadre par
-- personnage (le vrai pour le connecte, l'icone de classe pour les autres).
-- Le suivi, lui, reste toujours sur le personnage connecte.
local TAILLE_PORTRAIT = 30

local function PoserVisage(texture, p, estConnecte)
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
    -- Halo un peu plus grand que le portrait, comme dans CraftCore.
    b.halo:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.halo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.halo:SetBlendMode("ADD")
    b.halo:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function RendreListe()
    local bande = cadre.bande
    local persos = PersosVisibles()
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
        b.halo:SetShown(p.cle == etat.cle)
        b:SetAlpha(p.cle == etat.cle and 1 or 0.7)
        local cle, perso = p.cle, p
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(NS.NomCourt(cle), 1, 0.82, 0)
            if perso.niveau then GameTooltip:AddLine(string.format(L.LEVEL, perso.niveau), 1, 1, 1) end
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
-- Quetes communes : celles qu'au moins deux personnages ont en cours.
-- ---------------------------------------------------------------------------

local function Avancement(q)
    if q.complete == true then return L.DONE, { 0.31, 0.82, 0.41 } end
    if q.complete == -1 then return L.FAILED, { 0.9, 0.3, 0.3 } end
    local faits = 0
    for _, o in ipairs(q.objectifs or {}) do if o.fait then faits = faits + 1 end end
    return string.format(L.OBJ_COUNT, faits, #(q.objectifs or {})), nil
end

local function RendreCommunes(contenu, index, y)
    local parQuete = {}
    for _, p in ipairs(PersosVisibles()) do
        for id, q in pairs(p.quetes or {}) do
            parQuete[id] = parQuete[id] or {}
            table.insert(parQuete[id], { p = p, q = q })
        end
    end
    local parZone, zones, total = {}, {}, 0
    for id, liste in pairs(parQuete) do
        if #liste >= 2 then
            local zone = liste[1].q.zone or L.ZONE_OTHER
            if not parZone[zone] then parZone[zone] = {} table.insert(zones, zone) end
            table.insert(parZone[zone], id)
            total = total + 1
        end
    end
    table.sort(zones)
    index = index + 1
    y = Titre(contenu, index, y, string.format(L.COMMON_TITLE, total))
    if total == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.COMMON_NONE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    for _, zone in ipairs(zones) do
        -- Zone repliable, son + au bord gauche du filet, comme les disponibles.
        local cleZ = "qz" .. zone
        local fermeeZ = etat.ouvertes[cleZ] == false
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = not fermeeZ, texte = zone,
            police = "GameFontNormalSmall", couleur = { 1, 0.82, 0 },
            auClic = function()
                if etat.ouvertes[cleZ] == false then etat.ouvertes[cleZ] = nil else etat.ouvertes[cleZ] = false end
                fen.Rendre()
            end })
        local ids = fermeeZ and {} or parZone[zone]
        table.sort(ids, function(a, b)
            local qa, qb = parQuete[a][1].q, parQuete[b][1].q
            if (qa.niveau or 0) ~= (qb.niveau or 0) then return (qa.niveau or 0) < (qb.niveau or 0) end
            return tostring(qa.titre) < tostring(qb.titre)
        end)
        for _, id in ipairs(ids) do
            local liste = parQuete[id]
            table.sort(liste, function(a, b) return tostring(a.p.cle) < tostring(b.p.cle) end)
            local q, premier = liste[1].q, liste[1].p
            local cleOuverte = "commune" .. id
            local ouverte = etat.ouvertes[cleOuverte] == true
            local r, g, b = NS.ref.CouleurDeNiveau(q.niveau, premier.niveau)
            local idQuete = id
            index = index + 1
            y = Poser(contenu, index, y, { retrait = RETRAIT,
                texte = string.format("[%d] %s", q.niveau or 0, q.titre or ("#" .. id)), couleur = { r, g, b },
                droite = string.format(L.COMMON_COUNT, #liste),
                survol = function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    NS.ref.InfobulleDeQuete(GameTooltip, q, idQuete, premier)
                    GameTooltip:Show()
                end,
                auClic = function()
                    etat.ouvertes[cleOuverte] = not etat.ouvertes[cleOuverte] or nil
                    fen.Rendre()
                end })
            -- Ou en est chacun.
            for _, e in ipairs(liste) do
                local texteEtat, couleurEtat = Avancement(e.q)
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT * 2,
                    etatQuete = (e.q.complete == true) and true or (e.q.complete == -1 and -1 or false),
                    texte = NS.NomCourt(e.p.cle), couleur = { 0.9, 0.9, 0.9 },
                    droite = texteEtat, couleurDroite = couleurEtat })
                if ouverte then
                    for _, o in ipairs(e.q.objectifs or {}) do
                        index = index + 1
                        y = Poser(contenu, index, y, { retrait = RETRAIT * 3 + 18,
                            texte = "- " .. tostring(o.texte or ""),
                            couleur = o.fait and { 0.31, 0.82, 0.41 } or { 0.85, 0.85, 0.85 } })
                    end
                end
            end
        end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Parcours : suites de quetes a faire dans l'ordre, comme les projets de
-- CraftCore.
-- ---------------------------------------------------------------------------

local COULEURS_ETAPE = {
    faite = { 0.31, 0.82, 0.41 }, rendre = { 0.31, 0.82, 0.41 }, cours = { 1, 0.82, 0 },
    prendre = { 1, 0.82, 0 }, attente = { 0.6, 0.6, 0.6 },
}

local function TexteEtape(p, id, e)
    if e == "faite" then return L.STATE_DONE end
    if e == "rendre" then return L.DONE end
    if e == "cours" then
        local q = p.quetes[id]
        local faits = 0
        for _, o in ipairs(q.objectifs or {}) do if o.fait then faits = faits + 1 end end
        return string.format(L.OBJ_COUNT, faits, #(q.objectifs or {}))
    end
    if e == "prendre" then return L.ROUTE_TO_TAKE end
    local niveau = tonumber(NS.ref.Lire("QuestDB", id, "requiredLevel")) or 0
    if p.niveau and niveau > p.niveau then return string.format(L.ROUTE_LEVEL, niveau) end
    return L.ROUTE_WAITING
end

local function SurvolEtape(p, id)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local q = p.quetes and p.quetes[id]
        if q then
            NS.ref.InfobulleDeQuete(GameTooltip, q, id, p)
        else
            NS.ref.InfobulleDeLaBase(GameTooltip, id, p)
        end
        GameTooltip:Show()
    end
end

local function RendreParcours(contenu, p, index, y)
    local liste = NS.parcours.Liste(p.cle)
    -- Progression : seulement pour le personnage connecte (son experience).
    local connecte = p.cle == NS.ClePersonnage()
    local manque = connecte and NS.disponibles.XPManquante() or 0
    index = index + 1
    y = Titre(contenu, index, y, string.format(L.ROUTE_TITLE, #liste), {
        { connecte and string.format(L.ROUTE_MAKE_LEVEL, (p.niveau or 0) + 1, manque) or L.ROUTE_MAKE_LEVEL_OFF,
            function()
                -- Le guidage vers le niveau suivant (objectif "niveau").
                local ok, lance = pcall(NS.guidage.Lancer, "niveau", { niveau = (p.niveau or 0) + 1 })
                if not ok then NS.base.NoterIncident("progression", lance) return end
                fen.Rendre()
            end, connecte and manque > 0 },
    })
    if #liste == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.ROUTE_NONE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    -- Regroupes par genre, chaque groupe se replie.
    local groupes = {
        { cle = "suite", titre = L.ROUTE_GROUP_CHAINS, aide = L.ROUTE_GROUP_CHAINS_HELP, liste = {} },
        { cle = "selection", titre = L.ROUTE_GROUP_FREE, aide = L.ROUTE_GROUP_FREE_HELP, liste = {} },
        { cle = "progression", titre = L.ROUTE_GROUP_LEVEL, aide = L.ROUTE_GROUP_LEVEL_HELP, liste = {} },
        { cle = "kit", titre = L.ROUTE_GROUP_KIT, aide = L.ROUTE_GROUP_KIT_HELP, liste = {} },
    }
    for _, pc in ipairs(liste) do
        table.insert((pc.genre == "suite" and groupes[1].liste) or (pc.genre == "progression" and groupes[3].liste)
            or (pc.genre == "kit" and groupes[4].liste) or groupes[2].liste, pc)
    end
    for _, groupe in ipairs(groupes) do
      if #groupe.liste > 0 then
        local cleGroupe = "grp" .. groupe.cle
        local groupeFerme = etat.ouvertes[cleGroupe] == false
        -- Chaque genre de parcours sous son propre titre de section (comme
        -- les autres pages), avec ce qu'il est, en une ligne.
        if y > 0 then y = y + ESPACE_SECTION end
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = not groupeFerme, section = true, filet = true,
            texte = groupe.titre .. " (" .. #groupe.liste .. ")",
            auClic = function()
                if etat.ouvertes[cleGroupe] == false then etat.ouvertes[cleGroupe] = nil
                else etat.ouvertes[cleGroupe] = false end
                fen.Rendre()
            end }) + 2
        if not groupeFerme and groupe.aide then
            index = index + 1
            y = Poser(contenu, index, y, { retrait = RETRAIT, texte = groupe.aide, police = "GameFontDisableSmall",
                couleur = { 0.6, 0.6, 0.6 } }) + 2
        end
      if not groupeFerme then
    for _, pc in ipairs(groupe.liste) do
        local faites, total, pct = NS.parcours.Avancement(p, pc)
        local cleOuverte = "pc" .. pc.id
        local ouvert = etat.ouvertes[cleOuverte] == true
        local idP = pc.id
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, depliable = true, deplie = ouvert,
            police = "GameFontNormalSmall", texte = pc.nom, couleur = { 1, 0.82, 0 },
            droite = string.format(L.ROUTE_PROGRESS, faites, total, pct),
            couleurDroite = pct >= 100 and { 0.31, 0.82, 0.41 } or { 1, 1, 1 },
            auClic = function()
                etat.ouvertes[cleOuverte] = not etat.ouvertes[cleOuverte] or nil
                fen.Rendre()
            end })
        if pc.genre == "progression" and pc.objectifXP then
            index = index + 1
            y = Poser(contenu, index, y, { retrait = RETRAIT, couleur = { 0.75, 0.75, 0.75 },
                texte = string.format(L.ROUTE_LEVEL_PLAN, pc.xpPrevue or 0, pc.objectifXP)
                    .. (pc.tempsPrevu and string.format(L.ROUTE_TIME_PLAN, math.max(1, math.floor(pc.tempsPrevu / 60 + 0.5)))
                    or "") })
        end
        -- La prochaine chose a faire, toujours visible.
        local rang, prochaine = NS.parcours.Prochaine(p, pc)
        index = index + 1
        if prochaine then
            local e = NS.parcours.EtatEtape(p, prochaine)
            y = Poser(contenu, index, y, { retrait = RETRAIT,
                texte = string.format(L.ROUTE_NEXT, rang, NS.ref.NomDeQuete(prochaine, p)),
                couleur = { 0.9, 0.9, 0.9 }, droite = TexteEtape(p, prochaine, e), couleurDroite = COULEURS_ETAPE[e],
                survol = SurvolEtape(p, prochaine) })
        else
            y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.ROUTE_FINISHED, couleur = { 0.31, 0.82, 0.41 } })
        end
        if ouvert then
            for r, id in ipairs(pc.etapes) do
                local e = NS.parcours.EtatEtape(p, id)
                local choisie = etat.etapeChoisie and etat.etapeChoisie[1] == idP and etat.etapeChoisie[2] == r
                local niveau = (p.quetes[id] and p.quetes[id].niveau) or NS.ref.Lire("QuestDB", id, "questLevel") or 0
                local rangEtape = r
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT * 2,
                    etatQuete = (e == "rendre") and true or ((e == "cours") and false or nil),
                    icone = (e == "prendre") and "Interface\\GossipFrame\\AvailableQuestIcon" or nil,
                    texte = (tonumber(niveau) or 0) > 0
                        and string.format("%d. [%d] %s", r, niveau, NS.ref.NomDeQuete(id, p))
                        or string.format("%d. %s", r, NS.ref.NomDeQuete(id, p)),
                    couleur = (e == "faite") and { 0.55, 0.55, 0.55 } or { 1, 1, 1 },
                    droite = TexteEtape(p, id, e), couleurDroite = COULEURS_ETAPE[e],
                    survol = SurvolEtape(p, id),
                    auClic = function()
                        if choisie then etat.etapeChoisie = nil else etat.etapeChoisie = { idP, rangEtape } end
                        fen.Rendre()
                    end })
                if choisie then
                    index = index + 1
                    y = Poser(contenu, index, y + 2, { retrait = RETRAIT * 3, boutons = {
                        { L.ROUTE_UP, function()
                            NS.parcours.Deplacer(p.cle, idP, rangEtape, -1)
                            etat.etapeChoisie = { idP, rangEtape - 1 }
                            ParcoursChange()
                        end, rangEtape > 1 },
                        { L.ROUTE_DOWN, function()
                            NS.parcours.Deplacer(p.cle, idP, rangEtape, 1)
                            etat.etapeChoisie = { idP, rangEtape + 1 }
                            ParcoursChange()
                        end, rangEtape < #pc.etapes },
                        { L.ROUTE_REMOVE, function()
                            NS.parcours.Retirer(p.cle, idP, rangEtape)
                            etat.etapeChoisie = nil
                            ParcoursChange()
                        end },
                    } }) + 2
                end
            end
            local confirmer = etat.confirmerParcours == idP
            local uidP = pc.uid
            local guideIci = NS.guidage.EstActif("parcours", { uid = uidP })
            if etat.renommer == idP then
                index = index + 1
                local yLigne = y + 4
                y = Poser(contenu, index, yLigne, { retrait = RETRAIT, texte = "" }) + 4
                local saisie = contenu.saisieNom
                if not saisie then
                    saisie = CreateFrame("EditBox", nil, contenu, "InputBoxTemplate")
                    saisie:SetSize(240, 20)
                    saisie:SetAutoFocus(true)
                    saisie:SetMaxLetters(40)
                    contenu.saisieNom = saisie
                end
                saisie:ClearAllPoints()
                saisie:SetPoint("TOPLEFT", contenu, "TOPLEFT", RETRAIT * 2 + 6, -yLigne)
                saisie:SetText(pc.nom or "")
                saisie:SetScript("OnEnterPressed", function(self)
                    local nom = strtrim and strtrim(self:GetText() or "") or (self:GetText() or "")
                    if nom ~= "" then pc.nom = nom end
                    etat.renommer = nil
                    self:ClearFocus()
                    ParcoursChange()
                end)
                saisie:SetScript("OnEscapePressed", function(self)
                    etat.renommer = nil
                    self:ClearFocus()
                    fen.Rendre()
                end)
                saisie:Show()
                if saisie.SetFocus then saisie:SetFocus() end
            end
            index = index + 1
            y = Poser(contenu, index, y + 4, { retrait = RETRAIT, boutons = {
                { L.ROUTE_RENAME, function()
                    etat.renommer = (etat.renommer ~= idP) and idP or nil
                    fen.Rendre()
                end },
                { pc.carte and L.ROUTE_MAP_ON or L.ROUTE_MAP_OFF, function()
                    pc.carte = not pc.carte
                    ParcoursChange()
                end },
                { confirmer and L.ROUTE_DELETE_CONFIRM or L.ROUTE_DELETE, function()
                    if confirmer then
                        if guideIci then NS.suite.Arreter("joueur") end
                        NS.parcours.Supprimer(p.cle, idP)
                        etat.confirmerParcours = nil
                    else
                        etat.confirmerParcours = idP
                    end
                    ParcoursChange()
                end },
                (p.cle == NS.ClePersonnage()) and { guideIci and L.ROUTE_GUIDE_STOP or L.ROUTE_GUIDE_START, function()
                    NS.guidage.Basculer("parcours", { uid = uidP })
                    if not guideIci and NS.suivi and NS.suivi.MontrerParcours then pcall(NS.suivi.MontrerParcours, idP) end
                    fen.Rendre()
                end } or nil,
            } }) + 4
        end
        y = y + 6
    end
      end
        y = y + 4
      end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Mon histoire : zone par zone, tout ce que ce personnage peut y faire, ce
-- qu'il a fait et ce qui reste.
-- ---------------------------------------------------------------------------

-- "[12] " a la couleur de difficulte du jeu pour ce personnage.
local function NiveauColore(niveau, niveauPerso)
    if not niveau or niveau <= 0 then return "" end
    local r, g, b = NS.ref.CouleurDeNiveau(niveau, niveauPerso)
    return string.format("|cff%02x%02x%02x[%d]|r ", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), niveau)
end

local function RendreHistoire(contenu, p, index, y)
    local ok, liste, faites, total = pcall(NS.histoire.Bilan, p, etat.histoireToutes)
    if not ok then
        NS.base.NoterIncident("histoire", liste)
        return index, y
    end
    local pct = total > 0 and math.floor(faites * 100 / total) or 0
    local zoneIci = NS.Appeler(NS.Lecture("GetRealZoneText"))
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_STORY, {
        { etat.histoireToutes and L.STORY_ONLY_STARTED or L.STORY_ALL_ZONES, function()
            etat.histoireToutes = not etat.histoireToutes
            fen.Rendre()
        end },
        -- Quetes qu'on ne peut plus prendre : comptees ou non dans les pourcentages.
        { NS.histoire.AvecRetirees() and L.STORY_HIDE_RETIRED or L.STORY_SHOW_RETIRED, function()
            NS.histoire.PoserAvecRetirees(not NS.histoire.AvecRetirees())
            fen.Rendre()
        end },
    })
    index = index + 1
    -- Meme alignement que les noms de zones (apres le +).
    y = Poser(contenu, index, y + 2, { retrait = 18, texte = L.STORY_ALL,
        couleur = { 1, 1, 1 }, barre = total > 0 and (faites / total) or 0,
        texteBarre = string.format(L.STORY_BAR, faites, total, pct) }) + 6
    if #liste == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.STORY_NONE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    for _, z in ipairs(liste) do
        local cleOuverte = "zone" .. z.zone
        local ouverte = etat.ouvertes[cleOuverte] == true
        local fini = z.faites >= z.total
        local ici = zoneIci and (z.nom == zoneIci)
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = ouverte,
            -- Niveau de la zone a la couleur du jeu selon le personnage (gris,
            -- vert, jaune, orange, rouge), comme dans le menu de MapCore.
            texte = NiveauColore(z.niveau, p.niveau) .. z.nom
                .. (ici and ("   |cff4fd16a" .. L.STORY_HERE .. "|r") or ""), police = "GameFontHighlightSmall",
            surligne = ici,
            couleur = { 1, 1, 1 },
            barre = z.total > 0 and (z.faites / z.total) or 0,
            texteBarre = string.format(L.STORY_BAR, z.faites, z.total, z.pct),
            auClic = function()
                etat.ouvertes[cleOuverte] = not etat.ouvertes[cleOuverte] or nil
                fen.Rendre()
            end })
        if ouverte then
            -- Experience encore a prendre dans la zone.
            local xp = NS.histoire.XPRestante(p, z)
            if xp > 0 then
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT * 2, texte = string.format(L.STORY_ZONE_XP,
                    NS.ref.NombreLisible(xp), #z.restantes), couleur = { 1, 0.82, 0 } })
            end
            -- Ce qui reste, par niveau.
            local restantes = {}
            for _, id in ipairs(z.restantes) do
                table.insert(restantes, { id = id, niveau = tonumber(NS.ref.Lire("QuestDB", id, "questLevel")) or 0 })
            end
            table.sort(restantes, function(a, b)
                if a.niveau ~= b.niveau then return a.niveau < b.niveau end
                return a.id < b.id
            end)
            if #restantes == 0 then
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT * 2, texte = L.STORY_ZONE_DONE,
                    couleur = { 0.31, 0.82, 0.41 } })
            end
            for _, r in ipairs(restantes) do
                local q = p.quetes and p.quetes[r.id]
                local e = NS.parcours.EtatEtape(p, r.id)
                local droite, couleurDroite
                if e == "rendre" then
                    droite, couleurDroite = L.STORY_TURN_IN, { 0.31, 0.82, 0.41 }
                elseif e == "cours" then
                    droite = string.format(L.STORY_ACTIVE_PCT, NS.suivi.Avancement(q) or 0)
                    couleurDroite = { 1, 0.82, 0 }
                elseif e == "prendre" then
                    droite, couleurDroite = L.STORY_TO_TAKE, { 1, 1, 1 }
                else
                    local niveau = tonumber(NS.ref.Lire("QuestDB", r.id, "requiredLevel")) or 0
                    if NS.histoire.Retiree(r.id) then
                        droite, couleurDroite = L.STORY_RETIRED, { 0.6, 0.6, 0.6 }
                    elseif p.niveau and niveau > p.niveau then
                        droite, couleurDroite = string.format(L.ROUTE_LEVEL, niveau), { 0.6, 0.6, 0.6 }
                    end
                end
                local rr, gg, bb = NS.ref.CouleurDeNiveau(r.niveau, p.niveau)
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT * 2,
                    etatQuete = (e == "rendre") and true or ((e == "cours") and false or nil),
                    icone = (e == "prendre") and "Interface\\GossipFrame\\AvailableQuestIcon" or nil,
                    texte = string.format("[%d] %s", r.niveau, NS.ref.NomDeQuete(r.id, p)),
                    couleur = { rr, gg, bb },
                    droite = droite, couleurDroite = couleurDroite, decalageDroite = 28,
                    survol = SurvolEtape(p, r.id) })
            end
        end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Donjons : chaque donjon, son entree et ses quetes. Pour chaque quete qui
-- reste : chez qui la prendre, et ce qu'il faut avoir fait avant.
-- ---------------------------------------------------------------------------

local RendreDonjonOuvert
-- Recompenses d'une quete en une ligne : celles du journal si elle y est,
-- sinon celles de la base. Trois objets au plus, a la couleur de leur qualite.
local function LigneDeRecompenses(p, id)
    local q = p.quetes and p.quetes[id]
    local objets = {}
    local r = q and q.recompenses
    if r then
        for _, o in ipairs(r.objets or {}) do table.insert(objets, o.objet) end
        for _, o in ipairs(r.choix or {}) do table.insert(objets, o.objet) end
    else
        for _, objet in ipairs(NS.ref.ObjetsDeLaBase(id) or {}) do table.insert(objets, objet) end
    end
    if #objets == 0 then return nil end
    local morceaux = {}
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    for k, objet in ipairs(objets) do
        if k > 3 then table.insert(morceaux, "+" .. (#objets - 3)) break end
        local qualite = select(3, NS.Appeler(info, objet))
        local c = qualite and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[qualite]
        local hex = c and c.hex or "|cffffffff"
        table.insert(morceaux, string.format("|T%s:14|t %s%s|r", tostring(NS.ref.IconeDObjet(objet)), hex,
            NS.ref.NomDObjet(objet)))
    end
    return string.format(L.DUNGEON_REWARDS, table.concat(morceaux, "   "))
end

-- Un donjon deplie : son entree, puis le kit (les quetes a avoir en poche
-- avant d'y aller : celles du journal et celles a prendre maintenant), puis
-- celles d'apres (prerequis ou niveau), chacune avec ses recompenses.
RendreDonjonOuvert = function(contenu, p, d, index, y)
    if NS.ref.ConstruireIndexRecompenses then NS.ref.ConstruireIndexRecompenses() end
    local kit, plusTard, aPrendre, enPoche = {}, {}, {}, 0
    for _, id in ipairs(d.restantes) do
        local e = NS.parcours.EtatEtape(p, id)
        if e == "cours" or e == "rendre" then
            table.insert(kit, { id = id, etat = e })
            enPoche = enPoche + 1
        elseif e == "prendre" then
            table.insert(kit, { id = id, etat = e })
            table.insert(aPrendre, id)
        else
            table.insert(plusTard, { id = id, etat = e })
        end
    end
    -- Le trajet des prerequis : les quetes a prendre maintenant, et celles
    -- qu'il faut faire avant les autres (prerequis prenables).
    local vusPre = {}
    for _, id in ipairs(aPrendre) do vusPre[id] = true end
    for _, q in ipairs(plusTard) do
        for _, pre in ipairs(NS.donjons.PrealablesManquants(p, q.id)) do
            if not vusPre[pre] and NS.parcours.EtatEtape(p, pre) == "prendre" then
                vusPre[pre] = true
                table.insert(aPrendre, pre)
            end
        end
    end

    -- L'entree, puis une rangee : nos deux actions a gauche, le journal de
    -- donjons (DungeonJournal) seul a droite.
    local e = d.entrees[1]
    if e then
        local nomZone = NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), e.carte)
        nomZone = type(nomZone) == "table" and nomZone.name or "?"
        index = index + 1
        y = Poser(contenu, index, y + 2, { retrait = RETRAIT * 2,
            texte = string.format(L.DUNGEON_ENTRANCE, nomZone, e.x * 100, e.y * 100),
            couleur = { 0.85, 0.85, 0.85 } })
    end
    local boutons = {}
    if e then
        local nomD, entree = d.nom, e
        table.insert(boutons, { L.DUNGEON_SHOW_MAP, function()
            if NS.pageCarte and NS.pageCarte.MontrerEntree then
                NS.pageCarte.MontrerEntree(entree.carte, entree.x, entree.y, nomD)
            end
            fen.OuvrirCarte()
        end })
    end
    if #aPrendre > 0 then
        local ids, cleP, nomD, zoneD = aPrendre, p.cle, d.nom, d.zone
        table.insert(boutons, { string.format(L.DUNGEON_KIT_ROUTE, #ids), function()
            local pc = NS.parcours.CreerKit and NS.parcours.CreerKit(cleP, ids, string.format(L.DUNGEON_KIT_NAME, nomD), zoneD)
            if pc then
                etat.page = "parcours"
                etat.ouvertes["pc" .. pc.id] = true
                -- Comme tout nouveau trajet : le suivi le montre et la fleche part.
                if cleP == NS.ClePersonnage() then
                    if NS.suivi and NS.suivi.MontrerParcours then pcall(NS.suivi.MontrerParcours, pc.id) end
                    pcall(NS.guidage.Lancer, "parcours", { uid = pc.uid })
                end
                fen.Rendre()
            end
        end })
    end
    index = index + 1
    y = Poser(contenu, index, y, { retrait = RETRAIT * 2, boutons = boutons })
    do
        local l = contenu.lignes[index]
        local installe = _G.ForeverDungeonJournal_NS ~= nil
        local connu = installe and NS.donjons.NomDansLeJournal(d) ~= nil
        if not l.journal then
            l.journal = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
            l.journal:SetHeight(18)
            if l.journal.SetMotionScriptsWhileDisabled then l.journal:SetMotionScriptsWhileDisabled(true) end
            l.journal:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local b = l.journal
        b:SetText(L.DUNGEON_JOURNAL)
        b:SetWidth((b:GetTextWidth() or 120) + 24)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", l, "RIGHT", -8, 0)
        b:SetEnabled(connu)
        local donjon = d
        b:SetScript("OnClick", function() NS.donjons.OuvrirJournal(donjon, false) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.DUNGEON_JOURNAL, 1, 0.82, 0)
            GameTooltip:AddLine(connu and L.DUNGEON_JOURNAL_TIP or (installe and L.DUNGEON_JOURNAL_UNKNOWN
                or L.DUNGEON_JOURNAL_MISSING), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:Show()
        l.journalVu = true
    end
    if not (_G.ForeverDungeonJournal_NS ~= nil) then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT * 2, police = "GameFontDisableSmall", couleur = { 0.6, 0.6, 0.6 },
            texte = L.DUNGEON_JOURNAL_MISSING })
    end
    y = y + 4

    -- Une quete par ligne, son etat a droite ; un clic la deplie : chez qui
    -- la prendre (et le voir sur la carte), ce qui la debloque, ses recompenses.
    local function Quete(q, retrait)
        local id = q.id
        local niveau = tonumber(NS.ref.Lire("QuestDB", id, "questLevel")) or 0
        local droite, couleurDroite
        if q.etat == "faite" then
            droite, couleurDroite = L.DUNGEON_DONE, { 0.31, 0.82, 0.41 }
        elseif q.etat == "rendre" then
            droite, couleurDroite = L.STORY_TURN_IN, { 0.31, 0.82, 0.41 }
        elseif q.etat == "cours" then
            droite, couleurDroite = L.DUNGEON_IN_LOG, { 0.31, 0.82, 0.41 }
        elseif q.etat == "prendre" then
            droite, couleurDroite = L.STORY_TO_TAKE, { 1, 0.82, 0 }
        else
            local requis = tonumber(NS.ref.Lire("QuestDB", id, "requiredLevel")) or 0
            if p.niveau and requis > p.niveau then
                droite, couleurDroite = string.format(L.ROUTE_LEVEL, requis), { 0.6, 0.6, 0.6 }
            else
                droite, couleurDroite = L.DUNGEON_LOCKED, { 0.6, 0.6, 0.6 }
            end
        end
        local cleOuverte = "dq" .. id
        local ouverte = etat.ouvertes[cleOuverte] == true
        local rr, gg, bb = NS.ref.CouleurDeNiveau(niveau, p.niveau)
        if q.etat == "faite" then rr, gg, bb = 0.6, 0.6, 0.6 end
        index = index + 1
        y = Poser(contenu, index, y, { retrait = retrait,
            etatQuete = (q.etat == "rendre" or q.etat == "faite") and true or ((q.etat == "cours") and false or nil),
            icone = (q.etat == "prendre") and "Interface\\GossipFrame\\AvailableQuestIcon" or nil,
            texte = string.format("[%d] %s", niveau, NS.ref.NomDeQuete(id, p)),
            couleur = { rr, gg, bb },
            droite = droite, couleurDroite = couleurDroite, decalageDroite = 28,
            survol = SurvolEtape(p, id),
            auClic = function()
                etat.ouvertes[cleOuverte] = not etat.ouvertes[cleOuverte] or nil
                fen.Rendre()
            end })
        if not ouverte then return end
        local sous = retrait + RETRAIT + 18
        if q.etat == "prendre" or q.etat == "attente" then
            local donneurs = NS.ref.Donneurs(id)
            if donneurs[1] then
                index = index + 1
                y = Poser(contenu, index, y, { retrait = sous, texte = string.format(L.DUNGEON_GIVER, donneurs[1]),
                    couleur = { 0.85, 0.85, 0.85 } })
                local lieu = NS.donjons.LieuDuDonneur(id)
                if lieu then
                    index = index + 1
                    y = Poser(contenu, index, y, { retrait = sous, boutons = { { L.DUNGEON_LOCATE_GIVER, function()
                        fen.VoirQuete(id, p)
                    end } } })
                end
            end
        end
        if q.etat == "attente" then
            local manque = NS.donjons.PrealablesManquants(p, id)
            local noms = {}
            for k, pre in ipairs(manque) do
                if k > 3 then table.insert(noms, "...") break end
                local ep = NS.parcours.EtatEtape(p, pre)
                local tag = (ep == "prendre" and L.DUNGEON_PRE_TAKE) or ((ep == "cours" or ep == "rendre") and L.DUNGEON_PRE_ACTIVE)
                    or L.DUNGEON_PRE_LOCKED
                table.insert(noms, NS.ref.NomDeQuete(pre, p) .. " |cff8c8c8c(" .. tag .. ")|r")
            end
            if #noms > 0 then
                index = index + 1
                y = Poser(contenu, index, y, { retrait = sous, texte = string.format(L.DUNGEON_AFTER, table.concat(noms, ", ")),
                    couleur = { 0.7, 0.7, 0.7 }, police = "GameFontDisableSmall" })
            end
        end
        local recompenses = LigneDeRecompenses(p, id)
        if recompenses then
            index = index + 1
            y = Poser(contenu, index, y, { retrait = sous, texte = recompenses,
                couleur = { 0.85, 0.85, 0.85 }, police = "GameFontHighlightSmall" })
        end
        y = y + 2
    end

    local function Rubrique(texte)
        index = index + 1
        y = Poser(contenu, index, y + 6, { retrait = RETRAIT * 2, police = "GameFontNormalSmall", couleur = { 1, 0.82, 0 },
            texte = texte }) + 2
    end
    -- Avant d'y aller.
    Rubrique(#kit > 0 and string.format(L.DUNGEON_KIT, enPoche, #kit) or L.DUNGEON_KIT_TITLE)
    if #kit == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT * 2, texte = L.DUNGEON_KIT_EMPTY,
            couleur = { 0.6, 0.6, 0.6 }, police = "GameFontDisableSmall" })
    end
    for _, q in ipairs(kit) do Quete(q, RETRAIT * 2) end
    if #plusTard > 0 then
        Rubrique(string.format(L.DUNGEON_LATER, #plusTard))
        for _, q in ipairs(plusTard) do Quete(q, RETRAIT * 2) end
    end
    -- Deja faites : elles restent listees, marquees comme faites.
    if #(d.faitesIds or {}) > 0 then
        Rubrique(string.format(L.DUNGEON_DONE_LIST, #d.faitesIds))
        for _, id in ipairs(d.faitesIds) do Quete({ id = id, etat = "faite" }, RETRAIT * 2) end
    end
    return index, y + 6
end

local function RendreDonjons(contenu, p, index, y)
    if not (NS.donjons and NS.donjons.Disponible()) then
        index = index + 1
        y = Poser(contenu, index, y + 8, { retrait = 18, texte = L.DUNGEON_NO_BASE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    local ok, liste = pcall(NS.donjons.Liste, p)
    if not ok then
        NS.base.NoterIncident("donjons", liste)
        return index, y
    end
    index = index + 1
    y = Titre(contenu, index, y, L.NAV_DUNGEONS)
    index = index + 1
    y = Poser(contenu, index, y, { retrait = 18, texte = L.DUNGEON_HELP, police = "GameFontDisableSmall" }) + 4
    local zoneIci = NS.Appeler(NS.Lecture("GetRealZoneText"))
    local raids = false
    for _, d in ipairs(liste) do
        if d.raid and not raids then
            raids = true
            index = index + 1
            y = Titre(contenu, index, y, L.DUNGEON_RAIDS)
        end
        local cleOuverte = "donjon" .. d.zone
        local ouverte = etat.ouvertes[cleOuverte] == true
        local ici = zoneIci and d.nom == zoneIci
        local niveaux = ""
        if d.mini then
            local milieu = math.floor((d.mini + (d.maxi or d.mini)) / 2)
            local r, g, b = NS.ref.CouleurDeNiveau(milieu, p.niveau)
            niveaux = string.format("|cff%02x%02x%02x[%s]|r ", math.floor(r * 255), math.floor(g * 255),
                math.floor(b * 255), (d.maxi and d.maxi ~= d.mini) and (d.mini .. "-" .. d.maxi) or tostring(d.mini))
        end
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = ouverte,
            texte = niveaux .. d.nom .. (ici and ("   |cff4fd16a" .. L.STORY_HERE .. "|r") or ""),
            police = "GameFontHighlightSmall", surligne = ici, couleur = { 1, 1, 1 },
            barre = d.total > 0 and (d.faites / d.total) or 0,
            texteBarre = string.format(L.DUNGEON_BAR, d.faites, d.total),
            auClic = function()
                etat.ouvertes[cleOuverte] = not etat.ouvertes[cleOuverte] or nil
                fen.Rendre()
            end })
        if ouverte then
            index, y = RendreDonjonOuvert(contenu, p, d, index, y)
        end
    end
    return index, y
end

-- ---------------------------------------------------------------------------
-- Quetes disponibles : ce que le personnage peut prendre maintenant, par
-- zone (la sienne d'abord), sans les quetes grises.
-- ---------------------------------------------------------------------------

local function RendreDisponibles(contenu, p, index, y)
    local ok, liste = pcall(NS.disponibles.Liste, p)
    if not ok then NS.base.NoterIncident("disponibles", liste) return index, y end
    local ici = NS.Appeler(NS.Lecture("GetRealZoneText"))
    local parZone, zones, total = {}, {}, 0
    for _, d in ipairs(liste) do
        if not d.gris or etat.disposGrises then
            local nom = (d.zone > 0 and NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), d.zone)) or L.ZONE_OTHER
            if not parZone[nom] then
                parZone[nom] = { nom = nom, ids = {}, niveau = d.niveau }
                table.insert(zones, parZone[nom])
            end
            table.insert(parZone[nom].ids, d)
            total = total + 1
        end
    end
    table.sort(zones, function(a, b)
        if (a.nom == ici) ~= (b.nom == ici) then return a.nom == ici end
        if a.niveau ~= b.niveau then return a.niveau < b.niveau end
        return a.nom < b.nom
    end)
    -- Le compte couvre toutes les zones du monde (pas seulement celle ou l'on
    -- est) : on le dit, avec le nombre de zones et la part des grises.
    local grises = 0
    for _, z in ipairs(zones) do for _, d in ipairs(z.ids) do if d.gris then grises = grises + 1 end end end
    local titre = etat.disposGrises and string.format(L.AVAIL_TITLE_ALL_GRAY, total, #zones, grises)
        or string.format(L.AVAIL_TITLE_ALL, total, #zones)
    index = index + 1
    y = Titre(contenu, index, y, titre, {
        { etat.disposGrises and L.AVAIL_HIDE_GRAY or L.AVAIL_SHOW_GRAY, function()
            etat.disposGrises = not etat.disposGrises
            fen.Rendre()
        end },
    })
    if total == 0 then
        index = index + 1
        y = Poser(contenu, index, y, { retrait = RETRAIT, texte = L.AVAIL_NONE, couleur = { 0.6, 0.6, 0.6 } })
        return index, y
    end
    -- Les quetes disponibles maintenant (pour griser les autres etapes d'une suite).
    local dispo = {}
    for _, z in ipairs(zones) do for _, d in ipairs(z.ids) do if not d.gris then dispo[d.id] = true end end end
    for _, z in ipairs(zones) do
        local cleZone = "dz" .. z.nom
        -- Experience a prendre dans la zone avec les quetes du niveau du
        -- personnage, comme dans le suivi.
        local xpZone = 0
        for _, d in ipairs(z.ids) do
            if not d.gris and (d.niveau or 0) <= (p.niveau or 0) then
                xpZone = xpZone + (tonumber(NS.ref.XPDeLaBase(d.id, p.niveau)) or 0)
            end
        end
        local fermee = etat.ouvertes[cleZone] == false or (etat.ouvertes[cleZone] == nil and z.nom ~= ici)
        index = index + 1
        y = Poser(contenu, index, y, { retrait = 0, depliable = true, deplie = not fermee,
            texte = z.nom .. " (" .. #z.ids .. ")" .. ((z.nom == ici) and ("   |cff4fd16a" .. L.STORY_HERE .. "|r") or ""),
            police = "GameFontNormalSmall", couleur = { 1, 0.82, 0 }, surligne = z.nom == ici,
            droite = xpZone > 0 and string.format(L.TRACK_ZONE_XP, NS.ref.NombreLisible(xpZone)) or nil,
            couleurDroite = { 1, 0.82, 0 },
            auClic = function()
                -- Ouverte : on la ferme ; fermee : on l'ouvre.
                if fermee then etat.ouvertes[cleZone] = true else etat.ouvertes[cleZone] = false end
                fen.Rendre()
            end })
        if not fermee then
            for _, d in ipairs(z.ids) do
                local id = d.id
                local rr, gg, bb = NS.ref.CouleurDeNiveau(d.niveau, p.niveau)
                local donneurs = NS.ref.Donneurs(id)
                local ouverte = etat.dispoOuverte == id
                index = index + 1
                y = Poser(contenu, index, y, { retrait = RETRAIT,
                    icone = "Interface\\GossipFrame\\AvailableQuestIcon",
                    texte = string.format("[%d] %s", d.niveau, NS.ref.NomDeQuete(id, p)), couleur = { rr, gg, bb },
                    droite = donneurs[1], couleurDroite = { 0.75, 0.75, 0.75 },
                    survol = SurvolEtape(p, id),
                    auClic = function()
                        etat.dispoOuverte = (etat.dispoOuverte ~= id) and id or nil
                        fen.Rendre()
                    end })
                if ouverte then
                    local suite = NS.parcours.Suite(p, id)
                    local cleP = p.cle
                    -- Quete d'une suite : toutes ses etapes, dans l'ordre. Celle-ci
                    -- en or, celles qu'on peut prendre maintenant a leur couleur,
                    -- les autres grisees.
                    if #suite > 1 then
                        index = index + 1
                        y = Poser(contenu, index, y + 2, { retrait = RETRAIT * 2 + 18,
                            texte = string.format(L.AVAIL_CHAIN, #suite), couleur = { 1, 0.82, 0 } })
                        for rang, e in ipairs(suite) do
                            local nivE = tonumber(NS.ref.Lire("QuestDB", e, "questLevel")) or 0
                            local couleur
                            if e == id then couleur = { 1, 0.82, 0 }
                            elseif dispo[e] then couleur = { NS.ref.CouleurDeNiveau(nivE, p.niveau) }
                            else couleur = { 0.5, 0.5, 0.5 } end
                            index = index + 1
                            y = Poser(contenu, index, y, { retrait = RETRAIT * 2 + 30,
                                texte = string.format("%d. [%d] %s", rang, nivE, NS.ref.NomDeQuete(e, p)),
                                couleur = couleur, survol = SurvolEtape(p, e) })
                        end
                    end
                    local boutons = {}
                    if #suite > 1 then
                        table.insert(boutons, { string.format(L.ROUTE_MAKE_CHAIN, #suite), function()
                            local pc = NS.parcours.CreerSuite(cleP, p, id)
                            if pc then
                                etat.page = "parcours"
                                etat.ouvertes["pc" .. pc.id] = true
                            end
                            ParcoursChange()
                        end, true })
                    end
                    table.insert(boutons, { L.ROUTE_NEW, function()
                            NS.parcours.CreerSelection(cleP, p, id)
                            etat.page = "parcours"
                            ParcoursChange()
                        end })
                    table.insert(boutons, { L.DUNGEON_LOCATE_GIVER, function() fen.VoirQuete(id, p) end,
                            NS.donjons.LieuDuDonneur(id) ~= nil })
                    index = index + 1
                    y = Poser(contenu, index, y + 2, { retrait = RETRAIT * 2 + 18, boutons = boutons }) + 2
                end
            end
        end
    end
    return index, y
end

local MarquerMenu
local PoserOnglet, MarquerSelection

-- Memoire : on rouvre la page ou on s'etait arrete, meme apres /reload.
local pageRestauree = false
local function Memoire()
    if type(QuestCoreDB) ~= "table" then return nil end
    QuestCoreDB.memoire = type(QuestCoreDB.memoire) == "table" and QuestCoreDB.memoire or {}
    return QuestCoreDB.memoire
end

function fen.Rendre()
    if not cadre or not cadre:IsShown() then return end
    local m = Memoire()
    if m and not pageRestauree then
        pageRestauree = true
        if m.page then etat.page = m.page end
    end
    local ok, souci = pcall(function()
        local persos = PersosVisibles()
        SuivreLaSuite()
        -- Arrive par LT / RT depuis un autre add-on : premier ou dernier onglet.
        local entree = NS.suite and NS.suite.PrendreEntree and NS.suite.PrendreEntree()
        if entree == "debut" then etat.page = "quetes" elseif entree == "fin" then etat.page = "carte" end
        local visible = false
        for _, p in ipairs(persos) do if p.cle == etat.cle then visible = true end end
        if not etat.cle or not NS.base.PersoParCle(etat.cle) or not visible then
            -- Par defaut, le personnage connecte (s'il est de la faction regardee).
            local moi = NS.ClePersonnage()
            local moiVisible = false
            for _, p in ipairs(persos) do if p.cle == moi then moiVisible = true end end
            etat.cle = moiVisible and moi or (persos[1] and persos[1].cle)
        end
        -- L'equipement a son add-on (StuffCore) : plus d'onglet ici. La carte
        -- des trajets reste, ouverte par les boutons Trajet et Carte du suivi
        -- (sans onglet a droite).
        if etat.page == "equipement" then etat.page = etat.pageMenu or "quetes" end
        RendreListe()
        MarquerMenu()
        local surReglages = etat.page == "reglages"
        local surEquipement = etat.page == "equipement"
        local surCarte = etat.page == "carte"
        cadre.reglages:SetShown(surReglages)
        cadre.defilement:SetShown(not surReglages and not surEquipement and not surCarte)
        cadre.zoneFixe:SetShown(surEquipement or surCarte)
        cadre.bandeau.trait:SetShown(surEquipement)
        PoserOnglet()
        for page_, onglet in pairs({ equipement = cadre.ongletEquipement, carte = cadre.ongletCarte }) do
            local choisi = etat.page == page_
            if onglet.SetChecked then onglet:SetChecked(choisi) end
            MarquerSelection(onglet, choisi, onglet.Icon)
            onglet:Hide()
        end
        if surEquipement then
            NS.equipement.Rendre(cadre.zoneFixe, cadre.bandeau, etat.cle)
        else
            NS.equipement.Cacher(cadre.zoneFixe, cadre.bandeau)
        end
        if surCarte then
            NS.pageCarte.Rendre(cadre.zoneFixe, cadre.zone, cadre.menu, cadre.boutonsMenu[fen.PAGES[#fen.PAGES].cle])
        else
            NS.pageCarte.Cacher()
        end
        if not cadre.fondMenu:IsShown() then pcall(NS.charte.FondDuJournal, cadre.fondMenu) end
        local parchemin = NS.charte.Fond() == "parchemin"
        if cadre.parchemin then cadre.parchemin.Montrer(parchemin) end
        local contenu = cadre.contenu
        for _, l in ipairs(contenu.lignes or {}) do l:Hide() end
        if contenu.saisieNom then contenu.saisieNom:Hide() end
        local p = etat.cle and NS.base.PersoParCle(etat.cle)
        local index, y = 0, 0
        if not p then
            index = index + 1
            y = Poser(contenu, index, y, { texte = L.NOT_READ, couleur = { 0.6, 0.6, 0.6 } })
        else
            cadre.titre:SetText(L.TITLE .. " : " .. NS.NomCourt(p.cle)
                .. (p.releve and ("  |cff8c8c8c" .. string.format(L.LAST_READ, p.releve) .. "|r") or ""))
            if etat.page == "disponibles" then
                cadre.titre:SetText(L.TITLE .. " : " .. L.NAV_AVAILABLE .. " (" .. NS.NomCourt(p.cle) .. ")")
                index, y = RendreDisponibles(contenu, p, index, y)
            elseif etat.page == "histoire" then
                cadre.titre:SetText(L.TITLE .. " : " .. L.NAV_STORY .. " (" .. NS.NomCourt(p.cle) .. ")")
                index, y = RendreHistoire(contenu, p, index, y)
            elseif etat.page == "donjons" then
                cadre.titre:SetText(L.TITLE .. " : " .. L.NAV_DUNGEONS .. " (" .. NS.NomCourt(p.cle) .. ")")
                index, y = RendreDonjons(contenu, p, index, y)
            elseif etat.page == "parcours" then
                cadre.titre:SetText(L.TITLE .. " : " .. L.NAV_ROUTES .. " (" .. NS.NomCourt(p.cle) .. ")")
                index, y = RendreParcours(contenu, p, index, y)
            elseif etat.page == "communes" then
                cadre.titre:SetText(L.TITLE .. " : " .. L.NAV_COMMON)
                index, y = RendreCommunes(contenu, index, y)
            elseif p.nonReleve then
                index = index + 1
                y = Poser(contenu, index, y, { texte = L.NOT_READ, couleur = { 0.6, 0.6, 0.6 } })
            else
                index, y = RendreQuetes(contenu, p, index, y)
            end
            if etat.page ~= "communes" and etat.page ~= "parcours" and etat.page ~= "histoire" and etat.page ~= "donjons"
                and etat.page ~= "disponibles" then
                index, y = RendreEchanges(contenu, p, index, y)
            end
        end
        contenu:SetHeight(math.max(y + 8, 1))
        -- Textes a l'encre sur le parchemin, survol brun ; rien sur noir.
        NS.charte.Encrer(contenu, parchemin)
        NS.charte.Encrer(cadre.reglages, parchemin)
        NS.charte.Encrer(cadre.zoneFixe, parchemin)
        NS.charte.Encrer(cadre.bandeau, parchemin)
        for _, l in ipairs(contenu.lignes or {}) do
            local hl = l.GetHighlightTexture and l:GetHighlightTexture()
            if hl then
                if parchemin then hl:SetVertexColor(0.55, 0.35, 0.1) else hl:SetVertexColor(1, 1, 1) end
            end
        end
        -- Manette : element choisi retrouve, indications sous la fenetre.
        if NS.manette then
            NS.manette.ApresRendu(cadre)
            local dernier
            for _, b in ipairs(cadre.bande.boutons or {}) do if b:IsShown() then dernier = b end end
            local PAGES_ = fen.PAGES
            NS.manette.Indices(cadre, cadre.boutonsMenu[PAGES_[1].cle], cadre.boutonsMenu[PAGES_[#PAGES_].cle],
                nil, dernier, nil)
        end
    end)
    if m and etat.page then m.page = etat.page end
    if not ok then NS.base.NoterIncident("fenetre", souci) end
end

-- ---------------------------------------------------------------------------
-- Parametres du suivi : a la place de la liste, par le bouton du pied.
-- ---------------------------------------------------------------------------

local function PctTexte(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end

local function ConstruireReglages(parent)
    local panneau = CreateFrame("Frame", nil, parent)
    panneau.lignes = {}
    local y = 0
    local function Titre(texte)
        local f = panneau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f:SetPoint("TOPLEFT", panneau, "TOPLEFT", 0, -y)
        f:SetText(texte)
        local filet = panneau:CreateTexture(nil, "ARTWORK")
        filet:SetHeight(1)
        filet:SetColorTexture(0.54, 0.39, 0.17, 0.6)
        filet:SetPoint("TOPLEFT", panneau, "TOPLEFT", 0, -(y + 22))
        filet:SetPoint("RIGHT", panneau, "RIGHT", 0, 0)
        -- La police des titres de la suite, comme les autres pages.
        table.insert(panneau.lignes, function() pcall(NS.charte.TitreDeSection, f, filet) end)
        y = y + 34
    end
    local function Libelle(texte)
        local f = panneau:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f:SetPoint("TOPLEFT", panneau, "TOPLEFT", RETRAIT, -(y + 5))
        f:SetWidth(200)
        f:SetJustifyH("LEFT")
        f:SetText(texte)
        return f
    end
    local function Bouton(texte, largeur, ancre, dx)
        local b = CreateFrame("Button", nil, panneau, "UIPanelButtonTemplate")
        b:SetText(texte)
        -- Jamais de texte qui deborde : le bouton prend la largeur de son libelle.
        local mesure = b.GetTextWidth and b:GetTextWidth() or 0
        b:SetSize(math.max(largeur, (mesure or 0) + 28), 22)
        b:SetPoint("LEFT", ancre, "RIGHT", dx or 6, 0)
        return b
    end
    -- Une valeur reglable par - et + : `lire` et `poser` la tiennent.
    local function Reglage(texte, lire, poser, pas, mini, maxi, format)
        local libelle = Libelle(texte)
        -- La valeur entre deux fleches, le controle commun de la suite.
        local S = _G.CoreSuite
        if S and S.Curseur then
            local cu = S.Curseur(panneau, mini, maxi, pas, lire, function(v) poser(v) NS.suivi.Appliquer() end, format)
            cu:SetPoint("TOPRIGHT", panneau, "TOPRIGHT", -8, -y)
            cu.surParchemin = function() return NS.charte.Fond and NS.charte.Fond() == "parchemin" end
            table.insert(panneau.lignes, cu.Rendre)
            y = y + 30
            return
        end
        local moins = Bouton("-", 26, libelle, 8)
        local valeur = panneau:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valeur:SetWidth(64)
        valeur:SetPoint("LEFT", moins, "RIGHT", 4, 0)
        local plus = Bouton("+", 26, valeur, 4)
        local function Montrer() valeur:SetText(format(lire())) end
        local function Changer(sens)
            local v = lire() + sens * pas
            v = math.max(mini, math.min(maxi, math.floor(v / pas + 0.5) * pas))
            poser(v)
            Montrer()
            NS.suivi.Appliquer()
        end
        moins:SetScript("OnClick", function() Changer(-1) end)
        plus:SetScript("OnClick", function() Changer(1) end)
        table.insert(panneau.lignes, Montrer)
        y = y + 30
    end
    -- Un choix parmi plusieurs : le bouton en place est grise.
    local function Choix(texte, cle, options, table_, apres, actif)
        table_ = table_ or function() return NS.suivi.Reglages() end
        local libelle = Libelle(texte)
        -- La liste deroulante commune de la suite.
        local S = _G.CoreSuite
        if S and S.ListeDeroulante then
            local li = S.ListeDeroulante(panneau, options, function() return table_()[cle] end,
                function(v)
                    if apres then apres(v) else table_()[cle] = v end
                    NS.suivi.Appliquer()
                end, function() pcall(fen.Rendre) end)
            li:SetPoint("TOPRIGHT", panneau, "TOPRIGHT", -8, -y)
            table.insert(panneau.lignes, li.Rendre)
            if actif then
                table.insert(panneau.lignes, function()
                    local libre = actif()
                    S.ActiverListe(li, libre)
                    libelle:SetAlpha(libre and 1 or 0.5)
                end)
            end
            y = y + 30
            return
        end
        local boutons, ancre = {}, libelle
        for rang, o in ipairs(options) do
            local b = Bouton(o[2], 70, ancre, rang == 1 and 8 or 6)
            b.valeur = o[1]
            b:SetScript("OnClick", function()
                if apres then apres(o[1]) else table_()[cle] = o[1] end
                for _, x in ipairs(boutons) do x:SetEnabled(x.valeur ~= o[1]) end
                NS.suivi.Appliquer()
                fen.Rendre()
            end)
            table.insert(boutons, b)
            ancre = b
        end
        table.insert(panneau.lignes, function()
            local actuel = table_()[cle]
            for _, x in ipairs(boutons) do x:SetEnabled(x.valeur ~= actuel) end
        end)
        y = y + 30
    end
    local function S() return NS.suivi.Reglages() end

    Titre(L.SET_WINDOW)
    -- Parametrage par defaut de la suite : une case ; cochee, les fonds sont grises.
    local function Libre() local S = _G.CoreSuite return not (S and S.ParDefaut and S.ParDefaut()) end
    do
        local libelle = Libelle((GetLocale and GetLocale() == "frFR") and "Paramétrage par défaut" or "Default setup")
        local case = CreateFrame("CheckButton", nil, panneau, "UICheckButtonTemplate")
        case:SetSize(24, 24)
        case:SetPoint("TOPRIGHT", panneau, "TOPRIGHT", -8, -y)
        case:SetScript("OnClick", function(self)
            local S = _G.CoreSuite
            if S and S.PoserParDefaut then S.PoserParDefaut(self:GetChecked() and true or false) end
            for _, f in ipairs(panneau.lignes) do pcall(f) end
            pcall(fen.Rendre)
        end)
        table.insert(panneau.lignes, function() case:SetChecked(not Libre()) end)
        y = y + 30
    end
    Choix(L.SET_BACKGROUND, "fond", function() return NS.charte.OptionsDeFond() end,
        function() return { fond = NS.charte.FondComplet() } end, function(v) NS.charte.PoserFondComplet(v) end, Libre)
    y = y + 8
    Titre(L.SET_MAP)
    local function OptionCarte(texte, cle)
        Choix(texte, cle, { { true, L.YES }, { false, L.NO } }, function() return NS.pageCarte.Reglages() end,
            function(v)
                NS.pageCarte.Reglages()[cle] = v
                NS.carte.Invalider()
                pcall(NS.pageCarte.Rendre)
            end)
    end
    OptionCarte(L.MAPPAGE_OPT_REVEAL, "reveler")
    OptionCarte(L.MAPPAGE_OPT_OTHERS, "autres")
    OptionCarte(L.MAPPAGE_OPT_FADE, "fondu")
    OptionCarte(L.MAPPAGE_OPT_AVAILABLE, "disponibles")
    OptionCarte(L.MAPPAGE_OPT_ETA, "temps")
    y = y + 8
    Titre(L.SET_STORY)
    Choix(L.SET_STORY_RETIRED, "histoireRetirees", { { true, L.YES }, { false, L.NO } },
        function() return { histoireRetirees = NS.histoire.AvecRetirees() } end,
        function(v) NS.histoire.PoserAvecRetirees(v) end)
    y = y + 8
    Titre(L.SET_TRACKER)
    -- Fond des suivis (quetes et recolte), commun a la suite.
    Choix(L.SET_TRACK_BG, "fondSuivis", { { "gris", L.SET_BG_GREY }, { "parchemin", L.SET_BG_PARCHMENT_T } },
        function() return { fondSuivis = NS.charte.FondDesSuivis() } end,
        function(v) NS.charte.PoserFondDesSuivis(v) end, Libre)
    Reglage(L.SET_FONT, function() return S().taille end, function(v) S().taille = v end, 1, 9, 20,
        function(v) return tostring(v) end)
    Choix(L.SET_REST_MODE, "modeRepos", { { "visible", L.SET_REST_VISIBLE }, { "survol", L.SET_REST_HOVER } })
    Reglage(L.SET_ALPHA_REST, function() return S().alphaRepos end, function(v) S().alphaRepos = v end,
        0.05, 0, 1, PctTexte)
    Reglage(L.SET_ALPHA_MOVE, function() return S().alphaMouvement end, function(v) S().alphaMouvement = v end,
        0.05, 0, 1, PctTexte)
    Reglage(L.SET_ALPHA_HOVER, function() return S().alphaSurvol end, function(v) S().alphaSurvol = v end,
        0.05, 0.1, 1, PctTexte)
    Choix(L.SET_PARTY, "groupe", { { true, L.YES }, { false, L.NO } },
        function() return { groupe = NS.groupe.Actif() } end, function(v) NS.groupe.PoserActif(v) end)
    -- Couleur du cadeau des dons partiels (le vert reste celui du don complet).
    Choix(L.SET_GIFT, "couleurDon", { { "violet", L.SET_GIFT_PURPLE }, { "bleu", L.SET_GIFT_BLUE },
        { "orange", L.SET_GIFT_ORANGE }, { "rouge", L.SET_GIFT_RED }, { "jaune", L.SET_GIFT_YELLOW } },
        function() return { couleurDon = NS.suivi.Reglages().couleurDon or "violet" } end,
        function(v) NS.suivi.Reglages().couleurDon = v pcall(NS.suivi.Rendre) end)
    Choix(L.SET_DONE_PLACE, "termineesDansQuetes", { { false, L.SET_DONE_TURNIN_ONLY }, { true, L.SET_DONE_BOTH } })
    Choix(L.SET_GROUP, "regroupement", { { "zone", L.SET_GROUP_ZONE }, { "etat", L.SET_GROUP_STATE } })
    Choix(L.SET_COMBAT, "modeCombat", { { "normal", L.SET_COMBAT_NORMAL }, { "estompe", L.SET_COMBAT_FADE },
        { "cache", L.SET_COMBAT_HIDE } })
    Choix(L.SET_NATIVE, "masquerNatif", { { false, L.SET_NATIVE_SHOW }, { true, L.SET_NATIVE_HIDE } }, nil,
        function(v) NS.suivi.MasquerNatif(v) end)
    -- Avec CraftCore : souder le suivi des quetes sous celui de la recolte.
    if NS.suivi.CraftCorePresent() then
        Choix(L.SET_WELD, "souder", { { true, L.YES }, { false, L.NO } }, nil,
            function(v) NS.suivi.Souder(v) end)
        Choix(L.SET_SAME_ALPHA, "memeOpacite", { { true, L.YES }, { false, L.NO } })
    end
    -- Ancrer : la fenetre ne bouge plus (sauf en mode Edition du jeu).
    Choix(L.SET_LOCK, "ancre", { { true, L.YES }, { false, L.NO } },
        function() return { ancre = NS.suite and NS.suite.Ancree and NS.suite.Ancree("QuestCoreSuivi") or false } end,
        function(v) if NS.suite and NS.suite.PoserAncre then NS.suite.PoserAncre("QuestCoreSuivi", v) end end)
    local centrer = Bouton(L.SET_CENTER_BUTTON, 90, Libelle(L.SET_CENTER), 8)
    centrer:SetScript("OnClick", function() NS.suivi.Centrer() end)
    y = y + 30
    y = y + 8
    -- Mode developpeur : groupe simule, pour travailler l'affichage en groupe.
    -- Prive : seulement sur le poste de l'auteur (/sagacore prive).
    if NS.suite and NS.suite.Prive and NS.suite.Prive() then
    Titre(L.SET_DEV)
    Choix(L.SET_DEV_GROUP, "simuGroupe", { { 0, L.SET_DEV_OFF }, { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" } },
        function() return { simuGroupe = NS.groupe.Simulation() } end,
        function(v) NS.groupe.PoserSimulation(v) end)
    local avancee = Bouton(L.SET_DEV_STEP_BUTTON, 120, Libelle(L.SET_DEV_STEP), 8)
    avancee:SetScript("OnClick", function()
        if not NS.groupe.SimulerAvancee() then NS.Dire(L.SET_DEV_STEP_NONE) end
    end)
    y = y + 30
    y = y + 8
    end
    -- Bandeau des quetes : ce qui vient d'avancer, quelques secondes a l'ecran.
    Titre(L.SET_BANNER)
    Choix(L.SET_BANNER_SHOW, "actif", { { true, L.YES }, { false, L.NO } },
        function() return NS.bandeau.Reglages() end, function(v) NS.bandeau.Reglages().actif = v end)
    local function B() return NS.bandeau.Reglages() end
    local function Secondes(v)
        local t = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
        if NS.langue and NS.langue ~= "enUS" and NS.langue ~= "zhCN" then t = t:gsub("%.", ",") end
        return string.format(L.SET_BANNER_SECONDS, t)
    end
    Reglage(L.SET_BANNER_DURATION, function() return B().duree end, function(v) B().duree = v end,
        0.5, 1, 15, Secondes)
    Choix(L.SET_BANNER_HIDE, "disparition", { { "fondu", L.SET_BANNER_FADE }, { "net", L.SET_BANNER_CUT } },
        function() return B() end, function(v) B().disparition = v end)
    Reglage(L.SET_BANNER_FADE_TIME, function() return B().fondu end, function(v) B().fondu = v end,
        0.25, 0.25, 3, Secondes)
    local apercu = Bouton(L.SET_BANNER_PREVIEW, 90, Libelle(L.SET_BANNER_TRY), 8)
    apercu:SetScript("OnClick", function() NS.bandeau.Apercu() end)
    y = y + 30
    local placer = Bouton(L.SET_BANNER_MOVE, 90, Libelle(L.SET_BANNER_PLACE), 8)
    local recentrer = Bouton(L.SET_BANNER_CENTER, 90, placer, 8)
    local function Libeller()
        placer:SetText(NS.bandeau.EnPlacement() and L.SET_BANNER_LOCK or L.SET_BANNER_MOVE)
    end
    placer:SetScript("OnClick", function() NS.bandeau.Placer() Libeller() end)
    recentrer:SetScript("OnClick", function() NS.bandeau.Recentrer() end)
    table.insert(panneau.lignes, Libeller)
    y = y + 30
    y = y + 6
    local aide = panneau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aide:SetPoint("TOPLEFT", panneau, "TOPLEFT", RETRAIT, -y)
    aide:SetPoint("RIGHT", panneau, "RIGHT", -8, 0)
    aide:SetJustifyH("LEFT")
    aide:SetText(L.SET_HELP)

    panneau:SetHeight(y + (aide:GetStringHeight() or 14) + 12)
    panneau:SetScript("OnShow", function() for _, f in ipairs(panneau.lignes) do f() end end)
    return panneau
end

-- ---------------------------------------------------------------------------
-- Onglet lateral d'equipement (repris de CraftCore)
-- ---------------------------------------------------------------------------

local function CouleurSelection()
    local c = _G.NORMAL_FONT_COLOR
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

-- Halo de case cochee du jeu, le meme repere que CraftCore.
MarquerSelection = function(element, choisi, ancre)
    if not element then return end
    -- Onglet : en retrait (plus sombre) quand il n'est pas ouvert ; pas de
    -- transparence.
    if element.estOnglet then
        element.choisi = choisi and true or false
        element:SetAlpha(1)
        if element.Icon then
            local v = choisi and 1 or 0.55
            element.Icon:SetVertexColor(v, v, v)
        end
        return
    end
    if not element.haloSelection and element.CreateTexture then
        local halo = element:CreateTexture(nil, "OVERLAY")
        halo:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        halo:SetBlendMode("ADD")
        halo:SetPoint("TOPLEFT", ancre or element, "TOPLEFT", -2, 2)
        halo:SetPoint("BOTTOMRIGHT", ancre or element, "BOTTOMRIGHT", 2, -2)
        element.haloSelection = halo
    end
    if element.haloSelection then
        element.haloSelection:SetVertexColor(CouleurSelection())
        element.haloSelection:SetShown(choisi and true or false)
    end
    element:SetAlpha(choisi and 1 or 0.5)
end

-- Onglet du grimoire du jeu, meme taille et meme dessin que les onglets de
-- la suite (a gauche) et ceux de CraftCore. Celui qui n'est pas ouvert
-- reste en retrait (plus sombre), et s'eclaire au survol.
local TAILLE_ONGLET = 34
local function CreerOngletLateral(fenetreMere, icone, auClic)
    local onglet = CreateFrame("CheckButton", nil, fenetreMere)
    onglet:SetSize(TAILLE_ONGLET, TAILLE_ONGLET)
    local fond = onglet:CreateTexture(nil, "BACKGROUND")
    fond:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    do local S = NS.suite or _G.CoreSuite if S and S.TeinteOnglet then S.TeinteOnglet(fond) end end
    fond:SetSize(TAILLE_ONGLET * 2, TAILLE_ONGLET * 2)
    fond:SetPoint("TOPLEFT", -3, 12)
    local face = onglet:CreateTexture(nil, "ARTWORK")
    face:SetAllPoints()
    face:SetTexture(icone)
    onglet.Icon = face
    onglet.estOnglet = true
    onglet:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    onglet:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local halo = onglet:GetCheckedTexture()
    if halo then halo:SetBlendMode("ADD") end
    onglet:SetScript("OnClick", function(self)
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        self:SetChecked(self.choisi and true or false)
        auClic()
    end)
    onglet:SetScript("OnEnter", function(self)
        self.Icon:SetVertexColor(1, 1, 1)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText)
        GameTooltip:Show()
    end)
    onglet:SetScript("OnLeave", function(self)
        if not self.choisi then self.Icon:SetVertexColor(0.55, 0.55, 0.55) end
        GameTooltip:Hide()
    end)
    return onglet
end

-- Hauteur de l'onglet Equipement : exactement celle de CraftCore, comptee
-- depuis le trait sous l'en-tete. On la lit sur sa fenetre quand elle est la ;
-- sinon on la recalcule comme CraftCore la pose : onglets de metier depuis le
-- trait, puis un ecart plus grand, la progression, et l'equipement dessous.
local function DecalageDeCraftCore()
    local cc = _G.CraftCoreWindow
    local sien = cc and cc.ongletEquipement
    local ref = cc and (cc.fond or cc.zone)
    if sien and sien.IsShown and sien:IsShown() and sien.GetTop and ref and ref.GetTop then
        local a, b = sien:GetTop(), ref:GetTop()
        if a and b then return a - b end
    end
    local haut = (NS.suite and NS.suite.HAUT_ONGLET) or -7
    local ecart = (NS.suite and NS.suite.ECART_ENTRE_ONGLETS) or 14
    local metiers = cc and cc.ordreOnglets and #cc.ordreOnglets or 0
    if metiers < 1 then metiers = 2 end
    return haut - metiers * TAILLE_ONGLET - (metiers - 1) * ecart - 30 - TAILLE_ONGLET - ecart
end

PoserOnglet = function()
    local onglet = cadre and cadre.ongletEquipement
    if not onglet then return end
    -- A la hauteur de l'onglet Equipement de CraftCore.
    local y = DecalageDeCraftCore()
    if onglet.dernierY == y then return end
    onglet.dernierY = y
    onglet:ClearAllPoints()
    if NS.suite and NS.suite.AncreHaut then
        local ancre, point = NS.suite.AncreHaut(cadre, "droite")
        onglet:SetPoint("TOPLEFT", ancre, point, 0, y)
    else
        onglet:SetPoint("TOPLEFT", cadre, "TOPRIGHT", 0, y - 60)
    end
end

local PAGES = {
    { cle = "quetes", libelle = "NAV_QUESTS", icone = "Interface\\Icons\\INV_Misc_Book_08" },
    { cle = "communes", libelle = "NAV_COMMON", icone = "Interface\\Icons\\INV_Misc_Book_09" },
    { cle = "disponibles", libelle = "NAV_AVAILABLE", icone = "Interface\\GossipFrame\\AvailableQuestIcon" },
    { cle = "histoire", libelle = "NAV_STORY", icone = "Interface\\Icons\\INV_Misc_Book_11" },
    { cle = "donjons", libelle = "NAV_DUNGEONS", icone = "Interface\\Icons\\INV_Misc_Key_14" },
    { cle = "parcours", libelle = "NAV_ROUTES", icone = "Interface\\Icons\\INV_Scroll_03" },
    { cle = "reglages", libelle = "SETTINGS", icone = "Interface\\Icons\\Trade_Engineering" },
}

-- Une ligne de menu, le modele de liste du jeu (comme CraftCore).
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

fen.PAGES = PAGES

function fen.Page() return etat.page or "quetes" end

-- LB / RB : rubrique voisine du menu de gauche.
-- S'arrete aux bouts ; depuis un onglet de droite (Equipement, Carte), on
-- revient a la rubrique du menu qu'on avait quittee.
function fen.PageVoisine(pas)
    local index
    for rang, page in ipairs(PAGES) do if page.cle == fen.Page() then index = rang break end end
    if not index then
        etat.page = etat.pageMenu or PAGES[1].cle
        fen.Rendre()
        return
    end
    local suivant = math.max(1, math.min(#PAGES, index + pas))
    if suivant == index then return end
    etat.page = PAGES[suivant].cle
    etat.pageMenu = etat.page
    fen.Rendre()
end

-- LT / RT : les onglets de droite (Equipement, Carte), puis retour aux quetes.
local ONGLETS = { "quetes" }
-- LT / RT : Quetes (les pages du menu), Equipement, Carte ; s'arrete aux
-- bouts (les add-ons : Vue + LB / RB).
function fen.OngletVoisin(pas)
    local index = 1
    for rang, cle in ipairs(ONGLETS) do if cle == etat.page then index = rang break end end
    local suivant = math.max(1, math.min(#ONGLETS, index + pas))
    if suivant == index then return end
    if index == 1 then etat.pageMenu = fen.Page() end
    if suivant == 1 then etat.page = etat.pageMenu or "quetes"
    else etat.page = ONGLETS[suivant] end
    fen.Rendre()
end

-- Le personnage affiche est-il le dernier de la bande ? (la croix droite
-- passe alors aux add-ons de la suite, en haut a droite)
function fen.DernierPersonnage()
    local persos = PersosVisibles()
    return #persos == 0 or (persos[#persos].cle == etat.cle)
end

-- Croix gauche / droite : personnage voisin dans la bande du haut.
function fen.PersonnageVoisin(pas)
    local persos = PersosVisibles()
    if #persos == 0 then return end
    local index = 1
    for rang, p in ipairs(persos) do if p.cle == etat.cle then index = rang break end end
    ChoisirPerso(persos[((index - 1 + pas) % #persos) + 1].cle)
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    fen.Rendre()
end

MarquerMenu = function()
    for cle, b in pairs(cadre.boutonsMenu or {}) do
        local choisi = cle == (etat.page or "quetes")
        local texte = b.text or b.Text or (b.GetFontString and b:GetFontString())
        if texte then texte:SetFontObject(choisi and "GameFontHighlight" or "GameFontNormal") end
        b.fond:SetShown(choisi)
        b:SetAlpha(1)
    end
end

local function Construire()
    cadre = NS.charte.Fenetre("QuestCoreFenetre", LARGEUR, HAUTEUR, {})
    cadre:SetPoint("CENTER")
    cadre:Hide()
    table.insert(UISpecialFrames, "QuestCoreFenetre")
    if cadre.portrait or (cadre.PortraitContainer and cadre.PortraitContainer.portrait) then
        local portrait = cadre.portrait or cadre.PortraitContainer.portrait
        portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
    end

    local bande = CreateFrame("Frame", nil, cadre)
    bande:SetPoint("LEFT", cadre.entete, "LEFT", 0, 0)
    bande:SetPoint("RIGHT", cadre.entete, "RIGHT", 0, 0)
    bande:SetHeight(TAILLE_PORTRAIT + 4)
    cadre.bande = bande

    -- Menu de gauche : les pages de QuestCore (les reglages pour commencer).
    local menu = CreateFrame("Frame", nil, cadre)
    menu:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, 0)
    menu:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    menu:SetWidth(LARGEUR_LISTE)
    cadre.menu = menu
    local trait = cadre:CreateTexture(nil, "ARTWORK")
    -- Plus de trait visible entre le menu et le contenu : il ne sert que de repere.
    trait:SetColorTexture(0, 0, 0, 0)
    trait:SetWidth(1)
    trait:SetPoint("TOPLEFT", menu, "TOPRIGHT", ECART_MENU, 0)
    trait:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", ECART_MENU, 0)

    -- Fond du menu : celui du journal de quetes de la carte, comme CraftCore.
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
    contenu:SetSize(LARGEUR - LARGEUR_LISTE - 2 * NS.charte.MARGE - 60, 1)
    defilement:SetScrollChild(contenu)
    cadre.contenu = contenu
    cadre.defilement = defilement

    -- Parchemin au choix (Parametres), sur toute la zone de droite.
    NS.charte.Parchemin(cadre, { "TOPLEFT", trait, "TOPRIGHT", 2, NS.charte.MARGE - 4 },
        { "BOTTOMRIGHT", cadre.fond, "BOTTOMRIGHT", -4, 4 }, cadre.fond)

    local fermer = NS.charte.BoutonDePied(cadre, L.CLOSE, 110)
    fermer:SetScript("OnClick", function() cadre:Hide() end)

    -- Parametres dans une zone qui defile a la molette : plus rien ne passe
    -- sous le pied quand la liste s'allonge.
    -- Avec la barre de defilement du jeu (on voit qu'il y a une suite), un
    -- peu d'air en haut et en bas, et un pas de molette egal a une ligne
    -- d'option : aucune option ne reste coupee a moitie au bord.
    local okR, reglages = pcall(CreateFrame, "ScrollFrame", nil, cadre, "ScrollFrameTemplate")
    if not okR or not reglages then
        reglages = CreateFrame("ScrollFrame", nil, cadre, "UIPanelScrollFrameTemplate")
    end
    reglages:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_MENU + 4, -4)
    reglages:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", -18, 6)
    reglages:EnableMouseWheel(true)
    local panneauReglages = ConstruireReglages(reglages)
    panneauReglages:SetWidth(LARGEUR - LARGEUR_LISTE - 2 * NS.charte.MARGE - ECART_MENU * 2 - 48)
    reglages:SetScrollChild(panneauReglages)
    local PAS = 30
    reglages:SetScript("OnMouseWheel", function(self, sens)
        local maximum = math.max(0, (panneauReglages:GetHeight() or 0) - (self:GetHeight() or 0))
        local cible = (self:GetVerticalScroll() or 0) - sens * PAS
        cible = math.floor(cible / PAS + 0.5) * PAS
        self:SetVerticalScroll(math.max(0, math.min(maximum, cible)))
    end)
    reglages:SetScript("OnShow", function() for _, f in ipairs(panneauReglages.lignes) do f() end end)
    reglages:Hide()
    cadre.reglages = reglages

    -- Page d'equipement, batie comme celle de CraftCore : bandeau de
    -- comparaison en bas, zone fixe au-dessus.
    local bandeau = CreateFrame("Frame", nil, cadre)
    bandeau:SetPoint("BOTTOMLEFT", trait, "BOTTOMRIGHT", ECART_MENU, 0)
    bandeau:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    bandeau:SetHeight(HAUTEUR_BANDEAU)
    bandeau:Hide()
    cadre.bandeau = bandeau
    local traitBandeau = cadre:CreateTexture(nil, "ARTWORK")
    traitBandeau:SetColorTexture(0.54, 0.39, 0.17, 0.6)
    traitBandeau:SetHeight(1)
    traitBandeau:SetPoint("BOTTOMLEFT", bandeau, "TOPLEFT", 0, 4)
    traitBandeau:SetPoint("BOTTOMRIGHT", bandeau, "TOPRIGHT", 0, 4)
    traitBandeau:Hide()
    bandeau.trait = traitBandeau
    local zoneFixe = CreateFrame("Frame", nil, cadre)
    zoneFixe:SetPoint("TOPLEFT", trait, "TOPRIGHT", ECART_MENU, 0)
    zoneFixe:SetPoint("BOTTOMRIGHT", bandeau, "TOPRIGHT", 0, 8)
    zoneFixe:Hide()
    cadre.zoneFixe = zoneFixe

    -- Onglet lateral, a droite, comme celui de CraftCore.
    local onglet = CreerOngletLateral(cadre, "Interface\\Icons\\INV_Chest_Chain", function()
        etat.page = (etat.page == "equipement") and "quetes" or "equipement"
        fen.Rendre()
    end)
    onglet.tooltipText = L.NAV_EQUIPMENT
    cadre.ongletEquipement = onglet

    -- Carte, juste dessous.
    local ongletCarte = CreerOngletLateral(cadre, "Interface\\Icons\\INV_Misc_Map_01", function()
        etat.page = (etat.page == "carte") and "quetes" or "carte"
        fen.Rendre()
    end)
    ongletCarte.tooltipText = L.NAV_MAP
    ongletCarte:SetPoint("TOPLEFT", onglet, "BOTTOMLEFT", 0, -((NS.suite and NS.suite.ECART_ENTRE_ONGLETS) or 14))
    cadre.ongletCarte = ongletCarte

    cadre:SetScript("OnShow", function()
        -- La carte etait en filigrane (clic sur la fleche) : elle revient dans
        -- la fenetre, avec la molette et le glisser.
        if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then pcall(NS.pageCarte.Filigrane, false) end
        fen.Rendre()
    end)
    -- Les add-ons de la suite, en haut a droite : on bascule de l'un a l'autre.
    if NS.suite then pcall(NS.suite.Entete, cadre, "QuestCore", cadre.entete) end
end

function fen.Basculer()
    if not cadre then Construire() end
    if cadre:IsShown() then cadre:Hide() else cadre:Show() end
end

function fen.Visible() return cadre and cadre:IsShown() end

function fen.Ouvrir()
    if not cadre then Construire() end
    if not cadre:IsShown() then cadre:Show() end
end

function fen.Cadre() return cadre end

-- Ouvre la fenetre sur une quete disponible (clic sur un ! de la carte).
function fen.OuvrirDisponible(id)
    if not cadre then Construire() end
    ChoisirPerso(NS.ClePersonnage() or etat.cle)
    etat.page = "disponibles"
    etat.dispoOuverte = id
    local niveau = NS.ref.Lire("QuestDB", id, "zoneOrSort")
    local nom = niveau and NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), niveau)
    if nom then etat.ouvertes["dz" .. nom] = true end
    if cadre:IsShown() then fen.Rendre() else cadre:Show() end
end

-- Ouvre la fenetre sur la carte du personnage connecte.
function fen.OuvrirReglages()
    fen.Ouvrir()
    etat.page, etat.pageMenu = "reglages", "reglages"
    fen.Rendre()
end

-- "Voir sur la carte" d'une quete a prendre : la carte de la zone ou elle
-- se prend, son point d'exclamation qui clignote (clic : guidage).
function fen.VoirQuete(id, p, sansFleche)
    local lieu = NS.donjons.LieuDuDonneur(id)
    -- Donneur a l'interieur d'un donjon (sa carte ne s'affiche pas) : on
    -- montre l'entree du donjon, sur la carte de sa zone.
    local info = lieu and NS.Appeler(NS.Lecture("C_Map.GetMapInfo"), lieu.carte)
    local dedans = not lieu or (type(info) == "table" and (info.mapType or 0) >= 4)
    local d = dedans and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
    local e = d and d.entrees and d.entrees[1]
    if e and NS.pageCarte and NS.pageCarte.MontrerEntree then
        NS.pageCarte.MontrerEntree(e.carte, e.x, e.y, d.nom)
        fen.OuvrirCarte()
        return
    end
    if not lieu then return end
    -- Voir sur la carte ne fait que montrer : jamais de guidage en plus (le
    -- guidage, c'est le bouton Guider).
    sansFleche = true
    if NS.pageCarte and NS.pageCarte.MontrerQuete then
        NS.pageCarte.MontrerQuete(id, lieu.carte, lieu.x, lieu.y, NS.ref.NomDeQuete(id, p), lieu.nom, sansFleche)
    end
    fen.OuvrirCarte()
end

function fen.OuvrirCarte()
    if not cadre then Construire() end
    ChoisirPerso(NS.ClePersonnage() or etat.cle)
    etat.page = "carte"
    if NS.pageCarte and NS.pageCarte.EnFiligrane and NS.pageCarte.EnFiligrane() then pcall(NS.pageCarte.Filigrane, false) end
    if cadre:IsShown() then fen.Rendre() else cadre:Show() end
end

-- Ouvre la fenetre sur une page, pour le personnage connecte (messages).
function fen.OuvrirPage(page)
    if not cadre then Construire() end
    ChoisirPerso(NS.ClePersonnage() or etat.cle)
    etat.page = page
    if cadre:IsShown() then fen.Rendre() else cadre:Show() end
end

-- Ouvre la fenetre sur les parcours du personnage connecte.
function fen.OuvrirParcours()
    if not cadre then Construire() end
    ChoisirPerso(NS.ClePersonnage() or etat.cle)
    etat.page = "parcours"
    if cadre:IsShown() then fen.Rendre() else cadre:Show() end
end

-- Ouvre la fenetre sur un personnage, une quete depliee (clic droit dans le suivi).
function fen.OuvrirQuete(cle, id)
    if not cadre then Construire() end
    ChoisirPerso(cle)
    etat.page = "quetes"
    if id then etat.ouvertes[id] = true end
    if cadre:IsShown() then fen.Rendre() else cadre:Show() end
end

-- Reglages de QuestCore dans Options, Add-ons, Forever SagaCore : les memes
-- que la page Reglages de la fenetre.
do
    local function Apres() pcall(NS.suivi.Appliquer) pcall(fen.Rendre) end
    local function S() return NS.suivi.Reglages() end
    local function B() return NS.bandeau.Reglages() end
    local function OuiNon() return { { true, L.YES }, { false, L.NO } } end
    local function Carte(texte, cle)
        return { "case", texte, function() return NS.pageCarte.Reglages()[cle] end,
            function(v) NS.pageCarte.Reglages()[cle] = v pcall(NS.carte.Invalider) pcall(NS.pageCarte.Rendre) end }
    end
    local function Case(texte, lire, poser) return { "case", texte, lire, function(v) poser(v) Apres() end } end
    local function Choix(texte, options, lire, poser) return { "choix", texte, options, lire, function(v) poser(v) Apres() end } end
    local function Valeur(texte, lire, poser, pas, mini, maxi, format)
        return { "valeur", texte, lire, function(v) poser(v) Apres() end, pas, mini, maxi, format }
    end
    local function Secondes(v)
        local t = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
        if NS.langue and NS.langue ~= "enUS" and NS.langue ~= "zhCN" then t = t:gsub("%.", ",") end
        return string.format(L.SET_BANNER_SECONDS, t)
    end
    _G.SagaCoreOptions = type(_G.SagaCoreOptions) == "table" and _G.SagaCoreOptions or {}
    _G.SagaCoreOptions.QuestCore = { titre = "QuestCore", ordre = 2, elements = function()
        local liste = {
            { "section", L.SET_MAP },
            Carte(L.MAPPAGE_OPT_REVEAL, "reveler"),
            Carte(L.MAPPAGE_OPT_OTHERS, "autres"),
            Carte(L.MAPPAGE_OPT_FADE, "fondu"),
            Carte(L.MAPPAGE_OPT_AVAILABLE, "disponibles"),
            Carte(L.MAPPAGE_OPT_ETA, "temps"),
            { "section", L.SET_STORY },
            Case(L.SET_STORY_RETIRED, function() return NS.histoire.AvecRetirees() end, function(v) NS.histoire.PoserAvecRetirees(v) end),
            { "section", L.SET_TRACKER },
            Valeur(L.SET_FONT, function() return S().taille end, function(v) S().taille = v end, 1, 9, 20),
            Choix(L.SET_REST_MODE, { { "visible", L.SET_REST_VISIBLE }, { "survol", L.SET_REST_HOVER } },
                function() return S().modeRepos end, function(v) S().modeRepos = v end),
            Valeur(L.SET_ALPHA_REST, function() return S().alphaRepos end, function(v) S().alphaRepos = v end, 0.05, 0, 1, PctTexte),
            Valeur(L.SET_ALPHA_MOVE, function() return S().alphaMouvement end, function(v) S().alphaMouvement = v end, 0.05, 0, 1, PctTexte),
            Valeur(L.SET_ALPHA_HOVER, function() return S().alphaSurvol end, function(v) S().alphaSurvol = v end, 0.05, 0.1, 1, PctTexte),
            Case(L.SET_PARTY, function() return NS.groupe.Actif() end, function(v) NS.groupe.PoserActif(v) end),
            Choix(L.SET_GIFT, { { "violet", L.SET_GIFT_PURPLE }, { "bleu", L.SET_GIFT_BLUE }, { "orange", L.SET_GIFT_ORANGE },
                { "rouge", L.SET_GIFT_RED }, { "jaune", L.SET_GIFT_YELLOW } },
                function() return S().couleurDon or "violet" end, function(v) S().couleurDon = v pcall(NS.suivi.Rendre) end),
            Choix(L.SET_DONE_PLACE, { { false, L.SET_DONE_TURNIN_ONLY }, { true, L.SET_DONE_BOTH } },
                function() return S().termineesDansQuetes == true end, function(v) S().termineesDansQuetes = v end),
            Choix(L.SET_GROUP, { { "zone", L.SET_GROUP_ZONE }, { "etat", L.SET_GROUP_STATE } },
                function() return S().regroupement or "zone" end, function(v) S().regroupement = v end),
            Choix(L.SET_COMBAT, { { "normal", L.SET_COMBAT_NORMAL }, { "estompe", L.SET_COMBAT_FADE }, { "cache", L.SET_COMBAT_HIDE } },
                function() return S().modeCombat or "normal" end, function(v) S().modeCombat = v end),
            Choix(L.SET_NATIVE, { { false, L.SET_NATIVE_SHOW }, { true, L.SET_NATIVE_HIDE } },
                function() return S().masquerNatif == true end, function(v) NS.suivi.MasquerNatif(v) end),
        }
        if NS.suivi.CraftCorePresent() then
            table.insert(liste, Case(L.SET_WELD, function() return S().souder end, function(v) NS.suivi.Souder(v) end))
            table.insert(liste, Case(L.SET_SAME_ALPHA, function() return S().memeOpacite end, function(v) S().memeOpacite = v end))
        end
        table.insert(liste, { "case", L.SET_LOCK,
            function() return NS.suite and NS.suite.Ancree and NS.suite.Ancree("QuestCoreSuivi") end,
            function(v) if NS.suite and NS.suite.PoserAncre then NS.suite.PoserAncre("QuestCoreSuivi", v) end end })
        table.insert(liste, { "bouton", L.SET_CENTER, L.SET_CENTER_BUTTON, function() NS.suivi.Centrer() end })
        table.insert(liste, { "section", L.SET_BANNER })
        table.insert(liste, { "case", L.SET_BANNER_SHOW, function() return B().actif end, function(v) B().actif = v end })
        table.insert(liste, { "valeur", L.SET_BANNER_DURATION, function() return B().duree end, function(v) B().duree = v end, 0.5, 1, 15, Secondes })
        table.insert(liste, { "choix", L.SET_BANNER_HIDE, { { "fondu", L.SET_BANNER_FADE }, { "net", L.SET_BANNER_CUT } },
            function() return B().disparition end, function(v) B().disparition = v end })
        table.insert(liste, { "valeur", L.SET_BANNER_FADE_TIME, function() return B().fondu end, function(v) B().fondu = v end, 0.25, 0.25, 3, Secondes })
        table.insert(liste, { "bouton", L.SET_BANNER_TRY, L.SET_BANNER_PREVIEW, function() NS.bandeau.Apercu() end })
        table.insert(liste, { "bouton", L.SET_BANNER_PLACE,
            function() return NS.bandeau.EnPlacement() and L.SET_BANNER_LOCK or L.SET_BANNER_MOVE end, function() NS.bandeau.Placer() end })
        table.insert(liste, { "bouton", "", L.SET_BANNER_CENTER, function() NS.bandeau.Recentrer() end })
        return liste
    end }
end
