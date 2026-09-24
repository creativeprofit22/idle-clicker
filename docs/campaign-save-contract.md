# Campaign save contract — v1, with v2 (Legacy), v3 (Threat), v4 (away reward), v5 (Veteran Cadre) and v6 (defense loss cause) amendments

The current file format is **v6**; see "v6 amendment (defense loss cause)" at the end, which builds on
"v5 amendment (Veteran Cadre)", "v4 amendment (away reward)", "v3 amendment (Threat)" and "v2 amendment (Legacy)". The earlier sections are kept as history and still govern every rule
the amendments do not change.

**Status: APPROVED 23 September 2026 — implemented.** In-memory state capture, validation
and restoration exist in `src/campaign_state.gd`; isolated storage and D11 recovery exist in
`src/campaign_save.gd`; `src/campaign_prototype.gd` loads `user://campaign.json` at launch and
wires the D6 triggers and D7/D11 status feedback. Evidence lives in the README verification
sections and tests, not in this document. Saved-loop acceptance (README checklist G4/G5) was
recorded as passed on 23 September 2026 using window-driven input, which the user accepted;
no person clicked those two gates.

## Delivered versus candidate

**Before this contract (historical):** the campaign scene was session-only; closing it lost all
campaign state, including dynasty 2 and Inherited Drill. It now autosaves as decided below. Main-game Save-v1 (`user://progress.json`, `{version:1, gold, levels}`,
owned by `src/progress_save.gd`) is never read or written by the campaign scene.

**Candidate (this document):** cross-launch campaign persistence. The provisional save/load and
reset-persistence text in `docs/first-playable.md` is **not** a requirement; only decisions
recorded as approved below become requirements.

## State inventory

Owners: `src/economy.gd` (base model) → `src/campaign.gd` (campaign model); `src/combat.gd`
(battle); `src/campaign_prototype.gd` (scene adapter).

Classes: **Saved** = written to the file; **Derived** = recomputed on load from saved fields and
authored data; **Transient** = never saved, reinitialised on load.

| Field | Owner | Class | Rule |
|---|---|---|---|
| `gold` | Economy | Saved | integer 0..9007199254740991 (Save-v1 bound) |
| `levels[3]` | Economy | Saved | owned troop levels, each 1..3 |
| `gate_level` | Campaign | Saved | owned gate level 1..3 |
| `dynasty` | Campaign | Saved | v1: 1 or 2. v2: 1..9007199254740991 |
| `inherited_drill`, `reset_used` | Campaign | Derived (v1 only) | v1: both must equal `dynasty == 2`. Removed in v2 |
| `legacy`, `drill_rank` | Campaign | Saved (v2) | Legacy balance and Drill rank 0..3; exact ledger (see v2 amendment) |
| `_battle_drill_rank` | Campaign | Saved (v2, as `battle.snapshot_drill_rank`) | rank captured when the battle was created; 0..`drill_rank` |
| `border_cleared`, `archer_cleared`, `stronghold_cleared` | Campaign | Saved | prefix-monotone (a later flag implies earlier ones) |
| `phase` | Campaign | Saved | RUNNING, CONQUEST_CLEARED, DEFENDING, CAMPAIGN_SECURED |
| `mode` | Campaign | Saved | ADVANCE or FARM |
| `farm_encounter` | Campaign | Saved | −1 or a cleared ordinary stage; ≠ −1 exactly when mode is FARM |
| `pending_navigation`, `pending_farm` | Campaign | Saved | queued request; `pending_farm` ≠ −1 only with navigation FARM, and must be a cleared ordinary stage |
| `current_encounter` | Economy | Saved | campaign set {0 Border, 1 Archer, 3 Stronghold, 4 Counterattack}; 2 Fortified is rejected |
| `_settled` | Economy | Saved | must equal `battle.result != ONGOING` |
| `_battle_reward` | Economy | Derived | `encounter_reward(current_encounter)` |
| Player squad snapshot (max health, damage) | Combat | Saved as `battle.snapshot_levels[3]` | each 1..owned level; stats re-derived from snapshot levels plus drill; titles/roles from `Data.players()` order |
| Enemy squads' max health, damage, titles | Combat | Derived | `Data.enemies(current_encounter)` |
| Player and enemy current health | Combat | Saved | each 0..derived max |
| `gate_max_health` | Combat | Saved as `battle.snapshot_gate_level` | defense only; 80 + 60(n−1); may be below owned `gate_level` after a mid-assault purchase |
| `gate_health` | Combat | Saved | defense only; 0..snapshot max |
| `is_defense` | Combat | Derived | `current_encounter == COUNTERATTACK` |
| `rounds` | Combat | Saved | 0..60; ONGOING ⇒ < 60 |
| `result`, `defeat_reason` | Combat | Saved | ONGOING or VICTORY ⇒ reason NONE; conquest DEFEAT ⇒ ARMY_DEFEAT or TIMEOUT; defense DEFEAT ⇒ GATE_DESTROYED or TIMEOUT; TIMEOUT ⇒ `rounds` == 60 |
| `commander_damage` | Combat | Derived | from snapshot starting damage |
| `commander_queued` | Combat | Transient, must be `false` to save | the campaign has no commander control; a queued strike makes state unsavable rather than silently dropped. No control is added. |
| `elapsed_usec` | Scene | Saved as `round_progress_usec` | 0..ROUND_USEC−1; 0 unless phase RUNNING/DEFENDING with an ongoing battle |
| `last_frame_usec`, `suspended`, `focus_lost`, `application_paused`, `skip_resume_frame` | Scene | Transient | reinitialised; the first frame after load is excluded from timing |
| `dynasty_preview_open` | Scene | Transient | load always starts with the preview closed |
| `%LastResult` text | Scene | Transient | after load shows a neutral "Resumed saved campaign" line |
| `battle` object identity | Model | Rebuilt | restore installs a fresh `Combat` as `campaign.battle` so identity-based `settle()` keeps once-only semantics |

