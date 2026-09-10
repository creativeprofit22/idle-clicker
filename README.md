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

Launch separately using the pinned Standard executable above:

```powershell
& $GODOT --path . --scene res://scenes/campaign_prototype.tscn
```

With `godot` on PATH, the equivalent is
`godot --path . --scene res://scenes/campaign_prototype.tscn`.
The normal main scene and its launch instructions are unchanged.

This isolated native-control prototype owns one in-memory Campaign. Closing or
recreating it resets gold, upgrades, clearances and dynasty/doctrine state; main-game saves are never
loaded or changed. No main-menu link, commander or restart control is included.
Border → Archer → Stronghold transitions settle immediately, with the last
result retained onscreen rather than a replay delay. Farm requests require that
encounter's clearance; the latest valid farm/frontier request applies after the
current battle settles, never abandoning its reward. Purchases apply next battle.
A long frame stops at the first battle boundary; focus loss/pause freezes combat,
with no offline catch-up and the first resumed frame excluded.

Stronghold clearance stops at a preparation checkpoint. **Start Defense** explicitly
begins Counterattack; it never starts automatically after conquest, farming or resume.
Ordinary farming remains available; Frontier returns after farm settlement without
replaying Stronghold. Gate upgrades cost **20 then 40 gold**, cap at level 3, and
apply only to the next defense: buying during combat never repairs its gate or
changes its snapshot maximum. The gate HP label shows only retained defensive battles.

Defense uses foreground one-second rounds. Farm inputs queue recovery if defense
fails; Frontier cannot abandon an assault. Defeat pays **0 gold**, retains purchases
and clearances, displays gate-destroyed/timeout recovery guidance, and starts the
latest queued ordinary farm (Archer by default). Settle a Frontier return before
explicitly retrying with fresh troops and gate. Victory instead overrides farming,
displays **Campaign secured**, retains the winning battle and gate HP, pays **0 gold**,
and stops timing/navigation/start. Affordable purchases remain ownership-only operations,
even after security. Suspension freezes combat and rejects every purchase/navigation input.
There is no Fortified frontier, campaign persistence, export or release approval.

### One session-only dynasty reset

Only a **settled Counterattack victory with a surviving gate**, all three clearances,
first dynasty and unused allowance enables **Found a Dynasty**. Stronghold alone is
not enough. Opening the native preview shows actual gold/troop/gate losses; **Cancel**
or Escape changes no gameplay state and returns focus to Found a Dynasty. Purchases
and navigation are blocked while the preview is open; suspension also rejects reset
inputs. **Confirm reset — start dynasty 2** rechecks eligibility and applies once.

Confirmation loses all gold, troop/gate upgrades (levels return to 1), territory and
security; clears battle progress, queued commands/navigation, farm selection and
fractional time; and starts fresh full-health Border in Advance mode at round zero.
All three troop types remain available. **Inherited Drill** doubles squad damage
exactly once, **after level additions**, without changing health, enemies, rewards
or one-second round frequency. The passive opening becomes two rounds instead of
four. The doctrine survives in-session purchases, farming, defeat, recovery and defense.

Stronghold pays **30 gold once per run**, including the successor run, not once forever
per Campaign object; defense pays **0**. Securing dynasty 2 displays **Slice complete —
no further dynasty reset.** There is no second reset, stacked multiplier, Legacy or
extra victory bonus. Secured purchases remain ownership-only outside the preview.
This is **one reset/bonus for this session only**: closing or recreating the campaign
also discards Inherited Drill. Main-game saves remain untouched. Cross-launch doctrine,
campaign save/load, durable outcome protection and reset saving are explicitly deferred.

### Native suspension wall-time repair — 10 September 2026

**Current automated checks pass; physical manual acceptance remains PENDING.**
The older failures below are retained history, not the latest verification status.

The native gate used `SceneTreeTimer` for a 200ms transition wait and 1.2s frozen
interval. Those timers consume engine frame delta, not monotonic wall time: a
reproduced defense failure checked focus after about 63ms, while combat stayed
frozen. Regression assertions against `Time.get_ticks_usec()` failed before the
repair, including the too-short frozen interval. Both waits now use that monotonic
clock with the same 200ms/1.2s durations. Two duration assertions were added; all
existing focus, identity, frozen-state and restoration assertions remain. Native
PID/window-scoped actions, 12s/65s driver deadlines, 20s/75s caller bounds and the
smoke watchdog are unchanged. No production focus workaround was introduced.

One intermediate focus-only run still failed because the window restored during
the frozen interval before any driver restore request (`bd204bcf-8404-4bce-987b-a4f724aa8dab`).
The driver has no startup restore logic; the source of that restoration is unconfirmed.
That failed result is retained, not converted into a pass. Temporary event/frame
tracing and post-failure observation were removed; the existing bounded snapshots remain.

Final runs on the repaired code, with complete native observations and child/driver
exits 0, each confirming child reaped and reader joined:

| Scenario | Checks / failures | Execution log ID |
|---|---|---|
| Defense | 61 / 0 | `848c5bda-4983-4a36-8285-1e33884fb9b1` |
| Dynasty | 57 / 0 | `a61b50c6-8952-4eab-bfbe-7254c1ce7309` |
| Campaign | 54 / 0 | `d13908e8-0972-44f0-8756-8de90f33a25e` |
| Focus-only | 11 / 0 | `b44ae26a-b0b5-472e-baa4-b40126930f80` |

Logs are outside the repository under `%USERPROFILE%/.gg/foreground/<ID>.log`.
All 16 current campaign PNGs were opened, including secured, narrow reset preview
and fresh successor: notices and focused controls were readable, scroll cropping
was expected, and the successor showed round zero, zero gold and doubled damage.
Captures remain ignored. Import and normal/forced/immediate-normal headless checks
passed: **2753/0, 2754/1, 2753/0**, exits **0/1/0**, exactly one intentional failure
(`43ce22a1-a4c9-424a-ab2c-e0527d93f1eb`). Default graphical smoke passed **105/0**, exit 0
(`4d9f5d71-a1e9-4468-8b54-21d651be9d00`). These automated runs do not prove physical
input acceptance or release readiness. No new export or Android claim is made.

### Historical dynasty verification — 10 September 2026

At this checkpoint, implementation was delivered; **verification was not all green**. These are recorded
step-6 results, not checks rerun for this documentation-only review. Raw logs remain
outside the repository under `%TEMP%/idle-step6-verification/` and
`%TEMP%/idle-step6-click-repair/`. Earlier sections below are historical checkpoints.

| Gate | Recorded result |
|---|---|
| Initial import | Exit 0 |
| Headless normal / forced / immediate normal | 2753/0 · 2754/1 (exactly one intentional failure) · 2753/0; exits 0/1/0 |
| Main-game persistence regression | 13/0 + 10/0 + 4/0; existing Save-v1 only |
| Main graphical default / progression / fortified | 105/0 · 35/0 · 37/0, exits 0 |
| Initial native focus-only / campaign | 9/0 · 52/0, child and driver exits 0 |
| Initial native defense | 59/11, failed: click target sampled before deferred scrolling settled |
| After shared click-helper repair | Import exit 0; defense 59/0 and dynasty 55/0, child and driver exits 0; native observations complete, child reaped and reader joined |
| Post-repair native campaign | **Incomplete, 47 checks / 1 failure**, child and driver exits 1; cleanup complete |

