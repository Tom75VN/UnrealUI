-- unrealUI :: modules/auras.lua
--
-- Debuff icons above the player and target unit frames, plus the "Unit Frames"
-- settings page that filters what they show.
--
-- Scope: debuffs only, on player and target only. Buffs, party/raid auras,
-- aura timers, aura tooltips, weapon enchants and pfUI's whole buff/debuff
-- module framework are not reproduced here.
--
-- ---------------------------------------------------------------------------
-- The measured contract this file is built on
-- ---------------------------------------------------------------------------
--
-- knowledge.json / auras.unitbuff_unitdebuff_contract_unverified (PARTIAL,
-- RUNTIME_MEASURED, probe auras.* v1.10.0): on this client
--
--     UnitDebuff(unit, index) -> texture, count, debuffType
--
-- and nothing else. Three values, measured with a warlock Immolate live on the
-- target: texture="/Game/Interface/Icons/Spell_Fire_Immolation_TEX", count=1,
-- debuffType="Magic". There is no name, no duration, no timeLeft and no caster
-- return on this runtime -- that is true Vanilla 1.12 shape, not the extended
-- tuple pfUI's own code reads, which comes from its separate libdebuff
-- GameTooltip wrapper rather than from raw UnitDebuff.
--
-- Two consequences drive the whole design:
--
--   * No timers. Without duration or timeLeft there is nothing to count down
--     from, so no cooldown swipe and no remaining-time text are drawn. Building
--     one from a guessed duration table would be exactly the fragile emulation
--     the project rules say to omit.
--   * No "DoT only" filter is possible. The client does not report whether a
--     debuff deals damage over time; debuffType is the dispel school (Magic /
--     Curse / Poison / Disease, or nil for physical effects), which is a
--     different axis entirely -- Corruption and Curse of Weakness are both
--     "Curse". So the row shows every debuff and the settings page filters by
--     the one property the client does report.
--
-- The empty-index shape was measured too: an unused slot returns nil as its
-- first value (with 0 as the second), and the first probe run -- taken with no
-- debuff live -- returned nothing at all across 24 indices, confirming these
-- are read live per call and never latched from the aura event.
--
-- Other compatibility notes that shaped this file:
--
--   * events.json: UNIT_AURA is observed on this client, PLAYER_AURAS_CHANGED
--     was accepted but never seen firing. UNIT_AURA is therefore an
--     accelerator, and the shared polling tick is the mechanism -- the same
--     split modules/unitframes.lua uses for target-of-target.
--   * knowledge.json / scripts.child_onupdate_unreliable: no frame here owns an
--     OnUpdate. Refreshes run on U.RegisterUpdate.
--   * The icons are deliberately not mouse-interactive (no tooltip on hover).
--     UnitDebuff already gives no name, so a tooltip would have nothing more
--     to show than the icon already does; not a workaround for a client bug --
--     knowledge.json / tooltip.core_population_contract_unverified is
--     SUPPORTED/BEHAVIOR_VERIFIED, GameTooltip itself works fine here.
--   * knowledge.json / config.savedvariables_backslash_corruption: only
--     numbers and booleans are persisted. The icon path is never stored -- it
--     comes back from the client on every read.

local U = UnrealUI
local M = U.media

local A = U.RegisterModule("auras")

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local CONFIG = "auras"

local defaults = {
  playerEnabled = true,
  targetEnabled = true,
  belowFrame    = false,
  size          = 20,
  perRow        = 8,
  maxIcons      = 16,
  spacing       = 2,
  -- Filters, keyed by the dispel school the client reports. "other" covers a
  -- nil debuffType, which is what physical effects (Rend, Sunder Armor,
  -- stuns) come back as.
  showMagic     = true,
  showCurse     = true,
  showPoison    = true,
  showDisease   = true,
  showOther     = true,
}

local function Config()
  return U.ModuleConfig(CONFIG, defaults)
end

function U.GetAuraSetting(key)
  local value = Config()[key]
  if value == nil then return defaults[key] end
  return value
end

