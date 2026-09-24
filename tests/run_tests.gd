extends SceneTree

const Combat = preload("res://src/combat.gd")
const Economy = preload("res://src/economy.gd")
const Campaign = preload("res://src/campaign.gd")
const Data = preload("res://src/encounter_data.gd")
const BattleScene = preload("res://scenes/opening_battle.tscn")
const Presentation = preload("res://src/opening_battle.gd")
const CampaignScene = preload("res://scenes/campaign_prototype.tscn")
const CampaignPresentation = preload("res://src/campaign_prototype.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")
const CampaignState = preload("res://src/campaign_state.gd")
const CampaignSave = preload("res://src/campaign_save.gd")

# Only the OS window-state read is substituted; lifecycle, controls and clock are real.
class CampaignWindowFixture extends CampaignPresentation:
	var minimized: bool = false
	func _is_window_minimized() -> bool:
		return minimized
	func set_reason(reason: int, active: bool) -> void:
		if reason == 2:
			minimized = active
			get_tree().process_frame.emit()
		else:
			var events := [[MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN],
				[MainLoop.NOTIFICATION_APPLICATION_PAUSED, MainLoop.NOTIFICATION_APPLICATION_RESUMED]]
			notification(events[reason][0 if active else 1])

class FailingSave extends ProgressSave:
	var fail_write: bool = false
	var fail_move_to: String = ""
	var writes: int = 0
	func _write_stage(destination: String, text: String) -> Error:
		writes += 1
		var error := super._write_stage(destination, text)
		return ERR_FILE_CANT_WRITE if fail_write else error
	func _move(source: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if destination == fail_move_to else super._move(source, destination)

class PreflightFailingSave extends ProgressSave:
	var fail_primary_read: bool = false
	var primary_reads: int = 0
	func _read(source: String) -> Dictionary:
		if source == path:
			primary_reads += 1
			if fail_primary_read:
				return {"outcome": Outcome.IO_FAILURE}
		return super._read(source)

class FailingCampaignSave extends CampaignSave:
	var fail_write: bool = false
	var alter_stage: bool = false
	var fail_move_to: String = ""
	var move_failures_left: int = -1 # -1: every move to fail_move_to fails.
	func _write_stage(destination: String, text: String) -> Error:
		# alter_stage writes a valid but different snapshot, so only verification can catch it.
		var error := super._write_stage(destination, text.replace('"gold":', '"gold":1') if alter_stage else text)
		return ERR_FILE_CANT_WRITE if fail_write else error
	func _move(source: String, destination: String) -> Error:
		if destination == fail_move_to and move_failures_left != 0:
			if move_failures_left > 0:
				move_failures_left -= 1
			return ERR_FILE_CANT_WRITE
		return super._move(source, destination)

class PreflightFailingCampaignSave extends CampaignSave:
	var fail_primary_read: bool = false
	var primary_reads: int = 0
	func _read(source: String) -> Dictionary:
		if source == path:
			primary_reads += 1
			if fail_primary_read:
				return {"outcome": Outcome.IO_FAILURE}
		return super._read(source)

# Wall-clock seam only: storage, validation and the scene are real; `now` is the Unix second.
class ClockCampaignSave extends FailingCampaignSave:
	var now: int = 0
	func _now() -> int:
		return now

var checks: int = 0
var failures: int = 0
# When set, state round trips go through real files in an isolated fixture directory.
var state_store: CampaignSave = null
# The player's real campaign save (if any) must be byte-identical before and after the run.
var player_campaign_files: Dictionary = {}

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", title])

func _initialize() -> void:
	run.call_deferred()

func player_campaign_snapshot() -> Dictionary:
	var files: Dictionary = {}
	for suffix in ["", ".tmp", ".bak"]:
		var entry: String = "user://campaign.json" + suffix
		files[suffix] = FileAccess.get_file_as_bytes(entry) if FileAccess.file_exists(entry) else null
	return files

func run() -> void:
	player_campaign_files = player_campaign_snapshot()
	var passive := Combat.new()
	check(passive.rounds == 0 and passive.enemies[0].health == 72, "initial: no damage")
	for i in range(4):
		passive.step_round()
		check(passive.enemies[0].health == [54, 36, 18, 0][i]
			and passive.players[0].health == [117, 114, 111, 108][i]
			and passive.players[1].health == 40 and passive.players[2].health == 60
			and passive.rounds == i + 1
			and passive.result == (Combat.Result.VICTORY if i == 3 else Combat.Result.ONGOING),
			"passive round %d: simultaneous health and result" % (i + 1))
	var active := Combat.new()
	check(active.commander_damage == 6, "commander: starting damage formula")
	for i in range(3):
		var before: int = active.enemies[0].health
		check(active.queue_commander(), "commander interval %d accepted" % i)
		var rejected: bool = true
		for extra in range(9):
			rejected = not active.queue_commander() and rejected
		check(rejected and active.enemies[0].health == before, "ten requests: one queued, no immediate damage")
		active.step_round()
		check(active.enemies[0].health == [48, 24, 0][i]
			and active.players[0].health == [117, 114, 111][i]
			and not active.commander_queued
			and active.result == (Combat.Result.VICTORY if i == 2 else Combat.Result.ONGOING),
			"commander round %d: exact health and result" % (i + 1))
	check(not active.queue_commander(), "terminal: commands rejected")
	active.step_round()
	check(active.rounds == 3 and active.players[0].health == 111, "terminal: ticks frozen")
	var unbanked := Combat.new()
	unbanked.queue_commander()
	unbanked.step_round()
	unbanked.step_round()
	check(unbanked.enemies[0].health == 30, "commander: no banking into next interval")
	var mutual := Combat.new()
	mutual.players[0].health = 3
	mutual.players[1].health = 0
	mutual.players[2].health = 0
	mutual.enemies[0].health = 4
	mutual.step_round()
	check(mutual.enemies[0].health == 0 and mutual.players[0].health == 0
		and mutual.result == Combat.Result.DEFEAT, "mutual elimination: defeat")
	var dead := Combat.new()
	dead.players[0].health = 0
	dead.players[1].health = 0
	dead.step_round()
	check(dead.enemies[0].health == 66 and dead.players[2].health == 57,
		"dead attackers excluded; mobile takes damage before ranged")
	check(Combat.new().players[0].health == 120, "fixtures: independent health")
	test_dynasty()
	test_threat()
	test_threat_state()
	test_conquest_targeting()
	test_archer_position()
	test_progression_balance()
	test_fortified_balance()
	test_adapter()
	test_timing_partitions()
	test_foreground_clock()
	test_economy()
	test_encounter_economy()
	test_encounter_adapter()
	test_encounter_saves()
	test_fortified_economy()
	test_fortified_adapter()
	test_fortified_saves()
	test_progress_format()
	test_progress_failures()
	test_progress_adapter()
	test_defensive_combat()
	test_defense_preparation()
	test_defense_routing()
	test_defense_snapshots()
	test_campaign_progression()
	test_campaign_navigation()
	test_campaign_losses()
	test_campaign_boundaries()
	test_campaign_settlement_guards()
	test_campaign_checkpoint()
	test_campaign_purchases()
	test_campaign_determinism()
	test_campaign_scene_fresh()
	test_campaign_scene_progression()
	test_campaign_scene_navigation()
	test_campaign_scene_purchases()
	test_campaign_scene_checkpoint()
	test_campaign_scene_lifecycle()
	test_campaign_scene_defense()
	test_campaign_scene_defense_lifecycle()
	test_campaign_scene_conflicting_suspension()
	test_campaign_scene_dynasty()
	test_campaign_state_round_trips()
	test_campaign_state_duplicates()
	test_campaign_state_rejection()
	test_campaign_save_round_trips()
	test_campaign_save_format()
	test_campaign_save_failures()
	test_campaign_save_isolation()
	test_campaign_scene_saves()
	test_campaign_scene_interruptions()
	test_away_reward_rule()
	test_away_reward_format()
	test_away_reward_scene()
	check(player_campaign_snapshot() == player_campaign_files,
		"Campaign save isolation: player campaign save files unchanged by the whole run")
	if "--force-failure" in OS.get_cmdline_user_args():
		check(false, "forced runner failure")
	print("SUMMARY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func state_json(state: Dictionary) -> Variant:
	if state_store != null:
		# Disk mode: save through the store, then return the parsed bytes actually on disk.
		var source := CampaignState.restore(state)
		var before := int(Time.get_unix_time_from_system())
		var saved: bool = source.outcome == CampaignState.Outcome.VALID \
			and state_store.save_campaign(source.campaign, source.round_progress_usec) == OK
		var after := int(Time.get_unix_time_from_system())
		var loaded := CampaignSave.new(state_store.path).load_campaign()
		check(saved and loaded.outcome == CampaignSave.Outcome.LOADED and loaded.saved_at >= before and loaded.saved_at <= after
			and unstamped(CampaignSave._state_of(loaded)) == unstamped(state),
			"Campaign save: state saved and reloaded exactly from disk")
		return JSON.parse_string(FileAccess.get_file_as_string(state_store.path))
	# In-memory JSON round trip only: integers come back as floats, nothing touches disk.
	return JSON.parse_string(JSON.stringify(state))

# The save stamp is wall-clock time, not campaign state: exact-state comparisons zero it on
# both sides; the stamp itself is checked separately against an injected or bracketing clock.
func unstamped(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY or not (state as Dictionary).has("saved_at"):
		return state
	var copy: Dictionary = (state as Dictionary).duplicate(true)
	copy.saved_at = 0
	return copy

func state_scene(campaign: Campaign, elapsed: int = 0) -> CampaignPresentation:
	var scene := campaign_scene_new()
	scene.campaign = campaign
	scene.elapsed_usec = elapsed
	scene._refresh()
	return scene

func state_restore(original: CampaignPresentation, title: String) -> CampaignPresentation:
	var captured := CampaignState.capture(original.campaign, original.elapsed_usec)
	var restored: Dictionary = {"outcome": CampaignState.Outcome.UNSAVABLE}
	if captured.outcome == CampaignState.Outcome.VALID and state_store != null:
		# Disk mode: a fresh store loads what this store saved.
		var saved := state_store.save_campaign(original.campaign, original.elapsed_usec)
		var loaded := CampaignSave.new(state_store.path).load_campaign()
		if saved == OK and loaded.outcome == CampaignSave.Outcome.LOADED and not loaded.has("recovered"):
			restored = {"outcome": CampaignState.Outcome.VALID, "campaign": loaded.campaign,
				"round_progress_usec": loaded.round_progress_usec}
	elif captured.outcome == CampaignState.Outcome.VALID:
		restored = CampaignState.restore(state_json(captured.state))
	var valid: bool = restored.outcome == CampaignState.Outcome.VALID
	var again: Dictionary = CampaignState.capture(restored.campaign, restored.round_progress_usec) if valid else {}
	check(valid and again.get("state") == captured.state
		and restored.campaign != original.campaign and restored.campaign.battle != original.campaign.battle,
		("Campaign save: save/load through real file is exact and independent: " if state_store != null
			else "Campaign state: capture/JSON/restore/capture is exact and independent: ") + title)
	# A failed restore yields a fresh scene so later comparisons fail instead of crashing.
	return state_scene(restored.campaign, restored.round_progress_usec) if valid else campaign_scene_new()

func state_steps(repeats: int) -> Array[int]:
	var steps: Array[int] = []
	for i in range(repeats):
		steps.append_array([250000, 750000, 1500000, 999999, 1, 3000000, 2200000, 800000, 5000000])
	return steps

func state_continue(original: CampaignPresentation, restored: CampaignPresentation, steps: Array[int], title: String) -> void:
	var same: bool = campaign_snapshot(original.campaign, false) == campaign_snapshot(restored.campaign, false) \
		and original.elapsed_usec == restored.elapsed_usec
	for usec in steps:
		original.advance_usec(usec)
		restored.advance_usec(usec)
		same = same and campaign_snapshot(original.campaign, false) == campaign_snapshot(restored.campaign, false) \
			and original.elapsed_usec == restored.elapsed_usec
	same = same and CampaignState.capture(original.campaign, original.elapsed_usec) \
		== CampaignState.capture(restored.campaign, restored.elapsed_usec)
	check(same, "Campaign state: restored matches uninterrupted under identical input: " + title)
	original.set_process(false)
	restored.set_process(false)

func state_secured() -> Campaign:
	var campaign := Campaign.new()
	campaign.gold = 240 # Isolated funds; every owned level uses production purchases.
	for role in range(3):
		campaign.purchase(role)
		campaign.purchase(role)
	campaign.purchase_gate()
	campaign.purchase_gate()
	campaign.restart_battle()
	for stage in range(3):
		campaign_finish(campaign)
	campaign.start_defense()
	campaign_finish(campaign)
	check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED, "Campaign state fixture: real secured campaign")
	return campaign

func test_campaign_state_round_trips() -> void:
	check(CampaignState.ROUND_USEC == CampaignPresentation.ROUND_USEC, "Campaign state: round length matches scene")
	var steps := state_steps(8)
	var scenes: Array[CampaignPresentation] = []
	# Conquest: mid-round Border.
	var border := campaign_scene_new()
	border.advance_usec(2500000)
	check(border.campaign.battle.rounds == 2 and border.elapsed_usec == 500000
		and border.campaign.battle.enemies[0].health < 72, "Campaign state fixture: damaged mid-round Border")
	var restored := state_restore(border, "Border")
	state_continue(border, restored, steps, "mid-round Border")
	scenes.append_array([border, restored])
	# Conquest: damaged Archer.
	var archer := campaign_scene_new()
	campaign_scene_finish(archer)
	archer.advance_usec(1300000)
	check(archer.campaign.current_encounter == Data.Encounter.ARCHER_POSITION and archer.campaign.battle.rounds == 1,
		"Campaign state fixture: damaged Archer")
	restored = state_restore(archer, "Archer")
	state_continue(archer, restored, steps, "damaged Archer")
	scenes.append_array([archer, restored])
	# Conquest: damaged Stronghold, continued through defeat into farm recovery.
	var stronghold := campaign_scene_new()
	campaign_scene_finish(stronghold)
	campaign_scene_finish(stronghold)
	stronghold.advance_usec(2400000)
	check(stronghold.campaign.current_encounter == Data.Encounter.STRONGHOLD and stronghold.campaign.battle.rounds == 2,
		"Campaign state fixture: damaged Stronghold")
	restored = state_restore(stronghold, "Stronghold")
	state_continue(stronghold, restored, steps, "damaged Stronghold through defeat")
	check(restored.campaign.mode == Campaign.Mode.FARM and not restored.campaign.stronghold_cleared,
		"Campaign state: restored Stronghold defeat routes to farm recovery")
	scenes.append_array([stronghold, restored])
	# Conquest: upgraded Stronghold with the enemy shield dead but other enemies still fighting.
	var shield_down := campaign_scene_new()
	shield_down.campaign.gold = 140 # Isolated affordability fixture; conquest uses real rounds.
	for role in [0, 0, 1, 1, 2]:
		shield_down.upgrades[role].pressed.emit()
	campaign_scene_finish(shield_down)
	campaign_scene_finish(shield_down)
	var shield_battle := shield_down.campaign.battle
	for i in range(60):
		if shield_battle.enemies[0].health == 0 or shield_battle.result != Combat.Result.ONGOING:
			break
		shield_down.advance_usec(CampaignPresentation.ROUND_USEC)
	check(shield_down.campaign.current_encounter == Data.Encounter.STRONGHOLD
		and shield_down.campaign.battle == shield_battle and shield_battle.result == Combat.Result.ONGOING
		and shield_battle.enemies[0].role == Data.Role.SHIELD and shield_battle.enemies[0].health == 0
		and shield_battle.enemies.slice(1).any(func(squad: Data.Squad) -> bool: return squad.health > 0),
		"Campaign state fixture: ongoing Stronghold with enemy shield down")
	var shield_captured := CampaignState.capture(shield_down.campaign, shield_down.elapsed_usec)
	check(shield_captured.outcome == CampaignState.Outcome.VALID
		and CampaignState.validate(state_json(shield_captured.state)).outcome == CampaignState.Outcome.VALID,
		"Campaign state: ongoing battle with enemy shield down validates")
	restored = state_restore(shield_down, "enemy shield down")
	state_continue(shield_down, restored, state_steps(8), "enemy shield down")
	scenes.append_array([shield_down, restored])
	# Farming with queued frontier.
	var farm := campaign_scene_new()
	campaign_scene_finish(farm)
	farm.get_node("%FarmBorder").pressed.emit()
	campaign_scene_finish(farm)
	farm.advance_usec(1600000)
	farm.get_node("%Frontier").pressed.emit()
	check(farm.campaign.mode == Campaign.Mode.FARM and farm.campaign.farm_encounter == Data.Encounter.BORDER_SKIRMISH
		and farm.campaign.pending_navigation == Campaign.Navigation.FRONTIER and farm.elapsed_usec == 600000,
		"Campaign state fixture: farming with queued frontier")
	restored = state_restore(farm, "farm to frontier")
	state_continue(farm, restored, steps, "farming with queued frontier")
	scenes.append_array([farm, restored])
	# Farming with a queued farm switch after a Stronghold defeat.
	var switch := campaign_scene_new()
	campaign_scene_finish(switch)
	campaign_scene_finish(switch)
	switch.get_node("%FarmBorder").pressed.emit()
	campaign_scene_finish(switch)
	switch.get_node("%FarmArcher").pressed.emit()
	switch.advance_usec(1200000)
	check(switch.campaign.mode == Campaign.Mode.FARM and switch.campaign.farm_encounter == Data.Encounter.BORDER_SKIRMISH
		and switch.campaign.pending_farm == Data.Encounter.ARCHER_POSITION, "Campaign state fixture: queued farm switch")
	restored = state_restore(switch, "farm switch")
	state_continue(switch, restored, steps, "farming with queued farm switch")
	scenes.append_array([switch, restored])
	# Checkpoint: time does nothing; explicit defense start matches.
	var defense := campaign_scene_new()
	defense.campaign.gold = 140 # Isolated affordability fixture; conquest uses real rounds.
	for role in [0, 0, 1, 1, 2]:
		defense.upgrades[role].pressed.emit()
	for i in range(3):
		campaign_scene_finish(defense)
	check(defense.campaign.phase == Campaign.Phase.CONQUEST_CLEARED and defense.campaign.levels == [3, 3, 2],
		"Campaign state fixture: real checkpoint below horse cap")
	var checkpoint := state_restore(defense, "checkpoint")
	state_continue(defense, checkpoint, [2000000, 5000000], "checkpoint ignores time")
	for scene in [defense, checkpoint]:
		scene.get_node("%StartDefense").pressed.emit()
		scene.set_process(false)
	state_continue(defense, checkpoint, steps.slice(0, 3), "explicit defense start from restored checkpoint")
	scenes.append(checkpoint)
	# Defense: damaged gate after mid-assault troop and gate purchases, with queued recovery farm.
	defense.upgrades[2].pressed.emit()
	defense.get_node("%GateUpgrade").pressed.emit()
	defense.get_node("%FarmBorder").pressed.emit()
	var assault := defense.campaign.battle
	for i in range(60):
		if assault.gate_health < assault.gate_max_health or assault.result != Combat.Result.ONGOING:
			break
		defense.advance_usec(1000000)
	var leftover: int = defense.elapsed_usec
	defense.advance_usec(400000)
	check(defense.campaign.phase == Campaign.Phase.DEFENDING and assault.gate_health < 80 and assault.gate_health > 0
		and assault.gate_max_health == 80 and defense.campaign.gate_level == 2 and defense.campaign.levels == [3, 3, 3]
		and defense.campaign.pending_farm == Data.Encounter.BORDER_SKIRMISH and defense.elapsed_usec == (leftover + 400000) % 1000000 and defense.elapsed_usec > 0,
		"Campaign state fixture: damaged gate after mid-assault purchases")
	var captured := CampaignState.capture(defense.campaign, defense.elapsed_usec)
	check(captured.outcome == CampaignState.Outcome.VALID and captured.state.battle.snapshot_levels == [3, 3, 2]
		and captured.state.battle.snapshot_gate_level == 1 and captured.state.levels == [3, 3, 3]
		and captured.state.gate_level == 2, "Campaign state: defense snapshot stays below purchased ownership")
	restored = state_restore(defense, "defense")
	check(restored.campaign.battle.gate_max_health == 80 and restored.campaign.battle.players[2].max_health == 80
		and restored.campaign.battle.commander_damage == assault.commander_damage,
		"Campaign state: restored defense keeps snapshot gate and squad stats")
	state_continue(defense, restored, steps, "damaged defense")
	scenes.append_array([defense, restored])
	# Secured dynasty 1: restored eligibility and Legacy, rank bought after the secured battle's
	# snapshot round-trips exactly, identical successor, dynasty-2 Border won in two rounds.
	var secured := state_scene(state_secured())
	restored = state_restore(secured, "secured dynasty 1")
	check(secured.campaign.can_found_dynasty() and restored.campaign.can_found_dynasty()
		and restored.campaign.legacy == 10 and restored.campaign.drill_rank == 0,
		"Campaign state: restored secured campaign can found the dynasty with 10 Legacy")
	scenes.append(restored)
	check(secured.campaign.train_drill() and secured.campaign.legacy == 0 and secured.campaign.drill_rank == 1
		and secured.campaign._battle_drill_rank == 0, "Campaign state: Drill rank 1 bought after the secured battle")
	restored = state_restore(secured, "secured dynasty 1 with rank bought after the battle snapshot")
	check(restored.campaign.drill_rank == 1 and restored.campaign._battle_drill_rank == 0
		and restored.campaign.battle.players[0].damage == secured.campaign.battle.players[0].damage,
		"Campaign state: settled battle keeps its pre-purchase snapshot rank")
	secured.campaign.found_dynasty()
	restored.campaign.found_dynasty()
	state_continue(secured, restored, [], "dynasty founded from restored security")
	scenes.append(restored)
	secured.advance_usec(1500000)
	restored = state_restore(secured, "dynasty 2 Border")
	state_continue(secured, restored, [500000], "dynasty 2 mid-Border")
	check(restored.campaign.border_cleared and restored.campaign.gold == 10
		and restored.campaign.current_encounter == Data.Encounter.ARCHER_POSITION,
		"Campaign state: restored dynasty 2 Border won in two rounds")
	state_continue(secured, restored, steps, "dynasty 2 after Border")
	scenes.append_array([secured, restored])
	# Secured dynasty 2: +3 Legacy, and resets repeat into dynasty 3 from a restored checkpoint.
	var successor := state_secured()
	successor.train_drill()
	successor.found_dynasty()
	campaign_finish(successor)
	dynasty_prepare(successor)
	successor.start_defense()
	campaign_finish(successor)
	var final := state_scene(successor)
	restored = state_restore(final, "secured dynasty 2")
	check(final.campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and final.campaign.dynasty == 2
		and restored.campaign.legacy == 3 and restored.campaign.drill_rank == 1
		and restored.campaign.can_found_dynasty() and restored.campaign.found_dynasty() != null
		and final.campaign.found_dynasty() != null and restored.campaign.dynasty == 3
		and restored.campaign.legacy == 3 and restored.campaign.drill_rank == 1,
		"Campaign state: restored dynasty 2 security resets again into dynasty 3 keeping Legacy and rank")
	state_continue(final, restored, steps.slice(0, 5), "dynasty 3 from restored dynasty 2 security")
	scenes.append_array([final, restored])
	# Mid-battle training: the ongoing battle keeps its snapshot rank; the next battle uses the new rank.
	var unspent := Campaign.new()
	unspent.dynasty = 2
	unspent.legacy = 10 # Ledger-valid: dynasty 1 secured (+10), reset without training.
	unspent.legacy_earned = 10
	unspent.best_threat = 0
	unspent.restart_battle()
	var training := state_scene(unspent)
	training.advance_usec(1500000)
	check(unspent.train_drill() and unspent.drill_rank == 1 and unspent._battle_drill_rank == 0
		and unspent.battle.players[0].damage == 4 and unspent.battle.rounds == 1,
		"Campaign state fixture: Drill rank bought mid-battle leaves the active battle at 1x")
	restored = state_restore(training, "mid-battle Drill training")
	check(restored.campaign._battle_drill_rank == 0 and restored.campaign.battle.players[0].damage == 4,
		"Campaign state: restored mid-battle training keeps the 1x snapshot")
	state_continue(training, restored, steps.slice(0, 5), "mid-battle Drill training")
	check(restored.campaign.border_cleared and restored.campaign.battle.players[0].damage == 8
		and restored.campaign._battle_drill_rank == 1, "Campaign state: next battle after training uses 2x")
	scenes.append_array([training, restored])
	for scene in scenes:
		scene.free()

func test_campaign_state_duplicates() -> void:
	# Settled checkpoint: neither the restored nor the original battle can pay again.
	var original := state_secured()
	var restored: Campaign = CampaignState.restore(state_json(CampaignState.capture(original, 0).state)).campaign
	var gold: int = original.gold
	check(not restored.settle(restored.battle) and not original.settle(original.battle)
		and not restored.settle(original.battle) and restored.gold == gold and original.gold == gold,
		"Campaign state: restored settled checkpoint cannot duplicate its reward")
	# Ongoing battle: pays exactly once after restoration.
	var ongoing := Campaign.new()
	ongoing.restart_battle()
	ongoing.battle.step_round()
	ongoing.battle.step_round()
	restored = CampaignState.restore(state_json(CampaignState.capture(ongoing, 0).state)).campaign
	var completed := restored.battle
	while completed.result == Combat.Result.ONGOING:
		completed.step_round()
	check(restored.settle(completed) and restored.gold == 10 and not restored.settle(completed)
		and restored.gold == 10 and ongoing.gold == 0 and ongoing.battle.rounds == 2,
		"Campaign state: restored ongoing battle pays once and leaves the source untouched")
	# Dynasty 2: Drill rank 1 applies once across repeated capture/restore cycles.
	var drilled := state_secured()
	drilled.train_drill()
	drilled.found_dynasty()
	var cycled: Campaign = drilled
	for i in range(3):
		cycled = CampaignState.restore(state_json(CampaignState.capture(cycled, 0).state)).campaign
	var damage: Array[int] = []
	var expected: Array[int] = []
	for i in range(3):
		damage.append(cycled.battle.players[i].damage)
		expected.append(drilled.battle.players[i].damage)
	check(damage == expected and damage == [8, 16, 12] and cycled.drill_rank == 1 and cycled.legacy == 0
		and cycled.battle.commander_damage == drilled.battle.commander_damage,
		"Campaign state: repeated restoration keeps exactly 2x Drill damage")
	# Secured Legacy is credited once; restoring the checkpoint cannot pay it again.
	var paid := state_secured()
	var again: Campaign = CampaignState.restore(state_json(CampaignState.capture(paid, 0).state)).campaign
	check(paid.legacy == 10 and again.legacy == 10 and not again.settle(again.battle) and again.legacy == 10,
		"Campaign state: secured Legacy paid once and never duplicated by restore")
	# Restored battles are new, unshared objects.
	var state: Dictionary = CampaignState.capture(ongoing, 0).state
	var first: Campaign = CampaignState.restore(state).campaign
	var second: Campaign = CampaignState.restore(state).campaign
	first.battle.step_round()
	check(first.battle != second.battle and first.battle != ongoing.battle
		and not is_same(first.battle.players, second.battle.players)
		and first.battle.players[0] != second.battle.players[0]
		and second.battle.rounds == 2 and ongoing.battle.rounds == 2 and first.battle.rounds == 3,
		"Campaign state: independent restorations share no battle state")

func state_rejects(base: Dictionary, title: String, expected: CampaignState.Outcome, mutate: Callable) -> void:
	var state: Dictionary = base.duplicate(true)
	mutate.call(state)
	var copy: Dictionary = state.duplicate(true)
	var restored := CampaignState.restore(state)
	check(restored.outcome == expected and not restored.has("campaign")
		and CampaignState.validate(state).outcome == expected and state == copy,
		"Campaign state: rejects without mutation: " + title)

func test_campaign_state_rejection() -> void:
	var CORRUPT := CampaignState.Outcome.CORRUPT
	var running := Campaign.new()
	running.restart_battle()
	running.battle.step_round()
	running.battle.step_round()
	var base: Dictionary = state_json(CampaignState.capture(running, 500000).state)
	check(CampaignState.validate(base).outcome == CampaignState.Outcome.VALID,
		"Campaign state: JSON-shaped valid state accepted")
	check(CampaignState.restore([]).outcome == CORRUPT and CampaignState.restore(null).outcome == CORRUPT
		and CampaignState.restore("{}").outcome == CORRUPT, "Campaign state: non-object rejected")
	state_rejects(base, "missing key", CORRUPT, func(s: Dictionary) -> void: s.erase("gold"))
	state_rejects(base, "extra key", CORRUPT, func(s: Dictionary) -> void: s["extra"] = 1)
	state_rejects(base, "missing battle key", CORRUPT, func(s: Dictionary) -> void: s.battle.erase("rounds"))
	state_rejects(base, "extra battle key", CORRUPT, func(s: Dictionary) -> void: s.battle["commander_queued"] = false)
	state_rejects(base, "battle not object", CORRUPT, func(s: Dictionary) -> void: s.battle = [])
	state_rejects(base, "wrong format", CORRUPT, func(s: Dictionary) -> void: s.format = "idle-clicker-progress")
	state_rejects(base, "missing format", CORRUPT, func(s: Dictionary) -> void: s.erase("format"))
	state_rejects(base, "future version", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = 5)
	state_rejects(base, "future version float", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = 5.0)
	state_rejects(base, "version zero", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = 0)
	state_rejects(base, "negative version", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = -1)
	state_rejects(base, "huge version", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = 1e20)
	state_rejects(base, "fractional version", CORRUPT, func(s: Dictionary) -> void: s.version = 1.5)
	state_rejects(base, "string version", CORRUPT, func(s: Dictionary) -> void: s.version = "1")
	state_rejects(base, "int as bool", CORRUPT, func(s: Dictionary) -> void: s.settled = 0)
	state_rejects(base, "int cleared flag", CORRUPT, func(s: Dictionary) -> void: s.cleared[0] = 0)
	state_rejects(base, "bool as int", CORRUPT, func(s: Dictionary) -> void: s.gold = true)
	state_rejects(base, "fractional gold", CORRUPT, func(s: Dictionary) -> void: s.gold = 3.5)
	state_rejects(base, "negative gold", CORRUPT, func(s: Dictionary) -> void: s.gold = -1)
	state_rejects(base, "gold over max", CORRUPT, func(s: Dictionary) -> void: s.gold = 9007199254740992.0)
	state_rejects(base, "level over cap", CORRUPT, func(s: Dictionary) -> void: s.levels = [4, 1, 1])
	state_rejects(base, "short levels", CORRUPT, func(s: Dictionary) -> void: s.levels = [1, 1])
	state_rejects(base, "gate level zero", CORRUPT, func(s: Dictionary) -> void: s.gate_level = 0)
	state_rejects(base, "dynasty zero", CORRUPT, func(s: Dictionary) -> void: s.dynasty = 0)
	state_rejects(base, "dynasty without its Legacy", CORRUPT, func(s: Dictionary) -> void: s.dynasty = 3)
	state_rejects(base, "hand-edited Legacy", CORRUPT, func(s: Dictionary) -> void: s.legacy = 1)
	state_rejects(base, "negative Legacy", CORRUPT, func(s: Dictionary) -> void: s.legacy = -1)
	state_rejects(base, "fractional Legacy", CORRUPT, func(s: Dictionary) -> void: s.legacy = 0.5)
	state_rejects(base, "unpaid Drill rank", CORRUPT, func(s: Dictionary) -> void: s.drill_rank = 1)
	state_rejects(base, "Drill rank over max", CORRUPT, func(s: Dictionary) -> void: s.drill_rank = 4)
	state_rejects(base, "missing Legacy", CORRUPT, func(s: Dictionary) -> void: s.erase("legacy"))
	state_rejects(base, "missing snapshot rank", CORRUPT, func(s: Dictionary) -> void: s.battle.erase("snapshot_drill_rank"))
	state_rejects(base, "snapshot rank above owned", CORRUPT, func(s: Dictionary) -> void: s.battle.snapshot_drill_rank = 1)
	# Ledger-valid rank 1 at dynasty 2: a snapshot rank that disagrees with the stats is corrupt.
	var ledger: Dictionary = base.duplicate(true)
	ledger.dynasty = 2
	ledger.drill_rank = 1
	ledger.best_threat = 0
	ledger.legacy_earned = 10
	check(CampaignState.validate(ledger).outcome == CampaignState.Outcome.VALID
		and CampaignState.restore(ledger).campaign.battle.players[0].damage == 4,
		"Campaign state: dynasty 2 rank 1 with rank-0 snapshot is valid and keeps 1x battle stats")
	# Stats are derived, never stored: the snapshot rank alone decides battle damage.
	ledger.battle.snapshot_drill_rank = 1
	check(CampaignState.restore(ledger).campaign.battle.players[0].damage == 8,
		"Campaign state: snapshot rank 1 derives 2x battle stats")
	ledger.battle.snapshot_drill_rank = 0
	state_rejects(ledger, "rank ledger off by one", CORRUPT, func(s: Dictionary) -> void: s.legacy = 1)
	test_campaign_state_migration()
	state_rejects(base, "Fortified encounter", CORRUPT, func(s: Dictionary) -> void: s.current_encounter = 2)
	state_rejects(base, "enemy length", CORRUPT, func(s: Dictionary) -> void: s.battle.enemy_health.append(10))
	state_rejects(base, "healed player", CORRUPT, func(s: Dictionary) -> void: s.battle.player_health[0] = 121)
	state_rejects(base, "healed enemy", CORRUPT, func(s: Dictionary) -> void: s.battle.enemy_health[0] = 73)
	state_rejects(base, "negative health", CORRUPT, func(s: Dictionary) -> void: s.battle.player_health[1] = -1)
	state_rejects(base, "snapshot above owned", CORRUPT, func(s: Dictionary) -> void: s.battle.snapshot_levels = [2, 1, 1])
	state_rejects(base, "gate snapshot outside defense", CORRUPT, func(s: Dictionary) -> void: s.battle.snapshot_gate_level = 1)
	state_rejects(base, "non-prefix clearance", CORRUPT, func(s: Dictionary) -> void: s.cleared = [false, true, false])
	state_rejects(base, "running but settled", CORRUPT, func(s: Dictionary) -> void: s.settled = true)
	state_rejects(base, "early timeout", CORRUPT, func(s: Dictionary) -> void:
		s.settled = true
		s.battle.result = Combat.Result.DEFEAT
		s.battle.defeat_reason = Combat.DefeatReason.TIMEOUT)
	state_rejects(base, "ongoing at round sixty", CORRUPT, func(s: Dictionary) -> void: s.battle.rounds = 60)
	state_rejects(base, "victory with living enemy", CORRUPT, func(s: Dictionary) -> void:
		s.settled = true
		s.battle.result = Combat.Result.VICTORY)
	state_rejects(base, "ongoing without enemies", CORRUPT, func(s: Dictionary) -> void: s.battle.enemy_health = [0])
	state_rejects(base, "damage at round zero", CORRUPT, func(s: Dictionary) -> void: s.battle.rounds = 0)
	state_rejects(base, "uncleared pending farm", CORRUPT, func(s: Dictionary) -> void:
		s.pending_navigation = Campaign.Navigation.FARM
		s.pending_farm = Data.Encounter.BORDER_SKIRMISH)
	state_rejects(base, "farm mode without target", CORRUPT, func(s: Dictionary) -> void: s.mode = Campaign.Mode.FARM)
	state_rejects(base, "frontier queued while advancing", CORRUPT, func(s: Dictionary) -> void:
		s.pending_navigation = Campaign.Navigation.FRONTIER)
	state_rejects(base, "advance off frontier", CORRUPT, func(s: Dictionary) -> void:
		s.cleared = [true, false, false])
	state_rejects(base, "progress at round length", CORRUPT, func(s: Dictionary) -> void:
		s.round_progress_usec = CampaignState.ROUND_USEC)
	state_rejects(base, "negative progress", CORRUPT, func(s: Dictionary) -> void: s.round_progress_usec = -1)
	# Defense and secured states.
	var assault := Campaign.new()
	assault.gold = 240 # Isolated funds; every owned level uses production purchases.
	for role in range(3):
		assault.purchase(role)
		assault.purchase(role)
	assault.restart_battle()
	for stage in range(3):
		campaign_finish(assault)
	assault.start_defense()
	for i in range(3):
		assault.battle.step_round()
	var defense: Dictionary = state_json(CampaignState.capture(assault, 1).state)
	check(CampaignState.validate(defense).outcome == CampaignState.Outcome.VALID
		and defense.phase == Campaign.Phase.DEFENDING, "Campaign state: valid ongoing defense accepted")
	state_rejects(defense, "healed gate", CORRUPT, func(s: Dictionary) -> void: s.battle.gate_health = 81)
	state_rejects(defense, "gate snapshot above owned", CORRUPT, func(s: Dictionary) -> void: s.battle.snapshot_gate_level = 2)
	state_rejects(defense, "missing gate snapshot", CORRUPT, func(s: Dictionary) -> void: s.battle.snapshot_gate_level = 0)
	state_rejects(defense, "defense damages non-shield squad", CORRUPT, func(s: Dictionary) -> void: s.battle.player_health[1] = 1)
	state_rejects(defense, "defense in farm mode", CORRUPT, func(s: Dictionary) -> void:
		s.mode = Campaign.Mode.FARM
		s.farm_encounter = Data.Encounter.BORDER_SKIRMISH)
	state_rejects(defense, "defense before Stronghold", CORRUPT, func(s: Dictionary) -> void: s.cleared = [true, true, false])
	state_rejects(defense, "army defeat in defense", CORRUPT, func(s: Dictionary) -> void:
		s.settled = true
		s.battle.result = Combat.Result.DEFEAT
		s.battle.defeat_reason = Combat.DefeatReason.ARMY_DEFEAT)
	var secured: Dictionary = state_json(CampaignState.capture(state_secured(), 0).state)
	state_rejects(secured, "secured with destroyed gate", CORRUPT, func(s: Dictionary) -> void: s.battle.gate_health = 0)
	state_rejects(secured, "progress at checkpoint", CORRUPT, func(s: Dictionary) -> void: s.round_progress_usec = 1)
	state_rejects(secured, "secured with queued farm", CORRUPT, func(s: Dictionary) -> void:
		s.pending_navigation = Campaign.Navigation.FARM
		s.pending_farm = Data.Encounter.BORDER_SKIRMISH)
	state_rejects(secured, "secured but unsettled", CORRUPT, func(s: Dictionary) -> void: s.settled = false)
	state_rejects(secured, "secured phase running", CORRUPT, func(s: Dictionary) -> void: s.phase = Campaign.Phase.RUNNING)
	# Capture refuses states a file cannot reproduce and never mutates the source.
	var queued := Campaign.new()
	queued.restart_battle()
	queued.battle.queue_commander()
	var before := campaign_snapshot(queued)
	check(CampaignState.capture(queued, 0).outcome == CampaignState.Outcome.UNSAVABLE and campaign_snapshot(queued) == before,
		"Campaign state: capture refuses queued commander strike unchanged")
	var altered := Campaign.new()
	altered.restart_battle()
	altered.battle.players[0].damage = 5
	before = campaign_snapshot(altered)
	check(CampaignState.capture(altered, 0).outcome == CampaignState.Outcome.UNSAVABLE and campaign_snapshot(altered) == before,
		"Campaign state: capture refuses non-level squad stats unchanged")
	var orphan := Campaign.new()
	orphan.restart_battle()
	orphan.legacy = 5
	before = campaign_snapshot(orphan)
	check(CampaignState.capture(orphan, 0).outcome == CampaignState.Outcome.UNSAVABLE and campaign_snapshot(orphan) == before
		and CampaignState.capture(Campaign.new(), 0).outcome == CampaignState.Outcome.UNSAVABLE
		and CampaignState.capture(running, CampaignState.ROUND_USEC).outcome == CampaignState.Outcome.UNSAVABLE,
		"Campaign state: capture refuses unearned Legacy, missing battle and whole-round progress")
	var unpaid := Campaign.new()
	unpaid.restart_battle()
	unpaid.drill_rank = 1
	unpaid._battle_drill_rank = 1
	before = campaign_snapshot(unpaid)
	check(CampaignState.capture(unpaid, 0).outcome == CampaignState.Outcome.UNSAVABLE and campaign_snapshot(unpaid) == before,
		"Campaign state: capture refuses an unpaid Drill rank unchanged")
	check(player_campaign_snapshot() == player_campaign_files, "Campaign state: player campaign save files unchanged")

# Build a contract-v3 state from a v4 capture (drop the save stamp) as older builds wrote it.
func state_as_v3(state: Dictionary) -> Dictionary:
	var old: Dictionary = state.duplicate(true)
	old.version = 3
	old.erase("saved_at")
	return old

# Build a contract-v2 state from a v4 capture (drop the stamp and Threat keys) as older builds wrote it.
func state_as_v2(state: Dictionary) -> Dictionary:
	var old: Dictionary = state_as_v3(state)
	old.version = 2
	old.erase("threat")
	old.erase("best_threat")
	old.erase("legacy_earned")
	return old

# Build a contract-v1 state from a v4 capture (drop the Threat and Legacy keys) as older builds wrote it.
func state_as_v1(state: Dictionary) -> Dictionary:
	var old: Dictionary = state_as_v2(state)
	old.version = 1
	old.erase("legacy")
	old.erase("drill_rank")
	old.battle.erase("snapshot_drill_rank")
	return old

func test_campaign_state_migration() -> void:
	var CORRUPT := CampaignState.Outcome.CORRUPT
	# Dynasty 1 running: rank 0, no Legacy.
	var running := campaign_running(2)
	var v1: Dictionary = state_as_v1(state_json(CampaignState.capture(running, 250000).state))
	var migrated := CampaignState.restore(v1)
	check(migrated.outcome == CampaignState.Outcome.VALID and migrated.campaign.dynasty == 1
		and migrated.campaign.legacy == 0 and migrated.campaign.drill_rank == 0
		and CampaignState.capture(migrated.campaign, 250000).state == CampaignState.capture(running, 250000).state,
		"Campaign migration: v1 dynasty 1 running maps to rank 0, Legacy 0, exact state")
	# Dynasty 1 secured: the first-secure 10 Legacy is credited.
	var secured := state_secured()
	v1 = state_as_v1(state_json(CampaignState.capture(secured, 0).state))
	migrated = CampaignState.restore(v1)
	check(migrated.outcome == CampaignState.Outcome.VALID and migrated.campaign.legacy == 10
		and migrated.campaign.drill_rank == 0 and migrated.campaign.can_found_dynasty(),
		"Campaign migration: v1 secured dynasty 1 gains 10 Legacy and can reset")
	# Dynasty 2 running: the old free doctrine becomes Drill rank 1 (2x battle stats kept).
	secured.train_drill()
	secured.found_dynasty()
	secured.battle.step_round()
	v1 = state_as_v1(state_json(CampaignState.capture(secured, 0).state))
	migrated = CampaignState.restore(v1)
	check(migrated.outcome == CampaignState.Outcome.VALID and migrated.campaign.dynasty == 2
		and migrated.campaign.legacy == 0 and migrated.campaign.drill_rank == 1
		and migrated.campaign._battle_drill_rank == 1 and migrated.campaign.battle.players[0].damage == 8
		and CampaignState.capture(migrated.campaign, 0).state == CampaignState.capture(secured, 0).state,
		"Campaign migration: v1 dynasty 2 maps to Drill rank 1 with exact 2x battle")
	# Dynasty 2 secured: repeat payout of 3 Legacy.
	campaign_finish(secured)
	dynasty_prepare(secured)
	secured.start_defense()
	campaign_finish(secured)
	v1 = state_as_v1(state_json(CampaignState.capture(secured, 0).state))
	migrated = CampaignState.restore(v1)
	check(migrated.outcome == CampaignState.Outcome.VALID and migrated.campaign.legacy == 3
		and migrated.campaign.drill_rank == 1 and migrated.campaign.can_found_dynasty(),
		"Campaign migration: v1 secured dynasty 2 gains 3 Legacy and can reset again")
	# v1 keeps its own exact rules.
	state_rejects(v1, "v1 dynasty three", CORRUPT, func(s: Dictionary) -> void: s.dynasty = 3)
	state_rejects(v1, "v1 with v2 Legacy key", CORRUPT, func(s: Dictionary) -> void: s["legacy"] = 3)
	state_rejects(v1, "v1 with v2 snapshot rank", CORRUPT, func(s: Dictionary) -> void: s.battle["snapshot_drill_rank"] = 1)
	state_rejects(v1, "v2 without Legacy keys", CORRUPT, func(s: Dictionary) -> void: s.version = 2)
	# On disk: a v1 file loads through the real store, and the next ordinary save writes v4.
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign migration: isolated directory owned")
	if not fixture.owned:
		return
	check(fixture.put(JSON.stringify(v1)) == OK, "Campaign migration: v1 file written")
	var store := CampaignSave.new(fixture.path)
	var loaded := store.load_campaign()
	check(loaded.outcome == CampaignSave.Outcome.LOADED and not loaded.has("recovered")
		and loaded.campaign.legacy == 3 and loaded.campaign.drill_rank == 1
		and FileAccess.get_file_as_string(fixture.path) == JSON.stringify(v1),
		"Campaign migration: v1 file loads through the store without being rewritten")
	check(store.save_campaign(loaded.campaign, loaded.round_progress_usec) == OK
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).version == 4
		and CampaignSave.new(fixture.path).load_campaign().campaign.legacy == 3,
		"Campaign migration: next save writes v4 that reloads exactly")
	check(fixture.cleanup() == OK, "Campaign migration: directory cleaned")

func campaign_running(rounds: int = 2, gold: int = 7) -> Campaign:
	var campaign := Campaign.new()
	campaign.gold = gold # Isolated storage fixture value; combat uses real rounds.
	campaign.restart_battle()
	for i in range(rounds):
		campaign.battle.step_round()
	return campaign

func campaign_state_of(path: String) -> Variant:
	return unstamped(CampaignSave._state_of(CampaignSave.new(path).load_campaign()))

func test_campaign_save_round_trips() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign save: isolated directory owned")
	if not fixture.owned:
		return
	var store := CampaignSave.new(fixture.path)
	check(store.load_campaign().outcome == CampaignSave.Outcome.MISSING and not FileAccess.file_exists(fixture.path),
		"Campaign save: missing file loads as missing and writes nothing")
	var queued := campaign_running(0)
	queued.battle.queue_commander()
	check(store.save_campaign(queued, 0) == ERR_INVALID_DATA and not FileAccess.file_exists(fixture.path)
		and not FileAccess.file_exists(fixture.path + ".tmp"), "Campaign save: unsavable queued strike refused before any I/O")
	check(fixture.put("abandoned", ".tmp") == OK and CampaignSave.new(fixture.path).load_campaign().outcome == CampaignSave.Outcome.MISSING,
		"Campaign save: abandoned stage ignored")
	# Every restoration and duplicate scenario, re-run through real files.
	state_store = store
	test_campaign_state_round_trips()
	test_campaign_state_duplicates()
	state_store = null
	# Largest values stay within the bounded read.
	var rich := state_secured()
	rich.gold = ProgressSave.MAX_GOLD
	var big := campaign_running(1, ProgressSave.MAX_GOLD)
	for campaign in [rich, big]:
		var size_ok: bool = store.save_campaign(campaign, 999999 if campaign == big else 0) == OK
		var length := FileAccess.get_file_as_bytes(fixture.path).size()
		var loaded := CampaignSave.new(fixture.path).load_campaign()
		check(size_ok and length > 0 and length <= ProgressSave.MAX_BYTES and loaded.outcome == CampaignSave.Outcome.LOADED
			and loaded.campaign.gold == ProgressSave.MAX_GOLD, "Campaign save: max-gold snapshot fits %d bytes and loads" % length)
	var first := CampaignSave.new(fixture.path).load_campaign()
	first.campaign.gold = 1
	first.campaign.battle.step_round()
	var second := CampaignSave.new(fixture.path).load_campaign()
	check(second.campaign.gold == ProgressSave.MAX_GOLD and second.campaign.battle.rounds == 1
		and second.campaign != first.campaign, "Campaign save: returned campaigns are independent")
	check(fixture.cleanup() == OK, "Campaign save: round-trip directory cleaned")

func test_campaign_save_format() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign save format: isolated directory owned")
	if not fixture.owned:
		return
	var base: Dictionary = CampaignState.capture(campaign_running(), 250000).state
	var valid: String = JSON.stringify(base)
	check(valid.contains('"gold":7') and valid.ends_with('"version":4}'), "Campaign save format: canonical integer text")
	var backup: String = JSON.stringify(CampaignState.capture(campaign_running(1), 0).state)
	check(fixture.put(backup, ".bak") == OK, "Campaign save format: valid backup beside every primary")
	var mutated := func(mutate: Callable) -> String:
		var state: Dictionary = base.duplicate(true)
		mutate.call(state)
		return JSON.stringify(state)
	var corrupt: Array[String] = ["", "{", "not json", "[]", "null", "{}", " ".repeat(4097),
		valid + " ".repeat(4097 - valid.length()),
		valid.replace('"gold":7', '"gold":0.5'),
		valid.replace('"gold":7', '"gold":1.00000000000000001'),
		valid.replace('"gold":7', '"gold":9007199254740992'),
		valid.replace('"gold":7', '"gold":1e999'),
		valid.replace('"gold":7', '"gold":"7"'),
		'{"version":1,"gold":0,"levels":[1,1,1]}',
		mutated.call(func(s: Dictionary) -> void: s["extra"] = 0),
		mutated.call(func(s: Dictionary) -> void: s.erase("gold")),
		mutated.call(func(s: Dictionary) -> void: s.erase("format")),
		mutated.call(func(s: Dictionary) -> void: s.format = "idle-clicker-progress"),
		mutated.call(func(s: Dictionary) -> void: s.cleared = [false, true, false]),
		mutated.call(func(s: Dictionary) -> void: s.battle.player_health[0] = 121),
		mutated.call(func(s: Dictionary) -> void: s.settled = true)]
	check(corrupt[7].length() == 4097, "Campaign save format: oversize fixture is 4097 bytes")
	var unsupported: Array[String] = [mutated.call(func(s: Dictionary) -> void: s.version = 5),
		'{"format":"idle-clicker-campaign","version":99,"gold":"future payload"}']
	var replacement := campaign_running(3)
	for expected in [CampaignSave.Outcome.CORRUPT, CampaignSave.Outcome.UNSUPPORTED]:
		for text: String in (corrupt if expected == CampaignSave.Outcome.CORRUPT else unsupported):
			check(fixture.put(text) == OK, "Campaign save format: invalid fixture written")
			var rejected := CampaignSave.new(fixture.path)
			var loaded := rejected.load_campaign()
			check(loaded.outcome == expected and not loaded.has("campaign") and not loaded.has("recovered")
				and rejected.save_campaign(replacement, 0) == ERR_UNAUTHORIZED
				and FileAccess.get_file_as_bytes(fixture.path) == text.to_utf8_buffer()
				and FileAccess.get_file_as_string(fixture.path + ".bak") == backup
				and not FileAccess.file_exists(fixture.path + ".tmp"),
				"Campaign save format: %s preserved, never overwritten, no backup bypass"
				% ("corrupt" if expected == CampaignSave.Outcome.CORRUPT else "unsupported"))
	for text in [valid.replace('"gold":7', '"gold":70e-1').replace('"version":1}', '"version":1.0}'),
			valid.replace('"gold":7', '"gold":7E0')]:
		check(fixture.put(text) == OK and campaign_state_of(fixture.path) == base,
			"Campaign save format: exact whole decimal and exponent forms accepted")
	check(fixture.cleanup() == OK, "Campaign save format: directory cleaned")

func test_campaign_save_failures() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign save failures: isolated directory owned")
	if not fixture.owned:
		return
	var path: String = fixture.path
	var good := campaign_running(2)
	var good_state: Dictionary = CampaignState.capture(good, 250000).state
	var store := FailingCampaignSave.new(path)
	check(store.save_campaign(good, 250000) == OK and campaign_state_of(path) == good_state, "Campaign save failures: baseline")
	var before := FileAccess.get_file_as_bytes(path)
	var next := campaign_running(3, 9)
	var next_state: Dictionary = CampaignState.capture(next, 500000).state
	store.fail_write = true
	check(store.save_campaign(next, 500000) == ERR_FILE_CANT_WRITE and FileAccess.get_file_as_bytes(path) == before,
		"Campaign save failures: write/flush failure reported, primary preserved")
	store.fail_write = false
	check(DirAccess.remove_absolute(path + ".tmp") == OK and DirAccess.make_dir_absolute(path + ".tmp") == OK,
		"Campaign save failures: real blocked staging path")
	check(store.save_campaign(next, 500000) != OK and FileAccess.get_file_as_bytes(path) == before,
		"Campaign save failures: staging open failure reported, primary preserved")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Campaign save failures: staging obstruction removed")
	store.alter_stage = true
	check(store.save_campaign(next, 500000) == ERR_FILE_CORRUPT and FileAccess.get_file_as_bytes(path) == before
		and not FileAccess.file_exists(path + ".bak"), "Campaign save failures: stage verification mismatch refused before rotation")
	store.alter_stage = false
	check(DirAccess.make_dir_absolute(path + ".bak") == OK, "Campaign save failures: real backup obstruction")
	check(store.save_campaign(next, 500000) != OK and FileAccess.get_file_as_bytes(path) == before,
		"Campaign save failures: backup rotation failure reported, primary preserved")
	check(DirAccess.remove_absolute(path + ".bak") == OK, "Campaign save failures: backup obstruction removed")
	store.fail_move_to = path
	check(store.save_campaign(next, 500000) != OK and not FileAccess.file_exists(path)
		and FileAccess.get_file_as_bytes(path + ".bak") == before,
		"Campaign save failures: failed commit and restore retain last-good backup")
	var recovered := CampaignSave.new(path).load_campaign()
	check(recovered.outcome == CampaignSave.Outcome.LOADED and recovered.get("recovered", false)
		and unstamped(CampaignSave._state_of(recovered)) == good_state, "Campaign save failures: missing primary recovered from validated backup")
	store.fail_move_to = ""
	check(store.save_campaign(next, 500000) == OK and campaign_state_of(path) == next_state
		and FileAccess.get_file_as_bytes(path + ".bak") == before, "Campaign save failures: retry saves full state, backup retained")
	# Commit failure with a working restore puts the last-good primary back.
	var committed := FileAccess.get_file_as_bytes(path)
	var restorer := FailingCampaignSave.new(path)
	check(restorer.load_campaign().outcome == CampaignSave.Outcome.LOADED, "Campaign save failures: restorer loaded")
	restorer.fail_move_to = path
	restorer.move_failures_left = 1
	check(restorer.save_campaign(good, 250000) == ERR_FILE_CANT_WRITE and FileAccess.get_file_as_bytes(path) == committed
		and FileAccess.get_file_as_bytes(path + ".bak") == committed and not FileAccess.file_exists(path + ".tmp"),
		"Campaign save failures: failed commit reported, last-good primary restored from backup")
	check(CampaignSave.new(path).load_campaign().get("recovered", false) == false and campaign_state_of(path) == next_state,
		"Campaign save failures: restored primary loads directly")
	# Unreadable primary: reported, preserved, backup not bypassed.
	check(DirAccess.remove_absolute(path) == OK and DirAccess.make_dir_absolute(path) == OK, "Campaign save failures: unreadable primary directory")
	var unreadable := CampaignSave.new(path)
	check(unreadable.load_campaign().outcome == CampaignSave.Outcome.IO_FAILURE and unreadable.save_campaign(next, 0) == ERR_UNAUTHORIZED
		and DirAccess.dir_exists_absolute(path) and FileAccess.get_file_as_bytes(path + ".bak") == committed,
		"Campaign save failures: unreadable primary preserved, saving disabled, backup not bypassed")
	check(DirAccess.remove_absolute(path) == OK and fixture.put(committed.get_string_from_utf8()) == OK,
		"Campaign save failures: primary restored for session tests")
	# Mid-session transient read failure: retry allowed, nothing staged.
	var session := PreflightFailingCampaignSave.new(path)
	check(session.load_campaign().outcome == CampaignSave.Outcome.LOADED and not FileAccess.file_exists(path + ".tmp"),
		"Campaign save failures: session loaded without stale stage")
	session.fail_primary_read = true
	check(session.save_campaign(good, 250000) == ERR_FILE_CANT_READ and not FileAccess.file_exists(path + ".tmp")
		and FileAccess.get_file_as_bytes(path) == committed, "Campaign save failures: mid-session read failure stages nothing")
	session.fail_primary_read = false
	var reads := session.primary_reads
	check(session.save_campaign(good, 250000) == OK and session.primary_reads > reads and campaign_state_of(path) == good_state,
		"Campaign save failures: retry rereads primary and saves")
	# Mid-session corruption: refused permanently for this launch, bytes preserved.
	check(fixture.put("{") == OK, "Campaign save failures: primary corrupted after accepted load")
	check(session.save_campaign(next, 500000) == ERR_UNAUTHORIZED and FileAccess.get_file_as_string(path) == "{"
		and session.get_preservation_outcome() == CampaignSave.Outcome.CORRUPT, "Campaign save failures: mid-session corruption preserved")
	check(fixture.put(committed.get_string_from_utf8()) == OK and session.save_campaign(next, 500000) == ERR_UNAUTHORIZED
		and FileAccess.get_file_as_bytes(path) == committed, "Campaign save failures: saving stays disabled for the launch")
	check(fixture.cleanup() == OK, "Campaign save failures: directory cleaned")
	# Crash before an acknowledged dynasty confirmation: pre-confirm security, Drill applied exactly once.
	var dynasty := ProgressFixture.new("campaign.json")
	check(dynasty.owned, "Campaign save dynasty: isolated directory owned")
	if not dynasty.owned:
		return
	var secured := state_secured()
	secured.train_drill()
	var secured_state: Dictionary = CampaignState.capture(secured, 0).state
	var founder := FailingCampaignSave.new(dynasty.path)
	check(founder.save_campaign(secured, 0) == OK, "Campaign save dynasty: secured dynasty 1 saved")
	secured.found_dynasty()
	founder.fail_move_to = dynasty.path
	check(secured.dynasty == 2 and founder.save_campaign(secured, 0) != OK, "Campaign save dynasty: confirmation save failed")
	var relaunch := CampaignSave.new(dynasty.path).load_campaign()
	check(relaunch.outcome == CampaignSave.Outcome.LOADED and unstamped(CampaignSave._state_of(relaunch)) == secured_state
		and relaunch.campaign.dynasty == 1 and relaunch.campaign.can_found_dynasty() and relaunch.campaign.drill_rank == 1,
		"Campaign save dynasty: unacknowledged confirm reloads pre-confirm security")
	var successor: Campaign = relaunch.campaign
	var founded := successor.found_dynasty() != null
	var damage: Array[int] = []
	for squad in successor.battle.players:
		damage.append(squad.damage)
	check(founded and successor.dynasty == 2 and damage == [8, 16, 12] and successor.found_dynasty() == null,
		"Campaign save dynasty: single confirm gives exactly 2x Drill, no reset before security")
	founder.fail_move_to = ""
	var again := CampaignSave.new(dynasty.path)
	check(again.load_campaign().get("recovered", false) and again.save_campaign(successor, 0) == OK, "Campaign save dynasty: successor saved")
	var reloaded := CampaignSave.new(dynasty.path).load_campaign()
	damage.clear()
	for squad in reloaded.campaign.battle.players:
		damage.append(squad.damage)
	check(reloaded.campaign.dynasty == 2 and damage == [8, 16, 12] and not reloaded.campaign.can_found_dynasty()
		and reloaded.campaign.drill_rank == 1 and reloaded.campaign.legacy == 0,
		"Campaign save dynasty: relaunched successor keeps Drill once, no reset before security")
	# No absence progress: a real delay changes nothing about the loaded battle.
	var paused := campaign_running(2)
	var paused_state: Dictionary = CampaignState.capture(paused, 750000).state
	check(CampaignSave.new(dynasty.path).save_campaign(paused, 750000) == OK, "Campaign save absence: battle saved")
	OS.delay_msec(1200)
	var resumed := CampaignSave.new(dynasty.path).load_campaign()
	check(unstamped(CampaignSave._state_of(resumed)) == paused_state and resumed.campaign.battle.rounds == 2
		and resumed.round_progress_usec == 750000, "Campaign save absence: elapsed time adds no rounds, damage or progress")
	check(dynasty.cleanup() == OK, "Campaign save dynasty: directory cleaned")

func test_campaign_save_isolation() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign save isolation: isolated directory owned")
	if not fixture.owned:
		return
	var progress_path: String = fixture.directory.path_join("progress.json")
	var levels: Array[int] = [2, 1, 1]
	check(ProgressSave.new(progress_path).save_progress(10, levels) == OK, "Campaign save isolation: sibling Save-v1 written")
	var progress_bytes := FileAccess.get_file_as_bytes(progress_path)
	var store := FailingCampaignSave.new(fixture.path)
	var ok: bool = store.save_campaign(campaign_running(1), 0) == OK and store.save_campaign(campaign_running(2), 0) == OK
	store.fail_move_to = fixture.path
	ok = ok and store.save_campaign(campaign_running(3), 0) != OK
	store.fail_move_to = ""
	ok = ok and store.save_campaign(campaign_running(3), 0) == OK and fixture.put("{") == OK
	ok = ok and CampaignSave.new(fixture.path).save_campaign(campaign_running(4), 0) == ERR_UNAUTHORIZED
	check(ok, "Campaign save isolation: campaign saves, failures and refusals exercised")
	check(FileAccess.get_file_as_bytes(progress_path) == progress_bytes and not FileAccess.file_exists(progress_path + ".tmp")
		and not FileAccess.file_exists(progress_path + ".bak"), "Campaign save isolation: sibling Save-v1 bytes untouched")
	var misdirected := CampaignSave.new(progress_path)
	check(misdirected.load_campaign().outcome == CampaignSave.Outcome.IO_FAILURE
		and misdirected.save_campaign(campaign_running(1), 0) == ERR_UNAUTHORIZED
		and FileAccess.get_file_as_bytes(progress_path) == progress_bytes and not FileAccess.file_exists(progress_path + ".tmp"),
		"Campaign save isolation: store refuses a Save-v1 path")
	var loaded := ProgressSave.new(progress_path).load_progress()
	check(loaded.outcome == ProgressSave.Outcome.LOADED and loaded.gold == 10 and loaded.levels == levels,
		"Campaign save isolation: Save-v1 still loads unchanged")
	check(fixture.cleanup() == OK, "Campaign save isolation: directory cleaned")
	check(player_campaign_snapshot() == player_campaign_files,
		"Campaign save isolation: player campaign save files unchanged")

func scene_saved_exactly(scene: CampaignPresentation, path: String) -> bool:
	var captured := CampaignState.capture(scene.campaign, scene.elapsed_usec)
	return captured.outcome == CampaignState.Outcome.VALID and campaign_state_of(path) == captured.state

func scene_state(scene: CampaignPresentation) -> Variant:
	var captured := CampaignState.capture(scene.campaign, scene.elapsed_usec)
	return captured.state if captured.outcome == CampaignState.Outcome.VALID else null

func test_campaign_scene_saves() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Campaign scene saves: isolated directory owned")
	if not fixture.owned:
		return
	var path: String = fixture.path
	var progress_path: String = fixture.directory.path_join("progress.json")
	var v1_levels: Array[int] = [2, 1, 1]
	check(ProgressSave.new(progress_path).save_progress(10, v1_levels) == OK, "Campaign scene saves: sibling Save-v1 written")
	var v1_bytes := FileAccess.get_file_as_bytes(progress_path)
	# Missing save: fresh session; the first accepted trigger creates the file.
	var scene := campaign_scene_new(CampaignWindowFixture, CampaignSave.new(path)) as CampaignWindowFixture
	check(scene.saving_enabled and scene.get_node("%SaveStatus").text == "Autosave on"
		and scene.campaign.gold == 0 and scene.campaign.battle.rounds == 0 and not FileAccess.file_exists(path),
		"Campaign scene saves: missing save starts fresh without writing")
	scene.advance_usec(2500000)
	check(scene.campaign.battle.rounds == 2 and not FileAccess.file_exists(path), "Campaign scene saves: rounds alone never save")
	scene.advance_time(120.0)
	check(scene.campaign.border_cleared and scene.campaign.gold == 10 and scene.elapsed_usec == 0
		and scene.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(scene, path),
		"Campaign scene saves: settlement saves reward, clearance and routing together")
	var bytes := FileAccess.get_file_as_bytes(path)
	scene.upgrades[0].pressed.emit()
	check(scene.campaign.levels[0] == 1 and FileAccess.get_file_as_bytes(path) == bytes,
		"Campaign scene saves: rejected purchase writes nothing")
	campaign_scene_finish(scene)
	scene.advance_usec(1250000)
	scene.upgrades[0].pressed.emit()
	check(scene.campaign.levels[0] == 2 and scene.campaign.battle.players[0].damage == 4 and scene.elapsed_usec == 250000
		and scene.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(scene, path),
		"Campaign scene saves: mid-battle purchase saves owned level, snapshot and fractional time")
	scene.get_node("%FarmBorder").pressed.emit()
	check(scene.campaign.pending_navigation == Campaign.Navigation.FARM and scene_saved_exactly(scene, path),
		"Campaign scene saves: queued farm saved")
	scene.advance_usec(300000)
	scene.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(scene.elapsed_usec == 550000 and scene_saved_exactly(scene, path), "Campaign scene saves: close request saves mid-round progress")
	scene.advance_usec(100000)
	scene.set_reason(0, true)
	check(scene.suspended and scene.elapsed_usec == 650000 and scene_saved_exactly(scene, path),
		"Campaign scene saves: entering suspension saves mid-round progress")
	scene.set_reason(0, false)
	campaign_scene_finish(scene)
	check(scene.campaign.mode == Campaign.Mode.FARM and scene_saved_exactly(scene, path),
		"Campaign scene saves: queued farm routed and saved")
	scene.get_node("%Frontier").pressed.emit()
	check(scene.campaign.pending_navigation == Campaign.Navigation.FRONTIER and scene_saved_exactly(scene, path),
		"Campaign scene saves: queued frontier saved")
	var expected: Variant = scene_state(scene)
	scene.free()
	# Relaunch: exact state, resume message, first frame excluded.
	var loaded := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	check(loaded.get_node("%SaveStatus").text == "Autosave on" and loaded.get_node("%LastResult").text == "Resumed saved campaign"
		and scene_state(loaded) == expected and loaded.skip_resume_frame, "Campaign scene saves: relaunch restores exact state")
	loaded.advance_usec(9000000)
	loaded.advance_usec(CampaignPresentation.ROUND_USEC - loaded.elapsed_usec - 1)
	check(loaded.campaign.battle.rounds == 0, "Campaign scene saves: loaded first frame and absence add no rounds")
	loaded.free()
	# Missing primary: validated backup restored.
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	check(DirAccess.rename_absolute(path, path + ".bak") == OK, "Campaign scene saves: primary moved to backup")
	var recovered := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	check(recovered.get_node("%SaveStatus").text == "Restored from backup" and scene_state(recovered) == expected,
		"Campaign scene saves: backup restore shown and exact")
	recovered.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(recovered.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(recovered, path),
		"Campaign scene saves: recovered session saves a new primary")
	recovered.free()
	# Unusable primaries: fresh session, saving disabled, file preserved.
	var unsupported_state: Dictionary = (expected as Dictionary).duplicate(true)
	unsupported_state.version = 5
	var backup_bytes := FileAccess.get_file_as_bytes(path + ".bak")
	for case in [["{", "damaged"], [JSON.stringify(unsupported_state), "from an unsupported version"], ["", "unreadable"]]:
		if case[1] == "unreadable":
			DirAccess.remove_absolute(path)
			DirAccess.make_dir_absolute(path)
		else:
			fixture.put(case[0])
		var refused := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
		check(not refused.saving_enabled and refused.campaign.gold == 0 and not refused.campaign.border_cleared
			and refused.get_node("%SaveStatus").text == "Saving disabled: campaign save %s, preserved. This session will not be kept." % case[1],
			"Campaign scene saves: %s save starts fresh with saving disabled" % case[1])
		refused.advance_time(120.0)
		refused.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		var preserved: bool = DirAccess.dir_exists_absolute(path) if case[1] == "unreadable" \
			else FileAccess.get_file_as_string(path) == case[0]
		check(refused.campaign.border_cleared and preserved and FileAccess.get_file_as_bytes(path + ".bak") == backup_bytes
			and not FileAccess.file_exists(path + ".tmp") and refused.get_node("%SaveStatus").text.begins_with("Saving disabled"),
			"Campaign scene saves: %s save preserved, backup not bypassed" % case[1])
		refused.free()
	DirAccess.remove_absolute(path)
	# Failed write: memory kept, retry on next trigger saves the full state.
	check(CampaignSave.new(path).save_campaign(campaign_running(1, 100), 400000) == OK, "Campaign scene saves: funded fixture saved")
	var failing := FailingCampaignSave.new(path)
	var retry := campaign_scene_new(CampaignPresentation, failing)
	bytes = FileAccess.get_file_as_bytes(path)
	failing.fail_write = true
	retry.upgrades[0].pressed.emit()
	check(retry.campaign.levels == [2, 1, 1] and retry.campaign.gold == 80 and FileAccess.get_file_as_bytes(path) == bytes
		and retry.get_node("%SaveStatus").text == "Progress not saved — will retry",
		"Campaign scene saves: failed save keeps memory and last good file")
	failing.fail_write = false
	retry.upgrades[1].pressed.emit()
	check(retry.campaign.levels == [2, 2, 1] and retry.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(retry, path),
		"Campaign scene saves: next trigger retries and saves full state")
	check(fixture.put("{") == OK, "Campaign scene saves: primary corrupted mid-session")
	retry.upgrades[2].pressed.emit()
	retry.upgrades[0].pressed.emit()
	check(not retry.saving_enabled and FileAccess.get_file_as_string(path) == "{"
		and retry.get_node("%SaveStatus").text == "Saving disabled: campaign save damaged, preserved. This session will not be kept.",
		"Campaign scene saves: mid-session corruption disables saving and preserves file")
	retry.free()
	DirAccess.remove_absolute(path)
	# Dynasty preview: open/cancel/Escape never write; confirm saves the successor once.
	check(CampaignSave.new(path).save_campaign(state_secured(), 0) == OK, "Campaign scene saves: secured fixture saved")
	var secured := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	bytes = FileAccess.get_file_as_bytes(path)
	secured.get_node("%FoundDynasty").pressed.emit()
	var opened: bool = secured.dynasty_preview_open
	secured.get_node("%CancelDynasty").pressed.emit()
	secured.get_node("%FoundDynasty").pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	secured._input(escape)
	check(opened and not secured.dynasty_preview_open and secured.campaign.dynasty == 1
		and FileAccess.get_file_as_bytes(path) == bytes and secured.get_node("%SaveStatus").text == "Autosave on",
		"Campaign scene saves: preview open, cancel and Escape leave file bytes identical")
	secured.get_node("%TrainDrill").pressed.emit()
	check(secured.campaign.drill_rank == 1 and secured.campaign.legacy == 0
		and secured.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(secured, path),
		"Campaign scene saves: Train Drill autosaves the Legacy purchase")
	bytes = FileAccess.get_file_as_bytes(path)
	secured.get_node("%TrainDrill").pressed.emit()
	check(secured.campaign.drill_rank == 1 and FileAccess.get_file_as_bytes(path) == bytes,
		"Campaign scene saves: unaffordable Train Drill never writes")
	secured.get_node("%FoundDynasty").pressed.emit()
	secured.get_node("%ConfirmDynasty").pressed.emit()
	check(secured.campaign.dynasty == 2 and secured.get_node("%SaveStatus").text == "Saved" and scene_saved_exactly(secured, path),
		"Campaign scene saves: confirmed reset saved")
	secured.free()
	var successor := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	successor.get_node("%FoundDynasty").pressed.emit()
	check(successor.campaign.dynasty == 2 and successor.campaign.drill_rank == 1 and successor.campaign.legacy == 0
		and not successor.dynasty_preview_open and successor.get_node("%FoundDynasty").disabled
		and successor.get_node("%DynastyStatus").text == "Dynasty 2 · Legacy 0 · Drill rank 1 (×2 squad damage) · Securing this campaign earns 3 Legacy",
		"Campaign scene saves: relaunched successor keeps Legacy and Drill rank, reset waits for security")
	successor.free()
	check(FileAccess.get_file_as_bytes(progress_path) == v1_bytes and not FileAccess.file_exists(progress_path + ".tmp")
		and not FileAccess.file_exists(progress_path + ".bak"), "Campaign scene saves: sibling Save-v1 bytes untouched")
	check(fixture.cleanup() == OK, "Campaign scene saves: directory cleaned")

# A fresh scene with a fresh store stands in for a relaunch after a crash at each boundary.
func test_campaign_scene_interruptions() -> void:
	for action in ["purchase", "settlement", "dynasty"]:
		for boundary in ["before write", "between rotate and commit", "after commit"]:
			campaign_interruption(action, boundary)

func campaign_interruption_act(scene: CampaignPresentation, action: String) -> void:
	match action:
		"purchase":
			scene.upgrades[0].pressed.emit()
		"settlement":
			scene.advance_usec(CampaignPresentation.ROUND_USEC - scene.elapsed_usec)
		"dynasty":
			scene.get_node("%FoundDynasty").pressed.emit()
			scene.get_node("%ConfirmDynasty").pressed.emit()

func campaign_interruption(action: String, boundary: String) -> void:
	var title: String = "Campaign interruption %s %s: " % [action, boundary]
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, title + "isolated directory owned")
	if not fixture.owned:
		return
	var path: String = fixture.path
	var base: Campaign = state_secured() if action == "dynasty" else campaign_running(3 if action == "settlement" else 1, 7 if action == "settlement" else 100)
	var base_usec: int = 0 if action == "dynasty" else 400000
	if action == "dynasty":
		check(base.train_drill(), title + "earned Drill rank 1 before reset")
	check(CampaignSave.new(path).save_campaign(base, base_usec) == OK, title + "base saved")
	var base_state: Variant = CampaignState.capture(base, base_usec).state
	var base_bytes := FileAccess.get_file_as_bytes(path)
	var store := FailingCampaignSave.new(path)
	var scene := campaign_scene_new(CampaignPresentation, store)
	scene.advance_usec(0) # Consume the excluded first frame after load.
	if boundary == "before write":
		store.fail_write = true
	elif boundary == "between rotate and commit":
		store.fail_move_to = path # Commit and restore both fail: only the rotated backup remains.
	campaign_interruption_act(scene, action)
	var applied: Variant = scene_state(scene)
	var failed: bool = boundary != "after commit"
	check(applied != null and applied != base_state and scene.get_node("%SaveStatus").text == (
		"Progress not saved — will retry" if failed else "Saved"), title + "transition applied in memory with exact status")
	if boundary == "between rotate and commit":
		check(not FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path + ".bak") == base_bytes,
			title + "primary rotated to backup, commit missing")
	scene.free() # Crash: no close request.
	var relaunch := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	var status: String = relaunch.get_node("%SaveStatus").text
	if failed:
		check(scene_state(relaunch) == base_state and status == ("Restored from backup" if boundary == "between rotate and commit" else "Autosave on"),
			title + "relaunch restores the complete pre-transition state")
		relaunch.advance_usec(0)
		campaign_interruption_act(relaunch, action)
		check(scene_state(relaunch) == applied and relaunch.get_node("%SaveStatus").text == "Saved",
			title + "redo applies the transition exactly once")
	else:
		check(scene_state(relaunch) == applied and status == "Autosave on", title + "relaunch restores the complete transition")
	relaunch.free()
	var final := campaign_scene_new(CampaignPresentation, CampaignSave.new(path))
	var campaign := final.campaign
	match action:
		"purchase":
			check(campaign.levels == [2, 1, 1] and campaign.gold == 80, title + "paid exactly once")
		"settlement":
			check(campaign.border_cleared and campaign.gold == 17 and campaign.current_encounter == Data.Encounter.ARCHER_POSITION,
				title + "rewarded and routed exactly once")
		"dynasty":
			var damage: Array[int] = []
			for squad in campaign.battle.players:
				damage.append(squad.damage)
			final.get_node("%FoundDynasty").pressed.emit()
			check(campaign.dynasty == 2 and campaign.drill_rank == 1 and campaign.legacy == 0 and campaign.gold == 0
				and campaign.levels == [1, 1, 1] and damage == [8, 16, 12] and not campaign.can_found_dynasty()
				and not final.dynasty_preview_open,
				title + "single reset with exactly 2x Drill, no reset before security")
	check(scene_state(final) == applied, title + "final relaunch matches the single applied transition")
	final.free()
	check(fixture.cleanup() == OK, title + "directory cleaned")