The click helper now awaits two layout frames before sampling; all callers await it,
with assertions and deadlines retained. The post-repair campaign passed 44 interaction
checks but the minimized native window retained focus: freeze/restore checks were
**unreached**. No unchanged retry was made; its earlier pass does not clear this failure.
Initial dynasty 53/2 harness failures were repaired; another exit-1 attempt had unreadable
output and remains unresolved. Subsequent UTF-8-captured dynasty runs passed 55/0 both
before and after the shared click repair; failed attempts are not erased by those passes.

### Native suspension diagnostic follow-up — 10 September 2026 (UTC)

Added read-only `NATIVE_DIAG` snapshots in the shared smoke gate and receipt-time
`DRIVER DIAG` OS observations, including failures before successful assertions.
Snapshots include timestamps, owned HWND/PID, iconic/foreground equality, Godot
mode/focus, suspension/lifecycle flags, processing, phase, original/current battle
identity/result, rounds and elapsed time. OS samples follow pipe receipt; they are
not atomic with Godot snapshots and never set successful-observation bookkeeping.
No production code, assertions, native actions, waits or deadlines changed.
Existing uncommitted work was preserved with user approval.

Ran each native scenario once with `PYTHONIOENCODING=utf-8 python
tests/windows_campaign_driver.py <scenario>`, pinned Standard
`4.7.2.stable.official.ed1daf0bf`. Caller/driver bounds remained 75/65 seconds
(full scenarios) and 20/12 seconds (focus-only); Godot's 60-second watchdog remains.

| Gate | Actual summary | Child / driver exits | Duration | Execution log ID |
|---|---|---|---|---|
| Full campaign | 52 checks, 0 failures; native observations complete | 0 / 0 | 30.690s | `9e5e8d43-482c-4697-a23f-4ae312786652` |
| Focus-only | 9 checks, 0 failures; native observations complete | 0 / 0 | 2.424s | `69a4cf9d-a7c8-4d56-a31a-4154144b7404` |
| Full defense | **Incomplete: 45 checks, 1 failure** | 1 / 1 | 32.583s | `11468e86-6186-4513-8340-af1dde4c32e8` |
| Full dynasty | **Incomplete: 25 checks, 1 failure** | 1 / 1 | 22.196s | `3f25bfe6-29da-4789-8e95-34f6f9c7286f` |

All four drivers confirmed child reaped and reader joined. No unchanged retries.
Logs reside under `%USERPROFILE%/.gg/foreground/<ID>.log`, outside this repository.
The original failed campaign log remains untouched at
`%TEMP%/idle-step6-click-repair/campaign.log` (47/1, exits 1/1).

**Observed, not a root-cause repair:** the passing campaign initially reported
`mode=1 focus=true focus_lost=true suspended=true`; Windows reported iconic and
not foreground. At the existing suspension check 76,194 usec later, Godot focus
was false. It then passed the real frozen interval and same-battle restore.
In defense (owned PID 15944, HWND 19794004) and dynasty (PID 15528, HWND 19925076),
Windows still reported iconic/not foreground at failure while Godot reported
`mode=1 focus=true focus_lost=false suspended=true`. Both retained the original
ongoing defense, processing enabled, round zero, and unchanged accumulated time
from observed minimization to failure (34,379 and 16,455 usec respectively).
Godot timestamps span 62,890 and 118,056 usec from first minimized observation to
check; these are observed wall intervals, not claims that the 0.2-second scene
timer guaranteed that much wall time.

This confirms engine/OS focus disagreement at the failed shared gate, **not broken
production suspension or dynasty reset**. The passing run shows transient disagreement;
the failed runs stop at their existing assertion, so delayed notification beyond
failure versus persistent disagreement remains unproven. No actionable production
cause was demonstrated; no engine workaround or timing tolerance was introduced.
Defense and dynasty freeze/restore, later victory/secured checks, and dynasty
preview/cancel/reset/successor checks were unreached. Their required gates remain
**FAILED/incomplete**, despite the new campaign pass.

Opened all 13 fresh PNGs: campaign `initial`, `archer`, `farm`, `stronghold`,
`conquest`, `small-scrolled`, `small-checkpoint`; defense `defense-ready`,
`small-defense-controls`, `defense-start`, `defense-damaged`, `defense-recovery`,
`defense-retry`. UTC timestamps fall within their runs (07:17:35.946–07:18:04.283
and 07:18:37.786–07:18:52.083). Labels/wrapped notices and focused controls were
readable; narrow captures show expected scroll cropping. Gate images show 80/80,
46/80 and fresh 200/200; recovery retains +0 defeat and retry queues farming.
No new secured or dynasty PNG was reached; older files are not current evidence.
Captures remain ignored under `.gg/screenshots/campaign/`.

Pinned import passed (4.407s, `48297036-d57b-4dc1-9afb-b57b6427a684`). Headless
normal/forced/normal completed 2753/0, 2754/1, 2753/0, exits 0/1/0 in
2.573/2.427/2.502s; exactly one intentional failure, no script errors, and the two
existing exponent warnings per run. Log IDs: `ef3f8ce9-c8c8-4db7-8596-9e4d9e8692b1`,
`afa3d9f4-9932-4709-afda-734135117764`, `f136f991-e80f-4c29-9701-4fc1e9512c96`.
Main-game graphical/persistence and CI were not rerun for this diagnostic-only change.
**Physical acceptance remains PENDING. No repair, release, or all-gates-passed claim.**

Step-6 visual review covered all 25 main-game and 14 campaign/defense PNGs, then corrected
final defense-retry/secured and dynasty captures. These automated observations are not
physical input proof. `gh` found no run for HEAD `35d88d1`; successful historical run
`34324612490` targets another SHA and does not validate this dirty diff.
**Physical manual acceptance, including reset preview/cancel/confirm, remains PENDING.**
No export, Android or release acceptance is claimed.

### Defense presentation verification — 8 September 2026

At this checkpoint, implementation and headless gates were complete; **all five
graphical gates and native PNG inspection were PENDING**. Supervision had not been
confirmed, so no graphical commands had been launched or new captures inspected.
The native-gate follow-up below records later runs; earlier conquest passes are
historical evidence, not defense-presentation passes.

Pinned `4.7.2.stable.official.ed1daf0bf`, unchanged **35-second caller bounds**:

| Gate | Checks / failures | Exit |
|---|---|---|
| Headless editor import | Complete, no script/parse errors | 0 |
| Headless normal / forced / normal | 1461/0 · 1462/1 · 1461/0 | 0 / 1 / 0 |
| Default / progression / fortified graphical | Pending supervision | Not run |
| Campaign `--manual-focus` | Pending supervision | Not run |
| Campaign `--manual-focus --defense` | Pending supervision | Not run |

Full headless logs were scanned: **162 balance rows in each run**, no script/parse
errors, exactly one `FAIL forced runner failure` in the forced run, and complete
summaries. The two existing `Exponent too high` negative-save-test warnings remain.
Import took 5.915 seconds; headless runs took 1.964 / 1.745 / 1.840 seconds.
Scene tests exercise real conquest and both defense outcomes, explicit entry and
retry, snapshot-only gate purchases, zero rewards, terminal inertness, exact timing,
input ordering, focus/pause freeze and resume. Small fixtures isolate timeout and
terminal ownership eligibility; they do not replace the real combat outcome tests.

Execution IDs: import `b23a9b98-1277-4f20-be6b-5c4393438318`; headless
`cfeb7275-b66e-4742-9f3b-2fb218437f68`, `5a3992ef-3422-4768-9320-1356bb595e86`,
`4717fbca-89bd-4415-b6cf-23d74979d925`. Full-log audit:
`156b5d89-fbe1-4f61-9c97-95545b10d4b2`.

