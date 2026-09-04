-- unrealUI :: modules/castbarclassic.lua
--
-- Classic-only target castbar skin. Candidate A was confirmed visible in game
-- on 2026-09-05: Interface\CastingBar\UI-CastingBar-Border. The measured
-- CastingBarFrame geometry is reproduced with addon-owned regions only. This
-- file deliberately never resolves, walks, retains, anchors to, or mutates the
-- client's CastingBarFrame or any of its regions; see knowledge.json /
-- castbar.native_frame_hierarchy and frames.native_widget_reference_crash_risk.

local U = UnrealUI
local M = U.media
local classicCastbar = {
  WIDTH = 195,
  HEIGHT = 13,
  BORDER_WIDTH = 256,
  BORDER_HEIGHT = 64,
  SPARK_WIDTH = 32,
  SPARK_HEIGHT = 32,
  FILL_COLOR = { 1.00, 0.70, 0.00, 1.00 },
  BACKGROUND_COLOR = { 0.12, 0.12, 0.12, 1.00 },
}

function classicCastbar.UpdateSpark(widget)
  if not widget or not widget.uuiSpark then return end

  local size = tonumber(widget:GetWidth()) or 0
  local minimum = tonumber(widget.uuiMin) or 0
  local range = (tonumber(widget.uuiMax) or 0) - minimum
  local extent = 0
  if range > 0 and size > 0 then
    extent = size / range * ((tonumber(widget.uuiValue) or 0) - minimum)
  end
  if extent < 0 then extent = 0 end
  if extent > size then extent = size end

  if extent <= 0 then
    if widget.uuiSpark:IsShown() then widget.uuiSpark:Hide() end
    return
  end

  widget.uuiSpark:ClearAllPoints()
  widget.uuiSpark:SetPoint("CENTER", widget, "LEFT", extent, 0)
  if not widget.uuiSpark:IsShown() then widget.uuiSpark:Show() end
end

function classicCastbar.SetDynamicShown(widget, shown)
  if not widget or not widget.uuiSpark then return end
  if not shown then
    if widget.uuiSpark:IsShown() then widget.uuiSpark:Hide() end
    return
  end
  classicCastbar.UpdateSpark(widget)
end

function U.CreateClassicTargetCastbar(frameName)
  -- Exact-theme gate: no other native-chrome or Modern theme inherits this
  -- ornamental stock art merely because it shares module infrastructure.
  if type(U.GetActiveThemeStyle) ~= "function" or
     U.GetActiveThemeStyle() ~= "classic-wow" then return nil end

  local widget = U.CreateStatusBar(UIParent, {
    name = frameName,
    width = classicCastbar.WIDTH,
    height = classicCastbar.HEIGHT,
    texture = M.texture.classicStatusBar,
    color = classicCastbar.FILL_COLOR,
    background = classicCastbar.BACKGROUND_COLOR,
  })
  if not widget then return nil end

  -- Match the safe visual probe exactly: the depleted bed uses the same stock
  -- status texture at a dark tint, with the verified normal border over it.
  widget.uuiBackground:SetTexture(M.texture.classicStatusBar)

  local border = widget:CreateTexture(nil, "OVERLAY")
  border:SetTexture(M.texture.classicCastbarBorder)
  border:SetWidth(classicCastbar.BORDER_WIDTH)
  border:SetHeight(classicCastbar.BORDER_HEIGHT)
  border:SetPoint("CENTER", widget, "CENTER", 0, 0)

  local spark = widget:CreateTexture(nil, "OVERLAY")
  spark:SetTexture(M.texture.classicCastbarSpark)
  spark:SetWidth(classicCastbar.SPARK_WIDTH)
  spark:SetHeight(classicCastbar.SPARK_HEIGHT)
  -- This stock texture carries a black field intended for additive
  -- composition. With the default BLEND mode that field becomes the moving
  -- black square confirmed in game on 2026-09-05. Updated-client docs support
  -- ADD; if the method is absent or errors, omit the optional spark instead of
  -- leaving the artifact visible.
  if not spark.SetBlendMode or
     not pcall(spark.SetBlendMode, spark, "ADD") then
    spark:Hide()
    spark = nil
  end
  if spark then
    spark:SetPoint("CENTER", widget, "LEFT", 0, 0)
    spark:Hide()
  end

  local name = U.CreateLabel(widget, {
    inherits = "GameFontHighlightSmall",
    color = M.color.text,
    width = 185,
    height = 16,
    justify = "CENTER",
  })
  if name then name:SetPoint("CENTER", widget, "CENTER", 0, 0) end

  -- The castbar tracker consumes the same compact widget contract as Modern.
  -- This Classic version intentionally has no icon or countdown: the measured
  -- native bar has one centered text region and no separate icon/time cell.
  widget.bar = widget
  widget.name = name
  widget.time = nil
  widget.icon = nil
  widget.showIcon = false
  widget.uuiKeepNativeTint = true
  widget.uuiSpark = spark
  if spark then
    widget.uuiUpdateSpark = classicCastbar.UpdateSpark
    widget.uuiSetDynamicShown = classicCastbar.SetDynamicShown
  end
  widget.uuiCells = { widget.uuiBackground, widget.uuiFillTexture, border }
  if name then table.insert(widget.uuiCells, name) end

  widget:SetMinMaxValues(0, 1)
  widget:SetValue(0)
  return widget
end
