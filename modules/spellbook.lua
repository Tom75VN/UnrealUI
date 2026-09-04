-- unrealUI :: modules/spellbook.lua
--
-- Dark native Spellbook skin matching the Quest Log treatment. Spell buttons,
-- paging, skill-line tabs, drag/click behavior and the native update function
-- remain in charge; only their presentation is changed.
--
-- The window also owns two behaviour features, the "Highest rank" filter and
-- the "Not on action bars" hint, both deliberately theme-independent: chrome
-- is theme-bound, a spellbook filter and a spellbook hint are not, so both are
-- installed under Classic WoW / Modern WoW native chrome as well as under the
-- Modern skin. See the rank and missing tables below.

local U = UnrealUI
local M = U.media
local SB = U.RegisterModule("spellbook")

local SPELL_GOLD = { 1.00, 0.82, 0.00, 1.00 }
local SPELL_WHITE = { 1.00, 1.00, 1.00, 1.00 }

local frame, panel
local config

-- Highest-rank filter.
--
-- Everything the feature needs lives on this one table so the module keeps its
-- top-level local budget small (see .claude/rules/unreal-ui.md).
--
-- The whole filter hangs off a single native entry point, SpellBook_GetSpellID,
-- which the client's own spell buttons call to turn a 1..SPELLS_PER_PAGE button
-- index into a spellbook slot. Replacing that mapping means the native update,
-- click, drag and tooltip paths all keep working and only see the filtered
-- slots -- nothing here re-implements a spell button.
--
-- BEHAVIOR_VERIFIED (knowledge.json /
-- spellbook.rank_filter_native_mapping_unverified, behavior.json /
-- spellbookrank.watch.v2): this client's real chain is Vanilla's
-- SpellButton_OnEvent -> SpellButton_UpdateButton -> SpellBook_GetSpellID ->
-- GetSpellName, and it honours the wrapper's return value for icon, name,
-- rank, tooltip, click and drag. Buttons carry fixed positional ids 1..12.
--
-- The one place this client is NOT Vanilla-shaped is the repaint, which has no
-- frame-level entry point at all -- see rank.Refresh. Every entry point below
-- is still capability-checked and the filter switches itself off -- falling
-- through to the unmodified native mapping -- rather than guessing.
local rank = {
  -- Installed and validated. False keeps the checkbox out of the window
  -- entirely instead of offering a control that cannot work.
  active = false,
  native = nil,
  -- Filtered slot list for one skill line, cached by book/offset/count.
  -- `set` is the same list in lookup form, for rank.IsHighest.
  key = nil,
  slots = nil,
  set = nil,
  -- Page state recovered from the native mapping on the last resolve, and
  -- whether that resolve actually got that far. Paging is only taken over
  -- while it did: a filter that is falling through must leave the client its
  -- own arrows rather than stranding the player on a page they cannot leave.
  page = 1,
  pages = 1,
  mapped = false,
  -- Whichever toggle this theme built: unrealUI's shared checkbox control
  -- under the Modern skin, the client's own CheckButton under native chrome.
  -- Only ever tested for existence, so the two shapes are interchangeable.
  box = nil,
  -- The toggle's own text region, whichever shape built it. The "not on
  -- action bars" toggle anchors to its right edge, so the two controls sit
  -- side by side without either theme needing to know the other's metrics.
  label = nil,
  -- Native-chrome toggle only. The client's checkbox keeps its own art at its
  -- own size; the Modern skin uses the shared component's 14 instead.
  NATIVE_SIZE = 20,
  -- Frame levels above SpellBookFrame for the native checkbox, so its mark
  -- draws over the window's other children rather than under them.
  LEVEL_LIFT = 5,
  LABEL_WIDTH = 100,
}

local function G(name)
  return U.G(name)
end

local function StripDecorations()
  if frame then U.StripStockTextures(frame) end
end

local function SetSpellFont(object, size, color)
  U.SetStockFont(object, size or M.fontSize.normal, color or SPELL_WHITE)
end

local function SpellCount()
  return tonumber(G("SPELLS_PER_PAGE")) or 12
end

local function SkillTabCount()
  return tonumber(G("MAX_SKILLLINE_TABS")) or 8
end

local function StyleSpellButton(index, refreshOnly)
  local button = G("SpellButton" .. index)
  local icon = G("SpellButton" .. index .. "IconTexture")
  if not button then return end

  if refreshOnly then
    U.RefreshStockButtonArtwork(button, icon)
  else
    U.StyleStockButton(button, { icon = icon })
  end

  SetSpellFont(G("SpellButton" .. index .. "SpellName"),
               M.fontSize.normal, SPELL_GOLD)
  SetSpellFont(G("SpellButton" .. index .. "SubSpellName"),
               M.fontSize.small, SPELL_WHITE)

  local auto = G("SpellButton" .. index .. "AutoCastable")
  if auto then
    pcall(auto.SetTexture, auto, "Interface\\Buttons\\UI-AutoCastableOverlay")
    pcall(auto.SetAlpha, auto, 1)
  end

  local highlight = G("SpellButton" .. index .. "Highlight")
  if highlight and not highlight.uuiSpellHighlightSuppressed then
    U.HideRegion(highlight)
    pcall(function()
      highlight.uuiSpellHighlightSuppressed = true
      highlight.SetTexture = function() return end
    end)
  end
end

local function StyleSkillTabs()
  local first = G("SpellBookSkillLineTab1")
  if first and panel then
    pcall(function()
      first:ClearAllPoints()
      first:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, -30)
    end)
  end

  local previous, i = nil, nil
  for i = 1, SkillTabCount() do
    local button = G("SpellBookSkillLineTab" .. i)
    if button then
      local icon
      if button.GetNormalTexture then
        local ok, texture = pcall(button.GetNormalTexture, button)
        if ok then icon = texture end
      end

      U.StyleStockButton(button, { icon = icon })
      pcall(button.SetScale, button, 1.1)
      if icon then pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93) end

      if previous then
        pcall(function()
          button:ClearAllPoints()
          button:SetPoint("TOP", previous, "BOTTOM", 0, -3)
        end)
      end
      previous = button
    end
  end
end

local function StyleBookTabs()
  local first = G("SpellBookFrameTabButton1")
  if first and panel then
    pcall(function()
      first:ClearAllPoints()
      first:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 1, -3)
    end)
  end

  local previous, i = nil, nil
  for i = 1, 3 do
    local tab = G("SpellBookFrameTabButton" .. i)
    if tab then
      if previous then
        pcall(function()
          tab:ClearAllPoints()
          tab:SetPoint("LEFT", previous, "RIGHT", 3, 0)
        end)
      end
      U.StyleStockTab(tab)
      previous = tab
    end
  end
end

-- ---------------------------------------------------------------------------
-- Highest-rank filter
-- ---------------------------------------------------------------------------

-- Resolved lazily: the module is enabled before the player ever opens the
-- window, and under native-chrome themes BuildFrame never runs, so `frame` may
-- legitimately be nil here.
local function BookFrame()
  return frame or G("SpellBookFrame")
end

-- The book the window is currently showing. Returned as nil when the client
-- does not expose it, which disables filtering rather than risking pet spells
-- being resolved against the player book.
function rank.BookType()
  local book = BookFrame()
  local value = book and book.bookType
  if type(value) ~= "string" or value == "" then return nil end
  return value
end

-- Slot range of the book section that `slot` belongs to, plus the 1-based tab
-- index it was found in. The selected skill line is derived from the slot
-- itself rather than read from a SpellBookFrame field, so no assumption is
-- made about the client's field names.
--
-- The tab index is a third return rather than a second walk of the same tabs:
-- the bar hint needs it to tell a class ability from a profession, and every
-- existing caller keeps working because it only ever asked for two values.
function rank.Range(bookType, slot)
  -- Anything that is not the player book is the pet book, which has no skill
  -- lines. The token itself is read from the client rather than hardcoded.
  local playerBook = G("BOOKTYPE_SPELL")
  if type(playerBook) ~= "string" or playerBook == "" then playerBook = "spell" end

  if bookType ~= playerBook then
    local pet = G("HasPetSpells")
    if type(pet) ~= "function" then return nil end
    local ok, count = pcall(pet)
    if not ok or type(count) ~= "number" then return nil end
    return 0, count
  end

  local tabCount, tabInfo = G("GetNumSpellTabs"), G("GetSpellTabInfo")
  if type(tabCount) ~= "function" or type(tabInfo) ~= "function" then
    return nil
  end

  local countOk, tabs = pcall(tabCount)
  if not countOk or type(tabs) ~= "number" then return nil end

  local i
  for i = 1, tabs do
    local ok, name, texture, offset, numSpells = pcall(tabInfo, i)
    if ok and type(offset) == "number" and type(numSpells) == "number"
       and slot > offset and slot <= offset + numSpells then
      return offset, numSpells, i
    end
  end
  return nil
end

-- Rank number carried by a spellbook subtext, or nil when it holds no number
-- at all -- "Passive", "Racial Passive" and the profession tiers all land here.
--
-- The digits are read positionally instead of being matched against a
-- localized "Rank %d" template: the template global is not something this
-- client is known to expose, every locale unrealUI ships writes the rank with
-- Arabic numerals, and string.match does not exist on this client's Lua, so
-- string.find's capture is the portable read.
--
-- The read itself moved to U.SpellRankNumber (core/compat.lua) once
-- modules/castbar.lua needed the same answer for the rank-dependent aura
-- durations. This stays as the name the rest of the module calls.
function rank.Number(sub)
  return U.SpellRankNumber(sub)
end

-- Slots to actually display for one book section, highest rank only.
--
-- Ranks of one spell occupy consecutive slots, but NOT reliably in ascending
-- order on this client: /uui sb ranks measured a priest whose Shadow Magic tab
-- listed Shadow Word: Pain as "Rank 2" at slot 27 and "Rank 1" at slot 28,
-- while Lesser Heal (18-20) and Smite (23-24) in the same book ascended
-- normally. Taking the last entry of a run therefore showed Rank 1 as the
-- highest rank. The run is now resolved by comparing the rank numbers
-- themselves, and only falls back to "last entry wins" for a run that carries
-- no rank numbers at all, which is what it always did for those.
--
-- Collapsing only consecutive runs is kept: it stops two genuinely different
-- entries that happen to share a name from being merged, and the measurement
-- above found every rank of a spell adjacent (holes=0, one run per spell).
function rank.List(bookType, offset, numSpells)
  local key = bookType .. ":" .. offset .. ":" .. numSpells
  if rank.key == key and rank.slots then return rank.slots end

  local spellName = G("GetSpellName")
  if type(spellName) ~= "function" then return nil end

  -- `best` is the rank number of the slot currently standing as the run's
  -- highest, so a run is resolved in one pass without re-reading its slots.
  local list, last, best, i = {}, nil, nil, nil
  for i = offset + 1, offset + numSpells do
    local ok, name, sub = pcall(spellName, i, bookType)
    if not ok or type(name) ~= "string" or name == "" then break end

    local number = rank.Number(sub)
    if name == last then
      local take
      if number and best then
        take = number > best
      elseif number then
        -- The run's first numbered entry outranks an unnumbered incumbent: a
        -- readable rank is better evidence than position.
        take = true
      else
        take = not best
      end

      if take then
        list[table.getn(list)] = i
        best = number or best
      end
    else
      table.insert(list, i)
      last, best = name, number
    end
  end

  if table.getn(list) == 0 then return nil end

  -- The same list in lookup form, so rank.IsHighest can answer for one slot
  -- without walking the array once per spell button.
  local set, n = {}, nil
  for n = 1, table.getn(list) do set[list[n]] = true end

  rank.key, rank.slots, rank.set = key, list, set
  return list
end

function rank.Invalidate()
  rank.key, rank.slots, rank.set = nil, nil, nil
end

-- Whether `slot` holds the highest rank of its spell, as the same consecutive
-- run collapse rank.List already performs. nil means the client did not give
-- up enough to tell, which callers must treat as "do not act", never as false.
function rank.IsHighest(bookType, slot)
  if type(bookType) ~= "string" or type(slot) ~= "number" then return nil end

  local offset, numSpells = rank.Range(bookType, slot)
  if not offset then return nil end
  if not rank.List(bookType, offset, numSpells) or not rank.set then
    return nil
  end
  return rank.set[slot] and true or false
end

