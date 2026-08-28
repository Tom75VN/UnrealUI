-- unrealUI :: modules/bank.lua
--
-- The bank window, in unrealUI's modern style: one flat near-black panel with
-- a single 1-unit outline, the purchased bank bags and a purchase control in
-- the header, the addon-accent "Bank" title, an owned close glyph, and the
-- bank container plus every purchased bank bag packed into one continuous slot
-- grid at the same density as the bag frame.
--
-- It is deliberately the same component as the bag window: both draw their
-- slots with core/itemslot.lua and both take their metrics from
-- core/media.lua's M.slot, so the two windows cannot drift into two styles.
-- There is no search field: .claude/rules/unreal-ui-design.md excludes text
-- inputs on this client (knowledge.json / widgets.editbox_focus_crash), and
-- the omission was confirmed with the user rather than guessed.
--
-- Evidence:
--
--   * documentation.json (OFFICIAL_CLIENT_DOCUMENTATION,
--     DOCUMENTED_NOT_RUNTIME_VERIFIED) covers the Bank category used here:
--     GetNumBankSlots, GetBankSlotCost, PurchaseSlot, CloseBankFrame and
--     BankButtonIDToInvSlotID.
--   * The container half (GetContainerNumSlots / GetContainerItemInfo / the
--     item-button templates) is the same INCONCLUSIVE record the bag frame
--     runs on -- knowledge.json / bags.container_api_contract_unverified.
--   * BANKFRAME_OPENED / BANKFRAME_CLOSED / PLAYERBANKSLOTS_CHANGED /
--     PLAYERBANKBAGSLOTS_CHANGED have no compact record at all, and
--     BankItemButtonGenericTemplate / BankItemButtonBagTemplate have none
--     either. Per the UnrealPfUI evidence-gap fallback they default to what
--     UnrealPfUI/modules/bags.lua demonstrably does on this same client:
--     bank container -1 with the generic bank template, and bank bag buttons
--     on BankItemButtonBagTemplate carrying SetID(slot + 4) so container ids
--     land on 5..10. WORKING_SOURCE only, never runtime verified.
--
-- The native BankFrame is parked far off-screen, never hidden. In
-- Vanilla-shaped FrameXML the stock frame's OnHide calls CloseBankFrame, so
-- hiding it would end the banker session the moment unrealUI's window opened;
-- UnrealPfUI avoids that the same way (its bags.lua:83). This is why the bank
-- is *not* registered with U.SuppressNativeFrame, which hides the object and
-- neutralises its Show by design. Alpha and scale were the first attempt and
-- this client ignored both -- see NeutraliseNativeBank.

local U = UnrealUI
local M = U.media

local BK = U.RegisterModule("bank")

local BANK_CONTAINER  = -1
local BANK_BAG_OFFSET = 4     -- bank bag n is container n + 4, i.e. 5..10
local MAX_BANK_BAGS   = 6     -- NUM_BANKBAGSLOTS in Vanilla FrameXML
local BANK_SLOTS      = 24    -- NUM_BANKGENERIC_SLOTS in Vanilla FrameXML
local NATIVE_PARK     = 4000  -- where the stock bank window is sent to

-- Shared container tokens; only the row length is this window's own.
local COLUMNS       = 10
local SLOT_SIZE     = M.slot.size
local SLOT_GAP      = M.slot.gap
local PADDING       = M.slot.padding
local HEADER_HEIGHT = M.slot.header
local ICON_SIZE     = M.slot.icon
local BAG_BUTTON    = 20      -- header bank-bag button, sized to the header

local anchor, frame, grid
local slots = {}        -- slots[bag][slot] = button
local containers = {}   -- containers[bag] = per-bag parent frame, SetID(bag)
local bagButtons = {}   -- bagButtons[n] = header bank-bag button, n = 1..6

local layoutDirty = true
local headerDirty = true
local cooldownDirty = false
local bagDirty = {}
local closing = false
local emptyReported = false

