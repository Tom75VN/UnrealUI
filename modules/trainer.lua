-- unrealUI :: modules/trainer.lua
--
-- Treatment of the native Class/Profession Trainer window
-- (ClassTrainerFrame). Native trainer data, scrolling, selection, filtering
-- and purchase behaviour stay intact; unrealUI changes artwork, typography
-- and layout only.
--
-- WORKING_SOURCE, not runtime-verified on this client: query_compat.py has no
-- record at all for ClassTrainerFrame or any of its children (no probe has
-- ever touched this window), so every name and behaviour below is taken from
-- UnrealPfUI's skins\blizzard\trainer.lua as a same-client working
-- implementation. The Modern WoW drawing path wears the gossip window's
-- housing (quadrants, portrait ring, title, close button, rock footer) and
-- lays ForeverFrameXML Blizzard_TrainerUI/Mainline's content inside it: one
-- list of TrainerTextures row cells and a lower money/action bar. The older
-- fixed rows are adapted into that list rather than widened into DF-main's
-- unrelated two-pane compatibility layout. Verify in game.

local U = UnrealUI
local M = U.media
local TR = U.RegisterModule("trainer")

local WHITE = { 1.00, 1.00, 1.00, 1 }

local frame, panel
local useModernWow = false
local modernBuilt = false

local function G(name)
  return U.G(name)
end

local function SetTrainerFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function Reposition(object, point, relativeTo, relativePoint, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, relativeTo, relativePoint, x, y)
  end)
end

-- Requested: each spell line's label sits 2-3px lower than its native anchor
-- inside the row's hover/active highlight. Native anchor/relative-point are
-- preserved (only the row's own fontstring is nudged), matching how
-- core/stockui.lua's AlignTabText repositions tab labels without guessing at
-- the template's real anchor.
local ROW_TEXT_Y_OFFSET = -0.5

local function NudgeRowText(row)
  -- StyleSkillRows reruns on every native ClassTrainer_Update (filter/select
  -- changes, new service learned); guard so a repeat pass does not read back
  -- the already-nudged anchor and stack another offset on top of it.
  if not row or row.uuiRowTextNudged or not row.GetFontString then return end
  local fontOk, fontstring = pcall(row.GetFontString, row)
  if not fontOk or not fontstring then return end

  local pointOk, point, relTo, relPoint, x, y = pcall(fontstring.GetPoint, fontstring, 1)
  if not pointOk or not point then return end
  row.uuiRowTextNudged = true

  pcall(function()
    fontstring:ClearAllPoints()
    fontstring:SetPoint(point, relTo or row, relPoint or point,
                        x or 0, (y or 0) + ROW_TEXT_Y_OFFSET)
  end)
end

-- Per-row skill headers use the shared collapse box instead of the native
-- +/- art. Native click/collapse behaviour is untouched; only the icon and
-- its click routing are unrealUI's, same treatment as modules/questlog.lua's
-- header rows.
local function RowFontString(row)
  if not row or not row.GetFontString then return nil end
  local ok, fontstring = pcall(row.GetFontString, row)
  return ok and fontstring or nil
end

local function SetTextureCell(texture, path, coords)
  if not texture or not coords then return end
  pcall(texture.SetTexture, texture, path)
  pcall(texture.SetTexCoord, texture, coords[1], coords[2],
        coords[3], coords[4])
end

local function TrainerSelection()
  local getSelection = G("GetTrainerSelectionIndex")
  if type(getSelection) == "function" then
    local ok, selected = pcall(getSelection)
    if ok then return tonumber(selected) end
  end
  return frame and tonumber(frame.selectedService) or nil
end

-- ---------------------------------------------------------------------------
-- Modern WoW service rows, drawn as ForeverFrameXML's ClassTrainerSkillButton
-- (Blizzard_TrainerUI.xml / ClassTrainerFrame_InitServiceButton) and its
-- TrainerUICategoryTemplate header. The client's own row button stays the
-- click owner; its label, rank text and state art are hidden and the row is
-- drawn from the Training API instead, so a native recolour or re-texture
-- cannot show through (user screenshot, 2026-09-23: red native names, the
-- description overlapping the next row, the native +/- art over the header).
--
-- Every string is the client's own global (REQUIRES_LABEL, TRAINER_REQ_*,
-- ITEM_SPELL_KNOWN, LEVEL); a missing one is left out rather than replaced
-- with addon text. The requirement APIs are OFFICIAL_CLIENT_DOCUMENTATION,
-- not runtime-verified.
-- ---------------------------------------------------------------------------
local rows = { RED = "|cffff2020", CLOSE = "|r", DELIMITER = ", " }

function rows.Str(key)
  local value = G(key)
  return type(value) == "string" and value or nil
end

function rows.Call(name, a, b)
  local fn = G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3, r4 = pcall(fn, a, b)
  if ok then return r1, r2, r3, r4 end
  return nil
end