## Decisions

**D1 Mid-battle resume.** Exact resume: snapshot, current health, rounds, gate health and
sub-round progress restore. A damaged battle is never recreated at full health. No absence
progress: load resets the frame clock, excludes the first frame and awards nothing for wall time.

**D2 Purchases after snapshot.** Owned levels save immediately. The active battle keeps its
snapshot levels; a purchase affects only the next created battle (matches delivered behaviour).

**D3 Defeat and farming recovery.** The routed state after settlement is saved (the farm battle
has already begun). Queued navigation persists and applies at the next settlement as today.

**D4 Checkpoints.** CONQUEST_CLEARED (defense-ready) and CAMPAIGN_SECURED (reset-ready / slice
complete) restore as checkpoints with their retained settled battle. No timing runs; Start
Defense stays explicit; nothing auto-starts on load.
*Superseded in v2 — see 'v2 amendment (Legacy)'.* CAMPAIGN_SECURED is no longer a slice end;
it credits Legacy and can always found another dynasty.

**D5 Reset preview, cancel, confirm, successor.** The preview is never saved; cancel writes
nothing. Confirm is one complete transition (dynasty 2, drill, reset used, zeroed run, fresh
Border) saved as one file. A dynasty-2 secured save restores as "Slice complete" with no further
reset. Last-result text is not persisted.
*Superseded in v2 — see 'v2 amendment (Legacy)'.* Resets are repeatable; Legacy and Drill rank
are kept, and the secured status shows the Legacy earned instead of "Slice complete".

**D6 Save triggers (autosave, no new controls).** Save after every accepted mutation: troop or
gate purchase, navigation request, Start Defense, each settlement (reward, clearance and routing
in one write), dynasty confirm. Also a best-effort save on suspension (focus loss, application
pause, window minimize) and on window close request, capturing mid-round progress. No per-round save.
*Clarified 23 September 2026:* window minimize was added to the suspension list to align this
text with the delivered suspension behavior (minimize already suspends and saves); it is a
correction of the text, not a new decision.
*Superseded in v2 — see 'v2 amendment (Legacy)'.* v2 adds a successful Train Drill purchase to
the trigger list.

