local _, NS = ...

-- Les personnages du compte, tels que toute la suite les connait : nos
-- releves (AchievementCoreDB), QuestCore (quetes faites, race), CraftCore
-- (metiers, recettes, sacs et banque), LegacyCore (niveau, classe). Chaque
-- lecture prend l'add-on qui la donne, sinon notre propre releve.

NS.persos = {}
local persos = NS.persos
local ref = NS.ref

local function DB(nom)
    local d = _G[nom]
    return type(d) == "table" and d or nil
end
local function QC(cle) local d = DB("QuestCoreDB") return d and type(d.persos) == "table" and type(d.persos[cle]) == "table" and d.persos[cle] or nil end
local function CC(cle) local d = DB("CraftCoreDB") return d and type(d.personnages) == "table" and type(d.personnages[cle]) == "table" and d.personnages[cle] or nil end
local function LC(cle) local d = DB("LegacyCoreDB") return d and type(d.persos) == "table" and type(d.persos[cle]) == "table" and d.persos[cle] or nil end
local function AC(cle) local d = DB("AchievementCoreDB") return d and type(d.persos) == "table" and type(d.persos[cle]) == "table" and d.persos[cle] or nil end
persos.QC, persos.CC, persos.LC, persos.AC = QC, CC, LC, AC

local function Faction(f)
    if f == "Alliance" or f == "alliance" then return "Alliance" end
    if f == "Horde" or f == "horde" then return "Horde" end
    return nil
end

-- Jeton de classe d'une fiche de CraftCore (qui note aussi le nom traduit).
local function JetonDeClasse(fiche)
    if type(fiche.jetonClasse) == "string" then return fiche.jetonClasse end
    if type(fiche.classe) ~= "string" then return nil end
    if _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[fiche.classe] then return fiche.classe end
    for _, noms in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(noms) == "table" then
            for jeton, nom in pairs(noms) do if nom == fiche.classe then return jeton end end
        end
    end
    return nil
end

-- Liste memorisee par version des personnages.
local cache, cacheVersion

-- Tous les personnages : { cle, nom, faction, race, classe, niveau, sexe },
-- le connecte d'abord, puis par nom.
function persos.Liste()
    local v = NS.Version("persos")
    if cache and cacheVersion == v then return cache end
    local parCle = {}
    local function Ajouter(cle, info)
        if type(cle) ~= "string" or not cle:find(" %- ") then return end
        local p = parCle[cle]
        if not p then p = { cle = cle, nom = NS.NomCourt(cle) } parCle[cle] = p end
        if not p.faction then p.faction = Faction(info.faction) end
        if not p.race and tonumber(info.race) then p.race = tonumber(info.race) end
        if not p.classe and type(info.classe) == "string" and info.classe ~= "" then p.classe = info.classe end
        local n = tonumber(info.niveau)
        if n and (not p.niveau or n > p.niveau) then p.niveau = n end
        if not p.sexe and tonumber(info.sexe) then p.sexe = tonumber(info.sexe) end
    end
    for cle, f in pairs((DB("AchievementCoreDB") or {}).persos or {}) do
        if type(f) == "table" then Ajouter(cle, f) end
    end
    for cle, f in pairs((DB("QuestCoreDB") or {}).persos or {}) do
        if type(f) == "table" then Ajouter(cle, f) end
    end
    for cle, f in pairs((DB("CraftCoreDB") or {}).personnages or {}) do
        if type(f) == "table" then Ajouter(cle, { faction = f.faction, classe = JetonDeClasse(f), niveau = f.niveau }) end
    end
    for cle, f in pairs((DB("LegacyCoreDB") or {}).persos or {}) do
        if type(f) == "table" then Ajouter(cle, { classe = f.classe, niveau = f.niveau }) end
    end
    -- Sans faction notee : celle de sa race.
    for _, p in pairs(parCle) do
        if not p.faction and p.race and ref.RACE[p.race] then p.faction = ref.RACE[p.race].faction end
    end
    local courant = NS.ClePersonnage()
    -- Un meme nom sous deux royaumes : une ancienne fiche (royaume vide ou
    -- provisoire). On garde celle du royaume actuel, sinon la plus complete.
    local royaume = type(courant) == "string" and courant:match(" %- (.+)$") or nil
    local parNom = {}
    for cle, p in pairs(parCle) do
        local r = cle:match(" %- (.*)$") or ""
        local note = (r == royaume and 100 or 0) + (r ~= "" and 10 or 0) + (p.niveau or 0) / 100
        local deja = parNom[p.nom]
        if not deja or note > deja.note then parNom[p.nom] = { p = p, note = note } end
    end
    local liste = {}
    for _, e in pairs(parNom) do table.insert(liste, e.p) end
    table.sort(liste, function(a, b)
        if (a.cle == courant) ~= (b.cle == courant) then return a.cle == courant end
        return a.cle < b.cle
    end)
    cache, cacheVersion = liste, v
    return liste
end

function persos.Par(cle)
    for _, p in ipairs(persos.Liste()) do if p.cle == cle then return p end end
    return nil
end

function persos.DeFaction(faction)
    local liste = {}
    for _, p in ipairs(persos.Liste()) do if p.faction == faction then table.insert(liste, p) end end
    return liste
end

-- ---------------------------------------------------------------------------
-- Ce que chaque personnage a fait, par source
-- ---------------------------------------------------------------------------

-- Quetes rendues : { [id] = true } (QuestCore et notre releve reunis).
function persos.Quetes(cle)
    local q, a = QC(cle), AC(cle)
    local qf = q and type(q.faites) == "table" and q.faites
    local af = a and type(a.quetes) == "table" and a.quetes
    if qf and not af then return qf end
    if af and not qf then return af end
    if not qf then return {} end
    local t = {}
    for id in pairs(qf) do t[id] = true end
    for id in pairs(af) do t[id] = true end
    return t
