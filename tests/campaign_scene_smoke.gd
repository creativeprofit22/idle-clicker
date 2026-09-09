extends SceneTree

const CampaignScene = preload("res://scenes/campaign_prototype.tscn")
const Presentation = preload("res://src/campaign_prototype.gd")
const Campaign = preload("res://src/campaign.gd")
const Data = preload("res://src/encounter_data.gd")
const OUTPUT: String = "res://.gg/screenshots/campaign/"
var scene: Presentation
var checks: int = 0
var failures: int = 0
var watching_focus: bool = false
var foreground_broken: bool = false
var watchdog: SceneTreeTimer
var manual: bool = "--manual-focus" in OS.get_cmdline_user_args()
var native_driver: bool = "--native-window-driver" in OS.get_cmdline_user_args()
var exit_status: int = 1

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s campaign: %s" % ["PASS" if condition else "FAIL", title])

func audit_foreground() -> void:
	if watching_focus and (not root.has_focus() or root.mode == Window.MODE_MINIMIZED or scene.suspended):
		foreground_broken = true
		watching_focus = false
		check(false, "foreground interrupted (mode=%d focus=%s suspended=%s)" % [root.mode, root.has_focus(), scene.suspended])
		print("SUMMARY: campaign: incomplete — foreground interrupted; %d checks, %d failures" % [checks, failures])
		if not manual:
			quit(1)
		else:
			root.title = "Focus was interrupted — test will report failure, window stays open"

func run() -> void:
	if native_driver and manual:
		print("FAIL native driver cannot replace physical manual verification; SUMMARY: incomplete")
		quit(1)
		return
	if native_driver:
		auto_accept_quit = false
		root.close_requested.connect(func() -> void: quit(exit_status))
	watchdog = create_timer(60.0)
	watchdog.timeout.connect(func() -> void:
		check(false, "campaign smoke timeout; SUMMARY: incomplete")
		end_run(1))
	if DisplayServer.get_name() == "headless":
		print("FAIL campaign graphical renderer required; SUMMARY: incomplete")
		quit(1)
		return
	if manual:
		auto_accept_quit = false
		root.close_requested.connect(func() -> void: quit(exit_status))
		root.title = "Campaign check — click Start when YOU are ready"
		var start := Button.new()
		start.text = "START WHEN READY\nThen keep this window selected until the MINIMIZE prompt.\nThere is no countdown. The window stays open afterward."
		start.position = Vector2(24, 24)
		start.size = Vector2(672, 160)
		root.add_child(start)
		watchdog.time_left = INF
		await start.pressed
		root.remove_child(start)
		start.queue_free()
		watchdog.time_left = 60.0
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK,
		"capture directory available")
	scene = CampaignScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	root.grab_focus()
	if not await await_focus():
		finish()
		return
	process_frame.connect(audit_foreground)
	root.focus_exited.connect(func() -> void:
		if watching_focus:
			foreground_broken = true)
	watching_focus = true
	if "--focus-only" in OS.get_cmdline_user_args():
		if not await test_native_resume():
			end_run(1)
			return
		finish()
		return
	if "--defense" in OS.get_cmdline_user_args():
		if not await test_defense():
			end_run(1)
			return
		finish()
		return
	var campaign := scene.campaign
	check(campaign.gold == 0 and campaign.levels == [1, 1, 1]
		and scene.get_node("%FarmBorder").disabled, "fresh session and locked farming")
	await capture("initial")
	await next_battle()
	check(campaign.border_cleared and campaign.current_encounter == Data.Encounter.ARCHER_POSITION
		and campaign.gold == 10 and scene.get_node("%LastResult").text.contains("+10"),
		"real-time Border victory automatically advances to Archer and pays once")
	await capture("archer")
	var archer := campaign.battle
	click(scene.get_node("%FarmBorder"))
	check(campaign.battle == archer and campaign.pending_navigation == Campaign.Navigation.FARM
		and scene.get_node("%PendingNavigation").text.contains("after this battle"),
		"viewport farm request defers without abandoning Archer")
	# Isolated affordability fixture only: battles, clearances and timing stay real.
	campaign.gold += 180
	scene._refresh()
	var old_health: int = archer.players[0].max_health
	for button in scene.upgrades:
		click(button)
		click(button)
	check(campaign.levels == [3, 3, 3] and campaign.gold == 10
		and archer.players[0].max_health == old_health, "mouse purchases charge 180; current snapshot unchanged")
	await next_battle()
	check(campaign.archer_cleared and campaign.mode == Campaign.Mode.FARM
		and campaign.current_encounter == Data.Encounter.BORDER_SKIRMISH and campaign.gold == 40
		and campaign.battle.players[0].max_health > old_health,
		"Archer settles before deferred farming; purchases apply to successor")
	await capture("farm")
	var farming := campaign.battle
	await keyboard(scene.get_node("%Frontier"))
	check(campaign.battle == farming and campaign.pending_navigation == Campaign.Navigation.FRONTIER,
		"viewport keyboard frontier request defers until farm settlement")
	await next_battle()
	check(campaign.current_encounter == Data.Encounter.STRONGHOLD
		and campaign.mode == Campaign.Mode.ADVANCE and campaign.gold == 50,
		"farm reward retained before frontier starts Stronghold")
	await capture("stronghold")
	await next_battle()
	check(campaign.stronghold_cleared and campaign.phase == Campaign.Phase.CONQUEST_CLEARED
		and campaign.gold == 80 and scene.get_node("%Frontier").disabled
		and scene.get_node("%CampaignStatus").text.contains("prepare upgrades, then Start Defense; ordinary farming remains available"),
		"real-time Stronghold victory pays once and renders conquest checkpoint")
	await capture("conquest")
	var terminal := campaign.battle
	await create_timer(1.2).timeout
	check(campaign.battle == terminal and campaign.gold == 80 and not scene.is_processing(),
		"checkpoint remains idle without replay or duplicate reward")
	click(scene.get_node("%FarmArcher"))
	check(campaign.phase == Campaign.Phase.RUNNING and campaign.mode == Campaign.Mode.FARM
		and campaign.current_encounter == Data.Encounter.ARCHER_POSITION and scene.is_processing(),
		"checkpoint farming resumes real processing")
	await keyboard(scene.get_node("%Frontier"))
	await next_battle()
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.gold == 110,
		"deferred return settles Archer then stops at cleared checkpoint")
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	# Capped upgrade buttons cannot take focus; the last enabled farming control can.
	var farm: Button = scene.get_node("%FarmArcher")
	farm.grab_focus()
	await process_frame
	await process_frame
	check(scene.get_node("Margin/Scroll").scroll_vertical > 0
		and root.get_visible_rect().encloses(farm.get_global_rect()), "small-window focus-follow scroll exposes farming")
	await capture("small-scrolled")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await process_frame
	await capture("small-checkpoint")
	check(not foreground_broken, "campaign interactions remained foreground and unminimized")
	print("CAMPAIGN INTERACTIONS: %d checks, %d failures; native suspension gate follows" % [checks, failures])
	await keyboard(farm)
	if not await test_native_resume():
		end_run(1)
		return
	finish()

