local _, NS = ...

-- ===========================================================================
-- Page de l'equipement
-- ===========================================================================

-- Page de l'equipement, vue transverse du compte.
--
-- A gauche les emplacements du personnage regarde. A droite, pour l'emplacement
-- choisi, tout ce que le compte peut offrir : ce que ce personnage sait faire,
-- ce qu'un autre sait faire, et ce qui dort deja chez un autre. En bas, la
-- comparaison des objets retenus.
--
-- Aucun objet n'est declare meilleur : on rassemble, l'utilisateur tranche.

NS.equipement = {}
local equipement = NS.equipement

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
            NS.ecran.selectionObjets = {}
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
            NS.ecran.objetDepose = nil
            equipement.Rendre(contenu, bandeau)
            return
        end
        equipement.RecevoirObjet(contenu, bandeau)
    end)
    depot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if NS.ecran.objetDepose and GameTooltip.SetItemByID then
            pcall(GameTooltip.SetItemByID, GameTooltip, NS.ecran.objetDepose)
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
    NS.ecran.objetDepose = objet
    -- L'objet glisse est celui qu'on compare, seul.
    NS.ecran.selectionObjets = {}
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

    -- Un chiffre au plus apres la virgule (les degats par seconde).
    local function Chiffre(v)
        v = tonumber(v) or 0
        local arrondi = math.floor(math.abs(v) * 10 + 0.5) / 10
        if v < 0 then arrondi = -arrondi end
        if arrondi == math.floor(arrondi) then return string.format("%d", arrondi) end
        return string.format("%.1f", arrondi)
    end
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
        ligne.colonnes[1]:SetText(Chiffre(base))
        ligne.colonnes[1]:SetTextColor(0.55, 0.55, 0.55)

        for rangChoisi = 1, 2 do
            local colonneTexte = ligne.colonnes[rangChoisi + 1]
            local c = choisis[rangChoisi]
            if c then
                local valeur = (cle == "__niveau") and (c.niveau or 0)
                    or ((c.stats and c.stats[cle]) or 0)
                local ecart = valeur - base
                colonneTexte:SetText(Chiffre(valeur) .. "  " .. (ecart > 0 and "+" or "") .. Chiffre(ecart))
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

