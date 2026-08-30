-- unrealUI :: modules/autoattack.lua
--
-- Optional target-selection auto attack. PLAYER_TARGET_CHANGED is verified on
-- this client and covers both mouse selection and Tab targeting. AttackTarget
-- and UnitCanAttack are OFFICIAL_CLIENT_DOCUMENTATION.
--
-- The hard part is not starting the attack, it is knowing whether one is
-- already running: AttackTarget is a *toggle*, so a wrong answer either misses
-- a swing (thought we were attacking, we were not) or cancels one (thought we
-- were idle, we were not). The previous revision answered that question with a
-- local boolean fed only by PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT. Those
-- two events are not in the probed event set at all -- events.json lists
-- neither as tested nor observed -- and the flag was also set unconditionally
-- after every AttackTarget call, including calls that could not have started an
-- attack: a corpse passes UnitCanAttack, which is documented as a faction test
-- and says nothing about death, and clicking a corpse is what a player does
-- after every kill. Either path latches the flag true with no event able to
-- clear it, and every later target change is then skipped -- auto attack works
-- until the first miss and then stays off.
--
-- So the toggle state is read back from the client instead of remembered.
-- IsAttackAction locates the Attack action once, IsCurrentAction reports
-- whether it is the active action; both are documented, and
-- modules/actionbar.lua already drives its active-button border off
-- IsCurrentAction. A live "true" is always trusted. A live "false" is trusted
-- only once this session has seen the pair report true at least once, so a
-- client that never reports the state cannot make this module cancel a running
-- attack. Without that proof, and with no Attack action on any bar, the
-- optimistic flag remains -- but it now expires unless PLAYER_ENTER_COMBAT
-- confirms it, so it can no longer latch.
--
-- Rogue Stealth is detected through the verified bonus-bar offset transition.
-- Druid Prowl follows UnrealPfUI's working Cat Form + stealth-aura texture
-- check, so ordinary Cat Form remains eligible for auto attack.

local U = UnrealUI

local AA = U.RegisterModule("autoattack")

local config
local playerClass
local targetEpoch = 0
local recentTargetEpoch
local recentTargetUntil = 0
local recentRetryUsed = false

-- Fallback belief, used only while the client's own state is unreadable.
local attacking = false
local attackConfirmed = false
local attackStartedAt = 0

local attackSlot
local attackSlotScanned = false
local liveStateProven = false

-- Keep the target-change handoff armed briefly. The user-confirmed missed
-- attack is consistent with PLAYER_TARGET_CHANGED arriving before the click
-- finishes dropping the old auto-attack state; if PLAYER_LEAVE_COMBAT follows,
-- the new target needs one more check. The window is only for that handoff; it
-- must not turn an ordinary later manual stop back on.
local TARGET_SETTLE_SECONDS = 0.5

-- An AttackTarget call that nothing ever confirms is assumed to have failed, so
-- the fallback belief cannot outlive the swing it was standing in for.
local UNCONFIRMED_ATTACK_SECONDS = 3

local MAX_ACTION_SLOT = 120

-- Vanilla's boolean-ish APIs return 1 or nil, but that is not guaranteed here,
-- so anything other than nil/false/0/"" counts as true.
local function Truthy(value)
  if value == nil or value == false or value == 0 or value == "" then
    return false
  end
  return true
end

-- Second return says whether the call actually happened, which is how an
-- unreadable API is told apart from one reporting false.
local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil, false end
  local ok, value = pcall(fn, a, b)
  if not ok then return nil, false end
  return value, true
end

local function ApiTruth(name, a, b)
  local value = Call(name, a, b)
  return Truthy(value)
end

local function Now()
  local value, called = Call("GetTime")
  if called and type(value) == "number" then return value end
  return nil
end

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

-- ---------------------------------------------------------------------------
-- Reading the real toggle state
-- ---------------------------------------------------------------------------

