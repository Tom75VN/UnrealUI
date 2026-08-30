-- unrealUI :: modules/quest.lua
--
-- pfUI-modern-inspired treatment of the native NPC quest dialog (QuestFrame) --
-- the window that opens when you talk to a quest giver: the greeting list of
-- available/current quests, the quest detail with Accept/Decline, the progress
-- panel with required items, and the reward panel with Complete. Native quest
-- data, item slots and click behaviour stay intact; unrealUI changes only
-- artwork, typography and layout, matching the Character/Quest Log/Gossip
-- treatment.
--
-- USER_CONFIRMED_INGAME: talking to a quest giver still showed the completely
-- native parchment window after modules/gossip.lua was in place. GossipFrame
-- and QuestFrame are two different stock windows -- an NPC with no gossip
-- options opens QuestFrame's greeting panel directly -- and unrealUI skinned
-- only the former, so the whole quest-giver flow had no coverage at all. This
-- module is that missing half; it deliberately mirrors modules/gossip.lua's
-- shape so the two NPC dialogs read as one window.
--
-- WORKING_SOURCE, not runtime-verified on this client: query_compat.py has no
-- record at all for QuestFrame or any of its children (documentation.json
-- covers only the Quest Lua API, not the frame's widget hierarchy), so every
-- region name below is taken from UnrealPfUI's skins\blizzard\gossipquest.lua
-- as a same-client working implementation rather than confirmed evidence.
-- Verify in game and fold any surprises into knowledge.json.
--
-- Unlike UnrealPfUI (which hides the NPC portrait entirely), the portrait is
-- kept and cropped like modules/gossip.lua's header -- rules/unreal-ui-
-- design.md classifies portraits as meaningful content imagery to preserve,
-- not decorative chrome to strip.

local U = UnrealUI
local M = U.media
local QF = U.RegisterModule("quest")

-- Requested: every string in the NPC quest dialog reads as plain white --
-- including the NPC name, which is NOT given the accent heading colour other
-- stock windows use for their title. Same explicit request already recorded in
-- modules/trainer.lua's ReapplyHeaderText, and the same pure-white value
-- modules/questlog.lua uses (QUEST_WHITE), deliberately not M.color.text: that
-- token is 0.90 grey and reads dim against this window's dark panel.
local WHITE = { 1.00, 1.00, 1.00, 1 }
-- RUNTIME_PROBE questgreetingicon measured a 14px QuestTitleButton height.
-- Keep a 1px vertical margin on both sides so adjacent quest glyphs never
-- overlap even when two rows are packed directly together.
local QUEST_ROW_ICON_HEIGHT = 10.8
local QUEST_ROW_ICON_WIDTH = QUEST_ROW_ICON_HEIGHT * 19 / 32
local QUEST_ROW_ICON_SLOT_WIDTH = 16
local QUEST_ROW_TEXTURES = {
  available = "Interface\\AddOns\\unrealUI\\media\\QuestIcon",
  active = "Interface\\AddOns\\unrealUI\\media\\ActiveQuestIcon",
  complete = "Interface\\AddOns\\unrealUI\\media\\CompleteQuestIcon",
}

local frame, panel

local function G(name)
  return U.G(name)
end

local function SetQuestFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function Reposition(object, point, relativeTo, relativePoint, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, relativeTo, relativePoint, x, y)
  end)
end

-- Full stock-font pass, not a bare recolour: this window's strings carry a
-- native FontObject whose gold decorative book face otherwise survives
-- SetTextColor. See U.ForceStockTextWhite in core/stockui.lua.
local function ForceWhiteText(object)
  U.ForceStockTextWhite(object, WHITE, M.fontSize.normal)
end

-- Match questlog.lua's reliable path: address the known stock content strings
-- by name as well as walking the frame. The Detail/Reward-prefixed names were
-- captured by the live /uui questtext diagnostic on this client; the shorter
-- compatibility peers remain guarded for other panels/builds.
local QUEST_TEXT = {
  "GreetingText",
  "AvailableQuestsText",
  "QuestGreetingText",
  "QuestTitleText",
  "QuestObjectivesText",
  "QuestObjectiveText",
  "QuestDescription",
  "QuestRewardText",
  "QuestItemChooseText",
  "QuestItemReceiveText",
  "QuestDetailItemChooseText",
  "QuestDetailItemReceiveText",
  "QuestRewardItemChooseText",
  "QuestRewardItemReceiveText",
  "QuestRequiredMoneyText",
  "QuestSpellLearnText",
  "QuestDetailSpellLearnText",
  "QuestRewardSpellLearnText",
  "QuestProgressTitleText",
  "QuestProgressText",
  "QuestProgressRequiredItemsText",
  "QuestRewardTitleText",
}

local function ApplyNamedWhiteText()
  local i
  for i = 1, table.getn(QUEST_TEXT) do
    SetQuestFont(G(QUEST_TEXT[i]), M.fontSize.normal, WHITE)
  end
