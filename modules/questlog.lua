-- unrealUI :: modules/questlog.lua
--
-- pfUI-modern-inspired treatment of the native Quest Log. The native quest
-- data, row templates, scrolling, selection, tracking and action scripts stay
-- intact; unrealUI changes only artwork, typography and layout.

local U = UnrealUI
local M = U.media
local QL = U.RegisterModule("questlog")

local QUEST_ROWS = 23
local QUEST_ACCENT = { 0.25, 0.95, 0.75, 1 }
local QUEST_BRIGHT = { 0.92, 0.92, 0.92, 1 }
local QUEST_WHITE = { 1.00, 1.00, 1.00, 1 }

local config
local frame, detail, listScroll, detailPanel

local function G(name)
  return U.G(name)
end

local function IsShown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

local function StripDecorations(object)
  if not object then return end
  U.StripStockTextures(object)
end

local function SetQuestFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or M.color.text)
end

local function ApplyQuestFonts()
  SetQuestFont(G("QuestLogTitleText"), M.fontSize.large, QUEST_BRIGHT)
  SetQuestFont(G("QuestLogQuestCount"), M.fontSize.small, QUEST_ACCENT)
  SetQuestFont(G("QuestLogQuestTitle"), M.fontSize.large, QUEST_ACCENT)
  SetQuestFont(G("QuestLogObjectivesText"), nil, QUEST_WHITE)
  SetQuestFont(G("QuestLogQuestDescription"), nil, QUEST_WHITE)
  SetQuestFont(G("QuestLogDescriptionTitle"), M.fontSize.large, QUEST_ACCENT)
  SetQuestFont(G("QuestLogRewardTitleText"), M.fontSize.large, QUEST_ACCENT)
  SetQuestFont(G("QuestLogItemChooseText"), nil, QUEST_WHITE)
  SetQuestFont(G("QuestLogItemReceiveText"), nil, QUEST_WHITE)
  SetQuestFont(G("QuestLogRequiredMoneyText"), nil, QUEST_WHITE)
  SetQuestFont(G("QuestLogSpellLearnText"), nil, QUEST_WHITE)

  local i
  for i = 1, QUEST_ROWS do
    SetQuestFont(G("QuestLogTitle" .. i), M.fontSize.normal, QUEST_BRIGHT)
  end
  for i = 1, 10 do
    SetQuestFont(G("QuestLogObjective" .. i), nil, QUEST_WHITE)
    SetQuestFont(G("QuestLogItem" .. i .. "Name"), nil, QUEST_WHITE)
    SetQuestFont(G("QuestLogItem" .. i .. "Count"), M.fontSize.small, QUEST_WHITE)
  end
end

local function ReapplyNativeStrip()
  StripDecorations(frame)
  StripDecorations(detail)
  ApplyQuestFonts()
end

local function SetDetailVisible(show)
  if not frame or not detail then return end

  detail.uuiUserHidden = show and nil or true
  if show then
    pcall(detail.Show, detail)
    pcall(frame.SetWidth, frame, 676)
    local update = G("QuestLog_UpdateQuestDetails")
    if type(update) == "function" then pcall(update) end
  else
    pcall(detail.Hide, detail)
    pcall(frame.SetWidth, frame, 340)
  end

  local expand = G("UnrealUIQuestLogExpand")
  if expand then U.StyleStockArrowButton(expand, show and "left" or "right", 21) end
end

local function BuildQuestLevelToggle(collapseAll)
  if not collapseAll then return end

  local ok, toggle = pcall(CreateFrame, "CheckButton",
    "UnrealUIQuestLogLevels", frame, "UICheckButtonTemplate")
  if not ok or not toggle then return end

  toggle:SetPoint("LEFT", collapseAll, "RIGHT", 4, 1)
  toggle:SetChecked(config.showQuestLevels and true or nil)
  U.StyleStockCheckbox(toggle, 20)

  local text = G("UnrealUIQuestLogLevelsText")
  if text then
    text:SetText("Levels")
    SetQuestFont(text, M.fontSize.small, M.color.textDim)
  end

  toggle:SetScript("OnClick", function()
    config.showQuestLevels = not config.showQuestLevels
    toggle:SetChecked(config.showQuestLevels and true or nil)
    local update = G("QuestLog_Update")
    if type(update) == "function" then pcall(update) end
  end)
