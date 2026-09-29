-- unrealUI :: modules/microbar.lua
--
-- pfUI-style micro button bar: pulls the client's own micro menu buttons
-- (character, spellbook, talent, quest log, social, world map, main menu,
-- help) into one compact, movable row. The `classic-wow` theme keeps the
-- complete stock MainMenuBar assembly intact, including its original micro
-- menu. `modern` draws the `modern-wow` glyph row (user request, 2026-09-28);
-- only classic-wow's "action only" bar keeps the native art, reparented and
-- scaled, which is deliberate; see the reskin note below. The enable
-- option lives on the settings window's General page (modules/settings.lua)
-- rather than a dedicated tab, since it is the bar's only setting.
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
-- different technique than the two that failed: the native face art is
-- replaced outright rather than cropped or boxed. Each button is rebuilt as
-- Retail's MainMenuBarMicroButton from Retail's own micro-menu atlas (user
-- request, 2026-09-28): the icon cells in the button's own state slots and
-- the ButtonBG plate behind them -- see the modern-wow drawing path below and
-- U.BuildModernWowMicroBar. `modern` takes the same path (user request,
-- 2026-09-28; modernWow.Active), while classic-wow leaves the whole stock bar
-- in place.
--
-- One button is the addon's own rather than the client's: Professions,
-- between Spellbook and Talents (user request, 2026-09-28). This client has no
-- professions micro button and no professions book, so it opens the
-- Spellbook's Professions page (modules/spellbookprofessions.lua), which every
-- theme builds. See the `profession` table below.
--
-- A second one, Group Finder, sits after Social under the Retail row only
-- (user request, 2026-09-28). This client has no group finder: see the
-- `finder` table below for what it does instead.
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

local PROFESSION = "UnrealUIProfessionMicroButton"
local FINDER = "UnrealUIGroupFinderMicroButton"

