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

local styled = false
local order
local chrome
local title
local uuiButton
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

local function EnsureOwnButtons(frame)
  if not uuiButton then
    uuiButton = U.CreateButton(frame, {
      name = "UnrealUIGameMenuButton",
      text = "|cffffffffUnreal|cfff5ae0aUI|r",
      width = BUTTON_WIDTH,
      height = BUTTON_HEIGHT,
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
      onClick = function()
        local hide = U.G("HideUIPanel")
        if type(hide) == "function" then
          pcall(hide, frame)
        else
          pcall(frame.Hide, frame)
        end
        U.OpenSettings(true)
      end,
    })
    RaiseAbove(uuiButton, frame, 20)
  end

  if not closeButton then
    closeButton = U.CreateButton(frame, {
      name = "UnrealUIGameMenuCloseButton",
      text = "Close",
      width = BUTTON_WIDTH,
      height = BUTTON_HEIGHT,
      background = { 0.025, 0.025, 0.025, 0.96 },
      border = { 0.11, 0.11, 0.11, 1 },
      onClick = function()
        local hide = U.G("HideUIPanel")
        if type(hide) == "function" then
          pcall(hide, frame)
        else
          pcall(frame.Hide, frame)
        end
      end,
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
    if button ~= continueBtn and button ~= uuiButton and button ~= closeButton then
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
      inserted = true
    end
    table.insert(result, button)
  end
  if not inserted then table.insert(result, uuiButton) end
  table.insert(result, closeButton)

  -- Replaced by the UnrealUI-owned Close row above.
  if continueBtn then pcall(continueBtn.Hide, continueBtn) end
  return result
end

local function ButtonGroup(button)
  if button == closeButton then return 5 end
  if IsNamed(button, "GameMenuButtonLogout") or
     IsNamed(button, "GameMenuButtonQuit") then return 4 end
  if button == uuiButton or
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
      if button ~= uuiButton and button ~= closeButton then
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
  title:SetText("Options")
  title:SetPoint("TOP", chrome, "TOP", 0, -10)
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

  U.PostHookScript(frame, "OnShow", OnMenuShow)

  local ok, shown = pcall(frame.IsShown, frame)
  if ok and shown then OnMenuShow() end
end
