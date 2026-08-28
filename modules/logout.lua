-- unrealUI :: modules/logout.lua
--
-- Modern-style skin for the native confirmation popups: logout/camp, releasing
-- a spirit, and accepting a resurrection. They retain their native actions;
-- this module replaces only the chrome around those actions.
--
-- query_compat.py has no StaticPopup evidence at all on this client
-- (SOURCE_DEPENDENCY_GAP). Per the UnrealPfUI evidence-gap fallback, this
-- reproduces UnrealPfUI's own generic StaticPopup skin (skins/blizzard/
-- popup_dialogs.lua: CreateBackdrop + SkinButton per dialog), narrowed to
-- the confirmation dialogs UnrealUI owns rather than reskinning every stock
-- popup.
-- WORKING_SOURCE, not runtime-verified.

local U = UnrealUI
local M = U.media

local G = U.RegisterModule("logout")

-- `DEATH` is the Release Spirit confirmation and `RESURRECT` is the native
-- resurrection offer. The no-sickness variant uses the same controls and is
-- included so the modern theme stays coherent for both offer states.
local TRACK_WHICH = {
  CAMP = true,
  QUIT = true,
  DEATH = true,
  RESURRECT = true,
  RESURRECT_NO_SICKNESS = true,
}
local styledDialogs = {}

local function StyleDialog(dialog, name)
  if styledDialogs[dialog] then return end
  styledDialogs[dialog] = true

  U.StripStockTextures(dialog)
  U.CreateBackdrop(dialog, {
    background = { 0.04, 0.04, 0.04, 0.92 },
    border = M.color.border,
  })

  local text = U.G(name .. "Text")
  if text then U.SetStockFont(text, M.fontSize.normal, M.color.text) end

  local button1 = U.G(name .. "Button1")
  if button1 then U.StyleStockButton(button1, { hoverBorder = M.color.accent }) end

  local button2 = U.G(name .. "Button2")
  if button2 then U.StyleStockButton(button2, { hoverBorder = M.color.accent }) end
end

local function OnDialogShow(dialog, name)
  local which
  pcall(function() which = dialog.which end)
  if which and TRACK_WHICH[which] then StyleDialog(dialog, name) end
end

function G:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then return end
  local max = tonumber(U.G("STATICPOPUP_NUMDIALOGS")) or 4
  local i
  for i = 1, max do
    local name = "StaticPopup" .. i
    local dialog = U.G(name)
    if dialog then
      U.PostHookScript(dialog, "OnShow", function() OnDialogShow(dialog, name) end)

      local ok, shown = pcall(dialog.IsShown, dialog)
      if ok and shown then OnDialogShow(dialog, name) end
    end
  end
end
