-- unrealUI :: modules/bagbar.lua
--
-- The HUD bag bar: a backpack button, the four equipped bag slots, the keyring
-- and a collapse arrow, laid out along the bottom-right corner the way
-- DragonflightUI places its own bag bar.
--
-- WHY IT EXISTS
--
-- modules/bags.lua can be switched off entirely, so a player running a
-- third-party bag addon gets the client's own container windows back
-- (SETTINGS_BAGS_ENABLE). What that switch cannot give back is the stock bag
-- BAR: MainMenuBarBackpackButton, CharacterBag0-3Slot and KeyRingButton are
-- children of MainMenuBar, and modules/actionbar.lua suppresses that whole
-- family because UnrealUI draws its own action bars. Turning the bag module
-- off therefore left no on-screen way to open a bag at all -- only a keybind.
-- This module fills that gap:
--
--   bags module OFF  -> this bar appears outside classic-wow, and every click
--                       goes to the client's own globals (ToggleBackpack,
--                       OpenAllBags, ToggleBag), so whichever addon owns the
--                       container UI answers it. Classic keeps the stock bag
--                       buttons inside the native MainMenuBar instead.
--   bags module ON   -> the merged bag window owns the container UI, so the
--                       bar is redundant and stays hidden -- except under
--                       `modern-wow` with the `bagbar` surface on, where the
--                       DragonflightUI bag row is part of that interface's
--                       HUD and the player asked to keep it (user request,
--                       2026-09-21). There it builds exactly as it does with
--                       the module off: modules/bags.lua has already pointed
--                       ToggleBackpack/OpenAllBags at its merged window and
--                       neutered ToggleBag, so the same clicks land on that
--                       window without this module knowing anything about it.
--                       Only the keyring needs a different destination, since
--                       the merged window carries its own keyring tray rather
--                       than a global -- see bb.CreateKeyring.
--
-- WHAT IT DOES NOT DO
--
-- It does not touch a native widget. Outside classic-wow, the stock bag buttons
-- remain where the client put them under the suppressed MainMenuBar; under
-- classic-wow this module does not build and those buttons remain fully native.
-- Nothing here reparents, reskins, hides or caches one, so no part of this
-- depends on a native child's lifetime (rules/unreal-ui.md, native widget
-- ownership). The four equipped-bag slots in this replacement bar are
-- UnrealUI-owned buttons built on the client's bag-slot template through the
-- shared component in core/itemslot.lua, exactly as the bag window builds its
-- own row.
--
-- THEMES
--
-- Two complete drawing paths behind one seam, per rules/unreal-ui-design.md:
-- `modern` gets the shared flat item-slot chrome, `classic-wow` keeps the stock
-- MainMenuBar bag buttons, and `modern-wow` gets DragonflightUI bag art from
-- media/Textures/modern-wow/bags (registered as the `bagbar` surface in
-- modules/modernwow.lua). The theme is read once, in Build.
--
-- EVIDENCE
--
-- ToggleBackpack, OpenAllBags, CloseAllBags, ToggleBag, ToggleKeyRing and
-- HasKey have no runtime record on this client -- query_compat.py returns
-- nothing for the first four, and documents HasKey and the container readers
-- as OFFICIAL_CLIENT_DOCUMENTATION only. Every one of them is therefore
-- resolved through U.G, type-checked before use and called inside pcall, and a
-- control whose global is missing is simply not shown rather than shown broken.

local U = UnrealUI
local M = U.media

local BB = U.RegisterModule("bagbar")

-- One table rather than a run of top-level locals (rules/unreal-ui.md: a Lua
-- 5.0/5.1 chunk silently fails to load past 200 of them).
local bb = {}

bb.SLOT_COUNT = 4            -- the four swappable equipped bag slots
bb.KEYRING_BAG = -2
bb.BACKPACK_BAG = 0

-- Metrics.
--
-- The equipped-bag slots are the shared item-slot size, so the bar keeps the
-- container windows' density rather than inventing its own, and the backpack
-- is scaled up from that same token: one clearly primary control with a row of
-- smaller ones beside it.
--
-- The scale is kept as its two factors rather than one rounded pixel count, so
-- the inherited proportion and the local adjustment stay separable. 1.5 is
-- DragonflightUI's own default bagScale against its 30px bag buttons
-- (modules/bags/bags.lua); the 1.15 on top of it is this interface's own
-- choice, asked for after seeing the bar in game.
bb.BACKPACK_SCALE = 1.5 * 1.15

bb.SLOT     = M.slot.size                                  -- 30
bb.BACKPACK = U.Round(M.slot.size * bb.BACKPACK_SCALE)     -- 52
bb.GAP      = M.slot.gap                                   -- 3
bb.LEAD     = 6      -- backpack to the first bag slot
bb.ARROW    = 16

