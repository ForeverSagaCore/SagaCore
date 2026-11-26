local _, NS = ...
-- Un filet de separation : en apparence moderne, la couleur commune du theme
-- (repeinte quand il change) ; sinon la couleur donnee.
local function PeindreFilet(t, r, g, b, a)
    local S = _G.CoreSuite
    if S and S.PeindreFilet then S.PeindreFilet(t, r, g, b, a) else t:SetColorTexture(r, g, b, a) end
end

-- ===========================================================================
-- Suivi de recolte
-- ===========================================================================
--
-- Une petite fenetre du jeu, comme le suivi des quetes : a chaque objet
-- ramasse qui sert a un projet ou a la progression d'un metier, elle dit ce
-- qu'il apporte. Elle compte la session de farm, se deplace a la souris et
-- garde sa place, devient presque transparente quand on court, se masque
-- par sa croix et revient au prochain objet utile. Reinitialiser remet la
-- session a zero. Rien n'est jamais dit dans la discussion.
--
-- Deux onglets :
--   Session     tout ce qui a ete ramasse d'utile, et a quoi ca sert ;
--   Objectifs   les rangs vises (page Progression, "Viser un rang") et les
--               projets : chacun avec son pourcentage, et deplie, ses
--               matieres (grisees tant qu'on n'en a aucune).

local infobulles = NS.infobulles

NS.suivi = {}
local suivi = NS.suivi

local LARGEUR_SUIVI = 300
local ALPHA_EN_COURSE = 0.25
local cadreSuivi

local function Session()
    local d = CraftCoreDB
    if type(d) ~= "table" then return { objets = {}, ordre = 0 } end
    local cle = NS.ClePersonnage and NS.ClePersonnage() or "?"
    d.suiviRecolte = d.suiviRecolte or {}
    if not d.suiviRecolte[cle] then d.suiviRecolte[cle] = { objets = {}, ordre = 0, debut = NS.Horodatage() } end
    return d.suiviRecolte[cle]
end

local function Actif()
    local g = NS.base.ReglagesGeneraux()
    if g.suiviRecolte == nil then g.suiviRecolte = true end
    return g.suiviRecolte
end

-- Ce qu'un objet apporte, en quelques lignes, pour le personnage connecte.
local function Utilite(objet)
    local L = NS.L
    local lignes = {}
    -- Projets et fabrications rapides : ce qui manque encore apres ce butin.
    infobulles.Invalider()
    local projets = NS.infobulles.Index()[objet]
    if projets then
        for nom, manque in pairs(projets) do
            if manque > 0 then
                table.insert(lignes, { string.format(L.TRACK_PROJECT_MISSING, nom, manque), 1, 0.82, 0 })
            else
                table.insert(lignes, { string.format(L.TRACK_PROJECT_DONE, nom), 0.31, 0.82, 0.41 })
            end
        end
    end
    -- Progression : les recettes oranges qui l'utilisent, et jusqu'ou le
    -- metier peut monter maintenant.
    local fiche = NS.base.Personnage()
    local catalogue = NS.recettes
    if fiche and type(fiche.metiers) == "table" and catalogue and catalogue.Progression then
        for cleMetier, sien in pairs(fiche.metiers) do
            local ligneMetier = tonumber(cleMetier)
            if ligneMetier and ligneMetier > 0 and type(sien) == "table" and sien.rang then
                local sert
                for _, recette in ipairs((catalogue.Pour(ligneMetier))) do
                    if catalogue.ChanceDePoint(recette, sien.rang) >= 0.5 and catalogue.EstApprise(recette.id) then
                        for _, comp in ipairs(recette.composants or {}) do
                            if comp.objet == objet then sert = recette break end
                        end
                    end
                    if sert then break end
                end
                if sert then
                    local plan = catalogue.Progression(ligneMetier, sien.rang, sien.rangMax, nil)
                    local nom = sien.nom or catalogue.NomDuMetier(ligneMetier) or "?"
                    if plan.atteint > sien.rang then
                        table.insert(lignes, { string.format(L.TRACK_PROGRESS, nom, plan.atteint, plan.atteint - sien.rang),
                            0.31, 0.82, 0.41 })
                    else
                        table.insert(lignes, { string.format(L.TRACK_PROGRESS_USE, nom, sert.nom or "?"), 0.8, 0.8, 0.8 })
                    end
                end
            end
        end
    end
    return lignes
end

-- ---------------------------------------------------------------------------
-- Objectifs : rangs vises et projets
-- ---------------------------------------------------------------------------

local function EstApprise(id)
    return NS.recettes and NS.recettes.EstApprise and NS.recettes.EstApprise(id) or false
end

-- Une matiere d'objectif : requis, ce qui manque encore, ce qu'on possede.
local function Matieres(requis, manques)
    local liste = {}
    for objet, n in pairs(requis) do
        if n > 0 then
            -- Couvert = requis moins ce qui manque encore : le meme calcul que le
            -- pourcentage, donc une matiere complete est toujours en vert.
            local manque = math.max(0, math.min(n, manques[objet] or 0))
            local possede = n - manque
            table.insert(liste, { objet = objet, requis = n, manque = manque, possede = possede })
        end
    end
    -- En cours d'abord, puis pas commencees, puis completes.
    local function Ordre(m)
        if m.manque == 0 then return 3 end
        if m.possede == 0 then return 2 end
        return 1
    end
    table.sort(liste, function(a, b)
        if Ordre(a) ~= Ordre(b) then return Ordre(a) < Ordre(b) end
        return a.manque > b.manque
    end)
    return liste
end

-- Caisses suivies du personnage connecte : le pack choisi, ce que le compte
-- en a (tous personnages du meme camp), ce qui est deja chez lui.
local function ObjectifsDeCaisses(liste, cle)
    if not (NS.caisses and NS.caisses.Suivies) then return end
    for _, c in ipairs(NS.caisses.Suivies(cle)) do
        local total = NS.inventaire.TotalPossede(c.objet) or 0
        local requis = c.requis or 1
        local manque = math.max(0, requis - total)
        local pct = math.min(1, total / requis)
        table.insert(liste, { groupe = "caisses", genre = "caisse", caisse = c.caisse, cle = "caisse" .. tostring(c.caisse),
            nom = NS.inventaire.NomDObjet(c.caisse), titreAnnonce = NS.inventaire.NomDObjet(c.caisse),
            pct = pct, atteint = pct >= 1, fabriquer = {}, nLignes = 0, lignes = {},
            matieres = { { objet = c.objet, requis = requis, manque = manque, possede = requis - manque } } })
    end
end

-- Rangs vises du personnage connecte.
local function ObjectifsDeProgression(liste)
    local L = NS.L
    local fiche = NS.base.Personnage()
    local catalogue = NS.recettes
    if not fiche or not catalogue or not catalogue.MetiersVises then return end
    -- Metiers qui ont deja leur projet de progression : l'objectif n'est pas
    -- montre en double, le projet suffit (rang actuel, rang vise, recettes).
    local avecProjet = {}
    for _, projet in ipairs(NS.projets and NS.projets.Tous and NS.projets.Tous(false) or {}) do
        if projet.progression and not projet.horsSuivi then avecProjet[tostring(projet.progression)] = true end
    end
    for _, cle in ipairs(catalogue.MetiersVises(fiche)) do
        local ligne = tonumber(cle)
        local sien = type(fiche.metiers) == "table" and fiche.metiers[tostring(cle)]
        if ligne and type(sien) == "table" and sien.rang and not avecProjet[tostring(cle)] then
            local nom = sien.nom or catalogue.NomDuMetier(ligne) or "?"
            -- Un objectif par rang vise, a la suite (82, puis 90...).
            for _, seg in ipairs(catalogue.PlansVises(fiche, cle, sien.rang, sien.rangMax)) do
            local vise, plan = seg.vise, seg.plan
            -- Un meilleur plan existe (recette apprise entre-temps) : il est
            -- seulement propose ; rien ne change sans l'accord du joueur.
            if seg.autre and suivi.ProposerPlan then
                pcall(suivi.ProposerPlan, fiche, cle, nom, vise, plan, seg.autre)
            end
            local requis = {}
            for _, etape in ipairs(plan.etapes or {}) do
                for _, comp in ipairs(etape.recette.composants or {}) do
                    if not catalogue.EstVenduPartout(comp.objet) then
                        requis[comp.objet] = (requis[comp.objet] or 0) + comp.quantite * etape.fois
                    end
                end
            end
            -- Ce qu'on fabrique soi-meme (silex a aiguiser, fait de pierre) :
            -- seule la part deja en stock compte pour lui ; le reste devient
            -- ses propres composants, a reunir.
            local inter = plan.intermediaires or {}
            if next(inter) then
                local producteurs = {}
                for _, r in pairs(catalogue.Toutes and catalogue.Toutes() or {}) do
                    if type(r) == "table" and r.objetProduit and inter[r.objetProduit] and catalogue.EstApprise(r.id) then
                        producteurs[r.objetProduit] = r
                    end
                end
                for objet, fois in pairs(inter) do
                    local r = producteurs[objet]
                    if r then
                        local fabriques = fois * math.max(1, tonumber(r.quantiteMin) or 1)
                        requis[objet] = math.max(0, (requis[objet] or 0) - fabriques)
                        for _, c in ipairs(r.composants or {}) do
                            if not catalogue.EstVenduPartout(c.objet) then
                                requis[c.objet] = (requis[c.objet] or 0) + c.quantite * fois
                            end
                        end
                    end
                end
            end
            -- Ce qui s'achete chez un marchand (fioles, fils...) compte aussi :
            -- il faut l'avoir, meme sans le recolter.
            local manques = {}
            for objet, n in pairs(plan.manques or {}) do manques[objet] = n end
            for objet, n in pairs(plan.achats or {}) do
                requis[objet] = (requis[objet] or 0) + n
                -- Ce qui se vend partout ne se fait pas envoyer par un autre
                -- personnage : seul ce que j'ai moi-meme compte (sacs, banque,
                -- courrier), comme l'etape « Acheter chez un marchand ».
                local sacs, banque, courrier = NS.inventaire.SacsEtBanque(fiche, objet)
                local miens = (sacs or 0) + (banque or 0) + (courrier or 0)
                manques[objet] = (manques[objet] or 0) + math.max(0, n - miens)
            end
            local total, manque = 0, 0
            for objet, n in pairs(requis) do
                total = total + n
                manque = manque + math.min(n, manques[objet] or 0)
            end
            local pct
            if sien.rang >= vise then pct = 1
            elseif total > 0 then pct = (total - manque) / total
            else pct = 0 end
            local fige = plan.fige
            table.insert(liste, { cle = "prog" .. cle .. ":" .. vise, ligne = ligne, vise = vise, nom = (plan.probable and sien.rang < vise)
                    and (nom .. " : " .. (NS.ICONE_CHANCE or "") .. string.format(L.GUIDE_TARGET_ONE or "rang %d", vise))
                    or string.format(L.GOAL_PROG, nom, vise), genre = "progression",
                planId = type(fige) == "table" and (tostring(fige.creeLe) .. ":" .. tostring(fige.rangDepart)) or nil,
                detail = string.format(L.GOAL_PROG_DETAIL, sien.rang, vise), pct = pct, atteint = sien.rang >= vise,
                matieres = Matieres(requis, manques), achats = plan.achats,
                -- Recettes a apprendre en chemin (une seule fois chacune). Elles
                -- sont retenues pour l'objectif : une fois apprises, elles
                -- restent affichees, en vert, jusqu'au rang vise.
                aApprendre = (function()
                    local trouvees, vus = {}, {}
                    -- Sans recette nouvelle, le rang vise n'est pas atteint :
                    -- le meme calcul, recettes a apprendre comprises, dit lesquelles.
                    local source = plan
                    if sien.rang < vise and (plan.atteint or sien.rang) < vise then
                        -- Le meme plan fige, recettes a apprendre comprises
                        -- (calcule une fois, pas a chaque affichage).
                        local ok, segs = pcall(catalogue.PlansVises, fiche, cle, sien.rang, sien.rangMax, { vise }, true)
                        if ok and segs and segs[1] then source = segs[1].plan end
                    end
                    local rangsRequis = {}
                    for _, etape in ipairs(source.etapes or {}) do
                        local r = etape.apprendre and etape.recette
                        if r and r.id and not vus[r.id] then
                            vus[r.id] = true
                            rangsRequis[r.id] = tonumber(etape.rangRequis) or tonumber(etape.de)
                            table.insert(trouvees, r)
                        end
                    end
                    local g = NS.base.ReglagesGeneraux()
                    g.aApprendre = type(g.aApprendre) == "table" and g.aApprendre or {}
                    local cleM = tostring(fiche.cle) .. ":" .. tostring(cle) .. ":" .. tostring(vise)
                    if sien.rang >= vise then g.aApprendre[cleM] = nil return {} end
                    local memo = type(g.aApprendre[cleM]) == "table" and g.aApprendre[cleM] or {}
                    for _, r in ipairs(trouvees) do
                        memo[tostring(r.id)] = { nom = r.nom or tostring(r.id), rang = rangsRequis[r.id] }
                    end
                    g.aApprendre[cleM] = next(memo) and memo or nil
                    local t = {}
                    for id, m in pairs(memo) do
                        local r = catalogue.Toutes()[id]
                        local nom = type(m) == "table" and m.nom or tostring(m)
                        local rang = type(m) == "table" and tonumber(m.rang) or (r and catalogue.RangRequis and catalogue.RangRequis(r)) or nil
                        table.insert(t, { id = id, nom = nom, recette = r, appris = catalogue.EstApprise(id),
                            rang = rang, plusTard = rang and sien.rang < rang or false })
                    end
                    table.sort(t, function(x, y2)
                        if x.appris ~= y2.appris then return not x.appris end
                        if (x.rang or 0) ~= (y2.rang or 0) then return (x.rang or 0) < (y2.rang or 0) end
                        return tostring(x.nom) < tostring(y2.nom)
                    end)
                    return t
                end)(),
                -- Les recettes du plan, dans l'ordre : le bouton Creer les lance.
                lignes = (function()
                    local t = {}
                    for _, etape in ipairs(plan.etapes or {}) do
                        if etape.recette and etape.recette.id and not etape.apprendre and (etape.fois or 0) > 0 then
                            table.insert(t, { recette = etape.recette.id, quantite = etape.fois })
                        end
                    end
                    return t
                end)() })
                -- Une recette a apprendre maintenant, ni apprise ni en main :
                -- tout n'est pas faisable, le pourcentage ne dit jamais 100.
                local o = liste[#liste]
                local aPrendre = 0
                for _, a in ipairs(o.aApprendre or {}) do
                    if not a.appris and not a.plusTard then aPrendre = aPrendre + 1 end
                end
                if aPrendre > 0 and not o.atteint then
                    o.pct = math.min(o.pct or 0, 0.9) * (1 / (1 + 0.1 * (aPrendre - 1)))
                    o.recetteManquante = true
                end
            end
        end
    end
end

-- Proposition d'un autre plan : une petite fenetre, deux choix. Une fois
-- par plan propose et par session ; « Garder mon plan » ne la fait plus
-- revenir pour ce plan-la.
local proposes, fenetrePlan = {}, nil
local function ResumeDuPlan(plan)
    local fois, manque = 0, 0
    for _, e in ipairs(plan and plan.etapes or {}) do if not e.apprendre then fois = fois + (e.fois or 0) end end
    for _, n in pairs(plan and plan.manques or {}) do manque = manque + n end
    return fois, manque
end
function suivi.ProposerPlan(fiche, cle, nomMetier, vise, actuel, autre)
    local L = NS.L
    if InCombatLockdown and InCombatLockdown() then return end
    local sig = NS.recettes.SignatureDuPlan(autre)
    local fige = NS.recettes.PlanFige(fiche, cle, vise)
    if not fige or (fige.refus and fige.refus[sig]) then return end
    local k = tostring(fiche.cle) .. ":" .. tostring(cle) .. ":" .. tostring(vise) .. ":" .. sig
    if proposes[k] then return end
    proposes[k] = true
    if not fenetrePlan then
        local f = NS.charte.Fenetre("CraftCoreNouveauPlan", 400, 200, { portrait = false, strate = "DIALOG" })
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        if f.titre then f.titre:SetText("CraftCore") end
        f.textes = {}
        for i = 1, 5 do
            local t = f:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
            t:SetJustifyH("LEFT")
            t:SetWordWrap(false)
            t:SetWidth(364)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -40 - (i - 1) * 20 - (i > 1 and 4 or 0))
            f.textes[i] = t
        end
        f.garder = NS.charte.BoutonDePied(f, L.PLAN_KEEP, 150)
        f.changer = NS.charte.BoutonDePied(f, L.PLAN_SWITCH, 150, f.garder)
        f:SetHeight(40 + 5 * 20 + 48)
        table.insert(UISpecialFrames, "CraftCoreNouveauPlan")
        do local S = NS.suite or _G.CoreSuite if S and S.ToucheDEntree then S.ToucheDEntree(f, "CraftCoreNouveauPlan") end end
        fenetrePlan = f
    end
    local f = fenetrePlan
    local foisA, manqueA = ResumeDuPlan(actuel)
    local foisN, manqueN = ResumeDuPlan(autre)
    local function Detail(fois, manque, plan)
        local t = string.format(L.PLAN_CRAFTS, fois)
        t = t .. "  |cffb3b3b3" .. (manque > 0 and string.format(L.PLAN_TO_GATHER, manque) or L.PLAN_ALL_THERE) .. "|r"
        if plan and plan.estime then t = t .. "  |cffb3b3b3" .. L.PLAN_LUCK .. "|r" end
        return t
    end
    f.textes[1]:SetText(L.PLAN_OTHER_TITLE)
    f.textes[2]:SetText(string.format(L.GOAL_PROG, nomMetier or "?", vise))
    f.textes[3]:SetText(L.PLAN_CURRENT .. " : " .. Detail(foisA, manqueA, actuel))
    f.textes[4]:SetText(L.PLAN_NEW .. " : " .. Detail(foisN, manqueN, autre))
    f.textes[5]:SetText("|cffb3b3b3" .. L.PLAN_CHOICE_NOTE .. "|r")
    -- Deux boutons, au milieu du pied.
    local total = f.garder:GetWidth() + 8 + f.changer:GetWidth()
    f.changer:ClearAllPoints()
    f.changer:SetPoint("LEFT", f.pied, "CENTER", -total / 2, 0)
    f.garder:ClearAllPoints()
    f.garder:SetPoint("LEFT", f.changer, "RIGHT", 8, 0)
    f.changer:SetScript("OnClick", function()
        NS.recettes.FigerPlan(fiche, cle, vise, autre, (NS.recettes.PlanFige(fiche, cle, vise) or {}).stock)
        f:Hide()
        if suivi.Dessiner then pcall(suivi.Dessiner) end
        if NS.ecran and NS.ecran.Actualiser then pcall(NS.ecran.Actualiser) end
    end)
    f.garder:SetScript("OnClick", function()
        local p = NS.recettes.PlanFige(fiche, cle, vise)
        if p then p.refus = type(p.refus) == "table" and p.refus or {} p.refus[sig] = true end
        f:Hide()
    end)
    f:Show()
