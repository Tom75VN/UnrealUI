-- unrealUI :: core/stockui.lua
--
-- Small, capability-checked helpers for restyling native interface windows.
-- They reproduce only the stock-control treatment shared by the requested
-- Quest Log and Spellbook skins; this is not a general Blizzard-skin system.

local U = UnrealUI
local M = U.media
local TAB_TEXT_Y_OFFSET = -1

-- Append a handler without replacing the native behavior. Explicit arguments
-- preserve both direct handler shapes used by this client and legacy globals.
function U.PostHookScript(frame, script, callback)
  if not frame or not frame.GetScript or not frame.SetScript or
     type(script) ~= "string" or type(callback) ~= "function" then
    return false
  end

  local ok, previous = pcall(frame.GetScript, frame, script)
  if not ok then return false end

  return pcall(frame.SetScript, frame, script,
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      if previous then previous(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
      callback(a1, a2, a3, a4, a5, a6, a7, a8, a9)
    end)
end

-- Post-hooks a native global function.
--
-- The previous implementation resolved a global `hooksecurefunc` and failed
-- closed when it was absent. Nothing in the compact evidence records that
-- global on this client, and the installed UnrealPfUI does not rely on one
-- either: compat/vanilla.lua defines its own wrapper because the Vanilla-shaped
-- client does not ship one. So every unrealUI reapply hook -- the Quest Log
-- font/strip passes and the Spellbook refresh -- was silently never installed,
-- which is why native updates were free to repaint quest text after unrealUI's
-- one-time pass. WORKING_SOURCE (UnrealPfUI), not runtime-verified.
--
-- unrealUI therefore owns the wrapper. The original is always called first and
-- its returns are passed through, so this appends behaviour rather than
-- replacing a client function, and the write is read back before any callback
-- is registered so an ignored global assignment still fails closed.
--
-- LIMIT -- USER_CONFIRMED_INGAME: never point this at a native function that
-- reads `...`/arg.n. The wrapper has fixed arity and always forwards ten
-- arguments, so a vararg original sees arg.n == 10 and iterates over the
-- padding nils. Hooking this client's GossipFrameOptionsUpdate that way built
-- an option row per nil and threw "attempt to concatenate field '?' (a nil
-- value)" out of GossipFrame.lua. Fixed-signature natives (the QuestFrame
-- *_Update functions) are fine; for a vararg one, drive the reapply from an
-- event or an OnShow/OnEvent script hook instead.
local hookedGlobals = {}   -- global name -> array of unrealUI callbacks

