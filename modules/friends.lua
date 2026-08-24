-- unrealUI :: modules/friends.lua
--
-- pfUI-modern-inspired treatment of the native Friends/Social window
-- (FriendsFrame): Friends+Ignore, Who and Guild tabs. Native list data,
-- scrolling, row templates and click behaviour stay intact; unrealUI changes
-- only artwork, typography and layout, matching the Character/Quest Log
-- treatment.
--
-- Scope trim: the Guild Control (rank/permission editor) popup and the Raid
-- Info / raid roster panels that also live under this frame are left native.
-- They are separate admin/raid subsystems, not the friend list itself, and
-- CLAUDE.md keeps raid systems out of scope unless explicitly requested.
--
-- WORKING_SOURCE, not runtime-verified on this client: query_compat.py has no
-- record at all for FriendsFrame or any of its children (no probe has ever
-- touched this window), so every name and behaviour below is taken from
-- UnrealPfUI's skins\blizzard\friends.lua as a same-client working
-- implementation rather than confirmed evidence. Verify in game and fold any
-- surprises into knowledge.json.

local U = UnrealUI
local M = U.media
local FR = U.RegisterModule("friends")

local GOLD = M.color.accent
local WHITE = M.color.text
local DIM = M.color.textDim

local frame, panel, whoSearchBackdrop

local function G(name)
  return U.G(name)
end

local function N(name, fallback)
  local value = tonumber(G(name))
  return value or fallback
end

-- Runs `fn` on the next shared-driver tick instead of inline. A post-hooked
-- native *_Update runs unrealUI's callback synchronously, inside the same
-- call chain that just added/removed a row and may still be mutating that
-- row's backing objects (texture handles, etc.) -- USER_CONFIRMED_INGAME: the
-- client crashed (native EXCEPTION_ACCESS_VIOLATION, not a catchable Lua
-- error) when Remove Friend triggered a synchronous re-style of the row list
-- from inside FriendsList_Update. Deferring one tick lets that native call
-- finish and settle before unrealUI touches the same rows.
--
-- The mechanism is shared with core/dropdown.lua, so it lives in core/init.lua.
local function DeferOnce(id, fn)
  U.DeferOnce("friends:" .. tostring(id), fn)
end

local function SetTextFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function Reposition(object, point, relativeTo, relativePoint, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, relativeTo, relativePoint, x, y)
  end)
end

-- USER_CONFIRMED_INGAME: removing a friend can crash the native client.
-- Remove its native handler and shield the control from all mouse input.
local function DisableRemoveFriend(button)
  if not button then return end

  -- Disable does not reliably prevent this native control's click path on the
  -- current client. Remove its handler and cover it with an inert button so
  -- clicks cannot reach the native frame even if it is re-enabled internally.
  pcall(button.SetScript, button, "OnClick", nil)
  pcall(button.Disable, button)
  pcall(button.SetBackdropColor, button, 0.08, 0.08, 0.08, 0.82)
  pcall(button.SetBackdropBorderColor, button, M.Unpack(M.color.border))

  local ok, text = pcall(button.GetFontString, button)
  if ok and text then SetTextFont(text, M.fontSize.normal, DIM) end

  local shield = button.uuiRemoveFriendShield
  if not shield then
    shield = U.CreateButton(frame or UIParent, {
      name = "UnrealUIRemoveFriendShield",
      text = "",
      width = 1,
      height = 1,
    })
    if not shield then return end

    shield:ClearAllPoints()
    shield:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    shield:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    local levelOk, level = pcall(button.GetFrameLevel, button)
    if levelOk and type(level) == "number" then
      pcall(shield.SetFrameLevel, shield, level + 2)
    end
    pcall(shield.SetAlpha, shield, 0)
    shield:SetScript("OnClick", function() end)
    -- The independent GameTooltip path crashed on hover in-game. The shield
    -- must stay entirely inert until that sequence has focused probe evidence.
    shield:SetScript("OnEnter", nil)
    shield:SetScript("OnLeave", nil)
    button.uuiRemoveFriendShield = shield
  end
  pcall(shield.Show, shield)
end

