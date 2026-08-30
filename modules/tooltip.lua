-- unrealUI :: modules/tooltip.lua
--
-- Flat pfUI-modern GameTooltip. The stock beveled frame is replaced with the
-- addon's flat panel look (WHITE8X8 fill, one thin dark outline), and the
-- native status bar is pulled flush against the body with a centered health
-- readout drawn on it.
--
-- For a hovered player the text is rebuilt as:
--   Raykou                          -- white
--   <Guild> [Rank]                  -- guild green + dim grey rank
--   60 Night Elf Ranger             -- class colour
--   [====== 5.4K / 5.4K ======]     -- bar tinted with the class colour
--
-- The flat frame styling is applied to GameTooltip itself, so item and action
-- tooltips inherit the same flat look. Only the *text* rebuild is gated on a
-- player mouseover; item and action tooltip contents are never touched.
--
-- This module is deliberately theme-independent. Classic WoW keeps the client
-- chrome on stock *windows*, but the tooltip is not one of them: it is the
-- surface that carries UnrealUI's own item comparison -- the CURRENTLY_EQUIPPED
-- heading, the stat tint and the change summary -- and running that on the
-- stock tooltip left those features off in that theme entirely. Both themes
-- therefore draw the same flat tooltip. The Classic palette leaves
-- M.color.background/border/text/textDim at their shared values
-- (themes/classic-wow.lua), so nothing here needs a per-theme colour.
--
-- behavior.json / tooltip.native_read/regions/hide/backdrop/statusbar/child.v1
-- (all SUPPORTED, BEHAVIOR_VERIFIED) confirm the calls used here: GameTooltip
-- accepts SetBackdrop while populated, its texture regions hide without fault,
-- GameTooltipStatusBar is a real StatusBar with its own SetStatusBarTexture /
-- SetStatusBarColor, and a plain Frame parented to it accepts a fontstring.
--
-- Two details the probe settled that shape this module:
--   * GameTooltipStatusBar's GetValue/GetMinMaxValues always report a fixed
--     0-100 range regardless of the unit's real pool, so the health text is
--     built from UnitHealth/UnitHealthMax, never from the bar's own value.
--   * The bar is natively anchored below the body at (2, 1) with a 2px side
--     inset, which is the gap being removed here. Re-anchoring it is the one
--     call the probe did not cover; it matches UnrealPfUI's working tooltip
--     module (WORKING_SOURCE), not measured runtime evidence.

local U = UnrealUI
local M = U.media
local TT = U.RegisterModule("tooltip")

-- Target palette, kept together so a colour can be corrected in one place.
local COLOR = {
  name   = { 1.00, 1.00, 1.00 },
  guild  = { 0.30, 1.00, 0.50 },
  rank   = { 0.70, 0.70, 0.70 },
  health = { 1.00, 1.00, 1.00 },
}

local BAR_HEIGHT = 12

local apiCache = {}

local function Api(name)
  local cached = apiCache[name]
  if cached ~= nil then return cached or nil end

  local fn = U.G(name)
  apiCache[name] = type(fn) == "function" and fn or false
  return apiCache[name] or nil
end

local function Call(name, ...)
  local fn = Api(name)
  if not fn then return nil end

  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function IsTruthy(value)
  return value ~= nil and value ~= false and value ~= 0 and value ~= ""
end