function U.PostHookGlobal(name, callback)
  if type(name) ~= "string" or type(callback) ~= "function" then return false end

  local callbacks = hookedGlobals[name]
  if not callbacks then
    local original = U.G(name)
    if type(original) ~= "function" then return false end

    callbacks = {}
    local wrapper = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
      local r1, r2, r3, r4, r5 =
        original(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)

      local i
      for i = 1, table.getn(callbacks) do
        local ok, err = pcall(callbacks[i],
                              a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
        if not ok then U.Error(name .. " hook: " .. tostring(err)) end
      end

      return r1, r2, r3, r4, r5
    end

    U.SetG(name, wrapper)
    if U.G(name) ~= wrapper then
      U.Debug("PostHookGlobal could not replace " .. name)
      return false
    end
    hookedGlobals[name] = callbacks
  end

  table.insert(callbacks, callback)
  return true
end

-- Measured readout for /uui check: whether this client provides its own
-- hooksecurefunc, and which globals unrealUI's wrapper actually replaced. The
-- absence of that global is currently WORKING_SOURCE inference from
-- UnrealPfUI, so this is what turns it into an observation.
function U.PostHookReport()
  local names, name = {}, nil
  for name in pairs(hookedGlobals) do table.insert(names, name) end
  table.sort(names)
  return type(U.G("hooksecurefunc")), names
end

-- Replaces a stock model's separate rotate buttons with click-drag rotation.
-- Character and Inspect use the same model interaction, so the guarded drag
-- recipe lives here instead of being copied into each window module.
--
-- WORKING_SOURCE: UnrealPfUI rotates these stock model frames with
-- SetRotation. The Button catcher and StartMoving/StopMoving pairing are the
-- UnrealUI path confirmed to deliver a matching OnDragStop on this client.
-- USER_CONFIRMED_INGAME: RegisterForDrag alone left Character spinning after
-- release; the throwaway StartMoving/StopMovingOrSizing followed by the real
-- StartMoving is the established mover recipe that fixed that lifecycle.
function U.EnableStockModelDrag(model, options)
  options = options or {}
  if options.leftButton then pcall(options.leftButton.Hide, options.leftButton) end
  if options.rightButton then pcall(options.rightButton.Hide, options.rightButton) end
  if not model then return nil end
  if model.uuiModelRotateCatcher then return model.uuiModelRotateCatcher end

  local ticker = options.ticker or "stock-model-rotate"
  local speed = tonumber(options.speed) or 0.01
  local created, catcher = pcall(CreateFrame, "Button", options.name, model)
  if not created or not catcher then return nil end

  local state = { rotation = 0, lastX = nil }
  model.uuiModelRotateCatcher = catcher
  catcher.uuiModelRotateState = state

  pcall(catcher.SetAllPoints, catcher, model)
  pcall(catcher.EnableMouse, catcher, true)
  pcall(catcher.RegisterForDrag, catcher, "LeftButton")

  local function StopDrag()
    U.UnregisterUpdate(ticker)
    state.lastX = nil
  end

  local function LeftButtonStillDown()
    local fn = U.G("IsMouseButtonDown")
    if type(fn) ~= "function" then return true end
    local ok, down = pcall(fn, "LeftButton")
    if not ok then return true end
    return down and true or false
  end

  local function LiveDrag()
    if not LeftButtonStillDown() then
      StopDrag()
      return
    end

    local cursor = U.G("GetCursorPosition")
    if type(cursor) ~= "function" then return end
    local ok, x = pcall(cursor)
    if not ok or not tonumber(x) then return end

    local scale = 1
    local scaleOk, value = pcall(model.GetEffectiveScale, model)
    if scaleOk and tonumber(value) and value > 0 then scale = value end
    x = x / scale

    if state.lastX then
      state.rotation = state.rotation + (x - state.lastX) * speed
      pcall(model.SetRotation, model, state.rotation)
    end
    state.lastX = x
  end

  catcher:SetScript("OnDragStart", function()
    if not pcall(catcher.SetMovable, catcher, true) then return end
    if pcall(catcher.StartMoving, catcher) then
      pcall(catcher.StopMovingOrSizing, catcher)
    end
    if not pcall(catcher.StartMoving, catcher) then return end

    state.lastX = nil
    U.RegisterUpdate(ticker, 0, LiveDrag)
  end)
  catcher:SetScript("OnDragStop", function()
    StopDrag()
    pcall(catcher.StopMovingOrSizing, catcher)
    pcall(function()
      catcher:ClearAllPoints()
      catcher:SetAllPoints(model)
    end)
  end)

  return catcher
end

-- Reset native FontObject attachment before trying the measured font adapter.
-- Emberveil can otherwise retain the decorative book font after SetFont.
function U.SetStockFont(fontstring, size, color, fontObject)
  if not fontstring then return false end

  local inherited = fontObject or U.G("GameFontNormal")
  if inherited and fontstring.SetFontObject then
    pcall(fontstring.SetFontObject, fontstring, inherited)
  end

  local applied = U.SetFont(fontstring, size or M.fontSize.normal)
  if type(color) == "table" and fontstring.SetTextColor then
    pcall(fontstring.SetTextColor, fontstring, M.Unpack(color))
  end
  return applied
end

-- Left-aligns a single-line stock FontString by shrinking its box to its own
-- text. SetJustifyH is not reliable after a SetFontObject rebind: /uui qlalign
-- (2026-09-13, UnrealUIDiagDB.questLogAlign) measured fixed-width TOPLEFT boxes
-- still drawing their text centred. The native width is remembered once and is
-- the ceiling, so a long line still wraps where it did before.
--
-- Failed approach (USER_CONFIRMED_INGAME 2026-09-13): adding a second TOPRIGHT
-- point derived from GetPoint broke the Quest Log details layout.
function U.FitLineToText(object)
  if not object then return end
  pcall(object.SetJustifyH, object, "LEFT")
  if not object.uuiNativeWidth then
    local ok, width = pcall(object.GetWidth, object)
    if not ok or not tonumber(width) or width <= 0 then return end
    object.uuiNativeWidth = width
  end
  local width = object.uuiNativeWidth
  -- Back to full width BEFORE measuring (USER_CONFIRMED_INGAME 2026-09-13): a
  -- box shrunk for a previous, shorter text reports only its wrapped width.
  pcall(object.SetWidth, object, width)
  local ok, textWidth = pcall(object.GetStringWidth, object)
  textWidth = ok and tonumber(textWidth) or 0
  -- +2 absorbs rounding so a line that fits is not wrapped by its own box.
  if textWidth > 0 and textWidth + 2 < width then width = textWidth + 2 end
  pcall(object.SetWidth, object, width)
  -- What this width was measured against, so a caller that cannot know when
  -- the string changed can ask. A box fitted to one text and then filled with
  -- a longer one wraps inside its own shrunk width, and nothing in the native
  -- refresh path fires when another addon writes the string directly.
  local textOk, text = pcall(object.GetText, object)
  object.uuiFitText = textOk and text or nil
end

-- True when `object` was fitted against a different string than it now shows.
-- Cheap enough for a poll: one GetText and a compare, no geometry touched.
function U.FitLineIsStale(object)
  if not object or not object.uuiNativeWidth then return false end
  local ok, text = pcall(object.GetText, object)
  if not ok then return false end
  return (text or "") ~= (object.uuiFitText or "")
end

function U.StockRegionKeep(frame, extra)
  local keep = {}
  if frame and frame.uuiFill then keep[frame.uuiFill] = true end
  if frame and type(frame.uuiEdges) == "table" then
    local i
    for i = 1, table.getn(frame.uuiEdges) do
      keep[frame.uuiEdges[i]] = true
    end
  end
  if extra and extra.icon then keep[extra.icon] = true end
  if extra and type(extra.keep) == "table" then
    local region, value
    for region, value in pairs(extra.keep) do
      if value then keep[region] = true end
    end
  end
  return keep
end

function U.StripStockTextures(frame, extra)
  return U.StripTextures(frame, U.StockRegionKeep(frame, extra))
end

-- ---------------------------------------------------------------------------
-- Stock list rows that carry a meaningful per-row icon
--
-- rules/unreal-ui-design.md keeps content imagery (the NPC dialog's "talk to
-- the banker" / "train me" / "!" / "?" glyphs) while stripping row chrome.
-- Keeping it by global name alone is not enough on this client:
--
--  * the region names for these rows are WORKING_SOURCE from UnrealPfUI, so a
--    single missed name silently strips a real icon, and
--  * U.HideRegion is deliberately permanent (SetTexture(nil) + SetAlpha(0) +
--    Hide, per knowledge.json / rendering.native_texture_strip_requires_alpha).
--    A row that was empty when unrealUI first stripped it keeps alpha 0 after
--    FrameXML repopulates it, because the native update only calls SetTexture
--    -- it never restores alpha or shown state. That is invisible-icon-forever.
--
-- So rows are stripped by *what the texture is* rather than by name, and every
-- kept icon is actively revealed again on each pass.
local CONTENT_ICON_PATHS = {
  "gossipicon",        -- Interface\GossipFrame\<token>GossipIcon
  "questicon",         -- Available/ActiveQuestIcon and the quest row markers
  "interface\\icons\\",  -- ability/item art, should a row ever use it
  "interface/icons/",
}

local function IsContentIconTexture(region)
  if not region or not region.GetObjectType or not region.GetTexture then
    return false
  end

  local typeOk, objectType = pcall(region.GetObjectType, region)
  if not typeOk or objectType ~= "Texture" then return false end

  local pathOk, path = pcall(region.GetTexture, region)
  if not pathOk or type(path) ~= "string" then return false end

  path = string.lower(path)
  local i
  for i = 1, table.getn(CONTENT_ICON_PATHS) do
    if string.find(path, CONTENT_ICON_PATHS[i], 1, true) then return true end
  end
  return false
end

-- Undo an earlier U.HideRegion on a region that turned out to be content.
function U.RestoreContentIcon(region)
  if not region then return false end
  pcall(function() if region.SetAlpha then region:SetAlpha(1) end end)
  pcall(function()
    if region.SetVertexColor then region:SetVertexColor(1, 1, 1) end
  end)
  pcall(function() if region.Show then region:Show() end end)
  return true
end

-- Strip a stock list row's native chrome, keep its content icon, and make sure
-- that icon is actually visible afterwards. `extra.icon` is still honoured as
-- the named hint; texture-path detection is the safety net behind it.
function U.StripStockRowTextures(button, extra)
  if not button then return 0 end

  local keep = U.StockRegionKeep(button, extra)
  local icons = {}
  if extra and extra.icon then table.insert(icons, extra.icon) end

  if button.GetRegions then
    local ok, regions = pcall(function() return { button:GetRegions() } end)
    if ok and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        if IsContentIconTexture(regions[i]) then
          keep[regions[i]] = true
          table.insert(icons, regions[i])
        end
      end
    end
  end

  local stripped = U.StripTextures(button, keep)

  -- Only the icons, never unrealUI's own fill/edge regions in `keep`.
  local i
  for i = 1, table.getn(icons) do
    U.RestoreContentIcon(icons[i])
  end

  return stripped
end

-- Recolours every FontString under a stock window, found by walking regions and
-- children rather than by name.
--
-- USER_CONFIRMED_INGAME (modules/gossip.lua): stock NPC dialog body text came
-- back native black-on-parchment against unrealUI's dark panel, unreadable.
-- The greeting/body fontstrings of the NPC dialogs have no confirmed field
-- names in either compact evidence or UnrealPfUI's skin, so recolouring by
-- enumeration is correct regardless of what this client names them.
--
-- Shared here rather than duplicated because modules/gossip.lua and
-- modules/quest.lua both need it.
--
-- USER_CONFIRMED_INGAME: a bare SetTextColor pass is NOT enough on this client.
-- The NPC quest dialog kept its gold decorative book text after every string
-- under QuestFrame had been recoloured -- the giveaway was that the *font* was
-- still the serif book face too, not just the colour. These stock strings carry
-- a native FontObject (QuestFont and friends) whose face and colour keep
-- winning, which is exactly the case U.SetStockFont above exists for: it
-- detaches the FontObject first, then sets the measured font, then the colour.
-- modules/questlog.lua reads as plain white for the same reason -- every string
-- it touches goes through U.SetStockFont, never a raw SetTextColor.
--
-- So this walks the same way but applies the full stock-font treatment to each
-- FontString it finds. `size` is applied uniformly (default normal); a caller
-- that wants a larger title re-applies U.SetStockFont to that one string after
-- this pass, the ordering modules/quest.lua and modules/gossip.lua both use.
-- Bounded recursion depth guards against an unexpected frame cycle.
function U.ForceStockTextWhite(object, color, size, depth)
  if not object then return end
  color = color or M.color.text
  size = size or M.fontSize.normal
  depth = depth or 0
  if depth > 8 then return end

  -- Emberveil's SimpleHTML uses integer 0..255 channels, unlike FontString's
  -- 0..1 SetTextColor contract. The NPC diagnostic exposed generated
  -- MyVasyanFontObject_* strings alongside greeting content, so apply the
  -- owner-level contract whenever recursion identifies a real SimpleHTML.
  if object.GetObjectType and object.SetTextColor then
    local typeOk, objectType = pcall(object.GetObjectType, object)
    if typeOk and objectType == "SimpleHTML" then
      pcall(object.SetTextColor, object, 255, 255, 255)
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
            U.SetStockFont(region, size, color)
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
        U.ForceStockTextWhite(children[i], color, size, depth + 1)
      end
    end
  end
end

local function ClearButtonFaces(button, keep)
  local getters = {
    "GetNormalTexture", "GetHighlightTexture",
    "GetPushedTexture", "GetDisabledTexture",
  }
  local setters = {
    "SetNormalTexture", "SetHighlightTexture",
    "SetPushedTexture", "SetDisabledTexture",
  }

  local i
  for i = 1, table.getn(getters) do
    local getter = button[getters[i]]
    if type(getter) == "function" then
      local ok, texture = pcall(getter, button)
      if ok and texture and not keep[texture] then U.HideRegion(texture) end
    end
  end

  for i = 1, table.getn(setters) do
    local setter = button[setters[i]]
    -- WORKING_SOURCE (UnrealPfUI api/ui-widgets.lua SkinButton): this client
    -- keeps drawing a button face after Set*Texture(nil); "" is the call
    -- shape that source uses successfully, so it is tried first here too.
    if type(setter) == "function" then
      if not pcall(setter, button, "") then pcall(setter, button, nil) end
    end
  end

  U.StripTextures(button, keep)
  pcall(button.SetBackdropBorderColor, button, 0, 0, 0, 0)
end

function U.StyleStockButton(button, options)
  if not button then return nil end
  options = options or {}

  if not button.uuiStockStyled then
    button.uuiStockStyled = true
    local keep = U.StockRegionKeep(button, options)
    ClearButtonFaces(button, keep)

    U.CreateBackdrop(button, {
      background = options.background or { 0.03, 0.03, 0.03, 0.82 },
      border = options.border or M.color.border,
    })

    U.PostHookScript(button, "OnEnter", function()
      U.SetBorderColor(button, M.Unpack(options.hoverBorder or M.color.accent))
    end)
    U.PostHookScript(button, "OnLeave", function()
      U.SetBorderColor(button, M.Unpack(options.border or M.color.border))
    end)
  end

  local icon = options.icon
  if icon then
    pcall(function()
      icon:Show()
      icon:SetAlpha(1)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      if options.fitIcon ~= false then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
      end
    end)
  end

  local ok, fontstring = false, nil
  if button.GetFontString then
    ok, fontstring = pcall(button.GetFontString, button)
  end
  if ok and fontstring then
    U.SetStockFont(fontstring, options.fontSize or M.fontSize.normal,
                   options.textColor or M.color.text)
    U.CenterButtonLabel(fontstring, button)
  end

  return button
end

-- Native SpellBook_Update can restore button faces. Re-run the narrow clear
-- while preserving the real spell icon and unrealUI's own border textures.
function U.RefreshStockButtonArtwork(button, icon)
  if not button then return end
  local options = { icon = icon }
  ClearButtonFaces(button, U.StockRegionKeep(button, options))
  if icon then
    pcall(function()
      icon:Show()
      icon:SetAlpha(1)
    end)
  end
end

local function EnsureGlyph(button, field, text, color, size)
  local label = button[field]
  if not label then
    label = U.CreateLabel(button, {
      size = size or M.fontSize.small,
      color = color or M.color.text,
      inherits = "GameFontNormal",
    })
    button[field] = label
    if label then label:SetPoint("CENTER", button, "CENTER", 0, 0) end
  end
  if label then
    label:SetText(text or "")
    pcall(label.SetTextColor, label, M.Unpack(color or M.color.text))
  end
  return label
end

function U.StyleStockCloseButton(button, parent, x, y)
  if not button then return nil end
  U.StyleStockButton(button, { hoverBorder = M.color.closeGlyph })
  pcall(button.SetWidth, button, 17)
  pcall(button.SetHeight, button, 17)
  -- Normalize the hit rect to the new 17x17 bounds rather than whatever inset
  -- the native (larger) close button carried. DOCUMENTED_NOT_RUNTIME_VERIFIED
  -- (Frame:SetHitRectInsets). The actual top-half hover loss on friends/
  -- spellbook was core/windowdrag.lua's raised drag handle overlapping the
  -- button when it's anchored to an inset panel -- see MakeWindowDraggable
  -- headerInset at those call sites.
  pcall(button.SetHitRectInsets, button, 0, 0, 0, 0)
  if parent then
    pcall(function()
      button:ClearAllPoints()
      button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or -6, y or -6)
    end)
  end
  local glyph = EnsureGlyph(button, "uuiCloseGlyph", "X", M.color.closeGlyph,
                            M.fontSize.small)
  if glyph then
    glyph:ClearAllPoints()
    glyph:SetPoint("CENTER", button, "CENTER", 0, -2)
  end
  return button
end

function U.StyleStockArrowButton(button, direction, size)
  if not button then return nil end
  U.StyleStockButton(button)

  -- Arrow buttons are commonly reduced from their native dimensions. Preserve
  -- a usable mouse target instead of carrying the old positive insets into the
  -- smaller frame (which can collapse the clickable rectangle completely).
  -- Official client documentation confirms negative insets expand the hit
  -- rectangle; UnrealPfUI's working same-client SkinArrowButton uses -3 here.
  pcall(button.SetHitRectInsets, button, -3, -3, -3, -3)

  if size then
    pcall(button.SetWidth, button, size)
    pcall(button.SetHeight, button, size)
  end

  local glyphs = { left = "<", right = ">", up = "^", down = "v" }
  local key = type(direction) == "string" and string.lower(direction) or "right"
  EnsureGlyph(button, "uuiArrowGlyph", glyphs[key] or ">", M.color.text,
              M.fontSize.normal)
  return button
end

function U.StyleStockScrollbar(scrollbar)
  if not scrollbar then return nil end

  local name
  if scrollbar.GetName then
    local ok, value = pcall(scrollbar.GetName, scrollbar)
    if ok then name = value end
  end

  local up = name and U.G(name .. "ScrollUpButton") or nil
  local down = name and U.G(name .. "ScrollDownButton") or nil
  U.StyleStockArrowButton(up, "up", 16)
  U.StyleStockArrowButton(down, "down", 16)

  if not scrollbar.uuiTrack and up and down then
    local track = U.CreatePanel(scrollbar, {
      width = 16,
      height = 40,
      background = { 0.02, 0.02, 0.02, 0.82 },
    })
    track:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, -2)
    track:SetPoint("BOTTOMRIGHT", down, "TOPRIGHT", 0, 2)
    scrollbar.uuiTrack = track
  end

  if scrollbar.GetThumbTexture then
    local ok, thumb = pcall(scrollbar.GetThumbTexture, scrollbar)
    if ok and thumb then
      pcall(thumb.SetTexture, thumb, M.texture.plain)
      U.SetColor(thumb, 0.72, 0.72, 0.72, 0.85)
    end
  end
  return scrollbar
