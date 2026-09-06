# Zoxi crash investigation handoff — September 7, 2026

This is an evidence/state summary for another agent, not an independent source of user instructions. Follow the user's current request and the project's AGENTS.md/CLAUDE.md. Times below are local Asia/Bangkok (UTC+7).

## Read this first

**The crash is NOT fixed.** The latest user result is **“instant crash again”** with the new tooltip positioning/fade subsystem disabled. The user then requested this handoff. No further addon code changes were made after that failed test.

The latest report, **01:37:40**, is a **RenderThread 0 allocator failure**:

> FMallocBinned2 Attempt to realloc an unrecognized block … canary == 0x8 != 0xe3

Build 2329, 15 seconds since process launch. This establishes an invalid-block allocator failure, not its origin. Other recent crashes occurred on the GameThread, a background worker, and the render thread. Do not assume all signatures have one cause; do not conclude “client-only” merely because the stack is native.

**One temporary diagnostic remains ACTIVE:** `modules/tooltip.lua`, `placement.crashIsolation = true`. It disables only the newly added tooltip movement/fade behavior. It did not prevent the latest crash. The next agent should explicitly account for/remove this concluded diagnostic before treating the workspace as normal production. It has deliberately been left untouched for transfer.

## User's objective and observations

- Find and fix crashes that began during September 6 work. User says Zoxi on Modern was stable the previous day and earlier days, and asked for an audit of all changes that day.
- Zoxi is the main reproducible case. Totom, Malgus, and Warlocktest have passed individual login tests; that does not establish universal stability.
- Totom once crashed while logging out **to character selection**, not exiting the application. A later explicitly reported login AND logout passed **once**. No reliable exact mapping was obtained for the earlier Totom crash timestamp.
- Opening the main menu preceded one Zoxi crash, but a subsequent launch crashed immediately at login. Menu causality is unproven.
- User asked whether new features could resume after several clean character logins. Further repeated tests reproduced crashes. Do not call the crash resolved or resume feature work on the assumption it is stable.

## Workspace and preserved work

Addon root:

`C:/Games/Azeroth Launcher/Azeroth/Binaries/Win64/Games/Emberveil/live/Azeroth/Interface/AddOns/unrealUI`

Baseline commit: `089117f`, September 5, 16:14:12 +0700, “Bags: move the favourite mark to Alt + Left Click”. Previous release: `963e810`, 0.5.0. No later local commit. The workspace was already heavily dirty when investigation started. **No commits, git reset, wholesale checkout, SavedVariables edits, or sibling-addon edits were made.** Preserve unrelated work.

The client also changed from build **2324 to 2329** on September 6, around 05:16 according to earlier session evidence. That is a confounder: prior source stability does not prove safety on the new build.

Original supplied handoff:

`C:/Users/User/Downloads/HANDOFFcrashsession20260906.md`

Read it as historical evidence. Some conclusions were overconfident and were corrected in this investigation.

## Exact current code state

| Area | Current state | Meaning |
|---|---|---|
| `core/compat.lua` shared suppression | Normal configured suppression restored; startup settle policy unchanged | Temporary `CRASH_TEST_NO_NATIVE_SUPPRESSION` constant and early return are REMOVED |
| `core/compat.lua:1725`, `U.SuppressNativeFrame` | Rejects names matching `^TargetFrameBuff%d`, `^TargetFrameDebuff%d`, `^PartyMemberFrame%d+Debuff%d` before registration/lookup | Retained exclusion of 148 crash-sensitive aura names across themes; not a proven Zoxi fix |
| `modules/petbar.lua:743`, `Apply` | `if (cfg and cfg.buttonLayout) or appliedLayout then RefreshCapture() end` | Retained correction: default-disabled sizing no longer captures ten native child buttons |
| `modules/petbar.lua`, `PB:OnEnable` | Normal startup restored | Temporary whole-petbar early return is REMOVED; source exactly matched `petbar.before-full-isolation.lua` when restored |
| `modules/status.lua` | Original September 6 private-font options restored | The temporary removal of eleven `shadow = false, privateFont = true` lines is REVERTED; file byte-matched `status.before-font-isolation.lua` |
| `modules/tooltip.lua:1335` | **`placement.crashIsolation = true` still ACTIVE** | Four guards in Register, SetCursorFadeAlpha, Tick, ApplyTooltipPosition; failed diagnostic retained for handoff |

