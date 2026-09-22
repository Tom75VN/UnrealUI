-- unrealUI :: modules/gamesettingslist.lua
--
-- Rebuilds a hosted client settings page as WoW Forever's settings LIST (user
-- request, 2026-09-21), instead of showing the 2006 panel as a canvas. It is
-- the companion of modules/gamesettings.lua, which hosts the panel; this file
-- only runs for a page whose spec says layout = "list".
--
-- Forever's list (Blizzard_Settings_Shared/Blizzard_SettingsList.xml/.lua and
-- Blizzard_SettingControls.xml/.lua, ForeverFrameXML-1.60.1.69913):
--
--   Header      title at 7,-22, DefaultsButton 96x22 at TOPRIGHT -36,-16,
--               Options_HorizontalDivider at y -50 (the window already draws
--               the title and the rule; the Defaults button lands here)
--   ScrollBox   a linear view: 10 padding top and bottom, 25 on the left,
--               9 between elements, MinimalScrollBar at its right
--   Section     45 tall, GameFontHighlightLarge title at 7,-16, no box
--   Row         26 tall, GameFontNormal label from indent+37 to CENTER-85,
--               the control from CENTER-80 (dropdown CENTER-48)
--
-- The controls are the CLIENT's, not copies: every checkbox, slider and
-- dropdown keeps its own scripts, CVar handling and OnShow initialisation. Each
-- is reparented into an addon row and anchored to it, with its own label
-- FontString moved into the row's label column. Anchoring a client widget to an
-- addon frame is the permitted direction under rules/unreal-ui.md (native
-- widget ownership boundaries); nothing addon-owned is anchored to a native
-- child. Everything moved is captured first and put back on detach, so the
-- panel handed back to the client is the panel it had.
--
-- What each page contains is DISCOVERED from its frame tree rather than listed
-- (see gs.Collect in gamesettings.lua for why a name list cannot keep up with
-- this client): a named frame with a <name>Title FontString is a section, a
-- named direct child of the page without one is a tab container (the Video
-- page's LegacyFrames / ModernFrames, the Interface page's BasicOptions /
-- AdvancedOptions), and controls are ordered as the client laid them out --
-- top to bottom, then left to right -- measured once, before anything moves.
--
-- Three client behaviours drive the rest (all measured on this client):
--
--   * SetFrameLevel moves one frame, not its subtree (gs.Relevel), so every
--     moved control is re-levelled above its row, and the list sits above the
--     panel that still hosts the page's own scripts.
--   * SetBackdrop(nil) is not a clear (rendering.setbackdrop_nil_does_not_
--     clear); a section box is hidden by zeroing its colours.
--   * The mouse wheel reaches an addon ScrollFrame through a Lua OnMouseWheel
--     (scripts.scrollframe_receives_mousewheel), and arg1 is a raw delta whose
--     sign is all that is used.
--
-- Uncertain and therefore watched: an addon-created Slider (the scrollbar)
-- follows the 2026-08-28 client note that fixed CreateFrame("Slider")
-- (widgets.native_slider_no_thumb, superseded) rather than a probe of its own;
-- the drawn thumb is U.StyleModernWowScrollbar's owned one, which only needs
-- GetValue / SetValue / GetMinMaxValues. The scrollbar is Blizzard's
-- MinimalScrollBar -- the bar Forever's SettingsList itself uses -- borrowed
-- from the shared Modern WoW component rather than drawn a second time.

local U = UnrealUI
local M = U.media
local gs = U.gameSettings

local L = {
  model = {},      -- [page.id] = discovered sections, measured once
  saved = {},      -- [page.id] = everything moved, for Detach
  rows = {},       -- [control name] = row frame
  headers = {},    -- [section name] = header frame
  values = {},     -- [slider name] = value FontString
  meters = {},     -- [meter name] = the theme bar drawn around it, per row
  hooked = {},     -- [frame name] = true once a relayout hook is installed
  searchIndex = {},-- [page.id] = searchable labels without moving its controls
  active = nil,    -- page currently laid out
  range = 0,       -- max scroll offset for the active page, from L.UpdateRange
}
gs.list = L

-- Slider FontStrings the list does not use: the row label replaces the title
-- and the written value replaces the end-of-track and tick labels.
L.SLIDER_EXTRAS = { "Low", "High", "Medium", "SettingLow", "SettingMedium",
                    "SettingHigh", "SettingUltra" }
-- Section FontStrings other than the title, drawn inside the client's box.
L.SECTION_EXTRAS = { "Title", "SubText", "Label" }
L.WALK_DEPTH = 5
L.LEVEL_GAP = 12

function L.FilterValue(text)
  if type(text) ~= "string" then return "" end
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

function L.Contains(value, query)
  if type(value) ~= "string" or query == "" then return query == "" end
  if string.find(value, query, 1, true) then return true end
  return string.find(string.lower(value), string.lower(query), 1, true) ~= nil
end

function L.Matches(section, control)
  local query = L.filter or ""
  return query == "" or L.Contains(section and section.title, query) or
         L.Contains(control and control.label, query)
end

function L.SetFilter(text)
  L.filter = L.FilterValue(text)
  L.offset = 0
  -- Deferred so a page this call selects has attached before it is filtered.
  if type(L.SyncBindingFilter) == "function" then
    U.DeferOnce("gamesettings:bindingsearch", L.SyncBindingFilter)
  end
  if L.bar then
    L.laying = true
    pcall(L.bar.SetValue, L.bar, 0)
    L.laying = false
  end

  -- Search belongs to the whole settings window, not only the open category.
  -- When the current category has no hit, move to the first category that
  -- does; its list is then filtered by the same query during Attach.
  if L.filter ~= "" and type(L.PageMatches) == "function" and
     type(L.FirstMatchingPage) == "function" and
     (not gs.active or not L.PageMatches(gs.active, L.filter)) then
    local page = L.FirstMatchingPage(L.filter)
    if page and (not gs.active or gs.active.id ~= page.id) and
       type(gs.SelectPage) == "function" then
      gs.SelectPage(page.id)
      return
    end
  end

  if L.active then
    L.Layout(L.active)
  elseif type(gs.RenderList) == "function" then
    gs.RenderList()
  end
end

-- ---------------------------------------------------------------------------
-- Capture / restore
-- ---------------------------------------------------------------------------
function L.Points(object)
  local points = {}
  local count = gs.Number(object, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y = pcall(object.GetPoint, object, i)
    if ok and point then
      table.insert(points, { point, relative, relativePoint, x, y })
    end
  end
  return points
end

function L.ApplyPoints(object, points)
  if not object or not points then return end
  pcall(object.ClearAllPoints, object)
  local i
  for i = 1, table.getn(points) do
    local p = points[i]
    pcall(object.SetPoint, object, p[1], p[2], p[3], p[4], p[5])
  end
end

-- Records an object's placement the first time this attach moves it. `state`
-- is the per-page record Detach walks.
function L.Keep(state, object, extra)
  if not object or state.kept[object] then return end
  local record = {
    object = object,
    parent = gs.Read(object, "GetParent"),
    points = L.Points(object),
    width = gs.Number(object, "GetWidth"),
    height = gs.Number(object, "GetHeight"),
    shown = gs.Read(object, "IsShown") and true or false,
  }
  if extra then
    local key, value
    for key, value in pairs(extra) do record[key] = value end
  end
  state.kept[object] = record
  table.insert(state.order, record)
end

function L.HideKept(state, object)
  if not object then return end
  L.Keep(state, object)
  pcall(object.Hide, object)
end

function L.Detach(page)
  local state = L.saved[page.id]
  L.active = nil
  if type(L.StopHover) == "function" then L.StopHover() end
  if type(L.ClearPending) == "function" then L.ClearPending() end
  if L.empty then pcall(L.empty.Hide, L.empty) end
  if L.scroll then pcall(L.scroll.Hide, L.scroll) end
  if L.bar then pcall(L.bar.Hide, L.bar) end
  if not state then return end

  -- Reverse order: a control goes back before the frame it was taken from is
  -- touched, and each object is put back exactly as it was found.
  local i
  for i = table.getn(state.order), 1, -1 do
    local record = state.order[i]
    local object = record.object
    if record.parent and record.reparented then
      pcall(object.SetParent, object, record.parent)
    end
    L.ApplyPoints(object, record.points)
    if record.resized and record.width then
      pcall(object.SetWidth, object, record.width)
    end
    if record.resizedHeight and record.height then
      pcall(object.SetHeight, object, record.height)
    end
    if record.box then
      local list = M.foreverWow.list
      pcall(object.SetBackdropColor, object, M.Unpack(list.boxColor))
      pcall(object.SetBackdropBorderColor, object, M.Unpack(list.boxBorderColor))
    end
    -- A meter: the client art hidden around its fill, then the material the
    -- fill drew before the list gave it the theme's (false when the walk
    -- could not name it; the bar then keeps the theme material until the
    -- client sets one of its own).
    if record.regions then
      local r
      for r = 1, table.getn(record.regions) do
        pcall(record.regions[r].Show, record.regions[r])
      end
    end
    if record.statusTexture and type(object.SetStatusBarTexture) == "function" then
      pcall(object.SetStatusBarTexture, object, record.statusTexture)
    end
    if record.text then pcall(object.SetText, object, record.text) end
    if record.mouse ~= nil then pcall(object.EnableMouse, object, record.mouse) end
    if record.alpha then pcall(object.SetAlpha, object, record.alpha) end
    if record.shown then pcall(object.Show, object) end
  end
  L.saved[page.id] = nil

  local k, row
  for k, row in pairs(L.rows) do pcall(row.Hide, row) end
  for k, row in pairs(L.headers) do pcall(row.Hide, row) end
end

-- ---------------------------------------------------------------------------
-- Discovery (once per page, before anything is moved)
-- ---------------------------------------------------------------------------
-- The page's own chrome, which L.PlaceChrome places and the list must not
-- collect as a control: Forever's Okay / Cancel / Defaults and the tab strip.
L.CHROME_BUTTON = { "Okay$", "Cancel$", "Defaults$", "Tab%d$" }

function L.KindOf(name, kind)
  if kind == "CheckButton" then return "checkbox" end
  if kind == "Slider" then
    if string.find(name, "ScrollBar") then return nil end
    return "slider"
  end
  if kind == "Frame" and gs.IsDropdown(name) then return "dropdown" end
  -- A StatusBar is a value the client draws beside a control rather than a
  -- setting to change -- the Sound page's microphone level. Reported in game
  -- 2026-09-22: with no row of its own it stayed anchored where the client
  -- had drawn it on the panel, which is outside this window, and kept drawing
  -- while the list scrolled under it.
  if kind == "StatusBar" then
    if string.find(name, "ScrollBar") then return nil end
    return "meter"
  end
  -- A plain Button is a control with an action rather than a value -- the
  -- Sound page's microphone test is the one this client has. Reported in game
  -- 2026-09-22: with no row of its own it stayed wherever the client had
  -- anchored it on the panel, which is outside this window.
  if kind == "Button" then
    local i
    for i = 1, table.getn(L.CHROME_BUTTON) do
      if string.find(name, L.CHROME_BUTTON[i]) then return nil end
    end
    return "button"
  end
  return nil
end

function L.Measure(name)
  local object = U.G(name)
  return gs.Number(object, "GetTop"), gs.Number(object, "GetLeft")
end

function L.AddControl(model, ctx, name, kind)
  local section = ctx.section
  if not section then
    section = { container = ctx.container, controls = {} }
    table.insert(model, section)
    ctx.section = section
  end
  local top, left = L.Measure(name)
  table.insert(section.controls, {
    name = name, kind = kind, top = top, left = left,
    index = table.getn(section.controls) + 1,
  })
end

function L.CountControls(model)
  local total = 0
  local i
  for i = 1, table.getn(model) do
    total = total + table.getn(model[i].controls)
  end
  return total
end

-- A named frame with no children of its own that still draws something: a bar
-- or a plate the client placed beside a control, not a group of controls. This
-- reads ONE frame's own regions, the bounded walk gs.StripChrome documents,
-- and reads only -- nothing here is hidden or kept.
function L.DrawsOnly(frame)
  if type(frame.GetChildren) == "function" then
    local ok, kids = pcall(function() return { frame:GetChildren() } end)
    if not ok or not kids or table.getn(kids) > 0 then return false end
  end
  if type(frame.GetRegions) ~= "function" then return false end
  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or not regions then return false end
  local i
  for i = 1, table.getn(regions) do
    if gs.Read(regions[i], "GetObjectType") == "Texture" and
       gs.Read(regions[i], "IsShown") then
      return true
    end
  end
  return false
end

function L.Walk(frame, depth, ctx, model)
  if depth > L.WALK_DEPTH or type(frame.GetChildren) ~= "function" then return end
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok or not kids then return end

  local i
  for i = 1, table.getn(kids) do
    local kid = kids[i]
    local name = gs.Read(kid, "GetName")
    local objectType = gs.Read(kid, "GetObjectType")
    if type(name) ~= "string" or name == "" then
      if objectType == "Frame" then L.Walk(kid, depth + 1, ctx, model) end
    else
      local kind = L.KindOf(name, objectType)
      if kind then
        L.AddControl(model, ctx, name, kind)
      elseif objectType == "Frame" then
        local title = U.G(name .. "Title")
        if title then
          local text = gs.Read(title, "GetText")
          local section = { name = name, container = ctx.container,
                            title = (text ~= "" and text) or nil, controls = {} }
          table.insert(model, section)
          L.Walk(kid, depth + 1, { container = ctx.container, section = section },
                 model)
        elseif depth == 1 then
          -- A tab page: its sections belong to it and show only while it does.
          L.Walk(kid, depth + 1, { container = name }, model)
        else
          local before = L.CountControls(model)
          L.Walk(kid, depth + 1, ctx, model)
          -- A named frame that contributed no control and only draws is the
          -- same stray a StatusBar is -- a bar or plate beside a control --
          -- so it is adopted the same way instead of being left on the panel.
          if L.CountControls(model) == before and L.DrawsOnly(kid) then
            L.AddControl(model, ctx, name, "meter")
          end
        end
      end
    end
  end
end

-- Top to bottom, then left to right, as the client laid them out. Anything the
-- client had not placed keeps its discovery order after the placed ones.
function L.Sort(controls)
  table.sort(controls, function(a, b)
    if a.top and b.top then
      if math.abs(a.top - b.top) > 4 then return a.top > b.top end
      if a.left and b.left and a.left ~= b.left then return a.left < b.left end
      return a.index < b.index
    end
    if a.top then return true end
    if b.top then return false end
    return a.index < b.index
  end)
end

function L.Discover(page, frame)
  if L.model[page.id] then return L.model[page.id] end
  local model = {}
  L.Walk(frame, 1, { container = nil }, model)
  local i, j
  for i = 1, table.getn(model) do
    L.Sort(model[i].controls)
    -- The label each row shows is the client's own text, read once so a
    -- trimmed label never becomes the source of the next trim.
    for j = 1, table.getn(model[i].controls) do
      local control = model[i].controls[j]
      if control.kind == "button" then
        -- A button's text is its own, not a separate label FontString.
        control.label = gs.Read(U.G(control.name), "GetText")
      else
        local label = U.G(control.name ..
                          (control.kind == "dropdown" and "Label" or "Text"))
        control.label = gs.Read(label, "GetText")
      end
    end
    -- A bar the client drew on the same line as a button belongs to it -- the
    -- microphone level beside Test Microphone -- so it rides that button's
    -- row, in its empty label column, rather than taking a line of its own.
    -- Its label is the owner's so one search query keeps the pair together;
    -- a sidecar never draws a label (L.PlaceControl).
    for j = 2, table.getn(model[i].controls) do
      local control = model[i].controls[j]
      local owner = model[i].controls[j - 1]
      if control.kind == "meter" and owner.kind == "button" and
         control.top and owner.top and
         math.abs(control.top - owner.top) <= 4 then
        control.sidecar = owner.name
        control.label = owner.label
      end
    end
  end
  L.model[page.id] = model
  -- A page can build controls lazily on its first Show. Replace any earlier
  -- search-only scan with this authoritative model once it exists.
  L.searchIndex[page.id] = nil
  return model
end

-- ---------------------------------------------------------------------------
-- Whole-window search index
--
-- This is a read-only GetChildren walk matching discovery's bounded depth. It
-- never walks regions and never moves a client object. Pages that have already
-- been discovered use that model; unopened pages are indexed from their named
-- controls so one query can find Video, Sound, Interface and Key Bindings.
-- ---------------------------------------------------------------------------
function L.AddSearchValue(values, value)
  if type(value) == "string" and value ~= "" then table.insert(values, value) end
end

