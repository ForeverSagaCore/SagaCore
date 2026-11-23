local _, NS = ...

-- Page Carte de QuestCore : la carte de la zone telle que le jeu la dessine,
-- zones explorees, et a la demande toute la zone revelee ; la position du
-- personnage ; les reperes des quetes et les parcours choisis, avec le
-- trajet a suivre depuis le personnage, etape par etape.
-- Molette : zoom sous le curseur. Glisser : deplacer.
-- Les choix (zone, parcours, affichage) sont dans le bas du menu de gauche.
-- En option, la fenetre s'efface quand on court : seul le trajet reste net.

NS.pageCarte = {}
local page = NS.pageCarte
local L = NS.L

local TUILE = 256
local ZOOM_MAX = 6
local HAUT_TITRE = 30
-- Sous la carte : la rangee de filtres.
local BAS_CARTE = 50
local ALPHA_COURSE = 0.05
local COULEURS_TRAJET = { { 1, 0.82, 0 }, { 0.45, 0.8, 1 }, { 0.5, 0.95, 0.4 }, { 0.82, 0.55, 1 } }

local vue, menu, calque
local carteChoisie             -- uiMapID affiche, nil = la zone du personnage
local zoom, decX, decY = 1, 0, 0
local derniereCarte

local function Lecture(chemin) return NS.Lecture(chemin) end

local function Reglages()
    local g = NS.base.ReglagesGeneraux()
    g.cartePage = g.cartePage or {}
    local r = g.cartePage
    if r.reveler == nil then r.reveler = true end
    if r.autres == nil then r.autres = true end
    if r.fondu == nil then r.fondu = false end
    if r.disponibles == nil then r.disponibles = true end
    if r.temps == nil then r.temps = true end
    return r
end

page.Reglages = Reglages

-- Carte cloisonnee sur l'objectif de QuestCore guide : ouverte au lancement
-- du guidage, elle ne montre que lui (ni recolte, ni reperes, ni autres
-- quetes, ni filtres) et la liste de ses etapes a gauche, dans l'ordre vise.
-- Un parcours guide garde sa liste a lui.
local modeTrajet = false
local function TrajetCourant()
    local g = NS.guidage
    local a = g and g.Objectif and g.Objectif()
    if not a then return nil end
    if a.type == "parcours" then
        return NS.parcours and NS.parcours.TrouverUid(NS.ClePersonnage(), a.params.uid)
    end
    local etapes = {}
    for _, e in ipairs(g.Etapes and g.Etapes() or {}) do if e.id then table.insert(etapes, e.id) end end
    return { nom = a.libelle, etapes = etapes }
end
local queteSeule
function page.ModeTrajet(oui)
    modeTrajet = oui == true
    if oui then carteChoisie = nil queteSeule = nil end
    if NS.carte then NS.carte.Invalider() end
end
function page.EnModeTrajet() return modeTrajet and TrajetCourant() ~= nil end

-- Entree d'un donjon a montrer (page Donjons) : la carte de sa zone, un
-- repere a l'entree.
local entree
-- Une entree posee sur la carte d'une ville ou d'un sous-sol (Fossoyeuse...)
-- se montre la ou elle est dans le monde : sur la carte de la zone qui la
-- contient, tant que cette zone l'englobe.
local function SurLaZone(idCarte, x, y)
    local info, rect = Lecture("C_Map.GetMapInfo"), Lecture("C_Map.GetMapRectOnMap")
    if not (info and rect) then return idCarte, x, y end
    for _ = 1, 3 do
        local i = NS.Appeler(info, idCarte)
        local parent = type(i) == "table" and i.parentMapID
        local p = parent and NS.Appeler(info, parent)
        if type(p) ~= "table" or p.mapType ~= 3 then break end
        local g, d, h, b = NS.Appeler(rect, idCarte, parent)
        if not (g and d and h and b) or d - g <= 0 or b - h <= 0 then break end
        idCarte, x, y = parent, g + x * (d - g), h + y * (b - h)
    end
    return idCarte, x, y
end
page.SurLaZone = SurLaZone
function page.MontrerEntree(idCarte, x, y, nom)
    idCarte, x, y = SurLaZone(idCarte, x, y)
    modeTrajet = false
    quetePointee = nil
    queteSeule = nil
    entree = { carte = idCarte, x = x, y = y, nom = nom }
    carteChoisie = idCarte
end