Tooltip diagnostic details: it creates no placement guides/mover, schedules no `tooltip.position` updater, and makes no new fade writes. `placement.Apply` also exits because no placement frame exists. It covers manual position reapply. Older `StyleFrame`, show/resize hooks, shopping-tooltip comparisons, and `tooltip.player-style` 0.10-second updater **still run**. This was NOT a whole-tooltip-module disable.

The aura guard can leave stock target auras below the target frame alongside unrealUI custom auras above. Malgus visibly showed this. It is an expected visual consequence, not evidence suppression is globally still off. Do not restore suspected unsafe aura suppression merely to hide duplicates.

Pet module behavior: it loads for **every class**, not only hunters/warlocks. Normal OnEnable checks for `PetActionBarFrame`, then handles the native root, mover, and periodic updates even without a class/pet-presence gate. The retained child-capture correction only limits the per-button size/spacing path.

## Test history, in order

These are user-reported runtime results. Host/mock checks are described separately below.

| Test | Result | Interpretation/current disposition |
|---|---|---|
| Initial central 148-name aura guard | Zoxi still crashed immediately on retest | Guard insufficient as Zoxi fix; retained to avoid previously implicated aura objects |
| Disable **only unrealUI**, other addons unchanged | First Zoxi launch clean, then three additional fresh launches clean: **4 total** | Strongest clean control so far; exact durations unknown; does not identify a module or rule out addon interaction |
| Re-enable unrealUI, force shared native suppression OFF throughout startup/settle/reapply | First fresh Zoxi launch crashed | Shared suppression alone is not required for that tested failure; temporary gate later removed |
| Keep suppression OFF, add default pet-child capture guard | Warlocktest, Totom, Malgus, Zoxi login clean; Totom crashed at logout to selection | Four different characters, NOT four repeated fresh Zoxi launches. Stock UI overlap expected |
| Restore normal suppression, keep aura/pet guards | All four characters reported no crash; Malgus duplicate native/custom target auras | Preliminary passes only |
| Repeat normal-suppression test | Totom login+logout to selection clean once. Zoxi launch 1 clean with play; launch 2 crash seconds later on opening main menu; launch 3 instant login crash | Pet guard did not fix intermittent crash; main menu not established as cause |
| Skip entire petbar OnEnable before native lookup/custom mode/parenting/mover/events/updates | Zoxi fresh launches 1 and 2 clean with a few mobs killed; launch 3 instant login crash | Whole pet startup suppression is not a complete mitigation; diagnostic removed, pet restored |
| Restore pet startup; remove only eleven new status/population private-font opt-ins | **First fresh start crashed** | Status-font rollback not a complete mitigation; original status restored |
| Restore status; disable only new tooltip movement/fade subsystem | **Instant crash again** — latest user result | Failed test; diagnostic still installed at handoff, no new test pending |

Several runs passed before failing on launch 3. At least four fresh launches with some play are needed even for an initial clean classification. Passing once or twice cannot clear a module. Conversely, failure after removing a subsystem does not prove that subsystem is universally safe or that another signature has the same cause.

## Crash reports and limitations

UE crash root:

`C:/Users/User/AppData/Local/Azeroth/Saved/Crashes/`

Each directory has `CrashContext.runtime-xml` and usually `UEMinidump.dmp`. Use RuntimeProperties **PCallStack** and **PCallStackHash**; CallStack may be empty. The crashed thread is in `Threads/Thread` with IsCrashed=true. SecondsSinceStart includes character-selection/process time. IsRequestingExit=false does not distinguish gameplay from logout to character selection.

