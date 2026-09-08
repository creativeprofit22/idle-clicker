extends RefCounted

const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const LEVEL_CAP: int = 3
const VICTORY_GOLD: int = 10
const HEALTH_GAIN: Array[int] = [40, 12, 20]
const DAMAGE_GAIN: Array[int] = [2, 4, 3]

var gold: int = 0
var levels: Array[int] = [1, 1, 1]
var battle: Combat
var _settled: bool = false
var current_encounter: int = Data.Encounter.BORDER_SKIRMISH
var _battle_reward: int = VICTORY_GOLD

func purchase_cost(role: int) -> int:
	if role < 0 or role >= levels.size() or levels[role] >= LEVEL_CAP:
		return 0
	return 20 * levels[role]

func purchase(role: int) -> bool:
	var cost: int = purchase_cost(role)
	if cost == 0 or gold < cost:
		return false
	gold -= cost
	levels[role] += 1
	return true

func is_encounter_unlocked(encounter: int) -> bool:
	if encounter == Data.Encounter.BORDER_SKIRMISH:
		return true
	if encounter == Data.Encounter.FORTIFIED_POSITION:
		return levels.all(func(level: int) -> bool: return level >= 2)
	return encounter == Data.Encounter.ARCHER_POSITION and levels.any(func(level: int) -> bool: return level > 1)

func encounter_reward(encounter: int) -> int:
	match encounter:
		Data.Encounter.BORDER_SKIRMISH: return VICTORY_GOLD
		Data.Encounter.ARCHER_POSITION: return 30
		Data.Encounter.FORTIFIED_POSITION: return 54
	return 0

func restart_battle(encounter: int = -1) -> Combat:
	var requested: int = current_encounter if encounter == -1 else encounter
	if not is_encounter_unlocked(requested):
		return null
	# Abandon the old battle without settling it: restart never awards gold.
	var army: Array[Data.Squad] = Data.players()
	for squad in army:
		var upgrades: int = levels[squad.role] - 1
		squad.max_health += HEALTH_GAIN[squad.role] * upgrades
		squad.damage += DAMAGE_GAIN[squad.role] * upgrades
	battle = Combat.new(requested, army)
	current_encounter = requested
	_battle_reward = encounter_reward(requested)
	_settled = false
	return battle

func settle(completed: Combat) -> bool:
	# Only the current, terminal battle can be consumed, once; no growing ID ledger.
	if completed == null or completed != battle or _settled or completed.result == Combat.Result.ONGOING:
		return false
	_settled = true
	if completed.result == Combat.Result.VICTORY:
		gold += _battle_reward
	return true
