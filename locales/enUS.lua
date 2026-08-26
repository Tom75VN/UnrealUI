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
MOVER_LABEL_XP_BAR        = "Experience Bar",
MOVER_LABEL_REP_BAR       = "Reputation Bar",
MOVER_LABEL_MICRO_BAR     = "Micro Bar",
MOVER_LABEL_MINIMAP       = "Minimap",
MOVER_LABEL_PET_BAR       = "Pet Bar",
MOVER_LABEL_STANCE_BAR    = "Stance Bar",
MOVER_LABEL_STATUS        = "Status Overlay",
MOVER_LABEL_ONLINE_COUNT  = "Online Count Overlay",
MOVER_LABEL_QUEST_TRACKER = "Quest Tracker",
MOVER_LABEL_BAGS          = "Bags",
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

SETTINGS_THEME_STYLE      = "Theme style",
SETTINGS_THEME_CHANGED    = "Theme changed",
SETTINGS_THEME_RELOAD     = "Type /reload to apply the %s theme.",
SETTINGS_THEME_HINT       = "Classic WoW restores the original native interface after a reload, keeping the UnrealUI and Quick Binding entries in the game menu. Modern WoW is still in development.",
SETTINGS_THEME_WIP        = " (WIP)",
SETTINGS_THEMES_AVAILABLE = "available themes:",

SETTINGS_QUICKBIND        = "Quick Binding",
SETTINGS_QUICKBIND_HINT   = "Hover an action bar slot and press a key to bind it. Escape over a slot clears it.",
SETTINGS_MICROBAR         = "Enable micro bar",
SETTINGS_MICROBAR_HINT    = "Pulls the native character/spellbook/talent/quest log/social/map/menu/help buttons into one movable row. Disabling returns them to their stock location.",
SETTINGS_REPUTATION_BAR   = "Show reputation bar",
SETTINGS_MINIMAP_BUTTON   = "Show minimap settings button",
SETTINGS_ZONE_LEVELS      = "Show zone level ranges on the world map",
SETTINGS_ZONE_LEVELS_HINT = "Hovering a zone on a continent map shows its level range beside the name: green below your level, orange at your level, red above your level.",

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
ABC_SHOW_GCD              = "Show global cooldown wipe",
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
UF_COLORS_HEADER          = "Unit Frame Colors",
UF_CUSTOM_BAR_COLORS      = "Use custom bar colors",
UF_HEALTH_BAR_COLOR       = "Health bar color",
UF_CLASS_COLORS           = "Use class colors for player health bars",
UF_POWER_BAR_COLORS       = "Power bar colors",
UF_POWER_MANA             = "Mana",
UF_POWER_RAGE             = "Rage",
UF_POWER_FOCUS            = "Focus",
UF_POWER_ENERGY           = "Energy",

UF_PARTY_HEADER           = "Party Frames",
UF_PARTY_PETS             = "Show party member pets",

AURAS_HEADER              = "Unit Frame Auras",
AURAS_PLAYER_DEBUFFS      = "Player frame debuffs",
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
AURAS_HINT                = "Your own auras are timed by the client and are exact. For any other unit this client reports no duration, so those timers are rebuilt from a spell duration table and the moment the aura was first seen: one already running when you target reads as fresh, and one the table does not list shows no timer. Use /uui aura to see which is which.",

-- ---------------------------------------------------------------------------
-- Pet bar (modules/petbar.lua)
-- ---------------------------------------------------------------------------
PETBAR_PAGE               = "Pet Bar",
PETBAR_BUTTONS_PER_ROW    = "Buttons Per Row",
PETBAR_BUTTON_SIZE        = "Button Size",
PETBAR_BUTTON_SPACING     = "Button Spacing",
PETBAR_AUTOCAST           = "Highlight auto-cast abilities",
PETBAR_HINT               = "Shown only while you have an active pet with its own action bar.",

-- ---------------------------------------------------------------------------
-- Bags and bank (modules/bags.lua, modules/bank.lua)
-- ---------------------------------------------------------------------------
BAGS_TITLE                = "Bags",
BAGS_TOGGLE_KEYRING       = "Toggle Keyring",
BAGS_KEYRING_HINT         = "Show the keyring.",
BAGS_TOGGLE_BAGS          = "Toggle Bags",
BAGS_BAG_SLOTS_HINT       = "Show the equipped bag slots.",
BAGS_VENDOR_GRAYS         = "Vendor / Delete Grays",
BAGS_GREYS_HINT           = "Sells grey items at an open vendor; otherwise asks to delete them.",
BAGS_DELETE_CONFIRM_ONE   = "Delete %d grey item?",
BAGS_DELETE_CONFIRM_OTHER = "Delete %d grey items?",
BAGS_SOLD_GREYS           = "Sold grey items for %s.",
BAGS_DELETED_GREYS_ONE    = "Deleted %d grey item.",
BAGS_DELETED_GREYS_OTHER  = "Deleted %d grey items.",
BAGS_NO_GREYS             = "No grey items found.",
BANK_TITLE                = "Bank",
BANK_BAG_LABEL            = "Bank Bag",
BANK_BUY_SLOT             = "Purchase another bank bag slot?",
BANK_PURCHASE             = "Purchase",
BANK_PURCHASE_TITLE       = "Purchase Bank Bag",
BANK_TRANSFER_PICKUP      = "Bank transfer stopped in your inventory; pick the item up again to continue.",
BANK_TRANSFER_EMPTY_SLOT  = "Moving items between bank bags needs one empty player-bag slot.",
BANK_SLOT_TEMPLATE_FALLBACK = "%s is not available on this client; bank slots use the bag slot template instead.",
BANK_SLOTS_LOADING        = "The client has not reported the bank slots yet; retrying while the window is open.",

-- ---------------------------------------------------------------------------
-- Overlays and native screens
-- ---------------------------------------------------------------------------
STATUS_FPS                = "FPS:",
STATUS_LATENCY            = "MS:",
STATUS_DURABILITY         = "Durability:",
STATUS_FACTION            = "Faction:",
STATUS_ONLINE             = "online",

WORLDMAP_CURSOR           = "Cursor: --, --",
WORLDMAP_CURSOR_OFF_MAP   = "Cursor: Off Map",
QUESTLOG_LEVELS           = "Levels",
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
