-- unrealUI :: core/style.lua
--
-- Shared visual primitives: backdrops, borders, status bars and labels.
-- pfUI modern is the visual baseline -- near-black panels, one thin dark
-- outline, flat bar fills -- but none of pfUI's structure is reproduced here.

local U = UnrealUI
local M = U.media

-- ---------------------------------------------------------------------------
-- Borders
--
-- knowledge.json / rendering.backdrop_edge_fractional_not_rasterized: the
-- backdrop edgeFile is retained but a fractional edgeSize is not reliably
-- rasterised, so pfUI's thin outlines simply disappear on this client. The
-- background fill is unaffected.
--
-- unrealUI therefore keeps SetBackdrop for the fill only and draws every
-- outline from four plain textures, which behavior.json /
-- textures.pfui_bar_path.v1 verifies as a working drawing path. An outline is
-- never asked to be thinner than one full draw unit, because the sub-unit
-- request is exactly what fails to appear.
--
-- At the recorded 1920-wide display UIParent measures 1365.33 units, so one
-- physical pixel is ~0.71 units. Rounding up to 1 is the deliberate trade:
-- a slightly heavier border that renders beats a hairline that does not.
-- ---------------------------------------------------------------------------
local EDGES = {
  { "TOPLEFT",    "TOPRIGHT",    "horizontal" },
  { "BOTTOMLEFT", "BOTTOMRIGHT", "horizontal" },
  { "TOPLEFT",    "BOTTOMLEFT",  "vertical"   },
  { "TOPRIGHT",   "BOTTOMRIGHT", "vertical"   },
}

function U.BorderSize()
  return 1
end

-- Builds (or resizes) the four outline textures on a frame.
function U.CreateBorder(frame, thickness)
  if not frame or not frame.CreateTexture then return nil end

  thickness = tonumber(thickness) or U.BorderSize()
  if thickness < 1 then thickness = 1 end

  if not frame.uuiEdges then
    local edges, i = {}, nil
    for i = 1, table.getn(EDGES) do
      local anchor = EDGES[i]
      local edge = frame:CreateTexture(nil, "OVERLAY")
      edge:SetTexture(M.texture.plain)
      -- Start dark rather than at the texture's own white, so a frame is never
      -- outlined in white even for the one frame before it is tinted.
      U.SetColor(edge, M.Unpack(M.color.border))
      edge:SetPoint(anchor[1], frame, anchor[1], 0, 0)
      edge:SetPoint(anchor[2], frame, anchor[2], 0, 0)
      edges[i] = edge
    end
    frame.uuiEdges = edges
  end

  local i
  for i = 1, table.getn(EDGES) do
    if EDGES[i][3] == "horizontal" then
      frame.uuiEdges[i]:SetHeight(thickness)
    else
      frame.uuiEdges[i]:SetWidth(thickness)
    end
  end

  return frame.uuiEdges
end

function U.SetBorderColor(frame, r, g, b, a)
  if not frame or not frame.uuiEdges then return end
  local i
  for i = 1, table.getn(frame.uuiEdges) do
    U.SetColor(frame.uuiEdges[i], r, g, b, a)
  end
end

-- ---------------------------------------------------------------------------
-- Backdrops
-- ---------------------------------------------------------------------------