-- Forever's requirement line: level, skill rank, previous rank, each red when
-- unmet, after the client's own "Requires:" label.
function rows.Requirements(id, serviceType)
  if serviceType == "used" then return rows.Str("ITEM_SPELL_KNOWN") or "" end

  local parts = {}
  local level = tonumber((rows.Call("GetTrainerServiceLevelReq", id))) or 1
  if level > 1 then
    local text
    local template = rows.Str("TRAINER_REQ_LEVEL")
    if template then
      text = string.format(template, level)
    elseif rows.Str("LEVEL") then
      text = rows.Str("LEVEL") .. " " .. level
    else
      text = tostring(level)
    end
    local playerLevel = tonumber((rows.Call("UnitLevel", "player"))) or 0
    if playerLevel < level then
      -- Red as a whole, number included (user request, 2026-09-23): the
      -- client's template can colour its own %d, which kept the number
      -- white inside the red, so its colour codes are dropped first.
      text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
      text = string.gsub(text, "|r", "")
      text = rows.RED .. text .. rows.CLOSE
    end
    table.insert(parts, text)
  end

  local skill, rank, hasSkill = rows.Call("GetTrainerServiceSkillReq", id)
  if type(skill) == "string" and skill ~= "" then
    local text = string.format("%s (%d)", skill, tonumber(rank) or 0)
    if not hasSkill then text = rows.RED .. text .. rows.CLOSE end
    table.insert(parts, text)
  end

  -- At most one ability requirement exists; its second result is 1 when
  -- known and 0 when not (0 is true in Lua, so it is compared, not tested).
  local count = tonumber((rows.Call("GetTrainerServiceNumAbilityReq", id))) or 0
  if count > 0 then
    local ability, known = rows.Call("GetTrainerServiceAbilityReq", id, 1)
    if type(ability) == "string" and ability ~= "" then
      if known ~= 1 and known ~= true then
        ability = rows.RED .. ability .. rows.CLOSE
      end
      table.insert(parts, ability)
    end
  end

  if table.getn(parts) == 0 then return "" end
  local text = table.concat(parts, rows.DELIMITER)
  local label = rows.Str("REQUIRES_LABEL")
  if label then text = label .. " " .. text end
  return text
end

function rows.RowId(row)
  if not row or not row.GetID then return nil end
  local ok, value = pcall(row.GetID, row)
  return ok and tonumber(value) or nil
end

-- The client's row label, rank text and state slots: hidden on every pass,
-- because the native update rewrites them.
--
-- The label is hidden through its GLOBAL, not the object GetFontString hands
-- back: this client returns a wrapper that carries the readers but not the
-- writers (knowledge.json / widgets.region_walk_wrapper_lacks_setters), so a
-- Hide on it did nothing and the native header text stayed above the bar
-- (user screenshot, 2026-09-23). Its GetName resolves the real widget; the
-- template's usual <row>Text name is the fallback.
function rows.HideNative(row)
  local name = row.GetName and row:GetName()
  local label = RowFontString(row)
  local labelName
  if label and label.GetName then
    local ok, value = pcall(label.GetName, label)
    if ok and type(value) == "string" and value ~= "" then labelName = value end
  end
  local natives = {
    labelName and G(labelName),
    name and G(name .. "Text"),
    name and G(name .. "SubText"),
  }
  local k
  for k = 1, 3 do
    local object = natives[k]
    if object then pcall(object.Hide, object) end
  end
  if label then pcall(label.Hide, label) end
  -- The state slots only, through the button's own setters: never a region
  -- walk, which would also hide this row's addon art (rules/unreal-ui.md).
  local slots = { "SetNormalTexture", "SetPushedTexture",
                  "SetHighlightTexture", "SetDisabledTexture" }
  local i
  for i = 1, table.getn(slots) do
    local setter = row[slots[i]]
    if type(setter) == "function" then
      if not pcall(setter, row, "") then pcall(setter, row, nil) end
    end
  end
end

function rows.MoneyColor(readout, color)
  local coins = { readout.gold, readout.silver, readout.copper }
  local i
  for i = 1, 3 do
    local coin = coins[i]
    if coin and coin.label then
      pcall(coin.label.SetTextColor, coin.label, color[1], color[2], color[3])
    end
  end
end

-- One professions-atlas cell ({ left, top, right, bottom } texels).
function rows.Cell(texture, cell)
  local atlas = M.modernWow.professions.atlas
  pcall(texture.SetTexture, texture, M.modernWow.professions.texture.atlas)
  pcall(texture.SetTexCoord, texture, cell.left / atlas.width,
        cell.right / atlas.width, cell.top / atlas.height,
        cell.bottom / atlas.height)
end

function rows.Refresh(row)
  local state = row and row.uuiModernTrainerRow
  if not state then return end
  local t = M.modernWow.trainer.row
  rows.HideNative(row)

  local id = rows.RowId(row)
  local name, rank, serviceType, expanded
  if id then name, rank, serviceType, expanded = rows.Call("GetTrainerServiceInfo", id) end

  if serviceType == "header" then
    state.normal:Hide()
    state.disabled:Hide()
    state.selected:Hide()
    state.highlight:Hide()
    state.icon:Hide()
    state.name:Hide()
    state.rank:Hide()
    state.subText:Hide()
    state.money:Hide()
    local cells = M.modernWow.professions.cells
    rows.Cell(state.toggle, expanded and cells.expanded or cells.collapsed)
    state.headerLabel:SetText(name or "")
    U.SetStockFont(state.headerLabel, M.fontSize.normal,
                   state.hovered and t.headerHover or t.headerText)
    U.ClearTextShadow(state.headerLabel)
    local i
    for i = 1, table.getn(state.headerParts) do state.headerParts[i]:Show() end
    return
  end

  local i
  for i = 1, table.getn(state.headerParts) do state.headerParts[i]:Hide() end
  state.normal:Show()
  state.name:Show()
  state.rank:Show()
  state.subText:Show()

  local unavailable = serviceType == "unavailable"
  local icon = id and rows.Call("GetTrainerServiceIcon", id)
  pcall(state.icon.SetTexture, state.icon, icon)
  pcall(state.icon.Show, state.icon)
  -- ClassTrainerSkillButton's disabledBG: a service that cannot be learned
  -- sits on darker parchment, and its icon is dimmed.
  if unavailable then state.disabled:Show() else state.disabled:Hide() end
  local shade = unavailable and t.disabledShade or 1
  U.SetColor(state.icon, shade, shade, shade, 1)

  state.name:SetText(name or "")
  U.SetStockFont(state.name, M.fontSize.normal,
                 unavailable and t.unavailableText or t.nameText)
  U.FitLineToText(state.name)
  if type(rank) == "string" and rank ~= "" then
    state.rank:SetText("(" .. rank .. ")")
  else
    state.rank:SetText("")
  end
  U.SetStockFont(state.rank, M.fontSize.small, t.rankText)
  state.subText:SetText(id and rows.Requirements(id, serviceType) or "")
  U.SetStockFont(state.subText, M.fontSize.small, t.subText)

  local cost = tonumber((id and rows.Call("GetTrainerServiceCost", id))) or 0
  if serviceType ~= "used" and cost > 0 then
    state.money:SetAmount(cost)
    local money = tonumber((rows.Call("GetMoney"))) or 0
    rows.MoneyColor(state.money, money >= cost and t.subText or t.costRed)
    state.money:Show()
  else
    state.money:Hide()
  end

  local selected = TrainerSelection()
  if selected and selected == id then state.selected:Show()
  else state.selected:Hide() end
  if state.hovered then state.highlight:Show()
  else state.highlight:Hide() end
