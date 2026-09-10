# First playable: implemented prototype and future proposal

**Only the implemented-scope section below describes approved, delivered work.** The later first-playable rules, tables, formulas, and acceptance thresholds remain proposals unless explicitly identified as already implemented. Their presence does not approve another milestone or validate the complete proposed game loop.

The broader vision includes offline single-player play, pre-gunpowder historical armies, attack and defense, level-1 resets retaining selected benefits, and eventual Android support. Playable defense, gate upgrades and one session-only dynasty reset are delivered in the separate campaign. Full campaign saving, permanent doctrine and Android delivery remain deferred.

## Approved implemented scope — 10 September 2026

The project uses **Godot 4.7.2 Standard, GDScript, and native controls**. The current
[README](../README.md) is authoritative for launch commands, playable contracts,
verification evidence, and remaining release gates. Two separate playable scenes exist:

- **Default opening-battle game:** Border, Archer, and Fortified selection; ownership-based
  unlocks; automatic replay; commander input; next-battle purchases; two-enemy presentation
  and native scrolling. Manual encounter switching abandons an ongoing battle without
  payment. Save-v1 persists only gold and troop levels; launch starts fresh Border combat.
- **Separate campaign prototype:** `scenes/campaign_prototype.tscn` and
  `src/campaign_prototype.gd` connect the in-memory `src/campaign.gd` model to a native UI.
  Real-time automatic progression, deferred farm/frontier requests, purchases, scrolling,
  conquest preparation, explicit defense/recovery, secured idle and one confirmed dynasty
  reset are implemented. This session-only scene neither loads nor writes the default
  game's save. Closing/recreating it discards campaign progress and inherited doctrine.

The approved campaign prototype and its scene integration are implemented, not deferred.
It does not replace the default farming game or constitute acceptance of the broader
first-playable proposal. No further implementation milestone is approved here.

Campaign alone advances through the explicit order Border (ID 0), Archer (ID 1), then
Stronghold (ID 3), using clearance-based access. Archer pays **30 gold**, superseding the
original provisional 15-gold proposal without retuning the approved economy. Fortified
Position remains ID 2: two enemies, all troops level 2+ to unlock, and 54 gold per victory
in ordinary Economy. It is neither Stronghold nor a campaign frontier. Stronghold is a
separate three-enemy fixture and awards 30 gold once per run, including the successor run.

Campaign navigation retains only the latest valid request and waits for settlement.
Victory rewards and clearances precede navigation; Stronghold victory overrides queued
navigation and stops at `CONQUEST_CLEARED`. Otherwise queued navigation beats defeat
recovery; without a request, any defeat (including while farming) farms the highest
cleared ordinary stage, or retries Border in advance mode if none is cleared. A farm
victory repeats its selected stage. The controller's explicit restart abandons the battle
and clears navigation without paying; it cannot switch destinations or restart a checkpoint.
Farming after conquest clearance preserves it; retry frontier finishes that farm battle
and returns to the checkpoint without recreating or repaying Stronghold.

Settlement is synchronous and once-only in memory, not a durable transaction.
Campaign saving, live battle resume and crash/reload duplicate protection remain
deferred. Main-game Save-v1 does not save campaign, gate, security or doctrine state.

### Playable Counterattack and session-only dynasty

The native **Start Defense** control explicitly enters Counterattack from
`CONQUEST_CLEARED`, including farm-return checkpoints; defense never starts automatically.
Gate upgrades cost **20 then 40 gold**, cap at level 3 and snapshot **80/140/200 HP**
at the next assault. Mid-assault purchases never repair or change the active gate.
Counterattack (ID 4) remains outside conquest and unavailable in ordinary Economy.
Enemies target living shield infantry, then the gate; simultaneous attacks do not
spill on shield death. Gate zero defeats first, otherwise enemy elimination wins,
then unresolved round 60 times out. Army elimination alone is not defensive defeat.

Defense pays **0 gold**. Defeat retains ownership and clearances and enters the latest
queued ordinary farm (Archer by default). Frontier cannot abandon defense; retry needs
farm settlement, return to preparation and explicit Start Defense. Victory overrides
queued farming, retains the winning battle/gate and stops timing/navigation at
`CAMPAIGN_SECURED`. Affordable purchases remain ownership-only outside the reset preview.

