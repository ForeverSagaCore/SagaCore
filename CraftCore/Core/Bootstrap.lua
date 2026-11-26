local ADDON_NAME, NS = ...

-- Espace de noms partage. Chaque fichier recoit la meme table d'addon.
if type(NS) ~= "table" then
    NS = _G.CraftCore_NS or {}
end
_G.CraftCore_NS = NS

NS.ADDON_NAME = ADDON_NAME
NS.VERSION = "0.34.0"
-- Le de du jeu (jets de butin) : devant un rang qui ne s'atteint qu'avec de la
-- chance (recettes jaunes), partout ou un rang vise s'affiche.
NS.ICONE_CHANCE = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:14:14:0:-1|t "

-- Le client ne parle que le langage moderne : releve du 13 novembre 2026 sur
-- Forever 1.60.1 build 70938, palier 16001. Les anciennes lectures globales
-- (sacs, objets, metiers) sont toutes absentes. On passe donc par les espaces
-- modernes, mais toujours par ce point unique : si le client evolue, un seul
-- endroit change.
--
-- Patron repris des extensions deja installees sur ce client : repli explicite
-- puis appel sous filet, jamais d'appel direct.

-- Resout un chemin pointe depuis l'environnement global, sans jamais lever.
local function Resoudre(chemin)
    local cible = _G
    for partie in string.gmatch(chemin, "[^%.]+") do
        if type(cible) ~= "table" then return nil end
        cible = cible[partie]
        if cible == nil then return nil end
    end
    return cible
end
NS.Resoudre = Resoudre

-- Renvoie la premiere lecture disponible parmi les chemins donnes, ou nil.
function NS.Lecture(...)
    for i = 1, select("#", ...) do
        local fn = Resoudre((select(i, ...)))
        if type(fn) == "function" then return fn end
    end
    return nil
end

-- Appelle une lecture sous filet. Renvoie nil si elle manque ou si elle leve.
function NS.Appeler(fn, ...)
    if type(fn) ~= "function" then return nil end
    local resultats = { pcall(fn, ...) }
    if not resultats[1] then return nil end
    return resultats[2], resultats[3], resultats[4], resultats[5]
end

-- Lectures dont l'addon depend, resolues une fois pour toutes.
NS.jeu = {}

function NS.ResoudreLectures()
    local j = NS.jeu
    j.nombreEmplacements = NS.Lecture("C_Container.GetContainerNumSlots")
    j.objetDeLEmplacement = NS.Lecture("C_Container.GetContainerItemID")
    j.infoDeLEmplacement = NS.Lecture("C_Container.GetContainerItemInfo")
    j.nomDuConteneur = NS.Lecture("C_Container.GetBagName")
    j.infoObjet = NS.Lecture("C_Item.GetItemInfo")
    j.infoObjetImmediate = NS.Lecture("C_Item.GetItemInfoInstant")
    j.iconeObjet = NS.Lecture("C_Item.GetItemIconByID")
    -- Metiers. Le releve du 13 novembre a confirme ces lectures presentes, et
    -- a confirme absentes la lecture d'info de ligne de metier et tout
    -- l'ancien systeme. On ne les resout donc pas.
    j.toutesLesLignesDeMetier = NS.Lecture("C_TradeSkillUI.GetAllProfessionTradeSkillLines")
    j.recettesFiltrees = NS.Lecture("C_TradeSkillUI.GetFilteredRecipeIDs")
    j.toutesLesRecettes = NS.Lecture("C_TradeSkillUI.GetAllRecipeIDs")
    j.infoRecette = NS.Lecture("C_TradeSkillUI.GetRecipeInfo")
    j.planRecette = NS.Lecture("C_TradeSkillUI.GetRecipeSchematic")
    j.infoMetierParLigne = NS.Lecture("C_TradeSkillUI.GetProfessionInfoBySkillLineID")
    j.infoMetierDeBase = NS.Lecture("C_TradeSkillUI.GetBaseProfessionInfo")
    j.lienRecette = NS.Lecture("C_TradeSkillUI.GetRecipeItemLink")
    j.sourceRecette = NS.Lecture("C_TradeSkillUI.GetRecipeSourceText")
    j.fabriquer = NS.Lecture("C_TradeSkillUI.CraftRecipe")
    j.ouvrirMetier = NS.Lecture("C_TradeSkillUI.OpenTradeSkill")
    j.fermerMetier = NS.Lecture("C_TradeSkillUI.CloseTradeSkill")
    j.categoriesDuMetier = NS.Lecture("C_TradeSkillUI.GetCategories")
    j.infoCategorie = NS.Lecture("C_TradeSkillUI.GetCategoryInfo")

    -- Equipement porte. Chaque lecture est optionnelle : ce que le client ne
    -- rend pas n'est pas affiche, et surtout pas invente.
    j.objetEquipe = NS.Lecture("GetInventoryItemID")
    j.lienObjetEquipe = NS.Lecture("GetInventoryItemLink")
    j.statsObjet = NS.Lecture("C_Item.GetItemStats", "GetItemStats")

    j.nomDuPersonnage = NS.Lecture("UnitName")
    j.nomDuRoyaume = NS.Lecture("SagaCoreRoyaume", "GetRealmName")
    return j
