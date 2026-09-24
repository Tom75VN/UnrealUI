-- unrealUI :: modules/bagcategoryview.lua
--
-- The category view shared by the combined bag (modules/bags.lua) and the live
-- bank (modules/bank.lua): stacked category boxes over the very same slot
-- buttons the window's flat grid uses. Nothing is created, destroyed or
-- re-parented when the view is switched, the buttons are only re-anchored, so
-- click, drag, tooltip, price, comparison and cooldown behavior are identical
-- in both views and switching costs one relayout rather than a rebuild.
--
-- It was the bag window's own code until the bank was asked to draw the same
-- view (user request, 2026-09-24). It moved here rather than being copied, so
-- the two windows cannot drift into two category views. A window hands in a
-- host table (U.CreateBagCategoryView) describing its containers and slot
-- buttons; this file decides where a category goes on screen, and
-- core/itemcategory.lua decides what an item *is*.
--
-- The empty-slot proxy and its drop routing live here too: the category view
-- draws every free slot as one proxy button, and a drop on it has to find a
-- real free slot among the host's containers. The drop's source record is one
-- for the whole addon, because there is one cursor.

local U = UnrealUI
local M = U.media

local CV = {}

-- ---------------------------------------------------------------------------
-- Empty-slot drop routing
--
-- One cursor route serves both ways a player can put an item down: release a
-- real drag over the proxy, or click the proxy while already carrying one.
-- The source record is only compatibility context. The physical destination
-- always comes from the view's current category-layout cache.
-- ---------------------------------------------------------------------------
CV.drop = {
  source = nil,
  subclasses = {},
  containerCategories = {
    [2] = { reagent = true },
    [3] = { herb = true },
    [4] = { enchanting = true },
    [5] = { engineering = true },
    [6] = { gem = true },
    [7] = { ore = true, gem = true },
    [8] = { leather = true },
  },
}

function CV.drop.Trace(message)
  U.Debug("bags empty-slot: " .. tostring(message))
end

function CV.drop.SlotSource(bag, slot)
  local link = U.ContainerSlotLink(bag, slot)
  if not link then return nil end

  return {
    bagNum = bag,
    slotNum = slot,
    link = link,
    category = U.ItemCategoryForSlot(bag, slot),
  }
end

-- The source record for an item a window's slot is about to put on the cursor
-- (nil for an empty slot), and the setter that keeps it. Slot click and drag
-- hooks call these; the proxy reads the record when the item comes down.
function U.BagCategoryDropSource(bag, slot)
  return CV.drop.SlotSource(bag, slot)
end

function U.SetBagCategoryDropSource(source)
  CV.drop.source = source
end

function CV.drop.AuctionSubclasses(classIndex)
  if CV.drop.subclasses[classIndex] then
    return CV.drop.subclasses[classIndex]
  end

  local list = {}
  local fn = U.G("GetAuctionItemSubClasses")
  if type(fn) ~= "function" then return list end

  local packed = { pcall(fn, classIndex) }
  if not packed[1] then return list end

  local i
  for i = 2, table.getn(packed) do
    if type(packed[i]) == "string" and packed[i] ~= "" then
      table.insert(list, packed[i])
    end
  end
  if table.getn(list) > 0 then CV.drop.subclasses[classIndex] = list end
  return list
end

function CV.drop.SourceSubtype()
  local source = CV.drop.source
  if not source or not source.link then return nil end

  local ok, _, _, _, _, _, subtype = pcall(GetItemInfo, source.link)
  if ok and type(subtype) == "string" and subtype ~= "" then return subtype end
  return nil
end

function CV.drop.Compatible(entry)
  local source = CV.drop.source

  -- An equipped bag must never be offered one of its own cached interior
  -- slots. Those entries can remain in the layout briefly while the client is
  -- processing the bag pickup.
  if source and source.containerBag and source.containerBag == entry.bagNum then
    return false
  end

  if not entry.special then return true end
  if not source then return false end

  local label = entry.bagType
  local containersList = CV.drop.AuctionSubclasses(3)
  local i
  for i = 2, table.getn(containersList) do
    if label == containersList[i] then
      local accepted = CV.drop.containerCategories[i]
      return accepted and accepted[source.category] and true or false
    end
  end

  -- Projectile and quiver subclasses use the same fixed positional pairing:
  -- arrows -> quiver, bullets -> ammo pouch. Comparing the localized subclass
  -- strings keeps this rule language-neutral.
  local quivers = CV.drop.AuctionSubclasses(7)
  for i = 1, table.getn(quivers) do
    if label == quivers[i] then
      local projectiles = CV.drop.AuctionSubclasses(6)
      return source.category == "ammo" and
             CV.drop.SourceSubtype() == projectiles[i]
    end
  end

  -- A custom specialty bag not represented by the client's auction subclass
  -- list is accepted only for a category already observed inside that same
  -- bag. An empty unknown specialty bag therefore fails closed.
  return entry.acceptedCategories and
         entry.acceptedCategories[source.category] and true or false
