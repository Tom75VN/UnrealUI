-- unrealUI :: modules/gossip.lua
--
-- pfUI-modern-inspired treatment of the native NPC dialog window (GossipFrame)
-- -- what opens when talking to a trainer, quartermaster, or any NPC offering
-- gossip options. Native gossip data, option list, and click behaviour stay
-- intact; unrealUI changes only artwork, typography and layout, matching the
-- Character/Quest Log/Trainer treatment.
--
-- WORKING_SOURCE, not runtime-verified on this client: query_compat.py has no
-- record at all for GossipFrame or any of its children (documentation.json
-- only covers the Gossip Lua API, not the frame's widget hierarchy), so every
-- region name below is taken from UnrealPfUI's skins\blizzard\gossipquest.lua
-- as a same-client working implementation rather than confirmed evidence.
-- Verify in game and fold any surprises into knowledge.json.
--
-- Unlike UnrealPfUI (which hides the NPC portrait entirely), the portrait is
-- kept and cropped like modules/merchant.lua's header -- rules/unreal-ui-
-- design.md classifies portraits as meaningful content imagery to preserve,
-- not decorative chrome to strip.

local U = UnrealUI
local M = U.media
local GS = U.RegisterModule("gossip")

-- Requested: every string in the NPC dialog reads as plain white, including
-- the NPC name -- no accent heading colour here. Same request already recorded
-- in modules/trainer.lua's ReapplyHeaderText, and the same pure-white value
-- modules/questlog.lua uses (QUEST_WHITE), deliberately not M.color.text: that
-- token is 0.90 grey and reads dim against this window's dark panel.
local WHITE = { 1.00, 1.00, 1.00, 1 }

local frame, panel

local function G(name)
  return U.G(name)
end

local function SetGossipFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function Reposition(object, point, relativeTo, relativePoint, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, relativeTo, relativePoint, x, y)
  end)
end

-- Gossip option rows (GossipTitleButton1..N) are plain clickable text/icon
-- rows, not stock chrome buttons -- same shape as modules/trainer.lua's skill
-- rows. The per-option icon (GossipTitleButtonNGossipIcon) is a meaningful
-- content glyph (chat bubble / quest marker), so it is kept explicitly rather
-- than stripped with the rest of the row's native art.
local function StyleTitleRow(i)
  local button = G("GossipTitleButton" .. i)
  if not button then return end

  local icon = G("GossipTitleButton" .. i .. "GossipIcon")
  U.StripStockTextures(button, icon and { icon = icon } or nil)

  local function ForceRowWhite()
    -- Button:SetTextColor controls the normal label state; applying the shared
    -- stock-font adapter to the FontString afterward also wins over the native
    -- black highlight font that is selected during OnEnter.
    if button.SetTextColor then
      pcall(button.SetTextColor, button, 1, 1, 1)
    end

    if button.GetFontString then
      local fontOk, fontstring = pcall(button.GetFontString, button)
      if fontOk and fontstring then
        SetGossipFont(fontstring, M.fontSize.normal, WHITE)
      end
    end
  end

  ForceRowWhite()

  -- USER_CONFIRMED_INGAME: the trainer/gossip option becomes black when its
  -- native yellow highlight appears. Run after the native enter/leave scripts
  -- so both states are restored to white without replacing click behavior.
  if not button.uuiWhiteTextHooks then
    button.uuiWhiteTextHooks = true
    U.PostHookScript(button, "OnEnter", ForceRowWhite)
    U.PostHookScript(button, "OnLeave", ForceRowWhite)
  end
end

-- No compact-DB record for how many GossipTitleButton rows FrameXML ever
-- instantiates. Same convention as modules/trainer.lua's CLASS_TRAINER_
-- SKILLS_DISPLAYED fallback: try the documented constant, fall back to a
-- safe upper bound, and let the per-row G() guard no-op past the real count.
local function StyleTitleRows()
  local rows = tonumber(G("NUMGOSSIPBUTTONS")) or 10
  local i
  for i = 1, rows do
    StyleTitleRow(i)
  end
end

local function StyleHeader()
  local portrait = G("GossipFramePortrait")
  if portrait then
    pcall(portrait.SetTexCoord, portrait, 0.08, 0.92, 0.08, 0.92)
  end
end

