# Border Skirmish — farming loop

Three offline placeholder encounters: three player squads, simultaneous one-second
rounds, one commander strike per interval, encounter rewards, automatic replay
and three troop upgrades. Upgrade any troop to level 2 to unlock Archer Position;
upgrade every troop to level 2 to unlock Fortified Position. Uses native Godot controls,
shapes and fonts; no downloaded art, plugins or runtime packages.

## Run (Windows PowerShell, from this directory)

Requires **Godot 4.7.2 Standard**, not .NET. This machine's portable installation:

```powershell
$GODOT = "$env:LOCALAPPDATA\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
& $GODOT --version
& $GODOT --path .
```

Alternatively import `project.godot` in that editor and run the main scene.
The window starts at 720×960 and resizes. Click Commander strike or use Tab
and Space/Enter on a focused button. Activation happens on press; holding a
key does not repeat. Restart works during battle and after victory.

The starting army wins Border in four passive rounds, or three with one strike
each round. Losing focus or suspending freezes in-memory combat; the resume-frame
gap is excluded. Each result stays visible for one second, then the selected
encounter replays at full health. Border victories pay 10 gold; Archer Position
victories pay 30 gold; Fortified Position victories pay 54 gold, once per battle
including replays. Defeat pays nothing.
Restart abandons the current battle without settlement, clears queued input and
timing, cancels pending replay, and retains gold and owned levels. Already-earned
victory gold remains; restarting itself never pays.

Each troop starts at level 1, costs 20 gold for level 2 and 40 for level 3, and
caps at level 3. Each level adds health/damage: shield +40/+2, foot +12/+4,
horse +20/+3. Ownership changes immediately; combat snapshots change only at the
next replay, restart or encounter switch. Insufficient funds and capped purchases change nothing.
Gold and owned troop levels save locally after victories and successful purchases.
Every launch starts fresh full-health Border combat; there is no absence/offline reward.

Archer Position unlocks immediately after any troop reaches level 2, including
from an existing version-1 save or recovered backup. Gold alone does not unlock it.
Selection is manual: no automatic advancement or entry fee. Switching abandons
an ongoing battle without reward, clears queued strikes/time and cancels replay;
already-settled gold remains. Manual restart and replay retain the selection.
Border always remains available. Selection is rejected while suspended.
Only gold and upgrades persist, not selection or completion. Unsaved upgrades
retain their unlock in memory only until a successful save retry.
At the first upgrade, passive Archer takes eight rounds with a shield upgrade,
or seven with either archer upgrade. Combat stats and costs are unchanged.
Native scrolling and focus-follow keep controls reachable when content exceeds
the viewport; the existing canvas scaling remains unchanged.

## Separate session-only campaign prototype

For a future separate launch using the pinned Standard executable above:

```powershell
& $GODOT --path . --scene res://scenes/campaign_prototype.tscn
```

With `godot` on PATH, the equivalent is
`godot --path . --scene res://scenes/campaign_prototype.tscn`.
The normal main scene and its launch instructions are unchanged.

This isolated native-control prototype owns one in-memory Campaign. Closing or
recreating it resets gold, upgrades and clearances; main-game saves are never
loaded or changed. No main-menu link, commander or restart control is included.
Border → Archer → Stronghold transitions settle immediately, with the last
result retained onscreen rather than a replay delay. Farm requests require that
encounter's clearance; the latest valid farm/frontier request applies after the
current battle settles, never abandoning its reward. Purchases apply next battle.
A long frame stops at the first battle boundary; focus loss/pause freezes combat,
with no offline catch-up and the first resumed frame excluded.

Stronghold clearance ends at **“Conquest cleared — prototype ends here; ordinary
farming remains available”**. Frontier is a disabled no-op at that checkpoint;
from farming it returns there after settlement without replaying Stronghold.
There is no Fortified frontier, defense, dynasty, export or playable-release approval.

**Campaign supervised graphical verification PASSED; automatic minimization remains a separate unresolved failure.**

Latest complete run (2026-09-08, `--manual-focus`): **52 graphical checks,
0 failures, exit 0**, about 51 seconds including user interaction. The user
started the test, minimized when prompted, and closed the window after results.
The same run covered campaign progression through conquest, deferred navigation,
purchases, scrolling, and physical minimize/freeze/restore without catch-up.
Godot's foreground checks remained satisfied outside the explicit suspension test.
This is a supervised native run, not independent continuous Win32 focus telemetry
or a headless substitute. No milestone beyond campaign verification is started.

```powershell
& $GODOT --path . --script tests/campaign_scene_smoke.gd
# Short suspension reproduction only, not campaign integration coverage:
& $GODOT --path . --script tests/campaign_scene_smoke.gd -- --focus-only
# Same assertions, with a physical title-bar minimize click instead of automatic minimization:
& $GODOT --path . --script tests/campaign_scene_smoke.gd -- --manual-focus
```

Keep the window focused and unminimized except during the explicit suspension test.
Manual mode first displays **START WHEN READY**, without a countdown. After
starting, minimize only when its title says **MINIMIZE**; the driver waits for
that click without a countdown, then restores automatically. The window stays
open after success or failure until you close it; the title displays the result.
Closing before completion exits with failure. `--focus-only` can be combined
with `--manual-focus` for the short physical check. The 60-second watchdog
excludes human readiness and result viewing; actual battle and suspension checks
retain their deadlines. Use a 70-second external bound for unattended automatic
runs, not interactive manual runs. Foreground interruptions outside the explicit
suspension test still record failure, but do not close an interactive window.
No focus/suspension assertions are bypassed.

