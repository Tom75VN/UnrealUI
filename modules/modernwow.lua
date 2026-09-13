-- unrealUI :: modules/modernwow.lua
--
-- The complete drawing path for themes/modern-wow.lua. Nothing here runs under
-- any other theme: OnEnable returns immediately unless the theme that was
-- actually loaded this session is "modern-wow", which is the single seam
-- core/unitframestyle.lua describes for a style that is its own
-- implementation rather than a set of conditionals threaded through shared
-- code.
--
-- What it dresses is UnrealUI's own frames and the stock windows UnrealUI has
-- already skinned, exactly as under `modern`. It deliberately does NOT follow
-- DragonflightUI's approach of parenting art onto PlayerFrame/TargetFrame and
-- no-opping their Show: rules/unreal-ui.md records that lifecycle as
-- crash-confirmed on this client (unitframes.classic_targetframe_hide_crash).
-- No native unit frame is touched from here at all.
--
-- SURFACES AND THE OFF SWITCH
--
-- Every visual area is a registered surface with its own persisted enable
-- flag, and a surface ships disabled until it has been seen working in game.
-- That is the whole point of the registry: the art and the layout for a dozen
-- areas can land at once, and each is switched on and judged on its own
-- instead of one bad offset making the entire theme look broken.
--
-- Enabling is reload-bound for the same reason a theme change is -- a surface
-- builds its textures once, at OnEnable, and a flag flipped afterwards would
-- leave half an interface dressed.
--
--   /uui mw              measure and dump what is actually built
--   /uui mw list         every surface with its state
--   /uui mw on <id>      enable, then reload
--   /uui mw off <id>     disable, then reload
--
-- Local budget: everything hangs off one `mw` table rather than a file of
-- top-level locals, per rules/unreal-ui.md -- a Lua 5.0/5.1 chunk silently
-- fails to load past 200 of them
-- (knowledge.json / lua.top_level_local_limit_silent_file_failure).

local U = UnrealUI
local M = U.media
local MW = U.RegisterModule("modernwow")

local mw = {}

mw.THEME = "modern-wow"

-- ---------------------------------------------------------------------------
-- Surface registry
-- ---------------------------------------------------------------------------
mw.surfaces = {}
mw.surfaceOrder = {}

-- `default` is what a fresh profile gets. A surface ships off until it has
-- been seen working in game, then flips on -- which is the reason the registry
-- exists. Unit frames, cast bars and the bar animation have passed that bar;
-- everything below them has not.
function mw.RegisterSurface(id, label, default, build)
  local surface = {
    id = id,
    label = label,
    default = default and true or false,
    build = build,
    built = false,
  }
  mw.surfaces[id] = surface
  table.insert(mw.surfaceOrder, surface)
  return surface
end

function mw.Defaults()
  -- Unit-frame and portrait size are intentionally absent: modern-wow always
  -- uses the pixel-perfect geometry validated on Malgus. Keeping either value
  -- profile-scoped made the same frame render at different sizes after a
  -- character or account change. Old stored values remain harmless because no
  -- drawing path reads them.
  -- castScale remains configurable because it affects cast bars, not unit
  -- frames. See mw.cast.scale for the shipped value this takes.
  local defaults, i = { powerTextSize = 0,
                        castScale = mw.cast.scale,
                        actionbarVisualVersion = 1,
                        playerFXVersion = 1,
                        microbarVersion = 1,
                        xpbarVersion = 1 }, nil
  for i = 1, table.getn(mw.surfaceOrder) do
    local surface = mw.surfaceOrder[i]
    defaults["surface_" .. surface.id] = surface.default
  end
  return defaults
end

function mw.Config()
  return U.ModuleConfig("modernwow", mw.Defaults())
end

function mw.Enabled(id)
  local surface = mw.surfaces[id]
  if not surface then return false end
  local config = mw.Config()
  local value = config["surface_" .. id]
  if type(value) ~= "boolean" then return surface.default end
  return value
end

function mw.Active()
  if type(U.GetActiveThemeStyle) ~= "function" then return false end
  return U.GetActiveThemeStyle() == mw.THEME
end

function MW:OnInit()
  local config = mw.Config()
  -- The action-bar surface used to be a disabled no-op roadmap entry. Turn it
  -- on once when the actual drawing path first lands; after this migration an
  -- explicit `/uui mw off actionbar` choice remains untouched.
  if (tonumber(config.actionbarVisualVersion) or 1) < 2 then
    config.surface_actionbar = true
    config.actionbarVisualVersion = 2
  end

  -- The player combat/rest surface shipped off for one release, the registry's
  -- rule being that a surface stays disabled until it has been seen working in
  -- game. It has, so it defaults on now -- and this turns it on once for the
  -- profiles that stored the old default, which U.ModuleConfig would otherwise
  -- keep forever. An explicit `/uui mw off playerfx` after this point
  -- is still respected.
  if (tonumber(config.playerFXVersion) or 1) < 2 then
    config.surface_playerfx = true
    config.playerFXVersion = 2
  end

  -- Same story for the micro bar: it was a disabled no-op roadmap entry, so
  -- every profile that ran that build stored surface_microbar = false and
  -- would keep it forever once the drawing path landed, whatever the
  -- registration default says. Turned on once here; an explicit
  -- `/uui mw off microbar` after this point is still respected.
  if (tonumber(config.microbarVersion) or 1) < 2 then
    config.surface_microbar = true
    config.microbarVersion = 2
  end

  -- The XP/reputation surface previously existed as a disabled roadmap entry.
  -- Enable the completed drawing path once for profiles that stored that old
  -- default; later explicit `/uui mw off xpbar` choices remain untouched.
  if (tonumber(config.xpbarVersion) or 1) < 2 then
    config.surface_xpbar = true
    config.xpbarVersion = 2
  end
end

-- Narrow theme-surface query for the module that owns a dressed frame. This
-- keeps action-bar configuration in this registry while modules/actionbar.lua
-- remains the only code that creates or mutates action-bar buttons.
function U.ModernWowSurfaceEnabled(id)
  return mw.Active() and mw.Enabled(id)
end

-- ---------------------------------------------------------------------------
-- Shared drawing helpers
-- ---------------------------------------------------------------------------

-- Every texture this module creates goes through here so the draw layer, the
-- texture path and the texture coordinates are applied in one guarded place.
-- Only the four-argument SetTexCoord form is used, per knowledge.json /
-- textures.rle_512_tga_atlas_four_arg_supported.
function mw.Texture(parent, layer, path, u1, u2, v1, v2)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer or "ARTWORK")
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  if u1 then pcall(texture.SetTexCoord, texture, u1, u2, v1, v2) end
  return texture
end

function mw.Dimension(frame, method)
  if not frame or not frame[method] then return 0 end
  local ok, value = pcall(frame[method], frame)
  return (ok and tonumber(value)) or 0
end

-- Takes UnrealUI's flat outline off a frame this theme is about to cover with
-- its own art. Deliberately edge-only: U.SetBackdropShown would also clear the
-- fill, which is the dark bed the art's transparent centre shows. Same
-- distinction modules/unitframes.lua draws in classSkin.SetOuterBordersShown.
function mw.HideFlatEdges(frame)
  local edges = frame and frame.uuiEdges
  if not edges then return end
  local i
  for i = 1, table.getn(edges) do
    pcall(edges[i].Hide, edges[i])
  end
end

-- The stronger version, for a frame this theme covers with opaque art edge to
-- edge: the fill is not a bed there, it is a near-black sheet drawn OVER the
-- art. The chrome frame sits one level BELOW the window it dresses, so the
-- window's own backdrop wins wherever it is still painted -- which is why the
-- Quest Log read as a flat dark panel with the page art faintly behind it.
function mw.HideFlatSurface(frame)
  if not frame then return end
  if type(U.SetBackdropShown) == "function" then
    pcall(U.SetBackdropShown, frame, false)
  end
  mw.HideFlatEdges(frame)
end

-- Fills one of a button's state slots from a cell of a shared atlas.
--
-- The alpha and Show at the end are not optional, and they are what the first
-- attempt at this got wrong. UnrealUI clears a stock button's faces through
-- U.HideRegion, which zeroes the region's alpha and calls Hide() on it as well
-- as dropping its texture -- and Set*Texture hands back that same region. The
-- client picks which slot to display, but a region it picks while still hidden
-- draws nothing, which is why a close button dressed with a pushed face left
-- hidden simply vanished for the duration of the press. Every slot filled here
-- is therefore un-hidden; the client still decides which one is on screen.
function mw.ButtonFace(button, setter, getter, cell, path)
  if not button or not cell or not button[setter] then return end
  if not pcall(button[setter], button,
               path or M.modernWow.texture.redButton) then
    return
  end

  local ok, texture = pcall(button[getter], button)
  if not ok or not texture then return end

  pcall(texture.SetTexCoord, texture, cell[1], cell[2], cell[3], cell[4])
  pcall(texture.SetAlpha, texture, 1)
  pcall(texture.Show, texture)
end

-- Rectangular NPC actions use the same measured three-slice construction as
-- UnrealQuest's three Quest Log buttons: fixed-aspect bevel caps and only a
-- stretched middle. The stock button remains the input/state owner.
function mw.ActionButtonSetSlice(texture, token, left, right, top)
  pcall(texture.SetTexCoord, texture,
        left / token.atlasWidth, right / token.atlasWidth,
        top / token.atlasHeight,
        (top + token.cellHeight) / token.atlasHeight)
end

function mw.PaintActionButton(button, hovered)
  local state = button and button.uuiModernWowAction
  if type(state) ~= "table" then return end
  local token = state.token or M.modernWow.button128Red
  if not token then return end

  -- Disabled wins over hover; an atlas without a disabled cell keeps normal.
  -- A grey owner draws that same cell while enabled: the atlas has no grey
  -- hover, so its owner shows hover through its label instead.
  local wanted = "normal"
  if (state.disabled or state.grey) and token.disabled then
    wanted = "disabled"
  elseif hovered then
    wanted = "hover"
  end
  if state.painted == wanted then return end
  state.painted = wanted

  local cell = token[wanted]
  local cap = token.cap
  local bar = token.barWidth
  mw.ActionButtonSetSlice(state.left, token, cell.capLeft,
                          cell.capLeft + cap, cell.capTop)
  mw.ActionButtonSetSlice(state.middle, token, cap, bar - cap, cell.barTop)
  mw.ActionButtonSetSlice(state.right, token, bar - cap, bar, cell.barTop)
end

function mw.PlaceActionButton(button)
  local state = button and button.uuiModernWowAction
  local anchor = type(state) == "table" and state.anchor
  if not anchor or not anchor.ready then return false end

  local ok = pcall(function()
    button:ClearAllPoints()
    button:SetPoint(anchor.point, anchor.relative,
                    anchor.relativePoint or anchor.point,
                    anchor.x, anchor.y + M.modernWow.button128Red.lift)
  end)
  return ok and true or false
end

-- Capture once, then apply on the next shared tick. U.GetFramePoint normalises
-- this client's name-string relative frame and inverted Y readback; deferring
-- avoids the documented invalid capture-and-immediately-reapply sequence.
function mw.LiftActionButton(button)
  local state = button and button.uuiModernWowAction
  if type(state) ~= "table" then return end
  if state.anchor then
    mw.PlaceActionButton(button)
    return
  end

  local point, relative, relativePoint, x, y = U.GetFramePoint(button, 1)
  if not point then return end
  state.anchor = {
    point = point,
    relative = relative,
    relativePoint = relativePoint,
    x = x,
    y = y,
    ready = false,
  }

  local name = "button"
  if button.GetName then
    local ok, value = pcall(button.GetName, button)
    if ok and value then name = value end
  end
  U.DeferOnce("modernwow-action-lift-" .. name, function()
    if not button.uuiModernWowAction then return end
    button.uuiModernWowAction.anchor.ready = true
    mw.PlaceActionButton(button)
  end)
end