function L.SearchWalk(frame, depth, sectionTitle, values)
  if depth > L.WALK_DEPTH or type(frame.GetChildren) ~= "function" then return end
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok or not kids then return end

  local i
  for i = 1, table.getn(kids) do
    local kid = kids[i]
    local name = gs.Read(kid, "GetName")
    local objectType = gs.Read(kid, "GetObjectType")
    if type(name) == "string" and name ~= "" then
      local kind = L.KindOf(name, objectType)
      if kind then
        L.AddSearchValue(values, sectionTitle)
        if kind == "button" then
          L.AddSearchValue(values, gs.Read(kid, "GetText"))
        else
          local label = U.G(name .. (kind == "dropdown" and "Label" or "Text"))
          L.AddSearchValue(values, gs.Read(label, "GetText"))
        end
      elseif objectType == "Frame" then
        local title = U.G(name .. "Title")
        local text = title and gs.Read(title, "GetText") or sectionTitle
        L.SearchWalk(kid, depth + 1, text, values)
      end
    elseif objectType == "Frame" then
      L.SearchWalk(kid, depth + 1, sectionTitle, values)
    end
  end
end

function L.SearchValues(page)
  local cached = page and L.searchIndex[page.id]
  if cached then return cached end

  local values = {}
  local ready = false
  L.AddSearchValue(values, page and U.L(page.label))
  local model = page and L.model[page.id]
  local i, j
  if model then
    ready = true
    for i = 1, table.getn(model) do
      L.AddSearchValue(values, model[i].title)
      for j = 1, table.getn(model[i].controls) do
        L.AddSearchValue(values, model[i].controls[j].label)
      end
    end
  else
    local frame = page and gs.Frame(page)
    if frame then
      ready = true
      L.SearchWalk(frame, 1, nil, values)
    end
  end

  local tabs = page and gs.PageTabs(page) or {}
  for i = 1, table.getn(tabs) do L.AddSearchValue(values, tabs[i].label) end
  -- Key Bindings recycles a few visible rows, so its frame walk finds only key
  -- names. Its commands come from the client's own binding table instead,
  -- which needs no load-on-demand frame.
  if page and page.bindingList then
    local bindings = L.BindingSearchEntries()
    if not bindings then
      ready = false
    else
      for i = 1, table.getn(bindings) do
        L.AddSearchValue(values, bindings[i].text)
      end
    end
  end
  if page and ready then L.searchIndex[page.id] = values end
  return values
end

-- Every row of the client's binding table as { index, text }, where text is
-- the name the Key Bindings page shows: BINDING_NAME_<command>, or
-- BINDING_HEADER_<category> for a header row. GetNumBindings returns nothing
-- until the player pawn exists, so an empty read is not cached.
function L.BindingSearchEntries()
  if L.bindingSearch then return L.bindingSearch end
  local num, get = L.BindingAPI()
  if type(num) ~= "function" or type(get) ~= "function" then return nil end
  local ok, count = pcall(num)
  count = ok and tonumber(count) or 0
  if count < 1 then return nil end

  local entries = {}
  local i
  for i = 1, count do
    local read, command = pcall(get, i)
    if read and type(command) == "string" and command ~= "" then
      local text
      local header = string.sub(command, 1, 7) == "HEADER_"
      if header then
        text = U.G("BINDING_HEADER_" .. string.sub(command, 8))
      else
        text = U.G("BINDING_NAME_" .. command)
      end
      if type(text) ~= "string" or text == "" then text = command end
      table.insert(entries, { index = i, text = text, header = header })
    end
  end
  L.bindingSearch = entries
  return entries
end

-- ---------------------------------------------------------------------------
-- Key Bindings filter (user request, 2026-09-23)
--
-- The Key Bindings page is the client's own list, which reads every row from
-- GetNumBindings / GetBinding. While a search is active on that page, both
-- globals are wrapped so the list sees only the matching rows: a command whose
-- name matches, under its category header, or every command of a category
-- whose header matches. The rows keep the real command, so binding a key on a
-- filtered row binds that command.
--
-- WORKING_SOURCE, not runtime-verified: this assumes the list is Lua that
-- looks both globals up at call time and repaints through
-- KeyBindingFrame_Update, as 1.12's Blizzard_BindingUI does. When
-- KeyBindingFrame_Update is not a Lua function, the page is scrolled to the
-- first match instead (L.RevealBinding). The wrappers check the page on every
-- call and pass straight through when it is not showing a search, so a close
-- that skips L.SyncBindingFilter still leaves every other caller unfiltered.
-- ---------------------------------------------------------------------------
function L.BindingAPI()
  local orig = L.bindingOrig
  if orig then return orig.num, orig.get end
  return U.G("GetNumBindings"), U.G("GetBinding")
end

function L.BindingFilterActive()
  local page = gs.active
  if not page or not page.bindingList then return false end
  if L.FilterValue(L.filter) == "" then return false end
  local frame = U.G("KeyBindingFrame")
  return frame ~= nil and gs.Read(frame, "IsShown") and true or false
end

-- Real GetBinding indices of the rows the query keeps, cached per query.
function L.BindingRows(query)
  if L.bindingRows and L.bindingRows.query == query then return L.bindingRows end
  local entries = L.BindingSearchEntries()
  if not entries then return nil end

  local rows = { query = query }
  local header, headerMatch, headerAdded
  local i
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry.header then
      header = entry
      headerMatch = L.Contains(entry.text, query)
      headerAdded = headerMatch
      if headerMatch then table.insert(rows, entry.index) end
    elseif headerMatch or L.Contains(entry.text, query) then
      if header and not headerAdded then
        table.insert(rows, header.index)
        headerAdded = true
      end
      table.insert(rows, entry.index)
    end
  end
  L.bindingRows = rows
  return rows
end

function L.FilteredNumBindings()
  local orig = L.bindingOrig
  if L.BindingFilterActive() then
    local rows = L.BindingRows(L.FilterValue(L.filter))
    if rows then return table.getn(rows) end
  end
  return orig.num()
end

-- Called with exactly the arguments it was given: a native function may count
-- them, so a trailing nil is never added.
function L.FilteredGetBinding(index, mode)
  local orig = L.bindingOrig
  if L.BindingFilterActive() then
    local rows = L.BindingRows(L.FilterValue(L.filter))
    if rows then
      local real = rows[tonumber(index) or 0]
      if not real then return nil end
      index = real
    end
  end
  if mode ~= nil then return orig.get(index, mode) end
  return orig.get(index)
end

function L.InstallBindingFilter()
  -- Still in the call chain: L.RemoveBindingFilter clears this only once both
  -- client functions are back.
  if L.bindingOrig then return true end
  local num, get = U.G("GetNumBindings"), U.G("GetBinding")
  if type(num) ~= "function" or type(get) ~= "function" then return false end
  L.bindingOrig = { num = num, get = get }
  U.SetG("GetNumBindings", L.FilteredNumBindings)
  U.SetG("GetBinding", L.FilteredGetBinding)
  if U.G("GetNumBindings") ~= L.FilteredNumBindings or
     U.G("GetBinding") ~= L.FilteredGetBinding then
    L.RemoveBindingFilter()
    return false
  end
  return true
end

-- Puts the client's functions back unless something has wrapped ours since;
-- then ours stay in its chain, passing through while no search is shown.
function L.RemoveBindingFilter()
  local orig = L.bindingOrig
  if not orig then return end
  if U.G("GetNumBindings") == L.FilteredNumBindings then
    U.SetG("GetNumBindings", orig.num)
  end
  if U.G("GetBinding") == L.FilteredGetBinding then
    U.SetG("GetBinding", orig.get)
  end
  if U.G("GetNumBindings") == orig.num and U.G("GetBinding") == orig.get then
    L.bindingOrig = nil
  end
end

-- Brings the Key Bindings list in line with the current query: wraps or
-- unwraps the binding globals, returns the list to its top and repaints it.
-- Also run from L.SearchTick, so a page switch or an Escape that hides the
-- page is caught; it does nothing while the shown query is unchanged, which
-- keeps it from fighting the player's own scrolling.
function L.SyncBindingFilter()
  local query = L.BindingFilterActive() and L.FilterValue(L.filter) or nil
  if query == L.bindingShown then return end
  L.bindingShown = query

  local refresh = U.G("KeyBindingFrame_Update")
  if type(refresh) ~= "function" or (query and not L.InstallBindingFilter()) then
    L.RemoveBindingFilter()
    if query then L.RevealBinding() end
    return
  end
  if not query then L.RemoveBindingFilter() end

  local bar = U.G("KeyBindingFrameScrollFrameScrollBar")
  if bar then pcall(bar.SetValue, bar, 0) end
  pcall(refresh)
  if type(gs.PaintBindingList) == "function" then
    U.DeferOnce("gamesettings:bindings", gs.PaintBindingList)
  end
end

-- Scrolls the Key Bindings page to the first row matching the query. The
-- client's list is a FauxScrollFrame whose offset is the scroll bar's value
-- over one row's height; that height is KEY_BINDING_HEIGHT when the client
-- defines it, else the measured pitch between its first two rows. Setting the
-- bar's value runs the client's own OnValueChanged, which repaints the rows.
-- Assumes the page lists GetBinding's rows in order, as 1.12's
-- KeyBindingFrame_Update does (WORKING_SOURCE, not runtime-verified); with no
-- readable height it leaves the list where it is.
function L.RevealBinding()
  local page = gs.active
  local query = L.FilterValue(L.filter)
  if not page or not page.bindingList or query == "" then return end
  local bar = U.G("KeyBindingFrameScrollFrameScrollBar")
  local bindings = L.BindingSearchEntries()
  if not bar or not bindings then return end

  local found, i
  for i = 1, table.getn(bindings) do
    if L.Contains(bindings[i].text, query) then
      found = bindings[i].index
      break
    end
  end
  if not found then return end

  local height = tonumber(U.G("KEY_BINDING_HEIGHT"))
  if not height or height <= 0 then
    local first = U.G("KeyBindingFrameBinding1Key1Button")
    local second = U.G("KeyBindingFrameBinding2Key1Button")
    local a = first and gs.Number(first, "GetTop")
    local b = second and gs.Number(second, "GetTop")
    height = a and b and (a - b) or nil
  end
  if not height or height <= 0 then return end
  pcall(bar.SetValue, bar, (found - 1) * height)
end

function L.InvalidateSearch(page)
  if page then L.searchIndex[page.id] = nil end
end

function L.PageMatches(page, query)
  if type(gs.PageAvailable) == "function" and not gs.PageAvailable(page) then
    return false
  end
  query = L.FilterValue(query or L.filter)
  if query == "" then return true end
  local values = L.SearchValues(page)
  local i
  for i = 1, table.getn(values) do
    if L.Contains(values[i], query) then return true end
  end
  return false
end

function L.FirstMatchingPage(query)
  local i
  for i = 1, table.getn(gs.PAGES) do
    if L.PageMatches(gs.PAGES[i], query) then return gs.PAGES[i] end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- The list itself
-- ---------------------------------------------------------------------------
function L.PaintSearchPlaceholder()
  if not L.searchPlaceholder or not L.searchEdit then return end
  local text = gs.Read(L.searchEdit, "GetText") or ""
  if text == "" then
    pcall(L.searchPlaceholder.Show, L.searchPlaceholder)
  else
    pcall(L.searchPlaceholder.Hide, L.searchPlaceholder)
  end
end

function L.BuildSearch()
  if L.search or not gs.panel then return L.search ~= nil end
  local token = M.foreverWow.search
  if not token then return false end

  local ok, search = pcall(CreateFrame, "Frame", "UnrealUIGameSettingsSearch",
                           gs.panel)
  if not ok or not search then return false end
  search:Hide()
  search:SetWidth(token.width)
  search:SetHeight(token.height)
  -- Centre the field in the strip between the window header and the recessed
  -- content plate. It is aligned to the plate's right edge, but is not part of
  -- the content canvas and therefore takes no height away from the option list.
  local lane = gs.PLATE_TOP - gs.HEADER_HEIGHT
  local top = gs.HEADER_HEIGHT + math.max(0, (lane - token.height) / 2)
  search:SetPoint("TOPRIGHT", gs.panel, "TOPRIGHT", -gs.PLATE_SIDE, -top)
  pcall(search.EnableMouse, search, false)
  pcall(search.SetFrameLevel, search,
        (gs.Number(gs.panel, "GetFrameLevel") or 1) + L.LEVEL_GAP)

  local border = token.border
  local function BorderPiece(cell)
    local texture = search:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(border.texture)
    gs.SetCell(texture, cell, border.sheetWidth, border.sheetHeight)
    texture:SetHeight(border.height)
    return texture
  end
  local left = BorderPiece(border.left)
  local middle = BorderPiece(border.middle)
  local right = BorderPiece(border.right)
  left:SetWidth(border.capWidth)
  left:SetPoint("LEFT", search, "LEFT", -5, 0)
  right:SetWidth(border.capWidth)
  right:SetPoint("RIGHT", search, "RIGHT", 0, 0)
  middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
  middle:SetPoint("RIGHT", right, "LEFT", 0, 0)

  -- This is the user-confirmed UnrealQuest search contract: no EditBox scripts
  -- and no programmatic focus. A separate window updater reads the text while
  -- the user types; the magnifier remains an optional submit/focus-release.
  local made, edit = pcall(CreateFrame, "EditBox",
                           "UnrealUIGameSettingsSearchEdit", search)
  if not made or not edit then return false end
  edit:SetWidth(token.width)
  edit:SetHeight(14)
  edit:SetPoint("CENTER", search, "CENTER", 0, -3)
  local font = U.G("GameFontHighlightSmall")
  if font then pcall(edit.SetFontObject, edit, font) end
  pcall(edit.SetTextColor, edit, 1, 1, 1)
  pcall(edit.SetJustifyH, edit, "LEFT")
  pcall(edit.SetTextInsets, edit, token.textInset.left, token.textInset.right, 0, 0)
  pcall(edit.SetAutoFocus, edit, false)
  pcall(edit.SetText, edit, "")

  local icons = token.icons
  local function IconButton(name, cell, alpha, point, x, y, onClick)
    local button = CreateFrame("Button", name, search)
    button:SetWidth(icons.buttonSize)
    button:SetHeight(icons.buttonSize)
    button:SetPoint(point, search, point, x, y)
    pcall(button.SetFrameLevel, button,
          (gs.Number(search, "GetFrameLevel") or 1) + 2)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(icons.texture)
    gs.SetCell(icon, cell, icons.sheetWidth, icons.sheetHeight)
    icon:SetWidth(icons.size)
    icon:SetHeight(icons.size)
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

  local submit = IconButton("UnrealUIGameSettingsSearchButton", icons.search,
                            0.6, "LEFT", -2, -1, function()
    local text = gs.Read(edit, "GetText") or ""
    if type(edit.ClearFocus) == "function" then pcall(edit.ClearFocus, edit) end
    L.SetFilter(text)
    L.PaintSearchPlaceholder()
  end)
  local clear = IconButton("UnrealUIGameSettingsSearchClear", icons.clear,
                           0.5, "RIGHT", -3, 0, function()
    pcall(edit.SetText, edit, "")
    if type(edit.ClearFocus) == "function" then pcall(edit.ClearFocus, edit) end
    L.SetFilter("")
    L.PaintSearchPlaceholder()
  end)

  local placeholder = U.CreateLabel(search, {
    size = M.fontSize.small,
    color = { 0.58, 0.58, 0.58, 1 },
    inherits = "GameFontDisableSmall",
    justify = "LEFT",
    width = token.width - token.textInset.left - token.textInset.right,
    height = 14,
  })
  if placeholder then
    placeholder:SetPoint("LEFT", search, "LEFT", token.textInset.left, -3)
    placeholder:SetText(U.L("GAMESETTINGS_SEARCH"))
  end

  L.search = search
  L.searchEdit = edit
  L.searchButton = submit
  L.searchClear = clear
  L.searchPlaceholder = placeholder
  L.PaintSearchPlaceholder()
  return true
end

function L.SearchTick()
  if not gs.panel or not gs.Read(gs.panel, "IsShown") then return end
  L.PaintSearchPlaceholder()
  if not L.searchEdit then return end
  local text = L.FilterValue(gs.Read(L.searchEdit, "GetText") or "")
  if text ~= (L.filter or "") then L.SetFilter(text) end
  L.SyncBindingFilter()
end

function L.ShowSearch()
  if not L.BuildSearch() then return false end
  pcall(L.search.Show, L.search)
  L.PaintSearchPlaceholder()
  if not L.searchRunning then
    L.searchRunning = true
    U.RegisterUpdate("gamesettings.search", M.foreverWow.list.hover.interval,
                     L.SearchTick)
  end
  return true
end

