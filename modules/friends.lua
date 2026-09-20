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

-- Chosen once at OnEnable, before any control is styled
-- (rules/unreal-ui-design.md branching rule). Under the modern-wow `social`
-- surface this file keeps its layout but draws buttons, list channels, boxes
-- and docks from the theme (modules/modernwow.lua owns the window art, tabs
-- and close buttons); the shared flat treatment is never applied first.
local modernWow = false
-- Title, headings and field labels: the addon accent, or the theme's warm
-- gold. Body values stay WHITE in both.
local titleColor, headingColor = GOLD, DIM

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

-- The measured 128RedButton face on a native action button. The client
-- enables and disables these (Group Invite with an offline friend, Promote
-- by rank) outside any show, so its Enable/Disable are wrapped the way the
-- theme's tabs wrap SetWidth, and the repaint runs a tick later: never inside
-- the native list update that made the call (see DeferOnce above).
local function ModernWowActionButton(button, options)
  if not U.StyleModernWowActionButton(button, options) then return false end
  if button.uuiSocialEnableWatch then return true end
  button.uuiSocialEnableWatch = true

  local name = "button"
  local nameOk, value = pcall(button.GetName, button)
  if nameOk and value then name = value end
  local function Repaint()
    DeferOnce("action." .. name, function()
      U.StyleModernWowActionButton(button, options)
    end)
  end

  local enable, disable = button.Enable, button.Disable
  if type(enable) == "function" then
    button.Enable = function(self)
      local result = enable(self)
      Repaint()
      return result
    end
  end
  if type(disable) == "function" then
    button.Disable = function(self)
      local result = disable(self)
      Repaint()
      return result
    end
  end
  return true
end

-- Every action button in this window goes through here, so the theme branch
-- is decided in one place.
local function ActionButton(button, options)
  if not button then return nil end
  if modernWow and ModernWowActionButton(button, options) then return button end
  return U.StyleStockButton(button)
end

-- A list's scroll frame and its scrollbar. Modern WoW keeps the native bar
-- and its atlas (rules/unreal-ui-design.md) and only lays a channel behind
-- it, so nothing is stripped on that path.
--
-- REVERTED 2026-09-19, USER_CONFIRMED_INGAME (crash): these lists briefly
-- drew the shared MinimalScrollBar (U.StyleModernWowScrollbar) by user
-- request, as the quest-giver window and Character > Skills do. Scrolling a
-- social list then crashed the client, and in the same session clicking back
-- to the Friends tab from a scrolled Who list needed two clicks -- the first
-- never reached the tab (RUNTIME_PROBE social.tab_state.click1.v1:
-- selectedTab stayed 2 with Tab1 shown, enabled and carrying an OnClick).
-- Do not re-add it here without a focused probe explaining both. The Skills,
-- profession and quest-giver surfaces keep it; only this window is affected.
-- The Friends, Who and Guild channels take the lighter `listAlpha`.
local LIGHT_BEDS = {
  FriendsFrameFriendsScrollFrameScrollBar = true,
  WhoListScrollFrameScrollBar = true,
  GuildListScrollFrameScrollBar = true,
}

local function StyleList(scroll, barName)
  if modernWow then
    local bar = G(barName)
    U.ModernWowSocialScrollBed(bar)
    local bed = bar and bar.uuiModernWowProgressBackground
    if bed and LIGHT_BEDS[barName] then
      pcall(bed.SetAlpha, bed, M.modernWow.social.scrollBed.listAlpha)
    end
    return
  end
  U.StripStockTextures(scroll)
  U.CreateBackdrop(scroll, { background = { 0.01, 0.01, 0.01, 0.74 } })
  U.StyleStockScrollbar(G(barName))
end

-- A text/message bed: the theme's dark inset box, or the flat fill.
local function InsetBox(target, background)
  if not target then return end
  if modernWow and U.ModernWowInsetBox(target) then return end
  U.CreateBackdrop(target, background and { background = background } or {})
end

-- A guild side dock: the theme's metal housing, or the flat panel. The metal
-- is re-measured on every layout pass, so it follows the dock's live size.
local function DockHousing(dock)
  if not dock then return end
  if modernWow then
    U.ModernWowMetalFrame(dock)
    return
  end
  if not dock.uuiSocialFlatDock then
    dock.uuiSocialFlatDock = true
    U.CreateBackdrop(dock, { background = { 0.01, 0.01, 0.01, 0.82 } })
  end
end

-- The Friends/Ignore toggle run starts on its list's left edge. Under Modern
-- WoW the list begins under the portrait ring, so the run is pushed right
-- until it clears the ring (M.modernWow.social.ringRight + ringGap). Measured
-- from live bounds, so it runs again on every show; an unmeasured window
-- keeps the list-edge placement until then.
local function PlaceToggleTabs(tabName, scroll)
  local tab = G(tabName)
  if not tab or not scroll then return end
  local x = 0
  if modernWow and frame then
    local token = M.modernWow.social
    local okF, frameLeft = pcall(frame.GetLeft, frame)
    local okS, scrollLeft = pcall(scroll.GetLeft, scroll)
    if okF and okS and tonumber(frameLeft) and tonumber(scrollLeft) then
      x = token.ringRight + token.ringGap - (scrollLeft - frameLeft)
      if x < 0 then x = 0 end
    end
  end
  local y = modernWow and M.modernWow.social.toggleY or 3
  Reposition(tab, "BOTTOMLEFT", scroll, "TOPLEFT", x, y)
end

-- ---------------------------------------------------------------------------
-- Friends tab (Friends list + Ignore sub-list)
-- ---------------------------------------------------------------------------
-- Each list owns its own pair of Friends/Ignore toggles, and the pair on
-- screen always names the list it sits on: Friends selected over the friend
-- list, Ignore over the ignore list. The shared tab group only follows clicks,
-- so a click on the pair being hidden left it showing the other list's tab as
-- selected when that list came back. Re-asserted whenever a list is shown.
local TOGGLE_ACTIVE = {
  FriendsFrameToggleTab1 = true,  FriendsFrameToggleTab2 = false,
  IgnoreFrameToggleTab1 = false,  IgnoreFrameToggleTab2 = true,
}

local function SyncToggleTabs()
  local name, active
  for name, active in pairs(TOGGLE_ACTIVE) do
    local tab = G(name)
    if tab and tab.SetActive then tab.SetActive(active) end
  end
end

-- Friend-row polish under the modern-wow surface only: a 1-unit gap between
-- stacked rows, and the row text nudged to sit centred on the resulting bar.
--
-- The rows themselves stay native. The only change is their own highlight
-- texture -- the hover art, which a click also locks on as the selection art
-- -- whose single CENTER anchor fills the whole 298x31 row, so consecutive
-- highlights meet with no seam. Re-anchoring it TOPLEFT/BOTTOMRIGHT with the
-- bottom edge lifted by `rowGap` separates them, and its right edge pushed
-- out by `rowExtend` covers the bare strip the narrower row leaves.
--
-- Why this is safe when knowledge.json
-- frames.friendsframe_row_touch_crashes_client says the opposite: that record
-- came from running the same re-anchor (plus row SetHeight) out of a
-- FriendsList_Update post-hook, and then a tick later, so it re-ran inside the
-- client's own list-update and selection path. Probe friendhighlight.v1
-- (2026-09-19, USER_CONFIRMED_INGAME) applied only the re-anchor, once, off
-- that path, to all ten rows: no failure, no crash, and selecting a friend
-- afterwards was fine. So this runs exactly once per row, never from a list
-- hook, and never touches row height.
--
-- The text nudge is the same one-shot, off-path treatment applied to the row's
-- own FontStrings. They are resolved by name, never by a region walk: a walked
-- region carries the readers but not the setters on this client
-- (knowledge.json widgets.region_walk_wrapper_lacks_setters), so a walk could
-- not move them anyway.
-- /urp interface FriendsFrameFriendButton1 (2026-09-19) gives the row as:
--   FriendsFrameFriendButton1                       Button   298x31
--     FriendsFrameFriendButton1ButtonText           Frame    298x31
--       ...ButtonTextNameLocation  FontString  "Ap - Scholomance"
--       ...ButtonTextInfo          FontString  "Level 59 Paladin"
-- Both lines live in that one child frame, so moving it moves them together
-- and each row takes a single touch instead of two.
local ROW_TEXTS = { "ButtonText" }

local function NudgeRowText(name)
  local text = G(name)
  if not text or text.uuiSocialRowTextY then return end
  local ok, count = pcall(text.GetNumPoints, text)
  if not ok or not count or count < 1 then return end
  text.uuiSocialRowTextY = true
  local points, i = {}, nil
  for i = 1, count do
    local got, point, relative, relativePoint, x, y = pcall(text.GetPoint, text, i)
    if got and point then
      table.insert(points, { point, relative, relativePoint, x or 0,
                             (y or 0) + M.modernWow.social.rowTextY })
    end
  end
  if table.getn(points) < 1 then return end
  pcall(function()
    text:ClearAllPoints()
    local p
    for p = 1, table.getn(points) do
      local entry = points[p]
      text:SetPoint(entry[1], entry[2], entry[3], entry[4], entry[5])
    end
  end)
end

-- Guild message box. GuildFrameNotesLabel / GuildFrameNotesText are regions
-- of GuildFrame, while the box's backdrop is drawn on GuildMOTDEditButton, a
-- child frame one level up -- so the backdrop drew OVER the text (user
-- reports 2026-09-20, first under modern-wow and then under `modern`, which
-- is why this runs under every theme: the flat InsetBox fill covers the same
-- regions the themed one did). A region cannot be lifted above a
-- child frame, so addon-owned copies sit on a mouse-transparent overlay above
-- the button and the natives are hidden; the copy re-reads the native text
-- after every roster update (GuildStatus_Update) and on each style pass.
-- `pad`: the copy's inset inside the box on every side (user, 2026-09-20:
-- 4 more than the native 4); `labelGap` the text's drop below the label.
local guildNotes = { pad = 8, labelGap = 17 }

-- One GuildFrame region redrawn on the notes overlay, so it draws at the same
-- level as the toggle's own "Show Player Status" label instead of under the
-- message box's backdrop (user, 2026-09-20). The copy takes the region's own
-- anchors, so whichever branch placed the native still decides where it sits.
--
-- `swapFrom`/`swapTo` retarget one anchor: "(n online)" hangs off
-- GuildFrameTotals, and mirroring it verbatim pointed the copy at a native
-- this function had just hidden, which is why the count disappeared on the
-- first attempt. It is chained to the totals COPY instead.
local function MirrorGuildRegion(key, region, swapFrom, swapTo)
  local overlay = guildNotes.overlay
  if not overlay or not region then return nil end
  local copy = guildNotes[key]
  if not copy then
    copy = overlay:CreateFontString(nil, "OVERLAY")
    if not copy then return nil end
    guildNotes[key] = copy
    SetTextFont(copy, M.fontSize.small, WHITE)
  end

  local placed = false
  pcall(function()
    local count = region:GetNumPoints()
    if not count or count < 1 then return end
    copy:ClearAllPoints()
    local i
    for i = 1, count do
      local point, relative, relativePoint, x, y = region:GetPoint(i)
      if swapFrom and swapTo and relative == swapFrom then relative = swapTo end
      copy:SetPoint(point, relative or overlay, relativePoint, x or 0, y or 0)
      placed = true
    end
    if region.GetJustifyH then copy:SetJustifyH(region:GetJustifyH() or "LEFT") end
    copy:SetText(region:GetText() or "")
  end)

  -- The native is hidden only once its copy is actually on screen, so a
  -- failed mirror leaves the client's own text visible rather than nothing.
  if placed then
    pcall(region.Hide, region)
    pcall(copy.Show, copy)
  else
    pcall(copy.Hide, copy)
  end
  return placed and copy or nil
end

local function SyncGuildNotes()
  local motd = G("GuildMOTDEditButton")
  local label, text = G("GuildFrameNotesLabel"), G("GuildFrameNotesText")
  if not motd or not label or not text then return end
  if not guildNotes.overlay then
    local ok, overlay = pcall(CreateFrame, "Frame", nil, motd)
    if not ok or not overlay then return end
    pcall(overlay.SetAllPoints, overlay, motd)
    pcall(overlay.EnableMouse, overlay, false)
    pcall(overlay.SetFrameLevel, overlay, motd:GetFrameLevel() + 1)
    guildNotes.overlay = overlay
    guildNotes.label = overlay:CreateFontString(nil, "OVERLAY")
    guildNotes.text = overlay:CreateFontString(nil, "OVERLAY")
    SetTextFont(guildNotes.label, M.fontSize.small, headingColor)
    SetTextFont(guildNotes.text, M.fontSize.small, WHITE)
    pcall(function()
      local pad = guildNotes.pad
      guildNotes.label:SetPoint("TOPLEFT", overlay, "TOPLEFT", pad, -pad)
      guildNotes.label:SetJustifyH("LEFT")
      guildNotes.text:SetPoint("TOPLEFT", overlay, "TOPLEFT", pad,
                               -(pad + guildNotes.labelGap))
      guildNotes.text:SetJustifyH("LEFT")
      if guildNotes.text.SetJustifyV then guildNotes.text:SetJustifyV("TOP") end
    end)
  end
  -- Two corner anchors did not bound the copy: it ran past the box on one
  -- line (user report 2026-09-20). An explicit width/height from the box's
  -- live size is what makes a FontString wrap and clip here.
  pcall(function()
    local width, height = motd:GetWidth(), motd:GetHeight()
    local pad = guildNotes.pad
    local w = width and width - pad * 2
    local h = height and height - (pad * 2 + guildNotes.labelGap)
    if w and w > 0 then guildNotes.text:SetWidth(w) end
    if h and h > 0 then guildNotes.text:SetHeight(h) end
    guildNotes.label:SetText(label:GetText() or "")
    guildNotes.text:SetText(text:GetText() or "")
  end)
  pcall(label.Hide, label)
  pcall(text.Hide, text)

  -- "n Guild Members" / "(n online)" are GuildFrame regions too, so the box's
  -- backdrop covers them the same way. Mirrored onto this overlay, with the
  -- online count chained to the totals copy rather than to the hidden native.
  local totalsRegion = G("GuildFrameTotals")
  local totalsCopy = MirrorGuildRegion("totals", totalsRegion)
  MirrorGuildRegion("online", G("GuildFrameOnlineTotals"),
                    totalsRegion, totalsCopy)
end