end

-- The spell's own tooltip while a service row is hovered (user request,
-- 2026-09-23), as ClassTrainerSkillButtonTemplate's OnEnter does:
-- GameTooltip:SetOwner(self, "ANCHOR_RIGHT") then SetTrainerService(id). The
-- shared GameTooltip showing game content, the same use as the professions
-- and action-bar hovers; SetTrainerService is OFFICIAL_CLIENT_DOCUMENTATION,
-- not runtime-verified. Headers get none.
function rows.ShowTip(row)
  local id = rows.RowId(row)
  if not id then return end
  local _, _, serviceType = rows.Call("GetTrainerServiceInfo", id)
  if not serviceType or serviceType == "header" then return end
  local tip = G("GameTooltip")
  if not tip or type(tip.SetTrainerService) ~= "function" then return end
  pcall(tip.SetOwner, tip, row, "ANCHOR_RIGHT")
  if pcall(tip.SetTrainerService, tip, id) then
    pcall(tip.Show, tip)
    row.uuiTrainerTip = true
  end
end

function rows.HideTip(row)
  if not row.uuiTrainerTip then return end
  row.uuiTrainerTip = nil
  local tip = G("GameTooltip")
  if tip then pcall(tip.Hide, tip) end
end

-- Forever's TrainerUICategoryTemplate on the professions atlas the Modern WoW
-- recipe list already draws (M.modernWow.professions.cells): a 25-high bar
-- with fixed end pieces, the label at LEFT 10, the collapse glyph at RIGHT -10.
function rows.BuildHeader(row, state)
  local h = M.modernWow.professions.header
  local cells = M.modernWow.professions.cells
  local t = M.modernWow.trainer.row
  local left = row:CreateTexture(nil, "BACKGROUND")
  local middle = row:CreateTexture(nil, "BACKGROUND")
  local right = row:CreateTexture(nil, "BACKGROUND")
  rows.Cell(left, cells.headerLeft)
  rows.Cell(middle, cells.headerMiddle)
  rows.Cell(right, cells.headerRight)
  pcall(function()
    left:SetWidth(h.pieceWidth)
    left:SetHeight(h.pieceHeight)
    left:SetPoint("LEFT", row, "LEFT", 0, t.headerY)
    right:SetWidth(h.pieceWidth)
    right:SetHeight(h.pieceHeight)
    right:SetPoint("RIGHT", row, "RIGHT", 0, t.headerY)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
  end)

  local toggle = row:CreateTexture(nil, "ARTWORK")
  pcall(function()
    toggle:SetWidth(h.collapseWidth)
    toggle:SetHeight(h.collapseHeight)
    toggle:SetPoint("RIGHT", row, "RIGHT", -10, t.headerY)
  end)

  -- On the bar and level with the +/- (user request, 2026-09-23). This
  -- client draws a label's glyphs high in its box, so the box is fixed at 12
  -- and sits the professions list's in-game-tuned `labelY - lift` below the
  -- art's centre; both anchors carry that y so the box is not stretched.
  local labelY = t.headerY + h.labelY - h.lift + t.headerLabelY
  local label = U.CreateLabel(row, { size = M.fontSize.normal, color = t.headerText })
  pcall(function()
    label:SetPoint("LEFT", row, "LEFT", 10, labelY)
    label:SetPoint("RIGHT", row, "RIGHT", -(10 + h.collapseWidth + 6), labelY)
    label:SetHeight(12)
    label:SetJustifyH("LEFT")
    if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
  end)

  state.toggle = toggle
  state.headerLabel = label
  state.headerParts = { left, middle, right, toggle, label }
end