-- Inline colour escape, for the one line that carries two colours at once.
local function Hex(color)
  return string.format("|cff%02x%02x%02x",
    math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

-- Matches the target's "5.4K / 5.4K" reading rather than a raw number.
local function Abbreviate(value)
  value = tonumber(value) or 0
  if value >= 1000000 then
    return string.format("%.1fM", value / 1000000)
  elseif value >= 1000 then
    return string.format("%.1fK", value / 1000)
  end
  return tostring(value)
end

local function LineText(index)
  local label = U.G("GameTooltipTextLeft" .. index)
  if not label or not label.GetText then return nil, nil end
  local ok, text = pcall(label.GetText, label)
  if not ok or type(text) ~= "string" then return label, nil end
  return label, text
end

-- ---------------------------------------------------------------------------
-- Item name rarity colour
--
-- The tooltip cannot be asked what it is showing. This client's GameTooltip
-- has no GetItem -- documentation.json records 46 GameTooltip widget methods
-- and that is not one of them -- and GetItemInfo takes an item id or an item
-- string / hyperlink only, never a display name, so line 1's own text is not a
-- lookup key either.
--
-- The item identity therefore arrives from the hover surface, exactly the way
-- modules/itemprice.lua resolves its price, and the consequence is the one
-- that file already states: this appears on the surfaces unrealUI owns a hover
-- hook for -- bag and bank slots, character-sheet slots, vendor rows and quest
-- rewards. Loot and chat links keep whatever the client draws until they get
-- a hook of their own.
--
-- The colour is remembered rather than applied once, because a native item
-- setter can rewrite its own lines while the tooltip stays up and a rewritten
-- line comes back in the client's colour. It is reasserted on every styling
-- pass, keyed to the line-1 text it was resolved for: if the tooltip goes on
-- to show something else without a hook clearing it first, the name no longer
-- matches and the colour is dropped rather than painted onto an unrelated
-- subject.
-- ---------------------------------------------------------------------------
local itemNameColor, itemNameSubject

local function ApplyItemNameColor()
  if not itemNameColor then return end

  local label, text = LineText(1)
  if not label or not label.SetTextColor then return end

  if itemNameSubject and text ~= itemNameSubject then
    itemNameColor, itemNameSubject = nil, nil
    return
  end

  pcall(label.SetTextColor, label,
        itemNameColor[1], itemNameColor[2], itemNameColor[3])
end

-- `quality` is used when the hover surface reports the index directly, which
-- container slots and equipped slots both do; `link` is resolved through the
-- shared item helper otherwise. Neither resolving -- an uncached item, a
-- missing API -- clears any remembered colour and leaves the native one alone.
--
-- `expect` is the optional name the caller believes the tooltip is showing.
-- Where a hover surface can be sure of the item it hands in, it is left out;
-- vendor rows pass it because the stock row buttons are shared between the
-- vendor and buyback lists and only one of those has a link getter here, so
-- the row's index alone does not prove which list the tooltip came from.
function U.ColorTooltipItemName(link, quality, expect)
  local _, text = LineText(1)

  if type(expect) == "string" and text ~= expect then
    U.ClearTooltipItemName()
    return
  end

  local color = nil
  if U.ItemQualityColor then color = U.ItemQualityColor(quality) end
  if not color and link and U.ItemLinkQualityColor then
    color = U.ItemLinkQualityColor(link)
  end

  itemNameColor = color
  itemNameSubject = text
  if not color then
    itemNameSubject = nil
    return
  end

  ApplyItemNameColor()
end

function U.ClearTooltipItemName()
  itemNameColor, itemNameSubject = nil, nil
end

-- ShoppingTooltip1/2 carry the equipped counterpart during a comparison.
-- core/itemslot.lua populates them and knows the worn item's link, so it calls
-- in here immediately after SetInventoryItem and before the CURRENTLY_EQUIPPED
-- heading is inserted -- the heading's line shift copies each row's colour
-- along with its text, so colouring line 1 first is what carries the colour
-- down to the row the name ends up on.
function U.ColorCompareTooltipItemName(name, link)
  if type(name) ~= "string" or not U.ItemLinkQualityColor then return end

  local color = U.ItemLinkQualityColor(link)
  if not color then return end

  local label = U.G(name .. "TextLeft1")
  if not label or not label.SetTextColor then return end
  pcall(label.SetTextColor, label, color[1], color[2], color[3])
end

-- ---------------------------------------------------------------------------
-- Flat frame styling
--
-- The stock edge art comes back after the tooltip is populated, so this is
-- re-applied every time the tooltip is shown or repopulated, not once at
-- enable -- a recorded failed approach was styling only during addon enable,
-- which left the stock border visible as soon as content arrived. See "Style
-- triggers" at the foot of this file for why that reapply is event-driven
-- rather than driven off the update ticker.
--
-- SetBackdrop with a table carrying no edgeFile does NOT drop the stock edge on
-- this client: the fill changes to the requested flat colour while the tan
-- UI-Tooltip-Border art keeps drawing. Confirmed in game -- the body went flat
-- dark and the ornate border survived, on both GameTooltip and its status bar.
-- The edge is therefore removed by driving its colour to zero alpha, which
-- tooltip.native_backdrop.v1 verified as a working call, rather than by trying
-- to clear the backdrop out from under a native frame.
-- ---------------------------------------------------------------------------
local healthLabel

local function ClearNativeEdge(frame)
  if not frame or not frame.SetBackdropBorderColor then return end
  pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
end

local function ClearNativeTextures(name)
  local i
  for i = 1, 3 do
    U.HideRegion(U.G(name .. "Texture" .. i))
  end
end

local function StyleStatusBar()
  local bar = U.G("GameTooltipStatusBar")
  if not bar then return nil end

  -- Flush against the body: no side inset, no vertical offset. The native
  -- anchors are TOPLEFT/TOPRIGHT -> GameTooltip BOTTOMLEFT/BOTTOMRIGHT at
  -- (2, 1) and (-2, 1), which is exactly the margin being removed.
  local tooltip = U.G("GameTooltip")
  if tooltip then
    pcall(bar.ClearAllPoints, bar)
    pcall(bar.SetPoint, bar, "TOPLEFT", tooltip, "BOTTOMLEFT", 0, 0)
    pcall(bar.SetPoint, bar, "TOPRIGHT", tooltip, "BOTTOMRIGHT", 0, 0)
  end
  pcall(bar.SetHeight, bar, BAR_HEIGHT)
  pcall(bar.SetStatusBarTexture, bar, M.texture.statusBar)

  -- Flat fill behind the bar so a partially depleted pool reads as dark rather
  -- than transparent, plus the same thin outline the body carries. The bar
  -- carries its own stock edge, and two adjacent tan edges are most of what
  -- read as a gap between the body and the bar.
  U.CreateBackdrop(bar, { background = M.color.healthBg, border = M.color.border })
  ClearNativeEdge(bar)

  if not healthLabel and bar.CreateFontString then
    local holderOk, holder = pcall(CreateFrame, "Frame", nil, bar)
    if holderOk and holder then
      pcall(holder.SetAllPoints, holder, bar)
      local levelOk, level = pcall(bar.GetFrameLevel, bar)
      pcall(holder.SetFrameLevel, holder,
            (levelOk and type(level) == "number" and level or 0) + 1)

      healthLabel = U.CreateLabel(holder, {
        size = M.fontSize.small,
        color = COLOR.health,
        inherits = "GameFontNormalSmall",
      })
      if healthLabel then
        pcall(healthLabel.SetPoint, healthLabel, "CENTER", holder, "CENTER", 0, 0)
      end
    end
  end

  return bar
end

local function StyleFrame()
  local tooltip = U.G("GameTooltip")
  if not tooltip then return end

  -- Fill only, no edgeFile: the stock bevel lives on the backdrop's edge, and
  -- rendering.backdrop_edge_fractional_not_rasterized means unrealUI draws its
  -- own outline from plain textures instead (core/style.lua).
  U.CreateBackdrop(tooltip, {
    background = M.color.background,
    border = M.color.border,
  })
  ClearNativeEdge(tooltip)

  -- GameTooltipTexture1-3 are the only Texture regions on this client's
  -- tooltip (the other 60 regions are the Left/Right fontstrings); they carry
  -- the remaining stock corner and item-divider art.
  ClearNativeTextures("GameTooltip")

  -- Tooltip text is populated into native FontStrings instead of passing
  -- through U.CreateLabel/U.SetStockFont. Bring every populated line onto the
  -- same crisp one-pixel shadow as the rest of UnrealUI-styled text.
  local lineCount = 0
  local countOk, count = pcall(tooltip.NumLines, tooltip)
  if countOk and type(count) == "number" then lineCount = count end
  for i = 1, lineCount do
    U.SetTextShadow(U.G("GameTooltipTextLeft" .. i))
    U.SetTextShadow(U.G("GameTooltipTextRight" .. i))
  end

  StyleStatusBar()
end

-- ShoppingTooltip1/2 are native GameTooltip frames used by item comparison.
-- They need the same flat body and text treatment as the primary tooltip, but
-- do not carry GameTooltip's unit-health status bar.
function U.StyleCompareTooltip(tooltip, name)
  if not tooltip or type(name) ~= "string" then return end

  -- Unlike GameTooltip, the shopping frames retain their native grey
  -- UI-Tooltip backdrop when a replacement table is applied directly. Clear
  -- that definition first, then install UnrealUI's flat fill. UnrealPfUI uses
  -- this same SetBackdrop(nil) sequence for ShoppingTooltip1/2 on this client
  -- (WORKING_SOURCE; skins/blizzard/tooltips.lua + api/api.lua).
  if tooltip.SetBackdrop then
    pcall(tooltip.SetBackdrop, tooltip, nil)
  end

  U.CreateBackdrop(tooltip, {
    background = M.color.background,
    border = M.color.border,
  })
  ClearNativeEdge(tooltip)

  ClearNativeTextures(name)

  local lineCount = 0
  local countOk, count = pcall(tooltip.NumLines, tooltip)
  if countOk and type(count) == "number" then lineCount = count end
  local i
  for i = 1, lineCount do
    U.SetTextShadow(U.G(name .. "TextLeft" .. i))
    U.SetTextShadow(U.G(name .. "TextRight" .. i))
  end
end

-- SetInventoryItem populates ShoppingTooltip with the equipped item's native
-- lines but does not add CURRENTLY_EQUIPPED. Both themes therefore supply the
-- heading themselves, and both put it *inside* the tooltip: the native compare
-- setters this client uses elsewhere also render it as line 1, so an attached
-- external panel reads as a second floating frame rather than part of the
-- comparison. The heading is inserted with the stock-style line-shift pattern
-- from UnrealPfUI's working comparison module (WORKING_SOURCE,
-- modules/eqcompare.lua): existing line text moves down one row and line 1 is
-- reused for the heading, so no addon-owned row has to relayout a populated
-- tooltip (knowledge.json / tooltip.added_lines_do_not_relayout). Only the
-- final overflow row needs AddLine, and nothing about the result is laid out
-- again for us: the geometry the shift needs is applied by hand below.
local COMPARE_TEXT_SIDES = { "Left", "Right" }

-- How this client lays a tooltip line out, measured by the focused probe in
-- behavior.json / tooltipline (native_layout, measure_order,
-- right_follows_left, v1):
--
--   * A line's text is measured, and truncated to fit, at the moment SetText
--     runs -- against whatever width the region has right then. Widening the
--     region afterwards never reflows the string, which is why sizing a line
--     after writing it left the heading reading "Currently Eq..".
--   * SetText with a string a line already holds does not re-measure at all,
--     so a rewrite has to change the text to take effect.
--   * The client sizes every line to its drawn text plus 5, and draws the
--     glyphs centred in that region. A rewritten row given a wider region
--     therefore drifts to the middle of it -- the heading floating in the
--     middle of the frame, and "Legs" sliding across "Cloth".
--   * A right-hand line is anchored RIGHT-to-LEFT off its own row's left line,
--     offset by the frame's content width. It does not follow a resized frame,
--     and a row that moves down inherits the offset of whatever tooltip laid
--     that row out last -- which is what put the worn item's "Mace" beside its
--     name instead of beside "Main Hand".
--
-- So the shift owns all of it: width before text, the client's own +5 after,
-- and one pass that sizes the frame and re-anchors the right column to it.
local COMPARE_TEXT_INSET = 10
local COMPARE_TEXT_GAP = 8
local COMPARE_LINE_PAD = 5
-- Wider than any tooltip row: text is written against this so the client
-- cannot truncate it, before the row is trimmed to what it measured.
local COMPARE_MEASURE_WIDTH = 512

