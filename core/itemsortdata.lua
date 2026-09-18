-- unrealUI :: core/itemsortdata.lua
--
-- Thin reader for Database/item_sort.lua. The generated database stores one
-- packed integer per Vanilla item template; this file owns the packing format
-- so category and sort callers never duplicate it. Items absent from the
-- snapshot deliberately return nil and keep using the live-client fallback in
-- core/itemcategory.lua and core/itemsort.lua.

local U = UnrealUI
local SD = {}

SD.CATEGORY_SPAN = 67108864

-- Category ids are part of the generated-data contract. "favorite" is not
-- present here: it is a player-owned view overlay, never an item property.
SD.category = {
  [1]  = "gear",
  [2]  = "quest",
  [3]  = "consumable",
  [4]  = "food",
  [5]  = "potion",
  [6]  = "buff",
  [7]  = "bandage",
  [8]  = "explosive",
  [9]  = "reagent",
  [10] = "tradegoods",
  [11] = "recipe",
  [12] = "ammo",
  [13] = "container",
  [14] = "key",
  [15] = "junk",
  [16] = "misc",
  [31] = "unknown",
}

local packed = UnrealUIItemSortDB
if type(packed) == "table" and type(packed.items) == "table" then
  SD.items = packed.items
else
  SD.items = {}
end

-- Keep only the item-id lookup alive. The wrapper and its version marker are
-- not needed after load, and leaving a second public global invites callers to
-- depend on the generated representation instead of this reader.
UnrealUIItemSortDB = nil

function SD.ItemId(link)
  if type(link) == "number" then return math.floor(link) end
  if type(link) ~= "string" or link == "" then return nil end

  local _, _, itemId = string.find(link, "item:(%d+)")
  return tonumber(itemId)
end

-- Returns packed code, item template id, category key and the within-category
-- portion of the code. The latter is ordered family -> subgroup -> tier.
function U.ItemSortStaticInfo(link)
  local itemId = SD.ItemId(link)
  if not itemId then return nil end

  local code = SD.items[itemId]
  if type(code) ~= "number" then return nil, itemId end

  local categoryId = math.floor(code / SD.CATEGORY_SPAN)
  local category = SD.category[categoryId]
  if not category then return nil, itemId end

  return code, itemId, category, code - categoryId * SD.CATEGORY_SPAN
end

function U.ItemSortStaticCategory(link)
  local _, _, category = U.ItemSortStaticInfo(link)
  return category
end
