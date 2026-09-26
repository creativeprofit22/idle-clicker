extends "res://src/economy.gd"

# Session-local campaign; the separate playable prototype exposes conquest and defense.
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
var dynasty: int = 1
# Permanent across dynasty resets: Legacy balance and purchased Drill rank.
var drill_rank: int = 0
var legacy: int = 0
# Permanent one-rank Legacy upgrade: dynasties founded after purchase start troops at level 2.
var veteran_cadre: bool = false
# Drill rank captured when the current battle was created (purchases apply next battle).
var _battle_drill_rank: int = 0
# Threat chosen when this dynasty was founded (dynasty 1 is always 0); fixed for the dynasty.
var threat: int = 0
# Highest Threat ever secured (-1 before the first secure) and total Legacy ever paid out.
var best_threat: int = -1
var legacy_earned: int = 0
# Cause of the last lost Counterattack (Combat.DefeatReason: NONE, GATE_DESTROYED or TIMEOUT).
# Kept until the next defense starts; shown as a hint only, never changes rewards or state.
var last_defense_loss: int = Combat.DefeatReason.NONE
# Rally: boosted rounds still to resolve (0..RALLY_ROUNDS) and cooldown rounds left
# (0..RALLY_COOLDOWN). Never both nonzero; both 0 means ready.
var rally_rounds: int = 0
var rally_cooldown: int = 0
# Shield Wall: shielded rounds still to resolve (0..SHIELD_WALL_ROUNDS) and cooldown rounds left
# (0..SHIELD_WALL_COOLDOWN). Never both nonzero; both 0 means ready. Independent of Rally.
var shield_wall_rounds: int = 0
var shield_wall_cooldown: int = 0
# Archer Platform: owned level (0..PLATFORM_MAX, per dynasty) and the level locked in when the
# current battle was created (0 unless it is the Counterattack; purchases apply next defense).
var archer_platform_level: int = 0
var _battle_platform_level: int = 0

const FIRST_SECURE_LEGACY: int = 10
const REPEAT_SECURE_LEGACY: int = 3
const DRILL_COSTS: Array[int] = [10, 20, 40]
const DRILL_MAX: int = 3
const VETERAN_CADRE_COST: int = 50
const THREAT_MAX: int = 10
const RALLY_PERCENT: int = Combat.RALLY_PERCENT
const RALLY_ROUNDS: int = 5
const RALLY_COOLDOWN: int = 20
const SHIELD_WALL_PERCENT: int = Combat.SHIELD_WALL_PERCENT
const SHIELD_WALL_ROUNDS: int = 5
const SHIELD_WALL_COOLDOWN: int = 20
const PLATFORM_MAX: int = 3
const PLATFORM_COSTS: Array[int] = [30, 50, 70]
const PLATFORM_DAMAGE_PER_LEVEL: int = 3
# Closed-app reward: capped gold from the best farmable cleared territory, never simulated combat.
const AWAY_CAP_SECONDS: int = 28800
const AWAY_MINUTES_PER_VICTORY: int = 2

# Gold for `seconds` of closed-app absence: one victory of the best farmable cleared stage every
# AWAY_MINUTES_PER_VICTORY minutes, capped at AWAY_CAP_SECONDS. Integer math; negative time pays 0.
func away_reward(seconds: int) -> int:
	if seconds <= 0:
		return 0
	var territory: int = Data.Encounter.ARCHER_POSITION if archer_cleared else (
		Data.Encounter.BORDER_SKIRMISH if border_cleared else -1)
	if territory == -1:
		return 0
	@warning_ignore("integer_division")
	return mini(seconds, AWAY_CAP_SECONDS) * encounter_reward(territory) / (AWAY_MINUTES_PER_VICTORY * 60)

# Legacy paid for securing a later dynasty at the given Threat.
static func threat_legacy(level: int) -> int:
	return REPEAT_SECURE_LEGACY * (1 + level)

# Legacy paid when the current dynasty's campaign is secured.
func secure_legacy() -> int:
	return FIRST_SECURE_LEGACY if dynasty == 1 else threat_legacy(threat)

# Highest Threat a new dynasty may choose: one above the best secured, never locked out of 0.
func max_selectable_threat() -> int:
	return clampi(best_threat + 1, 0, THREAT_MAX)

# Rally is usable in any ongoing campaign battle when neither active nor cooling down.
func can_rally() -> bool:
	return phase in [Phase.RUNNING, Phase.DEFENDING] and battle != null \
		and battle.result == Combat.Result.ONGOING and rally_rounds == 0 and rally_cooldown == 0

# Like the commander strike, the boost starts at the next resolved round.
func rally() -> bool:
	if not can_rally():
		return false
	rally_rounds = RALLY_ROUNDS
	return true

# Shield Wall is usable in any ongoing campaign battle when neither active nor cooling down.
func can_shield_wall() -> bool:
	return phase in [Phase.RUNNING, Phase.DEFENDING] and battle != null \
		and battle.result == Combat.Result.ONGOING and shield_wall_rounds == 0 \
		and shield_wall_cooldown == 0

# Like Rally, the cut starts at the next resolved round.
func shield_wall() -> bool:
	if not can_shield_wall():
		return false
	shield_wall_rounds = SHIELD_WALL_ROUNDS
	return true

