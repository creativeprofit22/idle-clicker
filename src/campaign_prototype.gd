extends Control

const Campaign = preload("res://src/campaign.gd")
const CampaignSave = preload("res://src/campaign_save.gd")
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
# Tests set null (saving disabled) or a fixture store before add_child.
var campaign_save: CampaignSave = CampaignSave.new()
var saving_enabled: bool = false
var elapsed_usec: int = 0
var last_frame_usec: int = 0
var suspended: bool = false
var focus_lost: bool = false
var application_paused: bool = false
var skip_resume_frame: bool = false
var dynasty_preview_open: bool = false
# Threat chosen in the open preview; resets to the safe 0 each time the preview opens.
var preview_threat: int = 0
# Away reward not yet committed; added only inside a save so gold and stamp land together.
var pending_away_reward: int = 0
var pending_away_seconds: int = 0
const AWAY_WAIT_TEXT: String = "Away reward waits for a successful save"
const RESUMED_TEXT: String = "Resumed saved campaign"
const RESTORED_TEXT: String = "Restored from backup"
# Defense-loss cause and upgrade hint (text only; nothing is bought automatically).
const LOSS_RESULT_TEXT: Dictionary = {
	Combat.DefeatReason.GATE_DESTROYED: "The gate broke. Upgrade the Gate or your Shield infantry to hold longer.",
	Combat.DefeatReason.TIMEOUT: "Time ran out at round 60. Level up your troops or the Archer Platform for more damage to finish sooner.",
}
const LOSS_STATUS_TEXT: Dictionary = {
	Combat.DefeatReason.GATE_DESTROYED: "Last defense: the gate broke — upgrade Gate or Shield",
	Combat.DefeatReason.TIMEOUT: "Last defense: time ran out at round 60 — level up troop or platform damage",
}

@onready var upgrades: Array[Button] = [%ShieldUpgrade, %FootUpgrade, %HorseUpgrade]

func _ready() -> void:
	%FarmBorder.pressed.connect(_request_farm.bind(Data.Encounter.BORDER_SKIRMISH))
	%FarmArcher.pressed.connect(_request_farm.bind(Data.Encounter.ARCHER_POSITION))
	%Frontier.pressed.connect(_request_frontier)
	%StartDefense.pressed.connect(_start_defense)
	%Rally.pressed.connect(_rally)
	%ShieldWall.pressed.connect(_shield_wall)
	%GateUpgrade.pressed.connect(_purchase_gate)
	%ArcherPlatform.pressed.connect(_purchase_platform)
	%TrainDrill.pressed.connect(_train_drill)
	%VeteranCadre.pressed.connect(_buy_veteran_cadre)
	%FoundDynasty.pressed.connect(_open_dynasty_preview)
	%CancelDynasty.pressed.connect(_cancel_dynasty_preview)
	%ConfirmDynasty.pressed.connect(_confirm_dynasty)
	%ThreatDown.pressed.connect(_change_threat.bind(-1))
	%ThreatUp.pressed.connect(_change_threat.bind(1))
	for role in range(upgrades.size()):
		upgrades[role].pressed.connect(_purchase.bind(role))
	_load_campaign()
	last_frame_usec = Time.get_ticks_usec()
	# Check native mode even at idle checkpoints where this node stops processing.
	get_tree().process_frame.connect(_sync_suspension)
	_sync_suspension()
	_refresh()

# Contract D1/D11: exact resume of a valid save; anything unusable starts a fresh session.
func _load_campaign() -> void:
	if campaign_save == null:
		saving_enabled = false
		campaign.restart_battle()
		%SaveStatus.text = "Saving disabled for isolated test"
		return
	var loaded := campaign_save.load_campaign()
	match loaded.outcome:
		CampaignSave.Outcome.LOADED:
			campaign = loaded.campaign
			elapsed_usec = loaded.round_progress_usec
			# No absence progress: the first frame after load is excluded from timing.
			skip_resume_frame = true
			%LastResult.text = RESUMED_TEXT
			set_process(campaign.phase in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING])
			saving_enabled = true
			%SaveStatus.text = RESTORED_TEXT if loaded.get("recovered", false) else "Autosave on"
			_grant_away_reward(loaded.saved_at)
		CampaignSave.Outcome.MISSING:
			campaign.restart_battle()
			saving_enabled = true
			%SaveStatus.text = "Autosave on"
		_:
			campaign.restart_battle()
			_show_preservation_status()

