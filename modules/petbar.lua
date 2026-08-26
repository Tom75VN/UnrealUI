-- unrealUI :: modules/petbar.lua
--
-- A single pet action bar in the pfUI-modern button style shared with
-- modules/actionbar.lua: flat near-black square buttons, one thin outline,
-- the icon inset inside it. Pet action slots carry no keybind, macro name or
-- item count in Vanilla, so those corner labels are omitted entirely rather
-- than built and left empty. Only the look and the pet-specific call shapes
-- are taken from pfUI-modern; none of its bar architecture is reproduced.
--
-- Compatibility notes that shaped this file:
--
--   * query_compat.py has no compact record for GetPetActionInfo,
--     GetPetActionCooldown, CastPetAction, PickupPetAction, PetHasActionBar,
--     GetPetActionsUsable, IsPetAttackActive, PetStopAttack,
--     TogglePetAutocast, UNIT_PET or the PET_BAR_* events -- an evidence
--     gap, not a confirmed incompatibility. Every call shape below matches
--     UnrealPfUI's working modules/actionbar.lua pet-bar branch (bar == 12),
--     which is WORKING_SOURCE evidence only, not runtime-verified on this
--     client. Confirm the bar in game; if a call misbehaves, do not guess a
--     second variant blind -- collect a focused probe first and feed the
--     result back into knowledge.json.
--   * scripts.handler_arguments_direct: OnClick's mouse-button argument is
--     not guaranteed to arrive as a direct parameter here. ResolveClickButton
--     mirrors modules/unitframes.lua's own resolver rather than importing it,
--     since it is a three-line pure function local to each caller's frame.
--   * actionbars.native_stock_children_suppression: the stock pet bar and
--     its buttons need the same explicit suppress-and-reapply treatment as
--     the main action bars; kept local to this file since it only owns the
--     pet-bar native names, not modules/actionbar.lua's list.
--   * Cooldown display is the native swipe only (CooldownFrameTemplate), not
--     a numeric countdown: duplicating actionbar.lua's clock-wrap-corrected
--     countdown engine for a bar whose cooldowns are short and rarely cross
--     that edge case would be exactly the fragile emulation the project
--     guidance says to omit rather than build for feature-count parity.

local U = UnrealUI
local M = U.media

local PB = U.RegisterModule("petbar")

local ICON_INSET = 2

local LIMITS = {
  perRow  = { min = 1,  max = 10, step = 1 },
  size    = { min = 15, max = 60, step = 1 },
  spacing = { min = -3, max = 20, step = 1 },
}

local DEFAULTS = {
  enabled      = true,
  perRow       = 10,
  size         = 24,
  spacing      = 2,
  showAutocast = true,
}

local COLOR = {
  cooldown = { 1.00, 0.20, 0.20, 1.00 },
  active   = { 0.20, 1.00, 0.20, 1.00 },
  autocast = { 0.30, 0.75, 1.00, 1.00 },
}

local frame, buttons = nil, {}
local shown = false
local cfg
local slotCount = 10
local gridActive = false

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Resolved by name and pcall'd, same pattern as modules/actionbar.lua: a
-- missing call degrades one part of the bar rather than erroring the module.
-- ---------------------------------------------------------------------------
-- Memoized for the reason recorded in knowledge.json /
-- compat.native_suppression_pcall_burst_stutter: U.G is itself a pcall, so
-- resolving the name on every call doubled the cost of every read in the
-- recurring sweeps below.
local apiFnCache = {}

local function ResolveApiFn(name)
  local cached = apiFnCache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local fn = U.G(name)
  if type(fn) == "function" then
    apiFnCache[name] = fn
    return fn
  end
  apiFnCache[name] = false
  return nil
end

local function Call(name, a, b, c)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3
end

local function Has(name)
  return ResolveApiFn(name) and true or false
end