end

function CV.drop.PlaceCursorItemIntoSlotTarget(view, target)
  local hasItem = U.CursorHasItem()
  CV.drop.Trace("CursorHasItem inside target handler=" .. tostring(hasItem))
  CV.drop.Trace("target.isEmptySlotStack=" ..
                tostring(target and target.isEmptySlotStack))
  if not hasItem or not target then return false end

  if not target.isEmptySlotStack then
    if not target.bagNum or not target.slotNum then return false end
    CV.drop.Trace("selected destination=" .. target.bagNum .. "/" ..
                  target.slotNum)
    CV.drop.Trace("before PickupContainerItem")
    U.PickupContainerSlot(target.bagNum, target.slotNum)
    hasItem = U.CursorHasItem()
    CV.drop.Trace("CursorHasItem after PickupContainerItem=" ..
                  tostring(hasItem))
    return not hasItem
  end

  local emptySlots = view.emptySlots
  CV.drop.Trace("number of cached candidate slots=" ..
                tostring(table.getn(emptySlots)))

  local i
  for i = 1, table.getn(emptySlots) do
    local entry = emptySlots[i]
    local empty = entry.emptySlot == 1 and
                  not U.ContainerSlotHasItem(entry.bagNum, entry.slotNum)
    local compatible = empty and not entry.preventEmptySlotStack and
                       CV.drop.Compatible(entry)
    CV.drop.Trace("candidate " .. entry.bagNum .. "/" .. entry.slotNum ..
                  " empty=" .. tostring(empty) ..
                  " compatibility=" .. tostring(compatible))

    if compatible then
      CV.drop.Trace("selected destination=" .. entry.bagNum .. "/" ..
                    entry.slotNum)
      CV.drop.Trace("before PickupContainerItem")
      U.PickupContainerSlot(entry.bagNum, entry.slotNum)
      hasItem = U.CursorHasItem()
      CV.drop.Trace("CursorHasItem after PickupContainerItem=" ..
                    tostring(hasItem))
      if not hasItem then
        CV.drop.source = nil
        if type(view.host.onDropped) == "function" then view.host.onDropped() end
        return true
      end

      -- Do not retry a destination the client just refused during this cache
      -- lifetime. A BAG_UPDATE rebuilds the physical empty-slot entries.
      entry.preventEmptySlotStack = 1
    end
  end

  -- A refused proxy drop behaves like a refused native slot drop: the item
  -- remains on the cursor, so the player can choose another destination.
  U.Print(U.L(view.host.fullText or "BAGS_INVENTORY_FULL"))
  return false
end

-- The one button that stands for every free slot in the view.
function CV.BuildEmptyProxy(view)
  if view.emptyProxy then return view.emptyProxy end
  local grid = view.host.grid
  local root = CreateFrame("Frame", nil, grid)
  root:SetID(0)
  root:SetAllPoints(grid)

  local levelOk, level = pcall(grid.GetFrameLevel, grid)
  if levelOk and tonumber(level) then
    pcall(root.SetFrameLevel, root, level + 5)
  end

  local button = U.CreateItemSlot(root, view.host.name .. "EmptyProxy", 0, 0)
  if not button then return nil end

  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")
  pcall(button.RegisterForDrag, button, "LeftButton")
  button.isEmptySlotStack = true
  button:SetScript("OnClick", function(a, b)
    CV.drop.Trace("TARGET OnClick fired")
    local mouseButton = U.MouseButton(a, b)
    if not mouseButton or mouseButton == "LeftButton" then
      CV.drop.PlaceCursorItemIntoSlotTarget(view, button)
    end
  end)
  button:SetScript("OnDragStart", function()
    CV.drop.Trace("SOURCE OnDragStart fired (empty proxy; no item)")
  end)
  button:SetScript("OnEnter", function() end)
  button:SetScript("OnLeave", function() end)
  button:SetScript("OnReceiveDrag", function()
    CV.drop.Trace("TARGET OnReceiveDrag fired")
    CV.drop.PlaceCursorItemIntoSlotTarget(view, button)
  end)

  button:Hide()
  view.emptyProxy = button
  return button
