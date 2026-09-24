extends SceneTree

# Cross-process campaign persistence (contract D1/D6/D8/D11). The parent owns an isolated
# fixture directory and launches one fresh engine process per phase; each child drives the
# real campaign scene and compares against an uninterrupted in-process reference run.
const CampaignScene = preload("res://scenes/campaign_prototype.tscn")
const Presentation = preload("res://src/campaign_prototype.gd")
const Campaign = preload("res://src/campaign.gd")
const CampaignSave = preload("res://src/campaign_save.gd")
const CampaignState = preload("res://src/campaign_state.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")
const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const PHASES: Array[String] = ["conquest", "resume-conquest", "checkpoint", "resume-defense",
	"reset-interrupt", "reset", "successor", "successor-complete", "threat", "resume-threat"]
const ABSENCE_MSEC: int = 1200

# Commit seam: every move onto the primary fails, so the failed confirmation leaves the
# previous primary rotated to .bak and no restored primary (interrupted between rotate and commit).
# Its clock is pinned so every process stamps and reads the same time: the closed-app reward
# (covered in run_tests.gd) stays 0, keeping relaunches comparable to the uninterrupted reference.
class CommitFailingSave extends CampaignSave:
	const PINNED_NOW: int = 1800000000
	var fail_commit: bool = false
	func _now() -> int:
		return PINNED_NOW
	func _move(source: String, destination: String) -> Error:
		if fail_commit and destination == path:
			return ERR_FILE_CANT_WRITE
		return super._move(source, destination)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", title])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		coordinate()
		return
	var allowed := RegEx.new()
	allowed.compile("^user://progress-test-[0-9]+-[0-9]+/campaign\\.json$")
	if args.size() != 2 or args[0] not in PHASES or allowed.search(args[1]) == null:
		check(false, "isolated child arguments required")
		finish("invalid")
		return
	create_timer(30.0).timeout.connect(func() -> void:
		print("FAIL campaign persistence timeout; SUMMARY: incomplete")
		quit(1))
	child(args[0], args[1])

# --- Scripted inputs, shared verbatim by the child scene and the reference scene. ---

func state_of(scene: Presentation) -> Variant:
	var captured := CampaignState.capture(scene.campaign, scene.elapsed_usec)
	return captured.state if captured.outcome == CampaignState.Outcome.VALID else null

