-- UnrealUI: the bag-family design (Dragonflight art).
--
-- One independent module owns how the combined bag (modules/bags.lua), the
-- live bank (modules/bank.lua) and the saved-bank view (modules/bankview.lua)
-- look: metal housing, round backpack portrait, gold title, red octagonal
-- close, dark-grey slot faces on header icons, a metal rule between header
-- and grid, thin-border category boxes, and every spacing number that goes
-- with them. The window modules keep only their own layout and interaction,
-- and ask this module for chrome and metrics, so the three windows cannot
-- drift into three looks. Art and geometry tokens are M.modernWow.bags
-- (core/media.lua).
--
-- Active under `modern-wow` (the "bags" surface) and under `classic-wow`
-- (the "bags" Classic -> Modern WoW module, on by default): by user decision
-- the bag family is one design in both themes, an explicit exception to the
-- theme-scope rule in .claude/rules/unreal-ui-design.md. The choice is read
-- once; a theme change applies after reload, like every other theme switch.

local U = UnrealUI
local M = U.media

local design = {}

function U.ModernWowBagFamilyActive()
  if design.active == nil then
    design.active = type(U.ModernWowSurfaceEnabled) == "function" and
                    U.ModernWowSurfaceEnabled("bags") or false
  end
  return design.active
end

-- ---------------------------------------------------------------------------
-- Metrics
--
-- Each takes the window's own flat-theme value and returns the value the
-- active design uses, so a window writes one call per number and the flat
-- theme keeps its values untouched.
-- ---------------------------------------------------------------------------
design.metrics = {
  -- Header strip height (icon row + separator).
  header = function(base, t) return t.header end,
  -- Gap between grid slots.
  slotGap = function(base, t) return base + t.slotGap end,
  -- Gap between header icons.
  iconGap = function(base, t) return t.actions.gap end,
  -- Window edge to grid, left and right.
  sidePad = function(base, t) return base + t.sidePad end,
  -- Window edge to grid, bottom (windows without a footer).
  bottomPad = function(base, t) return base + t.bottomPad end,
  -- Box edge to slots in a category box.
  sectionInset = function(base, t) return t.section.inset end,
}

function U.ModernWowBagMetric(name, base)
  local metric = design.metrics[name]
  if not metric or not U.ModernWowBagFamilyActive() then return base end
  return metric(base, M.modernWow.bags)
end

-- ---------------------------------------------------------------------------
-- Chrome
-- ---------------------------------------------------------------------------

-- Metal housing over the window's flat panel; call again after a resize.
function U.ModernWowBagHousing(window)
  if not window or type(U.ModernWowMetalFrame) ~= "function" then
    return false
  end
  local ok = U.ModernWowMetalFrame(window)
  if ok then U.SetBackdropShown(window, false) end
  return ok and true or false
end

-- Round backpack portrait overhanging the window's top-left corner.
function U.ModernWowBagPortrait(window)
  if not window or window.uuiModernWowPortrait then return end
  local token = M.modernWow.bags.portrait
  local portrait = window:CreateTexture(nil, "ARTWORK")
  portrait:SetTexture(M.modernWow.texture.bagSlot)
  portrait:SetWidth(token.size)
  portrait:SetHeight(token.size)
  portrait:SetPoint("TOPLEFT", window, "TOPLEFT", token.left, -token.top)
  window.uuiModernWowPortrait = portrait
end

-- The gold title label. The caller anchors it.
function U.ModernWowBagTitle(window, text)
  if not window then return nil end
  if not window.uuiModernWowTitle then
    window.uuiModernWowTitle = U.CreateLabel(window, {
      size = M.fontSize.normal,
      color = M.modernWow.bags.title.color,
      inherits = "GameFontNormal",
    })
  end
  local title = window.uuiModernWowTitle
  if title then
    title:SetText(text or "")
    pcall(title.SetJustifyH, title, "CENTER")
  end
  return title
end

-- Places `window.close` on the header line and gives it the red X cell. The
-- button must be a named global (U.ModernWowDressCloseButton looks it up).
function U.ModernWowBagClose(window, name)
  local close = window and window.close
  if not close then return end
  local token = M.modernWow.bags.close
  close:ClearAllPoints()
  close:SetWidth(token.width)
  close:SetHeight(token.height)
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -token.right, -token.top)
  -- The octagonal red X cell is the whole face; the flat "X" label goes.
  if close.label then close.label:Hide() end
  if type(U.ModernWowDressCloseButton) == "function" then
    U.ModernWowDressCloseButton(name)
  end
end

