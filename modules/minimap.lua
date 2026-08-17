-- unrealUI :: modules/minimap.lua
--
-- One settings button beside the native minimap. That is the entire module.
--
-- The native minimap is kept as it is: no replacement, no reskin, no chrome
-- suppression. knowledge.json / minimap.render_pass_under_ordinary_frames says
-- the map surface is drawn in a special pass beneath ordinary frames, which is
-- also why the button is placed *outside* the map rather than over it -- an
-- ordinary frame on top of the map would cover it.

local U = UnrealUI
local M = U.media

local MM = U.RegisterModule("minimap")

local BUTTON_SIZE = 24

-- Anchored to the map's left edge so it never lands on the map surface or on
-- the stock chrome hanging off the right side.
local function AnchorButton(button)
  local minimap = U.G("Minimap")
  if minimap then
    button:SetPoint("TOPRIGHT", minimap, "TOPLEFT", -6, 0)
    return "Minimap"
  end

  local cluster = U.G("MinimapCluster")
  if cluster then
    button:SetPoint("TOPRIGHT", cluster, "TOPLEFT", -6, -6)
    return "MinimapCluster"
  end

  -- No minimap to sit beside: park it in the corner rather than not existing.
  button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
  return "UIParent (no minimap found)"
end

function MM:OnEnable()
  if self.button then return end

  local button = U.CreateButton(UIParent, {
    name = "UnrealUISettingsButton",
    width = BUTTON_SIZE,
    height = BUTTON_SIZE,
    text = "",
    onClick = function()
      if type(U.OpenSettings) == "function" then U.OpenSettings() end
    end,
  })

  local border = U.BorderSize()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", border, -border)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -border, border)

  -- A stock icon path. Nothing in the compact DB covers Interface\ICONS on this
  -- client, so if the call is rejected the button falls back to its own label
  -- rather than showing an empty square.
  local applied = pcall(icon.SetTexture, icon, "Interface\\ICONS\\INV_Misc_Gear_01")
  if applied then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  else
    icon:Hide()
    if button.label then button.label:SetText("UI") end
  end
  button.icon = icon

  local anchor = AnchorButton(button)
  button:Show()
  if button.label then button.label:Show() end

  self.button = button
  U.Debug("settings button anchored to " .. anchor)
end