func test_defense() -> bool:
	var campaign := scene.campaign
	check(campaign.gold == 0 and campaign.gate_level == 1 and campaign.levels == [1, 1, 1],
		"defense scenario starts a fresh session")
	campaign.gold = 180 # Isolated affordability fixture; no combat or outcome mutation.
	scene._refresh()
	await process_frame
	for button in scene.upgrades:
		click(button)
		click(button)
	check(campaign.gold == 0 and campaign.levels == [3, 3, 3], "real troop purchases charge 180")
	for i in range(3):
		await next_battle()
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.gold == 70
		and not scene.get_node("%StartDefense").disabled, "conquest enables explicit defense preparation")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-ready")
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	for name in ["StartDefense", "GateUpgrade"]:
		var button: Button = scene.get_node("%" + name)
		button.grab_focus()
		await process_frame
		await process_frame
		check(button.has_focus() and not button.disabled
			and root.get_visible_rect().encloses(button.get_global_rect())
			and scene.get_node("Margin/Scroll").scroll_vertical > 0,
			"narrow focus-follow exposes new control " + name)
	await capture("small-defense-controls")
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	await process_frame
	await process_frame
	click(scene.get_node("%StartDefense"))
	var assault := campaign.battle
	check(campaign.phase == Campaign.Phase.DEFENDING and assault.rounds == 0
		and assault.gate_health == 80 and assault.gate_max_health == 80,
		"viewport starts fresh level-one defense without checkpoint catch-up")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-start")
	click(scene.get_node("%GateUpgrade"))
	click(scene.get_node("%GateUpgrade"))
	check(campaign.gate_level == 3 and campaign.gold == 10
		and assault.gate_health == 80 and assault.gate_max_health == 80,
		"live purchases charge sixty without changing current gate snapshot")
	var deadline: int = Time.get_ticks_msec() + 15000
	while campaign.battle == assault and assault.gate_health == 80 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(campaign.battle == assault and assault.gate_health > 0 and assault.gate_health < 80,
		"real elapsed rounds damage the original gate")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-damaged")
	await next_battle()
	check(campaign.mode == Campaign.Mode.FARM and campaign.current_encounter == Data.Encounter.ARCHER_POSITION
		and campaign.gold == 10 and campaign.gate_level == 3 and not scene.get_node("%GateHealth").visible
		and scene.get_node("%LastResult").text.contains("Defeat · +0 gold · Gate destroyed"),
		"real defeat routes ordinary recovery with retained zero-gold reason")
	await capture("defense-recovery")
	await keyboard(scene.get_node("%Frontier"))
	await next_battle()
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.gold == 40
		and not scene.get_node("%StartDefense").disabled, "keyboard return settles farm before explicit retry")
	click(scene.get_node("%StartDefense"))
	assault = campaign.battle
	check(assault.rounds == 0 and assault.gate_health == 200 and assault.gate_max_health == 200,
		"retry gets fresh full upgraded gate")
	click(scene.get_node("%FarmBorder"))
	check(campaign.battle == assault and campaign.pending_navigation == Campaign.Navigation.FARM
		and scene.get_node("%PendingNavigation").text.contains("if defense fails"), "defense farm input queues recovery only")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-retry")
	if not await test_native_resume(Campaign.Phase.DEFENDING):
		return false
	await next_battle()
	check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.battle == assault
		and assault.gate_health > 0 and campaign.gold == 40
		and campaign.pending_navigation == Campaign.Navigation.NONE
		and scene.get_node("%LastResult").text == "Counterattack: Victory · +0 gold"
		and scene.get_node("%CampaignStatus").text.contains("Campaign secured"),
		"real defense victory overrides farming and retains winning gate without reward")
	var rounds: int = assault.rounds
	var gate: int = assault.gate_health
	await create_timer(1.2).timeout
	check(not scene.is_processing() and campaign.battle == assault and assault.rounds == rounds
		and assault.gate_health == gate and campaign.gold == 40, "secured state stays idle without replay or payment")
	for name in ["StartDefense", "FarmBorder", "FarmArcher", "Frontier"]:
		check(scene.get_node("%" + name).disabled, "secured navigation disabled " + name)
	await capture("campaign-secured")
	return true

