-- unrealUI :: modules/spellbookprofessions.lua
--
-- The modern-wow Spellbook's Professions tab and page: a bottom tab beside
-- Spellbook that swaps the spell pages for the Dragonflight professions pages,
-- with two primary rows (icon ring, name, rank, skill bar) and four secondary
-- rows (Poisons, Fishing, Cooking, First Aid).
--
-- Built only by modules/spellbookmodernwow.lua's drawing path, which asks for
-- the tab while dressing its bottom tabs; nothing here runs under any other
-- theme.
--
-- Mechanism is WORKING_SOURCE from WoW-DragonflightUI (Mixin/UI.mixin.lua
-- SpellbookEraProfessions, Mixin/ProfessionSpellbook.mixin.lua,
-- XML/ProfessionSpellbook.xml), adapted to this client:
--
--  * DragonflightUI casts from its own SecureActionButtons. Neither exists
--    here: CastSpell and CastSpellByName are protected (documentation.json),
--    and addon-driven casting already failed in game on the pet bar
--    (knowledge.json / petbar.castpetaction_protected_no_custom_pet_bar).
--    The page instead reuses the client's own SpellButton1-12. While it is
--    open, modules/spellbook.lua's SpellBook_GetSpellID wrapper maps each
--    button to a profession spell slot, and the client honours that mapping
--    for icon, name, tooltip, click and drag (knowledge.json /
--    spellbook.rank_filter_native_mapping_unverified, BEHAVIOR_VERIFIED).
--  * DragonflightUI resolves professions by skill ID through GetSpellInfo and
--    GetSpellBookItemName, neither of which exists here. Skill lines are
--    matched by their localized name (names from DragonflightUI's
--    Localization/BlizzardData/Professions.lua) and profession spells are
--    found in the General tab (knowledge.json /
--    spellbook.general_tab_is_first_class_abilities_follow) by name, or by
--    icon for spells named differently from their skill (Find Herbs,
--    Smelting, Basic Campfire). The icon names are not runtime-verified.
--  * A skill line under a collapsed Skills header is not listed by
--    GetNumSkillLines (documentation.json), so that profession shows as not
--    learned until the header is expanded again.
--
-- Local budget: one table, per rules/unreal-ui.md.

local U = UnrealUI
local M = U.media

local prof = {
  active = false,
  available = true,
  frame = nil,
  tab = nil,
  page = nil,
  rows = nil,
  slotById = {},
  placeByIndex = {},
  shown = {},
  title = nil,
}

-- Skill-line names, every UnrealUI locale merged into one lookup: a name is
-- only ever looked up, and no name means a different profession in another
-- of these languages.
prof.NAMES = {
  alchemy = { "Alchemy", "Alchimie", "Алхимия", "炼金术" },
  blacksmithing = { "Blacksmithing", "Forge", "Кузнечное дело", "锻造" },
  enchanting = { "Enchanting", "Enchantement", "Наложение чар", "附魔" },
  engineering = { "Engineering", "Ingénierie", "Инженерное дело", "工程学" },
  herbalism = { "Herbalism", "Herboristerie", "Травничество", "草药学" },
  leatherworking = { "Leatherworking", "Travail du cuir", "Кожевничество",
                     "制皮" },
  mining = { "Mining", "Minage", "Горное дело", "采矿" },
  skinning = { "Skinning", "Dépeçage", "Снятие шкур", "剥皮" },
  tailoring = { "Tailoring", "Couture", "Портняжное дело", "裁缝" },
  cooking = { "Cooking", "Cuisine", "Кулинария", "烹饪" },
  fishing = { "Fishing", "Pêche", "Рыбная ловля", "钓鱼" },
  firstaid = { "First Aid", "Secourisme", "Первая помощь", "急救" },
  poisons = { "Poisons", "Яды", "毒药" },
}

prof.PRIMARY = {
  alchemy = true, blacksmithing = true, enchanting = true, engineering = true,
  herbalism = true, leatherworking = true, mining = true, skinning = true,
  tailoring = true,
}

-- Spells named differently from their skill, matched by name before the icon
-- fallback below, every locale merged as in prof.NAMES. Basic Campfire is in
-- the General tab (knowledge.json /
-- spellbook.general_tab_is_first_class_abilities_follow, measured by its
-- English name); the other names are the clients' usual translations and are
-- not runtime-verified.
prof.SPELL_NAMES = {
  cooking = { "Basic Campfire", "Feu de camp basique", "Простой костер",
              "Простой костёр", "基础营火" },
}

-- Lower-case icon file names of each profession's spells, in the order they
-- are preferred. The first also stands in as the ring icon when no spell is
-- found.
prof.ICONS = {
  alchemy = { "trade_alchemy" },
  blacksmithing = { "trade_blacksmithing" },
  enchanting = { "trade_engraving" },
  engineering = { "trade_engineering" },
  herbalism = { "inv_misc_flower_02" },
  leatherworking = { "inv_misc_armorkit_17" },
  mining = { "spell_fire_flameblades", "spell_nature_earthquake" },
  skinning = { "inv_misc_pelt_wolf_01" },
  tailoring = { "trade_tailoring" },
  cooking = { "inv_misc_food_15", "spell_fire_fire" },
  fishing = { "trade_fishing" },
  firstaid = { "spell_holy_sealofsacrifice" },
  poisons = { "trade_brewpoison" },
}