-- The slot handed back for a button past the end of a short final page. Just
-- outside the client's own declared spell bound, so SpellButton_UpdateButton
-- finds nothing there and hides the button. MAX_SPELLS is read from the client
-- (1024 here, behavior.json / spellbookrank.book_type.v1) rather than replaced
-- with an arbitrary large number, keeping the value inside the range the
-- client's own bounds checks reason about.
function rank.Empty()
  local max = tonumber(G("MAX_SPELLS"))
  if max then return max + 1 end
  return 100000
end

-- Filtered slot for one spell button, or nil to fall through to the client's
-- own mapping.
function rank.Resolve(index)
  rank.mapped = false

  local native = rank.native
  if type(native) ~= "function" then return nil end
  if type(index) ~= "number" then return nil end
  if not config or not config.highestRankOnly then return nil end

  local bookType = rank.BookType()
  if not bookType then return nil end

  -- The current page is read back out of the native mapping instead of out of
  -- a page global, so the client stays free to compute it however it likes.
  -- The two probes also verify the mapping is the linear, contiguous one this
  -- filter depends on; anything else disables the filter for this pass.
  local firstOk, first = pcall(native, 1)
  local secondOk, second = pcall(native, 2)
  if not firstOk or not secondOk then return nil end
  if type(first) ~= "number" or second ~= first + 1 then return nil end

  local offset, numSpells = rank.Range(bookType, first)
  if not offset then return nil end

  local list = rank.List(bookType, offset, numSpells)
  if not list then return nil end

  local perPage = SpellCount()
  local page = math.floor((first - 1 - offset) / perPage) + 1
  local pages = math.ceil(table.getn(list) / perPage)
  if pages < 1 then pages = 1 end
  if page < 1 then page = 1 end
  -- Fewer pages survive the filter than the client thinks exist, so a page
  -- number left over from the unfiltered book shows the last filtered page
  -- rather than an empty one. Paging back converges on the real page.
  if page > pages then page = pages end

  rank.page, rank.pages = page, pages
  rank.mapped = true
  return list[(page - 1) * perPage + index] or rank.Empty()
end

-- The Modern skin replaces the arrow art with an owned glyph, so the native
-- disabled texture is not what the player sees. The glyph carries the disabled
-- state instead, and follows the button whether the client or this filter set
-- it.
local function SyncArrowGlyph(button)
  local glyph = button and button.uuiArrowGlyph
  if not glyph then return end

  local enabled = true
  if button.IsEnabled then
    local ok, value = pcall(button.IsEnabled, button)
    if ok then enabled = value and true or false end
  end
  pcall(glyph.SetTextColor, glyph,
        M.Unpack(enabled and M.color.text or M.color.textDim))
end

local function SetArrow(button, enabled)
  if not button then return end
  if enabled then
    pcall(button.Enable, button)
  else
    pcall(button.Disable, button)
  end
  SyncArrowGlyph(button)
end

-- The client sizes its page arrows and page number from the unfiltered spell
-- count, so both are corrected after every native update.
function rank.UpdatePaging()
  if not rank.active then return end

  local prev = G("SpellBookPrevPageButton")
  local forward = G("SpellBookNextPageButton")

  -- The client owns the arrows outright unless the filter is genuinely
  -- remapping slots: re-enabling them here would defeat its own first/last
  -- page handling, and disabling them on a filter that is falling through
  -- would stand the player on a page they cannot page off. Only the owned
  -- glyph is kept in step.
  if not config or not config.highestRankOnly or not rank.mapped then
    SyncArrowGlyph(prev)
    SyncArrowGlyph(forward)
    return
  end

  SetArrow(prev, rank.page > 1)
  SetArrow(forward, rank.page < rank.pages)

  -- Swap the number the client just wrote for the filtered one and keep its
  -- own wording, rather than replacing "Page 1" with a bare "1". The client
  -- rewrites this on every update and the substitution is idempotent, so it
  -- survives both the update hook and the ticker.
  local text = G("SpellBookPageText")
  if text and text.GetText then
    local readOk, current = pcall(text.GetText, text)
    if readOk and type(current) == "string" and current ~= "" then
      local swapped = string.gsub(current, "%d+", tostring(rank.page), 1)
      pcall(text.SetText, text, swapped)
    end
  end
end

-- Redraws the open window after the checkbox changes.
--
-- This client repaints spell buttons only through SpellButton_UpdateButton,
-- reached from each button's own OnEvent -- never from a frame-level updater.
-- Driving SpellBookFrame_Update() produces zero GetSpellName/GetSpellTexture
-- calls and leaves every button untouched, and SpellBook_Update,
-- SpellBook_UpdateSpells and SpellBookFrame_UpdateSpells do not exist here at
-- all (behavior.json / spellbookrank.redraw.v2, .resolution.v1, .lua_surface.v2
-- -- BEHAVIOR_VERIFIED). Calling the frame updater, which is what this used to
-- do, therefore changed the setting and repainted nothing: the filter's own
-- page indicator moved while every icon stayed put.
--
-- SpellButton_UpdateButton takes its button from the global `this`, the
-- Vanilla convention, so `this` is set per button and restored afterwards.
-- Measured at 12 repaints for 12 buttons.
function rank.Refresh()
  rank.Invalidate()

  local updater = G("SpellButton_UpdateButton")
  if type(updater) == "function" then
    local previous = G("this")
    local i
    for i = 1, SpellCount() do
      local button = G("SpellButton" .. i)
      if button then
        U.SetG("this", button)
        pcall(updater)
      end
    end
    U.SetG("this", previous)
  else
    U.Debug("spellbook: SpellButton_UpdateButton unavailable, no rank redraw")
  end

  rank.UpdatePaging()
end

-- Both toggles sit in the same place: above the first spell button, aligned
-- with the left spell column. SpellButton1 is the anchor rather than the
-- window, because the Modern skin insets its own panel inside SpellBookFrame
-- while the native themes do not, whereas the spell buttons sit in the same
-- place under both. The strip above the first row is also the only part of the
-- page top that never holds a spell button.
--
-- Returned as a multiple value so each builder can feed it straight into the
-- SetPoint shape its own control uses.
function rank.AnchorArgs()
  local first = G("SpellButton1")
  if first then return "BOTTOMLEFT", first, "TOPLEFT", -2, 2 end
  return "TOPLEFT", panel or BookFrame(), "TOPLEFT", 12, -34
end

-- Applies the toggle's stored state to the config and redraws. Shared so the
-- two controls differ only in their chrome, never in their behaviour.
function rank.Commit(value)
  config.highestRankOnly = value and true or false
  rank.Refresh()
end

-- Native-chrome themes keep the client's own checkbox art, so the only
-- adjustment made here is draw order. The checkbox is a child of
-- SpellBookFrame alongside the spell buttons, and its mark otherwise paints
-- underneath them.
--
-- Frame:SetFrameLevel/GetFrameLevel and LayeredRegion:SetDrawLayer are
-- documented on this client. CheckButton:GetCheckedTexture is NOT -- the
-- documented CheckButton surface has GetChecked/SetChecked and
-- SetNormalTexture but no checked-texture accessor -- so lifting the mark's
-- own layer is attempted and never depended on. The frame level alone puts the
-- whole control, mark included, above the window's other children.
function rank.RaiseNativeMark(box)
  if not box then return end

  local parent
  if box.GetParent then
    local parentOk, value = pcall(box.GetParent, box)
    if parentOk then parent = value end
  end

  if parent and parent.GetFrameLevel and box.SetFrameLevel then
    local levelOk, level = pcall(parent.GetFrameLevel, parent)
    if levelOk and tonumber(level) then
      pcall(box.SetFrameLevel, box, level + rank.LEVEL_LIFT)
    end
  end

  -- OVERLAY is the highest ordinary texture layer, so the mark sits above the
  -- checkbox's own normal and pushed art rather than behind it.
  if box.GetCheckedTexture then
    local markOk, mark = pcall(box.GetCheckedTexture, box)
    if markOk and mark and mark.SetDrawLayer then
      pcall(mark.SetDrawLayer, mark, "OVERLAY")
    end
  end
end

function rank.AttachTooltip(box)
  if not box or box.uuiRankTooltipAttached then return end
  box.uuiRankTooltipAttached = true

  U.PostHookScript(box, "OnEnter", function()
    local tooltip = G("GameTooltip")
    if not tooltip then return end
    pcall(tooltip.SetOwner, tooltip, box, "ANCHOR_RIGHT")
    pcall(tooltip.SetText, tooltip, U.L("SPELLBOOK_HIGHEST_RANK_TOOLTIP"))
    pcall(tooltip.Show, tooltip)
  end)
  U.PostHookScript(box, "OnLeave", function()
    local tooltip = G("GameTooltip")
    if tooltip then pcall(tooltip.Hide, tooltip) end
  end)
end

function rank.BuildNativeToggle(book)
  local ok, box = pcall(CreateFrame, "CheckButton", "UnrealUISpellBookRank",
                        book, "UICheckButtonTemplate")
  if not ok or not box then return nil end

  box:SetPoint(rank.AnchorArgs())
  pcall(box.SetWidth, box, rank.NATIVE_SIZE)
  pcall(box.SetHeight, box, rank.NATIVE_SIZE)

  local label = G("UnrealUISpellBookRankText")
  if label then
    label:SetText(U.L("SPELLBOOK_HIGHEST_RANK"))
    -- Re-anchored rather than left on the template default, so the gap follows
    -- the box size this theme actually applied.
    pcall(function()
      label:ClearAllPoints()
      label:SetPoint("LEFT", box, "RIGHT", 3, 0)
    end)
    rank.label = label
  end

  rank.RaiseNativeMark(box)
  rank.AttachTooltip(box)

  box:SetChecked(config.highestRankOnly and true or nil)
  box:SetScript("OnClick", function()
    local value = not config.highestRankOnly
    box:SetChecked(value and true or nil)
    -- The client repaints its own checkbox art on click, so re-assert the draw
    -- order each time rather than only at build.
    rank.RaiseNativeMark(box)
    rank.Commit(value)
  end)

  return box
end

function rank.BuildModernToggle(book)
  local ok, control = pcall(U.CreateCheckbox, book, {
    name = "UnrealUISpellBookRank",
    text = U.L("SPELLBOOK_HIGHEST_RANK"),
    value = config.highestRankOnly,
    textWidth = rank.LABEL_WIDTH,
    onChange = rank.Commit,
  })
  if not ok or not control then return nil end

  control.SetPoint(rank.AnchorArgs())
  rank.label = control.label
  rank.AttachTooltip(control.box)
  return control
end

-- The Modern skin uses unrealUI's shared checkbox control outright
-- (rules/unreal-ui-design.md: reuse the shared component, never a local
-- variant). Native-chrome themes keep the client's own CheckButton, because
-- there the whole window is stock art and a flat unrealUI square would be the
-- one foreign element on it.
function rank.BuildToggle()
  local book = BookFrame()
  if not book or rank.box then return end

  if U.ThemeStyleUsesNativeChrome() then
    rank.box = rank.BuildNativeToggle(book)
  else
    rank.box = rank.BuildModernToggle(book)
  end

  if not rank.box then
    U.Debug("spellbook: rank toggle unavailable")
    return
  end
  U.AddWindowDragInteractiveFrame(book, rank.box.box or rank.box)
end

function rank.Install()
  if rank.active then return end

  local native = G("SpellBook_GetSpellID")
  if type(native) ~= "function" then
    U.Debug("spellbook: SpellBook_GetSpellID unavailable, rank filter omitted")
    return
  end

  local wrapper = function(index)
    local filtered = rank.Resolve(index)
    if filtered then return filtered end
    return native(index)
  end

  rank.native = native
  U.SetG("SpellBook_GetSpellID", wrapper)
  if G("SpellBook_GetSpellID") ~= wrapper then
    U.Debug("spellbook: could not replace SpellBook_GetSpellID")
    rank.native = nil
    return
  end
  rank.active = true

  rank.BuildToggle()

  -- Paging is corrected from the native update hook where that global exists,
  -- and from the shared ticker regardless: the client is not required to route
  -- every spell button refresh through a function unrealUI can hook, and a
  -- wrong arrow state is the one part of this feature a stale frame would show.
  U.PostHookGlobal("SpellBook_Update", rank.UpdatePaging)
  U.PostHookGlobal("SpellBookFrame_Update", rank.UpdatePaging)

  U.RegisterUpdate("spellbook.rank-paging", 0.2, function()
    local book = BookFrame()
    if not book or not book.IsShown then return end
    local shownOk, shown = pcall(book.IsShown, book)
    if not shownOk or not shown then return end

    -- Also the retry for the checkbox: the window is provably built by the
    -- time it is first shown, even if it was not at PLAYER_LOGIN.
    if not rank.box then rank.BuildToggle() end
    rank.UpdatePaging()
  end)

  U.RegisterEvent("SPELLS_CHANGED", rank.Invalidate)
  U.RegisterEvent("LEARNED_SPELL_IN_TAB", rank.Invalidate)