function mw.DressActionButton(button)
  if not button then return false end

  local token = M.modernWow.button128Red
  local path = M.modernWow.texture.button128Red
  if not token or not path then return false end

  local state = button.uuiModernWowAction
  if type(state) ~= "table" then
    mw.HideFlatSurface(button)
    pcall(button.SetHeight, button, token.height)

    state = {}
    local okLeft, left = pcall(button.CreateTexture, button, nil, "BACKGROUND")
    local okMiddle, middle = pcall(button.CreateTexture, button, nil, "BACKGROUND")
    local okRight, right = pcall(button.CreateTexture, button, nil, "BACKGROUND")
    if not okLeft or not okMiddle or not okRight or
       not left or not middle or not right then
      return false
    end
    state.left, state.middle, state.right = left, middle, right
    button.uuiModernWowAction = state

    pcall(left.SetTexture, left, path)
    pcall(middle.SetTexture, middle, path)
    pcall(right.SetTexture, right, path)

    local capWidth = token.height * token.cap / token.cellHeight
    pcall(left.SetWidth, left, capWidth)
    pcall(right.SetWidth, right, capWidth)
    pcall(left.SetPoint, left, "TOPLEFT", button, "TOPLEFT", 0, 0)
    pcall(left.SetPoint, left, "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    pcall(right.SetPoint, right, "TOPRIGHT", button, "TOPRIGHT", 0, 0)
    pcall(right.SetPoint, right, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    pcall(middle.SetPoint, middle, "TOPLEFT", left, "TOPRIGHT", 0, 0)
    pcall(middle.SetPoint, middle, "BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)

    U.PostHookScript(button, "OnEnter", function()
      state.hovered = true
      mw.PaintActionButton(button, true)
    end)
    U.PostHookScript(button, "OnLeave", function()
      state.hovered = false
      mw.PaintActionButton(button, false)
    end)
    U.PostHookScript(button, "OnShow", function()
      mw.PaintActionButton(button, state.hovered)
      mw.PlaceActionButton(button)
    end)
  end

  local ok, label = false, nil
  if button.GetFontString then
    ok, label = pcall(button.GetFontString, button)
  end
  if ok and label then
    U.SetStockFont(label, M.fontSize.normal, M.color.text)
    U.CenterButtonLabel(label, button)
  end

  mw.PaintActionButton(button, state.hovered)
  mw.LiftActionButton(button)
  return true
end

function U.ModernWowNpcActionButton(button)
  if not mw.Active() or not mw.Enabled("npcdialogs") then return false end
  return mw.DressActionButton(button)
end

-- Owned red-button face: the measured 128RedButton three-slice drawn on an
-- addon-owned frame (the Modern WoW game menu's rows). Nothing is stripped --
-- the owner has no art of its own -- and no input is hooked: the caller owns
-- the frame's size, anchor, label and hover source, and repaints through
-- U.ModernWowPaintRedButton. Re-run after a resize so the caps keep the cell's
-- aspect at the new height; only the middle stretches. `height` is the height
-- the caller is giving the owner, for an anchored owner that cannot report it
-- yet; without it the owner's own height is read. `gold` selects the
-- gold-rimmed atlas; it is fixed by the owner's first call.
function U.ModernWowRedButtonFace(owner, height, gold)
  if not mw.Active() or not owner then return false end

  local token = M.modernWow.button128Red
  local path = M.modernWow.texture.button128Red
  if gold then
    token = M.modernWow.button128GoldRed
    path = M.modernWow.texture.button128GoldRed
  end
  if not token or not path then return false end

  local state = owner.uuiModernWowAction
  if type(state) ~= "table" then
    local left = mw.Texture(owner, "BACKGROUND", path)
    local middle = mw.Texture(owner, "BACKGROUND", path)
    local right = mw.Texture(owner, "BACKGROUND", path)
    if not left or not middle or not right then return false end

    state = { left = left, middle = middle, right = right, token = token }
    owner.uuiModernWowAction = state

    pcall(left.SetPoint, left, "TOPLEFT", owner, "TOPLEFT", 0, 0)
    pcall(left.SetPoint, left, "BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
    pcall(right.SetPoint, right, "TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    pcall(right.SetPoint, right, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    pcall(middle.SetPoint, middle, "TOPLEFT", left, "TOPRIGHT", 0, 0)
    pcall(middle.SetPoint, middle, "BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
  end

  height = tonumber(height) or mw.Dimension(owner, "GetHeight")
  if height > 0 then
    local capWidth = height * token.cap / token.cellHeight
    pcall(state.left.SetWidth, state.left, capWidth)
    pcall(state.right.SetWidth, state.right, capWidth)
  end

  state.painted = nil
  mw.PaintActionButton(owner, state.hovered)
  return true
end

function U.ModernWowPaintRedButton(owner, hovered)
  local state = owner and owner.uuiModernWowAction
  if type(state) ~= "table" then return end
  state.hovered = hovered and true or false
  mw.PaintActionButton(owner, state.hovered)
end

-- The grey face for a row the owner reports as disabled.
function U.ModernWowSetRedButtonDisabled(owner, disabled)
  local state = owner and owner.uuiModernWowAction
  if type(state) ~= "table" then return end
  state.disabled = disabled and true or false
  mw.PaintActionButton(owner, state.hovered)
end

-- The grey face for an enabled row the owner wants set apart (the game menu's
-- Donation Rewards row). It stays clickable; only the drawn cell changes.
function U.ModernWowSetRedButtonGrey(owner, grey)
  local state = owner and owner.uuiModernWowAction
  if type(state) ~= "table" then return end
  state.grey = grey and true or false
  state.painted = nil
  mw.PaintActionButton(owner, state.hovered)
end

-- Window housing: the diamond-metal frame (M.modernWow.metalFrame) around a
-- translucent flat bed, drawn on an addon-owned window (the Modern WoW game
-- menu). Fill in BACKGROUND and metal in BORDER, so the window's child rows
-- stay above all of it. Nothing here takes the mouse. Placement is recomputed
-- on every call so the corner arms and edges follow the window's size;
-- `width`/`height` supply that size for an anchored frame that cannot report
-- it yet.
function mw.MetalSlice(texture, slice, token)
  local aw, ah = token.atlasWidth, token.atlasHeight
  pcall(texture.SetTexCoord, texture, slice.u1 / aw, slice.u2 / aw,
        slice.v1 / ah, slice.v2 / ah)
end

function U.ModernWowMetalFrame(frame, width, height)
  if not mw.Active() or not frame then return false end

  local token = M.modernWow.metalFrame
  if not token then return false end

  local state = frame.uuiModernWowMetal
  if type(state) ~= "table" then
    local fill = mw.Texture(frame, "BACKGROUND", M.texture.plain)
    if not fill then return false end
    pcall(fill.SetVertexColor, fill, M.Unpack(token.fill))

    state = { fill = fill, corners = {}, edges = {} }
    local i
    for i = 1, table.getn(token.corners) do
      local piece = mw.Texture(frame, "BORDER", token.path)
      if not piece then return false end
      state.corners[i] = piece
    end

    local sides = { "top", "bottom", "left", "right" }
    for i = 1, table.getn(sides) do
      local edge = mw.Texture(frame, "BORDER", token.path)
      if not edge then return false end
      mw.MetalSlice(edge, token[sides[i]], token)
      state.edges[sides[i]] = edge
    end
    frame.uuiModernWowMetal = state
  end

  local s = token.scale
  local inset = token.inset
  width = tonumber(width) or mw.Dimension(frame, "GetWidth")
  height = tonumber(height) or mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return false end

  local fill = state.fill
  pcall(function()
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  end)

  -- Arms reach inward until they would pass the frame's midpoint.
  local e = token.outer
  local n = math.min(token.arm, (math.min(width, height) / 2 - inset) / s)
  if n < 0 then n = 0 end
  local shift = e * s - inset
  local aw, ah = token.atlasWidth, token.atlasHeight
  local i
  for i = 1, table.getn(token.corners) do
    local c = token.corners[i]
    local piece = state.corners[i]
    local u1, u2, v1, v2
    if c.h < 0 then u1, u2 = c.x - e, c.x + n else u1, u2 = c.x - n, c.x + e end
    if c.v > 0 then v1, v2 = c.y - e, c.y + n else v1, v2 = c.y - n, c.y + e end
    pcall(function()
      piece:ClearAllPoints()
      piece:SetWidth((e + n) * s)
      piece:SetHeight((e + n) * s)
      piece:SetPoint(c.point, frame, c.point, c.h * shift, c.v * shift)
      piece:SetTexCoord(u1 / aw, u2 / aw, v1 / ah, v2 / ah)
    end)
  end

  -- Straight runs fill the gap between the corner arms, centred on the same
  -- centreline; only their length stretches.
  local reach = inset + n * s
  local edges = state.edges
  local halfH = (token.top.v2 - token.top.v1) / 2 * s
  local halfB = (token.bottom.v2 - token.bottom.v1) / 2 * s
  local halfL = (token.left.u2 - token.left.u1) / 2 * s
  local halfR = (token.right.u2 - token.right.u1) / 2 * s
  pcall(function()
    local top = edges.top
    top:ClearAllPoints()
    top:SetHeight(halfH * 2)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", reach, -inset + halfH)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -reach, -inset + halfH)

    local bottom = edges.bottom
    bottom:ClearAllPoints()
    bottom:SetHeight(halfB * 2)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", reach, inset - halfB)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -reach, inset - halfB)

    local left = edges.left
    left:ClearAllPoints()
    left:SetWidth(halfL * 2)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset - halfL, -reach)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset - halfL, reach)

    local right = edges.right
    right:ClearAllPoints()
    right:SetWidth(halfR * 2)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset + halfR, -reach)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset + halfR, reach)
  end)

  return true
end

-- The Quest Progress scrollbar keeps its native atlas, but the generic NPC
-- quadrants have no recessed track behind it. An owned frame one level lower
-- supplies a narrow warm rim and near-black bed without touching the bar's
-- state machine, regions, anchors or mouse handling.
function mw.QuestProgressBarBackground(bar)
  if not bar then return false end
  if bar.uuiModernWowProgressBackground then return true end

  local token = M.modernWow.npcDialog and
                M.modernWow.npcDialog.progressBarBackground
  if not token then return false end

  local parent = nil
  if bar.GetParent then
    local ok, value = pcall(bar.GetParent, bar)
    if ok then parent = value end
  end
  if not parent then return false end

  local ok, background = pcall(CreateFrame, "Frame",
                                "UnrealUIQuestProgressBarBackground", parent)
  if not ok or not background then return false end
  pcall(background.EnableMouse, background, false)
  pcall(background.SetPoint, background, "TOPLEFT", bar, "TOPLEFT",
        -token.padding, token.padding)
  pcall(background.SetPoint, background, "BOTTOMRIGHT", bar, "BOTTOMRIGHT",
        token.padding, -token.padding)

  local levelOk, level = false, nil
  if bar.GetFrameLevel then levelOk, level = pcall(bar.GetFrameLevel, bar) end
  if levelOk and tonumber(level) then
    pcall(background.SetFrameLevel, background, math.max(0, level - 1))
  end

  local outer = mw.Texture(background, "BACKGROUND", M.texture.plain)
  local inner = mw.Texture(background, "ARTWORK", M.texture.plain)
  if not outer or not inner then
    pcall(background.Hide, background)
    return false
  end
  pcall(outer.SetAllPoints, outer, background)
  pcall(inner.SetPoint, inner, "TOPLEFT", background, "TOPLEFT",
        token.inset, -token.inset)
  pcall(inner.SetPoint, inner, "BOTTOMRIGHT", background, "BOTTOMRIGHT",
        -token.inset, token.inset)
  U.SetColor(outer, M.Unpack(token.outer))
  U.SetColor(inner, M.Unpack(token.inner))

  bar.uuiModernWowProgressBackground = background
  U.PostHookScript(bar, "OnShow", function()
    pcall(background.Show, background)
  end)
  U.PostHookScript(bar, "OnHide", function()
    pcall(background.Hide, background)
  end)

  if bar.IsShown then
    local shownOk, shown = pcall(bar.IsShown, bar)
    if shownOk and not shown then pcall(background.Hide, background) end
  end
  return true
end

function U.ModernWowQuestProgressBarBackground(bar)
  if not mw.Active() or not mw.Enabled("npcdialogs") then return false end
  return mw.QuestProgressBarBackground(bar)
end

-- ---------------------------------------------------------------------------
-- Surface: unit frames
--
-- The frame art is one whole 256x128 texture, drawn mirrored. It is not cut
-- into slices: the source art is a fixed-proportion housing with a portrait
-- ring at one end, so stretching pieces of it independently was what made the
-- first attempt distort. Scaling the whole canvas keeps every proportion the
-- artist authored, and a classification change becomes one SetTexture.
--
-- The art is authored with the ring on the RIGHT, because DragonflightUI hands
-- it to the client's own PlayerFrame/TargetFrame regions and the frame XML
-- flips it for the player. UnrealUI draws every unit frame portrait-left, so
-- the flip happens here, by passing descending horizontal coordinates to the
-- four-argument SetTexCoord form.
-- ---------------------------------------------------------------------------

-- `power` names the fill each frame's power bar wears. modules/unitframes.lua
-- builds BOTH bars from M.unitFrame.statusTexture, which this theme points at
-- the health fill, so without this every mana bar would wear health art. Only
-- the health bar is ever re-textured at runtime (unitframes.lua
-- ApplyHealthColor and the two colour paths beside it), so setting the power
-- fill once here is not undone later.
-- `mirror` says which way round the frame reads. The art is authored with the
-- portrait on the RIGHT, which is the target's orientation in the source
-- interface; the player frame is the mirrored one there, and the client's own
-- frame XML is what flips it. So the target and its followers are drawn
-- unflipped -- the authored orientation, and one less transform -- while the
-- player is flipped here.
mw.units = {
  -- `header` nudges the name and level labels horizontally, in UI units, with
  -- positive meaning rightward on screen whichever side the label sits on.
  -- Per frame rather than derived from the mirroring: the two frames want
  -- different amounts on their right-hand label.
  { id = "player",       art = "playerFrame", bg = "playerFrameBg",
    power = "powerFill", mirror = true, shiftLabels = true,
    -- The player's power opening narrows slightly at both ends. Keep its fill
    -- clear of that rim without changing the health bar or any other frame.
    powerInset = 2,
    -- The health fill only overruns the rim at its right edge.
    healthRightInset = 2,
    -- Health box starts 2 units further right (and so is 2 narrower).
    healthLeftInset = 2,
    -- percentX nudges BOTH percentage readouts -- health and power -- at the
    -- inner end of this frame's bars. Per frame, because the target's sit
    -- against a mirrored housing and do not want the same inset.
    percentX = 2,
    -- The power box starts powerInset units right of the health box, so its
    -- percentage is pulled back by that difference to share the health one's
    -- screen x. Player only: the target's insets are left as they read today.
    alignPowerPercent = true,
    -- Horizontal nudge for this frame's aura rows only, in screen units with
    -- positive meaning rightward whichever way the housing is mirrored. The
    -- player's bar opening reads 3 units left of where its auras should line
    -- up; the target's does not, so this is per frame rather than shared.
    auraX = 3,
    header = { name = 3, level = -7 } },
  { id = "target",       art = "targetFrame", bg = "targetFrameBg",
    power = "powerFillTarget", classification = true, mirror = false,
    shiftLabels = true,
    -- The target health fill only overruns the rim at its left edge.
    healthLeftInset = 2,
    -- Extra rightward nudge for the power bar's percentage only.
    powerPercentX = 1,
    header = { name = -5, level = 6 } },
  -- Portrait LEFT, by request: the housing is flipped so the ring sits on the
  -- left. The bed takes the player file, whose opaque region lies under the
  -- portrait-left bar rectangle; the target bed only fits portrait-right.
  { id = "targettarget", art = "targetFrame", bg = "playerFrameBg",
    power = "totPowerFill", mirror = true,
    -- The single health bar is trimmed 3 units off its bottom edge, and its
    -- centred name kept on the bar's centre, to sit inside this compact housing.
    healthTrim = 3, nameY = 0 },
  -- Target art, not the imported partyFrame: that one is a 128x64 canvas with
  -- its own proportions, and M.modernWow.sourceLayout describes the 256x128
  -- one. Giving the pet its own layout is a separate job; borrowing the target
  -- housing keeps it consistent in the meantime rather than laying the pet out
  -- with numbers that do not describe its art.
  -- The pet mirrors the target housing into portrait-left reading order, so
  -- its unmirrored bed must be the player file. The target bed extends beneath
  -- the left-hand ring and shows through as two dark horizontal bands.
  { id = "pet",          art = "targetFrame", bg = "playerFrameBg",
    power = "totPowerFill", mirror = true, powerX = -2, healthValueX = -2,
    alignPowerPercent = true,
    header = { name = 2, level = -4 } },
}

-- The party block wears the SMALL pet canvas, which is what DragonflightUI
-- itself draws its party rows with -- modules/unit/mini.lua
-- Setup:PartyFramesSetup gives every PartyMemberFrame a 128x64 "pet" border, a
-- 35px portrait and 69-wide bars. That is why its party block is roughly half
-- the linear size of its player and target frames, and it is deliberate: the
-- large housing's proportions are fixed, so a party row cannot be that housing
-- shrunk down, it has to be the smaller canvas the art was authored as.
--
-- Every row in the block is identical, including party0 -- the player's own
-- row at the top. party0 is modules/unitframes.lua's PARTY_PLAYER_ID, a frame
-- id and never a unit token; that spec's unit is "player". It is listed here
-- so the row is dressed at all: mw.Entry keys off this table, and without an
-- entry it kept UnrealUI's flat chrome while the four members around it wore
-- Dragonflight art.
--
-- None of the large housing's per-frame nudges carry over. powerInset,
-- healthRightInset, percentX, auraX and the header offsets were each measured
-- against the 256x128 art's openings and mean nothing on a different canvas,
-- so the rows take the layout's own geometry unmodified. `bg` is absent for
-- the same reason: DragonflightUI ships a background bed for the two large
-- housings only, and this canvas draws its own recess.
do
  local ids = { "party0", "party1", "party2", "party3", "party4" }
  local i
  for i = 1, table.getn(ids) do
    table.insert(mw.units, {
      id = ids[i],
      art = "partyFrame",
      layout = "partyLayout",
      -- DragonflightUI fills the party mana bar with the TARGET mana art
      -- (mini.lua PartyFramesSetup), not the player's, so this matches it.
      power = "powerFillTarget",
      -- Portrait left, which is also how this canvas is authored, so
      -- BuildHousing draws it without flipping the texture.
      mirror = true,
      -- Name/level row, nudged two units left. Both ends take the SAME sign:
      -- these are SetPoint x offsets, which are screen-absolute, so negative
      -- moves each label left whichever edge of the bar it is anchored to --
      -- the row shifts rather than tightening. Per entry rather than in
      -- partyLayout because it is a placement preference on these rows, not a
      -- property of the canvas.
      header = { name = -2, level = -2 },
      -- 15% over the authored size, by request. DragonflightUI's party rows
      -- are deliberately half the linear size of its player and target frames;
      -- this keeps that relationship but makes the block easier to read.
      scale = 1.15,
    })
  end
end

-- Ornament art per target classification, in the spelling UnitClassification
-- returns on this client. A tier with no entry keeps the plain target ring,
-- which is also what an unreadable classification degrades to.
mw.classification = {
  rare      = "frameRare",
  elite     = "frameElite",
  rareelite = "frameRareElite",
  worldboss = "frameBoss",
}

-- Answered for modules/unitframes.lua at frame-build time, which is why it is
-- a plain predicate on U rather than anything that needs this module's state
-- to be initialised: modules/modernwow.lua is loaded last in the TOC, so this
-- chunk has run long before unitframes' OnEnable builds a frame.
--
-- Only the pet spec sets spec.portrait in UnrealUI's shared layout, and that
-- layout is frozen for `modern` and `classic-wow`. This adds the portrait for
-- the frames this theme's art is drawn around, and answers false for every
-- other theme, so nothing changes outside modern-wow.
function U.ModernWowWantsPortrait(id)
  if not mw.Active() or not mw.Enabled("unitframes") then return false end
  if type(id) ~= "string" then return false end

  local i
  for i = 1, table.getn(mw.units) do
    if mw.units[i].id == id then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The art drives the layout, not the other way round.
--
-- The first version of this painted Dragonflight art behind UnrealUI's own bar
-- boxes. That could never work: those boxes carry their own outline and their
-- fills span the full box, so the housing was completely hidden behind them
-- and only the ring stuck out. DragonflightUI does the opposite -- it pins
-- bars at fixed pixel offsets INSIDE the art (modules/unit/player.lua) -- and
-- that is what is reproduced here.
--
-- So this takes the frame over completely for this theme:
--
--   * the whole 256x128 frame art is drawn as ONE mirrored texture, which also
--     means a classification change is a single SetTexture and needs no slice
--     geometry at all;
--   * the frame is resized to the art's visible extent;
--   * health and power are re-anchored and resized into the art's own bar
--     rectangles, and their flat outline and backdrop come off;
--   * the portrait is sized and centred on the art's circle.
--
-- The art is at BACKGROUND on a frame below the bars, which is where
-- DragonflightUI puts it (PlayerFrameTexture:SetDrawLayer("BACKGROUND")). The
-- housing rim is beside the bars rather than over them, so nothing needs to
-- draw on top and the bars stay fully readable.
--
-- Scale comes from the configured bar width, so the one unit-frame setting
-- that still has a visible meaning under this theme keeps working: a wider bar
-- scales the whole frame with it and every proportion holds.
-- ---------------------------------------------------------------------------
-- Scale comes from the configured HEALTH BAR HEIGHT, not its width.
--
-- Width was the obvious choice and was wrong: every primary spec shares
-- PRIMARY_WIDTH, so target-of-target scaled to exactly the same size as the
-- target and the two frames collided, ornament over ornament. Height is what
-- actually distinguishes them -- player and target ask for 34, the compact
-- target-of-target for 18 -- so scaling by it reproduces the source
-- interface's relative sizing and keeps each spec's own proportions meaningful.
--
-- The bar ends up 130/30 times the health height, which is the source's own
-- ratio rather than the configured width. That is the trade this theme makes:
-- the art's proportions are fixed, so one of the two settings has to follow.
-- Reference scale: the health bar height the source art was authored against.
-- A frame whose spec asks for this height draws the art at 1.0, which is
-- exactly the size DragonflightUI draws it, and everything else scales in
-- proportion to it.
--
-- The primary specs ask for 34 rather than the source's 30, which drew the
-- whole frame 13% larger than the reference. Under a theme whose entire point
-- is reproducing that reference, the art wins: a primary frame is pinned to
-- 1.0 and only the genuinely different sizes -- the compact target-of-target
-- at 18, a party pet row -- scale down from it.
--
-- The consequence, and it is the trade this theme already made when the layout
-- became art-driven: the configured health-bar height no longer resizes a
-- primary frame. It still decides the relative size of the smaller frames.
function mw.ArtScale(frame, L)
  L = L or M.modernWow.sourceLayout
  local spec = frame.spec
  local height = spec and tonumber(spec.health)
  if not height or height <= 0 then
    height = mw.Dimension(frame, "GetHeight")
  end
  if height <= 0 then return 1 end

  -- At or above the authored height, draw the art at its authored size. The
  -- fixed pixel-perfect screen scale is deliberately not folded in here; it is
  -- applied once to the complete frame by mw.ApplyFrameScale.
  if height >= L.healthHeight then return 1 end
  return height / L.healthHeight
end

-- Strips one of UnrealUI's bar boxes back to just its fill, and moves it to an
-- art-space rectangle. Edge-only removal plus a cleared backdrop: the art
-- supplies both the outline and the bed, so the box must contribute neither.
function mw.PlaceBar(box, frame, s, x, y, w, h)
  if not box then return end

  mw.HideFlatEdges(box)
  pcall(box.SetBackdropColor, box, 0, 0, 0, 0)

  box:SetWidth(w)
  box:SetHeight(h)
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)

  -- The status bar inside the box was given an explicit size at build time and
  -- computes its fill from its own GetWidth (core/style.lua), so it has to be
  -- resized too or the fill keeps the old geometry.
  local bar = box.bar
  if bar then
    bar:SetWidth(w)
    bar:SetHeight(h)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)

    -- U.CreateStatusBar gives every bar its own dark BACKGROUND texture for the
    -- depleted portion. The source art already draws that recess, so leaving
    -- this on stacks a second flat bed on top of it and reads as a grey slab
    -- with the wrong edge -- which is what the housing's border looked like.
    -- Hidden rather than recoloured, so the art underneath is what shows when
    -- the bar is not full.
    if bar.uuiBackground then pcall(bar.uuiBackground.Hide, bar.uuiBackground) end
  end
end

-- Rewrites one spec's text layout to the source interface's, called from
-- modules/unitframes.lua BuildFrame before the frame exists.
--
-- The source puts a bare percentage at the inner end of each bar and the
-- absolute value at the outer end, with the unit's name and level on their own
-- row above -- where UnrealUI packs level and a combined "value - percent"
-- readout onto the health bar itself. mw.Entry decides which frames get it, so
-- a frame this theme does not dress keeps its declared labels.
function U.ModernWowSpecOverride(spec)
  if not mw.Active() or not mw.Enabled("unitframes") then return end
  if type(spec) ~= "table" then return end

  local entry = mw.Entry(spec.id)
  if not entry then return end

  -- Target-of-target stays a single centred name: it is one compact bar in
  -- both interfaces and a percentage on it reads as clutter.
  if spec.healthText then return end

  -- A layout may carry its own answer, because how much text fits is a
  -- property of the canvas's openings rather than of the frame. Copied field
  -- by field rather than assigned: the five party specs share one layout
  -- table, and handing them all the same labels table would make a later
  -- per-spec edit reach every row.
  local L = mw.Layout(entry)
  if L.healthLabels then
    spec.healthLabels = { left = L.healthLabels.left,
                          right = L.healthLabels.right }
  else
    spec.healthLabels = { left = "healthpct", right = "healthval" }
  end
  if L.healthLabelSize then spec.healthLabelSize = L.healthLabelSize end

  if spec.powerLabels then
    if L.powerText == false then
      spec.powerLabels = nil
    else
      spec.powerLabels = { left = "powerpct", right = "powerval" }
    end
  end

  -- The name/level row above the bars is drawn by this module rather than by
  -- the spec: UnrealUI's frame has no slot above the health bar, and the
  -- source art reserves one between the housing's top edge and the bar.
  spec.uuiModernWowHeader = true
end

-- Which canvas an entry is drawn from. The large 256x128 housing is the
-- default; an entry naming another layout in M.modernWow gets that one, which
-- is what lets the party block wear the small pet canvas at its own
-- proportions rather than the large housing shrunk down.
function mw.Layout(entry)
  local layout = entry and entry.layout
  return (layout and M.modernWow[layout]) or M.modernWow.sourceLayout
end

function mw.Entry(id)
  local i
  for i = 1, table.getn(mw.units) do
    if mw.units[i].id == id then return mw.units[i] end
  end
  return nil
end

-- Sizes and centres one portrait from the geometry BuildHousing recorded.
-- The measured size is fixed: every profile and account must reproduce the
-- same unit-frame geometry validated on Malgus.
function mw.ApplyPortraitSize(portrait)
  local geometry = portrait and portrait.uuiModernWowGeometry
  if not geometry or not geometry.frame then return end

  local size = geometry.size
  portrait:SetWidth(size)
  portrait:SetHeight(size)
  portrait:ClearAllPoints()
  portrait:SetPoint("CENTER", geometry.frame, "TOPLEFT", geometry.x, geometry.y)
  if portrait.icon then
    portrait.icon:ClearAllPoints()
    portrait.icon:SetAllPoints(portrait)
  end
end

-- Applies the fixed Malgus frame scale to one unit frame.
--
-- Malgus used the pixel-perfect path. Making it unconditional keeps one texel
-- at one screen pixel even when another account uses a different UIParent
-- scale, so the visible size remains constant rather than merely storing the
-- same profile number.
-- `entry.scale` multiplies that: a per-entry size trim applied to the WHOLE
-- frame, so the art, the bars, the portrait and the text all grow together and
-- the frame stays the same design at a different size. Growing the art in
-- art-space instead (mw.ArtScale) would leave the fonts at their declared
-- point size and change the design rather than its size.
--
-- The trade is explicit: a frame with a scale other than 1 is no longer
-- exactly one texel to one screen pixel, so its art is resampled. That is the
-- cost of asking for a size the art was not authored at, and it is why the
-- multiplier lives on the entries that opt in rather than on every frame.
function mw.ApplyFrameScale(frame, entry)
  if not frame then return end

  local scale = mw.PixelScaleFor(frame)
  local extra = entry and tonumber(entry.scale)
  if extra and extra > 0 then scale = scale * extra end

  pcall(frame.SetScale, frame, scale)
end

-- The frame scale that makes one texel cover exactly one screen pixel.
--
-- Drawing the 256x128 canvas at 256x128 UI units is NOT pixel perfect on this
-- client: a UI unit is wider than a screen pixel (core/media.lua records the
-- same thing for text shadow offsets), so UIParent's scale still resamples the
-- texture and the art is filtered rather than exact.
--
-- GetEffectiveScale includes the frame's OWN scale, so the frame is reset to 1
-- first; what comes back is then the scale of the parent chain alone, and its
-- reciprocal is the own-scale that cancels it. The frame's effective scale
-- becomes 1, one UI unit becomes one screen pixel, and the art lands 1:1.
function mw.PixelScaleFor(frame)
  pcall(frame.SetScale, frame, 1)

  local ok, effective = pcall(frame.GetEffectiveScale, frame)
  effective = ok and tonumber(effective) or nil
  if not effective or effective <= 0 then return 1 end

  return 1 / effective
end

-- Pulls a bar's outer value readout further in from the bar's edge.
--
-- Re-anchored rather than nudged: modules/unitframes.lua positions these with
-- a single SetPoint, and GetPoint is recorded in this addon as unreliable for
-- reading an anchor back (modules/castbar.lua notes it reports only the first
-- of several). The numbers below mirror that module's own BAR_LABEL_MARGIN of
-- 4 and its -2 / -1 vertical offsets, so the label lands where it did plus the
-- shift and nothing else moves.
function mw.ShiftBarLabel(box, yOffset, shiftX, percentX, valueX)
  if not box or not box.textLayer then return end

  local shift = shiftX and (tonumber(M.modernWow.labelShift) or 0) or 0
  percentX = tonumber(percentX) or 0
  valueX = tonumber(valueX) or 0

  -- Both ends are re-anchored so the vertical nudge moves the row together;
  -- per-entry horizontal offsets can then refine either end independently.
  if box.leftLabel then
    box.leftLabel:ClearAllPoints()
    box.leftLabel:SetPoint("LEFT", box.textLayer, "LEFT", 4 + percentX, yOffset)
  end
  if box.rightLabel then
    box.rightLabel:ClearAllPoints()
    box.rightLabel:SetPoint("RIGHT", box.textLayer, "RIGHT",
                            -4 - shift + valueX, yOffset)
  end
end

function mw.BuildHousing(frame, entry)
  if not frame or frame.uuiModernWow then return nil end

  local art = M.modernWow.texture[entry.art]
  if not art then return nil end

  -- modules/unitframes.lua's ApplyHealthColor only puts M.unitFrame.statusTexture
  -- -- which this theme points at the Dragonflight health art -- on a bar whose
  -- spec asks for healthTexture, and only the target spec does. Every other
  -- frame got flat WHITE8X8, which is why the player bar stayed a plain
  -- UnrealUI gradient under Dragonflight housing.
  --
  -- Set on the frame's own spec entry, which is one element of that module's
  -- SPECS list rather than a shared table, and only while this theme is the one
  -- that loaded. ApplyHealthColor re-reads it on every colour change, so this
  -- has to be the flag rather than a one-shot SetStatusBarTexture that the next
  -- health tick would overwrite.
  if frame.spec then frame.spec.healthTexture = true end

  local L = mw.Layout(entry)
  local s = mw.ArtScale(frame, L)

  local contentW = (L.contentRight - L.contentLeft) * s
  local contentH = (L.contentBottom - L.contentTop) * s

  -- The frame becomes the art's visible extent. Movers anchor the frame rather
  -- than read its size, and modules/auras.lua attaches to its edge, so both
  -- follow the new size instead of needing to know about it.
  frame:SetWidth(contentW)
  frame:SetHeight(contentH)

  local housing = CreateFrame("Frame", nil, frame)
  housing:SetAllPoints(frame)
  local level = mw.Dimension(frame, "GetFrameLevel")
  if level > 0 then pcall(housing.SetFrameLevel, housing, level) end

  -- Every measurement in a layout table is in the PLAYER's reading order
  -- (portrait left), because that is the orientation DragonflightUI's own
  -- numbers were taken from. A frame drawn the other way round -- the target,
  -- which is the orientation the large art is actually authored in -- flips
  -- each rectangle inside the content box instead of needing a second set of
  -- numbers.
  local mirrored = entry.mirror ~= false

  -- Whether the TEXTURE has to be flipped is a separate question from which
  -- way the frame reads, and the two only looked like one thing while every
  -- entry came off the same canvas. The large housing is authored ring-right,
  -- so a portrait-left frame flips it; the small pet canvas is authored
  -- ring-left, so the same portrait-left frame must NOT flip it. Reading the
  -- authored side off the layout keeps both cases in one expression.
  local flipArt = mirrored == (L.authoredRight ~= false)

  local function FlipX(x, w)
    if mirrored then return x end
    return contentW - x - (w or 0)
  end

  local artY = L.contentTop * s
  local artW = L.artWidth * s

  local function PlaceArt(texture)
    if not texture then return end
    texture:SetWidth(artW)
    texture:SetHeight(L.artHeight * s)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT",
                     FlipX(-L.contentLeft * s, artW), artY)
  end

  -- The background bed is NEVER mirrored, even on a frame whose housing is.
  -- Measured: its opaque region is x103..226 in the player file and x30..166 in
  -- the target one, and in each case that lands under the bar rectangle only if
  -- the texture is left as authored. Mirroring it with the housing threw the
  -- player's bed out to x30..153 -- a dark slab sitting to the left of the
  -- portrait, outside the frame's own bars.
  if entry.bg and M.modernWow.texture[entry.bg] then
    PlaceArt(mw.Texture(housing, "BACKGROUND", M.modernWow.texture[entry.bg],
                        0, 1, 0, 1))
  end

  -- The housing rim is drawn ABOVE the bars, on its own frame, rather than
  -- behind them on the housing.
  --
  -- It is safe because the art's interior is genuinely open where the bars sit:
  -- measured down the bar column, the opaque runs are y19..33 (the translucent
  -- name band), y52..54 (the divider between the two bars) and y63..67 (the
  -- bottom rim), with y34..51 and y55..62 fully transparent. So the rim, the
  -- divider and the band draw over the fills while the openings stay clear --
  -- which is what makes the border visible instead of being covered by a bar
  -- that overruns it.
  --
  -- DragonflightUI does the opposite (PlayerFrameTexture at BACKGROUND) and
  -- simply lets its bars cover the interior detail. Drawing it on top is what
  -- shows where the openings actually are, which is what the bar rectangles
  -- are being fitted to.
  local overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(frame)
  if level > 0 then pcall(overlay.SetFrameLevel, overlay, level + 20) end

  -- The pet's happiness badge and numeric readouts were built before this
  -- housing and normally sit only ten levels above their boxes. Promote them
  -- past the art overlay so the gold rim cannot cover the badge or either
  -- value. Kept pet-only because the request is specific to this frame.
  if entry.id == "pet" and level > 0 then
    if frame.happiness then
      pcall(frame.happiness.SetFrameLevel, frame.happiness, level + 21)
    end
    if frame.health and frame.health.textLayer then
      pcall(frame.health.textLayer.SetFrameLevel, frame.health.textLayer,
            level + 21)
    end
    if frame.power and frame.power.textLayer then
      pcall(frame.power.textLayer.SetFrameLevel, frame.power.textLayer,
            level + 21)
    end
  end

  -- One whole canvas, drawn mirrored for a player-orientation frame:
  -- descending horizontal coordinates flip it, ascending leave it as authored.
  --
  -- Cutting this into a separate housing and ornament, so the gold ring could
  -- carry its own scale, was tried and reverted -- the two pieces did not line
  -- up and the frame came apart on screen. The ring is baked into this canvas,
  -- so the only thing that resizes it is the canvas scale, which is what
  -- the fixed pixel-perfect scale sets for the whole frame art together.
  local u1, u2 = 0, 1
  if flipArt then u1, u2 = 1, 0 end

  local frameArt = mw.Texture(overlay, "ARTWORK", art, u1, u2, 0, 1)
  PlaceArt(frameArt)

  -- Bars, in the art's own rectangles. A frame with no power bar gives its
  -- health bar both rows, so the housing opening is never left half empty.
  local barX = (L.barX - L.contentLeft) * s
  local barW = L.barWidth * s
  local healthY = (L.healthY - L.contentTop) * s
  local healthH = L.healthHeight * s
  local headerY = 2 + (tonumber(L.headerY) or
                       tonumber(M.modernWow.text.headerY) or 0)
  -- The name/level row's point size, which a layout may raise for a canvas
  -- whose row is read at a different size. Resolved here rather than at each
  -- label because headerTop -- the aura rows' near edge -- is measured from
  -- the top of this text and has to follow it.
  local headerSize = tonumber(L.headerSize) or M.fontSize.small
  local headerTop = -healthY + headerY + headerSize
  local powerY = (L.powerY - L.contentTop) * s
  local powerH = L.powerHeight * s
  local powerPercentY = -1 +
                        (tonumber(M.modernWow.text.powerPercentY) or 0)
  local powerTextBottom = -powerY - powerH / 2 + powerPercentY -
                          M.fontSize.normal / 2

  -- modules/auras.lua consumes only these bounded numbers. Primary aura rows
  -- align with the visible bar opening and derive their column count from its
  -- width, with an optional per-frame horizontal nudge (`auraX`). Their near
  -- edge sits M.modernWow.aura.nameGap above the name/level row when drawn
  -- above the frame and powerGap under the power readout when drawn below,
  -- while every aura attached to a dressed unit frame uses the theme's icon
  -- scale. The below-frame position carries its own left edge as well, so its
  -- extra shift cannot reach a row drawn above the frame. No native widget is
  -- retained as an anchor.
  local auraLeft = FlipX(barX, barW) + (tonumber(entry.auraX) or 0)

  frame.uuiAuraLayout = {
    left = auraLeft,
    belowLeft = auraLeft + (tonumber(M.modernWow.aura.belowX) or 0),
    width = barW,
    iconScale = tonumber(M.modernWow.aura.iconScale) or 1,
    top = headerTop + (tonumber(M.modernWow.aura.nameGap) or 5),
    belowTop = powerTextBottom -
               (tonumber(M.modernWow.aura.powerGap) or 0),
  }

  if not frame.power then
    healthH = (L.powerY + L.powerHeight - L.healthY) * s
  end
  healthH = healthH - (tonumber(entry.healthTrim) or 0)

  local healthLeftInset = tonumber(entry.healthLeftInset) or 0
  local healthRightInset = tonumber(entry.healthRightInset) or 0
  mw.PlaceBar(frame.health, frame, s,
              FlipX(barX, barW) + healthLeftInset, healthY,
              barW - healthLeftInset - healthRightInset, healthH)
  if frame.power then
    local powerInset = tonumber(entry.powerInset) or 0
    mw.PlaceBar(frame.power, frame, s,
                FlipX(barX, barW) + powerInset +
                  (tonumber(entry.powerX) or 0),
                (L.powerY - L.contentTop) * s, barW - powerInset * 2,
                L.powerHeight * s)
  end

  -- -2 and -1 are modules/unitframes.lua's own BAR_LABEL_Y_OFFSET and
  -- POWER_LABEL_Y_OFFSET. The health row's lift applies to EVERY dressed
  -- frame unless its layout carries its own barLabelY -- the small canvas's
  -- opening is 18 units against the large housing's 30, so a nudge tuned on
  -- one does not read the same on the other. Same precedence as headerY
  -- above. The horizontal shift stays on the frames that ask for it.
  mw.ShiftBarLabel(frame.health,
                   -2 + (tonumber(L.barLabelY) or
                         tonumber(M.modernWow.text.barLabelY) or 0),
                   entry.shiftLabels, entry.percentX, entry.healthValueX)
  mw.ShiftBarLabel(frame.power, -1, entry.shiftLabels, entry.percentX)
  -- Centred single-label bars (target-of-target) take their own vertical nudge.
  if entry.nameY and frame.health and frame.health.label and
     frame.health.textLayer then
    frame.health.label:ClearAllPoints()
    frame.health.label:SetPoint("CENTER", frame.health.textLayer, "CENTER", 0,
                                tonumber(entry.nameY) or 0)
  end
  mw.AlignPercentages(frame, entry)

  -- Portrait: fitted to the ring's measured inner opening, with the square box
  -- chrome taken off so the gold rim is the only border it has. Per-art,
  -- because the player and target ornaments put their opening in slightly
  -- different places and a shared average reads as a misaligned portrait.
  local portrait = frame.portrait
  if portrait then
    local ring = M.modernWow.ring[entry.art] or
                 { size = L.portraitSize, x = L.circleX, y = L.circleY }
    mw.HideFlatEdges(portrait)
    pcall(portrait.SetBackdropColor, portrait, 0, 0, 0, 0)

    -- BELOW the rim overlay, so the gold ring draws over the portrait's edge.
    --
    -- The portrait is still built wider than the ring's opening -- 62 against
    -- 51 -- so it fills the hole completely and the rim crops it rather than
    -- leaving a gap. What shows is a 51-pixel circle inside the full-thickness
    -- gold ring, with the portrait tucked under the metal the way a frame sits
    -- over a picture.
    --
    -- Stacking is now: bars, then portrait, then the frame art over both.
    if level > 0 then pcall(portrait.SetFrameLevel, portrait, level + 1) end

    -- Geometry kept on the frame so the fixed portrait placement stays in one
    -- path and cannot diverge between the initial build and later reuse.
    portrait.uuiModernWowGeometry = {
      size = ring.size * s,
      x = FlipX((ring.x - L.contentLeft) * s, 0),
      y = -(ring.y - L.contentTop) * s,
      frame = frame,
    }
    mw.ApplyPortraitSize(portrait)
  end

  -- Name and level, on their own row above the health bar. The source art
  -- leaves a strip between the housing's top edge and the bar for exactly
  -- this, and the row mirrors with the frame: the player reads name-then-level
  -- left to right, the target reads level-then-name.
  if frame.spec and frame.spec.uuiModernWowHeader and frame.health then
    local outer = entry.mirror ~= false and "LEFT" or "RIGHT"
    local inner = entry.mirror ~= false and "RIGHT" or "LEFT"

    -- Above the frame art, not under it. These used to live on the housing at
    -- the frame's own level, which put them beneath the art overlay: the name
    -- band the art draws across that row is translucent, so the text showed
    -- through it dimmed and muddied instead of sitting cleanly on top.
    local textLayer = CreateFrame("Frame", nil, frame)
    textLayer:SetAllPoints(frame)
    if level > 0 then pcall(textLayer.SetFrameLevel, textLayer, level + 21) end

    local name = U.CreateLabel(textLayer, {
      size = headerSize,
      color = M.color.text,
      inherits = "GameFontNormalSmall",
      fontRole = "unitframe",
      justify = outer,
    })
    local offsets = entry.header or {}
    if name then
      name:SetPoint("BOTTOM" .. outer, frame.health, "TOP" .. outer,
                    tonumber(offsets.name) or 0, headerY)
    end

    -- levelText, not `level`: the numeric frame level is still in scope here
    -- and textLayer above reads it. Shadowing it worked only because a Lua
    -- local starts after its own declaration, which is a trap for anyone
    -- reordering these lines.
    local levelText = U.CreateLabel(textLayer, {
      size = headerSize,
      color = M.color.textAccent,
      inherits = "GameFontNormalSmall",
      fontRole = "unitframe",
      justify = inner,
    })
    if levelText then
      levelText:SetPoint("BOTTOM" .. inner, frame.health, "TOP" .. inner,
                         tonumber(offsets.level) or 0, headerY)
    end

    -- How much width the name may use before it reaches the level at the other
    -- end: the bar's width less both labels' insets, less the room the level
    -- itself needs. Recomputed nowhere -- the bar does not resize after this.
    local barWidth = mw.Dimension(frame.health, "GetWidth")
    local nameBudget = barWidth
                       - math.abs(tonumber(offsets.name) or 0)
                       - math.abs(tonumber(offsets.level) or 0)
                       - (tonumber(L.levelReserve) or
                          tonumber(M.modernWow.text.levelReserve) or 0)

    frame.uuiModernWowHeaderText = { name = name, level = levelText,
                                     nameBudget = nameBudget }
  end

  mw.ApplyFrameScale(frame, entry)

  frame.uuiModernWow = { housing = housing, overlay = overlay,
                         frameArt = frameArt, art = art, scale = s }
  return frame.uuiModernWow