-- Each friend row's highlight ends at an addon-owned 1x1 "stop" frame
-- instead of the row's own corner, so its width can follow the scrollbar
-- (user request 2026-09-20: stop at the scrollbar's track when the list
-- scrolls, full width when it does not). The row's texture is still
-- re-anchored exactly ONCE (the safe pattern of knowledge.json
-- frames.friendsframe_row_highlight_reanchor_once_safe); later width changes
-- move only the stop frames, which are ours, so no row is touched again.
-- Until the first PlaceRowStops the stops have no points and the highlight
-- simply does not draw.
local rowStops = {}

local function RowGap()
  if not modernWow then return end
  local count = tonumber(FRIENDS_TO_DISPLAY) or 10
  local i
  for i = 1, count do
    local row = G("FriendsFrameFriendButton" .. i)
    if row and not row.uuiSocialRowGap then
      -- Marked before the call: if this ever does fault, a later style pass
      -- must not repeat it on the same row.
      row.uuiSocialRowGap = true
      local ok, texture = pcall(row.GetHighlightTexture, row)
      local okS, stop = false, nil
      if panel then okS, stop = pcall(CreateFrame, "Frame", nil, panel) end
      if ok and texture and okS and stop then
        pcall(stop.EnableMouse, stop, false)
        pcall(stop.SetWidth, stop, 1)
        pcall(stop.SetHeight, stop, 1)
        rowStops[i] = stop
        pcall(function()
          texture:ClearAllPoints()
          texture:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
          texture:SetPoint("BOTTOMRIGHT", stop, "BOTTOMRIGHT", 0, 0)
        end)
      end
      local t
      for t = 1, table.getn(ROW_TEXTS) do
        NudgeRowText("FriendsFrameFriendButton" .. i .. ROW_TEXTS[t])
      end
    end
  end
end

-- A Social list's native track art: two textures on the scroll frame itself
-- (Interface/PaperDollInfoFrame/UI-Character-ScrollBar, a 31x256 top and a
-- 31x106 bottom cap, BACKGROUND). RUNTIME_PROBE 2026-09-19 (/urp interface
-- WhoListScrollFrame): a walked one returns NO GetTexture(); its GetName() is
-- the path plus an address, so it is matched by name, and split by height.
-- They hang off the scroll frame, not the bar, so they do not follow a moved
-- bar or a footer/header band. A walked region has no reliable writers
-- (knowledge.json widgets.region_walk_wrapper_lacks_setters): each is moved
-- through the global of its own name, else hidden (Hide is honoured) and an
-- owned copy drawn. Anchors/texcoords: 1.12 FriendsFrame.xml (WORKING_SOURCE).
local TRACK = {
  path = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar",
  bottom = { point = "BOTTOMLEFT", relative = "BOTTOMRIGHT", x = -2, y = -2,
             width = 31, height = 106,
             coords = { 0.515625, 1.0, 0, 0.4140625 } },
  top = { point = "TOPLEFT", relative = "TOPRIGHT", x = -2,
          width = 31, height = 256, coords = { 0, 0.484375, 0, 1.0 } },
}

-- `anchor` (optional) = { frame, point, x }: attach the piece to another
-- frame (the scrollbar) instead of the scroll frame, so it follows it.
local function PlaceTrackPiece(scroll, region, spec, y, anchor)
  local function Anchor(piece)
    piece:ClearAllPoints()
    if anchor then
      piece:SetPoint(spec.point, anchor.frame, anchor.point, anchor.x, y)
    else
      piece:SetPoint(spec.point, scroll, spec.relative, spec.x, y)
    end
  end
  local real = U.G(region.name)
  if type(real) == "table" and type(real.SetPoint) == "function" and
     pcall(Anchor, real) then
    return real
  end
  local ok, piece = pcall(scroll.CreateTexture, scroll, nil, "BACKGROUND")
  if not ok or not piece then return nil end
  local c = spec.coords
  pcall(function()
    piece:SetTexture(TRACK.path)
    piece:SetTexCoord(c[1], c[2], c[3], c[4])
    piece:SetWidth(spec.width)
    piece:SetHeight(spec.height)
    Anchor(piece)
  end)
  pcall(region.object.Hide, region.object)
  return piece
end

-- The two track pieces of `scroll`, as { object, name } by "top"/"bottom".
local function FindTrackPieces(scroll)
  local found = {}
  local ok, regions = pcall(function() return { scroll:GetRegions() } end)
  if not ok or type(regions) ~= "table" then return found end
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    if region then
      local okN, name = pcall(region.GetName, region)
      local okH, height = pcall(region.GetHeight, region)
      if okN and type(name) == "string" and
         string.find(string.lower(name), "ui%-character%-scrollbar") and
         okH and tonumber(height) then
        found[height < 200 and "bottom" or "top"] = { object = region, name = name }
      end
    end
  end
  return found
end

-- The dark section the four actions sit on, with the theme's metal rule
-- between it and the friend list. Modern WoW only; the flat designs keep the
-- buttons on the window's own surface.
--
-- The plate wraps the run by anchoring to its two corner buttons rather than
-- to a measured rectangle, so it follows M.modernWow.social.footerButton's
-- width/x/y/pull without a second set of numbers to keep in step. It is
-- addon-owned, parented to the addon panel, kept below the native buttons and
-- takes no mouse input (rules/unreal-ui-design.md layering).
-- The plate is up on every tab; on the Who tab its top reaches `whoGrow`
-- higher. Only the anchors change, so nothing is read back from the plate.
local function PlaceFooterPlate()
  local plate = panel and panel.uuiSocialFooterPlate
  if not plate or not plate.uuiFirst or not plate.uuiLast then return end
  local token = M.modernWow.social.footerPlate

  -- Raid tab (user request 2026-09-20): no footer plate there, and its two
  -- top buttons (Convert to Raid, Raid Info) sit `raidButtonsDrop` lower.
  -- Names WORKING_SOURCE (UnrealPfUI's friends skin on this client). Each
  -- button is re-anchored once from its own offset against the shown raid
  -- frame. The plate is shown again on every other tab.
  local raid = G("RaidFrame")
  local okR, raidShown = false, false
  if raid then okR, raidShown = pcall(raid.IsVisible, raid) end
  if okR and raidShown then
    pcall(plate.Hide, plate)
    local drop = token.raidButtonsDrop or 0
    local names = { "RaidFrameConvertToRaidButton", "RaidFrameRaidInfoButton" }
    local i
    for i = 1, table.getn(names) do
      local button = G(names[i])
      if button and drop ~= 0 and not button.uuiRaidDropped then
        pcall(function()
          local top, left = button:GetTop(), button:GetLeft()
          local rTop, rLeft = raid:GetTop(), raid:GetLeft()
          if top and left and rTop and rLeft then
            button.uuiRaidDropped = true
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", raid, "TOPLEFT", left - rLeft,
                            top - rTop - drop)
          end
        end)
      end
    end
    return
  end
  pcall(plate.Show, plate)
  local grow = 0
  local who = G("WhoFrame")
  if who then
    local ok, shown = pcall(who.IsVisible, who)
    if ok and shown then grow = token.whoGrow or 0 end
  end
  -- Guild tab: the plate's top instead hangs off the Guild action row, so its
  -- rule's lower edge sits `guildGap` above those buttons (user request
  -- 2026-09-20; the rule is centred on the plate's top edge and reaches
  -- `ruleHalf` below it). Its left edge is kept by reading its own current
  -- x -- a shown frame -- and the bottom edge is unchanged.
  local guild, info = G("GuildFrame"), G("GuildFrameGuildInformationButton")
  local okV, guildShown = false, false
  if guild then okV, guildShown = pcall(guild.IsVisible, guild) end
  if okV and guildShown and info then
    local placed = pcall(function()
      local left, infoLeft = plate:GetLeft(), info:GetLeft()
      if not left or not infoLeft then error("no geometry") end
      local ruleHalf = M.modernWow.social.headerPlate.ruleHalf
      plate:ClearAllPoints()
      plate:SetPoint("TOPLEFT", info, "TOPLEFT", left - infoLeft,
                     token.guildGap + ruleHalf)
      plate:SetPoint("BOTTOMRIGHT", plate.uuiLast, "BOTTOMRIGHT",
                     token.padX, -token.padBottom -
                     (M.modernWow.social.footerButton.raise or 0))
    end)
    if placed then return end
  end

  -- The Friends buttons were raised by footerButton.raise; the plate does
  -- not follow them.
  local raise = M.modernWow.social.footerButton.raise or 0
  pcall(function()
    plate:ClearAllPoints()
    plate:SetPoint("TOPLEFT", plate.uuiFirst, "TOPLEFT", -token.padX,
                   token.padTop + grow - raise)
    plate:SetPoint("BOTTOMRIGHT", plate.uuiLast, "BOTTOMRIGHT",
                   token.padX, -token.padBottom - raise)
  end)
end

local function FooterPlate(first, last)
  if not modernWow or not first or not last or not panel then return end
  local plate = panel.uuiSocialFooterPlate
  if not plate then
    -- Named so a focused probe can read its geometry and layering.
    local ok, created = pcall(CreateFrame, "Frame",
                              "UnrealUISocialFooterPlate", panel)
    if not ok or not created then return end
    plate = created
    panel.uuiSocialFooterPlate = plate
    pcall(plate.EnableMouse, plate, false)
  end

  -- Level taken from the buttons, not from the panel: the theme's window art
  -- sits above the panel, so a panel+1 plate was drawn under the artwork and
  -- never showed. One below the buttons keeps it over the art and under the
  -- controls it backs.
  local levelOk, level = pcall(first.GetFrameLevel, first)
  if not levelOk or not tonumber(level) then
    levelOk, level = pcall(panel.GetFrameLevel, panel)
    if levelOk and tonumber(level) then level = level + 1 end
  end
  if tonumber(level) then
    pcall(plate.SetFrameLevel, plate, math.max(0, level - 1))
  end

  plate.uuiFirst, plate.uuiLast = first, last
  PlaceFooterPlate()
  U.ModernWowSocialFooterPlate(plate)
  pcall(plate.Show, plate)

  -- The friend list's scroll channel runs down to the footer's top edge, so
  -- no bare strip of window art is left between the two.
  --
  -- Both corners stay on the scrollbar and the drop below it is a measured
  -- number, rather than anchoring the channel's bottom to the plate: the
  -- plate is the buttons' own wrapper, and a live cross-frame anchor onto it
  -- left the channel short. Measured a tick later, once this pass's
  -- repositioning has settled.
  local bed = plate.uuiSocialFooterBed
  if not bed then
    local bar = G("FriendsFrameFriendsScrollFrameScrollBar")
    bed = bar and bar.uuiModernWowProgressBackground
    if not bed then return end
    plate.uuiSocialFooterBed = bed
    plate.uuiSocialFooterBar = bar
  end
  DeferOnce("footer-bed", function()
    local bar = plate.uuiSocialFooterBar
    if not bar then return end
    local okBottom, barBottom = pcall(bar.GetBottom, bar)
    local okTop, plateTop = pcall(plate.GetTop, plate)
    barBottom = okBottom and tonumber(barBottom)
    plateTop = okTop and tonumber(plateTop)
    if not barBottom or not plateTop then return end
    local pad = M.modernWow.social.scrollBed.padding

    -- The arrow buttons sit outside the Slider's own rect, so the channel
    -- has to be lifted over the up arrow the way the measured drop already
    -- carries it down past the down arrow -- otherwise only one end of the
    -- bar has the dark backing behind it.
    --
    -- The arrow's NATIVE offsets are measured once and kept, so the lift
    -- does not change when the arrow itself is moved below.
    local lift = pad
    local up = G("FriendsFrameFriendsScrollFrameScrollBarScrollUpButton")
    if up and not plate.uuiUpNative then
      pcall(function()
        local barTop, barLeft, barRight = bar:GetTop(), bar:GetLeft(), bar:GetRight()
        local upTop, upBottom = up:GetTop(), up:GetBottom()
        local upLeft, upRight = up:GetLeft(), up:GetRight()
        if barTop and barLeft and barRight and upTop and upBottom and
           upLeft and upRight then
          local native = {
            lift = upTop - barTop, y = upBottom - barTop,
            x = (upLeft + upRight) / 2 - (barLeft + barRight) / 2,
          }
          -- The bar's own edges against its scroll frame, and the down
          -- arrow's offset from the bar, for the thumb-range move below.
          local list = G("FriendsFrameFriendsScrollFrame")
          local down = G("FriendsFrameFriendsScrollFrameScrollBarScrollDownButton")
          local sTop, sBottom = list and list:GetTop(), list and list:GetBottom()
          local sRight = list and list:GetRight()
          local barBottom0 = bar:GetBottom()
          local dTop = down and down:GetTop()
          local dLeft, dRight = down and down:GetLeft(), down and down:GetRight()
          if sTop and sBottom and sRight and barBottom0 and dTop and dLeft and
             dRight then
            native.bar = { x = barLeft - sRight, top = barTop - sTop,
                           bottom = barBottom0 - sBottom }
            native.down = { x = (dLeft + dRight) / 2 - (barLeft + barRight) / 2,
                            y = dTop - barBottom0 }
          end
          plate.uuiUpNative = native
        end
      end)
    end
    local native = plate.uuiUpNative
    if native and native.lift > 0 then lift = native.lift end

    -- The thumb travels inside the bar's own rect, so its end stops move
    -- with the bar's edges: the top edge `friendsThumbTop` and the bottom
    -- edge `friendsThumbBottom` lower (user, 2026-09-20). Both arrows are
    -- re-placed against the moved edges so they land where asked, and the
    -- channel is corrected by the same amounts below.
    local sb = M.modernWow.social.scrollBed
    local topDrop, bottomDrop = 0, 0
    local list = G("FriendsFrameFriendsScrollFrame")
    if native and native.bar and list then
      topDrop, bottomDrop = sb.friendsThumbTop or 0, sb.friendsThumbBottom or 0
      pcall(function()
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", list, "TOPRIGHT", native.bar.x,
                     native.bar.top - topDrop)
        bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", native.bar.x,
                     native.bar.bottom - bottomDrop)
      end)
      local okLB, listBottom = pcall(list.GetBottom, list)
      if okLB and tonumber(listBottom) then
        barBottom = listBottom + native.bar.bottom - bottomDrop
      end
      local down = G("FriendsFrameFriendsScrollFrameScrollBarScrollDownButton")
      if down and native.down then
        -- Rides the bottom edge's drop, then `friendsDownY` more in total.
        pcall(function()
          down:ClearAllPoints()
          down:SetPoint("TOP", bar, "BOTTOM", native.down.x,
                        native.down.y + bottomDrop - (sb.friendsDownY or 0))
        end)
      end
    end

    -- The up arrow alone sits `friendsUpY` higher (user, 2026-09-20),
    -- measured from its native place, not from the lowered top edge.
    if up and native then
      pcall(function()
        up:ClearAllPoints()
        up:SetPoint("BOTTOM", bar, "TOP", native.x,
                    native.y + topDrop + (sb.friendsUpY or 0))
      end)
    end

    pcall(function()
      -- The whole channel then sits `friendsBedY` higher (user, 2026-09-20).
      local up5 = M.modernWow.social.scrollBed.friendsBedY or 0
      bed:ClearAllPoints()
      -- Its top edge alone then moves by `friendsBedTopY` (negative: down).
      bed:SetPoint("TOPLEFT", bar, "TOPLEFT", -pad,
                   lift + topDrop + up5 +
                   (M.modernWow.social.scrollBed.friendsBedTopY or 0))
      -- ...and its bottom edge alone by `friendsBedBottomY` (negative: down).
      bed:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad,
                   plateTop - barBottom + up5 +
                   (M.modernWow.social.scrollBed.friendsBedBottomY or 0))
    end)

    -- The list's native track bottom cap hung below the down arrow into the
    -- footer (user report 2026-09-20): it now ends just above the plate's
    -- rule, which is centred on the plate's top edge. Once, on success.
    local list = G("FriendsFrameFriendsScrollFrame")
    if list and not list.uuiTrackCapPlaced then
      local okB, listBottom = pcall(list.GetBottom, list)
      listBottom = okB and tonumber(listBottom)
      local found = listBottom and FindTrackPieces(list) or {}
      if found.bottom then
        local ruleHalf = M.modernWow.social.headerPlate.ruleHalf
        if PlaceTrackPiece(list, found.bottom, TRACK.bottom,
                           plateTop + ruleHalf - listBottom) then
          list.uuiTrackCapPlaced = true
        end
      end
    end
  end)
