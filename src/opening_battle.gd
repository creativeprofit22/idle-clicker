extends Control

const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const USEC_PER_SECOND: int = 1000000
const ROUND_USEC: int = roundi(Data.ROUND_SECONDS * USEC_PER_SECOND)

var battle: Combat
var elapsed_usec: int = 0
var suspended: bool = false
var skip_resume_frame: bool = false
var last_frame_usec: int = 0

@onready var status_label: Label = %Status
@onready var round_label: Label = %Round
@onready var commander: Button = %Commander
@onready var restart: Button = %Restart
@onready var health_labels: Array[Label] = [%ShieldHealth, %FootHealth, %HorseHealth, %EnemyHealth]
@onready var health_bars: Array[ProgressBar] = [%ShieldBar, %FootBar, %HorseBar, %EnemyBar]

func _ready() -> void:
	commander.pressed.connect(_command)
	restart.pressed.connect(restart_battle)
	restart_battle()

func restart_battle() -> void:
	battle = Combat.new()
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
		skip_resume_frame = false
		return
	if battle.result != Combat.Result.ONGOING:
		return
	elapsed_usec += usec
	while elapsed_usec >= ROUND_USEC:
		elapsed_usec -= ROUND_USEC
		battle.step_round()
		_refresh()
		if battle.result != Combat.Result.ONGOING:
			elapsed_usec = 0
			set_process(false)
			break

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		suspended = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		suspended = false
		skip_resume_frame = true

func _command() -> void:
	if not suspended and battle.queue_commander():
		_refresh()

func _refresh() -> void:
	var squads: Array[Data.Squad] = battle.players.duplicate()
	# simplification: opening-only UI; add squad rows before presenting later encounters.
	assert(battle.enemies.size() == 1, "Opening scene supports only Border skirmish")
	squads.append(battle.enemies[0])
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
			status_label.text = "Victory — border secured"
		Combat.Result.DEFEAT:
			status_label.text = "Defeat — restart to try again"
		_:
			status_label.text = "Commander queued for next round" if battle.commander_queued else "Battle underway — your army attacks automatically"
