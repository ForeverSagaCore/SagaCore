local _, NS = ...
NS.L = NS.L or {}
local L = NS.L
L.TITLE = "LegacyCore"
L.LOADED = "LegacyCore %s loaded. /lc opens the window."
L.CLOSE = "Close"
L.NAV_TREES = "My trees"
L.NAV_CHALLENGES = "Challenges"
L.NAV_CHARACTERS = "Characters"
L.NAV_ADVICE = "Advice"
L.TREE_PROFESSIONS = "Professions"
L.TREE_ADVENTURE = "Adventure"
L.TREE_RESOURCES = "Ingenuity"
L.TREE_SPENT = "  (%d points)"
L.TIER = "Row %d"
L.LEVEL = "Level %d"
L.LOCKED_LEVEL = "Legacy unlocks at level %d (this character: %d)."
L.NO_DATA_HERE = "Nothing read yet for this character: open your Legacy window once, then /reload."
L.NO_DATA_OTHER = "Not read yet: log in once on this character with LegacyCore enabled."
L.POINTS_SPENT = "Points spent: %d / %d"
L.POINTS_FREE = "%d to spend"
L.READ_ON = "Read on %s"
L.DONE_MARK = "Done"
L.TODO_MARK = "To do"
L.CHALLENGES_NOTE = "Worked out from your known characters (QuestCore, CraftCore, LegacyCore). The game's Legacy window is the reference."
L.CHALLENGES_CLASSES = "Classes: levels 25, 45 and 60"
L.CHALLENGES_TRADES = "Crafting professions: 150, 225 and 300"
L.BEST_CHAR = "Closest: %s, level %d"
L.BEST_TRADE = "Closest: %s, skill %d"
L.NO_TRADE = "No character with this profession known by CraftCore."
L.PAD_PAGES = "Pages"
L.PAD_CHARS = "Characters"
L.PAD_SCROLL = "Scroll"
L.PROF_164 = "Blacksmithing"
L.PROF_165 = "Leatherworking"
L.PROF_171 = "Alchemy"
L.PROF_197 = "Tailoring"
L.PROF_202 = "Engineering"
L.PROF_333 = "Enchanting"
L.ADVICE_NOTE = "Most common choices in community guides (WoW Forever launch). Talent names are translated; the game's own names are on the My trees page."
L.ADVICE = {
    { "Leveling (Adventure)",
        { "Well Rested 5/5", "Rested experience builds faster and holds more. Required for Talented." },
        { "Talented 5/5", "Talent points start at level 5 instead of 10: five more talent points while leveling. Useless at 60." },
        { "Thrill of Adventure", "Some health and mana back on each kill, outdoors only. Fills the remaining points." } },
    { "Alts who fly a lot",
        { "Field Guide 3/3, then Frequent Flier", "Flight paths half price and a faster flight mount, instead of Thrill of Adventure." } },
    { "Professions and gold (at 60)",
        { "Working Overtime 5/5", "Better chance of a skill increase in every profession." },
        { "Bountiful Harvest 5/5", "More rare materials from mining, herbalism and skinning." },
        { "Bartering, Dedicated Study", "Cheaper vendor items, and one more point in your lowest profession." } },
    { "Dungeons, raids, PvP (at 60)",
        { "Gourmand, Permanence", "Food buffs and long group buffs last longer." },
        { "Reinforce", "Less durability lost on death." },
        { "For Great Honor or Diplomat", "More honor, or more reputation." } },
    { "Reminder",
        { "Respec at your class trainer", "Points are shared by the account but spent per character: reset at 60 to move from leveling to your end game build." } },
}
L.PAD_SUITE = "Add-ons"
L.CHALLENGE_CLICK_ROUTE = "Click: route to the next level (QuestCore)"
L.CHALLENGE_LOG_ON = "(log on %s for a route)"
L.CHALLENGE_ROUTE_NONE = "No quest found for a leveling route."
L.NAV_TIMELINE = "Timeline"
L.TREES_TITLE = "My trees"
L.RANK_OF = "Rank %d / %d"
L.NO_CLASS = "No character of this class."
L.PLAYED_TOTAL = "Played: %s"
L.LEVEL_TIME = "Time spent: %s"
L.LEVEL_TIME_NOW = "In progress: %s"
L.LEVEL_TIME_UNKNOWN = "Reached before LegacyCore was installed: time unknown."
L.LEVEL_TIME_LATER = "Not reached yet."
L.TIMELINE_LEVELS = "Time per level: %s"
L.LONGEST_LEVEL = "Longest: level %d (%s)"
L.AVERAGE_LEVEL = "Average: %s per level"
L.TIMELINE_NO_TIME = "No time recorded yet for this character: log in once on it."
L.TIMELINE_NOTE = "Each column is a level, its height the time spent on it. Green: the current level; gray: levels reached before installation (time unknown)."
L.TIMELINE_ACCOUNT = "Account timeline"
L.TIMELINE_EMPTY = "Nothing yet: every level your characters gain will be listed here."
L.TIMELINE_LEVEL_UP = "reached level %d"
L.TIMELINE_TOOK = "%s at level %d"
L.DUR_DAYS = "%dd %dh"
L.DUR_HOURS = "%dh %02d"
L.DUR_MINUTES = "%d min"
L.CHAR_LEVEL_OF = "%s level %s"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "Open Legacy to spend points"
L.OPEN_LEGACY_FAIL = "Could not open the Legacy window: use its key (Y by default)."
L.UNLOCKED_LEVEL = "Legacy unlocked (level %d)"
