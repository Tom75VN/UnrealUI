-- unrealUI :: modules/quickbind.lua
--
-- Quick binding: a mode where hovering an action slot and pressing a key binds
-- that key to the slot. Reached from the Escape menu, from ActionBars ->
-- General Options, and from /uui bind.
--
-- Scope is deliberately narrow. This is not pfUI's hoverbind module rebuilt:
-- there is no stance/pet/paging keymap, no pfUI info-box framework and no
-- second binding UI. It drives exactly the slots modules/actionbar.lua reports
-- through U.ActionBarBindTargets, using the native binding commands that
-- already back the corner key labels.
--
-- Behaviour that was decided rather than inherited:
--
--   * A slot carries exactly one key. Binding a key clears whatever keys the
--     slot's command held first, so the key shown on the button is always the
--     key that was just pressed. pfUI adds instead, which leaves the label
--     showing the older key.
--   * Keys are written to the client as they are pressed, so every slot always
--     shows what the client actually holds rather than a staged preview. They
--     cannot be fired while the mode is open -- the catchers own the keyboard --
--     but they are live the moment it closes. Save persists them to the binding
--     set; Cancel (and Escape outside a slot) puts every key this session
--     touched back to the action it held on open.
--   * Only the bars this client gives a binding command can be bound: bars
--     1-5. Bar 6 and the class pages 7-10 have no key route at all here (see
--     "Bars with no key route" in modules/actionbar.lua for the three routes
--     that were tried and measured closed). They are still shown in the mode,
--     outlined in red, with the reason in their tooltip -- more useful than a
--     hole in the overlay, and honest about what the client can do.
--
-- Compatibility notes that shaped this file:
--
--   * SetBinding / SaveBindings / GetBindingAction / GetCurrentBindingSet have
--     no compact runtime record. SetBinding is WORKING_SOURCE on this client
--     from two places: UnrealPfUI's modules/hoverbind.lua (the exact feature
--     reproduced here) and unrealUI's own chat wheel remap (knowledge.json /
--     chat.mousewheel_uses_binding_layer). Every call is resolved by name and
--     pcall'd, and a missing SaveBindings is reported to the player rather
--     than silently dropping their work.
--   * knowledge.json / frames.movable_drag_requires_button_handle
--     (BEHAVIOR_VERIFIED): mouse input reaches a Button parented to the frame
--     it covers and raised by frame level. The per-slot catchers are therefore
--     Buttons parented to the action button, not the plain Frames pfUI uses.
--   * knowledge.json / scripts.keyboard_frame_only_keydown_arg1 (measured in
--     game on 2026-08-19 with /uui keytest): on this client a plain Frame with
--     EnableKeyboard(true) receives OnKeyDown, a Button receives nothing at
--     all, OnKeyUp never fires, and the key name arrives only through the
--     legacy arg1 global. That single measurement decides three things here:
--     keys are caught by one plain Frame (not by the per-slot catchers, which
--     stay Buttons because frames.movable_drag_requires_button_handle makes
--     Button the widget mouse input reaches), every key script is OnKeyDown,
--     and ResolveInput's arg1 fallback is the path that actually carries the
--     name rather than a defensive extra.
--   * knowledge.json / chat.mousewheel_uses_binding_layer: the binding layer
--     runs before addon frame scripts on this client. That is why the wheel is
--     not offered as a bindable input, and why Escape has to be lifted off
--     TOGGLEGAMEMENU for the duration of the mode (SuspendMenuKeys) instead of
--     being relied on to stop at a keyboard-enabled frame -- confirmed in game
--     on 2026-08-19, where Escape opened the client's game menu on top of the
--     mode. The same record's solution shape is used: save the action, remap
--     while the mode owns the screen, always restore.
--   * knowledge.json / rendering.parent_alpha_not_propagated: every region is
--     shown and hidden explicitly, never through its parent.
--   * knowledge.json / scripts.child_onupdate_unreliable: this mode owns no
--     OnUpdate. It is event and input driven only.

