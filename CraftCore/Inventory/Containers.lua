local _, NS = ...

-- Lecture des conteneurs.
--
-- Rien n'est suppose ici. Les identifiants de conteneurs ne sont pas ecrits en
-- dur : on demande au client lesquels existent, et on retient lesquels ne
-- repondent que banque ouverte. Le releve du 13 novembre 2026 a montre que les
-- anciennes constantes de banque sont absentes de ce client, donc les deviner
-- serait faux.

NS.inventaire = {}
local inventaire = NS.inventaire

-- ---------------------------------------------------------------------------
-- Qui a quoi : une seule facon de le calculer et de l'ecrire, partout.
-- ---------------------------------------------------------------------------

-- Code couleur commun : vert dans les sacs du personnage, or ailleurs (sa
-- banque ou un autre personnage, toujours nomme), rouge manquant.
inventaire.COULEURS = {
    sacs = { 0.31, 0.82, 0.41 },
    ailleurs = { 1, 0.82, 0 },
    manque = { 0.9, 0.3, 0.3 },
    detail = { 0.7, 0.7, 0.7 },
}

-- "Thrall - Serveur" donne "Thrall".
function inventaire.NomCourt(cle)
    return string.match(cle or "", "^(.-)%s*%-") or cle or "?"
end

-- ---------------------------------------------------------------------------
-- Boites aux lettres
-- ---------------------------------------------------------------------------
-- Ce qui attend dans la boite de chaque personnage : releve a chaque
-- ouverture de sa boite (tout ce qu'elle contient, d'ou que ca vienne), plus
-- ce que mes autres personnages lui ont envoye depuis (connu a l'envoi). Un
-- courrier recu d'un inconnu n'est connu qu'a l'ouverture de la boite.
local JOURS_COURRIER = 30

local function Boites()
    local d = CraftCoreDB
    if type(d) ~= "table" then return {} end
    d.boites = type(d.boites) == "table" and d.boites or {}
    return d.boites
end

local function Boite(cle)
    local b = Boites()
    if type(b[cle]) ~= "table" then b[cle] = { objets = {}, envois = {} } end
    b[cle].objets = type(b[cle].objets) == "table" and b[cle].objets or {}
    b[cle].envois = type(b[cle].envois) == "table" and b[cle].envois or {}
    return b[cle]
end

-- Boite du personnage connecte, ouverte : tout ce qu'elle contient.
function inventaire.ReleverBoite()
    local cle = NS.ClePersonnage()
    local nombre, objetJoint = NS.Lecture("GetInboxNumItems"), NS.Lecture("GetInboxItem")
    if not (cle and nombre and objetJoint) then return end
    local n = tonumber((NS.Appeler(nombre))) or 0
    local objets = {}
    for i = 1, n do
        for j = 1, tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16 do
            local _, idObjet, _, quantite = NS.Appeler(objetJoint, i, j)
            idObjet = tonumber(idObjet)
            if idObjet then objets[idObjet] = (objets[idObjet] or 0) + (tonumber(quantite) or 1) end
        end
    end
    local b = Boite(cle)
    b.objets = objets
    b.releve = NS.Appeler(_G.time) or 0
    -- Tout ce qui lui avait ete envoye est desormais dans le releve.
    b.envois = {}
end

-- Envoi reussi d'un de mes personnages a un autre : { [objet] = n }.
function inventaire.NoterEnvoi(cle, objets)
    if not cle or type(objets) ~= "table" then return end
    local copie = {}
    for objet, n in pairs(objets) do copie[tonumber(objet)] = tonumber(n) or 0 end
    table.insert(Boite(cle).envois, { quand = NS.Appeler(_G.time) or 0, objets = copie })
end

-- Quantite d'un objet qui attend dans la boite d'un personnage.
function inventaire.Courrier(fiche, objet)
    local cle = type(fiche) == "table" and fiche.cle or fiche
    local b = cle and Boites()[cle]
    if type(b) ~= "table" then return 0 end
    local id = tonumber(objet)
    if not id then return 0 end
    local total = tonumber(type(b.objets) == "table" and b.objets[id]) or 0
    local maintenant = NS.Appeler(_G.time) or 0
    for _, e in ipairs(type(b.envois) == "table" and b.envois or {}) do
        if maintenant - (e.quand or 0) <= JOURS_COURRIER * 86400 then
            total = total + (tonumber(e.objets and e.objets[id]) or 0)
        end
    end
    return total
end

-- Objets qui attendent dans la boite d'un personnage : { ["id"] = true }.
function inventaire.ObjetsAuCourrier(fiche)
    local cle = type(fiche) == "table" and fiche.cle or fiche
    local b = cle and Boites()[cle]
    local liste = {}
    if type(b) ~= "table" then return liste end
    for id in pairs(type(b.objets) == "table" and b.objets or {}) do liste[tostring(id)] = true end
    for _, e in ipairs(type(b.envois) == "table" and b.envois or {}) do
        for id in pairs(e.objets or {}) do liste[tostring(id)] = true end
    end
    return liste
end

-- Tous les personnages du meme camp que `ref` qui detiennent un objet, `ref`
-- compris, du plus fourni au moins fourni : { cle, nom, sacs, banque,
-- courrier, total }.
function inventaire.Detenteurs(objet, ref)
    ref = ref or NS.base.FicheAffichee()
    local liste = {}
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        local memeCamp = (not ref) or (not ref.faction) or (not fiche.faction) or fiche.faction == ref.faction
        if memeCamp then
            local sacs, banque, courrier = inventaire.SacsEtBanque(fiche, objet)
            if sacs + banque + courrier > 0 then
                table.insert(liste, { cle = fiche.cle, nom = inventaire.NomCourt(fiche.cle),
                    sacs = sacs, banque = banque, courrier = courrier, total = sacs + banque + courrier,
                    estRef = ref and fiche.cle == ref.cle })
            end
        end
    end
    table.sort(liste, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return tostring(a.cle) < tostring(b.cle)
    end)
    return liste
end

-- "3 en sacs, 2 en banque", ou "10 en banque".
function inventaire.TexteSacsBanque(sacs, banque, courrier)
    local L = NS.L
    courrier = tonumber(courrier) or 0
    local morceaux = {}
    if sacs > 0 then table.insert(morceaux, string.format(L.WHERE_BAGS, sacs)) end
    if banque > 0 then table.insert(morceaux, string.format(L.WHERE_BANK, banque)) end
    if courrier > 0 then table.insert(morceaux, string.format(L.WHERE_MAIL or "%d au courrier", courrier)) end
    if #morceaux == 0 then return string.format(L.WHERE_BAGS, 0) end
    return table.concat(morceaux, ", ")
end

-- Ou se trouve un objet, en une ligne : d'abord le personnage `ref`, puis les
-- autres par leur nom. "3 en sacs, Thrall 10".
function inventaire.TexteOuEst(objet, ref)
    local L = NS.L
    ref = ref or NS.base.FicheAffichee()
    local morceaux = {}
    for _, d in ipairs(inventaire.Detenteurs(objet, ref)) do
        if d.estRef then
            if d.sacs > 0 then table.insert(morceaux, 1, string.format(L.WHERE_BAGS, d.sacs)) end
            if d.banque > 0 then table.insert(morceaux, d.sacs > 0 and 2 or 1, string.format(L.WHERE_BANK, d.banque)) end
            if (d.courrier or 0) > 0 then
                table.insert(morceaux, (d.sacs > 0 and 1 or 0) + (d.banque > 0 and 1 or 0) + 1,
                    string.format(L.WHERE_MAIL or "%d au courrier", d.courrier))
            end
        else
            table.insert(morceaux, d.nom .. " " .. d.total)
        end
    end
    return table.concat(morceaux, ", ")
end

-- Plage de balayage. Large volontairement : un identifiant qui ne repond pas
-- est simplement absent, cela ne coute rien.
local ID_MIN, ID_MAX = -5, 20

-- Conteneurs a ne jamais compter comme du stock. Le trousseau de clefs ne
-- contient que des clefs. On cherche d'abord son nom dans l'enumeration du
-- client ; a defaut on retient -5 a -1 hors reserve, d'apres le releve qui l'a
-- vu repondre a -1 avec 32 emplacements.
local function ConteneursAEcarter()
    local ecartes = {}
    local enumeration = NS.Resoudre("Enum.BagIndex")
    if type(enumeration) == "table" then
        for nom, valeur in pairs(enumeration) do
            if type(valeur) == "number" and type(nom) == "string" then
                local minuscule = string.lower(nom)
                if string.find(minuscule, "keyring", 1, true) then
                    ecartes[valeur] = "trousseau"
                end
            end
        end
    end
    if not next(ecartes) then
        ecartes[-1] = "trousseau, d'apres le releve en jeu"
    end
    return ecartes
end

-- Note la forme reelle de la reponse du client, une seule fois, pour qu'elle
-- soit constatee plutot que supposee.
local function NoterFormeDeReponse(reponse)
    local dec = NS.base.Decouverte()
    if not dec or dec.formeInfoEmplacement then return end
    if type(reponse) ~= "table" then
        dec.formeInfoEmplacement = { genre = type(reponse) }
        return
    end
    local champs = {}
    for champ, valeur in pairs(reponse) do
        champs[tostring(champ)] = type(valeur)
    end
    dec.formeInfoEmplacement = { genre = "table", champs = champs }
end

-- Quantite d'une pile. Plusieurs noms de champ sont acceptes : la forme exacte
-- de la reponse de ce client n'est pas encore constatee, et inventer un nom
-- ferait sous-compter les piles en silence.
local function QuantiteDeLaPile(info)
    if type(info) ~= "table" then return nil end
    return tonumber(info.stackCount) or tonumber(info.itemCount) or tonumber(info.count)
end

-- Les conteneurs qui repondent maintenant.
function inventaire.Decouvrir()
    local j = NS.jeu
    if not j.nombreEmplacements then return {} end

    local trouves = {}
    for id = ID_MIN, ID_MAX do
        local emplacements = tonumber(NS.Appeler(j.nombreEmplacements, id))
        if emplacements and emplacements > 0 then
            local entree = { id = id, emplacements = emplacements }
            if j.nomDuConteneur then
                entree.nom = NS.Appeler(j.nomDuConteneur, id)
            end
            trouves[id] = entree
        end
    end
    return trouves
end

-- Releve complet. `banqueOuverte` dit si la banque est accessible a cet
-- instant : c'est ce qui permet de reconnaitre ses conteneurs sans les deviner.
function inventaire.Relever(banqueOuverte)
    local j = NS.jeu
    local fiche = NS.base.Personnage()
    if not fiche then return nil end

    local ecartes = ConteneursAEcarter()
    local conteneurs = inventaire.Decouvrir()
    if not next(conteneurs) then
        -- Aucune lecture n'a repondu : on ne touche pas au dernier releve, qui
        -- vaut mieux qu'un releve vide.
        return nil
    end

    local nouveauxDeBanque = 0
    if banqueOuverte then
        -- Un conteneur qui ne repond que banque ouverte est un conteneur de
        -- banque. Les sacs portes, eux, repondent toujours.
        for id in pairs(conteneurs) do
            if not fiche.conteneursToujoursVus or not fiche.conteneursToujoursVus[tostring(id)] then
                if NS.base.NoterConteneurDeBanque(id) then
                    nouveauxDeBanque = nouveauxDeBanque + 1
                end
            end
        end
    else
        -- Hors banque, ce qui repond est forcement porte par le personnage.
        fiche.conteneursToujoursVus = {}
        for id in pairs(conteneurs) do
            fiche.conteneursToujoursVus[tostring(id)] = true
        end
    end

    -- Ce qui ne repond pas maintenant n'est pas perdu : la banque fermee ne
    -- repond plus, et son contenu doit rester connu avec sa date de releve.
    local ancienStocks = NS.base.StocksDe(fiche)
    local ancienConteneurs = NS.base.ConteneursDe(fiche)

    local stocks = {}
    local nbConteneurs = 0
    local nbObjets = 0
    local quantitesIncertaines = false
    local fichesConteneurs = {}

    for id, entree in pairs(conteneurs) do
        if not ecartes[id] then
            nbConteneurs = nbConteneurs + 1
            local source
            if NS.base.EstConteneurDeBanque(id) then
                source = "banque"
            elseif fiche.conteneursToujoursVus and fiche.conteneursToujoursVus[tostring(id)] then
                source = "sacs"
            else
                source = "inconnu"
            end
            fichesConteneurs[tostring(id)] = {
                emplacements = entree.emplacements,
                nom = entree.nom,
                source = source,
                vuLe = NS.Horodatage(),
            }

            for emplacement = 1, entree.emplacements do
                local objet = tonumber(NS.Appeler(j.objetDeLEmplacement, id, emplacement))
                if objet then
                    local quantite
                    if j.infoDeLEmplacement then
                        local info = NS.Appeler(j.infoDeLEmplacement, id, emplacement)
                        NoterFormeDeReponse(info)
                        quantite = QuantiteDeLaPile(info)
                    end
                    if not quantite then
                        quantite = 1
                        quantitesIncertaines = true
                    end

                    local cle = tostring(objet)
                    local ligne = stocks[cle]
                    if not ligne then
                        ligne = { total = 0, parConteneur = {} }
                        stocks[cle] = ligne
                        nbObjets = nbObjets + 1
                    end
                    ligne.total = ligne.total + quantite
                    local cleConteneur = tostring(id)
                    ligne.parConteneur[cleConteneur] = (ligne.parConteneur[cleConteneur] or 0) + quantite
                end
            end
        end
    end

    -- Report des conteneurs de banque qui n'ont pas repondu ce coup ci, avec
    -- leur contenu et leur date d'origine : banque fermee, ils restent connus.
    -- Seulement la banque : un sac retire ne repond plus non plus, et reporter
    -- son ancien contenu le ferait compter en double une fois range ailleurs.
    for idConteneur, ancienneFiche in pairs(ancienConteneurs) do
        if not fichesConteneurs[idConteneur] and not banqueOuverte
            and type(ancienneFiche) == "table" and ancienneFiche.source == "banque" then
            fichesConteneurs[idConteneur] = ancienneFiche
            for cle, ligne in pairs(ancienStocks) do
                local quantite = ligne.parConteneur and ligne.parConteneur[idConteneur]
                if quantite and quantite > 0 then
                    local nouvelle = stocks[cle]
                    if not nouvelle then
                        nouvelle = { total = 0, parConteneur = {} }
                        stocks[cle] = nouvelle
                    end
                    nouvelle.total = nouvelle.total + quantite
                    nouvelle.parConteneur[idConteneur] = quantite
                end
            end
        end
    end

    nbConteneurs, nbObjets = 0, 0
    for _ in pairs(fichesConteneurs) do nbConteneurs = nbConteneurs + 1 end
    for _ in pairs(stocks) do nbObjets = nbObjets + 1 end

    -- Ce qui vient d'arriver dans les sacs, pour prevenir si un projet
    -- l'attendait. On compare les sacs seuls au releve precedent : ouvrir la
    -- banque n'est pas ramasser. Un objet jamais vu compte aussi, sauf au tout
    -- premier releve, ou tout serait nouveau.
    local function DansLesSacs(ligne, fiches)
        local total = 0
        for idConteneur, quantite in pairs((ligne and ligne.parConteneur) or {}) do
            local fc = fiches[idConteneur]
            if not fc or fc.source ~= "banque" then total = total + quantite end
        end
        return total
    end
    local arrives = {}
    if next(ancienStocks) ~= nil then
        for cle, ligne in pairs(stocks) do
            local gagne = DansLesSacs(ligne, fichesConteneurs)
                - DansLesSacs(ancienStocks[cle], ancienConteneurs)
            if gagne > 0 then
                arrives[tonumber(cle)] = gagne
            end
        end
    end

    fiche.stocks = stocks
    fiche.conteneurs = fichesConteneurs
    fiche.releveLe = NS.Horodatage()
    fiche.quantitesIncertaines = quantitesIncertaines or nil
    fiche.nombreConteneurs = nbConteneurs
    fiche.nombreObjets = nbObjets

    return {
        conteneurs = nbConteneurs,
        objets = nbObjets,
        nouveauxDeBanque = nouveauxDeBanque,
        quantitesIncertaines = quantitesIncertaines,
        arrives = arrives,
    }
end

-- Nom lisible d'un objet, si le client l'a deja en memoire. Sinon son
-- identifiant, jamais un nom invente.
function inventaire.NomDObjet(identifiant)
    local j = NS.jeu
    local id = tonumber(identifiant)
    if not id then return tostring(identifiant) end
    -- La lecture immediate ne renvoie pas le nom mais l'identifiant : seule la
    -- lecture complete donne un nom, et seulement si le client a deja vu l'objet.
    if j.infoObjet then
        local nom = NS.Appeler(j.infoObjet, id)
        if type(nom) == "string" and nom ~= "" then return nom end
    end
    return "objet " .. id
end

-- Total possede de ce cote de la faction. Les calculs passent tous par la :
-- additionner les deux camps donnerait un total qu'on ne peut pas reunir.
function inventaire.TotalPossede(objet)
    return inventaire.APortee(objet) + inventaire.ChezLesAutres(objet)
end

-- Ce que le personnage connecte a reellement sous la main, hors banque : la
-- quantite possedee et la quantite atteignable ne sont pas la meme chose.
function inventaire.DisponibleDansLesSacs(objet)
    local fiche = NS.base.FicheAffichee()
    if not fiche then return 0 end
    local ligne = NS.base.StocksDe(fiche)[tostring(objet)]
    if not ligne then return 0 end
    local conteneurs = NS.base.ConteneursDe(fiche)
    local total = 0
    for idConteneur, quantite in pairs(ligne.parConteneur or {}) do
        local fc = conteneurs[idConteneur]
        if not fc or fc.source ~= "banque" then
            total = total + quantite
        end
    end
    return total
end

-- Trois niveaux, et ils ne disent pas la meme chose.
--
--   a portee  : ce que le personnage connecte a dans ses sacs et sa banque
--   ailleurs  : ce que ses autres personnages de la meme faction detiennent
--   total     : la somme des deux
--
-- On n'additionne jamais les deux factions : rien ne passe de l'une a l'autre.

local function FactionDuPersonnage()
    local fiche = NS.base.FicheAffichee()
    return fiche and fiche.faction or nil
end

-- Une fiche compte-t-elle du cote du personnage affiche ? Seule regle de
-- faction de l'addon : tous les totaux passent par elle. Une fiche sans
-- faction connue est comptee : elle date d'avant que l'addon la releve, et
-- l'ecarter ferait disparaitre des stocks.
function inventaire.MemeCamp(fiche)
    local faction = FactionDuPersonnage()
    if type(fiche) ~= "table" then return false end
    return (not faction) or (not fiche.faction) or fiche.faction == faction
end

-- Tout ce que le personnage connecte detient, sacs et banque confondus.
function inventaire.APortee(objet)
    local fiche = NS.base.FicheAffichee()
    if not fiche then return 0 end
    local ligne = NS.base.StocksDe(fiche)[tostring(objet)]
    return ((ligne and ligne.total) or 0) + inventaire.Courrier(fiche, objet)
end

-- Ce que les autres personnages de la meme faction detiennent.
function inventaire.ChezLesAutres(objet)
    local courant = NS.base.CleAffichee()
    local total = 0
    for _, fiche in ipairs(NS.base.TousLesPersonnages()) do
        if fiche.cle ~= courant then
            if inventaire.MemeCamp(fiche) then
                local ligne = NS.base.StocksDe(fiche)[tostring(objet)]
                total = total + ((ligne and ligne.total) or 0) + inventaire.Courrier(fiche, objet)
            end
        end
    end
    return total
end

-- Sacs et banque d'un objet chez un personnage donne, puis ce qui attend
-- dans sa boite aux lettres.
function inventaire.SacsEtBanque(fiche, objet)
    local courrier = inventaire.Courrier(fiche, objet)
    local ligne = NS.base.StocksDe(fiche)[tostring(objet)]
    if not ligne then return 0, 0, courrier end
    local conteneurs = NS.base.ConteneursDe(fiche)
    local sacs, banque = 0, 0
    for idConteneur, quantite in pairs(ligne.parConteneur or {}) do
        local fc = conteneurs[idConteneur]
        if fc and fc.source == "banque" then banque = banque + quantite else sacs = sacs + quantite end
    end
    return sacs, banque, courrier
end

-- Ce que les autres personnages du meme camp que `ref` detiennent d'un objet,
-- en total et personnage par personnage, pour la colonne et son infobulle.
function inventaire.DetailChezLesAutres(ref, objet)
    local total, detail = 0, {}
    if type(ref) ~= "table" then return total, detail end
    for _, d in ipairs(inventaire.Detenteurs(objet, ref)) do
        if not d.estRef then
            total = total + d.total
            table.insert(detail, d)
        end
    end
    return total, detail
end

-- Somme des deux, c'est a dire ce que le compte possede de ce cote.
function inventaire.TotalDeLaFaction(objet)
    return inventaire.APortee(objet) + inventaire.ChezLesAutres(objet)
end

-- Equipement porte par le personnage connecte, enregistre dans sa fiche.
-- Sans cela, on ne peut ni deduire sa matiere native ni comparer un objet
-- depuis un autre personnage.
function inventaire.ReleverEquipement()
    local fiche = NS.base.Personnage()
    if not fiche then return 0 end
    local j = NS.jeu
    if not j.objetEquipe then return 0 end

    local porte = {}
    local combien = 0
    for _, emplacement in ipairs(NS.emplacements.DuPersonnage) do
        local numero = NS.emplacements.Numero(emplacement.nom)
        if numero then
            local id = tonumber(NS.Appeler(j.objetEquipe, "player", numero))
            if id then
                local lien = j.lienObjetEquipe and NS.Appeler(j.lienObjetEquipe, "player", numero)
                porte[emplacement.nom] = { id = id, lien = type(lien) == "string" and lien or nil, vuLe = NS.Horodatage() }
                combien = combien + 1
            end
        end
    end

    -- Un relevé vide n'efface pas le precedent : mieux vaut un equipement date
    -- qu'aucun equipement.
    if combien > 0 then
        fiche.equipement = porte
    end
    return combien
end

-- ---------------------------------------------------------------------------
-- Composants d'une recette dans une infobulle : pour chacun, ce qu'on a et ce
-- qu'il faut, et quand ce n'est pas dans les sacs du personnage, ou ca se
-- trouve (sa banque, ou tel autre personnage, sacs ou banque).
-- `siIncomplet` : n'ajoute rien quand tout est deja dans les sacs.
-- ---------------------------------------------------------------------------
function inventaire.ComposantsDansLInfobulle(tt, recette, siIncomplet)
    local L = NS.L
    if not (tt and recette and type(recette.composants) == "table" and #recette.composants > 0) then return end
    local moi = NS.base.FicheAffichee()
    if not moi then return end
    local Nom, OuTexte, C = inventaire.NomCourt, inventaire.TexteSacsBanque, inventaire.COULEURS

    local lignes, manque, enSacs = {}, 0, true
    for _, comp in ipairs(recette.composants) do
        local besoin = tonumber(comp.quantite) or 1
        local sacs, banque = inventaire.SacsEtBanque(moi, comp.objet)
        local ailleurs, detail = inventaire.DetailChezLesAutres(moi, comp.objet)
        local total = sacs + banque + ailleurs
        local r, g, b = unpack(C.sacs)
        if total < besoin then
            r, g, b = unpack(C.manque)
            manque = manque + 1
        elseif sacs < besoin then
            r, g, b = unpack(C.ailleurs)
            enSacs = false
        end
        local sous = {}
        if sacs < besoin then
            if banque > 0 then table.insert(sous, { Nom(moi.cle), OuTexte(0, banque) }) end
            for _, d in ipairs(detail) do table.insert(sous, { Nom(d.cle), OuTexte(d.sacs, d.banque) }) end
        end
        table.insert(lignes, { nom = inventaire.NomDObjet(comp.objet),
            compte = string.format("%d / %d", math.min(total, 9999), besoin), r = r, g = g, b = b, sous = sous })
    end
    if siIncomplet and manque == 0 and enSacs then return end

    tt:AddLine(" ")
    tt:AddLine(L.GEAR_REAGENTS, 1, 0.82, 0)
    for _, l in ipairs(lignes) do
        tt:AddDoubleLine("  " .. l.nom, l.compte, 1, 1, 1, l.r, l.g, l.b)
        for _, s in ipairs(l.sous) do
            local d = C.detail
            tt:AddDoubleLine("      " .. s[1], s[2], d[1], d[2], d[3], d[1], d[2], d[3])
        end
    end
    if manque > 0 then
        tt:AddLine(string.format(L.GEAR_REAGENTS_MISSING, manque), unpack(C.manque))
    elseif enSacs then
        tt:AddLine(L.GEAR_REAGENTS_READY, unpack(C.sacs))
    else
        local c = C.ailleurs
        tt:AddLine(L.GEAR_REAGENTS_FETCH, c[1], c[2], c[3], true)
    end
end
