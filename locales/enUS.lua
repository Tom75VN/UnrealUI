-- unrealUI :: locales/enUS.lua
--
-- English. This file is the catalog: it defines every key the addon may look
-- up, and core/locale.lua falls back to it for anything another language has
-- not translated yet. A key that does not exist here is a bug -- it will show
-- in game as its own upper-case identifier.
--
-- Conventions for every locale file:
--   * UTF-8, no BOM, LF line endings.
--   * `%s` / `%d` placeholders keep their order and count. Where a sentence
--     needs a different word order, reorder the sentence, not the arguments.
--   * Colour escapes (|cffffff00 ... |r) are part of the string. Keep them
--     paired and keep them around the same word they highlight here.
--   * Slash commands (/uui, /reload) are client input and are never
--     translated.
--   * _ONE / _OTHER suffixed pairs are plural forms selected by U.LN; a
--     language may add _FEW / _MANY and register a rule in its own file.

UnrealUI.RegisterLocale("enUS", {

-- Opt-in custom pet bar (native remains the default).
CMD_PETBAR                = "  |cffffff00/uui petbar <native/custom>|r - select the pet bar (needs /reload)",
PETBAR_MODE_NATIVE        = "Native",
PETBAR_MODE_CUSTOM        = "Custom (Modern)",
PETBAR_MODE_STATUS        = "Pet bar: %s. Selected for next reload: %s.",
PETBAR_MODE_SELECTED      = "Pet bar selected: %s. Type /reload to apply.",
PETBAR_CUSTOM_WARNING     = "Experimental custom pet bar: this client blocks pet spell clicks. Restore native casting with /uui petbar native, then /reload.",
PETBAR_ACTION_UNAVAILABLE = "This pet action is unavailable on this client.",
PETBAR_UNAVAILABLE        = "Pet bar mode controls are unavailable in this session.",

-- ---------------------------------------------------------------------------
-- Shared controls (core/widgets.lua, core/style.lua)
-- ---------------------------------------------------------------------------
COMMON_OK                 = "Okay",
COMMON_OK_SHORT           = "OK",
COMMON_CANCEL             = "Cancel",
COMMON_ACCEPT             = "Accept",
COMMON_CLOSE              = "Close",
COMMON_SAVE               = "Save",
COMMON_DELETE             = "Delete",
COMMON_ENABLE             = "Enable",
COMMON_ARE_YOU_SURE       = "Are you sure?",
COMMON_CANNOT_BE_UNDONE   = "This cannot be undone.",
COMMON_SELECT_COLOUR      = "Select colour",
COMMON_COST               = "Cost:",
COMMON_SELL               = "Sell:",
LOADING_TITLE             = "Preparing UnrealUI",
LOADING_CLIENT_LIMITATION = "Loading required due to current client limitations. To avoid freeze while playing.",
LOADING_FPS_DEPENDENT     = "Duration depends on FPS. Removed in future client update.",

-- ---------------------------------------------------------------------------
-- Edit mode (core/mover.lua)
-- ---------------------------------------------------------------------------
MOVER_TITLE               = "Edit UI",
MOVER_HINT_FREE           = "|cfff5ae0aShift + drag|r: free movement",
MOVER_HINT_MAGNET         = "|cfff5ae0aNear another element|r: magnet",
MOVER_HINT_ARROWS         = "|cfff5ae0aClick a frame|r: keyboard arrows move 1 px",
MOVER_SAVE_EXIT           = "Save and exit",
MOVER_RESET               = "Reset",
MOVER_DRAG_FIRST          = "Drag %s once before nudging it.",
MOVER_ENTERED             = "Edit mode. Drag, snap, or nudge with arrow keys. |cffffff00Save and exit|r when done.",
MOVER_SAVED               = "Layout saved. Edit mode closed.",
MOVER_RESET_ONE           = "Reset %d frame position to defaults.",
MOVER_RESET_OTHER         = "Reset %d frame positions to defaults.",

-- Names shown on the edit-mode overlay of each movable element.
MOVER_LABEL_PLAYER        = "Player",
MOVER_LABEL_TARGET        = "Target",
MOVER_LABEL_TARGET_TARGET = "Target of target",
MOVER_LABEL_PET           = "Pet",
MOVER_LABEL_PARTY         = "Party",
MOVER_LABEL_PARTY_N       = "Party %d",
MOVER_LABEL_DRUID_MANA    = "Druid Mana",
MOVER_LABEL_CASTBAR       = "Cast bar",
MOVER_LABEL_TARGET_CASTBAR = "Target cast bar",
MOVER_LABEL_PET_CASTBAR   = "Pet cast bar",
MOVER_LABEL_XP_BAR        = "Experience Bar",
MOVER_LABEL_REP_BAR       = "Reputation Bar",
MOVER_LABEL_BREATH_BAR    = "Breath Bar",
MOVER_LABEL_SWING_BAR     = "Auto attack : Swing bar",
MOVER_LABEL_MICRO_BAR     = "Micro Bar",
MOVER_LABEL_BUFFS         = "Buffs & Debuffs",
MOVER_LABEL_MINIMAP       = "Minimap",
MOVER_LABEL_PET_BAR       = "Pet Bar",
MOVER_LABEL_STANCE_BAR    = "Stance Bar",
MOVER_LABEL_STATUS        = "Status Overlay",
MOVER_LABEL_ONLINE_COUNT  = "Online Count Overlay",
MOVER_LABEL_QUEST_TRACKER = "Quest Tracker",
MOVER_LABEL_BANK          = "Bank",
MOVER_LABEL_ACTION_BAR    = "Bar %d",
MOVER_LABEL_MOVER_TEST    = "Mover test",

-- ---------------------------------------------------------------------------
-- Settings window (modules/settings.lua)
-- ---------------------------------------------------------------------------
SETTINGS_MOVE_UI          = "Move UI",
SETTINGS_LANGUAGE_CHANGED = "Language changed",
SETTINGS_LANGUAGE_RELOAD  = "Type /reload to show UnrealUI in %s.",

SETTINGS_PAGE_GENERAL     = "General",
SETTINGS_PAGE_PROFILES    = "Profiles",
SETTINGS_PAGE_BAGS        = "Bags",
SETTINGS_PAGE_ROGUE       = "Rogue",

SETTINGS_THEME_STYLE      = "Theme style",
SETTINGS_THEME_CHANGED    = "Theme changed",
SETTINGS_THEME_RELOAD     = "Type /reload to apply the %s theme.",
SETTINGS_THEME_HINT       = "Classic WoW restores the original native interface after a reload, keeping the UnrealUI and Quick Binding entries in the game menu. Modern WoW is still in development.",
SETTINGS_THEME_WIP        = " (WIP)",
SETTINGS_THEMES_AVAILABLE = "available themes:",

SETTINGS_QUICKBIND        = "Quick Binding",
SETTINGS_QUICKBIND_HINT   = "Hover an action bar or stance bar slot and press a key to bind it. Escape over a slot clears it.",
SETTINGS_AUTO_ATTACK      = "Start auto attack when targeting",
SETTINGS_AUTO_ATTACK_HINT = "Click or Tab to attack. Put Auto Shot (hunters) or Shoot on an action bar to switch between bow/gun and melee with distance. Stops when you stop attacking. Stops the attack, and never starts one, while a Rogue is stealthed or a Druid prowls.",
SETTINGS_SWING_BAR        = "Show auto attack swing bar",
SETTINGS_SWING_BAR_HINT   = "Shows main-hand, off-hand, and bow or ranged swing timing while the target is in range. Move it with Move UI.",
SETTINGS_MICROBAR         = "Enable micro bar",
SETTINGS_MICROBAR_HINT    = "Pulls the native character/spellbook/talent/quest log/social/map/menu/help buttons into one movable row. Disabling returns them to their stock location.",
SETTINGS_REPUTATION_BAR   = "Show reputation bar",
SETTINGS_MINIMAP_BUTTON   = "Show minimap settings button",
SETTINGS_ZONE_LEVELS      = "Show zone level ranges on the world map",
SETTINGS_ZONE_LEVELS_HINT = "Hovering a zone on a continent map shows its level range beside the name: green below your level, orange at your level, red above your level.",

SWING_BAR_MAIN            = "MH",
SWING_BAR_OFF             = "OH",
SWING_BAR_RANGED          = "R",

ROGUE_SETTINGS_HEADER         = "Poison shortcuts",
ROGUE_POISON_SHIFT_CLICK      = "Enable poison Shift-clicks",
ROGUE_POISON_SHIFT_CLICK_HINT = "In the bags, Shift-left-click a poison for the main hand or Shift-right-click it for the off hand. Chat linking is unchanged while the chat input is open.",

-- Profiles page
PROFILE_SELECT            = "Select Profile",
PROFILE_SELECT_HINT       = "Choose a profile created by any character on this account.",
PROFILE_NONE_OTHER        = "No other profiles",
PROFILE_CREATE_COPY       = "Create Profile Copy",
PROFILE_CREATE_HINT       = "Copies the current settings under a generated name. For a custom name, use /uui profile create <name>.",
PROFILE_COPY_FROM         = "Copy From",
PROFILE_COPY_SETTINGS     = "Copy Settings",
PROFILE_COPY_HINT         = "Copies another profile into the currently active profile.",
PROFILE_COPIED            = "copied |cffffff00%s|r into |cffffff00%s|r",
PROFILE_DELETE_SECTION    = "Delete a Profile",
PROFILE_DELETE            = "Delete Profile",
PROFILE_DELETE_HINT       = "Deletes a profile not assigned to any character.",
PROFILE_DELETED           = "deleted profile |cffffff00%s|r",
PROFILE_CONFIRM_DELETE    = "Confirm Delete",
PROFILE_RESET_SECTION     = "Reset Current Profile",
PROFILE_RESET             = "Reset Profile",
PROFILE_CONFIRM_RESET     = "Confirm Reset",
PROFILE_RESET_HINT        = "Restores defaults. Characters using the same profile share its settings.",
PROFILE_CURRENT           = "Current Profile: |cfff5ae0a%s|r",
PROFILE_CLICK_CONFIRM_DELETE = "click Confirm Delete to remove |cffffff00%s|r",
PROFILE_CLICK_CONFIRM_RESET  = "click Confirm Reset to restore the current profile defaults",
PROFILE_NO_NAME_FREE      = "could not find an available profile name",
PROFILE_RELOAD_NOTICE     = "%s - |cffffff00/reload|r to apply it",
PROFILE_SELECTED          = "selected profile |cffffff00%s|r",
PROFILE_CREATED           = "created and selected profile |cffffff00%s|r",
PROFILE_WAS_RESET         = "reset profile |cffffff00%s|r",

-- ---------------------------------------------------------------------------
-- Action bars (modules/actionbarconfig.lua)
-- ---------------------------------------------------------------------------
ABC_GROUP                 = "ActionBars",
ABC_GENERAL               = "General Options",
ABC_BAR_N                 = "Bar %d",
ABC_BUTTONS               = "Buttons",
ABC_BUTTONS_PER_ROW       = "Buttons Per Row",
ABC_BUTTON_SIZE           = "Button Size",
ABC_BUTTON_SPACING        = "Button Spacing",
ABC_HIDE_SLOT_BACKGROUND  = "Hide Slot Background",
ABC_HINT_BAR1             = "Bar 1 follows the action page and the stock bar keybinds.",
ABC_HINT_MULTIBAR         = "Uses the stock multi-bar keybinds for these slots.",
ABC_HINT_PAGE_ONLY        = "Page-only bar: this client has no keybind command for it, so its slots are mouse-only.",
ABC_RESERVED_FOR          = "Reserved for %s",
ABC_RESERVED_ROGUE        = "Rogue Stealth",
ABC_RESERVED_WARRIOR      = "Warrior stances",
ABC_RESERVED_DRUID        = "Druid forms",
ABC_RESERVED_GENERIC      = "class/form paging",
ABC_RESERVED_TOOLTIP      = "Reserved for %s. Bar 1 uses this page automatically.",
ABC_RESERVED_EXPLANATION  = "This action page is used automatically by Bar 1 while %s is active. Showing it as another physical bar would expose the same action slots twice, so its layout controls are locked on this character.",
ABC_RESERVED_SAVED        = "Account-wide settings for this page are preserved. They remain available on characters whose class does not reserve it.",
ABC_SHOW_KEYBIND          = "Show keybinds",
ABC_SHOW_MACRO            = "Show macro names",
ABC_SHOW_COUNT            = "Show item counts",
ABC_SHOW_COOLDOWN         = "Show cooldown timers",
ABC_SHOW_GCD              = "Show global cooldown",
ABC_GENERAL_HINT          = "%d independent bars are available. Pages used by this class's forms are shown only on Bar 1.",
ABC_BIND_HINT             = "Hover a slot and press a key to bind it. Escape over a slot clears it. Bars 1-5 are bindable; bars 6-10 have no key command in this client, so they are shown but cannot take one.",

-- ---------------------------------------------------------------------------
-- Quick binding (modules/quickbind.lua)
-- ---------------------------------------------------------------------------
QUICKBIND_TITLE           = "Quick Binding",
QUICKBIND_OPENED          = "Quick binding. Hover a slot and press a key. |cffffff00Save|r keeps the changes, |cffffff00Cancel|r or Escape drops them.",
QUICKBIND_NO_ACTIONBARS   = "action bars are not available, so quick binding has nothing to bind.",
QUICKBIND_NO_SLOTS        = "no action bar slots are visible, so there is nothing to bind.",
QUICKBIND_UNAVAILABLE     = "quick binding is not available in this build.",
QUICKBIND_CLEARED         = "Cleared the binding on bar %s slot %s.",
QUICKBIND_CLEARED_STANCE  = "Cleared the binding on stance slot %s.",
QUICKBIND_NO_COMMAND      = "This client has no key command for bar %s. Bars 1-5 are the bindable ones.",
QUICKBIND_SAVED_ONE       = "Saved %d binding change.",
QUICKBIND_SAVED_OTHER     = "Saved %d binding changes.",
QUICKBIND_NOTHING_CHANGED = "Quick binding closed. Nothing changed.",
QUICKBIND_REVERTED_ONE    = "Quick binding cancelled. %d change reverted.",
QUICKBIND_REVERTED_OTHER  = "Quick binding cancelled. %d changes reverted.",
QUICKBIND_CLOSED          = "Quick binding closed.",
QUICKBIND_COMBAT          = "Quick binding closed: combat started.",
QUICKBIND_NO_SETBINDING   = "|cffff5555SetBinding is unavailable in this client; quick binding cannot change keys.|r",
QUICKBIND_SAVE_UNAVAILABLE = "|cffff5555SaveBindings is unavailable in this client:|r your keys work now but will not survive a logout.",
QUICKBIND_SAVE_FAILED     = "|cffff5555SaveBindings failed;|r your keys work now but may not survive a logout.",
QUICKBIND_SLOT_COUNT_ONE  = "%d slot in this mode.",
QUICKBIND_SLOT_COUNT_OTHER = "%d slots in this mode.",

-- ---------------------------------------------------------------------------
-- Unit frames and auras (modules/unitframes.lua, modules/auras.lua)
-- ---------------------------------------------------------------------------
UF_PAGE                   = "Unit Frames",
-- Sub-pages of the Unit Frames group in the settings window.
UF_TAB_GENERAL            = "General Options",
UF_TAB_PARTY              = "Party Frames",
UF_TAB_AURAS              = "Auras",
UF_TAB_COLORS             = "Colors",
UF_COLORS_HEADER          = "Unit Frame Colors",
UF_CUSTOM_BAR_COLORS      = "Use custom bar colors",
UF_HEALTH_BAR_COLOR       = "Health bar color",
UF_CLASS_COLORS           = "Use class colors for player health bars",
UF_POWER_BAR_COLORS       = "Power bar colors",
UF_POWER_MANA             = "Mana",
UF_POWER_RAGE             = "Rage",
UF_POWER_FOCUS            = "Focus",
UF_POWER_ENERGY           = "Energy",

-- Printed on a unit frame in place of a disconnected member's health readout,
-- on a frame the module also fades. Keep it short: it shares the party health
-- bar with the member's level and name.
UF_OFFLINE                = "OFFLINE",

UF_PARTY_HEADER           = "Party Frames",
UF_PARTY_PETS             = "Show party member pets",
UF_POWER_TICK_HEADER      = "Player Power Tick",
UF_MANA_TICK              = "Show mana tick",
UF_ENERGY_TICK            = "Show energy tick",
UF_COMBO_POINTS_HEADER    = "Combo Points",
UF_COMBO_POINTS_PLAYER_FRAME = "Player frame",
UF_COMBO_POINTS_TARGET_FRAME = "Target frame",

-- Heal-over-time indicators on the party frames (modules/hots.lua). The client
-- reports no caster and no duration for another unit's buffs, so only the
-- player's own casts are tracked and a HoT that does not appear is a known
-- limit rather than a bug.
HOTS_HEADER               = "Party HoT Indicators",
HOTS_ENABLED              = "Show HoTs",
HOTS_CORNER               = "Corner",
HOTS_SIZE                 = "Icon size",
HOTS_SPACING              = "Icon spacing",
HOTS_CORNER_TOPLEFT       = "Top left",
HOTS_CORNER_TOPRIGHT      = "Top right",
HOTS_CORNER_BOTTOMLEFT    = "Bottom left",
HOTS_CORNER_BOTTOMRIGHT   = "Bottom right",
HEALPREDICT_HEADER        = "Incoming Heals",
HEALPREDICT_ENABLED       = "Show incoming heals on health bars",
HEALPREDICT_HINT          = "Paints the part of a health bar your heal is about to fill while it is still casting, so an overheal is visible before it is wasted. This client reports no incoming heals of its own, so only your own casts are shown, and a spell has to be seen land once before its amount is known. Other healers' heals never appear.",

AURAS_HEADER              = "Unit Frame Auras",
AURAS_ON_PLAYER_FRAME     = "Show auras on the player frame",
AURAS_NEAR_MINIMAP        = "Show auras near the minimap",
AURAS_PLAYER_DEBUFFS      = "Player frame debuffs",
AURAS_PLAYER_BUFFS        = "Player frame buffs",
AURAS_TARGET_DEBUFFS      = "Target frame debuffs",
AURAS_TARGET_BUFFS        = "Target frame buffs",
AURAS_PARTY_DEBUFFS       = "Party frame debuffs",
AURAS_PARTY_BUFFS         = "Party frame buffs",
AURAS_SHOW_TIMERS         = "Timers on aura icons",
AURAS_BELOW_FRAME         = "Player / target auras below frames",
AURAS_DISPEL_HEADER       = "Show Debuffs By Dispel Type",
AURAS_MAGIC               = "Magic",
AURAS_CURSE               = "Curse",
AURAS_POISON              = "Poison",
AURAS_DISEASE             = "Disease",
AURAS_OTHER               = "Physical / other",
AURAS_HINT                = "Only your own aura timers are exact. This client reports no duration for other units, so those are estimated from a spell table: an aura already running reads as fresh, and one the table omits shows no timer. Use /uui aura to see which.",

-- ---------------------------------------------------------------------------
-- Bags and bank (modules/bags.lua, modules/bank.lua)
-- ---------------------------------------------------------------------------
SETTINGS_BAGS_ENABLE      = "Enable",
SETTINGS_BAGS_ENABLE_HINT = "Replaces the client's bag windows with the merged UnrealUI bag. Unticking it stops the UnrealUI bag completely and gives the default client bags back, so another bag addon can take over without fighting it. Either change needs a reload.",
SETTINGS_BAGS_CHANGED     = "Bag interface changed",
SETTINGS_BAGS_RELOAD_ON   = "Type /reload to use the UnrealUI bag.",
SETTINGS_BAGS_RELOAD_OFF  = "Type /reload to return to the default client bags.",
SETTINGS_BAGS_CATEGORIES  = "Category-based bag view",
SETTINGS_BAGS_CATEGORIES_HINT = "Groups the bag contents into labelled category boxes instead of one flat grid. Categories come from the item's own class, so nothing has to be tagged or sorted by hand. Takes effect straight away; no reload needed.",

ITEM_CATEGORY_FAVORITE    = "Favorites",
ITEM_CATEGORY_GEAR        = "My Gear",
ITEM_CATEGORY_QUEST       = "Quest Items",
ITEM_CATEGORY_CONSUMABLE  = "Consumables",
ITEM_CATEGORY_FOOD        = "Food & Drink",
ITEM_CATEGORY_POTION      = "Potions",
ITEM_CATEGORY_BUFF        = "Buffs",
ITEM_CATEGORY_BANDAGE     = "Bandages",
ITEM_CATEGORY_EXPLOSIVE   = "Explosives",
ITEM_CATEGORY_REAGENT     = "Class Reagents",
ITEM_CATEGORY_TRADEGOODS  = "Trade Goods",
ITEM_CATEGORY_RECIPE      = "Recipes",
ITEM_CATEGORY_AMMO        = "Ammunition",
ITEM_CATEGORY_CONTAINER   = "Containers",
ITEM_CATEGORY_KEY         = "Keys",
ITEM_CATEGORY_JUNK        = "Junk",
ITEM_CATEGORY_MISC        = "Miscellaneous",
ITEM_CATEGORY_UNKNOWN     = "Uncategorized",

BAGS_TITLE                = "Bags",
BAGS_SLOT_COUNT           = "%d/%d",
BAGS_SORT                 = "Sort Bags",
BAGS_SORT_HINT            = "Rearranges your bags into category order. Special bags (herb, soul, enchanting, engineering, quivers) are left alone.",
BAGS_SORT_BUSY            = "Already sorting.",
BAGS_SORT_CURSOR          = "Put down the item on your cursor first.",
BAGS_SORT_DONE            = "Bags sorted.",
BAGS_SORT_NOTHING         = "Bags are already sorted.",
BAGS_SORT_FAILED          = "Sorting stopped: an item did not move. Nothing was lost.",
BAGS_TOGGLE_KEYRING       = "Toggle Keyring",
BAGS_KEYRING_HINT         = "Show the keyring.",
BAGS_TOGGLE_BAGS          = "Toggle Bags",
BAGS_BAG_SLOTS_HINT       = "Show the equipped bag slots.",
BAGS_VENDOR_GRAYS         = "Vendor / Delete Grays",
BAGS_GREYS_HINT           = "Sells grey items at an open vendor; otherwise asks to delete them.",
BAGS_PICK_LOCK            = "Pick Lock",
BAGS_PICK_LOCK_HINT       = "Activate Pick Lock, then click a locked box in the bags.",
BAGS_PICK_LOCK_ACTION_HINT = "Place Pick Lock on an action bar to use the bag shortcut.",
BAGS_DELETE_CONFIRM_ONE   = "Delete %d grey item?",
BAGS_DELETE_CONFIRM_OTHER = "Delete %d grey items?",
BAGS_SOLD_GREYS           = "Sold grey items for %s.",
BAGS_DELETED_GREYS_ONE    = "Deleted %d grey item.",
BAGS_DELETED_GREYS_OTHER  = "Deleted %d grey items.",
BAGS_NO_GREYS             = "No grey items found.",
BAGS_FAVORITE_HINT_ADD    = "Alt + Left Click: mark as favorite",
BAGS_FAVORITE_HINT_REMOVE = "Alt + Left Click: remove favorite",
BAGS_FAVORITE_SELL_CONFIRM = "Sell this favorite item?",
BAGS_FAVORITE_SELL_ACCEPT = "Sell",
BAGS_FAVORITE_BATCH_SELL_ONE   = "%d grey item is marked as a favorite.",
BAGS_FAVORITE_BATCH_SELL_OTHER = "%d grey items are marked as favorites.",
BAGS_FAVORITE_BATCH_DELETE_ONE   = "%d grey item is marked as a favorite.",
BAGS_FAVORITE_BATCH_DELETE_OTHER = "%d grey items are marked as favorites.",
BAGS_FAVORITE_BATCH_DETAIL = "Include them, or skip them and keep them in your bags?",
BAGS_FAVORITE_BATCH_INCLUDE = "Include",
BAGS_FAVORITE_BATCH_SKIP  = "Skip",
BAGS_FAVORITE_BATCH_NONE_LEFT = "Only favorite grey items were found; nothing was done.",
BANK_TITLE                = "Bank",
BANK_SORT                 = "Sort Bank",
BANK_SORT_HINT            = "Rearranges your bank and bank bags into category order. Special bags are left alone.",
BANK_SORT_BUSY            = "Already sorting.",
BANK_SORT_CURSOR          = "Put down the item on your cursor first.",
BANK_SORT_DONE            = "Bank sorted.",
BANK_SORT_NOTHING         = "Bank is already sorted.",
BANK_SORT_FAILED          = "Bank sorting stopped: an item did not move.",
BANK_BAG_LABEL            = "Bank Bag",
BANK_BUY_SLOT             = "Purchase another bank bag slot?",
BANK_PURCHASE             = "Purchase",
BANK_PURCHASE_TITLE       = "Purchase Bank Bag",
BANK_TRANSFER_PICKUP      = "Bank transfer stopped in your inventory; pick the item up again to continue.",
BANK_TRANSFER_EMPTY_SLOT  = "Moving items between bank bags needs a player-bag slot to pass through; none could be used.",
BANK_SLOT_TEMPLATE_FALLBACK = "%s is not available on this client; bank slots use the bag slot template instead.",
BANK_SLOTS_LOADING        = "The client has not reported the bank slots yet; retrying while the window is open.",

-- ---------------------------------------------------------------------------
-- Item comparison (modules/tooltip.lua)
-- ---------------------------------------------------------------------------
TOOLTIP_COMPARE_SUMMARY   = "If you replace this item :",

-- ---------------------------------------------------------------------------
-- Overlays and native screens
-- ---------------------------------------------------------------------------
STATUS_FPS                = "FPS:",
STATUS_LATENCY            = "MS:",
STATUS_DURABILITY         = "Durability:",
STATUS_TIME               = "Time:",
STATUS_ONLINE             = "online players",

WORLDMAP_CURSOR           = "Cursor: --, --",
WORLDMAP_CURSOR_OFF_MAP   = "Cursor: Off Map",
QUESTLOG_LEVELS           = "Levels",
SPELLBOOK_HIGHEST_RANK    = "Highest rank",
SPELLBOOK_HIGHEST_RANK_TOOLTIP = "Shows only the last rank of each spell.",
SPELLBOOK_BAR_HINT        = "Not on action bars",
SPELLBOOK_BAR_HINT_TOOLTIP = "Highlights spells not on action bars.",
GAMEMENU_OPTIONS          = "Options",

-- ---------------------------------------------------------------------------
-- Slash commands (core/commands.lua)
--
-- Only the player-facing surface is translated. The diagnostic dumps
-- (/uui np, aura, res, bindscan, keytest, perf, suppress) stay in English:
-- they are developer telemetry that gets pasted into a bug report.
-- ---------------------------------------------------------------------------
CMD_HEADER                = "v%s commands:",
CMD_SETTINGS              = "  |cffffff00/uui|r - open settings",
CMD_UNLOCK                = "  |cffffff00/uui unlock|r - unlock frames for moving",
CMD_LOCK                  = "  |cffffff00/uui lock|r - lock frames",
CMD_RESET                 = "  |cffffff00/uui reset|r - reset all frame positions",
CMD_BIND                  = "  |cffffff00/uui bind|r - open quick binding",
CMD_CHECK                 = "  |cffffff00/uui check|r - runtime self-check",
CMD_THEME                 = "  |cffffff00/uui theme <style>|r - select a theme (needs /reload)",
-- The argument list uses slashes, not pipes: a bare "|c" inside a chat string
-- is read as the start of a colour escape and would swallow the rest of it.
CMD_LANGUAGE              = "  |cffffff00/uui lang <en/cn/ru/fr>|r - select a language (needs /reload)",
CMD_PROFILE               = "  |cffffff00/uui profile create <name>|r - create and select a shared profile",
CMD_DEBUG                 = "  |cffffff00/uui debug|r - toggle debug output",
CMD_DIAGNOSTICS           = "  |cffffff00/uui help diag|r - list the diagnostic dumps",
CMD_UNKNOWN               = "unknown command: %s",
CMD_SETTINGS_UNAVAILABLE  = "settings interface is not available yet in this build.",
CMD_LANGUAGE_CURRENT      = "language: |cffffff00%s|r",
CMD_LANGUAGE_AVAILABLE    = "available languages:",
CMD_PROFILE_CURRENT       = "current profile: |cffffff00%s|r",
CMD_PROFILE_CREATE_USAGE  = "  |cffffff00/uui profile create <name>|r",
CMD_PROFILE_UNAVAILABLE   = "profile management is unavailable in this build",
CMD_PROFILE_EXISTS        = "a profile named |cffffff00%s|r already exists",
CMD_PROFILE_NAME_RULES    = "profile names may contain letters, numbers, spaces, hyphens and underscores (maximum 64 characters)",
CMD_PROFILE_CREATED       = "created and selected profile |cffffff00%s|r - |cffffff00/reload|r to apply it",

})