end

-- Footer action availability: Add Friend is always live, Remove Friend needs a
-- selected friend, and Send Message / Group Invite need that friend to be
-- online as well.
--
-- Polled on the shared driver rather than hooked. Selecting a row fires no
-- event at all, and a FriendsList_Update post-hook is the exact pattern that
-- crashed this window before (knowledge.json
-- frames.friendsframe_row_touch_crashes_client), so nothing here attaches to
-- the client's list update.
--
-- Under modern-wow the red/grey face follows on its own: the atlas skin reads
-- button:IsEnabled() and the Enable/Disable wrappers above repaint it a tick
-- later. Under the flat themes the label is dimmed here instead.
local FOOTER_INTERVAL = 0.2

-- The selection comes from GetSelectedFriend(), the client's own documented
-- accessor (1-based, 0 when nothing is selected), NOT from
-- FriendsFrame.selectedFriend. RUNTIME_PROBE friendhighlight (2026-09-19)
-- sampled that field with an online friend selected and again with an offline
-- one: it read 2 both times, so it does not follow the clicked row on this
-- client and every button downstream of it was answering about the wrong
-- friend. The field is kept only as a fallback if the accessor is missing.
--
-- GetFriendInfo -> name, level, class, area, connected. The same probe
-- confirmed the 5th return is a real boolean here ("Ap" true / the rest
-- false), matching UnrealPfUI's use of it on this client.
local function SelectedFriend()
  local index = 0
  if type(GetSelectedFriend) == "function" then
    local ok, value = pcall(GetSelectedFriend)
    if ok then index = tonumber(value) or 0 end
  end
  if index < 1 then
    local window = G("FriendsFrame")
    index = (window and tonumber(window.selectedFriend)) or 0
  end
  if index < 1 then return 0, false end
  local countOk, count = pcall(GetNumFriends)
  if not countOk or index > (tonumber(count) or 0) then return 0, false end
  local infoOk, _, _, _, _, connected = pcall(GetFriendInfo, index)
  return index, (infoOk and connected) and true or false
end

-- The live state is read back from the button instead of being cached here,
-- so a native Enable/Disable between polls cannot leave the face out of step.
local function SetFooterEnabled(button, enabled)
  if not button then return end
  enabled = enabled and true or false
  local current
  if button.IsEnabled then
    local ok, value = pcall(button.IsEnabled, button)
    if ok then current = (value == true or value == 1) end
  end
  if current == enabled then return end
  if enabled then
    pcall(button.Enable, button)
  else
    pcall(button.Disable, button)
  end
  if not modernWow then
    local ok, label = pcall(button.GetFontString, button)
    if ok and label then
      SetTextFont(label, M.fontSize.normal, enabled and WHITE or DIM)
    end
  end
end

-- The red/grey face only repaints when Enable/Disable is called through the
-- wrappers above. The client also flips these controls on its own -- selecting
-- an offline friend leaves Send Message and Group Invite reporting IsEnabled 0
-- without any Lua call this module can see -- and the face is then left on the
-- red cell over a dead button. So the drawn state is compared with the live
-- one here and the skin is restyled only when they disagree.
local function SyncFooterFace(button)
  if not modernWow or not button then return end
  local skin = button.uuiModernWowActionButton
  local face = type(skin) == "table" and skin.cover
  local paint = face and face.uuiModernWowAction
  if type(paint) ~= "table" then return end

  local enabled = true
  if button.IsEnabled then
    -- IsEnabled returns 1/0 here, not a boolean (RUNTIME_PROBE 2026-09-19,
    -- knowledge.json frames.friendsframe_selectedfriend_field_is_stale).
    local ok, value = pcall(button.IsEnabled, button)
    if ok then enabled = (value == true or value == 1) end
  end
  if paint.disabled == (not enabled) then return end
  U.StyleModernWowActionButton(button)
end

-- Moves the stop frames (see RowGap): the highlight's right edge is the
-- row's right plus `rowExtend` while the scrollbar is hidden, and the list
-- track's left edge (its art starts 2 left of the scroll frame's right,
-- TRACK) while it is shown. Bottom stays the row's bottom plus `rowGap`.
-- Bounded numbers read from shown frames; re-run only when the scrollbar's
-- visibility flips or a row was not yet measurable.
local function PlaceRowStops()
  if not modernWow then return end
  local scroll = G("FriendsFrameFriendsScrollFrame")
  local bar = G("FriendsFrameFriendsScrollFrameScrollBar")
  if not scroll or not bar then return end
  local okV, barShown = pcall(bar.IsVisible, bar)
  barShown = okV and barShown and true or false
  if rowStops.done and rowStops.barShown == barShown then return end

  local social = M.modernWow.social
  local okG, sLeft, sTop, sRight = pcall(function()
    return scroll:GetLeft(), scroll:GetTop(), scroll:GetRight()
  end)
  if not okG or not sLeft or not sTop or not sRight then return end

  local done = true
  local i
  for i = 1, tonumber(FRIENDS_TO_DISPLAY) or 10 do
    local stop = rowStops[i]
    local row = G("FriendsFrameFriendButton" .. i)
    if stop and row then
      local okR, right, bottom = pcall(function()
        return row:GetRight(), row:GetBottom()
      end)
      if okR and right and bottom then
        local x = barShown and (sRight + TRACK.top.x - sLeft) or
                               (right + social.rowExtend - sLeft)
        pcall(function()
          stop:ClearAllPoints()
          stop:SetPoint("BOTTOMRIGHT", scroll, "TOPLEFT", x,
                        bottom + social.rowGap - sTop)
        end)
      else
        done = false
      end
    end
  end
  rowStops.done, rowStops.barShown = done, barShown
end