end

-- These exact detail/reward heading names were identified by the live /uui
-- questtext dump. They are short section headings, so use the shared normal
-- font and accent colour only after the blanket white pass.
local function ApplySectionHeadingColors()
  SetQuestFont(G("AvailableQuestsText"), M.fontSize.normal, M.color.accent)
  SetQuestFont(G("CurrentQuestsText"), M.fontSize.normal, M.color.accent)
  SetQuestFont(G("QuestDetailObjectiveTitleText"), M.fontSize.normal,
               M.color.accent)
  SetQuestFont(G("QuestDetailRewardTitleText"), M.fontSize.normal,
               M.color.accent)
  SetQuestFont(G("QuestRewardRewardTitleText"), M.fontSize.normal,
               M.color.accent)
end

-- The four content panels the stock window swaps between. Only one is shown at
-- a time, but all four carry their own parchment art and their own scroll
-- frame, so each needs the same pass.
local PANELS = { "Greeting", "Detail", "Progress", "Reward" }

-- Bottom-row action buttons. Listed explicitly rather than discovered, because
-- these are the only children of QuestFrame that should keep a button surface;
-- everything else stock draws here is chrome.
local BUTTONS = {
  "QuestFrameGreetingGoodbyeButton",
  "QuestFrameDeclineButton",
  "QuestFrameAcceptButton",
  "QuestFrameGoodbyeButton",
  "QuestFrameCompleteButton",
  "QuestFrameCancelButton",
  "QuestFrameCompleteQuestButton",
}

-- The live /uui questtext dump exposed QuestRewardItem1..9 on this client.
-- The per-slot G() guard no-ops for panels that instantiate fewer.
local ITEM_PREFIXES = { "QuestProgressItem", "QuestDetailItem", "QuestRewardItem" }
local ITEMS_PER_PANEL = 9

-- The native quest button owns tooltip population and stores the corresponding
-- GetQuestItemLink list in button.type, with its 1-based item index in GetID().
-- Append the price only after that native OnEnter has run, exactly like
-- core/itemslot.lua does for bag buttons. The resolved link also drives that
-- same module's equipped-item comparison tooltips. Progress/required items are
-- intentionally excluded: these readouts are for rewards the player is
-- evaluating.
--
-- This is behavior only -- no texture, font or anchor is touched -- so the
-- Classic theme installs the same hooks on the untouched native frame without
-- pulling in any of the skinning below.
local function HookRewardTooltip(button, prefix)
  if not button or prefix == "QuestProgressItem" then return end
  if button.uuiQuestPriceHooks then return end
  button.uuiQuestPriceHooks = true

  U.PostHookScript(button, "OnEnter", function()
    local idOk, index = false, nil
    if button.GetID then idOk, index = pcall(button.GetID, button) end
    if not idOk then return end

    local link
    if type(U.ShowQuestItemPrice) == "function" then
      link = U.ShowQuestItemPrice(button.type, index)
    end
    -- The same resolved link carries the reward's rarity onto the tooltip's
    -- name line. A reward that only resolved through the name fallback simply
    -- leaves the native colour alone.
    if type(U.ColorTooltipItemName) == "function" then
      U.ColorTooltipItemName(link)
    end
    if type(U.ShowItemCompare) == "function" then
      U.ShowItemCompare(link)
    end
  end)
  U.PostHookScript(button, "OnLeave", function()
    if type(U.ClearTooltipItemName) == "function" then
      U.ClearTooltipItemName()
    end
    if type(U.HideItemPrice) == "function" then U.HideItemPrice() end
    if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  end)
end

-- Classic keeps the client's own quest frame, so the reward readouts are all
-- that gets added. Re-run on every quest event because the client populates
-- and reuses these buttons per panel; HookRewardTooltip is idempotent, so a
-- button already carrying the hooks is skipped.
local function HookQuestRewards()
  local p
  for p = 1, table.getn(ITEM_PREFIXES) do
    local i
    for i = 1, ITEMS_PER_PANEL do
      HookRewardTooltip(G(ITEM_PREFIXES[p] .. i), ITEM_PREFIXES[p])
    end
  end
end

-- The parchment fill is a set of Material* textures owned by each panel, and
-- knowledge.json / frames.stock_singletons_structure_nonvanilla records that
-- stock singletons recreate artwork when they are shown. UnrealPfUI had to
-- neuter those textures' Show methods outright; unrealUI instead re-runs the
-- strip from every panel's OnShow and from the native item-update hooks, which
-- is the same reapply path modules/questlog.lua already uses and avoids
-- overwriting a real client method.
local function StripPanels()
  local i
  for i = 1, table.getn(PANELS) do
    local name = PANELS[i]
    U.StripStockTextures(G("QuestFrame" .. name .. "Panel"))
    U.StripStockTextures(G("Quest" .. name .. "ScrollFrame"))
    U.StripStockTextures(G("Quest" .. name .. "ScrollChildFrame"))
  end
