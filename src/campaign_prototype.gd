extends Control

const Campaign = preload("res://src/campaign.gd")
const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const USEC_PER_SECOND: int = 1000000
const ROUND_USEC: int = roundi(Data.ROUND_SECONDS * USEC_PER_SECOND)
const ENCOUNTER_TITLES: Dictionary = {
	Data.Encounter.BORDER_SKIRMISH: "Border Skirmish",
	Data.Encounter.ARCHER_POSITION: "Archer Position",
	Data.Encounter.STRONGHOLD: "Stronghold",
}

var campaign := Campaign.new()
var elapsed_usec: int = 0
var last_frame_usec: int = 0
var suspended: bool = false
var skip_resume_frame: bool = false

@onready var upgrades: Array[Button] = [%ShieldUpgrade, %FootUpgrade, %HorseUpgrade]

func _ready() -> void:
	%FarmBorder.pressed.connect(_request_farm.bind(Data.Encounter.BORDER_SKIRMISH))
	%FarmArcher.pressed.connect(_request_farm.bind(Data.Encounter.ARCHER_POSITION))
	%Frontier.pressed.connect(_request_frontier)
	for role in range(upgrades.size()):
		upgrades[role].pressed.connect(_purchase.bind(role))
	campaign.restart_battle()
	last_frame_usec = Time.get_ticks_usec()
	_refresh()

func _process(_delta: float) -> void:
	advance_foreground(Time.get_ticks_usec())

func _input(_event: InputEvent) -> void:
	# Settle elapsed rounds before GUI activation, including currently disabled buttons.
	advance_foreground(Time.get_ticks_usec())

func advance_foreground(now: int) -> void:
	var usec: int = now - last_frame_usec
	last_frame_usec = now
	advance_usec(usec)

func advance_time(seconds: float) -> void:
	advance_usec(roundi(seconds * USEC_PER_SECOND))

func advance_usec(usec: int) -> void:
	if suspended:
		return
	if skip_resume_frame:
		skip_resume_frame = false
		return
	if campaign.phase != Campaign.Phase.RUNNING:
		return
	elapsed_usec += usec
	while elapsed_usec >= ROUND_USEC:
		elapsed_usec -= ROUND_USEC
		var completed := campaign.battle
		var encounter: int = campaign.current_encounter
		var gold_before: int = campaign.gold
		completed.step_round()
		if campaign.settle(completed):
			%LastResult.text = "%s: %s · +%d gold" % [ENCOUNTER_TITLES[encounter],
				"Victory" if completed.result == Combat.Result.VICTORY else "Defeat",
				campaign.gold - gold_before]
			# Campaign already routed: never restart or tick its fresh successor here.
			elapsed_usec = 0
			set_process(campaign.phase == Campaign.Phase.RUNNING)
			_refresh()
			break
		_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		suspended = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		suspended = false
		skip_resume_frame = true
	else:
		return
	if is_node_ready():
		_refresh()

func _request_farm(encounter: int) -> void:
	if suspended:
		return
	var was_checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	if campaign.request_farm(encounter) and was_checkpoint:
		elapsed_usec = 0
		last_frame_usec = Time.get_ticks_usec()
		set_process(true)
	_refresh()

func _request_frontier() -> void:
	if suspended:
		return
	campaign.request_frontier()
	_refresh()

func _purchase(role: int) -> void:
	if suspended:
		return
	campaign.purchase(role)
	_refresh()

func _refresh() -> void:
	var checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	%CampaignStatus.text = "%s · %s · %s" % [ENCOUNTER_TITLES[campaign.current_encounter],
		"Farm" if campaign.mode == Campaign.Mode.FARM else "Advance",
		"Conquest cleared — prototype ends here; ordinary farming remains available" if checkpoint else "Running"]
	if suspended:
		%CampaignStatus.text += " · Paused"
	match campaign.pending_navigation:
		Campaign.Navigation.FARM:
			%PendingNavigation.text = "Farm %s after this battle" % ENCOUNTER_TITLES[campaign.pending_farm]
		Campaign.Navigation.FRONTIER:
			%PendingNavigation.text = "Return to cleared checkpoint after this battle" if campaign.stronghold_cleared else "Retry frontier after this battle"
		_:
			%PendingNavigation.text = "No queued navigation"
	%Gold.text = "Gold: %d" % campaign.gold
	%Round.text = "Round: %d" % campaign.battle.rounds
	var labels: Array[Label] = [%Army, %Enemies]
	var armies: Array = [campaign.battle.players, campaign.battle.enemies]
	for i in range(armies.size()):
		var rows: PackedStringArray = ["Army" if i == 0 else "Enemies"]
		for squad: Data.Squad in armies[i]:
			rows.append("%s | HP %d / %d | Damage %d" % [
				squad.title, squad.health, squad.max_health, squad.damage])
		labels[i].text = "\n".join(rows)
	%FarmBorder.disabled = suspended or not campaign.border_cleared
	%FarmArcher.disabled = suspended or not campaign.archer_cleared
	# At the cleared checkpoint frontier is a controller no-op; farming remains available.
	%Frontier.disabled = suspended or checkpoint or campaign.mode != Campaign.Mode.FARM
	%Frontier.text = "Return to cleared checkpoint after battle" if campaign.stronghold_cleared else "Retry frontier after battle"
	var titles: Array[String] = ["Shield infantry", "Foot archers", "Horse archers"]
	for role in range(upgrades.size()):
		var cost: int = campaign.purchase_cost(role)
		upgrades[role].text = "%s Lv.%d · %s" % [titles[role], campaign.levels[role],
			"MAX" if cost == 0 else "Upgrade %d gold" % cost]
		upgrades[role].disabled = suspended or cost <= 0 or campaign.gold < cost
