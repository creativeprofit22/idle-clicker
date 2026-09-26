extends SceneTree

const CampaignScene = preload("res://scenes/campaign_prototype.tscn")
const Presentation = preload("res://src/campaign_prototype.gd")
const Campaign = preload("res://src/campaign.gd")
const Data = preload("res://src/encounter_data.gd")
const CampaignSave = preload("res://src/campaign_save.gd")
const CampaignState = preload("res://src/campaign_state.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")
const OUTPUT: String = "res://.gg/screenshots/campaign/"
var scene: Presentation
# Isolated campaign save; the player's real campaign file is never touched.
var fixture: ProgressFixture
var checks: int = 0
var failures: int = 0
var watching_focus: bool = false
var foreground_broken: bool = false
var watchdog: SceneTreeTimer
# Independent proof of watchdog consumption while it counts. The engine drops process time
# beyond max physics steps per frame, so the watchdog may trail wall time but never exceed it;
# summed process deltas are the same clock the watchdog uses and must match it.
var watchdog_counting: bool = false
var watchdog_engine_seconds: float = 0.0
var watchdog_mark_usec: int = 0
var watchdog_measured_usec: int = 0
var manual: bool = "--manual-focus" in OS.get_cmdline_user_args()
var native_driver: bool = "--native-window-driver" in OS.get_cmdline_user_args()
# Physical title-bar minimize with the native driver's restore (never a driver minimize).
var human_minimize: bool = "--human-minimize" in OS.get_cmdline_user_args()
var exit_status: int = 1
# Read-only context for native failure diagnostics; never used by gate conditions.
var diagnostic_battle: RefCounted
var diagnostic_expected_phase: int = -1

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
		native_diagnostic("foreground-interrupted")
		check(false, "foreground interrupted (mode=%d focus=%s suspended=%s)" % [root.mode, root.has_focus(), scene.suspended])
		print("SUMMARY: campaign: incomplete — foreground interrupted; %d checks, %d failures" % [checks, failures])
		if not manual:
			quit_after_cleanup(1)
		else:
			root.title = "Focus was interrupted — test will report failure, window stays open"