Scoped diff inspection found only the two campaign presentation files, two existing
test drivers, this README and the one-line Campaign comment correction. No default-game,
balance, save, project configuration or dependency files changed. `git diff --check`
passed; `.godot/`, campaign captures, local logs and `.env` remain ignored. Engine
execution logs live outside the repository. No commit or push was made.

The separate `--defense` graphical scenario uses real purchases and elapsed rounds:
level-one defeat, in-assault gate upgrades, recovery, explicit upgraded retry,
queued-farm victory override, physical minimize/freeze/restore and secured idle.
It preserves the 15-second boundary and 60-second measured watchdog bounds and
existing human-readiness/result-viewing exclusions. Expected ignored native captures:
`defense-ready`, `defense-start`, `defense-damaged`, `defense-recovery`, `defense-retry`,
`campaign-secured`, and the 540×480 `small-defense-controls`. These still require
visual inspection for readable state/HP/recovery text, clipping and reachable controls.
Native viewport input/captures do not prove physical input or independent OS focus.
The inspected official Godot C# HUD sample supports callback-driven native controls
only; local GDScript patterns and executable tests establish campaign behavior.

### Native suspension gate follow-up — 9 September 2026 (UTC)

The smoke helper now retains the battle identity before requesting minimization,
requires the expected active phase (`DEFENDING` for the defense caller), an
`ONGOING` result and enabled processing at observed minimization/suspension, and
rechecks those conditions on every frame of the frozen interval and after restore.
An expired/replaced battle reports **incomplete**, requires a full affected-scenario
rerun, and propagates failure to the caller without running subsequent victory
assertions. Human readiness remains unbounded; the 60-second measured watchdog,
15-second battle bounds and production combat/focus behavior are unchanged.

Supervision was confirmed and the pinned `4.7.2.stable.official.ed1daf0bf` Standard
executable was used in managed background sessions. Actual results:

| Run | Checks / failures | Exit | Evidence |
|---|---|---|---|
| Original defense helper, before editing | 59 / 0 | 0 | `6d0d1e39-e648-4201-873f-0e5debb117ca` |
| Corrected defense, interrupted after active restore | 60 / 6 | 1 | `555205f9-5388-427c-a830-c2c3e9ce1fa9` |
| Deliberately delayed defense minimize | 45 / 1, incomplete | 1 | `3f7a005e-e3f2-4235-9be3-1dcfcc7f479a` |
| Intended prompt-minimize defense rerun, battle expired before click | 45 / 1, incomplete | 1 | `60255c30-94b5-4cb1-82de-5d9087218020` |
| Corrected full conquest `--manual-focus` | Pending supervision | Not run | — |
| Corrected `--manual-focus --focus-only` | Pending supervision | Not run | — |

Both expired-battle runs reported `readiness outlasted the expected battle before
observed minimization`, printed no suspension/freeze/restore pass, skipped subsequent
victory checks, and exited 1 after the supervisor closed the window. The interrupted
run did verify same-active-battle suspension/restore, but subsequent foreground loss,
battle-boundary failure and watchdog timeout invalidate the full scenario. The
original log did not capture state at minimize, and delayed physical action was not
separately confirmed: its apparent pass is not proof of active-defense suspension.

**Complete successful defense, conquest and focus-only graphical gates remain
PENDING**, as does native PNG inspection. The final retry coordination received no
answer, so no further graphical runs were launched. Retain these failed runs as
evidence; rerun each full affected scenario with one prompt physical minimize, then
keep the restored window selected until results. No automatic-minimization fix,
artificial game freeze, injected lifecycle notification or outcome mutation was made.

Headless checks retained 35-second caller bounds: editor import exit 0 in 4.842s
(`5f28b8e2-e150-4a55-a53a-a2bceec69fc1`); normal/forced/normal tests produced
1461/0, 1462/1 and 1461/0 with exits 0/1/0 in 1.926/1.728/1.739s
(`97471f6b-3eae-4e59-810f-3f12582fec89`, `0c4043a8-92ae-4cd1-b8cf-35668f475c24`,
`02cd0917-8aeb-47fb-a122-697d0865b27f`). Full-log audit
`057020a2-2ff4-4b45-adf3-5c24bd40b3de` found 162 balance rows per run, complete
summaries, no script/parse errors, exactly one intentional forced failure, and only
the two existing `Exponent too high` warnings per test run.

The corpus could not index GDScript. A read of Godot Dialogue Manager's C#
`ResolveThingMethod` (revision `a719088aea342572f29b5559fd8726896c9519b2`,
`addons/dialogue_manager/DialogueManager.cs:790–802`) provided an await-then-revalidate
comparison, not evidence of native suspension correctness. This fix uses the local
GDScript gate patterns; execution above establishes the observed behavior.
Only this README and the campaign smoke driver were edited for this follow-up;
pre-existing campaign changes were preserved. Captures and `.godot/` remain ignored.
No dependencies, commits or pushes were added.

### Measured watchdog accounting follow-up — 9 September 2026 (UTC)

The manual minimize prompt now saves the watchdog remainder, assigns `INF` once
for human readiness, and restores exactly that remainder on observed minimization.
The per-frame 60-second reset is removed, including from unattended driver waits,
which now remain measured. Initial START WHEN READY and final result viewing retain
their unbounded exclusions. Active-battle checks, actual combat, the 60-second total
measured allowance and 15-second battle bounds are unchanged.

The existing graphical driver checks the readiness exclusion and exact restoration
and prints both values. The equality check runs immediately after assignment without
an intervening frame; subsequent frames consume the retained budget normally, with
no added tolerance or deadline extension. A source-level reproduction failed before
the change (`11d4dcf1-c6d8-400e-8e5e-a8da1656b2f5`) and passed afterward
(`a7a69b20-949a-49c2-81a5-181f4de25d4a`); this is not graphical proof.

With supervision confirmed, both requested manual commands ran sequentially as
managed background sessions using pinned `4.7.2.stable.official.ed1daf0bf` Standard:

| Scenario | Saved / restored seconds | Checks / failures | Exit on closing | Evidence |
|---|---|---|---|---|
| `--manual-focus` | 31.604610 / 31.604610 | 49 / 1, incomplete | 1 | `12938a9d-40be-4219-b547-58d19e889d40` |
| `--manual-focus --defense` | 28.665164 / 28.665164 | 47 / 1, incomplete | 1 | `1c24762e-0535-4234-a077-023cf20d6fa4` |

Both runs passed the new budget assertions, but observed minimization came after
the expected battle ended or was replaced. Both correctly reported `readiness
outlasted the expected battle before observed minimization`. No active-combat
freeze/restore pass was reached; defense's subsequent victory and secured-idle
checks were not reached. All reached 15-second battle checks passed. Neither run
hit the measured watchdog. These failures do not establish that defense exceeds
its retained budget. Both processes exited after result viewing; neither was killed.
No unchanged manual retry was launched. **Successful full physical graphical gates
remain pending**; retained-budget observation alone is not a full scenario pass.
Subsequent automated results and new PNG inspection are recorded below.

Regression checks used 35-second caller bounds:

| Gate | Result | Exit / duration | Evidence |
|---|---|---|---|
| Headless import | No script/parse errors | 0 / 4.671s | `a893f358-941f-4a53-9059-124697b86818` |
| Normal tests | 2515 checks / 0 failures | 0 / 3.821s | `db5b1ecd-17cd-44cd-bebd-9e154a20f1ca` |
| Forced tests | 2516 checks / one intentional failure | 1 / 3.450s | `0a140a5f-8a4a-4dd5-afb6-eee7fd419673` |
| Normal rerun | 2515 checks / 0 failures | 0 / 3.269s | `e427454f-ee18-48c5-8818-4b37e3de3a7c` |