-- The Azeroth bank backend rejects a cursor item picked up from one bank
-- container when it is dropped directly into a different bank container
-- ("Item not found" -- knowledge.json /
-- bank.cross_container_transfer_requires_inventory_stage, USER_CONFIRMED_INGAME).
-- The same item succeeds after it has passed through a player-bag slot, so
-- remember which bank container supplied the cursor item and use that proven
-- route only for cross-container bank transfers.
--
-- cursorBankLink is the item the cursor is carrying.  It has to be read from
-- the source slot *before* the stock handler runs, because an item already on
-- the cursor cannot be read out of any container.  It exists so an occupied
-- player-bag slot can serve as the staging slot: swapping the cursor item
-- against a *different* item is safe, while swapping it against the same item
-- would merge the two stacks and drag the player's own items into the bank.
local cursorBankBag
local cursorBankLink

-- Shared with the bag-slot wrappers in modules/bags.lua; the reading itself
-- lives in core/compat.lua.
local function CursorHasInventoryItem()
  return U.CursorHasItem()
end

local function SlotLink(bag, slot)
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if ok and link and link ~= "" then return link end
  return nil
end

local function SlotLocked(bag, slot)
  local texture, count, locked = U.ContainerSlotInfo(bag, slot)
  return locked and true or false
end

-- Specialty bags cannot accept every item.  Prefer the backpack, then bags a
-- Vanilla-shaped GetBagFamily helper identifies as normal.  Nothing records a
-- client GetBagFamily global on this client at all -- UnrealPfUI builds its own
-- from GetInventoryItemLink/GetItemInfo rather than calling one -- so the
-- helper stays optional here: when it is missing, errors, or answers in the
-- numeric form where 0 means an ordinary bag, every bag is tried and the
-- container state below decides whether the client accepted the drop.
local function PlayerBagCanStage(bag)
  if bag == 0 then return true end

  local familyFn = U.G("GetBagFamily")
  if type(familyFn) ~= "function" then return true end

  local ok, family = pcall(familyFn, bag)
  if not ok or family == nil then return true end
  if type(family) == "number" then return family == 0 end
  return family == "BAG"
end

-- First choice: an empty player-bag slot.  The cursor item is placed there and
-- picked straight back up, which changes its source from a bank container to
-- player inventory without changing the item or its final destination.
-- Returns true on success, false after a failure that has been reported, and
-- nil when this bag simply offered no usable slot.
local function StageThroughEmptySlot(bag)
  local sizeOk, size = pcall(GetContainerNumSlots, bag)
  size = (sizeOk and tonumber(size)) or 0

  local slot
  for slot = 1, size do
    -- U.ContainerSlotHasItem, not `not texture`: an empty slot on this client
    -- reports texture "" from GetContainerItemInfo, which is truthy in Lua, so
    -- the Vanilla-shaped test matched nothing and no staging slot was ever
    -- found. core/compat.lua carries the documentation for that difference.
    if not U.ContainerSlotHasItem(bag, slot) then
      pcall(PickupContainerItem, bag, slot)
      if not CursorHasInventoryItem() then
        -- The temporary drop succeeded. Pick the same item back up so the
        -- caller can place it in the requested bank destination.
        pcall(PickupContainerItem, bag, slot)
        if CursorHasInventoryItem() then return true end

        -- The item is safe in player inventory, but the second pickup did
        -- not complete. Do not pretend the bank transfer succeeded.
        U.Print(U.L("BANK_TRANSFER_PICKUP"))
        cursorBankBag = nil
        cursorBankLink = nil
        return false
      end
    end
  end

  return nil
end

-- Fallback for full bags, which is the normal state of a player standing at a
-- banker.  A slot holding a *different* item stages just as well, because
-- PickupContainerItem swaps: the first call puts the cursor item into the slot
-- and lifts that slot's item, the second puts it back and returns the original
-- to the cursor -- now sourced from player inventory.  A slot holding the same
-- item is never used, because the stacks would merge and the player's own item
-- would travel into the bank with it; without a known cursor item the whole
-- pass is skipped rather than guessed.  Each half is confirmed by re-reading
-- the slot, so a slot the client refused (specialty bag, locked item) is
-- skipped instead of assumed, and an unexpected result stops the pass rather
-- than shuffling further items blind.
local function StageThroughOccupiedSlot(bag)
  if not cursorBankLink then return nil end

  local sizeOk, size = pcall(GetContainerNumSlots, bag)
  size = (sizeOk and tonumber(size)) or 0

  local slot
  for slot = 1, size do
    local link = SlotLink(bag, slot)
    if link and link ~= cursorBankLink and not SlotLocked(bag, slot) then
      pcall(PickupContainerItem, bag, slot)

      local now = SlotLink(bag, slot)
      if now == cursorBankLink then
        pcall(PickupContainerItem, bag, slot)
        if SlotLink(bag, slot) == link and CursorHasInventoryItem() then
          return true
        end

        -- The swap back did not complete. Both items are in inventory, so
        -- nothing is lost, but the bank transfer is not done.
        U.Print(U.L("BANK_TRANSFER_PICKUP"))
        cursorBankBag = nil
        cursorBankLink = nil
        return false
      elseif now ~= link then
        -- The slot became something neither expected. Stop rather than move
        -- more of the player's items around blind.
        U.Print(U.L("BANK_TRANSFER_PICKUP"))
        cursorBankBag = nil
        cursorBankLink = nil
        return false
      end
    end
  end

  return nil
