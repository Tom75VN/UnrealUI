-- unrealUI :: modules/screenalerts.lua
--
-- Full-screen Retail warning art for low health and loss of character control.
-- Retail 12.1.0 drives LowHealth at 35% and pulses its additive texture; the
-- current Retail source does not reference OutOfControl, so the blue art is
-- driven by this client's documented HasFullControl state.

local U = UnrealUI
local M = U.media

local SA = U.RegisterModule("screenalerts")

local PAGE_WIDTH = 484
local LOW_HEALTH_START = 0.35
local PULSE_HALF = 0.5236

local lowHealth
local outOfControl

local function Config()
  return U.ModuleConfig("screenalerts", {
    lowHealth = true,
    outOfControl = true,
  })
end

local function SetAlertShown(alert, shown)
  if not alert or not alert.supported then return end
  shown = shown and true or false
  if alert.shown == shown then return end

  alert.shown = shown
  if shown then
    alert.startedAt = GetTime()
    U.SetColor(alert.texture, 1, 1, 1, alert.minAlpha)
    alert.frame:Show()
  else
    alert.frame:Hide()
  end
end

local function CreateAlert(name, texturePath, minAlpha, maxAlpha, reducedMaxAlpha)
  local frame = CreateFrame("Frame", name, UIParent)
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:Hide()

  local texture = frame:CreateTexture(nil, "BACKGROUND")
  texture:SetTexture(texturePath)
  texture:SetAllPoints(frame)

  local supported = texture.SetBlendMode and
                    pcall(texture.SetBlendMode, texture, "ADD")
  if not supported then
    U.Debug(name .. ": additive textures are unavailable")
  end

  return {
    frame = frame,
    texture = texture,
    minAlpha = minAlpha,
    maxAlpha = maxAlpha,
    reducedMaxAlpha = reducedMaxAlpha,
    supported = supported and true or false,
    shown = false,
    startedAt = 0,
  }
end

local function PlayerDeadOrGhost()
  return UnitIsDead("player") or UnitIsGhost("player")
end

local function RefreshLowHealth(event, unit)
  if (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and
     unit and unit ~= "player" then
    return
  end

  local shown = false
  if Config().lowHealth and not PlayerDeadOrGhost() then
    local maximum = tonumber(UnitHealthMax("player")) or 0
    local current = tonumber(UnitHealth("player")) or maximum
    shown = maximum > 0 and current / maximum <= LOW_HEALTH_START
  end
  SetAlertShown(lowHealth, shown)
end

local function RefreshOutOfControl()
  local shown = false
  if Config().outOfControl and not PlayerDeadOrGhost() and
     (tonumber(UnitHealthMax("player")) or 0) > 0 and
     type(HasFullControl) == "function" then
    local onTaxi = type(UnitOnTaxi) == "function" and UnitOnTaxi("player")
    local ok, hasControl = pcall(HasFullControl)
    shown = ok and not onTaxi and hasControl == false
  end
  SetAlertShown(outOfControl, shown)
end

local function OnEnteringWorld()
  RefreshLowHealth()
  RefreshOutOfControl()
end

local function PulseAlert(alert, now)
  if not alert or not alert.shown then return end

  local elapsed = now - alert.startedAt
  local phase = math.mod(elapsed, PULSE_HALF * 2) / PULSE_HALF
  local amount
  if phase <= 1 then amount = phase else amount = 2 - phase end

  local maximum = alert.maxAlpha
  if alert.reducedMaxAlpha and elapsed > 2 then
    local blend = math.min(1, elapsed - 2)
    maximum = maximum + (alert.reducedMaxAlpha - maximum) * blend
  end

  local alpha = alert.minAlpha + (maximum - alert.minAlpha) * amount
  U.SetColor(alert.texture, 1, 1, 1, alpha)
end

local function UpdatePulse()
  local now = GetTime()
  PulseAlert(lowHealth, now)
  PulseAlert(outOfControl, now)
end

function U.ApplyScreenAlerts()
  RefreshLowHealth()
  RefreshOutOfControl()
end

local function BuildSettingsPage(parent)
  local widgets = {}
  local config = Config()

  local header = U.CreateSectionHeader(parent, {
    text = U.L("SCREEN_ALERTS_PAGE"),
    width = PAGE_WIDTH,
    y = -4,
  })
  table.insert(widgets, header)

  local health = U.CreateCheckbox(parent, {
    name = "UnrealUIScreenAlertsLowHealth",
    text = U.L("SCREEN_ALERTS_LOW_HEALTH"),
    value = config.lowHealth,
    onChange = function(value)
      Config().lowHealth = value
      U.ApplyScreenAlerts()
    end,
  })
  health.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, health)

  local healthHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
  })
  if healthHint then
    U.AnchorSettingsDescription(healthHint, health.box)
    healthHint:SetText(U.L("SCREEN_ALERTS_LOW_HEALTH_HINT"))
    table.insert(widgets, healthHint)
  end

  local control = U.CreateCheckbox(parent, {
    name = "UnrealUIScreenAlertsOutOfControl",
    text = U.L("SCREEN_ALERTS_OUT_OF_CONTROL"),
    value = config.outOfControl,
    onChange = function(value)
      Config().outOfControl = value
      U.ApplyScreenAlerts()
    end,
  })
  if healthHint then
    control.SetPoint("TOPLEFT", healthHint, "BOTTOMLEFT", 0, -12)
  else
    control.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -78)
  end
  table.insert(widgets, control)

  local controlHint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = PAGE_WIDTH,
  })
  if controlHint then
    U.AnchorSettingsDescription(controlHint, control.box)
    controlHint:SetText(U.L("SCREEN_ALERTS_OUT_OF_CONTROL_HINT"))
    table.insert(widgets, controlHint)
  end

  local function Refresh()
    config = Config()
    health.SetValue(config.lowHealth)
    control.SetValue(config.outOfControl)
  end

  return widgets, Refresh
end

function SA:OnInit()
  if type(U.RegisterSettingsTab) == "function" then
    U.RegisterSettingsTab("screen-alerts", U.L("SCREEN_ALERTS_PAGE"),
                          BuildSettingsPage, { after = "general" })
  end
end

function SA:OnEnable()
  lowHealth = CreateAlert("UnrealUILowHealthFrame",
                          M.texture.fullscreenLowHealth, 0.15, 1.0, 0.5)
  outOfControl = CreateAlert("UnrealUIOutOfControlFrame",
                             M.texture.fullscreenOutOfControl, 0.2, 0.75)

  U.RegisterEvent("UNIT_HEALTH", RefreshLowHealth)
  U.RegisterEvent("UNIT_MAXHEALTH", RefreshLowHealth)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
  U.RegisterUpdate("screenalerts.control", 0.1, RefreshOutOfControl)
  U.RegisterUpdate("screenalerts.pulse", 0.03, UpdatePulse)

  U.ApplyScreenAlerts()
end