-- Applies the unrealUI panel look to an existing frame: flat fill plus the
-- explicit outline. Returns the frame for chaining.
function U.CreateBackdrop(frame, options)
  if not frame then return frame end
  options = options or {}

  local background = options.background or M.color.background
  local border = options.border or M.color.border

  if frame.SetBackdrop then
    -- Only the fill is taken from the backdrop; edgeFile is deliberately
    -- omitted rather than requested and left invisible.
    local ok = pcall(frame.SetBackdrop, frame, {
      bgFile = M.texture.plain,
      tile = false,
      tileSize = 0,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if ok then
      pcall(frame.SetBackdropColor, frame, M.Unpack(background))
      -- knowledge.json / rendering.setbackdrop_keeps_native_edge_art
      -- (BEHAVIOR_VERIFIED, USER_CONFIRMED_INGAME): a backdrop table that
      -- omits edgeFile replaces the fill but leaves the frame's stock edge
      -- art drawing on top. It is not an enumerable region, so it survives
      -- StripTextures too; only SetBackdropBorderColor removes it.
      pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
    else
      -- No usable backdrop: fall back to a plain fill texture so the panel is
      -- still opaque rather than transparent.
      if not frame.uuiFill and frame.CreateTexture then
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetTexture(M.texture.plain)
        fill:SetAllPoints(frame)
        frame.uuiFill = fill
      end
      U.SetColor(frame.uuiFill, M.Unpack(background))
    end
  end

  if options.border ~= false then
    U.CreateBorder(frame, options.thickness)
    U.SetBorderColor(frame, M.Unpack(border))
  end

  return frame
end

function U.SetBackgroundColor(frame, r, g, b, a)
  if not frame then return end
  if frame.uuiFill then
    U.SetColor(frame.uuiFill, r, g, b, a)
    return
  end
  if frame.SetBackdropColor then
    pcall(frame.SetBackdropColor, frame,
          tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 1)
  end
end

-- Creates a new styled panel.
function U.CreatePanel(parent, options)
  local frame = CreateFrame("Frame", (options and options.name) or nil,
                            parent or UIParent)
  frame:SetWidth((options and options.width) or 100)
  frame:SetHeight((options and options.height) or 20)
  return U.CreateBackdrop(frame, options)
end

-- ---------------------------------------------------------------------------
-- Status bars
--
-- Not the client's StatusBar widget. unrealUI's first unit frames built one,
-- created the fill as a texture object and handed it to SetStatusBarTexture,
-- and the result on screen was a fixed green block hanging outside the frame's
-- bounds instead of a bar: the fill kept its creation tint and was not laid out
-- from the bar's value at all.
--
-- UnrealPfUI does not use the widget either. api/ui-widgets.lua builds every
-- bar from a plain frame plus two textures and computes the fill extent itself
-- by re-anchoring the fill's far corner (CreateStatusBar / DisplayValue). That
-- is a working implementation on this client, so unrealUI matches it -- and it
-- only needs plain textures, which behavior.json / textures.pfui_bar_path.v1
-- verifies.
--
-- The object keeps the Vanilla method names (SetMinMaxValues / SetValue /
-- GetValue / GetMinMaxValues / SetOrientation) so callers read like normal bar
-- code. They are unrealUI's own functions on a plain Frame, not overrides of a
-- client widget: a Frame has none of these to begin with.
--
-- knowledge.json / statusbar.native_widget_fill_not_laid_out.
-- ---------------------------------------------------------------------------
local function UpdateStatusBarFill(bar)
  local fill = bar.uuiFillTexture
  if not fill then return end

  local size
  if bar.uuiVertical then
    size = tonumber(bar:GetHeight())
  else
    size = tonumber(bar:GetWidth())
  end
  size = size or 0

  local range = (bar.uuiMax or 0) - (bar.uuiMin or 0)
  local extent = 0
  if range > 0 and size > 0 then
    extent = size / range * ((bar.uuiValue or 0) - (bar.uuiMin or 0))
  end

  if extent < 0 then extent = 0 end
  if extent > size then extent = size end

  -- A zero-extent texture is hidden rather than left at zero size: a texture
  -- asked for no width is exactly the case that rendered as a stray block.
  if extent <= 0 then
    fill:Hide()
    return
  end

  fill:ClearAllPoints()
  if bar.uuiVertical then
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(size - extent))
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  else
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(size - extent), 0)
  end
  fill:Show()
end

local function BarSetMinMaxValues(self, minimum, maximum)
  self.uuiMin = tonumber(minimum) or 0
  self.uuiMax = tonumber(maximum) or 0
  UpdateStatusBarFill(self)
end

local function BarGetMinMaxValues(self)
  return self.uuiMin, self.uuiMax
end

local function BarSetValue(self, value)
  self.uuiValue = tonumber(value) or 0
  UpdateStatusBarFill(self)
end

local function BarGetValue(self)
  return self.uuiValue
end

local function BarSetOrientation(self, mode)
  self.uuiVertical = (type(mode) == "string" and string.upper(mode) == "VERTICAL")
  UpdateStatusBarFill(self)
end

function U.CreateStatusBar(parent, options)
  options = options or {}

  local bar = CreateFrame("Frame", options.name, parent or UIParent)
  bar:SetWidth(options.width or 100)
  bar:SetHeight(options.height or 12)

  -- Background sits behind the fill and shows the depleted portion.
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(M.texture.plain)
  bg:SetAllPoints(bar)
  U.SetColor(bg, M.Unpack(options.background or M.color.healthBg))
  bar.uuiBackground = bg

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(M.texture.plain)
  U.SetColor(fill, M.Unpack(options.color or M.color.health))
  bar.uuiFillTexture = fill

  bar.uuiMin, bar.uuiMax, bar.uuiValue = 0, 1, 1
  bar.uuiVertical = (options.orientation == "VERTICAL")

  bar.SetMinMaxValues = BarSetMinMaxValues
  bar.GetMinMaxValues = BarGetMinMaxValues
  bar.SetValue = BarSetValue
  bar.GetValue = BarGetValue
  bar.SetOrientation = BarSetOrientation

  UpdateStatusBarFill(bar)
  return bar
end

function U.SetStatusBarColor(bar, r, g, b, a)
  if not bar or not bar.uuiFillTexture then return end
  U.SetColor(bar.uuiFillTexture, r, g, b, a)
