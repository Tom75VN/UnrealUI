-- unrealUI :: modules/talents.lua
--
-- Modern treatment of the native talent window. The client continues to own
-- talent data, icons, ranks, tooltips, prerequisites and click handling;
-- unrealUI only replaces the window and control chrome.

local U = UnrealUI
local M = U.media
local TL = U.RegisterModule("talents")

local frame, frameName, panel
local built = false

local function G(name)
  return U.G(name)
end

-- UnrealPfUI's same-client skin supports both names: TalentFrame is the
-- Vanilla-shaped window and PlayerTalentFrame is the TBC-shaped equivalent.
-- This is WORKING_SOURCE evidence, not a runtime measurement, so every access
-- below stays optional and nil-safe.
local function ResolveFrame()
  local candidate = G("PlayerTalentFrame") or G("TalentFrame")
  if not candidate then return nil end

  local ok, name = pcall(candidate.GetName, candidate)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  frameName = name
  return candidate
end

local function Named(suffix)
  if not frameName then return nil end
  return G(frameName .. suffix)
end

local function TalentCount()
  local count = tonumber(G("MAX_NUM_TALENTS")) or 20
  if count < 1 then count = 20 end
  if count > 80 then count = 80 end
  return count
end

local function StyleText(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or M.color.text)
end

local function StyleTalent(index)
  local button = Named("Talent" .. index)
  if not button then return end

  local icon = Named("Talent" .. index .. "IconTexture")
  U.StyleStockButton(button, { icon = icon })
  -- Native talent refreshes can repaint button faces after the first skinning
  -- pass. Keep the real ability icon, but remove those faces again.
  U.RefreshStockButtonArtwork(button, icon)
  -- Rank colour is native talent state (available, learned, maxed), not addon
  -- chrome. Normalize the font while preserving that semantic colour.
  U.SetStockFont(Named("Talent" .. index .. "Rank"), M.fontSize.small)
end

local function StyleTalents()
  local i
  for i = 1, TalentCount() do StyleTalent(i) end
end

local function StyleHeader()
  local title = Named("TitleText")
  if title and panel then
    pcall(function()
      title:ClearAllPoints()
      title:SetPoint("TOP", panel, "TOP", 0, -10)
    end)
  end
  StyleText(title, M.fontSize.large, M.color.accent)

  local spent = Named("SpentPoints")
  if spent and panel then
    pcall(function()
      spent:ClearAllPoints()
      spent:SetPoint("TOP", panel, "TOP", 0, -47)
    end)
  end
  StyleText(spent, M.fontSize.small, M.color.textDim)

  local available = Named("TalentPointsText")
  if available and panel then
    pcall(function()
      available:ClearAllPoints()
      available:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    end)
  end
  StyleText(available, M.fontSize.normal, M.color.accent)
end

local function CollectTabs()
  local tabs = {}
  local i
  for i = 1, 5 do
    local tab = Named("Tab" .. i)
    if tab then table.insert(tabs, tab) end
  end
  return tabs
end

local function CollectDragControls()
  local controls = {}
  local close = Named("CloseButton")
  if close then table.insert(controls, close) end
  return controls
end

local function Reapply()
  if not frame then return end
  U.StripStockTextures(frame)
  U.StripStockTextures(Named("ScrollFrame"))
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")
  local cancel = Named("CancelButton")
  if cancel then pcall(cancel.Hide, cancel) end
  if panel then pcall(panel.Show, panel) end
  StyleHeader()
  StyleTalents()
end

local function InstallRefreshHooks(tabs)
  local i
  for i = 1, TalentCount() do
    local talent = Named("Talent" .. i)
    if talent then
      U.PostHookScript(talent, "OnClick", function()
        U.DeferOnce("talents.reapply", Reapply)
      end)
    end
  end

  for i = 1, table.getn(tabs) do
    U.PostHookScript(tabs[i], "OnClick", function()
      U.DeferOnce("talents.reapply", Reapply)
    end)
  end
end

local function BuildFrame()
  if built then return true end
  frame = ResolveFrame()
  if not frame then
    U.Debug("talents: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)
  pcall(frame.DisableDrawLayer, frame, "BACKGROUND")

  panel = U.CreatePanel(frame, {
    name = "UnrealUITalentPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 72)
  pcall(panel.EnableMouse, panel, false)
  pcall(frame.SetHitRectInsets, frame, 10, 32, 10, 72)

  local levelOk, level = pcall(frame.GetFrameLevel, frame)
  if levelOk and tonumber(level) then pcall(panel.SetFrameLevel, panel, level) end

  local cancel = Named("CancelButton")
  if cancel then pcall(cancel.Hide, cancel) end

  U.StyleStockCloseButton(Named("CloseButton"), panel, -6, -6)
  U.StripStockTextures(Named("ScrollFrame"))
  U.StyleStockScrollbar(Named("ScrollFrameScrollBar"))

  local tabs = CollectTabs()
  if tabs[1] then
    pcall(function()
      tabs[1]:ClearAllPoints()
      tabs[1]:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, 0)
    end)
  end
  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)

  U.MakeWindowDraggable("talents", frame, {
    headerHeight = 76,
    headerInset = 56,
    interactiveFrames = CollectDragControls(),
  })

  StyleHeader()
  StyleTalents()
  InstallRefreshHooks(tabs)

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then pcall(panel.Hide, panel) end
  end)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else pcall(panel.Hide, panel) end
  built = true
  return true
end

-- TalentFrame may be created by Blizzard_TalentUI after unrealUI's own module
-- phase. ADDON_LOADED is the safe lazy-load fallback used by the other stock
-- windows in this addon.
local function TryBuild()
  if BuildFrame() then U.UnregisterEvent("ADDON_LOADED", TryBuild) end
end

function TL:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then return end
  if BuildFrame() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
end