-- An item slot or header icon on the dark-grey slot face.
function U.ModernWowBagSlot(button, size)
  if not button or type(U.StyleModernWowContainerSlot) ~= "function" then
    return false
  end
  return U.StyleModernWowContainerSlot(button, size)
end

-- A header icon button on the dark-grey slot face, flat backdrop removed.
function U.ModernWowBagHeaderIcon(control, size)
  if not control then return end
  U.ModernWowBagSlot(control, size)
  U.SetBackdropShown(control, false)
end

-- Horizontal separator between the icon row and the grid, cut from the same
-- straight metal run as the window's top edge (M.modernWow.metalFrame) and
-- centred on headerRule.y. Its ends meet the side rails' inner edges (each
-- rail is centred on metal.inset and is its slice width * scale wide), pushed
-- `extend` units into them.
function U.ModernWowBagSeparator(window)
  if not window or window.uuiModernWowHeaderRule then return end
  local token = M.modernWow.bags.headerRule
  local metal = M.modernWow.metalFrame
  local slice = metal.top
  local rule = window:CreateTexture(nil, "BORDER")
  rule:SetTexture(metal.path)
  rule:SetTexCoord(slice.u1 / metal.atlasWidth, slice.u2 / metal.atlasWidth,
                   slice.v1 / metal.atlasHeight, slice.v2 / metal.atlasHeight)
  local height = (slice.v2 - slice.v1) * metal.scale
  local top = -token.y + height / 2
  rule:SetHeight(height)
  local extend = token.extend or 0
  local left = metal.inset +
               (metal.left.u2 - metal.left.u1) / 2 * metal.scale - extend
  local right = metal.inset +
                (metal.right.u2 - metal.right.u1) / 2 * metal.scale - extend
  rule:SetPoint("TOPLEFT", window, "TOPLEFT", left, top)
  rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -right, top)
  window.uuiModernWowHeaderRule = rule
end

