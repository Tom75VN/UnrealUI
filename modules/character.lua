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

local frame, panel

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
      color = U.ItemQualityColor(quality) or M.slotBorder.plain
    else
      color = M.slotBorder.plain
    end
  end

  border[1], border[2], border[3], border[4] = M.Unpack(color)

  if keepNativeChrome then
    -- Classic keeps the client's paper-doll artwork and button states intact.
    -- Add only UnrealUI's semantic outline above that native slot so equipped
    -- item rarity remains visible without turning the character sheet Modern.
    U.CreateBorder(slot)
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

local function BuildClassicSlotBorders()
  frame = G("CharacterFrame")
  if not frame then
    U.Debug("character: native frame unavailable")
    return false
  end

  local function RefreshClassicSlotBorders()
    StyleSlots(true)
  end

  RefreshClassicSlotBorders()
  U.PostHookScript(frame, "OnShow", RefreshClassicSlotBorders)
  U.PostHookGlobal("PaperDollItemSlotButton_Update",
                   RefreshClassicSlotBorders)
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
local function RaiseResistancesAboveModel()
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

-- Click-drag model rotation, replacing the native rotate-left/right buttons
-- (hidden below) with a direct drag on the preview itself.
--
-- WORKING_SOURCE, not runtime-verified on this client: UnrealPfUI's
-- api/ui-widgets.lua EnableClickRotate rotates the same CharacterModelFrame
-- type via frame:SetRotation(radians) on several stock model frames
-- (character, dressup, inspect, stable, tabard, auction), but query_compat.py
-- has no record for SetRotation and it has not been probed on Unreal
-- specifically. Confirm the model actually turns in game.
--
-- Unlike pfUI's version (raw OnMouseDown/OnUpdate on the model frame itself,
-- reading the undocumented `this`), this follows unrealUI's own verified
-- drag recipe: a Button overlay (frames.movable_drag_requires_button_handle)
-- driven by the shared update ticker rather than a child OnUpdate
-- (scripts.child_onupdate_unreliable), matching U.CreateSlider's thumb.
--
-- USER_CONFIRMED_INGAME: an earlier version registered the drag with
-- RegisterForDrag/OnDragStart/OnDragStop alone (no SetMovable/StartMoving)
-- and the model kept spinning after the mouse button was released -- rotation
-- never stopped. core/mover.lua's StartDrag is the only recipe in this addon
-- confirmed to receive a matching OnDragStop on this client, and it always
-- pairs RegisterForDrag with SetMovable(true) immediately before each drag
-- plus a throwaway StartMoving/StopMovingOrSizing pair before the real
-- StartMoving. Reusing that exact pairing here is what makes OnDragStop (and
-- so the ticker teardown) actually fire; the catcher itself moving off the
-- model during the drag doesn't matter since it is invisible and gets
-- re-anchored in OnDragStop, and mouse delivery follows the button that
-- started the drag rather than its current position.
local ROTATE_RADIANS_PER_PIXEL = 0.01
local modelRotation = 0
local modelCatcher
-- Declared ahead of LiveModelDrag/StyleModel, both of which close over it:
-- a later `local` of the same name would not be visible as an upvalue inside
-- a function textually defined before it (Lua locals only scope forward).
local DRAG_TICKER = "character.model-rotate"

-- Safety net alongside OnDragStop, not a replacement for it: if the button
-- reads as released, stop the ticker even if OnDragStop was somehow never
-- delivered. IsMouseButtonDown has no compact-DB record either way, so this
-- is a no-op (ticker just keeps relying on OnDragStop alone) on a client
-- where the call fails or the pcall it lives inside is not trusted.
local function LeftButtonStillDown()
  local ok, down = pcall(IsMouseButtonDown, "LeftButton")
  if not ok then return true end
  return down and true or false
end

local function LiveModelDrag()
  if not modelCatcher then return end
  if not LeftButtonStillDown() then
    U.UnregisterUpdate(DRAG_TICKER)
    modelCatcher.uuiLastX = nil
    return
  end

  local model = G("CharacterModelFrame")
  if not model then return end

  local ok, x = pcall(GetCursorPosition)
  if not ok or not tonumber(x) then return end

  local scale = 1
  local scaleOk, value = pcall(model.GetEffectiveScale, model)
  if scaleOk and tonumber(value) and value > 0 then scale = value end
  x = x / scale

  local last = modelCatcher.uuiLastX
  if last then
    modelRotation = modelRotation + (x - last) * ROTATE_RADIANS_PER_PIXEL
    pcall(model.SetRotation, model, modelRotation)
  end
  modelCatcher.uuiLastX = x
end

