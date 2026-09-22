-- unrealUI :: modules/gamesettings.lua
--
-- One window for the client's four settings panels -- Video (OptionsFrame),
-- Sound (SoundOptionsFrame), Interface (UIOptionsFrame) and Key Bindings
-- (KeyBindingFrame) -- instead of four separate windows opened one at a time
-- from the Escape menu.
--
-- The four client panels are followed by an Unreal UI category. That category
-- renders the pages registered through modules/settings.lua in this same
-- window. When UnrealQuest is installed, the pages it registers there are
-- listed as a separate Unreal Quest category after it.
--
-- Structure copied from WoW Forever. In ForeverFrameXML-1.60.1.69913 there is
-- one SettingsPanel with a category list down the left, and a category is
-- either a list the panel builds itself or a *canvas*: a frame the panel does
-- not own, moved into its container while that category is selected
-- (Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua):
--
--   DisplayLayout             frame:SetParent(canvas)  ClearAllPoints  SetAllPoints
--   ClearCurrentCategoryCanvas  frame:SetParent(nil)   ClearAllPoints  Hide
--
-- Graphics, Audio, Interface and Keybindings are all just canvas categories of
-- that one window. Every page here is that kind, and exactly one client panel
-- is ever attached.
--
-- Evidence: knowledge.json / frames.settings_panels_windowed_and_groupable
-- (probe settings.unified_window.v1, RUNTIME_MEASURED + USER_CONFIRMED_INGAME
-- 2026-09-21). What it settled, and what each point costs here:
--
--   * All four accept SetParent onto an addon frame, and the anchor set on them
--     survives their own OnShow. Two can be visible at once, so nothing in the
--     client forces one panel at a time.
--   * They are listed in UIPanelWindows as area="center", so they are only ever
--     shown with frame:Show() here. ShowUIPanel would hand them back to the
--     panel manager, which moves and closes center-area panels.
--   * A reparented frame KEEPS its own strata and level, which is why a page
--     still looked like the original window in the probe. Both are taken from
--     the host in Attach.
--   * The client re-applies OptionsFrame's own width on every show and does not
--     lay a panel out until it has been shown once (OptionsFrame reads 10 units
--     wide before that), so the window fits itself to the page and re-measures
--     on every selection rather than sizing the page.
--   * KeyBindingFrame does not exist at login: it comes from the
--     Blizzard_BindingUI load-on-demand addon, which the Key Bindings page
--     loads the first time it is opened.
--
-- Each native page keeps its own Okay / Cancel / Defaults row. The addon-owned
-- Unreal UI category has one shared Okay / Cancel pair in the same footer seat;
-- it persists while its registered subpages switch beneath it.
--
-- The window is DRAWN as Forever draws its own (user request, 2026-09-21): the
-- ButtonFrameTemplateNoPortrait metal rim, the flat panel background, the
-- recessed Options_InnerFrame plate, and the category list's own two row
-- states, all from media/Textures/forever-wow/ through M.foreverWow. The
-- controls inside a hosted page are restyled from the same folder's Forever
-- control art (M.foreverWow.control). See the two chrome sections below.
--
-- That makes this a fourth visual family beside modern, classic-wow and
-- modern-wow, and like modern-wow it is exempt from the flat/sharp/near-black
-- language of rules/unreal-ui-design.md for exactly the surface whose purpose
-- is to reproduce someone else's chrome. It does not leak: no other module
-- reads M.foreverWow, and nothing in the shared token defaults changed.
--
-- knowledge.json / widgets.region_walk_wrapper_lacks_setters: on this client a
-- walked region is never == the object a getter returned, so a `keep` table
-- protects nothing. Two consequences, both deliberate here:
--
--   * Controls and named chrome are reached by GLOBAL NAME and changed through
--     their own accessors. Nothing looks for them by walking.
--   * gs.StripChrome is the single region walk, over one panel's OWN regions
--     and never its children, to take off the background and border the client
--     draws as regions rather than as a backdrop. It keeps nothing -- it cannot
--     -- and instead remembers every texture it hid so gs.Restore can show them
--     again when the page is handed back. Every control on these panels is a
--     child frame, so that walk cannot reach anything interactive.

local U = UnrealUI
local M = U.media

local G = U.RegisterModule("gamesettings")

-- Window metrics, matching modules/settings.lua so the two windows read as one
-- interface. Width is a floor: a page wider than this grows the window (see
-- gs.Fit), which is what OptionsFrame's client-owned width needs.
local gs = {
  -- The original 648-unit window gains the same 20-unit seat as the category
  -- list, so the page area keeps its width when the scrollbar is present.
  -- Options_InnerFrame is authored 886x618 and Forever draws it with
  -- useAtlasSize inside insets of 17/22 and 64/46; neither the insets nor the
  -- header scale, so the plate takes the whole reduction.
  --
  -- It is not squeezed as a whole to get there. It carries an authored
  -- vertical seam that separates the category list from the page, and
  -- squeezing or stretching the whole plate drags that seam into the list,
  -- which was tried and rejected. gs.BuildInnerPlate draws it as a 5x3 grid
  -- instead (M.foreverWow.options.innerSlice): rims and corners 1:1, the seam
  -- 1:1 at the list's right edge, and only the flat fields squeezed.
  -- Everything that does not fit the smaller page box is scaled inside it,
  -- which is what gs.Fit does.
  WIDTH = 721.44,       -- 801.6 * 0.90
  HEIGHT = 611.52,      -- 509.6 * 1.20
  -- The rows stay 30% narrower than Forever's 199 (user request, 2026-09-22),
  -- with a 20-unit seat added beside them for the conditional scrollbar.
  -- gs.BuildInnerPlate draws the plate's seam at the sidebar's new right edge.
  LIST_SCALE = 0.7,
  SIDEBAR_CONTENT_WIDTH = 139.3,
  SIDEBAR_SCROLLBAR_SEAT = 20,
  SIDEBAR_WIDTH = 139.3 + 20,
  -- The row label's inset, off Forever's 36 (user request, 2026-09-22: the
  -- menu text moved left). That 36 reserves room for an expand toggle, and
  -- none of these categories has one; the header band's label uses it too, so
  -- the list reads as one column.
  ROW_LABEL_INSET = 10,
  ROW_HEIGHT = 20,
  ROW_GAP = 0,
  -- Both section headers are list items and scroll with their rows.
  LIST_TOP = 0,
  -- The header band is as tall as the Close button it holds, plus 3 units
  -- above and below it (user request, 2026-09-22: "the height have to fit the
  -- close btn border"), rather than Forever's 64. The top rail forms the
  -- header border, with the title and X centred on it.
  HEADER_HEIGHT = 30,   -- M.foreverWow.control.close.size (24) + 3 + 3
  -- The close icon's adjustment from Forever's anchor: 3px right and 2px up.
  CLOSE_NUDGE = { x = 0, y = 2 },
  -- The page's own header band -- its title, its Legacy/Modern tabs, the
  -- Defaults button and the rule under them. Forever's is 50; this is 42 and
  -- then 35% off that (user requests, 2026-09-22).
  -- M.foreverWow.panel.listHeaderHeight stays the measurement. The tabs no
  -- longer live here at all -- they are sub-rows of the category list -- so
  -- the band holds only the title and the 22-unit Defaults button, both
  -- centred on it, which is what lets it go this low.
  CONTENT_HEADER = 27.3,   -- 42 * 0.65
  -- A page's tabs are drawn as sub-rows of its category row instead of a
  -- horizontal tab strip (user request, 2026-09-22). SUB_INDENT is how far
  -- their labels sit inside the parent's, and TOGGLE_SIZE / TOGGLE_RIGHT place
  -- the collapse control -- at the row's right edge, because the labels are
  -- flush left and Forever's own toggle seat at LEFT 9 is no longer free.
  SUB_INDENT = 12,
  TOGGLE_SIZE = 14,
  -- The +/- artwork stays inset inside its 14px click target, so its hover
  -- tint does not spill over the category list's yellow border.
  TOGGLE_FACE_SIZE = 10,
  -- Right-aligned on the LIST, not on the row (user request, 2026-09-22): the
  -- rows are narrower than the category list they sit in, so anchoring the
  -- toggles to the row's own edge left the column floating in the middle of
  -- the list. They hang off the sidebar's right edge instead, still children
  -- of their row, and still short of the plate's seam.
  TOGGLE_RIGHT = -5 - 20,
  subRows = {},      -- [page index] = its sub-rows, by tab index
  expanded = {},     -- [page.id] = false while its sub-rows are collapsed
  panel = nil,
  sidebar = nil,
  content = nil,
  host = nil,
  rows = {},
  active = nil,      -- page currently attached
  saved = {},        -- [page.id] = captured native parent/anchors/strata/scale
  hooked = {},       -- [button name] = original OnClick, for Restore
  stripped = {},     -- [page.id] = regions hidden by gs.StripChrome
  placed = {},       -- [page.id] = client objects this window moved on a canvas
  message = nil,     -- shown in place of a page that is not available
}

-- The recessed plate starts under the header's border rather than at Forever's
-- authored 64 (user request, 2026-09-22): the header is only as tall as its
-- Close button now, and the difference would otherwise be a dead strip between
-- the border and the plate. The category list keeps Forever's own 12-unit drop
-- below the plate's top edge.
--
-- The border is a bar, not a line -- the metal strip is its authored thickness
-- at the housing's scale -- so the plate clears the bar's own height and then
-- gs.HEADER_GAP of space under it (user request, 2026-09-22: a gap between the
-- content's border and the header's). That gap is the one number to change.
gs.HEADER_GAP = 8
gs.PLATE_TOP = gs.HEADER_HEIGHT + gs.HEADER_GAP +
               (M.modernWow.gameSettingsFrame and
                M.modernWow.gameSettingsFrame.content.rail or 0)

-- The same gap on the left and the right (user request, 2026-09-22), measured
-- from the inner face of the housing's side rail. Forever's own insets were
-- 17 and 22, so this also squares the two sides, which its art never was.
gs.PLATE_SIDE = gs.HEADER_GAP +
                (M.modernWow.gameSettingsFrame and
                 M.modernWow.gameSettingsFrame.content.side or 0)

-- The bottom is not the same gap (user request, 2026-09-22: reduce it). What
-- sits under the plate there is the page's own Okay and Cancel, so the plate
-- clears those buttons and then gs.BOTTOM_GAP, rather than Forever's authored
-- 46. The buttons keep their own inset from the window's edge.
-- Sub-row text (user request, 2026-09-22): grey at rest, white while that tab
-- is the open one -- the category rows above keep Forever's gold-idle /
-- white-selected pair, so a sub-row reads as subordinate to its parent. An
-- unavailable tab is greyer still, dimmer than the idle grey so the two states
-- are not the same colour.
gs.SUB_COLOR = {
  idle = M.color.textDim,
  active = { 1.00, 1.00, 1.00, 1.00 },
  unavailable = { 0.38, 0.38, 0.38, 1.00 },
}

gs.BOTTOM_GAP = 4
gs.PLATE_BOTTOM = M.foreverWow.panel.buttonInset.bottom +
                  M.foreverWow.panel.buttonHeight + gs.BOTTOM_GAP
gs.LIST_DROP = M.foreverWow.panel.categoryInset.top -
               M.foreverWow.panel.innerInset.top

-- Measured live, 2026-09-21 (settings.unified_window.v1). These sizes are only
-- used until the client has laid a panel out once; after that the real size is
-- read off the frame on every selection.
gs.PAGES = {
  {
    id = "video",
    label = "GAMESETTINGS_VIDEO",
    frame = "OptionsFrame",
    -- Rebuilt as Forever's settings list (modules/gamesettingslist.lua).
    layout = "list",
    menuButton = "GameMenuButtonOptions",
    -- Measured in this window, 2026-09-21 (`extent` stage): laid out here the
    -- panel is 745.91x630.49, not the 520x700 it reports after a native open.
    -- The client relays it out for the space it is given, so these are the
    -- first-open estimate only -- the real numbers are re-read after Show.
    width = 674, height = 700,
    -- Fallback only, until the panel has been laid out once: measured 0 above
    -- and below (which retired an earlier 160-unit guess for a title and tab
    -- strip that turn out to sit inside the rect) and about 102 past the right
    -- edge. gs.Overhang re-measures all four every time after that.
    padRight = 102,
    dropdowns = {
      "OptionsFrameResolutionDropDown", "OptionsFrameRefreshDropDown",
      "OptionsFrameMultiSampleDropDown",
    },
    -- The stock header plate. Its title FontString has no global name on this
    -- client, so it is left in place rather than hunted for by walking regions.
    hide = { "OptionsFrameHeader" },
  },
  {
    id = "sound",
    label = "GAMESETTINGS_SOUND",
    frame = "SoundOptionsFrame",
    layout = "list",
    menuButton = "GameMenuButtonSoundOptions",
    width = 400, height = 570,
    dropdowns = { "SoundOptionsOutputDropDown" },
  },
  {
    id = "interface",
    label = "GAMESETTINGS_INTERFACE",
    frame = "UIOptionsFrame",
    layout = "list",
    -- Its title sits on AdvancedOptions rather than on the frame itself, so
    -- the own-region text strip does not reach it.
    hide = { "UIOptionsFrameTitle" },
    menuButton = "GameMenuButtonUIOptions",
    -- UIOptionsFrame is a screen-sized container on this client (1834x768),
    -- not a compact panel, so it is resized to its own content instead of
    -- being scaled down whole.
    --
    -- Measured 2026-09-21 (settings.unified_window.v1, `parts` stage): the two
    -- tab pages BasicOptions and AdvancedOptions are both 864x648 and CENTERed
    -- on UIOptionsFrame, and every visible control hangs off THEM rather than
    -- off the container's edges -- Defaults and Cancel at BasicOptions'
    -- bottom corners, Tab1 54.84 below its BOTTOMLEFT, the title on
    -- AdvancedOptions' TOP. So the whole visible panel is 864 wide by roughly
    -- 648 + 55.
    --
    -- 864x760 is that content plus 56 units of margin above and below the
    -- centred page, which is what keeps the tabs inside the frame. The pages
    -- are a fixed size and stay centred, so nothing inside has to be moved.
    -- UnrealPfUI resizes this same frame on this same client
    -- (skins/blizzard/options-interface.lua, 1024x700), which is the working
    -- precedent for the operation rather than for these numbers.
    resize = { width = 864, height = 760 },
    width = 864, height = 760,
    dropdowns = {
      "UIOptionsFrameClickCameraDropDown", "UIOptionsFrameCameraDropDown",
      "UIOptionsFrameTargetofTargetDropDown", "UIOptionsFrameCombatTextDropDown",
    },
  },
  {
    id = "keys",
    label = "GAMESETTINGS_KEYBINDINGS",
    frame = "KeyBindingFrame",
    menuButton = "GameMenuButtonKeybindings",
    width = 640, height = 512,
    lod = "Blizzard_BindingUI",
    -- Its one toggle is a CheckButton with its own name rather than a
    -- numbered one, so the numbered sweep finds nothing here.
    checkboxes = { "KeyBindingFrameCharacterButton" },
    -- Every binding lives inside this page's scroll frame, so the control walk
    -- has to go in there. Each binding wears Forever's own binding face (user
    -- request, 2026-09-22): UIMenuButtonStretchTemplate's silver stretch
    -- button, which is what KeyBindingFrameBindingButtonTemplate inherits,
    -- instead of the WowStyle2 bed it wore before.
    scrollButtons = true,
    buttonStyle = "silver",
    -- Its category rows wear Forever's expandable-section bar (user request,
    -- 2026-09-22); see gs.PaintBindingRow.
    bindingList = true,
    -- Aligned to the page box's right edge rather than centred (user request,
    -- 2026-09-22: the page overlapped the category list on the left).
    align = "right",
    -- No buttonWidth or buttonShift any more (measured 2026-09-22,
    -- /uui gamedump keys). This client's page is already Forever-shaped: its
    -- rows are the template's own 560 wide inside a 640 panel, and it lays
    -- itself out AFTER this window styles it -- every binding read back 133
    -- wide, the width the client had just given it, not the 90 set here. So
    -- the width did nothing and the shift did harm: it was what carried the
    -- bottom buttons off the panel's left edge. Both key columns sit inside
    -- the page box at the client's own anchors.
  },
  {
    id = "unrealui",
    label = "GAMESETTINGS_UNREALUI",
    settings = true,
    settingsScope = "unrealui",
    listHeader = true,
  },
  -- UnrealQuest's pages as their own category under the Unreal UI one (user
  -- request, 2026-09-22). Listed only while UnrealQuest is installed and has
  -- registered its settings group with UnrealUI (gs.PageAvailable).
  {
    id = "unrealquest",
    label = "GAMESETTINGS_UNREALQUEST",
    settings = true,
    settingsScope = "unrealquest",
    listHeader = true,
  },
}

-- A settings category with nothing registered under it is not listed.
function gs.PageAvailable(page)
  if not page then return false end
  if page.settingsScope and page.settingsScope ~= "unrealui" then
    return type(U.HasIntegratedSettingsScope) == "function" and
           U.HasIntegratedSettingsScope(page.settingsScope) and true or false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Frame reading helpers
