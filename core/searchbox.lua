-- unrealUI :: core/searchbox.lua
--
-- The one search field of the addon (user request, 2026-09-24): the game
-- settings window, the bag, the live bank and the saved bank all build it
-- here, so an improvement to it reaches every one of them. What it looks like
-- is a per-theme style (SB.styles, chosen by SB.THEME_STYLE); how it behaves
-- is the same everywhere.
--
-- It is addon-drawn, not an EditBox (user decision, 2026-09-24). This client
-- gives an addon no way to know that a native EditBox has keyboard focus (no
-- HasFocus / GetCurrentKeyBoardFocus in compact evidence), scripting one has
-- crashed it (knowledge.json / widgets.editbox_focus_crash), and a focused one
-- lets keys through to the binding layer, so a spell bound to a letter was cast
-- while its name was typed (user report, 2026-09-24). An owned field knows its
-- own state instead:
--
--   * A click on the field opens typing mode. The shared key catcher -- a plain
--     Frame with EnableKeyboard(true), shown only while the mode is open, the
--     Quick-Bind pattern (knowledge.json / scripts.keyboard_frame_captures_
--     all_input, scripts.keyboard_frame_only_keydown_arg1) -- takes the
--     keyboard, reads each key name from the legacy arg1 global, and turns it
--     into text. Movement and chat are unavailable while it is open, like a
--     chat line.
--   * The binding layer resolves a bound key before an addon frame hears it
--     (see modules/quickbind.lua), so the keys that type are taken off the
--     client while the mode is open and put back after (SB.HoldKeys), and
--     modules/actionbar.lua's TextInputBlocksActionKey also asks
--     U.SearchBoxTyping() as a second gate for action keys.
--   * The caret is an owned blinking texture, shown from the click on, so an
--     empty field shows where typing will go.
--   * Enter, Tab or Escape, the magnifier, the clear button, the owner hiding
--     the field, entering combat and leaving the world all leave the mode.
--     Escape is one of the held keys, so it only ends typing. The mode never
--     opens in combat.
--
-- Only what a key name can carry is typed: letters, digits, space and plain
-- punctuation. Matching folds Latin accents (U.SearchFold), so "epee" finds
-- "Epee" written with accents.

local U = UnrealUI
local M = U.media

local SB = {
  MAX_LETTERS = 40,
  BLINK = 0.5,
  BACKSPACE_CHAR = "\008",
  active = nil,    -- the field in typing mode
}

-- ---------------------------------------------------------------------------
-- Styles
--
-- Each theme names the style its fields draw. Every theme currently uses
-- Forever's SearchBoxTemplate art (M.foreverWow.search), the field the game
-- settings window was built with; a new look is added as a style here and
-- mapped to its theme, and every search field in the addon follows.
-- ---------------------------------------------------------------------------
SB.THEME_STYLE = {
  ["modern"] = "forever",
  ["modern-wow"] = "forever",
  ["classic-wow"] = "forever",
}

function SB.SetCell(texture, cell, sheetWidth, sheetHeight)
  pcall(texture.SetTexCoord, texture, cell[1] / sheetWidth, cell[2] / sheetWidth,
        cell[3] / sheetHeight, cell[4] / sheetHeight)
end

SB.styles = {}

