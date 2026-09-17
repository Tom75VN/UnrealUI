-- unrealUI :: modules/character.lua
--
-- pfUI-modern-inspired treatment of the native Character sheet (PaperDoll).
-- Native slot buttons, model frame, stat computation and tab switching stay
-- intact; unrealUI changes only artwork, typography and layout, matching the
-- Quest Log / Spellbook treatment.

local U = UnrealUI
local M = U.media
local CH = U.RegisterModule("character")

local GOLD  = { 0.96, 0.68, 0.04, 1.00 }
local WHITE = { 0.90, 0.90, 0.90, 1.00 }
local DIM   = { 0.60, 0.60, 0.60, 1.00 }

local frame, panel, modernWowTabMode, toggleCharacterOriginal
local StyleModel, RaiseResistancesAboveModel

local SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
  "ShirtSlot", "TabardSlot", "WristSlot",
  "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
  "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
  "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot",
}

-- CharacterFrameTab1-5: Character, Reputation, (Pet -- conditional on
-- HasPetUI(), which is why the chain below only re-anchors past a tab that is
-- actually shown), Skills, Honor. Styling all five is what the previous
-- 4-tab pass missed: Honor is index 5, not 4, so it never got the flat skin
-- and kept native selected-tab art (USER_CONFIRMED_INGAME).
local TAB_COUNT = 5

-- The visible window surface: panel sits this far inside CharacterFrame on
-- each side. The tab strip is aligned to the same two insets so its first tab
-- starts flush with the window's left edge and the run ends flush with its
-- right, rather than to a second set of numbers.
-- Measurements from the last LayoutTabs pass, for /uui tabs.
local tabFit

local PANEL_INSET_LEFT = 10
local PANEL_INSET_RIGHT = 30
local TAB_GAP = 3
-- Offset from the panel's bottom edge. Negative lifts the strip into that
-- edge, which is the placement the sheet uses.
local TAB_DROP = -1
-- Padding on each side of a tab's label. The Pet tab is the one conditional
-- tab in the run, and the tighter five-tab layout reads better with a little
-- more inset, so it gets the extra; U.FitStockTabStrip still reduces this if
-- the run would not fit.
local TAB_PADDING = 10
local TAB_PET_PADDING = 2

local function G(name)
  return U.G(name)
end

local function SetTextFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

-- The equipped item's quality index, or nil when this client will not report
-- one. Shared by the slot's rarity border below and by its tooltip hook, so
-- the two cannot disagree about what is equipped.
local function SlotQuality(slotName)
  local getSlot = G("GetInventorySlotInfo")
  local getQuality = G("GetInventoryItemQuality")
  if type(getSlot) ~= "function" or type(getQuality) ~= "function" then
    return nil
  end

  local slotOk, inventorySlot = pcall(getSlot, slotName)
  if not slotOk or not tonumber(inventorySlot) then return nil end

  local qualityOk, quality = pcall(getQuality, "player", inventorySlot)
  return qualityOk and tonumber(quality) or nil
end

-- Rarity colour on the tooltip's name line, from the slot the native handler
-- is about to describe. Behavior only -- no texture, font or anchor is touched
-- -- so the Classic theme installs it on the untouched paper doll exactly like
-- the Modern one, the way modules/quest.lua hooks its reward rows.
local function HookSlotTooltip(slot, slotName)
  if not slot or slot.uuiSlotTooltipHook then return end
  slot.uuiSlotTooltipHook = true

  U.PostHookScript(slot, "OnEnter", function()
    if type(U.ColorTooltipItemName) == "function" then
      U.ColorTooltipItemName(nil, SlotQuality(slotName))
    end
  end)
  U.PostHookScript(slot, "OnLeave", function()
    if type(U.ClearTooltipItemName) == "function" then
      U.ClearTooltipItemName()
    end
  end)
end

local function StyleSlot(slotName, keepNativeChrome)
  local slot = G("Character" .. slotName)
  if not slot then return end

  HookSlotTooltip(slot, slotName)

  -- GetInventorySlotInfo/GetInventoryItemQuality are documented by this
  -- client but not yet runtime-verified. Keep both guarded: an unavailable
  -- call leaves the slot on the neutral empty border instead of interrupting
  -- the character-sheet refresh.
  --
  -- The table is deliberately persistent. StyleStockButton's OnLeave hook
  -- closes over it on the first styling pass, so mutating the same table when
  -- equipment changes makes hover restore the current rarity colour rather
  -- than the original neutral outline.
  local border = slot.uuiCharacterBorder
  if not border then
    border = { M.Unpack(M.slotBorder.empty) }
    slot.uuiCharacterBorder = border
  end

  local color = M.slotBorder.empty
  local quality = SlotQuality(slotName)
  if quality then
    if quality > M.qualityLimit then
      -- The stronger rare blue belongs only to the native Classic and the
      -- metal-framed Modern WoW character surfaces. Modern keeps stock colour.
      local themedColor = keepNativeChrome or modernWowTabMode
      color = (themedColor and U.ItemQualityBorderColor(quality) or
               U.ItemQualityColor(quality)) or M.slotBorder.plain
    else
      color = M.slotBorder.plain
    end
  end

  border[1], border[2], border[3], border[4] = M.Unpack(color)

  if keepNativeChrome then
    -- Classic keeps the client's paper-doll artwork and button states intact.
    -- Use the same semantic rarity glow as Modern WoW over the native frame.
    U.SetGearQualityGlow(slot, border)
  else
    local icon = G("Character" .. slotName .. "IconTexture")
    U.StyleStockButton(slot, { icon = icon, border = border })
  end
  U.SetBorderColor(slot, M.Unpack(border))
end

local function StyleSlots(keepNativeChrome)
  local i
  for i = 1, table.getn(SLOTS) do
    StyleSlot(SLOTS[i], keepNativeChrome)
  end
end

-- Classic keeps the native level/race/class line. Colour only the class name
-- inside that localized stock text, then lower the line two pixels without
-- replacing the client's typography or the rest of its wording.
local function RefreshClassicClassLine()
  local text = G("CharacterLevelText")
  if not text then return end

  local textOk, value = pcall(text.GetText, text)
  local classOk, className, classToken = pcall(UnitClass, "player")
  if not textOk or type(value) ~= "string" or not classOk or
     type(className) ~= "string" then
    return
  end

  local r, g, b = M.ClassColor(classToken)
  if not r then return end
  local coloredName = string.format("|cff%02x%02x%02x%s|r",
    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5), className)
  if string.find(value, coloredName, 1, true) then return end

  local first, last = string.find(value, className, 1, true)
  if first then
    pcall(text.SetText, text,
      string.sub(value, 1, first - 1) .. coloredName ..
      string.sub(value, last + 1))
  end
end

local function ShiftClassicClassLine()
  local text = G("CharacterLevelText")
  if not text or type(text.GetNumPoints) ~= "function" or
     type(text.GetPoint) ~= "function" then
    return
  end

  local points = text.uuiClassicClassLineStockPoints
  local i
  if not points then
    points = {}
    local countOk, count = pcall(text.GetNumPoints, text)
    count = countOk and tonumber(count) or 0
    for i = 1, count do
      local ok, point, relative, relativePoint, x, y =
        pcall(text.GetPoint, text, i)
      if ok and point then
        table.insert(points, { point, relative, relativePoint,
                               tonumber(x) or 0, tonumber(y) or 0 })
      end
    end
    text.uuiClassicClassLineStockPoints = points
  end
  if table.getn(points) == 0 then return end

  pcall(function()
    text:ClearAllPoints()
    for i = 1, table.getn(points) do
      local point = points[i]
      text:SetPoint(point[1], point[2], point[3], point[4], point[5] - 2)
    end
  end)
end

