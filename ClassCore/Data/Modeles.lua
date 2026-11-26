local _, NS = ...

-- Modeles de talents conseilles pour WoW Forever, d'apres les guides
-- publies pour Forever (sources ci-dessous). Deux formes :
--   code  : l'ordre des points (Warcraft Tavern). Une lettre change d'arbre
--           (A, B, C), chaque caractere suivant est un point dans la case de
--           la grille de l'arbre (4 colonnes, base 36 : 0 = rangee 1
--           colonne 1, 4 = rangee 2 colonne 1...).
--   rangs : les rangs finaux (wowforevertalent, talentsforever) : un chiffre
--           par talent de l'arbre, dans l'ordre du jeu (rangee puis
--           colonne), un arbre apres l'autre separes par "-". L'ordre des
--           points en est deduit (l'arbre principal d'abord, de haut en bas).
-- Un modele que l'arbre du jeu ne permet pas (talent change) n'est pas montre.
--
-- activite : "solo" (montee de niveau), "donjons" (donjons pendant la
-- montee), "jce" (raids et donjons au niveau 60), "jcj" (joueur contre
-- joueur). jusqua : niveau ou le modele s'arrete (modeles courts).
--
-- Sources : warcrafttavern.com/forever (guides de montee de niveau),
-- wowforevertalent.com/builds, talentsforever.com/hunter/builds.

NS.MODELES = {
    HUNTER = {
        { activite = "solo", code = "A1111144222889aaeeeeehjjaammmmmpB222226666655555eeeee" },
        { activite = "solo", code = "B222226666655555eeeeed88ggiiimmpmmmA11111B99999000444b" },
        { activite = "solo", code = "C111115522299988dddddjggiimmmmmhhpB222226666655555edb" },
        { activite = "jce", code = "A11111442B2222266666dA22aaaaaeeeee9fjjhmmmmmpBee44499ee" },
        { activite = "jce", rangs = "5-3053552011523051-5" },
        { activite = "jce", rangs = "5-005005001-500230230250222151" },
        { activite = "jcj", rangs = "5-3453552011523151-" },
    },
    MAGE = {
        { activite = "solo", code = "A1111177666b6699feeeC222A9hiiiiimmm4p4B1111122222b44444" },
        { activite = "solo", code = "C222B2222244444a8881e1111hhhbbmmmccpcA111117766666BfffA4" },
        { activite = "solo", code = "A1111177C1111122555a4444dfff4iihggmmmmmp2A66666CgB11111A9" },
    },
    DRUID = {
        { activite = "solo", code = "B1111144555a99bbedffchccjjkkkkkqpC22222A222227766B22222" },
        { activite = "solo", code = "C2222255544444aafaaabhhhgdddddeeepA2222266111a11C11111" },
        { activite = "donjons", rangs = "0000000000000000-5500010000000000000-0000000000000000", jusqua = 20 },
        { activite = "jce", rangs = "5532220115501351-00000000000000000000-5050000000000000" },
        { activite = "jcj", rangs = "3302213100521251-00000000000000000000-5053002022100000" },
    },
    SHAMAN = {
        { activite = "solo", code = "A222226667787111ccdddhiiigm" },
        { activite = "solo", code = "B1111155566a8887edddddiihhm" },
        { activite = "solo", code = "C1111144422a8882eccccicdddd" },
    },
    ROGUE = {
        { activite = "solo", code = "A1122222777aa444eeeeehgggggmmmcpccccC22222AdB0002244466" },
        { activite = "solo", code = "A11B11000555669688bdeeffhggiiiiimmpmmmbfA22277722aa444" },
        { activite = "solo", code = "A11B11C2222266655aaa59d8881ih11cmmmmmpB000A22222777aa444" },
        { activite = "solo", code = "A11C0001155544aaa98d8877iffh2mm222p21A222227779B000AaaCcc", variante = "saignement" },
    },
    WARLOCK = {
        { activite = "solo", rangs = "25522323035201351-0050020000000000000-0000000000000000" },
        { activite = "jce", rangs = "15522320035201351-2050003001000000000-0000000000000000" },
        { activite = "jce", rangs = "00000000000000000-0051203231220001351-2550305000000000" },
        { activite = "jcj", rangs = "02530013104211250-2050203221201001000-0000000000000000" },
    },
    PRIEST = {
        { activite = "solo", rangs = "525035031333011001-00000000000000000-00552201000000000" },
        { activite = "donjons", rangs = "005203000100000000-00000000000000000-00000000000000000", jusqua = 20 },
    },
    WARRIOR = {
        { activite = "solo", rangs = "00000000000000000-0505001000000000000-000000000000000000", jusqua = 20 },
    },
    PALADIN = {
        { activite = "donjons", rangs = "00000000000000000-05302001000000000-00000000000000000", jusqua = 20 },
    },
}