func _show_preservation_status() -> void:
	saving_enabled = false
	var reason: String = "unreadable"
	match campaign_save.get_preservation_outcome():
		CampaignSave.Outcome.CORRUPT:
			reason = "damaged"
		CampaignSave.Outcome.UNSUPPORTED:
			reason = "from an unsupported version"
	%SaveStatus.text = "Saving disabled: campaign save %s, preserved. This session will not be kept." % reason
	if pending_away_reward > 0:
		# No save can commit this session, so the reward can never be kept.
		pending_away_reward = 0
		pending_away_seconds = 0
		%LastResult.text = "Away reward cannot be kept this session"

# Closed-app reward, across launches only: gold from secured territory, no simulated combat.
# The grant is kept only once a save commits it with a new stamp, so it can never pay twice.
# If that save fails but saving stays enabled, the next committed save carries it.
func _grant_away_reward(saved_at: int) -> void:
	var away: int = campaign_save._now() - saved_at if saved_at > 0 else 0
	var reward: int = campaign.away_reward(away)
	if reward <= 0:
		return
	pending_away_reward = reward
	pending_away_seconds = away
	# Contract: a backup restore must stay visible even when the grant's save commits.
	var restored: bool = %SaveStatus.text == RESTORED_TEXT
	if _save_campaign() and restored:
		%SaveStatus.text = RESTORED_TEXT + " · Saved"
	if pending_away_reward > 0:
		%LastResult.text = AWAY_WAIT_TEXT

static func _away_text(seconds: int) -> String:
	@warning_ignore("integer_division")
	var minutes: int = seconds / 60
	if minutes < 60:
		return "%dm" % minutes
	@warning_ignore("integer_division")
	return "%dh %dm" % [minutes / 60, minutes % 60]

# Contract D6/D7: the in-memory transition is already applied; "Saved" only after commit.
# Returns true only when the snapshot committed.
func _save_campaign() -> bool:
	if not saving_enabled:
		return false
	# A pending away reward rides in this snapshot so it commits atomically with the new stamp.
	var pending: int = pending_away_reward
	campaign.gold += pending
	var error := campaign_save.save_campaign(campaign, elapsed_usec)
	if campaign_save.get_preservation_outcome() not in [CampaignSave.Outcome.MISSING, CampaignSave.Outcome.LOADED]:
		campaign.gold -= pending
		_show_preservation_status()
		return false
	if error != OK:
		campaign.gold -= pending
	elif pending > 0:
		pending_away_reward = 0
		@warning_ignore("integer_division")
		var line: String = "Away %s · +%d gold from secured territory (cap %dh)" % [
			_away_text(pending_away_seconds), pending, Campaign.AWAY_CAP_SECONDS / 3600]
		pending_away_seconds = 0
		# Keep any battle result shown since launch; replace only the launch/waiting lines.
		var last: Label = %LastResult
		last.text = line if last.text in [AWAY_WAIT_TEXT, RESUMED_TEXT] else last.text + " · " + line
	%SaveStatus.text = "Saved" if error == OK else "Progress not saved — will retry"
	return error == OK

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
		campaign.resolve_round()
		if campaign.settle(completed):
			%LastResult.text = "%s: %s · +%d gold" % [ENCOUNTER_TITLES[encounter],
				"Victory" if completed.result == Combat.Result.VICTORY else "Defeat",
				campaign.gold - gold_before]
			if completed.is_defense and completed.result == Combat.Result.DEFEAT:
				%LastResult.text += " · %s Farm to recover, return to the checkpoint after battle, then Start Defense to retry." % (
					LOSS_RESULT_TEXT[campaign.last_defense_loss])
			# Campaign already routed: never restart or tick its fresh successor here.
			elapsed_usec = 0
			# Reward, clearance and routing are one write (D6/D8).
			_save_campaign()
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
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Best-effort save of mid-round progress before the app quits.
			_save_campaign()
			return
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
	else:
		# Best-effort save on focus loss, pause or minimize (D6).
		_save_campaign()
	if is_node_ready():
		_refresh()

