-- unrealUI :: modules/gamemenu.lua
--
-- UnrealUI-owned presentation for the native GameMenuFrame (Escape menu).
-- The native buttons remain in place as the click targets, preserving every
-- client action, but an opaque mouse-transparent layer replaces their artwork.
--
-- knowledge.json / frames.stock_singletons_structure_nonvanilla: the client
-- can return no GameMenuFrame regions/children and can add its own buttons.
-- Collection is therefore capability-checked and retains the known-global
-- fallback from the working UnrealPfUI game-menu implementation.

local U = UnrealUI
local M = U.media

local G = U.RegisterModule("gamemenu")

local FRAME_WIDTH = 246
local BUTTON_WIDTH = 180
local BUTTON_HEIGHT = 26
local TOP_OFFSET = 34
local BOTTOM_PADDING = 20
local SPACING = 4
local GROUP_SPACING = 18

-- Classic only: this client centres a button label high inside its own button
-- face, so every row of the native menu -- the client's own as well as the two
-- added here -- is nudged down onto the face. USER_CONFIRMED_INGAME.
local CLASSIC_TEXT_Y_OFFSET = -2

-- Classic rows are labelled in white rather than the client's gold, so the
-- redrawn rows and the two added ones read as one menu.
local CLASSIC_TEXT_COLOR = { 1, 1, 1, 1 }

local styled = false
local order
local chrome
local title
local uuiButton
local bindButton
local closeButton

local LABELS = {
  GameMenuButtonOptions = "Video",
  GameMenuButtonSoundOptions = "Sound",
  GameMenuButtonUIOptions = "Interface",
  GameMenuButtonKeybindings = "Key Bindings",
  GameMenuButtonMacros = "Macros",
  GameMenuButtonAddOns = "AddOns",
  GameMenuButtonHelp = "Help / Report Bug",
  GameMenuButtonLogout = "Logout",
  GameMenuButtonQuit = "Exit Game",
  GameMenuButtonContinue = "Close",
}

local function IsNamed(button, name)
  return button and button == U.G(name)
end

local function RaiseAbove(frame, owner, amount)
  if not frame or not owner then return end
  local ok, level = pcall(owner.GetFrameLevel, owner)
  if ok and tonumber(level) then
    pcall(frame.SetFrameLevel, frame, tonumber(level) + (amount or 1))
  end
end

local function NativeText(button)
  local name
  pcall(function() name = button:GetName() end)
  if name and LABELS[name] then return LABELS[name] end

  local text
  if button.GetText then pcall(function() text = button:GetText() end) end
  if not text and button.GetFontString then
    local fontstring
    pcall(function() fontstring = button:GetFontString() end)
    if fontstring and fontstring.GetText then
      pcall(function() text = fontstring:GetText() end)
    end
  end

  if type(text) ~= "string" or text == "" then return "Option" end
  return string.gsub(text, " Options$", "")
end

-- The cover is a child frame above every native draw layer. EnableMouse(false)
-- leaves the original button as the physical click target, while the opaque
-- fill guarantees that late-restored red/stone button faces cannot show.
local function StyleNativeButton(button)
  if not button then return end

  local cover = button.uuiGameMenuCover
  if not cover then
    cover = CreateFrame("Frame", nil, button)
    cover:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    cover:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    pcall(cover.EnableMouse, cover, false)
    RaiseAbove(cover, button, 10)
    U.CreateBackdrop(cover, {
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
    })

    local label = U.CreateLabel(cover, {
      size = M.fontSize.normal,
      color = M.color.text,
      inherits = "GameFontNormal",
    })
    label:SetPoint("CENTER", cover, "CENTER", 0, 0)
    cover.label = label
    button.uuiGameMenuCover = cover

    U.PostHookScript(button, "OnEnter", function()
      U.SetBorderColor(cover, M.Unpack(M.color.accent))
    end)
    U.PostHookScript(button, "OnLeave", function()
      U.SetBorderColor(cover, 0.11, 0.11, 0.11, 1)
    end)
  end

  -- Native OnShow/update code can restore faces; clear what is enumerable as
  -- well as keeping the opaque cover above anything that is not enumerable.
  U.RefreshStockButtonArtwork(button)
  cover.label:SetText(NativeText(button))

  local enabled = true
  if button.IsEnabled then
    local ok, value = pcall(button.IsEnabled, button)
    if ok then enabled = value and value ~= 0 end
  end
  pcall(cover.label.SetTextColor, cover.label,
        M.Unpack(enabled and M.color.text or M.color.textDim))
  cover:Show()