end

-- Imported from UnrealQuest by request. All three files are 19x32, so preserve
-- that ratio instead of stretching them into square native icon slots.
--
-- QuestFrame's active list contains both incomplete and completable quests.
-- The same-client FrameXML contract may return completion as GetActiveTitle's
-- second result. Official client documentation only records the title result,
-- so the quest-log completion flag is the evidence-backed fallback.
local function ActiveQuestIsComplete(button)
  local id
  if button and button.GetID then
    local idOk, value = pcall(button.GetID, button)
    if idOk then id = tonumber(value) end
  end
  if not id then return false end

  local activeTitle
  local getActiveTitle = G("GetActiveTitle")
  if type(getActiveTitle) == "function" then
    local titleOk, title, isComplete = pcall(getActiveTitle, id)
    if titleOk then
      activeTitle = title
      if isComplete ~= nil then
        return isComplete == 1 or isComplete == true
      end
    end
  end

  local getCount = G("GetNumQuestLogEntries")
  local getLogTitle = G("GetQuestLogTitle")
  if type(activeTitle) ~= "string" or activeTitle == "" or
     type(getCount) ~= "function" or type(getLogTitle) ~= "function" then
    return false
  end

  local countOk, count = pcall(getCount)
  if not countOk or not tonumber(count) then return false end

  local index
  for index = 1, count do
    -- UnrealQuest Compatibility/ClientAPI.lua records this client's verified
    -- six-value tuple as title, level, tag, isHeader, isCollapsed, isComplete.
    -- Reading a seventh `group` value shifted both flags and made every active
    -- quest appear incomplete.
    local titleOk, title, level, tag, isHeader, isCollapsed, isComplete =
      pcall(getLogTitle, index)
    if titleOk and not isHeader and title == activeTitle then
      return isComplete == 1 or isComplete == true
    end
  end
  return false
end

local function NativeQuestRowState(nativeIcon)
  if not nativeIcon or not nativeIcon.GetTexture then return nil end
  local textureOk, texture = pcall(nativeIcon.GetTexture, nativeIcon)
  if not textureOk or type(texture) ~= "string" then return nil end

  texture = string.lower(texture)
  if string.find(texture, "completequesticon", 1, true) then return "complete" end
  if string.find(texture, "incompletequesticon", 1, true) or
     string.find(texture, "activequesticon", 1, true) then return "active" end
  if string.find(texture, "availablequesticon", 1, true) then
    return "available"
  end
  return nil
end

local function QuestRowText(button, fontstring)
  local source = fontstring
  if not source or not source.GetText then source = button end
  if not source or not source.GetText then return nil end

  local textOk, text = pcall(source.GetText, source)
  if textOk and type(text) == "string" and text ~= "" then return text end
  return nil
end

-- RUNTIME_PROBE questgreetingicon.production_state.v1 (2026-08-29): every
-- visible QuestTitleButton has `type == nil`, and its only stock texture is the
-- generic UI-Quest-BulletPoint. Neither therefore carries active/available
-- state on this client. The button ID *does* index GetActiveTitle and
-- GetAvailableTitle, and the returned title identifies which section owns the
-- row even though both sections restart their IDs at one.
local function QuestRowState(button, nativeIcon, fontstring)
  local id
  if button and button.GetID then
    local idOk, value = pcall(button.GetID, button)
    if idOk then id = tonumber(value) end
  end

  local title = QuestRowText(button, fontstring)
  if id and title then
    local getActive = G("GetActiveTitle")
    if type(getActive) == "function" then
      local activeOk, activeTitle = pcall(getActive, id)
      if activeOk and activeTitle == title then
        return ActiveQuestIsComplete(button) and "complete" or "active"
      end
    end

    local getAvailable = G("GetAvailableTitle")
    if type(getAvailable) == "function" then
      local availableOk, availableTitle = pcall(getAvailable, id)
      if availableOk and availableTitle == title then return "available" end
    end
  end

  local rowType = type(button.type) == "string" and
                  string.lower(button.type) or nil
  if rowType == "available" then return "available" end
  if rowType == "active" then
    return ActiveQuestIsComplete(button) and "complete" or "active"
  end
  return NativeQuestRowState(nativeIcon)
end

