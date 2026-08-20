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
local REWARD_CARD_WIDTH = 250

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

-- Quest rows on the greeting panel (QuestTitleButton1..N) are plain clickable
-- text/icon rows, not stock chrome buttons -- same shape as modules/gossip.lua's
-- option rows. The per-row icon (QuestTitleButtonNQuestIcon) is a meaningful
-- content glyph (the available/turn-in marker), so it is kept explicitly rather
-- than stripped with the rest of the row's native art.
local function StyleTitleRows()
  -- No compact-DB record for how many QuestTitleButton rows FrameXML ever
  -- instantiates. Same convention as modules/gossip.lua's NUMGOSSIPBUTTONS
  -- fallback: try the documented constant, fall back to a safe upper bound.
  local rows = tonumber(G("MAX_NUM_QUESTS")) or 32
  local i
  for i = 1, rows do
    local button = G("QuestTitleButton" .. i)
    if button then
      local icon = G("QuestTitleButton" .. i .. "QuestIcon")
      U.StripStockTextures(button, icon and { icon = icon } or nil)

      local fontOk, fontstring = false, nil
      if button.GetFontString then
        fontOk, fontstring = pcall(button.GetFontString, button)
      end
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

-- Reward/progress/detail item slots.
--
-- These are Buttons whose icon is a separate <name>IconTexture region, so
-- U.RefreshStockButtonArtwork clears the four native button faces while
-- preserving the real item icon.  These buttons are *layout containers* on
-- this client, not compact icon buttons: their native bounds span the reward
-- area while their icon and label live in separately positioned regions.
-- Creating an unrealUI backdrop on the container therefore produced the two
-- large black blocks in the accept screen and visually cut across its reward
-- content.  Keep the container transparent and style only its real content.
-- U.StyleStockButton is likewise deliberately not used here: it centres the
-- button's own fontstring, which would drag the item name off its native
-- left-aligned anchor beside the icon.
local function StyleItemSlots()
  local p
  for p = 1, table.getn(ITEM_PREFIXES) do
    local i
    for i = 1, ITEMS_PER_PANEL do
      local name = ITEM_PREFIXES[p] .. i
      local button = G(name)
      if button then
        local icon = G(name .. "IconTexture")
        U.RefreshStockButtonArtwork(button, icon)
        U.StripStockTextures(button, icon and { icon = icon } or nil)

        -- Hide a backdrop left by an earlier reload of this module.  Do not
        -- add a replacement: this frame is the full reward-row container.
        U.SetBackdropShown(button, false)

        if icon then
          pcall(function()
            icon:Show()
            icon:SetAlpha(1)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          end)
        end

        local itemName = G(name .. "Name")
        SetQuestFont(itemName, M.fontSize.normal, WHITE)
        SetQuestFont(G(name .. "Count"), M.fontSize.small, WHITE)

        -- The accept frame separates each reward label from its icon during
        -- its native refresh on this client.  The horizontal offset survives,
        -- but the label is reset near the objectives heading, causing the
        -- visible overlap in the reward panel.  Re-anchor the real label to
        -- its real icon after every refresh; do not reposition the container.
        if itemName and icon then
          Reposition(itemName, "LEFT", icon, "RIGHT", 8, 0)
        end

        -- QuestDetailItem/QuestRewardItem are oversized native layout
        -- containers, so their own backdrop cannot be used for the compact
        -- reward card requested here. Build a separate, mouse-transparent
        -- UnrealUI panel around the real icon/name content instead.
        if p > 1 and icon and itemName then
          local card = button.uuiQuestRewardCard
          if not card then
            local owner = frame
            if button.GetParent then
              local parentOk, parent = pcall(button.GetParent, button)
              if parentOk and parent then owner = parent end
            end

            local created, owned = pcall(CreateFrame, "Frame", nil, owner)
            if created and owned then
              card = owned
              button.uuiQuestRewardCard = card
              card:SetWidth(REWARD_CARD_WIDTH)
              U.CreateBackdrop(card, {
                background = { 0.01, 0.01, 0.01, 0.88 },
                border = M.color.border,
              })
              pcall(card.EnableMouse, card, false)

              local levelOk, level = pcall(button.GetFrameLevel, button)
              if levelOk and tonumber(level) then
                level = tonumber(level)
                pcall(card.SetFrameLevel, card, level > 0 and level - 1 or 0)
              end

              if not button.uuiQuestRewardCardHooks then
                button.uuiQuestRewardCardHooks = true
                U.PostHookScript(button, "OnEnter", function()
                  if button.uuiQuestRewardCard then
                    U.SetBorderColor(button.uuiQuestRewardCard,
                                     M.Unpack(M.color.accentDim))
                  end
                end)
                U.PostHookScript(button, "OnLeave", function()
                  if button.uuiQuestRewardCard then
                    U.SetBorderColor(button.uuiQuestRewardCard,
                                     M.Unpack(M.color.border))
                  end
                end)
              end
            end
          end

          if card then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
            card:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -4, -4)

            local hasItem = false
            if itemName.GetText then
              local textOk, text = pcall(itemName.GetText, itemName)
              hasItem = textOk and type(text) == "string" and text ~= ""
            end
            if hasItem then
              card:Show()
            else
              card:Hide()
            end
          end
        end
      end
    end
  end
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
    end
    return true
  end
  return false
end

function QF:OnEnable()
  if TryBuild() then return end

  local i
  for i = 1, table.getn(pendingEvents) do
    U.RegisterEvent(pendingEvents[i], TryBuild)
  end
end