func run() -> void:
	if native_driver and manual:
		print("FAIL native driver cannot replace physical manual verification; SUMMARY: incomplete")
		quit(1)
		return
	if human_minimize and not native_driver:
		print("FAIL --human-minimize requires the native Windows driver; SUMMARY: incomplete")
		quit(1)
		return
	if native_driver:
		auto_accept_quit = false
		root.close_requested.connect(func() -> void: quit_after_cleanup(exit_status))
	watchdog = create_timer(60.0)
	process_frame.connect(func() -> void:
		if watchdog_counting:
			watchdog_engine_seconds += root.get_process_delta_time())
	watchdog_counting = true
	watchdog_mark_usec = Time.get_ticks_usec()
	watchdog.timeout.connect(func() -> void:
		check(false, "campaign smoke timeout; SUMMARY: incomplete")
		end_run(1))
	if DisplayServer.get_name() == "headless":
		print("FAIL campaign graphical renderer required; SUMMARY: incomplete")
		quit(1)
		return
	if manual:
		auto_accept_quit = false
		root.close_requested.connect(func() -> void: quit_after_cleanup(exit_status))
		root.title = "Campaign check — click Start when YOU are ready"
		var start := Button.new()
		start.text = "START WHEN READY\nThen keep this window selected until the MINIMIZE prompt.\nThere is no countdown. The window stays open afterward."
		start.position = Vector2(24, 24)
		start.size = Vector2(672, 160)
		root.add_child(start)
		watchdog.time_left = INF
		watchdog_counting = false
		await start.pressed
		root.remove_child(start)
		start.queue_free()
		watchdog.time_left = 60.0
		watchdog_counting = true
		watchdog_mark_usec = Time.get_ticks_usec()
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK,
		"capture directory available")
	fixture = ProgressFixture.new("campaign.json")
	check(fixture.owned, "isolated campaign save directory owned")
	scene = CampaignScene.instantiate()
	scene.campaign_save = CampaignSave.new(fixture.path) if fixture.owned else null
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
	if "--dynasty" in OS.get_cmdline_user_args():
		if not await test_dynasty():
			end_run(1)
			return
		finish()
		return
	var campaign := scene.campaign
	check(campaign.gold == 0 and campaign.levels == [1, 1, 1]
		and scene.get_node("%FarmBorder").disabled, "fresh session and locked farming")
	await capture("initial")
	# Rally by mouse during the real Border: saved, arms 5 boosted rounds, focus stays with the pressed control.
	var rally: Button = scene.get_node("%Rally")
	check(not rally.disabled and rally.text == "Rally — +50% army damage for 5 rounds"
		and campaign.can_rally(), "Rally ready during the first Border")
	var focus_before: Control = root.gui_get_focus_owner()
	await click(rally)
	check(campaign.battle.result == Presentation.Combat.Result.ONGOING and campaign.rally_rounds > 0
		and rally.disabled and rally.text.begins_with("Rally active — ")
		and root.gui_get_focus_owner() in [focus_before, rally]
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).rally_rounds == campaign.rally_rounds,
		"mouse Rally arms the boost, saves it and never moves focus to another control")
	await capture("campaign-rally-active")
	# Shield Wall by mouse next to Rally in the same Border: arms, saves, focus never moves elsewhere.
	var shield_wall: Button = scene.get_node("%ShieldWall")
	check(not shield_wall.disabled and shield_wall.text == "Shield Wall — −25% enemy damage for 5 rounds"
		and campaign.can_shield_wall(), "Shield Wall ready during the first Border alongside active Rally")
	var shield_focus_before: Control = root.gui_get_focus_owner()
	await click(shield_wall)
	check(campaign.battle.result == Presentation.Combat.Result.ONGOING and campaign.shield_wall_rounds > 0
		and campaign.rally_rounds > 0 and shield_wall.disabled and shield_wall.text.begins_with("Shield Wall active — ")
		and root.gui_get_focus_owner() in [shield_focus_before, shield_wall]
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).shield_wall_rounds == campaign.shield_wall_rounds,
		"mouse Shield Wall arms the cut, saves it and never moves focus to another control")
	await capture("campaign-shield-wall-active")
	await next_battle()
	check(campaign.rally_rounds == 0 and campaign.rally_cooldown > 0 and campaign.rally_cooldown <= 20
		and rally.disabled and rally.text.begins_with("Rally recovering — ready in %d battle round" % campaign.rally_cooldown)
		and rally.text.ends_with("(%d s)" % campaign.rally_cooldown),
		"Border end drops Rally to a cooldown shown with rounds and seconds left")
	await capture("campaign-rally-cooldown")
	check(campaign.shield_wall_rounds == 0 and campaign.shield_wall_cooldown > 0 and campaign.shield_wall_cooldown <= 20
		and shield_wall.disabled
		and shield_wall.text.begins_with("Shield Wall recovering — ready in %d battle round" % campaign.shield_wall_cooldown)
		and shield_wall.text.ends_with("(%d s)" % campaign.shield_wall_cooldown),
		"Border end drops Shield Wall to a cooldown shown with rounds and seconds left")
	scene.get_node("Margin/Scroll").ensure_control_visible(shield_wall)
	await process_frame
	await process_frame
	await capture("campaign-shield-wall-cooldown")
	check(campaign.border_cleared and campaign.current_encounter == Data.Encounter.ARCHER_POSITION
		and campaign.gold == 10 and scene.get_node("%LastResult").text.contains("+10"),
		"real-time Border victory automatically advances to Archer and pays once")
	await capture("archer")
	var archer := campaign.battle
	await click(scene.get_node("%FarmBorder"))
	check(campaign.battle == archer and campaign.pending_navigation == Campaign.Navigation.FARM
		and scene.get_node("%PendingNavigation").text.contains("after this battle"),
		"viewport farm request defers without abandoning Archer")
	# Isolated affordability fixture only: battles, clearances and timing stay real.
	campaign.gold += 180
	scene._refresh()
	var old_health: int = archer.players[0].max_health
	for button in scene.upgrades:
		await click(button)
		await click(button)
	check(campaign.levels == [3, 3, 3] and campaign.gold == 10
		and archer.players[0].max_health == old_health, "mouse purchases charge 180; current snapshot unchanged")
	# Archer Platform during the real Archer battle: +150 isolated fixture gold, spent exactly (net zero).
	campaign.gold += 150
	scene._refresh()
	var platform: Button = scene.get_node("%ArcherPlatform")
	var archer_rounds: int = archer.rounds
	check(not platform.disabled and platform.text == "Archer Platform Lv.0 · +0 damage/round in defense · Upgrade 30 gold",
		"Archer Platform offered at Lv.0 for 30 gold during conquest")
	await click(platform)
	check(campaign.archer_platform_level == 1 and campaign.gold == 130 and campaign.battle == archer
		and archer.platform_damage == 0 and archer.players[0].max_health == old_health
		and platform.text == "Archer Platform Lv.1 · +3 damage/round in defense · Upgrade 50 gold"
		and scene.get_node("%SaveStatus").text == "Saved" and saved_platform_level() == 1,
		"mouse Archer Platform Lv.1 charges 30, saves at once and leaves the conquest battle unchanged")
	await keyboard(platform)
	check(campaign.archer_platform_level == 2 and campaign.gold == 80 and campaign.battle == archer
		and archer.platform_damage == 0 and root.gui_get_focus_owner() == platform
		and platform.text == "Archer Platform Lv.2 · +6 damage/round in defense · Upgrade 70 gold"
		and saved_platform_level() == 2,
		"keyboard Archer Platform Lv.2 charges 50, saves at once, keeps focus, conquest battle unchanged")
	await click(platform)
	check(campaign.archer_platform_level == 3 and campaign.gold == 10 and campaign.battle == archer
		and archer.platform_damage == 0 and platform.disabled
		and platform.text == "Archer Platform Lv.3 · +9 damage/round in defense · MAX" and saved_platform_level() == 3
		and archer.rounds >= archer_rounds,
		"mouse Archer Platform Lv.3 charges 70, saves and disables the button at MAX")
	await capture("campaign-platform-max")
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
	await click(scene.get_node("%FarmArcher"))
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