-- GetPetActionInfo returns seven values; the shared Call() above only
-- forwards three, so this gets its own fixed-arity wrapper instead of a
-- variadic one (the rest of this addon avoids `...` through pcall).
local function GetPetInfo(id)
  local fn = ResolveApiFn("GetPetActionInfo")
  if not fn then return nil end
  local ok, name, subtext, texture, token, active, castable, autocast =
    pcall(fn, id)
  if not ok then return nil end
  return name, subtext, texture, token, active, castable, autocast
end

local function Clamp(name, value)
  local limit = LIMITS[name]
  value = tonumber(value)
  if not limit then return value end
  if not value then return limit.min end
  value = U.Round(value)
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return value
end

local function Number(name)
  if not cfg then return LIMITS[name] and LIMITS[name].min or 0 end
  return Clamp(name, cfg[name])
end

local function IsEnabled()
  return cfg and cfg.enabled and true or false
end

-- query_compat.py: PetHasActionBar has no compact record. UnitExists("pet")
-- is the fallback proxy if this client does not expose it at all.
local function HasPetBar()
  if Has("PetHasActionBar") then return Call("PetHasActionBar") and true or false end
  return Call("UnitExists", "pet") and true or false
end

-- Mirrors modules/unitframes.lua's ResolveClickButton: try direct OnClick
-- arguments first, then the legacy `arg1` global.
local function ResolveClickButton(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  return U.G("arg1")
end

local function CursorHoldsAction()
  if gridActive then return true end
  if Call("CursorHasItem") then return true end
  if Call("CursorHasSpell") then return true end
  if Call("CursorHasMacro") then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
local function ApplyBorder(button)
  if button.uuiCdActive then
    U.SetBorderColor(button, COLOR.cooldown[1], COLOR.cooldown[2], COLOR.cooldown[3], 1)
  elseif button.uuiActive then
    U.SetBorderColor(button, COLOR.active[1], COLOR.active[2], COLOR.active[3], 1)
  elseif button.uuiAutocast and cfg and cfg.showAutocast then
    U.SetBorderColor(button, COLOR.autocast[1], COLOR.autocast[2], COLOR.autocast[3], 1)
  else
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end
end

local function OnButtonClick(button, a, b)
  local mouseButton = ResolveClickButton(a, b)

  if CursorHoldsAction() then
    Call("PickupPetAction", button.uuiIndex)
    return
  end

  if mouseButton == "RightButton" then
    Call("TogglePetAutocast", button.uuiIndex)
    return
  end

  if Call("IsPetAttackActive", button.uuiIndex) then
    Call("PetStopAttack")
  else
    Call("CastPetAction", button.uuiIndex)
  end
end

-- pfUI's working pet-bar branch calls PickupPetAction on both drag start and
-- receive drag (unlike normal actions, which pair PickupAction/PlaceAction).
local function OnButtonDrag(button)
  Call("PickupPetAction", button.uuiIndex)
end

-- GetPetActionInfo's isToken flag marks the three fixed actions (Attack,
-- Follow, Stay): the working pfUI path reads their display name through a
-- second _G lookup rather than the plain string it returns for an actual pet
-- ability. Reproduced as-is; see the WORKING_SOURCE note in the file header.
local function ShowTooltip(button)
  local tooltip = U.G("GameTooltip")
  if not tooltip then return end
  pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
  pcall(tooltip.ClearLines, tooltip)

  local name, _, _, token = GetPetInfo(button.uuiIndex)
  if token and type(name) == "string" then
    pcall(tooltip.AddLine, tooltip, U.G(name))
    pcall(tooltip.Show, tooltip)
  elseif type(tooltip.SetPetAction) == "function" then
    if not pcall(tooltip.SetPetAction, tooltip, button.uuiIndex) then
      pcall(tooltip.Hide, tooltip)
    end
  end
end

local function HideTooltip()
  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end
end