function L.HideSearch()
  U.UnregisterUpdate("gamesettings.search")
  L.searchRunning = nil
  if L.searchEdit and type(L.searchEdit.ClearFocus) == "function" then
    pcall(L.searchEdit.ClearFocus, L.searchEdit)
  end
  if L.searchEdit then pcall(L.searchEdit.SetText, L.searchEdit, "") end
  L.filter = ""
  L.SyncBindingFilter()
  if L.search then pcall(L.search.Hide, L.search) end
end

function L.Build()
  if L.scroll or not gs.host then return L.scroll ~= nil end
  local list = M.foreverWow.list

  L.BuildSearch()

  local ok, scroll = pcall(CreateFrame, "ScrollFrame", "UnrealUIGameSettingsList", gs.host)
  if not ok or not scroll then return false end
  L.scroll = scroll
  scroll:SetPoint("TOPLEFT", gs.host, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", gs.host, "BOTTOMRIGHT",
                  -(list.scrollbarWidth + list.scrollbarInset.right +
                    list.scrollbarGap), 0)

  -- The ScrollFrame is kept for the wheel alone, with the 1x1 scroll child
  -- scripts.scrollframe_receives_mousewheel verified. It never scrolls:
  -- reported in game 2026-09-21, moving the scroll child carried the section
  -- headers (addon frames) but left every client control where it was, so a
  -- reparented native widget does not follow a scroll-child offset on this
  -- client. The rows therefore live on a plain frame over the same area and
  -- the list is painted from an offset instead (L.Layout), the way UnrealUI's
  -- other lists scroll here.
  local dummy = CreateFrame("Frame", nil, scroll)
  dummy:SetWidth(1)
  dummy:SetHeight(1)
  pcall(scroll.SetScrollChild, scroll, dummy)

  local child = CreateFrame("Frame", "UnrealUIGameSettingsListChild", gs.host)
  child:SetAllPoints(scroll)
  pcall(child.EnableMouse, child, false)
  L.child = child
  L.offset = 0

  local okBar, bar = pcall(CreateFrame, "Slider", "UnrealUIGameSettingsListBar", gs.host)
  if okBar and bar then
    L.bar = bar
    pcall(bar.SetOrientation, bar, "VERTICAL")
    bar:SetWidth(list.scrollbarWidth)
    bar:SetPoint("TOPRIGHT", gs.host, "TOPRIGHT", -list.scrollbarInset.right,
                 -list.scrollbarInset.top)
    bar:SetPoint("BOTTOMRIGHT", gs.host, "BOTTOMRIGHT", -list.scrollbarInset.right,
                 list.scrollbarInset.bottom)
    pcall(bar.SetMinMaxValues, bar, 0, 0)
    pcall(bar.SetValueStep, bar, 1)
    pcall(bar.SetValue, bar, 0)
    bar:SetScript("OnValueChanged", function()
      local value = math.floor((gs.Number(bar, "GetValue") or 0) + 0.5)
      L.PaintArrows()
      if value == L.offset then return end
      L.offset = value
      if L.active and not L.laying then L.Layout(L.active) end
    end)
    -- MinimalScrollBar's steppers. The shared component finds them by the
    -- Slider's name and draws them; each moves the list one wheel step.
    local function Arrow(suffix, direction)
      local okArrow, arrow = pcall(CreateFrame, "Button",
                                   "UnrealUIGameSettingsListBar" .. suffix, bar)
      if not okArrow or not arrow then return end
      arrow:SetScript("OnClick", function()
        local value = gs.Number(bar, "GetValue") or 0
        pcall(bar.SetValue, bar, L.Clamp(value + direction * M.foreverWow.list.wheelStep))
      end)
    end
    Arrow("ScrollUpButton", -1)
    Arrow("ScrollDownButton", 1)
    if type(U.StyleModernWowScrollbar) == "function" then
      -- The Modern WoW MinimalScrollBar (modern-wow/ui, M.modernWow.scrollbar,
      -- the component's default) by user request, 2026-09-22 -- not the
      -- Forever sheets.
      U.StyleModernWowScrollbar(bar)
    end
  end

  pcall(scroll.EnableMouseWheel, scroll, true)
  scroll:SetScript("OnMouseWheel", function()
    local delta = tonumber(arg1)
    if not delta or delta == 0 or not L.bar then return end
    local value = gs.Number(L.bar, "GetValue") or 0
    local step = M.foreverWow.list.wheelStep
    if delta > 0 then value = value - step else value = value + step end
    pcall(L.bar.SetValue, L.bar, L.Clamp(value))
  end)
  return true
end

function L.Row(name)
  local row = L.rows[name]
  if row then return row end
  row = CreateFrame("Frame", nil, L.child)
  row:SetHeight(M.foreverWow.list.rowHeight)
  pcall(row.EnableMouse, row, false)
  L.rows[name] = row
  return row
end

function L.Header(section)
  local key = section.name or "?"
  local header = L.headers[key]
  if header then return header end
  local list = M.foreverWow.list
  header = CreateFrame("Frame", nil, L.child)
  header:SetHeight(list.sectionHeight)
  pcall(header.EnableMouse, header, false)
  header.title = U.CreateLabel(header, {
    size = M.fontSize.large,
    color = list.sectionColor,
    inherits = "GameFontHighlightLarge",
    justify = "LEFT",
  })
  if header.title then
    header.title:SetPoint("TOPLEFT", header, "TOPLEFT", list.sectionTitle.x,
                          list.sectionTitle.y)
  end
  L.headers[key] = header
  return header
end

-- The slider's current value, where Forever writes its RightText: 25 right of
-- the track, GameFontNormal. Anchored to the ROW at the track's measured end,
-- not to the client slider: an addon region is never anchored to a native
-- widget (rules/unreal-ui.md), and a native widget does not carry what hangs
-- off it when it moves (widgets.reparented_native_widget_ignores_scroll_offset).
function L.ValueText(row, slider, name)
  local list = M.foreverWow.list
  local text = L.values[name]
  if not text then
    text = U.CreateLabel(row, {
      size = M.fontSize.normal,
      color = list.labelColor,
      inherits = "GameFontNormal",
      justify = "LEFT",
    })
    L.values[name] = text
    U.PostHookScript(slider, "OnValueChanged", function() L.PaintValue(name) end)
  end
  if text then
    pcall(text.ClearAllPoints, text)
    pcall(text.SetPoint, text, "LEFT", row, "CENTER",
          L.Col().sliderX + list.sliderWidth + list.valueGap, list.sliderY)
  end
  return text
end

-- MinimalSliderWithSteppers' Back and Forward buttons: 11x19 and 9x18,
-- stepperGap outside each end of the track, Minimal_SliderBar_Button_Left /
-- _Right. The client's sliders have none, so they are the row's own buttons,
-- anchored to the row at the track's measured ends, and move the client
-- slider through its own SetValue -- the call its thumb uses -- so its native
-- OnValueChanged applies the setting.
function L.Steppers(row, name)
  if row.uuiSteppers then return row.uuiSteppers end
  local token = M.foreverWow.control.slider
  local steppers = gs.BuildSliderSteppers(row)
  if not steppers then return nil end
  steppers.onStep = function(direction)
    local slider = U.G(row.uuiSliderName)
    if not slider then return end
    local value = gs.Number(slider, "GetValue")
    local okRange, low, high = pcall(slider.GetMinMaxValues, slider)
    if not value or not okRange then return end
    low, high = tonumber(low) or 0, tonumber(high) or 0
    local step = gs.Number(slider, "GetValueStep") or 0
    if step <= 0 then step = (high - low) / token.fallbackSteps end
    if step <= 0 then return end
    value = value + direction * step
    if value < low then value = low end
    if value > high then value = high end
    pcall(slider.SetValue, slider, value)
  end
  row.uuiSteppers = steppers
  return steppers
end

function L.PaintSliderSteppers(row)
  local slider = row and U.G(row.uuiSliderName)
  local steppers = row and row.uuiSteppers
  if not slider or not steppers then return end
  local value = gs.Number(slider, "GetValue")
  local okRange, low, high = pcall(slider.GetMinMaxValues, slider)
  if not value or not okRange then return end
  low, high = tonumber(low) or 0, tonumber(high) or 0
  gs.SetSliderStepperState(steppers, value > low, value < high)
end

function L.PlaceSteppers(row, name, level)
  local list = M.foreverWow.list
  local token = M.foreverWow.control.slider
  local steppers = L.Steppers(row, name)
  if not steppers then return end
  row.uuiSliderName = name
  if steppers.back then
    steppers.back:ClearAllPoints()
    steppers.back:SetPoint("RIGHT", row, "CENTER", L.Col().sliderX - token.stepperGap,
                           list.sliderY)
    pcall(steppers.back.SetFrameLevel, steppers.back, level)
    steppers.back:Show()
  end
  if steppers.forward then
    steppers.forward:ClearAllPoints()
    steppers.forward:SetPoint("LEFT", row, "CENTER",
                              L.Col().sliderX + list.sliderWidth + token.stepperGap,
                              list.sliderY)
    pcall(steppers.forward.SetFrameLevel, steppers.forward, level)
    steppers.forward:Show()
  end
  L.PaintSliderSteppers(row)
end

function L.PaintValue(name)
  local text, slider = L.values[name], U.G(name)
  if not text or not slider then return end
  local value = gs.Number(slider, "GetValue")
  if not value then
    pcall(text.SetText, text, "")
    return
  end
  -- A missing step means the client slider is continuous. Preserve its
  -- fractional value instead of treating the absent method as an integer step.
  local step = gs.Number(slider, "GetValueStep") or 0
  local shown
  if step >= 1 then
    shown = string.format("%d", math.floor(value + 0.5))
  elseif step >= 0.1 then
    shown = string.format("%.1f", value)
  else
    shown = string.format("%.2f", value)
  end
  pcall(text.SetText, text, shown)
  L.PaintSliderSteppers(slider.uuiForeverRow)
  -- The owned thumb follows every value change, whoever made it.
  L.PaintThumb(name)
  if L.dragTrace and table.getn(L.dragTrace) < L.DRAG_TRACE_MAX then
    table.insert(L.dragTrace, { ev = "changed", name = name, value = value,
                                t = gs.TraceTime() })
  end
end

-- Drag trace (diagnostic, 2026-09-22): reported in game, the owned thumb
-- "vibrates" while dragged and the value does not follow. Every drag tick
-- records the cursor, the geometry the value was computed from, and the
-- slider's value before and after SetValue; every OnValueChanged records the
-- value it carried. Written to UnrealUIDiagDB.gameSettingsSlider when the
-- drag stops. Capped, and only while a drag is running.
L.DRAG_TRACE_MAX = 240

function gs.TraceTime()
  local clock = U.G("GetTime")
  if type(clock) ~= "function" then return nil end
  local ok, value = pcall(clock)
  return ok and value or nil
end

function L.TraceDrag(row, slider, before, value)
  L.dragTrace = L.dragTrace or {}
  if table.getn(L.dragTrace) >= L.DRAG_TRACE_MAX then return end
  local cursor = U.G("GetCursorPosition")
  local x, y
  if type(cursor) == "function" then
    local ok, a, b = pcall(cursor)
    if ok then x, y = a, b end
  end
  local trackLeft, trackWidth, thumbWidth = L.SliderGeometry(row)
  local down
  local isDown = U.G("IsMouseButtonDown")
  if type(isDown) == "function" then
    local ok, held = pcall(isDown, "LeftButton")
    if ok then down = held and true or false end
  end
  table.insert(L.dragTrace, {
    ev = "tick", t = gs.TraceTime(), name = row.uuiSliderName,
    x = x, y = y, scale = gs.Number(row, "GetEffectiveScale"),
    rowLeft = gs.Number(row, "GetLeft"), rowRight = gs.Number(row, "GetRight"),
    trackLeft = trackLeft, trackWidth = trackWidth, thumbWidth = thumbWidth,
    before = before, wanted = value, after = gs.Number(slider, "GetValue"),
    down = down, mouse = gs.Read(slider, "IsMouseEnabled"),
  })
end

function L.SaveDragTrace()
  if not L.dragTrace then return end
  U.SaveDiagnostic("gameSettingsSlider", L.dragTrace)
  L.dragTrace = nil
end

-- ---------------------------------------------------------------------------
-- Slider input, rebuilt (user requests, 2026-09-22)
--
-- The client's slider cannot be dragged once it is reparented into a row: this
-- client does not carry a reparented native widget's geometry along
-- (widgets.reparented_native_widget_ignores_scroll_offset / _ancestor_scale),
-- so the thumb it drags by is not the one drawn. The row therefore owns the
-- input, and the client slider keeps drawing its bar, stops taking the mouse
-- and is moved only through its own SetValue -- so its OnValueChanged still
-- applies the setting.
--
-- The drag is U.CreateSlider's (core/widgets.lua), the thumb recipe proven on
-- this client, not a cursor poll. A first version polled GetCursorPosition
-- from OnMouseDown and re-anchored its thumb every tick; /uui gamefocus'
-- successor trace (UnrealUIDiagDB.gameSettingsSlider, 2026-09-22) read the
-- cursor moving 6 units in 186 ticks while the player dragged across the bar,
-- and the thumb shook between two values. The recipe that works:
--
--   * the INPUT is an invisible Button registered for drag, and OnDragStart
--     puts it in native StartMoving (StartMoving / StopMovingOrSizing /
--     StartMoving, as core/mover.lua does) -- the cursor is read only while
--     that native move runs;
--   * the drawn knob is a separate mouse-transparent frame, placed from the
--     cursor during the drag and from the value otherwise;
--   * nothing re-anchors the input Button while it is being moved
--     (knowledge.json / widgets.thumb_reposition_during_drag_breaks_drag);
--   * OnDragStop publishes the value and puts the input back on the knob.
--
-- A click on the track sets the value there, as U.CreateSlider's does.
-- ---------------------------------------------------------------------------
function L.SliderGeometry(row)
  local list = M.foreverWow.list
  local token = M.foreverWow.control.slider
  local left = gs.Number(row, "GetLeft")
  local right = gs.Number(row, "GetRight")
  if not left or not right then return nil end
  local trackLeft = left + (right - left) / 2 + L.Col().sliderX
  return trackLeft, list.sliderWidth, token.thumbWidth
end

-- The cursor's X in the row's coordinate space, or nil.
function L.SliderCursorX(row)
  local cursor = U.G("GetCursorPosition")
  if type(cursor) ~= "function" then return nil end
  local ok, x = pcall(cursor)
  local scale = gs.Number(row, "GetEffectiveScale")
  x = ok and tonumber(x) or nil
  if not x or not scale or scale <= 0 then return nil end
  return x / scale
end

-- The knob's left edge inside the track for the slider's current value --
-- the placement L.PaintThumb draws.
function L.KnobOffset(slider)
  local token = M.foreverWow.control.slider
  local value = gs.Number(slider, "GetValue")
  local okRange, low, high = pcall(slider.GetMinMaxValues, slider)
  low, high = okRange and tonumber(low), okRange and tonumber(high)
  local fraction = 0
  if value and low and high and high > low then
    fraction = (value - low) / (high - low)
  end
  if fraction < 0 then fraction = 0 end
  if fraction > 1 then fraction = 1 end
  return fraction * (M.foreverWow.list.sliderWidth - token.thumbWidth)
end

-- Where on the knob the cursor holds it, 0..thumbWidth from its left edge, or
-- nil. The drag keeps this point under the cursor: the gameSettingsSlider
-- trace (2026-09-22) read the first drag tick 10 units right of the knob's
-- centre -- the client's drag threshold plus an off-centre press -- and
-- re-centring the knob on the cursor made it jump right on every grab.
function L.SliderGrab(row, slider)
  local x = L.SliderCursorX(row)
  local trackLeft, _, thumbWidth = L.SliderGeometry(row)
  if not x or not trackLeft then return nil end
  local grab = x - trackLeft - L.KnobOffset(slider)
  if grab < 0 then grab = 0 end
  if grab > thumbWidth then grab = thumbWidth end
  return grab
end

-- The value and knob offset under the cursor, or nil when anything needed is
-- not readable yet, so an unlaid-out row keeps its value instead of jumping.
-- grab is the held point on the knob; nil centres the knob on the cursor, as
-- a click on the bare track does.
function L.SliderValueAt(row, slider, grab)
  local x = L.SliderCursorX(row)
  if not x then return nil end

  local trackLeft, trackWidth, thumbWidth = L.SliderGeometry(row)
  if not trackLeft then return nil end
  local okRange, low, high = pcall(slider.GetMinMaxValues, slider)
  low, high = okRange and tonumber(low), okRange and tonumber(high)
  if not low or not high or high <= low then return nil end

  local usable = trackWidth - thumbWidth
  if usable <= 0 then return nil end
  local offset = x - trackLeft - (grab or thumbWidth / 2)
  if offset < 0 then offset = 0 end
  if offset > usable then offset = usable end
  local value = low + offset / usable * (high - low)

  local step = gs.Number(slider, "GetValueStep") or 0
  if step > 0 then value = low + math.floor((value - low) / step + 0.5) * step end
  if value < low then value = low end
  if value > high then value = high end
  return value, offset
end

function L.SliderInput(row, name, level)
  local list = M.foreverWow.list
  local token = M.foreverWow.control.slider
  local input = row.uuiSliderInput
  if not input then
    input = { dragging = false }
    local okTrack, track = pcall(CreateFrame, "Button", nil, row)
    local okThumb, thumb = pcall(CreateFrame, "Button", nil, row)
    local okKnob, knob = pcall(CreateFrame, "Frame", nil, row)
    if not okTrack or not track or not okThumb or not thumb or
       not okKnob or not knob then
      return nil
    end
    input.track, input.thumb, input.knob = track, thumb, knob

    pcall(track.EnableMouse, track, true)
    pcall(track.SetHeight, track, token.thumbHeight)

    -- The invisible input handle.
    pcall(thumb.EnableMouse, thumb, true)
    pcall(thumb.RegisterForDrag, thumb, "LeftButton")
    pcall(thumb.SetWidth, thumb, token.thumbWidth)
    pcall(thumb.SetHeight, thumb, token.thumbHeight)

    -- The drawn knob, never the mouse target.
    pcall(knob.EnableMouse, knob, false)
    pcall(knob.SetWidth, knob, token.thumbWidth)
    pcall(knob.SetHeight, knob, token.thumbHeight)
    local made, face = pcall(knob.CreateTexture, knob, nil, "OVERLAY")
    if made and face then
      pcall(face.SetTexture, face, token.texture)
      pcall(face.SetAllPoints, face, knob)
      gs.SetCell(face, token.thumb, token.sheetWidth, token.sheetHeight)
      knob.uuiFace = face
    end

    local function Slider()
      local slider = U.G(row.uuiSliderName)
      if not slider then return nil end
      local enabled = gs.Read(slider, "IsEnabled")
      if enabled == 0 or enabled == false then return nil end
      return slider
    end

    local function Apply(slider, value)
      if value and value ~= gs.Number(slider, "GetValue") then
        pcall(slider.SetValue, slider, value)
      end
    end

    local updateId = "gamesettings.slider." .. tostring(row)

    local function FinishDrag()
      if not input.dragging then return end
      input.dragging = false
      U.UnregisterUpdate(updateId)
      pcall(thumb.StopMovingOrSizing, thumb)
      local slider = Slider()
      if slider then Apply(slider, L.SliderValueAt(row, slider, input.dragGrab)) end
      input.dragGrab = nil
      L.SaveDragTrace()
      L.PaintThumb(row.uuiSliderName)
    end

    -- IsMouseButtonDown does not exist on this client (the drag trace read
    -- nil), so this only ends a drag where it does; OnDragStop is the path.
    local function StillDown()
      local down = U.G("IsMouseButtonDown")
      if type(down) ~= "function" then return true end
      local ok, held = pcall(down, "LeftButton")
      if not ok then return true end
      return held and true or false
    end

    local function Follow()
      if not StillDown() then
        FinishDrag()
        return
      end
      local slider = Slider()
      if not slider then return end
      local before = gs.Number(slider, "GetValue")
      local value, offset = L.SliderValueAt(row, slider, input.dragGrab)
      if not value then return end
      -- The knob follows the cursor; the input handle is left alone.
      pcall(knob.ClearAllPoints, knob)
      pcall(knob.SetPoint, knob, "LEFT", row, "CENTER", L.Col().sliderX + offset,
            list.sliderY)
      Apply(slider, value)
      L.TraceDrag(row, slider, before, value)
    end

    -- The press, not the drag start, fixes the held point: OnDragStart only
    -- fires once the cursor has already travelled the drag threshold.
    -- GetCursorPosition in OnMouseDown is the colour picker's verified read
    -- (api.getcursorposition_usable_for_hit_testing).
    thumb:SetScript("OnMouseDown", function()
      local slider = Slider()
      input.grab = slider and L.SliderGrab(row, slider) or nil
    end)

    thumb:SetScript("OnDragStart", function()
      local slider = Slider()
      if not slider then return end
      -- Consumed here so a later release cannot read a stale press; without a
      -- press read, the held point is taken now, clamped onto the knob.
      input.dragGrab = input.grab or L.SliderGrab(row, slider)
      input.grab = nil
      if not pcall(thumb.SetMovable, thumb, true) then return end
      if pcall(thumb.StartMoving, thumb) then
        pcall(thumb.StopMovingOrSizing, thumb)
      end
      if not pcall(thumb.StartMoving, thumb) then return end
      input.dragging = true
      U.RegisterUpdate(updateId, 0, Follow)
      Follow()
    end)
    thumb:SetScript("OnDragStop", FinishDrag)
    thumb:SetScript("OnHide", FinishDrag)

    track:SetScript("OnMouseDown", function()
      local slider = Slider()
      if not slider then return end
      Apply(slider, L.SliderValueAt(row, slider))
      L.PaintThumb(row.uuiSliderName)
    end)
    row.uuiSliderInput = input
  end

  row.uuiSliderName = name
  pcall(input.track.ClearAllPoints, input.track)
  pcall(input.track.SetPoint, input.track, "LEFT", row, "CENTER", L.Col().sliderX, list.sliderY)
  pcall(input.track.SetWidth, input.track, list.sliderWidth)
  pcall(input.track.SetFrameLevel, input.track, level)
  pcall(input.knob.SetFrameLevel, input.knob, level + 1)
  pcall(input.thumb.SetFrameLevel, input.thumb, level + 2)
  pcall(input.track.Show, input.track)
  pcall(input.knob.Show, input.knob)
  pcall(input.thumb.Show, input.thumb)

  -- The client slider keeps its bar but not the mouse or its own thumb.
  local slider = U.G(name)
  if slider then
    pcall(slider.EnableMouse, slider, false)
    local native = gs.Read(slider, "GetThumbTexture")
    if native then U.HideRegion(native) end
    slider.uuiForeverRow = row
  end
  L.PaintThumb(name)
  return input
end

-- Places the knob -- and, when no drag is running, the input handle on it --
-- from the slider's value. Called on every value change, whoever made it.
function L.PaintThumb(name)
  local slider = U.G(name)
  local row = slider and slider.uuiForeverRow
  local input = row and row.uuiSliderInput
  if not input or row.uuiSliderName ~= name then return end
  local list = M.foreverWow.list
  local offset = L.KnobOffset(slider)

  -- During a drag the knob is the cursor's and the handle is the client's
  -- to move: re-anchoring either would fight the drag.
  if not input.dragging then
    pcall(input.knob.ClearAllPoints, input.knob)
    pcall(input.knob.SetPoint, input.knob, "LEFT", row, "CENTER",
          L.Col().sliderX + offset, list.sliderY)
    pcall(input.thumb.ClearAllPoints, input.thumb)
    pcall(input.thumb.SetPoint, input.thumb, "LEFT", row, "CENTER",
          L.Col().sliderX + offset, list.sliderY)
  end

  -- IsEnabled returns 1 / 0 on this client, not a boolean.
  local enabled = gs.Read(slider, "IsEnabled")
  local shade = (enabled == 0 or enabled == false) and 0.5 or 1
  if input.knob.uuiFace then
    pcall(input.knob.uuiFace.SetVertexColor, input.knob.uuiFace, shade, shade, shade, 1)
  end
end

-- ---------------------------------------------------------------------------
-- Dropdown steppers (user request, 2026-09-22)
--
-- Forever's settings dropdown is Metal2DropdownWithSteppersAndLabelTemplate: a
-- back arrow left of the dropdown and a next arrow right of it, each on the
-- same common-dropdown-c-button bed, stepping to the previous / next option.
-- The client's dropdowns have none, so each dropdown row gets two owned
-- buttons, anchored to the row at the dropdown's measured edges (a numeric
-- width read once per layout, never the native frame as an anchor).
--
-- Stepping reuses the client's own option list and handler rather than
-- keeping a copy: the dropdown's initialize function is run with
-- UIDropDownMenu_AddButton briefly swapped for a collector, which yields the
-- same info tables the open menu would build; the chosen entry's func is then
-- called the way a 1.12 menu row calls it -- `this` a stand-in row carrying
-- that entry's value, text and id -- so the client applies the setting
-- itself. Working source for the 1.12 contract (UIDropDownMenu.lua), not a
-- probe of this client's menu: if a step selects without applying, this is
-- the place to look. Every global swapped here is restored even on error.
-- ---------------------------------------------------------------------------
-- What the client's menu globals hold for this dropdown: its frame or its
-- name, whichever type the client itself stores there (a 1.12 client stores
-- the name; an unknown one is matched rather than assumed).
function L.MenuRef(dropdown, current)
  if type(current) == "table" then return dropdown end
  return gs.Read(dropdown, "GetName") or dropdown