Full-log audit `3e26add0-b5bb-4ce1-953f-311e4947701a` confirmed complete
summaries, 162 balance rows per test run, no script/parse errors, exactly one
intentional forced failure and only the two existing `Exponent too high` warnings.
The first audit command missed the log's `[stdout]` prefixes; correcting the reader
verified the same logs without rerunning tests. Only the campaign smoke driver and
this README were edited for this accounting fix; existing work was preserved.
No model/default-game changes, dependencies or git-history changes were made.

### Automated verification after watchdog fix — 9 September 2026 (UTC)

Ran the existing Windows driver sequentially, with no code changes, using pinned
Godot `4.7.2.stable.official.ed1daf0bf` Standard. Each retained its 65-second driver
deadline, 75-second caller bound, 60-second smoke watchdog and 15-second battle bounds.

| Command | Complete graphical summary | Child / driver exit | Duration | Evidence |
|---|---|---|---|---|
| `python tests/windows_campaign_driver.py campaign` | 52 checks, 0 failures | 0 / 0 | 31.339s | `49093517-905c-4528-8534-26bc759c85d2` |
| `python tests/windows_campaign_driver.py defense` | 59 checks, 0 failures | 0 / 0 | 46.131s | `8182a605-bdc4-4233-8728-dcb03b6f472a` |

Both passed native focus loss, suspension of the same ongoing battle, frozen rounds,
accumulated time and gate, and restoration without catch-up. Windows independently
confirmed minimized/not foreground and restored/foreground states. Both reported
`native_observations_complete=True` and cleanup with child reaped (exit 0) and reader
joined. Defense also reached victory, retained the winning gate without reward,
and passed secured-idle and disabled-navigation checks. No script errors, timeouts
or failed assertions appeared; no corrective changes or reruns were needed.

Inspected all 14 newly captured campaign/defense PNGs. The campaign progression and
checkpoint text were readable, narrow captures exposed focused farming/defense/gate
controls through scrolling, and defense captures showed gate 80/80, damage 46/80,
zero-gold defeat/recovery, fresh retry 200/200 and secured victory 94/200 with disabled
navigation. Captures remain ignored generated evidence.

These are **automated graphical passes**, not physical manual acceptance. They do
not exercise human-readiness exclusion; the earlier manual runs separately observed
exact remainder restoration but failed their active-battle gates. Physical manual
acceptance remains pending, not waived. No assertions, focus/suspension behavior,
deadlines or model logic were changed for these automated runs.

### Current-checkpoint default scripted graphical verification — 9 September 2026 (UTC)

Ran only `--path . --script tests/scene_smoke.gd` with pinned Godot
`4.7.2.stable.official.ed1daf0bf` Standard, retaining the 35-second caller bound
and unchanged internal deadline, assertions and focus/suspension behavior.

| Gate | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Default scripted graphical | 105 graphical checks, 0 failures | 0 | 19.760s | `ec7a63b2-3910-458b-a3d8-16e73d6f9cd5` |

The complete captured log was read: no script/parse errors, failed assertions or
timeout. This clears only the current-checkpoint default scripted graphical gate.
Progression, fortified and completed checks were not run. Generated PNGs were not
visually inspected in this invocation. No code changed; only this evidence was added.

Follow-up visual inspection opened all 12 native PNGs from that run in
`.gg/screenshots/opening-battle/`: `initial`, `commander-queued`, `victory`,
`restarted`, `small-restarted`, `small-queued`, `small-purchased`,
`small-upgraded-replay`, `upgraded-replay`, `saved-reload`, `small-saved-reload`,
and `small-save-warning`. All exist; their UTC modification times span
04:06:55.621–04:07:14.186, within the recorded run (04:06:54.591 start,
19.760s duration), matching its 12 named PNG-save passes. Timestamp inspection
is recorded as `fb1b97b7-b9cb-4b32-9ae0-1537c68cccea`.

At 720×960 and 540×720, visible HP, gold, state text, purchase labels and
commander/restart controls were readable, with no observed overlap or horizontal
text clipping. The queued control is dimmed; victory shows enemy HP 0/72 and
+10 gold; restart shows fresh HP and retained 10 gold. The purchase capture shows
foot archers Lv.2 with current HP 40/40 and damage 8; replay captures show 52/52
and damage 12. Saved-reload captures show shield Lv.2, HP 160/160 and autosave
text. The small warning wraps its recovery explanation onto two readable lines
and leaves restart fully visible. Its lower footer is outside the scroll viewport;
this static inspection does not establish scrolling or physical input behavior.
The small restarted capture also shows a visible commander focus outline.
No test was rerun or code changed for this inspection.
**Physical manual acceptance remains PENDING; the release task remains open.**

### Fortified opt-in timing diagnostics — 9 September 2026 (UTC)

The original current-checkpoint failure remains **37 checks / 4 failures, exit 1**,
14.592s, execution `a59d9399-89e7-49a9-99a0-20a50e45fce8`. Its full log remains
outside the repository; all six run-linked PNGs were preserved before the new run
in ignored `.gg/screenshots/fortified-failed-a59d9399/`. The original victory,
scaled and bottom captures showed ongoing round 6, enemy HP 52/160 and 26/80,
and zero gold. That failure is not erased or retrospectively explained by this pass.

Added opt-in `--fortified-diagnostics` alongside `--fortified`: the test enables
read-only internal logging before scene entry. Logs include monotonic timestamps,
application focus/pause notifications after state changes, actual resumed-update
skips with discarded update duration, and combat-clock/round state at the victory
wait start and first victory assertion. Default logging is off. No gameplay state
transitions, assertions, 11.5s/1.5s local waits, 25s internal deadline or 35s caller
bound changed. Corpus discovery found Dialogic, but indexing rejected its GDScript;
local patterns and official GDScript documentation informed this implementation,
not a verified comparable public diagnostics implementation.

| Run | Summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Pinned headless editor import/script check | Complete, no script/parse errors | 0 | 11.107s | `ed5e88fc-5d92-411e-a1fb-815c57674efd` |
| `--path . --script tests/scene_smoke.gd -- --fortified --fortified-diagnostics` | 37 graphical checks, 0 failures | 0 | 12.421s | `aada937f-6c53-4868-8283-02a4e1aeea1a` |

The diagnostic wait started at 1,013,483 usec; the first assertion logged at
10,995,114 usec (9.981631s later), before the unchanged 12,513ms local deadline.
It showed round 10, victory, 54 gold, both enemy HP zero, replay timer running,
focus true and suspension false. No focus/pause transition or resumed-update-skip
lines appeared while this scene was instrumented. Those branches therefore remain
unexercised by this run; startup notifications before scene entry are not covered.
The original stall did not reproduce, so its cause remains unproven. All subsequent
assertions passed. No fix or additional scenario run followed. New diagnostic PNGs
were generated but not visually inspected. Physical manual acceptance remains
**PENDING**, and the release task remains open.

### Fortified on diagnostic code, diagnostics disabled — 9 September 2026 (UTC)

Ran only `--path . --script tests/scene_smoke.gd -- --fortified` with pinned
Godot Standard `4.7.2.stable.official.ed1daf0bf`, without diagnostics. Assertions,
local waits, 25-second internal deadline, 35-second caller limit and
focus/suspension behavior remained unchanged.

