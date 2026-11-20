local _, NS = ...

-- Langue : l'anglais pour toute cle non traduite, celle du jeu au
-- chargement, puis celle choisie dans les reglages generaux de la suite des
-- que les reglages sont charges. NS.L reste la meme table : les textes
-- changent en place.
local L = {}
NS.L = L
local CORRESPONDANCE = { esMX = "esES", zhTW = "zhCN", enGB = "enUS" }
local function CodeLangue(code)
    code = code or (GetLocale and GetLocale()) or "enUS"
    return CORRESPONDANCE[code] or code
end
function NS.AppliquerLangue(code)
    code = CodeLangue(code)
    local base, choisie = NS.locales.enUS, NS.locales[code]
    for cle in pairs(L) do if base[cle] == nil then L[cle] = nil end end
    for cle, texte in pairs(base) do L[cle] = texte end
    if choisie and choisie ~= base then for cle, texte in pairs(choisie) do L[cle] = texte end end
    NS.langue = choisie and code or "enUS"
end
NS.AppliquerLangue()
do
    local veille = CreateFrame("Frame")
    veille:RegisterEvent("ADDON_LOADED")
    veille:SetScript("OnEvent", function(self, _, qui)
        if qui ~= "CraftCore" then return end
        self:UnregisterEvent("ADDON_LOADED")
        local choix = type(CoreSuiteDB) == "table" and CoreSuiteDB.langue or nil
        if choix and CodeLangue(choix) ~= NS.langue then NS.AppliquerLangue(choix) end
    end)
end

local base = NS.base
local inventaire = NS.inventaire

local ecran = NS.ecran
local releveEnAttente = false

-- Definie plus bas, appelee des le premier releve differe. Declaree ici pour
-- rester propre a l'addon au lieu de devenir une globale du jeu.
local PrevenirSiUtile

-- Etat de la banque, partage avec l'ecran qui en a besoin pour actualiser.
local function BanqueOuverte(valeur)
    if valeur ~= nil then ecran.banqueOuverte = valeur end
    return ecran.banqueOuverte == true
end

-- Les avis de changement de sac arrivent en rafale. On regroupe, pour ne pas
-- relire six conteneurs a chaque objet ramasse.
-- Apres chaque releve : les infobulles et l'assistant de banque et de
-- courrier se recalculent sur les nouveaux stocks.
local function ApresReleve()
    if NS.infobulles then NS.infobulles.Invalider() end
    if NS.courrier then NS.courrier.Actualiser() end
    -- Le suivi (Mes fabrications, pourcentages) suit les sacs a chaque
    -- releve : achat chez un marchand, banque, courrier, butin.
    if NS.suivi and NS.suivi.Dessiner then
        local ok, souci = pcall(NS.suivi.Dessiner)
        if not ok and NS.base.NoterIncident then NS.base.NoterIncident("suivi apres releve", souci) end
    end
end

local function ReleverBientot()
    if releveEnAttente then return end
    releveEnAttente = true
    local plusTard = NS.Lecture("C_Timer.After")
    if not plusTard then
        releveEnAttente = false
        PrevenirSiUtile(inventaire.Relever(BanqueOuverte()))
        if NS.caisses and NS.caisses.MarquerARelever then NS.caisses.MarquerARelever() end
        ecran.Actualiser()
        ApresReleve()
        return
    end
    NS.Appeler(plusTard, 1, function()
        releveEnAttente = false
        local resultat = inventaire.Relever(BanqueOuverte())
        PrevenirSiUtile(resultat)
        if NS.caisses and NS.caisses.MarquerARelever then NS.caisses.MarquerARelever() end
        ecran.Actualiser()
        ApresReleve()
    end)
end

-- Les avis de liste de metier arrivent eux aussi en rafale a l'ouverture.
local recettesEnAttente = false
local function ReleverRecettesBientot()
    if recettesEnAttente then return end
    recettesEnAttente = true
    local plusTard = NS.Lecture("C_Timer.After")
    local faire = function()
        recettesEnAttente = false
        if NS.recettes and NS.recettes.Relever and NS.recettes.Relever("métier ouvert") then
            ecran.Actualiser()
        end
    end
    if not plusTard then
        faire()
        return
    end
    NS.Appeler(plusTard, 1, faire)
end

