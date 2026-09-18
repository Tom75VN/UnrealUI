-- unrealUI :: modules/questlogdesign.lua
--
-- The Quest Log's Dragonflight design (Modern WoW), as one independent module.
--
-- modules/questlog.lua owns the window's behaviour -- quest rows, selection,
-- tracking, the reward hooks, the details toggle and the flat layout -- and
-- asks this file for the themed one: the page art's two panes, the three
-- action-button beds, the native scroll bars in their recessed channels, the
-- collapse-all column beside the gold ring, the DF-main count boxes, the
-- parchment ink for the details page and the scrolling reward-money row. The
-- page artwork itself is the `questlog` surface in modules/modernwow.lua; this
-- is everything that puts the client's own controls into it.
--
-- Active under `modern-wow` (the `questlog` surface) and under `classic-wow`
-- (the `questlog` Classic -> Modern WoW module), which is the point of the
-- split: both themes run exactly this code rather than each carrying a copy.
-- U.ModernWowSurfaceEnabled answers for both, so a theme is named in one place
-- (design.Active) instead of in every drawing decision. The choice is read
-- once; a theme or module change applies after reload, like every other one.
--
-- Nothing here is built unless modules/questlog.lua binds the window first, and
-- every entry point is a safe no-op while this design is not the one drawn --
-- that is what lets the owning module call them unconditionally.
--
-- Local budget: state, metrics and drawing hang off tables rather than a file
-- of top-level locals, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local design = {
  SURFACE = "questlog",
  -- Bound by modules/questlog.lua (U.ModernWowQuestLogBind).
  frame = nil,
  detail = nil,
  list = nil,
  collapseAll = nil,
  reapply = nil,
  rows = 23,
  -- The stock buttons the art has a drawn bed for, in bed order.
  buttons = {},
  active = nil,
}

-- Ink for the page art. This design draws the details pane as parchment, so
-- near-white body text and the chrome accent are both illegible on it; these
-- are the two colours used there instead. The quest LIST keeps its bright
-- text, because the same art draws that page dark.
local QUEST_INK_HEADING = M.modernWow.parchmentInk.heading
local QUEST_INK_BODY = M.modernWow.parchmentInk.body

local function G(name)
  return U.G(name)
end

local function IsShown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

-- Whether this design is the Quest Log's drawing path in this session. Read
-- once: the surface flag and the theme are both reload-bound, and every
-- drawing decision below asks this rather than the theme.
function design.Active()
  if design.active == nil then
    design.active = type(U.ModernWowSurfaceEnabled) == "function" and
                    U.ModernWowSurfaceEnabled(design.SURFACE) or false
  end
  return design.active
end

-- modules/questlog.lua's own strip-and-refont pass, which parts of this path
-- have to run at a specific point in their own work.
function design.Reapply()
  if type(design.reapply) == "function" then pcall(design.reapply) end
end

-- The details pane's scroll extent, after anything inside it has moved.
function design.UpdateDetailScroll()
  local pane = design.detail
  if not pane or type(pane.UpdateScrollChildRect) ~= "function" then return end
  pcall(pane.UpdateScrollChildRect, pane)
end

-- The details toggle is taken off the window under this design. The art draws
-- three button beds and one window control, the close button, with nowhere a
-- fourth belongs; the header strip is not it. Hidden rather than never built,
-- because the pane itself still works -- SetDetailVisible drives it, and the
-- empty-log path still collapses it -- and the flat themes still show the
-- control.
local function HideModernWowExpand(expand)
  if not expand then return end
  pcall(expand.Hide, expand)
  pcall(expand.EnableMouse, expand, false)
end

-- The action buttons sit in beds that are proportions of the window's left
-- page, and the window changes width whenever the details pane opens or
-- closes, so this runs again after every resize instead of once at build.
local function PlaceModernWowButtons()
  if type(U.ModernWowQuestLogButtonRect) ~= "function" then return end
  local i
  for i = 1, table.getn(design.buttons) do
    local entry = design.buttons[i]
    local left, bottom, width, height = U.ModernWowQuestLogButtonRect(entry.bed)
    if left and entry.button then
      pcall(function()
        entry.button:ClearAllPoints()
        entry.button:SetPoint("BOTTOMLEFT", design.frame, "BOTTOMLEFT", left, bottom)
        entry.button:SetWidth(width)
        entry.button:SetHeight(height)
      end)
      if type(U.StyleModernWowActionButton) == "function" then
        U.StyleModernWowActionButton(entry.button)
      end
    end
  end
end

-- Native Quest Log updates can enable or disable Share/Abandon without
-- resizing the footer. Repaint only the shared face on those updates; layout
-- remains the responsibility of PlaceModernWowButtons.
local function RefreshModernWowButtonStates()
  if not design.Active() or type(U.StyleModernWowActionButton) ~= "function" then
    return
  end
  local i
  for i = 1, table.getn(design.buttons) do
    U.StyleModernWowActionButton(design.buttons[i].button)
  end
end

