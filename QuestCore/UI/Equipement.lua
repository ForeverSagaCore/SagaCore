local _, NS = ...

-- ===========================================================================
-- Page de l'equipement
-- ===========================================================================

-- Page reprise de CraftCore, a l'identique : a gauche les emplacements du
-- personnage regarde, a droite, pour l'emplacement choisi, les quetes en
-- cours qui donnent un objet pour lui, en bas la comparaison.

NS.equipement = {}
local equipement = NS.equipement

-- Etat de la page (CraftCore le tient dans son ecran).
local ecran = { selectionObjets = {}, filtresParPerso = {} }
local cleCourante

local LARGEUR_COLONNE = 186
local LARGEUR_CHOIX = 330
local HAUTEUR_CASE = 32
local HAUTEUR_CANDIDAT = 24
local LIGNES_PAR_COLONNE = 5

local L

-- ---------------------------------------------------------------------------
-- Lecture
-- ---------------------------------------------------------------------------

local function ObjetPorteDe(fiche, nomEmplacement, estConnecte)
    -- Pour le personnage connecte, on demande au client. Pour les autres, on
    -- se fie au dernier releve enregistre.
    if estConnecte then
        local j = NS.jeu
        local numero = NS.emplacements.Numero(nomEmplacement)
        if numero and j.objetEquipe then
            local id = tonumber(NS.Appeler(j.objetEquipe, "player", numero))
            if id then return id end
        end
    end
    local porte = fiche and fiche.equipement and fiche.equipement[nomEmplacement]
    return porte and porte.id or nil
end

local function InfosObjet(id)
    if not id then return nil end
    local info = NS.objets.Info(id)
    return {
        id = id,
        nom = info and info.nom,
        niveau = info and info.niveau,
        icone = info and info.icone,
        stats = NS.objets.Stats(id),
    }
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function CreerCaseEmplacement(parent)
    local bouton = CreateFrame("Button", nil, parent)
    bouton:SetHeight(HAUTEUR_CASE)

    bouton.cadre = bouton:CreateTexture(nil, "BACKGROUND")
    bouton.cadre:SetSize(28, 28)
    bouton.cadre:SetPoint("LEFT", bouton, "LEFT", 2, 0)
    bouton.cadre:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")

    bouton.icone = bouton:CreateTexture(nil, "ARTWORK")
    bouton.icone:SetSize(24, 24)
    bouton.icone:SetPoint("CENTER", bouton.cadre, "CENTER", 0, 0)
    bouton.icone:Hide()

    bouton.ou = bouton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bouton.ou:SetPoint("TOPLEFT", bouton.cadre, "TOPRIGHT", 6, -1)
    bouton.ou:SetJustifyH("LEFT")
    bouton.ou:SetWordWrap(false)

    bouton.porte = bouton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bouton.porte:SetPoint("TOPLEFT", bouton.ou, "BOTTOMLEFT", 0, -1)
    bouton.porte:SetPoint("RIGHT", bouton, "RIGHT", -2, 0)
    bouton.porte:SetJustifyH("LEFT")
    bouton.porte:SetWordWrap(false)
    bouton.ou:SetPoint("RIGHT", bouton, "RIGHT", -2, 0)

    bouton.marque = bouton:CreateTexture(nil, "OVERLAY")
    bouton.marque:SetSize(12, 12)
    bouton.marque:SetPoint("BOTTOMRIGHT", bouton.cadre, "BOTTOMRIGHT", 2, -2)
    bouton.marque:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    bouton.marque:Hide()

    bouton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return bouton
end

local function CreerBoutonFiltre(parent)
    local bouton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    bouton:SetHeight(18)
    return bouton
end