bb.config = nil
bb.anchor = nil
bb.backpack = nil
bb.arrow = nil
bb.keyring = nil
bb.slots = {}
bb.dirty = true
bb.built = false

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
function bb.EnsureConfig()
  -- expanded is the collapse arrow's state, persisted so the bar comes back
  -- the way it was left. enabled exists for the player whose replacement bag
  -- addon draws a bag bar of its own and does not want a second one.
  if not bb.config then
    bb.config = U.ModuleConfig("bagbar", { enabled = true, expanded = true })
  end
  return bb.config
end

-- Public for the two views of this switch: the Bags settings page
-- (modules/bags.lua) and the contextual panel on this bar's own edit-mode
-- anchor.
--
-- It takes effect immediately -- no reload. Nothing about the bar depends on a
-- state read once at load: the only thing it decides at build time is which
-- theme it draws, and a theme change is reload-bound in its own right. So the
-- switch simply shows or hides the row. The anchor under it stays put either
-- way, because the panel on that anchor is one of the two places this switch
-- lives (bb.Available, bb.HideControls).
function U.BagBarEnabled()
  return bb.EnsureConfig().enabled and true or false
end

function U.SetBagBarEnabled(value)
  bb.EnsureConfig().enabled = value and true or false
  bb.Apply()
  return U.BagBarEnabled()
end

-- The `modern-wow` bag row: the theme is on and its `bagbar` surface has not
-- been switched off. Build reads this to choose its drawing path, and Wanted
-- reads it to decide whether the bar survives the bag module being on, so both
-- answers come from one place rather than drifting apart.
function bb.ModernWowActive()
  if type(U.GetActiveThemeStyle) ~= "function" then return false end
  if U.GetActiveThemeStyle() ~= "modern-wow" then return false end
  if type(U.ModernWowSurfaceEnabled) ~= "function" then return true end
  return U.ModernWowSurfaceEnabled("bagbar") and true or false
end

-- Whether this interface has a place for the bar at all, ignoring the player's
-- own switch. The bar stands in for the bag module, so that is normally only
-- while the module is off; the exception is `modern-wow`, where the bag row is
-- part of the theme's own HUD rather than a stand-in and stays on screen
-- alongside the merged bag window (user request, 2026-09-21). Classic keeps
-- the stock bag buttons on the native MainMenuBar and needs neither.
--
-- This, not bb.Wanted, is the mover's `visible` predicate: an anchor that
-- disappeared with the bar would take away the only place the bar can be
-- switched back on in edit mode (user request, 2026-09-21).
function bb.Available()
  local nativeMain = nil
  if type(U.ActionBarUsesNativeMainMenuBar) == "function" then
    nativeMain = U.ActionBarUsesNativeMainMenuBar()
  elseif type(U.ThemeStyleUsesNativeMainMenuBar) == "function" then
    nativeMain = U.ThemeStyleUsesNativeMainMenuBar()
  end
  if nativeMain then return false end
  if type(U.BagsEnabled) ~= "function" then return true end
  if not U.BagsEnabled() then return true end
  return bb.ModernWowActive()
end

-- ...and whether it is actually drawn: the above plus the player's switch.
-- U.BagsEnabled reads the same persisted flag the bag module's own settings
-- checkbox writes, and that switch is reload-bound; this bar's own switch is
-- not, which is why the answer is recomputed by bb.Apply rather than captured
-- once.
function bb.Wanted()
  if not bb.EnsureConfig().enabled then return false end
  return bb.Available()
end

-- True while the bar is sharing the screen with UnrealUI's own merged bag
-- window rather than standing in for it. Only the keyring control cares: every
-- other click already reaches that window through the globals bags.lua
-- overrides.
function bb.SharesWithBagWindow()
  return type(U.BagsEnabled) == "function" and U.BagsEnabled() and true or false
end

-- ---------------------------------------------------------------------------
-- Client calls
--
-- Every global this module uses is resolved here, so a missing one is a nil
-- return at one place instead of an error at the call site.
-- ---------------------------------------------------------------------------
function bb.Call(name, arg)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, arg) and true or false
end

function bb.Has(name)
  return type(U.G(name)) == "function"
end

-- Free and total carried slots, across the backpack and the four bags.
-- GetContainerNumSlots and GetContainerItemInfo are documented but not runtime
-- verified here (knowledge.json / bags.container_api_contract_unverified), and
-- this client answers an empty slot with texture "" rather than nil -- which is
-- why the shared reader in core/compat.lua is used rather than the raw call.
function bb.FreeSlots()
  local free, total, bag, slot = 0, 0, nil, nil

  for bag = bb.BACKPACK_BAG, bb.SLOT_COUNT do
    local ok, count = pcall(GetContainerNumSlots, bag)
    count = (ok and tonumber(count)) or 0
    total = total + count
    for slot = 1, count do
      local texture = U.ContainerSlotInfo(bag, slot)
      if not texture then free = free + 1 end
    end
  end

  return free, total
end