local function BuildModernRow(row)
  if not row then return end
  local t = M.modernWow.trainer.row
  local state = row.uuiModernTrainerRow
  if not state then
    -- Native art off once, before any addon art goes on.
    U.StripStockTextures(row)
    state = {}
    state.normal = row:CreateTexture(nil, "BACKGROUND")
    state.normal:SetAllPoints(row)
    SetTextureCell(state.normal, M.modernWow.texture.trainerSheet, t.normal)

    -- Forever darkens an unavailable row with disabledBG, a 0.55 grey in MOD
    -- blend under the row art. MOD is not runtime-verified here (only ADD is,
    -- rendering.setblendmode_add_inert), and the row cell is near-black at
    -- about 56% file alpha, so shading its vertex colour changed nothing
    -- (user report, 2026-09-23). A second copy of that translucent cell does
    -- the darkening through file alpha, which this client composites: the
    -- parchment ends at about 0.19 of its brightness, Forever's 0.24.
    state.disabled = row:CreateTexture(nil, "BACKGROUND")
    state.disabled:SetAllPoints(row)
    SetTextureCell(state.disabled, M.modernWow.texture.trainerSheet, t.normal)
    state.disabled:Hide()

    state.selected = row:CreateTexture(nil, "ARTWORK")
    state.selected:SetAllPoints(row)
    SetTextureCell(state.selected, M.modernWow.texture.trainerSheet, t.selected)
    pcall(state.selected.SetBlendMode, state.selected, "ADD")

    state.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    state.highlight:SetAllPoints(row)
    SetTextureCell(state.highlight, M.modernWow.texture.trainerSheet, t.highlight)
    pcall(state.highlight.SetBlendMode, state.highlight, "ADD")
    state.highlight:Hide()

    state.icon = row:CreateTexture(nil, "OVERLAY")
    state.icon:SetWidth(t.icon)
    state.icon:SetHeight(t.icon)
    state.icon:SetPoint("LEFT", row, "LEFT", t.iconLeft, 0)
    state.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- name: TOPLEFT of the icon's TOPRIGHT +6,-1; rank: BOTTOMLEFT of the
    -- name's BOTTOMRIGHT +5,-1; requirements: 19 under the name.
    state.name = U.CreateLabel(row, { size = M.fontSize.normal, color = t.nameText })
    state.name:SetPoint("TOPLEFT", state.icon, "TOPRIGHT", t.nameLeft, t.nameTop)
    state.name:SetJustifyH("LEFT")
    -- One line (user request, 2026-09-23). U.FitLineToText keeps the first
    -- width it measures as its ceiling, so a row first filled with a short
    -- name wrapped every longer one; the ceiling is set here instead.
    state.name:SetWidth(t.nameWidth)
    state.name.uuiNativeWidth = t.nameWidth
    pcall(state.name.SetNonSpaceWrap, state.name, false)

    state.rank = U.CreateLabel(row, { size = M.fontSize.small, color = t.rankText })
    state.rank:SetPoint("BOTTOMLEFT", state.name, "BOTTOMRIGHT", t.rankGap, -1)
    state.rank:SetJustifyH("LEFT")

    state.subText = U.CreateLabel(row, { size = M.fontSize.small, color = t.subText })
    state.subText:SetPoint("TOPLEFT", state.name, "TOPLEFT", 0, t.subTop)
    state.subText:SetWidth(t.subWidth)
    state.subText:SetJustifyH("LEFT")

    state.money = U.CreateMoneyReadout(row, { gap = 2 })
    state.money:SetPoint("TOPRIGHT", row, "TOPRIGHT", -t.costRight, t.costTop)
    -- Each coin icon raised by coinIconY, its number left where it was (user
    -- request, 2026-09-23). The number hangs off the icon in the shared
    -- component, so it is re-anchored to the coin's own frame first.
    local coins = { state.money.gold, state.money.silver, state.money.copper }
    local c
    for c = 1, 3 do
      local coin = coins[c]
      if coin and coin.icon then
        pcall(function()
          if coin.label then
            coin.label:ClearAllPoints()
            coin.label:SetPoint("RIGHT", coin, "RIGHT",
                                -((coin.iconWidth or 0) + 1), 0)
          end
          coin.icon:ClearAllPoints()
          coin.icon:SetPoint("RIGHT", coin, "RIGHT", 0, t.coinIconY)
        end)
      end
    end

    rows.BuildHeader(row, state)

    U.PostHookScript(row, "OnEnter", function()
      state.hovered = true
      rows.Refresh(row)
      rows.ShowTip(row)
    end)
    U.PostHookScript(row, "OnLeave", function()
      state.hovered = false
      rows.Refresh(row)
      rows.HideTip(row)
    end)
    U.PostHookScript(row, "OnClick", function()
      U.DeferOnce("trainer:rowclick", function()
        local i
        for i = 1, t.count do rows.Refresh(G("ClassTrainerSkill" .. i)) end
      end)
    end)

    row.uuiModernTrainerRow = state
  end

  pcall(row.SetWidth, row, t.width)
  pcall(row.SetHeight, row, t.height)
  rows.Refresh(row)
end

-- Rows past the list's own (row.count) are parked in a hidden frame, as the
-- settings list parks a client control: a later native Show cannot draw them.
-- The client's update loop did not follow CLASS_TRAINER_SKILLS_DISPLAYED on
-- this client (user screenshot, 2026-09-23: rows 7+ drawn below the list).
function rows.Park()
  if not rows.park then
    local ok, park = pcall(CreateFrame, "Frame", nil, UIParent)
    if not ok or not park then return nil end
    pcall(park.Hide, park)
    rows.park = park
  end
  return rows.park
end

function rows.ParkExtras()
  if not rows.Park() then return end
  local i = M.modernWow.trainer.row.count + 1
  local row = G("ClassTrainerSkill" .. i)
  while row do
    if not row.uuiTrainerParked then
      row.uuiTrainerParked = true
      pcall(row.SetParent, row, rows.park)
    end
    i = i + 1
    row = G("ClassTrainerSkill" .. i)
  end
end

