-- unrealUI :: modules/rogue.lua
--
-- Rogue-only bag conveniences. Poison Shift-clicks are opt-in and preserve
-- the stock item-slot handler for every other click, including Shift-click
-- chat linking while the native chat edit box is open.
--
-- CastSpell/CastSpellByName are documented as protected on this client, so
-- the Pick Lock bag shortcut deliberately activates an existing action-bar
-- copy through UseAction instead. The icon appears when the spell is known;
-- its tooltip explains when Pick Lock still needs to be placed on a bar.

local U = UnrealUI
local M = U.media

local R = U.RegisterModule("rogue")

local rogue = {
  defaults = { poisonShiftClick = false },
  classKnown = false,
  isRogue = false,
  pickLockSpell = nil,
  pickLockAction = nil,
  pickLockTexture = "spell_nature_moonkey",
  poisonSubTypes = {
    Poison = true,
    Poisons = true,
    ["毒药"] = true,
    ["毒藥"] = true,
    ["Яд"] = true,
    ["Яды"] = true,
  },
  consumableTypes = {
    Consumable = true,
    ["消耗品"] = true,
    ["Расходуемые"] = true,
    Consommable = true,
  },
  -- Standard Rogue poisons use one of these item/spell icons. This is a
  -- fallback for clients that report their subtype as Item Enhancement rather
  -- than Poison; the Consumable class check keeps similarly named equipment
  -- and abilities out of the path.
  poisonTextures = {
    ability_poisons = true,
    ability_poisonsting = true,
    spell_nature_nullifydisease = true,
    ability_rogue_dualweild = true,
    inv_misc_herb_16 = true,
  },
}

function rogue.Config()
  return U.ModuleConfig("rogue", rogue.defaults)
end

function rogue.IsPlayer()
  if rogue.classKnown then return rogue.isRogue end

  local ok, _, token = pcall(UnitClass, "player")
  if ok and type(token) == "string" then
    rogue.classKnown = true
    rogue.isRogue = token == "ROGUE"
  end
  return rogue.isRogue
end

U.IsRogue = rogue.IsPlayer

function rogue.ChatIsEditing()
  local edit = U.G("ChatFrameEditBox")
  if not edit or type(edit.IsVisible) ~= "function" then return false end
  local ok, visible = pcall(edit.IsVisible, edit)
  return ok and visible and true or false
end