end

-- ---------------------------------------------------------------------------
-- Metrics
-- ---------------------------------------------------------------------------

-- Slot inset inside a category box. Modern WoW's thin-border rim is wider
-- than the flat outline, so the slots sit further in to clear it.
function CV.Inset()
  return U.ModernWowBagMetric("sectionInset", M.bagCategory.inset)
end

-- Height of a category box's bottom border, from the box's bottom edge to the
-- top of its line: what text resting on that border is offset by. The flat
-- outline is one unit; the Modern WoW rim's line starts at its measured fill
-- inset (a shadow runs below it) and is taken as one unit thick.
function CV.BorderLine()
  if U.ModernWowBagFamilyActive() and
     type(U.ModernWowThinBorderInsets) == "function" then
    local section = M.modernWow and M.modernWow.bags and M.modernWow.bags.section
    local _, _, _, bottom = U.ModernWowThinBorderInsets(section and section.edge)
    return math.ceil(tonumber(bottom) or 0) + 1
  end
  return 1
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------
function CV.HideSection(section)
  if not section then return end
  if section.box then section.box:Hide() end
  if section.toggle then section.toggle:Hide() end
  if section.title then section.title:Hide() end
  if section.count then section.count:Hide() end
end

function CV.HideSections(view)
  local key, section
  for key, section in pairs(view.sections) do CV.HideSection(section) end
end

function CV.ToggleSection(view, key, collapsed)
  -- Only collapsed categories are stored, so folding one back open removes its
  -- entry rather than leaving a false behind in SavedVariables.
  view.host.collapsed()[key] = collapsed or nil
  CV.Layout(view)
end

