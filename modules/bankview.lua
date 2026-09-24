-- unrealUI :: modules/bankview.lua
--
-- The saved bank: a per-character snapshot of the bank, taken while a banker
-- session is open and re-taken after every change, and a read-only window that
-- shows it anywhere. The window is opened from the bag window's header
-- (modules/bags.lua), so it exists only while unrealUI's bag window does.
--
-- Read-only by construction, not by guard: the view's slots are plain Buttons
-- with no item template, no click, drag or pickup script, and no container
-- identity. Nothing on them can reach a container API, so nothing can move.
--
-- Evidence:
--
--   * Every read goes through the shared guarded container readers in
--     core/compat.lua (U.ContainerSlotInfo / U.ContainerSlotLink /
--     U.ContainerSlotCount), the same INCONCLUSIVE contract the live bank
--     window runs on (knowledge.json / bags.container_api_contract_unverified).
--   * The main pane reports no stack count on this client
--     (knowledge.json / bank.stack_count_region_not_visible); the quantity
--     saved here is modules/bankcount.lua's derived one, or none.
--   * The store keeps item links, numbers and the icon path exactly as the
--     client returned it. This client's paths use forward slashes; a path
--     with backslashes would be rewritten, because the SavedVariables writer
--     is not trusted with them (knowledge.json /
--     config.savedvariables_backslash_corruption). The first version kept
--     only the suffix after an assumed "Interface\Icons\" prefix, which this
--     client never returns, so every saved item lost its icon (user in-game
--     report, 2026-09-19).
--   * The tooltip is GameTooltip:SetHyperlink (documentation.json,
--     DOCUMENTED_NOT_RUNTIME_VERIFIED). An item the client has not cached may
--     show an incomplete tooltip; nothing else depends on it.
--   * The bank events are the WORKING_SOURCE set modules/bank.lua already
--     relies on (BANKFRAME_OPENED / _CLOSED, PLAYERBANKSLOTS_CHANGED,
--     PLAYERBANKBAGSLOTS_CHANGED, BAG_UPDATE).

local U = UnrealUI
local M = U.media

local BV = U.RegisterModule("bankview")

local DB_NAME         = "UnrealUIBankCacheDB"
local DB_VERSION      = 1
local BANK_CONTAINER  = -1
local BANK_BAG_OFFSET = 4
local MAX_BANK_BAGS   = 6
local ICON_PREFIX     = "Interface\\Icons\\"
local UNKNOWN_ICON    = "INV_Misc_QuestionMark"
local SNAPSHOT_TICK   = 0.25
-- Passes run after each change: the second one picks up a main-pane quantity
-- modules/bankcount.lua only derives on the bank window's next refresh tick.
local SNAPSHOT_PASSES = 2
local BANK_POSITION_ID = "bank.main"
local VIEW_POSITION_ID = "bankview.main"

local COLUMNS       = 10
local SLOT_SIZE     = M.slot.size
local SLOT_GAP      = M.slot.gap
local PADDING       = M.slot.padding
local HEADER_HEIGHT = M.slot.header
local ICON_SIZE     = M.slot.icon
local EMPTY_ROWS    = 2       -- slot rows of height the empty-state note gets

-- One table for the module's state, so this file stays far from the Lua
-- top-level local budget (.claude/rules/unreal-ui.md).
local view = {
  store = nil,
  frame = nil,
  grid = nil,
  slots = {},       -- slots[n] = display button, n = position in the grid
  live = false,     -- a banker session is open
  pending = 0,      -- snapshot passes still owed
  sawItems = false, -- this session has read a non-empty bank at least once
}

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------
local function ValidItem(item)
  return type(item) == "table" and type(item.l) == "string" and item.l ~= ""
end