local function RefreshFooter()
  local window = G("FriendsFrame")
  if not window then return end
  local visibleOk, visible = pcall(window.IsVisible, window)
  if not visibleOk or not visible then return end

  PlaceRowStops()

  local index, online = SelectedFriend()
  local selected = index > 0
  local buttons = {
    { G("FriendsFrameAddFriendButton"), true },
    { G("FriendsFrameRemoveFriendButton"), selected },
    { G("FriendsFrameSendMessageButton"), selected and online },
    { G("FriendsFrameGroupInviteButton"), selected and online },
  }
  local i
  for i = 1, table.getn(buttons) do
    SetFooterEnabled(buttons[i][1], buttons[i][2])
    SyncFooterFace(buttons[i][1])
  end

  -- The Who footer has the same stale face: the client enables Add Friend
  -- and Group Invite on its own when a row is selected, so they stayed grey
  -- until a hover repainted them. Their enabled state stays native-owned;
  -- only the face is brought in line.
  SyncFooterFace(G("WhoFrameAddFriendButton"))
  SyncFooterFace(G("WhoFrameGroupInviteButton"))

  -- Same for the Guild tab: the client disables its actions by guild rank
  -- (Add Member, Guild Control, the member dock's Remove / Group Invite)
  -- without a call this module sees, so the red face stayed on a dead
  -- button. It now shows the grey disabled face (user request 2026-09-20).
  local guild = {
    "GuildFrameGuildInformationButton", "GuildFrameAddMemberButton",
    "GuildFrameControlButton", "GuildMemberRemoveButton",
    "GuildMemberGroupInviteButton",
  }
  local g
  for g = 1, table.getn(guild) do
    SyncFooterFace(G(guild[g]))
  end
end

local function StyleFriendsSubTab()
  local scroll = G("FriendsFrameFriendsScrollFrame")
  if not scroll then return end

  U.StyleStockTabGroup(
    { G("FriendsFrameToggleTab1"), G("FriendsFrameToggleTab2") }, 1)
  PlaceToggleTabs("FriendsFrameToggleTab1", scroll)
  local toggle2 = G("FriendsFrameToggleTab2")
  if toggle2 then
    Reposition(toggle2, "LEFT", G("FriendsFrameToggleTab1"), "RIGHT", 3, 0)
  end

  StyleList(scroll, "FriendsFrameFriendsScrollFrameScrollBar")

  RowGap()

  -- Modern WoW footer size (M.modernWow.social.footerButton). Set before the
  -- theme face is built, so its end caps take their aspect from this height.
  local width, shift, drop, pull = 158, 0, 0, 0
  if modernWow then
    local token = M.modernWow.social.footerButton
    width, shift, drop, pull = token.width, token.x, token.y, token.pull
    local names = {
      "FriendsFrameAddFriendButton", "FriendsFrameRemoveFriendButton",
      "FriendsFrameSendMessageButton", "FriendsFrameGroupInviteButton",
    }
    local i
    for i = 1, table.getn(names) do
      local button = G(names[i])
      if button and not button.uuiSocialFooterSized then
        button.uuiSocialFooterSized = true
        local ok, height = pcall(button.GetHeight, button)
        if ok and tonumber(height) and height > 0 then
          pcall(button.SetHeight, button, height + token.heightGrow)
        end
      end
    end
  end

  local add = ActionButton(G("FriendsFrameAddFriendButton"))
  -- Remove Friend is a normal action button again. USER_CONFIRMED_INGAME
  -- 2026-09-19: removing a friend no longer crashes this client, so the
  -- cleared OnClick, the pinned disabled face and the inert input shield that
  -- knowledge.json frames.friendsframe_row_touch_crashes_client called for are
  -- all gone and the native control owns its own click path again.
  local remove = ActionButton(G("FriendsFrameRemoveFriendButton"))
  local message = ActionButton(G("FriendsFrameSendMessageButton"))
  local invite = ActionButton(G("FriendsFrameGroupInviteButton"))

  -- The right column hangs off the scrollbar's down arrow, which Modern WoW
  -- lowers by `friendsDownY` (scrollBed), and it dragged Send Message and
  -- Group Invite down with it. That drop is cancelled on the right column and
  -- the two columns meet halfway (user request 2026-09-20): the left one
  -- half of it lower, the right one half of it higher than its old place.
  local leftY, rightY = 0, 0
  if modernWow then
    local downY = M.modernWow.social.scrollBed.friendsDownY or 0
    leftY, rightY = -downY / 2, downY - downY / 2
    -- Both columns then sit `raise` higher (user, 2026-09-20); the footer
    -- plate, which hangs off these buttons, takes the same amount back in
    -- PlaceFooterPlate so it stays where it is on every tab.
    local raise = M.modernWow.social.footerButton.raise or 0
    leftY, rightY = leftY + raise, rightY + raise
  end

  if add then
    pcall(add.SetWidth, add, width)
    Reposition(add, "TOPLEFT", scroll, "BOTTOMLEFT", shift + pull,
               -6 + drop + leftY)
  end
  if remove and add then
    pcall(remove.SetWidth, remove, width)
    Reposition(remove, "TOP", add, "BOTTOM", 0, -4)
  end
  if message then
    pcall(message.SetWidth, message, width)
    local down = G("FriendsFrameFriendsScrollFrameScrollBarScrollDownButton")
    Reposition(message, "TOPRIGHT", down or scroll, "BOTTOMRIGHT", shift - pull,
               -6 + drop + rightY)
  end
  if invite and message then
    pcall(invite.SetWidth, invite, width)
    Reposition(invite, "TOP", message, "BOTTOM", 0, -4)
  end

  FooterPlate(add, invite)
end

local function StyleIgnoreSubTab()
  local scroll = G("FriendsFrameIgnoreScrollFrame")
  if not scroll then return end

  U.StyleStockTabGroup(
    { G("IgnoreFrameToggleTab1"), G("IgnoreFrameToggleTab2") }, 2)
  PlaceToggleTabs("IgnoreFrameToggleTab1", scroll)
  local toggle2 = G("IgnoreFrameToggleTab2")
  if toggle2 then
    Reposition(toggle2, "LEFT", G("IgnoreFrameToggleTab1"), "RIGHT", 3, 0)
  end

  StyleList(scroll, "FriendsFrameIgnoreScrollFrameScrollBar")

  -- Ignore rows left fully native, same reasoning as the Friends list above.

  local ignore = ActionButton(G("FriendsFrameIgnorePlayerButton"))
  local stop = ActionButton(G("FriendsFrameStopIgnoreButton"))
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
--
-- Headers and row fields are laid out from this one spec, left-justified, so
-- each header label starts exactly over its column. `x` is from the row's
-- left edge; WhoFrameButton1 sits 5 left of the scroll frame (StyleWhoTab).
local whoCols = {
  rowToScroll = -5,
  gap = 10,
  level = { x = 16, width = 22 },  -- user: +6 right; width 30 -40% +20%
  class = { width = 36 },  -- user: +20% (was 30)
  name = { width = 105 },
  nameHeaderX = -5,
}

local function LeftText(object)
  if object and object.SetJustifyH then
    pcall(object.SetJustifyH, object, "LEFT")
  end
end

-- A header's label is pinned to the header's left edge, so the header's
-- position is the label's position.
local function PinHeaderLabel(header)
  if not header or not header.GetFontString then return end
  local ok, label = pcall(header.GetFontString, header)
  if not ok or not label then return end
  Reposition(label, "LEFT", header, "LEFT", 0, 0)
  LeftText(label)
end

-- The header's native hover highlight is anchored to its stock Left/Right
-- caps, which keep their template widths after the header is narrowed, so the
-- blue glow ran past the column. Pinned to the header's own bounds instead.
-- The button's OWN highlight (GetHighlightTexture), re-anchored once from the
-- build path -- the pattern knowledge.json
-- frames.friendsframe_row_highlight_reanchor_once_safe records as safe.
local function FitHeaderHighlight(header)
  if not header or not header.GetHighlightTexture then return end
  local ok, glow = pcall(header.GetHighlightTexture, header)
  if not ok or not glow then return end
  pcall(function()
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  end)
end

local function StyleWhoHeaders(scroll)
  local level = G("WhoFrameColumnHeader3")
  local class = G("WhoFrameColumnHeader4")
  local name = G("WhoFrameColumnHeader1")
  local zone = G("WhoFrameColumnHeader2")
  local c = whoCols

  local headers = { level, class, name, zone }
  local i
  for i = 1, table.getn(headers) do
    local header = headers[i]
    if header then
      U.StripStockTextures(header)
      SetTextFont(header, M.fontSize.small, headingColor)
      PinHeaderLabel(header)
      FitHeaderHighlight(header)
    end
  end

  if level then
    pcall(level.SetWidth, level, c.level.width)
    Reposition(level, "BOTTOMLEFT", scroll, "TOPLEFT",
               c.rowToScroll + c.level.x, 4)
  end
  if class and level then
    pcall(class.SetWidth, class, c.class.width)
    Reposition(class, "LEFT", level, "RIGHT", c.gap, 0)
  end
  if name and class then
    pcall(name.SetWidth, name, c.name.width)
    -- The Name header alone sits `nameHeaderX` left of its column (user,
    -- 2026-09-19); the rows keep the plain gap.
    Reposition(name, "LEFT", class, "RIGHT", c.gap + c.nameHeaderX, 0)
  end
  if zone and name then
    Reposition(zone, "LEFT", name, "RIGHT", c.gap - c.nameHeaderX, 0)
  end
end

-- Per-row fields follow the same spec as the headers above, and
-- WhoList_Update re-applies its own native anchors on every refresh -- so
-- this has to run again after every update, not just once at build time.
local function StyleWhoRows()
  local count = N("WHOS_TO_DISPLAY", 17)
  local c = whoCols
  local i
  for i = 1, count do
    local row = G("WhoFrameButton" .. i)
    local level = G("WhoFrameButton" .. i .. "Level")
    local class = G("WhoFrameButton" .. i .. "Class")
    local name = G("WhoFrameButton" .. i .. "Name")
    local zone = G("WhoFrameButton" .. i .. "Variable")

    if level and row then
      pcall(level.SetWidth, level, c.level.width)
      Reposition(level, "TOPLEFT", row, "TOPLEFT", c.level.x, -3)
      LeftText(level)
    end
    if class and level then
      pcall(class.SetWidth, class, c.class.width)
      Reposition(class, "LEFT", level, "RIGHT", c.gap, 0)
      LeftText(class)
    end
    if name and class then
      pcall(name.SetWidth, name, c.name.width)
      Reposition(name, "LEFT", class, "RIGHT", c.gap, 0)
      LeftText(name)
    end
    if zone and name then
      Reposition(zone, "LEFT", name, "RIGHT", c.gap, 0)
      LeftText(zone)
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
    if modernWow then
      local created, box = pcall(CreateFrame, "Frame",
                                 "UnrealUIWhoSearchBackdrop", scroll)
      if created and box then
        whoSearchBackdrop = box
        InsetBox(box)
      end
    end
    if not whoSearchBackdrop then
      whoSearchBackdrop = U.CreatePanel(scroll, {
        name = "UnrealUIWhoSearchBackdrop",
        width = 1,
        height = 1,
      })
    end
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
  -- WhoFrameEditBox is client-owned: a login bisection confirmed that
  -- visual/mouse mutation crashes the client, so only MoveWhoSearch re-anchors
  -- it, after the window is shown. The owned backdrop restores the compact search-field
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

  -- The row keeps the search field's width but is centred on the list span
  -- (scroll frame left to scrollbar right, plus the Friends footer's `x`), so
  -- it shares a centre with the Friends tab's footer. The shift is read as
  -- bounded numbers, never kept as an anchor on the native list; before the
  -- window is laid out it is 0 and the next deferred pass corrects it.
  local buttonAnchor = totals or anchor
  local dx = 0
  local bar = G("WhoListScrollFrameScrollBar")
  if modernWow and bar and scroll then
    pcall(function()
      local left, right = scroll:GetLeft(), bar:GetRight()
      local aLeft, aRight = anchor:GetLeft(), anchor:GetRight()
      if left and right and aLeft and aRight then
        dx = (left + right) / 2 - (aLeft + aRight) / 2 +
             M.modernWow.social.footerButton.x
      end
    end)
  end
  local y = modernWow and 0 or -5
  if who then
    Reposition(who, "TOPLEFT", buttonAnchor, "BOTTOMLEFT", dx, y)
  end
  if groupInvite then
    Reposition(groupInvite, "TOPRIGHT", buttonAnchor, "BOTTOMRIGHT", dx, y)
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

-- The search field is moved under the totals, centred on the list span and just
-- above the action row. USER_CONFIRMED_INGAME 2026-09-19 (knowledge.json
-- frames.whoframe_editbox_touch_crashes_login, now PARTIAL): re-anchoring
-- WhoFrameEditBox from a deferred pass after the window is shown does not
-- crash. This touches ONLY ClearAllPoints/SetPoint on it and never runs during
-- login; hiding it or changing its backdrop/mouse state is still forbidden.
--
-- Geometry is bounded numbers read once from the native layout (the search
-- field's old top-left, the action row's width) plus the live list span.
-- gapTotals: totals to field (user: field up 3 from 4). gapButtons: field to
-- the action row (user: row up 8 overall, 3 of it riding with the field).
-- capLift: the track's bottom cap rides this much higher (user, 2026-09-19).
-- downDrop: the scrollbar's down arrow alone sits this much lower.
-- trackTop: the track's top piece starts this far under the list's top edge
-- (the header band's rule reaches 3 into the list). arrowPad: the up arrow's
-- top below the track's top, as natively (track +5, arrow 0).
local whoMove = { gapTotals = 1, gapButtons = 1, capLift = 5, downDrop = 4,
                  trackTop = 3, arrowPad = 5 }

-- The Who list's native track art is two textures on the scroll frame itself
-- (Interface/PaperDollInfoFrame/UI-Character-ScrollBar: a 31x256 top and a
-- 31x106 bottom cap, BACKGROUND). RUNTIME_PROBE 2026-09-19
-- (/urp interface WhoListScrollFrame): both are there, and on this client a
-- walked one returns NO GetTexture(); its GetName() is the path plus an
-- address ("Interface/PaperDollInfoFrame/UI-Character-ScrollBar_0x..."), so
-- it is matched by name and height. They hang off the scroll frame, not the
-- bar, so the bottom cap stayed put when the bar moved.
--
-- A walked region has readers but no reliable writers (knowledge.json
-- widgets.region_walk_wrapper_lacks_setters): the cap is first exchanged for
-- the global of its own name and moved directly; failing that, it is hidden
-- (Hide is honoured on a walked region) and an owned copy drawn instead.
-- Anchor and texcoords are the 1.12 FriendsFrame.xml values (WORKING_SOURCE):
-- BOTTOMLEFT to the scroll frame's BOTTOMRIGHT at (-2, -2). Runs once.
-- Who: the bottom cap rides `capLift` higher; the top piece starts
-- `trackTop` under the list's top edge, below the header band's rule (it
-- natively hangs 5 ABOVE the list, into the header -- user report
-- 2026-09-20). Runs once.
local function LiftWhoTrackCap(scroll)
  if whoMove.cap ~= nil then return end
  whoMove.cap = false
  local found = FindTrackPieces(scroll)
  if found.bottom then
    whoMove.cap = PlaceTrackPiece(scroll, found.bottom, TRACK.bottom,
                                  TRACK.bottom.y + whoMove.capLift) or false
  end
  if found.top then
    whoMove.capTop = PlaceTrackPiece(scroll, found.top, TRACK.top,
                                     -whoMove.trackTop)
  end
end

local function MoveWhoSearch()
  if not modernWow or not whoSearchBackdrop then return end
  local edit = G("WhoFrameEditBox")
  local totals = G("WhoFrameTotals")
  local scroll = G("WhoListScrollFrame")
  local bar = G("WhoListScrollFrameScrollBar")
  local who = G("WhoFrameWhoButton")
  local invite = G("WhoFrameGroupInviteButton")
  local add = G("WhoFrameAddFriendButton")
  if not edit or not totals or not scroll or not bar or
     not who or not invite or not add then return end

  local ok = pcall(function()
    local sLeft, sBottom = scroll:GetLeft(), scroll:GetBottom()
    local bRight = bar:GetRight()
    if not sLeft or not sBottom or not bRight then error("no geometry") end

    -- First pass only, while everything is still in its old place.
    if not whoMove.top then
      local top, left = whoSearchBackdrop:GetTop(), whoSearchBackdrop:GetLeft()
      local rowLeft, rowRight = who:GetLeft(), invite:GetRight()
      if not top or not left or not rowLeft or not rowRight then
        error("no geometry")
      end
      whoMove.top = top - sBottom
      whoMove.left = left - sLeft
      whoMove.row = rowRight - rowLeft

      -- The list scrollbar's native edges against its scroll frame, measured
      -- rather than read with GetPoint (knowledge.json
      -- frames.getpoint_y_same_sign_as_setpoint).
      local sTop, sRight = scroll:GetTop(), scroll:GetRight()
      local barTop, barBottom, barLeft = bar:GetTop(), bar:GetBottom(),
                                         bar:GetLeft()
      if sTop and sRight and barTop and barBottom and barLeft then
        whoMove.bar = { x = barLeft - sRight, top = barTop - sTop,
                        bottom = barBottom - sBottom }
      end

      -- The up arrow's height above the bar's top, measured the same way.
      local upButton = G("WhoListScrollFrameScrollBarScrollUpButton")
      local uTop = upButton and upButton:GetTop()
      if uTop and barTop then whoMove.upOff = uTop - barTop end

      -- The down arrow's native offset from the bar, measured the same way.
      local down = G("WhoListScrollFrameScrollBarScrollDownButton")
      local dTop = down and down:GetTop()
      local dLeft, dRight = down and down:GetLeft(), down and down:GetRight()
      local bLeft, bRight = bar:GetLeft(), bar:GetRight()
      if dTop and dLeft and dRight and barBottom and bLeft and bRight then
        whoMove.down = { x = (dLeft + dRight) / 2 - (bLeft + bRight) / 2,
                         y = dTop - barBottom }
      end
    end

    LiftWhoTrackCap(scroll)

    -- The footer plate reaches `whoGrow` higher on this tab, so the whole
    -- scrollbar rides up by the same amount and its bottom still ends just
    -- above the plate. Same length, same handlers; only its two anchors.
    if whoMove.bar then
      local lift = M.modernWow.social.footerPlate.whoGrow or 0
      bar:ClearAllPoints()
      -- Its top instead starts under the header band: the up arrow's top
      -- keeps its native `arrowPad` below the track's (moved) top piece, and
      -- the channel follows the arrow (user, 2026-09-20).
      local top = whoMove.bar.top + lift
      if whoMove.upOff then
        top = -(whoMove.trackTop + whoMove.arrowPad) - whoMove.upOff
      end
      bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", whoMove.bar.x, top)
      bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", whoMove.bar.x,
                   whoMove.bar.bottom + lift)
    end

    -- Only the down arrow sits `downDrop` lower (user, 2026-09-19); the bar,
    -- its thumb range and the up arrow are unchanged.
    local down = G("WhoListScrollFrameScrollBarScrollDownButton")
    if down and whoMove.down then
      down:ClearAllPoints()
      down:SetPoint("TOP", bar, "BOTTOM", whoMove.down.x,
                    whoMove.down.y - whoMove.downDrop)
    end

    -- The channel behind the bar starts at the bar's own top, but the up
    -- arrow sits above that rect, so the channel's top edge cut across the
    -- arrow. Lift it over the arrow as the Friends list does (FooterPlate).
    -- The arrow hangs off the bar, so the difference survives the move above.
    local bed = bar.uuiModernWowProgressBackground
    local up = G("WhoListScrollFrameScrollBarScrollUpButton")
    if bed and up then
      local pad = M.modernWow.social.scrollBed.padding
      local upTop, barTop = up:GetTop(), bar:GetTop()
      if upTop and barTop and upTop > barTop then
        bed:ClearAllPoints()
        bed:SetPoint("TOPLEFT", bar, "TOPLEFT", -pad, upTop - barTop)
        bed:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad, -pad)
      end
    end

    local centre = (bRight - sLeft) / 2 +
                   M.modernWow.social.footerButton.x
    local totalsHeight = tonumber(totals:GetHeight()) or 12

    -- The totals take the search field's old place, which already lies inside
    -- the footer plate under its rule. Deliberately NOT derived from the
    -- plate's live GetTop: the plate hangs off the Friends footer buttons,
    -- which are hidden on this tab, and that read differed between the tab
    -- click and a later refresh -- the whole stack jumped (user report
    -- 2026-09-19). The captured number is stable.
    local top = whoMove.top
    totals:ClearAllPoints()
    totals:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", whoMove.left, top)

    -- The backdrop draws 2 left of and 5 below the EditBox's own top-left
    -- (EnsureWhoSearchBackdrop), so the EditBox is offset to centre it.
    local boxTop = top - totalsHeight - whoMove.gapTotals
    edit:ClearAllPoints()
    edit:SetPoint("TOP", scroll, "BOTTOMLEFT", centre + 2, boxTop + 5)

    -- The action row keeps its width, centred under the field.
    -- WhoFrameTotals is a region of WhoFrame, which draws at the footer
    -- plate's level, so inside the plate it disappeared under the rock wash
    -- (user report 2026-09-19). An addon-owned copy on the search backdrop --
    -- which does draw over the plate -- carries the text instead; the native
    -- string is only hidden, and WhoList_Update keeps setting its text.
    local label = whoMove.label
    if not label then
      label = whoSearchBackdrop:CreateFontString(nil, "OVERLAY")
      whoMove.label = label
      SetTextFont(label, M.fontSize.small, WHITE)
      label:SetJustifyH("CENTER")
    end
    -- Centred over the field, the same centre as the field and the row.
    label:ClearAllPoints()
    label:SetPoint("BOTTOM", whoSearchBackdrop, "TOP", 0, whoMove.gapTotals)
    label:SetText(totals:GetText() or "")
    label:Show()
    totals:Hide()

    local half = whoMove.row / 2
    who:ClearAllPoints()
    who:SetPoint("TOPLEFT", whoSearchBackdrop, "BOTTOM", -half,
                 -whoMove.gapButtons)
    invite:ClearAllPoints()
    invite:SetPoint("TOPRIGHT", whoSearchBackdrop, "BOTTOM", half,
                    -whoMove.gapButtons)
    add:ClearAllPoints()
    add:SetPoint("LEFT", who, "RIGHT", 3, 0)
    add:SetPoint("RIGHT", invite, "LEFT", -3, 0)
  end)
  whoMove.active = ok
end

-- The Zone column's x from the list's left edge, from the same spec that
-- chains the headers (StyleWhoHeaders): Level, Class, Name, then Zone.
local function WhoZoneX()
  local c = whoCols
  return c.rowToScroll + c.level.x + c.level.width + c.gap +
         c.class.width + c.gap + c.name.width + c.gap
end

-- Clicking the dropdown's text sorts the list by the column it shows, as the
-- classic header does; only the arrow opens the menu (user request
-- 2026-09-19). The dropdown's button, which the component spreads over the
-- whole control, is narrowed to the arrow, and an addon-owned button over the
-- rest calls SortWho with the shown column.
--
-- Not the native header: USER_CONFIRMED_INGAME 2026-09-19, with it laid over
-- the text WhoFrameColumnHeader2 did take the mouse, but it has no OnClick
-- script and no sortType on this client, so the click did nothing. SortWho
-- is the client's documented sort (OFFICIAL_CLIENT_DOCUMENTATION:
-- "name"/"zone"/"level"/"class"/"guild"/"race"; repeated calls are how the
-- native headers reverse the order, WORKING_SOURCE). The dropdown is anchored
-- by number (WhoZoneX), not to the header.
local WHO_ARROW_WIDTH = 20
local WHO_SORT_TYPES = { "zone", "guild", "race" }