local BUTTON_NAMES = {
  "CharacterMicroButton", "SpellbookMicroButton", PROFESSION,
  "TalentMicroButton", "QuestLogMicroButton", "SocialsMicroButton", FINDER,
  "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

local BUTTON_SCALE = 0.6
local BUTTON_GAP = 0
local HEIGHT = 23
-- The bar's width is measured from the buttons it holds (size.FitAnchor); it
-- replaced pfUI's hard-coded 145-per-8 panel width, which left the edit-mode
-- handle wider than the row.
local MIN_WIDTH = 20

-- The player's size for the whole bar (user request, 2026-09-28), a percent of
-- each style's own default, set from the micro bar's edit-mode panel. One
-- uniform factor on every button's scale, on the gaps and on the bar's box,
-- so the row keeps its ratio in every style.
--
-- 100% is the size the bar is drawn at today (user request, 2026-09-28: the
-- percent is rebased so the size in use reads 100%). Until the Retail row was
-- sized by dimensions its buttons ignored every scale, so what was on screen
-- was the style's full size; that is 100% now.
local size = { MIN = 50, MAX = 100, STEP = 5, DEFAULT = 100 }

-- ---------------------------------------------------------------------------
-- modern-wow drawing path (also drawn under `modern`)
--
-- Kept on one table rather than as a dozen top-level locals: this file stays
-- well inside the 200-local chunk limit that way, per rules/unreal-ui.md.
--
-- Retail's micro menu (Blizzard_MicroMenu/Mainline, MainMenuBarMicroButton),
-- drawn only from Retail's micro-menu atlas (M.modernWow.microMenu):
--
--  * each button is 32x40 with `ButtonBG-Up` behind it at atlas size, swapped
--    for `ButtonBG-Down` while pushed (the template's Background /
--    PushedBackground), on addon textures created on the button;
--  * the icon's Up / Down / Disabled cells go in the button's own state slots
--    (LoadMicroButtonTextures), and the highlight slot takes Mouseover BLEND
--    at full alpha -- or, while pushed, the Down cell ADD at half alpha
--    (SetPushed / SetNormal);
--  * the normal face goes transparent while hovered, because Retail bakes the
--    shadow into the highlight (OnEnter / OnLeave);
--  * CharacterMicroButton is an icon button like the rest, with the atlas's
--    shield (`Achievements` cells) instead of Retail's live portrait, whose
--    2D snapshot is too low-resolution at this size (user request,
--    2026-09-28).
--
-- A native button's pushed state is the client's own: vanilla
-- UpdateMicroButtons() locks a button PUSHED while its window is open. That
-- state is read back (GetButtonState) and the Retail look follows it, from
-- the UpdateMicroButtons post-hook, the row guard's tick and each mouse-up.
-- Nothing is replaced: every script is post-hooked (U.PostHookScript).
--
-- The Dragonflight glyph row this replaces (20x30 at 85%) is gone with its
-- files (user request, 2026-09-28).
-- ---------------------------------------------------------------------------
local modernWow = {
  -- Native regions that sit on top of a micro button's own face art and would
  -- otherwise cover the Retail art: the character portrait overlay (the
  -- button draws the shield instead) and the performance/latency bar the
  -- client parents to the main-menu button. Both are looked up as plain
  -- globals and skipped when absent, the same existence discipline
  -- BUTTON_NAMES uses.
  overlays = { "MicroButtonPortrait", "MainMenuBarPerformanceBarFrame" },

  -- name -> the addon regions drawn on that button and its painted state.
  skins = {},
  -- True while the bar is installed in this style; every hook checks it, so
  -- a bar switched off or to the native path is left alone.
  enabled = false,
}

function modernWow.Token()
  return M.modernWow.microMenu
end

-- The addon's own micro buttons (Professions, Group Finder) show the same
-- tooltip as the client's micro buttons (user request, 2026-09-28): vanilla
-- GameTooltip_AddNewbieTip's shape -- the default tooltip anchor, a white
-- title, then a wrapped description in NORMAL_FONT_COLOR gold -- on the
-- client's GameTooltip, so UnrealUI's tooltip skin and placement
-- (modules/tooltip.lua) apply to it exactly as to Social's. Populated fresh
-- (SetText first) and shown once, the sequence modules/xpbar.lua uses; lines
-- are never appended to a tooltip already shown, which this client does not
-- relayout for (core/widgets.lua, info tooltip note).
modernWow.TOOLTIP_GOLD = { 1, 0.82, 0 }

function modernWow.ShowTooltip(owner, title, description, extra)
  local tip = GameTooltip
  if not tip or not owner then return end
  local anchor = U.G("GameTooltip_SetDefaultAnchor")
  local placed = type(anchor) == "function" and pcall(anchor, tip, owner)
  if not placed then pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT") end
  pcall(tip.SetText, tip, title, 1, 1, 1)
  local gold = modernWow.TOOLTIP_GOLD
  if description then
    pcall(tip.AddLine, tip, description, gold[1], gold[2], gold[3], 1)
  end
  if extra then pcall(tip.AddLine, tip, extra, 1, 1, 1, 1) end
  pcall(tip.Show, tip)
end

function modernWow.HideTooltip()
  if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

-- Evaluated on every Apply rather than latched at login, so flipping the micro
-- bar off and back on from the settings page redraws in the right style. Both
-- helpers are defined by files the TOC loads before this module's OnEnable
-- runs, but they are still type-checked: this module must not stop working if
-- either is absent.
--
-- `modern` draws the same row (user request, 2026-09-28): it has no surface
-- registry, so it needs no surface check.
function modernWow.Active()
  if type(U.GetActiveThemeStyle) ~= "function" then return false end
  local style = U.GetActiveThemeStyle()
  if style == "modern" then return true end
  if style ~= "modern-wow" then return false end
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
  if not config then
    config = U.ModuleConfig("microbar", {
      enabled = true, size = size.DEFAULT, sizeVersion = 3,
    })
    -- Sizes stored before version 3 were percents of a scale the buttons
    -- never applied, so none of them matches what the player saw: every one
    -- becomes 100%, the size that was actually on screen. Once.
    if (tonumber(config.sizeVersion) or 0) < 3 then
      config.size = size.DEFAULT
      config.sizeVersion = 3
    end
  end
  return config
end

function size.Percent()
  local value = tonumber(config and config.size) or size.DEFAULT
  if value < size.MIN then value = size.MIN end
  if value > size.MAX then value = size.MAX end
  return value
end

function size.Factor()
  return size.Percent() / 100
end

-- The size multiplier for the current style. Under the Retail row it is
-- applied to dimensions, never as a frame scale: MEASURED (group
-- `microbarvis`, span.v2, 2026-09-28) the buttons reported scale 0.4 yet
-- were drawn and measured at their full 32x40, so SetScale does not shrink
-- them here (see also knowledge.json /
-- widgets.reparented_native_widget_ignores_ancestor_scale: keep scale 1 and
-- size the layout instead). The native-art path still uses it as a scale.
function size.ButtonScale()
  if modernWow.Active() then
    return modernWow.Token().scale * size.Factor()
  end
  return BUTTON_SCALE * size.Factor()
end

-- The offset between two neighbours, in the bar's units: Retail's -5
-- overlap at the row's size.
function size.Gap()
  if modernWow.Active() then
    return modernWow.Token().padding * size.ButtonScale()
  end
  return BUTTON_GAP
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

-- Points one of the button's own texture slots at `path`, cropped to `coords`
-- ({ left, right, top, bottom }; the whole file when nil). Each slot is set
-- from a path, which creates the texture object when the button has none, so
-- no region is hunted for or retained -- the returned texture is used
-- immediately by the caller and dropped, never cached across refreshes
-- (rules/unreal-ui.md, native widget ownership).
function modernWow.SetSlot(button, setter, getter, path, coords)
  if not path then return nil end
  pcall(setter, button, path)
  local ok, texture = pcall(getter, button)
  if not ok or not texture then return nil end
  local c = coords or { 0, 1, 0, 1 }
  pcall(texture.SetTexCoord, texture, c[1], c[2], c[3], c[4])
  return texture
end

-- One icon cell in one of the button's own state slots, placed exactly as the
-- plate is: at its atlas size, centred on the button. The slot's own box
-- cannot be trusted -- MEASURED (group `microbarvis`, 2026-09-28): every
-- native micro button keeps its face texture at a client-set 29x40, inset 1.5
-- each side of the 32x40 button, which squeezed the 64x82 cells ~10%
-- horizontally. Sized from the atlas instead, icon and plate share one
-- canvas, as Retail authored them.
function modernWow.SetCell(button, setter, getter, coords)
  local t = modernWow.Token()
  local texture = modernWow.SetSlot(button, setter, getter, t.texture, coords)
  if texture then
    local s = size.ButtonScale()
    pcall(function()
      texture:ClearAllPoints()
      texture:SetWidth(t.atlasWidth * s)
      texture:SetHeight(t.atlasHeight * s)
      texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    end)
  end
  return texture
end

-- One atlas member at its atlas size, centred on the button (useAtlasSize +
-- CENTER, as the template's Background textures are).
function modernWow.Region(button, layer, coords)
  local t = modernWow.Token()
  local ok, texture = pcall(button.CreateTexture, button, nil, layer)
  if not ok or not texture then return nil end
  pcall(function()
    texture:SetTexture(t.texture)
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
  end)
  modernWow.SizeRegion(texture)
  return texture
end

-- An atlas-size region at the row's size (see size.ButtonScale).
function modernWow.SizeRegion(texture)
  if not texture then return end
  local t = modernWow.Token()
  local s = size.ButtonScale()
  pcall(texture.SetWidth, texture, t.atlasWidth * s)
  pcall(texture.SetHeight, texture, t.atlasHeight * s)
end

function modernWow.SetShown(region, shown)
  if not region then return end
  if shown then pcall(region.Show, region) else pcall(region.Hide, region) end
end

function modernWow.IsPushed(button)
  local ok, state = pcall(button.GetButtonState, button)
  return ok and state == "PUSHED" or false
end

function modernWow.IsEnabled(button)
  local ok, enabled = pcall(button.IsEnabled, button)
  if not ok then return true end
  return enabled and true or false
end

-- MainMenuBarMicroButtonMixin:SetPushed / :SetNormal.
function modernWow.Paint(name, pushed)
  local skin = modernWow.skins[name]
  if not skin then return end
  local t = modernWow.Token()
  local button = skin.button
  skin.pushed = pushed

  modernWow.SetShown(skin.plate, not pushed)
  modernWow.SetShown(skin.pushedPlate, pushed)

  local icon = t.icons[t.map[name]]
  if not icon then return end
  local highlight = modernWow.SetCell(button, button.SetHighlightTexture,
                                      button.GetHighlightTexture,
                                      pushed and icon.pushed or icon.highlight)
  if highlight then
    pcall(highlight.SetBlendMode, highlight, pushed and "ADD" or "BLEND")
    pcall(highlight.SetAlpha, highlight,
          pushed and t.pushedHighlightAlpha or 1)
  end
end

-- Brings every drawn button in line with its real button state; writes
-- nothing for a button that already matches.
function modernWow.SyncAll()
  if not modernWow.enabled then return end
  local name, skin
  for name, skin in pairs(modernWow.skins) do
    local pushed = modernWow.IsPushed(skin.button)
    if pushed ~= skin.pushed then modernWow.Paint(name, pushed) end
  end
end

function modernWow.SetNormalAlpha(button, alpha)
  local ok, normal = pcall(button.GetNormalTexture, button)
  if ok and normal then pcall(normal.SetAlpha, normal, alpha) end
end

-- OnMouseDown / OnMouseUp / OnEnter / OnLeave, post-hooked once per button.
function modernWow.HookButton(name, button)
  U.PostHookScript(button, "OnMouseDown", function()
    if modernWow.enabled and modernWow.IsEnabled(button) then
      modernWow.Paint(name, true)
    end
  end)
  -- The click's own window toggle (and the client's UpdateMicroButtons) run
  -- around mouse-up, so the settled state is read a frame later.
  U.PostHookScript(button, "OnMouseUp", function()
    if modernWow.enabled then U.DeferOnce("microbar.sync", modernWow.SyncAll) end
  end)
  U.PostHookScript(button, "OnEnter", function()
    if modernWow.enabled then modernWow.SetNormalAlpha(button, 0) end
  end)
  U.PostHookScript(button, "OnLeave", function()
    if modernWow.enabled then modernWow.SetNormalAlpha(button, 1) end
  end)
end

-- An addon-owned, mouse-less frame on the bar's anchor that holds one native
-- button's plate. Its level sits under every button of the row, so the icon
-- (the button's own state textures) always draws over it.
function modernWow.PlateHost()
  if not anchor then return nil end
  local ok, host = pcall(CreateFrame, "Frame", nil, anchor)
  if not ok or not host then return nil end
  pcall(host.SetFrameStrata, host, "LOW")
  pcall(host.SetFrameLevel, host, 1)
  pcall(host.EnableMouse, host, false)
  return host
end

function modernWow.SizeHost(skin)
  if not skin or not skin.host then return end
  local t = modernWow.Token()
  local s = size.ButtonScale()
  pcall(skin.host.SetWidth, skin.host, t.width * s)
  pcall(skin.host.SetHeight, skin.host, t.height * s)
end

-- Draws one button in the Retail style. Its regions are created the first
-- time and reused, never recreated.
function modernWow.SkinButton(name, button)
  local t = modernWow.Token()
  local icon = t.icons[t.map[name] or ""]
  if not icon then return false end

  local skin = modernWow.skins[name]
  if not skin then
    skin = { button = button }
    -- The addon's own buttons carry their plate as regions of their own
    -- frame. A client-owned button does not show regions added to it (only
    -- Professions and Group Finder drew a plate, user report 2026-09-29), so
    -- its plate is drawn on an addon-owned host frame under the button,
    -- placed by AnchorRow from the bar anchor's own geometry.
    local plateOwner = button
    if name ~= PROFESSION and name ~= FINDER then
      skin.host = modernWow.PlateHost()
      plateOwner = skin.host or button
    end
    skin.plate = modernWow.Region(plateOwner, "BACKGROUND", t.plateUp)
    skin.pushedPlate = modernWow.Region(plateOwner, "BACKGROUND", t.plateDown)
    modernWow.skins[name] = skin
    modernWow.HookButton(name, button)
  end
  modernWow.SizeRegion(skin.plate)
  modernWow.SizeRegion(skin.pushedPlate)
  modernWow.SizeHost(skin)
  if skin.host then modernWow.SetShown(skin.host, true) end

  modernWow.SetCell(button, button.SetNormalTexture, button.GetNormalTexture,
                    icon.normal)
  modernWow.SetCell(button, button.SetPushedTexture, button.GetPushedTexture,
                    icon.pushed)
  modernWow.SetCell(button, button.SetDisabledTexture,
                    button.GetDisabledTexture, icon.disabled)
  modernWow.SetNormalAlpha(button, 1)

  modernWow.Paint(name, modernWow.IsPushed(button))
  return true
end

-- Takes every addon region off the buttons when the bar is switched off, so
-- a button handed back to its stock place carries no Retail plate. The state
-- faces are not put back (see RestoreButtons).
function modernWow.HideSkins()
  modernWow.enabled = false
  local name, skin
  for name, skin in pairs(modernWow.skins) do
    modernWow.SetShown(skin.plate, false)
    modernWow.SetShown(skin.pushedPlate, false)
    modernWow.SetShown(skin.host, false)
    modernWow.SetNormalAlpha(skin.button, 1)
  end
end

-- Hides the native regions that would otherwise draw over the Retail art.
-- Hide only: nothing is unregistered, reparented or replaced, so the client
-- keeps full ownership of both frames.
function modernWow.HideOverlays()
  local i
  for i = 1, table.getn(modernWow.overlays) do
    local frame = U.G(modernWow.overlays[i])
    if frame then pcall(frame.Hide, frame) end
  end
end

-- ---------------------------------------------------------------------------
-- Professions button
--
-- Addon-owned. Under modern-wow / modern it is one more Retail button
-- (`Professions` cells, through modernWow.SkinButton like its neighbours).
-- On classic-wow's native "action only" bar it takes the client's own
-- micro-button art (M.microProfession), built like its Character button: the
-- blank portrait plate in the state slots and a profession icon in the
-- portrait window, dimmed and shifted while pressed.
--
-- It is held pressed while the Spellbook shows its Professions page, as a
-- native micro button is while its window is open.
--
-- Its hover tooltip is the client micro buttons' own (modernWow.ShowTooltip),
-- titled with the Spellbook tab's localized "Professions".
-- ---------------------------------------------------------------------------
local profession = { pressed = false, locked = false, skinned = nil }

-- The client's Character button faces, read once as plain path strings and
-- then dropped (rules/unreal-ui.md, native widget ownership). Falls back to
-- the recorded Vanilla paths when a face cannot be read.
function profession.CharacterFace(getter, fallback)
  local character = U.G("CharacterMicroButton")
  if not character or not character[getter] then return fallback end
  local ok, texture = pcall(character[getter], character)
  if not ok or not texture or not texture.GetTexture then return fallback end
  local pathOk, path = pcall(texture.GetTexture, texture)
  if pathOk and type(path) == "string" and path ~= "" then return path end
  return fallback
end

function profession.Create()
  if profession.button then return profession.button end
  if not anchor then return nil end

  local ok, button = pcall(CreateFrame, "Button", PROFESSION, anchor)
  if not ok or not button then return nil end
  pcall(button.RegisterForClicks, button, "LeftButtonUp")

  profession.icon = button:CreateTexture(nil, "OVERLAY")

  button:SetScript("OnClick", function()
    if type(U.ToggleSpellBookProfessions) == "function" then
      U.ToggleSpellBookProfessions()
    end
    profession.Sync()
  end)
  button:SetScript("OnMouseDown", function()
    profession.pressed = true
    profession.Paint()
  end)
  button:SetScript("OnMouseUp", function()
    profession.pressed = false
    profession.Paint()
  end)
  button:SetScript("OnEnter", function()
    modernWow.ShowTooltip(button, U.L("SPELLBOOK_PROFESSIONS"),
                          U.L("MICROBAR_PROFESSIONS_TIP"))
  end)
  button:SetScript("OnLeave", modernWow.HideTooltip)

  pcall(button.Hide, button)
  profession.button = button
  return button
end

-- The native path's portrait icon, which follows the press but not the
-- button's own state machine. The Retail path is painted by modernWow.
function profession.Paint()
  if not profession.button or profession.skinned then return end
  local pressed = profession.pressed or profession.locked
  local n = M.microProfession
  local c = pressed and n.iconPushed or n.iconNormal
  pcall(profession.icon.SetTexCoord, profession.icon, c[1], c[2], c[3], c[4])
  pcall(profession.icon.SetAlpha, profession.icon,
        pressed and n.iconPushedAlpha or 1)
end

-- Holds the button pressed while the Professions page is open, and splits the
-- Spellbook window between the two buttons by its active tab.
function profession.Sync()
  if not profession.button then return end
  local shown = type(U.SpellBookProfessionsShown) == "function" and
                U.SpellBookProfessionsShown() and true or false
  if shown ~= profession.locked then
    profession.locked = shown
    if shown then
      pcall(profession.button.SetButtonState, profession.button, "PUSHED", 1)
    else
      pcall(profession.button.SetButtonState, profession.button, "NORMAL")
    end
    profession.Paint()
  end
  profession.SyncSpellbook(shown)
  modernWow.SyncAll()
end

-- The client's UpdateMicroButtons holds SpellbookMicroButton pressed whenever
-- SpellBookFrame is shown, whichever page it shows, and does not run again on
-- a tab switch. While the Professions page is up the Spellbook button is
-- released here; when the book goes back to its spell tab it is pressed again
-- -- but only if this function released it, so the client's own pressed state
-- (and a press in progress) is otherwise left alone. Same SetButtonState the
-- client uses; nothing is hooked or replaced.
function profession.SyncSpellbook(professionsShown)
  local button = U.G("SpellbookMicroButton")
  if not button then return end
  local stateOk, state = pcall(button.GetButtonState, button)
  local pushed = stateOk and state == "PUSHED"

  if professionsShown then
    if pushed then
      pcall(button.SetButtonState, button, "NORMAL")
      profession.releasedSpellbook = true
    end
    return
  end

  if not profession.releasedSpellbook then return end
  profession.releasedSpellbook = false
  local book = U.G("SpellBookFrame")
  local openOk, open = false, false
  if book then openOk, open = pcall(book.IsShown, book) end
  if openOk and open and not pushed then
    pcall(button.SetButtonState, button, "PUSHED", 1)
  end
end

-- Retail's Spellbook button, while the Professions page is open, switches the
-- window to its Spellbook tab rather than closing it. The client's own OnClick
-- would toggle the window shut, and a post-hook runs too late to stop that, so
-- this one script is wrapped instead: in that single case the owned tab is
-- clicked (U.SpellBookShowSpellsTab) and the client's handler is skipped; in
-- every other case, and whenever the bar is off, the client's handler runs
-- untouched with the same arguments (its `this` / `arg1` globals are still the
-- ones the click set). Installed once.
function profession.HookSpellbookClick()
  if profession.spellbookHooked then return end
  local button = U.G("SpellbookMicroButton")
  if not button then return end
  local ok, previous = pcall(button.GetScript, button, "OnClick")
  if not ok then return end
  profession.spellbookHooked = pcall(button.SetScript, button, "OnClick",
    function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
      if config and config.enabled and
         type(U.SpellBookShowSpellsTab) == "function" and
         U.SpellBookShowSpellsTab() then
        profession.Sync()
        return
      end
      if previous then previous(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
    end) and true or false
end

-- Called by modules/spellbookprofessions.lua whenever its page opens or
-- closes, so a tab switch inside the Spellbook repaints both buttons at once
-- instead of on the row guard's next tick.
function U.MicroBarSync()
  if not config or not config.enabled or not anchor then return end
  profession.Sync()
end

-- Draws the button in the chosen style and sizes it for the native path; the
-- Retail path is sized by ArrangeButtons with every other button.
function profession.Skin(button, skinned)
  profession.skinned = skinned
  if skinned then
    pcall(profession.icon.Hide, profession.icon)
    modernWow.SkinButton(PROFESSION, button)
  else
    local n = M.microProfession
    modernWow.SetSlot(button, button.SetNormalTexture, button.GetNormalTexture,
                      profession.CharacterFace("GetNormalTexture", n.plateUp))
    modernWow.SetSlot(button, button.SetPushedTexture, button.GetPushedTexture,
                      profession.CharacterFace("GetPushedTexture", n.plateDown))
    local highlight = modernWow.SetSlot(button, button.SetHighlightTexture,
                        button.GetHighlightTexture,
                        profession.CharacterFace("GetHighlightTexture",
                                                 n.highlight))
    if highlight then pcall(highlight.SetBlendMode, highlight, "ADD") end

    -- Sized and hit-inset like the Spellbook button beside it, so the row
    -- stays even; the recorded Vanilla size when that was not captured.
    local ref = buttons.SpellbookMicroButton
    pcall(button.SetWidth, button, (ref and ref.width) or n.width)
    pcall(button.SetHeight, button, (ref and ref.height) or n.height)
    if ref and ref.insetL then
      pcall(button.SetHitRectInsets, button, ref.insetL, ref.insetR or 0,
            ref.insetT or 0, ref.insetB or 0)
    end

    pcall(profession.icon.SetTexture, profession.icon, n.icon)
    pcall(profession.icon.SetWidth, profession.icon, n.iconWidth)
    pcall(profession.icon.SetHeight, profession.icon, n.iconHeight)
    pcall(profession.icon.ClearAllPoints, profession.icon)
    pcall(profession.icon.SetPoint, profession.icon, "TOP", button, "TOP", 0,
          -n.iconTop)
    pcall(profession.icon.Show, profession.icon)
  end
  profession.Sync()
  profession.Paint()
end

-- ---------------------------------------------------------------------------
-- Group Finder button (user request, 2026-09-28)
--
-- Retail's LFD button, `Groupfinder` cells, after Social as in Retail's row.
-- The client's group finder has no documented Lua entry point (the
-- documented GetLookingForGroup / SetLookingForGroup are no-ops); it is opened
-- from its minimap button, and so is this one (finder.Open):
--
--  * always enabled on the atlas's Up eye (user request, 2026-09-28: the
--    greyed Disabled cell at half alpha hid the eye);
--  * a click opens the same finder the minimap button opens;
--  * held pressed while a battleground queue reports `queued`;
--  * its tooltip is the client micro buttons' own (modernWow.ShowTooltip),
--    with a white line while queued.
--
-- The three queues (GetBattlefieldStatus 1-3) are read on the row guard's
-- tick; no queue-status event has compatibility evidence on this client, so
-- none is registered. Retail row only: classic-wow's native-art bar has no
-- art for it, so it is left out of that row.
-- ---------------------------------------------------------------------------
local finder = { queue = nil, locked = false }

function finder.Create()
  if finder.button then return finder.button end
  if not anchor then return nil end

  local ok, button = pcall(CreateFrame, "Button", FINDER, anchor)
  if not ok or not button then return nil end
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  button:SetScript("OnClick", finder.Open)
  button:SetScript("OnEnter", function()
    modernWow.ShowTooltip(button, U.L("MICROBAR_GROUP_FINDER"),
                          U.L("MICROBAR_GROUP_FINDER_TIP"),
                          finder.Queued() and
                            U.L("MICROBAR_GROUP_FINDER_QUEUED") or nil)
  end)
  button:SetScript("OnLeave", modernWow.HideTooltip)
  pcall(button.Hide, button)
  finder.button = button
  return button
end

-- The first battleground queue whose status is `queued`, or nil.
function finder.Queued()
  local status = U.G("GetBattlefieldStatus")
  if type(status) ~= "function" then return nil end
  local i
  for i = 1, 3 do
    local ok, value = pcall(status, i)
    if ok and value == "queued" then return i end
  end
  return nil
end

-- Opens the client's own group finder, exactly as its minimap button does
-- (user request, 2026-09-28). MEASURED (group `microbarfinder`, 2026-09-28):
-- that button is LFTMinimapButton, a 33x33 Button on the Minimap whose only
-- click script is OnMouseUp -- no OnClick. Its handler is run as a left
-- mouse-up on it: the legacy `this` / `arg1` globals this client's handlers
-- read (knowledge.json / scripts.onupdate_elapsed_only_via_arg1) are set for
-- the call and restored, and the same values are passed as arguments for a
-- handler that takes them. Nothing is hooked, replaced or moved. Without the
-- button, a battleground queue's join dialog is reopened instead.
function finder.Open()
  local target = U.G("LFTMinimapButton")
  local ok, handler = false, nil
  if target and target.GetScript then
    ok, handler = pcall(target.GetScript, target, "OnMouseUp")
  end
  if ok and type(handler) == "function" then
    local oldThis, oldArg1 = this, arg1
    this, arg1 = target, "LeftButton"
    pcall(handler, target, "LeftButton")
    this, arg1 = oldThis, oldArg1
  else
    local index = finder.Queued()
    local show = U.G("ShowBattlefieldList")
    if index and type(show) == "function" then pcall(show, index) end
  end
  finder.Sync()
end

-- Held pressed while queued. Writes only on a change.
function finder.Sync()
  local button = finder.button
  if not button or not modernWow.enabled then return end
  finder.queue = finder.Queued()
  local queued = finder.queue ~= nil

  if queued ~= finder.locked then
    finder.locked = queued
    if queued then
      pcall(button.SetButtonState, button, "PUSHED", 1)
    else
      pcall(button.SetButtonState, button, "NORMAL")
    end
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
  local gap = size.Gap()
  local skinned = modernWow.Active()
  local x = 0
  local buttonWidth = skinned and modernWow.Token().width * size.ButtonScale()

  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local entry = buttons[name]
    if entry and entry.button and not entry.excluded then
      local button = entry.button
      pcall(button.ClearAllPoints, button)
      if prev then
        pcall(button.SetPoint, button, "LEFT", prev, "RIGHT", gap, 0)
      else
        pcall(button.SetPoint, button, "LEFT", anchor, "LEFT", 0, 0)
      end
      prev = button

      -- The plate host follows the same row, from the anchor's own edge: the
      -- row is one uniform width and gap, so its slot is a running sum.
      local skin = modernWow.skins[name]
      if skin and skin.host and buttonWidth then
        pcall(skin.host.ClearAllPoints, skin.host)
        pcall(skin.host.SetPoint, skin.host, "LEFT", anchor, "LEFT", x, 0)
        x = x + buttonWidth + gap
      elseif buttonWidth then
        x = x + buttonWidth + gap
      end
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
    if entry and entry.button and not entry.excluded then
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
  -- The Professions page opens and closes by tab clicks that never reach
  -- UpdateMicroButtons, so the button's held state is checked here too, and
  -- the Retail look follows every button's real state.
  profession.Sync()
  finder.Sync()
  modernWow.SyncAll()
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
    if config and config.enabled then
      AnchorRow()
      profession.Sync()
      finder.Sync()
      modernWow.SyncAll()
    end
  end) and true or false