function equipement.Rendre(contenu, bandeau)
    L = NS.L
    local vue = equipement.Construire(contenu, bandeau)
    vue:Show()

    local cleAffichee = NS.base.CleAffichee()
    local estConnecte = (cleAffichee == NS.ClePersonnage())
    local fiche = NS.base.FicheAffichee()

    -- Emplacements.
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

        local candidats = NS.transverse.Candidats(emplacement.code)
        local combien = #candidats.moi + #candidats.autres + #candidats.possedes
        bouton.marque:SetShown(combien > 0)

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

    -- Filtres de matiere : seulement les armures que ce personnage peut porter.
    -- La meilleure pour sa classe et son niveau est la preference, active par
    -- defaut ; une matiere encore portable mais depassee reste proposee, en
    -- retrait. Le reste n'est meme pas montre. Un emplacement d'arme ou de
    -- bijou n'a pas de matiere : la rangee disparait.
    local portables = NS.transverse.ArmuresPortables(fiche)
    NS.ecran.filtresParPerso = NS.ecran.filtresParPerso or {}
    local filtresPerso = NS.ecran.filtresParPerso[cleAffichee]
    if not filtresPerso then
        filtresPerso = {}
        for sous, rang in pairs(portables) do
            if rang == "prefere" then filtresPerso[sous] = true end
        end
        NS.ecran.filtresParPerso[cleAffichee] = filtresPerso
    end

    local candidatsDeLaPlace = NS.transverse.Candidats(emplacementChoisi.code)
    local presentes, matieres, nomsMatieres = {}, {}, {}
    for _, groupe in ipairs({ candidatsDeLaPlace.moi, candidatsDeLaPlace.autres, candidatsDeLaPlace.possedes }) do
        for _, c in ipairs(groupe) do
            if c.sousClasse and portables[c.sousClasse] and not presentes[c.sousClasse] then
                presentes[c.sousClasse] = true
                nomsMatieres[c.sousClasse] = c.matiere or tostring(c.sousClasse)
                table.insert(matieres, c.sousClasse)
            end
        end
    end
    -- La preference d'abord, puis les autres de la plus lourde a la plus legere.
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
        -- Preference pleine ; matiere depassee en retrait, meme active.
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

    -- Haut de la liste : sous les filtres, ou sous le titre s'il n'y en a pas.
    -- Toujours le premier filtre, aligne a gauche sous le titre : jamais le
    -- dernier, qui decalerait la liste vers la droite.
    local ancreHaut = (#matieres > 0 and choix.filtres[1]) or choix.sousTitre
    vue.depot:Show()
    if NS.ecran.objetDepose then
        vue.depot.image:SetTexture(NS.Appeler(NS.jeu.iconeObjet, NS.ecran.objetDepose))
        vue.depot.image:Show()
        vue.depot.texte:SetText(NS.inventaire.NomDObjet(NS.ecran.objetDepose))
    else
        vue.depot.image:Hide()
        vue.depot.texte:SetText(L.GEAR_DROP)
    end

    -- Candidats, groupes par origine. Une armure que ce personnage ne peut
    -- pas porter n'apparait jamais ; les autres suivent les filtres.
    local candidats = candidatsDeLaPlace
    local aucunFiltre = (next(filtresPerso) == nil)
    local function garde(c)
        if not c.sousClasse then return true end
        if not portables[c.sousClasse] then return false end
        if aucunFiltre then return true end
        return filtresPerso[c.sousClasse] == true
    end

    -- Le meilleur pour ce personnage parmi ce qu'on peut fabriquer (lui ou un
    -- autre), s'il vaut mieux que ce qu'il porte : une coche le signale.
    local scorePorte = objetPorte and NS.transverse.Score(objetPorte, fiche) or 0
    -- Comparaison a ce qui est porte, pour chaque objet affiche : fleche
    -- montante si c'est mieux pour la classe (doree pour le meilleur), fleche
    -- descendante si c'est moins bien, rien si c'est equivalent.
    local meilleurObjet, meilleurScore
    local ameliorations, moinsBien = {}, {}
    for _, groupe in ipairs({ candidats.moi, candidats.autres, candidats.possedes }) do
        for _, c in ipairs(groupe) do
            if garde(c) and c.objet then
                local s = NS.transverse.Score(c.objet, fiche)
                if s < scorePorte then moinsBien[c.objet] = true end
                if s > scorePorte then
                    ameliorations[c.objet] = true
                    if not meilleurScore or s > meilleurScore then meilleurObjet, meilleurScore = c.objet, s end
                end
            end
        end
    end
    -- Des paliers de progression a montrer dans cette liste ?
    local paliersVus = false
    for _, c in ipairs(candidats.moi) do
        if garde(c) and c.recette then
            local p = NS.recettes.Palier((CraftCoreDB.recettes or {})[tostring(c.recette)])
            if p and p ~= "rien" then paliersVus = true break end
        end
    end
    -- Legende, seulement quand il y a des medailles a lire.
    if not vue.legende then
        vue.legende = vue.choix:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        vue.legende:SetJustifyH("LEFT")
    end
    vue.legende:ClearAllPoints()
    vue.legende:SetPoint("TOPLEFT", ancreHaut, "BOTTOMLEFT", 0, -6)
    local textes = {}
    if meilleurObjet or next(moinsBien) then table.insert(textes, L.GEAR_MEDALS) end
    if paliersVus then table.insert(textes, NS.recettes.LegendeDesPaliers()) end
    vue.legende:SetWidth(LARGEUR_CHOIX - 10)
    vue.legende:SetWordWrap(true)
    vue.legende:SetText(table.concat(textes, "\n"))
    local avecLegende = #textes > 0
    vue.legende:SetShown(avecLegende)
    -- La liste commence sous la legende quand elle est la, sinon sous la case.
    vue.defilement:ClearAllPoints()
    vue.defilement:SetPoint("TOPLEFT", avecLegende and vue.legende or ancreHaut, "BOTTOMLEFT", 0, -6)
    vue.defilement:SetPoint("BOTTOMRIGHT", vue.choix, "BOTTOMRIGHT", -24, 0)

    NS.ecran.selectionObjets = NS.ecran.selectionObjets or {}
    local liste = vue.liste
    local index, y = 0, 0
    local choisis = {}

    local groupes = {
        { titre = L.GEAR_MINE, entrees = candidats.moi, origine = "moi" },
        { titre = L.GEAR_OTHERS, entrees = candidats.autres, origine = "autres" },
        { titre = L.GEAR_OWNED, entrees = candidats.possedes, origine = "possedes" },
    }

    local rien = true
    for _, groupe in ipairs(groupes) do
        local retenus = {}
        for _, c in ipairs(groupe.entrees) do
            if garde(c) then table.insert(retenus, c) end
        end
        if #retenus > 0 then
            rien = false
            index = index + 1
            local titre = CreerLigneCandidat(liste, index)
            titre:ClearAllPoints()
            titre:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
            titre:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)
            titre.fond:Hide()
            titre.icone:Hide()
            titre.nom:SetFontObject("GameFontNormalSmall")
            titre.nom:SetText(groupe.titre)
            titre.nom:SetTextColor(0.82, 0.69, 0.4)
            titre.etat:SetText("")
            if titre.coche then titre.coche:Hide() end
            if titre.palier then titre.palier:Hide() end
            titre:SetScript("OnEnter", nil)
            titre:SetScript("OnLeave", nil)
            titre:SetScript("OnClick", nil)
            titre:SetHeight(HAUTEUR_CANDIDAT)
            titre:Show()
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

                if groupe.origine == "moi" then
                    if c.pret then
                        ligne.etat:SetText(c.combien and c.combien > 0
                            and string.format(L.EQUIP_CAN_MAKE, c.combien) or L.RECIPES_CAN_CRAFT)
                        ligne.etat:SetTextColor(0.31, 0.82, 0.41)
                    else
                        ligne.etat:SetText(L.RECIPES_MISSING_SHORT:format(1))
                        ligne.etat:SetTextColor(0.55, 0.55, 0.55)
                    end
                elseif groupe.origine == "autres" then
                    ligne.etat:SetText(string.format(L.GEAR_MAKER, c.nomCourt))
                    ligne.etat:SetTextColor(0.55, 0.55, 0.55)
                else
                    ligne.etat:SetText(string.format(
                        c.ou == "banque" and L.GEAR_IN_BANK or L.GEAR_IN_BAGS, c.nomCourt))
                    ligne.etat:SetTextColor(0.31, 0.82, 0.41)
                end

                local choisi = NS.ecran.selectionObjets[c.objet] == true
                ligne.fond:SetShown(choisi)
                if choisi then
                    local fiche = InfosObjet(c.objet)
                    if fiche then
                        c.origine = groupe.origine
                        fiche.source = c
                        table.insert(choisis, fiche)
                    end
                end

                local objetCandidat = c.objet
                -- Survol : l'objet, et pour une recette, ses composants un par un
                -- avec ce qu'on en a. Rien de plus a l'ecran.
                local candidatSurvol = c
                ligne:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, candidatSurvol.objet) end
                    local recette = candidatSurvol.recette and (CraftCoreDB.recettes or {})[tostring(candidatSurvol.recette)]
                    if recette then NS.inventaire.ComposantsDansLInfobulle(GameTooltip, recette) end
                    GameTooltip:Show()
                end)
                ligne:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Un seul objet compare a la fois : plus lisible.
                ligne:SetScript("OnClick", function()
                    if NS.ecran.selectionObjets[objetCandidat] then
                        NS.ecran.selectionObjets = {}
                    else
                        NS.ecran.selectionObjets = { [objetCandidat] = true }
                        NS.ecran.objetDepose = nil
                    end
                    equipement.Rendre(contenu, bandeau)
                end)
                -- Coche du meilleur choix pour ce personnage.
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
                -- Progression du metier : la meme coche que dans Recettes, en
                -- coin d'icone, pour ce que ce personnage fabrique lui-meme.
                if not ligne.palier then
                    ligne.palier = ligne:CreateTexture(nil, "OVERLAY")
                    ligne.palier:SetSize(12, 12)
                    ligne.palier:SetPoint("BOTTOMRIGHT", ligne.icone, "BOTTOMRIGHT", 4, -3)
                    ligne.palier:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                end
                local palier = groupe.origine == "moi" and c.recette
                    and NS.recettes.Palier((CraftCoreDB.recettes or {})[tostring(c.recette)])
                if palier and palier ~= "rien" then
                    local couleur = NS.recettes.COULEURS_PALIER[palier]
                    ligne.palier:SetVertexColor(couleur[1], couleur[2], couleur[3])
                    ligne.palier:Show()
                    paliersVus = true
                else
                    ligne.palier:Hide()
                end
                -- Hauteur selon le texte : nom sur une ou deux lignes, puis l'etat.
                local hauteur = 8 + (ligne.nom:GetStringHeight() or 12) + 2 + (ligne.etat:GetStringHeight() or 12)
                hauteur = math.max(HAUTEUR_CANDIDAT, math.min(hauteur, 52))
                ligne:SetHeight(hauteur)
                ligne:Show()
                y = y + hauteur + 2
            end
        end
    end

    -- L'objet depose par glisser, s'il va a cet emplacement.
    if NS.ecran.objetDepose then
        local objet = NS.ecran.objetDepose
        if NS.emplacements.DeLObjet(objet) == emplacementChoisi.code then
            local fiche = InfosObjet(objet)
            if fiche then
                fiche.source = { origine = "depose" }
                table.insert(choisis, fiche)
                rien = false
            end
        else
            NS.ecran.objetDepose = nil
        end
    end

    if rien then
        index = index + 1
        local vide = CreerLigneCandidat(liste, index)
        vide:ClearAllPoints()
        vide:SetPoint("TOPLEFT", liste, "TOPLEFT", 0, -y)
        vide:SetPoint("TOPRIGHT", liste, "TOPRIGHT", 0, -y)
        vide.fond:Hide()
        vide.icone:Hide()
        vide.nom:SetFontObject("GameFontDisableSmall")
        vide.nom:SetText(L.GEAR_NONE_HERE)
        vide.nom:SetTextColor(0.55, 0.55, 0.55)
        vide.etat:SetText("")
        if vide.coche then vide.coche:Hide() end
        if vide.palier then vide.palier:Hide() end
        vide:SetScript("OnEnter", nil)
        vide:SetScript("OnLeave", nil)
        vide:SetScript("OnClick", nil)
        vide:SetHeight(HAUTEUR_CANDIDAT)
        vide:Show()
        y = y + HAUTEUR_CANDIDAT
    end

    for suite = index + 1, #(liste.candidats or {}) do liste.candidats[suite]:Hide() end
    liste:SetHeight(math.max(y, 1))

    -- Au plus deux objets compares a la fois.
    while #choisis > 1 do table.remove(choisis) end
    RendreBandeau(bandeau, porte, choisis)
    equipement.PoserBoutonDeProjet(bandeau, choisis, emplacementChoisi, contenu)