local function CompareHeaderText()
  local header = U.G("CURRENTLY_EQUIPPED")
  if type(header) ~= "string" or header == "" then
    return "Currently Equipped"
  end
  return header
end

-- Drawn width of a populated line, or 0 for a row that draws nothing.
local function CompareDrawnWidth(label)
  if not label or not label.GetStringWidth then return 0 end

  local shownOk, shown = pcall(label.IsShown, label)
  if not shownOk or not shown then return 0 end

  local textOk, text = pcall(label.GetText, label)
  if not textOk or type(text) ~= "string" or text == "" then return 0 end

  local widthOk, width = pcall(label.GetStringWidth, label)
  if not widthOk or type(width) ~= "number" or width < 0 then return 0 end
  return width
end

-- Writes one line and leaves it with the geometry the client would have given
-- it. The text is written against a ceiling no row reaches, so nothing is
-- truncated while it is measured, and the row is then trimmed to that
-- measurement plus the 5 units every native line carries. The blank write in
-- between is what makes a repeat of the same string take effect at all.
local function WriteCompareLine(label, text)
  if not label or not label.SetText or not label.SetWidth then return 0 end

  pcall(label.SetWidth, label, COMPARE_MEASURE_WIDTH)
  pcall(label.SetText, label, "")
  pcall(label.SetText, label, text)

  local widthOk, width = pcall(label.GetStringWidth, label)
  if not widthOk or type(width) ~= "number" or width <= 0 then return 0 end

  pcall(label.SetWidth, label, width + COMPARE_LINE_PAD)
  return width
end

-- Puts one right-hand line on the content's right border. The offset is the
-- content width because the anchor hangs off the row's left line, whose own
-- left edge is that border's opposite side, and the relative side is named
-- rather than passed as a region because named anchors are what the client's
-- own tooltip layout stores. Re-pointing an existing anchor is expected to
-- replace it; the count is checked rather than assumed, because clearing first
-- would leave the line unanchored if the call after it did not take.
local function AnchorCompareRight(label, leftName, leftLabel, content)
  if not label or not label.SetPoint then return end

  local ok = pcall(label.SetPoint, label, "RIGHT", leftName, "LEFT", content, 0)
  if not ok and leftLabel then
    ok = pcall(label.SetPoint, label, "RIGHT", leftLabel, "LEFT", content, 0)
  end
  if not ok then return end

  local countOk, points = pcall(label.GetNumPoints, label)
  if countOk and type(points) == "number" and points > 1 then
    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "RIGHT", leftName, "LEFT", content, 0)
  end
end

-- Sizes the frame around the rewritten rows and puts the right-hand column
-- back on its inner border. Growing only keeps the client's own width as the
-- floor; the re-anchor runs either way, because a right line that moved down a
-- row is carrying some other tooltip's offset until it is told otherwise.
local function FitCompareTooltip(tooltip, name)
  local countOk, lineCount = pcall(tooltip.NumLines, tooltip)
  if not countOk or type(lineCount) ~= "number" then return end

  local widest = 0
  local lineIndex
  for lineIndex = 1, lineCount do
    local row = CompareDrawnWidth(U.G(name .. "TextLeft" .. lineIndex))
    local right = CompareDrawnWidth(U.G(name .. "TextRight" .. lineIndex))
    if right > 0 then row = row + COMPARE_TEXT_GAP + right end
    if row > widest then widest = row end
  end
  if widest <= 0 then return end

  local content = 0
  local currentOk, current = pcall(tooltip.GetWidth, tooltip)
  if currentOk and type(current) == "number" then
    content = current - COMPARE_TEXT_INSET * 2
  end
  if widest > content then
    content = widest
    pcall(tooltip.SetWidth, tooltip, content + COMPARE_TEXT_INSET * 2)
  end

  for lineIndex = 1, lineCount do
    local right = U.G(name .. "TextRight" .. lineIndex)
    if CompareDrawnWidth(right) > 0 then
      local leftName = name .. "TextLeft" .. lineIndex
      AnchorCompareRight(right, leftName, U.G(leftName), content)
    end
  end
end

function U.ShowCompareTooltipHeader(tooltip, name)
  if not tooltip or type(name) ~= "string" then return end

  local header = CompareHeaderText()
  local first = U.G(name .. "TextLeft1")
  if not first or not first.GetText then return end

  local firstOk, firstText = pcall(first.GetText, first)
  if firstOk and firstText == header then return first end

  local countOk, lineCount = pcall(tooltip.NumLines, tooltip)
  if not countOk or type(lineCount) ~= "number" then return end

  local lineIndex, sideIndex
  for lineIndex = lineCount, 1, -1 do
    for sideIndex = 1, table.getn(COMPARE_TEXT_SIDES) do
      local side = COMPARE_TEXT_SIDES[sideIndex]
      local current = U.G(name .. "Text" .. side .. lineIndex)
      local below = U.G(name .. "Text" .. side .. (lineIndex + 1))
      local shownOk, shown = false, false
      if current and current.IsShown then
        shownOk, shown = pcall(current.IsShown, current)
      end

      if shownOk and shown and below then
        local textOk, text = pcall(current.GetText, current)
        if textOk and type(text) == "string" and text ~= "" then
          local colorOk, r, g, b = pcall(current.GetTextColor, current)
          if not colorOk then r, g, b = 1, 1, 1 end

          local linesOk, currentLines = pcall(tooltip.NumLines, tooltip)
          if linesOk and type(currentLines) == "number" and
             currentLines < lineIndex + 1 then
            pcall(tooltip.AddLine, tooltip, text, r, g, b, true)
          else
            WriteCompareLine(below, text)
            pcall(below.SetTextColor, below, r, g, b)
            pcall(below.Show, below)
            pcall(current.Hide, current)
          end
        end
      end
    end
  end

  -- The heading takes the shared palette in every theme, because the tooltip
  -- it sits in is UnrealUI's flat frame in every theme.
  local dim = M.color.textDim
  local r, g, b = 0.5, 0.5, 0.5
  if dim then r, g, b = dim[1], dim[2], dim[3] end

  WriteCompareLine(first, header)
  pcall(first.SetTextColor, first, r, g, b, 1)
  pcall(first.Show, first)
  pcall(tooltip.Show, tooltip)
  FitCompareTooltip(tooltip, name)
  return first
end

-- Comparison tooltips are not owned by the bag module. The client can show
-- ShoppingTooltip1/2 from merchant, character, auction and other native item
-- paths, so their modern skin must be driven from the tooltip frames
-- themselves. A bag-slot-only call leaves every other path in native chrome.
local compareStyledFor = {}

local function CompareLineText(name, index)
  local label = U.G(name .. "TextLeft" .. index)
  if not label or not label.GetText then return nil end
  local ok, value = pcall(label.GetText, label)
  if ok and type(value) == "string" then return value end
  return nil
end

