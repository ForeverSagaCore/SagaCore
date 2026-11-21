local _, NS = ...

-- AuraCore : un cercle de 16 places fixes autour du personnage (voir plus
-- bas l'ordre des places). Rien n'est lu en combat : l'anneau recopie ce que
-- le jeu donne a ses propres icones ; les places reservees gardent l'etat
-- releve juste avant le combat.

NS.anneau = {}
local A = NS.anneau
local D = NS.donnees

local function Reglages()
    AuraCoreDB = type(AuraCoreDB) == "table" and AuraCoreDB or {}
    local r = AuraCoreDB
    r.taille = r.taille or 30
    r.hauteur = r.hauteur or -30
    r.rayon = r.rayon or 110
    -- Opacite generale de l'anneau : pleine par defaut.
    r.opaciteAnneau = r.opaciteAnneau or 1
    -- Nourriture, flacon, potion : visibles, dans le quart du bas par defaut.
    if r.consoVisibles == nil then r.consoVisibles = true end
    r.consoPlace = r.consoPlace or "bas"
    -- Duree restante : a l'exterieur de l'icone (ou dedans) ; cercle de
    -- recharge degressif (ou progressif).
    r.dureePlace = r.dureePlace or "interieur"
    if not r.duree2 then r.duree2 = true r.dureePlace = "interieur" end
    r.remplissage = r.remplissage or "degressif"
    -- Effets nuisibles sur leur propre cercle (dedans), depart en bas.
    if r.nuisiblesAPart == nil then r.nuisiblesAPart = true end
    r.nuisiblesPlace = r.nuisiblesPlace or "dedans"
    r.nuisiblesDepart = r.nuisiblesDepart or "bas"
    r.nuisiblesSens = r.nuisiblesSens or "horaire"
    r.nuisiblesTaille = r.nuisiblesTaille or "meme"
    r.nuisiblesDuree = r.nuisiblesDuree or "interieur"
    -- Buffs de groupe a part, dans le quart droit par defaut.
    if r.groupeVisibles == nil then r.groupeVisibles = true end
    r.groupePlace = r.groupePlace or "droite"
    -- Une seule fois : la disposition reservee (celle des 16 places).
    if not r.disposition3 then r.disposition3 = true r.disposition = "reserve" end
    r.disposition = r.disposition or "reserve"
    r.depart = r.depart or "haut"
    r.sens = r.sens or "horaire"
    return r
end
A.Reglages = Reglages

local T = NS.T

local function Secret(v) return _G.issecretvalue and _G.issecretvalue(v) end

-- ---------------------------------------------------------------------------
-- Pastilles rondes
-- ---------------------------------------------------------------------------

local racine = CreateFrame("Frame", "AuraCoreAnneau", UIParent)
racine:SetSize(1, 1)
racine:SetFrameStrata("LOW")
racine:EnableMouse(false)
A.racine = racine

local Bulle -- plus bas

local function Pastille(parent)
    local p = CreateFrame("Frame", nil, parent)
    -- La souris montre l'infobulle, mais les clics passent au travers
    -- (on peut toujours cliquer le monde derriere).
    p:EnableMouse(true)
    if p.SetMouseClickEnabled then p:SetMouseClickEnabled(false) end
    p:SetScript("OnEnter", function(self) pcall(Bulle, self) end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Meme habillage que les onglets ronds des suivis : fond sombre, icone
    -- ronde, anneau dore du jeu (gris et epais quand absent).
    p.fond = p:CreateTexture(nil, "BACKGROUND")
    p.fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    p.fond:SetPoint("CENTER")
    p.bordure = p:CreateTexture(nil, "OVERLAY", nil, 1)
    p.bordure:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    p.bordure:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    p.icone = p:CreateTexture(nil, "ARTWORK")
    p.icone:SetPoint("CENTER")
    p.icone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if p.CreateMaskTexture then
        local m = p:CreateMaskTexture()
        if m then
            m:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(p.icone)
            p.icone:AddMaskTexture(m)
        end
    end
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, p, "CooldownFrameTemplate")
    if ok and cd then
        p.recharge = cd
        cd:SetAllPoints(p.icone)
        if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, "Interface\\Masks\\CircleMaskScalable") end
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
        -- Chiffres du jeu un peu plus petits, pour tenir dans l'icone.
        if cd.SetCountdownFont then pcall(cd.SetCountdownFont, cd, "NumberFontNormalSmall") end
        cd:EnableMouse(false)
    end
    -- Chiffres au-dessus du cercle de recharge (sinon il les assombrit).
    p.dessus = CreateFrame("Frame", nil, p)
    p.dessus:SetAllPoints()
    p.dessus:SetFrameLevel(p:GetFrameLevel() + 5)
    p.dessus:EnableMouse(false)
    p.compte = p.dessus:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    p.compte:SetPoint("BOTTOMRIGHT", 2, -2)
    -- La duree, sans unite : au centre de l'icone ou a l'exterieur.
    p.duree = p.dessus:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    p.duree:SetPoint("CENTER", p, "CENTER", 0, 0)
    -- Proportions des onglets des suivis (bouton 24 : fond 19, icone 16,
    -- anneau 41 pose en haut a gauche).
    function p.Taille(self, t)
        self:SetSize(t, t)
        -- Chiffres proportionnes a l'icone : plus petits dedans (ils doivent
        -- tenir dans l'image), un peu plus grands dehors.
        local function Police(taille)
            local nom = "AuraCoreChiffres" .. taille
            if not _G[nom] and CreateFont then
                local f = CreateFont(nom)
                local fichier, _, drapeaux = (NumberFontNormal or GameFontHighlight):GetFont()
                f:SetFont(fichier, taille, drapeaux or "OUTLINE")
            end
            return _G[nom] and nom or nil
        end
        if self.tailleChiffres ~= t then
            self.tailleChiffres = t
            -- Un tiers de la hauteur de l'icone, dedans comme dehors.
            local taille = math.max(8, math.floor(t / 3 + 0.5))
            local nom = Police(taille)
            if nom then
                self.duree:SetFontObject(_G[nom])
                if self.recharge and self.recharge.SetCountdownFont then pcall(self.recharge.SetCountdownFont, self.recharge, nom) end
            end
        end
        self.fond:SetSize(t * 19 / 24, t * 19 / 24)
        self.icone:SetSize(t * 16 / 24, t * 16 / 24)
        self.bordure:SetSize(t * 41 / 24, t * 41 / 24)
    end
    p:Hide()
    return p