The driver exercises real elapsed-time progression, viewport mouse/keyboard
activation, deferred farm/frontier navigation, six purchases, next-battle stats,
conquest settlement, checkpoint farming, and narrow-window focus-follow scrolling.
Its only campaign fixture adds 180 session gold for purchases; battle timing,
outcomes and clearances are not changed. Captures use the native renderer and
are written to ignored `.gg/screenshots/campaign/`; they are not desktop captures
or evidence of physical input.

**Earlier attempts during this verification run (2026-09-08):** one complete interaction
portion passed **44 checks**, and all seven rendered captures were inspected.
The full run still failed the following native suspension gate. Automatic
minimization leaves Godot reporting focus while combat continues; an external
Win32 probe confirmed the native window was minimized and not foreground.
Godot's focus flag therefore does not independently prove continuous native
focus on this host. A physical-click attempt observed no minimize transition
within 15 seconds; a subsequent full run timed out during Stronghold and is
failed evidence, not a replacement pass. An earlier full manual-mode attempt
failed after about 15 seconds at **25 checks, 1 failure**, with the observed
state `mode=0 focus=false suspended=true`: real focus was lost before the
minimize prompt, and the campaign correctly entered suspension. The new
fail-fast monitor preserved that exact blocker instead of waiting for a timeout.
**Subsequent physical check passed:** after replacing the click countdown with
an explicit human-readiness wait, `--focus-only --manual-focus` completed
**9 graphical checks, 0 failures, exit 0**. The user minimized the window; Godot
reported `mode=1 focus=false suspended=true`. Rounds and partial elapsed time
remained frozen, automatic restore regained focus, and no catch-up round occurred.
That short check alone did not establish a complete campaign pass. Its 9 checks
and the earlier 44-check interaction portion remain separate historical results;
the later 52-check full supervised pass is recorded above. One intervening full
run exposed an offscreen test target; the keyboard helper now explicitly scrolls
an already-focused button back into view before input, retaining its visibility
assertion. The successful full run exercised this correction.
Automatic-minimize failures remain unresolved, not proof of an engine root cause.
Native suspension assertions retain the active-combat precondition.

Earlier checks on the wider working tree: editor import passed; headless normal / forced / normal
completed **1157/0, 1158/1, 1157/0** checks/failures, exits **0/1/0**, with exactly
one intentional forced failure. The separate opening-battle graphical smoke
passed **105 checks**, exit 0; it does not establish campaign graphical success.
The separately recorded Fortified graphical failure remains unresolved. Human
persistence remains **DEFERRED — not passed**. Comparable external GDScript
integration usage remains unverified; the driver follows local test patterns.
No new implementation milestone or campaign-saving scope is approved.

**Scoped checkpoint verification:** the separately staged prerequisite snapshot
passed editor import and normal / forced / normal with **591/0, 592/1, 591/0**
checks/failures, exits **0/1/0**, exactly one intentional failure. These counts
exclude unrelated, still-uncommitted main-game test additions; no tests were
removed from the working tree. The campaign runtime files match the successful
52-check supervised graphical run. Captures, logs, staging snapshots and `.godot`
data remain ignored and outside both commits. Normal Git hooks are not bypassed;
this checkout has only sample hooks and no configured active hook.

Previously recorded prototype headless verification (2026-09-08, native Godot 4.7.2 Standard,
35-second caller bounds): editor import exit 0 with no script/parse errors;
normal / forced / normal completed **1157/0, 1158/1, 1157/0** checks/failures
with exits **0/1/0**, exactly one intentional forced failure, and all **162**
existing balance rows retained. The existing malformed-number save tests emit
two `Exponent too high` warnings. Isolated persistence earn/reload/parent passed
**13/10/4** checks, zero failures, exit 0. An initial redirected normal run timed
out before SUMMARY during existing timing tests; it is failed evidence, not a
pass. The subsequent direct normal/forced/normal sequence above completed under
the same bounds without code changes. No graphical or human-persistence claim.

## Local progress and recovery

`user://progress.json` stores only version 1, gold and three owned troop levels.
Use the Godot editor's **Project → Open User Data Folder** to locate it. Reads
are bounded to 4 KiB; gold must be a whole number from 0–9007199254740991 and
levels exactly three whole numbers from 1–3. Numeric strings, booleans, nonfinite
values, and fractions (including fractions rounded away by JSON doubles) are
rejected. No resources, objects, scripts, paths, battle health, strikes, replay
state, timestamps or offline income are loaded from this file.

- Missing progress starts defaults without writing on launch. Valid progress
  loads before the first combat snapshot; no startup or shutdown save occurs.
- At startup, damaged, unsupported or unreadable progress remains untouched. That session
  plays defaults with saving disabled and a persistent explanation. Close the
  app and move `progress.json` and any `progress.json.bak` aside together to
  explicitly start over, or reopen with a compatible version. Keep the moved
  files if progress matters; there is no reset button or automatic migration.
