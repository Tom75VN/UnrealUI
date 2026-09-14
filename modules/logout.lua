-- unrealUI :: modules/logout.lua
--
-- UnrealUI presentation for the native logout/disconnect confirmations. The
-- native StaticPopup frames and buttons remain the real controls; this module
-- replaces only their artwork. Modern WoW deliberately uses the same metal
-- housing, translucent bed and measured red-button face as the Escape menu.
--
-- StaticPopup structure is still a SOURCE_DEPENDENCY_GAP for this client. The
-- known globals and `which` values below come from the existing working path;
-- every lookup and repaint therefore remains capability-checked.

local U = UnrealUI
local M = U.media

local G = U.RegisterModule("logout")
local popup = {}

popup.tracked = {
  CAMP = true,
  QUIT = true,
  DEATH = true,
  RESURRECT = true,
  RESURRECT_NO_SICKNESS = true,
  -- "Resurrect now?" beside the corpse. The `which` value is
  -- USER_CONFIRMED_INGAME (2026-09-14): an OnShow hook matching it fired.
  RECOVER_CORPSE = true,
}
popup.styled = {}

function popup.Number(frame, method)
  if not frame or type(frame[method]) ~= "function" then return nil end
  local ok, value = pcall(frame[method], frame)
  if ok then return tonumber(value) end
  return nil
end

function popup.Enabled(button)
  if not button or type(button.IsEnabled) ~= "function" then return true end
  local ok, enabled = pcall(button.IsEnabled, button)
  if not ok then return true end
  return enabled and enabled ~= 0
end

-- Repeated region walks would also see the addon-owned atlas slices on this
-- client, so the full strip is done exactly once before those slices exist.
-- Later native refreshes are silenced only through the button's state setters.
function popup.ClearButtonStateArt(button)
  if not button then return end
  local setters = {
    "SetNormalTexture", "SetHighlightTexture",
    "SetPushedTexture", "SetDisabledTexture",
  }
  local i
  for i = 1, table.getn(setters) do
    local setter = button[setters[i]]
    if type(setter) == "function" then
      if not pcall(setter, button, "") then pcall(setter, button, nil) end
    end
  end
  pcall(button.SetBackdropColor, button, 0, 0, 0, 0)
  pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 0)
end

function popup.ButtonLabel(button)
  if not button or type(button.GetFontString) ~= "function" then return nil end
  local ok, label = pcall(button.GetFontString, button)
  if ok then return label end
  return nil
end

-- `alwaysRed` keeps the red face and neutral label whatever IsEnabled reports:
-- the "Resurrect now?" button read as disabled at show and drew the grey cell,
-- and the user asked for red (2026-09-14).
function popup.StyleWowButton(button, alwaysRed)
  if not button then return end

  if not button.uuiLogoutWowButton then
    button.uuiLogoutWowButton = true
    U.RefreshStockButtonArtwork(button)

    U.PostHookScript(button, "OnEnter", function()
      U.ModernWowPaintRedButton(button, true)
    end)
    U.PostHookScript(button, "OnLeave", function()
      U.ModernWowPaintRedButton(button, false)
    end)
  else
    popup.ClearButtonStateArt(button)
  end

  local height = popup.Number(button, "GetHeight")
  local enabled = alwaysRed or popup.Enabled(button)
  U.ModernWowRedButtonFace(button, height)
  U.ModernWowSetRedButtonDisabled(button, not enabled)

  local label = popup.ButtonLabel(button)
  if label then
    U.SetStockFont(label, M.fontSize.normal,
      enabled and M.color.text or M.color.textDim)
    U.CenterButtonLabel(label, button)
  end
end

function popup.StyleWowDialog(dialog, name)
  if not popup.styled[dialog] then
    -- The strip must precede ModernWowMetalFrame: region wrappers cannot be
    -- matched by identity here, so a later strip would erase our own frame.
    U.StripStockTextures(dialog)
    popup.styled[dialog] = { style = "modern-wow" }
  end

  -- The client may restore its own backdrop between uses. Zeroing its colours
  -- is the verified non-destructive clear used by the Modern WoW game menu.
  pcall(dialog.SetBackdropColor, dialog, 0, 0, 0, 0)
  pcall(dialog.SetBackdropBorderColor, dialog, 0, 0, 0, 0)

  U.ModernWowMetalFrame(dialog,
    popup.Number(dialog, "GetWidth"), popup.Number(dialog, "GetHeight"))

  local text = U.G(name .. "Text")
  if text then U.SetStockFont(text, M.fontSize.normal, M.color.text) end

  local which
  pcall(function() which = dialog.which end)
  local alwaysRed = which == "RECOVER_CORPSE"
  popup.StyleWowButton(U.G(name .. "Button1"), alwaysRed)
  popup.StyleWowButton(U.G(name .. "Button2"), alwaysRed)
end

function popup.StyleFlatDialog(dialog, name)
  if popup.styled[dialog] then return end
  popup.styled[dialog] = { style = "modern" }

  U.StripStockTextures(dialog)
  U.CreateBackdrop(dialog, {
    background = { 0.04, 0.04, 0.04, 0.92 },
    border = M.color.border,
  })

  local text = U.G(name .. "Text")
  if text then U.SetStockFont(text, M.fontSize.normal, M.color.text) end

  local button1 = U.G(name .. "Button1")
  if button1 then
    U.StyleStockButton(button1, { hoverBorder = M.color.accent })
  end

  local button2 = U.G(name .. "Button2")
  if button2 then
    U.StyleStockButton(button2, { hoverBorder = M.color.accent })
  end