-- The column the dropdown shows. UIDropDownMenu_GetSelectedID (1 zone,
-- 2 guild, 3 race: the 1.12 menu order, WORKING_SOURCE) when the client has
-- it; otherwise the shown text against the client's own localized ZONE /
-- GUILD / RACE strings, so a non-English client still matches.
local function WhoSortType(dropdown)
  local getID = G("UIDropDownMenu_GetSelectedID")
  if type(getID) == "function" then
    local ok, id = pcall(getID, dropdown)
    if ok and WHO_SORT_TYPES[tonumber(id) or 0] then
      return WHO_SORT_TYPES[tonumber(id)]
    end
  end
  local text = G("WhoFrameDropDownText")
  local ok, shown = false, nil
  if text then ok, shown = pcall(text.GetText, text) end
  if ok and type(shown) == "string" then
    local i
    for i = 1, table.getn(WHO_SORT_TYPES) do
      local label = G(string.upper(WHO_SORT_TYPES[i]))
      if type(label) == "string" and label == shown then
        return WHO_SORT_TYPES[i]
      end
    end
  end
  return "zone"
end

local function WhoDropdownSortArea(dropdown)
  local name = dropdown and dropdown.GetName and dropdown:GetName()
  local button = name and G(name .. "Button")
  if not button then return end
  pcall(function()
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, 0)
    button:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", 0, 0)
    button:SetWidth(WHO_ARROW_WIDTH)
  end)

  local sort = dropdown.uuiWhoSortButton
  if not sort then
    local ok, created = pcall(CreateFrame, "Button", "UnrealUIWhoSortButton",
                              dropdown)
    if not ok or not created then return end
    sort = created
    dropdown.uuiWhoSortButton = sort
    pcall(sort.SetScript, sort, "OnClick", function()
      if type(SortWho) == "function" then pcall(SortWho, WhoSortType(dropdown)) end
    end)
  end
  pcall(function()
    sort:ClearAllPoints()
    sort:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, 0)
    sort:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -WHO_ARROW_WIDTH, 0)
    -- Above the native Zone header, which still lies under this area and
    -- takes the mouse.
    sort:SetFrameLevel(dropdown:GetFrameLevel() + 3)
  end)

  -- The native Zone header's own label stays hidden; the dropdown shows it.
  -- Its hover glow is cleared too (user, 2026-09-19): the button's own state
  -- art, emptied directly rather than walked (rules/unreal-ui.md).
  local header = G("WhoFrameColumnHeader2")
  if header then
    local ok, label = pcall(header.GetFontString, header)
    if ok and label then pcall(label.Hide, label) end
    local okG, glow = pcall(header.GetHighlightTexture, header)
    if okG and glow then pcall(glow.Hide, glow) end
    if not pcall(header.SetHighlightTexture, header, "") then
      pcall(header.SetHighlightTexture, header, nil)
    end
  end
end

-- Modern WoW: the header band above the Who list, the footer plate's twin
-- with its rule on the bottom edge (M.modernWow.social.headerPlate).
-- Parented to WhoFrame, so it shows and hides with the tab on its own, and
-- one level under the column headers so they and the dropdown draw over it.
-- Addon-owned and mouse-transparent.
-- A header band over a Social list (Who, Guild): the footer plate's twin
-- with its rule on the bottom edge, between the header and the list. It is
-- parented to the tab's own frame (`host`), so it shows and hides with the
-- tab, and sits one level under the tab's first column header so headers and
-- controls draw over it. Sides and top come from the window art's recess;
-- the height reaches down to `scroll`'s top edge, read as bounded numbers
-- from frames that are shown on this tab (the first call, before layout,
-- just waits for a deferred one). Returns the band and its height.
-- `bottomScroll` (optional) is the list whose top edge ends the band, when
-- that is not `scroll` itself (the Guild band borrows the Who list's).
--
-- That borrowed edge is NOT read live: on the Guild tab the Who list is
-- hidden, and a hidden frame's position here can be stale (reopening the
-- window on Guild threw the headers out of it -- user report 2026-09-20; the
-- same kind of stale read as the Friends-button plate). Its depth below the
-- window's top is stored whenever the Who band is laid out with the Who list
-- SHOWN, and the Guild band uses the window's live top minus that depth. The
-- own list's top is the fallback before Who has been shown.
local bandDepth = {}

local function HeaderBand(scroll, host, name, headerName, bottomScroll)
  if not modernWow or not scroll or not host then return nil end
  local plate = scroll.uuiHeaderBand
  if not plate then
    local ok, created = pcall(CreateFrame, "Frame", name, host)
    if not ok or not created then return nil end
    plate = created
    scroll.uuiHeaderBand = plate
    pcall(plate.EnableMouse, plate, false)
    local header = G(headerName)
    local okL, level = false, nil
    if header then okL, level = pcall(header.GetFrameLevel, header) end
    if okL and tonumber(level) then
      pcall(plate.SetFrameLevel, plate, math.max(0, level - 1))
    end
  end

  local t = M.modernWow.social.headerPlate
  local window = G("FriendsFrame")
  local height, bottomY
  if window then
    pcall(function()
      local frameTop = window:GetTop()
      local listTop
      if bottomScroll then
        if bandDepth.who and frameTop then
          listTop = frameTop - bandDepth.who
        else
          -- Who not shown yet this session: never trust its hidden edge;
          -- end on this tab's own (shown) list until it has been.
          listTop = scroll:GetTop()
        end
      else
        listTop = scroll:GetTop()
        -- A shown list: keep its depth for bands that borrow it.
        local okV, shown = pcall(scroll.IsVisible, scroll)
        if okV and shown and frameTop and listTop and
           scroll == G("WhoListScrollFrame") then
          bandDepth.who = frameTop - listTop
        end
      end
      if not frameTop or not listTop then return end
      local h = (frameTop - t.top) - listTop
      if h <= 0 then return end
      plate:ClearAllPoints()
      plate:SetPoint("TOPLEFT", window, "TOPLEFT", t.left, -t.top)
      plate:SetPoint("TOPRIGHT", window, "TOPLEFT", t.right, -t.top)
      plate:SetHeight(h)
      height, bottomY = h, listTop
    end)
  end
  -- Built once; later calls only re-sample the rock grain for the live size.
  U.ModernWowSocialFooterPlate(plate, "BOTTOM")
  return plate, height, bottomY
end

local function WhoHeaderPlate(scroll)
  if not modernWow or not scroll then return end
  local plate, height = HeaderBand(scroll, G("WhoFrame"),
                                   "UnrealUIWhoHeaderPlate",
                                   "WhoFrameColumnHeader1")
  local t = M.modernWow.social.headerPlate
  if plate and height then
    pcall(function()
      -- Centre the header row on the band above the rule. The Level header
      -- heads the chain (StyleWhoHeaders), so moving it moves all four; each
      -- label is pinned to its header's vertical centre.
      local inner = height - t.ruleHalf
      local centre = t.ruleHalf + inner / 2 + t.contentY
      local headerBottom = centre - t.headerHeight / 2
      local level = G("WhoFrameColumnHeader3")
      if level then
        pcall(level.SetHeight, level, t.headerHeight)
        Reposition(level, "BOTTOMLEFT", scroll, "TOPLEFT",
                   whoCols.rowToScroll + whoCols.level.x, headerBottom)
      end

      -- The dropdown fits the same band: `pad` clear of it, centred on the
      -- same line, at most the component's normal height.
      local dropdown = G("WhoFrameDropDown")
      if dropdown then
        local dh = math.min(28, inner - t.pad * 2) + t.dropdownGrow
        if dh > 0 then
          U.Dropdown.SetControlHeight(dropdown, dh)
          local bottom = centre - dh / 2
          dropdown:ClearAllPoints()
          dropdown:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", WhoZoneX(), bottom)
          dropdown:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", 0, bottom)
          WhoDropdownSortArea(dropdown)
        end
      end
    end)
  end
end

local function StyleWhoTab()
  local scroll = G("WhoListScrollFrame")
  if not scroll then return end

  StyleList(scroll, "WhoListScrollFrameScrollBar")
  Reposition(G("WhoFrameButton1"), "TOPLEFT", scroll, "TOPLEFT", -5, -5)

  StyleWhoHeaders(scroll)
  StyleWhoRows()
  WhoHeaderPlate(scroll)

  -- Keep the native text filter untouched; test the dropdown independently.
  U.Dropdown.StyleStock(G("WhoFrameDropDown"), 120, { modernWow = modernWow })
  local dropdown = G("WhoFrameDropDown")
  if dropdown and modernWow then
    -- As wide as the Zone column it filters: from that column to the list's
    -- right edge (user request 2026-09-19). WhoHeaderPlate re-centres it.
    pcall(function()
      dropdown:ClearAllPoints()
      dropdown:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", WhoZoneX(), 3)
      dropdown:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", 0, 3)
    end)
    WhoDropdownSortArea(dropdown)
  elseif dropdown then
    Reposition(dropdown, "BOTTOMRIGHT", scroll, "TOPRIGHT", 0, 3)
  end

  -- Same height grow as the Friends footer, set before the theme face is
  -- built so its end caps take their aspect from it. All three buttons share
  -- one row, so they grow together.
  local names = {
    "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton",
  }
  local i
  for i = 1, table.getn(names) do
    local button = G(names[i])
    if modernWow and button and not button.uuiSocialFooterSized then
      button.uuiSocialFooterSized = true
      local ok, height = pcall(button.GetHeight, button)
      if ok and tonumber(height) and height > 0 then
        pcall(button.SetHeight, button,
              height + M.modernWow.social.footerButton.heightGrow)
      end
    end
    ActionButton(button)
  end
  LayoutWhoFooter()
end

-- ---------------------------------------------------------------------------
-- Guild tab
--
-- Column headers, roster list and the MOTD/notes controls only -- the deeper
-- rank-editing (GuildControlPopupFrame) dialog stays native, per the scope
-- trim above.
-- ---------------------------------------------------------------------------
-- How far the flat themes drop the guild list below where the client puts it
-- (user request, 2026-09-20).
local GUILD_LIST_DROP = 8

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

-- The status rows' "Last Online" value ran past the window's right edge
-- (user reports 2026-09-20, both themes). It is re-placed under its own
-- header -- the columns' summed widths from the list's left edge -- and
-- bounded to end `onlineRight` inside the list, left-aligned, so a long value
-- wraps or clips instead of escaping the window. x is measured against the
-- first status row, which shares every row's left edge; field names are
-- WORKING_SOURCE (1.12 FrameXML) and a missing one is skipped. Re-run after
-- every roster update, like StyleGuildRows.
local function LayoutGuildStatusOnline(scroll)
  if not scroll then return end
  local c = M.guildStatusColumns
  local statusRow = G("GuildFrameGuildStatusButton1")
  if not statusRow then return end

  local okW, rowLeft, sLeft, sRight = pcall(function()
    return statusRow:GetLeft(), scroll:GetLeft(), scroll:GetRight()
  end)
  if not okW or not rowLeft or not sLeft or not sRight then return end

  local x = c.x + c.width[1] + c.width[2] + c.width[3]
  local width = (sRight - sLeft) - x - c.onlineRight
  if width <= 0 then return end
  local n
  for n = 1, N("GUILDMEMBERS_TO_DISPLAY", 13) do
    local row = G("GuildFrameGuildStatusButton" .. n)
    local online = G("GuildFrameGuildStatusButton" .. n .. "Online")
    if row and online then
      pcall(online.SetWidth, online, width)
      Reposition(online, "LEFT", row, "LEFT", x - (rowLeft - sLeft), 0)
      LeftText(online)
    end
  end
end