function prof.Token()
  return M.modernWow.spellBook.professions
end

-- pcall on a client global; returns ok followed by its results.
function prof.Call(name, a, b)
  local fn = U.G(name)
  if type(fn) ~= "function" then return false end
  return pcall(fn, a, b)
end

function prof.Shown(object)
  if not object or not object.IsShown then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

function prof.BookType()
  local book = U.G("BOOKTYPE_SPELL")
  if type(book) ~= "string" or book == "" then book = "spell" end
  return book
end

-- Just past the client's own spell bound, which SpellButton_UpdateButton
-- draws as an empty slot (the same value modules/spellbook.lua's filter uses).
function prof.Empty()
  local max = tonumber(U.G("MAX_SPELLS"))
  if max then return max + 1 end
  return 100000
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
function prof.Lookup()
  if prof.lookup then return prof.lookup end
  local lookup = {}
  local key, names
  for key, names in pairs(prof.NAMES) do
    local i
    for i = 1, table.getn(names) do lookup[names[i]] = key end
  end
  prof.lookup = lookup
  return lookup
end

function prof.GeneralSpells()
  local list = {}
  local ok, _, _, offset, count = prof.Call("GetSpellTabInfo", 1)
  offset, count = tonumber(offset), tonumber(count)
  if not ok or not offset or not count then return list end

  local book = prof.BookType()
  local slot
  for slot = offset + 1, offset + count do
    local nameOk, name = prof.Call("GetSpellName", slot, book)
    if nameOk and type(name) == "string" then
      local iconOk, icon = prof.Call("GetSpellTexture", slot, book)
      table.insert(list, {
        slot = slot,
        name = name,
        icon = iconOk and type(icon) == "string" and string.lower(icon) or "",
      })
    end
  end
  return list
end

function prof.IconIs(icon, file)
  local length = string.len(file)
  return string.len(icon) >= length and string.sub(icon, -length) == file
end

-- Up to two spells for one profession: its same-named spell first (the last
-- slot, should a lower rank still be listed), then prof.SPELL_NAMES, then one
-- per icon name. The first sits on the row's right slot, the second left of it
-- (M.modernWow.spellBook.professions.button.leftX).
function prof.FindSpells(entry, spells)
  local found, seen = {}, {}
  local i

  local byName
  for i = 1, table.getn(spells) do
    if spells[i].name == entry.name then byName = spells[i] end
  end
  if byName then
    table.insert(found, byName)
    seen[byName.name] = true
  end

  local names = prof.SPELL_NAMES[entry.key] or {}
  local n
  for n = 1, table.getn(names) do
    for i = 1, table.getn(spells) do
      local spell = spells[i]
      if not seen[spell.name] and spell.name == names[n] and
         table.getn(found) < 2 then
        table.insert(found, spell)
        seen[spell.name] = true
      end
    end
  end

  local icons = prof.ICONS[entry.key] or {}
  local k
  for k = 1, table.getn(icons) do
    local match
    for i = 1, table.getn(spells) do
      local spell = spells[i]
      if not seen[spell.name] and prof.IconIs(spell.icon, icons[k]) then
        match = spell
      end
    end
    if match and table.getn(found) < 2 then
      table.insert(found, match)
      seen[match.name] = true
    end
  end
  return found
end

function prof.Scan()
  local lookup = prof.Lookup()
  local rows = { primary = {} }
  local ok, count = prof.Call("GetNumSkillLines")
  count = ok and tonumber(count) or 0

  local i
  for i = 1, count do
    local lineOk, name, header, _, rank, _, modifier, maxRank =
      prof.Call("GetSkillLineInfo", i)
    local key = lineOk and not header and type(name) == "string" and
                lookup[name]
    if key then
      local entry = {
        key = key,
        index = i,
        name = name,
        rank = tonumber(rank) or 0,
        modifier = tonumber(modifier) or 0,
        maxRank = tonumber(maxRank) or 0,
      }
      if prof.PRIMARY[key] then
        if table.getn(rows.primary) < 2 then
          table.insert(rows.primary, entry)
        end
      else
        rows[key] = entry
      end
    end
  end

  local spells = prof.GeneralSpells()
  local list = { rows.primary[1], rows.primary[2], rows.poisons,
                 rows.fishing, rows.cooking, rows.firstaid }
  for i = 1, 6 do
    if list[i] then list[i].spells = prof.FindSpells(list[i], spells) end
  end
  rows.ordered = list
  return rows
end

function prof.RankTitle(maxRank)
  local ranks = prof.Token().ranks
  local title = nil
  local i
  for i = 1, table.getn(ranks) do
    if maxRank >= ranks[i] then title = U.L("SPELLBOOK_PROF_RANK_" .. i) end
  end
  return title or U.L("SPELLBOOK_PROF_RANK_1")
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- A page-art rectangle as TOPLEFT window units.
function prof.Place(region, x, y, width, height)
  if not region then return end
  local left, top = U.ModernWowSpellBookPagePoint(x, y)
  local kx, ky = U.ModernWowSpellBookPageScale()
  if not left or not kx then return end
  pcall(function()
    region:ClearAllPoints()
    if width then region:SetWidth(width * kx) end
    if height then region:SetHeight(height * ky) end
    region:SetPoint("TOPLEFT", prof.frame, "TOPLEFT", left, -top)
  end)
end

function prof.Part(parent, layer, cell)
  local parts = prof.Token().parts
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, prof.Token().texture.parts)
  pcall(texture.SetTexCoord, texture, cell.left / parts.width,
        cell.right / parts.width, cell.top / parts.height,
        cell.bottom / parts.height)
  return texture