end

-- Projets en cours : ce qu'il faut recolter au bout de la chaine.
local function ObjectifsDeProjets(liste)
    local L = NS.L
    local catalogue = CraftCoreDB and CraftCoreDB.recettes
    if type(catalogue) ~= "table" then return end
    -- Les fabrications rapides d'abord, comme dans Mes fabrications, puis les
    -- projets suivis.
    local blocs = { { id = "rapides", rapides = true } }
    for _, projet in ipairs(NS.projets.Tous(false) or {}) do table.insert(blocs, projet) end
    -- Les commandes (demandees par un autre personnage) : une meme
    -- fabrication demandee par plusieurs personnages n'en fait qu'une, aux
    -- quantites additionnees, avec la liste de ceux pour qui on la fait.
    local moiCle = NS.ClePersonnage and NS.ClePersonnage()
    local function DemandeurDe(projet)
        if projet.rapides then return nil end
        -- Commande d'un joueur du groupe : son nom, sans le royaume.
        if projet.pourJoueur then return projet.pourJoueur end
        if projet.commande ~= nil then
            local c = NS.commandes and NS.commandes.Par and NS.commandes.Par(projet.commande)
            return (c and c.demandeur) or "?"
        end
        if projet.pour and projet.pour ~= moiCle then return projet.pour end
        return nil
    end
    local rendus, fusions = {}, {}
    for _, projet in ipairs(blocs) do
      if not projet.horsSuivi then
        local lignesP = {}
        for _, entree in ipairs(NS.projets.Contenu(projet.id) or {}) do
            table.insert(lignesP, { recette = tonumber(entree.recette) or entree.recette,
                quantite = tonumber(entree.quantite) or 1 })
        end
        local demandeur = #lignesP > 0 and DemandeurDe(projet)
        if demandeur then
            local cles = {}
            for _, l in ipairs(lignesP) do table.insert(cles, tostring(l.recette)) end
            table.sort(cles)
            local k = table.concat(cles, ",")
            local f = fusions[k]
            if f then
                for _, l in ipairs(lignesP) do
                    for _, fl in ipairs(f.lignes) do
                        if tostring(fl.recette) == tostring(l.recette) then fl.quantite = fl.quantite + l.quantite end
                    end
                end
                local deja = false
                for _, p in ipairs(f.pour) do if p == demandeur then deja = true end end
                if not deja then table.insert(f.pour, demandeur) end
            else
                f = { projet = projet, lignes = lignesP, pour = { demandeur } }
                fusions[k] = f
                table.insert(rendus, f)
            end
        else
            table.insert(rendus, { projet = projet, lignes = lignesP })
        end
      end
    end
    for _, e in ipairs(rendus) do
      local projet, lignes = e.projet, e.lignes
      do
        if #lignes > 0 then
            -- Besoin complet (sans rien en stock), puis ce qui manque vraiment.
            local _, requis = NS.moteur.DecomposerPlusieurs(catalogue, {}, lignes, EstApprise)
            local arbres, manques = NS.moteur.DecomposerPlusieurs(catalogue, NS.projets.StocksDuCompte(), lignes, EstApprise)
            local pct = NS.moteur.Couverture(arbres) or 0
            -- Le pourcentage dit ce qui est reuni, comme les comptes des
            -- matieres (ce qui reste a fabriquer en route n'en fait pas partie).
            local total, reuni = 0, 0
            for objet, n in pairs(requis or {}) do
                if n > 0 then
                    total = total + n
                    reuni = reuni + (n - math.max(0, math.min(n, (manques or {})[objet] or 0)))
                end
            end
            if total > 0 then pct = reuni / total end
            -- Ce qu'il y aura a fabriquer une fois tout reuni.
            local fabriquer = {}
            for _, l in ipairs(lignes) do
                local r = catalogue[l.recette] or catalogue[tostring(l.recette)]
                local nomR = type(r) == "table" and (r.nom or r.name)
                if nomR and #fabriquer < 3 then table.insert(fabriquer, nomR) end
            end
            local nomBloc = projet.rapides and L.NAV_QUICK or NS.projets.NomDe(projet)
            -- Projet tire d'un plan de progression : dans les progressions,
            -- sous son nom seul.
            local deProg = not projet.rapides and NS.projets.EstDeProgression(projet)
            local commande = e.pour ~= nil
            if commande then deProg = false end
            -- Pour qui : les noms, a la couleur de leur classe.
            local pourQui
            if commande then
                local noms = {}
                for _, cleP in ipairs(e.pour) do
                    local nom = NS.groupe and tostring(cleP):find(" %- ") == nil and NS.groupe.NomSeul(cleP) or NS.inventaire.NomCourt(cleP)
                    local fiche
                    for _, f in ipairs(NS.base.TousLesPersonnages()) do if f.cle == cleP then fiche = f end end
                    local jeton = type(fiche) == "table" and fiche.jetonClasse
                    local c = jeton and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[jeton]
                    if c and c.colorStr then nom = "|c" .. c.colorStr .. nom .. "|r"
                    elseif c then nom = string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, nom) end
                    table.insert(noms, nom)
                end
                pourQui = string.format(L.TRACK_ORDER_FOR, table.concat(noms, ", "))
            end
            table.insert(liste, { groupe = deProg and "progression" or "projets", commande = commande or nil, pourQui = pourQui,
                ligneMetier = deProg and tonumber(projet.progression) or nil,
                cle = commande and ("commande" .. table.concat((function() local t = {} for _, l in ipairs(lignes) do table.insert(t, tostring(l.recette)) end table.sort(t) return t end)(), ",")) or ("projet" .. tostring(projet.id)),
                genre = "projet", rapides = projet.rapides,
                titreAnnonce = nomBloc, fabriquer = fabriquer, nLignes = #lignes, lignes = lignes,
                nom = (projet.rapides or deProg or commande) and nomBloc or string.format(L.GOAL_PROJECT, nomBloc), pct = pct, atteint = pct >= 1,
                matieres = Matieres(requis or {}, manques or {}) })
        end
      end
    end
end

-- Rangs vises du personnage affiche dans la fenetre (page Mes progressions).
function suivi.RangsVises()
    local liste = {}
    local ok, souci = pcall(NS.base.AvecPersonnage, NS.base.CleAffichee(), function()
        ObjectifsDeProgression(liste)
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("rangs vises", souci) end
    table.sort(liste, function(a, b) return tostring(a.nom) < tostring(b.nom) end)
    return liste
end

function suivi.Objectifs()
    -- Onglet Fabrications : fabrications rapides et projets nommes. Onglet
    -- Progressions : rangs vises, puis projets tires d'un plan.
    local liste = {}
    local cle = NS.ClePersonnage and NS.ClePersonnage()
    local ok, souci = pcall(NS.base.AvecPersonnage, cle, function()
        ObjectifsDeProjets(liste)
        ObjectifsDeCaisses(liste, cle)
        local rangs = {}
        ObjectifsDeProgression(rangs)
        -- Rang atteint : l'objectif quitte le suivi (felicitations a la place).
        for _, o in ipairs(rangs) do
            if not o.atteint then o.groupe = "progression" table.insert(liste, o) end
        end
        -- Les rangs vises avant les projets de progression ; les commandes
        -- pour mes autres personnages apres mes propres fabrications.
        local avant, apres = {}, {}
        for _, o in ipairs(liste) do
            if (o.groupe == "progression" and o.genre == "projet") or o.commande then table.insert(apres, o) else table.insert(avant, o) end
        end
        for k in pairs(liste) do liste[k] = nil end
        for _, o in ipairs(avant) do table.insert(liste, o) end
        for _, o in ipairs(apres) do table.insert(liste, o) end
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("objectifs de recolte", souci) end
    return liste
end

-- La barre d'avancement de QuestCore : texture des competences du jeu, fine
-- bordure d'infobulle aux coins arrondis, pourcentage dedans.
local function Barre(parent)
    local okF, b = pcall(CreateFrame, "StatusBar", nil, parent, "BackdropTemplate")
    b = okF and b or CreateFrame("StatusBar", nil, parent)
    b.sansEncre = true
    b:SetSize(90, 10)
    b:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    b:SetMinMaxValues(0, 1)
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetColorTexture(0, 0, 0, 0.65)
    local okB, bordure = pcall(CreateFrame, "Frame", nil, b, "BackdropTemplate")
    bordure = okB and bordure or CreateFrame("Frame", nil, b)
    bordure:SetPoint("TOPLEFT", -2, 2)
    bordure:SetPoint("BOTTOMRIGHT", 2, -2)
    if bordure.SetBackdrop then
        bordure:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 5 })
        bordure:SetBackdropBorderColor(0.8, 0.65, 0.35, 1)
    end
    bordure:SetFrameLevel(b:GetFrameLevel() + 2)
    b.texte = bordure:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.texte:SetPoint("CENTER", b, "CENTER", 0, 0)
    local fichier, _, drapeaux = b.texte:GetFont()
    if fichier then b.texte:SetFont(NS.Police(fichier), 9, drapeaux) end
    b.texte:SetShadowOffset(1, -1)
    return b
end

local function Vue()
    local g = NS.base.ReglagesGeneraux()
    if g.vueRecolte == "progressions" or g.vueRecolte == "commandes" or g.vueRecolte == "caisses" then return g.vueRecolte end
    return "fabrications"
end
suivi.Vue = Vue
-- L'objectif de recolte de l'onglet affiche (bouton Guider du bas).
function suivi.ParamsOnglet() return { onglet = Vue() } end

-- Memes polices et memes tailles que le suivi des quetes de QuestCore :
-- titres un cran au-dessus, lignes a la taille du suivi.
-- La taille du suivi des quetes (reglage de QuestCore, 12 par defaut).
local TAILLE_LIGNE = 12
local function TailleDesQuetes()
    local d = _G.QuestCoreDB
    local s = type(d) == "table" and type(d.reglages) == "table" and type(d.reglages.general) == "table"
        and d.reglages.general.suivi
    return tonumber(type(s) == "table" and s.taille) or 12
end
local function Police(nom, repli) return _G[nom] and nom or repli end
local function Taille(fs, taille)
    local fichier, _, drapeaux = fs:GetFont()
    if fichier then fs:SetFont(NS.Police and NS.Police(fichier) or fichier, taille, drapeaux) end
end
local HAUT_ONGLETS = 38

-- Le suivi est tenu par son coin BAS gauche : quand il grandit (onglet
-- Session, objectifs deplies), il s'ouvre vers le haut et son bas reste ou
-- on l'a pose.
local function TenirParLeBas(cadre)
    local gauche, bas = cadre:GetLeft(), cadre:GetBottom()
    if not gauche or not bas then return end
    cadre:ClearAllPoints()
    cadre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", gauche, bas)
    NS.base.ReglagesGeneraux().placeSuivi = { point = "BOTTOMLEFT", relatif = "BOTTOMLEFT", x = gauche, y = bas }
end

