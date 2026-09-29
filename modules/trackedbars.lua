-- unrealUI :: modules/trackedbars.lua
--
-- Tracked Bars: Retail's Cooldown Manager buff bars (BuffBarCooldownViewer,
-- RetailFrameXML 12.1.0.69933 Blizzard_CooldownViewer). One bar per aura --
-- icon, name, stack count, remaining time and a draining fill with its pip --
-- stacked downwards from one edit-mode anchor.
--
-- Retail fills the list from C_CooldownViewer, a server-provided and
-- player-curated spell list this client does not have. By user decision
-- (2026-09-29) every helpful aura on the player that reports a remaining time
-- is tracked, in the order it was first seen this session. Kept from Retail:
--   * CooldownViewerBuffBarItemTemplate's item (geometry in M.trackedBars);
--   * the settings EditModeCooldownViewerSystemMixin:ShouldShowSetting leaves
--     the BuffBar system -- Size, Padding, Bar Width, Opacity, Visibility, Bar
--     Content, Hide When Inactive, Show Timer, Show Tooltips -- with Retail's
--     ranges and Mainline defaults;
--   * edit mode shows every tracked bar, inactive ones too, padded to
--     CooldownViewerMixin:GetItemCount's minimum of two with paused
--     placeholders.
-- Adapted: an inactive bar is one whose aura dropped this session, and with
-- Hide When Inactive on the remaining bars close up instead of keeping
-- Retail's fixed slots, since nobody arranged this list.
--
-- Evidence: GetPlayerBuff and its Texture/Applications/TimeLeft companions
-- exist and GetPlayerBuff answers -1 for an empty slot (probe
-- auras.player_getplayerbuff_*_timers.v1), but a live remaining time is not
-- runtime verified (knowledge.json / auras.no_native_debuff_expiry_time): an
-- aura that reports none simply gets no bar. The name comes from a private
-- scanner tooltip -- GameTooltip:SetPlayerBuff (documented) first, the
-- measured SetUnitBuff("player", n) read second.

local U = UnrealUI
local M = U.media

local TB = U.RegisterModule("trackedbars")

local MOVER_ID = "trackedbars"
local SCANNER_NAME = "UnrealUITrackedBarScanner"
local PANEL_COLUMN = 168
local PANEL_CONTROL_WIDTH = 150
local PANEL_CONTENT_WIDTH = 318

local tb = {
  config = nil, preview = {},
  anchor = nil, items = {}, display = {}, layoutKey = nil,
  entries = {}, byKey = {}, names = {}, pass = 0, primed = false,
  modernWow = false, editing = false, contentHidden = false,
  ticking = false, tooltipItem = nil,
  scanner = nil, scannerBuilt = false,
  samples = {},
  choices = {
    visibility = { always = true, combat = true, hidden = true },
    content = { iconName = true, icon = true, name = true },
  },
  flags = { enabled = true, hideInactive = true, showTimer = true, showTooltips = true },
}

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function tb.Config()
  if not tb.config then
    local limit = M.trackedBars.limit
    tb.config = U.ModuleConfig("trackedbars", {
      size = limit.size.default,
      padding = limit.padding.default,
      width = limit.width.default,
      opacity = limit.opacity.default,
      visibility = "always",
      content = "iconName",
      enabled = true,
      hideInactive = true,
      showTimer = true,
      showTooltips = true,
    })
  end
  return tb.config
end

function tb.Clamp(key, value)
  local limit = M.trackedBars.limit[key]
  value = tonumber(value) or limit.default
  if value < limit.min then value = limit.min end
  if value > limit.max then value = limit.max end
  return math.floor((value - limit.min) / limit.step + 0.5) * limit.step +
         limit.min
end

function U.GetTrackedBarsSetting(key)
  local cfg = tb.Config()
  if M.trackedBars.limit[key] then return tb.Clamp(key, cfg[key]) end
  if tb.choices[key] then
    if tb.choices[key][cfg[key]] then return cfg[key] end
    return key == "visibility" and "always" or "iconName"
  end
  if tb.flags[key] then return cfg[key] and true or false end
  return nil
end