end

-- The page number's shadow-free route (modules/spellbookmodernwow.lua,
-- PlaceWindowControls). U.SetStockFont left these strings dark with a doubled
-- shadow on the parchment (USER_CONFIRMED_INGAME, 2026-09-14).
function prof.Text(parent, size, color, width)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  U.SetFont(text, size, nil, nil, true)
  pcall(text.SetTextColor, text, M.Unpack(color))
  U.ClearTextShadow(text)
  pcall(text.SetJustifyH, text, "LEFT")
  if width then
    local kx = U.ModernWowSpellBookPageScale()
    if kx then pcall(text.SetWidth, text, width * kx) end
  end
  return text
end

-- Skill bar: the shared two-texture bar (a native StatusBar does not lay out
-- its fill here, knowledge.json / statusbar.native_widget_fill_not_laid_out)
-- carrying the professions fill, with the atlas end pieces around it.
function prof.BuildBar(parent, x, y)
  local t = prof.Token()
  local cfg = t.bar
  local kx, ky = U.ModernWowSpellBookPageScale()

  -- The dark track -- rounded left end, middle, rounded right end -- is laid
  -- out on the page in page texels, the way the ring is, each piece at its
  -- own explicit rect beneath the bar frame. Hung off the bar's edges, the
  -- right end did not show and the track ended square (user report,
  -- 2026-09-14); the cause was not isolated.
  local track = {
    prof.Part(parent, "BACKGROUND", t.parts.barLeft),
    prof.Part(parent, "BACKGROUND", t.parts.barMiddle),
    prof.Part(parent, "BACKGROUND", t.parts.barRight),
  }
  local trackY = y - cfg.capLift
  prof.Place(track[1], x - cfg.cap, trackY, cfg.cap, cfg.cap)
  prof.Place(track[2], x, trackY, cfg.width, cfg.cap)
  prof.Place(track[3], x + cfg.width, trackY, cfg.cap, cfg.cap)

  local bar = U.CreateStatusBar(parent, {
    width = cfg.width * kx,
    height = cfg.height * ky,
    texture = t.texture.fill,
    color = { 1, 1, 1, 1 },
    background = { 0, 0, 0, 0 },
  })
  prof.Place(bar, x, y)
  pcall(bar.EnableMouse, bar, false)
  bar.track = track

  -- The green rounded ends of the fill: the left one sized by prof.SetProgress,
  -- the right one once the skill is at its maximum (DragonflightUI's
  -- capRight). The left cap is anchored by its LEFT edge so a cropped cap
  -- keeps its rounded end where the full one starts.
  local lift = cfg.capLift * ky
  local endCap = cfg.endCap * kx
  local caps = {
    { cell = t.parts.capLeft, point = "LEFT", relative = "LEFT", x = -endCap },
    { cell = t.parts.capRight, point = "LEFT", relative = "RIGHT", x = 0 },
  }
  local regions = {}
  local i
  for i = 1, 2 do
    local cap = caps[i]
    local region = prof.Part(bar, "OVERLAY", cap.cell)
    if region then
      pcall(function()
        region:SetWidth(endCap)
        region:SetHeight(endCap)
        region:SetPoint(cap.point, bar, cap.relative, cap.x, lift)
      end)
    end
    regions[i] = region
  end
  bar.capLeft, bar.capRight = regions[1], regions[2]
  bar.endCap, bar.runWidth = endCap, cfg.width * kx

  bar.text = prof.Text(bar, M.fontSize.tiny, t.barTextColor)
  pcall(function()
    bar.text:SetPoint("LEFT", bar, "LEFT", cfg.textInset * kx,
                      lift - cfg.textDrop)
    bar.text:SetJustifyH("LEFT")
  end)
  return bar
end

