local _, NS = ...

-- Ce que la base de reference (QuestieDB) dit des quetes, et ce qu'on en
-- deduit pour chaque personnage : prerequis, suites, donneurs, objets requis,
-- et qui peut fournir quoi a qui.

NS.ref = {}
local ref = NS.ref

-- Une base de Questie, ou a defaut la copie personnelle du compte (Memoire).
function ref.Base(entite)
    local e = _G[entite]
    if type(e) == "table" and type(e.Get) == "function" then return e end
    return NS.memoire and NS.memoire.Base and NS.memoire.Base(entite) or nil
end

function ref.Disponible()
    return ref.Base("QuestDB") ~= nil
end

local function Lire(entite, id, champ)
    local e = ref.Base(entite)
    if type(e) ~= "table" or type(e.Get) ~= "function" or not id then return nil end
    local ok, v = pcall(e.Get, id, champ)
    if ok then return v end
    return nil
end
ref.Lire = Lire

-- Nom d'une quete : celui du journal s'il est connu, sinon la base.
function ref.NomDeQuete(id, p)
    local q = p and p.quetes and p.quetes[id]
    if q and q.titre then return q.titre end
    return Lire("QuestDB", id, "name") or ("#" .. tostring(id))
end

-- Etat d'une quete pour un personnage : "faite", "en cours" ou "pas faite".
function ref.Etat(p, id)
    if not p or not id then return "pas faite" end
    if p.faites and p.faites[id] then return "faite" end
    if p.quetes and p.quetes[id] then return "en cours" end
    return "pas faite"
end

