# Nameplates roadmap

Status of UnrealUI's nameplates (`modules/nameplates.lua`, settings in
`modules/nameplatesettings.lua`), measured against ShaguPlates' nameplate
options (`C:\Games\Azeroth Launcher\diagnostics\shaguplates-index`).
ShaguPlates is reference for intent only: no code, config schema or assets are
copied.

Legend: **Done** = implemented and in game · **Done (untested)** = code is in,
not yet checked in game · **Next** = planned · **Blocked** = needs runtime
evidence first · **Won't do** = out of scope or against UnrealUI rules.

## Handoff for the next agent

**State (2026-10-20):** Phases 1 and 2 are written and uncommitted, and none
of it is tested in game yet. Phase 2's open items are all done; what is left
of it is blocked on runtime evidence, as is all of Phase 3. Next step: the
in-game checklists below, then record the owed evidence. The working tree also holds the user's own
uncommitted edits in `core/commands.lua`, `core/media.lua`,
`modules/castbar.lua`, `modules/character.lua`, `modules/modernwow.lua` and
`modules/nameplates.lua` (cast bar, Modern WoW health art). Preserve them.

**Read first:** `CLAUDE.md`, `.claude/rules/unreal-ui.md`,
`.claude/rules/unreal-ui-design.md` and, for any text,
`.claude/rules/unreal-ui-localization.md`.

**Files**

| File | Role |
|---|---|
| `modules/nameplates.lua` | Discovery, overlays, refresh, and all option behaviour. `defaults` holds the settings schema; option logic sits on one `style` table to save top-level locals (about 56 of the 200 limit used). |
| `modules/nameplatesettings.lua` | Settings group "nameplates" and its pages, built from spec tables (`nps.PAGES`) by one builder. |
| `core/media.lua` | `M.texture.raidTargetIcons`, `M.color.guildOwn` |
| `core/playercache.lua` | Player name -> class and guild (Phase 2): `U.PlayerInfo`, `U.PlayerKnown`, `U.PlayerGuild`, `U.PlayerCacheLearn`. Session-only. Loads after `core/unitvitals.lua`. |
| `core/widgets.lua` | `U.CreateSlider` gained `disabled` / `SetEnabled` (used by the level-size slider). |
| `locales/*.lua` | `NP_*` keys, identical in all four locales. frFR stays ASCII-only. |
| `unrealUI.toc` | `nameplatesettings.lua` loads right after `nameplates.lua`. |

**Interfaces**

- `U.NameplateSetting(key)` / `U.SetNameplateSetting(key, value)`. A write is
  coerced to the default's type, then runs `style.Invalidate()`: it clears
  every overlay's `cache`, re-runs `style.Layout`, then `RefreshAll()`.
  `showHostile` and `showFriendly` also call `style.ApplyVisibility()`.
- `U.RegisterNameplateSettings()` is called from `NP:OnInit`.
- Per plate, each refresh: `RefreshPlate` resolves the reaction (live, then
  learned, then `style.CachedFriend`, then the creature DB), runs
  `style.RefreshColors` and `style.RefreshTotem`, applies `style.HideHealth`,
  then `style.HealthText`, `style.RefreshOutline`, `style.RefreshZoom`,
  `style.RefreshStrata`, `style.RefreshRaidIcon`, the target auras and cast,
  `style.RefreshGuild` and `style.RefreshCombo`.
- Rows under the bar stack through `style.BelowOffset`: cast bar, guild line,
  combo points.
- Creature lookups (`style.TotemIcon`, `style.IsCritter`) go name ->
  `U.unitNames` -> creature id, so they work for enUS, ruRU and zhCN without
  translation; frFR has no name table.
- Sizes and anchors belong in `style.Layout` only, never in `BuildOverlay`.

**Adding an option**

1. Add the key to `defaults`. Colours are flat numbers (`xR`, `xG`, `xB`):
   `U.ModuleConfig` shares table defaults by reference.
2. Use `cfg.<key>` in a `style.*` function, and give it a cache key if it
   draws.