local function StyleQuestRowIcon(button, nativeIcon, fontstring)
  if not button then return nil end

  local state = QuestRowState(button, nativeIcon, fontstring)

  local icon = button.uuiQuestStateIcon
  local shown = true
  if button.IsShown then
    local shownOk, value = pcall(button.IsShown, button)
    if shownOk then shown = value and true or false end
  end
  if not shown or not QUEST_ROW_TEXTURES[state] then
    if icon then pcall(icon.Hide, icon) end
    return icon
  end

  if not icon and button.CreateTexture then
    local createOk, created = pcall(button.CreateTexture, button, nil, "BACKGROUND")
    if createOk then
      icon = created
      button.uuiQuestStateIcon = icon
    end
  end
  if not icon then return nil end

  pcall(function()
    icon:SetTexture(QUEST_ROW_TEXTURES[state])
    icon:SetVertexColor(1, 1, 1)
    icon:SetAlpha(1)
    icon:ClearAllPoints()
    icon:SetWidth(QUEST_ROW_ICON_WIDTH)
    icon:SetHeight(QUEST_ROW_ICON_HEIGHT)
    -- Centre the portrait glyph within the native 16px-wide inset and the
    -- button's measured 14px line height.
    icon:SetPoint("LEFT", button, "LEFT",
      (QUEST_ROW_ICON_SLOT_WIDTH - QUEST_ROW_ICON_WIDTH) / 2, 0)
    icon:Show()
  end)
  return icon
end

-- Quest rows on the greeting panel (QuestTitleButton1..N) are plain clickable
-- text/icon rows, not stock chrome buttons. Keep the stock buttons and click
-- handlers, but use the imported UnrealQuest assets for their state glyphs.
local function StyleTitleRows()
  -- No compact-DB record for how many QuestTitleButton rows FrameXML ever
  -- instantiates. Same convention as modules/gossip.lua's NUMGOSSIPBUTTONS
  -- fallback: try the documented constant, fall back to a safe upper bound.
  local rows = tonumber(G("MAX_NUM_QUESTS")) or 32
  local i
  for i = 1, rows do
    local button = G("QuestTitleButton" .. i)
    if button then
      local fontOk, fontstring = false, nil
      if button.GetFontString then
        fontOk, fontstring = pcall(button.GetFontString, button)
      end

      -- Strip first, including an icon left from an earlier population pass.
      -- RUNTIME_PROBE questgreetingicon.production_state.v1 measured that a
      -- keep-table strip performed after styling still left all three owned
      -- textures hidden with alpha zero on this client. Reapplying the owned
      -- texture last is the verified region-suppression recovery sequence.
      U.StripStockTextures(button)
      local nativeIcon = G("QuestTitleButton" .. i .. "QuestIcon")
      StyleQuestRowIcon(button, nativeIcon, fontOk and fontstring or nil)

      if fontOk and fontstring then
        SetQuestFont(fontstring, M.fontSize.normal, WHITE)
      end

      -- Quest rows are buttons, so the native hover state can restore the
      -- button label's black normal font after the frame-wide FontString pass.
      -- Keep the button state itself white too, and run again after its native
      -- enter/leave scripts just as the NPC gossip rows do.
      local function ForceRowWhite()
        if button.SetTextColor then
          pcall(button.SetTextColor, button, 1, 1, 1)
        end
        if button.GetFontString then
          local rowFontOk, rowFontstring = pcall(button.GetFontString, button)
          if rowFontOk and rowFontstring then
            SetQuestFont(rowFontstring, M.fontSize.normal, WHITE)
          end
        end
      end
      ForceRowWhite()
      if not button.uuiQuestWhiteTextHooks then
        button.uuiQuestWhiteTextHooks = true
        U.PostHookScript(button, "OnEnter", ForceRowWhite)
        U.PostHookScript(button, "OnLeave", ForceRowWhite)
      end
    end
  end
end

-- The client marks the chosen reward with QuestRewardItemHighlight, a stock
-- gold UI-QuestItemHighlight box sized for the untouched native reward row
-- (WORKING_SOURCE: UnrealPfUI's skins/blizzard/gossipquest.lua replaces the
-- same frame on this client). It is a second style family on top of unrealUI's
-- flat rows, and its fixed size no longer matches the Quest Log cell geometry
-- used below, so the modern themes strip that artwork and express the selected
-- state with the reward row's own accent outline and accent fill instead --
-- the selected state rules/unreal-ui-design.md defines.
--
-- The selection is stored as the row's 1-based index, not as a frame
-- reference, and is cleared only by the quest events that mean the window now
-- holds different content. The earlier shape read the stock highlight frame's
-- visibility on every restyle pass and dropped the selection whenever that
-- read failed -- one absent frame, or one native rebuild between the click and
-- the next pass, silently returned every row to the plain border.
local REWARD_BACKGROUND = { 0.03, 0.03, 0.03, 0.82 }
local selectedRewardIndex
local hoveredReward

local function StripRewardHighlight()
  local highlight = G("QuestRewardItemHighlight")
  if not highlight then return end

  U.StripStockTextures(highlight)
  if not highlight.uuiQuestHighlightHooks then
    highlight.uuiQuestHighlightHooks = true
    U.PostHookScript(highlight, "OnShow", function()
      U.StripStockTextures(highlight)
    end)
  end
end

local function RewardIndex(button, fallback)
  if button and button.GetID then
    local ok, id = pcall(button.GetID, button)
    if ok and tonumber(id) then return tonumber(id) end
  end
  return fallback