-- ---------------------------------------------------------------------------
-- modern-wow drawing path
--
-- WORKING_SOURCE: DragonflightUI-Reforged modules/bags/bags.lua dresses the
-- stock bag buttons with a bag picture on the backpack, a cutout rim over it,
-- and per-slot cells out of one atlas. Only that art and its geometry are
-- reproduced. Its stock-button ownership, tempDB config machinery and
-- dark-mode/colour callbacks are not.
-- ---------------------------------------------------------------------------
bb.mw = {
  active = false,
  -- The small-slot cells are drawn a half pixel over their 30px button and
  -- nudged (2, -1): the ring is not centred within its own cell in the source
  -- atlas, and this is DragonflightUI's correction for it (Setup:SmallBags).
  -- The same atlas is used here, so the same correction applies.
  slotGrow = 0.5,
  cellX = 2,
  cellY = -1,
  -- The backpack's two pieces are authored at button size and need no nudge:
  -- DF sets the bag picture as the button's item texture and pins the cutout
  -- rim corner to corner (Setup:MainBag).
  bagGrow = 0,
  -- A 20px icon inside a 30px slot, which is DF's iconSize against the same
  -- ring. Expressed as an inset so it follows bb.SLOT if that changes.
  iconInset = 5,
  -- An equipped bag's own item icon is square where DF rounds it off with
  -- SetPortraitToTexture (see DressIcon), so at DF's icon size its corners sit
  -- on the ring. Asked for after seeing the bar in game: trim 3px off the
  -- extra-bag icons only, which pulls those corners inside the rim. The
  -- backpack (its own DF bag picture) and the keyring (the atlas key picture)
  -- are already authored to their art and keep the plain inset.
  bagIconTrim = 3,
  -- ...and drop the whole extra-bag cell -- ring, rim, state rings and icon --
  -- 3px, which is the other half of the same in-game correction: the slots
  -- read high against the backpack's larger ring beside them. The keyring keeps
  -- the plain cell offset, so this is passed in rather than folded into cellY.
  bagDrop = 3,
}

function bb.mw.Texture(parent, layer, path, cell)
  if not parent or type(parent.CreateTexture) ~= "function" then return nil end
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  if not pcall(texture.SetTexture, texture, path) then return nil end
  if cell then
    pcall(texture.SetTexCoord, texture, cell[1], cell[2], cell[3], cell[4])
  end
  return texture
end

function bb.mw.Size(texture, size)
  if not texture then return end
  pcall(texture.SetWidth, texture, size)
  pcall(texture.SetHeight, texture, size)
end

-- Points one of a button's own state textures at the atlas hover cell. The
-- slot is left to the client to show and hide; only its art is replaced.
function bb.mw.StateCell(button, setter, getter, size, y)
  if type(button[setter]) ~= "function" then return end
  if not pcall(button[setter], button, M.modernWow.texture.bagSlotFrame) then
    return
  end

  local ok, region = pcall(button[getter], button)
  if not ok or not region then return end

  pcall(region.SetTexCoord, region, M.Unpack(M.modernWow.bagCell.highlight))
  pcall(region.ClearAllPoints, region)
  bb.mw.Size(region, size)
  pcall(region.SetPoint, region, "CENTER", button, "CENTER",
        bb.mw.cellX, y or bb.mw.cellY)
end

-- One round bag-slot face: the empty-slot cell behind the icon and the rim
-- cell over it, with the atlas hover ring as the button's own highlight. The
-- button keeps its flat UnrealUI backdrop underneath but hidden, so switching
-- nothing else is needed if a texture is missing.
function bb.mw.DressSlot(button, size, cells, drop)
  if not button or button.uuiModernWowBag then return end

  local art = M.modernWow.texture.bagSlotFrame
  local ring = size + bb.mw.slotGrow
  local cellY = bb.mw.cellY - (drop or 0)

  local face = bb.mw.Texture(button, "BACKGROUND", art, cells.face)
  local rim = bb.mw.Texture(button, "OVERLAY", art, cells.rim)

  -- Both structural pieces or neither: a half-dressed round slot reads worse
  -- than the flat square it would otherwise have been.
  if not face or not rim then
    if face then pcall(face.Hide, face) end
    if rim then pcall(rim.Hide, rim) end
    button.uuiModernWowBag = { failed = true }
    return
  end

  bb.mw.Size(face, ring)
  bb.mw.Size(rim, ring)
  face:SetPoint("CENTER", button, "CENTER", bb.mw.cellX, cellY)
  rim:SetPoint("CENTER", button, "CENTER", bb.mw.cellX, cellY)

  U.SetBackdropShown(button, false)

  -- Hover and, on a CheckButton, the checked state are the button's own state
  -- slots rather than textures of ours, so the client keeps driving them.
  bb.mw.StateCell(button, "SetHighlightTexture", "GetHighlightTexture",
                  ring, cellY)
  bb.mw.StateCell(button, "SetCheckedTexture", "GetCheckedTexture", ring, cellY)
  bb.mw.StateCell(button, "SetPushedTexture", "GetPushedTexture", ring, cellY)

  button.uuiModernWowBag = { face = face, rim = rim }
