-- unrealUI :: modules/supportpopup.lua
--
-- A one-time reminder, a few seconds after login, asking the player to like
-- UnrealUI in the launcher (user request, 2026-11-26, after unrealMap's
-- SupportPopup.lua). "I already liked it" stops it for good, account-wide
-- (U.SupportPopupDismissed in core/config.lua); "OK, I will add a like" only
-- closes it until the next login.
--
-- Drawn with UnrealUI's shared components rather than unrealMap's copied art:
-- under `modern-wow` the metal housing and the game settings 128RedButton
-- face (U.StyleGameSettingsWidgets); under the other themes the flat panel
-- and buttons. Nothing is built for a dismissed popup.

local U = UnrealUI
local M = U.media

local G = U.RegisterModule("supportpopup")

local support = {
  delay = 6,
  width = 368,
  height = 148,
  textWidth = 312,
  buttonHeight = 30,
  buttonBottom = 16,
  thanksGap = 6,
  title = "|cffffffffUnreal |cfff5ae0aUI|r",
}

-- Side by side with the other Unreal addons' like popups (unrealQuest,
-- unrealMap all show theirs a few seconds after login, centred). Shared
-- protocol, identical in each addon: every popup adds its frame once to the
-- global UnrealSupportPopups list, and showing or hiding one re-lays every
-- shown popup in centred rows, wrapping when a row would leave the screen.
support.gap = 12

function support.Layout()
  local list = UnrealSupportPopups
  if type(list) ~= "table" then return end
  local shown = {}
  local width, height = 0, 0
  local i
  for i = 1, table.getn(list) do
    local f = list[i]
    local ok, visible = pcall(f.IsShown, f)
    if ok and visible then
      table.insert(shown, f)
      local okW, w = pcall(f.GetWidth, f)
      local okH, h = pcall(f.GetHeight, f)
      w = okW and tonumber(w) or 0
      h = okH and tonumber(h) or 0
      if w > width then width = w end
      if h > height then height = h end
    end
  end
  local n = table.getn(shown)
  if n == 0 then return end

  local gap = support.gap
  local okP, screen = pcall(UIParent.GetWidth, UIParent)
  screen = okP and tonumber(screen) or 0
  local perRow = n
  if screen > 0 and width > 0 then
    perRow = math.floor((screen - gap) / (width + gap))
    if perRow < 1 then perRow = 1 end
    if perRow > n then perRow = n end
  end
  local rows = math.ceil(n / perRow)
  for i = 1, n do
    local row = math.floor((i - 1) / perRow)
    local col = (i - 1) - row * perRow
    local inRow = math.min(perRow, n - row * perRow)
    local x = (col - (inRow - 1) / 2) * (width + gap)
    local y = ((rows - 1) / 2 - row) * (height + gap)
    pcall(shown[i].ClearAllPoints, shown[i])
    pcall(shown[i].SetPoint, shown[i], "CENTER", UIParent, "CENTER", x, y)
  end
end

function support.Register(frame)
  if type(UnrealSupportPopups) ~= "table" then UnrealSupportPopups = {} end
  local i
  for i = 1, table.getn(UnrealSupportPopups) do
    if UnrealSupportPopups[i] == frame then return end
  end
  table.insert(UnrealSupportPopups, frame)
end

function support.ModernWow()
  return type(U.GetActiveThemeStyle) == "function" and
         U.GetActiveThemeStyle() == "modern-wow" and
         type(U.ModernWowMetalFrame) == "function" and
         type(U.StyleGameSettingsWidgets) == "function"
end

-- Fonts and colours are the stock templates unrealQuest's and unrealMap's
-- popups use, so the three read as one set side by side (user request,
-- 2026-11-26): GameFontNormalLarge title, GameFontHighlight lines, white
-- GameFontNormal button text.
function support.Label(frame, template, text)
  local ok, label = pcall(frame.CreateFontString, frame, nil, "OVERLAY", template)
  if not ok or not label then return nil end
  pcall(label.SetWidth, label, support.textWidth)
  pcall(label.SetJustifyH, label, "CENTER")
  pcall(label.SetText, label, text)
  return label
end

-- The button's own label is retired: the game settings face repaints
-- button.label in its gold on every state change (gs.PaintButton).
function support.ButtonText(button, text)
  if button.label then
    pcall(button.label.SetText, button.label, "")
    pcall(button.label.Hide, button.label)
    button.label = nil
  end
  local ok, label = pcall(button.CreateFontString, button, nil, "OVERLAY",
                          "GameFontNormal")
  if not ok or not label then return nil end
  pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0, 0)
  pcall(label.SetTextColor, label, 1, 1, 1)
  pcall(label.SetText, label, text)
  return label