**D7 Acknowledgement and failure feedback.** The in-memory transition applies first, then the
save. A status label shows "Saved" only after the staged file re-reads identically and is
committed. On failure it shows "Progress not saved — will retry", keeps in-memory state,
preserves the last valid file and retries the full current state at the next trigger. No retry
button (that would be a new control).

**D8 Crash rollback bound.** A crash loses at most the changes since the last acknowledged save.
In-battle rounds since the last trigger replay deterministically from the saved point. An
unacknowledged settlement, purchase or reset is simply not applied, so rewards and doctrine
cannot duplicate (reward and `_settled` share one write).

**Not claimed:** power-loss or OS-crash durability (Godot `flush` is not an fsync), multi-instance
safety, tamper resistance.

**D9 Storage.** Separate file `user://campaign.json` with `.tmp` and `.bak` siblings. The campaign
never reads or writes `user://progress.json*`. Reuse Save-v1's algorithm: bounded read
(≤ 4096 bytes), strict JSON, exact-integer check, stage → verify re-read → rotate primary to
`.bak` → move stage to primary; restore the backup on a failed commit. Implement as its own
module; the implementation phase decides whether to extract shared helpers. No Save-v1
migration, import or overwrite.

**D10 Versioning and validation.** See schema below. Wrong or missing `format` = corrupt; any
other integer `version` = unsupported. Validation is structural only: it cannot prove a
hand-edited file was legitimately reached.

**D11 Invalid, unreadable and unsupported recovery.** Mirrors Save-v1:
- Missing primary, valid backup → load backup, show "Restored from backup".
- Both missing → fresh campaign; the first save creates the file.
- Corrupt or unsupported primary → fresh in-memory session with saving disabled, visible
  warning, file bytes preserved, no automatic backup bypass.
- Read I/O failure → same as corrupt for this launch; retry next launch.
- No "discard save" control is added, so a corrupt save has no in-game fix until one is approved.

## JSON schema v1

*Superseded in v2 — see 'v2 amendment (Legacy)'.* v2 writes `"version": 2` and adds `legacy`,
`drill_rank` and `battle.snapshot_drill_rank`; v1 files migrate on load.

Exact key sets at every level; extra or missing keys are corrupt. All numbers are exact integers.

```json
{
  "format": "idle-clicker-campaign",
  "version": 1,
  "gold": 0,
  "levels": [1, 1, 1],
  "gate_level": 1,
  "dynasty": 1,
  "cleared": [false, false, false],
  "phase": 0,
  "mode": 0,
  "farm_encounter": -1,
  "pending_navigation": 0,
  "pending_farm": -1,
  "current_encounter": 0,
  "settled": false,
  "round_progress_usec": 0,
  "battle": {
    "snapshot_levels": [1, 1, 1],
    "player_health": [0, 0, 0],
    "enemy_health": [0],
    "snapshot_gate_level": 0,
    "gate_health": 0,
    "rounds": 0,
    "result": 0,
    "defeat_reason": 0
  }
}
```

- `cleared` = [border, archer, stronghold]. Enums use the source integer values.
- `enemy_health` length equals `Data.enemies(current_encounter).size()`.
- `snapshot_gate_level` and `gate_health` are 0 for non-defense battles; for defense
  `snapshot_gate_level` is 1..`gate_level`.

### Cross-field validation

- RUNNING ⇒ ordinary encounter (0, 1, 3), battle ONGOING and `settled` false. (Settlement always
  begins a fresh battle or leaves RUNNING, so a settled battle under RUNNING would stall forever.)
- DEFENDING ⇒ Counterattack, battle ONGOING, stronghold cleared.
- CONQUEST_CLEARED ⇒ stronghold cleared, settled battle.
- CAMPAIGN_SECURED ⇒ settled Counterattack victory, gate health > 0, all cleared.
- Mode/farm/navigation consistency as in the inventory; dynasty trio agreement; snapshot levels ≤ owned.
  *Superseded in v2 — see 'v2 amendment (Legacy)'.* v2 uses the Legacy ledger instead of the
  dynasty trio.
