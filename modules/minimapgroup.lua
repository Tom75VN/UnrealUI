-- unrealUI :: modules/minimapgroup.lua
--
-- Grouped minimap icons (user request, 2026-11-26, as PandaUI). With "Group
-- minimap icons" on, the icons around the minimap move into one flyout that a
-- single launcher icon on the rim opens. The player ticks the icons to keep
-- around the minimap instead; every other one joins the group.
--
-- Ported from PandaUI's modules/minimap.lua "Grouped icons" (WORKING_SOURCE on
-- another client, never runtime evidence here). Candidates are the client's
-- own round minimap icons -- MiniMapTrackingFrame, MiniMapMeetingStoneFrame,
-- MiniMapBattlefieldFrame and LFTMinimapButton, all Minimap children on this
-- client (behavior.json / facing.minimap_arrow_children.v1) -- plus other
-- addons' minimap buttons, found the way pfUI's addonbuttons module finds
-- them: named Minimap / MinimapBackdrop children up to 40 units with a click
-- or mouse script. That is one level of GetChildren on two frames, run when
-- grouping is applied and when a settings view lists the icons, never a
-- recursive walk.
--
-- MiniMapMailFrame is left out: its letter is unrealUI's own flipbook drawn
-- on UIParent (modules/minimap.lua), which would sit under the flyout.
--
-- The icons stay their owners' frames. Parent, strata, level and anchors are
-- saved on capture and restored on release. A reparent this client ignores
-- (it did for MinimapZoneTextButton, 2026-09-14) is read back by name, and
-- that icon simply stays on the map.
--
-- One table, `grp`, holds everything: modules/minimap.lua is near the local
-- budget and owns the lifecycle, calling U.MinimapGroup from its OnEnable,
-- settings page and edit-mode panel.

local U = UnrealUI
local M = U.media