end

function L.DropdownEntries(dropdown)
  local init = dropdown and dropdown.initialize
  if type(init) ~= "function" then return nil end

  local entries = {}
  local savedAdd = UIDropDownMenu_AddButton
  local savedInit = UIDROPDOWNMENU_INIT_MENU
  local savedThis = this
  -- Each entry is COPIED as it is added. /uui step probe
  -- (UnrealUIDiagDB.gameSettingsStep, 2026-09-22) read all twenty Resolution
  -- entries as the same "3440x1440 (Wide)", checked: the client's initializer
  -- reuses one info table for every option and the real AddButton copies its
  -- fields, so keeping the table kept only the last option, twenty times.
  UIDropDownMenu_AddButton = function(info, level)
    if (tonumber(level) or 1) == 1 and type(info) == "table" and not info.isTitle then
      local copy = {}
      local key, value
      for key, value in pairs(info) do copy[key] = value end
      table.insert(entries, copy)
    end
  end
  -- Reading the list must not change what the dropdown shows. The probe
  -- (UnrealUIDiagDB.gameSettingsStep, 2026-09-22) read Graphics API's step
  -- land -- its handler set the pending selection -- and then come undone in
  -- the same click, because the arrows re-read the list and Graphics API's
  -- initializer re-syncs the dropdown from the saved CVar, which is only
  -- written on Okay. The selection fields and the shown text are therefore
  -- captured before the initializer runs and put back after it.
  local keep = {
    selectedID = dropdown.selectedID,
    selectedValue = dropdown.selectedValue,
    selectedName = dropdown.selectedName,
  }
  local textRegion = U.G((gs.Read(dropdown, "GetName") or "") .. "Text")
  local keepText = textRegion and gs.Read(textRegion, "GetText")

  UIDROPDOWNMENU_INIT_MENU = L.MenuRef(dropdown, savedInit)
  this = dropdown
  -- While the list is read, a selection call the initializer makes is ours,
  -- not the player's: the repaint hook below ignores it. Without this the
  -- initializer's own SetSelectedValue scheduled a repaint, which read the
  -- list again, every tick -- reported in game 2026-09-22 as the open menu's
  -- right side flickering while rows were hovered.
  L.readingEntries = true
  local ok, err = pcall(init, 1)
  L.readingEntries = false
  UIDropDownMenu_AddButton = savedAdd
  UIDROPDOWNMENU_INIT_MENU = savedInit
  this = savedThis

  dropdown.selectedID = keep.selectedID
  dropdown.selectedValue = keep.selectedValue
  dropdown.selectedName = keep.selectedName
  if textRegion and keepText and gs.Read(textRegion, "GetText") ~= keepText then
    pcall(textRegion.SetText, textRegion, keepText)
  end
  L.lastInit = { ok = ok, err = err and tostring(err) or nil }
  return entries
end

-- The entry the dropdown shows now. The dropdown's own selection first -- the
-- probe found Resolution and Multisampling keep selectedID and Refresh,
-- GPU and Graphics API keep selectedValue -- then the entry the initializer
-- marked checked, then the one whose text the dropdown displays (which does
-- not always match: Resolution shows "3440x1440" for "3440x1440 (Wide)").
function L.DropdownCurrent(dropdown, entries)
  local count = table.getn(entries)
  local id = tonumber(dropdown.selectedID)
  if id and id >= 1 and id <= count then return id end
  local i
  local selected = dropdown.selectedValue
  if selected ~= nil then
    for i = 1, count do
      if entries[i].value ~= nil and tostring(entries[i].value) == tostring(selected) then
        return i
      end
    end
  end
  for i = 1, count do
    if entries[i].checked then return i end
  end
  local name = gs.Read(dropdown, "GetName")
  local shown = name and gs.Read(U.G(name .. "Text"), "GetText")
  for i = 1, table.getn(entries) do
    if shown and entries[i].text == shown then return i end
  end
  return nil
end

function L.StepDropdown(name, delta)
  local dropdown = U.G(name)
  local probe = L.StepProbeStart(name, delta, dropdown)
  local entries = dropdown and L.DropdownEntries(dropdown)
  L.StepProbeEntries(probe, entries)
  if not entries or table.getn(entries) == 0 then return L.StepProbeEnd(probe, "no entries") end
  local current = L.DropdownCurrent(dropdown, entries) or 0
  local target = current + delta
  probe.current, probe.target = current, target
  if target < 1 or target > table.getn(entries) then return L.StepProbeEnd(probe, "out of range") end
  local info = entries[target]
  if type(info.func) ~= "function" then return L.StepProbeEnd(probe, "no func") end

  local row = {
    value = info.value, arg1 = info.arg1, arg2 = info.arg2, checked = info.checked,
  }
  row.GetID = function() return target end
  row.GetText = function() return info.text end
  row.GetName = function() return "DropDownList1Button" .. target end
  row.GetParent = function() return U.G("DropDownList1") end

  -- Reported in game 2026-09-22: an arrow changed ANOTHER dropdown's value.
  -- A 1.12 option handler finds its dropdown through the open-menu state --
  -- UIDROPDOWNMENU_OPEN_MENU, or DropDownList1.dropdown via the row's parent
  -- -- and with no menu opened by the arrow that state still named the last
  -- dropdown whose menu was opened. All of it is pointed at this dropdown for
  -- the call and put back after.
  local list = U.G("DropDownList1")
  local savedThis = this
  local savedOpen = UIDROPDOWNMENU_OPEN_MENU
  local savedInit = UIDROPDOWNMENU_INIT_MENU
  local savedLevel = UIDROPDOWNMENU_MENU_LEVEL
  local savedListOwner = list and list.dropdown
  this = row
  UIDROPDOWNMENU_OPEN_MENU = L.MenuRef(dropdown, savedOpen)
  UIDROPDOWNMENU_INIT_MENU = L.MenuRef(dropdown, savedInit)
  UIDROPDOWNMENU_MENU_LEVEL = 1
  if list then list.dropdown = dropdown end
  row.owner = dropdown
  row.dropdown = dropdown
  probe.during = { open = L.Describe2(UIDROPDOWNMENU_OPEN_MENU),
                   init = L.Describe2(UIDROPDOWNMENU_INIT_MENU) }
  local beforeID, beforeValue = dropdown.selectedID, dropdown.selectedValue
  L.StepTrace("before func", name, { target = target, want = info.value, wantText = info.text })
  local okFunc, errFunc = pcall(info.func, info.arg1, info.arg2)
  L.StepTrace("after func", name, { ok = okFunc, err = errFunc and tostring(errFunc) or nil })
  probe.func = { ok = okFunc, err = errFunc and tostring(errFunc) or nil,
                 id = tostring(info.func), shape = "legacy" }
  -- Not every handler here is 1.12-shaped. The probe
  -- (UnrealUIDiagDB.gameSettingsStep, 2026-09-22) read Graphics API's
  -- handler returning cleanly from the `this`-style call with its selection
  -- untouched (selectedValue still dx12), after which its initializer put
  -- "DirectX 12" back. A modern handler takes the menu row as its first
  -- argument -- func(self, arg1, arg2) -- so when the legacy call changed
  -- nothing, the same row is passed that way. Only then: a handler that did
  -- act is never called twice.
  if dropdown.selectedID == beforeID and dropdown.selectedValue == beforeValue then
    local okSelf, errSelf = pcall(info.func, row, info.arg1, info.arg2)
    probe.funcSelf = { ok = okSelf, err = errSelf and tostring(errSelf) or nil,
                       changed = not (dropdown.selectedID == beforeID and
                                      dropdown.selectedValue == beforeValue) }
  end
  this = savedThis
  UIDROPDOWNMENU_OPEN_MENU = savedOpen
  UIDROPDOWNMENU_INIT_MENU = savedInit
  UIDROPDOWNMENU_MENU_LEVEL = savedLevel
  if list then list.dropdown = savedListOwner end

  -- The shown text is written from the chosen entry. A 1.12
  -- UIDropDownMenu_SetSelectedID / SetSelectedValue takes the text from the
  -- rows of DropDownList1, which hold whatever menu was opened last: the probe
  -- read Resolution showing "2x multisample" after its own handler had set its
  -- selectedID to 2. The selection itself is the handler's and is left alone.
  local textRegion = U.G(name .. "Text")
  if textRegion and info.text then
    local setText = U.G("UIDropDownMenu_SetText")
    local okText = false
    if type(setText) == "function" then
      okText = pcall(setText, info.text, dropdown)
    end
    local shown = gs.Read(textRegion, "GetText")
    if not okText or shown ~= info.text then
      pcall(textRegion.SetText, textRegion, info.text)
    end
  end
  probe.written = info.text
  L.pending = L.pending or {}
  L.pending[name] = { id = dropdown.selectedID, value = dropdown.selectedValue,
                      text = info.text }
  L.StepTrace("after text", name, {})

  -- The value the client now shows is laid out again at the bed's width.
  if U.Dropdown and type(U.Dropdown.SetControlHeight) == "function" then
    U.Dropdown.SetControlHeight(dropdown, dropdown.uuiDropdownHeight)
  end
  L.StepTrace("after layout", name, {})
  L.PaintSteppers(name)
  local row = dropdown.uuiForeverRow
  local steppers = row and row.uuiDropdownSteppers
  L.StepTrace("after paint", name, {
    width = gs.Number(dropdown, "GetWidth"),
    drawnWidth = L.Col().dropdownWidth,
    dropLeft = gs.Number(dropdown, "GetLeft"), dropRight = gs.Number(dropdown, "GetRight"),
    backLeft = steppers and gs.Number(steppers.back, "GetLeft"),
    nextLeft = steppers and gs.Number(steppers.next, "GetLeft"),
  })
  -- One tick later too: a client handler or the dropdown component's own
  -- deferred layout may still change the dropdown after this call returns.
  U.DeferOnce("gamesettings:steptrace:" .. name, function()
    L.StepTrace("next tick", name, {})
  end)
  L.StepProbeEnd(probe, "called")
