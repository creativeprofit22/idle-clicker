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

var checks: int = 0
var failures: int = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", title])

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
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
	if "--force-failure" in OS.get_cmdline_user_args():
		check(false, "forced runner failure")
	print("SUMMARY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func campaign_scene_new(script: GDScript = CampaignPresentation) -> CampaignPresentation:
	var scene: CampaignPresentation = CampaignScene.instantiate()
	if script != CampaignPresentation:
		scene.set_script(script)
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
	for name in ["FoundDynasty", "ConfirmDynasty", "CancelDynasty"]:
		scene.get_node("%" + name).pressed.emit()
	check(campaign_snapshot(campaign) == before and not scene.dynasty_preview_open,
		"Dynasty scene: premature emitted reset actions reject")
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
	check(campaign.can_found_dynasty() and defense.result == Combat.Result.VICTORY,
		"Dynasty scene: real earned conquest and defense enable reset")
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
		"same three troop types", "exactly 2× squad damage after level additions",
		"health, gold rewards and round frequency are unchanged", "only reset/bonus for this session",
		"Closing/recreating", "main-game saves are untouched"]:
		check(copy.contains(text), "Dynasty scene: preview discloses " + text)
	for name in ["GateUpgrade", "ShieldUpgrade", "FootUpgrade", "HorseUpgrade", "FarmBorder", "FarmArcher", "Frontier", "StartDefense", "FoundDynasty"]:
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
		and scene.get_node("%DynastyStatus").text == "Dynasty 2 · Inherited Drill: 2× squad damage",
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
	check(fresh.campaign.dynasty == 1 and not fresh.campaign.inherited_drill
		and fresh.campaign.battle.players[0].damage == 4 and not fresh.dynasty_preview_open,
		"Dynasty scene: concurrent fresh instance has no doctrine")
	fresh.free()
	dynasty_prepare(campaign)
	scene._refresh()
	scene.get_node("%StartDefense").pressed.emit()
	campaign_scene_finish(scene)
	check(scene.get_node("%CampaignStatus").text.contains("Slice complete — no further dynasty reset.")
		and scene.get_node("%FoundDynasty").disabled and not scene.is_processing(),
		"Dynasty scene: real successor completion is terminal with exact status")
	scene.free()

func test_campaign_scene_fresh() -> void:
	var scene := campaign_scene_new()
	check(scene.get_node("%Title").text == "Campaign prototype"
		and scene.get_node("%SessionNotice").visible
		and scene.get_node("%SessionNotice").text == "Session-only progress. Closing/recreating resets this campaign and discards its doctrine. Main-game saves are not loaded or changed.",
		"Campaign scene: permanent session-only notice and title")
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
			and scene.get_node("%CampaignStatus").text == "Campaign secured · Counterattack defeated"
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
	check(campaign.dynasty == 1 and not campaign.inherited_drill and not campaign.reset_used
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
	check(campaign.settle(defense) and campaign.gold == wallet and campaign.can_found_dynasty(),
		"Dynasty: only settled defense enables reset, no reward")
	# Each eligibility conjunct independently protects an otherwise secured model.
	for field in ["dynasty", "inherited_drill", "reset_used", "border_cleared", "archer_cleared",
		"stronghold_cleared", "_settled", "current_encounter"]:
		var original: Variant = campaign.get(field)
		campaign.set(field, 2 if field == "dynasty" else (0 if field == "current_encounter" else not original))
		dynasty_rejected(campaign, "guard " + field)
		campaign.set(field, original)
	var surviving_gate: int = defense.gate_health
	defense.gate_health = 0
	dynasty_rejected(campaign, "no surviving gate")
	defense.gate_health = surviving_gate
	var old_state := campaign_snapshot(campaign)
	var successor := campaign.found_dynasty()
	check(successor != null and campaign.dynasty == 2 and campaign.inherited_drill and campaign.reset_used,
		"Dynasty: one synchronous successor and consumed allowance")
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
	dynasty_rejected(campaign, "duplicate reset")
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
	var formula := Campaign.new()
	formula.inherited_drill = true
	formula.levels = [2, 2, 2]
	var upgraded := formula.restart_battle()
	var ordinary := Economy.new()
	ordinary.levels = [2, 2, 2]
	var normal := ordinary.restart_battle()
	for role in range(3):
		check(upgraded.players[role].damage == [12, 24, 18][role]
			and normal.players[role].damage == [6, 12, 9][role]
			and upgraded.players[role].max_health == normal.players[role].max_health,
			"Dynasty: level additions before isolated multiplier, unchanged health")
	check(upgraded.commander_damage == 18 and normal.commander_damage == 9,
		"Dynasty: commander derives upgraded snapshot")
	var fresh := Campaign.new()
	check(not fresh.inherited_drill and fresh.dynasty == 1 and not fresh.reset_used
		and fresh.restart_battle().players[0].damage == 4
		and Economy.new().restart_battle().players[0].damage == 4, "Dynasty: fresh model and Economy isolation")
	dynasty_prepare(campaign)
	campaign.start_defense()
	wallet = campaign.gold
	var final_defense := campaign_finish(campaign)
	check(final_defense.result == Combat.Result.VICTORY and campaign.phase == Campaign.Phase.CAMPAIGN_SECURED
		and campaign.gold == wallet and campaign.inherited_drill and campaign.dynasty == 2
		and final_defense.players[0].damage == 16, "Dynasty: successor secured, zero bonus, no stacking")
	dynasty_rejected(campaign, "second secured campaign")
	var terminal := campaign_snapshot(campaign)
	check(not campaign.settle(final_defense) and campaign.restart_battle() == null
		and not campaign.request_frontier() and not campaign.request_farm(0)
		and campaign_snapshot(campaign) == terminal, "Dynasty: successor checkpoint stays inert")
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
	# Isolate doctrine retention through a gate-destruction/recovery boundary.
	loss.dynasty = 2
	loss.inherited_drill = true
	loss.reset_used = true
	check(loss.request_frontier(), "Dynasty: recovery frontier queued")
	campaign_finish(loss)
	var retry := loss.start_defense()
	retry.players[0].health = 0
	retry.gate_health = 1
	campaign_finish(loss)
	check(retry.result == Combat.Result.DEFEAT and loss.inherited_drill and loss.reset_used
		and loss.dynasty == 2 and loss.mode == Campaign.Mode.FARM
		and loss.battle.players[0].damage == 8 and loss.battle.commander_damage == 12,
		"Dynasty: defeat and recovery preserve doctrine without stacking")
	dynasty_rejected(loss, "successor defensive recovery")

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
		campaign.dynasty, campaign.inherited_drill, campaign.reset_used]

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