-- ---------------------------------------------------------------------------
-- Unlearn button
--
-- WORKING_SOURCE: WoW-DragonflightUI XML/ProfessionSpellbook.xml's
-- UnlearnButton, on the primary rows only, its right edge `gap` left of the
-- skill bar and centred on it. Its glyph is the path modules/character.lua
-- already draws on the native skill-detail unlearn button.
--
-- DragonflightUI confirms through StaticPopup "UNLEARN_SKILL"; query_compat.py
-- has no record of StaticPopup on this client, so the shared U.ShowConfirm
-- asks instead. AbandonSkill(skillIndex) is DOCUMENTED_NOT_RUNTIME_VERIFIED
-- (documentation.json). No hover tooltip: the shared GameTooltip is not
-- repurposed for explanatory text (rules/unreal-ui-design.md); the dialog
-- names the profession and the loss.
-- ---------------------------------------------------------------------------
function prof.SetUnlearnState(button, state)
  local cfg = prof.Token().unlearn
  local icon = button.icon
  if not icon then return end
  local alpha, shift = cfg.alpha, 0
  if state == "hover" then alpha = cfg.hoverAlpha end
  if state == "pressed" then alpha, shift = cfg.hoverAlpha, cfg.pressShift end
  pcall(function()
    icon:SetAlpha(alpha)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", shift, -shift)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", shift, -shift)
  end)
end

-- `barX` is the bar's left edge and `centreY` its vertical centre, in page
-- texels.
function prof.BuildUnlearn(page, row, barX, centreY)
  local t = prof.Token()
  local cfg = t.unlearn
  local ok, button = pcall(CreateFrame, "Button", nil, page)
  if not ok or not button then return nil end

  prof.Place(button, barX - cfg.gap - cfg.size,
             centreY - cfg.size / 2 - cfg.lift, cfg.size, cfg.size)
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp")

  -- A texture created on a button here stays hidden until shown explicitly
  -- (modules/character.lua, skillunlearn.icon_field.v1).
  local iconOk, icon = pcall(button.CreateTexture, button, nil, "ARTWORK")
  if iconOk and icon then
    pcall(icon.SetTexture, icon, t.texture.unlearn)
    pcall(icon.Show, icon)
    button.icon = icon
  end
  prof.SetUnlearnState(button, "normal")

  local hovered = false
  button:SetScript("OnEnter", function()
    hovered = true
    prof.SetUnlearnState(button, "hover")
  end)
  button:SetScript("OnLeave", function()
    hovered = false
    prof.SetUnlearnState(button, "normal")
  end)
  button:SetScript("OnMouseDown", function()
    prof.SetUnlearnState(button, "pressed")
  end)
  button:SetScript("OnMouseUp", function()
    prof.SetUnlearnState(button, hovered and "hover" or "normal")
  end)
  button:SetScript("OnClick", function() prof.ConfirmUnlearn(row) end)
  return button
end

-- The skill-line index is looked up again by name on accept: expanding or
-- collapsing a Skills header since the page was filled shifts every index.
function prof.SkillIndex(name)
  local ok, count = prof.Call("GetNumSkillLines")
  count = ok and tonumber(count) or 0
  local i
  for i = 1, count do
    local lineOk, lineName, header = prof.Call("GetSkillLineInfo", i)
    if lineOk and not header and lineName == name then return i end
  end
  return nil
end

function prof.ConfirmUnlearn(row)
  local entry = row.entry
  if not entry then return end
  local name = entry.name
  U.ShowConfirm({
    owner = prof,
    centered = true,
    modernWow = true,
    text = string.format(U.L("SPELLBOOK_PROF_UNLEARN_CONFIRM"), name),
    detail = U.L("SPELLBOOK_PROF_UNLEARN_DETAIL"),
    acceptText = U.L("SPELLBOOK_PROF_UNLEARN"),
    onAccept = function()
      local index = prof.SkillIndex(name)
      if not index then return end
      local ok, err = prof.Call("AbandonSkill", index)
      if not ok and err then U.Error("AbandonSkill: " .. tostring(err)) end
      prof.Refresh()
    end,
  })
end

-- The green run is the left cap plus the bar, filled in proportion to the
-- skill. DragonflightUI always draws the full 12-unit cap outside its bar, so
-- 1/75 read as about an eighth of the bar (user report, 2026-09-15). Here the
-- cap is the run's first stretch: below its width only its left part shows,
-- cropped rather than squeezed so the rounded end keeps its shape, and the
-- fill takes over past it.
function prof.SetProgress(bar, rank, maxRank)
  local cap, width = bar.endCap, bar.runWidth
  local share = 0
  if maxRank > 0 then share = math.min(math.max(rank / maxRank, 0), 1) end
  local green = (cap + width) * share
  local capShown = math.min(green, cap)

  bar:SetMinMaxValues(0, width)
  bar:SetValue(green - capShown)

  local region = bar.capLeft
  if not region then return end
  if capShown <= 0 then
    prof.SetShown(region, false)
    return
  end
  local cell = prof.Token().parts.capLeft
  local atlas = prof.Token().parts
  local right = cell.left + (cell.right - cell.left) * capShown / cap
  pcall(function()
    region:SetTexCoord(cell.left / atlas.width, right / atlas.width,
                       cell.top / atlas.height, cell.bottom / atlas.height)
    region:SetWidth(capShown)
    region:Show()
  end)