end

-- The equipped bag's own icon, inset so the round rim closes over its corners
-- rather than meeting a square edge.
--
-- DragonflightUI rounds this icon off with SetPortraitToTexture. That call is
-- deliberately not made here: it is documented to raise a Lua error when it
-- cannot resolve the named region, and nothing on this client confirms it
-- resolves a texture an addon named itself. A square icon under a round rim is
-- a smaller cost than a guessed native call on a startup path.
function bb.mw.DressIcon(button, name, size, drop)
  local icon = U.G(name .. "IconTexture")
  if not icon then return end

  pcall(icon.ClearAllPoints, icon)
  pcall(icon.SetPoint, icon, "CENTER", button, "CENTER", 0, -(drop or 0))
  local extent = size - bb.mw.iconInset * 2 - bb.mw.bagIconTrim
  pcall(icon.SetWidth, icon, extent)
  pcall(icon.SetHeight, icon, extent)
  pcall(icon.SetDrawLayer, icon, "BORDER")
  button.uuiModernWowIcon = icon
end

-- The backpack wears DragonflightUI's own bag picture rather than a client
-- item icon, plus the separate cutout rim that art is authored with.
function bb.mw.DressBackpack(button, size)
  if not button then return end

  local ring = size + bb.mw.bagGrow
  local bag = bb.mw.Texture(button, "ARTWORK", M.modernWow.texture.bagSlot)
  local rim = bb.mw.Texture(button, "OVERLAY",
                            M.modernWow.texture.bagSlotCutout)
  local hover = bb.mw.Texture(button, "OVERLAY",
                              M.modernWow.texture.bagSlotHighlight)

  if not bag then return false end

  U.SetBackdropShown(button, false)
  if button.icon then pcall(button.icon.Hide, button.icon) end

  bb.mw.Size(bag, size)
  bag:SetPoint("CENTER", button, "CENTER", 0, 0)
  if rim then
    bb.mw.Size(rim, ring)
    rim:SetPoint("CENTER", button, "CENTER", 0, 0)
  end
  if hover then
    bb.mw.Size(hover, ring)
    hover:SetPoint("CENTER", button, "CENTER", 0, 0)
    pcall(hover.Hide, hover)
    button.uuiModernWowHover = hover
  end

  button.uuiModernWowBag = { face = bag, rim = rim }
  return true
end

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------

-- The backpack. Left click is the stock toggle; right click opens or closes
-- every bag at once, which is the one thing the stock button cannot do and the
-- reason a HUD bag control is worth having. Both are optional: a client
-- missing OpenAllBags simply has no right-click behavior.
function bb.CreateBackpack()
  local button = U.CreateButton(bb.anchor, {
    name = "UnrealUIBagBarBackpack",
    text = "",
    width = bb.BACKPACK,
    height = bb.BACKPACK,
  })

  local edge = U.BorderSize()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)
  if pcall(icon.SetTexture, icon, M.texture.bagIcon) then
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  else
    icon:Hide()
  end
  button.icon = icon

  -- Free-slot readout, under the button the way DragonflightUI places it.
  button.freeText = U.CreateLabel(button, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "CENTER",
  })
  if button.freeText then
    button.freeText:SetPoint("TOP", button, "BOTTOM", 0, 1)
  end

  pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")

  button:SetScript("OnClick", function(a1, a2)
    local mouseButton = U.MouseButton(a1, a2)
    if mouseButton == "RightButton" then
      if not bb.Call("OpenAllBags") then bb.Call("ToggleBackpack") end
      return
    end
    if not bb.Call("ToggleBackpack") then bb.Call("OpenBackpack") end
  end)

  -- An item dropped on the bag goes into the first free backpack slot, which
  -- is what the stock button does. OnReceiveDrag only; a click carrying an
  -- item is left to the toggle above so a misclick cannot silently stash it.
  button:SetScript("OnReceiveDrag", function()
    bb.Call("PutItemInBackpack")
  end)

  button:SetScript("OnEnter", function()
    if not bb.mw.active then
      U.SetBorderColor(button, M.Unpack(M.color.accentDim))
    elseif button.uuiModernWowHover then
      pcall(button.uuiModernWowHover.Show, button.uuiModernWowHover)
    end

    local tip = U.G("GameTooltip")
    if tip then
      pcall(tip.SetOwner, tip, button, "ANCHOR_RIGHT")
      pcall(tip.SetText, tip, U.L("BAGBAR_BACKPACK"))
      local free, total = bb.FreeSlots()
      pcall(tip.AddLine, tip, U.L("BAGBAR_FREE_SLOTS", free, total),
            0.65, 0.65, 0.65, 1)
      -- Not while the merged bag window owns the container UI: bags.lua points
      -- OpenAllBags at the same toggle as ToggleBackpack, so right click does
      -- exactly what left click does and the line would promise a second
      -- behaviour that does not exist.
      if bb.Has("OpenAllBags") and not bb.SharesWithBagWindow() then
        pcall(tip.AddLine, tip, U.L("BAGBAR_OPEN_ALL_HINT"),
              0.65, 0.65, 0.65, 1)
      end
      pcall(tip.Show, tip)
    end
  end)

  button:SetScript("OnLeave", function()
    if not bb.mw.active then
      U.SetBorderColor(button, M.Unpack(M.color.border))
    elseif button.uuiModernWowHover then
      pcall(button.uuiModernWowHover.Hide, button.uuiModernWowHover)
    end
    local tip = U.G("GameTooltip")
    if tip then pcall(tip.Hide, tip) end
  end)

  return button