end

-- ---------------------------------------------------------------------------
-- "Not on action bars" hint
--
-- Outlines a class ability in the book when its highest rank is not sitting
-- on any of the player's action slots. Only the highest rank is ever a
-- candidate: a lower rank is not expected on a bar, so marking one would flag
-- a spell the player has already placed at the rank they actually cast.
-- Whether the rank filter above happens to be showing that highest rank is
-- irrelevant -- the hint reads the book, not the page.
--
-- Class abilities only, and that scope is the difference between a signal and
-- a permanent decoration: marking everything droppable put nine standing
-- marks on the General tab -- Attack, Shoot, Perception, three profession
-- headers and the items they grant -- against one real one. The General tab
-- is skipped entirely; see the tab test in Wanted.
--
-- Like the rank filter this is behaviour rather than chrome, so it installs
-- under every theme and draws its own accent outline on an owned overlay
-- frame, instead of recolouring a button border that only the Modern skin
-- owns and that hover already drives.
--
-- What the client will not tell us: which spell sits in an action slot. There
-- is no GetActionInfo here at all (query_compat.py: no match), so the slot is
-- read the way UnrealPfUI reads it on this same client -- a private
-- GameTooltip armed with SetAction, whose first line carries the spell name on
-- the left and the rank subtext on the right. WORKING_SOURCE, not runtime
-- verification: UnrealPfUI libs/libcast.lua's UseAction hook and
-- modules/hunterbar.lua both depend on that first line, and libs/libspell.lua
-- compares that rank string against GetSpellName's own second return -- which
-- is what lets the comparison below stay locale-free instead of parsing
-- "Rank %d".
--
-- Every failure degrades towards silence rather than towards noise: an
-- unreadable slot, an unreadable rank, or a scan that resolved no spell at all
-- leaves spells unmarked instead of marking every one of them.
-- ---------------------------------------------------------------------------
local missing = {
  -- Installed and validated, same meaning as rank.active: false keeps the
  -- checkbox out of the window rather than offering a dead control.
  active = false,
  box = nil,

  -- Action-slot index, rebuilt whenever `dirty` is set. Three tables so an
  -- unreadable rank stays distinguishable from a missing one:
  --   any      -- name is on some slot, at some or unknown rank
  --   ranked   -- name plus that exact rank subtext is on some slot
  --   unranked -- name is on some slot whose rank could not be read
  any = {},
  ranked = {},
  unranked = {},
  built = false,
  -- Two flags, not one, and they are cleared by different code. `dirty` means
  -- the index needs rebuilding and is cleared by the rebuild; `remark` means
  -- every overlay needs re-testing and is cleared only by the ticker that
  -- re-tests them. Sharing one flag was a real bug: a single button repainting
  -- for its own reasons ran the lazy rebuild, cleared the flag, and re-marked
  -- only itself -- so the ticker saw nothing to do and the other eleven
  -- buttons kept the marks the previous index had given them.
  dirty = true,
  remark = true,
  -- Cleared when a scan found actions but resolved no spell from any of them,
  -- which is the shape a broken tooltip read takes. Marking every spell in the
  -- book is a much worse failure than marking none, so that case switches the
  -- hint off until a later scan succeeds.
  usable = true,

  scanner = nil,
  scannerBuilt = false,
  SCANNER = "UnrealUISpellBookActionScanner",

  -- Documented as 1-119; the extra slot is harmless because every read is
  -- bounds-checked by HasAction first, and UnrealPfUI sweeps 1-120 here.
  MAX_SLOTS = 120,
  -- Spellbook tabs at or below this one are not class abilities. Tab 1 is
  -- General; every tab after it is a class skill line.
  GENERAL_TAB = 1,
  -- Drawn one unit inside the button, so the ring stays readable as its own
  -- mark next to the accent hover border the Modern skin puts on the edge.
  INSET = 1,
  CLEAR = { 0, 0, 0, 0 },
  LABEL_WIDTH = 130,
  -- Stable schema id for the saved /uui sb and /uui sb trace evidence. The
  -- first trace only recorded the spell resolved through our own mapper, which
  -- made a mapper/render/layout disagreement look self-consistent. v2 first
  -- recorded those identities independently; v3 keeps them while storing the
  -- static layout once instead of inflating every dynamic snapshot.
  PROBE_VERSION = "spellbook.bar_hint.visual_mapping.v3",
  MAX_TOOLTIP_LINES = 12,
}

function missing.Invalidate()
  missing.dirty = true
end

-- Private tooltip, never shown to the player and never the shared GameTooltip
-- -- the same shape modules/status.lua and modules/auras.lua already use for
-- their own scans.
function missing.Scanner()
  if missing.scannerBuilt then return missing.scanner end
  missing.scannerBuilt = true

  local ok, tip = pcall(CreateFrame, "GameTooltip", missing.SCANNER, nil,
                        "GameTooltipTemplate")
  if not ok or not tip then
    U.Debug("spellbook: action scanner unavailable, bar hint inactive")
    return nil
  end

  pcall(tip.SetOwner, tip, G("WorldFrame") or UIParent, "ANCHOR_NONE")
  missing.scanner = tip
  return tip
end

-- One tooltip line region by global name. `guard` applies the visibility test
-- UnrealPfUI's libtipscan uses: ClearLines resets the line count but a
-- fontstring keeps the text a previous scan left on it, so a right-hand line
-- that is not part of the tooltip just built must not be read back as this
-- action's rank. The left line is read unguarded, which is the sequence
-- modules/auras.lua's scanner has verified on this client.
function missing.LineText(suffix, guard)
  local name = missing.SCANNER .. suffix

  local region = nil
  if _G then region = _G[name] end
  if not region then region = U.G(name) end
  if not region or type(region.GetText) ~= "function" then return nil end

  if guard and type(region.IsVisible) == "function" then
    local seenOk, seen = pcall(region.IsVisible, region)
    if seenOk and not seen then return nil end
  end

  local ok, text = pcall(region.GetText, region)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  return text
end

-- Spell name and rank subtext for one action slot, or nil for a slot this
-- client will not describe.
function missing.ScanSlot(slot)
  local tip = missing.Scanner()
  if not tip or type(tip.SetAction) ~= "function" then return nil end

  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, G("WorldFrame") or UIParent, "ANCHOR_NONE")
  if not pcall(tip.SetAction, tip, slot) then return nil end

  local name = missing.LineText("TextLeft1", false)
  if not name then return nil end
  return name, missing.LineText("TextRight1", true)
end

-- The same read, shared. modules/hots.lua has to know which spell an action
-- press just used: this client fires SPELLCAST_STOP with no arguments at all
-- (events.json, 40 captures, lastArguments count 0) and SPELLCAST_START only
-- for a spell with a cast time, so an instant heal-over-time is identifiable
-- from the action slot or not at all.
--
-- knowledge.json / spellbook.action_slot_spell_identity_tooltip_unverified
-- (BEHAVIOR_VERIFIED, USER_CONFIRMED_INGAME): there is no GetActionInfo on
-- this client and the SetAction tooltip's first line is the localized spell
-- name. GetActionText names a macro, whose body is not readable, so a macro
-- slot is deliberately refused rather than credited to whatever its tooltip
-- happens to show.
function U.ActionSlotSpellName(slot)
  slot = tonumber(slot)
  if not slot then return nil end

  local has = G("HasAction")
  if type(has) == "function" then
    local ok, present = pcall(has, slot)
    if ok and not present then return nil end
  end

  local text = G("GetActionText")
  if type(text) == "function" then
    local ok, macro = pcall(text, slot)
    if ok and type(macro) == "string" and macro ~= "" then return nil end
  end

  return missing.ScanSlot(slot)
end

-- ---------------------------------------------------------------------------
-- Independent diagnostic readback
--
-- The mark calculation and the old trace both called SpellBook_GetSpellID, so
-- they could only agree with each other. These helpers also read the native
-- button's rendered label/icon and the real frame/overlay geometry. A shifted
-- outline, a stale native label and a wrong mapper result therefore leave
-- different evidence instead of the same circular "button N means spell X".
-- All stored values are primitives; no frame userdata can leak into
-- SavedVariables.
-- ---------------------------------------------------------------------------

function missing.Stored(value)
  if value == nil then return "<nil>" end
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then
    return value
  end
  return missing.ObjectName(value)
end

function missing.ObjectName(object)
  if object == nil then return "<nil>" end
  if type(object) == "string" then return object end

  local fn = object.GetName
  if type(fn) == "function" then
    local ok, name = pcall(fn, object)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return tostring(object)
end

function missing.Read(object, method)
  if not object then return "<nil object>" end
  local fn = object[method]
  if type(fn) ~= "function" then return "<no " .. method .. ">" end
  local ok, value = pcall(fn, object)
  if not ok then return "<error>" end
  return missing.Stored(value)
end

function missing.Points(object)
  local out = {}
  if not object or type(object.GetNumPoints) ~= "function" or
     type(object.GetPoint) ~= "function" then
    return out
  end

  local countOk, count = pcall(object.GetNumPoints, object)
  count = countOk and tonumber(count) or nil
  if not count then return out end

  local i
  for i = 1, count do
    local ok, point, relative, relativePoint, x, y =
      pcall(object.GetPoint, object, i)
    table.insert(out, {
      index = i,
      ok = ok and true or false,
      point = missing.Stored(point),
      relative = missing.ObjectName(relative),
      relativePoint = missing.Stored(relativePoint),
      x = missing.Stored(x),
      y = missing.Stored(y),
    })
  end
  return out
end

function missing.ObjectState(object)
  if not object then return { exists = false } end
  local parent = nil
  if type(object.GetParent) == "function" then
    local ok, value = pcall(object.GetParent, object)
    if ok then parent = value end
  end
  return {
    exists = true,
    name = missing.ObjectName(object),
    objectType = missing.Read(object, "GetObjectType"),
    id = missing.Read(object, "GetID"),
    parent = missing.ObjectName(parent),
    shown = missing.Read(object, "IsShown"),
    visible = missing.Read(object, "IsVisible"),
    alpha = missing.Read(object, "GetAlpha"),
    strata = missing.Read(object, "GetFrameStrata"),
    level = missing.Read(object, "GetFrameLevel"),
    left = missing.Read(object, "GetLeft"),
    right = missing.Read(object, "GetRight"),
    top = missing.Read(object, "GetTop"),
    bottom = missing.Read(object, "GetBottom"),
    width = missing.Read(object, "GetWidth"),
    height = missing.Read(object, "GetHeight"),
    texture = missing.Read(object, "GetTexture"),
    text = missing.Read(object, "GetText"),
    points = missing.Points(object),
  }
end

function missing.SpellState(slot, bookType)
  local out = { slot = missing.Stored(slot), bookType = missing.Stored(bookType) }
  if type(slot) ~= "number" then return out end

  local spellName = G("GetSpellName")
  if type(spellName) == "function" then
    local ok, name, rankText = pcall(spellName, slot, bookType)
    out.nameOk = ok and true or false
    out.name = missing.Stored(name)
    out.rank = missing.Stored(rankText)
  else
    out.nameOk = false
    out.name = "<no GetSpellName>"
    out.rank = "<no GetSpellName>"
  end

  local spellTexture = G("GetSpellTexture")
  if type(spellTexture) == "function" then
    local ok, texture = pcall(spellTexture, slot, bookType)
    out.textureOk = ok and true or false
    out.texture = missing.Stored(texture)
  else
    out.textureOk = false
    out.texture = "<no GetSpellTexture>"
  end

  local passive = G("IsSpellPassive")
  if type(passive) == "function" then
    local ok, value = pcall(passive, slot, bookType)
    out.passiveOk = ok and true or false
    out.passive = missing.Stored(value)
  end

  local offset, count, tab = rank.Range(bookType, slot)
  out.tab = missing.Stored(tab)
  out.tabOffset = missing.Stored(offset)
  out.tabCount = missing.Stored(count)
  return out
end

-- SpellButton globals are named in visual row order, but their GetID values
-- are in spell-list order: 1,7,2,8,3,9,4,10,5,11,6,12. The native update path
-- passes GetID() to SpellBook_GetSpellID. The saved v2 trace verified that the
-- rendered label follows that ID, not the numeric suffix in "SpellButtonN".
function missing.ButtonID(button)
  if not button or type(button.GetID) ~= "function" then return nil end
  local ok, value = pcall(button.GetID, button)
  value = ok and tonumber(value) or nil
  if not value or value < 1 or value > SpellCount() then return nil end
  return value
