-- unrealUI :: core/commands.lua
--
-- The /uui slash command.
--
-- The settings interface is a later module. It registers itself by assigning
-- U.OpenSettings, and both /uui and the minimap button will call through that
-- single entry point so they can never diverge.

local U = UnrealUI

-- ---------------------------------------------------------------------------
-- Diagnostic SavedVariables
--
-- The nameplate dump and self-check readouts got long enough to flood the
-- chat frame past what a player can usefully copy out. UnrealUIDiagDB is a
-- second SavedVariables table, separate from UnrealUIDB (core/config.lua),
-- used only as a write-out target for /uui commands -- never read back by the
-- addon itself, so none of config.lua's validation/whitelisting applies here.
-- A command writes into it and prints one short line; the full data is read
-- afterwards straight out of the SavedVariables file.
--
-- That file is NOT under the game install. This client keeps addon
-- SavedVariables in the Unreal save tree, the same place
-- .claude-shared/unreal-azeroth-runtime.md records for the probe:
--
--   %AppData%\..\Local\Azeroth\Saved\Account\<account>\SavedVariables\unrealUI.lua
--
-- There is no WTF folder on this client. Earlier revisions of these commands
-- printed the Vanilla WTF path, which sent readers to a directory that does
-- not exist and cost a later session real time.
-- ---------------------------------------------------------------------------
local function SaveDiagnostic(key, data)
  if type(UnrealUIDiagDB) ~= "table" then UnrealUIDiagDB = {} end
  UnrealUIDiagDB[key] = data

  local stamp = "?"
  if type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S")
    if ok and type(formatted) == "string" then stamp = formatted end
  end
  UnrealUIDiagDB[key .. "_savedAt"] = stamp
end

-- Shared with core/perf.lua: the perf recorder's report is numeric/table data
-- with nothing UI-only about it, so it writes into the same diagnostic store
-- other /uui commands use rather than only ever printing to a chat frame the
-- player would otherwise have to screenshot.
U.SaveDiagnostic = SaveDiagnostic

-- One place that knows where SavedVariables actually live, so no command can
-- print a path that does not exist again.
function U.SavedVariablesHint()
  return "AppData/Local/Azeroth/Saved/Account/<account>/SavedVariables/unrealUI.lua"
end

-- Appends rather than overwrites, so several runs survive in one session.
-- SaveDiagnostic keys are single-slot: a second /uui perf replaced the first,
-- which forced a /reload between every A/B comparison and made two runs
-- impossible to take under the same conditions. Capped so a long session cannot
-- grow the SavedVariables file without bound.
local APPEND_LIMIT = 12

function U.AppendDiagnostic(key, data)
  if type(UnrealUIDiagDB) ~= "table" then UnrealUIDiagDB = {} end
  if type(UnrealUIDiagDB[key]) ~= "table" then UnrealUIDiagDB[key] = {} end

  local list = UnrealUIDiagDB[key]
  table.insert(list, data)
  while table.getn(list) > APPEND_LIMIT do table.remove(list, 1) end
  return table.getn(list)
end

local function Trim(text)
  if type(text) ~= "string" then return "" end
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function Split(text)
  local space = string.find(text, " ")
  if not space then return string.lower(text), "" end
  return string.lower(string.sub(text, 1, space - 1)),
         Trim(string.sub(text, space + 1))
end

-- The diagnostic dumps stay in English in every language and are not part of
-- the translated catalog. They exist to be pasted into a bug report, where a
-- translated field name is worse than useless, and they are behind
-- `/uui help diag` so the listing a player actually reads stays short.
local DIAGNOSTIC_HELP = {
  "  |cffffff00/uui menu|r - dump the game menu rows and the UnrealUI entries",
  "  |cffffff00/uui bindscan|r - dump the client binding table",
  "  |cffffff00/uui keytest|r - measure whether key events reach addon frames",
  "  |cffffff00/uui elite|r - cycle the classification icon test",
  "  |cffffff00/uui np|r - dump WorldFrame children (nameplates)",
  "  |cffffff00/uui aura|r - dump the aura rows and why a timer is missing",
  "  |cffffff00/uui map|r - arm the map hover watch before opening it",
  "  |cffffff00/uui res|r - dump the Character sheet resistance frames",
  "  |cffffff00/uui abhl [alpha] [hover] [rest]|r - dump or tune the classic hover highlight",
  "  |cffffff00/uui abcd|r - dump why an action button shows no cooldown number",
  "  |cffffff00/uui cb|r - arm a placement dump for the native cast bar",
  "  |cffffff00/uui movertest|r - foundation mover smoke test",
  "  |cffffff00/uui perf|r - record frame time around target changes",
  "  |cffffff00/uui nosuppress|r - skip native frame suppression (needs /reload)",
  "  |cffffff00/uui suppress <0-4>|r - bisect the suppression recipe (needs /reload)",
}

local function ShowHelp(rest)
  if type(rest) == "string" and string.lower(Trim(rest)) == "diag" then
    U.Print("diagnostic dumps (English only, for bug reports):")
    local d
    for d = 1, table.getn(DIAGNOSTIC_HELP) do U.Print(DIAGNOSTIC_HELP[d]) end
    return
  end

  U.Print(U.L("CMD_HEADER", U.version))
  U.Print(U.L("CMD_SETTINGS"))
  U.Print(U.L("CMD_UNLOCK"))
  U.Print(U.L("CMD_LOCK"))
  U.Print(U.L("CMD_RESET"))
  U.Print(U.L("CMD_BIND"))
  U.Print(U.L("CMD_CHECK"))
  U.Print(U.L("CMD_THEME"))
  U.Print(U.L("CMD_LANGUAGE"))
  U.Print(U.L("CMD_PROFILE"))
  U.Print(U.L("CMD_DEBUG"))
  U.Print(U.L("CMD_DIAGNOSTICS"))
end