end

-- One equipped-bag slot, from the shared component so its identity, click,
-- drag and pickup fallback are the same code the bag window's own row runs.
function bb.CreateSlot(i)
  local name = "UnrealUIBagBarSlot" .. i
  local button = U.CreateBagSlotButton(bb.anchor, name, i)
  if not button then return nil end

  button:SetWidth(bb.SLOT)
  button:SetHeight(bb.SLOT)
  U.StyleItemSlot(button, name)

  if bb.mw.active then
    -- Not U.UseBorderOnlyItemSlotHover here: it empties the highlight slot the
    -- atlas ring is about to take over as this theme's hover state.
    bb.mw.DressSlot(button, bb.SLOT, {
      face = M.modernWow.bagCell.slot,
      rim = M.modernWow.bagCell.border,
    }, bb.mw.bagDrop)
    bb.mw.DressIcon(button, name, bb.SLOT, bb.mw.bagDrop)
  else
    -- The explicit border is the whole hover state under the flat themes, the
    -- same treatment the bag window's equipped-bag row uses.
    U.UseBorderOnlyItemSlotHover(button)
    U.PostHookScript(button, "OnEnter", function()
      U.SetBorderColor(button, M.Unpack(M.color.accentDim))
    end)
    U.PostHookScript(button, "OnLeave", function()
      U.SetBorderColor(button, M.Unpack(M.color.border))
    end)
  end

  return button
end

-- The keyring, when this client has one to open. ToggleKeyRing has no record
-- at all here, so its absence hides the button rather than leaving a control
-- that does nothing.
function bb.CreateKeyring()
  -- With the merged bag window on screen beside this bar, the keyring lives
  -- in that window's own tray and there is no global that opens it -- bags.lua
  -- leaves ToggleKeyRing alone and makes ToggleBag a no-op, so the stock path
  -- below would open the client's KeyRingFrame on top of the merged bag. Route
  -- to the window's tray instead, and if that module exposes no opener, show
  -- no keyring at all rather than one that opens the wrong thing.
  local shared = bb.SharesWithBagWindow()
  if shared then
    if type(U.ToggleBagKeyring) ~= "function" then return nil end
  elseif not bb.Has("ToggleKeyRing") and not bb.Has("ToggleBag") then
    return nil
  end

  local name = "UnrealUIBagBarKeyring"
  local button = U.CreateButton(bb.anchor, {
    name = name,
    text = "",
    width = bb.SLOT,
    height = bb.SLOT,
    onClick = function()
      if shared then
        pcall(U.ToggleBagKeyring)
        return
      end
      if not bb.Call("ToggleKeyRing") then
        bb.Call("ToggleBag", bb.KEYRING_BAG)
      end
    end,
  })

  local edge = U.BorderSize()
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", edge, -edge)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -edge, edge)
  if not pcall(icon.SetTexture, icon, M.texture.keyringIcon) then icon:Hide() end
  button.icon = icon

  if bb.mw.active then
    bb.mw.DressSlot(button, bb.SLOT, {
      face = M.modernWow.bagCell.keySlot,
      rim = M.modernWow.bagCell.keyBorder,
    })
    -- The source art has its own key picture for this button; under the round
    -- face it replaces the flat theme's icon entirely.
    if pcall(icon.SetTexture, icon, M.modernWow.texture.bagKeyring) then
      local inset = bb.mw.iconInset
      pcall(icon.ClearAllPoints, icon)
      pcall(icon.SetPoint, icon, "CENTER", button, "CENTER", 0, 0)
      pcall(icon.SetWidth, icon, bb.SLOT - inset * 2)
      pcall(icon.SetHeight, icon, bb.SLOT - inset * 2)
    end
  else
    button:SetScript("OnEnter", function()
      U.SetBorderColor(button, M.Unpack(M.color.accentDim))
    end)
    button:SetScript("OnLeave", function()
      U.SetBorderColor(button, M.Unpack(M.color.border))
    end)
  end

  return button
end