-- Une quete a prendre, montree depuis "Voir sur la carte" : l'icone de la
-- quete (le point d'exclamation, pas le PNJ), qui pulse doucement.
local quetePointee

-- Quete seule (longue-vue du suivi) : la carte ne montre que ses reperes,
-- jusqu'a "Revenir a ma position" ou un autre lieu montre.
function page.QueteSeule() return queteSeule end

function page.MontrerQuete(id, idCarte, x, y, nomQuete, nomDonneur, sansFleche, genre, seule)
    queteSeule = seule and id or nil
    -- Lieu dans un donjon : la carte de l'instance n'est pas affichable ici
    -- (elle partait en carte du continent etiree) ; on montre son entree.
    if NS.carte and NS.carte.EstInstance and NS.carte.EstInstance(idCarte) then
        local e = NS.carte.EntreeDInstance(idCarte)
        if not e then return end
        idCarte, x, y = SurLaZone(e.carte, e.x, e.y)
    end
    modeTrajet = false
    entree = nil
    quetePointee = { carte = idCarte, x = x, y = y, quete = id, nom = nomQuete, donneur = nomDonneur, genre = genre }
    carteChoisie = idCarte
    -- Voir sur la carte ne guide pas : la fleche part au clic sur le point
    -- violet (objectif "quetes" de cette seule quete).
end

local function PoserQuetePointee(idCarte)
    if not vue then return end
    if not vue.pointee then
        -- Le meme point d'exclamation que les autres quetes, a la meme taille,
        -- mais violet (le jaune, le bleu et l'orange ont deja un sens) et qui
        -- clignote : il apparait, disparait, apparait...
        local b = CreateFrame("Button", nil, vue.toile)
        b:SetSize(22, 22)
        b.t = b:CreateTexture(nil, "ARTWORK")
        b.t:SetPoint("CENTER")
        if b.t.SetAtlas and pcall(b.t.SetAtlas, b.t, "QuestNormal") and b.t:GetAtlas() then
            b.t:SetSize(20, 20)
        else
            b.t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            b.t:SetSize(16, 16)
        end
        b.t:SetDesaturated(true)
        b.t:SetVertexColor(0.78, 0.45, 1)
        local ag = b:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fondu = ag:CreateAnimation("Alpha")
        fondu:SetFromAlpha(1)
        fondu:SetToAlpha(0)
        fondu:SetDuration(0.6)
        b.anim = ag
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.nom or "", 1, 0.82, 0)
            if self.donneur then GameTooltip:AddLine(string.format(L.DUNGEON_GIVER, self.donneur), 1, 1, 1) end
            GameTooltip:AddLine(L.MAP_GUIDE_CLICK, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Clic : la fleche de guidage de la suite mene a cette quete (ses
        -- objectifs, puis son rendu).
        b:SetScript("OnClick", function(self)
            local q = quetePointee
            local api = _G.QuestCoreAPI
            if q and q.quete and api and api.GuiderQuetes then api.GuiderQuetes({ q.quete }) end
            GameTooltip:Hide()
        end)
        vue.pointee = b
    end
    local b = vue.pointee
    if quetePointee and quetePointee.carte == idCarte then
        b.ax, b.ay, b.nom, b.donneur = quetePointee.x, quetePointee.y, quetePointee.nom, quetePointee.donneur
        -- Quete deja prise : pas le point d'exclamation (a prendre), mais
        -- l'icone de son etat, celle du journal (en cours ou a rendre).
        local g = quetePointee.genre
        if b.genre ~= g then
            b.genre = g
            if g == "rendre" or g == "objectif" then
                b.t:SetTexture(g == "rendre" and "Interface\\GossipFrame\\ActiveQuestIcon"
                    or "Interface\\GossipFrame\\IncompleteQuestIcon")
                b.t:SetSize(16, 16)
            elseif b.t.SetAtlas and pcall(b.t.SetAtlas, b.t, "QuestNormal") and b.t:GetAtlas() then
                b.t:SetSize(20, 20)
            else
                b.t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                b.t:SetSize(16, 16)
            end
        end
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 25)
        b:Show()
        -- D'abord un halo dore qui s'elargit (deux fois) pour dire "c'est
        -- ici", puis seulement le clignotement, qui reste. Comme MapCore.
        local maintenant = NS.Appeler(GetTime) or 0
        if not quetePointee.haloFait then
            quetePointee.haloFait = true
            quetePointee.debutClignote = maintenant + 1.6
            if not b.ping then
                local f = CreateFrame("Frame", nil, b)
                f:SetPoint("CENTER")
                f:SetSize(44, 44)
                local t = f:CreateTexture(nil, "BACKGROUND")
                t:SetAllPoints()
                t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                t:SetVertexColor(1, 0.82, 0)
                t:SetBlendMode("ADD")
                local ag = f:CreateAnimationGroup()
                ag:SetLooping("REPEAT")
                local taille = ag:CreateAnimation("Scale")
                if taille.SetScaleFrom then taille:SetScaleFrom(0.3, 0.3) taille:SetScaleTo(1.4, 1.4)
                else taille:SetFromScale(0.3, 0.3) taille:SetToScale(1.4, 1.4) end
                taille:SetDuration(0.8)
                local fondu = ag:CreateAnimation("Alpha")
                fondu:SetFromAlpha(0.9)
                fondu:SetToAlpha(0)
                fondu:SetDuration(0.8)
                f.anim = ag
                b.ping = f
            end
            if b.anim then b.anim:Stop() end
            b.t:SetAlpha(1)
            b.ping:Show()
            b.ping.anim:Play()
            local ping, cible = b.ping, quetePointee
            local plusTard = NS.Lecture("C_Timer.After")
            if plusTard then
                plusTard(1.6, function()
                    ping.anim:Stop()
                    ping:Hide()
                    if quetePointee == cible and b:IsShown() and b.anim then b.anim:Play() end
                end)
            end
        elseif maintenant >= (quetePointee.debutClignote or 0) and b.anim and not b.anim:IsPlaying() then
            b.anim:Play()
        end
    else
        if b.anim then b.anim:Stop() end
        b:Hide()
    end
end

local function PoserEntree(idCarte)
    if not vue then return end
    if not vue.entree then
        local b = CreateFrame("Button", nil, vue.toile)
        b:SetSize(24, 24)
        b.t = b:CreateTexture(nil, "ARTWORK")
        b.t:SetAllPoints()
        if not (b.t.SetAtlas and pcall(b.t.SetAtlas, b.t, "Dungeon") and b.t:GetAtlas()) then
            b.t:SetTexture("Interface\\Icons\\INV_Misc_Key_14")
            if b.t.SetMask then pcall(b.t.SetMask, b.t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
        end
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.nom or "", 1, 0.82, 0)
            GameTooltip:AddLine(L.DUNGEON_ENTRANCE_PIN, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        vue.entree = b
    end
    local b = vue.entree
    if entree and entree.carte == idCarte then
        b.ax, b.ay, b.nom = entree.x, entree.y, entree.nom
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 20)
        b:Show()
    else
        b:Hide()
    end
end

local function NomDeCarte(id)
    local info = NS.Appeler(Lecture("C_Map.GetMapInfo"), id)
    return type(info) == "table" and info.name or ("#" .. tostring(id))
end

local function CarteDuPerso()
    return NS.Appeler(Lecture("C_Map.GetBestMapForUnit"), "player")
end

local function PositionJoueur(idCarte)
    local pos = NS.Appeler(Lecture("C_Map.GetPlayerMapPosition"), idCarte, "player")
    local x, y
    if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then return nil end
    return x, y
end

local function Bouton(parent, texte, largeurMin)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(20)
    b:SetText(texte or "")
    b:SetWidth(math.max(largeurMin or 40, (b.GetTextWidth and b:GetTextWidth() or 40) + 24))
    return b
end

-- ---------------------------------------------------------------------------
-- Calque du trajet : au-dessus de la carte, mais pas dans la fenetre, pour
-- rester net quand la fenetre s'efface en course.
-- ---------------------------------------------------------------------------

local function Calque()
    if calque then return calque end
    calque = CreateFrame("Frame", nil, UIParent)
    calque:SetAllPoints(vue.clip)
    if calque.SetClipsChildren then calque:SetClipsChildren(true) end
    calque:EnableMouse(false)
    calque.fleche = calque:CreateTexture(nil, "OVERLAY")
    calque.fleche:SetTexture("Interface\\Minimap\\MinimapArrow")
    calque.fleche:SetSize(30, 30)
    calque.fleche:Hide()
    -- Distance et temps estime jusqu'a la prochaine etape, en bas a gauche.
    calque.temps = calque:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calque.temps:SetPoint("BOTTOMLEFT", calque, "BOTTOMLEFT", 10, 10)
    calque.fondTemps = calque:CreateTexture(nil, "ARTWORK")
    calque.fondTemps:SetColorTexture(0, 0, 0, 0.6)
    calque.fondTemps:SetPoint("TOPLEFT", calque.temps, "TOPLEFT", -6, 4)
    calque.fondTemps:SetPoint("BOTTOMRIGHT", calque.temps, "BOTTOMRIGHT", 6, -4)
    calque.temps:Hide()
    calque.fondTemps:Hide()
    calque:Hide()
    return calque
end

-- Position d'un point de la carte (0 a 1) dans le calque.
local function VersCalque(u, v)
    local k = (vue.clip:GetEffectiveScale() or 1) / (calque:GetEffectiveScale() or 1)
    return (decX + u * vue.largeur * vue.echelle) * k, (decY + v * vue.hauteur * vue.echelle) * k
end

-- Un point du chemin : petit rond du jeu.
local function Point(rang)
    calque.points = calque.points or {}
    local t = calque.points[rang]
    if not t then
        t = calque:CreateTexture(nil, "ARTWORK")
        if not (t.SetAtlas and pcall(t.SetAtlas, t, "WhiteCircle-RaidBlips") and t:GetAtlas()) then
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        calque.points[rang] = t
    end
    return t
end

local ESPACE_POINTS = 11

-- Pointilles d'un point a un autre, a pas reguliers a l'ecran.
local function Pointilles(rang, ax, ay, bx, by, c, taille, alpha)
    local dx, dy = bx - ax, by - ay
    local longueur = math.sqrt(dx * dx + dy * dy)
    local n = math.max(1, math.floor(longueur / ESPACE_POINTS))
    for i = 1, n do
        if rang >= 600 then return rang end
        local f = (i - 0.5) / n
        rang = rang + 1
        local t = Point(rang)
        t:ClearAllPoints()
        t:SetSize(taille, taille)
        t:SetPoint("CENTER", calque, "TOPLEFT", ax + dx * f, -(ay + dy * f))
        t:SetVertexColor(c[1], c[2], c[3], alpha)
        t:Show()
    end
    return rang
end

-- Distance en metres entre deux points d'une carte (coordonnees du monde du
-- jeu, en yards), ou nil si le client ne la donne pas.
local function Metres(idCarte, x1, y1, x2, y2)
    local f, V = Lecture("C_Map.GetWorldPosFromMapPos"), _G.CreateVector2D
    if f and V then
        local ok1, _, a = pcall(f, idCarte, V(x1, y1))
        local ok2, _, b = pcall(f, idCarte, V(x2, y2))
        if ok1 and ok2 and a and b and a.GetXY and b.GetXY then
            local ax, ay = a:GetXY()
            local bx, by = b:GetXY()
            return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) * 0.9144
        end
    end
    local taille = Lecture("C_Map.GetMapWorldSize")
    if taille then
        local ok, l, h = pcall(taille, idCarte)
        if ok and tonumber(l) and tonumber(h) and l > 0 then
            return math.sqrt(((x1 - x2) * l) ^ 2 + ((y1 - y2) * h) ^ 2) * 0.9144
        end
    end
    return nil
end