local function BuildClassicSlotBorders()
  frame = G("CharacterFrame")
  if not frame then
    U.Debug("character: native frame unavailable")
    return false
  end

  local function RefreshClassicSlotBorders()
    StyleSlots(true)
  end
  local function QueueClassicClassLineRefresh()
    -- CharacterFrame's OnShow fires before the native paper-doll pass finishes
    -- rewriting and anchoring CharacterLevelText. Reapply both on the next
    -- shared-driver tick so the requested colour and offset are the final
    -- writes.
    U.DeferOnce("character.classic-class-line", function()
      StyleModel()
      RaiseResistancesAboveModel()
      ShiftClassicClassLine()
      RefreshClassicClassLine()
    end)
  end

  RefreshClassicSlotBorders()
  StyleModel()
  RaiseResistancesAboveModel()
  QueueClassicClassLineRefresh()
  U.PostHookScript(frame, "OnShow", function()
    RefreshClassicSlotBorders()
    QueueClassicClassLineRefresh()
  end)
  U.PostHookScript(G("PaperDollFrame"), "OnShow",
    QueueClassicClassLineRefresh)
  U.RegisterEvent("PLAYER_LEVEL_UP", QueueClassicClassLineRefresh)
  -- The client calls PaperDollItemSlotButton_Update once per slot button, and
  -- its gear and bag slots all react to bag/lock events: one item moved between
  -- bags ran this full every-slot pass hundreds of times inside one frame,
  -- window open or not (measured 2026-09-16 with UnrealRuntimeProbe bagmove ab:
  -- 180-260ms frames that survived switching unrealUI bags and bars off).
  -- Closed window: nothing to draw, OnShow restyles it. Open: one deferred pass.
  U.PostHookGlobal("PaperDollItemSlotButton_Update", function()
    local ok, shown = pcall(frame.IsShown, frame)
    if not (ok and shown) then return end
    U.DeferOnce("character.classic-slot-borders", RefreshClassicSlotBorders)
  end)
  return true
end

-- Resistance readouts (MagicResFrame1-5).
--
-- Measured on this client with /uui res (UnrealUIDiagDB.resistances,
-- USER_CONFIRMED_INGAME). Each MagicResFrame<i> is a 32x29 Frame with
-- mouse enabled, GetID() giving the real school id (6,2,3,4,5 =
-- arcane/fire/nature/frost/shadow, so the frame index is NOT the id), and
-- exactly two native regions of interest:
--
--   * an unnamed BACKGROUND Texture, 32x29, filling the frame -- the client's
--     own resistance icon, already cropped per school;
--   * MagicResText<i>, the BACKGROUND FontString holding the value.
--
-- Two things that dump settled, both of which had defeated earlier passes:
--
--   * GetTexture() returns nothing for these regions on this client, so the
--     path filter UnrealPfUI's GetNoNameObject relies on cannot find the icon
--     here. GetName() carries it instead -- the region reads as
--     "Interface/PaperDollInfoFrame/UI-Character-ResistanceIcons_0x...". That
--     name, not the texture path, is what identifies it below.
--   * The icon path is Interface/PaperDollInfoFrame/UI-Character-
--     ResistanceIcons, not Vanilla's PaperDoll sheet. An earlier pass created
--     its own texture pointing at the Vanilla path and got an invisible
--     region (it showed up in the dump as a 28x25 ARTWORK texture with no
--     texture at all), which is why the icons stayed missing.
--
-- So unrealUI reuses the native region rather than owning one: it is kept out
-- of the strip pass and simply shown again, at its native full-frame anchor
-- and native crop. The 1-unit outline is OVERLAY and still draws over it.
local RESIST_ICON_MARKER = "ResistanceIcons"

local function FindResistIcon(res)
  if res.uuiResistIcon then return res.uuiResistIcon end
  if not res.GetRegions then return nil end

  local ok, regions = pcall(function() return { res:GetRegions() } end)
  if not ok then return nil end

  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    local typeOk, objectType = false, nil
    if region and region.GetObjectType then
      typeOk, objectType = pcall(region.GetObjectType, region)
    end
    if typeOk and objectType == "Texture" and region.GetName then
      local nameOk, name = pcall(region.GetName, region)
      if nameOk and type(name) == "string" and
         string.find(name, RESIST_ICON_MARKER, 1, true) then
        res.uuiResistIcon = region
        -- The name is "<texture path>_0x<address>", so the path can be
        -- recovered from it. Kept because U.HideRegion's strip recipe calls
        -- SetTexture(nil): if any pass ever reaches this region before the
        -- keep set does, showing it again is not enough to bring the art back,
        -- and GetTexture() cannot report what it used to be on this client.
        res.uuiResistIconPath = string.gsub(name, "_0[xX]%x+$", "")
        return region
      end
    end
  end
  return nil
end