-- Previent quand un objet ramasse manque a un projet en cours. Seulement pour
-- les objets attendus, et seulement tant que le projet n'est pas couvert :
-- prevenir pour tout serait du bruit.
local dejaDit = {}
PrevenirSiUtile = function(resultat)
    if type(resultat) ~= "table" or type(resultat.arrives) ~= "table" then return end
    -- Ce qui sort de la banque ou du courrier n'est pas du butin.
    if BanqueOuverte() or ecran.courrierOuvert then return end
    -- Le suivi de recolte remplace le message dans la discussion.
    if NS.suivi and NS.suivi.ObjetsArrives then
        local ok, souci = pcall(NS.suivi.ObjetsArrives, resultat.arrives)
        if not ok then NS.base.NoterIncident("suivi de recolte", souci) end
        return
    end
    if not NS.projets or not NS.projets.QuiAttendent then return end

    for objet in pairs(resultat.arrives) do
        local attendus = NS.projets.QuiAttendent(objet)
        if #attendus > 0 then
            local premier = attendus[1]
            local cle = tostring(objet) .. ":" .. tostring(premier.projet.id)
            -- Une fois par objet et par projet, pas a chaque ramassage.
            if not dejaDit[cle] then
                dejaDit[cle] = true
                NS.Dire(string.format(L.LOOT_USEFUL,
                    NS.inventaire.NomDObjet(objet),
                    NS.projets.NomDe(premier.projet),
                    math.floor(premier.couverture * 100 + 0.5)))
            end
        end
    end
end

-- Les noms d'objets arrivent en rafale apres que le client les a charges. On
-- regroupe, puis on redessine une fois : sans cela l'ecran garde des
-- identifiants a la place des noms.
local nomsEnAttente = false
local function RedessinerBientot()
    if nomsEnAttente then return end
    nomsEnAttente = true
    local plusTard = NS.Lecture("C_Timer.After")
    local faire = function()
        nomsEnAttente = false
        ecran.Actualiser()
    end
    if not plusTard then faire() return end
    NS.Appeler(plusTard, 1, faire)
end

-- ---------------------------------------------------------------------------
-- Commandes assignables, utilisables au clavier comme a la manette
-- ---------------------------------------------------------------------------

-- Le raccourci ouvre la suite la ou on l'avait laissee (dernier add-on,
-- derniere page), et la referme.
function CraftCore_Basculer()
    local S = NS.suite or _G.CoreSuite
    if S and S.BasculerDernier then
        local ok = pcall(S.BasculerDernier, "CraftCore")
        if ok then return end
    end
    ecran.Basculer()
end

function CraftCore_PageSuivante()
    ecran.PageVoisine(1)
end

function CraftCore_PagePrecedente()
    ecran.PageVoisine(-1)
end

function CraftCore_MetierSuivant()
    ecran.MetierVoisin(1)
end

function CraftCore_MetierPrecedent()
    ecran.MetierVoisin(-1)
end

-- ---------------------------------------------------------------------------
-- Branchement
-- ---------------------------------------------------------------------------

local cadre = CreateFrame("Frame")

local function Brancher(nom)
    return pcall(cadre.RegisterEvent, cadre, nom)
end

