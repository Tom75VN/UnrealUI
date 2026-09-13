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

function popup.StyleWowButton(button)
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
  U.ModernWowRedButtonFace(button, height)
  U.ModernWowSetRedButtonDisabled(button, not popup.Enabled(button))

  local label = popup.ButtonLabel(button)
  if label then
    U.SetStockFont(label, M.fontSize.normal,
      popup.Enabled(button) and M.color.text or M.color.textDim)
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

  popup.StyleWowButton(U.G(name .. "Button1"))
  popup.StyleWowButton(U.G(name .. "Button2"))
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

function popup.OnShow(dialog, name)
  local which
  pcall(function() which = dialog.which end)
  if not which or not popup.tracked[which] then return end

  if U.GetActiveThemeStyle() == "modern-wow" and
     type(U.ModernWowMetalFrame) == "function" and
     type(U.ModernWowRedButtonFace) == "function" then
    popup.StyleWowDialog(dialog, name)
  else
    popup.StyleFlatDialog(dialog, name)
  end
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