end

local function CollectButtons(frame)
  local buttons, seen = {}, {}

  local function Add(button)
    if not button or seen[button] then return end
    local ok, objType = pcall(button.GetObjectType, button)
    if not ok or objType ~= "Button" then return end
    seen[button] = true
    table.insert(buttons, button)
  end

  local scanOk = pcall(function()
    local _, child
    for _, child in ipairs({ frame:GetChildren() }) do Add(child) end
  end)

  if not scanOk or table.getn(buttons) == 0 then
    local known = {
      "GameMenuButtonContinue", "GameMenuButtonOptions", "GameMenuButtonUIOptions",
      "GameMenuButtonSoundOptions", "GameMenuButtonKeybindings", "GameMenuButtonMacros",
      "GameMenuButtonAddOns", "GameMenuButtonShop", "GameMenuButtonRatings",
      "GameMenuButtonHelp",
      "GameMenuButtonLogout", "GameMenuButtonQuit",
    }
    local i
    for i = 1, table.getn(known) do Add(U.G(known[i])) end
  end

  return buttons
end

local function HideMenu(frame)
  local hide = U.G("HideUIPanel")
  if type(hide) == "function" then
    pcall(hide, frame)
  else
    pcall(frame.Hide, frame)
  end
end

local function OpenSettingsPanel(frame)
  HideMenu(frame)
  U.OpenSettings(true)
end

local function OpenQuickBinding(frame)
  HideMenu(frame)
  if type(U.OpenQuickBind) == "function" then
    U.OpenQuickBind()
  else
    U.Error(U.L("QUICKBIND_UNAVAILABLE"))
  end
end

local function EnsureOwnButtons(frame)
  if not uuiButton then
    uuiButton = U.CreateButton(frame, {
      name = "UnrealUIGameMenuButton",
      text = "|cffffffffUnreal|cfff5ae0aUI|r",
      width = BUTTON_WIDTH,
      height = BUTTON_HEIGHT,
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
      onClick = function() OpenSettingsPanel(frame) end,
    })
    RaiseAbove(uuiButton, frame, 20)
  end

  -- Quick binding sits directly under the UnrealUI row: it is a mode, not a
  -- settings page, so it opens straight from here instead of through the
  -- settings window (which it would only have to close again).
  if not bindButton then
    bindButton = U.CreateButton(frame, {
      name = "UnrealUIGameMenuQuickBindButton",
      text = U.L("SETTINGS_QUICKBIND"),
      width = BUTTON_WIDTH,
      height = BUTTON_HEIGHT,
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
      onClick = function() OpenQuickBinding(frame) end,
    })
    RaiseAbove(bindButton, frame, 20)
  end

  if not closeButton then
    closeButton = U.CreateButton(frame, {
      name = "UnrealUIGameMenuCloseButton",
      text = U.L("COMMON_CLOSE"),
      width = BUTTON_WIDTH,
      height = BUTTON_HEIGHT,
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
      onClick = function() HideMenu(frame) end,
    })
    RaiseAbove(closeButton, frame, 20)
  end
end

local function CaptureOrder(frame, buttons)
  EnsureOwnButtons(frame)

  local continueBtn = U.G("GameMenuButtonContinue")
  local sorted = {}
  local i
  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    if button ~= continueBtn and button ~= uuiButton and
       button ~= bindButton and button ~= closeButton then
      table.insert(sorted, button)
    end
  end

  table.sort(sorted, function(a, b)
    local at, bt
    pcall(function() at = a:GetTop() end)
    pcall(function() bt = b:GetTop() end)
    return (at or 0) > (bt or 0)
  end)

  local result, inserted = {}, false
  for i = 1, table.getn(sorted) do
    local button = sorted[i]
    if not inserted and (IsNamed(button, "GameMenuButtonLogout") or
                         IsNamed(button, "GameMenuButtonQuit")) then
      table.insert(result, uuiButton)
      table.insert(result, bindButton)
      inserted = true
    end
    table.insert(result, button)
  end
  if not inserted then
    table.insert(result, uuiButton)
    table.insert(result, bindButton)
  end
  table.insert(result, closeButton)

  -- Replaced by the UnrealUI-owned Close row above.
  if continueBtn then pcall(continueBtn.Hide, continueBtn) end
  return result
end