-- A slider's live preview wins over the stored value until its drag ends.
function tb.Setting(key)
  local value = tb.preview[key]
  if value ~= nil then return tb.Clamp(key, value) end
  return U.GetTrackedBarsSetting(key)
end

function U.SetTrackedBarsSetting(key, value)
  local cfg = tb.Config()
  if M.trackedBars.limit[key] then
    if not tonumber(value) then return false end
    cfg[key] = tb.Clamp(key, value)
    tb.preview[key] = nil
  elseif tb.choices[key] then
    if not tb.choices[key][value] then return false end
    cfg[key] = value
  elseif tb.flags[key] then
    cfg[key] = value and true or false
  else
    return false
  end

  tb.Layout(true)
  if type(U.RefreshMoverPanel) == "function" then
    U.RefreshMoverPanel(MOVER_ID)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Aura source
-- ---------------------------------------------------------------------------
function tb.Call(name, a1, a2)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1 = pcall(fn, a1, a2)
  if not ok then return nil end
  return r1
end

function tb.Now()
  return tonumber(tb.Call("GetTime")) or 0
end

function tb.ReadScanner(tip, setter, a1, a2)
  if type(setter) ~= "function" then return nil end
  U.ArmScannerTooltip(tip)
  local text = nil
  if pcall(setter, tip, a1, a2) then
    local global = SCANNER_NAME .. "TextLeft1"
    local line = _G and _G[global] or U.G(global)
    if line and type(line.GetText) == "function" then
      local ok, value = pcall(line.GetText, line)
      if ok and type(value) == "string" and value ~= "" then text = value end
    end
  end
  U.ReleaseScannerTooltip(tip)
  return text
end

function tb.ScanName(buffIndex, order)
  if not tb.scannerBuilt then
    tb.scannerBuilt = true
    tb.scanner = U.CreateScannerTooltip(SCANNER_NAME, UIParent)
  end
  local tip = tb.scanner
  if not tip then return nil end
  return tb.ReadScanner(tip, tip.SetPlayerBuff, buffIndex) or
         tb.ReadScanner(tip, tip.SetUnitBuff, "player", order)
end

-- The list is capped at IconLimit's maximum. A new aura displaces the oldest
-- inactive bar; with every bar live it is not tracked.
function tb.AddEntry(key)
  local entries = tb.entries
  if table.getn(entries) >= M.trackedBars.maxBars then
    local drop, i = nil, nil
    for i = 1, table.getn(entries) do
      if not entries[i].active then
        drop = i
        break
      end
    end
    if not drop then return nil end
    tb.byKey[entries[drop].key] = nil
    table.remove(entries, drop)
  end

  local entry = { key = key }
  table.insert(entries, entry)
  tb.byKey[key] = entry
  return entry
end

-- The client reports remaining time, never the total. A bar seen being
-- applied, reapplied (its remaining time jumped up) or coming back takes that
-- remaining time as its total. One already running at the first scan takes
-- core/auradata.lua's duration when that is longer, else starts full, as
-- modules/auras.lua's native timers do.
function tb.Track(buffIndex, order, texture, timeLeft, now)
  local cached = tb.names[buffIndex]
  if not cached or cached.texture ~= texture then
    cached = { texture = texture, name = tb.ScanName(buffIndex, order) }
    tb.names[buffIndex] = cached
  end
  cached.pass = tb.pass

  local key = cached.name or texture
  local entry = tb.byKey[key]
  if entry and entry.seen == tb.pass then return end

  if not entry then
    entry = tb.AddEntry(key)
    if not entry then return end
    entry.duration = timeLeft
    if not tb.primed and cached.name and type(U.AuraDuration) == "function" then
      local tabled = tonumber(U.AuraDuration(cached.name))
      if tabled and tabled > timeLeft then entry.duration = tabled end
    end
  elseif not entry.active then
    entry.duration = timeLeft
  elseif timeLeft > (entry.expires or now) - now + 1 then
    entry.duration = timeLeft
  end
  if timeLeft > (entry.duration or 0) then entry.duration = timeLeft end

  entry.name = cached.name
  entry.texture = texture
  entry.buffIndex = buffIndex
  entry.count = tonumber(tb.Call("GetPlayerBuffApplications", buffIndex)) or 0
  entry.expires = now + timeLeft
  entry.active = true
  entry.seen = tb.pass
