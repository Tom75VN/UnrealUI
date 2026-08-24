-- unrealUI :: themes/classic-wow.lua
--
-- Classic WoW retains the client chrome on stock windows while UnrealUI's
-- modules remain fully enabled. Unit frames use the real client artwork over
-- UnrealUI's invisible mover/aura anchors, and action buttons reuse the live
-- client's own button faces over UnrealUI's full bar system. The merged bag
-- keeps its UnrealUI behavior but draws from the live ContainerFrame and item
-- slot assets. Addon-owned HUD extras use the Classic palette below. The theme
-- is never an addon-off switch.

local U = UnrealUI

U.RegisterThemeStyle("classic-wow", {
  label = "Classic WoW",
  available = true,
  nativeChrome = true,
  apply = function(M)
    -- These tokens still style addon-owned unit-frame extras such as the druid
    -- mana bar. Player/target/pet/party visuals themselves come from the native
    -- client frames while their UnrealUI anchors remain alive underneath.
    M.color.unitFrameBorder[1], M.color.unitFrameBorder[2] = 0.56, 0.43
    M.color.unitFrameBorder[3], M.color.unitFrameBorder[4] = 0.20, 1.00
    M.color.healthFull[1], M.color.healthFull[2] = 0.00, 0.75
    M.color.healthFull[3], M.color.healthFull[4] = 0.00, 1.00
    M.unitFrame.usePastelGradient = false
    M.unitFrame.statusTexture = M.texture.classicStatusBar
    M.unitFrame.background[1], M.unitFrame.background[2] = 0.12, 0.075
    M.unitFrame.background[3], M.unitFrame.background[4] = 0.035, 0.95
  end,
})