end

local function BuildRows()
  local first = G("QuestLogTitle1")
  if not first or not listScroll then return end

  pcall(function()
    first:ClearAllPoints()
    first:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, 0)
  end)

  local i
  for i = 7, QUEST_ROWS do
    local name = "QuestLogTitle" .. i
    local row = G(name)
    if not row then
      local ok, created = pcall(CreateFrame, "Button", name, frame,
                                "QuestLogTitleButtonTemplate")
      if ok then row = created end
    end

    local previous = G("QuestLogTitle" .. (i - 1))
    if row and previous then
      pcall(row.SetID, row, i)
      pcall(function()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 1)
      end)
    end
  end

  for i = 1, QUEST_ROWS do
    U.StyleStockCollapseButton(G("QuestLogTitle" .. i))
  end
end

local function UpdateRows()
  ReapplyNativeStrip()

  if detail and detail.uuiUserHidden then pcall(detail.Hide, detail) end

  local getCount = G("GetNumQuestLogEntries")
  local getTitle = G("GetQuestLogTitle")
  local offsetFn = G("FauxScrollFrame_GetOffset")
  if type(getCount) ~= "function" or type(getTitle) ~= "function" then return end

  local ok, numEntries = pcall(getCount)
  if not ok or not tonumber(numEntries) then return end

  local offset = 0
  if type(offsetFn) == "function" and listScroll then
    local offsetOk, value = pcall(offsetFn, listScroll)
    if offsetOk and tonumber(value) then offset = value end
  end

  local i
  for i = 1, QUEST_ROWS do
    local row = G("QuestLogTitle" .. i)
    local check = G("QuestLogTitle" .. i .. "Check")
    if row and check then
      pcall(function()
        check:ClearAllPoints()
        check:SetPoint("RIGHT", row, "LEFT", 24, 0)
      end)
    end

    if config.showQuestLevels and row then
      local questIndex = i + offset
      if questIndex <= numEntries then
        local titleOk, text, level, questTag, isHeader =
          pcall(getTitle, questIndex)
        if titleOk and not isHeader and type(text) == "string" then
          local shownLevel = tostring(level or "?") .. (questTag and "+" or "")
          pcall(row.SetText, row, " [" .. shownLevel .. "] " .. text)
        end
      end
    end
  end
end

local function StyleQuestItems()
  local maxItems = tonumber(G("MAX_NUM_ITEMS")) or 10
  local i
  for i = 1, maxItems do
    local name = "QuestLogItem" .. i
    local item = G(name)
    local icon = G(name .. "IconTexture")
    if item and not item.uuiQuestItemStyled then
      item.uuiQuestItemStyled = true

      local widthOk, width = pcall(item.GetWidth, item)
      if widthOk and tonumber(width) and width > 12 then
        pcall(item.SetWidth, item, width - 12)
      end

      U.StyleStockButton(item, { icon = icon, fitIcon = false })

      if icon then
        local heightOk, height = pcall(item.GetHeight, item)
        local iconSize = heightOk and tonumber(height) and math.max(height - 12, 16) or 32
        pcall(function()
          icon:ClearAllPoints()
          icon:SetWidth(iconSize)
          icon:SetHeight(iconSize)
          icon:SetPoint("LEFT", item, "LEFT", 6, 0)
          icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          icon:Show()
          icon:SetAlpha(1)
        end)
      end
    end
  end
end

-- The focused questwatch probe identified QuestWatchFrame as the native
-- tracked-objectives root.  Leave its native placement untouched until the
-- player moves it; unlike unrealUI-owned overlays, it has no fabricated
-- fallback position to restore.
local function RegisterQuestWatchMover()
  local watch = G("QuestWatchFrame")
  if not watch then
    U.Debug("questlog: QuestWatchFrame unavailable")
    return false
  end

  U.RegisterMover("questwatch.frame", watch, {
    label = "Quest Tracker",
  })
  return true
