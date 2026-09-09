extends SceneTree

const BattleScene = preload("res://scenes/opening_battle.tscn")
const Presentation = preload("res://src/opening_battle.gd")
const Combat = preload("res://src/combat.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")
const OUTPUT: String = "res://.gg/screenshots/opening-battle/"
var scene: Presentation
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
	create_timer(25.0).timeout.connect(func() -> void:
		print("FAIL smoke timeout; SUMMARY: incomplete")
		quit(1))
	if DisplayServer.get_name() == "headless":
		print("FAIL graphical renderer required; SUMMARY: incomplete")
		quit(1)
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	check(directory_error == OK, "capture directory available")
	scene = BattleScene.instantiate()
	scene.progress_save = null
	scene.fortified_diagnostics = "--fortified" in OS.get_cmdline_user_args() and "--fortified-diagnostics" in OS.get_cmdline_user_args()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if "--fortified" in OS.get_cmdline_user_args():
		await test_fortified_progression()
		print("SUMMARY: fortified: %d graphical checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	if "--progression" in OS.get_cmdline_user_args():
		await test_progression()
		print("SUMMARY: progression: %d graphical checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	await capture("initial")
	check(scene.battle.rounds == 0 and scene.battle.enemies[0].health == 72,
		"initial: no damage and round zero")
	press_mouse(scene.commander, true)
	press_mouse(scene.commander, false)
	check(scene.battle.commander_queued and scene.commander.disabled
		and scene.status_label.text.contains("queued"), "viewport mouse: queued status and disabled button")
	await capture("commander-queued")
	for target_round in range(1, 4):
		var deadline: int = Time.get_ticks_msec() + 2500
		while scene.battle.rounds < target_round and Time.get_ticks_msec() < deadline:
			await process_frame
		check(scene.battle.rounds == target_round
			and scene.battle.enemies[0].health == [48, 24, 0][target_round - 1],
			"real foreground timer: commander round %d" % target_round)
		if target_round < 3:
			press_mouse(scene.commander, true)
			press_mouse(scene.commander, false)
	check(scene.battle.result == Combat.Result.VICTORY and scene.battle.players[0].health == 111
		and scene.commander.disabled and scene.status_label.text.begins_with("Victory"),
		"victory: UI and simultaneous death-round damage")
	await capture("victory")
	# A press rejected at victory must not activate on release after restart.
	press_mouse(scene.commander, true)
	press_mouse(scene.restart, true)
	press_mouse(scene.restart, false)
	press_mouse(scene.commander, false)
	check(scene.battle.rounds == 0 and scene.battle.enemies[0].health == 72
		and not scene.battle.commander_queued and not scene.commander.disabled
		and scene.round_label.text.begins_with("Round 0"), "viewport restart: refreshed UI, no terminal input leak")
	await capture("restarted")
	# Native keyboard path: echo must not queue again after an interval or restart.
	scene.commander.grab_focus()
	press_key(true, false)
	check(scene.battle.commander_queued, "keyboard: focused commander accepts press")
	var next_round: int = scene.battle.rounds + 1
	var held_deadline: int = Time.get_ticks_msec() + 2500
	while scene.battle.rounds < next_round and Time.get_ticks_msec() < held_deadline:
		await process_frame
	press_key(true, true)
	check(scene.battle.rounds == next_round and not scene.battle.commander_queued,
		"keyboard: held echo cannot repeat in next interval")
	press_mouse(scene.restart, true)
	press_mouse(scene.restart, false)
	scene.commander.grab_focus()
	press_key(true, true)
	press_key(false, false)
	check(scene.battle.rounds == 0 and not scene.battle.commander_queued,
		"keyboard: held input cannot leak across restart")
	root.size = Vector2i(540, 720)
	await process_frame
	await process_frame
	await capture("small-restarted")
	press_mouse(scene.commander, true)
	press_mouse(scene.commander, false)
	check(scene.battle.commander_queued, "smaller window: viewport button remains clickable")
	await capture("small-queued")
	await test_delayed_input()
	await test_farming()
	await test_saved_reload()
	print("SUMMARY: %d graphical checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_fortified_progression() -> void:
	var fortified: Button = scene.get_node("%FortifiedSelect")
	var border: Button = scene.get_node("%BorderSelect")
	var archer: Button = scene.get_node("%ArcherSelect")
	check(root.has_focus() and not scene.suspended, "Fortified graphical: focused foreground start")
	check(fortified.disabled and scene.get_node("%FortifiedUnlockHint").visible, "Fortified graphical: starts locked")
	# Isolated in-memory ownership only; the final required purchase uses viewport input.
	scene.economy.levels.assign([2, 2, 1])
	scene.economy.gold = 20
	scene._refresh()
	await capture("fortified-locked")
	press_mouse(scene.upgrades[2], true)
	press_mouse(scene.upgrades[2], false)
	check(not fortified.disabled and scene.economy.gold == 0 and scene.economy.levels == [2, 2, 2]
		and not scene.get_node("%FortifiedUnlockHint").visible, "Fortified graphical: viewport last purchase unlocks")
	press_mouse(fortified, true)
	press_mouse(fortified, false)
	check(scene.economy.current_encounter == 2 and fortified.disabled
		and scene.get_node("%Title").text == "FORTIFIED POSITION"
		and scene.health_bars[3].value == 160 and scene.health_bars[4].value == 80, "Fortified graphical: viewport selection full enemy rows")
	await capture("fortified-selected")
	var deadline: int = Time.get_ticks_msec() + 11500
	scene.trace_fortified("victory-wait-start deadline_msec=%d" % deadline)
	while scene.battle.result == Combat.Result.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	scene.trace_fortified("first-assertion deadline_msec=%d status=%s enemy_hp=%s/%s replay_stopped=%s" % [
		deadline, scene.status_label.text, scene.health_bars[3].value,
		scene.health_bars[4].value, scene.replay_timer.is_stopped()])
	check(root.has_focus() and not scene.suspended and scene.battle.rounds == 10
		and scene.battle.result == Combat.Result.VICTORY and scene.economy.gold == 54
		and scene.status_label.text.contains("+54") and scene.health_bars[3].value == 0
		and scene.health_bars[4].value == 0, "Fortified graphical: real ten-second victory pays 54")
	check(not scene.replay_timer.is_stopped() and scene.replay_timer.wait_time == 1.0,
		"Fortified graphical: one-second replay pending")
	await capture("fortified-victory")
	var completed := scene.battle
	deadline = Time.get_ticks_msec() + 1500
	while scene.battle == completed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.battle != completed and scene.economy.current_encounter == 2 and scene.battle.rounds == 0
		and scene.battle.players[0].health == 160 and scene.battle.enemies[0].health == 160
		and scene.battle.enemies[1].health == 80 and scene.economy.gold == 54
		and not scene.battle.commander_queued, "Fortified graphical: real automatic fresh replay")
	root.size = Vector2i(540, 720)
	await process_frame
	await process_frame
	await capture("fortified-small-scaled")
	root.content_scale_size = Vector2i(540, 720)
	await process_frame
	await process_frame
	scene.restart.grab_focus()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(scene.restart.get_global_rect())
		and scene.get_node("%Scroll").scroll_vertical > 0, "Fortified graphical: small-window lower focus scrolling")
	await capture("fortified-small-bottom")
	border.grab_focus()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(border.get_global_rect()), "Fortified graphical: selector focus scrolls back")
	press_key(true, false)
	press_key(false, false)
	check(scene.economy.current_encounter == 0 and scene.battle.enemies.size() == 1
		and not scene.get_node("%EnemyFootRow").visible and scene.economy.gold == 54,
		"Fortified graphical: keyboard returns to Border without payment")
	press_mouse(archer, true)
	press_mouse(archer, false)
	check(scene.economy.current_encounter == 1 and scene.health_bars[3].value == 100
		and scene.health_bars[4].value == 40 and scene.gold_label.text.contains("+30"),
		"Fortified graphical: old Archer selector restores fixture")
	await capture("fortified-small-archer")
	check(root.has_focus() and not scene.suspended, "Fortified graphical: focused foreground completion")

