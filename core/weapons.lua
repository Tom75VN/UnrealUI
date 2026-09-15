-- unrealUI :: core/weapons.lua
-- Shared equipment and ranged-action reads for autoattack and swingbar.
-- GetItemInfo uses this client's tuple (equipLoc is return 8).
-- UnitAttackSpeed's second return is tied to slot 18 on this client, and
-- OffhandHasWeapon always returns false. Neither identifies an offhand weapon.
-- See knowledge.json / combat.weapon_slots_and_ranged_handoff.

local U = UnrealUI
local W = { nextScan = 0, api = {}, actionNames = {} }
local getItemInfo = U.G("GetItemInfo")

local function Call(name, a, b)
  local fn = W.api[name]
  if fn == nil then
    fn = U.G(name) or false
    W.api[name] = fn
  end
  if type(fn) ~= "function" then return nil, false end
  local ok, value = pcall(fn, a, b)
  if not ok then return nil, false end
  return value, true
end

local function Truthy(value)
  return value ~= nil and value ~= false and value ~= 0 and value ~= ""
end

function U.EquippedWeaponInfo(slot)
  local link, read = Call("GetInventoryItemLink", "player", slot)
  if not read or type(link) ~= "string" or link == "" then return nil end
  if type(getItemInfo) ~= "function" then return nil end
  local ok, name, _, _, _, _, subType, _, equipLoc, texture = pcall(getItemInfo, link)
  if not ok or not name then return nil end
  return equipLoc, subType, texture
end

function U.HasOffhandWeapon()
  local equipLoc = U.EquippedWeaponInfo(17)
  return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
end

function U.HasRangedWeapon()
  local equipLoc = U.EquippedWeaponInfo(18)
  return equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or
         equipLoc == "INVTYPE_THROWN"
end

-- These are item subclass identities, not addon display strings. An unknown
-- subclass does not authorize generic Shoot; a named hunter Auto Shot is
-- recognized independently below, without making wands start automatically.
-- rangedshot.v1 measured subclass "Gun", not Vanilla's plural "Guns".
W.projectiles = { bow = true, bows = true, gun = true, guns = true,
                  crossbow = true, crossbows = true }

function U.HasBowOrGun()
  local equipLoc, subType = U.EquippedWeaponInfo(18)
  if equipLoc ~= "INVTYPE_RANGED" and equipLoc ~= "INVTYPE_RANGEDRIGHT" then
    return false
  end
  return type(subType) == "string" and W.projectiles[string.lower(subType)] == true
end

function U.InvalidateRangedAttack()
  W.slot = nil
  W.autoShot = false
  W.actionNames = {}
  W.nextScan = 0
end

-- These are client spell identities, not the selected UnrealUI UI language.
-- The targeted UnrealPfUI env/locales_* spell tables identify Auto Shot with
-- its own Ability_Whirlwind icon, not the equipped gun/bow icon. The same icon
-- is also used by unrelated spells, so only the actual action name identifies
-- an idle hunter Auto Shot. See spellbook.action_slot_spell_identity_tooltip_unverified.
W.autoShotNames = {
  ["Auto Shot"] = true,
  ["Tir automatique"] = true,
  ["Автоматическая стрельба"] = true,
  ["自动射击"] = true,
}

local function ActionName(slot)
  if W.actionNames[slot] then return W.actionNames[slot] end
  if not W.scanner then
    local ok, tip = pcall(CreateFrame, "GameTooltip", "UnrealUIRangedActionScan",
                          nil, "GameTooltipTemplate")
    if not ok or not tip then return nil end
    W.scanner = tip
  end

  -- Same private, never-shown SetAction sequence already verified by the
  -- spellbook scanner. Never borrow or change the player's GameTooltip.
  local tip = W.scanner
  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, U.G("WorldFrame") or UIParent, "ANCHOR_NONE")
  local line = U.G("UnrealUIRangedActionScanTextLeft1")
  if line and type(line.SetText) == "function" then pcall(line.SetText, line, "") end
  if not pcall(tip.SetAction, tip, slot) then return nil end
  line = line or U.G("UnrealUIRangedActionScanTextLeft1")
  if not line or type(line.GetText) ~= "function" then return nil end
  local ok, name = pcall(line.GetText, line)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  W.actionNames[slot] = name
  return name
end

local function TextureKey(texture)
  if type(texture) ~= "string" or texture == "" then return nil end
  return string.lower(string.gsub(texture, "/", "\\"))
end