func test_dynasty() -> bool:
	var campaign := scene.campaign
	check(campaign.dynasty == 1 and campaign.drill_rank == 0 and campaign.legacy == 0
		and campaign.gold == 0 and campaign.levels == [1, 1, 1]
		and scene.get_node("%TrainDrill").disabled, "dynasty starts without Legacy, Drill or purchases")
	if not await observe_passive_border(false):
		return false
	# Established affordability fixture only; every clearance and outcome uses real elapsed combat.
	campaign.gold += 180
	scene._refresh()
	for button in scene.upgrades:
		await click(button)
		await click(button)
	check(campaign.gold == 10 and campaign.levels == [3, 3, 3], "dynasty troop purchases charge 180 after passive baseline")
	await next_battle()
	await next_battle()
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.gold == 70
		and not campaign.can_found_dynasty(), "real conquest alone cannot found dynasty")
	await click(scene.get_node("%GateUpgrade"))
	await click(scene.get_node("%GateUpgrade"))
	await keyboard(scene.get_node("%StartDefense"))
	var defense := campaign.battle
	check(campaign.phase == Campaign.Phase.DEFENDING and defense.rounds == 0
		and defense.gate_health == 200 and campaign.gold == 10, "prepared level-three gate begins real defense")
	if not await test_native_resume(Campaign.Phase.DEFENDING):
		return false
	await next_battle()
	check(campaign.can_found_dynasty() and campaign.battle == defense and defense.gate_health > 0
		and campaign.gold == 10 and campaign.legacy == 10 and not scene.is_processing()
		and scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated · +10 Legacy earned",
		"settled real defense enables optional reset and pays 10 Legacy, no gold")
	if not campaign.can_found_dynasty():
		return false
	var drill_button: Button = scene.get_node("%TrainDrill")
	await click(drill_button)
	await process_frame
	await capture("dynasty-secured")
	check(campaign.drill_rank == 1 and campaign.legacy == 0 and campaign.battle == defense
		and drill_button.disabled and drill_button.text == "Train Drill rank 2 — 20 Legacy"
		and scene.get_node("%DynastyStatus").text == "Dynasty 1 · Legacy 0 · Drill rank 1 (×2 squad damage)",
		"native Train Drill click spends 10 Legacy for rank 1 without touching the settled battle")
	var cadre_button: Button = scene.get_node("%VeteranCadre")
	check(cadre_button.disabled and cadre_button.text == "Recruit Veteran Cadre — 50 Legacy"
		and cadre_button.get_index() == drill_button.get_index() + 1, "Veteran Cadre shown after Drill, unaffordable at 0 Legacy")
	# Real secured dynasty-1 state, reused below as the Veteran Cadre relaunch fixture.
	var secured_capture := CampaignState.capture(campaign, scene.elapsed_usec)
	check(secured_capture.outcome == CampaignState.Outcome.VALID, "secured dynasty state captured for the cadre fixture")
	var checkpoint := dynasty_checkpoint()
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	await click(scene.get_node("%FoundDynasty"))
	await process_frame
	await process_frame
	check(scene.dynasty_preview_open and scene.get_node("%CancelDynasty").has_focus()
		and dynasty_checkpoint() == checkpoint, "mouse preview moves focus without changing secured gameplay")
	var losses: String = scene.get_node("%DynastyLosses").text
	check(losses.contains("10 gold") and losses.count("Lv.3") == 4
		and losses.contains("all return to level 1") and losses.contains("territory and security")
		and losses.contains("fractional round time")
		and losses.contains("Keep Legacy 0 and Drill rank 1 (×2 squad damage after level additions)")
		and losses.contains("health, gold rewards and round frequency are unchanged")
		and losses.contains("Next secured campaign earns 3 Legacy") and not losses.contains("only dynasty reset")
		and losses.contains("Legacy and Drill rank are kept in the campaign save")
		and losses.contains("main-game saves are untouched")
		and losses.contains("Archer Platform Lv.0 returns to level 0.")
		and scene.get_node("%ConfirmDynasty").text == "Confirm reset — start dynasty 2",
		"native preview discloses actual losses, exact benefit and save limits")
	# Opening already focused Cancel; use actual focus transitions, not a no-op grab.
	for name in ["ConfirmDynasty", "CancelDynasty", "ConfirmDynasty"]:
		var button: Button = scene.get_node("%" + name)
		button.grab_focus()
		await process_frame
		await process_frame
		check(button.has_focus() and not button.disabled
			and root.get_visible_rect().encloses(button.get_global_rect())
			and scene.get_node("Margin/Scroll").scroll_vertical > 0,
			"narrow focus-follow exposes " + name)
	await capture("dynasty-preview")
	await keyboard(scene.get_node("%CancelDynasty"))
	check(not scene.dynasty_preview_open and scene.get_node("%FoundDynasty").has_focus()
		and dynasty_checkpoint() == checkpoint, "keyboard Cancel restores unchanged secured checkpoint")
	await keyboard(scene.get_node("%FoundDynasty"))
	# Let the reopen and its focus-follow settle; a person cannot press Escape in the same frame.
	await process_frame
	await process_frame
	check(scene.dynasty_preview_open and scene.get_node("%CancelDynasty").has_focus()
		and dynasty_checkpoint() == checkpoint, "keyboard reopens preview with Cancel focused")
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		root.push_input(event, true)
	check(not scene.dynasty_preview_open and scene.get_node("%FoundDynasty").has_focus()
		and dynasty_checkpoint() == checkpoint, "Escape dismisses reopened preview without gameplay mutation")
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(scene.get_node("%FoundDynasty").get_global_rect()),
		"narrow focus-follow keeps FoundDynasty visible after Escape")
	await click(scene.get_node("%FoundDynasty"))
	# Observe the synchronous transition after the scene handler, before key release
	# legitimately contributes foreground microseconds through Presentation._input().
	scene.get_node("%ConfirmDynasty").pressed.connect(func() -> void:
		check(scene.elapsed_usec == 0 and campaign.battle.rounds == 0,
			"confirmation press clears fractional clock before subsequent input"), CONNECT_ONE_SHOT)
	await keyboard(scene.get_node("%ConfirmDynasty"))
	var successor := campaign.battle
	check(successor != defense and campaign.dynasty == 2 and campaign.drill_rank == 1 and campaign.legacy == 0
		and campaign.gold == 0 and campaign.levels == [1, 1, 1] and campaign.gate_level == 1
		and not campaign.border_cleared and not campaign.archer_cleared and not campaign.stronghold_cleared
		and campaign.mode == Campaign.Mode.ADVANCE and campaign.farm_encounter == -1
		and campaign.pending_navigation == Campaign.Navigation.NONE and campaign.pending_farm == -1
		and successor.rounds == 0 and not successor.commander_queued and not successor.is_defense
		and scene.is_processing() and not scene.dynasty_preview_open
		and scene.get_node("%LastResult").text == "No completed battle"
		and scene.get_node("%DynastyStatus").text == "Dynasty 2 · Legacy 0 · Drill rank 1 (×2 squad damage) · Securing this campaign earns 3 Legacy"
		and scene.get_node("%FoundDynasty").disabled,
		"keyboard confirmation creates clean round-zero successor and clears ownership, progress and clock")
	root.size = Vector2i(720, 960)
	root.content_scale_size = Vector2i(720, 960)
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("dynasty-fresh-successor")
	if not await observe_passive_border(true):
		return false
	check(not campaign.settle(successor) and not campaign.settle(defense) and campaign.gold == 10,
		"old defense and successor cannot settle twice")
	if secured_capture.outcome != CampaignState.Outcome.VALID:
		return false
	return await test_veteran_cadre(secured_capture.state)