end

local function StageCursorThroughPlayerBags()
  local bag, staged

  for bag = 0, 4 do
    if PlayerBagCanStage(bag) then
      staged = StageThroughEmptySlot(bag)
      if staged ~= nil then return staged end
    end
  end

  for bag = 0, 4 do
    if PlayerBagCanStage(bag) then
      staged = StageThroughOccupiedSlot(bag)
      if staged ~= nil then return staged end
    end
  end

  U.Print(U.L("BANK_TRANSFER_EMPTY_SLOT"))
  return false
end

local function TransferCursorToBank(bag, slot, drop)
  if not CursorHasInventoryItem() then
    cursorBankBag = nil
    cursorBankLink = nil
    return false
  end

  if cursorBankBag and cursorBankBag ~= bag then
    if not StageCursorThroughPlayerBags() then return false end
  end

  -- Read before the drop: an occupied destination hands its previous item to
  -- the cursor, and that item is what a following transfer would carry.
  local previous = SlotLink(bag, slot)

  -- Let the destination's original template perform the final drop.  The main
  -- bank and purchased bank bags use different stock templates, and retaining
  -- their own destination call avoids substituting one API for the other.
  if type(drop) ~= "function" then return false end
  drop()

  -- An occupied destination leaves its previous item on the cursor.  That
  -- item's new source is the destination container, so a following cross-bank
  -- drop must use the workaround again.
  if CursorHasInventoryItem() then
    cursorBankBag = bag
    cursorBankLink = previous
  else
    cursorBankBag = nil
    cursorBankLink = nil
  end
  return true
end

local function MouseButton(a1, a2)
  return U.MouseButton(a1, a2)
end

