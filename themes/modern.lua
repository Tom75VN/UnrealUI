-- unrealUI :: themes/modern.lua
--
-- The current UnrealUI visual system. Its tokens continue to live in
-- core/media.lua and its shared components in core/style.lua/widgets.lua; this
-- registration makes that established implementation an explicit theme.

local U = UnrealUI

U.RegisterThemeStyle("modern", {
  label = "Modern",
  available = true,
  apply = function(M)
    -- Themes reload-boundly mutate shared tokens in place. Reset every token
    -- Classic changes so switching back cannot retain its colours.
    M.color.unitFrameBorder[1], M.color.unitFrameBorder[2] = 0.05, 0.05
    M.color.unitFrameBorder[3], M.color.unitFrameBorder[4] = 0.05, 1.00
    M.color.healthFull[1], M.color.healthFull[2] = 0.18, 0.50
    M.color.healthFull[3], M.color.healthFull[4] = 0.22, 1.00
    M.unitFrame.usePastelGradient = true
    M.unitFrame.statusTexture = M.texture.statusBar
    M.unitFrame.background[1], M.unitFrame.background[2] = 0.06, 0.06
    M.unitFrame.background[3], M.unitFrame.background[4] = 0.06, 0.85
  end,
})
