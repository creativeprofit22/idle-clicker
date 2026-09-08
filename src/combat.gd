extends RefCounted

const Data = preload("res://src/encounter_data.gd")
enum Result { ONGOING, VICTORY, DEFEAT }
enum DefeatReason { NONE, ARMY_DEFEAT, GATE_DESTROYED, TIMEOUT }

var is_defense: bool = false
var gate_max_health: int = 0
var gate_health: int = 0
var defeat_reason: DefeatReason = DefeatReason.NONE

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
	is_defense = encounter == Data.Encounter.COUNTERATTACK
	gate_max_health = 80 if is_defense else 0
	gate_health = gate_max_health
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
	var gate_damage: int = 0
	for squad in enemies:
		if squad.health <= 0:
			continue
		var target: int = -1
		if is_defense:
			for i in range(players.size()):
				if players[i].health > 0 and players[i].role == Data.Role.SHIELD:
					target = i
					break
		else:
			target = _target_index(players, squad.role)
		if target >= 0:
			incoming[target] += squad.damage
		elif is_defense:
			gate_damage += squad.damage
	if commander_queued:
		var target: int = _target_index(enemies, Data.Role.SHIELD)
		if target >= 0:
			outgoing[target] += commander_damage
	for i in range(enemies.size()):
		enemies[i].health = maxi(0, enemies[i].health - outgoing[i])
	for i in range(players.size()):
		players[i].health = maxi(0, players[i].health - incoming[i])
	gate_health = maxi(0, gate_health - gate_damage)
	commander_queued = false
	rounds += 1
	if is_defense and gate_health == 0:
		result = Result.DEFEAT
		defeat_reason = DefeatReason.GATE_DESTROYED
	elif not is_defense and _target_index(players, Data.Role.SHIELD) < 0:
		result = Result.DEFEAT
		defeat_reason = DefeatReason.ARMY_DEFEAT
	elif _target_index(enemies, Data.Role.SHIELD) < 0:
		result = Result.VICTORY
	elif rounds >= 60:
		result = Result.DEFEAT
		defeat_reason = DefeatReason.TIMEOUT