-- Body text recolouring lives in core/stockui.lua (U.ForceStockTextWhite);
-- modules/quest.lua needs the identical pass for the sibling NPC dialog, so
-- the walker is shared rather than duplicated per module.
local function ForceWhiteText(object)
  U.ForceStockTextWhite(object, WHITE, M.fontSize.normal)
end

-- Use the same explicit stock-string treatment as questlog.lua in addition to
-- the frame walk. GossipGreetingText is the WORKING_SOURCE native greeting
-- string; G() safely skips it if this client does not expose that peer.
local function ApplyNamedWhiteText()
  SetGossipFont(G("GossipGreetingText"), M.fontSize.normal, WHITE)
end

-- WORKING_SOURCE (knowledge.json frames.stock_singletons_structure_nonvanilla):
-- questlog.lua/spellbook.lua confirm stock singleton windows can recreate
-- their decorative regions on native content refresh, not just on first
-- OnShow, so every stripped region here must be reapplied on each refresh
-- rather than stripped once in BuildFrame. Reapply is now the single place
-- that re-strips the greeting panel/scroll chrome too.
local function Reapply()
  U.StripStockTextures(frame)
  U.StripStockTextures(G("GossipFrameGreetingPanel"))
  U.StripStockTextures(G("GossipGreetingScrollFrame"))
  StyleHeader()
  ForceWhiteText(frame)
  ApplyNamedWhiteText()
  SetGossipFont(G("GossipFrameNpcNameText"), M.fontSize.large, WHITE)
  StyleTitleRows()
end

local function BuildFrame()
  frame = G("GossipFrame")
  if not frame then
    U.Debug("gossip: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  -- Content backdrop inset from the real frame bounds, same shape as
  -- modules/trainer.lua's panel: leaves the bottom strip clear for the
  -- Goodbye button instead of burying it inside the dark box.
  panel = U.CreatePanel(frame, {
    name = "UnrealUIGossipPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 8, 30, 10, 40)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  U.MakeWindowDraggable("gossip", frame, { headerInset = 54 })

  StyleHeader()
  Reposition(G("GossipFrameNpcNameText"), "TOP", panel, "TOP", 0, -10)

  U.StyleStockCloseButton(G("GossipFrameCloseButton"), panel, -6, -6)

  U.StripStockTextures(G("GossipGreetingScrollFrame"))
  U.StyleStockScrollbar(G("GossipGreetingScrollFrameScrollBar"))
  U.StripStockTextures(G("GossipFrameGreetingPanel"))

  ForceWhiteText(frame)
  ApplyNamedWhiteText()
  SetGossipFont(G("GossipFrameNpcNameText"), M.fontSize.large, WHITE)
  StyleTitleRows()

  U.StyleStockButton(G("GossipFrameGreetingGoodbyeButton"))

  -- No compact-DB record of a documented "gossip list changed" hook (no
  -- UpdateGossipFrame/GossipFrame_Update entry either). Reapply drives off
  -- OnShow only, same fallback modules/merchant.lua uses when no native
  -- refresh hook is confirmed; if in-game testing shows the option list can
  -- change while the window stays open (e.g. a quest turned in mid-gossip),
  -- fold the real update hook into knowledge.json and hook it here.
  U.PostHookScript(frame, "OnShow", Reapply)

  if frame.IsShown then
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then Reapply() end
  end
  return true
end

-- USER_CONFIRMED_INGAME (modules/trainer.lua): stock dialog frames like this
-- are not reliably resolvable from OnEnable on this client. Same retry shape:
-- ADDON_LOADED as the lazy-load fallback, GOSSIP_SHOW (documented open-gossip
-- event) as the real trigger, both torn down once BuildFrame succeeds once.
local pendingEvents = { "ADDON_LOADED", "GOSSIP_SHOW" }

local function TryBuild()
  if BuildFrame() then
    local i
    for i = 1, table.getn(pendingEvents) do
      U.UnregisterEvent(pendingEvents[i], TryBuild)
    end
    -- GOSSIP_SHOW is the documented content-refresh event (options/quests can
    -- change per NPC without the frame re-firing OnShow); keep it registered
    -- after the build so every refresh reapplies the strip, same shape as
    -- questlog.lua's UpdateRows-driven ReapplyNativeStrip.
    U.RegisterEvent("GOSSIP_SHOW", Reapply)
    return true
  end
  return false
end

function GS:OnEnable()
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("GOSSIP_SHOW", TryBuild)
end