local grp = {
  saved = {},
  found = {},
  FLYOUT_NAME = "UnrealUIMinimapGroupFlyout",
  LAUNCHER_NAME = "UnrealUIMinimapGroupButton",
  updateId = "minimap.group.flyout",
  -- The client's own icons, in the order they are listed.
  NATIVE = {
    "UnrealUISettingsButton", "MiniMapTrackingFrame", "MiniMapMeetingStoneFrame",
    "MiniMapBattlefieldFrame", "LFTMinimapButton",
  },
  -- Shown as written: the addon's own name.
  PLAIN_LABELS = { UnrealUISettingsButton = "UnrealUI" },
  LABELS = {
    MiniMapTrackingFrame = "MINIMAP_ICON_TRACKING",
    MiniMapMeetingStoneFrame = "MINIMAP_ICON_MEETING_STONE",
    MiniMapBattlefieldFrame = "MINIMAP_ICON_BATTLEFIELD",
    LFTMinimapButton = "MINIMAP_ICON_GROUP_FINDER",
  },
  -- Lower-case name prefixes of Minimap children that are not icons to group:
  -- map pins and notes (pfUI's ignore list), the map's own controls, the
  -- mail letter, and this suite's own frames.
  NOT_ICONS = {
    "note", "jquest", "naut_", "minimapicon", "gathermatepin", "westpointer",
    "chinchilla_", "smartminimapzoom", "questienote", "smm", "pfminimappin",
    "gathernote", "mininotepoi", "fwgminimappoi", "reciperadarminimapicon",
    "cartographernotespoi", "minimapzoom", "minimapping", "minimaptoggle",
    "minimapworldmap", "minimapbackdrop", "minimapmail", "unrealui",
    "unrealquestminimappin",
  },
}
U.MinimapGroup = grp

function grp.Config()
  local cfg = U.ModuleConfig("minimap", {
    groupIcons = false,
    groupAngle = M.minimapGroup.defaultAngle,
  })
  if type(cfg.keepIcons) ~= "table" then cfg.keepIcons = {} end
  return cfg
end

function grp.On()
  return grp.Config().groupIcons and true or false
end

-- Whether the icon stays around the minimap rather than joining the group.
function grp.Kept(name)
  return grp.Config().keepIcons[name] and true or false
end

function grp.FrameName(frame)
  local ok, name = pcall(frame.GetName, frame)
  if ok and type(name) == "string" then return name end
  return nil
end

function grp.IsNative(name)
  local i
  for i = 1, table.getn(grp.NATIVE) do
    if grp.NATIVE[i] == name then return true end
  end
  return false
end

-- Whether a Minimap child looks like an addon's minimap button.
function grp.LooksLikeButton(frame)
  local name = grp.FrameName(frame)
  if not name or grp.IsNative(name) then return false end
  local lower = string.lower(name)
  local i
  for i = 1, table.getn(grp.NOT_ICONS) do
    if string.find(lower, grp.NOT_ICONS[i], 1, true) == 1 then return false end
  end
  local wOk, width = pcall(frame.GetWidth, frame)
  local hOk, height = pcall(frame.GetHeight, frame)
  local max = M.minimapGroup.maxButtonSize
  if not wOk or not hOk or type(width) ~= "number" or type(height) ~= "number" or
     width > max or height > max then
    return false
  end
  local function Has(script)
    local ok, handler = pcall(frame.GetScript, frame, script)
    return ok and type(handler) == "function"
  end
  local typeOk, isButton = pcall(frame.IsObjectType, frame, "Button")
  if typeOk and isButton then
    return Has("OnClick") or Has("OnMouseDown") or Has("OnMouseUp")
  end
  if string.find(lower, "icon", 1, true) or string.find(lower, "button", 1, true) then
    return Has("OnMouseDown") or Has("OnMouseUp")
  end
  return false
end

-- Adds newly created addon buttons to grp.found. Captured buttons are flyout
-- children now, so they are never lost from the list.
function grp.Scan()
  local known = {}
  local i, j
  for i = 1, table.getn(grp.found) do known[grp.found[i]] = true end
  local holders = { U.G("Minimap"), U.G("MinimapBackdrop") }
  for i = 1, 2 do
    local holder = holders[i]
    if holder then
      local ok, children = pcall(function() return { holder:GetChildren() } end)
      if ok and type(children) == "table" then
        for j = 1, table.getn(children) do
          local child = children[j]
          if grp.LooksLikeButton(child) then
            local name = grp.FrameName(child)
            if not known[name] then
              known[name] = true
              table.insert(grp.found, name)
            end
          end
        end
      end
    end
  end
end

-- Every icon that can join the group, the client's own first.
function grp.Candidates()
  local list = {}
  local i
  for i = 1, table.getn(grp.NATIVE) do
    if U.G(grp.NATIVE[i]) then table.insert(list, grp.NATIVE[i]) end
  end
  for i = 1, table.getn(grp.found) do
    if U.G(grp.found[i]) then table.insert(list, grp.found[i]) end
  end
  return list
end

function grp.Label(name)
  if grp.PLAIN_LABELS[name] then return grp.PLAIN_LABELS[name] end
  local key = grp.LABELS[name]
  if key then return U.L(key) end
  -- LibDBIcon-style names carry a library prefix before the addon's name.
  local short = string.gsub(name, "^LibDBIcon10_", "")
  return short
end

-- ---------------------------------------------------------------------------
-- Flyout
-- ---------------------------------------------------------------------------

-- The theme's popup surface: the Modern WoW dropdown list under modern-wow,
-- the flat panel everywhere else.
function grp.Build()
  if grp.flyout then return grp.flyout end
  local modernWow = U.GetActiveThemeStyle() == "modern-wow" and
                    type(U.ModernWowBuildThinBorder) == "function"
  local flyout
  if modernWow then
    local mw = M.modernWow.dropdown
    flyout = U.CreatePanel(UIParent, {
      name = grp.FLYOUT_NAME, width = 100, height = 40,
      background = { 0, 0, 0, 0 }, border = false,
    })
    local fill = flyout:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture(M.texture.plain)
    U.SetColor(fill, M.Unpack(mw.listFill))
    if type(U.ModernWowThinBorderFill) == "function" then
      U.ModernWowThinBorderFill(fill, flyout, mw.borderSize)
    else
      fill:SetAllPoints(flyout)
    end
    U.ModernWowBuildThinBorder(flyout, mw.borderSize)
  else
    flyout = U.CreatePanel(UIParent, { name = grp.FLYOUT_NAME, width = 100, height = 40 })
  end
  pcall(flyout.SetFrameStrata, flyout, "DIALOG")
  pcall(flyout.EnableMouse, flyout, true)
  pcall(flyout.SetClampedToScreen, flyout, true)
  flyout:SetScript("OnShow", function()
    grp.Layout()
    U.RegisterUpdate(grp.updateId, 0.5, grp.Layout)
  end)
  flyout:SetScript("OnHide", function() U.UnregisterUpdate(grp.updateId) end)
  flyout:Hide()
  local special = U.G("UISpecialFrames")
  if type(special) == "table" then table.insert(special, grp.FLYOUT_NAME) end
  grp.flyout = flyout
  return flyout
end

-- Whether a frame's centre is in the upper / right half of the screen.
function grp.ScreenHalves(frame)
  local ok, cx, cy = pcall(frame.GetCenter, frame)
  local scaleOk, scale = pcall(frame.GetEffectiveScale, frame)
  local uiOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
  if not ok or not scaleOk or not uiOk or type(cx) ~= "number" or
     type(cy) ~= "number" or type(scale) ~= "number" or type(uiScale) ~= "number" then
    return true, true
  end
  local top = cy * scale > UIParent:GetHeight() * uiScale / 2
  local right = cx * scale > UIParent:GetWidth() * uiScale / 2
  return top, right
end

-- Lays the members the client currently shows in rows, then hangs the flyout
-- off the launcher toward the middle of the screen. Re-run every half second
-- while open, so an icon the client shows or hides meanwhile is picked up;
-- nothing is re-anchored unless the shown set changed.
function grp.Layout()
  local flyout, launcher = grp.flyout, grp.launcher
  if not flyout or not launcher then return end

  local shown = {}
  local signature = ""
  local name
  for name in pairs(grp.saved) do
    local frame = U.G(name)
    local ok, isShown = false, false
    if frame then ok, isShown = pcall(frame.IsShown, frame) end
    if ok and isShown then table.insert(shown, name) end
  end
  table.sort(shown)
  signature = table.concat(shown, ",")
  local count = table.getn(shown)
  if count == 0 then
    grp.signature = nil
    flyout:Hide()
    return
  end
  if signature == grp.signature then return end
  grp.signature = signature

  -- The scale the icons had on the minimap.
  local minimap = U.G("Minimap")
  if minimap then
    local mapOk, mapScale = pcall(minimap.GetEffectiveScale, minimap)
    local uiOk, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
    if mapOk and uiOk and type(mapScale) == "number" and
       type(uiScale) == "number" and uiScale > 0 then
      pcall(flyout.SetScale, flyout, mapScale / uiScale)
    end
  end

  local g = M.minimapGroup
  local columns = math.min(count, g.columns)
  local rows = math.ceil(count / g.columns)
  local step = g.cell + g.gap
  flyout:SetWidth(g.pad * 2 + columns * step - g.gap)
  flyout:SetHeight(g.pad * 2 + rows * step - g.gap)
  local level = flyout:GetFrameLevel()
  local i
  for i = 1, count do
    local frame = U.G(shown[i])
    local row = math.floor((i - 1) / g.columns)
    local column = (i - 1) - row * g.columns
    pcall(frame.SetFrameStrata, frame, "DIALOG")
    pcall(frame.SetFrameLevel, frame, level + 2)
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, "CENTER", flyout, "TOPLEFT",
      g.pad + column * step + g.cell / 2,
      -(g.pad + row * step + g.cell / 2))
  end

  local top, right = grp.ScreenHalves(launcher)
  local vertical = top and "TOP" or "BOTTOM"
  local horizontal = right and "RIGHT" or "LEFT"
  flyout:ClearAllPoints()
  flyout:SetPoint(vertical .. horizontal, launcher,
    (top and "BOTTOM" or "TOP") .. horizontal, 0, top and -2 or 2)