local function RefreshCompareTooltip(index, force)
  if U.PerfDisabled and U.PerfDisabled("tooltip") then return end

  local name = "ShoppingTooltip" .. index
  local tooltip = U.G(name)
  if not tooltip or not tooltip.IsShown then return end

  local shownOk, shown = pcall(tooltip.IsShown, tooltip)
  if not shownOk or not shown then
    compareStyledFor[index] = nil
    return
  end

  -- SetInventoryItem uses the item name on line 1; native compare setters add
  -- CURRENTLY_EQUIPPED first and put the item name on line 2. Track both so a
  -- visible tooltip repopulated through either path gets a fresh full pass.
  local subject = (CompareLineText(name, 1) or "?") .. "\n" ..
                  (CompareLineText(name, 2) or "")
  if force or compareStyledFor[index] ~= subject then
    U.StyleCompareTooltip(tooltip, name)
    compareStyledFor[index] = subject
  else
    -- Native population can restore edge/corner art without changing the
    -- visible subject. Keep the cheap suppression active between full passes.
    ClearNativeEdge(tooltip)
    ClearNativeTextures(name)
  end
end

-- ---------------------------------------------------------------------------
-- Comparison placement
--
-- The comparison frames were chained straight off the item tooltip's left
-- border, which is right only while that side has room. Hovering a bag slot
-- near the left edge of the screen pushed the equipped-item frame out of the
-- draw area, and the client's own clamp then slid it back inwards -- on top of
-- the item tooltip it was meant to sit beside (user report with screenshot,
-- 2026-08-30).
--
-- Placement is therefore measured before it is applied: the free width on
-- either side of the host tooltip is weighed against what the visible
-- comparison frames need, the side that fits wins, and every frame is kept
-- inside the draw area by this code rather than by the client's clamp. When
-- neither border can hold a frame it is stacked off the host's top or bottom
-- instead, which is the one remaining way to keep it off the item's text.
--
-- Geometry is handled in UIParent units. knowledge.json /
-- frames.scaled_frame_edge_coordinates_mixed_space (PARTIAL) records that on a
-- frame whose scale is not 1 this client returns the origin in the parent's
-- space while the extent stays in the frame's own, so GetLeft/GetBottom are
-- taken as they come back and GetWidth/GetHeight are converted through the
-- frame's effective-scale ratio. Both are identities for the scale-1 tooltips
-- this actually runs on, and neither guesses at a mixed-space rule.
-- ---------------------------------------------------------------------------

-- Between the host tooltip and a comparison frame, and between two comparison
-- frames. The same gap the chained anchor carried.
local COMPARE_EDGE_GAP = 3
-- Held clear of the draw area's border, so the client's own clamp never has a
-- reason to move a frame this pass has already placed.
local COMPARE_SCREEN_MARGIN = 4

-- Where each frame was last put, so the 0.10s pass re-points one only when the
-- placement it computes has actually changed.
local comparePlacement = {}

-- GameTooltip owns every hover path; ItemRefTooltip is the chat-link case,
-- where re-anchoring to a hidden GameTooltip would throw the comparison into
-- the corner of the screen.
local COMPARE_HOSTS = { "GameTooltip", "ItemRefTooltip" }

local function CompareVisible(frame)
  if not frame or not frame.IsShown then return false end
  local ok, shown = pcall(frame.IsShown, frame)
  if ok and shown then return true end
  return false
end

local function CompareHost()
  local i
  for i = 1, table.getn(COMPARE_HOSTS) do
    local frame = U.G(COMPARE_HOSTS[i])
    if CompareVisible(frame) then return frame end
  end
  return nil
end

local function CompareScaleRatio(frame)
  local ok, scale = pcall(frame.GetEffectiveScale, frame)
  if not ok or type(scale) ~= "number" or scale <= 0 then return 1 end

  local uiOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
  if not uiOk or type(uiScale) ~= "number" or uiScale <= 0 then return 1 end
  return scale / uiScale
end

-- left, bottom, width and height in UIParent units, or nil for a frame the
-- client cannot measure yet.
local function CompareBox(frame)
  if not frame then return nil end

  local leftOk, left = pcall(frame.GetLeft, frame)
  local bottomOk, bottom = pcall(frame.GetBottom, frame)
  local widthOk, width = pcall(frame.GetWidth, frame)
  local heightOk, height = pcall(frame.GetHeight, frame)
  if not leftOk or not bottomOk or not widthOk or not heightOk then return nil end
  if type(left) ~= "number" or type(bottom) ~= "number" then return nil end
  if type(width) ~= "number" or type(height) ~= "number" then return nil end
  if width <= 0 or height <= 0 then return nil end

  local ratio = CompareScaleRatio(frame)
  return left, bottom, width * ratio, height * ratio
end

-- SetPoint offsets are read in the positioned frame's own units, so the
-- UIParent-space delta goes back through the ratio the box was measured with.
-- The frame's measured corner is checked alongside the remembered offset: a
-- native compare setter can re-anchor a frame this pass already placed, and a
-- cache hit on its own would then leave it wherever the client put it.
local function ApplyComparePlacement(entry, host, hostLeft, hostBottom, x, y)
  local ratio = CompareScaleRatio(entry.frame)
  if ratio <= 0 then ratio = 1 end

  local dx = (x - hostLeft) / ratio
  local dy = (y - hostBottom) / ratio

  local previous = comparePlacement[entry.index]
  if previous and previous.host == host and previous.x == dx and
     previous.y == dy and math.abs(entry.left - x) < 0.5 and
     math.abs(entry.bottom - y) < 0.5 then
    return
  end

  if not pcall(entry.frame.ClearAllPoints, entry.frame) then return end
  if not pcall(entry.frame.SetPoint, entry.frame, "BOTTOMLEFT", host,
               "BOTTOMLEFT", dx, dy) then
    comparePlacement[entry.index] = nil
    return
  end

  comparePlacement[entry.index] = { host = host, x = dx, y = dy }
end

