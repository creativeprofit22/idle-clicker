extends SceneTree

const Combat = preload("res://src/combat.gd")
const Economy = preload("res://src/economy.gd")
const Data = preload("res://src/encounter_data.gd")
const BattleScene = preload("res://scenes/opening_battle.tscn")
const Presentation = preload("res://src/opening_battle.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const ProgressFixture = preload("res://tests/progress_fixture.gd")

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
	test_conquest_targeting()
	test_archer_position()
	test_adapter()
	test_timing_partitions()
	test_foreground_clock()
	test_economy()
	test_progress_format()
	test_progress_failures()
	test_progress_adapter()
	if "--force-failure" in OS.get_cmdline_user_args():
		check(false, "forced runner failure")
	print("SUMMARY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

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
