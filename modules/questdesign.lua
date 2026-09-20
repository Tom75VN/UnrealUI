-- unrealUI :: modules/questdesign.lua
--
-- The quest giver's Dragonflight design (Modern WoW), as one independent
-- module, for the two windows a quest-giver conversation opens (user requests,
-- 2026-09-19):
--
--   * QuestFrame  -- offering, accepting and turning in one quest, and the
--                    greeting list of an NPC that only gives quests;
--   * GossipFrame -- an NPC with gossip or several quests, whose option list
--                    leads into QuestFrame.
--
-- They are the NPC dialogs taken off the classic-wow native path under this
-- theme; merchant, trainer and the mailbox stay native
-- (rules/unreal-ui-design.md). Both are the same 384x512 stock window, and
-- DF-main dresses both identically (ChangeQuestFrame / ChangeGossipFrame), so
-- one drawing path serves both, driven by a per-window spec below.
--
-- modules/quest.lua and modules/gossip.lua own their window's behaviour --
-- rows and their glyphs, reward hooks, refresh hooks -- and ask this file for
-- the themed drawing:
--
--   * the 384x512 paperdoll quadrants, NPC portrait in the gold ring and red
--     close button (U.ModernWowQuestDialogChrome, modules/modernwow.lua);
--   * DF-main's quest parchment in the quadrants' inner recess: the top-left
--     page of questbackgroundparchment, the only cell DF-main draws, for
--     every panel of both windows;
--   * beside it, flush right, the dark scrollbar channel cut by texture
--     coordinates from DF-main's ui-questlogdualpane-right, holding the
--     shared Modern WoW scrollbar (core/modernwowscrollbar.lua);
--   * the native scroll frames over the page;
--   * the measured 128RedButton action buttons along the page's bottom;
--   * parchment ink for every string on the page.
--
-- Active under `modern-wow` only, gated by its `questdialog` surface. Read
-- once, like every theme choice. Every entry point is a safe no-op while this
-- design is not the one drawn, so the owning modules call them freely.
--
-- WORKING_SOURCE, not runtime-verified: the child names below are the ones
-- modules/quest.lua and modules/gossip.lua already address (UnrealPfUI
-- gossipquest.lua and the live /uui questtext dump). query_compat.py has no
-- QuestFrame or GossipFrame geometry.
--
-- Local budget: everything hangs off one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local design = {
  SURFACE = "questdialog",
  active = nil,
  WHITE = { 1, 1, 1, 1 },
  -- Bound windows by key ("quest", "gossip").
  windows = {},
  specs = {
    quest = {
      portrait = "QuestFramePortrait",
      close = "QuestFrameCloseButton",
      title = "QuestFrameNpcNameText",
      panels = {
        "QuestFrameGreetingPanel", "QuestFrameDetailPanel",
        "QuestFrameProgressPanel", "QuestFrameRewardPanel",
      },
      scrolls = {
        "QuestGreetingScrollFrame", "QuestDetailScrollFrame",
        "QuestProgressScrollFrame", "QuestRewardScrollFrame",
      },
      -- Stock action buttons by side of the bed. Each panel shows one of each.
      left = {
        "QuestFrameAcceptButton",
        "QuestFrameCompleteButton",
        "QuestFrameCompleteQuestButton",
      },
      right = {
        "QuestFrameDeclineButton",
        "QuestFrameGoodbyeButton",
        "QuestFrameCancelButton",
        "QuestFrameGreetingGoodbyeButton",
      },
      -- Section headings on the page: the Quest Log details page's heading
      -- typography (modules/quest.lua ApplyNativeHeadingFonts uses the same
      -- list for the native window).
      headings = {
        "QuestTitleText",
        "QuestProgressTitleText",
        "QuestRewardTitleText",
        "QuestProgressRequiredItemsText",
        "QuestDetailObjectiveTitleText",
        "QuestDetailRewardTitleText",
        "QuestRewardRewardTitleText",
        "CurrentQuestsText",
        "AvailableQuestsText",
      },
      items = { "QuestProgressItem", "QuestDetailItem", "QuestRewardItem" },
    },
    gossip = {
      portrait = "GossipFramePortrait",
      close = "GossipFrameCloseButton",
      title = "GossipFrameNpcNameText",
      panels = { "GossipFrameGreetingPanel" },
      scrolls = { "GossipGreetingScrollFrame" },
      left = {},
      right = { "GossipFrameGreetingGoodbyeButton" },
      headings = {},
      items = {},
    },
  },
  ITEMS_PER_PANEL = 9,
}