end

function tb.Scan()
  local get = U.G("GetPlayerBuff")
  if type(get) ~= "function" then return end

  local base = tonumber(U.G("PLAYER_BUFF_START_ID")) or 0
  local now = tb.Now()
  tb.pass = tb.pass + 1

  local order, i = 0, nil
  for i = 1, 32 do
    local ok, buffIndex = pcall(get, base + i - 1, "HELPFUL")
    buffIndex = ok and tonumber(buffIndex) or nil
    if buffIndex and buffIndex >= 0 then
      order = order + 1
      local timeLeft = tonumber(tb.Call("GetPlayerBuffTimeLeft", buffIndex)) or 0
      local texture = tb.Call("GetPlayerBuffTexture", buffIndex)
      if timeLeft > 0 and type(texture) == "string" and texture ~= "" then
        tb.Track(buffIndex, order, texture, timeLeft, now)
      end
    end
  end

  for i = 1, table.getn(tb.entries) do
    local entry = tb.entries[i]
    if entry.seen ~= tb.pass then
      entry.active = false
      entry.buffIndex = nil
    end
  end

  local index, cached
  for index, cached in pairs(tb.names) do
    if cached.pass ~= tb.pass then tb.names[index] = nil end
  end
  tb.primed = true
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------
function tb.Cell(texture, cell)
  local art = M.modernWow.trackedBars
  texture:SetTexture(art.texture)
  texture:SetTexCoord(cell[1] / art.sheet[1], cell[3] / art.sheet[1],
                      cell[2] / art.sheet[2], cell[4] / art.sheet[2])
end

function tb.DressFlat(item)
  local inset = U.BorderSize()
  U.CreateBackdrop(item.iconFrame, { background = { 0, 0, 0, 0 } })
  item.icon:SetPoint("TOPLEFT", item.iconFrame, "TOPLEFT", inset, -inset)
  item.icon:SetPoint("BOTTOMRIGHT", item.iconFrame, "BOTTOMRIGHT", -inset, inset)

  U.CreateBackdrop(item.bar, { background = M.trackedBars.flat.barBackground })
  item.fill:SetTexture(M.texture.plain)
  item.pip:SetTexture(M.texture.plain)
  U.SetColor(item.pip, M.Unpack(M.trackedBars.flat.pip))
  item.inset = inset
end

function tb.DressModernWow(item)
  local art = M.modernWow.trackedBars
  item.icon:SetAllPoints(item.iconFrame)

  item.barBG = item.bar:CreateTexture(nil, "BACKGROUND")
  tb.Cell(item.barBG, art.barBG)
  tb.Cell(item.fill, art.bar)
  local fill = M.trackedBars.fill
  U.SetColor(item.fill, fill[1], fill[2], fill[3], fill[4] * art.fillAlpha)
  tb.Cell(item.pip, art.pip)
  item.fillCell = art.bar

  item.overlay = item.iconFrame:CreateTexture(nil, "OVERLAY")
  tb.Cell(item.overlay, art.overlay)
  item.inset = 0
end

function tb.Label(parent, justify)
  return U.CreateLabel(parent, {
    size = M.trackedBars.fontSize,
    color = M.color.text,
    inherits = "GameFontHighlightSmall",
    justify = justify,
    shadowOffset = M.compactTextShadowOffset,
    shadowColor = M.color.shadowStrong,
  })
end