# Resolves one round of the current battle with any Rally boost and Shield Wall cut, then ticks
# both. The cooldown clocks advance only here, so they count resolved battle rounds only.
func resolve_round() -> void:
	if battle == null or battle.result != Combat.Result.ONGOING:
		return
	battle.rally_active = rally_rounds > 0
	battle.shield_wall_active = shield_wall_rounds > 0
	battle.step_round()
	battle.rally_active = false
	battle.shield_wall_active = false
	if shield_wall_rounds > 0:
		shield_wall_rounds -= 1
		if shield_wall_rounds == 0 or battle.result != Combat.Result.ONGOING:
			shield_wall_rounds = 0
			shield_wall_cooldown = SHIELD_WALL_COOLDOWN
	elif shield_wall_cooldown > 0:
		shield_wall_cooldown -= 1
	if rally_rounds > 0:
		rally_rounds -= 1
		if rally_rounds == 0 or battle.result != Combat.Result.ONGOING:
			rally_rounds = 0
			rally_cooldown = RALLY_COOLDOWN
	elif rally_cooldown > 0:
		rally_cooldown -= 1

# A battle that ends or restarts while Rally is active drops the rest and starts the full cooldown.
func _drop_rally() -> void:
	if rally_rounds > 0:
		rally_rounds = 0
		rally_cooldown = RALLY_COOLDOWN

# Same transitions as Rally: the rest of an active Shield Wall is dropped and the full cooldown starts.
func _drop_shield_wall() -> void:
	if shield_wall_rounds > 0:
		shield_wall_rounds = 0
		shield_wall_cooldown = SHIELD_WALL_COOLDOWN

func drill_cost() -> int:
	return 0 if drill_rank >= DRILL_MAX else DRILL_COSTS[drill_rank]

# Allowed in any phase; the multiplier applies from the next created battle.
func train_drill() -> bool:
	var cost: int = drill_cost()
	if cost == 0 or legacy < cost:
		return false
	legacy -= cost
	drill_rank += 1
	return true

func can_buy_veteran_cadre() -> bool:
	return not veteran_cadre and legacy >= VETERAN_CADRE_COST

# Allowed in any phase; changes nothing but Legacy and the flag. It takes effect at the next founded dynasty.
func buy_veteran_cadre() -> bool:
	if not can_buy_veteran_cadre():
		return false
	legacy -= VETERAN_CADRE_COST
	veteran_cadre = true
	return true

# Troop level a newly founded dynasty starts at (the gate always starts at 1).
func dynasty_start_level() -> int:
	return 2 if veteran_cadre else 1

func _squad_damage_multiplier() -> int:
	return 1 + drill_rank

func _enemy_threat() -> int:
	return threat

func can_found_dynasty() -> bool:
	return phase == Phase.CAMPAIGN_SECURED \
		and border_cleared and archer_cleared and stronghold_cleared \
		and current_encounter == Data.Encounter.COUNTERATTACK \
		and battle != null and battle.is_defense and _settled \
		and battle.result == Combat.Result.VICTORY and battle.gate_health > 0

func found_dynasty(next_threat: int = 0) -> Combat:
	if not can_found_dynasty() or next_threat < 0 or next_threat > max_selectable_threat():
		return null
	dynasty += 1
	threat = next_threat
	gold = 0
	var start: int = dynasty_start_level()
	levels = [start, start, start]
	gate_level = 1
	archer_platform_level = 0
	phase = Phase.RUNNING
	mode = Mode.ADVANCE
	border_cleared = false
	archer_cleared = false
	stronghold_cleared = false
	farm_encounter = -1
	pending_navigation = Navigation.NONE
	pending_farm = -1
	# Founding requires a won defense, which already cleared this; reset anyway for safety.
	last_defense_loss = Combat.DefeatReason.NONE
	rally_rounds = 0
	rally_cooldown = 0
	shield_wall_rounds = 0
	shield_wall_cooldown = 0
	return _begin_encounter(Data.Encounter.BORDER_SKIRMISH)

func gate_purchase_cost() -> int:
	return 0 if gate_level >= LEVEL_CAP else 20 * gate_level

func purchase_gate() -> bool:
	var cost: int = gate_purchase_cost()
	if cost == 0 or gold < cost:
		return false
	gold -= cost
	gate_level += 1
	return true

# Gold for the next Archer Platform level; 0 once capped.
func platform_purchase_cost() -> int:
	return 0 if archer_platform_level >= PLATFORM_MAX else PLATFORM_COSTS[archer_platform_level]

func can_purchase_platform() -> bool:
	var cost: int = platform_purchase_cost()
	return cost > 0 and gold >= cost

# Allowed in any phase, like the gate; the new level is locked in at the next Start Defense.
func purchase_platform() -> bool:
	if not can_purchase_platform():
		return false
	gold -= platform_purchase_cost()
	archer_platform_level += 1
	return true

static func platform_damage_for(level: int) -> int:
	return PLATFORM_DAMAGE_PER_LEVEL * level

func start_defense() -> Combat:
	if phase != Phase.CONQUEST_CLEARED or not stronghold_cleared:
		return null
	var assault := _begin_encounter(Data.Encounter.COUNTERATTACK)
	last_defense_loss = Combat.DefeatReason.NONE
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
	if created != null:
		_battle_drill_rank = drill_rank
		_drop_rally()
		_drop_shield_wall()
	if created != null:
		_battle_platform_level = archer_platform_level if created.is_defense else 0
		created.platform_damage = platform_damage_for(_battle_platform_level)
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
	# Normally already dropped by resolve_round(); covers a battle ended by any other path.
	_drop_rally()
	_drop_shield_wall()
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
			# Legacy is credited in the same transition (one save write, D8).
			phase = Phase.CAMPAIGN_SECURED
			legacy += secure_legacy()
			legacy_earned += secure_legacy()
			best_threat = maxi(best_threat, threat)
			return true
		# Combat already decided the cause (gate at zero before the round-60 timeout).
		last_defense_loss = completed.defeat_reason
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
