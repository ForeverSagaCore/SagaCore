local _, NS = ...

-- Le catalogue des familiers du chasseur : chaque famille, son regime, ses
-- techniques, et la technique propre a la famille sur Forever. Les
-- techniques ont leurs rangs : niveau du familier et points de dressage.
-- Les betes qui enseignent chaque rang sont dans Data/Dresseurs.lua.

local T = NS.T

NS.dataFamiliers = {}
local D = NS.dataFamiliers

-- Regimes : cle -> libelle.
D.REGIMES = {
    viande = function() return T("Viande", "Meat") end,
    poisson = function() return T("Poisson", "Fish") end,
    fruits = function() return T("Fruits", "Fruit") end,
    champignons = function() return T("Champignons", "Fungus") end,
    pain = function() return T("Pain", "Bread") end,
    fromage = function() return T("Fromage", "Cheese") end,
}

-- Techniques : cle -> { nom, rangs = { { niveau du familier, points } } }
-- (rangs seulement quand une source les confirme).
D.TECHNIQUES = {
    Bite = { nom = function() return T("Morsure", "Bite") end, icone = "Interface\\Icons\\Ability_Racial_Cannibalize",
        rangs = { { 1, 1 }, { 8, 4 }, { 16, 7 }, { 24, 10 }, { 32, 13 }, { 40, 17 }, { 48, 21 }, { 56, 25 } } },
    Claw = { nom = function() return T("Griffe", "Claw") end, icone = "Interface\\Icons\\Ability_Druid_Rake",
        rangs = { { 1, 1 }, { 8, 4 }, { 16, 7 }, { 24, 10 }, { 32, 13 }, { 40, 17 }, { 48, 21 }, { 56, 25 } } },
    Cower = { nom = function() return T("Dérobade", "Cower") end, icone = "Interface\\Icons\\Ability_Druid_Cower",
        rangs = nil },
    Charge = { nom = function() return T("Charge", "Charge") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
        rangs = { { 1 }, { 12 }, { 24 }, { 36 }, { 48 }, { 60 } } },
    Dash = { nom = function() return T("Course", "Dash") end, icone = "Interface\\Icons\\Ability_Druid_Dash",
        rangs = { { 30, 15 }, { 40, 20 }, { 50, 25 } } },
    Dive = { nom = function() return T("Plongeon", "Dive") end, icone = "Interface\\Icons\\Spell_Shadow_BurningSpirit",
        rangs = { { 30, 15 }, { 40, 20 }, { 50, 25 } } },
    ["Furious Howl"] = { nom = function() return T("Hurlement furieux", "Furious Howl") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
        rangs = { { 10 }, { 24 }, { 40 }, { 56 } } },
    ["Lightning Breath"] = { nom = function() return T("Souffle de foudre", "Lightning Breath") end, icone = "Interface\\Icons\\Spell_Nature_Lightning",
        rangs = { { 1 }, { 12 }, { 24 }, { 36 }, { 48 }, { 60 } } },
    Prowl = { nom = function() return T("Rôder", "Prowl") end, icone = "Interface\\Icons\\Ability_Druid_SupriseAttack",
        rangs = nil },
    ["Scorpid Poison"] = { nom = function() return T("Poison de scorpide", "Scorpid Poison") end, icone = "Interface\\Icons\\Ability_PoisonSting",
        rangs = nil },
    Screech = { nom = function() return T("Hurlement", "Screech") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
        rangs = nil },
    ["Shell Shield"] = { nom = function() return T("Bouclier de carapace", "Shell Shield") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
        rangs = nil },
    Thunderstomp = { nom = function() return T("Choc du tonnerre", "Thunderstomp") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
        rangs = nil },
}

D.ORDRE_TECHNIQUES = { "Bite", "Claw", "Cower", "Charge", "Dash", "Dive", "Furious Howl", "Lightning Breath",
    "Prowl", "Scorpid Poison", "Screech", "Shell Shield", "Thunderstomp" }