local U = UnrealUI
local M = U.media

local QB = U.RegisterModule("quickbind")

-- The binding readout in the middle of a slot, and the tooltip's key line.
-- Green rather than the unrealUI accent so it cannot be mistaken for the
-- addon's own chrome while the mode is open.
local KEY_COLOR      = { 0.35, 1.00, 0.35, 1.00 }
local KEY_NONE_COLOR = { 0.60, 0.60, 0.60, 1.00 }
local KEY_LOCK_COLOR = { 0.85, 0.35, 0.35, 1.00 }

local HOVER_FILL   = { 0.96, 0.68, 0.04, 0.25 }
local BINDABLE     = { 0.55, 0.39, 0.03, 1.00 }
-- Only reachable when the client has not registered unrealUI's declared
-- commands, which needs a client restart rather than a /reload.
local NOT_BINDABLE = { 0.35, 0.14, 0.14, 1.00 }

local PANEL_WIDTH = 420
local PANEL_HEIGHT = 158

-- Two frames can both be handed the same key press (the slot catcher and the
-- keyboard-enabled shade behind it). Re-running one bind is harmless, but a
-- repeat of Escape would clear a binding the first pass had already replaced.
local REPEAT_GUARD = 0.15

-- ---------------------------------------------------------------------------
-- Client calls
-- ---------------------------------------------------------------------------
local function Call(name, a, b, c)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3
end

local function Down(name)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  local ok, held = pcall(fn)
  if not ok then return false end
  return (held and held ~= 0) and true or false
end