-- A section is a heading row plus a box of slots. The heading is deliberately
-- *not* part of the box: a collapsed category keeps its title and its +/-
-- control on screen while the box goes away, and a region belonging to a hidden
-- frame cannot stay visible. All three are children of the grid instead.
function CV.EnsureSection(view, key, contentWidth, label)
  local section = view.sections[key]
  if section then return section end

  local host = view.host
  local grid = host.grid
  local metric = M.bagCategory
  local inset = CV.Inset()
  section = {}

  section.box = U.CreatePanel(grid, {
    name = host.name .. "Category_" .. key,
    width = contentWidth + inset * 2,
    height = host.slotSize + inset * 2,
  })
  if type(host.styleBox) == "function" then host.styleBox(section.box) end
  if U.ModernWowBagFamilyActive() then U.ModernWowBagSection(section.box) end
  -- Purely a backdrop for the slots anchored over it; it must not eat the
  -- clicks and drags those slots depend on.
  pcall(section.box.EnableMouse, section.box, false)

  -- The empty-slot category is one proxy button: it keeps its box as the
  -- layout anchor but draws no box chrome around it (user request,
  -- 2026-09-24). The proxy is not a child of the box, so it stays visible.
  if key == "empty" then pcall(section.box.SetAlpha, section.box, 0) end

  -- The shared collapse control (U.CreateCollapseButton), not a local variant:
  -- same sharp box, same accent hover, same owned +/- glyph as every other
  -- collapsible header in the addon.
  section.toggle = U.CreateCollapseButton(grid, {
    size = metric.toggle,
    collapsed = host.collapsed()[key],
    onClick = function(collapsed) CV.ToggleSection(view, key, collapsed) end,
  })
  if U.ModernWowBagFamilyActive() and
     type(U.ModernWowPlusMinusFace) == "function" then
    -- Category headers use the Modern WoW tree control's literal pair: plus
    -- when folded, minus when open. The shared collapse button still owns the
    -- click handling and persisted state.
    U.ModernWowPlusMinusFace(section.toggle)
  end

  section.title = U.CreateLabel(grid, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if section.title then section.title:SetText(label or U.ItemCategoryLabel(key)) end

  -- A specialty bag's used/total readout. It sits over the box's bottom
  -- border, so it is white with the shared strong shadow to stay legible on
  -- the rim (user request, 2026-09-24). A region of the grid would draw under
  -- the box, whose frame is above the grid, so it gets its own frame above
  -- the box instead. Not a child of the box: a folded bag hides the box but
  -- keeps the readout on its heading line.
  section.countHolder = CreateFrame("Frame", nil, grid)
  section.countHolder:SetAllPoints(grid)
  pcall(section.countHolder.EnableMouse, section.countHolder, false)
  local levelOk, level = pcall(section.box.GetFrameLevel, section.box)
  if levelOk and tonumber(level) then
    pcall(section.countHolder.SetFrameLevel, section.countHolder, level + 2)
  end
  section.count = U.CreateLabel(section.countHolder, {
    size = M.fontSize.tiny,
    color = { 1, 1, 1, 1 },
    shadowColor = M.color.shadowStrong,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
  })
  if section.count then section.count:Hide() end

  view.sections[key] = section
  return section
end

-- One pass over every slot of the host's containers, bucketed by category.
-- Empty slots stay as physical entries so the proxy can address a real drop
-- target; the host's readout reports their total count.
function CV.Collect(view)
  local host = view.host
  local bags = host.bags()
  local buckets = {}
  local special = {}
  local empty = {}
  local used, total = 0, 0
  local i

  -- The favourite section overrides whatever the item would otherwise be
  -- filed under, so a marked item is in one place and only one place. Resolved
  -- once per pass rather than per slot; nil when modules/bagfavorites.lua is
  -- not loaded or the host does not carry the mark, and the view then behaves
  -- exactly as it did before.
  local favoriteKey = nil
  if host.favorites and type(U.ItemCategoryFavorite) == "function" and
     type(U.IsBagSlotFavorite) == "function" then
    favoriteKey = U.ItemCategoryFavorite()
  end

  for i = 1, table.getn(bags) do
    local bag = bags[i]
    local n = tonumber(host.slotCount(bag)) or 0

    local label = type(U.BagSpecialtyLabel) == "function" and
                  U.BagSpecialtyLabel(bag) or nil
    local specialKey = label and ("specialbag_" .. bag) or nil
    if specialKey then
      buckets[specialKey] = {
        entries = {}, special = true, label = label, used = 0, total = n,
        acceptedCategories = {},
      }
      table.insert(special, specialKey)
    end

    local slot
    for slot = 1, n do
      total = total + 1

      local key = U.ItemCategoryForSlot(bag, slot)
      if key == "empty" then
        table.insert(empty, {
          id = 0, emptySlot = 1, bagNum = bag, slotNum = slot,
          special = specialKey and true or false,
          bagType = label,
          acceptedCategories = specialKey and
                               buckets[specialKey].acceptedCategories or nil,
          preventEmptySlotStack = false,
        })
      end
      if specialKey and key ~= "empty" then
        buckets[specialKey].used = buckets[specialKey].used + 1
        buckets[specialKey].acceptedCategories[key] = true
      end
      -- After the classification, not instead of it: an empty slot is still
      -- empty, and the mark is only ever asked about a slot that holds
      -- something.
      local favorite = key ~= "empty" and favoriteKey and
                       U.IsBagSlotFavorite(bag, slot)
      if favorite then
        key = favoriteKey
      end
      if key ~= "empty" then
        used = used + 1
        if specialKey and not favorite then
          key = specialKey
        end
        if not buckets[key] then buckets[key] = { entries = {} } end

        -- The grouped view is the visual form of the physical sorter: category
        -- headings own the first level, and this shared key groups functional
        -- kinds (healing potions, mana potions, etc.) plus identical items
        -- inside each heading. Coordinates make equal stacks deterministic.
        local link = U.ContainerSlotLink(bag, slot)
        local sort = U.ItemSortKey(link) ..
          string.format("|%02d|%04d", bag + 2, slot)
        table.insert(buckets[key].entries,
                     { bag = bag, slot = slot, sort = sort })
      end
    end
  end

  -- Automatic while category view is enabled: only the slot buttons move on
  -- screen. The player's actual container slots are left untouched.
  local _, bucket
  for _, bucket in pairs(buckets) do
    table.sort(bucket.entries, function(a, b) return a.sort < b.sort end)
  end
  table.sort(empty, function(a, b)
    if a.special ~= b.special then return not a.special end
    if a.bagNum ~= b.bagNum then return a.bagNum < b.bagNum end
    return a.slotNum < b.slotNum
  end)

  return buckets, special, empty, used, total
end

-- ---------------------------------------------------------------------------
-- Category row planner: numbers in, numbers out, no frames touched.
-- ---------------------------------------------------------------------------
-- Bagshui's layout idea (Components/Inventory.Layout.lua, UpdateWindow): a row
-- holds several categories side by side, each only as wide as its content,
-- and when they no longer fit across the window the whole row grows one slot
-- row taller so every category on it can be narrower. All categories on a row
-- share that height; each keeps its own width.
--
-- Deliberate departures from Bagshui:
-- - For a given height the width is solved directly, ceil(shown / height),
--   instead of shaving one column per pass. That is the narrowest width that
--   still holds the items, which Bagshui's lockstep decrement can overshoot
--   (7 items over 2 rows: 4 wide here, 5 there).
-- - The budget is pixels, not slots: each box's inset and the gutter between
--   boxes are paid for, so a row is never allowed to widen the window.
-- - A box is never narrower than its heading, measured from the drawn title,
--   so a one-slot category cannot push its name over its neighbour's.
-- - UnrealUI has no configured rows, only an order, so rows are formed
--   greedily in that order: the next category joins the current row when a
--   fit exists and the shared row is no taller than starting a new row would
--   be. Order is never changed and nothing is bin-packed.
--
-- A spec is { shown = items drawn (0 when collapsed), minSlots = heading
-- width in slots, headingHeight = pixels }. `m` carries the pixel metrics.
CV.plan = {}

-- Pixel width of a box `slots` slots wide, insets included.
function CV.plan.BoxWidth(slots, m)
  return m.inset * 2 + slots * m.pitch - m.gap
end

-- Pixel height of a box `rows` slot rows tall; 0 means no box at all.
function CV.plan.BodyHeight(rows, m)
  if rows <= 0 then return 0 end
  return m.inset * 2 + rows * m.pitch - m.gap
end

-- Narrowest whole number of slots whose box is at least `pixels` wide.
function CV.plan.SlotsForWidth(pixels, m)
  local slots = math.ceil((pixels - m.inset * 2 + m.gap) / m.pitch)
  return math.max(1, math.min(m.columns, slots))
end

-- Lays one row out at the lowest shared height that fits the budget. Returns
-- { widths, rows, width, heading, height }, or nil when the categories do not
-- fit side by side at any height (never the case for a single category).
function CV.plan.Fit(specs, m)
  local count = table.getn(specs)
  local total, tallest, heading = 0, 0, 0
  local i
  for i = 1, count do
    total = total + specs[i].shown
    tallest = math.max(tallest, specs[i].shown)
    heading = math.max(heading, specs[i].headingHeight)
  end

  -- No lower height can fit: every slot shown on the row has to fit in
  -- m.columns per slot row. At `tallest` every category is one slot wide, so
  -- if that does not fit nothing taller will either.
  local first = math.max(1, math.ceil(total / m.columns))
  local h
  for h = first, math.max(first, tallest) do
    local widths = {}
    local width = (count - 1) * m.columnGap
    for i = 1, count do
      local w = specs[i].minSlots
      if specs[i].shown > 0 then
        w = math.max(w, math.ceil(specs[i].shown / h))
      end
      widths[i] = w
      width = width + CV.plan.BoxWidth(w, m)
    end
    if width <= m.budget then
      local rows = (total > 0) and h or 0
      return {
        widths = widths, rows = rows, width = width, heading = heading,
        height = heading + CV.plan.BodyHeight(rows, m),
      }
    end
  end
  return nil
end

-- Splits the ordered specs into rows: a list of { specs, fit }.
--
-- `pinned`, when given, opens the first row (the empty-slot category, kept
-- top left). The first category always joins it when they fit, so it never
-- takes a row of its own above the rest.
function CV.plan.Rows(specs, m, pinned)
  local rows = {}
  local current
  local i, j
  if pinned then
    current = { specs = { pinned }, fit = CV.plan.Fit({ pinned }, m),
                pinned = true }
    table.insert(rows, current)
  end
  for i = 1, table.getn(specs) do
    local spec = specs[i]
    local alone = CV.plan.Fit({ spec }, m)
    local joined = false

    if current then
      local count = table.getn(current.specs)
      local candidate = {}
      for j = 1, count do
        candidate[j] = current.specs[j]
      end
      table.insert(candidate, spec)
      local shared = CV.plan.Fit(candidate, m)
      if shared and ((current.pinned and count == 1) or shared.height <=
         current.fit.height + m.sectionGap + alone.height) then
        current.specs, current.fit = candidate, shared
        joined = true
      end
    end

    if not joined then
      current = { specs = { spec }, fit = alone }
      table.insert(rows, current)
    end
  end
  return rows
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
-- Draws the view into host.grid. Returns the content width the host's window
-- has to hold, the content height, and how many slots the host's containers
-- report (so a host can tell an empty container set from one whose contents
-- have not reached the client yet). host.onLayout(width, height) runs after a
-- pass, including one started by a section's collapse control.
function CV.Layout(view)
  local host = view.host
  local grid = host.grid
  local metric = M.bagCategory
  local slotSize = host.slotSize
  local slotGap = host.slotGap()
  local inset = CV.Inset()
  local pitch = slotSize + slotGap
  local fullContentWidth = host.columns * pitch - slotGap
  local metrics = {
    columns = host.columns, pitch = pitch, gap = slotGap, inset = inset,
    columnGap = metric.columnGap, sectionGap = metric.gap,
    budget = fullContentWidth + inset * 2,
  }
  local collapsed = host.collapsed()
  local buckets, special, empty, usedSlots, totalSlots = CV.Collect(view)
  local order = U.ItemCategoryOrder()
  local live = {}    -- every (bag, slot) this pass actually placed
  local drawn = {}   -- every category this pass actually drew
  local visible = {} -- ordered categories with at least one item
  local y = 0
  local i

  if type(host.onSlotCount) == "function" then
    host.onSlotCount(usedSlots, totalSlots)
  end

  for i = 1, table.getn(order) do
    local key = order[i]
    local bucket = buckets[key]
    local entries = bucket and bucket.entries
    local n = (entries and table.getn(entries)) or 0
    if n > 0 then
      table.insert(visible, {
        key = key,
        entries = entries,
        n = n,
        headingHeight = metric.title,
        collapsed = collapsed[key] and true or false,
      })
    end
  end

  -- Specialty containers belong after the ordinary item categories, preserving
  -- the physical container order within this final group. Their used/total
  -- readout takes a cell of the box rather than a line under the heading, so
  -- the planner is told about one more item than the bag holds.
  for i = 1, table.getn(special) do
    local key = special[i]
    local bucket = buckets[key]
    table.insert(visible, {
      key = key,
      entries = bucket.entries,
      n = table.getn(bucket.entries),
      special = true,
      label = bucket.label,
      used = bucket.used,
      total = bucket.total,
      headingHeight = metric.title,
      collapsed = collapsed[key] and true or false,
    })
  end

  -- Free slots are one category holding one button, the proxy, however many
  -- slots are free. It is measured with the others, then taken back out and
  -- handed to the planner pinned to the top left (user request,
  -- 2026-09-24): it opens the first row rather than taking a line of its own.
  view.emptySlots = empty
  local emptyProxy = CV.BuildEmptyProxy(view)
  local emptySpec = nil
  if emptyProxy and table.getn(empty) > 0 then
    emptySpec = {
      key = "empty",
      entries = {},
      n = 1,
      empty = true,
      label = U.L("BAGS_CATEGORY_EMPTY"),
      headingHeight = metric.title,
      -- It has no collapse control, so it can never be folded; a fold stored
      -- before the control was removed is ignored.
      collapsed = false,
    }
    table.insert(visible, emptySpec)
  end

  -- Heading pass: set each heading's text and measure it, so the planner
  -- knows how narrow each box may go. The labels are never given a width,
  -- which is what keeps GetStringWidth honest on this client
  -- (widgets.fontstring_stringwidth_clamped_by_setwidth).
  for i = 1, table.getn(visible) do
    local spec = visible[i]
    local section = CV.EnsureSection(view, spec.key, fullContentWidth, spec.label)
    local text = spec.label or U.ItemCategoryLabel(spec.key)
    local heading = metric.toggle + metric.titlePad * 2
    local width = 0

    spec.section = section
    spec.shown = 0
    if not spec.collapsed then
      spec.shown = spec.special and (spec.n + 1) or spec.n
    end
    -- The empty-slot category is always one proxy slot: no +/- control, just
    -- its title (user requests, 2026-09-24), so the heading needs no room for
    -- the control and the box can stay one slot wide.
    if spec.empty then heading = metric.titlePad * 2 end
    if section.title then
      section.title:SetText(text)
      section.title:Show()
      local ok, w = pcall(section.title.GetStringWidth, section.title)
      width = (ok and tonumber(w)) or 0
    end
    -- Unmeasurable (no label, or the call failed): a rough per-glyph guess
    -- is better than letting the title run into the next box.
    if width <= 0 then width = string.len(text or "") * M.fontSize.small * 0.6 end
    if spec.special and section.count then
      section.count:SetText(U.L("BAGS_SLOT_COUNT", spec.used, spec.total))
      -- Reapplied after every SetText: the colour given at creation did not
      -- show in game (user report, 2026-09-24).
      pcall(section.count.SetTextColor, section.count, 1, 1, 1, 1)
      section.count:Show()
      -- A folded bag has no cell to show it in, so the readout follows the
      -- title on the heading line and the heading has to make room for it.
      if spec.collapsed then
        local ok, w = pcall(section.count.GetStringWidth, section.count)
        width = width + metric.titlePad + ((ok and tonumber(w)) or 0)
      end
    end
    spec.minSlots = CV.plan.SlotsForWidth(heading + width, metrics)
  end

  if emptySpec then table.remove(visible) end
  local rows = CV.plan.Rows(visible, metrics, emptySpec)

  -- Rows are only as wide as their content, so the block they form is centred
  -- in the window rather than leaving all of the spare width on the right.
  local blockWidth = 0
  for i = 1, table.getn(rows) do
    blockWidth = math.max(blockWidth, rows[i].fit.width)
  end
  local left = math.floor((metrics.budget - blockWidth) / 2)
  local toggleY = math.floor((metric.title - metric.toggle) / 2)

  -- Render pass: only applies the plan to frames.
  local proxyPlaced = false
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local fit = row.fit
    local bodyHeight = CV.plan.BodyHeight(fit.rows, metrics)
    local x = left
    local k

    for k = 1, table.getn(row.specs) do
      local spec = row.specs[k]
      local section = spec.section
      local columns = fit.widths[k]
      local boxWidth = CV.plan.BoxWidth(columns, metrics)
      drawn[spec.key] = true

      -- Heading row: the +/- control and the category name remain visible even
      -- when the category box below them is folded away. The title sits one
      -- unit below the control's centre line (user request, 2026-09-24).
      if spec.empty then
        -- No control: the title alone, on the line the other titles use (the
        -- control's centre, one unit lower).
        if section.toggle then section.toggle:Hide() end
      elseif section.toggle then
        section.toggle:ClearAllPoints()
        section.toggle:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -(y + toggleY))
        section.toggle.uuiSetCollapsed(spec.collapsed)
        section.toggle:Show()
      end
      if section.title then
        section.title:ClearAllPoints()
        if spec.empty then
          section.title:SetPoint("LEFT", grid, "TOPLEFT", x + metric.titlePad,
                                 -(y + math.floor(metric.title / 2)) - 1)
        elseif section.toggle then
          section.title:SetPoint("LEFT", section.toggle, "RIGHT",
                                 metric.titlePad, -1)
        else
          section.title:SetPoint("TOPLEFT", grid, "TOPLEFT", x + 2, -(y + 1))
        end
      end

      if spec.shown == 0 then
        -- The slots are simply not placed. Nothing marks them live, so the
        -- sweep at the end of this function is what takes them off screen.
        section.box:Hide()
      else
        -- Every box on a row shares the row's height, so the boxes line up
        -- top and bottom even when one needs fewer slot rows than the others.
        section.box:SetWidth(boxWidth)
        section.box:SetHeight(bodyHeight)
        section.box:ClearAllPoints()
        section.box:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -(y + fit.heading))
        section.box:Show()

        local j
        for j = 1, table.getn(spec.entries) do
          local entry = spec.entries[j]
          local button = host.ensureSlot(entry.bag, entry.slot)
          if button then
            local col = math.mod(j - 1, columns)
            local slotRow = math.floor((j - 1) / columns)
            host.placeSlot(button, section.box,
                           inset + col * pitch,
                           -(inset + slotRow * pitch))
            host.updateSlot(entry.bag, entry.slot)
            button:Show()
            live[entry.bag .. ":" .. entry.slot] = true
          end
        end

        if spec.empty then
          host.placeSlot(emptyProxy, section.box, inset, -inset)
          proxyPlaced = true
        end
      end

      if section.count then
        if not spec.special then
          section.count:Hide()
        elseif spec.collapsed then
          section.count:ClearAllPoints()
          if section.title then
            section.count:SetPoint("LEFT", section.title, "RIGHT",
                                   metric.titlePad, 0)
          else
            section.count:SetPoint("TOPLEFT", grid, "TOPLEFT",
                                   x + metric.toggle + metric.titlePad, -y)
          end
        else
          -- The planner reserved one cell past the bag's items, and every box
          -- on a row is at least as tall as its own items need, so the
          -- bottom-right cell is always free for the readout. It rests on
          -- the box's bottom border line, lowered 6 units so it overlaps the
          -- rim (user requests, 2026-09-24).
          section.count:ClearAllPoints()
          section.count:SetPoint("BOTTOMRIGHT", section.box, "BOTTOMRIGHT",
                                 -(inset + 2), CV.BorderLine() - 6)
        end
      end

      x = x + boxWidth + metric.columnGap
    end

    y = y + fit.height + metric.gap
  end

  if emptyProxy and proxyPlaced then
    pcall(SetItemButtonTexture, emptyProxy, nil)
    emptyProxy.count = 0
    if emptyProxy.uuiCount then
      emptyProxy.uuiCount:SetText(tostring(table.getn(empty)))
      emptyProxy.uuiCount:SetAlpha(1)
      emptyProxy.uuiCount:Show()
    end
    emptyProxy:Show()
  elseif emptyProxy then
    emptyProxy:Hide()
  end

  if y > 0 then y = y - metric.gap end

  -- Everything this pass did not place: every physical empty slot represented
  -- by the proxy, every slot inside a collapsed category, and any button left
  -- over from a container since swapped for a smaller one.
  local bags = host.bags()
  for i = 1, table.getn(bags) do
    local bag = bags[i]
    local bagSlots = host.slots[bag]
    if bagSlots then
      local slot
      for slot = 1, table.getn(bagSlots) do
        if bagSlots[slot] and not live[bag .. ":" .. slot] then
          bagSlots[slot]:Hide()
        end
      end
    end
  end

  local key, section
  for key, section in pairs(view.sections) do
    if not drawn[key] then CV.HideSection(section) end
  end

  -- No containers at all (or none readable yet): keep one slot row of window
  -- rather than collapsing the frame onto its header.
  if y <= 0 then y = slotSize end

  if type(host.onLayout) == "function" then host.onLayout(metrics.budget, y) end
  return metrics.budget, y, totalSlots
end

-- Leaves the category view for the host's flat grid: its boxes, headings and
-- proxy go away. The slot buttons are the host's to re-anchor.
function CV.Clear(view)
  CV.HideSections(view)
  view.emptySlots = {}
  if view.emptyProxy then view.emptyProxy:Hide() end
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------
-- host = {
--   grid        frame the view draws into (slot roots sit 5 levels above it)
--   name        global-name prefix: <name>Category_<key>, <name>EmptyProxy
--   columns     slots per full row; slotSize; slotGap() -> units
--   bags()      container ids, in display order
--   slotCount(bag), ensureSlot(bag, slot) -> button, slots[bag][slot]
--   placeSlot(button, relative, x, y), updateSlot(bag, slot)
--   collapsed() -> the persisted { [categoryKey] = true } table
--   favorites   true when the favourite section applies (carried bags)
--   styleBox(box), onSlotCount(used, total), onLayout(width, height),
--   onDropped()  -- all optional
--   fullText    locale key printed when a proxy drop finds no free slot
-- }
function U.CreateBagCategoryView(host)
  local view = { host = host, sections = {}, emptySlots = {} }
  view.Layout = function() return CV.Layout(view) end
  view.Clear = function() CV.Clear(view) end
  return view
end