-- Forever's SettingsPanel.SearchBox (SearchBoxTemplate): a three-slice bed,
-- the magnifier and clear icons from the same sheet, grey placeholder.
SB.styles.forever = {
  token = function() return M.foreverWow and M.foreverWow.search end,

  bed = function(box, token)
    local border = token.border
    local function Piece(cell)
      local texture = box:CreateTexture(nil, "BACKGROUND")
      texture:SetTexture(border.texture)
      SB.SetCell(texture, cell, border.sheetWidth, border.sheetHeight)
      texture:SetHeight(border.height)
      return texture
    end
    local left = Piece(border.left)
    local middle = Piece(border.middle)
    local right = Piece(border.right)
    left:SetWidth(border.capWidth)
    left:SetPoint("LEFT", box, "LEFT", -5, 0)
    right:SetWidth(border.capWidth)
    right:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
    middle:SetPoint("RIGHT", right, "LEFT", 0, 0)
  end,

  icon = function(button, token, cell)
    local icons = token.icons
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(icons.texture)
    SB.SetCell(icon, cell, icons.sheetWidth, icons.sheetHeight)
    icon:SetWidth(icons.size)
    icon:SetHeight(icons.size)
    return icon
  end,

  textColor = { 1, 1, 1 },
  placeholderColor = { 0.58, 0.58, 0.58, 1 },
  caretColor = { 1, 1, 1 },
}

function SB.Style()
  local theme = type(U.GetActiveThemeStyle) == "function" and
                U.GetActiveThemeStyle() or nil
  return SB.styles[SB.THEME_STYLE[theme] or "forever"] or SB.styles.forever
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

-- Latin letters with a diacritic, as their UTF-8 pairs, to the plain letter.
SB.FOLD = {
  ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a",
  ["\195\164"] = "a", ["\195\165"] = "a", ["\195\128"] = "a", ["\195\129"] = "a",
  ["\195\130"] = "a", ["\195\131"] = "a", ["\195\132"] = "a", ["\195\133"] = "a",
  ["\195\166"] = "ae", ["\195\134"] = "ae",
  ["\195\167"] = "c", ["\195\135"] = "c",
  ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
  ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e",
  ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
  ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i",
  ["\195\177"] = "n", ["\195\145"] = "n",
  ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o",
  ["\195\182"] = "o", ["\195\184"] = "o", ["\195\146"] = "o", ["\195\147"] = "o",
  ["\195\148"] = "o", ["\195\149"] = "o", ["\195\150"] = "o", ["\195\152"] = "o",
  ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
  ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u",
  ["\195\189"] = "y", ["\195\191"] = "y", ["\195\157"] = "y",
  ["\195\159"] = "ss",
  ["\197\147"] = "oe", ["\197\146"] = "oe",
}

-- Lowercase with Latin accents folded away, for matching typed text (which
-- carries no accents) against names that do.
function U.SearchFold(text)
  if type(text) ~= "string" then return "" end
  text = string.gsub(text, "[\195\197][\128-\191]", function(pair)
    return SB.FOLD[pair] or pair
  end)
  return string.lower(text)
end

-- Key names this client reports for keys that type something other than
-- their own name.
SB.KEY_TEXT = {
  SPACE = " ", MINUS = "-", EQUALS = "=", PERIOD = ".", COMMA = ",",
  APOSTROPHE = "'", SEMICOLON = ";", SLASH = "/",
  NUMPADMINUS = "-", NUMPADPLUS = "+", NUMPADDECIMAL = ".",
  NUMPADDIVIDE = "/", NUMPADMULTIPLY = "*",
  NUMPAD0 = "0", NUMPAD1 = "1", NUMPAD2 = "2", NUMPAD3 = "3", NUMPAD4 = "4",
  NUMPAD5 = "5", NUMPAD6 = "6", NUMPAD7 = "7", NUMPAD8 = "8", NUMPAD9 = "9",
}

SB.LEAVE_KEYS = { ESCAPE = true, ENTER = true, NUMPADENTER = true, TAB = true }

function SB.Held(name)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  local ok, held = pcall(fn)
  return ok and held and held ~= 0 and true or false
end

