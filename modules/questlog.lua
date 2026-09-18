-- unrealUI :: modules/questlog.lua
--
-- pfUI-modern-inspired treatment of the native Quest Log. The native quest
-- data, row templates, scrolling, selection, tracking and action scripts stay
-- intact; unrealUI changes only artwork, typography and layout.
--
-- This file owns the window under every theme that is not the client's own
-- chrome, and the behaviour under all of them. The Dragonflight design is a
-- separate module, modules/questlogdesign.lua, which `modern-wow` and
-- classic-wow's `questlog` Modern WoW module selection both draw -- the same
-- code, one file. Every U.ModernWowQuestLog* call below is a no-op when that
-- design is not the one being drawn.

local U = UnrealUI
local M = U.media
local QL = U.RegisterModule("questlog")

local QUEST_ROWS = 23
-- Quest log headings use unrealUI's real chrome accent (#f5ae0a) rather than
-- the teal this module previously carried; headings are addon chrome, so they
-- follow the shared accent token instead of a module-local colour.
local QUEST_ACCENT = M.color.accent
local QUEST_BRIGHT = { 0.92, 0.92, 0.92, 1 }
local QUEST_WHITE = { 1.00, 1.00, 1.00, 1 }

local config
local frame, detail, listScroll, detailPanel, collapseAllButton

-- Filled by the first header click attempt so /uui check can report which of
-- the collapse entry points this client actually provides.
local collapseReport = { collapse = "untested", expand = "untested",
                         nativeClick = "untested" }

-- Which signal the tracked-quest mark ended up using, and how many rows it
-- marked on the last refresh. Turns "the mark does not show" into something
-- specific: no source means the client offers neither signal.
local trackReport = { source = "none", marked = 0 }

-- Reload-time re-tracking.
--
-- questlog.isquestwatched_resets_to_zero_across_reload (knowledge.json):
-- IsQuestWatched genuinely reports 0 tracked quests after /reload -- the
-- watch list itself does not survive on this client, unlike Vanilla where
-- it is engine-side state independent of the Lua environment. The
-- questtrack probe (USER_CONFIRMED_INGAME) confirmed AddQuestWatch(index)/
-- RemoveQuestWatch(index) both exist and round-trip correctly against
-- IsQuestWatched(index) using the same raw GetQuestLogTitle index -- no
-- separate "quest-only" index space, that was a probe bug, not client
-- behaviour. So unrealUI can re-establish tracking itself: remember which
-- quest titles the player tracked (title, not index -- the index shifts
-- every time a quest is turned in or the log re-sorts) and call
-- AddQuestWatch again for any of them found untracked after login/reload.
-- Defined here, ahead of UpdateRows, because a later `local function` of the
-- same name would not be visible as an upvalue inside a function textually
-- defined before it -- Lua locals only scope forward from their declaration.
--
-- trackingRestored gates *forgetting* a quest. BuildFrame runs UpdateRows
-- before OnEnable reaches RestoreTrackedQuests, and straight after a reload
-- the client reports every quest unwatched -- so without this gate that first
-- pass would erase the very memory the restore is about to read, and the
-- feature would silently defeat itself. Remembering is never gated; only
-- removal waits until the restore has had its turn.
local trackingRestored = false

local function SyncTrackedQuestMemory(title, watched)
  if not config or not title or title == "" then return end
  if watched then
    config.trackedQuests[title] = true
  elseif trackingRestored and config.trackedQuests[title] then
    config.trackedQuests[title] = nil
  end
end

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

-- Whether the Quest Log's Dragonflight design is the one being drawn.
--
-- That design is modules/questlogdesign.lua, one independent module used by
-- `modern-wow` and by classic-wow's `questlog` Modern WoW module selection --
-- the same code for both themes, which is why this file asks that module
-- rather than naming a theme. One read, here; everything below calls this
-- (rules/unreal-ui-design.md, theme scope).
local function ModernWow()
  return type(U.ModernWowQuestLogActive) == "function" and
         U.ModernWowQuestLogActive() and true or false
end

