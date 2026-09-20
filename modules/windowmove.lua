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
--
-- Modern WoW keeps NPC/service dialogs and the mailbox on the classic-wow
-- native path (U.ThemeStyleUsesClassicInteractionChrome), so their Modern
-- modules never build and never register a drag handle. Under that theme only
-- the `interaction` entries are registered here; Friends, Spellbook, Talents
-- and Quest Log are themed surfaces whose own modules own their drag handles.

local U = UnrealUI
local WM = U.RegisterModule("windowmove")

local WINDOWS = {
  { id = "friends", frame = "FriendsFrame" },
  { id = "spellbook", frame = "SpellBookFrame" },
  -- Same-client working source supports the Vanilla TalentFrame name and the
  -- TBC-shaped PlayerTalentFrame variant. Resolve whichever one was loaded.
  { id = "talents", frames = { "PlayerTalentFrame", "TalentFrame" } },
  { id = "questlog", frame = "QuestLogFrame" },
  { id = "merchant", frame = "MerchantFrame", interaction = true },
  { id = "trainer", frame = "ClassTrainerFrame", interaction = true },
  -- The quest giver's two windows swap in place during one conversation:
  -- one stored position and one group (core/windowdrag.lua), as in
  -- modules/quest.lua and modules/gossip.lua.
  { id = "gossip", frame = "GossipFrame", interaction = true,
    dragId = "questgiver", group = "questgiver" },
  { id = "quest", frame = "QuestFrame", interaction = true,
    dragId = "questgiver", group = "questgiver" },
  { id = "mail", frame = "MailFrame", interaction = true },
}
local interactionOnly = false

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
    -- The quest giver's two windows under their Modern WoW design are built
    -- by modules/quest.lua and modules/gossip.lua, which register their own
    -- drag handles.
    if (entry.id == "quest" or entry.id == "gossip") and not entry.registered and
       type(U.ModernWowQuestDialogActive) == "function" and
       U.ModernWowQuestDialogActive() then
      entry.registered = true
    end
    if not entry.registered and (entry.interaction or not interactionOnly) then
      local frame = ResolveFrame(entry)
      if frame then
        U.MakeWindowDraggable(entry.dragId or entry.id, frame,
                              { headerInset = 40, group = entry.group })
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
  if not U.ThemeStyleUsesClassicInteractionChrome() then return end
  interactionOnly = not U.ThemeStyleUsesNativeChrome()
  if TryRegister() then return end

  listening = true
  local i
  for i = 1, table.getn(RETRY_EVENTS) do
    U.RegisterEvent(RETRY_EVENTS[i], TryRegister)
  end
end