local function CreateButton(index)
  local name = "UnrealUIPetBarButton" .. index
  local button = CreateFrame("Button", name, frame)
  button.uuiIndex = index

  U.CreateBackdrop(button, {})
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")
  pcall(button.RegisterForDrag, button, "LeftButton", "RightButton")

  local icon = button:CreateTexture(nil, "ARTWORK")
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  button.uuiIcon = icon

  -- Same Model-frame cooldown swipe as modules/actionbar.lua; see that file's
  -- header note for why this is the native Vanilla-shaped primitive rather
  -- than a synthetic overlay.
  local ok, cooldown = pcall(CreateFrame, "Model", name .. "Cooldown", button,
                             "CooldownFrameTemplate")
  if ok and cooldown and Has("CooldownFrame_SetTimer") then
    pcall(cooldown.SetAllPoints, cooldown, button)
    button.uuiCooldown = cooldown
  end

  button:SetScript("OnClick", function(a, b) OnButtonClick(button, a, b) end)
  button:SetScript("OnDragStart", function() OnButtonDrag(button) end)
  button:SetScript("OnReceiveDrag", function() OnButtonDrag(button) end)
  button:SetScript("OnEnter", function()
    button.uuiHover = true
    ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    button.uuiHover = false
    HideTooltip()
  end)

  return button
end

local function SizeButton(button, size)
  button:SetWidth(size)
  button:SetHeight(size)
  button.uuiIcon:ClearAllPoints()
  button.uuiIcon:SetPoint("TOPLEFT", button, "TOPLEFT", ICON_INSET, -ICON_INSET)
  button.uuiIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
end

local function HideButton(button)
  if button.uuiIcon then button.uuiIcon:Hide() end
  button.uuiCdActive = false
  if button.uuiCooldown then pcall(button.uuiCooldown.Hide, button.uuiCooldown) end
  button:Hide()
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local function UpdateSlot(button)
  local name, _, texture, token, active, castable, autocast =
    GetPetInfo(button.uuiIndex)

  if token and type(texture) == "string" then texture = U.G(texture) end

  if type(texture) == "string" and texture ~= "" then
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    button.uuiIcon:Show()
  else
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    button.uuiIcon:Hide()
  end

  local usable = true
  if Has("GetPetActionsUsable") then
    usable = Call("GetPetActionsUsable") and true or false
  end
  pcall(button.uuiIcon.SetDesaturated, button.uuiIcon, not usable)

  button.uuiActive = active and true or false
  button.uuiAutocast = autocast and true or false
  ApplyBorder(button)
end

local function UpdateCooldown(button)
  local start, duration, enable = Call("GetPetActionCooldown", button.uuiIndex)
  start = tonumber(start) or 0
  duration = tonumber(duration) or 0

  if button.uuiCooldown then
    local fn = ResolveApiFn("CooldownFrame_SetTimer")
    if fn then
      pcall(fn, button.uuiCooldown, start, duration, tonumber(enable) or 1)
    end
  end

  button.uuiCdActive = (start > 0 and duration > 0) and true or false
  ApplyBorder(button)
end

local function FullUpdate(button)
  UpdateSlot(button)
  UpdateCooldown(button)
end

local function ForEachButton(callback)
  -- /uui perf petbar. Both recurring sweeps walk the buttons through here.
  if U.PerfDisabled and U.PerfDisabled("petbar") then return end
  if not shown then return end
  local i
  for i = 1, table.getn(buttons) do callback(buttons[i]) end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local function CreateBar()
  frame = CreateFrame("Frame", "UnrealUIPetBar", UIParent)
  -- Match the main action bars: the persistent pet HUD must stay below
  -- overlapping native interface windows.
  pcall(frame.SetFrameStrata, frame, "LOW")
  frame:SetWidth(100)
  frame:SetHeight(30)

  local i
  for i = 1, slotCount do buttons[i] = CreateButton(i) end

  U.RegisterMover("petbar", frame, {
    label = U.L("MOVER_LABEL_PET_BAR"),
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 64 },
    visible = function() return IsEnabled() end,
  })
