-- unrealUI :: core/playercache.lua
--
-- Player name -> class and guild, for frames that show a player by name only.
--
-- A nameplate carries a name and no unit token, so nothing on it says which
-- class or guild the player is. A unit token does: the player, the target, the
-- mouseover and every party and raid member are read with UnitClass /
-- GetGuildInfo and remembered by name, and the guild roster adds the rest of
-- the player's own guild. Same sources as ShaguPlates' libunitscan (intent
-- only, no code reused). Session-only: nothing is written to SavedVariables.
--
-- Evidence: query_compat.py has no record for UnitClass; modules/tooltip.lua
-- already reads UnitClass(unit) as (localized, token) and GetGuildInfo(unit)
-- as (guild, rank) for its class-coloured player lines, so this follows the
-- shape that code relies on. GetNumPartyMembers, GetNumRaidMembers,
-- GetNumGuildMembers, GetGuildRosterInfo and GuildRoster are documented, not
-- runtime-verified; every call is resolved by name and pcalled, so a missing
-- or failing one only leaves the cache emptier.
--
-- The roster gives a localized class name and no token. The token is learned
-- from UnitClass reads (localized -> token) and resolved when asked, so a
-- roster entry gains its colour once anyone of that class has been seen.
--
-- Names are unique per realm, but a player and a creature can share one;
-- callers decide whether the name on their frame is a player.

local U = UnrealUI

local P = U.RegisterModule("playercache")

-- name -> { class = token or nil, localized = string or nil, guild = string }
P.players = {}
P.count = 0
P.LIMIT = 3000
-- localized class name -> token, learned from UnitClass
P.tokenOf = {}
P.ROSTER_INTERVAL = 120

local function Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3, r4, r5 = pcall(fn, a, b)
  if not ok then return nil end
  return r1, r2, r3, r4, r5
end

local function Truth(value)
  return value ~= nil and value ~= false and value ~= 0 and value ~= ""
end

function P.Add(name, token, localized, guild)
  if type(name) ~= "string" or name == "" then return end
  local entry = P.players[name]
  if not entry then
    if P.count >= P.LIMIT then
      P.players, P.count = {}, 0
    end
    entry = {}
    P.players[name] = entry
    P.count = P.count + 1
  end
  if type(token) == "string" and token ~= "" then entry.class = token end
  if type(localized) == "string" and localized ~= "" then
    entry.localized = localized
  end
  -- An empty guild is an answer only from a live unit read (guild = false).
  if type(guild) == "string" and guild ~= "" then
    entry.guild = guild
  elseif guild == false then
    entry.guild = nil
  end
end

function P.LearnUnit(unit)
  if not Truth(Call("UnitIsPlayer", unit)) then return end
  local name = Call("UnitName", unit)
  local localized, token = Call("UnitClass", unit)
  if type(localized) == "string" and type(token) == "string" then
    P.tokenOf[localized] = token
  end
  local guild = Call("GetGuildInfo", unit)
  P.Add(name, token, localized, type(guild) == "string" and guild or false)
end

function P.ScanGroup()
  local i
  for i = 1, tonumber(Call("GetNumPartyMembers")) or 0 do
    P.LearnUnit("party" .. i)
  end
  for i = 1, tonumber(Call("GetNumRaidMembers")) or 0 do
    P.LearnUnit("raid" .. i)
  end
end

function P.ScanRoster()
  local guild = Call("GetGuildInfo", "player")
  if type(guild) ~= "string" then return end
  local i
  for i = 1, tonumber(Call("GetNumGuildMembers")) or 0 do
    local name, _, _, _, localized = Call("GetGuildRosterInfo", i)
    P.Add(name, nil, localized, guild)
  end
end

-- The roster is only as fresh as the last request; GuildRoster asks the server
-- and GUILD_ROSTER_UPDATE answers.
function P.RequestRoster()
  if type(Call("GetGuildInfo", "player")) ~= "string" then return end
  Call("GuildRoster")
end

-- Public: class token (or nil) and guild (or nil) for a player name.
function U.PlayerInfo(name)
  local entry = name and P.players[name]
  if not entry then return nil, nil end
  local token = entry.class or (entry.localized and P.tokenOf[entry.localized])
  return token, entry.guild
end

-- Public: whether the name was ever read as a player.
function U.PlayerKnown(name)
  return name and P.players[name] ~= nil or false
end

-- Public: the player's own guild, for "same guild" checks.
function U.PlayerGuild()
  local guild = Call("GetGuildInfo", "player")
  return type(guild) == "string" and guild or nil
end

-- Public: learn a unit now. The nameplates call it for the target and the
-- mouseover on each pass, so a plate is coloured without waiting for an event.
function U.PlayerCacheLearn(unit)
  P.LearnUnit(unit)
end

function P:OnEnable()
  U.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    P.LearnUnit("player")
    P.ScanGroup()
    P.RequestRoster()
  end)
  U.RegisterEvent("PLAYER_TARGET_CHANGED", function() P.LearnUnit("target") end)
  -- No mouseover event: UPDATE_MOUSEOVER_UNIT has no compat record, and the
  -- nameplates learn the mouseover every pass (U.PlayerCacheLearn).
  U.RegisterEvent("PARTY_MEMBERS_CHANGED", P.ScanGroup)
  U.RegisterEvent("RAID_ROSTER_UPDATE", P.ScanGroup)
  U.RegisterEvent("GUILD_ROSTER_UPDATE", P.ScanRoster)
  -- The timer also reads whatever roster the client already holds, in case
  -- GUILD_ROSTER_UPDATE (documented, unverified) never arrives.
  U.RegisterUpdate("playercache.roster", P.ROSTER_INTERVAL, function()
    P.ScanRoster()
    P.RequestRoster()
  end)
end