end

-- Objets eus au moins une fois : { [id] = true }. Ce que CraftCore voit dans
-- les sacs, la banque et l'equipement s'ajoute a notre memoire et y reste
-- (une fois par version des objets).
local objetsVus = {}
function persos.Objets(cle)
    local a = AC(cle)
    local c = CC(cle)
    local v = NS.Version("objets")
    if c and objetsVus[cle] == v and a and type(a.objets) == "table" then return a.objets end
    objetsVus[cle] = v
    if c then
        local f = NS.base.Fiche(cle)
        local objets = NS.base.Table(f, "objets")
        for id in pairs(type(c.stocks) == "table" and c.stocks or {}) do
            local n = tonumber(id)
            if n and not objets[n] then objets[n] = true end
        end
        for _, e in pairs(type(c.equipement) == "table" and c.equipement or {}) do
            local n = type(e) == "table" and tonumber(e.id)
            if n and not objets[n] then objets[n] = true end
        end
        return objets
    end
    return a and type(a.objets) == "table" and a.objets or {}
end

-- Metiers : { [ligne] = { rang, rangMax, nom } }, le meilleur releve.
function persos.Metiers(cle)
    local t = {}
    local function Prendre(src)
        for ligne, m in pairs(type(src) == "table" and src or {}) do
            local l = tonumber(ligne)
            if l and type(m) == "table" and tonumber(m.rang) then
                local e = t[l]
                if not e or tonumber(m.rang) > e.rang then
                    t[l] = { rang = tonumber(m.rang), rangMax = tonumber(m.rangMax), nom = m.nom }
                end
            end
        end
    end
    local c, a = CC(cle), AC(cle)
    if c then Prendre(c.metiers) end
    if a then Prendre(a.metiers) end
    return t
end

-- Recettes apprises : { [id] = true } (cles numeriques).
function persos.Recettes(cle)
    local t = {}
    local c, a = CC(cle), AC(cle)
    for id, oui in pairs(c and type(c.recettesApprises) == "table" and c.recettesApprises or {}) do
        if oui then t[tonumber(id) or id] = true end
    end
    for id, oui in pairs(a and type(a.recettes) == "table" and a.recettes or {}) do
        if oui then t[tonumber(id) or id] = true end
    end
    return t
end

-- Catalogue des recettes du compte : { [id] = { ligne, nom } }.
function persos.Catalogue()
    local t = {}
    local d = DB("CraftCoreDB")
    if d and type(d.recettes) == "table" then
        local categories = type(d.categoriesParMetier) == "table" and d.categoriesParMetier or {}
        for id, r in pairs(d.recettes) do
            if type(r) == "table" then
                local ligne = tonumber(r.metier)
                if not (ligne and ligne > 0) and r.categorie then ligne = tonumber(categories[tostring(r.categorie)]) end
                if ligne and ligne > 0 then t[tonumber(id) or id] = { ligne = ligne, nom = r.nom } end
            end
        end
    end
    local a = DB("AchievementCoreDB")
    for id, r in pairs(a and type(a.recettes) == "table" and a.recettes or {}) do
        local n = tonumber(id) or id
        if type(r) == "table" and tonumber(r.ligne) and not t[n] then t[n] = { ligne = tonumber(r.ligne), nom = r.nom } end
    end
    return t
end

-- Les autres releves ne viennent que de nous.
local function Champ(cle, champ)
    local a = AC(cle)
    return a and type(a[champ]) == "table" and a[champ] or {}
end
function persos.Exploration(cle) return Champ(cle, "explore") end
function persos.Visites(cle) return Champ(cle, "visites") end
function persos.Instances(cle) return Champ(cle, "instances") end
function persos.Boss(cle) return Champ(cle, "boss") end
function persos.Reputations(cle) return Champ(cle, "reputations") end
function persos.ReputationsDetail(cle) return Champ(cle, "reputationsDetail") end
function persos.JcJ(cle) return Champ(cle, "jcj") end

-- ---------------------------------------------------------------------------
-- Unions par faction, memorisees par version
-- ---------------------------------------------------------------------------

local unions = {}
-- L'union d'un ensemble { [id] = true } sur les personnages d'une liste.
function persos.Union(nom, liste, lecture, version)
    local cle = nom .. ":" .. tostring(version)
    for _, p in ipairs(liste) do cle = cle .. ":" .. p.cle end
    if unions[nom] and unions[nom].cle == cle then return unions[nom].t end
    local t = {}
    for _, p in ipairs(liste) do
        for id, v in pairs(lecture(p.cle)) do if v then t[id] = true end end
    end
    unions[nom] = { cle = cle, t = t }
    return t
end

-- Couleur et portrait, comme les lignes de personnage de LegacyCore.
function persos.Visage(texture, p)
    -- Rond, dans un anneau a la couleur de la classe (comme la recherche de groupe).
    if _G.CoreSuite and _G.CoreSuite.AnneauDeClasse then _G.CoreSuite.AnneauDeClasse(texture, p and p.classe) end

    texture:SetTexCoord(0, 1, 0, 1)
    if p.cle == NS.ClePersonnage() and _G.SetPortraitTexture and pcall(_G.SetPortraitTexture, texture, "player") then return end
    local coords = _G.CLASS_ICON_TCOORDS and p.classe and _G.CLASS_ICON_TCOORDS[p.classe]
    if coords then
        texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        pcall(texture.SetTexCoord, texture, coords[1], coords[2], coords[3], coords[4])
        return
    end
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end
