-- unrealUI :: modules/talents.lua
--
-- Chooses the Talent window's drawing path, and nothing else. Both paths
-- rebuild the same interface -- all three talent trees side by side, with
-- addon-owned talent buttons, prerequisite branches and per-tree headers -- so
-- the choice here is only which visual family draws it:
--
--   modules/talentsmodernwow.lua  the `modern-wow` theme (and Classic's
--                                 explicit Talents selection)
--   modules/talentsmodern.lua     the `modern` theme
--   modules/talentsclassic.lua    `classic-wow` (user request, 2026-09-21),
--                                 whenever that Talents selection is off
--
-- The client keeps owning talent data, ranks, tooltips, prerequisites and
-- LearnTalent in all three. Under `classic-wow` the Talents Classic -> Modern
-- WoW module chooses between the Dragonflight housing and the client's own,
-- exactly as the Quest Log's module chooses between its two designs; neither
-- setting leaves the native single-tree window in place.
--
-- A path is entered once and never falls back to another: by the time one can
-- fail the window may already be partly rebuilt, so the failure is reported
-- rather than papered over with a second attempt.

local U = UnrealUI
local TL = U.RegisterModule("talents")

local built = false

-- UnrealPfUI's same-client skin supports both names: TalentFrame is the
-- Vanilla-shaped window and PlayerTalentFrame is the TBC-shaped equivalent.
-- This is WORKING_SOURCE evidence, not a runtime measurement, so the lookup
-- stays optional and nil-safe.
local function ResolveFrame()
  local candidate = U.G("PlayerTalentFrame") or U.G("TalentFrame")
  if not candidate then return nil end

  local ok, name = pcall(candidate.GetName, candidate)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  return candidate
end

local function Wanted(test)
  return type(test) == "function" and test() and true or false
end

local function Build(label, builder, frame)
  local ok, err = pcall(builder, frame)
  if not ok then
    U.Error("talents: " .. label .. " drawing path: " .. tostring(err))
  end
  built = true
  return true
end

local function BuildFrame()
  if built then return true end

  local frame = ResolveFrame()
  if not frame then
    U.Debug("talents: native frame unavailable")
    return false
  end

  if Wanted(U.ModernWowTalentsWanted) then
    return Build("modern-wow", U.BuildModernWowTalents, frame)
  end
  if Wanted(U.ModernTalentsWanted) then
    return Build("modern", U.BuildModernTalents, frame)
  end
  if Wanted(U.ClassicTalentsWanted) then
    return Build("classic-wow", U.BuildClassicTalents, frame)
  end

  -- No path claims this theme: the native window is left exactly as it is.
  built = true
  return true
end

local function AnyPathWanted()
  return Wanted(U.ModernWowTalentsWanted) or
         Wanted(U.ModernTalentsWanted) or
         Wanted(U.ClassicTalentsWanted)
end

-- TalentFrame may be created by Blizzard_TalentUI after unrealUI's own module
-- phase. ADDON_LOADED is the safe lazy-load fallback used by the other stock
-- windows in this addon.
local function TryBuild()
  if BuildFrame() then U.UnregisterEvent("ADDON_LOADED", TryBuild) end
end

function TL:OnEnable()
  -- Native chrome no longer means "leave this window alone": classic-wow has a
  -- path of its own, so the question is only whether any path claims it.
  if not AnyPathWanted() then return end
  if BuildFrame() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
end