- `settled` ⇔ result ≠ ONGOING; ONGOING ⇒ at least one enemy squad has health > 0; in
  non-defense battles at least one player squad has health > 0; in defense `gate_health` > 0.
  *Clarified 23 September 2026:* this wording now matches the `Combat.step_round()` terminal
  checks (a side is beaten only when every squad is dead, not just its shield squad); it is a
  correction of the text, not a new decision.

## Acceptance cases for implementation

1. **Round trips** for each checkpoint class: mid-round Border/Archer/Stronghold; farming with a
   queued frontier; DEFENDING with a damaged gate after a mid-assault gate purchase;
   CONQUEST_CLEARED; CAMPAIGN_SECURED in dynasty 1 and 2.
2. **Loaded versus uninterrupted:** under identical `advance_usec` input, identical health per
   round, rounds, gold, clearances, routing and dynasty.
3. **Interrupted writes** (existing seam style): stage open/write/flush failure, rotate failure,
   commit failure with backup restore → last valid save intact, no success reported.
4. **Corrupted files:** corrupt, oversize, non-JSON, fractional, extra-key, wrong-format and
   inconsistent-state files are rejected, bytes preserved, not overwritten; a future version is
   unsupported.
5. **Duplicate protection:** reload after settlement pays nothing again; reload an ongoing battle
   then settle pays once; reload after confirm cannot confirm again; a crash before acknowledging
   confirm grants exactly one doctrine.
6. **Cross-launch doctrine:** a dynasty-2 relaunch keeps 2× damage (Border won in 2 rounds); a
   secured successor shows no reset.
7. **No absence progress:** save, advance wall clock before load; the first loaded frame adds nothing.
8. **Save-v1 isolation:** `progress.json` bytes unchanged across all campaign operations.

All existing import, headless, forced-failure, graphical, Windows-driver and CI gates remain in
force for the implementation; the physical manual gate remains pending.

## Approval record

Approved by the user on 23 September 2026, before any runtime implementation. All
recommended defaults were accepted:

- D1–D11 as written above, with no amendments.
- Save triggers (D6): after every accepted action plus best-effort on suspension and close.
- Corrupt/unsupported save (D11): fresh session, saving disabled, file untouched, no automatic backup bypass.
- Last-result text: not saved; shows "Resumed saved campaign" after load.
- Queued strike: state with a queued strike is refused as unsavable; no control is added.

Clarified 23 September 2026: the RUNNING, ONGOING and `result`/`defeat_reason` validation rules
were tightened to match states the game can actually reach. This implements already-approved
intent (D10 rejects inconsistent state) and is not a new decision.

