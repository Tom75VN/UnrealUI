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
-- On a character with no Attack action anywhere on the bars that belief is the
-- only answer there is: IsAttackAction finds no slot, so IsCurrentAction is
-- never asked and the live state is permanently unreadable. Overriding it from
-- the swing bar's reported-swing count was tried and reverted -- it was an
-- inference from a symptom, not a measurement, and it regressed a rogue's
-- ordinary left-click-and-close melee start. MeleeSwingObserved and
-- U.AutoAttackState remain as read-only surfaces so meleeswing.v2 can measure
-- which state actually refuses the attack rather than guessing again.
--
-- Being hidden is the module's ONLY class-conditional behavior, and outside it
-- a rogue or a cat druid must behave exactly like every other class. That makes
-- a false positive here indistinguishable from auto attack being broken for the
-- class, so the check is deliberately hard to trip: the aura list decides, and
-- the bonus-bar offset only fills in when the aura list cannot be read.
--
-- actionpaging.state_sequence.v1 measured GetBonusBarOffset going 0 -> 1 -> 0
-- across Rogue Stealth, so the offset is real evidence -- but it is evidence
-- about which action page is showing, not about being hidden, and a druid's
-- offset moves for every form. A readable buff list with no Stealth aura in it
-- therefore vetoes the offset outright. Druid Prowl stays on UnrealPfUI's
-- working Cat Form + stealth-aura texture pair, so ordinary Cat Form remains
-- eligible for auto attack and never consults the offset at all.
--
-- Being hidden suspends the engagement rather than ending it: a rogue who picks
-- a target while stealthed and then opens used to arrive with nothing watching,
-- because the very first check had already thrown the watch away.
--
-- Bow/gun Shoot uses its action's min/max range. That takes precedence over
-- the wider melee-interact approximation, including where both report true.
-- Follow a selected target between ranged and melee while its attack remains
-- active. An explicit stop drops this watch until the next target selection.
--
-- The client also ends a ranged auto-repeat by itself, and that is not an
-- explicit stop. rangedshot.v1 caught it three times in one minute: each time
-- the hunter ran toward the target, the shot was cancelled as
-- STOP_AUTOREPEAT_SPELL and SPELLCAST_INTERRUPTED sharing one timestamp, and
-- the player arrived in melee range with nothing attacking. The two events
-- arrive in either order within the batch, so that decision is deferred to the
-- end of it, and a re-activation cooldown keeps a repeatedly cancelled shot
-- from becoming a per-tick retry loop while the player is still running.
--
-- Classifying the stop is not enough on its own, because a stop can also carry
-- nothing to classify, and because a ranged attack can lapse without any stop
-- event reaching this module at all. Both of those used to end the engagement
-- outright, and both only happen where the shot ends BEFORE the player reaches
-- melee reach, which is why the handoff worked on one pull and not the next.
--
-- So a stop no longer ends the engagement; at most it ends the shooting. The
-- follow tracks whether the attack was ever seen running: a toggle that never
-- became visible is still abandoned, because that is a client that did not act
-- on it, but an attack that was running and then stopped simply re-picks the
-- mode. A stop that looks deliberate -- no interruption, and not already in
-- melee reach -- retires the ranged half only, so shooting does not resume,
-- while walking into melee reach still attacks. The engagement itself ends
-- with the target: a new target, an unattackable one, stealth, or the option
-- being turned off.
--
-- The engagement is also adopted from START_AUTOREPEAT_SPELL, so a shot the
-- player started themselves -- by key, macro, or on a target selected long
-- before -- is followed into melee exactly like one this module issued. The
-- range watch is otherwise only armed by a target change, which is why an
-- Auto Shot begun by hand used to have nothing following it at all.

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

-- Target epoch the range watch is armed for; nil when it is not running.
local rangeWatchEpoch
local TryStartAttack
local followMode
local followPendingUntil = 0
local switchingAttack = false

-- Whether the followed attack has actually been seen running. This is what
-- separates "the client never acted on the toggle" from "it was attacking and
-- something ended it", which need opposite answers.
local followConfirmed = false

-- Set when a stop reads as the player's own. Shooting is not resumed for this
-- target while it holds, but the melee handoff still is.
local rangedRetired = false

