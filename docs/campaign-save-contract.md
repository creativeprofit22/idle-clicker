# Campaign save contract — v1

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
| `dynasty` | Campaign | Saved | 1 or 2 |
| `inherited_drill`, `reset_used` | Campaign | Derived | both must equal `dynasty == 2`; the model keeps three fields, the file keeps one |
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

**D5 Reset preview, cancel, confirm, successor.** The preview is never saved; cancel writes
nothing. Confirm is one complete transition (dynasty 2, drill, reset used, zeroed run, fresh
Border) saved as one file. A dynasty-2 secured save restores as "Slice complete" with no further
reset. Last-result text is not persisted.

**D6 Save triggers (autosave, no new controls).** Save after every accepted mutation: troop or
gate purchase, navigation request, Start Defense, each settlement (reward, clearance and routing
in one write), dynasty confirm. Also a best-effort save on suspension (focus loss, application
pause, window minimize) and on window close request, capturing mid-round progress. No per-round save.
*Clarified 23 September 2026:* window minimize was added to the suspension list to align this
text with the delivered suspension behavior (minimize already suspends and saves); it is a
correction of the text, not a new decision.

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