local function ButtonGroup(button)
  if button == closeButton then return 5 end
  if IsNamed(button, "GameMenuButtonLogout") or
     IsNamed(button, "GameMenuButtonQuit") then return 4 end
  if button == uuiButton or button == bindButton or
     IsNamed(button, "GameMenuButtonKeybindings") or
     IsNamed(button, "GameMenuButtonMacros") or
     IsNamed(button, "GameMenuButtonAddOns") then return 3 end
  if IsNamed(button, "GameMenuButtonOptions") or
     IsNamed(button, "GameMenuButtonSoundOptions") or
     IsNamed(button, "GameMenuButtonUIOptions") then return 2 end
  return 1
end

local function Layout(frame)
  order = order or CaptureOrder(frame, CollectButtons(frame))

  local continueBtn = U.G("GameMenuButtonContinue")
  if continueBtn then pcall(continueBtn.Hide, continueBtn) end

  local previous
  local previousGroup
  local height = TOP_OFFSET
  local i

  for i = 1, table.getn(order) do
    local button = order[i]
    local shown = true
    pcall(function() shown = button:IsShown() and true or false end)

    if shown then
      if button ~= uuiButton and button ~= bindButton and
         button ~= closeButton then
        StyleNativeButton(button)
      end

      button:ClearAllPoints()
      pcall(button.SetWidth, button, BUTTON_WIDTH)
      pcall(button.SetHeight, button, BUTTON_HEIGHT)

      local group = ButtonGroup(button)
      if previous then
        local gap = group ~= previousGroup and GROUP_SPACING or SPACING
        button:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
        height = height + gap
      else
        button:SetPoint("TOP", frame, "TOP", 0, -TOP_OFFSET)
      end

      height = height + BUTTON_HEIGHT
      previous = button
      previousGroup = group
    end
  end

  frame:SetWidth(FRAME_WIDTH)
  frame:SetHeight(height + BOTTOM_PADDING)
end