function tb.CreateItem()
  local item = CreateFrame("Frame", nil, tb.anchor)

  item.iconFrame = CreateFrame("Frame", nil, item)
  item.icon = item.iconFrame:CreateTexture(nil, "ARTWORK")
  local crop = M.trackedBars.iconCrop
  item.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)

  item.bar = CreateFrame("Frame", nil, item)
  item.fill = item.bar:CreateTexture(nil, "ARTWORK")
  U.SetColor(item.fill, M.Unpack(M.trackedBars.fill))
  item.pip = item.bar:CreateTexture(nil, "OVERLAY")
  item.fill:Hide()
  item.pip:Hide()

  if tb.modernWow then tb.DressModernWow(item) else tb.DressFlat(item) end

  -- Text sits on its own raised layers so no bar or icon art can cover it.
  local level = tonumber(item.bar:GetFrameLevel()) or 1
  local textLayer = CreateFrame("Frame", nil, item.bar)
  textLayer:SetAllPoints(item.bar)
  pcall(textLayer.SetFrameLevel, textLayer, level + 2)
  item.name = tb.Label(textLayer, "LEFT")
  item.duration = tb.Label(textLayer, "RIGHT")

  local countLayer = CreateFrame("Frame", nil, item.iconFrame)
  countLayer:SetAllPoints(item.iconFrame)
  pcall(countLayer.SetFrameLevel, countLayer, level + 2)
  item.count = tb.Label(countLayer, "RIGHT")

  item:SetScript("OnEnter", function() tb.OnEnter(item) end)
  item:SetScript("OnLeave", function() tb.OnLeave(item) end)
  pcall(item.EnableMouse, item, false)
  return item
end

function tb.Metrics()
  local t = M.trackedBars
  local s = tb.Setting("size") / 100
  return {
    scale = s,
    width = t.width * (tb.Setting("width") / 100) * s,
    height = t.height * s,
    icon = (t.bar.height + t.iconExtra) * s,
    barHeight = t.bar.height * s,
    gap = t.bar.gap * s,
    spacing = (tb.Setting("padding") + t.paddingOffset) * s,
    font = math.max(6, math.floor(t.fontSize * s + 0.5)),
  }
end

function tb.SetLabelSize(label, size)
  if not label or label.uuiTrackedSize == size then return end
  label.uuiTrackedSize = size
  U.SetFont(label, size)
  U.SetTextShadow(label, M.compactTextShadowOffset, M.color.shadowStrong)
end

function tb.PlaceItem(item, index, mt, content)
  local t = M.trackedBars
  local s = mt.scale

  item:SetWidth(mt.width)
  item:SetHeight(mt.height)
  item:ClearAllPoints()
  item:SetPoint("TOPLEFT", tb.anchor, "TOPLEFT", 0,
                -(index - 1) * (mt.height + mt.spacing))

  local showIcon = content ~= "name"
  item.iconFrame:SetWidth(mt.icon)
  item.iconFrame:SetHeight(mt.icon)
  item.iconFrame:ClearAllPoints()
  item.iconFrame:SetPoint("LEFT", item, "LEFT", 0, 0)
  if showIcon then item.iconFrame:Show() else item.iconFrame:Hide() end

  local barLeft = showIcon and (mt.icon + mt.gap) or 0
  item.barWidth = math.max(mt.width - barLeft, 1)
  item.bar:ClearAllPoints()
  item.bar:SetPoint("LEFT", item, "LEFT", barLeft, 0)
  item.bar:SetWidth(item.barWidth)
  item.bar:SetHeight(mt.barHeight)

  tb.SetLabelSize(item.name, mt.font)
  tb.SetLabelSize(item.duration, mt.font)
  tb.SetLabelSize(item.count, mt.font)

  if item.name then
    item.name:ClearAllPoints()
    item.name:SetPoint("LEFT", item.bar, "LEFT", t.name.left * s,
                       -t.name.down * s)
    pcall(item.name.SetWidth, item.name,
          math.max(item.barWidth - (t.name.left + t.name.right) * s, 1))
    pcall(item.name.SetHeight, item.name, mt.barHeight)
    if content == "icon" then item.name:Hide() else item.name:Show() end
  end
  if item.duration then
    item.duration:ClearAllPoints()
    item.duration:SetPoint("RIGHT", item.bar, "RIGHT", -t.duration.right * s,
                           -t.duration.down * s)
    pcall(item.duration.SetHeight, item.duration, mt.barHeight)
  end
  if item.count then
    item.count:ClearAllPoints()
    item.count:SetPoint("BOTTOMRIGHT", item.iconFrame, "BOTTOMRIGHT",
                        -t.count.right * s, t.count.bottom * s)
  end

  item.pip:ClearAllPoints()
  if tb.modernWow then
    local art = M.modernWow.trackedBars
    local bg, ov = art.barBGInset, art.overlayInset
    item.barBG:ClearAllPoints()
    item.barBG:SetPoint("TOPLEFT", item.bar, "TOPLEFT", bg.left * s, bg.top * s)
    item.barBG:SetPoint("BOTTOMRIGHT", item.bar, "BOTTOMRIGHT",
                        bg.right * s, bg.bottom * s)
    item.overlay:ClearAllPoints()
    item.overlay:SetPoint("TOPLEFT", item.iconFrame, "TOPLEFT",
                          ov.left * s, ov.top * s)
    item.overlay:SetPoint("BOTTOMRIGHT", item.iconFrame, "BOTTOMRIGHT",
                          ov.right * s, ov.bottom * s)
    item.pip:SetWidth(art.pipSize[1] * s)
    item.pip:SetHeight(art.pipSize[2] * s)
    item.pip:SetPoint("CENTER", item.fill, "RIGHT", 0, art.pipY * s)
  else
    item.pip:SetWidth(M.trackedBars.flat.pipWidth)
    item.pip:SetHeight(math.max(mt.barHeight - 2 * item.inset, 1))
    item.pip:SetPoint("CENTER", item.fill, "RIGHT", 0, 0)
  end
  item.fraction = nil
