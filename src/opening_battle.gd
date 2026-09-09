extends Control

const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const Economy = preload("res://src/economy.gd")
const ProgressSave = preload("res://src/progress_save.gd")
const USEC_PER_SECOND: int = 1000000
const ROUND_USEC: int = roundi(Data.ROUND_SECONDS * USEC_PER_SECOND)

var economy := Economy.new()
# Tests inject null or an isolated store before adding this scene to the tree.
var progress_save: ProgressSave = ProgressSave.new()
var saving_enabled: bool = true
var battle: Combat
var elapsed_usec: int = 0
var suspended: bool = false
var skip_resume_frame: bool = false
var last_frame_usec: int = 0
var fortified_diagnostics: bool = false

func trace_fortified(event: String, update_usec: int = 0) -> void:
	if fortified_diagnostics:
		print("[FORTIFIED-DIAG] t_usec=%d event=%s focus=%s suspended=%s skip_resume=%s processing=%s last_frame_usec=%d update_usec=%d elapsed_usec=%d rounds=%d result=%d gold=%d" % [
			Time.get_ticks_usec(), event, get_window().has_focus(), suspended,
			skip_resume_frame, is_processing(), last_frame_usec, update_usec, elapsed_usec,
			battle.rounds if battle != null else -1, battle.result if battle != null else -1, economy.gold])

@onready var status_label: Label = %Status
@onready var round_label: Label = %Round
@onready var commander: Button = %Commander
@onready var restart: Button = %Restart
@onready var replay_timer: Timer = $ReplayTimer
@onready var gold_label: Label = %Gold
@onready var save_status: Label = %SaveStatus
@onready var upgrades: Array[Button] = [%ShieldUpgrade, %FootUpgrade, %HorseUpgrade]
@onready var health_labels: Array[Label] = [%ShieldHealth, %FootHealth, %HorseHealth, %EnemyHealth, %EnemyFootHealth]
@onready var health_bars: Array[ProgressBar] = [%ShieldBar, %FootBar, %HorseBar, %EnemyBar, %EnemyFootBar]

func _ready() -> void:
	commander.pressed.connect(_command)
	restart.pressed.connect(restart_battle)
	replay_timer.timeout.connect(restart_battle)
	for role in range(upgrades.size()):
		upgrades[role].pressed.connect(_purchase.bind(role))
	%BorderSelect.pressed.connect(_select_encounter.bind(Data.Encounter.BORDER_SKIRMISH))
	%ArcherSelect.pressed.connect(_select_encounter.bind(Data.Encounter.ARCHER_POSITION))
	%FortifiedSelect.pressed.connect(_select_encounter.bind(Data.Encounter.FORTIFIED_POSITION))
	_load_progress()
	restart_battle()

func _load_progress() -> void:
	if progress_save == null:
		saving_enabled = false
		save_status.text = "Saving disabled for isolated test"
		return
	var loaded := progress_save.load_progress()
	saving_enabled = loaded.outcome in [ProgressSave.Outcome.MISSING, ProgressSave.Outcome.LOADED]
	if loaded.outcome == ProgressSave.Outcome.LOADED:
		economy.gold = loaded.gold
		economy.levels.assign(loaded.levels)
	if saving_enabled:
		save_status.text = "Backup recovered · Autosave after victories and purchases" if loaded.get("recovered", false) else "Autosave after victories and purchases"
	else:
		_show_preservation_status()

func _show_preservation_status() -> void:
	saving_enabled = false
	var reason: String = "unreadable"
	if progress_save.get_preservation_outcome() == ProgressSave.Outcome.CORRUPT:
		reason = "damaged"
	elif progress_save.get_preservation_outcome() == ProgressSave.Outcome.UNSUPPORTED:
		reason = "from an unsupported version"
	save_status.text = "Saving disabled: save %s, preserved. Close and move progress.json (and .bak) aside, or use a compatible app." % reason

func _save_progress() -> void:
	if saving_enabled:
		var error := progress_save.save_progress(economy.gold, economy.levels)
		if progress_save.get_preservation_outcome() not in [ProgressSave.Outcome.MISSING, ProgressSave.Outcome.LOADED]:
			_show_preservation_status()
			return
		save_status.text = "Progress saved · Autosave on" if error == OK else "Progress not saved · Retry on next victory or purchase; unsaved changes lost on close"

func _select_encounter(encounter: int) -> void:
	if suspended or encounter == economy.current_encounter or not economy.is_encounter_unlocked(encounter):
		return
	_start_battle(encounter)

func restart_battle() -> void:
	_start_battle()

func _start_battle(encounter: int = -1) -> void:
	var accepted := economy.restart_battle(encounter)
	if accepted == null:
		return
	replay_timer.stop()
	battle = accepted
	elapsed_usec = 0
	last_frame_usec = Time.get_ticks_usec()
	_refresh()
	set_process(true)