local function BuildChrome(frame)
  U.StripStockTextures(frame)
  pcall(frame.SetBackdrop, frame, nil)
  pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)

  chrome = U.CreatePanel(frame, {
    name = "UnrealUIGameMenuChrome",
    background = { 0.04, 0.04, 0.04, 0.40 },
    border = { 0.10, 0.10, 0.10, 1 },
  })
  chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  chrome:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  pcall(chrome.EnableMouse, chrome, false)
  RaiseAbove(chrome, frame, 5)

  title = U.CreateLabel(chrome, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  title:SetText(U.L("GAMEMENU_OPTIONS"))
  title:SetPoint("TOP", chrome, "TOP", 0, -10)
end

-- Classic WoW keeps the client's own menu chrome, so none of the restyling
-- above runs there. The UnrealUI and Quick Binding rows are addon access
-- rather than decoration, so Classic still gets them: they are built from the
-- client's own menu-button template (with its faces copied by hand when that
-- template is unavailable, as UnrealPfUI's menu entry has to do here), placed
-- above the client's "Return to Game" row, and the frame is grown to fit.
--
-- Everything else on the frame is left exactly as the client drew it.
local classicMenu = {}

function classicMenu.Number(object, method)
  if not object or not object[method] then return nil end
  local ok, value = pcall(object[method], object)
  if not ok then return nil end
  return tonumber(value)
end

-- USER_CONFIRMED_INGAME: EnableMouse(false) on a sibling Button above these
-- native rows does not pass input through on this client. Keep the replacement
-- face below the transparent native row instead, so engine-dispatched clicks
-- still reach the row's original handler (including handlers that read the
-- client's implicit `this` rather than their Lua argument).
function classicMenu.PlaceVisualBelow(visual, row)
  local rowLevel = classicMenu.Number(row, "GetFrameLevel")
  local visualLevel = classicMenu.Number(visual, "GetFrameLevel")
  if rowLevel and visualLevel and visualLevel >= rowLevel then
    -- Child frame levels can be clamped to their parent's level, so lowering
    -- the visual is not sufficient. Raise the transparent native target one
    -- level instead; subsequent passes leave the stable ordering untouched.
    pcall(row.SetFrameLevel, row, visualLevel + 1)
  end
end

function classicMenu.CopyFace(button, source, getter, setter)
  if not button or not source then return end
  if not button[setter] or not source[getter] then return end

  local ok, region = pcall(source[getter], source)
  if not ok or not region or not region.GetTexture then return end

  local pathOk, path = pcall(region.GetTexture, region)
  if not pathOk or type(path) ~= "string" or path == "" then return end
  if not pcall(button[setter], button, path) then return end

  -- The stock faces are slices of a shared file. Copy the coordinates when
  -- this client exposes them; when it does not, the whole file is left in
  -- place rather than guessing an atlas rectangle.
  if not region.GetTexCoord then return end
  local applied
  local appliedOk, value = pcall(button[getter], button)
  if appliedOk then applied = value end
  if not applied or not applied.SetTexCoord then return end

  local coord = { pcall(region.GetTexCoord, region) }
  if coord[1] and table.getn(coord) == 9 then
    pcall(applied.SetTexCoord, applied, coord[2], coord[3], coord[4], coord[5],
          coord[6], coord[7], coord[8], coord[9])
  end
end

-- The rows this module owns are recognised by name as well as by identity.
-- /uui menu showed both of them coming back out of GetChildren() as native
-- rows even though they were stored here, so the layout re-anchored them into
-- a cycle and threw them off screen (top -104252). Whatever makes the stored
-- reference and the enumerated child compare unequal on this client, the name
-- is the client's own and cannot drift.
classicMenu.OWN = {
  ["UnrealUIGameMenuButton"] = true,
  ["UnrealUIGameMenuQuickBindButton"] = true,
}

function classicMenu.NameOf(object)
  if not object or not object.GetName then return nil end
  local name
  pcall(function() name = object:GetName() end)
  if type(name) ~= "string" then return nil end
  return name
end

function classicMenu.IsOwn(button)
  if not button then return false end
  if button == classicMenu.settings or button == classicMenu.bind then
    return true
  end
  if button.uuiClassicMenuVisual then return true end
  if button.uuiClassicMenuRow then return true end

  local name = classicMenu.NameOf(button)
  return (name and classicMenu.OWN[name]) and true or false
end

function classicMenu.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, value = pcall(object.IsShown, object)
  return (ok and value and value ~= 0) and true or false
end

function classicMenu.HasFace(button)
  if not button or not button.GetNormalTexture then return false end
  local ok, texture = pcall(button.GetNormalTexture, button)
  if not ok or not texture or not texture.GetTexture then return false end
  local pathOk, path = pcall(texture.GetTexture, texture)
  return (pathOk and type(path) == "string" and path ~= "") and true or false
end

function classicMenu.FindTemplate(frame)
  local known = {
    "GameMenuButtonContinue", "GameMenuButtonOptions", "GameMenuButtonKeybindings",
    "GameMenuButtonLogout", "GameMenuButtonQuit",
  }
  local i
  for i = 1, table.getn(known) do
    local button = U.G(known[i])
    if button then return button end
  end

  local buttons = CollectButtons(frame)
  return buttons[1]
end

-- The client's own fontstring is the label whenever the button has one.
--
-- /uui menu showed a button built from the client's menu template carrying its
-- own fontstring while this module held a second one it had created: both drew
-- the same text, and only the module's copy moved, so the visible label never
-- shifted. GetFontString() can still be nil at creation time, so the lookup is
-- repeated on every pass and the created fallback is dropped as soon as the
-- client's own label is carrying the text.
function classicMenu.Label(button)
  if not button then return nil end

  local fontstring
  if button.GetFontString then
    local ok, value = pcall(button.GetFontString, button)
    if ok then fontstring = value end
  end
  if not fontstring or fontstring == button.uuiLabel then
    return button.uuiLabel or fontstring
  end

  local text
  pcall(function() text = fontstring:GetText() end)
  if type(text) ~= "string" or text == "" then
    -- The client's label is not carrying the text yet; keep drawing our own.
    return button.uuiLabel or fontstring
  end

  local spare = button.uuiLabel
  if spare and spare ~= fontstring then
    pcall(spare.SetText, spare, "")
    pcall(spare.Hide, spare)
    button.uuiLabel = nil
  end
  return fontstring
end

function classicMenu.SetLabelText(button, text)
  if not button then return end
  button.uuiText = text or button.uuiText

  if button.SetText then pcall(button.SetText, button, button.uuiText) end

  local label = classicMenu.Label(button)
  if not label then
    if not button.CreateFontString then return end
    label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pcall(button.SetFontString, button, label)
    button.uuiLabel = label
  end

  local applied
  pcall(function() applied = label:GetText() end)
  if applied ~= button.uuiText then
    pcall(label.SetText, label, button.uuiText)
  end
  pcall(label.SetTextColor, label, M.Unpack(CLASSIC_TEXT_COLOR))
end

-- Re-applied on every layout pass, not only at creation: a label owned by the
-- client's template is the client's to move, and an anchor set once at
-- creation is not guaranteed to survive its next pass over the frame.
function classicMenu.AlignLabel(button)
  local label = classicMenu.Label(button)
  if not label or not label.SetPoint then return end

  pcall(label.ClearAllPoints, label)
  pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0,
        CLASSIC_TEXT_Y_OFFSET)