end

function grp.ReadPoints(frame)
  local points = {}
  local countOk, count = pcall(frame.GetNumPoints, frame)
  if not countOk or type(count) ~= "number" then count = 0 end
  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
    if ok and point then
      table.insert(points, { point, relative, relativePoint, x, y })
    end
  end
  return points
end

function grp.Capture(name)
  local frame = U.G(name)
  if not frame or grp.saved[name] then return false end
  local ok, parent = pcall(frame.GetParent, frame)
  if not ok or not parent then return false end
  local state = { parent = parent, points = grp.ReadPoints(frame) }
  local strataOk, strata = pcall(frame.GetFrameStrata, frame)
  if strataOk then state.strata = strata end
  local levelOk, level = pcall(frame.GetFrameLevel, frame)
  if levelOk then state.level = level end

  pcall(frame.SetParent, frame, grp.flyout)
  local nowOk, now = pcall(frame.GetParent, frame)
  if not nowOk or not now or grp.FrameName(now) ~= grp.FLYOUT_NAME then
    -- Left where it was: an icon still parented to the map would draw beside
    -- the launcher whether the flyout is open or not.
    U.Debug("minimap group: " .. name .. " cannot be reparented; kept on the map")
    return false
  end

  -- The owner's own drag would carry the icon out of the flyout.
  local startOk, start = pcall(frame.GetScript, frame, "OnDragStart")
  local stopOk, stop = pcall(frame.GetScript, frame, "OnDragStop")
  if startOk then state.dragStart = start end
  if stopOk then state.dragStop = stop end
  pcall(frame.SetScript, frame, "OnDragStart", nil)
  pcall(frame.SetScript, frame, "OnDragStop", nil)

  grp.saved[name] = state
  grp.signature = nil
  grp.Notify(name, true)
  return true