function view.EnsureStore()
  if view.store then return view.store end

  local db = U.G(DB_NAME)
  if type(db) ~= "table" then
    U.SetG(DB_NAME, { version = DB_VERSION })
    db = U.G(DB_NAME)
    if type(db) ~= "table" then db = { version = DB_VERSION } end
  end

  db.version = DB_VERSION
  if type(db.bags) ~= "table" then db.bags = {} end

  -- A hand-edited or damaged file must not be able to draw garbage.
  local clean = {}
  local i
  for i = 1, table.getn(db.bags) do
    local bag = db.bags[i]
    if type(bag) == "table" and tonumber(bag.id) and tonumber(bag.size) and
       bag.size > 0 and bag.size <= 64 and type(bag.items) == "table" then
      local slot, item
      for slot, item in pairs(bag.items) do
        if type(slot) ~= "number" or slot < 1 or slot > bag.size or
           not ValidItem(item) then
          bag.items[slot] = nil
        end
      end
      table.insert(clean, bag)
    end
  end
  db.bags = clean

  view.store = db
  return db
end

-- ---------------------------------------------------------------------------
-- Snapshot
-- ---------------------------------------------------------------------------
-- Whatever the container reader returned, made safe to persist, onto `item`.
-- This client hands out forward-slash paths ("/Game/Interface/Icons/X_TEX" or
-- "Interface/Icons/X"; see U.IconKey in core/compat.lua), which persist as
-- they are and go back to SetTexture byte for byte. Only a path that really
-- carries backslashes is rewritten, and item.b records that it was.
function view.SaveIcon(item, texture)
  if type(texture) == "number" then
    item.i = texture
  elseif type(texture) == "string" and texture ~= "" then
    if string.find(texture, "\\", 1, true) then
      item.i = string.gsub(texture, "\\", "/")
      item.b = 1
    else
      item.i = texture
    end
  end
end

function view.IconPath(item)
  local key = item.i
  if type(key) == "number" then return key end
  if type(key) ~= "string" or key == "" then return nil end
  if item.b then return (string.gsub(key, "/", "\\")) end
  return key
end

-- Snapshots saved by the first version carry no icon at all: it assumed an
-- "Interface\Icons\" prefix this client does not return and dropped every
-- path. The item's own icon from GetItemInfo (documented ninth return) fills
-- the gap when the client has the item cached; otherwise the slot shows the
-- question mark until the next banker visit re-saves it.
function view.ItemIcon(item)
  local path = view.IconPath(item)
  if path then return path end

  local ok, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, item.l)
  if ok and type(texture) == "string" and texture ~= "" then return texture end
  return ICON_PREFIX .. UNKNOWN_ICON
end

function view.PurchasedBags()
  local ok, n = pcall(GetNumBankSlots)
  n = (ok and tonumber(n)) or 0
  if n < 0 then n = 0 end
  if n > MAX_BANK_BAGS then n = MAX_BANK_BAGS end
  return n
end

function view.ReadSlot(bag, slot)
  local texture, count, _, quality = U.ContainerSlotInfo(bag, slot)
  local link = U.ContainerSlotLink(bag, slot)
  if not link then return nil end

  if bag == BANK_CONTAINER then
    -- nil when bankcount cannot stand behind a number: saved as a single.
    count = type(U.BankSlotStackCount) == "function" and
            U.BankSlotStackCount(bag, slot) or 1
  end

  local infoOk, _, _, linkQuality, _, itemType = pcall(GetItemInfo, link)
  if not tonumber(quality) and infoOk then quality = linkQuality end

  local item = { l = link }
  view.SaveIcon(item, texture)
  count = tonumber(count)
  if count and count > 1 then item.c = count end
  if tonumber(quality) then item.q = tonumber(quality) end
  if infoOk and itemType == "Quest" then item.k = 1 end
  return item
end