Only first-dynasty **settled defensive victory with a surviving gate**, all clearances
and an unused reset enables **Found a Dynasty**. The native preview shows actual gold,
troop and gate levels and all losses. Cancel or Escape changes no gameplay state and
returns focus; preview-open purchase/navigation handlers are blocked. Confirmation
requires an open preview, fresh model eligibility and no suspension, and applies once.

**Confirm reset — start dynasty 2** loses all gold and territory/security, returns all
troop/gate levels to 1, clears battle progress, queued commands/navigation, farm selection
and fractional time, then starts fresh round-zero Border in Advance mode. Roster access
remains. **Inherited Drill** applies exactly **2× squad damage after level additions**;
health, enemies, gold rewards and one-second rounds are unchanged. The passive opening
takes two rounds rather than four. Commander snapshot strength derives from damage,
but the campaign UI has no commander control. Doctrine survives in-session farming,
purchases, defeat, recovery and defense; duplicates cannot restart or stack it.

Stronghold pays **30 gold once per run**, including dynasty 2. Securing the successor
grants no additional bonus/reset and displays **Slice complete — no further dynasty
reset.** Only one reset/bonus is available per session. Closing or recreating the
campaign discards the doctrine too; main-game saves are never loaded or changed.
Permanent doctrine, cross-launch retention, reset saving and full campaign persistence
are explicitly deferred, not delivered by this slice.

### Current verification — 10 September 2026

The native smoke's 200ms transition wait and 1.2s frozen interval now use monotonic
wall time rather than engine-delta timers. Duration assertions failed before the
repair; existing focus/frozen-state assertions, native actions and deadlines remain.
Final native **focus-only 11/0, campaign 54/0, defense 61/0 and dynasty 57/0** passed
with child/driver exits 0, complete observations and reaped-child/joined-reader cleanup.
Import passed; headless normal/forced/immediate normal passed **2753/0 · 2754/1 · 2753/0**,
exits **0/1/0**, exactly one intentional failure. Default graphical smoke passed **105/0**.
All 16 current campaign captures were opened, including the secured checkpoint,
narrow reset preview and fresh round-zero successor. README records log IDs and
retains an intermediate early-restoration failure whose external source is unconfirmed.
**Physical manual acceptance remains PENDING**, including reset preview/cancel/confirm;
automated passes do not waive it or claim release readiness.

### Historical verification — 10 September 2026

No checks were rerun for that documentation-only review. Step 6 recorded import exit 0;
headless normal/forced/immediate normal **2753/0 · 2754/1 · 2753/0**, exits **0/1/0**
(exactly one intentional failure); Save-v1 persistence **13/0 + 10/0 + 4/0**; and main
graphical **105/0 · 35/0 · 37/0**. Initial native focus-only/campaign passed **9/0 · 52/0**.
Initial defense **59/11** exposed click sampling before deferred scrolling settled.
After the shared two-frame click-helper repair, import passed and native defense
**59/0**, dynasty **55/0** passed with child/driver exits 0, complete native observations
and reaped-child/joined-reader cleanup. However, post-repair campaign was **incomplete,
47 checks / 1 failure**, child/driver exits 1, cleanup complete: minimized native focus
remained true after 44 interaction passes; freeze/restore checks were unreached. No
unchanged retry followed. Earlier dynasty **53/2** harness failures were repaired; an
unreadable exit-1 attempt remains unresolved despite later UTF-8-captured **55/0** passes.

Step-6 PNG inspection covered all 25 main-game and 14 campaign/defense captures, then
corrected final defense-retry/secured and dynasty captures. See README's dynasty
verification section for external log locations and retained failure history. No CI run
exists for HEAD `35d88d1`; historical successful run `34324612490` is another SHA, not
this dirty diff. **Verification is not all green; physical manual acceptance remains
PENDING**, including real reset preview/cancel/confirm interaction. Automated evidence
does not waive that gate. No export, Android or release acceptance is claimed.

## Future first-playable proposal — NOT APPROVED

Everything below describes the proposed larger loop, not an instruction to implement it.
Combat, conquest, playable defense/gates and the session-local reset overlap delivered
work above. **Permanent** doctrine, cross-launch reset retention and full-state campaign
persistence remain deferred. The save/load, durable reset and atomic-saving promises below
are proposals only and must not be attributed to Save-v1 or the session-only campaign.
Future work requires separate approval.