end

-- Only a choose-one row can be selected; a guaranteed reward is not a choice
-- and must never take the accent.
--
-- USER_CONFIRMED_INGAME (knowledge.json
-- quest.reward_item_link_nil_after_tooltip_population): a reward button on
-- this client carries type == "choice" with its 1-based index in GetID(), the
-- same pair HookRewardTooltip already relies on. GetNumQuestChoices is the
-- documented fallback for a build that leaves the tag unset: the client fills
-- the reward buttons with the choose-one items first, so anything within that
-- count is a choice row.
local function IsChoiceButton(button, fallbackIndex)
  if not button then return false end
  if button.type == "choice" then return true end
  if button.type then return false end

  if type(GetNumQuestChoices) ~= "function" then return false end
  local index = RewardIndex(button, fallbackIndex)
  local ok, choices = pcall(GetNumQuestChoices)
  if not ok or not tonumber(choices) or not tonumber(index) then return false end
  return choices > 0 and index <= choices
end

-- Both reward row states are painted from one place, because hover and
-- selection share one outline. Hover is the subdued accent; the picked reward
-- takes the full accent outline plus the accent fill, so the two stay
-- distinguishable while the mouse is still on the row it just selected.
local function ApplyRewardStates()
  local i
  for i = 1, ITEMS_PER_PANEL do
    local button = G("QuestRewardItem" .. i)
    -- uuiEdges is the outline U.StyleStockButton installed; a button that has
    -- not been through that pass yet has nothing to recolour.
    if button and button.uuiEdges then
      if selectedRewardIndex and RewardIndex(button, i) == selectedRewardIndex
         and IsChoiceButton(button, i) then
        U.SetBorderColor(button, M.Unpack(M.color.accent))
        U.SetBackgroundColor(button, M.Unpack(M.color.accentFill))
      elseif button == hoveredReward then
        U.SetBorderColor(button, M.Unpack(M.color.accentDim))
        U.SetBackgroundColor(button, M.Unpack(REWARD_BACKGROUND))
      else
        U.SetBorderColor(button, M.Unpack(M.color.border))
        U.SetBackgroundColor(button, M.Unpack(REWARD_BACKGROUND))
      end
    end
  end
end

local function SelectReward(button, fallbackIndex)
  if not IsChoiceButton(button, fallbackIndex) then return end
  selectedRewardIndex = RewardIndex(button, fallbackIndex)
  ApplyRewardStates()
end

-- The selection belongs to one open quest window, so it is dropped when that
-- window's content changes and never on a restyle pass, which runs far more
-- often. MEASURED_RUNTIME (knowledge.json
-- questlog.turnin_event_sequence_measured): QUEST_COMPLETE fires as the
-- completion dialog opens and QUEST_FINISHED when it closes, so both ends of a
-- turn-in are covered by the quest events this module already listens for.
local function ClearRewardSelection()
  selectedRewardIndex = nil
  hoveredReward = nil
  ApplyRewardStates()
end