-- Text on the right page. Under modern-wow these are left-aligned to the
-- parchment's inner margin: the art gives that page a printed edge, and a
-- centred paragraph inside it reads as floating rather than set on the page.
-- The flat themes keep whatever justification the client shipped, so this is
-- applied through SetQuestFont's `align` flag rather than to every string.
local function SetQuestFont(object, size, color, align)
  local points = size or M.fontSize.normal
  U.SetStockFont(object, points, color or M.color.text)

  -- No shadow on the page art: the details pane is parchment there, where a
  -- dark shadow under dark ink reads as a smudge rather than separation, and
  -- the quest list is dark enough not to need one either. Re-declared through
  -- U.SetFont with shadowFree so a later restyle does not put it back, then
  -- cleared, because the shadow this call already applied is still on the
  -- FontString.
  if ModernWow() then
    U.SetFont(object, points, nil, nil, true)
    U.ClearTextShadow(object)
  end

  -- Justification LAST, and that ordering is the whole fix.
  --
  -- Every font call above ends in FontString:SetFontObject -- U.SetStockFont
  -- binds GameFontNormal, and U.SetFont binds the private Font object that
  -- core/compat.lua builds per FontString (ApplyFontRecord). SetFontObject
  -- carries the font object's OWN justification onto the string, so a
  -- SetJustifyH issued before them is overwritten by the next one. That is why
  -- the wrapped body already read left -- its font object is left-justified --
  -- while the title, the section headings and the objectives snapped back to
  -- centred no matter what this module asked for.
  --
  -- Only justification is touched. Converting these strings' anchors was tried
  -- and is wrong on this client: knowledge.json /
  -- frames.getpoint_relative_name_y_inverted records that GetPoint returns the
  -- relative frame as a name string with an inverted Y, and lists "recapturing
  -- then immediately clearing/reapplying the same point" as a failed approach.
  if align and ModernWow() then
    pcall(object.SetJustifyH, object, "LEFT")
  end
end

local function ApplyQuestFonts()
  -- Only the details pane changes colour between designs: it is the one part of
  -- this window that sits on parchment under the Modern WoW design. Everything
  -- anchored to the header or the quest list is over dark art either way and
  -- keeps unrealUI's own colours. The two ink colours belong to that design, so
  -- they are asked for rather than restated here.
  local inkHeading, inkBody = U.ModernWowQuestLogInk()
  local heading = inkHeading or QUEST_ACCENT
  local body = inkBody or QUEST_WHITE

  SetQuestFont(G("QuestLogTitleText"), M.fontSize.large, QUEST_BRIGHT)
  SetQuestFont(G("QuestLogQuestCount"), M.fontSize.small, QUEST_ACCENT)
  SetQuestFont(G("QuestLogQuestTitle"), M.fontSize.large, heading, true)
  SetQuestFont(G("QuestLogObjectivesText"), nil, body, true)
  SetQuestFont(G("QuestLogQuestDescription"), nil, body, true)
  SetQuestFont(G("QuestLogDescriptionTitle"), M.fontSize.large, heading, true)
  SetQuestFont(G("QuestLogRewardTitleText"), M.fontSize.large, heading, true)
  SetQuestFont(G("QuestLogItemChooseText"), nil, body, true)
  SetQuestFont(G("QuestLogItemReceiveText"), nil, body, true)
  SetQuestFont(G("QuestLogRequiredMoneyText"), nil, body, true)
  SetQuestFont(G("QuestLogSpellLearnText"), nil, body, true)
  -- Single-line strings only -- but "single-line" is a property of the TEXT,
  -- not of the field. A paragraph that happens to fit on one line never wraps,
  -- so it is drawn centred in its 285-wide box exactly like a heading is, which
  -- is why the two body paragraphs are fitted here as well: a short quest
  -- summary was reported sitting indented, out of line with the description
  -- under it. The fit is inert on anything that really does wrap, because
  -- GetStringWidth then reports more than the box and the native width stands
  -- as the ceiling.
  -- "You will be able to choose one of these rewards:" is in the list for the
  -- same reason as the headings: one line, drawn centred in its own box.
  -- The string list, the measuring and the re-fit poll are the Modern WoW
  -- design's (modules/questlogdesign.lua); inert under the flat themes.
  U.ModernWowQuestLogFitLines()

  local i
  for i = 1, QUEST_ROWS do
    SetQuestFont(G("QuestLogTitle" .. i), M.fontSize.normal, QUEST_BRIGHT)
  end
  for i = 1, 10 do
    SetQuestFont(G("QuestLogObjective" .. i), nil, body, true)
    U.ModernWowQuestLogFitLine(G("QuestLogObjective" .. i))
    -- The reward name and count stay bright in both themes: they are drawn on
    -- the reward button's own dark face, not on the page behind it.
    SetQuestFont(G("QuestLogItem" .. i .. "Name"), nil, QUEST_WHITE)
    SetQuestFont(G("QuestLogItem" .. i .. "Count"), M.fontSize.small, QUEST_WHITE)
    -- Rarity wins over the white base; a reward with no resolvable quality
    -- simply stays white (core/itemslot.lua U.ColorQuestRewardName).
    U.ColorQuestRewardName(G("QuestLogItem" .. i), G("QuestLogItem" .. i .. "Name"),
                           "log", i)
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
  U.RefreshWindowOverlap(frame)
  U.ModernWowQuestLogResize()