func await_focus() -> bool:
	var deadline: int = Time.get_ticks_msec() + 3000
	while (not root.has_focus() or scene.suspended or root.mode == Window.MODE_MINIMIZED) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	var focused: bool = root.has_focus() and not scene.suspended and root.mode != Window.MODE_MINIMIZED
	check(focused, "Godot reports window focused, unminimized and resumed")
	return focused

func next_battle() -> void:
	var completed := scene.campaign.battle
	var deadline: int = Time.get_ticks_msec() + 15000
	while scene.campaign.battle == completed and scene.campaign.phase in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING] and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.campaign.battle != completed or scene.campaign.phase in [Campaign.Phase.CONQUEST_CLEARED, Campaign.Phase.CAMPAIGN_SECURED],
		"real elapsed-time battle boundary within 15 seconds")

func test_native_resume(expected_phase: Campaign.Phase = Campaign.Phase.RUNNING) -> bool:
	# Only unattended focus-only diagnoses gameplay beyond a native focus failure.
	var separate_native_focus: bool = "--focus-only" in OS.get_cmdline_user_args() and not manual
	var battle := scene.campaign.battle
	var same_active_battle := func() -> bool:
		return scene.campaign.battle == battle and scene.campaign.phase == expected_phase \
			and battle.result == Presentation.Combat.Result.ONGOING and scene.is_processing()
	if not same_active_battle.call():
		return native_gate_incomplete("expected active battle missing before minimize request")
	check(true, "native suspension test starts with expected active combat, not an idle checkpoint")
	watching_focus = false
	if manual or native_driver:
		var remaining: float = watchdog.time_left
		if manual:
			# Exclude only human readiness, never replenish measured time already spent.
			watchdog.time_left = INF
		if native_driver:
			native_driver_request("minimize")
		else:
			root.title = "Campaign smoke: MINIMIZE THIS WINDOW NOW; automatic restore follows"
			print("ACTION: waiting for you — click the Godot title-bar minimize button when ready")
		while root.mode != Window.MODE_MINIMIZED:
			await process_frame
		if manual:
			check(watchdog.time_left == INF, "human readiness excluded from measured watchdog")
			watchdog.time_left = remaining
			check(watchdog.time_left == remaining and remaining > 0.0 and remaining < 60.0,
				"watchdog restores saved remainder, not a fresh 60 seconds")
			print("WATCHDOG: saved=%.6f restored=%.6f seconds" % [remaining, watchdog.time_left])
	else:
		root.mode = Window.MODE_MINIMIZED
	if not same_active_battle.call():
		return native_gate_incomplete("readiness outlasted the expected battle before observed minimization")
	await create_timer(0.2).timeout
	if not same_active_battle.call() or root.mode != Window.MODE_MINIMIZED or not scene.suspended:
		return native_gate_incomplete("OS minimization did not suspend the same ongoing battle with processing enabled "
			+ "(mode=%d focus=%s suspended=%s processing=%s phase=%d expected_phase=%d same_battle=%s result=%d)" % [
				root.mode, root.has_focus(), scene.suspended, scene.is_processing(), scene.campaign.phase,
				expected_phase, scene.campaign.battle == battle, battle.result])
	var native_focus_failed: bool = root.has_focus()
	if native_focus_failed and not separate_native_focus:
		return native_gate_incomplete("native minimized window retained focus")
	check(not native_focus_failed, "native minimized window reports focus lost")
	check(true, "OS minimization suspends the same ongoing battle in expected phase with processing enabled")
	var rounds: int = battle.rounds
	var elapsed: int = scene.elapsed_usec
	var gate: int = battle.gate_health
	var gold: int = scene.campaign.gold
	var level: int = scene.campaign.gate_level
	var frozen_interval := create_timer(1.2)
	while frozen_interval.time_left > 0:
		await process_frame
		if not same_active_battle.call() or root.mode != Window.MODE_MINIMIZED or not scene.suspended \
			or battle.rounds != rounds or scene.elapsed_usec != elapsed or battle.gate_health != gate \
			or scene.campaign.gold != gold or scene.campaign.gate_level != level:
			return native_gate_incomplete("same active battle or frozen state changed during minimized interval")
		if root.has_focus():
			if not separate_native_focus:
				return native_gate_incomplete("native window regained focus during minimized interval")
			if not native_focus_failed:
				check(false, "native window regained focus during minimized interval")
				native_focus_failed = true
	check(true, "native minimized interval freezes same active battle, rounds, accumulated time and gate")
	if native_driver:
		native_driver_request("restore")
	else:
		root.mode = Window.MODE_WINDOWED
		root.grab_focus()
	if not await await_focus():
		return native_gate_incomplete("native restore did not regain focus")
	if not same_active_battle.call() or battle.rounds != rounds:
		return native_gate_incomplete("native restore changed active battle or added a catch-up round")
	check(true, "native restore retains same active battle; no catch-up round")
	watching_focus = true
	# Completed gameplay observations do not erase native failures: finish() exits nonzero.
	return true