end

-- Step trace (diagnostic, 2026-09-22): reported in game, Graphics API's arrow
-- still "not working well", and the last clicks left no step record -- so a
-- click may be landing on a disabled arrow. Every arrow click (enabled or
-- not), every arrow repaint, and every phase of a step is appended, with the
-- dropdown's shown text and selection at that moment, to
-- UnrealUIDiagDB.gameSettingsStepTrace (the last 150 events).
L.STEP_TRACE_MAX = 150

function L.StepTrace(event, name, extra)
  if type(UnrealUIDiagDB) ~= "table" then UnrealUIDiagDB = {} end
  local log = UnrealUIDiagDB.gameSettingsStepTrace
  if type(log) ~= "table" then
    log = {}
    UnrealUIDiagDB.gameSettingsStepTrace = log
  end
  local dropdown = name and U.G(name)
  local entry = {
    event = event, name = name, t = gs.TraceTime and gs.TraceTime() or nil,
    text = name and gs.Read(U.G(name .. "Text"), "GetText"),
    selectedID = dropdown and dropdown.selectedID,
    selectedValue = dropdown and dropdown.selectedValue and tostring(dropdown.selectedValue),
  }
  local key, value
  for key, value in pairs(extra or {}) do entry[key] = value end
  table.insert(log, entry)
  while table.getn(log) > L.STEP_TRACE_MAX do table.remove(log, 1) end
end

-- ---------------------------------------------------------------------------
-- Step probe (diagnostic, 2026-09-22)
--
-- Reported in game: a dropdown arrow changes ANOTHER dropdown's value, and
-- pointing the menu globals at the stepped dropdown changed nothing. Every
-- arrow click is recorded to UnrealUIDiagDB.gameSettingsStep (the last 12):
-- the dropdown and its initialize function's identity beside every other
-- dropdown's (a shared initializer would build the wrong list), whether the
-- initializer ran, the entries it produced, the entry chosen, the menu
-- globals before and during the call, whether the option's handler raised,
-- and the displayed value and selection fields of EVERY dropdown on the page
-- before and after -- which names the dropdown that actually changed.
-- Read-only apart from the step itself.
-- ---------------------------------------------------------------------------
function L.Describe2(value)
  if value == nil then return "nil" end
  if type(value) == "table" then
    return "frame:" .. tostring(gs.Read(value, "GetName") or value)
  end
  return type(value) .. ":" .. tostring(value)
end

function L.StepSnapshot()
  local shot = {}
  local page = L.active
  local model = page and L.model[page.id]
  local i, j
  for i = 1, table.getn(model or {}) do
    for j = 1, table.getn(model[i].controls) do
      local control = model[i].controls[j]
      if control.kind == "dropdown" then
        local frame = U.G(control.name)
        shot[control.name] = {
          text = gs.Read(U.G(control.name .. "Text"), "GetText"),
          selectedID = frame and frame.selectedID,
          selectedValue = frame and frame.selectedValue and tostring(frame.selectedValue),
          selectedName = frame and frame.selectedName,
          init = frame and frame.initialize and tostring(frame.initialize),
        }
      end
    end
  end
  return shot
end

function L.StepProbeStart(name, delta, dropdown)
  local list = U.G("DropDownList1")
  return {
    at = U.DiagnosticStamp and U.DiagnosticStamp() or nil,
    name = name, delta = delta, found = dropdown ~= nil,
    initialize = dropdown and dropdown.initialize and tostring(dropdown.initialize),
    before = {
      open = L.Describe2(UIDROPDOWNMENU_OPEN_MENU),
      init = L.Describe2(UIDROPDOWNMENU_INIT_MENU),
      listOwner = L.Describe2(list and list.dropdown),
    },
    pageBefore = L.StepSnapshot(),
  }
end

function L.StepProbeEntries(probe, entries)
  probe.initRun = L.lastInit
  probe.entries = {}
  local i
  for i = 1, table.getn(entries or {}) do
    local e = entries[i]
    table.insert(probe.entries, {
      text = e.text, value = e.value and tostring(e.value),
      arg1 = e.arg1 and tostring(e.arg1), checked = e.checked and true or false,
      func = e.func and tostring(e.func),
    })
  end
end

function L.StepProbeEnd(probe, outcome)
  if not probe then return end
  probe.outcome = outcome
  probe.pageAfter = L.StepSnapshot()
  if type(U.AppendDiagnostic) == "function" then
    U.AppendDiagnostic("gameSettingsStep", probe)
  end
end

function L.DropdownSteppers(row, name, level)
  local token = M.foreverWow.control.dropdown
  local spec = token.stepper
  local steppers = row.uuiDropdownSteppers
  if not steppers then
    steppers = gs.BuildDropdownSteppers(row)
    if not steppers then return end
    steppers.onClick = function(delta, enabled)
      L.StepTrace("click", row.uuiDropdownName,
                  { delta = delta, enabled = enabled and true or false })
    end
    steppers.onStep = function(delta)
      L.StepDropdown(row.uuiDropdownName, delta)
    end
    row.uuiDropdownSteppers = steppers
  end

  -- A choice made in the open menu moves the selection too; the arrows follow
  -- it through the same global post-hook core/dropdown.lua already uses.
  if not L.selectionHooked and type(U.PostHookGlobal) == "function" then
    local function Repaint(frame)
      if L.readingEntries then return end
      local frameName = frame and gs.Read(frame, "GetName")
      if frameName and frame.uuiForeverRow then
        U.DeferOnce("gamesettings:steppers:" .. frameName, function()
          L.PaintSteppers(frameName)
        end)
      end
    end
    -- By id (Resolution, Multisampling) and by value (Refresh, GPU,
    -- Graphics API): the probe found both kinds on the Video page.
    local byId = U.PostHookGlobal("UIDropDownMenu_SetSelectedID", Repaint)
    local byValue = U.PostHookGlobal("UIDropDownMenu_SetSelectedValue", Repaint)
    L.selectionHooked = (byId or byValue) and true or false
  end

  row.uuiDropdownName = name
  local list = M.foreverWow.list
  local dropdown = U.G(name)
  L.HookPending(name)

  -- The width is the slider's (L.DropdownSpan), not the client's: every
  -- dropdown on the page is drawn the same, and the next arrow is placed from
  -- a number this file owns.
  --
  -- It also settles a defect reported in game 2026-09-22 with the step trace
  -- (UnrealUIDiagDB.gameSettingsStepTrace): at DX11 the arrow the player
  -- clicked as "left" logged delta +1 -- the NEXT arrow, sitting on the left.
  -- The width had been re-read off the client mid-paint, came back wrong, and
  -- dropped the next arrow onto the dropdown's left side, under the cursor.
  -- Capturing that read once was the first fix; deriving the width removes the
  -- read altogether, which is what rules/unreal-ui.md asks for.
  local width = L.Col().dropdownWidth or 0
  if dropdown and width > 0 then pcall(dropdown.SetWidth, dropdown, width) end
  if steppers.back then
    steppers.back:ClearAllPoints()
    steppers.back:SetPoint("RIGHT", row, "CENTER", L.Col().dropdownX - spec.gapLeft,
                           list.dropdownY)
    pcall(steppers.back.SetFrameLevel, steppers.back, level)
    steppers.back:Show()
  end
  if steppers.next then
    steppers.next:ClearAllPoints()
    steppers.next:SetPoint("LEFT", row, "CENTER", L.Col().dropdownX + width + spec.gapRight,
                           list.dropdownY)
    pcall(steppers.next.SetFrameLevel, steppers.next, level)
    steppers.next:Show()
  end
  if dropdown then dropdown.uuiForeverRow = row end
  L.PaintSteppers(name)
end

-- A step's choice stays PENDING until the page's Okay, and opening the menu
-- undoes it. Reported in game 2026-09-22: after the left arrow picked DX11,
-- opening the Graphics API menu showed DX12 again -- opening runs the
-- dropdown's initializer, which re-syncs it from the saved CVar (the same
-- behaviour the step trace caught when the arrows re-read the list). The
-- pending choice is therefore put back once the menu has opened, and dropped
-- when the player makes a choice in the menu, presses Okay, Cancel or
-- Defaults, or leaves the page.
function L.RestorePending(name)
  local pending = L.pending and L.pending[name]
  local dropdown = U.G(name)
  if not pending or not dropdown then return end
  dropdown.selectedID = pending.id
  dropdown.selectedValue = pending.value
  local text = U.G(name .. "Text")
  if text and pending.text and gs.Read(text, "GetText") ~= pending.text then
    pcall(text.SetText, text, pending.text)
    if U.Dropdown and type(U.Dropdown.SetControlHeight) == "function" then
      U.Dropdown.SetControlHeight(dropdown, dropdown.uuiDropdownHeight)
    end
  end
  L.PaintSteppers(name)
end

function L.ClearPending(name)
  if not L.pending then return end
  if name then L.pending[name] = nil else L.pending = {} end
end

function L.HookPending(name)
  L.pendingHooked = L.pendingHooked or {}

  -- Opening this dropdown's menu: put the pending choice back, now and once
  -- the client's own open path has finished.
  local button = U.G(name .. "Button")
  if button and not L.pendingHooked[name] then
    L.pendingHooked[name] = true
    U.PostHookScript(button, "OnClick", function()
      -- Which dropdown owns the menu now, noted here because the client may
      -- clear its own open-menu global before a row click reaches us.
      L.menuOwner = name
      L.RestorePending(name)
      U.DeferOnce("gamesettings:pending:" .. name, function() L.RestorePending(name) end)
    end)
  end

  -- A row picked in the open menu is the player's own choice: it replaces
  -- any pending arrow choice for the dropdown that opened the menu.
  if not L.pendingHooked["menu rows"] then
    L.pendingHooked["menu rows"] = true
    local max = tonumber(U.G("UIDROPDOWNMENU_MAXBUTTONS")) or 32
    local i
    for i = 1, max do
      local rowButton = U.G("DropDownList1Button" .. i)
      if rowButton then
        U.PostHookScript(rowButton, "OnClick", function()
          local owner = L.menuOwner
          if not owner then return end
          L.ClearPending(owner)
          -- The arrows follow the new choice once the client's handler is
          -- done. Reported in game 2026-09-22: after DX12 was picked in the
          -- menu the right arrow stayed enabled -- the only refresh was a
          -- SetSelectedID hook, and Graphics API selects by value.
          U.DeferOnce("gamesettings:menupick:" .. owner, function()
            L.PaintSteppers(owner)
          end)
        end)
      end
    end
  end

  -- Okay, Cancel and Defaults settle every choice on the page.
  local page = L.active
  if page and not L.pendingHooked["page:" .. page.id] then
    L.pendingHooked["page:" .. page.id] = true
    local suffixes = { "Okay", "Cancel", "Defaults" }
    local i
    for i = 1, 3 do
      local action = U.G(page.frame .. suffixes[i])
      if action then
        U.PostHookScript(action, "OnClick", function() L.ClearPending() end)
      end
    end
  end
end

-- Enabled where there is an option to step to and the dropdown is enabled.
function L.PaintSteppers(name)
  local dropdown = U.G(name)
  local row = dropdown and dropdown.uuiForeverRow
  local steppers = row and row.uuiDropdownSteppers
  if not steppers or row.uuiDropdownName ~= name then return end

  local count, current = 0, 0
  local button = U.G(name .. "Button")
  local enabled = gs.Read(button, "IsEnabled")
  local usable = not (enabled == 0 or enabled == false)
  if usable then
    local entries = L.DropdownEntries(dropdown)
    if entries then
      count = table.getn(entries)
      current = L.DropdownCurrent(dropdown, entries) or 0
    end
  end
  gs.SetDropdownStepperState(steppers, usable and current > 1,
                             usable and current > 0 and current < count)
  -- Logged only when the outcome changes, so scrolling does not flood it.
  local signature = tostring(usable) .. ":" .. count .. ":" .. current .. ":" ..
                    tostring(steppers.back and steppers.back.enabled) .. ":" ..
                    tostring(steppers.next and steppers.next.enabled)
  L.lastPaint = L.lastPaint or {}
  if L.lastPaint[name] ~= signature then
    L.lastPaint[name] = signature
    L.StepTrace("paint", name, { usable = usable, count = count, current = current,
                                 back = steppers.back and steppers.back.enabled or false,
                                 next = steppers.next and steppers.next.enabled or false })
  end
end

-- Relayout whenever the page itself changes what it shows: a tab switch, or a
-- checkbox that reveals or hides a dependent control. Deferred one tick so the
-- client's own handler has finished before the list reads the result.
function L.Watch(name)
  local object = U.G(name)
  if not object or L.hooked[name] then return end
  L.hooked[name] = true
  U.PostHookScript(object, "OnClick", function()
    if L.active then U.DeferOnce("gamesettings:list", function()
      if L.active then L.Layout(L.active) end
    end) end
  end)
end

-- ---------------------------------------------------------------------------
-- Meters
--
-- A value bar the client draws beside a control rather than a setting to
-- change: the Sound page's microphone level, beside Test Microphone. It is
-- adopted exactly like every other control -- captured first, reparented into
-- a row, handed back on detach -- and dressed in the Modern WoW XP bar's
-- material (user request, 2026-09-22), the theme this list already borrows
-- MinimalScrollBar from. Its own value handling stays the client's: only the
-- fill's texture path changes, which is the documented form of
-- StatusBar:SetStatusBarTexture here.
-- ---------------------------------------------------------------------------

-- The rect a meter draws in: an offset from the row's LEFT, plus a size.
function L.MeterRect(control, width)
  local list = M.foreverWow.list
  local meter = list.meter
  local col = L.Col()
  local x, barWidth
  if control.sidecar then
    -- Its owner carries its own text, so that row's label column is empty:
    -- the bar draws there, beside the button, as the client had it.
    x = list.labelInset + meter.sidecarInset
    barWidth = width / 2 + L.ControlEdge("meter") - x - meter.sidecarGap
    if col.dropdownWidth and barWidth > col.dropdownWidth then
      barWidth = col.dropdownWidth
    end
  else
    x = width / 2 + col.dropdownX
    barWidth = col.dropdownWidth or 0
  end
  if barWidth < meter.minWidth then barWidth = meter.minWidth end
  return x, barWidth, meter.height
end

-- Every Texture region of the bar, by index, as the path it currently draws.
-- One object's OWN regions, the bounded read gs.StripChrome documents.
function L.MeterRegions(object)
  local paths = {}
  if type(object.GetRegions) ~= "function" then return paths, nil end
  local ok, regions = pcall(function() return { object:GetRegions() } end)
  if not ok or not regions then return paths, nil end
  local i
  for i = 1, table.getn(regions) do
    if gs.Read(regions[i], "GetObjectType") == "Texture" then
      paths[i] = gs.Read(regions[i], "GetTexture") or ""
    end
  end
  return paths, regions
