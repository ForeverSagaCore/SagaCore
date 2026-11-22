local _, NS = ...

-- Ce que le JcJ a a dire, lu dans le jeu : rang et progression, victoires
-- honorables (aujourd'hui, cette semaine, la semaine derniere, a vie), files
-- d'attente des champs de bataille, champ de bataille en cours (duree et
-- objectifs), marques d'honneur et quetes JcJ du journal. Tout est lu a la
-- demande, sans rien garder. Chaque lecture est protegee : une fonction
-- absente de ce client ne casse rien, la ligne est simplement omise.

NS.honneur = {}
local H = NS.honneur
local T = NS.T

local function Appel(nom, ...)
    local fn = NS.Lecture(nom)
    if not fn then return nil end
    return NS.Appeler(fn, ...)
end
local function Nombre(v)
    if _G.issecretvalue and _G.issecretvalue(v) then return nil end
    return tonumber(v)
end
local function Lisible(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local r = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (r:gsub("^ ", ""))
end
H.Lisible = Lisible
local function Duree(secondes)
    secondes = math.max(0, math.floor(tonumber(secondes) or 0))
    if secondes >= 3600 then return string.format("%d h %02d", math.floor(secondes / 3600), math.floor(secondes % 3600 / 60)) end
    return string.format("%d min %02d s", math.floor(secondes / 60), secondes % 60)
end
H.Duree = Duree

-- Les champs de bataille, par leur zone (noms dans la langue du jeu).
local ZONES_CDB = { 2597, 3277, 3358 }   -- Vallee d'Alterac, Goulet des Chanteguerres, Bassin Arathi
local function NomsDesChamps()
    local noms = {}
    for _, z in ipairs(ZONES_CDB) do
        local n = Appel("C_Map.GetAreaInfo", z)
        if type(n) == "string" and n ~= "" then noms[n] = true end
    end
    return noms
end
-- Marques d'honneur : Vallee d'Alterac, Goulet des Chanteguerres, Bassin Arathi.
local MARQUES = { 20560, 20558, 20559 }

-- Vrai dans un champ de bataille.
function H.EnChamp()
    local dedans, genre = Appel("IsInInstance")
    return dedans and genre == "pvp" or false
end

-- Les rubriques, dans l'ordre : { { titre, lignes = { { texte, droite, couleur } } } }.
function H.Rubriques()
    local r = {}
    local function Rubrique(titre) local x = { titre = titre, lignes = {} } table.insert(r, x) return x end
    local function Ligne(x, texte, droite, couleur) table.insert(x.lignes, { texte = texte, droite = droite, couleur = couleur }) end

    -- Champ de bataille en cours : duree et objectifs (les textes du haut de l'ecran).
    if H.EnChamp() then
        local nom = Appel("GetRealZoneText") or ""
        local x = Rubrique(nom ~= "" and nom or T("Champ de bataille", "Battleground"))
        local ms = Nombre(Appel("GetBattlefieldInstanceRunTime"))
        if ms and ms > 0 then Ligne(x, T("Durée", "Time"), Duree(ms / 1000)) end
        local textes = H.Objectifs()
        if NS.champ then textes = NS.champ.Annoter(textes) end
        for _, texte in ipairs(textes) do Ligne(x, texte) end
        if NS.champ then
            for _, l in ipairs(NS.champ.Lignes()) do Ligne(x, l.texte, nil, l.couleur) end
        end
    end

    -- Files d'attente.
    local files = {}
    local maxi = Nombre(Appel("GetMaxBattlefieldID")) or 0
    for i = 1, maxi do
        local statut, nom = Appel("GetBattlefieldStatus", i)
        if statut == "queued" then
            local attendu = (Nombre(Appel("GetBattlefieldTimeWaited", i)) or 0) / 1000
            local estime = (Nombre(Appel("GetBattlefieldEstimatedWaitTime", i)) or 0) / 1000
            local droite = Duree(attendu)
            if estime > 0 then droite = droite .. " / " .. Duree(estime) end
            table.insert(files, { tostring(nom or "?"), droite })
        elseif statut == "confirm" then
            local reste = Nombre(Appel("GetBattlefieldPortExpiration", i)) or 0
            table.insert(files, { tostring(nom or "?"), T("Prêt : entrez", "Ready : enter") .. " (" .. math.floor(reste) .. " s)", { 0.31, 0.82, 0.41 } })
        end
    end
    if #files > 0 then
        local x = Rubrique(T("Files d'attente", "Queues"))
        for _, f in ipairs(files) do Ligne(x, f[1], f[2], f[3]) end
    end

    -- Rang et progression.
    local rang = Nombre(Appel("UnitPVPRank", "player")) or 0
    local x = Rubrique(T("Rang", "Rank"))
    if rang > 0 then
        local nomRang, numero = Appel("GetPVPRankInfo", rang)
        local progres = Nombre(Appel("GetPVPRankProgress"))
        Ligne(x, tostring(nomRang or "?") .. ((numero and tonumber(numero) and tonumber(numero) > 0) and ("  (" .. numero .. ")") or ""),
            progres and (math.floor(progres * 100 + 0.5) .. " %") or nil)
    else
        Ligne(x, T("Aucun rang pour l'instant", "No rank yet"), nil, { 0.6, 0.6, 0.6 })
    end

    -- Aujourd'hui : victoires, honneur estime (rendement decroissant compris),
    -- honneur bonus, honneur par heure de la session.
    local V = NS.victoires
    if V then
        local j = V.Jour()
        local a = Rubrique(T("Aujourd'hui", "Today"))
        local hk = Nombre((Appel("GetPVPSessionStats"))) or j.vh or 0
        Ligne(a, T("Victoires honorables", "Honourable kills"), Lisible(hk))
        Ligne(a, T("Honneur estimé", "Estimated honour"), Lisible((V.HonneurDuJour())))
        if (j.bonus or 0) > 0 then Ligne(a, T("Dont honneur bonus", "Of which bonus honour"), Lisible(j.bonus)) end
        local ph = V.HonneurParHeure()
        if ph then Ligne(a, T("Honneur par heure (session)", "Honour per hour (session)"), Lisible(ph)) end

        -- Objectif de la semaine (honneur vise, 15 victoires pour etre classe).
        local objectif = V.Objectif() * 1000
        local honneurS, hkS = V.Semaine()
        local classer = hkS > 0 and hkS < 15
        if objectif > 0 or classer then
            local o = Rubrique(T("Objectif de la semaine", "Weekly goal"))
            if objectif > 0 then
                local fait = math.min(100, math.floor(honneurS * 100 / objectif))
                Ligne(o, T("Honneur", "Honour") .. "  " .. Lisible(honneurS) .. " / " .. Lisible(objectif), fait .. " %",
                    fait >= 100 and { 0.31, 0.82, 0.41 } or nil)
                if honneurS < objectif then Ligne(o, T("Reste", "Left"), Lisible(objectif - honneurS)) end
            end
            if hkS < 15 and (classer or objectif > 0) then Ligne(o, T("Victoires pour être classé", "Kills to be ranked"), hkS .. " / 15", { 1, 0.82, 0 }) end
        end

        -- Cibles du jour : rendement decroissant de la prochaine victoire.
        local cibles = V.Cibles(8)
        if #cibles > 0 then
            local c = Rubrique(T("Cibles du jour", "Today's targets"))
            for _, e in ipairs(cibles) do
                local prochaine = V.Rendement(e.n + 1)
                Ligne(c, e.nom, e.n .. T("  ·  prochaine ", "  ·  next ") .. math.floor(prochaine * 100) .. " %",
                    prochaine > 0 and nil or { 0.6, 0.6, 0.6 })
            end
        end
    end

    -- Victoires honorables et honneur.
    local v = Rubrique(T("Victoires honorables", "Honourable kills"))
    local hkS, contribS = Appel("GetPVPThisWeekStats")
    if Nombre(hkS) then Ligne(v, T("Cette semaine", "This week"), Lisible(hkS) .. (Nombre(contribS) and ("  ·  " .. Lisible(contribS) .. " " .. T("honneur", "honour")) or "")) end
    local hkP, _, contribP = Appel("GetPVPLastWeekStats")
    if Nombre(hkP) then Ligne(v, T("Semaine dernière", "Last week"), Lisible(hkP) .. (Nombre(contribP) and ("  ·  " .. Lisible(contribP) .. " " .. T("honneur", "honour")) or "")) end
    local hkV = Appel("GetPVPLifetimeStats")
    if Nombre(hkV) then Ligne(v, T("À vie", "Lifetime"), Lisible(hkV)) end
    if #v.lignes == 0 then Ligne(v, T("Pas encore lues", "Not read yet"), nil, { 0.6, 0.6, 0.6 }) end

    -- Marques d'honneur (seulement celles qu'on a).
    local m = { titre = T("Marques d'honneur", "Marks of honour"), lignes = {} }
    for _, id in ipairs(MARQUES) do
        local n = Nombre(Appel("C_Item.GetItemCount", id)) or Nombre(Appel("GetItemCount", id)) or 0
        if n > 0 then
            local nom = Appel("C_Item.GetItemNameByID", id) or Appel("GetItemInfo", id)
            table.insert(m.lignes, { texte = tostring(nom or ("#" .. id)), droite = tostring(n) })
        end
    end
    if #m.lignes > 0 then table.insert(r, m) end

    -- Quetes JcJ : celles du journal rangees sous un champ de bataille.
    local q = H.Quetes()
    if #q > 0 then
        local x2 = Rubrique(T("Quêtes JcJ", "PvP quests"))
        for _, e in ipairs(q) do
            Ligne(x2, e.titre, e.complete and T("À rendre", "To turn in") or nil, e.complete and { 0.31, 0.82, 0.41 } or { 1, 0.82, 0 })
            for _, o in ipairs(e.objectifs) do Ligne(x2, "   " .. o.texte, nil, o.fait and { 0.5, 0.5, 0.5 } or { 0.85, 0.85, 0.85 }) end
        end
    end
    return r
end

-- Les objectifs affiches en haut de l'ecran pendant un champ de bataille.
function H.Objectifs()
    local textes = {}
    local W = _G.C_UIWidgetManager
    if W and W.GetTopCenterWidgetSetID and W.GetAllWidgetsBySetID then
        local ok, set = pcall(W.GetTopCenterWidgetSetID)
        local ok2, widgets = pcall(W.GetAllWidgetsBySetID, ok and set or 0)
        for _, w in ipairs(ok2 and type(widgets) == "table" and widgets or {}) do
            local id = w.widgetID
            for _, lire in ipairs({ "GetIconAndTextWidgetVisualizationInfo", "GetDoubleStatusBarWidgetVisualizationInfo",
                "GetTextWithStateWidgetVisualizationInfo", "GetDoubleStateIconRowVisualizationInfo" }) do
                if W[lire] then
                    local okI, info = pcall(W[lire], id)
                    if okI and type(info) == "table" then
                        local texte = info.text or info.leftBarTooltip
                        if type(texte) == "string" and texte ~= "" and not (_G.issecretvalue and _G.issecretvalue(texte)) then
                            texte = texte:gsub("|n", " "):gsub("\n", " ")
                            table.insert(textes, texte)
                            break
                        end
                    end
                end
            end
        end
    end
    -- Sinon : les textes affiches par le jeu lui-meme en haut de l'ecran
    -- (les cadres de ses objectifs), lus tels quels.
    if #textes == 0 then
        local racine = _G.UIWidgetTopCenterContainerFrame
        local vus = {}
        local function Lire(cadre, profondeur)
            if not cadre or profondeur > 4 or (cadre.IsShown and not cadre:IsShown()) then return end
            for _, r in ipairs({ cadre:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                    local ok, texte = pcall(r.GetText, r)
                    if ok and type(texte) == "string" and texte ~= "" and not vus[texte]
                        and not (_G.issecretvalue and _G.issecretvalue(texte)) then
                        vus[texte] = true
                        table.insert(textes, (texte:gsub("|n", " "):gsub("\n", " ")))
                    end
                end
            end
            for _, enfant in ipairs({ cadre:GetChildren() }) do Lire(enfant, profondeur + 1) end
        end
        if racine then pcall(Lire, racine, 0) end
    end
    -- Ancienne interface (clients plus anciens).
    if #textes == 0 then
        local n = Nombre(Appel("GetNumWorldStateUI")) or 0
        for i = 1, n do
            local _, etat, _, texte = Appel("GetWorldStateUIInfo", i)
            if etat and etat > 0 and type(texte) == "string" and texte ~= "" then table.insert(textes, texte) end
        end
    end
    return textes
end

-- Les quetes du journal classees sous un champ de bataille.
function H.Quetes()
    local liste = {}
    local noms = NomsDesChamps()
    local n = Nombre(Appel("GetNumQuestLogEntries")) or 0
    local dansChamp = false
    for i = 1, n do
        local titre, _, _, enTete, _, complete = Appel("GetQuestLogTitle", i)
        if enTete then
            dansChamp = type(titre) == "string" and noms[titre] == true
        elseif dansChamp and type(titre) == "string" then
            local e = { titre = titre, complete = complete == 1 or complete == true, objectifs = {} }
            local nObj = Nombre(Appel("GetNumQuestLeaderBoards", i)) or 0
            for k = 1, nObj do
                local texte, _, fait = Appel("GetQuestLogLeaderBoard", k, i)
                if type(texte) == "string" and texte ~= "" then table.insert(e.objectifs, { texte = texte, fait = fait and true or false }) end
            end
            table.insert(liste, e)
        end
    end
    return liste
end

-- Pour les autres add-ons de la suite (onglet JcJ du suivi de QuestCore).
_G.PvPCoreAPI = {
    Disponible = function() return true end,
    Rubriques = function() local ok, r = pcall(H.Rubriques) return ok and r or {} end,
    EnChamp = function() return H.EnChamp() end,
    Ouvrir = function() if NS.fenetre and NS.fenetre.Ouvrir then NS.fenetre.Ouvrir() end end,
}