local function Placer(cadre)
    cadre:ClearAllPoints()
    local place = NS.base.ReglagesGeneraux().placeSuivi
    if type(place) == "table" and place.point then
        cadre:SetPoint(place.point, UIParent, place.relatif or place.point, place.x or 0, place.y or 0)
        -- Ancienne position (centre, haut...) : convertie une fois par le bas.
        if place.point ~= "BOTTOMLEFT" then pcall(TenirParLeBas, cadre) end
    else
        cadre:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function Construire()
    local cadre = NS.charte.Fenetre("CraftCoreSuivi", LARGEUR_SUIVI, 120,
        { portrait = false, strate = "MEDIUM", sansPied = true })
    if cadre.titre then cadre.titre:SetText(NS.L.TRACK_TITLE) end

    -- Reglages de l'add-on, en haut a gauche : un clic les ouvre.
    local reglages = CreateFrame("Button", nil, cadre)
    reglages:SetSize(14, 14)
    reglages:SetPoint("TOPLEFT", cadre, "TOPLEFT", 19, -5)
    -- Au niveau du bouton de fermeture, au-dessus du cadre du jeu (sinon le
    -- bord du cadre le recouvre des que la fenetre est pleinement opaque).
    local fermer = cadre.fermer or cadre.CloseButton
    reglages:SetFrameLevel(math.max(cadre:GetFrameLevel() + 20, (fermer and fermer:GetFrameLevel() or 0) + 2))
    reglages:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    reglages:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    reglages:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(NS.L.OPEN_SETTINGS, 1, 1, 1)
        GameTooltip:Show()
    end)
    reglages:SetScript("OnLeave", function() GameTooltip:Hide() end)
    reglages:SetScript("OnClick", function() if NS.ecran and NS.ecran.Montrer then NS.ecran.Montrer("reglages") end end)
    cadre.boutonReglages = reglages
    cadre:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TenirParLeBas(self)
        suivi.Dessiner()
    end)
    cadre.fermer:SetScript("OnClick", function() cadre:Hide() end)
    -- Le bouton Assembler (securise, pose a part) part avec le suivi.
    cadre:HookScript("OnHide", function() if suivi.CacherAssembleur then suivi.CacherAssembleur() end end)
    cadre.textes, cadre.icones, cadre.barres, cadre.boutons = {}, {}, {}, {}

    -- Replier / deplier tout le suivi, comme celui des quetes de QuestCore.
    local niveauTitre = (cadre.fermer:GetFrameLevel() or cadre:GetFrameLevel()) + 1
    local replier = CreateFrame("Button", nil, cadre)
    replier:SetFrameLevel(niveauTitre)
    replier:SetSize(16, 16)
    replier:SetPoint("RIGHT", cadre.fermer, "LEFT", -2, 0)
    replier:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    replier:SetScript("OnClick", function()
        local g = NS.base.ReglagesGeneraux()
        g.suiviReplie = not g.suiviReplie or nil
        suivi.Dessiner()
    end)
    cadre.replier = replier
    cadre.resume = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cadre.resume:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -2)
    cadre.resume:SetPoint("RIGHT", cadre.zone, "RIGHT", 0, 0)
    cadre.resume:SetJustifyH("LEFT")
    cadre.resume:SetWordWrap(false)
    cadre.resume:Hide()
    -- Ancre : ne bouge qu'en mode Edition du jeu.
    cadre:SetScript("OnDragStart", function(self)
        if NS.suite and NS.suite.Libre and not NS.suite.Libre("CraftCoreSuivi") then return end
        self:StartMoving()
    end)
    if NS.suite and NS.suite.Ancrable then
        pcall(NS.suite.Ancrable, "CraftCoreSuivi", cadre, NS.L.TRACK_EDIT_LABEL)
    end

    -- Onglets, comme ceux du suivi des quetes de QuestCore : des boutons
    -- ronds, l'icone du jeu et un compte a cote, le nom au survol, un filet
    -- dessous. Fabrications (mes projets), commandes (pour mes autres
    -- personnages), progressions (rangs vises).
    cadre.vues = {}
    local largeurZone = LARGEUR_SUIVI - 2 * NS.charte.MARGE - 10
    local pas = math.floor(largeurZone / 4)
    for rang, v in ipairs({
        { "fabrications", NS.L.TRACK_TAB_CRAFTS, "Interface\\Icons\\Trade_BlackSmithing" },
        { "commandes", NS.L.TRACK_TAB_ORDERS, "Interface\\Icons\\INV_Letter_15" },
        { "progressions", NS.L.TRACK_TAB_PROGRESSIONS, "Interface\\Icons\\INV_Misc_Book_09" },
        { "caisses", NS.L.TRACK_TAB_CRATES, "Interface\\Icons\\INV_Crate_02" } }) do
        local b = CreateFrame("Button", nil, cadre)
        b:SetSize(24, 24)
        b:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", (rang - 1) * pas + 2, 0)
        b.fond = b:CreateTexture(nil, "BACKGROUND")
        b.fond:SetSize(19, 19)
        b.fond:SetPoint("CENTER")
        b.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        b.image = b:CreateTexture(nil, "ARTWORK")
        b.image:SetPoint("CENTER")
        b.image:SetSize(16, 16)
        b.image:SetTexture(v[3])
        if b.image.SetMask then pcall(b.image.SetMask, b.image, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        b.anneau = b:CreateTexture(nil, "OVERLAY")
        b.anneau:SetSize(41, 41)
        b.anneau:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        b.compte = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.compte:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.nom = v[2]
        -- Onglet pour la manette (LB / RB quand on pilote le suivi).
        b.ongletPilote = true
        function b.Compter(self, n) self.compte:SetText(tostring(n or 0)) end
        function b.Choisir(self, oui)
            self.choisi = oui and true or nil
            self.image:SetDesaturated(not oui)
            self.image:SetAlpha(oui and 1 or 0.55)
            self.anneau:SetDesaturated(not oui)
            self.compte:SetTextColor(oui and 1 or 0.6, oui and 0.82 or 0.6, oui and 0 or 0.6)
        end
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.nom, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local cle = v[1]
        b:SetScript("OnClick", function()
            NS.base.ReglagesGeneraux().vueRecolte = cle
            suivi.Dessiner()
        end)
        cadre.vues[cle] = b
    end
    local filetHaut = cadre:CreateTexture(nil, "ARTWORK")
    filetHaut:SetHeight(1)
    filetHaut:SetPoint("TOPLEFT", cadre.zone, "TOPLEFT", 0, -HAUT_ONGLETS + 6)
    filetHaut:SetPoint("TOPRIGHT", cadre.zone, "TOPRIGHT", 0, -HAUT_ONGLETS + 6)
    PeindreFilet(filetHaut, 0.8, 0.65, 0.35, 0.35)
    cadre.filetHaut = filetHaut

    -- Tout ouvrir / tout fermer les objectifs de l'onglet.
    local tout = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    tout:SetSize(110, 20)
    tout:SetPoint("BOTTOMLEFT", cadre.zone, "BOTTOMLEFT", 0, 0)
    tout:SetScript("OnClick", function(self) suivi.ToutOuvrir(self.ouvrir) end)
    cadre.tout = tout

    -- Onglet Objectifs : guider vers le lieu connu le plus proche d'une
    -- matiere qui manque encore (meme place que le bouton de la session).
    local guider = CreateFrame("Button", nil, cadre, "UIPanelButtonTemplate")
    guider:SetSize(110, 20)
    guider:SetPoint("BOTTOMRIGHT", cadre.zone, "BOTTOMRIGHT", 0, 0)
    guider:SetScript("OnClick", function() NS.guidage.Basculer(suivi.ParamsOnglet()) end)
    guider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(NS.L.GUIDE_GOALS_HELP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    guider:Hide()
    cadre.guider = guider

    -- Presque transparente quand on court, nette a l'arret.
    local attente = 0
    cadre:SetScript("OnUpdate", function(self, ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.2
        local bouge = NS.Lecture("IsPlayerMoving")
        local ok, enMouvement = false, false
        if bouge then ok, enMouvement = pcall(bouge) end
        local survol = self.IsMouseOver and self:IsMouseOver()
        self:SetAlpha((ok and enMouvement and not survol) and ALPHA_EN_COURSE or 1)
    end)
    Placer(cadre)
    cadre:Hide()
    return cadre
end

local function Texte(rang, police)
    local t = cadreSuivi.textes[rang]
    if not t then
        t = cadreSuivi:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        cadreSuivi.textes[rang] = t
    end
    t:SetFontObject(police or "GameFontHighlightSmall")
    -- Un texte est reutilise d'un tour a l'autre (nom, puis compte) : son
    -- alignement repart a gauche, sinon un nom herite du calage a droite.
    t:SetJustifyH("LEFT")
    t:SetWordWrap(true)
    t:Show()
    return t
end

-- Objectifs ouverts (deplies), par cle.
local function Ouverts()
    local g = NS.base.ReglagesGeneraux()
    if type(g.objectifsOuverts) ~= "table" then g.objectifsOuverts = {} end
    return g.objectifsOuverts
end

local function OngletDe(o)
    if o.genre == "caisse" then return "caisses" end
    if o.groupe == "progression" then return "progressions" end
    if o.commande then return "commandes" end
    return "fabrications"
end

local function DeLOnglet(objectifs, vue)
    local rendu = {}
    for _, o in ipairs(objectifs) do
        if OngletDe(o) == vue then table.insert(rendu, o) end
    end
    return rendu
end
suivi.DeLOnglet = DeLOnglet

-- Tout ouvrir (oui) ou tout fermer les objectifs de l'onglet affiche.
function suivi.ToutOuvrir(oui)
    local ouverts = Ouverts()
    for _, o in ipairs(DeLOnglet(suivi.Objectifs(), Vue())) do ouverts[o.cle] = oui and true or nil end
    suivi.Dessiner()
end

-- Recette qui fabrique un objet (apprise), cherchee une fois par dessin.
local producteurs
local function Producteur(objet)
    if not producteurs then
        producteurs = {}
        for _, rec in pairs(CraftCoreDB and CraftCoreDB.recettes or {}) do
            if type(rec) == "table" and rec.objetProduit and NS.recettes.EstApprise and NS.recettes.EstApprise(rec.id) then
                producteurs[rec.objetProduit] = producteurs[rec.objetProduit] or rec
            end
        end
    end
    return producteurs[objet]
end

-- Les etapes de fabrication d'un projet, dans l'ordre : d'abord ce qu'il
-- faut fabriquer en route (barres, catalyseurs...), puis l'objet lui-meme.
-- Chaque etape : recette, objet, combien de fois, faite ou non.
-- Combien on en a sur soi, lu en direct dans le jeu (le releve des sacs a
-- une seconde de retard).
local function SurSoi(objet)
    local compter = NS.Lecture("C_Item.GetItemCount", "GetItemCount")
    local n = compter and NS.Appeler(compter, objet, false) or nil
    if type(n) == "number" then return n end
    return NS.inventaire.DisponibleDansLesSacs(objet) or 0
end

local function EtapesDeFabrication(lignes)
    local etapes = {}
    local catalogue = CraftCoreDB and CraftCoreDB.recettes or {}
    for _, l in ipairs(lignes or {}) do
        local rec = catalogue[tostring(l.recette)] or catalogue[l.recette]
        if type(rec) == "table" then
            local quantite = l.quantite or 1
            for _, comp in ipairs(rec.composants or {}) do
                local sous = Producteur(comp.objet)
                if sous and sous ~= rec then
                    local besoin = comp.quantite * quantite
                    local avoir = SurSoi(comp.objet)
                    local parFois = math.max(1, tonumber(sous.quantiteMin) or 1)
                    table.insert(etapes, { recette = sous, objet = comp.objet, besoin = besoin, avoir = math.min(avoir, besoin),
                        fois = math.max(1, math.ceil(math.max(0, besoin - avoir) / parFois)), faite = avoir >= besoin })
                end
            end
            table.insert(etapes, { recette = rec, objet = rec.objetProduit, besoin = quantite, fois = quantite, faite = false, finale = true })
        end
    end
    return etapes
end

-- ---------------------------------------------------------------------------
-- Feuille de route d'un objectif.
--
-- Les etapes sont toujours tirees de l'etat reel du moment (sacs, courrier,
-- banque, envois en route, autres personnages), jamais de la memoire :
--   1 recolter ou trouver ce que personne n'a ;
--   2 relever mon courrier (ce qui y etait deja) ;
--   3 sortir de ma banque ;
--   4 connecter mes autres personnages, au plus rapide (jamais moi, jamais
--     une ancienne fiche a mon nom) ;
--   5 revenir relever le courrier, seulement si du courrier est en route ou
--     attendu (envoye par un autre personnage, ou une etape 4 a faire) ;
--   6 acheter (ce qui se vend chez tous les marchands) ;
--   7 fabriquer.
-- Les memes etapes au survol, dans Mon atelier et dans la consigne.
-- ---------------------------------------------------------------------------
local PHASES = { recolte = 1, courrier = 2, banque = 3, perso = 4, retour = 5, achats = 6, fab = 7 }
local function PhaseDe(cle)
    return PHASES[string.match(tostring(cle or ""), "^([^:]+)") or ""] or 8
end

-- Le personnage `cle` est-il `moi`, ou une ancienne fiche a mon nom (royaume
-- vide ou provisoire, d'avant la correction du royaume) ? On ne se connecte
-- jamais sur soi et on ne s'envoie jamais rien.
local function EstMoiOuFantome(cle, moi)
    if not (cle and moi) then return false end
    if cle == moi then return true end
    return NS.inventaire.NomCourt(cle) == NS.inventaire.NomCourt(moi)
end
suivi.EstMoiOuFantome = EstMoiOuFantome

local COUT_LIEU = { ville = 1, auberge = 1.5, campagne = 3 }
-- Un banquier attend toujours en ville, a cote de sa banque : il passe
-- avant les autres personnages.
local function Cout(fiche)
    if NS.banquiers and NS.banquiers.Est(fiche.cle) then return 0.8 end
    local l = type(fiche) == "table" and type(fiche.lieu) == "table" and fiche.lieu
    return COUT_LIEU[l and l.genre or "campagne"] or 3
end
local function LieuDe(fiche)
    local l = type(fiche) == "table" and fiche.lieu
    if type(l) ~= "table" then return nil end
    return l
end
local function TexteLieu(l)
    local L = NS.L
    if not l then return L.ROUTE_WHERE_UNKNOWN end
    local zone = l.zone or "?"
    if l.genre == "ville" then return string.format(L.ROUTE_WHERE_CITY, zone) end
    if l.genre == "auberge" then return string.format(L.ROUTE_WHERE_INN, zone) end
    return string.format(L.ROUTE_WHERE_FIELD, zone)
end

-- Mes autres personnages qui peuvent aider : meme camp que moi, jamais moi
-- ni une fiche a mon nom.
local function Autres(moi)
    local liste = {}
    for _, f in ipairs(NS.base.TousLesPersonnages()) do
        if type(f) == "table" and f.cle and not EstMoiOuFantome(f.cle, moi.cle)
            and ((not moi.faction) or (not f.faction) or f.faction == moi.faction) then
            table.insert(liste, f)
        end
    end
    -- Ordre stable : le meme calcul donne toujours les memes etapes.
    table.sort(liste, function(a, b) return tostring(a.cle) < tostring(b.cle) end)
    return liste
end

-- Ajoute n objets a une liste { {objet, n} } en gardant un seul exemplaire
-- par objet.
local function Ajouter(liste, objet, n)
    if not n or n <= 0 then return end
    for _, x in ipairs(liste) do if x.objet == objet then x.n = x.n + n return end end
    table.insert(liste, { objet = objet, n = n })
end

function suivi.FeuilleDeRoute(o)
    local L = NS.L
    local inv = NS.inventaire
    local cat = NS.recettes
    local moi = NS.base.Personnage()
    local etapes = {}
    if not (o and moi and not moi.temporaire) then return etapes end
    local nomMoi = inv.NomCourt(moi.cle)

    -- Ce qu'il faut avoir dans les sacs, matiere par matiere. Ce qui
    -- s'achete et n'est pas parmi les matieres compte aussi.
    local requis, ordre = {}, {}
    for _, m in ipairs(o.matieres or {}) do
        local n = tonumber(m.requis) or 0
        if m.objet and n > 0 and not requis[m.objet] then requis[m.objet] = n table.insert(ordre, m.objet) end
    end
    for objet, n in pairs(o.achats or {}) do
        n = tonumber(n) or 0
        if n > 0 and not requis[objet] then requis[objet] = n table.insert(ordre, objet) end
    end
    local function Achetable(objet)
        return (o.achats and o.achats[objet]) or (cat and cat.EstVenduPartout and cat.EstVenduPartout(objet)) or false
    end

    -- Mes propres sources d'abord : mon courrier (deja la, puis envoye par
    -- mes personnages), ma banque. `sacs` : ce que j'ai sur moi, en direct.
    local sacs, reste = {}, {}
    local monCourrier, attendu, maBanque = {}, {}, {}
    for _, objet in ipairs(ordre) do
        sacs[objet] = SurSoi(objet)
        local r = requis[objet] - sacs[objet]
        if r > 0 then
            local _, banque = inv.SacsEtBanque(moi, objet)
            local boite, enRoute = inv.CourrierEnDeux(moi, objet)
            local c = math.min(r, boite or 0)
            if c > 0 then Ajouter(monCourrier, objet, c) r = r - c end
            local a = math.min(r, enRoute or 0)
            if a > 0 then Ajouter(attendu, objet, a) r = r - a end
            local b = math.min(r, banque or 0)
            if b > 0 then Ajouter(maBanque, objet, b) r = r - b end
            if r > 0 then reste[objet] = r end
        end
    end

    -- Les autres personnages, au plus rapide (le plus couvert pour le moins
    -- de deplacement), jusqu'a ce que tout soit trouve. Ce qui s'achete
    -- partout ne vaut pas une connexion : il n'est pris que chez un
    -- personnage qu'on visite deja pour autre chose.
    local candidats = Autres(moi)
    local function Prise(f, achatsSeuls)
        local p, couvert = { courrier = {}, sacs = {}, banque = {} }, 0
        for _, objet in ipairs(ordre) do
            local r = reste[objet]
            if r and r > 0 and (Achetable(objet) and true or false) == (achatsSeuls and true or false) then
                local s, b, c = inv.SacsEtBanque(f, objet)
                local ds = math.min(r, s or 0)
                local dc = math.min(r - ds, c or 0)
                local db = math.min(r - ds - dc, b or 0)
                Ajouter(p.sacs, objet, ds)
                Ajouter(p.courrier, objet, dc)
                Ajouter(p.banque, objet, db)
                couvert = couvert + ds + dc + db
            end
        end
        return p, couvert
    end
    local function Retirer(p)
        for _, part in pairs(p) do
            for _, x in ipairs(part) do
                reste[x.objet] = reste[x.objet] - x.n
                if reste[x.objet] <= 0 then reste[x.objet] = nil end
            end
        end
    end
    local visites, vus = {}, {}
    while next(reste) do
        local meilleur, score, prise
        for _, f in ipairs(candidats) do
            if not vus[f.cle] then
                local p, couvert = Prise(f, false)
                local s = couvert / Cout(f)
                if couvert > 0 and (not score or s > score) then meilleur, score, prise = f, s, p end
            end
        end
        if not meilleur then break end
        vus[meilleur.cle] = true
        Retirer(prise)
        table.insert(visites, { fiche = meilleur, prise = prise })
    end
    -- Ce qui s'achete, chez ceux qu'on visite de toute facon.
    for _, v in ipairs(visites) do
        local p = Prise(v.fiche, true)
        Retirer(p)
        for nom, part in pairs(p) do for _, x in ipairs(part) do Ajouter(v.prise[nom], x.objet, x.n) end end
    end
    table.sort(visites, function(a, b)
        local ca, cb = Cout(a.fiche), Cout(b.fiche)
        if ca ~= cb then return ca < cb end
        return tostring(a.fiche.cle) < tostring(b.fiche.cle)
    end)

    -- Chaque etape : un titre, un lieu, des blocs (une action et ses
    -- objets), le guide, et sa cible : ce que les sacs contiendront une fois
    -- l'etape faite (sa preuve, voir suivi.Feuille).
    local function Etape(cle, qui, titre, lieu, blocs, guide, cible)
        local resume = {}
        for _, b in ipairs(blocs or {}) do
            local noms = {}
            for _, x in ipairs(b.objets or {}) do table.insert(noms, x.n .. " " .. inv.NomDObjet(x.objet)) end
            local liste = table.concat(noms, ", ")
            table.insert(resume, (b.action and liste ~= "") and (b.action .. " " .. liste) or ((b.action or "") .. liste))
        end
        table.insert(etapes, { cle = cle, phase = PhaseDe(cle), qui = qui, titre = titre, lieu = lieu, blocs = blocs or {}, guide = guide,
            cible = cible, texte = titre .. (lieu and (" (" .. lieu .. ")") or "") .. (#resume > 0 and (" : " .. table.concat(resume, " ; ")) or "") })
    end
    local function Cible(objets)
        local c = {}
        for _, x in ipairs(objets) do c[x.objet] = (c[x.objet] or sacs[x.objet] or SurSoi(x.objet)) + x.n end
        return c
    end

    -- 1. Ce que personne n'a : a recolter ou a trouver ; ce qui se vend
    -- partout s'achete (etape 6).
    local introuvables, achats = {}, {}
    for _, objet in ipairs(ordre) do
        if reste[objet] then
            if Achetable(objet) then Ajouter(achats, objet, reste[objet]) else Ajouter(introuvables, objet, reste[objet]) end
        end
    end
    if #introuvables > 0 then
        Etape("recolte", nil, L.ROUTE_T_GATHER, nil, { { objets = introuvables } },
            { recolte = { objectifs = { o.cle } } }, Cible(introuvables))
    end
    -- 2 et 3. Mon courrier, ma banque.
    if #monCourrier > 0 then
        Etape("courrier", nil, string.format(L.ROUTE_T_MAILBOX, nomMoi), nil,
            { { action = L.ROUTE_D_COLLECT, objets = monCourrier } }, { service = "courrier" }, Cible(monCourrier))
    end
    if #maBanque > 0 then
        Etape("banque", nil, string.format(L.ROUTE_T_BANK, nomMoi), nil,
            { { action = L.ROUTE_D_TAKE, objets = maBanque } }, { service = "banque" }, Cible(maBanque))
    end
    -- 4. Les visites : relever son courrier, sortir de sa banque, m'envoyer.
    for _, v in ipairs(visites) do
        local nom = inv.NomCourt(v.fiche.cle)
        if NS.banquiers and NS.banquiers.Est(v.fiche.cle) then nom = nom .. " (" .. L.ROUTE_BANKER .. ")" end
        local tout, blocs = {}, {}
        for _, part in ipairs({ v.prise.sacs, v.prise.courrier, v.prise.banque }) do
            for _, x in ipairs(part) do Ajouter(tout, x.objet, x.n) Ajouter(attendu, x.objet, x.n) end
        end
        if #v.prise.courrier > 0 then table.insert(blocs, { action = L.ROUTE_D_COLLECT, objets = v.prise.courrier }) end
        if #v.prise.banque > 0 then table.insert(blocs, { action = L.ROUTE_D_TAKE, objets = v.prise.banque }) end
        table.insert(blocs, { action = string.format(L.ROUTE_D_SEND, nomMoi), objets = tout })
        Etape("perso:" .. v.fiche.cle, v.fiche.cle, string.format(L.ROUTE_T_LOGIN, nom), TexteLieu(LieuDe(v.fiche)), blocs,
            #v.prise.banque > 0 and { service = "banque" } or { service = "courrier" })
    end
    -- 5. Revenir relever : seulement le courrier en route ou attendu.
    if #attendu > 0 then
        Etape("retour", nil, string.format(L.ROUTE_T_BACK, nomMoi), nil,
            { { action = L.ROUTE_D_COLLECT, objets = attendu } }, { service = "courrier" }, Cible(attendu))
    end
    -- 6. Acheter.
    if #achats > 0 then
        Etape("achats", nil, L.ROUTE_T_BUY, nil, { { objets = achats } }, { marchand = achats[1].objet }, Cible(achats))
    end
    -- 7. Les fabrications, dans l'ordre. Une fabrication en route est faite
    -- quand ses objets sont dans les sacs ; la derniere, quand l'objectif est
    -- atteint (il quitte alors le suivi).
    for _, e in ipairs(EtapesDeFabrication(o.lignes)) do
        if not e.faite and e.recette then
            Etape("fab:" .. tostring(e.objet), nil, L.ROUTE_T_CRAFT, nil,
                { { objets = { { objet = e.objet, n = e.fois or 1, fois = true } } } }, nil,
                (not e.finale) and { [e.objet] = e.besoin } or nil)
        end
    end
    return etapes
end

-- ---------------------------------------------------------------------------
-- Memoire des feuilles de route, par personnage et par objectif. Elle ne
-- cree jamais d'etape : elle sert a garder en vert, a sa place, une etape
-- vraiment accomplie, et aux autres personnages (consigne a leur connexion).
-- Une etape est faite seulement avec une preuve :
--   "sacs"   ses objets sont arrives dans mes sacs (sa cible est atteinte) ;
--   "envoi"  l'autre personnage a poste tout son envoi (suivi.EnvoiFait).
-- Une etape qui disparait du calcul sans preuve est simplement oubliee.
-- ---------------------------------------------------------------------------
local feuillesPropres
local function EnvoiDe(e)
    local blocs = type(e) == "table" and type(e.blocs) == "table" and e.blocs or {}
    return blocs[#blocs]
end
local function EnvoiCouvert(e)
    local envoi = EnvoiDe(e)
    if not (envoi and type(envoi.objets) == "table" and #envoi.objets > 0 and type(e.envoye) == "table") then return false end
    for _, x in ipairs(envoi.objets) do
        if (tonumber(e.envoye[x.objet]) or 0) < (tonumber(x.n) or 0) then return false end
    end
    return true
end
-- Remet d'aplomb, une fois par session, ce que d'anciennes versions ont
-- garde : etapes pour soi-meme ou une fiche au meme nom, etapes faites sans
-- preuve, phases d'avant.
local function NettoyerMemoire(F)
    for proprio, objectifs in pairs(F) do
        if type(objectifs) ~= "table" then
            F[proprio] = nil
        else
            for k, f in pairs(objectifs) do
                if type(f) ~= "table" or type(f.etapes) ~= "table" then
                    objectifs[k] = nil
                else
                    local garde = {}
                    for _, e in ipairs(f.etapes) do
                        if type(e) == "table" and e.cle and not (e.qui and EstMoiOuFantome(e.qui, proprio)) then
                            if e.faite and not e.preuve then
                                if e.qui and EnvoiCouvert(e) then e.preuve = "envoi" else e.faite = nil end
                            end
                            e.phase = PhaseDe(e.cle)
                            table.insert(garde, e)
                        end
                    end
                    f.etapes = garde
                end
            end
        end
    end
end
local function Feuilles()
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.feuilles = type(d.feuilles) == "table" and d.feuilles or {}
    if feuillesPropres ~= d.feuilles then
        NettoyerMemoire(d.feuilles)
        feuillesPropres = d.feuilles
    end
    return d.feuilles
end
local function CleObjectif(o) return tostring(o.cle or o.nom or "?") end

-- Preuve d'une de mes etapes disparue du calcul : tout ce qu'elle apportait
-- est dans mes sacs.
local function CibleAtteinte(e)
    if type(e.cible) ~= "table" or not next(e.cible) then return false end
    for objet, n in pairs(e.cible) do
        if SurSoi(objet) < (tonumber(n) or 0) then return false end
    end
    return true
end

-- Les etapes d'un objectif du personnage connecte, faites comprises.
function suivi.Feuille(o)
    local moi = NS.base.Personnage()
    local calcul = suivi.FeuilleDeRoute(o)
    if not moi or moi.temporaire then return calcul end
    local F = Feuilles()
    F[moi.cle] = type(F[moi.cle]) == "table" and F[moi.cle] or {}
    -- Les feuilles d'une ancienne fiche a mon nom sont perimees : c'est moi
    -- qui les tiens a jour maintenant.
    for proprio in pairs(F) do
        if proprio ~= moi.cle and EstMoiOuFantome(proprio, moi.cle) then F[proprio] = nil end
    end
    local cle = CleObjectif(o)
    local avant = F[moi.cle][cle]
    -- Rang vise : la memoire ne vaut que pour le meme plan fige (un nouveau
    -- plan repart d'une feuille propre, sans etapes d'un ancien plan).
    if type(avant) == "table" and o.planId and avant.planId ~= o.planId then avant = nil end
    local neuves = {}
    for _, e in ipairs(calcul) do neuves[e.cle] = e end
    local liste, vus = {}, {}
    for k, e in ipairs(type(avant) == "table" and type(avant.etapes) == "table" and avant.etapes or {}) do
        if type(e) == "table" and e.cle and not vus[e.cle] and not (e.qui and EstMoiOuFantome(e.qui, moi.cle)) then
            local n = neuves[e.cle]
            if n then
                -- Encore a faire d'apres l'etat reel : a sa place d'avant.
                n.rang = k
                table.insert(liste, n)
                vus[e.cle] = true
            elseif e.faite and e.preuve then
                e.rang = k
                table.insert(liste, e)
                vus[e.cle] = true
            elseif not e.qui and (CibleAtteinte(e) or (cle:sub(1, 4) == "prog" and e.cle ~= nil)) then
                -- Une etape d'un rang vise que le plan fige ne demande plus est
                -- faite : elle reste en vert a sa place, meme si une autre
                -- etape a depuis consomme ce qu'elle avait reuni.
                e.faite, e.preuve, e.rang = true, e.preuve or "sacs", k
                table.insert(liste, e)
                vus[e.cle] = true
            end
        end
    end
    for i, e in ipairs(calcul) do
        if not vus[e.cle] then e.rang = 1000 + i table.insert(liste, e) vus[e.cle] = true end
    end
    for _, e in ipairs(liste) do e.phase = PhaseDe(e.cle) end
    table.sort(liste, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return (a.rang or 0) < (b.rang or 0)
    end)
    -- Gardee pour les autres personnages (sans le guide).
    local garde = {}
    for _, e in ipairs(liste) do
        table.insert(garde, { cle = e.cle, phase = e.phase, qui = e.qui, titre = e.titre, lieu = e.lieu,
            blocs = e.blocs, faite = e.faite, preuve = e.preuve, cible = e.cible, envoye = e.envoye, texte = e.texte })
    end
    F[moi.cle][cle] = { nom = o.nom, etapes = garde, quand = NS.Appeler(_G.time) or 0, planId = o.planId }
    return liste
end

-- Un objectif disparu (fait ou retire) : sa feuille s'efface.
function suivi.NettoyerFeuilles(objectifs)
    local moi = NS.base.Personnage()
    local F = Feuilles()
    if not (moi and type(F[moi.cle]) == "table") then return end
    local vivants = {}
    for _, o in ipairs(objectifs or {}) do vivants[CleObjectif(o)] = true end
    for cle in pairs(F[moi.cle]) do if not vivants[cle] then F[moi.cle][cle] = nil end end
end

-- Toutes les feuilles du personnage connecte, gardees pour les autres
-- (a l'arrivee, apres un releve, a la deconnexion).
function suivi.MemoriserFeuilles()
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok or type(objectifs) ~= "table" then return end
    for _, o in ipairs(objectifs) do pcall(suivi.Feuille, o) end
    suivi.NettoyerFeuilles(objectifs)
end

-- La feuille de route dans une infobulle, comme une suite de quetes : le
-- titre de chaque etape, puis ses objectifs en plus petit ; une etape faite
-- passe en vert, coche du jeu a la place du numero.
local VERT = { 0.31, 0.82, 0.41 }
local COCHE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local function Petite(tt)
    local n = tt.NumLines and tt:NumLines() or 0
    local fs = _G[(tt.GetName and tt:GetName() or "GameTooltip") .. "TextLeft" .. n]
    if fs and fs.SetFontObject then pcall(fs.SetFontObject, fs, "GameTooltipTextSmall") end
end
local function LigneDObjet(tt, objet, n, fois, faite)
    local icone = NS.Appeler(NS.jeu.iconeObjet, objet) or "Interface\\Icons\\INV_Misc_QuestionMark"
    local r, g, b = 1, 1, 1
    if faite then r, g, b = VERT[1], VERT[2], VERT[3]
    elseif NS.objets and NS.objets.CouleurDuNom then
        local ok, rr, gg, bb = pcall(NS.objets.CouleurDuNom, objet)
        if ok and rr then r, g, b = rr, gg, bb end
    end
    local nombre = (faite and "  " or "  |cffffffff") .. (fois and "x" or "") .. n .. (faite and "" or "|r")
    tt:AddLine(string.format("        |T%s:14|t %s%s", tostring(icone), NS.inventaire.NomDObjet(objet), nombre), r, g, b)
    Petite(tt)
end
function suivi.FeuilleDansLInfobulle(tt, o)
    local L = NS.L
    local etapes = suivi.Feuille(o)
    if #etapes == 0 then return end
    -- 100 % mais pas tout dans les sacs : le dire.
    if (o.pct or 0) >= 1 and not suivi.Pret(o) then
        tt:AddLine(L.ROUTE_THEORETICAL, 0.7, 0.7, 0.7, true)
        Petite(tt)
    end
    -- Les etapes faites, regroupees en une ligne ; Maj enfoncee : le detail.
    local detail = IsShiftKeyDown and IsShiftKeyDown()
    local faites = 0
    for _, t in ipairs(etapes) do if t.faite then faites = faites + 1 end end
    if faites > 0 and not detail then
        tt:AddLine(" ")
        tt:AddLine(COCHE .. " " .. string.format(L.TIP_STEPS_DONE, faites), VERT[1], VERT[2], VERT[3])
        Petite(tt)
    end
    for i, t in ipairs(etapes) do
      if detail or not t.faite then
        tt:AddLine(" ")
        local tete = t.faite and (COCHE .. " ") or (i .. ". ")
        if t.faite then tt:AddLine(tete .. t.titre, VERT[1], VERT[2], VERT[3]) else tt:AddLine(tete .. t.titre, 1, 0.82, 0) end
        if t.lieu then
            tt:AddLine("     " .. t.lieu, 0.6, 0.6, 0.6)
            Petite(tt)
        end
        for _, b in ipairs(t.blocs or {}) do
            if b.action then
                if t.faite then tt:AddLine("     " .. b.action, VERT[1], VERT[2], VERT[3]) else tt:AddLine("     " .. b.action, 0.9, 0.9, 0.9) end
                Petite(tt)
            end
            -- Une infobulle ne defile pas : au-dela de 5 objets, leur nombre.
            for k, x in ipairs(b.objets or {}) do
                if k > 5 then
                    tt:AddLine("        " .. string.format(L.TIP_MORE_ITEMS, #b.objets - 5), 0.6, 0.6, 0.6)
                    Petite(tt)
                    break
                end
                LigneDObjet(tt, x.objet, x.n, x.fois, t.faite)
            end
        end
      end
    end
end

-- Maj enfoncee ou relachee pendant le survol : l'infobulle se refait (detail
-- des etapes faites).
do
    local veille = CreateFrame("Frame")
    pcall(veille.RegisterEvent, veille, "MODIFIER_STATE_CHANGED")
    veille:SetScript("OnEvent", function()
        local proprio = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner()
        if proprio and proprio.objectifSuivi then
            local f = proprio:GetScript("OnEnter")
            if f then pcall(f, proprio) end
        end
    end)
end

-- Tout est-il dans les sacs (de quoi tout fabriquer tout de suite) ?
function suivi.Pret(o)
    return not NS.inventaire.HorsDesSacs(o and o.matieres)
end

-- ---------------------------------------------------------------------------
-- Consigne : une petite fenetre au milieu de l'ecran, pour le reroll qui a
-- quelque chose a faire pour l'objectif d'un autre personnage (a sa
-- connexion), et apres son envoi (qui est le suivant).
-- ---------------------------------------------------------------------------
local consigne
local function Consigne()
    if consigne then return consigne end
    local f = NS.charte.Fenetre("CraftCoreConsigne", 380, 200, { portrait = false, strate = "DIALOG" })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    if f.titre then f.titre:SetText("CraftCore") end
    f.lignes = {}
    -- Les boutons du pied de la charte, comme toutes les fenetres de la suite.
    if f.pied and NS.charte.BoutonDePied then
        f.ok = NS.charte.BoutonDePied(f, "", 120)
        f.guider = NS.charte.BoutonDePied(f, "", 170, f.ok)
    else
        f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.ok:SetSize(120, 24)
        f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
        f.guider = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.guider:SetSize(170, 24)
        f.guider:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    end
    f.ok:SetScript("OnClick", function() f:Hide() end)
    -- On arrive sur place pendant que la consigne est ouverte : le bouton
    -- de guidage s'en va.
    for _, e in ipairs({ "BANKFRAME_OPENED", "MAIL_SHOW" }) do pcall(f.RegisterEvent, f, e) end
    f:HookScript("OnEvent", function(self, e)
        if not self:IsShown() then return end
        local service = self.guideService
        if (e == "BANKFRAME_OPENED" and service == "banque") or (e == "MAIL_SHOW" and service ~= "banque") then
            self.guider:Hide()
            self:PoserBoutons()
        end
    end)
    -- Les boutons au milieu du pied, comme les fenetres de dialogue du jeu.
    f.PoserBoutons = function(self)
        self.ok:ClearAllPoints()
        self.guider:ClearAllPoints()
        if self.guider:IsShown() then
            local total = self.ok:GetWidth() + 8 + self.guider:GetWidth()
            self.guider:SetPoint("LEFT", self.pied or self, "CENTER", -total / 2, 0)
            self.ok:SetPoint("LEFT", self.guider, "RIGHT", 8, 0)
        else
            self.ok:SetPoint("CENTER", self.pied or self, "CENTER", 0, 0)
        end
    end
    -- Fermeture : Echap au clavier, B a la manette (fenetre speciale du
    -- jeu, comme ses propres fenetres), ou Compris. Aucune liaison de touche
    -- modifiee : cela derangeait la gestion de la manette du jeu.
    f.Lier = function() end
    table.insert(UISpecialFrames, "CraftCoreConsigne")
    do local S = NS.suite or _G.CoreSuite if S and S.ToucheDEntree then S.ToucheDEntree(f, "CraftCoreConsigne") end end
    f:Hide()
    consigne = f
    return f
end
local function Montrer(titre, lignes, guide)
    local L = NS.L
    local f = Consigne()
    for _, l in ipairs(f.lignes) do l:Hide() end
    local y = 40
    local function Ligne(texte, police, r, g, b)
        local n = #f.lignes + 1
        local fs = f.lignes[n]
        for k, l in ipairs(f.lignes) do if not l:IsShown() then fs, n = l, k break end end
        if not fs or fs:IsShown() then
            fs = f:CreateFontString(nil, "OVERLAY", police)
            fs:SetJustifyH("LEFT")
            table.insert(f.lignes, fs)
        end
        fs:SetFontObject(police)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -y)
        fs:SetWidth(344)
        fs:SetWordWrap(true)
        fs:SetText(texte)
        fs:SetTextColor(r or 1, g or 1, b or 1)
        fs:Show()
        y = y + (fs:GetStringHeight() or 14) + 4
    end
    Ligne(titre, "GameFontNormal", 1, 0.82, 0)
    y = y + 4
    for _, l in ipairs(lignes) do Ligne(l[1], l[2] or "GameFontHighlightSmall", l[3], l[4], l[5]) end
    f.ok:SetText(L.ROUTE_OK)
    -- Deja sur place (banque ou boite aux lettres ouverte) : pas de guidage.
    f.guideService = guide and guide.service or nil
    local surPlace = false
    if guide then
        local cadres = (guide.service == "banque") and { "BankFrame", "BankPanel" } or { "MailFrame" }
        for _, nom in ipairs(cadres) do
            local c = _G[nom]
            if c and c.IsVisible and c:IsVisible() then surPlace = true end
        end
    end
    f.guider:SetShown(guide ~= nil and not surPlace)
    if guide and not surPlace then
        f.guider:SetText((guide.service == "banque") and L.ROUTE_GUIDE_BANK_SHORT or L.ROUTE_GUIDE_MAIL_SHORT)
        f.guider:SetScript("OnClick", function()
            if NS.guidage and NS.guidage.Etape then NS.guidage.Etape(guide) end
            f:Hide()
        end)
    end
    f:SetHeight(y + 48)
    f:PoserBoutons()
    f:Show()
end

-- Ce que le personnage connecte detient encore d'un objet (sacs, banque,
-- courrier) : une consigne pour des objets qu'il n'a plus est perimee.
local function JaiEncore(moi, e)
    local envoi = EnvoiDe(e)
    for _, x in ipairs(envoi and envoi.objets or {}) do
        local s, b, c = NS.inventaire.SacsEtBanque(moi, x.objet)
        if (s or 0) + (b or 0) + (c or 0) > 0 then return true end
    end
    return false
end

-- Les etapes que le personnage connecte doit faire pour les autres (jamais
-- pour lui-meme ni pour une ancienne fiche a son nom).
local function MesEtapes()
    local moi = NS.base.Personnage()
    local res = {}
    if not moi or moi.temporaire then return res end
    local F = Feuilles()
    local proprios = {}
    for proprio, objectifs in pairs(F) do
        if type(objectifs) == "table" and not EstMoiOuFantome(proprio, moi.cle) then table.insert(proprios, proprio) end
    end
    table.sort(proprios)
    for _, proprio in ipairs(proprios) do
        local cles = {}
        for k in pairs(F[proprio]) do table.insert(cles, k) end
        table.sort(cles)
        for _, k in ipairs(cles) do
            local f = F[proprio][k]
            for _, e in ipairs(type(f) == "table" and type(f.etapes) == "table" and f.etapes or {}) do
                if e.qui == moi.cle and not e.faite and JaiEncore(moi, e) then
                    table.insert(res, { proprio = proprio, feuille = f, etape = e })
                end
            end
        end
    end
    return res
end
local function TexteObjets(objets)
    local t = {}
    for _, x in ipairs(objets or {}) do
        local icone = NS.Appeler(NS.jeu.iconeObjet, x.objet) or "Interface\\Icons\\INV_Misc_QuestionMark"
        table.insert(t, string.format("|T%s:14|t %d %s", tostring(icone), x.n, NS.inventaire.NomDObjet(x.objet)))
    end
    return t
end

-- A la connexion : ce que ce reroll a a faire, s'il a quelque chose.
function suivi.ConsigneConnexion()
    local L = NS.L
    local a = MesEtapes()
    if #a == 0 then return end
    local lignes, banque = {}, false
    for _, x in ipairs(a) do
        table.insert(lignes, { string.format(L.ROUTE_FOR, NS.inventaire.NomCourt(x.proprio), x.feuille.nom or "?"), "GameFontHighlight", 1, 1, 1 })
        for _, b in ipairs(x.etape.blocs or {}) do
            if b.action then table.insert(lignes, { "   " .. b.action, "GameFontHighlightSmall", 0.9, 0.9, 0.9 }) end
            if b.action == L.ROUTE_D_TAKE then banque = true end
            for _, t in ipairs(TexteObjets(b.objets)) do table.insert(lignes, { "      " .. t, "GameFontHighlightSmall" }) end
        end
    end
    table.insert(lignes, { banque and L.ROUTE_HINT_BANK or L.ROUTE_HINT_MAIL, "GameFontDisableSmall" })
    Montrer(L.ROUTE_YOUR_PART, lignes, { service = banque and "banque" or "courrier" })
end

-- Apres un envoi reussi a `dest` : ce qui est parti est reparti entre mes
-- etapes pour lui (chaque objet compte une seule fois) ; une etape est
-- faite, preuve a l'appui, quand tout son envoi est parti. Puis, qui est le
-- suivant.
function suivi.EnvoiFait(dest, objets)
    local L = NS.L
    local moi = NS.base.Personnage()
    local F = Feuilles()
    if not (moi and dest and not EstMoiOuFantome(dest, moi.cle) and type(F[dest]) == "table") then return end
    local parti = {}
    for objet, n in pairs(objets or {}) do
        local id = tonumber(objet)
        if id then parti[id] = (parti[id] or 0) + (tonumber(n) or 0) end
    end
    local cles = {}
    for k in pairs(F[dest]) do table.insert(cles, k) end
    table.sort(cles)
    local fini = {}
    for _, k in ipairs(cles) do
        local f = F[dest][k]
        for _, e in ipairs(type(f) == "table" and type(f.etapes) == "table" and f.etapes or {}) do
            if e.qui == moi.cle and not e.faite then
                local envoi = EnvoiDe(e)
                e.envoye = type(e.envoye) == "table" and e.envoye or {}
                for _, x in ipairs(envoi and envoi.objets or {}) do
                    local id = tonumber(x.objet)
                    local manque = (tonumber(x.n) or 0) - (tonumber(e.envoye[x.objet]) or 0)
                    local d = id and math.min(manque, parti[id] or 0) or 0
                    if d > 0 then
                        e.envoye[x.objet] = (tonumber(e.envoye[x.objet]) or 0) + d
                        parti[id] = parti[id] - d
                    end
                end
                if EnvoiCouvert(e) then
                    e.faite, e.preuve = true, "envoi"
                    table.insert(fini, f)
                end
            end
        end
    end
    if #fini == 0 then return end
    -- La suite : un autre reroll a connecter, sinon le retour au demandeur.
    local f = fini[1]
    local suivant
    for _, e in ipairs(f.etapes or {}) do
        if not e.faite and e.qui and e.qui ~= moi.cle and not EstMoiOuFantome(e.qui, dest) then suivant = e.qui break end
    end
    local lignes = { { string.format(L.ROUTE_DONE_FOR, NS.inventaire.NomCourt(dest), f.nom or "?"), "GameFontHighlight", VERT[1], VERT[2], VERT[3] } }
    if suivant then
        table.insert(lignes, { string.format(L.ROUTE_NEXT_LOGIN, NS.inventaire.NomCourt(suivant)), "GameFontHighlight", 1, 1, 1 })
    else
        table.insert(lignes, { string.format(L.ROUTE_NEXT_BACK, NS.inventaire.NomCourt(dest)), "GameFontHighlight", 1, 1, 1 })
    end
    Montrer(L.ROUTE_PART_DONE, lignes, nil)
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(self, evenement, premiere, recharge)
        if evenement == "PLAYER_LOGOUT" then pcall(suivi.MemoriserFeuilles) return end
        if not (premiere or recharge) then return end
        -- Un peu apres l'arrivee, quand les sacs sont releves.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(4, function()
                pcall(suivi.MemoriserFeuilles)
                pcall(suivi.ConsigneConnexion)
            end)
        end
    end)
end

-- La prochaine etape : la premiere pas faite. Rend l'etape, son rang, et
-- si elle peut etre lancee maintenant (tout dans les sacs).
local function ProchaineEtape(etapes)
    local A = NS.actions
    for rang, e in ipairs(etapes) do
        if not e.faite then
            local pret = A and A.EtatPourFabriquer and A.EtatPourFabriquer(e.recette) == true
            return e, rang, pret
        end
    end
    return nil
end

-- La premiere fabrication prete d'un projet. Rend la recette, le nombre de
-- fois, l'etape et son rang.
local function PremiereFabricationPrete(lignes)
    local A = NS.actions
    if not (A and A.EtatPourFabriquer) then return nil end
    local etapes = EtapesDeFabrication(lignes)
    local e, rang, pret = ProchaineEtape(etapes)
    if e and pret then
        return e.recette, math.min(e.fois, A.NombrePossible(e.recette)), e, rang, etapes
    end
    return nil, nil, nil, nil, etapes
end

-- Une fabrication prete dans le metier ouvert, pour un des objectifs du
-- suivi : la fenetre cachee du metier reste alors ouverte.
function suivi.FabricationPreteIci()
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return false end
    producteurs = nil
    for _, o in ipairs(objectifs or {}) do
        local rec = PremiereFabricationPrete(o.lignes)
        if rec and NS.recettes.PretALancer and NS.recettes.PretALancer(rec) then return true end
    end
    return false
end

-- La fabrication `idRec` sert-elle encore l'objectif `cle` ? Non si
-- l'objectif est atteint (rang vise, projet fini) ou si l'etape en cours a
-- deja ce qu'il lui faut, compte en direct dans les sacs.
function suivi.EncoreUtile(cle, idRec)
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return true end
    producteurs = nil
    for _, o in ipairs(objectifs or {}) do
        if o.cle == cle then
            -- « Atteint » ne veut dire « fini » que pour un rang vise ; pour un
            -- projet ou les fabrications rapides, c'est « tout est reuni » :
            -- justement le moment de fabriquer, la serie continue.
            if o.atteint and o.genre == "progression" then return false end
            for _, e in ipairs(EtapesDeFabrication(o.lignes)) do
                if e.recette and tostring(e.recette.id) == tostring(idRec) then
                    if e.finale then return true end
                    return SurSoi(e.objet) < (e.besoin or 0)
                end
            end
            return false
        end
    end
    return false
end

-- Le groupe d'un objectif dans son onglet, comme les zones du suivi des
-- quetes : cle et titre.
local function GroupeDe(o, vue)
    local L = NS.L
    if vue == "commandes" then return "commandes", L.TRACK_TAB_ORDERS end
    if vue == "caisses" then return "caisses", L.TRACK_TAB_CRATES end
    if vue == "progressions" then
        if o.genre == "progression" then return "rangs", L.TRACK_GROUP_RANKS end
        return "plans", L.TRACK_GROUP_PLANS
    end
    if o.rapides then return "rapides", L.NAV_QUICK end
    return "projets", L.TRACK_GROUP_PROJECTS
end

local function Favoris()
    local g = NS.base.ReglagesGeneraux()
    if type(g.favorisSuivi) ~= "table" then g.favorisSuivi = {} end
    return g.favorisSuivi
end

local function GroupesReplies()
    local g = NS.base.ReglagesGeneraux()
    if type(g.groupesReplies) ~= "table" then g.groupesReplies = {} end
    return g.groupesReplies
end

-- Les objectifs de l'onglet, presentes comme le suivi des quetes : des
-- groupes (comme les zones) separes d'un filet, qui se replient ; dedans,
-- chaque objectif comme une quete, son pourcentage a droite ; deplie, ses
-- matieres comme des objectifs de quete.
-- Ce qui a deja ete montre d'un objectif (etapes, matieres), dans l'ordre :
-- une etape ou une matiere qui sort du calcul (consommee, faite) reste a sa
-- place, en vert, jusqu'a ce que l'objectif soit atteint. La fenetre ne
-- saute plus a chaque fabrication.
local memoEtapes, memoMatieres = {}, {}

local function Fusion(memo, cle, actuels, champ, quantite)
    local m = memo[cle] or {}
    memo[cle] = m
    local parObjet = {}
    for _, e in ipairs(actuels) do parObjet[e[champ]] = e end
    local connus = {}
    for _, x in ipairs(m) do connus[x.objet] = true end
    for _, e in ipairs(actuels) do
        if not connus[e[champ]] then table.insert(m, { objet = e[champ], quantite = e[quantite], ref = e }) connus[e[champ]] = true end
    end
    local rendu = {}
    for _, x in ipairs(m) do
        local e = parObjet[x.objet]
        if e then x.quantite = math.max(x.quantite or 0, e[quantite] or 0) x.ref = e table.insert(rendu, { e = e })
        else table.insert(rendu, { e = x.ref, fini = true, quantite = x.quantite }) end
    end
    return rendu
end

-- Assembler une caisse : utiliser l'objet caisse est une action protegee du
-- jeu, donc un bouton securise (le jeu fait le clic lui-meme). Un seul, pose
-- sur la caisse prete ; jamais touche en combat.
local assembleur, assembleurPose
local function Assembleur()
    if assembleur then return assembleur end
    if NS.Appeler(InCombatLockdown) then return nil end
    local ok, b = pcall(CreateFrame, "Button", "CraftCoreAssembler", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    if not ok or not b then return nil end
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:SetFrameStrata("HIGH")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(NS.L.CRATES_ASSEMBLE, 1, 0.82, 0)
        GameTooltip:AddLine(NS.L.CRATES_ASSEMBLE_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    assembleur = b
    return b
end
local function CacherAssembleur()
    if assembleur and not NS.Appeler(InCombatLockdown) then assembleur:Hide() end
end
suivi.CacherAssembleur = CacherAssembleur

local function DessinerObjectifs(y, objectifs, vue)
    local L = NS.L
    local zone = cadreSuivi.zone
    local largeur = LARGEUR_SUIVI - 2 * NS.charte.MARGE - 10
    local nt, ni, nbo, ne, nf = 0, 0, 0, 0, 0
    local LIGNE = Police("ObjectiveTrackerLineFont", "GameFontHighlightSmall")
    local TITRE = Police("ObjectiveTrackerHeaderFont", "GameFontNormal")
    local function T(police, taille)
        nt = nt + 1
        local t = Texte(nt, police)
        if taille then Taille(t, taille) end
        -- Texte repris d'un autre usage : alignement et coupure par defaut, sinon
        -- un etat aligne a droite deplacait la ligne suivante.
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        t:SetWidth(0)
        return t
    end
    local function Icone()
        ni = ni + 1
        local icone = cadreSuivi.icones[ni]
        if not icone then
            icone = cadreSuivi:CreateTexture(nil, "ARTWORK")
            icone:SetSize(16, 16)
            cadreSuivi.icones[ni] = icone
        end
        icone:ClearAllPoints()
        icone:SetSize(16, 16)
        icone:SetDesaturated(false)
        icone:Show()
        return icone
    end
    local function Filet(yF)
        nf = nf + 1
        cadreSuivi.filets = cadreSuivi.filets or {}
        local f = cadreSuivi.filets[nf]
        if not f then
            f = cadreSuivi:CreateTexture(nil, "ARTWORK")
            cadreSuivi.filets[nf] = f
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -yF)
        f:SetPoint("TOPRIGHT", zone, "TOPRIGHT", 0, -yF)
        if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(f, 1, 1) else f:SetHeight(1) end
        PeindreFilet(f, 0.8, 0.65, 0.35, 0.35)
        f:Show()
    end
    local function Ligne(pool)
        cadreSuivi[pool] = cadreSuivi[pool] or {}
        local liste = cadreSuivi[pool]
        local rang = (pool == "entetes") and (ne + 1) or (nbo + 1)
        if pool == "entetes" then ne = rang else nbo = rang end
        local b = liste[rang]
        if not b then
            b = CreateFrame("Button", nil, cadreSuivi)
            b:SetHeight(18)
            b.marqueur = b:CreateTexture(nil, "ARTWORK")
            b.marqueur:SetSize(14, 14)
            b.marqueur:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.nom = b:CreateFontString(nil, "OVERLAY", TITRE)
            b.nom:SetPoint("LEFT", b.marqueur, "RIGHT", 4, 0)
            b.nom:SetJustifyH("LEFT")
            b.nom:SetWordWrap(false)
            b.droite = b:CreateFontString(nil, "OVERLAY", TITRE)
            b.droite:SetPoint("RIGHT", b, "RIGHT", 0, 0)
            b.droite:SetJustifyH("RIGHT")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            liste[rang] = b
        end
        b:ClearAllPoints()
        if b.creer then b.creer:Hide() end
        if b.barreFab then b.barreFab:Hide() end
        b:Show()
        return b
    end
    if #objectifs == 0 then
        local t = T(LIGNE, TAILLE_LIGNE)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
        t:SetWidth(largeur)
        t:SetText(L.GOAL_NONE)
        t:SetTextColor(0.8, 0.8, 0.8)
        return y + (t:GetStringHeight() or 14) + 8
    end
    -- Les groupes, dans l'ordre ou ils apparaissent.
    local groupes, ordre = {}, {}
    for _, o in ipairs(objectifs) do
        local cleG, titreG = GroupeDe(o, vue)
        if not groupes[cleG] then
            groupes[cleG] = { titre = titreG, liste = {} }
            table.insert(ordre, cleG)
        end
        table.insert(groupes[cleG].liste, o)
    end
    local ouverts, replies = Ouverts(), GroupesReplies()
    for rangG, cleG in ipairs(ordre) do
        local gr = groupes[cleG]
        local replie = replies[cleG] == true
        if rangG > 1 then
            y = y + 8
            Filet(y)
            y = y + 6
        end
        -- En-tete du groupe : comme une zone du suivi des quetes.
        local e = Ligne("entetes")
        e:SetPoint("TOPLEFT", zone, "TOPLEFT", 0, -y)
        e:SetWidth(largeur)
        e:SetHeight(20)
        e.marqueur:SetTexture(replie and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        e.nom:SetFontObject("GameFontNormal")
        Taille(e.nom, TAILLE_LIGNE + 3)
        e.nom:SetText(gr.titre)
        e.nom:SetTextColor(1, 0.82, 0)
        e.droite:SetFontObject("GameFontNormal")
        Taille(e.droite, TAILLE_LIGNE)
        e.droite:SetText(tostring(#gr.liste))
        e.droite:SetTextColor(0.8, 0.8, 0.8)
        e.nom:SetPoint("RIGHT", e.droite, "LEFT", -6, 0)
        e:SetScript("OnClick", function()
            replies[cleG] = not replies[cleG] or nil
            suivi.Dessiner()
        end)
        y = y + 24
        if not replie then
            for _, o in ipairs(gr.liste) do
                local estOuvert = ouverts[o.cle] == true
                local b = Ligne("boutons")
                b:SetPoint("TOPLEFT", zone, "TOPLEFT", 6, -y)
                b:SetWidth(largeur - 6)
                b:SetHeight(18)
                b.marqueur:SetTexture(estOuvert and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
                b.nom:SetFontObject(TITRE)
                Taille(b.nom, TAILLE_LIGNE + 1)
                b.nom:SetText(o.nom)
                -- Vert : tout est dans les sacs, on peut fabriquer. Sinon gris.
                local pretO = (o.pct or 0) >= 1 and suivi.Pret(o)
                if pretO then b.nom:SetTextColor(0.31, 0.82, 0.41) else b.nom:SetTextColor(0.85, 0.85, 0.85) end
                -- Le pourcentage, comme celui des quetes.
                local pct = math.floor((o.pct or 0) * 100 + 0.5)
                b.droite:SetFontObject(TITRE)
                Taille(b.droite, TAILLE_LIGNE)
                b.droite:SetText(pct .. " %")
                -- 100 % en vert seulement quand tout est dans les sacs ; sinon
                -- gris (l'infobulle dit "100 % theorique").
                if pretO then b.droite:SetTextColor(0.31, 0.82, 0.41)
                else b.droite:SetTextColor(0.7, 0.7, 0.7) end
                b.nom:SetPoint("RIGHT", b.droite, "LEFT", -8, 0)
                -- Plus d'etoile de favori : le pourcentage au bord droit.
                if b.etoile then b.etoile:Hide() end
                b.droite:ClearAllPoints()
                b.droite:SetPoint("RIGHT", b, "RIGHT", 0, 0)
                local cle = o.cle
                b:SetScript("OnClick", function()
                    ouverts[cle] = not ouverts[cle] or nil
                    suivi.Dessiner()
                end)
                -- Au survol : une infobulle collee a droite du suivi, avec la
                -- prochaine etape et ce qui manque encore dans les sacs (et ou
                -- le trouver), quand le bouton Creer n'est pas la.
                local objectif = o
                b.objectifSuivi = true
                b:SetScript("OnEnter", function(self)
                    local etapesS = EtapesDeFabrication(objectif.lignes)
                    local e, rangE = ProchaineEtape(etapesS)
                    -- Toujours au meme endroit : contre le haut du suivi, du
                    -- cote choisi (la suite place l'infobulle).
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(objectif.nom or "", 1, 1, 1)
                    if e then
                        local pret = NS.actions and NS.actions.EtatPourFabriquer and NS.actions.EtatPourFabriquer(e.recette)
                        if pret == nil then
                            GameTooltip:AddLine(L.CRAFT_OTHER_CHAR, 0.8, 0.8, 0.8, true)
                        end
                    end
                    -- Toutes les matieres de l'objectif, aux quantites de
                    -- l'objectif entier, et ou elles sont des qu'elles ne sont
                    -- pas toutes dans les sacs (banque, courrier, autres persos).
                    -- La feuille de route : les etapes dans l'ordre le plus
                    -- rapide (qui envoie quoi, banque, courrier, achats...).
                    suivi.FeuilleDansLInfobulle(GameTooltip, objectif)
                    -- Recettes a apprendre : ou les apprendre.
                    local premiere = true
                    for _, a in ipairs(objectif.aApprendre or {}) do
                        if not a.appris then
                            if premiere then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(L.GOAL_LEARN_WHERE, 1, 0.82, 0)
                                premiere = false
                            end
                            -- La recette, ou (le mot court), puis le detail :
                            -- le plan deja en main, sinon qui le vend ou le laisse.
                            local okC, nature, lignes = pcall(NS.recettes.CommentApprendre, a.recette)
                            local ou = okC and nature and L[nature] or nil
                            if okC and nature == "RECIPES_HOW_TRAINER" and NS.avisRang and NS.avisRang.TexteFormateur then
                                ou = NS.avisRang.TexteFormateur(a.recette)
                            end
                            local okP, _, possede = pcall(NS.recettes.PlanPossede, a.recette)
                            if okP and possede then ou = string.format(L.GOAL_LEARN_HAVE, possede) end
                            local quand = a.plusTard and ("  |cffb3b3b3" .. string.format(L.GOAL_LEARN_RANK, a.rang) .. "|r") or ""
                            GameTooltip:AddLine("     " .. a.nom .. (ou and ("  |cffb3b3b3" .. ou .. "|r") or "") .. quand, 1, 1, 1)
                            Petite(GameTooltip)
                            if not (okP and possede) and okC and type(lignes) == "table" then
                                local n = 0
                                for _, l in ipairs(lignes) do
                                    if n >= 3 then break end
                                    if l ~= L.RECIPES_SRC_ORIGIN and l ~= L.RECIPES_HOW_TRAINER_GUESS then
                                        GameTooltip:AddLine("          " .. l, 0.7, 0.7, 0.7)
                                        Petite(GameTooltip)
                                        n = n + 1
                                    end
                                end
                            end
                        end
                    end
                    -- A acheter : seulement ce qui manque encore dans les sacs.
                    local aAcheter = {}
                    for objet, n in pairs(objectif.achats or {}) do
                        local dans = NS.inventaire.DisponibleDansLesSacs(objet) or 0
                        if dans < n then table.insert(aAcheter, { objet = objet, n = n - dans }) end
                    end
                    if #aAcheter > 0 then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(L.CRAFT_TO_BUY, 1, 0.82, 0)
                        for _, x in ipairs(aAcheter) do LigneDObjet(GameTooltip, x.objet, x.n, false, false) end
                    end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                -- Tout est reuni : un bouton Creer sur la ligne, comme la petite
                -- carte et l'etoile du suivi des quetes. Un clic lance la
                -- premiere fabrication prete (le premier ouvre le metier).
                local recettePrete, fois, etapeP, rangP, etapes = PremiereFabricationPrete(o.lignes)
                -- Une etape vient de se terminer : on le dit, et on invite a la suivante.
                local suiviEtapes = NS.base.ReglagesGeneraux()
                suiviEtapes.etapesFab = type(suiviEtapes.etapesFab) == "table" and suiviEtapes.etapesFab or {}
                if rangP then
                    local avant = suiviEtapes.etapesFab[o.cle]
                    if avant and rangP > avant and etapes and #etapes > 1 then
                        NS.Dire(string.format(L.CRAFT_STEP_DONE, avant, rangP))
                    end
                    suiviEtapes.etapesFab[o.cle] = rangP
                end
                -- Pas de fabrication partielle : tout doit etre reuni (100 %) et
                -- dans les sacs (rien a sortir de la banque ni a acheter).
                -- Monter un metier : chaque etape se fait des qu'elle a ses
                -- composants (le bouton se grise seul sinon) ; jamais bloque
                -- par une recette a apprendre plus tard.
                -- Regle ferme, rang vise compris : Creer ne s'active qu'a 100 %,
                -- tout reuni et dans les sacs.
                local toutEnSacs = (o.pct or 0) >= 1
                for _, m in ipairs(toutEnSacs and o.matieres or {}) do
                    if (NS.inventaire.DisponibleDansLesSacs(m.objet) or 0) < (m.requis or 0) then toutEnSacs = false break end
                end
                for objet, n in pairs(toutEnSacs and type(o.achats) == "table" and o.achats or {}) do
                    if (NS.inventaire.DisponibleDansLesSacs(objet) or 0) < (tonumber(n) or 0) then toutEnSacs = false break end
                end
                -- Une serie de cette recette est en cours : a la place du
                -- bouton, une petite barre qui avance a chaque objet fabrique
                -- (« 3 / 17 »). Le bouton revient a la fin de la serie.
                local serie = NS.actions and NS.actions.serie
                local serieIci = serie and serie.lancee and recettePrete and tostring(serie.recette) == tostring(recettePrete.id)
                    and (serie.reussis or 0) < (serie.total or 1)
                if b.barreFab then b.barreFab:Hide() end
                -- Bouton et barre a une place fixe, quel que soit le pourcentage :
                -- la place de « 100 % » est gardee a droite, tous s'alignent.
                if not b.mesurePct then
                    b.mesurePct = b:CreateFontString(nil, "OVERLAY", TITRE)
                    b.mesurePct:Hide()
                end
                b.mesurePct:SetFontObject(b.droite:GetFontObject() or TITRE)
                b.mesurePct:SetText("100 %")
                local placePct = math.ceil(b.mesurePct:GetStringWidth() or 36) + 8
                if serieIci then
                    if not b.barreFab then b.barreFab = NS.actions.BarreDeSerie(b) end
                    local barre = b.barreFab
                    barre:ClearAllPoints()
                    barre:SetPoint("RIGHT", b, "RIGHT", -placePct, 0)
                    barre:SetSize(60, 16)
                    barre:Poser(serie.reussis, serie.total)
                    barre:SetFrameLevel(b:GetFrameLevel() + 3)
                    barre:Show()
                    if b.creer then b.creer:Hide() end
                    b.nom:SetPoint("RIGHT", barre, "LEFT", -6, 0)
                elseif o.genre == "caisse" and toutEnSacs and not assembleurPose and not NS.Appeler(InCombatLockdown) then
                    local a = Assembleur()
                    if a then
                        assembleurPose = true
                        a:ClearAllPoints()
                        a:SetPoint("RIGHT", b, "RIGHT", -placePct, 0)
                        a:SetSize(76, 16)
                        a:SetText(L.CRATES_ASSEMBLE)
                        local txt = a:GetFontString()
                        if txt then Taille(txt, 10) end
                        a:SetAttribute("item", "item:" .. tostring(o.caisse))
                        a:Show()
                        b.nom:SetPoint("RIGHT", a, "LEFT", -6, 0)
                    end
                elseif recettePrete and toutEnSacs then
                    if not b.creer then
                        b.creer = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
                        b.creer:SetSize(52, 16)
                    end
                    b.creer:ClearAllPoints()
                    b.creer:SetPoint("RIGHT", b, "RIGHT", -placePct, 0)
                    b.creer:SetSize(60, 16)
                    b.creer:SetText((etapes and #etapes > 1) and L.CRAFT_STEP_NOW or L.CRAFT_BUTTON)
                    local cleO, idRec = o.cle, recettePrete.id
                    NS.actions.PreparerBoutonFabriquer(b.creer, recettePrete, fois, function()
                        return suivi.EncoreUtile(cleO, idRec)
                    end)
                    -- L'infobulle dit quelle etape le clic va lancer.
                    b.creer.etape = (etapes and #etapes > 1 and etapeP) and string.format(L.CRAFT_STEP_TIP, rangP, #etapes,
                        NS.inventaire.NomDObjet(etapeP.objet), fois or 1) or nil
                    if not b.creer.etapeAccroche then
                        b.creer.etapeAccroche = true
                        b.creer:HookScript("OnEnter", function(self)
                            if self.etape and GameTooltip:IsOwned(self) then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(self.etape, 1, 0.82, 0, true)
                                GameTooltip:Show()
                            end
                        end)
                    end
                    local txt = b.creer:GetFontString()
                    if txt then Taille(txt, 10) end
                    b.creer:SetFrameLevel(b:GetFrameLevel() + 3)
                    b.nom:SetPoint("RIGHT", b.creer, "LEFT", -6, 0)
                end
                -- Des matieres manquent et leurs lieux sont connus : la petite
                -- carte du suivi des quetes lance le guidage de recolte.
                local lieux = (not recettePrete) and suivi.LieuxRecoltables({ o }) or {}
                if #lieux > 0 then
                    local paramsPion = { objectifs = { o.cle } }
                    if not b.pion then
                        b.pion = CreateFrame("Button", nil, b)
                        b.pion:SetSize(18, 18)
                        b.pion.fond = b.pion:CreateTexture(nil, "BACKGROUND")
                        b.pion.fond:SetSize(14, 14)
                        b.pion.fond:SetPoint("CENTER")
                        b.pion.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
                        b.pion.t = b.pion:CreateTexture(nil, "ARTWORK")
                        b.pion.t:SetSize(12, 12)
                        b.pion.t:SetPoint("CENTER")
                        b.pion.t:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
                        if b.pion.t.SetMask then pcall(b.pion.t.SetMask, b.pion.t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
                        b.pion.anneau = b.pion:CreateTexture(nil, "OVERLAY")
                        b.pion.anneau:SetSize(31, 31)
                        b.pion.anneau:SetPoint("TOPLEFT", b.pion, "TOPLEFT", 0, 0)
                        b.pion.anneau:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                        b.pion:SetScript("OnClick", function(self) if self.params then NS.guidage.Basculer(self.params) end end)
                        b.pion:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(suivi.EnGuidage(self.params) and L.GUIDE_GOALS_STOP or L.GUIDE_GOALS, 1, 0.82, 0)
                            GameTooltip:AddLine(L.GUIDE_GOALS_HELP, 1, 1, 1, true)
                            GameTooltip:Show()
                        end)
                        b.pion:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end
                    b.pion:ClearAllPoints()
                    b.pion:SetPoint("RIGHT", b.droite, "LEFT", -4, 0)
                    b.pion:SetFrameLevel(b:GetFrameLevel() + 3)
                    b.pion.params = paramsPion
                    local actif = suivi.EnGuidage(paramsPion)
                    b.pion.t:SetDesaturated(not actif)
                    b.pion.anneau:SetDesaturated(not actif)
                    b.pion:Show()
                    b.nom:SetPoint("RIGHT", b.pion, "LEFT", -4, 0)
                elseif b.pion then
                    b.pion:Hide()
                end
                y = y + 20
                -- Tout est reuni et il y a plusieurs etapes : elles s'affichent
                -- dessous, dans l'ordre, chacune avec son etat.
                local vues = (((o.pct or 0) >= 1 and etapes and #etapes > 1) or (memoEtapes[o.cle] and #memoEtapes[o.cle] > 1))
                    and Fusion(memoEtapes, o.cle, etapes or {}, "objet", "besoin") or nil
                if vues and #vues > 1 then
                    -- De l'air sous la ligne (et son bouton) avant les etapes.
                    y = y + 4
                    local objetProchain = etapes and rangP and etapes[rangP] and etapes[rangP].objet
                    for rangE, v in ipairs(vues) do
                        local e = v.e or {}
                        if v.fini then e = { objet = e.objet, recette = e.recette, finale = false, faite = true, avoir = v.quantite, besoin = v.quantite } end
                        local t = T(LIGNE, TAILLE_LIGNE - 1)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -(y - 2))
                        t:SetWidth(largeur - 24 - 70)
                        t:SetWordWrap(false)
                        -- Compte "fait / a faire" : 0 / 5, puis 1 / 5... jusqu'a 5 / 5.
                        local fait, total
                        if e.finale then
                            local cleT = tostring(o.cle) .. "/" .. tostring(e.recette.id)
                            suiviEtapes.totauxFab = type(suiviEtapes.totauxFab) == "table" and suiviEtapes.totauxFab or {}
                            total = math.max(tonumber(suiviEtapes.totauxFab[cleT]) or 0, e.besoin or 1)
                            suiviEtapes.totauxFab[cleT] = total
                            fait = total - (e.besoin or 1)
                        else
                            fait, total = e.avoir or 0, e.besoin or 1
                        end
                        t:SetText(string.format(L.CRAFT_STEP_LINE, rangE, NS.inventaire.NomDObjet(e.objet), fait, total))
                        local etat = T(LIGNE, TAILLE_LIGNE - 1)
                        etat:ClearAllPoints()
                        -- "Fait" et "A creer" tout a droite, toujours au meme endroit ;
                        -- un nom trop long est coupe par des points.
                        etat:SetPoint("TOPRIGHT", zone, "TOPLEFT", largeur - 2, -(y - 2))
                        etat:SetWidth(70)
                        etat:SetJustifyH("RIGHT")
                        etat:SetWordWrap(false)
                        -- Faite : toute la ligne en vert. La prochaine : en blanc,
                        -- suivie de "A creer" (le bouton de la ligne la lance).
                        -- Les suivantes : en blanc.
                        if e.faite then
                            t:SetTextColor(0.31, 0.82, 0.41)
                            etat:SetText(L.GUIDE_DONE)
                            etat:SetTextColor(0.31, 0.82, 0.41)
                        elseif e.objet == objetProchain then
                            t:SetTextColor(1, 1, 1)
                            etat:SetText(L.CRAFT_STEP_NOW)
                            etat:SetTextColor(1, 1, 1)
                        else
                            t:SetTextColor(1, 1, 1)
                            etat:SetText("")
                        end
                        y = y + 14
                    end
                    y = y + 2
                end
                -- Commande : pour qui, en dessous, comme l'XP sous une zone.
                if o.pourQui then
                    local t = T(LIGNE, TAILLE_LIGNE - 1)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -(y - 2))
                    t:SetWidth(largeur - 24)
                    t:SetWordWrap(false)
                    t:SetText(o.pourQui)
                    t:SetTextColor(0.8, 0.8, 0.8)
                    y = y + 14
                end
                if estOuvert then
                    if o.detail then
                        -- L'objectif (rang actuel, rang vise), puis un petit
                        -- filet avant les matieres.
                        y = y + 4
                        local t = T(LIGNE, TAILLE_LIGNE - 1)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -y)
                        t:SetWidth(largeur - 24)
                        t:SetText(o.detail)
                        t:SetTextColor(0.8, 0.8, 0.8)
                        y = y + (t:GetStringHeight() or 14) + 5
                        nf = nf + 1
                        cadreSuivi.filets = cadreSuivi.filets or {}
                        local f = cadreSuivi.filets[nf]
                        if not f then
                            f = cadreSuivi:CreateTexture(nil, "ARTWORK")
                            cadreSuivi.filets[nf] = f
                        end
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", zone, "TOPLEFT", 24, -y)
                        f:SetPoint("TOPRIGHT", zone, "TOPRIGHT", -40, -y)
                        if _G.PixelUtil and _G.PixelUtil.SetHeight then _G.PixelUtil.SetHeight(f, 1, 1) else f:SetHeight(1) end
                        PeindreFilet(f, 0.8, 0.65, 0.35, 0.22)
                        f:Show()
                        y = y + 6
                    end
                    -- D'abord les recettes a apprendre, avant les matieres.
                    -- Comme les matieres : a faire en couleur, fait en gris
                    -- avec la coche verte a droite. Ou l'apprendre : au survol.
                    for _, a in ipairs(o.aApprendre or {}) do
                        local icone = Icone()
                        icone:SetPoint("TOPLEFT", zone, "TOPLEFT", 28, -y)
                        icone:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
                        icone:SetDesaturated(a.appris)
                        -- A droite, en court : le plan deja en main (ou), sinon
                        -- comment l'obtenir (a acheter, a looter...).
                        local ouTexte
                        if not a.appris and not a.plusTard then
                            local okP, _, possede = pcall(NS.recettes.PlanPossede, a.recette)
                            if okP and possede then ouTexte = string.format(L.GOAL_LEARN_HAVE, possede)
                            else
                                local okC, nature = pcall(NS.recettes.CommentApprendre, a.recette)
                                ouTexte = okC and nature and L[nature] or nil
                                if okC and nature == "RECIPES_HOW_TRAINER" and NS.avisRang and NS.avisRang.TexteFormateur then
                                    ouTexte = NS.avisRang.TexteFormateur(a.recette)
                                end
                            end
                        end
                        local ou
                        if ouTexte then
                            ou = T(LIGNE, TAILLE_LIGNE)
                            ou:ClearAllPoints()
                            ou:SetPoint("RIGHT", zone, "TOPLEFT", largeur - 2, -(y + 8))
                            ou:SetWidth(0)
                            ou:SetJustifyH("RIGHT")
                            ou:SetWordWrap(false)
                            ou:SetText(ouTexte)
                            ou:SetTextColor(0.7, 0.7, 0.7)
                        end
                        local t = T(LIGNE, TAILLE_LIGNE)
                        t:ClearAllPoints()
                        t:SetPoint("LEFT", icone, "RIGHT", 6, 0)
                        if ou then t:SetPoint("RIGHT", ou, "LEFT", -8, 0)
                        else t:SetPoint("RIGHT", zone, "TOPLEFT", largeur - 22, -(y + 8)) end
                        t:SetWordWrap(false)
                        -- Pas encore le rang : dit pour plus tard, en gris ; la
                        -- fabrication continue d'ici la.
                        if a.plusTard and not a.appris then
                            t:SetText(string.format(L.GOAL_LEARN_AT, a.rang, a.nom))
                        else
                            t:SetText(string.format(L.GOAL_LEARN, a.nom))
                        end
                        if a.plusTard and not a.appris then
                            t:SetTextColor(0.6, 0.6, 0.6)
                            icone:SetDesaturated(true)
                        elseif a.appris then
                            t:SetTextColor(0.5, 0.5, 0.5)
                            local coche = Icone()
                            coche:SetSize(14, 14)
                            coche:SetPoint("RIGHT", zone, "TOPLEFT", largeur - 2, -(y + 8))
                            coche:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                        else
                            t:SetTextColor(1, 0.82, 0)
                        end
                        y = y + 18
                    end
                    if #(o.matieres or {}) == 0 then
                        local t = T(LIGNE, TAILLE_LIGNE)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", zone, "TOPLEFT", 28, -y)
                        t:SetWidth(largeur - 28)
                        t:SetText(L.GOAL_NOTHING_TO_GATHER)
                        t:SetTextColor(0.8, 0.8, 0.8)
                        y = y + 16
                    end
                    for _, v in ipairs(Fusion(memoMatieres, o.cle, o.matieres or {}, "objet", "requis")) do
                        local m = v.e
                        if v.fini then m = { objet = m.objet, requis = v.quantite, possede = v.quantite, manque = 0, fini = true } end
                        local icone = Icone()
                        icone:SetPoint("TOPLEFT", zone, "TOPLEFT", 28, -y)
                        icone:SetTexture(NS.Appeler(NS.jeu.iconeObjet, m.objet) or "Interface\\Icons\\INV_Misc_QuestionMark")
                        icone:SetDesaturated(m.possede == 0)
                        local nom = T(LIGNE, TAILLE_LIGNE)
                        nom:ClearAllPoints()
                        nom:SetPoint("LEFT", icone, "RIGHT", 6, 0)
                        nom:SetPoint("RIGHT", zone, "TOPLEFT", largeur - 66, -(y + 8))
                        nom:SetWordWrap(false)
                        nom:SetText(NS.inventaire.NomDObjet(m.objet))
                        local compte = T(LIGNE, TAILLE_LIGNE)
                        compte:ClearAllPoints()
                        -- Le compte cale sur le bord droit de la zone, a la
                        -- meme place pour toutes les lignes, quel que soit
                        -- leur etat (fait, en cours, absent).
                        -- Deux points d'ancrage : sa boite est fixe, jamais
                        -- heritee d'un autre usage du meme texte.
                        compte:SetPoint("RIGHT", zone, "TOPLEFT", largeur - 2, -(y + 8))
                        compte:SetWidth(0)
                        compte:SetJustifyH("RIGHT")
                        compte:SetWordWrap(false)
                        compte:SetText(math.min(m.possede, m.requis) .. " / " .. m.requis)
                        if m.fini then
                            -- Deja utilisee : faite, en vert, a sa place.
                            nom:SetTextColor(0.31, 0.82, 0.41)
                            compte:SetTextColor(0.31, 0.82, 0.41)
                        elseif m.manque == 0 and (NS.inventaire.DisponibleDansLesSacs(m.objet) or 0) < m.requis then
                            -- Reunie, mais pas toute dans les sacs : en gris.
                            nom:SetTextColor(0.85, 0.85, 0.85)
                            compte:SetTextColor(0.7, 0.7, 0.7)
                        elseif m.manque == 0 then
                            nom:SetTextColor(0.5, 0.5, 0.5)
                            compte:SetTextColor(0.31, 0.82, 0.41)
                        elseif m.possede == 0 then
                            nom:SetTextColor(0.6, 0.6, 0.6)
                            compte:SetTextColor(0.6, 0.6, 0.6)
                        else
                            nom:SetTextColor(0.85, 0.85, 0.85)
                            compte:SetTextColor(1, 1, 1)
                        end
                        y = y + 18
                    end
                    y = y + 4
                end
            end
        end
    end
    return y + 4
end

function suivi.Dessiner()
    if not cadreSuivi then return end
    assembleurPose = false
    CacherAssembleur()
    local L = NS.L
    for _, t in ipairs(cadreSuivi.textes) do t:Hide() end
    for _, i in ipairs(cadreSuivi.icones) do i:Hide() end
    for _, b in ipairs(cadreSuivi.barres) do b:Hide() end
    for _, b in ipairs(cadreSuivi.boutons) do b:Hide() end
    for _, b in ipairs(cadreSuivi.entetes or {}) do b:Hide() end
    for _, f in ipairs(cadreSuivi.filets or {}) do f:Hide() end
    if cadreSuivi.filetCommandes then cadreSuivi.filetCommandes:Hide() end
    local vue = Vue()
    TAILLE_LIGNE = TailleDesQuetes()
    producteurs = nil
    local objectifs = suivi.Objectifs()
    -- Les objectifs disparus (atteints, retires) : leur memoire s'efface.
    do
        local presents = {}
        for _, o in ipairs(objectifs or {}) do presents[o.cle] = true end
        for cle in pairs(memoEtapes) do if not presents[cle] then memoEtapes[cle] = nil end end
        for cle in pairs(memoMatieres) do if not presents[cle] then memoMatieres[cle] = nil end end
    end
    local g = NS.base.ReglagesGeneraux()
    cadreSuivi.replier:SetNormalTexture(g.suiviReplie and "Interface\\Buttons\\UI-PlusButton-Up"
        or "Interface\\Buttons\\UI-MinusButton-Up")
    if g.suiviReplie then
        -- Replie : une ligne de resume, la moyenne des objectifs.
        for _, b in pairs(cadreSuivi.vues) do b:Hide() end
        if cadreSuivi.filetHaut then cadreSuivi.filetHaut:Hide() end
        cadreSuivi.tout:Hide()
        cadreSuivi.guider:Hide()
        local texte = L.GOAL_NONE_SHORT
        if #objectifs > 0 then
            local somme = 0
            for _, o in ipairs(objectifs) do somme = somme + o.pct end
            texte = string.format(L.TRACK_FOLDED_GOALS, #objectifs, math.floor(somme / #objectifs * 100 + 0.5))
        end
        cadreSuivi.resume:SetText(texte)
        cadreSuivi.resume:Show()
        -- Meme hauteur que le suivi des quetes replie (QuestCore).
        cadreSuivi:SetHeight(100)
        return
    end
    cadreSuivi.resume:Hide()
    local deLOnglet = DeLOnglet(objectifs, vue)
    local comptes = { fabrications = 0, commandes = 0, progressions = 0, caisses = 0 }
    for _, o in ipairs(objectifs) do comptes[OngletDe(o)] = comptes[OngletDe(o)] + 1 end
    for cle, b in pairs(cadreSuivi.vues) do
        b:Compter(comptes[cle])
        b:Choisir(cle == vue)
        b:Show()
    end
    if cadreSuivi.filetHaut then cadreSuivi.filetHaut:Show() end
    local y = HAUT_ONGLETS
    y = DessinerObjectifs(y, deLOnglet, vue)
    -- Tout ouvrir / tout fermer : selon ce qui est deja ouvert.
    local ouverts, tousOuverts = Ouverts(), #deLOnglet > 0
    for _, o in ipairs(deLOnglet) do if not ouverts[o.cle] then tousOuverts = false end end
    cadreSuivi.tout.ouvrir = not tousOuverts
    cadreSuivi.tout:SetText(tousOuverts and L.TRACK_CLOSE_ALL or L.TRACK_OPEN_ALL)
    cadreSuivi.tout:SetShown(#deLOnglet > 1)
    -- Guidage possible si une matiere qui manque aux objectifs de l'onglet,
    -- et que le personnage sait recolter, a un lieu connu.
    -- Un seul moyen de guider : la petite carte de chaque fabrication (un
    -- objectif precis). Plus de bouton Guider pour tout l'onglet, qui
    -- faisait doublon et brouillait lequel etait en cours.
    cadreSuivi.guider:Hide()
    if #deLOnglet > 1 then y = y + 26 end
    -- Hauteur figee tant qu'un objectif est deplie et que les memes objectifs
    -- sont la : elle peut grandir, jamais retrecir. Un objectif atteint (ou
    -- un autre onglet) libere la hauteur.
    local h = 24 + NS.charte.MARGE + y + NS.charte.MARGE + 4
    local cles = { vue }
    local deplie = false
    for _, o in ipairs(deLOnglet) do
        table.insert(cles, tostring(o.cle))
        if ouverts[o.cle] then deplie = true end
    end
    local signature = table.concat(cles, "|")
    if deplie and cadreSuivi.hauteurFigee and cadreSuivi.signatureFigee == signature then
        h = math.max(h, cadreSuivi.hauteurFigee)
    end
    cadreSuivi.hauteurFigee = deplie and h or nil
    cadreSuivi.signatureFigee = signature
    cadreSuivi:SetHeight(h)
end

-- Affichage permanent (reglage) : le suivi se montre des la connexion, meme
-- sans rien ramasse ; sinon il attend le premier objet utile.
function suivi.Permanent() return NS.base.ReglagesGeneraux().suiviPermanent == true end

function suivi.Demarrer()
    if Actif() and suivi.Permanent() then suivi.Montrer() end
end

function suivi.Montrer()
    cadreSuivi = cadreSuivi or Construire()
    suivi.Dessiner()
    cadreSuivi:Show()
end

function suivi.Reinitialiser()
    local d = CraftCoreDB
    local cle = NS.ClePersonnage and NS.ClePersonnage() or "?"
    if type(d) == "table" and d.suiviRecolte then d.suiviRecolte[cle] = nil end
    suivi.Dessiner()
end

-- Appele apres chaque releve des sacs avec ce qui vient d'y arriver.
function suivi.ObjetsArrives(arrives)
    if not Actif() or type(arrives) ~= "table" then return end
    local session = Session()
    local change = false
    for objet, n in pairs(arrives) do
        local cle = NS.ClePersonnage and NS.ClePersonnage()
        local ok, lignes = pcall(NS.base.AvecPersonnage, cle, Utilite, objet)
        if ok and #lignes > 0 then
            local e = session.objets[objet] or { n = 0 }
            e.n = (e.n or 0) + n
            session.ordre = (session.ordre or 0) + 1
            e.ordre = session.ordre
            e.lignes = lignes
            session.objets[objet] = e
            change = true
        elseif not ok and NS.base.NoterIncident then
            NS.base.NoterIncident("suivi de recolte", lignes)
        end
    end
    if change then
        suivi.Montrer()
    elseif cadreSuivi and cadreSuivi:IsShown() and Vue() == "objectifs" then
        -- Les pourcentages suivent les sacs, meme pour un objet sans autre usage.
        suivi.Dessiner()
    end
end

-- ---------------------------------------------------------------------------
-- Fond du suivi (gris, parchemin ou illustre), commun a la suite : pose
-- apres chaque rendu ; sur parchemin, les textes passent a l'encre.
-- ---------------------------------------------------------------------------

local DessinerSansFond = suivi.Dessiner
suivi.Dessiner = function(...)
    DessinerSansFond(...)
    if not cadreSuivi or not NS.charte.HabillerSuivi then return end
    local ok, souci = pcall(function()
        local parchemin = NS.charte.HabillerSuivi(cadreSuivi)
        NS.charte.EncrerTextes(cadreSuivi.textes, parchemin)
        local autres = { cadreSuivi.resume }
        for _, b in ipairs(cadreSuivi.boutons or {}) do table.insert(autres, b.nom) end
        NS.charte.EncrerTextes(autres, parchemin)
    end)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("fond du suivi", souci) end
end
if NS.charte.SurFondDesSuivis then NS.charte.SurFondDesSuivis(function() suivi.Dessiner() end) end

-- ---------------------------------------------------------------------------
-- Lieux de recolte : ou chaque matiere a ete ramassee (noeuds d'herbes, de
-- minerai, coffres, peche), pour les afficher sur la carte de MapCore.
-- Points proches fusionnes ; au plus 60 lieux par matiere et par carte.
-- ---------------------------------------------------------------------------

local RAYON_FUSION = 0.012

-- Metier de recolte d'une matiere : "herbes" (herboristerie), "minerais"
-- (minage : minerais, pierres, gemmes) ou nil (autre chose, ex. un coffre).
-- Herbes, minerais, pierres et gemmes du jeu d'origine : reconnus d'emblee,
-- meme pour les lieux notes avant que le metier ne soit memorise.
local CONNUS = {}
for _, id in ipairs({ 765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819,
    3820, 3821, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468, 19726 }) do
    CONNUS[id] = "herbes"
end
for _, id in ipairs({ 2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370, 2835, 2836, 2838, 7912, 12365,
    774, 818, 1206, 1210, 1529, 1705, 3864, 7909, 7910, 12361, 12364, 12799, 12800 }) do
    CONNUS[id] = "minerais"
end

-- Ce qui a ete appris en recoltant (sort lance juste avant le butin) fait
-- foi ; a defaut, la classe de l'objet.
local function MetierDeMatiere(objet)
    local d = CraftCoreDB
    local appris = type(d) == "table" and type(d.metierObjet) == "table" and d.metierObjet[objet]
    if appris then return appris end
    if CONNUS[objet] then return CONNUS[objet] end
    local info = NS.Lecture("C_Item.GetItemInfoInstant", "GetItemInfoInstant")
    local _, _, _, _, _, classe, sousClasse = NS.Appeler(info, objet)
    if classe == 7 and sousClasse == 9 then return "herbes" end
    if (classe == 7 and sousClasse == 7) or classe == 3 then return "minerais" end
    return nil
end
suivi.MetierDeMatiere = MetierDeMatiere

-- Dernier sort de recolte lance : Cueillette (herboristerie) ou Minage, par
-- leur nom dans la langue du jeu, tous rangs confondus.
local dernierSort = { metier = nil, quand = 0 }
local function NomDeSort(id)
    local f = NS.Lecture("C_Spell.GetSpellName")
    local nom = f and NS.Appeler(f, id)
    if not nom then nom = NS.Appeler(NS.Lecture("GetSpellInfo"), id) end
    return nom
end
local ecouteSorts = CreateFrame("Frame")
pcall(ecouteSorts.RegisterUnitEvent or ecouteSorts.RegisterEvent, ecouteSorts, "UNIT_SPELLCAST_SUCCEEDED", "player")
ecouteSorts:SetScript("OnEvent", function(_, _, _, _, idSort)
    local nom = NomDeSort(idSort)
    if not nom then return end
    local metier
    if nom == NomDeSort(2366) then metier = "herbes"
    elseif nom == NomDeSort(2575) then metier = "minerais" end
    if metier then dernierSort.metier, dernierSort.quand = metier, NS.Appeler(GetTime) or 0 end
end)
local function SortRecent()
    local maintenant = NS.Appeler(GetTime) or 0
    if dernierSort.metier and maintenant - dernierSort.quand < 8 then return dernierSort.metier end
    return nil
end

local OterRepere -- plus bas

local function NoterLieux()
    local d = CraftCoreDB
    if type(d) ~= "table" then return end
    local source = NS.Appeler(NS.Lecture("GetLootSourceInfo"), 1)
    local peche = NS.Appeler(NS.Lecture("IsFishingLoot"))
    -- Trace des dernieres ramasses (pour comprendre ce qui n'est pas note).
    pcall(function()
        local trace = { quand = NS.Horodatage(), source = tostring(source), sort = tostring(SortRecent()) }
        for slot = 1, tonumber(NS.Appeler(NS.Lecture("GetNumLootItems"))) or 0 do
            local lien = NS.Appeler(NS.Lecture("GetLootSlotLink"), slot)
            local objet = type(lien) == "string" and tonumber(string.match(lien, "item:(%d+)"))
            if objet then table.insert(trace, objet .. "=" .. tostring(MetierDeMatiere(objet))) end
        end
        d.traceLieux = type(d.traceLieux) == "table" and d.traceLieux or {}
        table.insert(d.traceLieux, trace)
        while #d.traceLieux > 12 do table.remove(d.traceLieux, 1) end
    end)
    if not peche and not (type(source) == "string" and string.find(source, "^GameObject")) then return end
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carte and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
    if type(pos) ~= "table" or not pos.GetXY then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    d.lieux = d.lieux or {}
    for slot = 1, tonumber(NS.Appeler(NS.Lecture("GetNumLootItems"))) or 0 do
        local lien = NS.Appeler(NS.Lecture("GetLootSlotLink"), slot)
        local objet = type(lien) == "string" and tonumber(string.match(lien, "item:(%d+)"))
        local metier = objet and (peche and "peche" or SortRecent() or MetierDeMatiere(objet))
        if metier then
            pcall(OterRepere, carte, x, y, metier)
            -- Appris pour de bon : sert aussi aux lieux deja notes de cet objet.
            if peche or SortRecent() then
                d.metierObjet = d.metierObjet or {}
                d.metierObjet[objet] = metier
            end
            local parCarte = d.lieux[objet] or {}
            d.lieux[objet] = parCarte
            local liste = parCarte[carte] or {}
            parCarte[carte] = liste
            local fusion
            for _, l in ipairs(liste) do
                if math.abs(l[1] - x) < RAYON_FUSION and math.abs(l[2] - y) < RAYON_FUSION then fusion = l break end
            end
            if fusion then
                fusion[3] = (fusion[3] or 1) + 1
            elseif #liste < 60 then
                table.insert(liste, { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, 1, metier })
            end
        end
    end
end

-- Noeud qu'on ne peut pas recolter ("Requiert Minage") : on note quand meme
-- l'endroit, pour y revenir avec un personnage qui a le metier. Le nom du
-- noeud vient de l'infobulle du jeu quand elle est affichee. Une vraie
-- recolte au meme endroit remplace ensuite le repere.
local NOMS_METIER = { herbes = { 2366, "Herboristerie", "Herbalism" }, minerais = { 2575, "Minage", "Mining" } }
local ICONES_METIER = { herbes = "Interface\\Icons\\Trade_Herbalism", minerais = "Interface\\Icons\\Trade_Mining" }

local function MetierExige(message)
    if type(message) ~= "string" then return nil end
    for metier, noms in pairs(NOMS_METIER) do
        for _, n in ipairs(noms) do
            local nom = type(n) == "number" and NomDeSort(n) or n
            if nom and nom ~= "" and string.find(message, nom, 1, true) then return metier end
        end
    end
    return nil
end

local function NoterNoeudRepere(message, metierConnu, nomConnu)
    local metier = metierConnu or MetierExige(message)
    local d = CraftCoreDB
    if not metier or type(d) ~= "table" then return end
    local carte = NS.Appeler(NS.Lecture("C_Map.GetBestMapForUnit"), "player")
    local pos = carte and NS.Appeler(NS.Lecture("C_Map.GetPlayerMapPosition"), carte, "player")
    if type(pos) ~= "table" or not pos.GetXY then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    local nom = nomConnu
    local tt = _G.GameTooltip
    local ligne = _G.GameTooltipTextLeft1
    if not nom and tt and tt:IsShown() and ligne and ligne.GetText then nom = ligne:GetText() end
    d.noeuds = d.noeuds or {}
    local liste = d.noeuds[carte] or {}
    d.noeuds[carte] = liste
    for _, l in ipairs(liste) do
        if l[4] == metier and math.abs(l[1] - x) < RAYON_FUSION and math.abs(l[2] - y) < RAYON_FUSION then
            l[5] = l[5] or nom
            return
        end
    end
    if #liste < 200 then
        table.insert(liste, { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, 1, metier, nom })
    end
end

-- Recolte faite : le repere au meme endroit n'a plus lieu d'etre.
OterRepere = function(carte, x, y, metier)
    local liste = type(CraftCoreDB) == "table" and CraftCoreDB.noeuds and CraftCoreDB.noeuds[carte]
    for i = #(liste or {}), 1, -1 do
        local l = liste[i]
        if l[4] == metier and math.abs(l[1] - x) < RAYON_FUSION * 2 and math.abs(l[2] - y) < RAYON_FUSION * 2 then
            table.remove(liste, i)
        end
    end
end

-- Debut d'une cueillette ou d'un minage : le noeud est note tout de suite,
-- avec son nom (la cible du sort). Si quelqu'un l'a pris avant nous, le
-- repere reste ; si la recolte aboutit, le vrai lieu le remplace.
local function NoterNoeudVise(cible, idSort)
    -- En combat, le jeu peut rendre ces valeurs secretes : on ne les lit pas.
    local secret = _G.issecretvalue
    if secret and (secret(cible) or secret(idSort)) then return end
    local nom = NomDeSort(idSort)
    local metier = nom and ((nom == NomDeSort(2366) and "herbes") or (nom == NomDeSort(2575) and "minerais"))
    if not metier then return end
    NoterNoeudRepere(nil, metier, type(cible) == "string" and cible ~= "" and cible or nil)
    if _G.CraftCoreAPI and _G.CraftCoreAPI.OublierLieux then _G.CraftCoreAPI.OublierLieux() end
end

local ecouteVise = CreateFrame("Frame")
pcall(ecouteVise.RegisterUnitEvent or ecouteVise.RegisterEvent, ecouteVise, "UNIT_SPELLCAST_SENT", "player")
ecouteVise:SetScript("OnEvent", function(_, _, unite, cible, _, idSort)
    if unite ~= "player" then return end
    local ok, souci = pcall(NoterNoeudVise, cible, idSort)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("noeud vise", souci) end
end)

local ecouteErreurs = CreateFrame("Frame")
pcall(ecouteErreurs.RegisterEvent, ecouteErreurs, "UI_ERROR_MESSAGE")
ecouteErreurs:SetScript("OnEvent", function(_, _, a, b)
    -- Selon la version du jeu : (type, message) ou (message).
    local message = type(b) == "string" and b or a
    local ok, souci = pcall(NoterNoeudRepere, message)
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("noeud repere", souci) end
end)

local ecouteLieux = CreateFrame("Frame")
pcall(ecouteLieux.RegisterEvent, ecouteLieux, "LOOT_OPENED")
ecouteLieux:SetScript("OnEvent", function()
    local ok, souci = pcall(NoterLieux)
    if _G.CraftCoreAPI and _G.CraftCoreAPI.OublierLieux then _G.CraftCoreAPI.OublierLieux() end
    if not ok and NS.base.NoterIncident then NS.base.NoterIncident("lieux de recolte", souci) end
end)

-- Pour MapCore : les lieux connus sur une carte, { objet, x, y, n }.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
-- Le resultat est garde 3 secondes par carte : la minicarte le demande dix
-- fois par seconde.
local lieuxEnCache, lieuxCarte, lieuxQuand = nil, nil, 0
local ConstruireLieux
_G.CraftCoreAPI.Lieux = function(carte)
    local maintenant = NS.Appeler(GetTime) or 0
    if lieuxEnCache and lieuxCarte == carte and maintenant - lieuxQuand < 3 then return lieuxEnCache end
    lieuxEnCache, lieuxCarte, lieuxQuand = ConstruireLieux(carte), carte, maintenant
    return lieuxEnCache
end
_G.CraftCoreAPI.OublierLieux = function() lieuxEnCache = nil end
ConstruireLieux = function(carte)
    local liste = {}
    local d = CraftCoreDB
    for objet, parCarte in pairs(type(d) == "table" and d.lieux or {}) do
        for _, l in ipairs(parCarte[carte] or {}) do
            local metier = l[4] or MetierDeMatiere(objet)
            if metier then
                table.insert(liste, { objet = objet, x = l[1], y = l[2], n = l[3] or 1, metier = metier,
                    nomType = NS.inventaire.NomDObjet(objet) })
            end
        end
    end
    -- Noeuds reperes sans pouvoir les recolter : symbole du metier.
    for _, l in ipairs(type(d) == "table" and d.noeuds and d.noeuds[carte] or {}) do
        table.insert(liste, { x = l[1], y = l[2], n = l[3] or 1, metier = l[4], nom = l[5], repere = true,
            icone = ICONES_METIER[l[4]], nomType = l[5] })
    end
    return liste
end

-- Metiers de recolte a proposer en filtre sur les cartes : ceux du
-- personnage (herboristerie 182, minage 186, peche 356), et ceux dont des
-- lieux sont deja notes.
local LIGNES_RECOLTE = { herbes = "182", minerais = "186", peche = "356" }
-- Le personnage connecte a-t-il ce metier de recolte ? Sans lui, ni filtre
-- ni lieux de ce metier sur les cartes.
_G.CraftCoreAPI.ARecolte = function(metier)
    local fiche = NS.base.Personnage and NS.base.Personnage()
    local siens = fiche and type(fiche.metiers) == "table" and fiche.metiers
    return siens and siens[LIGNES_RECOLTE[metier] or ""] ~= nil or false
end
_G.CraftCoreAPI.MetierDeRecolte = function(metier) return _G.CraftCoreAPI.ARecolte(metier) end
_G.CraftCoreAPI.Objet = function(objet)
    if type(objet) == "string" then return nil end
    return NS.inventaire.NomDObjet(objet), NS.Appeler(NS.jeu.iconeObjet, objet)
end

-- ---------------------------------------------------------------------------
-- Lieux de recolte des matieres qui manquent : la ou on les a deja recoltees
-- (tous personnages), et les noeuds reperes sans pouvoir les recolter. Le
-- guidage lui-meme est un objectif de la suite (UI/Guidage.lua).
-- ---------------------------------------------------------------------------

-- Lieux { carte, x, y, objet, cle } des objets de l'ensemble { [objet] = n }.
function suivi.LieuxDe(ensemble)
    local liste = {}
    local d = CraftCoreDB
    -- Les noeuds vus sans pouvoir les recolter ("Minage requis", ou deja pris)
    -- comptent aussi, par leur nom : "Filon de cuivre" donne du "Minerai de
    -- cuivre" (meme fin de nom), une plante porte le nom de l'herbe.
    local function Fin(nom)
        nom = string.lower(tostring(nom or ""))
        return (string.match(nom, "^%S+%s+(.+)$")) or nom
    end
    local function Donne(nomNoeud, objet)
        if not nomNoeud then return false end
        local nomObjet = NS.inventaire.NomDObjet(objet)
        if not nomObjet then return false end
        local a, b = string.lower(nomNoeud), string.lower(nomObjet)
        return a == b or Fin(a) == Fin(b)
    end
    for objet in pairs(ensemble or {}) do
        local metier = MetierDeMatiere(objet)
        for carte, noeuds in pairs(metier and type(d) == "table" and d.noeuds or {}) do
            for _, l in ipairs(noeuds) do
                if l[4] == metier and Donne(l[5], objet) then
                    table.insert(liste, { carte = carte, x = l[1], y = l[2], objet = objet,
                        cle = objet .. ":n" .. carte .. ":" .. l[1] .. ":" .. l[2] })
                end
            end
        end
    end
    for objet in pairs(ensemble or {}) do
        for carte, lieux in pairs(type(d) == "table" and d.lieux and d.lieux[objet] or {}) do
            for _, l in ipairs(lieux) do
                table.insert(liste, { carte = carte, x = l[1], y = l[2], objet = objet,
                    cle = objet .. ":" .. carte .. ":" .. l[1] .. ":" .. l[2] })
            end
        end
    end
    return liste
end

local function ManquesDe(objectifs)
    local manques = {}
    for _, o in ipairs(objectifs or {}) do
        for _, m in ipairs(o.matieres or {}) do
            if (m.manque or 0) > 0 then manques[m.objet] = (manques[m.objet] or 0) + m.manque end
        end
    end
    return manques
end

-- Lieux des matieres qui manquent a ces objectifs.
function suivi.LieuxManquants(objectifs)
    local manques = ManquesDe(objectifs)
    suivi.matieresManquantes = manques
    return suivi.LieuxDe(manques)
end

-- Les memes, seulement pour ce que le personnage sait recolter.
function suivi.LieuxRecoltables(objectifs)
    local voulus = {}
    local api = _G.CraftCoreAPI
    for objet, n in pairs(ManquesDe(objectifs)) do
        local metier = MetierDeMatiere(objet)
        if metier and api and api.ARecolte and api.ARecolte(metier) then voulus[objet] = n end
    end
    return suivi.LieuxDe(voulus)
end

-- Pour la vue d'ensemble de MapCore : le circuit de recolte (lieux connus
-- des matieres qui manquent), et son guidage.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
_G.CraftCoreAPI.CircuitRecolte = function()
    local ok, objectifs = pcall(suivi.Objectifs)
    local lieux = ok and suivi.LieuxManquants(objectifs) or {}
    if #lieux == 0 then return nil end
    local matieres = {}
    for _, l in ipairs(lieux) do matieres[l.objet] = true end
    local n = 0
    for _ in pairs(matieres) do n = n + 1 end
    local S = NS.suite or _G.CoreSuite
    return { lieux = #lieux, matieres = n, guide = S and S.GuidageActif and S.GuidageActif("CraftCore") or false }
end

-- Ce guidage de recolte precis (par defaut : celui de l'onglet affiche).
function suivi.EnGuidage(params)
    return NS.guidage and NS.guidage.EstActif and NS.guidage.EstActif(params or suivi.ParamsOnglet()) or false
end

-- ---------------------------------------------------------------------------
-- Annonce : un projet (ou un rang vise) arrive a 100 %. Le meme bandeau que
-- l'avancement des quetes de QuestCore (memes reglages, meme place) ; sans
-- QuestCore, un message en haut de l'ecran et dans la discussion.
-- ---------------------------------------------------------------------------

local etatsAnnonce, premierPassage = {}, true
local function Annoncer(titre, detail, detail2)
    if NS.Trace then NS.Trace("annonce : " .. tostring(titre)) end
    local qc = _G.QuestCoreAPI
    if qc and qc.Bandeau then
        local ok, montre = pcall(qc.Bandeau, titre, detail, true, detail2)
        if ok and montre then return end
    end
    local texte = titre .. " : " .. detail .. (detail2 and (". " .. detail2) or "")
    if _G.UIErrorsFrame then pcall(_G.UIErrorsFrame.AddMessage, _G.UIErrorsFrame, texte, 1, 0.82, 0) end
    NS.Dire(texte)
end

local resumesAnnonce = {}
-- Une fabrication en cours (incantation, ou serie pas finie) : les annonces
-- attendent la fin, pour feliciter une fois tout fabrique.
local function FabricationEnCours()
    local okC, sort = pcall(UnitCastingInfo, "player")
    if okC and sort ~= nil then return true end
    local A = NS.actions
    local serie = A and A.serie
    local recente = A and A.derniereFabrication and ((NS.Appeler(GetTime) or 0) - A.derniereFabrication) < 10
    return serie ~= nil and recente and (serie.reussis or 0) < (serie.total or 1)
end

local function Verifier()
    local L = NS.L
    if not premierPassage and FabricationEnCours() then return "attente" end
    local ok, objectifs = pcall(suivi.Objectifs)
    if not ok then return end
    local vus = {}
    local function Vendu(objet)
        local r = NS.recettes
        if not (r and r.EstVenduPartout) then return false end
        local okV, oui = pcall(r.EstVenduPartout, objet)
        return okV and oui == true
    end
    local function Liste(matieres)
        local t = {}
        for k, m in ipairs(matieres) do
            if k > 3 then t[#t + 1] = "..." break end
            t[#t + 1] = string.format("%s x%d", NS.inventaire.NomDObjet(m.objet) or ("#" .. tostring(m.objet)), m.manque)
        end
        return table.concat(t, ", ")
    end
    for _, o in ipairs(objectifs or {}) do
        -- Ce qui manque encore : a acheter chez un marchand, a recolter
        -- (herbes, minerais), ou autre chose (butin, fabrication...).
        local aAcheter, autres, recoltables, recoltesManquantes = {}, {}, 0, 0
        for _, m in ipairs(o.matieres or {}) do
            local recolte = MetierDeMatiere(m.objet) ~= nil
            if recolte then
                recoltables = recoltables + 1
                if (m.manque or 0) > 0 then recoltesManquantes = recoltesManquantes + 1 end
            end
            if (m.manque or 0) > 0 then
                if Vendu(m.objet) then table.insert(aAcheter, m)
                elseif not recolte then table.insert(autres, m) end
            end
        end
        local etat = "encours"
        if o.atteint then etat = "atteint"
        elseif (o.pct or 0) >= 1 then etat = "reuni"
        elseif recoltesManquantes == 0 and #autres == 0 and #aAcheter > 0 then etat = "achats"
        elseif recoltables > 0 and recoltesManquantes == 0 and #autres > 0 then etat = "recolte" end
        local avant = etatsAnnonce[o.cle]
        vus[o.cle] = true
        etatsAnnonce[o.cle] = etat
        local titre = (o.genre == "projet" and not o.rapides) and string.format(L.ANNOUNCE_PROJECT, o.titreAnnonce or o.nom) or o.nom
        resumesAnnonce[o.cle] = { titre = o.commande and o.nom or titre,
            felicitation = (o.commande and L.ANNOUNCE_DONE_ORDER) or (o.groupe == "progression" and L.ANNOUNCE_DONE_PROG) or L.ANNOUNCE_DONE_PROJECT,
            quoi = #(o.fabriquer or {}) > 0 and table.concat(o.fabriquer, ", ") or nil }
        if not premierPassage and avant and avant ~= etat and (etat == "achats" or etat == "recolte") then
            Annoncer(titre, L.ANNOUNCE_GATHERED, string.format(etat == "achats" and L.ANNOUNCE_BUY or L.ANNOUNCE_LEFT,
                Liste(etat == "achats" and aAcheter or autres)))
        elseif not premierPassage and avant and avant ~= etat and etat ~= "encours" then
            if o.genre == "projet" then
                local quoi = #(o.fabriquer or {}) > 0 and table.concat(o.fabriquer, ", ")
                    .. (((o.nLignes or 0) > #o.fabriquer) and ", ..." or "") or nil
                Annoncer(o.rapides and o.nom or string.format(L.ANNOUNCE_PROJECT, o.titreAnnonce or o.nom), L.ANNOUNCE_100,
                    quoi and string.format(L.ANNOUNCE_CRAFT, quoi) or L.ANNOUNCE_CRAFT_ANY)
            elseif o.genre == "progression" then
                if etat == "atteint" then
                    Annoncer(o.nom, L.ANNOUNCE_RANK_DONE, nil)
                elseif avant == "encours" then
                    Annoncer(o.nom, L.ANNOUNCE_100, L.ANNOUNCE_RANK_GO)
                end
            end
        end
    end
    -- Un objectif tout juste fabrique disparait du suivi : bravo, au milieu
    -- de l'ecran, avec ce qui a ete fait. Seulement juste apres une
    -- fabrication (pas quand on supprime un projet a la main).
    local recent = NS.actions and NS.actions.derniereFabrication
        and ((NS.Appeler(GetTime) or 0) - NS.actions.derniereFabrication) < 30
    for cle in pairs(etatsAnnonce) do
        if not vus[cle] then
            local r = resumesAnnonce[cle]
            if recent and r and etatsAnnonce[cle] == "reuni" then
                Annoncer(r.titre, r.felicitation, r.quoi and string.format(L.ANNOUNCE_MADE, r.quoi) or nil)
            end
            etatsAnnonce[cle] = nil
            resumesAnnonce[cle] = nil
        end
    end
    premierPassage = false
end

local ecouteAnnonce = CreateFrame("Frame")
local annonceDans
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(ecouteAnnonce.RegisterEvent, ecouteAnnonce, e)
end
-- Au plus une verification toutes les 2 secondes (le sac change souvent).
ecouteAnnonce:SetScript("OnEvent", function() annonceDans = annonceDans or 2 end)
ecouteAnnonce:SetScript("OnUpdate", function(_, ecoule)
    if not annonceDans then return end
    annonceDans = annonceDans - (ecoule or 0)
    if annonceDans > 0 then return end
    annonceDans = nil
    local okV, souci = pcall(Verifier)
    if okV and souci == "attente" then annonceDans = 1 return end
    if not okV and NS.base.NoterIncident then NS.base.NoterIncident("annonce d'objectif", souci) end
end)
suivi.VerifierAnnonces = Verifier

-- Pour les raccourcis de la suite : montrer ou cacher le suivi de mes
-- fabrications, et ouvrir la page Monter un metier.
_G.CraftCoreAPI = _G.CraftCoreAPI or {}
_G.CraftCoreAPI.BasculerSuivi = function()
    local cadre = _G.CraftCoreSuivi
    if cadre and cadre:IsShown() then cadre:Hide() else suivi.Montrer() end
end
_G.CraftCoreAPI.MonterUnMetier = function() if NS.ecran then NS.ecran.Montrer("progression") end end