local function Demarrer()
    NS.ResoudreLectures()

    local manquantes = NS.LecturesManquantes()
    if #manquantes > 0 then
        -- Mieux vaut se taire que montrer des stocks faux.
        NS.Dire("lectures indisponibles sur ce client : " .. table.concat(manquantes, ", ") .. ".")
        return
    end

    local premiereFois = base.Preparer()
    -- On regarde toujours le personnage qui joue en arrivant. Garder le choix
    -- d'une session precedente laissait voir les metiers d'un autre.
    if base.PoserPersonnageAffiche then base.PoserPersonnageAffiche(nil) end
    -- La fiche du personnage existe des la connexion : sans cela, un
    -- personnage dont le releve echoue resterait invisible dans l'addon.
    local fiche = base.Personnage()
    if fiche then
        fiche.vuLe = NS.Horodatage()
        local classe, jeton = NS.Appeler(NS.Lecture("UnitClass"), "player")
        if classe then fiche.classe = classe end
        -- Le jeton, en plus du nom traduit : c'est lui que la table d'icones
        -- de classe du jeu attend.
        if type(jeton) == "string" and jeton ~= "" then fiche.jetonClasse = jeton end
        local niveau = NS.Appeler(NS.Lecture("UnitLevel"), "player")
        if niveau then fiche.niveau = niveau end
        -- La faction compte : on n'echange rien avec l'autre camp, donc ses
        -- stocks ne doivent pas entrer dans un total.
        local faction = NS.Appeler(NS.Lecture("UnitFactionGroup"), "player")
        if type(faction) == "string" and faction ~= "" then fiche.faction = faction end
    end
    if NS.ConstruireBoutonDeMinicarte then NS.ConstruireBoutonDeMinicarte() end
    -- Suite Core : un seul bouton de minicarte pour CraftCore, QuestCore, MapCore.
    if NS.suite then
        pcall(NS.suite.Inscrire, "CraftCore", {
            ouvrir = function() NS.ecran.Montrer() end,
            fenetre = function() return NS.ecran.Fenetre() end,
            boutonMinicarte = _G.CraftCoreMinimapButton,
        })
    end
    if NS.recettes and NS.recettes.Sonder then NS.recettes.Sonder() end
    -- Les recettes deja enregistrees suffisent a apprendre quelle categorie
    -- appartient a quel metier : inutile d'attendre une fenetre de metier.
    if NS.recettes and NS.recettes.ApprendreLesCategories then
        NS.recettes.ApprendreLesCategories()
    end
    -- Infobulles des objets, partout dans le jeu.
    if NS.infobulles then pcall(NS.infobulles.Installer) end
    -- Niveau de chaque metier, lu sans ouvrir les metiers.
    if NS.recettes and NS.recettes.ReleverNiveaux then pcall(NS.recettes.ReleverNiveaux) end
    -- Ce que le client offre pour l'interface manette, releve une fois.
    if NS.manette and NS.manette.Sonder then pcall(NS.manette.Sonder) end
    local resultat = inventaire.Relever(BanqueOuverte())
    inventaire.ReleverEquipement()

    if premiereFois then
        NS.Dire(L.MSG_FIRST_RUN)
        NS.Dire(L.WELCOME_1)
        NS.Dire(L.WELCOME_2)
        NS.Dire(L.WELCOME_3)
        NS.Dire(L.WELCOME_4)
    end
    if resultat then
        NS.Dire(string.format(L.MSG_READY, resultat.objets, resultat.conteneurs))
    end

    -- Premiere connexion avec cette version : la fenetre s'ouvre d'elle-meme
    -- sur l'accueil, une seule fois. La meme version ne la rouvre plus.
    if NS.aide and NS.aide.AccueilAMontrer() then
        local plusTard = NS.Lecture("C_Timer.After")
        local ouvrir = function()
            if NS.aide.AccueilAMontrer() then ecran.Montrer() end
        end
        if plusTard then NS.Appeler(plusTard, 3, ouvrir) else ouvrir() end
    end
end