end

function classicMenu.RowText(row)
  local text
  if row and row.GetText then pcall(function() text = row:GetText() end) end

  if type(text) ~= "string" or text == "" then
    local label = classicMenu.Label(row)
    if label and label.GetText then
      pcall(function() text = label:GetText() end)
    end
  end
  if type(text) ~= "string" then text = "" end
  return text
end

-- Build the same template-backed visual used by the two addon-owned rows. It is
-- a sibling rather than a child so the native row can be made fully transparent
-- without also hiding this replacement.
function classicMenu.CreateRowVisual(row)
  local parent
  pcall(function() parent = row:GetParent() end)
  if not parent then parent = U.G("GameMenuFrame") end
  if not parent then return nil end

  local visual
  pcall(function()
    visual = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
  end)
  if not visual then visual = CreateFrame("Button", nil, parent) end
  if not visual then return nil end

  visual.uuiClassicMenuVisual = true
  pcall(visual.EnableMouse, visual, false)

  if not classicMenu.HasFace(visual) then
    local source = classicMenu.settings or classicMenu.bind or classicMenu.template
    classicMenu.CopyFace(visual, source, "GetNormalTexture", "SetNormalTexture")
    classicMenu.CopyFace(visual, source, "GetPushedTexture", "SetPushedTexture")
    classicMenu.CopyFace(visual, source, "GetHighlightTexture", "SetHighlightTexture")
  end

  if not classicMenu.HasFace(visual) then
    U.CreateBackdrop(visual, {
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
    })
  end

  classicMenu.PlaceVisualBelow(visual, row)

  -- The visual remains mouse-transparent and below the real target. Mirror the
  -- native row's interaction state onto it. All calls are capability-checked.
  U.PostHookScript(row, "OnEnter", function()
    if visual.LockHighlight then pcall(visual.LockHighlight, visual) end
  end)
  U.PostHookScript(row, "OnLeave", function()
    if visual.UnlockHighlight then pcall(visual.UnlockHighlight, visual) end
  end)
  U.PostHookScript(row, "OnMouseDown", function()
    if visual.SetButtonState then
      pcall(visual.SetButtonState, visual, "PUSHED")
    end
  end)
  U.PostHookScript(row, "OnMouseUp", function()
    if visual.SetButtonState then
      pcall(visual.SetButtonState, visual, "NORMAL")
    end
  end)

  return visual
end

-- The original row remains shown, enabled and anchored as the physical click
-- target, but alpha zero removes every piece of its independently rendered art
-- and text. The visible sibling behind it is a real GameMenuButtonTemplate,
-- just like Unreal UI and Quick Binding. This avoids Button:Click, which is
-- RUNTIME_FAILURE_CONFIRMED broken on this client
-- (behavior.json / loot.native_button_click.v1).
function classicMenu.CoverRow(row)
  if not row then return end

  if not row.uuiRowText or row.uuiRowText == "" then
    row.uuiRowText = classicMenu.RowText(row)
  end

  local visual = row.uuiRowVisual
  if not visual then
    visual = classicMenu.CreateRowVisual(row)
    row.uuiRowVisual = visual
  end
  if not visual then return end

  local width = classicMenu.Number(row, "GetWidth")
  local height = classicMenu.Number(row, "GetHeight")
  if width and width > 0 then pcall(visual.SetWidth, visual, width) end
  if height and height > 0 then pcall(visual.SetHeight, visual, height) end
  visual:ClearAllPoints()
  visual:SetPoint("CENTER", row, "CENTER", 0, 0)
  classicMenu.PlaceVisualBelow(visual, row)
  classicMenu.SetLabelText(visual, row.uuiRowText)
  classicMenu.AlignLabel(visual)
  if visual.SetButtonState then
    pcall(visual.SetButtonState, visual, "NORMAL")
  end
  visual:Show()

  -- Re-applied on every layout pass because the native menu may restore alpha
  -- while rebuilding its rows. Alpha does not remove the button or its scripts.
  pcall(row.SetAlpha, row, 0)
end

