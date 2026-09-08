extends RefCounted

const Data = preload("res://src/encounter_data.gd")
enum Result { ONGOING, VICTORY, DEFEAT }

var players: Array[Data.Squad]
var enemies: Array[Data.Squad]
var rounds: int = 0
var result: Result = Result.ONGOING
var commander_queued: bool = false
var commander_damage: int = 0

func _init(encounter: Data.Encounter = Data.Encounter.BORDER_SKIRMISH,
		army: Array[Data.Squad] = Data.players()) -> void:
	for squad in army:
		players.append(Data.Squad.new(squad.role, squad.title, squad.max_health, squad.damage))
	enemies = Data.enemies(encounter)
	var starting_damage: int = 0
	for squad in players:
		starting_damage += squad.damage
	commander_damage = maxi(1, floori(starting_damage / 3.0))

func queue_commander() -> bool:
	if result != Result.ONGOING or commander_queued:
		return false
	commander_queued = true
	return true

func _target_index(opponents: Array[Data.Squad], role: Data.Role) -> int:
	var priority: Array[Data.Role] = [Data.Role.SHIELD, Data.Role.HORSE, Data.Role.FOOT]
	if role == Data.Role.HORSE:
		priority = [Data.Role.FOOT, Data.Role.HORSE, Data.Role.SHIELD]
	for target_role in priority:
		for i in range(opponents.size()):
			if opponents[i].role == target_role and opponents[i].health > 0:
				return i
	return -1

func step_round() -> void:
	if result != Result.ONGOING:
		return
	var outgoing: Array[int] = []
	outgoing.resize(enemies.size())
	outgoing.fill(0)
	var incoming: Array[int] = []
	incoming.resize(players.size())
	incoming.fill(0)
	# Select every target before applying either army's damage; no overkill spills.
	for squad in players:
		var target: int = _target_index(enemies, squad.role)
		if squad.health > 0 and target >= 0:
			outgoing[target] += squad.damage
	for squad in enemies:
		var target: int = _target_index(players, squad.role)
		if squad.health > 0 and target >= 0:
			incoming[target] += squad.damage
	if commander_queued:
		var target: int = _target_index(enemies, Data.Role.SHIELD)
		if target >= 0:
			outgoing[target] += commander_damage
	for i in range(enemies.size()):
		enemies[i].health = maxi(0, enemies[i].health - outgoing[i])
	for i in range(players.size()):
		players[i].health = maxi(0, players[i].health - incoming[i])
	commander_queued = false
	rounds += 1
	if _target_index(players, Data.Role.SHIELD) < 0:
		result = Result.DEFEAT
	elif _target_index(enemies, Data.Role.SHIELD) < 0:
		result = Result.VICTORY
	elif rounds >= 60:
		result = Result.DEFEAT