local function StyleSkillRows()
  -- No runtime frame dump exists yet. Forever supplies the target geometry;
  -- the fixed-row names and constants are same-client working source.
  local count = tonumber(G("CLASS_TRAINER_SKILLS_DISPLAYED")) or 15
  if useModernWow then
    count = M.modernWow.trainer.row.count
    if _G then
      _G.CLASS_TRAINER_SKILLS_DISPLAYED = count
      _G.CLASS_TRAINER_SKILL_HEIGHT = M.modernWow.trainer.row.height
    end
    rows.ParkExtras()
  end
  local i
  for i = 1, count do
    local row = G("ClassTrainerSkill" .. i)
    if row then
      if useModernWow then
        BuildModernRow(row)
      else
        U.StripStockTextures(row)
        SetTrainerFont(row, M.fontSize.normal, WHITE)
        U.StyleStockCollapseButton(row)
        NudgeRowText(row)
      end
    end
  end

  local collapseAll = G("ClassTrainerCollapseAllButton")
  if collapseAll then
    U.StripStockTextures(collapseAll)
    U.StyleStockCollapseButton(collapseAll, true)
    if useModernWow and type(U.ModernWowCollapseFace) == "function" then
      U.ModernWowCollapseFace(collapseAll)
    end
  end

  local expandFrame = G("ClassTrainerExpandButtonFrame")
  if expandFrame then
    U.StripStockTextures(expandFrame)
    if useModernWow then pcall(expandFrame.Hide, expandFrame) end
  end
end

-- Skill icon shown in the detail pane once a service is selected.
--
-- BUG (reported in game): the icon never appeared. Unlike modules/
-- character.lua's equipment slots -- where the icon is a separate
-- <slot>IconTexture region -- ClassTrainerSkillIcon has no separate icon
-- region; its icon IS the button's own normal texture, same shape as the
-- merchant repair-item icon bug. The previous code passed the button itself
-- as the "icon" option to U.StyleStockButton/U.RefreshStockButtonArtwork,
-- which does not protect a real texture and still runs the unconditional
-- SetNormalTexture(button, "") clear. Worse, that clear was wired to run
-- again on every ClassTrainer_SetSelection -- immediately after the native
-- call assigns the real icon path each time a skill is selected, wiping it
-- straight back out.
--
-- WORKING_SOURCE (UnrealPfUI skins/blizzard/trainer.lua): its hook reads
-- ClassTrainerSkillIcon:GetNormalTexture() *after* native selection instead
-- of re-clearing the button, and only touches cosmetics (show/alpha/crop).
local function StyleSkillIcon()
  local icon = G("ClassTrainerSkillIcon")
  if not icon then return end
  U.StyleStockButton(icon)

  U.PostHookGlobal("ClassTrainer_SetSelection", function()
    local textureOk, texture = pcall(icon.GetNormalTexture, icon)
    if textureOk and texture then
      pcall(texture.Show, texture)
      pcall(texture.SetAlpha, texture, 1)
      pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
    end
  end)
end

-- Requested: name + greeting + skill rows all read as plain white, not the
-- accent heading color other stock windows use for their title. Reapplied on
-- every OnShow and native update (below) since talking to a new trainer NPC
-- re-sets both FontStrings' text/color through native code, not just once.
local function ReapplyHeaderText()
  if useModernWow then
    -- The gossip window's title: warm gold on the quadrants' title strip.
    local name = G("ClassTrainerNameText")
    local title = M.modernWow.trainer.title
    if name then
      U.SetStockFont(name, M.fontSize.normal, title.color)
      Reposition(name, "CENTER", frame, "TOPLEFT", title.x, -title.y)
      pcall(name.Show, name)
    end
    return
  end
  SetTrainerFont(G("ClassTrainerNameText"), M.fontSize.large, WHITE)
  SetTrainerFont(G("ClassTrainerGreetingText"), M.fontSize.normal, WHITE)
end

local function ReapplyAllText()
  -- Modern WoW draws every string it shows itself (gold names, the gold
  -- Filter label, parchment title); a blanket white pass would undo them.
  if not useModernWow then
    U.ForceStockTextWhite(frame, WHITE, M.fontSize.normal)
  end
  ReapplyHeaderText()
  StyleSkillRows()
end

-- Anchors an object to the window's top-left corner at a 384x512 design-space
-- point. Everything in the Modern WoW layout is placed this way: straight on
-- ClassTrainerFrame, never through the list's scroll child, whose client-owned
-- children this client does not carry along when the child moves
-- (knowledge.json / widgets.reparented_native_widget_ignores_scroll_offset) --
-- the rows stayed behind when the window was dragged (user report,
-- 2026-09-23).
local function DesignPoint(object, point, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, frame, "TOPLEFT", x, -y)
  end)
end

-- Lifts a control over the window chrome. The chrome is a child of the window,
-- so on a level-1 window it sits at the same level as every stock child and
-- its quadrants can draw over them: the filter dropdown's bed was hidden that
-- way (user report, 2026-09-23). SetFrameLevel on this client moves one frame,
-- not its subtree (modules/gamesettings.lua gs.Relevel), so each frame that
-- draws or takes the mouse is lifted by name.
local function RaiseAboveChrome(object, offset)
  if not object then return end
  local ok, level = pcall(frame.GetFrameLevel, frame)
  level = ok and tonumber(level) or nil
  if level then pcall(object.SetFrameLevel, object, level + offset) end
end

