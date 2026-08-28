-- unrealUI :: modules/autoattack.lua
--
-- Optional target-selection auto attack. PLAYER_TARGET_CHANGED is verified on
-- this client and covers both mouse selection and Tab targeting. AttackTarget,
-- UnitCanAttack, PLAYER_ENTER_COMBAT and PLAYER_LEAVE_COMBAT follow
-- UnrealPfUI's working Vanilla implementation on this same client; the combat
-- events describe the auto-attack toggle state, not the broader combat flag.
-- Rogue Stealth is detected through the verified bonus-bar offset transition.
-- Druid Prowl follows UnrealPfUI's working Cat Form + stealth-aura texture
-- check, so ordinary Cat Form remains eligible for auto attack.

local U = UnrealUI

local AA = U.RegisterModule("autoattack")

local config
local attacking = false
local playerClass
local targetEpoch = 0
local recentTargetEpoch
local recentTargetUntil = 0
local recentRetryUsed = false

-- Keep the target-change handoff armed briefly. The user-confirmed missed
-- attack is consistent with PLAYER_TARGET_CHANGED arriving before the click
-- finishes dropping the old auto-attack state; if PLAYER_LEAVE_COMBAT follows,
-- the new target needs one more check. The window is only for that handoff; it
-- must not turn an ordinary later manual stop back on.
local TARGET_SETTLE_SECONDS = 0.5

local function PlayerClass()
  if playerClass then return playerClass end

  local unitClass = U.G("UnitClass")
  if type(unitClass) ~= "function" then return nil end

  local ok, _, class = pcall(unitClass, "player")
  if ok and type(class) == "string" then playerClass = class end
  return playerClass
end

local function IsDruidProwling()
  local getTexture = U.G("GetPlayerBuffTexture")
  if type(getTexture) ~= "function" then return false end

  local cat, hidden = false, false
  local index
  for index = 0, 31 do
    local ok, texture = pcall(getTexture, index)
    if not ok or type(texture) ~= "string" or texture == "" then break end

    if string.find(texture, "Ability_Druid_CatForm", 1, true) then
      cat = true
    elseif string.find(texture, "Ability_Ambush", 1, true) or
           string.find(texture, "Ability_Druid_SupriseAttack", 1, true) then
      hidden = true
    end

    if cat and hidden then return true end
  end

  return false
end

local function IsHidden()
  local class = PlayerClass()
  if class == "ROGUE" then
    local getBonusBarOffset = U.G("GetBonusBarOffset")
    if type(getBonusBarOffset) ~= "function" then return false end

    local ok, offset = pcall(getBonusBarOffset)
    return ok and tonumber(offset) == 1
  elseif class == "DRUID" then
    return IsDruidProwling()
  end

  return false
end

local function Now()
  local getTime = U.G("GetTime")
  if type(getTime) ~= "function" then return nil end

  local ok, value = pcall(getTime)
  if ok and type(value) == "number" then return value end
  return nil
end

local function TryStartAttack(epoch)
  if epoch ~= targetEpoch then return end
  if not config or not config.enabled or attacking or IsHidden() then return end

  local unitCanAttack = U.G("UnitCanAttack")
  local attackTarget = U.G("AttackTarget")
  if type(unitCanAttack) ~= "function" or type(attackTarget) ~= "function" then
    return
  end

  local ok, canAttack = pcall(unitCanAttack, "player", "target")
  if not ok or not canAttack or canAttack == 0 then return end

  -- AttackTarget is a toggle. Mark it immediately so duplicate target events
  -- cannot turn it back off before PLAYER_ENTER_COMBAT reports the new state.
  if pcall(attackTarget) then attacking = true end
end

local function QueueTargetAttack(epoch)
  U.DeferOnce("autoattack.target", function()
    TryStartAttack(epoch)
  end)
end

local function OnTargetChanged()
  targetEpoch = targetEpoch + 1
  recentTargetEpoch = targetEpoch
  recentRetryUsed = false
  local now = Now()
  recentTargetUntil = now and now + TARGET_SETTLE_SECONDS or 0

  -- Let the native left-click target transition finish before consulting the
  -- attack-toggle events. Tab targeting also follows this harmless one-tick
  -- path, and repeated target changes coalesce to the newest epoch.
  QueueTargetAttack(targetEpoch)
end

function AA:OnInit()
  config = U.ModuleConfig("autoattack", { enabled = true })
end

function AA:OnEnable()
  if not config then
    config = U.ModuleConfig("autoattack", { enabled = true })
  end

  U.RegisterEvent("PLAYER_ENTER_COMBAT", function()
    attacking = true
    recentTargetEpoch = nil
  end)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    attacking = false

    -- If a left click stops the old target's swing just after announcing the
    -- new target, re-check that same target on the next tick, once native click
    -- processing has completed. Outside the short handoff window, leave a
    -- deliberate/manual stop alone.
    local now = Now()
    if not recentRetryUsed and recentTargetEpoch == targetEpoch and now and
       now <= recentTargetUntil then
      recentRetryUsed = true
      QueueTargetAttack(targetEpoch)
    else
      recentTargetEpoch = nil
    end
  end)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", OnTargetChanged)
end