| Run | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Fortified, diagnostics disabled | 37 graphical checks, 0 failures | 0 | 12.319s | `13ad109d-94a4-4ca5-b130-f4a2ade675e3` |

Complete output showed no errors, failed assertions or diagnostic lines; all six
named PNG-save checks passed. Opened `fortified-locked`, `fortified-selected`,
`fortified-victory`, `fortified-small-scaled`, `fortified-small-bottom` and
`fortified-small-archer` in `.gg/screenshots/opening-battle/`. Their UTC modification
timestamps span 05:00:34.665615–05:00:45.885336, within this run (05:00:33.732 start,
12.319s duration), matching the saved names. Timestamp inspection:
`c4a49dec-31c4-4029-8968-d64a95db8eac`.

Visual findings at 720×960 and 540×720: readable locked requirement, upgrade prices
and full selected enemy rows (160/160, 80/80). Victory shows round 10, both enemies
at zero, 54 gold and the +54 replay message; commander is dimmed. Scaled and bottom
replay captures show full HP and retained 54 gold. The bottom view shows all
purchases and fully visible focused restart. Archer restores enemy HP 100/100
and 40/40 with retained 54 gold and +30 reward text. No label overlap or horizontal
text clipping was observed. Selected/victory/scaled views crop the lower footer
at the scroll boundary; scrolled views omit offscreen content. PNG inspection
establishes visible states, not physical interaction.

No code changed, no retries or other scenarios ran. The original unexplained
37/4, exit 1 fortified failure and its archived captures remain preserved.
**Physical acceptance remains PENDING; the release task stays open.**

### Progression on diagnostic code, diagnostics disabled — 9 September 2026 (UTC)

Ran only `--path . --script tests/scene_smoke.gd -- --progression` with pinned
Godot Standard `4.7.2.stable.official.ed1daf0bf`, without diagnostic flags. All
local waits, the 25-second internal deadline, 35-second caller limit and existing
focus/suspension checks remained unchanged.

| Run | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Progression, diagnostics disabled | 35 graphical checks, 0 failures | 0 | 10.379s | `6a137767-2826-4320-8fc7-57ed265ce632` |

Complete output contained no error, failed assertion or diagnostic lines. All
seven named PNG saves passed. Opened all seven native captures in
`.gg/screenshots/opening-battle/`: `progression-locked`, `progression-archer`,
`progression-victory`, `progression-small-scaled`, `progression-small-bottom`,
`progression-small-border`, and `progression-small-warning`. Their UTC modification
timestamps (04:57:09.117107–04:57:18.379467) fall within this run's interval
(04:57:08.152 start, 10.379s duration), matching the save log names. Timestamp
inspection: `08e3113a-69dc-4907-bc98-59841d317271`.

Visual findings at 720×960 and 540×720: readable unlock hint, purchase prices and
two Archer enemy rows (100/100 and 40/40). Victory shows round 8, both enemies at
zero, 30 gold and the +30 replay message. Scaled replay restores full HP while
retaining 30 gold. The narrow bottom capture shows readable purchases and fully
visible focused restart. Border shows a focused selector, 72/72 enemy HP and
retained 30 gold. The warning fully wraps its unsaved-changes loss message onto
two readable lines. No label overlap or horizontal text clipping was observed;
scrolled views omit offscreen content, and the warning view does not show restart.
These static observations do not establish physical input behavior.

No code changes, retries or other scenarios. The original unexplained fortified
failure remains preserved. **Physical acceptance remains PENDING; the release
task stays open and release acceptance is not complete.**

### Default graphical on diagnostic code, diagnostics disabled — 9 September 2026 (UTC)

Ran only the documented default `--path . --script tests/scene_smoke.gd` with
pinned Godot Standard `4.7.2.stable.official.ed1daf0bf`, without diagnostic flags.
All deadlines, the 35-second caller limit and focus/suspension checks were unchanged.

| Run | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Default graphical, diagnostics disabled | 105 graphical checks, 0 failures | 0 | 19.841s | `851a9074-2a1a-4802-8365-5593f1d101c2` |

Full-log inspection found all 12 named PNG-save passes, the complete summary,
and no error, failed-check or diagnostic lines. Opened all 12 native PNGs in
`.gg/screenshots/opening-battle/`: `initial`, `commander-queued`, `victory`,
`restarted`, `small-restarted`, `small-queued`, `small-purchased`,
`small-upgraded-replay`, `upgraded-replay`, `saved-reload`, `small-saved-reload`,
`small-save-warning`. Their UTC modification timestamps span
04:52:14.945194–04:52:33.479050, within this run (04:52:13.820 start, 19.841s).
Provenance inspection: `6e0a9806-4abc-454a-9be7-e9ba421c82db`.

At 720×960 and 540×720, visible HP, gold, status and purchase labels were readable
without observed overlap or horizontal clipping. Queued controls were dimmed;
victory showed round 3, enemy HP zero and 10 gold; restart showed full HP and
retained 10 gold. Small restart showed the commander focus outline. Purchase
showed foot archers Lv.2 but unchanged current stats; both upgraded replay views
showed HP 52/52, damage 12 and commander +7. Both saved-reload views showed shield
Lv.2, HP 160/160 and autosave text. The small warning's complete recovery message
wrapped onto two lines, with restart fully visible; its footer remains below the
scroll viewport. Static inspection does not establish physical input or scrolling.

No code changed, no retry or other scenario ran. The original unexplained
fortified failure remains preserved. **Physical acceptance and the release task
remain pending; release acceptance is not complete.**

### Headless sequence with diagnostics disabled — 9 September 2026 (UTC)

On the unchanged diagnostic code, ran the required normal → forced failure →
normal sequence using pinned Godot Standard `4.7.2.stable.official.ed1daf0bf`:
`--headless --path . --script tests/run_tests.gd`, adding only
`-- --force-failure` for the middle invocation. No diagnostic flag was supplied.

| Run | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Normal | 2515 checks, 0 failures | 0 | 3.055s | `819f709c-3857-4762-aae5-29ac667b0e3d` |
| Forced failure | 2516 checks, 1 failures | 1 | 2.935s | `fa274f66-e702-491c-b474-5764730dc19e` |
| Normal rerun | 2515 checks, 0 failures | 0 | 4.535s | `f10c5e36-f0dc-442c-8545-e363f734456c` |

Full-log checks confirmed exactly one intentional `FAIL forced runner failure`
in the middle run and no normal failures. All summaries were complete; no script
or parse errors, timeouts or `[FORTIFIED-DIAG]` output appeared. Each log contained
two `WARNING: Exponent too high` messages; this is not a warning-free claim.
Log inspection evidence: `c3d4cfd6-ac6e-43d9-b782-9462957bac74`.
No code changed and no graphical scenarios ran. The original unexplained fortified
failure remains preserved. **Physical and release acceptance remain PENDING;
the release task stays open.**

### Latest fortified verification and PNG inspection — 9 September 2026 (UTC)

The subsequently requested verification of unchanged diagnostic code used the same
pinned engine, command and limits:

| Run | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Fortified with opt-in diagnostics | 37 graphical checks, 0 failures | 0 | 12.341s | `479b6207-07af-4af7-91d8-55bc3575de33` |

Read its full log: all six named PNG-save checks passed, with no script/parse
errors or failed assertions. Opened all six PNGs in
`.gg/screenshots/opening-battle/` and matched their modification timestamps to
this run's UTC interval (04:40:26.042 start, 12.341s duration):