-- Unit API readout.
--
-- knowledge.json / unitframes.core_unit_api_contract_partial is INCONCLUSIVE:
-- no unit API return contract is verified on this client. This prints what the
-- calls actually returned for each frame's unit, which is the raw material for
-- closing that record rather than another assumption about it.
local function ShowUnitFrameCheck()
  if type(U.UnitFrameReport) ~= "function" then return end

  U.Print("unit frames:")
  U.Print("  stock frames suppressed: " .. tostring(U.SuppressedFrameCount()))

  local report, i = U.UnitFrameReport(), nil
  for i = 1, table.getn(report) do
    local line = report[i]
    if not line.exists then
      U.Print("  " .. line.id .. " (" .. line.unit .. "): no unit, shown " ..
              tostring(line.shown))
    else
      U.Print("  " .. line.id .. " (" .. line.unit .. "): " ..
              tostring(line.name) .. ", shown " .. tostring(line.shown))
      U.Print("    hp " .. tostring(line.health) .. "/" ..
              tostring(line.healthMax) ..
              "  power " .. tostring(line.power) .. "/" ..
              tostring(line.powerMax) ..
              " type " .. tostring(line.powerType))
      U.Print("    class " .. tostring(line.class) ..
              ", reaction " .. tostring(line.reaction) ..
              ", classification " .. tostring(line.classification))
    end

    -- Bar state, printed for every frame including empty ones: a bar that draws
    -- wrong with no unit is a different failure from one that draws wrong with
    -- a unit, and both were visible in the first in-game screenshot.
    U.Print("    bar " .. tostring(line.barWidth) .. "x" ..
            tostring(line.barHeight) ..
            "  value " .. tostring(line.barValue) ..
            " of " .. tostring(line.barMin) .. ".." .. tostring(line.barMax))
    U.Print("    fill " .. tostring(line.fillWidth) .. "x" ..
            tostring(line.fillHeight) ..
            ", shown " .. tostring(line.fillShown) ..
            ", tint " .. tostring(line.fillColor))
  end

  -- knowledge.json / castbar.player_events_partial: SPELLCAST_START's argument
  -- shape was only ever captured once. This readout is how a second cast (of a
  -- different spell, or interrupted, or channelled) turns into more evidence
  -- instead of another assumption.
  if type(U.CastbarReport) == "function" then
    local cb = U.CastbarReport()
    if cb and cb.native then
      -- Native-chrome theme: the client's own CastingBarFrame is in use and
      -- this module built nothing, so there is no unrealUI state to read.
      U.Print("castbar: native client bar (theme " ..
              tostring(U.GetActiveThemeStyle()) .. ")")
    elseif cb then
      U.Print("castbar: casting " .. tostring(cb.casting) ..
              ", shown " .. tostring(cb.shown))
      if cb.casting then
        U.Print("  duration " .. tostring(cb.duration) ..
                "s, remaining " .. tostring(cb.remaining))
      end
      -- The two WORKING_SOURCE gaps in modules/castbar.lua's header: whether
      -- the spellbook lookup resolved a real icon for the last cast, and
      -- whether this client emitted SPELLCAST_DELAYED for pushback at all.
      U.Print("  icon " .. tostring(cb.iconSource) ..
              ", delays " .. tostring(cb.delays) ..
              " (+" .. string.format("%.2f", tonumber(cb.delaySeconds) or 0) ..
              "s)")
    end
  end

  -- Druids only. Reading mana while shifted has no verified source on this
  -- client (see modules/unitframes.lua's druid section), so this prints the
  -- raw UnitMana/UnitManaMax returns taken in form -- run it in bear or cat
  -- form and the gap is either closed or confirmed.
  if type(U.DruidManaReport) == "function" then
    local dm = U.DruidManaReport()
    if dm then
      U.Print("druid mana: source " .. tostring(dm.source) ..
              ", power type " .. tostring(dm.powerType) ..
              ", shifted " .. tostring(dm.shifted) ..
              ", shown " .. tostring(dm.shown))
      U.Print("  mana " .. tostring(dm.mana) .. "/" .. tostring(dm.manaMax) ..
              "  raw " .. tostring(dm.returns))
    end
  end

  -- Warriors and Rogues only. modules/stancebar.lua never creates its bar or
  -- mover for any other class, so supported false with created false is the
  -- expected line for everyone else. "classic" reports whether the buttons
  -- took the client's own action-button faces, which only Classic WoW does.
  if type(U.StanceBarReport) == "function" then
    local sb = U.StanceBarReport()
    if sb then
      U.Print("stance bar: class " .. tostring(sb.class) ..
              ", supported " .. tostring(sb.supported) ..
              ", classic " .. tostring(sb.classic) ..
              ", created " .. tostring(sb.created) ..
              ", shown " .. tostring(sb.shown) ..
              ", forms " .. tostring(sb.slotCount) ..
              ", cd text " .. tostring(sb.cooldownText) ..
              ", cd sweep " .. tostring(sb.cooldownSweep))
    end
  end

  -- The pet bar is the client's own frame; unrealUI only places it. "placed"
  -- false with "driving" false is the untouched-interface state, and means the
  -- bar is sitting wherever the client anchored it.
  if type(U.PetBarReport) == "function" then
    local pb = U.PetBarReport()
    if pb then
      U.Print("pet bar: native " .. tostring(pb.native) ..
              ", has bar " .. tostring(pb.hasPetBar) ..
              ", placed " .. tostring(pb.placed) ..
              ", driving " .. tostring(pb.driving) ..
              ", native anchor " .. tostring(pb.nativeAnchorCaptured))
    end
  end
end

-- Nameplate readout.
--
-- query_compat.py has no record at all for nameplates on this client, so
-- modules/nameplates.lua discovers the plate's structure at runtime instead of
-- assuming Vanilla's. The full readout (detector, reject reasons, min/max
-- WorldFrame child count, one sample plate) is long enough to flood the chat
-- frame past what is copyable, so it is written to UnrealUIDiagDB.nameplates
-- instead -- readable straight out of the SavedVariables file after a reload
-- and only
-- a one-line summary prints in chat.
local function ShowNameplateCheck()
  if type(U.NameplateReport) ~= "function" then return end

  local report = U.NameplateReport()
  SaveDiagnostic("nameplates", report)

  local changed = report.minChildren ~= report.maxChildren
  U.Print("nameplates: detector " .. tostring(report.detector) ..
          ", plates " .. tostring(report.plates) .. "/" ..
          tostring(report.worldChildren) ..
          ", children " .. tostring(report.minChildren) .. ".." ..
          tostring(report.maxChildren) ..
          (changed and "" or " |cffff5555(never changed)|r"))
  U.Print("  saved to UnrealUIDiagDB.nameplates - |cffffff00/reload|r then " ..
          "open " .. U.SavedVariablesHint() .. " to read it")
end

-- Raw WorldFrame child dump, one line per child.
--
-- Nameplate detection is the one part of unrealUI with no compact-DB evidence
-- behind it at all, and the first run adopted none of this client's 28
-- WorldFrame children. Rather than print one line per child (28+ lines, past
-- what can be copied out of chat), the full per-child breakdown is written to
-- UnrealUIDiagDB.nameplateDump and only a count prints in chat.
local function ShowNameplateDump()
  if type(U.NameplateDump) ~= "function" then
    U.Print("nameplate module is not loaded")
    return
  end

  local dump = U.NameplateDump()
  local total = table.getn(dump)
  SaveDiagnostic("nameplateDump", dump)

  U.Print("WorldFrame children: " .. tostring(total) ..
          " - saved to UnrealUIDiagDB.nameplateDump")
  U.Print("  |cffffff00/reload|r then open " ..
          U.SavedVariablesHint() .. " to read it")
end

-- Elite/classification icon test.
--
-- Two unknowns, both exercised without leaving the spot you are standing on:
-- whether UnitClassification returns Vanilla's tokens on this client, and
-- whether the icon's texture path renders at all -- knowledge.json /
-- textures.separate_coin_paths_not_rendered is a confirmed case of stock paths
-- that do not. The override forces the classification every unit frame reads,
-- so any mob stands in for an elite.
local ELITE_CYCLE = { "elite", "rareelite", "worldboss", "rare", "normal", "off" }

local ELITE_USAGE = "usage: |cffffff00/uui elite|r " ..
  "[elite|rareelite|worldboss|rare|normal|off] | tex <path> | " ..
  "size <w> <h> | coord <l> <r> <t> <b> | status"

-- Split() only cuts the first token off; this walks the rest of the line.
local function Numbers(text)
  local values, rest, count = {}, Trim(text or ""), 0

  -- Indexed rather than table.insert'd: a non-numeric token has to leave a hole
  -- in place instead of shifting the values after it into the wrong argument.
  while rest ~= "" do
    local token
    token, rest = Split(rest)
    count = count + 1
    values[count] = tonumber(token)
  end

  return values
end

local function ShowEliteReport()
  local report = U.EliteIconReport()

  U.Print("elite icon: override " .. tostring(report.override) ..
          ", size " .. tostring(report.width) .. "x" .. tostring(report.height) ..
          (report.coords and (", coords " .. report.coords) or ""))
  U.Print("  texture " .. tostring(report.texture))

  local i
  for i = 1, table.getn(report.units) do
    local u = report.units[i]
    U.Print("  " .. u.id .. " (" .. u.unit .. "): api " ..
            tostring(u.classification) .. ", drawn as " ..
            tostring(u.effective) .. ", icon shown " .. tostring(u.shown) ..
            (u.tint and (", tint " .. u.tint) or ""))
    if u.path and u.path ~= report.texture then
      U.Print("    readback " .. tostring(u.path))
    end
  end

  if table.getn(report.units) == 0 then
    U.Print("  no unit on any frame - target something first")
  end