end

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
    ClearButtonFaces(button, U.StockRegionKeep(button))
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

  StyleArrow(name and U.G(name .. "ScrollUpButton"), token.arrow.up,
             "BOTTOM", "TOP", token.arrow.gap)
  StyleArrow(name and U.G(name .. "ScrollDownButton"), token.arrow.down,
             "TOP", "BOTTOM", -token.arrow.gap)

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
    bottom = thumb:CreateTexture(nil, "ARTWORK"),
  }
  art.top:SetWidth(token.thumb.width)
  art.top:SetHeight(token.thumb.topExtent)
  art.top:SetPoint("TOP", thumb, "TOP", 0, 0)
  art.bottom:SetWidth(token.thumb.width)
  art.bottom:SetHeight(token.thumb.bottomExtent)
  art.bottom:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  art.middle:SetWidth(token.thumb.width)
  art.middle:SetPoint("TOP", art.top, "BOTTOM", 0, 0)
  art.middle:SetPoint("BOTTOM", art.bottom, "TOP", 0, 0)

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

-- Retargets a native StatusBar's fill to unrealUI's flat texture and strips
-- every other native texture off it, keeping the fill itself.
--
-- The keep set is the whole point. GetStatusBarTexture is absent on this
-- client, so the live fill cannot be asked for directly -- it is located among
-- the bar's direct Texture regions by the path SetStatusBarTexture just gave
-- it. Stripping without that identification is the confirmed empty-bar
-- failure: the strip hides the fill, and a later SetStatusBarTexture writes a
-- path onto a region that is already hidden, so the bar renders as nothing at
-- all. It happened first on the reputation rows and again on the pet page's
-- experience bar.
--
-- Returns false without touching the bar when the fill cannot be identified,
-- so a caller fails closed to the native bar rather than to an invisible one.
--
-- options: color (fill), background, border, hideBorder
function U.StyleStockStatusBar(bar, options)
  if not bar then return false end
  options = options or {}

  if not pcall(bar.SetStatusBarTexture, bar, M.texture.plain) then
    return false
  end

  local keep, found = {}, false
  if bar.GetRegions then
    local regionsOk, regions = pcall(function() return { bar:GetRegions() } end)
    if regionsOk and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        if region and type(region.GetTexture) == "function" then
          local textureOk, texture = pcall(region.GetTexture, region)
          if textureOk and type(texture) == "string" and
             string.lower(texture) == string.lower(M.texture.plain) then
            keep[region] = true
            found = true
          end
        end
      end
    end
  end
  if not found then return false end

  U.StripStockTextures(bar, { keep = keep })

  if options.color then
    U.SetStatusBarColor(bar, M.Unpack(options.color))
  end

  U.CreateBackdrop(bar, {
    background = options.background or M.color.healthBg,
    border = options.border or M.color.border,
  })
  if options.hideBorder then
    pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 0)
  end
  return true