end

local function Layout()
  if not frame then return end

  -- A bar that only exists while it has an active pet could never be dragged
  -- into place: modules/castbar.lua and modules/unitframes.lua force the same
  -- kind of conditional frame shown (with an idle placeholder) while the UI
  -- is unlocked, and the mover handle -- a child of this frame -- only
  -- renders while its parent is shown, so this bar needs the same rule.
  local visible = IsEnabled() and (HasPetBar() or U.IsUnlocked())
  local perRow = Number("perRow")
  local size = Number("size")
  local spacing = Number("spacing")

  if perRow > slotCount then perRow = slotCount end
  local rows = math.ceil(slotCount / perRow)

  frame:SetWidth(perRow * size + (perRow - 1) * spacing)
  frame:SetHeight(rows * size + (rows - 1) * spacing)

  local i
  for i = 1, slotCount do
    local button = buttons[i]
    if visible then
      local row = math.floor((i - 1) / perRow)
      local column = (i - 1) - row * perRow

      SizeButton(button, size)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame, "TOPLEFT",
                      column * (size + spacing), -row * (size + spacing))
      button:Show()
      FullUpdate(button)
    else
      HideButton(button)
    end
  end

  shown = visible
  if visible then frame:Show() else frame:Hide() end
end

local function Apply()
  if not frame then
    if not IsEnabled() then return end
    CreateBar()
  end
  Layout()
end

-- ---------------------------------------------------------------------------
-- Native bar
-- ---------------------------------------------------------------------------
local NATIVE_PARTS = {
  "Icon", "NormalTexture", "NormalTexture2", "HotKey", "Count",
  "Border", "Cooldown", "Flash", "Name", "AutoCast", "AutoCastable",
}

local function SuppressNativeBar()
  local names = { "PetActionBarFrame" }
  local i, j
  for i = 1, slotCount do
    local base = "PetActionButton" .. i
    table.insert(names, base)
    for j = 1, table.getn(NATIVE_PARTS) do
      table.insert(names, base .. NATIVE_PARTS[j])
    end
  end
  U.SuppressNativeFrame(names, "petbar")
end

-- ---------------------------------------------------------------------------
-- Public API (settings tab)
-- ---------------------------------------------------------------------------
function U.PetBarLimits(name)
  local limit = LIMITS[name]
  if not limit then return nil end
  return limit.min, limit.max, limit.step
end

function U.GetPetBarSetting(name)
  if not cfg then return nil end
  if name == "enabled" or name == "showAutocast" then return cfg[name] and true or false end
  return Number(name)
end

function U.SetPetBarSetting(name, value)
  if not cfg then return nil end
  if name == "enabled" or name == "showAutocast" then
    cfg[name] = value and true or false
  else
    if not LIMITS[name] then return nil end
    cfg[name] = Clamp(name, value)
  end
  Apply()
  return U.GetPetBarSetting(name)
end

-- ---------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------
local PAGE_WIDTH = 484
local SLIDERS = {
  { key = "perRow",  textKey = "PETBAR_BUTTONS_PER_ROW" },
  { key = "size",    textKey = "PETBAR_BUTTON_SIZE" },
  { key = "spacing", textKey = "PETBAR_BUTTON_SPACING" },
}