-- Wrap the stock template rather than discarding it: modifier clicks, stack
-- splitting, right-click use, repair targeting and tooltips remain native.
-- Only a left-button drop whose cursor source is a different bank container
-- takes the inventory-staging route above.
local function InstallBankTransfer(button, bag)
  if not button or button.uuiBankTransfer then return end
  button.uuiBankTransfer = true

  local click = button:GetScript("OnClick")
  button:SetScript("OnClick",
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local slot = button:GetID()
      local hadItem = CursorHasInventoryItem()
      local left = MouseButton(a1, a2) == "LeftButton"
      -- Whatever this slot holds now is what the cursor holds afterwards,
      -- whether the click lifts the item or swaps the cursor item for it.
      local previous = SlotLink(bag, slot)

      if left and hadItem and cursorBankBag and cursorBankBag ~= bag then
        TransferCursorToBank(bag, slot, function()
          if click then click(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
        end)
        return
      end

      if click then click(a1, a2, a3, a4, a5, a6, a7, a8, a9) end

      if left then
        if CursorHasInventoryItem() then
          cursorBankBag = bag
          cursorBankLink = previous
        else
          cursorBankBag = nil
          cursorBankLink = nil
        end
      end
    end)

  local dragStart = button:GetScript("OnDragStart")
  button:SetScript("OnDragStart",
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local previous = SlotLink(bag, button:GetID())

      if dragStart then
        dragStart(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      end
      if CursorHasInventoryItem() then
        cursorBankBag = bag
        cursorBankLink = previous
      end
    end)

  local receiveDrag = button:GetScript("OnReceiveDrag")
  button:SetScript("OnReceiveDrag",
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local slot = button:GetID()

      if CursorHasInventoryItem() and cursorBankBag and
         cursorBankBag ~= bag then
        TransferCursorToBank(bag, slot, function()
          if receiveDrag then
            receiveDrag(a1, a2, a3, a4, a5, a6, a7, a8, a9)
          end
        end)
        return
      end

      local previous = SlotLink(bag, slot)

      if receiveDrag then
        receiveDrag(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      end

      if CursorHasInventoryItem() then
        cursorBankBag = bag
        cursorBankLink = previous
      else
        cursorBankBag = nil
        cursorBankLink = nil
      end
    end)
end

-- ---------------------------------------------------------------------------
-- Bank state
-- ---------------------------------------------------------------------------
local function MaxBankBags()
  local stock = tonumber(U.G("NUM_BANKBAGSLOTS"))
  if stock and stock > 0 then return stock end
  return MAX_BANK_BAGS
end

local function PurchasedBags()
  local ok, n = pcall(GetNumBankSlots)
  n = (ok and tonumber(n)) or 0
  if n < 0 then n = 0 end
  if n > MaxBankBags() then n = MaxBankBags() end
  return n
end

-- The bank container first, then every purchased bank bag: the order the grid
-- packs them in.
local function BankBags()
  local list = { BANK_CONTAINER }
  local i
  for i = 1, PurchasedBags() do
    table.insert(list, i + BANK_BAG_OFFSET)
  end
  return list
end

-- GetContainerNumSlots is the source of truth, but it has no compact record
-- for bank containers on this client and the first in-game run came back with
-- an empty grid while the stock window showed 24 usable slots. When it reports
-- nothing for the bank container, the documented Vanilla size is used instead
-- so the window still draws; a bank bag reporting nothing really is empty.
local function BagSlotCount(bag)
  local ok, n = pcall(GetContainerNumSlots, bag)
  n = (ok and tonumber(n)) or 0
  if n > 0 then return n end

  if bag == BANK_CONTAINER then
    local stock = tonumber(U.G("NUM_BANKGENERIC_SLOTS"))
    if stock and stock > 0 then return stock end
    return BANK_SLOTS
  end

  return 0
end


-- ---------------------------------------------------------------------------
-- Native bank frame
--
-- Parked off-screen, never hidden; see the header note on why Hide() is wrong.
-- Re-applied on every refresh tick while the window is open, because the stock
-- panel manager re-anchors the windows it owns whenever it shows one.
-- ---------------------------------------------------------------------------
local function NeutraliseNativeBank()
  local native = U.G("BankFrame")
  if not native then return end

  -- Position is the one property this client demonstrably propagates from the
  -- native bank to its parts. Alpha 0 and scale 0.001 were the first attempt
  -- and both were ignored: every stock slot, bag button and the purchase
  -- dialog kept drawing at full size, while the SetPoint in the same function
  -- moved the whole stock window to exactly where it was anchored (screen
  -- top-left, user screenshot). So the stock window is parked far outside the
  -- viewport instead, which takes everything anchored to it along and still
  -- never calls Hide() -- see the header note on why hiding it is wrong.
  --
  -- Scale is reset to 1 first on purpose: SetPoint offsets are in the frame's
  -- own scale, so leaving 0.001 on it would turn the offset below into four
  -- pixels. Clamping is dropped for the same reason -- a clamped frame is
  -- pulled back onto the screen.
  pcall(native.SetScale, native, 1)
  pcall(native.SetClampedToScreen, native, false)
  pcall(native.EnableMouse, native, false)
  pcall(native.SetAlpha, native, 0)
  pcall(function()
    native:ClearAllPoints()
    native:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                    -NATIVE_PARK, NATIVE_PARK)
  end)
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------
local function EnsureBagRoot(bag, parent)
  if containers[bag] then return containers[bag] end

  local root = CreateFrame("Frame", nil, parent)
  root:SetID(bag)
  root:SetAllPoints(parent)
  containers[bag] = root
  slots[bag] = slots[bag] or {}
  return root
end

local function EnsureSlot(bag, slot, parent)
  slots[bag] = slots[bag] or {}
  if slots[bag][slot] then return slots[bag][slot] end

  local root = EnsureBagRoot(bag, parent)
  local name = "UnrealUIBankSlot" .. (bag < 0 and ("m" .. -bag) or bag) ..
               "_" .. slot

  local button = U.CreateItemSlot(root, name, bag, slot)
  if not button then return nil end

  InstallBankTransfer(button, bag)

  slots[bag][slot] = button
  return button
end

local function UpdateSlotAppearance(bag, slot)
  U.UpdateItemSlot(slots[bag] and slots[bag][slot], bag, slot)
end

local function RefreshBag(bag)
  local bagSlots = slots[bag]
  if not bagSlots then return end

  local slot
  for slot = 1, table.getn(bagSlots) do
    if bagSlots[slot] and bagSlots[slot]:IsShown() then
      UpdateSlotAppearance(bag, slot)
    end
  end
end

-- Hover feedback for a header bank bag: that bag's slots take the accent
-- outline while the pointer is over it, which is the one cheap way to tell six
-- identical-looking bags apart inside a single merged grid.
local function HighlightBag(bag, on)
  local bagSlots = bag and slots[bag]
  if not bagSlots then return end

  local slot
  for slot = 1, table.getn(bagSlots) do
    local button = bagSlots[slot]
    if button and button:IsShown() then
      if on then
        U.SetBorderColor(button, M.Unpack(M.color.accent))
      else
        UpdateSlotAppearance(bag, slot)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Header: bank bags, purchase control, title, close
-- ---------------------------------------------------------------------------
local function EnsureBankBagButton(index)
  if bagButtons[index] then return bagButtons[index] end

  local name = "UnrealUIBankBag" .. index
  local ok, button = pcall(CreateFrame, "CheckButton", name, frame.bags,
                           "BankItemButtonBagTemplate")
  if not ok or not button then
    U.Error("bank: BankItemButtonBagTemplate unavailable; bank bag " ..
            index .. " not created")
    return nil
  end

  -- UnrealPfUI's working mapping on this client: the bank bag button carries
  -- the container id, not a 1-based bag index.
  button:SetID(index + BANK_BAG_OFFSET)
  button.uuiBag = index + BANK_BAG_OFFSET
  button:SetWidth(BAG_BUTTON)
  button:SetHeight(BAG_BUTTON)
  U.StyleItemSlot(button, name)

  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(M.color.moverEdge))
    HighlightBag(button.uuiBag, true)

    local tip = U.G("GameTooltip")
    if not tip then return end
    pcall(tip.SetOwner, tip, button, "ANCHOR_BOTTOM")
    pcall(tip.SetText, tip, U.G("BANK_BAG") or "Bank Bag")
    pcall(tip.Show, tip)
  end)

  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(M.color.border))
    HighlightBag(button.uuiBag, false)
    local tip = U.G("GameTooltip")
    if tip then pcall(tip.Hide, tip) end
  end)

  bagButtons[index] = button
  return button