-- Familles : regimes du client Classic (masque PetFoodMask) ; la technique
-- propre a chaque famille sur Forever (warcrafttavern).
D.FAMILLES = {
    { cle = "Bat", nom = function() return T("Chauve-souris", "Bat") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
      regime = { "fruits", "champignons" }, techniques = { "Bite", "Cower", "Dive", "Screech" }, unique = "Sonic Blast" },
    { cle = "Bear", nom = function() return T("Ours", "Bear") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
      regime = { "viande", "poisson", "fruits", "champignons", "pain", "fromage" }, techniques = { "Bite", "Claw", "Cower" }, unique = "Swipe" },
    { cle = "Boar", nom = function() return T("Sanglier", "Boar") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
      regime = { "viande", "poisson", "fruits", "champignons", "pain", "fromage" }, techniques = { "Bite", "Charge", "Cower", "Dash" }, unique = "Charge" },
    { cle = "Carrion Bird", nom = function() return T("Charognard", "Carrion Bird") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Vulture",
      regime = { "viande", "poisson" }, techniques = { "Bite", "Claw", "Cower", "Dive", "Screech" }, unique = "Demoralizing Screech" },
    { cle = "Cat", nom = function() return T("Félin", "Cat") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
      regime = { "viande", "poisson" }, techniques = { "Bite", "Claw", "Cower", "Dash", "Prowl" }, unique = "Prowl" },
    { cle = "Crab", nom = function() return T("Crabe", "Crab") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Crab",
      regime = { "poisson", "pain", "champignons", "fruits" }, techniques = { "Claw", "Cower" }, unique = "Pinch" },
    { cle = "Crocolisk", nom = function() return T("Crocilisque", "Crocolisk") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Crocolisk",
      regime = { "viande", "poisson" }, techniques = { "Bite", "Cower" }, unique = "Dismember" },
    { cle = "Fox", nom = function() return T("Renard", "Fox") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
      regime = { "fruits", "viande" }, techniques = { "Bite", "Cower", "Dash" }, unique = "Trickster's Dance", forever = true },
    { cle = "Gorilla", nom = function() return T("Gorille", "Gorilla") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
      regime = { "fruits", "champignons" }, techniques = { "Bite", "Cower", "Thunderstomp" }, unique = "Thunderstomp" },
    { cle = "Hyena", nom = function() return T("Hyène", "Hyena") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
      regime = { "viande", "fruits" }, techniques = { "Bite", "Cower", "Dash" }, unique = "Tendon Rip" },
    { cle = "Owl", nom = function() return T("Chouette", "Owl") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Owl",
      regime = { "viande" }, techniques = { "Claw", "Cower", "Dive", "Screech" }, unique = "Mine!" },
    { cle = "Raptor", nom = function() return T("Raptor", "Raptor") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
      regime = { "viande" }, techniques = { "Bite", "Claw", "Cower", "Dash" }, unique = "Savage Rend" },
    { cle = "Scorpid", nom = function() return T("Scorpide", "Scorpid") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
      regime = { "viande" }, techniques = { "Claw", "Cower", "Scorpid Poison" }, unique = "Scorpid Poison" },
    { cle = "Spider", nom = function() return T("Araignée", "Spider") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
      regime = { "viande" }, techniques = { "Bite", "Cower" }, unique = "Web" },
    { cle = "Tallstrider", nom = function() return T("Haut-trotteur", "Tallstrider") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_TallStrider",
      regime = { "fromage", "fruits", "champignons" }, techniques = { "Bite", "Cower", "Dash" }, unique = "Dust Cloud" },
    { cle = "Turtle", nom = function() return T("Tortue", "Turtle") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
      regime = { "poisson", "fruits", "champignons" }, techniques = { "Bite", "Cower", "Shell Shield" }, unique = "Shell Shield" },
    { cle = "Wind Serpent", nom = function() return T("Serpent des vents", "Wind Serpent") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
      regime = { "poisson", "fromage", "pain" }, techniques = { "Bite", "Cower", "Dive", "Lightning Breath" }, unique = "Lightning Breath" },
    { cle = "Wolf", nom = function() return T("Loup", "Wolf") end, icone = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
      regime = { "viande" }, techniques = { "Bite", "Cower", "Dash", "Furious Howl" }, unique = "Furious Howl" },
}

-- Les betes qui enseignent (remplies par Data/Dresseurs.lua).
D.DRESSEURS = D.DRESSEURS or {}
D.RARES = D.RARES or {}