end

function missing.ButtonState(index)
  local button = G("SpellButton" .. index)
  local bookType = rank.BookType()
  local spellIndex = missing.ButtonID(button)
  local mappedSlot, nativeSlot = nil, nil

  local mapper = G("SpellBook_GetSpellID")
  if type(mapper) == "function" and spellIndex then
    local ok, value = pcall(mapper, spellIndex)
    if ok then mappedSlot = value end
  end
  if type(rank.native) == "function" and spellIndex then
    local ok, value = pcall(rank.native, spellIndex)
    if ok then nativeSlot = value end
  end

  local overlay = button and button.uuiBarHint
  local appliedWanted = "<no overlay>"
  if overlay then appliedWanted = missing.Stored(overlay.uuiBarHintWanted) end
  local out = {
    index = index,
    spellIndex = missing.Stored(spellIndex),
    mapped = missing.SpellState(mappedSlot, bookType),
    native = missing.SpellState(nativeSlot, bookType),
    button = missing.ObjectState(button),
    rendered = {
      name = missing.ObjectState(G("SpellButton" .. index .. "SpellName")),
      sub = missing.ObjectState(G("SpellButton" .. index .. "SubSpellName")),
      icon = missing.ObjectState(G("SpellButton" .. index .. "IconTexture")),
    },
    overlay = missing.ObjectState(overlay),
    appliedWanted = appliedWanted,
    edges = {},
  }

  if overlay and overlay.uuiEdges then
    local i
    for i = 1, table.getn(overlay.uuiEdges) do
      table.insert(out.edges, missing.ObjectState(overlay.uuiEdges[i]))
    end
  end

  local wantedOk, wanted = pcall(missing.Wanted, spellIndex)
  out.wantedOk = wantedOk and true or false
  if wantedOk then
    out.wanted = wanted and true or false
  else
    out.wanted = "<error>"
  end

  local renderedName = out.rendered.name.text
  local mappedName = out.mapped.name
  if type(renderedName) == "string" and string.sub(renderedName, 1, 1) ~= "<" and
     type(mappedName) == "string" and string.sub(mappedName, 1, 1) ~= "<" then
    out.mappedMatchesRendered = renderedName == mappedName
  else
    out.mappedMatchesRendered = "<inconclusive>"
  end
  return out
end

-- Dynamic snapshots keep only values that can change during this focused
-- drag test. The complete frame/region/edge topology is saved once as
-- trace.layout. v2 repeated that topology in every snapshot and produced a
-- 3 MB SavedVariables entry for a 48-second run without adding information.
function missing.TraceObject(state)
  if not state then return { exists = false } end
  return {
    exists = state.exists,
    name = state.name,
    id = state.id,
    parent = state.parent,
    shown = state.shown,
    visible = state.visible,
    alpha = state.alpha,
    left = state.left,
    bottom = state.bottom,
    width = state.width,
    height = state.height,
    texture = state.texture,
    text = state.text,
  }
end

function missing.ButtonTraceState(index)
  local full = missing.ButtonState(index)
  return {
    index = full.index,
    spellIndex = full.spellIndex,
    mapped = full.mapped,
    native = full.native,
    button = missing.TraceObject(full.button),
    rendered = {
      name = missing.TraceObject(full.rendered.name),
      sub = missing.TraceObject(full.rendered.sub),
      icon = missing.TraceObject(full.rendered.icon),
    },
    overlay = missing.TraceObject(full.overlay),
    appliedWanted = full.appliedWanted,
    wantedOk = full.wantedOk,
    wanted = full.wanted,
    mappedMatchesRendered = full.mappedMatchesRendered,
  }
end

function missing.ActionSlotState(slot)
  local out = { slot = missing.Stored(slot), tooltip = { lines = {} } }
  local index = tonumber(slot)
  if not index then return out end

  local calls = {
    { "HasAction", "hasAction" },
    { "GetActionText", "actionText" },
    { "GetActionTexture", "actionTexture" },
    { "IsCurrentAction", "isCurrent" },
    { "IsAutoRepeatAction", "isAutoRepeat" },
    { "IsUsableAction", "isUsable" },
  }
  local i
  for i = 1, table.getn(calls) do
    local fn = G(calls[i][1])
    if type(fn) == "function" then
      local ok, value, extra = pcall(fn, index)
      out[calls[i][2] .. "Ok"] = ok and true or false
      out[calls[i][2]] = missing.Stored(value)
      out[calls[i][2] .. "Extra"] = missing.Stored(extra)
    else
      out[calls[i][2] .. "Ok"] = false
      out[calls[i][2]] = "<no " .. calls[i][1] .. ">"
    end
  end

  local cooldown = G("GetActionCooldown")
  if type(cooldown) == "function" then
    local ok, start, duration, enable = pcall(cooldown, index)
    out.cooldown = {
      ok = ok and true or false,
      start = missing.Stored(start),
      duration = missing.Stored(duration),
      enable = missing.Stored(enable),
    }
  end

  local tip = missing.Scanner()
  if not tip or type(tip.SetAction) ~= "function" then
    out.tooltip.setAction = "<no scanner>"
    return out
  end

  pcall(tip.ClearLines, tip)
  pcall(tip.SetOwner, tip, G("WorldFrame") or UIParent, "ANCHOR_NONE")
  local setOk, setValue = pcall(tip.SetAction, tip, index)
  out.tooltip.setActionOk = setOk and true or false
  out.tooltip.setAction = missing.Stored(setValue)

  local lines = 0
  if type(tip.NumLines) == "function" then
    local ok, value = pcall(tip.NumLines, tip)
    if ok and tonumber(value) then lines = tonumber(value) end
  end
  out.tooltip.numLines = lines
  if lines > missing.MAX_TOOLTIP_LINES then lines = missing.MAX_TOOLTIP_LINES end

  for i = 1, lines do
    table.insert(out.tooltip.lines, {
      index = i,
      left = missing.ObjectState(G(missing.SCANNER .. "TextLeft" .. i)),
      right = missing.ObjectState(G(missing.SCANNER .. "TextRight" .. i)),
    })
  end
  return out
end

function missing.ViewState(label, compact)
  local book = BookFrame()
  local out = {
    label = label,
    at = missing.Now and missing.Now() or 0,
    probeVersion = missing.PROBE_VERSION,
    config = {
      barHint = config and config.barHint or false,
      highestRankOnly = config and config.highestRankOnly or false,
      chrome = U.ThemeStyleUsesNativeChrome() and "native" or "modern",
    },
    book = missing.ObjectState(book),
    bookFields = {
      bookType = book and missing.Stored(book.bookType) or "<no book>",
      pageNum = book and missing.Stored(book.pageNum) or "<no book>",
      currentPage = book and missing.Stored(book.currentPage) or "<no book>",
      selectedSkillLine = book and missing.Stored(book.selectedSkillLine) or
                          "<no book>",
    },
    rank = {
      active = rank.active,
      mapped = rank.mapped,
      page = rank.page,
      pages = rank.pages,
      cacheKey = missing.Stored(rank.key),
    },
    buttons = {},
  }

  local i
  for i = 1, SpellCount() do
    if compact then
      table.insert(out.buttons, missing.ButtonTraceState(i))
    else
      table.insert(out.buttons, missing.ButtonState(i))
    end
  end
  return out
end

-- Walks every action slot once and records what is on it.
function missing.Rebuild()
  local any, ranked, unranked = {}, {}, {}
  local occupied, resolved = 0, 0
  local filledCount, macroCount = 0, 0

  -- Only while /uui sb trace is armed. The whole point of the trace is which
  -- index entries a drag added or removed, and that cannot be reconstructed
  -- after the tables have already been replaced.
  local before, scan = nil, nil
  if missing.trace.on then
    before, scan = missing.Snapshot(), {}
  end

  local hasAction, actionText = G("HasAction"), G("GetActionText")

  local slot
  for slot = 1, missing.MAX_SLOTS do
    local filled = false
    if type(hasAction) == "function" then
      local ok, value = pcall(hasAction, slot)
      filled = ok and value and true or false
    end

    if filled then
      filledCount = filledCount + 1
      -- A macro carries its own name and its body is not readable from here,
      -- so whatever it casts cannot be credited to a spell. Skipping it keeps
      -- the index honest; the cost is that a spell only ever placed inside a
      -- macro still reads as missing.
      local macro = false
      if type(actionText) == "function" then
        local ok, value = pcall(actionText, slot)
        macro = ok and type(value) == "string" and value ~= ""
      end
      if macro then macroCount = macroCount + 1 end

      if scan then
        local action = missing.ActionSlotState(slot)
        action.macro = macro and true or false
        table.insert(scan, action)
      end

      if not macro then
        occupied = occupied + 1
        local name, rankText = missing.ScanSlot(slot)
        if name then
          resolved = resolved + 1
          local key = string.lower(name)
          any[key] = true
          if type(rankText) == "string" and rankText ~= "" then
            ranked[key .. "\001" .. rankText] = true
          else
            unranked[key] = true
          end
        end
      end
    end
  end

  missing.any, missing.ranked, missing.unranked = any, ranked, unranked
  missing.built, missing.dirty = true, false

  -- Whatever the answers were, they were computed against the old index.
  -- Set here rather than at the call sites so no rebuild path can forget it.
  missing.remark = true

  local usable = not (occupied > 0 and resolved == 0)
  if usable ~= missing.usable then
    missing.usable = usable
    if not usable then
      U.Debug("spellbook: no action slot could be read, bar hint suppressed")
    end
  end

  if before then
    missing.NoteRebuild(before, scan, occupied, resolved,
                        filledCount, macroCount)
  end
end

function missing.Ensure()
  if not missing.built or missing.dirty then missing.Rebuild() end
end

-- Whether this spell already sits on a bar. Anything ambiguous answers true,
-- because a spell wrongly left unmarked is invisible while a spell wrongly
-- marked is a lie the player has to go and check.
function missing.Present(name, rankText)
  local key = string.lower(name)
  if not missing.any[key] then return false end
  if type(rankText) ~= "string" or rankText == "" then return true end
  if missing.unranked[key] then return true end
  return missing.ranked[key .. "\001" .. rankText] and true or false
end

-- Whether the spell drawn for native spell-list position `index` should be
-- marked. This is button:GetID(), not the SpellButton global-name suffix.
function missing.Wanted(index)
  if not missing.active or not missing.usable then return false end
  if not config or not config.barHint then return false end
  if type(index) ~= "number" then return false end

  -- Pet spells belong to the pet bar, which these action slots are not, so
  -- the pet book is left alone entirely rather than marked wholesale.
  local bookType = rank.BookType()
  local playerBook = G("BOOKTYPE_SPELL")
  if type(playerBook) ~= "string" or playerBook == "" then playerBook = "spell" end
  if bookType ~= playerBook then return false end

  -- The live global, not rank.native: on a filtered page the button shows the
  -- slot the wrapper resolves, and that is the spell being asked about. The
  -- call is side-effect free for the filter -- rank.Resolve recomputes the
  -- same page state it just computed from the same inputs.
  local mapper = G("SpellBook_GetSpellID")
  if type(mapper) ~= "function" then return false end
  local slotOk, slot = pcall(mapper, index)
  if not slotOk or type(slot) ~= "number" then return false end

  local spellName = G("GetSpellName")
  if type(spellName) ~= "function" then return false end
  local nameOk, name, rankText = pcall(spellName, slot, bookType)
  if not nameOk or type(name) ~= "string" or name == "" then return false end

  -- Passives cannot be dragged to a bar, so "not on a bar" is not a gap.
  local passive = G("IsSpellPassive")
  if type(passive) == "function" then
    local passiveOk, value = pcall(passive, slot, bookType)
    if passiveOk and value and value ~= 0 then return false end
  end

  if rank.IsHighest(bookType, slot) ~= true then return false end

  -- Class abilities only, which is the whole of what the mark is for. The
  -- first spellbook tab is General, and on this client it measured as
  -- Attack, Shoot, the racials, the weapon skills, the professions and the
  -- items those professions grant -- fourteen entries, of which nine were
  -- droppable onto a bar and so marked forever against a single genuine hit
  -- (Shadow Word: Pain). The class tabs that follow it held nothing but real
  -- abilities. See knowledge.json /
  -- spellbook.general_tab_is_first_class_abilities_follow.
  --
  -- The test is the tab, not the rank subtext: a subtext exists on
  -- professions ("Apprentice") and racials ("Racial") too, and requiring one
  -- would silently drop the class abilities that have no rank at all --
  -- warrior stances and druid forms among them.
  --
  -- A client that ordered its tabs differently would lose marks rather than
  -- gain wrong ones, which is the direction every other failure here already
  -- degrades in.
  local _, _, tab = rank.Range(bookType, slot)
  if type(tab) ~= "number" or tab <= missing.GENERAL_TAB then return false end

  -- Re-tested after the build, not only before it: the first button drawn
  -- after the window opens is the one that triggers the lazy rebuild, so it
  -- is also the one that would otherwise be judged against an index the
  -- rebuild had just declared unusable.
  missing.Ensure()
  if not missing.usable then return false end

  return not missing.Present(name, rankText)