end

-- The bag's own icon. The stock template resolves its art through frame names
-- it does not know here, so the inventory texture is read directly and
-- BankFrameItemButton_Update is only the fallback for what that misses.
local function RefreshBankBagButton(index)
  local button = bagButtons[index]
  if not button then return end

  local texture
  local idOk, inventoryId = pcall(BankButtonIDToInvSlotID, button:GetID())
  if idOk and tonumber(inventoryId) then
    local texOk, value = pcall(GetInventoryItemTexture, "player", inventoryId)
    if texOk then texture = value end
  end

  if texture then
    pcall(SetItemButtonTexture, button, texture)
  else
    local fn = U.G("BankFrameItemButton_Update")
    if type(fn) == "function" then pcall(fn, button) end
  end

  button.tooltipText = U.L("BANK_BAG_LABEL")
  U.SetBorderColor(button, M.Unpack(M.color.border))
end

local function BankSlotCost()
  local ok, cost = pcall(GetBankSlotCost)
  return (ok and tonumber(cost)) or 0
end

local function BuyBankSlot()
  U.ShowConfirm({
    text = U.L("BANK_BUY_SLOT"),
    moneyCopper = BankSlotCost(),
    acceptText = U.L("BANK_PURCHASE"),
    owner = "bank",
    onAccept = function()
      pcall(PurchaseSlot)
      headerDirty = true
      layoutDirty = true
    end,
  })