local function CreerLigneCandidat(parent, index)
    parent.candidats = parent.candidats or {}
    local ligne = parent.candidats[index]
    if ligne then return ligne end

    ligne = CreateFrame("Button", nil, parent)
    ligne:SetHeight(HAUTEUR_CANDIDAT)

    ligne.fond = ligne:CreateTexture(nil, "BACKGROUND")
    ligne.fond:SetAllPoints()
    ligne.fond:SetColorTexture(0.35, 0.28, 0.12, 0.5)
    -- Fond de selection (l'apparence moderne en fait un trait d'accent).
    ligne.fondSelection = true
    ligne.fond:Hide()

    ligne.icone = ligne:CreateTexture(nil, "ARTWORK")
    ligne.icone:SetSize(18, 18)
    ligne.icone:SetPoint("TOPLEFT", ligne, "TOPLEFT", 2, -4)

    -- Deux lignes : le nom en entier, puis l'etat dessous. Rien n'est coupe
    -- par la largeur de la colonne.
    ligne.nom = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ligne.nom:SetPoint("TOPLEFT", ligne, "TOPLEFT", 25, -4)
    ligne.nom:SetPoint("RIGHT", ligne, "RIGHT", -20, 0)
    ligne.nom:SetJustifyH("LEFT")
    ligne.nom:SetWordWrap(true)
    if ligne.nom.SetMaxLines then ligne.nom:SetMaxLines(2) end

    ligne.etat = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ligne.etat.pasExplication = true
    ligne.etat:SetPoint("TOPLEFT", ligne.nom, "BOTTOMLEFT", 0, -2)
    ligne.etat:SetPoint("RIGHT", ligne, "RIGHT", -4, 0)
    ligne.etat:SetJustifyH("LEFT")
    ligne.etat:SetWordWrap(true)

    ligne:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    parent.candidats[index] = ligne
    return ligne
end

local function CreerLigneStat(bandeau, index)
    bandeau.stats = bandeau.stats or {}
    local ligne = bandeau.stats[index]
    if ligne then return ligne end

    ligne = CreateFrame("Frame", nil, bandeau)
    ligne:SetHeight(14)
    ligne.colonnes = {}

    ligne.cle = ligne:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ligne.cle.pasExplication = true
    ligne.cle:SetPoint("LEFT", ligne, "LEFT", 0, 0)
    ligne.cle:SetJustifyH("LEFT")
    ligne.cle:SetWordWrap(false)

    for rang = 1, 3 do
        local colonne = ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        colonne:SetWidth(84)
        colonne:SetJustifyH("RIGHT")
        if rang == 1 then
            colonne:SetPoint("LEFT", ligne, "LEFT", 150, 0)
        else
            colonne:SetPoint("LEFT", ligne.colonnes[rang - 1], "RIGHT", 6, 0)
        end
        ligne.colonnes[rang] = colonne
    end
    ligne.cle:SetPoint("RIGHT", ligne.colonnes[1], "LEFT", -6, 0)

    bandeau.stats[index] = ligne
    return ligne
end