end

-- ---------------------------------------------------------------------------
-- Text
--
-- knowledge.json / fonts.stretched_justification_ignored: horizontal
-- justification can be ignored on a region stretched between two corners.
-- Labels are therefore anchored to the single edge they belong to; callers
-- should place them with one SetPoint, not two.
-- ---------------------------------------------------------------------------
-- options.inherits names a stock font object to inherit from. It matters when
-- U.ResolveFont finds no path this client will resize: a fontstring created
-- with no template and no working SetFont has no font at all, and inheriting a
-- stock object is the only thing guaranteeing the text appears. The template
-- form is attempted first and dropped if this client rejects the extra
-- argument, since neither shape is verified in the compact DB.
function U.CreateLabel(parent, options)
  if not parent or not parent.CreateFontString then return nil end
  options = options or {}

  local layer = options.layer or "OVERLAY"
  local ok, label = false, nil

  if options.inherits then
    ok, label = pcall(parent.CreateFontString, parent, options.name, layer,
                      options.inherits)
  end

  if not ok or not label then
    ok, label = pcall(parent.CreateFontString, parent, options.name, layer)
  end
  if not ok or not label then return nil end

  U.SetFont(label, options.size or M.fontSize.normal, options.flags)

  local color = options.color or M.color.text
  pcall(label.SetTextColor, label, M.Unpack(color))

  if options.justify then
    pcall(label.SetJustifyH, label, options.justify)
  end

  -- A FontString with no explicit width grows to the full text width and can
  -- draw beyond its owning panel. Settings widgets pass their available width
  -- through this shared option so both normal words and long, unbroken values
  -- stay inside the interface. UnrealPfUI uses SetNonSpaceWrap on this client;
  -- keep the call guarded because the compact runtime DB has no direct record.
  if options.width then
    pcall(label.SetWidth, label, options.width)
  end
  if options.height then
    pcall(label.SetHeight, label, options.height)
  end
  if options.nonSpaceWrap ~= nil and label.SetNonSpaceWrap then
    pcall(label.SetNonSpaceWrap, label, options.nonSpaceWrap and true or false)
  end

  return label
end

-- ---------------------------------------------------------------------------
-- Buttons
--
-- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
-- accepts SetText without ever showing a FontString, so the label is a region
-- unrealUI creates and owns rather than the Button's own text.
--
-- Button is also the widget type this client is known to route mouse input to
-- (frames.movable_drag_requires_button_handle), so it is used even where a
-- clickable Frame would do in Vanilla.
-- ---------------------------------------------------------------------------
function U.CreateButton(parent, options)
  options = options or {}

  local width = options.width or 100
  local height = options.height or 22

  local button = CreateFrame("Button", options.name, parent or UIParent)
  button:SetWidth(width)
  button:SetHeight(height)
  pcall(button.EnableMouse, button, true)

  U.CreateBackdrop(button, options)

  local label = U.CreateLabel(button, {
    size = options.size or M.fontSize.normal,
    color = options.textColor or M.color.text,
    inherits = "GameFontNormal",
    width = math.max(1, width - 8),
    height = math.max(1, height - 4),
    nonSpaceWrap = true,
  })
  if label then
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(options.text or "")
  end
  button.label = label

  -- Closures over `button`, never `this`: scripts.handler_arguments_direct
  -- means the handler argument shape is not guaranteed.
  button:SetScript("OnEnter", function()
    U.SetBorderColor(button, M.Unpack(options.hoverBorder or M.color.moverEdge))
  end)
  button:SetScript("OnLeave", function()
    U.SetBorderColor(button, M.Unpack(options.border or M.color.border))
  end)

  if type(options.onClick) == "function" then
    button:SetScript("OnClick", options.onClick)
  end

  return button
end

-- ---------------------------------------------------------------------------
-- Stripping stock art
--
-- knowledge.json / rendering.native_texture_strip_requires_alpha and
-- frames.stock_singletons_structure_nonvanilla: stock windows do not reliably
-- expose the regions upstream skins assume, and a texture can survive Hide().
-- Enumerate what is actually there and use the clear + hide + alpha-0 path.
--
-- This is a primitive only. Each stock window still needs its own
-- capability-checked skin; see the native-interface work, not this file.
-- ---------------------------------------------------------------------------
function U.StripTextures(frame, keep)
  if not frame or not frame.GetRegions then return 0 end

  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return 0 end

  local stripped, i = 0, nil
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local isTexture = false
    if region and region.GetObjectType then
      local typeOk, objectType = pcall(region.GetObjectType, region)
      isTexture = typeOk and objectType == "Texture"
    end

    if isTexture and not (keep and keep[region]) then
      U.HideRegion(region)
      stripped = stripped + 1
    end
  end

  return stripped
end
