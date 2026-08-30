-- unrealUI :: modules/stancebar.lua
--
-- The class stance bar the client draws for a Warrior (Battle/Defensive/
-- Berserker Stance) and for a Rogue (Stealth), rebuilt as an unrealUI bar with
-- its own mover. It follows the active theme exactly as the action bars do:
-- Modern draws the flat unrealUI button, Classic borrows the live client's own
-- action-button faces through modules/actionbar.lua's shared Classic helpers,
-- so a stance button always matches the action buttons sitting next to it.
--
-- The class list is deliberate, per .claude/rules/unreal-ui.md ("a feature
-- existing in pfUI is not sufficient reason to add it to UnrealUI"): only the
-- classes actually asked for get a bar. For every other class this module
-- creates nothing, suppresses nothing and registers no mover, so the client's
-- own shapeshift bar is left exactly as it is.
--
-- Compatibility notes that shaped this file:
--
--   * documentation.json: GetNumShapeshiftForms(), CastShapeshiftForm(id) and
--     GetShapeshiftFormCooldown(id) -> start, duration, enable are
--     OFFICIAL_CLIENT_DOCUMENTATION / DOCUMENTED_NOT_RUNTIME_VERIFIED.
--     GetShapeshiftFormInfo(id) -> texture, name, isActive, isCastable is the
--     same class of evidence, and its return order matches UnrealPfUI's
--     working bar-11 branch (modules/actionbar.lua:608,718,787) --
--     WORKING_SOURCE agreement, not runtime-verified on this client.
--   * documentation.json / global:Spell:CastShapeshiftForm records the call
--     as "Not protected", and that pressing an already-active form cancels it
--     -- except the non-toggleable warrior stances, which no-op. That is the
--     native Stealth toggle, so the Rogue bar needs no separate cancel route.
--     (Contrast modules/petbar.lua, where the equivalent pet call *is*
--     documented protected, which is why that bar was given back to the
--     client instead of being rebuilt.)
--   * knowledge.json / actionbars.bonus_page_static_bar_alias, BEHAVIOR_
--     VERIFIED on a Rogue in game: entering Stealth pages the main bar to
--     bonus page 7. That belongs to modules/actionbar.lua and stays there --
--     this bar only casts the form, and never touches an action page.
--   * behavior.json / actionpaging.eventRegistration: UPDATE_SHAPESHIFT_FORM
--     and PLAYER_AURAS_CHANGED both registered without error on this client
--     (RUNTIME evidence, from a probe run on a Rogue; no form data of its own
--     was captured, and nothing was captured on a Warrior). UPDATE_SHAPESHIFT_
--     FORMS (plural) is UnrealPfUI's own event for this same bar
--     (modules/actionbar.lua:1447) with no compact record here; kept as a
--     third, harmless accelerator. The periodic slot sweep below is what
--     actually guarantees a refresh if none of the three fire.
--   * GameTooltip:SetShapeshift(index) is OFFICIAL_CLIENT_DOCUMENTATION.
--   * behavior.json / wheelbinding.addon_command_registered.v1 enumerated this
--     client's whole binding table (225 commands, 2026-08-23): SHAPESHIFTBUTTON1
--     through SHAPESHIFTBUTTON10 are in it, at indices 54-63, defaulting to
--     CTRL-F1..CTRL-F10. RUNTIME evidence, and the reason this bar can be quick-
--     bound at all: those are real client commands, unlike unrealUI's own
--     declared ones, which the same capture proved absent. The keys reach the
--     client's own (suppressed but intact) shapeshift buttons -- suppression
--     hides an object and drops its mouse, it never strips its scripts or its
--     binding command -- which is the identical route modules/actionbar.lua's
--     native ACTIONBUTTON keys take.
--   * knowledge.json / actionbars.native_stock_children_suppression: the
--     native ShapeshiftBarFrame and its ShapeshiftButton1-N need the same
--     explicit suppress-and-reapply treatment as the other stock bars;
--     UnrealPfUI/modules/actionbar.lua:84,90 names the same frame/prefix
--     (WORKING_SOURCE).

local U = UnrealUI
local M = U.media

local SB = U.RegisterModule("stancebar")

local ICON_INSET = 2
local SIZE = 30
local SPACING = 3
local MAX_SLOTS = 10 -- native ShapeshiftButton1-10; no supported class fills it

-- The classes this bar is built for, and how many slots to hold open for one
-- while the client still reports none. GetNumShapeshiftForms returns 0 in the
-- short window after login before the spellbook is synced, and a bar of zero
-- buttons could never be dragged into place, so an unlocked interface shows
-- this many placeholders rather than nothing.
local SUPPORTED_CLASSES = {
  WARRIOR = 3, -- Battle / Defensive / Berserker Stance
  ROGUE   = 1, -- Stealth
}

local COLOR = {
  cooldown = { 1.00, 0.20, 0.20, 1.00 },
  keybind  = { 0.85, 0.85, 0.85, 1.00 },
}

-- Countdown-number tiers, shared with modules/actionbar.lua and
-- modules/auras.lua through M.cooldownText so the same remaining time reads
-- the same colour wherever unrealUI draws it.
local CD_COLOR = M.cooldownText

-- Below this a cooldown gets the radial sweep but no number. The warrior
-- stance swap is the case that matters: a digit flashing on every stance dance
-- is noise, while the sweep reads as motion. Same threshold and the same
-- reasoning as modules/actionbar.lua's GCD_THRESHOLD.
local CD_TEXT_THRESHOLD = 2

-- Both readouts work off the pair cached by UpdateCooldown rather than
-- re-asking the client, so they can tick faster than the API sweep. The wipe
-- is the faster of the two because a 1.5s animation redrawn at the number's
-- rate would step rather than travel.
local CD_TICK = 0.1
local SWEEP_TICK = 0.04
local cooldownTextRunning = false
local cooldownSweepRunning = false
local RefreshCooldownTexts
local RefreshCooldownSweeps

-- The client's own stance keys. One command per slot, exactly as the native
-- bar uses them, so a key bound here is the same key the Key Bindings window
-- shows and it keeps working with the addon unloaded.
local BINDING_PREFIX = "SHAPESHIFTBUTTON"

local frame, buttons = nil, {}
local shown = false
local slotCount = 0
local playerClass = nil
local placeholderSlots = 0
local supported = false
-- Resolved once in OnEnable. Classic only reports ready after
-- modules/actionbar.lua has captured the live client faces, which it does in
-- its own OnEnable -- ahead of this module in TOC order.
local classicChrome = false

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Resolved by name and pcall'd, same pattern as modules/actionbar.lua and
-- modules/petbar.lua: a missing call degrades one part of the bar rather than
-- erroring the module.
-- ---------------------------------------------------------------------------
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

-- GetShapeshiftFormInfo returns four values; the shared Call() above only
-- forwards three, so this gets its own fixed-arity wrapper.
local function GetFormInfo(id)
  local fn = ResolveApiFn("GetShapeshiftFormInfo")
  if not fn then return nil end
  local ok, texture, name, active, castable = pcall(fn, id)
  if not ok then return nil end
  return texture, name, active, castable
end

-- ---------------------------------------------------------------------------
-- Keybinds
--
-- Labels only: the keys themselves are the client's, and modules/quickbind.lua
-- writes them through the shared SetBinding path. Nothing here routes a key.
-- ---------------------------------------------------------------------------
local function ShowRegion(region, show)
  if not region then return end
  if show then pcall(region.Show, region) else pcall(region.Hide, region) end
end

local function BindingCommand(index)
  return BINDING_PREFIX .. index
end

-- One switch for every key label unrealUI draws: the action bars' own "Show
-- Keybinds" setting, rather than a second copy of it on this bar.
local function ShowKeybinds()
  if type(U.ActionBarShowsKeybinds) ~= "function" then return true end
  return U.ActionBarShowsKeybinds() and true or false
end

local function UpdateKeybind(button)
  if not button.uuiKeybind then return end

  local text = ""
  if ShowKeybinds() then
    -- Through U.SlotBindingKey for the same reason the action bars do: while
    -- the quick-binding mode is open it holds these keys, not the client.
    local command = BindingCommand(button.uuiIndex)
    local key
    if type(U.SlotBindingKey) == "function" then
      key = U.SlotBindingKey(command)
    else
      key = Call("GetBindingKey", command)
    end
    if type(key) == "string" and key ~= "" then
      -- Shared with the action bars so both read the same on an AZERTY client
      -- and compact a modifier the same way.
      text = (type(U.ActionBindingLabel) == "function" and
              U.ActionBindingLabel(key)) or key
    end
  end

  pcall(button.uuiKeybind.SetText, button.uuiKeybind, text)
  ShowRegion(button.uuiKeybind, text ~= "")
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
local function ApplyState(button)
  -- Classic never tints an outline (modules/actionbar.lua's ApplyButtonBorder
  -- returns early for a Classic slot): the client's own highlight carries
  -- hover and the held form, and the cooldown swipe carries the cooldown.
  if button.uuiClassic then
    U.SetClassicActionButtonHighlight(button, button.uuiHover, button.uuiActive)
    return
  end

  if button.uuiCdActive then
    U.SetBorderColor(button, COLOR.cooldown[1], COLOR.cooldown[2], COLOR.cooldown[3], 1)
  elseif button.uuiActive then
    U.SetBorderColor(button, M.Unpack(M.color.accent))
  elseif button.uuiHover then
    U.SetBorderColor(button, 0.55, 0.55, 0.55, 1)
  else
    U.SetBorderColor(button, M.Unpack(M.color.border))
  end
end

local function OnButtonClick(button)
  Call("CastShapeshiftForm", button.uuiIndex)
end

local function ShowTooltip(button)
  local tooltip = U.G("GameTooltip")
  if not tooltip then return end
  pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
  if pcall(tooltip.SetShapeshift, tooltip, button.uuiIndex) then
    pcall(tooltip.Show, tooltip)
  else
    pcall(tooltip.Hide, tooltip)
  end
end

local function HideTooltip()
  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end
end

local function CreateButton(index)
  local name = "UnrealUIStanceBarButton" .. index
  local button = CreateFrame("Button", name, frame)
  button.uuiIndex = index

  U.CreateBackdrop(button, {})
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp")

  local icon = button:CreateTexture(nil, "ARTWORK")
  button.uuiIcon = icon

  -- fonts.stretched_justification_ignored: anchored to the corner it belongs
  -- in rather than stretched across the button, the same as an action slot.
  button.uuiKeybind = U.CreateLabel(button, {
    size = M.fontSize.tiny, color = COLOR.keybind,
    inherits = "GameFontNormalSmall",
  })
  if button.uuiKeybind then
    button.uuiKeybind:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    button.uuiKeybind:Hide()
  end

  -- Same Model-frame cooldown swipe as modules/actionbar.lua and
  -- modules/petbar.lua; see actionbar.lua's header note for why this is the
  -- native Vanilla-shaped primitive rather than a synthetic overlay.
  local ok, cooldown = pcall(CreateFrame, "Model", name .. "Cooldown", button,
                             "CooldownFrameTemplate")
  if ok and cooldown and Has("CooldownFrame_SetTimer") then
    pcall(cooldown.SetAllPoints, cooldown, button)
    button.uuiCooldown = cooldown
  end

  -- knowledge.json / cooldown.model_swipe_not_rendered (RUNTIME_FAILURE_
  -- CONFIRMED): the Model swipe above draws nothing on this client, so the
  -- cooldown a player can actually see is unrealUI's own -- the hand-drawn
  -- radial wipe plus the countdown number, exactly as modules/actionbar.lua
  -- draws them on an action slot.
  --
  -- Both sit on a raised child frame for the reason that module raises its
  -- own: the Model child is drawn above the button's own OVERLAY layer, so a
  -- fontstring living there can end up underneath it. The layer takes no mouse
  -- input, so clicks still reach the button.
  local textLayer = CreateFrame("Frame", nil, button)
  pcall(textLayer.SetAllPoints, textLayer, button)
  local levelOk, level = pcall(button.GetFrameLevel, button)
  if levelOk and tonumber(level) then
    pcall(textLayer.SetFrameLevel, textLayer, level + 10)
  end
  button.uuiCooldownLayer = textLayer

  -- At BACKGROUND within the raised layer, so it covers the icon while the
  -- number stays on top of it. Sized explicitly rather than from the layer:
  -- the button is given its own size further down, so GetWidth answers 0 here.
  button.uuiSweep = U.CreateRadialWipe(textLayer)
  U.SizeRadialWipe(button.uuiSweep, SIZE)

  -- The countdown is the readout, not a corner label, so it scales off the
  -- button rather than off the keybind size -- the same half-the-button rule
  -- modules/actionbar.lua uses.
  local cdSize = math.floor(SIZE * 0.5)
  if cdSize < 10 then cdSize = 10 end
  if cdSize > 24 then cdSize = 24 end
  button.uuiCooldownText = U.CreateLabel(textLayer, {
    size = cdSize, color = CD_COLOR.normal, inherits = "GameFontNormal",
  })
  if button.uuiCooldownText then
    button.uuiCooldownText:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    button.uuiCooldownText:Hide()
  end

  button:SetScript("OnClick", function() OnButtonClick(button) end)
  button:SetScript("OnEnter", function()
    button.uuiHover = true
    ApplyState(button)
    ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    button.uuiHover = false
    ApplyState(button)
    HideTooltip()
  end)

  button:SetWidth(SIZE)
  button:SetHeight(SIZE)

  -- Classic owns the icon geometry as well as the slot face, because the
  -- client's face is the ornamental edge *around* an uncropped icon rather
  -- than a rim inside the button. If the faces were unavailable the button
  -- keeps the Modern flat treatment rather than drawing half of each.
  button.uuiClassic = classicChrome and
                      U.StyleClassicActionIconButton(button, icon, SIZE) or false

  if not button.uuiClassic then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", ICON_INSET, -ICON_INSET)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
  end

  return button
end

local function HideButton(button)
  -- A hidden button keeps no state. Classic locks the client highlight on for
  -- a held form, and a button hidden while locked comes back lit.
  button.uuiCdActive = false
  button.uuiCdText = false
  button.uuiCdShown = false
  button.uuiCdColor = nil
  button.uuiSweepShown = false
  button.uuiActive = false
  button.uuiHover = false
  ApplyState(button)
  ShowRegion(button.uuiKeybind, false)
  ShowRegion(button.uuiCooldownText, false)
  U.HideRadialWipe(button.uuiSweep)
  if button.uuiCooldown then pcall(button.uuiCooldown.Hide, button.uuiCooldown) end
  button:Hide()
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local function UpdateSlot(button)
  local texture, _, active, castable = GetFormInfo(button.uuiIndex)

  if type(texture) == "string" and texture ~= "" then
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    button.uuiIcon:Show()
  else
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    button.uuiIcon:Hide()
  end

  pcall(button.uuiIcon.SetDesaturated, button.uuiIcon, not castable)

  button.uuiActive = active and true or false
  ApplyState(button)
end

-- Redraws one button's number from its cached pair. Cheap on purpose: this is
-- what runs at CD_TICK, so it re-reads the clock but not the form API.
local function RefreshCooldownText(button)
  local label = button.uuiCooldownText
  if not label then return end

  local remaining = nil
  if button.uuiCdText then
    remaining = U.CooldownRemaining(button.uuiCdStart, button.uuiCdDuration)
  end

  if not remaining or remaining <= 0 then
    if remaining and remaining <= 0 then button.uuiCdText = false end
    if button.uuiCdShown then
      button.uuiCdShown = false
      button.uuiCdColor = nil
      pcall(label.SetText, label, "")
      pcall(label.Hide, label)
    end
    return
  end

  -- The string and its tier come from the shared U.FormatTimeShort; this only
  -- maps the tier onto the palette.
  local text, tier = U.FormatTimeShort(remaining)
  local color = CD_COLOR[tier] or CD_COLOR.normal
  pcall(label.SetText, label, text)

  if button.uuiCdColor ~= color then
    button.uuiCdColor = color
    pcall(label.SetTextColor, label, color[1], color[2], color[3], color[4])
  end
  if not button.uuiCdShown then
    button.uuiCdShown = true
    pcall(label.Show, label)
  end
  return true
end

-- The wipe travels across the whole cooldown, the short ones included: below
-- CD_TEXT_THRESHOLD it is the only feedback there is, which is the entire
-- reason a stance swap needs it. Idle cost is the uuiSweepShown flag check,
-- so this can tick at SWEEP_TICK without the bar paying for it while nothing
-- is running.
local function RefreshCooldownSweep(button)
  if not button.uuiSweep then return end

  if not button.uuiCdActive then
    if button.uuiSweepShown then
      button.uuiSweepShown = false
      U.HideRadialWipe(button.uuiSweep)
    end
    return
  end

  local duration = button.uuiCdDuration or 0
  local remaining = U.CooldownRemaining(button.uuiCdStart, duration)
  if duration <= 0 or not remaining or remaining <= 0 then
    -- Ending the cooldown here rather than waiting for the next API sweep is
    -- what drops the Modern red outline on the same frame the wipe closes.
    button.uuiCdActive = false
    button.uuiSweepShown = false
    U.HideRadialWipe(button.uuiSweep)
    ApplyState(button)
    return
  end

  button.uuiSweepShown = true
  U.SetRadialWipeProgress(button.uuiSweep, (duration - remaining) / duration)
  return true
end

local function WakeCooldownText()
  if cooldownTextRunning then return end
  cooldownTextRunning = true
  U.RegisterUpdate("stancebar.cdtext", CD_TICK, RefreshCooldownTexts)
end

local function WakeCooldownSweep()
  if cooldownSweepRunning then return end
  cooldownSweepRunning = true
  U.RegisterUpdate("stancebar.sweep", SWEEP_TICK, RefreshCooldownSweeps)
end

local function UpdateCooldown(button)
  local start, duration, enable = Call("GetShapeshiftFormCooldown", button.uuiIndex)
  start = tonumber(start) or 0
  duration = tonumber(duration) or 0
  enable = tonumber(enable)

  if button.uuiCooldown then
    local fn = ResolveApiFn("CooldownFrame_SetTimer")
    if fn then pcall(fn, button.uuiCooldown, start, duration, enable or 1) end
  end

  button.uuiCdStart = start
  button.uuiCdDuration = duration
  -- enable == 0 is Vanilla's "this slot has a cooldown but must not display
  -- one" flag; a missing value is read as enabled, the way
  -- modules/actionbar.lua reads it.
  local running = (start > 0 and duration > 0 and
                   (enable == nil or enable > 0)) and true or false
  button.uuiCdActive = running
  button.uuiCdText = (running and duration >= CD_TEXT_THRESHOLD) and true or false

  ApplyState(button)
  if RefreshCooldownSweep(button) then WakeCooldownSweep() end
  if RefreshCooldownText(button) then WakeCooldownText() end
end

local function FullUpdate(button)
  UpdateSlot(button)
  UpdateCooldown(button)
  UpdateKeybind(button)
end

local function ForEachButton(callback)
  -- /uui perf stancebar. Both recurring sweeps walk the buttons through here.
  if U.PerfDisabled and U.PerfDisabled("stancebar") then return end
  if not shown then return end
  local i
  for i = 1, table.getn(buttons) do callback(buttons[i]) end
end

local activeCooldownTextSeen = false
local function RefreshActiveCooldownText(button)
  if RefreshCooldownText(button) then activeCooldownTextSeen = true end
end

RefreshCooldownTexts = function()
  activeCooldownTextSeen = false
  ForEachButton(RefreshActiveCooldownText)
  if not activeCooldownTextSeen then
    cooldownTextRunning = false
    U.UnregisterUpdate("stancebar.cdtext")
  end
end

local activeCooldownSweepSeen = false
local function RefreshActiveCooldownSweep(button)
  if RefreshCooldownSweep(button) then activeCooldownSweepSeen = true end
end

RefreshCooldownSweeps = function()
  activeCooldownSweepSeen = false
  ForEachButton(RefreshActiveCooldownSweep)
  if not activeCooldownSweepSeen then
    cooldownSweepRunning = false
    U.UnregisterUpdate("stancebar.sweep")
  end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local function CreateBar()
  frame = CreateFrame("Frame", "UnrealUIStanceBar", UIParent)
  -- Matches the main action bars and pet bar: stays below overlapping native
  -- interface windows.
  pcall(frame.SetFrameStrata, frame, "LOW")
  frame:SetWidth(100)
  frame:SetHeight(SIZE)

  U.RegisterMover("stancebar", frame, {
    label = U.L("MOVER_LABEL_STANCE_BAR"),
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = -120, y = 64 },
  })
