-- unrealUI :: core/modernwowscrollbar.lua
--
-- The Modern WoW scrollbar: Blizzard's Dragonflight MinimalScrollBar drawn
-- over a stock Slider. One implementation for every Modern WoW surface that
-- draws this bar -- Character > Skills, the profession window and the
-- quest-giver window today -- so a fix to its art or behaviour lands
-- everywhere at once. Callers never draw a scrollbar piece of their own; they
-- call U.StyleModernWowScrollbar once and, for a proportional thumb,
-- U.SetModernWowScrollbarProportion on each refresh. Tokens live in
-- core/media.lua (M.modernWow.scrollbar).

local U = UnrealUI
local M = U.media

-- Applies the imported Dragonflight MinimalScrollBar atlas to an existing
-- native vertical Slider. The Slider keeps its range, value and native scroll
-- scripts, and its arrow buttons keep their click handling; every visible
-- piece is addon-owned and redrawn from those values. Atlas cells and authored
-- sizes live centrally in core/media.lua.
--
-- USER_CONFIRMED_INGAME 2026-09-16 (Character Skills, modern-wow): the first
-- version hung this art on the client's own state regions and failed three
-- ways, so none of those routes is used here.
--  * There is no Button:GetDisabledTexture (the client's Button method list
--    has no such getter), so a disabled arrow kept the native art at either
--    end of the list.
--  * Art anchored to the stock thumb texture did not follow the height given
--    to it: the drawn thumb left the track, and grabbing it often missed the
--    real thumb, so the list could not be dragged.
--  * A post-hook on SkillFrame_Update never fired on a scroll. `options.
--    onChange` is called on every value or range change instead.
--  * The range stays the owner's to set. FOCUSED_RUNTIME_PROBE
--    (skillscroll.first_open_range.v1): UpdateScrollChildRect is no repair
--    for an empty FauxScrollFrame range -- it recomputes the max from the
--    child's overflow, and that is 0 when the pane is taller than its rows.
-- The owned thumb is dragged with the GetCursorPosition / GetEffectiveScale
-- pair (knowledge.json / api.getcursorposition_usable_for_hit_testing) and
-- moves the list through Slider:SetValue, the call the arrows and the mouse
-- wheel already use.
function U.StyleModernWowScrollbar(scrollbar, options)
  local token = M.modernWow and M.modernWow.scrollbar
  if not scrollbar or not token then return nil end
  options = options or {}

  local state = scrollbar.uuiModernWow
  if state then
    state.onChange = options.onChange
    return scrollbar
  end

  local name
  if scrollbar.GetName then
    local ok, value = pcall(scrollbar.GetName, scrollbar)
    if ok then name = value end
  end

  local created, thumb = pcall(CreateFrame, "Button", nil, scrollbar)
  if not created or not thumb then return nil end

  state = {
    onChange = options.onChange,
    -- Read by UnrealRuntimeProbe's skillscroll capture; nothing here uses it.
    thumb = thumb,
    extent = token.thumb.minExtent,
    arrows = {},
  }
  scrollbar.uuiModernWow = state

  local function SetCell(texture, path, cell, alpha)
    pcall(texture.SetTexture, texture, path)
    pcall(texture.SetTexCoord, texture, M.Unpack(cell))
    pcall(texture.SetAlpha, texture, alpha or 1)
  end

  -- Arrows. Their native faces come off the way every stock button's do
  -- (ClearButtonFaces) before the owned face is added, and each stepper sits
  -- MinimalScrollBar's gap beyond its end of the Slider.
  local function StyleArrow(button, cells, point, relativePoint, offsetY)
    if not button or not cells or not button.CreateTexture then return end
    U.ClearStockButtonFaces(button, U.StockRegionKeep(button))
    if button.uuiArrowGlyph then pcall(button.uuiArrowGlyph.Hide, button.uuiArrowGlyph) end
    pcall(function()
      button:SetWidth(token.arrow.width)
      button:SetHeight(token.arrow.height)
      button:ClearAllPoints()
      button:SetPoint(point, scrollbar, relativePoint, 0, offsetY)
    end)
    pcall(button.SetHitRectInsets, button, -3, -3, -3, -3)

    local face = button:CreateTexture(nil, "ARTWORK")
    face:SetAllPoints(button)
    local arrow = { button = button, face = face, cells = cells }
    U.PostHookScript(button, "OnEnter", function() arrow.hover = true end)
    U.PostHookScript(button, "OnLeave", function() arrow.hover = false end)
    table.insert(state.arrows, arrow)
  end

  local function PaintArrow(arrow)
    local button = arrow.button
    local key = "normal"
    -- IsEnabled returns 1 / 0 on this client, not a boolean (documentation).
    local okEnabled, enabled = pcall(button.IsEnabled, button)
    if okEnabled and enabled ~= 1 and enabled ~= true then
      key = "disabled"
    else
      local okState, buttonState = pcall(button.GetButtonState, button)
      if okState and buttonState == "PUSHED" then
        key = "pushed"
      elseif arrow.hover then
        key = "hover"
      end
    end
    if key == arrow.key then return end
    arrow.key = key
    if key == "disabled" then
      SetCell(arrow.face, token.proportional, arrow.cells.normal,
              token.arrow.disabledAlpha)
    else
      SetCell(arrow.face, token.proportional, arrow.cells[key])
    end
  end

  -- options.upArrowY / downArrowY: extra vertical offset (positive up) for
  -- a caller whose art gives an arrow its own measured seat.
  StyleArrow(name and U.G(name .. "ScrollUpButton"), token.arrow.up,
             "BOTTOM", "TOP", token.arrow.gap + (tonumber(options.upArrowY) or 0))
  StyleArrow(name and U.G(name .. "ScrollDownButton"), token.arrow.down,
             "TOP", "BOTTOM",
             -token.arrow.gap + (tonumber(options.downArrowY) or 0))

  if scrollbar.uuiTrack then pcall(scrollbar.uuiTrack.Hide, scrollbar.uuiTrack) end
  if scrollbar.CreateTexture then
    local track = token.track
    local top = scrollbar:CreateTexture(nil, "BACKGROUND")
    local middle = scrollbar:CreateTexture(nil, "BACKGROUND")
    local bottom = scrollbar:CreateTexture(nil, "BACKGROUND")

    SetCell(top, token.proportional, track.top)
    top:SetWidth(track.width)
    top:SetHeight(track.cap)
    top:SetPoint("TOP", scrollbar, "TOP", 0, 0)

    SetCell(bottom, token.proportional, track.bottom)
    bottom:SetWidth(track.width)
    bottom:SetHeight(track.cap)
    bottom:SetPoint("BOTTOM", scrollbar, "BOTTOM", 0, 0)

    SetCell(middle, token.vertical, track.middle)
    middle:SetWidth(track.width)
    middle:SetPoint("TOP", top, "BOTTOM", 0, 0)
    middle:SetPoint("BOTTOM", bottom, "TOP", 0, 0)
  end

  -- The stock thumb stays where the Slider puts it, only invisible; the owned
  -- thumb above it is what is drawn and grabbed.
  if scrollbar.GetThumbTexture then
    local ok, native = pcall(scrollbar.GetThumbTexture, scrollbar)
    if ok and native then pcall(native.SetAlpha, native, 0) end
  end

  pcall(thumb.EnableMouse, thumb, true)
  local art = {
    top = thumb:CreateTexture(nil, "ARTWORK"),
    middle = thumb:CreateTexture(nil, "ARTWORK"),
    bottom = thumb:CreateTexture(nil, "OVERLAY"),
  }
  art.top:SetWidth(token.thumb.width)
  art.top:SetHeight(token.thumb.topExtent)
  art.top:SetPoint("TOP", thumb, "TOP", 0, 0)
  art.bottom:SetWidth(token.thumb.width)
  art.bottom:SetHeight(token.thumb.bottomExtent)
  art.bottom:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  art.middle:SetWidth(token.thumb.width)
  art.middle:SetPoint("TOP", art.top, "BOTTOM", 0, 0)
  -- The bottom cap's upper rows fade in from transparent: MinimalScrollBar
  -- draws that cap OVER the body, not after it. Run the body down under the
  -- fade so it blends into the body instead of showing the track through it
  -- (USER_CONFIRMED_INGAME 2026-09-19: a detached tail under the thumb).
  art.middle:SetPoint("BOTTOM", art.bottom, "TOP", 0,
                      -(token.thumb.bottomFade or 0))

  local function PaintThumb()
    local key = "normal"
    if state.drag then key = "pushed" elseif state.hover then key = "hover" end
    if key == state.thumbKey then return end
    state.thumbKey = key
    local cells = token.thumb[key]
    SetCell(art.top, token.proportional, cells.top)
    SetCell(art.middle, token.vertical, cells.middle)
    SetCell(art.bottom, token.proportional, cells.bottom)
  end

  local function Number(ok, value)
    if ok and value ~= nil then return tonumber(value) end
    return nil
  end

  local function Measure()
    local okValue, value = pcall(scrollbar.GetValue, scrollbar)
    local okRange, low, high = pcall(scrollbar.GetMinMaxValues, scrollbar)
    local okHeight, height = pcall(scrollbar.GetHeight, scrollbar)
    value, low = Number(okValue, value), Number(okRange, low)
    high, height = Number(okRange, high), Number(okHeight, height)
    if not value or not low or not high or not height then return nil end
    return value, low, high, math.max(0, height)
  end

  local getCursor = U.G("GetCursorPosition")
  local function CursorY()
    if type(getCursor) ~= "function" then return nil end
    local ok, _, y = pcall(getCursor)
    local okScale, scale = pcall(scrollbar.GetEffectiveScale, scrollbar)
    y, scale = Number(ok, y), Number(okScale, scale)
    if not y or not scale or scale <= 0 then return nil end
    return y / scale
  end

  local function PlaceThumb(value, low, high, height)
    local extent = math.min(height, state.extent)
    local travel = height - extent
    local offset = 0
    if travel > 0 and high > low then
      offset = math.floor((value - low) / (high - low) * travel + 0.5)
    end
    pcall(function()
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPLEFT", scrollbar, "TOPLEFT", 0, -offset)
      thumb:SetPoint("TOPRIGHT", scrollbar, "TOPRIGHT", 0, -offset)
      thumb:SetHeight(extent)
    end)
  end

  local function Tick()
    local value, low, high, height = Measure()
    if not value then return end

    local drag = state.drag
    if drag then
      local y = CursorY()
      local travel = height - math.min(height, state.extent)
      if y and travel > 0 and high > low then
        -- Cursor Y grows upward; the Slider's value grows down the list.
        local target = drag.value + (drag.y - y) / travel * (high - low)
        if target < low then target = low end
        if target > high then target = high end
        if target ~= value then
          pcall(scrollbar.SetValue, scrollbar, target)
          value, low, high, height = Measure()
          if not value then return end
        end
      end
    end

    local moved = value ~= state.value or low ~= state.low or high ~= state.high
    if moved or height ~= state.height or state.extent ~= state.placedExtent then
      state.value, state.low, state.high = value, low, high
      state.height, state.placedExtent = height, state.extent
      PlaceThumb(value, low, high, height)
      if moved and type(state.onChange) == "function" then
        local ok, err = pcall(state.onChange)
        if not ok then U.Error("modern-wow scrollbar: " .. tostring(err)) end
      end
    end

    local i
    for i = 1, table.getn(state.arrows) do PaintArrow(state.arrows[i]) end
  end

  -- Polled only while the bar is on screen: the thumb is its child, so it is
  -- hidden with it whenever the list fits and the native code hides the bar.
  local updateId = "modernwow.scrollbar." .. tostring(name or scrollbar)

  thumb:SetScript("OnEnter", function()
    state.hover = true
    PaintThumb()
  end)
  thumb:SetScript("OnLeave", function()
    state.hover = false
    PaintThumb()
  end)
  thumb:SetScript("OnMouseDown", function()
    local y = CursorY()
    local value = Measure()
    if y and value then state.drag = { y = y, value = value } end
    PaintThumb()
  end)
  thumb:SetScript("OnMouseUp", function()
    state.drag = nil
    PaintThumb()
  end)
  thumb:SetScript("OnShow", function()
    U.RegisterUpdate(updateId, 0, Tick)
  end)
  thumb:SetScript("OnHide", function()
    state.drag = nil
    -- Re-place and refresh the owner as soon as the bar comes back.
    state.value = nil
    U.UnregisterUpdate(updateId)
    PaintThumb()
  end)

  PaintThumb()
  local okVisible, visible = pcall(thumb.IsVisible, thumb)
  if okVisible and visible and visible ~= 0 then
    U.RegisterUpdate(updateId, 0, Tick)
  end

  return scrollbar
end

-- Gives the owned thumb MinimalScrollBar's proportional extent. The Slider is
-- the whole track (see M.modernWow.scrollbar); the scrollbar's next tick
-- re-places the thumb at the new size.
function U.SetModernWowScrollbarProportion(scrollbar, visibleCount, totalCount)
  local token = M.modernWow and M.modernWow.scrollbar
  local state = scrollbar and scrollbar.uuiModernWow
  if not token or not state then return nil end

  visibleCount = tonumber(visibleCount or 0) or 0
  totalCount = tonumber(totalCount or 0) or 0
  local ok, height = pcall(scrollbar.GetHeight, scrollbar)
  height = ok and height ~= nil and tonumber(height) or nil
  if not height then return nil end
  height = math.max(0, height)

  local extent = height
  if totalCount > visibleCount and totalCount > 0 then
    extent = math.floor((height * visibleCount / totalCount) + 0.5)
  end
  state.extent = math.min(height, math.max(token.thumb.minExtent, extent))
  return state.extent
end