end

-- The mark itself: an accent outline on an owned frame one level above the
-- button, so it survives the native artwork refresh that ClearButtonFaces has
-- to keep undoing and needs nothing from whichever theme drew the button.
--
-- Held at alpha 0 rather than hidden, because the button itself is what shows
-- and hides here; the overlay never has to be told about that.
function missing.Overlay(button)
  if not button then return nil end
  if button.uuiBarHint then return button.uuiBarHint end

  local ok, overlay = pcall(CreateFrame, "Frame", nil, button)
  if not ok or not overlay then return nil end

  local inset = missing.INSET
  pcall(function()
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
  end)
  pcall(overlay.EnableMouse, overlay, false)

  if button.GetFrameLevel and overlay.SetFrameLevel then
    local levelOk, level = pcall(button.GetFrameLevel, button)
    if levelOk and tonumber(level) then
      pcall(overlay.SetFrameLevel, overlay, level + 1)
    end
  end

  U.CreateBorder(overlay, 1)
  U.SetBorderColor(overlay, M.Unpack(missing.CLEAR))

  button.uuiBarHint = overlay
  return overlay
end

function missing.Apply(index)
  local button = G("SpellButton" .. index)
  if not button then return end

  local overlay = missing.Overlay(button)
  if not overlay then return end

  local spellIndex = missing.ButtonID(button)
  local wanted = false
  local ok, value = pcall(missing.Wanted, spellIndex)
  if ok then wanted = value and true or false end

  U.SetBorderColor(overlay,
                   M.Unpack(wanted and M.color.accent or missing.CLEAR))
  -- GetVertexColor cannot read the border tint back on this client. Preserve
  -- the verdict that was actually painted so the diagnostic can compare it to
  -- both the current calculation and the native rendered button.
  overlay.uuiBarHintWanted = wanted

  if missing.trace.on then
    missing.NoteVerdict(index, button, spellIndex, wanted)
  end
end

function missing.ApplyAll()
  local i
  for i = 1, SpellCount() do missing.Apply(i) end
end

function missing.Commit(value)
  config.barHint = value and true or false
  missing.ApplyAll()
end

function missing.AnchorArgs()
  -- Beside the rank toggle, measured from that toggle's own text rather than
  -- from a width this file would have to know for two different chrome
  -- shapes. Without it, take the place the rank toggle would have had.
  if rank.box and rank.label then
    return "LEFT", rank.label, "RIGHT", 10, 0
  end
  return rank.AnchorArgs()
end

function missing.AttachTooltip(button)
  if not button or button.uuiBarHintTooltipAttached then return end
  button.uuiBarHintTooltipAttached = true

  U.PostHookScript(button, "OnEnter", function()
    local tooltip = G("GameTooltip")
    if not tooltip then return end
    pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
    pcall(tooltip.SetText, tooltip, U.L("SPELLBOOK_BAR_HINT_TOOLTIP"))
    pcall(tooltip.Show, tooltip)
  end)
  U.PostHookScript(button, "OnLeave", function()
    local tooltip = G("GameTooltip")
    if tooltip then pcall(tooltip.Hide, tooltip) end
  end)
end

function missing.BuildNativeToggle(book)
  local ok, box = pcall(CreateFrame, "CheckButton", "UnrealUISpellBookBarHint",
                        book, "UICheckButtonTemplate")
  if not ok or not box then return nil end

  box:SetPoint(missing.AnchorArgs())
  pcall(box.SetWidth, box, rank.NATIVE_SIZE)
  pcall(box.SetHeight, box, rank.NATIVE_SIZE)

  local label = G("UnrealUISpellBookBarHintText")
  if label then
    label:SetText(U.L("SPELLBOOK_BAR_HINT"))
    pcall(function()
      label:ClearAllPoints()
      label:SetPoint("LEFT", box, "RIGHT", 3, 0)
    end)
  end

  rank.RaiseNativeMark(box)

  box:SetChecked(config.barHint and true or nil)
  box:SetScript("OnClick", function()
    local value = not config.barHint
    box:SetChecked(value and true or nil)
    rank.RaiseNativeMark(box)
    missing.Commit(value)
  end)
  missing.AttachTooltip(box)

  return box
end

function missing.BuildModernToggle(book)
  local ok, control = pcall(U.CreateCheckbox, book, {
    name = "UnrealUISpellBookBarHint",
    text = U.L("SPELLBOOK_BAR_HINT"),
    value = config.barHint,
    textWidth = missing.LABEL_WIDTH,
    onChange = missing.Commit,
  })
  if not ok or not control then return nil end

  control.SetPoint(missing.AnchorArgs())
  missing.AttachTooltip(control.box)
  return control
end

-- Same split as rank.BuildToggle, and for the same reason.
function missing.BuildToggle()
  local book = BookFrame()
  if not book or missing.box then return end

  -- This control anchors to the rank toggle, and the two are built from
  -- separate tickers whose phases do not line up, so the neighbour is settled
  -- first rather than left to whichever tick happened to fire earlier.
  -- rank.BuildToggle already returns early once it has built.
  if rank.active then rank.BuildToggle() end

  if U.ThemeStyleUsesNativeChrome() then
    missing.box = missing.BuildNativeToggle(book)
  else
    missing.box = missing.BuildModernToggle(book)
  end

  if not missing.box then
    U.Debug("spellbook: bar hint toggle unavailable")
    return
  end
  U.AddWindowDragInteractiveFrame(book, missing.box.box or missing.box)
end

function missing.Install()
  if missing.active then return end

  -- Both halves are required: without the mapping there is no way to know
  -- which spell a button is showing, and without the tooltip there is no way
  -- to know what is on a slot.
  if type(G("SpellBook_GetSpellID")) ~= "function" then
    U.Debug("spellbook: SpellBook_GetSpellID unavailable, bar hint omitted")
    return
  end
  if not missing.Scanner() then return end

  missing.active = true
  missing.BuildToggle()

  -- SpellButton_UpdateButton is this client's only spell-button repaint path
  -- (knowledge.json /
  -- spellbook.rank_filter_redraw_requires_spellbutton_updatebutton), and it
  -- takes its button from the global `this`, so the mark is re-applied for
  -- exactly the button the client just drew -- page turns, skill-line changes
  -- and rank.Refresh all included.
  U.PostHookGlobal("SpellButton_UpdateButton", function()
    local button = G("this")
    if not button then return end

    local i
    for i = 1, SpellCount() do
      if G("SpellButton" .. i) == button then
        if missing.trace.on then missing.NoteButtonUpdate(i) end
        missing.Apply(i)
        return
      end
    end
  end)

  -- The book does not repaint when a spell is dragged onto a bar, so the
  -- index is rebuilt and the open page re-marked off the shared ticker
  -- instead. Both only happen while something actually changed and the window
  -- is open, so an untouched action bar costs one IsShown test per tick.
  --
  -- Half a second rather than the rank filter's 0.2: a rebuild is 120 tooltip
  -- reads, and rearranging a bar fires ACTIONBAR_SLOT_CHANGED per slot
  -- touched. The interval is what bounds that, since the event handler only
  -- sets a flag. Half a second is still under the time it takes to look back
  -- at the book after dropping a spell.
  U.RegisterUpdate("spellbook.bar-hint", 0.5, function()
    if not missing.BookShown() then return end

    if not missing.box then missing.BuildToggle() end
    if missing.dirty or not missing.built then missing.Rebuild() end

    -- Cleared before the sweep, not after: ApplyAll cannot set it again
    -- (nothing it calls rebuilds while the index is clean), and clearing
    -- first means a rebuild racing the sweep is not silently swallowed.
    if missing.remark then
      missing.remark = false
      if missing.trace.on then missing.Note("sweep") end
      missing.ApplyAll()
      if missing.trace.on then missing.Capture("after sweep") end
    end
  end)

  U.RegisterEvent("ACTIONBAR_SLOT_CHANGED", missing.OnBarEvent)
  U.RegisterEvent("PLAYER_ENTERING_WORLD", missing.OnBarEvent)
  U.RegisterEvent("SPELLS_CHANGED", missing.OnBarEvent)
  U.RegisterEvent("LEARNED_SPELL_IN_TAB", missing.OnBarEvent)
end

-- ---------------------------------------------------------------------------
-- /uui sb trace -- what actually changes when a spell goes on or off a bar
--
-- /uui sb answers "what does the feature believe right now". It cannot answer
-- "what happened when I dragged that spell", because every observation it
-- makes is taken after the fact: by the time the command runs the index has
-- already been rebuilt and the one it replaced is gone.
--
-- This records the whole chain instead, in order, while the player drags:
--
--   ACTIONBAR_SLOT_CHANGED  the slot the client named, plus HasAction and the
--                           scanner read for that slot AT THAT MOMENT -- the
--                           one observation no later rebuild can reconstruct
--   rebuild                 counts, plus the added/removed index keys, so a
--                           drag that changed nothing in the index stays
--                           distinguishable from one that changed the wrong
--                           entry
--   sweep / button          each verdict transition, with the spell that
--                           button was showing and the overlay's own state
--
-- Verdict lines are change-only. A page turn repaints twelve buttons, and a
-- line per button per repaint buries the two lines that matter.
--
-- Every line is written to UnrealUIDiagDB.spellbookTrace as it happens, so an
-- unexpected /reload never costs the run, and echoed to chat so a wrong mark
-- can be matched against the frame it appeared on without leaving the game.
-- ---------------------------------------------------------------------------
missing.trace = {
  on = false,
  log = {},
  -- Per-rebuild raw slot reads. Not echoed to chat -- 40 lines per rebuild is
  -- unreadable there -- but it is what exposes a tooltip that reported the
  -- previous slot's spell, which is the failure a resolved count hides.
  scans = {},
  -- Exact event arguments and action-slot state at event time.
  events = {},
  -- Native SpellButton_UpdateButton readback. Stored only when the rendered
  -- identity for an index changes, so page changes are visible without logging
  -- every repaint of the same page.
  updates = {},
  updateKeys = {},
  -- Complete mapper/render/frame/overlay snapshots around each transition.
  snapshots = {},
  -- Full static frame/region/edge topology, captured once per run.
  layout = nil,
  marks = {},
  started = nil,
  ended = nil,
  capped = false,
  -- A drag is a handful of events. The cap only matters if something fires
  -- continuously and the trace is left armed.
  LIMIT = 300,
  SCANS = 8,
  EVENTS = 40,
  UPDATES = 60,
  SNAPSHOTS = 16,
}

function missing.Now()
  local clock = G("GetTime")
  if type(clock) ~= "function" then return 0 end
  local ok, value = pcall(clock)
  return (ok and tonumber(value)) or 0
end

function missing.BookShown()
  local book = BookFrame()
  if not book or not book.IsShown then return false end
  local ok, shown = pcall(book.IsShown, book)
  return (ok and shown) and true or false
end

function missing.Save()
  U.SaveDiagnostic("spellbookTrace", {
    probeVersion = missing.PROBE_VERSION,
    started = missing.trace.started,
    ended = missing.trace.ended,
    active = missing.trace.on,
    log = missing.trace.log,
    scans = missing.trace.scans,
    events = missing.trace.events,
    updates = missing.trace.updates,
    snapshots = missing.trace.snapshots,
    layout = missing.trace.layout,
    limits = {
      log = missing.trace.LIMIT,
      scans = missing.trace.SCANS,
      events = missing.trace.EVENTS,
      updates = missing.trace.UPDATES,
      snapshots = missing.trace.SNAPSHOTS,
    },
  })
end