| Local time | Directory suffix after `UECC-Windows-` | Lifetime / thread | Context |
|---|---|---|---|
| Sep 6 23:31:14 | `5B9B84AE4A7896F820ED2D8D5ADFBBB8_0001` | 110s / GameThread | Earlier Zoxi report; hash `8A2B8274E7BE7A8B3839789AE0321E141E5F86E6` |
| Sep 7 00:01:50 | `E6819BE34251CFDEAA014C9B85EDA89B_0001` | 17s / GameThread | Shared suppression OFF still crashed; same `8A2...` hash |
| 00:15:29 | `B33FC0464DFAEECAEBBC70A3EDF2537A_0001` | 15s / GameThread | Same `8A2...` hash; exact character/action mapping unresolved |
| 00:18:45 | `0B8097EA4EEFB379ACC8BC8CAEBB9A55_0001` | 168s / GameThread | Hash `85180A76512C24A76B88624BA83F5409ACCD1BAA`; not conclusively mapped to Totom |
| 00:30:51 | `243908924B034006EBD3DE91495E003A_0001` | 61s / GameThread | Hash `ED8129BA7B5C258D328BCFB68FCA7325AA98090B`; not conclusively mapped to Totom |
| 01:05:55 | `D63A4A984DEB1F093E74A084A0A4F98A_0001` | 15s / GameThread | After normal suppression/pet guard; only one new UE report found for two user-reported failures. Hash `EC98A1B105FBF21CA26B87B5A0E1440F1AB8391D` |
| 01:16:38 | `7403E6FB474376111BDCE4A95A100916_0001` | 17s / Background Worker #6 | Whole pet startup OFF; error address 0x23, hash `497890DFD33DC35525940E7BF64526B2C6F4A2EA` |
| 01:29:12 | `A1B4505249AB5FB4C80D328CFA17F9D9_0000` | 16s / RenderThread 0 | Status-font rollback; AV at `0x1a032bc3100`, hash `6AB2BF12B16A30493570C98EF94923EF239D4E70` |
| **01:37:40** | **`645FE77F48B12B64B96D6AAD16AFE4CD_0000`** | **15s / RenderThread 0** | **Tooltip placement/fade OFF; allocator invalid block/canary failure; hash `030889A3115F816D33701713709DB65AB3669E6E`** |

Latest error is MallocBinned2.cpp line 900, “Attempt to realloc an unrecognized block 000001EB4E6F0000 canary == 0x8 != 0xe3”. Native executable offsets start `115b31e -> 117846e -> 2713be6 -> 279df61 -> 277e0c0 -> 27d741c -> 28352f6 -> 254235a -> 281b640 ...`. The preceding render-thread AV shares part of the later render chain, but exact corruption source remains unknown.

Earlier GameThread dumps often execute a heap address, followed by `+145197c/+113e017/+1139629/+12cc077`, exception machinery, then `+3787d86/+3f6775f/...`. The 01:05 dump has `+3787d80` instead. These are unsymbolized offsets, not identified Lua/native functions.

WER root: `C:/Users/User/AppData/Local/CrashDumps/`. Relevant files:

- `Azeroth-Win64-Shipping.exe.44224.dmp`, Sep 6 23:34:53, 36s, Background Worker #4.
- `Azeroth-Win64-Shipping.exe.43436.dmp`, Sep 6 23:48:49, 35s, Background Worker #14.
- Both final read AVs at `ntdll+0x165497`; bounded raw-stack scans found hundreds of exception-shaped records and a stack-overflow candidate. Those scans are **not unwinds or proof of root cause**.
- No newer WER dump was found at handoff. No usable client PDB/debugger was available in the earlier inspection.

## September 6 change audit

Full audit already completed against September 5 HEAD: **24 tracked modified files + 9 new files/assets**. File mtimes are not reliable per-hunk history. See `change-audit/AUDIT.md`, inventory, full diff and zip described below; do not restart a broad audit from nothing.

Findings:

1. **Definite default-path regression corrected:** unconditional pet `RefreshCapture()` captured ten native child buttons even when sizing disabled. Guard now prevents this. Production-function mock replay went from 20 native child method reads/110 global lookups to 0/0 across 100 refreshes; root mover still runs. This correction did not establish crash resolution.
2. **New status fonts:** eleven source option sites create private fonts at startup even for Original. Individually rolling these options back failed. Restored.
3. **New tooltip placement/fade:** each-frame native positioning in fixed and cursor modes; native root/text/bar reset writes on show even with followCursor=false. Individually disabling this new subsystem failed. Diagnostic still installed. Older tooltip operations were not disabled.
4. **New unit-vitals:** new ~437 KB data table, startup name-index chunks of 1200 entries/tick, bounded 400-entry cache, defaults exactVitals=true. Applies to Modern too. Pure data/normal unit API work seen; no new retained native widgets found. Not independently isolated.
5. **Modern target ornaments:** eight addon-owned slices, three conditional TGA assets. Fifteen TGA files passed structural header/RLE checks, which does not establish renderer safety. Enhanced glow PNG appears unused. Not independently isolated.
6. **Chat:** new noTextShadow/private-font/background behavior is dormant for known Zoxi defaults (`noTextShadow` absent/false); shared font helpers retained. Not comprehensively exonerated.
7. **Bags/bank/item slots:** higher rendering strata; bank-count labels/readback; new sorting logic. Sorting is action-triggered, not automatic at login. Bank-count reconciliation needs bank activity. Lower startup priority, not exonerated.
8. **Classic unit-frame changes:** substantial but much gated out for Zoxi Modern; do not attribute every unitframes diff to the Modern startup path. Castbar shared/event refactoring and exact vitals are not all Classic-only.

Tracked changes: core/{commands,compat,init,itemslot,itemsort,media,style}.lua; locales/{enUS,frFR,ruRU,zhCN}.lua; modules/{actionbarconfig,bags,bank,castbar,castbarclassic,chat,petbar,settings,status,tooltip,unitframes,xpbar}.lua; unrealUI.toc.

New files/assets: Database/{init,unit_vitals}.lua; core/{unitframestyle,unitvitals}.lua; modules/bankcount.lua; media/frame-{rare,elite,boss}-350.tga; media/Textures/unitFrame/enhanced/glow-border.png.

## Saved configuration and other addons

Do not edit SavedVariables. There is **no WTF folder**. Files only persist on clean logout/reload; hard crashes leave stale data.

- Account addon state: `C:/Users/User/AppData/Local/Azeroth/Saved/Account/TOTOM/AddOns.json`.
- Account saved config: same root, `SavedVariables/unrealUI.lua` (~146 KB).
- Character profile selection: `Emberveil/Zoxi/SavedVariables/unrealUI.lua`, table `UnrealUIProfileDB.active = "Zoxi - Emberveil"`.
- Actual profiles: account `UnrealUIProfiles.profiles[profileName]`, not `UnrealUIDB.profiles`.
- Totom selection: `"Totom - Emberveil Copy"`.
- Last checked both active profiles: themeStyle=modern, defaultFont=original, suppressLevel=4, noSuppress=false, petbar.mode=native, buttonLayout=false, buttonSize=0, buttonSpacing=-1.
- Account `UnrealUIDB` alone can show a different font; read selected profile, not just that table.
- Prior addon-state inspection showed unrealUI, unrealQuest and UnrealRuntimeProbe enabled. Only unrealUI was disabled for the four-run control, by the user. No assistant changes to enable states.
- Live `SavedVariables/UnrealRuntimeProbe.lua` rechecked at handoff: **80 bytes**, last written 01:16:13. Do not attribute the newest allocator failure to the historic 12.46 MB probe-save bug: the oversized-file condition is absent. This does not prove the probe addon itself irrelevant.

## Evidence, backups and knowledge

Report base:

`C:/Games/Azeroth Launcher/runtime-reports/zoxi-crash-20260906/`