end

-- Etat d'une pastille : actif (anneau dore), absent (gris), nuisible (rouge).
local function Cercler(p, etat)
    if etat == "absent" then
        p.bordure:SetDesaturated(true)
        p.bordure:SetVertexColor(0.75, 0.75, 0.75, 1)
        p.icone:SetDesaturated(true)
    elseif etat == "nuisible" then
        p.bordure:SetDesaturated(false)
        p.bordure:SetVertexColor(1, 0.25, 0.2, 1)
        p.icone:SetDesaturated(false)
    else
        p.bordure:SetDesaturated(false)
        p.bordure:SetVertexColor(1, 1, 1, 1)
        p.icone:SetDesaturated(false)
    end
end

local anneau = {}
local function Prendre(liste, i, parent)
    liste[i] = liste[i] or Pastille(parent)
    return liste[i]
end

-- ---------------------------------------------------------------------------
-- 1. L'anneau : tous les buffs, sans les lire
-- ---------------------------------------------------------------------------

-- Duree restante sans unite : 57 qui ne bouge pas, ce sont des minutes.
local function Court(reste)
    if reste >= 3600 then return tostring(math.floor(reste / 3600)) end
    if reste >= 60 then return tostring(math.floor(reste / 60)) end
    return tostring(math.max(0, math.floor(reste)))
end