func away_campaign(border: bool, archer: bool) -> Campaign:
	var campaign := Campaign.new()
	campaign.border_cleared = border # Pure rule fixture: only the clearance flags matter.
	campaign.archer_cleared = archer
	return campaign

func test_away_reward_rule() -> void:
	check(away_campaign(false, false).away_reward(3600) == 0, "Away reward: nothing cleared pays 0")
	check(away_campaign(true, false).away_reward(60) == 5, "Away reward: Border only, 60 s pays 5")
	check(away_campaign(true, true).away_reward(60) == 15, "Away reward: Archer, 60 s pays 15")
	check(away_campaign(true, true).away_reward(3) == 0 and away_campaign(true, true).away_reward(4) == 1,
		"Away reward: whole-gold floor (3 s pays 0, 4 s pays 1)")
	check(away_campaign(true, true).away_reward(Campaign.AWAY_CAP_SECONDS) == 7200
		and away_campaign(true, true).away_reward(30 * 3600) == 7200, "Away reward: 8 h and 30 h both cap at 7200")
	check(away_campaign(true, false).away_reward(30 * 3600) == 2400, "Away reward: Border cap is 2400")
	check(away_campaign(true, true).away_reward(-60) == 0 and away_campaign(true, true).away_reward(0) == 0,
		"Away reward: negative or zero time pays 0")