-- ---------------------------------------------------------------------------
function gs.Number(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if not ok then return nil end
  return tonumber(value)
end

-- Any zero-argument reader whose result is not a number: GetParent,
-- GetFrameStrata, IsShown.
function gs.Read(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if not ok then return nil end
  return value
end

-- Resolved by global name on every use rather than cached: a client-owned frame
-- may be replaced outside Lua's lifetime model (rules/unreal-ui.md, native
-- widget ownership boundaries), and one of these does not exist until its
-- load-on-demand addon has been pulled in.
function gs.Frame(page)
  if not page then return nil end

  if page.lod and not page.prepared then
    page.prepared = true
    local load = U.G("LoadAddOn")
    if type(load) == "function" then pcall(load, page.lod) end
  end

  return U.G(page.frame)
end

function gs.Page(id)
  local i
  for i = 1, table.getn(gs.PAGES) do
    if gs.PAGES[i].id == id then return gs.PAGES[i] end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Canvas host
-- ---------------------------------------------------------------------------

-- Captured once per page, before anything is changed, so Detach hands the frame
-- back as the client had it rather than as this window left it.
function gs.Capture(page, frame)
  if gs.saved[page.id] then return end

  local record = {
    parent = gs.Read(frame, "GetParent"),
    strata = gs.Read(frame, "GetFrameStrata"),
    level = gs.Number(frame, "GetFrameLevel"),
    scale = gs.Number(frame, "GetScale"),
    backdrop = gs.Read(frame, "GetBackdrop"),
    width = gs.Number(frame, "GetWidth"),
    height = gs.Number(frame, "GetHeight"),
    points = {},
  }

  local count = gs.Number(frame, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
    if ok and point then
      table.insert(record.points, { point = point, relative = relative,
                                    relativePoint = relativePoint, x = x, y = y })
    end
  end

  gs.saved[page.id] = record
end

-- Chrome the page draws for itself and should not draw inside this window.
-- Named globals only; see the note at the top of the file.
function gs.Chrome(page, show)
  if type(page.hide) ~= "table" then return end

  page.hidden = page.hidden or {}
  local i
  for i = 1, table.getn(page.hide) do
    local name = page.hide[i]
    local object = U.G(name)
    if object and type(object.Hide) == "function" then
      if show then
        -- Only put back what was on screen when this page took it over.
        if page.hidden[name] and type(object.Show) == "function" then
          pcall(object.Show, object)
        end
      else
        local was = true
        if type(object.IsShown) == "function" then
          local ok, value = pcall(object.IsShown, object)
          if ok then was = value and true or false end
        end
        page.hidden[name] = was
        pcall(object.Hide, object)
      end
    end
  end
end

-- The window grows sideways to the page and scales a page too tall for the
-- content area, because height cannot grow past the screen. Both numbers are
-- re-read on every selection: the client does not lay a panel out until it has
-- been shown once.
-- Removes the hosted panel's own background and border so it sits directly on
-- this window's recessed plate (user request, 2026-09-21), where a panel draws
-- that chrome as REGIONS. OptionsFrame does not -- its housing is a backdrop,
-- handled by gs.ClearBackdrop -- so this hides nothing there (/uui gamedump
-- measured 0); it stays for panels whose chrome is region art.
--
-- This is the one region walk in the file, and the rules in rules/unreal-ui.md
-- permit exactly this shape of it:
--
--   * It runs over ONE frame's own regions, never its children. Every control
--     on these panels -- sliders, checkboxes, dropdowns, buttons, the tab strip
--     -- is a child frame, so nothing interactive is a region of the panel and
--     nothing interactive is touched here. What is left at region level is the
--     background and border art, which is the whole point.
--   * UnrealUI adds no texture of its own to a hosted panel, so the standing
--     ban on re-stripping a frame that carries addon art does not apply: there
--     is none to lose. knowledge.json / widgets.region_walk_wrapper_lacks_setters
--     says a walked region is never == the object a getter returned, so a keep
--     table would protect nothing -- which is why this keeps nothing and
--     instead restores by remembering what was shown.
--   * Hide DOES work through the walked wrapper. That record exists because a
--     Spellbook re-strip hid art that was meant to survive; here hiding all of
--     it is the intent.
--
-- Everything hidden is remembered per panel and shown again by gs.Restore when
-- the page is detached, so a panel handed back to the client is intact.
function gs.StripChrome(page, frame)
  if page.stripChrome == false then return end

  local state = gs.stripped[page.id]
  if state then
    -- Already stripped once. The client rebuilds parts of these panels when
    -- they are shown, so anything that came back is hidden again, but the
    -- record of what was originally visible is kept from the first pass.
    local i
    for i = 1, table.getn(state) do
      pcall(state[i].Hide, state[i])
    end
    return
  end

  if type(frame.GetNumRegions) ~= "function" or
     type(frame.GetRegions) ~= "function" then
    return
  end

  local count = gs.Number(frame, "GetNumRegions") or 0
  if count < 1 then return end

  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or not regions then return end

  state = {}
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    -- Textures only on a canvas page, where a FontString region is the
    -- panel's own title and label text. A list page draws its own title in
    -- the list header, so the panel's unnamed title ("Video Options") is
    -- hidden with the rest; the controls' labels are regions of the
    -- controls, not of the panel, and are never reached from here.
    local kind = gs.Read(region, "GetObjectType")
    if (kind == "Texture" or (kind == "FontString" and page.layout == "list"))
       and gs.Read(region, "IsShown") then
      table.insert(state, region)
      pcall(region.Hide, region)
    end
  end

  gs.stripped[page.id] = state
end

-- The panel's own housing -- OptionsFrame's DialogBox background and border --
-- is a real BACKDROP, not regions. /uui gamedump (UnrealUIDiagDB.
-- gameSettingsChrome, 2026-09-21) read it back as UI-DialogBox-Background /
-- UI-DialogBox-Border edgeSize 32 AFTER SetBackdrop(nil) had run, with no
-- chrome texture among the panel's own regions (gs.StripChrome hid 0): nil is
-- not a clear on this client, and the documentation says as much.
--
-- So the backdrop stays and is made invisible instead: both colours to zero
-- alpha, the documented setters, and the same thing U.SetBackdropShown and
-- modules/questlogdesign.lua already do in production. Re-applied after Show
-- in case the client re-dresses the panel on the way up. The colour getters do
-- not exist here (knowledge.json / rendering.backdrop_color_getters_absent),
-- so gs.RestoreBackdrop cannot put back a read colour; see there.
function gs.ClearBackdrop(page, frame)
  if page.stripBackdrop == false then return end
  if type(frame.SetBackdropColor) == "function" then
    pcall(frame.SetBackdropColor, frame, 0, 0, 0, 0)
  end
  if type(frame.SetBackdropBorderColor) == "function" then
    pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
  end
end

-- Re-applies the captured backdrop, which resets its colours, then sets both to
-- white explicitly: the DialogBox art is authored to be drawn untinted, and
-- that is how the panel draws after a native open.
function gs.RestoreBackdrop(frame, record)
  if not record or not record.backdrop then return end
  if type(frame.SetBackdrop) == "function" then
    pcall(frame.SetBackdrop, frame, record.backdrop)
  end
  if type(frame.SetBackdropColor) == "function" then
    pcall(frame.SetBackdropColor, frame, 1, 1, 1, 1)
  end
  if type(frame.SetBackdropBorderColor) == "function" then
    pcall(frame.SetBackdropBorderColor, frame, 1, 1, 1, 1)
  end
end

function gs.Restore(page)
  local state = gs.stripped[page.id]
  if not state then return end
  local i
  for i = 1, table.getn(state) do
    pcall(state[i].Show, state[i])
  end
  gs.stripped[page.id] = nil
end

-- How far a panel draws outside its own rect, measured from its DIRECT
-- children rather than declared.
--
-- These panels resize themselves to whatever space they are given: the same
-- Video panel measured 745.91x630.49 in one host box and 674.07x700 in another
-- (settings.unified_window.v1, `extent` stage, two runs), with the right-edge
-- overhang moving from 92.33 to 102.14. A hardcoded pad is therefore wrong as
-- soon as the box changes, so it is read live instead.
--
-- rules/unreal-ui.md allows exactly this: the discovery was kept behind a
-- focused probe first, and what is promoted here is the smallest hierarchy that
-- probe verified -- one frame, its direct children, geometry reads only, on
-- attach rather than at startup. The declared page values remain the fallback
-- for when the walk returns nothing.
function gs.Overhang(page, frame)
  local top = gs.Number(frame, "GetTop")
  local bottom = gs.Number(frame, "GetBottom")
  local left = gs.Number(frame, "GetLeft")
  local right = gs.Number(frame, "GetRight")
  if not top or not bottom or not left or not right then return nil end

  local count = gs.Number(frame, "GetNumChildren") or 0
  if count < 1 or type(frame.GetChildren) ~= "function" then return nil end

  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok or not kids then return nil end

  local uTop, uBottom, uLeft, uRight = top, bottom, left, right
  local i
  for i = 1, table.getn(kids) do
    local kid = kids[i]
    if gs.Read(kid, "IsVisible") then
      local kt = gs.Number(kid, "GetTop")
      local kb = gs.Number(kid, "GetBottom")
      local kl = gs.Number(kid, "GetLeft")
      local kr = gs.Number(kid, "GetRight")
      if kt and kb and kl and kr then
        if kt > uTop then uTop = kt end
        if kb < uBottom then uBottom = kb end
        if kl < uLeft then uLeft = kl end
        if kr > uRight then uRight = kr end
      end
    end
  end

  -- The frame reports in its own scaled units; the overhang is in the same
  -- ones, so it is divided back out before being added to GetWidth/GetHeight.
  local scale = gs.Number(frame, "GetScale") or 1
  if scale <= 0 then scale = 1 end

  return {
    top = (uTop - top) / scale,
    bottom = (bottom - uBottom) / scale,
    left = (left - uLeft) / scale,
    right = (uRight - right) / scale,
  }
end

function gs.Fit(page, frame)
  if not gs.panel or not frame then return end

  -- Cleared first: an early return below would otherwise leave the offset from
  -- a previous page in place and anchor this one by it.
  page.fitOffsetX = 0
  page.fitOffsetY = 0

  -- A page whose client frame is a screen-sized container is resized down to
  -- its own content rather than scaled as a whole, which is what UnrealPfUI's
  -- options-interface.lua does on this client too (SetWidth/SetHeight on
  -- UIOptionsFrame). Re-applied on every selection, because the client
  -- re-applies its own size when a panel is shown.
  if page.resize then
    pcall(frame.SetWidth, frame, page.resize.width)
    pcall(frame.SetHeight, frame, page.resize.height)
  end

  local width = gs.Number(frame, "GetWidth")
  local height = gs.Number(frame, "GetHeight")
  if not width or width < 32 then width = page.width end
  if not height or height < 32 then height = page.height end

  -- The window never changes size, so the page is scaled into the box the
  -- authored plate leaves for it and centred there. Only shrinking: a small
  -- panel is left at 1:1 rather than blown up past its art.
  local boxWidth = gs.Number(gs.host, "GetWidth")
  local boxHeight = gs.Number(gs.host, "GetHeight")
  if not boxWidth or boxWidth < 1 or not boxHeight or boxHeight < 1 then return end

  -- Some of these panels draw ABOVE their own rect. The probe measured
  -- OptionsFrameHeader anchored to OptionsFrame TOP at y=+12, and this
  -- client's Video panel also carries its title and a Legacy/Modern tab strip
  -- up there, none of which GetHeight counts. padTop is that overhang, so the
  -- scale is computed against what the page actually covers and the frame is
  -- pushed down by the same amount -- otherwise the title rides up into the
  -- window header, which is what was reported in game on 2026-09-21.
  local padTop = tonumber(page.padTop) or 0
  local padBottom = tonumber(page.padBottom) or 0
  local padLeft = tonumber(page.padLeft) or 0
  local padRight = tonumber(page.padRight) or 0

  -- Live measurement wins over the declared fallback whenever the panel has
  -- been laid out, which is every call after the first Show.
  --
  -- Clamped, and that clamp is load-bearing. Reported in game 2026-09-21: the
  -- Video page went off screen entirely. A child anchored to something OUTSIDE
  -- its own frame -- a dropdown list, a tab strip parked elsewhere -- measures
  -- as an overhang of hundreds of units, which collapsed the scale and threw
  -- the anchor offset far past the window. Real chrome overhang is a fraction
  -- of the panel; anything larger than the panel itself is a child that is not
  -- part of it, so it is discarded rather than trusted.
  local measured = gs.Overhang(page, frame)
  if measured then
    local limitX = width or 0
    local limitY = height or 0
    local function Sane(value, limit)
      value = tonumber(value) or 0
      if value <= 0 then return 0 end
      if limit > 0 and value > limit then return 0 end
      return value
    end
    padTop = Sane(measured.top, limitY)
    padBottom = Sane(measured.bottom, limitY)
    padLeft = Sane(measured.left, limitX)
    padRight = Sane(measured.right, limitX)
  end

  local total = (height or 0) + padTop + padBottom
  local span = (width or 0) + padLeft + padRight

  local scale = 1
  if span > 0 and span > boxWidth then scale = boxWidth / span end
  if total > 0 and total * scale > boxHeight then scale = boxHeight / total end
  if scale <= 0 or scale > 1 then scale = 1 end
  pcall(frame.SetScale, frame, scale)

  -- Centre the PADDED box rather than the frame: half the difference between
  -- the opposite overhangs. SetPoint offsets are in the HOST's units while the
  -- overhang is in the frame's own, so it is multiplied back by the scale --
  -- without that the page sits a little further out the more it is scaled.
  page.fitOffsetY = (padTop - padBottom) / 2 * scale
  page.fitOffsetX = (padRight - padLeft) / 2 * scale
  -- What the page draws past its own right edge, in the HOST's units: a
  -- right-aligned page is pulled in by that much so the art, not the rect,
  -- meets the box's edge.
  page.fitPadRight = padRight * scale
end

-- Centres the page in the box, pushed down by whatever it overhangs upward.
--
-- A page may ask to be aligned to the box's RIGHT edge instead (Key Bindings,
-- user request 2026-09-22): its rows are wider than the box, and centred it
-- ran left over the category list. Vertically it stays centred, as the
-- "RIGHT" point already does.
function gs.Anchor(page, frame)
  if not frame or not gs.host then return end
  pcall(frame.ClearAllPoints, frame)
  if page.align == "right" then
    local inset = (tonumber(page.fitPadRight) or 0) +
                  (tonumber(page.alignInset) or 0)
    pcall(frame.SetPoint, frame, "RIGHT", gs.host, "RIGHT", -inset,
          -(tonumber(page.fitOffsetY) or 0))
    return
  end
  pcall(frame.SetPoint, frame, "CENTER", gs.host, "CENTER",
        -(tonumber(page.fitOffsetX) or 0), -(tonumber(page.fitOffsetY) or 0))
end

-- Puts a frame at `level` and every descendant frame one above its parent.
--
-- Reported in game 2026-09-21: no control on a hosted page took input --
-- dropdowns would not open, checkboxes would not toggle. /uui gamedump had
-- already shown why: after Attach raised OptionsFrame to host+1 (level 4) its
-- children still read 1, 2 and 3. SetFrameLevel on this client moves the frame
-- alone, not its subtree, so the mouse-enabled panel ended up ABOVE its own
-- controls and took every click. Forever's SetParent re-levels the subtree
-- for it; here it is done explicitly.
--
-- Frames only (GetChildren, never GetRegions), on attach, down the hierarchy
-- that dump verified; gs.RELEVEL_DEPTH is only a guard against a cycle.
gs.RELEVEL_DEPTH = 8

function gs.Relevel(frame, level, depth)
  pcall(frame.SetFrameLevel, frame, level)
  if depth >= gs.RELEVEL_DEPTH or type(frame.GetChildren) ~= "function" then
    return
  end
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok or not kids then return end
  local i
  for i = 1, table.getn(kids) do
    gs.Relevel(kids[i], level + 1, depth + 1)
  end
end

-- Escape closes the whole window (user request, 2026-09-21). The client's own
-- Escape path hides the hosted panel -- OptionsFrame and the rest are its
-- UIPanelWindows -- but this window is deliberately not in UISpecialFrames
-- (see gs.Build), so Escape used to take the page away and leave the window
-- standing empty. The panel's own OnHide is therefore watched, and a hide the
-- client makes on its own -- not a page switch, not this window detaching the
-- page -- closes the window with it. The same covers the page's own Okay and
-- Cancel, which hide the panel the same way. Post-hooked once per panel, so
-- the client's OnHide still runs first; it acts only while that page is the
-- attached one.
function gs.WatchPanel(page, frame)
  if page.watched then return end
  page.watched = U.PostHookScript(frame, "OnHide", function()
    if gs.switching or gs.detaching or gs.active ~= page then return end
    gs.Close()
  end) and true or false
end

-- A canvas page is placed by gs.Fit / gs.Anchor, and this client lays a panel
-- out on its own schedule: the size read during Attach is not always the size
-- it ends up with, and a panel the client shows again later comes up wherever
-- its own code put it. Reported in game 2026-09-22 with a screenshot: the Key
-- Bindings page drew across the category list and past the window entirely.
--
-- So the placement is re-applied one tick after the panel's own Show, which is
-- what UnrealPfUI does for these same panels on this client (WORKING_SOURCE,
-- skins/blizzard/*.lua: an OnShow re-anchor). Deferred, never read-and-written
-- in the same pass, and only while that page is the attached one.
function gs.WatchCanvas(page, frame)
  if page.canvasWatched then return end
  page.canvasWatched = U.PostHookScript(frame, "OnShow", function()
    U.DeferOnce("gamesettings:canvas:" .. page.id, function()
      if gs.active ~= page or page.layout == "list" then return end
      local live = gs.Frame(page)
      if not live then return end
      gs.Fit(page, live)
      gs.Anchor(page, live)
      -- The page's scale is what gs.LiftToWindow divides out of a moved
      -- control, so anything drawn at the window's scale is placed again from
      -- the scale this fit just set.
      if page.bindingList and type(gs.DressBindingChrome) == "function" then
        gs.DressBindingChrome(page)
      end
    end)
  end) and true or false
end

-- SettingsPanelMixin:DisplayLayout, with this client's strata and width
-- behaviour handled.
function gs.Attach(page)
  if not gs.host then return false end

  if page.settings then
    if type(U.ShowIntegratedSettings) ~= "function" then return false end
    local attached = U.ShowIntegratedSettings(gs.host, page.settingsPage,
                                              page.settingsScope)
    gs.SetIntegratedActionsShown(attached)
    if attached then
      local frame = U.G("UnrealUIGameSettingsUI")
      local strata = gs.Read(gs.host, "GetFrameStrata")
      local level = gs.Number(gs.host, "GetFrameLevel")
      if frame and strata then pcall(frame.SetFrameStrata, frame, strata) end
      if frame and level then gs.Relevel(frame, level + 1, 0) end
      gs.active = page
    end
    return attached
  end

  local frame = gs.Frame(page)
  if not frame then return false end

  gs.Capture(page, frame)
  gs.Chrome(page, false)
  gs.WatchPanel(page, frame)
  if page.layout ~= "list" then gs.WatchCanvas(page, frame) end

  pcall(frame.SetParent, frame, gs.host)

  -- A reparented client frame keeps its own strata and level, so both come from
  -- the host rather than being inherited.
  local strata = gs.Read(gs.host, "GetFrameStrata")
  if strata then pcall(frame.SetFrameStrata, frame, strata) end
  local level = gs.Number(gs.host, "GetFrameLevel")
  if level then gs.Relevel(frame, level + 1, 0) end

  -- Fit first, then anchor: a scaled frame is placed by its own scaled size,
  -- so centring before the scale is known puts it off by half the difference.
  --
  -- A LIST page is never scaled, not even for a moment. Measured 2026-09-22
  -- (/uui gamefocus, UnrealUIDiagDB.gameSettingsFocus): every texture the
  -- addon created on a Video dropdown drew 1.2963x its set size -- the bed
  -- 29.17 tall for 22.5, its caps 8.22 for 6.35 -- while the dropdown's own
  -- frame and text measured true. 1 / 1.2963 = 0.771, the scale this Fit gave
  -- OptionsFrame before the list set it back to 1; the controls reparented
  -- out of it kept the stale scale, because a reparented client widget does
  -- not follow its ancestors' changes
  -- (widgets.reparented_native_widget_ignores_ancestor_scale). That is what
  -- pushed each dropdown bed into the next row, and it made every control's
  -- drawn size disagree with its tokens.
  if page.layout == "list" then
    pcall(frame.SetScale, frame, 1)
  else
    gs.Fit(page, frame)
    gs.Anchor(page, frame)
  end
  -- The panel's own housing comes off so it sits directly on this window's
  -- recessed plate instead of drawing a second framed box inside it. The
  -- backdrop is captured in gs.Capture, made transparent here and put back by
  -- gs.Detach; see gs.ClearBackdrop for why it is not removed.
  gs.ClearBackdrop(page, frame)
  gs.StripChrome(page, frame)

  pcall(frame.Show, frame)

  -- Some panels create their searchable controls on first Show. Discard an
  -- earlier hidden-frame scan now that the complete native page exists.
  if gs.list and type(gs.list.InvalidateSearch) == "function" then
    gs.list.InvalidateSearch(page)
  end

  -- After Show: the client lays a panel out when it is first shown, and a
  -- control that does not exist yet cannot be restyled. The same applies to
  -- chrome it restores on the way up.
  gs.SkinControls(page)
  gs.ClearBackdrop(page, frame)
  gs.StripChrome(page, frame)
  -- Again after Show and the skin pass: the first Show is where the client
  -- builds and levels anything it creates lazily, and a control built there
  -- would sit at its own level under the panel. See gs.Relevel.
  if level then gs.Relevel(frame, level + 1, 0) end

  -- A list page is rebuilt as Forever's settings list instead of being shown
  -- as a canvas; there is nothing left to fit.
  if page.layout == "list" and gs.list and gs.list.Attach(page, frame) then
    gs.active = page
    return true
  end

  -- Re-fit and re-anchor now that the client has laid it out. Reported in game
  -- 2026-09-21: fitting only before Show left the Video panel overflowing the
  -- page box, its title and Legacy/Modern tabs riding up into the window
  -- header, because this client's panel is not the size it reports until it
  -- has been shown.
  gs.Fit(page, frame)
  gs.Anchor(page, frame)

  gs.active = page
  return true
end

-- SettingsPanelMixin:ClearCurrentCategoryCanvas. Forever parents the frame to
-- nil; the captured parent goes back here instead, because these are
-- client-owned panels with their own show path, and that is the restore the
-- probe verified.
function gs.Detach()
  local page = gs.active
  gs.active = nil
  if not page then return end

  if page.settings then
    gs.SetIntegratedActionsShown(false)
    if type(U.HideIntegratedSettings) == "function" then
      U.HideIntegratedSettings()
    end
    return
  end

  -- The list hands every moved control back to the panel first, while the
  -- panel is still where the list put it.
  if gs.list then gs.list.Detach(page) end

  -- Anything this window moved out of a canvas page goes back first, while the
  -- panel is still where the window put it.
  gs.RestorePlaced(page)

  local frame = U.G(page.frame)
  local record = gs.saved[page.id]
  if frame then
    gs.detaching = true
    pcall(frame.Hide, frame)
    gs.detaching = false
    pcall(frame.ClearAllPoints, frame)
    if record then
      if record.parent then pcall(frame.SetParent, frame, record.parent) end
      if record.strata then pcall(frame.SetFrameStrata, frame, record.strata) end
      if record.level then pcall(frame.SetFrameLevel, frame, record.level) end
      if record.scale then pcall(frame.SetScale, frame, record.scale) end
      if record.width then pcall(frame.SetWidth, frame, record.width) end
      if record.height then pcall(frame.SetHeight, frame, record.height) end
      gs.RestoreBackdrop(frame, record)
      local i
      for i = 1, table.getn(record.points) do
        local point = record.points[i]
        pcall(frame.SetPoint, frame, point.point, point.relative,
              point.relativePoint, point.x, point.y)
      end
    end
  end

  gs.Chrome(page, true)
  gs.Restore(page)
end

-- ---------------------------------------------------------------------------
-- Category list
--
-- Native settings rows followed by the Unreal UI section header and its pages.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Category list
--
-- Built to Forever's own list, from Blizzard_CategoryList.xml and
-- SettingsCategoryListButtonMixin:UpdateStateInternal. The details that matter,
-- because each of them was wrong in the first pass:
--
--   * The state art is drawn at its AUTHORED size and centred on the row
--     (`SetAtlas(..., UseAtlasSize)` over a Texture anchored CENTER), not
--     stretched to the row. Options_List_Active is 187x21 over a 175x20 row,
--     so it deliberately overhangs 6 units each side and 1 above and below.
--   * There is no idle art at all. Idle hides the texture; hover shows
--     Options_List_Hover; selected shows Options_List_Active and wins over
--     hover, so running the mouse down the list never moves the selection mark.
--   * The colour runs the other way round from UnrealUI's flat lists: a
--     top-level row idles in GameFontNormal (the warm gold) and the SELECTED
--     row is GameFontHighlight (white). Subcategory rows idle white too.
--   * The label is inset 36 and left-justified, which is the room the expand
--     toggle needs at LEFT 9; every row carries that indent whether or not it
--     has a toggle, so the labels line up.
--
-- The header band above the rows is SettingsCategoryListHeaderTemplate:
-- Options_CategoryHeader_1, 199x144, a 30-unit header whose gradient fades
-- down behind the rows beneath it.
-- ---------------------------------------------------------------------------

-- The shared section header used by both "Game Settings" and "Unreal UI".
-- Options_CategoryHeader_1 is taller than its frame so its gradient continues
-- behind the rows beneath it, exactly as Forever's category list draws it.
function gs.ListHeaderFrame(name, label)
  local token = M.foreverWow.options.categoryHeader
  local panel = M.foreverWow.panel
  local header = CreateFrame("Frame", name, gs.sidebar)
  header:SetWidth(gs.SIDEBAR_CONTENT_WIDTH)
  header:SetHeight(panel.headerRowHeight)
  pcall(header.EnableMouse, header, false)

  header.art = gs.Cell(header, "ARTWORK", M.foreverWow.texture.options, token[1])
  if header.art then
    header.art:SetWidth(gs.SIDEBAR_CONTENT_WIDTH)
    header.art:SetHeight(token.height)
    header.art:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
  end

  header.label = U.CreateLabel(header, {
    size = M.fontSize.normal,
    color = { 1, 1, 1, 1 },
    inherits = "GameFontHighlightMedium",
    justify = "LEFT",
  })
  if header.label then
    header.label:SetPoint("LEFT", header, "LEFT", gs.ROW_LABEL_INSET, -1)
    header.label:SetText(U.L(label))
  end
  return header
end

-- The Unreal UI and Unreal Quest pages are titled with their addon's wordmark
-- (user requests, 2026-09-23): "Unreal" white, "UI"/"Quest" accent, then the
-- version dimmed, the same split the TOC titles use. Inline escapes because
-- one region carries three colours. UnrealQuest's version is read from its
-- namespace on each open; without one the wordmark stands alone.
gs.WORDMARK = {
  unrealui = { word = "UI", version = function() return U.version end },
  unrealquest = {
    word = "Quest",
    version = function()
      local uq = U.G("UnrealQuest")
      return uq and uq.version
    end,
  },
}

function gs.Hex(color)
  local function Byte(v) return math.floor((v or 1) * 255 + 0.5) end
  return string.format("%02x%02x%02x", Byte(color[1]), Byte(color[2]),
                       Byte(color[3]))
end

function gs.PageTitleText(page)
  local mark = gs.WORDMARK[page.id]
  if not mark then return U.L(page.label) end
  local text = "|cffffffffUnreal|r |cff" .. gs.Hex(M.color.accent) ..
               mark.word .. "|r"
  local ok, version = pcall(mark.version)
  if ok and version then
    text = text .. " |cff" .. gs.Hex(M.color.textDim) .. "v" ..
           tostring(version) .. "|r"
  end
  return text
end

function gs.StyleRow(row, page, selected)
  local color = M.color.text

  if page.unavailable then
    color = M.color.textDim
  elseif selected then
    -- Forever's selected row is the WHITE one; gold is the idle state.
    color = { 1, 1, 1, 1 }
  else
    color = M.color.accent
  end

  if row.label then
    row.label:SetText(U.L(page.label))
    pcall(row.label.SetTextColor, row.label, M.Unpack(color))
  end

  row.selected = selected and true or false
  if row.active then
    if row.selected then row.active:Show() else row.active:Hide() end
  end
  -- Selected wins: hover never replaces the selection mark.
  if row.hover and row.selected then row.hover:Hide() end
end

-- One list row: the two state plates and the label, at the list's scale. A
-- category row and a tab sub-row are the same frame; only the label's indent
-- and the click differ.
function gs.RowFrame(name, indent)
  local token = M.foreverWow.options
  local panel = M.foreverWow.panel
  local state = token.rowStateSize

  local rowWidth = panel.rowWidth * gs.LIST_SCALE
  -- The state plates overhang the row by the same total the authored pair does
  -- (187 over 175), so they keep sitting proud of it at the smaller size.
  local plateWidth = rowWidth + (state.width - panel.rowWidth)

  local row = CreateFrame("Button", name, gs.sidebar)
  row:SetWidth(rowWidth)
  row:SetHeight(gs.ROW_HEIGHT)
  row.uuiLabelInset = gs.ROW_LABEL_INSET + indent

  -- Both state plates keep their authored height and are centred, the way
  -- UseAtlasSize draws them on Forever's CENTER-anchored Texture. Their width
  -- follows the narrowed row: the art is a soft glow bar that fades to nothing
  -- at both ends (profiled on the sheet, 2026-09-22), with no cap to protect,
  -- so the fade simply gets shorter.
  local function Plate(cell)
    local texture = gs.Cell(row, "BACKGROUND", M.foreverWow.texture.options, cell)
    if not texture then return nil end
    texture:SetWidth(plateWidth)
    texture:SetHeight(state.height)
    texture:SetPoint("CENTER", row, "CENTER", 6, 0)
    texture:Hide()
    return texture
  end

  row.hover = Plate(token.rowHover)
  row.active = Plate(token.rowActive)

  row.label = U.CreateLabel(row, {
    size = M.fontSize.normal,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if row.label then
    row.label:SetPoint("LEFT", row, "LEFT", row.uuiLabelInset, -1)
    pcall(row.label.SetWidth, row.label,
          rowWidth - row.uuiLabelInset - 4)
  end

  row:SetScript("OnEnter", function()
    if row.hover and not row.selected then row.hover:Show() end
  end)
  row:SetScript("OnLeave", function()
    if row.hover then row.hover:Hide() end
  end)
  return row
end

function gs.SizeSidebarItem(row, contentWidth)
  if not row then return end
  if row.uuiListHeader or row == gs.listHeader then
    pcall(row.SetWidth, row, contentWidth)
    if row.art then pcall(row.art.SetWidth, row.art, contentWidth) end
    return
  end

  local panel = M.foreverWow.panel
  local state = M.foreverWow.options.rowStateSize
  local rowWidth = panel.rowWidth * gs.LIST_SCALE +
                   (contentWidth - gs.SIDEBAR_CONTENT_WIDTH)
  local plateWidth = rowWidth + (state.width - panel.rowWidth)
  pcall(row.SetWidth, row, rowWidth)
  if row.hover then pcall(row.hover.SetWidth, row.hover, plateWidth) end
  if row.active then pcall(row.active.SetWidth, row.active, plateWidth) end
  if row.label then
    local inset = row.uuiLabelInset or gs.ROW_LABEL_INSET
    pcall(row.label.SetWidth, row.label, math.max(1, rowWidth - inset - 4))
  end
  if row.uuiToggle then
    local right = contentWidth - gs.SIDEBAR_WIDTH - 5
    pcall(row.uuiToggle.ClearAllPoints, row.uuiToggle)
    pcall(row.uuiToggle.SetPoint, row.uuiToggle, "RIGHT", gs.sidebar,
          "RIGHT", right, 0)
    pcall(row.uuiToggle.SetPoint, row.uuiToggle, "TOP", row, "TOP", 0,
          -(gs.ROW_HEIGHT - gs.TOGGLE_SIZE) / 2 + 1)
  end
end

-- Clicking a tree row's text has the same meaning as clicking its visible
-- +/- control. Pooled rows can retain a hidden toggle from an earlier entry,
-- so only dispatch through the control while it is actually being shown.
function gs.ClickRowToggle(row)
  local toggle = row and row.uuiToggle
  if not toggle or not gs.Read(toggle, "IsShown") or
     type(row.uuiToggleHandler) ~= "function" then
    return false
  end
  row.uuiToggleHandler(not toggle.uuiCollapsed)
  return true
end

function gs.CreateRow(index)
  local page = gs.PAGES[index]
  if page.listHeader then
    local header = gs.ListHeaderFrame("UnrealUIGameSettingsRow" .. index,
                                      page.label)
    header.uuiListHeader = true
    gs.rows[index] = header
    return header
  end
  local row = gs.RowFrame("UnrealUIGameSettingsRow" .. index, 0)
  row:SetScript("OnClick", function()
    if gs.ClickRowToggle(row) then return end
    gs.SelectPage(page.id, true)
  end)
  gs.rows[index] = row
  return row
end

function gs.PaintSidebarArrows(shown)
  local up = U.G("UnrealUIGameSettingsSidebarBarScrollUpButton")
  local down = U.G("UnrealUIGameSettingsSidebarBarScrollDownButton")
  if not shown then
    if up then pcall(up.Hide, up) end
    if down then pcall(down.Hide, down) end
    return
  end
  if up then
    pcall(up.Show, up)
    if (gs.sidebarOffset or 0) > 0 then
      pcall(up.Enable, up)
    else
      pcall(up.Disable, up)
    end
  end
  if down then
    pcall(down.Show, down)
    if (gs.sidebarOffset or 0) < (gs.sidebarMaximum or 0) then
      pcall(down.Enable, down)
    else
      pcall(down.Disable, down)
    end
  end
end

function gs.BuildSidebarScrollbar()
  if gs.sidebarBar or not gs.sidebar then return end
  local ok, bar = pcall(CreateFrame, "Slider", "UnrealUIGameSettingsSidebarBar",
                        gs.sidebar)
  if not ok or not bar then return end

  local list = M.foreverWow.list
  local token = M.modernWow.scrollbar
  local endInset = token and token.arrow and
                   (token.arrow.height + token.arrow.gap) or 19
  gs.sidebarBar = bar
  pcall(bar.SetOrientation, bar, "VERTICAL")
  pcall(bar.SetFrameLevel, bar,
        (gs.Number(gs.sidebar, "GetFrameLevel") or 1) + 2)
  bar:SetWidth(list.scrollbarWidth)
  bar:SetPoint("TOPRIGHT", gs.sidebar, "TOPRIGHT", -5,
               -(gs.LIST_TOP + endInset))
  bar:SetPoint("BOTTOMRIGHT", gs.sidebar, "BOTTOMRIGHT", -5, endInset)
  pcall(bar.SetMinMaxValues, bar, 0, 0)
  pcall(bar.SetValueStep, bar, 1)
  pcall(bar.SetValue, bar, 0)
  bar:SetScript("OnValueChanged", function()
    if gs.sidebarLaying then return end
    local value = math.floor((gs.Number(bar, "GetValue") or 0) + 0.5)
    if value == (gs.sidebarOffset or 0) then return end
    gs.sidebarOffset = value
    gs.RenderList()
  end)

  local function Arrow(suffix, direction)
    local arrow = CreateFrame("Button",
      "UnrealUIGameSettingsSidebarBar" .. suffix, bar)
    arrow:SetScript("OnClick", function()
      local value = gs.Number(bar, "GetValue") or 0
      pcall(bar.SetValue, bar, value + direction * 3)
    end)
  end
  Arrow("ScrollUpButton", -1)
  Arrow("ScrollDownButton", 1)
  if type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, { bodyX = 1 })
  end
  pcall(bar.Hide, bar)
  gs.PaintSidebarArrows(false)
end

-- ---------------------------------------------------------------------------
-- A page's tabs as sub-rows (user request, 2026-09-22)
--
-- The client's own tab strip is no longer drawn across the content header
-- (modules/gamesettingslist.lua hides it); each tab is a row under its
-- category instead, and a parent that has tabs carries a collapse control in
-- the Modern WoW red-button art -- U.CreateCollapseButton re-faced by
-- U.ModernWowCollapseFace, which this window may call with no Modern WoW
-- selection on, as it does for the metal housing.
--
-- The tabs are read off the client by global name rather than listed: the
-- Video page's Legacy/Modern and the Interface page's Basic/Advanced are
-- <frame>Tab1..n, and a page with none simply has no sub-rows. They are read
-- again on every render, because the labels are the client's.
--
-- Selection and availability are read APART, which the tab strip's own art
-- never did (user question, 2026-09-22: the Video page's Modern tab is greyed
-- out in the native UI). Both states disable the button on this client, so
-- IsEnabled alone cannot tell them apart -- it was the strip's only test, and
-- it would have drawn an unavailable tab as the open one.
--
--   * selection is `<frame>.selectedTab`, the index PanelTemplates_SetTab
--     writes on the page frame. That function exists here (knowledge.json /
--     frames.wholist_update_forces_who_tab wraps it), and FrameXML's
--     PanelTemplates_SelectTab is what disables the tab it selects
--     (widgets.button_lacks_state_fontobject_setters). WORKING_SOURCE for the
--     field itself -- no probe has read it on a settings page.
--   * a tab that is disabled and is NOT that index is unavailable: the client
--     offers it, but not for this build or this video mode.
--
-- With no readable selectedTab the old test stands in, so a client that does
-- not keep the field behaves exactly as before.
-- ---------------------------------------------------------------------------
function gs.PageTabs(page)
  local tabs = {}
  if page and page.settings and type(U.GetIntegratedSettingsTabs) == "function" then
    if not gs.PageAvailable(page) then return tabs end
    return U.GetIntegratedSettingsTabs(page.settingsScope)
  end
  if not page or not page.frame then return tabs end

  local frame = U.G(page.frame)
  local selected
  if frame then
    local ok, value = pcall(function() return frame.selectedTab end)
    if ok then selected = tonumber(value) end
  end

  local i
  for i = 1, 9 do
    local name = page.frame .. "Tab" .. i
    local tab = U.G(name)
    local label = tab and gs.Read(tab, "GetText")
    if tab and type(label) == "string" and label ~= "" then
      -- IsEnabled returns 1 / 0 on this client, not a boolean.
      local enabled = gs.Read(tab, "IsEnabled")
      local off = enabled == 0 or enabled == false
      local open
      if selected then open = selected == i else open = off end
      table.insert(tabs, {
        name = name,
        label = label,
        selected = open,
        unavailable = off and not open,
      })
    end
  end
  return tabs
end

-- A click on the client's tab, in every argument shape this client uses --
-- the same forward L.ForwardClick documents for a checkbox, without the
-- checked state. The tab's own handler switches the page's containers, and the
-- list relayouts through the post-hook L.Watch already puts on it.
function gs.ClickTab(name, keepSidebar)
  local sidebarOffset = keepSidebar and gs.sidebarOffset or nil
  if gs.active and gs.active.settings and
     type(U.SelectIntegratedSettingsPage) == "function" then
    local selected = U.SelectIntegratedSettingsPage(name, gs.active.settingsScope)
    if selected then
      local frame = U.G("UnrealUIGameSettingsUI")
      local level = gs.Number(gs.host, "GetFrameLevel")
      if frame and level then gs.Relevel(frame, level + 1, 0) end
      if sidebarOffset ~= nil then
        gs.sidebarOffset = sidebarOffset
        gs.revealSettingsSelection = nil
      end
      gs.RenderList()
    end
    return selected
  end

  local tab = U.G(name)
  if not tab then return false end
  local enabled = gs.Read(tab, "IsEnabled")
  if enabled == 0 or enabled == false then return true end

  local handler
  if type(tab.GetScript) == "function" then
    local ok, value = pcall(tab.GetScript, tab, "OnClick")
    if ok then handler = value end
  end
  if type(handler) ~= "function" then return false end
  local oldThis, oldArg1 = this, arg1
  this = tab
  arg1 = "LeftButton"
  pcall(handler, tab, "LeftButton")
  this = oldThis
  arg1 = oldArg1
  return true
end

function gs.SubRow(pageIndex, tabIndex)
  gs.subRows[pageIndex] = gs.subRows[pageIndex] or {}
  local rows = gs.subRows[pageIndex]
  if rows[tabIndex] then return rows[tabIndex] end
  local row = gs.RowFrame("UnrealUIGameSettingsSubRow" .. pageIndex .. "_" ..
                          tabIndex, gs.SUB_INDENT)
  row:SetScript("OnClick", function()
    if gs.ClickRowToggle(row) then return end
    local page = gs.PAGES[pageIndex]
    if not page or not row.uuiTab or row.uuiUnavailable then return end
    if not gs.active or gs.active.id ~= page.id then
      gs.SelectPage(page.id, true)
    end
    gs.ClickTab(row.uuiTab, true)
    gs.RenderList()
  end)
  row:SetScript("OnEnter", function()
    if row.hover and not row.selected and not row.uuiUnavailable then
      row.hover:Show()
    end
  end)
  rows[tabIndex] = row
  return row
end

-- One collapse control for either a native category or an UnrealUI settings
-- group. Pooled sub-rows replace the handler when their entry changes.
function gs.EnsureRowToggle(row)
  if row.uuiToggle then return row.uuiToggle end
  if type(U.CreateCollapseButton) ~= "function" then return nil end
  local toggle = U.CreateCollapseButton(row, {
    size = gs.TOGGLE_SIZE,
    collapsed = false,
    onClick = function(collapse)
      if type(row.uuiToggleHandler) == "function" then
        row.uuiToggleHandler(collapse)
      end
    end,
  })
  if not toggle then return nil end
  pcall(toggle.ClearAllPoints, toggle)
  pcall(toggle.SetPoint, toggle, "RIGHT", gs.sidebar, "RIGHT", gs.TOGGLE_RIGHT, 0)
  -- Anchored across to the list, so it follows the row's own vertical place
  -- through its parent while keeping the list's right edge.
  pcall(toggle.SetPoint, toggle, "TOP", row, "TOP", 0,
        -(gs.ROW_HEIGHT - gs.TOGGLE_SIZE) / 2 + 1)
  -- Modern WoW media over that component, which is what a theme is allowed to
  -- override on a shared widget: Blizzard's own plus / minus tree button
  -- (buttons/plus-minus-button, M.modernWow.plusMinusCell) by user request,
  -- 2026-09-22 -- a literal pair, where the red-button atlas the theme's other
  -- collapse controls use carries a minus but no plus and falls back to
  -- arrows.
  if type(U.ModernWowPlusMinusFace) == "function" then
    U.ModernWowPlusMinusFace(toggle, true)
    local face = toggle.uuiModernWowFace
    if face then
      pcall(face.ClearAllPoints, face)
      pcall(face.SetSize, face, gs.TOGGLE_FACE_SIZE, gs.TOGGLE_FACE_SIZE)
      pcall(face.SetPoint, face, "CENTER", toggle, "CENTER", 0, 0)
    end
  end
  row.uuiToggle = toggle
  return toggle
end

function gs.RowToggle(row, page)
  local toggle = gs.EnsureRowToggle(row)
  if not toggle then return nil end
  row.uuiToggleHandler = function(collapse)
    gs.expanded[page.id] = not collapse
    gs.RenderList()
  end
  return toggle
end

function gs.SettingsRowToggle(row, tab)
  local toggle = gs.EnsureRowToggle(row)
  if not toggle then return nil end
  row.uuiToggleHandler = function(collapse)
    local id = row.uuiSettingsGroup
    if id and type(U.SetIntegratedSettingsGroupExpanded) == "function" and
       U.SetIntegratedSettingsGroupExpanded(id, not collapse) then
      gs.RenderList()
    end
  end
  if type(toggle.uuiSetCollapsed) == "function" then
    pcall(toggle.uuiSetCollapsed, tab.collapsed and true or false)
  end
  return toggle
end

-- A sub-row's own state: its label is the tab's, white while that tab is the
-- one the client has selected on the open page, gold otherwise -- the same way
-- round as the category rows above it.
function gs.StyleSubRow(row, page, tab, pageSelected)
  row.uuiTab = tab.name
  row.uuiUnavailable = tab.unavailable and true or false
  row.uuiSettingsHeader = tab.settingsHeader and true or false
  row.uuiSettingsGroup = tab.settingsGroup
  row.uuiMuted = tab.muted and true or false
  local selected = pageSelected and tab.selected and true or false

  -- gs.SUB_COLOR: grey at rest, white while open, dimmer grey while the client
  -- has the tab disabled for something other than selection.
  local color = gs.SUB_COLOR.idle
  if row.uuiSettingsHeader then
    color = M.color.accent
  elseif selected then
    color = gs.SUB_COLOR.active
  elseif row.uuiMuted then
    color = gs.SUB_COLOR.unavailable
  elseif row.uuiUnavailable then
    color = gs.SUB_COLOR.unavailable
  end
  if row.label then
    row.uuiLabelInset = gs.ROW_LABEL_INSET + gs.SUB_INDENT +
                         (tonumber(tab.indent) or 0)
    row.label:SetText(tab.label)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", row.uuiLabelInset, -1)
    pcall(row.label.SetTextColor, row.label, M.Unpack(color))
  end

  row.selected = selected
  if row.active then
    if selected then row.active:Show() else row.active:Hide() end
  end
  if row.hover and (selected or row.uuiUnavailable) then row.hover:Hide() end
  if row.uuiSettingsGroup then gs.SettingsRowToggle(row, tab) end
end

-- The one header band over the list, as Forever puts a header over each group
-- of categories. These four are all client settings, so there is one.
function gs.BuildListHeader()
  if gs.listHeader then return gs.listHeader end
  local header = gs.ListHeaderFrame(nil, "GAMESETTINGS_TITLE")

  gs.listHeader = header
  return header
end

-- Laid out from a running offset rather than from the row index: a category
-- with tabs is followed by its own sub-rows while it is expanded (user
-- request, 2026-09-22).
function gs.RenderList()
  local step = gs.ROW_HEIGHT + gs.ROW_GAP
  local items = {}
  if gs.listHeader then
    table.insert(items, {
      row = gs.listHeader,
      height = M.foreverWow.panel.headerRowHeight,
      toggle = false,
    })
  end
  local i, j
  for i = 1, table.getn(gs.PAGES) do
    local page = gs.PAGES[i]
    local row = gs.rows[i] or gs.CreateRow(i)
    local matches = gs.PageAvailable(page) and
                    (not gs.list or type(gs.list.PageMatches) ~= "function" or
                     gs.list.PageMatches(page))

    if matches then
      local selected = gs.active ~= nil and gs.active.id == page.id
      if page.listHeader then
        if row.label then row.label:SetText(U.L(page.label)) end
      else
        gs.StyleRow(row, page, selected)
      end
      local item = {
        row = row,
        toggle = false,
        height = page.listHeader and M.foreverWow.panel.headerRowHeight or step,
      }
      table.insert(items, item)

      local tabs = gs.PageTabs(page)
      local count = table.getn(tabs)
      local open = count > 0 and
                   (page.listHeader or gs.expanded[page.id] ~= false)

      -- The toggle exists only on a row that has tabs, and is created the first
      -- time that row has them: the client's panels are not all loaded when the
      -- window is built.
      if count > 0 and not page.listHeader then
        item.toggle = true
        local toggle = gs.RowToggle(row, page)
        if toggle then
          -- The setter owns uuiCollapsed and the drawn glyph; the component
          -- starts hidden, so every render shows it.
          if type(toggle.uuiSetCollapsed) == "function" then
            pcall(toggle.uuiSetCollapsed, not open)
          end
        end
      elseif row.uuiToggle then
        pcall(row.uuiToggle.Hide, row.uuiToggle)
      end

      local rows = gs.subRows[i] or {}
      for j = 1, math.max(count, table.getn(rows)) do
        if j <= count and open then
          local sub = gs.SubRow(i, j)
          gs.StyleSubRow(sub, page, tabs[j], selected)
          table.insert(items, {
            row = sub,
            selected = tabs[j].selected,
            toggle = tabs[j].settingsGroup and true or false,
          })
        elseif rows[j] then
          pcall(rows[j].Hide, rows[j])
        end
      end
    else
      pcall(row.Hide, row)
      if row.uuiToggle then pcall(row.uuiToggle.Hide, row.uuiToggle) end
      local rows = gs.subRows[i] or {}
      for j = 1, table.getn(rows) do
        pcall(rows[j].Hide, rows[j])
      end
    end
  end

  -- UnrealUI contributes more pages than fit in the compact Forever sidebar.
  -- The wheel moves a row window over the same pooled buttons; nothing is
  -- reparented and rows outside the viewport are explicitly hidden because
  -- parent clipping is not reliable on this client.
  local height = gs.Number(gs.sidebar, "GetHeight") or 0
  local available = math.max(1, height - gs.LIST_TOP - 2)
  local count = table.getn(items)

  local function ItemHeight(index)
    return (items[index] and items[index].height) or step
  end

  local function VisibleCount(offset)
    local used, visible = 0, 0
    local index
    for index = offset + 1, count do
      local itemHeight = ItemHeight(index)
      if visible > 0 and used + itemHeight > available then break end
      used = used + itemHeight
      visible = visible + 1
    end
    return visible
  end

  -- The furthest useful offset is the first item in the shortest tail that
  -- fills the viewport. This keeps the final page at the bottom without a
  -- blank gap even though section headers are taller than ordinary rows.
  local used, first = 0, count + 1
  for i = count, 1, -1 do
    local itemHeight = ItemHeight(i)
    if first <= count and used + itemHeight > available then break end
    used = used + itemHeight
    first = i
  end
  local maximum = math.max(0, first - 1)
  local contentWidth = gs.SIDEBAR_WIDTH
  if maximum > 0 then
    contentWidth = gs.SIDEBAR_WIDTH - gs.SIDEBAR_SCROLLBAR_SEAT
  end
  gs.sidebarContentWidth = contentWidth
  for i = 1, count do gs.SizeSidebarItem(items[i].row, contentWidth) end

  gs.sidebarOffset = math.max(0, math.min(maximum, gs.sidebarOffset or 0))
  if gs.revealSettingsSelection then
    for i = 1, table.getn(items) do
      if items[i].selected then
        if i <= gs.sidebarOffset then
          gs.sidebarOffset = i - 1
        else
          while i > gs.sidebarOffset + VisibleCount(gs.sidebarOffset) and
                gs.sidebarOffset < maximum do
            gs.sidebarOffset = gs.sidebarOffset + 1
          end
        end
        break
      end
    end
    gs.sidebarOffset = math.max(0, math.min(maximum, gs.sidebarOffset))
    gs.revealSettingsSelection = nil
  end
  local capacity = VisibleCount(gs.sidebarOffset)
  gs.sidebarMaximum = maximum

  if gs.sidebarBar then
    gs.sidebarLaying = true
    pcall(gs.sidebarBar.SetMinMaxValues, gs.sidebarBar, 0, maximum)
    pcall(gs.sidebarBar.SetValue, gs.sidebarBar, gs.sidebarOffset)
    gs.sidebarLaying = nil
    if maximum > 0 then
      pcall(gs.sidebarBar.Show, gs.sidebarBar)
      if type(U.SetModernWowScrollbarProportion) == "function" then
        U.SetModernWowScrollbarProportion(gs.sidebarBar, capacity,
                                          table.getn(items))
      end
      gs.PaintSidebarArrows(true)
    else
      pcall(gs.sidebarBar.Hide, gs.sidebarBar)
      gs.PaintSidebarArrows(false)
    end
  end

  local y = gs.LIST_TOP
  for i = 1, table.getn(items) do
    local item = items[i]
    local row = item.row
    local visible = i > gs.sidebarOffset and
                    i <= gs.sidebarOffset + capacity
    if visible then
      pcall(row.ClearAllPoints, row)
      pcall(row.SetPoint, row, "TOPLEFT", gs.sidebar, "TOPLEFT", 0,
            -y)
      pcall(row.Show, row)
      if row.label then pcall(row.label.Show, row.label) end
      if row.uuiToggle then
        if item.toggle then
          pcall(row.uuiToggle.Show, row.uuiToggle)
        else
          pcall(row.uuiToggle.Hide, row.uuiToggle)
        end
      end
      y = y + ItemHeight(i)
    else
      pcall(row.Hide, row)
      if row.uuiToggle then pcall(row.uuiToggle.Hide, row.uuiToggle) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------
function gs.SelectPage(id, keepSidebar)
  local page = gs.Page(id)
  if page and not gs.PageAvailable(page) then page = gs.Page("unrealui") end
  if not page or not gs.panel then return false end
  local sidebarOffset = keepSidebar and gs.sidebarOffset or nil
  if page.settings then gs.expanded[page.id] = true end

  -- Hiding the outgoing client panel hands control back to the client's own
  -- "back out of options" path, which shows the game menu and closes windows.
  -- The whole switch therefore runs behind one flag: this window's OnHide does
  -- not tear the page down while it is set, and the window is put back up
  -- afterwards if the client took it down in the middle.
  gs.switching = true

  -- Exactly one client panel is ever attached, the same way
  -- SettingsPanelMixin:SelectCategory clears the outgoing canvas first.
  if gs.active ~= page then gs.Detach() end

  local attached = gs.Attach(page)
  page.unavailable = not attached

  gs.switching = false

  local shown = gs.Read(gs.panel, "IsShown")
  if not shown then pcall(gs.panel.Show, gs.panel) end

  -- The client's game menu comes back with it, over this window. Close it
  -- again: the row that was clicked is in this window, not in that menu.
  local menu = U.G("GameMenuFrame")
  if menu and gs.Read(menu, "IsShown") then gs.HideMenu(menu) end

  -- A panel this client does not have says so rather than leaving a blank page.
  if gs.message then
    if attached then
      gs.message:Hide()
    else
      gs.message:SetText(U.L("GAMESETTINGS_UNAVAILABLE"))
      gs.message:Show()
    end
  end

  if gs.pageTitle then gs.pageTitle:SetText(gs.PageTitleText(page)) end

  if sidebarOffset ~= nil then
    gs.sidebarOffset = sidebarOffset
    gs.revealSettingsSelection = nil
  end
  gs.RenderList()
  return attached
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Controls inside a hosted page
--
-- The client's own checkboxes, sliders, dropdowns and buttons are restyled with
-- the Forever build's own control art (M.foreverWow.control, user request
-- 2026-09-21), so a hosted page reads as part of this window rather than as a
-- 2006 panel sitting inside it.
--
-- Every control is reached by its GLOBAL NAME and restyled through its own
-- accessors -- SetNormalTexture, SetCheckedTexture, SetThumbTexture. Nothing
-- here walks regions: knowledge.json / widgets.region_walk_wrapper_lacks_setters
-- means a walked region is never the object the setter returned on this client,
-- so a walk could neither find these reliably nor leave the rest alone. That
-- rule also says to clear a button's state art through its own getters, which
-- is what this does.
--
-- Re-applied on every attach rather than once: the client rebuilds parts of
-- these panels when they are shown (frames.stock_singletons_structure_nonvanilla),
-- and a texture it replaced would otherwise stay stock for the rest of the
-- session. Every skin below is written to be repeated.
--
-- Which controls a page has is DISCOVERED, not listed. /uui gamedump
-- (UnrealUIDiagDB.gameSettingsChrome, 2026-09-21) showed why a list cannot
-- keep up: the Video panel numbers its checkboxes 3, 5, 9, 10, 12, 17, 19-21,
-- 23, 24 with no 1, so a loop stopping at the first gap skinned none of them,
-- and its Legacy and Modern tab pages carry dropdowns (GPU, Graphics API,
-- Modern Resolution/Refresh/Anti-Aliasing) no upstream name list has.
--
-- gs.Collect walks FRAMES -- GetChildren, never GetRegions -- down the
-- hierarchy that dump verified (panel > tab page > section > control), on
-- attach only, and records each control's GLOBAL NAME. Skinning then resolves
-- every control by that name, so nothing is done to a walked wrapper and the
-- region-identity problem (widgets.region_walk_wrapper_lacks_setters) does not
-- arise. It does not descend into a control, a ScrollFrame, or anything
-- unnamed, and a slider named like a scrollbar is left alone.
-- ---------------------------------------------------------------------------

gs.COLLECT_DEPTH = 4

function gs.IsDropdown(name)
  return U.G(name .. "Button") ~= nil and U.G(name .. "Middle") ~= nil and
         U.G(name .. "Text") ~= nil
end

function gs.Collect(frame, depth, found)
  if depth > gs.COLLECT_DEPTH or type(frame.GetChildren) ~= "function" then
    return found
  end
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok or not kids then return found end

  local i
  for i = 1, table.getn(kids) do
    local kid = kids[i]
    local name = gs.Read(kid, "GetName")
    local kind = gs.Read(kid, "GetObjectType")
    if type(name) == "string" and name ~= "" then
      if kind == "CheckButton" then
        table.insert(found.checkboxes, name)
      elseif kind == "Slider" then
        if not string.find(name, "ScrollBar") then
          table.insert(found.sliders, name)
        end
      elseif kind == "Button" then
        -- Tabs keep the client's own tab art: this atlas has no tab cell, and
        -- a scrollbar's steppers are chrome, not controls.
        if not string.find(name, "Tab%d+$") and
           not string.find(name, "ScrollUpButton$") and
           not string.find(name, "ScrollDownButton$") then
          table.insert(found.buttons, name)
        end
      elseif kind == "ScrollFrame" then
        -- A scrolled list's rows and bar are not form controls -- except on a
        -- page that says otherwise (found.scroll): Key Bindings keeps every
        -- binding inside its scroll frame, and those ARE its controls.
        if found.scroll then gs.Collect(kid, depth + 1, found) end
      elseif gs.IsDropdown(name) then
        table.insert(found.dropdowns, name)
      else
        gs.Collect(kid, depth + 1, found)
      end
    elseif kind == "Frame" then
      gs.Collect(kid, depth + 1, found)
    end
  end
  return found
end

-- The Forever sheets are addressed in texels in M.foreverWow.control; this
-- turns one { x0, x1, y0, y1 } cell into texture coordinates on a sheet of the
-- given size (height defaults to width for a square sheet).
function gs.SetCell(texture, cell, sheetWidth, sheetHeight, flip)
  if not texture or not cell or not sheetWidth then return end
  sheetHeight = sheetHeight or sheetWidth
  local l, r = cell[1] / sheetWidth, cell[2] / sheetWidth
  if flip then l, r = r, l end
  pcall(texture.SetTexCoord, texture, l, r, cell[3] / sheetHeight, cell[4] / sheetHeight)
end

-- Retextures one of a button's own state slots through its own getter, the
-- way rules/unreal-ui.md says button state art is changed. The state setters
-- are not used with a path (widgets.setthumbtexture_path_shares_one_thumb).
function gs.SetState(button, getter, path, cell, sheetWidth, sheetHeight)
  local texture = gs.Read(button, getter)
  if not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  gs.SetCell(texture, cell, sheetWidth, sheetHeight)
  pcall(texture.SetBlendMode, texture, "BLEND")
  pcall(texture.SetVertexColor, texture, 1, 1, 1, 1)
  return texture
end

-- The size a checkbox had before this skin first touched it. The drawn size is
-- Forever's own; the client's size still tells a sub-option from a main one
-- (the list indents a checkbox the client drew smaller).
gs.checkboxSize = {}

-- SettingsCheckboxTemplate: checkbox-minimal as the bed and checkmark-minimal
-- / -disabled as the tick, all from checkmark-minimal.tga. Blizzard draws no
-- hover art on the box itself, so the highlight slot is emptied rather than
-- restyled; a disabled box is its bed greyed.
--
-- The TICK is an owned texture, not the client's checked slot. Reported in
-- game 2026-09-21 with a screenshot: after its checked slot had been
-- retextured, the client still drew its own stock gold check at full size
-- over the box. That is the behaviour U.StyleStockCheckbox (core/stockui.lua)
-- already records for this client -- the client puts its checked art back and
-- a plain Hide can leave it visible -- so the same pattern is used: the two
-- checked slots are cleared with U.HideRegion on every refresh, and the owned
-- tick follows GetChecked through OnClick, OnShow and SetChecked.
function gs.SkinCheckbox(name)
  local button = U.G(name)
  if not button then return end
  local token = M.foreverWow.control.checkbox

  if not gs.checkboxSize[name] then
    local size = gs.Number(button, "GetWidth")
    if not size or size < 8 then return end
    gs.checkboxSize[name] = size
  end
  pcall(button.SetWidth, button, token.width)
  pcall(button.SetHeight, button, token.height)

  gs.SetState(button, "GetNormalTexture", token.texture, token.cell, token.sheet)
  gs.SetState(button, "GetPushedTexture", token.texture, token.cell, token.sheet)
  local disabled = gs.SetState(button, "GetDisabledTexture", token.texture,
                               token.cell, token.sheet)
  if disabled then pcall(disabled.SetVertexColor, disabled, 0.5, 0.5, 0.5, 1) end
  local highlight = gs.Read(button, "GetHighlightTexture")
  if highlight then U.HideRegion(highlight) end

  -- Each bed face is also given the size itself, centred on the button,
  -- instead of trusting it to fill the button: after the box was set smaller
  -- it still drew at the size before (reported in game 2026-09-21).
  local getters = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }
  local i
  for i = 1, table.getn(getters) do
    local face = gs.Read(button, getters[i])
    if face then
      pcall(face.ClearAllPoints, face)
      pcall(face.SetPoint, face, "CENTER", button, "CENTER", 0, 0)
      pcall(face.SetWidth, face, token.width)
      pcall(face.SetHeight, face, token.height)
    end
  end

  if not button.uuiOwnTick then
    local ok, tick = pcall(button.CreateTexture, button, nil, "OVERLAY")
    if ok and tick then
      pcall(tick.SetTexture, tick, token.checkTexture)
      pcall(tick.SetPoint, tick, "CENTER", button, "CENTER", 0, 0)
      pcall(tick.SetWidth, tick, token.checkWidth)
      pcall(tick.SetHeight, tick, token.checkHeight)
      button.uuiOwnTick = tick

      U.PostHookScript(button, "OnClick", function() gs.PaintCheck(button) end)
      U.PostHookScript(button, "OnShow", function() gs.PaintCheck(button) end)
      -- Settings code sets the state with SetChecked rather than a click.
      if type(button.SetChecked) == "function" then
        local setChecked = button.SetChecked
        button.SetChecked = function(self, value)
          local result = setChecked(self, value)
          gs.PaintCheck(self)
          return result
        end
      end
    end
  end
  -- On a list page the client's checkbox is parked undrawn and the list
  -- draws its own in its place (modules/gamesettingslist.lua L.CheckButton),
  -- pointing these at that face; a canvas page keeps the button's own.
  button.uuiForeverTick = button.uuiOwnTick
  button.uuiForeverBox = nil
  if button.uuiOwnTick then pcall(button.uuiOwnTick.Hide, button.uuiOwnTick) end
  gs.PaintCheck(button)
end

function gs.PaintCheck(button)
  local tick = button and button.uuiForeverTick
  if not tick then return end
  local token = M.foreverWow.control.checkbox

  -- The client's own checked art is suppressed every time, because it puts
  -- it back. Reported in game 2026-09-21: hiding the object GetCheckedTexture
  -- returns (U.HideRegion) left the stock check drawn beside the owned tick,
  -- so the slot is also emptied through the button's own setter -- the route
  -- rules/unreal-ui.md gives for a button's state art, and the one
  -- core/dropdown.lua's RemoveButtonArt uses ("" first, nil if refused).
  local setters = { { "GetCheckedTexture", "SetCheckedTexture" },
                    { "GetDisabledCheckedTexture", "SetDisabledCheckedTexture" } }
  local i
  for i = 1, table.getn(setters) do
    local slot = gs.Read(button, setters[i][1])
    if slot then U.HideRegion(slot) end
    local setter = button[setters[i][2]]
    if type(setter) == "function" then
      if not pcall(setter, button, "") then pcall(setter, button, nil) end
    end
  end

  -- IsEnabled returns 1 / 0 on this client, not a boolean.
  local enabled = gs.Read(button, "IsEnabled")
  local disabled = enabled == 0 or enabled == false
  local box = button.uuiForeverBox
  if box then
    local shade = disabled and 0.5 or 1
    pcall(box.SetVertexColor, box, shade, shade, shade, 1)
  end

  local checked = gs.Read(button, "GetChecked")
  if not checked or checked == 0 then
    pcall(tick.Hide, tick)
    return
  end
  local cell = disabled and token.checkDisabled or token.check
  gs.SetCell(tick, cell, token.checkSheet)
  pcall(tick.Show, tick)
end

-- MinimalSliderTemplate's face is shared by client-owned sliders and the
-- UnrealUI widgets hosted in this window. Both paths call these builders, so
-- the bar crop, cap geometry, and thumb can never diverge.
function gs.BuildSliderBar(slider)
  if not slider then return nil end
  local token = M.foreverWow.control.slider
  local w, h = token.sheetWidth, token.sheetHeight
  if slider.uuiForeverBar then return slider.uuiForeverBar end
  local bar = {}
  local function Piece(cell)
    local ok, texture = pcall(slider.CreateTexture, slider, nil, "BACKGROUND")
    if not ok or not texture then return nil end
    pcall(texture.SetTexture, texture, token.texture)
    gs.SetCell(texture, cell, w, h)
    pcall(texture.SetHeight, texture, token.barHeight)
    return texture
  end
  bar.left, bar.middle, bar.right = Piece(token.left), Piece(token.middle), Piece(token.right)
  if not bar.left or not bar.middle or not bar.right then return nil end
  pcall(function()
    bar.left:SetWidth(token.capWidth)
    bar.left:SetPoint("LEFT", slider, "LEFT", 0, 0)
    bar.right:SetWidth(token.capWidth)
    bar.right:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    bar.middle:SetPoint("LEFT", bar.left, "RIGHT", 0, 0)
    bar.middle:SetPoint("RIGHT", bar.right, "LEFT", 0, 0)
  end)
  slider.uuiForeverBar = bar
  return bar
end

function gs.StyleSliderThumb(thumb)
  if not thumb then return nil end
  local token = M.foreverWow.control.slider
  pcall(thumb.SetTexture, thumb, token.texture)
  gs.SetCell(thumb, token.thumb, token.sheetWidth, token.sheetHeight)
  pcall(thumb.SetWidth, thumb, token.thumbWidth)
  pcall(thumb.SetHeight, thumb, token.thumbHeight)
  return thumb
end

-- MinimalSliderTemplate: Minimal_SliderBar_Left / _Middle / _Right across the
-- slider at their authored caps, and Minimal_SliderBar_Button as the thumb.
function gs.SkinSlider(name)
  local slider = U.G(name)
  if not slider then return end

  -- The groove is the slider's own backdrop (UI-SliderBar-Background/Border in
  -- the dump). Made transparent rather than removed, exactly as the panel's
  -- housing is (gs.ClearBackdrop): SetBackdrop(nil) is not a clear here.
  pcall(slider.SetBackdropColor, slider, 0, 0, 0, 0)
  pcall(slider.SetBackdropBorderColor, slider, 0, 0, 0, 0)
  gs.BuildSliderBar(slider)

  -- The slider's OWN thumb is retextured; SetThumbTexture is not used
  -- (widgets.setthumbtexture_path_shares_one_thumb).
  local thumb = gs.Read(slider, "GetThumbTexture")
  gs.StyleSliderThumb(thumb)
end

-- The shared dropdown component does the work -- full-width hit area, height
-- lock, value layout, list placement -- and draws the WowStyle2 bed handed to
-- it.
function gs.SkinDropdown(name)
  local frame = U.G(name)
  if not frame or not U.Dropdown or type(U.Dropdown.StyleStock) ~= "function" then
    return
  end
  local token = M.foreverWow.control.dropdown
  U.Dropdown.StyleStock(frame, nil, {
    bed = {
      texture = token.texture,
      sheet = token.sheet,
      normal = token.normal,
      hover = token.hover,
      pressed = token.pressed,
      disabled = token.disabled,
      capLeft = token.capLeft,
      capRight = token.capRight,
      height = token.height,
      controlHeight = token.controlHeight,
      overhang = token.overhang,
      arrow = token.arrow,
      textInset = token.textInset,
      textAlign = token.textAlign,
      textColor = token.textColor,
      textSize = M.fontSize.normal,
      menu = token.menu,
    },
  })
end

-- A page's own action buttons (Okay, Cancel, Defaults, the Key Bindings
-- rows' buttons) take the same rounded bed as this window's header X.
-- Their stock face is cleared through the button's own getters and setters
-- first; the click owner, hit area and label are the client's.
-- Forever's own actions on a page, which keep the red face wherever a page
-- asks for another one.
-- A page's own actions, which stay the window's red face and are never
-- resized or shifted with the page's controls. The second row is Key
-- Bindings', whose four bottom buttons end in "Button" and so matched none of
-- the first row's patterns. Measured 2026-09-22 (/uui gamedump keys): with
-- them treated as controls, each was shifted by page.buttonShift, and because
-- the client chains their anchors -- Okay off Cancel, Unbind off Okay -- the
-- shifts compounded to 70 / 140 / 210, carrying Unbind and Default 119.67
-- units LEFT of the panel's own edge. gs.Overhang read that as a left
-- overhang, gs.Fit scaled and placed the whole page around it, and the page
-- drew across the category list.
gs.CHROME_BUTTON = {
  "Okay$", "Cancel$", "Defaults$", "Tab%d+$",
  "OkayButton$", "CancelButton$", "DefaultButton$", "DefaultsButton$",
  "UnbindButton$",
}

function gs.IsChromeButton(name)
  if type(name) ~= "string" then return false end
  local i
  for i = 1, table.getn(gs.CHROME_BUTTON) do
    if string.find(name, gs.CHROME_BUTTON[i]) then return true end
  end
  return false
end

function gs.SkinButton(name)
  local button = U.G(name)
  if not button then return end
  local height = gs.Number(button, "GetHeight")
  if not height or height < 8 or height > 40 then return end

  local getters = { "GetNormalTexture", "GetPushedTexture",
                    "GetHighlightTexture", "GetDisabledTexture" }
  local setters = { "SetNormalTexture", "SetPushedTexture",
                    "SetHighlightTexture", "SetDisabledTexture" }
  local i
  for i = 1, table.getn(getters) do
    local texture = gs.Read(button, getters[i])
    if texture then U.HideRegion(texture) end
    if type(button[setters[i]]) == "function" then
      if not pcall(button[setters[i]], button, "") then
        pcall(button[setters[i]], button, nil)
      end
    end
  end

  if not button.label then button.label = gs.Read(button, "GetFontString") end
  gs.DressButton(button, height)
end

-- Moves one client control left, for a page whose own layout is wider than
-- this window's page box (Key Bindings, user request 2026-09-22: the rows ran
-- outside the panel). Two rules keep it safe:
--
--   * The point is captured ONCE and re-applied on the next tick, never read
--     and written in the same pass -- the sequence rules/unreal-ui.md calls
--     invalid, and the one mw.LiftActionButton defers for the same reason.
--   * A control anchored to ANOTHER control this page shifted is left alone:
--     the client anchors the second key of a binding to the first, so moving
--     both would move it twice.
function gs.ShiftControl(control, shift)
  shift = tonumber(shift) or 0
  if not control or shift == 0 or control.uuiForeverShift then return false end
  local point, relative, relativePoint, x, y = U.GetFramePoint(control, 1)
  if not point or not x then return false end

  -- A control anchored to one this page has ALREADY shifted moves with it, so
  -- shifting it again compounds. Measured 2026-09-22 (/uui gamedump keys):
  -- the client chains Key Bindings' bottom buttons, and one 70-unit shift per
  -- button became 210 on the last of them. The name test stays for the
  -- binding pair, whose second key is anchored to the first and may be read
  -- before it has been marked.
  local anchorName = gs.Read(relative, "GetName")
  if relative and relative.uuiForeverShift then
    control.uuiForeverShift = true
    return false
  end
  if type(anchorName) == "string" and string.find(anchorName, "Key%d+Button$") then
    control.uuiForeverShift = true
    return false
  end

  control.uuiForeverShift = true
  local name = gs.Read(control, "GetName") or tostring(control)
  U.DeferOnce("gamesettings:shift:" .. name, function()
    pcall(control.ClearAllPoints, control)
    pcall(control.SetPoint, control, point, relative, relativePoint, x - shift, y)
  end)
  return true
end

-- The Key Bindings rows wear the WowStyle2 bed rather than the red action face
-- (user request, 2026-09-22): a binding is a value the player sets, closer to
-- a dropdown than to Okay. It is the SAME bed the settings dropdowns draw --
-- M.foreverWow.control.dropdown, through the shared component's own builder
-- and painter -- with no arrow and no text inset, so there is no second bed
-- drawer in the addon.
--
-- The bed is drawn in the dropdown's own proportion: its art is `height` tall
-- around a `controlHeight` control, so a button of another height keeps that
-- ratio rather than squashing the rim.
function gs.DressBedButton(target)
  local button = type(target) == "string" and U.G(target) or target
  if not button or button.uuiForeverBed then return false end
  if type(U.Dropdown) ~= "table" or type(U.Dropdown.BuildBed) ~= "function" then
    return false
  end
  local token = M.foreverWow.control.dropdown
  local height = gs.Number(button, "GetHeight")
  if not height or height < 8 or height > 40 then return false end

  local ratio = height / (token.controlHeight or height)
  local bed = {
    texture = token.texture,
    sheet = token.sheet,
    normal = token.normal,
    hover = token.hover,
    pressed = token.pressed,
    disabled = token.disabled,
    capLeft = token.capLeft,
    capRight = token.capRight,
    height = (token.height or height) * ratio,
    controlHeight = height,
    overhang = (token.overhang or 0) * ratio,
  }
  if not U.Dropdown.BuildBed(button, bed) then return false end
  button.uuiForeverBed = true

  local function Paint(state)
    -- U.CreateButton's OnEnter recolours its old flat outline, and the shared
    -- dropdown visibility helper can show that outline again. Keep the legacy
    -- backdrop suppressed on every state repaint so only the Forever bed is
    -- visible.
    U.SetBackdropShown(button, false)
    local enabled = gs.Read(button, "IsEnabled")
    if enabled == 0 or enabled == false then state = "disabled" end
    U.Dropdown.PaintBed(button, state)
  end
  U.PostHookScript(button, "OnEnter", function() Paint("hover") end)
  U.PostHookScript(button, "OnLeave", function() Paint(nil) end)
  U.PostHookScript(button, "OnMouseDown", function() Paint("pressed") end)
  U.PostHookScript(button, "OnMouseUp", function() Paint("hover") end)
  U.PostHookScript(button, "OnShow", function() Paint(nil) end)

  local label = gs.Read(button, "GetFontString")
  if label then
    U.SetStockFont(label, M.fontSize.normal, M.foreverWow.list.valueColor)
    U.CenterButtonLabel(label, button)
  end
  Paint(nil)
  return true
end

-- ---------------------------------------------------------------------------
-- UnrealUI-owned controls inside the unified settings canvas
-- ---------------------------------------------------------------------------

function gs.BuildOwnedCheckboxFace(frame)
  if not frame then return nil end
  if frame.uuiForeverCheckbox then return frame.uuiForeverCheckbox end
  local token = M.foreverWow.control.checkbox
  local face = {}

  -- gs.Cell consumes normalized coordinates, while the control tokens are
  -- atlas texels. Build the regions first and normalize through gs.SetCell,
  -- exactly as the client-owned Game Settings controls do above.
  face.box = gs.Cell(frame, "ARTWORK", token.texture)
  face.tick = gs.Cell(frame, "OVERLAY", token.checkTexture)
  if not face.box or not face.tick then return nil end
  gs.SetCell(face.box, token.cell, token.sheet)
  gs.SetCell(face.tick, token.check, token.checkSheet)
  pcall(function()
    face.box:SetWidth(token.width)
    face.box:SetHeight(token.height)
    face.box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    face.tick:SetWidth(token.checkWidth)
    face.tick:SetHeight(token.checkHeight)
    face.tick:SetPoint("CENTER", frame, "CENTER", 0, 0)
    face.tick:Hide()
  end)
  frame.uuiForeverCheckbox = face
  return face
end

function gs.PaintOwnedCheckbox(frame, checked, enabled)
  local face = gs.BuildOwnedCheckboxFace(frame)
  if not face then return end
  U.SetBackdropShown(frame, false)
  if frame.uuiCheckboxMask then pcall(frame.uuiCheckboxMask.Hide, frame.uuiCheckboxMask) end
  if frame.uuiCheckboxMark then pcall(frame.uuiCheckboxMark.Hide, frame.uuiCheckboxMark) end

  local shade = enabled == false and 0.5 or 1
  pcall(face.box.SetVertexColor, face.box, shade, shade, shade, 1)
  if checked then
    local token = M.foreverWow.control.checkbox
    gs.SetCell(face.tick, enabled == false and token.checkDisabled or token.check,
               token.checkSheet)
    pcall(face.tick.Show, face.tick)
  else
    pcall(face.tick.Hide, face.tick)
  end
end

-- The exact two stepper families used by Forever's settings controls. These
-- builders are shared by the rebuilt client list (gamesettingslist.lua) and
-- the UnrealUI-owned pages below; callers supply only the value-changing
-- callback and placement. The art/state logic consequently cannot drift.
function gs.BuildSliderSteppers(parent)
  if not parent then return nil end
  if parent.uuiForeverSliderSteppers then return parent.uuiForeverSliderSteppers end
  local token = M.foreverWow.control.slider
  local steppers = {}

  local function Make(spec, direction)
    local ok, button = pcall(CreateFrame, "Button", nil, parent)
    if not ok or not button then return nil end
    button:SetWidth(spec.width)
    button:SetHeight(spec.height)
    pcall(button.EnableMouse, button, true)
    local level = gs.Number(parent, "GetFrameLevel")
    if level then pcall(button.SetFrameLevel, button, level + 1) end
    local made, face = pcall(button.CreateTexture, button, nil, "ARTWORK")
    if made and face then
      pcall(face.SetTexture, face, token.texture)
      pcall(face.SetAllPoints, face, button)
      gs.SetCell(face, spec.cell, token.sheetWidth, token.sheetHeight)
      button.face = face
    end
    button.enabled = true
    button.direction = direction
    button:SetScript("OnClick", function()
      if button.enabled and type(steppers.onStep) == "function" then
        steppers.onStep(direction)
      end
    end)
    return button
  end

  steppers.back = Make(token.back, -1)
  steppers.forward = Make(token.forward, 1)
  parent.uuiForeverSliderSteppers = steppers
  return steppers
end

function gs.PaintSliderStepper(button)
  if not button or not button.face then return end
  local shade = button.enabled == false and 0.5 or 1
  pcall(button.face.SetVertexColor, button.face, shade, shade, shade, 1)
  pcall(button.EnableMouse, button, button.enabled ~= false)
end

function gs.SetSliderStepperState(steppers, back, forward)
  if not steppers then return end
  if steppers.back then
    steppers.back.enabled = back and true or false
    gs.PaintSliderStepper(steppers.back)
  end
  if steppers.forward then
    steppers.forward.enabled = forward and true or false
    gs.PaintSliderStepper(steppers.forward)
  end
end

-- One geometry source for the native Game Settings list and the integrated
-- UnrealUI controls. The dropdown group is derived from the slider group's
-- outer arrow edges, matching Forever's column exactly.
function gs.SliderControlSpan()
  local list = M.foreverWow.list
  local token = M.foreverWow.control.slider
  local left = list.sliderX - token.stepperGap - token.back.width
  local right = list.sliderX + list.sliderWidth + token.stepperGap +
                token.forward.width
  return left, right - left
end

function gs.DropdownStepperPads()
  local spec = M.foreverWow.control.dropdown.stepper
  local bed = math.max(0, (spec.bedSize - spec.width) / 2)
  return spec.gapLeft + spec.width + bed,
         spec.gapRight + spec.width + bed
end

function gs.DropdownControlSpan()
  local sliderLeft, span = gs.SliderControlSpan()
  local leftPad, rightPad = gs.DropdownStepperPads()
  local nudge = M.foreverWow.list.dropdownShift or 0
  return sliderLeft + leftPad + nudge, span - leftPad - rightPad
end

function gs.BuildDropdownSteppers(parent)
  if not parent then return nil end
  if parent.uuiForeverDropdownSteppers then
    return parent.uuiForeverDropdownSteppers
  end
  local token = M.foreverWow.control.dropdown
  local spec = token.stepper
  local steppers = {}

  local function Make(direction, icon)
    local ok, button = pcall(CreateFrame, "Button", nil, parent)
    if not ok or not button then return nil end
    pcall(button.SetWidth, button, spec.width)
    pcall(button.SetHeight, button, spec.height)
    pcall(button.EnableMouse, button, true)
    local level = gs.Number(parent, "GetFrameLevel")
    if level then pcall(button.SetFrameLevel, button, level + 1) end
    local function Piece(layer, path, size)
      local made, texture = pcall(button.CreateTexture, button, nil, layer)
      if not made or not texture then return nil end
      pcall(texture.SetTexture, texture, path)
      pcall(texture.SetPoint, texture, "CENTER", button, "CENTER", 0, 0)
      pcall(texture.SetWidth, texture, size)
      pcall(texture.SetHeight, texture, size)
      return texture
    end
    button.bed = Piece("BACKGROUND", token.texture, spec.bedSize)
    button.icon = Piece("OVERLAY", spec.iconTexture, spec.iconSize)
    button.enabled = true
    button.direction = direction
    button.iconKey = icon
    button:SetScript("OnEnter", function()
      button.over = true
      gs.PaintDropdownStepper(button)
    end)
    button:SetScript("OnLeave", function()
      button.over = false
      button.down = false
      gs.PaintDropdownStepper(button)
    end)
    button:SetScript("OnMouseDown", function()
      button.down = true
      gs.PaintDropdownStepper(button)
    end)
    button:SetScript("OnMouseUp", function()
      button.down = false
      gs.PaintDropdownStepper(button)
    end)
    button:SetScript("OnClick", function()
      if type(steppers.onClick) == "function" then
        steppers.onClick(direction, button.enabled and true or false)
      end
      if button.enabled and type(steppers.onStep) == "function" then
        steppers.onStep(direction)
      end
    end)
    return button
  end

  steppers.back = Make(-1, "back")
  steppers.next = Make(1, "next")
  parent.uuiForeverDropdownSteppers = steppers
  gs.SetDropdownStepperState(steppers, true, true)
  return steppers
end

function gs.PaintDropdownStepper(button)
  if not button or not button.bed then return end
  local token = M.foreverWow.control.dropdown
  local spec = token.stepper
  local cell = spec.normal
  if not button.enabled then
    cell = spec.disabled
  elseif button.down then
    cell = spec.pressed
  elseif button.over then
    cell = spec.hover
  end
  gs.SetCell(button.bed, cell, token.sheet)
  if button.icon then
    local key = button.iconKey .. (button.enabled and "" or "Disabled")
    gs.SetCell(button.icon, spec[key], spec.iconSheet)
  end
  pcall(button.EnableMouse, button, button.enabled and true or false)
end

function gs.SetDropdownStepperState(steppers, back, next)
  if not steppers then return end
  if steppers.back then
    steppers.back.enabled = back and true or false
    gs.PaintDropdownStepper(steppers.back)
  end
  if steppers.next then
    steppers.next.enabled = next and true or false
    gs.PaintDropdownStepper(steppers.next)
  end
end

function gs.StyleOwnedCheckbox(control)
  if not control or control.uuiForeverStyled or not control.box then return false end
  control.uuiForeverStyled = true
  local original = control.Apply
  control.Apply = function()
    if type(original) == "function" then original() end
    -- The shared widget's old flat mark is not merely hidden: its private
    -- Apply can show it again later. Emptying this owned texture guarantees
    -- the Forever checkmark is the only checked-state art.
    if control.box.uuiCheckboxMark then
      pcall(control.box.uuiCheckboxMark.SetTexture,
            control.box.uuiCheckboxMark, "")
    end
    gs.PaintOwnedCheckbox(control.box, control.value, control.enabled)
    if control.row then U.SetBackdropShown(control.row, false) end
    if control.label then
      U.SetStockFont(control.label, M.fontSize.normal,
                     control.enabled and M.foreverWow.list.labelColor or
                     M.color.textDim)
    end
  end
  control.Apply()
  return true
end

function gs.StyleOwnedRadio(control)
  if not control or control.uuiForeverStyled or type(control.rows) ~= "table" then
    return false
  end
  control.uuiForeverStyled = true
  local function PaintRow(row)
    local selected = row.item and row.item.value == control.value
    local enabled = not (row.item and row.item.disabled)
    if row.indicator then
      U.SetBackdropShown(row.indicator, false)
      if row.mark then
        pcall(row.mark.SetTexture, row.mark, "")
        pcall(row.mark.Hide, row.mark)
      end
      gs.PaintOwnedCheckbox(row.indicator, selected, enabled)
    end
    U.SetBackdropShown(row, false)
    if row.label then
      U.SetStockFont(row.label, M.fontSize.normal,
                     enabled and M.foreverWow.list.labelColor or M.color.textDim)
    end
  end
  local original = control.Apply
  control.Apply = function()
    if type(original) == "function" then original() end
    local i
    for i = 1, table.getn(control.rows) do PaintRow(control.rows[i]) end
  end
  local i
  for i = 1, table.getn(control.rows) do
    local row = control.rows[i]
    -- U.CreateRadioGroup's private ApplyRow runs directly on OnLeave and can
    -- otherwise restore its flat accent square after our public Apply wrapper.
    U.PostHookScript(row, "OnEnter", function() PaintRow(row) end)
    U.PostHookScript(row, "OnLeave", function() PaintRow(row) end)
    U.PostHookScript(row, "OnShow", function() PaintRow(row) end)
  end
  control.Apply()
  return true
end

function gs.StyleOwnedDropdown(control)
  if not control or control.uuiForeverStyled or not control.button then return false end
  if type(U.Dropdown) ~= "table" or type(U.Dropdown.BuildBed) ~= "function" then
    return false
  end
  control.uuiForeverStyled = true
  local token = M.foreverWow.control.dropdown
  local button = control.button
  local _, controlWidth = gs.DropdownControlSpan()
  if controlWidth and controlWidth > 0 then
    pcall(button.SetWidth, button, controlWidth)
    if control.menu then pcall(control.menu.SetWidth, control.menu, controlWidth) end
    local rowIndex
    for rowIndex = 1, table.getn(control.rows or {}) do
      local row = control.rows[rowIndex]
      pcall(row.SetWidth, row, controlWidth - 2)
      if row.label then pcall(row.label.SetWidth, row.label, controlWidth - 16) end
    end
  end
  pcall(button.SetHeight, button, token.controlHeight)
  U.SetBackdropShown(button, false)
  button.uuiDropdownStateButton = button
  U.Dropdown.BuildBed(button, token)
  button.uuiForeverBed = true

  local function Paint(state)
    U.SetBackdropShown(button, false)
    local enabled = gs.Read(button, "IsEnabled")
    if enabled == 0 or enabled == false then state = "disabled" end
    U.Dropdown.PaintBed(button, state)
  end
  U.PostHookScript(button, "OnEnter", function() Paint("hover") end)
  U.PostHookScript(button, "OnLeave", function() Paint(nil) end)
  U.PostHookScript(button, "OnMouseDown", function() Paint("pressed") end)
  U.PostHookScript(button, "OnMouseUp", function() Paint("hover") end)
  U.PostHookScript(button, "OnShow", function() Paint(nil) end)

  if control.arrow then pcall(control.arrow.Hide, control.arrow) end
  local setShown = control.uuiSetShown
  if type(setShown) == "function" then
    control.uuiSetShown = function(shown)
      setShown(shown)
      U.SetBackdropShown(button, false)
      if control.arrow then pcall(control.arrow.Hide, control.arrow) end
    end
  end
  if button.label then
    pcall(button.label.ClearAllPoints, button.label)
    pcall(button.label.SetPoint, button.label, "LEFT", button, "LEFT",
          token.textInset, U.BUTTON_LABEL_OFFSET_Y)
    pcall(button.label.SetPoint, button.label, "RIGHT", button, "RIGHT",
          -(button.uuiDropdownBedRight or token.textInset),
          U.BUTTON_LABEL_OFFSET_Y)
    pcall(button.label.SetJustifyH, button.label, token.textAlign or "LEFT")
    U.SetStockFont(button.label, token.textSize or M.fontSize.normal,
                   token.textColor)
  end

  if control.menu and type(U.Dropdown.BedMenu) == "function" then
    U.SetBackdropShown(control.menu, false)
    U.Dropdown.BedMenu(control.menu, token)
    local originalOpen = control.SetOpen
    control.SetOpen = function(open)
      originalOpen(open)
      U.SetBackdropShown(control.menu, false)
      local chrome = control.menu.uuiDropdownBedMenu
      if chrome then
        if open then pcall(chrome.Show, chrome) else pcall(chrome.Hide, chrome) end
      end
    end
    control.SetOpen(control.open)
  end

  local steppers = gs.BuildDropdownSteppers(button)
  if steppers then
    local function RefreshSteppers()
      local back, next = false, false
      if type(control.GetStepState) == "function" then
        back, next = control.GetStepState()
      end
      gs.SetDropdownStepperState(steppers, back, next)
    end
    local spec = token.stepper
    steppers.onStep = function(direction)
      if type(control.StepValue) == "function" then control.StepValue(direction) end
      RefreshSteppers()
    end
    if steppers.back then
      pcall(steppers.back.ClearAllPoints, steppers.back)
      pcall(steppers.back.SetPoint, steppers.back, "RIGHT", button, "LEFT",
            -spec.gapLeft, 0)
      pcall(steppers.back.Show, steppers.back)
    end
    if steppers.next then
      pcall(steppers.next.ClearAllPoints, steppers.next)
      pcall(steppers.next.SetPoint, steppers.next, "LEFT", button, "RIGHT",
            spec.gapRight, 0)
      pcall(steppers.next.Show, steppers.next)
    end
    local setValue = control.SetValue
    if type(setValue) == "function" then
      control.SetValue = function(value, notify)
        local result = setValue(value, notify)
        RefreshSteppers()
        return result
      end
    end
    RefreshSteppers()
    control.uuiForeverSteppers = steppers
  end
  Paint(nil)
  return true
end

function gs.StyleOwnedSlider(control)
  if not control or control.uuiForeverStyled or not control.track then return false end
  control.uuiForeverStyled = true
  local token = M.foreverWow.control.slider
  local track = control.track
  if type(control.SetControlWidth) == "function" then
    control.SetControlWidth(M.foreverWow.list.sliderWidth)
  end
  U.SetBackdropShown(track, false)
  if control.caption then
    U.SetStockFont(control.caption, M.fontSize.normal,
                   M.foreverWow.list.labelColor)
  end
  control.uuiForeverBar = gs.BuildSliderBar(track)

  if control.thumbVisual then
    U.SetBackdropShown(control.thumbVisual, false)
    local thumb = gs.Cell(control.thumbVisual, "OVERLAY", token.texture)
    if thumb then
      gs.StyleSliderThumb(thumb)
      pcall(thumb.SetPoint, thumb, "CENTER", control.thumbVisual, "CENTER", 0, 0)
      control.uuiForeverThumb = thumb
    end
  end

  -- Forever writes the value beside the Forward arrow; it does not put a
  -- second flat/edit-style box beneath the track.
  if control.box then
    U.SetBackdropShown(control.box, false)
    pcall(control.box.ClearAllPoints, control.box)
    pcall(control.box.SetPoint, control.box, "LEFT", track, "RIGHT",
          M.foreverWow.list.valueGap, 0)
    if control.readout then
      U.SetStockFont(control.readout, M.fontSize.normal,
                     M.foreverWow.list.valueColor)
      pcall(control.readout.SetJustifyH, control.readout, "LEFT")
    end
  end
  if control.minLabel then pcall(control.minLabel.Hide, control.minLabel) end
  if control.maxLabel then pcall(control.maxLabel.Hide, control.maxLabel) end
  control.uuiSetShown = function(shown)
    local partIndex
    for partIndex = 1, table.getn(control.uuiParts or {}) do
      local part = control.uuiParts[partIndex]
      if shown then pcall(part.Show, part) else pcall(part.Hide, part) end
    end
    if control.minLabel then pcall(control.minLabel.Hide, control.minLabel) end
    if control.maxLabel then pcall(control.maxLabel.Hide, control.maxLabel) end
  end

  local steppers = gs.BuildSliderSteppers(track)
  if steppers then
    local function RefreshSteppers()
      local back, forward = false, false
      if type(control.GetStepState) == "function" then
        back, forward = control.GetStepState()
      end
      gs.SetSliderStepperState(steppers, back, forward)
    end
    steppers.onStep = function(direction)
      if type(control.StepValue) == "function" then control.StepValue(direction) end
      RefreshSteppers()
    end
    if steppers.back then
      pcall(steppers.back.ClearAllPoints, steppers.back)
      pcall(steppers.back.SetPoint, steppers.back, "RIGHT", track, "LEFT",
            -token.stepperGap, 0)
      pcall(steppers.back.Show, steppers.back)
    end
    if steppers.forward then
      pcall(steppers.forward.ClearAllPoints, steppers.forward)
      pcall(steppers.forward.SetPoint, steppers.forward, "LEFT", track, "RIGHT",
            token.stepperGap, 0)
      pcall(steppers.forward.Show, steppers.forward)
    end
    local setValue = control.SetValue
    if type(setValue) == "function" then
      control.SetValue = function(value)
        local result = setValue(value)
        RefreshSteppers()
        return result
      end
    end
    RefreshSteppers()
    control.uuiForeverSteppers = steppers
  end
  return true
end

function gs.StyleOwnedColor(control)
  if not control or control.uuiForeverStyled or not control.swatch then return false end
  control.uuiForeverStyled = true
  gs.BuildOwnedCheckboxFace(control.swatch)
  U.SetBackdropShown(control.swatch, false)
  if control.preview then
    pcall(control.preview.SetDrawLayer, control.preview, "OVERLAY", 1)
    pcall(control.preview.ClearAllPoints, control.preview)
    pcall(control.preview.SetPoint, control.preview, "TOPLEFT", control.swatch,
          "TOPLEFT", 4, -4)
    pcall(control.preview.SetPoint, control.preview, "BOTTOMRIGHT", control.swatch,
          "BOTTOMRIGHT", -4, 4)
  end
  if control.label then
    U.SetStockFont(control.label, M.fontSize.normal,
                   M.foreverWow.list.labelColor)
  end
  return true
end

function gs.StyleOwnedButton(button)
  if not button or button.uuiFlag or button.uuiForeverFace or
     button.uuiForeverBed then return false end
  local height = gs.Number(button, "GetHeight")
  if not height or height < 8 or height > 40 then return false end
  U.SetBackdropShown(button, false)
  return gs.DressButton(button, height)
end

function gs.StyleOwnedSectionHeader(control)
  if not control or control.uuiForeverStyled or not control.title then return false end
  control.uuiForeverStyled = true
  local title = control.title
  local parent = control.uuiSectionParent
  local i
  for i = 1, table.getn(control.uuiParts or {}) do
    local part = control.uuiParts[i]
    if part ~= title then pcall(part.Hide, part) end
  end
  if parent then
    pcall(title.ClearAllPoints, title)
    pcall(title.SetPoint, title, "TOPLEFT", parent, "TOPLEFT",
          control.uuiSectionX or 0, control.uuiSectionY or 0)
  end
  pcall(title.SetWidth, title, control.uuiSectionWidth or 400)
  pcall(title.SetJustifyH, title, "LEFT")
  -- Match the native Game Settings section title treatment (for example the
  -- Video page's "Legacy" heading), whose larger white face comes from
  -- GameFontHighlightLarge rather than GameFontNormal.
  U.SetStockFont(title, M.fontSize.large, M.foreverWow.list.sectionColor,
                 U.G("GameFontHighlightLarge"))

  control.uuiSetShown = function(shown)
    if shown then pcall(title.Show, title) else pcall(title.Hide, title) end
    local partIndex
    for partIndex = 1, table.getn(control.uuiParts or {}) do
      local part = control.uuiParts[partIndex]
      if part ~= title then pcall(part.Hide, part) end
    end
  end
  return true
end

function gs.StyleIntegratedWidget(widget)
  if not widget then return end
  if widget.uuiSectionHeader then
    gs.StyleOwnedSectionHeader(widget)
    return
  end
  if widget.box and widget.Apply and widget.SetEnabled then
    gs.StyleOwnedCheckbox(widget)
    return
  end
  if widget.button and widget.menu and widget.rows then
    gs.StyleOwnedDropdown(widget)
    return
  end
  if widget.track and widget.thumbVisual then
    gs.StyleOwnedSlider(widget)
    return
  end
  if widget.swatch and widget.preview then
    gs.StyleOwnedColor(widget)
    return
  end
  if widget.rows and widget.SetValue and widget.rows[1] and
     widget.rows[1].indicator then
    gs.StyleOwnedRadio(widget)
    return
  end
  if gs.Read(widget, "GetObjectType") == "Button" then
    gs.StyleOwnedButton(widget)
  end
end

function gs.StyleIntegratedWidgets(widgets)
  if type(widgets) ~= "table" then return end
  local i
  for i = 1, table.getn(widgets) do gs.StyleIntegratedWidget(widgets[i]) end
end

-- ---------------------------------------------------------------------------
-- Key Bindings, drawn as Forever draws its own (user request, 2026-09-22)
--
-- Forever's Keybindings page is a settings list of collapsible sections
-- (Blizzard_SettingsDefinitions_Frame/Keybindings.lua) whose rows carry
-- KeyBindingFrameBindingButtonTemplate -- UIMenuButtonStretchTemplate's silver
-- stretch face -- and whose category headers are
-- SettingsExpandableSectionTemplate's Options_ListExpand bar with a +/- cap.
-- This page stays the client's own KeyBindingFrame, so what is reproduced is
-- the ART on the client's rows: the silver face on every binding button, and
-- that bar on every category row.
--
-- The client's widget names are UnrealPfUI's, which skins this same frame on
-- this same client (WORKING_SOURCE, skins/blizzard/keybindings.lua):
-- KeyBindingFrameBinding<row>Key<1|2>Button inside KeyBindingFrameScrollFrame,
-- KEY_BINDINGS_DISPLAYED rows recycled as the list scrolls. A row's own frame
-- is read from the button's parent when the row itself has no global name.
-- ---------------------------------------------------------------------------

-- UIMenuButtonStretchTemplate is one 128x32 sheet cut nine ways: four 12x6
-- corners at the corners, a 6-tall top and bottom that stretch sideways, a
-- 12-wide left and right that stretch down, and a centre that stretches both
-- ways. Every piece keeps its texture coordinates when the sheet is swapped
-- for the pressed one, which is how the template's own mixin presses it.
function gs.BuildSilverFace(button)
  local token = M.foreverWow.control.binding
  local face = { pieces = {} }

  -- ARTWORK, not BACKGROUND: this client's own binding face is a set of
  -- regions rather than the button's state slots, and it comes back after the
  -- page's own update (reported in game 2026-09-22 -- the stock rounded face
  -- drew over the silver one). The face is drawn above that layer and
  -- gs.StripSilverForeign takes the client's art off again on every repaint;
  -- the button's label is OVERLAY, so it still sits above both.
  local function Piece(cell, width, height)
    local texture = gs.Cell(button, "ARTWORK", token.up, cell)
    if not texture then return nil end
    if width then pcall(texture.SetWidth, texture, width) end
    if height then pcall(texture.SetHeight, texture, height) end
    table.insert(face.pieces, texture)
    return texture
  end

  local cw, ch = token.corner.width, token.corner.height
  local ew = token.edge.width
  local topLeft     = Piece(token.topLeft, cw, ch)
  local topRight    = Piece(token.topRight, cw, ch)
  local bottomLeft  = Piece(token.bottomLeft, cw, ch)
  local bottomRight = Piece(token.bottomRight, cw, ch)
  if not topLeft or not topRight or not bottomLeft or not bottomRight then
    return nil
  end
  topLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  topRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
  bottomLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  bottomRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

  local topMiddle = Piece(token.topMiddle, nil, ch)
  if topMiddle then
    topMiddle:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    topMiddle:SetPoint("BOTTOMRIGHT", topRight, "BOTTOMLEFT", 0, 0)
  end
  local bottomMiddle = Piece(token.bottomMiddle, nil, ch)
  if bottomMiddle then
    bottomMiddle:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT", 0, 0)
    bottomMiddle:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
  end
  local middleLeft = Piece(token.middleLeft, ew, nil)
  if middleLeft then
    middleLeft:SetPoint("TOPRIGHT", topLeft, "BOTTOMRIGHT", 0, 0)
    middleLeft:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
  end
  local middleRight = Piece(token.middleRight, ew, nil)
  if middleRight then
    middleRight:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    middleRight:SetPoint("BOTTOMLEFT", bottomRight, "TOPLEFT", 0, 0)
  end
  local middle = Piece(token.middleMiddle, nil, nil)
  if middle then
    middle:SetPoint("TOPLEFT", topLeft, "BOTTOMRIGHT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", bottomRight, "TOPLEFT", 0, 0)
  end

  -- The pieces whose fixed dimension is re-derived from the button's height in
  -- gs.SizeSilverFace: the four corners take both, the horizontal edges the
  -- height and the vertical edges the width.
  face.corner = { topLeft, topRight, bottomLeft, bottomRight }
  face.edgeH = { topMiddle, bottomMiddle }
  face.edgeV = { middleLeft, middleRight }

  -- The template's HighlightTexture, at its own crop and ADD blend. Shown from
  -- the button's own OnEnter rather than left to the HIGHLIGHT draw layer,
  -- which is not verified on this client. Created after the face on the same
  -- layer, so it draws over it.
  face.highlight = gs.Cell(button, "ARTWORK", token.highlight,
                           token.highlightCoords)
  if face.highlight then
    pcall(face.highlight.SetAllPoints, face.highlight, button)
    pcall(face.highlight.SetBlendMode, face.highlight, "ADD")
    pcall(face.highlight.Hide, face.highlight)
  end
  return face
end

-- The client's own art on a binding button, taken off again after its update
-- has put it back. This is the one strip shape rules/unreal-ui.md allows on a
-- button that already carries addon textures: regions are told apart by the
-- PATH they draw, never by identity (a walked region is never == what a getter
-- returned), and anything under unrealUI -- the silver face and its highlight
-- -- is left alone, exactly as book.StripForeign does in
-- modules/spellbookmodernwow.lua. A region whose path cannot be read is left
-- alone too.
function gs.StripSilverForeign(button)
  if not button or type(button.GetRegions) ~= "function" then return end
  local ok, regions = pcall(function() return { button:GetRegions() } end)
  if not ok or not regions then return end

  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    if gs.Read(region, "GetObjectType") == "Texture" and
       gs.Read(region, "IsShown") then
      local path = gs.Read(region, "GetTexture")
      if type(path) == "string" and path ~= "" and
         not string.find(string.lower(path), "unrealui", 1, true) then
        pcall(region.Hide, region)
      end
    end
  end
end

-- The face in the template's own PROPORTION rather than at its authored
-- texel sizes. UIMenuButtonStretchTemplate cuts a 22-high button into 6-high
-- caps and a 12-wide rim; this client's binding button is only about 15 units
-- high, and the authored 6 left the rim taking four fifths of it -- the thick
-- rounded pill reported in game 2026-09-22 with a screenshot. Measured in the
-- same dump: the client's own three-slice caps read 8.12 where the template's
-- are 12, which is that same ratio, so this is what the client does with the
-- art too. Re-checked on every repaint, because the page relayouts itself.
function gs.SizeSilverFace(button)
  local face = button and button.uuiSilver
  if not face then return end
  local token = M.foreverWow.control.binding
  local height = gs.Number(button, "GetHeight")
  if not height or height < 4 then return end

  local ratio = height / token.height
  if ratio > 1 then ratio = 1 end
  if face.ratio and ratio > face.ratio - 0.01 and ratio < face.ratio + 0.01 then
    return
  end
  face.ratio = ratio

  local cw = token.corner.width * ratio
  local ch = token.corner.height * ratio
  local ew = token.edge.width * ratio
  local i
  for i = 1, table.getn(face.corner) do
    pcall(face.corner[i].SetWidth, face.corner[i], cw)
    pcall(face.corner[i].SetHeight, face.corner[i], ch)
  end
  for i = 1, table.getn(face.edgeH) do
    pcall(face.edgeH[i].SetHeight, face.edgeH[i], ch)
  end
  for i = 1, table.getn(face.edgeV) do
    pcall(face.edgeV[i].SetWidth, face.edgeV[i], ew)
  end
end

function gs.PaintSilver(button)
  local face = button and button.uuiSilver
  if not face then return end
  gs.StripSilverForeign(button)
  gs.SizeSilverFace(button)
  local token = M.foreverWow.control.binding
  local enabled = gs.Read(button, "IsEnabled")
  local disabled = (enabled == 0 or enabled == false)
  local path = (face.pressed and not disabled) and token.down or token.up

  local i
  for i = 1, table.getn(face.pieces) do
    local piece = face.pieces[i]
    pcall(piece.SetTexture, piece, path)
    if disabled then
      pcall(piece.SetVertexColor, piece, 0.55, 0.55, 0.55, 1)
    else
      pcall(piece.SetVertexColor, piece, 1, 1, 1, 1)
    end
  end
  if face.highlight then
    if face.over and not disabled and not face.pressed then
      pcall(face.highlight.Show, face.highlight)
    else
      pcall(face.highlight.Hide, face.highlight)
    end
  end
  -- Only a disabled button's text is recoloured. The client already tells a
  -- bound key from an unbound one by colour on every update, and overriding
  -- that on each repaint would flatten the two into one.
  if face.label and disabled then
    U.SetStockFont(face.label, M.fontSize.small, token.disabledTextColor)
  end
end

-- The client's own state art is cleared first, before any addon texture is
-- added to the button: the strip-then-dress order rules/unreal-ui.md requires,
-- and it runs once per button because the face is remembered on it.
function gs.DressSilverButton(name)
  local button = U.G(name)
  if not button or button.uuiSilver then return false end

  -- This client draws a binding button's face as its own texture REGIONS, not
  -- through the Normal / Pushed / Highlight / Disabled slots: clearing the
  -- slots alone left the stock red face drawing over the silver one
  -- (reported in game 2026-09-22 with a screenshot). U.ClearStockButtonFaces
  -- empties the slots AND walks the button's regions, which is the shared
  -- helper the Modern WoW scrollbar's steppers already use. The walk is safe
  -- here for the reason rules/unreal-ui.md gives: it runs once, BEFORE any
  -- addon texture is put on this button, and the face below is what it then
  -- carries.
  if type(U.ClearStockButtonFaces) == "function" then
    local keep = (type(U.StockRegionKeep) == "function" and
                  U.StockRegionKeep(button)) or {}
    U.ClearStockButtonFaces(button, keep)
  end

  local face = gs.BuildSilverFace(button)
  if not face then return false end
  face.label = gs.Read(button, "GetFontString")
  button.uuiSilver = face

  if face.label then U.CenterButtonLabel(face.label, button) end
  U.PostHookScript(button, "OnEnter", function()
    face.over = true; gs.PaintSilver(button)
  end)
  U.PostHookScript(button, "OnLeave", function()
    face.over = false; face.pressed = false; gs.PaintSilver(button)
  end)
  U.PostHookScript(button, "OnMouseDown", function()
    face.pressed = true; gs.PaintSilver(button)
  end)
  U.PostHookScript(button, "OnMouseUp", function()
    face.pressed = false; gs.PaintSilver(button)
  end)
  U.PostHookScript(button, "OnShow", function()
    face.pressed = false; gs.PaintSilver(button)
  end)
  gs.PaintSilver(button)
  return true
end

-- KEY_BINDINGS_DISPLAYED is the client's own count; this is only the fallback
-- when that global is missing, and it is the 1.12 template's number.
gs.BINDING_ROWS = 20

-- ---------------------------------------------------------------------------
-- Moving a client object on a canvas page
--
-- A list page hands its controls to modules/gamesettingslist.lua, which
-- captures each one before it moves it and puts it back on detach. A canvas
-- page keeps the client's own layout, so only a few objects are ever moved --
-- the page's Okay and Cancel, and its two header strings -- and they keep the
-- same contract through these two functions: captured the first time they are
-- moved, restored by gs.Detach, so the panel handed back is the panel the
-- client had.
-- ---------------------------------------------------------------------------
function gs.KeepPlaced(page, object)
  if not object then return nil end
  local state = gs.placed[page.id]
  if not state then
    state = { order = {}, kept = {} }
    gs.placed[page.id] = state
  end
  if state.kept[object] then return state.kept[object] end

  local record = {
    object = object,
    parent = gs.Read(object, "GetParent"),
    width = gs.Number(object, "GetWidth"),
    height = gs.Number(object, "GetHeight"),
    scale = gs.Number(object, "GetScale"),
    points = {},
  }
  local count = gs.Number(object, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y = pcall(object.GetPoint, object, i)
    if ok and point then
      table.insert(record.points, { point, relative, relativePoint, x, y })
    end
  end
  state.kept[object] = record
  table.insert(state.order, record)
  return record
end

function gs.RestorePlaced(page)
  local state = gs.placed[page.id]
  if not state then return end

  -- Reverse order, as the list's own detach does: an object goes back before
  -- whatever it was anchored to is touched.
  local i
  for i = table.getn(state.order), 1, -1 do
    local record = state.order[i]
    local object = record.object
    -- Only a frame can be reparented on this client; a FontString is left
    -- with the parent it always had and only re-anchored.
    if record.parent and type(object.SetParent) == "function" then
      pcall(object.SetParent, object, record.parent)
    end
    pcall(object.ClearAllPoints, object)
    local j
    for j = 1, table.getn(record.points) do
      local p = record.points[j]
      pcall(object.SetPoint, object, p[1], p[2], p[3], p[4], p[5])
    end
    if record.width and type(object.SetWidth) == "function" then
      pcall(object.SetWidth, object, record.width)
    end
    if record.height and type(object.SetHeight) == "function" then
      pcall(object.SetHeight, object, record.height)
    end
    if record.scale and type(object.SetScale) == "function" then
      pcall(object.SetScale, object, record.scale)
    end
    object.uuiForeverDropped = nil
  end
  gs.placed[page.id] = nil
end

-- Draws one client object at the WINDOW's scale while it stays where the
-- client parented it. A canvas page is scaled to fit the box, so a control on
-- it draws smaller than the same control on a list page; this divides that
-- scale back out of the object alone, and its SetPoint offsets are then in the
-- window's own units.
--
-- Reparenting it to the window does the same thing and breaks the client:
-- these scripts reach their owner through GetParent. Reported in game
-- 2026-09-22 -- with the scrollbar moved to the page box, one wheel turn threw
-- "attempt to call method 'SetVerticalScroll' (a nil value)" from the client's
-- own OnValueChanged, which scrolls GetParent(). So nothing here is ever
-- reparented; only its scale and anchors change.
function gs.LiftToWindow(object, frame)
  if not object or type(object.SetScale) ~= "function" then return 1 end

  -- The object's own scale is set so that its EFFECTIVE scale becomes the page
  -- box's: effective = own x effective(parent), so own = the box's effective
  -- over the parent's. Dividing the page's GetScale out instead lands
  -- somewhere else entirely -- that scale is not what its children draw at
  -- (see gs.Unit).
  local parent = gs.Read(object, "GetParent")
  local base = parent and gs.Unit(parent) or gs.Unit(frame)
  local target = gs.Unit(gs.host)
  if base > 0 and target > 0 then
    pcall(object.SetScale, object, target / base)
  end
  return target
end

-- One row of the client's binding list. The row itself may have no global
-- name on this client, so it is read from its first key button's parent --
-- a read at dress time, to give that row's OWN art a parent, never a
-- persistent anchor onto a native widget.
function gs.BindingRow(index)
  local row = U.G("KeyBindingFrameBinding" .. index)
  if row then return row end
  local button = U.G("KeyBindingFrameBinding" .. index .. "Key1Button")
  if not button then return nil end
  return gs.Read(button, "GetParent")
end

-- A row's own label: the command's name, or a category's on a header row. The
-- row may have no global name here, so the FontString is looked up by the
-- row's name first and read off the row second.
function gs.BindingLabel(index)
  local label = U.G("KeyBindingFrameBinding" .. index .. "Text")
  if label then return label end
  local row = gs.BindingRow(index)
  return row and gs.Read(row, "GetFontString") or nil
end

-- SettingsExpandableSectionTemplate's bar: the 12x26 left cap, the 1x26 middle
-- stretched between, and the +/- cap at the right. Drawn at the row's own
-- height when that is shorter than Forever's 30, so a bar never covers the
-- row above or below it.
function gs.BuildBindingBar(row)
  local token = M.foreverWow.listExpand
  local path = M.foreverWow.texture.listExpand
  local bar = {}
  bar.left = gs.Cell(row, "BACKGROUND", path, token.left)
  bar.middle = gs.Cell(row, "BACKGROUND", path, token.middle)
  bar.right = gs.Cell(row, "BACKGROUND", path, token.expanded)
  if not bar.left or not bar.middle or not bar.right then return nil end
  return bar
end

function gs.LayoutBindingBar(row, bar)
  local token = M.foreverWow.listExpand
  local height = gs.Number(row, "GetHeight") or token.barHeight
  if height > token.barHeight then height = token.barHeight end
  if height < 6 then height = token.barHeight end
  local ratio = height / token.height
  -- This client applies these row-anchor offsets in screen pixels.
  local verticalInset = token.verticalInset or 0

  bar.left:ClearAllPoints()
  bar.left:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -verticalInset)
  bar.left:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, verticalInset)
  bar.left:SetWidth(token.leftWidth * ratio)

  -- Category rows are narrower than binding rows on this client. Their bar
  -- ends precisely at the visible Key 2 button, never at the window edge.
  local inset = token.barInsetRight
  local keyRight
  local count = tonumber(U.G("KEY_BINDINGS_DISPLAYED")) or gs.BINDING_ROWS
  if count < 1 or count > 64 then count = gs.BINDING_ROWS end
  local i
  for i = 1, count do
    local key = U.G("KeyBindingFrameBinding" .. i .. "Key2Button")
    if key and gs.Read(key, "IsShown") then
      keyRight = gs.Number(key, "GetRight")
      if keyRight then break end
    end
  end
  local rowLeft = gs.Number(row, "GetLeft")
  local fullWidth = keyRight and rowLeft and
    (keyRight - rowLeft) or nil

  bar.right:ClearAllPoints()
  if fullWidth then
    bar.right:SetPoint("TOPRIGHT", row, "TOPLEFT", fullWidth - inset,
                       -verticalInset)
    bar.right:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", fullWidth - inset,
                       verticalInset)
  else
    bar.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -inset, -verticalInset)
    bar.right:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset,
                       verticalInset)
  end
  bar.right:SetWidth(token.width * ratio)

  bar.middle:ClearAllPoints()
  bar.middle:SetPoint("LEFT", bar.left, "RIGHT", 0, 0)
  bar.middle:SetPoint("RIGHT", bar.right, "LEFT", 0, 0)
  bar.middle:SetPoint("TOP", row, "TOP", 0, -verticalInset)
  bar.middle:SetPoint("BOTTOM", row, "BOTTOM", 0, verticalInset)
end

-- A category row in the client's list is the one with no key buttons on it,
-- which is how this client marks a binding header. Repainted whenever the list
-- scrolls, because the client recycles these rows.
function gs.PaintBindingRow(index)
  local row = gs.BindingRow(index)
  if not row then return end
  local key1 = U.G("KeyBindingFrameBinding" .. index .. "Key1Button")
  local header = key1 ~= nil and not gs.Read(key1, "IsShown")

  -- The client repaints a recycled row's buttons with its own face and its own
  -- label colour, so the silver one is re-applied here rather than only on the
  -- button's own hover, press and show.
  local j
  for j = 1, 2 do
    local key = U.G("KeyBindingFrameBinding" .. index .. "Key" .. j .. "Button")
    if key and key.uuiSilver then gs.PaintSilver(key) end
  end

  local bar = row.uuiForeverBar
  if header and not bar then
    bar = gs.BuildBindingBar(row)
    row.uuiForeverBar = bar
  end
  if not bar then return end

  if header then
    gs.LayoutBindingBar(row, bar)
    bar.left:Show(); bar.middle:Show(); bar.right:Show()
  else
    bar.left:Hide(); bar.middle:Hide(); bar.right:Hide()
  end

  -- The category uses its own Header FontString, which shares the bar's
  -- BACKGROUND layer until raised here.
  if header then
    local label = U.G("KeyBindingFrameBinding" .. index .. "Header")
    local token = M.foreverWow.listExpand
    if label and not row.uuiForeverHeaderMoved then
      row.uuiForeverHeaderMoved = true
      pcall(label.ClearAllPoints, label)
      pcall(label.SetPoint, label, "LEFT", row, "LEFT",
            token.titleInset.x, token.titleInset.y)
    end
    if label then
      pcall(label.SetDrawLayer, label, "OVERLAY")
      U.SetStockFont(label, M.fontSize.normal, token.titleColor)
      pcall(label.Show, label)
    end
  end
end

function gs.PaintBindingList()
  local count = tonumber(U.G("KEY_BINDINGS_DISPLAYED")) or 0
  if count < 1 or count > 64 then count = gs.BINDING_ROWS end
  local i
  for i = 1, count do gs.PaintBindingRow(i) end
end

-- The content column a list page draws, in screen units: from the page box's
-- left plus list.padLeft to where the scrollbar's own column begins. These are
-- L.Build's and L.Layout's own numbers, so a row here spans exactly what a row
-- on the Video page spans.
-- One object's pixels-per-unit: what a size or a SetPoint offset set on it is
-- multiplied by before it is drawn.
--
-- This matters everywhere a measured rect is turned back into a number to set.
-- Measured 2026-09-22 (/uui gamedump keys): a texture set to 12 read back
-- 14.5037 and a button set to 90 read back 108.778 -- both 1.2086x -- so
-- GetLeft / GetWidth and friends report in SCREEN pixels while SetPoint and
-- SetWidth take the frame's own units. The divisor is the frame's EFFECTIVE
-- scale, never the page's own GetScale: the page reported 0.8175 while its
-- children drew at 1.2086, and converting with the page's scale overshot every
-- shift by half as much again (reported in game 2026-09-22 -- the listing
-- still sat right of the other pages).
function gs.Unit(object)
  local unit = gs.Number(object, "GetEffectiveScale")
  if not unit or unit <= 0 then unit = gs.Number(object, "GetScale") end
  if not unit or unit <= 0 then return 1 end
  return unit
end

-- The content column a list page draws, in SCREEN pixels: from the page box's
-- left plus list.padLeft to where the scrollbar's own column begins. The
-- tokens are the box's own units, so each is multiplied by the box's unit.
function gs.ListContent()
  if not gs.host then return nil end
  local list = M.foreverWow.list
  local left = gs.Number(gs.host, "GetLeft")
  local width = gs.Number(gs.host, "GetWidth")
  if not left or not width then return nil end
  local unit = gs.Unit(gs.host)
  local bar = (list.scrollbarWidth + list.scrollbarInset.right +
               list.scrollbarGap) * unit
  local pad = (list.padLeft + list.padRight) * unit
  return left + list.padLeft * unit, width - bar - pad
end

-- Shifts every point sideways and, on a row anchored by both edges, widens it
-- by moving the right one further. A row anchored by one point is widened with
-- SetWidth instead, which its single anchor lets through.
function gs.SpanPoints(object, delta, grow, drop)
  if not object then return false end
  local points = {}
  local count = gs.Number(object, "GetNumPoints") or 0
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y = pcall(object.GetPoint, object, i)
    if not ok or not point or not x then return false end
    table.insert(points, { point, relative, relativePoint, x, y })
  end
  if table.getn(points) < 1 then return false end

  local spanned = false
  pcall(object.ClearAllPoints, object)
  for i = 1, table.getn(points) do
    local p = points[i]
    local x = p[4] + delta
    if grow ~= 0 and string.find(p[1], "RIGHT") then
      x = x + grow
      spanned = true
    end
    -- A SetPoint offset is positive upward, so a drop is taken off y.
    pcall(object.SetPoint, object, p[1], p[2], p[3], x, p[5] - (drop or 0))
  end
  return true, spanned
end

-- Puts the binding list on a list page's own content column (user requests,
-- 2026-09-22): its left edge where a list row's left edge is, and its width
-- what a list row spans -- so the gap between the listing and the scrollbar is
-- the same on every page.
--
-- Every number is measured from the LIVE rect on each call, so running it
-- again after a re-fit corrects rather than compounds, and a row anchored to
-- one this pass has already moved is skipped -- the trap that carried the
-- bottom buttons off the panel on 2026-09-22.
function gs.AlignBindingList(page, frame)
  if not frame or not gs.host then return end

  -- Measured INSIDE the deferred pass, not before it. Two callers ask for this
  -- on consecutive ticks -- the skin pass and the re-fit after the page's own
  -- Show -- and a delta measured before the first write would be measured
  -- again, unchanged, and applied twice.
  U.DeferOnce("gamesettings:bindalign", function()
    if gs.active ~= page then return end
    local want, width = gs.ListContent()
    -- The page's own nudge off that column, taken out of the width so only the
    -- left edge moves.
    local nudge = M.foreverWow.keys.listNudge or 0
    if want then
      want = want + nudge
      width = width - nudge
    end
    local count = tonumber(U.G("KEY_BINDINGS_DISPLAYED")) or 0
    if count < 1 or count > 64 then count = gs.BINDING_ROWS end

    -- Measured on a BINDING row, never a category row: a category's label has
    -- been moved onto the bar at Forever's own inset, and reading that one
    -- would drag the whole listing left by it.
    local reference = 1
    local i
    for i = 1, count do
      local key = U.G("KeyBindingFrameBinding" .. i .. "Key1Button")
      if key and gs.Read(key, "IsShown") then
        reference = i
        break
      end
    end
    local first = gs.BindingRow(reference)
    local have = gs.Number(first, "GetLeft")
    local span = gs.Number(first, "GetWidth")
    if not want or not have or not span then return end

    -- Pixels per unit for the rows themselves; see gs.Unit.
    local scale = gs.Unit(first)

    -- What is aligned is the LINE the player sees -- the command's own text --
    -- not the row frame around it (user request, 2026-09-22: the listing still
    -- sat right of the other pages). A list row draws its label flush with the
    -- row (list.labelInset is 0), so that text is what starts at this column;
    -- this client insets its label inside the row instead, and the row has to
    -- move by that inset too.
    local label = gs.BindingLabel(reference)
    local text = gs.Number(label, "GetLeft") or have
    local shift = want - text
    -- The right edge still lands on the column's end, so the row is widened by
    -- whatever the shift took off it.
    local grow = (want + width) - (have + shift) - span

    local delta = shift / scale
    grow = grow / scale
    if delta > -0.5 and delta < 0.5 then delta = 0 end
    if grow > -0.5 and grow < 0.5 then grow = 0 end

    -- The listing's own drop. Unlike the shift and the width it is not
    -- measured against anything, so it is applied ONCE per attach -- marked on
    -- the row that takes it -- and every later pass leaves it alone rather
    -- than adding it again. gs.RestorePlaced clears the mark with the anchors.
    local drop = (M.foreverWow.keys.listDrop or 0) / scale
    local wanted = drop ~= 0 and first and not first.uuiForeverDropped
    if delta == 0 and grow == 0 and not wanted then return end

    local moved = {}
    for i = 1, count do
      local row = gs.BindingRow(i)
      if row then
        -- A row anchored to one already moved this pass follows its shift;
        -- moving it too would double it. Its WIDTH is still its own.
        local point, rel = U.GetFramePoint(row, 1)
        local chained = rel and moved[rel]
        gs.KeepPlaced(page, row)
        local fall = 0
        if not chained and drop ~= 0 and not row.uuiForeverDropped then
          fall = drop
          row.uuiForeverDropped = true
        end
        local ok, spanned = gs.SpanPoints(row, chained and 0 or delta, grow, fall)
        if ok and not spanned and grow ~= 0 then
          pcall(row.SetWidth, row, width / scale)
        end
        moved[row] = true
      end
    end

    -- The column headings sit over the rows' own columns: Name is offset right
    -- of the command text, while each Key label is centred on its button. Key
    -- 1 supplies the shared baseline, so all three captions stay level even
    -- when the client gives Command a different default anchor.
    local keyOneHeading = U.G("KeyBindingFrameKey1Label")
    local headerTop = gs.Number(keyOneHeading, "GetTop")
    local command = U.G("KeyBindingFrameCommandLabel")
    local at = gs.Number(command, "GetLeft")
    if command and at then
      gs.KeepPlaced(page, command)
      local commandWant = want + (M.foreverWow.keys.commandHeaderNudge or 0)
      local commandTop = gs.Number(command, "GetTop")
      local commandDrop = headerTop and commandTop and
        (commandTop - headerTop) / gs.Unit(command) or 0
      gs.SpanPoints(command, (commandWant - at) / gs.Unit(command), 0, commandDrop)
    end
    local j
    for j = 1, 2 do
      local heading = U.G("KeyBindingFrameKey" .. j .. "Label")
      local key = U.G("KeyBindingFrameBinding" .. reference .. "Key" .. j .. "Button")
      local from = gs.Number(heading, "GetLeft")
      local to = gs.Number(key, "GetLeft")
      local headWidth = gs.Number(heading, "GetWidth") or 0
      local keyWidth = gs.Number(key, "GetWidth") or 0
      if heading and from and to then
        gs.KeepPlaced(page, heading)
        local nudge = (M.foreverWow.keys.keyHeaderNudge or {})[j] or 0
        local centre = (to + keyWidth / 2) - (from + headWidth / 2) + nudge
        local keyTop = gs.Number(heading, "GetTop")
        local keyDrop = headerTop and keyTop and
          (keyTop - headerTop) / gs.Unit(heading) or 0
        gs.SpanPoints(heading, centre / gs.Unit(heading), 0, keyDrop)
      end
    end
  end)
end

-- The rest of this page drawn as the others are (user request, 2026-09-22):
-- the window's own scrollbar, its Okay and Cancel in the window's bottom-right
-- corner, and the client's two header strings moved inside the page.
--
-- Okay and Cancel are REPARENTED to the window rather than only re-anchored,
-- which is what modules/gamesettingslist.lua does for a list page's buttons.
-- A canvas page is scaled to fit the box and a reparented client widget does
-- not follow an ancestor's scale
-- (widgets.reparented_native_widget_ignores_ancestor_scale), so this is what
-- draws them at the same size as every other page's pair instead of at the
-- page's.
function gs.DressBindingChrome(page)
  local panel = M.foreverWow.panel

  -- The shared Modern WoW MinimalScrollBar, in the settings list's own seat
  -- (user request, 2026-09-22: the same position and size as the Video page's
  -- bar). That bar is L.Build's: a `list.scrollbarWidth` Slider hung on the
  -- page box's right edge at list.scrollbarInset, top to bottom. The client's
  -- own Slider is given the same parent, width and anchors, so the two pages
  -- show one bar in one place; it keeps its range, value and scripts, and its
  -- arrows -- children of the bar -- come with it.
  local frame = U.G(page.frame)
  local bar = U.G("KeyBindingFrameScrollFrameScrollBar")
  if bar and gs.host and frame then
    local list = M.foreverWow.list
    gs.KeepPlaced(page, bar)
    gs.LiftToWindow(bar, frame)
    pcall(bar.SetWidth, bar, list.scrollbarWidth)
    pcall(bar.ClearAllPoints, bar)
    pcall(bar.SetPoint, bar, "TOPRIGHT", gs.host, "TOPRIGHT",
          -list.scrollbarInset.right, -list.scrollbarInset.top)
    pcall(bar.SetPoint, bar, "BOTTOMRIGHT", gs.host, "BOTTOMRIGHT",
          -list.scrollbarInset.right, list.scrollbarInset.bottom)
    gs.Relevel(bar, (gs.Number(gs.host, "GetFrameLevel") or 1) + gs.ACTION_LEVEL, 0)
  end
  if bar and type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar, {
      onChange = function()
        U.DeferOnce("gamesettings:bindings", gs.PaintBindingList)
      end,
    })
  end

  local function Corner(object, point, relative, relativePoint, x, y)
    if not object then return false end
    gs.KeepPlaced(page, object)
    -- Lifted, never reparented: this page's Okay hides its own frame through
    -- GetParent, as its scrollbar scrolls through GetParent.
    gs.LiftToWindow(object, frame)
    pcall(object.SetWidth, object, panel.buttonWidth)
    pcall(object.SetHeight, object, panel.buttonHeight)
    pcall(object.ClearAllPoints, object)
    pcall(object.SetPoint, object, point, relative, relativePoint, x, y)
    local level = gs.Number(gs.panel, "GetFrameLevel") or 1
    gs.Relevel(object, level + gs.ACTION_LEVEL, 0)
    return true
  end

  -- Cancel in the window's bottom-right corner and Okay to its left, at the
  -- same insets L.PlaceChrome uses for every list page.
  local cancel = U.G("KeyBindingFrameCancelButton")
  local okay = U.G("KeyBindingFrameOkayButton")
  if gs.panel and Corner(cancel, "BOTTOMRIGHT", gs.panel, "BOTTOMRIGHT",
                         -panel.buttonInset.right, panel.buttonInset.bottom) then
    Corner(okay, "RIGHT", cancel, "LEFT", -panel.buttonGap, 0)
  end

  local keys = M.foreverWow.keys

  -- Unbind and Default stay on the page, in its bottom-left corner. They are
  -- re-anchored, not left alone: the client anchors them off Okay, which has
  -- just left for the window's corner, and they would follow it there.
  local unbind = U.G("KeyBindingFrameUnbindButton")
  local defaults = U.G("KeyBindingFrameDefaultButton")
  if frame and defaults then
    gs.KeepPlaced(page, defaults)
    pcall(defaults.ClearAllPoints, defaults)
    pcall(defaults.SetPoint, defaults, "BOTTOMLEFT", frame, "BOTTOMLEFT",
          keys.actionInset.x, keys.actionInset.y)
    if unbind then
      gs.KeepPlaced(page, unbind)
      pcall(unbind.ClearAllPoints, unbind)
      pcall(unbind.SetPoint, unbind, "LEFT", defaults, "RIGHT", keys.actionGap, 0)
    end
  end

  -- The page's own title and its binding-set line. The client draws both on a
  -- plate above the panel, which this window hides, so they are moved inside
  -- the panel, with the binding-set line beside the title.
  local function Inside(object, inset)
    if not object or not frame or not inset then return end
    gs.KeepPlaced(page, object)
    pcall(object.ClearAllPoints, object)
    pcall(object.SetPoint, object, "TOPLEFT", frame, "TOPLEFT", inset.x, inset.y)
  end
  local title = U.G("KeyBindingFrameHeaderText")
  local output = U.G("KeyBindingFrameOutputText")
  if title and gs.pageTitle then
    gs.KeepPlaced(page, title)
    pcall(title.ClearAllPoints, title)
    pcall(title.SetPoint, title, "LEFT", gs.pageTitle, "RIGHT", keys.titleGap, 0)
  else
    Inside(title, keys.titleInset)
  end
  if output and title then
    gs.KeepPlaced(page, output)
    pcall(output.ClearAllPoints, output)
    pcall(output.SetPoint, output, "LEFT", title, "RIGHT", keys.outputGap, 0)
  else
    Inside(output, keys.outputInset)
  end

  -- A binding button changes this same output label to the "Press a key"
  -- instruction. It belongs beside the two bottom action buttons while the
  -- client is listening, then returns to its usual header placement next time
  -- this page is attached.
  local function PlaceBindingPrompt()
    local prompt = U.G("KeyBindingFrameOutputText")
    local action = U.G("KeyBindingFrameUnbindButton")
    if not prompt or not action or gs.active ~= page then return end
    gs.KeepPlaced(page, prompt)
    pcall(prompt.ClearAllPoints, prompt)
    pcall(prompt.SetPoint, prompt, "LEFT", action, "RIGHT", keys.promptGap, 0)
  end
  local count = tonumber(U.G("KEY_BINDINGS_DISPLAYED")) or gs.BINDING_ROWS
  if count < 1 or count > 64 then count = gs.BINDING_ROWS end
  local i, slot
  for i = 1, count do
    for slot = 1, 2 do
      local button = U.G("KeyBindingFrameBinding" .. i .. "Key" .. slot .. "Button")
      if button and not button.uuiForeverPromptHook then
        button.uuiForeverPromptHook = true
        U.PostHookScript(button, "OnClick", function()
          U.DeferOnce("gamesettings:bindingprompt", PlaceBindingPrompt)
        end)
      end
    end
  end

  -- Its text is a child of this native checkbox, so moving the checkbox keeps
  -- the two aligned. Reapply the first captured anchor to avoid compounding on
  -- the client's later Key Bindings relayouts.
  local character = U.G("KeyBindingFrameCharacterButton")
  local characterRecord = gs.KeepPlaced(page, character)
  local characterPoint = characterRecord and characterRecord.points[1]
  if character and characterPoint then
    local x = tonumber(characterPoint[4]) or 0
    local y = tonumber(characterPoint[5]) or 0
    pcall(character.ClearAllPoints, character)
    pcall(character.SetPoint, character, characterPoint[1], characterPoint[2],
          characterPoint[3], x + keys.characterShift.x, y + keys.characterShift.y)
  end
  local characterText = U.G("KeyBindingFrameCharacterButtonText") or
                        (character and gs.Read(character, "GetFontString"))
  if characterText then
    gs.KeepPlaced(page, characterText)
    pcall(characterText.ClearAllPoints, characterText)
    pcall(characterText.SetPoint, characterText, "LEFT", character, "RIGHT",
          keys.characterTextGap, keys.characterTextLift)
  end

  gs.AlignBindingList(page, frame)
end

-- How far above the window a moved page action sits: clear of the plate, the
-- category list and the page itself, which is the host's level plus its own
-- subtree.
gs.ACTION_LEVEL = 10

-- The client repaints its rows from the scroll bar's value (and again every
-- time the page is shown), so the bars follow that rather than an OnUpdate.
function gs.WatchBindingList()
  if gs.bindingWatched then
    gs.PaintBindingList()
    return
  end
  gs.bindingWatched = true

  local function Repaint()
    U.DeferOnce("gamesettings:bindings", gs.PaintBindingList)
  end
  local bar = U.G("KeyBindingFrameScrollFrameScrollBar")
  if bar then U.PostHookScript(bar, "OnValueChanged", Repaint) end
  local frame = U.G("KeyBindingFrame")
  if frame then U.PostHookScript(frame, "OnShow", Repaint) end
  gs.PaintBindingList()
end

-- Re-applied on every attach: the client rebuilds parts of these panels when
-- they are shown, and each skin above is written to be repeated.
function gs.SkinControls(page)
  local frame = U.G(page.frame)
  if not frame then return end
  local found = gs.Collect(frame, 1, { checkboxes = {}, sliders = {},
                                       dropdowns = {}, buttons = {},
                                       scroll = page.scrollButtons })

  -- Named extras a page declares beyond what the walk reaches.
  local extra = { checkboxes = page.checkboxes, dropdowns = page.dropdowns }
  local kind, list
  for kind, list in pairs(extra) do
    if type(list) == "table" then
      local i
      for i = 1, table.getn(list) do table.insert(found[kind], list[i]) end
    end
  end

  local i
  for i = 1, table.getn(found.checkboxes) do gs.SkinCheckbox(found.checkboxes[i]) end
  for i = 1, table.getn(found.sliders) do gs.SkinSlider(found.sliders[i]) end
  for i = 1, table.getn(found.dropdowns) do gs.SkinDropdown(found.dropdowns[i]) end
  for i = 1, table.getn(found.buttons) do
    local name = found.buttons[i]
    -- A page may ask for the WowStyle2 bed instead of the red action face
    -- (Key Bindings). Its own Okay / Cancel / Defaults stay red: they are the
    -- window's actions, not the page's values.
    if (page.buttonStyle == "bed" or page.buttonStyle == "silver") and
       not gs.IsChromeButton(name) then
      local button = U.G(name)
      if page.buttonWidth then
        pcall(button.SetWidth, button, page.buttonWidth)
      end
      gs.ShiftControl(button, page.buttonShift)
      if page.buttonStyle == "silver" then
        gs.DressSilverButton(name)
      else
        gs.DressBedButton(name)
      end
    else
      gs.SkinButton(name)
    end
  end

  -- The binding categories' own bars, after the buttons: a row is read as a
  -- header by its key buttons being hidden. Then the page's own chrome -- the
  -- scrollbar, its two actions and its header strings.
  if page.bindingList then
    gs.WatchBindingList()
    gs.DressBindingChrome(page)
  end
  page.controls = found
end

-- ---------------------------------------------------------------------------
-- Forever chrome
--
-- The window is drawn as WoW Forever draws its own settings window (user
-- request, 2026-09-21), from the art imported into media/Textures/forever-wow/
-- and tokenised as M.foreverWow in core/media.lua. That makes this a fourth
-- visual family beside modern, classic-wow and modern-wow, and like modern-wow
-- it is exempt from the flat/sharp/near-black language for exactly the surface
-- whose point is to reproduce someone else's chrome. Nothing here leaks into
-- another theme: no other module reads M.foreverWow.
--
-- Forever's own stack, from Blizzard_SettingsPanel.xml and
-- Mainline/Blizzard_SettingsPanelTemplates.xml, bottom to top:
--
--   Bg          FlatPanelBackgroundTemplate, inset 7,-18 / -3,3
--   NineSlice   ButtonFrameTemplateNoPortrait metal rim, plus the title
--   InnerFrame  Options_InnerFrame, the recessed plate at TOPLEFT 17,-64
--   CategoryList / Container / buttons
--
-- One deliberate difference. Forever's window is a fixed 920x724 and draws
-- Options_InnerFrame at its authored 886x618 with useAtlasSize. This window is
-- sized to whichever client panel it is hosting (gs.Fit), so the plate is
-- stretched to the inner area instead. It is a large recessed surface with no
-- directional detail, which is why stretching it reads correctly where
-- stretching a corner would not.
--
-- The outer frame follows Forever's ButtonFrameTemplateNoPortrait layout,
-- using the Modern WoW metal frame atlas; see gs.BuildRim.
-- ---------------------------------------------------------------------------

-- Creates one texture on a frame, with its atlas cell applied.
function gs.Cell(parent, layer, path, cell)
  local texture = parent:CreateTexture(nil, layer or "ARTWORK")
  if not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  if cell then
    pcall(texture.SetTexCoord, texture, cell[1], cell[2], cell[3], cell[4])
  end
  return texture
end

-- FlatPanelBackgroundTemplate: two authored bottom corners and three flat
-- fills, every piece tinted with the one panel colour.
function gs.BuildBackground(panel)
  local token = M.foreverWow.panelBackground
  local path = M.foreverWow.texture.panelBg
  local size = token.cornerSize
  local color = token.color

  local bg = CreateFrame("Frame", nil, panel)
  local frame = M.modernWow.gameSettingsFrame
  local body = frame and frame.body or { left = 0, top = 0, right = 0, bottom = 0 }
  bg:SetPoint("TOPLEFT", panel, "TOPLEFT", body.left, -body.top)
  bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -body.right, body.bottom)
  pcall(bg.EnableMouse, bg, false)
  pcall(bg.SetFrameLevel, bg, 0)

  bg.bottomLeft = gs.Cell(bg, "BACKGROUND", path, token.bottomLeft)
  bg.bottomLeft:SetWidth(size)
  bg.bottomLeft:SetHeight(size)
  bg.bottomLeft:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)

  bg.bottomRight = gs.Cell(bg, "BACKGROUND", path, token.bottomRight)
  bg.bottomRight:SetWidth(size)
  bg.bottomRight:SetHeight(size)
  bg.bottomRight:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)

  -- The strip between the corners and everything above them are plain fills.
  bg.bottomEdge = bg:CreateTexture(nil, "BACKGROUND")
  bg.bottomEdge:SetTexture(M.texture.plain)
  bg.bottomEdge:SetPoint("TOPLEFT", bg.bottomLeft, "TOPRIGHT", 0, 0)
  bg.bottomEdge:SetPoint("BOTTOMRIGHT", bg.bottomRight, "BOTTOMLEFT", 0, 0)

  bg.top = bg:CreateTexture(nil, "BACKGROUND")
  bg.top:SetTexture(M.texture.plain)
  bg.top:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
  bg.top:SetPoint("BOTTOMRIGHT", bg.bottomRight, "TOPRIGHT", 0, 0)

  local i
  local pieces = { bg.bottomLeft, bg.bottomRight, bg.bottomEdge, bg.top }
  for i = 1, table.getn(pieces) do
    pcall(pieces[i].SetVertexColor, pieces[i], color[1], color[2], color[3], color[4])
  end

  panel.bg = bg
  return bg
end

-- Forever's ButtonFrameTemplateNoPortrait is an eight-piece rim: four corners
-- sit proud of the frame and the straight rails stretch between those corners.
-- This keeps that construction exactly, but reads its pieces from modern-wow's
-- ui/frame metal atlas instead of the Forever source art.
function gs.BuildRim(panel)
  local rim = CreateFrame("Frame", nil, panel)
  rim:SetAllPoints(panel)
  pcall(rim.EnableMouse, rim, false)
  pcall(rim.SetFrameLevel, rim, gs.Number(panel, "GetFrameLevel") + 6)
  panel.rim = rim

  local token = M.modernWow.gameSettingsFrame
  if not token then return rim end

  local function Corner(spec, point, x, y)
    local piece = gs.Cell(rim, "OVERLAY", token.corners, spec.texCoord)
    if not piece then return nil end
    piece:SetWidth(spec.width)
    piece:SetHeight(spec.height)
    piece:SetPoint(point, panel, point, x, y)
    return piece
  end

  local offset = token.offset
  local tl = Corner(token.topLeft, "TOPLEFT", offset.left, offset.top)
  local tr = Corner(token.topRight, "TOPRIGHT", offset.right, offset.top)
  local bl = Corner(token.bottomLeft, "BOTTOMLEFT", offset.left, offset.bottom)
  local br = Corner(token.bottomRight, "BOTTOMRIGHT", offset.right, offset.bottom)

  local function Rail(path, spec)
    return gs.Cell(rim, "OVERLAY", path, spec.texCoord)
  end
  local top = Rail(token.horizontal, token.edgeTop)
  if top and tl and tr then
    top:SetHeight(token.edgeTop.height)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
  end
  local bottom = Rail(token.horizontal, token.edgeBottom)
  if bottom and bl and br then
    bottom:SetHeight(token.edgeBottom.height)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    bottom:SetPoint("TOPRIGHT", br, "TOPLEFT", 0, 0)
  end
  local left = Rail(token.vertical, token.edgeLeft)
  if left and tl and bl then
    left:SetWidth(token.edgeLeft.width)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
  end
  local right = Rail(token.vertical, token.edgeRight)
  if right and tr and br then
    right:SetWidth(token.edgeRight.width)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
  end

  return rim
end

-- The window's and the pages' rectangular buttons (Close, Okay, Cancel,
-- Defaults, the Key Bindings rows) wear Blizzard's HD 128RedButton face,
-- modern-wow/buttons/128RedButton.tga, by user request (2026-09-22): Forever's
-- own UIPanelButtonTemplate faces are the old 128x32 UI-Panel-Button files,
-- whose 22-row face drew soft at this size. The cuts are the measured
-- M.modernWow.button128Red three-slice -- the same cells the Modern WoW
-- windows' action buttons use: a 24-texel cap each side kept at its aspect
-- and only the middle stretched, normal / hover / disabled. It is drawn here
-- rather than through U.ModernWowRedButtonFace because that builder is gated
-- to the Modern WoW theme, and this window looks the same under every theme.
-- The atlas has no pressed cell, so a held button is its hover cell a step
-- darker. Every piece is an addon texture; the button's own state slots stay
-- empty (gs.SkinButton clears them). The label is gold, white while hovered,
-- grey while disabled.
function gs.DressButton(button, height)
  local token = M.modernWow.button128Red
  local path = M.modernWow.texture.button128Red
  if not button or not token or not path then return false end

  local face = button.uuiForeverFace
  if not face then
    face = {}
    local function Piece()
      local ok, texture = pcall(button.CreateTexture, button, nil, "BACKGROUND")
      if not ok or not texture then return nil end
      pcall(texture.SetTexture, texture, path)
      return texture
    end
    face.left, face.middle, face.right = Piece(), Piece(), Piece()
    if not face.left or not face.middle or not face.right then return false end

    -- The hover bloom, drawn ADD over the resting face exactly as the close
    -- button's highlight cell is (gs.BuildCloseX), rather than swapping the
    -- three-slice to the atlas's hover row (user request, 2026-09-22). One
    -- stretched piece: the cell is a soft glow with no bevel to protect.
    local glow = Piece()
    if glow then
      pcall(glow.SetDrawLayer, glow, "OVERLAY")
      pcall(glow.SetBlendMode, glow, "ADD")
      local cell = token.glow
      if cell then
        pcall(glow.SetTexCoord, glow, cell[1] / token.atlasWidth,
              cell[2] / token.atlasWidth, cell[3] / token.atlasHeight,
              cell[4] / token.atlasHeight)
      end
      local margin = token.glowMargin or 0
      pcall(glow.SetPoint, glow, "TOPLEFT", button, "TOPLEFT", -margin, margin)
      pcall(glow.SetPoint, glow, "BOTTOMRIGHT", button, "BOTTOMRIGHT",
            margin, -margin)
      local shade = token.glowIntensity or 1
      pcall(glow.SetVertexColor, glow, shade, shade, shade, 1)
      pcall(glow.Hide, glow)
      face.glow = glow
    end

    button.uuiForeverFace = face
    U.SetBackdropShown(button, false)

    U.PostHookScript(button, "OnEnter", function()
      face.over = true
      gs.PaintButton(button)
    end)
    U.PostHookScript(button, "OnLeave", function()
      face.over = false
      face.down = false
      gs.PaintButton(button)
    end)
    U.PostHookScript(button, "OnMouseDown", function()
      face.down = true
      gs.PaintButton(button)
    end)
    U.PostHookScript(button, "OnMouseUp", function()
      face.down = false
      gs.PaintButton(button)
    end)
    U.PostHookScript(button, "OnShow", function() gs.PaintButton(button) end)
  end

  -- The caps keep the cell's aspect at the button's own height.
  local drawn = tonumber(height) or gs.Number(button, "GetHeight") or 22
  local capWidth = drawn * token.cap / token.cellHeight
  pcall(function()
    face.left:ClearAllPoints()
    face.left:SetWidth(capWidth)
    face.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    face.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    face.right:ClearAllPoints()
    face.right:SetWidth(capWidth)
    face.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    face.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    face.middle:ClearAllPoints()
    face.middle:SetPoint("TOPLEFT", face.left, "TOPRIGHT", 0, 0)
    face.middle:SetPoint("BOTTOMRIGHT", face.right, "BOTTOMLEFT", 0, 0)
  end)

  face.painted = nil
  gs.PaintButton(button)
  return true
end

-- One piece of the three-slice: texels left..right of the row starting at top.
function gs.ButtonSlice(texture, token, left, right, top)
  pcall(texture.SetTexCoord, texture,
        left / token.atlasWidth, right / token.atlasWidth,
        top / token.atlasHeight, (top + token.cellHeight) / token.atlasHeight)
end

function gs.PaintButton(button)
  local face = button and button.uuiForeverFace
  local token = M.modernWow.button128Red
  local colors = M.foreverWow.control.button
  if not face or not token then return end

  -- IsEnabled returns 1 / 0 on this client, not a boolean.
  local enabled = gs.Read(button, "IsEnabled")
  local disabled = enabled == 0 or enabled == false
  -- Three faces and one bloom (user requests, 2026-09-22): the resting row at
  -- rest, the atlas's darker row while the button is held, its grey row while
  -- disabled, and the glow over the resting face while hovered. A held button
  -- drops the glow -- it is showing the pressed face instead.
  local wanted = "normal"
  if disabled then
    wanted = "disabled"
  elseif face.down then
    wanted = "pressed"
  end
  if face.glow then
    if face.over and not face.down and not disabled then
      pcall(face.glow.Show, face.glow)
    else
      pcall(face.glow.Hide, face.glow)
    end
  end

  if face.painted ~= wanted then
    face.painted = wanted
    local cell = token[wanted] or token.normal
    local cap, bar = token.cap, token.barWidth
    gs.ButtonSlice(face.left, token, cell.capLeft, cell.capLeft + cap, cell.capTop)
    gs.ButtonSlice(face.middle, token, cap, bar - cap, cell.barTop)
    gs.ButtonSlice(face.right, token, bar - cap, bar, cell.barTop)
  end

  -- No shade on top: the press is the pressed row itself now, and darkening
  -- it again over-sold it.
  local pieces = { face.left, face.middle, face.right }
  local i
  for i = 1, 3 do
    pcall(pieces[i].SetVertexColor, pieces[i], 1, 1, 1, 1)
  end

  local color = colors.textColor
  if disabled then
    color = colors.disabledTextColor
  elseif face.over then
    color = colors.hoverTextColor
  end
  if button.label then
    U.SetStockFont(button.label, M.fontSize.normal, color)
  end
end

-- Unreal UI pages apply their settings through their existing callbacks. This
-- pair supplies the persistent Game Settings footer action row: both actions
-- leave the unified window, while native categories continue to use their own
-- client buttons and semantics.
function gs.BuildIntegratedActions()
  if gs.integratedOkay or not gs.panel then return end
  local panel = M.foreverWow.panel
  local function Label(globalName, fallback)
    local value = U.G(globalName)
    return type(value) == "string" and value or fallback
  end
  local function Button(name, text)
    local button = U.CreateButton(gs.panel, {
      name = name,
      text = text,
      width = panel.buttonWidth,
      height = panel.buttonHeight,
      onClick = function() gs.Close() end,
    })
    gs.DressButton(button, panel.buttonHeight)
    local level = gs.Number(gs.panel, "GetFrameLevel") or 1
    gs.Relevel(button, level + gs.ACTION_LEVEL, 0)
    button:Hide()
    return button
  end

  gs.integratedCancel = Button("UnrealUIGameSettingsUICancel",
                               Label("CANCEL", "Cancel"))
  gs.integratedOkay = Button("UnrealUIGameSettingsUIOkay",
                             Label("OKAY", "Okay"))
  if gs.integratedCancel then
    gs.integratedCancel:SetPoint("BOTTOMRIGHT", gs.panel, "BOTTOMRIGHT",
                                 -panel.buttonInset.right,
                                 panel.buttonInset.bottom)
  end
  if gs.integratedOkay and gs.integratedCancel then
    gs.integratedOkay:SetPoint("RIGHT", gs.integratedCancel, "LEFT",
                               -panel.buttonGap, 0)
  end
end

function gs.SetIntegratedActionsShown(shown)
  local buttons = { gs.integratedOkay, gs.integratedCancel }
  local level = gs.panel and (gs.Number(gs.panel, "GetFrameLevel") or 1) or 1
  local i
  for i = 1, 2 do
    local button = buttons[i]
    if button then
      if shown then
        gs.Relevel(button, level + gs.ACTION_LEVEL, 0)
        pcall(button.Show, button)
      else
        pcall(button.Hide, button)
      end
    end
  end
end

-- Options_InnerFrame, the recessed plate the list and the page sit on. Its
-- authored height (618) is drawn 1:1, exactly as Forever draws it with
-- useAtlasSize; its authored width (886) is not, because the window is 30%
-- narrower than Forever's (user request, 2026-09-22).
--
-- Its category list is narrower than the art was authored for too (user
-- request, 2026-09-22), so the SEAM the art prints between the list and the
-- page has to move with it.
--
-- The plate is therefore a horizontal five-slice on a plain anchor frame, from
-- M.foreverWow.options.innerSlice: the rim and the rounded corners at each end
-- are drawn 1:1, the seam block is drawn 1:1 at the category list's own right
-- edge, and the two flat fields either side of it -- the list's and the page's
-- -- are squeezed to whatever is left. Squeezing the whole member instead
-- drags the seam into the list, which is the same defect that made stretching
-- it for a wider page unacceptable.
--
-- panel.plate stays the anchor everything else hangs off (the sidebar's
-- bottom, the page box's bottom-right), so it is a Frame now rather than the
-- texture itself.
function gs.BuildInnerPlate(panel)
  local options = M.foreverWow.options
  local size = options.innerSize
  local slice = options.innerSlice
  local cell = options.innerFrame
  local sheet = options.sheet

  local plate = CreateFrame("Frame", nil, panel)
  if not plate then return nil end
  -- Sized from the WINDOW, both ways: the plate is what the page box, the
  -- category list and the scrollbar all hang off, so leaving it at the art's
  -- authored height left them 154 units below the shortened window (reported
  -- in game 2026-09-22 with a screenshot: the rim was short, the list ran on
  -- past it).
  plate:SetWidth(gs.WIDTH - 2 * gs.PLATE_SIDE)
  plate:SetHeight(gs.HEIGHT - gs.PLATE_TOP - gs.PLATE_BOTTOM)
  plate:SetPoint("TOPLEFT", panel, "TOPLEFT", gs.PLATE_SIDE, -gs.PLATE_TOP)
  pcall(plate.EnableMouse, plate, false)
  panel.plate = plate

  local width = gs.Number(plate, "GetWidth") or size.width
  local height = gs.Number(plate, "GetHeight") or size.height
  -- Where the seam is DRAWN: the category list's own right edge, in the
  -- plate's coordinates. The list is anchored to the panel, so its inset is
  -- taken off the plate's.
  local seam = (M.foreverWow.panel.categoryInset.left - gs.PLATE_SIDE) +
               gs.SIDEBAR_WIDTH
  local list = seam - slice.rim
  local field = width - seam - slice.seamKeep - slice.keepRight
  local band = height - slice.top - slice.bottom

  if list < 1 or field < 1 or band < 1 then
    -- No room for one of the squeezed fields: the member is drawn whole and
    -- the seam lands wherever the stretch puts it. Not reachable at the
    -- current sizes, kept so a future one cannot leave the plate undrawn.
    local whole = gs.Cell(plate, "BACKGROUND", M.foreverWow.texture.options, cell)
    if whole then whole:SetAllPoints(plate) end
    return plate
  end

  -- Texel cuts on the sheet. cell[1] / cell[3] are the member's own left and
  -- top edges, so every cut is measured from them. Each entry is
  -- { from, to, drawn offset, drawn size }.
  local x0 = cell[1] * sheet
  local y0 = cell[3] * sheet
  local function CutX(texel)
    return (x0 + texel) / sheet
  end
  local function CutY(texel)
    return (y0 + texel) / sheet
  end
  local columns = {
    { CutX(0), CutX(slice.rim), 0, slice.rim },
    { CutX(slice.rim), CutX(slice.seam), slice.rim, list },
    { CutX(slice.seam), CutX(slice.seam + slice.seamKeep), seam, slice.seamKeep },
    { CutX(slice.seam + slice.seamKeep), CutX(size.width - slice.keepRight),
      seam + slice.seamKeep, field },
    { CutX(size.width - slice.keepRight), CutX(size.width),
      width - slice.keepRight, slice.keepRight },
  }
  local rows = {
    { CutY(0), CutY(slice.top), 0, slice.top },
    { CutY(slice.top), CutY(size.height - slice.bottom), slice.top, band },
    { CutY(size.height - slice.bottom), CutY(size.height),
      height - slice.bottom, slice.bottom },
  }

  -- The plate's art is drawn as authored: the background's alpha is the
  -- surround's alone (user request, 2026-09-22), so the content keeps an
  -- opaque bed to read against.
  plate.pieces = {}
  local i, j
  for i = 1, 5 do
    local column = columns[i]
    for j = 1, 3 do
      local row = rows[j]
      local texture = gs.Cell(plate, "BACKGROUND", M.foreverWow.texture.options,
                              { column[1], column[2], row[1], row[2] })
      if texture then
        texture:SetWidth(column[4])
        texture:SetHeight(row[4])
        texture:SetPoint("TOPLEFT", plate, "TOPLEFT", column[3], -row[3])
        table.insert(plate.pieces, texture)
      end
    end
  end

  return plate
end

function gs.Build()
  local panel = M.foreverWow.panel

  -- A bare frame: every surface on it is Forever art, so there is no flat
  -- backdrop to create and then paint over.
  gs.panel = CreateFrame("Frame", "UnrealUIGameSettings", UIParent)
  gs.panel:SetWidth(gs.WIDTH)
  gs.panel:SetHeight(gs.HEIGHT)
  gs.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  pcall(gs.panel.EnableMouse, gs.panel, true)
  pcall(gs.panel.SetFrameStrata, gs.panel, "HIGH")
  U.MakeWindowDraggable("gamesettings", gs.panel,
                        { headerHeight = gs.HEADER_HEIGHT })

  gs.BuildBackground(gs.panel)
  gs.BuildInnerPlate(gs.panel)
  gs.BuildRim(gs.panel)

  -- Deliberately NOT in UISpecialFrames, unlike the /uui window.
  --
  -- Reported in game 2026-09-21: clicking a row in the list closed this window
  -- and left the Escape menu on screen. Switching pages hides the outgoing
  -- client panel, and hiding one of these panels puts the client back on its
  -- game menu -- which is the client's own "back out of options" path, and that
  -- path closes every window listed in UISpecialFrames. Being listed there is
  -- what let the client take this window down mid-switch, so it is not listed.
  --
  -- Escape is handled instead by gs.WatchPanel and gs.GuardMenu, which close
  -- this window and keep the game menu down. gs.switching below covers the
  -- rest of the same chain.
  gs.panel:SetScript("OnHide", function()
    if gs.switching then return end
    gs.Detach()
  end)

  -- The title sits on the metal rim, centred, exactly as Forever anchors
  -- NineSlice.Text. Warm gold, which is this family's heading colour.
  -- On the rim frame: the housing is a child frame above the panel's own
  -- regions, so a title parented to the panel would be drawn under the metal
  -- band it sits on.
  gs.panel.title = U.CreateLabel(gs.panel.rim or gs.panel, {
    size = M.fontSize.large,
    color = M.color.accent,
    inherits = "GameFontNormal",
    justify = "CENTER",
  })
  if gs.panel.title then
    local frame = M.modernWow.gameSettingsFrame
    local titleY = -gs.HEADER_HEIGHT / 2
    if frame and frame.offset and frame.edgeTop then
      titleY = frame.offset.top - frame.edgeTop.height / 2
    end
    titleY = titleY + (frame and frame.titleOffsetY or 0)
    gs.panel.title:SetPoint("CENTER", gs.panel, "TOP", 0, titleY)
    gs.panel.title:SetText(U.L("GAMESETTINGS_TITLE"))
    if gs.panel.rim then
      pcall(gs.panel.title.SetDrawLayer, gs.panel.title, "OVERLAY", 7)
    end
  end

  -- The category list is a plain anchor: its rows carry their own art and the
  -- recessed plate behind them is the window's, so it needs no fill of its own.
  gs.sidebar = CreateFrame("Frame", "UnrealUIGameSettingsSidebar", gs.panel)
  gs.sidebar:SetWidth(gs.SIDEBAR_WIDTH)
  gs.sidebar:SetPoint("TOPLEFT", gs.panel, "TOPLEFT",
                      panel.categoryInset.left, -(gs.PLATE_TOP + gs.LIST_DROP))
  gs.sidebar:SetPoint("BOTTOMLEFT", gs.panel.plate, "BOTTOMLEFT", 1, 12)
  pcall(gs.sidebar.EnableMouse, gs.sidebar, false)

  gs.BuildListHeader()
  gs.BuildSidebarScrollbar()
  if type(U.CreateWheelCatcher) == "function" then
    gs.sidebarWheel = U.CreateWheelCatcher(gs.sidebar, function(delta)
      local maximum = gs.sidebarMaximum or 0
      local offset = math.max(0, math.min(maximum,
        (gs.sidebarOffset or 0) - delta * 3))
      if offset == gs.sidebarOffset then return end
      gs.sidebarOffset = offset
      gs.RenderList()
    end)
  end

  gs.content = CreateFrame("Frame", "UnrealUIGameSettingsContent", gs.panel)
  gs.content:SetPoint("TOPLEFT", gs.sidebar, "TOPRIGHT", panel.containerGap, 0)
  gs.content:SetPoint("BOTTOMRIGHT", gs.panel.plate, "BOTTOMRIGHT", -6, 12)

  -- Options_HorizontalDivider under the page title, the rule Forever draws
  -- across the top of its settings list. Stretched, never tiled: the member is
  -- 630x1, so there is nothing in it to repeat.
  gs.divider = gs.Cell(gs.content, "ARTWORK", M.foreverWow.texture.options,
                       M.foreverWow.options.divider)
  if gs.divider then
    gs.divider:SetHeight(M.foreverWow.options.dividerHeight)
    gs.divider:SetPoint("TOPLEFT", gs.content, "TOPLEFT", 0,
                        -gs.CONTENT_HEADER)
    gs.divider:SetPoint("TOPRIGHT", gs.content, "TOPRIGHT", 0,
                        -gs.CONTENT_HEADER)
  end

  -- The open page's name, above that rule, where Forever puts
  -- SettingsList.Header.Title.
  gs.pageTitle = U.CreateLabel(gs.content, {
    size = M.fontSize.large,
    color = M.color.text,
    inherits = "GameFontNormalLarge",
    justify = "LEFT",
  })
  if gs.pageTitle then
    -- Centred on the band rather than dropped Forever's 22 from its top, so
    -- it stays put whatever gs.CONTENT_HEADER becomes.
    gs.pageTitle:SetPoint("LEFT", gs.content, "TOPLEFT",
                          panel.listTitleInset.x, -gs.CONTENT_HEADER / 2)
  end

  -- Forever's SettingsPanel.Container holds the canvas the selected category's
  -- frame is moved into. This is that frame: separate from the content anchor
  -- so a hosted panel takes its strata and level from something narrower than
  -- the whole window, and mouse-transparent, because the hosted panel owns
  -- every click inside it. It starts below the header rule, as the list does.
  gs.host = CreateFrame("Frame", "UnrealUIGameSettingsCanvas", gs.content)
  gs.host:SetPoint("TOPLEFT", gs.content, "TOPLEFT", 0,
                   -(gs.CONTENT_HEADER + 4))
  gs.host:SetPoint("BOTTOMRIGHT", gs.content, "BOTTOMRIGHT", 0, 0)
  pcall(gs.host.EnableMouse, gs.host, false)

  gs.message = U.CreateLabel(gs.content, {
    size = M.fontSize.normal,
    color = M.color.textDim,
    inherits = "GameFontNormal",
    justify = "LEFT",
  })
  if gs.message then
    gs.message:SetPoint("TOPLEFT", gs.host, "TOPLEFT", 8, -8)
    gs.message:Hide()
  end

  -- No Close button at the bottom right (user request, 2026-09-22). The red X
  -- in the header is the window's closer; the page's own Okay and Cancel take
  -- the bottom-right corner it used to hold (L.PlaceChrome).
  gs.BuildCloseX(gs.panel)
  gs.BuildIntegratedActions()

  gs.panel:Hide()
end

-- UIPanelCloseButtonDefaultAnchors, the red X ButtonFrameTemplate puts at the
-- window's TOPRIGHT -2,1 on the metal rim. Its four RedButton cells are the
-- addon's own textures swapped by state, not the button's state slots given a
-- path (widgets.setthumbtexture_path_shares_one_thumb). Above the rim, and so
-- above the header drag handle (windowdrag HANDLE_LEVEL_OFFSET is 1), which
-- would otherwise take its clicks.
function gs.BuildCloseX(panel)
  local token = M.foreverWow.control.close
  local cells = M.modernWow.redButtonCell
  local path = M.modernWow.texture.redButton
  if not cells or not path then return end
  local ok, button = pcall(CreateFrame, "Button", "UnrealUIGameSettingsCloseX", panel)
  if not ok or not button then return end
  button:SetWidth(token.size)
  button:SetHeight(token.size)
  -- Forever's horizontal inset plus the requested local adjustment.
  button:SetPoint("RIGHT", panel, "TOPRIGHT", token.x + gs.CLOSE_NUDGE.x,
                  -gs.HEADER_HEIGHT / 2 + gs.CLOSE_NUDGE.y)
  pcall(button.EnableMouse, button, true)
  if panel.rim then
    pcall(button.SetFrameLevel, button, gs.Number(panel.rim, "GetFrameLevel") + 2)
  end

  local function Piece(layer)
    local made, texture = pcall(button.CreateTexture, button, nil, layer)
    if not made or not texture then return nil end
    pcall(texture.SetTexture, texture, path)
    pcall(texture.SetAllPoints, texture, button)
    return texture
  end
  local face, glow = Piece("ARTWORK"), Piece("OVERLAY")
  if not face then return end
  if glow then
    pcall(glow.SetTexCoord, glow, cells.highlight[1], cells.highlight[2],
          cells.highlight[3], cells.highlight[4])
    pcall(glow.SetBlendMode, glow, "ADD")
    pcall(glow.Hide, glow)
  end

  local state = { over = false, down = false }
  local function Paint()
    local cell = state.down and cells.closePushed or cells.closeNormal
    pcall(face.SetTexCoord, face, cell[1], cell[2], cell[3], cell[4])
    if glow then
      if state.over then pcall(glow.Show, glow) else pcall(glow.Hide, glow) end
    end
  end
  button:SetScript("OnEnter", function() state.over = true; Paint() end)
  button:SetScript("OnLeave", function() state.over = false; state.down = false; Paint() end)
  button:SetScript("OnMouseDown", function() state.down = true; Paint() end)
  button:SetScript("OnMouseUp", function() state.down = false; Paint() end)
  button:SetScript("OnClick", function() gs.Close() end)
  Paint()
  panel.closeX = button
end

-- id selects the page to open on; omitted keeps the last one, or Video.
function gs.Open(id)
  if not gs.panel then gs.Build() end

  -- Always drawn at scale 1 (user decision, 2026-09-21). Scaling the window
  -- down to Forever's on-screen size was tried and reverted: the client's own
  -- controls, reparented into it, kept their full size inside the shrunken
  -- window (knowledge.json / widgets.reparented_native_widget_ignores_ancestor_scale).
  pcall(gs.panel.SetScale, gs.panel, 1)
  gs.panel:Show()
  if gs.list and type(gs.list.ShowSearch) == "function" then
    gs.list.ShowSearch()
  end
  gs.RenderList()
  gs.SelectPage(id or (gs.active and gs.active.id) or gs.PAGES[1].id)
end

function gs.Close()
  if not gs.panel or gs.closing then return end
  -- Closing this window never lands on the game menu (user request,
  -- 2026-09-22). Handing a hosted panel back to the client runs its own
  -- "back out of options" OnHide, which re-shows GameMenuFrame; the guard in
  -- gs.GuardMenu turns that down until the next tick.
  gs.suppressMenu = true
  U.DeferOnce("gamesettings:suppressmenu", function() gs.suppressMenu = nil end)
  if gs.list and type(gs.list.HideSearch) == "function" then
    gs.list.HideSearch()
  end
  -- Detaching re-shows the menu from inside this call (the panel's OnHide),
  -- and gs.GuardMenu would close again; the flag keeps that from re-entering.
  gs.closing = true
  pcall(gs.Detach)
  pcall(gs.panel.Hide, gs.panel)
  gs.closing = false
end

-- Escape while this window is open closes it and never opens the game menu
-- (user request, 2026-09-22). The window is not in UISpecialFrames (see
-- gs.Build), so the client's Escape handler either hides the hosted panel --
-- gs.WatchPanel closes the window, then the panel's OnHide re-shows the menu --
-- or, finding nothing of its own to close, shows the menu directly. Both
-- arrive here, from the menu's OnShow: a menu shown over the open window, or
-- in the same tick the window closed, is hidden again and the window closed.
-- A page switch is left alone; gs.SelectPage deals with the menu itself.
function gs.GuardMenu(menu)
  if gs.switching or not gs.panel then return end
  local open = gs.Read(gs.panel, "IsShown")
  if not open and not gs.suppressMenu then return end
  gs.HideMenu(menu)
  if open and not gs.closing then gs.Close() end
end

-- ---------------------------------------------------------------------------
-- Escape menu
--
-- The four menu rows stay where they are and keep their own labels; each one
-- opens this window on its own page instead of the client's separate panel.
-- modules/gamemenu.lua is untouched: it covers these buttons with its own
-- artwork and leaves the native button as the click target, which is exactly
-- the handler replaced here.
-- ---------------------------------------------------------------------------
-- Closes the game menu the way the client does. HideUIPanel keeps the client's
-- own panel bookkeeping consistent; a bare Hide leaves it thinking the menu is
-- still up, which is what modules/gamemenu.lua falls back to when the function
-- is missing.
function gs.HideMenu(menu)
  local hide = U.G("HideUIPanel")
  if type(hide) == "function" then
    local ok = pcall(hide, menu)
    if ok then return end
  end
  pcall(menu.Hide, menu)
end

-- Self-healing: the handler is re-installed whenever the button is not already
-- carrying ours, and HookShow runs this on every menu show. The client rebuilds
-- and re-scripts its own menu rows (knowledge.json /
-- frames.stock_singletons_structure_nonvanilla), so a reroute installed once at
-- load cannot be assumed to still be there.
function gs.HookMenu()
  if gs.rerouteOff then return end

  local i
  for i = 1, table.getn(gs.PAGES) do
    local page = gs.PAGES[i]
    local button = U.G(page.menuButton)
    if button and type(button.SetScript) == "function" then
      local current
      if type(button.GetScript) == "function" then
        local ok, value = pcall(button.GetScript, button, "OnClick")
        if ok then current = value end
      end

      if current ~= page.handler then
        -- Whatever was there before ours is the client's, and is what
        -- RestoreMenu puts back. Only captured the first time, so a second
        -- pass cannot record our own handler as the original.
        if gs.hooked[page.menuButton] == nil then
          gs.hooked[page.menuButton] = current or true
        end

        local id = page.id
        page.handler = function()
          local menu = U.G("GameMenuFrame")
          if menu then gs.HideMenu(menu) end
          gs.Open(id)
        end
        local ok = pcall(button.SetScript, button, "OnClick", page.handler)
        if not ok then page.handler = nil end
      end
    end
  end
end

-- Puts the client's own handlers back, for a future settings toggle and so the
-- reroute is never a one-way change.
function gs.RestoreMenu()
  -- HookMenu runs again on every menu show, so the reroute has to be switched
  -- off as well as undone or it would reinstall itself immediately.
  gs.rerouteOff = true

  local name, previous
  for name, previous in pairs(gs.hooked) do
    local button = U.G(name)
    if button and type(button.SetScript) == "function" then
      pcall(button.SetScript, button, "OnClick",
            type(previous) == "function" and previous or nil)
    end
  end
  gs.hooked = {}

  -- Clearing the remembered handlers is what stops HookMenu putting the
  -- reroute straight back on the next menu show.
  local i
  for i = 1, table.getn(gs.PAGES) do gs.PAGES[i].handler = nil end
end

-- The client can add and rebuild its own menu rows (knowledge.json /
-- frames.stock_singletons_structure_nonvanilla: GameMenuFrame does not present
-- the hierarchy upstream assumes here), so the reroute is retried every time
-- the menu opens rather than assumed to have worked at load. HookMenu is
-- idempotent, so this is a no-op once all four are rerouted.
function gs.HookShow()
  local menu = U.G("GameMenuFrame")
  if not menu or gs.showHooked then return end
  if type(menu.SetScript) ~= "function" then return end

  local previous
  if type(menu.GetScript) == "function" then
    local ok, value = pcall(menu.GetScript, menu, "OnShow")
    if ok then previous = value end
  end

  local ok = pcall(menu.SetScript, menu, "OnShow", function()
    if type(previous) == "function" then pcall(previous) end
    gs.HookMenu()
    gs.GuardMenu(menu)
  end)
  if ok then gs.showHooked = true end
end

function G:OnEnable()
  gs.HookMenu()
  gs.HookShow()
end

-- /uui gamesettings, and the entry point for anything else that wants the
-- window (a future settings row, a binding).
function U.OpenGameSettings(id)
  gs.Open(id)
end

function U.CloseGameSettings()
  gs.Close()
end

-- ---------------------------------------------------------------------------
-- /uui gamedump -- chrome inventory of the hosted page
--
-- gs.StripChrome hides the attached panel's OWN texture regions and clears its
-- backdrop, yet the Video page still draws a border and background inside this
-- window (reported in game, 2026-09-21). So that chrome belongs to something
-- else -- a child frame's backdrop or regions -- and which one is not on record
-- (knowledge.json / frames.settings_panels_windowed_and_groupable names the
-- Video section frames but not their art). This is the focused read that names
-- it before anything is changed.
--
-- A diagnostic, not a production path: it runs only on the command, reads only
-- (names, types, sizes, backdrop presence, texture paths and layers), walks at
-- most gs.DUMP_DEPTH levels below the page and gs.DUMP_KIDS children per frame,
-- and writes to UnrealUIDiagDB.gameSettingsChrome.
-- ---------------------------------------------------------------------------
gs.DUMP_DEPTH = 3
gs.DUMP_KIDS = 40

function gs.DumpRegions(frame)
  local out = {}
  if type(frame.GetRegions) ~= "function" then return out end
  local ok, regions = pcall(function() return { frame:GetRegions() } end)
  if not ok or not regions then return out end

  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local entry = {
      type = gs.Read(region, "GetObjectType"),
      name = gs.Read(region, "GetName"),
      shown = gs.Read(region, "IsShown") and true or false,
      w = gs.Number(region, "GetWidth"),
      h = gs.Number(region, "GetHeight"),
    }
    if entry.type == "Texture" then
      entry.texture = gs.Read(region, "GetTexture")
      if type(region.GetDrawLayer) == "function" then
        local okLayer, layer, sub = pcall(region.GetDrawLayer, region)
        if okLayer then entry.layer = layer; entry.sub = sub end
      end
      entry.alpha = gs.Number(region, "GetAlpha")
    elseif entry.type == "FontString" then
      entry.text = gs.Read(region, "GetText")
    end
    table.insert(out, entry)
  end
  return out
end

function gs.DumpFrame(frame, depth)
  local entry = {
    name = gs.Read(frame, "GetName"),
    type = gs.Read(frame, "GetObjectType"),
    shown = gs.Read(frame, "IsShown") and true or false,
    w = gs.Number(frame, "GetWidth"),
    h = gs.Number(frame, "GetHeight"),
    level = gs.Number(frame, "GetFrameLevel"),
    regions = gs.DumpRegions(frame),
  }

  -- Presence and the file names only: a backdrop table is the client's, and
  -- copying it whole into SavedVariables is not needed to name its owner.
  local backdrop = gs.Read(frame, "GetBackdrop")
  if type(backdrop) == "table" then
    entry.backdrop = { bgFile = backdrop.bgFile, edgeFile = backdrop.edgeFile,
                       edgeSize = backdrop.edgeSize }
  elseif backdrop ~= nil then
    entry.backdrop = tostring(backdrop)
  end

  if depth < gs.DUMP_DEPTH and type(frame.GetChildren) == "function" then
    local ok, kids = pcall(function() return { frame:GetChildren() } end)
    if ok and kids then
      entry.children = {}
      local i
      for i = 1, math.min(table.getn(kids), gs.DUMP_KIDS) do
        table.insert(entry.children, gs.DumpFrame(kids[i], depth + 1))
      end
      entry.childCount = table.getn(kids)
    end
  end
  return entry
end

function U.DumpGameSettings(id)
  gs.Open(id or "video")
  local page = gs.active
  local frame = page and U.G(page.frame)
  if not frame then
    U.Print("gamedump: no page attached.")
    return
  end

  local data = {
    page = page.id,
    stripped = table.getn(gs.stripped[page.id] or {}),
    tree = gs.DumpFrame(frame, 0),
  }

  -- A canvas page is placed rather than rebuilt, so what it is worth reading
  -- back is the placement: the box, the panel's live rect and scale, what
  -- gs.Overhang measured, and what gs.Fit made of it. Added 2026-09-22, when
  -- the Key Bindings page drew across the category list and past the window.
  if page.layout ~= "list" then
    local function Rect(object)
      if not object then return nil end
      return {
        left = gs.Number(object, "GetLeft"),
        right = gs.Number(object, "GetRight"),
        top = gs.Number(object, "GetTop"),
        bottom = gs.Number(object, "GetBottom"),
        width = gs.Number(object, "GetWidth"),
        height = gs.Number(object, "GetHeight"),
        scale = gs.Number(object, "GetScale"),
      }
    end
    local point, relative, relativePoint, x, y = U.GetFramePoint(frame, 1)
    data.canvas = {
      align = page.align,
      panel = Rect(frame),
      host = Rect(gs.host),
      overhang = gs.Overhang(page, frame),
      fitOffsetX = page.fitOffsetX,
      fitOffsetY = page.fitOffsetY,
      fitPadRight = page.fitPadRight,
      anchor = point and { point = point, relative = gs.Read(relative, "GetName"),
                           relativePoint = relativePoint, x = x, y = y } or nil,
      points = gs.Number(frame, "GetNumPoints"),
    }
    -- What the control walk actually reached on this page, and what each
    -- button ended up wearing: a binding the walk never found keeps the
    -- client's own face and its own width.
    local found = page.controls
    if found and found.buttons then
      local buttons = {}
      local i
      for i = 1, table.getn(found.buttons) do
        local name = found.buttons[i]
        local button = U.G(name)
        table.insert(buttons, {
          name = name,
          width = gs.Number(button, "GetWidth"),
          height = gs.Number(button, "GetHeight"),
          left = gs.Number(button, "GetLeft"),
          right = gs.Number(button, "GetRight"),
          silver = (button and button.uuiSilver) and true or false,
          bed = (button and button.uuiForeverBed) and true or false,
          shifted = (button and button.uuiForeverShift) and true or false,
        })
      end
      data.canvas.buttons = buttons
      data.canvas.checkboxes = found.checkboxes
      data.canvas.sliders = found.sliders
    end
  end

  -- The Forever list, when this page is one: what discovery found and what
  -- the scroll frame and bar ended up holding.
  local list = gs.list
  if list and page.layout == "list" and list.model[page.id] then
    local sections = {}
    local i, j
    for i = 1, table.getn(list.model[page.id]) do
      local section = list.model[page.id][i]
      local names = {}
      for j = 1, table.getn(section.controls) do
        local control = section.controls[j]
        table.insert(names, control.kind .. ":" .. control.name ..
                     (gs.Read(U.G(control.name), "IsShown") and "" or " (hidden)"))
      end
      table.insert(sections, { name = section.name, title = section.title,
                               container = section.container, controls = names })
    end
    local low, high
    if list.bar and type(list.bar.GetMinMaxValues) == "function" then
      local ok, a, b = pcall(list.bar.GetMinMaxValues, list.bar)
      if ok then low, high = a, b end
    end
    data.list = {
      sections = sections,
      childHeight = gs.Number(list.child, "GetHeight"),
      viewHeight = gs.Number(list.scroll, "GetHeight"),
      viewWidth = gs.Number(list.scroll, "GetWidth"),
      offset = list.offset,
      barMin = low, barMax = high,
      barShown = gs.Read(list.bar, "IsShown") and true or false,
      scrollLevel = gs.Number(list.scroll, "GetFrameLevel"),
      pageLevel = gs.Number(frame, "GetFrameLevel"),
    }
  end
  U.SaveDiagnostic("gameSettingsChrome", data)

  U.Print("gamedump: " .. page.id .. ", " ..
          tostring(data.tree.childCount or 0) .. " children, " ..
          data.stripped .. " own textures hidden - saved to " ..
          "UnrealUIDiagDB.gameSettingsChrome")
  U.Print("  |cffffff00/reload|r then read " .. U.SavedVariablesHint())
end

U.gameSettings = gs