func native_driver_request(action: String) -> void:
	print("NATIVE_DRIVER: %s hwnd=%d pid=%d" % [action,
		DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id()), OS.get_process_id()])

func native_gate_incomplete(reason: String) -> bool:
	check(false, "native suspension gate incomplete: " + reason)
	print("SUMMARY: campaign: incomplete — rerun the full affected scenario; %d checks, %d failures" % [checks, failures])
	if not native_driver:
		root.mode = Window.MODE_WINDOWED
		root.grab_focus()
	return false

func click(button: Button) -> void:
	scene.get_node("Margin/Scroll").ensure_control_visible(button)
	check(not button.disabled and root.get_visible_rect().encloses(button.get_global_rect()),
		"mouse target enabled and fully visible")
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event, true)

func keyboard(button: Button) -> void:
	button.grab_focus()
	# Re-focusing an already focused control does not scroll it back into view.
	scene.get_node("Margin/Scroll").ensure_control_visible(button)
	await process_frame
	await process_frame
	check(button.has_focus() and not button.disabled and root.get_visible_rect().encloses(button.get_global_rect()),
		"keyboard target focused, enabled and visible")
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.pressed = down
		root.push_input(event, true)

func capture(title: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), title + ": native rendered image")
	if image != null and not image.is_empty():
		check(image.save_png(OUTPUT + title + ".png") == OK, title + ": PNG saved")

func finish() -> void:
	check(not foreground_broken and root.has_focus() and not scene.suspended
		and root.mode != Window.MODE_MINIMIZED, "continuous foreground outside explicit native suspension test")
	print("SUMMARY: campaign: %d graphical checks, %d failures" % [checks, failures])
	end_run(0 if failures == 0 else 1)

func end_run(code: int) -> void:
	exit_status = code
	if not manual and not native_driver:
		quit(code)
		return
	watching_focus = false
	watchdog.time_left = INF
	if native_driver:
		native_driver_request("complete")
		return
	root.title = "Campaign check %s — close this window when YOU are ready" % ["PASSED" if code == 0 else "FAILED"]
	print("WAITING: results recorded; close the window when you are ready")