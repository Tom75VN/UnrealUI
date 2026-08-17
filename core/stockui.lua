-- unrealUI :: core/stockui.lua
--
-- Small, capability-checked helpers for restyling native interface windows.
-- They reproduce only the stock-control treatment shared by the requested
-- Quest Log and Spellbook skins; this is not a general Blizzard-skin system.

local U = UnrealUI
local M = U.media

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
  if parent then
    pcall(function()
      button:ClearAllPoints()
      button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or -6, y or -6)
    end)
  end
  EnsureGlyph(button, "uuiCloseGlyph", "X", { 1, 0.25, 0.25, 1 },
              M.fontSize.small)
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

function U.StyleStockTab(button)
  if not button then return nil end
  U.StyleStockButton(button)
  pcall(button.SetHeight, button, 20)
  return button
end

function U.StyleStockCheckbox(button, size)
  if not button then return nil end
  local keep = {}
  if button.GetCheckedTexture then
    local ok, checked = pcall(button.GetCheckedTexture, button)
    if ok and checked then keep[checked] = true end
  end
  U.StyleStockButton(button, { keep = keep })
  if size then
    pcall(button.SetWidth, button, size)
    pcall(button.SetHeight, button, size)
  end
  return button
end

-- Quest rows use their normal texture to communicate header expand/collapse.
-- Replace only that picture with a small +/- box while leaving row scripts and
-- click behavior native.
function U.StyleStockCollapseButton(button, expandedSize)
  if not button or button.uuiCollapseStyled then return button end
  button.uuiCollapseStyled = true

  local size = expandedSize and 14 or 10
  local icon = U.CreatePanel(button, {
    width = size,
    height = size,
    background = { 0.03, 0.03, 0.03, 0.90 },
  })
  icon:SetPoint("LEFT", button, "LEFT", 2, 1)
  icon.text = U.CreateLabel(icon, {
    size = M.fontSize.small,
    color = M.color.text,
    inherits = "GameFontNormalSmall",
  })
  if icon.text then
    icon.text:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.text:SetText("-")
  end
  button.uuiCollapseIcon = icon

  local nativeSetNormal = button.SetNormalTexture
  if type(nativeSetNormal) == "function" then
    pcall(nativeSetNormal, button, nil)
    button.SetNormalTexture = function(self, texture)
      if not texture or texture == "" then
        icon:Hide()
      else
        local minus = type(texture) == "string" and
                      string.find(texture, "MinusButton", 1, true)
        if icon.text then icon.text:SetText(minus and "-" or "+") end
        icon:Show()
      end
    end
  end

  local name
  if button.GetName then
    local ok, value = pcall(button.GetName, button)
    if ok then name = value end
  end
  if name then U.HideRegion(U.G(name .. "Highlight")) end
  return button
end