end

-- The fill is a plain texture sized to its extent, never the StatusBar widget
-- (knowledge.json / statusbar.native_widget_fill_not_laid_out). The Retail
-- atlas cell is cropped by the same fraction, as the swing bar does, so its
-- gradient and end cap are revealed rather than squeezed.
function tb.SetFill(item, fraction, live)
  if item.fraction == fraction and item.live == live then return end
  item.fraction, item.live = fraction, live

  local inset = item.inset or 0
  local extent = (item.barWidth - 2 * inset) * fraction
  if extent < 1 then
    item.fill:Hide()
    item.pip:Hide()
    return
  end

  item.fill:ClearAllPoints()
  item.fill:SetPoint("TOPLEFT", item.bar, "TOPLEFT", inset, -inset)
  item.fill:SetPoint("BOTTOMLEFT", item.bar, "BOTTOMLEFT", inset, inset)
  item.fill:SetWidth(extent)

  local cell = item.fillCell
  if cell then
    local sheet = M.modernWow.trackedBars.sheet
    item.fill:SetTexCoord(cell[1] / sheet[1],
                          (cell[1] + (cell[3] - cell[1]) * fraction) / sheet[1],
                          cell[2] / sheet[2], cell[4] / sheet[2])
  end
  item.fill:Show()
  if live then item.pip:Show() else item.pip:Hide() end
end

-- Seconds keep one decimal as the Cooldown Manager's readout does; minutes
-- and hours are this client's addition, for the half-hour buffs it tracks.
function tb.FormatTime(seconds)
  if seconds < 60 then return string.format("%.1f", seconds) end
  local whole = math.floor(seconds)
  if whole < 3600 then
    return string.format("%d:%02d", math.floor(whole / 60), math.mod(whole, 60))
  end
  return string.format("%d:%02d:%02d", math.floor(whole / 3600),
                       math.floor(math.mod(whole, 3600) / 60),
                       math.mod(whole, 60))
end

function tb.SetText(label, text)
  if not label or label.uuiTrackedText == text then return end
  label.uuiTrackedText = text
  label:SetText(text)
end

function tb.RefreshItem(item, now)
  local entry = item.entry
  if not entry then return end

  local fraction, remaining = 0, 0
  if entry.sample then
    fraction = entry.fraction
    remaining = entry.fraction * M.trackedBars.sampleDuration
  elseif entry.active then
    remaining = math.max((entry.expires or now) - now, 0)
    if (entry.duration or 0) > 0 then fraction = remaining / entry.duration end
  end
  if fraction > 1 then fraction = 1 end
  if fraction < 0 then fraction = 0 end

  local texture = entry.texture or M.trackedBars.sampleIcon
  if item.iconTexture ~= texture then
    item.iconTexture = texture
    item.icon:SetTexture(texture)
  end

  if entry.sample then
    tb.SetText(item.name, U.L("TRACKEDBARS_SAMPLE"))
  else
    tb.SetText(item.name, entry.name or "")
  end
  tb.SetText(item.count, (entry.count or 0) > 1 and tostring(entry.count) or "")
  tb.SetText(item.duration, remaining > 0 and tb.FormatTime(remaining) or "")
  tb.SetFill(item, fraction, remaining > 0)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
