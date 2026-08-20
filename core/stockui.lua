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
  U.StyleStockButton(button, { hoverBorder = { 1, 0.25, 0.25, 1 } })
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
  local glyph = EnsureGlyph(button, "uuiCloseGlyph", "X", { 1, 0.25, 0.25, 1 },
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

  local function Refresh()
    -- Selection is intentionally communicated through the label alone: every
    -- tab retains the same neutral surface and border in both states.
    U.SetBackgroundColor(button, M.Unpack(inactiveBg))
    U.SetBorderColor(button, M.Unpack(M.color.border))

    local ok, fontstring = false, nil
    if button.GetFontString then
      ok, fontstring = pcall(button.GetFontString, button)
    end
    if ok and fontstring then
      U.SetStockFont(fontstring, options.fontSize or M.fontSize.small,
        button.uuiTabActive and M.color.textAccent or M.color.text)
    end
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
local collapseIconCount = 0

function U.StyleStockCollapseButton(button, expandedSize)
  if not button or button.uuiCollapseStyled then return button end
  button.uuiCollapseStyled = true

  -- USER_CONFIRMED_INGAME: SetHitRectInsets with negative values (tried here
  -- previously to pad a small icon's click area) made the icon's left portion
  -- unclickable instead of expanding the hit area -- this client does not
  -- treat negative insets as "grow outward" the way retail does. No
  -- compact-DB record covers SetHitRectInsets at all, so rather than guess at
  -- a second sign/clamp convention, the icon is simply built larger: its real
  -- clickable frame size now matches what a comfortable click target needs,
  -- with no inset call at all.
  local size = expandedSize and 18 or 16
  collapseIconCount = collapseIconCount + 1

  local created, icon = pcall(CreateFrame, "Button",
    "UnrealUICollapseIcon" .. collapseIconCount, button)
  if not created or not icon then return button end

  icon:SetWidth(size)
  icon:SetHeight(size)
  icon:SetPoint("LEFT", button, "LEFT", 2, 1)
  U.CreateBackdrop(icon, { background = { 0.03, 0.03, 0.03, 0.90 } })
  pcall(icon.EnableMouse, icon, true)

  local levelOk, level = pcall(button.GetFrameLevel, button)
  if levelOk and tonumber(level) then
    pcall(icon.SetFrameLevel, icon, level + 2)
  end

  -- unrealUI's own hover feedback: the icon's border brightens to the addon
  -- accent, matching every other stock control's OnEnter/OnLeave treatment.
  -- This replaces relying on the row's native highlight (below), whose fixed
  -- native anchor is what previously made the hover glow appear beside the
  -- icon instead of on it.
  icon:SetScript("OnEnter", function()
    U.SetBorderColor(icon, M.Unpack(M.color.accent))
  end)
  icon:SetScript("OnLeave", function()
    U.SetBorderColor(icon, M.Unpack(M.color.border))
  end)

  -- knowledge.json / buttons.plain_settext_no_fontstring: an untemplated Button
  -- accepts SetText without ever showing a FontString, so the +/- glyph has to
  -- be a FontString unrealUI creates and owns.
  icon.text = U.CreateLabel(icon, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if icon.text then
    icon.text:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.text:SetText("-")
  end

  icon:SetScript("OnClick", function()
    if type(button.uuiCollapseClick) == "function" then
      local ok, err = pcall(button.uuiCollapseClick, button)
      if not ok then U.Error("collapse click: " .. tostring(err)) end
      return
    end
    -- No override: hand the click straight back to the stock button so a
    -- control that already works natively keeps working.
    if button.GetScript then
      local scriptOk, native = pcall(button.GetScript, button, "OnClick")
      if scriptOk and native then pcall(native, button) end
    end
  end)

  icon:Hide()
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

  if icon.text then icon.text:SetText(collapsed and "+" or "-") end
  icon:Show()
  return true
end