-- Vitesse retenue : la derniere vue en mouvement (monture comprise), sinon
-- la course a pied (7 yards par seconde).
local vitesseRetenue = 7
local function TempsEstime(metres)
    local v = NS.Appeler(GetUnitSpeed, "player") or 0
    -- En combat, le jeu peut rendre une valeur secrete : on ne s'en sert pas.
    if _G.issecretvalue and _G.issecretvalue(v) then v = 0 end
    if v > 0 then vitesseRetenue = v end
    local secondes = math.floor(metres / 0.9144 / vitesseRetenue + 0.5)
    if secondes < 60 then return string.format(L.MAPPAGE_SECONDS, secondes) end
    return string.format(L.MAPPAGE_MINUTES, math.floor(secondes / 60), secondes % 60)
end

-- Distance et temps jusqu'a la prochaine etape : une ligne de plus dans le
-- cadre de la legende (plus de rectangle noir a part).
local function MontrerTemps(cible, jx, jy)
    if calque and calque.temps then calque.temps:Hide() calque.fondTemps:Hide() end
    local f = vue and vue.legende
    if not f then return end
    local metres = cible and jx and Reglages().temps and Metres(vue.idCarte, jx, jy, cible.x, cible.y)
    if not f.eta then
        f.eta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.eta:SetJustifyH("LEFT")
    end
    local n = f.nLignes or 0
    if metres then
        f.eta:SetText(string.format(L.MAPPAGE_ETA, cible.texte, math.floor(metres + 0.5), TempsEstime(metres)))
        f.eta:ClearAllPoints()
        f.eta:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8 - n * 15)
        f.eta:Show()
        local largeur = math.max(f.largeurBase or 0, f.eta:GetStringWidth() or 0)
        f:SetSize(largeur + 20, (n + 1) * 15 + 14)
        f:Show()
    else
        f.eta:Hide()
        if n > 0 then f:SetSize((f.largeurBase or 0) + 20, n * 15 + 14) else f:Hide() end
    end
end