end

-- Gives the bar the theme's material and hides the client art around it, once
-- per attach. A walked region is never == what a getter returned
-- (widgets.region_walk_wrapper_lacks_setters), so the fill is found by its
-- PATH the way book.StripForeign does: the material is set first, and the one
-- region then carrying it is the fill. The path it had is kept from the
-- matching index of the walk taken before the change -- this client has no
-- GetStatusBarTexture to read it back from on detach, and nothing but that
-- material changed between the two walks. Everything else the bar drew is
-- hidden and remembered, so L.Detach hands the client its bar intact.
--
-- Safe to strip: UnrealUI adds no texture to the bar itself -- the theme's
-- background and border are the ROW's -- so the ban on re-stripping a frame
-- that carries addon art does not apply, and it runs once either way.
function L.DressMeterArt(state, object)
  local record = state.kept[object]
  if not record or record.regions then return end

  local before = L.MeterRegions(object)
  if type(object.SetStatusBarTexture) == "function" then
    pcall(object.SetStatusBarTexture, object, M.modernWow.texture.xpFill)
  end

  local after, regions = L.MeterRegions(object)
  local hidden = {}
  if regions then
    local mine = string.lower(M.modernWow.texture.xpFill)
    local i
    for i = 1, table.getn(regions) do
      local path = after[i]
      if type(path) == "string" and path ~= "" and
         string.find(string.lower(path), mine, 1, true) then
        record.statusTexture = before[i] or false
      elseif gs.Read(regions[i], "GetObjectType") == "Texture" and
             gs.Read(regions[i], "IsShown") then
        table.insert(hidden, regions[i])
        pcall(regions[i].Hide, regions[i])
      end
    end
  end
  record.regions = hidden
end

-- The theme's bar around the client's fill: a dark bed, the XP border halves
-- (one piece mirrored, as modules/xpbar.lua draws them) and -- only when the
-- stray is not a StatusBar and has no fill of its own -- the fill material
-- itself. All of it belongs to the ROW: an addon texture is never anchored to
-- a native widget (rules/unreal-ui.md), and a row that scrolls out of the
-- view hides its own art with it, which is the defect this fixes.
function L.MeterArt(control, row)
  local art = L.meters[control.name]
  if art and art.row ~= row then
    -- The bar changed rows: a filtered pass parks it on a hidden row of its
    -- own rather than on its owner's.
    local key, piece
    for key, piece in pairs(art.piece) do pcall(piece.Hide, piece) end
    art = nil
  end
  if art then return art end

  art = { row = row, piece = {} }
  art.back = row:CreateTexture(nil, "BACKGROUND")
  art.back:SetTexture(M.texture.plain)
  art.piece.back = art.back

  local object = U.G(control.name)
  if not object or type(object.SetStatusBarTexture) ~= "function" then
    art.fill = row:CreateTexture(nil, "ARTWORK")
    art.fill:SetTexture(M.modernWow.texture.xpFill)
    art.piece.fill = art.fill
  end

  -- The border draws above the client's own fill, which sits at the control's
  -- frame level, so it lives on a frame of its own one level up.
  art.top = CreateFrame("Frame", nil, row)
  pcall(art.top.EnableMouse, art.top, false)
  art.piece.top = art.top
  art.left = art.top:CreateTexture(nil, "OVERLAY")
  art.left:SetTexture(M.modernWow.texture.xpBorder)
  art.piece.left = art.left
  art.right = art.top:CreateTexture(nil, "OVERLAY")
  art.right:SetTexture(M.modernWow.texture.xpBorder)
  art.right:SetTexCoord(1, 0, 0, 1)
  art.piece.right = art.right

  L.meters[control.name] = art
  return art
end

function L.PlaceMeter(state, control, object, row, level, width)
  local list = M.foreverWow.list
  local bar = M.modernWow.xpbar
  local x, barWidth, height = L.MeterRect(control, width)

  pcall(object.SetWidth, object, barWidth)
  pcall(object.SetHeight, object, height)
  pcall(object.SetPoint, object, "LEFT", row, "LEFT", x, list.dropdownY)
  L.DressMeterArt(state, object)

  local art = L.MeterArt(control, row)
  art.back:ClearAllPoints()
  art.back:SetPoint("LEFT", row, "LEFT", x, list.dropdownY)
  art.back:SetWidth(barWidth)
  art.back:SetHeight(height)
  U.SetColor(art.back, M.Unpack(bar.background))
  art.back:Show()

  if art.fill then
    art.fill:ClearAllPoints()
    art.fill:SetPoint("LEFT", row, "LEFT", x, list.dropdownY)
    art.fill:SetWidth(barWidth)
    art.fill:SetHeight(height + bar.fillTopOverhang)
    art.fill:Show()
  end

  art.top:ClearAllPoints()
  art.top:SetPoint("LEFT", row, "LEFT", x, list.dropdownY)
  art.top:SetWidth(barWidth)
  art.top:SetHeight(height)
  pcall(art.top.SetFrameLevel, art.top, level + 1)
  art.top:Show()

  local pieceWidth = barWidth / 2 + bar.borderWidthExtra
  local pieceHeight = height + bar.borderHeightExtra
  art.left:ClearAllPoints()
  art.left:SetPoint("LEFT", art.top, "LEFT", -bar.borderOverhang, 0)
  art.left:SetWidth(pieceWidth)
  art.left:SetHeight(pieceHeight)
  art.left:Show()
  art.right:ClearAllPoints()
  art.right:SetPoint("RIGHT", art.top, "RIGHT", bar.borderOverhang, 0)
  art.right:SetWidth(pieceWidth)
  art.right:SetHeight(pieceHeight)
  art.right:Show()
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------
function L.PlaceControl(state, control, row, level, width)
  local list = M.foreverWow.list
  local object = U.G(control.name)
  if not object then return false end

  -- A meter is sized by the list as well as moved: the width the client gave
  -- its bar is the panel's, not this row's.
  L.Keep(state, object, {
    reparented = true,
    resized = control.kind == "slider" or control.kind == "meter",
    resizedHeight = control.kind == "meter",
  })
  -- A checkbox is parked, undrawn, in the vault and replaced on the row by
  -- L.CheckButton; everything else is reparented into the row itself.
  local parent = row
  if control.kind == "checkbox" then parent = L.Vault() or row end
  pcall(object.SetParent, object, parent)
  pcall(object.ClearAllPoints, object)

  -- A checkbox the client drew smaller than the rest is a sub-option of the
  -- one above it; Forever indents those by its indentSize.
  local indent = 0
  local size = gs.checkboxSize and gs.checkboxSize[control.name]
  if control.kind == "checkbox" and size and size < 24 then indent = list.indent end

  if control.kind == "checkbox" then
    pcall(object.SetPoint, object, "LEFT", row, "CENTER", L.Col().checkboxX,
          list.dropdownY)
    L.CheckButton(row, control.name, level, width, indent, control.label)
    L.Watch(control.name)
    return true
  elseif control.kind == "slider" then
    pcall(object.SetWidth, object, list.sliderWidth)
    pcall(object.SetPoint, object, "LEFT", row, "CENTER", L.Col().sliderX, list.sliderY)
    local i
    for i = 1, table.getn(L.SLIDER_EXTRAS) do
      local extra = U.G(control.name .. L.SLIDER_EXTRAS[i])
      if extra and gs.Read(extra, "IsShown") then L.HideKept(state, extra) end
    end
    L.ValueText(row, object, control.name)
    L.PaintValue(control.name)
    L.PlaceSteppers(row, control.name, level)
    -- The client slider's mouse flag is taken off by L.SliderInput; the flag
    -- it had is kept so detach puts it back.
    if state.kept[object] and state.kept[object].mouse == nil then
      state.kept[object].mouse = gs.Read(object, "IsMouseEnabled") and true or false
    end
    L.SliderInput(row, control.name, level + 1)
  elseif control.kind == "button" then
    -- At the control column, like every other control, in the window's own
    -- red-button face. Its own text is its label, so the row's label column
    -- stays empty; the client keeps the click, the hit area and the enabled
    -- state, as it does for Okay and Cancel.
    local height = gs.Number(object, "GetHeight") or 0
    if height < 8 or height > 40 then
      height = M.foreverWow.panel.buttonHeight
      pcall(object.SetHeight, object, height)
    end
    local room = L.Col().dropdownWidth or 0
    local width = gs.Number(object, "GetWidth") or 0
    if room > 0 and (width < 8 or width > room) then
      pcall(object.SetWidth, object, room)
    end
    pcall(object.SetPoint, object, "LEFT", row, "CENTER", L.Col().dropdownX,
          list.dropdownY)
    if type(gs.SkinButton) == "function" then gs.SkinButton(control.name) end
    if type(gs.DressButton) == "function" then gs.DressButton(object, height) end
  elseif control.kind == "meter" then
    L.PlaceMeter(state, control, object, row, level, width)
  else
    pcall(object.SetPoint, object, "LEFT", row, "CENTER", L.Col().dropdownX, list.dropdownY)
    L.DropdownSteppers(row, control.name, level)
  end
  gs.Relevel(object, level, 0)

  -- A button carries its own text, and a sidecar bar draws inside its owner's
  -- label column; every other control has a separate label FontString the row
  -- moves into that column.
  local label
  if control.kind ~= "button" and not control.sidecar then
    label = U.G(control.name .. (control.kind == "dropdown" and "Label" or "Text"))
  end
  if label then
    L.Keep(state, label, { text = control.label })
    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "LEFT", row, "LEFT", list.labelInset + indent, 0)
    U.SetStockFont(label, M.fontSize.normal, list.labelColor)
    if type(U.FitLabelText) == "function" then
      U.FitLabelText(label, control.label or "",
                     width / 2 + L.Col().labelRight - list.labelInset - indent)
    end
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Checkbox, rebuilt (user request, 2026-09-22)
--
-- The client's CheckButton draws nothing in the list any more. Its stock gold
-- check could not be taken off it by any Lua route on this client, each tried
-- and reported in game 2026-09-21/22:
--
--   * retexturing its checked slot: the stock check still drew;
--   * U.HideRegion on that slot, then SetCheckedTexture("") -- /uui gamefocus
--     then read the slot as nil and found no other texture region on the
--     button, yet the check still drew;
--   * SetAlpha(0) on the whole button: the check still drew.
--
-- So the engine draws that check from the button's checked state, outside
-- anything Lua reaches. The button is therefore parked in L.vault, a hidden
-- addon frame: a frame under a hidden parent is not drawn at all, while its
-- own shown flag -- which says whether the client wants the option offered --
-- and its checked state stay intact and readable. Everything the player sees
-- and clicks is L.CheckButton's: box, tick and label, from
-- checkmark-minimal.tga (M.foreverWow.control.checkbox).
--
-- A click is forwarded the way a real click reaches the client's checkbox:
-- the checked state is toggled with the button's own SetChecked, then the
-- button's own OnClick script runs, so whatever the client does on a click
-- (dependent options, immediate CVars) still happens, and Okay reads the
-- state as before. The handler is called in every argument shape this client
-- uses (knowledge.json / scripts.handler_arguments_direct): the legacy `this`
-- / `arg1` globals set, and (self, "LeftButton") passed directly. That call
-- is a working assumption, not a probe result: if a checkbox's option stops
-- applying, this is the place to look.
-- ---------------------------------------------------------------------------
function L.Vault()
  if L.vault then return L.vault end
  local ok, vault = pcall(CreateFrame, "Frame", "UnrealUIGameSettingsVault", UIParent)
  if not ok or not vault then return nil end
  pcall(vault.SetWidth, vault, 1)
  pcall(vault.SetHeight, vault, 1)
  pcall(vault.SetPoint, vault, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  pcall(vault.Hide, vault)
  L.vault = vault
  return vault
end

function L.ForwardClick(native)
  if not native then return end
  -- IsEnabled returns 1 / 0 on this client, not a boolean.
  local enabled = gs.Read(native, "IsEnabled")
  if enabled == 0 or enabled == false then return end

  local checked = gs.Read(native, "GetChecked")
  local want = not (checked and checked ~= 0)
  pcall(native.SetChecked, native, want)

  local handler
  if type(native.GetScript) == "function" then
    local ok, value = pcall(native.GetScript, native, "OnClick")
    if ok then handler = value end
  end
  if type(handler) == "function" then
    local oldThis, oldArg1 = this, arg1
    this = native
    arg1 = "LeftButton"
    pcall(handler, native, "LeftButton")
    this = oldThis
    arg1 = oldArg1
  end
  if type(gs.PaintCheck) == "function" then gs.PaintCheck(native) end
end

-- The owned checkbox for one row: a Button at the checkbox position, the box
-- and tick as its textures, and a label on the row. Created once per row.
function L.CheckButton(row, name, level, width, indent, text)
  local list = M.foreverWow.list
  local token = M.foreverWow.control.checkbox
  local box = row.uuiCheck
  if not box then
    local ok, button = pcall(CreateFrame, "Button", nil, row)
    if not ok or not button then return nil end
    box = button
    pcall(box.SetWidth, box, token.width)
    pcall(box.SetHeight, box, token.height)
    pcall(box.EnableMouse, box, true)
    -- A small target: the click area reaches a few units round the box.
    pcall(box.SetHitRectInsets, box, -3, -3, -3, -3)

    local face = gs.BuildOwnedCheckboxFace(box)
    box.face = face and face.box
    box.tick = face and face.tick

    box:SetScript("OnClick", function() L.ForwardClick(U.G(row.uuiCheckName)) end)

    row.uuiCheckLabel = U.CreateLabel(row, {
      size = M.fontSize.normal,
      color = list.labelColor,
      inherits = "GameFontNormal",
      justify = "LEFT",
    })
    row.uuiCheck = box
  end

  row.uuiCheckName = name
  pcall(box.ClearAllPoints, box)
  -- On the dropdown's line, not the row's centre: a stepper's bed is drawn
  -- list.dropdownY above centre, and the box is the same control in a column
  -- (user request, 2026-09-22).
  pcall(box.SetPoint, box, "LEFT", row, "CENTER", L.Col().checkboxX,
        list.dropdownY)
  pcall(box.SetFrameLevel, box, level)
  pcall(box.Show, box)

  local label = row.uuiCheckLabel
  if label then
    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "LEFT", row, "LEFT", list.labelInset + indent, 0)
    if type(U.FitLabelText) == "function" then
      U.FitLabelText(label, text or "",
                     width / 2 + L.Col().labelRight - list.labelInset - indent)
    else
      pcall(label.SetText, label, text or "")
    end
    pcall(label.Show, label)
  end

  -- gs.PaintCheck draws from these: the native button's state, this face.
  local native = U.G(name)
  if native then
    native.uuiForeverTick = box.tick
    native.uuiForeverBox = box.face
    if type(gs.PaintCheck) == "function" then gs.PaintCheck(native) end
  end
  return box
end

-- The page's own chrome, moved into Forever's places: Defaults into the list
-- header, Okay and Cancel beside the window's Close, and the tab strip beside
-- Defaults, dressed as MinimalTabTemplate.
function L.PlaceChrome(state, page)
  local list = M.foreverWow.list
  local base = page.frame

  -- Defaults is centred on the header band rather than dropped Forever's 16
  -- from its top (user request, 2026-09-22: the band is shorter than the drop
  -- plus the button). Its horizontal inset is Forever's own.
  local defaults = U.G(base .. "Defaults")
  if defaults then
    L.Keep(state, defaults)
    pcall(defaults.ClearAllPoints, defaults)
    pcall(defaults.SetPoint, defaults, "RIGHT", gs.content, "TOPRIGHT",
          list.defaultsInset.x, -gs.CONTENT_HEADER / 2)
  end

  -- Cancel takes the window's bottom-right corner, where its own Close button
  -- used to sit before it was removed (user request, 2026-09-22), at the same
  -- insets; Okay stays to its left.
  local cancel, okay = U.G(base .. "Cancel"), U.G(base .. "Okay")
  if cancel and gs.panel then
    local inset = M.foreverWow.panel.buttonInset
    L.Keep(state, cancel)
    pcall(cancel.ClearAllPoints, cancel)
    pcall(cancel.SetPoint, cancel, "BOTTOMRIGHT", gs.panel, "BOTTOMRIGHT",
          -inset.right, inset.bottom)
  end
  if okay and cancel then
    L.Keep(state, okay)
    pcall(okay.ClearAllPoints, okay)
    pcall(okay.SetPoint, okay, "RIGHT", cancel, "LEFT", -M.foreverWow.panel.buttonGap, 0)
  end

  -- The tab strip is not drawn at all any more (user request, 2026-09-22):
  -- each tab is a sub-row of the page's own category row in the list at the
  -- left (gs.PageTabs / gs.SubRow), so the horizontal strip would be a second
  -- copy of the same control. The tabs stay alive, hidden, because they are
  -- still the client's own selection mechanism -- a sub-row clicks one -- and
  -- L.Watch keeps the post-hook that relayouts this list when a tab switches
  -- the page's containers. L.Keep records each one, so detach hands the page
  -- back with its strip shown exactly as it was.
  local i
  for i = 9, 1, -1 do
    local tab = U.G(base .. "Tab" .. i)
    if tab then
      L.Keep(state, tab, { resizedHeight = true })
      L.Watch(base .. "Tab" .. i)
      L.HideKept(state, tab)
    end
  end