-- ---------------------------------------------------------------------------
-- Header search (user requests, 2026-09-24)
--
-- The addon's shared search field (U.CreateSearchBox, core/searchbox.lua) on
-- the header's icon row, for the bag, the live bank and the saved bank. It
-- filters as the user types -- the field reports every change -- and shades
-- every slot whose item name does not contain the text, accents folded
-- (U.SearchFold). The shade is an owned black texture faded with SetAlpha
-- on the texture itself: a parent's alpha does not reach its regions on this
-- client (rendering.parent_alpha_not_propagated) and vertex alpha is no
-- opacity route (textures.vertex_alpha_is_not_an_opacity_route).
--
-- The field has one anchor, LEFT on `after` -- the window's last left-hand
-- header control, centred on the icon row -- with the vertical offset the bag
-- was tuned against in game. Its x offset and width are fitted, while shown,
-- to the lane from `after` to `before` (the first right-hand control; the
-- close cell when there is none): the field takes `widthScale` of it,
-- right-aligned. Measured rather than fixed because every lane changes with
-- what the header shows (Pick Lock, bought bank bags, the note's text, the
-- category view's width). All edges are addon-owned children of one window,
-- so they share a scale.
-- ---------------------------------------------------------------------------

-- Plain, case-insensitive match of an item link's name against a lowercased
-- query. An empty query matches everything, an empty slot nothing else.
function design.SearchMatches(link, query)
  if query == "" then return true end
  if not link then return false end
  local _, _, name = string.find(link, "%[(.-)%]")
  if not name then return false end
  return string.find(U.SearchFold(name), query, 1, true) ~= nil
end

-- The gold icon alert around a hit (match: M.modernWow.bags.search.match,
-- shared by M.slot.search), sized so its line sits on the slot rim, grow`n-- units outside the button. Built on first use; sized on every show, since
-- the bag and bank draw their slots at different sizes.
function design.SearchMark(button, shown, token, grow)
  local mark = button.uuiSearchMark
  if not shown then
    if mark then pcall(mark.Hide, mark) end
    return
  end
  if not mark then
    local ok, texture = pcall(button.CreateTexture, button, nil, "OVERLAY")
    if not ok or not texture then return end
    pcall(texture.SetTexture, texture, token.texture)
    button.uuiSearchMark = texture
    mark = texture
  end
  local okW, width = pcall(button.GetWidth, button)
  width = okW and tonumber(width)
  if not width or width <= 0 then return end
  local rim = width + (grow or 0)
  local size = rim * token.sheet / (token.sheet - 2 * token.line)
  pcall(function()
    mark:ClearAllPoints()
    mark:SetWidth(size)
    mark:SetHeight(size)
    mark:SetPoint("CENTER", button, "CENTER", 0, 0)
  end)
  pcall(mark.SetAlpha, mark, token.alpha or 1)
  pcall(mark.Show, mark)
end

-- dimmed: shaded, its rim and quality glow faded to `borderAlpha` (the shade
-- covers only the button, and both run past its edge). matched: an active
-- query's hit, ringed with the gold icon alert (design.SearchMark; user
-- requests, 2026-09-24). Neither: the slot as drawn with no query. `token`
-- carries dimAlpha / borderAlpha / match: M.modernWow.bags.search for the bag
-- design, M.slot.search for the flat header; grow is the rim's overhang.
function design.SearchShade(button, dimmed, matched, token, grow)
  -- Border alpha is reapplied on every paint rather than behind the state
  -- check below: a slot redraw can create the quality glow after the slot was
  -- dimmed, and it is born at full opacity.
  local borderAlpha = dimmed and token.borderAlpha or 1
  local slot = button.uuiModernWowContainerSlot
  local rim = slot and slot.frame
  local glow, boost = button.uuiGearQualityGlow, button.uuiGearRareBoost
  if rim then pcall(rim.SetAlpha, rim, borderAlpha) end
  if glow then pcall(glow.SetAlpha, glow, borderAlpha) end
  if boost then pcall(boost.SetAlpha, boost, borderAlpha) end

  if button.uuiSearchDimmed == dimmed and
     button.uuiSearchMatched == matched then
    return
  end
  button.uuiSearchDimmed = dimmed
  button.uuiSearchMatched = matched

  design.SearchMark(button, matched, token.match, grow)

  local shade = button.uuiSearchShade
  if not dimmed then
    if shade then pcall(shade.Hide, shade) end
    return
  end
  if not shade then
    local ok, texture = pcall(button.CreateTexture, button, nil, "OVERLAY")
    if not ok or not texture then return end
    texture:SetTexture(M.texture.plain)
    texture:SetVertexColor(0, 0, 0)
    texture:SetAllPoints(button)
    button.uuiSearchShade = texture
    shade = texture
  end
  pcall(shade.SetAlpha, shade, token.dimAlpha)
  pcall(shade.Show, shade)
end

-- spec = {
--   window   the bag-family window (its close cell is the default lane end)
--   name     global name of the field
--   id       update-loop id, unique per window
--   after    frame whose right edge starts the lane (on the icon row)
--   before   frame whose left edge ends it; nil = the close cell
--   each(fn) calls fn(button, link) for every slot button the window draws
-- }
-- Returns a controller -- Start / Stop on show and hide, Paint(button, link)
-- and PaintSlot(button, bag, slot) after a slot is redrawn -- or nil when the
-- field cannot be built. U.ModernWowBagSearch serves the bag design,
-- U.FlatBagSearch the `modern` header; both are this one controller on a
-- different `lane`:
--   shade      dimAlpha / borderAlpha for a miss (design.SearchShade)
--   marked     ring a hit with the gold alert
--   markGrow   the slot rim's overhang past the button, for the ring's size
--   left/right the field's gap to `after` / the lane end
--   widthScale share of the lane the field takes, right-aligned
--   poll       refit interval while shown, seconds
--   y          vertical offset from `after`'s centre line
--   closeInset window right edge to the lane end when there is no `before`
function design.LaneSearch(spec, lane)
  local window = spec.window
  local ctl = { query = "" }

  function ctl.Paint(button, link)
    if not button then return end
    local match = design.SearchMatches(link, ctl.query)
    design.SearchShade(button, not match,
                       lane.marked and match and ctl.query ~= "", lane.shade,
                       lane.markGrow)
  end

  -- Reads the slot's link only while a query is active.
  function ctl.PaintSlot(button, bag, slot)
    if not button then return end
    if ctl.query == "" then
      design.SearchShade(button, false, false, lane.shade, lane.markGrow)
      return
    end
    ctl.Paint(button, U.ContainerSlotLink(bag, slot))
  end

  function ctl.SetQuery(text)
    local query = U.SearchFold(text or "")
    query = string.gsub(query, "^%s+", "")
    query = string.gsub(query, "%s+$", "")
    if query == ctl.query then return end
    ctl.query = query
    spec.each(ctl.Paint)
  end

  function ctl.Place(x)
    ctl.field:ClearAllPoints()
    ctl.field:SetPoint("LEFT", spec.after, "RIGHT", x, lane.y)
  end

  function ctl.Fit()
    local okL, left = pcall(spec.after.GetRight, spec.after)
    local right
    if spec.before then
      local okR, edge = pcall(spec.before.GetLeft, spec.before)
      right = okR and tonumber(edge)
    else
      local okR, edge = pcall(window.GetRight, window)
      right = okR and tonumber(edge) and (tonumber(edge) - lane.closeInset)
    end
    left = okL and tonumber(left)
    if not left or not right then return end
    local span = (right - lane.right) - (left + lane.left)
    local width = math.floor(span * (lane.widthScale or 1) + 0.5)
    if width < 1 or width == ctl.width then return end
    ctl.width = width
    pcall(ctl.field.SetWidth, ctl.field, width)
    pcall(ctl.Place, lane.left + span - width)
    -- The text keeps its tail in view, so a new width repaints it.
    U.PaintSearchBox(ctl.field)
  end

  -- The lane moves with the header, so the fit is kept up while shown.
  function ctl.Tick()
    ctl.Fit()
  end

  function ctl.Start()
    ctl.Fit()
    U.RegisterUpdate(spec.id, lane.poll, ctl.Tick)
  end

  -- Closing the window empties the field, so it never reopens shaded.
  function ctl.Stop()
    U.UnregisterUpdate(spec.id)
    U.ResetSearchBox(ctl.field)
    ctl.SetQuery("")
  end

  local field = U.CreateSearchBox(window, {
    name = spec.name,
    placeholder = U.L("BAGS_SEARCH"),
    onChange = ctl.SetQuery,
  })
  if not field then return nil end
  ctl.field = field
  ctl.Place(lane.left)
  -- Above the window's own header children, so the field takes the click.
  local ok, level = pcall(window.GetFrameLevel, window)
  U.LevelSearchBox(field, ((ok and tonumber(level)) or 1) + 3)
  return ctl
end

function U.ModernWowBagSearch(spec)
  if not spec or not spec.window or not spec.after or
     not U.ModernWowBagFamilyActive() or
     type(U.CreateSearchBox) ~= "function" then
    return nil
  end
  local token = M.modernWow.bags
  local iconMiddle = token.actions.top + token.actions.height / 2
  local closeMiddle = token.close.top + token.close.height / 2
  return design.LaneSearch(spec, {
    shade = token.search, marked = true, markGrow = token.slot.grow,
    left = token.search.left, right = token.search.right,
    widthScale = token.search.widthScale, poll = token.search.poll,
    y = iconMiddle - closeMiddle + (token.search.lift or 0),
    closeInset = token.close.right + token.close.width,
  })
end

-- ---------------------------------------------------------------------------
-- Flat header search (`modern` theme; user requests, 2026-09-24)
--
-- The same field and lane as the bag design, on the flat header's icon row:
-- the bag's money readout moves to the footer (as the bag design has it), so
-- the lane runs from the last icon to the close button. Nothing of
-- M.modernWow is read on this path (M.slot.search). A hit is ringed with the
-- same gold alert (user request, 2026-09-24), shared by reference in
-- M.slot.search.match as the talent advisor shares its marks.
-- ---------------------------------------------------------------------------
function U.FlatBagSearchWanted()
  return type(U.GetActiveThemeStyle) == "function" and
         U.GetActiveThemeStyle() == "modern" and
         type(U.CreateSearchBox) == "function"
end

function U.FlatBagSearch(spec)
  if not spec or not spec.window or not spec.after or
     not U.FlatBagSearchWanted() then
    return nil
  end
  local token = M.slot.search
  return design.LaneSearch(spec, {
    shade = token, marked = true, markGrow = 0,
    left = token.left, right = token.right,
    widthScale = token.widthScale, poll = token.poll,
    y = 0,
    closeInset = M.slot.padding + M.slot.icon,
  })
end

-- Category box: the thin-border eight-slice from the one shared builder (as
-- the talent panels and Quest Log count box draw it) over a dark bed. The
-- builder draws the right side as the left mirrored, because the set's
-- authored right pieces do not meet the mirrored bottom-right corner (user
-- report, 2026-09-23; rules/unreal-ui-design.md, ThinBorder rim). Every
-- piece is anchored to the box, so a resize needs no redraw.
function U.ModernWowBagSection(box)
  if not box or box.uuiModernWowSection then return false end
  local spec = M.modernWow.bags.section

  local fillOk, fill = pcall(box.CreateTexture, box, nil, "BACKGROUND")
  if not fillOk or not fill then return false end
  local ok = pcall(function()
    fill:SetTexture(M.texture.plain)
    fill:SetVertexColor(M.Unpack(spec.fill))
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", spec.fillInset, -spec.fillInset)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -spec.fillInset,
                  spec.fillInset)
  end)
  if not ok or type(U.ModernWowBuildThinBorder) ~= "function" or
     not U.ModernWowBuildThinBorder(box, spec.edge) then
    return false
  end

  U.SetBackdropShown(box, false)
  box.uuiModernWowSection = true
  return true
end