local function LayoutGuildHeaderSet(prefix, scroll)
  if not scroll then return end

  -- Player-status view: Name, Rank, Note, Last Online -- its own natural
  -- order, not the roster's -- chained left to right over the value columns
  -- (user requests 2026-09-20, for modern-wow and then for `modern`; the
  -- generic branch below maps the roster's columns and put these headers over
  -- the wrong values). Under modern-wow GuildHeaderPlate additionally puts
  -- the first one on the header band's line.
  if prefix == "GuildFrameGuildStatusColumnHeader" then
    local c = M.guildStatusColumns
    local previous
    local i
    for i = 1, 4 do
      local header = G(prefix .. i)
      if header then
        pcall(header.SetWidth, header, c.width[i])
        if previous then
          Reposition(header, "LEFT", previous, "RIGHT", 0, 0)
        else
          Reposition(header, "BOTTOMLEFT", scroll, "TOPLEFT", c.x, 4)
        end
        previous = header
      end
    end
    return
  end

  local level = G(prefix .. "3")
  local class = G(prefix .. "4")
  local name = G(prefix .. "1")
  local zone = G(prefix .. "2")

  if level then
    pcall(level.SetWidth, level, 20)
    Reposition(level, "BOTTOMLEFT", scroll, "TOPLEFT", 8, 4)
  end
  if class and level then
    pcall(class.SetWidth, class, 54)
    Reposition(class, "LEFT", level, "RIGHT", 5, 0)
  end
  if name and class then
    pcall(name.SetWidth, name, 120)
    Reposition(name, "LEFT", class, "RIGHT", 4, 0)
  end
  if zone and name then
    pcall(zone.SetWidth, zone, 160)
    Reposition(zone, "LEFT", name, "RIGHT", 4, 0)
  end
end

local function LayoutGuildHeaders(scroll)
  local prefixIndex
  for prefixIndex = 1, table.getn(GUILD_HEADER_PREFIXES) do
    LayoutGuildHeaderSet(GUILD_HEADER_PREFIXES[prefixIndex], scroll)
  end
  LayoutGuildStatusOnline(scroll)
  PositionGuildSortArrows()
end

-- Guild tab: the same band over the roster (user request 2026-09-20), and
-- the same height and position as the Who tab's (user request 2026-09-20):
-- it ends on the Who list's top edge rather than the roster's, which sits
-- lower. The Who list is hidden on this tab, but it is never re-anchored by
-- UnrealUI, so its native top is a stable reading.
--
-- Its header labels then sit where the Who tab's do: the same height, the
-- same centre line in the band (WhoHeaderPlate's arithmetic). Both guild
-- header sets (roster and guild-status view) move by their Level header,
-- which heads each chain (LayoutGuildHeaderSet), keeping its x of 8.
local function GuildHeaderPlate()
  local scroll = G("GuildListScrollFrame")
  local plate, height, bottomY = HeaderBand(scroll, G("GuildFrame"),
                                            "UnrealUIGuildHeaderPlate",
                                            "GuildFrameColumnHeader1",
                                            G("WhoListScrollFrame"))
  if not plate or not height or not bottomY then return end
  local t = M.modernWow.social.headerPlate
  local inner = height - t.ruleHalf
  local centre = t.ruleHalf + inner / 2 + t.contentY
  local headerBottom = bottomY + centre - t.headerHeight / 2
  local okT, listTop = pcall(scroll.GetTop, scroll)
  if not okT or not tonumber(listTop) then return end

  -- The roster's scrollbar sits `barDrop` lower (user, 2026-09-20): its
  -- native edges against the list are measured once from the shown tab (not
  -- read with GetPoint, knowledge.json frames.getpoint_y_same_sign_as_setpoint)
  -- and both anchors re-set from them. Arrows and channel ride the bar; the
  -- message box, whose corner hangs off the down arrow, takes it back in
  -- StyleGuildTab.
  local bar = G("GuildListScrollFrameScrollBar")
  local drop = M.modernWow.social.guildButtons.barDrop or 0
  if bar and drop ~= 0 then
    if not scroll.uuiGuildBarNative then
      pcall(function()
        local bTop, bBottom, bLeft = bar:GetTop(), bar:GetBottom(), bar:GetLeft()
        local sRight, sBottom = scroll:GetRight(), scroll:GetBottom()
        if bTop and bBottom and bLeft and sRight and sBottom then
          scroll.uuiGuildBarNative = { x = bLeft - sRight, top = bTop - listTop,
                                       bottom = bBottom - sBottom }
        end
      end)
    end
    local n = scroll.uuiGuildBarNative
    if n then
      pcall(function()
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", n.x, n.top - drop)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", n.x, n.bottom - drop)
      end)

      -- The list's track art (TRACK: two textures on the scroll frame) is
      -- attached to the BAR itself, keeping its native offset from it, so it
      -- rides every bar move -- this drop and any later one -- together with
      -- the arrows and the thumb (user request 2026-09-20). Native offsets
      -- against the list: top +5, bottom -2 (TRACK); against the bar they are
      -- those minus the bar's own measured ones. Once per session.
      if not scroll.uuiGuildTrackPlaced then
        scroll.uuiGuildTrackPlaced = true
        local found = FindTrackPieces(scroll)
        local x = TRACK.top.x - n.x
        if found.top then
          PlaceTrackPiece(scroll, found.top, TRACK.top, 5 - n.top,
                          { frame = bar, point = "TOPLEFT", x = x })
        end
        if found.bottom then
          PlaceTrackPiece(scroll, found.bottom, TRACK.bottom,
                          TRACK.bottom.y - n.bottom,
                          { frame = bar, point = "BOTTOMLEFT", x = x })
        end
      end
    end
  end

  -- The roster headers start where their values do (user, 2026-09-20): the
  -- first row's left edge plus the rows' level offset (StyleGuildRows uses
  -- whoCols.level.x), measured from the shown list. The header chain uses
  -- the rows' own widths and gaps, and each label is pinned to its header's
  -- left edge (StyleGuildHeaders), so every label lands over its column.
  -- The guild-status view has other columns and keeps its x of 8.
  -- The roster rows sit `rowsDrop` lower (user, 2026-09-20): the client
  -- shows a fixed 13 rows, so the extra list height is spent as space above
  -- them rather than more members. Only the first row is re-anchored -- the
  -- others hang off it natively -- and only once, from its own measured
  -- offset against the shown list.
  local first = G("GuildFrameButton1")
  local rowsDrop = M.modernWow.social.guildButtons.rowsDrop or 0
  if first and rowsDrop ~= 0 and not scroll.uuiGuildRowsDropped then
    pcall(function()
      local rTop, rLeft = first:GetTop(), first:GetLeft()
      local sLeft = scroll:GetLeft()
      if rTop and rLeft and sLeft then
        scroll.uuiGuildRowsDropped = true
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", scroll, "TOPLEFT", rLeft - sLeft,
                       rTop - listTop - rowsDrop)
      end
    end)
  end

  -- "Show Offline Members" (checkbox + label, both inside GuildFrameLFGFrame)
  -- sits `offlineDrop` lower (user, 2026-09-20): the container is re-anchored
  -- once from its own measured offset against the shown Guild frame.
  local lfg, guild = G("GuildFrameLFGFrame"), G("GuildFrame")
  local offlineDrop = M.modernWow.social.guildButtons.offlineDrop or 0
  if lfg and guild and offlineDrop ~= 0 and not lfg.uuiOfflineDropped then
    pcall(function()
      local top, left = lfg:GetTop(), lfg:GetLeft()
      local gTop, gLeft = guild:GetTop(), guild:GetLeft()
      if top and left and gTop and gLeft then
        lfg.uuiOfflineDropped = true
        lfg:ClearAllPoints()
        lfg:SetPoint("TOPLEFT", guild, "TOPLEFT", left - gLeft,
                     top - gTop - offlineDrop)
      end
    end)
  end

  local rosterX = 8
  local row = G("GuildFrameButton1")
  if row then
    local okL, rowLeft, listLeft = pcall(function()
      return row:GetLeft(), scroll:GetLeft()
    end)
    if okL and rowLeft and listLeft then
      rosterX = rowLeft - listLeft + whoCols.level.x
    end
  end
  local level = G("GuildFrameColumnHeader3")
  if level then
    pcall(level.SetHeight, level, t.headerHeight)
    Reposition(level, "BOTTOMLEFT", scroll, "TOPLEFT", rosterX,
               headerBottom - listTop)
  end

  -- Player-status view: its headers 1-4 are Name, Rank, Note, Last Online.
  -- LayoutGuildHeaderSet chains that set in natural order from fixed widths
  -- (M.modernWow.social.guildStatusColumns); here the first one is put on
  -- the band's header line, and each label is pinned to its header's left.
  -- The status rows' "Last Online" value ran past the window's right edge
  -- (user report 2026-09-20): it is re-placed under its header -- the
  -- columns' summed widths from the list's left edge -- and bounded to end
  -- `onlineRight` inside the list, left-aligned. x is measured against the
  -- first status row, which shares every row's left edge; fields are
  -- WORKING_SOURCE names (1.12 FrameXML), a missing one is skipped. Re-run
  -- after every roster update, like StyleGuildRows.
  LayoutGuildStatusOnline(scroll)

  local status = G("GuildFrameGuildStatusColumnHeader1")
  if status then
    Reposition(status, "BOTTOMLEFT", scroll, "TOPLEFT",
               M.modernWow.social.guildStatusColumns.x, headerBottom - listTop)
  end
  local i
  for i = 1, 4 do
    local header = G("GuildFrameGuildStatusColumnHeader" .. i)
    if header then
      pcall(header.SetHeight, header, t.headerHeight)
      PinHeaderLabel(header)
    end
  end
  PositionGuildSortArrows()
end

local function StyleGuildHeaders(scroll)
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
        SetTextFont(header, M.fontSize.small, headingColor)
        -- Every label starts at its header's left edge, over the left-aligned
        -- values beneath it (user, 2026-09-20). Previously only the modern-wow
        -- roster set was pinned, so the other sets kept the stock centred
        -- label and read as offset from their own column.
        PinHeaderLabel(header)
      end
    end
  end

  LayoutGuildHeaders(scroll)
end

-- The client roster template is Name / Zone / Level / Class, while the modern
-- header treatment is Level / Class / Name / Zone. Moving only the Level
-- header leaves it on top of Name and drags Class away from its row -- exactly
-- the collision visible in the guild screenshot. Keep both headers and rows on
-- one explicit chain, and reapply it after every native roster refresh.
-- Declared here because StyleGuildRows' click hook below calls it and the
-- definition sits further down, with the rest of the detail panel's layout.
local GuildDetailTail

local function StyleGuildRows()
  local count = N("GUILDMEMBERS_TO_DISPLAY", 13)
  local scroll = G("GuildListScrollFrame")
  local rosterLevel = nil
  if scroll then
    local levelOk, level = pcall(scroll.GetFrameLevel, scroll)
    if levelOk and tonumber(level) then rosterLevel = level + 1 end
  end
  local i
  for i = 1, count do
    local row = G("GuildFrameButton" .. i)
    -- The roster rows are siblings of GuildListScrollFrame, whose flat
    -- backdrop under `modern` otherwise draws over their text (user,
    -- 2026-09-20). Lift each row one level above the list.
    if row and rosterLevel then
      pcall(row.SetFrameLevel, row, rosterLevel)
    end
    -- Clicking a row repopulates and re-sizes the detail panel natively. The
    -- shared driver puts the fitted height back, but a tick later, which reads
    -- as a flicker; re-applying it from the click itself lands in the same
    -- frame. Hooked once per row.
    if row and not row.uuiGuildDetailClick then
      row.uuiGuildDetailClick = true
      U.PostHookScript(row, "OnClick", function()
        local dock = G("GuildMemberDetailFrame")
        if dock then GuildDetailTail(dock) end
      end)
    end
    local level = G("GuildFrameButton" .. i .. "Level")
    local class = G("GuildFrameButton" .. i .. "Class")
    local name = G("GuildFrameButton" .. i .. "Name")
    local zone = G("GuildFrameButton" .. i .. "Zone")

    if level and row then
      pcall(level.SetWidth, level, 20)
      -- Same left padding in its row as the Who list's level (whoCols), and
      -- left-aligned like it (user, 2026-09-20).
      Reposition(level, "TOPLEFT", row, "TOPLEFT", whoCols.level.x, -3)
      LeftText(level)
    end
    if class and level then
      pcall(class.SetWidth, class, 54)
      Reposition(class, "LEFT", level, "RIGHT", 5, 0)
    end
    if name and class then
      pcall(name.SetWidth, name, 120)
      Reposition(name, "LEFT", class, "RIGHT", 4, 0)
    end
    if zone and name then
      pcall(zone.SetWidth, zone, 160)
      Reposition(zone, "LEFT", name, "RIGHT", 4, 0)
    end
  end
end

-- The panel's actions and its own height, applied after the rows above.
--
-- Split out and run twice -- inline and one tick later -- because the client
-- re-applies its own size: RUNTIME_PROBE 2026-09-20
-- (social.guild_detail_layout.v1) measured GuildMemberDetailFrame at 195 tall
-- with the note running to 218 and the officer note to 291 below its top, so
-- both notes and both buttons hung outside the panel, while the button anchors
-- this file had set (-303) had survived. Only the height was being overwritten.
--
-- The actions sit UNDER the last note instead of on the panel's bottom edge;
-- pinned to the bottom they landed on top of the note. Which notes exist is
-- the client's decision per rank, and the officer note's visibility is only
-- settled once the panel is up, which is the other reason for the second pass.
-- Where the panel's content ends, in units below its top edge: the note runs
-- laid out above are note 164..218 and officer note 237..291, and which of
-- them the client shows depends on the viewer's rank.
local function GuildDetailLastBottom()
  local officerNote = G("GuildMemberOfficerNoteBackground")
  if officerNote then
    local shownOk, shown = pcall(officerNote.IsShown, officerNote)
    if shownOk and shown then return 237 + 54 end
  end
  return 164 + 54
end

-- The fitted height: content, the gap under it, the action row, bottom inset.
local function GuildDetailHeight()
  return GuildDetailLastBottom() + 12 + 22 + 14
end