end

local function AlignTabText(button)
  if not button or not button.GetFontString then return end

  local ok, fontstring = pcall(button.GetFontString, button)
  if not ok or not fontstring then return end

  pcall(function()
    fontstring:ClearAllPoints()
    fontstring:SetPoint("CENTER", button, "CENTER", 0, TAB_TEXT_Y_OFFSET)
  end)
end

function U.StyleStockTab(button)
  if not button then return nil end
  U.StyleStockButton(button)
  pcall(button.SetHeight, button, 20)
  AlignTabText(button)
  return button
end

-- ---------------------------------------------------------------------------
-- Tab groups (flat, active/inactive aware)
--
-- U.StyleStockTab (above) reuses U.StyleStockButton, which only clears what
-- GetNormalTexture/GetHighlightTexture/GetPushedTexture/GetDisabledTexture
-- expose. The stock TabButtonTemplate draws its Left/Middle/Right pieces --
-- and a visibly different "selected" piece for whichever tab is currently
-- active -- as separate child Texture regions outside those four getters, so
-- that clear does not reach them. USER_CONFIRMED_INGAME: the Character
-- sheet's Honor tab kept its native beveled/selected look after
-- U.StyleStockTab for exactly this reason.
--
-- This is a separate, self-contained component rather than a change to
-- U.StyleStockTab, so existing callers (e.g. Spellbook's page tabs) keep
-- their current look; only screens that opt into U.StyleStockTabGroup get
-- the flat design and the owned active state below.
--
-- Native tab selection is driven by PanelTemplates_SetTab, which recolours
-- fontstrings and swaps the selected-tab art on its own schedule that
-- unrealUI does not hook. Rather than depend on that (or on an unverified
-- frame.selectedTab field), this owns active/inactive state entirely: each
-- tab gets a real SetActive(bool) and OnClick marks itself active and every
-- sibling inactive, so the flat highlight always matches the click that
-- produced it regardless of what the native frame does underneath.
-- ---------------------------------------------------------------------------
local function StyleGroupTab(button, options)
  if not button or button.uuiTabStyled then return button end
  button.uuiTabStyled = true

  ClearButtonFaces(button, {})
  U.StripTextures(button, U.StockRegionKeep(button, {}))

  local inactiveBg = options.background or { 0.03, 0.03, 0.03, 0.82 }
  U.CreateBackdrop(button, { background = inactiveBg, border = M.color.border })
  pcall(button.SetHeight, button, options.height or 22)
  AlignTabText(button)

  button.uuiTabActive = false

  local function RefreshFont()
    local ok, fontstring = false, nil
    if button.GetFontString then
      ok, fontstring = pcall(button.GetFontString, button)
    end
    if ok and fontstring then
      U.SetStockFont(fontstring, options.fontSize or M.fontSize.small,
        button.uuiTabActive and M.color.textAccent or M.color.text)
    end
  end
  button.uuiTabRefreshFont = RefreshFont

  local function Refresh()
    -- Selection is intentionally communicated through the label alone: every
    -- tab retains the same neutral surface and border in both states.
    U.SetBackgroundColor(button, M.Unpack(inactiveBg))
    U.SetBorderColor(button, M.Unpack(M.color.border))
    RefreshFont()
  end
  button.uuiTabRefresh = Refresh

  button.SetActive = function(active)
    button.uuiTabActive = active and true or false
    Refresh()
  end

  button:SetScript("OnEnter", function()
    if not button.uuiTabActive then
      U.SetBorderColor(button, M.Unpack(M.color.accentDim))
    end
  end)
  button:SetScript("OnLeave", Refresh)

  Refresh()
  return button
end

-- Re-anchors an ordered array of stock tab buttons into a single LEFT-to-RIGHT
-- strip with a fixed gap, skipping past any tab that is not currently shown
-- rather than chaining off it. A hidden tab (e.g. the Character sheet's Pet
-- slot with no pet out) still occupies its array index but must not be
-- chained into, or the tab after it would inherit a gap sized to an invisible
-- button -- WORKING_SOURCE from UnrealPfUI's own skins, which guard the same
-- chain on lastTab:IsShown(). Shared by every multi-tab stock window
-- (Character, Friends, ...) instead of each module re-deriving it.
function U.ChainStockTabs(tabs, gap)
  if type(tabs) ~= "table" then return end
  gap = gap or 3

  local previous = nil
  local i
  for i = 1, table.getn(tabs) do
    local tab = tabs[i]
    if tab then
      if previous then
        local shownOk, shown = pcall(previous.IsShown, previous)
        if shownOk and shown then
          pcall(function()
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", previous, "RIGHT", gap, 0)
          end)
        end
      end
      previous = tab
    end
  end
end

-- Label width of a stock tab, or nil when the client will not report one.
-- FontString:GetStringWidth is measured on this client (behavior.json /
-- chat.shadow_matrix_*.v2 return real numbers from it), and is the only read
-- that gives a tab's text extent independently of the width the native
-- template happened to give the button.
local function TabLabelWidth(tab)
  if not tab or not tab.GetFontString then return nil end

  local ok, fontstring = pcall(tab.GetFontString, tab)
  if not ok or not fontstring then return nil end

  if fontstring.GetStringWidth then
    local widthOk, width = pcall(fontstring.GetStringWidth, fontstring)
    if widthOk and tonumber(width) and width > 0 then return width end
  end
  if fontstring.GetWidth then
    local widthOk, width = pcall(fontstring.GetWidth, fontstring)
    if widthOk and tonumber(width) and width > 0 then return width end
  end
  return nil
end

-- Sizes a chained tab strip from its labels instead of from the widths the
-- native template baked in, and starts it flush with the window's left inset.
--
-- Written for the Character sheet's conditional Pet tab: the native widths are
-- generous enough that a fifth tab ran past the window edge. Scaling those
-- widths down proportionally was not enough, because the padding is where the
-- slack actually is -- so each tab is rebuilt as label + padding, and the
-- padding is the single value reduced until the whole run fits. Text is never
-- squeezed: if even the labels plus the minimum padding do not fit, the run
-- keeps that minimum and the caller is told so by the return value.
--
-- options:
--   gap         between tabs (default 3, the shared tab-strip gap)
--   left        inset from the window's left edge for the first tab, which is
--               re-anchored there so the strip lines up with the window
--   right       inset reserved on the right (defaults to `left`, symmetric)
--   padding     preferred padding on each side of a label
--   minPadding  floor that padding is never reduced below
--   anchor      { frame, point, relativePoint, x, y } for the first tab; when
--               omitted the tab is put at `left` and keeps its native Y
-- Returns `fits, info`. `info` is a measurement record -- every number this
-- read and wrote, plus a `reason` when it did not size anything -- so a strip
-- that visibly ignores the fit can be diagnosed from the client instead of
-- from a second guess. `fits` is false when the run could not be brought
-- inside the window at the minimum padding, and nil when nothing was applied.
function U.FitStockTabStrip(tabs, frame, options)
  local info = { rows = {} }
  if type(tabs) ~= "table" or not frame then
    info.reason = "no tabs or no frame"
    return nil, info
  end
  options = options or {}

  local gap = tonumber(options.gap) or 3
  local left = tonumber(options.left) or 10
  local right = tonumber(options.right) or left
  local padding = tonumber(options.padding) or 10
  local minPadding = tonumber(options.minPadding) or 4

  local shown, labels, labelTotal = {}, {}, 0
  local i
  for i = 1, table.getn(tabs) do
    local tab = tabs[i]
    local visible = false
    if tab and tab.IsShown then
      local ok, value = pcall(tab.IsShown, tab)
      visible = ok and value and true or false
    end
    if visible then
      local width = TabLabelWidth(tab)
      if not width then
        info.reason = "no label width for tab " .. i
        return nil, info
      end
      table.insert(shown, tab)
      table.insert(labels, width)
      labelTotal = labelTotal + width
    end
  end

  local count = table.getn(shown)
  info.count = count
  info.labelTotal = labelTotal
  if count == 0 then
    info.reason = "no shown tabs"
    return nil, info
  end

  local first = shown[1]
  local frameWidthOk, frameWidth = pcall(frame.GetWidth, frame)
  if not frameWidthOk or not tonumber(frameWidth) then
    info.reason = "window width unreadable"
    return nil, info
  end
  info.frameWidth = frameWidth

  -- Where the run starts. An `anchor` names the frame the strip should hang
  -- off outright -- the window's own inset panel, for a window whose visible
  -- surface stops short of the frame edge -- which is how a strip is placed
  -- just below that surface instead of overlapping it.
  --
  -- Without one, only the horizontal start is taken over: the tab keeps
  -- whatever vertical placement the client gave it, re-derived from its own
  -- position rather than from an invented native offset.
  local anchor = options.anchor
  local anchorOk
  if type(anchor) == "table" and anchor.frame then
    anchorOk = pcall(function()
      first:ClearAllPoints()
      first:SetPoint(anchor.point or "TOPLEFT", anchor.frame,
                     anchor.relativePoint or "BOTTOMLEFT",
                     tonumber(anchor.x) or 0, tonumber(anchor.y) or 0)
    end)
  else
    local frameLeftOk, frameLeft = pcall(frame.GetLeft, frame)
    local frameBottomOk, frameBottom = pcall(frame.GetBottom, frame)
    local tabBottomOk, tabBottom = pcall(first.GetBottom, first)
    if not frameLeftOk or not frameBottomOk or not tabBottomOk
       or not tonumber(frameLeft) or not tonumber(frameBottom)
       or not tonumber(tabBottom) then
      info.reason = "window or tab geometry unreadable"
      return nil, info
    end
    anchorOk = pcall(function()
      first:ClearAllPoints()
      first:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left,
                     tabBottom - frameBottom)
    end)
  end
  info.anchored = anchorOk

  local available = frameWidth - left - right - (gap * (count - 1))
  info.available = available
  if available <= 0 then
    info.reason = "no room between the window insets"
    return nil, info
  end

  -- One padding value for the whole run, so the tabs keep a consistent inset
  -- rather than each shrinking by a different amount.
  local room = math.floor((available - labelTotal) / (count * 2))
  local fits = true
  if room < padding then
    padding = room
    if padding < minPadding then
      padding = minPadding
      fits = false
    end
  end
  info.padding = padding

  for i = 1, count do
    local tab = shown[i]
    local target = math.floor(labels[i] + (padding * 2))

    local beforeOk, before = pcall(tab.GetWidth, tab)
    pcall(tab.SetWidth, tab, target)
    local afterOk, after = pcall(tab.GetWidth, tab)

    local name = "?"
    if tab.GetName then
      local nameOk, value = pcall(tab.GetName, tab)
      if nameOk and value then name = value end
    end

    table.insert(info.rows, {
      name = name,
      label = labels[i],
      target = target,
      before = beforeOk and before or nil,
      after = afterOk and after or nil,
    })
  end
  return fits, info
