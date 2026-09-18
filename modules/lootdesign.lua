-- unrealUI :: modules/lootdesign.lua
--
-- One independent module owns the corpse loot window, in two designs (user
-- requests, 2026-09-19). lw.Style resolves which one draws, once:
--
--   "modern-wow" -- the Dragonflight chrome: thin grey metal rim, dark body and
--                   title band, red close button, and per row the professions
--                   card, the combined bag's slot rim around the icon and the
--                   item's quality name. Drawn under the `modern-wow` "loot"
--                   surface and under the `classic-wow` "loot" Classic ->
--                   Modern WoW module (on by default) -- one design in both
--                   themes, the same explicit exception to the theme-scope rule
--                   in .claude/rules/unreal-ui-design.md that the bag family
--                   carries.
--   "modern"     -- UnrealUI's flat system: near-black panel with one 1-unit
--                   outline, accent title over a 1-unit rule, the shared close
--                   button, and per row a flat surface with a single outline
--                   around the icon. lw.BuildFlatChrome onward.
--   nil          -- `classic-wow` with the module off: the native window is
--                   left untouched.
--
-- Everything else is one path. The geometry, strip, fit, drag strip, position
-- store, tooltip placement and animation are design-free, and the two token
-- tables (M.modernWow.loot and M.loot.flat) share key names so they read the
-- active one through lw.Token. Both selections are reload-bound, like every
-- other theme switch.
--
-- The window's animation is separate and runs under every theme, `modern`
-- included (user request, 2026-09-19): it fades the window in, staggers the
-- rows and slides a looted item out, all of which move and fade what the
-- client already draws. lw.AnimWanted gates it, lw.Wanted gates the design,
-- and with only the animation on the slide carries the item's icon and name
-- without this module's card or rim -- so no theme gains chrome it does not
-- have. Shared timings live in M.loot (core/media.lua), outside M.modernWow.
--
-- The native LootFrame and its LootButton rows remain the only interaction
-- owners. Scripted looting does not claim items on this client (knowledge.json
-- / loot.native_shift_autoloot_and_scripted_slot_failure), so a replacement
-- window could never loot; this path only redraws around the native one.
-- UnrealRuntimeProbe lootskin.v1/v2 (2026-09-19) established what it relies
-- on: LootFrame's five regions (LootFramePortraitOverlay, the unnamed
-- UI-LootPanel art, the title and LootFramePrev/Next) strip through a region
-- walk and by name, an addon child panel draws behind the rows, and a physical
-- row click still loots with that panel in place.
--
-- Rules honoured: LootFrame is never shown, hidden or re-scripted and no event
-- is unregistered; addon chrome never takes the mouse; LootFrame is stripped
-- by walk only because every addon region lives on an addon child or on the
-- rows, never on LootFrame itself; row geometry is read once, as numbers,
-- when the window first opens (rules/unreal-ui.md, native widget ownership).
--
-- Local budget: one table, per rules/unreal-ui.md.
local U = UnrealUI
local M = U.media
local lw = { built = false, failed = false, rows = {}, hooked = false }

function lw.Anim() return M.loot end

-- Which design draws the window, or nil for none.
--
--   "modern-wow" -- the Dragonflight chrome, under the `modern-wow` "loot"
--                   surface or the `classic-wow` "loot" module.
--   "modern"     -- UnrealUI's flat system (user request, 2026-09-19).
--   nil          -- nothing: `classic-wow` with the module off keeps the
--                   untouched native window.
--
-- Read once and cached. Both selections are reload-bound, and lw.Token is on
-- the fit, tooltip and row paths, so this must not re-resolve per call.
function lw.Style()
  if lw.style == nil then
    local style = false
    if type(U.ModernWowSurfaceEnabled) == "function" and
       U.ModernWowSurfaceEnabled("loot") then
      style = "modern-wow"
    elseif type(U.GetActiveThemeStyle) == "function" and
           U.GetActiveThemeStyle() == "modern" then
      style = "modern"
    end
    lw.style = style
  end
  return lw.style or nil
end

-- The design gate.
function lw.Wanted()
  return lw.Style() ~= nil
end

-- Layout numbers for the active design. The two token tables share key names
-- for everything the shared mechanics read -- pad, header, footer, cardWidth,
-- close, drag, tooltip, quality -- so lw.Fit, lw.BuildDragHandle and
-- lw.PlaceTooltip stay one path per rules/unreal-ui-design.md's branching rule.
function lw.Token()
  if lw.Style() == "modern" then return M.loot.flat end
  return M.modernWow.loot
end

-- The animation gate (user request, 2026-09-19: the animation runs under
-- `modern` too, with no design change). The animation is behaviour -- it fades
-- and slides what the client already draws, adds no chrome and moves no native
-- row -- so it is not tied to lw.Wanted. Under `modern` the window stays the
-- native one: it fades in, its rows stagger, and a looted item's icon and name
-- slide out, with none of the theme's card or rim behind them.
--
-- Kept as a function so a future switch has one place to live, and so every
-- animation path reads the same gate rather than checking the theme itself.
function lw.AnimWanted()
  return not lw.failed
end

function lw.Texture(parent, layer, path)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  if path then pcall(texture.SetTexture, texture, path) end
  return texture
end