end

function prof.BuildPrimary(page, top, missingKey)
  local t = prof.Token()
  local cfg, ring = t.primary, t.ring
  local x = t.rowLeft
  local textX = x + cfg.barX - t.bar.cap
  local row = { primary = true, missingKey = missingKey }

  local centreX = x + ring.x + ring.size / 2
  local centreY = top + ring.y + ring.size / 2
  row.icon = page:CreateTexture(nil, "BORDER")
  pcall(row.icon.SetTexCoord, row.icon, 0.08, 0.92, 0.08, 0.92)
  prof.Place(row.icon, centreX - ring.icon / 2, centreY - ring.icon / 2,
             ring.icon, ring.icon)
  row.ring = prof.Part(page, "ARTWORK", t.parts.ring)
  prof.Place(row.ring, x + ring.x, top + ring.y, ring.size, ring.size)

  row.name = prof.Text(page, M.fontSize.large, t.nameColor)
  prof.Place(row.name, textX, top + cfg.nameY)
  row.rank = prof.Text(page, M.fontSize.small, t.rankColor)
  prof.Place(row.rank, textX, top + cfg.rankY)
  row.bar = prof.BuildBar(page, x + cfg.barX, top + cfg.barY)
  row.unlearn = prof.BuildUnlearn(page, row, x + cfg.barX,
                                  top + cfg.barY + t.bar.height / 2)

  row.missingHeader = prof.Text(page, M.fontSize.large, t.missingHeaderColor,
                                cfg.missingWidth)
  prof.Place(row.missingHeader, x + cfg.missingX, top + cfg.missingY)
  row.missingText = prof.Text(page, M.fontSize.small, t.missingTextColor,
                              cfg.missingWidth)
  pcall(function()
    row.missingText:SetPoint("TOPLEFT", row.missingHeader, "BOTTOMLEFT", 0, -2)
  end)
  return row
end

function prof.BuildSecondary(page, top, missingKey)
  local t = prof.Token()
  local cfg = t.secondary
  local x = t.rowLeft
  local textX = x + cfg.barX - t.bar.cap
  local row = { missingKey = missingKey }

  row.name = prof.Text(page, M.fontSize.normal, t.nameColor)
  prof.Place(row.name, textX, top + cfg.nameY)
  row.rank = prof.Text(page, M.fontSize.tiny, t.rankColor)
  prof.Place(row.rank, textX, top + cfg.rankY)
  row.bar = prof.BuildBar(page, x + cfg.barX, top + cfg.barY)

  row.missingHeader = prof.Text(page, M.fontSize.large, t.missingHeaderColor)
  prof.Place(row.missingHeader, x + cfg.missingX, top + cfg.missingY)
  row.missingText = prof.Text(page, M.fontSize.small, t.missingTextColor,
                              cfg.missingWidth)
  prof.Place(row.missingText, cfg.missingTextX, top + cfg.missingY)
  return row
end

function prof.BuildPage()
  local frame = prof.frame
  local ok, page = pcall(CreateFrame, "Frame", nil, frame)
  if not ok or not page then error("professions page could not be created") end
  pcall(page.SetAllPoints, page, frame)
  pcall(page.EnableMouse, page, false)
  pcall(page.Hide, page)

  local t = prof.Token()

  -- The book in the gold ring, over the hidden class portrait. On this page
  -- frame rather than the window: the window's own redress hides every
  -- region whose path is not the addon's (book.StripForeign).
  local left, top, size = U.ModernWowSpellBookShowClassPortrait(true)
  if left then
    local icon = page:CreateTexture(nil, "ARTWORK")
    pcall(icon.SetTexture, icon, t.portrait)
    pcall(function()
      icon:SetWidth(size)
      icon:SetHeight(size)
      icon:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    end)
  end
  prof.rows = {
    prof.BuildPrimary(page, t.primaryTop[1], "SPELLBOOK_PROF_FIRST"),
    prof.BuildPrimary(page, t.primaryTop[2], "SPELLBOOK_PROF_SECOND"),
    -- Poisons is class-specific, so its row stays blank when missing, as
    -- DragonflightUI leaves its first secondary row.
    prof.BuildSecondary(page, t.secondaryTop[1], nil),
    prof.BuildSecondary(page, t.secondaryTop[2], "SPELLBOOK_PROF_FISHING"),
    prof.BuildSecondary(page, t.secondaryTop[3], "SPELLBOOK_PROF_COOKING"),
    prof.BuildSecondary(page, t.secondaryTop[4], "SPELLBOOK_PROF_FIRST_AID"),
  }
  prof.page = page
end