local function BuildSettingsPage(parent)
  local widgets, controls = {}, {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("PETBAR_PAGE"), width = PAGE_WIDTH, y = -4,
  })
  table.insert(widgets, header)

  local enable = U.CreateCheckbox(parent, {
    name = "UnrealUIPetBarConfigEnable",
    text = U.L("COMMON_ENABLE"),
    value = U.GetPetBarSetting("enabled"),
    onChange = function(value) U.SetPetBarSetting("enabled", value) end,
  })
  enable.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, enable)

  local autocast = U.CreateCheckbox(parent, {
    name = "UnrealUIPetBarConfigAutocast",
    text = U.L("PETBAR_AUTOCAST"),
    value = U.GetPetBarSetting("showAutocast"),
    onChange = function(value) U.SetPetBarSetting("showAutocast", value) end,
  })
  autocast.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -58)
  table.insert(widgets, autocast)

  local i
  for i = 1, table.getn(SLIDERS) do
    local spec = SLIDERS[i]
    local min, max, step = U.PetBarLimits(spec.key)

    local slider = U.CreateSlider(parent, {
      name = "UnrealUIPetBarConfig" .. spec.key,
      text = U.L(spec.textKey),
      width = 200,
      min = min, max = max, step = step,
      value = U.GetPetBarSetting(spec.key),
      onChange = function(value) U.SetPetBarSetting(spec.key, value) end,
    })
    slider.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -102 - (i - 1) * 44)

    controls[spec.key] = slider
    table.insert(widgets, slider)
  end

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small, color = M.color.textDim,
    inherits = "GameFontNormalSmall", justify = "LEFT",
  })
  if hint then
    local finalSlider = controls[SLIDERS[table.getn(SLIDERS)].key]
    U.AnchorSettingsDescription(hint, finalSlider.box,
                                -math.floor((finalSlider.width - finalSlider.boxWidth) / 2))
    hint:SetText(U.L("PETBAR_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    enable.SetValue(U.GetPetBarSetting("enabled"))
    autocast.SetValue(U.GetPetBarSetting("showAutocast"))
    local j
    for j = 1, table.getn(SLIDERS) do
      local key = SLIDERS[j].key
      if controls[key] then controls[key].SetValue(U.GetPetBarSetting(key)) end
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Events and refresh
-- ---------------------------------------------------------------------------
local function RegisterEvents()
  U.RegisterEvent("UNIT_PET", function(event, unit)
    if not unit or unit == "player" then Apply() end
  end)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() Apply() end)
  U.RegisterEvent("PET_BAR_UPDATE", function() ForEachButton(UpdateSlot) end)
  U.RegisterEvent("PET_BAR_UPDATE_COOLDOWN", function() ForEachButton(UpdateCooldown) end)
  U.RegisterEvent("PET_BAR_SHOWGRID", function() gridActive = true end)
  U.RegisterEvent("PET_BAR_HIDEGRID", function() gridActive = false end)
end

function PB:OnInit()
  slotCount = tonumber(U.G("NUM_PET_ACTION_SLOTS")) or 10
  cfg = U.ModuleConfig("petbar", DEFAULTS)

  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("petbar", U.L("PETBAR_PAGE"), BuildSettingsPage, {
      parent = "actionbars",
      after = "actionbars.general",
    })
  end
end

function PB:OnEnable()
  if not cfg then cfg = U.ModuleConfig("petbar", DEFAULTS) end
  if not slotCount or slotCount < 1 then slotCount = 10 end

  SuppressNativeBar()
  Apply()
  RegisterEvents()

  -- Two rates, same reasoning as modules/actionbar.lua: state (cooldown/
  -- active/autocast border) is what the eye tracks and ticks faster; the full
  -- slot contents + visibility sweep is the low-frequency safety net that
  -- catches anything the accelerator events above missed.
  U.RegisterUpdate("petbar.cooldown", 0.5, function() ForEachButton(UpdateCooldown) end)
  -- Faster than modules/actionbar.lua's equivalent sweep: this one also
  -- catches a pet summon/dismiss and an edit-mode lock/unlock, both of which
  -- should not take up to 2 seconds to show or hide the bar/handle.
  U.RegisterUpdate("petbar.slots", 0.5, function() Apply() end)
end

-- Reported by /uui check.
function U.PetBarReport()
  return {
    enabled = IsEnabled(),
    hasPetBar = HasPetBar(),
    created = frame and true or false,
    shown = shown,
    slotCount = slotCount,
    perRow = Number("perRow"),
    size = Number("size"),
    spacing = Number("spacing"),
  }
end