end

-- The bag icon matches the equipped-bag toggle on the player bag window
-- (modules/bags.lua's frame.bagsToggle); the hover price is the shared
-- readout (core/widgets.lua's price panel), coloured and iconed the same as
-- the status overlay's money display (core/media.lua M.money).
local function EnsureBuyButton()
  if frame.buy then return frame.buy end

  frame.buy = U.CreateIconButton(frame.bags, {
    name = "UnrealUIBankBuySlot",
    texture = "Interface\\Icons\\INV_Misc_Bag_08",
    fallback = "+",
    size = BAG_BUTTON,
    title = U.L("BANK_PURCHASE_TITLE"),
    price = BankSlotCost,
    onClick = BuyBankSlot,
  })

  return frame.buy
end

-- Purchased bags left to right, then the purchase control while slots remain.
local function LayoutHeader()
  if not frame or not frame.bags then return end

  local purchased = PurchasedBags()
  local maximum = MaxBankBags()
  local shown = 0
  local index

  for index = 1, maximum do
    local button
    if index <= purchased then
      button = EnsureBankBagButton(index)
    else
      button = bagButtons[index]
    end

    if button then
      if index <= purchased then
        button:ClearAllPoints()
        button:SetPoint("LEFT", frame.bags, "LEFT",
                        shown * (BAG_BUTTON + SLOT_GAP), 0)
        RefreshBankBagButton(index)
        button:Show()
        shown = shown + 1
      else
        button:Hide()
      end
    end
  end

  local width = shown * (BAG_BUTTON + SLOT_GAP)

  if purchased < maximum then
    local buy = EnsureBuyButton()
    buy:ClearAllPoints()
    buy:SetPoint("LEFT", frame.bags, "LEFT", width, 0)
    buy:Show()
    width = width + BAG_BUTTON + SLOT_GAP
  elseif frame.buy then
    frame.buy:Hide()
  end

  if width > 0 then width = width - SLOT_GAP end
  frame.bags:SetWidth(math.max(1, width))
  frame.bags:SetHeight(BAG_BUTTON)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
-- Returns how many slots it actually placed, so the caller can tell an empty
-- bank from a bank whose contents have not reached the client yet.
local function LayoutSlots()
  local bags = BankBags()
  local live = {}
  local placed = 0
  local x, y = 0, 0
  local i

  for i = 1, table.getn(bags) do
    local bag = bags[i]
    live[bag] = true

    local n = BagSlotCount(bag)

    local slot
    for slot = 1, n do
      local button = EnsureSlot(bag, slot, grid)
      if button then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", grid, "TOPLEFT",
                        x * (SLOT_SIZE + SLOT_GAP),
                        -(y * (SLOT_SIZE + SLOT_GAP)))
        button:SetWidth(SLOT_SIZE)
        button:SetHeight(SLOT_SIZE)
        UpdateSlotAppearance(bag, slot)
        button:Show()
        placed = placed + 1

        if x >= COLUMNS - 1 then
          x, y = 0, y + 1
        else
          x = x + 1
        end
      end
    end

    -- A bank bag swapped for a smaller one leaves stale buttons past its size.
    local bagSlots = slots[bag]
    if bagSlots then
      local stale
      for stale = n + 1, table.getn(bagSlots) do
        if bagSlots[stale] then bagSlots[stale]:Hide() end
      end
    end
  end

  -- Slots of a bag that is gone entirely (its bank bag was taken out) stay
  -- created, but must not keep drawing over the grid.
  for bag, bagSlots in pairs(slots) do
    if not live[bag] then
      local slot
      for slot = 1, table.getn(bagSlots) do
        if bagSlots[slot] then bagSlots[slot]:Hide() end
      end
    end
  end

  if x > 0 then y = y + 1 end
  if y == 0 then y = 1 end

  -- The anchor owns the rect; the visible frame is stretched over it, so the
  -- mover handle keeps the same bounds whether or not the bank is open.
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  anchor:SetHeight(HEADER_HEIGHT + y * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
                   + PADDING)

  return placed
end

local function ProcessDirty()
  if U.PerfDisabled and U.PerfDisabled("bank") then return end

  if not CursorHasInventoryItem() then
    cursorBankBag = nil
    cursorBankLink = nil
  end

  NeutraliseNativeBank()

  if headerDirty then
    headerDirty = false
    LayoutHeader()
  end

  if layoutDirty then
    -- A layout that placed nothing is retried on the next tick rather than
    -- latched: BANKFRAME_OPENED can arrive before the client has the container
    -- contents, and nothing else would mark this dirty again. Reported once so
    -- a client that never fills the bank in is visible instead of silent.
    if LayoutSlots() > 0 then
      layoutDirty = false
      emptyReported = false
    elseif not emptyReported then
      emptyReported = true
      U.Print(U.L("BANK_SLOTS_LOADING"))
    end
  end

  local bag
  for bag, _ in pairs(bagDirty) do
    bagDirty[bag] = nil
    RefreshBag(bag)
  end

  if cooldownDirty then
    cooldownDirty = false
    local bags = BankBags()
    local i
    for i = 1, table.getn(bags) do
      local bagId = bags[i]
      local bagSlots = slots[bagId]
      if bagSlots then
        local slot
        for slot = 1, table.getn(bagSlots) do
          U.UpdateItemSlotCooldown(bagId, bagSlots[slot])
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Show / hide
--
-- The window follows the banker session rather than the other way round: the
-- close glyph and Escape both end the session, and BANKFRAME_CLOSED is what
-- actually hides the frame.
-- ---------------------------------------------------------------------------
local function ShowBank()
  if not frame then return end

  headerDirty = true
  layoutDirty = true
  frame:Show()
  U.RegisterUpdate("bank.refresh", 0.2, ProcessDirty)
  ProcessDirty()
end

local function CloseBank()
  local ok = pcall(CloseBankFrame)
  if not ok and frame then frame:Hide() end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildHeader()
  frame.close = U.CreateButton(frame, {
    name = "UnrealUIBankClose",
    text = "X",
    width = ICON_SIZE,
    height = ICON_SIZE,
    size = M.fontSize.small,
    onClick = CloseBank,
  })
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)

  frame.title = U.CreateLabel(frame, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  if frame.title then
    frame.title:SetText(U.L("BANK_TITLE"))
    frame.title:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
  end

  -- Holder for the bank bag row. Its right edge is pinned to the title, so
  -- buying a slot grows the row leftwards instead of pushing the title out.
  frame.bags = CreateFrame("Frame", "UnrealUIBankBags", frame)
  frame.bags:SetWidth(BAG_BUTTON)
  frame.bags:SetHeight(BAG_BUTTON)
  if frame.title then
    frame.bags:SetPoint("RIGHT", frame.title, "LEFT", -8, 0)
  else
    frame.bags:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
  end
end

-- ---------------------------------------------------------------------------
-- Direct drag
--
-- The header's empty strip (left of the bag row) moves the window without
-- entering edit mode first. It drags the anchor -- the same frame
-- core/mover.lua's edit-mode handle moves -- and saves to the identical
-- "bank.main" position (U.SavePosition/U.GetPosition), so a plain drag and an
-- edit-mode drag never disagree about where the window is.
--
-- Reuses the throwaway StartMoving/StopMovingOrSizing pair before the real
-- StartMoving that core/mover.lua and core/windowdrag.lua both use
-- (knowledge.json / frames.movable_drag_requires_button_handle).
-- ---------------------------------------------------------------------------
local BANK_MOVER_ID = "bank.main"

local function StartBankDrag()
  if pcall(anchor.StartMoving, anchor) then
    pcall(anchor.StopMovingOrSizing, anchor)
  end
  pcall(anchor.StartMoving, anchor)
end

local function StopBankDrag()
  pcall(anchor.StopMovingOrSizing, anchor)

  local point, _, relativePoint, x, y = U.GetFramePoint(anchor, 1)
  if point then U.SavePosition(BANK_MOVER_ID, point, relativePoint, x, y) end
end

-- Anchored to frame.bags's live left edge rather than a captured width, so it
-- keeps clear of the bank bag row as slots are bought and stays correct
-- without its own LayoutHeader hook.
local function BuildDragHandle()
  local handle = CreateFrame("Button", "UnrealUIBankDrag", frame)
  handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", frame.bags, "TOPLEFT", -4, 0)
  handle:SetHeight(HEADER_HEIGHT)
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)

  handle:SetScript("OnDragStart", StartBankDrag)
  handle:SetScript("OnDragStop", StopBankDrag)

  frame.dragHandle = handle
  return handle
