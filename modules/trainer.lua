-- unrealUI :: modules/trainer.lua
--
-- pfUI-modern-inspired treatment of the native Class/Profession Trainer
-- window (ClassTrainerFrame). Native trainer data, service list, selection,
-- filter and buy/cancel behaviour stay intact; unrealUI changes only
-- artwork, typography and layout, matching the Character/Quest Log/Friends
-- treatment. Uses the shared dropdown component for the skill-type filter
-- and the shared collapse component for skill-line headers.
--
-- WORKING_SOURCE, not runtime-verified on this client: query_compat.py has no
-- record at all for ClassTrainerFrame or any of its children (no probe has
-- ever touched this window), so every name and behaviour below is taken from
-- UnrealPfUI's skins\blizzard\trainer.lua as a same-client working
-- implementation rather than confirmed evidence. Verify in game and fold any
-- surprises into knowledge.json.

local U = UnrealUI
local M = U.media
local TR = U.RegisterModule("trainer")

local WHITE = { 1.00, 1.00, 1.00, 1 }

local frame, panel

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
local function StyleSkillRows()
  -- No compat record for this constant; fall back the same way
  -- modules/questlog.lua does for MAX_NUM_ITEMS.
  local rows = tonumber(G("CLASS_TRAINER_SKILLS_DISPLAYED")) or 15
  local i
  for i = 1, rows do
    local row = G("ClassTrainerSkill" .. i)
    if row then
      U.StripStockTextures(row)
      SetTrainerFont(row, M.fontSize.normal, WHITE)
      U.StyleStockCollapseButton(row)
      NudgeRowText(row)
    end
  end

  local collapseAll = G("ClassTrainerCollapseAllButton")
  if collapseAll then
    U.StripStockTextures(collapseAll)
    U.StyleStockCollapseButton(collapseAll, true)
  end

  local expandFrame = G("ClassTrainerExpandButtonFrame")
  if expandFrame then U.StripStockTextures(expandFrame) end
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
  SetTrainerFont(G("ClassTrainerNameText"), M.fontSize.large, WHITE)
  SetTrainerFont(G("ClassTrainerGreetingText"), M.fontSize.normal, WHITE)
end

local function ReapplyAllText()
  U.ForceStockTextWhite(frame, WHITE, M.fontSize.normal)
  ReapplyHeaderText()
  StyleSkillRows()
end

local function Reapply()
  U.StripStockTextures(frame)
  ReapplyAllText()
end

local function BuildFrame()
  frame = G("ClassTrainerFrame")
  if not frame then
    U.Debug("trainer: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  -- Content backdrop inset from the real frame bounds, same shape as
  -- modules/friends.lua's panel: leaves the bottom strip clear for the
  -- Train/Cancel buttons instead of burying them inside the dark box.
  panel = U.CreatePanel(frame, {
    name = "UnrealUITrainerPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 40)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 8, 32, 10, 40)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  U.MakeWindowDraggable("trainer", frame, { headerInset = 56 })

  Reposition(G("ClassTrainerNameText"), "TOP", panel, "TOP", 0, -10)
  Reposition(G("ClassTrainerGreetingText"), "TOP",
             G("ClassTrainerNameText"), "BOTTOM", 0, -4)
  ReapplyHeaderText()

  U.StyleStockCloseButton(G("ClassTrainerFrameCloseButton"), panel, -6, -6)

  -- Each entry is an independent on/off filter rather than one selected value.
  local filterDropdown = G("ClassTrainerFrameFilterDropDown")
  U.Dropdown.StyleStock(filterDropdown, 130, { checkboxes = true })

  -- BUG (reported in game): the Filter dropdown box extended past the
  -- interface's visible edge. Its native anchor was set for the full-width,
  -- unstripped ClassTrainerFrame; the content panel above is inset from the
  -- frame's real edges, so that anchor no longer lines up with the visible
  -- dark backdrop once widened by D.StyleStock. Re-anchor explicitly against
  -- the panel and the already-repositioned greeting text instead of relying
  -- on the untouched native placement.
  if filterDropdown then
    pcall(function()
      filterDropdown:ClearAllPoints()
      filterDropdown:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
      filterDropdown:SetPoint("TOP", G("ClassTrainerGreetingText"), "BOTTOM", 0, -14)
    end)
  end

  U.StripStockTextures(G("ClassTrainerListScrollFrame"))
  U.StyleStockScrollbar(G("ClassTrainerListScrollFrameScrollBar"))

  U.StripStockTextures(G("ClassTrainerDetailScrollFrame"))
  U.StyleStockScrollbar(G("ClassTrainerDetailScrollFrameScrollBar"))

  StyleSkillIcon()
  StyleSkillRows()

  U.StyleStockButton(G("ClassTrainerCancelButton"))
  local train = U.StyleStockButton(G("ClassTrainerTrainButton"))
  local cancel = G("ClassTrainerCancelButton")
  if train and cancel then
    Reposition(train, "RIGHT", cancel, "LEFT", -6, 0)
  end

  -- Native list rebuilds (filter change, new service learned) can restore
  -- stock row/collapse art; reapply the same way modules/questlog.lua does
  -- for its header rows.
  U.PostHookGlobal("ClassTrainer_Update", function()
    ReapplyAllText()
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
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("TRAINER_SHOW", TryBuild)
end