# Affordability fixture: dynasty 1 can only ever hold 10 Legacy, so the real secured state's history
# is rewritten to a ledger-valid secured dynasty 7 (best Threat 5, 73 earned, 10 spent on Drill, 63 held)
# and loaded through the scene's normal relaunch path. Purchase, preview and reset are all real input.
func test_veteran_cadre(secured: Dictionary) -> bool:
	var state: Dictionary = secured.duplicate(true)
	state.dynasty = 7
	state.best_threat = 5
	state.legacy_earned = 73
	state.legacy = 63
	state.saved_at = 0
	check(state.veteran_cadre == false and state.drill_rank == 1 and fixture.put(JSON.stringify(state)) == OK,
		"cadre fixture written to the isolated save")
	var old := scene
	root.remove_child(old)
	old.free()
	scene = CampaignScene.instantiate()
	scene.campaign_save = CampaignSave.new(fixture.path)
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	var campaign := scene.campaign
	var button: Button = scene.get_node("%VeteranCadre")
	check(campaign.dynasty == 7 and campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.legacy == 63
		and not campaign.veteran_cadre and campaign.levels == [3, 3, 3] and not button.disabled
		and button.text == "Recruit Veteran Cadre — 50 Legacy" and scene.get_node("%SaveStatus").text == "Autosave on",
		"relaunched ledger-valid fixture offers Veteran Cadre")
	button.grab_focus()
	await process_frame
	await process_frame
	check(button.has_focus() and root.get_visible_rect().encloses(button.get_global_rect()),
		"narrow focus-follow exposes VeteranCadre")
	await click(button)
	await process_frame
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	check(campaign.veteran_cadre and campaign.legacy == 13 and campaign.levels == [3, 3, 3] and button.disabled
		and button.text == "Veteran Cadre owned — new dynasties start troops at level 2"
		and scene.get_node("%DynastyStatus").text.ends_with(" · Veteran Cadre")
		and scene.get_node("%SaveStatus").text == "Saved" and on_disk is Dictionary
		and on_disk.veteran_cadre == true and on_disk.legacy == 13 and on_disk.version == 9
		and on_disk.archer_platform_level == 0,
		"native Veteran Cadre click spends 50 Legacy once, shows owned and saves v9")
	await click(scene.get_node("%FoundDynasty"))
	await process_frame
	await process_frame
	var losses: String = scene.get_node("%DynastyLosses").text
	check(scene.dynasty_preview_open and scene.get_node("%CancelDynasty").has_focus() and button.disabled
		and losses.contains("Horse archers Lv.3 return to level 2 (Veteran Cadre)")
		and losses.contains("returns to level 1") and not losses.contains("all return to level 1")
		and losses.contains("Keep Veteran Cadre (owned: troops start at level 2)"),
		"native preview discloses the level-2 start and the kept Veteran Cadre")
	for name in ["ConfirmDynasty", "CancelDynasty", "ConfirmDynasty"]:
		var target: Button = scene.get_node("%" + name)
		target.grab_focus()
		await process_frame
		await process_frame
		check(target.has_focus() and not target.disabled and root.get_visible_rect().encloses(target.get_global_rect()),
			"cadre preview narrow focus-follow exposes " + name)
	await capture("dynasty-cadre")
	await keyboard(scene.get_node("%ConfirmDynasty"))
	await process_frame
	on_disk = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	check(campaign.dynasty == 8 and campaign.levels == [2, 2, 2] and campaign.gate_level == 1 and campaign.legacy == 13
		and campaign.veteran_cadre and campaign.battle.players[0].damage == 12 and campaign.battle.rounds == 0
		and not scene.dynasty_preview_open and on_disk is Dictionary and on_disk.dynasty == 8
		and on_disk.levels.map(func(level: Variant) -> int: return int(level)) == [2, 2, 2] and on_disk.veteran_cadre == true,
		"keyboard confirmation founds dynasty 8 with troops at level 2 and Drill applied once")
	root.size = Vector2i(720, 960)
	root.content_scale_size = Vector2i(720, 960)
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("dynasty-cadre-successor")
	return true