-- Both scroll panes move into the pages the art draws instead of filling the
-- flat window, which is what the removed panel beds used to define. These are
-- measured off the art at the window's shipped 676x440 -- the same footing as
-- the flat layout numbers in modules/questlog.lua's BuildFrame, and the window
-- only has that width and the collapsed 340 where the details pane is hidden
-- anyway.
-- Where a scroll bar's left edge sits relative to its pane's right edge.
-- The stock templates hang the bar outside the pane (x = +6), which on this
-- art puts it past the page's printed edge and onto the frame. Negative pulls
-- it back inside, so the gutter lands on parchment and the bar lines up with
-- the pane the art defines. One constant for both panes, because they are the
-- same gutter on two pages.
local MW_SCROLLBAR_X = -10
local MW_SCROLLBAR_INSET_Y = 16
-- The quest list's bar sits this much further right, by request.
local MW_LIST_SCROLLBAR_NUDGE_X = 13
-- The quest list's bar reaches this much lower, so the thumb travels further
-- down, by request. Its bottom arrow is pulled up by the same amount to stay put.
local MW_LIST_SCROLLBAR_EXTEND_BOTTOM = 11

-- Where the details pane's left edge sits, measured from the quest list's
-- right edge. This is the whole offset, not an inset added to the flat
-- layout's own 35: that 35 belongs to the `modern` theme, which is frozen with
-- respect to this work, so modern-wow states its own value rather than padding
-- the shared one. The pane is only moved, not narrowed -- the art leaves slack
-- on the right that the wrap can grow into.
local MW_DETAIL_LEFT = 30

-- Clearance between the page art's gold ring and the first control placed
-- beside it.
local MW_RING_GAP = M.modernWow.collapseAll.ringGap

-- The list pane's top-left on the left page, and the gap the collapse-all
-- control keeps above it.
local MW_LIST_LEFT = 20
local MW_LIST_TOP = -72
local MW_COLLAPSE_ALL_GAP = 6
-- By request the icon and "All" label sit this much lower than the control's
-- hit area, which keeps the GAP position above.
local MW_COLLAPSE_ALL_FACE_DROP = 2

-- Re-anchors one stock scroll bar to its own pane. Both ends are set, so the
-- bar keeps tracking a pane whose height changes with the details toggle.
local function PlaceModernWowScrollBar(pane, barName, nudgeX, extendBottom)
  local bar = G(barName)
  if not pane or not bar then return end
  local x = MW_SCROLLBAR_X + (nudgeX or 0)
  local bottom = MW_SCROLLBAR_INSET_Y - (extendBottom or 0)
  pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", pane, "TOPRIGHT", x, -MW_SCROLLBAR_INSET_Y)
    bar:SetPoint("BOTTOMLEFT", pane, "BOTTOMRIGHT", x, bottom)
  end)
end

-- The details pane's bar goes into the channel the art recesses down the right
-- page, so it is placed against the window and the measured art rather than
-- against its own pane: the pane's right edge is a native width no unrealUI
-- module owns, and it is not what the channel lines up with.
--
-- The bar keeps its own width and is centred in the channel, because the art
-- draws a lit bevel down each side of it that the bar must not cover.
local function PlaceModernWowDetailScrollBar()
  local bar = G("QuestLogDetailScrollFrameScrollBar")
  if not bar or not design.frame then return false end
  if type(U.ModernWowQuestLogScrollRect) ~= "function" then return false end

  local left, top, width, height = U.ModernWowQuestLogScrollRect()
  if not left then return false end

  local okWidth, barWidth = pcall(bar.GetWidth, bar)
  barWidth = (okWidth and tonumber(barWidth)) or 0
  -- Centred in the channel, then nudged 2px left by request.
  local x = left + (width - barWidth) / 2 - 2

  pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", design.frame, "TOPLEFT", x, top)
    bar:SetPoint("BOTTOMLEFT", design.frame, "TOPLEFT", x, top - height)
  end)

  -- Only the bottom arrow drops 2px, by request; the bar and track stay put.
  -- WORKING_SOURCE: Vanilla's UIPanelScrollBarTemplate hangs ScrollDownButton
  -- TOP to the bar's BOTTOM with no offset. No runtime record confirms that
  -- anchor here, and GetPoint is not read back because this client inverts
  -- its Y (knowledge.json / frames.getpoint_relative_name_y_inverted).
  local down = G("QuestLogDetailScrollFrameScrollBarScrollDownButton")
  if down then
    pcall(function()
      down:ClearAllPoints()
      down:SetPoint("TOP", bar, "BOTTOM", 0, -2)
    end)
  end
  return true
end