func test_away_reward_format() -> void:
	var CORRUPT := CampaignState.Outcome.CORRUPT
	var stamped: Dictionary = CampaignState.capture(campaign_running(), 250000, 1700000000).state
	var restored := CampaignState.restore(state_json(stamped))
	check(stamped.version == 4 and restored.outcome == CampaignState.Outcome.VALID and restored.saved_at == 1700000000
		and CampaignState.capture(restored.campaign, restored.round_progress_usec, restored.saved_at).state == stamped,
		"Away save: v4 round trip keeps saved_at exactly")
	state_rejects(stamped, "missing saved_at", CORRUPT, func(s: Dictionary) -> void: s.erase("saved_at"))
	state_rejects(stamped, "negative saved_at", CORRUPT, func(s: Dictionary) -> void: s.saved_at = -1)
	state_rejects(stamped, "fractional saved_at", CORRUPT, func(s: Dictionary) -> void: s.saved_at = 1.5)
	state_rejects(stamped, "string saved_at", CORRUPT, func(s: Dictionary) -> void: s.saved_at = "1700000000")
	state_rejects(stamped, "huge saved_at", CORRUPT, func(s: Dictionary) -> void: s.saved_at = ProgressSave.MAX_GOLD + 1)
	state_rejects(stamped, "v3 carrying saved_at", CORRUPT, func(s: Dictionary) -> void: s.version = 3)
	state_rejects(stamped, "version 5", CampaignState.Outcome.UNSUPPORTED, func(s: Dictionary) -> void: s.version = 5)
	# v1-v3 files migrate with an unknown (0) stamp, so they never pay an away reward.
	var secured: Dictionary = state_json(CampaignState.capture(state_secured(), 0, 1700000000).state)
	for old: Dictionary in [state_as_v3(secured), state_as_v2(secured), state_as_v1(secured)]:
		var migrated := CampaignState.restore(old)
		check(not old.has("saved_at") and migrated.outcome == CampaignState.Outcome.VALID and migrated.saved_at == 0,
			"Away save: v%d migrates with saved_at 0" % old.version)
	# On disk: a v3 file loads with stamp 0; the next save writes v4 with the store's clock.
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Away save: isolated directory owned")
	if not fixture.owned:
		return
	var v3_text := JSON.stringify(state_as_v3(secured))
	var store := ClockCampaignSave.new(fixture.path)
	store.now = 1700000500
	check(fixture.put(v3_text) == OK and store.load_campaign().get("saved_at", -1) == 0
		and FileAccess.get_file_as_string(fixture.path) == v3_text, "Away save: v3 file loads with saved_at 0, not rewritten")
	var loaded := store.load_campaign()
	var written: Variant = null
	if loaded.outcome == CampaignSave.Outcome.LOADED and store.save_campaign(loaded.campaign, loaded.round_progress_usec) == OK:
		written = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	var reloaded := CampaignSave.new(fixture.path).load_campaign()
	check(written != null and written.version == 4 and written.saved_at == 1700000500
		and reloaded.outcome == CampaignSave.Outcome.LOADED and reloaded.saved_at == 1700000500,
		"Away save: store with injected clock stamps and reloads saved_at exactly")
	check(fixture.cleanup() == OK, "Away save: directory cleaned")

# Archer and Border cleared by real battles, then one round into the Stronghold.
func away_archer_campaign() -> Campaign:
	var campaign := Campaign.new()
	campaign.gold = 240 # Isolated funds; every owned level uses production purchases.
	for role in range(3):
		campaign.purchase(role)
		campaign.purchase(role)
	campaign.restart_battle()
	campaign_finish(campaign)
	campaign_finish(campaign)
	campaign.battle.step_round()
	return campaign

func test_away_reward_scene() -> void:
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Away scene: isolated directory owned")
	if not fixture.owned:
		return
	var path: String = fixture.path
	var T: int = 1700003600
	var source := away_archer_campaign()
	var writer := ClockCampaignSave.new(path)
	writer.now = T - 3600
	check(source.archer_cleared and source.battle.result == Combat.Result.ONGOING
		and writer.save_campaign(source, 400000) == OK, "Away scene: Archer-cleared campaign saved an hour before launch")
	var before: Array = campaign_snapshot(source, false)
	var fixture_bytes := FileAccess.get_file_as_bytes(path)
	# Failing save: the grant is reverted and the file is untouched, so nothing can pay twice.
	var failing := ClockCampaignSave.new(path)
	failing.now = T
	failing.fail_write = true
	var refused := campaign_scene_new(CampaignPresentation, failing)
	check(refused.campaign.gold == source.gold and campaign_snapshot(refused.campaign, false) == before
		and refused.elapsed_usec == 400000
		and refused.get_node("%LastResult").text == "Away reward waits for a successful save"
		and FileAccess.get_file_as_bytes(path) == fixture_bytes,
		"Away scene: failed save reverts the grant and leaves the file byte-identical")
	refused.free()
	# Successful grant: +900 gold (3600 s at 30 gold per 120 s), battle untouched, file re-stamped.
	var clock := ClockCampaignSave.new(path)
	clock.now = T
	var scene := campaign_scene_new(CampaignPresentation, clock)
	var on_disk := CampaignSave.new(path).load_campaign()
	var granted: Array = campaign_snapshot(scene.campaign, false)
	granted[0] -= 900 # Gold is the only field the reward may change.
	check(scene.campaign.gold == source.gold + 900 and granted == before
		and scene.elapsed_usec == 400000 and scene.skip_resume_frame
		and scene.get_node("%LastResult").text == "Away 1h 0m · +900 gold from secured territory (cap 8h)"
		and scene.get_node("%SaveStatus").text == "Saved",
		"Away scene: an hour away grants 900 gold with the welcome-back line, combat untouched")
	check(on_disk.outcome == CampaignSave.Outcome.LOADED and on_disk.saved_at == T
		and on_disk.campaign.gold == source.gold + 900 and on_disk.round_progress_usec == 400000,
		"Away scene: granted gold committed with the new stamp")
	scene.advance_usec(9000000)
	check(scene.campaign.battle.rounds == 1, "Away scene: first frame after load still adds no rounds")
	scene.free()
	# Relaunch at the same time: no double grant.
	var again := campaign_scene_new(CampaignPresentation, clock)
	check(again.campaign.gold == source.gold + 900 and again.get_node("%LastResult").text == "Resumed saved campaign",
		"Away scene: relaunch at the same time grants nothing more")
	again.free()
	# Clock moved backwards: nothing granted.
	clock.now = T - 7200
	var backwards := campaign_scene_new(CampaignPresentation, clock)
	check(backwards.campaign.gold == source.gold + 900 and backwards.get_node("%LastResult").text == "Resumed saved campaign",
		"Away scene: clock moved backwards grants nothing")
	backwards.free()
	# Transient failure, then retry: the pending reward rides the next ordinary save with the new stamp.
	var stamped_text := fixture_bytes.get_string_from_utf8()
	var retry := ClockCampaignSave.new(path)
	retry.now = T
	retry.fail_write = true
	check(fixture.put(stamped_text) == OK, "Away scene: hour-old save restored for retry")
	var pending := campaign_scene_new(CampaignPresentation, retry)
	check(pending.campaign.gold == source.gold and pending.pending_away_reward == 900 and pending.saving_enabled
		and pending.get_node("%LastResult").text == "Away reward waits for a successful save"
		and FileAccess.get_file_as_bytes(path) == fixture_bytes,
		"Away scene: first failed write keeps the reward pending, gold and file unchanged")
	check(not pending._save_campaign() and pending.campaign.gold == source.gold and pending.pending_away_reward == 900
		and FileAccess.get_file_as_bytes(path) == fixture_bytes,
		"Away scene: a further failed save neither writes nor pays the pending reward")
	retry.fail_write = false
	var retried: bool = pending._save_campaign()
	var retried_disk := CampaignSave.new(path).load_campaign()
	check(retried and pending.campaign.gold == source.gold + 900 and pending.pending_away_reward == 0
		and pending.get_node("%LastResult").text == "Away 1h 0m · +900 gold from secured territory (cap 8h)"
		and retried_disk.outcome == CampaignSave.Outcome.LOADED and retried_disk.saved_at == T
		and retried_disk.campaign.gold == source.gold + 900 and retried_disk.round_progress_usec == 400000,
		"Away scene: next successful save commits +900 gold with the new stamp")
	check(pending._save_campaign() and pending.campaign.gold == source.gold + 900
		and CampaignSave.new(path).load_campaign().campaign.gold == source.gold + 900,
		"Away scene: later saves do not add the reward again")
	pending.free()
	var after_retry := campaign_scene_new(CampaignPresentation, retry)
	check(after_retry.campaign.gold == source.gold + 900 and after_retry.pending_away_reward == 0
		and after_retry.get_node("%LastResult").text == "Resumed saved campaign",
		"Away scene: relaunch after the retried grant pays nothing more")
	after_retry.free()
	# Saving disabled after a failed grant: the pending reward is dropped, never written.
	var doomed := ClockCampaignSave.new(path)
	doomed.now = T
	doomed.fail_write = true
	check(fixture.put(stamped_text) == OK, "Away scene: hour-old save restored for disabled case")
	var dropped := campaign_scene_new(CampaignPresentation, doomed)
	check(dropped.pending_away_reward == 900, "Away scene: disabled case starts with the reward pending")
	doomed.fail_write = false
	check(fixture.put("{") == OK, "Away scene: campaign file damaged mid-session")
	check(not dropped._save_campaign() and not dropped.saving_enabled and dropped.pending_away_reward == 0
		and dropped.campaign.gold == source.gold
		and dropped.get_node("%LastResult").text == "Away reward cannot be kept this session"
		and FileAccess.get_file_as_string(path) == "{",
		"Away scene: saving disabled drops the pending reward and says it cannot be kept")
	dropped.free()
	# Backup-only launch: the grant's save must not hide that the backup was restored.
	check(fixture.put(stamped_text) == OK, "Away scene: hour-old save restored for backup case")
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	check(DirAccess.rename_absolute(path, path + ".bak") == OK and not FileAccess.file_exists(path),
		"Away scene: only the hour-old backup exists")
	var backup_clock := ClockCampaignSave.new(path)
	backup_clock.now = T
	var from_backup := campaign_scene_new(CampaignPresentation, backup_clock)
	var backup_disk := CampaignSave.new(path).load_campaign()
	check(from_backup.campaign.gold == source.gold + 900 and from_backup.pending_away_reward == 0
		and from_backup.get_node("%LastResult").text == "Away 1h 0m · +900 gold from secured territory (cap 8h)"
		and from_backup.get_node("%SaveStatus").text == "Restored from backup · Saved",
		"Away scene: backup restore stays visible after the grant's save")
	check(backup_disk.outcome == CampaignSave.Outcome.LOADED and not backup_disk.get("recovered", false)
		and backup_disk.saved_at == T and backup_disk.campaign.gold == source.gold + 900,
		"Away scene: backup grant writes a new primary with the new stamp")
	from_backup.free()
	check(fixture.cleanup() == OK, "Away scene: directory cleaned")

func campaign_scene_new(script: GDScript = CampaignPresentation, store: CampaignSave = null) -> CampaignPresentation:
	var scene: CampaignPresentation = CampaignScene.instantiate()
	if script != CampaignPresentation:
		scene.set_script(script)
	# Never touch the player's real campaign save: null (disabled) or an isolated fixture store.
	scene.campaign_save = store
	root.add_child(scene)
	scene.set_process(false)
	return scene

func campaign_scene_finish(scene: CampaignPresentation) -> Combat:
	var completed := scene.campaign.battle
	for i in range(60):
		if scene.campaign.battle != completed or scene.campaign.phase in [Campaign.Phase.CONQUEST_CLEARED, Campaign.Phase.CAMPAIGN_SECURED]:
			break
		scene.advance_time(1.0)
	check(completed.result != Combat.Result.ONGOING,
		"Campaign scene: production timing completes real battle within sixty rounds")
	# Successor routing enables processing; keep logical-time fixtures deterministic.
	scene.set_process(false)
	return completed

