local _, NS = ...

-- La fenetre d'AuraCore, comme celles de la suite (menu a gauche,
-- parchemin). AuraCore embarque le socle de la suite : seul, il a la meme
-- fenetre, avec son seul onglet.

NS.fenetre = {}
local F = NS.fenetre

local T = NS.T
local function R() return NS.anneau.Reglages() end
local function Redessiner() pcall(NS.anneau.Dessiner) end

-- Petite illustration des deux dispositions, avec le depart et le sens
-- choisis : cinq icones numerotees, dans l'ordre ou elles apparaissent.
local function Schema(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(588, 258)
    f.cas, f.boutons = {}, {}
    for i, cle in ipairs({ "equilibre", "suite", "reserve" }) do
        -- Un petit panneau encadre par cas : celui en place est lumineux,
        -- bordure doree ; les autres sont grises.
        local okB, c = pcall(CreateFrame, "Frame", nil, f, "BackdropTemplate")
        if not okB or not c then c = CreateFrame("Frame", nil, f) end
        c:SetSize(186, 258)
        c:SetPoint("TOPLEFT", (i - 1) * 201, 0)
        if c.SetBackdrop then
            c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        end
        c.cle = cle
        c.titre = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        c.titre:SetPoint("TOP", 0, -12)
        c.centre = CreateFrame("Frame", nil, c)
        c.centre:SetSize(1, 1)
        c.centre:SetPoint("TOP", 0, -84)
        c.perso = c:CreateTexture(nil, "ARTWORK")
        c.perso:SetSize(14, 14)
        c.perso:SetPoint("CENTER", c.centre)
        c.perso:SetTexture("Interface\\Masks\\CircleMaskScalable")
        c.points = {}
        for n = 1, 5 do
            local p = CreateFrame("Frame", nil, c)
            p:SetSize(16, 16)
            p.rond = p:CreateTexture(nil, "ARTWORK")
            p.rond:SetAllPoints()
            p.rond:SetTexture("Interface\\Masks\\CircleMaskScalable")
            p.chiffre = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            p.chiffre:SetPoint("CENTER", 0, 0)
            c.points[n] = p
        end
        c.texte = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.texte:SetPoint("TOP", 0, -142)
        c.texte:SetWidth(166)
        c.texte:SetJustifyH("CENTER")
        c.texte:SetJustifyV("TOP")
        c.bouton = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        c.bouton:SetSize(120, 22)
        c.bouton:SetPoint("BOTTOM", 0, 12)
        c.bouton:SetScript("OnClick", function() R().disposition = cle Redessiner() f.Rendre() end)
        f.boutons[i] = c.bouton
        f.cas[i] = c
    end
    local TITRES = {
        equilibre = function() return T("Équilibrée", "Balanced") end,
        suite = function() return T("À la suite", "In a row") end,
        reserve = function() return T("Places réservées", "Reserved places") end,
    }
    local TEXTES = {
        equilibre = function() return T("Les icônes actives s'écartent pour occuper tout l'arc libre. Deux icônes : face à face. Toutes bougent quand une arrive ou part.",
            "Active icons spread over the whole free arc. Two icons : facing each other. They all move when one comes or goes.") end,
        suite = function() return T("Les icônes actives se suivent, collées, depuis le point de départ. Rien n'est réservé : votre aspect n'apparaît que s'il est actif.",
            "Active icons follow one another, side by side, from the starting point. Nothing is reserved : your aspect only shows when active.") end,
        reserve = function() return T("Ce que vous vous mettez vous-même (aspect, aura, armure) a sa place, grisée s'il manque. Les procs suivent, chacun à sa place.",
            "What you put on yourself (aspect, aura, armour) has its own place, greyed when missing. Procs follow, each in its place.") end,
    }
    function f.Rendre()
        local r = R()
        local depart = ({ haut = 90, droite = 0, bas = 270, gauche = 180 })[r.depart] or 90
        local signe = (r.sens == "antihoraire") and 1 or -1
        for _, c in ipairs(f.cas) do
            local choisi = r.disposition == c.cle
            c.titre:SetText(TITRES[c.cle]())
            c.texte:SetText(TEXTES[c.cle]())
            if c.SetBackdrop then
                c:SetBackdropColor(0.04, 0.04, 0.05, 0.92)
                if choisi then c:SetBackdropBorderColor(1, 0.82, 0, 1) else c:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end
            end
            -- Lumineux pour celui en place ; gris pour les autres.
            if choisi then c.titre:SetTextColor(1, 0.82, 0) c.texte:SetTextColor(1, 1, 1)
            else c.titre:SetTextColor(0.75, 0.75, 0.75) c.texte:SetTextColor(0.7, 0.7, 0.7) end
            c.perso:SetVertexColor(0.6, 0.6, 0.6, choisi and 0.9 or 0.4)
            local pas = (c.cle == "equilibre") and 72 or 34
            for n, p in ipairs(c.points) do
                local a = math.rad(depart + signe * (n - 1) * pas)
                p:ClearAllPoints()
                p:SetPoint("CENTER", c.centre, "CENTER", math.cos(a) * 42, math.sin(a) * 42)
                local manque = c.cle == "reserve" and n == 2
                if not choisi then
                    p.rond:SetVertexColor(0.4, 0.4, 0.4, manque and 0.4 or 0.8)
                elseif manque then
                    p.rond:SetVertexColor(0.45, 0.45, 0.45, 0.6)
                else
                    p.rond:SetVertexColor(0.85, 0.7, 0.35, 1)
                end
                if c.cle == "reserve" and n <= 3 then p.chiffre:SetText("")
                else p.chiffre:SetText(c.cle == "reserve" and (n - 3) or n) end
                p.chiffre:SetTextColor(choisi and 1 or 0.6, choisi and 1 or 0.6, choisi and 1 or 0.6)
            end
            c.bouton:SetText(choisi and T("Activée", "Active") or T("Activer", "Activate"))
            c.bouton:SetEnabled(not choisi)
        end
    end
    return f
end
F.Schema = Schema

-- La page de la suite complete (AuraCore installe seul).
local ADRESSE_SUITE = "https://www.curseforge.com/projects/1817365"
function F.PageSuite()
    return { cle = "suite", icone = "Interface\\Icons\\INV_Misc_Book_11",
        libelle = function() return T("La suite", "The suite") end,
        construire = function(page, O)
            page.t1 = O.Section()
            page.intro = O.Detail(70)
            page.t2 = O.Texte(20)
            page.rLien = O.Rangee(28)
            local e = CreateFrame("EditBox", nil, page.rLien, "InputBoxTemplate")
            e:SetSize(420, 24)
            e:SetPoint("LEFT", page.rLien, "LEFT", 6, 0)
            e:SetAutoFocus(false)
            e:SetText(ADRESSE_SUITE)
            e:SetCursorPosition(0)
            -- L'adresse ne se modifie pas : un clic la selectionne pour la copier.
            e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            e:SetScript("OnTextChanged", function(self, parUtilisateur)
                if parUtilisateur then self:SetText(ADRESSE_SUITE) self:HighlightText() end
            end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            page.lien = e
            table.insert(page.focus, e)
            page.aide = O.Detail(30)
        end,
        rendre = function(page)
            page.t1:SetText("Forever SagaCore")
            page.intro:SetText(T("AuraCore fait partie de Forever SagaCore, une suite d'add-ons pour WoW Forever : fabrications et métiers (CraftCore), quêtes et trajets (QuestCore), carte et services (MapCore), héritage (LegacyCore). Installés ensemble, ils partagent la même fenêtre, les mêmes réglages et la même manette.",
                "AuraCore is part of Forever SagaCore, a suite of add-ons for WoW Forever : crafting and professions (CraftCore), quests and routes (QuestCore), map and services (MapCore), legacy (LegacyCore). Installed together, they share one window, the same settings and the same gamepad controls."))
            page.t2:SetText(T("Retrouvez la suite complète sur CurseForge :", "Get the complete suite on CurseForge :"))
            page.rLien.nom:SetText("")
            page.aide:SetText(T("Cliquez sur l'adresse, puis Ctrl+C (Cmd+C sur Mac) pour la copier.", "Click the address, then Ctrl+C (Cmd+C on Mac) to copy it."))
        end }
end

function F.Construire()
    local S = _G.CoreSuite
    if F.w or not (S and S.FenetreAPages) then return F.w end
    local pages = {
            { cle = "disposition", icone = "Interface\\Icons\\INV_Misc_Spyglass_02",
              libelle = function() return T("Disposition", "Layout") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Detail(40)
                  page.rSchema = O.Rangee(270)
                  page.schema = Schema(page.rSchema)
                  page.schema:SetPoint("TOP", page.rSchema, "TOP", 0, 0)
                  table.insert(page.controles, page.schema)
                  for _, b in ipairs(page.schema.boutons) do table.insert(page.focus, b) end
                  page.rDepart = O.Rangee()
                  O.Liste(page.rDepart, function() return { { "haut", T("Haut", "Top") }, { "droite", T("Droite", "Right") },
                      { "bas", T("Bas", "Bottom") }, { "gauche", T("Gauche", "Left") } } end,
                      function() return R().depart end, function(v) R().depart = v Redessiner() end)
                  page.rSens = O.Rangee()
                  O.Liste(page.rSens, function() return { { "horaire", T("Horaire", "Clockwise") }, { "antihoraire", T("Antihoraire", "Counterclockwise") } } end,
                      function() return R().sens end, function(v) R().sens = v Redessiner() end)
              end,
              rendre = function(page)
                  page.t1:SetText(T("Disposition des icônes", "Icon layout"))
                  page.intro:SetText(T("Comment se placent les icônes hors des quarts réservés (nourriture, flacon, potion et buffs de groupe) : ce que vous vous mettez vous-même et ce qui se déclenche.",
                      "How the icons outside the reserved quarters are placed : what you put on yourself and what procs."))
                  page.schema.Rendre()
                  page.rDepart.nom:SetText(T("Point de départ", "Starting point"))
                  page.rSens.nom:SetText(T("Sens", "Direction"))
              end },
            { cle = "anneau", icone = "Interface\\Icons\\Spell_Holy_AuraOfLight",
              libelle = function() return T("L'anneau", "The ring") end,
              construire = function(page, O)
                  local function Pct(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end
                  page.t1 = O.Section()
                  page.intro = O.Detail(40)
                  page.rVoir = O.Rangee()
                  page.cVoir = O.Case(page.rVoir, function(oui) R().cache = (not oui) or nil Redessiner() end)
                  page.cVoir:SetPoint("RIGHT", page.rVoir, "RIGHT", -8, 0)
                  page.rTaille = O.Rangee()
                  O.Liste(page.rTaille, function() return { { 24, T("Petite", "Small") }, { 30, T("Moyenne", "Medium") }, { 38, T("Grande", "Large") } } end,
                      function() return R().taille end, function(v) R().taille = v Redessiner() end)
                  page.rHauteur = O.Rangee()
                  O.Curseur(page.rHauteur, -400, 400, 10, function() return R().hauteur end, function(v) R().hauteur = v Redessiner() end, nil, true)
                  page.rRayon = O.Rangee()
                  O.Curseur(page.rRayon, 50, 300, 10, function() return R().rayon end, function(v) R().rayon = v Redessiner() end, nil, true)
                  page.rOpacite = O.Rangee()
                  O.Curseur(page.rOpacite, 0.1, 1, 0.1, function() return R().opaciteAnneau end, function(v) R().opaciteAnneau = v Redessiner() end, Pct, true)
                  page.rDuree = O.Rangee()
                  O.Liste(page.rDuree, function() return { { "interieur", T("Dans l'icône", "Inside the icon") }, { "exterieur", T("À l'extérieur de l'icône", "Outside the icon") }, { "aucune", T("Non affichée", "Hidden") } } end,
                      function() return R().dureePlace end, function(v) R().dureePlace = v Redessiner() end)
                  page.rRemplir = O.Rangee()
                  O.Liste(page.rRemplir, function() return { { "degressif", T("Dégressif", "Decreasing") }, { "progressif", T("Progressif", "Increasing") } } end,
                      function() return R().remplissage end, function(v) R().remplissage = v Redessiner() end)
                  page.rConso = O.Rangee()
                  page.cConso = O.Case(page.rConso, function(oui) R().consoVisibles = oui and true or false Redessiner() end)
                  page.cConso:SetPoint("RIGHT", page.rConso, "RIGHT", -8, 0)
                  page.rConsoPlace = O.Rangee()
                  O.Liste(page.rConsoPlace, function() return { { "haut", T("Quart du haut", "Top quarter") }, { "droite", T("Quart droit", "Right quarter") },
                      { "bas", T("Quart du bas", "Bottom quarter") }, { "gauche", T("Quart gauche", "Left quarter") } } end,
                      function() return R().consoPlace end, function(v) R().consoPlace = v Redessiner() end)
                  page.rGroupe = O.Rangee()
                  page.cGroupe = O.Case(page.rGroupe, function(oui) R().groupeVisibles = oui and true or false Redessiner() end)
                  page.cGroupe:SetPoint("RIGHT", page.rGroupe, "RIGHT", -8, 0)
                  page.rGroupePlace = O.Rangee()
                  O.Liste(page.rGroupePlace, function() return { { "haut", T("Quart du haut", "Top quarter") }, { "droite", T("Quart droit", "Right quarter") },
                      { "bas", T("Quart du bas", "Bottom quarter") }, { "gauche", T("Quart gauche", "Left quarter") } } end,
                      function() return R().groupePlace end, function(v) R().groupePlace = v Redessiner() end)
                  page.rDemande = O.Rangee()
                  page.bDemande = O.Bouton(page.rDemande, 100, function() NS.demande.Envoyer() end)
                  page.bDemande:SetPoint("RIGHT", page.rDemande, "RIGHT", -8, 0)
                  page.apercu = O.Detail(44)
                  page.rBouton = O.Rangee()
                  page.cBouton = O.Case(page.rBouton, function(oui) R().boutonBuffsCache = (not oui) or nil pcall(NS.demande.MettreAJour) end)
                  page.cBouton:SetPoint("RIGHT", page.rBouton, "RIGHT", -8, 0)
                  page.bReplacer = O.Bouton(page.rBouton, 90, function() NS.demande.ReplacerBouton() end)
                  page.bReplacer:SetPoint("RIGHT", page.cBouton, "LEFT", -8, 0)
                  page.aide = O.Detail(30)
              end,
              rendre = function(page)
                  page.t1:SetText(T("L'anneau autour du personnage", "The ring around your character"))
                  page.intro:SetText(T("Seize places fixes en cercle autour du personnage. En couleur ce qui est actif, en gris ce qui manque. Passez la souris sur une icône pour voir ce qu'elle est.",
                      "Sixteen fixed places in a circle around your character. In colour what is active, in grey what is missing. Hover an icon to see what it is."))
                  page.rVoir.nom:SetText(T("Afficher l'anneau", "Show the ring"))
                  page.cVoir:SetChecked(not R().cache)
                  page.rTaille.nom:SetText(T("Taille des icônes", "Icon size"))
                  page.rHauteur.nom:SetText(T("Hauteur à l'écran", "Height on screen"))
                  page.rRayon.nom:SetText(T("Rayon minimum", "Minimum radius"))
                  page.rOpacite.nom:SetText(T("Opacité de l'anneau", "Ring opacity"))
                  page.rDuree.nom:SetText(T("Durée restante", "Time left"))
                  page.rRemplir.nom:SetText(T("Cercle de durée", "Duration circle"))
                  page.rConso.nom:SetText(T("Nourriture, flacon et potion", "Food, flask and potion"))
                  page.cConso:SetChecked(R().consoVisibles ~= false)
                  page.rConsoPlace.nom:SetText(T("Leur place", "Their place"))
                  page.rGroupe.nom:SetText(T("Buffs que le groupe peut donner", "Buffs your group can give"))
                  page.cGroupe:SetChecked(R().groupeVisibles ~= false)
                  page.rGroupePlace.nom:SetText(T("Leur place", "Their place"))
                  page.rDemande.nom:SetText(T("Demander au groupe les buffs manquants", "Ask the group for missing buffs"))
                  page.bDemande:SetText(T("Demander", "Ask"))
                  page.apercu:SetText(NS.demande.Apercu())
                  page.rBouton.nom:SetText(T("Bouton au-dessus du portrait", "Button above the portrait"))
                  page.cBouton:SetChecked(not R().boutonBuffsCache)
                  page.bReplacer:SetText(T("Replacer", "Reset"))
                  page.aide:SetText(T("/auracore off cache tout, /auracore on le remet, /auracore buffs demande les buffs manquants.", "/auracore off hides everything, /auracore on shows it again, /auracore buffs asks for missing buffs."))
              end },
            { cle = "nuisibles", icone = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
              libelle = function() return T("Nuisibles", "Debuffs") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Detail(40)
                  page.rAPart = O.Rangee()
                  page.cAPart = O.Case(page.rAPart, function(oui) R().nuisiblesAPart = oui and true or false Redessiner() end)
                  page.cAPart:SetPoint("RIGHT", page.rAPart, "RIGHT", -8, 0)
                  page.rPlace = O.Rangee()
                  O.Liste(page.rPlace, function() return { { "dedans", T("À l'intérieur de l'anneau", "Inside the ring") }, { "dehors", T("À l'extérieur de l'anneau", "Outside the ring") } } end,
                      function() return R().nuisiblesPlace end, function(v) R().nuisiblesPlace = v Redessiner() end)
                  page.rTaille = O.Rangee()
                  O.Liste(page.rTaille, function() return { { "petite", T("Plus petites", "Smaller") }, { "meme", T("Comme l'anneau", "Same as the ring") }, { "grande", T("Plus grandes", "Larger") } } end,
                      function() return R().nuisiblesTaille end, function(v) R().nuisiblesTaille = v Redessiner() end)
                  page.rDepart = O.Rangee()
                  O.Liste(page.rDepart, function() return { { "haut", T("Haut", "Top") }, { "hautdroite", T("En haut à droite", "Top right") },
                      { "droite", T("Droite", "Right") }, { "basdroite", T("En bas à droite", "Bottom right") }, { "bas", T("Bas", "Bottom") },
                      { "basgauche", T("En bas à gauche", "Bottom left") }, { "gauche", T("Gauche", "Left") }, { "hautgauche", T("En haut à gauche", "Top left") } } end,
                      function() return R().nuisiblesDepart end, function(v) R().nuisiblesDepart = v Redessiner() end)
                  page.rSens = O.Rangee()
                  O.Liste(page.rSens, function() return { { "horaire", T("Horaire", "Clockwise") }, { "antihoraire", T("Antihoraire", "Counterclockwise") } } end,
                      function() return R().nuisiblesSens end, function(v) R().nuisiblesSens = v Redessiner() end)
                  page.rDuree = O.Rangee()
                  O.Liste(page.rDuree, function() return { { "interieur", T("Dans l'icône", "Inside the icon") }, { "exterieur", T("À l'extérieur de l'icône", "Outside the icon") }, { "aucune", T("Non affichée", "Hidden") } } end,
                      function() return R().nuisiblesDuree end, function(v) R().nuisiblesDuree = v Redessiner() end)
              end,
              rendre = function(page)
                  page.t1:SetText(T("Les effets nuisibles", "Debuffs"))
                  page.intro:SetText(T("Sur leur propre cercle, autour ou à l'intérieur de l'anneau, sans jamais le toucher. Le premier arrivé prend la place 1, le suivant la 2, et ainsi de suite.",
                      "On their own circle, around or inside the ring, never touching it. The first one takes place 1, the next place 2, and so on."))
                  page.rAPart.nom:SetText(T("Cercle à part", "Separate circle"))
                  page.cAPart:SetChecked(R().nuisiblesAPart ~= false)
                  page.rPlace.nom:SetText(T("Position", "Position"))
                  page.rTaille.nom:SetText(T("Taille des icônes", "Icon size"))
                  page.rDepart.nom:SetText(T("Point de départ", "Starting point"))
                  page.rSens.nom:SetText(T("Sens", "Direction"))
                  page.rDuree.nom:SetText(T("Durée restante", "Time left"))
              end },
            { cle = "petits", icone = "Interface\\Icons\\Spell_Nature_Thorns",
              libelle = function() return T("Petits sorts", "Minor spells") end,
              construire = function(page, O)
                  page.t1 = O.Section()
                  page.intro = O.Detail(56)
                  page.lignes = {}
                  for _, p in ipairs(NS.donnees.PETITS) do
                      local cle = p.cle
                      local l = O.Rangee()
                      l.icone = l:CreateTexture(nil, "ARTWORK")
                      l.icone:SetSize(18, 18)
                      l.icone:SetPoint("LEFT", l, "LEFT", 0, 0)
                      l.nom:ClearAllPoints()
                      l.nom:SetPoint("LEFT", l.icone, "RIGHT", 8, 0)
                      l.case = O.Case(l, function(oui)
                          local r = R()
                          r.petits = type(r.petits) == "table" and r.petits or {}
                          r.petits[cle] = oui and true or nil
                          if NS.anneau.OublierEcartes then NS.anneau.OublierEcartes() end
                          Redessiner()
                      end)
                      l.case:SetPoint("RIGHT", l, "RIGHT", -8, 0)
                      l.p = p
                      table.insert(page.lignes, l)
                  end
              end,
              rendre = function(page)
                  page.t1:SetText(T("Petits sorts des autres", "Other players' minor spells"))
                  page.intro:SetText(T("Les vrais buffs (bénédictions, Robustesse, Intelligence des Arcanes, Marque du fauve) ont toujours leur place dans leur quart. Les petits sorts, courts ou de situation, sont cachés : cochez ceux que vous voulez voir dans l'anneau.",
                      "Real buffs (blessings, Fortitude, Arcane Intellect, Mark of the Wild) always have their place in their quarter. Minor spells, short or situational, are hidden : tick the ones you want to see in the ring."))
                  local choisis = type(R().petits) == "table" and R().petits or {}
                  for _, l in ipairs(page.lignes) do
                      l.icone:SetTexture(NS.donnees.Icone(l.p.ids[1]))
                      l.nom:SetText(NS.donnees.Nom(l.p.ids[1]) or "?")
                      l.case:SetChecked(choisis[l.p.cle] == true)
                  end
              end },
    }
    -- Seul (sans la suite) : une page pour faire connaitre la suite complete.
    if S.Seul and S.Seul() then table.insert(pages, F.PageSuite()) end
    F.w = S.FenetreAPages({
        nom = "AuraCoreFenetre", cle = "AuraCore", icone = "Interface\\Icons\\Spell_Holy_AuraOfLight",
        titre = function() return "AuraCore |cffff8800(" .. T("bêta", "beta") .. ")|r" end,
        pages = pages,
    })
    return F.w
end

function F.Ouvrir()
    local S = _G.CoreSuite
    if F.Construire() and S and S.Ouvrir then S.Ouvrir("AuraCore") return true end
    return false
end

-- Reglages d'AuraCore dans Options, Add-ons, Forever SagaCore.
do
    local function Pct(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end
    local function Champ(cle, mini, maxi)
        return function() return R()[cle] end, function(v) R()[cle] = v Redessiner() end, 10, mini, maxi
    end
    _G.SagaCoreOptions = type(_G.SagaCoreOptions) == "table" and _G.SagaCoreOptions or {}
    _G.SagaCoreOptions.AuraCore = { titre = "AuraCore", ordre = 6, elements = function()
        local liste = {
            { "section", function() return T("L'anneau", "The ring") end },
            { "case", function() return T("Anneau affiché", "Ring shown") end,
              function() return not R().cache end, function(v) R().cache = (not v) or nil Redessiner() end },
            { "choix", function() return T("Taille des icônes", "Icon size") end,
              { { 24, function() return T("Petite", "Small") end }, { 30, function() return T("Moyenne", "Medium") end },
                { 38, function() return T("Grande", "Large") end } },
              function() return R().taille end, function(v) R().taille = v Redessiner() end },
            { "valeur", function() return T("Hauteur à l'écran", "Height on screen") end, Champ("hauteur", -400, 400) },
            { "valeur", function() return T("Rayon minimum", "Minimum radius") end, Champ("rayon", 50, 300) },
            { "choix", function() return T("Durée restante", "Time left") end,
              { { "interieur", function() return T("Dans l'icône", "Inside the icon") end }, { "exterieur", function() return T("À l'extérieur de l'icône", "Outside the icon") end }, { "aucune", function() return T("Non affichée", "Hidden") end } },
              function() return R().dureePlace end, function(v) R().dureePlace = v Redessiner() end },
            { "choix", function() return T("Cercle de durée", "Duration circle") end,
              { { "degressif", function() return T("Dégressif", "Decreasing") end }, { "progressif", function() return T("Progressif", "Increasing") end } },
              function() return R().remplissage end, function(v) R().remplissage = v Redessiner() end },
            { "case", function() return T("Nourriture, flacon et potion", "Food, flask and potion") end,
              function() return R().consoVisibles ~= false end, function(v) R().consoVisibles = v and true or false Redessiner() end },
            { "choix", function() return T("Leur place", "Their place") end,
              { { "haut", function() return T("Quart du haut", "Top quarter") end }, { "droite", function() return T("Quart droit", "Right quarter") end },
                { "bas", function() return T("Quart du bas", "Bottom quarter") end }, { "gauche", function() return T("Quart gauche", "Left quarter") end } },
              function() return R().consoPlace end, function(v) R().consoPlace = v Redessiner() end },
            { "case", function() return T("Buffs que le groupe peut donner", "Buffs your group can give") end,
              function() return R().groupeVisibles ~= false end, function(v) R().groupeVisibles = v and true or false Redessiner() end },
            { "choix", function() return T("Leur place", "Their place") end,
              { { "haut", function() return T("Quart du haut", "Top quarter") end }, { "droite", function() return T("Quart droit", "Right quarter") end },
                { "bas", function() return T("Quart du bas", "Bottom quarter") end }, { "gauche", function() return T("Quart gauche", "Left quarter") end } },
              function() return R().groupePlace end, function(v) R().groupePlace = v Redessiner() end },
            { "section", function() return T("Disposition des autres icônes", "Layout of the other icons") end },
            { "cadre", 262, function(parent) local sc = Schema(parent) sc:SetPoint("TOP", 0, 0) return sc.Rendre end },
            { "choix", function() return T("Point de départ", "Starting point") end,
              { { "haut", function() return T("Haut", "Top") end }, { "droite", function() return T("Droite", "Right") end },
                { "bas", function() return T("Bas", "Bottom") end }, { "gauche", function() return T("Gauche", "Left") end } },
              function() return R().depart end, function(v) R().depart = v Redessiner() end },
            { "choix", function() return T("Sens", "Direction") end,
              { { "horaire", function() return T("Horaire", "Clockwise") end }, { "antihoraire", function() return T("Antihoraire", "Counterclockwise") end } },
              function() return R().sens end, function(v) R().sens = v Redessiner() end },
            { "valeur", function() return T("Opacité de l'anneau", "Ring opacity") end,
              function() return R().opaciteAnneau end, function(v) R().opaciteAnneau = v Redessiner() end, 0.1, 0.1, 1, Pct },
        }
        return liste
    end }
end