## The player's first run — provisional experience

The player begins at campaign level 1 with Roman-inspired shield infantry, Egyptian-inspired foot archers, and Steppe-inspired horse archers. Each squad starts at troop level 1. They represent frontline, ranged, and mobile roles, not successive replacements for the same purchase. All three fight together automatically. There is no deployment shop, formation editor, recruitment queue, or expedition/garrison split. Historical labels describe influences rather than claiming that this combined army existed historically.

The first skirmish is deliberately winnable without buying anything or tapping. Shield infantry takes the enemy's attacks while the other squads contribute damage. A commander tap adds a rate-limited strike, letting the player compare observing with helping immediately. The opening encounter is a brief proof of cause and effect, not the whole session. Victory earns gold and advances automatically to a second skirmish, which introduces enemy archers and lets the mobile squad's back-line targeting matter.

The player spends gold on troop levels while combat continues, but each battle retains the stats with which it started. Purchases affect the next encounter or retry, avoiding mid-fight maximum-health changes and making comparisons understandable. Cleared ordinary stages can be replayed for income. Doing nothing still produces automatic combat and farming rewards; upgrade purchases and deliberate frontier retries remain player decisions rather than automatic spending.

The stronghold at level 3 tests a full enemy composition. A premature defeat removes neither gold nor purchased levels. Instead, the army returns to farming a cleared ordinary stage. Once strengthened, it can retry the stronghold at full health. Stronghold victory unlocks defense and pauses for preparation; it does not launch an unexpected assault while the player is absent.

Defense uses the same army but a different objective. Enemy attacks threaten shield infantry first, then the gate if that squad falls. Surviving archers keep fighting while the gate buys time, so a gate upgrade creates an opportunity that does not exist on offense. A defensive loss returns the player to farming without requiring another stronghold victory. Defeating the assault with the gate intact secures the campaign.

The player can then choose Found a Dynasty. Its preview explains that gold, territory, troop levels, and gate upgrades will reset, while one permanent doctrine will be granted. Confirmation returns the campaign to level 1 with original troop levels but double squad damage. The identical opening enemy now falls faster under identical input, including no tapping. This single reset proves the intended payoff without adding a prestige shop or allowing repeated multiplier stacking.

## Roster, stats, and purchases — provisional

Each side has at most one squad of each of the same three types. Health belongs to an encounter, not a persistent count of individual recruits. Living squads deal full damage regardless of remaining health. There is no armor, randomness, critical hit, dodge, morale, charge meter, equipment, or siege system.

| Player squad | Role | Level-1 health | Level-1 damage per attack | Each purchased level adds |
| --- | --- | ---: | ---: | --- |
| Shield infantry | Frontline | 120 | 4 | 40 health and 2 damage |
| Foot archers | Ranged | 40 | 8 | 12 health and 4 damage |
| Horse archers | Mobile | 60 | 6 | 20 health and 3 damage |

All squads start at troop level 1 and cap at level 3. Level 2 costs 20 gold and level 3 costs 40 gold, independently for each squad: price is `20 × current level`. Stat additions apply before any dynasty multiplier. All three types remain available throughout; there are no recruit-unlock purchases.

The gate starts at level 1 with 80 health. Each additional gate level adds 60 health, with the same 20-gold and 40-gold prices and level-3 cap. It cannot attack and does not appear in conquest. A dynasty starts with 0 gold. Gold comes from completed victories, not individual kills or damage.

A purchase deducts its exact price and raises exactly one owned level. Insufficient funds and capped purchases leave state unchanged. There are no refunds, upkeep, selling, or healing costs. Ownership changes immediately and survives defeat or saving; combat stats change only at the next encounter start. Multiple purchases before then all apply. Removing roster selection is a deliberate scope limit: this slice tests roles and upgrade allocation, not interchangeable cultural units.

## Targeting, damage, and commander input — provisional

Combat uses one-second logical rounds of active play time. Automatic attacks first occur after one second. Every living squad attacks once each round. Identical starting state and accepted inputs produce identical results, independent of rendering frequency. The existing prototype implements foreground timing with integer-microsecond accumulation; this proposal does not select a replacement.