cadre:SetScript("OnEvent", function(_, evenement, argument1)
    if evenement == "PLAYER_LOGIN" then
        local ok, souci = pcall(Demarrer)
        if not ok then
            NS.Dire("démarrage incomplet : " .. tostring(souci))
        end
        -- Suivi de recolte affiche en permanence : il se montre tout de suite.
        local plusTard = NS.Lecture("C_Timer.After")
        local function SuiviPermanent() if NS.suivi and NS.suivi.Demarrer then pcall(NS.suivi.Demarrer) end end
        if plusTard then NS.Appeler(plusTard, 2, SuiviPermanent) else SuiviPermanent() end
    elseif evenement == "BANKFRAME_OPENED" then
        BanqueOuverte(true)
        local resultat = inventaire.Relever(true)
        if resultat then
            if resultat.nouveauxDeBanque > 0 then
                NS.Dire(string.format(L.MSG_BANK_FOUND, resultat.nouveauxDeBanque))
            else
                NS.Dire(L.MSG_NO_BANK)
            end
            ecran.Actualiser()
        end
        if NS.infobulles then NS.infobulles.Invalider() end
        if NS.courrier then NS.courrier.Ouvert("banque") end
    elseif evenement == "BANKFRAME_CLOSED" then
        BanqueOuverte(false)
        if NS.courrier then NS.courrier.Ferme("banque") end
    elseif evenement == "MAIL_INBOX_UPDATE" then
        -- La boite ouverte est relevee (le jeu l'a remplie) : ses objets
        -- comptent dans les stocks.
        if ecran.courrierOuvert and inventaire.ReleverBoite then
            pcall(inventaire.ReleverBoite)
            RedessinerBientot()
        end
    elseif evenement == "MAIL_SHOW" then
        ecran.courrierOuvert = true
        if NS.courrier then NS.courrier.Ouvert("courrier") end
    elseif evenement == "MAIL_CLOSED" then
        ecran.courrierOuvert = nil
        if NS.courrier then NS.courrier.Ferme("courrier") end
    elseif evenement == "BAG_UPDATE_DELAYED" then
        ReleverBientot()
        if NS.commandes then pcall(NS.commandes.VerifierReception) end
    elseif evenement == "TRADE_SKILL_SHOW" or evenement == "TRADE_SKILL_LIST_UPDATE"
        or evenement == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        ReleverRecettesBientot()
    elseif evenement == "NEW_RECIPE_LEARNED" or evenement == "SKILL_LINES_CHANGED" then
        if evenement == "SKILL_LINES_CHANGED" and NS.recettes.ReleverNiveaux then
            pcall(NS.recettes.ReleverNiveaux)
            -- Un point de metier gagne : rangs vises a jour tout de suite.
            if NS.suivi and NS.suivi.Dessiner then pcall(NS.suivi.Dessiner) end
        end
        -- Une recette tout juste apprise est notee aussitot, sans attendre
        -- que la fenetre du metier soit ouverte.
        if evenement == "NEW_RECIPE_LEARNED" and NS.recettes.NoterApprise then
            pcall(NS.recettes.NoterApprise, argument1)
            ecran.Actualiser()
        end
        ReleverRecettesBientot()
    elseif evenement == "PLAYER_EQUIPMENT_CHANGED" then
        inventaire.ReleverEquipement()
        ecran.Actualiser()
    elseif evenement == "GET_ITEM_INFO_RECEIVED" then
        -- Un objet vient d'arriver : les infobulles deviennent lisibles, donc
        -- le tour des caisses peut enfin aboutir.
        if NS.caisses and NS.caisses.MarquerARelever then NS.caisses.MarquerARelever() end
        RedessinerBientot()
    end
end)

Brancher("PLAYER_LOGIN")
Brancher("BAG_UPDATE_DELAYED")
Brancher("BANKFRAME_OPENED")
Brancher("BANKFRAME_CLOSED")
Brancher("TRADE_SKILL_SHOW")
Brancher("TRADE_SKILL_LIST_UPDATE")
Brancher("TRADE_SKILL_DATA_SOURCE_CHANGED")
Brancher("NEW_RECIPE_LEARNED")
Brancher("SKILL_LINES_CHANGED")
Brancher("GET_ITEM_INFO_RECEIVED")
Brancher("PLAYER_EQUIPMENT_CHANGED")
Brancher("MAIL_SHOW")
Brancher("MAIL_CLOSED")
Brancher("MAIL_INBOX_UPDATE")

SLASH_CRAFTCORE1 = "/craftcore"
SLASH_CRAFTCORE2 = "/cc"
SlashCmdList["CRAFTCORE"] = function(argument)
    argument = string.lower(argument or "")
    if argument == "" then
        ecran.Basculer()
        return
    end
    if argument == "stocks" then
        ecran.Montrer("stocks")
        return
    end
    if argument == "drapeau" or argument == "flag" then
        if NS.marchands then NS.marchands.ChoisirDrapeau() end
        return
    end
    if argument == "aide" or argument == "help" then
        ecran.Montrer()
        if NS.aide then NS.aide.Montrer("accueil") end
        return
    end
    if argument == "suivi" or argument == "recolte" then
        if NS.suivi then NS.suivi.Montrer() end
        return
    end
    if argument == "caisses" then
        if NS.caisses and NS.caisses.MarquerARelever then NS.caisses.MarquerARelever() end
        local trouvees = NS.caisses and NS.caisses.Relever(true) or {}
        NS.Dire(string.format(L.SEARCH_DONE, #trouvees, "caisses"))
        return
    end
    if argument == "sources" then
        local combien = NS.recettes.SonderDesNonApprises()
        NS.Dire(string.format(L.SEARCH_DONE, combien, "sources"))
        return
    end
    local mot = argument:match("^trouver%s+(.+)$")
    if mot then
        local combien = NS.objets.Chercher(mot)
        NS.Dire(string.format(L.SEARCH_DONE, combien, mot))
        return
    end
    if argument == "scan" then
        local resultat = inventaire.Relever(BanqueOuverte())
        if resultat then
            NS.Dire(string.format(L.MSG_SCANNED, resultat.objets, resultat.conteneurs))
        end
        ecran.Actualiser()
        return
    end
    NS.Dire(L.MSG_UNKNOWN_COMMAND)
end

-- Entree dans le compartiment d'extensions du jeu, comme le fait le journal de
-- donjon installe sur ce client.
function CraftCore_OnAddonCompartmentClick()
    ecran.Basculer()
end
