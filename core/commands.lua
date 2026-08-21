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

local function ShowHelp()
  U.Print("v" .. U.version .. " commands:")
  U.Print("  |cffffff00/uui|r - open settings")
  U.Print("  |cffffff00/uui unlock|r - unlock frames for moving")
  U.Print("  |cffffff00/uui lock|r - lock frames")
  U.Print("  |cffffff00/uui reset|r - reset all frame positions")
  U.Print("  |cffffff00/uui bind|r - open quick binding")
  U.Print("  |cffffff00/uui bindscan|r - dump the client binding table")
  U.Print("  |cffffff00/uui keytest|r - measure whether key events reach addon frames")
  U.Print("  |cffffff00/uui check|r - runtime self-check")
  U.Print("  |cffffff00/uui elite|r - cycle the classification icon test")
  U.Print("  |cffffff00/uui np|r - dump WorldFrame children (nameplates)")
  U.Print("  |cffffff00/uui movertest|r - foundation mover smoke test")
  U.Print("  |cffffff00/uui perf|r - record frame time around target changes")
  U.Print("  |cffffff00/uui nosuppress|r - skip native frame suppression (needs /reload)")
  U.Print("  |cffffff00/uui suppress <0-4>|r - bisect the suppression recipe (needs /reload)")
  U.Print("  |cffffff00/uui debug|r - toggle debug output")
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
    if cb then
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
            ", menu guard " .. tostring(qb.menuGuard))
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
      label = "Mover test",
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

local handlers = {}

handlers["unlock"] = function() U.UnlockUI() end
handlers["lock"]   = function() U.LockUI() end
handlers["toggle"] = function() U.ToggleUI() end
handlers["reset"]  = function() U.ResetPositions() end
handlers["check"]  = function() ShowSelfCheck() end
handlers["help"]   = function() ShowHelp() end
handlers["movertest"] = function() ShowMoverTest() end
handlers["np"] = function() ShowNameplateDump() end
handlers["elite"] = function(rest) HandleElite(rest) end

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
    U.Print("quick binding is not available in this build.")
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
local SUPPRESS_LEVELS = {
  "0 - off, stock frames fully intact",
  "1 - Hide() only",
  "2 - + SetAlpha(0)",
  "3 - + EnableMouse(false) and the Show() neutraliser",
  "4 - + UnregisterAllEvents and the periodic re-apply (shipped default)",
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
      U.Print("settings interface is not available yet in this build.")
      ShowHelp()
    end
    return
  end

  local handler = handlers[command]
  if handler then
    handler(rest)
    return
  end

  U.Print("unknown command: " .. command)
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