-- The collapse arrow. Folds the bag slots and keyring away and leaves the
-- backpack, which is DragonflightUI's toggleBags control.
function bb.CreateArrow()
  local button

  local function Toggle()
    bb.EnsureConfig().expanded = not bb.config.expanded
    bb.Layout()
  end

  if bb.mw.active then
    button = CreateFrame("Button", "UnrealUIBagBarToggle", bb.anchor)
    button:SetWidth(bb.ARROW)
    button:SetHeight(bb.ARROW)
    local glyph = bb.mw.Texture(button, "ARTWORK",
                                M.modernWow.texture.bagExpand)
    if glyph then
      glyph:SetAllPoints(button)
      button.glyph = glyph
      pcall(button.SetHighlightTexture, button,
            M.modernWow.texture.bagExpand)
    end
    button:SetScript("OnClick", Toggle)
  else
    button = U.CreateArrowToggle(bb.anchor, {
      name = "UnrealUIBagBarToggle",
      size = M.fontSize.normal,
      width = bb.ARROW,
      height = bb.SLOT,
      onClick = Toggle,
    })
  end

  return button
end

-- ---------------------------------------------------------------------------
-- Layout
--
-- Right to left from the backpack, which is the corner-most control, so the
-- row grows leftwards as slots appear and the backpack never moves.
-- ---------------------------------------------------------------------------
function bb.SetArrowDirection(expanded)
  local button = bb.arrow
  if not button then return end

  if bb.mw.active then
    -- The source glyph is authored pointing left, which is the direction the
    -- row grows -- so it is the collapsed state that wears it unflipped, and
    -- the open row that mirrors it into a "fold this away" arrow. Flipping
    -- texture coordinates is how DragonflightUI turns this glyph around.
    local i
    local regions = { button.glyph }
    local hlOk, highlight = pcall(button.GetHighlightTexture, button)
    if hlOk and highlight then table.insert(regions, highlight) end
    for i = 1, table.getn(regions) do
      if regions[i] then
        if expanded then
          pcall(regions[i].SetTexCoord, regions[i], 1, 0, 0, 1)
        else
          pcall(regions[i].SetTexCoord, regions[i], 0, 1, 0, 1)
        end
      end
    end
  elseif button.SetDirection then
    button.SetDirection(expanded and "right" or "left")
  end
end

-- Places one control with its right edge `offset` from the bar's right edge,
-- and its own centre on the bar's centre line. Every control is anchored to
-- the bar rather than to the one before it, so a control of a different height
-- -- the backpack is half again as tall as the slots beside it -- sits on that
-- one line instead of inheriting its neighbour's centre down the row.
function bb.Place(control, size, offset)
  if not control then return offset end
  control:ClearAllPoints()
  control:SetPoint("RIGHT", bb.anchor, "RIGHT", -offset, 0)
  control:Show()
  return offset + size
end

function bb.Layout()
  if not bb.anchor or not bb.backpack then return end

  local expanded = bb.EnsureConfig().expanded and true or false
  local i

  -- The backpack is the corner-most control and never moves, so the row grows
  -- leftwards from it as slots appear.
  local offset = bb.Place(bb.backpack, bb.BACKPACK, 0)

  for i = 1, bb.SLOT_COUNT do
    local button = bb.slots[i]
    if button then
      if expanded then
        -- The wider lead belongs to whichever slot ends up first, which is
        -- not necessarily slot 1 if the client refused to build one.
        local gap = (offset == bb.BACKPACK) and bb.LEAD or bb.GAP
        offset = bb.Place(button, bb.SLOT, offset + gap)
      else
        button:Hide()
      end
    end
  end

  if bb.keyring then
    -- Shown only while the row is open and the player actually carries a key:
    -- an empty keyring button is a control that opens nothing. A client with
    -- no HasKey cannot say either way, and an extra button that opens an empty
    -- keyring is a smaller fault than a missing one.
    local hasKey = U.G("HasKey")
    local ok, carries = true, true
    if type(hasKey) == "function" then ok, carries = pcall(hasKey) end
    carries = (not ok) or (carries and true or false)

    if expanded and carries then
      local gap = (offset == bb.BACKPACK) and bb.LEAD or bb.GAP
      offset = bb.Place(bb.keyring, bb.SLOT, offset + gap)
    else
      bb.keyring:Hide()
    end
  end

  if bb.arrow then
    offset = bb.Place(bb.arrow, bb.ARROW, offset + bb.GAP)
    bb.SetArrowDirection(expanded)
  end

  bb.anchor:SetWidth(offset)
  -- The backpack is the tallest control, so it defines the line everything
  -- else is centred on.
  bb.anchor:SetHeight(bb.BACKPACK)
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function bb.Refresh()
  if not bb.built then return end

  local i
  for i = 1, bb.SLOT_COUNT do
    local button = bb.slots[i]
    if button then
      U.RefreshBagSlotIcon(button)
      if not bb.mw.active then
        U.SetBorderColor(button, M.Unpack(M.color.border))
      end
    end
  end

  if bb.backpack and bb.backpack.freeText then
    local label = bb.backpack.freeText
    local free, total = bb.FreeSlots()
    pcall(label.SetText, label, U.L("BAGBAR_FREE_FORMAT", free, total))
    -- A full bag is the one state worth calling out, and the accent is the
    -- addon's own active-state colour rather than a new semantic token.
    local color = (free == 0) and M.color.accent or M.color.textDim
    pcall(label.SetTextColor, label, M.Unpack(color))
  end

  -- The keyring appears and disappears with the player's first and last key.
  bb.Layout()