end

-- Built on demand rather than MAX_SLOTS at a time: a Rogue needs exactly one
-- slot, and every button carries a Model cooldown frame that a class which can
-- never fill it should not pay for.
local function EnsureButtons(count)
  if count > MAX_SLOTS then count = MAX_SLOTS end
  local i
  for i = table.getn(buttons) + 1, count do buttons[i] = CreateButton(i) end
end

local function Layout()
  if not frame then return end

  slotCount = tonumber(Call("GetNumShapeshiftForms")) or 0
  -- A bar with zero forms (a brief race right after login, before the
  -- spellbook is synced) could never be dragged into place: keep the same
  -- unlocked-placeholder rule modules/petbar.lua and modules/castbar.lua use.
  local visible = supported and (slotCount > 0 or U.IsUnlocked())
  local count = slotCount > 0 and slotCount or placeholderSlots
  if count > MAX_SLOTS then count = MAX_SLOTS end
  EnsureButtons(count)

  frame:SetWidth(count * SIZE + (count - 1) * SPACING)
  frame:SetHeight(SIZE)

  local i
  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    if visible and i <= count then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (SIZE + SPACING), 0)
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
  if not supported then return end
  if not frame then CreateBar() end
  Layout()
end

-- ---------------------------------------------------------------------------
-- Native bar
-- ---------------------------------------------------------------------------
local NATIVE_PARTS = {
  "Icon", "NormalTexture", "NormalTexture2", "HotKey", "Count",
  "Border", "Cooldown", "Flash", "Name", "AutoCastable",
}