function classicMenu.CreateButton(frame, name, text, onClick)
  -- A button under this name from an earlier pass is reused rather than
  -- replaced: creating a second one would leave the first orphaned on the
  -- frame, still drawing, with the global pointing at the newer object.
  local button = U.G(name)
  if not button then
    pcall(function()
      button = CreateFrame("Button", name, frame, "GameMenuButtonTemplate")
    end)
  end
  if not button then button = CreateFrame("Button", name, frame) end
  if not button then return nil end
  button.uuiClassicMenuRow = true

  -- A template button already carries the client's faces; anything else has
  -- them copied off a real menu row.
  if not classicMenu.HasFace(button) then
    local source = classicMenu.template
    classicMenu.CopyFace(button, source, "GetNormalTexture", "SetNormalTexture")
    classicMenu.CopyFace(button, source, "GetPushedTexture", "SetPushedTexture")
    classicMenu.CopyFace(button, source, "GetHighlightTexture", "SetHighlightTexture")
  end

  if not classicMenu.HasFace(button) then
    -- This client exposed no reusable menu-button art. A visible row beats an
    -- invisible one, so it falls back to UnrealUI's own flat surface.
    U.CreateBackdrop(button, {
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
    })
    U.Debug("classic game menu: no native button face, using the flat fallback")
  end

  classicMenu.SetLabelText(button, text)
  classicMenu.AlignLabel(button)

  button:SetScript("OnClick", onClick)

  -- A size and a point before the first layout: a plain button starts at 0x0
  -- and unanchored, which would leave the row invisible if the layout pass
  -- below it never ran. Both are replaced the moment it does.
  local width = classicMenu.Number(classicMenu.template, "GetWidth")
  local height = classicMenu.Number(classicMenu.template, "GetHeight")
  pcall(button.SetWidth, button, (width and width > 0) and width or BUTTON_WIDTH)
  pcall(button.SetHeight, button, (height and height > 0) and height or BUTTON_HEIGHT)
  button:ClearAllPoints()
  button:SetPoint("BOTTOM", frame, "BOTTOM", 0, BOTTOM_PADDING)

  -- The client can draw menu art above a plain child, exactly as the Modern
  -- path has to allow for, so the row is lifted clear of the frame.
  RaiseAbove(button, frame, 20)
  button:Show()
  return button
end

function classicMenu.Ensure(frame)
  if classicMenu.settings and classicMenu.bind then return end
  classicMenu.template = classicMenu.template or classicMenu.FindTemplate(frame)

  classicMenu.settings = classicMenu.settings or classicMenu.CreateButton(
    frame, "UnrealUIGameMenuButton", "|cffffffffUnreal|cfff5ae0aUI|r",
    function() OpenSettingsPanel(frame) end)

  classicMenu.bind = classicMenu.bind or classicMenu.CreateButton(
    frame, "UnrealUIGameMenuQuickBindButton", "Quick Binding",
    function() OpenQuickBinding(frame) end)
end

-- Native rows, top to bottom, excluding the two UnrealUI adds.
function classicMenu.Rows(frame)
  local buttons = CollectButtons(frame)
  local rows = {}
  local i
  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    if not classicMenu.IsOwn(button) and classicMenu.Shown(button) then
      table.insert(rows, button)
    end
  end

  table.sort(rows, function(a, b)
    local at, bt
    pcall(function() at = a:GetTop() end)
    pcall(function() bt = b:GetTop() end)
    return (at or 0) > (bt or 0)
  end)
  return rows
end

-- The client's own spacing is read once, from the untouched native layout, and
-- kept per row. Measuring again later would read back the gaps this module
-- opened itself. The ordinary row spacing is the smallest of them; anything
-- larger is one of the client's own group breaks.
function classicMenu.MeasureGaps(rows)
  if classicMenu.measured then return end
  classicMenu.measured = true
  classicMenu.gap = {}

  local smallest
  local i
  for i = 2, table.getn(rows) do
    local bottom = classicMenu.Number(rows[i - 1], "GetBottom")
    local top = classicMenu.Number(rows[i], "GetTop")
    if bottom and top and bottom >= top then
      local gap = bottom - top
      classicMenu.gap[rows[i]] = gap
      if not smallest or gap < smallest then smallest = gap end
    end
  end

  classicMenu.rowGap = smallest or 1
end

-- The seat is the row directly above "Return to Game", which is where the
-- Modern menu shows the same pair: this client does not present its Logout and
-- Exit Game buttons as the globals that path checks for, so both menus resolve
-- their seat from the closing row instead and stay identical.
function classicMenu.FollowerIndex(rows)
  local count = table.getn(rows)
  local i
  for i = 2, count do
    if classicMenu.NameOf(rows[i]) == "GameMenuButtonContinue" then return i end
  end

  for i = 2, count do
    local name = classicMenu.NameOf(rows[i])
    if name == "GameMenuButtonLogout" or name == "GameMenuButtonQuit" then
      return i
    end
  end
  return nil