-- Tooltip.
--
-- The client owns a per-school tooltip of its own ("Increases the ability to
-- resist frost-based attacks, spells and abilities. / Resistance against level
-- 20: None", USER_CONFIRMED_INGAME screenshot) and the dump shows the native
-- OnEnter handler still attached with mouse enabled. That text is richer and
-- correctly localized, so unrealUI does not replace it -- it only makes sure
-- the native handler is left able to run, and it comes up inside the shared
-- GameTooltip that modules/tooltip.lua already skins, which is the same
-- component the equipment slots' tooltips use.
--
-- No OnEnter hook is installed here. The previous pass added one that rebuilt
-- the tooltip from UnitResistance; that both discarded the client's own text
-- and, since UnitResistance is only DOCUMENTED_NOT_RUNTIME_VERIFIED here, gave
-- a silent handler error a way to leave the tooltip cleared but never shown --
-- indistinguishable in game from no tooltip at all.
-- Native crop of each school inside the resistance sheet, one row per
-- MagicResFrame index. These are the client's own coordinates for this texture,
-- confirmed by UnrealPfUI re-applying exactly these values to the same regions
-- (skins/blizzard/character.lua:25-31, WORKING_SOURCE).
--
-- They have to be restated rather than read back and adjusted: GetTexCoord has
-- no compact-evidence record on this client, so the crop already in place is not
-- readable.
local RESIST_TEXCOORD = {
  { 0.21875, 0.78125, 0.25,        0.3203125  },
  { 0.21875, 0.78125, 0.0234375,   0.09375    },
  { 0.21875, 0.78125, 0.13671875,  0.20703125 },
  { 0.21875, 0.78125, 0.36328125,  0.43359375 },
  { 0.21875, 0.78125, 0.4765625,   0.546875   },
}

-- The sheet paints a rounded bevelled ring around each glyph, which is stock
-- decorative chrome the design system does not allow to survive on a skinned
-- surface (rules/unreal-ui-design.md, native texture policy) -- and it is baked
-- into the art rather than carried by a separate region, so it can only be
-- cropped out. This trims each native rect inwards by a fraction of its own
-- span, keeping the glyph and dropping the ring, in the same spirit as the
-- 0.08/0.92 trim U.StyleStockButton applies to item icons.
local RESIST_ICON_TRIM = 0.14

local function ApplyResistIconCrop(icon, index)
  local coords = RESIST_TEXCOORD[index]
  if not coords then return end

  local insetX = (coords[2] - coords[1]) * RESIST_ICON_TRIM
  local insetY = (coords[4] - coords[3]) * RESIST_ICON_TRIM

  pcall(icon.SetTexCoord, icon,
        coords[1] + insetX, coords[2] - insetX,
        coords[3] + insetY, coords[4] - insetY)
end

local function StyleResistance(res, index)
  local icon = FindResistIcon(res)

  -- The icon has to be named in the keep set on every pass: StyleResistances is
  -- re-run by the reapply hooks, and without this the strip pass hides the very
  -- region being restored one line later.
  U.StripStockTextures(res, { icon = icon })
  U.CreateBackdrop(res, { background = { 0.03, 0.03, 0.03, 0.82 } })

  -- U.HideRegion clears, hides and alpha-0s a region, so restoring one that a
  -- previous pass stripped takes both calls back.
  if icon then
    if res.uuiResistIconPath then
      pcall(icon.SetTexture, icon, res.uuiResistIconPath)
    end
    ApplyResistIconCrop(icon, index)

    -- Inset by the outline thickness so unrealUI's own 1-unit border stays the
    -- only edge on the square, with the glyph flat inside it.
    local border = U.BorderSize()
    pcall(function()
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", res, "TOPLEFT", border, -border)
      icon:SetPoint("BOTTOMRIGHT", res, "BOTTOMRIGHT", -border, border)
    end)

    pcall(icon.Show, icon)
    pcall(icon.SetAlpha, icon, 1)
  end

  SetTextFont(G("MagicResText" .. index), M.fontSize.small, WHITE)
end

-- The resistance column overlaps CharacterModelFrame, and unrealUI's own
-- click-rotate catcher (StyleModel below) is SetAllPoints on that model with
-- mouse enabled -- so it sat over the resistance frames and swallowed their
-- hover. /uui res proved the native OnEnter itself is fine: called directly it
-- returns ok and shows a populated tooltip ("Frost Resistance 0"), so nothing
-- was wrong with the handler or the skin, the mouse simply never reached it.
--
-- Raising the container above the catcher is the narrow fix; the catcher still
-- covers the rest of the model, so click-rotate keeps working everywhere the
-- resistances are not.
-- Measured overlap (/uui res, USER_CONFIRMED_INGAME): unrealUI's click-rotate
-- catcher spans x 344-577 / y 369-593 over CharacterModelFrame, and the
-- resistance column sits at x 544-576 inside it. Both were MEDIUM strata at
-- level 4 -- a tie the catcher wins, which is why hovering an icon produced no
-- OnEnter at all while a gear slot beside it behaved normally.
--
-- The level has to be set on each MagicResFrame, not on their container: this
-- client does not push a SetFrameLevel down to existing children, so an earlier
-- pass that raised CharacterResistanceFrame to level 9 left the five frames
-- that actually take the mouse still sitting at 4.
RaiseResistancesAboveModel = function()
  local catcher = G("UnrealUICharacterModelRotateCatcher")
  if not catcher then return end

  local strataOk, strata = pcall(catcher.GetFrameStrata, catcher)
  local levelOk, level = pcall(catcher.GetFrameLevel, catcher)
  level = levelOk and tonumber(level) or nil

  local i
  for i = 1, 5 do
    local res = G("MagicResFrame" .. i)
    if res then
      if strataOk and strata then pcall(res.SetFrameStrata, res, strata) end
      if level then pcall(res.SetFrameLevel, res, level + 5) end
    end
  end
end

local function StyleResistances()
  local i
  for i = 1, 5 do
    local res = G("MagicResFrame" .. i)
    if res then StyleResistance(res, i) end
  end
  RaiseResistancesAboveModel()
end

-- FontString names below (CharacterStrengthLabel/Value, MeleeAttackPower*,
-- etc.) are UNVERIFIED against this client's compact evidence -- no
-- query_compat.py or query_unrealUI.py record covers them, and UnrealPfUI's own
-- Character skin never touches stat text either. Every call is G()+pcall
-- guarded so a wrong name simply leaves that line un-recoloured (native
-- black/white text) rather than breaking the sheet; confirm in-game and fold
-- the real names into knowledge.json once checked.
local function StyleAttributes()
  local labels = {
    "CharacterStrength", "CharacterAgility", "CharacterStamina",
    "CharacterIntellect", "CharacterSpirit", "CharacterArmor",
  }
  local i
  for i = 1, table.getn(labels) do
    SetTextFont(G(labels[i] .. "Label"), M.fontSize.normal, DIM)
    SetTextFont(G(labels[i] .. "Value"), M.fontSize.normal, WHITE)
  end

  local attackLabels = {
    "MeleeAttackPower", "MeleeDamage", "MeleeAttackBonus",
    "RangedAttackPower", "RangedDamage", "RangedAttackBonus",
    "Defense", "Armor", "ResistanceFrame",
  }
  for i = 1, table.getn(attackLabels) do
    SetTextFont(G(attackLabels[i] .. "Label"), M.fontSize.small, DIM)
    SetTextFont(G(attackLabels[i] .. "Value"), M.fontSize.small, WHITE)
  end
end

StyleModel = function()
  local model = G("CharacterModelFrame")
  U.EnableStockModelDrag(model, {
    name = "UnrealUICharacterModelRotateCatcher",
    ticker = "character.model-rotate",
    leftButton = G("CharacterModelFrameRotateLeftButton"),
    rightButton = G("CharacterModelFrameRotateRightButton"),
  })
end

-- Flat, actively-tracked tab bar (see U.StyleStockTabGroup). Positioning is
-- kept separate from styling: a hidden tab (the Pet slot with no pet out)
-- still occupies its index but must not be chained into, or the tabs after
-- it would inherit a gap sized to an invisible button -- WORKING_SOURCE from
-- UnrealPfUI's own character skin, which guards the same chain on
-- lastTab:IsShown().
local function TabStrip()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("CharacterFrameTab" .. i)
  end
  return tabs
end

-- Whether the conditional Pet tab is currently in the run. Counted rather
-- than read off a fixed index: Pet is the only tab the client shows and hides
-- here, so a full run is a run with a pet in it, and that holds whatever
-- position this client gives the tab.
local function HasPetTab()
  local tabs, shown, i = TabStrip(), 0, nil
  for i = 1, TAB_COUNT do
    local tab = tabs[i]
    if tab and tab.IsShown then
      local ok, visible = pcall(tab.IsShown, tab)
      if ok and visible then shown = shown + 1 end
    end
  end
  return shown >= TAB_COUNT
end

-- Chain + fit. The Pet tab is the fifth in the run and pushed it past the
-- window edge; U.FitStockTabStrip rebuilds each tab as label + padding and
-- reduces that padding until the whole run fits between the window's insets,
-- so the tabs get tighter rather than the strip getting longer.
local function LayoutTabs()
  local tabs = TabStrip()

  -- Focused runtime probe character.tabs.click_geometry.v1 measured the
  -- client's selected-tab pass changing every visible label from its stable
  -- small FontObject to a larger one for several rendered frames. The native
  -- tab widths followed those transient metrics (64/70/47/52 became
  -- 74/81/52/59), and the internal writes bypassed the Lua SetWidth methods.
  -- Restore the shared component's font state before measuring, otherwise the
  -- fit faithfully turns that native transition into a visibly resizing strip.
  if modernWowTabMode then
    local i
    for i = 1, table.getn(tabs) do
      local tab = tabs[i]
      if tab and type(tab.uuiTabRefreshFont) == "function" then
        tab.uuiTabRefreshFont()
      end
    end
  end
  U.ChainStockTabs(tabs, TAB_GAP)

  local padding = TAB_PADDING
  if HasPetTab() then padding = padding + TAB_PET_PADDING end
  -- The Dragonflight tab art needs more room inside its end caps.
  if modernWowTabMode then
    padding = M.modernWow.tab.padding
  end

  -- Hung off the panel rather than the frame: the panel is the visible window
  -- surface, and CharacterFrame extends well past its bottom edge, so a strip
  -- placed against the frame overlapped the interface it belongs under.
  local fits, info = U.FitStockTabStrip(tabs, frame or G("CharacterFrame"), {
    gap = TAB_GAP,
    left = PANEL_INSET_LEFT,
    right = PANEL_INSET_RIGHT,
    padding = padding,
    anchor = panel and {
      frame = panel,
      point = "TOPLEFT",
      relativePoint = "BOTTOMLEFT",
      x = modernWowTabMode and 5 or 0,
      y = -TAB_DROP,
    } or nil,
  })
  tabFit = info
  if info then info.fits = fits end
  if info and info.reason then
    U.Debug("character: tab strip not sized - " .. info.reason)
  end
end

-- The client resizes a tab from its own metrics whenever the sheet switches
-- pages, and not always inside the OnClick this module can hook: /uui tabs
-- showed widths already back to native between two passes with only a tab
-- click in between. Rather than hunt every native resize path, the applied
-- widths are re-asserted whenever one drifts from its target, and only while
-- the sheet is open. A pass that is already correct writes nothing.
--
-- The targets themselves can also be stale: the pass on open runs before the
-- client has settled which tabs are shown and what their labels measure, so
-- the correct sizes only appeared after the first click re-measured. The shown
-- run and each label width are compared too, and any change re-measures.
local function TabFitDrifted()
  local info = tabFit
  if not info or not info.rows then return true end

  local tabs = TabStrip()
  local shown = 0
  local i
  for i = 1, table.getn(tabs) do
    local tab = tabs[i]
    local ok, visible = false, false
    if tab and tab.IsShown then ok, visible = pcall(tab.IsShown, tab) end
    if ok and visible then
      shown = shown + 1
      local row = info.rows[shown]
      if not row or row.name ~= tab:GetName() then return true end
      local fsOk, fontstring = pcall(tab.GetFontString, tab)
      if fsOk and fontstring and fontstring.GetStringWidth then
        local wOk, width = pcall(fontstring.GetStringWidth, fontstring)
        if wOk and tonumber(width) and width > 0
           and math.abs(width - row.label) > 0.5 then
          return true
        end
      end
    end
  end
  if shown ~= table.getn(info.rows) then return true end

  for i = 1, table.getn(info.rows) do
    local row = info.rows[i]
    local tab = G(row.name)
    if tab and tab.GetWidth and tonumber(row.target) then
      local ok, width = pcall(tab.GetWidth, tab)
      if ok and tonumber(width) and math.abs(width - row.target) > 0.5 then
        return true
      end
    end
  end
  return false
end

-- What the last layout pass actually measured and wrote. The tabs visibly kept
-- their native width through two sizing attempts, and the two explanations for
-- that -- the label measurement being wrong, or SetWidth being overwritten
-- after the pass -- are only distinguishable from the client. Each row carries
-- the width read back immediately after the write, so a target that did not
-- stick is separable from one that stuck and was reset later.
function U.CharacterTabReport()
  LayoutTabs()

  local report = { rows = {} }
  local info = tabFit
  if not info then
    report.reason = "no layout pass has run"
    return report
  end

  report.reason = info.reason
  report.fits = info.fits
  report.count = info.count
  report.padding = info.padding
  report.labelTotal = info.labelTotal
  report.available = info.available
  report.frameWidth = info.frameWidth

  local i
  for i = 1, table.getn(info.rows) do
    local row = info.rows[i]
    -- Read again now, one full frame after the write, so a native resize that
    -- lands between the two reads shows up as after ~= live.
    local tab = G(row.name)
    local live
    if tab and tab.GetWidth then
      local ok, value = pcall(tab.GetWidth, tab)
      if ok then live = value end
    end
    table.insert(report.rows, {
      name = row.name,
      label = row.label,
      target = row.target,
      before = row.before,
      after = row.after,
      live = live,
    })
  end
  return report
end

local function StyleTabs()
  local tabs = TabStrip()
  U.StyleStockTabGroup(tabs, 1)

  -- The native tab template resizes a tab from its own metrics when the sheet
  -- switches pages, which would undo the padding fit. Re-laying out after the
  -- click restores it; the pass is idempotent.
  local i
  for i = 1, table.getn(tabs) do
    if tabs[i] then U.PostHookScript(tabs[i], "OnClick", LayoutTabs) end
  end

  LayoutTabs()
end

-- The shared tab component owns the visible active state, while the client
-- owns which Character page is actually shown. Mouse clicks normally update
-- both, but ToggleCharacter("PaperDollFrame") changes selectedTab directly.
-- Keep the owned state aligned with the measured native field instead of
-- assuming the last clicked tab is still the selected one.
local function SyncTabSelection()
  if not frame then return end
  local selected = tonumber(frame.selectedTab)
  if not selected or selected < 1 or selected > TAB_COUNT then return end

  local tabs = TabStrip()
  local i
  for i = 1, table.getn(tabs) do
    local tab = tabs[i]
    local active = i == selected
    if tab and type(tab.SetActive) == "function"
       and tab.uuiTabActive ~= active then
      tab.SetActive(active)
    end
  end
end

-- Focused probe character.tabs.click_geometry.v1 captured the C binding's
-- exact fixed-arity call: ToggleCharacter("PaperDollFrame"). With the window
-- open on Honor, the first call changed selectedTab 5 -> 1 and left the frame
-- visible; the second identical call hid it. Reproduce that verified native
-- sequence inside one binding call, but only for the Modern WoW drawing path
-- when the request began on another Character page. Calling the original twice avoids
-- introducing an unverified HideUIPanel/CharacterFrame:Hide path.
local function InstallModernWowCharacterToggle()
  if not modernWowTabMode or toggleCharacterOriginal then return end
  local original = G("ToggleCharacter")
  if type(original) ~= "function" then
    U.Debug("character: ToggleCharacter unavailable")
    return
  end

  local wrapper = function(request)
    local closeAfterSwitch = false
    if request == "PaperDollFrame" and frame and frame.IsShown then
      local ok, shown = pcall(frame.IsShown, frame)
      local selected = tonumber(frame.selectedTab)
      closeAfterSwitch = ok and shown and selected and selected ~= 1
    end

    local r1, r2, r3, r4, r5 = original(request)
    if closeAfterSwitch then original(request) end
    SyncTabSelection()
    return r1, r2, r3, r4, r5
  end

  if U.SetG("ToggleCharacter", wrapper) and G("ToggleCharacter") == wrapper then
    toggleCharacterOriginal = original
  else
    U.Debug("character: ToggleCharacter wrapper assignment was refused")
  end
end

-- ---------------------------------------------------------------------------
-- Reputation / Skills / Honor tabs
--
-- Same dark pfUI-modern treatment as the Character tab, applied once at
-- BuildFrame like UnrealPfUI's own Character skin: these are static reskins,
-- not re-hooked to native update functions, matching the Quest Log/Spellbook
-- effort level for a first pass. Native StatusBar retexturing
-- (SetStatusBarTexture with a plain path on an existing stock bar) is
-- BEHAVIOR_VERIFIED via modules/tooltip.lua's GameTooltipStatusBar handling;
-- everything else here is WORKING_SOURCE from UnrealPfUI's
-- skins/blizzard/character.lua, unconfirmed on Unreal specifically.
-- ---------------------------------------------------------------------------

-- Matches modules/tooltip.lua's verified StyleStatusBar exactly: retexture,
-- then CreateBackdrop, then explicitly re-zero the backdrop border colour.
-- U.StripStockTextures must NOT run on an existing native StatusBar first --
-- USER_CONFIRMED_INGAME: an earlier version stripped the bar's regions before
-- retexturing it and the fill never came back, leaving a flat empty bar. The
-- StatusBar's fill is a real Texture region enumerable via GetRegions(), so a
-- blanket strip hides the exact region SetStatusBarTexture was about to
-- reuse; only SetStatusBarTexture is a safe way to touch it.
local function StyleBar(bar)
  if not bar then return end
  pcall(bar.SetStatusBarTexture, bar, M.texture.plain)
  U.CreateBackdrop(bar, { background = M.color.healthBg, border = M.color.border })
  pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 0)