end

-- UnrealUI's own settings button (modules/minimap.lua) keeps its click and
-- drag on a separate UIParent input, which has to be raised over the flyout
-- and kept off the rim while the button is grouped.
function grp.Notify(name, grouped)
  if name == "UnrealUISettingsButton" and
     type(U.MinimapSettingsButtonGrouped) == "function" then
    U.MinimapSettingsButtonGrouped(grouped)
  end
end

function grp.Release(name)
  local frame = U.G(name)
  local state = grp.saved[name]
  grp.saved[name] = nil
  grp.signature = nil
  if not frame or not state then return end
  pcall(frame.SetParent, frame, state.parent)
  if state.strata then pcall(frame.SetFrameStrata, frame, state.strata) end
  if state.level then pcall(frame.SetFrameLevel, frame, state.level) end
  if state.dragStart then pcall(frame.SetScript, frame, "OnDragStart", state.dragStart) end
  if state.dragStop then pcall(frame.SetScript, frame, "OnDragStop", state.dragStop) end
  pcall(frame.ClearAllPoints, frame)
  local i
  for i = 1, table.getn(state.points) do
    pcall(frame.SetPoint, frame, unpack(state.points[i]))
  end
  -- PandaUI's client left a shown icon invisible under its restored parent
  -- until it was shown again (its probe minimapgroup.v1); the same re-show is
  -- harmless here.
  local shownOk, shown = pcall(frame.IsShown, frame)
  if shownOk and shown then
    pcall(frame.Hide, frame)
    pcall(frame.Show, frame)
  end
  grp.Notify(name, false)
end

function grp.ReleaseAll()
  local names = {}
  local name
  for name in pairs(grp.saved) do table.insert(names, name) end
  local i
  for i = 1, table.getn(names) do grp.Release(names[i]) end
end

-- Applies the stored choices: captures what should be grouped, releases what
-- should stay on the map, and shows the launcher only while grouping is on.
function grp.Apply()
  if not grp.launcher then return end
  local on = grp.On()
  if on then
    grp.Build()
    grp.Scan()
  end

  local candidates = grp.Candidates()
  local i
  for i = 1, table.getn(candidates) do
    local name = candidates[i]
    if on and not grp.Kept(name) then
      grp.Capture(name)
    elseif grp.saved[name] then
      grp.Release(name)
    end
  end

  if on then
    grp.PlaceLauncher()
    grp.launcher:Show()
    if grp.flyout:IsShown() then grp.Layout() end
  else
    grp.launcher:Hide()
    if grp.flyout then grp.flyout:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- Launcher
-- ---------------------------------------------------------------------------

function grp.Angle()
  local angle = tonumber(grp.Config().groupAngle)
  return angle or M.minimapGroup.defaultAngle
end

