-- unrealUI :: modules/microbar.lua
--
-- pfUI-style micro button bar: pulls the client's own micro menu buttons
-- (character, spellbook, talent, quest log, social, world map, main menu,
-- help) into one compact, movable row. Under the `modern` and `classic-wow`
-- themes the buttons' own native art is left completely untouched --
-- reparented and scaled down only -- which is deliberate, not an omission:
-- see the reskin note below. The enable option lives on the settings window's
-- General page (modules/settings.lua) rather than a dedicated tab, since it
-- is the bar's only setting.
--
-- Evidence gap: query_compat.py has no runtime record for MICRO_BUTTONS or
-- any individual *MicroButton global on this client. UnrealPfUI's own
-- modules/panel.lua and UnrealRuntimeProbe's TargetedProbes.lua already
-- document that gap and fall back to the vanilla candidate names below,
-- checking _G for each before touching it. This module reuses that exact
-- fallback list and existence check. A candidate this client does not have is
-- simply skipped, so the worst case is an empty bar, never an error.
--
-- Reskin history (do not repeat without new evidence): two flat-icon reskin
-- attempts were tried and both regressed visually in-game and were reverted.
-- MEASURED (2026-08-18, /uui check on this client -- knowledge.json /
-- ui.microbutton_icon_child_absent): none of the 8 candidates expose a
-- "<name>Icon" child distinct from their own Normal/Pushed/Highlight/Disabled
-- state art, unlike quest log/spellbook rows (which do, and are the case
-- core/stockui.lua's U.StyleStockButton was written for). A first attempt
-- drew a flat panel behind the untouched native art -- boxed/broken look. A
-- second attempt cropped the button's own GetNormalTexture() as a substitute
-- icon (the same trim actionbar icons use) with no border/background -- also
-- reported broken/distorted in-game. Native micro button face art is left
-- alone until there is a confirmed technique, not another guess.
--
-- Under the `modern-wow` theme the buttons are skinned after all, but by a
-- different technique than the two that failed: each button's own
-- Normal/Pushed/Highlight/Disabled slots are pointed at a complete imported
-- Dragonflight glyph (icon plus its own button plate), so nothing is drawn
-- behind or cropped out of the native art -- it is replaced outright. That is
-- what DragonflightUI-Reforged itself does (modules/micro/micro.lua), so it is
-- WORKING_SOURCE for a 1.12-era client, not runtime verification here. See
-- U.BuildModernWowMicroBar below; the other two themes still leave the native
-- art completely alone.
--
-- `/uui check` reports how many candidates resolved.
--
-- Disabling the feature (General page checkbox, U.ModuleConfig "microbar")
-- hands every installed button back to its captured original parent, anchor,
-- scale and size, so turning it off returns the stock micro menu to where the
-- client originally put it.

local U = UnrealUI
local M = U.media

local MB = U.RegisterModule("microbar")

local BUTTON_NAMES = {
  "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
  "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
  "MainMenuMicroButton", "HelpMicroButton",
}

local BUTTON_SCALE = 0.6
local BUTTON_GAP = 0
local HEIGHT = 23
-- pfUI's own microbutton panel is a hard-coded 145 wide for these same 8
-- candidates at the same 0.6 scale (UnrealPfUI modules/panel.lua); reused
-- here as a WORKING_SOURCE width rather than a measured one, scaled down when
-- fewer candidates resolve on this client.
local FULL_WIDTH = 145
local MIN_WIDTH = 20

-- ---------------------------------------------------------------------------
-- modern-wow drawing path
--
-- Kept on one table rather than as a dozen top-level locals: this file stays
-- well inside the 200-local chunk limit that way, per rules/unreal-ui.md.
--
-- `glyph` maps each native button to a core/media.lua micro-glyph id. Seven of
-- the eight are the obvious counterpart. WorldMapMicroButton is the exception:
-- the Dragonflight micro menu has no map button at all, so neither the
-- imported colour set nor the source's grey atlas contains one, and the
-- closest glyph that still reads as an atlas -- the tome (`log`, the source's
-- Adventure Guide icon) -- is used for it. DragonflightUI's own file maps its
-- world-map button to the shield, which is its character glyph here.
--
-- Sizes, spacing and the texture-coordinate window are the source's own
-- numbers for these exact files (20x30 buttons, 2 apart, sampling
-- 36..86 x 29..98 out of each 128x128 glyph), so the art is drawn at the
-- proportions it was authored for.
-- ---------------------------------------------------------------------------
local modernWow = {
  glyph = {
    CharacterMicroButton = "character",
    SpellbookMicroButton = "spellbook",
    TalentMicroButton    = "talents",
    QuestLogMicroButton  = "quest",
    SocialsMicroButton   = "social",
    WorldMapMicroButton  = "log",
    MainMenuMicroButton  = "menu",
    HelpMicroButton      = "help",
  },

  -- Native regions that sit on top of a micro button's own face art and would
  -- otherwise cover the imported glyph: the character portrait overlay and the
  -- performance/latency bar the client parents to the main-menu button. Both
  -- are looked up as plain globals and skipped when absent, the same existence
  -- discipline BUTTON_NAMES uses.
  overlays = { "MicroButtonPortrait", "MainMenuBarPerformanceBarFrame" },

  -- The source's 20x30 / 2 geometry drawn at 85%, keeping its proportions.
  width = 20 * 0.85,
  height = 30 * 0.85,
  gap = 2 * 0.85,

  left = 36 / 128,
  right = 86 / 128,
  top = 29 / 128,
  bottom = 98 / 128,
}

-- Evaluated on every Apply rather than latched at login, so flipping the micro
-- bar off and back on from the settings page redraws in the right style. Both
-- helpers are defined by files the TOC loads before this module's OnEnable
-- runs, but they are still type-checked: this module must not stop working if
-- either is absent.
function modernWow.Active()
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= "modern-wow" then return false end
  if type(U.ModernWowSurfaceEnabled) == "function" and
     not U.ModernWowSurfaceEnabled("microbar") then return false end
  return true
end

local config
local anchor
local buttons = {}   -- name -> captured original state + button reference

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local function EnsureConfig()
  if not config then config = U.ModuleConfig("microbar", { enabled = true }) end
  return config
end

-- ---------------------------------------------------------------------------
-- Button capture / install / restore
-- ---------------------------------------------------------------------------

-- Captures a button's pre-microbar state exactly once. U.GetFramePoint already
-- normalises this client's inverted GetPoint Y (core/compat.lua); feeding that
-- normalised tuple straight back into SetPoint against the *original* relative
-- frame is the same round-trip core/mover.lua relies on for saved positions.
local function CaptureOriginal(name, button)
  local entry = buttons[name]
  if entry then return entry end

  local point, relative, relativePoint, x, y = U.GetFramePoint(button, 1)
  local parentOk, parent = pcall(button.GetParent, button)
  local scaleOk, scale = pcall(button.GetScale, button)
  -- Size and hit rect only matter for the modern-wow path, which resizes the
  -- buttons rather than only scaling them; captured unconditionally so a
  -- theme switch cannot find them missing. A method this client does not
  -- expose simply leaves the field nil and is then not restored.
  local widthOk, width = pcall(button.GetWidth, button)
  local heightOk, height = pcall(button.GetHeight, button)
  local insetOk, insetL, insetR, insetT, insetB =
    pcall(button.GetHitRectInsets, button)

  entry = {
    button = button,
    parent = parentOk and parent or nil,
    point = point,
    relative = relative,
    relativePoint = relativePoint,
    x = x,
    y = y,
    scale = (scaleOk and tonumber(scale)) or nil,
    width = (widthOk and tonumber(width)) or nil,
    height = (heightOk and tonumber(height)) or nil,
    insetL = (insetOk and tonumber(insetL)) or nil,
    insetR = (insetOk and tonumber(insetR)) or nil,
    insetT = (insetOk and tonumber(insetT)) or nil,
    insetB = (insetOk and tonumber(insetB)) or nil,
  }
  buttons[name] = entry
  return entry
end

-- Points one of the button's own texture slots at an imported glyph and
-- windows it down to the glyph's drawn area. Each slot is set from a path,
-- which creates the texture object when the button has none, so no region is
-- hunted for or retained -- the returned texture is used immediately and
-- dropped, never cached across refreshes (rules/unreal-ui.md, native widget
-- ownership).
function modernWow.SetSlot(button, setter, getter, path)
  if not path then return end
  pcall(setter, button, path)
  local ok, texture = pcall(getter, button)
  if ok and texture then
    pcall(texture.SetTexCoord, texture, modernWow.left, modernWow.right,
          modernWow.top, modernWow.bottom)
  end
end

-- Replaces a button's four state faces with the Dragonflight glyph set. The
-- pushed/hover/disabled art comes from the same glyph, so every state the
-- button already had keeps working and none of them can reveal native art.
-- Only `talents` ships a real disabled face; the rest reuse the faded one,
-- which is the source's own pushed art and reads as the dimmed state.
function modernWow.SkinButton(name, button)
  local id = modernWow.glyph[name]
  local art = id and M.modernWow and M.modernWow.micro
                and M.modernWow.micro[id]
  if not art then return false end

  modernWow.SetSlot(button, button.SetNormalTexture,
                    button.GetNormalTexture, art.normal)
  modernWow.SetSlot(button, button.SetPushedTexture,
                    button.GetPushedTexture, art.faded)
  modernWow.SetSlot(button, button.SetHighlightTexture,
                    button.GetHighlightTexture, art.highlight)
  modernWow.SetSlot(button, button.SetDisabledTexture,
                    button.GetDisabledTexture, art.disabled or art.faded)
  return true
end

-- Hides the native regions that would otherwise draw over the imported glyph.
-- Hide only: nothing is unregistered, reparented or replaced, so the client
-- keeps full ownership of both frames.
function modernWow.HideOverlays()
  local i
  for i = 1, table.getn(modernWow.overlays) do
    local frame = U.G(modernWow.overlays[i])
    if frame then pcall(frame.Hide, frame) end
  end
end

-- Lays the installed buttons out left to right with one uniform gap, and
-- nothing else: no parent, size, scale, hit rect or texture is touched, so
-- this is cheap enough to re-run from a native update hook (see
-- InstallNativeUpdateHook below). Every pair gets exactly the same gap because
-- each button is anchored to the previous one's RIGHT edge and they are all
-- the same width.
local function AnchorRow()
  if not anchor then return end

  local prev = nil
  local i
  local gap = (modernWow.Active() and modernWow.gap) or BUTTON_GAP

  for i = 1, table.getn(BUTTON_NAMES) do
    local entry = buttons[BUTTON_NAMES[i]]
    if entry and entry.button then
      local button = entry.button
      pcall(button.ClearAllPoints, button)
      if prev then
        pcall(button.SetPoint, button, "LEFT", prev, "RIGHT", gap, 0)
      else
        pcall(button.SetPoint, button, "LEFT", anchor, "LEFT", 0, 0)
      end
      prev = button
    end
  end
end

-- The client re-anchors one button behind the bar's back, and the row has to
-- take it back.
--
-- MEASURED (UnrealRuntimeProbe /urp probe microbar, group `microbar`,
-- 2026-09-12, USER_CONFIRMED_INGAME + probe evidence
-- microbar.row_geometry.v1 / microbar.native_update.v1): at steady state under
-- the modern-wow skin every button was parented to the bar at scale 1, sized
-- 20x30, with a 20x30 face texture, and seven of the eight carried exactly one
-- anchor point -- the row's own LEFT -> previous RIGHT, x 2. QuestLogMicroButton
-- carried TWO:
--
--   1  LEFT        -> TalentMicroButton RIGHT        x  2   (this module)
--   2  BOTTOMLEFT  -> TalentMicroButton BOTTOMRIGHT  x -2   (the client)
--
-- The client's extra point won, and the talent/quest-log pair measured a -2
-- gap where all six other pairs measured +2. That is the whole defect: the art
-- is identical in size for every button, so nothing about the imported glyphs
-- was involved.
--
-- -2 is the overlap the native micro-button face art is drawn for, and vanilla
-- FrameXML's UpdateMicroButtons() is what writes it (it re-points the quest-log
-- button at the talent button, or at the spellbook button below level 10).
-- Calling that global once through this module's post-hook left QuestLog with
-- exactly the row's single point and restored the even +2 row across all seven
-- pairs -- so re-asserting the row is the correct repair.
--
-- What the probe could NOT establish is when the second point is written. It
-- survives a reload with the post-hook installed, so it is not written through
-- the global: the writer is native code or an XML handler this addon cannot
-- observe, and it lands after this module's own layout pass. Guessing at its
-- trigger is what the two earlier attempts did. Instead the row is checked on
-- the shared driver: a button this module placed has exactly one point, so any
-- other count means someone re-anchored it and the row is simply laid out
-- again. GetNumPoints is BEHAVIOR_VERIFIED on this client by the same probe
-- run (countCallOk true, exact counts returned for all eight buttons), the
-- check is eight reads twice a second, and it writes nothing at all while the
-- row is clean.
--
-- The UpdateMicroButtons post-hook is kept as well. It is the cheapest repair
-- path for every re-anchor that does come through Lua (each stock window
-- opening and closing calls it), and it fixes those in the same frame instead
-- of on the next guard tick.
local DRIFT_ID = "microbar.anchors"
local DRIFT_INTERVAL = 0.5