func test_progression() -> void:
	var archer: Button = scene.get_node("%ArcherSelect")
	var border: Button = scene.get_node("%BorderSelect")
	check(archer.disabled and scene.get_node("%UnlockHint").visible, "progression: fresh locked hint")
	scene.economy.gold = 20
	scene._refresh()
	await capture("progression-locked")
	press_mouse(scene.upgrades[0], true)
	press_mouse(scene.upgrades[0], false)
	check(not archer.disabled and scene.economy.gold == 0, "progression: real mouse purchase unlocks")
	press_mouse(archer, true)
	press_mouse(archer, false)
	check(scene.battle.enemies.size() == 2 and scene.health_bars[3].value == 100
		and scene.health_bars[4].value == 40 and archer.disabled, "progression: mouse selection renders two full enemies")
	await capture("progression-archer")
	var deadline: int = Time.get_ticks_msec() + 9500
	while scene.battle.result == Combat.Result.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.battle.result == Combat.Result.VICTORY and scene.economy.gold == 30
		and scene.health_bars[3].value == 0 and scene.health_bars[4].value == 0
		and scene.status_label.text.contains("+30"), "progression: timed Archer victory pays 30")
	await capture("progression-victory")
	var completed := scene.battle
	deadline = Time.get_ticks_msec() + 1500
	while scene.battle == completed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.battle != completed and scene.battle.enemies.size() == 2
		and scene.battle.rounds == 0 and scene.battle.players[0].health == 160,
		"progression: automatic same-encounter replay")
	root.size = Vector2i(540, 720)
	await process_frame
	await process_frame
	await capture("progression-small-scaled")
	# Also constrain logical size: normal canvas scaling alone does not exercise scrolling.
	root.content_scale_size = Vector2i(540, 720)
	await process_frame
	await process_frame
	scene.restart.grab_focus()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(scene.restart.get_global_rect())
		and scene.get_node("%Scroll").scroll_vertical > 0, "progression: focus scrolls lower controls into view")
	await capture("progression-small-bottom")
	border.grab_focus()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(border.get_global_rect()), "progression: focus scrolls back to selector")
	press_key(true, false)
	press_key(false, false)
	check(scene.battle.enemies.size() == 1 and not scene.get_node("%EnemyFootRow").visible
		and scene.economy.gold == 30, "progression: keyboard returns Border without extra payout")
	await capture("progression-small-border")
	scene.save_status.text = "Progress not saved · Retry on next victory or purchase; unsaved changes lost on close"
	await process_frame
	await process_frame
	scene.get_node("%Scroll").ensure_control_visible(scene.save_status)
	await process_frame
	check(root.get_visible_rect().encloses(scene.save_status.get_global_rect()), "progression: small-window save warning reachable")
	await capture("progression-small-warning")