end

-- Header expand/collapse.
--
-- The stock row Button's own OnClick does not collapse a header on this client
-- (USER_CONFIRMED_INGAME: clicking "Northshire Valley" did nothing, while the
-- All button worked), and query_compat.py has no record for CollapseQuestHeader,
-- ExpandQuestHeader or the row click handler. Rather than guess at one of them,
-- this tries the documented Vanilla entry points in order and records what was
-- actually available, so /uui check turns the first click into evidence instead
-- of another round of blind iteration.
local function ToggleHeader(row)
  local index = row and row.uuiQuestIndex
  if not index then return end

  local collapsed = row.uuiCollapsed
  local name = collapsed and "ExpandQuestHeader" or "CollapseQuestHeader"
  local key = collapsed and "expand" or "collapse"
  local fn = G(name)

  if type(fn) == "function" then
    local ok, err = pcall(fn, index)
    collapseReport[key] = ok and "ok" or ("error: " .. tostring(err))
    if ok then
      local update = G("QuestLog_Update")
      if type(update) == "function" then pcall(update) end
      return
    end
  else
    collapseReport[key] = "missing"
  end

  -- Fall back to the row's own handler in case this client routes collapsing
  -- through the click path rather than the standalone globals.
  if row.GetScript then
    local scriptOk, native = pcall(row.GetScript, row, "OnClick")
    if scriptOk and native then
      collapseReport.nativeClick = "present"
      pcall(native, row)
      return
    end
  end
  collapseReport.nativeClick = "missing"
  U.Error("questlog: no working header collapse call (" .. name .. " missing)")
end

-- Read-only alignment readout for the details page (/uui qlalign).
--
-- Reported in game under modern-wow: the quest title, the "Description"
-- heading and the objective lines stay centred although SetQuestFont issues
-- SetJustifyH("LEFT") last, while the wrapped summary and body read left.
-- Rather than guess again, this records what the client reports for each
-- string: justification, box width versus text width, and the raw anchor
-- points. GetPoint is only read here, never reapplied (knowledge.json /
-- frames.getpoint_relative_name_y_inverted), so its Y sign is as reported.
function U.QuestLogAlignReport()
  -- UnrealQuestLogLevel is UnrealQuest's level label, placed inside the
  -- title's grown height; recorded so an overlap with the summary can be
  -- measured rather than guessed.
  local names = { "QuestLogQuestTitle", "UnrealQuestLogLevel",
                  "QuestLogObjectivesText",
                  "QuestLogDescriptionTitle", "QuestLogQuestDescription" }
  local n
  for n = 1, 10 do table.insert(names, "QuestLogObjective" .. n) end

  local function read(object, method)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(object[method], object)
    if not ok then return "error" end
    return a, b, c, d, e
  end

  local report = { theme = ModernWow() and "modern-wow" or "other",
                   style = U.GetActiveThemeStyle() }
  local i
  for i = 1, table.getn(names) do
    local object = G(names[i])
    local entry = { name = names[i], present = object and "yes" or "no" }
    if object then
      entry.shown = read(object, "IsShown") and "yes" or "no"
      entry.text = tostring(read(object, "GetText") or "")
      entry.justifyH = tostring(read(object, "GetJustifyH"))
      entry.width = tostring(read(object, "GetWidth"))
      entry.height = tostring(read(object, "GetHeight"))
      entry.top = tostring(read(object, "GetTop"))
      entry.bottom = tostring(read(object, "GetBottom"))
      entry.stringWidth = tostring(read(object, "GetStringWidth"))
      local count = tonumber(read(object, "GetNumPoints")) or 0
      entry.numPoints = count
      entry.points = {}
      local p
      for p = 1, math.max(count, 1) do
        local ok, point, relative, relativePoint, x, y =
          pcall(object.GetPoint, object, p)
        if ok and point then
          if type(relative) == "table" and relative.GetName then
            local nameOk, relName = pcall(relative.GetName, relative)
            relative = nameOk and relName or "table"
          end
          table.insert(entry.points, tostring(point) .. " -> " ..
            tostring(relative) .. " " .. tostring(relativePoint) ..
            " " .. tostring(x) .. "," .. tostring(y))
        end
      end
    end
    table.insert(report, entry)
  end
  return report