local function PoserRecharge(p, expiration, duree, place, idAura)
    -- Le chiffre seul (sans unite), dans l'icone ou a l'exterieur selon le
    -- reglage. Valeurs secretes (combat) : le cercle et les chiffres du jeu
    -- (dans l'icone), sinon rendre faux pour recopier le texte du jeu.
    local r = Reglages()
    place = place or r.dureePlace
    -- Sans duree : ni chiffre ni cercle.
    if place == "aucune" then
        if p.recharge then p.recharge:Clear() end
        p.cdExp, p.cdDur = nil, nil
        return true
    end
    local dedans = place == "interieur"
    local lisible = type(expiration) == "number" and not Secret(expiration) and not Secret(duree)
    if lisible and expiration > 0 then p.duree:SetText(Court(expiration - GetTime())) end
    if not p.recharge then return lisible end
    if p.recharge.SetReverse then p.recharge:SetReverse(r.remplissage == "progressif") end
    if lisible then
        -- Meme duree que la derniere fois : on ne relance pas le cercle (il
        -- resterait desynchronise de son chiffre).
        if p.cdExp == expiration and p.cdDur == duree and p.cdJeu == false then return true end
        p.cdExp, p.cdDur, p.cdJeu = expiration, duree, false
        p.recharge:Clear()
        if p.recharge.SetHideCountdownNumbers then p.recharge:SetHideCountdownNumbers(true) end
        if duree and duree > 0 and expiration > 0 then
            if p.recharge.SetCooldownFromExpirationTime then
                pcall(p.recharge.SetCooldownFromExpirationTime, p.recharge, expiration, duree)
            else
                pcall(p.recharge.SetCooldown, p.recharge, expiration - duree, duree)
            end
        end
        return true
    end
    -- Valeurs secretes : on confie la duree au cadre de recharge du jeu, qui
    -- sait l'afficher sans qu'on la lise (objet de duree de l'aura, ou
    -- expiration secrete).
    p.cdExp, p.cdDur, p.cdJeu = nil, nil, true
    local pose = false
    local C = _G.C_UnitAuras
    if idAura ~= nil and C and C.GetAuraDuration and p.recharge.SetCooldownFromDurationObject then
        pose = pcall(function()
            local objet = C.GetAuraDuration("player", idAura)
            if objet == nil then error("rien") end
            p.recharge:SetCooldownFromDurationObject(objet)
        end)
    end
    if not pose and expiration ~= nil and duree ~= nil and p.recharge.SetCooldownFromExpirationTime then
        pose = pcall(p.recharge.SetCooldownFromExpirationTime, p.recharge, expiration, duree)
    end
    if p.recharge.SetHideCountdownNumbers then p.recharge:SetHideCountdownNumbers(not (pose and dedans)) end
    -- Chiffres du jeu dans l'icone : fait. Sinon, le texte du jeu (Recopier).
    return pose and dedans
end

-- Seulement ce qui compte en combat : les pistages (herbes, minerais,
-- betes...) n'ont rien a faire dans l'anneau. Reconnus hors combat par leur
-- sort ; leur numero d'aura est retenu pour les ecarter aussi en combat.
local PISTAGES = {
    [2383] = true, [2580] = true, [2481] = true, [1494] = true, [19883] = true, [19884] = true,
    [19885] = true, [19880] = true, [19878] = true, [19882] = true, [19879] = true, [5225] = true,
    [5502] = true, [5500] = true, [43308] = true,
}
local exclus, iconesExclues = {}, {}
local function Exclu(id, icone)
    if id ~= nil and not Secret(id) and exclus[id] then return true end
    if icone ~= nil and not Secret(icone) and iconesExclues[icone] then return true end
    return false
end

-- Source 1 : ce que l'interface de programmation du jeu donne aux add-ons :
-- les ameliorations, puis les ameliorations nuisibles.
local function DepuisLeJeu()
    local liste, erreur = {}, nil
    local C = _G.C_UnitAuras
    if not (C and C.GetAuraDataByIndex) then return liste, "absent" end
    -- Pistage lance en combat : la liste ne dit plus quel sort c'est. On le
    -- demande directement par son sort ; ce que le jeu laisse lire (numero
    -- d'aura, icone) suffit a l'ecarter tout de suite.
    if C.GetPlayerAuraBySpellID then
        for sort in pairs(PISTAGES) do
            local ok, a = pcall(C.GetPlayerAuraBySpellID, sort)
            if ok and type(a) == "table" then
                if a.auraInstanceID ~= nil and not Secret(a.auraInstanceID) then exclus[a.auraInstanceID] = true end
                if a.icon ~= nil and not Secret(a.icon) then iconesExclues[a.icon] = true end
            end
        end
    end
    for _, filtre in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, a = pcall(C.GetAuraDataByIndex, "player", i, filtre)
            if not ok then erreur = tostring(a) break end
            if type(a) ~= "table" then break end
            local sort = a.spellId
            if sort ~= nil and not Secret(sort) and PISTAGES[sort] then
                if a.auraInstanceID ~= nil and not Secret(a.auraInstanceID) then exclus[a.auraInstanceID] = true end
                if a.icon ~= nil and not Secret(a.icon) then iconesExclues[a.icon] = true end
            elseif not Exclu(a.auraInstanceID, a.icon) then
                table.insert(liste, { index = i, id = a.auraInstanceID, icone = a.icon,
                    nom = (not Secret(a.name)) and a.name or nil, nuisible = filtre == "HARMFUL",
                    compte = a.applications, expiration = a.expirationTime, duree = a.duration })
            end
        end
        if erreur then break end
    end
    return liste, erreur
end

-- Source 2 : les boutons du cadre des ameliorations du jeu, tels qu'il les
-- affiche. On ne lit rien : on recopie l'icone, la duree et le nombre de
-- charges, tels quels, dans nos pastilles.
local function BoutonsDe(cadre, prefixe, liste, nuisible)
    local avant = #liste
    if cadre and type(cadre.auraFrames) == "table" then
        for _, b in ipairs(cadre.auraFrames) do
            local ok, vu = pcall(b.IsShown, b)
            if ok and vu == true then table.insert(liste, b) b.suiteNuisible = nuisible end
        end
    end
    if #liste == avant then
        for i = 1, 40 do
            local b = _G[prefixe .. i]
            if b then
                local ok, vu = pcall(b.IsShown, b)
                if ok and vu == true then table.insert(liste, b) b.suiteNuisible = nuisible end
            end
        end
    end
end
local function BoutonsDuJeu()
    local liste = {}
    BoutonsDe(_G.BuffFrame, "BuffButton", liste, false)
    BoutonsDe(_G.DebuffFrame, "DebuffButton", liste, true)
    return liste
end

local function Champ(b, cle)
    return b[cle] or (b.GetName and b:GetName() and _G[b:GetName() .. cle]) or nil
end

local function DepuisLeCadreDuJeu()
    local liste = {}
    for _, b in ipairs(BoutonsDuJeu()) do
        local e = { bouton = b }
        local icone = Champ(b, "Icon") or Champ(b, "icon")
        if icone and icone.GetTexture then
            local ok, t = pcall(icone.GetTexture, icone)
            if ok then e.icone = t end
        end
        local info = b.buttonInfo
        if type(info) == "table" then
            e.expiration, e.duree, e.id, e.index = info.expirationTime, info.duration, info.auraInstanceID, info.index
        end
        e.texteDuree = Champ(b, "Duration") or Champ(b, "duration")
        e.texteCompte = Champ(b, "Count") or Champ(b, "count")
        e.nuisible = b.suiteNuisible
        -- Un emplacement vide du cadre du jeu (pas d'image, ou image cachee)
        -- ne donne pas de cercle vide dans l'anneau.
        local vide = (e.icone == nil)
        if not vide and icone and icone.IsShown then
            local okV, vu = pcall(icone.IsShown, icone)
            if okV and vu == false then vide = true end
        end
        if not vide and not Exclu(e.id, e.icone) then table.insert(liste, e) end
    end
    return liste
end

local function Recopier(fs, source, chiffreSeul)
    fs:SetText("")
    if not (source and source.GetText) then return end
    local okv, vu = pcall(source.IsShown, source)
    if okv and vu == false then return end
    local ok, t = pcall(source.GetText, source)
    if ok and t ~= nil then
        pcall(fs.SetText, fs, t)
        -- Le chiffre seul, sans l'unite (si le jeu le laisse lire).
        if chiffreSeul then
            pcall(function()
                local n = t:match("%d+")
                if n then fs:SetText(n) end
            end)
        end
    end
end

local function Diag()
    local r = Reglages()
    r.diag = type(r.diag) == "table" and r.diag or {}
    return r.diag
end

-- ---------------------------------------------------------------------------
-- Les 16 places du cercle, toujours dans le meme ordre (depuis le point de
-- depart, dans le sens choisi) :
--   1. ce que le personnage se met lui-meme (un aspect, une aura, une
--      armure...) : une place par famille ; la derniere activee y reste,
--      grisee quand elle manque ;
--   2. nourriture, flacon ou elixir, potion (avec sa recharge) ;
--   3. les buffs que les classes du groupe peuvent donner ;
--   4. puis tout le reste a la file (procs, buffs recus, effets nuisibles en
--      rouge), chacun garde sa place tant qu'il est la.
-- Actif : en couleur ; absent : gris. Les places reservees sont relevees
-- hors combat (en combat, le jeu ne dit plus quel buff est lequel).
-- ---------------------------------------------------------------------------

local PLACES = 16
local DessinerNuisibles -- plus bas
local reservees = {}     -- etat des places reservees (releve hors combat)
local placesFile = {}    -- [cle d'aura] = rang dans la file (place fixe)
local premierDessin = true

local function StylerReserve(p, e, r)
    p.aura, p.colonne = nil, e
    pcall(p.icone.SetTexture, p.icone, e.icone)
    p.compte:SetText(e.compte and e.compte > 1 and e.compte or "")
    p.duree:SetText("")
    p.icone:SetVertexColor(1, 1, 1)
    Cercler(p, e.actif and "actif" or "absent")
    -- Place active avec une duree (nourriture, flacon, buff recu...) : la
    -- duree restante, comme les autres icones. Sinon, pas de cercle.
    local avecDuree = e.actif and not e.potion and type(e.expiration) == "number" and e.expiration > 0
    if avecDuree then
        PoserRecharge(p, e.expiration, e.duree)
    elseif not e.potion and p.recharge then
        p.recharge:Clear()
        p.cdExp, p.cdDur = nil, nil
    end
    -- Potion : sa recharge tourne une fois bue.
    if e.potion and p.recharge then
        local f = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
        if f then
            local ok, debut, duree = pcall(f, e.potion)
            if ok and type(debut) == "number" and type(duree) == "number" and duree > 0 then
                PoserRecharge(p, debut + duree, duree)
            end
        end
    end
    p.absent = not e.actif
end

local indexDes = {}
local temps = {}   -- [nom] = { expiration, duree } (releve hors combat)
local function MesBuffs()
    indexDes = {}
    local t, ids = {}, {}
    temps = {}
    local C = _G.C_UnitAuras
    for i = 1, 40 do
        if not (C and C.GetAuraDataByIndex) then break end
        local ok, a = pcall(C.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        local nom = a.name
        if nom and not Secret(nom) then
            t[nom] = a.icon or true
            indexDes[nom] = i
            if a.auraInstanceID ~= nil and not Secret(a.auraInstanceID) then ids[nom] = a.auraInstanceID end
            if not Secret(a.expirationTime) and not Secret(a.duration) then temps[nom] = { a.expirationTime, a.duration } end
        end
    end
    return t, ids
end

local function Premier(liste, buffs)
    for _, id in ipairs(liste) do
        local nom = D.Nom(id)
        if nom and buffs[nom] then return buffs[nom], id, nom end
    end
    return nil, liste[1], nil
end

-- Le personnage connait-il ce sort (un des rangs) ?
local function Connu(liste)
    for _, id in ipairs(liste) do
        local nom = D.Nom(id)
        if nom and _G.GetSpellInfo then
            local ok, n = pcall(_G.GetSpellInfo, nom)
            if ok and n then return true end
        end
        if _G.IsPlayerSpell and _G.IsPlayerSpell(id) then return true end
    end
    return false
end

local function Compter(objet)
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, objet)
    return ok and tonumber(n) or 0
end

local ORDRE_CLASSES = { "PRIEST", "MAGE", "DRUID", "PALADIN", "WARRIOR", "HUNTER", "SHAMAN", "WARLOCK", "ROGUE" }
local function ClassesDuGroupe()
    local classes = {}
    local _, moi = UnitClass("player")
    if moi then classes[moi] = true end
    local raid = _G.IsInRaid and _G.IsInRaid()
    for i = 1, (_G.GetNumGroupMembers and _G.GetNumGroupMembers()) or 0 do
        local unite = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unite) then
            local _, c = UnitClass(unite)
            if c then classes[c] = true end
        end
    end
    return classes, moi
end

local function Relever()
    local r = Reglages()
    r.derniers = type(r.derniers) == "table" and r.derniers or {}
    local buffs, ids = MesBuffs()
    reservees = {}
    local function Noter(nom)
        local e = reservees[#reservees]
        if e and nom then
            e.idAura = ids[nom]
            local d = temps[nom]
            if d then e.expiration, e.duree = d[1], d[2] end
        end
    end
    local classes, moi = ClassesDuGroupe()
    -- 1. Ce que le personnage se met lui-meme : la derniere activee reste.
    for g, famille in ipairs((moi and D.SOI[moi]) or {}) do
        if Connu(famille) then
            local b, id, nom = Premier(famille, buffs)
            local cle = moi .. g
            if nom then r.derniers[cle] = id end
            local montre = (nom and id) or r.derniers[cle] or famille[1]
            table.insert(reservees, { icone = (type(b) ~= "boolean" and b) or D.Icone(montre), actif = nom ~= nil,
                sort = montre, classe = moi, nom = nom, index = nom and indexDes[nom], soi = true })
            Noter(nom)
        end
    end
    -- 2. Nourriture, flacon ou elixir, potion.
    local b, id, nom = Premier(D.NOURRITURE, buffs)
    table.insert(reservees, { icone = (type(b) ~= "boolean" and b) or "Interface\\Icons\\INV_Misc_Food_14", actif = nom ~= nil,
        titre = T("Nourriture", "Food"), nom = nom, index = nom and indexDes[nom], conso = true })
    Noter(nom)
    b, id, nom = Premier(D.FLACONS, buffs)
    table.insert(reservees, { icone = (type(b) ~= "boolean" and b) or "Interface\\Icons\\INV_Potion_97", actif = nom ~= nil,
        titre = T("Flacon ou élixir", "Flask or elixir"), nom = nom, index = nom and indexDes[nom], conso = true })
    Noter(nom)
    local potion
    for _, objet in ipairs(D.POTIONS) do
        local n = Compter(objet)
        if n > 0 then
            local icone = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(objet)) or (_G.GetItemIcon and _G.GetItemIcon(objet))
            potion = { icone = icone, actif = true, compte = n, potion = objet, conso = true }
            break
        end
    end
    table.insert(reservees, potion or { icone = "Interface\\Icons\\INV_Potion_51", actif = false, potion = D.POTIONS[#D.POTIONS], compte = 0, conso = true })
    -- 3. Les buffs que les classes du groupe peuvent donner.
    for _, classe in ipairs(ORDRE_CLASSES) do
        if classes[classe] then
            for _, alternatives in ipairs(D.GROUPE[classe] or {}) do
                if classe ~= moi or Connu(alternatives) then
                    local bb, idd, nn = Premier(alternatives, buffs)
                    table.insert(reservees, { icone = (type(bb) ~= "boolean" and bb) or D.Icone(idd), actif = nn ~= nil,
                        sort = idd, classe = classe, nom = nn, index = nn and indexDes[nn], groupe = true })
                    Noter(nn)
                end
            end
        end
    end
end

-- Une icone qui vient d'arriver dans la file clignote deux fois.
local function Signaler(p)
    if not p.signal then
        p.signal = p:CreateAnimationGroup()
        p.signal:SetLooping("BOUNCE")
        local a = p.signal:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.25)
        a:SetDuration(0.25)
    end
    p.signal:Stop()
    p.signal:Play()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() if p.signal then p.signal:Stop() end end) end
end

local function CleAura(e, i)
    if e.id ~= nil and not Secret(e.id) then return "id" .. tostring(e.id) end
    return "rang" .. i
end

-- Le cercle des effets nuisibles, concentrique : dedans ou dehors, depart
-- sur un des huit points (cardinaux et diagonales), dans un sens ou dans
-- l'autre. Le premier arrive prend la place 1, le suivant la 2, et ainsi de
-- suite (sans trou : quand un effet part, les suivants avancent).
local nuisibles = {}
local ordreNuisibles = {}
local DEPARTS = { haut = 90, hautdroite = 45, droite = 0, basdroite = 315, bas = 270, basgauche = 225, gauche = 180, hautgauche = 135 }
local ECHELLES = { petite = 0.8, meme = 1, grande = 1.25 }
DessinerNuisibles = function(r, presents, rayonPrincipal, tPrincipal)
    local t = math.floor(tPrincipal * (ECHELLES[r.nuisiblesTaille] or 1) + 0.5)
    local dehors = r.nuisiblesPlace == "dehors"
    -- Jamais de contact entre les deux cercles : demi-anneau de chacun, plus
    -- un espace, plus la place des chiffres ecrits entre les deux.
    local ecart = tPrincipal * 0.55 + t * 0.55 + 10
    if dehors and r.dureePlace == "exterieur" then ecart = ecart + tPrincipal / 3 + 10 end
    if not dehors and r.nuisiblesDuree == "exterieur" then ecart = ecart + t / 3 + 10 end
    local rayon = dehors and (rayonPrincipal + ecart) or (rayonPrincipal - ecart)
    -- Ordre d'arrivee : ceux deja la gardent leur rang, les nouveaux a la fin.
    local la = {}
    for _, x in ipairs(presents) do la[x.cle] = x.e end
    local garde = {}
    for _, cle in ipairs(ordreNuisibles) do if la[cle] then table.insert(garde, cle) la[cle .. "#vu"] = true end end
    local neufs = {}
    for _, x in ipairs(presents) do if not la[x.cle .. "#vu"] then table.insert(garde, x.cle) neufs[x.cle] = true end end
    ordreNuisibles = garde
    local depart = DEPARTS[r.nuisiblesDepart] or 270
    local signe = (r.nuisiblesSens == "antihoraire") and 1 or -1
    -- Autant de places que le cercle en contient sans que les icones se
    -- touchent (un cercle interieur trop petit en a moins).
    local places = (rayon > 0) and math.floor(2 * math.pi * rayon / (t * 1.1 + 6)) or 0
    if places < 1 then places = (rayon > 0) and 1 or 0 end
    local pas = 360 / places
    local n = 0
    for rang, cle in ipairs(ordreNuisibles) do
        if rang > places then break end
        local e = la[cle]
        n = n + 1
        local p = Prendre(nuisibles, n, racine)
        p.aura, p.colonne, p.absent = e, nil, false
        pcall(p.icone.SetTexture, p.icone, e.icone)
        Cercler(p, "nuisible")
        p.icone:SetVertexColor(1, 1, 1)
        p.compte:SetText("")
        p.duree:SetText("")
        if e.bouton then
            Recopier(p.compte, e.texteCompte)
            if not PoserRecharge(p, e.expiration, e.duree, r.nuisiblesDuree, e.id) then Recopier(p.duree, e.texteDuree, true) end
        else
            pcall(function() if not Secret(e.compte) and (e.compte or 0) > 1 then p.compte:SetText(e.compte) end end)
            PoserRecharge(p, e.expiration, e.duree, r.nuisiblesDuree, e.id)
        end
        local a = math.rad(depart + signe * (rang - 1) * pas)
        p:Taille(t)
        p:ClearAllPoints()
        p:SetPoint("CENTER", racine, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
        local ecartTexte = (r.nuisiblesDuree == "interieur") and 0 or (t * 0.5 + 9)
        p.duree:ClearAllPoints()
        p.duree:SetPoint("CENTER", p, "CENTER", math.cos(a) * ecartTexte, math.sin(a) * ecartTexte)
        p.duree:SetTextColor(1, 1, 1)
        p:SetAlpha(1)
        p:Show()
        if neufs[cle] and not premierDessin then Signaler(p) end
    end
    for i = n + 1, #nuisibles do nuisibles[i]:Hide() end
end

local function DessinerAnneau(r)
    local t = r.taille
    -- Les 16 places tiennent toujours : le cercle s'agrandit si la taille des
    -- icones l'exige, a partir du rayon minimum choisi.
    local rayon = math.max(r.rayon, (PLACES * (t * 1.1 + 6)) / (2 * math.pi))
    local depart = ({ haut = 90, droite = 0, bas = 270, gauche = 180 })[r.depart] or 90
    local signe = (r.sens == "antihoraire") and 1 or -1
    local pas = 360 / PLACES
    -- Les 16 angles, depuis le point de depart, dans le sens choisi.
    local angles = {}
    for k = 0, PLACES - 1 do angles[k + 1] = (depart + signe * k * pas) % 360 end
    -- Quarts reserves (haut, droite, bas ou gauche) : nourriture, flacon et
    -- potion d'un cote, buffs de groupe d'un autre, chacun ses trois places,
    -- dans le sens de lecture. Le reste prend les autres places.
    local DIR = { haut = 90, droite = 0, bas = 270, gauche = 180 }
    local function Quart(place)
        local q = DIR[place] or 270
        local l = {}
        for _, a in ipairs(angles) do
            if math.abs(((a - q + 180) % 360) - 180) < 44 then table.insert(l, a) end
        end
        table.sort(l, function(x, y)
            local rx, ry = math.rad(x), math.rad(y)
            if place == "droite" or place == "gauche" then return math.sin(rx) > math.sin(ry) end
            return math.cos(rx) < math.cos(ry)
        end)
        return l
    end
    local pris = {}
    local placesConso = r.consoVisibles and Quart(r.consoPlace) or {}
    for _, a in ipairs(placesConso) do pris[a] = true end
    local placesGroupe = {}
    if r.groupeVisibles then
        for _, a in ipairs(Quart(r.groupePlace)) do
            if not pris[a] then table.insert(placesGroupe, a) pris[a] = true end
        end
    end
    local autres = {}
    for _, a in ipairs(angles) do if not pris[a] then table.insert(autres, a) end end
    local function Poser(p, angle)
        local a = math.rad(angle)
        p:Taille(t)
        p:ClearAllPoints()
        p:SetPoint("CENTER", racine, "CENTER", math.cos(a) * rayon, math.sin(a) * rayon)
        -- La duree restante : en blanc, a l'exterieur du cercle, dans l'axe
        -- de l'icone (au-dessus en haut, en dessous en bas...).
        local ecart = (r.dureePlace == "interieur") and 0 or (t * 0.5 + 9)
        p.duree:ClearAllPoints()
        p.duree:SetPoint("CENTER", p, "CENTER", math.cos(a) * ecart, math.sin(a) * ecart)
        p.duree:SetTextColor(1, 1, 1)
        p:SetAlpha(p.absent and 0.45 or 1)
        p:Show()
    end
    -- Disposition du reste : "reserve" (sa place a ce qu'on se met soi-meme,
    -- grisee si elle manque, puis la file), "suite" (chacun a la file, a
    -- place fixe), "equilibre" (repartis sur tout l'arc, ils bougent).
    local dispo = r.disposition or "reserve"
    local montrees, dejaNoms, dejaIds = {}, {}, {}
    local n, iConso, iGroupe, iAutre = 0, 0, 0, 0
    local enTrop = {}
    for _, e in ipairs(reservees) do
        local angle
        if e.conso then
            if r.consoVisibles then iConso = iConso + 1 angle = placesConso[iConso] end
        elseif e.groupe then
            if r.groupeVisibles then
                iGroupe = iGroupe + 1
                angle = placesGroupe[iGroupe]
                if not angle then table.insert(enTrop, e) end
            elseif dispo == "reserve" then
                table.insert(enTrop, e)
            end
        elseif e.soi and dispo == "reserve" then
            iAutre = iAutre + 1
            angle = autres[iAutre]
        end
        if angle then
            n = n + 1
            local p = Prendre(anneau, n, racine)
            StylerReserve(p, e, r)
            Poser(p, angle)
            if e.nom then dejaNoms[e.nom] = true end
            if e.idAura then dejaIds[e.idAura] = true end
        end
    end
    -- Buffs de groupe sans place dans leur quart : a la suite, apres le soi.
    for _, e in ipairs(enTrop) do
        iAutre = iAutre + 1
        local angle = autres[iAutre]
        if angle then
            n = n + 1
            local p = Prendre(anneau, n, racine)
            StylerReserve(p, e, r)
            Poser(p, angle)
            if e.nom then dejaNoms[e.nom] = true end
            if e.idAura then dejaIds[e.idAura] = true end
        end
    end
    local debutFile = n
    local anglesFile = {}
    for i = iAutre + 1, #autres do table.insert(anglesFile, autres[i]) end
    -- La file : tout le reste, sans les pistages ni ce qui a deja sa place.
    local liste, source = {}, "jeu"
    local api, erreur = DepuisLeJeu()
    liste = api
    if #api == 0 then
        local natifs = DepuisLeCadreDuJeu()
        if #natifs > 0 then liste, source = natifs, "cadre" end
    end
    local d = Diag()
    local enCombat = InCombatLockdown and InCombatLockdown() or false
    d[enCombat and "combat" or "horsCombat"] = { api = #api, erreur = erreur, source = source, montres = #liste,
        natifs = #BoutonsDuJeu() }
    local libres = #anglesFile
    local vus, aPlacer = {}, {}
    -- Effets nuisibles : sur leur propre cercle, si l'option est cochee.
    local aPart = r.nuisiblesAPart and {} or nil
    for i, e in ipairs(liste) do
        local deja = (e.nom and dejaNoms[e.nom]) or (e.id ~= nil and not Secret(e.id) and dejaIds[e.id])
        if not deja and aPart and e.nuisible then
            table.insert(aPart, { cle = CleAura(e, i), e = e })
            deja = true
        end
        if not deja then
            local cle = CleAura(e, i)
            vus[cle] = e
            if not placesFile[cle] then table.insert(aPlacer, cle) end
        end
    end
    -- Ceux qui sont partis liberent leur place ; les nouveaux prennent la
    -- premiere place libre ; les autres ne bougent pas.
    local prises = {}
    for cle, rang in pairs(placesFile) do
        if vus[cle] and rang <= libres then prises[rang] = cle else placesFile[cle] = nil end
    end
    local nouveaux = {}
    for _, cle in ipairs(aPlacer) do
        for rang = 1, libres do
            if not prises[rang] then
                prises[rang], placesFile[cle] = cle, rang
                nouveaux[cle] = true
                break
            end
        end
    end
    -- Equilibree : les presents se repartissent sur toutes les places libres.
    if dispo == "equilibre" then
        local presents = {}
        for rang = 1, libres do if prises[rang] then table.insert(presents, prises[rang]) end end
        local nb = #presents
        local neuf = {}
        for i, cle in ipairs(presents) do
            local rang = math.floor((i - 1) * libres / nb) + 1
            neuf[rang] = cle
            placesFile[cle] = rang
        end
        prises = neuf
    end
    local maxi = 0
    for rang = 1, libres do
        local cle = prises[rang]
        local p = Prendre(anneau, debutFile + rang, racine)
        if cle then
            local e = vus[cle]
            p.aura, p.colonne, p.absent = e, nil, false
            pcall(p.icone.SetTexture, p.icone, e.icone)
            Cercler(p, e.nuisible and "nuisible" or "actif")
            p.icone:SetVertexColor(1, 1, 1)
            p.compte:SetText("")
            p.duree:SetText("")
            if e.bouton then
                Recopier(p.compte, e.texteCompte)
                if not PoserRecharge(p, e.expiration, e.duree, nil, e.id) then Recopier(p.duree, e.texteDuree, true) end
            else
                pcall(function() if not Secret(e.compte) and (e.compte or 0) > 1 then p.compte:SetText(e.compte) end end)
                PoserRecharge(p, e.expiration, e.duree, nil, e.id)
            end
            Poser(p, anglesFile[rang])
            if nouveaux[cle] and not premierDessin then Signaler(p) end
            maxi = debutFile + rang
        else
            p:Hide()
        end
    end
    for i = debutFile + libres + 1, #anneau do anneau[i]:Hide() end
    DessinerNuisibles(r, aPart or {}, rayon, t)
    premierDessin = false
end

-- ---------------------------------------------------------------------------
-- Infobulles
-- ---------------------------------------------------------------------------

local function BulleDAura(id, index, nuisible)
    local G = GameTooltip
    local filtre = nuisible and "HARMFUL" or "HELPFUL"
    local parId = nuisible and G.SetUnitDebuffByAuraInstanceID or G.SetUnitBuffByAuraInstanceID
    if id ~= nil and parId then
        if pcall(parId, G, "player", id, filtre) then return true end
    end
    if index ~= nil and G.SetUnitAura then
        if pcall(G.SetUnitAura, G, "player", index, filtre) then return true end
    end
    return false
end

Bulle = function(p)
    local G = GameTooltip
    G:SetOwner(p, "ANCHOR_RIGHT")
    local a, e = p.aura, p.colonne
    if a then
        local index = a.index
        if index == nil and a.bouton and a.bouton.GetID then index = a.bouton:GetID() end
        if not BulleDAura(a.id, index, a.nuisible) then
            G:SetText(a.nuisible and T("Amélioration nuisible", "Debuff") or T("Amélioration", "Buff"), 1, 0.82, 0)
        end
    elseif e then
        local vert, gris = { 0.3, 1, 0.3 }, { 0.6, 0.6, 0.6 }
        if e.potion then
            if not pcall(G.SetItemByID, G, e.potion) then G:SetText(T("Potion", "Potion"), 1, 0.82, 0) end
            G:AddLine(T("Dans vos sacs : ", "In your bags : ") .. tostring(e.compte or 0), 1, 1, 1)
        elseif e.sort then
            if not pcall(G.SetSpellByID, G, e.sort) then G:SetText(D.Nom(e.sort) or "?", 1, 0.82, 0) end
            local classe = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[e.classe]) or e.classe
            G:AddLine(T("Donné par : ", "Given by : ") .. tostring(classe), 1, 1, 1)
            if e.actif then G:AddLine(T("Actif", "Active"), unpack(vert)) else G:AddLine(T("Absent", "Missing"), unpack(gris)) end
        else
            G:SetText(e.titre or "", 1, 0.82, 0)
            if e.actif then
                G:AddLine(T("Actif : ", "Active : ") .. tostring(e.nom or ""), unpack(vert))
            else
                G:AddLine(T("Absent", "Missing"), unpack(gris))
            end
        end
        if InCombatLockdown and InCombatLockdown() and not e.potion then
            G:AddLine(T("État relevé avant le combat.", "State read before combat."), 0.6, 0.6, 0.6)
        end
    end
    G:Show()
end

-- ---------------------------------------------------------------------------
-- Dessin
-- ---------------------------------------------------------------------------

function A.Dessiner()
    local r = Reglages()
    racine:ClearAllPoints()
    racine:SetPoint("CENTER", UIParent, "CENTER", 0, r.hauteur)
    if r.cache then racine:Hide() return end
    racine:Show()
    -- Opacite generale de l'anneau (moins intrusif) ; les absents restent gris.
    racine:SetAlpha(r.opaciteAnneau)
    if not (InCombatLockdown and InCombatLockdown()) then pcall(Relever) end
    DessinerAnneau(r)
end

local attente = 0
racine:SetScript("OnUpdate", function(_, ecoule)
    attente = attente - (ecoule or 0)
    if attente > 0 then return end
    attente = 0.25
    local ok, souci = pcall(A.Dessiner)
    if not ok then A.dernierSouci = souci end
end)