local function FindRangedSlot()
  local now = tonumber((Call("GetTime"))) or 0
  if now < W.nextScan then return W.slot end
  W.nextScan = now + 1
  W.slot = nil
  W.autoShot = false
  if not U.HasRangedWeapon() then return nil end

  local weaponTexture = TextureKey(Call("GetInventoryItemTexture", "player", 18))
  local activeSlot, shootSlot, autoShotSlot
  local slot
  for slot = 1, 120 do
    local repeating, readable = Call("IsAutoRepeatAction", slot)
    if readable and Truthy(repeating) then
      activeSlot = activeSlot or slot
    end
    -- false/nil are idle state, not the identity of the spell. Identify Auto
    -- Shot even when inactive, independently of its icon or repetition flag.
    local macro, macroRead = Call("GetActionText", slot)
    if readable and macroRead and not Truthy(macro) then
      local attack, spellRead = Call("IsAttackAction", slot)
      if spellRead and attack ~= nil and not Truthy(attack) then
        local name = ActionName(slot)
        if name and W.autoShotNames[name] then
          autoShotSlot = autoShotSlot or slot
        end
        -- Keep generic Shoot as a fallback, but scan all slots for Auto Shot
        -- first: a hunter can have both actions on the bars.
        if weaponTexture and repeating ~= nil and
           TextureKey(Call("GetActionTexture", slot)) == weaponTexture then
          shootSlot = shootSlot or slot
        end
      end
    end
  end
  W.slot = activeSlot or autoShotSlot or shootSlot
  W.autoShot = W.slot ~= nil and W.slot == autoShotSlot
  W.autoShotSlot = autoShotSlot
  return W.slot
end

-- Active, in range (nil if unreadable), slot, positively identified Auto Shot.
-- The identity lets a hunter start Auto Shot without relying on English item
-- subclass strings. Still require positive range evidence before activation.
function U.RangedAttackState()
  local slot = FindRangedSlot()
  if not slot then return false, nil, nil, false end
  local active = Truthy(Call("IsAutoRepeatAction", slot))
  local range, read = Call("IsActionInRange", slot)
  if not read or range == nil then return active, nil, slot, W.autoShot end
  return active, Truthy(range), slot, W.autoShot
end

-- Hunter Auto Shot placement. UseAction is the only unprotected way to start
-- Auto Shot (CastSpell and CastSpellByName are protected), so a hunter with the
-- action on no bar cannot shoot from target selection. autoshotslot.v2
-- measured PickupSpell + PlaceAction filling an empty slot in 1-72 at once,
-- firing ACTIONBAR_SLOT_CHANGED, surviving /reload, and UseAction starting
-- Auto Shot from it. v1 aimed the same sequence at slot 120: the cursor was
-- consumed and the slot stayed empty, hence the 72 ceiling.
-- See knowledge.json / actionbars.addon_place_autoshot_empty_slot.
W.PLACE_LAST_SLOT = 72
W.PLACE_RETRY_SECONDS = 10
W.nextPlaceAt = 0

function W.SpellbookAutoShot()
  local getTab = U.G("GetSpellTabInfo")
  local getName = U.G("GetSpellName")
  if type(getTab) ~= "function" or type(getName) ~= "function" then return nil end
  local bookType = U.G("BOOKTYPE_SPELL")
  if type(bookType) ~= "string" then bookType = "spell" end

  local total = 0
  local tabs = tonumber((Call("GetNumSpellTabs"))) or 0
  local tab
  for tab = 1, tabs do
    local ok, _, _, offset, count = pcall(getTab, tab)
    if ok and type(offset) == "number" and type(count) == "number" and
       offset + count > total then
      total = offset + count
    end
  end
  local index
  for index = 1, total do
    local ok, name = pcall(getName, index, bookType)
    if ok and type(name) == "string" and W.autoShotNames[name] then
      return index, bookType
    end
  end
  return nil
end

-- Returns the slot holding Auto Shot, placing it first when no bar has one.
-- Never overwrites an action or takes over a busy cursor, never leaves the
-- picked-up spell on the cursor, and waits PLACE_RETRY_SECONDS after an attempt
-- that did not end with Auto Shot on a bar, so a refusal is not re-asked on
-- every target change.
function U.EnsureAutoShotAction()
  local unitClass = U.G("UnitClass")
  if type(unitClass) ~= "function" then return nil end
  local okClass, _, class = pcall(unitClass, "player")
  if not okClass or class ~= "HUNTER" or not U.HasRangedWeapon() then return nil end

  local now = tonumber((Call("GetTime"))) or 0
  U.InvalidateRangedAttack()
  FindRangedSlot()
  if W.autoShotSlot then return W.autoShotSlot end
  if now < W.nextPlaceAt then return nil end
  W.nextPlaceAt = now + W.PLACE_RETRY_SECONDS

  if Truthy((Call("CursorHasSpell"))) or Truthy((Call("CursorHasItem"))) then
    return nil
  end
  local index, bookType = W.SpellbookAutoShot()
  if not index then return nil end

  local target
  local slot
  for slot = W.PLACE_LAST_SLOT, 1, -1 do
    local has, read = Call("HasAction", slot)
    if read and not Truthy(has) then
      target = slot
      break
    end
  end
  if not target then return nil end

  local pickup = U.G("PickupSpell")
  local place = U.G("PlaceAction")
  if type(pickup) ~= "function" or type(place) ~= "function" then return nil end
  if not pcall(pickup, index, bookType) then return nil end
  if not Truthy((Call("CursorHasSpell"))) then return nil end
  pcall(place, target)
  if Truthy((Call("CursorHasSpell"))) then Call("ClearCursor") end

  U.InvalidateRangedAttack()
  FindRangedSlot()
  if W.autoShotSlot then W.nextPlaceAt = 0 end
  return W.autoShotSlot
end