end

-- Section boxes stay where the client put them, empty: their backdrop is made
-- transparent and their own text hidden, so no second framing appears behind
-- the list.
function L.ClearSections(state, model)
  local i
  for i = 1, table.getn(model) do
    local name = model[i].name
    local frame = name and U.G(name)
    if frame and not state.kept[frame] then
      L.Keep(state, frame, { box = gs.Read(frame, "GetBackdrop") ~= nil })
      pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
      pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
      local j
      for j = 1, table.getn(L.SECTION_EXTRAS) do
        local text = U.G(name .. L.SECTION_EXTRAS[j])
        if text and gs.Read(text, "IsShown") then L.HideKept(state, text) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- The control column, measured (user request, 2026-09-22)
--
-- Forever anchors every control to the row's CENTER. Forever's list is narrow,
-- so that reads as one column; this window's list is much wider, which left a
-- long empty run between a short label ("GPU") and its dropdown. The column is
-- therefore slid LEFT -- never right of Forever's own place -- until the
-- tightest row on the page keeps only `list.labelGap` between its label and
-- the leftmost unit its control draws. Every label stays untruncated, because
-- the row that needs the most room is the one that sets the column.
--
-- A control reaches further left than its own X token: a slider's Back stepper
-- hangs `stepperGap` + its width past the track, and a dropdown's hangs
-- `gapLeft` + its width past the bed, with its bed drawn `bedSize` wide around
-- a narrower button. Those overheads come from the same tokens that place the
-- steppers, so the gap holds if either is re-measured.
--
-- L.col is what every placement reads; L.Col() keeps it filled, so a paint
-- that runs outside a relayout (a slider drag, a stepper repaint) uses the
-- same column the rows were laid out on.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- One width for every dropdown, the slider's (user request, 2026-09-22)
--
-- Forever's dropdowns are each as wide as the client made them, which on this
-- page read as three different widths in a column. They are all drawn at the
-- slider's instead: the same span from the left edge of the Back arrow to the
-- right edge of the Forward arrow, so a slider row and a dropdown row line up
-- on both edges.
--
-- Both spans are derived from the tokens that place the parts, never stored,
-- so re-measuring a stepper or the slider track moves both together. A
-- stepper's bed is drawn `bedSize` wide around a narrower button, so it
-- reaches (bedSize - width) / 2 past the button on each side; the slider's
-- arrows are drawn at their own width with no bed.
-- ---------------------------------------------------------------------------

-- The slider group's drawn span: its left edge as an offset from the row's
-- CENTER, and its width.
function L.SliderSpan()
  return gs.SliderControlSpan()
end

-- The dropdown bed's LEFT, as an offset from the row's CENTER, and its width:
-- whatever puts its arrows exactly where the slider's are. M.foreverWow.list
-- keeps Forever's own dropdownX as the measurement, but the column is this.
function L.DropdownSpan()
  return gs.DropdownControlSpan()
end

L.col = {}

function L.SetColumn(shift)
  local list = M.foreverWow.list
  local edge = L.SliderSpan()
  L.col.shift = shift
  -- Every control family starts on one line: the left edge of its left arrow
  -- (user request, 2026-09-22). That is the slider's, which a dropdown already
  -- shares, so it is the checkbox that moves -- 3 units right of Forever's own
  -- column, which sits at the slider GROUP's edge rather than its arrow's.
  L.col.checkboxX = edge + shift
  L.col.sliderX = list.sliderX + shift
  local dropdownX, dropdownWidth = L.DropdownSpan()
  L.col.dropdownX = dropdownX + shift
  L.col.dropdownWidth = dropdownWidth
  L.col.labelRight = list.labelRight + shift
  return L.col
end

function L.Col()
  if not L.col.checkboxX then L.SetColumn(0) end
  return L.col
end