local function PlaceModernWowPanes()
  -- By request, UnrealQuest's shorter rows get a list viewport 19px taller to
  -- the bottom. The scroll bar is compensated by the same amount so it stays
  -- in place.
  local listGrow = G("UnrealQuest") and 19 or 0
  if design.list then
    pcall(function()
      design.list:ClearAllPoints()
      design.list:SetPoint("TOPLEFT", design.frame, "TOPLEFT", MW_LIST_LEFT, MW_LIST_TOP)
      design.list:SetHeight(322 + listGrow)
    end)
  end
  PlaceModernWowScrollBar(design.list, "QuestLogListScrollFrameScrollBar",
                          MW_LIST_SCROLLBAR_NUDGE_X,
                          MW_LIST_SCROLLBAR_EXTEND_BOTTOM - listGrow)
  -- By request the list's top arrow rises 2px and its bottom arrow drops 14px;
  -- the bar and track stay put.
  -- WORKING_SOURCE: Vanilla's UIPanelScrollBarTemplate hangs ScrollUpButton
  -- BOTTOM to the bar's TOP and ScrollDownButton TOP to its BOTTOM, with no
  -- offset. GetPoint is not read back because this client inverts its Y
  -- (knowledge.json / frames.getpoint_relative_name_y_inverted).
  local listBar = G("QuestLogListScrollFrameScrollBar")
  local up = G("QuestLogListScrollFrameScrollBarScrollUpButton")
  local down = G("QuestLogListScrollFrameScrollBarScrollDownButton")
  if listBar and up then
    pcall(function()
      up:ClearAllPoints()
      up:SetPoint("BOTTOM", listBar, "TOP", 0, 2)
    end)
  end
  if listBar and down then
    pcall(function()
      down:ClearAllPoints()
      down:SetPoint("TOP", listBar, "BOTTOM", 0,
                    -14 + MW_LIST_SCROLLBAR_EXTEND_BOTTOM)
    end)
  end
  PlaceModernWowDetailScrollBar()
  -- The details pane keeps its anchor to the list pane's top-right corner, so
  -- it has already followed the list onto the parchment. Its height has to
  -- come in or it runs off the bottom of the page, and its left edge is set
  -- outright -- see MW_DETAIL_LEFT.
  if design.detail then
    if design.list then
      pcall(function()
        design.detail:ClearAllPoints()
        design.detail:SetPoint("TOPLEFT", design.list, "TOPRIGHT", MW_DETAIL_LEFT, 0)
      end)
    end
    pcall(design.detail.SetHeight, design.detail, 340)
    local child = G("QuestLogDetailScrollChildFrame")
    -- Keep the page viewport inside the modern-wow artwork, but retain the
    -- native 376px content extent. Collapsing both to 340 clipped the native
    -- money row exactly 35px below the child (questrewardlayout.live_geometry.v3),
    -- while classic-wow kept the row because it never shortened this child.
    if child then pcall(child.SetHeight, child, 376) end
    design.UpdateDetailScroll()
  end
end

local function RefreshModernWow()
  if not design.Active() then return false end
  PlaceModernWowPanes()
  PlaceModernWowButtons()
  -- Re-hidden on every refresh: the shared toggle path restyles and re-places
  -- this control whenever the pane changes, so once is not enough.
  HideModernWowExpand(G("UnrealUIQuestLogExpand"))
  return true
end

-- The native QuestLogMoneyFrame does not travel with this client's detail
-- scroll child under this design. When UnrealQuest is absent, replace it with
-- the same owned denomination row that UnrealQuest uses: a number followed by
-- a slice of Interface\MoneyFrame\UI-MoneyIcons for each non-zero coin value.
--
-- The row is deliberately parented to QuestLogDetailScrollChildFrame and
-- anchored to QuestLogItemReceiveText. Focused questrewardlayout probes verify
-- those exact objects and this scrolling ownership on the current client. The
-- named container also lets the first guaranteed reward item be restored only
-- when it is still anchored to this row; GetPoint returns fresh wrappers here,
-- so object identity must not be used.
--
-- UnrealQuest is the sole owner whenever its runtime global exists. That keeps
-- this fallback from hiding its coin row, moving its reward item, or issuing a
-- second UpdateScrollChildRect call (which can flash scrolled contents at their
-- unscrolled position on this client).
local money = {
  name = "UnrealUIQuestLogRewardMoney",
  itemGap = 5,
  row = nil,
  readout = nil,
  movedItem = nil,
  amount = nil,
  anchored = false,
  relativeTop = nil,
  relativeBottom = nil,
}

function money.RelativeName(relative)
  if type(relative) == "string" then return relative end
  if relative and type(relative.GetName) == "function" then
    local ok, name = pcall(relative.GetName, relative)
    if ok then return name end
  end
  return nil
end

function money.RestoreMovedItem()
  local item = money.movedItem
  money.movedItem = nil
  if not item or type(item.GetPoint) ~= "function" then return false end

  local ok, point, relative, relativePoint, x = pcall(item.GetPoint, item, 1)
  if not ok or money.RelativeName(relative) ~= money.name then
    return false
  end

  local label = G("QuestLogItemReceiveText")
  if not label then return false end
  return pcall(function()
    item:ClearAllPoints()
    item:SetPoint(point or "TOPLEFT", label, relativePoint or "BOTTOMLEFT",
                  type(x) == "number" and x or 0, -money.itemGap)
  end)
end

function money.Create(dock)
  if money.row ~= nil then return money.row or nil end
  local ok, row = pcall(CreateFrame, "Frame", money.name, dock)
  if not ok or not row then
    money.row = false
    return nil
  end

  pcall(row.SetHeight, row, 14)
  pcall(row.SetWidth, row, 1)
  local readout = U.CreateMoneyReadout(row, { gap = 1 })
  if not readout then
    pcall(row.Hide, row)
    money.row = false
    return nil
  end
  readout:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

  -- Match UnrealQuest's quest-reward row: white, shadow-free numbers; the coin
  -- art itself carries the denomination colour.
  local coins = { readout.gold, readout.silver, readout.copper }
  local i
  for i = 1, table.getn(coins) do
    local label = coins[i] and coins[i].label
    if label then
      U.SetFont(label, M.fontSize.small, nil, nil, true)
      U.ClearTextShadow(label)
      pcall(label.SetTextColor, label, 1, 1, 1, 1)
    end
  end

  local levelOk, level = pcall(dock.GetFrameLevel, dock)
  if levelOk and type(level) == "number" then
    pcall(row.SetFrameLevel, row, level + 2)
  end
  money.row = row
  money.readout = readout
  return row