local function StyleModel()
  local model = G("CharacterModelFrame")
  local left = G("CharacterModelFrameRotateLeftButton")
  local right = G("CharacterModelFrameRotateRightButton")
  if left then pcall(left.Hide, left) end
  if right then pcall(right.Hide, right) end

  if not model or modelCatcher then return end

  local created, catcher = pcall(CreateFrame, "Button",
    "UnrealUICharacterModelRotateCatcher", model)
  if not created or not catcher then return end
  modelCatcher = catcher

  pcall(catcher.SetAllPoints, catcher, model)
  pcall(catcher.EnableMouse, catcher, true)
  pcall(catcher.RegisterForDrag, catcher, "LeftButton")

  catcher:SetScript("OnDragStart", function()
    if not pcall(catcher.SetMovable, catcher, true) then return end
    if pcall(catcher.StartMoving, catcher) then
      pcall(catcher.StopMovingOrSizing, catcher)
    end
    if not pcall(catcher.StartMoving, catcher) then return end

    modelCatcher.uuiLastX = nil
    U.RegisterUpdate(DRAG_TICKER, 0, LiveModelDrag)
  end)
  catcher:SetScript("OnDragStop", function()
    U.UnregisterUpdate(DRAG_TICKER)
    pcall(catcher.StopMovingOrSizing, catcher)
    modelCatcher.uuiLastX = nil

    -- StartMoving let the catcher drift with the cursor; put it back over the
    -- model so the next click-drag has full coverage again.
    pcall(function()
      catcher:ClearAllPoints()
      catcher:SetAllPoints(model)
    end)
  end)
end

-- Flat, actively-tracked tab bar (see U.StyleStockTabGroup). Positioning is
-- kept separate from styling: a hidden tab (the Pet slot with no pet out)
-- still occupies its index but must not be chained into, or the tabs after
-- it would inherit a gap sized to an invisible button -- WORKING_SOURCE from
-- UnrealPfUI's own character skin, which guards the same chain on
-- lastTab:IsShown().
local function StyleTabs()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("CharacterFrameTab" .. i)
  end

  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)
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
    end
  end
end

UpdateSkillRows = function()
  local getCount = G("GetNumSkillLines")
  local getInfo = G("GetSkillLineInfo")
  if type(getCount) ~= "function" or type(getInfo) ~= "function" then return end

  local ok, numEntries = pcall(getCount)
  if not ok or not tonumber(numEntries) then return end

  local offset = 0
  local offsetFn = G("FauxScrollFrame_GetOffset")
  local scroll = G("SkillListScrollFrame")
  if type(offsetFn) == "function" and scroll then
    local offsetOk, value = pcall(offsetFn, scroll)
    if offsetOk and tonumber(value) then offset = value end
  end

  local i, headers, collapsedHeaders = nil, 0, 0
  for i = 1, SKILL_ROWS do
    local header = G("SkillTypeLabel" .. i)
    local bar = G("SkillRankFrame" .. i)
    local index = i + offset

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
end

local function StyleSkillsTab()
  local skill = G("SkillFrame")
  if not skill then return end
  U.StripStockTextures(skill)

  -- The pill-shaped background behind "All" belongs to this companion frame,
  -- not to SkillFrameCollapseAllButton itself (WORKING_SOURCE, UnrealPfUI
  -- skins/blizzard/character.lua) -- StripStockTextures on the button alone
  -- left it in place.
  local expandBackground = G("SkillFrameExpandButtonFrame")
  if expandBackground then
    pcall(expandBackground.DisableDrawLayer, expandBackground, "BACKGROUND")
  end

  local cancel = G("SkillFrameCancelButton")
  if cancel then pcall(cancel.Hide, cancel) end

  local collapseAll = G("SkillFrameCollapseAllButton")
  if collapseAll then
    U.StripStockTextures(collapseAll)
    U.StyleStockCollapseButton(collapseAll, true)
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
      collapseAll:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -6, 4)
    end)
  end

  BuildSkillRows()
  UpdateSkillRows()

  U.StripStockTextures(G("SkillListScrollFrame"))
  U.StyleStockScrollbar(G("SkillListScrollFrameScrollBar"))

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

local function Reapply()
  U.StripStockTextures(frame)
  if panel then panel:Show() end

  SetTextFont(G("CharacterNameText"), M.fontSize.large, GOLD)
  SetTextFont(G("CharacterLevelText"), M.fontSize.small, GOLD)

  StyleSlots()
  StyleResistances()
  StyleAttributes()
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
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 72)
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

  U.StyleStockCloseButton(G("CharacterFrameCloseButton"), panel, -6, -6)
  -- The close button is anchored to panel, whose right edge is 30px inside
  -- CharacterFrame. Reserve its full horizontal bounds so the raised header
  -- drag handle cannot steal hover/clicks from the button's upper section.
  U.MakeWindowDraggable("character", frame, { headerInset = 54 })
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

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  -- PaperDollItemSlotButton_Update redraws a slot whenever an item is
  -- equipped/unequipped while the sheet is open; re-running StyleSlots keeps
  -- unrealUI's border/icon framing in sync with it. StyleStockButton no-ops
  -- past its first pass per button, so this is safe to call repeatedly.
  U.PostHookGlobal("PaperDollItemSlotButton_Update", StyleSlots)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

function CH:OnEnable()
  -- The native theme keeps CharacterFrame's own chrome. windowmove.lua still
  -- supplies its mover. Only the semantic rarity outlines are layered above
  -- the stock item slots.
  if U.ThemeStyleUsesNativeChrome() then
    BuildClassicSlotBorders()
    return
  end
  BuildFrame()
end
