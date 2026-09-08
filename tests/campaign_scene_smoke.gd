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
		await test_native_resume()
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
		and scene.get_node("%CampaignStatus").text.contains("prototype ends here"),
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
	await test_native_resume()
	finish()

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
	while scene.campaign.battle == completed and scene.campaign.phase == Campaign.Phase.RUNNING and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.campaign.battle != completed or scene.campaign.phase == Campaign.Phase.CONQUEST_CLEARED,
		"real elapsed-time battle boundary within 15 seconds")

func test_native_resume() -> void:
	check(scene.campaign.phase == Campaign.Phase.RUNNING and scene.is_processing(),
		"native suspension test starts with active combat, not an idle checkpoint")
	watching_focus = false
	if "--manual-focus" in OS.get_cmdline_user_args():
		root.title = "Campaign smoke: MINIMIZE THIS WINDOW NOW; automatic restore follows"
		print("ACTION: waiting for you — click the Godot title-bar minimize button when ready")
		while root.mode != Window.MODE_MINIMIZED:
			# Human readiness is unbounded; measured battle/suspension deadlines are unchanged.
			watchdog.time_left = 60.0
			await process_frame
		check(root.mode == Window.MODE_MINIMIZED, "physical minimize observed")
	else:
		root.mode = Window.MODE_MINIMIZED
	await create_timer(0.2).timeout
	check(root.mode == Window.MODE_MINIMIZED and not root.has_focus() and scene.suspended,
		"OS minimization delivers real focus-loss suspension (mode=%d focus=%s suspended=%s)" % [root.mode, root.has_focus(), scene.suspended])
	var battle := scene.campaign.battle
	var rounds: int = battle.rounds
	var elapsed: int = scene.elapsed_usec
	await create_timer(1.2).timeout
	check(battle.rounds == rounds and scene.elapsed_usec == elapsed,
		"native minimized interval freezes rounds and accumulated time")
	root.mode = Window.MODE_WINDOWED
	root.grab_focus()
	await await_focus()
	check(battle.rounds == rounds, "native restore excludes minimized interval; no catch-up round")
	watching_focus = true

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
	if not manual:
		quit(code)
		return
	watching_focus = false
	watchdog.time_left = INF
	root.title = "Campaign check %s — close this window when YOU are ready" % ["PASSED" if code == 0 else "FAILED"]
	print("WAITING: results recorded; close the window when you are ready")