end

-- Bouton de projet transverse, quand l'objet retenu est fabricable par un autre.
function equipement.PoserBoutonDeProjet(bandeau, choisis, emplacement, contenu)
    local transverse
    for _, c in ipairs(choisis) do
        if c.source and c.source.qui and c.source.recette then transverse = c break end
    end

    if not bandeau.boutonProjet then
        bandeau.boutonProjet = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonProjet:SetHeight(20)
        bandeau.boutonProjet:SetPoint("BOTTOMRIGHT", bandeau, "BOTTOMRIGHT", -8, 4)
    end

    -- Fabriquer : un objet que le personnage connecte sait faire, et qu'il
    -- peut faire maintenant. Meme bouton que dans les recettes.
    local aFaire
    for _, c in ipairs(choisis) do
        if c.source and c.source.origine == "moi" and c.source.recette then aFaire = c break end
    end
    if not bandeau.boutonFabriquer then
        bandeau.boutonFabriquer = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonFabriquer:SetHeight(20)
    end
    local fabriquer = bandeau.boutonFabriquer
    -- Ajouter : en projet ou en fabrication rapide, sans quitter la page.
    if not bandeau.boutonAjouter then
        bandeau.boutonAjouter = CreateFrame("Button", nil, bandeau, "UIPanelButtonTemplate")
        bandeau.boutonAjouter:SetHeight(20)
    end
    local ajouter = bandeau.boutonAjouter
    ajouter:ClearAllPoints()
    if transverse then
        ajouter:SetPoint("BOTTOMRIGHT", bandeau.boutonProjet, "BOTTOMLEFT", -6, 0)
    else
        ajouter:SetPoint("BOTTOMRIGHT", bandeau, "BOTTOMRIGHT", -8, 4)
    end
    fabriquer:ClearAllPoints()
    fabriquer:SetPoint("BOTTOMRIGHT", ajouter, "BOTTOMLEFT", -6, 0)
    if aFaire and NS.base.CleAffichee() == NS.ClePersonnage() then
        local idRecette, nomObjet = aFaire.source.recette, aFaire.nom
        -- Un clic, une action : l'objet part dans les fabrications rapides.
        ajouter:SetText(L.GEAR_ADD)
        ajouter:SetWidth(math.max(90, (ajouter.GetTextWidth and ajouter:GetTextWidth() or 70) + 24))
        ajouter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.GEAR_ADD_TIP, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ajouter:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ajouter:SetScript("OnClick", function()
            NS.actions.AjouterA({ cible = "rapides", nom = L.NAV_QUICK }, idRecette, nomObjet, 1)
            NS.ecran.Montrer(NS.ecran.page)
        end)
        ajouter:Show()
    else
        ajouter:Hide()
    end
    if aFaire and NS.base.CleAffichee() == NS.ClePersonnage() then
        local recette = CraftCoreDB.recettes and CraftCoreDB.recettes[tostring(aFaire.source.recette)]
        fabriquer:SetText(L.GEAR_CRAFT)
        fabriquer:SetWidth(math.max(90, (fabriquer.GetTextWidth and fabriquer:GetTextWidth() or 70) + 24))
        -- Toujours la, grise s'il manque des composants ; le survol dit
        -- lesquels et ou ils sont.
        NS.actions.PreparerBoutonFabriquer(fabriquer, recette, 1)
    else
        fabriquer:Hide()
    end

    -- Plus de rangee de destinations : on cache celle d'une ancienne version.
    for _, b in ipairs(bandeau.choixAjout or {}) do b:Hide() end

    if not transverse then
        bandeau.boutonProjet:Hide()
        return
    end

    local libelle = string.format(L.GEAR_MAKE_PROJECT, transverse.nom or "", transverse.source.nomCourt)
    bandeau.boutonProjet:SetText(libelle)
    bandeau.boutonProjet:SetWidth(math.max(200,
        (bandeau.boutonProjet.GetTextWidth and bandeau.boutonProjet:GetTextWidth() or 180) + 24))
    bandeau.boutonProjet:SetScript("OnClick", function()
        NS.projets.CreerTransverse(transverse.source.qui, NS.base.CleAffichee(),
            transverse.source.recette, transverse.nom)
        NS.ecran.Montrer("projets")
    end)
    bandeau.boutonProjet:Show()
