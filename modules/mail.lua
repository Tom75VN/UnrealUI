-- unrealUI :: modules/mail.lua
--
-- pfUI-modern-inspired treatment of the native Mailbox window (MailFrame):
-- its Inbox tab and Send Mail tab, plus OpenMailFrame -- the separate popup
-- used to read one received letter -- matching the Merchant/Trainer/
-- Character treatment. Native mail data, tab switching, item/money handling
-- and send/take-mail/open-mail logic stay intact; unrealUI changes only
-- artwork, typography and layout.
--
-- query_compat.py has no record at all for MailFrame or any of its children
-- (checked before writing this file). Every field name below is
-- WORKING_SOURCE from UnrealPfUI's skins/blizzard/mail.lua "vanilla" branch
-- (this client's .toc Interface: 11200 is Vanilla-shaped, not the TBC
-- ATTACHMENTS_MAX_SEND branch that file also carries), not runtime-verified
-- on this client -- every access is G()+pcall guarded so a wrong name simply
-- leaves that element untouched rather than erroring. Confirm in game and
-- fold real names into knowledge.json once checked.
--
-- SendMailNameEditBox, SendMailSubjectEditBox, the message-body EditBox
-- inside SendMailScrollFrame, and SendMailMoney (a MoneyInputFrame, itself
-- composed of EditBoxes) are deliberately left 100% untouched -- no strip,
-- no backdrop, no font pass -- unlike UnrealPfUI's skin, which does wrap
-- the name/subject boxes. rules/unreal-ui-design.md excludes every native
-- text input on this client after an EditBox focus crashed it
-- (knowledge.json / widgets.editbox_focus_crash); this is a deliberate scope
-- cut, not an oversight. SendMailScrollFrameScrollBar is a Slider, not a
-- text input, so its arrows/track are styled normally.
--
-- OpenMailFrame's letter body (inside OpenMailScrollFrame) is a read-only
-- FontString, not an EditBox -- you cannot edit a received letter -- so it is
-- recoloured the same way modules/gossip.lua's NPC dialog text is; nothing
-- in that section is a text input either.

local U = UnrealUI
local M = U.media
local ML = U.RegisterModule("mail")

local WHITE = { 0.90, 0.90, 0.90, 1.00 }

local frame, panel

local TAB_COUNT = 2

local function G(name)
  return U.G(name)
end

local function SetMailFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or WHITE)
end

local function Reposition(object, point, relativeTo, relativePoint, x, y)
  if not object then return end
  pcall(function()
    object:ClearAllPoints()
    object:SetPoint(point, relativeTo, relativePoint, x, y)
  end)
end

-- ---------------------------------------------------------------------------
-- MailFrame chrome: strip, panel, close, drag, tabs
-- ---------------------------------------------------------------------------
-- USER_CONFIRMED_INGAME: unlike Character/Merchant -- where the native tab
-- anchor already sits below the window and StyleTabs only needs to style,
-- not move, the tabs -- this client anchors MailFrameTab1 inside MailFrame's
-- own bounds, so it rendered on top of the content panel instead of as an
-- outside strip. WORKING_SOURCE (UnrealPfUI): its vanilla-branch skin
-- explicitly re-anchors tab 1 below MailFrame.backdrop for the same reason,
-- which is what this reproduces. Tab 2 still chains off tab 1 normally.
local TAB_Y_OFFSET = -4

local function StyleTabs()
  local tabs, i = {}, nil
  for i = 1, TAB_COUNT do
    tabs[i] = G("MailFrameTab" .. i)
  end

  Reposition(tabs[1], "TOPLEFT", panel, "BOTTOMLEFT", 0, TAB_Y_OFFSET)

  U.ChainStockTabs(tabs, 3)
  U.StyleStockTabGroup(tabs, 1)
end

-- ---------------------------------------------------------------------------
-- Inbox tab
-- ---------------------------------------------------------------------------

-- No compact-DB record for this constant; Vanilla's own Mail.lua defines it
-- as 7. Falls back the same way modules/trainer.lua does for
-- CLASS_TRAINER_SKILLS_DISPLAYED.
local function InboxRowCount()
  return tonumber(G("INBOXITEMS_TO_DISPLAY")) or 7
end

-- Tints the flat row background behind an inbox entry, same recipe as
-- modules/merchant.lua's TintRow: a thin low-layer white-alpha wash rather
-- than a full backdrop, so the sender/subject text and envelope icon stay
-- the visual focus of the row.
local function TintRow(owner)
  if not owner or owner.uuiRowTint then return end
  local ok, tint = pcall(owner.CreateTexture, owner, nil, "BACKGROUND")
  if not ok or not tint then return end
  pcall(tint.SetTexture, tint, M.texture.plain)
  pcall(tint.SetVertexColor, tint, 1, 1, 1, 0.05)
  pcall(tint.SetAllPoints, tint, owner)
  owner.uuiRowTint = tint