-- Self-healing script hook, deliberately not U.PostHookScript.
--
-- U.PostHookScript wraps once and the caller guards with a flag on the button,
-- so a native reward rebuild that reassigns these buttons' scripts drops the
-- unrealUI handler for the rest of the session with no error and no way to
-- notice. That is the shape of "the hover state simply stopped existing".
-- Storing the installed wrapper lets every styling pass compare it against the
-- live script and re-wrap whatever the client has put there now.
--
-- UNVERIFIED: nothing in the compact evidence records whether this client's
-- quest code reassigns reward-button scripts. This is written to be correct
-- either way -- when the script is still ours the pass is a single comparison.
local function HookRewardScript(button, script, callback)
  local field = "uuiQuestHook" .. script
  local liveOk, live = pcall(button.GetScript, button, script)
  if liveOk and live and live == button[field] then return end

  local previous = liveOk and live or nil
  local wrapper = function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
    if previous then previous(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
    callback(a1, a2, a3, a4, a5, a6, a7, a8, a9)
  end

  if pcall(button.SetScript, button, script, wrapper) then
    button[field] = wrapper
  end
end

local function HookRewardSelection(button, prefix)
  if not button or prefix ~= "QuestRewardItem" then return end
  if not button.GetScript or not button.SetScript then return end

  -- The reward row owns its own hover state rather than leaving it to
  -- U.StyleStockButton's hooks: this runs at the end of the chain in both
  -- directions, so leaving a row cannot clear the accent on the selected one
  -- and a native rebuild cannot silently take the hover with it.
  HookRewardScript(button, "OnEnter", function()
    hoveredReward = button
    ApplyRewardStates()
  end)

  HookRewardScript(button, "OnLeave", function()
    if hoveredReward == button then hoveredReward = nil end
    ApplyRewardStates()
  end)

  HookRewardScript(button, "OnClick", function()
    -- The native handler has already run, so the row now carries whatever the
    -- client decided about this click.
    SelectReward(button)
  end)
end

-- Second, independent click path.
--
-- WORKING_SOURCE (UnrealPfUI skins/blizzard/gossipquest.lua): this client
-- routes reward clicks through a global QuestRewardItem_OnClick, which is how
-- that skin drives its own selection box. Hooking the global as well as the
-- rows' own OnClick covers a build whose buttons carry no OnClick script of
-- their own, and a native rebuild that reassigns them between styling passes.
-- U.PostHookGlobal fails closed when the function is absent, so this costs
-- nothing where the per-button hook is already the live path.
--
-- The clicked row arrives either as the first argument or in the legacy `this`
-- global; knowledge.json scripts.handler_arguments_direct records that this
-- client uses both shapes depending on the handler, so both are resolved
-- rather than one being assumed.
local function RewardClicked(a1)
  local button = a1
  if type(button) ~= "table" then button = U.G("this") end
  if type(button) ~= "table" then return end

  local i
  for i = 1, ITEMS_PER_PANEL do
    if G("QuestRewardItem" .. i) == button then
      SelectReward(button, i)
      return
    end
  end
end

-- Reward/progress/detail item slots use the Quest Log item-cell treatment
-- directly.  Do not maintain a second card layout here: it let the native
-- accept-panel refresh leave reward icons on top of one another.
local function StyleItemSlots()
  StripRewardHighlight()
  hoveredReward = nil

  local p
  for p = 1, table.getn(ITEM_PREFIXES) do
    local rowStart
    local nextIsRight = false
    local i
    for i = 1, ITEMS_PER_PANEL do
      local name = ITEM_PREFIXES[p] .. i
      local button = G(name)
      if button then
        local icon = G(name .. "IconTexture")
        local itemName = G(name .. "Name")
        local count = G(name .. "Count")
        local hasItem = false
        if itemName and itemName.GetText then
          local textOk, text = pcall(itemName.GetText, itemName)
          hasItem = textOk and type(text) == "string" and text ~= ""
        end

        U.RefreshStockButtonArtwork(button, icon)

        -- A card from an earlier version can still live on an existing stock
        -- frame after /reload.  It must stay hidden so this exact Quest Log
        -- treatment is the only reward surface shown.
        local oldCard = button.uuiQuestRewardCard
        if oldCard and oldCard.Hide then pcall(oldCard.Hide, oldCard) end

        if not button.uuiQuestItemLayout then
          button.uuiQuestItemLayout = true
          -- Copy the actual Quest Log cell dimensions instead of assuming a
          -- quest-dialog container is already the same shape.
          local questLogItem = G("QuestLogItem1")
          local widthOk, width = false, nil
          local heightOk, height = false, nil
          if questLogItem then
            widthOk, width = pcall(questLogItem.GetWidth, questLogItem)
            heightOk, height = pcall(questLogItem.GetHeight, questLogItem)
          end
          if widthOk and tonumber(width) then
            pcall(button.SetWidth, button, width)
          else
            widthOk, width = pcall(button.GetWidth, button)
            if widthOk and tonumber(width) and width > 12 then
              pcall(button.SetWidth, button, width - 12)
            end
          end
          if heightOk and tonumber(height) then
            pcall(button.SetHeight, button, height)
          end
        end

        -- The stock accept panel is free to stack all of its wide item
        -- containers at one position.  Restore the Quest Log's compact,
        -- two-column item grid for the real entries.
        if hasItem then
          if not rowStart then
            rowStart = button
            nextIsRight = true
          elseif nextIsRight then
            Reposition(button, "TOPLEFT", rowStart, "TOPRIGHT", 4, 0)
            nextIsRight = false
          else
            Reposition(button, "TOPLEFT", rowStart, "BOTTOMLEFT", 0, -4)
            rowStart = button
            nextIsRight = true
          end
        end

        -- The background is named rather than defaulted because
        -- ApplyRewardStates has to put this exact fill back when a row stops
        -- being the selected one.
        U.StyleStockButton(button, { icon = icon, fitIcon = false,
                                     background = REWARD_BACKGROUND,
                                     hoverBorder = M.color.accentDim })

        HookRewardTooltip(button, ITEM_PREFIXES[p])
        HookRewardSelection(button, ITEM_PREFIXES[p])

        if icon then
          pcall(function()
            local heightOk, height = pcall(button.GetHeight, button)
            local iconSize = heightOk and tonumber(height) and
                             math.max(height - 12, 16) or 32
            icon:ClearAllPoints()
            icon:SetWidth(iconSize)
            icon:SetHeight(iconSize)
            icon:SetPoint("LEFT", button, "LEFT", 6, 0)
            icon:Show()
            icon:SetAlpha(1)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          end)
        end

        SetQuestFont(itemName, M.fontSize.normal, WHITE)
        SetQuestFont(count, M.fontSize.small, WHITE)

        -- These anchors are deliberately identical to StyleQuestItems in the
        -- Quest Log: the icon occupies the left inset, the name is constrained
        -- to the remaining cell, and the count stays on the icon.
        if itemName and icon then
          pcall(function()
            itemName:ClearAllPoints()
            itemName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
            itemName:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 4)
            itemName:SetJustifyH("LEFT")
            itemName:SetJustifyV("MIDDLE")
          end)
        end

        if count and icon then
          pcall(function()
            count:ClearAllPoints()
            count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
          end)
        end
      end
    end
  end

  ApplyRewardStates()