function tb.DisplayList()
  local list, i = {}, nil
  local hide = tb.Setting("hideInactive") and not tb.editing
  for i = 1, table.getn(tb.entries) do
    local entry = tb.entries[i]
    if entry.active or not hide then table.insert(list, entry) end
  end
  if tb.editing then
    for i = table.getn(list) + 1, table.getn(tb.samples) do
      table.insert(list, tb.samples[i])
    end
  end
  return list
end

-- Enable off hides the bars everywhere but edit mode, where the anchor must
-- stay reachable to switch them back on.
function tb.ShouldShow()
  if tb.contentHidden then return false end
  if tb.editing then return true end
  if not tb.Setting("enabled") then return false end
  local visibility = tb.Setting("visibility")
  if visibility == "hidden" then return false end
  if visibility == "combat" then
    local fn = U.G("UnitAffectingCombat")
    if type(fn) ~= "function" then return true end
    local ok, value = pcall(fn, "player")
    return ok and value and value ~= 0 and true or false
  end
  return true
end

function tb.UpdateShown()
  if not tb.anchor then return end
  if tb.ShouldShow() then tb.anchor:Show() else tb.anchor:Hide() end
end

function tb.Tick()
  local now, i = tb.Now(), nil
  for i = 1, table.getn(tb.display) do
    local item = tb.items[i]
    if item then tb.RefreshItem(item, now) end
  end
end

function tb.UpdateTicker()
  local need, i = false, nil
  if tb.anchor and tb.anchor:IsShown() then
    for i = 1, table.getn(tb.display) do
      if tb.display[i].active then
        need = true
        break
      end
    end
  end
  if need == tb.ticking then return end
  tb.ticking = need
  if need then
    U.RegisterUpdate("trackedbars.tick", 0.05, tb.Tick)
  else
    U.UnregisterUpdate("trackedbars.tick")
  end
end

-- `force` re-places every item; otherwise the items are only rebuilt when the
-- set of bars or their live state changed since the last pass.
function tb.Layout(force)
  if not tb.anchor then return end

  local list = tb.DisplayList()
  local parts, i = {}, nil
  for i = 1, table.getn(list) do
    table.insert(parts, (list[i].key or "?") .. (list[i].active and "+" or "-"))
  end
  local key = table.concat(parts, "\n")

  if force or key ~= tb.layoutKey then
    tb.layoutKey = key
    tb.display = list

    local mt = tb.Metrics()
    tb.anchor:SetWidth(mt.width)
    local count = table.getn(list)
    tb.anchor:SetHeight(math.max(mt.height,
      count * mt.height + math.max(count - 1, 0) * mt.spacing))

    local content = tb.Setting("content")
    local opacity = tb.Setting("opacity") / 100
    local timer = tb.Setting("showTimer")
    local tooltips = tb.Setting("showTooltips")

    for i = 1, table.getn(list) do
      local item = tb.items[i]
      if not item then
        item = tb.CreateItem()
        tb.items[i] = item
      end
      if item.entry ~= list[i] and tb.tooltipItem == item then
        tb.OnLeave(item)
      end
      item.entry = list[i]
      tb.PlaceItem(item, i, mt, content)
      pcall(item.SetAlpha, item, opacity)
      pcall(item.EnableMouse, item, tooltips and not list[i].sample)
      if item.duration then
        if timer then item.duration:Show() else item.duration:Hide() end
      end
      item:Show()
    end
    for i = table.getn(list) + 1, table.getn(tb.items) do
      if tb.tooltipItem == tb.items[i] then tb.OnLeave(tb.items[i]) end
      tb.items[i].entry = nil
      tb.items[i]:Hide()
    end
  end

  tb.UpdateShown()
  tb.Tick()
  tb.UpdateTicker()
end

function tb.Refresh()
  if not tb.anchor then return end
  if tb.Setting("enabled") and
     not (U.PerfDisabled and U.PerfDisabled("trackedbars")) then
    tb.Scan()
  end
  tb.Layout(false)
end

