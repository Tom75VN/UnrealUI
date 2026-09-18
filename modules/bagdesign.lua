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

-- Category box: the authored thin-border eight-slice (as the talent panels
-- and Quest Log count box draw it) over a dark bed. The art ships no
-- bottom-right corner, so the bottom-left one is mirrored into it. Every
-- piece is anchored to the box, so a resize needs no redraw.
function U.ModernWowBagSection(box)
  if not box or box.uuiModernWowSection then return false end
  local spec = M.modernWow.bags.section
  local paths, edge = spec.border, spec.edge

  local function Piece(layer, path, width, height)
    local ok, texture = pcall(box.CreateTexture, box, nil, layer)
    if not ok or not texture then return nil end
    pcall(texture.SetTexture, texture, path)
    if width then pcall(texture.SetWidth, texture, width) end
    if height then pcall(texture.SetHeight, texture, height) end
    return texture
  end

  local fill = Piece("BACKGROUND", M.texture.plain)
  local topLeft = Piece("BORDER", paths.topLeft, edge, edge)
  local topRight = Piece("BORDER", paths.topRight, edge, edge)
  local bottomLeft = Piece("BORDER", paths.bottomLeft, edge, edge)
  local bottomRight = Piece("BORDER", paths.bottomLeft, edge, edge)
  local top = Piece("BORDER", paths.top, nil, edge)
  local bottom = Piece("BORDER", paths.bottom, nil, edge)
  local left = Piece("BORDER", paths.left, edge, nil)
  local right = Piece("BORDER", paths.right, edge, nil)
  if not (fill and topLeft and topRight and bottomLeft and bottomRight and
          top and bottom and left and right) then
    return false
  end

  local ok = pcall(function()
    fill:SetVertexColor(M.Unpack(spec.fill))
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", spec.fillInset, -spec.fillInset)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -spec.fillInset,
                  spec.fillInset)
    bottomRight:SetTexCoord(1, 0, 0, 1)
    topLeft:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    topRight:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    bottomLeft:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    bottomRight:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
  end)
  if not ok then return false end

  U.SetBackdropShown(box, false)
  box.uuiModernWowSection = true
  return true
end