local function G(name)
  return U.G(name)
end

function design.Active()
  if design.active == nil then
    design.active = type(U.ModernWowSurfaceEnabled) == "function" and
                    U.ModernWowSurfaceEnabled(design.SURFACE) or false
  end
  return design.active
end

function design.Token()
  return M.modernWow.questDialog
end

-- Design-space rectangle -> frame offsets. The art is authored at 384x512,
-- the stock size of both windows, so the scale is 1 unless the client differs.
function design.X(w, x) return x * w.sx end
function design.Y(w, y) return y * w.sy end

-- ---------------------------------------------------------------------------
-- Native chrome
--
-- The window's own regions are all native art except the NPC portrait, which
-- is meaningful content. They are told apart by name (a reader), never by
-- region identity: GetRegions returns fresh wrappers on this client, so a keep
-- table protects nothing (rules/unreal-ui.md). Addon art lives on child
-- frames, so this walk never reaches it. The content panels carry only native
-- parchment and are stripped whole; their scroll frames are left alone.
-- ---------------------------------------------------------------------------
function design.StripNative(w)
  local frame = w.frame
  if frame and frame.GetRegions then
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        local typeOk, objectType = false, nil
        if region and region.GetObjectType then
          typeOk, objectType = pcall(region.GetObjectType, region)
        end
        if typeOk and objectType == "Texture" then
          local nameOk, name = pcall(region.GetName, region)
          if not (nameOk and name == w.spec.portrait) then
            U.HideRegion(region)
          end
        end
      end
    end
  end

  local i
  for i = 1, table.getn(w.spec.panels) do
    U.StripStockTextures(G(w.spec.panels[i]))
  end
end

-- ---------------------------------------------------------------------------
-- Parchment
--
-- One opaque page, drawn as three vertical slices so the torn top and bottom
-- edges keep their authored height and only the plain middle is compressed to
-- the recess. Drawn in the window chrome's own ARTWORK layer, over the
-- quadrants' BACKGROUND: QuestFrame sits at level 1, so the chrome cannot go
-- below it, and a separate frame at the window's level drew UNDER the
-- quadrants (in-game readback 2026-09-19: QuestFrame 1, chrome 2). The chrome
-- already draws below the content panels, so the page does too.
-- ---------------------------------------------------------------------------
-- One texel column drawn as three vertical slices: `cap` rows at each end at
-- their authored height, the plain middle stretched to fill. Used for the
-- parchment page and for the scrollbar channel beside it.
function design.VerticalSlices(w, holder, path, texW, texH, u1, u2, v1, v2,
                               cap, left, width, top, bottom)
  local rows = {
    { v1 = v1, v2 = v1 + cap, y = top, h = cap },
    { v1 = v1 + cap, v2 = v2 - cap, y = top + cap,
      h = (bottom - top) - 2 * cap },
    { v1 = v2 - cap, v2 = v2, y = bottom - cap, h = cap },
  }

  local i
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local texOk, tex = pcall(holder.CreateTexture, holder, nil, "ARTWORK")
    if texOk and tex then
      pcall(function()
        tex:SetTexture(path)
        tex:SetTexCoord(u1 / texW, u2 / texW, row.v1 / texH, row.v2 / texH)
        tex:SetWidth(design.X(w, width))
        tex:SetHeight(design.Y(w, row.h))
        tex:SetPoint("TOPLEFT", w.frame, "TOPLEFT",
                     design.X(w, left), -design.Y(w, row.y))
      end)
    end
  end
end

