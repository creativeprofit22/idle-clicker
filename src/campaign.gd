extends "res://src/economy.gd"

# Session-local campaign; the separate playable prototype exposes conquest only.
enum Phase { RUNNING, CONQUEST_CLEARED, DEFENDING, CAMPAIGN_SECURED }
enum Mode { ADVANCE, FARM }
enum Navigation { NONE, FARM, FRONTIER }
const STAGES: Array[int] = [Data.Encounter.BORDER_SKIRMISH,
	Data.Encounter.ARCHER_POSITION, Data.Encounter.STRONGHOLD]

var phase: Phase = Phase.RUNNING
var mode: Mode = Mode.ADVANCE
var border_cleared: bool = false
var archer_cleared: bool = false
var stronghold_cleared: bool = false
var farm_encounter: int = -1
var pending_navigation: Navigation = Navigation.NONE
var pending_farm: int = -1
var gate_level: int = 1

func gate_purchase_cost() -> int:
	return 0 if gate_level >= LEVEL_CAP else 20 * gate_level

func purchase_gate() -> bool:
	var cost: int = gate_purchase_cost()
	if cost == 0 or gold < cost:
		return false
	gold -= cost
	gate_level += 1
	return true

func start_defense() -> Combat:
	if phase != Phase.CONQUEST_CLEARED or not stronghold_cleared:
		return null
	var assault := _begin_encounter(Data.Encounter.COUNTERATTACK)
	phase = Phase.DEFENDING
	mode = Mode.ADVANCE
	farm_encounter = -1
	pending_navigation = Navigation.NONE
	pending_farm = -1
	return assault

func is_encounter_unlocked(encounter: int) -> bool:
	match encounter:
		Data.Encounter.COUNTERATTACK: return phase == Phase.CONQUEST_CLEARED and stronghold_cleared
		Data.Encounter.BORDER_SKIRMISH: return true
		Data.Encounter.ARCHER_POSITION: return border_cleared
		Data.Encounter.STRONGHOLD: return border_cleared and archer_cleared and not stronghold_cleared
	return false

func encounter_reward(encounter: int) -> int:
	if encounter == Data.Encounter.STRONGHOLD:
		return 30
	if encounter in [Data.Encounter.FORTIFIED_POSITION, Data.Encounter.COUNTERATTACK]:
		return 0
	return super.encounter_reward(encounter)

func _frontier_encounter() -> int:
	var cleared: Array[bool] = [border_cleared, archer_cleared, stronghold_cleared]
	for i in range(STAGES.size()):
		if not cleared[i]:
			return STAGES[i]
	return -1

func _begin_encounter(encounter: int) -> Combat:
	var created := super.restart_battle(encounter)
	if created != null and created.is_defense:
		created.gate_max_health = 80 + 60 * (gate_level - 1)
		created.gate_health = created.gate_max_health
	return created

func restart_battle(encounter: int = -1) -> Combat:
	if phase != Phase.RUNNING or (encounter != -1 and encounter != current_encounter):
		return null
	pending_navigation = Navigation.NONE
	pending_farm = -1
	return _begin_encounter(current_encounter)

func request_farm(encounter: int) -> bool:
	if phase == Phase.CAMPAIGN_SECURED:
		return false
	if not ((encounter == Data.Encounter.BORDER_SKIRMISH and border_cleared)
		or (encounter == Data.Encounter.ARCHER_POSITION and archer_cleared)):
		return false
	if phase == Phase.CONQUEST_CLEARED:
		mode = Mode.FARM
		farm_encounter = encounter
		phase = Phase.RUNNING
		_begin_encounter(encounter)
	else:
		pending_navigation = Navigation.FARM
		pending_farm = encounter
	return true

func request_frontier() -> bool:
	if phase in [Phase.DEFENDING, Phase.CAMPAIGN_SECURED]:
		return false
	if phase == Phase.CONQUEST_CLEARED:
		return true
	if mode != Mode.FARM:
		return false
	pending_navigation = Navigation.FRONTIER
	pending_farm = -1
	return true

func settle(completed: Combat) -> bool:
	if not super.settle(completed):
		return false
	var victory: bool = completed.result == Combat.Result.VICTORY
	if victory:
		match current_encounter:
			Data.Encounter.BORDER_SKIRMISH: border_cleared = true
			Data.Encounter.ARCHER_POSITION: archer_cleared = true
			Data.Encounter.STRONGHOLD: stronghold_cleared = true
	var navigation: Navigation = pending_navigation
	var destination: int = pending_farm
	pending_navigation = Navigation.NONE
	pending_farm = -1
	# Outcome and clearance precede routing; a terminal objective overrides navigation.
	if phase == Phase.DEFENDING:
		if victory:
			phase = Phase.CAMPAIGN_SECURED
			return true
		phase = Phase.RUNNING
	if victory and current_encounter == Data.Encounter.STRONGHOLD:
		phase = Phase.CONQUEST_CLEARED
		mode = Mode.ADVANCE
		farm_encounter = -1
		return true
	if navigation == Navigation.FARM:
		mode = Mode.FARM
		farm_encounter = destination
	elif navigation == Navigation.FRONTIER:
		mode = Mode.ADVANCE
		farm_encounter = -1
		destination = _frontier_encounter()
	elif not victory:
		farm_encounter = Data.Encounter.ARCHER_POSITION if archer_cleared else (
			Data.Encounter.BORDER_SKIRMISH if border_cleared else -1)
		mode = Mode.FARM if farm_encounter != -1 else Mode.ADVANCE
		destination = farm_encounter if mode == Mode.FARM else Data.Encounter.BORDER_SKIRMISH
	elif mode == Mode.FARM:
		destination = farm_encounter
	else:
		destination = _frontier_encounter()
	if destination == -1:
		phase = Phase.CONQUEST_CLEARED
	else:
		_begin_encounter(destination)
	return true
