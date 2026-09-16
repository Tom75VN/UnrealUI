-- unrealUI :: themes/modern-wow.lua
--
-- The Dragonflight-styled visual family: ornamental unit-frame housings, a
-- gold-rimmed cast bar and textured window chrome, drawn from the art imported
-- into media/Textures/modern-wow (see that folder's ATTRIBUTION.md).
--
-- This is the one UnrealUI theme exempt from the flat/near-black language in
-- rules/unreal-ui-design.md, because reproducing that look is the whole point
-- of it. rules/unreal-ui-design.md "Theme scope" records the exemption and its
-- limits; `modern` and `classic-wow` are untouched by any of it.
--
-- nativeChrome stays false: UnrealUI draws its own frames under this theme and
-- then dresses them, exactly as it does under `modern`. It never hands a
-- surface back to the client the way `classic-wow` does, and it never takes
-- the DragonflightUI route of no-opping Show on the native unit frames --
-- rules/unreal-ui.md records that lifecycle as crash-confirmed.
--
-- Only shared tokens live here. The drawing itself is modules/modernwow.lua,
-- which owns both this theme's complete implementation and the same complete
-- per-module paths Classic can explicitly select.

local U = UnrealUI

U.RegisterThemeStyle("modern-wow", {
  label = "Modern WoW",
  available = true,
  nativeChrome = false,
  apply = function(M)
    -- Themes mutate the shared token tables in place and must reset every
    -- token any other theme writes, so switching between them cannot leave a
    -- colour behind. The token list here is deliberately the same one
    -- themes/modern.lua and themes/classic-wow.lua write.
    --
    -- The housing art supplies the visible frame edge, so the flat outline the
    -- bar boxes draw is pulled down to near-black rather than removed: it
    -- still separates the two fills where the ornament does not reach.
    M.color.unitFrameBorder[1], M.color.unitFrameBorder[2] = 0.04, 0.03
    M.color.unitFrameBorder[3], M.color.unitFrameBorder[4] = 0.02, 1.00

    -- Dragonflight's health green. Bright and fully saturated, not the
    -- desaturated UnrealUI fill: this theme reproduces a specific interface,
    -- and modules/unitframes.lua now holds this one colour at every health
    -- level under this theme rather than fading into the pastel gradient.
    M.color.healthFull[1], M.color.healthFull[2] = 0.10, 0.80
    M.color.healthFull[3], M.color.healthFull[4] = 0.10, 1.00

    -- The power palette is deliberately NOT overridden here. M.power is
    -- UnrealUI's own semantic colour set, no other theme writes it, and it is
    -- a feature of the addon rather than part of the layout this theme
    -- reproduces. The bar colour settings -- custom colours, class health
    -- colours, the pastel gradient -- all keep working exactly as they do
    -- under `modern`; only the geometry is Dragonflight's.

    -- The imported fills already carry their own vertical shading, so the
    -- pastel gradient UnrealUI applies on top of a flat bar would double it.
    M.unitFrame.usePastelGradient = false
    M.unitFrame.statusTexture = M.modernWow.texture.healthFill

    -- Warmer and more opaque than the modern near-black: the housing art is
    -- brown-gold and a cold grey bar bed reads as a different interface.
    M.unitFrame.background[1], M.unitFrame.background[2] = 0.07, 0.06
    M.unitFrame.background[3], M.unitFrame.background[4] = 0.05, 0.92

    -- Untinted. The cast fills are the Dragonflight per-state art (cast,
    -- channel, craft, interrupted), already coloured, so any vertex colour
    -- here would only muddy them. modules/castbar.lua applies it through
    -- ApplyUnitBarTint, and modules/modernwow.lua restores it after a finish.
    -- The pushback colour is deliberately left alone: it still needs to read
    -- as a state change.
    M.color.cast[1], M.color.cast[2] = 1.00, 1.00
    M.color.cast[3], M.color.cast[4] = 1.00, 1.00
  end,
})