function design.BuildParchment(w)
  if w.parchment then return end
  local token = design.Token()
  local t = token.parchment
  local path = M.modernWow.texture.questParchment
  if not t or not path then return end

  local holder = type(U.ModernWowWindowChrome) == "function" and
                 U.ModernWowWindowChrome(w.frame) or nil
  if not holder then return end

  design.VerticalSlices(w, holder, path, t.atlas, t.atlas,
                        t.u1, t.u2, t.v1, t.v2, t.edge,
                        t.left, t.width, t.top, t.bottom)

  -- Only the dark scrollbar channel of DF-main's dual-pane Quest Log page,
  -- flush with the recess's right rim; its parchment half is never drawn.
  local c = token.channel
  local channelPath = M.modernWow.texture.questScrollChannel
  if c and channelPath then
    design.VerticalSlices(w, holder, channelPath, c.width, c.height,
                          c.u1, c.u2, c.v1, c.v2, c.cap,
                          c.left, c.u2 - c.u1, c.top, c.bottom)
  end

  design.BuildFooter(w, holder)
  w.parchment = holder
end

-- The darker footer that holds the action buttons, and the Dialog Box
-- separator between it and the page.
function design.BuildFooter(w, holder)
  local token = design.Token()
  local f = token.footer
  local rock = M.modernWow.texture.questFooter
  if f and rock then
    local texOk, tex = pcall(holder.CreateTexture, holder, nil, "ARTWORK")
    if texOk and tex then
      local width, height = f.right - f.left, f.bottom - f.top
      pcall(function()
        tex:SetTexture(rock)
        -- Sampled 1:1 so the rock grain keeps its authored scale.
        tex:SetTexCoord(0, width / f.atlas, 0, height / f.atlas)
        tex:SetVertexColor(f.shade, f.shade, f.shade)
        tex:SetWidth(design.X(w, width))
        tex:SetHeight(design.Y(w, height))
        tex:SetPoint("TOPLEFT", w.frame, "TOPLEFT",
                     design.X(w, f.left), -design.Y(w, f.top))
      end)
    end
  end

  -- Keep the channel's own brackets on its end squares, then lay the dedicated
  -- Dialog Box divider across the page/footer boundary.
  local d = token.divider
  local c = token.channel
  local path = M.modernWow.texture.questScrollChannel
  if not d or not c or not path then return end

  -- Close the channel's two end squares with its own bracket at channel
  -- width: as authored under the bottom square, flipped over the top one.
  local e = token.channelEnds
  if e then
    local rows = e.v2 - e.v1
    local ends = {
      -- Unflipped: the line is (line - v1) rows below the piece's top.
      { v1 = e.v1, v2 = e.v2, top = e.bottomLine - (e.line - e.v1) },
      -- Flipped: the line is (v2 - 1 - line) rows below the piece's top.
      { v1 = e.v2, v2 = e.v1, top = e.topLine - (e.v2 - 1 - e.line) },
    }
    local i
    for i = 1, table.getn(ends) do
      local piece = ends[i]
      local texOk, tex = pcall(holder.CreateTexture, holder, nil, "OVERLAY")
      if texOk and tex then
        pcall(function()
          tex:SetTexture(path)
          tex:SetTexCoord(c.u1 / c.width, c.u2 / c.width,
                          piece.v1 / c.height, piece.v2 / c.height)
          tex:SetWidth(design.X(w, c.u2 - c.u1))
          tex:SetHeight(design.Y(w, rows))
          tex:SetPoint("TOPLEFT", w.frame, "TOPLEFT", design.X(w, c.left),
                       -design.Y(w, piece.top))
        end)
      end
    end
  end
  local barToken = M.modernWow.horizontalBar
  if barToken and type(U.ModernWowHorizontalBar) == "function" then
    local rowH = barToken.height
    local bar = U.ModernWowHorizontalBar(
      holder, design.X(w, d.right - d.left), design.Y(w, rowH), "OVERLAY")
    if bar then
      pcall(function()
        bar:SetPoint("TOPLEFT", w.frame, "TOPLEFT", design.X(w, d.left),
                     -design.Y(w, d.y - rowH / 2))
      end)
      w.horizontalBar = bar
    end
  end