-- ---------------------------------------------------------------------------
-- Tooltips
--
-- Show Tooltips puts the aura's own tooltip on the game tooltip, the call the
-- native buff buttons make (GameTooltip:SetPlayerBuff, documented).
-- ---------------------------------------------------------------------------
function tb.OnEnter(item)
  local entry = item.entry
  if not entry or entry.sample or not entry.active or not entry.buffIndex then
    return
  end
  if not tb.Setting("showTooltips") then return end
  pcall(GameTooltip.SetOwner, GameTooltip, item, "ANCHOR_RIGHT")
  if not pcall(GameTooltip.SetPlayerBuff, GameTooltip, entry.buffIndex) then
    pcall(GameTooltip.Hide, GameTooltip)
    return
  end
  pcall(GameTooltip.Show, GameTooltip)
  tb.tooltipItem = item
end

function tb.OnLeave(item)
  if tb.tooltipItem ~= item then return end
  tb.tooltipItem = nil
  pcall(GameTooltip.Hide, GameTooltip)
end

-- ---------------------------------------------------------------------------
-- Edit-mode settings
-- ---------------------------------------------------------------------------
function tb.BuildPanel(frame, contentTop)
  local pad = U.MoverPanelPad()
  local widgets, controls = {}, {}

  local function At(control, column, y)
    control.SetPoint("TOPLEFT", frame, "TOPLEFT",
                     pad + column * PANEL_COLUMN, contentTop + y)
    table.insert(widgets, control)
  end

  local function Check(key, textKey, column, y)
    local control = U.CreateCheckbox(frame, {
      name = "UnrealUITrackedBars" .. key,
      text = U.L(textKey),
      textWidth = PANEL_CONTROL_WIDTH - 20,
      value = U.GetTrackedBarsSetting(key),
      onChange = function(value) U.SetTrackedBarsSetting(key, value) end,
    })
    At(control, column, y)
    controls[key] = control
  end

  local function Slider(key, textKey, column, y)
    local limit = M.trackedBars.limit[key]
    local control = U.CreateSlider(frame, {
      name = "UnrealUITrackedBars" .. key,
      text = U.L(textKey),
      width = PANEL_CONTROL_WIDTH,
      boxWidth = 60,
      min = limit.min,
      max = limit.max,
      step = limit.step,
      value = U.GetTrackedBarsSetting(key),
      onInputStart = function()
        if type(U.FreezeMoverPanel) == "function" then U.FreezeMoverPanel() end
      end,
      onInput = function(value)
        tb.preview[key] = value
        tb.Layout(true)
      end,
      onChange = function(value) U.SetTrackedBarsSetting(key, value) end,
    })
    At(control, column, y)
    controls[key] = control
  end

  local function Dropdown(key, textKey, items, column, y)
    local caption = U.CreateSettingsLabel(frame, {
      size = M.fontSize.small,
      color = M.color.accent,
      inherits = "GameFontNormalSmall",
      justify = "LEFT",
      width = PANEL_CONTROL_WIDTH,
    })
    if caption then
      caption:SetPoint("TOPLEFT", frame, "TOPLEFT",
                       pad + column * PANEL_COLUMN, contentTop + y)
      caption:SetText(U.L(textKey))
      table.insert(widgets, caption)
    end
    local control = U.CreateDropdown(frame, {
      name = "UnrealUITrackedBars" .. key,
      width = PANEL_CONTROL_WIDTH,
      height = 24,
      rowHeight = 20,
      value = U.GetTrackedBarsSetting(key),
      items = items,
      onChange = function(value) U.SetTrackedBarsSetting(key, value) end,
    })
    At(control, column, y - 16)
    controls[key] = control
  end

  Check("enabled", "COMMON_ENABLE", 0, 0)
  Check("hideInactive", "TRACKEDBARS_HIDE_INACTIVE", 1, 0)
  Check("showTimer", "TRACKEDBARS_SHOW_TIMER", 0, -22)
  Check("showTooltips", "TRACKEDBARS_SHOW_TOOLTIPS", 1, -22)
  Slider("size", "TRACKEDBARS_SIZE", 0, -64)
  Slider("width", "TRACKEDBARS_WIDTH", 1, -64)
  Slider("padding", "TRACKEDBARS_PADDING", 0, -122)
  Slider("opacity", "TRACKEDBARS_OPACITY", 1, -122)
  Dropdown("visibility", "TRACKEDBARS_VISIBILITY", {
    { value = "always", text = U.L("TRACKEDBARS_VISIBLE_ALWAYS") },
    { value = "combat", text = U.L("TRACKEDBARS_VISIBLE_COMBAT") },
    { value = "hidden", text = U.L("TRACKEDBARS_VISIBLE_HIDDEN") },
  }, 0, -180)
  Dropdown("content", "TRACKEDBARS_CONTENT", {
    { value = "iconName", text = U.L("TRACKEDBARS_CONTENT_ICON_NAME") },
    { value = "icon", text = U.L("TRACKEDBARS_CONTENT_ICON") },
    { value = "name", text = U.L("TRACKEDBARS_CONTENT_NAME") },
  }, 1, -180)

  local function Refresh()
    local key, control
    for key, control in pairs(controls) do
      control.SetValue(U.GetTrackedBarsSetting(key))
    end
  end

  return widgets, Refresh
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
-- Read by modules/modernwow.lua's `trackedbars` surface to confirm the
-- Retail art path was chosen.
function U.TrackedBarsModernWowActive()
  return tb.anchor ~= nil and tb.modernWow