func test_campaign_scene_dynasty() -> void:
	var scene := campaign_scene_new(CampaignWindowFixture) as CampaignWindowFixture
	var campaign := scene.campaign
	var before := campaign_snapshot(campaign)
	for name in ["FoundDynasty", "ConfirmDynasty", "CancelDynasty", "TrainDrill"]:
		scene.get_node("%" + name).pressed.emit()
	check(campaign_snapshot(campaign) == before and not scene.dynasty_preview_open
		and scene.get_node("%TrainDrill").disabled and scene.get_node("%TrainDrill").text == "Train Drill rank 1 — 10 Legacy"
		and scene.get_node("%DynastyStatus").text == "Dynasty 1 · Legacy 0 · Drill rank 0 (×1 squad damage) · Securing this campaign earns 10 Legacy",
		"Dynasty scene: premature emitted reset and training actions reject")
	# Earn funds through real scene rounds; leave a gate upgrade affordable at security.
	campaign_scene_finish(scene)
	scene.get_node("%FarmBorder").pressed.emit()
	campaign_scene_finish(scene)
	for i in range(40):
		if campaign.gold >= 260:
			break
		campaign_scene_finish(scene)
	check(campaign.gold >= 260, "Dynasty scene: earned preparation wallet")
	scene.get_node("%GateUpgrade").pressed.emit()
	for button in scene.upgrades:
		button.pressed.emit()
		button.pressed.emit()
	scene.get_node("%Frontier").pressed.emit()
	campaign_scene_finish(scene)
	for i in range(4):
		if campaign.phase != Campaign.Phase.RUNNING:
			break
		campaign_scene_finish(scene)
	scene.get_node("%StartDefense").pressed.emit()
	var defense := campaign_scene_finish(scene)
	check(campaign.can_found_dynasty() and defense.result == Combat.Result.VICTORY and campaign.legacy == 10
		and not scene.get_node("%TrainDrill").disabled
		and scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated · +10 Legacy earned"
		and scene.get_node("%DynastyStatus").text == "Dynasty 1 · Legacy 10 · Drill rank 0 (×1 squad damage)",
		"Dynasty scene: real earned conquest and defense enable reset and pay 10 Legacy")
	scene.get_node("%TrainDrill").pressed.emit()
	check(campaign.drill_rank == 1 and campaign.legacy == 0 and scene.get_node("%TrainDrill").disabled
		and scene.get_node("%TrainDrill").text == "Train Drill rank 2 — 20 Legacy"
		and scene.get_node("%DynastyStatus").text == "Dynasty 1 · Legacy 0 · Drill rank 1 (×2 squad damage)"
		and defense.players[0].damage == campaign.battle.players[0].damage,
		"Dynasty scene: Train Drill buys rank 1 without touching the settled battle")
	scene.elapsed_usec = 345678
	scene.last_frame_usec = 1
	before = campaign_snapshot(campaign)
	scene.get_node("%ConfirmDynasty").pressed.emit()
	check(campaign_snapshot(campaign) == before, "Dynasty scene: confirm without preview rejects")
	scene.get_node("%FoundDynasty").pressed.emit()
	check(scene.dynasty_preview_open and scene.get_node("%DynastyPreview").visible
		and scene.get_viewport().gui_get_focus_owner() == scene.get_node("%CancelDynasty")
		and scene.get_node("Margin/Scroll").follow_focus
		and scene.elapsed_usec == 345678 and scene.last_frame_usec == 1
		and campaign_snapshot(campaign) == before, "Dynasty scene: preview focuses native cancel without gameplay or clock mutation")
	var copy: String = scene.get_node("%DynastyLosses").text
	for text in ["%d gold" % campaign.gold, "Shield infantry Lv.3", "Foot archers Lv.3", "Horse archers Lv.3",
		"Gate Lv.2", "return to level 1", "territory and security", "Border Skirmish in Advance",
		"fresh full-health troops", "pending commands", "farming/navigation", "fractional round time",
		"same three troop types", "Keep Legacy 0 and Drill rank 1 (×2 squad damage after level additions)",
		"health, gold rewards and round frequency are unchanged", "Next secured campaign earns 3 Legacy",
		"Legacy and Drill rank are kept in the campaign save", "main-game saves are untouched"]:
		check(copy.contains(text), "Dynasty scene: preview discloses " + text)
	check(not copy.contains("only dynasty reset")
		and scene.get_node("%ConfirmDynasty").text == "Confirm reset — start dynasty 2",
		"Dynasty scene: preview is repeatable and names the next dynasty")
	# Threat choice: defaults to the safe 0, clamps to one above the best secured, never mutates play.
	check(scene.preview_threat == 0 and scene.get_node("%ThreatDown").disabled and not scene.get_node("%ThreatUp").disabled
		and scene.get_node("%ThreatChoice").text.contains("New dynasty Threat 0 (up to 1)")
		and scene.get_node("%ThreatChoice").text.contains("securing it earns 3 Legacy")
		and scene.get_node("%ThreatChoice").text.contains("Threat 0 is always available"),
		"Threat scene: preview defaults to Threat 0 with up to 1 unlocked")
	scene.get_node("%ThreatUp").pressed.emit()
	scene.get_node("%ThreatUp").pressed.emit()
	check(scene.preview_threat == 1 and scene.get_node("%ThreatUp").disabled and not scene.get_node("%ThreatDown").disabled
		and scene.get_node("%ThreatChoice").text.contains("enemies +25% health and damage; securing it earns 6 Legacy")
		and scene.get_node("%DynastyLosses").text.contains("Next secured campaign earns 6 Legacy")
		and campaign_snapshot(campaign) == before and scene.elapsed_usec == 345678,
		"Threat scene: raise clamps at 1 above best and updates payout without mutation")
	scene.get_node("%ThreatDown").pressed.emit()
	scene.get_node("%ThreatDown").pressed.emit()
	check(scene.preview_threat == 0 and scene.get_node("%DynastyLosses").text.contains("Next secured campaign earns 3 Legacy"),
		"Threat scene: lower clamps at Threat 0")
	scene.set_reason(0, true)
	scene.get_node("%ThreatUp").pressed.emit()
	check(scene.preview_threat == 0 and scene.get_node("%ThreatUp").disabled, "Threat scene: suspended raise rejected")
	scene.set_reason(0, false)
	for name in ["GateUpgrade", "ShieldUpgrade", "FootUpgrade", "HorseUpgrade", "FarmBorder", "FarmArcher", "Frontier", "StartDefense", "FoundDynasty", "TrainDrill"]:
		check(scene.get_node("%" + name).disabled, "Dynasty scene: preview disables " + name)
		scene.get_node("%" + name).pressed.emit()
	check(campaign_snapshot(campaign) == before, "Dynasty scene: emitted blocked signals preserve preview losses")
	scene.get_node("%CancelDynasty").pressed.emit()
	check(not scene.dynasty_preview_open and campaign_snapshot(campaign) == before
		and scene.elapsed_usec == 345678 and not scene.get_node("%GateUpgrade").disabled
		and scene.get_viewport().gui_get_focus_owner() == scene.get_node("%FoundDynasty"),
		"Dynasty scene: cancel restores secured ownership controls and focus")
	scene.get_node("%FoundDynasty").pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	scene._input(escape)
	check(not scene.dynasty_preview_open and campaign_snapshot(campaign) == before
		and scene.elapsed_usec == 345678, "Dynasty scene: Escape dismisses without gameplay mutation")
	# Every lifecycle reason rejects opening and confirmation; overlapping reasons stay authoritative.
	for reason in range(3):
		scene.set_reason(reason, true)
		scene.get_node("%FoundDynasty").pressed.emit()
		check(not scene.dynasty_preview_open, "Dynasty scene: suspended opening rejected")
		scene.set_reason(reason, false)
	scene.get_node("%FoundDynasty").pressed.emit()
	for reason in range(3):
		scene.set_reason(reason, true)
	for reason in range(3):
		for name in ["ConfirmDynasty", "CancelDynasty", "GateUpgrade", "FarmBorder"]:
			scene.get_node("%" + name).pressed.emit()
		scene.advance_time(120.0)
		check(scene.suspended and scene.dynasty_preview_open and campaign_snapshot(campaign) == before
			and scene.elapsed_usec == 345678, "Dynasty scene: conflicting suspension rejects preview actions and time")
		scene.set_reason(reason, false)
	# Fresh model eligibility is checked even when a previously enabled signal is emitted.
	campaign.border_cleared = false
	var stale := campaign_snapshot(campaign)
	scene.get_node("%ConfirmDynasty").pressed.emit()
	check(campaign_snapshot(campaign) == stale and scene.dynasty_preview_open,
		"Dynasty scene: stale model eligibility rejects confirmation")
	campaign.border_cleared = true
	var now := Time.get_ticks_usec()
	scene.get_node("%ConfirmDynasty").pressed.emit()
	var successor := campaign.battle
	check(successor != defense and campaign.dynasty == 2 and campaign.gold == 0
		and campaign.levels == [1, 1, 1] and campaign.gate_level == 1
		and scene.elapsed_usec == 0 and scene.last_frame_usec >= now and successor.rounds == 0
		and scene.is_processing() and scene.skip_resume_frame and not scene.dynasty_preview_open
		and scene.get_node("%LastResult").text == "No completed battle"
		and scene.get_node("%DynastyStatus").text == "Dynasty 2 · Legacy 0 · Drill rank 1 (×2 squad damage) · Securing this campaign earns 3 Legacy",
		"Dynasty scene: single clean-clock successor preserves resume gate and clears old presentation")
	before = campaign_snapshot(campaign)
	for name in ["ConfirmDynasty", "FoundDynasty", "CancelDynasty", "ConfirmDynasty"]:
		scene.get_node("%" + name).pressed.emit()
	check(campaign_snapshot(campaign) == before and not campaign.settle(defense),
		"Dynasty scene: duplicate and stale signals cannot restart or settle old defense")
	scene.advance_foreground(scene.last_frame_usec + 9000000)
	check(successor.rounds == 0 and scene.elapsed_usec == 0 and not scene.skip_resume_frame,
		"Dynasty scene: first resumed triggering gap excluded")
	scene.advance_usec(999999)
	check(successor.rounds == 0, "Dynasty scene: successor retains one-second round frequency")
	scene.advance_usec(1)
	check(successor.rounds == 1 and successor.enemies[0].health == 36,
		"Dynasty scene: successor passive first round deals doubled damage")
	scene.advance_time(1.0)
	check(successor.rounds == 2 and successor.result == Combat.Result.VICTORY and campaign.gold == 10,
		"Dynasty scene: passive successor victory pays ordinary reward after two rounds")
	var fresh := campaign_scene_new()
	check(fresh.campaign.dynasty == 1 and fresh.campaign.drill_rank == 0 and fresh.campaign.legacy == 0
		and fresh.campaign.battle.players[0].damage == 4 and not fresh.dynasty_preview_open,
		"Dynasty scene: concurrent fresh instance has no Legacy or Drill")
	fresh.free()
	dynasty_prepare(campaign)
	scene._refresh()
	scene.get_node("%StartDefense").pressed.emit()
	campaign_scene_finish(scene)
	check(scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated · +3 Legacy earned"
		and campaign.legacy == 3 and not scene.get_node("%FoundDynasty").disabled
		and scene.get_node("%TrainDrill").disabled and not scene.is_processing()
		and scene.get_node("%DynastyStatus").text == "Dynasty 2 · Legacy 3 · Drill rank 1 (×2 squad damage)",
		"Dynasty scene: real successor security pays 3 Legacy and offers another reset")
	scene.get_node("%FoundDynasty").pressed.emit()
	check(scene.dynasty_preview_open and scene.get_node("%ConfirmDynasty").text == "Confirm reset — start dynasty 3",
		"Dynasty scene: repeat preview offers dynasty 3")
	scene.get_node("%ThreatUp").pressed.emit()
	scene.get_node("%ConfirmDynasty").pressed.emit()
	check(campaign.dynasty == 3 and campaign.legacy == 3 and campaign.drill_rank == 1 and not scene.dynasty_preview_open
		and campaign.threat == 1 and campaign.battle.enemies[0].max_health == 90
		and scene.get_node("%ThreatStatus").text == "Threat 1 (enemies +25% health and damage) · Best secured Threat 0"
		and scene.get_node("%DynastyStatus").text.ends_with("Securing this campaign earns 6 Legacy"),
		"Dynasty scene: repeat reset starts dynasty 3 at the chosen Threat keeping Legacy and rank")
	scene.free()

func test_campaign_scene_fresh() -> void:
	var scene := campaign_scene_new()
	check(scene.get_node("%Title").text == "Campaign prototype"
		and scene.get_node("%SessionNotice").visible
		and scene.get_node("%SessionNotice").text == "Campaign progress autosaves to its own file. Main-game saves are not loaded or changed."
		and scene.get_node("%SaveStatus").text == "Saving disabled for isolated test",
		"Campaign scene: permanent autosave notice, isolated save status and title")
	check(scene.campaign.gold == 0 and scene.campaign.levels == [1, 1, 1]
		and scene.campaign.current_encounter == 0 and scene.campaign.battle.rounds == 0
		and scene.get_node("%CampaignStatus").text == "Border Skirmish · Advance · Running"
		and scene.get_node("%Gold").text == "Gold: 0"
		and scene.get_node("%PendingNavigation").text == "No queued navigation",
		"Campaign scene: fresh Border ownership and labels")
	for name in ["FarmBorder", "FarmArcher", "Frontier", "StartDefense", "GateUpgrade", "ShieldUpgrade", "FootUpgrade", "HorseUpgrade"]:
		var button: Button = scene.get_node("%" + name)
		check(button.disabled and button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS,
			"Campaign scene: initially disabled on-press control " + name)
		var before := campaign_snapshot(scene.campaign)
		button.pressed.emit()
		check(campaign_snapshot(scene.campaign) == before,
			"Campaign scene: controller rejects emitted locked control " + name)
	for button in scene.upgrades:
		check(button.text.contains("Lv.1") and button.text.contains("20 gold"),
			"Campaign scene: starting owned level and cost")
	campaign_scene_finish(scene)
	var other := campaign_scene_new()
	check(other.campaign != scene.campaign and other.campaign.gold == 0
		and other.campaign.levels == [1, 1, 1] and not other.campaign.border_cleared
		and other.campaign.battle.players[0] != scene.campaign.battle.players[0],
		"Campaign scene: concurrent instance starts independent session")
	scene.free()
	other.free()

func test_campaign_scene_progression() -> void:
	var scene := campaign_scene_new()
	var border := scene.campaign.battle
	scene.advance_time(120.0)
	campaign_fresh(scene.campaign, border, Data.Encounter.ARCHER_POSITION)
	check(border.rounds == 4 and scene.campaign.gold == 10 and scene.elapsed_usec == 0
		and scene.get_node("%LastResult").text == "Border Skirmish: Victory · +10 gold"
		and scene.get_node("%CampaignStatus").text == "Archer Position · Advance · Running"
		and scene.get_node("%Round").text == "Round: 0"
		and not scene.get_node("%FarmBorder").disabled and scene.get_node("%FarmArcher").disabled,
		"Campaign scene: large delta pays Border once without consuming successor")
	scene.advance_time(1.0)
	check(scene.get_node("%LastResult").text == "Border Skirmish: Victory · +10 gold"
		and scene.get_node("%Round").text == "Round: 1",
		"Campaign scene: previous result retained during next battle")
	var archer := campaign_scene_finish(scene)
	campaign_fresh(scene.campaign, archer, Data.Encounter.STRONGHOLD)
	check(scene.campaign.gold == 40 and scene.get_node("%Gold").text == "Gold: 40"
		and scene.get_node("%LastResult").text == "Archer Position: Victory · +30 gold"
		and scene.get_node("%CampaignStatus").text == "Stronghold · Advance · Running",
		"Campaign scene: Archer pays thirty and advances directly to Stronghold, not Fortified")
	var enemy_text: String = scene.get_node("%Enemies").text
	check(scene.campaign.battle.enemies.size() == 3 and enemy_text.split("\n").size() == 4,
		"Campaign scene: all three Stronghold enemy rows rendered")
	for squad in scene.campaign.battle.enemies:
		check(enemy_text.contains("%s | HP %d / %d | Damage %d" % [
			squad.title, squad.health, squad.max_health, squad.damage]),
			"Campaign scene: actual Stronghold squad stats " + squad.title)
	var stronghold := campaign_scene_finish(scene)
	campaign_fresh(scene.campaign, stronghold, Data.Encounter.ARCHER_POSITION)
	check(stronghold.result == Combat.Result.DEFEAT and scene.campaign.gold == 40
		and scene.campaign.mode == Campaign.Mode.FARM
		and scene.get_node("%LastResult").text == "Stronghold: Defeat · +0 gold"
		and scene.get_node("%CampaignStatus").text == "Archer Position · Farm · Running"
		and not scene.get_node("%Frontier").disabled,
		"Campaign scene: real Stronghold defeat pays zero and renders highest-cleared farm")
	scene.free()

func test_campaign_scene_navigation() -> void:
	var scene := campaign_scene_new()
	campaign_scene_finish(scene)
	scene.advance_time(0.25)
	var combat := scene.campaign.battle
	var stats: Array = campaign_snapshot(scene.campaign)[17]
	var clock: int = scene.last_frame_usec
	scene.get_node("%FarmBorder").pressed.emit()
	check(scene.campaign.battle == combat and campaign_snapshot(scene.campaign)[17] == stats
		and combat.rounds == 0 and scene.campaign.gold == 10 and scene.elapsed_usec == 250000
		and scene.last_frame_usec == clock
		and scene.get_node("%PendingNavigation").text == "Farm Border Skirmish after this battle",
		"Campaign scene: farm request updates pending label without battle, funds or timing mutation")
	var before := campaign_snapshot(scene.campaign)
	scene.get_node("%FarmArcher").pressed.emit()
	scene.get_node("%Frontier").pressed.emit()
	scene._request_farm(Data.Encounter.FORTIFIED_POSITION)
	scene._request_farm(Data.Encounter.STRONGHOLD)
	scene._request_farm(-1)
	check(campaign_snapshot(scene.campaign) == before
		and scene.get_node("%PendingNavigation").text == "Farm Border Skirmish after this battle",
		"Campaign scene: rejected locked/invalid navigation preserves valid intent")
	campaign_scene_finish(scene)
	campaign_fresh(scene.campaign, combat, Data.Encounter.BORDER_SKIRMISH)
	check(scene.campaign.gold == 40 and scene.campaign.mode == Campaign.Mode.FARM
		and scene.get_node("%PendingNavigation").text == "No queued navigation",
		"Campaign scene: requested farm begins only after Archer reward")
	campaign_scene_finish(scene)
	check(scene.campaign.gold == 50 and scene.campaign.current_encounter == 0,
		"Campaign scene: ordinary farming repeats and pays again")
	scene.get_node("%FarmArcher").pressed.emit()
	scene.get_node("%Frontier").pressed.emit()
	check(scene.campaign.pending_navigation == Campaign.Navigation.FRONTIER
		and scene.get_node("%PendingNavigation").text == "Retry frontier after this battle",
		"Campaign scene: frontier replaces valid farm intent")
	scene.get_node("%FarmArcher").pressed.emit()
	check(scene.campaign.pending_navigation == Campaign.Navigation.FARM and scene.campaign.pending_farm == 1,
		"Campaign scene: latest farm replaces frontier intent")
	campaign_scene_finish(scene)
	check(scene.campaign.current_encounter == 1 and scene.campaign.gold == 60,
		"Campaign scene: latest valid farm target wins at settlement")
	scene.get_node("%Frontier").pressed.emit()
	combat = campaign_scene_finish(scene)
	campaign_fresh(scene.campaign, combat, Data.Encounter.STRONGHOLD)
	check(scene.campaign.gold == 90 and scene.campaign.mode == Campaign.Mode.ADVANCE
		and scene.get_node("%PendingNavigation").text == "No queued navigation",
		"Campaign scene: frontier waits for legitimate farm reward then retries unresolved Stronghold")
	scene.free()

func test_campaign_scene_purchases() -> void:
	var scene := campaign_scene_new()
	scene.campaign.gold = 60 # Isolated fixture funds, never production defaults.
	scene._refresh()
	var combat := scene.campaign.battle
	var stats: Array = campaign_snapshot(scene.campaign)[17]
	check(not scene.get_node("%FootUpgrade").disabled, "Campaign scene: affordable purchase enabled")
	scene.get_node("%FootUpgrade").pressed.emit()
	check(scene.campaign.gold == 40 and scene.campaign.levels == [1, 2, 1]
		and scene.get_node("%Gold").text == "Gold: 40"
		and scene.get_node("%FootUpgrade").text == "Foot archers Lv.2 · Upgrade 40 gold"
		and not scene.get_node("%FootUpgrade").disabled
		and scene.campaign.battle == combat and campaign_snapshot(scene.campaign)[17] == stats,
		"Campaign scene: purchase updates ownership/wallet/cost, not active stats")
	scene.get_node("%FootUpgrade").pressed.emit()
	check(scene.campaign.gold == 0 and scene.campaign.levels == [1, 3, 1]
		and scene.get_node("%FootUpgrade").text == "Foot archers Lv.3 · MAX"
		and scene.get_node("%FootUpgrade").disabled and scene.get_node("%ShieldUpgrade").disabled
		and campaign_snapshot(scene.campaign)[17] == stats,
		"Campaign scene: cap and empty wallet disable controls without changing active snapshot")
	var before := campaign_snapshot(scene.campaign)
	scene.get_node("%FootUpgrade").pressed.emit()
	scene.get_node("%ShieldUpgrade").pressed.emit()
	scene._purchase(-1)
	scene._purchase(3)
	check(campaign_snapshot(scene.campaign) == before,
		"Campaign scene: capped, insufficient and invalid purchases inert even without physical gating")
	campaign_scene_finish(scene)
	check(scene.campaign.battle.players[1].health == 64 and scene.campaign.battle.players[1].damage == 16
		and scene.campaign.gold == 10 and scene.get_node("%Army").text.contains("HP 64 / 64 | Damage 16"),
		"Campaign scene: next battle renders purchased full-health snapshot")
	scene.free()

func test_campaign_scene_checkpoint() -> void:
	var scene := campaign_scene_new()
	scene.campaign.gold = 180 # Only this instance is funded for a real upgraded conquest.
	for button in scene.upgrades:
		button.pressed.emit()
		button.pressed.emit()
	check(scene.campaign.levels == [3, 3, 3] and scene.campaign.gold == 0,
		"Campaign scene: all upgrade buttons purchase through production connections")
	campaign_scene_finish(scene)
	campaign_scene_finish(scene)
	scene.get_node("%FarmBorder").pressed.emit()
	var stronghold := scene.campaign.battle
	for i in range(60):
		if scene.campaign.phase in [Campaign.Phase.CONQUEST_CLEARED, Campaign.Phase.CAMPAIGN_SECURED]:
			break
		scene.advance_time(1.0)
	check(stronghold.result == Combat.Result.VICTORY and scene.campaign.gold == 70
		and scene.campaign.phase == Campaign.Phase.CONQUEST_CLEARED
		and scene.campaign.battle == stronghold and not scene.is_processing()
		and scene.campaign.pending_navigation == Campaign.Navigation.NONE
		and scene.campaign.pending_farm == -1 and scene.elapsed_usec == 0
		and scene.get_node("%LastResult").text == "Stronghold: Victory · +30 gold"
		and scene.get_node("%CampaignStatus").text.contains("Conquest cleared — prepare upgrades, then Start Defense; ordinary farming remains available")
		and scene.get_node("%PendingNavigation").text == "No queued navigation",
		"Campaign scene: real conquest pays thirty once, clears intent, retains terminal display and stops processing")
	check(scene.get_node("%Frontier").disabled and not scene.get_node("%FarmBorder").disabled
		and not scene.get_node("%FarmArcher").disabled
		and scene.get_node("%Frontier").text == "Return to cleared checkpoint after battle",
		"Campaign scene: checkpoint frontier is disabled no-op, ordinary farms remain available")
	var before := campaign_snapshot(scene.campaign)
	for i in range(3):
		scene.advance_time(120.0)
		scene.get_node("%Frontier").pressed.emit()
	check(campaign_snapshot(scene.campaign) == before and scene.elapsed_usec == 0,
		"Campaign scene: repeated checkpoint time and frontier emission cannot repay or tick")
	scene.last_frame_usec = 1
	var clock_before: int = Time.get_ticks_usec()
	scene.get_node("%FarmArcher").pressed.emit()
	campaign_fresh(scene.campaign, stronghold, Data.Encounter.ARCHER_POSITION)
	check(scene.is_processing() and scene.last_frame_usec >= clock_before and scene.elapsed_usec == 0
		and scene.campaign.gold == 70 and scene.campaign.stronghold_cleared,
		"Campaign scene: leaving checkpoint resumes with clean clock and no reward")
	scene.set_process(false)
	scene.advance_foreground(scene.last_frame_usec + 250000)
	check(scene.campaign.battle.rounds == 0 and scene.elapsed_usec == 250000,
		"Campaign scene: no stale checkpoint gap consumed after farming starts")
	scene.get_node("%Frontier").pressed.emit()
	var farm := scene.campaign.battle
	for i in range(60):
		if scene.campaign.phase in [Campaign.Phase.CONQUEST_CLEARED, Campaign.Phase.CAMPAIGN_SECURED]:
			break
		scene.advance_time(1.0)
	check(scene.campaign.phase == Campaign.Phase.CONQUEST_CLEARED and scene.campaign.battle == farm
		and farm != stronghold and scene.campaign.current_encounter == 1 and scene.campaign.gold == 100
		and not scene.is_processing() and scene.get_node("%LastResult").text == "Archer Position: Victory · +30 gold",
		"Campaign scene: farm reward returns to checkpoint without Stronghold recreation or repayment")
	before = campaign_snapshot(scene.campaign)
	scene.advance_time(120.0)
	check(campaign_snapshot(scene.campaign) == before, "Campaign scene: returned checkpoint remains frozen")
	var old_squad := scene.campaign.battle.players[0]
	scene.free()
	var recreated := campaign_scene_new()
	check(recreated.campaign.gold == 0 and recreated.campaign.levels == [1, 1, 1]
		and not recreated.campaign.border_cleared and not recreated.campaign.archer_cleared
		and not recreated.campaign.stronghold_cleared and recreated.campaign.battle.players[0] != old_squad,
		"Campaign scene: removal and recreation discard wallet, clearances and squad instances")
	recreated.free()

func test_campaign_scene_lifecycle() -> void:
	for pair in [[MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN],
		[MainLoop.NOTIFICATION_APPLICATION_PAUSED, MainLoop.NOTIFICATION_APPLICATION_RESUMED]]:
		var scene := campaign_scene_new()
		campaign_scene_finish(scene)
		campaign_scene_finish(scene)
		campaign_scene_finish(scene) # Real defeat enables farm and frontier controls.
		scene.advance_foreground(scene.last_frame_usec + 250000)
		var before := campaign_snapshot(scene.campaign)
		scene.notification(pair[0])
		check(scene.suspended and scene.get_node("%CampaignStatus").text.contains("Paused"),
			"Campaign scene: lifecycle suspension displayed")
		for name in ["FarmBorder", "FarmArcher", "Frontier", "StartDefense", "GateUpgrade", "ShieldUpgrade", "FootUpgrade", "HorseUpgrade"]:
			var button: Button = scene.get_node("%" + name)
			check(button.disabled, "Campaign scene: suspended control disabled " + name)
			button.pressed.emit()
		scene.advance_foreground(scene.last_frame_usec + 9000000)
		scene.advance_time(120.0)
		check(campaign_snapshot(scene.campaign) == before and scene.elapsed_usec == 250000,
			"Campaign scene: suspension freezes rounds, funds, ownership, navigation and partial time")
		scene.notification(pair[1])
		check(not scene.suspended and scene.skip_resume_frame
			and not scene.get_node("%FarmBorder").disabled and not scene.get_node("%Frontier").disabled
			and not scene.get_node("%ShieldUpgrade").disabled,
			"Campaign scene: resume restores eligible controls without bypass")
		scene.advance_foreground(scene.last_frame_usec + 9000000)
		check(not scene.skip_resume_frame and campaign_snapshot(scene.campaign) == before
			and scene.elapsed_usec == 250000, "Campaign scene: stale resume frame excluded")
		scene.advance_foreground(scene.last_frame_usec + 749999)
		check(scene.campaign.battle.rounds == 0 and scene.elapsed_usec == 999999,
			"Campaign scene: preserved fraction does not round early")
		scene.advance_foreground(scene.last_frame_usec + 1)
		check(scene.campaign.battle.rounds == 1 and scene.elapsed_usec == 0,
			"Campaign scene: exact remaining foreground microsecond progresses normally")
		scene.advance_foreground(scene.last_frame_usec)
		check(scene.campaign.battle.rounds == 1 and scene.elapsed_usec == 0,
			"Campaign scene: same timestamp cannot consume elapsed span twice")
		scene.free()

func campaign_scene_defense_ready(script: GDScript = CampaignPresentation) -> CampaignPresentation:
	var scene := campaign_scene_new(script)
	scene.campaign.gold = 180 # Isolated affordability fixture; conquest uses real rounds.
	for button in scene.upgrades:
		button.pressed.emit()
		button.pressed.emit()
	for i in range(3):
		campaign_scene_finish(scene)
	check(scene.campaign.phase == Campaign.Phase.CONQUEST_CLEARED
		and not scene.get_node("%StartDefense").disabled, "Defense scene: real conquest enables explicit entry")
	return scene

func test_campaign_scene_defense() -> void:
	for queued in [false, true]:
		var scene := campaign_scene_defense_ready()
		var campaign := scene.campaign
		check(not scene.get_node("%GateHealth").visible
			and scene.get_node("%GateUpgrade").text == "Gate Lv.1 · Upgrade 20 gold",
			"Defense scene: preparation shows ownership/cost without a live gate preview")
		scene.last_frame_usec = 1
		scene.elapsed_usec = 123
		var clock: int = Time.get_ticks_usec()
		scene.get_node("%StartDefense").pressed.emit()
		var assault := campaign.battle
		check(campaign.phase == Campaign.Phase.DEFENDING and assault.rounds == 0
			and assault.gate_health == 80 and assault.gate_max_health == 80
			and campaign.pending_navigation == Campaign.Navigation.NONE and campaign.pending_farm == -1
			and scene.elapsed_usec == 0 and scene.last_frame_usec >= clock and scene.is_processing()
			and scene.get_node("%CampaignStatus").text == "Counterattack · Defending the Stronghold",
			"Defense scene: explicit entry resets clock, queue and full gate at round zero")
		for squad in assault.players:
			check(squad.health == squad.max_health, "Defense scene: full troop snapshot")
		scene.set_process(false)
		scene.advance_foreground(scene.last_frame_usec + 250000)
		clock = scene.last_frame_usec
		for i in range(3):
			scene.get_node("%StartDefense").pressed.emit()
			scene.get_node("%Frontier").pressed.emit()
		check(campaign.battle == assault and assault.rounds == 0 and scene.elapsed_usec == 250000
			and scene.last_frame_usec == clock and scene.get_node("%StartDefense").disabled
			and scene.get_node("%Frontier").disabled, "Defense scene: repeated start/frontier cannot escape or reset time")
		var stats: Array = campaign_snapshot(campaign)[17]
		scene.get_node("%GateUpgrade").pressed.emit()
		check(campaign.gold == 50 and campaign.gate_level == 2
			and scene.get_node("%GateUpgrade").text == "Gate Lv.2 · Upgrade 40 gold",
			"Defense scene: gate level two charges exactly twenty")
		scene.get_node("%GateUpgrade").pressed.emit()
		for i in range(3):
			scene.get_node("%GateUpgrade").pressed.emit()
		check(campaign.gold == 10 and campaign.gate_level == 3 and campaign_snapshot(campaign)[17] == stats
			and assault.gate_health == 80 and assault.gate_max_health == 80
			and scene.get_node("%GateHealth").text == "Gate HP: 80 / 80"
			and scene.get_node("%GateUpgrade").text == "Gate Lv.3 · MAX"
			and scene.get_node("%GateUpgrade").disabled, "Defense scene: forty charge, cap and no live snapshot repair")
		if queued:
			scene.get_node("%FarmArcher").pressed.emit()
			scene.get_node("%FarmBorder").pressed.emit()
			scene._request_farm(Data.Encounter.STRONGHOLD)
			check(scene.get_node("%PendingNavigation").text.contains("if defense fails; victory secures"),
				"Defense scene: recovery intent explains victory override")
		scene.advance_time(120.0)
		check(assault.result == Combat.Result.DEFEAT and assault.defeat_reason == Combat.DefeatReason.GATE_DESTROYED
			and campaign.battle != assault and campaign.battle.rounds == 0 and scene.elapsed_usec == 0
			and campaign.current_encounter == (Data.Encounter.BORDER_SKIRMISH if queued else Data.Encounter.ARCHER_POSITION)
			and campaign.gold == 10 and campaign.gate_level == 3 and campaign.levels == [3, 3, 3]
			and campaign.border_cleared and campaign.archer_cleared and campaign.stronghold_cleared
			and not scene.get_node("%GateHealth").visible
			and scene.get_node("%LastResult").text.contains("Counterattack: Defeat · +0 gold · Gate destroyed")
			and scene.get_node("%LastResult").text.contains("return to the checkpoint"),
			"Defense scene: real defeat pays zero, preserves progress and routes one fresh recovery battle")
		var recovery := campaign.battle
		scene.get_node("%StartDefense").pressed.emit()
		check(campaign.battle == recovery and scene.get_node("%StartDefense").disabled,
			"Defense scene: farming cannot directly start defense")
		scene.get_node("%Frontier").pressed.emit()
		campaign_scene_finish(scene)
		check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and not scene.get_node("%StartDefense").disabled,
			"Defense scene: settled frontier return enables explicit retry")
		scene.get_node("%StartDefense").pressed.emit()
		assault = campaign.battle
		check(assault != recovery and assault.rounds == 0 and assault.gate_health == 200
			and assault.gate_max_health == 200, "Defense scene: retry snapshots full upgraded gate")
		scene.get_node("%FarmBorder").pressed.emit()
		var gold: int = campaign.gold
		campaign_scene_finish(scene)
		check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.battle == assault
			and assault.result == Combat.Result.VICTORY and assault.gate_health > 0
			and campaign.gold == gold and campaign.pending_navigation == Campaign.Navigation.NONE
			and scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated · +10 Legacy earned"
			and scene.get_node("%LastResult").text == "Counterattack: Victory · +0 gold"
			and scene.get_node("%GateHealth").visible and not scene.is_processing(),
			"Defense scene: real victory retains winning gate and overrides queued farm without reward")
		var before := campaign_snapshot(campaign)
		for name in ["StartDefense", "Frontier", "FarmBorder", "FarmArcher"]:
			check(scene.get_node("%" + name).disabled, "Defense scene: secured control disabled " + name)
			scene.get_node("%" + name).pressed.emit()
			scene.advance_time(120.0)
		check(campaign_snapshot(campaign) == before and scene.elapsed_usec == 0 and not scene.is_processing(),
			"Defense scene: terminal signals/time cannot replace, tick, repay or resume")
		scene.free()
	# Explicit edge fixture: timeout is decided by a real Combat round, not a fabricated result.
	var timeout := campaign_scene_defense_ready()
	timeout.get_node("%StartDefense").pressed.emit()
	timeout.campaign.battle.rounds = 59
	timeout.advance_time(1.0)
	check(timeout.get_node("%LastResult").text.contains("Defeat · +0 gold · Timeout")
		and not timeout.get_node("%GateHealth").visible, "Defense scene: timeout reason survives recovery routing")
	timeout.free()
	var terminal := campaign_scene_defense_ready()
	terminal.campaign.phase = Campaign.Phase.CAMPAIGN_SECURED # Ownership-only terminal eligibility fixture.
	terminal._refresh()
	terminal.get_node("%GateUpgrade").pressed.emit()
	check(terminal.campaign.gate_level == 2 and terminal.campaign.gold == 50
		and not terminal.is_processing(), "Defense scene: terminal gate purchases retain ownership-only semantics")
	terminal.campaign.gold = 39
	terminal._refresh()
	terminal.get_node("%GateUpgrade").pressed.emit()
	check(terminal.get_node("%GateUpgrade").disabled and terminal.campaign.gate_level == 2
		and terminal.campaign.gold == 39, "Defense scene: insufficient gate funds reject direct emission")
	terminal.free()