end

function money.RewardCounts()
  local choices, rewards = 0, 0
  local getChoices = G("GetNumQuestLogChoices")
  local getRewards = G("GetNumQuestLogRewards")
  if type(getChoices) == "function" then
    local ok, value = pcall(getChoices)
    if ok and type(value) == "number" and value > 0 then choices = value end
  end
  if type(getRewards) == "function" then
    local ok, value = pcall(getRewards)
    if ok and type(value) == "number" and value > 0 then rewards = value end
  end
  return choices, rewards
end

-- Native quest-detail refreshes can restore the guaranteed-item anchor after
-- unrealUI's synchronous post-hook has returned. Read the live anchor and
-- write only when it has moved back to QuestLogItemReceiveText; a stable item
-- already attached to the owned row is left completely untouched.
function money.PlaceRewardItem(row)
  local choices, rewards = money.RewardCounts()
  if rewards <= 0 then return money.RestoreMovedItem() end

  local item = G("QuestLogItem" .. (choices + 1))
  if not item or type(item.GetPoint) ~= "function" then return false end
  if money.movedItem and money.movedItem ~= item then
    money.RestoreMovedItem()
  end

  local ok, point, relative, relativePoint, x = pcall(item.GetPoint, item, 1)
  if not ok then return false end
  local relativeName = money.RelativeName(relative)
  if relativeName == money.name then
    money.movedItem = item
    return false
  end
  if relativeName ~= "QuestLogItemReceiveText" then return false end

  local placed = pcall(function()
    item:ClearAllPoints()
    item:SetPoint(point or "TOPLEFT", row, relativePoint or "BOTTOMLEFT",
                  type(x) == "number" and x or 0,
                  -money.itemGap)
  end)
  if placed then money.movedItem = item end
  return placed and true or false
end

function money.ReadAmount()
  local getMoney = G("GetQuestLogRewardMoney")
  if type(getMoney) == "function" then
    local ok, value = pcall(getMoney)
    if ok and type(value) == "number" then return math.max(value, 0) end
  end
  return nil
end

function money.GeometryChanged(row, dock)
  local function Read(object, method)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object)
    return ok and type(value) == "number" and value or nil
  end

  local rowTop, rowBottom = Read(row, "GetTop"), Read(row, "GetBottom")
  local dockTop, dockBottom = Read(dock, "GetTop"), Read(dock, "GetBottom")
  local relativeTop = rowTop and dockTop and (rowTop - dockTop) or nil
  local relativeBottom = rowBottom and dockBottom and (rowBottom - dockBottom) or nil
  local changed = money.relativeTop ~= relativeTop
                  or money.relativeBottom ~= relativeBottom
  money.relativeTop = relativeTop
  money.relativeBottom = relativeBottom
  return changed
end

-- A late-loading UnrealQuest takes ownership cleanly: remove only state this
-- fallback marked as its own, and never undo UnrealQuest's separate native
-- replacement marker.
function money.Release()
  money.RestoreMovedItem()
  if money.row and IsShown(money.row) then
    pcall(money.row.Hide, money.row)
  end
  money.amount = nil
  money.anchored = false
  money.relativeTop = nil
  money.relativeBottom = nil

  local native = G("QuestLogMoneyFrame")
  if native and native.uuiModernWowMoneyReplaced then
    native.uuiModernWowMoneyReplaced = nil
    if not native.unrealQuestMoneyReplaced then
      pcall(native.SetAlpha, native, 1)
      local amount = money.ReadAmount()
      if amount and amount > 0 then pcall(native.Show, native) end
    end
  end
end

function money.Refresh()
  if not design.Active() then return false end
  if G("UnrealQuest") then
    money.Release()
    return false
  end

  local amount = money.ReadAmount()
  if amount == nil then
    money.Release()
    return false
  end

  local dock = G("QuestLogDetailScrollChildFrame")
  local label = G("QuestLogItemReceiveText")
  local native = G("QuestLogMoneyFrame")
  local wanted = amount and amount > 0 and dock and label
                 and IsShown(dock) and IsShown(label)

  -- FrameXML shows the native frame again on every selection. Alpha zero keeps
  -- it from flashing before this post-hook hides it again.
  if native then
    if not native.uuiModernWowMoneyReplaced then
      native.uuiModernWowMoneyReplaced = true
      pcall(native.SetAlpha, native, 0)
    end
    if IsShown(native) then pcall(native.Hide, native) end
  end

  local changed = false
  local row = money.row or nil
  if wanted and money.row == nil then
    row = money.Create(dock)
  end
  if not wanted or not row then
    changed = money.RestoreMovedItem()
    if row and IsShown(row) then
      pcall(row.Hide, row)
      changed = true
    end
    money.amount = nil
    money.relativeTop = nil
    money.relativeBottom = nil
    if changed then design.UpdateDetailScroll() end
    return false
  end

  changed = changed or not IsShown(row)
  if money.amount ~= amount then
    money.readout:SetAmount(amount)
    row:SetWidth(money.readout.contentWidth or 1)
    money.amount = amount
    changed = true
  end
  if not money.anchored then
    money.anchored = pcall(function()
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    end)
    changed = money.anchored or changed
  end
  if not IsShown(row) then pcall(row.Show, row) end
  changed = money.GeometryChanged(row, dock) or changed
  changed = money.PlaceRewardItem(row) or changed

  if changed then design.UpdateDetailScroll() end
  return true