end

local function NextOverride(current)
  local total = table.getn(ELITE_CYCLE)
  local i
  for i = 1, total do
    if ELITE_CYCLE[i] == current then
      if i >= total then return ELITE_CYCLE[1] end
      return ELITE_CYCLE[i + 1]
    end
  end
  return ELITE_CYCLE[1]
end

local function HandleElite(rest)
  if type(U.SetUnitClassificationOverride) ~= "function" then
    U.Print("unit frames are not loaded")
    return
  end

  local sub, arg = Split(Trim(rest or ""))

  if sub == "status" then
    ShowEliteReport()
    return
  end

  -- The path keeps its original case: Split() only lowercases the token it
  -- cuts off, never the remainder.
  if sub == "tex" or sub == "texture" then
    U.Print("elite icon texture: " .. tostring(U.SetEliteIconTexture(arg)))
    U.Print("  no icon at all means the path does not render here - try " ..
            "another, |cffffff00/uui elite tex default|r restores the built-in")
    return
  end

  if sub == "size" then
    local values = Numbers(arg)
    local width, height = U.SetEliteIconSize(values[1], values[2])
    U.Print("elite icon size: " .. tostring(width) .. "x" .. tostring(height))
    return
  end

  if sub == "coord" or sub == "coords" then
    local values = Numbers(arg)
    local coords = U.SetEliteIconCoords(values[1], values[2], values[3],
                                        values[4])
    if coords then
      U.Print("elite icon crop: " .. table.concat(coords, " "))
    else
      U.Print("elite icon crop cleared - drawing the whole texture")
    end
    return
  end

  local value = sub
  if value == "" then value = NextOverride(U.EliteIconReport().override) end

  local ok, override = U.SetUnitClassificationOverride(value)
  if not ok then
    U.Print("unknown classification: " .. tostring(sub))
    U.Print(ELITE_USAGE)
    return
  end

  U.Print("classification override: |cffffff00" .. (override or "off") ..
          "|r - target any mob; |cffffff00/uui elite|r again for the next one")
  ShowEliteReport()
end

-- Reports what this client actually did with the calls unrealUI depends on.
-- The point is to turn the foundation's compatibility assumptions into
-- observed results that can be fed back into the evidence workflow.
local function ShowSelfCheck()
  local report = U.RunSelfCheck()

  U.Print("self-check (v" .. tostring(report.version) .. ")")
  U.Print("  font:        " .. tostring(report.font))
  U.Print("  handlers:    " .. tostring(report.handlerShape))
  U.Print("  OnUpdate:    " .. tostring(report.ticks) .. " ticks")
  U.Print("  UIParent:    " .. tostring(U.Round(report.uiWidth)) .. " x " ..
          tostring(U.Round(report.uiHeight)))
  U.Print("  GetScreenW:  " .. tostring(report.screenWidth) ..
          "  (pixel scale " .. tostring(report.pixelScale) .. ")")
  U.Print("  GetPoint rel type: " .. tostring(report.rawRelativeType) ..
          ", raw y " .. tostring(report.rawY) ..
          " -> normalised y " .. tostring(report.normY))

  if report.anchorRoundTrip then
    U.Print("  anchor round-trip: |cff55ff55ok|r (x/y survive capture)")
  else
    U.Print("  anchor round-trip: |cffff5555FAILED|r - mover persistence " ..
            "would drift; report this output")
  end

  local hookType, hooked = U.PostHookReport()
  U.Print("  hooksecurefunc: " .. tostring(hookType) ..
          "  post-hooked: " .. (table.getn(hooked) > 0
            and table.concat(hooked, ", ") or "|cffff5555none|r"))

  U.Print("  movers registered: " .. tostring(U.MoverCount()))

  -- Per-mover drag state. Frame dragging has no compact-DB record on this
  -- client, so this is the readout that turns "it does not move" into something
  -- specific enough to act on.
  local movers, i = U.MoverReport(), nil
  for i = 1, table.getn(movers) do
    local m = movers[i]
    U.Print("  mover " .. m.id .. ": " .. tostring(m.handleType or "no handle") ..
            ", movable " .. tostring(m.movable) ..
            ", mouse " .. tostring(m.mouse))
    U.Print("    enter " .. tostring(m.enters) ..
            " / dragStart " .. tostring(m.dragStarts) ..
            " / dragStop " .. tostring(m.dragStops) ..
            ", saved " .. tostring(m.saved))
    U.Print("    at " .. tostring(m.point) ..
            " " .. tostring(m.x) .. "," .. tostring(m.y))
  end

  if type(U.MicroBarReport) == "function" then
    local micro = U.MicroBarReport()
    U.Print("  micro bar: enabled " .. tostring(micro.enabled) ..
            ", found " .. table.getn(micro.found) .. "/" ..
            (table.getn(micro.found) + table.getn(micro.missing)))
    if table.getn(micro.missing) > 0 then
      U.Print("    missing: " .. table.concat(micro.missing, ", "))
    end
  end

  -- Quick binding rests entirely on calls with no compact runtime record
  -- (SetBinding, SaveBindings, GetBindingAction, GetCurrentBindingSet,
  -- GetMouseFocus). Printing which of them this client actually exposes is the
  -- raw material for closing that gap instead of assuming Vanilla shapes.
  if type(U.QuickBindReport) == "function" then
    local qb = U.QuickBindReport()
    U.Print("  quick bind: active " .. tostring(qb.active) ..
            ", slots " .. tostring(qb.slots) ..
            ", pending changes " .. tostring(qb.changes))
    U.Print("    SetBinding " .. tostring(qb.setBinding) ..
            ", SaveBindings " .. tostring(qb.saveBindings) ..
            ", GetBindingAction " .. tostring(qb.bindingAction))
    U.Print("    GetCurrentBindingSet " .. tostring(qb.bindingSet) ..
            ", GetMouseFocus " .. tostring(qb.mouseFocus))
    U.Print("    bars 6-10 key route: declared commands " ..
            tostring(qb.declaredBindings) ..
            ", SetOverrideBindingClick " .. tostring(qb.overrideBindings))
    U.Print("    menu keys held " .. tostring(qb.menuKeysHeld) ..
            ", menu guard " .. tostring(qb.menuGuard) ..
            ", slot keys held " .. tostring(qb.slotKeysHeld))
  end

  if type(U.ChatResizeReport) == "function" then
    local chat = U.ChatResizeReport()
    U.Print("  chat resize: frame " .. tostring(chat.frame) ..
            ", grip " .. tostring(chat.grip) ..
            ", locked " .. tostring(chat.locked) ..
            ", shown " .. tostring(chat.shown) ..
            ", saved " .. tostring(chat.saved) ..
            ", size " .. tostring(chat.width) .. "x" ..
            tostring(chat.height))
    U.Print("    position " .. tostring(chat.left) .. "," ..
            tostring(chat.bottom) .. "  saved " ..
            tostring(chat.savedLeft) .. "," ..
            tostring(chat.savedBottom))
  end

  -- Quest header collapsing has no compact-DB record and the stock row click
  -- does not do it on this client, so the first header click is the only thing
  -- that says which entry point actually exists. Read this after clicking one.
  if type(U.QuestLogCollapseReport) == "function" then
    local q = U.QuestLogCollapseReport()
    U.Print("  quest collapse: CollapseQuestHeader " .. tostring(q.collapse) ..
            ", ExpandQuestHeader " .. tostring(q.expand) ..
            ", row OnClick " .. tostring(q.nativeClick))
  end

  if type(U.QuestLogTrackReport) == "function" then
    local t = U.QuestLogTrackReport()
    U.Print("  quest tracking: source " .. tostring(t.source) ..
            ", rows marked " .. tostring(t.marked))
  end

  ShowUnitFrameCheck()
  ShowNameplateCheck()