local function PositionCompareTooltips()
  local host = CompareHost()
  if not host then return end

  local hostLeft, hostBottom, hostWidth, hostHeight = CompareBox(host)
  if not hostLeft then return end

  local shown, count = {}, 0
  local i
  for i = 1, 2 do
    local frame = U.G("ShoppingTooltip" .. i)
    if not CompareVisible(frame) then
      comparePlacement[i] = nil
    else
      local left, bottom, width, height = CompareBox(frame)
      if width then
        count = count + 1
        shown[count] = {
          frame = frame, index = i,
          left = left, bottom = bottom, width = width, height = height,
        }
      end
    end
  end
  if count < 1 then return end

  -- The draw area's own borders, not 0 and the width: UIParent is read for its
  -- origin as well as its extent so nothing here assumes it starts at the
  -- screen corner. U.UIWidth/U.UIHeight are the addon's single source for the
  -- extent (core/compat.lua: GetScreenWidth is not in this unit space).
  local uiLeft, uiBottom = 0, 0
  local originOk, originLeft, originBottom = pcall(function()
    return UIParent:GetLeft(), UIParent:GetBottom()
  end)
  if originOk and type(originLeft) == "number" and type(originBottom) == "number" then
    uiLeft, uiBottom = originLeft, originBottom
  end

  local minX = uiLeft + COMPARE_SCREEN_MARGIN
  local maxX = uiLeft + U.UIWidth() - COMPARE_SCREEN_MARGIN
  local minY = uiBottom + COMPARE_SCREEN_MARGIN
  local maxY = uiBottom + U.UIHeight() - COMPARE_SCREEN_MARGIN

  local hostRight = hostLeft + hostWidth
  local hostTop = hostBottom + hostHeight

  local needed = 0
  for i = 1, count do
    needed = needed + COMPARE_EDGE_GAP + shown[i].width
  end

  -- Left first, because that is the side this client puts a comparison on when
  -- it fits. The right border is the fallback, and when neither can take the
  -- whole set the wider of the two is used, so the vertical stack below stays
  -- the last resort it is meant to be.
  local roomLeft = hostLeft - minX
  local roomRight = maxX - hostRight
  local toLeft = true
  if roomLeft < needed and (roomRight >= needed or roomRight > roomLeft) then
    toLeft = false
  end

  local cursor = hostLeft
  if not toLeft then cursor = hostRight end
  local stackTop, stackBottom = hostTop, hostBottom

  for i = 1, count do
    local entry = shown[i]
    local x, y = nil, nil

    if toLeft then
      local candidate = cursor - COMPARE_EDGE_GAP - entry.width
      if candidate >= minX then
        x = candidate
        cursor = candidate
      end
    else
      local candidate = cursor + COMPARE_EDGE_GAP
      if candidate + entry.width <= maxX then
        x = candidate
        cursor = candidate + entry.width
      end
    end

    if x then
      -- Bottom-aligned with the host, as the chained anchor was, then pulled
      -- back inside the draw area here instead of by the client's clamp.
      y = hostBottom
      if y + entry.height > maxY then y = maxY - entry.height end
      if y < minY then y = minY end
    else
      -- No border has room for this frame beside the item, so it goes above
      -- the host, or below it once the band above is used. A frame with no
      -- clear band left is not moved at all: covering the item is the one
      -- outcome this pass exists to prevent.
      y = stackTop + COMPARE_EDGE_GAP
      if y + entry.height <= maxY then
        stackTop = y + entry.height
      else
        y = stackBottom - COMPARE_EDGE_GAP - entry.height
        if y < minY then
          y = nil
        else
          stackBottom = y
        end
      end

      if y then
        x = hostLeft
        if x + entry.width > maxX then x = maxX - entry.width end
        if x < minX then x = minX end
      end
    end

    if x and y then
      ApplyComparePlacement(entry, host, hostLeft, hostBottom, x, y)
    end
  end
end

-- Shared with core/itemslot.lua, which populates the comparison frames for bag
-- and quest-reward hovers and hands placement back here rather than carrying a
-- second copy of the edge arithmetic.
function U.PositionItemCompare()
  PositionCompareTooltips()
end

-- ---------------------------------------------------------------------------
-- Comparison stat scraping
--
-- Both items' stat lines are read straight off the two populated tooltips, so
-- no item database and no table of localized stat names is involved. Only the
-- equipped item's tooltip is written to: the hovered item's own lines are left
-- exactly as the client drew them, so nothing on the new item is recoloured.
--
-- A line is reduced to a locale-independent key by replacing every number in it
-- with a marker and dropping whitespace and case: "+10 Stamina" becomes
-- "+#stamina" carrying the value 10, and the worn item's "+7 Stamina" produces
-- the same key carrying 7. Keys present on both items are compared by value; a
-- key only one side carries counts as that side's full amount.
--
-- Numbered rows that are not stats (durability, level requirements, weapon
-- speed, charges) are skipped. Their templates come from the client's own
-- global strings, so the exclusion follows the game locale instead of a list of
-- English words. No compact evidence names these globals on this client, so
-- every candidate spelling is listed and a missing one is simply skipped; the
-- structural "# / #" rule below is the durability backstop that does not depend
-- on a global existing at all.
-- ---------------------------------------------------------------------------

local COMPARE_IGNORE_GLOBALS = {
  "DURABILITY_TEMPLATE",
  "ITEM_MIN_LEVEL",
  "ITEM_REQ_LEVEL",
  "ITEM_MIN_SKILL",
  "ITEM_REQ_SKILL",
  "ITEM_LEVEL",
  "ITEM_SPELL_CHARGES",
  "SPEED",
}

local compareIgnore

local function StripEscapes(text)
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  return text
end

-- "+10 Stamina" -> "+#stamina", 10. Returns nil for a line carrying no number,
-- which is every flavour, binding, class and slot row.
local function StatLineKey(text)
  if type(text) ~= "string" or text == "" then return nil end
  text = StripEscapes(text)

  local key, total, pos = "", nil, 1
  while true do
    local first, last = string.find(text, "%-?%d+%.?%d*", pos)
    if not first then break end
    key = key .. string.sub(text, pos, first - 1) .. "#"
    total = (total or 0) + (tonumber(string.sub(text, first, last)) or 0)
    pos = last + 1
  end
  if not total then return nil end

  key = string.gsub(key .. string.sub(text, pos), "%s", "")
  if key == "" then return nil end
  return string.lower(key), total
end

-- The ignore templates go through the same normalisation, with their format
-- specifiers standing in for the numbers: "Durability %d / %d" becomes
-- "durability#/#", which is exactly the key "Durability 55 / 55" produces.
local function CompareIgnoreKeys()
  if compareIgnore then return compareIgnore end

  compareIgnore = {}
  local i
  for i = 1, table.getn(COMPARE_IGNORE_GLOBALS) do
    local template = U.G(COMPARE_IGNORE_GLOBALS[i])
    if type(template) == "string" and template ~= "" then
      local key = string.gsub(template, "%%%d?%$?[%-%d%.]*[dsfg]", "#")
      key = string.lower(string.gsub(key, "%s", ""))
      if key ~= "" then table.insert(compareIgnore, key) end
    end
  end
  return compareIgnore
end

local function IsIgnoredStatKey(key)
  -- A pair of numbers around a slash is a durability-style readout, never a
  -- stat. This holds in every locale and without any global string, so it stays
  -- correct even where the template lookup above finds nothing.
  if string.find(key, "#/#", 1, true) then return true end

  local keys = CompareIgnoreKeys()
  local i
  for i = 1, table.getn(keys) do
    if string.find(key, keys[i], 1, true) == 1 then return true end
  end
  return false
end