end

function support.Build()
  local modernWow = support.ModernWow()
  local width, height = support.width, support.height

  local frame = U.CreatePanel(UIParent, {
    name = "UnrealUISupportPopup",
    width = width,
    height = height,
  })
  pcall(frame.SetFrameStrata, frame, "DIALOG")
  pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
  pcall(frame.EnableMouse, frame, true)
  if modernWow and U.ModernWowMetalFrame(frame, width, height, true) then
    U.SetBackdropShown(frame, false)
  end

  local parts = {}
  local title = support.Label(frame, "GameFontNormalLarge", support.title)
  if title then
    pcall(title.SetPoint, title, "TOP", frame, "TOP", 0, -20)
    table.insert(parts, title)
  end

  local lines = {
    { U.L("SUPPORT_POPUP_QUESTION"), 0 },
    { U.L("SUPPORT_POPUP_MESSAGE"), 0 },
    { U.L("SUPPORT_POPUP_THANKS"), support.thanksGap },
  }
  local previous
  local i
  for i = 1, table.getn(lines) do
    local line = support.Label(frame, "GameFontHighlight", lines[i][1])
    if line then
      if previous then
        pcall(line.SetPoint, line, "TOP", previous, "BOTTOM", 0, -lines[i][2])
      else
        pcall(line.SetPoint, line, "TOP", frame, "TOP", 0, -46)
      end
      table.insert(parts, line)
      previous = line
    end
  end

  -- Two answers side by side, the shared popup pair geometry
  -- (M.modernWow.corpsePopupButton). Left: already liked, never shown again
  -- on any profile. Right: closed for now, shown again at the next login.
  local pair = M.modernWow and M.modernWow.corpsePopupButton
  local sideInset = pair and pair.sideInset or 18
  local pairGap = pair and pair.pairGap or 19
  local buttonWidth = (width - 2 * sideInset - pairGap) / 2

  local function Close()
    local j
    for j = 1, table.getn(parts) do pcall(parts[j].Hide, parts[j]) end
    pcall(frame.Hide, frame)
    support.Layout()
  end

  local liked = U.CreateButton(frame, {
    name = "UnrealUISupportPopupLiked",
    text = "",
    width = buttonWidth,
    height = support.buttonHeight,
  })
  liked:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -pairGap / 2, support.buttonBottom)

  local later = U.CreateButton(frame, {
    name = "UnrealUISupportPopupLater",
    text = "",
    width = buttonWidth,
    height = support.buttonHeight,
  })
  later:SetPoint("BOTTOMLEFT", frame, "BOTTOM", pairGap / 2, support.buttonBottom)
  table.insert(parts, liked)
  table.insert(parts, later)

  if modernWow then U.StyleGameSettingsWidgets({ liked, later }, true) end
  local likedText = support.ButtonText(liked, U.L("SUPPORT_POPUP_ALREADY_LIKED"))
  local laterText = support.ButtonText(later, U.L("SUPPORT_POPUP_WILL_LIKE"))
  if likedText then table.insert(parts, likedText) end
  if laterText then table.insert(parts, laterText) end

  -- rendering.parent_alpha_not_propagated: every part is shown and hidden
  -- explicitly rather than left to follow the panel.
  liked:SetScript("OnClick", function()
    U.SetSupportPopupDismissed(true)
    Close()
  end)
  later:SetScript("OnClick", Close)

  frame.parts = parts
  frame:Hide()
  return frame
end

function support.Show()
  if U.SupportPopupDismissed() then return end
  local ok, frame = pcall(support.Build)
  if not ok then
    U.Error("supportpopup: " .. tostring(frame))
    return
  end
  if not frame then return end
  support.Register(frame)
  pcall(frame.Show, frame)
  local i
  for i = 1, table.getn(frame.parts) do pcall(frame.parts[i].Show, frame.parts[i]) end
  support.Layout()
end

function G:OnEnable()
  if U.SupportPopupDismissed() then return end
  local timer = CreateFrame("Frame", nil, UIParent)
  local started
  timer:SetScript("OnUpdate", function()
    local now = type(GetTime) == "function" and GetTime() or 0
    if not started then started = now end
    if now - started < support.delay then return end
    timer:SetScript("OnUpdate", nil)
    timer:Hide()
    support.Show()
  end)
end