function missing.Capture(label)
  if not missing.trace.on then return end
  if not missing.trace.layout then
    missing.trace.layout = missing.ViewState("layout", false)
  end
  local snapshots = missing.trace.snapshots
  table.insert(snapshots, missing.ViewState(label, true))
  while table.getn(snapshots) > missing.trace.SNAPSHOTS do
    table.remove(snapshots, 1)
  end
  missing.Save()
end

function missing.EventArgs(a1, a2, a3, a4, a5, a6, a7, a8)
  local values = { a1, a2, a3, a4, a5, a6, a7, a8 }
  local out, i = {}, nil
  for i = 1, 8 do
    table.insert(out, {
      index = i,
      kind = type(values[i]),
      value = missing.Stored(values[i]),
    })
  end
  return out
end

function missing.NoteButtonUpdate(index)
  local state = missing.ButtonTraceState(index)
  local rendered = state.rendered or {}
  local name = rendered.name and rendered.name.text or "<no name region>"
  local sub = rendered.sub and rendered.sub.text or "<no sub region>"
  local texture = rendered.icon and rendered.icon.texture or "<no icon>"
  local key = tostring(name) .. "\001" .. tostring(sub) .. "\001" ..
              tostring(texture) .. "\001" .. tostring(state.mapped.slot) ..
              "\001" .. tostring(state.button.shown)
  if missing.trace.updateKeys[index] == key then return end
  missing.trace.updateKeys[index] = key

  state.at = missing.Now() - (missing.trace.started or 0)
  state.thisObject = missing.ObjectName(G("this"))
  table.insert(missing.trace.updates, state)
  while table.getn(missing.trace.updates) > missing.trace.UPDATES do
    table.remove(missing.trace.updates, 1)
  end
  missing.Save()
end

function missing.Note(text)
  local trace = missing.trace
  if not trace.on then return end

  if table.getn(trace.log) >= trace.LIMIT then
    if not trace.capped then
      trace.capped = true
      table.insert(trace.log, "-- trace full at " .. trace.LIMIT .. " lines")
      missing.Save()
      U.Print("|cff888888sb trace|r full, recording stopped")
    end
    return
  end

  local line = string.format("%7.2f  %s", missing.Now() - (trace.started or 0),
                             text)
  table.insert(trace.log, line)
  missing.Save()
  U.Print("|cff888888sb|r " .. line)
end

-- The index flattened to one comparable set, so a diff between two rebuilds
-- reads as the entries the feature will actually consult. A name whose rank
-- could not be read is tagged rather than merged into the ranked keys, because
-- those two states mean different things to Present: an unranked entry
-- satisfies every rank of that spell, a ranked one satisfies only its own.
function missing.Snapshot()
  local out, key = {}, nil
  for key in pairs(missing.ranked) do out[key] = true end
  for key in pairs(missing.unranked) do out[key .. "\001<no rank read>"] = true end
  return out
end

function missing.KeyText(key)
  return string.gsub(key, "\001", " | ")
end

function missing.NoteRebuild(before, scan, occupied, resolved,
                             filledCount, macroCount)
  local after, key = missing.Snapshot(), nil
  local added, removed = {}, {}

  for key in pairs(after) do
    if not before[key] then table.insert(added, key) end
  end
  for key in pairs(before) do
    if not after[key] then table.insert(removed, key) end
  end

  local names = 0
  for key in pairs(missing.any) do names = names + 1 end

  missing.Note("rebuild: occupied=" .. occupied .. " resolved=" .. resolved ..
               " filled=" .. tostring(filledCount) ..
               " macros=" .. tostring(macroCount) ..
               " names=" .. names .. " usable=" .. tostring(missing.usable) ..
               " changed=" .. (table.getn(added) + table.getn(removed)))

  local i
  for i = 1, table.getn(added) do
    missing.Note("    bar + " .. missing.KeyText(added[i]))
  end
  for i = 1, table.getn(removed) do
    missing.Note("    bar - " .. missing.KeyText(removed[i]))
  end

  if scan then
    table.insert(missing.trace.scans, {
      at = string.format("%.2f", missing.Now() - (missing.trace.started or 0)),
      occupied = occupied,
      resolved = resolved,
      filled = filledCount,
      macros = macroCount,
      slots = scan,
    })
    while table.getn(missing.trace.scans) > missing.trace.SCANS do
      table.remove(missing.trace.scans, 1)
    end
    missing.Save()
  end
end

-- The spell a button is showing, resolved exactly the way Wanted resolves it,
-- so a verdict line names what the verdict was actually about.
function missing.ButtonSpell(index)
  local mapper, spellName = G("SpellBook_GetSpellID"), G("GetSpellName")
  if type(mapper) ~= "function" or type(spellName) ~= "function" then
    return "<no mapping>"
  end

  local slotOk, slot = pcall(mapper, index)
  if not slotOk or type(slot) ~= "number" then return "<no slot>" end

  local nameOk, name, rankText = pcall(spellName, slot, rank.BookType())
  if not nameOk or type(name) ~= "string" or name == "" then
    return "<empty slot " .. tostring(slot) .. ">"
  end

  local text = name
  if type(rankText) == "string" and rankText ~= "" then
    text = text .. " | " .. rankText
  end
  return text .. " (slot " .. slot .. ")"
end

-- Overlay state, not just the verdict: a correct verdict painted onto a frame
-- that is hidden, transparent, or missing its edges looks exactly like a wrong
-- verdict on screen, and GetVertexColor does not exist on this client
-- (knowledge.json / textures.getvertexcolor_readback_missing) so the tint
-- itself cannot be read back to settle it.
function missing.OverlayState(button)
  if not button then return "no button" end

  local shown = "?"
  if type(button.IsVisible) == "function" then
    local ok, value = pcall(button.IsVisible, button)
    shown = ok and tostring(value) or "<error>"
  end

  local overlay = button.uuiBarHint
  if not overlay then return "btn vis=" .. shown .. " overlay=none" end

  local alpha = "?"
  if type(overlay.GetAlpha) == "function" then
    local ok, value = pcall(overlay.GetAlpha, overlay)
    alpha = ok and tostring(value) or "<error>"
  end

  local edges = 0
  if overlay.uuiEdges then edges = table.getn(overlay.uuiEdges) end

  return "btn vis=" .. shown .. " overlay alpha=" .. alpha ..
         " edges=" .. edges
end

function missing.NoteVerdict(index, button, spellIndex, wanted)
  local marks = missing.trace.marks
  if marks[index] == wanted then return end
  marks[index] = wanted

  local renderedName = missing.Read(G("SpellButton" .. index .. "SpellName"),
                                    "GetText")
  local renderedSub = missing.Read(G("SpellButton" .. index .. "SubSpellName"),
                                   "GetText")
  missing.Note("  button " .. index .. " " ..
               "id=" .. tostring(spellIndex) .. " " ..
               (wanted and "MARK " or "clear") .. " " ..
               missing.ButtonSpell(spellIndex) ..
               " rendered=" .. tostring(renderedName) .. " / " ..
               tostring(renderedSub) ..
               "  [" .. missing.OverlayState(button) .. "]")
end

-- Replaces Invalidate as the registered handler while keeping its behaviour
-- exactly: the flag is set as before, and everything above it runs only while
-- the trace is armed.
function missing.OnBarEvent(event, slot, a2, a3, a4, a5, a6, a7, a8)
  if missing.trace.on then
    local text = tostring(event) .. " slot=" .. tostring(slot)
    local eventRow = {
      at = missing.Now() - (missing.trace.started or 0),
      event = tostring(event),
      args = missing.EventArgs(slot, a2, a3, a4, a5, a6, a7, a8),
      bookShown = missing.BookShown(),
    }

    local index = tonumber(slot)
    if index then
      local hasAction = G("HasAction")
      local filled = "<no HasAction>"
      if type(hasAction) == "function" then
        local ok, value = pcall(hasAction, index)
        if ok then
          filled = tostring(value and true or false)
        else
          filled = "<error>"
        end
      end

      local name, rankText = missing.ScanSlot(index)
      text = text .. " has=" .. filled ..
             " reads=" .. tostring(name) .. " / " .. tostring(rankText)
      eventRow.action = missing.ActionSlotState(index)
    end

    table.insert(missing.trace.events, eventRow)
    while table.getn(missing.trace.events) > missing.trace.EVENTS do
      table.remove(missing.trace.events, 1)
    end
    missing.Note(text .. " bookShown=" .. tostring(missing.BookShown()))
    missing.Capture("after event " .. tostring(event))
  end

  missing.Invalidate()
end

function U.SpellBookBarHintTrace(mode)
  local trace = missing.trace

  if mode == "off" then
    if not trace.on then
      U.Print("sb trace was not armed")
      return
    end
    missing.Capture("trace off")
    trace.ended = missing.Now()
    trace.on = false
    missing.Save()
    U.Print("sb trace off: " .. table.getn(trace.log) .. " lines, " ..
            table.getn(trace.scans) .. " slot scans and " ..
            table.getn(trace.snapshots) .. " visual snapshots in " ..
            "UnrealUIDiagDB.spellbookTrace")
    U.Print("  |cffffff00/reload|r then read " .. U.SavedVariablesHint())
    return
  end

  if not missing.active then
    U.Print("sb trace: the bar hint never installed, nothing to trace " ..
            "(|cffffff00/uui sb|r says why)")
    return
  end

  trace.on = true
  trace.log, trace.scans, trace.events = {}, {}, {}
  trace.updates, trace.updateKeys, trace.snapshots = {}, {}, {}
  trace.layout = nil
  trace.marks = {}
  trace.capped = false
  trace.started = missing.Now()
  trace.ended = nil
  missing.Save()

  missing.Note("armed: barHint=" .. tostring(config and config.barHint) ..
               " highestRankOnly=" ..
               tostring(config and config.highestRankOnly) ..
               " bookShown=" .. tostring(missing.BookShown()) ..
               " chrome=" ..
               (U.ThemeStyleUsesNativeChrome() and "native" or "modern"))

  -- Forces the first rebuild and sweep to happen under the trace, so the run
  -- opens with the current verdict for every button rather than with whichever
  -- transition happens to come first.
  missing.Invalidate()
  missing.Capture("armed")

  U.Print("|cffffff00sb trace armed (v3).|r Open the affected spellbook tab, " ..
          "then remove and restore each of TWO neighbouring spells, waiting " ..
          "for the outline after every move.")
  U.Print("  then |cffffff00/uui sb trace off|r and |cffffff00/reload|r")
end


-- ---------------------------------------------------------------------------
-- /uui sb -- why a spell is, or is not, marked
--
-- Both halves of this feature read the client through calls with no runtime
-- record (knowledge.json /
-- spellbook.action_slot_spell_identity_tooltip_unverified), and a wrong mark
-- looks identical whichever half produced it. This dumps the raw material for
-- both: every occupied action slot with its unguarded tooltip reads AND the
-- IsVisible values the scan actually gates on, plus every highest-rank spell
-- in the book with the verdict the feature reached for it.
--
-- Written to UnrealUIDiagDB rather than chat, with a summary short enough to
-- answer the common cases without a reload.
-- ---------------------------------------------------------------------------

-- Raw fontstring readout: the text with no guard applied, and separately what
-- IsVisible says about it. Reported as strings so a nil, an error and an empty
-- string stay distinguishable in the dump.
function missing.DumpLine(suffix)
  local name = missing.SCANNER .. suffix

  local region = nil
  if _G then region = _G[name] end
  if not region then region = U.G(name) end
  if not region then return "<no region>", "<no region>" end

  local text = "<no GetText>"
  if type(region.GetText) == "function" then
    local ok, value = pcall(region.GetText, region)
    if not ok then
      text = "<error>"
    elseif value == nil then
      text = "<nil>"
    else
      text = tostring(value)
    end
  end

  local visible = "<no IsVisible>"
  if type(region.IsVisible) == "function" then
    local ok, value = pcall(region.IsVisible, region)
    visible = ok and tostring(value) or "<error>"
  end

  return text, visible
end

