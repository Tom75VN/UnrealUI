-- unrealUI :: modules/questlogextended.lua
--
-- Two-page parchment Quest Log for the Classic WoW theme.
--
-- Ported from UnrealQuest (Quest/ExtendedQuestLog.lua plus the extended
-- quest-log section of Compatibility/ClientAPI.lua), which in turn took its
-- layout and artwork from Extended QuestLog 3.6.1 (Copyright 2006 Daniel
-- Rehn). unrealUI now owns this surface outright: it carries its own copy of
-- the parchment art (media/Textures/classic-wow/questLog/, tokens in core/media.lua) and
-- applies the layout itself, so it works in a session with no UnrealQuest
-- installed. UnrealQuest's own module stands down whenever unrealUI is
-- present -- see the ownership note below.
--
-- Only the presentation is imported. The client still owns selection,
-- scrolling, quest actions and detail population on the same stock widgets,
-- and UnrealQuest's level, translation, tracking, reward and action-button
-- modules keep decorating them exactly as before.
--
-- Theme scope. This is the Classic WoW theme only, i.e. the one theme whose
-- windows keep native client chrome. `modern` and `modern-wow` already replace
-- the Quest Log with their own two-pane surface in modules/questlog.lua, which
-- is why that module builds nothing under native chrome and this one builds
-- nothing under anything else. The two never run together.
--
-- rules/unreal-ui-design.md deviation, recorded rather than hidden: parchment
-- is not the flat near-black system that file makes law for addon-owned extras
-- under `classic-wow`. It is here by explicit user decision, because the classic-wow
-- look *is* the requested feature and cannot be delivered in the flat family.
-- It stays confined to this window and this theme -- no token, colour or
-- texture from media/Textures/classic-wow/questLog/ is read anywhere else.
--
-- Ownership signal for UnrealQuest: the presence of the UnrealUI global is
-- what UnrealQuest checks, and U.ExtendedQuestLogOwned() below is the explicit
-- answer for anything that wants more than "installed". unrealUI wins whenever
-- both addons are loaded, under every theme.

local U = UnrealUI
local M = U.media
local QLX = U.RegisterModule("questlogextended")

-- The native frames are created by FrameXML, not by unrealUI, so they can be
-- unavailable for the first frames of a session. Poll on the shared driver
-- rather than making their load timing a correctness dependency; the same
-- fifteen-second budget UnrealQuest used.
local POLL_ID = "questlogextended.apply"
local POLL_INTERVAL = 0.5
local POLL_SECONDS = 15
local REWARD_ID = "questlogextended.rewards"
local REWARD_INTERVAL = 0.2

-- One table rather than a dozen file-scope locals (rules/unreal-ui.md, Lua's
-- 200-local ceiling is a silent whole-file load failure).
local state = {
  waited = 0,
  applied = nil,   -- nil untested, false failed, true live
  rows = nil,      -- how many stock rows the left page ended up holding
  pitch = nil,     -- the measured row height those rows are spaced by
  mode = "pending",
}

local function G(name)
  return U.G(name)
end

-- True while unrealUI owns the Quest Log presentation. Deliberately not
-- theme-dependent: under `modern` and `modern-wow` modules/questlog.lua owns
-- it, under `classic-wow` this module does, and a sibling addon should stand
-- down in either case.
function U.ExtendedQuestLogOwned()
  return true
end

function U.QuestLogExtendedReport()
  return state
end

local function IsShown(object)
  if not object or type(object.IsShown) ~= "function" then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

local function SetSize(object, width, height)
  if not object then return false end
  local applied = false
  if type(width) == "number" and width > 0 and type(object.SetWidth) == "function" then
    applied = pcall(object.SetWidth, object, width) or applied
  end
  if type(height) == "number" and height > 0 and type(object.SetHeight) == "function" then
    applied = pcall(object.SetHeight, object, height) or applied
  end
  return applied and true or false
end

local function SetAnchor(object, point, relative, relativePoint, x, y)
  if not object or type(object.ClearAllPoints) ~= "function"
     or type(object.SetPoint) ~= "function" then
    return false
  end
  pcall(object.ClearAllPoints, object)
  return pcall(object.SetPoint, object, point, relative, relativePoint, x, y)
         and true or false
end

-- knowledge.json / frames.getpoint_relative_name_y_inverted: this client
-- returns the relative widget's NAME rather than the widget, and inverts Y.
-- So an anchor is compared by ownership only -- point, relative point and
-- which widget it hangs off -- never by offset.
local function AnchorMatches(object, point, relative, relativeName, relativePoint)
  if not object or type(object.GetPoint) ~= "function" then return false end
  local ok, actualPoint, actualRelative, actualRelativePoint =
    pcall(object.GetPoint, object, 1)
  if not ok or actualPoint ~= point or actualRelativePoint ~= relativePoint then
    return false
  end
  if actualRelative == relative then return true end
  return type(actualRelative) == "string" and actualRelative == relativeName
