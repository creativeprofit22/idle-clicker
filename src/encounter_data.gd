extends RefCounted

const ROUND_SECONDS: float = 1.0
enum Role { SHIELD, FOOT, HORSE }
enum Encounter { BORDER_SKIRMISH, ARCHER_POSITION, FORTIFIED_POSITION, STRONGHOLD, COUNTERATTACK }

class Squad extends RefCounted:
	var role: Role
	var title: String
	var health: int
	var max_health: int
	var damage: int

	func _init(squad_role: Role, squad_title: String, hp: int, attack: int) -> void:
		role = squad_role
		title = squad_title
		health = hp
		max_health = hp
		damage = attack

static func players() -> Array[Squad]:
	return [Squad.new(Role.SHIELD, "Shield infantry", 120, 4),
		Squad.new(Role.FOOT, "Foot archers", 40, 8),
		Squad.new(Role.HORSE, "Horse archers", 60, 6)]

# Threat scales authored enemy health and damage by +THREAT_STEP_PERCENT% per level, rounded half up.
const THREAT_STEP_PERCENT: int = 25

static func threat_scaled(value: int, threat: int) -> int:
	return (value * (100 + THREAT_STEP_PERCENT * threat) + 50) / 100

static func enemies(encounter: Encounter = Encounter.BORDER_SKIRMISH, threat: int = 0) -> Array[Squad]:
	var authored := _authored_enemies(encounter)
	if threat > 0:
		for squad in authored:
			squad.max_health = threat_scaled(squad.max_health, threat)
			squad.health = squad.max_health
			squad.damage = threat_scaled(squad.damage, threat)
	return authored

static func _authored_enemies(encounter: Encounter) -> Array[Squad]:
	if encounter == Encounter.COUNTERATTACK:
		return [Squad.new(Role.SHIELD, "Enemy shield", 180, 12),
			Squad.new(Role.FOOT, "Enemy foot archers", 80, 10),
			Squad.new(Role.HORSE, "Enemy horse archers", 80, 12)]
	if encounter == Encounter.STRONGHOLD:
		return [Squad.new(Role.SHIELD, "Enemy shield", 160, 8),
			Squad.new(Role.FOOT, "Enemy foot archers", 60, 8),
			Squad.new(Role.HORSE, "Enemy horse archers", 60, 6)]
	if encounter == Encounter.FORTIFIED_POSITION:
		return [Squad.new(Role.SHIELD, "Enemy shield", 160, 12),
			Squad.new(Role.FOOT, "Enemy foot archers", 80, 12)]
	if encounter == Encounter.ARCHER_POSITION:
		return [Squad.new(Role.SHIELD, "Enemy shield", 100, 6),
			Squad.new(Role.FOOT, "Enemy foot archers", 40, 8)]
	return [Squad.new(Role.SHIELD, "Enemy shield", 72, 3)]