-- The text one key press types, or nil.
function SB.KeyText(key)
  if type(key) ~= "string" or key == "" then return nil end
  if SB.Held("IsControlKeyDown") or SB.Held("IsAltKeyDown") then return nil end
  local mapped = SB.KEY_TEXT[key]
  if mapped then return mapped end
  if string.len(key) ~= 1 then return nil end
  if string.find(key, "%a") then
    if SB.Held("IsShiftKeyDown") then return string.upper(key) end
    return string.lower(key)
  end
  return key
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Draws the text, keeping its tail when it is wider than the field, and puts
-- the caret after it. The label is never given a width, so GetStringWidth
-- stays honest (widgets.fontstring_stringwidth_clamped_by_setwidth).
function SB.Paint(box)
  local state = box and box.uuiSearch
  if not state then return end
  local label = state.label
  local text = state.text
  local typing = SB.active == box

  if label then
    local room = (tonumber(box:GetWidth()) or state.token.width) -
                 state.token.textInset.left - state.token.textInset.right
    local shown = text
    pcall(label.SetText, label, shown)
    local ok, width = pcall(label.GetStringWidth, label)
    width = (ok and tonumber(width)) or 0
    while width > room and string.len(shown) > 0 do
      shown = string.sub(shown, 2)
      pcall(label.SetText, label, shown)
      ok, width = pcall(label.GetStringWidth, label)
      width = (ok and tonumber(width)) or 0
    end
    local c = state.style.textColor
    pcall(label.SetTextColor, label, c[1], c[2], c[3])
    if text == "" then width = 0 end
    state.caretX = state.token.textInset.left + width
  end

  if state.placeholder then
    if text == "" and not typing then
      pcall(state.placeholder.Show, state.placeholder)
    else
      pcall(state.placeholder.Hide, state.placeholder)
    end
  end

  local caret = state.caret
  if caret then
    caret:ClearAllPoints()
    caret:SetPoint("LEFT", box, "LEFT", (state.caretX or 0) + 1, -3)
    if typing then caret:Show() else caret:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- Keys held off the client while typing
--
-- The key catcher does not stop the binding layer: this client resolves a
-- bound key before an addon frame hears it (modules/quickbind.lua), so typing
-- "c" opened the character window (user report, 2026-09-24). While a field is
-- being typed in, every key that types -- a bare key or its SHIFT- chord, plus
-- Backspace, Enter, Tab and Escape -- is taken off the client with SetBinding
-- and put back when typing ends: the mechanism Quick-Bind uses for its slot
-- keys. Chords with Ctrl or Alt type nothing and keep working.
--
-- Nothing is ever saved: the change is to the live set only and SaveBindings
-- is never called. The held list is still written to SavedVariables, so keys
-- left off by a disconnect or crash mid-typing are put back on the next load,
-- and leaving the world (logout, /reload) ends typing first.
-- ---------------------------------------------------------------------------
SB.held = {}   -- { { key = , command = }, ... }
SB.heldByCommand = {}

function SB.Call(name, a1, a2)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3 = pcall(fn, a1, a2)
  if not ok then return nil end
  return r1, r2, r3
end

-- True for a chord whose key types something (or leaves typing mode).
function SB.TypingChord(key)
  if type(key) ~= "string" or key == "" then return false end
  local base = key
  if string.sub(base, 1, 6) == "SHIFT-" then base = string.sub(base, 7) end
  if base == "" or string.find(base, "-", 2, true) then return false end
  if SB.LEAVE_KEYS[base] or base == "BACKSPACE" or SB.KEY_TEXT[base] then
    return true
  end
  return string.len(base) == 1
end

function SB.Store()
  if type(U.ModuleConfig) ~= "function" then return nil end
  return U.ModuleConfig("searchbox", { held = {} })
end

function SB.HoldKeys()
  if table.getn(SB.held) > 0 then return end
  local held = {}
  local count = tonumber(SB.Call("GetNumBindings")) or 0
  local i
  for i = 1, count do
    local command, key1, key2 = SB.Call("GetBinding", i)
    if type(command) == "string" and command ~= "" then
      if SB.TypingChord(key1) then
        table.insert(held, { key = key1, command = command })
      end
      if key2 ~= key1 and SB.TypingChord(key2) then
        table.insert(held, { key = key2, command = command })
      end
    end
  end

  SB.heldByCommand = {}
  for i = 1, table.getn(held) do
    SB.Call("SetBinding", held[i].key)
    local command = held[i].command
    if not SB.heldByCommand[command] then SB.heldByCommand[command] = held[i].key end
  end
  SB.held = held

  local store = SB.Store()
  if store then store.held = held end