func _process(_delta: float) -> void:
	advance_foreground(Time.get_ticks_usec())

func _input(_event: InputEvent) -> void:
	# Settle before GUI routing: a queued strike may still have the button disabled.
	# Button.pressed remains the only commander input path.
	advance_foreground(Time.get_ticks_usec())

func advance_foreground(now: int) -> void:
	var usec: int = now - last_frame_usec
	last_frame_usec = now
	advance_usec(usec)

func advance_time(seconds: float) -> void:
	# Test input is quantized once to the nearest microsecond, never accumulated as floats.
	advance_usec(roundi(seconds * USEC_PER_SECOND))

func advance_usec(usec: int) -> void:
	if suspended:
		return
	if skip_resume_frame:
		trace_fortified("resumed-update-skipped", usec)
		skip_resume_frame = false
		return
	if battle.result != Combat.Result.ONGOING:
		return
	elapsed_usec += usec
	while elapsed_usec >= ROUND_USEC:
		elapsed_usec -= ROUND_USEC
		battle.step_round()
		if economy.settle(battle):
			if battle.result == Combat.Result.VICTORY:
				_save_progress()
			replay_timer.start()
		_refresh()
		if battle.result != Combat.Result.ONGOING:
			elapsed_usec = 0
			set_process(false)
			break

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		suspended = true
		if is_node_ready():
			replay_timer.paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		suspended = false
		skip_resume_frame = true
		if is_node_ready():
			replay_timer.paused = false
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		trace_fortified("notification-%d" % what)

func _command() -> void:
	if not suspended and battle.queue_commander():
		_refresh()

func _purchase(role: int) -> void:
	if not suspended:
		if economy.purchase(role):
			_save_progress()
		_refresh()

func _refresh() -> void:
	var selected: int = economy.current_encounter
	var reward: int = economy.encounter_reward(selected)
	match selected:
		Data.Encounter.BORDER_SKIRMISH: %Title.text = "BORDER SKIRMISH"
		Data.Encounter.ARCHER_POSITION: %Title.text = "ARCHER POSITION"
		Data.Encounter.FORTIFIED_POSITION: %Title.text = "FORTIFIED POSITION"
	%BorderSelect.disabled = selected == Data.Encounter.BORDER_SKIRMISH
	%ArcherSelect.disabled = selected == Data.Encounter.ARCHER_POSITION or not economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION)
	%FortifiedSelect.disabled = selected == Data.Encounter.FORTIFIED_POSITION or not economy.is_encounter_unlocked(Data.Encounter.FORTIFIED_POSITION)
	%UnlockHint.visible = not economy.is_encounter_unlocked(Data.Encounter.ARCHER_POSITION)
	%FortifiedUnlockHint.visible = not economy.is_encounter_unlocked(Data.Encounter.FORTIFIED_POSITION)
	%EnemyFootRow.visible = selected in [Data.Encounter.ARCHER_POSITION, Data.Encounter.FORTIFIED_POSITION]
	gold_label.text = "Gold: %d · Victory +%d · Auto replay" % [economy.gold, reward]
	var titles: Array[String] = ["Shield infantry", "Foot archers", "Horse archers"]
	for role in range(upgrades.size()):
		var cost: int = economy.purchase_cost(role)
		upgrades[role].text = "%s Lv.%d · %s" % [titles[role], economy.levels[role],
			"MAX" if cost == 0 else "Upgrade %d gold" % cost]
		upgrades[role].disabled = cost == 0 or economy.gold < cost
	var squads: Array[Data.Squad] = battle.players.duplicate()
	# simplification: two authored enemy rows; extend explicitly for another roster.
	squads.append_array(battle.enemies)
	for i in range(squads.size()):
		var squad: Data.Squad = squads[i]
		health_labels[i].text = "%s  |  HP %d / %d  |  Damage %d" % [
			squad.title, squad.health, squad.max_health, squad.damage]
		health_bars[i].max_value = squad.max_health
		health_bars[i].value = squad.health
	round_label.text = "Round %d  /  One attack each second" % battle.rounds
	commander.disabled = battle.result != Combat.Result.ONGOING or battle.commander_queued
	commander.text = "Strike queued (+%d)" % battle.commander_damage if battle.commander_queued else "Commander strike (+%d)" % battle.commander_damage
	match battle.result:
		Combat.Result.VICTORY:
			status_label.text = "Victory +%d gold — replay in 1 second" % reward
		Combat.Result.DEFEAT:
			status_label.text = "Defeat — no reward; replay in 1 second"
		_:
			status_label.text = "Commander queued for next round" if battle.commander_queued else "Battle underway — your army attacks automatically"