end

function U.QuestLogCollapseReport()
  return collapseReport
end

function U.QuestLogTrackReport()
  return trackReport
end

-- Tracked-quest ("followed") mark.
--
-- The stock mark is QuestLogTitleNCheck, a Texture region on the row. Simply
-- re-anchoring it the way UnrealPfUI does (RIGHT to the row's LEFT +24) left
-- only a thin sliver visible on this client (USER_CONFIRMED_INGAME, twice):
-- the stock texture is wider than the 24-unit gutter it was moved into, so most
-- of it lands left of the list's left edge, and a Texture region cannot be
-- raised above whatever is drawn there -- draw layers only order regions within
-- one frame, so there is no z-order fix available for it from an AddOn.
--
-- So unrealUI stops trying to place the native texture and owns the mark: a
-- small accent bar, a real Frame parented to the row, explicitly raised above
-- the row and above the list panel. It is a Frame, not a Button, precisely so
-- it cannot swallow the shift+click that toggles tracking. The native Check is
-- stripped, but its shown state is still read as the tracking signal, so the
-- client keeps deciding what is tracked and unrealUI only renders it.
local TRACK_MARK_WIDTH = 4

local function BuildTrackMark(row)
  if not row or row.uuiTrackMark then return row.uuiTrackMark end

  local heightOk, height = pcall(row.GetHeight, row)
  local barHeight = heightOk and tonumber(height) and math.max(height - 6, 6) or 10

  -- USER_CONFIRMED_INGAME: the mark needs unrealUI's actual chrome colour
  -- (#f5ae0a) to read as an addon element instead of an off-palette accent.
  -- QUEST_ACCENT now resolves to this same token, so headings and the mark
  -- share one colour by design.
  local mark = U.CreatePanel(row, {
    width = TRACK_MARK_WIDTH,
    height = barHeight,
    background = M.color.accent,
    border = false,
  })
  if not mark then return nil end

  mark:SetPoint("LEFT", row, "LEFT", 4, 0)
  pcall(mark.EnableMouse, mark, false)

  -- The list panel is a sibling created after the rows, so the mark is raised
  -- explicitly rather than trusting creation order to keep it on top.
  local levelOk, level = pcall(row.GetFrameLevel, row)
  if levelOk and tonumber(level) then
    pcall(mark.SetFrameLevel, mark, level + 4)
  end

  mark:Hide()
  row.uuiTrackMark = mark
  return mark
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
    local row = G("QuestLogTitle" .. i)
    if row then
      row.uuiCollapseClick = ToggleHeader
      U.StyleStockCollapseButton(row)
      U.ModernWowQuestLogRowFace(row)
      BuildTrackMark(row)
    end
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
  local headers, collapsedHeaders = 0, 0

  local isWatched = G("IsQuestWatched")
  trackReport.marked = 0

  for i = 1, QUEST_ROWS do
    local row = G("QuestLogTitle" .. i)
    local check = G("QuestLogTitle" .. i .. "Check")

    -- Read the native mark's state before neutralising its artwork: Show/Hide
    -- still tracks correctly after the texture is blanked, so this keeps the
    -- client in charge of what counts as tracked.
    local nativeShown
    if check then
      local shownOk, shown = pcall(check.IsShown, check)
      if shownOk then nativeShown = shown and true or false end
      U.HideRegion(check)
    end

    local questIndex = i + offset
    local titleOk, text, level, questTag, isHeader, isCollapsed
    if row and questIndex <= numEntries then
      titleOk, text, level, questTag, isHeader, isCollapsed = pcall(getTitle, questIndex)
      titleOk = titleOk and type(text) == "string"
    end

    if row then
      -- The row's collapse action needs the quest index the row is currently
      -- showing, which only exists here: the scroll offset moves it.
      row.uuiQuestIndex = titleOk and isHeader and questIndex or nil
      row.uuiCollapsed = isCollapsed and true or false
      U.SetStockCollapseState(row, titleOk and isHeader, isCollapsed)

      -- Tracking state, preferring the API over the stripped native texture.
      -- Which one answers is recorded so /uui check can say whether the mark is
      -- driven by IsQuestWatched or by the stock Check region on this client.
      local watched
      if type(isWatched) == "function" and titleOk and not isHeader then
        local watchOk, value = pcall(isWatched, questIndex)
        if watchOk then
          watched = value and true or false
          trackReport.source = "IsQuestWatched"
        else
          trackReport.source = "IsQuestWatched error"
        end
      end
      if watched == nil then
        watched = nativeShown and true or false
        if type(isWatched) ~= "function" then
          trackReport.source = "native Check"
        end
      end
      if watched then trackReport.marked = trackReport.marked + 1 end
      if titleOk and not isHeader then SyncTrackedQuestMemory(text, watched) end

      local mark = row.uuiTrackMark
      if mark then
        if titleOk and not isHeader and watched then
          mark:Show()
        else
          mark:Hide()
        end
      end
    end
  end

  -- The All button keeps its native click; only its icon is unrealUI's, so its
  -- state is derived from the log itself rather than read from a native flag.
  -- This walks every entry, not just the rows on screen: the visible window is
  -- a scrolled slice and would report the wrong answer once the list is long.
  for i = 1, numEntries do
    local titleOk, _, _, _, isHeader, isCollapsed = pcall(getTitle, i)
    if titleOk and isHeader then
      headers = headers + 1
      if isCollapsed then collapsedHeaders = collapsedHeaders + 1 end
    end
  end
  U.SetStockCollapseState(collapseAllButton, true,
                          headers > 0 and collapsedHeaders == headers)

  -- No-op until the Modern WoW design's count boxes exist.
  U.ModernWowQuestLogCountUpdate()
end

-- Sell price and equipped-item comparison on quest-log rewards.
--
-- The same treatment modules/quest.lua gives the quest-giver frame, on the
-- other surface where the player weighs a reward. The native button owns
-- tooltip population and already knows which list it belongs to: it stores
-- "choice" or "reward" in button.type and its 1-based index in GetID(), which
-- is exactly what it feeds to GameTooltip:SetQuestLogItem. Append only after
-- that native OnEnter has run, so the price lands under a populated tooltip.
--
-- This is behavior only -- no texture, font or anchor is touched -- and it is
-- kept separate from the styling guard below so the hooks survive a button
-- that was already styled on an earlier pass.
local function HookQuestItemTooltip(item)
  if not item or item.uuiQuestLogPriceHooks then return end
  item.uuiQuestLogPriceHooks = true

  U.PostHookScript(item, "OnEnter", function()
    local idOk, index = false, nil
    if item.GetID then idOk, index = pcall(item.GetID, item) end
    if not idOk then return end

    local link
    if type(U.ShowQuestLogItemPrice) == "function" then
      link = U.ShowQuestLogItemPrice(item.type, index)
    end
    -- The resolved link also carries the reward's rarity onto the tooltip's
    -- name line. A reward that only resolved through the name fallback leaves
    -- the native colour alone.
    if type(U.ColorTooltipItemName) == "function" then
      U.ColorTooltipItemName(link)
    end
    if type(U.ShowItemCompare) == "function" then
      U.ShowItemCompare(link)
    end
  end)
  U.PostHookScript(item, "OnLeave", function()
    if type(U.ClearTooltipItemName) == "function" then
      U.ClearTooltipItemName()
    end
    if type(U.HideItemPrice) == "function" then U.HideItemPrice() end
    if type(U.HideItemCompare) == "function" then U.HideItemCompare() end
  end)
end

local function StyleQuestItems()
  local maxItems = tonumber(G("MAX_NUM_ITEMS")) or 10
  local i
  for i = 1, maxItems do
    local name = "QuestLogItem" .. i
    local item = G(name)
    local icon = G(name .. "IconTexture")
    HookQuestItemTooltip(item)
    -- The Modern WoW design keeps the reward buttons' native art -- the same slot
    -- background, size and icon placement Classic WoW shows -- because the
    -- dark flat cell reads as a hole in that theme's parchment page. The
    -- tooltip hooks above still apply. Theme changes are reload-bound, so a
    -- button is never left half-styled by a switch.
    if item and not item.uuiQuestItemStyled and not ModernWow() then
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

      -- The reward name keeps its native anchor, which was measured against the
      -- stock cell -- so after the cell is narrowed by 12 and the icon is moved
      -- and resized, the name is left sitting at the bottom of the cell and
      -- running past its right edge (USER_CONFIRMED_INGAME). Anchoring both
      -- corners boxes the FontString inside the remaining space, so a long
      -- reward name wraps within the cell instead of escaping it. The stock
      -- ScrollFrame does not clip its children, so an overflowing name is drawn
      -- outside the pane entirely rather than being cut off.
      local title = G(name .. "Name")
      if title and icon then
        pcall(function()
          title:ClearAllPoints()
          title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
          title:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -5, 4)
          title:SetJustifyH("LEFT")
          title:SetJustifyV("MIDDLE")
        end)
      end

      local count = G(name .. "Count")
      if count and icon then
        pcall(function()
          count:ClearAllPoints()
          count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
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

  -- The tracker is persistent HUD, like the action bars.  Its native frame
  -- otherwise inherits UIParent's default layer and can cover open interface
  -- windows where the two overlap.
  pcall(watch.SetFrameStrata, watch, "LOW")

  U.RegisterMover("questwatch.frame", watch, {
    label = U.L("MOVER_LABEL_QUEST_TRACKER"),
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
  local close = G("QuestLogFrameCloseButton")
  U.StyleStockCloseButton(close, frame, -6, -6)

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
      U.RefreshWindowOverlap(frame)
      U.ModernWowQuestLogResize()
    end
  end)
  U.PostHookScript(detail, "OnShow", function()
    if detailPanel then pcall(detailPanel.Show, detailPanel) end
    if not detail.uuiUserHidden then
      pcall(frame.SetWidth, frame, 676)
      U.StyleStockArrowButton(expand, "left", 21)
      U.RefreshWindowOverlap(frame)
      U.ModernWowQuestLogResize()
    end
  end)

  local collapseAll = G("QuestLogCollapseAllButton")
  collapseAllButton = collapseAll
  U.StripStockTextures(G("QuestLogExpandButtonFrame"))
  -- No uuiCollapseClick override: the All button's native OnClick already works
  -- on this client, so its icon just forwards the click back to it.
  U.StyleStockCollapseButton(collapseAll, true)
  U.SetStockCollapseState(collapseAll, true, false)
  if collapseAll and G("QuestLogTitle1") then
    pcall(function()
      collapseAll:ClearAllPoints()
      collapseAll:SetPoint("BOTTOMLEFT", G("QuestLogTitle1"), "TOPLEFT", -6, 4)
    end)
  end

  U.StripStockTextures(listScroll)
  -- The Modern WoW design keeps the client's own scroll bar art. DragonflightUI
  -- ships no
  -- scroll bar textures at all -- it never skins them -- so the stock gold bar
  -- is the one piece of chrome on this window that already matches parchment.
  -- U.StripTextures is not recursive, so the bar keeps its own art as long as
  -- nothing restyles it.
  if not ModernWow() then
    U.StyleStockScrollbar(G("QuestLogListScrollFrameScrollBar"))
  end
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
  if not ModernWow() then
    U.StyleStockScrollbar(G("QuestLogDetailScrollFrameScrollBar"))
  end
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

  -- The native track square (its tooltip is the "Shift-click a quest" hint) is
  -- removed by request; Shift-click on a row still tracks. Alpha 0 and no mouse
  -- as well as Hide, so a native refresh re-showing it stays invisible and inert.
  local track = G("QuestLogTrack")
  if track then
    pcall(track.EnableMouse, track, false)
    pcall(track.SetAlpha, track, 0)
    pcall(track.Hide, track)
  end
  local trackTitle = G("QuestLogTrackTitle")
  if trackTitle then pcall(trackTitle.Hide, trackTitle) end

  -- Hand the window and its controls to the Modern WoW design, then let it
  -- draw. Both calls are no-ops under the flat themes, which keep the panels
  -- and buttons exactly as they were built above.
  U.ModernWowQuestLogBind({
    frame = frame,
    detail = detail,
    list = listScroll,
    collapseAll = collapseAllButton,
    rows = QUEST_ROWS,
    reapply = ReapplyNativeStrip,
  })
  U.ModernWowQuestLogDress({ listPanel, detailPanel }, { abandon, push, exit })

  -- Keep the modern Quest Log's controls explicitly above the shared low-level
  -- drag strip because several of them occupy that same header area.
  local headerControls = {}
  local headerControlOffsets = {}
  if close then table.insert(headerControls, close) end
  if collapseAll then
    table.insert(headerControls, collapseAll)
    if collapseAll.uuiCollapseIcon then
      table.insert(headerControls, collapseAll.uuiCollapseIcon)
      -- Preserve the icon's normal one-level lead over its clickable parent.
      headerControlOffsets[collapseAll.uuiCollapseIcon] = 2
    end
  end
  U.MakeWindowDraggable("questlog", frame, {
    headerHeight = 48,
    headerLevelOffset = 1,
    interactiveFrames = headerControls,
    interactiveFrameOffsets = headerControlOffsets,
  })

  BuildRows()
  StyleQuestItems()
  ApplyQuestFonts()
  -- The coin row and the two polls that keep it and the fitted lines correct
  -- are the Modern WoW design's; both calls stand down under the flat themes.
  U.ModernWowQuestLogMoneyRefresh()
  U.ModernWowQuestLogBeginPolls()

  U.PostHookGlobal("QuestLog_OnShow", function()
    pcall(function()
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -104)
    end)
    ReapplyNativeStrip()
    U.ModernWowQuestLogResize()
  end)
  -- The native list update restores its own FontObjects after rendering rows.
  -- Reapply colours after that work so body text remains legible and headings
  -- retain their intended accent instead of falling back to native black.
  U.PostHookGlobal("QuestLog_Update", function()
    UpdateRows()
    ApplyQuestFonts()
    U.ModernWowQuestLogFitRows()
    U.ModernWowQuestLogRefreshButtons()
  end)
  -- Re-run the item pass as well: the reward buttons are repopulated per
  -- selected quest, and both helpers are idempotent, so a button that already
  -- carries its styling and hooks is skipped.
  U.PostHookGlobal("QuestLog_UpdateQuestDetails", function()
    StyleQuestItems()
    ApplyQuestFonts()
    U.ModernWowQuestLogMoneyRefresh()
    U.ModernWowQuestLogRefreshButtons()
  end)

  local empty = G("EmptyQuestLogFrame")
  if empty then
    -- The empty frame owns the native spiderweb/parchment artwork visible
    -- beneath its message. Keep the FontString but remove that stock art so
    -- the normal unrealUI list panel remains the only empty-state surface.
    StripDecorations(empty)

    local function ApplyEmptyState()
      SetDetailVisible(false)
      pcall(expand.Disable, expand)
    end

    U.PostHookScript(empty, "OnShow", ApplyEmptyState)
    U.PostHookScript(empty, "OnHide", function() pcall(expand.Enable, expand) end)

    -- EmptyQuestLogFrame can already be shown when the addon is initialized
    -- (notably after /reload with the log open), so OnShow is not guaranteed
    -- to run after the hooks above are installed.
    if IsShown(empty) then ApplyEmptyState() end
  end

  -- QuestLog_OnShow only fires when the frame transitions from hidden to
  -- shown. If /reload happens while the log is already open, the frame's
  -- Shown state carries straight through reload and OnShow never re-fires --
  -- so QuestLog_Update never runs and the collapse icons and tracked-quest
  -- marks stay at their just-built, all-hidden state until something else
  -- (scrolling, closing/reopening) forces a refresh (USER_CONFIRMED_INGAME:
  -- reported as the tracked mark "not saved" across reload). Call UpdateRows
  -- directly here to cover that case; it starts with ReapplyNativeStrip so
  -- this replaces that call rather than needing both.
  if IsShown(frame) then UpdateRows() end
  return true
end

-- Returns true when the restore is finished and should not be retried.
--
-- The quest log is not guaranteed to be populated at OnEnable: this client's
-- load-order for quest data is not in the compact evidence, and a restore that
-- runs against an empty log would quietly do nothing. So an empty log is
-- treated as "not ready yet" and retried on the shared update driver (verified
-- machinery -- core/init.lua's own bootstrap fallback uses it) rather than
-- depending on QUEST_LOG_UPDATE, which has no compact-DB record on this client.
local RESTORE_MAX_ATTEMPTS = 20
local restoreAttempts = 0

local function RestoreTrackedQuests()
  if not config or not next(config.trackedQuests) then return true end

  local getCount = G("GetNumQuestLogEntries")
  local getTitle = G("GetQuestLogTitle")
  local isWatched = G("IsQuestWatched")
  local addWatch = G("AddQuestWatch")
  if type(getCount) ~= "function" or type(getTitle) ~= "function" or
     type(addWatch) ~= "function" then
    U.Debug("questlog: quest watch API unavailable; tracking cannot be restored")
    return true
  end

  restoreAttempts = restoreAttempts + 1

  local ok, numEntries = pcall(getCount)
  numEntries = (ok and tonumber(numEntries)) or 0
  if numEntries <= 0 then
    return restoreAttempts >= RESTORE_MAX_ATTEMPTS
  end

  local i, restored = nil, 0
  for i = 1, numEntries do
    local titleOk, text, level, questTag, isHeader = pcall(getTitle, i)
    if titleOk and type(text) == "string" and not isHeader and
       config.trackedQuests[text] then
      local watchedNow = false
      if type(isWatched) == "function" then
        local watchedOk, value = pcall(isWatched, i)
        watchedNow = watchedOk and value and true or false
      end
      if not watchedNow then
        local addOk = pcall(addWatch, i)
        if addOk then restored = restored + 1 end
      end
    end
  end

  U.Debug("questlog: restored " .. restored .. " tracked quest(s) after reload")

  -- Repaint so the marks match the state that was just re-established.
  if type(G("QuestLog_Update")) == "function" then pcall(G("QuestLog_Update")) end
  return true
end

local function BeginTrackingRestore()
  local function Finish()
    trackingRestored = true
  end

  if RestoreTrackedQuests() then
    Finish()
    return
  end

  U.RegisterUpdate("questlog.restore-tracking", 1, function()
    if RestoreTrackedQuests() then
      U.UnregisterUpdate("questlog.restore-tracking")
      Finish()
    end
  end)
end

function QL:OnInit()
  config = U.ModuleConfig("questlog", { trackedQuests = {} })
end

function QL:OnEnable()
  -- Quest tracking is feature state rather than chrome, so retain its restore
  -- path while leaving the client Quest Log visually untouched.
  --
  -- This window is unrealUI's whenever it is not the client's: under `modern`
  -- and `modern-wow`, and under classic-wow when the player selected the Quest
  -- Log as one of its Modern WoW modules -- that selection runs this same
  -- build and the same design (modules/questlogdesign.lua) as the full theme,
  -- rather than a second copy of it. modules/questlogextended.lua stands down
  -- in that case, so the two Classic surfaces never run together.
  if not U.ThemeStyleUsesNativeChrome() or ModernWow() then
    BuildFrame()
  else
    -- Native chrome (classic-wow) keeps the client's Quest Log, but reward
    -- names still take their rarity colour, applied after the native detail
    -- pass has populated the buttons. Colour only: no font, anchor or art.
    U.PostHookGlobal("QuestLog_UpdateQuestDetails", function()
      local maxItems = tonumber(G("MAX_NUM_ITEMS")) or 10
      local i
      for i = 1, maxItems do
        U.ColorQuestRewardName(G("QuestLogItem" .. i),
                               G("QuestLogItem" .. i .. "Name"), "log", i)
      end
    end)
  end
  BeginTrackingRestore()
end