end

local function StyleInboxRow(i)
  local row = G("MailItem" .. i)
  if not row then return end

  U.StripStockTextures(row)
  TintRow(row)
  SetMailFont(row, M.fontSize.small, WHITE)

  local button = G("MailItem" .. i .. "Button")
  if button then
    local icon = G("MailItem" .. i .. "ButtonIcon")
    U.StyleStockButton(button, { icon = icon })
  end
end

local function StyleInboxRows()
  local rows = InboxRowCount()
  local i
  for i = 1, rows do
    StyleInboxRow(i)
  end
end

local function StylePageControls()
  U.StyleStockArrowButton(G("InboxPrevPageButton"), "left", 18)
  U.StyleStockArrowButton(G("InboxNextPageButton"), "right", 18)
end

local function ReapplyInboxHeader()
  SetMailFont(G("InboxTitleText"), M.fontSize.large, M.color.accent)
end

-- ---------------------------------------------------------------------------
-- Send Mail tab
--
-- SendMailPackageButton has no separate icon region -- its icon IS the
-- button's own normal texture, the same shape as modules/merchant.lua's
-- MerchantRepairItemButton bug (WORKING_SOURCE: UnrealPfUI's HandleIcon call
-- reads the button's own GetNormalTexture back after native update, rather
-- than treating it as a plain icon-bearing button). Applying that same fix
-- here pre-emptively rather than waiting to reproduce the bug in game.
-- ---------------------------------------------------------------------------
local function StyleSendPackageButton()
  local button = G("SendMailPackageButton")
  if not button then return end
  U.StyleStockButton(button)

  U.PostHookGlobal("SendMailFrame_Update", function()
    local textureOk, texture = pcall(button.GetNormalTexture, button)
    if textureOk and texture then
      pcall(texture.Show, texture)
      pcall(texture.SetAlpha, texture, 1)
      pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
    end
  end)
end

local function StyleSendButtons()
  local cancel = U.StyleStockButton(G("SendMailCancelButton"))
  local send = U.StyleStockButton(G("SendMailMailButton"))
  if send and cancel then
    Reposition(send, "RIGHT", cancel, "LEFT", -6, 0)
  end
end

local function ReapplySendHeader()
  SetMailFont(G("SendMailTitleText"), M.fontSize.large, M.color.accent)
end

local function StyleSendScrollbar()
  -- The body EditBox itself is untouched; only its scrollbar (a Slider, not
  -- a text input) gets the shared arrow/track treatment.
  U.StyleStockScrollbar(G("SendMailScrollFrameScrollBar"))
end

-- ---------------------------------------------------------------------------
-- Open Mail popup (reading one received letter)
--
-- A separate native frame from MailFrame, built in the same pass since it
-- shares Mail.xml's lazy-load timing: if MailFrame resolved, OpenMailFrame
-- resolves too. WORKING_SOURCE (UnrealPfUI): unlike SendMailPackageButton,
-- OpenMailPackageButton/OpenMailMoneyButton/OpenMailLetterButton each carry a
-- separate named icon region, so they take the plain icon-button treatment
-- rather than the GetNormalTexture-as-icon fix Send Mail needed. Not
-- movable, matching pfUI's own OpenMailFrame (only MailFrame gets
-- EnableMovable) -- it is tied to whichever letter is open, not a window a
-- player repositions.
-- ---------------------------------------------------------------------------
local openMailPanel

local function ReapplyOpenMailText()
  SetMailFont(G("OpenMailTitleText"), M.fontSize.large, M.color.accent)
  U.ForceStockTextWhite(G("OpenMailScrollFrame"), WHITE, M.fontSize.normal)
end