end

-- Puts back every held key the client has not been given to something else.
function SB.ReleaseKeys(list)
  list = list or SB.held
  local i
  for i = 1, table.getn(list) do
    local entry = list[i]
    if type(entry) == "table" and type(entry.key) == "string" and
       type(entry.command) == "string" then
      local current = SB.Call("GetBindingAction", entry.key)
      if type(current) ~= "string" or current == "" then
        SB.Call("SetBinding", entry.key, entry.command)
      end
    end
  end
  SB.held = {}
  SB.heldByCommand = {}
  local store = SB.Store()
  if store then store.held = {} end
end

-- The key a command had before typing took it, for labels drawn while typing
-- (modules/quickbind.lua's U.SlotBindingKey asks this).
function U.SearchHeldBindingKey(command)
  return SB.heldByCommand[command]
end

-- Keys a previous session left off (disconnect or crash mid-typing).
function SB.RestoreLeftovers()
  if SB.active then return end
  local store = SB.Store()
  if store and type(store.held) == "table" and table.getn(store.held) > 0 then
    SB.ReleaseKeys(store.held)
  end
end

if type(U.RegisterEvent) == "function" then
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function() SB.RestoreLeftovers() end)
  U.RegisterEvent("PLAYER_LEAVING_WORLD", function() SB.End() end)
  -- Entering combat always hands the keyboard back.
  U.RegisterEvent("PLAYER_REGEN_DISABLED", function() SB.End() end)
end

-- ---------------------------------------------------------------------------
-- Typing mode
-- ---------------------------------------------------------------------------
function SB.Keys()
  if SB.catcher then return SB.catcher end
  local keys = CreateFrame("Frame", "UnrealUISearchBoxKeys", UIParent)
  pcall(keys.SetAllPoints, keys, UIParent)
  pcall(keys.SetFrameStrata, keys, "FULLSCREEN_DIALOG")
  pcall(keys.EnableKeyboard, keys, true)
  pcall(keys.EnableMouse, keys, false)
  keys:SetScript("OnKeyDown", function(a, b)
    local key = a
    if type(key) ~= "string" then key = b end
    if type(key) ~= "string" then key = U.G("arg1") end
    SB.OnKey(key)
  end)
  keys:SetScript("OnChar", function(a, b)
    local char = a
    if type(char) ~= "string" then char = b end
    if type(char) ~= "string" then char = U.G("arg1") end
    SB.OnChar(char)
  end)
  -- The caret's blink runs off the catcher, which exists only while a field
  -- is being typed in.
  -- Elapsed time arrives as a direct argument or the arg1 global
  -- (knowledge.json / scripts.handler_arguments_direct), so both are read.
  keys:SetScript("OnUpdate", function(a, b)
    local elapsed = tonumber(a) or tonumber(b) or tonumber(U.G("arg1")) or 0
    SB.blink = (SB.blink or 0) + elapsed
    if SB.blink < SB.BLINK then return end
    SB.blink = 0
    local state = SB.active and SB.active.uuiSearch
    local caret = state and state.caret
    if not caret then return end
    if caret:IsShown() then caret:Hide() else caret:Show() end
  end)
  keys:Hide()
  SB.catcher = keys
  return keys
end

function SB.Begin(box)
  if not box or not box.uuiSearch then return end
  if SB.active == box then return end
  -- Not in combat: typing mode takes keys off the client, which must never
  -- happen mid-fight.
  if SB.Call("UnitAffectingCombat", "player") then return end
  if SB.active then SB.End() end
  SB.active = box
  SB.blink = 0
  SB.skipBackspaceChar = nil
  SB.HoldKeys()
  SB.Keys():Show()
  SB.Paint(box)
