local _, NS = ...

-- Boite aux lettres : ce que ce personnage a dans ses sacs et qui manque a
-- une quete d'un autre personnage du compte (meme camp). Un bouton Preparer
-- remplit l'envoi (destinataire, sujet, pieces jointes). L'envoi lui-meme
-- reste toujours au joueur : QuestCore n'envoie jamais rien.

NS.courrier = {}
local courrier = NS.courrier
local L = NS.L

local LARGEUR = 300
local panneau
local enCours = false

local function Lire(nom) return NS.Lecture(nom) end
local function Conteneur(nom) return Lire("C_Container." .. nom) or Lire(nom) end

-- Objet dans une case des sacs : id, nombre, verrouille.
local function ContenuDe(sac, case)
    local objet = NS.Appeler(Conteneur("GetContainerItemID"), sac, case)
    if not objet then return nil end
    local info = NS.Appeler(Conteneur("GetContainerItemInfo"), sac, case)
    local nombre, verrou = 1, false
    if type(info) == "table" then
        nombre = tonumber(info.stackCount) or 1
        verrou = info.isLocked and true or false
    end
    return objet, nombre, verrou
end

local function Sacs()
    local dernier = tonumber(_G.NUM_BAG_SLOTS) or 4
    local liste = {}
    for sac = 0, dernier do table.insert(liste, sac) end
    return liste
end

local function DansLesSacs(objet)
    local total = 0
    for _, sac in ipairs(Sacs()) do
        for case = 1, tonumber(NS.Appeler(Conteneur("GetContainerNumSlots"), sac)) or 0 do
            local present, nombre = ContenuDe(sac, case)
            if present == objet then total = total + nombre end
        end
    end
    return total
end

-- Envois possibles maintenant : objet dans mes sacs, manquant a la quete
-- d'un autre personnage. Regroupes par destinataire.
function courrier.Envois()
    local moi = NS.base.PersoParCle(NS.ClePersonnage())
    if not moi then return {} end
    local parDestinataire, liste = {}, {}
    for _, b in ipairs(NS.ref.CePeutFournir(moi)) do
        local dispo = DansLesSacs(b.objet)
        if dispo > 0 then
            local d = parDestinataire[b.cle]
            if not d then
                d = { cle = b.cle, nom = NS.NomCourt(b.cle), lignes = {} }
                parDestinataire[b.cle] = d
                table.insert(liste, d)
            end
            table.insert(d.lignes, { objet = b.objet, quantite = math.min(dispo, b.manque), quete = b.quete,
                titre = NS.ref.NomDeQuete(b.quete, b.perso) })
        end
    end
    return liste
end

-- Remplit l'envoi : onglet Envoyer, destinataire, sujet, pieces jointes une a
-- une (chaque objet deplace verrouille sa case un instant).
local function Preparer(envoi)
    if enCours then return end
    if InCombatLockdown and InCombatLockdown() then NS.Dire(L.MAIL_COMBAT) return end
    local joindre = Lire("ClickSendMailItemButton")
    local pieceJointe = Lire("GetSendMailItem")
    if not joindre then NS.Dire(L.MAIL_NOT_POSSIBLE) return end
    if _G.MailFrameTab2 and _G.MailFrameTab2.Click then pcall(_G.MailFrameTab2.Click, _G.MailFrameTab2) end
    if _G.SendMailNameEditBox then pcall(_G.SendMailNameEditBox.SetText, _G.SendMailNameEditBox, envoi.nom) end
    if _G.SendMailSubjectEditBox then
        pcall(_G.SendMailSubjectEditBox.SetText, _G.SendMailSubjectEditBox,
            string.format(L.MAIL_SUBJECT, envoi.lignes[1] and envoi.lignes[1].titre or ""))
    end
    local maximum = tonumber(_G.ATTACHMENTS_MAX_SEND) or 12
    local function CaseLibre()
        for i = 1, maximum do
            if not pieceJointe or not NS.Appeler(pieceJointe, i) then return i end
        end
        return nil
    end
    -- Etapes : une piece jointe par etape.
    local etapes = {}
    for _, ligne in ipairs(envoi.lignes) do
        local reste = ligne.quantite
        for _ = 1, 12 do
            table.insert(etapes, function()
                if reste <= 0 then return true end
                local case = CaseLibre()
                if not case then NS.Dire(L.MAIL_FULL) return false end
                for _, sac in ipairs(Sacs()) do
                    for c = 1, tonumber(NS.Appeler(Conteneur("GetContainerNumSlots"), sac)) or 0 do
                        local present, nombre, verrou = ContenuDe(sac, c)
                        if present == ligne.objet and not verrou then
                            local part = math.min(nombre, reste)
                            if part < nombre then
                                NS.Appeler(Conteneur("SplitContainerItem"), sac, c, part)
                            else
                                NS.Appeler(Conteneur("PickupContainerItem"), sac, c)
                            end
                            NS.Appeler(joindre, case)
                            reste = reste - part
                            return true
                        end
                    end
                end
                reste = 0
                return true
            end)
        end
    end
    enCours = true
    local rang = 0
    local plusTard = Lire("C_Timer.After")
    local function Suivante()
        rang = rang + 1
        local etape = etapes[rang]
        local ok, continuer = true, true
        if etape then ok, continuer = pcall(etape) end
        if not etape or not ok or continuer == false then
            enCours = false
            local vider = Lire("ClearCursor")
            if vider then NS.Appeler(vider) end
            if not ok then NS.base.NoterIncident("courrier", continuer) end
            NS.Dire(string.format(L.MAIL_PREPARED, envoi.nom))
            return
        end
        if plusTard then plusTard(0.25, Suivante) else Suivante() end
    end
    Suivante()