end

-- Pins the power bar's percentage to the same horizontal position as the
-- health bar's.
--
-- Both are already anchored LEFT at the same computed offset inside boxes that
-- share an x, so in principle they cannot differ -- but they are placed by two
-- separate calls against two separate text layers, and this removes the "in
-- principle". The health label's resolved offset is read back and applied to
-- the power label, so whatever the first one ended up at, the second matches.
--
-- GetPoint(1) is safe here: modules/castbar.lua records it as reporting only
-- the FIRST of several anchors, and these labels carry exactly one
-- (knowledge.json / fonts.stretched_justification_ignored is why they are
-- single-anchored). The computed value stays as the fallback.
function mw.AlignPercentages(frame, entry)
  if not frame or not frame.health or not frame.power then return end

  local source = frame.health.leftLabel
  local target = frame.power.leftLabel
  if not source or not target or not frame.power.textLayer then return end

  local ok, _, _, _, x = pcall(source.GetPoint, source, 1)
  x = ok and tonumber(x) or nil
  if not x then return end

  -- Each offset is relative to its own box, and mw.BuildHousing may inset or
  -- shift the two boxes independently. Opted-in frames cancel that difference
  -- so the readouts share one screen x rather than one box-relative x.
  if entry and entry.alignPowerPercent then
    x = x - ((tonumber(entry.powerInset) or 0) +
             (tonumber(entry.powerX) or 0) -
             (tonumber(entry.healthLeftInset) or 0))
  end
  if entry then x = x + (tonumber(entry.powerPercentX) or 0) end

  -- The vertical offset is taken from the power bar's own VALUE label, not
  -- from the percentage's current position: the two readouts sit at either end
  -- of the same row, so the percentage follows whatever the value ended up at
  -- and the row cannot end up staggered.
  local y = -1
  local peer = frame.power.rightLabel
  if peer then
    local okY, _, _, _, _, peerY = pcall(peer.GetPoint, peer, 1)
    if okY and tonumber(peerY) then y = tonumber(peerY) end
  end

  y = y + (tonumber(M.modernWow.text.powerPercentY) or 0)

  target:ClearAllPoints()
  target:SetPoint("LEFT", frame.power.textLayer, "LEFT", x, y)
