-- unrealUI :: modules/spellbookmodernwow.lua
--
-- The Spellbook's complete `modern-wow` drawing path: the Character window's
-- paperdoll housing, the Dragonflight book pages inside its recess, the
-- Spellbook-Parts slot frames on every spell button, the skill-line side tabs,
-- the themed bottom tabs and the red close button.
--
-- modules/spellbook.lua chooses this path in its own OnEnable, before any flat
-- styling, and falls back to its Modern skin when the theme or the `spellbook`
-- surface (modules/modernwow.lua) is off. That module keeps every behaviour it
-- owns -- the book tabs, the highest-rank filter and the action-bar hint -- and
-- only asks this file where the two toggles go.
--
-- Everything stays on the client's own widgets: spell buttons, tabs, arrows
-- and their click, drag, tooltip and checked handling are untouched. Placement
-- is numeric against SpellBookFrame itself, never against a native child, and
-- the window art is drawn as that frame's own regions, beneath every child
-- widget, so nothing here takes the mouse (rules/unreal-ui.md, native widget
-- ownership).
--
-- Geometry comes from M.modernWow.spellBook, measured off the art.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local book = {
  THEME = "modern-wow",
  SURFACE = "spellbook",
  built = false,
  frame = nil,
  layout = nil,
  buttons = {},
}

function book.Token()
  return M.modernWow.spellBook
end

function book.Dimension(object, method)
  if not object or not object[method] then return 0 end
  local ok, value = pcall(object[method], object)
  return (ok and tonumber(value)) or 0
end

function book.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function book.Texture(parent, layer, path, u1, u2, v1, v2)
  if not parent or not parent.CreateTexture then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  if u1 then pcall(texture.SetTexCoord, texture, u1, u2, v1, v2) end
  return texture
end

-- Places a texture at a TOPLEFT offset of the window, in window units.
function book.Place(texture, left, top, width, height)
  if not texture then return end
  pcall(function()
    texture:ClearAllPoints()
    texture:SetWidth(width)
    texture:SetHeight(height)
    texture:SetPoint("TOPLEFT", book.frame, "TOPLEFT", left, -top)
  end)
end

-- ---------------------------------------------------------------------------
-- Geometry
--
-- Solved once: the page is scaled to the recess height, and the window grows
-- by whatever that page is wider than the stock recess. Rounded to a whole
-- unit so the stretched housing columns and the page edge land on the same
-- pixel; the page absorbs that fraction of a unit, not the housing.
-- ---------------------------------------------------------------------------
function book.Solve()
  local t = book.Token()
  local recess = t.recess
  local pageHeight = recess.bottom - recess.top
  local ky = pageHeight / t.page.height
  local natural = (t.page.width + t.page.edgeWidth) * ky
  local extra = math.floor(natural - (recess.right - recess.left) + 0.5)
  if extra < 0 then extra = 0 end

  local pageWidth = recess.right - recess.left + extra
  return {
    extra = extra,
    width = t.design.width + extra,
    height = t.design.height,
    pageLeft = recess.left,
    pageTop = recess.top,
    pageHeight = pageHeight,
    kx = pageWidth / (t.page.width + t.page.edgeWidth),
    ky = ky,
  }
end

-- A point in page-art texels, as a TOPLEFT offset of the window.
function book.PagePoint(x, y)
  local L = book.layout
  return L.pageLeft + x * L.kx, L.pageTop + y * L.ky
end

-- ---------------------------------------------------------------------------
-- Housing and pages
-- ---------------------------------------------------------------------------

-- One quadrant row of the housing. The left quadrant is drawn 1:1; the right
-- one is cut at the plain stretch columns, so only that run takes the extra
-- width.
function book.HousingRow(chrome, leftPath, rightPath, top)
  local t = book.Token()
  local extra = book.layout.extra
  local half = t.design.height / 2
  local seam = 256
  local rightCanvas = t.design.width - seam
  local s1 = t.stretch.left - seam
  local s2 = t.stretch.right - seam

  book.Place(book.Texture(chrome, "BACKGROUND", leftPath),
             0, top, seam, half)
  book.Place(book.Texture(chrome, "BACKGROUND", rightPath,
                          0, s1 / rightCanvas, 0, 1),
             seam, top, s1, half)
  book.Place(book.Texture(chrome, "BACKGROUND", rightPath,
                          s1 / rightCanvas, s2 / rightCanvas, 0, 1),
             seam + s1, top, s2 - s1 + extra, half)
  book.Place(book.Texture(chrome, "BACKGROUND", rightPath,
                          s2 / rightCanvas, 1, 0, 1),
             seam + s2 + extra, top, rightCanvas - s2, half)
end