function prof.SetShown(region, shown)
  if not region then return end
  if shown then
    pcall(region.Show, region)
  else
    pcall(region.Hide, region)
  end
end

function prof.FillRow(row, entry)
  local t = prof.Token()
  local learned = entry and true or false
  row.entry = entry

  prof.SetShown(row.unlearn, learned)
  prof.SetShown(row.name, learned)
  prof.SetShown(row.rank, learned)
  prof.SetShown(row.bar, learned)
  local p
  for p = 1, table.getn(row.bar.track) do
    prof.SetShown(row.bar.track[p], learned)
  end
  prof.SetShown(row.missingHeader, not learned)
  prof.SetShown(row.missingText, not learned)

  if learned then
    pcall(row.name.SetText, row.name, entry.name)
    pcall(row.rank.SetText, row.rank, prof.RankTitle(entry.maxRank))

    prof.SetProgress(row.bar, entry.rank, entry.maxRank)
    local value = entry.rank .. "/" .. entry.maxRank
    if entry.modifier > 0 then
      value = entry.rank .. " (+" .. entry.modifier .. ")/" .. entry.maxRank
    end
    pcall(row.bar.text.SetText, row.bar.text, value)
    prof.SetShown(row.bar.capRight,
                  entry.maxRank > 0 and entry.rank >= entry.maxRank)
  else
    local header = row.missingKey and U.L(row.missingKey) or ""
    pcall(row.missingHeader.SetText, row.missingHeader, header)
    local text = ""
    if row.missingKey then
      text = U.L(row.primary and "SPELLBOOK_PROF_MISSING" or
                 "SPELLBOOK_PROF_NOT_LEARNED")
    end
    pcall(row.missingText.SetText, row.missingText, text)
  end

  if row.icon then
    local path = t.missingIcon
    if learned then
      local spell = entry.spells and entry.spells[1]
      if spell and spell.icon ~= "" then
        path = spell.icon
      else
        path = "Interface\\Icons\\" .. prof.ICONS[entry.key][1]
      end
    end
    pcall(row.icon.SetTexture, row.icon, path)
    pcall(row.icon.SetDesaturated, row.icon, not learned)
    pcall(row.icon.SetAlpha, row.icon, learned and 1 or t.missingIconAlpha)
  end
end

-- ---------------------------------------------------------------------------
-- Native spell buttons
--
-- Two per row, in row order: SpellButton1-2 on the first primary row through
-- SpellButton11-12 on First Aid. The mapping is keyed by each button's GetID,
-- the index SpellBook_GetSpellID is called with, which is not its name suffix
-- (knowledge.json / spellbook.rank_filter_native_mapping_unverified).
-- ---------------------------------------------------------------------------
function prof.ButtonPlace(rowIndex, position)
  local t = prof.Token()
  local cfg = t.button
  local x, y
  if rowIndex <= 2 then
    x = cfg.x
    y = t.primaryTop[rowIndex] + (position == 1 and cfg.primaryY or cfg.y)
  else
    x = position == 1 and cfg.x or cfg.leftX
    y = t.secondaryTop[rowIndex - 2] + cfg.y
  end

  local left, top = U.ModernWowSpellBookPagePoint(x, y)
  local kx = U.ModernWowSpellBookPageScale()
  if not left or not kx then return nil end

  -- The name plate, sized off the live button against the template's.
  local cell, plate = t.parts.nameFrame, cfg.nameFrame
  local w, h = t.parts.width, t.parts.height
  return { x = left, y = top, size = cfg.size * kx,
           textWidth = cfg.textWidth * kx, subColor = t.subSpellColor,
           plainSlot = true,
           nameFrame = {
             path = t.texture.parts,
             u1 = cell.left / w, u2 = cell.right / w,
             v1 = cell.top / h, v2 = cell.bottom / h,
             width = plate.width * kx, height = plate.height * kx,
             x = plate.x * kx, alpha = plate.alpha,
           } }
end

function prof.Assign(rows)
  prof.slotById, prof.placeByIndex = {}, {}
  local r
  for r = 1, 6 do
    local entry = rows.ordered[r]
    local spells = entry and entry.spells or {}
    local s
    for s = 1, 2 do
      local index = (r - 1) * 2 + s
      prof.placeByIndex[index] = prof.ButtonPlace(r, s)
      local button = U.G("SpellButton" .. index)
      local spell = spells[s]
      if button and spell and button.GetID then
        local ok, id = pcall(button.GetID, button)
        if ok and tonumber(id) then prof.slotById[tonumber(id)] = spell.slot end
      end
    end
  end
end

function prof.Placer(index)
  if not prof.active then return nil end
  return prof.placeByIndex[index]
end

-- ---------------------------------------------------------------------------
-- Spellbook controls that belong to the spell pages only
-- ---------------------------------------------------------------------------
prof.CONTROLS = {
  "SpellBookPrevPageButton", "SpellBookNextPageButton", "SpellBookPageText",
  "UnrealUISpellBookRank", "UnrealUISpellBookBarHint",
}