func test_campaign_scene_defense_lifecycle() -> void:
	for pair in [[MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN],
		[MainLoop.NOTIFICATION_APPLICATION_PAUSED, MainLoop.NOTIFICATION_APPLICATION_RESUMED]]:
		var scene := campaign_scene_defense_ready()
		scene.notification(pair[0])
		var checkpoint := scene.campaign.battle
		scene.get_node("%StartDefense").pressed.emit()
		scene.get_node("%GateUpgrade").pressed.emit()
		check(scene.campaign.battle == checkpoint and scene.campaign.gate_level == 1
			and scene.get_node("%StartDefense").disabled, "Defense lifecycle: suspended checkpoint rejects new controls")
		scene.notification(pair[1])
		scene.get_node("%StartDefense").pressed.emit()
		check(scene.skip_resume_frame, "Defense lifecycle: accepted entry preserves resume-gap guard")
		scene.advance_foreground(scene.last_frame_usec + 9000000)
		scene.advance_foreground(scene.last_frame_usec + 250000)
		var before := campaign_snapshot(scene.campaign)
		var gate: int = scene.campaign.battle.gate_health
		scene.notification(pair[0])
		for name in ["StartDefense", "GateUpgrade", "FarmBorder", "FarmArcher", "Frontier"]:
			check(scene.get_node("%" + name).disabled, "Defense lifecycle: disabled " + name)
			scene.get_node("%" + name).pressed.emit()
		scene.advance_time(120.0)
		check(campaign_snapshot(scene.campaign) == before and scene.campaign.battle.gate_health == gate
			and scene.campaign.gate_level == 1 and scene.elapsed_usec == 250000,
			"Defense lifecycle: suspended rounds, gate, ownership, gold and fraction freeze")
		scene.notification(pair[1])
		scene.advance_foreground(scene.last_frame_usec + 9000000)
		check(campaign_snapshot(scene.campaign) == before and scene.elapsed_usec == 250000,
			"Defense lifecycle: resume gap excluded")
		scene.advance_foreground(scene.last_frame_usec + 749999)
		check(scene.campaign.battle.rounds == 0 and scene.elapsed_usec == 999999,
			"Defense lifecycle: remaining fraction does not round early")
		scene.advance_foreground(scene.last_frame_usec + 1)
		check(scene.campaign.battle.rounds == 1 and scene.elapsed_usec == 0,
			"Defense lifecycle: exact remaining microsecond advances")
		# _input settles before GUI handlers, using the same real foreground clock.
		scene.last_frame_usec = Time.get_ticks_usec() - scene.ROUND_USEC
		scene._input(InputEventKey.new())
		check(scene.campaign.battle.rounds == 2, "Defense lifecycle: input settles due round before GUI purchase")
		scene.free()

func test_campaign_scene_conflicting_suspension() -> void:
	# Focus/pause in both orders, minimize alone, and overlapping native/lifecycle reasons.
	for order in [[0, 1], [1, 0], [2], [0, 2], [2, 0], [1, 2], [2, 1], [0, 1, 2], [2, 1, 0]]:
		for reverse in [false, true]:
			for defending in [false, true]:
				var scene := campaign_scene_defense_ready(CampaignWindowFixture) as CampaignWindowFixture
				if defending:
					scene.get_node("%StartDefense").pressed.emit()
					scene.advance_foreground(scene.last_frame_usec + 250000)
				var before := campaign_snapshot(scene.campaign)
				var elapsed: int = scene.elapsed_usec
				var label := "Suspension overlap %s reverse=%s defense=%s: " % [order, reverse, defending]
				for reason: int in order:
					scene.set_reason(reason, true)
				var releases: Array = order.duplicate()
				if reverse:
					releases.reverse()
				for reason: int in releases:
					check(scene.suspended and scene.get_node("%CampaignStatus").text.contains("Paused")
						and scene.is_processing() == defending, label + "remaining reason suspends without changing processing")
					for name in ["StartDefense", "GateUpgrade", "FarmBorder", "FarmArcher", "Frontier",
						"ShieldUpgrade", "FootUpgrade", "HorseUpgrade"]:
						var button: Button = scene.get_node("%" + name)
						check(button.disabled, label + "disabled " + name)
						button.pressed.emit()
					scene.advance_foreground(scene.last_frame_usec + 9000000)
					scene.advance_time(120.0)
					check(campaign_snapshot(scene.campaign) == before and scene.elapsed_usec == elapsed,
						label + "controls and time preserve gate, battle, ownership, gold and fraction")
					scene.set_reason(reason, false)
				check(not scene.suspended and scene.skip_resume_frame
					and not scene.get_node("%GateUpgrade").disabled
					and scene.get_node("%StartDefense").disabled == defending,
					label + "only final cleared reason resumes eligible controls")
				scene.advance_foreground(scene.last_frame_usec + 9000000)
				check(not scene.skip_resume_frame and campaign_snapshot(scene.campaign) == before
					and scene.elapsed_usec == elapsed, label + "first resumed frame excludes gap")
				for reason in range(3):
					scene.set_reason(reason, false)
				check(not scene.skip_resume_frame, label + "duplicate resume events do not discard another frame")
				if defending:
					scene.advance_foreground(scene.last_frame_usec + 749999)
					check(scene.campaign.battle.rounds == 0 and scene.elapsed_usec == 999999,
						label + "fraction remains exact after conflicting events")
					scene.advance_foreground(scene.last_frame_usec + 1)
					check(scene.campaign.battle.rounds == 1 and scene.elapsed_usec == 0,
						label + "last foreground microsecond advances one real round")
				scene.free()
	# A minimize change must also be observed by direct control/time entry points,
	# before the next process_frame poll, including non-processing checkpoints.
	var scene := campaign_scene_defense_ready(CampaignWindowFixture) as CampaignWindowFixture
	var before := campaign_snapshot(scene.campaign)
	scene.minimized = true
	scene.get_node("%StartDefense").pressed.emit()
	check(scene.suspended and scene.get_node("%StartDefense").disabled
		and campaign_snapshot(scene.campaign) == before and not scene.is_processing(),
		"Suspension: checkpoint control samples native mode before next frame")
	scene.set_reason(2, false)
	scene.get_node("%StartDefense").pressed.emit()
	scene.advance_time(9.0) # Exclude resume gap before the second independent minimize.
	scene.advance_time(0.25)
	before = campaign_snapshot(scene.campaign)
	scene.minimized = true
	scene.advance_time(120.0)
	check(scene.suspended and campaign_snapshot(scene.campaign) == before and scene.elapsed_usec == 250000,
		"Suspension: direct time entry samples native mode before next frame")
	scene.free()

func test_defense_snapshots() -> void:
	var runs: Array = []
	for repeat in range(2):
		var campaign := Campaign.new()
		campaign.gold = 240 # Isolated funds; every owned level uses production purchases.
		for role in range(3):
			check(campaign.purchase(role) and campaign.purchase(role), "Defense passive: cap troops")
		check(campaign.purchase_gate() and campaign.purchase_gate() and campaign.gold == 0,
			"Defense passive: cap gate")
		campaign.restart_battle()
		var snapshots: Array = [campaign_snapshot(campaign, false)]
		for stage in range(3):
			campaign_finish(campaign)
			snapshots.append(campaign_snapshot(campaign, false))
		check(campaign.start_defense() != null, "Defense passive: explicit assault")
		snapshots.append(campaign_snapshot(campaign, false))
		var gold_before: int = campaign.gold
		var assault := campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and assault.gate_health > 0
			and campaign.gold == gold_before and assault.result == Combat.Result.VICTORY,
			"Defense passive: real capped conquest and assault secure with zero defense gold")
		print("DEFENSE passive rounds=%d gate=%d snapshot=%s" % [assault.rounds,
			assault.gate_health, balance_snapshot(assault)])
		runs.append(snapshots)
	check(runs[0] == runs[1], "Defense: full capped sequence snapshots deterministic")
	var campaign := Campaign.new()
	campaign.restart_battle()
	campaign_finish(campaign)
	campaign_finish(campaign)
	# Controlled Stronghold health permits baseline ownership at a real settled checkpoint.
	for squad in campaign.battle.enemies:
		squad.health = 1
	campaign_finish(campaign)
	var assault := campaign.start_defense()
	assault.queue_commander()
	assault.step_round()
	var stats: Array = campaign_snapshot(campaign)[17]
	var gate_before: int = assault.gate_health
	campaign.gold = 80
	check(campaign.purchase(0) and campaign.purchase_gate() and campaign.gold == 40
		and campaign.levels == [2, 1, 1] and campaign.gate_level == 2
		and campaign_snapshot(campaign)[17] == stats and assault.gate_health == gate_before
		and assault.gate_max_health == 80 and assault.commander_damage == 6,
		"Defense: active troop/gate purchases affect ownership only")
	var other := defense_ready()
	other.start_defense()
	var other_before := campaign_snapshot(other)
	assault.players[0].health = 0
	assault.gate_health = 1
	campaign_finish(campaign)
	check(campaign.gold == 40 and campaign.gate_level == 2 and campaign.levels == [2, 1, 1],
		"Defense: loss retains purchased ownership and wallet")
	campaign.request_frontier()
	campaign_finish(campaign)
	var retry := campaign.start_defense()
	campaign_fresh(campaign, assault, 4)
	check(retry.players[0].health == 160 and retry.players[0].damage == 6
		and retry.gate_health == 140 and retry.gate_max_health == 140
		and retry.commander_damage == 6 and assault.gate_health == 0
		and campaign_snapshot(other) == other_before,
		"Defense: fresh retry applies purchases, old assault and other controller independent")
	retry.players[0].health = 0
	retry.enemies.assign([Data.Squad.new(Data.Role.HORSE, "Twelve", 100, 12)])
	retry.step_round()
	check(retry.gate_health == 128 and retry.players[1].health == 40 and retry.players[2].health == 60,
		"Defense: owned level-two snapshot takes twelve gate damage only")

func test_defense_routing() -> void:
	for queued in [false, true]:
		for farm_loss in [false, true]:
			var campaign := defense_ready()
			var stronghold := campaign.battle
			var ready_before := campaign_snapshot(campaign)
			check(not campaign.settle(stronghold) and campaign_snapshot(campaign) == ready_before,
				"Defense guards: duplicate Stronghold before assault inert")
			var assault := campaign.start_defense()
			if queued:
				check(campaign.request_farm(1) and campaign.request_farm(0),
					"Defense: latest valid farm queues without abandoning")
			var before := campaign_snapshot(campaign)
			for invalid in [null, assault, Combat.new(Data.Encounter.COUNTERATTACK), stronghold]:
				check(not campaign.settle(invalid) and campaign_snapshot(campaign) == before,
					"Defense guards: null ongoing foreign stale settlement inert")
			check(not campaign.request_frontier() and not campaign.request_farm(4)
				and not campaign.request_farm(3) and not campaign.request_farm(-1)
				and not campaign.request_farm(99) and campaign.start_defense() == null
				and campaign.restart_battle() == null and campaign_snapshot(campaign) == before,
				"Defense: invalid navigation preserves assault and latest intent")
			assault.players[0].health = 0
			assault.gate_health = 1
			campaign_finish(campaign)
			check(assault.defeat_reason == Combat.DefeatReason.GATE_DESTROYED and campaign.gold == 70
				and campaign.levels == [3, 3, 3] and campaign.gate_level == 1
				and campaign.border_cleared and campaign.archer_cleared and campaign.stronghold_cleared
				and campaign.phase == Campaign.Phase.RUNNING and campaign.mode == Campaign.Mode.FARM
				and campaign.current_encounter == (0 if queued else 1),
				"Defense: free defeat preserves ownership and clearance, routes queued/default farm")
			campaign_fresh(campaign, assault, 0 if queued else 1)
			before = campaign_snapshot(campaign)
			check(not campaign.settle(assault) and not campaign.settle(stronghold)
				and campaign.start_defense() == null and campaign_snapshot(campaign) == before,
				"Defense guards: duplicate loss cannot replace farm successor")
			var reward: int = 10 if queued else 30
			var farm := campaign_finish(campaign)
			check(campaign.gold == 70 + reward and campaign.phase == Campaign.Phase.RUNNING,
				"Defense: legitimate recovery farm pays once and repeats")
			campaign.request_frontier()
			before = campaign_snapshot(campaign)
			check(not campaign.settle(farm) and campaign_snapshot(campaign) == before,
				"Defense guards: old farm cannot consume newer frontier request")
			if farm_loss:
				for squad in campaign.battle.players:
					squad.health = 0
			campaign_finish(campaign)
			check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.stronghold_cleared
				and campaign.gold == 70 + reward * (1 if farm_loss else 2)
				and not campaign.battle.is_defense, "Defense: farm win/loss frontier returns ready, not assault")
			var previous := campaign.battle
			check(campaign.start_defense() != null, "Defense: explicit fresh retry accepted")
			campaign_fresh(campaign, previous, 4)
	var secured := defense_ready()
	var old_stronghold := secured.battle
	secured.purchase_gate()
	secured.purchase_gate()
	secured.start_defense()
	secured.request_farm(0)
	var gold_before: int = secured.gold
	var won := campaign_finish(secured)
	check(won.result == Combat.Result.VICTORY and secured.phase == Campaign.Phase.CAMPAIGN_SECURED
		and secured.battle == won and secured.gold == gold_before and secured.pending_farm == -1
		and secured.pending_navigation == Campaign.Navigation.NONE and secured.farm_encounter == -1,
		"Defense: victory security overrides queued farming, zero payout and retained battle")
	var before := campaign_snapshot(secured)
	check(not secured.settle(won) and not secured.settle(old_stronghold)
		and not secured.request_farm(0) and not secured.request_farm(1) and not secured.request_frontier()
		and secured.start_defense() == null and secured.restart_battle() == null
		and secured.restart_battle(4) == null and campaign_snapshot(secured) == before,
		"Defense: secured navigation and all duplicate settlements inert")

func defense_ready() -> Campaign:
	var campaign := Campaign.new()
	campaign.gold = 180
	for role in range(3):
		check(campaign.purchase(role) and campaign.purchase(role), "Defense setup: real troop purchases")
	campaign.restart_battle()
	for stage in range(3):
		campaign_finish(campaign)
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED, "Defense setup: real conquest checkpoint")
	return campaign

func test_defense_preparation() -> void:
	check(Campaign.Phase.RUNNING == 0 and Campaign.Phase.CONQUEST_CLEARED == 1
		and Campaign.Phase.DEFENDING == 2 and Campaign.Phase.CAMPAIGN_SECURED == 3
		and Campaign.STAGES == [0, 1, 3], "Defense: stable phases and conquest stages")
	var fresh := Campaign.new()
	check(fresh.start_defense() == null and fresh.battle == null and fresh.gate_level == 1,
		"Defense: fresh entry inert before first battle")
	fresh.restart_battle()
	var before := campaign_snapshot(fresh)
	check(fresh.start_defense() == null and fresh.restart_battle(4) == null
		and campaign_snapshot(fresh) == before, "Defense: running entry and generic bypass rejected")
	check(fresh.gate_purchase_cost() == 20 and not fresh.purchase_gate()
		and campaign_snapshot(fresh) == before, "Gate: insufficient funds inert")
	fresh.gold = 60
	check(fresh.purchase_gate() and fresh.gold == 40 and fresh.gate_level == 2
		and fresh.gate_purchase_cost() == 40, "Gate: exact first purchase")
	check(fresh.purchase_gate() and fresh.gold == 0 and fresh.gate_level == 3
		and fresh.gate_purchase_cost() == 0, "Gate: exact second purchase and cap")
	before = campaign_snapshot(fresh)
	check(not fresh.purchase_gate() and campaign_snapshot(fresh) == before, "Gate: cap inert")
	var campaign := defense_ready()
	var stronghold := campaign.battle
	var assault := campaign.start_defense()
	campaign_fresh(campaign, stronghold, 4)
	check(assault.is_defense and assault.gate_health == 80 and assault.commander_damage == 12
		and campaign.phase == Campaign.Phase.DEFENDING and campaign.mode == Campaign.Mode.ADVANCE
		and campaign.farm_encounter == -1 and campaign.pending_farm == -1,
		"Defense: explicit direct entry snapshots and clears selection")
	before = campaign_snapshot(campaign)
	check(campaign.start_defense() == null and campaign.restart_battle() == null
		and campaign.restart_battle(4) == null and campaign_snapshot(campaign) == before,
		"Defense: repeated start and restart inert")
	var returned := defense_ready()
	returned.request_farm(0)
	before = campaign_snapshot(returned)
	check(returned.start_defense() == null and campaign_snapshot(returned) == before,
		"Defense: farming entry rejected")
	returned.request_frontier()
	campaign_finish(returned)
	var farm := returned.battle
	check(returned.current_encounter == 0 and returned.start_defense() != null,
		"Defense: entry accepts ordinary farm-return checkpoint")
	campaign_fresh(returned, farm, 4)
	var ordinary := Economy.new()
	ordinary.levels.assign([3, 3, 3])
	check(not ordinary.is_encounter_unlocked(4) and ordinary.restart_battle(4) == null
		and ordinary.encounter_reward(4) == 0, "Defense: ordinary Economy cannot unlock or pay")

func test_defensive_combat() -> void:
	check(Data.Encounter.COUNTERATTACK == 4, "Defense: appended encounter ID")
	var authored := Combat.new(Data.Encounter.COUNTERATTACK)
	check(authored.enemies.map(func(s: Data.Squad) -> Array: return [s.health, s.damage])
		== [[180, 12], [80, 10], [80, 12]], "Defense: exact authored enemies")
	for shield_state in ["living", "dead", "absent"]:
		var combat := Combat.new(Data.Encounter.COUNTERATTACK)
		combat.players.reverse()
		for squad in combat.players:
			squad.title = "Scrambled"
			if squad.role == Data.Role.SHIELD and shield_state == "dead":
				squad.health = 0
		if shield_state == "absent":
			combat.players.remove_at(2)
		combat.step_round()
		check(combat.gate_health == (80 if shield_state == "living" else 46)
			and combat.players[0].health == 60 and combat.players[1].health == 40,
			"Defense: all enemy roles shield-only targeting %s" % shield_state)
	for gate in [80, 140]:
		var combat := Combat.new(Data.Encounter.COUNTERATTACK)
		combat.gate_max_health = gate
		combat.gate_health = gate
		combat.players[0].health = 1
		combat.enemies.assign([Data.Squad.new(Data.Role.HORSE, "Attack", 100, 12)])
		combat.step_round()
		check(combat.players[0].health == 0 and combat.gate_health == gate,
			"Defense: shield death has no same-round spill")
		combat.step_round()
		check(combat.gate_health == gate - 12 and combat.players[1].health == 40
			and combat.players[2].health == 60, "Defense: twelve damage reaches only gate")
	for outcome in ["victory", "mutual", "army", "timeout", "sixty_win", "sixty_gate"]:
		var combat := Combat.new(Data.Encounter.COUNTERATTACK)
		combat.players.assign([Data.Squad.new(Data.Role.FOOT, "Last archer", 1, 0)])
		combat.enemies.assign([Data.Squad.new(Data.Role.HORSE, "Last enemy", 1, 0)])
		if outcome.begins_with("sixty") or outcome == "timeout":
			for i in range(59):
				combat.step_round()
		if outcome != "timeout" and outcome != "army":
			combat.players[0].damage = 1
		if outcome == "mutual" or outcome == "sixty_gate":
			combat.enemies[0].damage = 80
		if outcome == "army":
			combat.players[0].health = 0
		combat.step_round()
		var won: bool = outcome == "victory" or outcome == "sixty_win"
		var reason: int = Combat.DefeatReason.NONE if won or outcome == "army" else (
			Combat.DefeatReason.TIMEOUT if outcome == "timeout" else Combat.DefeatReason.GATE_DESTROYED)
		check(combat.result == (Combat.Result.ONGOING if outcome == "army" else (
			Combat.Result.VICTORY if won else Combat.Result.DEFEAT)) and combat.defeat_reason == reason,
			"Defense: simultaneous outcome precedence %s" % outcome)
		if outcome != "army":
			var before: Array = [balance_snapshot(combat), combat.gate_health, combat.defeat_reason]
			check(not combat.queue_commander(), "Defense: terminal input rejected")
			combat.step_round()
			check([balance_snapshot(combat), combat.gate_health, combat.defeat_reason] == before
				and not combat.commander_queued, "Defense: terminal round inert")
	var strike := Combat.new(Data.Encounter.COUNTERATTACK)
	check(strike.commander_damage == 6 and strike.queue_commander() and not strike.queue_commander(),
		"Defense: commander original strength and rate limit")
	strike.step_round()
	check(strike.enemies[0].health == 162 and not strike.commander_queued and strike.queue_commander(),
		"Defense: commander retains frontline target and clears each round")
	var death := Combat.new(Data.Encounter.COUNTERATTACK)
	death.enemies.assign([Data.Squad.new(Data.Role.SHIELD, "Dying", 1, 12),
		Data.Squad.new(Data.Role.FOOT, "Survivor", 80, 0)])
	death.step_round()
	check(death.players[0].health == 108, "Defense: dying enemy attacks simultaneously")
	death.step_round()
	check(death.players[0].health == 108, "Defense: dead enemy cannot attack later")

func dynasty_rejected(campaign: Campaign, title: String) -> void:
	var before := campaign_snapshot(campaign)
	check(not campaign.can_found_dynasty() and campaign.found_dynasty() == null
		and campaign_snapshot(campaign) == before, "Dynasty rejected unchanged: " + title)

func dynasty_prepare(campaign: Campaign) -> void:
	# Earn every upgrade through ordinary farming; never inject wins or funds.
	check(campaign.request_farm(Data.Encounter.BORDER_SKIRMISH), "Dynasty: queue earned Border farm")
	campaign_finish(campaign)
	dynasty_rejected(campaign, "farming")
	for role in range(3):
		while campaign.levels[role] < 3:
			while campaign.gold < campaign.purchase_cost(role):
				campaign_finish(campaign)
			check(campaign.purchase(role), "Dynasty: earned troop purchase")
	while campaign.gate_level < 3:
		while campaign.gold < campaign.gate_purchase_cost():
			campaign_finish(campaign)
		check(campaign.purchase_gate(), "Dynasty: earned gate purchase")
	check(campaign.request_frontier(), "Dynasty: return to conquest")
	campaign_finish(campaign)
	for i in range(3):
		if campaign.phase != Campaign.Phase.RUNNING:
			break
		var reward_before: int = campaign.gold
		var completed := campaign_finish(campaign)
		if campaign.stronghold_cleared:
			check(completed.result == Combat.Result.VICTORY and campaign.gold == reward_before + 30,
				"Dynasty: Stronghold pays normal 30 this run")
	dynasty_rejected(campaign, "conquest preparation")

func test_dynasty() -> void:
	var campaign := Campaign.new()
	check(campaign.dynasty == 1 and campaign.drill_rank == 0 and campaign.legacy == 0
		and campaign.secure_legacy() == 10 and campaign.drill_cost() == 10 and not campaign.train_drill()
		and not campaign.can_found_dynasty() and campaign.found_dynasty() == null
		and campaign.battle == null and campaign.gold == 0 and campaign.levels == [1, 1, 1],
		"Dynasty: fresh session rejects without creating battle")
	var baseline := campaign.restart_battle()
	dynasty_rejected(campaign, "ongoing conquest")
	for i in range(4):
		baseline.step_round()
		check(baseline.enemies[0].health == [54, 36, 18, 0][i]
			and baseline.players[0].health == 120 - 3 * (i + 1)
			and baseline.players[1].health == 40 and baseline.players[2].health == 60
			and baseline.rounds == i + 1
			and baseline.result == (Combat.Result.VICTORY if i == 3 else Combat.Result.ONGOING),
			"Dynasty: baseline exact passive round %d" % (i + 1))
	dynasty_rejected(campaign, "unsettled conquest victory")
	check(campaign.settle(baseline), "Dynasty: settle baseline")
	dynasty_prepare(campaign)
	var defense := campaign.start_defense()
	campaign.request_farm(0)
	dynasty_rejected(campaign, "ongoing defense with queued navigation")
	for i in range(60):
		if defense.result != Combat.Result.ONGOING:
			break
		defense.step_round()
	check(defense.result == Combat.Result.VICTORY and defense.gate_health > 0,
		"Dynasty: real victorious surviving defense")
	dynasty_rejected(campaign, "actual unconsumed defensive victory")
	var wallet: int = campaign.gold
	check(campaign.legacy == 0 and campaign.settle(defense) and campaign.gold == wallet
		and campaign.legacy == 10 and campaign.can_found_dynasty(),
		"Dynasty: only settled defense enables reset, pays 10 Legacy and no gold")
	check(not campaign.settle(defense) and campaign.legacy == 10, "Dynasty: secured Legacy paid once")
	# Each eligibility conjunct independently protects an otherwise secured model.
	for field in ["border_cleared", "archer_cleared", "stronghold_cleared", "_settled", "current_encounter"]:
		var original: Variant = campaign.get(field)
		campaign.set(field, 0 if field == "current_encounter" else not original)
		dynasty_rejected(campaign, "guard " + field)
		campaign.set(field, original)
	var surviving_gate: int = defense.gate_health
	defense.gate_health = 0
	dynasty_rejected(campaign, "no surviving gate")
	defense.gate_health = surviving_gate
	# Training is a pure Legacy purchase: it never touches the settled battle or gold.
	var pre_train := campaign_snapshot(campaign)
	check(campaign.train_drill() and campaign.legacy == 0 and campaign.drill_rank == 1
		and campaign._battle_drill_rank == 0 and campaign.drill_cost() == 20 and not campaign.train_drill()
		and campaign_snapshot(campaign).slice(0, 23) == pre_train.slice(0, 23),
		"Dynasty: rank 1 costs 10 Legacy, rank 2 unaffordable, battle untouched")
	var old_state := campaign_snapshot(campaign)
	var successor := campaign.found_dynasty()
	check(successor != null and campaign.dynasty == 2 and campaign.drill_rank == 1 and campaign.legacy == 0
		and campaign._battle_drill_rank == 1 and campaign.secure_legacy() == 3,
		"Dynasty: one synchronous successor keeps Legacy and Drill rank")
	campaign_fresh(campaign, defense, Data.Encounter.BORDER_SKIRMISH)
	check(campaign.gold == 0 and campaign.levels == [1, 1, 1] and campaign.gate_level == 1
		and campaign.phase == Campaign.Phase.RUNNING and campaign.mode == Campaign.Mode.ADVANCE
		and not campaign.border_cleared and not campaign.archer_cleared and not campaign.stronghold_cleared
		and campaign.farm_encounter == -1 and campaign.pending_navigation == Campaign.Navigation.NONE
		and campaign.pending_farm == -1 and not campaign._settled and campaign._battle_reward == 10
		and not successor.is_defense and successor.commander_damage == 12,
		"Dynasty: complete reset ownership, progression, navigation, settlement and commander")
	var saved_successor := campaign_snapshot(campaign)
	# Reuse the full snapshot helper to prove the old Combat was not mutated.
	campaign.battle = defense
	var retained := campaign_snapshot(campaign)
	campaign.battle = successor
	check(retained.slice(14, 18) == old_state.slice(14, 18)
		and retained.slice(19, 23) == old_state.slice(19, 23), "Dynasty: prior winning battle unchanged")
	check(not campaign.settle(defense) and campaign_snapshot(campaign) == saved_successor,
		"Dynasty: prior defense cannot settle again")
	dynasty_rejected(campaign, "successor before security")
	for role in range(3):
		check(successor.players[role].health == [120, 40, 60][role]
			and successor.players[role].damage == [8, 16, 12][role], "Dynasty: base health and doubled damage")
	check(successor.enemies[0].max_health == 72 and successor.enemies[0].damage == 3,
		"Dynasty: authored enemy unchanged")
	for i in range(2):
		successor.step_round()
		check(successor.enemies[0].health == [36, 0][i] and successor.rounds == i + 1
			and successor.players[0].health == [117, 114][i]
			and successor.players[1].health == 40 and successor.players[2].health == 60
			and successor.result == (Combat.Result.ONGOING if i == 0 else Combat.Result.VICTORY),
			"Dynasty: successor exact passive round %d" % (i + 1))
	check(campaign.gold == 0 and campaign.settle(successor) and campaign.gold == 10
		and not campaign.settle(successor) and campaign.gold == 10, "Dynasty: ordinary Border reward once")
	var ordinary := Economy.new()
	ordinary.levels = [2, 2, 2]
	var normal := ordinary.restart_battle()
	for rank in range(4):
		var formula := Campaign.new()
		formula.drill_rank = rank
		formula.levels = [2, 2, 2]
		var upgraded := formula.restart_battle()
		for role in range(3):
			check(upgraded.players[role].damage == [6, 12, 9][role] * (1 + rank)
				and normal.players[role].damage == [6, 12, 9][role]
				and upgraded.players[role].max_health == normal.players[role].max_health,
				"Dynasty: rank %d level additions before x%d multiplier, unchanged health" % [rank, 1 + rank])
		check(upgraded.commander_damage == 9 * (1 + rank) and normal.commander_damage == 9
			and formula._battle_drill_rank == rank, "Dynasty: commander derives rank %d snapshot" % rank)
	# Rank costs 10/20/40 in Legacy, capped at rank 3.
	var ranks := Campaign.new()
	ranks.legacy = 69
	check(ranks.train_drill() and ranks.legacy == 59 and ranks.train_drill() and ranks.legacy == 39
		and not ranks.train_drill() and ranks.legacy == 39 and ranks.drill_rank == 2 and ranks.drill_cost() == 40,
		"Dynasty: rank 2 costs 20, rank 3 at 40 rejected with 39 unchanged")
	ranks.legacy += 1
	check(ranks.train_drill() and ranks.legacy == 0 and ranks.drill_rank == 3 and ranks.drill_cost() == 0,
		"Dynasty: rank 3 costs 40")
	ranks.legacy = 1000
	check(not ranks.train_drill() and ranks.drill_rank == 3 and ranks.legacy == 1000,
		"Dynasty: rank 3 is the maximum")
	var fresh := Campaign.new()
	check(fresh.drill_rank == 0 and fresh.dynasty == 1 and fresh.legacy == 0
		and fresh.restart_battle().players[0].damage == 4
		and Economy.new().restart_battle().players[0].damage == 4, "Dynasty: fresh model and Economy isolation")
	dynasty_prepare(campaign)
	campaign.start_defense()
	wallet = campaign.gold
	var final_defense := campaign_finish(campaign)
	check(final_defense.result == Combat.Result.VICTORY and campaign.phase == Campaign.Phase.CAMPAIGN_SECURED
		and campaign.gold == wallet and campaign.drill_rank == 1 and campaign.dynasty == 2 and campaign.legacy == 3
		and final_defense.players[0].damage == 16, "Dynasty: successor secured, +3 Legacy, no gold, no stacking")
	var terminal := campaign_snapshot(campaign)
	check(not campaign.settle(final_defense) and campaign.restart_battle() == null
		and not campaign.request_frontier() and not campaign.request_farm(0)
		and campaign_snapshot(campaign) == terminal and campaign.legacy == 3, "Dynasty: successor checkpoint stays inert")
	# Resets repeat: dynasty 3 keeps rank and Legacy, and its security pays 3 more.
	check(campaign.can_found_dynasty() and campaign.found_dynasty() != null and campaign.dynasty == 3
		and campaign.legacy == 3 and campaign.drill_rank == 1 and campaign.battle.players[0].damage == 8
		and campaign.gold == 0 and campaign.levels == [1, 1, 1], "Dynasty: repeat reset into dynasty 3")
	dynasty_rejected(campaign, "dynasty 3 before security")
	campaign_finish(campaign)
	dynasty_prepare(campaign)
	campaign.start_defense()
	campaign_finish(campaign)
	check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.legacy == 6 and campaign.can_found_dynasty()
		and campaign.found_dynasty() != null and campaign.dynasty == 4 and campaign.legacy == 6,
		"Dynasty: dynasty 3 security pays 3 more and resets again")
	# Real unupgraded defensive defeat and recovery also cannot authorize a reset.
	var loss := Campaign.new()
	loss.border_cleared = true
	loss.archer_cleared = true
	loss.stronghold_cleared = true
	loss.phase = Campaign.Phase.CONQUEST_CLEARED
	var lost := loss.start_defense()
	for i in range(60):
		if lost.result != Combat.Result.ONGOING:
			break
		lost.step_round()
	check(lost.result == Combat.Result.DEFEAT, "Dynasty: real defensive defeat fixture")
	dynasty_rejected(loss, "unsettled defensive defeat")
	check(loss.settle(lost), "Dynasty: settle defeat for recovery")
	dynasty_rejected(loss, "defensive recovery")
	# Isolate Drill retention through a gate-destruction/recovery boundary.
	loss.dynasty = 2
	loss.drill_rank = 1
	check(loss.request_frontier(), "Dynasty: recovery frontier queued")
	campaign_finish(loss)
	var retry := loss.start_defense()
	retry.players[0].health = 0
	retry.gate_health = 1
	campaign_finish(loss)
	check(retry.result == Combat.Result.DEFEAT and loss.drill_rank == 1 and loss.legacy == 0
		and loss.dynasty == 2 and loss.mode == Campaign.Mode.FARM
		and loss.battle.players[0].damage == 8 and loss.battle.commander_damage == 12,
		"Dynasty: defeat and recovery preserve Drill rank without stacking or Legacy")
	dynasty_rejected(loss, "successor defensive recovery")