-- knowledge.json / scripts.handler_arguments_direct: resolve all three observed
-- shapes rather than committing to one.
local function ResolveInput(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  local legacy = U.G("arg1")
  if type(legacy) == "string" then return legacy end
  return nil
end

-- ---------------------------------------------------------------------------
-- Input model
-- ---------------------------------------------------------------------------

-- A modifier on its own is never a binding: it is the prefix for the next key.
local MODIFIER_KEYS = {
  ["ALT"] = true, ["LALT"] = true, ["RALT"] = true,
  ["CTRL"] = true, ["LCTRL"] = true, ["RCTRL"] = true,
  ["SHIFT"] = true, ["LSHIFT"] = true, ["RSHIFT"] = true,
  ["UNKNOWN"] = true,
}

-- Mouse buttons are bindable; the wheel is not (see the header note on
-- chat.mousewheel_uses_binding_layer).
local MOUSE_BUTTON = {
  ["LeftButton"] = "BUTTON1",
  ["RightButton"] = "BUTTON2",
  ["MiddleButton"] = "BUTTON3",
  ["Button4"] = "BUTTON4",
  ["Button5"] = "BUTTON5",
}

-- Taking plain left/right click away from the action bars would make the mode
-- unusable, so those two need a modifier. Same rule as pfUI's blockedKeys.
local NEEDS_MODIFIER = {
  ["BUTTON1"] = true,
  ["BUTTON2"] = true,
}

local function Prefix()
  local prefix = ""
  if Down("IsAltKeyDown") then prefix = prefix .. "ALT-" end
  if Down("IsControlKeyDown") then prefix = prefix .. "CTRL-" end
  if Down("IsShiftKeyDown") then prefix = prefix .. "SHIFT-" end
  return prefix
end

-- ---------------------------------------------------------------------------
-- Binding state
--
-- `restore` is the undo log: the action each touched key held when the mode
-- first touched it, or false when the key was free. Binding a key can steal it
-- from another command, so the log is keyed by key rather than by slot -- that
-- is the only form Cancel can put back exactly.
-- ---------------------------------------------------------------------------
local active = false
local restore = {}   -- undo log: key -> the action it held on open, or false
local changes = 0
local lastInput, lastInputAt

local function RememberKey(key)
  if type(key) ~= "string" or key == "" then return end
  if restore[key] ~= nil then return end

  local action = Call("GetBindingAction", key)
  if type(action) ~= "string" or action == "" then action = false end
  restore[key] = action
end

local function CommandKeys(command)
  local keys = {}
  if type(command) ~= "string" then return keys end

  local key1, key2 = Call("GetBindingKey", command)
  if type(key1) == "string" and key1 ~= "" then table.insert(keys, key1) end
  if type(key2) == "string" and key2 ~= "" and key2 ~= key1 then
    table.insert(keys, key2)
  end
  return keys
end

local function CurrentKey(command)
  local keys = CommandKeys(command)
  return keys[1]
end

local function RefreshBars()
  if type(U.RefreshActionBarBindings) == "function" then
    U.RefreshActionBarBindings()
  end
end

-- Clears every key currently routed to `command`, logging each one first.
local function ClearCommand(command)
  local keys = CommandKeys(command)
  local i

  for i = 1, table.getn(keys) do
    RememberKey(keys[i])
    Call("SetBinding", keys[i])
  end
  return table.getn(keys)
end

local function BindKey(command, key)
  if type(command) ~= "string" or type(key) ~= "string" or key == "" then
    return false
  end

  -- One slot, one key: drop what the command held before taking the new key.
  ClearCommand(command)
  RememberKey(key)

  local set = U.G("SetBinding")
  if type(set) ~= "function" then
    U.Print(U.L("QUICKBIND_NO_SETBINDING"))
    return false
  end

  local ok, result = pcall(set, key, command)
  if not ok then return false end

  changes = changes + 1
  RefreshBars()
  return result ~= false
end

local function ClearBinding(command)
  if type(command) ~= "string" then return false end
  if table.getn(CommandKeys(command)) == 0 then return false end

  ClearCommand(command)
  changes = changes + 1
  RefreshBars()
  return true
end

local function RestoreBindings()
  local key, action

  -- Two passes: free every touched key first, so putting the old actions back
  -- cannot collide with a key that has not been released yet.
  for key, action in pairs(restore) do
    Call("SetBinding", key)
  end
  for key, action in pairs(restore) do
    if action then Call("SetBinding", key, action) end
  end

  restore = {}
  changes = 0
  RefreshBars()
end

local function PersistBindings()
  local save = U.G("SaveBindings")
  if type(save) ~= "function" then
    U.Print(U.L("QUICKBIND_SAVE_UNAVAILABLE"))
    return false
  end

  local set = tonumber(Call("GetCurrentBindingSet")) or
              tonumber(U.G("ACCOUNT_BINDINGS")) or 1

  if not pcall(save, set) then
    if not pcall(save) then
      U.Print(U.L("QUICKBIND_SAVE_FAILED"))
      restore = {}
      return false
    end
  end

  restore = {}
  return true
end

-- ---------------------------------------------------------------------------
-- Escape
--
-- Escape is the mode's clear-and-exit key, but the client reaches its own game
-- menu first: TOGGLEGAMEMENU fires from the binding layer, which this client
-- resolves before an addon frame's key script (chat.mousewheel_uses_binding_
-- layer). The mode therefore lifts that command's keys while it is open and
-- puts them back on close.
--
-- This is mode plumbing, not a player edit: it is kept out of the undo log, it
-- is restored on Save and on Cancel alike, and it is restored *before* anything
-- is written to the binding set so a save can never persist a missing menu key.
-- ---------------------------------------------------------------------------
local suspended = {}

local function SuspendMenuKeys()
  suspended = {}

  local keys = CommandKeys("TOGGLEGAMEMENU")
  local i
  for i = 1, table.getn(keys) do
    table.insert(suspended, keys[i])
    Call("SetBinding", keys[i])
  end
end

local function ReleaseMenuKeys()
  local i
  for i = 1, table.getn(suspended) do
    local key = suspended[i]
    -- Never take a key back off the player: if the mode handed this key to a
    -- slot, that assignment wins and the menu key stays gone.
    local action = Call("GetBindingAction", key)
    if type(action) ~= "string" or action == "" then
      Call("SetBinding", key, "TOGGLEGAMEMENU")
    end
  end
  suspended = {}
end