In conquest, shield infantry and foot archers target the first living opposing squad in this order: shield infantry, horse archers, foot archers. Horse archers instead prioritize foot archers, horse archers, then shield infantry. Both sides use these rules. There is only one squad per type, so no further tie-break is needed.

In defense, player targeting is unchanged, but **all enemy squads target living player shield infantry, otherwise the gate**. Enemy horse archers do not bypass that frontline during defense. This explicit assault rule creates gate pressure without extra enemy types or positional simulation. The cost is different enemy mobile behavior between phases; that difference must be understandable, not a hidden exception.

At a round boundary, choose targets from the living squads at round start, calculate squad attacks and any queued commander strike, then apply damage simultaneously. Health becomes `max(0, old health − incoming damage)`. A squad alive at round start still attacks if that round kills it. Overkill never spills to another target. Dead squads cannot attack or be targeted in later rounds and cannot revive within a fight.

The first tap during each round interval queues one strike for its ending boundary. Further taps in that interval do nothing and never accumulate. Strike damage is `max(1, floor(total starting player squad damage / 3))`; it includes purchased-level stats and the dynasty multiplier captured at encounter start. Casualties do not weaken the commander's strike during that encounter. It targets shield infantry, horse archers, then foot archers and joins the simultaneous damage batch. Pending input expires at encounter end. Taps outside combat have no effect.

## Victory, defeat, and recovery — provisional

Conquest victory requires all enemies dead and at least one player squad alive after the round. All player squads dead means defeat, including mutual elimination. Defensive victory requires all enemies dead and positive gate health. A destroyed gate means defeat even if the last enemy died that round. An unresolved encounter times out as defeat after round 60; damage-based outcomes are evaluated first, so a valid round-60 victory succeeds.

Every new encounter, replay, or retry begins at full health, with a fresh stat snapshot, zero elapsed rounds, and no queued strike. Defeat pays nothing and charges nothing. Owned troop levels, gate level, gold, and earlier clearances remain intact. Results identify army defeat, gate destruction, or timeout, allowing the player to understand what happened rather than infer it from a generic loss.

## Conquest, rewards, and encounter transitions — provisional

Enemies use the same three types with authored stats rather than player upgrade levels. A dash denotes an absent squad. These four definitions are the proposed campaign-loop content, not a list of all current fixtures. The separate main-game Fortified encounter is implemented but is not part of this campaign sequence.

| Encounter | Enemy shield health / damage | Enemy foot archers health / damage | Enemy horse archers health / damage | Victory reward |
| --- | --- | --- | --- | --- |
| Level 1: Border skirmish | 72 / 3 | — | — | 10 gold |
| Level 2: Archer position | 100 / 6 | 40 / 8 | — | 30 gold (approved reconciliation above) |
| Level 3: Stronghold | 160 / 8 | 60 / 8 | 60 / 6 | 30 gold, once per dynasty |
| Defense: Counterattack | 180 / 12 | 80 / 10 | 80 / 12 | Campaign secured; no gold |

Start level 1 in advance mode. Each ordinary first victory awards gold, records clearance, and starts the next conquest encounter at full health. Ordinary cleared stages are individually farmable even though the region is only secured after defense. The stronghold cannot be bypassed or repeatedly farmed.

A player can choose either cleared ordinary stage for farming. If requested during combat, this navigation takes effect after the battle result, never cancelling it. Farm mode repeats its selected stage after each victory and pays on every victory; defeats follow the recovery rule below. Retry frontier, requested while farming, finishes the current farm battle and then approaches the next unresolved frontier. Only the latest navigation request is retained; requests do not create rewards or refunds.

Conquest defeat defaults to farming the highest cleared ordinary stage, not repeatedly attacking the failed frontier. If no stage is cleared, level 1 retries for free. Stronghold victory commits its reward and clearance, then pauses at defense-ready regardless of pending navigation. There the player can start defense or choose ordinary-stage farming. Retry frontier after the stronghold is cleared returns to defense-ready rather than fighting the stronghold again.

Defensive defeat returns to farming while retaining stronghold clearance. Retrying reaches defense-ready, and Start defense begins a fresh assault. Defensive victory records campaign security and pauses at reset-ready. No additional farming or assault occurs from that checkpoint; the next progression action is the optional confirmed reset. After that reset, the same sequence can be replayed. Securing the successor campaign ends the slice without another reset or doctrine grant.