func test_saved_reload() -> void:
	var fixture := ProgressFixture.new()
	check(fixture.owned, "graphical save: isolated directory owned")
	if not fixture.owned:
		return
	var store := ProgressSave.new(fixture.path)
	check(store.save_progress(10, [2, 1, 1]) == OK, "graphical save: isolated progress seeded")
	scene.free()
	scene = BattleScene.instantiate()
	scene.progress_save = ProgressSave.new(fixture.path)
	root.add_child(scene)
	current_scene = scene
	check(scene.economy.gold == 10 and scene.economy.levels == [2, 1, 1]
		and scene.battle.players[0].health == 160 and scene.battle.rounds == 0
		and not scene.battle.commander_queued and scene.replay_timer.is_stopped(), "graphical save: first battle restored ownership, fresh combat")
	check(scene.save_status.is_visible_in_tree() and scene.save_status.text.contains("Autosave"), "graphical save: visible autosave status")
	root.size = Vector2i(720, 960)
	await process_frame
	await process_frame
	await capture("saved-reload")
	root.size = Vector2i(540, 720)
	await process_frame
	await process_frame
	await capture("small-saved-reload")
	check(root.get_visible_rect().encloses(scene.save_status.get_global_rect()), "graphical save: narrow status contained")
	scene.free()
	check(fixture.put("{") == OK, "graphical save: preserved error fixture")
	scene = BattleScene.instantiate()
	scene.progress_save = ProgressSave.new(fixture.path)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	await capture("small-save-warning")
	check(scene.save_status.is_visible_in_tree() and scene.save_status.text.contains("preserved") and not scene.saving_enabled, "graphical save: persistent recovery explanation visible")
	scene.restart.grab_focus()
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(scene.restart.get_global_rect()), "graphical save: recovery text leaves restart reachable")
	scene.free()
	check(fixture.cleanup() == OK, "graphical save: owned directory cleaned")