# The state as this smoke's store writes it: stamped with the pinned clock.
func stamped(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		return state
	var copy: Dictionary = (state as Dictionary).duplicate(true)
	copy.saved_at = CommitFailingSave.PINNED_NOW
	return copy

func press(scene: Presentation, name: String) -> void:
	scene.get_node("%" + name).pressed.emit()

# Deterministic preparation policy at battle granularity; never injects wins or funds.
func policy(scene: Presentation, gate_target: int, reserve: int, defend: bool) -> void:
	var campaign := scene.campaign
	if campaign.phase == Campaign.Phase.CONQUEST_CLEARED:
		if defend:
			press(scene, "StartDefense")
		return
	if campaign.phase != Campaign.Phase.RUNNING or campaign.mode != Campaign.Mode.FARM \
			or campaign.pending_navigation != Campaign.Navigation.NONE:
		return
	for role in range(3):
		if campaign.levels[role] < Campaign.LEVEL_CAP and campaign.gold >= campaign.purchase_cost(role):
			scene.upgrades[role].pressed.emit()
	if campaign.levels != [3, 3, 3]:
		return
	if campaign.gate_level < gate_target and campaign.gold >= campaign.gate_purchase_cost():
		press(scene, "GateUpgrade")
	if campaign.gate_level >= gate_target and campaign.gold >= reserve:
		press(scene, "Frontier")

func play_until(scene: Presentation, target: Campaign.Phase, gate_target: int, reserve: int, defend: bool) -> bool:
	for i in range(3000):
		if scene.campaign.phase == target:
			return true
		policy(scene, gate_target, reserve, defend)
		scene.advance_usec(Presentation.ROUND_USEC)
	return scene.campaign.phase == target

# Returns false when a scripted step cannot happen; the caller reports it.
func script_phase(scene: Presentation, phase: String) -> bool:
	var campaign := scene.campaign
	match phase:
		"conquest":
			# Border and Archer at level 1, then a damaged, mid-round Stronghold.
			for i in range(40):
				if campaign.current_encounter == Data.Encounter.STRONGHOLD:
					break
				scene.advance_usec(Presentation.ROUND_USEC)
			scene.advance_usec(2500000)
			scene.upgrades[0].pressed.emit()
			press(scene, "FarmBorder")
			scene.advance_usec(300000)
			return campaign.current_encounter == Data.Encounter.STRONGHOLD and campaign.levels[0] == 2 \
				and campaign.pending_navigation == Campaign.Navigation.FARM
		"resume-conquest":
			# Keep 40 gold so a gate upgrade is affordable mid-assault later.
			return play_until(scene, Campaign.Phase.CONQUEST_CLEARED, 1, 40, false)
		"checkpoint":
			press(scene, "StartDefense")
			scene.advance_usec(1500000)
			press(scene, "GateUpgrade")
			for i in range(60):
				if campaign.battle.gate_health < campaign.battle.gate_max_health \
						or campaign.battle.result != Combat.Result.ONGOING:
					break
				scene.advance_usec(Presentation.ROUND_USEC)
			scene.advance_usec(250000)
			press(scene, "FarmBorder")
			return campaign.phase == Campaign.Phase.DEFENDING and campaign.gate_level == 2 \
				and campaign.pending_navigation == Campaign.Navigation.FARM
		"resume-defense", "successor":
			return play_until(scene, Campaign.Phase.CAMPAIGN_SECURED, 3, 0, true)
		"reset-interrupt", "successor-complete", "resume-threat":
			return true # The interrupted confirmation is undone by relaunch; completion adds nothing.
		"threat":
			# Found dynasty 3 one Threat above the best secured (0), then stop mid-round after
			# one completed round of its Threat-1 Border.
			press(scene, "FoundDynasty")
			press(scene, "ThreatUp")
			press(scene, "ConfirmDynasty")
			scene.advance_usec(Presentation.ROUND_USEC + 400000)
			return campaign.dynasty == 3 and campaign.threat == 1 and campaign.battle.rounds == 1 \
				and campaign.battle.result == Combat.Result.ONGOING and scene.elapsed_usec == 400000
		"reset":
			press(scene, "TrainDrill")
			press(scene, "FoundDynasty")
			press(scene, "ConfirmDynasty")
			return campaign.dynasty == 2 and campaign.drill_rank == 1 and campaign.legacy == 0
	return false

# --- Child process ---

func child(phase: String, path: String) -> void:
	var index: int = PHASES.find(phase)
	# Uninterrupted reference: same scripted inputs, saving disabled.
	var reference: Presentation = CampaignScene.instantiate()
	reference.campaign_save = null
	root.add_child(reference)
	reference.set_process(false)
	var ok := true
	for i in range(index):
		ok = script_phase(reference, PHASES[i]) and ok
	check(ok, "%s: reference reached pre-launch state" % phase)
	var expected: Variant = state_of(reference)
	var store := CommitFailingSave.new(path)
	var scene: Presentation = CampaignScene.instantiate()
	scene.campaign_save = store
	root.add_child(scene)
	current_scene = scene
	# Launch-time processing decision, before logical time takes over from the real clock.
	var processing: bool = scene.is_processing()
	scene.set_process(false)
	var campaign := scene.campaign
	var status: String = scene.get_node("%SaveStatus").text
	var loaded := CampaignState.capture(campaign, scene.elapsed_usec)
	if phase == "conquest":
		check(status == "Autosave on" and not FileAccess.file_exists(path) and campaign.battle.rounds == 0
			and campaign.gold == 0, "conquest: missing save starts fresh without writing")
	else:
		check(status == ("Restored from backup" if phase == "reset" else "Autosave on")
			and scene.get_node("%LastResult").text == "Resumed saved campaign",
			"%s: resumed with expected save status (%s)" % [phase, status])
		check(loaded.outcome == CampaignState.Outcome.VALID and loaded.state == expected,
			"%s: relaunch state equals uninterrupted reference exactly" % phase)
		# The first frame after load and the real absence add no combat, income or progress.
		scene.advance_usec(9000000)
		check(state_of(scene) == expected and not scene.skip_resume_frame, "%s: first frame and absence add nothing" % phase)
	match phase:
		"resume-conquest":
			check(campaign.current_encounter == Data.Encounter.STRONGHOLD and campaign.battle.rounds == 2
				and scene.elapsed_usec == 800000 and campaign.levels == [2, 1, 1]
				and campaign.battle.players[0].max_health == 120 and campaign.battle.players[0].health < 120
				and campaign.pending_navigation == Campaign.Navigation.FARM
				and campaign.pending_farm == Data.Encounter.BORDER_SKIRMISH,
				"resume-conquest: damaged battle, fractional time, level-1 snapshot vs owned level 2, queued farm")
		"checkpoint":
			check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and not processing
				and not scene.get_node("%StartDefense").disabled and not campaign.battle.is_defense
				and campaign.last_defense_loss == Combat.DefeatReason.NONE
				and not scene.get_node("%CampaignStatus").text.contains("Last defense"),
				"checkpoint: restored checkpoint idle, Start Defense enabled, not auto-started, no loss hint before any defense")
		"resume-defense":
			check(campaign.phase == Campaign.Phase.DEFENDING and campaign.gate_level == 2
				and campaign.battle.gate_max_health == 80 and campaign.battle.gate_health < 80
				and scene.elapsed_usec == 750000 and campaign.pending_navigation == Campaign.Navigation.FARM
				and processing and campaign.last_defense_loss == Combat.DefeatReason.NONE
				and scene.get_node("%CampaignStatus").text == "Counterattack · Defending the Stronghold",
				"resume-defense: damaged gate snapshot vs owned level, queued recovery, time, no loss hint while defending")
		"reset-interrupt":
			check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.can_found_dynasty(),
				"reset-interrupt: secured campaign restored with reset available")
			var bytes := FileAccess.get_file_as_bytes(path)
			press(scene, "FoundDynasty")
			press(scene, "CancelDynasty")
			press(scene, "FoundDynasty")
			check(scene.dynasty_preview_open and FileAccess.get_file_as_bytes(path) == bytes and state_of(scene) == expected,
				"reset-interrupt: preview open and cancel leave the file byte-identical")
			store.fail_commit = true
			press(scene, "ConfirmDynasty")
			check(campaign.dynasty == 2 and scene.get_node("%SaveStatus").text == "Progress not saved — will retry"
				and not FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path + ".bak") == bytes,
				"reset-interrupt: confirmation interrupted between rotate and commit")
			finish(phase)
			return # Process ends with no further save trigger.
		"reset":
			check(campaign.dynasty == 1 and campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.can_found_dynasty()
				and campaign.legacy == 10 and campaign.drill_rank == 0,
				"reset: unacknowledged confirmation undone; still dynasty 1 with 10 Legacy and reset available")
		"successor":
			var damage: Array[int] = []
			for squad in campaign.battle.players:
				damage.append(squad.damage)
			check(campaign.dynasty == 2 and campaign.drill_rank == 1 and campaign.legacy == 0
				and not campaign.can_found_dynasty() and damage == [8, 16, 12],
				"successor: Legacy and exactly 2x Drill rank survive relaunch, no reset before security")
			var border := campaign.battle
			scene.advance_usec(Presentation.ROUND_USEC)
			check(border.result == Combat.Result.ONGOING, "successor: passive Border not won in one round")
			scene.advance_usec(Presentation.ROUND_USEC)
			check(border.rounds == 2 and border.result == Combat.Result.VICTORY and campaign.gold == 10,
				"successor: passive Border won in two rounds with ordinary reward")
			# Keep the reference aligned with these two rounds.
			reference.advance_usec(2 * Presentation.ROUND_USEC)
		"successor-complete":
			check(scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated · +3 Legacy earned"
				and campaign.legacy == 3 and campaign.drill_rank == 1 and campaign.can_found_dynasty()
				and not scene.get_node("%FoundDynasty").disabled and not processing,
				"successor-complete: +3 Legacy kept across relaunch, another reset offered, idle")
			press(scene, "FoundDynasty")
			check(scene.dynasty_preview_open
				and scene.get_node("%ConfirmDynasty").text == "Confirm reset — start dynasty 3"
				and scene.get_node("%DynastyLosses").text.contains("Keep Legacy 3 and Drill rank 1"),
				"successor-complete: repeat preview offers dynasty 3 keeping Legacy and rank")
			press(scene, "CancelDynasty")
			scene.advance_usec(60000000)
			check(state_of(scene) == expected and not scene.dynasty_preview_open,
				"successor-complete: cancelled repeat preview and relaunch time change nothing")
		"resume-threat":
			var enemy: Data.Squad = campaign.battle.enemies[0]
			check(campaign.dynasty == 3 and campaign.threat == 1 and campaign.best_threat == 0
				and campaign.legacy_earned == 13 and campaign.current_encounter == Data.Encounter.BORDER_SKIRMISH
				and campaign.battle.enemies.size() == 1 and enemy.max_health == 90 and enemy.health < 90
				and campaign.battle.rounds == 1 and campaign.battle.result == Combat.Result.ONGOING
				and scene.elapsed_usec == 400000 and processing,
				"resume-threat: Threat-1 dynasty 3 battle restored mid-fight (enemy shield 72 +25% = 90)")
			check(scene.get_node("%ThreatStatus").text.begins_with("Threat 1 (enemies +25% health and damage)")
				and scene.get_node("%DynastyStatus").text.ends_with("Securing this campaign earns 6 Legacy"),
				"resume-threat: Threat line and 6-Legacy payout shown after relaunch")
	var scripted := script_phase(scene, phase)
	check(scripted, "%s: scripted inputs applied" % phase)
	script_phase(reference, phase)
	var final: Variant = state_of(scene)
	check(final != null and final == state_of(reference), "%s: continued state matches uninterrupted reference" % phase)
	if phase == "reset":
		check(scene.get_node("%SaveStatus").text == "Saved", "reset: confirmation acknowledged with Saved")
	if phase in ["resume-conquest", "resume-defense", "successor"]:
		# Hard stop right after the terminal settlement: no close-request save, so only the
		# settlement's own write can have recorded the reward, clearance and routing.
		var settled := CampaignSave.new(path).load_campaign()
		check(CampaignSave._state_of(settled) == stamped(final) and scene.get_node("%SaveStatus").text == "Saved",
			"%s: settlement saved before any close request" % phase)
		finish(phase)
		return
	# Close like the window manager does: best-effort save, then quit.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved := CampaignSave.new(path).load_campaign()
	check(CampaignSave._state_of(saved) == stamped(final) and not saved.get("recovered", false),
		"%s: close request leaves exact state on disk" % phase)
	finish(phase)