| Inspected PNG | Modification time (UTC) |
|---|---|
| `fortified-locked.png` | 04:40:27.011428 |
| `fortified-selected.png` | 04:40:27.052304 |
| `fortified-victory.png` | 04:40:37.100180 |
| `fortified-small-scaled.png` | 04:40:38.121955 |
| `fortified-small-bottom.png` | 04:40:38.189641 |
| `fortified-small-archer.png` | 04:40:38.221303 |

Timestamp inspection: `20d20651-36c8-4c18-98b3-0465fa428bab`. No captures were
missing or outside the run interval; these are the latest run's captures, not the
preserved original failure images.

Visual findings at 720×960 and 540×720: readable locked hint and purchase labels;
selected Fortified shows two full enemy rows (160/160, 80/80); victory shows round
10, both enemies at zero, 54 gold and the +54 replay message. The commander is
dimmed at victory. Scaled and bottom replay captures show fresh troop/enemy HP
and retained 54 gold. The bottom capture exposes all purchases and a fully visible
focused restart. Archer shows enemy HP 100/100 and 40/40, retained 54 gold and
+30 reward text. No overlapping labels or horizontal text clipping was observed.
The selected/victory/scaled views crop the lower footer at the scroll boundary;
the bottom and Archer views omit offscreen content. These captures establish
visible states, not physical interaction or independent scrolling behavior.

Only this documentation was updated during inspection; no code changed or tests
ran. The original 37/4, exit 1 failure and its saved PNGs remain preserved and
unexplained. No focus/suspension transitions or resumed skips occurred in the
latest log, so those diagnostic branches remain unexercised. **Physical manual
acceptance and release acceptance remain PENDING; the release task stays open.**

### Current-checkpoint progression scripted graphical verification — 9 September 2026 (UTC)