end

-- modern-wow's list page is 322 high, so QUEST_ROWS stock rows run past the
-- artwork and over the footer buttons (USER_CONFIRMED_INGAME without
-- UnrealQuest). Trim QUESTS_DISPLAYED to the rows that actually end inside the
-- pane, so the surplus goes onto the native scroll bar.
--
-- Same measured algorithm as UnrealQuest's Client.FitQuestLogRowsToList
-- (WORKING_SOURCE, this client), which runs on this window when that addon is
-- loaded and changes the row height. Both passes only ever lower the count,
-- stop at the first hidden row and do nothing once every shown row fits, so
-- whichever runs second is a no-op: the two cannot fight.
-- GetBottom: DOCUMENTED_NOT_RUNTIME_VERIFIED; a missing value trims nothing.
local fitRows = { busy = false }

function fitRows.Apply()
  if fitRows.busy or not design.Active() or not design.list or not IsShown(design.frame) then
    return
  end
  -- Both fit passes only ever lower the count, so a pane that has grown (the
  -- UnrealQuest viewport extension) would keep the rows trimmed for the old
  -- height. When the height changes, restore the full pool and re-run the
  -- native update so the rows are shown again before they are measured.
  local okHeight, paneHeight = pcall(design.list.GetHeight, design.list)
  if okHeight and type(paneHeight) == "number"
      and paneHeight ~= fitRows.paneHeight then
    fitRows.paneHeight = paneHeight
    if QUESTS_DISPLAYED ~= design.rows then
      QUESTS_DISPLAYED = design.rows
      local update = G("QuestLog_Update")
      if type(update) == "function" then
        fitRows.busy = true
        pcall(update)
        fitRows.busy = false
      end
    end
  end

  local okPane, paneBottom = pcall(design.list.GetBottom, design.list)
  if not okPane or type(paneBottom) ~= "number" then return end

  local fitting, overflow = 0, nil
  local i
  for i = 1, design.rows do
    local row = G("QuestLogTitle" .. i)
    if not row or not IsShown(row) then break end
    local okRow, bottom = pcall(row.GetBottom, row)
    if not okRow or type(bottom) ~= "number" then return end
    -- Half a pixel of slack: a row resting on the pane edge is inside it.
    if bottom < paneBottom - 0.5 then
      overflow = i
      break
    end
    fitting = i
  end
  if not overflow or fitting < 6 then return end

  for i = overflow, design.rows do
    local row = G("QuestLogTitle" .. i)
    if row then pcall(row.Hide, row) end
  end
  QUESTS_DISPLAYED = fitting

  -- Re-run the native update so FauxScrollFrame_Update sees the new count.
  local update = G("QuestLog_Update")
  if type(update) == "function" then
    fitRows.busy = true
    pcall(update)
    fitRows.busy = false
  end
end

-- Quest and completed counts across the top of the modern-wow list page, laid
-- out as DF-main's DFQuestLogCount boxes. One table, so the whole subsystem
-- costs this file one local slot.
--
-- GetQuestLogTitle's six-value tuple matches Vanilla here (knowledge.json /
-- api.getquestlogtitle_now_matches_vanilla); isComplete, the sixth, was nil in
-- every captured sample, so the completed count is not yet runtime-verified.
-- GetNumQuestLogEntries' second return (the quest count) is the Vanilla shape
-- and is undocumented here. A missing count falls back to the visible quest
-- rows, which leaves out quests under a collapsed header
-- (knowledge.json / questlog.collapsed_header_hides_quests).
local questCount = { boxes = {} }