function lw.Rect(object)
  if not object then return nil end
  local ok, l, t, r, b = pcall(function()
    return object:GetLeft(), object:GetTop(), object:GetRight(), object:GetBottom()
  end)
  l, t, r, b = tonumber(l), tonumber(t), tonumber(r), tonumber(b)
  if not ok or not l or not t or not r or not b then return nil end
  return { left = l, top = t, right = r, bottom = b }
end

-- ---------------------------------------------------------------------------
-- Strip
--
-- The UI-LootPanel art has no global name, so LootFrame is walked. Textures go
-- through the shared strip; the one unnamed FontString is the stock title,
-- replaced by this path's own, and is hidden. Repeated on
-- every open because nothing establishes that the client leaves a stripped
-- region alone across LootFrame_Show.
-- ---------------------------------------------------------------------------
function lw.Strip(frame)
  U.StripStockTextures(frame)
  U.HideRegion(U.G("LootFramePortraitOverlay"))

  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return end
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local typeOk, kind = pcall(region.GetObjectType, region)
    if typeOk and kind == "FontString" then
      local nameOk, name = pcall(region.GetName, region)
      -- Hide, not SetAlpha: `/urp interface LootFrame` (2026-09-19) showed
      -- this title still at alpha 1 after SetAlpha(0) through the walk, while
      -- the textures the same walk stripped read shown=false, alpha 1 -- the
      -- walked wrapper honours Hide and ignores SetAlpha.
      if nameOk and (name == nil or name == "") then
        pcall(region.Hide, region)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Geometry, read once from the live rows while the window is on screen
-- ---------------------------------------------------------------------------
function lw.Measure(frame)
  local count = type(U.LootRowCount) == "function" and U.LootRowCount() or 0
  if count < 1 then return nil end

  local host = lw.Rect(frame)
  local first = lw.Rect(U.G("LootButton1"))
  if not host or not first then return nil end

  -- Each row's and the page arrows' bottom, as distances below the frame's
  -- top, so lw.Fit can size the window to whatever is shown.
  local rowBottoms = { host.top - first.bottom }
  local i
  for i = 2, count do
    local rect = lw.Rect(U.G("LootButton" .. i))
    rowBottoms[i] = rect and (host.top - rect.bottom) or rowBottoms[i - 1]
  end
  local arrowBottom = nil
  local names = { "LootFrameUpButton", "LootFrameDownButton" }
  for i = 1, 2 do
    local rect = lw.Rect(U.G(names[i]))
    if rect and (not arrowBottom or host.top - rect.bottom > arrowBottom) then
      arrowBottom = host.top - rect.bottom
    end
  end

  return {
    count = count,
    iconLeft = first.left - host.left,
    rowsTop = host.top - first.top,
    rowBottoms = rowBottoms,
    arrowBottom = arrowBottom,
    buttonSize = first.top - first.bottom,
  }
end

function lw.Shown(object)
  if not object then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

-- Window height follows the lowest visible row, or the page arrows while the
-- loot paginates (user request, 2026-09-19: no empty space under few items).
function lw.Fit()
  local g, t = lw.geo, lw.Token()
  if not g or not lw.chrome then return end
  local bottom = g.rowBottoms[1]
  local i
  for i = 1, g.count do
    if lw.Shown(U.G("LootButton" .. i)) and g.rowBottoms[i] > bottom then
      bottom = g.rowBottoms[i]
    end
  end
  if g.arrowBottom and g.arrowBottom > bottom and
     (lw.Shown(U.G("LootFrameUpButton")) or lw.Shown(U.G("LootFrameDownButton"))) then
    bottom = g.arrowBottom
  end
  pcall(lw.chrome.SetHeight, lw.chrome, t.header + (bottom - g.rowsTop) + t.footer)
end

-- ---------------------------------------------------------------------------
-- Window chrome
-- ---------------------------------------------------------------------------
function lw.BuildChrome(frame, g)
  local t = lw.Token()
  local left = g.iconLeft - t.pad
  local top = g.rowsTop - t.header
  local width = t.pad + t.cardWidth + t.pad
  local height = t.header + (g.rowBottoms[g.count] - g.rowsTop) + t.footer

  local chrome = CreateFrame("Frame", nil, frame)
  pcall(chrome.EnableMouse, chrome, false)
  pcall(chrome.SetFrameLevel, chrome, frame:GetFrameLevel())
  chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
  chrome:SetWidth(width)
  chrome:SetHeight(height)
  lw.chrome = chrome

  local fill = lw.Texture(chrome, "BACKGROUND", "Interface\\Buttons\\WHITE8X8")
  if fill then
    pcall(fill.SetVertexColor, fill, M.Unpack(t.fill))
    fill:SetPoint("TOPLEFT", chrome, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -2, 2)
  end

  local streak = lw.Texture(chrome, "BACKGROUND", t.streak)
  if streak then
    local c = t.streakTexCoord
    pcall(streak.SetTexCoord, streak, c[1], c[2], c[3], c[4])
    streak:SetPoint("TOPLEFT", chrome, "TOPLEFT", 3, -3)
    streak:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -3, -3)
    streak:SetHeight(t.header - 3)
  end

  if type(U.ModernWowThinBorder) == "function" then
    U.ModernWowThinBorder(chrome)
  end

  -- Rule separating the title band (title and close button) from the rows.
  local rule = t.headerRule
  local line = lw.Texture(chrome, "BORDER", t.border.top)
  if line and rule then
    local c = rule.texCoord
    pcall(line.SetTexCoord, line, c[1], c[2], c[3], c[4])
    line:SetHeight(rule.height)
    local y = -(t.header - rule.lineOffset)
    line:SetPoint("TOPLEFT", chrome, "TOPLEFT", rule.inset, y)
    line:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -rule.inset, y)
  end
  local title = U.CreateLabel(chrome, { size = t.title.size,
    color = t.title.color, justify = "CENTER" })
  if title then
    title:SetPoint("TOP", chrome, "TOP", 0, t.title.y)
    pcall(title.SetText, title, U.L("LOOT_TITLE"))
  end

  -- The native close keeps its OnClick; only its place and face change.
  local close = U.G("LootCloseButton")
  if close then
    pcall(function()
      close:ClearAllPoints()
      close:SetPoint("TOPRIGHT", frame, "TOPLEFT",
                     left + width + t.close.right, -top + t.close.top)
      close:SetWidth(t.close.size)
      close:SetHeight(t.close.size)
    end)
    if type(U.ModernWowDressCloseButton) == "function" then
      U.ModernWowDressCloseButton("LootCloseButton")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rows