function missing.DumpActions(report)
  local tip = missing.Scanner()
  local hasAction, actionText = G("HasAction"), G("GetActionText")

  local slot
  for slot = 1, missing.MAX_SLOTS do
    local filled = false
    if type(hasAction) == "function" then
      local ok, value = pcall(hasAction, slot)
      filled = ok and value and true or false
    end

    if filled then
      report.occupied = report.occupied + 1

      local macro = "<nil>"
      if type(actionText) == "function" then
        local ok, value = pcall(actionText, slot)
        if not ok then
          macro = "<error>"
        elseif value ~= nil then
          macro = tostring(value)
        end
      end

      local row = { slot = slot, actionText = macro }

      if tip and type(tip.SetAction) == "function" then
        pcall(tip.ClearLines, tip)
        pcall(tip.SetOwner, tip, G("WorldFrame") or UIParent, "ANCHOR_NONE")

        local setOk, setValue = pcall(tip.SetAction, tip, slot)
        row.setAction = setOk and tostring(setValue) or "<error>"

        if type(tip.NumLines) == "function" then
          local ok, lines = pcall(tip.NumLines, tip)
          row.lines = ok and tostring(lines) or "<error>"
        end

        row.left, row.leftVisible = missing.DumpLine("TextLeft1")
        row.right, row.rightVisible = missing.DumpLine("TextRight1")

        if row.left ~= "<nil>" and row.left ~= "" and
           string.sub(row.left, 1, 1) ~= "<" then
          report.resolved = report.resolved + 1
        end
      else
        row.setAction = "<no scanner>"
      end

      -- v3 keeps the original compact fields for chat compatibility and adds
      -- the full action identity/tooltip tuple for offline comparison against
      -- the rendered spellbook icon and label.
      row.detail = missing.ActionSlotState(slot)
      table.insert(report.slots, row)
    end
  end
end

function missing.DumpBook(report)
  local playerBook = G("BOOKTYPE_SPELL")
  if type(playerBook) ~= "string" or playerBook == "" then playerBook = "spell" end

  local tabCount, tabInfo = G("GetNumSpellTabs"), G("GetSpellTabInfo")
  local spellName, passive = G("GetSpellName"), G("IsSpellPassive")
  if type(tabCount) ~= "function" or type(tabInfo) ~= "function" or
     type(spellName) ~= "function" then
    return
  end

  local countOk, tabs = pcall(tabCount)
  if not countOk or type(tabs) ~= "number" then return end

  local t
  for t = 1, tabs do
    local tabOk, _, _, offset, num = pcall(tabInfo, t)
    offset, num = tonumber(offset), tonumber(num)

    if tabOk and offset and num then
      local s
      for s = offset + 1, offset + num do
        local nameOk, name, rankText = pcall(spellName, s, playerBook)
        if nameOk and type(name) == "string" and name ~= "" then
          report.spells = report.spells + 1

          if rank.IsHighest(playerBook, s) == true then
            report.highest = report.highest + 1

            local isPassive = "<nil>"
            if type(passive) == "function" then
              local ok, value = pcall(passive, s, playerBook)
              if not ok then
                isPassive = "<error>"
              elseif value ~= nil then
                isPassive = tostring(value)
              end
            end

            -- Mirrors Wanted's own tests, tab included, so a row that reads
            -- marked=false in the dump is not a spell the player can see an
            -- outline on.
            local present = missing.Present(name, rankText)
            local marked = not present and isPassive == "<nil>" and
                           t > missing.GENERAL_TAB
            if marked then report.marked = report.marked + 1 end

            table.insert(report.book, {
              tab = t,
              slot = s,
              name = name,
              rank = (rankText == nil) and "<nil>" or tostring(rankText),
              passive = isPassive,
              present = present,
              marked = marked,
            })
          end
        end
      end
    end
  end
end

-- Spellbook tab layout, with the rank/non-rank split per tab.
--
-- Needed to answer which tabs are professions: the marked list alone cannot
-- distinguish "Enchanting" the profession from a class ability, and the tab
-- ordering is not something to assume from Vanilla.
function missing.DumpTabs(report)
  local playerBook = G("BOOKTYPE_SPELL")
  if type(playerBook) ~= "string" or playerBook == "" then playerBook = "spell" end

  local tabCount, tabInfo = G("GetNumSpellTabs"), G("GetSpellTabInfo")
  local spellName, passive = G("GetSpellName"), G("IsSpellPassive")
  if type(tabCount) ~= "function" or type(tabInfo) ~= "function" or
     type(spellName) ~= "function" then
    return
  end

  local countOk, tabs = pcall(tabCount)
  if not countOk or type(tabs) ~= "number" then return end
  report.tabCount = tabs

  local t
  for t = 1, tabs do
    local tabOk, tabName, tabTexture, offset, num = pcall(tabInfo, t)
    offset, num = tonumber(offset), tonumber(num)

    if tabOk and offset and num then
      local entry = {
        index = t,
        name = tostring(tabName),
        texture = tostring(tabTexture),
        offset = offset,
        count = num,
        ranked = 0,
        other = 0,
        spells = {},
      }

      local s
      for s = offset + 1, offset + num do
        local nameOk, name, sub = pcall(spellName, s, playerBook)
        if nameOk and type(name) == "string" and name ~= "" then
          local isPassive = "<nil>"
          if type(passive) == "function" then
            local ok, value = pcall(passive, s, playerBook)
            if not ok then
              isPassive = "<error>"
            elseif value ~= nil then
              isPassive = tostring(value)
            end
          end

          -- "Ranked" here means only that a subtext exists, not that it parses
          -- as a rank: the point of the dump is to see what the subtexts are.
          local subText = (sub == nil) and "<nil>" or tostring(sub)
          if subText ~= "<nil>" and subText ~= "" then
            entry.ranked = entry.ranked + 1
          else
            entry.other = entry.other + 1
          end

          table.insert(entry.spells, {
            slot = s, name = name, sub = subText, passive = isPassive,
          })
        end
      end

      table.insert(report.tabs, entry)
    end
  end
end

-- The skill list, which is the only place the client groups a skill line under
-- a category. Headers are localized, so the dump records the grouping and the
-- rank/maxRank shape rather than matching any header name here.
--
-- Collapsed headers hide their children from this list, so the row count is
-- reported and the caller is told to expand the Skills window first.
function missing.DumpSkills(report)
  local numLines, lineInfo = G("GetNumSkillLines"), G("GetSkillLineInfo")
  if type(numLines) ~= "function" or type(lineInfo) ~= "function" then
    report.skillApi = "unavailable"
    return
  end
  report.skillApi = "ok"

  local countOk, rows = pcall(numLines)
  if not countOk or type(rows) ~= "number" then return end
  report.skillRows = rows

  local i
  for i = 1, rows do
    local ok, name, header, expanded, skillRank, temp, modifier, maxRank =
      pcall(lineInfo, i)
    if ok then
      table.insert(report.skills, {
        index = i,
        name = tostring(name),
        header = tostring(header),
        expanded = tostring(expanded),
        rank = tostring(skillRank),
        maxRank = tostring(maxRank),
      })
    end
  end
end

function U.SpellBookBarHintDump()
  local report = {
    probeVersion = missing.PROBE_VERSION,
    active = missing.active,
    usable = missing.usable,
    built = missing.built,
    dirty = missing.dirty,
    remark = missing.remark,
    barHint = config and config.barHint or false,
    highestRankOnly = config and config.highestRankOnly or false,
    bookType = tostring(rank.BookType()),
    playerBook = tostring(G("BOOKTYPE_SPELL")),
    scanner = missing.Scanner() and "ok" or "unavailable",
    api = {
      HasAction = type(G("HasAction")),
      GetActionText = type(G("GetActionText")),
      GetActionTexture = type(G("GetActionTexture")),
      IsCurrentAction = type(G("IsCurrentAction")),
      IsAutoRepeatAction = type(G("IsAutoRepeatAction")),
      IsUsableAction = type(G("IsUsableAction")),
      GetActionCooldown = type(G("GetActionCooldown")),
      GetSpellName = type(G("GetSpellName")),
      GetSpellTexture = type(G("GetSpellTexture")),
      IsSpellPassive = type(G("IsSpellPassive")),
      SpellBook_GetSpellID = type(G("SpellBook_GetSpellID")),
      GetNumSpellTabs = type(G("GetNumSpellTabs")),
    },
    occupied = 0,
    resolved = 0,
    spells = 0,
    highest = 0,
    marked = 0,
    slots = {},
    book = {},
    tabs = {},
    skills = {},
    tiers = {},
  }

  -- Vanilla names the trade-skill tiers in GlobalStrings. query_compat.py has
  -- no record of them on this client, so whether they exist at all is part of
  -- what this dump answers rather than something the filter may assume.
  local tierNames = { "APPRENTICE", "JOURNEYMAN", "EXPERT", "ARTISAN", "MASTER" }
  local n
  for n = 1, table.getn(tierNames) do
    local value = G(tierNames[n])
    report.tiers[tierNames[n]] = (value == nil) and "<nil>" or tostring(value)
  end

  -- Rebuild first, so the dump describes the index the feature is using right
  -- now rather than one left over from an earlier scan.
  missing.Rebuild()
  report.usableAfterRebuild = missing.usable

  missing.DumpActions(report)
  missing.DumpBook(report)
  missing.DumpTabs(report)
  missing.DumpSkills(report)
  report.view = missing.ViewState("dump after rebuild")

  local indexed, key = 0, nil
  for key in pairs(missing.any) do indexed = indexed + 1 end
  report.indexedNames = indexed

  U.SaveDiagnostic("spellbookBarHint", report)

  U.Print("spellbook bar hint: active=" .. tostring(report.active) ..
          " usable=" .. tostring(report.usable) ..
          " on=" .. tostring(report.barHint) ..
          " book=" .. report.bookType)
  U.Print("  action slots: occupied=" .. report.occupied ..
          " resolved=" .. report.resolved ..
          " indexedNames=" .. indexed ..
          " scanner=" .. report.scanner)

  local i
  for i = 1, 3 do
    local row = report.slots[i]
    if row then
      U.Print("  slot " .. row.slot ..
              ": setAction=" .. tostring(row.setAction) ..
              " lines=" .. tostring(row.lines) ..
              " text=" .. tostring(row.actionText))
      U.Print("      left=" .. tostring(row.left) ..
              " (vis " .. tostring(row.leftVisible) .. ")" ..
              " right=" .. tostring(row.right) ..
              " (vis " .. tostring(row.rightVisible) .. ")")
    end
  end

  U.Print("  book: spells=" .. report.spells ..
          " highest=" .. report.highest ..
          " marked=" .. report.marked)

  for i = 1, table.getn(report.book) do
    local row = report.book[i]
    if row.marked then
      U.Print("  marked: tab " .. row.tab .. " " .. row.name ..
              " |cff888888" .. row.rank .. "|r")
    end
  end

  U.Print("  spellbook tabs: " .. tostring(report.tabCount))
  for i = 1, table.getn(report.tabs) do
    local tab = report.tabs[i]
    U.Print("    tab " .. tab.index .. " \"" .. tab.name .. "\"" ..
            " spells=" .. tab.count ..
            " withSubtext=" .. tab.ranked ..
            " bare=" .. tab.other)
  end

  U.Print("  skills: api=" .. tostring(report.skillApi) ..
          " rows=" .. tostring(report.skillRows) ..
          " (expand every header in Character > Skills first)")

  local group = nil
  for i = 1, table.getn(report.skills) do
    local row = report.skills[i]
    if row.header == "1" or row.header == "true" then
      group = row.name
      U.Print("    [" .. row.name .. "]")
    else
      U.Print("        " .. row.name ..
              " " .. row.rank .. "/" .. row.maxRank)
    end
  end

  U.Print("  tiers: APPRENTICE=" .. report.tiers["APPRENTICE"] ..
          " JOURNEYMAN=" .. report.tiers["JOURNEYMAN"] ..
          " ARTISAN=" .. report.tiers["ARTISAN"])

  U.Print("  full dump in UnrealUIDiagDB.spellbookBarHint - " ..
          "|cffffff00/reload|r then open " .. U.SavedVariablesHint())
end