Clarified 23 September 2026 (state restoration): validation also rejects combinations the
campaign routing cannot produce. Farm mode, a queued farm or a queued frontier only occur while
RUNNING (a queued farm may also exist while DEFENDING; a queued frontier only while farming); a
RUNNING battle is the farm target when farming, otherwise the frontier stage;
CONQUEST_CLEARED, DEFENDING and CAMPAIGN_SECURED are in Advance with no farm target and (except
DEFENDING's queued farm) no queued navigation; at round 0 every squad and the gate are at full
health; during defense only the shield squad can lose health. Same D10 intent; not a new decision.

This approval covers the contract only. Implementation, its tests and all existing
verification gates remain separate work.

## v2 amendment (Legacy)

**Status: user-approved 23 September 2026 and implemented** (`src/campaign.gd`,
`src/campaign_state.gd`, `src/campaign_prototype.gd`). This amendment replaces the one-time free
Inherited Drill with Legacy, Drill ranks and repeatable dynasty resets.

**Rules.** Securing a campaign (a settled defense victory) credits Legacy in the same transition,
so it is one save write and can't be paid twice: **10** in dynasty 1 and **3** in every later
dynasty. Drill ranks 1/2/3 cost **10/20/40** Legacy. Squad damage is multiplied by **1 + rank**
after level additions, and nothing else changes. Found a Dynasty is available at every secured
campaign. It increments `dynasty`, keeps `legacy` and `drill_rank`, and zeroes the run exactly as
in D5.

**New keys.** Top level: `legacy` (0..MAX_GOLD) and `drill_rank` (0..3). Battle:
`snapshot_drill_rank` (0..`drill_rank`), the rank captured when the battle was created. Player
stats are derived from `snapshot_levels` and `snapshot_drill_rank`, so a rank bought mid-battle
leaves the active battle unchanged and round-trips exactly. `version` is `2`, and the key sets
remain exact.

**JSON schema v2.** Key order matches `KEYS` / `BATTLE_KEYS` in `src/campaign_state.gd`.

```json
{
  "format": "idle-clicker-campaign",
  "version": 2,
  "gold": 0,
  "levels": [1, 1, 1],
  "gate_level": 1,
  "dynasty": 1,
  "legacy": 0,
  "drill_rank": 0,
  "cleared": [false, false, false],
  "phase": 0,
  "mode": 0,
  "farm_encounter": -1,
  "pending_navigation": 0,
  "pending_farm": -1,
  "current_encounter": 0,
  "settled": false,
  "round_progress_usec": 0,
  "battle": {
    "snapshot_levels": [1, 1, 1],
    "snapshot_drill_rank": 0,
    "player_health": [0, 0, 0],
    "enemy_health": [0],
    "snapshot_gate_level": 0,
    "gate_health": 0,
    "rounds": 0,
    "result": 0,
    "defeat_reason": 0
  }
}
```

**Ledger (D10 addition).** A file is corrupt unless
`legacy + spent(drill_rank) == earned(dynasty, phase == CAMPAIGN_SECURED)`, where
`earned(d, s) = (d > 1 ? 10 + 3·(d − 2) : 0) + (s ? (d == 1 ? 10 : 3) : 0)` and
`spent(r)` = the sum of the first `r` Drill costs. A hand-edited balance, rank or dynasty is
therefore rejected. `capture()` refuses (UNSAVABLE) a model that breaks the ledger.

**v1 migration.** A v1 file is parsed under the exact v1 key set and v1 rules (dynasty 1..2),
then mapped in memory:

- dynasty 1 → rank 0, with Legacy 10 if secured, else 0
- dynasty 2 → rank 1 (the old free doctrine counts as rank 1 bought with the first 10), with
  Legacy 3 if secured, else 0
- `snapshot_drill_rank` = rank

The file isn't rewritten on load; the next ordinary save writes v2. Any version other than 1 or 2
is UNSUPPORTED. *(Superseded by v3: the next save writes v3; versions other than 1, 2 or 3 are
unsupported.)*

**D5 change.** Confirm is repeatable, and the successor keeps Legacy and Drill rank. The preview
discloses what is kept and that the next secured campaign earns 3 Legacy. The secured status
shows the Legacy earned instead of "Slice complete". *(Superseded by v3: the preview shows the
chosen Threat's payout, 3 × (1 + Threat).)*

**D6 addition.** A successful **Train Drill** purchase is an accepted mutation and autosaves.
Rejected training (unaffordable, at max, suspended or preview open) writes nothing.

**v2 acceptance cases** (covered in `tests/run_tests.gd`, `tests/campaign_persistence_smoke.gd`
and `tests/campaign_scene_smoke.gd`):

1. Legacy is paid 10 then 3, once per secured campaign, and a restore can't pay it again.
2. Drill costs are 10/20/40, the multipliers are ×2/×3/×4, rank 3 is the maximum, and a
   rejected purchase changes nothing.
3. Repeat resets reach dynasty 3 and 4, keeping Legacy and rank.
4. Mid-battle training: the active battle keeps its snapshot rank across capture/restore, and the
   next battle uses the new rank.
5. A tampered Legacy, rank, dynasty or snapshot rank, or missing v2 keys, are corrupt; version 3
   is unsupported. *(Superseded by v3: version 3 is current; version 4 is unsupported.)*
6. v1 dynasty-1/2, running/secured files migrate exactly, and the next save writes v2.
   *(Superseded by v3: the next save writes v3.)*

## v3 amendment (Threat)

**Status: implemented 23 September 2026** (not committed at time of writing). Gives later
dynasties a goal and a choice: each new dynasty picks a Threat level that makes enemies stronger
and pays more Legacy.

**Rules.**
- Dynasty 1 is always Threat 0. When founding a dynasty, the preview picks a Threat from 0 up to
  `best_threat + 1` (capped at `THREAT_MAX` = 10). It defaults to 0 each time the preview opens;
  Lower/Raise Threat change only the preview and write nothing. Threat 0 is always available, so
  a player can never be locked out.
- Threat is fixed for the whole dynasty. Every enemy squad in every battle (conquest, farm and
  defense) gets `round_half_up(authored * (100 + 25 * threat) / 100)` for max health and damage.
  Player troops, gold rewards, costs and round timing are unchanged.
- Securing dynasty 1 still pays 10. Securing a later dynasty pays `3 * (1 + threat)` (3, 6, 9 …)
  and raises `best_threat` to at least this Threat.

**New keys.** Top level, after `drill_rank`: `threat` (0..10), `best_threat` (-1..10, -1 = never
secured) and `legacy_earned` (0..MAX_GOLD, total Legacy ever paid). `version` is `3`. Key order
matches `KEYS` in `src/campaign_state.gd`; the battle key set is unchanged from v2.

**Cross-field validation (v3).**
- Dynasty 1 has `threat` 0; `best_threat` is -1 unless dynasty 1 is secured; later dynasties
  have `best_threat >= 0`.
- `best_threat <= dynasty - 1` when secured, else `<= dynasty - 2`; a secured dynasty has
  `best_threat >= threat`; an unsecured one has `threat <= best_threat + 1`.
- `legacy_earned` is bounded, because Threat history is not stored: the lowest possible value has
  every later secure at Threat 0 except one at each Threat 1..best. The highest has the j-th
  later secure at Threat `min(j, best)`. Values outside that range are corrupt.
- The ledger is exact: `legacy + spent(drill_rank) == legacy_earned`.
- Stored enemy health is capped by the Threat-scaled max health.

Limitation: inside the allowed range, a hand edit that raises `legacy_earned` and `legacy`
together by a feasible amount is accepted, because there is no per-dynasty history to check it
against. v2's exact ledger could reject every such edit.

**v2 migration.** A v2 file is parsed under the exact v2 key set and v2 rules (including the
exact +10/+3 ledger), then gets `threat` 0, `best_threat` 0 if it has ever been secured (dynasty
> 1, or dynasty 1 secured), else -1, and `legacy_earned` set to the v2 ledger total. v1 files migrate
the same way after their v1 migration. Files are not rewritten on load; the next ordinary save
writes v3. Any version other than 1, 2 or 3 is unsupported. *(Superseded by v4: the next save
writes v4; versions other than 1–4 are unsupported.)*

**v3 acceptance cases** (covered in `tests/run_tests.gd`, tests `test_threat`,
`test_threat_state` and `test_campaign_scene_dynasty`):

1. Scaling rounds half up at +25% per level, applies to every encounter's enemies only, and
   survives restart, farming, defense and save/restore.
2. Payouts are 10 for dynasty 1, then 3/6/… by Threat; a secure raises the best Threat, and
   dropping back to Threat 0 never lowers it.
3. Choosing more than one above the best, or a negative Threat, is rejected with no change.
4. v3 round-trips exactly. Threat above the unlocked level, out-of-range or missing keys, an
   inconsistent best, earned outside the feasible range, an unbalanced ledger, or enemy health
   above the scaled max are all corrupt. Version 4 is unsupported. *(Superseded by v4: version 4
   is current; version 5 is unsupported.)*
5. v2 dynasty-1 running and dynasty-2 secured files migrate (Threat 0, best -1/0, earned 0/13),
   still reject a tampered v2 ledger, can then found at Threat 1, and the next save writes v3.
6. The preview defaults to Threat 0, clamps Raise/Lower, shows the payout, ignores input while
   suspended, and confirming founds the dynasty at the chosen Threat.

## v4 amendment (away reward)

Reopening the campaign pays capped gold for the time the app was closed, from territory already
secured. Nothing is simulated: no battle, round, round progress, boss, defense milestone, Legacy,
clearance or routing changes. Focus loss, minimizing or pausing inside a running session pays
nothing; the reward is computed only when a saved campaign is loaded at launch.

**Field.** v4 adds `saved_at`: the whole Unix second of the save, an integer in `0..2^53-1`
(same exact-integer rules as `gold`). `0` means unknown. Every successful save stamps the current
system time. The key set is the v3 set plus `saved_at`; missing, extra, negative, fractional,
too large or non-numeric values are corrupt. Version 5 or higher is unsupported. *(Superseded by v5:
version 5 is current; version 6 or higher is unsupported.)*

**Rule.** `away = now - saved_at` (0 when `saved_at` is 0 or the clock went backwards). The best
farmable cleared territory pays half a victory per minute: Archer Position (30 gold) if cleared,
else Border Skirmish (10 gold), else nothing. `gold = floor(min(away, 28800) × reward / 120)`, so an
absence pays at most 7 200 gold (Archer) or 2 400 gold (Border); the cap is 8 hours. Constants live
in `src/campaign.gd` (`AWAY_CAP_SECONDS`, `AWAY_MINUTES_PER_VICTORY`).

**Commit.** A non-zero reward is held as pending and saved immediately: every save adds the pending
amount to the snapshot's gold, so the gold and the new stamp always reach disk together (never one
without the other). The welcome-back line ("Away 2h 14m · +4020 gold from secured territory
(cap 8h)") appears only once a save commits it; the pending amount is then cleared. If a save does
not commit, the gold is removed from memory again and the file keeps its old stamp, so the reward is
never paid twice. While saving stays enabled (a transient failure) the scene shows "Away reward
waits for a successful save" and the next ordinary save (victory, purchase, navigation, focus loss,
pause, minimize or close) retries it. If saving becomes disabled (the file is preserved as invalid),
the pending reward is dropped and the scene shows "Away reward cannot be kept this session".

**Migration.** v1, v2 and v3 files are parsed under their own exact key sets and migrate with
`saved_at` 0, so they pay no away reward. Files are not rewritten on load; the next save writes v4.
*(Superseded by v5: the next save writes v5.)*

**Known limits.** Moving the system clock forward can collect up to 8 hours per relaunch; this is
accepted for an offline single-player game. A dynasty's whole gold sink is about 240 gold, so any
multi-hour absence maxes every upgrade; balancing that is a separate decision.

**v4 acceptance cases** (covered in `tests/run_tests.gd`, tests `test_away_reward_rule`,
`test_away_reward_format` and `test_away_reward_scene`):

1. Nothing cleared pays 0; Border only for 60 s pays 5; Archer for 60 s pays 15; 8 h and 30 h
   both pay 7 200; zero or negative time pays 0.
2. v4 round-trips `saved_at` exactly; missing, negative, fractional, string or oversize values are
   corrupt, a v3 file carrying `saved_at` is corrupt, and version 5 is unsupported.
3. v1, v2 and v3 files migrate with `saved_at` 0; a v3 file loads without being rewritten and the
   next save writes v4 with the store's clock.
4. A campaign saved an hour earlier with Archer cleared relaunches with +900 gold, the welcome-back
   line and every other field unchanged, and is re-saved with the new stamp; relaunching at the
   same time, or with the clock moved backwards, pays nothing.
5. If the reward save fails, the gold is reverted and the file stays byte-identical.
6. After a transient reward-save failure, the next ordinary save commits +900 gold with the new
   stamp in memory and on disk, later saves add nothing, and a relaunch at the same time pays
   nothing more. If saving becomes disabled instead, the pending reward is dropped with the
   "cannot be kept this session" message.

## v5 amendment (Veteran Cadre)

Approved 24 September 2026. Veteran Cadre is a permanent, one-rank Legacy upgrade costing
**50 Legacy** (`Campaign.VETERAN_CADRE_COST`). Every dynasty founded after purchase starts all three
troop types at level 2; the gate still starts at 1. The purchase changes only `legacy` and the flag.

**Field.** v5 adds `veteran_cadre`, a JSON boolean. The key set is the v4 set plus `veteran_cadre`;
a missing key or any non-boolean value (number, string, null) is corrupt. Version 6 or higher is
unsupported. *(Superseded by v6: version 7 or higher is unsupported.)*

**Ledger.** The exact Legacy ledger becomes
`legacy + drill_spent(drill_rank) + (50 if veteran_cadre else 0) == legacy_earned`, so a flag set
without the spend, or a spend without the flag, is corrupt. Troop levels stay validated as 1..3 with
no starting-level coupling: the dynasty that makes the purchase legitimately holds level-1 troops.

**Migration.** v1–v4 files are parsed under their own exact key sets and load with Veteran Cadre
unowned; a v4 file carrying `veteran_cadre` is corrupt. Files are not rewritten on load; the next
save writes v5. *(Superseded by v6: the next save writes v6.)*

**v5 acceptance cases** (covered in `tests/run_tests.gd`, tests `test_veteran_cadre`,
`test_veteran_cadre_state` and `test_campaign_scene_veteran_cadre`):

1. A ledger-valid owned state round-trips exactly and a relaunched owner founds its next dynasty at
   troop levels [2, 2, 2], gate 1.
2. Flag without spend, spend without flag, integer/string/null/missing flag, and a v4 file carrying
   the flag are corrupt; version 6 is unsupported.
3. v1–v4 files load unowned with their Legacy intact; a v4 file loads without being rewritten and
   the next save writes v5 with the flag.
4. The scene purchase saves immediately; suspended or preview-open purchases change nothing.

## v6 amendment (defense loss cause)

Approved 24 September 2026. When the Counterattack is lost, the campaign records why so the player
is told the cause and the upgrade that addresses it, including after relaunch. The cause is only a
hint: it changes no reward, level, clearance, routing or Legacy.

**Field.** v6 adds `last_defense_loss`, a JSON integer holding a `Combat.DefeatReason` value:
`0` (NONE), `2` (GATE_DESTROYED) or `3` (TIMEOUT). The key set is the v5 set plus
`last_defense_loss`. A missing key, a non-integer, a boolean, `1` (ARMY_DEFEAT, impossible in
defense) or any out-of-range value is corrupt. Version 7 or higher is unsupported.

**Lifecycle.** A lost defense sets the cause from the battle's own defeat reason (gate at zero is
decided before the round-60 timeout). `Start Defense` clears it; a victory can only follow that
start, so it records NONE. Founding a dynasty also resets it.

