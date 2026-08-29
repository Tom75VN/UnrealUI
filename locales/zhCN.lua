-- unrealUI :: locales/zhCN.lua
--
-- Simplified Chinese. See locales/enUS.lua for the catalog and the rules every
-- locale file follows (UTF-8 without BOM, placeholders kept in order, colour
-- escapes kept paired, slash commands never translated).
--
-- knowledge.json / fonts.setfont_silent_failure: this addon cannot ship a
-- font, so CJK glyphs are drawn only if the client's own font provides them.
-- The language selector uses flags, so this language can always be left again
-- even if every other string renders blank.

UnrealUI.RegisterLocale("zhCN", {

-- ---------------------------------------------------------------------------
-- Shared controls
-- ---------------------------------------------------------------------------
COMMON_OK                 = "确定",
COMMON_OK_SHORT           = "确定",
COMMON_CANCEL             = "取消",
COMMON_ACCEPT             = "接受",
COMMON_CLOSE              = "关闭",
COMMON_SAVE               = "保存",
COMMON_DELETE             = "删除",
COMMON_ENABLE             = "启用",
COMMON_ARE_YOU_SURE       = "确定吗？",
COMMON_CANNOT_BE_UNDONE   = "此操作无法撤销。",
COMMON_SELECT_COLOUR      = "选择颜色",
COMMON_COST               = "花费：",
COMMON_SELL               = "售价：",
LOADING_TITLE             = "正在准备 UnrealUI",
LOADING_CLIENT_LIMITATION = "由于当前客户端限制，需要加载，以避免游戏过程中卡顿。",
LOADING_FPS_DEPENDENT     = "时长取决于 FPS。未来客户端更新后将移除。",

-- ---------------------------------------------------------------------------
-- Edit mode
-- ---------------------------------------------------------------------------
MOVER_TITLE               = "编辑界面",
MOVER_HINT_FREE           = "|cfff5ae0aShift + 拖动|r：自由移动",
MOVER_HINT_MAGNET         = "|cfff5ae0a靠近其他元素|r：自动吸附",
MOVER_HINT_ARROWS         = "|cfff5ae0a点击框体|r：方向键每次移动 1 像素",
MOVER_SAVE_EXIT           = "保存并退出",
MOVER_RESET               = "重置",
MOVER_DRAG_FIRST          = "请先拖动一次“%s”，然后再用方向键微调。",
MOVER_ENTERED             = "编辑模式。可拖动、吸附，或用方向键微调。完成后点击|cffffff00保存并退出|r。",
MOVER_SAVED               = "布局已保存，编辑模式已关闭。",
MOVER_RESET_ONE           = "已将 %d 个框体位置重置为默认值。",
MOVER_RESET_OTHER         = "已将 %d 个框体位置重置为默认值。",

MOVER_LABEL_PLAYER        = "玩家",
MOVER_LABEL_TARGET        = "目标",
MOVER_LABEL_TARGET_TARGET = "目标的目标",
MOVER_LABEL_PET           = "宠物",
MOVER_LABEL_PARTY         = "队伍",
MOVER_LABEL_PARTY_N       = "队伍 %d",
MOVER_LABEL_DRUID_MANA    = "德鲁伊法力",
MOVER_LABEL_CASTBAR       = "施法条",
MOVER_LABEL_TARGET_CASTBAR = "目标施法条",
MOVER_LABEL_XP_BAR        = "经验条",
MOVER_LABEL_REP_BAR       = "声望条",
MOVER_LABEL_BREATH_BAR    = "呼吸条",
MOVER_LABEL_MICRO_BAR     = "微型菜单条",
MOVER_LABEL_BUFFS         = "增益与减益",
MOVER_LABEL_MINIMAP       = "小地图",
MOVER_LABEL_PET_BAR       = "宠物动作条",
MOVER_LABEL_STANCE_BAR    = "姿态条",
MOVER_LABEL_STATUS        = "状态信息层",
MOVER_LABEL_ONLINE_COUNT  = "在线人数信息层",
MOVER_LABEL_QUEST_TRACKER = "任务追踪",
MOVER_LABEL_BAGS          = "背包",
MOVER_LABEL_BANK          = "银行",
MOVER_LABEL_ACTION_BAR    = "动作条 %d",
MOVER_LABEL_MOVER_TEST    = "移动测试",

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------
SETTINGS_MOVE_UI          = "移动界面",
SETTINGS_LANGUAGE_CHANGED = "语言已更改",
SETTINGS_LANGUAGE_RELOAD  = "输入 /reload 以将 UnrealUI 切换为%s。",

SETTINGS_PAGE_GENERAL     = "常规",
SETTINGS_PAGE_PROFILES    = "配置文件",
SETTINGS_PAGE_ROGUE       = "潜行者",

SETTINGS_THEME_STYLE      = "主题风格",
SETTINGS_THEME_CHANGED    = "主题已更改",
SETTINGS_THEME_RELOAD     = "输入 /reload 以应用“%s”主题。",
SETTINGS_THEME_HINT       = "“Classic WoW”会在重载后恢复原版原生界面，同时保留游戏菜单中的 UnrealUI 与“快速绑定”入口。“Modern WoW”仍在开发中。",
SETTINGS_THEME_WIP        = "（开发中）",
SETTINGS_THEMES_AVAILABLE = "可用主题：",

SETTINGS_QUICKBIND        = "快速绑定",
SETTINGS_QUICKBIND_HINT   = "将鼠标悬停在动作条或姿态条按钮上并按下按键即可绑定。在按钮上按 Esc 可清除绑定。",
SETTINGS_AUTO_ATTACK      = "选中目标时自动攻击",
SETTINGS_AUTO_ATTACK_HINT = "通过点击或按 Tab 选中可攻击目标时，自动开始普通攻击。潜行者或德鲁伊处于潜行状态时不会触发。",
SETTINGS_MICROBAR         = "启用微型菜单条",
SETTINGS_MICROBAR_HINT    = "将原生的角色、法术书、天赋、任务日志、社交、地图、菜单和帮助按钮集中到一排可移动的按钮中。禁用后它们会回到原来的位置。",
SETTINGS_REPUTATION_BAR   = "显示声望条",
SETTINGS_MINIMAP_BUTTON   = "在小地图旁显示设置按钮",
SETTINGS_ZONE_LEVELS      = "在世界地图上显示区域等级范围",
SETTINGS_ZONE_LEVELS_HINT = "在大陆地图上悬停某个区域时，会在名称旁显示其等级范围：绿色表示低于你的等级，橙色表示与你同级，红色表示高于你的等级。",

ROGUE_SETTINGS_HEADER         = "毒药快捷操作",
ROGUE_POISON_SHIFT_CLICK      = "启用毒药 Shift 点击",
ROGUE_POISON_SHIFT_CLICK_HINT = "在背包中，按住 Shift 左键点击毒药可涂抹到主手，按住 Shift 右键点击可涂抹到副手。聊天输入框打开时仍保持物品链接功能。",

PROFILE_SELECT            = "选择配置文件",
PROFILE_SELECT_HINT       = "选择本账号任意角色创建的配置文件。",
PROFILE_NONE_OTHER        = "没有其他配置文件",
PROFILE_CREATE_COPY       = "创建配置文件副本",
PROFILE_CREATE_HINT       = "以自动生成的名称复制当前设置。若需自定义名称，请使用 /uui profile create <名称>。",
PROFILE_COPY_FROM         = "复制来源",
PROFILE_COPY_SETTINGS     = "复制设置",
PROFILE_COPY_HINT         = "将另一个配置文件的设置复制到当前启用的配置文件中。",
PROFILE_COPIED            = "已将 |cffffff00%s|r 复制到 |cffffff00%s|r",
PROFILE_DELETE_SECTION    = "删除配置文件",
PROFILE_DELETE            = "删除配置文件",
PROFILE_DELETE_HINT       = "删除未分配给任何角色的配置文件。",
PROFILE_DELETED           = "已删除配置文件 |cffffff00%s|r",
PROFILE_CONFIRM_DELETE    = "确认删除",
PROFILE_RESET_SECTION     = "重置当前配置文件",
PROFILE_RESET             = "重置配置文件",
PROFILE_CONFIRM_RESET     = "确认重置",
PROFILE_RESET_HINT        = "恢复默认值。使用同一配置文件的角色将共享其设置。",
PROFILE_CURRENT           = "当前配置文件：|cfff5ae0a%s|r",
PROFILE_CLICK_CONFIRM_DELETE = "点击“确认删除”以移除 |cffffff00%s|r",
PROFILE_CLICK_CONFIRM_RESET  = "点击“确认重置”以恢复当前配置文件的默认值",
PROFILE_NO_NAME_FREE      = "找不到可用的配置文件名称",
PROFILE_RELOAD_NOTICE     = "%s - 输入 |cffffff00/reload|r 以应用",
PROFILE_SELECTED          = "已选择配置文件 |cffffff00%s|r",
PROFILE_CREATED           = "已创建并选择配置文件 |cffffff00%s|r",
PROFILE_WAS_RESET         = "已重置配置文件 |cffffff00%s|r",

-- ---------------------------------------------------------------------------
-- Action bars
-- ---------------------------------------------------------------------------
ABC_GROUP                 = "动作条",
ABC_GENERAL               = "通用选项",
ABC_BAR_N                 = "动作条 %d",
ABC_BUTTONS               = "按钮数量",
ABC_BUTTONS_PER_ROW       = "每行按钮数",
ABC_BUTTON_SIZE           = "按钮大小",
ABC_BUTTON_SPACING        = "按钮间距",
ABC_HIDE_SLOT_BACKGROUND  = "隐藏按钮背景",
ABC_HINT_BAR1             = "动作条 1 跟随动作页面以及原生主动作条的快捷键。",
ABC_HINT_MULTIBAR         = "这些按钮使用原生多重动作条的快捷键。",
ABC_HINT_PAGE_ONLY        = "仅页面动作条：此客户端没有对应的快捷键命令，因此其按钮只能用鼠标点击。",
ABC_RESERVED_FOR          = "已为%s保留",
ABC_RESERVED_ROGUE        = "潜行者潜行",
ABC_RESERVED_WARRIOR      = "战士姿态",
ABC_RESERVED_DRUID        = "德鲁伊形态",
ABC_RESERVED_GENERIC      = "职业/形态页面切换",
ABC_RESERVED_TOOLTIP      = "已为%s保留。动作条 1 会自动使用此页面。",
ABC_RESERVED_EXPLANATION  = "当%s处于激活状态时，动作条 1 会自动使用此动作页面。若再将其显示为一条独立动作条，同一批动作按钮就会出现两次，因此该角色上此页面的布局选项被锁定。",
ABC_RESERVED_SAVED        = "此页面的账号通用设置会被保留。在职业不占用该页面的角色上仍然可用。",
ABC_SHOW_KEYBIND          = "显示快捷键",
ABC_SHOW_MACRO            = "显示宏名称",
ABC_SHOW_COUNT            = "显示物品数量",
ABC_SHOW_COOLDOWN         = "显示冷却计时",
ABC_SHOW_GCD              = "显示公共冷却扫描效果",
ABC_GENERAL_HINT          = "共有 %d 条独立动作条可用。此职业形态使用的页面仅显示在动作条 1 上。",
ABC_BIND_HINT             = "将鼠标悬停在按钮上并按下按键即可绑定，按 Esc 可清除绑定。动作条 1-5 可以绑定；动作条 6-10 在此客户端中没有按键命令，因此会显示但无法绑定。",

-- ---------------------------------------------------------------------------
-- Quick binding
-- ---------------------------------------------------------------------------
QUICKBIND_TITLE           = "快速绑定",
QUICKBIND_OPENED          = "快速绑定。将鼠标悬停在按钮上并按下按键。|cffffff00保存|r 会保留更改，|cffffff00取消|r 或 Esc 则放弃更改。",
QUICKBIND_NO_ACTIONBARS   = "动作条不可用，因此快速绑定没有可绑定的对象。",
QUICKBIND_NO_SLOTS        = "没有可见的动作条按钮，因此没有可绑定的对象。",
QUICKBIND_UNAVAILABLE     = "此版本中快速绑定不可用。",
QUICKBIND_CLEARED         = "已清除动作条 %s 第 %s 格的绑定。",
QUICKBIND_CLEARED_STANCE  = "已清除姿态条第 %s 格的绑定。",
QUICKBIND_NO_COMMAND      = "此客户端没有针对动作条 %s 的按键命令。只有动作条 1-5 可以绑定。",
QUICKBIND_SAVED_ONE       = "已保存 %d 处绑定更改。",
QUICKBIND_SAVED_OTHER     = "已保存 %d 处绑定更改。",
QUICKBIND_NOTHING_CHANGED = "快速绑定已关闭，没有任何更改。",
QUICKBIND_REVERTED_ONE    = "已取消快速绑定，还原了 %d 处更改。",
QUICKBIND_REVERTED_OTHER  = "已取消快速绑定，还原了 %d 处更改。",
QUICKBIND_CLOSED          = "快速绑定已关闭。",
QUICKBIND_COMBAT          = "快速绑定已关闭：进入战斗。",
QUICKBIND_NO_SETBINDING   = "|cffff5555此客户端不支持 SetBinding，快速绑定无法修改按键。|r",
QUICKBIND_SAVE_UNAVAILABLE = "|cffff5555此客户端不支持 SaveBindings：|r按键当前有效，但注销后不会保留。",
QUICKBIND_SAVE_FAILED     = "|cffff5555SaveBindings 失败；|r按键当前有效，但注销后可能不会保留。",
QUICKBIND_SLOT_COUNT_ONE  = "此模式下有 %d 个可绑定按钮。",
QUICKBIND_SLOT_COUNT_OTHER = "此模式下有 %d 个可绑定按钮。",

-- ---------------------------------------------------------------------------
-- Unit frames and auras
-- ---------------------------------------------------------------------------
UF_PAGE                   = "单位框体",
UF_COLORS_HEADER          = "单位框体颜色",
UF_CUSTOM_BAR_COLORS      = "使用自定义状态条颜色",
UF_HEALTH_BAR_COLOR       = "生命条颜色",
UF_CLASS_COLORS           = "玩家生命条使用职业颜色",
UF_POWER_BAR_COLORS       = "能量条颜色",
UF_POWER_MANA             = "法力",
UF_POWER_RAGE             = "怒气",
UF_POWER_FOCUS            = "集中值",
UF_POWER_ENERGY           = "能量",

UF_PARTY_HEADER           = "小队框体",
UF_PARTY_PETS             = "显示队友嬠物",

AURAS_HEADER              = "单位框体光环",
AURAS_ON_PLAYER_FRAME     = "在玩家框体上显示光环",
AURAS_NEAR_MINIMAP        = "在小地图旁显示光环",
AURAS_PLAYER_DEBUFFS      = "玩家框体减益效果",
AURAS_PLAYER_BUFFS        = "玩家框体增益效果",
AURAS_TARGET_DEBUFFS      = "目标框体减益效果",
AURAS_TARGET_BUFFS        = "目标框体增益效果",
AURAS_PARTY_DEBUFFS       = "队伍框体减益效果",
AURAS_PARTY_BUFFS         = "队伍框体增益效果",
AURAS_SHOW_TIMERS         = "在光环图标上显示计时",
AURAS_BELOW_FRAME         = "玩家 / 目标光环显示在框体下方",
AURAS_DISPEL_HEADER       = "按驱散类型显示减益效果",
AURAS_MAGIC               = "魔法",
AURAS_CURSE               = "诅咒",
AURAS_POISON              = "中毒",
AURAS_DISEASE             = "疾病",
AURAS_OTHER               = "物理 / 其他",
AURAS_HINT                = "只有你自己身上的光环计时是准确的。此客户端不会返回其他单位的持续时间，这些计时由法术时长表推算：已在生效的光环会显示为刚刚开始，表中没有的则不显示计时。输入 /uui aura 可查看具体属于哪一种。",

-- ---------------------------------------------------------------------------
-- Bags and bank
-- ---------------------------------------------------------------------------
BAGS_TITLE                = "背包",
BAGS_TOGGLE_KEYRING       = "开关钥匙链",
BAGS_KEYRING_HINT         = "显示钥匙链。",
BAGS_TOGGLE_BAGS          = "开关背包",
BAGS_BAG_SLOTS_HINT       = "显示已装备的背包栏位。",
BAGS_VENDOR_GRAYS         = "出售 / 删除灰色物品",
BAGS_GREYS_HINT           = "在商人处出售灰色物品；其他情况下会询问是否删除。",
BAGS_PICK_LOCK            = "开锁",
BAGS_PICK_LOCK_HINT       = "激活开锁，然后点击背包中的上锁箱子。",
BAGS_PICK_LOCK_ACTION_HINT = "请先将开锁放到任意动作条上，以使用背包快捷按钮。",
BAGS_DELETE_CONFIRM_ONE   = "确定删除 %d 件灰色物品吗？",
BAGS_DELETE_CONFIRM_OTHER = "确定删除 %d 件灰色物品吗？",
BAGS_SOLD_GREYS           = "已出售灰色物品，获得 %s。",
BAGS_DELETED_GREYS_ONE    = "已删除 %d 件灰色物品。",
BAGS_DELETED_GREYS_OTHER  = "已删除 %d 件灰色物品。",
BAGS_NO_GREYS             = "未找到灰色物品。",
BANK_TITLE                = "银行",
BANK_BAG_LABEL            = "银行背包",
BANK_BUY_SLOT             = "是否再购买一个银行背包栏位？",
BANK_PURCHASE             = "购买",
BANK_PURCHASE_TITLE       = "购买银行背包",
BANK_TRANSFER_PICKUP      = "银行转移已停在角色背包中；请再次拾取该物品以继续。",
BANK_TRANSFER_EMPTY_SLOT  = "在银行背包之间移动物品需要一个角色背包格作中转，但没有可用的格子。",
BANK_SLOT_TEMPLATE_FALLBACK = "此客户端不支持 %s；银行栏位将改用背包栏位模板。",
BANK_SLOTS_LOADING        = "客户端尚未返回银行栏位；窗口打开期间将继续重试。",

-- ---------------------------------------------------------------------------
-- Item comparison (modules/tooltip.lua)
-- ---------------------------------------------------------------------------
TOOLTIP_COMPARE_SUMMARY   = "如果替换此物品：",

-- ---------------------------------------------------------------------------
-- Overlays and native screens
-- ---------------------------------------------------------------------------
STATUS_FPS                = "帧数：",
STATUS_LATENCY            = "延迟：",
STATUS_DURABILITY         = "耐久度：",
STATUS_ONLINE             = "在线玩家",

WORLDMAP_CURSOR           = "光标：--, --",
WORLDMAP_CURSOR_OFF_MAP   = "光标：地图之外",
QUESTLOG_LEVELS           = "等级",
GAMEMENU_OPTIONS          = "设置",

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
CMD_HEADER                = "v%s 命令列表：",
CMD_SETTINGS              = "  |cffffff00/uui|r - 打开设置",
CMD_UNLOCK                = "  |cffffff00/uui unlock|r - 解锁框体以便移动",
CMD_LOCK                  = "  |cffffff00/uui lock|r - 锁定框体",
CMD_RESET                 = "  |cffffff00/uui reset|r - 重置所有框体位置",
CMD_BIND                  = "  |cffffff00/uui bind|r - 打开快速绑定",
CMD_CHECK                 = "  |cffffff00/uui check|r - 运行时自检",
CMD_THEME                 = "  |cffffff00/uui theme <style>|r - 选择主题（需要 /reload）",
CMD_LANGUAGE              = "  |cffffff00/uui lang <en/cn/ru/fr>|r - 选择语言（需要 /reload）",
CMD_PROFILE               = "  |cffffff00/uui profile create <名称>|r - 创建并选择共享配置文件",
CMD_DEBUG                 = "  |cffffff00/uui debug|r - 开关调试输出",
CMD_DIAGNOSTICS           = "  |cffffff00/uui help diag|r - 列出诊断命令",
CMD_UNKNOWN               = "未知命令：%s",
CMD_SETTINGS_UNAVAILABLE  = "此版本中设置界面尚不可用。",
CMD_LANGUAGE_CURRENT      = "语言：|cffffff00%s|r",
CMD_LANGUAGE_AVAILABLE    = "可用语言：",
CMD_PROFILE_CURRENT       = "当前配置文件：|cffffff00%s|r",
CMD_PROFILE_CREATE_USAGE  = "  |cffffff00/uui profile create <名称>|r",
CMD_PROFILE_UNAVAILABLE   = "此版本中配置文件管理不可用",
CMD_PROFILE_EXISTS        = "名为 |cffffff00%s|r 的配置文件已存在",
CMD_PROFILE_NAME_RULES    = "配置文件名称可包含字母、数字、空格、连字符和下划线（最多 64 个字符）",
CMD_PROFILE_CREATED       = "已创建并选择配置文件 |cffffff00%s|r - 输入 |cffffff00/reload|r 以应用",

})

-- Chinese does not inflect a noun for count, so every counted string has one
-- form. Registering this rather than duplicating each _ONE key keeps U.LN from
-- falling through to the English _ONE form when the count happens to be 1.
UnrealUI.RegisterLocalePlural("zhCN", function()
  return "OTHER"
end)