end

-- `tabs` is an ordered array of stock tab buttons (nil entries are skipped
-- rather than breaking the group). `defaultIndex` is which one starts active
-- -- the native frame does not expose which tab it will reopen on, so this
-- always starts from the same one the sheet conventionally opens on, and
-- self-corrects on the first click either way.
function U.StyleStockTabGroup(tabs, defaultIndex, options)
  if type(tabs) ~= "table" then return end
  options = options or {}

  local function SelectIndex(selected)
    local i
    for i = 1, table.getn(tabs) do
      local tab = tabs[i]
      if tab and tab.SetActive then tab.SetActive(i == selected) end
    end
  end

  local i
  for i = 1, table.getn(tabs) do
    local tab = tabs[i]
    if tab then
      StyleGroupTab(tab, options)
      local index = i
      U.PostHookScript(tab, "OnClick", function() SelectIndex(index) end)
    end
  end

  SelectIndex(defaultIndex or 1)
end

-- Adapts an existing native CheckButton to unrealUI's shared checkbox chrome.
-- A numeric second argument remains supported; an options table additionally
-- lets stock screens opt into owned label spacing without creating local
-- checkbox variants.
function U.StyleStockCheckbox(button, sizeOrOptions)
  if not button then return nil end
  local options = type(sizeOrOptions) == "table" and sizeOrOptions or {
    size = sizeOrOptions,
  }
  U.StyleStockButton(button)

  local size = options.size
  if size then
    pcall(button.SetWidth, button, size)
    pcall(button.SetHeight, button, size)
  end
  U.SetBackgroundColor(button, M.Unpack(M.color.background))

  local function RefreshIndicator()
    -- The checked texture is native chrome, so suppress it every time the
    -- control refreshes.  HideRegion's clear + alpha-zero path is required on
    -- this client because a simple Hide can still leave stock art visible.
    if button.GetCheckedTexture then
      local textureOk, texture = pcall(button.GetCheckedTexture, button)
      if textureOk and texture then U.HideRegion(texture) end
    end

    local checked = false
    if button.GetChecked then
      local checkedOk, value = pcall(button.GetChecked, button)
      checked = checkedOk and value and true or false
    end
    U.SetCheckboxIndicator(button, checked)
  end

  if not button.uuiCheckboxIndicatorStyled then
    button.uuiCheckboxIndicatorStyled = true
    U.PostHookScript(button, "OnClick", RefreshIndicator)
    U.PostHookScript(button, "OnShow", RefreshIndicator)

    -- Some owned controls set their state after assigning a new OnClick
    -- handler.  Keep their indicator in sync without requiring a local
    -- checkbox variant or replacing the native checked-state implementation.
    if type(button.SetChecked) == "function" then
      local setChecked = button.SetChecked
      button.SetChecked = function(self, value)
        local result = setChecked(self, value)
        RefreshIndicator()
        return result
      end
    end
  end
  RefreshIndicator()

  if options.labelGap ~= nil or options.labelYOffset ~= nil then
    local label = options.label
    if not label and button.GetName then
      local nameOk, name = pcall(button.GetName, button)
      if nameOk and type(name) == "string" then label = U.G(name .. "Text") end
    end

    -- Some native templates do not export their label as <ButtonName>Text.
    -- Fall back to the first direct FontString region, never a Texture.
    if not label and button.GetRegions then
      local regionsOk, regions = pcall(function() return { button:GetRegions() } end)
      if regionsOk and type(regions) == "table" then
        local i
        for i = 1, table.getn(regions) do
          local region = regions[i]
          if region and region.GetObjectType then
            local typeOk, objectType = pcall(region.GetObjectType, region)
            if typeOk and objectType == "FontString" then
              label = region
              break
            end
          end
        end
      end
    end

    if label then
      pcall(function()
        label:ClearAllPoints()
        label:SetPoint("LEFT", button, "RIGHT",
                       tonumber(options.labelGap) or 0,
                       tonumber(options.labelYOffset) or 0)
      end)
      button.uuiCheckboxLabel = label
    end
  end
  return button