func _open_dynasty_preview() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open or not campaign.can_found_dynasty():
		return
	dynasty_preview_open = true
	preview_threat = 0
	_refresh()
	%CancelDynasty.grab_focus()

func _cancel_dynasty_preview() -> void:
	_sync_suspension()
	if suspended or not dynasty_preview_open:
		return
	dynasty_preview_open = false
	_refresh()
	%FoundDynasty.grab_focus()

# Preview-only choice: nothing changes or saves until Confirm.
func _change_threat(step: int) -> void:
	_sync_suspension()
	if suspended or not dynasty_preview_open:
		return
	preview_threat = clampi(preview_threat + step, 0, campaign.max_selectable_threat())
	_refresh()

func _confirm_dynasty() -> void:
	_sync_suspension()
	if suspended or not dynasty_preview_open or not campaign.can_found_dynasty():
		return
	if campaign.found_dynasty(preview_threat) == null:
		return
	dynasty_preview_open = false
	elapsed_usec = 0
	last_frame_usec = Time.get_ticks_usec()
	%LastResult.text = "No completed battle"
	set_process(true)
	_save_campaign()
	_refresh()

func _request_farm(encounter: int) -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	var was_checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	if campaign.request_farm(encounter):
		if was_checkpoint:
			elapsed_usec = 0
			last_frame_usec = Time.get_ticks_usec()
			set_process(true)
		_save_campaign()
	_refresh()

func _request_frontier() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.request_frontier():
		_save_campaign()
	_refresh()

func _start_defense() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open or campaign.start_defense() == null:
		return
	elapsed_usec = 0
	last_frame_usec = Time.get_ticks_usec()
	set_process(true)
	_save_campaign()
	_refresh()

# Takes effect at the next round boundary; never moves focus.
func _rally() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.rally():
		_save_campaign()
	_refresh()

# Like Rally: takes effect at the next round boundary; never moves focus.
func _shield_wall() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.shield_wall():
		_save_campaign()
	_refresh()

func _purchase_gate() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.purchase_gate():
		_save_campaign()
	_refresh()

# Like the gate, the new level is locked in at the next Start Defense; the active assault is unchanged.
func _purchase_platform() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.purchase_platform():
		_save_campaign()
	_refresh()

# Legacy purchase; like troop upgrades it applies from the next created battle (D2/D6).
func _train_drill() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.train_drill():
		_save_campaign()
	_refresh()

# Permanent Legacy purchase; the level-2 start applies from the next founded dynasty.
func _buy_veteran_cadre() -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.buy_veteran_cadre():
		_save_campaign()
	_refresh()

func _purchase(role: int) -> void:
	_sync_suspension()
	if suspended or dynasty_preview_open:
		return
	if campaign.purchase(role):
		_save_campaign()
	_refresh()