func test_delayed_input() -> void:
	for keyboard in [false, true]:
		for prior in [false, true]:
			scene.restart_battle()
			scene.commander.grab_focus()
			if prior:
				commander_click(keyboard)
			check(scene.battle.rounds == 0 and scene.battle.commander_queued == prior,
				"dispatch seam: round zero, keyboard=%s prior=%s" % [keyboard, prior])
			# Clock seam: 1.25 foreground seconds pending, no intervening frame.
			scene.elapsed_usec = 0
			scene.last_frame_usec = Time.get_ticks_usec() - 1250000
			commander_click(keyboard)
			check(scene.battle.rounds == 1 and scene.battle.enemies[0].health == (48 if prior else 54)
				and scene.battle.commander_queued,
				"late dispatch: old round settled, new strike queued; keyboard=%s prior=%s" % [keyboard, prior])
			await process_frame
			await process_frame
			check(scene.battle.rounds == 1 and scene.battle.commander_queued,
				"next frame: consumed span not counted twice; keyboard=%s prior=%s" % [keyboard, prior])
			var deadline: int = Time.get_ticks_msec() + 1500
			while scene.battle.rounds < 2 and Time.get_ticks_msec() < deadline:
				await process_frame
			check(scene.battle.rounds == 2 and scene.battle.enemies[0].health == (24 if prior else 30)
				and not scene.battle.commander_queued,
				"second boundary: late strike applied once; keyboard=%s prior=%s" % [keyboard, prior])
		scene.restart_battle()
		scene.commander.grab_focus()
		scene.last_frame_usec = Time.get_ticks_usec() - 4250000
		check(scene.battle.rounds == 0, "terminal dispatch seam: model still round zero")
		commander_click(keyboard)
		check(scene.battle.rounds == 4 and scene.battle.result == Combat.Result.VICTORY
			and scene.battle.players[0].health == 108 and not scene.battle.commander_queued
			and scene.commander.disabled and not scene.is_processing(),
			"terminal catch-up: late input rejected; keyboard=%s" % keyboard)

func test_farming() -> void:
	scene.economy = scene.Economy.new()
	scene.restart_battle()
	var first: Combat = scene.battle
	var deadline: int = Time.get_ticks_msec() + 11000
	while scene.economy.gold < 20 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.economy.gold == 20 and scene.battle != first
		and scene.battle.result == Combat.Result.VICTORY,
		"passive farming: two real timed victories pay 20 without restart or taps")
	var completed: Combat = scene.battle
	deadline = Time.get_ticks_msec() + 1500
	while scene.battle == completed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.battle != completed and scene.battle.rounds == 0
		and scene.battle.players[0].health == 120 and scene.battle.players[1].health == 40
		and scene.battle.players[2].health == 60 and not scene.battle.commander_queued,
		"automatic replay starts with full health and clean input")
	press_mouse(scene.upgrades[1], true)
	press_mouse(scene.upgrades[1], false)
	check(scene.economy.gold == 0 and scene.economy.levels == [1, 2, 1]
		and scene.battle.players[1].damage == 8 and scene.battle.players[1].max_health == 40
		and scene.upgrades[1].disabled and scene.upgrades[1].text.contains("40 gold"),
		"narrow viewport purchase: exact cost, next price, current stats unchanged")
	await capture("small-purchased")
	completed = scene.battle
	scene.last_frame_usec = Time.get_ticks_usec() - 4250000
	scene.advance_foreground(Time.get_ticks_usec())
	deadline = Time.get_ticks_msec() + 1500
	while scene.battle == completed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.battle != completed and scene.battle.rounds == 0
		and scene.battle.players[1].health == 52 and scene.battle.players[1].damage == 12
		and scene.economy.gold == 10,
		"automatic replay applies purchased stats and pays completed battle once")
	await capture("small-upgraded-replay")
	root.size = Vector2i(720, 960)
	await process_frame
	await process_frame
	await capture("upgraded-replay")

func commander_click(keyboard: bool) -> void:
	if keyboard:
		press_key(true, false)
		press_key(false, false)
	else:
		press_mouse(scene.commander, true, false)
		press_mouse(scene.commander, false, false)

func press_mouse(button: Button, down: bool, move_pointer: bool = true) -> void:
	if move_pointer:
		scene.get_node("%Scroll").ensure_control_visible(button)
	check(root.get_visible_rect().encloses(button.get_global_rect()), "mouse target fully visible")
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	if move_pointer:
		root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	root.push_input(event, true)

func press_key(down: bool, echo: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = down
	event.echo = echo
	root.push_input(event, true)

func capture(title: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "%s: rendered image" % title)
	if image != null and not image.is_empty():
		check(image.save_png(OUTPUT + title + ".png") == OK, "%s: PNG saved" % title)
	var bounds := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var contained: bool = true
	var scroll: ScrollContainer = scene.get_node("%Scroll")
	var column: Control = scene.get_node("Margin/Scroll/Column")
	for child in column.get_children():
		var control: Control = child as Control
		if not control.visible:
			continue
		var rect := control.get_global_rect()
		contained = rect.position.x >= bounds.position.x and rect.end.x <= bounds.end.x and contained
		contained = column.get_global_rect().encloses(rect) and rect.size.y <= scroll.size.y and contained
	check(contained and bounds.encloses(scroll.get_global_rect()), "%s: controls fit scrollable viewport" % title)
