-- unrealUI :: modules/minimap.lua
--
-- A settings button beside the native minimap, and a mover anchor so the
-- native minimap cluster can be dragged in unrealUI's edit mode.
--
-- The native minimap is kept as it is: no replacement, no reskin, no chrome
-- suppression. knowledge.json / minimap.render_pass_under_ordinary_frames says
-- the map surface is drawn in a special pass beneath ordinary frames, which is
-- also why the button is placed *outside* the map rather than over it -- an
-- ordinary frame on top of the map would cover it.
--
-- The mover targets MinimapCluster rather than bare Minimap: behavior.json /
-- minimap.context.frames.MinimapCluster confirms it holds the map's native
-- chrome (zone text, etc.) and defaults to TOPRIGHT UIParent TOPRIGHT 0,0 with
-- no pfUI involvement, so moving the cluster keeps that chrome attached and
-- the registration's own default matches where the client already puts it.
-- The settings button stays anchored to Minimap itself, so it keeps tracking
-- correctly without any extra work when the cluster moves.

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

-- MinimapCluster is preferred: it is the whole native unit (map plus its
-- attached chrome) and its default anchor is measured. A bare Minimap fallback
-- carries no default -- its own point is only known from a pfUI-influenced
-- snapshot, not trustworthy as this client's un-modded native anchor -- so
-- Reset simply leaves it wherever it already is in that rare case.
local function ResolveMoverTarget()
  local cluster = U.G("MinimapCluster")
  if cluster then
    return cluster, "MinimapCluster",
      { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = 0, y = 0 }
  end

  local minimap = U.G("Minimap")
  if minimap then return minimap, "Minimap", nil end

  return nil
end

local function RegisterMinimapMover()
  local target, name, default = ResolveMoverTarget()
  if not target then
    U.Debug("minimap: no MinimapCluster or Minimap to register as a mover")
    return
  end

  U.RegisterMover("minimap", target, { label = "Minimap", default = default })
  U.Debug("minimap mover registered on " .. name)
end

-- Applies the current enabled state to an already-created button. Public so
-- modules/settings.lua's General page can flip the checkbox without reaching
-- into this module's internals.
local function Apply()
  local button = MM.button
  if not button then return end

  if U.ModuleConfig("minimap", { enabled = true }).enabled then
    button:Show()
    if button.label then button.label:Show() end
  else
    button:Hide()
  end
end
U.ApplyMinimapButton = Apply

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

  self.button = button
  Apply()
  U.Debug("settings button anchored to " .. anchor)

  RegisterMinimapMover()
end