local function ApplyModernWowDialog()
  if not useModernWow then return end

  if type(U.ModernWowTrainerChrome) == "function" then
    U.ModernWowTrainerChrome(frame, panel, G("ClassTrainerFramePortrait"),
                             "ClassTrainerFrameCloseButton")
  end

  -- Train alone, right-aligned in the gossip Goodbye button's bed, as
  -- Forever's trainer has it; the window's red X closes it (user request,
  -- 2026-09-23). Measured from the window's TOPLEFT like the footer it sits
  -- on (user report, 2026-09-23: anchored to its bottom edge it was not in
  -- the window). The shared placement adds the red button's lift to this y.
  local t = M.modernWow.trainer
  local button = t.button
  local lift = M.modernWow.button128Red and M.modernWow.button128Red.lift or 0
  local y = -button.bottom - lift
  local train = G("ClassTrainerTrainButton")
  if type(U.ModernWowTrainerActionButton) == "function" then
    U.ModernWowTrainerActionButton(
      train, "BOTTOMRIGHT", frame, "TOPLEFT", button.right, y, button.height)
  end
  if train then
    pcall(train.SetWidth, train, button.width)
    RaiseAboveChrome(train, 3)
  end

  -- The client's Cancel button is parked undrawn, the settings list's way
  -- with a client control, so a native Show cannot bring it back.
  --
  -- So is the client's selection bar, ClassTrainerSkillHighlightFrame
  -- (vanilla FrameXML's name, WORKING_SOURCE from memory, not in any local
  -- source): a 293-wide strip the native update pins to the selected row and
  -- tints by service type. The rows are 284 wide, so its green end showed in
  -- the scrollbar gutter beside a selected learnable spell (user screenshot,
  -- 2026-09-23). The row's own `selected` cell is the selection here.
  local park = rows.Park()
  local parked = { G("ClassTrainerCancelButton"),
                   G("ClassTrainerSkillHighlightFrame") }
  local p
  for p = 1, 2 do
    local object = parked[p]
    if object and park and not object.uuiTrainerParked then
      object.uuiTrainerParked = true
      pcall(object.SetParent, object, park)
    end
  end

  local close = G("ClassTrainerFrameCloseButton")
  if close then
    Reposition(close, "TOPRIGHT", panel, "TOPRIGHT",
               -t.close.right, -t.close.top)
  end
end

-- BUG (reported in game): the Filter dropdown box extended past the
-- interface's visible edge. Its native anchor was set for the full-width,
-- unstripped ClassTrainerFrame; the content panel above is inset from the
-- frame's real edges, so that anchor no longer lines up with the visible
-- dark backdrop once widened by D.StyleStock. Re-anchor explicitly against
-- the panel and the already-repositioned greeting text instead of relying
-- on the untouched native placement.
--
-- These two points BOTH constrain the vertical axis: "RIGHT" pins the control's
-- vertical centre to the panel's, and "TOP" pins its top edge to the greeting.
-- That over-constrains height, so the control stretches to satisfy both and
-- core/dropdown.lua's CONTROL_HEIGHT lock is ignored (visibly a much taller
-- Filter box than the 28-unit component height). It also means the TOP offset
-- alone cannot move the control: raising it only grows the box upward while the
-- centre stays pinned. Keep the pair in step -- both Y offsets move together --
-- until the stretch itself is fixed by reducing this to a single anchor point.
local FILTER_Y = 5

local function RepositionFilterDropdown()
  local filterDropdown = G("ClassTrainerFrameFilterDropDown")
  if not filterDropdown then return end
  if useModernWow then
    local token = M.modernWow.trainer.filter
    pcall(filterDropdown.SetWidth, filterDropdown, token.width)
    DesignPoint(filterDropdown, "TOPRIGHT", token.right, token.top)
    -- The bed draws on the dropdown itself; its click button stays above it.
    RaiseAboveChrome(filterDropdown, 3)
    RaiseAboveChrome(G("ClassTrainerFrameFilterDropDownButton"), 4)
    return
  end
  pcall(function()
    filterDropdown:ClearAllPoints()
    filterDropdown:SetPoint("RIGHT", panel, "RIGHT", -14, FILTER_Y)
    filterDropdown:SetPoint("TOP", G("ClassTrainerGreetingText"), "BOTTOM", 0,
                            -14 + FILTER_Y)
  end)
end

local function PlaceModernScroll(scroll, bar)
  if not scroll then return end
  local t = M.modernWow.trainer
  DesignPoint(scroll, "TOPLEFT", t.scroll.left, t.scroll.top)
  pcall(scroll.SetWidth, scroll, t.scroll.width)
  pcall(scroll.SetHeight, scroll,
        t.row.count * t.row.height + (t.row.count - 1) * t.row.gap)
  if not bar then return end
  pcall(function()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT",
                 t.scrollBar.left, -t.scrollBar.top)
    bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT",
                 t.scrollBar.left, -t.scrollBar.bottom)
  end)
  if type(U.StyleModernWowScrollbar) == "function" then
    U.StyleModernWowScrollbar(bar)
  end

  local getCount = G("GetNumTrainerServices")
  if type(U.SetModernWowScrollbarProportion) == "function" and
     type(getCount) == "function" then
    local ok, total = pcall(getCount)
    if ok then
      U.SetModernWowScrollbarProportion(bar, t.row.count, tonumber(total) or 0)
    end
  end
end

local function HideModernDetail()
  local detail = G("ClassTrainerDetailScrollFrame")
  if detail then pcall(detail.Hide, detail) end
  local names = {
    "ClassTrainerSkillIcon",
    "ClassTrainerSkillName",
    "ClassTrainerSkillSubName",
    "ClassTrainerSkillDescription",
    "ClassTrainerSkillRequirements",
    "ClassTrainerSkillCost",
  }
  local i
  for i = 1, table.getn(names) do
    local object = G(names[i])
    if object then pcall(object.Hide, object) end
  end
end