end

function TB:OnInit()
  tb.Config()
  if type(U.RegisterMoverPanel) == "function" then
    U.RegisterMoverPanel(MOVER_ID, {
      name = "UnrealUITrackedBarsMoverSettings",
      width = PANEL_CONTENT_WIDTH + U.MoverPanelPad() * 2,
      height = 278,
      build = tb.BuildPanel,
      title = function() return U.L("MOVER_LABEL_TRACKED_BARS") end,
      preferVertical = true,
    })
  end
end

function TB:OnEnable()
  tb.Config()
  if tb.anchor then return end

  -- The theme is read once. classic-wow draws the Retail art too (user
  -- request, 2026-09-30): it is the client's own Cooldown Manager sheet, not
  -- imported Dragonflight chrome, so like the swing bar it needs no Classic
  -- -> Modern WoW module. Only modern keeps the flat family.
  local theme = type(U.GetActiveThemeStyle) == "function" and
                U.GetActiveThemeStyle()
  tb.modernWow = theme == "classic-wow" or
                 (theme == "modern-wow" and
                  type(U.ModernWowSurfaceEnabled) == "function" and
                  U.ModernWowSurfaceEnabled("trackedbars")) and true or false

  local i
  for i = 1, table.getn(M.trackedBars.sample) do
    tb.samples[i] = { key = "sample" .. i, sample = true,
                      fraction = M.trackedBars.sample[i] }
  end

  local anchor = CreateFrame("Frame", "UnrealUITrackedBarsAnchor", UIParent)
  pcall(anchor.SetFrameStrata, anchor, "LOW")
  anchor:SetWidth(M.trackedBars.width)
  anchor:SetHeight(M.trackedBars.height)
  tb.anchor = anchor

  U.RegisterMover(MOVER_ID, anchor, {
    label = U.L("MOVER_LABEL_TRACKED_BARS"),
    default = { point = "BOTTOM", relativePoint = "BOTTOM", x = 420, y = 430 },
    setEditShown = function(shown)
      tb.contentHidden = shown == false
      tb.Layout(false)
    end,
  })

  if type(U.RegisterMoverSample) == "function" then
    U.RegisterMoverSample(MOVER_ID, {
      apply = function(shown)
        tb.editing = shown and true or false
        tb.Layout(true)
      end,
    })
  end

  U.RegisterEvent("UNIT_AURA", function(event, unit)
    if unit == "player" then tb.Refresh() end
  end)
  U.RegisterEvent("PLAYER_AURAS_CHANGED", tb.Refresh)
  U.RegisterEvent("PLAYER_REGEN_DISABLED", function() tb.Layout(false) end)
  U.RegisterEvent("PLAYER_REGEN_ENABLED", function() tb.Layout(false) end)
  -- Neither aura event is relied on alone (modules/auras.lua); the poll also
  -- keeps In Combat visibility current.
  U.RegisterUpdate("trackedbars.refresh", 0.2, tb.Refresh)

  tb.Refresh()
  tb.Layout(true)
end