end

-- Ce dont l'addon ne peut pas se passer. Sans ca, il se tait au lieu de
-- fonctionner a moitie et de montrer des stocks faux.
function NS.LecturesManquantes()
    local manquantes = {}
    local j = NS.jeu
    if not j.nombreEmplacements then table.insert(manquantes, "nombre d'emplacements d'un conteneur") end
    if not j.objetDeLEmplacement then table.insert(manquantes, "objet d'un emplacement") end
    return manquantes
end

function NS.Dire(message)
    if not DEFAULT_CHAT_FRAME then return end
    local prefixe = (NS.L and NS.L.PREFIX) or "CraftCore: "
    DEFAULT_CHAT_FRAME:AddMessage(prefixe .. tostring(message))
    -- Aussi dans l'onglet SagaCore de la discussion, s'il est ouvert.
    local M = _G.SagaCoreMessages
    local onglet = M and M.CadreOnglet and M.CadreOnglet()
    if onglet and onglet ~= DEFAULT_CHAT_FRAME and onglet.AddMessage then onglet:AddMessage(prefixe .. tostring(message)) end
end

function NS.Horodatage()
    local valeur = NS.Appeler(date, "%Y-%m-%d %H:%M")
    if valeur then return valeur end
    return tostring(NS.Appeler(time) or 0)
end

-- Cle du personnage connecte, ou nil tant que le jeu ne donne pas encore son
-- nom et son royaume : une cle "? - ?" creait un personnage fantome.
function NS.ClePersonnage()
    local nom = NS.Appeler(NS.jeu.nomDuPersonnage, "player")
    local royaume = NS.Appeler(NS.jeu.nomDuRoyaume)
    if type(nom) ~= "string" or nom == "" or nom == "?" or nom == _G.UNKNOWNOBJECT then return nil end
    if type(royaume) ~= "string" or royaume == "" or royaume == "?" then return nil end
    return nom .. " - " .. royaume
end

-- Touches assignables, declarees dans le fichier de touches de l'addon. Elles
-- se reglent dans les options du jeu et fonctionnent donc aussi bien au clavier
-- qu'a la manette, avec la navigation native comme avec ConsolePort.
-- Patron repris du journal de donjon, qui en declare deux sur ce client.
local LIBELLES_TOUCHES = {
    frFR = {
        TOGGLE = "Ouvrir ou fermer CraftCore",
        NEXTPAGE = "Page suivante",
        PREVPAGE = "Page précédente",
        NEXTTRADE = "Métier suivant",
        PREVTRADE = "Métier précédent",
    },
    enUS = {
        TOGGLE = "Open or close CraftCore",
        NEXTPAGE = "Next page",
        PREVPAGE = "Previous page",
        NEXTTRADE = "Next profession",
        PREVTRADE = "Previous profession",
    },
}

local langue = (GetLocale and GetLocale()) or "enUS"
local libelles = LIBELLES_TOUCHES[langue] or LIBELLES_TOUCHES.enUS
BINDING_HEADER_CRAFTCORE = "CraftCore"
for cle, texte in pairs(libelles) do
    _G["BINDING_NAME_CRAFTCORE_" .. cle] = texte
end

-- Touche reellement assignee a une commande, telle que le jeu l'affiche. Rien
-- n'est suppose : sans assignation, on renvoie nil et l'ecran le dira.
function NS.ToucheDe(commande)
    local lire = NS.Lecture("GetBindingKey")
    if not lire then return nil end
    local touche = NS.Appeler(lire, "CRAFTCORE_" .. commande)
    if type(touche) ~= "string" or touche == "" then return nil end
    local libeller = NS.Lecture("GetBindingText")
    if libeller then
        local lisible = NS.Appeler(libeller, touche)
        if type(lisible) == "string" and lisible ~= "" then return lisible end
    end
    return touche
end