-- Prerequis : { groupe = { toutes requises }, une = { l'une suffit } }.
function ref.Prerequis(id)
    local groupe = Lire("QuestDB", id, "preQuestGroup")
    local une = Lire("QuestDB", id, "preQuestSingle")
    return type(groupe) == "table" and groupe or {}, type(une) == "table" and une or {}
end

-- Suites : la suivante de la chaine et les quetes que celle-ci debloque.
function ref.Suites(id)
    local liste, vus = {}, {}
    local suivante = Lire("QuestDB", id, "nextQuestInChain")
    if type(suivante) == "number" and suivante > 0 then table.insert(liste, suivante) vus[suivante] = true end
    for _, enfant in ipairs(Lire("QuestDB", id, "childQuests") or {}) do
        if not vus[enfant] then table.insert(liste, enfant) vus[enfant] = true end
    end
    return liste
end

-- Nom d'une zone (AreaTable) par le jeu.
local function NomDeZone(idZone)
    if type(idZone) ~= "number" or idZone <= 0 then return nil end
    local info = NS.Appeler(NS.Lecture("C_Map.GetAreaInfo"), idZone)
    return type(info) == "string" and info or nil
end
ref.NomDeZone = NomDeZone

-- "Nom (Zone)" des PNJ ou objets qui donnent / reprennent une quete.
local function Acteurs(liste)
    local noms = {}
    if type(liste) ~= "table" then return noms end
    for _, idPnj in ipairs(liste[1] or {}) do
        local nom = Lire("NpcDB", idPnj, "name")
        if nom then
            local zone = NomDeZone(Lire("NpcDB", idPnj, "zoneID"))
            table.insert(noms, zone and (nom .. " (" .. zone .. ")") or nom)
        end
    end
    for _, idObjet in ipairs(liste[2] or {}) do
        local nom = Lire("ObjectDB", idObjet, "name")
        if nom then table.insert(noms, nom) end
    end
    for _, idObjetSac in ipairs(liste[3] or {}) do
        local nom = Lire("ItemDB", idObjetSac, "name")
        if nom then table.insert(noms, nom) end
    end
    return noms
end

function ref.Donneurs(id) return Acteurs(Lire("QuestDB", id, "startedBy")) end
function ref.Receveurs(id) return Acteurs(Lire("QuestDB", id, "finishedBy")) end

-- Objets a rapporter pour une quete en cours d'un personnage :
-- { objet, requis, n } ; les objectifs "objet" du journal, dans l'ordre de la
-- base (c'est l'ordre du jeu).
function ref.ObjetsRequis(p, id)
    local resultat = {}
    local objectifs = Lire("QuestDB", id, "objectives")
    local objets = type(objectifs) == "table" and objectifs[3] or nil
    if type(objets) ~= "table" or #objets == 0 then return resultat end
    local q = p and p.quetes and p.quetes[id]
    local duJournal = {}
    for _, o in ipairs(q and q.objectifs or {}) do
        if o.type == "item" then table.insert(duJournal, o) end
    end
    for rang, ligne in ipairs(objets) do
        local objet, requis = ligne[1], tonumber(ligne[3]) or 1
        local o = duJournal[rang]
        table.insert(resultat, { objet = objet, requis = (o and o.requis > 0) and o.requis or requis,
            n = o and o.n or 0 })
    end
    return resultat
end

-- Couleur de difficulte d'une quete pour un niveau de personnage, comme le
-- journal du jeu : rouge, orange, jaune, vert, gris.
function ref.CouleurDeNiveau(niveauQuete, niveauPerso)
    niveauQuete, niveauPerso = tonumber(niveauQuete) or 0, tonumber(niveauPerso) or 0
    if niveauQuete <= 0 or niveauPerso <= 0 then return 1, 0.82, 0 end
    local ecart = niveauQuete - niveauPerso
    if ecart >= 5 then return 1, 0.1, 0.1 end
    if ecart >= 3 then return 1, 0.5, 0.25 end
    if ecart >= -2 then return 1, 1, 0 end
    local vert
    if niveauPerso <= 5 then vert = 5
    elseif niveauPerso <= 39 then vert = math.floor(niveauPerso / 10) + 5
    elseif niveauPerso <= 59 then vert = math.floor(niveauPerso / 5) + 1
    else vert = 9 end
    if -ecart <= vert then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

-- ---------------------------------------------------------------------------
-- Qui peut fournir quoi. Les stocks viennent de CraftCore s'il est actif
-- (sacs et banque de chaque personnage).
-- ---------------------------------------------------------------------------

function ref.StocksDisponibles()
    return type(_G.CraftCoreDB) == "table" and type(_G.CraftCoreDB.personnages) == "table"
end

-- Sacs et banque d'un personnage pour un objet.
function ref.Detenu(cle, objet)
    if not ref.StocksDisponibles() then return 0, 0 end
    local fiche = _G.CraftCoreDB.personnages[cle]
    local ligne = fiche and type(fiche.stocks) == "table" and fiche.stocks[tostring(objet)]
    if type(ligne) ~= "table" then return 0, 0 end
    local conteneurs = type(fiche.conteneurs) == "table" and fiche.conteneurs or {}
    local sacs, banque = 0, 0
    for idConteneur, quantite in pairs(ligne.parConteneur or {}) do
        local c = conteneurs[idConteneur]
        if c and c.source == "banque" then banque = banque + (tonumber(quantite) or 0)
        else sacs = sacs + (tonumber(quantite) or 0) end
    end
    return sacs, banque
end

-- Un objet lie ne s'envoie pas : seuls les objets non lies (ou lies quand
-- equipes) comptent. Inconnu du client : on le garde, avec le doute.
function ref.Envoyable(objet)
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    local r = { NS.Appeler(info, objet) }
    local lien = r[14]
    if lien == 1 or lien == 4 then return false end
    return true
end

function ref.NomDObjet(objet)
    local info = NS.Lecture("C_Item.GetItemInfo", "GetItemInfo")
    local nom = NS.Appeler(info, objet)
    return nom or Lire("ItemDB", objet, "name") or ("#" .. tostring(objet))
end

function ref.IconeDObjet(objet)
    local icone = NS.Appeler(NS.Lecture("C_Item.GetItemIconByID", "GetItemIcon"), objet)
    return icone or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MemeCamp(a, b)
    return not a.faction or not b.faction or a.faction == b.faction
end

-- Besoins de toutes les quetes en cours, personnage par personnage :
-- { cle, quete, objet, manque, n, requis }.
function ref.Besoins()
    local liste = {}
    for _, p in ipairs(NS.base.Persos()) do
        for id, q in pairs(p.quetes or {}) do
            if q.complete ~= true then
                for _, r in ipairs(ref.ObjetsRequis(p, id)) do
                    if r.requis - r.n > 0 then
                        table.insert(liste, { cle = p.cle, perso = p, quete = id, objet = r.objet,
                            manque = r.requis - r.n, n = r.n, requis = r.requis })
                    end
                end
            end
        end
    end
    return liste
end

-- Ce que `p` detient et qui manque a la quete d'un autre personnage du camp.
function ref.CePeutFournir(p)
    local liste = {}
    for _, b in ipairs(ref.Besoins()) do
        if b.cle ~= p.cle and MemeCamp(p, b.perso) then
            local sacs, banque = ref.Detenu(p.cle, b.objet)
            if sacs + banque > 0 and ref.Envoyable(b.objet) then
                b.sacs, b.banque = sacs, banque
                table.insert(liste, b)
            end
        end
    end
    return liste
end

-- Les personnages dont on connait les stocks (CraftCore), avec leur camp.
local function Detenteurs()
    local liste = {}
    if not ref.StocksDisponibles() then return liste end
    for cle, fiche in pairs(_G.CraftCoreDB.personnages) do
        if type(fiche) == "table" then table.insert(liste, { cle = cle, faction = fiche.faction }) end
    end
    return liste
end

-- Ce qui manque aux quetes de `p` et qu'un autre personnage du camp detient.
function ref.CeQuOnPeutLuiFournir(p)
    local liste = {}
    for _, b in ipairs(ref.Besoins()) do
        if b.cle == p.cle then
            for _, autre in ipairs(Detenteurs()) do
                if autre.cle ~= p.cle and MemeCamp(p, autre) then
                    local sacs, banque = ref.Detenu(autre.cle, b.objet)
                    if sacs + banque > 0 and ref.Envoyable(b.objet) then
                        table.insert(liste, { cle = autre.cle, objet = b.objet, quete = b.quete,
                            sacs = sacs, banque = banque, manque = b.manque, n = b.n, requis = b.requis })
                    end
                end
            end
        end
    end
    return liste
end

-- ---------------------------------------------------------------------------
-- Recompenses : texte de l'argent, et bloc d'infobulle.
-- ---------------------------------------------------------------------------

function ref.TexteArgent(cuivre)
    cuivre = tonumber(cuivre) or 0
    local jeu = NS.Lecture("GetCoinTextureString", "C_CurrencyInfo.GetCoinTextureString")
    local texte = jeu and NS.Appeler(jeu, cuivre)
    if texte then return texte end
    local po, pa, pc = math.floor(cuivre / 10000), math.floor(cuivre / 100) % 100, cuivre % 100
    local morceaux = {}
    if po > 0 then table.insert(morceaux, po .. " po") end
    if pa > 0 then table.insert(morceaux, pa .. " pa") end
    if pc > 0 or #morceaux == 0 then table.insert(morceaux, pc .. " pc") end
    return table.concat(morceaux, " ")
end

-- 12450 -> "12 450".
function ref.NombreLisible(n)
    n = math.floor(tonumber(n) or 0)
    -- Toujours groupe par milliers (la fonction du jeu ne le fait pas en
    -- francais dans ce client).
    local texte = tostring(n)
    while true do
        local suite, k = texte:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
        texte = suite
        if k == 0 then break end
    end
    return texte
end

-- "1 po 20 pa, 450 XP" : ce que rapporte une quete, ou nil.
function ref.ResumeRecompenses(q)
    local r = q and q.recompenses
    if not r then return nil end
    local morceaux = {}
    if (r.argent or 0) > 0 then table.insert(morceaux, ref.TexteArgent(r.argent)) end
    if (r.xp or 0) > 0 then table.insert(morceaux, string.format(NS.L.REWARD_XP, r.xp)) end
    if #morceaux == 0 then return nil end
    return table.concat(morceaux, "   ")
end

local function LigneObjet(tt, o)
    local nom = ref.NomDObjet(o.objet)
    local icone = ref.IconeDObjet(o.objet)
    local qualite = select(3, NS.Appeler(NS.Lecture("C_Item.GetItemInfo", "GetItemInfo"), o.objet))
    local r, g, b = 1, 1, 1
    local couleur = qualite and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[qualite]
    if couleur then r, g, b = couleur.r, couleur.g, couleur.b end
    tt:AddLine(string.format("  |T%s:16|t %s%s", tostring(icone), nom, (o.n or 1) > 1 and (" x" .. o.n) or ""), r, g, b)
end

-- Quete qui se fait dans une instance : laquelle, et si elle s'y prend.
function ref.LigneDonjon(tt, id)
    local d = NS.donjons and NS.donjons.DeQuete and NS.donjons.DeQuete(id)
    if not d then return end
    local L = NS.L
    tt:AddLine(ref.IconeDonjon() .. " " .. string.format(L.DUNGEON_QUEST_TIP, d.nom or "?"), 0.78, 0.6, 1, true)
    if NS.donjons.SePrendDedans(id) then tt:AddLine(L.DUNGEON_PICKUP_INSIDE, 0.78, 0.6, 1, true) end
end

-- Icone des quetes de donjon : celle de l'entree de donjon sur la carte.
local iconeDonjon
function ref.IconeDonjon()
    if iconeDonjon then return iconeDonjon end
    local ct = _G.C_Texture
    local ok, info = false, nil
    if ct and ct.GetAtlasInfo then ok, info = pcall(ct.GetAtlasInfo, "Dungeon") end
    iconeDonjon = (ok and info) and "|A:Dungeon:16:16|a" or "|TInterface\\Icons\\INV_Misc_Key_14:14:14|t"
    return iconeDonjon
end

-- Infobulle d'une quete : titre, niveau, puis les recompenses connues.
function ref.InfobulleDeQuete(tt, q, id, p)
    local L = NS.L
    tt:AddLine(q.titre or ref.NomDeQuete(id, p), 1, 0.82, 0)
    if q.niveau and q.niveau > 0 then tt:AddLine(string.format(L.LEVEL, q.niveau), 0.7, 0.7, 0.7) end
    -- Qui donne la quete, comme pour les quetes pas encore prises.
    local donneurs = ref.Donneurs(id)
    if #donneurs > 0 then tt:AddLine(string.format(L.GIVEN_BY, table.concat(donneurs, ", ")), 0.8, 0.8, 0.8, true) end
    ref.LigneDonjon(tt, id)
    local r = q.recompenses
    -- Ce qu'il faut faire (texte du journal), puis le recit, en entier.
    if r and r.but then
        tt:AddLine(" ")
        tt:AddLine(L.QUEST_GOAL, 1, 0.82, 0)
        tt:AddLine(r.but, 1, 1, 1, true)
    end
    if r and r.description then
        tt:AddLine(" ")
        tt:AddLine(L.QUEST_TEXT, 1, 0.82, 0)
        tt:AddLine(r.description, 0.8, 0.8, 0.8, true)
    end
    if not r then
        tt:AddLine(L.REWARD_UNKNOWN, 0.6, 0.6, 0.6, true)
        return
    end
    local resume = ref.ResumeRecompenses(q)
    if resume or #r.objets > 0 or #r.choix > 0 then
        tt:AddLine(" ")
        tt:AddLine(L.REWARDS, 1, 0.82, 0)
        if resume then tt:AddLine("  " .. resume, 1, 1, 1) end
        for _, o in ipairs(r.objets) do LigneObjet(tt, o) end
        if #r.choix > 0 then
            tt:AddLine(L.REWARD_CHOICE, 1, 0.82, 0)
            for _, o in ipairs(r.choix) do LigneObjet(tt, o) end
        end
    else
        tt:AddLine(L.REWARD_NONE, 0.6, 0.6, 0.6)
    end
end


-- ---------------------------------------------------------------------------
-- Recompenses connues de la base, pour une quete pas encore prise :
-- experience (table d'XP de QuestieDB, reduite comme le jeu le fait quand le
-- personnage depasse le niveau de la quete) et objets (index inverse des
-- objets "donnes par une quete", construit en arriere-plan au demarrage).
-- L'argent n'est pas dans la base : il reste inconnu tant que la quete
-- n'est pas dans le journal.
-- ---------------------------------------------------------------------------

local tableXP
local function TableXP()
    if tableXP ~= nil then return tableXP end
    tableXP = false
    local lib = _G.LibQuestieDB
    local mod = lib and lib.Support and lib.Support.Get and lib.Support.Get("QuestXP")
    if mod and type(mod.db) == "table" then tableXP = mod.db end
    return tableXP
end

function ref.XPDeLaBase(id, niveauPerso)
    local t = TableXP()
    local e = t and t[id]
    if type(e) ~= "table" or not tonumber(e[2]) then return nil end
    local xp, niveauQuete = tonumber(e[2]), tonumber(e[1]) or 0
    local ecart = (tonumber(niveauPerso) or 0) - niveauQuete
    if ecart > 5 then
        local facteurs = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
        xp = xp * (facteurs[ecart] or 0.1)
    end
    return math.floor(xp / 5 + 0.5) * 5
end

local objetsParQuete, indexPret = {}, false
function ref.ObjetsDeLaBase(id) return indexPret and objetsParQuete[id] or nil end
function ref.IndexPret() return indexPret end

-- Construit l'index peu a peu, quelques centaines d'objets par image.
function ref.ConstruireIndexRecompenses()
    local base = _G.ItemDB
    if indexPret or not (base and base.GetAllIds) then return end
    local ok, ids = pcall(base.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    local rang, cadre = 1, CreateFrame("Frame")
    cadre:SetScript("OnUpdate", function(self)
        local fin = math.min(#ids, rang + 400)
        for i = rang, fin do
            local objet = ids[i]
            local quetes = Lire("ItemDB", objet, "questRewards")
            if type(quetes) == "table" then
                for _, q in ipairs(quetes) do
                    objetsParQuete[q] = objetsParQuete[q] or {}
                    table.insert(objetsParQuete[q], objet)
                end
            end
        end
        rang = fin + 1
        if rang > #ids then
            indexPret = true
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Infobulle d'une quete pas encore prise : niveau, donneur, recompenses de la base.
function ref.InfobulleDeLaBase(tt, id, p)
    local L = NS.L
    tt:AddLine(ref.NomDeQuete(id, p), 1, 0.82, 0)
    local niveau = Lire("QuestDB", id, "questLevel")
    if niveau then tt:AddLine(string.format(L.LEVEL, niveau), 0.7, 0.7, 0.7) end
    local donneurs = ref.Donneurs(id)
    if #donneurs > 0 then tt:AddLine(string.format(L.GIVEN_BY, table.concat(donneurs, ", ")), 0.8, 0.8, 0.8, true) end
    ref.LigneDonjon(tt, id)
    local xp = ref.XPDeLaBase(id, p and p.niveau)
    local objets = ref.ObjetsDeLaBase(id)
    if xp or objets then
        tt:AddLine(" ")
        tt:AddLine(L.REWARDS, 1, 0.82, 0)
        if xp and xp > 0 then tt:AddLine("  " .. string.format(L.REWARD_XP, xp), 1, 1, 1) end
        for _, objet in ipairs(objets or {}) do LigneObjet(tt, { objet = objet, n = 1 }) end
        tt:AddLine(L.REWARD_BASE_NOTE, 0.6, 0.6, 0.6, true)
    end
end