function questCount.CreateBox(parent)
  local spec = M.modernWow.questLog.countBox
  local paths = spec.border
  if not paths then return nil end
  local ok, box = pcall(CreateFrame, "Frame", nil, parent)
  if not ok or not box then return nil end

  -- The page art's chrome is also a child of this window and only drops a
  -- level when the window sits above level 1 (mw.DressWindow), so at a low
  -- level it shares the box's level and its BACKGROUND art covered the box's
  -- BACKGROUND fill while the rim and text still drew. Lift the box clear.
  local levelOk, level = pcall(parent.GetFrameLevel, parent)
  if levelOk and tonumber(level) then
    pcall(box.SetFrameLevel, box, level + spec.levelAbove)
  end

  local built = pcall(function()
    box:SetHeight(spec.height)
    box:SetWidth(spec.minWidth)
    box:EnableMouse(false)

    -- See-through dark bed inside the rim. Drawn as a plain-file backdrop,
    -- the fill path U.CreateBackdrop uses for the list panel that already
    -- shows on this client; a separate tinted BACKGROUND texture did not
    -- show here (USER_CONFIRMED_INGAME 2026-09-16). The edge colour is
    -- cleared per knowledge.json / rendering.setbackdrop_keeps_native_edge_art.
    local inset = spec.fillInset
    box:SetBackdrop({
      bgFile = M.texture.plain,
      tile = false,
      tileSize = 0,
      insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    box:SetBackdropColor(M.Unpack(spec.fillColor))
    box:SetBackdropBorderColor(0, 0, 0, 0)

    -- The talent panels' eight-slice ThinBorder rim (tal.BuildPanelBorder in
    -- modules/talentsmodernwow.lua). The art ships no bottom-right corner, so
    -- the bottom-left one is mirrored into it.
    local edge = spec.edge
    local function Piece(path, width, height)
      local texture = box:CreateTexture(nil, "BORDER")
      texture:SetTexture(path)
      if width then texture:SetWidth(width) end
      if height then texture:SetHeight(height) end
      return texture
    end

    local topLeft = Piece(paths.topLeft, edge, edge)
    local topRight = Piece(paths.topRight, edge, edge)
    local bottomLeft = Piece(paths.bottomLeft, edge, edge)
    local bottomRight = Piece(paths.bottomLeft, edge, edge)
    bottomRight:SetTexCoord(1, 0, 0, 1)
    topLeft:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    topRight:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    bottomLeft:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    bottomRight:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

    local top = Piece(paths.top, nil, edge)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
    local bottom = Piece(paths.bottom, nil, edge)
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
    local left = Piece(paths.left, edge, nil)
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
    local right = Piece(paths.right, edge, nil)
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
  end)

  box.label = built and U.CreateLabel(box, {
    size = M.fontSize.small,
    color = spec.labelColor,
    inherits = "GameFontNormalSmall",
  })
  if not box.label then
    pcall(box.Hide, box)
    return nil
  end
  pcall(function()
    box.label:SetPoint("LEFT", box, "LEFT", spec.padding, 0)
  end)
  return box
end

-- Sets one box's text and fits the box to it.
function questCount.SetText(box, text)
  local spec = M.modernWow.questLog.countBox
  pcall(box.label.SetText, box.label, text)

  local ok, width = pcall(box.label.GetStringWidth, box.label)
  width = ok and tonumber(width)
  if not width or width <= 0 then
    ok, width = pcall(box.label.GetWidth, box.label)
    width = ok and tonumber(width)
  end
  if width and width > 0 then
    pcall(box.SetWidth, box, math.max(spec.minWidth, width + 2 * spec.padding))
  end
end

function questCount.Update()
  local quests, completed = questCount.boxes[1], questCount.boxes[2]
  if not quests or not completed then return end

  local getCount = G("GetNumQuestLogEntries")
  local getTitle = G("GetQuestLogTitle")
  if type(getCount) ~= "function" or type(getTitle) ~= "function" then return end

  local ok, numEntries, numQuests = pcall(getCount)
  numEntries = ok and tonumber(numEntries)
  if not numEntries then return end

  local rows, done = 0, 0
  for i = 1, numEntries do
    local titleOk, text, _, _, isHeader, _, isComplete = pcall(getTitle, i)
    if titleOk and type(text) == "string" and not isHeader then
      rows = rows + 1
      if isComplete == 1 or isComplete == true then done = done + 1 end
    end
  end

  local spec = M.modernWow.questLog.countBox
  local total = tonumber(numQuests) or rows
  local max = tonumber(G("MAX_QUESTLOG_QUESTS")) or spec.maxQuests
  questCount.SetText(quests, string.format(U.L("QUESTLOG_COUNT"), total, max))
  questCount.SetText(completed,
                     string.format(U.L("QUESTLOG_COMPLETED"), done, total))
end

-- Builds both boxes once, `x` units in from the window's left edge and, when
-- `centerY` is given, vertically centred on that offset from the window top.
-- Returns true only when both exist, so the caller hides the native count
-- line only when something replaces it.
function questCount.Build(x, centerY)
  if questCount.boxes[1] then return true end
  local spec = M.modernWow.questLog.countBox

  local quests = questCount.CreateBox(design.frame)
  local completed = quests and questCount.CreateBox(design.frame)
  if not completed then
    if quests then pcall(quests.Hide, quests) end
    return false
  end

  pcall(function()
    if centerY then
      quests:SetPoint("LEFT", design.frame, "TOPLEFT", x, centerY)
    else
      quests:SetPoint("TOPLEFT", design.frame, "TOPLEFT", x, spec.y)
    end
    completed:SetPoint("LEFT", quests, "RIGHT", spec.gap, 0)
  end)
  questCount.boxes = { quests, completed }
  questCount.Update()
  return true
end

-- One-time setup, run from modules/questlog.lua once every control exists
-- (U.ModernWowQuestLogDress).
local function DressModernWow(panels, buttons)
  if not design.Active() then return false end

  -- The art's header strip is deeper than the flat window's title row, so the
  -- close button drops into it.
  local close = G("QuestLogFrameCloseButton")
  if close then
    pcall(function()
      close:ClearAllPoints()
      close:SetPoint("TOPRIGHT", design.frame, "TOPRIGHT", -10, -16)
    end)
  end

  -- The collapse-all control moves out from under the page art's gold ring.
  -- Anchored to the first quest row it sat at roughly x 24, y -50..-68 from
  -- the window's top-left, and the ring covers x 5..69, y -2..-63 there, so
  -- the two overlapped. It keeps the column beside the ring, but sits just
  -- above the list pane by request rather than level with the ring's centre.
  --
  -- The column is measured off the live ring rather than hardcoded, because
  -- the ring is a fraction of a window whose width changes with the details
  -- pane.
  local ringLeft, ringTop, ringWidth, ringHeight
  if type(U.ModernWowQuestLogRingRect) == "function" then
    ringLeft, ringTop, ringWidth, ringHeight = U.ModernWowQuestLogRingRect()
  end
  if design.collapseAll and ringLeft then
    pcall(function()
      design.collapseAll:ClearAllPoints()
      -- The whole button drops so its icon and native label follow it without
      -- re-anchoring the label, whose native offset is not known here; the hit
      -- rect is pushed back up by the same amount so the click area stays put.
      -- Frame:SetHitRectInsets is DOCUMENTED_NOT_RUNTIME_VERIFIED; negative
      -- insets expand, per the same note in core/stockui.lua.
      design.collapseAll:SetPoint("BOTTOMLEFT", design.frame, "TOPLEFT",
                                  ringLeft + ringWidth + MW_RING_GAP,
                                  MW_LIST_TOP + MW_COLLAPSE_ALL_GAP
                                    - MW_COLLAPSE_ALL_FACE_DROP)
      design.collapseAll:SetHitRectInsets(0, 0, -MW_COLLAPSE_ALL_FACE_DROP,
                                          MW_COLLAPSE_ALL_FACE_DROP)
    end)
  elseif design.collapseAll and G("QuestLogTitle1") then
    -- No ring rect means no page art measurement to place against; the old
    -- row-relative spot is still better than leaving the control unplaced.
    pcall(function()
      design.collapseAll:ClearAllPoints()
      design.collapseAll:SetPoint("BOTTOMLEFT", G("QuestLogTitle1"), "TOPLEFT", 4, 4)
    end)
  end
  if type(U.ModernWowCollapseFace) == "function" then
    pcall(U.ModernWowCollapseFace, design.collapseAll)
  end

  -- The count boxes sit on the collapse-all control's row, just right of it,
  -- and replace the native count line, which is hidden only once they exist.
  -- Placed from the same numbers as that control plus its size read once
  -- here, never anchored to the client-owned button (rules/unreal-ui.md,
  -- native widget ownership). Without the ring rect the control hangs off the
  -- first row instead, so the boxes keep their own top-row fallback.
  local countX, countY = MW_LIST_LEFT, nil
  if ringLeft and design.collapseAll then
    local spec = M.modernWow.questLog.countBox
    local okW, w = pcall(design.collapseAll.GetWidth, design.collapseAll)
    local okH, h = pcall(design.collapseAll.GetHeight, design.collapseAll)
    w = (okW and tonumber(w) and w > 0) and w or spec.collapseWidth
    h = (okH and tonumber(h) and h > 0) and h or spec.collapseHeight
    countX = ringLeft + ringWidth + MW_RING_GAP + w + spec.collapseGap
    countY = MW_LIST_TOP + MW_COLLAPSE_ALL_GAP - MW_COLLAPSE_ALL_FACE_DROP + h / 2
             + spec.rowOffsetY
  end
  if questCount.Build(countX, countY) then
    U.HideRegion(G("QuestLogQuestCount"))
  end

  -- The ring the art draws is empty on purpose; modules/modernwow.lua fills it
  -- with the stock book portrait on its own chrome, out of this strip's reach.
  if type(U.ModernWowQuestLogBook) == "function" then
    pcall(U.ModernWowQuestLogBook)
  end
  design.Reapply()

  local i
  for i = 1, table.getn(panels) do
    -- The art draws both pages itself, so these beds are what hid the
    -- parchment. The frames stay -- detailPanel still tracks the pane's
    -- visibility -- they simply stop painting.
    U.SetBackdropShown(panels[i], false)
  end

  for i = 1, table.getn(buttons) do
    local button = buttons[i]
    if button then
      table.insert(design.buttons, { button = button, bed = i })
      U.SetBackdropShown(button, false)
    end
  end

  return RefreshModernWow()
end

local function ResizeModernWowTexture()
  if type(U.ResizeModernWowQuestLog) == "function" then
    pcall(U.ResizeModernWowQuestLog)
  end
  RefreshModernWow()
end

-- ---------------------------------------------------------------------------
-- Details-page line fitting
--
-- Left-aligns a single-line details string without relying on justification.
--
-- /uui qlalign (2026-09-13, modern-wow, UnrealUIDiagDB.questLogAlign) measured
-- the title, headings and objective lines as fixed 285-wide boxes anchored
-- TOPLEFT, with text 59-98 wide drawn centred inside them, even though
-- modules/questlog.lua issues SetJustifyH("LEFT") last; GetJustifyH does not
-- exist on these FontStrings, so the justification call is not observable here.
-- The box already starts at the page margin, so shrinking it to its own text
-- puts the text there. The native width is remembered once and restored for
-- empty text, and is the ceiling, so a long line still wraps where it did
-- before.
--
-- Failed approach (USER_CONFIRMED_INGAME 2026-09-13, reverted): adding a
-- second TOPRIGHT point derived from the live GetPoint tuple plus
-- SetJustifyH("LEFT") broke the whole details page layout.
-- The measuring itself is shared with modules/quest.lua in core/stockui.lua.
-- ---------------------------------------------------------------------------

-- The details-page strings that take that fit, in one list because two places
-- need it: the owning module's font pass, which runs on the client's own
-- refreshes, and the re-fit poll below, which covers the writes those
-- refreshes do not announce.
local FIT_LINES = {
  "QuestLogQuestTitle",
  "QuestLogObjectivesText",
  "QuestLogDescriptionTitle",
  "QuestLogQuestDescription",
  "QuestLogRewardTitleText",
  "QuestLogItemChooseText",
}

-- A fit is only as good as the string it was measured against, and these
-- strings are not all written by the client: UnrealQuest replaces the title,
-- the summary and the description with its own translation from its 0.2s
-- poll, long after QuestLog_UpdateQuestDetails has been and gone. A box still
-- sized for the English line then wraps the longer translated one inside
-- itself.
--
-- So the fit is re-measured on a change of text rather than on an event,
-- which is also the only way it can work: there is nothing to hook. Guarded
-- by U.FitLineIsStale, so a page nobody has translated does no work at all.
local function RefitChangedLines()
  local i
  for i = 1, table.getn(FIT_LINES) do
    local object = G(FIT_LINES[i])
    if U.FitLineIsStale(object) then U.FitLineToText(object) end
  end
end

-- ---------------------------------------------------------------------------
-- Entry points for modules/questlog.lua
--
-- Each one answers design.Active() itself, so the owning module keeps one
-- theme read (U.ModernWowQuestLogActive) and calls the rest unconditionally.
-- ---------------------------------------------------------------------------

function U.ModernWowQuestLogActive()
  return design.Active()
end

-- The native window and the controls this path places into the art, plus the
-- owning module's strip-and-refont pass. Nothing is drawn here: the module
-- binds during its own build and dresses afterwards.
function U.ModernWowQuestLogBind(context)
  if not design.Active() or type(context) ~= "table" then return false end
  design.frame = context.frame
  design.detail = context.detail
  design.list = context.list
  design.collapseAll = context.collapseAll
  design.reapply = context.reapply
  design.rows = tonumber(context.rows) or design.rows
  return true
end

-- The two details-page colours, or nil for the flat themes' own text colours.
function U.ModernWowQuestLogInk()
  if not design.Active() then return nil, nil end
  return QUEST_INK_HEADING, QUEST_INK_BODY
end

function U.ModernWowQuestLogFitLine(object)
  if not object or not design.Active() then return end
  U.FitLineToText(object)
end

function U.ModernWowQuestLogFitLines()
  if not design.Active() then return end
  local i
  for i = 1, table.getn(FIT_LINES) do
    U.FitLineToText(G(FIT_LINES[i]))
  end
end

-- The themed collapse glyph on one stock quest-log header row.
function U.ModernWowQuestLogRowFace(row)
  if not design.Active() or not row then return false end
  if type(U.ModernWowCollapseFace) ~= "function" then return false end
  return pcall(U.ModernWowCollapseFace, row) and true or false
end

-- One-time setup, run by the owning module once every control exists.
function U.ModernWowQuestLogDress(panels, buttons)
  return DressModernWow(panels or {}, buttons or {})
end

function U.ModernWowQuestLogRefresh()
  return RefreshModernWow()
end

function U.ModernWowQuestLogRefreshButtons()
  RefreshModernWowButtonStates()
end

-- Called after the native frame changes between its compact and expanded
-- widths: the page art is rescaled, then everything measured off it is placed
-- again.
function U.ModernWowQuestLogResize()
  if not design.Active() then return false end
  ResizeModernWowTexture()
  return true
end

function U.ModernWowQuestLogFitRows()
  fitRows.Apply()
end

function U.ModernWowQuestLogCountUpdate()
  questCount.Update()
end

function U.ModernWowQuestLogMoneyRefresh()
  return money.Refresh()
end

-- The two polls this path needs, registered by the owning module once its
-- window is built. Both read the window's shown state, so neither does work
-- while the Quest Log is closed.
function U.ModernWowQuestLogBeginPolls()
  if not design.Active() then return false end

  -- UnrealQuest repairs the same native anchor from its shared 0.3-second
  -- driver. Poll only while the window is shown, and keep Refresh read-only
  -- once the reward item still belongs to the scrolling coin row.
  U.RegisterUpdate("questlog.modernwow-money", 0.3, function()
    if G("UnrealQuest") then
      money.Release()
      U.UnregisterUpdate("questlog.modernwow-money")
      return
    end
    if IsShown(design.frame) then money.Refresh() end
  end)
  -- Separate from the coin poll above, which retires itself when UnrealQuest
  -- is loaded: this one exists BECAUSE of that addon's translation writes, so
  -- it has to survive exactly the case that one stands down for. Read-only on
  -- an untranslated page.
  U.RegisterUpdate("questlog.modernwow-fit", 0.3, function()
    if IsShown(design.frame) then RefitChangedLines() end
  end)
  return true
end