-- On the rim at the stored angle; left alone while the player drags it.
function grp.PlaceLauncher()
  local button = grp.launcher
  if not button then return end
  if grp.drag and grp.drag.IsDragging() then return end
  if type(U.MinimapRimPlace) == "function" and
     U.MinimapRimPlace(button, grp.Angle()) then
    return
  end
  local minimap = U.G("Minimap")
  pcall(button.ClearAllPoints, button)
  if minimap then
    button:SetPoint("RIGHT", minimap, "LEFT", 0, 0)
  else
    button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
  end
end

function grp.ToggleFlyout()
  local flyout = grp.Build()
  if flyout:IsShown() then
    flyout:Hide()
  else
    grp.signature = nil
    flyout:Show()
  end
end

-- Two layers, as the settings button (modules/minimap.lua): `button` is the
-- visible icon and takes no mouse; U.MinimapRimDraggable gives it a UIParent
-- input that clicks it open and drags it around the rim. Dragging the visible
-- frame itself loses the release on this client (knowledge.json /
-- widgets.thumb_reposition_during_drag_breaks_drag).
function grp.CreateLauncher()
  if grp.launcher then return grp.launcher end
  local minimap = U.G("Minimap")
  local g = M.minimapGroup
  local button = CreateFrame("Frame", grp.LAUNCHER_NAME, minimap or UIParent)
  button:SetWidth(g.size)
  button:SetHeight(g.size)
  pcall(button.EnableMouse, button, false)
  if minimap then
    local ok, level = pcall(minimap.GetFrameLevel, minimap)
    if ok and type(level) == "number" then
      pcall(button.SetFrameLevel, button, level + 5)
    end
  end

  local face = button:CreateTexture(nil, "BACKGROUND")
  face:SetWidth(g.faceSize)
  face:SetHeight(g.faceSize)
  face:SetPoint("TOPLEFT", button, "TOPLEFT", g.faceX, g.faceY)
  pcall(face.SetTexture, face, g.face)
  pcall(face.SetTexCoord, face, 0.08, 0.92, 0.08, 0.92)
  button.face = face
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetWidth(g.ringSize)
  ring:SetHeight(g.ringSize)
  ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  pcall(ring.SetTexture, ring, g.ring)
  -- Shown by the input's hover: this frame takes no mouse of its own.
  local glow = button:CreateTexture(nil, "OVERLAY")
  glow:SetAllPoints(button)
  pcall(glow.SetTexture, glow, g.highlight)
  pcall(glow.SetBlendMode, glow, "ADD")
  glow:Hide()

  button:Hide()
  grp.launcher = button

  if type(U.MinimapRimDraggable) == "function" then
    grp.input, grp.drag = U.MinimapRimDraggable(button, {
      name = grp.LAUNCHER_NAME .. "Input",
      updateId = "minimap.group.drag",
      getAngle = grp.Angle,
      setAngle = function(angle) grp.Config().groupAngle = angle end,
      onClick = grp.ToggleFlyout,
      onHover = function(on)
        if on then glow:Show() else glow:Hide() end
      end,
      onPress = function(on)
        local shade = on and 0.75 or 1
        pcall(face.SetVertexColor, face, shade, shade, shade, 1)
      end,
      -- The flyout hangs off the launcher; it reopens where the icon lands.
      onDragStart = function()
        if grp.flyout then grp.flyout:Hide() end
      end,
    })
  end

  -- /uui reset puts the launcher back at its default angle.
  if type(U.OnPositionReset) == "function" then
    U.OnPositionReset(function()
      grp.Config().groupAngle = M.minimapGroup.defaultAngle
      grp.PlaceLauncher()
      return true
    end)
  end

  grp.PlaceLauncher()
  return button
end

-- Called once from modules/minimap.lua's OnEnable, after the map is dressed.
-- Other addons create their minimap buttons while loading; by entering the
-- world they exist and can join the group.
function grp.Enable()
  grp.CreateLauncher()
  grp.Apply()
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local ok, err = pcall(grp.Apply)
    if not ok then U.Error("minimap grouping: " .. tostring(err)) end
  end)
end

-- ---------------------------------------------------------------------------
-- Controls, shared by the Minimap settings page and the minimap's edit-mode
-- panel: the group switch, then one "keep on the minimap" checkbox per icon in
-- two columns. Icons are listed as found when the view is first built.
-- ---------------------------------------------------------------------------
grp.ROW_STEP = 22