-- A stop is being classified this frame; nothing else may act until it is.
local stopPending = false

-- Toggles that were issued and never seen running. A client that does not act
-- on one must not be asked forever, but the engagement is not something to
-- throw away either: the player is usually still closing the distance, and
-- getting closer is exactly what makes another attempt worth making.
local UNCONFIRMED_ATTEMPT_LIMIT = 3
local unconfirmedMode
local unconfirmedClosed = false
local unconfirmedCount = 0

-- GetTime of the last interruption, used only to classify an auto-repeat stop
-- that shares its timestamp, and the last toggle this module issued.
local rangedInterruptAt = -1
local lastAttempt = { mode = nil, at = 0 }

-- Keep the target-change handoff armed briefly. The user-confirmed missed
-- attack is consistent with PLAYER_TARGET_CHANGED arriving before the click
-- finishes dropping the old auto-attack state; if PLAYER_LEAVE_COMBAT follows,
-- the new target needs one more check. The window is only for that handoff; it
-- must not turn an ordinary later manual stop back on.
local TARGET_SETTLE_SECONDS = 0.5

-- An AttackTarget call that nothing ever confirms is assumed to have failed, so
-- the fallback belief cannot outlive the swing it was standing in for.
local UNCONFIRMED_ATTACK_SECONDS = 3

-- The client can cancel a shot as fast as the player can re-issue one, so a
-- mode that was just cancelled is not retried within this window. It only
-- gates a repeat of the same mode; a genuine ranged-to-melee switch is not
-- delayed by it.
local REACTIVATE_COOLDOWN = 0.5

-- Nothing reports a distance change, so an out-of-range target is polled on the
-- shared updater at the same rate the swing bar refreshes its own range state.
local RANGE_INTERVAL = 0.15
local RANGE_WATCH_ID = "autoattack.range"

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

-- One pass over the player's own auras. First return says whether the list
-- could be read at all, which is what separates "no Stealth aura" -- a real
-- answer -- from "this client would not tell us", where the offset still has
-- to stand in. An empty list is a readable answer: a hidden player always
-- carries the aura that hides them.
local function ScanHiddenAuras()
  local getTexture = U.G("GetPlayerBuffTexture")
  if type(getTexture) ~= "function" then return false end

  local stealth, cat, prowl = false, false, false
  local index
  for index = 0, 31 do
    local ok, texture = pcall(getTexture, index)
    if not ok then return false end
    if type(texture) ~= "string" or texture == "" then break end

    texture = string.lower(texture)
    if string.find(texture, "ability_stealth", 1, true) then stealth = true end
    if string.find(texture, "ability_druid_catform", 1, true) then cat = true end
    if string.find(texture, "ability_ambush", 1, true) or
       string.find(texture, "ability_druid_supriseattack", 1, true) then
      prowl = true
    end
  end

  return true, stealth, cat, prowl
end

local function ComputeHidden()
  local class = PlayerClass()
  if class ~= "ROGUE" and class ~= "DRUID" then return false end

  local readable, stealth, cat, prowl = ScanHiddenAuras()
  if class == "DRUID" then
    -- Cat Form alone is an ordinary melee form and must attack like any other.
    -- The offset is never consulted here: it moves for every druid form.
    return readable and cat and prowl or false
  end

  local offsetHidden = false
  local getBonusBarOffset = U.G("GetBonusBarOffset")
  if type(getBonusBarOffset) == "function" then
    local ok, offset = pcall(getBonusBarOffset)
    offsetHidden = ok and tonumber(offset) == 1
  end

  -- A readable aura list that does not contain Stealth means the rogue is not
  -- hidden, whatever page the bars happen to be showing.
  if readable and not stealth then return false end
  return (readable and stealth) or offsetHidden
end

-- Recomputed at most every HIDDEN_CACHE_SECONDS, and immediately whenever the
-- client reports auras or the bonus bar changing. The range watch asks this
-- several times a second, and the aura pass is 32 calls.
local HIDDEN_CACHE_SECONDS = 0.2
local hiddenCache
local hiddenCacheAt = -1

local function ForgetHidden()
  hiddenCache = nil
end