end

-- Foundation smoke test.
--
-- Creates one styled, registered, movable panel so the shared mover system can
-- be exercised end to end -- drag, lock, /reload, restore -- before any real
-- module depends on it. This matters because the anchor behaviour it relies on
-- (knowledge.json / frames.getpoint_relative_name_y_inverted) inverts Y, and a
-- persistence bug found here is far cheaper than one found across six modules.
--
-- Remove this handler once real modules register movers.
local testPanel

local function ShowMoverTest()
  if not testPanel then
    testPanel = U.CreatePanel(UIParent, {
      name = "UnrealUIMoverTest",
      width = 170,
      height = 40,
    })

    -- No label of its own: the mover handle covers this panel and centres its
    -- own label, and two centred fontstrings just overprint each other.
    U.RegisterMover("debug.movertest", testPanel, {
      label = U.L("MOVER_LABEL_MOVER_TEST"),
      default = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    })
  end

  testPanel:Show()
  U.UnlockUI()
  U.Print("Drag the blue panel with the left mouse button.")
  U.Print("Then |cffffff00/uui check|r for measured drag state, " ..
          "|cffffff00/uui lock|r, |cffffff00/reload|r, and " ..
          "|cffffff00/uui movertest|r again to confirm it comes back in place.")
end

-- Resistance-block structure dump.
--
-- The Character sheet's resistance readouts are the one part of that skin with
-- no compact-DB evidence and no working Vanilla assumption behind them: this
-- client draws its own resistance icons and its own hover tooltip text
-- ("Increases the ability to resist frost-based attacks...", USER_CONFIRMED_
-- INGAME screenshot), neither of which matches Vanilla's paper doll. Skinning
-- them by the Vanilla names (MagicResFrame1-5) changed nothing on screen in
-- either direction, which is exactly what a wrong frame name looks like.
--
-- Rather than keep guessing names, this writes what is actually there. It is a
-- read-only walk: nothing is hidden, re-anchored or hooked.
local resDump = {}

resDump.CANDIDATES = {
  "CharacterResistanceFrame", "PaperDollFrame", "CharacterAttributesFrame",
  "MagicResFrame1", "MagicResFrame2", "MagicResFrame3", "MagicResFrame4",
  "MagicResFrame5",
  "MagicResText1", "MagicResText2", "MagicResText3", "MagicResText4",
  "MagicResText5",
  "PlayerResistanceFrame1", "PlayerResistanceFrame2", "PlayerResistanceFrame3",
  "PlayerResistanceFrame4", "PlayerResistanceFrame5",
  "ResistanceFrame1", "ResistanceFrame2", "ResistanceFrame3",
  "ResistanceFrame4", "ResistanceFrame5",
}