-- ---------------------------------------------------------------------------
-- Debuff colours
--
-- The border carries the dispel school, which is the only classification the
-- client actually reports. These are the stock Vanilla DebuffTypeColor values;
-- they are hardcoded rather than read from the global because query_compat.py
-- has no record of DebuffTypeColor existing on this client, and a missing
-- global would leave every icon unbordered.
-- ---------------------------------------------------------------------------
local TYPE_COLOR = {
  Magic   = { 0.20, 0.60, 1.00, 1.00 },
  Curse   = { 0.60, 0.00, 1.00, 1.00 },
  Poison  = { 0.00, 0.60, 0.00, 1.00 },
  Disease = { 0.60, 0.40, 0.00, 1.00 },
}

-- Physical/unclassified effects. Kept distinct from M.color.border so an
-- unfiltered row still reads as "these are debuffs" at a glance.
local OTHER_COLOR = { 0.70, 0.15, 0.15, 1.00 }

local FILTER_KEY = {
  Magic   = "showMagic",
  Curse   = "showCurse",
  Poison  = "showPoison",
  Disease = "showDisease",
}

local function TypeColor(debuffType)
  return TYPE_COLOR[debuffType] or OTHER_COLOR
end

local function PassesFilter(debuffType)
  local key = FILTER_KEY[debuffType] or "showOther"
  return U.GetAuraSetting(key) and true or false
end

-- ---------------------------------------------------------------------------
-- API access
--
-- Same defensive shape as modules/unitframes.lua: resolved once by name,
-- pcall'd on every call, and every value coerced. The measured tuple is
-- (texture, count, debuffType), but an unexpected return degrades to "no
-- debuff here" instead of erroring.
-- ---------------------------------------------------------------------------
local debuffFn = nil
local debuffResolved = false

local function ReadDebuff(unit, index)
  if not debuffResolved then
    local fn = U.G("UnitDebuff")
    debuffFn = type(fn) == "function" and fn or false
    debuffResolved = true
  end
  if not debuffFn then return nil end

  local ok, texture, count, debuffType = pcall(debuffFn, unit, index)
  if not ok or type(texture) ~= "string" or texture == "" then return nil end

  return texture, tonumber(count) or 0,
         (type(debuffType) == "string" and debuffType ~= "" ) and debuffType or nil
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------
-- How far to walk before giving up on a unit. Vanilla indices are contiguous,
-- but that is not verified here (the probe only ever had one debuff live), so
-- the walk tolerates a single gap and stops on two consecutive empty slots --
-- the same heuristic the probe itself used.
local MAX_SCAN = 24
local EMPTY_STOP = 2

-- Gap between the row and the unit frame edge it is anchored to, on either
-- side (above or below).
local ROW_GAP = 4

local rows = {}   -- unit id -> row frame

local function CreateIcon(row, index)
  local size = U.GetAuraSetting("size")

  local icon = CreateFrame("Frame", "UnrealUIAura" .. row.id .. index, row)
  icon:SetWidth(size)
  icon:SetHeight(size)
  U.CreateBackdrop(icon, {})

  -- Deliberately inert: no EnableMouse, no tooltip. See the GameTooltip note in
  -- the file header.
  local texture = icon:CreateTexture(nil, "ARTWORK")
  texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
  texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  -- Trims the stock icon border the same way modules/actionbar.lua does, so the
  -- unrealUI outline is the only edge on screen.
  pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
  icon.texture = texture

  -- fonts.stretched_justification_ignored: anchored to the one corner it
  -- belongs in rather than stretched across the icon.
  icon.count = U.CreateLabel(icon, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if icon.count then
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  end

  icon:Hide()
  row.icons[index] = icon
  return icon
end

-- Places one icon in the grid. The near row always sits against the frame
-- edge closest to it (top edge when shown above, bottom edge when shown
-- below) and further rows stack away from the frame, so that edge stays put
-- no matter how many debuffs are up.
local function PlaceIcon(row, icon, slot, size, spacing, perRow, below)
  local column = math.mod(slot - 1, perRow)
  local line = math.floor((slot - 1) / perRow)

  icon:ClearAllPoints()
  if below then
    icon:SetPoint("TOPLEFT", row, "TOPLEFT",
                  column * (size + spacing),
                  -line * (size + spacing))
  else
    icon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",
                  column * (size + spacing),
                  line * (size + spacing))
  end
end