local function IsHidden()
  local now = Now()
  if hiddenCache ~= nil and now and now < hiddenCacheAt + HIDDEN_CACHE_SECONDS then
    return hiddenCache
  end
  hiddenCache = ComputeHidden()
  hiddenCacheAt = now or 0
  return hiddenCache
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

-- The swing bar counts the melee swings this client actually reported, kept
-- apart from its clock anchor because PLAYER_ENTER_COMBAT anchors that too.
-- true: something is swinging. false: the lane is live and nothing has been
-- reported. nil: nothing to read -- no swing bar, lane inactive, or no weapon
-- speed -- in which case the caller keeps its previous behavior. The second
-- return is the weapon's swing time, i.e. how long an answer of false has to
-- stand before it means anything.
local function MeleeSwingObserved()
  local fn = U.MeleeSwingTiming
  if type(fn) ~= "function" then return nil end
  local ok, _, speed, _, active, _, _, _, _, _, _, _, swings = pcall(fn)
  if not ok or not speed or not active then return nil end
  return (tonumber(swings) or 0) > 0, speed
end

-- Second return says whether the client itself answered, which is what tells a
-- measured state apart from a belief nothing can contradict.
local function IsAttacking()
  local live = LiveAttackState()
  if live ~= nil then return live, true end

  if not attacking then return false, false end
  if attackConfirmed then return true, false end

  -- Unconfirmed and unreadable: let it lapse rather than block every future
  -- target change on a call that may never have started a swing. Out of combat
  -- only -- of the two ways to be wrong here, cancelling a swing that is really
  -- running is the worse one, and the combat flag is the last cheap signal that
  -- one might be.
  local now = Now()
  if now and now > attackStartedAt + UNCONFIRMED_ATTACK_SECONDS and
     not ApiTruth("UnitAffectingCombat", "player") then
    attacking = false
    return false, false
  end

  return true, false
end

-- Shared read-only state for modules that need to follow the real attack
-- toggle without duplicating the guarded action-slot scan above. The swing bar
-- uses this for manual attacks as well as attacks started by this module.
function U.IsAutoAttacking()
  return (IsAttacking())
end

local function TargetIsAttackable()
  if not ApiTruth("UnitExists", "target") then return false end
  if ApiTruth("UnitIsDead", "target") then return false end
  if ApiTruth("UnitIsGhost", "target") then return false end
  return ApiTruth("UnitCanAttack", "player", "target")
end

function U.IsAttackTargetValid()
  return TargetIsAttackable()
end

-- U.MeleeInteractRange is the shared CheckInteractDistance approximation, and
-- it returns nil when the client cannot answer. That degrades open: an
-- unreadable range call leaves auto attack behaving as it did before this gate
-- rather than turning the feature off entirely.
local function TargetInMeleeRange()
  local inRange = U.MeleeInteractRange("target")
  if inRange == nil then return true end
  return inRange
end

-- Positive evidence only. Degrading open is right for starting an attack, but
-- an unreadable range call must not be enough to override a player's stop.
local function ConfirmedMeleeRange()
  return U.MeleeInteractRange("target") == true
end

local function StopRangeWatch()
  followMode = nil
  followPendingUntil = 0
  followConfirmed = false
  rangedRetired = false
  unconfirmedMode = nil
  unconfirmedCount = 0
  lastAttempt.mode = nil
  if rangeWatchEpoch == nil then return end
  rangeWatchEpoch = nil
  U.UnregisterUpdate(RANGE_WATCH_ID)
end

-- Keeps re-checking the same target until it is reachable, replaced, or no
-- longer attackable. Re-arming for an epoch already being watched would only
-- reset the updater's phase, so it is skipped.
local function WatchAttackRange(epoch)
  if rangeWatchEpoch == epoch then return end
  rangeWatchEpoch = epoch
  U.RegisterUpdate(RANGE_WATCH_ID, RANGE_INTERVAL, function()
    if rangeWatchEpoch ~= targetEpoch then
      StopRangeWatch()
      return
    end
    TryStartAttack(rangeWatchEpoch)
  end)
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