--
-- Everything a row draws is a region of that LootButton, so it shows, hides
-- and pages with the button and needs no visibility bookkeeping here. The
-- card sits in BACKGROUND under the icon (BORDER), the rim in ARTWORK over it
-- and under the count, as on the combined bag's slots.
-- ---------------------------------------------------------------------------
function lw.CardSlice(button, height, u1, u2, width)
  local t = lw.Token()
  local texture = lw.Texture(button, "BACKGROUND", t.atlas)
  if not texture then return nil end
  local c = t.card
  local aw, ah = t.atlasSize.width, t.atlasSize.height
  pcall(texture.SetTexCoord, texture, u1 / aw, u2 / aw, c.top / ah, c.bottom / ah)
  pcall(texture.SetHeight, texture, height)
  if width then pcall(texture.SetWidth, texture, width) end
  return texture
end

-- The stock name plate behind the row text. Its global name is not the one
-- Vanilla declares on this client, so the row is walked once, before any
-- addon region exists on it (rules/unreal-ui.md: strip before adding). Walked
-- regions are told apart by name: this client names an unnamed texture after
-- its file (lootskin.v2 read "Interface/LootFrame/UI-LootPanel_0x..."), so
-- only a name-plate texture is hidden and the icon is never touched.
function lw.StripRow(button)
  local ok, regions = pcall(function() return { button:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return end
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local typeOk, kind = pcall(region.GetObjectType, region)
    local nameOk, rname = pcall(region.GetName, region)
    if typeOk and kind == "Texture" and nameOk and type(rname) == "string" then
      local lower = string.lower(rname)
      if string.find(lower, "nameframe", 1, true) then U.HideRegion(region) end
    end
  end
end

-- The row face -- professions card and bag slot rim -- on any owner the size
-- of a LootButton: the dressed row itself, or a looted-item ghost. Returns
-- the card's right cap, which the quality label anchors to.
function lw.BuildFace(owner, size)
  local t = lw.Token()
  -- The card starts under the icon's centre and is slightly shorter than it,
  -- so its outline emerges from behind the icon rim instead of running
  -- alongside it (user request, 2026-09-19: fewer overlapping borders).
  local c = t.card
  local inset = t.cardInset
  local height = size - 2 * inset
  local startX = math.floor(size / 2)
  local cap = math.floor(c.cap * height / (c.bottom - c.top) + 0.5)
  local leftCap = lw.CardSlice(owner, height, c.left, c.left + c.cap, cap)
  local rightCap = lw.CardSlice(owner, height, c.right - c.cap, c.right, cap)
  local middle = lw.CardSlice(owner, height, c.left + c.cap, c.right - c.cap)
  if leftCap and rightCap and middle then
    leftCap:SetPoint("TOPLEFT", owner, "TOPLEFT", startX, -inset)
    rightCap:SetPoint("TOPLEFT", owner, "TOPLEFT", t.cardWidth - cap, -inset)
    middle:SetPoint("TOPLEFT", leftCap, "TOPRIGHT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", rightCap, "BOTTOMLEFT", 0, 0)
  end

  local slot = t.slotRim
  local rim = lw.Texture(owner, "ARTWORK", slot.frame)
  if rim then
    local color = slot.frameColor
    if color then pcall(rim.SetVertexColor, rim, M.Unpack(color)) end
    rim:SetWidth(size + (slot.grow or 0))
    rim:SetHeight(size + (slot.grow or 0))
    rim:SetPoint("CENTER", owner, "CENTER", 0, 0)
  end

  return rightCap
end

-- ---------------------------------------------------------------------------
-- The `modern` design (user request, 2026-09-19)
--
-- UnrealUI's flat system on the same measured geometry as the themed path: a
-- near-black panel with one 1-unit outline behind the native rows, a 1-unit
-- rule under a short accent title, the shared 17-unit close button, and per row
-- one flat tinted surface with the icon framed by a single outline. No bevel,
-- no gloss, no second border, and the stock state squares are replaced by the
-- accent hover/press fills rather than hidden, so the client keeps driving them
-- (rules/unreal-ui-design.md).
--
-- The native LootFrame, its rows and its close button remain the interaction
-- owners here exactly as they are under the themed path.
-- ---------------------------------------------------------------------------
function lw.BuildFlatChrome(frame, g)
  local t = lw.Token()
  local left = g.iconLeft - t.pad
  local top = g.rowsTop - t.header
  local width = t.pad + t.cardWidth + t.pad
  local height = t.header + (g.rowBottoms[g.count] - g.rowsTop) + t.footer

  local chrome = U.CreatePanel(frame, {
    width = width,
    height = height,
    background = M.color.background,
    border = M.color.border,
  })
  pcall(chrome.EnableMouse, chrome, false)
  pcall(chrome.SetFrameLevel, chrome, frame:GetFrameLevel())
  chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
  lw.chrome = chrome

  local rule = lw.Texture(chrome, "BORDER", M.texture.plain)
  if rule then
    pcall(rule.SetVertexColor, rule, M.Unpack(M.color.border))
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", chrome, "TOPLEFT", t.rule.inset, -t.header)
    rule:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -t.rule.inset, -t.header)
  end

  local title = U.CreateLabel(chrome, { size = t.title.size,
    color = t.title.color, justify = "CENTER" })
  if title then
    title:SetPoint("TOP", chrome, "TOP", 0, t.title.y)
    pcall(title.SetText, title, U.L("LOOT_TITLE"))
  end

  -- The native close keeps its OnClick; the shared helper owns its size, hit
  -- rect and glyph.
  U.StyleStockCloseButton(U.G("LootCloseButton"), chrome, t.close.right,
                          t.close.top)
end

-- One 1-unit outline around the `size` square at the owner's top-left -- the
-- icon's frame in this design. Explicit edge textures rather than the shared
-- backdrop, because the same call has to work on a native row button, where the
-- square is the whole frame, and on the wider slide frame, where a backdrop
-- would outline the slide instead of the icon.
function lw.FlatIconEdges(owner, size)
  local specs = {
    { 0, 0, size, 1 },
    { 0, -(size - 1), size, 1 },
    { 0, 0, 1, size },
    { size - 1, 0, 1, size },
  }
  local i
  for i = 1, 4 do
    local spec = specs[i]
    local edge = lw.Texture(owner, "OVERLAY", M.texture.plain)
    if not edge then return end
    pcall(edge.SetVertexColor, edge, M.Unpack(M.color.border))
    edge:SetWidth(spec[3])
    edge:SetHeight(spec[4])
    edge:SetPoint("TOPLEFT", owner, "TOPLEFT", spec[1], spec[2])
  end
end

-- The flat row face, on any owner the size of a LootButton: the dressed row or
-- a looted-item slide. Returns the row surface, which the quality label anchors
-- to. Same shape as lw.BuildFace so lw.Face can dispatch between them.
function lw.BuildFlatFace(owner, size)
  local t = lw.Token()
  local startX = math.floor(size / 2)
  local strip = lw.Texture(owner, "BACKGROUND", M.texture.plain)
  if strip then
    pcall(strip.SetVertexColor, strip, M.Unpack(t.rowFill))
    strip:SetHeight(size - 2 * t.rowInset)
    strip:SetWidth(t.cardWidth - startX)
    strip:SetPoint("TOPLEFT", owner, "TOPLEFT", startX, -t.rowInset)
  end
  lw.FlatIconEdges(owner, size)
  return strip
end

-- The active design's row face.
function lw.Face(owner, size)
  if lw.Style() == "modern" then return lw.BuildFlatFace(owner, size) end
  return lw.BuildFace(owner, size)
end

function lw.DressRow(index, size)
  local name = "LootButton" .. index
  local button = U.G(name)
  if not button or button.uuiLootDressed then return end
  button.uuiLootDressed = true

  local t = lw.Token()
  lw.StripRow(button)
  pcall(button.SetNormalTexture, button, "")
  U.HideRegion(U.G(name .. "NormalTexture"))

  -- lootclick.v1 (2026-09-19): on press the button shows its stock
  -- UI-Quickslot-Depress square and on hover ButtonHilight-Square, both drawn
  -- as bevelled squares over the bag rim -- the "border glitch" on click. The
  -- state slots stay the button's own (the client still drives them); only
  -- their art becomes an icon-sized fill, so press and hover tint the icon
  -- without a second border. The themed design uses the combined bag's grey
  -- for both; `modern` uses a subdued accent on hover and the accent fill on
  -- press, as rules/unreal-ui-design.md requires of a real hover/pressed state.
  local hover = t.hoverFill or t.stateFill
  local press = t.pressFill or t.stateFill
  local okP, pushed = pcall(button.GetPushedTexture, button)
  if okP and pushed then
    pcall(pushed.SetTexture, pushed, press[1], press[2], press[3], press[4])
  end
  local okH, highlight = pcall(button.GetHighlightTexture, button)
  if okH and highlight then
    pcall(highlight.SetTexture, highlight, hover[1], hover[2], hover[3], hover[4])
  end

  local rightCap = lw.Face(button, size)

  local quality = U.CreateLabel(button, { size = t.quality.size,
    justify = "RIGHT", layer = "OVERLAY" })
  if quality and rightCap then
    quality:SetPoint("TOPRIGHT", rightCap, "TOPRIGHT", t.quality.right, t.quality.top)
  end
  lw.rows[index] = { button = button, quality = quality }
end

-- LootSlotIsCoin is documented only; a missing or throwing call just means the
-- coin row may get a quality name, never an error.
function lw.IsCoin(slot)
  local fn = U.G("LootSlotIsCoin")
  if type(fn) ~= "function" then return false end
  local ok, value = pcall(fn, slot)
  return ok and value and value ~= 0
end

function lw.Refresh()
  lw.Fit()
  lw.RestoreRows()
  lw.shown = lw.shown or {}
  local index, row
  for index, row in pairs(lw.rows) do
    local text, color, glowQuality = "", nil, nil
    local slot = type(U.LootRowSlot) == "function" and U.LootRowSlot(row.button, index)
    -- What each visible row shows, kept for its looted-item ghost: once the
    -- slot clears, the client no longer reports it. Entries are merged into
    -- the LOOT_OPENED snapshot, never reset here: this refresh runs a frame
    -- after the open and again after every clear, so emptying the table would
    -- throw away the faces of an all-at-once loot before their ghosts launch
    -- (user-observed 2026-09-19: Shift-looting played no slides at all).
    -- A slot keeps its item for the life of one window, so re-writing a
    -- visible slot only corrects its row index after the client pages.
    if slot and lw.Shown(row.button) then
      local infoOk, texture, itemName, count, itemQuality = pcall(GetLootSlotInfo, slot)
      if infoOk and texture then
        lw.shown[slot] = { row = index, texture = texture, name = itemName,
                           count = tonumber(count), quality = tonumber(itemQuality) }
      end
    end
    if slot and not lw.IsCoin(slot) then
      local ok, _, _, _, quality = pcall(GetLootSlotInfo, slot)
      quality = ok and tonumber(quality)
      if quality and quality >= 0 and quality <= 6 then
        text = U.L("LOOT_QUALITY_" .. quality)
        color = U.ItemQualityColor(quality)
        glowQuality = quality
      end
    end
    -- Rarity edge on the icon: the Character window's shared glow component.
    if type(U.SetItemQualityGlow) == "function" then
      U.SetItemQualityGlow(row.button, glowQuality)
    end
    if row.quality then
      pcall(row.quality.SetText, row.quality, text)
      -- Always set, so a reused row never keeps the previous item's colour.
      color = color or M.color.text
      pcall(row.quality.SetTextColor, row.quality, color[1], color[2], color[3], 1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Looted-item ghost (user request, 2026-09-19)
--
-- The client hides a row the moment its slot clears, so the looted item is
-- replayed by an addon-owned copy of its face -- card, rim, icon and name --
-- drawn over the row's measured position, easing right while it fades. The
-- native rows are never moved. Ghosts are UIParent children placed over the
-- row's own icon from LootFrame's corner, so one still finishes after the last
-- item closes the window, and the placement needs no chrome to exist.
-- Clears that arrive close together (Shift-click looting everything) are
-- staggered by `ghostStagger`.
-- ---------------------------------------------------------------------------
lw.ghosts = {}
lw.ghostSerial = 0
lw.ghostNext = 0

function lw.NewGhost()
  local i
  for i = 1, table.getn(lw.ghosts) do
    if not lw.ghosts[i].busy then return lw.ghosts[i] end
  end
  local g, a = lw.geo, lw.Anim()
  local size = g.buttonSize
  local width, gap = a.ghostWidth, a.ghostTextGap
  local frame = CreateFrame("Frame", nil, UIParent)
  pcall(frame.EnableMouse, frame, false)
  frame:SetWidth(width)
  frame:SetHeight(size)
  local ghost = { frame = frame }
  ghost.icon = lw.Texture(frame, "BORDER")
  if ghost.icon then
    ghost.icon:SetWidth(size)
    ghost.icon:SetHeight(size)
    ghost.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  end
  -- The slide wears the active design's row face, so it reads as the row it
  -- came from. With no design at all -- `classic-wow` with the module off --
  -- it carries the item's own icon and name and nothing else, so the animation
  -- never introduces chrome that theme does not have.
  if lw.Wanted() then lw.Face(frame, size) end
  ghost.name = U.CreateLabel(frame, { size = M.fontSize.normal,
    justify = "LEFT", layer = "OVERLAY" })
  if ghost.name then
    ghost.name:SetPoint("LEFT", frame, "LEFT", size + gap, 0)
    pcall(ghost.name.SetWidth, ghost.name, width - size - 2 * gap)
  end
  table.insert(lw.ghosts, ghost)
  return ghost
end

-- Over the row's own icon, measured from LootFrame's top-left rather than from
-- the chrome: the same place the chrome path put it, and the only anchor that
-- exists when no chrome is drawn.
function lw.PlaceGhost(ghost, row, dx)
  local g = lw.geo
  local frame = U.G("LootFrame")
  if not frame then return end
  ghost.frame:ClearAllPoints()
  ghost.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", g.iconLeft + dx,
                       -(g.rowBottoms[row] - g.buttonSize))
end

-- The client does not drop the looted row immediately (user-observed
-- 2026-09-19: the frame looked duplicated under the ghost), so the row is made
-- invisible while its ghost plays. Alpha only -- the button stays shown and
-- clickable. lw.RestoreRows brings it back, faded in, once the refresh finds
-- the row showing a different item; a row that still points at the cleared
-- slot stays invisible until the window reopens or closes (both reset alpha).
lw.hiddenRows = {}

function lw.HideRowUnderGhost(row, slot)
  local button = U.G("LootButton" .. row)
  if not button then return end
  if type(U.StopEasing) == "function" then U.StopEasing("loot.row" .. row) end
  pcall(button.SetAlpha, button, 0)
  lw.hiddenRows[row] = slot
end

function lw.RestoreRows()
  local a = lw.Anim().anim
  local row, cleared
  for row, cleared in pairs(lw.hiddenRows) do
    local button = U.G("LootButton" .. row)
    local slot = button and type(U.LootRowSlot) == "function" and
                 U.LootRowSlot(button, row)
    local okInfo, texture = false, nil
    if slot and slot ~= cleared then okInfo, texture = pcall(GetLootSlotInfo, slot) end
    if button and lw.Shown(button) and okInfo and texture then
      lw.hiddenRows[row] = nil
      local target = button
      U.StartEasing("loot.row" .. row, { from = 0, to = 1, duration = a.row,
        ease = U.EaseOutCubic,
        onUpdate = function(value) target:SetAlpha(value) end })
    end
  end
end

-- Every slot's face, taken synchronously on LOOT_OPENED. The per-row
-- snapshot in lw.Refresh runs a frame later, which is too late when the whole
-- corpse is looted at once (Shift-click): the slots have already cleared.
-- Rows follow the client's paging -- a paged window gives the last row to the
-- page arrows -- and slots past the first page reuse row positions; they only
-- ever play as staggered ghosts, never as visible rows.
function lw.SnapshotAll()
  local g = lw.geo
  if not g then return end
  local okTotal, total = pcall(GetNumLootItems)
  total = okTotal and tonumber(total) or 0
  local rows = g.count
  local perPage = rows
  if total > rows then perPage = rows - 1 end
  if perPage < 1 then return end
  local slot
  for slot = 1, total do
    local ok, texture, itemName, count, quality = pcall(GetLootSlotInfo, slot)
    if ok and texture then
      local row = slot - perPage * math.floor((slot - 1) / perPage)
      lw.shown[slot] = { row = row, texture = texture, name = itemName,
                         count = tonumber(count), quality = tonumber(quality) }
    end
  end
end

function lw.LaunchGhost(slot)
  local info = slot and lw.shown and lw.shown[slot]
  local frame = U.G("LootFrame")
  -- No visibility test: when everything is looted at once the client closes
  -- the window in the same frame as the clears, and each ghost must still play
  -- over where its row was, from the hidden window's last position.
  if not info or not lw.geo or not frame then return end
  lw.shown[slot] = nil
  local a = lw.Anim().anim
  local ghost = lw.NewGhost()
  ghost.busy = true

  pcall(ghost.frame.SetFrameStrata, ghost.frame, frame:GetFrameStrata())
  pcall(ghost.frame.SetFrameLevel, ghost.frame, frame:GetFrameLevel() + 10)
  if ghost.icon then pcall(ghost.icon.SetTexture, ghost.icon, info.texture) end
  if ghost.name then
    pcall(ghost.name.SetText, ghost.name, info.name or "")
    local color = info.quality and U.ItemQualityColor(info.quality) or M.color.text
    pcall(ghost.name.SetTextColor, ghost.name, color[1], color[2], color[3], 1)
  end
  lw.PlaceGhost(ghost, info.row, 0)
  pcall(ghost.frame.SetAlpha, ghost.frame, 1)
  lw.HideRowUnderGhost(info.row, slot)
  pcall(ghost.frame.Show, ghost.frame)

  local now = GetTime()
  local delay = lw.ghostNext - now
  if delay < 0 then delay = 0 end
  lw.ghostNext = now + delay + a.ghostStagger
  local total = delay + a.ghost

  lw.ghostSerial = lw.ghostSerial + 1
  U.StartEasing("loot.ghost" .. lw.ghostSerial, { from = 0, to = 1,
    duration = total,
    ease = function(progress)
      local local01 = (progress * total - delay) / a.ghost
      if local01 <= 0 then return 0 end
      return U.EaseOutCubic(local01)
    end,
    onUpdate = function(value)
      lw.PlaceGhost(ghost, info.row, a.ghostSlide * value)
      ghost.frame:SetAlpha(1 - value)
    end,
    onComplete = function()
      pcall(ghost.frame.Hide, ghost.frame)
      ghost.busy = false
    end })
end

-- ---------------------------------------------------------------------------
-- Moving the window (user request, 2026-09-19)
--
-- Same model as the combined bag (modules/bags.lua): a drag strip across the
-- title band, left of the close button, moves the frame that owns the window
-- rect -- here the native LootFrame, since the chrome hangs off it -- and the
-- drop is stored through the shared position store. Each open re-applies the
-- stored point after the client has placed the window; with nothing stored
-- the client's own placement is left alone. /uui reset clears the store and
-- the next open is native again.
-- ---------------------------------------------------------------------------
lw.POSITION_ID = "loot.window"

function lw.ApplyPosition(frame)
  local saved = U.GetPosition(lw.POSITION_ID)
  if not saved then return end
  if not U.ApplyFramePoint(frame, saved) then
    U.Debug("loot: failed to apply stored position")
  end
end

function lw.StartDrag()
  local frame = U.G("LootFrame")
  if not frame then return end
  if not pcall(frame.SetMovable, frame, true) then
    U.Error("loot: SetMovable failed; the loot window cannot be moved")
    return
  end
  if not pcall(frame.StartMoving, frame) then
    U.Error("loot: StartMoving failed; the loot window will not drag")
  end
end

function lw.StopDrag()
  local frame = U.G("LootFrame")
  if not frame then return end
  pcall(frame.StopMovingOrSizing, frame)
  -- Edge-derived, not GetPoint offsets (U.GetFramePlacement explains why).
  local placed = U.GetFramePlacement(frame)
  if not placed then
    U.Debug("loot: no readable position after drag")
    return
  end
  U.SavePosition(lw.POSITION_ID, placed.point, placed.relativePoint,
                 placed.x, placed.y)
end

function lw.BuildDragHandle(chrome)
  local t = lw.Token()
  local handle = CreateFrame("Button", nil, chrome)
  handle:SetPoint("TOPLEFT", chrome, "TOPLEFT", t.drag.inset, -t.drag.inset)
  handle:SetPoint("TOPRIGHT", chrome, "TOPRIGHT",
                  -(t.close.size + t.drag.closeGap), -t.drag.inset)
  handle:SetHeight(t.header - t.drag.inset)
  pcall(handle.SetFrameLevel, handle, chrome:GetFrameLevel() + 1)
  handle:RegisterForDrag("LeftButton")
  pcall(handle.EnableMouse, handle, true)
  handle:SetScript("OnDragStart", lw.StartDrag)
  handle:SetScript("OnDragStop", lw.StopDrag)
  lw.dragHandle = handle
end

-- ---------------------------------------------------------------------------
-- Item tooltip beside the window (user request, 2026-09-19)
--
-- The row's own OnEnter owns and fills GameTooltip (ANCHOR_RIGHT, over the
-- window's right edge); afterwards it is moved so its top-right meets the
-- window's left edge, level with the hovered row. Only when that fits on
-- screen -- otherwise the native placement stays. Widths are compared in
-- UIParent space through effective scales, never by differencing scaled edges
-- (knowledge.json / frames.scaled_frame_edge_coordinates_mixed_space).
--
-- The tooltip module records that native code can re-place a tooltip after
-- Lua runs (tooltip.default_corner_mover), so while the row stays hovered the
-- point is re-checked every frame and re-applied only when it has changed.
-- ---------------------------------------------------------------------------
function lw.TooltipFits(tooltip)
  local ok, left, chromeScale, tipWidth, tipScale, rootScale, rootLeft = pcall(function()
    return lw.chrome:GetLeft(), lw.chrome:GetEffectiveScale(),
           tooltip:GetWidth(), tooltip:GetEffectiveScale(),
           UIParent:GetEffectiveScale(), UIParent:GetLeft()
  end)
  if not ok or type(left) ~= "number" or type(tipWidth) ~= "number" or
     type(chromeScale) ~= "number" or type(tipScale) ~= "number" or
     type(rootScale) ~= "number" or rootScale <= 0 then return false end
  local gap = lw.Token().tooltip.gap
  local room = (left * chromeScale) / rootScale - (rootLeft or 0)
  local need = (tipWidth * tipScale) / rootScale + gap
  return room >= need
end

function lw.PlaceTooltip(index)
  local tooltip = U.G("GameTooltip")
  if not tooltip or not lw.chrome or not lw.geo or not lw.Shown(tooltip) then return false end
  if not lw.TooltipFits(tooltip) then return false end

  local g, t = lw.geo, lw.Token()
  local rows = g.rowBottoms[index] and index or 1
  local y = -((g.rowBottoms[rows] - g.buttonSize) - (g.rowsTop - t.header))
  local x = -t.tooltip.gap
  local point, relative, relativePoint, px, py = U.GetFramePoint(tooltip)
  if point == "TOPRIGHT" and relative == lw.chrome and relativePoint == "TOPLEFT" and
     px == x and py == y then return false end

  local placed = pcall(function()
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPRIGHT", lw.chrome, "TOPLEFT", x, y)
  end)
  return placed
end

function lw.TooltipTick()
  if not lw.hoverIndex then
    U.UnregisterUpdate("lootdesign.tooltip")
    return
  end
  -- Compare tooltips are placed against GameTooltip; follow it when it moves.
  if lw.PlaceTooltip(lw.hoverIndex) and type(U.PositionItemCompare) == "function" then
    pcall(U.PositionItemCompare)
  end
end

-- Called from modules/loot.lua's row OnEnter, before the price and compare
-- readouts so they are laid out against the moved tooltip.
function U.ModernWowLootTooltip(index)
  if not lw.built or not lw.Wanted() then return end
  lw.hoverIndex = index
  lw.PlaceTooltip(index)
  U.RegisterUpdate("lootdesign.tooltip", 0, lw.TooltipTick)
end

function U.ModernWowLootTooltipDone()
  lw.hoverIndex = nil
  U.UnregisterUpdate("lootdesign.tooltip")
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
-- Row geometry, read once from the live window. Both paths need it: the design
-- places its chrome from it and the animation places a looted item's slide over
-- the row it left, so it is measured even when no chrome is drawn.
function lw.EnsureGeo(frame)
  if lw.geo then return true end
  local g = lw.Measure(frame)
  if not g then
    lw.failed = true
    U.Error("loot window: row geometry unreadable; native window kept")
    return false
  end
  lw.geo = g
  return true
end

function lw.Build(frame)
  if not lw.EnsureGeo(frame) then return end
  local g = lw.geo
  -- One branch, into a complete drawing path each (rules/unreal-ui-design.md).
  if lw.Style() == "modern" then
    lw.BuildFlatChrome(frame, g)
  else
    lw.BuildChrome(frame, g)
  end
  lw.BuildDragHandle(lw.chrome)
  local i
  for i = 1, g.count do lw.DressRow(i, g.buttonSize) end
  lw.built = true
end

function lw.HookPaging()
  if lw.hooked then return end
  lw.hooked = true
  local names = { "LootFrameUpButton", "LootFrameDownButton" }
  local i
  for i = 1, 2 do
    U.PostHookScript(U.G(names[i]), "OnClick", function()
      U.DeferOnce("lootdesign.refresh", lw.Refresh)
    end)
  end
end

-- One frame after LOOT_OPENED, so the stock update has laid the rows out.
--
-- Split by gate: the geometry is read in every theme, because the animation
-- needs it, while the position store, the strip, the chrome and the row
-- dressing belong to the design and run only when it is on.
function lw.Apply()
  if lw.failed then return end
  local frame = U.G("LootFrame")
  if not frame then return end
  local ok, visible = pcall(frame.IsVisible, frame)
  if not ok or not visible then return end

  if not lw.Wanted() then
    lw.EnsureGeo(frame)
    return
  end

  lw.ApplyPosition(frame)
  lw.Strip(frame)
  if not lw.built then lw.Build(frame) end
  if not lw.built then return end
  lw.HookPaging()
  lw.Refresh()
end

-- ---------------------------------------------------------------------------
-- Opening animation (user request, 2026-09-19)
--
-- Alpha only, through the shared easer (core/easing.lua): the window fades in
-- with an ease-out, then each row follows after a short stagger. Nothing is
-- moved -- the rows are native buttons and stay anchored where the client
-- put them -- and alpha never affects their clicks. LOOT_CLOSED snaps every
-- alpha back to 1 so a window closed mid-fade never reopens translucent.
--
-- Design-free, so this runs under every theme: it reads no token but the shared
-- timings and touches nothing but alpha on frames the client owns.
-- ---------------------------------------------------------------------------
function lw.Animate()
  local a = lw.Anim().anim
  local frame = U.G("LootFrame")
  if not a or not frame or type(U.StartEasing) ~= "function" then return end

  pcall(frame.SetAlpha, frame, 0)
  U.StartEasing("loot.window", { from = 0, to = 1, duration = a.window,
    ease = U.EaseOutCubic,
    onUpdate = function(value) frame:SetAlpha(value) end })

  local count = type(U.LootRowCount) == "function" and U.LootRowCount() or 0
  local i
  for i = 1, count do
    local button = U.G("LootButton" .. i)
    if button then
      local delay = a.rowDelay + (i - 1) * a.stagger
      local total = delay + a.row
      pcall(button.SetAlpha, button, 0)
      U.StartEasing("loot.row" .. i, { from = 0, to = 1, duration = total,
        ease = function(progress)
          local local01 = (progress * total - delay) / a.row
          if local01 <= 0 then return 0 end
          return U.EaseOutCubic(local01)
        end,
        onUpdate = function(value) button:SetAlpha(value) end })
    end
  end
end

function lw.ResetAlpha()
  lw.hiddenRows = {}
  if type(U.StopEasing) == "function" then U.StopEasing("loot.window") end
  local frame = U.G("LootFrame")
  if frame then pcall(frame.SetAlpha, frame, 1) end
  local count = type(U.LootRowCount) == "function" and U.LootRowCount() or 0
  local i
  for i = 1, count do
    if type(U.StopEasing) == "function" then U.StopEasing("loot.row" .. i) end
    local button = U.G("LootButton" .. i)
    if button then pcall(button.SetAlpha, button, 1) end
  end
end

function U.ModernWowLootOpened()
  if not lw.AnimWanted() then return end
  lw.shown = {}
  lw.hiddenRows = {}
  lw.ghostNext = 0
  -- Stored position and slot snapshot now, not a frame later, so ghosts of an
  -- all-at-once loot start from the right place with the right items.
  local frame = U.G("LootFrame")
  if frame and lw.built then lw.ApplyPosition(frame) end
  lw.SnapshotAll()
  lw.Animate()
  U.DeferOnce("lootdesign.apply", lw.Apply)
end

function U.ModernWowLootClosed()
  if lw.Wanted() then U.ModernWowLootTooltipDone() end
  if not lw.AnimWanted() then return end
  lw.ResetAlpha()
end

function U.ModernWowLootChanged(slot)
  if not lw.AnimWanted() then return end
  lw.LaunchGhost(tonumber(slot))
  -- The refresh redraws the dressed rows and brings back the one the slide
  -- covered. With no chrome there is nothing to redraw, but the row still has
  -- to come back once the client has given it another item, so that half runs
  -- on its own.
  if lw.built then
    U.DeferOnce("lootdesign.refresh", lw.Refresh)
  else
    U.DeferOnce("lootdesign.rows", lw.RestoreRows)
  end
end

function U.ModernWowLootActive()
  return lw.built
end

-- The frame that owns this path's window rect. modules/loot.lua hands it to
-- modules/tooltip.lua, so the cursor-follow world tooltip can step around the
-- window instead of covering it. Handed over for immediate measurement only
-- and never retained (rules/unreal-ui.md, native widget ownership boundaries).
function U.ModernWowLootChrome()
  if not lw.built or not lw.Wanted() then return nil end
  if not lw.chrome or not lw.Shown(lw.chrome) then return nil end
  return lw.chrome
end