function prof.SuppressControls()
  local i
  for i = 1, table.getn(prof.CONTROLS) do
    prof.SetShown(U.G(prof.CONTROLS[i]), false)
  end
  local count = tonumber(U.G("MAX_SKILLLINE_TABS")) or 8
  for i = 1, count do
    prof.SetShown(U.G("SpellBookSkillLineTab" .. i), false)
  end

  local title = U.G("SpellBookTitleText")
  if title then
    pcall(title.SetText, title, U.L("SPELLBOOK_PROFESSIONS"))
  end
end

function prof.HideControls()
  prof.shown = {}
  local i
  for i = 1, table.getn(prof.CONTROLS) do
    prof.shown[i] = prof.Shown(U.G(prof.CONTROLS[i]))
  end
  local title = U.G("SpellBookTitleText")
  if title and title.GetText then
    local ok, text = pcall(title.GetText, title)
    prof.title = ok and text or nil
  end
  prof.SuppressControls()
end

-- Skill-line tabs are the client's to show again, from SpellBookFrame_Update.
function prof.RestoreControls()
  local i
  for i = 1, table.getn(prof.CONTROLS) do
    if prof.shown[i] then prof.SetShown(U.G(prof.CONTROLS[i]), true) end
  end
  local title = U.G("SpellBookTitleText")
  if title and prof.title then pcall(title.SetText, title, prof.title) end
end

-- ---------------------------------------------------------------------------
-- Enter / leave
-- ---------------------------------------------------------------------------
function prof.Repaint()
  if type(U.SpellBookRepaintButtons) == "function" then
    U.SpellBookRepaintButtons()
  end
end

function prof.Fill()
  local rows = prof.Scan()
  prof.Assign(rows)
  local i
  for i = 1, 6 do prof.FillRow(prof.rows[i], rows.ordered[i]) end
end

-- After an unlearn, and on the skill/spell events that follow one. Neither
-- event is runtime-verified to fire for AbandonSkill, so the accept path
-- refreshes directly as well.
function prof.Refresh()
  if not prof.active or not prof.page then return end
  prof.Fill()
  prof.Repaint()
end

function prof.Enter()
  if prof.active or not prof.available or not prof.frame then return end
  if type(U.ModernWowSpellBookActive) ~= "function" or
     not U.ModernWowSpellBookActive() then
    return
  end
  if not prof.page then prof.BuildPage() end

  -- Profession spells live in the player book.
  local frame = prof.frame
  local playerBook = prof.BookType()
  if frame.bookType ~= playerBook then
    frame.bookType = playerBook
    prof.Call("SpellBookFrame_Update", 1)
  end

  prof.active = true
  prof.Fill()

  U.ModernWowSpellBookSetPageArt(prof.Token().texture.pageLeft,
                                 prof.Token().texture.pageRight)
  prof.HideControls()
  U.ModernWowSpellBookRedress()
  U.ModernWowSpellBookShowClassPortrait(false)
  pcall(prof.page.Show, prof.page)
  prof.Repaint()
end

function prof.Leave()
  if not prof.active then return end
  prof.active = false
  if prof.page then pcall(prof.page.Hide, prof.page) end

  U.ModernWowSpellBookSetPageArt(nil, nil)
  U.ModernWowSpellBookShowClassPortrait(true)
  prof.RestoreControls()
  U.ModernWowSpellBookRedress()
  prof.Call("SpellBookFrame_Update", 1)
  prof.Repaint()
end

-- The window reopens on the book it closed on, as the native tabs do, so the
-- tab group is pointed back at that book's tab.
function prof.OnWindowHide()
  U.HideConfirm(prof)
  prof.Leave()
  if prof.tab and prof.tab.SetActive then prof.tab.SetActive(false) end

  local pet = U.G("BOOKTYPE_PET")
  local onPet = prof.frame and type(pet) == "string" and
                prof.frame.bookType == pet and true or false
  if prof.spellTab and prof.spellTab.SetActive then
    prof.spellTab.SetActive(not onPet)
  end
  local petTab = U.G("SpellBookFrameTabButton2")
  if petTab and petTab.SetActive then petTab.SetActive(onPet) end
end

-- The owned Spellbook tab stands in for the client's, which the client shows
-- again on its own updates whenever a pet is out.
function prof.HideNativeSpellTab()
  prof.SetShown(U.G("SpellBookFrameTabButton1"), false)
end

function prof.OnBookUpdate()
  prof.HideNativeSpellTab()
  if prof.active then prof.SuppressControls() end
end

function prof.OnSpellTabClick()
  prof.Leave()
  if type(U.SpellBookSelectBook) == "function" then
    U.SpellBookSelectBook(prof.BookType())
  end
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- Profession identity for the modern-wow profession window
-- (modules/professions.lua), from the same localized name table this page
-- matches skill lines with: the key for a skill-line name (nil when the name
-- is not one of these professions), and that profession's stand-in icon.
function U.ModernWowProfessionKey(name)
  if type(name) ~= "string" then return nil end
  return prof.Lookup()[name]