function view.Snapshot()
  local bags = {}
  local found = 0
  local ids = { BANK_CONTAINER }
  local i
  for i = 1, view.PurchasedBags() do
    table.insert(ids, i + BANK_BAG_OFFSET)
  end

  for i = 1, table.getn(ids) do
    local bag = ids[i]
    local size = U.ContainerSlotCount(bag)
    if size > 0 then
      local entry = { id = bag, size = size, items = {} }
      local slot
      for slot = 1, size do
        local item = view.ReadSlot(bag, slot)
        if item then
          entry.items[slot] = item
          found = found + 1
        end
      end
      table.insert(bags, entry)
    end
  end

  -- BANKFRAME_OPENED can arrive before the client has the bank contents
  -- (modules/bank.lua retries its layout for the same reason). An empty read
  -- is only trusted once this session has seen the bank filled in, i.e. when
  -- the player really emptied it while watching.
  if found == 0 and not view.sawItems then return false end
  if found > 0 then view.sawItems = true end

  local db = view.EnsureStore()
  db.bags = bags
  local ok, now = pcall(time)
  if ok and tonumber(now) then db.savedAt = now end
  return true
end

function view.Tick()
  if not view.live then
    U.UnregisterUpdate("bankview.snapshot")
    return
  end
  if U.CursorHasItem and U.CursorHasItem() then return end
  if view.pending <= 0 then return end

  if view.Snapshot() then view.pending = view.pending - 1 end
end

function view.MarkChanged()
  if view.live then view.pending = SNAPSHOT_PASSES end
end

-- ---------------------------------------------------------------------------
-- Display slots
--
-- A plain Button carrying the region names U.StyleItemSlot looks up
-- (<name>IconTexture, <name>Count), so the saved bank is drawn by the same
-- shared slot styling as the live one and cannot drift into its own look.
-- ---------------------------------------------------------------------------
-- The bag-family design (modules/bagdesign.lua) owns this window's chrome
-- and spacing whenever it is on.
function view.Modern()
  return U.ModernWowBagFamilyActive()
end

function view.Header()
  return U.ModernWowBagMetric("header", HEADER_HEIGHT)
end

function view.SlotGap()
  return U.ModernWowBagMetric("slotGap", SLOT_GAP)
end

function view.SidePad()
  return U.ModernWowBagMetric("sidePad", PADDING)
end

function view.BottomPad()
  return U.ModernWowBagMetric("bottomPad", PADDING)
end

function view.BorderColor(item)
  if not item then return M.slotBorder.empty end
  if item.k then return M.slotBorder.quest end
  if item.q and item.q > M.qualityLimit then
    return U.ItemQualityColor(item.q) or M.slotBorder.plain
  end
  return M.slotBorder.plain
end

function view.ItemString(link)
  local _, _, payload = string.find(link or "", "(item:[%-%d:]+)")
  return payload
end

function view.ShowTooltip(button)
  local item = button.uuiItem
  if not item then return end

  local tip = U.G("GameTooltip")
  local payload = view.ItemString(item.l)
  if not tip or not payload then return end

  pcall(tip.SetOwner, tip, button, "ANCHOR_RIGHT")
  pcall(tip.SetHyperlink, tip, payload)
  if type(U.ColorTooltipItemName) == "function" then
    U.ColorTooltipItemName(nil, item.q)
  end
  pcall(tip.Show, tip)
  U.ShowItemCompare(item.l)
end

function view.HideTooltip(button)
  U.HideItemCompare()
  if type(U.ClearTooltipItemName) == "function" then U.ClearTooltipItemName() end
  local tip = U.G("GameTooltip")
  if not tip then return end
  -- IsOwned is documented for GameTooltip here; GetOwner is not.
  local ok, owned = pcall(tip.IsOwned, tip, button)
  if not ok or owned then pcall(tip.Hide, tip) end
end