local function SuppressNativeBar()
  local names = { "ShapeshiftBarFrame" }
  local i, j
  for i = 1, MAX_SLOTS do
    local base = "ShapeshiftButton" .. i
    table.insert(names, base)
    for j = 1, table.getn(NATIVE_PARTS) do
      table.insert(names, base .. NATIVE_PARTS[j])
    end
  end
  U.SuppressNativeFrame(names)
end

-- ---------------------------------------------------------------------------
-- Events and refresh
-- ---------------------------------------------------------------------------
local function RegisterEvents()
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() Apply() end)
  U.RegisterEvent("UPDATE_SHAPESHIFT_FORM", function() ForEachButton(FullUpdate) end)
  U.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function() Apply() end)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", function() ForEachButton(UpdateSlot) end)
end

function SB:OnEnable()
  local _, class = Call("UnitClass", "player")
  playerClass = class
  placeholderSlots = SUPPORTED_CLASSES[class or ""] or 0
  supported = placeholderSlots > 0
  if not supported then return end

  -- Classic reuses the client's own action-button faces, which
  -- modules/actionbar.lua captures live in its own OnEnable -- before the stock
  -- bars are suppressed, and before this module runs. Modern captures nothing
  -- and this stays false, so every button below keeps the flat treatment.
  classicChrome = type(U.ClassicActionChromeReady) == "function" and
                  U.ClassicActionChromeReady() or false

  SuppressNativeBar()
  Apply()
  RegisterEvents()

  -- Two rates, same reasoning as modules/petbar.lua: state (cooldown/active
  -- border) is what the eye tracks and ticks faster; the full slot-contents +
  -- visibility sweep is the low-frequency safety net that catches anything
  -- the accelerator events above missed (including an edit-mode lock/unlock).
  --
  -- The cooldown pair itself is re-read faster than the old 0.5s: a stance
  -- swap is gone in about 1.5s, so half a second of latency before the sweep
  -- even starts is a third of the animation. The two readouts below then run
  -- off that cached pair only while it is active -- the number at CD_TICK, the
  -- wipe at SWEEP_TICK so it travels rather than steps.
  U.RegisterUpdate("stancebar.cooldown", 0.2, function() ForEachButton(UpdateCooldown) end)
  U.RegisterUpdate("stancebar.slots", 0.5, function() Apply() end)