-- ---------------------------------------------------------------------------
-- Highest-rank filter diagnostic (/uui sb ranks)
-- ---------------------------------------------------------------------------
--
-- rank.List has exactly one behavioural assumption: the ranks of a spell
-- occupy consecutive slots in ascending order inside a skill line, so the
-- last entry of a run of identical names is the highest rank. That is
-- Vanilla's layout, and knowledge.json /
-- spellbook.rank_filter_native_mapping_unverified records it only as the
-- *Vanilla expectation* -- it was never measured on this client.
--
-- Every way the assumption can fail shows the player the same thing ("the
-- wrong rank is displayed"), so this dump records the raw layout rather than
-- guessing which way it broke:
--
--   * a run whose subtexts descend -> the last slot is the LOWEST rank
--   * ranks that are not adjacent  -> two runs, and both survive the filter
--   * a slot inside a tab's declared range that the client has no name for
--     -> rank.List's break silently truncates the list from there on
--
-- The first run of this dump answered it: the first case is real on this
-- client and the other two are not (knowledge.json /
-- spellbook.spell_ranks_not_always_ascending_in_slot_order). rank.List now
-- resolves a run by rank number, and this command is what re-measures the
-- layout if the filter ever shows the wrong rank again.
--
-- Nothing here is read back by the addon: the report goes to
-- UnrealUIDiagDB.spellbookRanks, with a short form printed to chat.

-- Name and rank subtext of one slot. The name is nil when the client has
-- nothing at that slot, which is itself a finding, so the second return
-- always carries a printable string.
function rank.SlotText(bookType, slot)
  local spellName = G("GetSpellName")
  if type(spellName) ~= "function" then return nil, "<no api>" end

  local ok, name, sub = pcall(spellName, slot, bookType)
  if not ok then return nil, "<error>" end
  if type(name) ~= "string" or name == "" then return nil, "<nil>" end
  if sub == nil or sub == "" then return name, "" end
  return name, tostring(sub)
end

-- One skill line: every slot in its declared range, the runs of identical
-- names in the order the client returns them, and the slots rank.List keeps.
function rank.DumpSection(bookType, index, name, offset, count)
  local entry = {
    index = index,
    name = tostring(name),
    offset = offset,
    count = count,
    slots = {},
    runs = {},
    holes = {},
    filter = {},
    multiRank = 0,
  }

  -- The whole range is walked, holes included, because rank.List stops at the
  -- first one and the dump has to be able to show what it stopped in front of.
  local run, s = nil, nil
  for s = offset + 1, offset + count do
    local spell, sub = rank.SlotText(bookType, s)
    table.insert(entry.slots, {
      slot = s,
      name = spell or "<none>",
      sub = sub,
    })

    if not spell then
      table.insert(entry.holes, s)
      run = nil
    elseif run and run.name == spell then
      run.last, run.n = s, run.n + 1
      table.insert(run.subs, sub)
    else
      run = { name = spell, first = s, last = s, n = 1, subs = { sub } }
      table.insert(entry.runs, run)
    end
  end

  -- Built fresh, so the report describes what the filter computes right now
  -- rather than a list cached from an earlier page.
  rank.Invalidate()
  local list = rank.List(bookType, offset, count)
  if list then
    local i
    for i = 1, table.getn(list) do
      local spell, sub = rank.SlotText(bookType, list[i])
      table.insert(entry.filter, {
        slot = list[i],
        name = spell or "<none>",
        sub = sub,
      })
    end
  else
    entry.filterNote = "rank.List returned nil"
  end
  entry.filterCount = table.getn(entry.filter)
  rank.Invalidate()

  -- Which slot of each run survived the filter, in the run's own terms. A run
  -- reading kept=<dropped> is a spell the filtered page does not show at all.
  local i
  for i = 1, table.getn(entry.runs) do
    local r = entry.runs[i]
    r.subList = table.concat(r.subs, " | ")
    r.kept = "<dropped>"
    if r.n > 1 then entry.multiRank = entry.multiRank + 1 end

    local k
    for k = 1, table.getn(entry.filter) do
      local slot = entry.filter[k].slot
      if slot >= r.first and slot <= r.last then
        r.kept = tostring(slot)
        r.keptSub = entry.filter[k].sub
      end
    end
  end

  return entry
end

-- What the twelve spell buttons resolve to, native mapping beside filtered
-- mapping, plus the text the player is actually reading. button:GetID() is the
-- spell-list position; the SpellButtonN suffix is only visual row order
-- (knowledge.json / spellbook.rank_filter_native_mapping_unverified).
function rank.DumpButtons(report, bookType)
  local live, native = G("SpellBook_GetSpellID"), rank.native

  local i
  for i = 1, SpellCount() do
    local button = G("SpellButton" .. i)
    local row = { button = "SpellButton" .. i, id = "<no GetID>" }

    if button and button.GetID then
      local ok, id = pcall(button.GetID, button)
      if ok and type(id) == "number" then row.id = id end
    end

    local id = tonumber(row.id) or i
    if type(native) == "function" then
      local ok, slot = pcall(native, id)
      row.nativeSlot = (ok and type(slot) == "number") and slot or "<error>"
      if ok and type(slot) == "number" then
        local spell, sub = rank.SlotText(bookType, slot)
        row.nativeName, row.nativeSub = spell or "<none>", sub
      end
    end

    if type(live) == "function" then
      local ok, slot = pcall(live, id)
      row.liveSlot = (ok and type(slot) == "number") and slot or "<error>"
      if ok and type(slot) == "number" then
        local spell, sub = rank.SlotText(bookType, slot)
        row.liveName, row.liveSub = spell or "<none>", sub
      end
    end

    row.rendered = missing.Read(G("SpellButton" .. i .. "SpellName"), "GetText")
    row.renderedSub =
      missing.Read(G("SpellButton" .. i .. "SubSpellName"), "GetText")

    table.insert(report.buttons, row)
  end
end

function U.SpellBookRankDump()
  local playerBook = G("BOOKTYPE_SPELL")
  if type(playerBook) ~= "string" or playerBook == "" then
    playerBook = "spell"
  end

  local report = {
    highestRankOnly = config and config.highestRankOnly or false,
    active = rank.active,
    mapped = rank.mapped,
    page = rank.page,
    pages = rank.pages,
    perPage = SpellCount(),
    maxSpells = tostring(G("MAX_SPELLS")),
    bookType = tostring(rank.BookType()),
    playerBook = playerBook,
    wrapped = (G("SpellBook_GetSpellID") ~= rank.native) and true or false,
    sections = {},
    buttons = {},
  }

  -- The live wrapper is called below to record what each button resolves to,
  -- and rank.Resolve writes the filter's page state as a side effect. It is
  -- snapshotted and put back so the dump cannot leave the open window paging
  -- against numbers this diagnostic produced.
  local page, pages, mapped = rank.page, rank.pages, rank.mapped

  local tabCount, tabInfo = G("GetNumSpellTabs"), G("GetSpellTabInfo")
  if type(tabCount) == "function" and type(tabInfo) == "function" then
    local countOk, tabs = pcall(tabCount)
    if countOk and type(tabs) == "number" then
      report.tabCount = tabs

      local t
      for t = 1, tabs do
        local ok, name, texture, offset, num = pcall(tabInfo, t)
        offset, num = tonumber(offset), tonumber(num)
        if ok and offset and num then
          table.insert(report.sections,
                       rank.DumpSection(playerBook, t, name, offset, num))
        end
      end
    else
      report.tabCount = "<error>"
    end
  else
    report.tabCount = "<no api>"
  end

  rank.DumpButtons(report, playerBook)
  rank.page, rank.pages, rank.mapped = page, pages, mapped
  rank.Invalidate()

  U.SaveDiagnostic("spellbookRanks", report)

  U.Print("spellbook ranks: on=" .. tostring(report.highestRankOnly) ..
          " active=" .. tostring(report.active) ..
          " wrapped=" .. tostring(report.wrapped) ..
          " mapped=" .. tostring(report.mapped) ..
          " page=" .. tostring(report.page) .. "/" .. tostring(report.pages) ..
          " perPage=" .. tostring(report.perPage))
  U.Print("  book=" .. report.bookType ..
          " tabs=" .. tostring(report.tabCount) ..
          " MAX_SPELLS=" .. report.maxSpells)

  -- Only the runs that carry more than one entry are printed: a single-rank
  -- spell cannot show the wrong rank, and the multi-rank runs are the whole
  -- question. The cap keeps a full spellbook from flooding chat; the file has
  -- every row either way.
  local printed, i = 0, nil
  for i = 1, table.getn(report.sections) do
    local section = report.sections[i]
    U.Print("  tab " .. section.index .. " " .. section.name ..
            " slots " .. (section.offset + 1) .. "-" ..
            (section.offset + section.count) ..
            " runs=" .. table.getn(section.runs) ..
            " multiRank=" .. section.multiRank ..
            " filtered=" .. section.filterCount ..
            " holes=" .. table.getn(section.holes) ..
            (section.filterNote and (" " .. section.filterNote) or ""))

    if table.getn(section.holes) > 0 then
      U.Print("    |cffff5555holes|r: " ..
              table.concat(section.holes, ", ") ..
              " - rank.List stops at the first one")
    end

    local r
    for r = 1, table.getn(section.runs) do
      local runRow = section.runs[r]
      if runRow.n > 1 and printed < 14 then
        printed = printed + 1
        U.Print("    " .. runRow.name ..
                " slots " .. runRow.first .. "-" .. runRow.last ..
                " [" .. runRow.subList .. "]" ..
                " kept=" .. runRow.kept ..
                " (" .. tostring(runRow.keptSub) .. ")")
      end
    end
  end
  if printed >= 14 then U.Print("    ... more runs in the file") end

  for i = 1, table.getn(report.buttons) do
    local row = report.buttons[i]
    U.Print("  " .. row.button ..
            " id=" .. tostring(row.id) ..
            " native=" .. tostring(row.nativeSlot) ..
            " live=" .. tostring(row.liveSlot) ..
            " -> " .. tostring(row.liveName) ..
            " (" .. tostring(row.liveSub) .. ")" ..
            " rendered=" .. tostring(row.rendered) ..
            " / " .. tostring(row.renderedSub))
  end

  U.Print("  full dump in UnrealUIDiagDB.spellbookRanks - " ..
          "|cffffff00/reload|r then open " .. U.SavedVariablesHint())
end

local function Reapply()
  StripDecorations()
  if panel then panel:Show() end

  local i
  for i = 1, SpellCount() do StyleSpellButton(i, true) end
  SetSpellFont(G("SpellBookTitleText"), M.fontSize.large, SPELL_GOLD)
  SetSpellFont(G("SpellBookPageText"), M.fontSize.normal, SPELL_WHITE)
end

local function BuildFrame()
  frame = G("SpellBookFrame")
  if not frame then
    U.Debug("spellbook: native frame unavailable")
    return false
  end

  StripDecorations()

  panel = U.CreatePanel(frame, {
    name = "UnrealUISpellBookPanel",
    width = 450,
    height = 500,
    background = { 0.01, 0.01, 0.01, 0.78 },
  })
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 72)
  pcall(panel.EnableMouse, panel, false)

  pcall(frame.SetHitRectInsets, frame, 12, 30, 12, 72)

  local frameLevelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if frameLevelOk and tonumber(frameLevel) then
    pcall(panel.SetFrameLevel, panel, frameLevel)
  end

  local title = G("SpellBookTitleText")
  if title then
    pcall(function()
      title:ClearAllPoints()
      title:SetPoint("TOP", panel, "TOP", 0, -10)
    end)
  end
  SetSpellFont(title, M.fontSize.large, SPELL_GOLD)

  U.StyleStockCloseButton(G("SpellBookCloseButton"), panel, -6, -6)
  -- SpellBookCloseButton is anchored to panel, whose right edge is 30px
  -- inside SpellBookFrame. Reserve its full horizontal bounds so the raised
  -- header drag handle cannot steal hover/clicks from the button's upper
  -- section (same fix as modules/character.lua's headerInset).
  U.MakeWindowDraggable("spellbook", frame, {
    headerHeight = 76,
    headerInset = 54,
  })
  StyleBookTabs()

  local i
  for i = 1, SpellCount() do StyleSpellButton(i, false) end
  StyleSkillTabs()

  U.StyleStockArrowButton(G("SpellBookPrevPageButton"), "left", 18)
  U.StyleStockArrowButton(G("SpellBookNextPageButton"), "right", 18)
  SetSpellFont(G("SpellBookPageText"), M.fontSize.normal, SPELL_WHITE)

  U.PostHookScript(frame, "OnShow", Reapply)
  U.PostHookScript(frame, "OnHide", function()
    if panel then panel:Hide() end
  end)
  U.PostHookGlobal("SpellBook_Update", Reapply)

  local shown = false
  if frame.IsShown then
    local shownOk, value = pcall(frame.IsShown, frame)
    shown = shownOk and value and true or false
  end
  if shown then Reapply() else panel:Hide() end
  return true
end

function SB:OnInit()
  config = U.ModuleConfig("spellbook",
                          { highestRankOnly = false, barHint = true })
end

function SB:OnEnable()
  -- The native themes keep the client's own Spellbook chrome, so only the skin
  -- is skipped. The highest-rank filter is behaviour rather than chrome and is
  -- installed for every theme.
  if not U.ThemeStyleUsesNativeChrome() then BuildFrame() end
  rank.Install()
  missing.Install()
end