end

local function StyleHeader()
  local portrait = G("QuestFramePortrait")
  if portrait then
    pcall(portrait.SetTexCoord, portrait, 0.08, 0.92, 0.08, 0.92)
  end
end

-- Strings that keep the `large` size after the uniform white pass flattens
-- everything to `normal`. Colour is unchanged -- still the same white as the
-- rest of the window -- this only restores hierarchy, matching how
-- modules/questlog.lua sizes QuestLogQuestTitle/QuestLogTitleText.
--
-- QuestTitleText and QuestProgressTitleText are the two UnrealPfUI's
-- gossipquest.lua repositions on this client, so those names are WORKING_SOURCE.
-- QuestRewardTitleText is the unconfirmed sibling for the reward panel; the
-- G() guard makes it a no-op if this client does not have it.
local TITLES = {
  "QuestFrameNpcNameText",
  "QuestTitleText",
  "QuestProgressTitleText",
  "QuestRewardTitleText",
}

local function ApplyTitleSizes()
  local i
  for i = 1, table.getn(TITLES) do
    SetQuestFont(G(TITLES[i]), M.fontSize.large, WHITE)
  end
end

local function Reapply()
  U.StripStockTextures(frame)
  StripPanels()
  StyleHeader()
  ForceWhiteText(frame)
  ApplyNamedWhiteText()
  ApplyTitleSizes()
  ApplySectionHeadingColors()
  StyleTitleRows()
  StyleItemSlots()
end

-- Native quest handlers can continue assigning their FontObjects after panel
-- OnShow and event callbacks return. Apply immediately for stable panels, then
-- once more on the next verified shared-driver tick so the measured named
-- strings win after the native refresh has fully settled.
local function ReapplyAfterNative()
  Reapply()
  U.DeferOnce("quest-native-text-refresh", Reapply)
end