end

-- The power bar's text size. 0 means "leave it alone": the labels keep the
-- size modules/unitframes.lua gave them.
function mw.PowerTextSize()
  local value = tonumber(mw.Config().powerTextSize)
  if not value or value <= 0 then return 0 end
  return value
end

-- Re-sizes one frame's power-bar readouts.
--
-- Only the power row, and only through U.SetFont, which is the shared path
-- that also carries the font-role choice and the guarded custom-face handling
-- (core/compat.lua). Setting the face directly on a FontString is recorded as
-- silently failing on this client
-- (knowledge.json / fonts.pfui_path_and_measure.v1), so nothing here touches
-- SetFont on the widget itself.
function mw.ApplyPowerTextSize(frame)
  local size = mw.PowerTextSize()
  if size <= 0 or not frame or not frame.power then return end

  local labels = { frame.power.leftLabel, frame.power.rightLabel }
  local i
  for i = 1, table.getn(labels) do
    if labels[i] then
      pcall(U.SetFont, labels[i], size, nil, "unitframe")
    end
  end
end

-- `/uui mw powertext <n>` -- try a text size on every frame's power bar, live.
-- 0 restores whatever the unit-frame module set.
function U.ModernWowSetPowerTextSize(value)
  value = tonumber(value)
  if not value or value < 0 then
    U.Print("modern-wow: power text size is " ..
            (mw.PowerTextSize() > 0 and mw.PowerTextSize() or "default") ..
            " -- /uui mw powertext <number>, 0 for the default")
    return false
  end

  mw.Config().powerTextSize = value

  if value <= 0 then
    U.Print("modern-wow: power text size back to default -- /reload to apply")
    return true
  end

  local i
  for i = 1, table.getn(mw.units) do
    mw.ApplyPowerTextSize(type(U.GetUnitFrame) == "function"
                          and U.GetUnitFrame(mw.units[i].id) or nil)
  end

  U.Print("modern-wow: power text size " .. value)
  return true
end

-- Trims a name until it fits the room left beside the level label.
--
-- The name's own edge never moves -- it is anchored to the single edge it
-- belongs to, per knowledge.json / fonts.stretched_justification_ignored,
-- which is what keeps the outer end fixed however long the name is. What can
-- collide is the INNER end, where the text grows towards the level.
--
-- Measured rather than capped at a character count: a 12-character name of
-- wide glyphs is far longer on screen than twelve narrow ones, so a fixed cap
-- either truncates short names needlessly or lets wide ones overlap.
-- GetStringWidth is SUPPORTED / BEHAVIOR_VERIFIED on this client
-- (behavior.json / questgivertextmethods), and the character cap stays as the
-- fallback for the case where it is missing or returns nothing usable.
function mw.FitName(text, value)
  if value == "" then return value end

  local budget = text.nameBudget
  if not budget or budget <= 0 then
    if string.len(value) > 12 then return string.sub(value, 1, 12) end
    return value
  end

  text.name:SetText(value)
  local ok, width = pcall(text.name.GetStringWidth, text.name)
  width = ok and tonumber(width) or nil
  if not width then
    if string.len(value) > 12 then return string.sub(value, 1, 12) end
    return value
  end

  -- Drop a character at a time and re-measure. Names are short, so this costs
  -- a handful of iterations at most and only when the name actually changes.
  local trimmed = value
  while width > budget and string.len(trimmed) > 1 do
    trimmed = string.sub(trimmed, 1, string.len(trimmed) - 1)
    text.name:SetText(trimmed)
    ok, width = pcall(text.name.GetStringWidth, text.name)
    width = ok and tonumber(width) or budget
  end
  return trimmed
end

-- Fills the name/level row. Called from modules/unitframes.lua's refresh, so
-- it runs on the same schedule as every other readout and reads only the data
-- that refresh already gathered -- no client query of its own.
function U.ModernWowRefreshHeader(frame)
  local text = frame and frame.uuiModernWowHeaderText
  if not text then return end

  local data = frame.data or {}

  if text.name then
    local value = data.name
    if data.connected == false or type(value) ~= "string" then value = "" end
    if frame.spec and frame.spec.targetReactionName and
       type(U.UnitFrameNameColor) == "function" then
      local r, g, b = U.UnitFrameNameColor(data, true)
      pcall(text.name.SetTextColor, text.name, r, g, b, 1)
    end
    text.name:SetText(mw.FitName(text, value))
  end

  if text.level then
    local value = data.level
    text.level:SetText(type(value) == "number" and value > 0
                       and tostring(value) or "")
  end
end

-- Retargets one frame's power fill to the Dragonflight mana/rage art. Goes
-- through U.SetStatusBarTexture (core/style.lua) rather than touching the
-- texture directly, so the bar's remembered uuiTexturePath stays truthful and
-- any prediction segment built on it follows.
function mw.ApplyPowerFill(frame, entry)
  if not entry.power or not frame.power or not frame.power.bar then return end
  local fill = M.modernWow.texture[entry.power]
  if not fill then return end
  pcall(U.SetStatusBarTexture, frame.power.bar, fill)
end

-- Swaps only the ornament texture when the target's classification changes.
-- Nothing is rebuilt, and nothing native is read: UnitClassification is a unit
-- query, not a frame walk.
function mw.RefreshClassification()
  local frame = type(U.GetUnitFrame) == "function" and U.GetUnitFrame("target")
  local state = frame and frame.uuiModernWow
  if not state or not state.frameArt then return end

  -- One texture swap. Every tier shares the same bar rectangle and differs
  -- only in the ornament around the portrait, so nothing has to move: the
  -- wider boss and rare-elite wings are already inside the drawn canvas.
  local ok, tier = pcall(UnitClassification, "target")
  local art = nil
  if ok and type(tier) == "string" then
    art = M.modernWow.texture[mw.classification[tier] or ""]
  end
  pcall(state.frameArt.SetTexture, state.frameArt, art or state.art)
end

function mw.BuildUnitFrames()
  if type(U.GetUnitFrame) ~= "function" then return end

  local i
  for i = 1, table.getn(mw.units) do
    local entry = mw.units[i]
    local frame = U.GetUnitFrame(entry.id)
    if frame then
      mw.BuildHousing(frame, entry)
      mw.ApplyPowerFill(frame, entry)
    end
  end

  -- Unit frames build before this surface gives them their art-derived aura
  -- origins. Re-apply the existing player/target selection now that those
  -- bounded coordinates exist, placing the circular row opposite the auras.
  if type(U.ApplyComboPointAnchor) == "function" and
     type(U.GetComboPointAnchor) == "function" then
    U.ApplyComboPointAnchor(U.GetComboPointAnchor())
  end

  -- The party rows were just scaled; their anchor was sized before that, from
  -- the scale the rows had at build time. Re-measure it so the party mover's
  -- rect matches the block this surface draws.
  if type(U.RelayoutPartyBlock) == "function" then U.RelayoutPartyBlock() end

  U.RegisterEvent("PLAYER_TARGET_CHANGED", mw.RefreshClassification)
  mw.RefreshClassification()
end

-- This surface keeps modern-wow's existing per-surface off switch, but the
-- mechanism is shared with the Modern unit frames in core/statusbarfx.lua:
-- one time-based updater, a bounded cutout pool and an additive colour pulse.
function mw.BuildBarFX()
  if type(U.AttachStatusBarFX) ~= "function" then return end
  local i
  for i = 1, table.getn(mw.units) do
    local frame = type(U.GetUnitFrame) == "function"
                  and U.GetUnitFrame(mw.units[i].id) or nil
    if frame then
      if frame.health then U.AttachStatusBarFX(frame.health.bar) end
      if frame.power then U.AttachStatusBarFX(frame.power.bar) end
    end
  end

  -- Player only: target and pet casts are reconstructed from combat text and
  -- keep their existing direct progress path. The player's bar has the exact
  -- event-driven timing contract needed by the shared effect.
  local castbar = U.G("UnrealUICastBar")
  if castbar and castbar.bar then
    U.AttachStatusBarFX(castbar.bar)
    -- The shared pulse is a flat square over the filled span; drawn with the
    -- cast-bar mask instead, its corners follow the housing's shape rather
    -- than poking past the rim. Only the texture changes: placement, tint and
    -- timing stay core/statusbarfx.lua's.
    local state = castbar.bar.uuiStatusBarFX
    if state and state.pulse then
      pcall(state.pulse.SetTexture, state.pulse, M.modernWow.texture.castMask)
    end
  end
end


-- ---------------------------------------------------------------------------
-- Surface: player combat and rest effects
--
-- Two pieces of state art on the player frame, reproducing what
-- DragonflightUI draws on its own (modules/unit/player.lua Setup:CombatGlow,
-- Setup:RestingGlow and Setup:RestingZZZ): an additive halo that breathes red
-- in combat and cyan while resting, and a flipbook Z animation above the
-- portrait while resting. All the measured geometry is in
-- M.modernWow.playerFX; nothing here builds a path or a rectangle of its own.
--
-- WORKING_SOURCE, and weaker than usual. The source's own resting animation
-- has never run: it points at a texture DragonflightUI does not ship, so its
-- script is untested code and its 36-cell texture-coordinate table does not
-- even describe the 42-cell sheet used here. The behaviour was taken from it;
-- none of it is runtime evidence about this client.
--
-- WHAT IS NOT COPIED FROM THE SOURCE:
--
--   * `arg1` as the per-tick delta. This client passes OnUpdate handlers no
--     arguments at all (knowledge.json /
--     scripts.onupdate_elapsed_only_via_arg1, BEHAVIOR_VERIFIED), so elapsed
--     comes from GetTime, the same way core/statusbarfx.lua and
--     core/easing.lua derive theirs.
--   * math.sin for the pulse curve. query_compat.py has no record of it on
--     this client, and U.EaseInOutCubic is the addon's own shared curve --
--     ping-ponged, it is the same breathe.
--   * event-driven state. Neither PLAYER_REGEN_DISABLED/ENABLED nor
--     PLAYER_UPDATE_RESTING has usable evidence here, so the state is polled
--     on M.modernWow.playerFX.pollInterval instead. An event that never fires
--     would otherwise leave the glow stuck on, or never start it.
--   * two independent overlays. The source runs a combat pulse and a resting
--     pulse side by side, which add to near-white when a fight starts in an
--     inn. One overlay is drawn here and combat wins the colour, since combat
--     is the state worth reading at a glance.
--
-- The glow is a texture on the housing's existing overlay frame rather than a
-- frame of its own: at OVERLAY draw layer it lands above the frame art, which
-- is ARTWORK on that same frame, and still below the name/level row, which is
-- a higher frame level. Nothing native is touched, anchored to, or retained.
-- ---------------------------------------------------------------------------
mw.playerFX = {
  updateId = "modernwow.playerfx",
  alpha = 0,
  pulseTime = 0,
  pollTime = 0,
  cellTime = 0,
  cell = 1,
  resting = false,
  combat = false,
}

function mw.PlayerFXNow()
  if not mw.playerFX.getTime then
    mw.playerFX.getTime = U.G("GetTime")
  end
  if type(mw.playerFX.getTime) ~= "function" then return nil end
  local ok, value = pcall(mw.playerFX.getTime)
  if not ok or type(value) ~= "number" then return nil end
  return value
end

-- A unit query that reads false rather than erroring when the call is missing,
-- matching how modules/unitframes.lua treats IsResting.
function mw.PlayerFXTruth(name, unit)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  local ok, value = pcall(fn, unit)
  if not ok then return false end
  if value == nil or value == false or value == 0 or value == "" then
    return false
  end
  return true
end

-- Maps the halo's own visible rectangle onto the frame art's, in the
-- screen-order art pixels BuildHousing already works in. See the coordinate
-- note on M.modernWow.playerFX: the two rectangles are measured in different
-- files and must not be swapped.
function mw.BuildStatusGlow(frame, state, s)
  local cfg = M.modernWow.playerFX
  local L = M.modernWow.sourceLayout

  local glowW = cfg.glowRight - cfg.glowLeft
  local glowH = cfg.glowBottom - cfg.glowTop
  if glowW <= 0 or glowH <= 0 then return nil end

  local scaleX = (cfg.fitRight - cfg.fitLeft) / glowW
  local scaleY = (cfg.fitBottom - cfg.fitTop) / glowH

  -- No SetTexCoord: the file is authored in the player's own screen order, so
  -- unlike the frame art it needs no flip. This surface is player-only, which
  -- is what makes leaving it out safe.
  local glow = mw.Texture(state.overlay, "OVERLAY",
                          M.modernWow.texture.playerStatus)
  if not glow then return nil end

  glow:SetWidth(cfg.glowWidth * scaleX * s)
  glow:SetHeight(cfg.glowHeight * scaleY * s)
  glow:SetPoint("TOPLEFT", frame, "TOPLEFT",
                (cfg.fitLeft - L.contentLeft) * s - cfg.glowLeft * scaleX * s
                  + (cfg.glowOffsetX or 0),
                -(cfg.fitTop - L.contentTop) * s + cfg.glowTop * scaleY * s
                  + (cfg.glowOffsetY or 0))

  -- Additive so the halo only ever brightens the frame art beneath it; the
  -- shape is in the alpha, which ADD weights by, so the surround adds nothing.
  pcall(glow.SetBlendMode, glow, "ADD")
  pcall(glow.SetAlpha, glow, 0)
  pcall(glow.Hide, glow)
  return glow
end

function mw.BuildRestingCells(frame, s)
  local cfg = M.modernWow.playerFX
  local L = M.modernWow.sourceLayout
  local icon = cfg.icon

  -- Its own frame, above the art overlay and the name row, because the glyph
  -- floats over the top edge of the housing rather than sitting inside it.
  local layer = CreateFrame("Frame", nil, frame)
  layer:SetWidth(icon.size * s)
  layer:SetHeight(icon.size * s)
  layer:SetPoint("CENTER", frame, "TOPLEFT",
                 (icon.x - L.contentLeft) * s,
                 -(icon.y - L.contentTop) * s)

  local level = mw.Dimension(frame, "GetFrameLevel")
  if level > 0 then pcall(layer.SetFrameLevel, layer, level + 23) end

  local texture = mw.Texture(layer, "OVERLAY",
                             M.modernWow.texture.restingFlipbook)
  if not texture then return nil end
  texture:SetAllPoints(layer)

  pcall(layer.Hide, layer)
  return { layer = layer, texture = texture }
end

-- One cell of the flipbook, by index, counting left to right then down.
function mw.ShowRestingCell(index)
  local fx = mw.playerFX
  if not fx.zzz then return end

  local cfg = M.modernWow.playerFX
  local unit = cfg.restCell / cfg.restSheet
  local column = math.mod(index - 1, cfg.restColumns)
  local row = math.floor((index - 1) / cfg.restColumns)
  pcall(fx.zzz.texture.SetTexCoord, fx.zzz.texture,
        column * unit, (column + 1) * unit, row * unit, (row + 1) * unit)
end

function mw.PlayerFXPoll()
  local fx = mw.playerFX
  local cfg = M.modernWow.playerFX

  fx.resting = mw.PlayerFXTruth("IsResting")
  fx.combat = mw.PlayerFXTruth("UnitAffectingCombat", "player")

  -- Combat wins the colour; see the note above on why there is one overlay
  -- rather than the source's two.
  local tint = nil
  if fx.combat then tint = cfg.combatColor
  elseif fx.resting then tint = cfg.restColor end

  if tint and tint ~= fx.tint and fx.glow then
    fx.tint = tint
    pcall(fx.glow.SetVertexColor, fx.glow, tint[1], tint[2], tint[3])
  end

  if fx.zzz and fx.restingShown ~= fx.resting then
    fx.restingShown = fx.resting
    if fx.resting then
      -- Restart the animation on each entry rather than resuming wherever the
      -- last stay left off.
      fx.cell = 1
      fx.cellTime = 0
      mw.ShowRestingCell(fx.cell)
      pcall(fx.zzz.layer.Show, fx.zzz.layer)
    else
      pcall(fx.zzz.layer.Hide, fx.zzz.layer)
    end
  end
end

function mw.PlayerFXTick()
  local fx = mw.playerFX
  local cfg = M.modernWow.playerFX

  local now = mw.PlayerFXNow()
  if not now then return end
  local elapsed = now - (fx.lastTick or now)
  fx.lastTick = now
  if elapsed < 0 then elapsed = 0 end
  -- A load stall must not be replayed: every value here describes current
  -- state rather than integrating one, and the cell loop below is bounded by
  -- this clamp.
  if elapsed > 0.25 then elapsed = 0.25 end

  fx.pollTime = fx.pollTime + elapsed
  if fx.pollTime >= cfg.pollInterval then
    fx.pollTime = 0
    mw.PlayerFXPoll()
  end

  local active = fx.combat or fx.resting

  if fx.glow then
    if active then
      fx.pulseTime = math.mod(fx.pulseTime + elapsed, cfg.pulsePeriod)
      -- Ping-pong through the shared ease so the breathe is symmetric: out
      -- over the first half of the period, back over the second.
      local progress = fx.pulseTime / cfg.pulsePeriod
      local swing = progress < 0.5 and progress * 2 or (1 - progress) * 2
      fx.alpha = cfg.alphaMin +
                 (cfg.alphaMax - cfg.alphaMin) * U.EaseInOutCubic(swing)
    elseif fx.alpha > 0 then
      fx.pulseTime = 0
      fx.alpha = fx.alpha - elapsed * cfg.fadeSpeed
      if fx.alpha < 0 then fx.alpha = 0 end
    end

    if fx.alpha ~= fx.shownAlpha then
      fx.shownAlpha = fx.alpha
      pcall(fx.glow.SetAlpha, fx.glow, fx.alpha)
      if fx.alpha > 0 then pcall(fx.glow.Show, fx.glow)
      else pcall(fx.glow.Hide, fx.glow) end
    end
  end

  if fx.resting and fx.zzz then
    fx.cellTime = fx.cellTime + elapsed
    while fx.cellTime >= cfg.restInterval do
      fx.cellTime = fx.cellTime - cfg.restInterval
      fx.cell = fx.cell + 1
      if fx.cell > cfg.restColumns * cfg.restRows then fx.cell = 1 end
      mw.ShowRestingCell(fx.cell)
    end
  end
end

-- Player only. The halo is authored around one frame and the resting glyph
-- answers a question only the player has, so neither belongs on a target or a
-- party row -- which is also what makes the unflipped texture above safe.
function mw.BuildPlayerFX()
  if type(U.GetUnitFrame) ~= "function" then return end

  local frame = U.GetUnitFrame("player")
  local state = frame and frame.uuiModernWow
  -- Nothing to dress without the housing: both pieces are positioned against
  -- the frame art, so with the unit-frame surface off this surface has no
  -- geometry to work from and stays dark rather than inventing one.
  if not state or not state.overlay then return end

  local fx = mw.playerFX
  fx.glow = mw.BuildStatusGlow(frame, state, state.scale or 1)
  fx.zzz = mw.BuildRestingCells(frame, state.scale or 1)
  if not fx.glow and not fx.zzz then return end

  mw.PlayerFXPoll()
  U.RegisterUpdate(fx.updateId, 0, mw.PlayerFXTick)
end