end

function classicMenu.Layout()
  local frame = U.G("GameMenuFrame")
  if not frame then return end

  classicMenu.Ensure(frame)
  if not classicMenu.settings or not classicMenu.bind then return end

  local rows = classicMenu.Rows(frame)
  local count = table.getn(rows)
  if count == 0 then return end

  classicMenu.layouts = (classicMenu.layouts or 0) + 1
  classicMenu.MeasureGaps(rows)
  local rowGap = classicMenu.rowGap

  local index = classicMenu.FollowerIndex(rows)
  local anchor = index and rows[index - 1] or rows[count]
  if classicMenu.IsOwn(anchor) then return end
  local followerGap = index and classicMenu.gap[rows[index]] or nil

  -- The pair reads as its own block: the break above and below it is the
  -- client's own group spacing, or UnrealUI's when this menu has none.
  local separation = followerGap or 0
  if separation < GROUP_SPACING then separation = GROUP_SPACING end

  local width = classicMenu.Number(anchor, "GetWidth")
  local height = classicMenu.Number(anchor, "GetHeight")
  local own = { classicMenu.settings, classicMenu.bind }
  local previous = anchor
  local i
  for i = 1, table.getn(own) do
    local button = own[i]
    if width and width > 0 then pcall(button.SetWidth, button, width) end
    if height and height > 0 then pcall(button.SetHeight, button, height) end
    button:ClearAllPoints()
    button:SetPoint("TOP", previous, "BOTTOM", 0, i == 1 and -separation or -rowGap)
    classicMenu.SetLabelText(button)
    classicMenu.AlignLabel(button)
    button:Show()
    previous = button
  end

  -- Every row below the seat is re-anchored down the chain with the spacing it
  -- started with, so the native rows cannot overlap the inserted block whether
  -- the client anchored them to each other or to the frame.
  if index then
    for i = index, count do
      local row = rows[i]
      local gap = (i == index) and separation or (classicMenu.gap[row] or rowGap)
      row:ClearAllPoints()
      row:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
      previous = row
    end
  end

  -- Every row's label, not only the two added here: the client sits them all
  -- high on the face, and half a menu nudged would read worse than none.
  for i = 1, count do classicMenu.CoverRow(rows[i]) end

  local rowHeight = height or
                    classicMenu.Number(classicMenu.settings, "GetHeight") or 22
  local added = separation + rowGap + 2 * rowHeight
  if index then added = added + separation - (followerGap or rowGap) end

  U.Debug("classic game menu: seat " .. tostring(index) .. "/" .. count ..
          ", gap " .. tostring(rowGap) .. ", break " .. tostring(separation) ..
          ", added " .. tostring(added))

  local current = classicMenu.Number(frame, "GetHeight")
  if current then
    -- The client can recompute the menu height itself when its visible rows
    -- change; only a height this module set is treated as already grown.
    if classicMenu.appliedHeight and classicMenu.baseHeight and
       math.abs(current - classicMenu.appliedHeight) < 0.5 then
      current = classicMenu.baseHeight
    end
    classicMenu.baseHeight = current
    classicMenu.appliedHeight = current + added
    pcall(frame.SetHeight, frame, classicMenu.appliedHeight)
  end
end