end

function U.ModernWowProfessionIcon(key)
  local icons = key and prof.ICONS[key]
  if not icons then return nil end
  return "Interface\\Icons\\" .. icons[1]
end

-- Nil unless the page is open; then the profession slot for a native spell
-- button's id, or an empty slot for a button this page does not use.
function U.ModernWowProfessionSlot(index)
  if not prof.active then return nil end
  return prof.slotById[index] or prof.Empty()
end

function U.ModernWowProfessionsSetAvailable(available)
  prof.available = available and true or false
  if not prof.available then
    prof.Leave()
    if prof.tab then pcall(prof.tab.Hide, prof.tab) end
    -- The Pet tab was chained to Professions; it follows Spellbook instead.
    local petTab = U.G("SpellBookFrameTabButton2")
    if petTab and prof.spellTab then
      pcall(function()
        petTab:ClearAllPoints()
        petTab:SetPoint("LEFT", prof.spellTab, "RIGHT",
                        M.modernWow.spellBook.bottomTab.gap, 0)
      end)
    end
  end
end

-- An addon-owned bottom tab, sized to its label; the caller's tab group
-- styles, chains and selects it.
function prof.CreateTab(frame, name, text, onClick)
  local ok, tab = pcall(CreateFrame, "Button", name, frame)
  if not ok or not tab then return nil end

  -- Button:SetFontString is not in this client's documentation; the label is
  -- handed back directly when the button does not report it.
  local label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  pcall(tab.SetFontString, tab, label)
  local ownOk, own = false, nil
  if tab.GetFontString then ownOk, own = pcall(tab.GetFontString, tab) end
  if not ownOk or not own then
    tab.GetFontString = function() return label end
  end
  pcall(label.SetText, label, text)
  pcall(label.SetPoint, label, "CENTER", tab, "CENTER", 0, 0)

  local widthOk, width = pcall(label.GetStringWidth, label)
  if not widthOk or not tonumber(width) or width <= 0 then width = 60 end
  pcall(tab.SetWidth, tab, math.floor(width + 2 * M.modernWow.tab.padding + 0.5))
  pcall(tab.SetHeight, tab, M.modernWow.tab.height)
  pcall(tab.RegisterForClicks, tab, "LeftButtonUp")
  tab:SetScript("OnClick", onClick)
  return tab
end

-- The client's own Spellbook tab label, else the addon's.
function prof.SpellTabText()
  local native = U.G("SpellBookFrameTabButton1")
  if native and native.GetText then
    local ok, text = pcall(native.GetText, native)
    if ok and type(text) == "string" and text ~= "" then return text end
  end
  return U.L("SPELLBOOK_TAB")
end

-- Called once by modules/spellbookmodernwow.lua while dressing the bottom
-- tabs: { spellbook, professions }, which that module styles and chains ahead
-- of the client's Pet tab. Nil when either tab cannot be made, so the window
-- keeps the client's own tabs.
function U.ModernWowSpellBookExtraTabs(frame)
  if prof.tab and prof.spellTab then
    return { professions = prof.tab, spellbook = prof.spellTab }
  end
  if not frame then return nil end
  prof.frame = frame

  local professions = prof.CreateTab(frame, "UnrealUISpellBookProfessionsTab",
                                     U.L("SPELLBOOK_PROFESSIONS"),
                                     function() prof.Enter() end)
  local spellbook = prof.CreateTab(frame, "UnrealUISpellBookSpellsTab",
                                   prof.SpellTabText(), prof.OnSpellTabClick)
  if not professions or not spellbook then
    prof.SetShown(professions, false)
    prof.SetShown(spellbook, false)
    return nil
  end
  prof.tab, prof.spellTab = professions, spellbook

  prof.HideNativeSpellTab()
  local nativeSpell = U.G("SpellBookFrameTabButton1")
  if nativeSpell then
    U.PostHookScript(nativeSpell, "OnShow", prof.HideNativeSpellTab)
  end
  -- Installed before modules/spellbook.lua's book-tab hooks, so the page has
  -- already given the buttons back when that module repaints them.
  local petTab = U.G("SpellBookFrameTabButton2")
  if petTab then U.PostHookScript(petTab, "OnClick", prof.Leave) end
  U.PostHookScript(frame, "OnShow", prof.HideNativeSpellTab)
  U.PostHookScript(frame, "OnHide", prof.OnWindowHide)
  U.PostHookGlobal("SpellBookFrame_Update", prof.OnBookUpdate)
  U.RegisterEvent("SKILL_LINES_CHANGED", prof.Refresh)
  U.RegisterEvent("SPELLS_CHANGED", prof.Refresh)
  U.ModernWowSpellBookSetButtonPlacer(prof.Placer)
  return { professions = professions, spellbook = spellbook }
end