-- ---------------------------------------------------------------------------
-- Surface: cast bars
--
-- A reproduction of DragonflightUI's castbar (its modules/cast/cast.lua) on
-- UnrealUI's own bars, piece for piece:
--
--   * the 512x32 background art behind the fill, tinted with that addon's
--     default castColor (0.9) at its default darkMode (0);
--   * the gold fill -- the imported CastingBarStandard3 art under a
--     (1, 0.82, 0) vertex colour, which is exactly how it is drawn there.
--     The fill is CROPPED to the progress, not stretched: DragonflightUI sets
--     SetTexCoord(0, progress, 0, 1) on every update, so the gradient the
--     artist authored keeps its proportions as the bar fills;
--   * the frame rim over the fill, same tint, because the art's opening is
--     transparent and the gold edge belongs on top;
--   * the drop shadow below it, at that addon's own +1/+9/+5 geometry;
--   * the additive spark riding the fill edge, hidden at both ends;
--   * the white flash on a completed cast, ramped up at flashSpeed and then
--     faded out at alphaSpeed;
--   * the spell name and the countdown BELOW the bar rather than on it, which
--     is where that interface puts them.
--
-- What is deliberately NOT reproduced, and why:
--
--   * its fill smoothing (`currentProgress` lerped at elapsed * 2). For a cast
--     running forward that lerp resolves to the value UnrealUI's tick already
--     computes from the elapsed time, and pushback is handled in
--     modules/castbar.lua by moving the start, which is the native rollback.
--   * its OUTLINE font flag. U.SetFont applies a named Font object without
--     flags on this client (core/compat.lua -- direct FontString:SetFont is
--     the confirmed silent-failure route), so the labels keep UnrealUI's
--     verified text shadow, which does the same job over a bright fill.
--   * its config surface (fill direction, dark mode, per-bar fonts) and its
--     ShaguTweaks icon poller. UnrealUI already owns the icon, and a theme is
--     not the place to grow a second settings system.
--
-- The end-of-cast behaviour arrives through the uuiFinish / uuiFinishTick /
-- uuiFinishEnd hooks modules/castbar.lua offers: fill to full and flash for a
-- completed cast, the interrupted art plus FAILED/INTERRUPTED text and a
-- one-second hold for one that did not finish, a straight fade for a drained
-- channel. The per-state fills (cast / channel / craft) arrive through
-- uuiCastKind, and a channel drains because the widget sets uuiDrainChannel. Those hooks are inert for every
-- other theme, which is why the animation lives here and not there.
-- ---------------------------------------------------------------------------
mw.castBars = {
  "UnrealUICastBar",
  "UnrealUICastBarTarget",
  "UnrealUICastBarPet",
}

-- DragonflightUI's own castbar constants, kept in its units. The growth
-- numbers are absolute there as well -- its barHeight callback sets the spark
-- to height + 15 and the shadow to height + 9 whatever the bar measures -- so
-- they are applied to UnrealUI's taller bar unchanged.
mw.cast = {
  -- Well under full size. DragonflightUI's bar is 200x16 and UnrealUI's is
  -- both wider and half again as tall, so the housing art reads large against
  -- the rest of this interface at 1. Frame:SetScale is the same mechanism the
  -- unit-frame surface uses above (mw.ApplyFrameScale) and the same one
  -- DragonflightUI's own size slider uses, so the art, the bars, the spark and
  -- the labels all come down together and no geometry falls out of step.
  -- Applied to every bar this surface dresses, the pet bar included -- that
  -- one is therefore a quarter narrower than the pet frame it hangs under.
  -- This is the shipped default only; /uui mw cast overrides it per profile.
  scale       = 0.75,
  alphaSpeed  = 3.0,
  flashSpeed  = 5.0,
  holdTime    = 1,
  sparkWidth  = 25,
  sparkGrow   = 15,
  -- The drop shadow, stated as the two distances that describe it rather than
  -- as a width and a texture height: how far it reaches ABOVE the bar's bottom
  -- edge (behind the bar, DragonflightUI's own 5) and how far it reaches BELOW
  -- it. Its own height is the sum, so `shadowDrop` is the height control --
  -- lower it and the shadow gets shorter without moving. Its width is not a
  -- number at all: it is pinned to the bar's own left and right edges, so it
  -- can never overhang either side whatever the bar measures.
  -- 5 + 14.5 = 19.5 tall, a quarter under the 26 it was drawn at first. The
  -- lift is held at DragonflightUI's own 5 so the shadow keeps meeting the bar
  -- the same way; the whole reduction comes off the bottom.
  shadowLift  = 5,
  shadowDrop  = 14.5,
  textInset   = 5,
  -- The gap between the bar's bottom edge and the label row. DragonflightUI's
  -- own is 8 -- its default fontY of -16 on a 16-high bar is half the bar plus
  -- 8 -- and this is two under it, which keeps the row inside the shortened
  -- drop shadow above rather than sitting on its bottom edge.
  textGap     = 6,
  fontSize    = 12,
  chrome      = { 0.90, 0.90, 0.90, 1.00 },
  -- The fills carry their own state colour now (mw.castFills), so the
  -- finish no longer tints the bar green or red and the flash stays white.
  flashColor  = { 1.00, 1.00, 1.00, 1.00 },
}

-- How far along the bar is, as 0..1 and as a width in bar units. Read off the
-- shared status bar's remembered values rather than from the cast module's
-- state, the way modules/castbarclassic.lua reads them for its own spark.
function mw.CastProgress(bar)
  local size = mw.Dimension(bar, "GetWidth")
  local minimum = tonumber(bar.uuiMin) or 0
  local range = (tonumber(bar.uuiMax) or 0) - minimum
  if range <= 0 or size <= 0 then return 0, 0 end

  local progress = ((tonumber(bar.uuiValue) or 0) - minimum) / range
  if progress < 0 then progress = 0 end
  if progress > 1 then progress = 1 end
  return progress, progress * size
end

-- Installed as widget.uuiUpdateSpark, which modules/castbar.lua calls on every
-- fill write (SetUnitBarValue) -- the start, each tick, and the immediate
-- redraw a pushback forces. That is the one seam where both the crop and the
-- spark have to follow the fill, so both are done here.
function mw.CastFillUpdate(widget)
  local state = widget and widget.uuiModernWow
  local bar = widget and widget.bar
  if not state or not bar then return end

  local progress, extent = mw.CastProgress(bar)

  -- Skipped at zero, where core/style.lua has hidden the fill anyway: a
  -- zero-width UV rectangle is the one shape worth not handing this client.
  if bar.uuiFillTexture and progress > 0 then
    pcall(bar.uuiFillTexture.SetTexCoord, bar.uuiFillTexture,
          0, progress, 0, 1)
  end

  if not state.spark then return end
  -- Hidden at both ends, as in the source: a spark at zero sits outside the
  -- rim, and a spark at full sits on the closing edge of it.
  if progress <= 0 or progress >= 1 then
    if state.spark:IsShown() then state.spark:Hide() end
    return
  end
  state.spark:ClearAllPoints()
  state.spark:SetPoint("CENTER", bar, "LEFT", extent, 0)
  if not state.spark:IsShown() then state.spark:Show() end
end

-- The Dragonflight fill for each cast state. Every one is pre-shaped by
-- CastingBarMask (tools/import_modern_wow_media.py MASKED): this client has no
-- texture mask, and the SetTexCoord crop above keeps the baked shape on the
-- bar geometry the way a live mask would.
mw.castFills = {
  cast        = "castFill",
  channel     = "castFillChannel",
  craft       = "castFillCraft",
  interrupted = "castFillInterrupted",
}

function mw.CastSetFill(widget, kind)
  local bar = widget and widget.bar
  if not bar then return end
  local key = mw.castFills[kind] or mw.castFills.cast
  -- Through the shared setter, so the bar's remembered uuiTexturePath -- which
  -- core/statusbarfx.lua copies onto its cutouts -- stays truthful.
  pcall(U.SetStatusBarTexture, bar, M.modernWow.texture[key])
end

-- Installed as widget.uuiCastKind: modules/castbar.lua names the cast before
-- its first fill write ("cast", "channel" or "craft").
function mw.CastKind(widget, kind)
  local state = widget and widget.uuiModernWow
  if not state then return end
  state.kind = mw.castFills[kind] and kind or "cast"
  mw.CastSetFill(widget, state.kind)
end

-- Installed as widget.uuiSetDynamicShown: the spark is not one of the widget's
-- cells, so it has to be taken down with them when the bar goes idle.
function mw.CastDynamicShown(widget, shown)
  local state = widget and widget.uuiModernWow
  if not state or not state.spark then return end
  if not shown then
    if state.spark:IsShown() then state.spark:Hide() end
    return
  end
  mw.CastFillUpdate(widget)
end

-- knowledge.json / rendering.parent_alpha_not_propagated: a frame's alpha does
-- not reach its child FRAMES on this client, so the fade is applied to every
-- frame the bar is made of rather than to the container alone.
function mw.CastAlpha(widget, alpha)
  local state = widget and widget.uuiModernWow
  if not state then return end
  local i
  for i = 1, table.getn(state.fade) do
    pcall(state.fade[i].SetAlpha, state.fade[i], alpha)
  end
end

-- modules/castbar.lua hook: the cast has ended. Returns how long the bar stays
-- on screen, which is the source's own budget -- the flash ramp (1/flashSpeed)
-- or the failure hold, plus the fade (1/alphaSpeed).
function mw.CastFinish(widget, kind)
  local state = widget and widget.uuiModernWow
  local bar = widget and widget.bar
  if not state or not bar then return 0 end

  local c = mw.cast
  local complete = (kind == "stop")
  -- A channel that ends has run down to empty and simply fades, as the
  -- Dragonflight channel bar does. CHANNEL_STOP carries nothing that tells an
  -- early cancel from a full channel, so both end this way.
  local drained = complete and state.kind == "channel"

  -- A completed cast snaps to full on its own art and flashes. A failed or
  -- interrupted one snaps to full on the interrupted art and holds.
  local target = tonumber(bar.uuiMax) or 1
  if drained then target = tonumber(bar.uuiMin) or 0 end
  if type(U.ResetStatusBarFX) ~= "function" or
     not U.ResetStatusBarFX(bar, target) then
    pcall(bar.SetValue, bar, target)
  end
  if not complete then mw.CastSetFill(widget, "interrupted") end
  -- Written straight to the bar, so the crop and the spark are brought along
  -- by hand: the shared setter modules/castbar.lua drives is what normally
  -- calls this.
  mw.CastFillUpdate(widget)
  U.SetStatusBarColor(bar, M.Unpack(M.color.cast))
  if state.spark then pcall(state.spark.Hide, state.spark) end

  if not complete and widget.name then
    widget.name:SetText(U.L(kind == "interrupted" and "CASTBAR_INTERRUPTED"
                            or "CASTBAR_FAILED"))
  end

  state.alpha = 1
  state.flashAlpha = 0
  state.last = GetTime()
  -- Only a completed, non-channel cast flashes. A failed one holds on the
  -- interrupted art for a second and then fades, which is what the source
  -- does with its holdTime. A drained channel fades straight away.
  state.flashing = complete and not drained
  state.holdUntil = complete and 0 or (state.last + c.holdTime)
  mw.CastAlpha(widget, 1)
  if state.flash then
    U.SetColor(state.flash, M.Unpack(c.flashColor))
    pcall(state.flash.SetAlpha, state.flash, 0)
    pcall(state.flash.Hide, state.flash)
  end

  local budget = 0
  if state.flashing then
    budget = 1 / c.flashSpeed
  elseif not complete then
    budget = c.holdTime
  end
  return budget + (1 / c.alphaSpeed)
end

function mw.CastFinishTick(widget)
  local state = widget and widget.uuiModernWow
  if not state then return end

  local c = mw.cast
  local now = GetTime()
  local elapsed = now - (state.last or now)
  state.last = now

  if state.holdUntil and now < state.holdUntil then return end

  if state.flashing then
    if not state.flash then
      state.flashing = false
    else
      state.flashAlpha = state.flashAlpha + c.flashSpeed * elapsed
      if state.flashAlpha >= 1 then
        state.flashAlpha = 1
        state.flashing = false
      end
      pcall(state.flash.SetAlpha, state.flash, state.flashAlpha)
      if not state.flash:IsShown() then state.flash:Show() end
      return
    end
  end

  state.alpha = (state.alpha or 1) - c.alphaSpeed * elapsed
  if state.alpha < 0 then state.alpha = 0 end
  mw.CastAlpha(widget, state.alpha)
  -- The flash is a region of the housing, so the housing's own alpha already
  -- fades it; nothing extra to drive here.
end

-- The animation is over: put the widget back the way the next cast expects to
-- find it. modules/castbar.lua hides it immediately afterwards.
function mw.CastFinishEnd(widget)
  local state = widget and widget.uuiModernWow
  if not state then return end

  state.flashing = false
  state.holdUntil = nil
  state.alpha = 1
  mw.CastAlpha(widget, 1)
  if state.flash then
    pcall(state.flash.SetAlpha, state.flash, 0)
    pcall(state.flash.Hide, state.flash)
  end
  if state.spark then pcall(state.spark.Hide, state.spark) end
  -- The interrupted art must not outlive its finish: back to this cast's own.
  mw.CastSetFill(widget, state.kind)
  if widget.bar then
    U.SetStatusBarColor(widget.bar, M.Unpack(M.color.cast))
  end
end

function mw.BuildCastBar(name)
  local widget = U.G(name)
  if not widget or widget.uuiModernWow then return end

  local bar = widget.bar
  if not bar then return end

  local c = mw.cast
  local width = mw.Dimension(bar, "GetWidth")
  local height = mw.Dimension(bar, "GetHeight")
  local barLevel = mw.Dimension(bar, "GetFrameLevel")

  -- Before anything is measured off the art: SetScale does not change the
  -- widget's own width and height, so every rectangle below is still computed
  -- in the bar's own units and simply drawn smaller.
  local scale = mw.CastScale()
  if scale ~= 1 then
    pcall(widget.SetScale, widget, scale)
    -- The mover placed this bar at scale 1 during castbar's OnEnable; replay
    -- its point under the new scale or it drifts on every reload.
    U.ReapplyMoverPosition(widget)
  end

  -- Two owned frames around the bar: the bed carries the drop shadow strictly
  -- below the fill, the housing carries the rim, spark and flash strictly
  -- above it. Both are addon-owned children of an addon-owned widget, which is
  -- the ownership boundary rules/unreal-ui.md requires.
  local bed = CreateFrame("Frame", nil, widget)
  bed:SetAllPoints(bar)
  if barLevel > 0 then pcall(bed.SetFrameLevel, bed, barLevel - 1) end

  local housing = CreateFrame("Frame", nil, widget)
  housing:SetAllPoints(widget)
  local level = mw.Dimension(widget, "GetFrameLevel")
  if level > 0 then pcall(housing.SetFrameLevel, housing, level + 8) end

  -- The Dragonflight cast fill; mw.CastKind swaps it per cast. The tint is
  -- the theme's M.color.cast, which themes/modern-wow.lua leaves white.
  mw.CastSetFill(widget, "cast")
  U.SetStatusBarColor(bar, M.Unpack(M.color.cast))

  -- The backdrop. The shared status bar already owns a texture in exactly the
  -- place the source puts its background -- behind the fill, same rectangle --
  -- so that one is re-materialised instead of covered with a second.
  if bar.uuiBackground then
    pcall(bar.uuiBackground.SetTexture, bar.uuiBackground,
          M.modernWow.texture.castBackground)
    U.SetColor(bar.uuiBackground, M.Unpack(c.chrome))
  end

  -- Pinned to both of the bar's bottom corners, so its left and right edges
  -- are the bar's own edges by construction -- a width in units could only
  -- ever approximate that, and did overhang the right side. The height is then
  -- the one thing set explicitly. It lives on the bed frame, one level below
  -- the bar, so the part that overlaps stays BEHIND the fill and can never
  -- darken it.
  local shadow = mw.Texture(bed, "BACKGROUND", M.modernWow.texture.castShadow)
  if shadow then
    shadow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, c.shadowLift)
    shadow:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, c.shadowLift)
    shadow:SetHeight(c.shadowLift + c.shadowDrop)
  end

  -- Rim, then spark, then flash: regions on one frame draw in creation order,
  -- which is the order the source layers them in.
  local rim = mw.Texture(housing, "ARTWORK", M.modernWow.texture.castFrame)
  if rim then
    rim:SetAllPoints(bar)
    U.SetColor(rim, M.Unpack(c.chrome))
  end

  -- The spark art is additive: its field is opaque black, and with the default
  -- blend mode that field is the moving black square confirmed in game on
  -- 2026-09-05 (modules/castbarclassic.lua records the same trap). If the
  -- blend mode cannot be set, the spark is dropped rather than drawn wrong.
  local spark = mw.Texture(housing, "OVERLAY", M.modernWow.texture.castSpark)
  if spark then
    if spark.SetBlendMode and pcall(spark.SetBlendMode, spark, "ADD") then
      spark:SetWidth(c.sparkWidth)
      spark:SetHeight(height + c.sparkGrow)
      spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
      spark:Hide()
    else
      spark:Hide()
      spark = nil
    end
  end

  -- The finish flash, kept inside the housing. DragonflightUI draws its glow
  -- ring 5 units beyond the bar and over the rim, which read as a white
  -- rectangle around the frame. flash-inner is that art cropped to the bar
  -- and shaped by CastingBarMask, laid exactly over the bar at BORDER -- above
  -- the fill (the housing sits levels above the bar) and below the rim, so the
  -- rim covers the ring and only the glow over the fill shows.
  local flash = mw.Texture(housing, "BORDER",
                           M.modernWow.texture.castFlashInner)
  if flash then
    flash:SetAllPoints(bar)
    pcall(flash.SetAlpha, flash, 0)
    flash:Hide()
  end

  -- The progress cell's flat panel comes down completely -- fill and edges
  -- both -- because the art now supplies every part of it. The icon cell keeps
  -- its outline: the source frames its own cast icon the same way.
  local progressCell = widget.uuiCells and widget.uuiCells[2]
  if progressCell and progressCell ~= widget.iconCell then
    U.SetBackdropShown(progressCell, false)
  end

  -- Name and countdown move below the bar, at the source's own inset and half
  -- the bar's height plus the gap below its bottom edge (see mw.cast.textGap).
  local drop = -(height / 2 + c.textGap)
  if widget.name then
    widget.name:ClearAllPoints()
    widget.name:SetPoint("LEFT", bar, "LEFT", c.textInset, drop)
    -- knowledge.json / fonts.stretched_justification_ignored: one edge plus an
    -- explicit width, so a long name stops before the countdown.
    pcall(widget.name.SetWidth, widget.name, width - 50)
    U.SetFont(widget.name, c.fontSize)
  end
  if widget.time then
    widget.time:ClearAllPoints()
    widget.time:SetPoint("RIGHT", bar, "RIGHT", -c.textInset, drop)
    U.SetFont(widget.time, c.fontSize)
  end
  -- Remembered for modules/castbar.lua's ApplyPushback, which re-anchors the
  -- countdown whenever the pushback slot appears or goes away.
  widget.uuiTimeY = drop
  if widget.pushback then
    widget.pushback:ClearAllPoints()
    widget.pushback:SetPoint("RIGHT", bar, "RIGHT", -c.textInset, drop)
    U.SetFont(widget.pushback, c.fontSize)
  end

  local state = {
    bed = bed, housing = housing, rim = rim, spark = spark, flash = flash,
    fade = { widget, bar, bed, housing },
    alpha = 1, flashAlpha = 0, flashing = false, kind = "cast",
  }
  local i
  if widget.uuiCells then
    for i = 1, table.getn(widget.uuiCells) do
      table.insert(state.fade, widget.uuiCells[i])
    end
  end
  widget.uuiModernWow = state

  -- The hooks modules/castbar.lua offers. Installed last, so a widget that
  -- failed to dress above is never driven through them.
  widget.uuiUpdateSpark = mw.CastFillUpdate
  widget.uuiSetDynamicShown = mw.CastDynamicShown
  widget.uuiFinish = mw.CastFinish
  widget.uuiFinishTick = mw.CastFinishTick
  widget.uuiFinishEnd = mw.CastFinishEnd
  widget.uuiCastKind = mw.CastKind
  widget.uuiDrainChannel = true

  mw.CastFillUpdate(widget)