end

local REP_ROWS = 10
local UpdateReputationRows
local StyleReputationBar
local RefreshReputationDetailControls

local function ToggleReputationHeader(header)
  local index = header and header.uuiReputationIndex
  if not index then return end

  local fn = G(header.uuiCollapsed and "ExpandFactionHeader" or
               "CollapseFactionHeader")
  local handled = false
  if type(fn) == "function" then
    handled = pcall(fn, index)
  end

  -- If this client does not expose the dedicated function, ask the actual
  -- header Button to click itself.  This preserves the engine-dispatched path
  -- that the user confirmed works when clicking the text.
  if not handled and type(header.Click) == "function" then
    handled = pcall(header.Click, header)
  end

  if handled then
    local refresh = G("ReputationFrame_Update")
    if type(refresh) == "function" then pcall(refresh) end
    if type(UpdateReputationRows) == "function" then UpdateReputationRows() end
  else
    U.Error("reputation: no working header collapse action")
  end
end

-- GetFactionInfo is already the working-source fallback used by xpbar.lua.
-- The two header flags below follow its Vanilla-shaped tuple so the shared
-- collapse component can be driven from real faction state rather than from
-- the stock +/- artwork it replaces.  No compact runtime record covers the
-- tuple on this client yet, so every read stays guarded and an unavailable
-- result simply hides the custom icon rather than guessing a state.
UpdateReputationRows = function()
  local getFactionInfo = G("GetFactionInfo")
  if type(getFactionInfo) ~= "function" then return end

  local offset = 0
  local offsetFn = G("FauxScrollFrame_GetOffset")
  local scroll = G("ReputationListScrollFrame")
  if type(offsetFn) == "function" and scroll then
    local offsetOk, value = pcall(offsetFn, scroll)
    if offsetOk and tonumber(value) then offset = value end
  end

  local i
  for i = 1, REP_ROWS do
    local header = G("ReputationHeader" .. i)
    if header then
      local infoOk, name, _, _, _, _, _, _, _, isHeader, isCollapsed =
        pcall(getFactionInfo, i + offset)
      infoOk = infoOk and type(name) == "string"
      header.uuiReputationIndex = infoOk and isHeader and (i + offset) or nil
      header.uuiCollapsed = infoOk and isHeader and isCollapsed and true or false
      U.SetStockCollapseState(header, infoOk and isHeader, isCollapsed and true or false)
    end

    if type(StyleReputationBar) == "function" then
      StyleReputationBar(G("ReputationBar" .. i))
    end
  end

  if type(RefreshReputationDetailControls) == "function" then
    RefreshReputationDetailControls()
  end