end

-- ---------------------------------------------------------------------------
-- Layout: scroll frames over the page, the scrollbar down its right edge,
-- action buttons along its bottom. Placed once at bind: none of these is
-- re-anchored by the native code, and the action buttons' anchors are handed
-- to the shared red-button placement, so they must not move after that.
-- ---------------------------------------------------------------------------
function design.PlaceScrolls(w)
  local t = design.Token()
  local i
  for i = 1, table.getn(w.spec.scrolls) do
    local name = w.spec.scrolls[i]
    local scroll = G(name)
    if scroll then
      pcall(function()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", w.frame, "TOPLEFT",
                        design.X(w, t.scroll.left), -design.Y(w, t.scroll.top))
      end)
      pcall(scroll.SetWidth, scroll, design.X(w, t.scroll.width))
      pcall(scroll.SetHeight, scroll, design.Y(w, t.scroll.height))

      -- The scroll child keeps its fixed native height, which is taller than
      -- this text area, so even a short quest had that difference to scroll
      -- (user report, 2026-09-19). Sized to the text area, only content that
      -- really runs past it creates range: UpdateScrollChildRect recomputes
      -- the max from the child's overflow (knowledge.json /
      -- skillscroll.first_open_range, FOCUSED_RUNTIME_PROBE).
      local child = G((string.gsub(name, "ScrollFrame$", "ScrollChildFrame")))
      if child then
        pcall(child.SetHeight, child, design.Y(w, t.scroll.height))
      end
      if scroll.UpdateScrollChildRect then
        pcall(scroll.UpdateScrollChildRect, scroll)
      end
    end

    -- User request (2026-09-19): the Modern WoW MinimalScrollBar, the same
    -- shared component as Character > Skills, instead of the native atlas.
    -- The Slider keeps its range, value and scripts; only the drawing and the
    -- thumb are owned (core/modernwowscrollbar.lua).
    local bar = G(name .. "ScrollBar")
    if bar then
      pcall(function()
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", w.frame, "TOPLEFT",
                     design.X(w, t.scrollBar.left),
                     -design.Y(w, t.scrollBar.top))
        bar:SetPoint("BOTTOMLEFT", w.frame, "TOPLEFT",
                     design.X(w, t.scrollBar.left),
                     -design.Y(w, t.scrollBar.bottom))
      end)
      U.StyleModernWowScrollbar(bar, {
        upArrowY = t.scrollBar.upArrowY,
        downArrowY = t.scrollBar.downArrowY and
                     design.Y(w, t.scrollBar.downArrowY) or nil,
      })
      table.insert(w.scrolls, { scroll = scroll, bar = bar })
    end
  end
end

-- MinimalScrollBar's proportional thumb: the page's share of the scroll
-- child. The range changes with every NPC, so this runs on each refresh.
function design.SizeThumbs(w)
  local i
  for i = 1, table.getn(w.scrolls) do
    local entry = w.scrolls[i]
    local scroll = entry.scroll
    -- The range follows this NPC's content, not the previous one's.
    if scroll and scroll.UpdateScrollChildRect then
      pcall(scroll.UpdateScrollChildRect, scroll)
    end
    if scroll and scroll.GetVerticalScrollRange then
      local okRange, range = pcall(scroll.GetVerticalScrollRange, scroll)
      local okHeight, height = pcall(scroll.GetHeight, scroll)
      range = okRange and tonumber(range) or 0
      height = okHeight and tonumber(height) or 0
      if height > 0 then
        U.SetModernWowScrollbarProportion(entry.bar, height, height + range)
      end
    end
  end
end