end

local function Build()
  -- Same shape as the bag frame: the anchor owns the rect and is the mover
  -- target, the visible panel is stretched over it, so edit mode can place the
  -- bank while the bank is closed.
  anchor = CreateFrame("Frame", "UnrealUIBankAnchor", UIParent)
  anchor:SetWidth(COLUMNS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PADDING * 2)
  anchor:SetHeight(HEADER_HEIGHT + 4 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
                   + PADDING)

  frame = U.CreatePanel(anchor, { name = "UnrealUIBankFrame" })
  frame:SetAllPoints(anchor)
  pcall(frame.SetFrameStrata, frame, "MEDIUM")
  pcall(frame.EnableMouse, frame, true)
  frame:Hide()

  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUIBankFrame")
  end

  BuildHeader()
  BuildDragHandle()

  grid = CreateFrame("Frame", "UnrealUIBankGrid", frame)
  grid:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
  grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)

  -- Escape (UISpecialFrames) and the close glyph both end up here, so the
  -- banker session is closed from one place instead of from each caller. The
  -- guard keeps the BANKFRAME_CLOSED -> Hide -> CloseBankFrame path from
  -- looping back on itself.
  frame:SetScript("OnHide", function()
    U.UnregisterUpdate("bank.refresh")
    U.HideConfirm("bank")
    cursorBankBag = nil
    cursorBankLink = nil
    if closing then return end
    closing = true
    pcall(CloseBankFrame)
    closing = false
  end)

  U.RegisterMover("bank.main", anchor, {
    label = U.L("MOVER_LABEL_BANK"),
    default = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
                x = 20, y = 20 },
  })