end

StyleReputationBar = function(bar)
  if not bar then return end

  -- SetStatusBarTexture retargets the live fill to unrealUI's plain texture.
  -- GetStatusBarTexture is absent on this client, so locate that fill among the
  -- direct Texture regions by its newly assigned path, preserve it, and strip
  -- every other native texture from the row.
  pcall(bar.SetStatusBarTexture, bar, M.texture.plain)

  local keep, foundFill = {}, false
  if bar.GetRegions then
    local regionsOk, regions = pcall(function() return { bar:GetRegions() } end)
    if regionsOk and type(regions) == "table" then
      local i
      for i = 1, table.getn(regions) do
        local region = regions[i]
        if region and type(region.GetTexture) == "function" then
          local textureOk, texture = pcall(region.GetTexture, region)
          if textureOk and type(texture) == "string" and
             string.lower(texture) == string.lower(M.texture.plain) then
            keep[region] = true
            foundFill = true
          end
        end
      end
    end
  end

  -- Fail closed if the fill cannot be identified; stripping without it is the
  -- previously confirmed empty-bar failure.
  if foundFill then U.StripStockTextures(bar, { keep = keep }) end

  U.CreateBackdrop(bar, {
    background = { 0.012, 0.016, 0.024, 0.94 },
    border = { 0.16, 0.18, 0.23, 1 },
  })
  pcall(bar.SetBackdropBorderColor, bar, 0, 0, 0, 0)
end

-- The native detail refresh restores its checkbox geometry when a faction is
-- selected.  Own the compact layout and reapply it after every reputation
-- update so the boxes and their attached native labels cannot overlap.
RefreshReputationDetailControls = function()
  local detail = G("ReputationDetailFrame")
  if not detail then return end

  local controls = {
    G("ReputationDetailAtWarCheckBox"),
    G("ReputationDetailInactiveCheckBox"),
    G("ReputationDetailMainScreenCheckBox"),
  }
  local offsets = { 72, 48, 24 }
  local i
  for i = 1, table.getn(controls) do
    local checkbox = controls[i]
    if checkbox then
      U.StyleStockCheckbox(checkbox, {
        size = 14,
        labelGap = 4,
        labelYOffset = -1,
      })
      pcall(function()
        checkbox:ClearAllPoints()
        checkbox:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 24, offsets[i])
      end)
    end
  end
end

local function StyleReputationTab()
  local rep = G("ReputationFrame")
  if not rep then return end
  U.StripStockTextures(rep)

  local count = tonumber(G("NUM_FACTIONS_DISPLAYED")) or REP_ROWS
  local i
  for i = 1, count do
    local bar = G("ReputationBar" .. i)
    if bar then
      StyleReputationBar(bar)
      SetTextFont(bar, M.fontSize.small, WHITE)
      U.PostHookScript(bar, "OnClick", UpdateReputationRows)

      local war = G("ReputationBar" .. i .. "AtWarCheck")
      U.StyleStockCheckbox(war, 13)
    end

    local header = G("ReputationHeader" .. i)
    if header then
      header.uuiCollapseClick = ToggleReputationHeader
      U.StyleStockCollapseButton(header)
      if modernWowTabMode and type(U.ModernWowCollapseFace) == "function" then
        pcall(U.ModernWowCollapseFace, header)
      end
      U.PostHookScript(header, "OnClick", UpdateReputationRows)
      SetTextFont(header, M.fontSize.normal, GOLD)
    end
  end

  U.StripStockTextures(G("ReputationListScrollFrame"))
  U.StyleStockScrollbar(G("ReputationListScrollFrameScrollBar"))
  U.PostHookScript(G("ReputationListScrollFrame"), "OnVerticalScroll", UpdateReputationRows)

  local detail = G("ReputationDetailFrame")
  if detail then
    U.StripStockTextures(detail)
    U.CreateBackdrop(detail, { background = { 0.01, 0.01, 0.01, 0.78 } })
    U.StyleStockCloseButton(G("ReputationDetailCloseButton"), detail, -6, -6)
    U.PostHookScript(detail, "OnShow", RefreshReputationDetailControls)
  end

  RefreshReputationDetailControls()
  UpdateReputationRows()
end

-- ---------------------------------------------------------------------------
-- Skills tab
--
-- Reworked to the same live-refresh shape as modules/questlog.lua rather than
-- the earlier static pass: SkillFrame_Update repaints native art over a
-- one-time style, and the +/- collapse icon needs a real expanded/collapsed
-- read to ever show correctly, exactly like quest log headers did.
--
-- SKILL_ROWS: a fixed upper bound rather than SKILLS_TO_DISPLAY, matching
-- questlog.lua's QUEST_ROWS -- both are WORKING_SOURCE guesses at a Vanilla
-- constant with no compact-DB record; a row past the real count is simply
-- absent from G() and every loop body already guards for that.
--
-- GetNumSkillLines/GetSkillLineInfo/CollapseSkillHeader/ExpandSkillHeader are
-- UNVERIFIED on this client (no query_compat.py record). Header collapse
-- follows questlog.lua's ToggleHeader recipe exactly -- try the dedicated
-- native call, fall back to forwarding the row's own OnClick, and record
-- which path actually worked so it can be checked in game rather than
-- assumed.
-- ---------------------------------------------------------------------------
local SKILL_ROWS = 30

local skillCollapseReport = { collapse = "untested", expand = "untested",
                              nativeClick = "untested" }

function U.SkillCollapseReport()
  return skillCollapseReport
end