3. Add a spec line to a page in `nps.PAGES`. Types are check, slider,
   dropdown, color, header and note. `col = 2` puts it in the second column
   of the row; `disabled` greys a slider. Every option applies under every
   theme (user request, 2026-10-20); `flat`/`art` exist only for the two
   height keys, which store different units.
4. Add its `NP_*` text to all four locales.
5. Run `python -B "C:\Games\Azeroth Launcher\runtime-reports\query_unrealUI.py" <term>`
   to refresh the index.

**Runtime evidence still owed** (record results in `knowledge.json` through
the compat workflow; nothing new was recorded this pass):

- `ShowNameplates`, `HideNameplates`, `ShowFriendNameplates` and
  `HideFriendNameplates` on this client.
- The native plate's raid-icon region: is it detected
  (`parts.raidicon`)? Is its `GetTexCoord` cell readable? Does `SetAlpha(0)`
  alone hide it?
- Whether `style.ShowEdges` hiding (rather than a zero vertex alpha) holds
  after theme or border refreshes.
- `SetFrameStrata` carrying the target overlay's children (bars, cast bar,
  aura row) to LOW with it (`style.RefreshStrata`).
- `GetComboPoints("target")` (also used by the unit frames' combo strip).
- `UnitClass(unit)` as (localized, token); `GetNumGuildMembers`,
  `GetGuildRosterInfo`, `GuildRoster`, `GUILD_ROSTER_UPDATE`.
- Literal `Interface\Icons\<name>` paths for the totem icons.

**Validation available:** there is no Lua interpreter here. A tokenizer-based
block and bracket balance check was used. Key parity across the four locales
was checked with a short Python script.

## Phase 0: Foundation (done)

| Feature | Status | Notes |
|---|---|---|
| Plate discovery (WorldFrame scan, structural classifier, FrameXML denylist) | Done | `ClassifyPlate`, `ScanWorldFrame` |
| Native art muting, recycled-plate watch, first-frame invisible font | Done | `MuteNativePlate`, `WatchPlates`, `NAMEPLATE_FONT` |
| Overlay per theme (Modern / Classic WoW / Modern WoW art) | Done | `BuildOverlay` |
| Name, level (difficulty colour, elite `+`), health bar | Done | |
| Reaction colour (live target/mouseover, then creature DB) | Done | `reaction.*` |
| Exact creature HP via `core/unitvitals.lua` | Done | |
| Target debuffs on the plate | Done | `showAuras`, `modules/auras.lua` |
| Target cast bar on the plate (icon, name, timer, Modern WoW spark) | Done | `attachTargetCast`, `/uui npcast` preview |
| Fade non-target plates | Done | `fadeOthers` |
| Diagnostics (`/uui np`, dump, perf counters) | Done | |

## Phase 1: Easy and core options (this pass, done but untested in game)

Settings are now a **Nameplates** group with four pages: General, Health,
Target and Raid Marks.

| Option | Keys | Status | Notes |
|---|---|---|---|
| Enable, target debuffs, target cast bar (moved onto General) | `enabled`, `showAuras`, `attachTargetCast` | Done (untested) | |
| Width, health height, vertical offset, name/level/health-text font sizes | `width`, `healthHeight`, `artHealthHeight`, `verticalOffset`, `nameSize`, `levelSize`, `healthTextSize` | Done (untested) | Applied live by `style.Layout`. Height sits beside width under every theme: Modern WoW uses its own `artHealthHeight` (art units, default the authored 20) and stretches the art vertically. Name and health-text sizes apply under every theme (Modern WoW now shows the name). The level-size slider is disabled: the client does not apply it yet (user report 2026-10-20). |
| Show on hostile and friendly units | `showHostile`, `showFriendly` | Done (untested) | `Show/HideNameplates`, `Show/HideFriendNameplates`: documented, **not runtime-verified**. Applied at login and after each loading screen. |
| Health text format | `healthFormat` | Done (untested) | Percent, current, current/max, current (percent), missing. Falls back to percent when the real max is unknown. |
| Health text position, abbreviate numbers | `healthTextPos`, `abbrevNumbers` | Done (untested) | |
| Show health text | `showHealthText` | Done (untested) | Existing setting, now exposed. |
| Hide health bar for enemy NPCs, enemy players, neutral NPCs, friendly NPCs or friendly players | `hide*` | Done (untested) | Player detection is a heuristic: seen live, else "not in the creature DB". |
| Hiding exceptions: always show on the target and on damaged units | `keepHealthTarget`, `keepHealthDamaged` | Done (untested) | |
| Fade opacity | `otherAlpha` | Done (untested) | |
| Target zoom and its size | `targetZoom`, `targetZoomPercent` | Done (untested) | Scales the overlay and keeps its anchor. |
| Target outline and colour | `targetOutline`, `highlightR/G/B` | Done (untested) | Off by default (no resting outline, user request 2026-10-20). Modern WoW tints its white selected-plate art instead of edges; untinted on the target when no outline applies. |
| Reaction outlines | `outline*` | Done (untested) | Off by default. Modern WoW: selected-plate art in the reaction colour. |
| Raid marks: show, position, size, X/Y offset | `raidIcon`, `raidIconPos`, `raidIconSize`, `raidIconX/Y` | Done (untested) | Target: `GetRaidTargetIndex`. Other plates: read from the native raid-icon region's texture cell; **unverified** on this client. |
| Abbreviate long names | `abbrevNames` | Done (untested) | Over 20 bytes; UTF-8 safe initials. |
| Show names | `showName` | Done (untested) | On by default; hides the name on every plate, level kept (user request, 2026-10-20). |

### In-game test checklist for Phase 1

- [ ] Every page opens. No overlapping controls under Modern, Classic WoW or Modern WoW.
- [ ] Sliders resize live plates. Font sizes change. Nothing drifts after `/reload`.
- [ ] `ShowNameplates` / `HideFriendNameplates` act at login, after zoning and on toggle (record the result in `knowledge.json`).
- [ ] Each health format, position and number abbreviation. Players fall back to percent.
- [ ] Health-bar hiding per category. The target and damaged exceptions work.
- [ ] Target zoom keeps the plate anchored. Fade and outline follow target changes.
- [ ] Raid mark on the target. Then on a non-target plate (party leader marks a mob). If the native cell is not readable, record it and fall back to target only.
- [ ] Long English, Russian and Chinese names abbreviate without broken characters.

## Phase 2: Conditional features (open items done, untested; rest blocked)

| Feature | Status | Blocker / plan |
|---|---|---|
| Class-coloured enemy/friendly player bars, class-coloured friendly names | Done (untested) | `classColorEnemy`, `classColorFriendly` (on), `classColorFriendlyName` (off), General page. Cache: new `core/playercache.lua` (`U.PlayerInfo`, `U.PlayerKnown`, `U.PlayerGuild`), session-only, fed by player, target, mouseover, party, raid and the guild roster (localized roster class resolved through tokens learned from `UnitClass`). A cached name never seen live is treated as a friendly player (party/raid/guild), which also fixes those plates defaulting to hostile. A name seen live as a creature is never class-coloured. `UnitClass` has no compat record (modules/tooltip.lua relies on the same shape); the roster calls and `GUILD_ROSTER_UPDATE` are documented only. |
| Combo points on the target plate | Done (untested) | `comboPoints` (default on), `comboSize`. `style.BuildCombo/LayoutCombo/RefreshCombo`: filled points only, under the bar's right edge (under the cast bar while one shows). Flat: `M.rogueCombo` squares with a black outline; Modern WoW: its active combo circle. `GetComboPoints("target")` is documented only; the unit frames' combo strip already uses it, so that strip working in game is the evidence -- no separate probe. |
| Debuffs on non-target plates (position, size, stacks, own only, whitelist/blacklist) | Blocked | No unit token for non-target plates. Needs a name+level debuff cache (ShaguPlates `PlateCacheDebuffs`); estimates only. |
| Debuff countdown text (milliseconds near expiry, low-time colour) | Done (existing) | The target plate's debuff row already draws the shared `U.FormatTimeShort` countdown (tenths under 5 s, `M.cooldownText.low` red), governed by Auras > Show timers. No extra options, by user decision 2026-10-20. |
| Cast bars on non-target plates (only-target toggle, spell name, height) | Blocked | No `UnitCastingInfo` (UNSUPPORTED). `CHAT_MSG_SPELL` parsing is PARTIAL. Needs a combat-log cast provider and a same-name collision policy. |
| Totem icons replacing totem plates; hide health on totems | Done (untested) | `hideTotemHealth` (on), `totemIcons` (off), `totemSize`, Health page. `style.TOTEM_IDS`: 73 shaman-totem creature ids -> spell icon, resolved through `U.unitNames`, so enUS/ruRU/zhCN need no translation; frFR has no name table and is not recognised. Icon art names WORKING_SOURCE (ShaguPlates' list, plus Tranquil Air); literal `Interface\Icons` paths unverified beyond the bank fallback and npcast preview. |
| Hide health on critters | Done (untested) | `hideCritterHealth` (on, as ShaguPlates), Health page beside neutral NPCs. `style.CRITTER_IDS`: the 93 VMaNGOS `creature_template` type-8 entries (patch <= 10) less GM/test/trigger ones; a name counts only if every id sharing it is a critter. |
| Guild name line (green for own guild) | Done (untested) | `showGuild` (off, as ShaguPlates), General page "Players" section. `style.RefreshGuild`: `<Guild>` centred under the bar, `M.color.guildOwn` (new, the tooltip's guild green) for the player's own guild, dim otherwise; from `U.PlayerInfo`. Rows under the bar now stack (`style.BelowOffset`): cast bar, guild line, combo points. |
| Target plate draws above overlapping plates | Done (untested) | `style.RefreshStrata`: other plates BACKGROUND, target LOW (ShaguPlates' scheme), so the target never reaches MEDIUM windows and the LOW bag window (level 100) stays above it. Non-target plates also drop below the LOW HUD. `SetFrameStrata` reaching child frames is documented, not runtime-verified: confirm the target's bar, cast bar and debuffs all rise with it. |
| Keep the client's nameplate key state in step with the hostile/friendly options | Blocked | `NAMEPLATES_ON` semantics unverified on this client. |

### In-game test checklist for Phase 2

- [ ] Overlapping plates: the target's plate draws on top, bar, cast bar and debuffs included; bags and the Character window still cover it.
- [ ] Rogue / Cat Form: combo points appear under the target's bar, move under the cast bar while it casts (`/uui npcast`), clear on target change; size slider works.
- [ ] Class colours: enemy player bar after targeting, party/guild members friendly and class-coloured, friendly names option; an NPC sharing a known player's name keeps its reaction colour.
- [ ] Guild line: own guild green, other guilds dim, none for guildless players; stacks with cast bar and combo points without overlap.
- [ ] Totems: health hidden by default; icon mode shows the right icon per totem (note any blank one); size slider works.
- [ ] Critters: health hidden on rabbits, rats, deer and so on; a creature sharing a critter's name keeps its bar.
- [ ] Modern WoW: name shown above the bar, no overlap with level or debuffs; outline tints on the selected-plate art; level-size slider shows disabled.

## Phase 3: Interaction (blocked on probes)

| Feature | Status | Notes |
|---|---|---|
| Clickthrough | Blocked | `EnableMouse` on a native plate is unprobed. Plates are crash-sensitive native widgets. |
| Overlapping plates (disable stacking) | Blocked | Same. |
| Right-click mouselook and its attack threshold | Blocked | Same. Also check the input APIs. |

## Won't do

| Feature | Reason |
|---|---|
| Glow around the target | Decorative shadow. Against the Modern design rules; Modern WoW already has its selected art. |
| Font, border size, pixel-perfect border and health-bar texture choices | The theme system and `M.modernWow.nameplate` own these. |
| Vertical health bar | Little value. |
| SuperWoW combat-state colours (attacking you/others/no one/casting) | No SuperWoW on this client. |
| Health-point estimation (`libhealth`) | `core/unitvitals.lua` already provides exact creature HP. |
| Turtle WoW extras, profiles, `/rl` `/sp` commands, pfUI config framework | Not nameplate scope, or conflicts with UnrealUI. |