-- A hidden FontString in the label's own font, used to measure a label's full
-- width before it is fitted: the live label may already carry a "..." from an
-- earlier pass, so it cannot be measured.
function L.Ruler()
  if L.ruler then return L.ruler end
  if not L.child or type(U.CreateLabel) ~= "function" then return nil end
  local ok, label = pcall(U.CreateLabel, L.child, {
    size = M.fontSize.normal,
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if not ok or not label then return nil end
  pcall(label.Hide, label)
  L.ruler = label
  return L.ruler
end

-- The label column's inset for one control: a checkbox the client drew smaller
-- than the rest is a sub-option, as in L.PlaceControl.
function L.Indent(control)
  local size = gs.checkboxSize and gs.checkboxSize[control.name]
  if control.kind == "checkbox" and size and size < 24 then
    return M.foreverWow.list.indent
  end
  return 0
end

-- The leftmost unit this kind of control draws, as an offset from the row's
-- CENTER, at Forever's unshifted column.
function L.ControlEdge(kind)
  -- One line for all three families: the slider's left arrow, which the
  -- dropdown's left stepper and the checkbox box are both placed on.
  local left = L.SliderSpan()
  return left
end

-- The rightmost unit this control draws, as an offset from the row's CENTER,
-- at Forever's unshifted column. A slider's is its value rather than its
-- Forward arrow: the value sits list.valueGap right of the track, which is
-- further out than the arrow's stepperGap.
function L.ControlRight(control)
  local list = M.foreverWow.list
  local token = M.foreverWow.control
  if control.kind == "slider" then
    local text = L.values[control.name]
    local measured = 0
    if text then
      local ok, value = pcall(text.GetStringWidth, text)
      measured = (ok and tonumber(value)) or 0
    end
    if measured <= 0 then measured = list.valueWidth or 0 end
    return list.sliderX + list.sliderWidth + list.valueGap + measured
  elseif control.kind == "dropdown" then
    local x, width = L.DropdownSpan()
    local _, rightPad = gs.DropdownStepperPads()
    return x + width + rightPad
  elseif control.kind == "button" or control.kind == "meter" then
    -- Drawn at the dropdown bed's own width, with no steppers either side.
    local x, width = L.DropdownSpan()
    return x + width
  end
  local edge = L.ControlEdge("checkbox")
  return edge + token.checkbox.width
end

function L.MeasureColumn(model, rowWidth)
  L.SetColumn(0)
  local list = M.foreverWow.list
  local ruler = L.Ruler()
  if not ruler or not model then return end

  -- room:  how far the column could move LEFT before the tightest label loses
  --        list.labelGap.
  -- spare: how far the rightmost control on the page is from the row's right
  --        edge, which is where the scrollbar's own column begins.
  local room, spare
  local i, j
  for i = 1, table.getn(model) do
    local section = model[i]
    local container = section.container and U.G(section.container)
    if not container or gs.Read(container, "IsShown") then
      for j = 1, table.getn(section.controls) do
        local control = section.controls[j]
        local object = U.G(control.name)
        -- A sidecar bar draws inside its owner's label column, not on the
        -- control column, so it never decides where that column sits.
        if object and gs.Read(object, "IsShown") and not control.sidecar and
           L.Matches(section, control) then
          local text = control.label or ""
          pcall(ruler.SetWidth, ruler, 0)
          pcall(ruler.SetText, ruler, text)
          local ok, measured = pcall(ruler.GetStringWidth, ruler)
          measured = (ok and tonumber(measured)) or 0
          if measured <= 0 and text ~= "" then
            -- The hidden ruler reported nothing for a label that has text:
            -- every width below would be wrong and the column would slide
            -- onto the labels. Leave it where Forever puts it.
            return
          end
          local indent = L.Indent(control)
          local free = rowWidth / 2 + L.ControlEdge(control.kind) -
                       (list.labelInset + indent + measured) - list.labelGap
          if not room or free < room then room = free end
          local tail = rowWidth / 2 - L.ControlRight(control)
          if not spare or tail < spare then spare = tail end
        end
      end
    end
  end

  -- The column is placed from the RIGHT (user request, 2026-09-22): the gap
  -- between the rightmost control and the scrollbar is closed by
  -- list.rightGapTrim of itself. That gap is the row's own remainder plus the
  -- padding and the bare space the bar sits in, all of which is empty.
  if spare and spare > 0 then
    local gap = spare + list.padRight + list.scrollbarGap
    L.SetColumn(gap * (list.rightGapTrim or 0))
  elseif spare and spare < 0 then
    -- A control overhangs the row: pull the column back inside it, even though
    -- the tightest label may then be truncated (`room` says by how much it
    -- misses its gap).
    L.SetColumn(spare)
  end
end

function L.Layout(page)
  local model = L.model[page.id]
  local state = L.saved[page.id]
  if not model or not state or not L.child then return end
  local list = M.foreverWow.list

  local width = gs.Number(L.scroll, "GetWidth") or 0
  if width < 100 then
    width = (gs.Number(gs.host, "GetWidth") or 600) -
            (list.scrollbarWidth + list.scrollbarInset.right + list.scrollbarGap)
  end
  local rowWidth = width - list.padLeft - list.padRight
  pcall(L.child.SetWidth, L.child, width)
  -- The control column, before anything is placed on it.
  L.MeasureColumn(model, rowWidth)

  local base = (gs.Number(gs.host, "GetFrameLevel") or 1) + L.LEVEL_GAP
  pcall(L.scroll.SetFrameLevel, L.scroll, base)
  pcall(L.child.SetFrameLevel, L.child, base + 1)
  if L.bar then pcall(L.bar.SetFrameLevel, L.bar, base + 1) end

  local key, frame
  for key, frame in pairs(L.rows) do pcall(frame.Hide, frame) end
  for key, frame in pairs(L.headers) do pcall(frame.Hide, frame) end

  -- Painted from the offset: an element is placed at its list position moved
  -- up by the offset, and drawn only while it lies wholly inside the view.
  -- Hiding the row hides the client control on it; the control's own shown
  -- flag, which decides whether it has a row at all, is not touched.
  local view = gs.Number(L.child, "GetHeight") or 0
  local offset = L.offset or 0
  local function Place(object, y, height)
    local top = y + offset
    object:ClearAllPoints()
    object:SetPoint("TOPLEFT", L.child, "TOPLEFT", list.padLeft, top)
    if top <= 0 and top - height >= -view - 0.5 then
      object:Show()
      return true
    end
    object:Hide()
    return false
  end

  local y = -list.padTop
  local matched = 0
  local i, j
  for i = 1, table.getn(model) do
    local section = model[i]
    local container = section.container and U.G(section.container)
    local open = not container or gs.Read(container, "IsShown")
    if open then
      local visible = {}
      local rowHeight = math.max(list.rowHeight,
                                 M.foreverWow.control.dropdown.height)
      for j = 1, table.getn(section.controls) do
        local control = section.controls[j]
        local object = U.G(control.name)
        -- The control's own shown flag: it is the row's parent's now, so
        -- IsShown says whether the client wants it, not whether its old
        -- section happens to be visible.
        if object and gs.Read(object, "IsShown") then
          if L.Matches(section, control) then
            table.insert(visible, control)
          else
            -- Even a filtered-out native control must be moved into its hidden
            -- row; otherwise a page or tab opened under an active filter leaves
            -- that control drawing at its original panel position.
            local hiddenRow = L.Row(control.name)
            hiddenRow:SetWidth(rowWidth)
            pcall(hiddenRow.SetHeight, hiddenRow, rowHeight)
            pcall(hiddenRow.SetFrameLevel, hiddenRow, base + 2)
            pcall(hiddenRow.Hide, hiddenRow)
            L.PlaceControl(state, control, hiddenRow, base + 3, rowWidth)
          end
        end
      end

      if table.getn(visible) > 0 then
        if section.title then
          local header = L.Header(section)
          header:SetWidth(rowWidth)
          pcall(header.SetFrameLevel, header, base + 2)
          if header.title then header.title:SetText(section.title) end
          Place(header, y, list.sectionHeight)
          y = y - list.sectionHeight
        end

        for j = 1, table.getn(visible) do
          local control = visible[j]
          -- A bar that belongs to the control above it rides that row, in the
          -- label column a button leaves empty, instead of taking a line of
          -- its own. Its owner is placed first: the sort puts them on one
          -- line, left to right.
          local ridden = control.sidecar and L.rows[control.sidecar]
          if ridden then
            L.PlaceControl(state, control, ridden, base + 3, rowWidth)
          else
            local row = L.Row(control.name)
            -- Every line is one height (user request, 2026-09-22). It is
            -- never less than the dropdown's drawn bed, which overhangs its
            -- control above and below as WowStyle2Dropdown's does: at a
            -- smaller height consecutive dropdowns overlapped and the next
            -- bed covered the one above (reported in game 2026-09-22).
            row:SetWidth(rowWidth)
            pcall(row.SetHeight, row, rowHeight)
            pcall(row.SetFrameLevel, row, base + 2)
            Place(row, y, rowHeight)
            -- Every control is placed, shown row or not, so none is ever left
            -- drawing in its old section; and re-anchored on every paint,
            -- because a client control does not follow its row when the row
            -- alone is moved.
            L.PlaceControl(state, control, row, base + 3, rowWidth)
            matched = matched + 1
            y = y - rowHeight - list.spacing
          end
        end
      end
    end
  end

  local height = -y + list.padBottom

  if not L.empty then
    L.empty = U.CreateLabel(L.child, {
      size = M.fontSize.normal,
      color = M.color.textDim,
      inherits = "GameFontNormal",
      justify = "LEFT",
    })
    if L.empty then
      L.empty:SetPoint("TOPLEFT", L.child, "TOPLEFT", list.padLeft + 4,
                       -list.padTop - 8)
      L.empty:SetText(U.L("GAMESETTINGS_NO_MATCHES"))
    end
  end
  if L.empty then
    if matched == 0 and (L.filter or "") ~= "" then
      L.empty:Show()
    else
      L.empty:Hide()
    end
  end

  -- The tab strip stays down and the category list's sub-rows carry its state
  -- instead (user request, 2026-09-22). Re-hidden on every relayout because
  -- the client shows its own tabs again from its refresh paths, the same
  -- reason every control on a row is re-anchored above.
  for j = 1, 9 do
    local tab = U.G(page.frame .. "Tab" .. j)
    if tab and gs.Read(tab, "IsShown") then pcall(tab.Hide, tab) end
  end
  if type(gs.RenderList) == "function" then gs.RenderList() end

  L.UpdateRange(height)
  -- Update the active band's endpoint after UpdateRange has shown or hidden
  -- the scrollbar. A relayout can change that state without the cursor leaving
  -- its row, so HoverTick alone would not get a chance to repaint the bounds.
  if L.hovered and L.hovered.uuiHover then L.HoverTexture(L.hovered) end
end

-- The steppers at the ends of the range (user request, 2026-09-22: the arrow
-- changes when the list cannot scroll that way any more). Nothing else sets
-- their state -- they are the list's own Buttons, not a client scrollbar's --
-- so the list disables the one that cannot move, and the shared MinimalScroll-
-- Bar draws a disabled stepper as its normal cell at token.arrow.disabledAlpha
-- (the atlas ships no disabled cell). Its tick repaints them, so this only has
-- to set the state; it also takes the click away, which is the point.
function L.PaintArrows()
  if not L.bar then return end
  local value = gs.Number(L.bar, "GetValue") or 0
  local ok, low, high = pcall(L.bar.GetMinMaxValues, L.bar)
  low = (ok and tonumber(low)) or 0
  high = (ok and tonumber(high)) or 0

  local function Set(suffix, usable)
    local button = U.G("UnrealUIGameSettingsListBar" .. suffix)
    if not button then return end
    if usable then
      pcall(button.Enable, button)
    else
      pcall(button.Disable, button)
    end
  end
  -- Half a unit of tolerance: the offset is whole units, the Slider's value
  -- is not necessarily.
  Set("ScrollUpButton", value > low + 0.5)
  Set("ScrollDownButton", value < high - 0.5)
end

-- The list's own clamp on the offset a wheel turn or stepper click may reach
-- (user request, 2026-09-23: a page whose content already fits the view was
-- still scrollable, past the real rows into empty space below them).
-- SetMinMaxValues is documented to clamp SetValue into range, but that is
-- DOCUMENTED_NOT_RUNTIME_VERIFIED on this client and this Slider is already
-- flagged uncertain (L.Build's remark on GetValue/SetValue/GetMinMaxValues),
-- so every scroll input clamps against the content-height-derived L.range
-- itself rather than trusting the Slider to refuse an out-of-range value.
function L.Clamp(value)
  return math.max(0, math.min(L.range or 0, value or 0))
end

function L.UpdateRange(height)
  if not L.bar then return end
  local view = gs.Number(L.child, "GetHeight") or 0
  local range = math.max(0, (height or 0) - view)
  L.range = range
  L.laying = true
  pcall(L.bar.SetMinMaxValues, L.bar, 0, range)
  L.laying = false
  -- Content that shrank under the current offset (a tab switch, a collapsed
  -- option) is repainted from the clamped offset.
  if (L.offset or 0) > range then
    L.offset = range
    L.laying = true
    pcall(L.bar.SetValue, L.bar, range)
    L.laying = false
    if L.active then return L.Layout(L.active) end
  end
  if range > 0 then
    pcall(L.bar.Show, L.bar)
    if type(U.SetModernWowScrollbarProportion) == "function" then
      U.SetModernWowScrollbarProportion(L.bar, view, height)
    end
  else
    pcall(L.bar.Hide, L.bar)
  end
  L.PaintArrows()
end

-- ---------------------------------------------------------------------------
-- Entry point from gs.Attach, after the page is shown and skinned.
-- ---------------------------------------------------------------------------
function L.Attach(page, frame)
  if not L.Build() then return false end
  local model = L.Discover(page, frame)

  local state = { kept = {}, order = {} }
  L.saved[page.id] = state

  -- The client panel stays shown and keeps running its own scripts; it only
  -- stops being what is drawn. Unscaled, and held to the page box so no part
  -- of it can reach the category list.
  pcall(frame.SetScale, frame, 1)

  -- The panel stops taking the mouse while it is hosted as a list. It is
  -- stretched over the whole page box under the rows, and /uui gamefocus
  -- (2026-09-21) found it the only mouse-enabled frame covering the Video
  -- list, whose controls -- levels 18/19 above it, visible, mouse-enabled --
  -- received no OnEnter at all. Input-only and restored on detach; the
  -- panel's scripts and events are untouched.
  L.Keep(state, frame, { mouse = gs.Read(frame, "IsMouseEnabled") and true or false })
  pcall(frame.EnableMouse, frame, false)
  pcall(frame.ClearAllPoints, frame)
  pcall(frame.SetPoint, frame, "TOPLEFT", gs.host, "TOPLEFT", 0, 0)
  pcall(frame.SetWidth, frame, gs.Number(gs.host, "GetWidth") or 600)
  pcall(frame.SetHeight, frame, gs.Number(gs.host, "GetHeight") or 500)

  L.ClearSections(state, model)
  L.PlaceChrome(state, page)

  pcall(L.scroll.Show, L.scroll)
  L.ShowSearch()
  L.offset = 0
  if L.bar then
    L.laying = true
    pcall(L.bar.SetValue, L.bar, 0)
    L.laying = false
  end
  L.active = page
  L.Layout(page)
  L.StartHover()
  return true
end

-- ---------------------------------------------------------------------------
-- Row hover (user request, 2026-09-22): Forever's HoverBackground on every
-- line. A row's controls are its children, so the row's own OnEnter/OnLeave
-- would drop the highlight the moment the pointer reached the control; the
-- highlight instead follows the cursor, checked against each shown row's
-- rect a few times a second with the GetCursorPosition / GetEffectiveScale
-- pair (knowledge.json / api.getcursorposition_usable_for_hit_testing). It
-- runs only while a list page is attached.
-- ---------------------------------------------------------------------------
-- The hover surface's right edge in row-local coordinates. Every row uses the
-- same visual boundary: the scrollbar when it is present, otherwise the list
-- pane's right edge. The existing cursor hit test has already converted its
-- screen coordinates through the list scale, so the geometry below stays in
-- those same UI units.
function L.HoverRight(row)
  local hover = M.foreverWow.list.hover
  local right = hover.right
  local rowRight = gs.Number(row, "GetRight")
  if not rowRight then return right end

  local edge
  if L.bar and gs.Read(L.bar, "IsShown") then
    edge = gs.Number(L.bar, "GetLeft")
  elseif L.scroll then
    edge = gs.Number(L.scroll, "GetRight")
  end
  if edge then
    local scrollbarRight = edge - rowRight + hover.right
    if scrollbarRight > right then right = scrollbarRight end
  end
  return right
end

function L.HoverTexture(row)
  local hover = M.foreverWow.list.hover
  local texture = row.uuiHover
  if not texture then
    local ok
    ok, texture = pcall(row.CreateTexture, row, nil, "BACKGROUND")
    if not ok or not texture then return nil end
    pcall(texture.SetTexture, texture, M.texture.plain)
    U.SetColor(texture, M.Unpack(hover.color))
    pcall(texture.Hide, texture)
    row.uuiHover = texture
  end

  pcall(texture.ClearAllPoints, texture)
  pcall(texture.SetPoint, texture, "TOPLEFT", row, "TOPLEFT", hover.left, 0)
  pcall(texture.SetPoint, texture, "BOTTOMRIGHT", row, "BOTTOMRIGHT",
        L.HoverRight(row), 0)
  return texture
end

function L.HoverTick()
  if not L.active or not L.child then return L.StopHover() end
  local cursor = U.G("GetCursorPosition")
  if type(cursor) ~= "function" then return end
  local ok, x, y = pcall(cursor)
  local scale = gs.Number(L.child, "GetEffectiveScale")
  x, y = ok and tonumber(x), ok and tonumber(y)
  if not x or not y or not scale or scale <= 0 then return end
  x, y = x / scale, y / scale

  local over
  local name, row
  for name, row in pairs(L.rows) do
    if gs.Read(row, "IsVisible") then
      local left, right = gs.Number(row, "GetLeft"), gs.Number(row, "GetRight")
      local top, bottom = gs.Number(row, "GetTop"), gs.Number(row, "GetBottom")
      local hover = M.foreverWow.list.hover
      local hoverLeft = left and left + hover.left
      local hoverRight = right and right + L.HoverRight(row)
      if hoverLeft and hoverRight and top and bottom and x >= hoverLeft and x <= hoverRight and
          y >= bottom and y <= top then
        over = row
      end
    end
  end

  if over == L.hovered then return end
  if L.hovered and L.hovered.uuiHover then pcall(L.hovered.uuiHover.Hide, L.hovered.uuiHover) end
  L.hovered = over
  if over then
    local texture = L.HoverTexture(over)
    if texture then pcall(texture.Show, texture) end
  end
end

function L.StartHover()
  U.RegisterUpdate("gamesettings.hover", M.foreverWow.list.hover.interval, L.HoverTick)
end

function L.StopHover()
  U.UnregisterUpdate("gamesettings.hover")
  if L.hovered and L.hovered.uuiHover then pcall(L.hovered.uuiHover.Hide, L.hovered.uuiHover) end
  L.hovered = nil
end

-- ---------------------------------------------------------------------------
-- /uui gamefocus -- input trace for the list
--
-- Reported in game 2026-09-21: on the list pages no control takes input --
-- dropdowns do not open, checkboxes do not toggle, sliders do not move -- and
-- the slider thumb is not drawn. The earlier canvas-page failure was a level
-- inversion (gs.Relevel); whether this one is levels, strata, a frame over the
-- rows, or the same stale-geometry behaviour the scroll showed
-- (widgets.reparented_native_widget_ignores_scroll_offset) is not known, so
-- this measures instead of guessing.
--
-- While on, it samples GetMouseFocus by NAME every 0.1 s -- never by identity,
-- and a nil focus proves nothing (api.getmousefocus_not_identity_comparable) --
-- and counts OnEnter on every list control, which is the hit-test evidence
-- that record asks for. Stopping writes both, plus each control's geometry,
-- level, strata, mouse flag and (for a slider) its thumb, to
-- UnrealUIDiagDB.gameSettingsFocus. Read-only apart from the OnEnter
-- post-hooks, which only count.
-- ---------------------------------------------------------------------------
L.trace = nil

function L.Rect(object)
  if not object then return nil end
  return {
    l = gs.Number(object, "GetLeft"), t = gs.Number(object, "GetTop"),
    r = gs.Number(object, "GetRight"), b = gs.Number(object, "GetBottom"),
  }
end

function L.Describe(object)
  if not object then return nil end
  local parent = gs.Read(object, "GetParent")
  return {
    name = gs.Read(object, "GetName"),
    type = gs.Read(object, "GetObjectType"),
    rect = L.Rect(object),
    level = gs.Number(object, "GetFrameLevel"),
    strata = gs.Read(object, "GetFrameStrata"),
    mouse = gs.Read(object, "IsMouseEnabled"),
    shown = gs.Read(object, "IsShown") and true or false,
    visible = gs.Read(object, "IsVisible") and true or false,
    enabled = gs.Read(object, "IsEnabled"),
    parent = parent and gs.Read(parent, "GetName") or (parent and "<unnamed>") or nil,
    scale = gs.Number(object, "GetEffectiveScale"),
  }
end

function L.TraceSample()
  local trace = L.trace
  if not trace then return end
  local focus = U.G("GetMouseFocus")
  local name = "<nil>"
  if type(focus) == "function" then
    local ok, frame = pcall(focus)
    if ok and frame then
      name = gs.Read(frame, "GetName") or "<unnamed>"
      if not trace.focusInfo[name] then trace.focusInfo[name] = L.Describe(frame) end
    end
  end
  trace.focus[name] = (trace.focus[name] or 0) + 1
end

function U.GameSettingsFocusTrace()
  if L.trace then
    local trace = L.trace
    L.trace = nil
    U.UnregisterUpdate("gamesettings.focus")

    local controls = {}
    local page = L.active
    local model = page and L.model[page.id]
    local i, j
    for i = 1, table.getn(model or {}) do
      for j = 1, table.getn(model[i].controls) do
        local control = model[i].controls[j]
        local object = U.G(control.name)
        local entry = L.Describe(object) or { name = control.name }
        entry.kind = control.kind
        entry.enters = trace.enters[control.name] or 0
        entry.row = L.Describe(L.rows[control.name])
        if control.kind == "slider" then
          local thumb = gs.Read(object, "GetThumbTexture")
          entry.thumb = thumb and {
            texture = gs.Read(thumb, "GetTexture"),
            shown = gs.Read(thumb, "IsShown") and true or false,
            rect = L.Rect(thumb),
            w = gs.Number(thumb, "GetWidth"), h = gs.Number(thumb, "GetHeight"),
          } or "none"
          entry.value = gs.Number(object, "GetValue")
          local okRange, low, high = pcall(object.GetMinMaxValues, object)
          if okRange then entry.min, entry.max = low, high end
        elseif control.kind == "checkbox" then
          -- Every texture on the box: reported in game 2026-09-22, the stock
          -- check still draws after its checked slot was hidden AND emptied
          -- through SetCheckedTexture(""), so it may be another region. A
          -- read-only region walk in a diagnostic, one control, no writes.
          entry.checked = gs.Read(object, "GetChecked")
          entry.slots = {}
          local slotNames = { "GetNormalTexture", "GetPushedTexture",
                              "GetCheckedTexture", "GetDisabledCheckedTexture",
                              "GetHighlightTexture", "GetDisabledTexture" }
          local k
          for k = 1, table.getn(slotNames) do
            local slot = gs.Read(object, slotNames[k])
            if slot then
              entry.slots[slotNames[k]] = {
                texture = gs.Read(slot, "GetTexture"),
                shown = gs.Read(slot, "IsShown") and true or false,
                alpha = gs.Number(slot, "GetAlpha"),
                rect = L.Rect(slot),
              }
            end
          end
          local okRegions, regions = pcall(function() return { object:GetRegions() } end)
          entry.regions = {}
          if okRegions and regions then
            for k = 1, table.getn(regions) do
              local region = regions[k]
              local layer
              if type(region.GetDrawLayer) == "function" then
                local okLayer, value = pcall(region.GetDrawLayer, region)
                if okLayer then layer = value end
              end
              table.insert(entry.regions, {
                type = gs.Read(region, "GetObjectType"),
                name = gs.Read(region, "GetName"),
                texture = gs.Read(region, "GetTexture"),
                shown = gs.Read(region, "IsShown") and true or false,
                alpha = gs.Number(region, "GetAlpha"),
                layer = layer,
                rect = L.Rect(region),
              })
            end
          end
        elseif control.kind == "dropdown" then
          entry.button = L.Describe(U.G(control.name .. "Button"))
          -- Where the value text actually is, and what it is anchored to:
          -- reported in game 2026-09-21, the GPU value draws outside its bed.
          local text = U.G(control.name .. "Text")
          if text then
            local points = {}
            local p
            for p = 1, (gs.Number(text, "GetNumPoints") or 0) do
              local ok, point, relative, relativePoint, x, y = pcall(text.GetPoint, text, p)
              if ok and point then
                table.insert(points, point .. ">" .. tostring(relative and
                  (gs.Read(relative, "GetName") or "<unnamed>")) .. ":" ..
                  tostring(relativePoint) .. " " .. tostring(x) .. "," .. tostring(y))
              end
            end
            entry.text = {
              text = gs.Read(text, "GetText"),
              rect = L.Rect(text),
              w = gs.Number(text, "GetWidth"), h = gs.Number(text, "GetHeight"),
              stringWidth = gs.Number(text, "GetStringWidth"),
              justifyH = gs.Read(text, "GetJustifyH"),
              shown = gs.Read(text, "IsShown") and true or false,
              points = points,
            }
          end
          entry.left = L.Rect(U.G(control.name .. "Left"))
          -- Reported in game 2026-09-22: the bottom of the drawn bed is hidden.
          -- Every texture on the dropdown and on its button, with layer and
          -- rect, so whatever covers it can be named. Read-only.
          entry.regions = {}
          local sources = { object, U.G(control.name .. "Button") }
          local k, j
          for k = 1, 2 do
            local src = sources[k]
            local okRegions, regions = false, nil
            if src then
              okRegions, regions = pcall(function() return { src:GetRegions() } end)
            end
            if okRegions and regions then
              for j = 1, table.getn(regions) do
                local region = regions[j]
                local layer
                if type(region.GetDrawLayer) == "function" then
                  local okLayer, value = pcall(region.GetDrawLayer, region)
                  if okLayer then layer = value end
                end
                table.insert(entry.regions, {
                  owner = k == 1 and "dropdown" or "button",
                  type = gs.Read(region, "GetObjectType"),
                  name = gs.Read(region, "GetName"),
                  texture = gs.Read(region, "GetTexture"),
                  shown = gs.Read(region, "IsShown") and true or false,
                  alpha = gs.Number(region, "GetAlpha"),
                  layer = layer,
                  rect = L.Rect(region),
                })
              end
            end
          end
        end
        table.insert(controls, entry)
      end
    end

    U.SaveDiagnostic("gameSettingsFocus", {
      page = page and page.id,
      samples = trace.samples,
      focus = trace.focus,
      focusInfo = trace.focusInfo,
      controls = controls,
      list = { scroll = L.Describe(L.scroll), child = L.Describe(L.child),
               bar = L.Describe(L.bar), host = L.Describe(gs.host),
               panel = L.Describe(gs.panel),
               page = page and L.Describe(U.G(page.frame)) },
    })
    U.Print("gamefocus: stopped, saved to UnrealUIDiagDB.gameSettingsFocus - " ..
            "|cffffff00/reload|r then read " .. U.SavedVariablesHint())
    return
  end

  if not L.active then
    U.Print("gamefocus: open Video, Sound or Interface first.")
    return
  end
  L.trace = { samples = 0, focus = {}, focusInfo = {}, enters = {} }
  local page = L.active
  local model = L.model[page.id] or {}
  local i, j
  for i = 1, table.getn(model) do
    for j = 1, table.getn(model[i].controls) do
      local name = model[i].controls[j].name
      local targets = { name }
      if model[i].controls[j].kind == "dropdown" then table.insert(targets, name .. "Button") end
      local k
      for k = 1, table.getn(targets) do
        local key = targets[k]
        if not L.hooked["enter:" .. key] and U.G(key) then
          L.hooked["enter:" .. key] = true
          U.PostHookScript(U.G(key), "OnEnter", function()
            if L.trace then L.trace.enters[name] = (L.trace.enters[name] or 0) + 1 end
          end)
        end
      end
    end
  end
  U.RegisterUpdate("gamesettings.focus", 0.1, function()
    if L.trace then
      L.trace.samples = L.trace.samples + 1
      L.TraceSample()
    end
  end)
  U.Print("gamefocus: tracing - hover and click a checkbox, a dropdown and a " ..
          "slider for a few seconds each, then type |cffffff00/uui gamefocus|r again.")
end