end

-- Reparents every resolved candidate into the bar, left to right in candidate
-- order, and returns how many were actually available on this client.
local function ArrangeButtons()
  local count = 0
  local i
  local skinned = modernWow.Active()
  local t = modernWow.Token()
  if skinned then modernWow.enabled = true else modernWow.HideSkins() end

  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local entry = buttons[name]
    if entry and entry.button then
      -- Group Finder is part of the Retail row only.
      entry.excluded = name == FINDER and not skinned
    end
    if entry and entry.button and entry.excluded then
      pcall(entry.button.Hide, entry.button)
    elseif entry and entry.button then
      local button = entry.button

      pcall(button.SetParent, button, anchor)
      -- A reparented native button keeps its own strata (MEDIUM), which would
      -- draw it over the bag windows.
      pcall(button.SetFrameStrata, button, "LOW")

      if skinned then
        -- MainMenuBarMicroButton's 32x40 at the row's size, as dimensions at
        -- scale 1 (size.ButtonScale), its hit rect the whole button. The
        -- native art's own bottom inset would otherwise leave most of the
        -- Retail face unclickable.
        local s = size.ButtonScale()
        pcall(button.SetScale, button, 1)
        pcall(button.SetWidth, button, t.width * s)
        pcall(button.SetHeight, button, t.height * s)
        pcall(button.SetHitRectInsets, button, 0, 0, 0, 0)
        if name == PROFESSION then
          profession.Skin(button, true)
        else
          modernWow.SkinButton(name, button)
        end
      else
        pcall(button.SetScale, button, size.ButtonScale())
        if name == PROFESSION then profession.Skin(button, false) end
      end

      pcall(button.Show, button)

      count = count + 1
    end
  end

  -- Anchored after every button is parented and sized, so the row is chained
  -- against final widths.
  AnchorRow()

  if skinned then
    modernWow.HideOverlays()
    -- A button a previous build disabled and dimmed is restored first.
    if finder.button then
      pcall(finder.button.Enable, finder.button)
      pcall(finder.button.SetAlpha, finder.button, 1)
    end
    finder.Sync()
    modernWow.SyncAll()
  end

  return count