-- Second line of defence. If this client refuses to move TOGGLEGAMEMENU, or
-- reaches the menu by some route other than that command, the menu is closed
-- again rather than being left stacked on top of the mode.
local menuGuardInstalled = false

local function InstallMenuGuard()
  if menuGuardInstalled then return end

  local frame = U.G("GameMenuFrame")
  if not frame then return end

  menuGuardInstalled = U.PostHookScript(frame, "OnShow", function()
    if not active then return end
    local hide = U.G("HideUIPanel")
    if type(hide) == "function" then
      pcall(hide, frame)
    else
      pcall(frame.Hide, frame)
    end
  end) and true or false
end

-- ---------------------------------------------------------------------------
-- Overlay
--
-- One catcher Button per visible action slot, parented to the slot and raised
-- above it. While the mode is open the catcher owns the mouse, so the slot's
-- own OnEnter/OnLeave never run and the hover state drawn here is the only one.
-- ---------------------------------------------------------------------------
local overlays = {}      -- action button -> catcher
local shown = {}         -- catchers currently in use
local byFrame = {}       -- catcher -> catcher, for the GetMouseFocus fallback
local hovered
local shade, panel, keys

local HandleInput        -- forward declaration; the catchers call it

local function Bindable(catcher)
  return catcher.command and true or false
end

local function LabelFor(catcher)
  if not Bindable(catcher) then return "n/a", KEY_LOCK_COLOR end

  local key = CurrentKey(catcher.command)
  if not key then return "--", KEY_NONE_COLOR end

  local label = key
  if type(U.ActionBindingLabel) == "function" then
    label = U.ActionBindingLabel(key, true)
  end
  if label == "" then label = key end
  return label, KEY_COLOR
end

local function RefreshCatcher(catcher)
  local label, color = LabelFor(catcher)

  if catcher.text then
    catcher.text:SetText(label)
    pcall(catcher.text.SetTextColor, catcher.text, M.Unpack(color))
  end

  U.SetBorderColor(catcher, M.Unpack(
    hovered == catcher and M.color.moverEdge or
    (Bindable(catcher) and BINDABLE or NOT_BINDABLE)))
end

local function ShowTooltip(catcher)
  local tooltip = U.G("GameTooltip")
  if not tooltip or type(tooltip.AddLine) ~= "function" then return end

  if not pcall(tooltip.SetOwner, tooltip, catcher, "ANCHOR_RIGHT") then return end
  pcall(tooltip.ClearLines, tooltip)

  pcall(tooltip.AddLine, tooltip,
        "Bar " .. tostring(catcher.bar) .. "  Slot " .. tostring(catcher.index),
        1, 1, 1)

  if not Bindable(catcher) then
    pcall(tooltip.AddLine, tooltip,
          "This client has no key command for this bar.", 0.85, 0.35, 0.35)
    pcall(tooltip.AddLine, tooltip,
          "Bars 1-5 are the bindable ones.", 0.6, 0.6, 0.6)
    pcall(tooltip.Show, tooltip)
    return
  end

  local key = CurrentKey(catcher.command)
  if key then
    local label = key
    if type(U.ActionBindingLabel) == "function" then
      label = U.ActionBindingLabel(key, true)
    end
    pcall(tooltip.AddLine, tooltip, "Bound to " .. label, 0.35, 1, 0.35)
  else
    pcall(tooltip.AddLine, tooltip, "Not bound", 0.6, 0.6, 0.6)
  end

  pcall(tooltip.AddLine, tooltip, "Press a key to bind it to this slot.", 0.9, 0.9, 0.9)
  pcall(tooltip.AddLine, tooltip, "Press Escape to clear the binding.", 0.9, 0.9, 0.9)

  -- Only reachable if a client ever registers unrealUI's declared commands:
  -- they are filed under an unrealUI header rather than beside the stock keys.
  if catcher.declared then
    pcall(tooltip.AddLine, tooltip,
          "Key Bindings: unrealUI Bar " .. tostring(catcher.bar),
          0.96, 0.68, 0.04)
  end

  pcall(tooltip.Show, tooltip)