func saved_platform_level() -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	return int(data.archer_platform_level) if data is Dictionary and data.has("archer_platform_level") else -1

func dynasty_checkpoint() -> Array:
	var campaign := scene.campaign
	return [campaign.battle, campaign.battle.rounds, campaign.battle.gate_health, campaign.gold,
		campaign.levels.duplicate(), campaign.gate_level, campaign.phase, campaign.mode,
		campaign.border_cleared, campaign.archer_cleared, campaign.stronghold_cleared,
		campaign.pending_navigation, campaign.pending_farm, campaign.farm_encounter,
		campaign.dynasty, campaign.legacy, campaign.drill_rank, scene.elapsed_usec,
		scene.get_node("%LastResult").text, scene.is_processing()]

func observe_passive_border(inherited: bool) -> bool:
	var campaign := scene.campaign
	var battle := campaign.battle
	var total: int = 2 if inherited else 4
	check(campaign.current_encounter == Data.Encounter.BORDER_SKIRMISH and battle.rounds == 0
		and campaign.gold == 0 and battle.enemies[0].health == 72
		and battle.players[0].health == 120 and battle.players[1].health == 40 and battle.players[2].health == 60,
		"passive %d-round Border begins fresh with zero gold" % total)
	for round_number in range(1, total + 1):
		var deadline: int = Time.get_ticks_msec() + 2000
		while battle.rounds < round_number and Time.get_ticks_msec() < deadline:
			await process_frame
		var correct: bool = battle.rounds == round_number \
			and battle.enemies[0].health == maxi(0, 72 - round_number * (36 if inherited else 18)) \
			and battle.players[0].health == 120 - 3 * round_number \
			and battle.players[1].health == 40 and battle.players[2].health == 60 \
			and battle.result == (Presentation.Combat.Result.VICTORY if round_number == total else Presentation.Combat.Result.ONGOING)
		check(correct, "passive %d-second Border round %d: exact health and result" % [total, round_number])
		if not correct:
			return false
	check(campaign.battle != battle and campaign.current_encounter == Data.Encounter.ARCHER_POSITION
		and campaign.gold == 10 and scene.get_node("%LastResult").text == "Border Skirmish: Victory · +10 gold",
		"passive Border settles ordinary ten gold exactly at final round")
	return true

