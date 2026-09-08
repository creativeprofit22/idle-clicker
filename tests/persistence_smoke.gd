extends SceneTree

const BattleScene = preload("res://scenes/opening_battle.tscn")
const Presentation = preload("res://src/opening_battle.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")
const Combat = preload("res://src/combat.gd")
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
		await coordinate()
		return
	var allowed := RegEx.new()
	allowed.compile("^user://progress-test-[0-9]+-[0-9]+/progress\\.json$")
	if args.size() != 2 or args[0] not in ["earn", "reload"] or allowed.search(args[1]) == null:
		check(false, "isolated child arguments required")
		finish("invalid")
		return
	create_timer(15.0).timeout.connect(func() -> void:
		print("FAIL persistence timeout; SUMMARY: incomplete")
		quit(1))
	var store := ProgressSave.new(args[1])
	var initial := store.load_progress()
	check(initial.outcome == (ProgressSave.Outcome.MISSING if args[0] == "earn" else ProgressSave.Outcome.LOADED), "child: expected isolated save state")
	if failures > 0:
		finish(args[0])
		return
	var scene: Presentation = BattleScene.instantiate()
	scene.progress_save = store
	root.add_child(scene)
	current_scene = scene
	check(scene.battle.rounds == 0 and not scene.battle.commander_queued and scene.replay_timer.is_stopped() and scene.elapsed_usec == 0, "child: fresh combat, no restored strike/replay/time")
	for squad in scene.battle.players:
		check(squad.health == squad.max_health, "child: full health")
	if args[0] == "earn":
		check(scene.economy.gold == 0 and scene.economy.levels == [1, 1, 1], "earn: default ownership")
		await victory(scene)
		check(scene.economy.gold == 10, "earn: first victory +10")
		if DisplayServer.get_name() == "headless":
			scene.restart_battle()
		else:
			while scene.battle.result != Combat.Result.ONGOING:
				await process_frame
		await victory(scene)
		check(scene.economy.gold == 20, "earn: second victory +10")
		scene.upgrades[0].pressed.emit()
		check(scene.economy.gold == 0 and scene.economy.levels == [2, 1, 1] and not scene.replay_timer.is_stopped(), "earn: purchase while replay pending, close before replay")
	else:
		check(scene.economy.gold == 0 and scene.economy.levels == [2, 1, 1] and scene.battle.players[0].health == 160, "reload: identical ownership, upgraded first battle, no launch income")
		await victory(scene)
		check(scene.economy.gold == 10, "reload: one new victory adds exactly 10")
	var saved := ProgressSave.new(args[1]).load_progress()
	check(saved.outcome == ProgressSave.Outcome.LOADED and saved.gold == scene.economy.gold and saved.levels == scene.economy.levels, "child: current ownership on disk")
	finish(args[0])

func victory(scene: Presentation) -> void:
	if DisplayServer.get_name() == "headless":
		scene.advance_time(4.0)
	else:
		while scene.battle.result == Combat.Result.ONGOING:
			await process_frame
	check(scene.battle.result == Combat.Result.VICTORY, "child: victory accepted")

func coordinate() -> void:
	# Parent retains directory ownership until both scene processes have exited.
	var fixture := ProgressFixture.new()
	check(fixture.owned, "probe: fresh test-owned directory")
	if fixture.owned:
		for phase in ["earn", "reload"]:
			var arguments: PackedStringArray = ["--path", ProjectSettings.globalize_path("res://"), "--script", "tests/persistence_smoke.gd"]
			if DisplayServer.get_name() == "headless":
				arguments.append("--headless")
			arguments.append_array(["--", phase, fixture.path])
			# Fixed executable and argv, no shell. Caller must also enforce a 35-second bound.
			var output: Array = []
			var exit_code := OS.execute(OS.get_executable_path(), arguments, output, true)
			var text := "\n".join(output)
			print(text)
			check(exit_code == 0 and text.contains("SUMMARY: persistence %s" % phase) and not text.contains("FAIL") and not text.contains("ERROR:"), "probe: %s process complete" % phase)
			if failures > 0:
				break
		check(fixture.cleanup() == OK, "probe: owned directory cleaned after child exits")
	finish("two-process")

func finish(phase: String) -> void:
	print("SUMMARY: persistence %s: %d checks, %d failures (%s)" % [phase, checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
