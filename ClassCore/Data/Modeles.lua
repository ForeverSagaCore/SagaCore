local _, NS = ...

-- Modeles de talents conseilles pour WoW Forever, d'apres les guides qui
-- convergent (Warcraft Tavern et d'autres). Chaque modele est l'ordre des
-- points : une lettre change d'arbre (A, B, C), chaque caractere suivant est
-- un point dans la case de la grille de l'arbre (4 colonnes, base 36 :
-- 0 = rangee 1 colonne 1, 4 = rangee 2 colonne 1...). Un modele que l'arbre
-- du jeu ne permet pas (talent change) n'est pas montre.
--
-- activite : "quetes" (montee de niveau), "groupe" (donjons et raids).

NS.MODELES = {
    HUNTER = {
        { activite = "quetes", arbre = 1, code = "A1111144222889aaeeeeehjjaammmmmpB222226666655555eeeee" },
        { activite = "quetes", arbre = 2, code = "B222226666655555eeeeed88ggiiimmpmmmA11111B99999000444b" },
        { activite = "quetes", arbre = 3, code = "C111115522299988dddddjggiimmmmmhhpB222226666655555edb" },
        { activite = "groupe", arbre = 1, code = "A11111442B2222266666dA22aaaaaeeeee9fjjhmmmmmpBee44499ee" },
    },
    MAGE = {
        { activite = "quetes", arbre = 1, code = "A1111177666b6699feeeC222A9hiiiiimmm4p4B1111122222b44444" },
        { activite = "quetes", arbre = 2, code = "C222B2222244444a8881e1111hhhbbmmmccpcA111117766666BfffA4" },
        { activite = "quetes", arbre = 3, code = "A1111177C1111122555a4444dfff4iihggmmmmmp2A66666CgB11111A9" },
    },
    DRUID = {
        { activite = "quetes", arbre = 2, code = "B1111144555a99bbedffchccjjkkkkkqpC22222A222227766B22222" },
        { activite = "quetes", arbre = 3, code = "C2222255544444aafaaabhhhgdddddeeepA2222266111a11C11111" },
    },
    SHAMAN = {
        { activite = "quetes", arbre = 1, code = "A222226667787111ccdddhiiigm" },
        { activite = "quetes", arbre = 2, code = "B1111155566a8887edddddiihhm" },
        { activite = "quetes", arbre = 3, code = "C1111144422a8882eccccicdddd" },
    },
    ROGUE = {
        { activite = "quetes", arbre = 1, code = "A1122222777aa444eeeeehgggggmmmcpccccC22222AdB0002244466" },
        { activite = "quetes", arbre = 2, code = "A11B11000555669688bdeeffhggiiiiimmpmmmbfA22277722aa444" },
        { activite = "quetes", arbre = 3, code = "A11B11C2222266655aaa59d8881ih11cmmmmmpB000A22222777aa444" },
        { activite = "quetes", arbre = 3, code = "A11C0001155544aaa98d8877iffh2mm222p21A222227779B000AaaCcc", variante = "saignement" },
    },
}
