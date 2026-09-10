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
	Data.Encounter.COUNTERATTACK: "Counterattack",
}

var campaign := Campaign.new()
var elapsed_usec: int = 0
var last_frame_usec: int = 0
var suspended: bool = false
var focus_lost: bool = false
var application_paused: bool = false
var skip_resume_frame: bool = false
var dynasty_preview_open: bool = false

@onready var upgrades: Array[Button] = [%ShieldUpgrade, %FootUpgrade, %HorseUpgrade]

func _ready() -> void:
	%FarmBorder.pressed.connect(_request_farm.bind(Data.Encounter.BORDER_SKIRMISH))
	%FarmArcher.pressed.connect(_request_farm.bind(Data.Encounter.ARCHER_POSITION))
	%Frontier.pressed.connect(_request_frontier)
	%StartDefense.pressed.connect(_start_defense)
	%GateUpgrade.pressed.connect(_purchase_gate)
	%FoundDynasty.pressed.connect(_open_dynasty_preview)
	%CancelDynasty.pressed.connect(_cancel_dynasty_preview)
	%ConfirmDynasty.pressed.connect(_confirm_dynasty)
	for role in range(upgrades.size()):
		upgrades[role].pressed.connect(_purchase.bind(role))
	campaign.restart_battle()
	last_frame_usec = Time.get_ticks_usec()
	# Check native mode even at idle checkpoints where this node stops processing.
	get_tree().process_frame.connect(_sync_suspension)
	_sync_suspension()
	_refresh()

func _process(_delta: float) -> void:
	advance_foreground(Time.get_ticks_usec())

func _input(event: InputEvent) -> void:
	# Settle elapsed rounds before GUI activation, including currently disabled buttons.
	advance_foreground(Time.get_ticks_usec())
	if dynasty_preview_open and event.is_action_pressed("ui_cancel"):
		_cancel_dynasty_preview()
		get_viewport().set_input_as_handled()

func advance_foreground(now: int) -> void:
	var usec: int = now - last_frame_usec
	last_frame_usec = now
	advance_usec(usec)

func advance_time(seconds: float) -> void:
	advance_usec(roundi(seconds * USEC_PER_SECOND))

func advance_usec(usec: int) -> void:
	_sync_suspension()
	if suspended:
		return
	if skip_resume_frame:
		skip_resume_frame = false
		return
	if campaign.phase not in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING]:
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
			if completed.is_defense and completed.result == Combat.Result.DEFEAT:
				%LastResult.text += " · %s. Farm to recover, return to the checkpoint after battle, then Start Defense to retry." % (
					"Gate destroyed" if completed.defeat_reason == Combat.DefeatReason.GATE_DESTROYED else "Timeout")
			# Campaign already routed: never restart or tick its fresh successor here.
			elapsed_usec = 0
			set_process(campaign.phase in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING])
			_refresh()
			break
		_refresh()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			application_paused = true
		NOTIFICATION_APPLICATION_RESUMED:
			application_paused = false
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			focus_lost = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			focus_lost = false
		_:
			return
	_sync_suspension()

func _is_window_minimized() -> bool:
	# Headless has no native window; its dummy backend always returns MINIMIZED.
	return DisplayServer.get_name() != "headless" and is_inside_tree() \
		and get_window().mode == Window.MODE_MINIMIZED

func _sync_suspension() -> void:
	var should_suspend: bool = focus_lost or application_paused or _is_window_minimized()
	if suspended == should_suspend:
		return
	suspended = should_suspend
	if not suspended:
		skip_resume_frame = true
	if is_node_ready():
		_refresh()

func _open_dynasty_preview() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open or not campaign.can_found_dynasty():
		return
	dynasty_preview_open = true
	_refresh()
	%CancelDynasty.grab_focus()

func _cancel_dynasty_preview() -> void:
	_sync_suspension()
	if suspended or not dynasty_preview_open:
		return
	dynasty_preview_open = false
	_refresh()
	%FoundDynasty.grab_focus()

func _confirm_dynasty() -> void:
	_sync_suspension()
	if suspended or not dynasty_preview_open or not campaign.can_found_dynasty():
		return
	if campaign.found_dynasty() == null:
		return
	dynasty_preview_open = false
	elapsed_usec = 0
	last_frame_usec = Time.get_ticks_usec()
	%LastResult.text = "No completed battle"
	set_process(true)
	_refresh()

func _request_farm(encounter: int) -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	var was_checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	if campaign.request_farm(encounter) and was_checkpoint:
		elapsed_usec = 0
		last_frame_usec = Time.get_ticks_usec()
		set_process(true)
	_refresh()

func _request_frontier() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	campaign.request_frontier()
	_refresh()