# Real play to a secured defense at the campaign's current dynasty and Threat.
func threat_secure(campaign: Campaign) -> Combat:
	# dynasty_prepare farms Border, so win the opening Border battle first (real rounds, retried on loss).
	for i in range(10):
		if campaign.border_cleared:
			break
		campaign_finish(campaign)
	check(campaign.border_cleared, "Threat: opening Border battle cleared")
	if not campaign.border_cleared:
		return campaign.battle
	dynasty_prepare(campaign)
	var defense := campaign.start_defense()
	campaign_finish(campaign)
	return defense

func threat_rejected(campaign: Campaign, level: int, title: String) -> void:
	var before := campaign_snapshot(campaign)
	check(campaign.found_dynasty(level) == null and campaign_snapshot(campaign) == before,
		"Threat rejected unchanged: " + title)

func test_threat() -> void:
	# Enemy scaling: +25% health and damage per level, rounded half up; troops never scale.
	check(Data.threat_scaled(72, 1) == 90 and Data.threat_scaled(3, 1) == 4 and Data.threat_scaled(3, 2) == 5
		and Data.threat_scaled(72, 2) == 108 and Data.threat_scaled(3, 0) == 3 and Data.threat_scaled(10, 4) == 20,
		"Threat: scaling formula rounds half up at +25% per level")
	for encounter in [Data.Encounter.BORDER_SKIRMISH, Data.Encounter.ARCHER_POSITION,
			Data.Encounter.STRONGHOLD, Data.Encounter.COUNTERATTACK]:
		var base := Data.enemies(encounter)
		var scaled := Data.enemies(encounter, 3)
		var ok: bool = base.size() == scaled.size() and base.size() > 0
		for i in range(base.size()):
			ok = (ok and scaled[i].max_health == Data.threat_scaled(base[i].max_health, 3)
				and scaled[i].health == scaled[i].max_health
				and scaled[i].damage == Data.threat_scaled(base[i].damage, 3)
				and scaled[i].role == base[i].role and scaled[i].title == base[i].title)
		check(ok, "Threat: encounter %d enemies scale health and damage" % encounter)
	# Payouts: dynasty 1 always 10; later secures 3 x (1 + Threat).
	check(Campaign.threat_legacy(0) == 3 and Campaign.threat_legacy(1) == 6 and Campaign.threat_legacy(4) == 15,
		"Threat: later secure pays 3, 6 ... 3 x (1 + Threat)")
	var campaign := Campaign.new()
	check(campaign.threat == 0 and campaign.best_threat == -1 and campaign.legacy_earned == 0
		and campaign.max_selectable_threat() == 0 and campaign.secure_legacy() == 10,
		"Threat: fresh dynasty 1 is Threat 0 with nothing unlocked")
	campaign.restart_battle()
	var first := threat_secure(campaign)
	check(first.result == Combat.Result.VICTORY and campaign.legacy == 10 and campaign.legacy_earned == 10
		and campaign.best_threat == 0 and campaign.max_selectable_threat() == 1,
		"Threat: securing dynasty 1 records best Threat 0 and unlocks Threat 1")
	threat_rejected(campaign, 2, "two above best")
	threat_rejected(campaign, -1, "negative")
	check(campaign.train_drill() and campaign.drill_rank == 1, "Threat: train Drill rank 1")
	var hard := campaign.found_dynasty(1)
	check(hard != null and campaign.dynasty == 2 and campaign.threat == 1 and campaign.secure_legacy() == 6
		and hard.enemies[0].max_health == 90 and hard.enemies[0].health == 90 and hard.enemies[0].damage == 4
		and hard.players[0].max_health == 120 and hard.players[0].damage == 8,
		"Threat: dynasty 2 at Threat 1 scales enemies only and promises 6 Legacy")
	# Every battle in the dynasty (farm, conquest and defense) keeps the Threat.
	var defense := threat_secure(campaign)
	check(defense.is_defense and defense.enemies[0].max_health == Data.threat_scaled(Data.enemies(Data.Encounter.COUNTERATTACK)[0].max_health, 1)
		and defense.result == Combat.Result.VICTORY and campaign.legacy == 6 and campaign.legacy_earned == 16
		and campaign.best_threat == 1 and campaign.max_selectable_threat() == 2,
		"Threat: real Threat-1 secure pays 6 Legacy and unlocks Threat 2")
	# Dropping back to Threat 0 is always allowed and never lowers the best.
	check(campaign.found_dynasty(0) != null and campaign.threat == 0 and campaign.secure_legacy() == 3
		and campaign.battle.enemies[0].max_health == 72 and campaign.max_selectable_threat() == 2,
		"Threat: dynasty 3 can drop to Threat 0 with authored enemies")
	threat_secure(campaign)
	check(campaign.legacy == 9 and campaign.legacy_earned == 19 and campaign.best_threat == 1,
		"Threat: Threat-0 secure pays 3 and keeps best Threat 1")
	# Farming mid-dynasty keeps Threat; restart_battle keeps it too.
	check(campaign.found_dynasty(2) != null and campaign.threat == 2
		and campaign.restart_battle().enemies[0].max_health == 108, "Threat: restarted battle keeps Threat 2")
	var capped := Campaign.new()
	capped.best_threat = Campaign.THREAT_MAX
	check(capped.max_selectable_threat() == Campaign.THREAT_MAX, "Threat: selectable Threat capped at maximum")

func test_threat_state() -> void:
	var CORRUPT := CampaignState.Outcome.CORRUPT
	# v4 round trip: Threat, best and earned are persisted and battles restore scaled.
	var campaign := state_secured()
	campaign.train_drill()
	campaign.found_dynasty(1)
	campaign.battle.step_round()
	var state: Dictionary = state_json(CampaignState.capture(campaign, 0).state)
	var restored := CampaignState.restore(state)
	check(restored.outcome == CampaignState.Outcome.VALID and state.version == 4 and state.threat == 1
		and state.best_threat == 0 and state.legacy_earned == 10
		and restored.campaign.threat == 1 and restored.campaign.best_threat == 0 and restored.campaign.legacy_earned == 10
		and campaign_snapshot(restored.campaign, false) == campaign_snapshot(campaign, false),
		"Threat save: v4 round trip keeps Threat, best, earned and the scaled battle exactly")
	state_rejects(state, "Threat above unlocked", CORRUPT, func(s: Dictionary) -> void: s.threat = 2)
	state_rejects(state, "negative Threat", CORRUPT, func(s: Dictionary) -> void: s.threat = -1)
	state_rejects(state, "Threat over max", CORRUPT, func(s: Dictionary) -> void: s.threat = Campaign.THREAT_MAX + 1)
	state_rejects(state, "fractional Threat", CORRUPT, func(s: Dictionary) -> void: s.threat = 0.5)
	state_rejects(state, "missing Threat", CORRUPT, func(s: Dictionary) -> void: s.erase("threat"))
	state_rejects(state, "missing best Threat", CORRUPT, func(s: Dictionary) -> void: s.erase("best_threat"))
	state_rejects(state, "missing Legacy earned", CORRUPT, func(s: Dictionary) -> void: s.erase("legacy_earned"))
	state_rejects(state, "best Threat before it was reachable", CORRUPT, func(s: Dictionary) -> void: s.best_threat = 1)
	state_rejects(state, "no best after a secure", CORRUPT, func(s: Dictionary) -> void: s.best_threat = -1)
	state_rejects(state, "inflated earned and balance", CORRUPT, func(s: Dictionary) -> void:
		s.legacy_earned = 13
		s.legacy = 3)
	state_rejects(state, "earned without balance", CORRUPT, func(s: Dictionary) -> void: s.legacy_earned = 13)
	state_rejects(state, "enemy healed past scaled max", CORRUPT, func(s: Dictionary) -> void: s.battle.enemy_health[0] = 91)
	state_rejects(state, "v2 carrying Threat keys", CORRUPT, func(s: Dictionary) -> void: s.version = 2)
	var dynasty_one: Dictionary = state_json(CampaignState.capture(campaign_running(), 0).state)
	state_rejects(dynasty_one, "dynasty 1 at Threat 1", CORRUPT, func(s: Dictionary) -> void: s.threat = 1)
	state_rejects(dynasty_one, "dynasty 1 unsecured with a best", CORRUPT, func(s: Dictionary) -> void: s.best_threat = 0)
	# The scaled enemy cap is enforced: Threat-1 health 90 is valid, Threat-0 cap would not allow it.
	var edited: Dictionary = state.duplicate(true)
	edited.battle.enemy_health[0] = 90
	check(CampaignState.validate(edited).outcome == CampaignState.Outcome.VALID,
		"Threat save: Threat-1 enemy at scaled full health is valid")
	# Legacy earned ranges: dynasty 3 after Threat-1 secure and Threat-0 secure earns 10 + 6 + 3.
	threat_secure(campaign)
	campaign.found_dynasty(0)
	threat_secure(campaign)
	state = state_json(CampaignState.capture(campaign, 0).state)
	check(CampaignState.validate(state).outcome == CampaignState.Outcome.VALID and state.legacy_earned == 19
		and state.best_threat == 1 and state.dynasty == 3,
		"Threat save: mixed-Threat history saves as a valid v4 ledger")
	# Earned is a range check: with best Threat 1 over two later secures it lies in 19..22 (10 + 6 + 6).
	var richest: Dictionary = state.duplicate(true)
	richest.legacy_earned = 22
	richest.legacy += 3
	check(CampaignState.validate(richest).outcome == CampaignState.Outcome.VALID,
		"Threat save: richest history for best Threat 1 accepted")
	state_rejects(state, "earned above richest history", CORRUPT, func(s: Dictionary) -> void:
		s.legacy_earned = 23
		s.legacy += 4)
	state_rejects(state, "earned from a Threat above the best", CORRUPT, func(s: Dictionary) -> void:
		s.legacy_earned = 25
		s.legacy += 6)
	state_rejects(state, "earned below cheapest history", CORRUPT, func(s: Dictionary) -> void:
		s.legacy_earned = 16
		s.legacy -= 3)
	# v2 migration: old files are all Threat 0 and their fixed +10/+3 ledger becomes Legacy earned.
	var v2_fresh := CampaignState.restore(state_as_v2(state_json(CampaignState.capture(campaign_running(), 0).state)))
	check(v2_fresh.outcome == CampaignState.Outcome.VALID and v2_fresh.campaign.threat == 0
		and v2_fresh.campaign.best_threat == -1 and v2_fresh.campaign.legacy_earned == 0,
		"Threat migration: v2 dynasty 1 running loads Threat 0 with no best")
	var legacy_run := state_secured()
	legacy_run.train_drill()
	legacy_run.found_dynasty()
	threat_secure(legacy_run)
	var v2_secured: Dictionary = state_as_v2(state_json(CampaignState.capture(legacy_run, 0).state))
	var migrated := CampaignState.restore(v2_secured)
	check(not v2_secured.has("threat") and v2_secured.version == 2
		and migrated.outcome == CampaignState.Outcome.VALID and migrated.campaign.dynasty == 2
		and migrated.campaign.legacy == 3 and migrated.campaign.legacy_earned == 13
		and migrated.campaign.threat == 0 and migrated.campaign.best_threat == 0
		and migrated.campaign.max_selectable_threat() == 1,
		"Threat migration: v2 secured dynasty 2 loads Threat 0, best 0, earned 13 and unlocks Threat 1")
	state_rejects(v2_secured, "v2 hand-edited Legacy", CORRUPT, func(s: Dictionary) -> void: s.legacy = 4)
	state_rejects(v2_secured, "v2 dynasty without its Legacy", CORRUPT, func(s: Dictionary) -> void: s.dynasty = 3)
	check(migrated.campaign.found_dynasty(1) != null and migrated.campaign.battle.enemies[0].max_health == 90,
		"Threat migration: migrated v2 dynasty can found at Threat 1")
	# On disk: a v2 file loads unchanged; the next save writes v4 that reloads exactly.
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "Threat migration: isolated directory owned")
	if not fixture.owned:
		return
	check(fixture.put(JSON.stringify(v2_secured)) == OK, "Threat migration: v2 file written")
	var store := CampaignSave.new(fixture.path)
	var loaded := store.load_campaign()
	check(loaded.outcome == CampaignSave.Outcome.LOADED and not loaded.has("recovered")
		and loaded.campaign.legacy == 3 and loaded.campaign.legacy_earned == 13
		and FileAccess.get_file_as_string(fixture.path) == JSON.stringify(v2_secured),
		"Threat migration: v2 file loads through the store without being rewritten")
	check(store.save_campaign(loaded.campaign, loaded.round_progress_usec) == OK
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).version == 4
		and CampaignSave.new(fixture.path).load_campaign().campaign.legacy_earned == 13,
		"Threat migration: next save writes v4 that reloads exactly")
	check(fixture.cleanup() == OK, "Threat migration: directory cleaned")

func campaign_finish(campaign: Campaign) -> Combat:
	var completed := campaign.battle
	for i in range(60):
		if completed.result != Combat.Result.ONGOING:
			break
		completed.step_round()
	check(completed.result != Combat.Result.ONGOING and campaign.settle(completed),
		"Campaign: bounded real battle settles")
	return completed

func campaign_snapshot(campaign: Campaign, identity: bool = true) -> Array:
	var combat := campaign.battle
	var squads: Array = []
	for army in [combat.players, combat.enemies]:
		var rows: Array = []
		for squad in army:
			rows.append([squad.role, squad.title, squad.health, squad.max_health, squad.damage])
		squads.append(rows)
	return [campaign.gold, campaign.levels.duplicate(), campaign.border_cleared,
		campaign.archer_cleared, campaign.stronghold_cleared, campaign.mode, campaign.phase,
		campaign.farm_encounter, campaign.pending_navigation, campaign.pending_farm,
		campaign.current_encounter, campaign._battle_reward, campaign._settled,
		combat if identity else null, balance_snapshot(combat), combat.commander_queued,
		combat.commander_damage, squads, campaign.gate_level, combat.is_defense,
		combat.gate_max_health, combat.gate_health, combat.defeat_reason,
		campaign.dynasty, campaign.legacy, campaign.drill_rank, campaign._battle_drill_rank,
		campaign.threat, campaign.best_threat, campaign.legacy_earned]

func campaign_fresh(campaign: Campaign, previous: Combat, encounter: int) -> void:
	var combat := campaign.battle
	var full: bool = true
	for army in [combat.players, combat.enemies]:
		for squad in army:
			full = full and squad.health == squad.max_health
	check(combat != previous and not is_same(combat.players, previous.players)
		and not is_same(combat.enemies, previous.enemies)
		and combat.players[0] != previous.players[0] and combat.enemies[0] != previous.enemies[0]
		and combat.rounds == 0 and combat.result == Combat.Result.ONGOING
		and not combat.commander_queued and full and campaign.current_encounter == encounter
		and combat.defeat_reason == Combat.DefeatReason.NONE
		and combat.gate_health == combat.gate_max_health
		and combat.gate_max_health == (80 + 60 * (campaign.gate_level - 1) if combat.is_defense else 0),
		"Campaign: independent full-health successor %d" % encounter)

func test_campaign_progression() -> void:
	var campaign := Campaign.new()
	campaign.restart_battle()
	check(campaign.gold == 0 and campaign.levels == [1, 1, 1]
		and campaign.mode == Campaign.Mode.ADVANCE and campaign.farm_encounter == -1,
		"Campaign: fresh ownership and advance mode")
	var before := campaign_snapshot(campaign)
	check(not campaign.is_encounter_unlocked(1) and not campaign.is_encounter_unlocked(3)
		and campaign.restart_battle(1) == null and not campaign.request_farm(0)
		and not campaign.request_frontier() and campaign_snapshot(campaign) == before,
		"Campaign: initial destinations require clearance, rejection is inert")
	var border := campaign_finish(campaign)
	check(border.rounds == 4 and border.result == Combat.Result.VICTORY and campaign.gold == 10
		and campaign.border_cleared and not campaign.archer_cleared,
		"Campaign: passive Border round four pays ten and clears")
	campaign_fresh(campaign, border, 1)
	check(campaign.is_encounter_unlocked(1) and not campaign.is_encounter_unlocked(3),
		"Campaign: Border clearance unlocks Archer without ownership upgrade")
	var archer := campaign_finish(campaign)
	check(archer.rounds == 8 and archer.result == Combat.Result.VICTORY and campaign.gold == 40
		and campaign.archer_cleared and campaign.is_encounter_unlocked(3),
		"Campaign: passive Archer round eight pays thirty and clears")
	campaign_fresh(campaign, archer, 3)
	check(Data.Encounter.STRONGHOLD == 3 and campaign.encounter_reward(3) == 30
		and campaign.battle.enemies.size() == 3
		and campaign.battle.enemies.map(func(s: Data.Squad) -> Array: return [s.role, s.health, s.damage])
		== [[0, 160, 8], [1, 60, 8], [2, 60, 6]], "Campaign: distinct authored Stronghold")
	var economy := Economy.new()
	check(not economy.is_encounter_unlocked(1) and economy.restart_battle(3) == null
		and economy.encounter_reward(3) == 0, "Campaign isolation: ordinary locks and no Stronghold payout")
	economy.levels.assign([2, 2, 2])
	check(economy.is_encounter_unlocked(2) and economy.encounter_reward(2) == 54
		and not campaign.is_encounter_unlocked(2) and campaign.encounter_reward(2) == 0,
		"Campaign isolation: Fortified remains manual, repeatable and distinct")
	before = campaign_snapshot(campaign)
	check(not campaign.request_farm(2) and campaign.restart_battle(2) == null
		and campaign_snapshot(campaign) == before, "Campaign: Fortified rejected without mutation")
	var stronghold := campaign_finish(campaign)
	print("CAMPAIGN Stronghold baseline snapshot=%s" % [balance_snapshot(stronghold)])
	check(stronghold.result == Combat.Result.DEFEAT and campaign.gold == 40
		and campaign.current_encounter == 1 and campaign.mode == Campaign.Mode.FARM,
		"Campaign: real baseline Stronghold loss farms highest clearance")

func test_campaign_navigation() -> void:
	var campaign := Campaign.new()
	campaign.restart_battle()
	campaign_finish(campaign)
	campaign.battle.step_round()
	campaign.battle.queue_commander()
	var original := campaign.battle
	var combat_before := balance_snapshot(original)
	check(campaign.request_farm(0) and campaign.battle == original
		and balance_snapshot(original) == combat_before and original.commander_queued
		and campaign.gold == 10, "Campaign: queued farm preserves battle HP rounds strike and wallet")
	var before := campaign_snapshot(campaign)
	check(not campaign.request_farm(1) and not campaign.request_farm(2)
		and not campaign.request_farm(3) and not campaign.request_farm(99)
		and not campaign.request_farm(-1) and not campaign.request_frontier()
		and campaign.restart_battle(0) == null and campaign_snapshot(campaign) == before,
		"Campaign: invalid navigation preserves latest valid request")
	campaign_finish(campaign)
	check(campaign.gold == 40 and campaign.archer_cleared and campaign.current_encounter == 0
		and campaign.mode == Campaign.Mode.FARM and campaign.farm_encounter == 0,
		"Campaign: queued farm beats advance after finishing reward and clearance")
	campaign_fresh(campaign, original, 0)
	check(campaign.request_farm(1) and campaign.request_farm(0), "Campaign: two valid farms queue")
	campaign_finish(campaign)
	check(campaign.gold == 50 and campaign.current_encounter == 0
		and campaign.pending_navigation == Campaign.Navigation.NONE and campaign.pending_farm == -1,
		"Campaign: latest farm wins and request consumed once")
	campaign_finish(campaign)
	check(campaign.gold == 60 and campaign.current_encounter == 0,
		"Campaign: farm victory repeats selected ordinary stage with income")
	check(campaign.request_frontier() and campaign.request_farm(1), "Campaign: farm replaces frontier intent")
	campaign_finish(campaign)
	check(campaign.current_encounter == 1 and campaign.gold == 70, "Campaign: latest farm beats frontier")
	check(campaign.request_farm(0) and campaign.request_frontier(), "Campaign: frontier replaces farm intent")
	campaign_finish(campaign)
	check(campaign.current_encounter == 3 and campaign.gold == 100
		and campaign.mode == Campaign.Mode.ADVANCE and campaign.farm_encounter == -1,
		"Campaign: frontier resolved after farm settlement skips Fortified")

func test_campaign_losses() -> void:
	var campaign := Campaign.new()
	campaign.restart_battle()
	for squad in campaign.battle.players:
		squad.health = 0
	var lost := campaign_finish(campaign)
	check(lost.result == Combat.Result.DEFEAT and campaign.gold == 0 and not campaign.border_cleared
		and campaign.mode == Campaign.Mode.ADVANCE, "Campaign: no-clear loss retries Border without payment")
	campaign_fresh(campaign, lost, 0)
	campaign_finish(campaign)
	for squad in campaign.battle.players:
		squad.health = 0
	campaign_finish(campaign)
	check(campaign.current_encounter == 0 and campaign.mode == Campaign.Mode.FARM
		and campaign.gold == 10 and not campaign.archer_cleared, "Campaign: Archer loss farms Border")
	campaign.request_frontier()
	campaign_finish(campaign)
	campaign_finish(campaign)
	campaign.request_farm(0)
	for squad in campaign.battle.players:
		squad.health = 0
	campaign_finish(campaign)
	check(campaign.current_encounter == 0 and campaign.farm_encounter == 0 and campaign.gold == 50,
		"Campaign: explicit queued farm beats highest-clear loss fallback")
	for squad in campaign.battle.players:
		squad.health = 0
	campaign_finish(campaign)
	check(campaign.current_encounter == 1 and campaign.farm_encounter == 1 and campaign.gold == 50,
		"Campaign: farm loss without navigation uses highest clearance")
	campaign.request_frontier()
	for squad in campaign.battle.players:
		squad.health = 0
	campaign_finish(campaign)
	check(campaign.current_encounter == 3 and campaign.mode == Campaign.Mode.ADVANCE
		and campaign.gold == 50 and campaign.border_cleared and campaign.archer_cleared,
		"Campaign: queued frontier beats defeat fallback without payment")

func test_campaign_boundaries() -> void:
	for outcome in ["victory", "mutual", "timeout"]:
		var campaign := Campaign.new()
		campaign.restart_battle()
		var combat := campaign.battle
		# Controlled stats, real 60 logical rounds; never assign a terminal result.
		for squad in combat.players:
			squad.damage = 0
		combat.enemies[0].damage = 0
		for i in range(59):
			combat.step_round()
		if outcome != "timeout":
			combat.enemies[0].health = 4
			combat.players[0].damage = 4
		if outcome == "mutual":
			combat.players[0].health = 3
			combat.players[1].health = 0
			combat.players[2].health = 0
			combat.enemies[0].damage = 3
		campaign_finish(campaign)
		var won: bool = outcome == "victory"
		check(combat.rounds == 60 and combat.result == (Combat.Result.VICTORY if won else Combat.Result.DEFEAT)
			and campaign.gold == (10 if won else 0) and campaign.border_cleared == won
			and campaign.current_encounter == (1 if won else 0),
			"Campaign: round sixty production priority %s" % outcome)

func test_campaign_settlement_guards() -> void:
	var campaign := Campaign.new()
	campaign.restart_battle()
	var abandoned := campaign.battle
	abandoned.queue_commander()
	var fresh := campaign.restart_battle()
	campaign_fresh(campaign, abandoned, 0)
	var foreign := Campaign.new()
	foreign.restart_battle()
	var foreign_terminal := campaign_finish(foreign)
	for i in range(60):
		if abandoned.result != Combat.Result.ONGOING:
			break
		abandoned.step_round()
	for invalid in [null, fresh, foreign.battle, foreign_terminal, abandoned]:
		var before := campaign_snapshot(campaign)
		check(not campaign.settle(invalid) and campaign_snapshot(campaign) == before,
			"Campaign: null ongoing foreign abandoned settlement preserves full state")
	var terminal := campaign_finish(campaign)
	campaign.request_farm(0)
	var before := campaign_snapshot(campaign)
	check(not campaign.settle(terminal) and not campaign.settle(terminal)
		and campaign_snapshot(campaign) == before, "Campaign: stale duplicate cannot consume successor request")
	var old := campaign.battle
	var gold_before: int = campaign.gold
	campaign.restart_battle()
	check(campaign.pending_navigation == Campaign.Navigation.NONE and campaign.pending_farm == -1
		and campaign.gold == gold_before and campaign.border_cleared and not campaign.archer_cleared,
		"Campaign: explicit restart abandons pending navigation but retains progress")
	campaign_fresh(campaign, old, 1)

func test_campaign_checkpoint() -> void:
	var campaign := Campaign.new()
	campaign.gold = 180 # Isolated test funds; upgrades still use production purchases.
	for role in range(3):
		check(campaign.purchase(role) and campaign.purchase(role), "Campaign: inherited max-level purchases")
	campaign.restart_battle()
	campaign_finish(campaign)
	campaign_finish(campaign)
	check(campaign.request_farm(0), "Campaign: farm queued before terminal objective")
	var stronghold := campaign_finish(campaign)
	print("CAMPAIGN Stronghold upgraded snapshot=%s" % [balance_snapshot(stronghold)])
	check(stronghold.result == Combat.Result.VICTORY and campaign.gold == 70
		and campaign.stronghold_cleared and campaign.phase == Campaign.Phase.CONQUEST_CLEARED
		and campaign.battle == stronghold and campaign.pending_navigation == Campaign.Navigation.NONE
		and campaign.pending_farm == -1 and campaign.farm_encounter == -1,
		"Campaign: Stronghold thirty-gold clearance overrides queued farm and retains terminal object")
	var before := campaign_snapshot(campaign)
	check(not campaign.settle(stronghold) and campaign.restart_battle() == null
		and campaign.restart_battle(3) == null and not campaign.request_farm(3)
		and not campaign.is_encounter_unlocked(3) and campaign.request_frontier()
		and campaign_snapshot(campaign) == before, "Campaign: checkpoint no-op and duplicate/restart cannot repay")
	check(campaign.request_farm(1) and campaign.phase == Campaign.Phase.RUNNING
		and campaign.mode == Campaign.Mode.FARM and campaign.gold == 70 and campaign.stronghold_cleared,
		"Campaign: checkpoint farm starts immediately without payment or lost clearance")
	campaign_fresh(campaign, stronghold, 1)
	var farm := campaign.battle
	check(campaign.request_frontier() and campaign.battle == farm and campaign.gold == 70,
		"Campaign: post-clear frontier waits for farm completion")
	campaign_finish(campaign)
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.battle == farm
		and campaign.current_encounter == 1 and campaign.gold == 100 and campaign.stronghold_cleared,
		"Campaign: farm pays before returning to checkpoint without Stronghold recreation")
	before = campaign_snapshot(campaign)
	check(not campaign.settle(farm) and not campaign.settle(stronghold)
		and campaign.restart_battle() == null and campaign_snapshot(campaign) == before,
		"Campaign: neither checkpoint terminal object can repay")
	var independent := Campaign.new()
	independent.restart_battle()
	check(not independent.border_cleared and not independent.archer_cleared
		and not independent.stronghold_cleared and independent.gold == 0
		and independent.levels == [1, 1, 1] and independent.battle != campaign.battle,
		"Campaign: objective and ownership are independent per in-memory instance")

func test_campaign_purchases() -> void:
	var campaign := Campaign.new()
	campaign.restart_battle()
	campaign_finish(campaign)
	campaign.request_farm(0)
	campaign.gold = 60
	var combat := campaign.battle
	var stats_before: Array = campaign_snapshot(campaign)[17]
	check(campaign.purchase(1) and campaign.gold == 40 and campaign.levels == [1, 2, 1]
		and campaign_snapshot(campaign)[17] == stats_before and campaign.battle == combat,
		"Campaign: mid-battle purchase leaves complete active squad stats unchanged")
	var before := campaign_snapshot(campaign)
	check(not campaign.purchase(-1) and not campaign.purchase(3) and campaign_snapshot(campaign) == before,
		"Campaign: invalid purchases preserve navigation and battle")
	campaign_finish(campaign)
	check(campaign.gold == 70 and campaign.battle.players[1].health == 52
		and campaign.battle.players[1].damage == 12 and campaign.current_encounter == 0,
		"Campaign: transition applies purchased full-health snapshot after reward")
	campaign.request_frontier()
	check(campaign.purchase(1), "Campaign: next purchased level through inherited API")
	before = campaign_snapshot(campaign)
	check(not campaign.purchase(1) and campaign_snapshot(campaign) == before,
		"Campaign: capped purchase preserves queued frontier")
	var old := campaign.battle
	campaign.restart_battle()
	check(campaign.battle.players[1].health == 64 and campaign.battle.players[1].damage == 16
		and campaign.mode == Campaign.Mode.FARM and campaign.farm_encounter == 0
		and campaign.pending_navigation == Campaign.Navigation.NONE and campaign.gold == 30,
		"Campaign: explicit farm restart refreshes purchases and retains farm selection")
	campaign_fresh(campaign, old, 0)
	campaign_finish(campaign)
	check(campaign.battle.players[1].health == 64, "Campaign: farm replay retains purchased full health")
	campaign.gold = 0
	before = campaign_snapshot(campaign)
	check(not campaign.purchase(0) and campaign_snapshot(campaign) == before,
		"Campaign: unaffordable purchase is inert")
	campaign.request_frontier()
	for squad in campaign.battle.players:
		squad.health = 0
	campaign_finish(campaign)
	check(campaign.current_encounter == 3 and campaign.gold == 0 and campaign.levels == [1, 3, 1]
		and campaign.battle.players[1].health == 64 and campaign.battle.players[1].damage == 16,
		"Campaign: defeat frontier retry preserves purchases and refreshes stats")