end

-- Hands every captured button back to where it came from. Order does not
-- matter here: each entry restores against its own captured relative frame,
-- not against the previous button in the bar.
local function RestoreButtons()
  local i
  modernWow.HideSkins()
  for i = 1, table.getn(BUTTON_NAMES) do
    local entry = buttons[BUTTON_NAMES[i]]
    if BUTTON_NAMES[i] == PROFESSION or BUTTON_NAMES[i] == FINDER then
      -- The addon's own buttons have no stock place to return to.
      if entry and entry.button then pcall(entry.button.Hide, entry.button) end
    elseif entry and entry.button then
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
        -- Geometry the modern-wow path overwrites. The Retail faces are not
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
  -- HUD strata, under the bag windows (U.LowerWindowBelowInterface).
  pcall(anchor.SetFrameStrata, anchor, "LOW")

  U.RegisterMover("microbar", anchor, {
    label = U.L("MOVER_LABEL_MICRO_BAR"),
    default = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -190, y = -70 },
    -- A disabled bar keeps its stored position but offers no drag handle in
    -- edit mode; see core/mover.lua.
    visible = function() return config and config.enabled end,
  })
end

-- Sizes the bar's box to the row exactly: every installed button's width as
-- the client reports it, plus one gap per neighbour pair, so the edit-mode
-- handle -- which covers this box -- spans the whole bar and nothing more.
-- MEASURED (group `microbarvis`, span.v2, 2026-09-28): reported widths match
-- the drawn buttons, so no scale model is applied to them. Sized from the
-- buttons actually installed, so a client missing a candidate gets no dead
-- space.
function size.FitAnchor()
  if not anchor then return end
  local gap = size.Gap()
  local skinned = modernWow.Active()
  local t = modernWow.Token()
  local width, count, i = 0, 0, nil
  for i = 1, table.getn(BUTTON_NAMES) do
    local entry = buttons[BUTTON_NAMES[i]]
    if entry and entry.button and not entry.excluded then
      local ok, value = pcall(entry.button.GetWidth, entry.button)
      width = width + ((ok and tonumber(value)) or entry.width or 28)
      count = count + 1
    end
  end
  if count > 1 then width = width + gap * (count - 1) end

  if skinned then
    anchor:SetHeight(t.height * size.ButtonScale())
  else
    -- Height as well as width, because a modern-wow session that switched the
    -- surface off mid-session would otherwise leave the taller bar behind.
    anchor:SetHeight(HEIGHT * size.Factor())
  end
  if width < MIN_WIDTH then width = MIN_WIDTH end
  anchor:SetWidth(width)
