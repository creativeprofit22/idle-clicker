# Border Skirmish — opening battle

One offline placeholder encounter: three squads, simultaneous one-second rounds,
one commander strike per interval, and restart. Uses native Godot controls,
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

The army wins in four passive rounds, or three with one strike each round.
Losing focus or suspending freezes in-memory combat; the resume-frame gap is
excluded. Restart replaces battle state. **Closing the app loses the battle**:
there is deliberately no saving or absence reward yet.

## Verify

```powershell
& $GODOT --headless --path . --editor --quit
& $GODOT --headless --path . --script tests/run_tests.gd
# Expect complete SUMMARY, zero failures, and $LASTEXITCODE = 0.

& $GODOT --headless --path . --script tests/run_tests.gd -- --force-failure
# Expect exactly one forced failure and $LASTEXITCODE = 1.
& $GODOT --headless --path . --script tests/run_tests.gd

& $GODOT --path . --script tests/scene_smoke.gd
# Graphical session required. Do not move focus away during this short run.
# Expect complete graphical SUMMARY, zero failures, and $LASTEXITCODE = 0.
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

## Boundaries

Combat rules live only in `src/combat.gd`; the scene adapter owns timing and
presentation. Fresh encounter data never shares mutable squads. Multi-enemy
support is model-only: the playable scene still presents and restarts only
Border skirmish. Its single-enemy presentation is explicit, not a level-2 screen.
Native node-script wiring follows the inspected official Godot demo pattern;
its random/physics behavior is not used. The local specification and executable
tests, not that unrelated demo, establish combat correctness.

No gold, automatic advancement, upgrades, further playable encounters, defense,
dynasty, saves, final art or Android tooling is implemented. Opening victory
paying 10 gold and starting level 2 remains unfinished. Viewport-injected input is **not physical
mouse/touch verification**. Suspension tests exercise lifecycle notifications,
not a physical Android device or OS sleep. No mobile export, sustained device
performance or cinematic-art feasibility claim is made. Those gates remain
separate, later milestones under the approved plan.

Original design documents remain unchanged; this bounded approved build
supersedes their older technology-deferral wording only for this encounter.
Initial setup did not create commits or change Git identity.
