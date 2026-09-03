-- unrealUI :: modules/loot.lua
--
-- Sell price and equipped-item comparison on the native loot window.
--
-- Behavior only. .claude/rules/unreal-ui.md keeps the original loot interface
-- untouched, and this module honours that literally: it reads no texture and
-- writes no texture, font, colour, anchor or size. All it does is post-hook
-- OnEnter/OnLeave on each existing loot row and hand the resolved item to the
-- two shared readouts bag slots and quest rewards already drive --
-- modules/itemprice.lua for the sell value and core/itemslot.lua for the
-- equipped-item comparison tooltips.
--
-- The loot frame itself is the stock Vanilla one. The captured native layout
-- (diagnostics UnrealLootProbe /ulp layout) shows LootFrame owning
-- LootButton1..4 as real Buttons with GetID() 1..4, plus LootFrameUpButton /
-- LootFrameDownButton and the Prev/Next labels -- so the window paginates and
-- a row is a page position, not a loot slot. Everything below exists to turn
-- the one into the other safely.

local U = UnrealUI
local G = U.G
local LT = U.RegisterModule("loot")

-- Enough to cover a client that widened the stock four-row page. Discovery
-- stops at the first missing button, so the cap only bounds the scan.
local MAX_ROWS = 12

-- Loot rows this client actually has. Established once at enable time and used
-- by the paging arithmetic below.
local rows = 0

-- Every loot getter here is OFFICIAL_CLIENT_DOCUMENTATION only, so none of
-- them is called directly: a missing or throwing global leaves the row without
-- a readout instead of erroring inside the native tooltip build.
local function Call(name, a1)
  local fn = G(name)
  if type(fn) ~= "function" then return nil end

  local ok, r1, r2, r3, r4 = pcall(fn, a1)
  if not ok then return nil end
  return r1, r2, r3, r4
end

-- ---------------------------------------------------------------------------
-- Row -> loot slot
--
-- Vanilla's LootFrame_Update stores the slot it drew into a row on the button
-- as `.slot`, so that is the first candidate and, where this client sets it,
-- the exact answer. The rest reconstruct it: an unpaged window draws slot N
-- into row N, and a paged one gives the last row up to the page controls, so a
-- page carries one row fewer than there are buttons.
--
-- The candidates are then checked against the name the row is displaying,
-- because a wrong slot would quote a real price for the wrong item. A match is
-- preferred rather than required: if this client's row label does not read
-- back as the plain item name, the ordered candidates are still the answer
-- Vanilla's own arithmetic gives, and requiring a match would turn that into a
-- silent no-op.
-- ---------------------------------------------------------------------------
local function AddCandidate(list, value, total)
  value = tonumber(value)
  if not value or value < 1 or value > total then return end

  local i
  for i = 1, table.getn(list) do
    if list[i] == value then return end
  end
  table.insert(list, value)
end

local function RowText(index)
  local region = G("LootButton" .. index .. "Text")
  if not region or type(region.GetText) ~= "function" then return nil end

  local ok, text = pcall(region.GetText, region)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  return text
end

-- GetLootSlotInfo is the one getter on this path with runtime evidence:
-- behavior.json / lootbutton records it returning (texture, name, quantity,
-- quality) for a live row.
local function SlotItemName(slot)
  local _, name = Call("GetLootSlotInfo", slot)
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

local function LootPage()
  local frame = G("LootFrame")
  if not frame then return 1 end

  local page = tonumber(frame.page)
  if not page or page < 1 then return 1 end
  return page
end

local function ResolveSlot(button, index, total)
  local list = {}

  AddCandidate(list, button and button.slot, total)
  if total <= rows then AddCandidate(list, index, total) end

  local perPage = rows
  if total > rows then perPage = rows - 1 end
  if perPage > 0 then
    AddCandidate(list, perPage * (LootPage() - 1) + index, total)
  end

  AddCandidate(list, index, total)
  if table.getn(list) == 0 then return nil end

  local text = RowText(index)
  if text then
    local i
    for i = 1, table.getn(list) do
      if SlotItemName(list[i]) == text then return list[i] end
    end
  end
  return list[1]
end

-- ---------------------------------------------------------------------------
-- Hover
--
-- The stock row owns tooltip population, so these run after it: the price
-- panel lands under a populated GameTooltip and the comparison chain is placed
-- against where that tooltip actually ended up. The link comes back from the
-- price lookup rather than being read again here, which keeps both readouts on
-- one guarded identity -- including the documented-but-unverified
-- GetLootSlotLink returning nil, where the price path falls back to resolving
-- the row's displayed name.
-- ---------------------------------------------------------------------------
local function HookRow(index, button)
  if not button or button.uuiLootReadoutHooks then return end
  button.uuiLootReadoutHooks = true

  U.PostHookScript(button, "OnEnter", function()
    local total = tonumber(Call("GetNumLootItems")) or 0
    if total < 1 then return end

    local slot = ResolveSlot(button, index, total)
    if not slot then return end

    local link
    if type(U.ShowLootItemPrice) == "function" then
      link = U.ShowLootItemPrice(slot)
    end
    if type(U.ShowItemCompare) == "function" then
      U.ShowItemCompare(link)
    end
  end)

  U.PostHookScript(button, "OnLeave", function()
    if type(U.HideItemPrice) == "function" then U.HideItemPrice() end
    if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  end)
end

-- Rows exist for the life of the session -- the frame reuses them per page --
-- so one pass is normally enough. It is repeated on LOOT_OPENED anyway, and
-- the per-button guard makes that a no-op, in case a row is created later than
-- PLAYER_LOGIN on this client.
local function HookRows()
  local declared = tonumber(G("LOOTFRAME_NUMBUTTONS"))
  local i
  for i = 1, MAX_ROWS do
    local button = G("LootButton" .. i)
    if not button then break end
    if i > rows then rows = i end
    HookRow(i, button)
  end

  if declared and declared >= 1 then rows = declared end
end

function LT:OnEnable()
  HookRows()
  U.RegisterEvent("LOOT_OPENED", HookRows)

  -- The comparison tooltips are children of UIParent, not of the loot frame,
  -- so a window that closes under the cursor would otherwise leave them up.
  U.RegisterEvent("LOOT_CLOSED", function()
    if type(U.HideItemPrice) == "function" then U.HideItemPrice() end
    if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  end)
end