function TryStartAttack(epoch)
  if epoch ~= targetEpoch then return end
  if not config or not config.enabled then
    StopRangeWatch()
    return
  end
  if not TargetIsAttackable() then
    StopRangeWatch()
    return
  end
  -- Hidden is a state to wait out, not a reason to forget the target.
  if IsHidden() then
    WatchAttackRange(epoch)
    return
  end
  -- A stop is being classified this frame; let it finish before acting.
  if stopPending then return end

  local ranged, rangedInRange, rangedSlot, autoShot = U.RangedAttackState()
  local melee = IsAttacking()
  local now = Now() or 0
  local canShoot = rangedSlot ~= nil and (autoShot or U.HasBowOrGun())

  if followMode then
    local active = (followMode == "ranged" and ranged) or
                   (followMode == "melee" and melee and not ranged)

    if active then
      followConfirmed = true
      followPendingUntil = 0
      unconfirmedMode = nil
      unconfirmedCount = 0
    elseif not followConfirmed then
      -- Issued and never seen running. Give the toggle time to appear, then
      -- count it and re-pick rather than either retrying forever or dropping a
      -- target the player is still walking toward.
      if now < followPendingUntil then return end
      local closed = ConfirmedMeleeRange()
      if unconfirmedMode ~= followMode or unconfirmedClosed ~= closed then
        unconfirmedMode, unconfirmedClosed, unconfirmedCount = followMode, closed, 0
      end
      unconfirmedCount = unconfirmedCount + 1
      followMode = nil
      followPendingUntil = 0
    else
      -- It was running and is not any more. Whatever ended it, and wherever
      -- the player is standing, the engagement continues: re-pick below.
      followMode = nil
      followConfirmed = false
      followPendingUntil = 0
    end
  end

  -- The ranged action's own min/max range still decides, and it must: the
  -- melee-interact approximation is far wider than melee reach, so preferring
  -- melee wherever both report true would leave a hunter swinging at nothing
  -- from 9 yards. A thrown weapon reports in range at any distance, but it is
  -- only ever chosen while its auto-repeat is genuinely running.
  local closed = ConfirmedMeleeRange()
  local mode
  if rangedInRange == true and (canShoot or ranged) then
    mode = "ranged"
  elseif TargetInMeleeRange() then
    -- An unreadable Shoot range must not cancel an active ranged attack.
    if ranged and rangedInRange == nil then
      WatchAttackRange(epoch)
      return
    end
    mode = "melee"
  else
    WatchAttackRange(epoch)
    return
  end

  if (mode == "ranged" and ranged) or (mode == "melee" and melee and not ranged) then
    followMode = mode
    followConfirmed = true
    WatchAttackRange(epoch)
    return
  end

  -- The player stopped shooting this target. Keep following it so closing to
  -- melee still attacks, but do not put the shot back up.
  if mode == "ranged" and rangedRetired then
    WatchAttackRange(epoch)
    return
  end

  -- The same mode was issued a moment ago and the client is not showing it as
  -- active. Keep following, but let the situation change before re-issuing.
  if lastAttempt.mode == mode and now < lastAttempt.at + REACTIVATE_COOLDOWN then
    WatchAttackRange(epoch)
    return
  end

  -- This mode has been issued from here several times without the client ever
  -- showing it active. Stop asking until something about the situation moves.
  if unconfirmedCount >= UNCONFIRMED_ATTEMPT_LIMIT and unconfirmedMode == mode and
     unconfirmedClosed == closed then
    WatchAttackRange(epoch)
    return
  end

  local fn = U.G(mode == "ranged" and "UseAction" or "AttackTarget")
  if type(fn) ~= "function" then StopRangeWatch() return end

  lastAttempt.mode = mode
  lastAttempt.at = now
  followMode = mode
  followConfirmed = false
  followPendingUntil = now + TARGET_SETTLE_SECONDS
  WatchAttackRange(epoch)
  switchingAttack = true
  local ok
  if mode == "ranged" then ok = pcall(fn, rangedSlot) else ok = pcall(fn) end
  switchingAttack = false
  if not ok then StopRangeWatch() return end

  if mode == "melee" then
    attacking = true
    attackConfirmed = false
    attackStartedAt = now
    ConfirmAttack(epoch)
  else
    attacking = false
    attackConfirmed = false
  end
end