end

local function ParentMatches(object, parent, parentName)
  if not object or type(object.GetParent) ~= "function" then return false end
  local ok, actualParent = pcall(object.GetParent, object)
  if not ok then return false end
  if actualParent == parent then return true end
  return type(actualParent) == "string" and actualParent == parentName
end

local function CreatePageTexture(frame, spec)
  if not frame or type(frame.CreateTexture) ~= "function" then return nil end
  local ok, texture = pcall(frame.CreateTexture, frame, nil, "ARTWORK")
  if not ok or not texture or type(texture.SetTexture) ~= "function" then
    return nil
  end
  if not pcall(texture.SetTexture, texture, M.classicWow.path .. spec.file) then
    return nil
  end
  SetSize(texture, spec.width, spec.height)
  if type(texture.ClearAllPoints) == "function" then
    pcall(texture.ClearAllPoints, texture)
  end
  if type(texture.SetPoint) ~= "function"
     or not pcall(texture.SetPoint, texture, spec.point, frame, spec.point,
                  spec.x, spec.y) then
    return nil
  end
  return texture
end

-- ---------------------------------------------------------------------------
-- Reward money tail
--
-- The native reward template numbers guaranteed items after the choice items,
-- but restarts their two-column layout below QuestLogItemReceiveText. The
-- money tail therefore follows the LEFT item of the final guaranteed-reward
-- row, not simply the last numbered item, which may sit in the right column.
-- ---------------------------------------------------------------------------
local function MoneyAnchor(rewardText)
  local choices = 0
  local rewards = 0
  local getChoices = G("GetNumQuestLogChoices")
  local getRewards = G("GetNumQuestLogRewards")
  if type(getChoices) == "function" then
    local ok, value = pcall(getChoices)
    if ok and type(value) == "number" then choices = value end
  end
  if type(getRewards) == "function" then
    local ok, value = pcall(getRewards)
    if ok and type(value) == "number" then rewards = value end
  end

  if rewards > 0 then
    local finalRowReward = rewards
    if math.floor(finalRowReward / 2) * 2 == finalRowReward then
      finalRowReward = finalRowReward - 1
    end
    local itemName = "QuestLogItem" .. tostring(choices + finalRowReward)
    local item = G(itemName)
    if item then return item, itemName end
  end
  return rewardText, "QuestLogItemReceiveText"
end

local function AttachMoney(money, label, scrollChild, point, relativePoint, x, y)
  if not money or not label or not scrollChild
     or type(money.SetParent) ~= "function" then
    return false
  end
  if not pcall(money.SetParent, money, scrollChild) then return false end
  return SetAnchor(money, point, label, relativePoint, x or 0, y or 0)
end

-- ---------------------------------------------------------------------------
-- Rows
--
-- The row pitch is measured, never assumed, and each row takes its own offset
-- from the frame instead of being chained onto the row above it.
-- knowledge.json / questlog.eql3_chained_rows_leave_the_page is
-- RUNTIME_FAILURE_CONFIRMED: EQL3's chained 27 rows only land where a row
-- template is Vanilla's 16 pixels, and on this client the tail of a long quest
-- list drew over the footer buttons and off the parchment. An absolute offset
-- per row cannot accumulate an error, and the count is measured against the
-- page, so the block ends inside the list pane whatever a row measures.
-- ---------------------------------------------------------------------------
local function RowPitch(firstRow)
  local layout = M.classicWow.layout
  local height
  if firstRow and type(firstRow.GetHeight) == "function" then
    local ok, measured = pcall(firstRow.GetHeight, firstRow)
    if ok and type(measured) == "number"
       and measured >= layout.minRowHeight and measured <= layout.maxRowHeight then
      height = measured
    end
  end
  if not height then
    -- QUESTLOG_QUEST_HEIGHT is what the native QuestLog_Update feeds to
    -- FauxScrollFrame_Update as the scroll step, so it is the client's own
    -- idea of a row.
    local stock = G("QUESTLOG_QUEST_HEIGHT")
    if type(stock) == "number"
       and stock >= layout.minRowHeight and stock <= layout.maxRowHeight then
      height = stock
    end
  end
  return height or layout.defaultRowHeight
end

-- How many rows the left page holds without the tail spilling past the list
-- pane onto the footer buttons. Everything beyond this count is what the
-- native FauxScrollFrame scrolls: QuestLog_Update reads QUESTS_DISPLAYED for
-- both, so the drawn block and the scroll extent stay the same number.
local function RowCount(pitch)
  local layout = M.classicWow.layout
  local available = layout.listTop + layout.listHeight - layout.rowTop
  local rows = math.floor(available / pitch)
  if rows > layout.maxRows then rows = layout.maxRows end
  if rows < layout.minRows then rows = layout.minRows end
  return rows