-- Le trajet de chaque parcours trace : du personnage a la prochaine etape,
-- puis d'etape en etape, dans l'ordre. Le premier troncon est plus epais.
-- Legende des trajets, en bas a gauche de la carte : la couleur de chaque
-- parcours trace et son nom, et ce que veulent dire les points.
local function Legende(traces)
    local signature = {}
    for _, t in ipairs(traces) do table.insert(signature, t.nom .. t.couleur[1] .. t.couleur[2]) end
    signature = table.concat(signature, "|")
    if vue.legende and vue.legende.signature == signature then return end
    if not vue.legende then
        local ok, f = pcall(CreateFrame, "Frame", nil, vue.bord, "BackdropTemplate")
        f = ok and f or CreateFrame("Frame", nil, vue.bord)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
            f:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
        end
        f:SetPoint("BOTTOMLEFT", vue.bord, "BOTTOMLEFT", 8, 8)
        f:SetFrameLevel(vue.toile:GetFrameLevel() + 35)
        f.lignes = {}
        vue.legende = f
    end
    local f = vue.legende
    f.signature = signature
    for _, l in ipairs(f.lignes) do l:Hide() end
    f.nLignes, f.largeurBase = 0, 0
    if #traces == 0 then f:Hide() return end
    local function Ligne(rang)
        local l = f.lignes[rang]
        if not l then
            l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            l:SetJustifyH("LEFT")
            f.lignes[rang] = l
        end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8 - (rang - 1) * 15)
        l:Show()
        return l
    end
    local largeur = 0
    for rang, t in ipairs(traces) do
        local c = t.couleur
        local l = Ligne(rang)
        -- Trois points ronds de la couleur du trace (disque du jeu, teinte).
        local point = string.format("|TInterface\\CharacterFrame\\TempPortraitAlphaMask:7:7:0:0:64:64:0:64:0:64:%d:%d:%d|t",
            math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
        l:SetText(point .. " " .. point .. " " .. point .. "   " .. t.nom)
        largeur = math.max(largeur, l:GetStringWidth() or 0)
    end
    local aide = Ligne(#traces + 1)
    aide:SetText("|cffb3b3b3" .. L.MAPPAGE_LEGEND_HELP .. "|r")
    largeur = math.max(largeur, aide:GetStringWidth() or 0)
    f.nLignes, f.largeurBase = #traces + 1, largeur
    f:SetSize(largeur + 20, (#traces + 1) * 15 + 14)
    f:Show()
end

local function DessinerTrajet()
    if not calque or not vue.largeur then return end
    local fenetre = _G.QuestCoreFenetre
    calque:SetFrameStrata(vue.filigrane and "BACKGROUND" or (fenetre and fenetre:GetFrameStrata()) or "MEDIUM")
    calque:SetFrameLevel(math.min((vue.clip:GetFrameLevel() or 1) + 40, 9000))
    for _, t in ipairs(calque.points or {}) do t:Hide() end
    local jx, jy = PositionJoueur(vue.idCarte)
    -- Centre de chaque etape, par parcours.
    local parParcours = {}
    for i = 1, vue.enService do
        local b = vue.reperes[i]
        local pt = b.point
        if pt and pt.numero and pt.idParcours then
            local etapes = parParcours[pt.idParcours] or {}
            parParcours[pt.idParcours] = etapes
            local s = etapes[pt.numero] or { x = 0, y = 0, n = 0, attente = pt.attente }
            -- Au repere tel qu'il est pose (ecarte de ses voisins s'il le faut).
            local e = vue.echelle or 1
            local ex = (b.ecartX or 0) / math.max(1, vue.largeur * e)
            local ey = (b.ecartY or 0) / math.max(1, vue.hauteur * e)
            s.x, s.y, s.n = s.x + b.ax + ex, s.y + b.ay + ey, s.n + 1
            etapes[pt.numero] = s
        end
    end
    local rangPoint, rangCouleur = 0, 0
    -- Cible du temps estime : le receveur le plus proche avec le filtre "a
    -- rendre", sinon la prochaine etape du premier parcours trace.
    local cible
    if jx and NS.base.FiltreARendre() then
        local meilleur
        for i = 1, vue.enService do
            local b = vue.reperes[i]
            if b.point and b.point.genre == "rendre" then
                local d = (b.ax - jx) ^ 2 + (b.ay - jy) ^ 2
                if not meilleur or d < meilleur then
                    meilleur = d
                    cible = { x = b.ax, y = b.ay, texte = b.point.quoi or b.point.titre or L.MAPPAGE_TURNIN }
                end
            end
        end
    end
    local traces = {}
    for _, pc in ipairs(NS.parcours.Liste(NS.ClePersonnage())) do
        local etapes = parParcours[pc.id]
        if pc.carte and etapes then
            rangCouleur = rangCouleur + 1
            local c = COULEURS_TRAJET[((rangCouleur - 1) % #COULEURS_TRAJET) + 1]
            table.insert(traces, { nom = pc.nom or "?", couleur = c })
            local numeros = {}
            for n in pairs(etapes) do table.insert(numeros, n) end
            table.sort(numeros)
            local chemin = {}
            if jx then table.insert(chemin, { jx, jy }) end
            for _, n in ipairs(numeros) do
                local s = etapes[n]
                table.insert(chemin, { s.x / s.n, s.y / s.n, s.attente })
                if not cible and jx and not s.attente then
                    cible = { x = s.x / s.n, y = s.y / s.n, texte = string.format(L.MAPPAGE_STEP, n) }
                end
            end
            for i = 2, #chemin do
                local ax, ay = VersCalque(chemin[i - 1][1], chemin[i - 1][2])
                local bx, by = VersCalque(chemin[i][1], chemin[i][2])
                -- Le premier troncon (ou aller maintenant) en points plus gros.
                local premier = (i == 2)
                rangPoint = Pointilles(rangPoint, ax, ay, bx, by, c, premier and 7 or 5,
                    chemin[i][3] and 0.45 or 0.95)
            end
        end
    end
    local okL, souciL = pcall(Legende, traces)
    if not okL then NS.base.NoterIncident("legende des trajets", souciL) end
    if vue.legende then
        vue.legende:SetFrameStrata(calque:GetFrameStrata())
        vue.legende:SetFrameLevel(math.min((calque:GetFrameLevel() or 1) + 5, 9500))
    end
    MontrerTemps(cible, jx, jy)
end

function page.PlacerJoueur()
    if not vue or not vue:IsVisible() or not vue.idCarte or not vue.echelle or not calque then return end
    local x, y = PositionJoueur(vue.idCarte)
    if not x then calque.fleche:Hide() return end
    local px, py = VersCalque(x, y)
    calque.fleche:ClearAllPoints()
    calque.fleche:SetPoint("CENTER", calque, "TOPLEFT", px, -py)
    local cap = NS.Appeler(Lecture("GetPlayerFacing"))
    if cap and calque.fleche.SetRotation then calque.fleche:SetRotation(cap) end
    calque.fleche:Show()
end

-- ---------------------------------------------------------------------------
-- Zoom et deplacement
-- ---------------------------------------------------------------------------

-- Cadre a la proportion exacte de la carte, centre dans la place ; puis la
-- toile : echelle d'ajustement x zoom, decalage borne.
local function Disposer()
    if not vue or not vue.largeur then return end
    local placeL = (vue:GetWidth() or 0)
    local placeH = (vue:GetHeight() or 0) - HAUT_TITRE - BAS_CARTE
    if placeL <= 0 or placeH <= 0 then placeL, placeH = 780, 480 end
    local ajuste = math.min((placeL - 8) / vue.largeur, (placeH - 8) / vue.hauteur)
    local l0, h0 = vue.largeur * ajuste, vue.hauteur * ajuste
    vue.bord:ClearAllPoints()
    vue.bord:SetPoint("TOP", vue, "TOP", 0, -HAUT_TITRE)
    vue.bord:SetSize(l0 + 8, h0 + 8)

    local echelle = ajuste * zoom
    local l, h = vue.largeur * echelle, vue.hauteur * echelle
    decX = math.min(0, math.max(l0 - l, decX))
    decY = math.min(0, math.max(h0 - h, decY))
    vue.toile:SetScale(echelle)
    vue.toile:ClearAllPoints()
    vue.toile:SetPoint("TOPLEFT", vue.clip, "TOPLEFT", decX / echelle, -decY / echelle)
    vue.echelle = echelle
    -- Tous les reperes affiches, poses ensemble : ceux qui tombent au meme
    -- endroit sont mis cote a cote, jamais empiles.
    local poses = {}
    local function Prendre(b)
        if not (b and b.ax and b.ay) then return end
        b:SetScale(1 / echelle)
        table.insert(poses, { b = b, x = b.ax * vue.largeur * echelle, y = b.ay * vue.hauteur * echelle,
            taille = math.max(b:GetWidth() or 0, b:GetHeight() or 0, 16),
            ordre = b.point and b.point.numero or nil })
    end
    for i = 1, vue.enService do Prendre(vue.reperes[i]) end
    for _, b in ipairs(vue.lieux or {}) do if b:IsShown() then Prendre(b) end end
    if vue.pointee and vue.pointee:IsShown() then Prendre(vue.pointee) end
    if vue.entree and vue.entree:IsShown() then Prendre(vue.entree) end
    for _, b in ipairs(vue.mapcore or {}) do if b:IsShown() then Prendre(b) end end
    -- Recalcule seulement si le zoom ou les reperes changent (pas en glissant).
    local morceaux = { string.format("%.4f", echelle) }
    for _, e in ipairs(poses) do morceaux[#morceaux + 1] = string.format("%.3f,%.3f", e.b.ax, e.b.ay) end
    local cle = table.concat(morceaux, ":")
    if cle ~= vue.cleEcart then
        vue.cleEcart = cle
        local Suite = NS.suite or _G.CoreSuite
        if Suite and Suite.Ecarter then pcall(Suite.Ecarter, poses, 22) end
        for _, e in ipairs(poses) do e.b.ecartX, e.b.ecartY = e.dx or 0, e.dy or 0 end
    end
    for _, e in ipairs(poses) do
        e.b:ClearAllPoints()
        e.b:SetPoint("CENTER", vue.toile, "TOPLEFT", e.x + (e.b.ecartX or 0), -(e.y + (e.b.ecartY or 0)))
    end
    DessinerTrajet()
    page.PlacerJoueur()
end

local function CurseurDansClip()
    local x, y = GetCursorPosition()
    local s = vue.clip:GetEffectiveScale()
    return x / s - (vue.clip:GetLeft() or 0), (vue.clip:GetTop() or 0) - y / s
end

local function Zoomer(facteur, autourX, autourY)
    if not vue.largeur then return end
    local ancien = zoom
    zoom = math.max(1, math.min(ZOOM_MAX, zoom * facteur))
    if zoom == ancien then return end
    autourX = autourX or (vue.clip:GetWidth() or 0) / 2
    autourY = autourY or (vue.clip:GetHeight() or 0) / 2
    local r = zoom / ancien
    decX = autourX - (autourX - decX) * r
    decY = autourY - (autourY - decY) * r
    Disposer()
end

-- La fenetre s'efface en course, si demande ; nette a l'arret ou au survol.
-- Le survol ne compte que si la souris a bouge depuis peu : a la manette,
-- le curseur cache reste pose sur la fenetre et l'empechait de s'effacer.
-- En avancant, la camera qui suit le personnage fait trembler le curseur
-- cache de quelques pixels : il passait pour "bouge" et la fenetre restait
-- nette (a reculons, la camera ne tourne pas, d'ou l'effet). Desormais : la
-- manette active ou la camera tenue a la souris ne comptent jamais comme un
-- survol, et seul un vrai deplacement de la souris (plus de 6 pixels) compte.
local curseurX, curseurY, dernierBouge = nil, nil, 0
local function SourisSur(fenetre)
    local pad = _G.C_GamePad
    if pad and pad.IsEnabled then
        local ok, actif = pcall(pad.IsEnabled)
        if ok and actif then return false end
    end
    if IsMouselooking and IsMouselooking() then return false end
    local x, y = GetCursorPosition()
    x, y = x or 0, y or 0
    local maintenant = GetTime and GetTime() or 0
    if not curseurX or math.abs(x - curseurX) + math.abs(y - curseurY) > 6 then
        curseurX, curseurY, dernierBouge = x, y, maintenant
    end
    return fenetre:IsMouseOver() and (maintenant - dernierBouge) < 2
end

local function Fondu(ecoule)
    -- La suite efface toutes ses fenetres quand on marche : rien a faire ici.
    do return end
    local fenetre = _G.QuestCoreFenetre
    if not fenetre then return end
    local cible = 1
    if Reglages().fondu and not SourisSur(fenetre) then
        local vitesse = NS.Appeler(GetUnitSpeed, "player") or 0
    -- En combat, le jeu peut rendre une valeur secrete : on ne s'en sert pas.
    if _G.issecretvalue and _G.issecretvalue(vitesse) then vitesse = 0 end
        if vitesse > 0 then cible = ALPHA_COURSE end
    end
    local actuel = fenetre:GetAlpha() or 1
    if math.abs(actuel - cible) < 0.01 then return end
    local pas = 3 * (ecoule or 0.05)
    if actuel < cible then actuel = math.min(cible, actuel + pas) else actuel = math.max(cible, actuel - pas) end
    fenetre:SetAlpha(actuel)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function Construire(parent, basDroite)
    vue = CreateFrame("Frame", nil, parent)
    vue.ancres = { parent = parent, basDroite = basDroite }
    vue:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    vue:SetPoint("BOTTOMRIGHT", basDroite, "BOTTOMRIGHT", 0, 0)

    -- Nom de la zone, centre au-dessus de la carte, comme la carte du jeu.
    vue.titre = vue:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    vue.titre:SetPoint("TOP", vue, "TOP", 0, -4)

    local ok, bord = pcall(CreateFrame, "Frame", nil, vue, "BackdropTemplate")
    bord = ok and bord or CreateFrame("Frame", nil, vue)
    if bord.SetBackdrop then
        bord:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bord:SetBackdropColor(0, 0, 0, 1)
        bord:SetBackdropBorderColor(0.75, 0.6, 0.35, 1)
    end
    vue.bord = bord

    local clip = CreateFrame("Frame", nil, bord)
    clip:SetPoint("TOPLEFT", bord, "TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMRIGHT", bord, "BOTTOMRIGHT", -4, 4)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:EnableMouse(true)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(_, sens)
        local x, y = CurseurDansClip()
        Zoomer(sens > 0 and 1.25 or 0.8, x, y)
    end)
    clip:SetScript("OnMouseDown", function(_, bouton)
        if bouton ~= "LeftButton" then return end
        local x, y = CurseurDansClip()
        vue.saisie = { x = x, y = y, dx = decX, dy = decY }
    end)
    clip:SetScript("OnMouseUp", function() vue.saisie = nil end)
    vue.clip = clip

    local toile = CreateFrame("Frame", nil, clip)
    toile:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    vue.toile = toile
    toile.tuiles, toile.revelees, toile.explorees = {}, {}, {}
    vue.reperes, vue.enService = {}, 0

    vue.vide = bord:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    vue.vide:SetPoint("CENTER")
    vue.vide:Hide()

    -- En haut a gauche de la carte : revenir a sa position, ou aller voir la
    -- zone de la prochaine etape quand elle est ailleurs.
    vue.allerA = Bouton(bord, "", 60)
    vue.allerA:SetPoint("TOPLEFT", bord, "TOPLEFT", 8, -8)
    vue.allerA:SetFrameLevel(toile:GetFrameLevel() + 30)
    vue.allerA:Hide()

    local plus = Bouton(bord, "+", 24)
    vue.plus = plus
    plus:SetPoint("TOPRIGHT", bord, "TOPRIGHT", -8, -8)
    plus:SetFrameLevel(toile:GetFrameLevel() + 30)
    plus:SetScript("OnClick", function() Zoomer(1.5) end)
    local moins = Bouton(bord, "-", 24)
    vue.moins = moins
    moins:SetPoint("TOP", plus, "BOTTOM", 0, -2)
    moins:SetFrameLevel(toile:GetFrameLevel() + 30)
    moins:SetScript("OnClick", function() Zoomer(1 / 1.5) end)

    -- Filtres de la suite, sous la carte : les memes que dans MapCore.
    local Suite = NS.suite or _G.CoreSuite
    if Suite and Suite.BarreFiltres then
        vue.filtres = Suite.BarreFiltres(vue, function() page.Rendre() end, function() return vue.idCarte end)
        vue.filtres:Etendre(bord, 8)
    end

    vue:SetScript("OnSizeChanged", function() if vue:IsVisible() then Disposer() end end)
    Calque()
    vue:SetScript("OnShow", function() calque:Show() end)
    vue:SetScript("OnHide", function()
        calque:Hide()
        local fenetre = _G.QuestCoreFenetre
        if fenetre then fenetre:SetAlpha(1) end
    end)

    local attente = 0
    vue:SetScript("OnUpdate", function(_, ecoule)
        if vue.saisie then
            if not IsMouseButtonDown or IsMouseButtonDown("LeftButton") then
                local x, y = CurseurDansClip()
                decX = vue.saisie.dx + (x - vue.saisie.x)
                decY = vue.saisie.dy + (y - vue.saisie.y)
                Disposer()
            else
                vue.saisie = nil
            end
        end
        Fondu(ecoule)
        attente = attente - (ecoule or 0)
        if attente > 0 then return end
        attente = 0.15
        -- Le trajet part du personnage : il le suit.
        DessinerTrajet()
        page.PlacerJoueur()
    end)
    return vue
end

-- ---------------------------------------------------------------------------
-- Art de la zone
-- ---------------------------------------------------------------------------

local function Tuile(liste, rang, couche)
    local t = liste[rang]
    if not t then
        t = vue.toile:CreateTexture(nil, couche or "BACKGROUND")
        liste[rang] = t
    end
    return t
end

local function Cacher(liste) for _, t in ipairs(liste) do t:Hide() end end

local function PoserFond(idCarte)
    Cacher(vue.toile.tuiles)
    local couches = NS.Appeler(Lecture("C_Map.GetMapArtLayers"), idCarte)
    local couche = type(couches) == "table" and couches[1]
    if not couche then return nil end
    local textures = NS.Appeler(Lecture("C_Map.GetMapArtLayerTextures"), idCarte, 1)
    if type(textures) ~= "table" then return nil end
    local lignes = math.ceil(couche.layerHeight / couche.tileHeight)
    local colonnes = math.ceil(couche.layerWidth / couche.tileWidth)
    local rang = 0
    for i = 1, lignes do
        for j = 1, colonnes do
            rang = rang + 1
            local t = Tuile(vue.toile.tuiles, rang)
            t:ClearAllPoints()
            t:SetSize(couche.tileWidth, couche.tileHeight)
            t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", (j - 1) * couche.tileWidth, -(i - 1) * couche.tileHeight)
            t:SetTexture(textures[rang])
            t:Show()
        end
    end
    return couche.layerWidth, couche.layerHeight
end

-- Un morceau de carte decoupe en tuiles de 256, comme la carte du jeu.
local function PoserMorceau(liste, rang, largeur, hauteur, x, y, fichiers, couche, sousCouche, teinte)
    local large = math.ceil(largeur / TUILE)
    local haut = math.ceil(hauteur / TUILE)
    for j = 1, haut do
        local pxH, fichierH = TUILE, TUILE
        if j == haut then
            pxH = hauteur % TUILE
            if pxH == 0 then pxH = TUILE end
            fichierH = 16
            while fichierH < pxH do fichierH = fichierH * 2 end
        end
        for k = 1, large do
            local pxL, fichierL = TUILE, TUILE
            if k == large then
                pxL = largeur % TUILE
                if pxL == 0 then pxL = TUILE end
                fichierL = 16
                while fichierL < pxL do fichierL = fichierL * 2 end
            end
            local fichier = fichiers[(j - 1) * large + k]
            if fichier then
                rang = rang + 1
                local t = Tuile(liste, rang, couche)
                t:SetDrawLayer(couche, sousCouche)
                t:ClearAllPoints()
                t:SetSize(pxL, pxH)
                t:SetTexCoord(0, pxL / fichierL, 0, pxH / fichierH)
                t:SetPoint("TOPLEFT", vue.toile, "TOPLEFT", x + TUILE * (k - 1), -(y + TUILE * (j - 1)))
                t:SetTexture(fichier)
                t:SetVertexColor(teinte, teinte, teinte)
                t:Show()
            end
        end
    end
    return rang
end

local function PoserRevelees(idCarte)
    Cacher(vue.toile.revelees)
    if not Reglages().reveler then return 0 end
    local art = NS.Appeler(Lecture("C_Map.GetMapArtID"), idCarte)
    local morceaux = art and NS.reveleCarte and NS.reveleCarte[art]
    if type(morceaux) ~= "table" then return 0 end
    local rang = 0
    for cle, liste in pairs(morceaux) do
        local l, h, x, y = string.match(cle, "^(%d+):(%d+):(%d+):(%d+)$")
        if l then
            local fichiers = {}
            for id in string.gmatch(liste, "%d+") do table.insert(fichiers, tonumber(id)) end
            rang = PoserMorceau(vue.toile.revelees, rang, tonumber(l), tonumber(h), tonumber(x), tonumber(y),
                fichiers, "BORDER", 0, 0.6)
        end
    end
    return rang
end

local function PoserExplorees(idCarte)
    Cacher(vue.toile.explorees)
    local infos = NS.Appeler(Lecture("C_MapExplorationInfo.GetExploredMapTextures"), idCarte)
    if type(infos) ~= "table" then return 0 end
    local rang = 0
    for _, info in ipairs(infos) do
        rang = PoserMorceau(vue.toile.explorees, rang, info.textureWidth or 0, info.textureHeight or 0,
            info.offsetX or 0, info.offsetY or 0, info.fileDataIDs or {}, "BORDER", 1, 1)
    end
    return rang
end

-- ---------------------------------------------------------------------------
-- Reperes
-- ---------------------------------------------------------------------------

-- Reperes poses dans MapCore (s'il est installe) : icone de cible et note.
local function PoserReperesMapCore(idCarte)
    vue.mapcore = vue.mapcore or {}
    for _, b in ipairs(vue.mapcore) do b:Hide() end
    local api = _G.MapCoreAPI
    if not api then return end
    local Suite = NS.suite or _G.CoreSuite
    if Suite and Suite.Filtre and not Suite.Filtre("reperes") then return end
    local ok, liste = pcall(api.Reperes, idCarte)
    for rang, r in ipairs(ok and liste or {}) do
        local b = vue.mapcore[rang]
        if not b then
            b = CreateFrame("Button", nil, vue.toile)
            b:SetSize(18, 18)
            b.t = b:CreateTexture(nil, "ARTWORK")
            b.t:SetAllPoints()
            b.t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            b:SetScript("OnEnter", function(self)
                if not self.note or self.note == "" then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("MapCore", 1, 0.82, 0)
                GameTooltip:AddLine(self.note, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            vue.mapcore[rang] = b
        end
        local i = r.icone or 1
        local c, l = (i - 1) % 4, math.floor((i - 1) / 4)
        b.t:SetTexCoord(c * 0.25, (c + 1) * 0.25, l * 0.25, (l + 1) * 0.25)
        b.note = r.note
        b.ax, b.ay = r.x, r.y
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 12)
        b:Show()
    end
end

-- Lieux de recolte notes par CraftCore (s'il est installe) : icone ronde.
local function PoserLieux(idCarte)
    vue.lieux = vue.lieux or {}
    for _, b in ipairs(vue.lieux) do b:Hide() end
    local cc, Suite = _G.CraftCoreAPI, NS.suite or _G.CoreSuite
    if not (cc and cc.Lieux and Suite and Suite.PionRecolte) then return end
    local ok, lieux = pcall(cc.Lieux, idCarte)
    local garder = {}
    for _, l in ipairs(ok and lieux or {}) do
        if not Suite.LieuVisible or Suite.LieuVisible(l) then table.insert(garder, l) end
    end
    for rang, l in ipairs(garder) do
        local b = vue.lieux[rang]
        if not b then
            b = Suite.PionRecolte(vue.toile)
            vue.lieux[rang] = b
        end
        b:Poser(l)
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 1)
        b:Show()
    end
end

local function PoserReperes(idCarte)
    if QuestCoreDB then QuestCoreDB.diagCarte = nil end
    for i = 1, vue.enService do vue.reperes[i]:Hide() end
    vue.enService = 0
    -- Pendant le guidage : rien que le trajet (ni recolte, ni reperes, ni
    -- autres quetes).
    local guide = (NS.guidage and NS.guidage.Actif and NS.guidage.Actif()) or page.EnModeTrajet()
    if guide or queteSeule then
        for _, b in ipairs(vue.mapcore or {}) do b:Hide() end
        for _, b in ipairs(vue.lieux or {}) do b:Hide() end
    else
        pcall(PoserReperesMapCore, idCarte)
        pcall(PoserLieux, idCarte)
    end
    local Suite = NS.suite or _G.CoreSuite
    local autres = Reglages().autres
    local seulementRendre = NS.base.FiltreARendre()
    local liste = {}
    for _, pt in ipairs(NS.carte.TousLesPoints()) do
        local garder
        if seulementRendre then garder = pt.genre == "rendre" and not pt.dispo
        else garder = pt.numero or autres end
        -- Les etapes numerotees d'un trajet restent visibles quels que soient
        -- les filtres : sans elles, plus de trajet trace.
        if garder and not pt.numero and Suite and Suite.PointVisible and not Suite.PointVisible(pt) then garder = false end
        if guide and not pt.numero then garder = false end
        if queteSeule then garder = pt.quete == queteSeule end
        -- Zone par zone.
        -- Un itineraire (etapes numerotees d'un parcours affiche) reste entier,
        -- d'une zone a l'autre : c'est son affichage a lui.
        if garder and not pt.numero and not queteSeule and not NS.carte.ParZone(pt, idCarte) then garder = false end
        if garder then
            local x, y = NS.carte.Reporter(pt, idCarte)
            if x then table.insert(liste, { pt = pt, x = x, y = y }) end
        end
    end
    local function poids(e) return (e.pt.numero and 4 or 0) + ((e.pt.genre ~= "objectif") and 2 or 0) end
    table.sort(liste, function(a, b) return poids(a) < poids(b) end)
    for _, e in ipairs(liste) do
        vue.enService = vue.enService + 1
        local b = vue.reperes[vue.enService]
        if not b then
            b = NS.carte.CreerRepere(vue.toile)
            vue.reperes[vue.enService] = b
        end
        NS.carte.Habiller(b, e.pt.genre, e.pt.icone, e.pt.attente)
        b.point, b.ax, b.ay = e.pt, e.x, e.y
        b:SetFrameLevel(vue.toile:GetFrameLevel() + 2 + poids(e))
        -- Quete seule : son numero d'etape ne dit rien de plus, l'icone suffit.
        b.numero:SetText((e.pt.numero and not queteSeule) and tostring(e.pt.numero) or "")
        b:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Bas du menu de gauche : zones, parcours traces, affichage
-- ---------------------------------------------------------------------------

local function Changement()
    NS.carte.Invalider()
    pcall(NS.carte.Rendre)
    if NS.suivi then pcall(NS.suivi.Rendre) end
    page.Rendre()
end

local function LigneMenu(rang)
    menu.lignes = menu.lignes or {}
    local l = menu.lignes[rang]
    if l then return l end
    l = CreateFrame("Button", nil, menu)
    l:SetHeight(20)
    l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    l.fond = l:CreateTexture(nil, "BACKGROUND")
    l.fond:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    l.fond:SetBlendMode("ADD")
    l.fond:SetAllPoints()
    local ok, case = pcall(CreateFrame, "CheckButton", nil, l, "UICheckButtonTemplate")
    if ok and case then
        case:SetSize(20, 20)
        case:SetPoint("LEFT", l, "LEFT", 2, 0)
        case:EnableMouse(false)
        l.case = case
    end
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetJustifyH("LEFT")
    l.texte:SetWordWrap(false)
    menu.lignes[rang] = l
    return l
end

local function TitreMenu(rang)
    menu.titres = menu.titres or {}
    local t = menu.titres[rang]
    if not t then
        t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetJustifyH("LEFT")
        menu.titres[rang] = t
    end
    return t
end

local function RendreMenu(idCarte)
    if not menu then return end
    for _, l in ipairs(menu.lignes or {}) do l:Hide() end
    for _, t in ipairs(menu.titres or {}) do t:Hide() end
    for _, a in ipairs(menu.aides or {}) do a:Hide() end
    local y, nLigne, nTitre = 0, 0, 0
    local function Titre(texte, aide)
        nTitre = nTitre + 1
        local t = TitreMenu(nTitre)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
        t:SetText(texte)
        t:Show()
        y = y + 18
        if aide then
            menu.aides = menu.aides or {}
            local a = menu.aides[nTitre]
            if not a then
                a = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                a:SetJustifyH("LEFT")
                a:SetWordWrap(true)
                menu.aides[nTitre] = a
            end
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
            a:SetWidth((menu:GetWidth() or 170) - 10)
            a:SetText(aide)
            a:Show()
            y = y + (a:GetStringHeight() or 12) + 4
        end
    end
    -- case : nil (simple choix), true / false (case cochee ou non)
    local function Ligne(texte, case, choisie, auClic, survol, caseClic, couleur)
        nLigne = nLigne + 1
        local l = LigneMenu(nLigne)
        if l.case then
            l.case:EnableMouse(caseClic ~= nil)
            l.case:SetScript("OnClick", caseClic)
        end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -y)
        l:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
        l.texte:ClearAllPoints()
        if l.case and case ~= nil then
            l.case:Show()
            l.case:SetChecked(case)
            l.texte:SetPoint("LEFT", l, "LEFT", 24, 0)
        else
            if l.case then l.case:Hide() end
            l.texte:SetPoint("LEFT", l, "LEFT", 10, 0)
        end
        l.texte:SetPoint("RIGHT", l, "RIGHT", -2, 0)
        l.texte:SetText(texte)
        if couleur then l.texte:SetTextColor(couleur[1], couleur[2], couleur[3])
        else l.texte:SetTextColor(choisie and 1 or 0.9, choisie and 0.82 or 0.9, choisie and 0 or 0.9) end
        l.fond:SetShown(choisie == true)
        l:SetScript("OnClick", auClic)
        l:SetScript("OnEnter", survol)
        l:SetScript("OnLeave", survol and function() GameTooltip:Hide() end or nil)
        l:Show()
        y = y + 21
    end

    -- Carte cloisonnee sur le trajet : la liste de ses etapes, rien d'autre.
    local pcT = page.EnModeTrajet() and TrajetCourant()
    if pcT then
        local cle = NS.ClePersonnage()
        local moi = cle and NS.base.Perso(cle)
        Titre(pcT.nom or L.ROUTE_TURNIN_NAME, L.ROUTE_STEPS_HELP)
        -- Lieu d'une etape : la ou aller (receveur si a rendre, objectif sinon).
        local function Lieu(id)
            local q = moi and moi.quetes[id]
            local voulu = (q and q.complete == true) and "rendre" or (q and "objectif") or "prendre"
            local ok, pts = pcall(NS.carte.PointsPour, id, moi)
            local premier
            for _, pt in ipairs(ok and pts or {}) do
                if pt.genre == voulu then return pt end
                premier = premier or pt
            end
            return premier
        end
        local function Eclairer(id, oui)
            for i = 1, vue.enService do
                local b = vue.reperes[i]
                if b.point and b.point.quete == id then b:SetScale((oui and 1.6 or 1) / (vue.echelle or 1)) end
            end
        end
        local numero = 0
        for _, id in ipairs(pcT.etapes) do
            local etat = NS.parcours.EtatEtape(moi, id)
            if etat ~= "faite" then
                numero = numero + 1
                local idQ, n = id, numero
                -- Pendant le guidage, l'etape 1 est celle que vise la fleche.
                local visee = n == 1 and NS.guidage and NS.guidage.Actif()
                local q = moi and moi.quetes[id]
                local titre = (q and q.titre) or (NS.ref.Lire and NS.ref.Lire("QuestDB", id, "name")) or ("#" .. id)
                local lieu = Lieu(id)
                Ligne(n .. ". " .. titre, true, false, function()
                    -- Voir l'etape : sa zone, son repere en grand.
                    if lieu and lieu.carte then carteChoisie = lieu.carte end
                    page.Rendre()
                    Eclairer(idQ, true)
                end, function(self)
                    Eclairer(idQ, true)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(titre, 1, 0.82, 0)
                    if etat == "rendre" then
                        GameTooltip:AddLine(string.format(L.MAP_TURN_IN, lieu and lieu.quoi or "?"), 0.31, 0.82, 0.41)
                    elseif etat == "cours" then
                        GameTooltip:AddLine(L.ROUTE_STEP_TODO, 1, 1, 1)
                    else
                        GameTooltip:AddLine(string.format(L.MAP_PICK_UP, lieu and lieu.quoi or "?"), 1, 0.82, 0)
                    end
                    if lieu and lieu.carte then GameTooltip:AddLine(NomDeCarte(lieu.carte), 0.7, 0.7, 0.7) end
                    if visee then GameTooltip:AddLine(L.ROUTE_STEP_TARGET, 1, 0.82, 0) end
                    GameTooltip:AddLine(L.ROUTE_STEP_CLICK, 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end, function()
                    if NS.suivi and NS.suivi.PasserEtape then NS.suivi.PasserEtape(pcT.id, idQ) end
                    Changement()
                end, visee and { 1, 0.82, 0 } or (etat == "rendre" and { 0.31, 0.82, 0.41 } or nil))
                local l = menu.lignes[nLigne]
                l:SetScript("OnLeave", function() Eclairer(idQ, false) GameTooltip:Hide() end)
            end
        end
        if numero == 0 then Ligne(L.ROUTE_STEPS_NONE, nil, false, nil) end
        -- Etapes retirees : decochees, on les remet d'un clic sur la case.
        local retirees = {}
        for id in pairs(pcT.ignorees or {}) do
            if NS.parcours.EtatEtape(moi, id) ~= "faite" then table.insert(retirees, id) end
        end
        if #retirees > 0 then
            y = y + 6
            Titre(L.ROUTE_SKIPPED)
            table.sort(retirees)
            for _, id in ipairs(retirees) do
                local idQ = id
                local q = moi and moi.quetes[id]
                Ligne((q and q.titre) or ("#" .. id), false, false, nil, nil, function()
                    NS.parcours.RemettreEtape(cle, pcT.id, idQ)
                    if NS.suivi and NS.suivi.RafraichirTrajet then NS.suivi.RafraichirTrajet() end
                    Changement()
                end, { 0.5, 0.5, 0.5 })
            end
        end
        y = y + 10
        -- La liste n'existe que pendant le guidage : Arreter.
        Ligne(L.ROUTE_GUIDE_STOP, nil, false, function()
            if NS.guidage and NS.guidage.Basculer then NS.guidage.Basculer(false) end
            page.ModeTrajet(false)
            Changement()
        end, nil, nil, { 0.5, 0.95, 0.4 })
        Ligne(L.ROUTE_SHOW_ALL, nil, false, function()
            page.ModeTrajet(false)
            Changement()
        end)
        return
    end

    -- Quetes a rendre : une case qui ne montre plus que les receveurs.
    local cleP = NS.ClePersonnage()
    local nRendre = NS.base.NombreARendre(cleP and NS.base.PersoParCle(cleP))
    Titre(L.MAPPAGE_TURNIN, L.MAPPAGE_TURNIN_HELP)
    Ligne(string.format(L.TURNIN_ONLY, nRendre), NS.base.FiltreARendre(), false, function()
        NS.base.PoserFiltreARendre(not NS.base.FiltreARendre())
    end)
    y = y + 6

    -- Parcours traces : une case par parcours.
    local liste = NS.parcours and NS.parcours.Liste(NS.ClePersonnage()) or {}
    Titre(L.MAPPAGE_ROUTES, L.MAPPAGE_ROUTES_HELP)
    if #liste == 0 then
        Ligne(L.MAPPAGE_NO_ROUTE, nil, false, nil)
    end
    for _, pc in ipairs(liste) do
        local p = pc
        Ligne(pc.nom, pc.carte == true, false, function()
            p.carte = not p.carte
            Changement()
        end)
    end
    y = y + 6


end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------

-- parent : la zone de la page ; basDroite : son coin bas droit ;
-- menuParent, menuHaut : le menu de gauche et l'element sous lequel se poser.
function page.Rendre(parent, basDroite, menuParent, menuHaut)
    -- La fenetre reprend sa carte : fin du filigrane.
    if parent and vue and vue.filigrane then page.Filigrane(false) end
    if not vue then
        if not parent then return end
        Construire(parent, basDroite)
    end
    if not menu and menuParent then
        menu = CreateFrame("Frame", nil, menuParent)
        menu:SetPoint("TOPLEFT", menuHaut, "BOTTOMLEFT", 0, -18)
        menu:SetPoint("BOTTOMRIGHT", menuParent, "BOTTOMRIGHT", 0, 0)
    end
    vue:Show()
    -- A la creation la vue est deja visible : son OnShow ne part pas, et le
    -- calque (fleche du personnage, trajet) restait cache.
    if calque and vue:IsVisible() then calque:Show() end
    if menu then menu:Show() end
    -- Carte de donjon choisie (etape dans une instance) : sa zone dehors,
    -- sauf si on est dedans.
    if carteChoisie and carteChoisie ~= CarteDuPerso() and NS.carte.EstInstance(carteChoisie) then
        local e = NS.carte.EntreeDInstance(carteChoisie)
        carteChoisie = e and e.carte or nil
    end
    local idCarte = carteChoisie or CarteDuPerso()
    if idCarte ~= derniereCarte then zoom, decX, decY = 1, 0, 0 derniereCarte = idCarte end
    vue.idCarte = idCarte
    vue.titre:SetText(idCarte and NomDeCarte(idCarte) or L.MAPPAGE_TITLE)
    -- Le nom de la zone, le meme dans QuestCore et MapCore : encre sur le
    -- parchemin, or sur le fond sombre.
    if NS.charte.Fond() == "parchemin" then
        vue.titre:SetTextColor(0.42, 0.18, 0.02)
        vue.titre:SetShadowColor(0, 0, 0, 0)
    else
        vue.titre:SetTextColor(1, 0.82, 0)
        vue.titre:SetShadowColor(0, 0, 0, 1)
    end
    RendreMenu(idCarte)
    -- Un seul bouton, toujours au meme endroit : rien ne bouge.
    local cible
    local rendreIci, rendreAilleurs = false, nil
    if NS.base.FiltreARendre() then
        for _, pt in ipairs(NS.carte.TousLesPoints()) do
            if pt.genre == "rendre" and not pt.dispo then
                if NS.carte.Reporter(pt, idCarte) then rendreIci = true break end
                rendreAilleurs = rendreAilleurs or pt.carte
            end
        end
    end
    if carteChoisie then
        cible = { texte = L.MAPPAGE_BACK_HERE, id = nil }
    elseif rendreAilleurs and not rendreIci then
        cible = { texte = string.format(L.MAPPAGE_GO_TURNIN, NomDeCarte(rendreAilleurs)), id = rendreAilleurs }
    else
        local meilleur
        for _, pt in ipairs(NS.carte.TousLesPoints()) do
            if pt.numero and not pt.attente and pt.carte ~= idCarte and (not meilleur or pt.numero < meilleur.numero) then
                meilleur = pt
            end
        end
        if meilleur then
            cible = { texte = string.format(L.MAPPAGE_GO_STEP, meilleur.numero, NomDeCarte(meilleur.carte)), id = meilleur.carte }
        end
    end
    local cloisonne = page.EnModeTrajet()
    if vue.filtres then vue.filtres:SetShown(not cloisonne) end
    if cible and not cloisonne then
        vue.allerA:SetText(cible.texte)
        vue.allerA:SetWidth((vue.allerA.GetTextWidth and vue.allerA:GetTextWidth() or 120) + 24)
        vue.allerA:SetScript("OnClick", function()
            carteChoisie = cible.id
            queteSeule = nil
            page.Rendre()
        end)
        vue.allerA:Show()
    else
        vue.allerA:Hide()
    end

    local largeur, hauteur
    if idCarte then largeur, hauteur = PoserFond(idCarte) end
    vue.compte = {}
    if not largeur then
        Cacher(vue.toile.tuiles) Cacher(vue.toile.revelees) Cacher(vue.toile.explorees)
        for i = 1, vue.enService do vue.reperes[i]:Hide() end
        vue.enService = 0
        if calque then calque.fleche:Hide() for _, t in ipairs(calque.points or {}) do t:Hide() end end
        vue.vide:SetText(L.MAPPAGE_NONE)
        vue.vide:Show()
        vue.largeur = nil
        return
    end
    vue.vide:Hide()
    vue.largeur, vue.hauteur = largeur, hauteur
    vue.toile:SetSize(largeur, hauteur)
    vue.compte.revelees = PoserRevelees(idCarte)
    vue.compte.explorees = PoserExplorees(idCarte)
    PoserReperes(idCarte)
    pcall(PoserEntree, idCarte)
    pcall(PoserQuetePointee, idCarte)
    Disposer()
end

function page.Cacher()
    -- En filigrane, la carte reste a l'ecran quoi que montre la fenetre.
    if vue and vue.filigrane then
        if menu then menu:Hide() end
        return
    end
    if vue then vue:Hide() end
    if menu then menu:Hide() end
end

-- Rapport de la page, ecrit dans les donnees enregistrees (/qc carte).
function page.Constat()
    local d = QuestCoreDB
    if type(d) ~= "table" then return end
    local r = { quand = NS.Appeler(date, "%d/%m %H:%M:%S"), construite = vue ~= nil }
    if vue then
        r.visible = vue:IsVisible()
        r.carte = vue.idCarte
        r.taille = vue.largeur and (vue.largeur .. "x" .. vue.hauteur) or nil
        r.zoom = zoom
        r.reperes = vue.enService
        r.revelees = vue.compte and vue.compte.revelees
        r.explorees = vue.compte and vue.compte.explorees
        local traits = 0
        for _, t in ipairs(calque and calque.points or {}) do if t:IsShown() then traits = traits + 1 end end
        r.traits = traits
        r.ligneDispo = calque and calque.CreateLine ~= nil
        r.fleche = calque and calque.fleche:IsShown()
    end
    d.constatPage = r
end

-- ---------------------------------------------------------------------------
-- Filigrane : la carte seule, tres pale, au milieu de l'ecran et derriere
-- l'interface, sans souris : on voit le trajet en pointilles et sa position
-- en jouant. Lancee depuis la fleche de guidage.
-- ---------------------------------------------------------------------------

-- La carte a peine visible ; le trajet et la fleche du personnage, eux,
-- restent bien visibles (calque a part).
local ALPHA_FILIGRANE = 0.2
local ALPHA_TRAJET = 0.95
local avantFiligrane
local ecouteFiligrane

function page.EnFiligrane() return vue ~= nil and vue.filigrane == true end

function page.Filigrane(oui)
    if oui and not vue then
        -- La carte n'a jamais ete construite : on passe par la fenetre.
        if NS.fenetre and NS.fenetre.OuvrirCarte then pcall(NS.fenetre.OuvrirCarte) end
    end
    if not vue then
        -- Fenetre pas encore prete : on reessaie un instant plus tard.
        local plusTard = Lecture("C_Timer.After")
        if oui ~= false and plusTard and not page.reessai then
            page.reessai = true
            plusTard(0.2, function() page.reessai = nil if vue then page.Filigrane(true) end end)
        end
        return
    end
    if oui == nil then oui = not vue.filigrane end
    if oui == (vue.filigrane == true) then return end
    local caches = { vue.titre, vue.filtres, vue.allerA, vue.plus, vue.moins, vue.aide, vue.legende }
    if oui then
        avantFiligrane = { strata = vue:GetFrameStrata() }
        local fenetre = _G.QuestCoreFenetre
        if fenetre and fenetre:IsShown() then fenetre:Hide() end
        vue.filigrane = true
        vue:SetParent(UIParent)
        vue:ClearAllPoints()
        vue:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        vue:SetSize(math.min(900, (UIParent:GetWidth() or 1000) * 0.6), math.min(620, (UIParent:GetHeight() or 700) * 0.6))
        vue:SetFrameStrata("BACKGROUND")
        vue:SetAlpha(ALPHA_FILIGRANE)
        vue.clip:EnableMouse(false)
        vue.clip:EnableMouseWheel(false)
        for _, f in pairs(caches) do if f then f:SetAlpha(0) end end
        vue:Show()
        if calque then calque:SetAlpha(ALPHA_TRAJET) calque:Show() end
        -- La carte suit le personnage d'une zone a l'autre.
        if not ecouteFiligrane then
            ecouteFiligrane = CreateFrame("Frame")
            ecouteFiligrane:SetScript("OnEvent", function()
                if vue and vue.filigrane then pcall(page.Rendre) end
            end)
        end
        pcall(ecouteFiligrane.RegisterEvent, ecouteFiligrane, "ZONE_CHANGED_NEW_AREA")
        pcall(page.Rendre)
    else
        vue.filigrane = nil
        if ecouteFiligrane then pcall(ecouteFiligrane.UnregisterEvent, ecouteFiligrane, "ZONE_CHANGED_NEW_AREA") end
        local a = vue.ancres
        vue:SetParent(a.parent)
        vue:ClearAllPoints()
        vue:SetPoint("TOPLEFT", a.parent, "TOPLEFT", 0, 0)
        vue:SetPoint("BOTTOMRIGHT", a.basDroite, "BOTTOMRIGHT", 0, 0)
        vue:SetFrameStrata(avantFiligrane and avantFiligrane.strata or "MEDIUM")
        vue:SetAlpha(1)
        vue.clip:EnableMouse(true)
        vue.clip:EnableMouseWheel(true)
        for _, f in pairs(caches) do if f then f:SetAlpha(1) end end
        if calque then calque:SetAlpha(1) end
        local parent = vue:GetParent()
        if not (parent and parent:IsVisible()) then vue:Hide() end
        avantFiligrane = nil
    end
end