-- One point per installed button is this module's own signature. Anything else
-- -- the client's extra point, or a point it replaced -- is drift.
local function RowDrifted()
  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local entry = buttons[BUTTON_NAMES[i]]
    if entry and entry.button then
      local ok, count = pcall(entry.button.GetNumPoints, entry.button)
      count = ok and tonumber(count) or nil
      if count and count ~= 1 then return true end
    end
  end
  return false
end

local function WatchRow()
  if not anchor or not config or not config.enabled then return end
  if RowDrifted() then AnchorRow() end
end

-- Non-destructive: the native function runs first and untouched
-- (core/stockui.lua's U.PostHookGlobal), nothing is unregistered or replaced,
-- and only the anchors this module already owns are written again.
-- UpdateMicroButtons takes no arguments and does not read `arg`, so it is one
-- of the fixed-signature natives that wrapper documents as safe.
local hooked = false
local function InstallNativeUpdateHook()
  if hooked or type(U.PostHookGlobal) ~= "function" then return end
  -- A false return (global absent on this client) simply leaves the hook
  -- uninstalled and retries on the next Apply; the driver guard covers the row
  -- either way.
  hooked = U.PostHookGlobal("UpdateMicroButtons", function()
    if config and config.enabled then AnchorRow() end
  end) and true or false
end

-- Reparents every resolved candidate into the bar, left to right in candidate
-- order, and returns how many were actually available on this client.
local function ArrangeButtons()
  local count = 0
  local i
  local skinned = modernWow.Active()

  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local entry = buttons[name]
    if entry and entry.button then
      local button = entry.button

      pcall(button.SetParent, button, anchor)

      if skinned then
        -- The imported glyph is a full-bleed face, so the button is sized to
        -- it at scale 1 and its hit rect matches the art exactly. The native
        -- art's own bottom inset would otherwise leave most of the glyph
        -- unclickable.
        pcall(button.SetScale, button, 1)
        pcall(button.SetWidth, button, modernWow.width)
        pcall(button.SetHeight, button, modernWow.height)
        pcall(button.SetHitRectInsets, button, 0, 0, 0, 0)
        modernWow.SkinButton(name, button)
      else
        pcall(button.SetScale, button, BUTTON_SCALE)
      end

      pcall(button.Show, button)

      count = count + 1
    end
  end

  -- Anchored after every button is parented and sized, so the row is chained
  -- against final widths.
  AnchorRow()

  if skinned then modernWow.HideOverlays() end

  return count
end

-- Hands every captured button back to where it came from. Order does not
-- matter here: each entry restores against its own captured relative frame,
-- not against the previous button in the bar.
local function RestoreButtons()
  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local entry = buttons[BUTTON_NAMES[i]]
    if entry and entry.button then
      local button = entry.button
      pcall(function()
        button:SetParent(entry.parent or UIParent)
        button:ClearAllPoints()
        if entry.point then
          button:SetPoint(entry.point, entry.relative or UIParent,
                          entry.relativePoint or entry.point,
                          entry.x or 0, entry.y or 0)
        end
        if entry.scale then button:SetScale(entry.scale) end
        -- Geometry the modern-wow path overwrites. The imported faces are not
        -- put back: a texture swap has no captured counterpart to restore to
        -- (the native faces carry texture coordinates set in the client's own
        -- layout, which Lua cannot read back), and the theme is a reload-time
        -- choice anyway, so the buttons are stock again on the next login.
        if entry.width then button:SetWidth(entry.width) end
        if entry.height then button:SetHeight(entry.height) end
        if entry.insetL then
          button:SetHitRectInsets(entry.insetL, entry.insetR or 0,
                                  entry.insetT or 0, entry.insetB or 0)
        end
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Bar frame
-- ---------------------------------------------------------------------------
local function Build()
  anchor = CreateFrame("Frame", "UnrealUIMicroBarAnchor", UIParent)
  anchor:SetHeight(HEIGHT)
  anchor:SetWidth(MIN_WIDTH)
  pcall(anchor.SetFrameStrata, anchor, "MEDIUM")

  U.RegisterMover("microbar", anchor, {
    label = U.L("MOVER_LABEL_MICRO_BAR"),
    default = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -190, y = -70 },
    -- A disabled bar keeps its stored position but offers no drag handle in
    -- edit mode; see core/mover.lua.
    visible = function() return config and config.enabled end,
  })
end

-- Applies the current enabled state: installs (and sizes the bar around)
-- every resolved candidate, or restores everything to its stock location.
local function Apply()
  if not anchor then return end

  if not config.enabled then
    -- The guard stops with the bar: a restored button is the client's to
    -- anchor again, and re-asserting the row over it would fight it.
    U.UnregisterUpdate(DRIFT_ID)
    RestoreButtons()
    anchor:Hide()
    return
  end

  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local button = U.G(name)
    if button then CaptureOriginal(name, button) end
  end

  local count = ArrangeButtons()
  InstallNativeUpdateHook()
  if count > 0 then
    U.RegisterUpdate(DRIFT_ID, DRIFT_INTERVAL, WatchRow)
  else
    U.UnregisterUpdate(DRIFT_ID)
  end

  local width = MIN_WIDTH
  if modernWow.Active() then
    -- Sized from the buttons actually installed rather than from a fixed
    -- total, so a client missing a candidate gets a bar with no dead space.
    anchor:SetHeight(modernWow.height)
    if count > 0 then
      width = count * (modernWow.width + modernWow.gap) - modernWow.gap
    end
  else
    -- Height as well as width, because a modern-wow session that switched the
    -- surface off mid-session would otherwise leave the taller bar behind.
    anchor:SetHeight(HEIGHT)
    if count > 0 then
      width = U.Round(FULL_WIDTH * count / table.getn(BUTTON_NAMES))
    end
  end
  if width < MIN_WIDTH then width = MIN_WIDTH end
  anchor:SetWidth(width)
  anchor:Show()

  if count == 0 then
    U.Debug("microbar: none of the " .. table.getn(BUTTON_NAMES) ..
            " candidate micro buttons resolved on this client")
  end
end

-- Public so modules/settings.lua's General page can flip the checkbox without
-- reaching into this module's internals.
U.ApplyMicroBar = Apply

-- ---------------------------------------------------------------------------
-- modern-wow surface entry point
--
-- The drawing path lives in the module that owns the buttons, exactly as the
-- action bar's own U.BuildModernWowActionBars does. Apply already picks the
-- style itself, so this module has usually skinned the bar by the time
-- modules/modernwow.lua reaches its surface registry at PLAYER_LOGIN; the call
-- is still made so the surface is genuinely owned by the registry (and so
-- turning it off in the registry is what switches the skin off), and it simply
-- redraws.
--
-- Returns false, leaving the native art untouched, when the theme is not
-- active, the surface is off, or the micro bar itself is disabled.
-- ---------------------------------------------------------------------------
function U.BuildModernWowMicroBar()
  if not modernWow.Active() then return false end

  EnsureConfig()
  if not config.enabled then return false end

  if not anchor then Build() end
  Apply()
  return true
end

-- Measured readout for /uui check: which candidates resolved, so an empty bar
-- in-game can be told apart from a client that simply has none of these
-- globals, plus the installed row's real on-screen geometry.
--
-- `geom` is what turns "the gap between two icons looks wrong" into a number.
-- Every button in the row shares one parent and one scale, so their edges are
-- directly comparable: `gap` is the next button's left edge minus this one's
-- right edge, which must be modernWow.gap for every pair under the skinned
-- path. A uniform list means the layout is correct and the perceived gap is
-- the glyph art's own transparent margin; a single odd entry means something
-- re-anchored or resized that one button after ArrangeButtons ran.
function U.MicroBarReport()
  local report = {
    enabled = config and config.enabled,
    skin = (modernWow.Active() and "modern-wow") or "native",
    gap = (modernWow.Active() and modernWow.gap) or BUTTON_GAP,
    found = {}, missing = {}, geom = {},
  }
  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local button = U.G(name)
    if button then
      table.insert(report.found, name)

      -- Read once, straight into plain numbers; nothing about the native
      -- button is retained (rules/unreal-ui.md, native widget ownership).
      local leftOk, left = pcall(button.GetLeft, button)
      local rightOk, right = pcall(button.GetRight, button)
      local widthOk, width = pcall(button.GetWidth, button)
      local scaleOk, scale = pcall(button.GetScale, button)
      local point, relative, relativePoint, x = U.GetFramePoint(button, 1)
      local relName = nil
      if relative then
        local nameOk, resolved = pcall(relative.GetName, relative)
        relName = (nameOk and resolved) or "unnamed"
      end
      local pointsOk, points = pcall(button.GetNumPoints, button)

      table.insert(report.geom, {
        name = name,
        left = (leftOk and tonumber(left)) or nil,
        right = (rightOk and tonumber(right)) or nil,
        width = (widthOk and tonumber(width)) or nil,
        scale = (scaleOk and tonumber(scale)) or nil,
        points = (pointsOk and tonumber(points)) or nil,
        point = point,
        relative = relName,
        relativePoint = relativePoint,
        x = x,
      })
    else
      table.insert(report.missing, name)
    end
  end

  -- Pair gaps, filled in only where both neighbours reported an edge.
  for i = 1, table.getn(report.geom) - 1 do
    local a, b = report.geom[i], report.geom[i + 1]
    if a.right and b.left then a.gap = b.left - a.right end
  end

  return report
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
function MB:OnInit()
  EnsureConfig()
end

function MB:OnEnable()
  EnsureConfig()
  if not anchor then Build() end
  Apply()
end