end

-- Quest rows use their normal texture to communicate header expand/collapse.
-- Replace only that picture with a small +/- box while leaving row scripts and
-- click behavior native.
--
-- Two Unreal-specific behaviours shape this, both USER_CONFIRMED_INGAME:
--
--  * UnrealPfUI's SkinCollapseButton (WORKING_SOURCE) drives icon visibility by
--    intercepting SetNormalTexture and calls SetNormalTexture(button, nil) once
--    to clear the stock picture. On this client that single nil call does not
--    remove it -- the red native +/- kept drawing on quest rows -- so the
--    underlying Texture object is cleared directly as well, and
--    SetNormalTexture is then made a permanent no-op so native refreshes can
--    never bring it back. Icon state is not inferred from texture calls at all:
--    the caller drives it from real quest data each refresh.
--
--  * mover.lua / CreateHandle established that a Button is the widget type this
--    client reliably delivers mouse input to. The stock row Button's own
--    OnClick did not collapse a quest header here, while the All button's did,
--    so the icon is a Button and carries the click itself. `uuiCollapseClick`
--    lets the caller own the action; with no override the click forwards to the
--    parent's native OnClick, which is what keeps the All button native.
function U.StyleStockCollapseButton(button, expandedSize)
  if not button or button.uuiCollapseStyled then return button end
  button.uuiCollapseStyled = true

  -- The box itself is the shared control (U.CreateCollapseButton in
  -- core/widgets.lua), which carries the size rule, the accent hover and the
  -- owned +/- glyph. Everything below is the part that is specific to adapting
  -- a *native* stock header: placing the box on the row and taking the client's
  -- own art and highlight out of the render.
  local icon = U.CreateCollapseButton(button, {
    size = expandedSize and 18 or 16,
    onClick = function()
      if type(button.uuiCollapseClick) == "function" then
        button.uuiCollapseClick(button)
        return
      end
      -- No override: hand the click straight back to the stock button so a
      -- control that already works natively keeps working.
      if button.GetScript then
        local scriptOk, native = pcall(button.GetScript, button, "OnClick")
        if scriptOk and native then pcall(native, button) end
      end
    end,
  })
  if not icon then return button end

  icon:SetPoint("LEFT", button, "LEFT", 2, 1)
  button.uuiCollapseIcon = icon

  if button.GetNormalTexture then
    local ok, native = pcall(button.GetNormalTexture, button)
    if ok and native then
      pcall(native.SetTexture, native, nil)
      pcall(native.SetAlpha, native, 0)
      pcall(native.Hide, native)
    end
  end
  local nativeSetNormal = button.SetNormalTexture
  if type(nativeSetNormal) == "function" then
    pcall(nativeSetNormal, button, nil)
    button.SetNormalTexture = function() end
  end

  local name
  if button.GetName then
    local ok, value = pcall(button.GetName, button)
    if ok then name = value end
  end
  if name then U.HideRegion(U.G(name .. "Highlight")) end

  -- Belt-and-suspenders past the by-name lookup above: GetHighlightTexture
  -- reaches the row's native hover art even when it is not exposed as a
  -- separately named "<name>Highlight" global (that lookup depends on a
  -- naming convention no compact-DB record confirms every stock row follows).
  -- USER_CONFIRMED_INGAME: on the Skills tab this leftover highlight is what
  -- lit up beside unrealUI's icon instead of on it, since its native anchor
  -- never matched the icon's new position/size.
  if button.GetHighlightTexture then
    local ok, highlight = pcall(button.GetHighlightTexture, button)
    if ok and highlight then U.HideRegion(highlight) end
  end
  if type(button.SetHighlightTexture) == "function" then
    if not pcall(button.SetHighlightTexture, button, "") then
      pcall(button.SetHighlightTexture, button, nil)
    end
  end

  return button
end

-- Sets a styled collapse icon's state. `nil` shown hides it entirely, which is
-- how non-header quest rows end up with no icon at all.
function U.SetStockCollapseState(button, shown, collapsed)
  local icon = button and button.uuiCollapseIcon
  if not icon then return false end

  if not shown then
    icon:Hide()
    return true
  end

  if type(icon.uuiSetCollapsed) == "function" then
    icon.uuiSetCollapsed(collapsed)
  elseif icon.text then
    icon.text:SetText(collapsed and "+" or "-")
  end
  icon:Show()
  return true
end