func test_defense() -> bool:
	var campaign := scene.campaign
	check(campaign.gold == 0 and campaign.gate_level == 1 and campaign.levels == [1, 1, 1],
		"defense scenario starts a fresh session")
	campaign.gold = 180 # Isolated affordability fixture; no combat or outcome mutation.
	scene._refresh()
	await process_frame
	for button in scene.upgrades:
		await click(button)
		await click(button)
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
	for name in ["StartDefense", "GateUpgrade", "ArcherPlatform"]:
		var button: Button = scene.get_node("%" + name)
		button.grab_focus()
		await process_frame
		await process_frame
		check(button.has_focus() and not button.disabled
			and root.get_visible_rect().encloses(button.get_global_rect())
			and scene.get_node("Margin/Scroll").scroll_vertical > 0,
			"narrow focus-follow exposes new control " + name)
	var gate_rect: Rect2 = scene.get_node("%GateUpgrade").get_global_rect()
	var platform_button: Button = scene.get_node("%ArcherPlatform")
	check(root.get_visible_rect().encloses(gate_rect) and root.get_visible_rect().encloses(platform_button.get_global_rect())
		and not gate_rect.intersects(platform_button.get_global_rect())
		and platform_button.get_global_rect().size.x <= 540.0
		and platform_button.text == "Archer Platform Lv.0 · +0 damage/round in defense · Upgrade 30 gold",
		"Gate and Archer Platform both fit at 540x480 without overlapping")
	await capture("small-defense-controls")
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	await process_frame
	await process_frame
	await click(scene.get_node("%StartDefense"))
	var assault := campaign.battle
	check(campaign.phase == Campaign.Phase.DEFENDING and assault.rounds == 0
		and assault.gate_health == 80 and assault.gate_max_health == 80,
		"viewport starts fresh level-one defense without checkpoint catch-up")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-start")
	await click(scene.get_node("%GateUpgrade"))
	await click(scene.get_node("%GateUpgrade"))
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
		and campaign.last_defense_loss == Presentation.Combat.DefeatReason.GATE_DESTROYED
		and scene.get_node("%LastResult").text == "Counterattack: Defeat · +0 gold · The gate broke. Upgrade the Gate or your Shield infantry to hold longer. Farm to recover, return to the checkpoint after battle, then Start Defense to retry."
		and scene.get_node("%CampaignStatus").text.ends_with(" · Last defense: the gate broke — upgrade Gate or Shield"),
		"real defeat routes ordinary recovery with retained zero-gold cause and upgrade hint")
	await capture("defense-recovery")
	# Narrow layout: the wrapped cause and hint stay inside the viewport and buy nothing.
	var hint_gold: int = campaign.gold
	var hint_levels: Array = [campaign.levels.duplicate(), campaign.gate_level]
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	var scroll: ScrollContainer = scene.get_node("Margin/Scroll")
	for name in ["CampaignStatus", "LastResult"]:
		var label: Label = scene.get_node("%" + name)
		scroll.ensure_control_visible(label)
		await process_frame
		await process_frame
		check(label.get_line_count() > 1 and label.get_visible_line_count() == label.get_line_count()
			and root.get_visible_rect().encloses(label.get_global_rect()),
			"narrow loss text wraps fully inside the viewport: " + name)
	await capture("small-defense-loss")
	var frontier: Button = scene.get_node("%Frontier")
	frontier.grab_focus()
	await process_frame
	await process_frame
	check(frontier.has_focus() and root.get_visible_rect().encloses(frontier.get_global_rect())
		and campaign.gold == hint_gold and [campaign.levels, campaign.gate_level] == hint_levels,
		"narrow focus-follow still exposes Frontier below the loss text; the hint bought nothing")
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	await process_frame
	await process_frame
	await keyboard(scene.get_node("%Frontier"))
	await next_battle()
	check(campaign.phase == Campaign.Phase.CONQUEST_CLEARED and campaign.gold == 40
		and not scene.get_node("%StartDefense").disabled
		and scene.get_node("%CampaignStatus").text.ends_with("Start Defense; ordinary farming remains available · Last defense: the gate broke — upgrade Gate or Shield"),
		"keyboard return settles farm before explicit retry and keeps the loss hint")
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	for name in ["StartDefense", "GateUpgrade", "ArcherPlatform"]:
		var button: Button = scene.get_node("%" + name)
		if button.disabled:
			check(name == "GateUpgrade" and campaign.gate_level == 3, "capped Gate stays unfocusable at the hinted checkpoint")
			continue
		button.grab_focus()
		await process_frame
		await process_frame
		check(button.has_focus() and root.get_visible_rect().encloses(button.get_global_rect()),
			"narrow focus-follow exposes %s with the loss hint shown" % name)
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	await process_frame
	await process_frame
	await click(scene.get_node("%StartDefense"))
	assault = campaign.battle
	check(assault.rounds == 0 and assault.gate_health == 200 and assault.gate_max_health == 200,
		"retry gets fresh full upgraded gate")
	await click(scene.get_node("%FarmBorder"))
	check(campaign.battle == assault and campaign.pending_navigation == Campaign.Navigation.FARM
		and scene.get_node("%PendingNavigation").text.contains("if defense fails"), "defense farm input queues recovery only")
	# Archer Platform Lv.1 by keyboard mid-assault: charged once, saved, active assault keeps +0.
	var platform: Button = scene.get_node("%ArcherPlatform")
	await keyboard(platform)
	var platform_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path))
	check(campaign.archer_platform_level == 1 and campaign.gold == 10 and campaign.battle == assault
		and assault.platform_damage == 0 and campaign._battle_platform_level == 0
		and root.gui_get_focus_owner() == platform
		and platform_disk is Dictionary and platform_disk.version == 9 and platform_disk.archer_platform_level == 1
		and platform_disk.battle.snapshot_platform_level == 0 and platform_disk.battle.snapshot_gate_level == 3,
		"keyboard Archer Platform mid-assault charges 30 and saves Lv.1 while the active assault keeps +0")
	scene.get_node("Margin/Scroll").scroll_vertical = 0
	await capture("defense-retry")
	if not await test_native_resume(Campaign.Phase.DEFENDING):
		return false
	# Rally by keyboard in the retried Counterattack at 540x480: readable, saved, focus kept.
	root.size = Vector2i(540, 480)
	root.content_scale_size = Vector2i(540, 480)
	await process_frame
	await process_frame
	var rally: Button = scene.get_node("%Rally")
	check(campaign.battle == assault and assault.result == Presentation.Combat.Result.ONGOING and not rally.disabled
		and campaign.can_rally(), "Rally ready during the retried Counterattack")
	await keyboard(rally)
	await process_frame
	check(campaign.rally_rounds > 0 and rally.disabled and rally.text.begins_with("Rally active — ")
		and root.gui_get_focus_owner() == rally and root.get_visible_rect().encloses(rally.get_global_rect())
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).rally_rounds == campaign.rally_rounds,
		"keyboard Rally in defense arms, saves, keeps focus and stays visible at 540x480")
	await capture("defense-rally-active")
	# Shield Wall by keyboard in the same Counterattack, with Rally still active: both readable, no overlap.
	var shield_wall: Button = scene.get_node("%ShieldWall")
	check(assault.result == Presentation.Combat.Result.ONGOING and not shield_wall.disabled
		and campaign.can_shield_wall() and campaign.rally_rounds > 0,
		"Shield Wall ready in the retried Counterattack while Rally is active")
	await keyboard(shield_wall)
	await process_frame
	var visible := root.get_visible_rect()
	check(campaign.shield_wall_rounds > 0 and campaign.rally_rounds > 0 and shield_wall.disabled
		and shield_wall.text.begins_with("Shield Wall active — ") and rally.text.begins_with("Rally active — ")
		and root.gui_get_focus_owner() == shield_wall and visible.encloses(shield_wall.get_global_rect())
		and visible.encloses(rally.get_global_rect())
		and not shield_wall.get_global_rect().intersects(rally.get_global_rect())
		and JSON.parse_string(FileAccess.get_file_as_string(fixture.path)).shield_wall_rounds == campaign.shield_wall_rounds,
		"keyboard Shield Wall in defense arms, saves, keeps focus and shows beside Rally at 540x480")
	await capture("defense-shield-wall-active")
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	await process_frame
	await process_frame
	await next_battle()
	check(campaign.phase == Campaign.Phase.CAMPAIGN_SECURED and campaign.battle == assault
		and assault.gate_health > 0 and campaign.gold == 10
		and campaign.pending_navigation == Campaign.Navigation.NONE
		and scene.get_node("%LastResult").text == "Counterattack: Victory · +0 gold"
		and scene.get_node("%CampaignStatus").text.contains("Campaign secured"),
		"real defense victory overrides farming and retains winning gate without reward")
	var rounds: int = assault.rounds
	var gate: int = assault.gate_health
	await create_timer(1.2).timeout
	check(not scene.is_processing() and campaign.battle == assault and assault.rounds == rounds
		and assault.gate_health == gate and campaign.gold == 10, "secured state stays idle without replay or payment")
	for name in ["StartDefense", "FarmBorder", "FarmArcher", "Frontier"]:
		check(scene.get_node("%" + name).disabled, "secured navigation disabled " + name)
	check(campaign.rally_rounds == 0 and campaign.rally_cooldown > 0 and campaign.rally_cooldown <= 20
		and scene.get_node("%Rally").disabled
		and scene.get_node("%Rally").text.begins_with("Rally recovering — ready in %d battle round" % campaign.rally_cooldown),
		"rallied defense win leaves Rally recovering and disabled once secured")
	check(campaign.shield_wall_rounds == 0 and campaign.shield_wall_cooldown > 0 and campaign.shield_wall_cooldown <= 20
		and scene.get_node("%ShieldWall").disabled
		and scene.get_node("%ShieldWall").text.begins_with(
			"Shield Wall recovering — ready in %d battle round" % campaign.shield_wall_cooldown),
		"shielded defense win leaves Shield Wall recovering and disabled once secured")
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
	diagnostic_battle = battle
	diagnostic_expected_phase = expected_phase
	var same_active_battle := func() -> bool:
		return scene.campaign.battle == battle and scene.campaign.phase == expected_phase \
			and battle.result == Presentation.Combat.Result.ONGOING and scene.is_processing()
	if not same_active_battle.call():
		return native_gate_incomplete("expected active battle missing before minimize request")
	check(true, "native suspension test starts with expected active combat, not an idle checkpoint")
	watching_focus = false
	if manual or native_driver:
		var remaining: float = watchdog.time_left
		var consumed: float = 60.0 - remaining
		var wall_seconds: float = (watchdog_measured_usec + Time.get_ticks_usec() - watchdog_mark_usec) / 1000000.0
		check(absf(consumed - watchdog_engine_seconds) < 0.25 and consumed <= wall_seconds + 0.25,
			"watchdog consumption %.6f matches measured engine time %.6f (wall %.6f) seconds" % [
				consumed, watchdog_engine_seconds, wall_seconds])
		var human: bool = manual or human_minimize
		if human:
			# Exclude only human readiness, never replenish measured time already spent.
			watchdog_counting = false
			watchdog_measured_usec += Time.get_ticks_usec() - watchdog_mark_usec
			watchdog.time_left = INF
		if native_driver and not human_minimize:
			native_driver_request("minimize")
		else:
			if human_minimize:
				native_driver_request("await-minimize")
			root.title = "Campaign smoke: MINIMIZE THIS WINDOW NOW; automatic restore follows"
			print("ACTION: waiting for you — click the Godot title-bar minimize button when ready")
		while root.mode != Window.MODE_MINIMIZED:
			await process_frame
		native_diagnostic("minimized-observed")
		if human:
			check(watchdog.time_left == INF, "human readiness excluded from measured watchdog")
			watchdog.time_left = remaining
			watchdog_counting = true
			watchdog_mark_usec = Time.get_ticks_usec()
			# Focus-only reaches this gate before the first timer tick, so a saved 60.0 is legitimate;
			# the measured-elapsed check above plus equality here prove nothing was replenished.
			check(watchdog.time_left == remaining and remaining > 0.0 and remaining <= 60.0,
				"watchdog restores saved remainder, not a fresh 60 seconds")
			print("WATCHDOG: saved=%.6f restored=%.6f seconds" % [remaining, watchdog.time_left])
	else:
		root.mode = Window.MODE_MINIMIZED
	if not same_active_battle.call():
		return native_gate_incomplete("readiness outlasted the expected battle before observed minimization")
	var suspension_wait_start: int = Time.get_ticks_usec()
	# Native transitions use wall time, not the engine's smoothed frame delta.
	while Time.get_ticks_usec() - suspension_wait_start < 200000:
		await process_frame
	check(Time.get_ticks_usec() - suspension_wait_start >= 200000,
		"native suspension wait covers at least 200ms of monotonic time")
	native_diagnostic("suspension-check")
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
	var frozen_start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - frozen_start < 1200000:
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
	check(Time.get_ticks_usec() - frozen_start >= 1200000,
		"native frozen interval covers at least 1.2s of monotonic time")
	check(true, "native minimized interval freezes same active battle, rounds, accumulated time and gate")
	# The save stamp is wall-clock time, not campaign state: compare with the loaded stamp passed through.
	var on_disk := CampaignSave.new(fixture.path).load_campaign()
	var captured := CampaignState.capture(scene.campaign, scene.elapsed_usec, on_disk.get("saved_at", -1))
	check(scene.get_node("%SaveStatus").text == "Saved" and captured.outcome == CampaignState.Outcome.VALID
		and on_disk.get("saved_at", 0) > 0 and CampaignSave._state_of(on_disk) == captured.state,
		"native suspension autosaved the exact frozen campaign to the isolated file")
	if native_driver:
		native_driver_request("restore")
	else:
		root.mode = Window.MODE_WINDOWED
		root.grab_focus()
	if not await await_focus():
		return native_gate_incomplete("native restore did not regain focus")
	if not same_active_battle.call() or battle.rounds != rounds:
		return native_gate_incomplete("native restore changed active battle or added a catch-up round")
	native_diagnostic("restore-observed")
	if manual or human_minimize:
		# The stale minimize prompt must not invite a second, test-breaking click.
		root.title = "Campaign check — restored; hands off until results appear"
	check(true, "native restore retains same active battle; no catch-up round")
	watching_focus = true
	# Completed gameplay observations do not erase native failures: finish() exits nonzero.
	return true