- `STATUS.md`: latest state prepended above historical entries. Old “current/pending” paragraphs below are superseded.
- `compat.before.lua`: original compat file before this investigation's 148-name guard; includes pre-existing user work.
- `compat.before-suppression-test.lua`: aura guard present, normal suppression; exact restored compat reference.
- `compat.suppression-off.candidate.lua`: historical offline candidate, not literal installed source.
- `petbar.before-full-isolation.lua`: pet child guard present, normal OnEnable.
- `status.before-font-isolation.lua`: full September 6 status file; now restored exactly.
- `tooltip.before-placement-isolation.lua`: full tooltip file before CURRENT diagnostic; use for precise cleanup comparison.
- `test_aura_guard.py`: historical main expects suppression OFF and will fail against normal current suppression. Load definitions only (before `before, before_count = replay`) and call `replay(currentCompat, suppression_off=False)` for current behavior.
- `change-audit/test_pet_capture.py`: compares production pet functions against pre-fix archive. Still relevant; host-only.
- `change-audit/pre-pet-capture-fix.zip`: all 33 modified/new files before pet guard. `all-tracked-changes.patch` and `inventory.json` sit beside it.
- `change-audit/AUDIT.md`: detailed audit, but its opening/current-test text is historical. This handoff and newest STATUS take precedence for state.
- Crash JSONs: `crash-summary.json`, `windows-crash-summary.json`, `petbar-guard-recurrence.json`, `petbar-off-crash.json`, `status-font-off-crash.json`, `tooltip-placement-off-crash.json`.
- `inspect_windows_dumps.py`: bounded metadata parser; raw stack candidates not symbols.
- **Do not rerun `record_findings.py`**: initial archival writer would overwrite later evidence. Likewise temporary record-update scripts were single historical transitions, not idempotent state rebuilders.

Compact knowledge:

`C:/Games/Azeroth Launcher/diagnostics/unreal-runtime/compat/knowledge.json`

Relevant records: `compat.stock_aura_suppression_all_theme_guard`, `compat.zoxi_addon_disabled_baseline`, `compat.zoxi_native_suppression_isolation`, `petbar.disabled_layout_captures_native_children`, `compat.totom_logout_crash_20260907`, `compat.zoxi_petbar_startup_isolation`, `compat.zoxi_status_font_isolation`, `compat.zoxi_tooltip_placement_isolation`, `status.overlays_shadow_free`, `tooltip.default_corner_mover`, `tooltip.cursor_follow_screen_bounds`.

All completed negative results are to remain classified as such. Passing host tests or removing one path unsuccessfully does not upgrade native lifetime safety.

## Validation and project constraints

- Python 3.10 and `lupa.lua51` available. All 77 Lua files compiled earlier in audit; changed files compiled after subsequent tests.
- Focused host replay verified aura exclusions with other suppression active; pet default access correction; whole pet-startup bypass; exact status rollback/restoration; current tooltip guards with old styling/comparison startup still active.
- These tests use mocks, not the native client. Runtime root cause remains unidentified.
- Query source with `python -B "C:/Games/Azeroth Launcher/runtime-reports/query_unrealUI.py" TERM`; query compatibility with adjacent `query_compat.py` before API/native assumptions. Refresh source index after Lua edits.
- Source query writes its disposable index outside addon root. Current sandbox allows source/doc writes inside addon and designated visualization root; shared diagnostics/report writes required narrowly scoped escalation. Do not bypass permissions.
- Read AGENTS.md, CLAUDE.md, imported shared runtime/evidence rules. No subagents were used in this continuation.
- Never Hide/force Show/replace Show or OnShow/unregister native TargetFrame lifecycle. No broad native child walks/cached native-child anchors without focused evidence. pcall cannot catch engine crashes.
- No new guessed PLAYER_LOGOUT/PLAYER_LEAVING_WORLD cleanup hook: source index has no handlers and compatibility knowledge lacks reliable event/lifetime evidence.
- Keep native loot/minimap untouched. Preserve sibling addons and unrelated edits. Lua 5.1 top-level limit is 200 locals; unitframes is around 160, stop growth at 170.

## Where this leaves the investigation

No single tested change has prevented all crashes. The four-run unrealUI-disabled control remains the strongest clean comparison, but interactions and changed client build are unresolved. New data now includes a render-thread allocator failure after removing the tooltip additions, not just ambiguous heap-execution AVs.

The next agent should first read the latest failed result and current diagnostic, then select a deliberate next comparison or analyze the allocator/render evidence. A broader preserved-source baseline or systematic repeated-run module/feature isolation remains an option; **neither has been completed in this chat**. Avoid repeating these failed individual tests, relying on one clean run, or asserting another speculative patch is a fix.

Historical warning from the original handoff: a previous one-launch-per-step module bisect falsely blamed windowmove, which returns immediately in Modern. That bisect was reverted and is invalid evidence. Earlier Classic aura/delay conclusions also overreached: a 10-second delay passed Malgus but failed Warkys. Do not revive delayed stock-aura suppression as a verified solution.