end

-- The slider's live preview: each installed button's size (the Retail row
-- re-sizes its button, plate and icon cells; the native-art row rescales),
-- the gaps and the bar's box. No hook or anchor chain is rebuilt.
function size.Resize()
  if not anchor or not config or not config.enabled then return end
  local s = size.ButtonScale()
  local skinned = modernWow.Active()
  local t = modernWow.Token()
  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local entry = buttons[name]
    if entry and entry.button and not entry.excluded then
      local button = entry.button
      if skinned then
        pcall(button.SetWidth, button, t.width * s)
        pcall(button.SetHeight, button, t.height * s)
        modernWow.SkinButton(name, button)
      else
        pcall(button.SetScale, button, s)
      end
    end
  end
  AnchorRow()
  size.FitAnchor()
end

function size.Set(value)
  EnsureConfig()
  value = tonumber(value) or size.DEFAULT
  if value < size.MIN then value = size.MIN end
  if value > size.MAX then value = size.MAX end
  config.size = value
  size.Resize()
end

-- The micro bar's edit-mode panel (core/moverpanel.lua): one size slider,
-- shown when the bar's handle is selected, under every style that has the
-- bar. Built the way modules/xpbar.lua builds its mover panels.
size.PANEL_SLIDER_WIDTH = 150