local function BuildOpenMailFrame()
  local openFrame = G("OpenMailFrame")
  if not openFrame then return end

  U.StripStockTextures(openFrame)

  openMailPanel = U.CreatePanel(openFrame, {
    name = "UnrealUIOpenMailPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  openMailPanel:SetPoint("TOPLEFT", openFrame, "TOPLEFT", 10, -10)
  openMailPanel:SetPoint("BOTTOMRIGHT", openFrame, "BOTTOMRIGHT", -32, 40)
  pcall(openMailPanel.EnableMouse, openMailPanel, false)

  pcall(openFrame.SetHitRectInsets, openFrame, 10, 32, 10, 40)

  local frameLevelOk, frameLevel = pcall(openFrame.GetFrameLevel, openFrame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(openMailPanel.SetFrameLevel, openMailPanel, frameLevel)
  end

  U.StyleStockCloseButton(G("OpenMailCloseButton"), openMailPanel, -6, -6)

  ReapplyOpenMailText()

  local cancel = U.StyleStockButton(G("OpenMailCancelButton"))
  local delete = U.StyleStockButton(G("OpenMailDeleteButton"))
  if delete and cancel then
    Reposition(delete, "RIGHT", cancel, "LEFT", -6, 0)
  end
  local reply = U.StyleStockButton(G("OpenMailReplyButton"))
  if reply and delete then
    Reposition(reply, "RIGHT", delete, "LEFT", -6, 0)
  end

  U.StyleStockButton(G("OpenMailMoneyButton"),
                     { icon = G("OpenMailMoneyButtonIconTexture") })
  U.StyleStockButton(G("OpenMailLetterButton"),
                     { icon = G("OpenMailLetterButtonIconTexture") })
  U.StyleStockButton(G("OpenMailPackageButton"),
                     { icon = G("OpenMailPackageButtonIconTexture") })

  U.StripStockTextures(G("OpenMailScrollFrame"))
  U.StyleStockScrollbar(G("OpenMailScrollFrameScrollBar"))

  U.PostHookScript(openFrame, "OnShow", ReapplyOpenMailText)
end

-- ---------------------------------------------------------------------------
-- Build / reapply
-- ---------------------------------------------------------------------------
local function Reapply()
  U.StripStockTextures(frame)
  if panel then panel:Show() end

  ReapplyInboxHeader()
  ReapplySendHeader()
  StyleInboxRows()
end

local function BuildFrame()
  frame = G("MailFrame")
  if not frame then
    U.Debug("mail: native frame unavailable")
    return false
  end

  U.StripStockTextures(frame)

  panel = U.CreatePanel(frame, {
    name = "UnrealUIMailPanel",
    width = 100,
    height = 100,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 40)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 8, 32, 10, 40)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  -- WORKING_SOURCE (UnrealPfUI): the vanilla branch's close control is
  -- InboxCloseButton, which closes the whole MailFrame -- there is no
  -- separate MailFrameCloseButton on this client-shape.
  U.StyleStockCloseButton(G("InboxCloseButton"), panel, -6, -6)
  U.MakeWindowDraggable("mail", frame, { headerInset = 56 })

  StyleTabs()

  ReapplyInboxHeader()
  StyleInboxRows()
  StylePageControls()

  ReapplySendHeader()
  StyleSendPackageButton()
  StyleSendButtons()
  StyleSendScrollbar()

  BuildOpenMailFrame()

  -- Native InboxFrame_Update repopulates each row's sender/subject/date text
  -- on page turns and new mail, undoing the font/colour pass the same way
  -- modules/merchant.lua's MerchantFrame_UpdateMerchantInfo hook and
  -- modules/trainer.lua's ClassTrainer_Update hook exist to counter.
  U.PostHookGlobal("InboxFrame_Update", function()
    StyleInboxRows()
  end)

  -- WORKING_SOURCE (UnrealPfUI hooks the same global): OpenMailFrame:Show()
  -- only fires OnShow on the hidden->shown transition, so clicking a
  -- different inbox row while it is already open would leave the previous
  -- letter's styled title/body behind otherwise -- InboxFrame_OnClick is the
  -- actual native trigger for "open this letter", open or not.
  U.PostHookGlobal("InboxFrame_OnClick", function()
    ReapplyOpenMailText()
  end)

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

-- USER_CONFIRMED_INGAME (modules/trainer.lua): a lazily-created stock frame
-- can be unresolvable at OnEnable time on this client. Mail shares that risk
-- -- UnrealPfUI's own skin gates its vanilla-branch setup behind MAIL_SHOW
-- and HookAddonOrVariable("Mail", ...) rather than assuming the frame exists
-- up front -- so this retries from whichever of MAIL_SHOW or ADDON_LOADED
-- actually fires first, the same shape as trainer.lua's pendingEvents.
local pendingEvents = { "ADDON_LOADED", "MAIL_SHOW" }

local function TryBuild()
  if BuildFrame() then
    local i
    for i = 1, table.getn(pendingEvents) do
      U.UnregisterEvent(pendingEvents[i], TryBuild)
    end
    return true
  end
  return false
end

function ML:OnEnable()
  if U.ThemeStyleUsesNativeChrome() then return end
  if TryBuild() then return end

  U.RegisterEvent("ADDON_LOADED", TryBuild)
  U.RegisterEvent("MAIL_SHOW", TryBuild)
end