-- Forward-declared: ToggleSkillHeader closes over this and is defined ahead
-- of UpdateSkillRows's real body -- a later `local function UpdateSkillRows`
-- would not be visible as an upvalue inside a function textually defined
-- before it (Lua locals only scope forward from their declaration; the same
-- issue questlog.lua's SyncTrackedQuestMemory comment documents).
local UpdateSkillRows
local StyleUnlearnButton

local function ToggleSkillHeader(row)
  local index = row and row.uuiSkillIndex
  if not index then return end

  local collapsed = row.uuiCollapsed
  local name = collapsed and "ExpandSkillHeader" or "CollapseSkillHeader"
  local key = collapsed and "expand" or "collapse"
  local fn = G(name)
  local handled = false

  if type(fn) == "function" then
    local ok, err = pcall(fn, index)
    skillCollapseReport[key] = ok and "ok" or ("error: " .. tostring(err))
    if ok then
      handled = true
      local update = G("SkillFrame_Update")
      if type(update) == "function" then pcall(update) end
    end
  else
    skillCollapseReport[key] = "missing"
  end

  if not handled and row.GetScript then
    local scriptOk, native = pcall(row.GetScript, row, "OnClick")
    if scriptOk and native then
      skillCollapseReport.nativeClick = "present"
      pcall(native, row)
      handled = true
    else
      skillCollapseReport.nativeClick = "missing"
    end
  end

  -- Always resync unrealUI's own icons/bars after a toggle, regardless of
  -- which path above fired. USER_CONFIRMED_INGAME: relying only on the
  -- wrapped SkillFrame_Update call left rows below a just-collapsed header
  -- with no collapse icon at all -- physical rows get reused for different
  -- skill lines once the list reflows, and if that global's real name on
  -- this client differs from the guess above, U.PostHookGlobal("SkillFrame_
  -- Update", ...) never attaches and this was the only place still driving a
  -- refresh at all.
  if type(UpdateSkillRows) == "function" then
    local ok, err = pcall(UpdateSkillRows)
    if not ok then U.Error("skills resync: " .. tostring(err)) end
  end
end

-- Flat modern bar: plain-textured fill on a dark backdrop, no native cap/lip
-- art. SetStatusBarColor is left untouched -- native code already uses it to
-- distinguish a learned skill (blue) from an unusable specialization choice
-- (grey), and that signal is worth keeping through the reskin.
--
-- Each numbered skill row has a separate sibling frame, "SkillRankFrame<i>
-- Border", carrying the native rounded end-cap/bevel art -- it is not a
-- region on the bar itself, so StripStockTextures(bar) never touches it and
-- the flat restyle was rendering underneath the untouched pill graphic.
-- WORKING_SOURCE (UnrealPfUI skins/blizzard/character.lua): pfUI strips this
-- exact sibling frame; query_compat.py has no record for Skill/SkillRankFrame
-- at all, so this is a no-evidence fallback, not a confirmed name on this
-- client, and should be checked in game.
local function StyleSkillBar(bar, borderName)
  if not bar then return end
  if borderName then U.StripStockTextures(G(borderName)) end
  StyleBar(bar)
  SetTextFont(bar, M.fontSize.small, WHITE)
end

local function BuildSkillRows()
  local i
  for i = 1, SKILL_ROWS do
    local header = G("SkillTypeLabel" .. i)
    if header then
      header.uuiCollapseClick = ToggleSkillHeader
      U.StyleStockCollapseButton(header)
      if modernWowTabMode and type(U.ModernWowCollapseFace) == "function" then
        pcall(U.ModernWowCollapseFace, header)
      end
    end
  end
end

UpdateSkillRows = function()
  local getCount = G("GetNumSkillLines")
  local getInfo = G("GetSkillLineInfo")
  if type(getCount) ~= "function" or type(getInfo) ~= "function" then return end

  local ok, numEntries = pcall(getCount)
  if not ok or not tonumber(numEntries) then return end

  -- FOCUSED_RUNTIME_PROBE (skillscroll.first_open_range.v1, 2026-09-16): on
  -- the first opening the list bar is shown with min/max 0/0 although the
  -- native update already sized the scroll child (13 lines x 15 = 195). The
  -- modern-wow pane is 220 high, so the client's own overflow recalculation
  -- (UpdateScrollChildRect) yields 0 as well. A header collapse re-runs the
  -- native update, which sets 0..(lines - SKILLS_TO_DISPLAY) *
  -- SKILLFRAME_SKILL_HEIGHT; that same range is applied here when missing.
  -- GetVerticalScrollRange followed the Slider's max in the same capture.
  local listBar = G("SkillListScrollFrameScrollBar")
  local display = G("SKILLS_TO_DISPLAY")
  local rowHeight = G("SKILLFRAME_SKILL_HEIGHT")
  if listBar and type(display) == "number" and type(rowHeight) == "number" and
     numEntries > display then
    local rangeOk, low, high = pcall(function()
      return listBar:GetMinMaxValues()
    end)
    if rangeOk and type(low) == "number" and type(high) == "number" and
       high <= low then
      pcall(listBar.SetMinMaxValues, listBar, 0, (numEntries - display) * rowHeight)
    end
  end

  local offset = 0
  local offsetFn = G("FauxScrollFrame_GetOffset")
  local scroll = G("SkillListScrollFrame")
  if type(offsetFn) == "function" and scroll then
    local offsetOk, value = pcall(offsetFn, scroll)
    if offsetOk and tonumber(value) then offset = value end
  end

  local i, headers, collapsedHeaders, visibleRows = nil, 0, 0, 0
  for i = 1, SKILL_ROWS do
    local header = G("SkillTypeLabel" .. i)
    local bar = G("SkillRankFrame" .. i)
    local index = i + offset

    if bar then visibleRows = visibleRows + 1 end

    local infoOk, name, isHeader, isExpanded
    if index <= numEntries then
      infoOk, name, isHeader, isExpanded = pcall(getInfo, index)
      infoOk = infoOk and type(name) == "string"
    end

    if header then
      header.uuiSkillIndex = infoOk and isHeader and index or nil
      header.uuiCollapsed = infoOk and isHeader and not isExpanded
      U.SetStockCollapseState(header, infoOk and isHeader, header.uuiCollapsed)
      SetTextFont(header, M.fontSize.normal, GOLD)
    end
    if bar then
      StyleSkillBar(bar, "SkillRankFrame" .. i .. "Border")
    end
  end

  for i = 1, numEntries do
    local infoOk, _, isHeader, isExpanded = pcall(getInfo, i)
    if infoOk and isHeader then
      headers = headers + 1
      if not isExpanded then collapsedHeaders = collapsedHeaders + 1 end
    end
  end

  local collapseAll = G("SkillFrameCollapseAllButton")
  U.SetStockCollapseState(collapseAll, true,
                          headers > 0 and collapsedHeaders == headers)
  if modernWowTabMode and type(U.SetModernWowScrollbarProportion) == "function" then
    U.SetModernWowScrollbarProportion(G("SkillListScrollFrameScrollBar"),
                                      visibleRows, numEntries)
  end
end

-- Modern WoW drawing path only: the Skills collapse-all plate and its button sit this much
-- higher, by request.
local SKILLS_COLLAPSE_RISE = 4

local function StyleSkillsTab()
  local skill = G("SkillFrame")
  if not skill then return end
  U.StripStockTextures(skill)

  -- The pill-shaped background behind "All" belongs to this companion frame,
  -- not to SkillFrameCollapseAllButton itself (WORKING_SOURCE, UnrealPfUI
  -- skins/blizzard/character.lua) -- StripStockTextures on the button alone
  -- left it in place.
  local expandBackground = G("SkillFrameExpandButtonFrame")
  if expandBackground and not modernWowTabMode then
    -- Unlike Quest Log, where the plate stays with the collapse button, the
    -- Skills plate is this frame's own art, so modern-wow must not strip it.
    -- U.HideRegion is permanent, so stripping first and restoring later is not
    -- an option. Flat modern still strips it.
    U.StripStockTextures(expandBackground)
  end
  if expandBackground and modernWowTabMode and frame then
    -- By request the plate rises 4px with its button (SKILLS_COLLAPSE_RISE
    -- below). Its native anchor is not known here and GetPoint is not read
    -- back (knowledge.json / frames.getpoint_relative_name_y_inverted), so
    -- its bounded numeric geometry is captured once and re-applied against
    -- the addon's window.
    pcall(function()
      local left, top = expandBackground:GetLeft(), expandBackground:GetTop()
      local width, height = expandBackground:GetWidth(), expandBackground:GetHeight()
      local frameLeft, frameTop = frame:GetLeft(), frame:GetTop()
      if not (tonumber(left) and tonumber(top) and tonumber(frameLeft) and
              tonumber(frameTop)) then return end
      expandBackground:ClearAllPoints()
      expandBackground:SetPoint("TOPLEFT", frame, "TOPLEFT", left - frameLeft,
                                top - frameTop + SKILLS_COLLAPSE_RISE)
      if tonumber(width) and width > 0 then expandBackground:SetWidth(width) end
      if tonumber(height) and height > 0 then expandBackground:SetHeight(height) end
    end)
  end

  local cancel = G("SkillFrameCancelButton")
  if cancel then pcall(cancel.Hide, cancel) end

  local collapseAll = G("SkillFrameCollapseAllButton")
  if collapseAll then
    -- The SortTab plate is not on this button (see SkillFrameExpandButtonFrame
    -- above); this strip only removes the button's own leftover art.
    if not modernWowTabMode then U.StripStockTextures(collapseAll) end
    U.StyleStockCollapseButton(collapseAll, true)
    if modernWowTabMode and type(U.ModernWowCollapseFace) == "function" then
      pcall(U.ModernWowCollapseFace, collapseAll)
    end
    U.SetStockCollapseState(collapseAll, true, false)

    -- Unlike a header row, there is no CollapseSkillHeader(index)-style API
    -- for "collapse everything" -- U.StyleStockCollapseButton's icon can only
    -- fall back to forwarding the native OnClick. USER_CONFIRMED_INGAME:
    -- that forwarded call did nothing here (pcall(native, button) does not
    -- set whatever implicit `this` this specific handler reads), while
    -- clicking the real "All" text worked. So this icon is made click- and
    -- hover-transparent so real engine-dispatched input falls through to the
    -- native button underneath, which already works correctly on its own;
    -- unrealUI keeps only the icon's cosmetic glyph and moves hover feedback
    -- onto the real button.
    local icon = collapseAll.uuiCollapseIcon
    if icon then
      pcall(icon.EnableMouse, icon, false)
      icon:SetScript("OnEnter", nil)
      icon:SetScript("OnLeave", nil)
      icon:SetScript("OnClick", nil)
    end
    local hoverTarget = icon or collapseAll
    U.PostHookScript(collapseAll, "OnEnter", function()
      U.SetBorderColor(hoverTarget, M.Unpack(M.color.accent))
    end)
    U.PostHookScript(collapseAll, "OnLeave", function()
      U.SetBorderColor(hoverTarget, M.Unpack(M.color.border))
    end)

    local scroll = G("SkillListScrollFrame")
    local anchor = scroll or skill
    pcall(function()
      collapseAll:ClearAllPoints()
      local placed = false
      if modernWowTabMode then
        local frameTopOk, frameTop = pcall(frame.GetTop, frame)
        local anchorTopOk, anchorTop = pcall(anchor.GetTop, anchor)
        if frameTopOk and anchorTopOk and
           tonumber(frameTop) and tonumber(anchorTop) then
          -- Use Quest Log's exact normal-layout X while preserving the Skills
          -- control's existing Y relative to its own list.
          collapseAll:SetPoint(
            "BOTTOMLEFT", frame, "TOPLEFT",
            M.modernWow.collapseAll.questLogX,
            anchorTop - frameTop + 4 + SKILLS_COLLAPSE_RISE)
          placed = true
        end
      end
      if not placed then
        collapseAll:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -6, 4)
      end
    end)
  end

  -- Styled before the first row update, which sizes the modern-wow thumb.
  local skillListScroll = G("SkillListScrollFrame")
  local skillListBar = G("SkillListScrollFrameScrollBar")
  U.StripStockTextures(skillListScroll)
  if modernWowTabMode and type(U.StyleModernWowScrollbar) == "function" then
    -- USER_CONFIRMED_INGAME: scrolling left header rows without their collapse
    -- icon, because the SkillFrame_Update post-hook below never fires on a
    -- scroll here. The scrollbar reports every value/range change instead,
    -- which also runs the empty-range repair in UpdateSkillRows on first open.
    U.StyleModernWowScrollbar(skillListBar, { onChange = UpdateSkillRows })
  else
    U.StyleStockScrollbar(skillListBar)
  end

  BuildSkillRows()
  UpdateSkillRows()

  U.StripStockTextures(G("SkillDetailScrollFrame"))
  SetTextFont(G("SkillDetailCostText"), M.fontSize.small, WHITE)
  SetTextFont(G("SkillDetailDescriptionText"), M.fontSize.small, WHITE)

  local status = G("SkillDetailStatusBar")
  if status then StyleSkillBar(status) end
  StyleUnlearnButton(G("SkillDetailStatusBarUnlearnButton"))

  U.PostHookGlobal("SkillFrame_Update", UpdateSkillRows)
end

-- The unlearn button carries its entire meaning in its NormalTexture (the red
-- "pass" X); it has no label. U.StyleStockButton clears every button face, so
-- the button rendered as an empty accent-outlined square in game
-- (USER_CONFIRMED_INGAME, screenshot). The native face cannot simply be kept:
-- the clear pass also runs SetNormalTexture(button, "") on this client, which
-- blanks the same texture object.
--
-- So the glyph is re-added as an unrealUI-owned ARTWORK texture and passed
-- through `keep` so the strip pass leaves it alone. WORKING_SOURCE
-- (UnrealPfUI skins/blizzard/character.lua:324): that skin sets exactly this
-- path on this button on this client, so it is the right art rather than a
-- guessed path -- this is a working implementation, not runtime verification.
--
-- No icon-atlas texcoord crop here: knowledge.json /
-- ui.microbutton_reskin_regresses_visually records that the 0.08-0.92 inset
-- assumes icon-atlas art and visibly cuts plain UI button textures like this
-- one. The glyph is inset with padding instead, which is why it does not go
-- through U.StyleStockButton's `icon` option.
local UNLEARN_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function SetIconAlpha(icon, alpha)
  if icon then pcall(icon.SetAlpha, icon, alpha) end
end

StyleUnlearnButton = function(button)
  if not button then return end

  if not button.uuiUnlearnIcon and button.CreateTexture then
    local ok, icon = pcall(button.CreateTexture, button, nil, "ARTWORK")
    if ok and icon then
      pcall(icon.SetTexture, icon, UNLEARN_ICON)
      pcall(function()
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
      end)
      button.uuiUnlearnIcon = icon
    end
  end

  local options
  if button.uuiUnlearnIcon then
    options = { keep = { [button.uuiUnlearnIcon] = true } }
  end
  U.StyleStockButton(button, options)

  -- RUNTIME_FAILURE_CONFIRMED (UnrealRuntimeProbe skillunlearn.icon_field.v1 /
  -- skillunlearn.icon_region_membership.v1): a texture from CreateTexture on
  -- this button defaulted to IsShown() == false even though its texture path,
  -- size, alpha and anchors were all set correctly -- and it is not enumerated
  -- by button:GetRegions() at all here, so the `keep` table above never had
  -- anything to protect it from. This client requires an explicit Show().
  if button.uuiUnlearnIcon then pcall(button.uuiUnlearnIcon.Show, button.uuiUnlearnIcon) end

  -- U.StyleStockButton only owns hover; the glyph carries the pressed state so
  -- a destructive click still gives feedback without stock pushed art.
  local icon = button.uuiUnlearnIcon
  if icon and not button.uuiUnlearnStates then
    button.uuiUnlearnStates = true
    U.PostHookScript(button, "OnEnter", function() SetIconAlpha(icon, 1) end)
    U.PostHookScript(button, "OnLeave", function() SetIconAlpha(icon, 0.85) end)
    U.PostHookScript(button, "OnMouseDown", function() SetIconAlpha(icon, 0.6) end)
    U.PostHookScript(button, "OnMouseUp", function() SetIconAlpha(icon, 0.85) end)
    SetIconAlpha(icon, 0.85)
  end
end

local function StyleHonorTab()
  local honor = G("HonorFrame")
  if not honor then return end
  U.StripStockTextures(honor)

  local bar = G("HonorFrameProgressBar")
  if bar then
    StyleBar(bar)
    SetTextFont(bar, M.fontSize.small, WHITE)
  end
end

-- ---------------------------------------------------------------------------
-- Pet tab
--
-- Modern skin only; BuildFrame is the only caller and it does not run under
-- the native-chrome themes.
--
-- Frame names here have no compact-evidence record at all (query_compat.py:
-- no match for PetPaperDoll or PetAttribute). Every name below except
-- PetLevelText is one UnrealPfUI's own character skin drives on this same
-- client, which .claude/rules/unreal-pfui.md makes the correct fallback in an
-- evidence gap -- WORKING_SOURCE, not runtime verification. Each read is
-- G()+pcall guarded, so a name this client does not carry leaves that piece
-- untouched rather than breaking the tab.
--
-- The stat text is deliberately not name-guessed. The child names inside
-- PetAttributesFrame are the part pfUI never touches, so instead of inventing
-- them the shared recursive pass (U.ForceStockTextWhite, already the way
-- gossip/mail/quest/trainer recolour stock body text) is applied to the
-- container. That gives every stat line the addon font at a consistent size
-- whatever the client calls it; the named lines below then re-apply the
-- label/value hierarchy on top of it where the names hold.
-- ---------------------------------------------------------------------------
local function StylePetTab()
  local pet = G("PetPaperDollFrame")
  if not pet then return end

  U.StripStockTextures(pet)

  -- Title block, matching the Character page: the pet's name is this page's
  -- primary heading and sits in the same place the player's does.
  local name = G("PetNameText")
  if name and panel then
    pcall(function()
      name:ClearAllPoints()
      name:SetPoint("TOP", panel, "TOP", 0, -10)
    end)
  end
  SetTextFont(name, M.fontSize.large, GOLD)
  SetTextFont(G("PetLevelText"), M.fontSize.small, GOLD)

  -- The page carries its own close button on top of the window's. One close
  -- control per window; the duplicate is stock chrome.
  local close = G("PetPaperDollCloseButton")
  if close then pcall(close.Hide, close) end

  -- Unlike the Character page these keep working rather than being replaced by
  -- a click-rotate catcher: that catcher is a single confirmed instance bound
  -- to CharacterModelFrame, and duplicating it here would mean rebuilding a
  -- USER_CONFIRMED_INGAME drag path against an unprobed second model frame.
  -- Flat arrows with owned glyphs satisfy the native-texture policy and leave
  -- the rotation intact.
  U.StyleStockArrowButton(G("PetModelFrameRotateLeftButton"), "left", 16)
  U.StyleStockArrowButton(G("PetModelFrameRotateRightButton"), "right", 16)

  local attributes = G("PetAttributesFrame")
  if attributes then
    U.StripStockTextures(attributes)
    U.ForceStockTextWhite(attributes, WHITE, M.fontSize.small)
  end

  SetTextFont(G("PetArmorFrameLabel"), M.fontSize.small, DIM)
  SetTextFont(G("PetArmorFrameText"), M.fontSize.small, WHITE)
  SetTextFont(G("PetTrainingPointLabel"), M.fontSize.small, DIM)
  SetTextFont(G("PetTrainingPointText"), M.fontSize.small, WHITE)

  -- Happiness/loyalty/diet. Stripped of its frame art; the icon itself is
  -- meaningful content imagery and is left alone.
  local info = G("PetPaperDollPetInfo")
  if info then U.StripStockTextures(info) end

  -- The player's XP bar colour, from the shared token, so the pet's experience
  -- reads as the same bar as the one under the unit frames. The earlier pass
  -- stripped this bar and then set its texture, which is exactly the empty-bar
  -- failure U.StyleStockStatusBar exists to prevent -- hence the shared call
  -- and the fail-closed branch rather than a local strip here.
  local bar = G("PetPaperDollFrameExpBar")
  if bar then
    local styled = U.StyleStockStatusBar(bar, { color = M.color.xp })
    if not styled then
      U.Debug("character: pet exp bar fill not found, left native")
    end
    SetTextFont(bar, M.fontSize.small, WHITE)

    -- Hovering the bar blanked it. The client runs its own art pass on this
    -- bar's hover -- the equipment slots and reputation rows have no such
    -- pass, which is why neither needed this -- and it lands after the skin,
    -- so the skin is re-asserted after it. U.StyleStockStatusBar re-identifies
    -- the live fill on every call, so this recovers the bar whether the hover
    -- re-pointed the fill or restored native art over it.
    --
    -- Which of those it actually is has not been probed; the two debug lines
    -- below separate them if it ever needs to be. Hooked once per bar, and
    -- only on the two hover scripts, so the region walk stays off every other
    -- path.
    if not bar.uuiPetExpHovered then
      bar.uuiPetExpHovered = true
      local Reassert = function()
        if not U.StyleStockStatusBar(bar, { color = M.color.xp }) then
          U.Debug("character: pet exp bar fill unidentifiable after hover")
        end
        if bar.IsShown then
          local ok, shown = pcall(bar.IsShown, bar)
          if ok and not shown then
            U.Debug("character: pet exp bar was hidden by the client on hover")
          end
        end
      end
      U.PostHookScript(bar, "OnEnter", Reassert)
      U.PostHookScript(bar, "OnLeave", Reassert)
    end
  end

  local resistances = G("PetResistanceFrame")
  if resistances then U.StripStockTextures(resistances) end

  -- The same five schools in the same order as the player's, so the shared
  -- StyleResistance -- flat square, cropped glyph, owned outline -- applies
  -- unchanged, including the native texcoords it restates.
  local i
  for i = 1, 5 do
    local res = G("PetMagicResFrame" .. i)
    if res then StyleResistance(res, i) end
    SetTextFont(G("PetMagicResText" .. i), M.fontSize.small, WHITE)
  end
end

local function Reapply()
  U.StripStockTextures(frame)
  if panel then panel:Show() end

  -- The Pet tab is shown/hidden by the client as the player gains or loses a
  -- pet, so the run has to be re-measured every time the sheet opens.
  LayoutTabs()

  SetTextFont(G("CharacterNameText"), M.fontSize.large, GOLD)
  SetTextFont(G("CharacterLevelText"), M.fontSize.small, GOLD)

  StyleSlots()
  StyleResistances()
  StyleAttributes()
end

local function CharacterDragControls()
  local controls = {}
  local close = G("CharacterFrameCloseButton")
  if close then table.insert(controls, close) end

  local i
  for i = 1, table.getn(SLOTS) do
    local slot = G("Character" .. SLOTS[i])
    if slot then table.insert(controls, slot) end
  end
  for i = 1, TAB_COUNT do
    local tab = G("CharacterFrameTab" .. i)
    if tab then table.insert(controls, tab) end
  end
  return controls
end

local function BuildFrame()
  frame = G("CharacterFrame")
  if not frame then
    U.Debug("character: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  panel = U.CreatePanel(frame, {
    name = "UnrealUICharacterPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_INSET_LEFT, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANEL_INSET_RIGHT, 72)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 10, 30, 10, 72)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  local name = G("CharacterNameText")
  if name then
    pcall(function()
      name:ClearAllPoints()
      name:SetPoint("TOP", panel, "TOP", 0, -10)
    end)
  end

  local close = G("CharacterFrameCloseButton")
  U.StyleStockCloseButton(close, panel, -6, -6)
  -- The close button is anchored to panel, whose right edge is 30px inside
  -- CharacterFrame. Reserve its full horizontal bounds so the raised header
  -- drag handle cannot steal hover/clicks from the button's upper section.
  U.MakeWindowDraggable("character", frame, {
    headerHeight = 76,
    headerInset = 54,
    -- Character's mouse-enabled model catcher sits above the base frame, so
    -- this window needs the proven high drag level rather than the shared +1.
    headerLevelOffset = 100,
    interactiveFrames = CharacterDragControls(),
  })
  StyleTabs()
  StyleModel()

  U.StripStockTextures(G("PaperDollFrame"))
  U.StripStockTextures(G("CharacterAttributesFrame"))
  U.StripStockTextures(G("CharacterResistanceFrame"))

  StyleSlots()
  StyleResistances()
  StyleAttributes()
  SetTextFont(G("CharacterLevelText"), M.fontSize.small, GOLD)

  StyleReputationTab()
  StyleSkillsTab()
  StyleHonorTab()
  StylePetTab()

  -- The client redraws the pet page's own art when the tab is opened, so the
  -- skin is re-asserted there rather than only at build. Every call in the
  -- pass is idempotent.
  U.PostHookScript(G("PetPaperDollFrame"), "OnShow", StylePetTab)

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  -- PaperDollItemSlotButton_Update redraws a slot whenever an item is
  -- equipped/unequipped while the sheet is open; re-running StyleSlots keeps
  -- unrealUI's border/icon framing in sync with it. StyleStockButton no-ops
  -- past its first pass per button, so this is safe to call repeatedly.
  -- The client calls PaperDollItemSlotButton_Update once per slot button, and
  -- its gear and bag slots all react to bag/lock events: one item moved between
  -- bags ran this full every-slot pass hundreds of times inside one frame,
  -- window open or not (measured 2026-09-16 with UnrealRuntimeProbe bagmove ab:
  -- 180-260ms frames that survived switching unrealUI bags and bars off).
  -- Closed window: nothing to draw, OnShow restyles it. Open: one deferred pass.
  U.PostHookGlobal("PaperDollItemSlotButton_Update", function()
    local ok, shown = pcall(frame.IsShown, frame)
    if not (ok and shown) then return end
    U.DeferOnce("character.slots", StyleSlots)
  end)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

function CH:OnEnable()
  modernWowTabMode = type(U.ModernWowSurfaceEnabled) == "function" and
                     U.ModernWowSurfaceEnabled("character")

  -- The native theme keeps CharacterFrame's own chrome. windowmove.lua still
  -- supplies its mover. Only the semantic rarity outlines are layered above
  -- the stock item slots.
  if U.ThemeStyleUsesNativeChrome() and not modernWowTabMode then
    if BuildClassicSlotBorders() then
      U.MakeWindowDraggable("character", frame, {
        headerInset = 40,
        headerLevelOffset = 100,
        interactiveFrames = CharacterDragControls(),
      })
    end
    return
  end
  if not BuildFrame() then return end
  InstallModernWowCharacterToggle()

  -- modern-wow's art follows the live tab geometry, so its watcher runs on
  -- every rendered frame and repairs the client's delayed native selection
  -- pass before it can be drawn. Other themes keep the existing low-rate
  -- watcher; this theme-specific race must not alter their drawing path.
  local tabFitInterval = modernWowTabMode and 0 or 0.2
  U.RegisterUpdate("character.tab-fit", tabFitInterval, function()
    if not frame or not frame.IsShown then return end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or not shown then return end
    SyncTabSelection()
    if TabFitDrifted() then LayoutTabs() end
  end)

  -- The client shows and hides the Pet tab with the pet itself. Re-laying the
  -- run out here keeps the fit correct when that happens while the sheet is
  -- already open; the OnShow pass covers every other case.
  U.RegisterEvent("UNIT_PET", function()
    if not frame or not frame.IsShown then return end
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then LayoutTabs() end
  end)
end
