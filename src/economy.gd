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

func restart_battle() -> Combat:
	# Abandon the old battle without settling it: restart never awards gold.
	var army: Array[Data.Squad] = Data.players()
	for squad in army:
		var upgrades: int = levels[squad.role] - 1
		squad.max_health += HEALTH_GAIN[squad.role] * upgrades
		squad.damage += DAMAGE_GAIN[squad.role] * upgrades
	battle = Combat.new(Data.Encounter.BORDER_SKIRMISH, army)
	_settled = false
	return battle

func settle(completed: Combat) -> bool:
	# Only the current, terminal battle can be consumed, once; no growing ID ledger.
	if completed == null or completed != battle or _settled or completed.result == Combat.Result.ONGOING:
		return false
	_settled = true
	if completed.result == Combat.Result.VICTORY:
		gold += VICTORY_GOLD
	return true