end

-- Second layer under the parking above: the stock bank's own parts, by name,
-- through the shared native-suppression adapter (core/compat.lua) -- the same
-- mechanism the bag frame uses on ContainerFrame1..5. BankFrame itself is
-- deliberately absent from this list; hiding a *child* never runs the parent's
-- OnHide, so the banker session is untouched.
local function SuppressNativeBankParts()
  local names = {
    "BankFrameTitleText", "BankFrameCloseButton", "BankPortraitTexture",
    "BankFrameMoneyFrame", "BankFramePurchaseInfo", "BankFramePurchaseButton",
    "BankFrameSlotCost", "BankSlotsFrame",
  }

  local i
  for i = 1, BANK_SLOTS do
    table.insert(names, "BankFrameItem" .. i)
  end
  for i = 1, MAX_BANK_BAGS do
    table.insert(names, "BankFrameBag" .. i)
  end

  U.SuppressNativeFrame(names)
end

function BK:OnEnable()
  if frame then return end

  Build()
  NeutraliseNativeBank()
  SuppressNativeBankParts()

  U.RegisterEvent("BANKFRAME_OPENED", function()
    NeutraliseNativeBank()
    ShowBank()

    -- Opening the bank with the bag window shut leaves nothing to move items
    -- to or from; UnrealPfUI opens the backpack here for the same reason.
    local open = U.G("OpenBackpack")
    if type(open) == "function" then pcall(open) end
  end)

  U.RegisterEvent("BANKFRAME_CLOSED", function()
    closing = true
    if frame then frame:Hide() end
    closing = false
  end)

  U.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
    bagDirty[BANK_CONTAINER] = true
    layoutDirty = true
  end)

  U.RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function()
    headerDirty = true
    layoutDirty = true
  end)

  U.RegisterEvent("BAG_UPDATE", function(event, bag)
    if not frame:IsShown() then return end
    layoutDirty = true
    bag = tonumber(bag)
    if bag then bagDirty[bag] = true end
  end)

  U.RegisterEvent("ITEM_LOCK_CHANGED", function()
    if not frame:IsShown() then return end
    local bags = BankBags()
    local i
    for i = 1, table.getn(bags) do bagDirty[bags[i]] = true end
  end)

  U.RegisterEvent("BAG_UPDATE_COOLDOWN", function()
    if frame:IsShown() then cooldownDirty = true end
  end)
end