function book.BuildChrome(frame)
  local t = book.Token()
  local L = book.layout
  local tex = M.modernWow.texture

  -- Drawn on SpellBookFrame itself, not on a child frame. A child sat at the
  -- same frame level as the spell buttons whenever the window's own level was
  -- too low to go one below (USER_CONFIRMED_INGAME, 2026-09-13: the pages drew
  -- over every icon, spell name, the title and the page number). A window's
  -- own regions always draw beneath its children, whatever its level.
  local chrome = frame

  book.HousingRow(chrome, tex.panelTopLeft, tex.panelTopRight, 0)
  book.HousingRow(chrome, tex.panelBottomLeft, tex.panelBottomRight,
                  t.design.height / 2)

  -- Pages above the housing: BORDER over BACKGROUND, so the order does not
  -- depend on creation order within one layer.
  -- Kept, so the Professions page can swap its own art into the same two
  -- regions (U.ModernWowSpellBookSetPageArt).
  local vBottom = t.page.height / t.page.canvas
  local page1Width = t.page.width * L.kx
  book.page1 = book.Texture(chrome, "BORDER", t.texture.page1, 0, 1, 0, vBottom)
  book.Place(book.page1, L.pageLeft, L.pageTop, page1Width, L.pageHeight)
  book.page2 = book.Texture(chrome, "BORDER", t.texture.page2,
                            0, t.page.edgeWidth / t.page.edgeCanvas, 0, vBottom)
  book.Place(book.page2, L.pageLeft + page1Width, L.pageTop,
             t.page.edgeWidth * L.kx, L.pageHeight)

  -- The class portrait in the housing's gold ring, as on the Character
  -- window. A token with no atlas cell draws no portrait.
  local ok, _, class = pcall(UnitClass, "player")
  local cell = ok and class and M.modernWow.classCell[class]
  if cell then
    local ring = t.ring
    book.portrait = book.Texture(chrome, "ARTWORK", tex.classPortraits,
                                 cell[1], cell[2], cell[3], cell[4])
    book.Place(book.portrait, ring.left + ring.inset, ring.top + ring.inset,
               ring.size - 2 * ring.inset, ring.size - 2 * ring.inset)
  end

  return chrome
end

-- ---------------------------------------------------------------------------
-- Header, page number and arrows
-- ---------------------------------------------------------------------------
function book.PlaceWindowControls()
  local t = book.Token()
  local L = book.layout
  local frame = book.frame
  local barRight = t.headerBar.right + L.extra
  local barY = (t.headerBar.top + t.headerBar.bottom) / 2

  local title = U.G("SpellBookTitleText")
  if title then
    pcall(function()
      title:ClearAllPoints()
      title:SetPoint("CENTER", frame, "TOPLEFT",
                     (t.headerBar.left + barRight) / 2, -barY)
    end)
    -- Same frame as the housing and pages now, so it is lifted above them.
    pcall(title.SetDrawLayer, title, "OVERLAY")
    U.SetStockFont(title, M.fontSize.large, t.titleColor)
  end

  local close = U.G("SpellBookCloseButton")
  if close then
    pcall(function()
      close:SetWidth(t.close.size)
      close:SetHeight(t.close.size)
      close:ClearAllPoints()
      close:SetPoint("CENTER", frame, "TOPLEFT", barRight - t.close.right, -barY)
    end)
  end

  local nav = t.nav
  local x, y = book.PagePoint(nav.prevX, nav.y)
  local prev = U.G("SpellBookPrevPageButton")
  if prev then
    pcall(function()
      prev:ClearAllPoints()
      prev:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    end)
  end
  x, y = book.PagePoint(nav.nextX, nav.y)
  local nextButton = U.G("SpellBookNextPageButton")
  if nextButton then
    pcall(function()
      nextButton:ClearAllPoints()
      nextButton:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    end)
  end

  x, y = book.PagePoint(nav.textX, nav.y)
  local pageText = U.G("SpellBookPageText")
  if pageText then
    pcall(function()
      pageText:ClearAllPoints()
      pageText:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
      pageText:SetJustifyH("CENTER")
    end)
    pcall(pageText.SetDrawLayer, pageText, "OVERLAY")
    -- Shadow-free through U.SetFont's private font record, the verified route
    -- (knowledge.json / text.shadow_session_findings), then cleared on the
    -- string as well. U.SetStockFont would re-apply the shared shadow.
    local inherited = U.G("GameFontNormal")
    if inherited and pageText.SetFontObject then
      pcall(pageText.SetFontObject, pageText, inherited)
    end
    U.SetFont(pageText, M.fontSize.normal, nil, nil, true)
    pcall(pageText.SetTextColor, pageText, M.Unpack(t.pageTextColor))
    U.ClearTextShadow(pageText)
  end

  book.ClearLabelShadows(prev)
  book.ClearLabelShadows(nextButton)
end