end

function equipement.Cacher(contenu, bandeau)
    if contenu.equipement then
        contenu.equipement:Hide()
        if contenu.equipement.depot then contenu.equipement.depot:Hide() end
    end
    if bandeau then
        bandeau:Hide()
        if bandeau.boutonProjet then bandeau.boutonProjet:Hide() end
        if bandeau.boutonFabriquer then bandeau.boutonFabriquer:Hide() end
        if bandeau.boutonAjouter then bandeau.boutonAjouter:Hide() end
        for _, b in ipairs(bandeau.choixAjout or {}) do b:Hide() end
    end
end

-- Chaque redessin de la page (choix d'un emplacement, d'un objet a comparer)
-- repasse les textes a l'encre sur parchemin, comme le dessin complet de la
-- fenetre : sinon les couleurs redeviennent claires et sans ombre.
do
    local rendreBrut = equipement.Rendre
    equipement.Rendre = function(contenu, bandeau, ...)
        local resultat = { rendreBrut(contenu, bandeau, ...) }
        pcall(function()
            local parchemin = NS.charte.Fond() == "parchemin"
            if contenu then NS.charte.Encrer(contenu, parchemin) end
            if bandeau then NS.charte.Encrer(bandeau, parchemin) end
        end)
        return unpack(resultat)
    end
end