- Writes stage to `progress.json.tmp`, check write/flush errors, close, reread
  and validate the entire snapshot. The validated primary is moved to `.bak`,
  checked there, then the staged file moves into the now-empty primary path.
  A failed commit attempts restoration, retaining the backup if restoration
  also fails. Abandoned `.tmp` files are uncommitted and ignored on load.
- A missing primary can recover a validated `.bak`; a present damaged or
  unsupported primary never silently falls back to an older backup. Recovery
  does not rewrite on launch; the next successful economy mutation saves.
- Write failure or a transient primary-read failure after an accepted startup
  preserves in-memory rewards/purchases and shows **Progress not saved**.
  A failed preflight read writes nothing; the next save rereads and validates
  the primary. The next successful victory or purchase retries the full current
  snapshot, clearing the warning on success. No double reward, refund or rebuy.
  **Unsaved changes can be lost when closing.** Restart, defeat, rejected
  purchases, duplicate settlement and replay alone never save or award gold.
- If the primary becomes damaged or unsupported during play, saving is disabled
  for the rest of that session, with the same persistent preservation/recovery
  instructions as startup. Earned gold and purchases stay in memory, not replaced
  by disk state. Restarting combat does not clear this protection or warning.

**One running instance only.** There is no writer lock or cloud sync; add writer
locking before supporting concurrent instances. The last-good backup covers
replacement recovery, not device loss. Recovery can lose mutations since the
last successful save (or the attempted mutation during interrupted rotation).
There is a missing-primary window between moves: this is **not crash-atomic**
and does not claim power-loss durability. Keep an external backup for device
loss; no automatic off-device backup is configured. Excessive gold is rejected
for persistence rather than rounded.

## Verify

```powershell
& $GODOT --headless --path . --editor --quit
& $GODOT --headless --path . --script tests/run_tests.gd
# Expect complete SUMMARY, zero failures, and $LASTEXITCODE = 0.

& $GODOT --headless --path . --script tests/run_tests.gd -- --force-failure
# Expect exactly one forced failure and $LASTEXITCODE = 1.
& $GODOT --headless --path . --script tests/run_tests.gd

& $GODOT --path . --script tests/scene_smoke.gd
& $GODOT --path . --script tests/scene_smoke.gd -- --progression
& $GODOT --path . --script tests/scene_smoke.gd -- --fortified
# Default: 105 checks. Archer progression: 35 checks. Fortified: 37 checks.
# Each has a 25s internal deadline and a 35s caller bound.
# Graphical session required. Do not move focus away during this short run.
# Expect complete graphical SUMMARY, zero failures, and $LASTEXITCODE = 0.

& $GODOT --headless --path . --script tests/persistence_smoke.gd
& $GODOT --path . --script tests/persistence_smoke.gd
# Two isolated scene processes: earn/purchase/exit, then reload/new victory.
# Keep each graphical child foreground and unminimized. Bound each command to 35s.
# Expect earn (13), reload (10), parent (4) checks, all zero failures, exit 0.
```

Missing summary, parse errors, timeout or a nonzero normal exit means failure.
The graphical driver has a 25-second deadline; automated callers should also
bound the process (35 seconds used here) to catch parse errors before startup.
It loads the actual scene, injects mouse/key events through its viewport,
waits for real timed rounds, and captures after `frame_post_draw`.
Keep the graphical window foreground and unminimized until its summary; do not
interact with other windows. OS focus loss intentionally freezes combat and
rejects commands, invalidating this foreground timing/input gate. An interrupted
run is not a pass: preserve its failure output and rerun the complete suite in
an uninterrupted graphical session. Do not disable suspension or extend deadlines.

## Verified evidence — 7 September 2026