-- The "Prev" / "Next" captions are unnamed FontStrings of the arrow buttons,
-- so they are reached by walking the two named buttons. A walked region is a
-- wrapper (knowledge.json / widgets.region_walk_wrapper_lacks_setters) that
-- may lack writers; each call is guarded, and the button's own font string is
-- tried first in case the caption is that. Returns how many were cleared, for
-- /uui sb look.
function book.ClearLabelShadows(button)
  if not button then return 0 end
  local cleared = 0

  if button.GetFontString then
    local ok, text = pcall(button.GetFontString, button)
    if ok and text and U.ClearTextShadow(text) then cleared = cleared + 1 end
  end

  if button.GetRegions then
    local ok, regions = pcall(function() return { button:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        local kindOk, kind = false, nil
        if region and region.GetObjectType then
          kindOk, kind = pcall(region.GetObjectType, region)
        end
        if kindOk and kind == "FontString" and U.ClearTextShadow(region) then
          cleared = cleared + 1
        end
      end
    end
  end
  return cleared
end

-- ---------------------------------------------------------------------------
-- Spell buttons
--
-- Three owned textures per button from Spellbook-Parts: the slot background
-- under the icon, the gold slot frame over it, and the soft shadow that seats
-- the name on the parchment. The client's own quick-slot frame and slot
-- background are the stock chrome these replace; the icon, highlight, pushed,
-- checked and autocast regions stay the client's.
--
-- An empty slot hides the three textures with its icon, read back after every
-- SpellButton_UpdateButton (the one repaint path on this client, knowledge.json
-- / spellbook.rank_filter_redraw_requires_spellbutton_updatebutton).
-- ---------------------------------------------------------------------------
function book.PartTexture(button, layer, cell)
  local parts = book.Token().parts
  return book.Texture(button, layer, book.Token().texture.parts,
                      cell.left / parts.atlas, cell.right / parts.atlas,
                      cell.top / parts.atlas, cell.bottom / parts.atlas)
end

-- Hides the client's own texture regions on `object` and nothing of this
-- theme's, optionally only those whose path contains `match`.
--
-- Deliberately NOT a keep-table strip (U.StripTextures). GetRegions returns a
-- fresh wrapper per region on this client (knowledge.json /
-- widgets.region_walk_wrapper_lacks_setters), so a wrapper never equals the
-- texture CreateTexture or a named global handed back, and every "kept"
-- region was hidden anyway (USER_CONFIRMED_INGAME, 2026-09-13: first the spell
-- icons and slot frames, then after an OnShow the whole book art vanished).
-- Regions are told apart by readers instead: the path they draw (separators
-- normalised to "\", since the client may report either) or, when `name` is
-- given, their own GetName(). A region whose path cannot be read is left
-- alone unless its name matches.
function book.StripForeign(object, match, name)
  if not object or not object.GetRegions then return end
  local ok, regions = pcall(function() return { object:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return end

  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local typeOk, kind = false, nil
    if region and region.GetObjectType then
      typeOk, kind = pcall(region.GetObjectType, region)
    end
    if typeOk and kind == "Texture" then
      local hide = false

      if name and region.GetName then
        local nameOk, own = pcall(region.GetName, region)
        hide = nameOk and own == name
      end

      if not hide and region.GetTexture then
        local pathOk, path = pcall(region.GetTexture, region)
        if pathOk and type(path) == "string" and path ~= "" then
          path = string.gsub(string.lower(path), "/", "\\")
          local ours = string.find(path, "unrealui", 1, true)
          hide = not ours and (not match or
                               string.find(path, match, 1, true) ~= nil)
        end
      end

      if hide then U.HideRegion(region) end
    end
  end
end

function book.StripSpellButton(index, state)
  local button = U.G("SpellButton" .. index)
  if not button then return end

  -- No region walk here at all: the icon, highlight, pushed, checked and
  -- autocast art are the client's and stay. The stock quick-slot square is a
  -- button state texture (USER_CONFIRMED_INGAME, 2026-09-13: black on passive
  -- spells) and is cleared the way core/stockui.lua clears button faces;
  -- SpellButton_UpdateButton only recolours it afterwards.
  --
  -- The slot's stock backing is the one other stock piece: a fixed-size
  -- texture hung off the button's TOPLEFT, so once the button shrank it showed
  -- as a brown bevelled square below and right of every icon, empty slots
  -- included (USER_CONFIRMED_INGAME, 2026-09-13). Matching its folder alone did
  -- not catch it, so it is hidden by its template name as well -- through the
  -- named global and through a name read on the walked wrapper, since either
  -- one alone may not reach the drawing region here.
  local backing = "SpellButton" .. index .. "Background"
  U.HideRegion(U.G(backing))
  book.StripForeign(button, "interface\\spellbook\\", backing)
  if button.GetNormalTexture then
    local ok, normal = pcall(button.GetNormalTexture, button)
    if ok and normal then U.HideRegion(normal) end
  end
  U.HideRegion(U.G("SpellButton" .. index .. "NormalTexture"))
  if button.SetNormalTexture and not pcall(button.SetNormalTexture, button, "") then
    pcall(button.SetNormalTexture, button, nil)
  end
end

function book.DressSpellButton(index)
  local button = U.G("SpellButton" .. index)
  if not button then return end

  local t = book.Token()
  local grid = t.grid
  local L = book.layout
  local state = book.buttons[index]

  if not state then
    state = {
      background = book.PartTexture(button, "BACKGROUND",
                                    t.parts.slotBackground),
      shadow = book.PartTexture(button, "BACKGROUND", t.parts.nameShadow),
      frame = book.PartTexture(button, "OVERLAY", t.parts.slotFrame),
    }
    if not state.background or not state.shadow or not state.frame then
      error("spell button " .. index .. " art could not be created")
    end
    state.regions = { state.background, state.frame, state.shadow }
    book.buttons[index] = state
  end

  local column = index - 1 - math.floor((index - 1) / grid.columns) * grid.columns
  local row = math.floor((index - 1) / grid.columns)
  local x, y = book.PagePoint(grid.left + column * grid.columnPitch,
                              grid.top + row * grid.rowPitch)
  -- The Professions page places the same native buttons in its own rows
  -- while it is shown; nil means the spell grid.
  local placed = book.placer and book.placer(index)
  if placed then x, y = placed.x, placed.y end

  -- The Professions page seats the name on its own plate
  -- (placed.nameFrame) instead of the spell page's name shadow; the one not
  -- in use is hidden and left out of the regions SyncSpellButton shows.
  local plate = placed and placed.nameFrame
  if plate and not state.nameFrame then
    state.nameFrame = book.Texture(button, "BACKGROUND", plate.path,
                                   plate.u1, plate.u2, plate.v1, plate.v2)
  end
  local seat = state.shadow
  if plate and state.nameFrame then
    seat = state.nameFrame
    pcall(function()
      seat:ClearAllPoints()
      seat:SetWidth(plate.width)
      seat:SetHeight(plate.height)
      seat:SetPoint("LEFT", button, "RIGHT", plate.x, 0)
      seat:SetAlpha(plate.alpha)
    end)
    pcall(state.shadow.Hide, state.shadow)
  elseif state.nameFrame then
    pcall(state.nameFrame.Hide, state.nameFrame)
  end
  -- The Professions page (placed.plainSlot) draws no slot art: as
  -- DragonflightUI's DFProfessionButtonTemplate does, the uncropped icon's
  -- own edge is the border.
  if placed and placed.plainSlot then
    pcall(state.background.Hide, state.background)
    pcall(state.frame.Hide, state.frame)
    state.regions = { seat }
  else
    state.regions = { state.background, state.frame, seat }
  end
  -- The not-on-bar pulse uses this addon-owned texture as its horizontal
  -- geometry reference. It must cover exactly the name run it sits behind.
  button.uuiModernWowNameShadow = seat
  pcall(function()
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", book.frame, "TOPLEFT", x, -y)
  end)

  -- The button is drawn at `grid.buttonScale` of the client's own size. Its
  -- native size (and that of the fixed-size autocast ring, which does not
  -- follow the button) is read once, before the first resize, so every later
  -- pass applies the same scale instead of compounding it. The name keeps its
  -- font size: the button is resized, not SetScale'd. The cooldown Model is
  -- left alone; it draws nothing on this client
  -- (knowledge.json / cooldown.model_swipe_not_rendered).
  if not state.native then
    local width = book.Dimension(button, "GetWidth")
    if width <= 0 then width = t.parts.designButton end
    state.native = { size = width, children = {} }
    local names = { "AutoCastable" }
    local i
    for i = 1, table.getn(names) do
      local child = U.G("SpellButton" .. index .. names[i])
      local w = book.Dimension(child, "GetWidth")
      local h = book.Dimension(child, "GetHeight")
      if child and w > 0 and h > 0 then
        table.insert(state.native.children, { name = names[i], w = w, h = h })
      end
    end
  end

  local size = state.native.size * grid.buttonScale
  if placed then size = placed.size end
  local childScale = size / state.native.size
  pcall(function()
    button:SetWidth(size)
    button:SetHeight(size)
  end)
  local c
  for c = 1, table.getn(state.native.children) do
    local entry = state.native.children[c]
    local child = U.G("SpellButton" .. index .. entry.name)
    if child then
      pcall(child.SetWidth, child, entry.w * childScale)
      pcall(child.SetHeight, child, entry.h * childScale)
    end
  end

  local k = size / t.parts.designButton
  local textWidth = grid.columnPitch * L.kx - size - grid.textGap -
                    grid.textInset
  if placed then textWidth = placed.textWidth end

  local slot = t.parts.slotBackground
  pcall(function()
    state.background:ClearAllPoints()
    state.background:SetWidth(slot.width * k)
    state.background:SetHeight(slot.height * k)
    state.background:SetPoint("CENTER", button, "CENTER", 0, 0)
  end)

  local rim = t.parts.slotFrame
  pcall(function()
    state.frame:ClearAllPoints()
    state.frame:SetWidth(rim.width * k)
    state.frame:SetHeight(rim.height * k)
    state.frame:SetPoint("CENTER", button, "CENTER", rim.x * k, 0)
  end)

  local shadow = t.parts.nameShadow
  pcall(function()
    state.shadow:ClearAllPoints()
    state.shadow:SetWidth((textWidth + shadow.pad) * shadow.widthScale)
    state.shadow:SetHeight(shadow.height * k)
    state.shadow:SetPoint("TOPLEFT", button, "TOPRIGHT", shadow.x * k,
                          shadow.y * k)
  end)

  local name = U.G("SpellButton" .. index .. "SpellName")
  if name then
    pcall(function()
      name:ClearAllPoints()
      name:SetPoint("TOPLEFT", button, "TOPRIGHT", grid.textGap, grid.nameY)
      name:SetWidth(textWidth)
      name:SetJustifyH("LEFT")
    end)
  end
  local sub = U.G("SpellButton" .. index .. "SubSpellName")
  if sub and name then
    pcall(function()
      sub:ClearAllPoints()
      sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, grid.subY)
      sub:SetWidth(textWidth)
      sub:SetJustifyH("LEFT")
    end)
  end
  -- Spell name and rank print on the parchment without a drop shadow (user
  -- request, 2026-09-13). The client's update only recolours these strings,
  -- and this pass also runs on every show.
  if name then U.ClearTextShadow(name) end
  if sub then U.ClearTextShadow(sub) end

  book.StripSpellButton(index, state)
  book.SyncSpellButton(index)
end

function book.SyncSpellButton(index)
  local state = book.buttons[index]
  if not state then return end

  local icon = U.G("SpellButton" .. index .. "IconTexture")
  local filled = book.Shown(icon)
  -- An icon is only ever the client's to show or hide. Its alpha is restored
  -- because an earlier strip on this client zeroed it, and the client's own
  -- update never resets alpha (core/stockui.lua, U.RestoreContentIcon).
  if filled then pcall(icon.SetAlpha, icon, 1) end

  -- The name shadow is a BACKGROUND texture on this same button, and the
  -- racial/passive names rendered under it (user report, 2026-09-13). The
  -- name and rank are lifted to OVERLAY after every client update so no
  -- spell type can leave them below the shadow; they never overlap the
  -- OVERLAY slot frame.
  local name = U.G("SpellButton" .. index .. "SpellName")
  local sub = U.G("SpellButton" .. index .. "SubSpellName")
  if name then pcall(name.SetDrawLayer, name, "OVERLAY") end
  if sub then pcall(sub.SetDrawLayer, sub, "OVERLAY") end

  -- Passive and racial passive spells look exactly like the rest: the
  -- client's update dims their name and swaps in a passive hover glow, so
  -- both are put back to the active-spell look after every update.
  local t = book.Token()
  if name then
    pcall(name.SetTextColor, name, M.Unpack(t.spellNameColor))
  end
  -- The Professions page draws the rank line in its own colour; the client's
  -- update restores its own once that page gives the button back.
  local placed = book.placer and book.placer(index)
  if sub and placed and placed.subColor then
    pcall(sub.SetTextColor, sub, M.Unpack(placed.subColor))
  end
  local highlight = U.G("SpellButton" .. index .. "Highlight")
  if highlight then
    pcall(highlight.SetTexture, highlight, t.spellHighlight)
  end

  local regions = state.regions
  local i
  for i = 1, table.getn(regions) do
    if filled then
      pcall(regions[i].Show, regions[i])
    else
      pcall(regions[i].Hide, regions[i])
    end
  end
end

function book.SpellCount()
  return tonumber(U.G("SPELLS_PER_PAGE")) or 12
end

function book.OnSpellButtonUpdate()
  local button = U.G("this")
  if not button then return end
  local i
  for i = 1, book.SpellCount() do
    if U.G("SpellButton" .. i) == button then
      book.SyncSpellButton(i)
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- "Not on action bars" glow
--
-- modules/spellbook.lua still decides which spell is marked; under this theme
-- it hands the verdict here instead of painting its flat accent outline. The
-- mark is the Spellbook-Parts burst glow, centred on the button and pulsing
-- the way the player frame's rest/combat halo does (modules/modernwow.lua,
-- mw.PlayerFXTick): additive, alpha ping-ponged through U.EaseInOutCubic,
-- elapsed read from GetTime because OnUpdate passes no delta here
-- (knowledge.json / scripts.onupdate_elapsed_only_via_arg1).
--
-- ARTWORK on the button: above the icon and name shadow, below the slot frame
-- and the name and rank, which SyncSpellButton lifts to OVERLAY, so the
-- streak never covers the text it runs behind. The ticker runs only while a
-- glow is lit and the window is open; reopening the book repaints every
-- button, which re-lights it.
-- ---------------------------------------------------------------------------
book.glow = {
  updateId = "modernwow.spellbook.barglow",
  lit = {},
  count = 0,
  running = false,
  pulseTime = 0,
  alpha = 0,
}

function book.GlowNow()
  local ok, value = pcall(U.G("GetTime"))
  if ok and type(value) == "number" then return value end
  return nil
end

function book.GlowStop()
  local g = book.glow
  if not g.running then return end
  g.running = false
  g.lastTick = nil
  U.UnregisterUpdate(g.updateId)
end

function book.GlowTick()
  local g = book.glow
  if g.count <= 0 or not book.Shown(book.frame) then
    book.GlowStop()
    return
  end

  local now = book.GlowNow()
  if not now then return end
  local elapsed = now - (g.lastTick or now)
  g.lastTick = now
  if elapsed < 0 then elapsed = 0 end
  if elapsed > 0.25 then elapsed = 0.25 end

  local cfg = book.Token().barGlowPulse
  g.pulseTime = math.mod(g.pulseTime + elapsed, cfg.pulsePeriod)
  local progress = g.pulseTime / cfg.pulsePeriod
  local swing = progress < 0.5 and progress * 2 or (1 - progress) * 2
  g.alpha = cfg.alphaMin + (cfg.alphaMax - cfg.alphaMin) * U.EaseInOutCubic(swing)

  local glow
  for glow in pairs(g.lit) do
    pcall(glow.burst.SetAlpha, glow.burst, g.alpha)
    pcall(glow.streak.SetAlpha, glow.streak, g.alpha)
  end
end

function book.GlowTexture(button)
  if button.uuiModernWowBarGlow then return button.uuiModernWowBarGlow end
  local cell = book.Token().parts.barGlow
  local burst = book.PartTexture(button, "ARTWORK", cell.burst)
  local streak = book.PartTexture(button, "ARTWORK", cell.streak)
  if not burst or not streak then
    if burst then pcall(burst.Hide, burst) end
    if streak then pcall(streak.Hide, streak) end
    return nil
  end
  pcall(burst.SetBlendMode, burst, "ADD")
  pcall(streak.SetBlendMode, streak, "ADD")
  pcall(burst.Hide, burst)
  pcall(streak.Hide, streak)
  local glow = { burst = burst, streak = streak }
  button.uuiModernWowBarGlow = glow
  return glow
end

-- Sized from the button's live width on every call, since DressSpellButton
-- owns that size and may re-apply it. The burst's rim is laid over the slot
-- frame's square, while the separately cropped streak is vertically aligned
-- with the name shadow and takes its exact live width. The atlas authored them
-- side by side, but one shared vertical anchor cannot align both pieces in
-- this compact layout.
function book.PlaceGlow(button, glow)
  local t = book.Token()
  local cell = t.parts.barGlow
  local rim = t.parts.slotFrame
  local k = book.Dimension(button, "GetWidth") / t.parts.designButton
  if k <= 0 then k = t.grid.buttonScale end

  local slotSq, glowSq = rim.square, cell.square
  local kg = k * (slotSq.right - slotSq.left) / (glowSq.right - glowSq.left)

  -- Slot square centre from the button centre (y up), then the glow region's
  -- centre from its own rim centre.
  local sx = ((slotSq.left + slotSq.right) / 2 -
              (rim.left + rim.right) / 2 + rim.x) * k
  local sy = ((rim.top + rim.bottom) / 2 -
              (slotSq.top + slotSq.bottom) / 2) * k
  local burst = cell.burst
  local bx = ((burst.left + burst.right) / 2 -
              (glowSq.left + glowSq.right) / 2) * kg
  local by = ((glowSq.top + glowSq.bottom) / 2 -
              (burst.top + burst.bottom) / 2) * kg
  local streak = cell.streak
  local tx = ((streak.left + streak.right) / 2 -
              (glowSq.left + glowSq.right) / 2) * kg
  local nameShadow = button.uuiModernWowNameShadow
  local shadowWidth = book.Dimension(nameShadow, "GetWidth")
  local streakWidth = shadowWidth * streak.widthScale
  if streakWidth <= 0 then
    streakWidth = (streak.right - streak.left) * kg
  end

  pcall(function()
    glow.burst:ClearAllPoints()
    glow.burst:SetWidth((burst.right - burst.left) * kg)
    glow.burst:SetHeight((burst.bottom - burst.top) * kg)
    glow.burst:SetPoint("CENTER", button, "CENTER", sx + bx, sy + by)

    glow.streak:ClearAllPoints()
    glow.streak:SetWidth(streakWidth)
    glow.streak:SetHeight((streak.bottom - streak.top) * kg)
    if nameShadow and shadowWidth > 0 then
      glow.streak:SetPoint("CENTER", nameShadow, "CENTER", 0, streak.y * k)
    else
      glow.streak:SetPoint("CENTER", button, "CENTER", sx + tx,
                           streak.y * k)
    end
  end)
end

-- Returns true when this theme drew (or cleared) the mark, so the caller
-- leaves its flat outline clear; false when this path is not drawn or the
-- glow could not be created, so the flat outline still shows the verdict.
function U.ModernWowSpellBookBarGlow(button, wanted)
  if not book.built or not button then return false end
  local g = book.glow

  if not wanted then
    local glow = button.uuiModernWowBarGlow
    if glow and g.lit[glow] then
      g.lit[glow] = nil
      g.count = g.count - 1
      pcall(glow.burst.Hide, glow.burst)
      pcall(glow.streak.Hide, glow.streak)
    end
    return true
  end

  local glow = book.GlowTexture(button)
  if not glow then return false end
  book.PlaceGlow(button, glow)

  if not g.lit[glow] then
    g.lit[glow] = true
    g.count = g.count + 1
    -- Joins the running phase so every lit spell breathes together.
    local alpha = g.running and g.alpha or
                  book.Token().barGlowPulse.alphaMin
    pcall(glow.burst.SetAlpha, glow.burst, alpha)
    pcall(glow.streak.SetAlpha, glow.streak, alpha)
    pcall(glow.burst.Show, glow.burst)
    pcall(glow.streak.Show, glow.streak)
  end

  if not g.running then
    g.running = true
    g.lastTick = nil
    U.RegisterUpdate(g.updateId, 0, book.GlowTick)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Skill-line side tabs
--
-- The Dragonflight frame replaces the client's parchment tab art on the same
-- button. Only the selected tab (the client's own checked state) draws the
-- gold face; hover keeps the neutral face and shows just the client's inner
-- highlight glow. The icon and the client's hover and checked glows stay.
-- ---------------------------------------------------------------------------
function book.RefreshSkillTab(tab)
  local state = tab and tab.uuiModernWowSkillTab
  if not state then return end

  local checked = false
  if tab.GetChecked then
    local ok, value = pcall(tab.GetChecked, tab)
    checked = ok and value and true or false
  end
  local t = book.Token()
  pcall(state.face.SetTexture, state.face,
        checked and t.texture.skillTabGlow or t.texture.skillTab)
end

function book.DressSkillTab(index)
  local tab = U.G("SpellBookSkillLineTab" .. index)
  if not tab then return end

  local t = book.Token()
  local token = t.skillTab
  local L = book.layout
  pcall(function()
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", book.frame, "TOPLEFT",
                 t.housing.right + L.extra - token.rim - token.artX,
                 -(token.top + (index - 1) * token.pitch))
  end)

  if tab.uuiModernWowSkillTab then
    book.RefreshSkillTab(tab)
    return
  end

  local size = book.Dimension(tab, "GetWidth")
  if size <= 0 then size = token.size end
  local k = size / token.size

  local face = book.Texture(tab, "BACKGROUND", t.texture.skillTab)
  if not face then return end
  pcall(function()
    face:SetWidth(token.art * k)
    face:SetHeight(token.art * k)
    face:SetPoint("TOPLEFT", tab, "TOPLEFT", token.artX * k, token.artY * k)
  end)

  -- Only the stock tab art (Interface\SpellBook\SpellBook-SkillLineTab); the
  -- icon and the client's hover and checked glows stay. See book.StripForeign
  -- for why this is matched by path.
  book.StripForeign(tab, "interface\\spellbook\\")

  local state = { face = face }
  tab.uuiModernWowSkillTab = state
  U.PostHookScript(tab, "OnClick", function() book.RefreshSkillTabs() end)
  book.RefreshSkillTab(tab)
end

function book.SkillTabCount()
  return tonumber(U.G("MAX_SKILLLINE_TABS")) or 8
end

function book.RefreshSkillTabs()
  local i
  for i = 1, book.SkillTabCount() do
    book.RefreshSkillTab(U.G("SpellBookSkillLineTab" .. i))
  end
end

-- ---------------------------------------------------------------------------
-- Bottom tabs
--
-- The shared tab group still owns selection (modules/spellbook.lua's booktab
-- does the book switch); modern-wow's frame-tabs art replaces only what the
-- group draws, exactly as on the Character window.
-- ---------------------------------------------------------------------------
function book.DressBottomTabs()
  local t = book.Token()
  local tabs, i = {}, nil
  local active = 1

  -- An owned Spellbook tab, then Professions, then the client's Pet tab. The
  -- client's own Spellbook tab is hidden whenever the player has no pet
  -- (USER_CONFIRMED_INGAME, 2026-09-14: it vanished and the Professions tab
  -- chained to it lost its anchor), so it is replaced rather than chained to.
  -- Only always-shown tabs precede the conditional Pet tab.
  local extra
  if type(U.ModernWowSpellBookExtraTabs) == "function" then
    local ok, value = pcall(U.ModernWowSpellBookExtraTabs, book.frame)
    if ok and type(value) == "table" and value.professions and
       value.spellbook then
      extra = value
    end
  end

  if extra then
    tabs = { extra.spellbook, extra.professions }
    for i = 2, 3 do
      local tab = U.G("SpellBookFrameTabButton" .. i)
      if tab then table.insert(tabs, tab) end
    end
  else
    for i = 1, 3 do
      local tab = U.G("SpellBookFrameTabButton" .. i)
      if tab then table.insert(tabs, tab) end
    end
  end
  if not tabs[1] then return end

  pcall(function()
    tabs[1]:ClearAllPoints()
    tabs[1]:SetPoint("TOPLEFT", book.frame, "TOPLEFT",
                     t.bottomTab.left, -t.bottomTab.top)
  end)
  U.ChainStockTabs(tabs, t.bottomTab.gap)
  U.StyleStockTabGroup(tabs, active, { height = 20 })

  if type(U.ModernWowDressTab) == "function" then
    for i = 1, table.getn(tabs) do
      pcall(U.ModernWowDressTab, tabs[i])
    end
  end
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function book.Reapply()
  if not book.built then return end
  -- The window's own parchment art, should the client restore it; this
  -- theme's regions on the same frame are recognised by path.
  book.StripForeign(book.frame)
  book.PlaceWindowControls()

  local i
  for i = 1, book.SpellCount() do book.DressSpellButton(i) end
  for i = 1, book.SkillTabCount() do book.DressSkillTab(i) end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
function U.ModernWowSpellBookWanted()
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= book.THEME then
    return false
  end
  return type(U.ModernWowSurfaceEnabled) == "function" and
         U.ModernWowSurfaceEnabled(book.SURFACE) and true or false
end

function U.ModernWowSpellBookActive()
  return book.built
end

-- Where modules/spellbook.lua puts its two toggles: the dark band under the
-- header bar, beside the ring. Nil when this path is not drawn.
function U.ModernWowSpellBookToggleAnchor()
  if not book.built then return nil end
  local toggle = book.Token().toggle
  return "TOPLEFT", book.frame, "TOPLEFT", toggle.left, -toggle.top
end

-- ---------------------------------------------------------------------------
-- Page hooks for modules/spellbookprofessions.lua
-- ---------------------------------------------------------------------------

-- Swaps the art in the two page regions; nil restores the spell pages. The
-- replacement must share the spell pages' canvas, since the regions keep
-- their texture coordinates.
function U.ModernWowSpellBookSetPageArt(page1, page2)
  if not book.built then return end
  local t = book.Token()
  if book.page1 then
    pcall(book.page1.SetTexture, book.page1, page1 or t.texture.page1)
  end
  if book.page2 then
    pcall(book.page2.SetTexture, book.page2, page2 or t.texture.page2)
  end
end

-- A page-art texel as a TOPLEFT offset of the window (y positive down).
function U.ModernWowSpellBookPagePoint(x, y)
  if not book.built then return nil end
  return book.PagePoint(x, y)
end

function U.ModernWowSpellBookPageScale()
  if not book.built then return nil end
  return book.layout.kx, book.layout.ky
end

-- `placer(index)` returns { x, y, size, textWidth } in window units for
-- SpellButton<index>, or nil for the spell grid. Applied on the next redress.
function U.ModernWowSpellBookSetButtonPlacer(placer)
  book.placer = placer
end

function U.ModernWowSpellBookRedress()
  book.Reapply()
end

-- The class portrait in the gold ring; the Professions page hides it under
-- its own icon. Returns the ring rect as TOPLEFT window units.
function U.ModernWowSpellBookShowClassPortrait(shown)
  if book.portrait then
    if shown then
      pcall(book.portrait.Show, book.portrait)
    else
      pcall(book.portrait.Hide, book.portrait)
    end
  end
  if not book.built then return nil end
  local ring = book.Token().ring
  return ring.left + ring.inset, ring.top + ring.inset,
         ring.size - 2 * ring.inset
end

-- `/uui sb look`: what the first spell button and skill tab actually draw, so
-- a missing icon or frame is answered from the client instead of a guess.
-- Read-only.
function U.ModernWowSpellBookReport()
  local function state(object)
    if not object then return "nil" end
    return "shown=" .. tostring(book.Shown(object)) ..
           " alpha=" .. string.format("%.2f", book.Dimension(object, "GetAlpha")) ..
           " level=" .. book.Dimension(object, "GetFrameLevel")
  end

  U.Print("spellbook modern-wow: wanted=" ..
          tostring(U.ModernWowSpellBookWanted()) ..
          " built=" .. tostring(book.built))
  local frame = U.G("SpellBookFrame")
  U.Print("  frame " .. state(frame) ..
          " width=" .. book.Dimension(frame, "GetWidth"))
  U.Print("  SpellButton1 " .. state(U.G("SpellButton1")))
  U.Print("  icon " .. state(U.G("SpellButton1IconTexture")))
  local name = U.G("SpellButton1SpellName")
  local textOk, text = false, nil
  if name and name.GetText then textOk, text = pcall(name.GetText, name) end
  U.Print("  name " .. state(name) .. " text=" ..
          tostring(textOk and text or "?"))
  -- Every texture region on the first button, by the readers a walked
  -- wrapper does carry, so a stock piece that survives can be named.
  local button = U.G("SpellButton1")
  if button and button.GetRegions then
    local ok, regions = pcall(function() return { button:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        local kindOk, kind = pcall(region.GetObjectType, region)
        if kindOk and kind == "Texture" then
          local nameOk, own = false, nil
          if region.GetName then nameOk, own = pcall(region.GetName, region) end
          local pathOk, path = false, nil
          if region.GetTexture then pathOk, path = pcall(region.GetTexture, region) end
          U.Print("    region " .. i .. " name=" .. tostring(nameOk and own) ..
                  " path=" .. tostring(pathOk and path) ..
                  " shown=" .. tostring(book.Shown(region)))
        end
      end
    end
  end

  U.Print("  prev/next caption shadows cleared: " ..
          book.ClearLabelShadows(U.G("SpellBookPrevPageButton")) .. "/" ..
          book.ClearLabelShadows(U.G("SpellBookNextPageButton")))

  local art = book.buttons[1]
  U.Print("  slot frame " .. state(art and art.frame) ..
          " background " .. state(art and art.background))
  local tab = U.G("SpellBookSkillLineTab1")
  local checkedOk, checked = false, nil
  if tab and tab.GetChecked then checkedOk, checked = pcall(tab.GetChecked, tab) end
  U.Print("  skill tab 1 " .. state(tab) .. " checked=" ..
          tostring(checkedOk and checked) .. " face=" ..
          tostring(tab ~= nil and tab.uuiModernWowSkillTab ~= nil))
end

-- Builds once. Called from modules/spellbook.lua's OnEnable under pcall, and
-- only after U.ModernWowSpellBookWanted; modules/modernwow.lua's surface
-- confirms the result.
function U.BuildModernWowSpellBook()
  if book.built then return true end

  local frame = U.G("SpellBookFrame")
  if not frame then error("SpellBookFrame is unavailable") end
  book.frame = frame
  book.layout = book.Solve()

  local t = book.Token()
  local L = book.layout

  U.StripStockTextures(frame)
  pcall(frame.SetWidth, frame, L.width)
  pcall(frame.SetHitRectInsets, frame, t.housing.left,
        L.width - (t.housing.right + L.extra), 0,
        L.height - t.housing.bottom)

  local chrome = book.BuildChrome(frame)
  -- Marks the window as dressed for /uui mw and keeps the generic window
  -- surface from laying its own quadrants over this one.
  frame.uuiModernWowWindow = { chrome = chrome, spellBook = true }
  book.built = true

  book.PlaceWindowControls()
  if type(U.ModernWowDressCloseButton) == "function" then
    pcall(U.ModernWowDressCloseButton, "SpellBookCloseButton")
  end

  U.MakeWindowDraggable("spellbook", frame, {
    headerHeight = t.headerBar.bottom + 1,
    headerInset = t.dragInset,
  })
  book.DressBottomTabs()

  local i
  for i = 1, book.SpellCount() do book.DressSpellButton(i) end
  for i = 1, book.SkillTabCount() do book.DressSkillTab(i) end

  U.PostHookScript(frame, "OnShow", book.Reapply)
  U.PostHookGlobal("SpellButton_UpdateButton", book.OnSpellButtonUpdate)
  U.PostHookGlobal("SpellBookFrame_Update", book.RefreshSkillTabs)
  return true
end