# --- Parent process ---

func coordinate() -> void:
	# Parent retains directory ownership until every scene process has exited.
	var fixture := ProgressFixture.new("campaign.json")
	check(fixture.owned, "probe: fresh test-owned directory")
	if fixture.owned:
		var progress_path: String = fixture.directory.path_join("progress.json")
		var levels: Array[int] = [2, 1, 1]
		check(ProgressSave.new(progress_path).save_progress(10, levels) == OK, "probe: sibling Save-v1 written")
		var progress_bytes := FileAccess.get_file_as_bytes(progress_path)
		for phase in PHASES:
			var arguments: PackedStringArray = ["--path", ProjectSettings.globalize_path("res://"),
				"--script", "tests/campaign_persistence_smoke.gd"]
			if DisplayServer.get_name() == "headless":
				arguments.append("--headless")
			arguments.append_array(["--", phase, fixture.path])
			# Fixed executable and argv, no shell. Caller must also enforce an overall bound.
			var output: Array = []
			var exit_code := OS.execute(OS.get_executable_path(), arguments, output, true)
			var text := "\n".join(output)
			print(text)
			check(exit_code == 0 and text.contains("SUMMARY: campaign persistence %s:" % phase)
				and not text.contains("FAIL") and not text.contains("ERROR:"), "probe: %s process complete" % phase)
			if failures > 0:
				break
			# Real absence between launches must not produce combat or income.
			OS.delay_msec(ABSENCE_MSEC)
		check(FileAccess.get_file_as_bytes(progress_path) == progress_bytes and not FileAccess.file_exists(progress_path + ".tmp")
			and not FileAccess.file_exists(progress_path + ".bak"), "probe: sibling Save-v1 bytes untouched")
		check(fixture.cleanup() == OK, "probe: owned directory cleaned after child exits")
	finish("two-process")

func finish(phase: String) -> void:
	print("SUMMARY: campaign persistence %s: %d checks, %d failures (%s)" % [phase, checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