function resDump.Try(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if not ok then return nil end
  return value
end

function resDump.Describe(object)
  if not object then return "nil" end

  local line = tostring(resDump.Try(object, "GetName") or "<unnamed>") ..
    " [" .. tostring(resDump.Try(object, "GetObjectType") or "?") .. "]"

  local id = resDump.Try(object, "GetID")
  if id then line = line .. " id=" .. tostring(id) end

  local width = resDump.Try(object, "GetWidth")
  local height = resDump.Try(object, "GetHeight")
  if width or height then
    line = line .. " size=" .. tostring(width) .. "x" .. tostring(height)
  end

  local layer = resDump.Try(object, "GetDrawLayer")
  if layer then line = line .. " layer=" .. tostring(layer) end

  local texture = resDump.Try(object, "GetTexture")
  if texture then line = line .. " tex=" .. tostring(texture) end

  local text = resDump.Try(object, "GetText")
  if text then line = line .. " text=\"" .. tostring(text) .. "\"" end

  if type(object.IsMouseEnabled) == "function" then
    line = line .. " mouse=" .. tostring(resDump.Try(object, "IsMouseEnabled"))
  end
  if type(object.GetScript) == "function" then
    local ok, handler = pcall(object.GetScript, object, "OnEnter")
    line = line .. " onEnter=" .. tostring(ok and handler ~= nil)
  end

  return line
end

-- Depth-limited so an unexpected parent chain cannot walk the whole UI.
function resDump.Walk(object, into, depth, prefix)
  local i
  if type(object.GetRegions) == "function" then
    local ok, regions = pcall(function() return { object:GetRegions() } end)
    if ok then
      for i = 1, table.getn(regions) do
        table.insert(into, prefix .. "region " .. resDump.Describe(regions[i]))
      end
    end
  end

  if depth <= 0 or type(object.GetChildren) ~= "function" then return end

  local ok, children = pcall(function() return { object:GetChildren() } end)
  if not ok then return end
  for i = 1, table.getn(children) do
    table.insert(into, prefix .. "child " .. resDump.Describe(children[i]))
    resDump.Walk(children[i], into, depth - 1, prefix .. "  ")
  end
end

-- Direct OnEnter exercise.
--
-- The structure dump alone cannot say why the resistance tooltip does not
-- appear: "no handler", "handler errors out", "handler runs but never calls
-- Show", and "tooltip shown somewhere invisible" all look identical while
-- hovering. unrealUI also suppresses Lua errors by default, so a failing
-- native handler stays silent.
--
-- This calls the handler itself and reports the error text and the resulting
-- GameTooltip state, which separates all four. `this` is set the way the
-- client's own C caller would for a Vanilla-shaped XML handler, then restored.
function resDump.FireOnEnter(res, into)
  local name = tostring(resDump.Try(res, "GetName"))
  local handler = nil
  if type(res.GetScript) == "function" then
    local ok, value = pcall(res.GetScript, res, "OnEnter")
    if ok then handler = value end
  end

  table.insert(into, name .. " OnEnter=" .. type(handler) ..
               " mouse=" .. tostring(resDump.Try(res, "IsMouseEnabled")))
  if type(handler) ~= "function" then return end

  local tooltip = U.G("GameTooltip")
  if tooltip then pcall(tooltip.Hide, tooltip) end

  local previousThis = this
  this = res
  resDump.firing = true
  local ok, err = pcall(handler, res)
  resDump.firing = false
  this = previousThis

  table.insert(into, "  called: ok=" .. tostring(ok) ..
               (ok and "" or " err=" .. tostring(err)))

  if not tooltip then
    table.insert(into, "  GameTooltip missing")
    return
  end

  table.insert(into, "  tooltip shown=" ..
               tostring(resDump.Try(tooltip, "IsShown")) ..
               " visible=" .. tostring(resDump.Try(tooltip, "IsVisible")) ..
               " alpha=" .. tostring(resDump.Try(tooltip, "GetAlpha")) ..
               " lines=" .. tostring(resDump.Try(tooltip, "NumLines")))

  local owner = nil
  if type(tooltip.GetOwner) == "function" then
    local ownerOk, value = pcall(tooltip.GetOwner, tooltip)
    if ownerOk and value then owner = resDump.Try(value, "GetName") end
  end
  table.insert(into, "  owner=" .. tostring(owner) ..
               " point=" .. tostring(resDump.Try(tooltip, "GetPoint")))

  local line
  for line = 1, 4 do
    local text = resDump.Try(U.G("GameTooltipTextLeft" .. line), "GetText")
    if text then table.insert(into, "  line" .. line .. "=\"" .. text .. "\"") end
  end

  pcall(tooltip.Hide, tooltip)
end

local function ShowResistanceDump()
  local lines, i = {}, nil

  for i = 1, table.getn(resDump.CANDIDATES) do
    local name = resDump.CANDIDATES[i]
    local object = U.G(name)
    table.insert(lines, "global " .. name .. " = " ..
                 (object and resDump.Describe(object) or "nil"))
  end

  local root = U.G("CharacterResistanceFrame") or U.G("PaperDollFrame")
  if root then
    table.insert(lines, "--- walk from " ..
                 tostring(resDump.Try(root, "GetName")) .. " ---")
    resDump.Walk(root, lines, 2, "")
  else
    table.insert(lines, "--- no CharacterResistanceFrame or PaperDollFrame ---")
  end

  -- Input priority context: strata first, then level. Printed together so the
  -- resistance column and everything overlapping it can be compared at a glance.
  table.insert(lines, "--- input priority ---")
  local overlap = {
    "CharacterResistanceFrame", "MagicResFrame1", "CharacterModelFrame",
    "UnrealUICharacterModelRotateCatcher", "UnrealUICharacterPanel",
    "CharacterHandsSlot", "PaperDollFrame", "CharacterFrame",
  }
  for i = 1, table.getn(overlap) do
    local object = U.G(overlap[i])
    table.insert(lines, overlap[i] .. " = " ..
      (object and ("strata=" .. tostring(resDump.Try(object, "GetFrameStrata")) ..
        " level=" .. tostring(resDump.Try(object, "GetFrameLevel")) ..
        " mouse=" .. tostring(resDump.Try(object, "IsMouseEnabled")) ..
        " x=" .. tostring(resDump.Try(object, "GetLeft")) ..
        " y=" .. tostring(resDump.Try(object, "GetBottom")) ..
        " w=" .. tostring(resDump.Try(object, "GetWidth")) ..
        " h=" .. tostring(resDump.Try(object, "GetHeight"))) or "nil"))
  end

  table.insert(lines, "--- OnEnter exercise ---")
  for i = 1, 5 do
    local res = U.G("MagicResFrame" .. i)
    if res then resDump.FireOnEnter(res, lines) end
  end

  -- Same exercise on an equipment slot, whose tooltip is confirmed working in
  -- game. If the slot behaves and the resistance frame does not, the
  -- difference is in the frame; if neither does, it is in how this dump calls
  -- them, not in the resistance skin.
  local slot = U.G("CharacterHeadSlot")
  if slot then
    table.insert(lines, "--- control: CharacterHeadSlot ---")
    resDump.FireOnEnter(slot, lines)
  end

  table.insert(lines, "--- event trace (/uui res trace) ---")
  for i = 1, table.getn(resDump.events) do
    table.insert(lines, resDump.events[i])
  end

  SaveDiagnostic("resistances", lines)
  U.Print("resistance dump: " .. tostring(table.getn(lines)) ..
          " lines saved to UnrealUIDiagDB.resistances")
  U.Print("  open the Character sheet first, then |cffffff00/reload|r and open " ..
          U.SavedVariablesHint() .. " to read it")
end

-- Who actually receives the cursor.
--
-- Raising CharacterResistanceFrame above the model rotate catcher did not bring
-- the tooltip back, and the handler is already proven to work when called
-- directly, so the remaining question is only which frame the client hands the
-- mouse to over that column. GetMouseFocus answers it, but it has to be read
-- *while* hovering -- which is why this samples on a ticker instead of
-- reporting once at command time.
local SLOT_NAMES = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "ChestSlot", "WristSlot",
  "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
  "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

resDump.HOVER_ID = "commands.res-hover"
resDump.HOVER_SECONDS = 8

function resDump.Chain(frame)
  local names, guard = {}, 0
  while frame and guard < 6 do
    table.insert(names, tostring(resDump.Try(frame, "GetName") or "<unnamed>") ..
                 "(L" .. tostring(resDump.Try(frame, "GetFrameLevel")) ..
                 "/" .. tostring(resDump.Try(frame, "GetFrameStrata")) .. ")")
    frame = resDump.Try(frame, "GetParent")
    guard = guard + 1
  end
  return table.concat(names, " < ")
end

-- Event trace on the frames themselves.
--
-- GetMouseFocus returned <none> for every sample of an 8s hover watch, so it
-- reports nothing usable on this client and cannot say who receives the cursor.
-- Hooking the frames answers the same question directly: if OnEnter never fires
-- on a resistance frame but does on the equipment slot beside it, the cursor is
-- being intercepted; if it fires and the tooltip is shown here but invisible in
-- game, something hides it afterwards -- which is why the tooltip state is
-- sampled both immediately and one tick later.
resDump.events = {}

-- FireOnEnter invokes the very handlers this traces, so a /uui res run would
-- otherwise fill the trace with its own synthetic ENTERs and read exactly like
-- a successful hover. Anything recorded while the dump is driving is dropped.
resDump.firing = false

function resDump.Note(text)
  if resDump.firing then return end
  if table.getn(resDump.events) < 60 then
    table.insert(resDump.events, text)
    U.Print("|cff888888trace|r " .. text)
    -- Written on every event so the trace survives a plain /reload with no
    -- second command to remember, and never has to be copied out of chat.
    SaveDiagnostic("resistanceTrace", resDump.events)
  end
end

-- Geometry, not just state: the trace proved the tooltip is shown and populated
-- on a real hover while nothing appears on screen, so what is left to measure is
-- where it actually is and what draws over it.
function resDump.TooltipState(tag, owner)
  local tooltip = U.G("GameTooltip")
  if not tooltip then return tag .. " GameTooltip=nil" end
  return tag .. " " .. tostring(owner) ..
         " shown=" .. tostring(resDump.Try(tooltip, "IsShown")) ..
         " lines=" .. tostring(resDump.Try(tooltip, "NumLines")) ..
         " x=" .. tostring(resDump.Try(tooltip, "GetLeft")) ..
         " y=" .. tostring(resDump.Try(tooltip, "GetBottom")) ..
         " w=" .. tostring(resDump.Try(tooltip, "GetWidth")) ..
         " h=" .. tostring(resDump.Try(tooltip, "GetHeight")) ..
         " strata=" .. tostring(resDump.Try(tooltip, "GetFrameStrata")) ..
         " level=" .. tostring(resDump.Try(tooltip, "GetFrameLevel")) ..
         " alpha=" .. tostring(resDump.Try(tooltip, "GetAlpha"))
end

function resDump.Trace(frame)
  local name = tostring(resDump.Try(frame, "GetName"))

  U.PostHookScript(frame, "OnEnter", function()
    resDump.Note(resDump.TooltipState("ENTER " .. name, name))
    U.DeferOnce("commands.res-trace", function()
      resDump.Note(resDump.TooltipState("  +1 tick " .. name, name))
    end)
  end)
  U.PostHookScript(frame, "OnLeave", function()
    resDump.Note("LEAVE " .. name)
  end)
end

local function StartEventTrace()
  local i
  for i = 1, 5 do
    local res = U.G("MagicResFrame" .. i)
    if res then resDump.Trace(res) end
  end
  -- Every gear slot, not just the head: the working tooltip is the reference
  -- this comparison depends on, and a trace armed on one slot reads as "no
  -- events" the moment a different piece of armour is hovered.
  for i = 1, table.getn(SLOT_NAMES) do
    resDump.Trace(U.G("Character" .. SLOT_NAMES[i]))
  end

  resDump.events = {}
  U.Print("trace armed - hover the resistance icons, then a gear slot, " ..
          "then |cffffff00/uui res|r and |cffffff00/reload|r")
end

local function StartHoverWatch()
  local getFocus = U.G("GetMouseFocus")
  if type(getFocus) ~= "function" then
    U.Print("GetMouseFocus unavailable on this client")
    return
  end

  local samples, seen, elapsed = {}, {}, 0

  U.RegisterUpdate(resDump.HOVER_ID, 0.1, function(step)
    elapsed = elapsed + (tonumber(step) or 0.1)

    local ok, focus = pcall(getFocus)
    local line = (ok and focus) and resDump.Chain(focus) or "<none>"
    if not seen[line] then
      seen[line] = true
      table.insert(samples, string.format("%.1fs %s", elapsed, line))
    end

    if elapsed >= resDump.HOVER_SECONDS then
      U.UnregisterUpdate(resDump.HOVER_ID)
      SaveDiagnostic("resistanceHover", samples)
      U.Print("hover watch done: " .. tostring(table.getn(samples)) ..
              " distinct targets saved to UnrealUIDiagDB.resistanceHover")
      U.Print("  |cffffff00/reload|r then read " .. U.SavedVariablesHint())
    end
  end)

  U.Print("hover watch armed for " .. resDump.HOVER_SECONDS ..
          "s - move the cursor slowly over the resistance icons NOW")
end

local handlers = {}

handlers["unlock"] = function() U.UnlockUI() end
handlers["lock"]   = function() U.LockUI() end
handlers["toggle"] = function() U.ToggleUI() end
handlers["reset"]  = function() U.ResetPositions() end
handlers["check"]  = function() ShowSelfCheck() end
handlers["help"]   = function(rest) ShowHelp(rest) end
handlers["movertest"] = function() ShowMoverTest() end
handlers["np"] = function() ShowNameplateDump() end
-- Live readout, printed straight to chat: an aura timer that does not appear
-- has exactly three possible causes and modules/auras.lua's dump names the one
-- responsible, per row and per index, without a reload or a probe run.
handlers["aura"] = function()
  if type(U.AuraDebugDump) ~= "function" then
    U.Print("aura dump unavailable - modules/auras.lua did not load")
    return
  end
  U.AuraDebugDump()
end
-- Whether the hovered zone name reaches unrealUI at all. The command being
-- unavailable is itself the first answer: it means modules/worldmap.lua did not
-- load, which no amount of reading the map code would have shown.
handlers["map"] = function()
  if type(U.WorldMapDebugDump) ~= "function" then
    U.Print("map dump unavailable - modules/worldmap.lua did not load")
    return
  end
  U.WorldMapDebugDump()
end
-- Which stage of the tooltip price readout stopped, for the item hovered last.
-- The command being unavailable is the first answer by itself: modules/
-- itemprice.lua did not load.
handlers["price"] = function()
  if type(U.PriceDebugDump) ~= "function" then
    U.Print("price dump unavailable - modules/itemprice.lua did not load")
    return
  end
  U.PriceDebugDump()
end
handlers["res"] = function(rest)
  local mode = Trim(rest or "")
  if mode == "hover" then
    StartHoverWatch()
  elseif mode == "trace" then
    StartEventTrace()
  else
    ShowResistanceDump()
  end
end
handlers["elite"] = function(rest) HandleElite(rest) end
handlers["cb"] = function()
  if type(U.CastbarNativeDump) ~= "function" then
    U.Print("castbar dump unavailable - modules/castbar.lua did not load")
    return
  end
  U.CastbarNativeDump()
end
handlers["abcd"] = function()
  if type(U.ActionBarCooldownDump) ~= "function" then
    U.Print("cooldown dump unavailable - modules/actionbar.lua did not load")
    return
  end
  U.ActionBarCooldownDump()
end
handlers["abhl"] = function(rest)
  if type(U.ActionBarHighlightDump) ~= "function" then
    U.Print("highlight dump unavailable - modules/actionbar.lua did not load")
    return
  end
  local first, remainder = Split(rest)
  if first == "" then
    U.ActionBarHighlightDump()
    return
  end
  local alpha = tonumber(first)
  if not alpha then
    U.Print("  |cffffff00/uui abhl|r - dump, or " ..
            "|cffffff00/uui abhl <alpha> [hover] [rest]|r")
    return
  end
  local second, third = Split(remainder)
  U.ActionBarHighlightTune(alpha, tonumber(second), tonumber(third))
end

-- Binding-table readout.
--
-- unrealUI declares its own commands for bars 6-10 in Bindings.xml
-- (UnrealPfUI's working path on this client). A first in-game check reported
-- them as not registered, and the detection itself is a suspect: GetBinding's
-- return shape on this client has no compact record, so "not found" and "found
-- but shaped differently" look the same from modules/actionbar.lua. This prints
-- the raw enumeration so the two can be told apart.
local BINDING_SCAN_MARKERS = {
  -- unrealUI's own declarations (Bindings.xml).
  "UNREALUIBAR",
  -- UnrealPfUI's, for the same case on the same client. If pfUI is enabled and
  -- its commands are missing too, the client ignores addon Bindings.xml
  -- entirely rather than rejecting unrealUI's file in particular.
  "PFPAGING",
  "PFSTANCE",
}

local function AddOnLoaded(name)
  local fn = U.G("IsAddOnLoaded")
  if type(fn) ~= "function" then return "?" end
  local ok, loaded = pcall(fn, name)
  if not ok then return "?" end
  return loaded and "yes" or "no"
end

local function ShowBindingScan()
  local numBindings = U.G("GetNumBindings")
  local getBinding = U.G("GetBinding")

  U.Print("binding scan:")
  U.Print("  addons loaded: unrealUI " .. AddOnLoaded("unrealUI") ..
          ", UnrealPfUI " .. AddOnLoaded("UnrealPfUI"))
  U.Print("  GetNumBindings " .. type(numBindings) ..
          ", GetBinding " .. type(getBinding))

  if type(numBindings) ~= "function" or type(getBinding) ~= "function" then
    U.Print("  |cffff5555the client exposes no binding enumeration|r")
  else
    local ok, count = pcall(numBindings)
    count = ok and tonumber(count) or 0
    U.Print("  bindings reported: " .. tostring(count))

    local hits, m = {}, nil
    for m = 1, table.getn(BINDING_SCAN_MARKERS) do
      hits[BINDING_SCAN_MARKERS[m]] = 0
    end

    local i, last = nil, nil
    for i = 1, count do
      local got, a = pcall(getBinding, i)
      if got and type(a) == "string" then
        last = a
        for m = 1, table.getn(BINDING_SCAN_MARKERS) do
          local marker = BINDING_SCAN_MARKERS[m]
          if string.find(a, marker, 1, true) then
            hits[marker] = hits[marker] + 1
          end
        end
      end
    end

    for m = 1, table.getn(BINDING_SCAN_MARKERS) do
      local marker = BINDING_SCAN_MARKERS[m]
      local found = hits[marker]
      U.Print("  " .. marker .. ": " ..
              (found > 0 and ("|cff55ff55" .. found .. "|r") or "|cffff55550|r"))
    end

    -- The last entry is where an addon's commands would land: the client
    -- appends them after its own table.
    U.Print("  last command in the table: " .. tostring(last))
  end

  local key1, key2 = nil, nil
  local getKey = U.G("GetBindingKey")
  if type(getKey) == "function" then
    local got
    got, key1, key2 = pcall(getKey, "UNREALUIBAR2BUTTON1")
    if not got then key1, key2 = "error", nil end
  end
  U.Print("  GetBindingKey(UNREALUIBAR2BUTTON1): " .. tostring(key1) ..
          ", " .. tostring(key2))
  U.Print("  UnrealUIActionButton: " .. type(U.G("UnrealUIActionButton")))
end

handlers["menu"] = function()
  if type(U.DumpGameMenu) == "function" then
    U.DumpGameMenu()
  else
    U.Print("the game menu module is not loaded.")
  end
end

handlers["bindscan"] = function() ShowBindingScan() end

-- NPC quest/gossip dialog text readout.
--
-- Reported in game: some strings in the NPC quest window stay non-white even
-- after modules/quest.lua's U.SetStockFont pass, which already fixed the
-- decorative gold book font on the rest. This prints only the strings that came
-- back non-white -- with the name, colour and font the client reports for each
-- -- so the survivors can be named instead of guessed at. The full list goes to
-- UnrealUIDiagDB because a busy quest window has more strings than chat can
-- usefully hold.
local function ShowQuestTextCheck()
  if type(U.QuestTextReport) ~= "function" then
    U.Print("quest module is not loaded")
    return
  end

  local report = U.QuestTextReport()
  SaveDiagnostic("questText", report)

  local total = table.getn(report)
  if total == 0 then
    U.Print("|cffff5555no FontStrings found|r - open the NPC quest window " ..
            "first, then run this again")
    return
  end

  local offenders, i = 0, nil
  for i = 1, total do
    local entry = report[i]
    -- Only shown strings matter visually, and only ones that are not already
    -- near-white. Hidden strings are still written to the saved dump.
    local white = tonumber(entry.r) and entry.r > 0.95
                  and entry.g > 0.95 and entry.b > 0.95
    if entry.shown == "yes" and not white then
      offenders = offenders + 1
      U.Print("  |cffff5555" .. entry.name .. "|r  rgb " .. entry.color ..
              "  size " .. entry.size)
      U.Print("    font " .. entry.font)
      if entry.text ~= "" then U.Print("    text \"" .. entry.text .. "\"") end
    end
  end

  U.Print("quest text: " .. tostring(total) .. " strings, " ..
          (offenders > 0
            and ("|cffff5555" .. offenders .. " not white|r")
            or "|cff55ff55all shown strings white|r"))
  U.Print("  full dump saved to UnrealUIDiagDB.questText")
end

handlers["questtext"] = function() ShowQuestTextCheck() end

-- ---------------------------------------------------------------------------
-- Keyboard capture test
--
-- Everything the quick-binding mode does rests on one unrecorded assumption:
-- that a keyboard-enabled addon frame receives OnKeyDown/OnKeyUp at all on this
-- client. knowledge.json / chat.mousewheel_uses_binding_layer says the binding
-- layer resolves before addon frame scripts here, and Escape was confirmed in
-- game opening the game menu straight through the mode, so the assumption is
-- actively in doubt.
--
-- This measures it instead of arguing about it. Two catchers are shown at once,
-- a Button and a plain Frame, because frames.movable_drag_requires_button_handle
-- established that widget type decides whether *mouse* input arrives here and
-- the same may hold for the keyboard. Each press prints which widget saw it,
-- which script fired, and how the key name arrived.
-- ---------------------------------------------------------------------------
local keyTest

local function StopKeyTest(reason)
  if not keyTest then return end

  U.UnregisterUpdate("commands.keytest")
  keyTest.button:Hide()
  keyTest.frame:Hide()
  if keyTest.label then keyTest.label:Hide() end

  U.Print("key test stopped (" .. reason .. "): " ..
          keyTest.button_down .. " button keydown, " ..
          keyTest.button_up .. " button keyup, " ..
          keyTest.frame_down .. " frame keydown, " ..
          keyTest.frame_up .. " frame keyup")

  if keyTest.total == 0 then
    U.Print("  |cffff5555no key ever reached an addon frame|r - the binding " ..
            "layer owns the keyboard on this client")
  end

  keyTest = nil
end

local function ReportKey(source, script, a, b)
  if not keyTest then return end

  -- scripts.handler_arguments_direct: report which of the three shapes carried
  -- the key name, since that is itself part of the answer.
  local shape, key = "none", nil
  if type(a) == "string" then
    shape, key = "arg1-direct", a
  elseif type(b) == "string" then
    shape, key = "arg2-direct", b
  else
    local legacy = U.G("arg1")
    if type(legacy) == "string" then shape, key = "global-arg1", legacy end
  end

  keyTest.total = keyTest.total + 1
  keyTest[source .. "_" .. script] = keyTest[source .. "_" .. script] + 1

  U.Print("  |cff55ff55" .. source .. " " .. script .. "|r: " ..
          tostring(key) .. "  (" .. shape .. ")")

  if key == "ESCAPE" then StopKeyTest("escape") end
end

local function StartKeyTest()
  if keyTest then
    StopKeyTest("restarted")
    return
  end

  local button = U.G("UnrealUIKeyTestButton")
  local frame = U.G("UnrealUIKeyTestFrame")

  if not button then
    button = CreateFrame("Button", "UnrealUIKeyTestButton", UIParent)
    button:SetWidth(260)
    button:SetHeight(60)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    pcall(button.SetFrameStrata, button, "FULLSCREEN_DIALOG")
    pcall(button.EnableKeyboard, button, true)
    pcall(button.EnableMouse, button, true)
    U.CreateBackdrop(button, {})

    frame = CreateFrame("Frame", "UnrealUIKeyTestFrame", UIParent)
    frame:SetWidth(260)
    frame:SetHeight(20)
    frame:SetPoint("TOP", button, "BOTTOM", 0, -8)
    pcall(frame.SetFrameStrata, frame, "FULLSCREEN_DIALOG")
    pcall(frame.EnableKeyboard, frame, true)

    button:SetScript("OnKeyDown", function(a, b) ReportKey("button", "down", a, b) end)
    button:SetScript("OnKeyUp",   function(a, b) ReportKey("button", "up", a, b) end)
    frame:SetScript("OnKeyDown",  function(a, b) ReportKey("frame", "down", a, b) end)
    frame:SetScript("OnKeyUp",    function(a, b) ReportKey("frame", "up", a, b) end)

    button.uuiLabel = U.CreateLabel(button, {
      size = U.media.fontSize.normal,
      color = U.media.color.accent,
      inherits = "GameFontNormal",
      width = 240,
    })
    if button.uuiLabel then
      button.uuiLabel:SetPoint("CENTER", button, "CENTER", 0, 0)
      button.uuiLabel:SetText("Key test: press keys. Escape or 15s stops it.")
    end
  end

  keyTest = {
    button = button,
    frame = frame,
    label = button.uuiLabel,
    total = 0,
    button_down = 0, button_up = 0,
    frame_down = 0, frame_up = 0,
    elapsed = 0,
  }

  button:Show()
  frame:Show()
  if button.uuiLabel then button.uuiLabel:Show() end

  U.Print("key test running. Press a bound key (a hotbar key), then an " ..
          "unbound one (a letter you never use), then Escape.")

  U.RegisterUpdate("commands.keytest", 1, function()
    if not keyTest then return end
    keyTest.elapsed = keyTest.elapsed + 1
    if keyTest.elapsed >= 15 then StopKeyTest("timeout") end
  end)
end

handlers["keytest"] = function() StartKeyTest() end

handlers["bind"] = function()
  if type(U.OpenQuickBind) ~= "function" then
    U.Print(U.L("QUICKBIND_UNAVAILABLE"))
    return
  end
  U.OpenQuickBind()
end

handlers["perf"] = function(rest)
  if type(U.PerfCommand) ~= "function" then
    U.Print("perf recorder is unavailable in this build")
    return
  end
  U.PerfCommand(rest)
end

-- The settings window cannot safely create an EditBox on this client, so its
-- Create button uses a generated name and this chat command is the supported
-- path for a custom one. Chat input is owned by the native UI and does not use
-- unrealUI's known-crashing addon-created text-input path.
handlers["profile"] = function(rest)
  local action, name = Split(rest)
  if action ~= "create" or name == "" then
    U.Print(U.L("CMD_PROFILE_CURRENT",
                tostring(U.GetCurrentProfileName and
                         U.GetCurrentProfileName() or "")))
    U.Print(U.L("CMD_PROFILE_CREATE_USAGE"))
    return
  end
  if type(U.CreateProfile) ~= "function" then
    U.Print(U.L("CMD_PROFILE_UNAVAILABLE"))
    return
  end

  local ok, reason = U.CreateProfile(name)
  if not ok then
    if reason == "exists" then
      U.Print(U.L("CMD_PROFILE_EXISTS", name))
    else
      U.Print(U.L("CMD_PROFILE_NAME_RULES"))
    end
    return
  end

  U.Print(U.L("CMD_PROFILE_CREATED", name))
end

-- Native Classic mode has no UnrealUI settings window by design.  Keep theme
-- selection available through the existing native chat input so a player can
-- return to Modern without editing SavedVariables by hand.
handlers["theme"] = function(rest)
  local id = string.lower(Trim(rest))
  local style = U.GetThemeStyleDefinition and U.GetThemeStyleDefinition(id)
  if not style or not style.available then
    U.Print(U.L("SETTINGS_THEMES_AVAILABLE"))
    local styles = U.GetThemeStyles and U.GetThemeStyles() or {}
    local i
    for i = 1, table.getn(styles) do
      if styles[i].available then
        U.Print("  |cffffff00" .. styles[i].id .. "|r - " .. styles[i].label)
      end
    end
    return
  end

  if U.SetThemeStyle(id) then
    U.ShowConfirm({
      owner = "commands.theme-reload",
      centered = true,
      text = U.L("SETTINGS_THEME_CHANGED"),
      detail = U.L("SETTINGS_THEME_RELOAD", style.label),
      acceptText = U.L("COMMON_OK_SHORT"),
      cancelText = U.L("COMMON_CLOSE"),
    })
  end
end

-- Language selection from chat, for the same reason `theme` exists here: the
-- Classic theme has no UnrealUI settings window, and a player who has ended up
-- in a language whose glyphs their client cannot draw needs a way back that
-- does not depend on reading the interface. Both the two-letter badge (en) and
-- the full locale code (enUS) are accepted, since the badge is what is on the
-- selector and the code is what is in SavedVariables.
handlers["lang"] = function(rest)
  local wanted = string.lower(Trim(rest))
  local languages = U.GetLanguages()
  local i

  for i = 1, table.getn(languages) do
    local entry = languages[i]
    if wanted ~= "" and (wanted == string.lower(entry.short) or
                         wanted == string.lower(entry.code)) then
      if U.SetLanguage(entry.code) then
        U.ShowConfirm({
          owner = "commands.language-reload",
          centered = true,
          text = U.L("SETTINGS_LANGUAGE_CHANGED"),
          detail = U.L("SETTINGS_LANGUAGE_RELOAD", entry.label),
          acceptText = U.L("COMMON_OK_SHORT"),
          cancelText = U.L("COMMON_CLOSE"),
        })
      end
      return
    end
  end

  U.Print(U.L("CMD_LANGUAGE_CURRENT", U.GetLanguageLabel()))
  U.Print(U.L("CMD_LANGUAGE_AVAILABLE"))
  for i = 1, table.getn(languages) do
    local entry = languages[i]
    U.Print("  |cffffff00" .. string.lower(entry.short) .. "|r - " .. entry.label)
  end
end

-- Skips core/compat.lua's native-frame suppression on the next load.
--
-- Why this needs its own command rather than a /uui perf switch: the perf
-- switches all gate recurring *work*, and can be flipped live. Suppression is
-- not recurring work -- it is a one-off state change applied to ~1275 stock
-- objects at OnEnable, and it is irreversible in-session because the original
-- Show is discarded and UnregisterAllEvents cannot be undone. So it can only
-- be skipped, and only from the very start, which means a persisted flag and
-- a reload.
handlers["nosuppress"] = function()
  if not U.db then
    U.Print("config not loaded yet")
    return
  end
  U.db.noSuppress = not U.db.noSuppress
  if U.db.noSuppress then
    U.Print("native frame suppression |cffff5555OFF|r on next load - " ..
            "|cffffff00/reload|r to apply")
    U.Print("  the stock unit frames and action bars will be visible on top " ..
            "of unrealUI; that is expected, it is what suppression normally hides")
  else
    U.Print("native frame suppression |cff55ff55ON|r again - " ..
            "|cffffff00/reload|r to apply")
  end
end

-- Bisects the suppression recipe rather than switching it wholesale. Measured
-- (see knowledge.json / compat.native_suppression_pcall_burst_stutter): the
-- recipe's permanent state, not its sweep, is what costs -- +2.66ms/frame and a
-- 9ms -> 159ms target-change peak. This narrows that to a step.
--
-- Level 4 used to add UnregisterAllEvents on top of the event-driven re-apply,
-- and that call was the party-only freeze (knowledge.json /
-- compat.unregisterallevents_native_frame_stall). It is gone from every level,
-- so 4 now differs from 3 only by the event-driven group sweeps. The ladder is
-- kept at five steps because it is the instrument that located the freeze.
local SUPPRESS_LEVELS = {
  "0 - off, stock frames fully intact",
  "1 - Hide() only",
  "2 - + SetAlpha(0)",
  "3 - + EnableMouse(false) and the Show() neutraliser",
  "4 - + event-driven re-apply on target/party change (shipped default)",
}

handlers["suppress"] = function(rest)
  if not U.db then
    U.Print("config not loaded yet")
    return
  end

  local level = tonumber(rest)
  if not level then
    U.Print("suppression level: |cffffff00" ..
            tostring(U.db.suppressLevel or 4) .. "|r" ..
            (U.db.noSuppress and "  |cffff5555(nosuppress also on)|r" or ""))
    local i
    for i = 1, table.getn(SUPPRESS_LEVELS) do
      U.Print("  |cffffff00/uui suppress " .. SUPPRESS_LEVELS[i])
    end
    U.Print("  lowering a level needs |cffffff00/reload|r to take full effect: " ..
            "what was already applied to a stock frame cannot be undone in-session")
    return
  end

  if level < 0 then level = 0 end
  if level > 4 then level = 4 end
  U.db.suppressLevel = level
  -- The two settings would otherwise fight: noSuppress forces level 0.
  if level > 0 then U.db.noSuppress = false end

  U.Print("suppression level |cffffff00" .. tostring(level) .. "|r - " ..
          "|cffffff00/reload|r to apply")
end

handlers["debug"] = function()
  if not U.db then
    U.Print("config not loaded yet")
    return
  end
  U.db.debug = not U.db.debug
  U.Print("debug output " .. (U.db.debug and "|cff55ff55on|r" or "|cffff5555off|r"))
end

local function HandleCommand(message)
  local command, rest = Split(Trim(message))

  if command == "" then
    if type(U.OpenSettings) == "function" then
      U.OpenSettings()
    else
      U.Print(U.L("CMD_SETTINGS_UNAVAILABLE"))
      ShowHelp()
    end
    return
  end

  local handler = handlers[command]
  if handler then
    handler(rest)
    return
  end

  U.Print(U.L("CMD_UNKNOWN", command))
  ShowHelp()
end

-- SlashCmdList handlers receive the message directly. The guard keeps a nil or
-- unexpected argument shape from erroring out of the command entirely.
if type(SlashCmdList) == "table" then
  SLASH_UNREALUI1 = "/uui"
  SlashCmdList["UNREALUI"] = function(message)
    if type(message) ~= "string" then message = U.G("arg1") end
    if type(message) ~= "string" then message = "" end
    HandleCommand(message)
  end
else
  U.Error("SlashCmdList is unavailable; /uui not registered")
end

-- Edit mode is a mode, not a setting: a session always starts locked, even if
-- the last one ended mid-drag. Only frame *positions* survive a reload.
U.RegisterModule("core.commands", {
  OnEnable = function()
    if U.db then U.db.locked = true end
  end,
})