An encounter result, its reward, its clearance flags, and its next state are one outcome. Loading or observing a completed outcome twice cannot pay it twice. This states required behavior without choosing a transaction framework. Numbers are initial fixtures, not measured session balance.

## Exactly what resets and persists — provisional

Completing the first defense unlocks one direct permanent reward through Found a Dynasty: **Inherited Drill**, doubling squad damage after troop-level additions. It changes neither health, reward amounts, nor attack frequency. Commander strength benefits indirectly through its starting-damage formula. Unlike the broader proposed Legacy economy, this slice has no Legacy wallet or shop; a direct doctrine grant is an explicitly bounded simplification, not rejection of a future prestige resource.

Reset is permitted only at first-dynasty reset-ready, before the reset-used flag is set. A preview discloses the losses and benefit. Cancelling changes nothing. Confirming applies the complete transition once, and duplicate confirmation or loading cannot grant a second multiplier.

| State category | Reset result |
| --- | --- |
| Campaign level, phase, mode | Level 1, conquest running, advance mode |
| Cleared ordinary stages, stronghold clearance, campaign security | Return to empty/false |
| Gold | 0; all unspent gold lost |
| Owned troop levels | All three return to level 1 |
| Owned gate level | Returns to level 1 |
| Battle snapshot and health | Fresh full-health level-1 army with doctrine damage; no active gate on conquest |
| Battle elapsed time, pending strike, navigation request, farm selection | Cleared to initial values |
| Roster access | All three types remain available |
| Inherited Drill | Permanently active, one multiplier of 2 |
| Reset-used flag and dynasty | True and dynasty 2; persist thereafter |

These are the complete gameplay-state categories in scope. There is no implied inventory, lifetime-statistics system, unlock tree, or account. The newly reset campaign must be saved, not treated as deletion of the save. Doctrine and reset-used state survive quitting, loading, and ordinary defeat.

## Offline operation and save/load — provisional

All gameplay and saving work without an internet connection. Closed-app earnings are deferred for this slice. Closing or suspending freezes combat and awards no elapsed-time gold, victory, defeat, or doctrine progress. Resume continues from the saved place. This is a scope choice about time away, not a restriction on offline play.

Saving preserves gold, owned levels, doctrine, reset-used state, dynasty, clearances, current phase/mode, selected farm stage, queued navigation, active encounter stat snapshot, current health, completed rounds, progress toward the next round, and any queued strike. Recreating a damaged battle at full health on load is not acceptable. An upgrade purchased after battle start must remain owned without retroactively changing that battle's snapshot.

Purchases, outcomes, and resets must save as complete valid transitions, not half-applied changes. A save acknowledged as successful must restore its full state. If saving fails, report that progress is not saved, retain in-memory progress, and preserve the last valid save. An invalid or unreadable save must not silently be overwritten by a fresh campaign. The full-state campaign storage and durability strategy remain unselected. Existing main-game Save-v1 and its tests do not implement this proposed campaign-resume contract.

## Observable acceptance tests — provisional

These are future checks, not tests claimed to have passed. Unless stated otherwise, fixtures start in dynasty 1 with no doctrine, all troop and gate levels at 1, and no pending input. Time means logical active combat time, excluding checkpoint waits and suspension.

**Passive progression without tapping:** Start fresh and do nothing. Level 1 must end in victory on round 4: automatic damage is 18 per round against 72 enemy health. The shield squad survives, 10 gold is paid, and level 2 starts. Level 2 must also be clearable without purchases or taps. If a later frontier defeats this army, cleared-stage farming continues earning gold without tapping. Separately, spend earned gold to reach troop and gate level 3, manually retry, and complete conquest and defense with zero strikes. This full-loop check allows purchases and checkpoint decisions; it does not claim hands-off buying or automatic prestige.

**Tapping's benefit:** Compare identical fresh level-1 starts. No taps wins on round 4. One accepted tap per round adds 6 damage to 18 automatic damage and wins on round 3. Ten taps per interval must behave exactly like one, not create ten strikes. Input outside combat cannot carry into the next encounter.