func test_campaign_determinism() -> void:
	var runs: Array = []
	for repeat in range(2):
		var campaign := Campaign.new()
		campaign.restart_battle()
		var snapshots: Array = [campaign_snapshot(campaign, false)]
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		campaign.request_farm(0)
		campaign.battle.queue_commander()
		snapshots.append(campaign_snapshot(campaign, false))
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		for squad in campaign.battle.players:
			squad.health = 0
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		campaign.gold = 180
		for role in range(3):
			campaign.purchase(role)
			campaign.purchase(role)
		campaign.request_frontier()
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		campaign.request_farm(0)
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		campaign.request_farm(1)
		campaign.request_frontier()
		campaign_finish(campaign)
		snapshots.append(campaign_snapshot(campaign, false))
		runs.append(snapshots)
	check(runs[0] == runs[1], "Campaign: repeated advance navigation loss checkpoint sequences exactly deterministic")

func test_fortified_economy() -> void:
	check(Data.Encounter.BORDER_SKIRMISH == 0 and Data.Encounter.ARCHER_POSITION == 1
		and Data.Encounter.FORTIFIED_POSITION == 2, "Fortified: stable encounter IDs")
	var economy := Economy.new()
	var original := economy.restart_battle()
	original.queue_commander()
	economy.gold = 1000
	for shield in range(1, 4):
		for foot in range(1, 4):
			for horse in range(1, 4):
				economy.levels.assign([shield, foot, horse])
				var unlocked: bool = shield >= 2 and foot >= 2 and horse >= 2
				check(economy.is_encounter_unlocked(2) == unlocked, "Fortified unlock: all ownership combinations %s" % [economy.levels])
				if not unlocked:
					check(economy.restart_battle(2) == null and economy.battle == original
						and original.commander_queued and not economy._settled and economy.gold == 1000,
						"Fortified unlock: rejected selection preserves model %s" % [economy.levels])
	for role in range(3):
		economy.levels.assign([2, 2, 2])
		economy.levels[role] = 1
		economy.gold = 19
		check(not economy.purchase(role) and not economy.is_encounter_unlocked(2), "Fortified unlock: insufficient last purchase %d" % role)
		economy.gold = 20
		check(economy.purchase(role) and economy.gold == 0 and economy.is_encounter_unlocked(2), "Fortified unlock: last role purchase %d" % role)
		economy.levels.assign([1, 1, 1])
		economy.levels[role] = 3
		check(not economy.purchase(role) and not economy.is_encounter_unlocked(2), "Fortified unlock: single cap stays locked %d" % role)
	economy.levels.assign([2, 2, 2])
	var battle := economy.restart_battle(2)
	check(battle.enemies[0].health == 160 and battle.enemies[0].damage == 12
		and battle.enemies[1].health == 80 and battle.enemies[1].damage == 12
		and economy.encounter_reward(2) == 54 and economy.gold == 0, "Fortified: authored fixture and revised reward")
	check(not economy.settle(original) and not economy.settle(null) and not economy.settle(battle), "Fortified: stale null ongoing settlements rejected")
	for victory in range(2):
		while battle.result == Combat.Result.ONGOING:
			battle.step_round()
		check(battle.result == Combat.Result.VICTORY and economy.settle(battle)
			and economy.gold == 54 * (victory + 1) and not economy.settle(battle), "Fortified: real victory pays 54 exactly once %d" % victory)
		var previous := battle
		battle = economy.restart_battle()
		check(battle != previous and battle.players[0] != previous.players[0]
			and battle.enemies[0] != previous.enemies[0] and battle.enemies[0].health == 160
			and battle.players[0].health == 160 and economy.current_encounter == 2
			and not economy.settle(previous), "Fortified: fresh independent replay retains selection %d" % victory)
	# Counterfactual baseline ownership produces a real defeat without changing combat rules.
	battle.players = Combat.new().players
	while battle.result == Combat.Result.ONGOING:
		battle.step_round()
	check(battle.result == Combat.Result.DEFEAT and economy.settle(battle)
		and economy.gold == 108 and not economy.settle(battle), "Fortified: real defeat pays zero once")
	economy.restart_battle(0)
	check(economy.gold == 108 and economy.battle.enemies[0].health == 72, "Fortified: return to Border without payment")

func test_fortified_adapter() -> void:
	var scene := fresh_scene()
	var original := scene.battle
	scene._command()
	scene.advance_usec(250000)
	for selection in [2, 99, 0]:
		scene._select_encounter(selection)
		check(scene.battle == original and original.commander_queued and scene.elapsed_usec == 250000
			and not scene.economy._settled and scene.replay_timer.is_stopped()
			and scene.economy.gold == 0 and scene.economy.levels == [1, 1, 1], "Fortified adapter: locked invalid same preserve state %d" % selection)
	check(scene.get_node("%FortifiedSelect").disabled and scene.get_node("%FortifiedUnlockHint").visible, "Fortified adapter: locked presentation")
	scene.economy.gold = 100
	for role in range(3):
		scene._purchase(role)
	check(not scene.get_node("%FortifiedSelect").disabled and not scene.get_node("%FortifiedUnlockHint").visible
		and original.players[0].max_health == 120, "Fortified adapter: immediate unlock leaves snapshot")
	scene._select_encounter(2)
	check(scene.battle != original and scene.elapsed_usec == 0 and not scene.battle.commander_queued
		and scene.economy.gold == 40 and scene.replay_timer.is_stopped(), "Fortified adapter: ongoing switch clears transients without payout")
	check(scene.get_node("%Title").text == "FORTIFIED POSITION" and scene.get_node("%FortifiedSelect").disabled
		and not scene.get_node("%BorderSelect").disabled and not scene.get_node("%ArcherSelect").disabled
		and scene.get_node("%EnemyFootRow").visible and scene.health_bars[3].value == 160
		and scene.health_bars[4].value == 80 and scene.gold_label.text.contains("+54"), "Fortified adapter: title selectors two rows reward")
	scene.advance_time(1)
	check(scene.health_bars[3].value == 142 and scene.health_bars[4].value == 71, "Fortified adapter: both damaged rows render")
	scene._purchase(1)
	check(scene.battle.players[1].damage == 12 and scene.economy.levels == [2, 3, 2], "Fortified adapter: purchase waits for next snapshot")
	original = scene.battle
	scene.suspended = true
	scene._select_encounter(0)
	check(scene.battle == original, "Fortified adapter: suspension rejects selection")
	scene.suspended = false
	scene.advance_time(9)
	check(scene.economy.gold == 54 and scene.status_label.text.contains("+54")
		and not scene.replay_timer.is_stopped() and scene.health_bars[3].value == 0
		and scene.health_bars[4].value == 0, "Fortified adapter: timed victory pays and schedules replay")
	for selection in [2, 99, -1]:
		scene._select_encounter(selection)
		check(scene.battle == original and scene.economy._settled and not scene.replay_timer.is_stopped()
			and scene.economy.battle == original and scene.economy.current_encounter == 2
			and scene.economy._battle_reward == 54 and scene.economy.levels == [2, 3, 2]
			and scene.economy.gold == 54, "Fortified adapter: pending replay preserved on rejection %d" % selection)
	scene.replay_timer.timeout.emit()
	check(scene.economy.current_encounter == 2 and scene.battle.rounds == 0
		and scene.battle.players[1].damage == 16 and scene.battle.players[1].health == 64
		and scene.replay_timer.is_stopped(), "Fortified adapter: replay fresh upgraded selection")
	scene._command()
	scene.advance_usec(250000)
	scene.restart_battle()
	check(scene.economy.current_encounter == 2 and scene.elapsed_usec == 0 and not scene.battle.commander_queued
		and scene.battle.enemies[1].health == 80 and scene.economy.gold == 54, "Fortified adapter: restart retains selection without payment")
	scene.advance_time(9)
	scene._select_encounter(0)
	check(scene.economy.gold == 108 and scene.replay_timer.is_stopped()
		and not scene.get_node("%EnemyFootRow").visible and scene.health_bars[3].value == 72,
		"Fortified adapter: settled switch cancels replay retains gold hides second row")
	scene._select_encounter(1)
	check(scene.get_node("%Title").text == "ARCHER POSITION" and scene.get_node("%EnemyFootRow").visible
		and scene.health_bars[3].value == 100 and scene.health_bars[4].value == 40
		and scene.gold_label.text.contains("+30"), "Fortified adapter: Archer fixture restored")
	scene._select_encounter(2)
	scene.battle.players = Combat.new().players
	scene.advance_time(60)
	check(scene.battle.result == Combat.Result.DEFEAT and scene.economy.gold == 108
		and not scene.replay_timer.is_stopped() and scene.replay_timer.wait_time == 1.0, "Fortified adapter: defeat schedules same one-second replay")
	scene.replay_timer.timeout.emit()
	check(scene.battle.players[0].health == 160 and scene.battle.rounds == 0
		and scene.economy.current_encounter == 2, "Fortified adapter: defeat replay restores owned army")
	scene.free()

	scene = fresh_scene()
	scene.economy.levels.assign([2, 2, 2])
	scene.economy.gold = 40
	scene._select_encounter(2)
	original = scene.battle
	scene._command()
	scene.advance_usec(250000)
	var last_frame := scene.last_frame_usec
	scene._select_encounter(-1)
	check(scene.battle == original and scene.economy.battle == original
		and scene.economy.current_encounter == 2 and scene.elapsed_usec == 250000
		and scene.last_frame_usec == last_frame and scene.battle.commander_queued
		and scene.economy.levels == [2, 2, 2] and scene.economy.gold == 40
		and not scene.economy._settled and scene.economy._battle_reward == 54
		and scene.replay_timer.is_stopped(), "Fortified adapter: invalid sentinel preserves ongoing state")
	scene.free()

func test_fortified_saves() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "Fortified save: isolated ownership")
	if not fixture.owned:
		return
	for owned in [[1, 1, 1], [3, 1, 1], [2, 2, 1], [2, 2, 2], [3, 3, 3]]:
		var text := JSON.stringify({"version": 1, "gold": 20, "levels": owned})
		check(fixture.put(text) == OK, "Fortified save: old version-1 fixture")
		var scene: Presentation = BattleScene.instantiate()
		scene.progress_save = ProgressSave.new(fixture.path)
		root.add_child(scene)
		check(scene.economy.is_encounter_unlocked(2) == (owned.min() >= 2)
			and scene.economy.current_encounter == 0 and scene.battle.rounds == 0
			and FileAccess.get_file_as_string(fixture.path) == text, "Fortified save: loaded ownership derives unlock without write %s" % [owned])
		scene.free()
	check(DirAccess.remove_absolute(fixture.path) == OK
		and fixture.put('{"version":1,"gold":20,"levels":[2,2,2]}', ".bak") == OK, "Fortified save: qualifying backup fixture")
	var recovered: Presentation = BattleScene.instantiate()
	recovered.progress_save = ProgressSave.new(fixture.path)
	root.add_child(recovered)
	check(recovered.economy.is_encounter_unlocked(2) and recovered.economy.current_encounter == 0
		and not FileAccess.file_exists(fixture.path), "Fortified save: backup unlock without startup rewrite")
	recovered.free()
	check(fixture.put('{"version":1,"gold":20,"levels":[2,2,1]}') == OK, "Fortified save: last purchase fixture")
	var store := FailingSave.new(fixture.path)
	var scene: Presentation = BattleScene.instantiate()
	scene.progress_save = store
	root.add_child(scene)
	scene.set_process(false)
	scene.suspended = false
	scene.skip_resume_frame = false
	store.fail_write = true
	scene._purchase(2)
	check(scene.economy.is_encounter_unlocked(2) and not scene.get_node("%FortifiedSelect").disabled
		and scene.economy.gold == 0 and scene.save_status.text.contains("not saved"), "Fortified save: failed last purchase retains in-memory unlock")
	var unsaved: Presentation = BattleScene.instantiate()
	unsaved.progress_save = ProgressSave.new(fixture.path)
	root.add_child(unsaved)
	check(not unsaved.economy.is_encounter_unlocked(2) and unsaved.economy.levels == [2, 2, 1]
		and unsaved.economy.gold == 20, "Fortified save: relaunch sees only successful ownership")
	unsaved.free()
	store.fail_write = false
	scene._select_encounter(2)
	scene.advance_time(10)
	var saved := ProgressSave.new(fixture.path).load_progress()
	check(saved.gold == 54 and saved.levels == [2, 2, 2] and not scene.economy.settle(scene.battle)
		and scene.save_status.text.contains("Progress saved"), "Fortified save: real victory retries full ownership and 54 once")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	check(payload.size() == 3 and payload.version == 1 and payload.has("gold") and payload.has("levels"), "Fortified save: unchanged version and keys")
	scene.free()
	var reloaded: Presentation = BattleScene.instantiate()
	reloaded.progress_save = ProgressSave.new(fixture.path)
	root.add_child(reloaded)
	check(reloaded.economy.gold == 54 and reloaded.economy.levels == [2, 2, 2]
		and reloaded.economy.is_encounter_unlocked(2) and reloaded.economy.current_encounter == 0
		and reloaded.battle.rounds == 0 and reloaded.battle.players[0].health == 160
		and not reloaded.battle.commander_queued and reloaded.elapsed_usec == 0
		and reloaded.replay_timer.is_stopped(), "Fortified save: reward reload starts clean Border")
	reloaded.free()
	check(fixture.cleanup() == OK, "Fortified save: isolated cleanup")

func test_encounter_adapter() -> void:
	var scene := fresh_scene()
	var original := scene.battle
	scene._select_encounter(Data.Encounter.ARCHER_POSITION)
	check(scene.battle == original and scene.get_node("%ArcherSelect").disabled, "selection: locked UI and boundary")
	scene.economy.gold = 60
	scene._purchase(0)
	check(not scene.get_node("%ArcherSelect").disabled and scene.battle == original
		and original.players[0].max_health == 120, "selection: purchase unlocks without changing snapshot")
	scene._command()
	scene.advance_usec(350000)
	scene._select_encounter(99)
	check(scene.battle == original and scene.elapsed_usec == 350000 and original.commander_queued, "selection: rejected start retains transients")
	scene._select_encounter(Data.Encounter.ARCHER_POSITION)
	check(scene.battle != original and scene.elapsed_usec == 0 and not scene.battle.commander_queued
		and scene.replay_timer.is_stopped() and scene.economy.gold == 40, "selection: abandons queue and partial round without payout")
	check(scene.health_bars[3].value == 100 and scene.health_bars[4].value == 40
		and scene.get_node("%EnemyFootRow").visible and scene.gold_label.text.contains("+30"), "selection: two initial enemy rows and reward")
	scene.advance_time(1)
	check(scene.health_bars[3].value == 86 and scene.health_bars[4].value == 34, "selection: both damaged enemies render")
	scene._purchase(1)
	check(scene.battle.players[1].damage == 8 and scene.economy.levels == [2, 2, 1], "selection: mid-Archer purchase leaves snapshot")
	scene.advance_time(7)
	check(scene.health_bars[3].value == 0 and scene.health_bars[4].value == 0
		and scene.economy.gold == 50 and scene.status_label.text.contains("+30"), "selection: dead rows and correct settled reward")
	scene.replay_timer.timeout.emit()
	check(scene.economy.current_encounter == Data.Encounter.ARCHER_POSITION and scene.battle.rounds == 0
		and scene.battle.players[1].damage == 12 and scene.replay_timer.is_stopped(), "selection: replay retains encounter and applies purchase")
	original = scene.battle
	scene.suspended = true
	scene._select_encounter(Data.Encounter.BORDER_SKIRMISH)
	check(scene.battle == original, "selection: suspension rejects selection")
	scene.suspended = false
	scene.advance_time(8)
	var paid: int = scene.economy.gold
	scene._select_encounter(Data.Encounter.BORDER_SKIRMISH)
	check(scene.replay_timer.is_stopped() and scene.economy.gold == paid
		and scene.battle.enemies.size() == 1 and not scene.get_node("%EnemyFootRow").visible,
		"selection: pending replay cancelled and settled reward retained returning Border")
	scene.free()

func test_encounter_saves() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "encounter save: isolated ownership")
	if not fixture.owned:
		return
	for owned in [[1, 1, 1], [2, 1, 1]]:
		var text := JSON.stringify({"version": 1, "gold": 0, "levels": owned})
		check(fixture.put(text) == OK, "encounter save: version-1 fixture")
		var scene: Presentation = BattleScene.instantiate()
		scene.progress_save = ProgressSave.new(fixture.path)
		root.add_child(scene)
		check(scene.economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION) == (owned[0] == 2)
			and scene.economy.current_encounter == Data.Encounter.BORDER_SKIRMISH
			and FileAccess.get_file_as_string(fixture.path) == text, "encounter save: unlock derived without startup rewrite")
		scene.free()
	check(DirAccess.remove_absolute(fixture.path) == OK
		and fixture.put('{"version":1,"gold":0,"levels":[2,1,1]}', ".bak") == OK, "encounter save: recovery fixture")
	var store := FailingSave.new(fixture.path)
	var scene: Presentation = BattleScene.instantiate()
	scene.progress_save = store
	root.add_child(scene)
	scene.set_process(false)
	scene.suspended = false
	scene.skip_resume_frame = false
	check(scene.economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION), "encounter save: recovered backup unlocks")
	scene._select_encounter(Data.Encounter.ARCHER_POSITION)
	store.fail_write = true
	scene.advance_time(8)
	check(scene.economy.gold == 30 and scene.save_status.text.contains("not saved"), "encounter save: failed Archer save retains reward and unlock")
	store.fail_write = false
	scene._purchase(1)
	var saved := ProgressSave.new(fixture.path).load_progress()
	check(saved.gold == 10 and saved.levels == [2, 2, 1] and not scene.economy.settle(scene.battle), "encounter save: retry full state without duplicate payout")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	check(payload.size() == 3 and payload.has("version") and payload.has("gold") and payload.has("levels"), "encounter save: no new schema keys")
	scene._select_encounter(Data.Encounter.BORDER_SKIRMISH)
	scene.advance_time(4)
	check(ProgressSave.new(fixture.path).load_progress().gold == 20, "encounter save: returning Border saves only 10")
	scene._select_encounter(Data.Encounter.ARCHER_POSITION)
	scene._command()
	scene.advance_usec(250000)
	scene.free()
	var reloaded: Presentation = BattleScene.instantiate()
	reloaded.progress_save = ProgressSave.new(fixture.path)
	root.add_child(reloaded)
	check(reloaded.economy.current_encounter == Data.Encounter.BORDER_SKIRMISH
		and reloaded.economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION)
		and reloaded.economy.gold == 20 and reloaded.battle.rounds == 0
		and not reloaded.battle.commander_queued and reloaded.elapsed_usec == 0
		and reloaded.replay_timer.is_stopped() and reloaded.battle.players[0].health == 160,
		"encounter save: reload resets selection and transients, preserves ownership")
	reloaded.free()
	check(fixture.cleanup() == OK, "encounter save: isolated cleanup")

func test_encounter_economy() -> void:
	var economy := Economy.new()
	var original := economy.restart_battle()
	check(not economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION), "encounter: fresh locked")
	check(not economy.purchase(0) and not economy.is_encounter_unlocked(1), "encounter: rejected purchase stays locked")
	economy.gold = 100
	for invalid in [Data.Encounter.ARCHER_POSITION, 99, -2]:
		check(economy.restart_battle(invalid) == null and economy.battle == original
			and economy.current_encounter == Data.Encounter.BORDER_SKIRMISH and economy.gold == 100
			and economy.levels == [1, 1, 1] and not economy._settled, "encounter: gold-only invalid start preserves state %d" % invalid)
	for role in range(3):
		economy.levels.assign([1, 1, 1])
		economy.levels[role] = 2
		check(economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION), "encounter: each role unlocks %d" % role)
	var archer := economy.restart_battle(Data.Encounter.ARCHER_POSITION)
	check(archer != null and not economy.settle(original) and not economy.settle(null)
		and not economy.settle(archer) and economy.gold == 100, "encounter: stale null ongoing do not pay")
	while archer.result == Combat.Result.ONGOING:
		archer.step_round()
	check(economy.settle(archer) and economy.gold == 130 and not economy.settle(archer), "encounter: Archer pays 30 once")
	check(economy.restart_battle(99) == null and economy.battle == archer and economy._settled, "encounter: invalid start preserves settled state")
	var replay := economy.restart_battle()
	check(replay.enemies.size() == 2 and replay != archer, "encounter: restart retains selection")
	for squad in replay.players:
		squad.health = 0
	replay.step_round()
	check(economy.settle(replay) and economy.gold == 130, "encounter: defeat pays nothing")
	var border := economy.restart_battle(Data.Encounter.BORDER_SKIRMISH)
	while border.result == Combat.Result.ONGOING:
		border.step_round()
	check(economy.settle(border) and economy.gold == 140, "encounter: return to Border pays 10")

func balance_battle(owned: Array, encounter: int, active: bool, enemy_override: Array[Data.Squad] = []) -> Combat:
	var army := Data.players()
	for squad in army:
		squad.max_health += Economy.HEALTH_GAIN[squad.role] * (owned[squad.role] - 1)
		squad.damage += Economy.DAMAGE_GAIN[squad.role] * (owned[squad.role] - 1)
	var combat := Combat.new(encounter, army)
	if not enemy_override.is_empty():
		combat.enemies = enemy_override
	for round_index in range(60):
		if combat.result != Combat.Result.ONGOING:
			break
		if active:
			combat.queue_commander()
		combat.step_round()
	return combat

func fortified_candidate() -> Array[Data.Squad]:
	return [Data.Squad.new(Data.Role.SHIELD, "Enemy shield", 160, 12),
		Data.Squad.new(Data.Role.FOOT, "Enemy foot archers", 80, 12)]

func balance_snapshot(combat: Combat) -> Array:
	return [combat.result, combat.rounds,
		combat.players.map(func(squad: Data.Squad) -> int: return squad.health),
		combat.enemies.map(func(squad: Data.Squad) -> int: return squad.health)]

func test_fortified_balance() -> void:
	var cases := [
		[[1, 1, 1], 10, 10, false, false],
		[[2, 1, 1], 12, 11, false, true],
		[[1, 2, 1], 11, 10, false, true],
		[[1, 1, 2], 13, 10, false, true],
		[[2, 2, 2], 10, 7, true, true],
		[[3, 3, 3], 7, 6, true, true],
	]
	for row in cases:
		for active in [false, true]:
			var battle := balance_battle(row[0], 0, active, fortified_candidate())
			check(battle.rounds == row[2 if active else 1]
				and (battle.result == Combat.Result.VICTORY) == row[4 if active else 3],
				"Fortified proposal: exact outcome/duration %s active=%s" % [row[0], active])
	for row in [
		[[1, 1, 1], [0, 0, 0], [0, 0, 0]],
		[[2, 2, 2], [0, 52, 20], [4, 52, 80]],
		[[3, 3, 3], [32, 64, 100], [68, 64, 100]],
	]:
		for active in [false, true]:
			check(balance_snapshot(balance_battle(row[0], 0, active, fortified_candidate()))[2] == row[2 if active else 1],
				"Fortified proposal: exact terminal HP %s active=%s" % [row[0], active])
	for shield in range(1, 4):
		for foot in range(1, 4):
			for horse in range(1, 4):
				var owned := [shield, foot, horse]
				for encounter in range(3):
					for active in [false, true]:
						var enemies: Array[Data.Squad] = []
						var repeat_enemies: Array[Data.Squad] = []
						if encounter == 2:
							enemies = fortified_candidate()
							repeat_enemies = fortified_candidate()
						var battle := balance_battle(owned, mini(encounter, 1), active, enemies)
						var repeat := balance_battle(owned, mini(encounter, 1), active, repeat_enemies)
						var snapshot := balance_snapshot(battle)
						if encounter == 2:
							check(snapshot == balance_snapshot(balance_battle(owned, Data.Encounter.FORTIFIED_POSITION, active)),
								"Fortified matrix: production fixture matches verified candidate %s active=%s" % [owned, active])
						check(snapshot == balance_snapshot(repeat) and battle.players[0] != repeat.players[0]
							and battle.enemies[0] != repeat.enemies[0],
							"Fortified matrix: complete deterministic independent snapshot %s encounter=%d active=%s" % [owned, encounter, active])
						var reward: int = [10, 30, 54][encounter] if battle.result == Combat.Result.VICTORY else 0
						print("BALANCE levels=%s encounter=%d active=%s snapshot=%s combat_rate=%.6f loop_rate=%.6f" % [owned, encounter, active, snapshot, float(reward) / battle.rounds, float(reward) / (battle.rounds + 1)])
						if encounter == 2 and shield >= 2 and foot >= 2 and horse >= 2:
							var archer := balance_battle(owned, 1, active)
							check(battle.result == Combat.Result.VICTORY and battle.rounds > archer.rounds,
								"Fortified matrix: unlocked victory longer than Archer %s active=%s" % [owned, active])
							check(54.0 / battle.rounds >= 30.0 / archer.rounds
								and 54.0 / (battle.rounds + 1) >= 30.0 / (archer.rounds + 1),
								"Fortified matrix: unlocked rates do not regress against Archer %s active=%s" % [owned, active])
							for role in range(3):
								if owned[role] == 3:
									continue
								var upgraded := owned.duplicate()
								upgraded[role] += 1
								var next := balance_battle(upgraded, 0, active, fortified_candidate())
								check(next.result == Combat.Result.VICTORY and next.rounds <= battle.rounds,
									"Fortified matrix: upgrade rate does not regress %s role=%d active=%s" % [owned, role, active])

func test_progression_balance() -> void:
	var cases := [
		[[1, 1, 1], 4, 3, 8, 16, 7, 28],
		[[2, 1, 1], 4, 3, 8, 56, 6, 82],
		[[1, 2, 1], 4, 3, 7, 22, 6, 42],
		[[1, 1, 2], 4, 3, 7, 38, 6, 44],
		[[2, 2, 2], 3, 2, 6, 84, 5, 96],
		[[3, 3, 3], 2, 2, 5, 138, 4, 150],
	]
	for row in cases:
		for active in [false, true]:
			var border := balance_battle(row[0], Data.Encounter.BORDER_SKIRMISH, active)
			var archer := balance_battle(row[0], Data.Encounter.ARCHER_POSITION, active)
			check(border.result == Combat.Result.VICTORY and border.rounds == row[2 if active else 1], "balance: exact Border rounds %s active=%s" % [row[0], active])
			check(archer.result == Combat.Result.VICTORY and archer.rounds == row[5 if active else 3]
				and archer.players[0].health == row[6 if active else 4]
				and archer.players[1].health == archer.players[1].max_health
				and archer.players[2].health == archer.players[2].max_health, "balance: exact Archer rounds and health %s active=%s" % [row[0], active])
	for shield in range(1, 4):
		for foot in range(1, 4):
			for horse in range(1, 4):
				for encounter in [Data.Encounter.BORDER_SKIRMISH, Data.Encounter.ARCHER_POSITION]:
					for active in [false, true]:
						var owned := [shield, foot, horse]
						var combat := balance_battle(owned, encounter, active)
						var repeat := balance_battle(owned, encounter, active)
						check(combat.result == Combat.Result.VICTORY and combat.rounds <= 60
							and combat != repeat and combat.players[0] != repeat.players[0]
							and combat.enemies[0] != repeat.enemies[0]
							and combat.rounds == repeat.rounds and combat.players[0].health == repeat.players[0].health,
							"balance: deterministic independent victory %s encounter=%d active=%s" % [owned, encounter, active])
	check(Data.players()[0].max_health == 120 and Data.players()[1].damage == 8
		and Data.enemies(Data.Encounter.ARCHER_POSITION)[0].max_health == 100,
		"balance: authored fixtures unchanged")

# Deliberately scrambled order and misleading titles: roles alone determine targets.
func priority_targets(mask: int, omit_dead: bool) -> Array[Data.Squad]:
	var squads: Array[Data.Squad] = []
	for role in [Data.Role.FOOT, Data.Role.SHIELD, Data.Role.HORSE]:
		var alive: bool = (mask & (1 << role)) != 0
		if alive or not omit_dead:
			squads.append(Data.Squad.new(role, "Horse shield foot", 30 if alive else 0, 0))
	return squads

func test_conquest_targeting() -> void:
	for enemy_attacks in [false, true]:
		for role in [Data.Role.SHIELD, Data.Role.FOOT, Data.Role.HORSE]:
			var priority: Array = [Data.Role.SHIELD, Data.Role.HORSE, Data.Role.FOOT]
			if role == Data.Role.HORSE:
				priority = [Data.Role.FOOT, Data.Role.HORSE, Data.Role.SHIELD]
			for mask in range(1, 8):
				for omit_dead in [false, true]:
					var battle := Combat.new()
					var targets := priority_targets(mask, omit_dead)
					var attacker: Array[Data.Squad] = [Data.Squad.new(role, "Not a role", 30, 7)]
					battle.players = targets if enemy_attacks else attacker
					battle.enemies = attacker if enemy_attacks else targets
					var expected_role: int = -1
					for candidate in priority:
						if (mask & (1 << candidate)) != 0:
							expected_role = candidate
							break
					battle.step_round()
					var correct: bool = attacker[0].health == 30
					for target in targets:
						correct = correct and target.health == (23 if target.role == expected_role else target.max_health)
					check(correct, "priority: enemy=%s role=%d mask=%d absent=%s" % [enemy_attacks, role, mask, omit_dead])
	# Commander uses frontline priority even after casualties and fixture reordering.
	for mask in range(1, 8):
		var battle := Combat.new()
		battle.players[0].health = 0
		battle.players[1].health = 0
		battle.players[2].damage = 0
		battle.enemies = priority_targets(mask, false)
		var expected_role: int = Data.Role.FOOT
		if (mask & (1 << Data.Role.SHIELD)) != 0:
			expected_role = Data.Role.SHIELD
		elif (mask & (1 << Data.Role.HORSE)) != 0:
			expected_role = Data.Role.HORSE
		check(battle.commander_damage == 6 and battle.queue_commander()
			and not battle.queue_commander(), "commander: fixed starting strength and one queue, mask=%d" % mask)
		battle.step_round()
		var correct: bool = not battle.commander_queued
		for target in battle.enemies:
			correct = correct and target.health == (24 if target.role == expected_role else target.max_health)
		check(correct, "commander: highest living priority, mask=%d" % mask)
	var combined := Combat.new(Data.Encounter.ARCHER_POSITION)
	combined.players[2].health = 0
	combined.enemies[0].health = 5
	combined.queue_commander()
	combined.step_round()
	check(combined.enemies[0].health == 0 and combined.enemies[1].health == 40
		and combined.players[0].health == 106, "combined attacks and commander: no retarget or overkill spill")
	var dying := Combat.new(Data.Encounter.ARCHER_POSITION)
	dying.enemies[1].health = 1
	dying.step_round()
	check(dying.enemies[1].health == 0 and dying.enemies[0].health == 88
		and dying.players[0].health == 106, "dying enemy foot: death-round attack still lands")
	for win in [false, true]:
		var boundary := Combat.new(Data.Encounter.ARCHER_POSITION)
		boundary.rounds = 59
		if win:
			boundary.enemies[0].health = 1
			boundary.enemies[1].health = 1
		boundary.queue_commander()
		boundary.step_round()
		check(boundary.rounds == 60 and not boundary.commander_queued
			and boundary.result == (Combat.Result.VICTORY if win else Combat.Result.DEFEAT),
			"round 60: damage precedes timeout, victory=%s" % win)
		var before := health_snapshot(boundary.players) + health_snapshot(boundary.enemies)
		boundary.step_round()
		check(not boundary.queue_commander() and boundary.rounds == 60
			and before == health_snapshot(boundary.players) + health_snapshot(boundary.enemies),
			"multi-enemy terminal: frozen health, rounds and queue, victory=%s" % win)
	var mutual := Combat.new(Data.Encounter.ARCHER_POSITION)
	mutual.players = [Data.Squad.new(Data.Role.SHIELD, "Front", 1, 1),
		Data.Squad.new(Data.Role.HORSE, "Mobile", 1, 1)]
	mutual.enemies = [Data.Squad.new(Data.Role.SHIELD, "Front", 1, 1),
		Data.Squad.new(Data.Role.HORSE, "Mobile", 1, 1)]
	mutual.queue_commander()
	mutual.step_round()
	check(mutual.result == Combat.Result.DEFEAT and mutual.players[0].health == 0
		and mutual.players[1].health == 0 and health_snapshot(mutual.enemies) == [0, 0]
		and not mutual.commander_queued,
		"multi-enemy mutual elimination: defeat and cleared strike")