-- The Attack action can sit on any page, so the whole slot range is scanned
-- once. The result is cached and dropped again whenever the bars change.
local function AttackSlot()
  if attackSlotScanned then return attackSlot end
  attackSlotScanned = true
  attackSlot = nil

  if type(U.G("IsAttackAction")) ~= "function" then return nil end

  local slot
  for slot = 1, MAX_ACTION_SLOT do
    if ApiTruth("IsAttackAction", slot) then
      attackSlot = slot
      return attackSlot
    end
  end

  return nil
end

local function ForgetAttackSlot()
  attackSlotScanned = false
  attackSlot = nil
end

-- true / false when the client can answer, nil when it cannot.
local function LiveAttackState()
  local slot = AttackSlot()
  if not slot then return nil end

  local value, called = Call("IsCurrentAction", slot)
  if not called then return nil end

  if Truthy(value) then
    liveStateProven = true
    return true
  end

  -- Until this pair has been seen reporting an active attack at least once, a
  -- "false" is indistinguishable from a state this client never reports, and
  -- acting on it would toggle a running attack off.
  if not liveStateProven then return nil end
  return false
end

local function IsAttacking()
  local live = LiveAttackState()
  if live ~= nil then return live end

  if not attacking then return false end
  if attackConfirmed then return true end

  -- Unconfirmed and unreadable: let it lapse rather than block every future
  -- target change on a call that may never have started a swing. Out of combat
  -- only -- of the two ways to be wrong here, cancelling a swing that is really
  -- running is the worse one, and the combat flag is the last cheap signal that
  -- one might be.
  local now = Now()
  if now and now > attackStartedAt + UNCONFIRMED_ATTACK_SECONDS and
     not ApiTruth("UnitAffectingCombat", "player") then
    attacking = false
    return false
  end

  return true
end

-- Shared read-only state for modules that need to follow the real attack
-- toggle without duplicating the guarded action-slot scan above. The swing bar
-- uses this for manual attacks as well as attacks started by this module.
function U.IsAutoAttacking()
  return IsAttacking()
end

local function TargetIsAttackable()
  if not ApiTruth("UnitExists", "target") then return false end
  if ApiTruth("UnitIsDead", "target") then return false end
  if ApiTruth("UnitIsGhost", "target") then return false end
  return ApiTruth("UnitCanAttack", "player", "target")
end

-- One tick after the toggle, check whether it took. This retires a belief the
-- client never acted on, and it is also how the live state gets proven during
-- ordinary play rather than only on the first fight of a session.
local function ConfirmAttack(epoch)
  U.DeferOnce("autoattack.confirm", function()
    if epoch ~= targetEpoch then return end

    local live = LiveAttackState()
    if live == true then
      attackConfirmed = true
    elseif live == false then
      attacking = false
      attackConfirmed = false
    end
  end)
end

local function TryStartAttack(epoch)
  if epoch ~= targetEpoch then return end
  if not config or not config.enabled or IsHidden() then return end
  if IsAttacking() then return end
  if not TargetIsAttackable() then return end

  local attackTarget = U.G("AttackTarget")
  if type(attackTarget) ~= "function" then return end

  -- AttackTarget is a toggle. Mark it immediately so duplicate target events
  -- cannot turn it back off before the state is readable again.
  if pcall(attackTarget) then
    attacking = true
    attackConfirmed = false
    attackStartedAt = Now() or 0
    ConfirmAttack(epoch)
  end
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
  -- attack-toggle state. Tab targeting also follows this harmless one-tick
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
    attackConfirmed = true
    attackStartedAt = Now() or 0
    recentTargetEpoch = nil
  end)
  U.RegisterEvent("PLAYER_LEAVE_COMBAT", function()
    attacking = false
    attackConfirmed = false

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

  -- The cached Attack slot is only valid for the current bar contents.
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", ForgetAttackSlot)
  U.RegisterEvent("ACTIONBAR_PAGE_CHANGED", ForgetAttackSlot)
  U.RegisterEvent("UPDATE_BONUS_ACTIONBAR", ForgetAttackSlot)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", ForgetAttackSlot)
end