function size.BuildPanel(frame, contentTop)
  local pad = U.MoverPanelPad()
  local slider = U.CreateSlider(frame, {
    name = "UnrealUIMicroBarMoverSize",
    text = U.L("MICROBAR_SIZE"),
    width = size.PANEL_SLIDER_WIDTH,
    boxWidth = 60,
    min = size.MIN,
    max = size.MAX,
    step = size.STEP,
    value = size.Percent(),
    onInputStart = function()
      if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
    end,
    onInput = size.Set,
    onChange = size.Set,
  })
  slider.SetPoint("TOPLEFT", frame, "TOPLEFT", pad, contentTop)

  local function Refresh()
    slider.SetValue(size.Percent())
  end
  return { slider }, Refresh
end

function size.RegisterPanel()
  if type(U.RegisterMoverPanel) ~= "function" then return end
  U.RegisterMoverPanel("microbar", {
    name = "UnrealUIMicroBarMoverSettings",
    width = size.PANEL_SLIDER_WIDTH + U.MoverPanelPad() * 2 + 30,
    height = 112,
    build = size.BuildPanel,
    title = function() return U.L("MOVER_LABEL_MICRO_BAR") end,
    -- Resizing a bar must not move the slider being dragged.
    preferVertical = true,
    available = function() return config and config.enabled and true or false end,
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

  -- Created before the capture pass so they resolve by name like the rest.
  profession.Create()
  finder.Create()

  local i
  for i = 1, table.getn(BUTTON_NAMES) do
    local name = BUTTON_NAMES[i]
    local button = U.G(name)
    if button then CaptureOriginal(name, button) end
  end

  local count = ArrangeButtons()
  InstallNativeUpdateHook()
  profession.HookSpellbookClick()
  if count > 0 then
    U.RegisterUpdate(DRIFT_ID, DRIFT_INTERVAL, WatchRow)
  else
    U.UnregisterUpdate(DRIFT_ID)
  end

  size.FitAnchor()
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
-- right edge, which must be the Retail padding for every pair under the skinned
-- path. A uniform list means the layout is correct and the perceived gap is
-- the glyph art's own transparent margin; a single odd entry means something
-- re-anchored or resized that one button after ArrangeButtons ran.
function U.MicroBarReport()
  local report = {
    enabled = config and config.enabled,
    skin = (modernWow.Active() and "modern-wow") or "native",
    gap = size.Gap(),
    found = {}, missing = {}, geom = {},
  }
  -- Where the bar itself is, so "the bar is not visible" can be told apart
  -- as hidden, off screen, or drawn with no art.
  if anchor then
    local okS, shown = pcall(anchor.IsShown, anchor)
    local okV, visible = pcall(anchor.IsVisible, anchor)
    local okL, left = pcall(anchor.GetLeft, anchor)
    local okT, top = pcall(anchor.GetTop, anchor)
    local okW, width = pcall(anchor.GetWidth, anchor)
    report.anchor = {
      shown = okS and shown and true or false,
      visible = okV and visible and true or false,
      left = okL and tonumber(left) or nil,
      top = okT and tonumber(top) or nil,
      width = okW and tonumber(width) or nil,
    }
  end
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
      local visibleOk, visible = pcall(button.IsVisible, button)
      local skin = modernWow.skins[name]
      local plateOk, plateShown = false, nil
      if skin and skin.plate then
        plateOk, plateShown = pcall(skin.plate.IsVisible, skin.plate)
      end

      table.insert(report.geom, {
        visible = visibleOk and visible and true or false,
        plate = (plateOk and (plateShown and "shown" or "hidden")) or "none",
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
  size.RegisterPanel()
end

function MB:OnEnable()
  EnsureConfig()
  local nativeMain = nil
  if type(U.ActionBarUsesNativeMainMenuBar) == "function" then
    nativeMain = U.ActionBarUsesNativeMainMenuBar()
  elseif type(U.ThemeStyleUsesNativeMainMenuBar) == "function" then
    nativeMain = U.ThemeStyleUsesNativeMainMenuBar()
  end
  if nativeMain then return end
  if not anchor then Build() end
  Apply()
end