end

function mw.BuildCastBars()
  local i
  for i = 1, table.getn(mw.castBars) do
    mw.BuildCastBar(mw.castBars[i])
  end
end

-- The stored cast-bar scale, falling back to the shipped value for a profile
-- written before this setting existed.
function mw.CastScale()
  local value = tonumber(mw.Config().castScale)
  if not value or value <= 0 then return mw.cast.scale end
  return value
end

-- `/uui mw cast <n>` -- the cast bar's scale, which sizes the housing art, the
-- fill, the spark and the labels together.
--
-- Live, not reload-bound, for the same reason the ring and portrait sizes are:
-- this is a number dialled in by eye against the art, and SetScale rebuilds
-- nothing -- the geometry below is computed in the bar's own units and only
-- drawn smaller (mw.BuildCastBar).
function U.ModernWowSetCastScale(value)
  value = tonumber(value)
  if not value or value <= 0 then
    U.Print("modern-wow: cast bar scale is " .. mw.CastScale() ..
            " -- /uui mw cast <number>, 1 = the bar's own size")
    return false
  end

  mw.Config().castScale = value

  local i, dressed = nil, 0
  for i = 1, table.getn(mw.castBars) do
    local widget = U.G(mw.castBars[i])
    if widget and widget.uuiModernWow then
      if pcall(widget.SetScale, widget, value) then
        U.ReapplyMoverPosition(widget)
        dressed = dressed + 1
      end
    end
  end

  U.Print("modern-wow: cast bar scale " .. value ..
          " (" .. dressed .. " bar(s) resized)")
  return true
end

-- ---------------------------------------------------------------------------
-- Surface: window chrome
--
-- The Dragonflight paperdoll art is four quadrants that tile to exactly
-- 384x512 -- 256+128 wide, 256+256 high -- which is the stock size of the
-- standard windows on this client. The Quest Log is the source's exception:
-- DragonflightUI replaces its native left/right regions with the dedicated
-- questlog-left and questlog-right art, so its entry below asks for those two
-- full-height pieces instead of borrowing the paperdoll quadrants. Both paths
-- are laid out proportionally, so a resized window gets the same chrome scaled
-- instead of a gap down one side.
--
-- UnrealUI has already stripped the native art and drawn its own flat surface
-- on these windows by the time this runs; only the flat outline is taken down,
-- and the quadrants go behind the window's content at BACKGROUND.
--
-- Nothing here reads or retains a native child. The chrome textures are
-- created on an addon-owned frame parented to the window, which is the
-- ownership boundary rules/unreal-ui.md requires.
-- ---------------------------------------------------------------------------
mw.questLogWindow = {
  name = "QuestLogFrame",
  left = "questlogLeft",
  right = "questlogRight",
  crop = M.modernWow.questLog,
  ownSurface = true,
}

mw.windows = {
  { name = "CharacterFrame" },
  { name = "FriendsFrame" },
  -- Quest Log remains in this inventory for shared header/close diagnostics,
  -- but owns an enabled-by-default surface so its theme art is not gated by
  -- the optional generic window-chrome surface.
  mw.questLogWindow,
  { name = "SpellBookFrame" },
  { name = "TalentFrame" },
  -- Interaction windows intentionally use classic-wow/native chrome even
  -- when the generic Modern WoW window/header surfaces are enabled.
  { name = "MerchantFrame", classicInteraction = true },
  { name = "ClassTrainerFrame", classicInteraction = true },
  { name = "MailFrame", classicInteraction = true },
  { name = "GossipFrame", classicInteraction = true },
  { name = "QuestFrame", classicInteraction = true },
  { name = "BankFrame", classicInteraction = true },
}

-- Quadrant widths as a fraction of the 384-wide design, so the seam lands in
-- the same place whatever the window measures.
mw.quadrant = { split = 256 / 384 }

-- Dedicated two-piece windows use their source-art seam when one is supplied,
-- otherwise the standard panel seam at 2/3 of the live frame width.
-- QuestLogFrame changes width when its details pane opens or closes, so these
-- dimensions cannot be a one-time build measurement.
function mw.ResizeSplitWindow(frame)
  local state = frame and frame.uuiModernWowWindow
  if not state or not state.left or not state.right then return false end

  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return false end

  local leftWidth = width * (state.split or mw.quadrant.split)

  state.left:ClearAllPoints()
  state.left:SetWidth(leftWidth)
  state.left:SetHeight(height)
  state.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

  state.right:ClearAllPoints()
  state.right:SetWidth(width - leftWidth)
  state.right:SetHeight(height)
  state.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

  state.width = width
  state.height = height
  -- The ring is a fraction of the live width, so the book follows the pane.
  if state.book then pcall(mw.PlaceQuestLogBook, frame) end
  return true
end

function mw.DressWindow(frame, entry)
  if not frame or frame.uuiModernWowWindow then return nil end

  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return nil end

  local chrome = CreateFrame("Frame", nil, frame)
  chrome:SetAllPoints(frame)

  -- Below the window's own content: the stock children sit at the frame's
  -- level or above, so one level down keeps every button and label clickable
  -- and visible over the art.
  local level = mw.Dimension(frame, "GetFrameLevel")
  if level > 1 then pcall(chrome.SetFrameLevel, chrome, level - 1) end

  if entry and entry.left and entry.right then
    local crop = entry.crop
    local leftCoords = crop and crop.leftTexCoord
    local rightCoords = crop and crop.rightTexCoord
    local left = mw.Texture(chrome, "BACKGROUND",
                            M.modernWow.texture[entry.left],
                            leftCoords and leftCoords[1],
                            leftCoords and leftCoords[2],
                            leftCoords and leftCoords[3],
                            leftCoords and leftCoords[4])
    local right = mw.Texture(chrome, "BACKGROUND",
                             M.modernWow.texture[entry.right],
                             rightCoords and rightCoords[1],
                             rightCoords and rightCoords[2],
                             rightCoords and rightCoords[3],
                             rightCoords and rightCoords[4])
    if not left or not right then return nil end

    mw.HideFlatSurface(frame)
    frame.uuiModernWowWindow = {
      chrome = chrome,
      left = left,
      right = right,
      split = crop and crop.split,
    }
    mw.ResizeSplitWindow(frame)
    return frame.uuiModernWowWindow
  end

  local leftWidth = width * mw.quadrant.split
  local rightWidth = width - leftWidth
  local halfHeight = height / 2

  local tl = mw.Texture(chrome, "BACKGROUND", M.modernWow.texture.panelTopLeft)
  if tl then
    tl:SetWidth(leftWidth)
    tl:SetHeight(halfHeight)
    tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  end

  local tr = mw.Texture(chrome, "BACKGROUND", M.modernWow.texture.panelTopRight)
  if tr then
    tr:SetWidth(rightWidth)
    tr:SetHeight(halfHeight)
    tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  end

  local bl = mw.Texture(chrome, "BACKGROUND",
                        M.modernWow.texture.panelBottomLeft)
  if bl then
    bl:SetWidth(leftWidth)
    bl:SetHeight(halfHeight)
    bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  end

  local br = mw.Texture(chrome, "BACKGROUND",
                        M.modernWow.texture.panelBottomRight)
  if br then
    br:SetWidth(rightWidth)
    br:SetHeight(halfHeight)
    br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  end

  mw.HideFlatEdges(frame)

  frame.uuiModernWowWindow = { chrome = chrome }
  return frame.uuiModernWowWindow
end

function mw.BuildWindows()
  local i
  for i = 1, table.getn(mw.windows) do
    local entry = mw.windows[i]
    local frame = U.G(entry.name)
    if frame and not entry.ownSurface and not entry.classicInteraction then
      -- Dressed once, now, rather than on every OnShow: the textures are
      -- static art on an addon-owned child, so there is nothing for a later
      -- show to restore. A window the client has not created this session is
      -- simply skipped.
      mw.DressWindow(frame, entry)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Surface: NPC interaction dialogs
--
-- Quest, gossip, merchant and trainer windows may be lazy stock singletons on
-- this client. A PLAYER_LOGIN-only window pass can therefore miss them, so
-- their owning modules call U.ModernWowNpcDialog as soon as each frame actually
-- exists. The surface builder below still handles a frame that happened to be
-- loaded already. Both paths converge on the same idempotent dresser.
--
-- Each stock-window module continues to own content, scrolling, service logic,
-- action buttons and refresh hooks. This theme replaces only its flat outer
-- panel, places a preserved NPC portrait inside the art's gold ring when the
-- window provides one, and applies the themed close button. Native interaction
-- behavior is untouched.
-- ---------------------------------------------------------------------------
mw.npcDialogs = {
  {
    frame = "GossipFrame",
    panel = "UnrealUIGossipPanel",
    portrait = "GossipFramePortrait",
    close = "GossipFrameCloseButton",
  },
  {
    frame = "QuestFrame",
    panel = "UnrealUIQuestPanel",
    portrait = "QuestFramePortrait",
    close = "QuestFrameCloseButton",
  },
  {
    frame = "MerchantFrame",
    panel = "UnrealUIMerchantPanel",
    portrait = "MerchantFramePortrait",
    close = "MerchantFrameCloseButton",
  },
  {
    frame = "ClassTrainerFrame",
    panel = "UnrealUITrainerPanel",
    close = "ClassTrainerFrameCloseButton",
  },
}

function mw.PlaceNpcPortrait(frame, portrait)
  if not frame or not portrait then return false end

  local token = M.modernWow.npcDialog
  local ring = token and token.portrait
  if not ring then return false end

  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return false end

  local sx = width / token.designWidth
  local sy = height / token.designHeight
  local inset = ring.inset or 0
  local size = ring.size - 2 * inset
  local ok = pcall(function()
    portrait:ClearAllPoints()
    portrait:SetWidth(size * sx)
    portrait:SetHeight(size * sy)
    portrait:SetPoint("TOPLEFT", frame, "TOPLEFT",
                      (ring.left + inset) * sx,
                      -(ring.top + inset) * sy)
    portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    portrait:SetAlpha(1)
    portrait:Show()
  end)
  return ok and true or false
end

function mw.DressNpcDialog(frame, panel, portrait, closeName)
  if not frame then return false end

  if not frame.uuiModernWowWindow and not mw.DressWindow(frame) then
    return false
  end

  -- modules/quest.lua and modules/gossip.lua deliberately retain this panel
  -- as the stable anchor for their title and close button.  Remove only its
  -- flat drawing; keeping the frame itself preserves those safe anchors.
  if panel then mw.HideFlatSurface(panel) end
  mw.PlaceNpcPortrait(frame, portrait)
  if closeName then mw.DressCloseButton(closeName) end

  frame.uuiModernWowNpcDialog = true
  return true
end

function U.ModernWowNpcDialog(frame, panel, portrait, closeName)
  if not mw.Active() or not mw.Enabled("npcdialogs") then return false end
  return mw.DressNpcDialog(frame, panel, portrait, closeName)
end

function mw.BuildNpcDialogs()
  local i
  for i = 1, table.getn(mw.npcDialogs) do
    local entry = mw.npcDialogs[i]
    mw.DressNpcDialog(U.G(entry.frame), U.G(entry.panel),
                      U.G(entry.portrait), entry.close)
  end
end

function mw.BuildQuestLog()
  local entry = mw.questLogWindow
  local frame = entry and U.G(entry.name)
  if not frame then error("modern-wow Quest Log frame is unavailable") end
  if not mw.DressWindow(frame, entry) then
    error("modern-wow Quest Log texture could not be applied")
  end
  -- Also created from modules/questlog.lua; whichever runs second finds it.
  pcall(U.ModernWowQuestLogBook)
  -- The window's own close button, dressed with this surface rather than with
  -- the generic `close` one: that surface covers a dozen windows this theme
  -- has not been judged on yet, while the Quest Log page art is shipped and
  -- the flat square in its corner is part of the same picture.
  mw.DressCloseButton("QuestLogFrameCloseButton")
end

-- ---------------------------------------------------------------------------
-- Surface: Character window
--
-- The paperdoll quadrants behind CharacterFrame, which is the window they were
-- authored for at 384x512 (gold portrait ring top-left, rim ending where
-- modules/character.lua's panel ends), plus the Dragonflight bottom tabs.
--
-- Its own enabled-by-default surface rather than the generic `windows` one,
-- for the same reason the Quest Log has one: the generic surface covers a
-- dozen windows not yet judged on this art. DressWindow is idempotent, so
-- enabling both is harmless.
--
-- modules/character.lua still owns the tabs' state and layout
-- (U.StyleStockTabGroup, U.FitStockTabStrip). This only swaps what they draw:
-- the flat fill and outline come off and the atlas pieces go on, repainted on
-- every state change that shared component makes. Tabs and the panel are
-- found by their global names, never by walking children.
-- ---------------------------------------------------------------------------
mw.character = {
  window = { name = "CharacterFrame" },
  panel = "UnrealUICharacterPanel",
  tabPrefix = "CharacterFrameTab",
  tabCount = 5,
}

function mw.TabSet(tab, layer, prefix)
  local token = M.modernWow.tab
  local path = M.modernWow.texture.frameTabs
  local middle = token[prefix .. "Middle"]
  local set = {
    prefix = prefix,
    left = mw.Texture(tab, layer, path),
    middle = mw.Texture(tab, layer, path, middle[1], middle[2], middle[3],
                        middle[4]),
    right = mw.Texture(tab, layer, path),
  }
  if not set.left or not set.middle or not set.right then return nil end
  return set
end

-- Lays one set out over the tab's live width. The caps keep their authored
-- width unless the tab is narrower than both together; then each is cropped
-- (not squeezed) from its inner side, so the rim and rounded corner survive.
function mw.PlaceTabSet(tab, set, alpha)
  local token = M.modernWow.tab
  local scale = token.scale
  local left = token[set.prefix .. "Left"]
  local right = token[set.prefix .. "Right"]
  local width = mw.Dimension(tab, "GetWidth")
  -- Both sets draw at the selected tab's height in whole pixels, so selecting
  -- a tab does not resize it and the hover wash lies exactly over the resting
  -- art.
  local height = math.floor(token.activeLeft.h * scale + 0.5)

  local cap = math.min(math.floor(left.w * scale + 0.5), math.floor(width / 2))
  if cap < 0 then cap = 0 end
  local span = math.min(cap / scale, left.w) / token.atlasWidth
  local lift = token.lift

  pcall(function()
    set.left:ClearAllPoints()
    set.left:SetWidth(cap)
    set.left:SetHeight(height)
    set.left:SetTexCoord(left[1], left[1] + span, left[3], left[4])
    set.left:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, lift)

    set.right:ClearAllPoints()
    set.right:SetWidth(cap)
    set.right:SetHeight(height)
    set.right:SetTexCoord(right[2] - span, right[2], right[3], right[4])
    set.right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, lift)

    set.middle:ClearAllPoints()
    set.middle:SetHeight(height)
    set.middle:SetPoint("TOPLEFT", tab, "TOPLEFT", cap, lift)
    set.middle:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -cap, lift)
  end)

  local pieces = { set.left, set.middle, set.right }
  local i
  for i = 1, 3 do
    local piece = pieces[i]
    local visible = alpha > 0 and (i ~= 2 or width - 2 * cap >= 1)
    if visible then
      pcall(piece.SetAlpha, piece, alpha)
      pcall(piece.Show, piece)
    else
      pcall(piece.Hide, piece)
    end
  end
end

-- Default shows the inactive art, selected the active art, and hover lays the
-- active art faintly over the inactive one. Disabled is the native selected
-- tab's own state and draws as selected. The shared tab repaints its flat fill
-- on each of those changes, so that is cleared again here every time.
function mw.RefreshTab(tab)
  local state = tab and tab.uuiModernWowTab
  if not state then return end
  mw.HideFlatSurface(tab)

  local active = tab.uuiTabActive and true or false
  local activeAlpha = 0
  if active then
    activeAlpha = 1
  elseif state.hover then
    activeAlpha = M.modernWow.tab.hoverAlpha
  end
  mw.PlaceTabSet(tab, state.inactive, active and 0 or 1)
  mw.PlaceTabSet(tab, state.active, activeAlpha)

  -- Re-anchored on every refresh so a native page switch cannot restore the
  -- shared flat tab's label offset.
  if tab.GetFontString then
    local ok, label = pcall(tab.GetFontString, tab)
    if ok and label then
      pcall(function()
        label:ClearAllPoints()
        label:SetPoint("CENTER", tab, "CENTER", 0, M.modernWow.tab.textY)
      end)
    end
  end
end

function mw.DressTab(tab)
  if not tab or tab.uuiModernWowTab then return end

  -- Inactive under active, so the hover wash lands on top of the resting art;
  -- both stay below the label's ARTWORK layer.
  local state = {
    inactive = mw.TabSet(tab, "BACKGROUND", "inactive"),
    active = mw.TabSet(tab, "BORDER", "active"),
  }
  if not state.inactive or not state.active then
    error("modern-wow tab art could not be created")
  end
  tab.uuiModernWowTab = state
  pcall(tab.SetHeight, tab, M.modernWow.tab.height)

  -- Wrapped, not replaced, the way core/stockui.lua wraps SetChecked: the
  -- shared component still owns selection, and U.FitStockTabStrip still owns
  -- width. Both reach the art through these.
  local setActive = tab.SetActive
  if type(setActive) == "function" then
    tab.SetActive = function(active)
      setActive(active)
      mw.RefreshTab(tab)
    end
  end
  local setWidth = tab.SetWidth
  if type(setWidth) == "function" then
    tab.SetWidth = function(self, width)
      local result = setWidth(self, width)
      mw.RefreshTab(tab)
      return result
    end
  end

  U.PostHookScript(tab, "OnEnter", function()
    state.hover = true
    mw.RefreshTab(tab)
  end)
  U.PostHookScript(tab, "OnLeave", function()
    state.hover = false
    mw.RefreshTab(tab)
  end)
  U.PostHookScript(tab, "OnShow", function() mw.RefreshTab(tab) end)

  mw.RefreshTab(tab)
end

function U.ModernWowNpcTab(tab)
  if not mw.Active() or not mw.Enabled("npcdialogs") then return false end
  mw.DressTab(tab)
  return tab and tab.uuiModernWowTab and true or false
end

-- The same tab and close-button dressing for a themed window whose own module
-- owns its drawing path (modules/spellbookmodernwow.lua). Gated on the theme
-- only; that module has already checked its own surface.
function U.ModernWowDressTab(tab)
  if not mw.Active() then return false end
  mw.DressTab(tab)
  return tab and tab.uuiModernWowTab and true or false
end

function U.ModernWowDressCloseButton(name)
  if not mw.Active() then return false end
  mw.DressCloseButton(name)
  return true
end

function mw.BuildCharacter()
  local entry = mw.character
  local frame = U.G(entry.window.name)
  if not frame then error("modern-wow Character frame is unavailable") end
  if not frame.uuiModernWowWindow and not mw.DressWindow(frame, entry.window) then
    error("modern-wow Character texture could not be applied")
  end

  -- modules/character.lua's near-black sheet sits above the chrome frame and
  -- would read as a dark slab over the art, exactly as the Quest Log did.
  local panel = U.G(entry.panel)
  if panel then mw.HideFlatSurface(panel) end

  mw.CharacterClassIcon(frame)
  mw.DressGearSlots(frame)
  mw.CharacterStatsFrame(frame)
  mw.ShiftTitleDropDown()
  mw.CharacterLevelLine(frame)

  local i
  for i = 1, entry.tabCount do
    mw.DressTab(U.G(entry.tabPrefix .. i))
  end
  mw.DressCloseButton("CharacterFrameCloseButton")