function design.DressButton(w, button, point, x)
  if not button or button.uuiQuestDesignButton then return end
  button.uuiQuestDesignButton = true

  -- The native UIPanelButton faces come off once, before the red-button art
  -- is added; the button is never walked again after that. Through the
  -- button's own state setters, not a bare region strip: this client keeps
  -- drawing a face after SetTexture(nil), which left the native button showing
  -- under the red one (USER_CONFIRMED_INGAME 2026-09-19).
  U.ClearStockButtonFaces(button, {})

  -- The shared placement adds the red button's lift to this y.
  local t = design.Token()
  local lift = M.modernWow.button128Red and M.modernWow.button128Red.lift or 0
  local y = design.Y(w, t.designHeight - t.buttons.bottom) - lift
  if type(U.ModernWowQuestActionButton) == "function" then
    U.ModernWowQuestActionButton(button, point, w.frame, x, y)
  end
end

function design.PlaceButtons(w)
  local t = design.Token()
  local i
  for i = 1, table.getn(w.spec.left) do
    design.DressButton(w, G(w.spec.left[i]), "BOTTOMLEFT",
                       design.X(w, t.buttons.left))
  end
  for i = 1, table.getn(w.spec.right) do
    design.DressButton(w, G(w.spec.right[i]), "BOTTOMRIGHT",
                       -design.X(w, t.designWidth - t.buttons.right))
  end
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

-- Body ink on every string under the window, shadow off (a black shadow under
-- brown ink reads as a smear on parchment). Same walk as
-- U.ForceStockTextWhite, except that a SimpleHTML -- whose SetTextColor takes
-- 0..255 channels on this client -- also gets the ink rather than white.
function design.InkWalk(object, ink, depth)
  if not object or depth > 8 then return end

  if object.GetObjectType and object.SetTextColor then
    local typeOk, objectType = pcall(object.GetObjectType, object)
    if typeOk and objectType == "SimpleHTML" then
      pcall(object.SetTextColor, object,
            ink[1] * 255, ink[2] * 255, ink[3] * 255)
    end
  end

  if object.GetRegions then
    local ok, regions = pcall(function() return { object:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        if region and region.GetObjectType then
          local typeOk, objectType = pcall(region.GetObjectType, region)
          if typeOk and objectType == "FontString" then
            U.SetStockFont(region, M.fontSize.normal, ink)
            U.ClearTextShadow(region)
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
        design.InkWalk(children[i], ink, depth + 1)
      end
    end
  end
end

function design.ApplyHeadings(w)
  local ink = M.modernWow.parchmentInk.heading
  local i
  for i = 1, table.getn(w.spec.headings) do
    local object = G(w.spec.headings[i])
    if object then
      -- Same sequence as the Quest Log details page under modern-wow.
      U.SetStockFont(object, M.fontSize.large, ink)
      U.SetFont(object, M.fontSize.large, nil, nil, true)
      U.ClearTextShadow(object)
      U.FitLineToText(object)
    end
  end
end

-- The NPC name sits on the dark title strip, not the page: warm gold title.
function design.ApplyTitle(w)
  local name = G(w.spec.title)
  if not name then return end
  local t = design.Token().title
  U.SetStockFont(name, M.fontSize.normal, t.color)
  pcall(function()
    name:ClearAllPoints()
    name:SetPoint("CENTER", w.frame, "TOPLEFT",
                  design.X(w, t.x), -design.Y(w, t.y))
  end)
end

-- Narrows one native item slot to the page's column width, once (the shared
-- U.FitQuestItemSlot, which the Modern WoW Quest Log uses too).
function design.FitItem(w, name)
  U.FitQuestItemSlot(name, design.X(w, design.Token().items.width))
end

-- Item names and counts sit on the native item cell's dark name frame, not
-- the page, so they stay light; rewards take their rarity colour on top.
function design.ApplyItemText(w)
  local p
  for p = 1, table.getn(w.spec.items) do
    local prefix = w.spec.items[p]
    local i
    for i = 1, design.ITEMS_PER_PANEL do
      local name = prefix .. i
      design.FitItem(w, name)
      local label = G(name .. "Name")
      if label then
        U.SetStockFont(label, M.fontSize.normal, design.WHITE)
        if prefix ~= "QuestProgressItem" then
          U.ColorQuestRewardName(G(name), label, "giver", i)
        end
      end
      local count = G(name .. "Count")
      if count then U.SetStockFont(count, M.fontSize.small, design.WHITE) end
    end
  end
end

-- Label and face follow the button's real enabled state (the progress panel's
-- Complete button is disabled until the quest can be handed in).
function design.RefreshButton(button)
  if not button or not button.uuiQuestDesignButton then return end
  local enabled = true
  if button.IsEnabled then
    local ok, value = pcall(button.IsEnabled, button)
    if ok then enabled = value and true or false end
  end
  if type(U.ModernWowSetRedButtonDisabled) == "function" then
    U.ModernWowSetRedButtonDisabled(button, not enabled)
  end
  if button.GetFontString then
    local ok, label = pcall(button.GetFontString, button)
    if ok and label then
      U.SetStockFont(label, M.fontSize.normal,
                     enabled and M.color.text or M.color.textDim)
      U.CenterButtonLabel(label, button)
    end
  end