function GuildDetailTail(detail)
  if not detail then return end

  local lastBottom = GuildDetailLastBottom()
  local buttonTop = -(lastBottom + 12)
  local wanted = lastBottom + 12 + 22 + 14

  -- Early-out only when the same run is in place AND the height is still the
  -- fitted one. The client puts its own height back natively, without going
  -- through the frame's Lua SetHeight (wrapping that changed nothing), so a
  -- marker alone would let the reverted size stand.
  local heightOk, height = pcall(detail.GetHeight, detail)
  local fitted = heightOk and
                 math.abs((tonumber(height) or 0) - wanted) < 0.5
  if detail.uuiGuildDetailRun == lastBottom and fitted then return end
  detail.uuiGuildDetailRun = lastBottom

  local remove = G("GuildMemberRemoveButton")
  if remove then
    pcall(function()
      remove:ClearAllPoints()
      remove:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, buttonTop)
      remove:SetPoint("TOPRIGHT", detail, "TOP", -2, buttonTop)
      remove:SetHeight(22)
    end)
  end
  local invite = G("GuildMemberGroupInviteButton")
  if invite then
    pcall(function()
      invite:ClearAllPoints()
      invite:SetPoint("TOPLEFT", detail, "TOP", 2, buttonTop)
      invite:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, buttonTop)
      invite:SetHeight(22)
    end)
  end

  pcall(detail.SetHeight, detail, wanted)
  -- Re-measured after the resize: the housing was fitted to the old height.
  if modernWow then
    DockHousing(detail)
    U.ModernWowMetalFrameFill(detail, M.modernWow.social.guildDetailFill)
  end
end

local function LayoutGuildMemberDetail(detail)
  if not detail then return end

  -- Dock the panel to the same top edge as the Social window instead of the
  -- lower native anchor. All child anchors below are cleared before being set;
  -- adding a RIGHT point to the stock LEFT point stretched Rank/Online values
  -- across their labels and made the two strings render on top of each other.
  local gap = modernWow and M.modernWow.social.dockGap or 2
  Reposition(detail, "TOPLEFT", panel or frame, "TOPRIGHT", gap, 0)
  if modernWow then
    DockHousing(detail)
    U.ModernWowMetalFrameFill(detail, M.modernWow.social.guildDetailFill)
  end

  local name = G("GuildMemberDetailName")
  local levelClass = G("GuildMemberDetailLevelClass")
  if name then
    Reposition(name, "TOPLEFT", detail, "TOPLEFT", 20, -16)
    SetTextFont(name, M.fontSize.large, titleColor)
  end
  if levelClass then
    Reposition(levelClass, "TOPLEFT", name or detail,
               name and "BOTTOMLEFT" or "TOPLEFT", 0, name and -2 or -36)
    SetTextFont(levelClass, M.fontSize.small, WHITE)
  end

  local labelRows = {
    { "ZoneLabel", -70 },
    { "RankLabel", -95 },
    { "OnlineLabel", -120 },
  }
  local i
  for i = 1, table.getn(labelRows) do
    local label = G("GuildMemberDetail" .. labelRows[i][1])
    if label then
      pcall(label.SetWidth, label, 80)
      pcall(label.SetJustifyH, label, "LEFT")
      Reposition(label, "TOPLEFT", detail, "TOPLEFT", 20, labelRows[i][2])
      SetTextFont(label, M.fontSize.small, titleColor)
    end
  end

  local valueRows = {
    { "ZoneText", -70 },
    { "OnlineText", -120 },
  }
  for i = 1, table.getn(valueRows) do
    local value = G("GuildMemberDetail" .. valueRows[i][1])
    if value then
      pcall(value.SetWidth, value, 160)
      pcall(value.SetJustifyH, value, "RIGHT")
      Reposition(value, "TOPRIGHT", detail, "TOPRIGHT", -20, valueRows[i][2])
      SetTextFont(value, M.fontSize.small, WHITE)
    end
  end

  -- The rank arrows sit at the LEFT of their row, just past the label, so the
  -- rank value can right-align on the same edge as Zone and Last Online
  -- (user, 2026-09-20). They used to occupy that right edge themselves, which
  -- forced the value to hang left of them and out of the column.
  local promote = G("GuildFramePromoteButton")
  local demote = G("GuildFrameDemoteButton")
  if promote then Reposition(promote, "TOPLEFT", detail, "TOPLEFT", 104, -91) end
  if demote and promote then
    -- Leave the two expanded mouse targets disjoint as well as the visible
    -- buttons, so the boundary can never dispatch to the wrong rank action.
    Reposition(demote, "LEFT", promote, "RIGHT", 7, 0)
  elseif demote then
    Reposition(demote, "TOPLEFT", detail, "TOPLEFT", 104, -91)
  end

  -- Rank is the third value in the Zone / Rank / Last Online column and shares
  -- their right edge unconditionally, whatever the rank arrows are doing.
  local rank = G("GuildMemberDetailRankText")
  if rank then
    pcall(rank.SetWidth, rank, 160)
    pcall(rank.SetJustifyH, rank, "RIGHT")
    Reposition(rank, "TOPRIGHT", detail, "TOPRIGHT", -20, -95)
    SetTextFont(rank, M.fontSize.small, WHITE)
  end

  local noteLabel = G("GuildMemberNoteLabel")
  if noteLabel then
    Reposition(noteLabel, "TOPLEFT", detail, "TOPLEFT", 20, -148)
    SetTextFont(noteLabel, M.fontSize.small, titleColor)
  end
  local note = G("GuildMemberNoteBackground")
  if note then
    pcall(function()
      note:ClearAllPoints()
      note:SetPoint("TOPLEFT", detail, "TOPLEFT", 18, -164)
      note:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -20, -164)
      note:SetHeight(54)
    end)
  end

  local officerLabel = G("GuildMemberOfficerNoteLabel")
  if officerLabel then
    Reposition(officerLabel, "TOPLEFT", detail, "TOPLEFT", 20, -221)
    SetTextFont(officerLabel, M.fontSize.small, titleColor)
  end
  local officerNote = G("GuildMemberOfficerNoteBackground")
  if officerNote then
    pcall(function()
      officerNote:ClearAllPoints()
      officerNote:SetPoint("TOPLEFT", detail, "TOPLEFT", 18, -237)
      officerNote:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -20, -237)
      officerNote:SetHeight(54)
    end)
  end

  GuildDetailTail(detail)
  -- The client re-applies its own size after this pass, so the tail runs again
  -- on the next tick (see GuildDetailTail).
  DeferOnce("guild-detail-tail", function()
    GuildDetailTail(G("GuildMemberDetailFrame"))
  end)
end

local function StyleGuildTab()
  local scroll = G("GuildListScrollFrame")
  if not scroll then return end

  -- Modern WoW: the roster reaches `listGrow` lower, down to just above the
  -- message box (user, 2026-09-20). Its scrollbar and track art hang off the
  -- list's bottom and follow; the message box, which also hangs off it,
  -- takes the growth back below so it stays put. Once per session.
  local listGrow = modernWow and M.modernWow.social.guildButtons.listGrow or 0
  if listGrow ~= 0 and not scroll.uuiGuildListGrown then
    local ok, height = pcall(scroll.GetHeight, scroll)
    if ok and tonumber(height) and height > 0 then
      scroll.uuiGuildListGrown = true
      pcall(scroll.SetHeight, scroll, height + listGrow)
    end
  end

  -- The flat themes drop the list's ROWS by GUILD_LIST_DROP (user,
  -- 2026-09-20) so the first one clears the column headers above it.
  --
  -- Moving the scroll frame instead put the headers on top of row 1: the
  -- headers anchor to the list's top edge and travelled with it, while the
  -- rows, which are children of GuildFrame, stayed where they were. Only the
  -- first row of each set is re-anchored -- the rest hang off it natively --
  -- once, from its own existing point. Modern WoW does the same thing with
  -- its own `rowsDrop` further down, so it is left alone here.
  if not modernWow and not scroll.uuiGuildRowsDropped then
    local sets = { G("GuildFrameButton1"), G("GuildFrameGuildStatusButton1") }
    local moved = false
    local setIndex
    for setIndex = 1, table.getn(sets) do
      local first = sets[setIndex]
      if first then
        local pointOk, point, relative, relativePoint, x, y =
          pcall(first.GetPoint, first, 1)
        if pointOk and point then
          Reposition(first, point, relative, relativePoint, x or 0,
                     (y or 0) - GUILD_LIST_DROP)
          moved = true
        end
      end
    end
    if moved then scroll.uuiGuildRowsDropped = true end
  end

  StyleList(scroll, "GuildListScrollFrameScrollBar")

  StyleGuildHeaders(scroll)
  StyleGuildRows()

  -- Modern WoW: the toggle row (and the member count level with it) sits
  -- `statusGap` above the message box (user request 2026-09-20). The box's
  -- top is `-6 + motdY` below the list's bottom (see the box below, which
  -- also cancels `listGrow`), so the row is placed by the same numbers.
  local toggleTop = 18
  if modernWow then
    local gb = M.modernWow.social.guildButtons
    local motdTop = -6 + (gb.motdY or 0) +
                    (scroll.uuiGuildListGrown and gb.listGrow or 0)
    toggleTop = motdTop + gb.statusGap + 16
  end

  local toggle = G("GuildFrameGuildListToggleButton")
  if toggle and modernWow then
    -- A textured arrow, not the flat glyph (user request 2026-09-20): the
    -- client's own next-page button art -- the same native page buttons the
    -- Modern WoW Spellbook keeps -- set as this button's OWN state textures,
    -- so its normal/pushed/disabled/hover states stay the client's. The theme
    -- media has no right-pointing arrow. Drawn at `size`, centred on the
    -- row's line so the row's placement (toggleTop) is unchanged.
    local art = M.modernWow.social.statusArrow
    pcall(toggle.SetWidth, toggle, art.size)
    pcall(toggle.SetHeight, toggle, art.size)
    pcall(toggle.SetNormalTexture, toggle, art.normal)
    pcall(toggle.SetPushedTexture, toggle, art.pushed)
    pcall(toggle.SetDisabledTexture, toggle, art.disabled)
    pcall(toggle.SetHighlightTexture, toggle, art.highlight)
    -- Each state texture carries the art's full texcoords -- set on the
    -- native button, the art kept the previous regions' small size and crop
    -- and drew as a sliver (user report 2026-09-20) -- and is CENTRED at the
    -- art's own ratio instead of filling the button's rect: that rect stays
    -- narrower than tall, which squeezed the square arrow (user report
    -- 2026-09-21).
    local getters = { "GetNormalTexture", "GetPushedTexture",
                      "GetDisabledTexture", "GetHighlightTexture" }
    local g
    for g = 1, table.getn(getters) do
      local okT, tex = pcall(toggle[getters[g]], toggle)
      if okT and tex then
        pcall(function()
          tex:ClearAllPoints()
          tex:SetPoint("CENTER", toggle, "CENTER", 0, 0)
          tex:SetWidth(art.size * (art.aspect or 1))
          tex:SetHeight(art.size)
          tex:SetTexCoord(0, 1, 0, 1)
        end)
        if g == 4 then pcall(tex.SetBlendMode, tex, "ADD") end
      end
    end
    -- Same centre line as the 16-unit control (8 below `toggleTop`), so a
    -- larger art size does not move the row. TOPRIGHT, as before: a RIGHT
    -- point against the list's BOTTOMRIGHT put the button half-way up the
    -- list instead (USER_CONFIRMED_INGAME 2026-09-20).
    Reposition(toggle, "TOPRIGHT", scroll, "BOTTOMRIGHT", -4 + art.rightPad,
               toggleTop - 8 + art.size / 2)
  elseif toggle then
    U.StyleStockArrowButton(toggle, "right", 16)
    Reposition(toggle, "TOPRIGHT", scroll, "BOTTOMRIGHT", -4, toggleTop)
  end
  if toggle then
    -- StyleStockArrowButton deliberately centres a button's native fontstring;
    -- this composite control also owns a long status label, so centring both it
    -- and the glyph in 16px puts the glyph through the words. Keep the dynamic
    -- native text, but give it a separate anchor immediately left of the arrow.
    local toggleText
    if toggle.GetFontString then
      pcall(function() toggleText = toggle:GetFontString() end)
    end
    if not toggleText then toggleText = G("GuildFrameGuildListToggleButtonText") end
    if toggleText then
      -- Modern WoW: level with "n Guild Members" (user request 2026-09-20),
      -- which sits `totalsY + leftTextY` off the toggle's centre line below.
      local labelY = 0
      if modernWow then
        local gb = M.modernWow.social.guildButtons
        -- ...then `statusLabelY` on its own (user, 2026-09-20: 3 up).
        labelY = (gb.totalsY or 0) + (gb.leftTextY or 0) +
                 (gb.statusLabelY or 0)
      end
      Reposition(toggleText, "RIGHT", toggle, "LEFT", -5, labelY)
      SetTextFont(toggleText, M.fontSize.small, titleColor)
    end

    -- "n Guild Members" + "(n online)" on the same line as the toggle's
    -- label, left side (user request 2026-09-20). Both hang off the list's
    -- bottom-left at the toggle's own centre line -- the toggle is 16 high,
    -- its top 18 above the list's bottom -- so they stay level with it
    -- whatever the texts' lengths. Names: WORKING_SOURCE (DragonflightUI's
    -- guild skin, 1.12 FrameXML); absent frames are skipped.
    local totals, online = G("GuildFrameTotals"), G("GuildFrameOnlineTotals")
    if modernWow and totals then
      -- The member count sits `totalsY` off that line (user, 2026-09-20:
      -- 2 lower), and "(n online)" now stays level with the count itself
      -- (user, 2026-09-20), so both share that offset.
      local dy = M.modernWow.social.guildButtons.totalsY or 0
      -- Both left texts then sit `leftTextY` further (user, 2026-09-20).
      local left = M.modernWow.social.guildButtons.leftTextY or 0
      Reposition(totals, "LEFT", scroll, "BOTTOMLEFT", 8,
                 toggleTop - 16 / 2 + dy + left)
      if online then Reposition(online, "LEFT", totals, "RIGHT", 4, 0) end
    end
  end

  local motd = G("GuildMOTDEditButton")
  if motd then
    InsetBox(motd, { 0.01, 0.01, 0.01, 0.78 })
    -- Modern WoW shifts the message box `motdX` right (user, 2026-09-20);
    -- the action row below, which hangs off it, takes the shift back.
    local motdX = modernWow and M.modernWow.social.guildButtons.motdX or 0
    -- ...and grows `motdGrow` taller at its bottom; the row takes that back too.
    local motdGrow = modernWow and M.modernWow.social.guildButtons.motdGrow or 0
    -- ...and the whole box moves `motdY` (negative: down); the row takes it back.
    local motdY = modernWow and M.modernWow.social.guildButtons.motdY or 0
    -- The roster above grew `listGrow` downward; cancel that here.
    if scroll.uuiGuildListGrown then
      motdY = motdY + M.modernWow.social.guildButtons.listGrow
    end
    Reposition(motd, "TOPLEFT", scroll, "BOTTOMLEFT", motdX, -6 + motdY)
    local down = G("GuildListScrollFrameScrollBarScrollDownButton")
    -- The down arrow rides the scrollbar's `barDrop` (GuildHeaderPlate);
    -- the box's corner cancels it so the box keeps its height.
    local barDrop = (modernWow and down) and
                    (M.modernWow.social.guildButtons.barDrop or 0) or 0
    pcall(motd.SetPoint, motd, "BOTTOMRIGHT", down or scroll, "BOTTOMRIGHT",
          motdX, -68 - motdGrow + motdY + barDrop)
  end

  local notesLabel = G("GuildFrameNotesLabel")
  if notesLabel and motd then
    Reposition(notesLabel, "TOPLEFT", motd, "TOPLEFT", 4, -4)
    SetTextFont(notesLabel, M.fontSize.small, headingColor)
  end
  local notesText = G("GuildFrameNotesText")
  if notesText and motd then
    pcall(function()
      notesText:ClearAllPoints()
      notesText:SetPoint("TOPLEFT", motd, "TOPLEFT", 4, -21)
      notesText:SetPoint("BOTTOMRIGHT", motd, "BOTTOMRIGHT", -4, 4)
    end)
    SetTextFont(notesText, M.fontSize.small, WHITE)
  end
  SyncGuildNotes()

  -- Modern WoW: the three actions share one height, the tallest native one
  -- plus the footer's `heightGrow` (user request 2026-09-20), set before the
  -- theme face is built so its caps take their aspect from it. They then
  -- hang by their BOTTOM edges from where the tallest one's bottom was, so
  -- the extra height goes up and the three bottoms line up.
  local guildNames = {
    "GuildFrameGuildInformationButton", "GuildFrameAddMemberButton",
    "GuildFrameControlButton",
  }
  local guildNative = 0
  if modernWow then
    local grow = M.modernWow.social.footerButton.heightGrow
    local i
    for i = 1, table.getn(guildNames) do
      local button = G(guildNames[i])
      local ok, height = false, nil
      if button then ok, height = pcall(button.GetHeight, button) end
      if ok and tonumber(height) and height > guildNative then
        guildNative = height
      end
    end
    for i = 1, table.getn(guildNames) do
      local button = G(guildNames[i])
      if button and guildNative > 0 and not button.uuiSocialFooterSized then
        button.uuiSocialFooterSized = true
        pcall(button.SetHeight, button, guildNative + grow)
      end
    end
  end

  local info = ActionButton(G("GuildFrameGuildInformationButton"))
  local addMember = ActionButton(G("GuildFrameAddMemberButton"))
  local control = ActionButton(G("GuildFrameControlButton"))
  if info and motd and guildNative > 0 then
    -- The row then moves by `guildButtons` x/y (user, 2026-09-20).
    local move = M.modernWow.social.guildButtons
    Reposition(info, "BOTTOMLEFT", motd, "BOTTOMLEFT", move.x - move.motdX,
               -5 - guildNative + move.y + move.motdGrow - move.motdY)
  elseif info and motd then
    Reposition(info, "TOPLEFT", motd, "BOTTOMLEFT", 0, -5)
  end
  if addMember and info and control then
    pcall(function()
      addMember:ClearAllPoints()
      addMember:SetPoint("LEFT", info, "RIGHT", 3, 0)
      addMember:SetPoint("RIGHT", control, "LEFT", -3, 0)
    end)
  end
  if control and motd and guildNative > 0 then
    local move = M.modernWow.social.guildButtons
    Reposition(control, "BOTTOMRIGHT", motd, "BOTTOMRIGHT", move.x - move.motdX,
               -5 - guildNative + move.y + move.motdGrow - move.motdY)
  elseif control and motd then
    Reposition(control, "TOPRIGHT", motd, "BOTTOMRIGHT", 0, -5)
  end

  U.StripStockTextures(G("GuildFrameLFGFrame"))
  -- "Show Offline Members". Modern WoW keeps the client's own CheckButton
  -- art at its native 20 (user request 2026-09-20), as the Modern WoW
  -- Spellbook's toggles do: a flat UnrealUI square would be the one foreign
  -- control on the textured window (rules/unreal-ui-design.md, Modern WoW
  -- interface-media contract). The flat themes keep the shared checkbox.
  local offline = G("GuildFrameLFGButton")
  if modernWow then
    if offline then pcall(offline.SetWidth, offline, 20) end
    if offline then pcall(offline.SetHeight, offline, 20) end
  else
    U.StyleStockCheckbox(offline, 20)
  end

  -- Member detail side dock.
  local detail = G("GuildMemberDetailFrame")
  if detail then
    -- Stripped once, before any addon texture exists on it; the Modern WoW
    -- metal is drawn by LayoutGuildMemberDetail at the dock's live size.
    U.StripStockTextures(detail)
    DockHousing(detail)
    U.StyleStockCloseButton(G("GuildMemberDetailCloseButton"), detail, -6, -6)

    U.StyleStockArrowButton(G("GuildFramePromoteButton"), "up", 16)
    U.StyleStockArrowButton(G("GuildFrameDemoteButton"), "down", 16)

    U.StripStockTextures(G("GuildMemberNoteBackground"))
    InsetBox(G("GuildMemberNoteBackground"))
    U.StripStockTextures(G("GuildMemberOfficerNoteBackground"))
    InsetBox(G("GuildMemberOfficerNoteBackground"))

    ActionButton(G("GuildMemberRemoveButton"))
    ActionButton(G("GuildMemberGroupInviteButton"))
    LayoutGuildMemberDetail(detail)
    U.PostHookScript(detail, "OnShow", function()
      LayoutGuildMemberDetail(detail)
    end)
    -- Selecting a DIFFERENT member repopulates the panel without re-showing
    -- it, and the client re-applies its own height every time it does, so the
    -- first member came out right and every one after it reverted (user,
    -- 2026-09-20).
    --
    -- Correcting that from the driver below left the client's own height on
    -- screen until the next tick, which read as a flicker on every member
    -- (user, 2026-09-20), so the frame's SetHeight is wrapped the way this
    -- file wraps Enable/Disable on the footer actions: the client's call is
    -- answered with the fitted height, and nothing wrong is ever drawn. The
    -- driver still runs, for the button row and the housing when a member's
    -- officer note appears or disappears.
    if not detail.uuiGuildHeightWatch then
      detail.uuiGuildHeightWatch = true
      local setHeight = detail.SetHeight
      if type(setHeight) == "function" then
        detail.SetHeight = function(self, value)
          return setHeight(self, GuildDetailHeight())
        end
      end
    end
    U.RegisterUpdate("friends.guild-detail", 0.2, function()
      local dock = G("GuildMemberDetailFrame")
      if not dock then return end
      local shownOk, shown = pcall(dock.IsShown, dock)
      if shownOk and shown then GuildDetailTail(dock) end
    end)
  end

  -- Guild info (MOTD editor) dock.
  local guildInfo = G("GuildInfoFrame")
  if guildInfo then
    U.StripStockTextures(guildInfo)
    DockHousing(guildInfo)
    U.StyleStockCloseButton(G("GuildInfoCloseButton"), guildInfo, -6, -6)
    InsetBox(G("GuildInfoTextBackground"))
    if modernWow then
      U.ModernWowSocialScrollBed(G("GuildInfoFrameScrollFrameScrollBar"))
      U.PostHookScript(guildInfo, "OnShow", function() DockHousing(guildInfo) end)
    else
      U.StyleStockScrollbar(G("GuildInfoFrameScrollFrameScrollBar"))
    end
    ActionButton(G("GuildInfoSaveButton"))
    ActionButton(G("GuildInfoCancelButton"))
  end