end

-- Gear slots: DragonflightUI's look, which is the stock square slot frame
-- darkened (M.modernWow.gearSlot), redrawn as an owned texture on each
-- Character equipment slot. HUD bags are not touched here; modules/bagbar.lua
-- owns those.
--
-- modules/character.lua keeps styling the slots (tooltip, rarity lookup) and
-- re-runs U.StyleStockButton on every PaperDollItemSlotButton_Update, which
-- re-anchors the icon to its flat 3px inset. These hooks are installed after
-- that module's, so this pass runs second and wins. Rarity comes from the
-- persistent slot.uuiCharacterBorder table that module maintains, and tints the
-- frame the way DF tints its bag borders by quality (bags.lua, WORKING_SOURCE).
mw.character.slots = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
  "ShirtSlot", "TabardSlot", "WristSlot",
  "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
  "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
  "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot",
}

function mw.SameColor(a, b)
  if not a or not b then return false end
  local i
  for i = 1, 3 do
    if math.abs((tonumber(a[i]) or 0) - (tonumber(b[i]) or 0)) > 0.01 then
      return false
    end
  end
  return true
end

function mw.PlaceGearSlot(slot)
  local state = slot and slot.uuiModernWowGear
  if not state then return end

  local token = M.modernWow.gearSlot
  local size = mw.Dimension(slot, "GetWidth")
  if size <= 0 then return end
  local k = size / token.designSlot

  -- The flat fill and rarity outline character.lua repaints are replaced by
  -- the metal corner frame, so they come off again on every pass.
  mw.HideFlatSurface(slot)

  -- Each corner spans `outer` px past the bar centreline and reaches inward to
  -- the slot's midpoint, so the four pieces meet and close the square.
  local s = token.artScale * k
  local line = token.lineOffset * k
  local e = token.outer
  local n = math.min((size / 2 + line) / s, token.arm)
  local shift = line + e * s
  local aw, ah = token.atlasWidth, token.atlasHeight
  local i
  for i = 1, table.getn(token.corners) do
    local c = token.corners[i]
    local piece = state.corners[i]
    local u1, u2, v1, v2
    if c.h < 0 then u1, u2 = c.x - e, c.x + n else u1, u2 = c.x - n, c.x + e end
    if c.v > 0 then v1, v2 = c.y - e, c.y + n else v1, v2 = c.y - n, c.y + e end
    pcall(function()
      piece:ClearAllPoints()
      piece:SetWidth((e + n) * s)
      piece:SetHeight((e + n) * s)
      piece:SetPoint(c.point, slot, c.point, c.h * shift, c.v * shift)
      piece:SetTexCoord(u1 / aw, u2 / aw, v1 / ah, v2 / ah)
    end)
  end

  -- U.StyleStockButton re-crops and insets the icon on every update; the
  -- stock slot shows it whole, edge to edge.
  local icon = state.icon
  if icon then
    pcall(function()
      icon:ClearAllPoints()
      icon:SetAllPoints(slot)
      icon:SetTexCoord(0, 1, 0, 1)
    end)
  end

  -- The metal keeps its own colour; rarity lives on the glow only.
  local shade = token.shade
  for i = 1, table.getn(state.corners) do
    pcall(state.corners[i].SetVertexColor, state.corners[i], shade, shade,
          shade, 1)
  end

  local border = slot.uuiCharacterBorder
  local rare = border and not mw.SameColor(border, M.slotBorder.empty)
     and not mw.SameColor(border, M.slotBorder.plain)
  local glow = state.glow
  if glow then
    local glowExtent = size + token.glowGrow * k
    pcall(function()
      glow:ClearAllPoints()
      glow:SetWidth(glowExtent)
      glow:SetHeight(glowExtent)
      glow:SetPoint("CENTER", slot, "CENTER", 0, 0)
      if rare then
        glow:SetVertexColor(border[1], border[2], border[3], token.glowAlpha)
        glow:Show()
      else
        glow:Hide()
      end
    end)
  end
end

function mw.DressGearSlot(slotName)
  local slot = U.G("Character" .. slotName)
  if not slot or slot.uuiModernWowGear then return end

  local token = M.modernWow.gearSlot
  local i
  local corners = {}
  for i = 1, table.getn(token.corners) do
    local piece = mw.Texture(slot, "ARTWORK", token.frame)
    if not piece then return end
    corners[i] = piece
  end

  -- Rarity glow: the action bar's glow art in the item's quality colour,
  -- above the metal frame (OVERLAY over ARTWORK).
  local glow = mw.Texture(slot, "OVERLAY", token.glowTexture)
  if glow then pcall(glow.Hide, glow) end

  -- Hover stays the button's own highlight slot so the client drives it.
  -- UnrealUI hid that region when it cleared the stock faces, so it is
  -- un-hidden here (see mw.ButtonFace). ADD matches the stock template on the
  -- updated client (knowledge: rendering.setblendmode_add_inert).
  local hover
  if pcall(slot.SetHighlightTexture, slot, token.hover) then
    local ok, region = pcall(slot.GetHighlightTexture, slot)
    if ok and region then
      pcall(region.SetTexCoord, region, 0, 1, 0, 1)
      pcall(region.SetBlendMode, region, "ADD")
      pcall(region.SetAlpha, region, 1)
      pcall(region.Show, region)
      hover = region
    end
  end

  slot.uuiModernWowGear = {
    corners = corners,
    glow = glow,
    hover = hover,
    icon = U.G("Character" .. slotName .. "IconTexture"),
  }
  mw.PlaceGearSlot(slot)
end

function mw.RefreshGearSlots()
  local slots = mw.character.slots
  local i
  for i = 1, table.getn(slots) do
    mw.PlaceGearSlot(U.G("Character" .. slots[i]))
  end
end

function mw.DressGearSlots(frame)
  local slots = mw.character.slots
  local i
  for i = 1, table.getn(slots) do
    mw.DressGearSlot(slots[i])
  end
  U.PostHookGlobal("PaperDollItemSlotButton_Update", mw.RefreshGearSlots)
  U.PostHookScript(frame, "OnShow", mw.RefreshGearSlots)
end

-- Stats boxes: DragonflightUI's look for the stats block under the 3D model --
-- the stock rounded group boxes (attributes on the left, melee and ranged
-- stacked on the right), darkened (modules/ui/ui.lua Darken, WORKING_SOURCE).
-- UnrealUI strips the stock art, so the boxes are redrawn as owned backdrops
-- with the client's tooltip edge (M.modernWow.statBoxes).
--
-- Placed from bounded numbers, not anchored to CharacterAttributesFrame: its
-- offset inside CharacterFrame is read once here and the boxes hang off the
-- addon-owned chrome frame (rules/unreal-ui.md, native widget ownership). A
-- position that cannot be read falls back to the stock layout.
--
-- The chrome shows on every Character tab, but the stats only exist on the
-- paper doll page, so the boxes follow PaperDollFrame's own show and hide.
--
-- The edge uses a whole-unit edgeSize; only fractional sizes are recorded as
-- failing (knowledge: rendering.backdrop_edge_fractional_not_rasterized). A
-- backdrop the client refuses leaves that box undrawn rather than erroring.
function mw.StatBox(parent, left, top, width, height)
  local token = M.modernWow.statBoxes
  local box = CreateFrame("Frame", nil, parent)
  -- A child frame lands one level above its parent, which can lift the box's
  -- 80% black fill over the stock stat text. Keep it at the holder's level,
  -- which sits below the window's content.
  local level = mw.Dimension(parent, "GetFrameLevel")
  if level > 0 then pcall(box.SetFrameLevel, box, level) end
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
  box:SetWidth(width)
  box:SetHeight(height)
  if pcall(box.SetBackdrop, box, {
    bgFile = token.background,
    edgeFile = token.edge,
    tile = true, tileSize = token.tileSize, edgeSize = token.edgeSize,
    insets = { left = token.inset, right = token.inset,
               top = token.inset, bottom = token.inset },
  }) then
    pcall(box.SetBackdropColor, box, M.Unpack(token.fill))
    pcall(box.SetBackdropBorderColor, box, M.Unpack(token.border))
  end
  return box
end

function mw.StatsRect(frame)
  local fallback = M.modernWow.statBoxes.statsRect
  local stats = U.G("CharacterAttributesFrame")
  local frameLeft = mw.Dimension(frame, "GetLeft")
  local frameTop = mw.Dimension(frame, "GetTop")
  local left = mw.Dimension(stats, "GetLeft")
  local top = mw.Dimension(stats, "GetTop")
  local width = mw.Dimension(stats, "GetWidth")
  local height = mw.Dimension(stats, "GetHeight")
  if frameLeft ~= 0 and frameTop ~= 0 and left ~= 0 and top ~= 0
     and width > 0 and height > 0 then
    return left - frameLeft, frameTop - top, width, height
  end
  return fallback.left, fallback.top, fallback.width, fallback.height
end

-- Attribute values move `valueShift` units left of their stock placement.
-- Every anchor point is captured once and all of them are re-applied shifted:
-- moving only GetPoint(1) left a second point pinning the text in place
-- (knowledge: frames.extra_anchor_point_survives_addon_setpoint). Re-running
-- starts from the captured stock points, so it never accumulates. No addon
-- frame is anchored to these FontStrings.
function mw.ShiftStockPoints(object, dx, dy)
  if not (object and object.GetPoint and object.GetNumPoints) then return end
  local base = object.uuiModernWowStockPoints
  if not base then
    base = {}
    local okCount, count = pcall(object.GetNumPoints, object)
    local p
    for p = 1, (okCount and tonumber(count)) or 0 do
      local ok, point, relative, relPoint, px, py =
        pcall(object.GetPoint, object, p)
      if ok and point then
        table.insert(base, { point, relative, relPoint,
                             tonumber(px) or 0, tonumber(py) or 0 })
      end
    end
    object.uuiModernWowStockPoints = base
  end
  if table.getn(base) > 0 then
    pcall(function()
      object:ClearAllPoints()
      local p
      for p = 1, table.getn(base) do
        local b = base[p]
        object:SetPoint(b[1], b[2], b[3], b[4] + dx, b[5] + dy)
      end
    end)
  end
end

function mw.ShiftStatValues()
  local names = M.modernWow.statValues
  local shift = M.modernWow.statBoxes.valueShift
  local i
  for i = 1, table.getn(names) do
    mw.ShiftStockPoints(U.G(names[i]), shift, 0)
  end
end

-- The title dropdown gets the same captured-once shift. Its name is
-- WORKING_SOURCE only (see M.modernWow.titleDropDown); nil skips it.
function mw.ShiftTitleDropDown()
  local token = M.modernWow.titleDropDown
  mw.ShiftStockPoints(U.G(token.name), token.x, token.y)
end

-- "<class> Level <n>" over the title dropdown: class name in its class colour,
-- the rest white (CHARACTER_CLASS_LEVEL). An addon-owned FontString on the
-- chrome frame, placed from bounded numbers read once off the dropdown, never
-- anchored to it (rules/unreal-ui.md, native widget ownership).
-- UnitClass/UnitLevel: OFFICIAL_CLIENT_DOCUMENTATION; PLAYER_LEVEL_UP:
-- MEASURED_RUNTIME (knowledge: events.no_quest_event_evidence). Its new level
-- comes from arg1 when present, because UnitLevel can still report the old one.
function mw.RefreshCharacterLevelLine(level)
  local text = mw.characterLevelText
  if not text then return end
  local okClass, className, token = pcall(UnitClass, "player")
  if not okClass or not className then return end
  level = tonumber(level)
  if not level then
    local okLevel, current = pcall(UnitLevel, "player")
    level = okLevel and tonumber(current) or 0
  end
  local r, g, b = M.ClassColor(token)
  local name = className
  if r then
    name = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5),
                         math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5),
                         className)
  end
  pcall(text.SetText, text, U.L("CHARACTER_CLASS_LEVEL", name, level))
end

-- Placed on the first show that has readable bounds: before the window has
-- been shown, the panel manager has not positioned it and the reads are 0.
-- Until then (or with no dropdown) the fallback point is used. Once placed,
-- only the captured numbers are kept.
function mw.PlaceCharacterLevelLine(frame)
  local text = mw.characterLevelText
  if not text or mw.characterLevelPlaced then return end

  -- Between the header's name and the title dropdown: centred on the name
  -- horizontally, and vertically midway between the name's bottom and the
  -- dropdown's top, so it follows the dropdown offset. With no dropdown it
  -- hangs `gap` units under the name. Both are client-owned regions read as
  -- numbers once, never anchored to.
  local token = M.modernWow.characterLevelLine
  local name = U.G("CharacterNameText")
  local dropdown = U.G(M.modernWow.titleDropDown.name)
  local frameLeft = mw.Dimension(frame, "GetLeft")
  local frameTop = mw.Dimension(frame, "GetTop")
  local nameLeft = mw.Dimension(name, "GetLeft")
  local nameRight = mw.Dimension(name, "GetRight")
  local nameBottom = mw.Dimension(name, "GetBottom")
  local top = mw.Dimension(dropdown, "GetTop")
  local measured = frameLeft ~= 0 and frameTop ~= 0 and nameLeft ~= 0
                   and nameRight > nameLeft and nameBottom ~= 0
  pcall(function()
    text:ClearAllPoints()
    if not measured then
      text:SetPoint("TOP", frame, "TOP", 0, -token.fallbackTop)
      return
    end
    local x = (nameLeft + nameRight) / 2 - frameLeft
    if top ~= 0 and top < nameBottom then
      text:SetPoint("CENTER", frame, "TOPLEFT", x,
                    (nameBottom + top) / 2 - frameTop + token.offsetY)
    else
      text:SetPoint("TOP", frame, "TOPLEFT", x,
                    nameBottom - frameTop - token.gap)
    end
  end)
  if measured then mw.characterLevelPlaced = true end
end

function mw.CharacterLevelLine(frame)
  local state = frame and frame.uuiModernWowWindow
  if not state or not state.chrome or mw.characterLevelText then return end

  -- Not on state.chrome: that frame sits one level below the window's content
  -- (mw.DressWindow), so the stock header region covered the text. This holder
  -- sits above the content; a plain Frame does not take the mouse.
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetAllPoints(frame)
  local level = mw.Dimension(frame, "GetFrameLevel")
  pcall(holder.SetFrameLevel, holder, level + M.modernWow.characterLevelLine.levelAbove)

  local okText, text = pcall(holder.CreateFontString, holder, nil, "OVERLAY")
  if not okText or not text then return end
  U.SetStockFont(text, M.fontSize.normal, M.color.text)
  mw.characterLevelText = text

  mw.PlaceCharacterLevelLine(frame)
  U.PostHookScript(frame, "OnShow", function()
    mw.PlaceCharacterLevelLine(frame)
  end)

  mw.RefreshCharacterLevelLine()
  U.RegisterEvent("PLAYER_LEVEL_UP", function(a1)
    mw.RefreshCharacterLevelLine(tonumber(a1) or arg1)
  end)
end

function mw.CharacterStatsFrame(frame)
  local state = frame and frame.uuiModernWowWindow
  if not state or not state.chrome or state.statsFrame then return end

  local token = M.modernWow.statBoxes
  local x, y, width, height = mw.StatsRect(frame)

  -- One holder so the page show/hide below toggles all three boxes. It stays
  -- at the chrome's level, below the stock stats, so the text draws on top.
  local box = CreateFrame("Frame", nil, state.chrome)
  box:SetAllPoints(state.chrome)
  local level = mw.Dimension(state.chrome, "GetFrameLevel")
  if level > 0 then pcall(box.SetFrameLevel, box, level) end
  state.statsFrame = box

  local split = x + width * token.split
  local middle = y + height / 2
  local right = x + width
  local bottom = y + height

  -- Edges are whole units from the rect; see M.modernWow.statBoxes.edges.
  local function place(l, t, r, b)
    mw.StatBox(box, l, t, r - l, b - t)
  end
  local e = token.edges
  pcall(function()
    -- Attributes, full height on the left.
    place(x + e.attributes.left, y + e.attributes.top,
          split + e.attributes.right, bottom + e.attributes.bottom)
    -- Melee attack, top right; ranged attack, bottom right.
    place(split + e.melee.left, y + e.melee.top,
          right + e.melee.right, middle + e.melee.bottom)
    place(split + e.ranged.left, middle + e.ranged.top,
          right + e.ranged.right, bottom + e.ranged.bottom)
  end)

  mw.ShiftStatValues()

  local paperDoll = U.G("PaperDollFrame")
  if paperDoll then
    U.PostHookScript(paperDoll, "OnShow", function() box:Show() end)
    U.PostHookScript(paperDoll, "OnHide", function() box:Hide() end)
    local ok, shown = pcall(paperDoll.IsShown, paperDoll)
    if ok and not shown then box:Hide() end
  end
end

-- The player's class icon inside the art's gold ring, from the same
-- class-portraits cells the unit-frame fallback uses. The player's class
-- cannot change in a session, so it is set once. An unknown token draws
-- nothing rather than the wrong class. Scaled from the 384x512 design so it
-- follows the quadrants if the window is not the stock size.
function mw.CharacterClassIcon(frame)
  local state = frame and frame.uuiModernWowWindow
  if not state or not state.chrome or state.classIcon then return end

  local ok, _, token = pcall(UnitClass, "player")
  local cell = ok and token and M.modernWow.classCell[token]
  if not cell then return end

  local ring = M.modernWow.characterRing
  local icon = mw.Texture(state.chrome, "ARTWORK",
                          M.modernWow.texture.classPortraits,
                          cell[1], cell[2], cell[3], cell[4])
  if not icon then return end

  local sx = mw.Dimension(frame, "GetWidth") / ring.designWidth
  local sy = mw.Dimension(frame, "GetHeight") / ring.designHeight
  local size = ring.size - 2 * ring.inset
  pcall(function()
    icon:SetWidth(size * sx)
    icon:SetHeight(size * sy)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT",
                  (ring.left + ring.inset) * sx,
                  -(ring.top + ring.inset) * sy)
  end)
  state.classIcon = icon
end

-- Where the Quest Log art draws its three button beds, in the window's own
-- coordinates, for the module that owns those buttons (modules/questlog.lua).
--
-- Recomputed per call rather than measured once: the beds are on the left
-- page, whose width is the live frame width times the art's seam, and the
-- window changes width whenever the details pane opens or closes. Returns
-- left, bottom, width and height as offsets from the frame's BOTTOMLEFT.
function U.ModernWowQuestLogButtonRect(index)
  if not mw.Active() then return nil end

  local cell = M.modernWow.questLog.buttonCell[index]
  if not cell then return nil end

  local frame = U.G(mw.questLogWindow.name)
  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return nil end

  local page = width * (M.modernWow.questLog.split or mw.quadrant.split)
  return cell.x * page, M.modernWow.questLog.buttonBottom * height,
         cell.width * page, M.modernWow.questLog.buttonHeight * height
end

-- Narrow seam used by modules/questlog.lua after the native frame changes
-- between its compact and expanded widths.
function U.ResizeModernWowQuestLog()
  if not mw.Active() then return false end
  return mw.ResizeSplitWindow(U.G(mw.questLogWindow.name))
end

-- ---------------------------------------------------------------------------
-- Surface: window headers
--
-- The three-piece Dragonflight title bar, drawn across the top of the same
-- windows. Separate from the quadrant surface because it is the piece most
-- likely to collide with a window's own title text, and collapsing both into
-- one flag would make that impossible to isolate.
-- ---------------------------------------------------------------------------
mw.headerHeight = 28