end

-- The logout panels take the "Resurrect now?" panel's size, by user request
-- (2026-09-14). Both are client-sized StaticPopups with no size in compact
-- evidence, so the corpse panel's size is measured whenever it opens and
-- remembered; until it has been seen once, the logout panels keep their own.
popup.matchCorpseSize = { CAMP = true, QUIT = true }

-- Modern WoW only: the native button is enlarged to the red button's size, and
-- the popup grows by the extra height so the button cannot cover the message.
-- The client sizes the popup again on every show, so this runs on every show.
-- The logout panels reuse it with `grow` off: their height is already the
-- (grown) resurrect panel's, held by popup.ApplyCorpseSize.
function popup.SizeCorpseButton(dialog, name, grow)
  if U.GetActiveThemeStyle() ~= "modern-wow" then return end
  local token = M.modernWow and M.modernWow.corpsePopupButton
  local button = U.G(name .. "Button1")
  if not token or not button then return end

  -- Two buttons side by side (Quit: Exit now / Cancel) at the full width ran
  -- past the metal frame (user screenshot, 2026-09-14), so a pair shares the
  -- width inside the frame's sides instead. The client centres the pair on
  -- the popup, so narrowing both keeps them inside without re-anchoring.
  local second = U.G(name .. "Button2")
  local pair = false
  if second then
    pcall(function() pair = second:IsShown() and true or false end)
  end

  local width = token.width
  local dialogWidth = popup.Number(dialog, "GetWidth")
  if pair and dialogWidth then
    local fit = (dialogWidth - 2 * token.sideInset - token.pairGap) / 2
    if fit < width then width = fit end
  end

  local oldHeight = popup.Number(button, "GetHeight") or token.height
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, token.height)

  if second then
    pcall(second.SetWidth, second, width)
    pcall(second.SetHeight, second, token.height)
  end

  local extra = token.height - oldHeight
  local height = popup.Number(dialog, "GetHeight")
  if grow and extra > 0 and height then
    pcall(dialog.SetHeight, dialog, height + extra)
  end
end

function popup.RecordCorpseSize(dialog)
  local width = popup.Number(dialog, "GetWidth")
  local height = popup.Number(dialog, "GetHeight")
  if not width or not height or width <= 0 or height <= 0 then return end
  local config = U.ModuleConfig("logout")
  config.corpseWidth = width
  config.corpseHeight = height
end

-- Returns true when the dialog's size had to be changed.
function popup.ApplyCorpseSize(dialog)
  local config = U.ModuleConfig("logout")
  local width, height = tonumber(config.corpseWidth), tonumber(config.corpseHeight)
  if not width or not height then return false end

  local changed = false
  local current = popup.Number(dialog, "GetWidth")
  if not current or math.abs(current - width) >= 0.5 then
    pcall(dialog.SetWidth, dialog, width)
    changed = true
  end
  current = popup.Number(dialog, "GetHeight")
  if not current or math.abs(current - height) >= 0.5 then
    pcall(dialog.SetHeight, dialog, height)
    changed = true
  end
  return changed
end

function popup.Style(dialog, name)
  if U.GetActiveThemeStyle() == "modern-wow" and
     type(U.ModernWowMetalFrame) == "function" and
     type(U.ModernWowRedButtonFace) == "function" then
    popup.StyleWowDialog(dialog, name)
  else
    popup.StyleFlatDialog(dialog, name)
  end
end

-- The client can resize a popup while it is open (the logout countdown
-- rewrites its text every second), so the size is held while it stays up.
function popup.HoldCorpseSize(dialog, name)
  local id = "logout.size." .. name
  U.RegisterUpdate(id, 0.25, function()
    local shown, which = false, nil
    pcall(function()
      shown = dialog:IsShown() and true or false
      which = dialog.which
    end)
    if not shown or not which or not popup.matchCorpseSize[which] then
      U.UnregisterUpdate(id)
      return
    end
    if popup.ApplyCorpseSize(dialog) then popup.Style(dialog, name) end
  end)
end

function popup.OnShow(dialog, name)
  local which
  pcall(function() which = dialog.which end)
  if not which or not popup.tracked[which] then return end

  if which == "RECOVER_CORPSE" then
    popup.SizeCorpseButton(dialog, name, true)
    popup.RecordCorpseSize(dialog)
  elseif popup.matchCorpseSize[which] then
    -- Size first: the buttons fit themselves to the popup's final width.
    popup.ApplyCorpseSize(dialog)
    popup.SizeCorpseButton(dialog, name, false)
    popup.HoldCorpseSize(dialog, name)
  end

  popup.Style(dialog, name)
end

function G:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then return end
  local max = tonumber(U.G("STATICPOPUP_NUMDIALOGS")) or 4
  local i
  for i = 1, max do
    local name = "StaticPopup" .. i
    local dialog = U.G(name)
    if dialog then
      U.PostHookScript(dialog, "OnShow", function()
        popup.OnShow(dialog, name)
      end)

      local ok, shown = pcall(dialog.IsShown, dialog)
      if ok and shown then popup.OnShow(dialog, name) end
    end
  end
end