end

local function HideTooltip()
  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end
end

local function SetHovered(catcher)
  local previous = hovered
  hovered = catcher

  if previous and previous ~= catcher then
    if previous.fill then previous.fill:Hide() end
    if previous.text then previous.text:Hide() end
    RefreshCatcher(previous)
  end

  if not catcher then
    HideTooltip()
    return
  end

  if catcher.fill then catcher.fill:Show() end
  if catcher.text then catcher.text:Show() end
  RefreshCatcher(catcher)
  ShowTooltip(catcher)
end

-- The catcher under the cursor. The tracked value is the primary answer;
-- GetMouseFocus is the fallback for a client that delivers a key press without
-- having delivered the matching OnEnter (it has no compact record here, which
-- is why it is not the primary path).
local function HoveredCatcher()
  if hovered then return hovered end

  local focus = Call("GetMouseFocus")
  if focus and byFrame[focus] then return byFrame[focus] end
  return nil
end

local function CreateCatcher(target)
  local button = target.button

  -- frames.movable_drag_requires_button_handle: Button widget, parented to the
  -- frame it covers, raised by frame level rather than by strata.
  -- Mouse only. Measured: a Button receives no key events on this client, so
  -- the keyboard lives on the single Frame in CreateKeyCatcher instead.
  local catcher = CreateFrame("Button", nil, button)
  pcall(catcher.SetAllPoints, catcher, button)
  pcall(catcher.EnableMouse, catcher, true)
  pcall(catcher.RegisterForClicks, catcher, "AnyUp")

  local ok, level = pcall(button.GetFrameLevel, button)
  if ok and tonumber(level) then
    pcall(catcher.SetFrameLevel, catcher, level + 20)
  end

  U.CreateBorder(catcher)

  local fill = catcher:CreateTexture(nil, "ARTWORK")
  pcall(fill.SetAllPoints, fill, catcher)
  pcall(fill.SetTexture, fill, M.texture.plain)
  U.SetColor(fill, M.Unpack(HOVER_FILL))
  fill:Hide()
  catcher.fill = fill

  catcher.text = U.CreateLabel(catcher, {
    size = M.fontSize.normal,
    color = KEY_COLOR,
    inherits = "GameFontNormal",
  })
  if catcher.text then
    catcher.text:SetPoint("CENTER", catcher, "CENTER", 0, 0)
    catcher.text:Hide()
  end

  -- scripts.handler_arguments_direct: handlers close over `catcher` and resolve
  -- their payload through ResolveInput instead of reading `this`.
  catcher:SetScript("OnEnter", function() SetHovered(catcher) end)
  catcher:SetScript("OnLeave", function()
    if hovered == catcher then SetHovered(nil) end
  end)
  catcher:SetScript("OnClick", function(a, b)
    HandleInput(ResolveInput(a, b), MOUSE_BUTTON)
  end)

  byFrame[catcher] = catcher
  return catcher
end

local function SizeCatcher(catcher)
  if not catcher.text then return end

  local size = 20
  local ok, height = pcall(catcher.GetHeight, catcher)
  if ok and tonumber(height) and height > 0 then size = height end

  -- The readout is the point of the mode, so it scales off the slot the way
  -- the cooldown countdown does rather than off the small corner-label size.
  local fontSize = math.floor(size * 0.45)
  if fontSize < 9 then fontSize = 9 end
  if fontSize > 20 then fontSize = 20 end
  U.SetFont(catcher.text, fontSize)
end

local function HideCatchers()
  local i
  for i = 1, table.getn(shown) do
    local catcher = shown[i]
    if catcher.fill then catcher.fill:Hide() end
    if catcher.text then catcher.text:Hide() end
    catcher:Hide()
  end
  shown = {}
  hovered = nil
end