end

function bb.MarkDirty()
  bb.dirty = true
end

function bb.ProcessDirty()
  if not bb.dirty then return end
  -- A bar that is switched off keeps its dirty flag rather than clearing it:
  -- bb.Apply redraws on the way back anyway, and leaving it set costs nothing.
  -- The anchor itself stays shown for the edit-mode handle, so the bar's own
  -- switch is what is tested here.
  if not bb.built or not bb.Wanted() then return end
  bb.dirty = false
  bb.Refresh()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function bb.Build()
  bb.mw.active = bb.ModernWowActive()

  bb.anchor = CreateFrame("Frame", "UnrealUIBagBarAnchor", UIParent)
  bb.anchor:SetWidth(bb.BACKPACK)
  bb.anchor:SetHeight(bb.BACKPACK)
  -- The same strata the action bars use: this is HUD furniture, and a bag
  -- window opening over the corner must cover it rather than the other way
  -- round.
  pcall(bb.anchor.SetFrameStrata, bb.anchor, "LOW")

  bb.backpack = bb.CreateBackpack()
  if bb.mw.active then
    if not bb.mw.DressBackpack(bb.backpack, bb.BACKPACK) then
      -- The art did not resolve; the flat button underneath is already a
      -- complete control, so the bar degrades to it instead of failing.
      bb.mw.active = false
    end
  end

  local i
  for i = 1, bb.SLOT_COUNT do
    bb.slots[i] = bb.CreateSlot(i)
  end
  bb.keyring = bb.CreateKeyring()
  bb.arrow = bb.CreateArrow()

  U.RegisterMover("bagbar", bb.anchor, {
    label = U.L("MOVER_LABEL_BAG_BAR"),
    default = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
                x = -12, y = 28 },
    -- Available, not Wanted: a bar the bag module is currently replacing has
    -- no anchor to drag, but a bar the player has merely switched off keeps
    -- one -- its contextual panel is where it is switched back on.
    visible = function() return bb.Available() end,
  })

  bb.built = true
  -- Registered here rather than in OnEnable: the bar may be built later, the
  -- first time the player switches it on, and it needs the same refresh tick
  -- from that moment. Build runs once, so these register once.
  U.RegisterEvent("PLAYER_ENTERING_WORLD", bb.MarkDirty)
  U.RegisterEvent("BAG_UPDATE", bb.MarkDirty)
  U.RegisterEvent("UNIT_INVENTORY_CHANGED", bb.MarkDirty)
  U.RegisterUpdate("bagbar.refresh", 0.2, bb.ProcessDirty)

  -- Refresh ends in a full layout, so the row is placed by the same code that
  -- will place it on every later bag change rather than by a separate pass.
  bb.Refresh()
end

-- Hides the row without hiding the frame it hangs on. The edit-mode handle is
-- created as a CHILD of the mover's frame (core/mover.lua CreateHandle), so
-- hiding bb.anchor would hide the handle with it and there would be no anchor
-- left to switch the bar back on from. The anchor carries no art of its own --
-- no backdrop, no texture, no mouse -- so leaving it shown draws nothing.
function bb.HideControls()
  local i
  local controls = { bb.backpack, bb.keyring, bb.arrow }
  for i = 1, table.getn(controls) do
    if controls[i] then controls[i]:Hide() end
  end
  for i = 1, bb.SLOT_COUNT do
    if bb.slots[i] then bb.slots[i]:Hide() end
  end
end

-- Brings the bar into line with bb.Wanted, building it the first time this
-- interface has a place for it. Safe to call at any time and as often as
-- wanted: Build runs once, and everything after it is a show or a hide.
function bb.Apply()
  if bb.Available() and not bb.built then bb.Build() end
  if not bb.anchor then return false end

  local wanted = bb.Wanted()
  bb.anchor:Show()

  if wanted then
    -- Free slots and equipped bags may have changed while it was hidden, and
    -- the refresh tick skips a hidden bar. Drawn here rather than left to the
    -- next tick so the bar does not appear a fifth of a second stale. Layout
    -- shows exactly the controls the collapse state calls for.
    bb.dirty = false
    bb.Refresh()
  else
    bb.HideControls()
  end

  return wanted
end