-- Capitalises each word without touching the rest of it, so a line written in
-- sentence case reads as a stat name ("damage per second" -> "Damage Per
-- Second") while one the client already capitalised keeps its own spelling
-- ("PvE Power"). Only ASCII letters are matched, which is what string.upper
-- can raise here; any other script is left exactly as the client wrote it.
local function TitleCaseWords(text)
  local result = string.gsub(text, "(%a)([%w']*)", function(first, rest)
    return string.upper(first) .. rest
  end)
  return result
end

-- Turns one populated tooltip line into the stat name a change row can be
-- labelled with, or nil for a line whose shape does not name a stat. This
-- client's item tooltips carry a stat in three shapes:
--
--   "+27 Stamina", "1767 Armor"            -- value first, name after
--   "(38.1 damage per second)"             -- the same, inside parentheses
--   "Equip: Increases spell power by 61."  -- a sentence, value last
--
-- The third is trimmed structurally rather than against a word list, because
-- the text is in the *client's* locale, which is not the addon's selected
-- language and may not be a language this file could list words for: the
-- leading token goes because a trigger line always opens with a verb, and a
-- trailing token of one or two characters goes because that is the connector
-- in front of the number ("by", "de", "um") and no stat name is that short.
--
-- Anything that does not fit is left unlabelled and simply never becomes a
-- change row -- a proc line ("Chance on hit: Blasts your target for 40 Fire
-- damage.") carries its number mid-sentence and drops out here, as do the
-- numbered rows that are not stats at all ("Item Level 69", "ID 247109"),
-- whose number does not lead and whose line has no trigger prefix.
local function CompareStatLabel(text)
  if type(text) ~= "string" or text == "" then return nil end

  local body = string.gsub(StripEscapes(text), "^%s+", "")
  body = string.gsub(body, "%s+$", "")

  local trigger
  local _, _, prefixed = string.find(body, "^[^:%d]-:%s*(.+)$")
  if prefixed then
    body = prefixed
    trigger = true
  end

  local _, _, inner = string.find(body, "^%((.+)%)$")
  if inner then body = inner end

  local label
  if trigger then
    local _, _, sentence = string.find(body, "^(.-)%s+[+-]?%d+%.?%d*[%s%p]*$")
    if sentence then
      label = string.gsub(sentence, "^%S+%s+", "")
      label = string.gsub(label, "%s+%S%S?$", "")
    end
  else
    local _, _, named = string.find(body, "^[+-]?%d+%.?%d*%s+(.+)$")
    label = named
  end

  if type(label) ~= "string" then return nil end
  label = string.gsub(label, "^[%s%p]+", "")
  label = string.gsub(label, "[%s%p]+$", "")

  -- A leftover digit means the line was a range or a second value rather than
  -- one stat ("94 - 134 Damage"), and a label with no letter names nothing.
  if label == "" or string.find(label, "%d") then return nil end
  if not string.find(label, "%a") then return nil end
  if string.len(label) > 48 then return nil end
  return TitleCaseWords(label)
end

-- Where a comparison frame's own item text ends. The change summary this
-- module appends below it is a readout of the comparison, not stats the item
-- grants, so a scan has to stop in front of it -- an appended "-27 Stamina"
-- row read back as a stat line would cancel the very stat it reports. The
-- block is located by its own heading rather than by a remembered line index,
-- because the CURRENTLY_EQUIPPED shift can move every line down by one after
-- the block was written.
local function CompareNativeLineCount(name, lineCount)
  local header = U.L("TOOLTIP_COMPARE_SUMMARY")
  if type(header) ~= "string" or header == "" then return lineCount end

  local index
  for index = 3, lineCount do
    local label = U.G(name .. "TextLeft" .. index)
    local textOk, text = false, nil
    if label and label.GetText then
      textOk, text = pcall(label.GetText, label)
    end
    if textOk and text == header then
      -- The heading sits on the second row of the block; the first is the
      -- blank spacer that separates it from the item's own text.
      return index - 2
    end
  end
  return lineCount
end

-- Every numbered line of one populated tooltip, keyed as above, with the
-- readable stat name each key was first seen with and the order they appeared
-- in. Both text sides are read: this client puts armour and damage on the left
-- and the secondary weapon columns on the right.
--
-- Every read goes through U.TooltipLineText, which drops a line region that is
-- not currently shown. That guard is what keeps a right-hand column honest:
-- ClearLines clears left text but only *hides* the right lines
-- (documentation.json / GameTooltip:ClearLines), and AddLine fills the left
-- column alone, so a row inside this tooltip's own NumLines can still hold the
-- right-hand text of whatever was in the frame before it. Read unguarded, the
-- "30 yd range" a spell tooltip leaves on GameTooltipTextRight2 became a
-- "+30 Yd Range" stat on a cloth robe.
local function StatMapFor(name)
  local tooltip = U.G(name)
  if not tooltip or not tooltip.IsShown then return nil end

  local shownOk, shown = pcall(tooltip.IsShown, tooltip)
  if not shownOk or not shown then return nil end

  local countOk, lineCount = pcall(tooltip.NumLines, tooltip)
  if not countOk or type(lineCount) ~= "number" or lineCount < 1 then return nil end

  lineCount = CompareNativeLineCount(name, lineCount)
  if lineCount < 1 then return nil end

  local map, info = {}, { order = {}, labels = {} }
  local index, sideIndex
  for index = 1, lineCount do
    for sideIndex = 1, table.getn(COMPARE_TEXT_SIDES) do
      local text = U.TooltipLineText(name, COMPARE_TEXT_SIDES[sideIndex], index)
      if text then
        local key, value = StatLineKey(text)
        if key and not IsIgnoredStatKey(key) then
          if map[key] == nil then
            table.insert(info.order, key)
            info.labels[key] = CompareStatLabel(text)
          end
          map[key] = (map[key] or 0) + value
        end
      end
    end
  end
  return map, info
end

-- ---------------------------------------------------------------------------
-- "If you replace this item" summary
--
-- Each equipped tooltip closes with the net stat change of swapping it for the
-- hovered item: green where the swap gains, red where it loses. It reads the
-- scraped stat maps above one comparison frame at a time, so every "Currently
-- Equipped" window states what replacing *that* piece would do -- the only
-- reading that stays unambiguous when two rings or two trinkets are on screen
-- at once. This block is the whole of the comparison colouring: the hovered
-- item's tooltip is never tinted, so the green/red only ever appears beside
-- the equipped piece it is describing.
--
-- A stat the hovered item does not carry at all appears here as the full loss.
--
-- Rows are appended with the tooltip's own AddLine. knowledge.json /
-- tooltip.added_lines_do_not_relayout records appended rows failing to grow
-- GameTooltip, which is why modules/itemprice.lua overrides that frame's
-- height instead; these comparison frames are not that case. The
-- CURRENTLY_EQUIPPED shift above already appends its overflow row to them and
-- renders in full, so AddLine is the mechanism with working precedent on this
-- surface -- WORKING_SOURCE from this addon, not a probe result. It is treated
-- as fallible anyway: every row checks that NumLines actually advanced, and a
-- frame that will not take one keeps what it already has rather than being
-- written to blind.
--
-- Every added row goes back through WriteCompareLine because AddLine measures
-- its text against whatever width the new region happens to have
-- (knowledge.json / tooltip.line_geometry_is_fixed_at_settext).
-- ---------------------------------------------------------------------------

-- Long enough for a full set of secondary stats, short enough that a novelty
-- item cannot push the block past the frame's own line pool.
local COMPARE_SUMMARY_MAX_ROWS = 12

local compareSummary = {}

-- "-38.1", "+1767". A fractional delta keeps one decimal, which is what a
-- damage-per-second row carries; everything else reads as a whole number.
local function FormatCompareDelta(value)
  local size = math.abs(value)
  size = math.floor(size * 10 + 0.5) / 10

  local text
  if size == math.floor(size) then
    text = string.format("%d", size)
  else
    text = string.format("%.1f", size)
  end
  return ((value > 0) and "+" or "-") .. text
end

-- The change rows for one comparison frame: the hovered item's own stat order
-- first, then whatever the worn item carries that the hovered one does not.
local function CompareSummaryRows(name)
  local hovered, hoveredInfo = StatMapFor("GameTooltip")
  if not hovered then return nil end

  local worn, wornInfo = StatMapFor(name)
  if not worn then return nil end

  local better = M.itemCompare and M.itemCompare.better
  local worse = M.itemCompare and M.itemCompare.worse
  local accent = M.color and M.color.accent
  if not better or not worse or not accent then return nil end

  local sources = { hoveredInfo, wornInfo }
  local rows, seen = {}, {}
  local sourceIndex, index
  for sourceIndex = 1, table.getn(sources) do
    local order = sources[sourceIndex].order
    for index = 1, table.getn(order) do
      local key = order[index]
      if not seen[key] then
        seen[key] = true

        -- Both sides produce the same label for a shared key; either may be
        -- the one that resolved it, since only one side may carry the line.
        local label = hoveredInfo.labels[key] or wornInfo.labels[key]
        local delta = (hovered[key] or 0) - (worn[key] or 0)
        if label and delta ~= 0 and
           table.getn(rows) < COMPARE_SUMMARY_MAX_ROWS then
          local color = (delta > 0) and better or worse
          table.insert(rows, {
            text = FormatCompareDelta(delta) .. " " .. label,
            r = color[1], g = color[2], b = color[3],
          })
        end
      end
    end
  end

  if table.getn(rows) == 0 then return nil end

  -- One blank row separates the block from the item's own text, the way the
  -- client separates its own tooltip sections, and the heading takes the
  -- accent: it is addon text about the comparison, not item content.
  table.insert(rows, 1, {
    text = " ", r = accent[1], g = accent[2], b = accent[3],
  })
  table.insert(rows, 2, {
    text = U.L("TOOLTIP_COMPARE_SUMMARY"),
    r = accent[1], g = accent[2], b = accent[3],
  })
  return rows
end

-- Empties a range of rows in place. NumLines cannot be lowered without
-- clearing the whole tooltip, so a block that is no longer wanted is blanked
-- rather than removed; the frame keeps that space until the client repopulates
-- it, which it does for every new comparison.
local function ClearCompareSummaryRows(name, fromLine, toLine)
  local lineIndex, sideIndex
  for lineIndex = fromLine, toLine do
    for sideIndex = 1, table.getn(COMPARE_TEXT_SIDES) do
      local label = U.G(name .. "Text" ..
                        COMPARE_TEXT_SIDES[sideIndex] .. lineIndex)
      if label then
        pcall(label.SetText, label, "")
        pcall(label.Hide, label)
      end
    end
  end
end

local function ApplyCompareSummary(index)
  if U.PerfDisabled and U.PerfDisabled("tooltip") then return end

  local name = "ShoppingTooltip" .. index
  local tooltip = U.G(name)
  if not tooltip or not tooltip.IsShown then return end

  local shownOk, shown = pcall(tooltip.IsShown, tooltip)
  if not shownOk or not shown then
    compareSummary[name] = nil
    return
  end

  local countOk, lineCount = pcall(tooltip.NumLines, tooltip)
  if not countOk or type(lineCount) ~= "number" or lineCount < 1 then return end

  -- The same hovered item against the same worn item, with the block still on
  -- the frame: nothing to do. This is every tick but the one where the hover
  -- changes. A native repopulate clears the lines it owns, which shows up here
  -- as the count dropping back to the item's own.
  local subject = (CompareLineText("GameTooltip", 1) or "?") .. "|" ..
                  (CompareLineText(name, 2) or "-")
  local state = compareSummary[name]
  if state and state.subject == subject and state.lines == lineCount then
    return
  end

  -- Where the item's own text ends. A block already on this frame is rewritten
  -- in place instead of being appended to a second time.
  local base = CompareNativeLineCount(name, lineCount)
  if base < 1 then return end

  local rows = CompareSummaryRows(name)
  local count = rows and table.getn(rows) or 0

  local written, rowIndex = 0, nil
  for rowIndex = 1, count do
    local target = base + rowIndex

    local currentOk, current = pcall(tooltip.NumLines, tooltip)
    if not currentOk or type(current) ~= "number" then break end

    if current < target then
      local addOk = pcall(tooltip.AddLine, tooltip, rows[rowIndex].text,
                          rows[rowIndex].r, rows[rowIndex].g,
                          rows[rowIndex].b, false)
      if not addOk then break end

      local grownOk, grown = pcall(tooltip.NumLines, tooltip)
      if not grownOk or type(grown) ~= "number" or grown < target then break end
    end

    local label = U.G(name .. "TextLeft" .. target)
    if not label then break end

    WriteCompareLine(label, rows[rowIndex].text)
    pcall(label.SetTextColor, label, rows[rowIndex].r, rows[rowIndex].g,
          rows[rowIndex].b, 1)
    pcall(label.Show, label)
    U.SetTextShadow(label)

    -- A row that carried a right-hand column for an earlier item would draw it
    -- beside the change readout; these rows are left-only.
    local right = U.G(name .. "TextRight" .. target)
    if right then
      pcall(right.SetText, right, "")
      pcall(right.Hide, right)
    end

    written = rowIndex
  end

  local finalOk, finalLines = pcall(tooltip.NumLines, tooltip)
  if not finalOk or type(finalLines) ~= "number" then
    finalLines = base + written
  end
  if finalLines > base + written then
    ClearCompareSummaryRows(name, base + written + 1, finalLines)
  end

  compareSummary[name] = { subject = subject, lines = finalLines }

  pcall(tooltip.Show, tooltip)
  FitCompareTooltip(tooltip, name)
end

-- ---------------------------------------------------------------------------
-- Player text rebuild
-- ---------------------------------------------------------------------------

-- Vanilla puts the guild on line 2 and pushes the level/race/class line down to
-- 3 for a guilded player, so neither index is fixed. Locate both by content
-- instead of assuming a position this client was never measured to use.
local function RewriteLines(guildName, rankName, localizedRace, localizedClass, r, g, b)
  local numLines = 4
  local countOk, count = pcall(function() return U.G("GameTooltip"):NumLines() end)
  if countOk and type(count) == "number" and count > 0 then numLines = count end

  local i
  for i = 2, numLines do
    local label, text = LineText(i)
    if label and text and text ~= "" then
      if guildName and guildName ~= "" and
         string.find(text, guildName, 1, true) then
        local line = Hex(COLOR.guild) .. "<" .. guildName .. ">|r"
        if type(rankName) == "string" and rankName ~= "" then
          line = line .. " " .. Hex(COLOR.rank) .. "[" .. rankName .. "]|r"
        end
        pcall(label.SetText, label, line)

      elseif (localizedRace and localizedRace ~= "" and
              string.find(text, localizedRace, 1, true)) or
             string.find(text, "(Player)", 1, true) or
             string.find(text, "Level", 1, true) then
        local level = Call("UnitLevel", "mouseover")
        local levelText = (type(level) == "number" and level > 0)
          and tostring(level) or "??"

        local parts = { levelText }
        if localizedRace and localizedRace ~= "" then
          table.insert(parts, localizedRace)
        end
        table.insert(parts, localizedClass)

        pcall(label.SetText, label, table.concat(parts, " "))
        pcall(label.SetTextColor, label, r, g, b)
      end
    end
  end
end

-- Placement is left entirely to the client. A mover was attempted and reverted:
-- repositioning GameTooltip needs ClearAllPoints/SetPoint on a native frame,
-- which no probe on this client covers -- it rests only on UnrealPfUI doing the
-- same thing. The tooltip keeps its native anchor (measured at BOTTOMRIGHT of
-- UIParent, -103, -97 by tooltip.native_read.v1) until that call is verified.

local styledFor

-- `force` restyles regardless of the cached subject. The show/resize hooks
-- below pass it so a freshly populated tooltip is flattened in the same frame
-- it appears, instead of waiting for the next poll.
local function RefreshTooltip(force)
  -- /uui perf tooltip. Every styling path in this module funnels through here,
  -- including the OnShow/OnSizeChanged hooks, so one guard silences the whole
  -- subsystem -- and specifically silences the Restyle -> StyleFrame ->
  -- OnSizeChanged -> Restyle path, which has no re-entrancy guard of its own.
  if U.PerfDisabled and U.PerfDisabled("tooltip") then return end

  local tooltip = U.G("GameTooltip")
  if not tooltip or not tooltip.IsShown then return end

  local shownOk, shown = pcall(tooltip.IsShown, tooltip)
  if not shownOk or not shown then
    styledFor = nil
    U.ClearTooltipItemName()
    return
  end

  local nameLabel, tooltipName = LineText(1)

  -- Re-flatten when the tooltip appears and whenever its subject changes, but
  -- not on every tick: the stock art comes back with new content, and moving
  -- between two units can repopulate without the frame ever hiding. An
  -- unreadable first line falls back to a constant so a tooltip with no name
  -- cannot re-trigger the styling pass on every tick.
  local subject = tooltipName or "?"
  if force or styledFor ~= subject then
    StyleFrame()
    styledFor = subject
  else
    -- The native edge art comes back on its own whenever the tooltip
    -- repopulates, even without its subject changing (e.g. a hovered unit's
    -- tooltip refreshing in place). Re-suppressing it every tick is cheap
    -- and idempotent; skipping it here is what caused the native border to
    -- flash back in between subject changes.
    ClearNativeEdge(tooltip)
    ClearNativeEdge(U.G("GameTooltipStatusBar"))
    -- Item builders can restore their grey divider without changing the
    -- tooltip's first line. Keep the native texture pool suppressed between
    -- full style passes so that late refresh cannot leave the divider visible.
    ClearNativeTextures("GameTooltip")
  end

  -- Before the unit path, which owns the name colour on a unit tooltip and
  -- overwrites this one when both somehow apply to the same frame.
  ApplyItemNameColor()

  if not IsTruthy(Call("UnitIsPlayer", "mouseover")) then return end

  local unitName = Call("UnitName", "mouseover")
  if type(unitName) ~= "string" then return end

  -- Confirm this visible tooltip belongs to the current mouseover before
  -- rewriting any text, so item and action tooltips are never rewritten.
  if not nameLabel or type(tooltipName) ~= "string" then return end
  if tooltipName ~= unitName and
     not string.find(tooltipName, unitName, 1, true) then
    return
  end

  local localizedClass, classToken = Call("UnitClass", "mouseover")
  if type(localizedClass) ~= "string" or type(classToken) ~= "string" then return end

  local r, g, b = M.ClassColor(classToken)
  r = r or 1; g = g or 1; b = b or 1

  pcall(nameLabel.SetTextColor, nameLabel, COLOR.name[1], COLOR.name[2], COLOR.name[3])

  local guildName, rankName = Call("GetGuildInfo", "mouseover")
  local localizedRace = Call("UnitRace", "mouseover")
  RewriteLines(guildName, rankName, localizedRace, localizedClass, r, g, b)

  local bar = U.G("GameTooltipStatusBar")
  if bar and bar.SetStatusBarColor then
    pcall(bar.SetStatusBarColor, bar, r, g, b)
  end

  if healthLabel then
    local hp = Call("UnitHealth", "mouseover")
    local hpMax = Call("UnitHealthMax", "mouseover")
    if type(hp) == "number" and type(hpMax) == "number" and hpMax > 0 then
      pcall(healthLabel.SetText, healthLabel,
            Abbreviate(hp) .. " / " .. Abbreviate(hpMax))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Style triggers
--
-- Polling alone cannot remove the flash. The native frame draws its stock
-- backdrop the moment the tooltip is shown or repopulated, so a 0.10s ticker
-- leaves the tan border on screen for up to a full tick before suppressing it.
-- That is exactly the blink seen when hovering character-sheet items, where
-- SetOwner/SetInventoryItem/Show populate and reveal the frame in one go.
--
-- The styling is therefore driven from the tooltip's own show and resize:
--
--   * A Frame parented to GameTooltip with SetAllPoints. A child's OnShow
--     fires with its parent, so this catches the tooltip appearing. UnrealPfUI
--     drives its whole tooltip module from this same child-frame OnShow on
--     this client (WORKING_SOURCE, modules/tooltip.lua), not runtime-verified
--     here.
--   * The same child's OnSizeChanged, which fires when the tooltip grows to
--     fit new content. This is what catches an already-visible tooltip being
--     repopulated in place -- moving between two item slots never hides the
--     frame, so OnShow alone would miss it. No probe covers OnSizeChanged on
--     a SetAllPoints child of a native frame.
--   * GameTooltip's own OnShow through U.PostHookScript, which appends to the
--     native handler rather than replacing it, as a second same-frame trigger
--     in case the child frame's scripts do not fire.
--
-- The ticker stays as the backstop and as the driver for the live health
-- readout, but it is no longer what makes the tooltip flat.
-- ---------------------------------------------------------------------------

local hookFrame
local compareHookFrames = {}

local function Restyle()
  RefreshTooltip(true)
end

local function InstallTriggers()
  local tooltip = U.G("GameTooltip")
  if not tooltip then return false end

  local installed = false

  if not hookFrame then
    local ok, frame = pcall(CreateFrame, "Frame", nil, tooltip)
    if ok and frame then
      pcall(frame.SetAllPoints, frame, tooltip)
      if pcall(frame.SetScript, frame, "OnShow", Restyle) then
        installed = true
      end
      pcall(frame.SetScript, frame, "OnSizeChanged", Restyle)
      hookFrame = frame
    end
  end

  if U.PostHookScript(tooltip, "OnShow", Restyle) then
    installed = true
  end

  -- A remembered rarity colour belongs to one hover. Dropping it the moment
  -- the tooltip hides is what keeps it from reaching the next subject in the
  -- window before the 0.10s backstop pass notices the frame went away.
  U.PostHookScript(tooltip, "OnHide", function()
    U.ClearTooltipItemName()
  end)

  return installed
end

local function InstallCompareTrigger(index)
  local name = "ShoppingTooltip" .. index
  local tooltip = U.G(name)
  if not tooltip then return false end

  local function RestyleCompare()
    RefreshCompareTooltip(index, true)

    -- A native item setter may keep mutating its tooltip after OnShow returns.
    -- Reapply once on the shared driver's next tick so that late native work
    -- cannot become the final visible state.
    U.DeferOnce("tooltip.compare-restyle." .. index, function()
      RefreshCompareTooltip(index, true)
      ApplyCompareSummary(index)
      -- Last, because the summary rows are what give the frame its final
      -- width: placing it before them would measure a box the player never
      -- sees and could leave the wider one overlapping the item after all.
      PositionCompareTooltips()
    end)
  end

  local installed = false
  if not compareHookFrames[index] then
    local ok, frame = pcall(CreateFrame, "Frame", nil, tooltip)
    if ok and frame then
      pcall(frame.SetAllPoints, frame, tooltip)
      if pcall(frame.SetScript, frame, "OnShow", RestyleCompare) then
        installed = true
      end
      pcall(frame.SetScript, frame, "OnSizeChanged", RestyleCompare)
      compareHookFrames[index] = frame
    end
  end

  if U.PostHookScript(tooltip, "OnShow", RestyleCompare) then
    installed = true
  end
  return installed
end

function TT.OnEnable()
  -- No theme gate: see the note at the head of this file. The tooltip carries
  -- UnrealUI's item comparison, so it is the addon's own frame in Classic WoW
  -- as well as Modern.
  --
  -- Style once up front so the very first tooltip is already flat rather than
  -- relying on a trigger that has not fired yet.
  StyleFrame()

  if not InstallTriggers() then
    U.Debug("tooltip: no show hook installed, styling is poll-driven only")
  end

  local compareInstalled = false
  local i
  for i = 1, 2 do
    if InstallCompareTrigger(i) then compareInstalled = true end
  end
  if not compareInstalled then
    U.Debug("tooltip: no comparison hooks installed, styling is poll-driven only")
  end

  U.RegisterUpdate("tooltip.player-style", 0.10, function()
    RefreshTooltip(false)
    local compareIndex
    for compareIndex = 1, 2 do
      RefreshCompareTooltip(compareIndex, false)
    end
    -- Every comparison frame has been restyled: the summary reads both
    -- populated tooltips and writes into the equipped one.
    for compareIndex = 1, 2 do
      ApplyCompareSummary(compareIndex)
    end
    -- Backstop for the placement, on the same terms as the styling: a native
    -- compare setter can re-anchor a frame after our pass, and the host
    -- tooltip itself can move without either frame being hidden. The pass
    -- re-points nothing while the computed placement still holds.
    PositionCompareTooltips()
  end)
end