end

function SB.End()
  local box = SB.active
  if not box then return end
  SB.active = nil
  SB.skipBackspaceChar = nil
  if SB.catcher then SB.catcher:Hide() end
  SB.ReleaseKeys()
  SB.Paint(box)
end

function SB.SetText(box, text, notify)
  local state = box and box.uuiSearch
  if not state then return end
  text = text or ""
  if text == state.text then return end
  state.text = text
  SB.blink = 0
  SB.Paint(box)
  if notify and type(state.onChange) == "function" then state.onChange(text) end
end

function SB.OnKey(key)
  local box = SB.active
  local state = box and box.uuiSearch
  if not state then
    SB.End()
    return
  end
  if SB.LEAVE_KEYS[key] then
    SB.End()
    return
  end
  if key == "BACKSPACE" then
    SB.skipBackspaceChar = true
    SB.SetText(box, string.sub(state.text, 1, -2), true)
    return
  end
  local typed = SB.KeyText(key)
  if not typed or string.len(state.text) >= SB.MAX_LETTERS then return end
  SB.SetText(box, state.text .. typed, true)
end

-- Use OnChar's native repeat stream when it supplies Backspace. Ignore its
-- first matching character because the initial OnKeyDown already removed one.
function SB.OnChar(char)
  if char ~= SB.BACKSPACE_CHAR and char ~= "BACKSPACE" then return end
  if SB.skipBackspaceChar then
    SB.skipBackspaceChar = nil
    return
  end
  local box = SB.active
  local state = box and box.uuiSearch
  if not state then return end
  SB.SetText(box, string.sub(state.text, 1, -2), true)
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- Builds a search field on `parent` and returns its frame, sized to the
-- style's width. The caller anchors it (two horizontal points stretch it) and
-- sets its level with U.LevelSearchBox. options.name names the frame and its
-- parts; options.placeholder is the hint text; options.onChange(text) runs on
-- every change, typed or cleared.
function U.CreateSearchBox(parent, options)
  local style = SB.Style()
  local token = style.token()
  if not parent or not token then return nil end
  options = options or {}
  local name = options.name

  local ok, box = pcall(CreateFrame, "Frame", name, parent)
  if not ok or not box then return nil end
  box:SetWidth(token.width)
  box:SetHeight(token.height)
  pcall(box.EnableMouse, box, false)

  local state = {
    style = style, token = token, text = "", onChange = options.onChange,
  }
  box.uuiSearch = state

  style.bed(box, token)

  -- The click that opens typing mode. Under the icon buttons, which keep
  -- their own clicks.
  local hit = CreateFrame("Button", name and (name .. "Hit"), box)
  hit:SetAllPoints(box)
  pcall(hit.RegisterForClicks, hit, "LeftButtonUp")
  hit:SetScript("OnClick", function() SB.Begin(box) end)
  box.hit = hit

  -- The text, the caret and the placeholder draw on their own frame above the
  -- hit button, so no region of the field sits under a frame of it.
  local face = CreateFrame("Frame", nil, box)
  face:SetAllPoints(box)
  pcall(face.EnableMouse, face, false)
  box.face = face

  state.label = U.CreateLabel(face, {
    size = M.fontSize.small,
    color = { style.textColor[1], style.textColor[2], style.textColor[3], 1 },
    inherits = "GameFontHighlightSmall",
    justify = "LEFT",
  })
  if state.label then
    state.label:SetPoint("LEFT", box, "LEFT", token.textInset.left, -3)
  end

  local caret = face:CreateTexture(nil, "OVERLAY")
  caret:SetTexture(M.texture.plain)
  caret:SetVertexColor(style.caretColor[1], style.caretColor[2],
                       style.caretColor[3])
  caret:SetWidth(1)
  caret:SetHeight(12)
  caret:Hide()
  state.caret = caret

  state.placeholder = U.CreateLabel(face, {
    size = M.fontSize.small,
    color = style.placeholderColor,
    inherits = "GameFontDisableSmall",
    justify = "LEFT",
    width = token.width - token.textInset.left - token.textInset.right,
    height = 14,
  })
  if state.placeholder then
    state.placeholder:SetPoint("LEFT", box, "LEFT", token.textInset.left, -3)
    state.placeholder:SetPoint("RIGHT", box, "RIGHT", -token.textInset.right, -3)
    state.placeholder:SetText(options.placeholder or "")
  end

  local icons = token.icons
  local function IconButton(suffix, cell, alpha, point, x, y, onClick)
    local button = CreateFrame("Button", name and (name .. suffix), box)
    button:SetWidth(icons.buttonSize)
    button:SetHeight(icons.buttonSize)
    button:SetPoint(point, box, point, x, y)
    local icon = style.icon(button, token, cell)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetAlpha(alpha)
    button:SetScript("OnEnter", function() icon:SetAlpha(1) end)
    button:SetScript("OnLeave", function() icon:SetAlpha(alpha) end)
    button:SetScript("OnMouseDown", function()
      icon:ClearAllPoints()
      icon:SetPoint("CENTER", button, "CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function()
      icon:ClearAllPoints()
      icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    end)
    button:SetScript("OnClick", onClick)
    return button
  end

  -- The magnifier ends typing and keeps the text; the clear button empties it.
  box.submit = IconButton("Button", icons.search, 0.6, "LEFT", -2, -1,
                          function()
    if SB.active == box then SB.End() end
  end)
  box.clear = IconButton("Clear", icons.clear, 0.5, "RIGHT", -3, 0, function()
    if SB.active == box then SB.End() end
    SB.SetText(box, "", true)
  end)

  -- A field that goes away takes typing mode with it.
  box:SetScript("OnHide", function()
    if SB.active == box then SB.End() end
  end)

  U.LevelSearchBox(box, (tonumber(parent:GetFrameLevel()) or 0) + 1)
  SB.Paint(box)
  return box
end

-- Sets the field's frame level. SetFrameLevel moves one frame, not its
-- subtree, so every part is levelled with it: the hit button one above, the
-- text face two, the icon buttons three.
function U.LevelSearchBox(box, level)
  if not box then return end
  pcall(box.SetFrameLevel, box, level)
  local ok, base = pcall(box.GetFrameLevel, box)
  base = (ok and tonumber(base)) or level
  if box.hit then pcall(box.hit.SetFrameLevel, box.hit, base + 1) end
  if box.face then pcall(box.face.SetFrameLevel, box.face, base + 2) end
  if box.submit then pcall(box.submit.SetFrameLevel, box.submit, base + 3) end
  if box.clear then pcall(box.clear.SetFrameLevel, box.clear, base + 3) end
end

-- The field's current text ("" for none).
function U.SearchBoxText(box)
  local state = box and box.uuiSearch
  return (state and state.text) or ""
end

-- Redraws the field; its owner calls it after a resize.
function U.PaintSearchBox(box)
  SB.Paint(box)
end

-- Leaves typing mode and empties the field without calling its onChange: the
-- owner is resetting it and already knows.
function U.ResetSearchBox(box)
  if not box or not box.uuiSearch then return end
  if SB.active == box then SB.End() end
  box.uuiSearch.text = ""
  SB.Paint(box)
end

-- True while any search field has the keyboard: typed keys are text, not
-- actions (modules/actionbar.lua).
function U.SearchBoxTyping()
  return SB.active ~= nil
end

-- Hands the keyboard back, whichever field had it.
function U.EndSearchTyping()
  SB.End()
end