func _start_defense() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open or campaign.start_defense() == null:
		return
	elapsed_usec = 0
	last_frame_usec = Time.get_ticks_usec()
	set_process(true)
	_refresh()

func _purchase_gate() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	campaign.purchase_gate()
	_refresh()

func _purchase(role: int) -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	campaign.purchase(role)
	_refresh()

func _refresh() -> void:
	var blocked: bool = suspended or dynasty_preview_open
	%DynastyStatus.text = "Dynasty %d · %s" % [campaign.dynasty,
		"Inherited Drill: 2× squad damage" if campaign.inherited_drill else "No inherited doctrine"]
	%DynastyPreview.visible = dynasty_preview_open
	%FoundDynasty.disabled = blocked or not campaign.can_found_dynasty()
	%CancelDynasty.disabled = suspended
	%ConfirmDynasty.disabled = suspended or not dynasty_preview_open or not campaign.can_found_dynasty()
	%DynastyLosses.text = ("Lose all current gold: %d gold. Shield infantry Lv.%d, Foot archers Lv.%d, Horse archers Lv.%d and Gate Lv.%d all return to level 1.\n"
		+ "Lose all conquered territory and security; restart Border Skirmish in Advance mode with fresh full-health troops.\n"
		+ "Clear battle progress, pending commands, farming/navigation choices and fractional round time.\n"
		+ "Keep access to the same three troop types. Gain Inherited Drill: exactly 2× squad damage after level additions; health, gold rewards and round frequency are unchanged.\n"
		+ "This is the only reset/bonus for this session. Closing/recreating the campaign discards the doctrine too; main-game saves are untouched.") % [
		campaign.gold, campaign.levels[0], campaign.levels[1], campaign.levels[2], campaign.gate_level]
	var checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	var defending: bool = campaign.phase == Campaign.Phase.DEFENDING
	var secured: bool = campaign.phase == Campaign.Phase.CAMPAIGN_SECURED
	match campaign.phase:
		Campaign.Phase.RUNNING:
			%CampaignStatus.text = "%s · %s · Running" % [ENCOUNTER_TITLES[campaign.current_encounter],
				"Farm" if campaign.mode == Campaign.Mode.FARM else "Advance"]
		Campaign.Phase.CONQUEST_CLEARED:
			%CampaignStatus.text = "Conquest cleared — prepare upgrades, then Start Defense; ordinary farming remains available"
		Campaign.Phase.DEFENDING:
			%CampaignStatus.text = "Counterattack · Defending the Stronghold"
		Campaign.Phase.CAMPAIGN_SECURED:
			%CampaignStatus.text = "Campaign secured · Counterattack defeated"
			if campaign.reset_used:
				%CampaignStatus.text += " · Slice complete — no further dynasty reset."
	if suspended:
		%CampaignStatus.text += " · Paused"
	match campaign.pending_navigation:
		Campaign.Navigation.FARM:
			%PendingNavigation.text = ("Recovery farm %s if defense fails; victory secures the campaign" if defending else "Farm %s after this battle") % ENCOUNTER_TITLES[campaign.pending_farm]
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
	%GateHealth.visible = campaign.battle.is_defense
	%GateHealth.text = "Gate HP: %d / %d" % [campaign.battle.gate_health, campaign.battle.gate_max_health]
	var gate_cost: int = campaign.gate_purchase_cost()
	%GateUpgrade.text = "Gate Lv.%d · %s" % [campaign.gate_level,
		"MAX" if gate_cost == 0 else "Upgrade %d gold" % gate_cost]
	%GateUpgrade.disabled = blocked or gate_cost <= 0 or campaign.gold < gate_cost
	%StartDefense.disabled = blocked or not checkpoint or not campaign.stronghold_cleared
	%FarmBorder.disabled = blocked or secured or not campaign.border_cleared
	%FarmArcher.disabled = blocked or secured or not campaign.archer_cleared
	# At the cleared checkpoint frontier is a controller no-op; farming remains available.
	%Frontier.disabled = blocked or checkpoint or defending or secured or campaign.mode != Campaign.Mode.FARM
	%Frontier.text = "Return to cleared checkpoint after battle" if campaign.stronghold_cleared else "Retry frontier after battle"
	var titles: Array[String] = ["Shield infantry", "Foot archers", "Horse archers"]
	for role in range(upgrades.size()):
		var cost: int = campaign.purchase_cost(role)
		upgrades[role].text = "%s Lv.%d · %s" % [titles[role], campaign.levels[role],
			"MAX" if cost == 0 else "Upgrade %d gold" % cost]
		upgrades[role].disabled = blocked or cost <= 0 or campaign.gold < cost