function mw.DressHeader(frame)
  if not frame or frame.uuiModernWowHeader then return nil end

  local state = frame.uuiModernWowWindow
  local parent = (state and state.chrome) or frame
  local cap = mw.headerHeight

  local left = mw.Texture(parent, "BORDER", M.modernWow.texture.headerLeft)
  if left then
    left:SetWidth(cap)
    left:SetHeight(cap)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  end

  local right = mw.Texture(parent, "BORDER", M.modernWow.texture.headerRight)
  if right then
    right:SetWidth(cap)
    right:SetHeight(cap)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  end

  local middle = mw.Texture(parent, "BORDER", M.modernWow.texture.header)
  if middle then
    middle:SetHeight(cap)
    middle:SetPoint("TOPLEFT", frame, "TOPLEFT", cap, 0)
    middle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -cap, 0)
  end

  frame.uuiModernWowHeader = { left = left, middle = middle, right = right }
  return frame.uuiModernWowHeader
end

function mw.BuildHeaders()
  local i
  for i = 1, table.getn(mw.windows) do
    local entry = mw.windows[i]
    local frame = U.G(entry.name)
    -- The Spellbook's housing already carries its header bar
    -- (modules/spellbookmodernwow.lua).
    local ownHeader = frame and frame.uuiModernWowWindow and
                      frame.uuiModernWowWindow.spellBook
    if frame and not entry.classicInteraction and not ownHeader then
      mw.DressHeader(frame)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Surface: close buttons
--
-- UnrealUI owns the glyph on every close button it skins
-- (U.StyleStockCloseButton). This swaps that owned glyph's art for the
-- Dragonflight one and nothing else: the button, its hit area, its hover and
-- pressed states and its OnClick all stay exactly where UnrealUI put them.
--
-- The button is located by the stock name beside each window, which is a plain
-- global lookup, not a walk of the window's children.
-- ---------------------------------------------------------------------------
mw.closeButtons = {
  "CharacterFrameCloseButton",
  "FriendsFrameCloseButton",
  "QuestLogFrameCloseButton",
  "SpellBookFrameCloseButton",
  "TalentFrameCloseButton",
}

function mw.DressCloseButton(name)
  local button = U.G(name)
  if not button or button.uuiModernWowClose then return end

  local cells = M.modernWow.redButtonCell

  -- The art IS the button here, so UnrealUI's own face comes off first: the
  -- flat fill and outline it drew (U.StyleStockButton) and the "X" glyph it
  -- owns (U.StyleStockCloseButton), which would otherwise sit on top of the
  -- Dragonflight X. The size, hit rect, placement and OnClick that
  -- U.StyleStockCloseButton set are all left exactly as they are -- 17x17 is
  -- already the size this art is drawn at in its source interface.
  mw.HideFlatSurface(button)
  if button.uuiCloseGlyph then
    pcall(button.uuiCloseGlyph.Hide, button.uuiCloseGlyph)
  end

  -- The button's own state slots, so the press, the hover and the disabled
  -- face are all driven by the client's button state machine exactly as they
  -- were before this theme touched the button. All four slots take the same
  -- atlas and differ only by cell, so the press costs one texture-coordinate
  -- pair rather than a second region and a pair of mouse handlers.
  --
  -- WORKING_SOURCE (DragonflightUI modules/micro/micro.lua switchColor): this
  -- Set*Texture + SetTexCoord per slot, with nothing hooked to the mouse, is
  -- how that addon drives a pressed face on this art. The one thing it never
  -- has to do is undo a strip first -- see mw.ButtonFace.
  mw.ButtonFace(button, "SetNormalTexture", "GetNormalTexture",
                cells.closeNormal)
  -- Row 3 of the atlas: the darkened, sunk-in face. This is the press.
  mw.ButtonFace(button, "SetPushedTexture", "GetPushedTexture",
                cells.closePushed)
  mw.ButtonFace(button, "SetDisabledTexture", "GetDisabledTexture",
                cells.closeDisabled)
  -- The atlas carries a dedicated glow for this (column 4, row 1) rather than
  -- expecting the resting face to be re-lit, so hover uses that cell.
  mw.ButtonFace(button, "SetHighlightTexture", "GetHighlightTexture",
                cells.highlight)

  button.uuiModernWowClose = true
end

-- Re-faces one shared collapse control (U.CreateCollapseButton) with the
-- atlas's arrow glyphs, for a surface whose art leaves no room for the flat
-- +/- box. The component and its state model are unchanged -- this overrides
-- only the media it draws with, which is what rules/unreal-ui-design.md allows
-- a theme to do to a shared widget.
--
-- The atlas carries a minus but no plus, so a literal +/- pair cannot come
-- from this art. The arrows stand in, and they show the CURRENT state rather
-- than the action: down-left while collapsed, up-right while expanded. Swap
-- the two cells below to invert that.
function mw.CollapseFace(icon)
  if not icon or icon.uuiModernWowFace then return false end

  local cells = M.modernWow.redButtonCell
  local created, face = pcall(icon.CreateTexture, icon, nil, "ARTWORK")
  if not created or not face then return false end
  if not pcall(face.SetTexture, face, M.modernWow.texture.redButton) then
    return false
  end
  pcall(face.SetAllPoints, face, icon)

  -- The flat box comes off: its backdrop is the chrome this art replaces, and
  -- its "+"/"-" label would sit on top of the glyph.
  if type(U.SetBackdropShown) == "function" then
    pcall(U.SetBackdropShown, icon, false)
  end
  if icon.text then pcall(icon.text.Hide, icon.text) end

  -- Hover keeps the component's accent feedback, moved from the (now hidden)
  -- outline onto the glyph itself so the state is still visible.
  icon:SetScript("OnEnter", function()
    pcall(face.SetVertexColor, face, M.Unpack(M.color.accent))
  end)
  icon:SetScript("OnLeave", function()
    pcall(face.SetVertexColor, face, 1, 1, 1, 1)
  end)

  -- Wraps the widget's own setter instead of replacing it, so uuiCollapsed and
  -- every caller of U.SetStockCollapseState keep working untouched.
  local native = icon.uuiSetCollapsed
  icon.uuiSetCollapsed = function(collapsed)
    if type(native) == "function" then pcall(native, collapsed) end
    local cell = collapsed and cells.minimizeNormal or cells.maximizeNormal
    pcall(face.SetTexCoord, face, cell[1], cell[2], cell[3], cell[4])
  end
  pcall(icon.uuiSetCollapsed, icon.uuiCollapsed)

  icon.uuiModernWowFace = face
  return true
end

-- Entry point for a module that owns a stock collapse header: hands in the
-- host button, not the icon, because uuiCollapseIcon is where the shared
-- component actually lives.
function U.ModernWowCollapseFace(button)
  if not mw.Active() or not button then return false end
  return mw.CollapseFace(button.uuiCollapseIcon)
end

-- Where the right page's recessed scroll channel lands, in the window's own
-- coordinates: left and width from the frame's LEFT edge, top as a NEGATIVE
-- offset from its TOP edge. Same contract and the same reason for being
-- recomputed as U.ModernWowQuestLogRingRect.
function U.ModernWowQuestLogScrollRect()
  if not mw.Active() then return nil end

  local channel = M.modernWow.questLog.scrollChannel
  if not channel then return nil end

  local frame = U.G(mw.questLogWindow.name)
  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return nil end

  -- The channel is on the RIGHT piece, so its fractions are of that piece and
  -- are offset by the seam rather than taken from the whole window.
  local split = M.modernWow.questLog.split or mw.quadrant.split
  local page = width * split
  local rightWidth = width - page

  return page + channel.left * rightWidth,
         -(channel.top * height),
         (channel.right - channel.left) * rightWidth,
         (channel.bottom - channel.top) * height
end

-- Where the left page's gold portrait ring lands, in the window's own
-- coordinates: left and width from the frame's LEFT edge, top as a NEGATIVE
-- offset from its TOP edge, so the result drops straight into SetPoint against
-- TOPLEFT. Recomputed per call for the same reason the button beds are -- the
-- window changes width whenever the details pane opens or closes.
function U.ModernWowQuestLogRingRect()
  if not mw.Active() then return nil end

  local ring = M.modernWow.questLog.portraitRing
  if not ring then return nil end

  local frame = U.G(mw.questLogWindow.name)
  local width = mw.Dimension(frame, "GetWidth")
  local height = mw.Dimension(frame, "GetHeight")
  if width <= 0 or height <= 0 then return nil end

  local page = width * (M.modernWow.questLog.split or mw.quadrant.split)
  return ring.left * page, -(ring.top * height),
         (ring.right - ring.left) * page, (ring.bottom - ring.top) * height
end

-- The ring is a frame for an icon the art does not draw: the Quest Log book
-- portrait classic-wow shows natively. The native region cannot be reused --
-- it is unnamed, lives on QuestLogFrame's BACKGROUND layer, and
-- modules/questlog.lua disables that layer and strips the region
-- (SetTexture(nil) + alpha 0) before this theme runs. So the same stock
-- texture is drawn on the addon-owned chrome instead, ARTWORK over the
-- BACKGROUND page art, fitted inside the ring.
function mw.PlaceQuestLogBook(frame)
  local state = frame and frame.uuiModernWowWindow
  local book = state and state.book
  if not book then return end

  local left, top, width, height = U.ModernWowQuestLogRingRect()
  if not left then return end

  local token = M.modernWow.questLog.bookIcon
  local inset = token.inset or 0
  local grow = token.grow or 0
  book:ClearAllPoints()
  book:SetWidth(width * (1 - 2 * inset) + grow)
  book:SetHeight(height * (1 - 2 * inset) + grow)
  book:SetPoint("CENTER", frame, "TOPLEFT",
                left + width / 2 + (token.x or 0),
                top - height / 2 + (token.y or 0))
end

function U.ModernWowQuestLogBook()
  if not mw.Active() then return nil end

  local frame = U.G(mw.questLogWindow.name)
  local state = frame and frame.uuiModernWowWindow
  if not state or not state.chrome then return nil end

  if not state.book then
    state.book = mw.Texture(state.chrome, "ARTWORK",
                            M.modernWow.questLog.bookIcon.path)
    if not state.book then return nil end
  end
  pcall(mw.PlaceQuestLogBook, frame)
  return state.book
end

function mw.BuildCloseButtons()
  local i
  for i = 1, table.getn(mw.closeButtons) do
    mw.DressCloseButton(mw.closeButtons[i])
  end
end

function mw.BuildMicroBar()
  if type(U.BuildModernWowMicroBar) ~= "function" then
    error("modern-wow micro-bar drawing path is unavailable")
  end
  -- Once the surface itself is on, a false return means only that the micro
  -- bar is switched off on the General page. That is the player's choice and
  -- there is nothing to draw, so it is not an error.
  U.BuildModernWowMicroBar()
end

-- The HUD bag bar (modules/bagbar.lua) chooses its art while it builds its own
-- buttons rather than being dressed afterwards, so this only confirms what that
-- produced. See U.BuildModernWowBagBar.
function mw.BuildBagBar()
  if type(U.BuildModernWowBagBar) ~= "function" then
    error("modern-wow bag-bar drawing path is unavailable")
  end
  if not U.BuildModernWowBagBar() then
    error("modern-wow bag-bar drawing path did not activate")
  end
end

function mw.BuildXPBars()
  if type(U.BuildModernWowXPBars) ~= "function" then
    error("modern-wow XP/reputation drawing path is unavailable")
  end
  if not U.BuildModernWowXPBars() then
    error("modern-wow XP/reputation drawing path did not activate")
  end
end

function mw.BuildActionBars()
  if type(U.BuildModernWowActionBars) ~= "function" then
    error("modern-wow action-bar drawing path is unavailable")
  end
  if not U.BuildModernWowActionBars() then
    error("modern-wow action-bar drawing path did not activate")
  end
end

-- ---------------------------------------------------------------------------
-- Surface registrations
--
-- Order is build order. Requested/verified surfaces default on; generic window
-- chrome and the remaining roadmap surfaces stay individually gated until they
-- have passed an in-game visual check.
-- ---------------------------------------------------------------------------
mw.RegisterSurface("unitframes", "Unit frames", true, mw.BuildUnitFrames)
mw.RegisterSurface("castbar", "Cast bars", true, mw.BuildCastBars)
mw.RegisterSurface("barfx", "Bar animation", true, mw.BuildBarFX)
mw.RegisterSurface("playerfx", "Player combat and rest glow", true,
                   mw.BuildPlayerFX)
mw.RegisterSurface("questlog", "Quest Log texture", true, mw.BuildQuestLog)
mw.RegisterSurface("character", "Character window", true, mw.BuildCharacter)
mw.RegisterSurface("windows", "Window chrome", false, mw.BuildWindows)
mw.RegisterSurface("headers", "Window headers", false, mw.BuildHeaders)
mw.RegisterSurface("close", "Close buttons", false, mw.BuildCloseButtons)
mw.RegisterSurface("actionbar", "Action bars", true, mw.BuildActionBars)
-- Shown only while modules/bags.lua is switched off, so most sessions never
-- see it at all. On by default for the same reason: when it does appear it is
-- the only bag control on screen, and a flat square in the corner of an
-- otherwise Dragonflight-styled interface is the wrong default.
mw.RegisterSurface("bagbar", "Bag bar", true, mw.BuildBagBar)
mw.RegisterSurface("microbar", "Micro bar", true, mw.BuildMicroBar)
mw.RegisterSurface("xpbar", "XP and reputation bars", true, mw.BuildXPBars)

-- modules/spellbook.lua draws this itself, from its own OnEnable, before its
-- toggles are built; the surface only gates that path and confirms it ran.
function mw.BuildSpellBook()
  if type(U.ModernWowSpellBookActive) ~= "function" or
     not U.ModernWowSpellBookActive() then
    error("modern-wow spellbook drawing path did not activate")
  end
end
mw.RegisterSurface("spellbook", "Spellbook", true, mw.BuildSpellBook)

-- Planned surfaces: art imported and tokenised in core/media.lua, no drawing
-- path yet. Registered with no build function so `/uui mw list` states the
-- real roadmap and enabling one is a no-op rather than a surprise.
--
-- These are not implemented from here because each needs a seam inside the
-- module that owns the frames, not a reach into its internals from outside --
-- the same reason modules/actionbar.lua already carries its own
-- U.StyleClassicActionButtonBorder family for the Classic theme rather than
-- letting another file dress its buttons:
--
--   bags       -> modules/bags.lua slot construction (slot, cutout, hover)
--                 plus the window background. The bag BAR is separate and
--                 already drawn -- see the `bagbar` surface above.
--   chat       -> the two scroll arrows only; the two-arrow control itself is
--                 a scope invariant and does not change.
mw.RegisterSurface("bags", "Bag window (planned)", false, nil)
mw.RegisterSurface("chat", "Chat arrows (planned)", false, nil)

-- ---------------------------------------------------------------------------
-- Lifecycle
--
-- OnEnable, not OnInit: this runs at PLAYER_LOGIN, after every module that
-- owns a frame has built it. modules/modernwow.lua is listed last in the TOC
-- for the same reason, so U.GetUnitFrame and the stock window globals already
-- resolve by the time this runs.
--
-- Each surface is built under its own pcall. One surface throwing must not
-- stop the rest, because the whole point of the registry is that surfaces are
-- judged independently.
-- ---------------------------------------------------------------------------
function MW:OnEnable()
  if not mw.Active() then return end

  local i
  for i = 1, table.getn(mw.surfaceOrder) do
    local surface = mw.surfaceOrder[i]
    if mw.Enabled(surface.id) and type(surface.build) == "function" then
      local ok, err = pcall(surface.build)
      surface.built = ok
      if not ok then
        U.Error("modern-wow surface " .. surface.id .. ": " .. tostring(err))
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Commands and diagnostics
--
-- `/uui mw` measures what this theme actually built and writes it to
-- UnrealUIDiagDB alongside a short chat summary. It exists because the layout
-- here is derived from source-pixel ratios against frame sizes the player can
-- change, so the first in-game session needs numbers rather than an eyeballed
-- screenshot -- and because knowledge.json /
-- textures.resources_cached_across_ui_reload means a wrong texture cannot
-- simply be corrected and reloaded, so guesses are expensive.
--
-- Measurement only: nothing here mutates a frame, and it runs on demand rather
-- than on any refresh path.
-- ---------------------------------------------------------------------------
function mw.Measure(frame)
  if not frame then return nil end
  return {
    width  = mw.Dimension(frame, "GetWidth"),
    height = mw.Dimension(frame, "GetHeight"),
    left   = mw.Dimension(frame, "GetLeft"),
    top    = mw.Dimension(frame, "GetTop"),
  }
end

function U.ModernWowSurfaces()
  U.Print("modern-wow surfaces (a change needs /reload):")
  local i
  for i = 1, table.getn(mw.surfaceOrder) do
    local surface = mw.surfaceOrder[i]
    local enabled = mw.Enabled(surface.id)
    local state
    if type(surface.build) ~= "function" then
      state = "not implemented"
    elseif not enabled then
      state = "off"
    elseif surface.built then
      state = "on, built"
    else
      state = "on, NOT built"
    end
    U.Print("  " .. surface.id .. " -- " .. surface.label .. ": " .. state)
  end
end

function U.ModernWowSetSurface(id, enabled)
  local surface = mw.surfaces[id]
  if not surface then
    U.Print("modern-wow: no surface named " .. tostring(id))
    U.ModernWowSurfaces()
    return false
  end

  mw.Config()["surface_" .. id] = enabled and true or false
  U.Print("modern-wow: " .. id .. " is now " ..
          (enabled and "on" or "off") .. " -- /reload to apply")
  return true
end

function U.ModernWowReport()
  local report = {
    theme = tostring(U.GetActiveThemeStyle and U.GetActiveThemeStyle() or "?"),
    active = mw.Active(),
    surfaces = {},
    units = {},
    castBars = {},
    windows = {},
  }

  local i
  for i = 1, table.getn(mw.surfaceOrder) do
    local surface = mw.surfaceOrder[i]
    report.surfaces[surface.id] = {
      enabled = mw.Enabled(surface.id),
      built = surface.built,
    }
  end

  for i = 1, table.getn(mw.units) do
    local entry = mw.units[i]
    local frame = type(U.GetUnitFrame) == "function"
                  and U.GetUnitFrame(entry.id) or nil
    local state = frame and frame.uuiModernWow
    report.units[entry.id] = {
      frame     = mw.Measure(frame),
      portrait  = frame and mw.Measure(frame.portrait) or nil,
      health    = frame and mw.Measure(frame.health) or nil,
      power     = frame and mw.Measure(frame.power) or nil,
      housing   = state and mw.Measure(state.housing) or nil,
      dressed   = state ~= nil,
      scale     = state and state.scale or 0,
      powerFill = entry.power or "-",
    }
  end

  for i = 1, table.getn(mw.castBars) do
    local name = mw.castBars[i]
    local widget = U.G(name)
    local state = widget and widget.uuiModernWow
    report.castBars[name] = {
      frame   = mw.Measure(widget),
      bar     = widget and mw.Measure(widget.bar) or nil,
      dressed = state ~= nil,
      spark   = state ~= nil and state.spark ~= nil,
      flash   = state ~= nil and state.flash ~= nil,
    }
  end

  for i = 1, table.getn(mw.windows) do
    local name = mw.windows[i].name
    local frame = U.G(name)
    report.windows[name] = {
      frame   = mw.Measure(frame),
      exists  = frame ~= nil,
      dressed = frame ~= nil and frame.uuiModernWowWindow ~= nil,
      header  = frame ~= nil and frame.uuiModernWowHeader ~= nil,
    }
  end

  U.Print("modern-wow: theme=" .. report.theme ..
          " active=" .. tostring(report.active))
  U.ModernWowSurfaces()
  if type(U.SaveDiagnostic) == "function" then
    U.SaveDiagnostic("modernWow", report)
    U.Print("saved to UnrealUIDiagDB.modernWow -- " .. U.SavedVariablesHint())
  end
end