func _refresh() -> void:
	var blocked: bool = suspended or dynasty_preview_open
	var secured: bool = campaign.phase == Campaign.Phase.CAMPAIGN_SECURED
	%DynastyStatus.text = "Dynasty %d · Legacy %d · Drill rank %d (×%d squad damage)" % [
		campaign.dynasty, campaign.legacy, campaign.drill_rank, 1 + campaign.drill_rank]
	if campaign.veteran_cadre:
		%DynastyStatus.text += " · Veteran Cadre"
	if not secured:
		%DynastyStatus.text += " · Securing this campaign earns %d Legacy" % campaign.secure_legacy()
	%ThreatStatus.text = "Threat %d (enemies +%d%% health and damage) · Best secured Threat %s" % [
		campaign.threat, Data.THREAT_STEP_PERCENT * campaign.threat,
		"none yet" if campaign.best_threat < 0 else str(campaign.best_threat)]
	var drill_cost: int = campaign.drill_cost()
	%TrainDrill.text = "Drill at maximum rank" if drill_cost == 0 else "Train Drill rank %d — %d Legacy" % [
		campaign.drill_rank + 1, drill_cost]
	%TrainDrill.disabled = blocked or drill_cost == 0 or campaign.legacy < drill_cost
	%VeteranCadre.text = "Veteran Cadre owned — new dynasties start troops at level 2" if campaign.veteran_cadre \
		else "Recruit Veteran Cadre — %d Legacy" % Campaign.VETERAN_CADRE_COST
	%VeteranCadre.disabled = blocked or not campaign.can_buy_veteran_cadre()
	%DynastyPreview.visible = dynasty_preview_open
	%FoundDynasty.disabled = blocked or not campaign.can_found_dynasty()
	%CancelDynasty.disabled = suspended
	%ConfirmDynasty.disabled = suspended or not dynasty_preview_open or not campaign.can_found_dynasty()
	%ConfirmDynasty.text = "Confirm reset — start dynasty %d" % (campaign.dynasty + 1)
	var threat_max: int = campaign.max_selectable_threat()
	%ThreatChoice.text = ("New dynasty Threat %d (up to %d): enemies +%d%% health and damage; securing it earns %d Legacy.\n"
		+ "Secure a Threat to unlock the next one. Threat 0 is always available.") % [
		preview_threat, threat_max, Data.THREAT_STEP_PERCENT * preview_threat, Campaign.threat_legacy(preview_threat)]
	%ThreatDown.disabled = suspended or not dynasty_preview_open or preview_threat <= 0
	%ThreatUp.disabled = suspended or not dynasty_preview_open or preview_threat >= threat_max
	var troop_reset: String = ("Shield infantry Lv.%d, Foot archers Lv.%d and Horse archers Lv.%d return to level 2 (Veteran Cadre); Gate Lv.%d returns to level 1."
		if campaign.veteran_cadre else
		"Shield infantry Lv.%d, Foot archers Lv.%d, Horse archers Lv.%d and Gate Lv.%d all return to level 1.") % [
		campaign.levels[0], campaign.levels[1], campaign.levels[2], campaign.gate_level]
	troop_reset += " Archer Platform Lv.%d returns to level 0." % campaign.archer_platform_level
	var cadre_keep: String = "owned: troops start at level 2" if campaign.veteran_cadre \
		else "not owned: %d Legacy" % Campaign.VETERAN_CADRE_COST
	%DynastyLosses.text = ("Lose all current gold: %d gold. %s\n"
		+ "Lose all conquered territory and security; restart Border Skirmish in Advance mode with fresh full-health troops.\n"
		+ "Clear battle progress, pending commands, farming/navigation choices and fractional round time.\n"
		+ "Keep access to the same three troop types. Keep Legacy %d and Drill rank %d (×%d squad damage after level additions); troop health, gold rewards and round frequency are unchanged. Keep Veteran Cadre (%s).\n"
		+ "Next secured campaign earns %d Legacy. Legacy and Drill rank are kept in the campaign save, as is Veteran Cadre; main-game saves are untouched.") % [
		campaign.gold, troop_reset, campaign.legacy, campaign.drill_rank, 1 + campaign.drill_rank, cadre_keep,
		Campaign.threat_legacy(preview_threat)]
	var checkpoint: bool = campaign.phase == Campaign.Phase.CONQUEST_CLEARED
	var defending: bool = campaign.phase == Campaign.Phase.DEFENDING
	match campaign.phase:
		Campaign.Phase.RUNNING:
			%CampaignStatus.text = "%s · %s · Running" % [ENCOUNTER_TITLES[campaign.current_encounter],
				"Farm" if campaign.mode == Campaign.Mode.FARM else "Advance"]
		Campaign.Phase.CONQUEST_CLEARED:
			%CampaignStatus.text = "Conquest cleared — prepare upgrades, then Start Defense; ordinary farming remains available"
		Campaign.Phase.DEFENDING:
			%CampaignStatus.text = "Counterattack · Defending the Stronghold"
		Campaign.Phase.CAMPAIGN_SECURED:
			%CampaignStatus.text = "Campaign secured · Counterattack defeated · +%d Legacy earned" % campaign.secure_legacy()
	if campaign.phase in [Campaign.Phase.RUNNING, Campaign.Phase.CONQUEST_CLEARED] \
			and LOSS_STATUS_TEXT.has(campaign.last_defense_loss):
		%CampaignStatus.text += " · " + LOSS_STATUS_TEXT[campaign.last_defense_loss]
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
	if campaign.battle.platform_damage > 0:
		%GateHealth.text += " · Archer Platform +%d damage/round" % campaign.battle.platform_damage
	%Rally.disabled = blocked or not campaign.can_rally()
	if campaign.rally_rounds > 0:
		%Rally.text = "Rally active — %d round%s left" % [campaign.rally_rounds,
			"" if campaign.rally_rounds == 1 else "s"]
	elif campaign.rally_cooldown > 0:
		%Rally.text = "Rally recovering — ready in %d battle round%s (%d s)" % [campaign.rally_cooldown,
			"" if campaign.rally_cooldown == 1 else "s", roundi(campaign.rally_cooldown * Data.ROUND_SECONDS)]
	elif campaign.can_rally():
		%Rally.text = "Rally — +%d%% army damage for %d rounds" % [Campaign.RALLY_PERCENT, Campaign.RALLY_ROUNDS]
	else:
		%Rally.text = "Rally — available during battles"
	%ShieldWall.disabled = blocked or not campaign.can_shield_wall()
	if campaign.shield_wall_rounds > 0:
		%ShieldWall.text = "Shield Wall active — %d round%s left" % [campaign.shield_wall_rounds,
			"" if campaign.shield_wall_rounds == 1 else "s"]
	elif campaign.shield_wall_cooldown > 0:
		%ShieldWall.text = "Shield Wall recovering — ready in %d battle round%s (%d s)" % [
			campaign.shield_wall_cooldown, "" if campaign.shield_wall_cooldown == 1 else "s",
			roundi(campaign.shield_wall_cooldown * Data.ROUND_SECONDS)]
	elif campaign.can_shield_wall():
		%ShieldWall.text = "Shield Wall — −%d%% enemy damage for %d rounds" % [
			Campaign.SHIELD_WALL_PERCENT, Campaign.SHIELD_WALL_ROUNDS]
	else:
		%ShieldWall.text = "Shield Wall — available during battles"
	var gate_cost: int = campaign.gate_purchase_cost()
	%GateUpgrade.text = "Gate Lv.%d · %s" % [campaign.gate_level,
		"MAX" if gate_cost == 0 else "Upgrade %d gold" % gate_cost]
	%GateUpgrade.disabled = blocked or gate_cost <= 0 or campaign.gold < gate_cost
	var platform_cost: int = campaign.platform_purchase_cost()
	%ArcherPlatform.text = "Archer Platform Lv.%d · +%d damage/round in defense · %s" % [
		campaign.archer_platform_level, Campaign.platform_damage_for(campaign.archer_platform_level),
		"MAX" if platform_cost == 0 else "Upgrade %d gold" % platform_cost]
	%ArcherPlatform.disabled = blocked or platform_cost <= 0 or campaign.gold < platform_cost
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