func native_driver_request(action: String) -> void:
	print("NATIVE_DRIVER: %s hwnd=%d pid=%d" % [action,
		DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id()), OS.get_process_id()])
	if action != "complete":
		native_diagnostic(action + "-requested")

func native_diagnostic(stage: String) -> void:
	if not native_driver or diagnostic_battle == null:
		return
	print("NATIVE_DIAG: stage=%s ticks_usec=%d unix=%.6f hwnd=%d pid=%d mode=%d focus=%s suspended=%s focus_lost=%s application_paused=%s skip_resume_frame=%s processing=%s phase=%d expected_phase=%d battle_id=%d expected_battle_id=%d same_battle=%s result=%d expected_result=%d rounds=%d elapsed_usec=%d last_frame_usec=%d" % [
		stage, Time.get_ticks_usec(), Time.get_unix_time_from_system(),
		DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id()), OS.get_process_id(),
		root.mode, root.has_focus(), scene.suspended, scene.focus_lost, scene.application_paused,
		scene.skip_resume_frame, scene.is_processing(), scene.campaign.phase, diagnostic_expected_phase,
		scene.campaign.battle.get_instance_id(), diagnostic_battle.get_instance_id(),
		scene.campaign.battle == diagnostic_battle, scene.campaign.battle.result, diagnostic_battle.result,
		diagnostic_battle.rounds, scene.elapsed_usec, scene.last_frame_usec])