func health_snapshot(squads: Array[Data.Squad]) -> Array[int]:
	var health: Array[int] = []
	for squad in squads:
		health.append(squad.health)
	return health

func test_archer_position() -> void:
	var battle := Combat.new(Data.Encounter.ARCHER_POSITION)
	check(battle.enemies.size() == 2 and health_snapshot(battle.enemies) == [100, 40]
		and battle.enemies[0].damage == 6 and battle.enemies[1].damage == 8
		and battle.enemies[0].role == Data.Role.SHIELD and battle.enemies[1].role == Data.Role.FOOT,
		"archer position: authored enemy fixture")
	for round_index in range(60):
		if battle.result != Combat.Result.ONGOING:
			break
		var players_before := health_snapshot(battle.players)
		var enemies_before := health_snapshot(battle.enemies)
		var expected_players: Array[int] = players_before.duplicate()
		var expected_enemies: Array[int] = enemies_before.duplicate()
		# Independent oracle for this authored encounter, using round-start health only.
		var front: int = 0 if players_before[0] > 0 else (2 if players_before[2] > 0 else 1)
		var enemy_front: int = 0 if enemies_before[0] > 0 else 1
		var enemy_back: int = 1 if enemies_before[1] > 0 else 0
		for i in range(2):
			if players_before[i] > 0:
				expected_enemies[enemy_front] -= battle.players[i].damage
			if enemies_before[i] > 0:
				expected_players[front] -= battle.enemies[i].damage
		if players_before[2] > 0:
			expected_enemies[enemy_back] -= battle.players[2].damage
		for i in range(expected_players.size()):
			expected_players[i] = maxi(0, expected_players[i])
		for i in range(expected_enemies.size()):
			expected_enemies[i] = maxi(0, expected_enemies[i])
		battle.step_round()
		check(health_snapshot(battle.players) == expected_players
			and health_snapshot(battle.enemies) == expected_enemies,
			"archer position round %d: living round-start targets, no revival" % (round_index + 1))
		if round_index == 0:
			check(expected_enemies == [88, 34] and expected_players == [106, 40, 60],
				"archer position first round: mobile attacks back line")
	check(battle.result == Combat.Result.VICTORY and battle.rounds <= 60
		and health_snapshot(battle.players).max() > 0,
		"archer position: passive victory within limit with survivor")
	for encounter in [Data.Encounter.BORDER_SKIRMISH, Data.Encounter.ARCHER_POSITION]:
		var first := Combat.new(encounter)
		var second := Combat.new(encounter)
		var independent: bool = true
		for i in range(first.players.size()):
			independent = independent and first.players[i] != second.players[i]
		for i in range(first.enemies.size()):
			independent = independent and first.enemies[i] != second.enemies[i]
		first.queue_commander()
		first.step_round()
		first.queue_commander()
		var fresh := Combat.new(Data.Encounter.ARCHER_POSITION)
		check(independent and health_snapshot(second.players) == [120, 40, 60]
			and health_snapshot(second.enemies) == ([72] if encounter == Data.Encounter.BORDER_SKIRMISH else [100, 40])
			and second.rounds == 0 and not second.commander_queued
			and health_snapshot(fresh.players) == [120, 40, 60]
			and health_snapshot(fresh.enemies) == [100, 40]
			and fresh.rounds == 0 and fresh.result == Combat.Result.ONGOING and not fresh.commander_queued,
			"fixtures: independent objects and fresh level 2 after encounter %d" % encounter)

func fresh_scene() -> Presentation:
	var scene: Presentation = BattleScene.instantiate()
	scene.progress_save = null
	root.add_child(scene)
	scene.set_process(false)
	scene.suspended = false
	scene.skip_resume_frame = false
	return scene

func check_fresh(scene: Presentation, title: String) -> void:
	check(scene.battle.enemies[0].health == 72 and scene.battle.players[0].health == 120
		and scene.battle.players[1].health == 40 and scene.battle.players[2].health == 60
		and scene.battle.rounds == 0 and scene.battle.result == Combat.Result.ONGOING
		and not scene.battle.commander_queued and scene.elapsed_usec == 0
		and not scene.commander.disabled and scene.round_label.text.begins_with("Round 0")
		and scene.health_bars[0].value == 120 and scene.health_bars[3].value == 72, title)

func test_timing_partitions() -> void:
	for count in [10, 100]:
		var split := fresh_scene()
		var whole := fresh_scene()
		for i in range(count):
			split.advance_time(1.0 / count)
		whole.advance_time(1.0)
		check_same_timing(split, whole, 0, "%d fractional advances equal one second" % count)
		split.free()
		whole.free()
	# Integer deltas from monotonic timestamps, including a one-microsecond boundary.
	var split := fresh_scene()
	var whole := fresh_scene()
	var seconds := fresh_scene()
	var ticks: Array[int] = [42000000, 42016667, 42033333, 42123456, 42456789, 42999999]
	for i in range(1, ticks.size()):
		var usec: int = ticks[i] - ticks[i - 1]
		split.advance_usec(usec)
		seconds.advance_time(usec / 1000000.0)
	check(split.battle.rounds == 0 and seconds.battle.rounds == 0
		and split.battle.enemies[0].health == 72 and seconds.battle.enemies[0].health == 72
		and split.elapsed_usec == 999999 and seconds.elapsed_usec == 999999,
		"microseconds: no attack one microsecond early")
	split.advance_usec(1)
	seconds.advance_time(0.000001)
	whole.advance_time(1.0)
	check_same_timing(split, whole, 0, "monotonic partitions: exact round boundary")
	check_same_timing(seconds, whole, 0, "seconds boundary: same microsecond partitions")
	split.advance_usec(16667)
	whole.advance_time(0.016667)
	check_same_timing(split, whole, 16667, "microseconds: exact remaining time")
	split.free()
	whole.free()
	seconds.free()

func check_same_timing(split: Presentation, whole: Presentation, remainder: int, title: String) -> void:
	var same_health: bool = split.battle.enemies[0].health == whole.battle.enemies[0].health
	for i in range(split.battle.players.size()):
		same_health = same_health and split.battle.players[i].health == whole.battle.players[i].health
	check(split.battle.rounds == 1 and whole.battle.rounds == 1
		and whole.battle.enemies[0].health == 54 and whole.battle.players[0].health == 117
		and whole.battle.players[1].health == 40 and whole.battle.players[2].health == 60
		and same_health and split.elapsed_usec == remainder and whole.elapsed_usec == remainder,
		title)

func test_foreground_clock() -> void:
	var scene := fresh_scene()
	var now: int = scene.last_frame_usec + 1250000
	scene.advance_foreground(now)
	check(scene.battle.rounds == 1 and scene.elapsed_usec == 250000
		and scene.last_frame_usec == now, "shared clock: consumes pending span exactly")
	scene.advance_foreground(now)
	check(scene.battle.rounds == 1 and scene.elapsed_usec == 250000,
		"shared clock: same timestamp cannot count twice")
	now += 250000
	scene.advance_foreground(now)
	check(scene.battle.rounds == 1 and scene.elapsed_usec == 500000,
		"shared clock: next update consumes only new time")
	scene.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	now += 120000000
	scene.advance_foreground(now)
	check(scene.battle.rounds == 1 and scene.elapsed_usec == 500000
		and scene.last_frame_usec == now, "shared clock: suspended span discarded once")
	scene.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	now += 120000000
	scene.advance_foreground(now)
	scene.advance_foreground(now)
	check(scene.battle.rounds == 1 and scene.elapsed_usec == 500000
		and not scene.skip_resume_frame and scene.last_frame_usec == now,
		"shared clock: resume gap excluded even with input and frame at same timestamp")
	scene.advance_foreground(now + 500000)
	check(scene.battle.rounds == 2 and scene.elapsed_usec == 0,
		"shared clock: foreground continues at exact boundary after resume")
	var before_restart: int = Time.get_ticks_usec()
	scene.restart_battle()
	check(scene.last_frame_usec >= before_restart and scene.last_frame_usec <= Time.get_ticks_usec(),
		"shared clock: restart resets monotonic origin")
	check_fresh(scene, "shared clock: restart clears consumed time and battle")
	scene.free()

func win(economy: Economy) -> Combat:
	var battle: Combat = economy.restart_battle()
	for i in range(60):
		battle.step_round()
	return battle

func test_economy() -> void:
	var economy := Economy.new()
	check(economy.gold == 0 and economy.levels == [1, 1, 1], "economy: fresh ownership")
	var unfinished := economy.restart_battle()
	check(not economy.settle(unfinished) and economy.gold == 0, "ongoing battle cannot pay")
	for i in range(18):
		var completed := win(economy)
		check(economy.settle(completed) and economy.gold == (i + 1) * 10,
			"farming victory %d: exactly 10 gold" % i)
		check(not economy.settle(completed) and economy.gold == (i + 1) * 10,
			"duplicate outcome %d: no second reward" % i)
	var old: Combat = economy.battle
	economy.restart_battle()
	check(not economy.settle(old) and economy.gold == 180, "stale victory cannot pay after restart")
	for role in range(3):
		for level in [1, 2]:
			var before: int = economy.gold
			var prior: Array[int] = economy.levels.duplicate()
			check(economy.purchase_cost(role) == 20 * level and economy.purchase(role)
				and economy.gold == before - 20 * level, "role %d level %d: exact price" % [role, level + 1])
			prior[role] += 1
			check(economy.levels == prior, "purchase changes exactly one level")
			if level == 1:
				var upgraded := economy.restart_battle()
				check(upgraded.players[role].health == [160, 52, 80][role]
					and upgraded.players[role].max_health == [160, 52, 80][role]
					and upgraded.players[role].damage == [6, 12, 9][role],
					"level 2 exact stats: role %d" % role)
	var full := economy.restart_battle()
	for role in range(3):
		check(full.players[role].health == [200, 64, 100][role]
			and full.players[role].max_health == [200, 64, 100][role]
			and full.players[role].damage == [8, 16, 12][role], "level 3 exact stats: role %d" % role)
	check(full.commander_damage == 12 and economy.gold == 0, "all upgrades cost 180; snapshot commander 12")
	economy.gold = 100
	for role in [-1, 0, 1, 2, 3]:
		check(not economy.purchase(role) and economy.gold == 100 and economy.levels == [3, 3, 3],
			"capped or invalid purchase leaves all state unchanged: %d" % role)
	var poor := Economy.new()
	poor.gold = 19
	for role in range(3):
		check(not poor.purchase(role) and poor.gold == 19 and poor.levels == [1, 1, 1],
			"unaffordable purchase unchanged: %d" % role)
	for role in range(3):
		var short_on_gold := Economy.new()
		short_on_gold.gold = 59
		short_on_gold.purchase(role)
		var before: Array[int] = short_on_gold.levels.duplicate()
		check(not short_on_gold.purchase(role) and short_on_gold.gold == 39
			and short_on_gold.levels == before, "level 3 rejects one gold short: role %d" % role)
	var source: Array[Data.Squad] = Data.players()
	var isolated := Combat.new(Data.Encounter.BORDER_SKIRMISH, source)
	source[1].damage = 999
	source[1].health = 0
	check(isolated.players[1].damage == 8 and isolated.players[1].health == 40,
		"combat owns independent squad snapshot")
	var abandoned := poor.restart_battle()
	for i in range(5):
		poor.restart_battle()
	check(poor.gold == 19 and poor.levels == [1, 1, 1], "repeated restart cannot mint rewards")
	for i in range(4):
		abandoned.step_round()
	check(not poor.settle(abandoned) and poor.gold == 19, "abandoned battle later winning cannot pay")
	for squad in poor.battle.players:
		squad.health = 0
	poor.battle.step_round()
	check(poor.settle(poor.battle) and poor.gold == 19 and poor.levels == [1, 1, 1],
		"defeat pays nothing and retains ownership")
	var scene := fresh_scene()
	scene.economy.gold = 60
	scene.advance_time(1.0)
	var snapshot: Combat = scene.battle
	scene.upgrades[1].pressed.emit()
	check(scene.economy.gold == 40 and scene.economy.levels == [1, 2, 1]
		and snapshot.players[1].max_health == 40 and snapshot.players[1].damage == 8
		and snapshot.enemies[0].health == 54 and snapshot.commander_damage == 6,
		"mid-battle purchase changes ownership, not snapshot")
	scene.upgrades[1].pressed.emit()
	scene.advance_time(3.0)
	check(scene.economy.gold == 10 and snapshot.rounds == 4 and not scene.replay_timer.is_stopped(),
		"original snapshot wins in four rounds; reward and replay scheduled")
	scene.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(scene.replay_timer.paused, "result replay pauses with application")
	scene.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not scene.replay_timer.paused, "result replay resumes with application")
	scene.replay_timer.timeout.emit()
	check(scene.battle != snapshot and scene.battle.rounds == 0 and scene.elapsed_usec == 0
		and not scene.battle.commander_queued and scene.battle.players[0].health == 120
		and scene.battle.players[1].health == 64 and scene.battle.players[1].damage == 16
		and scene.battle.players[2].health == 60 and scene.battle.commander_damage == 8,
		"next replay: both purchases, full health, fresh timer and commander snapshot")
	check(not scene.economy.settle(snapshot) and scene.economy.gold == 10, "replay cannot repay old outcome")
	scene.advance_time(0.0) # Exclude the resume frame as in production.
	scene.advance_time(1.0)
	check(scene.battle.enemies[0].health == 46, "next battle uses upgraded 26 damage")
	scene.restart_battle()
	check(scene.economy.gold == 10 and scene.economy.levels == [1, 3, 1]
		and scene.replay_timer.is_stopped(), "manual restart retains purchases, cancels pending replay, pays nothing")
	scene.free()

func test_adapter() -> void:
	var scene := fresh_scene()
	check_fresh(scene, "scene: fresh state and labels")
	scene.advance_time(0.5)
	check(scene.battle.rounds == 0 and scene.battle.enemies[0].health == 72,
		"timing: sub-second has no damage")
	scene.advance_time(0.5)
	scene.advance_time(0.75)
	scene.commander.pressed.emit()
	check(scene.battle.commander_queued and scene.commander.disabled
		and scene.status_label.text.contains("queued"), "scene: command signal updates UI")
	var old_battle: Combat = scene.battle
	scene.restart.pressed.emit()
	check_fresh(scene, "restart: dirty health, partial interval and queue cleared")
	check(scene.battle != old_battle and scene.is_processing(), "restart: fresh model and update active")
	scene.set_process(false)
	scene.advance_time(0.25)
	check(scene.battle.rounds == 0, "restart: no timing remainder")
	scene.advance_time(3.75)
	check(scene.battle.rounds == 4 and scene.battle.result == Combat.Result.VICTORY
		and scene.elapsed_usec == 0 and not scene.is_processing() and scene.commander.disabled,
		"scene: passive victory clears timing and stops updates")
	scene.advance_time(90.0)
	scene.commander.pressed.emit()
	check(scene.battle.rounds == 4 and not scene.battle.commander_queued, "scene: terminal input and time frozen")
	for i in range(5):
		scene.restart.pressed.emit()
		check_fresh(scene, "restart after victory %d: fresh state" % i)
		scene.set_process(false)
		scene.advance_time(4.0)
		check(scene.battle.rounds == 4 and scene.battle.players[0].health == 108,
			"restart %d: unchanged passive outcome" % i)
	check(scene.commander.pressed.get_connections().size() == 1
		and scene.restart.pressed.get_connections().size() == 1,
		"restart: exactly one connection per button")
	scene.restart_battle()
	scene.set_process(false)
	var other := fresh_scene()
	for i in range(10):
		scene.advance_time(0.25)
	other.advance_time(2.5)
	check(scene.battle.rounds == other.battle.rounds
		and scene.battle.enemies[0].health == other.battle.enemies[0].health
		and scene.elapsed_usec == other.elapsed_usec, "timing: equal foreground time, equal rounds")
	scene.commander.pressed.emit()
	scene.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	scene.advance_time(120.0)
	check(scene.battle.rounds == 2 and scene.elapsed_usec == 500000
		and scene.battle.commander_queued, "suspension: health, fraction and queued command frozen")
	scene.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	scene.advance_time(120.0)
	check(scene.battle.rounds == 2 and scene.elapsed_usec == 500000, "resume: gap frame discarded")
	scene.advance_time(0.5)
	check(scene.battle.rounds == 3 and scene.battle.enemies[0].health == 12,
		"resume: next foreground interval continues queued strike")
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	scene.advance_time(10.0)
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	scene.advance_time(10.0)
	check(scene.battle.rounds == 3, "desktop focus: no absence catch-up")
	scene.free()
	other.free()

func test_progress_format() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "save: isolated directory owned")
	if not fixture.owned:
		return
	var store := ProgressSave.new(fixture.path)
	check(store.load_progress().outcome == ProgressSave.Outcome.MISSING and not FileAccess.file_exists(fixture.path), "save: missing does not write")
	check(fixture.put("abandoned", ".tmp") == OK and store.load_progress().outcome == ProgressSave.Outcome.MISSING, "save: abandoned stage ignored")
	for gold in [0, 10, ProgressSave.MAX_GOLD]:
		for level in [1, 2, 3]:
			var levels: Array[int] = [level, level, level]
			check(store.save_progress(gold, levels) == OK, "save: write gold %d level %d" % [gold, level])
			var loaded := ProgressSave.new(fixture.path).load_progress()
			check(loaded.outcome == ProgressSave.Outcome.LOADED and loaded.gold == gold and loaded.levels == levels, "save: exact round trip")
	var isolated := store.load_progress()
	isolated.levels[0] = 1
	check(store.load_progress().levels == [3, 3, 3], "save: returned snapshot isolated")
	var before := FileAccess.get_file_as_bytes(fixture.path)
	check(store.save_progress(-1, [1, 1, 1]) != OK and store.save_progress(ProgressSave.MAX_GOLD + 1, [1, 1, 1]) != OK and store.save_progress(0, [1, 4, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == before, "save: invalid writes preserve primary")
	var invalid: Array[String] = ["", "{", "[]", "null", "true", "{}",
		'{"version":1}', '{"version":true,"gold":0,"levels":[1,1,1]}',
		'{"version":1,"gold":0,"levels":[1,1,1],"extra":0}',
		'{"version":1,"gold":"0","levels":[1,1,1]}',
		'{"version":1,"gold":true,"levels":[1,1,1]}',
		'{"version":1,"gold":-1,"levels":[1,1,1]}',
		'{"version":1,"gold":0.5,"levels":[1,1,1]}',
		'{"version":1,"gold":9007199254740991.1,"levels":[1,1,1]}',
		'{"version":1,"gold":1.00000000000000001,"levels":[1,1,1]}',
		'{"version":1,"gold":1e999,"levels":[1,1,1]}',
		'{"version":1,"gold":9007199254740992,"levels":[1,1,1]}',
		'{"version":1,"gold":0,"levels":{}}',
		'{"version":1,"gold":0,"levels":[1,1]}',
		'{"version":1,"gold":0,"levels":[1,1,1,1]}',
		'{"version":1,"gold":0,"levels":[0,1,1]}',
		'{"version":1,"gold":0,"levels":[1,4,1]}',
		'{"version":1,"gold":0,"levels":[1,1.5,1]}',
		'{"version":1,"gold":0,"levels":[1,true,1]}',
		'{"version":1,"gold":0,"levels":[1,"1",1]}', " ".repeat(4097)]
	for text in invalid:
		check(fixture.put(text) == OK, "save: invalid fixture written")
		var rejected := ProgressSave.new(fixture.path)
		check(rejected.load_progress().outcome == ProgressSave.Outcome.CORRUPT and rejected.save_progress(10, [1, 1, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == text.to_utf8_buffer(), "save: corrupt preserved without backup bypass")
	for text in ['{"version":1.0,"gold":15e1,"levels":[1.0,2e0,30e-1]}', '{"version":1,"gold":0e-999,"levels":[1,2,3]}']:
		check(fixture.put(text) == OK and ProgressSave.new(fixture.path).load_progress().outcome == ProgressSave.Outcome.LOADED, "save: exact whole decimal and exponent forms accepted")
	for text in ['{"version":2}', '{"version":99,"gold":"future payload"}']:
		check(fixture.put(text) == OK, "save: future fixture written")
		var future := ProgressSave.new(fixture.path)
		check(future.load_progress().outcome == ProgressSave.Outcome.UNSUPPORTED and future.save_progress(10, [1, 1, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == text.to_utf8_buffer(), "save: unsupported classified first and preserved")
	check(ProgressSave._validate({"version": 1, "gold": NAN, "levels": [1, 1, 1]}).outcome == ProgressSave.Outcome.CORRUPT and ProgressSave._validate({"version": 1, "gold": INF, "levels": [1, 1, 1]}).outcome == ProgressSave.Outcome.CORRUPT, "save: nonfinite rejected")
	check(fixture.cleanup() == OK, "save: owned format directory cleaned")

func test_progress_failures() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "save failures: directory owned")
	if not fixture.owned:
		return
	var store := FailingSave.new(fixture.path)
	check(store.save_progress(20, [1, 1, 1]) == OK, "save failures: baseline")
	var before := FileAccess.get_file_as_bytes(fixture.path)
	store.fail_write = true
	check(store.save_progress(30, [1, 1, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == before, "save failures: reported flush/write failure preserves primary")
	store.fail_write = false
	check(DirAccess.remove_absolute(fixture.path + ".tmp") == OK and DirAccess.make_dir_absolute(fixture.path + ".tmp") == OK, "save failures: real blocked staging path")
	check(store.save_progress(30, [1, 1, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == before, "save failures: staging open failure preserves primary")
	check(DirAccess.remove_absolute(fixture.path + ".tmp") == OK and DirAccess.make_dir_absolute(fixture.path + ".bak") == OK, "save failures: real backup obstruction")
	check(store.save_progress(30, [1, 1, 1]) != OK and FileAccess.get_file_as_bytes(fixture.path) == before, "save failures: native backup rename failure preserves primary")
	check(DirAccess.remove_absolute(fixture.path + ".bak") == OK, "save failures: backup obstruction removed")
	store.fail_move_to = fixture.path
	check(store.save_progress(30, [1, 1, 1]) != OK and not FileAccess.file_exists(fixture.path) and FileAccess.get_file_as_bytes(fixture.path + ".bak") == before, "save failures: failed commit and restore retain last-good backup")
	var recovery_started := Time.get_ticks_usec()
	var recovered := ProgressSave.new(fixture.path).load_progress()
	print("RECOVERY: validated backup loaded in %d usec" % (Time.get_ticks_usec() - recovery_started))
	check(recovered.outcome == ProgressSave.Outcome.LOADED and recovered.gold == 20 and recovered.get("recovered", false), "save failures: missing-primary crash window recovered")
	store.fail_move_to = ""
	check(store.save_progress(40, [2, 1, 1]) == OK and store.load_progress().gold == 40 and FileAccess.get_file_as_bytes(fixture.path + ".bak") == before, "save failures: retry full state with backup retained")
	check(DirAccess.remove_absolute(fixture.path) == OK and DirAccess.make_dir_absolute(fixture.path) == OK, "save failures: unreadable primary directory")
	var unreadable := ProgressSave.new(fixture.path)
	check(unreadable.load_progress().outcome == ProgressSave.Outcome.IO_FAILURE and unreadable.save_progress(50, [2, 1, 1]) != OK and DirAccess.dir_exists_absolute(fixture.path), "save failures: unreadable primary preserved, backup not bypassed")
	check(fixture.cleanup() == OK, "save failures: owned directory cleaned")

func test_runtime_preflight() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "runtime preflight: isolated directory owned")
	if not fixture.owned:
		return
	var store := PreflightFailingSave.new(fixture.path)
	var scene := saved_scene(store)
	scene.advance_time(4.0)
	var before := FileAccess.get_file_as_bytes(fixture.path)
	check(ProgressSave.new(fixture.path).load_progress().gold == 10, "runtime preflight: first victory saved")
	scene.restart_battle()
	store.fail_primary_read = true
	scene.advance_time(4.0)
	check(scene.economy.gold == 20 and FileAccess.get_file_as_bytes(fixture.path) == before
		and scene.saving_enabled and scene.save_status.text.contains("Retry"), "runtime preflight: transient failure preserves disk and earned reward")
	scene._refresh()
	check(scene.save_status.text.contains("Retry"), "runtime preflight: retry warning survives refresh")
	store.fail_primary_read = false
	var reads := store.primary_reads
	scene.upgrades[0].pressed.emit()
	var loaded := ProgressSave.new(fixture.path).load_progress()
	check(store.primary_reads > reads and loaded.gold == 0 and loaded.levels == [2, 1, 1]
		and scene.economy.gold == 0 and scene.economy.levels == [2, 1, 1]
		and scene.save_status.text.begins_with("Progress saved"), "runtime preflight: purchase rereads and retries full snapshot, clears warning")
	scene.advance_time(100.0)
	check(not scene.economy.settle(scene.battle) and scene.economy.gold == 0, "runtime preflight: no duplicate reward on retry")
	scene.free()
	for payload in ["{", '{"version":99,"gold":"future payload"}']:
		check(fixture.put('{"version":1,"gold":10,"levels":[1,1,1]}') == OK
			and fixture.put('{"version":1,"gold":0,"levels":[1,1,1]}', ".bak") == OK, "runtime preservation: valid startup and older backup")
		store = PreflightFailingSave.new(fixture.path)
		scene = saved_scene(store)
		check(fixture.put(payload) == OK, "runtime preservation: replace primary after accepted load")
		scene.advance_time(4.0)
		var warning := scene.save_status.text
		check(not scene.saving_enabled and warning.begins_with("Saving disabled")
			and warning.contains("preserved") and warning.contains("Close")
			and warning.contains("compatible") and not warning.contains("Retry")
			and scene.economy.gold == 20, "runtime preservation: terminal recovery UI without reloading earned state")
		reads = store.primary_reads
		scene._refresh()
		scene.restart.pressed.emit()
		scene.upgrades[0].pressed.emit()
		scene.advance_time(4.0)
		check(not scene.saving_enabled and scene.save_status.text == warning and store.primary_reads == reads
			and scene.economy.gold == 10 and scene.economy.levels == [2, 1, 1]
			and FileAccess.get_file_as_bytes(fixture.path) == payload.to_utf8_buffer(), "runtime preservation: refresh restart purchase victory retain disabled UI and exact bytes")
		check(store.save_progress(10, [2, 1, 1]) == ERR_UNAUTHORIZED
			and FileAccess.get_file_as_bytes(fixture.path) == payload.to_utf8_buffer(), "runtime preservation: store itself remains blocked")
		scene.free()
		scene = saved_scene(ProgressSave.new(fixture.path))
		check(not scene.saving_enabled and scene.economy.gold == 0 and scene.economy.levels == [1, 1, 1]
			and scene.save_status.text == warning, "runtime preservation: relaunch defaults without backup bypass")
		scene.free()
	check(fixture.cleanup() == OK, "runtime preflight: isolated directory cleaned")

func saved_scene(store: ProgressSave) -> Presentation:
	var scene: Presentation = BattleScene.instantiate()
	scene.progress_save = store
	root.add_child(scene)
	scene.set_process(false)
	scene.suspended = false
	scene.skip_resume_frame = false
	return scene

func test_progress_adapter() -> void:
	test_runtime_preflight()
	var fixture := ProgressFixture.new()
	check(fixture.owned, "saved adapter: directory owned")
	if not fixture.owned:
		return
	var store := FailingSave.new(fixture.path)
	var scene := saved_scene(store)
	check(store.writes == 0 and scene.economy.gold == 0, "saved adapter: no startup write")
	scene._purchase(0)
	scene.restart_battle()
	check(store.writes == 0, "saved adapter: rejected purchase and restart do not save")
	scene.advance_time(4.0)
	check(store.writes == 1 and store.load_progress().gold == 10, "saved adapter: victory reaches disk once")
	scene.advance_time(100.0)
	check(not scene.economy.settle(scene.battle) and store.writes == 1, "saved adapter: duplicate and terminal time do not save")
	scene.restart_battle()
	store.fail_write = true
	scene.advance_time(4.0)
	check(scene.economy.gold == 20 and store.load_progress().gold == 10 and scene.save_status.text.begins_with("Progress not saved"), "saved adapter: failed reward save keeps earned gold")
	scene._refresh()
	check(scene.save_status.text.begins_with("Progress not saved"), "saved adapter: refresh retains warning")
	store.fail_write = false
	scene._purchase(0)
	check(scene.economy.gold == 0 and store.load_progress().gold == 0 and store.load_progress().levels == [2, 1, 1] and scene.save_status.text.begins_with("Progress saved") and store.writes == 3, "saved adapter: purchase retries full snapshot, clears warning without reward")
	scene.free()
	check(store.writes == 3, "saved adapter: shutdown does not save")
	scene = saved_scene(ProgressSave.new(fixture.path))
	check(scene.economy.gold == 0 and scene.economy.levels == [2, 1, 1] and scene.battle.players[0].health == 160 and scene.battle.players[0].damage == Data.players()[0].damage + Economy.DAMAGE_GAIN[0] and scene.battle.rounds == 0 and not scene.battle.commander_queued and scene.replay_timer.is_stopped() and scene.elapsed_usec == 0, "saved adapter: load precedes first fresh full-health battle, no pending replay")
	scene.free()
	scene = saved_scene(store)
	for squad in scene.battle.players:
		squad.health = 0
	scene.advance_time(1.0)
	check(scene.battle.result == Combat.Result.DEFEAT and store.writes == 3, "saved adapter: defeat never saves")
	scene.free()
	check(fixture.put("{") == OK, "saved adapter: corrupt fixture")
	scene = saved_scene(ProgressSave.new(fixture.path))
	scene.advance_time(4.0)
	scene._refresh()
	check(scene.economy.gold == 10 and not scene.saving_enabled and scene.save_status.text.contains("preserved") and FileAccess.get_file_as_string(fixture.path) == "{", "saved adapter: corrupt defaults playable, visible durable warning, no overwrite")
	scene.free()
	check(fixture.cleanup() == OK, "saved adapter: owned directory cleaned")