-- The list parchment and the coin recess, drawn once into the window's chrome
-- frame over the quadrants (the footer's rock and divider come from
-- U.ModernWowTrainerFooterPlate). Anchored to the window, so they move with it.
local function BuildModernArt()
  if frame.uuiTrainerArt then return end
  local holder = type(U.ModernWowWindowChrome) == "function" and
                 U.ModernWowWindowChrome(frame) or nil
  if not holder then return end
  local t = M.modernWow.trainer

  local list = holder:CreateTexture(nil, "ARTWORK")
  SetTextureCell(list, M.modernWow.texture.trainerSheet, t.listBackground)
  pcall(list.SetWidth, list, t.list.right - t.list.left)
  pcall(list.SetHeight, list, t.list.bottom - t.list.top)
  DesignPoint(list, "TOPLEFT", t.list.left, t.list.top)

  if type(U.ModernWowTrainerFooterPlate) == "function" then
    U.ModernWowTrainerFooterPlate(frame)
  end

  local coins = holder:CreateTexture(nil, "OVERLAY")
  SetTextureCell(coins, M.modernWow.texture.trainerMoney, t.money.texCoord)
  pcall(coins.SetWidth, coins, t.money.width)
  pcall(coins.SetHeight, coins, t.money.height)
  DesignPoint(coins, "TOPLEFT", t.money.left, t.money.top)

  frame.uuiTrainerArt = { list = list, coins = coins }
end

local function BuildModernLayout()
  local t = M.modernWow.trainer
  -- The size first: the gossip housing's quadrants are cut to it once.
  pcall(frame.SetWidth, frame, t.width)
  pcall(frame.SetHeight, frame, t.height)

  local status = G("ClassTrainerStatusBar")
  if status then
    pcall(status.SetWidth, status, t.status.width)
    pcall(status.SetHeight, status, t.status.height)
    DesignPoint(status, "TOPLEFT", t.status.left, t.status.top)
    RaiseAboveChrome(status, 3)
  end
  local greeting = G("ClassTrainerGreetingText")
  if greeting then pcall(greeting.Hide, greeting) end

  RepositionFilterDropdown()
  PlaceModernScroll(G("ClassTrainerListScrollFrame"),
                    G("ClassTrainerListScrollFrameScrollBar"))
  HideModernDetail()

  -- The first row on the window, the rest chained under it, as the client's
  -- own layout chains them.
  -- A row under a category header is drawn up by headerPull, halving the
  -- space below the header's bar (user request, 2026-09-23); the rows keep
  -- their scroll step, only their drawn spacing changes.
  -- A header row is itself drawn up by headerTopPull, trimming the space
  -- above its bar (user request, 2026-09-23).
  local previous, previousHeader
  local i
  for i = 1, t.row.count do
    local row = G("ClassTrainerSkill" .. i)
    if row then
      local id = rows.RowId(row)
      local serviceType
      if id then
        local _, _
        _, _, serviceType = rows.Call("GetTrainerServiceInfo", id)
      end
      local isHeader = serviceType == "header"
      local pull = isHeader and t.row.headerTopPull or 0
      if previous then
        if previousHeader then pull = pull + t.row.headerPull end
        Reposition(row, "TOPLEFT", previous, "BOTTOMLEFT", 0, -t.row.gap + pull)
      else
        DesignPoint(row, "TOPLEFT", t.scroll.left, t.scroll.top - pull)
      end
      previousHeader = isHeader
      previous = row
    end
  end

  local money = G("ClassTrainerMoneyFrame")
  if money then
    DesignPoint(money, "RIGHT",
                t.money.left + t.money.width + t.money.contentRight,
                t.money.top + t.money.height / 2)
    RaiseAboveChrome(money, 3)
    pcall(money.Show, money)
  end
  ApplyModernWowDialog()
  BuildModernArt()
  modernBuilt = true
end

local function SyncModernButtons()
  if not useModernWow or type(U.ModernWowSetRedButtonDisabled) ~= "function" then
    return
  end
  local names = { "ClassTrainerTrainButton", "ClassTrainerCancelButton" }
  local i
  for i = 1, table.getn(names) do
    local button = G(names[i])
    if button and button.IsEnabled then
      local ok, enabled = pcall(button.IsEnabled, button)
      if ok then U.ModernWowSetRedButtonDisabled(button, not enabled) end
    end
  end
end

local function Reapply()
  if not useModernWow then U.StripStockTextures(frame) end
  ReapplyAllText()
  if useModernWow then
    BuildModernLayout()
    SyncModernButtons()
  else
    RepositionFilterDropdown()
  end
end