function rogue.MouseButton(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  local legacy = U.G("arg1")
  if type(legacy) == "string" then return legacy end
  return nil
end

function rogue.CursorBusy()
  local hasItem = U.G("CursorHasItem")
  if type(hasItem) == "function" then
    local ok, value = pcall(hasItem)
    if ok and value then return true end
  end

  local hasSpell = U.G("CursorHasSpell")
  if type(hasSpell) == "function" then
    local ok, value = pcall(hasSpell)
    if ok and value then return true end
  end
  return false
end

function rogue.IsPoisonItem(bag, slot)
  local linkOk, link = pcall(GetContainerItemLink, bag, slot)
  if not linkOk or not link then return false end

  -- Official client documentation records the tuple as name, link, quality,
  -- minLevel, type, subType, stackCount, equipLoc, texture.
  local infoOk, _, _, _, _, itemType, itemSubType, _, _, texture =
    pcall(GetItemInfo, link)
  if not infoOk then return false end
  if rogue.poisonSubTypes[itemSubType] then return true end
  if not rogue.consumableTypes[itemType] then return false end

  if type(texture) ~= "string" then
    local textureOk, containerTexture = pcall(GetContainerItemInfo, bag, slot)
    if textureOk then texture = containerTexture end
  end
  if type(texture) ~= "string" then return false end

  local lower = string.lower(texture)
  local token
  for token in pairs(rogue.poisonTextures) do
    if string.find(lower, token, 1, true) then return true end
  end
  return false
end

function rogue.ApplyPoison(bag, slot, inventorySlot)
  local useOk = pcall(UseContainerItem, bag, slot)
  if not useOk then return end

  -- Do not pick the weapon up if using the item failed to produce an item-
  -- targeting spell cursor (cooldown, combat restriction, unusable item, ...).
  local isTargeting = U.G("SpellIsTargeting")
  if type(isTargeting) == "function" then
    local targetOk, targeting = pcall(isTargeting)
    if targetOk and not targeting then return end
  end

  pcall(PickupInventoryItem, inventorySlot)
end

function U.TryRoguePoisonClick(bag, slot, a, b)
  if not rogue.IsPlayer() or not rogue.Config().poisonShiftClick then
    return false
  end

  local shiftOk, shift = pcall(IsShiftKeyDown)
  if not shiftOk or not shift or rogue.ChatIsEditing() then return false end

  local button = rogue.MouseButton(a, b)
  local inventorySlot
  if button == "LeftButton" then
    inventorySlot = 16
  elseif button == "RightButton" then
    inventorySlot = 17
  else
    return false
  end

  if not rogue.IsPoisonItem(bag, slot) or rogue.CursorBusy() then return false end
  rogue.ApplyPoison(bag, slot, inventorySlot)
  return true
end

function rogue.TextureMatches(texture, token)
  return type(texture) == "string" and
         string.find(string.lower(texture), token, 1, true) and true or false
end

function rogue.ScanPickLock()
  rogue.pickLockSpell = nil
  rogue.pickLockAction = nil
  if not rogue.IsPlayer() then return end

  local tabsOk, tabCount = pcall(GetNumSpellTabs)
  tabCount = (tabsOk and tonumber(tabCount)) or 0
  local bookType = U.G("BOOKTYPE_SPELL") or "spell"
  local tab
  for tab = 1, tabCount do
    local tabOk, _, _, offset, count = pcall(GetSpellTabInfo, tab)
    offset = (tabOk and tonumber(offset)) or 0
    count = (tabOk and tonumber(count)) or 0

    local spell
    for spell = offset + 1, offset + count do
      local textureOk, texture = pcall(GetSpellTexture, spell, bookType)
      if textureOk and rogue.TextureMatches(texture, rogue.pickLockTexture) then
        rogue.pickLockSpell = spell
        break
      end
    end
    if rogue.pickLockSpell then break end
  end

  if not rogue.pickLockSpell then return end

  local action
  for action = 1, 120 do
    local actionOk, texture = pcall(GetActionTexture, action)
    if actionOk and rogue.TextureMatches(texture, rogue.pickLockTexture) then
      rogue.pickLockAction = action
      return
    end
  end
end

function rogue.PublishState()
  rogue.ScanPickLock()
  if type(U.RefreshRogueBagButton) == "function" then
    U.RefreshRogueBagButton()
  end
end

function U.RogueHasPickLock()
  return rogue.pickLockSpell and true or false
end

function U.RoguePickLockActionAvailable()
  return rogue.pickLockAction and true or false
end

function U.ActivateRoguePickLock()
  rogue.ScanPickLock()
  if rogue.pickLockAction then
    local ok = pcall(UseAction, rogue.pickLockAction)
    if ok then return true end
  end
  U.Print(U.L("BAGS_PICK_LOCK_ACTION_HINT"))
  return false
end

function rogue.BuildSettingsPage(parent)
  local widgets = {}

  local header = U.CreateSectionHeader(parent, {
    text = U.L("ROGUE_SETTINGS_HEADER"),
    width = 484,
    y = -4,
  })
  table.insert(widgets, header)

  local poison = U.CreateCheckbox(parent, {
    name = "UnrealUIRoguePoisonShiftClick",
    text = U.L("ROGUE_POISON_SHIFT_CLICK"),
    value = rogue.Config().poisonShiftClick,
    onChange = function(value)
      rogue.Config().poisonShiftClick = value
    end,
  })
  poison.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
  table.insert(widgets, poison)

  local hint = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = 484,
  })
  if hint then
    U.AnchorSettingsDescription(hint, poison.box)
    hint:SetText(U.L("ROGUE_POISON_SHIFT_CLICK_HINT"))
    table.insert(widgets, hint)
  end

  local function Refresh()
    poison.SetValue(rogue.Config().poisonShiftClick)
  end
  return widgets, Refresh
end

function R:OnEnable()
  if not rogue.IsPlayer() then return end

  U.RegisterSettingsTab("rogue", U.L("SETTINGS_PAGE_ROGUE"),
                        rogue.BuildSettingsPage, { after = "profiles" })
  rogue.PublishState()

  U.RegisterEvent("SPELLS_CHANGED", rogue.PublishState)
  U.RegisterEvent("LEARNED_SPELL_IN_TAB", rogue.PublishState)
  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", rogue.PublishState)
end