function equipement.Construire(contenu, bandeau)
    L = NS.L
    if contenu.equipement then return contenu.equipement end

    local vue = CreateFrame("Frame", nil, contenu)
    vue:SetPoint("TOPLEFT", contenu, "TOPLEFT", 0, 0)
    vue:SetPoint("BOTTOMRIGHT", contenu, "BOTTOMRIGHT", 0, 0)
    vue.bandeau = bandeau

    -- Emplacements, deux colonnes aerees.
    vue.cases = {}
    local precedents = {}
    local hauteurColonnes = 0
    local rangBas = 0
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local bouton = CreerCaseEmplacement(vue)
        local cote = emplacement.cote
        if cote == "bas" then
            bouton:SetWidth((LARGEUR_COLONNE * 2 + 8) / 3 - 4)
            bouton.rang = rangBas
            rangBas = rangBas + 1
        else
            bouton:SetWidth(LARGEUR_COLONNE)
            if precedents[cote] then
                bouton:SetPoint("TOPLEFT", precedents[cote], "BOTTOMLEFT", 0, -2)
            elseif cote == "g" then
                bouton:SetPoint("TOPLEFT", vue, "TOPLEFT", 0, 0)
            else
                bouton:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE + 8, 0)
            end
            precedents[cote] = bouton
            if cote == "g" then hauteurColonnes = hauteurColonnes + HAUTEUR_CASE + 2 end
        end
        bouton.emplacement = emplacement
        bouton:SetScript("OnClick", function()
            vue.choisi = emplacement.nom
            ecran.selectionObjets = {}
            equipement.Rendre(contenu, bandeau)
        end)
        vue.cases[emplacement.nom] = bouton
    end

    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        if emplacement.cote == "bas" then
            local bouton = vue.cases[emplacement.nom]
            bouton:SetPoint("TOPLEFT", vue, "TOPLEFT",
                bouton.rang * ((LARGEUR_COLONNE * 2 + 8) / 3), -(hauteurColonnes + 8))
        end
    end
    vue.hauteurColonnes = hauteurColonnes

    -- Zone de choix, a droite.
    local choix = CreateFrame("Frame", nil, vue)
    choix:SetPoint("TOPLEFT", vue, "TOPLEFT", LARGEUR_COLONNE * 2 + 18, 0)
    choix:SetPoint("BOTTOMRIGHT", vue, "BOTTOMRIGHT", 0, 0)
    vue.choix = choix

    choix.titre = choix:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    choix.titre:SetPoint("TOPLEFT", choix, "TOPLEFT", 0, 0)
    choix.sousTitre = choix:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    choix.sousTitre:SetPoint("TOPLEFT", choix.titre, "BOTTOMLEFT", 0, -2)
    choix.sousTitre:SetPoint("RIGHT", choix, "RIGHT", 0, 0)
    choix.sousTitre:SetJustifyH("LEFT")
    choix.sousTitre:SetWordWrap(false)

    choix.filtres = {}

    -- Case d'accueil : une vraie case d'objet du jeu, vide, ou l'on glisse
    -- un objet de ses sacs pour le comparer. Clic droit : la vider.
    local depot
    -- Elle vit dans la bande de comparaison, en bas a droite : on y glisse un
    -- objet ramasse, CraftCore trouve son emplacement et le compare a ce qui
    -- est porte. Elle ne se confond pas avec la liste des objets fabricables.
    local okCase, cree = pcall(CreateFrame, "Button", nil, bandeau, "ItemButtonTemplate")
    depot = okCase and cree or CreateFrame("Button", nil, bandeau)
    depot:SetPoint("TOPRIGHT", bandeau, "TOPRIGHT", -14, -26)
    depot:SetSize(37, 37)
    depot:EnableMouse(true)
    depot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    depot.vide = depot:CreateTexture(nil, "BACKGROUND")
    depot.vide:SetAllPoints()
    depot.vide:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    depot.image = depot.icon or depot.Icon or depot:CreateTexture(nil, "ARTWORK")
    if not (depot.icon or depot.Icon) then depot.image:SetAllPoints() end
    depot.texte = depot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    depot.texte:SetPoint("BOTTOMRIGHT", depot, "TOPRIGHT", 0, 4)
    depot.texte:SetJustifyH("RIGHT")
    depot:SetScript("OnReceiveDrag", function()
        equipement.RecevoirObjet(contenu, bandeau)
    end)
    depot:SetScript("OnClick", function(_, bouton)
        if bouton == "RightButton" then
            ecran.objetDepose = nil
            equipement.Rendre(contenu, bandeau)
            return
        end
        equipement.RecevoirObjet(contenu, bandeau)
    end)
    depot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if ecran.objetDepose and GameTooltip.SetItemByID then
            pcall(GameTooltip.SetItemByID, GameTooltip, ecran.objetDepose)
            GameTooltip:AddLine(L.GEAR_DROP_CLEAR, 0.6, 0.6, 0.6)
        else
            GameTooltip:SetText(L.GEAR_DROP_TITLE)
            GameTooltip:AddLine(L.GEAR_DROP_TIP, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    depot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    vue.depot = depot

    -- La liste defile : un emplacement peut compter des dizaines d'objets.
    local defilement = CreateFrame("ScrollFrame", nil, choix, "UIPanelScrollFrameTemplate")
    defilement:SetPoint("TOPLEFT", choix.sousTitre, "BOTTOMLEFT", 0, -6)
    defilement:SetPoint("BOTTOMRIGHT", choix, "BOTTOMRIGHT", -24, 0)
    vue.defilement = defilement

    local liste = CreateFrame("Frame", nil, defilement)
    liste:SetSize(LARGEUR_CHOIX - 26, 1)
    defilement:SetScrollChild(liste)
    vue.liste = liste

    contenu.equipement = vue
    return vue
end

-- Recoit un objet depose ou tenu par le curseur.
function equipement.RecevoirObjet(contenu, bandeau)
    local info = NS.Lecture("GetCursorInfo")
    if not info then return end
    local genre, id, lien = NS.Appeler(info, nil)
    if genre ~= "item" then return end
    local objet = tonumber(id) or tonumber(string.match(tostring(lien or ""), "item:(%d+)"))
    if not objet then return end

    local vider = NS.Lecture("ClearCursor")
    if vider then NS.Appeler(vider) end

    -- L'objet va a un emplacement : on y passe, au lieu de l'ignorer parce
    -- qu'un autre emplacement etait choisi.
    local code = NS.emplacements.DeLObjet(objet)
    if not code then
        NS.Dire(L.GEAR_DROP_NOT_GEAR)
        return
    end
    local vue = contenu.equipement
    for _, e in ipairs(NS.emplacements.DuPersonnage) do
        if e.code == code then
            if vue then vue.choisi = e.nom end
            break
        end
    end
    ecran.objetDepose = objet
    -- L'objet glisse est celui qu'on compare, seul.
    ecran.selectionObjets = {}
    equipement.Rendre(contenu, bandeau)
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

local function RendreBandeau(bandeau, porte, choisis)
    if #choisis == 0 then
        bandeau:Show()
        if not bandeau.titre then
            bandeau.titre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            bandeau.titre:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8, -6)
            bandeau.titre:SetPoint("RIGHT", bandeau, "RIGHT", -120, 0)
            bandeau.titre:SetJustifyH("LEFT")
            bandeau.contre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            bandeau.contre:SetPoint("TOPLEFT", bandeau.titre, "BOTTOMLEFT", 0, -2)
        end
        bandeau.titre:SetText("")
        bandeau.contre:SetText(L.GEAR_PICK)
        for _, ligne in ipairs(bandeau.stats or {}) do ligne:Hide() end
        return
    end
    bandeau:Show()

    if not bandeau.titre then
        bandeau.titre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bandeau.titre:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8, -6)
        bandeau.titre:SetPoint("RIGHT", bandeau, "RIGHT", -120, 0)
        bandeau.titre:SetJustifyH("LEFT")
        bandeau.contre = bandeau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bandeau.contre:SetPoint("TOPLEFT", bandeau.titre, "BOTTOMLEFT", 0, -2)
    end

    local noms = {}
    for _, c in ipairs(choisis) do table.insert(noms, c.nom or "") end
    bandeau.titre:SetText(table.concat(noms, "     "))
    bandeau.contre:SetText(porte and porte.nom
        and string.format(L.EQUIP_AGAINST, porte.nom) or L.EQUIP_AGAINST_NOTHING)

    local cles, vues = {}, {}
    local function ajouter(stats)
        for cle in pairs(stats or {}) do
            if not vues[cle] then vues[cle] = true table.insert(cles, cle) end
        end
    end
    ajouter(porte and porte.stats)
    for _, c in ipairs(choisis) do ajouter(c.stats) end
    NS.objets.OrdonnerStats(cles)

    -- Le niveau d'objet en premier, il se lit comme une statistique.
    table.insert(cles, 1, "__niveau")

    local index = 0
    for _, cle in ipairs(cles) do
        index = index + 1
        local ligne = CreerLigneStat(bandeau, index)
        local colonne = math.floor((index - 1) / LIGNES_PAR_COLONNE)
        local rang = (index - 1) % LIGNES_PAR_COLONNE
        ligne:ClearAllPoints()
        ligne:SetPoint("TOPLEFT", bandeau, "TOPLEFT", 8 + colonne * 330, -34 - rang * 15)
        ligne:SetWidth(320)

        local libelle = (cle == "__niveau") and L.EQUIP_LEVEL:gsub("%%d", ""):gsub("%s+$", "")
            or NS.objets.LibelleDeStat(cle)
        ligne.cle:SetText(libelle)

        local base = (cle == "__niveau") and (porte and porte.niveau or 0)
            or ((porte and porte.stats and porte.stats[cle]) or 0)
        ligne.colonnes[1]:SetText(tostring(base))
        ligne.colonnes[1]:SetTextColor(0.55, 0.55, 0.55)

        for rangChoisi = 1, 2 do
            local colonneTexte = ligne.colonnes[rangChoisi + 1]
            local c = choisis[rangChoisi]
            if c then
                local valeur = (cle == "__niveau") and (c.niveau or 0)
                    or ((c.stats and c.stats[cle]) or 0)
                local ecart = valeur - base
                colonneTexte:SetText(string.format("%d  %s%d", valeur, ecart > 0 and "+" or "", ecart))
                if ecart > 0 then colonneTexte:SetTextColor(0.31, 0.82, 0.41)
                elseif ecart < 0 then colonneTexte:SetTextColor(0.85, 0.40, 0.37)
                else colonneTexte:SetTextColor(0.55, 0.55, 0.55) end
                colonneTexte:Show()
            else
                colonneTexte:SetText("")
                colonneTexte:Hide()
            end
        end
        ligne:Show()
    end
    for suite = index + 1, #(bandeau.stats or {}) do bandeau.stats[suite]:Hide() end