function view.EnsureSlot(n)
  if view.slots[n] then return view.slots[n] end

  local name = "UnrealUIBankViewSlot" .. n
  local button = CreateFrame("Button", name, view.grid)
  button:SetWidth(SLOT_SIZE)
  button:SetHeight(SLOT_SIZE)

  local icon = button:CreateTexture(name .. "IconTexture", "BORDER")
  icon:SetAllPoints(button)
  local ok, count = pcall(button.CreateFontString, button, name .. "Count",
                          "ARTWORK", "NumberFontNormal")
  if not ok or not count then
    pcall(button.CreateFontString, button, name .. "Count", "ARTWORK")
  end

  -- Under Modern WoW the hover matches the player bag's slots: the item
  -- template's highlight region, which U.StyleItemSlot tints to the shared
  -- grey wash. A plain Button has none, so it is given one first.
  if view.Modern() then
    pcall(button.SetHighlightTexture, button,
          "Interface\\Buttons\\ButtonHilight-Square")
  end
  U.StyleItemSlot(button, name)
  if view.Modern() then U.ModernWowBagSlot(button, SLOT_SIZE) end
  button.uuiIcon = icon

  -- Hover is the one interactive state a display slot has. Outside Modern WoW
  -- it is the same accent edge the bank's header bag buttons use, restored to
  -- the rarity edge on leave.
  button:SetScript("OnEnter", function()
    if not view.Modern() then
      U.SetBorderColor(button, M.Unpack(M.color.moverEdge))
    end
    view.ShowTooltip(button)
  end)
  button:SetScript("OnLeave", function()
    local item = button.uuiItem
    U.SetItemSlotRarity(button, view.BorderColor(item), item and item.q)
    view.HideTooltip(button)
  end)

  view.slots[n] = button
  return button
end

function view.FillSlot(button, item)
  button.uuiItem = item

  local texture
  if item then texture = view.ItemIcon(item) end
  if texture then
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    pcall(button.uuiIcon.Show, button.uuiIcon)
  else
    pcall(button.uuiIcon.Hide, button.uuiIcon)
  end

  local label = button.uuiCount
  if label then
    local n = item and item.c
    if n and n > 1 then
      pcall(label.SetText, label, tostring(n))
      pcall(label.SetAlpha, label, 1)
      pcall(label.Show, label)
    else
      pcall(label.SetText, label, "")
      pcall(label.Hide, label)
    end
  end

  U.SetItemSlotRarity(button, view.BorderColor(item), item and item.q)
  if button.uuiClassicItemSlot then
    local i
    for i = 1, table.getn(button.uuiEdges or {}) do
      pcall(button.uuiEdges[i].Show, button.uuiEdges[i])
    end
  end
  if view.search then view.search.Paint(button, item and item.l) end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function view.Layout()
  local db = view.EnsureStore()
  local n, x, y = 0, 0, 0
  local gap = view.SlotGap()
  local i

  for i = 1, table.getn(db.bags) do
    local bag = db.bags[i]
    local slot
    for slot = 1, bag.size do
      n = n + 1
      local button = view.EnsureSlot(n)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", view.grid, "TOPLEFT",
                      x * (SLOT_SIZE + gap), -(y * (SLOT_SIZE + gap)))
      view.FillSlot(button, bag.items[slot])
      button:Show()

      if x >= COLUMNS - 1 then
        x, y = 0, y + 1
      else
        x = x + 1
      end
    end
  end

  for i = n + 1, table.getn(view.slots) do
    view.slots[i]:Hide()
    view.slots[i].uuiItem = nil
  end

  if x > 0 then y = y + 1 end

  -- Never visited a banker on this character: the window still opens, with
  -- the reason it is empty written where the slots would be.
  if view.grid.empty then
    if n == 0 then view.grid.empty:Show() else view.grid.empty:Hide() end
  end
  if n == 0 then y = EMPTY_ROWS end

  local frame = view.frame
  frame:SetWidth(COLUMNS * (SLOT_SIZE + gap) - gap + view.SidePad() * 2)
  frame:SetHeight(view.Header() + y * (SLOT_SIZE + gap) - gap +
                  view.BottomPad())
  if view.Modern() then U.ModernWowBagHousing(frame) end
end