-- The icons a view lists, scanned fresh.
function grp.ListedIcons()
  grp.Scan()
  return grp.Candidates()
end

-- Built in `parent` below `anchor` (TOPLEFT to its TOPLEFT, `y` down). Returns
-- widgets, a refresh function and the height the controls take from `y`.
-- `description` adds the settings page's help text under the switch.
function grp.BuildControls(parent, anchor, y, width, prefix, description)
  local widgets, rows = {}, {}
  local icons = grp.ListedIcons()
  local columnWidth = math.floor(width / 2)

  local switch = U.CreateCheckbox(parent, {
    name = prefix .. "Group",
    text = U.L("SETTINGS_MINIMAP_GROUP"),
    textWidth = width - 20,
    value = grp.On(),
    onChange = function(value)
      grp.Config().groupIcons = value and true or false
      grp.Apply()
      grp.RefreshViews()
    end,
  })
  switch.SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
  table.insert(widgets, switch)

  local drop = 0
  if description then
    local hint = U.CreateSettingsLabel(parent, {
      size = M.fontSize.small,
      color = M.color.textDim,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = width,
    })
    if hint then
      U.AnchorSettingsDescription(hint, switch.box)
      hint:SetText(U.L("SETTINGS_MINIMAP_GROUP_HINT"))
      table.insert(widgets, hint)
      drop = U.SettingsDescriptionDrop(hint)
    end
  end

  local captionY = -(14 + drop + 10)
  local caption = U.CreateSettingsLabel(parent, {
    size = M.fontSize.small,
    color = M.color.accent,
    inherits = "GameFontNormalSmall",
    width = width,
    height = 14,
    justify = "LEFT",
  })
  if caption then
    caption:SetPoint("TOPLEFT", switch.box, "TOPLEFT", 0, captionY)
    caption:SetText(U.L("SETTINGS_MINIMAP_GROUP_KEEP"))
    table.insert(widgets, caption)
  end

  local listY = captionY - 18
  local i
  for i = 1, table.getn(icons) do
    local name = icons[i]
    local row = math.floor((i - 1) / 2)
    local column = (i - 1) - row * 2
    local control = U.CreateCheckbox(parent, {
      name = prefix .. "Icon" .. i,
      text = grp.Label(name),
      textWidth = columnWidth - 26,
      value = grp.Kept(name),
      onChange = function(value)
        grp.Config().keepIcons[name] = value and true or nil
        grp.Apply()
        grp.RefreshViews()
      end,
    })
    control.SetPoint("TOPLEFT", switch.box, "TOPLEFT",
                     column * columnWidth, listY - row * grp.ROW_STEP)
    control.SetEnabled(grp.On())
    table.insert(rows, { control = control, name = name })
    table.insert(widgets, control)
  end

  local listHeight = 14
  if table.getn(icons) == 0 then
    local none = U.CreateSettingsLabel(parent, {
      size = M.fontSize.small,
      color = M.color.textDim,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = width,
    })
    if none then
      none:SetPoint("TOPLEFT", switch.box, "TOPLEFT", 0, listY)
      none:SetText(U.L("SETTINGS_MINIMAP_GROUP_NONE"))
      table.insert(widgets, none)
    end
  else
    listHeight = math.ceil(table.getn(icons) / 2) * grp.ROW_STEP - 8
  end

  local function Refresh()
    local on = grp.On()
    switch.SetValue(on)
    local n
    for n = 1, table.getn(rows) do
      rows[n].control.SetValue(grp.Kept(rows[n].name))
      rows[n].control.SetEnabled(on)
    end
  end

  return widgets, Refresh, -listY + listHeight
end

-- The settings page and the edit-mode panel show the same stored choices, so
-- a change in either tells the other to re-read them.
function grp.RefreshViews()
  if type(U.RefreshSettingsPage) == "function" then U.RefreshSettingsPage("minimap") end
  if type(U.RefreshMoverPanel) == "function" then U.RefreshMoverPanel("minimap") end
end

-- The height the controls will take for the icons found now, for a panel that
-- has to know its size before building them.
function grp.ControlsHeight()
  local count = table.getn(grp.ListedIcons())
  local rows = math.max(1, math.ceil(count / 2))
  return 14 + 10 + 18 + rows * grp.ROW_STEP - 8
end