**Purchases affecting combat:** Compare identical level-1 starts with 20 gold, buying foot-archer level 2 only in the second fixture. Its gold becomes 0, foot-archer health becomes 52, and its damage becomes 12 instead of 8. After the first round, enemy health is 54 without the purchase and 50 with it. Both happen to win on round 4, so duration alone is insufficient to observe this first upgrade. For a duration check, spend 60 gold on both foot-archer upgrades before the fight: total damage becomes 26 and victory takes 3 rounds. Mid-battle purchases must affect the next battle, not the current snapshot. Capped or unaffordable purchases leave state untouched.

**Distinct defensive pressure:** Use a controlled defensive state with shield infantry already dead and one living enemy dealing 12 damage. It attacks the gate, not a surviving archer. Full gate levels 1 and 2 become 68 and 128 health respectively after that round; archer health is unchanged. Separately, run the complete counterattack from full health with all squads and gate at level 3 and no taps; it must be winnable. Destroying the gate on the same round as the last enemy dies must be defeat.

**Defeat and retry without lost purchases:** Start a stronghold fixture with known gold and troop/gate upgrades and force defeat through low current health. Gold and owned levels remain unchanged, no reward is awarded, and the highest cleared ordinary stage starts farming. Request Retry frontier: once the farm battle resolves, the stronghold starts at full health with purchased stats. Repeat for defense: stronghold clearance and its prior reward remain, and retry reaches defense-ready without another stronghold fight or another 30-gold award.

**Save/load preserving state:** Save partway through a round with damaged squads, gold, queued strike, queued navigation, and a purchase made after the battle snapshot. Loading must reproduce every scoped state category. Continue loaded and uninterrupted copies under identical input and compare damage, timing, rewards, and transitions. Defense-ready and reset-ready saves retain those checkpoints. Already paid outcomes must not pay again. Failed saves preserve the last successful save and never claim success.

**Reset accelerates the same encounter under identical input:** Record level 1 with level-1 troops, no purchases, and zero taps: 4 rounds. Complete the campaign and confirm the reset. With the same level-1 troops, zero purchases, and zero taps, the unchanged 72-health enemy now receives 36 automatic damage per round and dies in 2 rounds. Verify 0 gold before battle, restored level-1 ownership, cleared campaign flags, permanent doctrine, and reset-used true. Save/load the successor and repeat the comparison. Cancellation changes nothing; repeated confirmation grants nothing extra.

**Offline and boundary behavior:** Disconnect networking and exercise the same loop and saving. Suspend or close mid-fight and resume after a delay: no absence-generated damage, income, or progress occurs. Stronghold victory pauses at defense-ready; frontier defeat defaults to farming. A round-60 victory resolves before timeout; mutual conquest elimination is defeat. Securing the second campaign grants no second reset.

## Development constraints, evidence, and risks

Beyond the implemented scope above, the remaining proposal is documentation only and requires separate approval. Later work should retain the existing separation of rules/state from UI/rendering and keep future prestige and campaign persistence independently testable. Implement and behavior-test one approved slice before adding another. Existing modules, Godot tooling, and main-game Save-v1 are already selected; new campaign-storage and future-feature interfaces remain undecided.

The design authority is `docs/game-design.md`, especially its core loop, roles, non-destructive failure, reset payoff, first scope, and offline distinction. A corpus search/read inspected `etlegacy/etlegacy`, `src/game/g_combat.c`, lines 1153–1176, revision `631d0c936ee935e3c2ddb1ffc8278c5cdbe94319`: https://github.com/etlegacy/etlegacy/blob/631d0c936ee935e3c2ddb1ffc8278c5cdbe94319/src/game/g_combat.c#L1153-L1176. Its explicit exclusion of zero-health entities is a narrow real-code reference for dead-target eligibility. Its shooter-specific systems are not suitable architecture or balance references and are not imported.

Combat, economy, main-game saving, playable campaign defense/gates and the session-only dynasty reset have executable evidence recorded above, with historical verification failures retained and physical acceptance still pending. The proposed cross-launch doctrine/full-state-save loop is not implemented or validated. Future acceptance examples remain expected outcomes, not passed tests. Remaining design risks include uninteresting upgrade allocation, insufficient passive survivability, the defense targeting exception feeling arbitrary, and an overly short campaign failing to establish prestige's emotional payoff. Evaluate those only within separately approved work rather than preemptively adding systems. Direct doctrine granting, no closed-app rewards, and fixed roster access are explicit simplifications relative to the broader brainstorm.