local function ShowCatchers()
  HideCatchers()

  if type(U.ActionBarBindTargets) ~= "function" then return 0 end

  local targets = U.ActionBarBindTargets()
  local i
  for i = 1, table.getn(targets) do
    local target = targets[i]
    local catcher = overlays[target.button]
    if not catcher then
      catcher = CreateCatcher(target)
      overlays[target.button] = catcher
    end

    catcher.bar = target.bar
    catcher.index = target.index
    catcher.command = target.command
    catcher.declared = target.declared and true or false

    SizeCatcher(catcher)
    RefreshCatcher(catcher)
    catcher:Show()
    if catcher.fill then catcher.fill:Hide() end
    if catcher.text then catcher.text:Hide() end

    table.insert(shown, catcher)
  end

  return table.getn(shown)
end

local function RefreshShown()
  local i
  for i = 1, table.getn(shown) do RefreshCatcher(shown[i]) end
  if hovered then ShowTooltip(hovered) end
end

-- ---------------------------------------------------------------------------
-- Input handling
-- ---------------------------------------------------------------------------
local Close

-- input  the raw key or mouse-button name
-- map    MOUSE_BUTTON when the input came from a click, nil for a key
function HandleInput(input, map)
  if not active or type(input) ~= "string" or input == "" then return end
  if MODIFIER_KEYS[input] then return end

  -- One physical press can reach more than one keyboard-enabled frame.
  local now = tonumber(Call("GetTime"))
  if now and lastInput == input and lastInputAt and
     (now - lastInputAt) < REPEAT_GUARD then
    return
  end
  lastInput, lastInputAt = input, now

  local catcher = HoveredCatcher()

  if input == "ESCAPE" then
    -- Over a bindable slot Escape clears that slot; anywhere else it is the
    -- way out of the mode, which is the pfUI behaviour players expect.
    if catcher and Bindable(catcher) then
      if ClearBinding(catcher.command) then
        RefreshShown()
        U.Print(U.L("QUICKBIND_CLEARED", tostring(catcher.bar),
                    tostring(catcher.index)))
      end
      return
    end
    Close(false)
    return
  end

  if not catcher then return end

  if not Bindable(catcher) then
    U.Print(U.L("QUICKBIND_NO_COMMAND", tostring(catcher.bar)))
    return
  end

  local key = input
  if map then
    key = map[input]
    if not key then return end
  end

  local prefix = Prefix()
  if prefix == "" and NEEDS_MODIFIER[key] then return end

  if BindKey(catcher.command, prefix .. key) then
    RefreshShown()
  end
end

-- ---------------------------------------------------------------------------
-- Mode chrome
-- ---------------------------------------------------------------------------
local function CreateShade()
  -- pfUI's keybind shade sits at BACKGROUND so the bars stay clickable above
  -- it. It is mouse-enabled purely to swallow world clicks; keys are not its
  -- business (see CreateKeyCatcher).
  shade = CreateFrame("Button", "UnrealUIQuickBindShade", UIParent)
  pcall(shade.SetAllPoints, shade, UIParent)
  pcall(shade.SetFrameStrata, shade, "BACKGROUND")
  pcall(shade.SetFrameLevel, shade, 0)
  pcall(shade.EnableMouse, shade, true)

  local tex = shade:CreateTexture(nil, "BACKGROUND")
  pcall(tex.SetAllPoints, tex, shade)
  pcall(tex.SetTexture, tex, M.texture.plain)
  U.SetColor(tex, 0, 0, 0, 0.45)
  shade.tex = tex

  shade:Hide()
end

-- The one widget in this mode that receives keys.
--
-- Measured on this client (/uui keytest, 2026-08-19): a plain Frame with
-- EnableKeyboard(true) receives OnKeyDown for bound keys, unbound keys and
-- Escape alike; a Button receives nothing; OnKeyUp never fires; the key name
-- arrives only in the legacy arg1 global.
--
-- It takes no mouse input, so it can cover the screen without stealing a click
-- from the per-slot catchers underneath it, and which slot a key applies to
-- comes from the hover state those catchers track.
local function CreateKeyCatcher()
  keys = CreateFrame("Frame", "UnrealUIQuickBindKeys", UIParent)
  pcall(keys.SetAllPoints, keys, UIParent)
  pcall(keys.SetFrameStrata, keys, "FULLSCREEN_DIALOG")
  pcall(keys.EnableKeyboard, keys, true)
  pcall(keys.EnableMouse, keys, false)

  keys:SetScript("OnKeyDown", function(a, b)
    HandleInput(ResolveInput(a, b), nil)
  end)
  keys:Hide()
