-- unrealUI :: modules/spellbook.lua
--
-- Dark native Spellbook skin matching the Quest Log treatment. Spell buttons,
-- paging, skill-line tabs, drag/click behavior and the native update function
-- remain in charge; only their presentation is changed.

local U = UnrealUI
local M = U.media
local SB = U.RegisterModule("spellbook")

local SPELL_GOLD = { 1.00, 0.82, 0.00, 1.00 }
local SPELL_WHITE = { 1.00, 1.00, 1.00, 1.00 }

local frame, panel

local function G(name)
  return U.G(name)
end

local function StripDecorations()
  if frame then U.StripStockTextures(frame) end
end

local function SetSpellFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or SPELL_WHITE)
end

local function SpellCount()
  return tonumber(G("SPELLS_PER_PAGE")) or 12
end

local function SkillTabCount()
  return tonumber(G("MAX_SKILLLINE_TABS")) or 8
end

local function StyleSpellButton(index, refreshOnly)
  local button = G("SpellButton" .. index)
  local icon = G("SpellButton" .. index .. "IconTexture")
  if not button then return end

  if refreshOnly then
    U.RefreshStockButtonArtwork(button, icon)
  else
    U.StyleStockButton(button, { icon = icon })
  end

  SetSpellFont(G("SpellButton" .. index .. "SpellName"),
               M.fontSize.normal, SPELL_GOLD)
  SetSpellFont(G("SpellButton" .. index .. "SubSpellName"),
               M.fontSize.small, SPELL_WHITE)

  local auto = G("SpellButton" .. index .. "AutoCastable")
  if auto then
    pcall(auto.SetTexture, auto, "Interface\\Buttons\\UI-AutoCastableOverlay")
    pcall(auto.SetAlpha, auto, 1)
  end

  local highlight = G("SpellButton" .. index .. "Highlight")
  if highlight and not highlight.uuiSpellHighlightSuppressed then
    U.HideRegion(highlight)
    pcall(function()
      highlight.uuiSpellHighlightSuppressed = true
      highlight.SetTexture = function() return end
    end)
  end
end

local function StyleSkillTabs()
  local first = G("SpellBookSkillLineTab1")
  if first and panel then
    pcall(function()
      first:ClearAllPoints()
      first:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, -30)
    end)
  end

  local previous, i = nil, nil
  for i = 1, SkillTabCount() do
    local button = G("SpellBookSkillLineTab" .. i)
    if button then
      local icon
      if button.GetNormalTexture then
        local ok, texture = pcall(button.GetNormalTexture, button)
        if ok then icon = texture end
      end

      U.StyleStockButton(button, { icon = icon })
      pcall(button.SetScale, button, 1.1)
      if icon then pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93) end

      if previous then
        pcall(function()
          button:ClearAllPoints()
          button:SetPoint("TOP", previous, "BOTTOM", 0, -3)
        end)
      end
      previous = button
    end
  end
end

local function StyleBookTabs()
  local first = G("SpellBookFrameTabButton1")
  if first and panel then
    pcall(function()
      first:ClearAllPoints()
      first:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 1, -3)
    end)
  end

  local previous, i = nil, nil
  for i = 1, 3 do
    local tab = G("SpellBookFrameTabButton" .. i)
    if tab then
      if previous then
        pcall(function()
          tab:ClearAllPoints()
          tab:SetPoint("LEFT", previous, "RIGHT", 3, 0)
        end)
      end
      U.StyleStockTab(tab)
      previous = tab
    end
  end
end

local function Reapply()
  StripDecorations()
  if panel then panel:Show() end

  local i
  for i = 1, SpellCount() do StyleSpellButton(i, true) end
  SetSpellFont(G("SpellBookTitleText"), M.fontSize.large, SPELL_GOLD)
  SetSpellFont(G("SpellBookPageText"), M.fontSize.normal, SPELL_WHITE)
end

local function BuildFrame()
  frame = G("SpellBookFrame")
  if not frame then
    U.Debug("spellbook: native frame unavailable")
    return false
  end

  StripDecorations()

  panel = U.CreatePanel(frame, {
    name = "UnrealUISpellBookPanel",
    width = 450,
    height = 500,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 72)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 12, 30, 12, 72)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  local title = G("SpellBookTitleText")
  if title then
    pcall(function()
      title:ClearAllPoints()
      title:SetPoint("TOP", panel, "TOP", 0, -10)
    end)
  end
  SetSpellFont(title, M.fontSize.large, SPELL_GOLD)

  U.StyleStockCloseButton(G("SpellBookCloseButton"), panel, -6, -6)
  StyleBookTabs()

  local i
  for i = 1, SpellCount() do StyleSpellButton(i, false) end
  StyleSkillTabs()

  U.StyleStockArrowButton(G("SpellBookPrevPageButton"), "left", 18)
  U.StyleStockArrowButton(G("SpellBookNextPageButton"), "right", 18)
  SetSpellFont(G("SpellBookPageText"), M.fontSize.normal, SPELL_WHITE)

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)
  U.PostHookGlobal("SpellBook_Update", Reapply)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

function SB:OnEnable()
  BuildFrame()
end