local function BuildFrame()
  frame = G("ClassTrainerFrame")
  if not frame then
    U.Debug("trainer: native frame unavailable")
    return false
  end

  local portrait = useModernWow and G("ClassTrainerFramePortrait")
  local portraitPath
  if portrait and portrait.GetTexture then
    local ok, path = pcall(portrait.GetTexture, portrait)
    if ok then portraitPath = path end
  end
  U.StripStockTextures(frame)
  if portrait and portraitPath and portrait.SetTexture then
    pcall(portrait.SetTexture, portrait, portraitPath)
  end

  -- Content backdrop inset from the real frame bounds, same shape as
  -- modules/friends.lua's panel: leaves the bottom strip clear for the
  -- Train/Cancel buttons instead of burying them inside the dark box.
  panel = U.CreatePanel(frame, {
    name = "UnrealUITrainerPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  if useModernWow then
    -- As on gossip: the panel keeps only its role as the close button's
    -- anchor, sized to the art's visible bounds, which are also the hit rect.
    local art = M.modernWow.trainer.art
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", art.left, -art.top)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -art.right, art.bottom)
    pcall(frame.SetHitRectInsets, frame, art.left, art.right, art.top,
          art.bottom)
  else
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 40)
    pcall(frame.SetHitRectInsets, frame, 8, 32, 10, 40)
  end
  pcall(panel.EnableMouse, panel, false)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  -- Modern WoW: the gossip window's drag strip, which stops above the filter
  -- dropdown under the title strip.
  if useModernWow then
    U.MakeWindowDraggable("trainer", frame,
                          { headerInset = 54, headerHeight = 40 })
  else
    U.MakeWindowDraggable("trainer", frame, { headerInset = 56 })
  end

  if not useModernWow then
    Reposition(G("ClassTrainerNameText"), "TOP", panel, "TOP", 0, -10)
    Reposition(G("ClassTrainerGreetingText"), "TOP",
               G("ClassTrainerNameText"), "BOTTOM", 0, -4)
  end
  ReapplyHeaderText()

  U.StyleStockCloseButton(G("ClassTrainerFrameCloseButton"), panel, -6, -6)

  -- Each entry is an independent on/off filter rather than one selected value.
  -- Modern WoW draws FrameXML's filter button and menu art (the bed), and
  -- the game settings checkbox on each row, as every Modern WoW checkbox.
  local filterDropdown = G("ClassTrainerFrameFilterDropDown")
  if useModernWow then
    U.Dropdown.StyleStock(filterDropdown, M.modernWow.trainer.filter.width, {
      checkboxes = true,
      modernWow = true,
      bed = M.modernWow.trainer.filter.bed,
    })
  else
    U.Dropdown.StyleStock(filterDropdown, 130, { checkboxes = true })
  end
  RepositionFilterDropdown()

  U.StripStockTextures(G("ClassTrainerListScrollFrame"))
  if not useModernWow then
    U.StyleStockScrollbar(G("ClassTrainerListScrollFrameScrollBar"))
  end

  U.StripStockTextures(G("ClassTrainerDetailScrollFrame"))
  if not useModernWow then
    U.StyleStockScrollbar(G("ClassTrainerDetailScrollFrameScrollBar"))
  end

  if not useModernWow then StyleSkillIcon() end
  StyleSkillRows()

  U.StyleStockButton(G("ClassTrainerCancelButton"))
  local train = U.StyleStockButton(G("ClassTrainerTrainButton"))
  local cancel = G("ClassTrainerCancelButton")
  if useModernWow and cancel and cancel.SetText then
    pcall(cancel.SetText, cancel, G("CLOSE") or "Exit")
  end
  if not useModernWow and train and cancel then
    Reposition(train, "RIGHT", cancel, "LEFT", -6, 0)
  end
  if useModernWow then
    BuildModernLayout()
    SyncModernButtons()
  end

  -- Native list rebuilds (filter change, new service learned) can restore
  -- stock row/collapse art; reapply the same way modules/questlog.lua does
  -- for its header rows.
  --
  -- The update's name is not recorded for this client: the Modern WoW rows
  -- kept the native red names and showed rows past the sixth, so the
  -- ClassTrainer_Update hook alone did not run after it (user screenshot,
  -- 2026-09-23). Vanilla FrameXML names it ClassTrainerFrame_Update; both
  -- are hooked (a missing global fails closed), and the list's own events
  -- and scroll add one deferred pass after whatever the client ran.
  local function AfterUpdate()
    ReapplyAllText()
    if useModernWow then
      BuildModernLayout()
      SyncModernButtons()
    end
  end
  local function AfterUpdateSettled()
    if not frame or not frame.IsShown then return end
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then U.DeferOnce("trainer:update", AfterUpdate) end
  end
  U.PostHookGlobal("ClassTrainer_Update", AfterUpdate)
  U.PostHookGlobal("ClassTrainerFrame_Update", AfterUpdate)
  U.RegisterEvent("TRAINER_UPDATE", AfterUpdateSettled)
  local listBar = G("ClassTrainerListScrollFrameScrollBar")
  if useModernWow and listBar then
    U.PostHookScript(listBar, "OnValueChanged", AfterUpdateSettled)
  end
  U.PostHookGlobal("ClassTrainer_SetSelection", function()
    if useModernWow then StyleSkillRows() end
    SyncModernButtons()
  end)

  U.PostHookScript(frame, "OnShow", Reapply)

  if frame.IsShown then
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then Reapply() end
  end
  return true
end

-- USER_CONFIRMED_INGAME: unlike FriendsFrame/QuestLogFrame, ClassTrainerFrame
-- was still fully native (parchment art, no unrealUI styling at all) after
-- OnEnable ran, so G("ClassTrainerFrame") is not reliably resolvable that
-- early on this client -- matching UnrealPfUI's HookAddonOrVariable
-- ("Blizzard_TrainerUI", ...) guard in skins/blizzard/trainer.lua, which this
-- module skipped on the (wrong) assumption that trainer worked like the other
-- always-loaded stock frames. Retry from whichever of these actually fires
-- first rather than committing to one: ADDON_LOADED for the lazy-load addon
-- name pfUI's skin expects, and TRAINER_SHOW (the documented open-trainer
-- event, api.json Training category) as a fallback in case the frame is
-- created on first open rather than on addon load. Both listeners are torn
-- down once BuildFrame succeeds once.
local pendingEvents = { "ADDON_LOADED", "TRAINER_SHOW" }

function U.ModernWowTrainerActive()
  return modernBuilt
end

local function TryBuild()
  if BuildFrame() then
    local i
    for i = 1, table.getn(pendingEvents) do
      U.UnregisterEvent(pendingEvents[i], TryBuild)
    end
    return true
  end
  return false
end

function TR:OnEnable()
  useModernWow = type(U.GetActiveThemeStyle) == "function" and
                 U.GetActiveThemeStyle() == "modern-wow" and
                 type(U.ModernWowSurfaceEnabled) == "function" and
                 U.ModernWowSurfaceEnabled("trainer")
  if U.ThemeStyleUsesClassicInteractionChrome() and not useModernWow then return end
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("TRAINER_SHOW", TryBuild)
end