func native_gate_incomplete(reason: String) -> bool:
	native_diagnostic("incomplete")
	check(false, "native suspension gate incomplete: " + reason)
	print("SUMMARY: campaign: incomplete — rerun the full affected scenario; %d checks, %d failures" % [checks, failures])
	if not native_driver:
		root.mode = Window.MODE_WINDOWED
		root.grab_focus()
	return false

func click(button: Button) -> void:
	scene.get_node("Margin/Scroll").ensure_control_visible(button)
	# Let deferred scroll layout settle before checking or sampling the target.
	await process_frame
	await process_frame
	var visible_ok := not button.disabled and root.get_visible_rect().encloses(button.get_global_rect())
	if not visible_ok:
		var scroll: ScrollContainer = scene.get_node("Margin/Scroll")
		print("CLICK_DIAG: %s disabled=%s rect=%s visible=%s scroll=%d max=%d suspended=%s preview=%s" % [
			button.name, button.disabled, button.get_global_rect(), root.get_visible_rect(),
			scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value, scene.suspended, scene.dynasty_preview_open])
	check(visible_ok, "mouse target enabled and fully visible")
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
	var ready := button.has_focus() and not button.disabled and root.get_visible_rect().encloses(button.get_global_rect())
	if not ready:
		var scroll: ScrollContainer = scene.get_node("Margin/Scroll")
		print("KEY_DIAG: %s focus=%s disabled=%s rect=%s visible=%s scroll=%d max=%d suspended=%s preview=%s" % [
			button.name, button.has_focus(), button.disabled, button.get_global_rect(), root.get_visible_rect(),
			scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value, scene.suspended, scene.dynasty_preview_open])
	check(ready, "keyboard target focused, enabled and visible")
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

func cleanup_fixture() -> void:
	if scene != null:
		# Later close requests must not recreate the removed fixture.
		scene.saving_enabled = false
	if fixture != null and fixture.owned:
		var error := fixture.cleanup()
		print("CLEANUP: campaign save fixture %s" % ("removed" if error == OK else "NOT removed (%d)" % error))
		if error != OK:
			failures += 1

# Every early exit must remove the isolated fixture, not only the normal finish.
func quit_after_cleanup(code: int) -> void:
	cleanup_fixture()
	quit(code if failures == 0 else maxi(code, 1))

func _finalize() -> void:
	cleanup_fixture()

func end_run(code: int) -> void:
	cleanup_fixture()
	if code == 0 and failures > 0:
		code = 1
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