-- Read-only diagnostic surface. No behavior depends on it; a focused capture
-- uses it to see which of the follow, belief and range states is the one
-- refusing to start an attack.
function U.AutoAttackState()
  local melee, readable = IsAttacking()
  return followMode, followConfirmed, rangedRetired, rangeWatchEpoch, targetEpoch,
         melee, readable, attacking, attackConfirmed, liveStateProven,
         AttackSlot(), unconfirmedCount, MeleeSwingObserved(), IsHidden()
end

local function QueueTargetAttack(epoch)
  U.DeferOnce("autoattack.target", function()
    TryStartAttack(epoch)
  end)
end

local function OnTargetChanged()
  stopPending = false
  StopRangeWatch()
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
  config = U.ModuleConfig("autoattack", { enabled = false })
end

function AA:OnEnable()
  if not config then
    config = U.ModuleConfig("autoattack", { enabled = false })
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
    if switchingAttack then return end
    if not recentRetryUsed and recentTargetEpoch == targetEpoch and now and
       now <= recentTargetUntil then
      recentRetryUsed = true
      StopRangeWatch()
      QueueTargetAttack(targetEpoch)
    else
      recentTargetEpoch = nil
      if followMode == "melee" then StopRangeWatch() end
    end
  end)
  U.RegisterEvent("SPELLCAST_INTERRUPTED", function()
    rangedInterruptAt = Now() or -1
  end)
  U.RegisterEvent("START_AUTOREPEAT_SPELL", function()
    if not config or not config.enabled then return end
    if not TargetIsAttackable() then return end
    -- Starting a shot again is the player asking for it back.
    rangedRetired = false
    if followMode == "ranged" and rangeWatchEpoch == targetEpoch then return end
    followMode = "ranged"
    followConfirmed = true
    followPendingUntil = 0
    WatchAttackRange(targetEpoch)
  end)
  U.RegisterEvent("STOP_AUTOREPEAT_SPELL", function()
    if switchingAttack or followMode ~= "ranged" then return end
    local epoch = targetEpoch
    local now = Now()

    -- Nothing may act on the stop until the whole batch has been delivered:
    -- the interruption that explains it can still be behind it.
    stopPending = true

    U.DeferOnce("autoattack.ranged-stop", function()
      stopPending = false
      if epoch ~= targetEpoch or followMode ~= "ranged" then return end

      -- An interruption at or after the stop's own timestamp is the client
      -- ending the shot, not the player; so is any stop that happens with the
      -- target already within melee reach.
      local clientEnded = (now and rangedInterruptAt >= now - 0.001) or
                          ConfirmedMeleeRange()
      followMode = nil
      followConfirmed = false
      followPendingUntil = 0

      if not clientEnded then
        -- Read as the player's own stop, so the shot is not put back up. The
        -- handoff is kept: walking into melee reach is not a request to stand
        -- there doing nothing.
        rangedRetired = true
        -- Except during the target-change handoff, where a left click on a new
        -- target can stop the old attack just after the new one is announced.
        if not recentRetryUsed and recentTargetEpoch == targetEpoch and now and
           now <= recentTargetUntil then
          recentRetryUsed = true
          rangedRetired = false
        end
      end
      TryStartAttack(epoch)
    end)
  end)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", OnTargetChanged)

  -- The cached Attack slot is only valid for the current bar contents.
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", ForgetAttackSlot)
  U.RegisterEvent("ACTIONBAR_PAGE_CHANGED", ForgetAttackSlot)
  U.RegisterEvent("UPDATE_BONUS_ACTIONBAR", ForgetAttackSlot)
  U.RegisterEvent("UPDATE_BONUS_ACTIONBAR", ForgetHidden)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", ForgetHidden)
  U.RegisterEvent("UPDATE_SHAPESHIFT_FORM", ForgetHidden)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", ForgetAttackSlot)
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", U.InvalidateRangedAttack)
  U.RegisterEvent("ACTIONBAR_PAGE_CHANGED", U.InvalidateRangedAttack)
  U.RegisterEvent("UPDATE_BONUS_ACTIONBAR", U.InvalidateRangedAttack)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", U.InvalidateRangedAttack)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", U.InvalidateRangedAttack)
end