end

-- ---------------------------------------------------------------------------
-- Quick binding
--
-- modules/quickbind.lua asks every bind provider which buttons are on screen
-- and which client command each answers to, then hands the refresh back so the
-- corner labels are rebuilt where they are owned. This bar needs no key route
-- of its own: SHAPESHIFTBUTTON1-10 are the client's own commands (see the
-- header), so a key bound to one fires the client's shapeshift path directly.
-- ---------------------------------------------------------------------------
function U.StanceBarBindTargets()
  local targets = {}
  if not shown then return targets end

  local i
  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    local ok, visible = pcall(button.IsShown, button)
    if ok and visible then
      table.insert(targets, {
        button = button,
        index = button.uuiIndex,
        command = BindingCommand(button.uuiIndex),
        stance = true,
      })
    end
  end
  return targets
end

-- Only the buttons on screen: HideButton drops a hidden slot's label with the
-- rest of its state, and a refresh must not put it back.
function U.RefreshStanceBarBindings()
  local i
  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    local ok, visible = pcall(button.IsShown, button)
    if ok and visible then UpdateKeybind(button) end
  end
end

-- Reported by /uui check.
function U.StanceBarReport()
  return {
    class = playerClass,
    supported = supported,
    classic = classicChrome,
    created = frame and true or false,
    shown = shown,
    slotCount = slotCount,
    -- Whether the two owned cooldown readouts were actually built, so a bar
    -- showing no cooldown can be told apart from one whose label or wipe never
    -- got created.
    cooldownText = (buttons[1] and buttons[1].uuiCooldownText) and true or false,
    cooldownSweep = (buttons[1] and buttons[1].uuiSweep) and true or false,
  }
end