-- Anchors the row itself to the frame edge matching the current position
-- setting. Re-run every refresh (cheap, same pattern as the geometry reads
-- below) so a mid-session setting change takes effect without a reload.
local function PositionRow(row, below)
  row:ClearAllPoints()
  if below then
    row:SetPoint("TOPLEFT", row.anchor, "BOTTOMLEFT", 0, -ROW_GAP)
  else
    row:SetPoint("BOTTOMLEFT", row.anchor, "TOPLEFT", 0, ROW_GAP)
  end
end

local function ApplyIcon(icon, texture, count, debuffType, size)
  icon:SetWidth(size)
  icon:SetHeight(size)

  pcall(icon.texture.SetTexture, icon.texture, texture)
  U.SetBorderColor(icon, M.Unpack(TypeColor(debuffType)))

  -- A stack of 1 is the normal case and the number would just be noise.
  if icon.count then
    if count and count > 1 then
      icon.count:SetText(tostring(count))
      icon.count:Show()
    else
      icon.count:SetText("")
      icon.count:Hide()
    end
  end

  icon:Show()
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function RefreshRow(row)
  if not row then return end

  local settings = Config()
  local enabled = row.id == "player" and settings.playerEnabled
                                     or settings.targetEnabled

  local exists = false
  local existsFn = U.G("UnitExists")
  if type(existsFn) == "function" then
    local ok, value = pcall(existsFn, row.unit)
    exists = ok and value and value ~= 0 and true or false
  end

  if not enabled or not exists then
    local i
    for i = 1, table.getn(row.icons) do row.icons[i]:Hide() end
    row:Hide()
    return
  end

  local size = U.GetAuraSetting("size")
  local spacing = U.GetAuraSetting("spacing")
  local perRow = U.GetAuraSetting("perRow")
  local maxIcons = U.GetAuraSetting("maxIcons")
  local below = U.GetAuraSetting("belowFrame")

  PositionRow(row, below)

  local shown, empty, index = 0, 0, nil
  for index = 1, MAX_SCAN do
    local texture, count, debuffType = ReadDebuff(row.unit, index)

    if not texture then
      empty = empty + 1
      if empty >= EMPTY_STOP then break end
    else
      empty = 0
      if PassesFilter(debuffType) then
        shown = shown + 1
        local icon = row.icons[shown] or CreateIcon(row, shown)
        PlaceIcon(row, icon, shown, size, spacing, perRow, below)
        ApplyIcon(icon, texture, count, debuffType, size)
        if shown >= maxIcons then break end
      end
    end
  end

  local i
  for i = shown + 1, table.getn(row.icons) do row.icons[i]:Hide() end

  if shown > 0 then
    local lines = math.floor((shown - 1) / perRow) + 1
    local columns = shown < perRow and shown or perRow
    row:SetWidth(columns * (size + spacing))
    row:SetHeight(lines * (size + spacing))
    row:Show()
  else
    row:Hide()
  end
end

local function RefreshAll()
  RefreshRow(rows.player)
  RefreshRow(rows.target)
end

-- Only the row whose unit changed, when the event carries a usable token.
local function RefreshUnitToken(token)
  if type(token) ~= "string" then
    RefreshAll()
    return
  end
  if rows[token] then RefreshRow(rows[token]) end
end

-- Called by the settings page after any option changes: geometry and filters
-- both take effect on the next refresh, so this is just an immediate one.
function U.ApplyAuras()
  RefreshAll()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildRow(id, unit)
  local anchor = U.GetUnitFrame(id)
  if not anchor then
    U.Debug("no unit frame to anchor auras to: " .. id)
    return nil
  end

  -- A plain Frame, not a Button: nothing here takes mouse input, and the row
  -- rides the unit frame's mover rather than owning one of its own, so the
  -- icons cannot drift away from the frame they describe.
  local row = CreateFrame("Frame", "UnrealUIAuraRow" .. id, anchor)
  row.anchor = anchor
  row:SetWidth(1)
  row:SetHeight(1)
  PositionRow(row, U.GetAuraSetting("belowFrame"))

  row.id = id
  row.unit = unit
  row.icons = {}
  row:Hide()

  rows[id] = row
  return row
end