end

-- ---------------------------------------------------------------------------
-- Frame chrome + tabs
-- ---------------------------------------------------------------------------
-- The title sits on the panel's top edge, or centred on the Modern WoW art's
-- title strip beside the portrait ring (M.modernWow.social).
local function PlaceTitle()
  local title = G("FriendsFrameTitleText")
  if modernWow then
    local token = M.modernWow.social
    Reposition(title, "TOP", frame, "TOPLEFT", token.titleX, token.titleY)
  else
    Reposition(title, "TOP", panel, "TOP", 0, -10)
  end
  SetTextFont(title, M.fontSize.large, titleColor)
end

local function Reapply()
  -- FriendsFrame's own regions only: the Modern WoW art lives on an owned
  -- child frame, which this region walk never reaches.
  U.StripStockTextures(frame)
  if panel then panel:Show() end
  PlaceTitle()
  PlaceToggleTabs("FriendsFrameToggleTab1", G("FriendsFrameFriendsScrollFrame"))
  PlaceToggleTabs("IgnoreFrameToggleTab1", G("FriendsFrameIgnoreScrollFrame"))
  SyncToggleTabs()
  LayoutGuildHeaders(G("GuildListScrollFrame"))
  StyleGuildRows()
  LayoutGuildMemberDetail(G("GuildMemberDetailFrame"))
  LayoutWhoFooter()
  -- Again once the shown window has geometry, for the row's centring shift.
  DeferOnce("who-footer", function()
    LayoutWhoFooter()
    MoveWhoSearch()
    -- The bands have their real size now; re-sample their rock grain.
    WhoHeaderPlate(G("WhoListScrollFrame"))
    GuildHeaderPlate()
  end)
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

  PlaceTitle()
  U.StyleStockCloseButton(G("FriendsFrameCloseButton"), panel, -6, -6)

  -- FriendsFrameTab1-5: Friends, Who, Guild, Raid, (TBC+) Channels. Only the
  -- present ones are collected, so this reads the same on a client that never
  -- shows a Channels tab.
  local tabs, i = {}, nil
  for i = 1, 5 do
    local tab = G("FriendsFrameTab" .. i)
    if tab then table.insert(tabs, tab) end
  end
  -- Modern WoW tabs tuck in from the art's rounded corner, as Character's do
  -- (M.modernWow.social.tabX; the rest of the row chains off the first).
  Reposition(tabs[1], "TOPLEFT", panel, "BOTTOMLEFT",
             modernWow and M.modernWow.social.tabX or 0, 0)
  U.ChainStockTabs(tabs, 3)
  -- No colours of its own. Friends / Who / Guild / Raid briefly carried the
  -- accent on every tab, selected or not; superseded the same day by "grey
  -- when the tab is not active", which is the shared component's own rule
  -- (M.tab.activeTextColor / inactiveTextColor), so this row now reads it
  -- like every other strip rather than keeping a Social-only pair.
  U.StyleStockTabGroup(tabs, 1)

  -- RUNTIME_PROBE 2026-09-19 (social.tab_state.broken.v1): with the Who list
  -- up, clicking Friends left FriendsFrame.selectedTab and
  -- PanelTemplates_GetSelectedTab at 2 and WhoFrame shown, while Tab1 was
  -- shown and enabled -- the click never reached the tab. The row is anchored
  -- to the addon panel's bottom edge rather than the window's, which lifts it
  -- into the band a shown sub-frame covers, and WhoFrame reaches lower than
  -- the friend list does. Lift the tabs over the sub-frames so the row stays
  -- clickable whichever one is up.
  local tabLevelOk, tabLevel = pcall(frame.GetFrameLevel, frame)
  if tabLevelOk and tonumber(tabLevel) then
    local t
    for t = 1, table.getn(tabs) do
      pcall(tabs[t].SetFrameLevel, tabs[t], tabLevel + 12)
    end
  end

  StyleFriendsSubTab()
  StyleIgnoreSubTab()
  SyncToggleTabs()
  U.PostHookScript(G("FriendsFrameFriendsScrollFrame"), "OnShow", SyncToggleTabs)
  U.PostHookScript(G("FriendsFrameIgnoreScrollFrame"), "OnShow", SyncToggleTabs)
  -- A toggle click also runs the shared group's own select, after the list
  -- has already switched: clicking Ignore marks Ignore selected on the pair
  -- being hidden. Re-sync on the next tick, after every click handler.
  local toggleName
  for toggleName in pairs(TOGGLE_ACTIVE) do
    U.PostHookScript(G(toggleName), "OnClick", function()
      DeferOnce("toggle-tabs", SyncToggleTabs)
    end)
  end
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

  -- Every tab switch runs FriendsFrame_Update; the plate follows a tick later,
  -- outside the native switch (see the scroll-bed note in modernwow.lua).
  U.PostHookGlobal("FriendsFrame_Update", function()
    DeferOnce("footer-plate-tab", PlaceFooterPlate)
  end)

  -- The client rewrites the window title on every tab change -- Friends, Who,
  -- Guild, Raid -- and that restores its own font and colour with it, so the
  -- accent only survived on the tab the window happened to be built on (user,
  -- 2026-09-20). Re-applied after each update, one tick later so the native
  -- pass has finished writing the text.
  U.PostHookGlobal("FriendsFrame_Update", function()
    DeferOnce("friends.title", PlaceTitle)
  end)

  U.PostHookGlobal("WhoList_Update", function()
    DeferOnce("friends.restyle-who-rows", function()
      StyleWhoRows()
      LayoutWhoFooter()
      MoveWhoSearch()
      -- Also placed here: this pass runs with the Who list actually shown,
      -- so the list's top edge is a live reading.
      WhoHeaderPlate(G("WhoListScrollFrame"))
    end)
  end)

  -- WORKING_SOURCE from UnrealPfUI on this same client: GuildStatus_Update is
  -- the native roster refresh used when sorting and switching guild-list mode.
  -- Recalculate after it changes the active header so the shown arrow remains
  -- beside the current label.
  U.PostHookGlobal("GuildStatus_Update", function()
    DeferOnce("friends.restyle-guild-roster", function()
      LayoutGuildHeaders(G("GuildListScrollFrame"))
      StyleGuildRows()
      SyncGuildNotes()
      GuildHeaderPlate()
    end)
  end)

  U.RegisterUpdate("friends.footer-state", FOOTER_INTERVAL, RefreshFooter)
  RefreshFooter()

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
  modernWow = type(U.ModernWowSocialActive) == "function" and
              U.ModernWowSocialActive()
  if modernWow then
    titleColor = M.modernWow.social.titleColor
    headingColor = M.modernWow.social.headingColor
  end
  BuildFrame()
end