end

local function BuildFrame()
  frame = G("QuestLogFrame")
  detail = G("QuestLogDetailScrollFrame")
  listScroll = G("QuestLogListScrollFrame")
  if not frame or not detail or not listScroll then
    U.Debug("questlog: native frame unavailable")
    return false
  end

  RegisterQuestWatchMover()

  -- WORKING_SOURCE fallback from the installed UnrealPfUI skin. This client
  -- uses the Vanilla-shaped row tuple and supports the additional row pool.
  QUESTS_DISPLAYED = QUEST_ROWS
  MAX_WATCHABLE_QUESTS = 20

  pcall(frame.SetWidth, frame, 676)
  pcall(frame.SetHeight, frame, 440)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  StripDecorations(frame)
  U.CreateBackdrop(frame, { background = { 0.01, 0.01, 0.01, 0.78 } })

  local title = G("QuestLogTitleText")
  if title then
    pcall(function()
      title:ClearAllPoints()
      title:SetPoint("TOP", frame, "TOP", 0, -10)
    end)
  end
  U.StyleStockCloseButton(G("QuestLogFrameCloseButton"), frame, -6, -6)

  local count = G("QuestLogQuestCount")
  if count then
    pcall(function()
      count:ClearAllPoints()
      count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -30)
    end)
  end

  local emptyText = G("QuestLogNoQuestsText")
  if emptyText then
    pcall(function()
      emptyText:ClearAllPoints()
      emptyText:SetPoint("TOP", frame, "TOP", 0, -100)
    end)
  end

  local abandon = G("QuestLogFrameAbandonButton")
  local push = G("QuestFramePushQuestButton")
  local exit = G("QuestFrameExitButton")
  U.StyleStockButton(abandon)
  U.StyleStockButton(push)
  U.StyleStockButton(exit)
  if abandon then
    pcall(function()
      abandon:ClearAllPoints()
      abandon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
      abandon:SetWidth(98)
    end)
  end
  if push and abandon then
    pcall(function()
      push:ClearAllPoints()
      push:SetPoint("LEFT", abandon, "RIGHT", 5, 0)
      push:SetWidth(98)
    end)
  end
  if exit and push then
    pcall(function()
      exit:ClearAllPoints()
      exit:SetPoint("LEFT", push, "RIGHT", 5, 0)
      exit:SetWidth(99)
    end)
  end

  local expand = U.CreateButton(frame, {
    name = "UnrealUIQuestLogExpand",
    text = "",
    width = 21,
    height = 21,
    onClick = function() SetDetailVisible(not IsShown(detail)) end,
  })
  U.StyleStockArrowButton(expand, "left", 21)
  if exit then expand:SetPoint("LEFT", exit, "RIGHT", 5, 0) end

  -- detailPanel is parented to the window rather than to the ScrollFrame, so
  -- it has to track the pane's visibility explicitly or it would stay drawn in
  -- the collapsed layout.
  U.PostHookScript(detail, "OnHide", function()
    if detailPanel then pcall(detailPanel.Hide, detailPanel) end
    if frame and detail.uuiUserHidden then
      pcall(frame.SetWidth, frame, 340)
      U.StyleStockArrowButton(expand, "right", 21)
    end
  end)
  U.PostHookScript(detail, "OnShow", function()
    if detailPanel then pcall(detailPanel.Show, detailPanel) end
    if not detail.uuiUserHidden then
      pcall(frame.SetWidth, frame, 676)
      U.StyleStockArrowButton(expand, "left", 21)
    end
  end)

  local collapseAll = G("QuestLogCollapseAllButton")
  U.StripStockTextures(G("QuestLogExpandButtonFrame"))
  U.StyleStockCollapseButton(collapseAll, true)
  if collapseAll and G("QuestLogTitle1") then
    pcall(function()
      collapseAll:ClearAllPoints()
      collapseAll:SetPoint("BOTTOMLEFT", G("QuestLogTitle1"), "TOPLEFT", -6, 4)
    end)
  end
  BuildQuestLevelToggle(collapseAll)

  U.StripStockTextures(listScroll)
  U.StyleStockScrollbar(G("QuestLogListScrollFrameScrollBar"))
  pcall(function()
    listScroll:ClearAllPoints()
    listScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -54)
    listScroll:SetHeight(350)
  end)

  local levelOk, level = pcall(frame.GetFrameLevel, frame)

  -- Both scroll panes get their panel as a separate frame rather than a
  -- backdrop on the ScrollFrame itself, so it can extend the extra 26 units
  -- right and put the scrollbar gutter inside the dark panel instead of
  -- leaving it floating on the window background.
  local listPanel = U.CreatePanel(frame, {
    name = "UnrealUIQuestLogListPanel",
    background = { 0.01, 0.01, 0.01, 0.74 },
  })
  listPanel:SetPoint("TOPLEFT", listScroll, "TOPLEFT", -5, 5)
  listPanel:SetPoint("BOTTOMRIGHT", listScroll, "BOTTOMRIGHT", 26, -5)
  pcall(listPanel.EnableMouse, listPanel, false)
  if levelOk and tonumber(level) then pcall(listPanel.SetFrameLevel, listPanel, level) end

  U.StripStockTextures(detail)
  U.StyleStockScrollbar(G("QuestLogDetailScrollFrameScrollBar"))
  pcall(function()
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 35, 0)
    detail:SetHeight(376)
  end)
  local detailChild = G("QuestLogDetailScrollChildFrame")
  if detailChild then pcall(detailChild.SetHeight, detailChild, 376) end

  detailPanel = U.CreatePanel(frame, {
    name = "UnrealUIQuestLogDetailPanel",
    background = { 0.01, 0.01, 0.01, 0.74 },
  })
  detailPanel:SetPoint("TOPLEFT", detail, "TOPLEFT", -5, 5)
  detailPanel:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 26, -5)
  pcall(detailPanel.EnableMouse, detailPanel, false)
  if levelOk and tonumber(level) then pcall(detailPanel.SetFrameLevel, detailPanel, level) end
  if not IsShown(detail) then pcall(detailPanel.Hide, detailPanel) end

  local track = G("QuestLogTrack")
  local tracking = G("QuestLogTrackTracking")
  if track then
    U.StripStockTextures(track, { keep = tracking and { [tracking] = true } or {} })
    U.CreateBackdrop(track)
    pcall(track.SetWidth, track, 10)
    pcall(track.SetHeight, track, 10)
    if count then
      pcall(function()
        track:ClearAllPoints()
        track:SetPoint("RIGHT", count, "LEFT", -5, 0)
      end)
    end
  end
  if tracking then
    pcall(tracking.SetTexture, tracking, M.texture.plain)
    U.SetColor(tracking, 0.90, 0.05, 0.05, 1)
    pcall(tracking.SetAlpha, tracking, 1)
  end
  local trackTitle = G("QuestLogTrackTitle")
  if trackTitle then pcall(trackTitle.Hide, trackTitle) end

  BuildRows()
  StyleQuestItems()
  ApplyQuestFonts()

  U.PostHookGlobal("QuestLog_OnShow", function()
    pcall(function()
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -104)
    end)
    ReapplyNativeStrip()
  end)
  -- The native list update restores its own FontObjects after rendering rows.
  -- Reapply colours after that work so body text remains legible and headings
  -- retain their intended accent instead of falling back to native black.
  U.PostHookGlobal("QuestLog_Update", function()
    UpdateRows()
    ApplyQuestFonts()
  end)
  U.PostHookGlobal("QuestLog_UpdateQuestDetails", ApplyQuestFonts)

  local empty = G("EmptyQuestLogFrame")
  if empty then
    U.PostHookScript(empty, "OnShow", function()
      SetDetailVisible(false)
      pcall(expand.Disable, expand)
    end)
    U.PostHookScript(empty, "OnHide", function() pcall(expand.Enable, expand) end)
  end

  if IsShown(frame) then ReapplyNativeStrip() end
  return true
end

function QL:OnInit()
  config = U.ModuleConfig("questlog", { showQuestLevels = false })
end

function QL:OnEnable()
  BuildFrame()
end