end

function design.RefreshButtons(w)
  local i
  for i = 1, table.getn(w.spec.left) do
    design.RefreshButton(G(w.spec.left[i]))
  end
  for i = 1, table.getn(w.spec.right) do
    design.RefreshButton(G(w.spec.right[i]))
  end
end

-- ---------------------------------------------------------------------------
-- Entry points for modules/quest.lua and modules/gossip.lua. `key` names the
-- window ("quest" when omitted, the original caller's shape).
-- ---------------------------------------------------------------------------

function U.ModernWowQuestDialogActive()
  return design.Active()
end

-- One-time build, once the native window exists. `panel` is the retained
-- UnrealUI panel: its flat drawing comes off, and it stays as the close
-- button's anchor sized to the art's visible bounds.
function U.ModernWowQuestDialogBind(frame, panel, key)
  key = key or "quest"
  local spec = design.specs[key]
  if not design.Active() or not frame or not spec or design.windows[key] then
    return false
  end
  local w = {
    key = key,
    spec = spec,
    frame = frame,
    panel = panel,
    sx = 1,
    sy = 1,
    scrolls = {},
  }
  design.windows[key] = w

  local t = design.Token()
  local okW, width = pcall(frame.GetWidth, frame)
  local okH, height = pcall(frame.GetHeight, frame)
  width = okW and tonumber(width) or 0
  height = okH and tonumber(height) or 0
  if width > 0 then w.sx = width / t.designWidth end
  if height > 0 then w.sy = height / t.designHeight end

  local art = t.art
  pcall(frame.SetHitRectInsets, frame, design.X(w, art.left),
        design.X(w, art.right), design.Y(w, art.top), design.Y(w, art.bottom))
  if panel then
    pcall(function()
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", frame, "TOPLEFT",
                     design.X(w, art.left), -design.Y(w, art.top))
      panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
                     -design.X(w, art.right), design.Y(w, art.bottom))
    end)
    local close = G(spec.close)
    if close then
      pcall(function()
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                       -design.X(w, t.close.right), -design.Y(w, t.close.top))
      end)
    end
  end

  -- Native art off before any addon art goes on. The parchment follows the
  -- chrome, which the first refresh creates.
  design.StripNative(w)
  design.PlaceScrolls(w)
  design.PlaceButtons(w)
  return true
end

-- The full themed pass, run by the owning module on every native refresh.
-- Rows and reward hooks stay with the owning module and run after this.
function U.ModernWowQuestDialogRefresh(key)
  local w = design.Active() and design.windows[key or "quest"]
  if not w then return false end
  design.StripNative(w)
  if type(U.ModernWowQuestDialogChrome) == "function" then
    U.ModernWowQuestDialogChrome(w.frame, w.panel, G(w.spec.portrait),
                                 w.spec.close)
  end
  design.BuildParchment(w)
  design.InkWalk(w.frame, M.modernWow.parchmentInk.body, 0)
  design.ApplyHeadings(w)
  design.ApplyTitle(w)
  design.ApplyItemText(w)
  design.RefreshButtons(w)
  design.SizeThumbs(w)
  return true
end

-- Row label colours on parchment, or nil when this design is off.
function U.ModernWowQuestDialogRowColors()
  if not design.Active() then return nil end
  return design.Token().row
end