-- Opens where the player last dragged it. Until it has been dragged once, it
-- opens where the live bank opens: the bank's own anchor, on the same point
-- its saved placement uses, so it grows in the same direction the live one
-- does.
function view.Place()
  local frame = view.frame
  local own = U.GetPosition(VIEW_POSITION_ID)
  if own and U.ApplyFramePoint(frame, own) then return true end

  local bankAnchor = U.G("UnrealUIBankAnchor")
  local saved = U.GetPosition and U.GetPosition(BANK_POSITION_ID)
  local point = (type(saved) == "table" and type(saved.point) == "string" and
                 saved.point) or "BOTTOMLEFT"

  frame:ClearAllPoints()
  if not bankAnchor or
     not pcall(frame.SetPoint, frame, point, bankAnchor, point, 0, 0) then
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Direct drag
--
-- The header strip moves the window, the same arrangement as modules/bank.lua:
-- the throwaway StartMoving/StopMovingOrSizing pair before the real StartMoving
-- (knowledge.json / frames.movable_drag_requires_button_handle), an
-- edge-derived placement saved on release, and the shared screen guard.
-- ---------------------------------------------------------------------------
function view.StartDrag()
  local frame = view.frame
  if not pcall(frame.SetMovable, frame, true) then
    U.Error("bankview: SetMovable failed; the saved bank cannot be moved")
    return
  end

  if pcall(frame.StartMoving, frame) then
    pcall(frame.StopMovingOrSizing, frame)
  end
  if pcall(frame.StartMoving, frame) then
    U.HoldScreenGuard(frame, true)
  end
end

function view.StopDrag()
  local frame = view.frame
  pcall(frame.StopMovingOrSizing, frame)
  U.HoldScreenGuard(frame, false)

  local p = U.GetFramePlacement(frame)
  if p then
    U.SavePosition(VIEW_POSITION_ID, p.point, p.relativePoint, p.x, p.y)
  end
  U.CheckOnScreen(frame)
end

-- Spans the header up to the close glyph. The labels under it take no mouse
-- input, so the strip swallows no click; the close button stays clear of it.
function view.BuildDragHandle()
  local frame = view.frame
  local handle = CreateFrame("Button", "UnrealUIBankViewDrag", frame)
  handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -4, 0)
  handle:SetHeight(view.Header())
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)

  handle:SetScript("OnDragStart", view.StartDrag)
  handle:SetScript("OnDragStop", view.StopDrag)

  frame.dragHandle = handle
end

-- The bag-family header for a window with no controls: the
-- title takes the icon row's place and the read-only note sits right-aligned
-- against the close button. Both are pinned to fixed points rather than to
-- each other, since a label's own width is not set here.
function view.StyleHeader()
  if not view.Modern() then return end
  local frame = view.frame
  local token = M.modernWow.bags

  U.ModernWowBagHousing(frame)
  U.ModernWowBagPortrait(frame)
  U.ModernWowBagClose(frame, "UnrealUIBankViewClose")

  local rowMiddle = -(token.actions.top + token.actions.height / 2)
  if frame.title then frame.title:Hide() end
  local title = U.ModernWowBagTitle(frame, U.L("BANK_VIEW_TITLE"))
  if title then
    title:ClearAllPoints()
    title:SetPoint("LEFT", frame, "TOPLEFT", token.actions.left, rowMiddle)
    pcall(title.SetJustifyH, title, "LEFT")
  end

  if frame.note then
    frame.note:ClearAllPoints()
    frame.note:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
    pcall(frame.note.SetJustifyH, frame.note, "RIGHT")
  end

  U.ModernWowBagSeparator(frame)
end