-- ---------------------------------------------------------------------------
-- Settings page
--
-- One top-level "Unit Frames" page, per request. It is not a config framework:
-- the checkboxes read and write the module's own settings table directly, the
-- same way modules/actionbarconfig.lua does.
--
-- Icon size/per-row/max-icons/spacing are deliberately not exposed here --
-- there is no user-facing control for them, only the fixed defaults above.
-- ---------------------------------------------------------------------------
local PAGE_WIDTH = 484
local FILTER_COLUMN_X = 200

local TOGGLES = {
  { key = "playerEnabled", text = "Show player frame debuffs" },
  { key = "targetEnabled", text = "Show target frame debuffs" },
  { key = "belowFrame",    text = "Show debuffs below the frame instead of above" },
}

-- Laid out 2 per row (column, row) so the list reads as a table instead of a
-- single tall column.
local FILTERS = {
  { key = "showMagic",   text = "Magic",           column = 0, row = 0 },
  { key = "showCurse",   text = "Curse",           column = 1, row = 0 },
  { key = "showPoison",  text = "Poison",          column = 0, row = 1 },
  { key = "showDisease", text = "Disease",         column = 1, row = 1 },
  { key = "showOther",   text = "Physical / other", column = 0, row = 2 },
}

local function BuildSettingsPage(parent)
  local widgets = {}
  local controls = {}

  local header = U.CreateSectionHeader(parent, {
    text = "Unit Frame Debuffs",
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local i
  for i = 1, table.getn(TOGGLES) do
    local spec = TOGGLES[i]
    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIAuraToggle" .. spec.key,
      text = spec.text,
      value = U.GetAuraSetting(spec.key),
      onChange = function(value)
        Config()[spec.key] = value
        U.ApplyAuras()
      end,
    })
    check.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34 - (i - 1) * 26)
    controls[spec.key] = check
    table.insert(widgets, check)
  end

  local filterHeader = U.CreateSectionHeader(parent, {
    text = "Show By Dispel Type",
    width = PAGE_WIDTH,
    y = -128,
  })
  table.insert(widgets, filterHeader)

  for i = 1, table.getn(FILTERS) do
    local spec = FILTERS[i]
    local check = U.CreateCheckbox(parent, {
      name = "UnrealUIAuraFilter" .. spec.key,
      text = spec.text,
      textWidth = FILTER_COLUMN_X - 26,
      value = U.GetAuraSetting(spec.key),
      onChange = function(value)
        Config()[spec.key] = value
        U.ApplyAuras()
      end,
    })
    check.SetPoint("TOPLEFT", parent, "TOPLEFT",
                   spec.column * FILTER_COLUMN_X, -158 - spec.row * 26)
    controls[spec.key] = check
    table.insert(widgets, check)
  end

  -- States plainly what the client does and does not report, so the missing
  -- "DoTs only" option reads as a measured limit rather than an oversight.
  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
    height = 40,
  })
  if hint then
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -244)
    hint:SetText("This client reports only icon, stack count and dispel type " ..
                 "per debuff -- no duration and no caster -- so debuffs are " ..
                 "filtered by dispel type and shown without timers.")
    table.insert(widgets, hint)
  end

  local function Refresh()
    local key, control
    for key, control in pairs(controls) do
      control.SetValue(U.GetAuraSetting(key))
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function A:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("unitframes", "Unit Frames", BuildSettingsPage)
  end
end

function A:OnEnable()
  BuildRow("player", "player")
  BuildRow("target", "target")

  if not rows.player and not rows.target then
    U.Error("aura rows could not be anchored; unit frames are unavailable")
    return
  end

  -- UNIT_AURA is the one aura event observed firing on this client
  -- (events.json); PLAYER_AURAS_CHANGED registered but was never seen, so it is
  -- registered as a free accelerator rather than relied on.
  U.RegisterEvent("UNIT_AURA", function(event, unit) RefreshUnitToken(unit) end)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", function() RefreshAll() end)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", function() RefreshRow(rows.target) end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() RefreshAll() end)

  -- The mechanism, not an optimisation: with no duration return there is
  -- nothing to expire an icon locally, so a debuff that falls off is only
  -- noticed by re-reading. 0.2s matches the unit frame tick.
  U.RegisterUpdate("auras.refresh", 0.2, function() RefreshAll() end)

  RefreshAll()
end