local function BuildFrame()
  frame = G("QuestFrame")
  if not frame then
    U.Debug("quest: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  -- Content backdrop inset from the real frame bounds, using the same insets as
  -- modules/gossip.lua so the quest-giver and gossip windows are the same size
  -- and shape: leaves the bottom strip clear for Accept/Decline/Goodbye instead
  -- of burying them inside the dark box.
  panel = U.CreatePanel(frame, {
    name = "UnrealUIQuestPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 8, 30, 10, 40)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  U.MakeWindowDraggable("quest", frame, { headerInset = 54 })

  StyleHeader()
  Reposition(G("QuestFrameNpcNameText"), "TOP", panel, "TOP", 0, -10)

  U.StyleStockCloseButton(G("QuestFrameCloseButton"), panel, -6, -6)

  local i
  for i = 1, table.getn(PANELS) do
    local name = PANELS[i]
    U.StyleStockScrollbar(G("Quest" .. name .. "ScrollFrameScrollBar"))

    -- Each panel repaints its own parchment when the stock window switches to
    -- it, which happens without QuestFrame itself re-firing OnShow.
    U.PostHookScript(G("QuestFrame" .. name .. "Panel"), "OnShow",
                     ReapplyAfterNative)
  end

  for i = 1, table.getn(BUTTONS) do
    U.StyleStockButton(G(BUTTONS[i]))
  end

  StripPanels()
  ForceWhiteText(frame)
  ApplyNamedWhiteText()
  ApplyTitleSizes()
  ApplySectionHeadingColors()
  StyleTitleRows()
  StyleItemSlots()

  -- Native item rebuilds also restore their owning panels' FontObjects. Apply
  -- the complete pass after each native update, matching the Quest Log's
  -- QuestLog_Update/QuestLog_UpdateQuestDetails ordering so every visible
  -- quest-giver string is returned to white after native rendering.
  -- Both names are WORKING_SOURCE from UnrealPfUI; PostHookGlobal fails closed
  -- if either is absent, while the panel OnShow hooks still cover the common
  -- panel-transition path.
  U.PostHookGlobal("QuestFrameItems_Update", ReapplyAfterNative)
  U.PostHookGlobal("QuestFrameProgressItems_Update", ReapplyAfterNative)
  U.PostHookGlobal("QuestFrameRewardItems_Update", ReapplyAfterNative)

  -- The second click path described at RewardClicked, installed once per
  -- session next to the other stock-global hooks.
  U.PostHookGlobal("QuestRewardItem_OnClick", RewardClicked)

  U.PostHookScript(frame, "OnShow", ReapplyAfterNative)

  if frame.IsShown then
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then Reapply() end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Diagnostic: which strings did NOT come back white
--
-- Reported in game: some text in the NPC quest dialog is still not white after
-- the U.SetStockFont pass. Rather than guess at another name list, this reads
-- back what the client actually reports for every FontString reachable under
-- QuestFrame/GossipFrame -- name, colour, font face and size -- so the ones
-- that resisted the pass can be identified instead of assumed.
--
-- Read via /uui questtext with the NPC window open. Anything the walker never
-- reaches at all (a string parented outside these frames, or deeper than the
-- recursion limit) is absent from the list entirely, which is itself the
-- answer in that case.
-- ---------------------------------------------------------------------------
local function DescribeFontString(region)
  local entry = { name = "<unnamed>", text = "", color = "?", font = "?",
                  size = "?", shown = "?" }

  if region.GetName then
    local ok, name = pcall(region.GetName, region)
    if ok and name then entry.name = name end
  end

  if region.GetText then
    local ok, text = pcall(region.GetText, region)
    if ok and type(text) == "string" then
      entry.text = string.sub(text, 1, 40)
    end
  end

  if region.IsShown then
    local ok, shown = pcall(region.IsShown, region)
    if ok then entry.shown = shown and "yes" or "no" end
  end

  if region.GetTextColor then
    local ok, r, g, b = pcall(region.GetTextColor, region)
    if ok and tonumber(r) then
      entry.r, entry.g, entry.b = r, g, b
      entry.color = string.format("%.2f/%.2f/%.2f", r, g, b)
    end
  end

  if region.GetFont then
    local ok, path, size = pcall(region.GetFont, region)
    if ok then
      if type(path) == "string" then entry.font = path end
      if tonumber(size) then entry.size = tostring(size) end
    end
  end

  return entry
end

local function CollectStrings(object, out, depth)
  if not object or depth > 8 then return end

  if object.GetRegions then
    local ok, regions = pcall(function() return { object:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        if region and region.GetObjectType then
          local typeOk, objectType = pcall(region.GetObjectType, region)
          if typeOk and objectType == "FontString" then
            table.insert(out, DescribeFontString(region))
          end
        end
      end
    end
  end

  if object.GetChildren then
    local ok, children = pcall(function() return { object:GetChildren() } end)
    if ok and type(children) == "table" then
      local i
      for i = 1, table.getn(children) do
        CollectStrings(children[i], out, depth + 1)
      end
    end
  end
end

function U.QuestTextReport()
  local out = {}
  CollectStrings(G("QuestFrame"), out, 0)
  CollectStrings(G("GossipFrame"), out, 0)
  return out
end

-- USER_CONFIRMED_INGAME (modules/trainer.lua): stock dialog frames like this
-- are not reliably resolvable from OnEnable on this client. Same retry shape as
-- modules/gossip.lua: ADDON_LOADED as the lazy-load fallback plus the documented
-- quest-window events as the real triggers, all torn down once BuildFrame
-- succeeds once. Registering an event never proves it fires here, so several are
-- used rather than committing to one.
local pendingEvents = {
  "ADDON_LOADED",
  "QUEST_GREETING",
  "QUEST_DETAIL",
  "QUEST_PROGRESS",
  "QUEST_COMPLETE",
}

-- Not a build trigger: QUEST_FINISHED only ever means the quest window closed,
-- so it is registered beside the events above purely to drop the selection.
local FINISH_EVENT = "QUEST_FINISHED"

local function TryBuild()
  if BuildFrame() then
    local i
    for i = 1, table.getn(pendingEvents) do
      U.UnregisterEvent(pendingEvents[i], TryBuild)
    end
    -- The quest window swaps panels in place as you move greeting -> detail ->
    -- progress -> reward, so these stay registered after the build as content
    -- refresh triggers, alongside the per-panel OnShow hooks.
    for i = 2, table.getn(pendingEvents) do
      U.RegisterEvent(pendingEvents[i], ReapplyAfterNative)
      -- Registered after ReapplyAfterNative so the clear lands on top of the
      -- restyle that same event triggers, instead of being repainted by it.
      U.RegisterEvent(pendingEvents[i], ClearRewardSelection)
    end
    U.RegisterEvent(FINISH_EVENT, ClearRewardSelection)
    return true
  end
  return false
end

function QF:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then
    -- The stock quest frame is left exactly as the client draws it. Only the
    -- reward price and equipped-item comparison are added, matching what the
    -- modern themes get from StyleItemSlots.
    HookQuestRewards()
    local i
    for i = 1, table.getn(pendingEvents) do
      U.RegisterEvent(pendingEvents[i], HookQuestRewards)
    end
    return
  end
  if TryBuild() then return end

  local i
  for i = 1, table.getn(pendingEvents) do
    U.RegisterEvent(pendingEvents[i], TryBuild)
  end
end