**Cross-field.** A non-NONE cause is corrupt unless all three stages are cleared and the phase is
RUNNING or CONQUEST_CLEARED (never DEFENDING or CAMPAIGN_SECURED).

**Migration.** v1–v5 files are parsed under their own exact key sets and load with NONE; a v5 file
carrying `last_defense_loss` is corrupt. Files are not rewritten on load; the next save writes v6.

**v6 acceptance cases** (covered in `tests/run_tests.gd`, tests `test_defense_loss_cause`,
`test_defense_loss_cause_state` and `test_campaign_scene_defense_loss_cause`):

1. Gate-broken and timeout losses record their cause; a gate at zero on the round the last enemy
   dies records the gate cause; a round-60 win records NONE; Start Defense clears the cause.
2. Gold, levels, gate level, clearances, queued farm and Legacy match a run without the field.
3. A state holding either cause round-trips exactly through save and restore.
4. Missing, boolean, string, float-fraction, ARMY_DEFEAT and out-of-range values, a v5 file carrying
   the key, and a non-NONE cause while defending, secured or before the stronghold is cleared are
   corrupt; version 7 is unsupported.
5. v1–v5 files load with NONE and are not rewritten on load; the next save writes v6.
6. The scene shows the cause and hint in the result and status text, and the status text again
   after relaunch.
