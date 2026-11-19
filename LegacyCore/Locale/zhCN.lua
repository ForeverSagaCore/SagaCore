local _, NS = ...
NS.LANGUES = NS.LANGUES or {}
local L = {}
NS.LANGUES.zhCN = L

L.LOADED = "LegacyCore %s 已载入。/lc 打开窗口。"
L.CLOSE = "关闭"
L.NAV_TREES = "我的天赋树"
L.NAV_CHALLENGES = "挑战"
L.NAV_CHARACTERS = "角色"
L.NAV_ADVICE = "建议"
L.TREE_PROFESSIONS = "专业"
L.TREE_ADVENTURE = "冒险"
L.TREE_RESOURCES = "巧思"
L.TREE_SPENT = "  （%d 点）"
L.TIER = "第 %d 行"
L.LEVEL = "%d 级"
L.LOCKED_LEVEL = "传承在 %d 级解锁（此角色：%d 级）。"
L.NO_DATA_HERE = "尚未读取此角色的数据：打开一次传承窗口，然后输入 /reload。"
L.NO_DATA_OTHER = "尚未读取：启用 LegacyCore 后用此角色登录一次。"
L.POINTS_SPENT = "已用点数：%d / %d"
L.POINTS_FREE = "可分配 %d 点"
L.READ_ON = "读取于 %s"
L.DONE_MARK = "已完成"
L.TODO_MARK = "待完成"
L.CHALLENGES_NOTE = "根据已知角色计算（QuestCore、CraftCore、LegacyCore）。以游戏的传承窗口为准。"
L.CHALLENGES_CLASSES = "职业：25、45 和 60 级"
L.CHALLENGES_TRADES = "制造专业：150、225 和 300"
L.BEST_CHAR = "最接近：%s，%d 级"
L.BEST_TRADE = "最接近：%s，技能 %d"
L.NO_TRADE = "CraftCore 不知道有此专业的角色。"
L.PAD_PAGES = "页面"
L.PAD_CHARS = "角色"
L.PAD_SCROLL = "滚动"
L.PROF_164 = "锻造"
L.PROF_165 = "制皮"
L.PROF_171 = "炼金术"
L.PROF_197 = "裁缝"
L.PROF_202 = "工程学"
L.PROF_333 = "附魔"
L.ADVICE_NOTE = "社区指南中最常见的选择（WoW Forever 开服）。天赋名称为翻译；游戏中的名称见“我的天赋树”页面。"
L.PAD_SUITE = "插件"
L.CHALLENGE_CLICK_ROUTE = "点击：前往下一级的路线（QuestCore）"
L.CHALLENGE_LOG_ON = "（登录 %s 以获取路线）"
L.CHALLENGE_ROUTE_NONE = "未找到可用于升级路线的任务。"
L.NAV_TIMELINE = "时间线"
L.TREES_TITLE = "我的天赋树"
L.RANK_OF = "等级 %d / %d"
L.NO_CLASS = "没有此职业的角色。"
L.PLAYED_TOTAL = "游戏时间：%s"
L.LEVEL_TIME = "花费时间：%s"
L.LEVEL_TIME_NOW = "进行中：%s"
L.LEVEL_TIME_UNKNOWN = "在安装 LegacyCore 之前达到：时间未知。"
L.LEVEL_TIME_LATER = "尚未达到。"
L.TIMELINE_LEVELS = "每级时间：%s"
L.LONGEST_LEVEL = "最长：%d 级（%s）"
L.AVERAGE_LEVEL = "平均：每级 %s"
L.TIMELINE_NO_TIME = "此角色尚无时间记录：用它登录一次。"
L.TIMELINE_NOTE = "每一列代表一个等级，高度为在该等级花费的时间。绿色：当前等级；灰色：安装前达到的等级（时间未知）。"
L.TIMELINE_ACCOUNT = "账号时间线"
L.TIMELINE_EMPTY = "暂无内容：你的角色每升一级都会列在这里。"
L.TIMELINE_LEVEL_UP = "达到 %d 级"
L.TIMELINE_TOOK = "%s，%d 级"
L.DUR_DAYS = "%d天%d小时"
L.DUR_HOURS = "%d小时%02d"
L.DUR_MINUTES = "%d 分钟"
L.CHAR_LEVEL_OF = "%s %s 级"
L.CHAR_SKILL_OF = "%s %s"
L.OPEN_LEGACY = "打开传承以分配点数"
L.OPEN_LEGACY_FAIL = "无法打开传承窗口：请使用其快捷键（默认为 Y）。"
L.UNLOCKED_LEVEL = "传承已解锁（%d 级）"
L.OPEN_LEGACY_OTHER = "登录 %s 以分配其点数。"
L.ADVICE = {
    { "升级（冒险）",
        { "精力充沛 5/5", "休息经验积累更快、上限更高。“天赋异禀”的前置。" },
        { "天赋异禀 5/5", "从 5 级而非 10 级开始获得天赋点：升级期间多 5 个天赋点。60 级后无用。" },
        { "冒险的刺激", "每次击杀恢复少量生命和法力，仅限户外。用来填满剩余点数。" } },
    { "经常飞行的小号",
        { "野外指南 3/3，然后常旅客", "飞行路线半价，飞行坐骑更快，替代“冒险的刺激”。" } },
    { "专业与金币（60 级）",
        { "加班加点 5/5", "所有专业的技能提升几率更高。" },
        { "丰收 5/5", "采矿、草药学和剥皮获得更多稀有材料。" },
        { "讨价还价，专心钻研", "商人物品更便宜，最低的专业多一点。" } },
    { "地下城、团队副本、PvP（60 级）",
        { "美食家，持久", "食物增益和长时间的团队增益持续更久。" },
        { "加固", "死亡时损失的耐久度更少。" },
        { "为了荣誉或外交官", "更多荣誉，或更多声望。" } },
    { "提醒",
        { "在职业训练师处重置", "点数属于账号，但按角色分配：60 级时重置，从升级配置切换到满级配置。" } },
}
