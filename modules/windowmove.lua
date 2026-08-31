-- unrealUI :: modules/windowmove.lua
--
-- Wires U.MakeWindowDraggable (core/windowdrag.lua) onto native-chrome windows
-- whose Modern modules intentionally skip their skin/build path. Native close
-- buttons here are the unstyled ~32px stock ones, so the header strip reserves
-- more room on the right than the restyled 17px Modern close buttons need.
--
-- WorldMapFrame is not registered here: it needs the fullscreen panel layout
-- undone before a header drag means anything, and unrealUI does not do that --
-- modules/worldmap.lua leaves the native map's layout alone and only draws the
-- zone level range beside the hovered zone name.

local U = UnrealUI
local WM = U.RegisterModule("windowmove")

local WINDOWS = {
  { id = "friends", frame = "FriendsFrame" },
  { id = "spellbook", frame = "SpellBookFrame" },
  -- Same-client working source supports the Vanilla TalentFrame name and the
  -- TBC-shaped PlayerTalentFrame variant. Resolve whichever one was loaded.
  { id = "talents", frames = { "PlayerTalentFrame", "TalentFrame" } },
  { id = "questlog", frame = "QuestLogFrame" },
  { id = "merchant", frame = "MerchantFrame" },
  { id = "trainer", frame = "ClassTrainerFrame" },
  { id = "gossip", frame = "GossipFrame" },
  { id = "quest", frame = "QuestFrame" },
  { id = "mail", frame = "MailFrame" },
}

-- Several stock dialogs are created lazily on this client. Reuse the same
-- documented opening events their Modern modules already trust, then stop
-- listening once every native frame has been registered.
local RETRY_EVENTS = {
  "ADDON_LOADED",
  "MERCHANT_SHOW",
  "TRAINER_SHOW",
  "GOSSIP_SHOW",
  "MAIL_SHOW",
  "QUEST_GREETING",
  "QUEST_DETAIL",
  "QUEST_PROGRESS",
  "QUEST_COMPLETE",
}
local listening = false

local function ResolveFrame(entry)
  if entry.frame then return U.G(entry.frame) end
  if type(entry.frames) ~= "table" then return nil end

  local i
  for i = 1, table.getn(entry.frames) do
    local frame = U.G(entry.frames[i])
    if frame then return frame end
  end
  return nil
end

local function TryRegister()
  local pending = false
  local i
  for i = 1, table.getn(WINDOWS) do
    local entry = WINDOWS[i]
    if not entry.registered then
      local frame = ResolveFrame(entry)
      if frame then
        U.MakeWindowDraggable(entry.id, frame, { headerInset = 40 })
        entry.registered = true
      else
        pending = true
      end
    end
  end
  if not pending and listening then
    for i = 1, table.getn(RETRY_EVENTS) do
      U.UnregisterEvent(RETRY_EVENTS[i], TryRegister)
    end
    listening = false
  end
  return not pending
end

function WM:OnEnable()
  if not U.ThemeStyleUsesNativeChrome() then return end
  if TryRegister() then return end

  listening = true
  local i
  for i = 1, table.getn(RETRY_EVENTS) do
    U.RegisterEvent(RETRY_EVENTS[i], TryRegister)
  end
end
