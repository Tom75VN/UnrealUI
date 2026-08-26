-- unrealUI :: modules/windowmove.lua
--
-- Wires U.MakeWindowDraggable (core/windowdrag.lua) onto native windows that
-- unrealUI does not otherwise skin, so they can be repositioned by their
-- header the same way the Quest Log and Spellbook are. Native close buttons
-- here are the unstyled ~32px stock ones, so the header strip reserves more
-- room on the right than the restyled 17px close buttons in questlog.lua /
-- spellbook.lua need.
--
-- WorldMapFrame is not registered here: it needs the fullscreen panel layout
-- undone before a header drag means anything, and unrealUI does not do that --
-- modules/worldmap.lua leaves the native map's layout alone and only draws the
-- zone level range beside the hovered zone name.

local U = UnrealUI
local WM = U.RegisterModule("windowmove")

local WINDOWS = {
  { id = "character", frame = "CharacterFrame" },
  { id = "friends", frame = "FriendsFrame" },
}

function WM:OnEnable()
  local i
  for i = 1, table.getn(WINDOWS) do
    local entry = WINDOWS[i]
    local frame = U.G(entry.frame)
    if frame then
      U.MakeWindowDraggable(entry.id, frame, { headerInset = 40 })
    else
      U.Debug("windowmove: " .. entry.frame .. " unavailable")
    end
  end
end