end

local function BuildRows(frame, firstRow)
  local layout = M.classicWow.layout
  local pitch = RowPitch(firstRow)
  local rows = RowCount(pitch)

  -- WORKING_SOURCE, and the same technique modules/questlog.lua already uses
  -- under the Modern theme: this client accepts additional named
  -- QuestLogTitleButtonTemplate rows and the native QuestLog_Update fills them
  -- once QUESTS_DISPLAYED is raised.
  local i
  for i = 1, rows do
    local name = "QuestLogTitle" .. tostring(i)
    local row = G(name)
    if not row then
      local ok, created = pcall(CreateFrame, "Button", name, frame,
                                "QuestLogTitleButtonTemplate")
      if ok and created then
        row = created
        if type(row.Hide) == "function" then pcall(row.Hide, row) end
      end
    end
    if not row then return nil end
    if type(row.SetID) == "function" then pcall(row.SetID, row, i) end
    if not SetAnchor(row, "TOPLEFT", frame, "TOPLEFT", layout.rowLeft,
                     -(layout.rowTop + (i - 1) * pitch)) then
      return nil
    end
  end

  state.pitch = pitch
  return rows
end

local function LayoutFooter(frame)
  -- The three stock quest actions in the parchment footer shown by the classic-wow
  -- reference: Abandon at the left, Share and Exit paired at the right. The
  -- 411/413-pixel scroll panes end 27 pixels above the frame bottom, so this
  -- 21-pixel row owns that reserved strip instead of covering quest rows or
  -- reward details.
  local abandon = G("QuestLogFrameAbandonButton")
  local push = G("QuestFramePushQuestButton")
  local exit = G("QuestFrameExitButton")

  if abandon then
    SetSize(abandon, 125, 21)
    SetAnchor(abandon, "BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 5)
  end
  if exit then
    SetSize(exit, nil, 21)
    SetAnchor(exit, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 5)
  end
  if push then
    SetSize(push, 123, 21)
    if exit then
      SetAnchor(push, "BOTTOMRIGHT", exit, "BOTTOMLEFT", -4, 0)
    else
      SetAnchor(push, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 5)
    end
  end
end

-- Returns nil while the native frame set is not available yet, false after a
-- concrete preparation failure, and true once the one-shot layout is live.
local function Apply()
  local frame = G("QuestLogFrame")
  local listScroll = G("QuestLogListScrollFrame")
  local detail = G("QuestLogDetailScrollFrame")
  local detailChild = G("QuestLogDetailScrollChildFrame")
  local firstRow = G("QuestLogTitle1")
  local rewardMoney = G("QuestLogMoneyFrame")
  local rewardText = G("QuestLogItemReceiveText")
  local rewardSpacer = G("QuestLogSpacerFrame")
  if not frame or not listScroll or not detail or not detailChild
     or not firstRow or not rewardMoney or not rewardText or not rewardSpacer then
    return nil
  end
  if frame.uuiExtendedQuestLog ~= nil then
    return frame.uuiExtendedQuestLog and true or false
  end

  -- One attempt only. A partially created Texture cannot be destroyed on this
  -- client, so retrying would stack another parchment set on every poll.
  frame.uuiExtendedQuestLog = false

  local layout = M.classicWow.layout
  local textures = {}
  local i
  for i = 1, table.getn(M.classicWow.page) do
    local texture = CreatePageTexture(frame, M.classicWow.page[i])
    if not texture then
      frame.uuiExtendedQuestLogTextures = textures
      return false
    end
    table.insert(textures, texture)
  end
  frame.uuiExtendedQuestLogTextures = textures

  SetSize(frame, layout.width, layout.height)
  SetSize(listScroll, layout.listWidth, layout.listHeight)
  SetSize(detail, layout.detailWidth, layout.detailHeight)
  SetSize(detailChild, layout.detailWidth, layout.detailHeight)

  local rewardAnchor = MoneyAnchor(rewardText)
  if not SetAnchor(listScroll, "TOPLEFT", frame, "TOPLEFT", 20, -layout.listTop)
     or not SetAnchor(detail, "TOPLEFT", frame, "TOPLEFT",
                      layout.detailLeft, -layout.detailTop)
     -- Keep the money on its own line after the full guaranteed-item block and
     -- make that complete line part of the scroll extent. UnrealQuest's probe
     -- questrewardlayout.live_geometry.v1 measured the inline parent and anchor
     -- working while the native spacer still ended too early: 7 of 12 live
     -- money states were clipped by the detail pane.
     or not AttachMoney(rewardMoney, rewardAnchor, detailChild,
                        "TOPLEFT", "BOTTOMLEFT", 0, -2)
     or not SetAnchor(rewardSpacer, "TOP", rewardMoney, "BOTTOM", 0, 0) then
    return false
  end

  local requiredMoney = G("QuestLogRequiredMoneyFrame")
  local requiredText = G("QuestLogRequiredMoneyText")
  if requiredMoney and requiredText then
    AttachMoney(requiredMoney, requiredText, detailChild, "LEFT", "RIGHT", 10, 0)
  end

  local rows = BuildRows(frame, firstRow)
  if not rows then return false end

  -- The stock FrameXML row-count global consumed by QuestLog_Update, not
  -- persisted state. It is also what the native FauxScrollFrame_Update call
  -- inside QuestLog_Update treats as the visible window, so the scroll bar
  -- appears exactly when the log outgrows the page.
  QUESTS_DISPLAYED = rows
  state.rows = rows

  local close = G("QuestLogFrameCloseButton")
  if close then
    SetAnchor(close, "TOPRIGHT", frame, "TOPRIGHT", -20, -8)
  end
  LayoutFooter(frame)

  local windows = G("UIPanelWindows")
  if windows and type(windows.QuestLogFrame) == "table" then
    windows.QuestLogFrame.area = "doublewide"
  end

  frame.uuiExtendedQuestLog = true

  local refresh = G("QuestLog_Update")
  if type(refresh) == "function" then pcall(refresh) end
  return true
end

-- The native detail refresh rewrites QuestLogSpacerFrame after every
-- selection, i.e. after this one-shot layout has run. Re-assert the measured
-- reward tail from the shared driver while the log is open. Stable anchors are
-- read-only here; only a native rewrite costs anything. The native refresh
-- itself is never replaced or invoked from this path.
local function RefreshRewards()
  local frame = G("QuestLogFrame")
  local detail = G("QuestLogDetailScrollFrame")
  local detailChild = G("QuestLogDetailScrollChildFrame")
  local rewardText = G("QuestLogItemReceiveText")
  local rewardMoney = G("QuestLogMoneyFrame")
  local rewardSpacer = G("QuestLogSpacerFrame")
  if not frame or frame.uuiExtendedQuestLog ~= true
     or not detail or not detailChild or not rewardText
     or not rewardMoney or not rewardSpacer
     or not IsShown(frame) or not IsShown(rewardText) or not IsShown(rewardMoney) then
    return false
  end

  local rewardAnchor, rewardAnchorName = MoneyAnchor(rewardText)
  if ParentMatches(rewardMoney, detailChild, "QuestLogDetailScrollChildFrame")
     and AnchorMatches(rewardMoney, "TOPLEFT", rewardAnchor, rewardAnchorName,
                       "BOTTOMLEFT")
     and AnchorMatches(rewardSpacer, "TOP", rewardMoney, "QuestLogMoneyFrame",
                       "BOTTOM") then
    return true
  end

  if not AttachMoney(rewardMoney, rewardAnchor, detailChild,
                     "TOPLEFT", "BOTTOMLEFT", 0, -2)
     or not SetAnchor(rewardSpacer, "TOP", rewardMoney, "BOTTOM", 0, 0) then
    return false
  end

  -- So the re-anchored money line is inside the scrollable area rather than
  -- clipped past its bottom.
  if type(detail.UpdateScrollChildRect) == "function" then
    pcall(detail.UpdateScrollChildRect, detail)
  end
  return true
end

local function Finish(applied)
  state.applied = applied and true or false
  U.UnregisterUpdate(POLL_ID)
  if not state.applied then
    state.mode = "failed"
    U.Error("questlogextended: the extended Quest Log layout could not be prepared")
    return
  end
  state.mode = "extended"
  U.RegisterUpdate(REWARD_ID, REWARD_INTERVAL, RefreshRewards)
end

function QLX:OnEnable()
  -- modules/questlog.lua owns the Quest Log under every non-native theme, and
  -- has already built its own two-pane surface by now. Nothing to add there.
  if not U.ThemeStyleUsesNativeChrome() then
    state.mode = "modern"
    return
  end

  local applied = Apply()
  if applied ~= nil then
    Finish(applied)
    return
  end

  state.mode = "waiting"
  U.RegisterUpdate(POLL_ID, POLL_INTERVAL, function(interval)
    state.waited = state.waited + (interval or POLL_INTERVAL)
    local result = Apply()
    if result ~= nil then
      Finish(result)
    elseif state.waited >= POLL_SECONDS then
      state.mode = "missing"
      state.applied = false
      U.UnregisterUpdate(POLL_ID)
      U.Debug("questlogextended: native Quest Log frames never became available")
    end
  end)
end