-- ---------------------------------------------------------------------------
-- Friends tab (Friends list + Ignore sub-list)
-- ---------------------------------------------------------------------------
local function StyleFriendsSubTab()
  local scroll = G("FriendsFrameFriendsScrollFrame")
  if not scroll then return end

  U.StyleStockTabGroup(
    { G("FriendsFrameToggleTab1"), G("FriendsFrameToggleTab2") }, 1)
  Reposition(G("FriendsFrameToggleTab1"), "BOTTOMLEFT", scroll, "TOPLEFT", 0, 3)
  local toggle2 = G("FriendsFrameToggleTab2")
  if toggle2 then
    Reposition(toggle2, "LEFT", G("FriendsFrameToggleTab1"), "RIGHT", 3, 0)
  end

  U.StripStockTextures(scroll)
  U.CreateBackdrop(scroll, { background = { 0.01, 0.01, 0.01, 0.74 } })
  U.StyleStockScrollbar(G("FriendsFrameFriendsScrollFrameScrollBar"))

  -- Friend rows (FriendsFrameFriendButton<i>) are left fully native.
  -- USER_CONFIRMED_INGAME: touching them here (highlight-texture reanchor,
  -- row SetHeight) crashed the client -- first on Remove Friend, then again
  -- merely on selecting a row. Two crashes tied to this exact list is enough
  -- evidence to stop trying variations; see knowledge.json
  -- frames.friendsframe_row_touch_crashes_client. Do not re-add per-row
  -- styling here without a focused probe.

  local add = U.StyleStockButton(G("FriendsFrameAddFriendButton"))
  local remove = U.StyleStockButton(G("FriendsFrameRemoveFriendButton"))
  local message = U.StyleStockButton(G("FriendsFrameSendMessageButton"))
  local invite = U.StyleStockButton(G("FriendsFrameGroupInviteButton"))
  DisableRemoveFriend(remove)

  if add then
    pcall(add.SetWidth, add, 158)
    Reposition(add, "TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
  end
  if remove and add then
    pcall(remove.SetWidth, remove, 158)
    Reposition(remove, "TOP", add, "BOTTOM", 0, -4)
  end
  if message then
    pcall(message.SetWidth, message, 158)
    local down = G("FriendsFrameFriendsScrollFrameScrollBarScrollDownButton")
    Reposition(message, "TOPRIGHT", down or scroll, "BOTTOMRIGHT", 0, -6)
  end
  if invite and message then
    pcall(invite.SetWidth, invite, 158)
    Reposition(invite, "TOP", message, "BOTTOM", 0, -4)
  end
end

local function StyleIgnoreSubTab()
  local scroll = G("FriendsFrameIgnoreScrollFrame")
  if not scroll then return end

  U.StyleStockTabGroup(
    { G("IgnoreFrameToggleTab1"), G("IgnoreFrameToggleTab2") }, 1)
  Reposition(G("IgnoreFrameToggleTab1"), "BOTTOMLEFT", scroll, "TOPLEFT", 0, 3)
  local toggle2 = G("IgnoreFrameToggleTab2")
  if toggle2 then
    Reposition(toggle2, "LEFT", G("IgnoreFrameToggleTab1"), "RIGHT", 3, 0)
  end

  U.StripStockTextures(scroll)
  U.CreateBackdrop(scroll, { background = { 0.01, 0.01, 0.01, 0.74 } })
  U.StyleStockScrollbar(G("FriendsFrameIgnoreScrollFrameScrollBar"))

  -- Ignore rows left fully native, same reasoning as the Friends list above.

  local ignore = U.StyleStockButton(G("FriendsFrameIgnorePlayerButton"))
  local stop = U.StyleStockButton(G("FriendsFrameStopIgnoreButton"))
  if ignore then
    pcall(ignore.SetWidth, ignore, 158)
    Reposition(ignore, "TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
  end
  if stop then
    pcall(stop.SetWidth, stop, 158)
    local down = G("FriendsFrameIgnoreScrollFrameScrollBarScrollDownButton")
    Reposition(stop, "TOPRIGHT", down or scroll, "BOTTOMRIGHT", 0, -6)
  end
end

-- ---------------------------------------------------------------------------
-- Who tab
-- ---------------------------------------------------------------------------
-- Column headers 3/4/1/2 (Level, Class, Name, Zone) are native-anchored
-- relative to each other in that order, not left-to-right by index -- copied
-- as-is from a client that draws them stacked once their stock textures are
-- stripped. Chained explicitly here in display order instead, each narrowed
-- to the field it actually holds. WORKING_SOURCE from UnrealPfUI's own Who
-- tab skin.
local function StyleWhoHeaders(scroll)
  local level = G("WhoFrameColumnHeader3")
  local class = G("WhoFrameColumnHeader4")
  local name = G("WhoFrameColumnHeader1")
  local zone = G("WhoFrameColumnHeader2")

  local headers = { level, class, name, zone }
  local i
  for i = 1, table.getn(headers) do
    local header = headers[i]
    if header then
      U.StripStockTextures(header)
      SetTextFont(header, M.fontSize.small, DIM)
    end
  end

  if level then Reposition(level, "BOTTOMLEFT", scroll, "TOPLEFT", 0, 4) end
  if class and level then
    pcall(class.SetWidth, class, 32)
    Reposition(class, "LEFT", level, "RIGHT", 10, 0)
  end
  if name and class then
    pcall(name.SetWidth, name, 120)
    Reposition(name, "LEFT", class, "RIGHT", -2, 0)
  end
  if zone and name then Reposition(zone, "LEFT", name, "RIGHT", -2, 0) end
end

-- Per-row Level/Class/Name fields follow the same native stacked anchoring as
-- the headers above, and WhoList_Update re-applies its own native anchors on
-- every refresh -- so this has to run again after every update, not just once
-- at build time.
local function StyleWhoRows()
  local count = N("WHOS_TO_DISPLAY", 17)
  local i
  for i = 1, count do
    local row = G("WhoFrameButton" .. i)
    local level = G("WhoFrameButton" .. i .. "Level")
    local class = G("WhoFrameButton" .. i .. "Class")
    local name = G("WhoFrameButton" .. i .. "Name")

    if level and row then Reposition(level, "TOPLEFT", row, "TOPLEFT", 10, -3) end
    if class and level then
      pcall(class.SetWidth, class, 30)
      Reposition(class, "LEFT", level, "RIGHT", 10, 0)
    end
    if name and class then
      pcall(name.SetWidth, name, 120)
      Reposition(name, "LEFT", class, "RIGHT", 0, 0)
    end
  end
end

local function RaiseWhoButton(button)
  if not button then return end
  if panel then
    local ok, level = pcall(panel.GetFrameLevel, panel)
    if ok and tonumber(level) then
      pcall(button.SetFrameLevel, button, level + 2)
    end
  end
end

local function EnsureWhoSearchBackdrop(scroll)
  local edit = G("WhoFrameEditBox")
  if not scroll or not edit then return nil end

  -- USER_CONFIRMED_INGAME: mutating the native WhoFrameEditBox crashes during
  -- login. Restore the visible search field with addon-owned chrome anchored
  -- to its bounds; do not alter the EditBox itself in any way.
  if not whoSearchBackdrop then
    whoSearchBackdrop = U.CreatePanel(scroll, {
      name = "UnrealUIWhoSearchBackdrop",
      width = 1,
      height = 1,
    })
    pcall(whoSearchBackdrop.EnableMouse, whoSearchBackdrop, false)

    local ok, level = pcall(scroll.GetFrameLevel, scroll)
    if ok and tonumber(level) then
      pcall(whoSearchBackdrop.SetFrameLevel, whoSearchBackdrop, level)
    end
  end

  pcall(function()
    whoSearchBackdrop:ClearAllPoints()
    whoSearchBackdrop:SetPoint("TOPLEFT", edit, "TOPLEFT", -2, -5)
    whoSearchBackdrop:SetPoint("TOPRIGHT", edit, "TOPRIGHT", -2, -5)
    whoSearchBackdrop:SetHeight(22)
    whoSearchBackdrop:Show()
  end)
  return whoSearchBackdrop
end

local function LayoutWhoFooter()
  local totals = G("WhoFrameTotals")
  local who = G("WhoFrameWhoButton")
  local addFriend = G("WhoFrameAddFriendButton")
  local groupInvite = G("WhoFrameGroupInviteButton")
  -- WhoFrameEditBox is client-owned and must remain completely untouched; a
  -- focused login bisection confirmed that even visual/mouse mutation crashes
  -- the native client. The owned backdrop restores the compact search-field
  -- bounds and also provides a safe footer anchor.
  local scroll = G("WhoListScrollFrame")
  local anchor = EnsureWhoSearchBackdrop(scroll) or
                 G("WhoFrameEditBox") or scroll
  if not anchor then return end

  -- One results row followed by one action row. Native updates used to put the
  -- totals back under the buttons, leaving the labels visually merged.
  if totals then
    SetTextFont(totals, M.fontSize.small, WHITE)
    Reposition(totals, "TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  end

  local buttonAnchor = totals or anchor
  if who then
    Reposition(who, "TOPLEFT", buttonAnchor, "BOTTOMLEFT", 0, -5)
  end
  if groupInvite then
    Reposition(groupInvite, "TOPRIGHT", buttonAnchor, "BOTTOMRIGHT", 0, -5)
  end
  if addFriend and who and groupInvite then
    pcall(function()
      addFriend:ClearAllPoints()
      addFriend:SetPoint("LEFT", who, "RIGHT", 3, 0)
      addFriend:SetPoint("RIGHT", groupInvite, "LEFT", -3, 0)
    end)
  end

  RaiseWhoButton(who)
  RaiseWhoButton(addFriend)
  RaiseWhoButton(groupInvite)
end

local function StyleWhoTab()
  local scroll = G("WhoListScrollFrame")
  if not scroll then return end

  U.StripStockTextures(scroll)
  U.CreateBackdrop(scroll, { background = { 0.01, 0.01, 0.01, 0.74 } })
  U.StyleStockScrollbar(G("WhoListScrollFrameScrollBar"))
  Reposition(G("WhoFrameButton1"), "TOPLEFT", scroll, "TOPLEFT", -5, -5)

  StyleWhoHeaders(scroll)
  StyleWhoRows()

  -- Keep the native text filter untouched; test the dropdown independently.
  U.Dropdown.StyleStock(G("WhoFrameDropDown"), 120)
  local dropdown = G("WhoFrameDropDown")
  if dropdown then
    Reposition(dropdown, "BOTTOMRIGHT", scroll, "TOPRIGHT", 0, 3)
  end

  local who = U.StyleStockButton(G("WhoFrameWhoButton"))
  local addFriend = U.StyleStockButton(G("WhoFrameAddFriendButton"))
  local groupInvite = U.StyleStockButton(G("WhoFrameGroupInviteButton"))
  LayoutWhoFooter()
end

-- ---------------------------------------------------------------------------
-- Guild tab
--
-- Column headers, roster list and the MOTD/notes controls only -- the deeper
-- rank-editing (GuildControlPopupFrame) dialog stays native, per the scope
-- trim above.
-- ---------------------------------------------------------------------------
local GUILD_HEADER_PREFIXES = {
  "GuildFrameColumnHeader",
  "GuildFrameGuildStatusColumnHeader",
}

-- The stock sort texture is anchored near the header's right edge. That puts
-- it over longer localized labels once unrealUI narrows the roster columns.
-- Keep the semantic texture while stripping the decorative header pieces,
-- then place it from the rendered label width so it follows every locale and
-- both guild-list header sets.
local function PositionGuildSortArrows()
  local prefixIndex, column
  for prefixIndex = 1, table.getn(GUILD_HEADER_PREFIXES) do
    local prefix = GUILD_HEADER_PREFIXES[prefixIndex]
    for column = 1, 4 do
      local header = G(prefix .. column)
      local arrow = G(prefix .. column .. "Arrow")
      local text

      if header and arrow and header.GetFontString then
        pcall(function() text = header:GetFontString() end)
      end
      if not text then text = G(prefix .. column .. "Text") end

      if text and text.GetStringWidth then
        local widthOk, width = pcall(text.GetStringWidth, text)
        if widthOk and tonumber(width) then
          pcall(function()
            arrow:ClearAllPoints()
            arrow:SetPoint("LEFT", text, "CENTER",
                           math.floor(tonumber(width) / 2 + 0.5) + 2, 0)
          end)
        end
      end
    end
  end
end

local function StyleGuildHeaders()
  local prefixIndex, column
  for prefixIndex = 1, table.getn(GUILD_HEADER_PREFIXES) do
    local prefix = GUILD_HEADER_PREFIXES[prefixIndex]
    for column = 1, 4 do
      local header = G(prefix .. column)
      if header then
        local arrow = G(prefix .. column .. "Arrow")
        local extra
        if arrow then extra = { keep = { [arrow] = true } } end
        U.StripStockTextures(header, extra)
        SetTextFont(header, M.fontSize.small, DIM)
      end
    end
  end

  PositionGuildSortArrows()
end

local function StyleGuildTab()
  local scroll = G("GuildListScrollFrame")
  if not scroll then return end

  U.StripStockTextures(scroll)
  U.CreateBackdrop(scroll, { background = { 0.01, 0.01, 0.01, 0.74 } })
  U.StyleStockScrollbar(G("GuildListScrollFrameScrollBar"))

  StyleGuildHeaders()
  local i
  Reposition(G("GuildFrameColumnHeader3"), "TOPLEFT", frame, "TOPLEFT", 20, -70)

  local toggle = G("GuildFrameGuildListToggleButton")
  if toggle then
    U.StyleStockArrowButton(toggle, "right", 16)
    Reposition(toggle, "TOPLEFT", scroll, "BOTTOMRIGHT", -20, 20)
  end

  local motd = G("GuildMOTDEditButton")
  if motd then
    U.CreateBackdrop(motd, { background = { 0.01, 0.01, 0.01, 0.78 } })
    Reposition(motd, "TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
    local down = G("GuildListScrollFrameScrollBarScrollDownButton")
    pcall(motd.SetPoint, motd, "BOTTOMRIGHT", down or scroll, "BOTTOMRIGHT", 0, -68)
  end

  local notesLabel = G("GuildFrameNotesLabel")
  if notesLabel then SetTextFont(notesLabel, M.fontSize.small, DIM) end
  local notesText = G("GuildFrameNotesText")
  if notesText then SetTextFont(notesText, M.fontSize.small, WHITE) end

  local info = U.StyleStockButton(G("GuildFrameGuildInformationButton"))
  local addMember = U.StyleStockButton(G("GuildFrameAddMemberButton"))
  local control = U.StyleStockButton(G("GuildFrameControlButton"))
  if info and motd then Reposition(info, "TOPLEFT", motd, "BOTTOMLEFT", 0, -5) end
  if addMember and info and control then
    pcall(function()
      addMember:ClearAllPoints()
      addMember:SetPoint("LEFT", info, "RIGHT", 3, 0)
      addMember:SetPoint("RIGHT", control, "LEFT", -3, 0)
    end)
  end
  if control and motd then Reposition(control, "TOPRIGHT", motd, "BOTTOMRIGHT", 0, -5) end

  U.StripStockTextures(G("GuildFrameLFGFrame"))
  U.StyleStockCheckbox(G("GuildFrameLFGButton"), 20)

  -- Member detail side dock.
  local detail = G("GuildMemberDetailFrame")
  if detail then
    U.StripStockTextures(detail)
    U.CreateBackdrop(detail, { background = { 0.01, 0.01, 0.01, 0.82 } })
    U.StyleStockCloseButton(G("GuildMemberDetailCloseButton"), detail, -6, -6)

    local fields = { "ZoneText", "RankText", "OnlineText" }
    for i = 1, table.getn(fields) do
      local text = G("GuildMemberDetail" .. fields[i])
      if text then
        pcall(text.SetPoint, text, "RIGHT", -20, 0)
        pcall(text.SetJustifyH, text, "RIGHT")
        SetTextFont(text, M.fontSize.small, WHITE)
      end
    end

    U.StyleStockArrowButton(G("GuildFramePromoteButton"), "up", 12)
    U.StyleStockArrowButton(G("GuildFrameDemoteButton"), "down", 12)

    U.StripStockTextures(G("GuildMemberNoteBackground"))
    U.CreateBackdrop(G("GuildMemberNoteBackground"), {})
    U.StripStockTextures(G("GuildMemberOfficerNoteBackground"))
    U.CreateBackdrop(G("GuildMemberOfficerNoteBackground"), {})

    U.StyleStockButton(G("GuildMemberRemoveButton"))
    U.StyleStockButton(G("GuildMemberGroupInviteButton"))
  end

  -- Guild info (MOTD editor) dock.
  local guildInfo = G("GuildInfoFrame")
  if guildInfo then
    U.StripStockTextures(guildInfo)
    U.CreateBackdrop(guildInfo, { background = { 0.01, 0.01, 0.01, 0.82 } })
    U.StyleStockCloseButton(G("GuildInfoCloseButton"), guildInfo, -6, -6)
    U.CreateBackdrop(G("GuildInfoTextBackground"), {})
    U.StyleStockScrollbar(G("GuildInfoFrameScrollFrameScrollBar"))
    U.StyleStockButton(G("GuildInfoSaveButton"))
    U.StyleStockButton(G("GuildInfoCancelButton"))
  end
end

-- ---------------------------------------------------------------------------
-- Frame chrome + tabs
-- ---------------------------------------------------------------------------
local function Reapply()
  U.StripStockTextures(frame)
  if panel then panel:Show() end
  SetTextFont(G("FriendsFrameTitleText"), M.fontSize.large, GOLD)
  PositionGuildSortArrows()
  LayoutWhoFooter()
end

local function BuildFrame()
  frame = G("FriendsFrame")
  if not frame then
    U.Debug("friends: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  -- The content backdrop is inset from the real frame bounds, the same shape
  -- as modules/character.lua's panel: leaving a strip at the bottom outside
  -- the dark box for the tab row to hang in, rather than covering the whole
  -- frame and burying the tabs inside it (USER_CONFIRMED_INGAME: an earlier
  -- version backdropped the full frame and the tab row rendered stuck up
  -- against the button row, well inside the box, because FriendsFrameTab1's
  -- native anchor is not the frame's true bottom edge on this client and has
  -- to be moved there explicitly -- see the Tab1 reposition below).
  panel = U.CreatePanel(frame, {
    name = "UnrealUIFriendsPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 48)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 8, 32, 10, 48)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  -- FriendsFrameCloseButton is anchored to panel, whose right edge is 32px
  -- inside FriendsFrame. Reserve its full horizontal bounds so the raised
  -- header drag handle cannot steal hover/clicks from the button's upper
  -- section (same fix as modules/character.lua's headerInset).
  U.MakeWindowDraggable("friends", frame, { headerInset = 56 })

  Reposition(G("FriendsFrameTitleText"), "TOP", panel, "TOP", 0, -10)
  SetTextFont(G("FriendsFrameTitleText"), M.fontSize.large, GOLD)
  U.StyleStockCloseButton(G("FriendsFrameCloseButton"), panel, -6, -6)

  -- FriendsFrameTab1-5: Friends, Who, Guild, Raid, (TBC+) Channels. Only the
  -- present ones are collected, so this reads the same on a client that never
  -- shows a Channels tab.
  local tabs, i = {}, nil
  for i = 1, 5 do
    local tab = G("FriendsFrameTab" .. i)
    if tab then table.insert(tabs, tab) end
  end
  Reposition(tabs[1], "TOPLEFT", panel, "BOTTOMLEFT", 0, 0)
  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)

  StyleFriendsSubTab()
  StyleIgnoreSubTab()
  StyleWhoTab()
  StyleGuildTab()

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  -- REVERTED, USER_CONFIRMED_INGAME (crash): an earlier version manually
  -- re-invoked frame:GetScript(frame, "OnEvent") on FRIENDLIST_UPDATE to fix
  -- the new-friend-doesn't-appear-immediately symptom. Removing a friend then
  -- crashed the client. Calling a native OnEvent handler directly, outside
  -- the engine's own dispatch, does not populate whatever implicit state
  -- (arg1/event globals, or something else this client's FriendsFrame handler
  -- reads) a real event delivery would -- and unlike a Lua error that path is
  -- not pcall-catchable if the native side reads bad data. Do not re-add this
  -- without a focused probe confirming what FriendsFrame's OnEvent actually
  -- needs when called synthetically. The refresh-lag symptom itself is back
  -- to unaddressed; report it again separately if still needed.

  -- REVERTED, USER_CONFIRMED_INGAME (crash): the FriendsList_Update post-hook
  -- also used to re-style FriendsFrameFriendButton row highlights, deferred by
  -- one tick (see DeferOnce above). That still crashed the client, this time
  -- merely on selecting a row, not just on remove. Friend rows are now left
  -- fully native (see StyleFriendsSubTab/StyleIgnoreSubTab); there is nothing
  -- left for this hook to do. See knowledge.json
  -- frames.friendsframe_row_touch_crashes_client.

  U.PostHookGlobal("WhoList_Update", function()
    DeferOnce("friends.restyle-who-rows", function()
      StyleWhoRows()
      LayoutWhoFooter()
    end)
  end)

  -- WORKING_SOURCE from UnrealPfUI on this same client: GuildStatus_Update is
  -- the native roster refresh used when sorting and switching guild-list mode.
  -- Recalculate after it changes the active header so the shown arrow remains
  -- beside the current label.
  U.PostHookGlobal("GuildStatus_Update", PositionGuildSortArrows)

  if frame.IsShown then
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then Reapply() end
  end
  return true
end

function FR:OnEnable()
  -- Keep the client Friends/Social window intact; the independent windowmove
  -- module continues to provide the UnrealUI mover in this theme.
  if U.ThemeStyleUsesNativeChrome() then return end
  BuildFrame()
end