end

-- ---------------------------------------------------------------------------
-- Panneau, a droite de la boite aux lettres
-- ---------------------------------------------------------------------------

local function Construire()
    panneau = NS.charte.Fenetre("QuestCoreCourrier", LARGEUR, 120,
        { portrait = false, strate = "HIGH", sansPied = true, deplacable = false })
    if panneau.titre then panneau.titre:SetText(L.MAIL_TITLE) end
    panneau.lignes = {}
    panneau.fermer:SetScript("OnClick", function() panneau:Hide() end)
    panneau:Hide()
end

local function Ligne(rang)
    local l = panneau.lignes[rang]
    if l then return l end
    l = CreateFrame("Frame", nil, panneau)
    l:SetHeight(20)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.icone:SetSize(16, 16)
    l.icone:SetPoint("LEFT", l, "LEFT", 0, 0)
    l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texte:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
    l.texte:SetJustifyH("LEFT")
    l.texte:SetWordWrap(false)
    l.bouton = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
    l.bouton:SetHeight(20)
    l.bouton:SetPoint("RIGHT", l, "RIGHT", 0, 0)
    l.texte:SetPoint("RIGHT", l.bouton, "LEFT", -6, 0)
    panneau.lignes[rang] = l
    return l
end

function courrier.Actualiser()
    local boite = _G.MailFrame
    if not boite or not boite:IsShown() then
        if panneau then panneau:Hide() end
        return
    end
    local envois = courrier.Envois()
    if #envois == 0 then
        if panneau then panneau:Hide() end
        return
    end
    if not panneau then Construire() end
    for _, l in ipairs(panneau.lignes) do l:Hide() end
    local y, rang = 0, 0
    for _, envoi in ipairs(envois) do
        -- Une ligne titre par destinataire, avec son bouton.
        rang = rang + 1
        local t = Ligne(rang)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", panneau.zone, "TOPLEFT", 0, -y)
        t:SetPoint("RIGHT", panneau.zone, "RIGHT", 0, 0)
        t.icone:Hide()
        t.texte:ClearAllPoints()
        t.texte:SetPoint("LEFT", t, "LEFT", 0, 0)
        t.texte:SetPoint("RIGHT", t.bouton, "LEFT", -6, 0)
        t.texte:SetFontObject("GameFontNormal")
        t.texte:SetText(string.format(L.MAIL_FOR, envoi.nom))
        t.bouton:SetText(L.MAIL_PREPARE)
        t.bouton:SetWidth((t.bouton.GetTextWidth and t.bouton:GetTextWidth() or 60) + 24)
        local e = envoi
        t.bouton:SetScript("OnClick", function() pcall(Preparer, e) end)
        t.bouton:Show()
        t:Show()
        y = y + 24
        for _, ligne in ipairs(envoi.lignes) do
            rang = rang + 1
            local l = Ligne(rang)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", panneau.zone, "TOPLEFT", 8, -y)
            l:SetPoint("RIGHT", panneau.zone, "RIGHT", 0, 0)
            l.icone:SetTexture(NS.ref.IconeDObjet(ligne.objet))
            l.icone:Show()
            l.texte:ClearAllPoints()
            l.texte:SetPoint("LEFT", l.icone, "RIGHT", 6, 0)
            l.texte:SetPoint("RIGHT", l, "RIGHT", 0, 0)
            l.texte:SetFontObject("GameFontHighlightSmall")
            l.texte:SetText(string.format("%s x%d  |cff8c8c8c(%s)|r", NS.ref.NomDObjet(ligne.objet), ligne.quantite,
                ligne.titre or ""))
            l.bouton:Hide()
            l:Show()
            y = y + 20
        end
        y = y + 6
    end
    panneau:SetHeight(y + 24 + 2 * NS.charte.MARGE + 8)
    panneau:ClearAllPoints()
    -- Sous l'assistant de CraftCore s'il est la, sinon a droite de la boite.
    local assistant = _G.CraftCoreAssistant
    if assistant and assistant:IsShown() then
        panneau:SetPoint("TOPLEFT", assistant, "BOTTOMLEFT", 0, -6)
    else
        panneau:SetPoint("TOPLEFT", boite, "TOPRIGHT", 8, 0)
    end
    panneau:Show()
end

function courrier.Installer()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "BAG_UPDATE_DELAYED", "MAIL_SEND_SUCCESS" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, evenement)
        if evenement == "MAIL_CLOSED" then
            if panneau then panneau:Hide() end
            return
        end
        local plusTard = Lire("C_Timer.After")
        local function Faire()
            local ok, souci = pcall(courrier.Actualiser)
            if not ok then NS.base.NoterIncident("courrier", souci) end
        end
        if plusTard then plusTard(0.3, Faire) else Faire() end
    end)
end