function view.Build()
  local frame = U.CreatePanel(UIParent, { name = "UnrealUIBankViewFrame" })
  -- Below every interface window, like the live bank (user request,
  -- 2026-09-21). Previously HIGH so the item tooltip could draw over it; LOW
  -- keeps that and additionally puts every window on top. A world object's
  -- tooltip can draw over this window, as before (user request, 2026-09-19).
  U.LowerWindowBelowInterface(frame, 150)
  pcall(frame.EnableMouse, frame, true)
  frame:Hide()
  view.frame = frame

  local special = U.G("UISpecialFrames")
  if type(special) == "table" then
    table.insert(special, "UnrealUIBankViewFrame")
  end

  frame.close = U.CreateButton(frame, {
    name = "UnrealUIBankViewClose",
    text = "X",
    width = ICON_SIZE,
    height = ICON_SIZE,
    size = M.fontSize.small,
    onClick = function() frame:Hide() end,
  })
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)

  frame.title = U.CreateLabel(frame, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
  })
  if frame.title then
    frame.title:SetText(U.L("BANK_VIEW_TITLE"))
    frame.title:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
  end

  frame.note = U.CreateLabel(frame, {
    size = M.fontSize.small,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if frame.note then
    frame.note:SetText(U.L("BANK_VIEW_READONLY"))
    frame.note:SetPoint("LEFT", frame, "TOPLEFT", PADDING,
                        -math.floor(HEADER_HEIGHT / 2))
  end

  view.StyleHeader()

  view.grid = CreateFrame("Frame", "UnrealUIBankViewGrid", frame)
  view.grid:SetPoint("TOPLEFT", frame, "TOPLEFT", view.SidePad(),
                     -view.Header())
  view.grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -view.SidePad(),
                     view.BottomPad())

  view.grid.empty = U.CreateLabel(view.grid, {
    size = M.fontSize.normal,
    color = M.color.textDim,
    inherits = "GameFontNormal",
    justify = "CENTER",
    width = COLUMNS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP - 16,
  })
  if view.grid.empty then
    view.grid.empty:SetText(U.L("BANK_VIEW_EMPTY"))
    view.grid.empty:SetPoint("CENTER", view.grid, "CENTER", 0, 0)
    view.grid.empty:Hide()
  end

  frame:SetScript("OnHide", function()
    U.HideItemCompare()
    if view.search then view.search.Stop() end
  end)

  view.BuildDragHandle()

  -- Header search (user request, 2026-09-24): the bag's field
  -- (modules/bagdesign.lua), fitted between the title and the read-only note.
  -- Nil unless the bag design is on. It sits above the drag strip, which keeps
  -- the rest of the header.
  if frame.uuiModernWowTitle then
    view.search = U.ModernWowBagSearch({
      window = frame,
      name = "UnrealUIBankViewSearch",
      id = "bankview.search",
      after = frame.uuiModernWowTitle,
      before = frame.note,
      each = function(paint)
        local i
        for i = 1, table.getn(view.slots) do
          local item = view.slots[i].uuiItem
          paint(view.slots[i], item and item.l)
        end
      end,
    })
  end
  pcall(frame.SetMovable, frame, true)
  U.GuardOnScreen(frame, { id = VIEW_POSITION_ID })
  -- /uui reset clears the stored placement; an open window goes back to the
  -- bank's position straight away instead of on its next open.
  U.OnPositionReset(function()
    if frame:IsShown() then view.Place() end
  end)
end

-- The bag window's header button. A live banker session already shows the
-- real bank, so the saved one never opens on top of it.
function U.ToggleBankView()
  if not view.frame then return end

  if view.frame:IsShown() then
    view.frame:Hide()
    return
  end
  if view.live then return end

  view.Layout()
  view.Place()
  view.frame:Show()
  if view.search then view.search.Start() end
end

function BV:OnEnable()
  if view.frame then return end

  view.EnsureStore()
  view.Build()

  U.RegisterEvent("BANKFRAME_OPENED", function()
    view.live = true
    view.sawItems = false
    view.pending = SNAPSHOT_PASSES
    if view.frame then view.frame:Hide() end
    U.RegisterUpdate("bankview.snapshot", SNAPSHOT_TICK, view.Tick)
  end)

  U.RegisterEvent("BANKFRAME_CLOSED", function()
    view.live = false
    view.pending = 0
    U.UnregisterUpdate("bankview.snapshot")
  end)

  U.RegisterEvent("PLAYERBANKSLOTS_CHANGED", view.MarkChanged)
  U.RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", view.MarkChanged)
  -- Any bag, not only 5..10: a main-pane quantity is derived from what the
  -- carried bags lost, so a deposit shows up here as a carried-bag update.
  U.RegisterEvent("BAG_UPDATE", view.MarkChanged)
end