end
local function NomDObjet(id)
    local info = NS.objets.Info(id)
    return (info and info.nom) or ("objet " .. tostring(id))
end

-- Ligne de liste neutre (titre de quete, ou rien a montrer).
local function PoserTitre(ligne, liste, y, texte, r, v, b, police)
    ligne:ClearAllPoints()
    ligne:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
    ligne:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)
    ligne.fond:Hide()
    ligne.icone:Hide()
    ligne.nom:SetFontObject(police or "GameFontNormalSmall")
    ligne.nom:SetText(texte)
    ligne.nom:SetTextColor(r, v, b)
    ligne.etat:SetText("")
    if ligne.coche then ligne.coche:Hide() end
    ligne:SetScript("OnEnter", nil)
    ligne:SetScript("OnLeave", nil)
    ligne:SetScript("OnClick", nil)
    ligne:SetHeight(HAUTEUR_CANDIDAT)
    ligne:Show()
end

function equipement.Rendre(contenu, bandeau, cle)
    L = NS.L
    cleCourante = cle or cleCourante
    local vue = equipement.Construire(contenu, bandeau)
    vue:Show()

    local cleAffichee = cleCourante
    local estConnecte = (cleAffichee == NS.ClePersonnage())
    local fiche = NS.equip.Fiche(cleAffichee)

    -- Emplacements : une coche quand une quete en cours donne un objet pour lui.
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local bouton = vue.cases[emplacement.nom]
        local objet = ObjetPorteDe(fiche, emplacement.nom, estConnecte)
        local info = objet and NS.objets.Info(objet)

        bouton.ou:SetText(NS.emplacements.LibelleDuSlot(emplacement))
        if info and info.nom then
            bouton.porte:SetText(info.nom)
            bouton.porte:SetTextColor(NS.objets.CouleurDuNom(objet))
        elseif objet then
            bouton.porte:SetText(L.EQUIP_NOT_READ)
            bouton.porte:SetTextColor(0.55, 0.55, 0.55)
        else
            bouton.porte:SetText(L.EQUIP_EMPTY)
            bouton.porte:SetTextColor(0.55, 0.55, 0.55)
        end
        if info and info.icone then
            bouton.icone:SetTexture(info.icone)
            bouton.icone:Show()
        else
            bouton.icone:Hide()
        end

        bouton.marque:SetShown(#NS.equip.QuetesPour(cleAffichee, emplacement.code) > 0)

        if emplacement.nom == vue.choisi then
            bouton.ou:SetTextColor(1, 0.82, 0)
        else
            bouton.ou:SetTextColor(0.82, 0.69, 0.4)
        end
        bouton:Show()
    end

    vue.choisi = vue.choisi or NS.emplacements.DuPersonnage[1].nom
    local emplacementChoisi
    for _, e in ipairs(NS.emplacements.DuPersonnage) do
        if e.nom == vue.choisi then emplacementChoisi = e break end
    end

    local objetPorte = ObjetPorteDe(fiche, vue.choisi, estConnecte)
    local porte = InfosObjet(objetPorte)

    local choix = vue.choix
    choix.titre:SetText(NS.emplacements.LibelleDuSlot(emplacementChoisi))
    choix.sousTitre:SetText(porte and porte.nom or L.EQUIP_EMPTY)

    -- Filtres de matiere, comme CraftCore : seulement ce que ce personnage
    -- peut porter, la meilleure matiere active par defaut.
    local portables = NS.equip.ArmuresPortables(fiche)
    local filtresPerso = ecran.filtresParPerso[cleAffichee or ""]
    if not filtresPerso then
        filtresPerso = {}
        for sous, rang in pairs(portables) do
            if rang == "prefere" then filtresPerso[sous] = true end
        end
        ecran.filtresParPerso[cleAffichee or ""] = filtresPerso
    end

    local quetes = NS.equip.QuetesPour(cleAffichee, emplacementChoisi.code)
    local presentes, matieres, nomsMatieres = {}, {}, {}
    for _, q in ipairs(quetes) do
        for _, c in ipairs(q.objets) do
            if c.sousClasse and portables[c.sousClasse] and not presentes[c.sousClasse] then
                presentes[c.sousClasse] = true
                nomsMatieres[c.sousClasse] = c.matiere or tostring(c.sousClasse)
                table.insert(matieres, c.sousClasse)
            end
        end
    end
    table.sort(matieres, function(a, b)
        if (portables[a] == "prefere") ~= (portables[b] == "prefere") then return portables[a] == "prefere" end
        return a > b
    end)
    local precedentFiltre
    for rang, sous in ipairs(matieres) do
        local bouton = choix.filtres[rang]
        if not bouton then
            bouton = CreerBoutonFiltre(choix)
            choix.filtres[rang] = bouton
        end
        local actif = filtresPerso[sous] == true
        bouton:SetText(nomsMatieres[sous])
        bouton:SetWidth(math.max(54, (bouton.GetTextWidth and bouton:GetTextWidth() or 40) + 16))
        if portables[sous] == "prefere" then
            bouton:SetAlpha(actif and 1 or 0.6)
        else
            bouton:SetAlpha(actif and 0.75 or 0.4)
        end
        bouton:SetScript("OnClick", function()
            filtresPerso[sous] = (not filtresPerso[sous]) or nil
            equipement.Rendre(contenu, bandeau)
        end)
        bouton:ClearAllPoints()
        if precedentFiltre then
            bouton:SetPoint("LEFT", precedentFiltre, "RIGHT", 3, 0)
        else
            bouton:SetPoint("TOPLEFT", choix.sousTitre, "BOTTOMLEFT", 0, -6)
        end
        bouton:Show()
        precedentFiltre = bouton
    end
    for rang = #matieres + 1, #choix.filtres do choix.filtres[rang]:Hide() end

    local ancreHaut = (#matieres > 0 and choix.filtres[1]) or choix.sousTitre
    vue.depot:Show()
    if ecran.objetDepose then
        vue.depot.image:SetTexture(NS.Appeler(NS.jeu.iconeObjet, ecran.objetDepose))
        vue.depot.image:Show()
        vue.depot.texte:SetText(NomDObjet(ecran.objetDepose))
    else
        vue.depot.image:Hide()
        vue.depot.texte:SetText(L.GEAR_DROP)
    end

    local aucunFiltre = (next(filtresPerso) == nil)
    local function garde(c)
        if not c.sousClasse then return true end
        if not portables[c.sousClasse] then return false end
        if aucunFiltre then return true end
        return filtresPerso[c.sousClasse] == true
    end

    -- Fleches, comme CraftCore : doree pour le meilleur, verte si mieux que
    -- ce qui est porte, rouge si moins bien.
    local scorePorte = objetPorte and NS.equip.Score(objetPorte, fiche) or 0
    local meilleurObjet, meilleurScore
    local ameliorations, moinsBien = {}, {}
    for _, q in ipairs(quetes) do
        for _, c in ipairs(q.objets) do
            if garde(c) then
                local s = NS.equip.Score(c.objet, fiche)
                if s < scorePorte then moinsBien[c.objet] = true end
                if s > scorePorte then
                    ameliorations[c.objet] = true
                    if not meilleurScore or s > meilleurScore then meilleurObjet, meilleurScore = c.objet, s end
                end
            end
        end
    end
    if not vue.legende then
        vue.legende = vue.choix:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        vue.legende:SetJustifyH("LEFT")
    end
    vue.legende:ClearAllPoints()
    vue.legende:SetPoint("TOPLEFT", ancreHaut, "BOTTOMLEFT", 0, -6)
    local avecLegende = (meilleurObjet or next(moinsBien)) and true or false
    vue.legende:SetWidth(LARGEUR_CHOIX - 10)
    vue.legende:SetWordWrap(true)
    vue.legende:SetText(avecLegende and L.GEAR_MEDALS or "")
    vue.legende:SetShown(avecLegende)
    vue.defilement:ClearAllPoints()
    vue.defilement:SetPoint("TOPLEFT", avecLegende and vue.legende or ancreHaut, "BOTTOMLEFT", 0, -6)
    vue.defilement:SetPoint("BOTTOMRIGHT", vue.choix, "BOTTOMRIGHT", -24, 0)

    local liste = vue.liste
    local index, y = 0, 0
    local choisis = {}
    local rien = true

    -- Une rubrique par quete, ses objets pour cet emplacement dessous.
    for _, q in ipairs(quetes) do
        local retenus = {}
        for _, c in ipairs(q.objets) do
            if garde(c) then table.insert(retenus, c) end
        end
        if #retenus > 0 then
            rien = false
            index = index + 1
            local titre = CreerLigneCandidat(liste, index)
            local texte = string.format("[%d] %s", tonumber(q.niveau) or 0, q.titre or ("#" .. tostring(q.id)))
            PoserTitre(titre, liste, y, texte, 0.82, 0.69, 0.4)
            local idQuete = q.id
            titre:SetScript("OnEnter", function(self)
                local p = NS.base.PersoParCle(cleAffichee)
                local quete = p and p.quetes and p.quetes[idQuete]
                if not quete then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                NS.ref.InfobulleDeQuete(GameTooltip, quete, idQuete, p)
                GameTooltip:Show()
            end)
            titre:SetScript("OnLeave", function() GameTooltip:Hide() end)
            y = y + HAUTEUR_CANDIDAT

            for _, c in ipairs(retenus) do
                index = index + 1
                local ligne = CreerLigneCandidat(liste, index)
                ligne:ClearAllPoints()
                ligne:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
                ligne:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)

                local info = NS.objets.Info(c.objet)
                if info and info.icone then
                    ligne.icone:SetTexture(info.icone)
                    ligne.icone:Show()
                else
                    ligne.icone:Hide()
                end
                ligne.nom:SetFontObject("GameFontHighlightSmall")
                ligne.nom:SetText((info and info.nom) or ("objet " .. tostring(c.objet)))
                ligne.nom:SetTextColor(NS.objets.CouleurDuNom(c.objet))

                local etatTexte = c.auChoix and L.GEAR_REWARD_CHOICE or L.GEAR_REWARD_GIVEN
                if q.complete == true or q.complete == 1 then
                    ligne.etat:SetText(etatTexte .. ", " .. L.GEAR_REWARD_READY)
                    ligne.etat:SetTextColor(0.31, 0.82, 0.41)
                else
                    ligne.etat:SetText(etatTexte)
                    ligne.etat:SetTextColor(0.55, 0.55, 0.55)
                end

                local choisi = ecran.selectionObjets[c.objet] == true
                ligne.fond:SetShown(choisi)
                if choisi then
                    local infos = InfosObjet(c.objet)
                    if infos then
                        infos.source = c
                        table.insert(choisis, infos)
                    end
                end

                local objetCandidat = c.objet
                ligne:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, objetCandidat) end
                    GameTooltip:Show()
                end)
                ligne:SetScript("OnLeave", function() GameTooltip:Hide() end)
                ligne:SetScript("OnClick", function()
                    if ecran.selectionObjets[objetCandidat] then
                        ecran.selectionObjets = {}
                    else
                        ecran.selectionObjets = { [objetCandidat] = true }
                        ecran.objetDepose = nil
                    end
                    equipement.Rendre(contenu, bandeau)
                end)
                if not ligne.coche then
                    ligne.coche = ligne:CreateTexture(nil, "OVERLAY")
                    ligne.coche:SetSize(16, 16)
                    ligne.coche:SetPoint("TOPRIGHT", ligne, "TOPRIGHT", -3, -4)
                end
                local medaille = (c.objet == meilleurObjet and "or")
                    or (ameliorations[c.objet] and "mieux") or (moinsBien[c.objet] and "moins")
                if medaille == "moins" then
                    ligne.coche:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
                    ligne.coche:SetVertexColor(0.9, 0.3, 0.3)
                else
                    ligne.coche:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
                    if medaille == "or" then
                        ligne.coche:SetVertexColor(1, 0.82, 0)
                    else
                        ligne.coche:SetVertexColor(0.31, 0.82, 0.41)
                    end
                end
                ligne.coche:SetShown(medaille and true or false)
                local hauteur = 8 + (ligne.nom:GetStringHeight() or 12) + 2 + (ligne.etat:GetStringHeight() or 12)
                hauteur = math.max(HAUTEUR_CANDIDAT, math.min(hauteur, 52))
                ligne:SetHeight(hauteur)
                ligne:Show()
                y = y + hauteur + 2
            end
        end
    end

    -- L'objet depose par glisser, s'il va a cet emplacement.
    if ecran.objetDepose then
        local objet = ecran.objetDepose
        if NS.emplacements.DeLObjet(objet) == emplacementChoisi.code then
            local infos = InfosObjet(objet)
            if infos then
                infos.source = { origine = "depose" }
                table.insert(choisis, infos)
                rien = false
            end
        else
            ecran.objetDepose = nil
        end
    end

    if rien then
        index = index + 1
        local vide = CreerLigneCandidat(liste, index)
        PoserTitre(vide, liste, y, (#quetes > 0) and L.GEAR_NONE_HERE or L.GEAR_NO_QUEST,
            0.55, 0.55, 0.55, "GameFontDisableSmall")
        y = y + HAUTEUR_CANDIDAT
    end

    for suite = index + 1, #(liste.candidats or {}) do liste.candidats[suite]:Hide() end
    liste:SetHeight(math.max(y, 1))

    while #choisis > 1 do table.remove(choisis) end
    RendreBandeau(bandeau, porte, choisis)
end

function equipement.Cacher(contenu, bandeau)
    if contenu.equipement then
        contenu.equipement:Hide()
        if contenu.equipement.depot then contenu.equipement.depot:Hide() end
    end
    if bandeau then bandeau:Hide() end
end