end

local HINTS = {
  "Hover a slot, then press a key to set its binding.",
  "Press Escape over a slot to clear that slot's binding.",
  "Escape outside a slot, or Cancel, leaves without saving.",
}

local function CreatePanel()
  panel = U.CreatePanel(UIParent, {
    name = "UnrealUIQuickBindPanel",
    width = PANEL_WIDTH,
    height = PANEL_HEIGHT,
  })
  panel:SetPoint("TOP", UIParent, "TOP", 0, -140)
  pcall(panel.SetFrameStrata, panel, "DIALOG")

  panel.parts = {}

  local title = U.CreateLabel(panel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  if title then
    title:SetPoint("TOP", panel, "TOP", 0, -12)
    title:SetText(U.L("QUICKBIND_TITLE"))
    table.insert(panel.parts, title)
  end

  local i
  for i = 1, table.getn(HINTS) do
    local hint = U.CreateLabel(panel, {
      size = M.fontSize.small,
      color = M.color.textDim,
      inherits = "GameFontNormalSmall",
      width = PANEL_WIDTH - 32,
    })
    if hint then
      hint:SetPoint("TOP", panel, "TOP", 0, -38 - (i - 1) * 17)
      hint:SetText(HINTS[i])
      table.insert(panel.parts, hint)
    end
  end

  panel.status = U.CreateLabel(panel, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
    width = PANEL_WIDTH - 32,
  })
  if panel.status then
    panel.status:SetPoint("TOP", panel, "TOP", 0, -38 - table.getn(HINTS) * 17 - 4)
    table.insert(panel.parts, panel.status)
  end

  panel.save = U.CreateButton(panel, {
    name = "UnrealUIQuickBindSave",
    text = U.L("COMMON_SAVE"),
    width = 120,
    height = 24,
    onClick = function() Close(true) end,
  })
  panel.save:SetPoint("BOTTOM", panel, "BOTTOM", -66, 12)
  table.insert(panel.parts, panel.save)

  panel.cancel = U.CreateButton(panel, {
    name = "UnrealUIQuickBindCancel",
    text = U.L("COMMON_CANCEL"),
    width = 120,
    height = 24,
    onClick = function() Close(false) end,
  })
  panel.cancel:SetPoint("BOTTOM", panel, "BOTTOM", 66, 12)
  table.insert(panel.parts, panel.cancel)

  panel:Hide()
end

-- rendering.parent_alpha_not_propagated: the panel's children are toggled by
-- hand rather than through the panel itself. A button's caption is its own
-- region as well (buttons.plain_settext_no_fontstring), so it is toggled too.
local function SetPartShown(part, show)
  if not part then return end
  if show then part:Show() else part:Hide() end
  if part.label then
    if show then part.label:Show() else part.label:Hide() end
  end
end

local function SetPartsShown(show)
  local i
  for i = 1, table.getn(panel.parts) do SetPartShown(panel.parts[i], show) end
end

local function ShowPanel(count)
  if panel.status then
    panel.status:SetText(U.LN("QUICKBIND_SLOT_COUNT", count))
    pcall(panel.status.SetTextColor, panel.status, M.Unpack(M.color.textDim))
  end

  panel:Show()
  SetPartsShown(true)
end