Ran only the documented `& $GODOT --path . --script tests/scene_smoke.gd -- --progression`
(using Bash's equivalent executable invocation) with pinned Standard
`4.7.2.stable.official.ed1daf0bf`. The 25-second internal deadline, 35-second caller
bound, assertions and focus/suspension behavior were unchanged.

| Gate | Complete summary | Exit | Duration | Evidence |
|---|---|---|---|---|
| Progression scripted graphical | 35 graphical checks, 0 failures | 0 | 10.439s | `f43290ab-326a-4f1a-b19a-8bae3041f8b2` |

Complete output contained no script/parse errors, failed assertions or timeout.
Opened and visually inspected all seven native PNGs under
`.gg/screenshots/opening-battle/`: `progression-locked`, `progression-archer`,
`progression-victory`, `progression-small-scaled`, `progression-small-bottom`,
`progression-small-border`, and `progression-small-warning`. Their UTC modification
times (04:24:59.186–04:25:08.495) fall within this run (start 04:24:58.190,
10.439s duration) and match its named PNG-save passes; timestamp evidence:
`087783de-2e77-4672-a54a-2ea12fa040b0`.

The locked hint and purchase labels were readable. Archer captures showed both
enemy rows (100/100 and 40/40), then both at zero with 30 gold and the +30 victory
message. Scaled replay showed fresh enemy HP and retained 30 gold. The narrow
bottom capture showed readable purchases and a fully visible focused restart;
the Border capture showed the focused selector, enemy HP 72/72 and retained
30 gold. The warning wrapped fully onto two readable lines, including the
unsaved-changes loss warning. No overlapping labels or horizontal text clipping
was observed. Scrolled captures omit content above/below the viewport; the warning
capture does not show restart. The run separately passed focus-follow scrolling
and keyboard return assertions; screenshots do not establish physical input.

Only this pending scenario ran; no completed checks were rerun and no code changed.
**Physical manual acceptance remains PENDING; the release task remains open.**

### Automatic minimize diagnosis — 9 September 2026 (UTC)

Only the campaign `--focus-only` graphical reproducer was run for this investigation;
no manual interaction or wider-suite runs were requested. The original full failure
log (`8dee68f8-1ab4-441c-8a99-c2b1be53aad0`) contained only a combined suspension
failure. Temporary harness-only observations then recorded real application/window
focus events, Godot state, battle identity and monotonic time. A bounded Python
parent queried the game's HWND with Windows `IsIconic` and `GetForegroundWindow`;
it did not change native state or inject notifications.

The detailed run (`df33c6b4-b990-4289-955b-a26e81e1be4a`, 2.372s, exit 1;
12-second child / 20-second caller bounds) showed:

- Windows really minimized the window: `IsIconic=true`, foreground HWND not the game.
  Both Godot mode getters agreed on minimized mode (`1`).
- Application focus-out (`2017`) set production `suspended=true`; 4.533ms later,
  focus-in (`2016`) set it back to false while still minimized. Window focus-in
  signals followed; both Godot focus getters remained true.
- The existing nominal 0.2-second timer gate was reached about 71ms after the mode
  setter returned in this run. Its failure was recorded **before** an additional
  1.2-second, monotonic, observation-only interval; extra observation could not pass
  the failed check. State did not recover: the same ongoing battle advanced from
  round 0 to round 1 while Windows still reported minimized. This is not merely a
  short wait or a replaced/terminal battle.
- That diagnostic run reported 5 checks / 2 failures (the original assertion and
  final incomplete gate). Temporary traces, observers and extra waits were removed.
  Only explicit state values in the existing failure message were retained.

The final ordinary reproducer (`9f3c08d3-4957-42c2-85ac-3c095de203b8`) exited 1
in 1.151s under a 12-second bound: 4 checks / 1 failure, `mode=1 focus=true
suspended=false processing=true phase=0 expected_phase=0 same_battle=true result=0`.
**The unattended gate remains failed; no fix or graphical pass is claimed.**

Official [Window documentation](https://docs.godotengine.org/en/stable/classes/class_window.html)
and the pinned release's [Window](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Window.xml)
and [DisplayServer](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/DisplayServer.xml)
API definitions confirm the native mode/focus getters and HWND access.
[MainLoop documentation](https://docs.godotengine.org/en/stable/classes/class_mainloop.html#constants)
confirms desktop focus notifications; pause/resume notifications are Android/iOS-specific.
The production handler responds correctly to the events delivered, but the unexpected
focus-in resumes gameplay while the window is minimized.

The pinned [Windows backend](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/display_server_windows.cpp#L2787-L2799)
calls `ShowWindow(SW_MINIMIZE)`, then `_update_window_style`. That helper's
[`SetWindowPos` call](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/display_server_windows.cpp#L2680)
omits `SWP_NOACTIVATE` for ordinary minimized windows.
[Microsoft documents](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
that omission as activating the window. This source path matches the observed
focus-out/focus-in sequence inside the minimize setter.

**Historical engine fix proposal, not applied (application-layer follow-up below):** include minimized windows in
that backend call's `SWP_NOACTIVATE` condition (`wd.minimized || wd.no_focus ||
wd.is_popup`). Validate it with this unchanged focus-only gate against a corrected
engine before rerunning wider scenarios. A longer harness wait would not repair the
persistent focus state; guarding production resume alone would still fail the
required native-focus assertion. No engine binary, production handler, test condition,
manual requirement or existing watchdog/battle bound was changed.

### Application-layer suspension fix — 9 September 2026 (UTC)

Campaign presentation now retains independent focus-loss and application-pause
reasons, combining them with the current minimized window mode. Focus-in clears
only focus loss; application-resume clears only application pause. Gameplay resumes
only after every reason clears. The first resumed frame still excludes the gap,
preserves the partial round, and repeated resume events no longer discard extra
foreground frames. Disabled controls and direct-handler guards use the same state.
A scene-tree frame signal observes minimize/restore even at non-processing idle
checkpoints; direct controls and clock entry points also sample mode before acting.

Confirmed against the pinned official source: [`Window::get_mode`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/main/window.cpp#L547-L552)
queries DisplayServer for its native window. The [headless backend](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/display/display_server_headless.h#L122-L123)
always returns minimized despite having no window, so only that dummy native reason
is excluded in headless mode. Focus and pause handling remain active. New regression
fixtures replace only the OS mode read, exercising overlapping focus/pause/minimize
orders, both release orders, idle checkpoints, active defense, direct controls,
exact fractional timing and duplicate resumes. Existing assertions were retained.

Actual verification using the pinned executable:

| Check | Result | Exit / duration | Caller bound | Evidence |
|---|---|---|---|---|
| Import | No script/parse errors | 0 / 4.991s | 35s | `bc99c223-2e84-43f4-84cf-a932f5bcbd14` |
| Normal headless | 2515 checks / 0 failures | 0 / 2.579s | 35s | `2b4f6047-2af1-4e79-ae47-403cd8b6cb98` |
| Forced headless | 2516 checks / exactly one intentional failure | 1 / 2.697s | 35s | `7665203c-29b9-4b12-a292-62b7b1f44322` |
| Normal headless rerun | 2515 checks / 0 failures | 0 / 2.675s | 35s | `d4e01f99-4a13-4f40-9ff9-aa3596102223` |
| Unattended graphical `--focus-only` | Incomplete: 4 checks / 1 failure | 1 / 1.243s | 12s | `1f584b93-ab28-4da4-a0fd-70eb9768ff5e` |

Full-log audit `3271cf99-7bbc-4baf-8c6a-48d190461417` confirms complete headless
summaries, 162 balance rows per test run, no script/parse errors and only the two
existing `Exponent too high` warnings. An initial development run failed because of
the dummy headless minimized mode; the source-backed exclusion above resolved it
without changing existing assertions.

**Remaining native failure is separate:** the graphical log now reports `mode=1
focus=true suspended=true processing=true phase=0 expected_phase=0 same_battle=true
result=0`. Application suspension remains asserted despite erroneous native focus,
but the unchanged `not root.has_focus()` requirement still fails. The run therefore
does not reach its frozen-interval/restore assertions and is not a graphical pass.
Regression tests cover application freeze/restore logic, not physical OS behavior.
No engine modification, manual run, weakened native assertion, combat/balance change,
commit or push was made. Full manual graphical gates remain pending.

### Focus-only result separation — 9 September 2026 (UTC)

Only unattended `--focus-only` now records native-focus failure without immediately
aborting otherwise safe gameplay observations. Minimized mode, suspension, expected
active phase, battle identity and enabled processing remain mandatory; losing any
of them aborts the gate. Frozen-state and per-frame native-focus checks remain in
place. Native-focus failure is retained in the final count and nonzero exit.
Manual runs and full campaign/defense runs retain strict native-focus aborts; no
physical requirement, continuous foreground check, timing bound or engine changed.

Actual pinned-engine run `9fcc7094-dad3-4b12-b219-53d89392e9e0` completed in
2.553s under a 12-second caller bound: **9 graphical checks, 1 failure, exit 1**.

- **Native focus: FAIL** — the minimized window still reports focused.
- **Gameplay safety/frozen state: PASS** — the same ongoing battle remains suspended
  with processing enabled; rounds, accumulated time, gate health, gold and gate level
  stay unchanged throughout the existing 1.2-second interval.
- **Restore: PASS** — focused, unminimized and resumed; same active battle, no catch-up round.
- **Continuous foreground outside the suspension interval: PASS.**

Import (`2dd3780e-c4a5-4b57-8cd8-5a5123e331e5`) exited 0 in 4.300s;
headless tests (`15c773a2-956b-4ef0-adbb-0385a8826cc2`) reported 2515 checks /
0 failures, exit 0 in 2.779s. Both used 35-second caller bounds. These separate
native gameplay passes do not make the overall graphical gate pass or replace the
pending manual scenarios. No manual interaction was requested.

### Native Windows driver prototype — 9 September 2026 (UTC)

`python tests/windows_campaign_driver.py` runs exactly one unattended focus-only
probe with the pinned Standard engine. The prototype launches the underlying
`Godot_v4.7.2-stable_win64.exe` directly, rather than its console forwarder, so its
process handle/PID owns both the window and the cleanup target. The new
`--native-window-driver` smoke mode reuses the manual route's observed-minimization
wait without its human Start/close prompts. Initially restricted to unattended focus-only,
it now also supports explicit full-scenario selection as documented below.
Existing assertions, the frozen interval, focus audits and resume deadline remain.

Verified [ShowWindowAsync](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindowasync)
with [SW_MINIMIZE / SW_RESTORE](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindow)
issues native minimize/restore, not Godot mode setters. Before every command,
[GetWindowThreadProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowthreadprocessid)
must match the live launched PID; the HWND cannot change. No broadcast input,
foreground stealing, lifecycle injection or engine patch is used.
`IsIconic` and `GetForegroundWindow` independently observe minimized/restored state.
A targeted `WM_CLOSE` follows results and preserves the smoke's recorded exit code.
The driver's 12-second overall deadline and `finally` cleanup kill/reap only its own
child when necessary, then join the output reader. Invoke the Python driver, not the
internal handshake flag directly. No dependency installation is required.

**Single actual run: 9 graphical checks / 0 failures, child and driver exits 0**, in
2.666s under a 20-second caller bound (`0e388df1-7b69-4a86-9f45-1184f7046765`).
Native focus loss, same-active-battle frozen state, focused/unminimized restore,
no catch-up and continuous foreground checks all passed. Windows independently
confirmed minimized/not-foreground and restored/foreground states. Cleanup reported
child reaped (exit 0) and reader joined. No retry or wider suite was run.

**This is automated evidence, not the required physical manual gate.** Full campaign
and defense were unverified at the initial prototype checkpoint; later evidence follows.
Physical scenarios remain pending. Ordinary Godot-setter runs retain their known
native-focus failure. No assertion was relaxed.

### Full native-driver scenarios — 9 September 2026 (UTC)

Explicit, fixed scenario selection (no arbitrary executable, window or command input):

```sh
python tests/windows_campaign_driver.py focus-only
python tests/windows_campaign_driver.py campaign
python tests/windows_campaign_driver.py defense
python tests/windows_campaign_driver.py dynasty
```

Omitting the scenario still selects focus-only (12-second driver deadline; use a
20-second caller bound). Campaign, defense and dynasty each have a 65-second driver
deadline; use a 75-second caller bound to
include cleanup. The smoke's 60-second measured watchdog, 15-second battle bounds,
strict full-scenario focus gate, all gameplay assertions and PID/HWND-scoped native
actions remain intact. Driver mode cannot be combined with physical `--manual-focus`.

| Actual run | Complete summary | Child / driver exit | Duration | Evidence |
|---|---|---|---|---|
| Import (35-second bound) | No script/parse errors | 0 | 5.055s | `7fb3e07e-5f63-4123-a240-045771f3cabe` |
| Full campaign | 52 graphical checks / 0 failures | 0 / 0 | 30.647s | `e50cc0ed-040a-4f56-879c-43429fab2430` |
| Full defense | 59 graphical checks / 0 failures | 0 / 0 | 45.631s | `b698fdc3-a273-4153-a9b8-da3ac9225af9` |

The initial campaign attempt exited 1 in 7.171s
(`5e014266-5471-4ca0-9979-031fde2440c6`) after purchases, before the next battle
settlement. The user confirmed accidental window interference and explicitly requested
a fresh launch. It is retained as an incomplete attempt, not discarded as a pass;
the complete campaign rerun above used unchanged assertions.

**No later checks were unreached in either completed run.** Both passed native focus
loss, same-active-battle freezing/restoration and continuous foreground checks.
Defense additionally reached real victory after restore, cleared queued farming,
retained the surviving gate without reward, remained secured/idle, disabled all four
navigation controls and saved the secured capture. Both drivers independently
confirmed Windows minimized/not-foreground and restored/foreground state, then
reported child reaped and output reader joined.

All **14 freshly captured PNGs** in ignored `.gg/screenshots/campaign/` were opened
and inspected: `initial`, `archer`, `farm`, `stronghold`, `conquest`, `small-scrolled`,
`small-checkpoint`, `defense-ready`, `small-defense-controls`, `defense-start`,
`defense-damaged`, `defense-recovery`, `defense-retry`, and `campaign-secured`.
Readable labels, wrapped recovery/queue text, expected enabled/disabled controls,
visible focus outlines and working narrow-window scrolling were observed. Defense
captures show gate 80/80 initially, 46/80 after damage despite a level-three purchase,
200/200 on fresh retry, and 94/200 at secured victory with 40 gold and +0 reward.
Scroll-viewport cropping is expected; no overlapping labels or new visual defect was
observed. Native PNG inspection is complete for these automated runs.

**The separate physical manual gate remains PENDING.** No human interaction was
requested, engine modified, assertion weakened, or broader automation framework added.

**Historical conquest-only supervised graphical verification PASSED; automatic minimization remains a separate unresolved failure.**

Earlier complete run (2026-09-08, `--manual-focus`): **52 graphical checks,
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
# Separate bounded defense scenario, with the same supervision requirements:
& $GODOT --path . --script tests/campaign_scene_smoke.gd -- --manual-focus --defense
```

Keep the window focused and unminimized except during the explicit suspension test.
Manual mode first displays **START WHEN READY**, without a countdown. After
starting, minimize only when its title says **MINIMIZE**; the driver waits for
that click without a countdown, then restores automatically. Minimize promptly:
if the original battle ends or is replaced before the click, the native gate is
incomplete and the entire affected scenario must be rerun. The window stays
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

## Historical model-only Counterattack verification — 8 September 2026

Campaign now exposes `start_defense()` only at `CONQUEST_CLEARED` with Stronghold
cleared, including checkpoints returned to from ordinary farming. It never starts
automatically, and generic restart cannot enter or abandon defense. At this model-only
verification point neither playable scene had defense controls; the campaign scene
still had conquest-only wording. The later presentation implementation is documented above.

Counterattack is encounter ID **4**, outside conquest stages **0 → 1 → 3** and
locked in ordinary Economy. Its fresh shield/foot/horse enemies have **180/80/80 HP**
and **12/10/12 damage**. All living enemies target living player shield infantry
first, regardless of role; without it they attack only the gate. Damage remains
simultaneous, with no same-round shield overkill spilling into the gate. Surviving
archers keep fighting. Gate destruction beats enemy elimination; positive-gate
victory beats the round-60 timeout. Army elimination alone is not defensive defeat.
Combat records army, gate and timeout defeat reasons without changing result IDs.

Campaign owns gate levels **1–3**, health **80/140/200**, and upgrades costing
**20 then 40 gold** via `gate_purchase_cost()` / `purchase_gate()`. Purchases change
ownership only; each explicit assault takes fresh full-health troop and gate
snapshots, clean commander input and round zero. No model clock is introduced.

Accepted defense settlement pays zero. Defeat retains gold, purchases and all
clearances, then farms the latest valid queued ordinary stage or defaults to Archer.
Frontier must finish that farm before returning to the ready checkpoint; retry then
requires another explicit start. Victory overrides queued farming, retains the
terminal battle and enters `CAMPAIGN_SECURED`. Navigation, start and restart are
inert there; existing purchases remain ownership operations. Stronghold still pays
30 only once per controller at that historical checkpoint; the delivered dynasty slice
now pays it once per run, including the successor. All outcomes reuse inherited once-only settlement.

**Historical model-only verification**, pinned `4.7.2.stable.official.ed1daf0bf`:

| Gate | Checks / failures | Exit |
|---|---|---|
| Headless editor import | Complete, no script/parse errors | 0 |
| Headless normal / forced / normal | 1361/0 · 1362/1 · 1361/0 | 0 / 1 / 0 |
| Default graphical | 105 / 0 | 0 |
| Archer progression graphical | 35 / 0 | 0 |
| Fortified graphical | 37 / 0 | 0 |
| Supervised campaign `--manual-focus` | 52 / 0 | 0 |

Each headless run retained all **162 balance rows**; the forced run had exactly
one intentional failure. Full logs contained no script/parse errors. Existing
excessive-exponent negative save tests still emit their two expected warnings.
Headless and ordinary graphical commands used 35-second caller bounds; graphical
runs took approximately **20.0 / 10.3 / 12.3 seconds**, without deadline changes.
The interactive campaign process completed in about **5.2 minutes including human
readiness and result viewing**; its unchanged internal battle/watchdog bounds and
physical minimize/freeze/restore assertions passed. These runs establish unchanged
playable conquest/farming, not playable defense or independent native focus telemetry.

Two fully purchased passive conquest-plus-defense sequences matched complete
snapshots: Counterattack won in **11 rounds**, gate **94/200**, surviving player HP
**0/64/100**, and **zero defense gold**. These are observed outcomes, not a new
balance target. Coverage adds defensive targeting, outcome precedence, terminal
inertness, gate purchases, retry snapshots, isolation, settlement guards and security.

Run provenance (local execution IDs): import `23d79178-e180-47ce-9563-4cff93098a8b`;
headless `cf43b7a7-0320-492a-b198-b6d32b20b6ab`,
`b91758e8-14e0-4ded-9914-b6f9102013a6`, `ee58de6e-a451-448f-af5e-0cee695ce495`;
graphical `5b6a415e-f2a1-4e04-bee4-34276ad15bd4`,
`e0a74a47-b33d-459e-ad5b-cfd089dd9268`, `1e63a333-a7a7-4dc7-82b9-969020b427c1`;
campaign `f1a2fbfd-bdf2-44e8-9d9d-2b3af5b9d5cb`. Logs and captures remain ignored.

Defense, gate ownership and security are **in-memory only**. No campaign save,
reload protection, dynasty/reset, doctrine, UI, new dependencies or export was added
in that model-only step; the later campaign UI work is described above.
The separate automatic-minimize issue remains unresolved; human persistence remains
**DEFERRED**, not passed by these runs. Earlier release-gate history below is retained.
External guard-first zero-health code informed eligibility only; comparable GDScript
defense architecture remains unverified, and executable local tests establish behavior.

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

The default game has no automatic encounter advancement or gate/defense controls.
The separate session-local campaign exposes gate upgrades, defense and one confirmed
dynasty reset through its native UI; campaign persistence, final art and Android tooling
remain unimplemented. Border Skirmish, Archer Position and
Fortified Position repeat by manual selection; both older fixtures are unchanged.
Viewport-injected input is **not physical mouse/touch verification**. Suspension tests exercise lifecycle notifications,
not a physical Android device or OS sleep. No mobile export, sustained device
performance or cinematic-art feasibility claim is made. Those gates remain
separate, later milestones under the approved plan.

Original design documents remain unchanged; this bounded approved build
supersedes their older technology-deferral wording only for this encounter.
Initial setup did not create commits or change Git identity.
