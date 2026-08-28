-- unrealUI :: modules/breathbar.lua
--
-- Modern treatment for the client's breath mirror timer. The timer owns the
-- oxygen countdown and fill progression; this module only restyles that live
-- state after it is present. `MirrorTimer#timer == "BREATH"` and
-- `MirrorTimer#value` are WORKING_SOURCE evidence from the installed
-- UnrealPfUI mirror-timer implementation, because the compact runtime record
-- currently has no mirror-timer capture. The native StatusBar getters are
-- documented by this client and let the readout degrade safely if `value` is
-- unavailable.
--
-- Fatigue and other mirror timers deliberately keep their native treatment.
-- No timer scripts, events, or values are replaced, so the client remains the
-- single owner of breath timing.

local U = UnrealUI
local M = U.media

local BB = U.RegisterModule("breathbar")

local WIDTH = 260
local HEIGHT = 20
local TIMER_LIMIT = 5

local breathFrame
local breathSkin
local moverRegistered = false
local breathActive = false

local function IsBreathTimer(frame)
  if not frame then return false end
  local timer = frame.timer
  return type(timer) == "string" and string.upper(timer) == "BREATH"
end

local function TimerCount()
  local count = tonumber(U.G("MIRRORTIMER_NUMTIMERS")) or 3
  if count < 1 then count = 1 end
  if count > TIMER_LIMIT then count = TIMER_LIMIT end
  return count
end

local function FindBreathTimer()
  local i
  for i = 1, TimerCount() do
    local frame = U.G("MirrorTimer" .. i)
    if IsBreathTimer(frame) then return frame, i end
  end
  return nil, nil
end

local function HideStockPart(name)
  local part = U.G(name)
  if part and part.Hide then pcall(part.Hide, part) end
end

local function ReadBarValue(bar)
  if not bar or not bar.GetValue then return nil end
  local ok, value = pcall(bar.GetValue, bar)
  return ok and tonumber(value) or nil
end

local function FormatRemaining(value)
  value = math.max(0, tonumber(value) or 0)
  local whole = math.floor(value)
  return string.format("%d:%02d", math.floor(whole / 60),
                       math.mod(whole, 60))
end

local function SetSkinShown(shown)
  if not breathSkin then return end
  local parts = { breathSkin.bar, breathSkin.title, breathSkin.time }
  local i
  for i = 1, table.getn(parts) do
    local part = parts[i]
    if part then
      if shown then part:Show() else part:Hide() end
    end
  end
end

local function ApplyModernSkin(frame, index)
  if breathFrame ~= frame then
    breathFrame = frame
    breathSkin = nil
  end

  if not breathSkin then
    -- The native frame keeps receiving its own timer update. Its decorative
    -- art is removed once, then shared flat primitives provide the surface.
    U.StripTextures(frame)
    U.CreateBackdrop(frame, {
      background = M.color.healthBg,
      border = M.color.border,
    })
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEIGHT)

    local bar = U.G("MirrorTimer" .. index .. "StatusBar")
    if bar and bar.SetStatusBarTexture then
      pcall(bar.SetStatusBarTexture, bar, M.texture.statusBar)
      pcall(bar.ClearAllPoints, bar)
      pcall(bar.SetPoint, bar, "TOPLEFT", frame, "TOPLEFT", 1, -1)
      pcall(bar.SetPoint, bar, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    end

    local title = U.CreateLabel(frame, {
      size = M.fontSize.small,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
    })
    if title then title:SetPoint("LEFT", frame, "LEFT", 6, 0) end

    local time = U.CreateLabel(frame, {
      size = M.fontSize.small,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
      justify = "RIGHT",
    })
    if time then time:SetPoint("RIGHT", frame, "RIGHT", -6, 0) end

    breathSkin = { bar = bar, title = title, time = time }
  end

  -- The mirror-timer update can repaint these visible child regions, so keep
  -- them hidden while the owned labels carry the same information.
  HideStockPart("MirrorTimer" .. index .. "Border")
  HideStockPart("MirrorTimer" .. index .. "Text")

  if breathSkin.bar then
    if breathSkin.bar.SetStatusBarColor then
      pcall(breathSkin.bar.SetStatusBarColor, breathSkin.bar,
            M.Unpack(M.color.breath))
    end
    if breathSkin.bar.Show then breathSkin.bar:Show() end
  end

  local nativeTitle = U.G("MirrorTimer" .. index .. "Text")
  local titleText
  if nativeTitle and nativeTitle.GetText then
    local ok, text = pcall(nativeTitle.GetText, nativeTitle)
    if ok and type(text) == "string" and text ~= "" then titleText = text end
  end
  if breathSkin.title then
    breathSkin.title:SetText(titleText or U.L("MOVER_LABEL_BREATH_BAR"))
  end

  local value = tonumber(frame.value) or ReadBarValue(breathSkin.bar)
  if breathSkin.time then breathSkin.time:SetText(FormatRemaining(value)) end
  SetSkinShown(true)
end

local function RegisterMover(frame)
  if moverRegistered then return end
  moverRegistered = true
  U.RegisterMover("breathbar", frame, {
    label = U.L("MOVER_LABEL_BREATH_BAR"),
    default = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 },
    visible = function() return breathActive end,
  })
end

local function Refresh()
  if U.PerfDisabled and U.PerfDisabled("breathbar") then return end
  if U.ThemeStyleUsesNativeChrome() then return end

  local frame, index = FindBreathTimer()
  breathActive = frame ~= nil
  if not frame then
    SetSkinShown(false)
    return
  end

  RegisterMover(frame)
  ApplyModernSkin(frame, index)
end

function BB:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then return end

  -- Mirror timers are created and shown by the client only when needed; a
  -- short shared-driver refresh catches that transition without replacing the
  -- unknown mirror-timer event contract.
  U.RegisterUpdate("breathbar.refresh", 0.1, Refresh)
  Refresh()
end