local function HidePanel()
  if not panel then return end
  SetPartsShown(false)
  panel:Hide()
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function U.OpenQuickBind()
  if active then return true end

  if type(U.ActionBarBindTargets) ~= "function" then
    U.Print(U.L("QUICKBIND_NO_ACTIONBARS"))
    return false
  end

  -- Both other modes would sit on top of this one and fight it for the mouse.
  if type(U.CloseSettings) == "function" then U.CloseSettings() end
  if type(U.IsUnlocked) == "function" and U.IsUnlocked() then U.LockUI() end

  if not shade then CreateShade() end
  if not panel then CreatePanel() end
  if not keys then CreateKeyCatcher() end

  active = true
  restore = {}
  changes = 0
  lastInput, lastInputAt = nil, nil


  local count = ShowCatchers()
  if count == 0 then
    active = false
    U.Print(U.L("QUICKBIND_NO_SLOTS"))
    return false
  end

  -- Escape belongs to the mode from here on; the client's menu gets it back
  -- in U.CloseQuickBind.
  InstallMenuGuard()
  SuspendMenuKeys()

  shade:Show()
  if shade.tex then shade.tex:Show() end
  if type(U.ShowAlignmentGrid) == "function" then U.ShowAlignmentGrid() end
  keys:Show()
  ShowPanel(count)

  U.Print(U.L("QUICKBIND_OPENED"))
  return true
end

-- save = true persists to the client's binding set; anything else restores the
-- bindings to what they were when the mode opened.
function U.CloseQuickBind(save)
  if not active then return false end
  active = false

  local made = changes

  -- Before any save or restore: a binding set written while the menu key is
  -- lifted would persist its absence.
  ReleaseMenuKeys()

  HideTooltip()
  HideCatchers()
  HidePanel()
  if type(U.HideAlignmentGrid) == "function" then U.HideAlignmentGrid() end
  if keys then keys:Hide() end
  if shade then
    if shade.tex then shade.tex:Hide() end
    shade:Hide()
  end

  if save then
    if made > 0 then
      if PersistBindings() then
        U.Print(U.LN("QUICKBIND_SAVED", made))
      end
    else
      restore = {}
      U.Print(U.L("QUICKBIND_NOTHING_CHANGED"))
    end
  else
    if made > 0 then
      RestoreBindings()
      U.Print(U.LN("QUICKBIND_REVERTED", made))
    else
      restore = {}
      U.Print(U.L("QUICKBIND_CLOSED"))
    end
  end

  changes = 0
  return true
end

Close = U.CloseQuickBind

function U.ToggleQuickBind()
  if active then
    U.CloseQuickBind(false)
    return false
  end
  return U.OpenQuickBind()
end

function U.IsQuickBindActive()
  return active
end

-- Reported by /uui check.
function U.QuickBindReport()
  return {
    active = active,
    slots = table.getn(shown),
    changes = changes,
    setBinding = type(U.G("SetBinding")) == "function",
    saveBindings = type(U.G("SaveBindings")) == "function",
    bindingAction = type(U.G("GetBindingAction")) == "function",
    bindingSet = type(U.G("GetCurrentBindingSet")) == "function",
    mouseFocus = type(U.G("GetMouseFocus")) == "function",
    overrideBindings = type(U.ActionOverrideBindingsAvailable) == "function" and
                       U.ActionOverrideBindingsAvailable() or false,
    declaredBindings = type(U.ActionDeclaredBindingsRegistered) == "function" and
                       U.ActionDeclaredBindingsRegistered() or false,
    keyCatcher = keys and true or false,
    menuKeysHeld = table.getn(suspended),
    menuGuard = menuGuardInstalled,
  }
end

function QB:OnEnable()
  -- Keys are the player's combat input. Leaving the mode open into a fight
  -- would swallow them, and SetBinding is not something to be attempting there
  -- either, so the mode closes and keeps what was already done.
  local function CombatExit()
    if not active then return end
    U.CloseQuickBind(true)
    U.Print(U.L("QUICKBIND_COMBAT"))
  end

  U.RegisterEvent("PLAYER_REGEN_DISABLED", CombatExit)
  U.RegisterEvent("PLAYER_ENTER_COMBAT", CombatExit)

  -- A reload or a zone change rebuilds the bars underneath the catchers.
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if active then U.CloseQuickBind(false) end
  end)
end