-- Diagnostic for /uui menu. The classic rows depend on client behaviour that
-- compact evidence does not describe -- whether the menu template exists,
-- whether an OnShow hook survives, what the frame really parents -- so the
-- state they depend on is reportable rather than something to guess at.
function U.DumpGameMenu()
  local frame = U.G("GameMenuFrame")
  U.Print("game menu: " .. (frame and "found" or "|cffff5555missing|r") ..
          ", theme " .. U.GetActiveThemeStyle() ..
          ", native chrome " .. tostring(U.ThemeStyleUsesNativeChrome()))
  if not frame then return end

  U.Print("frame: shown " .. tostring(classicMenu.Shown(frame)) ..
          ", height " .. tostring(classicMenu.Number(frame, "GetHeight")) ..
          ", level " .. tostring(classicMenu.Number(frame, "GetFrameLevel")) ..
          ", layouts " .. tostring(classicMenu.layouts or 0))

  local names = { "UnrealUIGameMenuButton", "UnrealUIGameMenuQuickBindButton" }
  local i
  for i = 1, table.getn(names) do
    local button = U.G(names[i])
    if not button then
      U.Print(names[i] .. ": |cffff5555not created|r")
    else
      local point, relative, relativePoint, x, y
      pcall(function() point, relative, relativePoint, x, y = button:GetPoint(1) end)
      local relativeName
      if relative then pcall(function() relativeName = relative:GetName() end) end
      U.Print(names[i] .. ": shown " .. tostring(classicMenu.Shown(button)) ..
              ", face " .. tostring(classicMenu.HasFace(button)) ..
              ", " .. tostring(classicMenu.Number(button, "GetWidth")) .. "x" ..
              tostring(classicMenu.Number(button, "GetHeight")) ..
              ", level " .. tostring(classicMenu.Number(button, "GetFrameLevel")))
      local label = classicMenu.Label(button)
      local own = button.uuiLabel
      local fontstring
      if button.GetFontString then
        pcall(function() fontstring = button:GetFontString() end)
      end
      local lp, lrel, lrelPoint, lx, ly
      if label then
        pcall(function() lp, lrel, lrelPoint, lx, ly = label:GetPoint(1) end)
      end
      local labelText, buttonText
      if label then pcall(function() labelText = label:GetText() end) end
      if button.GetText then pcall(function() buttonText = button:GetText() end) end
      U.Print("  aligned " .. tostring(label) .. ", spare " ..
              tostring(own) .. ", fontstring " ..
              tostring(fontstring) .. ", text [" .. tostring(labelText) ..
              "] button text [" .. tostring(buttonText) .. "]")
      U.Print("  label anchored " .. tostring(lp) .. " to " ..
              tostring(lrelPoint) .. " " .. tostring(lx) .. "," ..
              tostring(ly) .. ", height " ..
              tostring(classicMenu.Number(label, "GetHeight")))
      U.Print("  object " .. tostring(button) .. ", stored " ..
              tostring(classicMenu.settings) .. "/" ..
              tostring(classicMenu.bind))
      U.Print("  anchored " .. tostring(point) .. " to " ..
              tostring(relativeName or relative) .. " " ..
              tostring(relativePoint) .. " " .. tostring(x) .. "," ..
              tostring(y) .. ", top " ..
              tostring(classicMenu.Number(button, "GetTop")))
    end
  end

  local rows = classicMenu.Rows(frame)
  U.Print("native rows shown: " .. table.getn(rows))
  for i = 1, table.getn(rows) do
    local name
    pcall(function() name = rows[i]:GetName() end)
    local text
    if rows[i].GetText then pcall(function() text = rows[i]:GetText() end) end
    U.Print("  " .. i .. ". " .. tostring(name or "unnamed") .. " [" ..
            tostring(text) .. "] top " ..
            tostring(classicMenu.Number(rows[i], "GetTop")) .. " " ..
            tostring(rows[i]))
  end
end

local function OnMenuShow()
  local frame = U.G("GameMenuFrame")
  if not frame then return end

  if not styled then
    styled = true
    BuildChrome(frame)
  end

  -- The client can repaint stock regions when the menu opens. The opaque
  -- chrome and button covers are retained; this clears whatever is exposed.
  U.StripStockTextures(frame)
  local header = U.G("GameMenuFrameHeader")
  if header then U.HideRegion(header) end
  Layout(frame)
end

function G:OnEnable()
  local frame = U.G("GameMenuFrame")
  if not frame then return end

  if not U.ThemeStyleUsesNativeChrome() then
    U.PostHookScript(frame, "OnShow", OnMenuShow)
    if classicMenu.Shown(frame) then OnMenuShow() end
    return
  end

  -- Classic keeps the client's menu and only gains the two UnrealUI rows.
  --
  -- The rows are built here rather than on first show, so they exist even if
  -- this client never runs the hook below, and the layout is additionally
  -- driven by the shared ticker while the menu is open: a script this module
  -- installs is not guaranteed to survive whatever the client sets afterwards,
  -- and the rows must not depend on a single hook to appear at all.
  classicMenu.Ensure(frame)
  U.PostHookScript(frame, "OnShow", classicMenu.Layout)

  U.RegisterUpdate("gamemenu.classic", 0.2, function()
    if not classicMenu.Shown(frame) then
      classicMenu.passes = 0
      return
    end
    -- A few passes per opening, not one: the client can finish its own menu
    -- update after the first, and the layout is idempotent.
    classicMenu.passes = (classicMenu.passes or 0) + 1
    if classicMenu.passes > 3 then return end
    classicMenu.Layout()
  end)

  if classicMenu.Shown(frame) then classicMenu.Layout() end
end