- Engine: `4.7.2.stable.official.ed1daf0bf`.
- Official Windows x86-64 Standard archive downloaded via the
  [release archive](https://godotengine.org/download/archive/4.7.2-stable/).
  SHA-512 matched official `SHA512-SUMS.txt`; both executables had valid
  Authenticode signatures from **Prehensile Tales B.V.** before execution.
- Headless import succeeded; **51 named model/scene checks passed**.
  Forced invocation: **52 checks, one intentional failure, exit 1**;
  subsequent normal invocation: **51 checks, zero failures, exit 0**.
  Timing regressions cover ten tenths, one hundred hundredths, integer
  microsecond partitions, exact remaining time, and no attack one microsecond early.
- Actual main scene launched under OpenGL 3.3 Compatibility on NVIDIA
  GeForce GTX 1080 (driver 561.17); its managed process was stopped afterward.
- Separate native graphical run: **30 checks passed, exit 0**. Verified
  queued/victory/restarted UI, actual viewport button routing, held-key echo
  rejection, terminal-input isolation, and smaller-window interaction.
- Six PNGs saved and visually inspected in ignored
  `.gg/screenshots/opening-battle/`: `initial.png`, `commander-queued.png`,
  `victory.png`, `restarted.png` (720×960), plus `small-restarted.png` and
  `small-queued.png` (540×720). Labels and controls were readable and contained.
  Re-running the driver refreshes these generated captures.

Official archive SHA-512:

```text
83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993
```

## Commander interval regression

Verified in the pinned native `4.7.2.stable.official.ed1daf0bf` graphical engine.
The smoke test sets a clock seam with 1,250,000 foreground microseconds pending
while the actual scene still shows round zero, then sends viewport mouse or
keyboard press/release events without awaiting a frame or calling a command
handler. The delayed mouse press has no intervening synthetic motion event.
Both empty and previously queued intervals are exercised, plus terminal catch-up
at 4,250,000 microseconds. Graphical waits remain bounded by the existing timeout.

Before the fix, the expanded run completed **50 checks, 12 failures, exit 1**.
Immediately after dispatch, both devices still reported round zero, enemy HP 72,
and a queued strike. Catch-up applied new input to the expired first round;
with a prior strike, the disabled button instead lost the new request.

The shared foreground-clock helper now runs in `_input` before GUI routing and
in `_process`. Settling only inside `Button.pressed` would miss an already-disabled
button. `_input` neither queues commands nor consumes events; the existing
button signal remains the sole command path. Godot's documented
[input order](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html)
supports this placement; native execution establishes the regression result,
not an external pattern. Comparable GDScript corpus usage remains unverified.

After the fix, dispatch reports round one, enemy HP 54 (no prior strike) or 48
(prior strike), with the new strike queued for round two. Terminal catch-up
rejects input. Verification: **59 headless checks and 50 graphical checks,
zero failures, both exit 0**. Exact timestamp tests cover single span consumption,
repeat timestamps, pause/resume exclusion and restart origin reset. The existing
round-boundary precision work (integer microseconds and partition regressions)
is preserved; combat formulas and scene wiring are unchanged.

## Multi-squad conquest model — verified 8 September 2026

The combat model now supports fresh Border skirmish and Archer position
fixtures, explicit squad roles, and multiple enemy squads. Both armies choose
living round-start targets by role: shield/foot prefer shield → horse → foot;
horse prefers foot → horse → shield. Damage is simultaneous, with no overkill
spill. Commander strikes keep their starting strength and frontline priority.

Native verification using `4.7.2.stable.official.ed1daf0bf`:

- Headless editor import: exit 0, no parse errors.
- Headless suite: **177 checks, zero failures, exit 0**.
- Forced-failure path: **178 checks, exactly one intentional failure, exit 1**;
  subsequent normal run: **177 checks, zero failures, exit 0**.
- Graphical regression: **50 checks, zero failures, exit 0**, completing in
  approximately 8.4 seconds under the unchanged 25-second internal deadline
  and a 35-second caller timeout. Timing and viewport input assertions remain.
- Archer position's first passive round: enemies **88 / 34 HP**; players
  **106 / 40 / 60 HP**. The fixture wins passively in eight rounds with a
  survivor; eight is an observed result, not a required balance target.
- Controlled fixtures exercise both armies' complete role priorities with
  absent/dead candidates and scrambled names/order, commander rate limiting
  and casualty-independent strength, simultaneous death-round damage, no spill,
  mutual defeat, round-60 precedence, terminal freezing and independent squads.

The approved public `gdquest-demos/godot-open-rpg` reference could not be indexed:
this corpus indexer does not recognize GDScript files. Comparable combat-pattern
usage therefore remains **unverified**. The official
[Array reference](https://docs.godotengine.org/en/stable/classes/class_array.html)
confirms typed arrays and reference semantics; fresh squad construction and
unchanged array membership during rounds follow those constraints. Native tests,
not an external RPG architecture, establish this bounded implementation's behavior.

## Graphical release-gate investigation — 8 September 2026

The reported 50-check runs with 7 and 22 failures had no focus trace; their
historical cause cannot be proved retrospectively. Fresh native runs used the
same pinned `4.7.2.stable.official.ed1daf0bf` console executable and renderer.

- Temporary diagnostics recorded `Window.has_focus()`, lifecycle notifications,
  `suspended`, `skip_resume_frame`, `elapsed_usec` and `last_frame_usec` at every
  scene assertion (checks 2–50; check 1 precedes scene creation).
- Controlled OS minimization after check 33 reproduced the failure family:
  **50 checks, 14 failures, exit 1**. The Windows foreground handle changed,
  focus-out notification 2017 arrived, and every failing assertion showed
  `focus=false suspended=true skip_resume_frame=false`. Check 34 retained
  `elapsed_usec=362691`, with `last_frame_usec=6317007`; subsequent delayed
  dispatches reported `rounds=0 enemy=72 queued=false`, zero elapsed time,
  and advancing frame timestamps. Second boundaries and terminal catch-up failed
  because suspension correctly discarded time and rejected commands.
- Two consecutive diagnostic runs completed **50 checks, zero failures, exit 0
  each**. All 49 scene assertions were focused, unsuspended, and outside the
  resume-skip frame; neither run received focus-out. No focused clock or GUI
  routing failure was demonstrated.
- After removing all temporary diagnostics, the required headless command
  completed **177 checks, zero failures, exit 0**. Two consecutive unmodified
  graphical runs then completed **50 checks, zero failures, exit 0 each**, in
  **8.175 and 8.176 seconds**, refreshing the six ignored PNGs.

All final commands had 35-second external bounds; the graphical internal
25-second deadline, every assertion, viewport injection, and no-motion delayed
mouse path are unchanged. No gameplay or harness fix was warranted. This
re-establishes the current gate under its foreground precondition, rather than
reclassifying the untraced historical failures as proven focus interruptions.
Only documentation and generated screenshots remain changed by this investigation.

## Pre-commit verification — 8 September 2026

Two initial graphical invocations failed **22/50** and **5/50** checks. Neither
recorded suspension state, so their cause remains unproven. A temporary trace
then completed **50/50**, with every scene assertion unsuspended and outside
the resume-skip frame; no gameplay defect was established. After removing that
trace and the leftover `DISPATCH` print, two consecutive graphical runs passed
**50/50**, exit 0, in **9.792 and 8.213 seconds**. All assertions, clock behavior,
focus handling and deadlines remain unchanged. Failed invocation logs remain
outside the repository in the local command history; a later pass does not
reclassify those failures as proven focus interruptions.

## Border Skirmish economy — verified 8 September 2026

- Native headless import: exit 0, no parse errors. Expanded suite: **258 checks,
  zero failures, exit 0**, including all 177 pre-existing checks unchanged.
- Forced failure: **259 checks, exactly one intentional failure, exit 1**;
  subsequent normal run: **258 checks, zero failures, exit 0**.
- Graphical suite: **63 checks, zero failures, exit 0**, 19.330 seconds.
  All 50 previous assertions remain. Two passive, real-timed victories earned
  20 gold without restart or input, then viewport purchase and automatic replay
  verified the upgraded snapshot. No unexpected failures occurred in this work.
- Every command had a 35-second external bound; graphical internal timeout
  remains 25 seconds. Focus/suspension behavior and existing checks were not weakened.
- Nine captures refreshed under ignored `.gg/screenshots/opening-battle/`.
  Visually inspected `upgraded-replay.png` (720×960) and
  `small-upgraded-replay.png` (540×720): health, gold, purchases and controls
  contained and readable. `small-purchased.png` captures ownership changing
  while current battle stats remain unchanged.

Purchase guards follow the inspected public
[PokéClicker Upgrade implementation](https://github.com/pokeclicker/pokeclicker/blob/a3062f11fdcf4c22e6a9a7d4747e5bb6614f44ab/src/modules/upgrades/Upgrade.ts#L53-L78):
check the cap and funds before debit and level change. Its globals, observables,
saving and generic upgrade hierarchy are unnecessary here and were not imported.
An active-battle identity and consumed flag prevent duplicate/stale payment without
an ever-growing reward ledger. Native behavior tests establish the local contract;
the external sample does not verify our rewards or Godot lifecycle handling.
The replay timer uses the official [Timer API](https://docs.godotengine.org/en/stable/classes/class_timer.html).

## Local persistence verification — 8 September 2026

- **CODE:** Inspected the pinned engine's complete
  [`DirAccessWindows::rename` implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/dir_access_windows.cpp).
  It removes an existing destination before `_wrename`. The approved adjustment
  rotates the primary into backup first, rather than overwriting the primary.
  Official FileAccess, DirAccess and JSON documentation informed error handling;
  comparable GDScript corpus usage remains **unverified** (indexer gap).
- **RUNTIME:** Native `4.7.2.stable.official.ed1daf0bf` import passed. Headless:
  **369 checks, zero failures, exit 0**, preserving the 258 prior checks.
  Forced run: **370 checks, exactly one intentional failure, exit 1**;
  subsequent normal run: **369 checks, zero failures, exit 0**.
- **RUNTIME:** Tests cover bounded schema reads, exact numeric limits, unsupported
  and corrupt byte preservation, isolated snapshots, replacement and recovery,
  real staging-open and backup-rename obstructions, unreadable-primary directory,
  simulated reported flush failure and failed final move/restoration. Last-good
  backup recovery loaded into memory in **1,181 microseconds** on the final run;
  the subsequent successful mutation repopulated the primary. This is a local
  drill timing, not a recovery-time guarantee. Real full disk, ACL-denied reads
  and power interruption were not reproduced; their error branches are covered
  by deterministic I/O failures/seams, not claimed as native fault injection.
- **RUNTIME:** Graphical regression: **81 checks, zero failures, exit 0** in
  **20.125 seconds**, including all 63 prior checks; unchanged 25-second internal
  deadline and 35-second caller bound. Save status, fresh restored scene and
  recovery text remain visible. Inspected `saved-reload.png` (720×960),
  `small-saved-reload.png` and `small-save-warning.png` (540×720), under ignored
  `.gg/screenshots/opening-battle/`.
- **RUNTIME:** Isolated two-process probe passed both headless and native Windows
  OpenGL runs (12 earn + 9 reload + 4 parent checks, no failures). Native run:
  **15.605 seconds**. Two real-timed victories, purchase, process exit while
  replay pending, new graphical process with matching gold/levels and fresh
  full-health combat, then exactly +10 from one new victory. This native run
  is distinct from the headless probe. Neither uses real player saves.
- Initial implementation checks exposed one incorrect expected damage value,
  two new graphical assertions mixing physical-window and logical-viewport
  coordinates, an invalid attempt to hide Godot's main window, and two JSON
  rounding acceptance cases. Corrected the test expectations/coordinate space,
  removed the unsupported hide call, and rejected non-whole lexical numbers;
  final runs above passed without weakening old assertions. Extreme exponent
  fixtures intentionally produce Godot's `Exponent too high` warning.
- **Unverified manual gate:** The native probe performs scripted exit/relaunch
  and signal-driven purchase, not a human-operated close button and physical
  purchase. Before release, repeat earn → purchase → close → relaunch using
  a disposable copy of the project with a distinct application name/user-data
  directory, never an existing player's save. Confirm matching ownership,
  fresh combat and exactly one new +10 reward. No power-loss or mobile claim.

All unrelated scene fixtures inject disabled persistence before entering the
scene tree. Persistence fixtures exclusively create uniquely named test-owned
`user://progress-test-<pid>-<ticks>/` directories. The two-process coordinator
retains ownership until children exit and removes only known test entries.
Children have 15-second internal deadlines; the caller's 35-second bound also
catches parse/startup hangs. Force-killing the coordinator can leave its isolated
test directory behind; it never authorizes cleanup of real player data.

## Runtime save-preflight regression — 8 September 2026

- **RUNTIME:** Isolated regression reproduced **388 checks, 7 failures, exit 1**
  before the fix: a transient primary read latched saving off, while runtime
  damaged/unsupported files received impossible retry promises.
- **CODE:** The store now distinguishes transient preflight I/O errors from
  terminal preservation outcomes. The adapter queries that status without
  reloading progress and reuses startup recovery instructions for terminal states.
- **RUNTIME:** Native import passed; headless **388 checks, zero failures, exit 0**.
  Forced run: **389 checks, exactly one intentional failure, exit 1**, followed
  by **388 checks, zero failures, exit 0**. Existing startup-unreadable checks
  remain unchanged. New assertions inspect disk through separate stores, never
  resetting the active store's preservation state.
- **RUNTIME:** Tests verify full-snapshot purchase retry after one injected
  primary-read failure, no duplicate reward, and corrupt/unsupported byte
  preservation plus disabled UI through refresh, combat restart, later mutations
  and relaunch, with no older-backup bypass. Real player saves were not used.
- **RUNTIME:** Native graphical scene smoke passed **81 checks**, exit 0 in
  **19.477 seconds**; graphical two-process persistence passed **12 + 9 + 4 checks**,
  exit 0 in **17.097 seconds**. Both used 35-second caller bounds; focus behavior
  and internal deadlines were unchanged. The separate human-operated release
  gate documented above remains unverified.

## Human-operated release attempt — 8 September 2026

- **UNVERIFIED / VERIFY-BEFORE-SHIP:** Windows native
  `4.7.2.stable.official.ed1daf0bf`, OpenGL compatibility on NVIDIA GTX 1080.
  Disposable import passed; launched the normal main scene, without test scripts.
- Owned disposable copy: `E:\Projects\idle-clicker-release-d1176c46-BGKUMFYI`.
  Copied only project configuration, scenes and scripts, without `.godot` data;
  changed only the copy's application name to
  `Border Skirmish Release d1176c46 BGKUMFYI` before import/launch. Verified its
  user-data directory did not exist before import and primary save did not exist
  before play. Source application identity and real player saves were untouched.
- Evidence is retained in that copy and exclusively its disposable user-data
  directory: `%APPDATA%\Godot\app_userdata\Border Skirmish Release d1176c46 BGKUMFYI`.
  Operator screenshot `.gg/uploads/mtsr6dse-image.png` (ignored local evidence)
  showed **90 gold, levels [1,1,1]**, visible **Progress saved · Autosave on**,
  and the victory/pending-replay message. A live read of this disposable primary
  subsequently showed **100 gold, levels [1,1,1]**. Initial zero-gold UI was not
  observed; missing initial disk state is not a substitute for that observation.
- Operator reported the sequence was too fast to confirm, then confirmed physically
  closing the OS window with **X**. Process exited **0**; the post-close disposable
  primary contained **120 gold, levels [1,1,1]**. Engine output contained startup
  information only, not physical-input or close-timing evidence.
- The exactly-two-victory **20 → 0 gold / [2,1,1]** purchase sequence was not
  achieved; pending-replay close timing was not established. No relaunch was
  performed: restored ownership, shield health **160**, clean combat/commander,
  no launch/offline income and exactly one new **+10** remain unverified.
  No runtime defect is established by this missed procedure. Operator requested
  pausing verification; no cleanup was performed. Repeat the prescribed sequence
  from a fresh uniquely named disposable copy before release, preserving this
  attempt rather than resetting its save. Focus/suspension behavior was unchanged;
  emitted signals and scripted quit were not used as physical-gate substitutes.
- **Operator follow-up:** Reported “verified” and, when asked for the repeat's
  observations, “all checks out, mate, move on.” This is an operator-reported
  success, not an independently observed repeat. No repeat project identity,
  before/after values or inspectable repeat save were supplied. Preserve the
  measured attempt above; the evidence-backed release gate remains unverified.

## Archer Position verification — 8 September 2026

- Native Godot 4.7.2 import passed. Headless: **559 checks, zero failures**.
  Intentional-failure run: **560 checks, exactly one forced failure, exit 1**;
  normal rerun: **559 checks, zero failures, exit 0**.
- Real Combat tests confirmed every predicted exact round/HP balance case and
  all 27 upgrade combinations for both encounters and both input modes.
  Repeated battles are deterministic and independent; authored fixtures remain unchanged.
- Headless and native graphical cross-process persistence passed **13 + 10 + 4**
  checks each. Graphical persistence completed in **15.608 seconds**.
- Default graphical gate passed **105 checks** in **19.529 seconds**; focused
  progression passed **35 checks** in **10.312 seconds**, all zero failures.
  Both retained 25-second internal and 35-second caller bounds.
- With explicit approval, existing graphical layout assertions now test scrollable
  containment and full mouse-target visibility instead of all content onscreen.
  Existing combat/input checks remain. The initial progression run failed one
  scroll assertion because canvas scaling kept the logical viewport at 720×960.
  The passing test captures the normal scaled 540×720 window, then additionally
  constrains logical size to 540×720 to actually exercise native focus scrolling.
- Inspected 720×960 Archer and 540×720 scrolling/focus/save-warning captures:
  readable enemy rows, reachable lower controls and wrapped warning text.
  Captures are ignored under `.gg/screenshots/opening-battle/progression-*.png`.
  Progression seeds only isolated in-memory gold; persistence uses test-owned storage.
  No save schema, combat mechanics, dependencies or real player saves changed.
  These scripted viewport inputs do not replace the separate human release gate.

## Fortified Position — balance and contract, 8 September 2026

Fortified Position appends encounter ID 2, preserving Border/Archer IDs 0/1.
It has an enemy shield with **160 HP / 12 damage** and foot archers with
**80 HP / 12 damage**. Victory pays **54 gold**; defeat pays zero. All three
owned troop levels must be at least 2. A single level-3 troop, gold alone,
rejected purchases and victories alone do not unlock it. The final required
purchase unlocks it immediately, even if saving fails; only successfully saved
ownership survives relaunch. Qualifying version-1 saves and recovered backups
also unlock it without a startup write.

Selection remains manual, with no entry fee or automatic advance. Both older
encounters retain their existing rules and fixtures. Locked, invalid and same
selections leave battle and replay state untouched. Accepted switches abandon
unfinished combat without payment, clear queued input/time and cancel replay.
Restart and one-second automatic replay retain selection and create fresh
squads with current upgrades. Purchases never alter an ongoing battle snapshot.
Save schema/version, costs, cap, combat and focus handling are unchanged. Only
gold/levels persist; every launch starts fresh Border combat.

Native candidate verification ran before gameplay edits using actual Combat
and isolated fresh test enemies: **162 cases (27 ownership combinations ×
3 encounters × 2 modes), each repeated with complete outcome/round/player HP/
enemy HP comparison**. Active means one queued strike before every round.
All eight unlocked ownership combinations win both ways and take longer than
Archer. No qualifying single upgrade increases Fortified duration.

The original 50-gold proposal matched every predicted outcome, duration and
terminal HP, but had five combat-only rate disadvantages versus Archer:
passive [2,2,3], [2,3,2], [3,2,2], and active [2,2,3], [3,2,3]. Full replay-loop
rates did not regress. The user explicitly approved **54 gold**, the minimum
whole reward giving combat-rate parity across unlocked combinations. The
original run reported **795 checks, 5 rate failures, exit 1**; revised native
verification reported **795 checks, zero failures, exit 0**. Two earlier
candidate harness attempts stopped inside the matrix on a typed-empty-array
error despite exit 0; neither counted as a pass. Explicit typed arrays fixed
the harness without changing combat or weakening assertions.

Each entry below is `outcome / combat seconds / gold per combat second`.
Locked combinations are counterfactual probes, not selectable encounters.

| Levels | Mode | Border | Archer | Fortified |
|---|---|---|---|---|
| [1,1,1] | Passive | W / 4 / 2.50 | W / 8 / 3.75 | L / 10 / 0 |
| [1,1,1] | Active | W / 3 / 3.33 | W / 7 / 4.29 | L / 10 / 0 |
| [2,1,1] | Passive | W / 4 / 2.50 | W / 8 / 3.75 | L / 12 / 0 |
| [2,1,1] | Active | W / 3 / 3.33 | W / 6 / 5.00 | W / 11 / 4.91 |
| [1,2,1] | Passive | W / 4 / 2.50 | W / 7 / 4.29 | L / 11 / 0 |
| [1,2,1] | Active | W / 3 / 3.33 | W / 6 / 5.00 | W / 10 / 5.40 |
| [1,1,2] | Passive | W / 4 / 2.50 | W / 7 / 4.29 | L / 13 / 0 |
| [1,1,2] | Active | W / 3 / 3.33 | W / 6 / 5.00 | W / 10 / 5.40 |
| [2,2,2] | Passive | W / 3 / 3.33 | W / 6 / 5.00 | W / 10 / 5.40 |
| [2,2,2] | Active | W / 2 / 5.00 | W / 5 / 6.00 | W / 7 / 7.71 |
| [3,3,3] | Passive | W / 2 / 5.00 | W / 5 / 6.00 | W / 7 / 7.71 |
| [3,3,3] | Active | W / 2 / 5.00 | W / 4 / 7.50 | W / 6 / 9.00 |

Fortified terminal player HP: baseline [0,0,0] both modes; all-level-2
passive [0,52,20], active [4,52,80]; all-level-3 passive [32,64,100],
active [68,64,100]. Including the one-second replay delay, Fortified earns
4.91 passive / 6.75 active gold per second at unlock, and 6.75 / 7.71 at cap.
These are ideal uninterrupted loop rates, not focus-loss wall-clock promises.
The headless suite prints all 162 complete snapshots and both rates and checks
production fixtures against the isolated candidate. Expanded behavior/save
coverage passed **952 checks, zero failures, exit 0** before graphical work.

Initial final automated gates completed in order on Windows / Godot 4.7.2:

| Gate | Actual result | Engine exit |
|---|---|---|
| Native editor import | Complete; no script/parse errors | 0 |
| Normal headless | 952 checks, 0 failures | 0 |
| Forced failure | 953 checks, exactly 1 intentional failure | 1 |
| Normal headless rerun | 952 checks, 0 failures | 0 |
| Default scripted graphical | 105 checks, 0 failures | 0 |
| Archer scripted graphical | 35 checks, 0 failures | 0 |
| Fortified scripted graphical | 37 checks, 0 failures | 0 |
| Headless cross-process persistence | Earn 13 / reload 10 / coordinator 4; 0 failures | 0 |
| Graphical cross-process persistence | Earn 13 / reload 10 / coordinator 4; 0 failures | 0 |

All final logs were checked for script/parse errors and missing summaries;
none occurred. Both normal headless logs contain all 162 balance rows. The
existing two excessive-exponent parser warnings remain expected negative-test
output. Graphical runs completed in approximately 21.3 / 10.3 / 12.2 seconds;
graphical persistence took 15.6 seconds, all within their original bounds.
The Fortified run also checked foreground focus at start, victory and finish;
no focus workaround or suspension override was used. Selected and small-window
bottom screenshots were inspected: enemy HP, +54 reward and reachable focused
restart matched the authored controls. These are scripted, not human, evidence.
An erroneous persistence invocation with unsupported `--graphical` was rejected
with `persistence invalid: 1 checks, 1 failures`, exit 1, before creating a
fixture. The documented graphical command (no `--headless`, no user arguments)
then passed as recorded above; the argument guard was not changed.

### Earlier requested verification rerun — 8 September 2026

Headless rerun: **952 checks, zero failures, exit 0**. Default graphical:
**105 checks, zero failures, exit 0**. Archer graphical: **35 checks, zero
failures, exit 0**. Fortified graphical: **37 checks, four failures, exit 1**.
The latest Fortified run passed focused startup, viewport unlock/selection and
the real ten-second +54 victory, but failed fresh replay, return-to-Border,
return-to-Archer and foreground-focus completion. An uninterrupted focused
session was therefore not maintained; the affected Fortified graphical gate is
**PENDING, not passed by this rerun**. The earlier passing run above remains
historical evidence only. No focus workaround, deadline increase, assertion
suppression or suspension change was made. Verification stopped at this failure;
no manual work was requested. Human graphical release remains deferred.

### Subsequent supervised Fortified pass — 8 September 2026

The documented `--fortified` command was rerun against the remaining working-tree
UI changes after coordinating focus with the user. It completed **37 graphical
checks, 0 failures, exit 0**, in **12.940 seconds**. Focus assertions passed at
startup, the ten-second victory, and completion. The final purchase unlocked
Fortified; both enemy rows rendered; victory paid 54 gold once; fresh replay,
return to Border without payment, restored Archer stats, and small-window
focus-follow scrolling all passed. All six native rendered captures were
inspected and remain ignored. No code, deadline, focus check, or suspension
behavior was changed to obtain this pass. Log execution ID:
`b3b9bfa2-9669-4f2a-9fad-50cfbd46e9f9`.

This later pass clears that scripted Fortified rerun gate; the four-failure run
above remains historical evidence, not erased or reclassified. Scripted viewport
input is still not physical gameplay or human persistence release verification.
The campaign automatic-minimize failure is a separate issue and remains unresolved.
The checkpoint's complete staged-tree gates must pass independently before commit.

The new `--fortified` branch uses isolated in-memory ownership/funds, viewport final purchase and
selection, real timed +54 victory/replay, both older selectors and small-window
focus scrolling. It does not touch real player saves. Scripted graphical
success is not physical-input evidence. **Human graphical release gate:
DEFERRED — not passed.** The retained human-attempt evidence above is unchanged.
Comparable external GDScript combat usage remains unverified; the inspected
PokéClicker guard-first upgrade sample informs purchase validation only.

## Boundaries

Combat rules live only in `src/combat.gd`; `src/economy.gd` owns gold, troop
levels, purchase validation, snapshot creation and once-only outcome settlement.
`src/progress_save.gd` alone owns persistence I/O. The scene adapter loads before
combat creation and saves only accepted economy mutations; it also owns timing,
the one-second result/replay timer and presentation. Fresh encounter data never
shares mutable squads. The playable scene presents all three authored encounters,
with an explicit second enemy row rather than a generalized roster renderer.
Native node-script wiring follows the inspected official Godot demo pattern;
its random/physics behavior is not used. The local specification and executable
tests, not that unrelated demo, establish combat correctness.

No automatic advancement to other encounters, gate upgrades, defense, dynasty,
final art or Android tooling is implemented. Border Skirmish, Archer Position and
Fortified Position repeat by manual selection; both older fixtures are unchanged.
Viewport-injected input is **not physical mouse/touch verification**. Suspension tests exercise lifecycle notifications,
not a physical Android device or OS sleep. No mobile export, sustained device
performance or cinematic-art feasibility claim is made. Those gates remain
separate, later milestones under the approved plan.

Original design documents remain unchanged; this bounded approved build
supersedes their older technology-deferral wording only for this encounter.
Initial setup did not create commits or change Git identity.