-- Called by modules/modernwow.lua's surface registry.
--
-- Unlike the other surfaces this one cannot dress an existing frame: the bar is
-- built once, at OnEnable, and its art has to be chosen while its buttons are
-- created rather than painted over them afterwards. bb.Build reads the same
-- surface flag itself, and this reports what that produced so `/uui mw list`
-- states the truth instead of a guess.
--
-- A bar that was never built is not a failure of this surface, so it reports
-- success with nothing drawn. That is where this interface has no place for
-- the bar at all (bb.Available) -- this surface off while the bag module owns
-- the container UI. The player's own switch is not that case: the bar is still
-- built, and merely hidden.
function U.BuildModernWowBagBar()
  if not bb.built then return true end
  if not bb.mw.active then
    error("bag-bar art did not resolve; the bar fell back to flat chrome")
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Edit-mode panel
--
-- Clicking this bar's anchor in edit mode selects it, and core/moverpanel.lua
-- puts this panel beside the handle. It carries the bag settings themselves
-- rather than a way through to the settings window (user request,
-- 2026-09-21): the merged bag window, its category view, and whether this bar
-- is on screen. Every one of them is the same accessor the Bags page writes
-- (U.SetBagsEnabled, U.SetBagsCategories, U.SetBagBarEnabled), so the two
-- views cannot drift -- including the reload prompt the merged bag's own
-- switch raises, which belongs to that setting and not to the page.
--
-- Kept on the bb table rather than as top-level locals, like the rest of this
-- file (rules/unreal-ui.md: the Lua chunk's 200-local limit).
-- ---------------------------------------------------------------------------
bb.MOVER_CONTENT_WIDTH = 236
bb.MOVER_ROW = 22
bb.MOVER_PANEL_HEIGHT = 150

-- The rows, in the order the Bags page lists them. A row whose accessors are
-- missing -- modules/bags.lua failed to load -- is skipped rather than
-- erroring inside a panel build, which is the same defensiveness bb.Available
-- applies to U.BagsEnabled.
bb.moverRows = {
  { name = "UnrealUIBagBarMoverBags",
    text = "SETTINGS_BAGS_ENABLE",
    get = "BagsEnabled", set = "SetBagsEnabled" },
  { name = "UnrealUIBagBarMoverCategories",
    text = "SETTINGS_BAGS_CATEGORIES",
    get = "BagsCategoriesEnabled", set = "SetBagsCategories" },
  -- Live, so the bar leaves and returns under the cursor. Its anchor stays
  -- either way, which is what keeps this panel reachable to switch it back on
  -- (see bb.Available).
  { name = "UnrealUIBagBarMoverEnable",
    text = "SETTINGS_BAGBAR_ENABLE",
    get = "BagBarEnabled", set = "SetBagBarEnabled" },
}

function bb.BuildMoverPanel(frame, contentTop, contentWidth)
  local pad = U.MoverPanelPad()
  local widgets = {}
  local boxes = {}
  local last = nil
  local i, rows = nil, 0

  for i = 1, table.getn(bb.moverRows) do
    local spec = bb.moverRows[i]
    local get, set = U[spec.get], U[spec.set]
    if type(get) == "function" and type(set) == "function" then
      local box = U.CreateCheckbox(frame, {
        name = spec.name,
        text = U.L(spec.text),
        textWidth = contentWidth,
        value = get(),
        onChange = function(value) set(value) end,
      })
      box.SetPoint("TOPLEFT", frame, "TOPLEFT", pad,
                   contentTop - rows * bb.MOVER_ROW)
      rows = rows + 1
      last = box
      table.insert(boxes, { box = box, get = get })
      table.insert(widgets, box)
    end
  end

  local hint = last and U.CreateSettingsLabel(frame, {
    size = M.fontSize.tiny,
    color = M.color.textDim,
    inherits = "GameFontNormalSmall",
    justify = "LEFT",
    width = contentWidth,
  })
  if hint then
    -- Anchored under the control it explains rather than at a panel-relative
    -- offset, per rules/unreal-ui-design.md.
    U.AnchorSettingsDescription(hint, last.box)
    hint:SetText(U.L("BAGBAR_MOVER_HINT"))
    table.insert(widgets, hint)
  end

  -- Re-read on every show: the Bags page writes the same three settings, and
  -- the merged bag's switch is only applied on the next reload.
  local function Refresh()
    local j
    for j = 1, table.getn(boxes) do
      boxes[j].box.SetValue(boxes[j].get())
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function BB:OnInit()
  bb.EnsureConfig()
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel("bagbar", {
      name = "UnrealUIBagBarMoverSettings",
      width = bb.MOVER_CONTENT_WIDTH + U.MoverPanelPad() * 2,
      height = bb.MOVER_PANEL_HEIGHT,
      build = bb.BuildMoverPanel,
      title = function() return U.L("MOVER_LABEL_BAG_BAR") end,
      preferVertical = true,
    })
  end
end

function BB:OnEnable()
  bb.EnsureConfig()
  -- Nothing is built where this interface has no place for the bar at all --
  -- classic-wow, or the bag module owning the container UI outside modern-wow.
  -- Everywhere else the bar is built and then shown or hidden by its own
  -- switch, which is live and keeps its anchor either way.
  bb.Apply()
end
