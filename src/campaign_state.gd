extends RefCounted

# In-memory campaign state capture, validation and restoration (contract v8; v1-v7 migrate on load). No I/O.
const Campaign = preload("res://src/campaign.gd")
const Combat = preload("res://src/combat.gd")
const Data = preload("res://src/encounter_data.gd")
const ProgressSave = preload("res://src/progress_save.gd")

enum Outcome { VALID, CORRUPT, UNSUPPORTED, UNSAVABLE }
const FORMAT: String = "idle-clicker-campaign"
const VERSION: int = 8
const ROUND_USEC: int = roundi(Data.ROUND_SECONDS * 1000000)
const KEYS_V1: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"cleared", "phase", "mode", "farm_encounter", "pending_navigation", "pending_farm",
	"current_encounter", "settled", "round_progress_usec", "battle"]
const BATTLE_KEYS_V1: Array[String] = ["snapshot_levels", "player_health", "enemy_health",
	"snapshot_gate_level", "gate_health", "rounds", "result", "defeat_reason"]
const KEYS_V2: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "cleared", "phase", "mode", "farm_encounter", "pending_navigation",
	"pending_farm", "current_encounter", "settled", "round_progress_usec", "battle"]
const KEYS_V3: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "threat", "best_threat", "legacy_earned", "cleared", "phase", "mode",
	"farm_encounter", "pending_navigation", "pending_farm", "current_encounter", "settled",
	"round_progress_usec", "battle"]
# v4 adds the whole-second Unix save time used only for the closed-app reward (0 = unknown).
const KEYS_V4: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "threat", "best_threat", "legacy_earned", "cleared", "phase", "mode",
	"farm_encounter", "pending_navigation", "pending_farm", "current_encounter", "settled",
	"round_progress_usec", "saved_at", "battle"]
# v5 adds the permanent Veteran Cadre flag (bool).
const KEYS_V5: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "veteran_cadre", "threat", "best_threat", "legacy_earned", "cleared",
	"phase", "mode", "farm_encounter", "pending_navigation", "pending_farm", "current_encounter",
	"settled", "round_progress_usec", "saved_at", "battle"]
# v6 adds the cause of the last lost Counterattack (Combat.DefeatReason NONE/GATE_DESTROYED/TIMEOUT).
const KEYS_V6: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "veteran_cadre", "threat", "best_threat", "legacy_earned", "cleared",
	"phase", "mode", "farm_encounter", "pending_navigation", "pending_farm", "current_encounter",
	"settled", "round_progress_usec", "saved_at", "last_defense_loss", "battle"]
# v7 adds Rally: boosted rounds left and cooldown rounds left (integers, never both nonzero).
const KEYS_V7: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "veteran_cadre", "threat", "best_threat", "legacy_earned", "cleared",
	"phase", "mode", "farm_encounter", "pending_navigation", "pending_farm", "current_encounter",
	"settled", "round_progress_usec", "saved_at", "last_defense_loss", "rally_rounds",
	"rally_cooldown", "battle"]
# v8 adds Shield Wall: shielded rounds left and cooldown rounds left (integers, never both nonzero).
const KEYS: Array[String] = ["format", "version", "gold", "levels", "gate_level", "dynasty",
	"legacy", "drill_rank", "veteran_cadre", "threat", "best_threat", "legacy_earned", "cleared",
	"phase", "mode", "farm_encounter", "pending_navigation", "pending_farm", "current_encounter",
	"settled", "round_progress_usec", "saved_at", "last_defense_loss", "rally_rounds",
	"rally_cooldown", "shield_wall_rounds", "shield_wall_cooldown", "battle"]
const BATTLE_KEYS: Array[String] = ["snapshot_levels", "snapshot_drill_rank", "player_health",
	"enemy_health", "snapshot_gate_level", "gate_health", "rounds", "result", "defeat_reason"]
const ENCOUNTERS: Array[int] = [Data.Encounter.BORDER_SKIRMISH, Data.Encounter.ARCHER_POSITION,
	Data.Encounter.STRONGHOLD, Data.Encounter.COUNTERATTACK]

static func _gate_max(gate: int) -> int:
	return 80 + 60 * (gate - 1)

static func _army(levels: Array[int], rank: int) -> Array[Data.Squad]:
	var model := Campaign.new()
	model.drill_rank = rank
	return model._snapshot_army(levels)

# Total Legacy ever paid out for reaching this dynasty (and securing it, if secured) when every
# later dynasty ran at Threat 0 — the only possibility for v1/v2 files.
static func _legacy_earned(dynasty: int, secured: bool) -> int:
	var earned: int = 0
	if dynasty > 1:
		earned = Campaign.FIRST_SECURE_LEGACY + Campaign.REPEAT_SECURE_LEGACY * (dynasty - 2)
	if secured:
		earned += Campaign.FIRST_SECURE_LEGACY if dynasty == 1 else Campaign.REPEAT_SECURE_LEGACY
	return earned

# v3 bounds on total Legacy earned, given how many later dynasties were secured and the best Threat.
static func _earned_range(dynasty: int, secured: bool, best: int) -> Array[int]:
	if best < 0:
		return [0, 0]
	var later: int = dynasty - 2 + (1 if secured and dynasty > 1 else 0)
	# Cheapest: every later secure at Threat 0 except one at each Threat 1..best.
	var low: int = Campaign.FIRST_SECURE_LEGACY + Campaign.threat_legacy(0) * later
	for t in range(1, best + 1):
		low += Campaign.threat_legacy(t) - Campaign.threat_legacy(0)
	# Richest: the j-th later secure at the highest Threat reachable by then (j), never above the best.
	var high: int = Campaign.FIRST_SECURE_LEGACY
	for j in range(1, later + 1):
		high += Campaign.threat_legacy(mini(j, best))
	return [low, high]

static func _legacy_spent(rank: int) -> int:
	var spent: int = 0
	for i in range(rank):
		spent += Campaign.DRILL_COSTS[i]
	return spent

# Everything restore() rebuilds; capture compares it to prove the round trip is exact.
static func _fingerprint(campaign: Campaign) -> Array:
	var combat: Combat = campaign.battle
	var rows: Array = []
	for army in [combat.players, combat.enemies]:
		for squad: Data.Squad in army:
			rows.append([squad.role, squad.title, squad.health, squad.max_health, squad.damage])
	return [campaign.gold, Array(campaign.levels), campaign.gate_level, campaign.dynasty,
		campaign.legacy, campaign.drill_rank, campaign.veteran_cadre, campaign._battle_drill_rank, campaign.threat,
		campaign.best_threat, campaign.legacy_earned, campaign.border_cleared,
		campaign.archer_cleared, campaign.stronghold_cleared, campaign.phase, campaign.mode,
		campaign.farm_encounter, campaign.pending_navigation, campaign.pending_farm,
		campaign.current_encounter, campaign._settled, campaign._battle_reward, campaign.last_defense_loss,
		campaign.rally_rounds, campaign.rally_cooldown, campaign.shield_wall_rounds,
		campaign.shield_wall_cooldown, rows,
		combat.players.size(), combat.enemies.size(), combat.is_defense, combat.gate_max_health,
		combat.gate_health, combat.rounds, combat.result, combat.defeat_reason,
		combat.commander_queued, combat.commander_damage]

static func capture(campaign: Campaign, round_progress_usec: int, saved_at: int = 0) -> Dictionary:
	if campaign == null or campaign.battle == null or campaign.battle.commander_queued:
		return {"outcome": Outcome.UNSAVABLE}
	var combat: Combat = campaign.battle
	if combat.players.size() != 3:
		return {"outcome": Outcome.UNSAVABLE}
	var snapshot_levels: Array = []
	for role in range(3):
		var found: int = 0
		for level in range(1, 4):
			var uniform: Array[int] = [level, level, level]
			var derived: Data.Squad = _army(uniform, campaign._battle_drill_rank)[role]
			if combat.players[role].max_health == derived.max_health and combat.players[role].damage == derived.damage:
				found = level
		if found == 0:
			return {"outcome": Outcome.UNSAVABLE}
		snapshot_levels.append(found)
	var snapshot_gate: int = 0
	if combat.is_defense:
		for gate in range(1, 4):
			if combat.gate_max_health == _gate_max(gate):
				snapshot_gate = gate
		if snapshot_gate == 0:
			return {"outcome": Outcome.UNSAVABLE}
	var player_health: Array = []
	for squad in combat.players:
		player_health.append(squad.health)
	var enemy_health: Array = []
	for squad in combat.enemies:
		enemy_health.append(squad.health)
	var state: Dictionary = {
		"format": FORMAT,
		"version": VERSION,
		"gold": campaign.gold,
		"levels": Array(campaign.levels),
		"gate_level": campaign.gate_level,
		"dynasty": campaign.dynasty,
		"legacy": campaign.legacy,
		"drill_rank": campaign.drill_rank,
		"veteran_cadre": campaign.veteran_cadre,
		"threat": campaign.threat,
		"best_threat": campaign.best_threat,
		"legacy_earned": campaign.legacy_earned,
		"cleared": [campaign.border_cleared, campaign.archer_cleared, campaign.stronghold_cleared],
		"phase": int(campaign.phase),
		"mode": int(campaign.mode),
		"farm_encounter": campaign.farm_encounter,
		"pending_navigation": int(campaign.pending_navigation),
		"pending_farm": campaign.pending_farm,
		"current_encounter": campaign.current_encounter,
		"settled": campaign._settled,
		"round_progress_usec": round_progress_usec,
		"saved_at": saved_at,
		"last_defense_loss": campaign.last_defense_loss,
		"rally_rounds": campaign.rally_rounds,
		"rally_cooldown": campaign.rally_cooldown,
		"shield_wall_rounds": campaign.shield_wall_rounds,
		"shield_wall_cooldown": campaign.shield_wall_cooldown,
		"battle": {
			"snapshot_levels": snapshot_levels,
			"snapshot_drill_rank": campaign._battle_drill_rank,
			"player_health": player_health,
			"enemy_health": enemy_health,
			"snapshot_gate_level": snapshot_gate,
			"gate_health": combat.gate_health if combat.is_defense else 0,
			"rounds": combat.rounds,
			"result": int(combat.result),
			"defeat_reason": int(combat.defeat_reason),
		},
	}
	# Refuse anything the file cannot reproduce exactly (Legacy ledger, altered stats, etc.).
	var restored := restore(state)
	if restored.outcome != Outcome.VALID or _fingerprint(restored.campaign) != _fingerprint(campaign):
		return {"outcome": Outcome.UNSAVABLE}
	return {"outcome": Outcome.VALID, "state": state}

static func validate(state: Variant) -> Dictionary:
	return {"outcome": _parse(state).outcome}

static func _keys_exact(data: Dictionary, keys: Array[String]) -> bool:
	if data.size() != keys.size():
		return false
	for key in keys:
		if not data.has(key):
			return false
	return true

static func _ints(value: Variant, size: int, minimum: int, maximum: int) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		return null
	var parsed: Array[int] = []
	for item in value:
		if not ProgressSave._integer(item, minimum, maximum):
			return null
		parsed.append(int(item))
	return parsed

static func _any_alive(health: Array[int]) -> bool:
	return health.any(func(value: int) -> bool: return value > 0)

# Exact integer or finite integral float, with no range bound (no int() truncation).
static func _whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value

# Returns normalized integer fields on success; any failure carries no state.
static func _parse(state: Variant) -> Dictionary:
	var corrupt := {"outcome": Outcome.CORRUPT}
	if typeof(state) != TYPE_DICTIONARY:
		return corrupt
	var data: Dictionary = state
	if not data.has("format") or typeof(data.format) != TYPE_STRING or data.format != FORMAT:
		return corrupt
	# D10: any finite whole-number version is a version; only its value decides support.
	if not data.has("version") or not _whole_number(data.version):
		return corrupt
	# v1-v7 files are parsed under their own exact key sets and migrated in memory (no separate write).
	var v1: bool = data.version == 1
	var v2: bool = data.version == 2
	var v3: bool = data.version == 3
	var v4: bool = data.version == 4
	var v5: bool = data.version == 5
	var v6: bool = data.version == 6
	var v7: bool = data.version == 7
	if not v1 and not v2 and not v3 and not v4 and not v5 and not v6 and not v7 \
			and data.version != VERSION:
		return {"outcome": Outcome.UNSUPPORTED}
	var keys: Array[String] = KEYS_V1 if v1 else (KEYS_V2 if v2 else (KEYS_V3 if v3 else (
		KEYS_V4 if v4 else (KEYS_V5 if v5 else (KEYS_V6 if v6 else (KEYS_V7 if v7 else KEYS))))))
	if not _keys_exact(data, keys) or typeof(data.battle) != TYPE_DICTIONARY:
		return corrupt
	# Files older than v5 predate Veteran Cadre: it loads unowned.
	var cadre: bool = false
	if data.has("veteran_cadre"):
		if typeof(data.veteran_cadre) != TYPE_BOOL:
			return corrupt
		cadre = data.veteran_cadre
	# Older files carry no save time: 0 means unknown, so they grant no closed-app reward.
	var saved_at: int = 0
	if data.has("saved_at"):
		if not ProgressSave._integer(data.saved_at, 0, ProgressSave.MAX_GOLD):
			return corrupt
		saved_at = int(data.saved_at)
	# Files older than v6 predate the stored defense-loss cause: it loads as NONE.
	var last_loss: int = Combat.DefeatReason.NONE
	if data.has("last_defense_loss"):
		if not ProgressSave._integer(data.last_defense_loss, 0, Combat.DefeatReason.TIMEOUT) \
				or int(data.last_defense_loss) == Combat.DefeatReason.ARMY_DEFEAT:
			return corrupt
		last_loss = int(data.last_defense_loss)
	# Files older than v7 predate Rally: it loads ready.
	var rally_rounds: int = 0
	var rally_cooldown: int = 0
	if data.has("rally_rounds"):
		if not ProgressSave._integer(data.rally_rounds, 0, Campaign.RALLY_ROUNDS) \
				or not ProgressSave._integer(data.rally_cooldown, 0, Campaign.RALLY_COOLDOWN):
			return corrupt
		rally_rounds = int(data.rally_rounds)
		rally_cooldown = int(data.rally_cooldown)
		if rally_rounds > 0 and rally_cooldown > 0:
			return corrupt
	# Files older than v8 predate Shield Wall: it loads ready.
	var shield_wall_rounds: int = 0
	var shield_wall_cooldown: int = 0
	if data.has("shield_wall_rounds"):
		if not ProgressSave._integer(data.shield_wall_rounds, 0, Campaign.SHIELD_WALL_ROUNDS) \
				or not ProgressSave._integer(data.shield_wall_cooldown, 0, Campaign.SHIELD_WALL_COOLDOWN):
			return corrupt
		shield_wall_rounds = int(data.shield_wall_rounds)
		shield_wall_cooldown = int(data.shield_wall_cooldown)
		if shield_wall_rounds > 0 and shield_wall_cooldown > 0:
			return corrupt
	var battle: Dictionary = data.battle
	if not _keys_exact(battle, BATTLE_KEYS_V1 if v1 else BATTLE_KEYS):
		return corrupt
	if typeof(data.settled) != TYPE_BOOL or typeof(data.cleared) != TYPE_ARRAY or data.cleared.size() != 3:
		return corrupt
	for flag in data.cleared:
		if typeof(flag) != TYPE_BOOL:
			return corrupt
	for key in ["gold", "gate_level", "dynasty", "phase", "mode", "farm_encounter",
			"pending_navigation", "pending_farm", "current_encounter", "round_progress_usec"]:
		if not ProgressSave._integer(data[key], -1, ProgressSave.MAX_GOLD):
			return corrupt
	for key in ["snapshot_gate_level", "gate_health", "rounds", "result", "defeat_reason"]:
		if not ProgressSave._integer(battle[key], 0, ProgressSave.MAX_GOLD):
			return corrupt
	var gold: int = int(data.gold)
	var gate_level: int = int(data.gate_level)
	var dynasty: int = int(data.dynasty)
	var phase: int = int(data.phase)
	var mode: int = int(data.mode)
	var farm: int = int(data.farm_encounter)
	var navigation: int = int(data.pending_navigation)
	var pending_farm: int = int(data.pending_farm)
	var encounter: int = int(data.current_encounter)
	var progress: int = int(data.round_progress_usec)
	var settled: bool = data.settled
	var cleared: Array[bool] = [data.cleared[0], data.cleared[1], data.cleared[2]]
	var snapshot_gate: int = int(battle.snapshot_gate_level)
	var gate_health: int = int(battle.gate_health)
	var rounds: int = int(battle.rounds)
	var result: int = int(battle.result)
	var reason: int = int(battle.defeat_reason)
	if dynasty < 1 or (v1 and dynasty > 2):
		return corrupt
	var secured: bool = phase == Campaign.Phase.CAMPAIGN_SECURED
	var legacy: int = 0
	var rank: int = 0
	var snapshot_rank: int = 0
	# v1/v2 predate Threat: every dynasty ran at Threat 0 and the old fixed ledger applies.
	var threat: int = 0
	var best: int = 0 if dynasty > 1 or secured else -1
	var earned: int = _legacy_earned(dynasty, secured)
	if v1:
		# The old free doctrine counts as Drill rank 1 bought with the first 10 Legacy.
		rank = dynasty - 1
		snapshot_rank = rank
		if phase == Campaign.Phase.CAMPAIGN_SECURED:
			legacy = _legacy_earned(dynasty, true) - _legacy_earned(dynasty, false)
	else:
		if not ProgressSave._integer(data.legacy, 0, ProgressSave.MAX_GOLD) \
				or not ProgressSave._integer(data.drill_rank, 0, Campaign.DRILL_MAX):
			return corrupt
		legacy = int(data.legacy)
		rank = int(data.drill_rank)
		if not ProgressSave._integer(battle.snapshot_drill_rank, 0, rank):
			return corrupt
		snapshot_rank = int(battle.snapshot_drill_rank)
	if not v1 and not v2:
		if not ProgressSave._integer(data.threat, 0, Campaign.THREAT_MAX) \
				or not ProgressSave._integer(data.best_threat, -1, Campaign.THREAT_MAX) \
				or not ProgressSave._integer(data.legacy_earned, 0, ProgressSave.MAX_GOLD):
			return corrupt
		threat = int(data.threat)
		best = int(data.best_threat)
		earned = int(data.legacy_earned)
		# Dynasty 1 is Threat 0 and unsecured means no best yet. Each dynasty picks at most one above
		# the best secured before it, and securing raises the best to at least its own Threat.
		if (dynasty == 1 and threat != 0) or (dynasty > 1 and best < 0) or (dynasty == 1 and not secured and best != -1) \
				or best > (dynasty - 1 if secured else dynasty - 2) \
				or (secured and best < threat) or (not secured and threat > best + 1):
			return corrupt
		var bounds := _earned_range(dynasty, secured, best)
		if earned < bounds[0] or earned > bounds[1]:
			return corrupt
	# Exact ledger: a hand-edited balance, rank or Veteran Cadre flag is corrupt.
	if legacy + _legacy_spent(rank) + (Campaign.VETERAN_CADRE_COST if cadre else 0) != earned:
		return corrupt
	if gold < 0 or gate_level < 1 or gate_level > 3 \
			or phase > Campaign.Phase.CAMPAIGN_SECURED or phase < 0 or mode < 0 or mode > Campaign.Mode.FARM \
			or navigation < 0 or navigation > Campaign.Navigation.FRONTIER or encounter not in ENCOUNTERS \
			or progress < 0 or progress >= ROUND_USEC or rounds > 60 \
			or result > Combat.Result.DEFEAT or reason > Combat.DefeatReason.TIMEOUT:
		return corrupt
	var levels: Variant = _ints(data.levels, 3, 1, 3)
	if levels == null:
		return corrupt
	var snapshot_levels: Variant = _ints(battle.snapshot_levels, 3, 1, 3)
	if snapshot_levels == null:
		return corrupt
	for role in range(3):
		if snapshot_levels[role] > levels[role]:
			return corrupt
	# Clearance is prefix-monotone; farm targets are cleared ordinary stages.
	if (cleared[1] and not cleared[0]) or (cleared[2] and not cleared[1]):
		return corrupt
	var farmable := func(stage: int) -> bool:
		return (stage == Data.Encounter.BORDER_SKIRMISH and cleared[0]) \
			or (stage == Data.Encounter.ARCHER_POSITION and cleared[1])
	if (farm != -1) != (mode == Campaign.Mode.FARM) or (farm != -1 and not farmable.call(farm)):
		return corrupt
	if (pending_farm != -1) != (navigation == Campaign.Navigation.FARM) \
			or (pending_farm != -1 and not farmable.call(pending_farm)):
		return corrupt
	# Battle health against snapshot-derived maxima: restoration can never heal.
	var army := _army(snapshot_levels, snapshot_rank)
	var enemies := Data.enemies(encounter, threat)
	var player_health: Variant = _ints(battle.player_health, 3, 0, ProgressSave.MAX_GOLD)
	var enemy_health: Variant = _ints(battle.enemy_health, enemies.size(), 0, ProgressSave.MAX_GOLD)
	if player_health == null or enemy_health == null:
		return corrupt
	var full: bool = true
	for i in range(3):
		if player_health[i] > army[i].max_health:
			return corrupt
		full = full and player_health[i] == army[i].max_health
	for i in range(enemies.size()):
		if enemy_health[i] > enemies[i].max_health:
			return corrupt
		full = full and enemy_health[i] == enemies[i].max_health
	var defense: bool = encounter == Data.Encounter.COUNTERATTACK
	if defense:
		if snapshot_gate < 1 or snapshot_gate > gate_level or gate_health > _gate_max(snapshot_gate):
			return corrupt
		full = full and gate_health == _gate_max(snapshot_gate)
		# Defense enemies strike only the shield squad; other squads never lose health.
		for i in range(3):
			if army[i].role != Data.Role.SHIELD and player_health[i] != army[i].max_health:
				return corrupt
	elif snapshot_gate != 0 or gate_health != 0:
		return corrupt
	# Result consistency mirrors Combat.step_round() terminal checks.
	var players_alive: bool = _any_alive(player_health)
	var enemies_alive: bool = _any_alive(enemy_health)
	if settled != (result != Combat.Result.ONGOING):
		return corrupt
	if rounds == 0 and (result != Combat.Result.ONGOING or not full):
		return corrupt
	match result:
		Combat.Result.ONGOING:
			if reason != Combat.DefeatReason.NONE or rounds >= 60 or not enemies_alive \
					or (defense and gate_health == 0) or (not defense and not players_alive):
				return corrupt
		Combat.Result.VICTORY:
			if reason != Combat.DefeatReason.NONE or enemies_alive \
					or (defense and gate_health == 0) or (not defense and not players_alive):
				return corrupt
		Combat.Result.DEFEAT:
			match reason:
				Combat.DefeatReason.ARMY_DEFEAT:
					if defense or players_alive:
						return corrupt
				Combat.DefeatReason.GATE_DESTROYED:
					if not defense or gate_health != 0:
						return corrupt
				Combat.DefeatReason.TIMEOUT:
					if rounds != 60 or not enemies_alive \
							or (defense and gate_health == 0) or (not defense and not players_alive):
						return corrupt
				_:
					return corrupt
	# Phase, mode and navigation combinations reachable through campaign.gd routing.
	var ongoing: bool = result == Combat.Result.ONGOING
	var frontier: int = -1
	for i in range(3):
		if not cleared[i]:
			frontier = Campaign.STAGES[i]
			break
	match phase:
		Campaign.Phase.RUNNING:
			if defense or not ongoing:
				return corrupt
			if navigation == Campaign.Navigation.FRONTIER and mode != Campaign.Mode.FARM:
				return corrupt
			if encounter != (farm if mode == Campaign.Mode.FARM else frontier):
				return corrupt
		Campaign.Phase.DEFENDING:
			if not defense or not ongoing or not cleared[2] or mode != Campaign.Mode.ADVANCE \
					or navigation == Campaign.Navigation.FRONTIER:
				return corrupt
		Campaign.Phase.CONQUEST_CLEARED:
			if defense or ongoing or not cleared[2] or mode != Campaign.Mode.ADVANCE \
					or navigation != Campaign.Navigation.NONE \
					or (encounter == Data.Encounter.STRONGHOLD and result != Combat.Result.VICTORY):
				return corrupt
		Campaign.Phase.CAMPAIGN_SECURED:
			if not defense or result != Combat.Result.VICTORY or not cleared[2] \
					or mode != Campaign.Mode.ADVANCE or navigation != Campaign.Navigation.NONE:
				return corrupt
	if progress != 0 and phase not in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING]:
		return corrupt
	# A stored loss cause exists only after a lost defense and before the next one starts.
	if last_loss != Combat.DefeatReason.NONE and (not cleared[2]
			or phase not in [Campaign.Phase.RUNNING, Campaign.Phase.CONQUEST_CLEARED]):
		return corrupt
	# An active Rally needs an ongoing battle old enough to hold every boosted round already used.
	if rally_rounds > 0 and (phase not in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING]
			or rounds < Campaign.RALLY_ROUNDS - rally_rounds):
		return corrupt
	# The same rule for an active Shield Wall.
	if shield_wall_rounds > 0 and (phase not in [Campaign.Phase.RUNNING, Campaign.Phase.DEFENDING]
			or rounds < Campaign.SHIELD_WALL_ROUNDS - shield_wall_rounds):
		return corrupt
	return {"outcome": Outcome.VALID, "gold": gold, "levels": levels, "gate_level": gate_level,
		"dynasty": dynasty, "legacy": legacy, "rank": rank, "cadre": cadre, "snapshot_rank": snapshot_rank,
		"threat": threat, "best": best, "earned": earned,
		"cleared": cleared, "phase": phase, "mode": mode, "farm": farm,
		"navigation": navigation, "pending_farm": pending_farm, "encounter": encounter,
		"settled": settled, "progress": progress, "saved_at": saved_at, "last_loss": last_loss,
		"rally_rounds": rally_rounds, "rally_cooldown": rally_cooldown,
		"shield_wall_rounds": shield_wall_rounds, "shield_wall_cooldown": shield_wall_cooldown,
		"snapshot_levels": snapshot_levels,
		"player_health": player_health, "enemy_health": enemy_health,
		"snapshot_gate": snapshot_gate, "gate_health": gate_health, "rounds": rounds,
		"result": result, "reason": reason}

# Builds a new Campaign; no existing object is touched, so a rejection mutates nothing.
static func restore(state: Variant) -> Dictionary:
	var parsed := _parse(state)
	if parsed.outcome != Outcome.VALID:
		return {"outcome": parsed.outcome}
	var campaign := Campaign.new()
	campaign.gold = parsed.gold
	campaign.levels.assign(parsed.levels)
	campaign.gate_level = parsed.gate_level
	campaign.dynasty = parsed.dynasty
	campaign.legacy = parsed.legacy
	campaign.drill_rank = parsed.rank
	campaign.veteran_cadre = parsed.cadre
	campaign._battle_drill_rank = parsed.snapshot_rank
	campaign.threat = parsed.threat
	campaign.best_threat = parsed.best
	campaign.legacy_earned = parsed.earned
	campaign.border_cleared = parsed.cleared[0]
	campaign.archer_cleared = parsed.cleared[1]
	campaign.stronghold_cleared = parsed.cleared[2]
	campaign.phase = parsed.phase as Campaign.Phase
	campaign.mode = parsed.mode as Campaign.Mode
	campaign.farm_encounter = parsed.farm
	campaign.pending_navigation = parsed.navigation as Campaign.Navigation
	campaign.pending_farm = parsed.pending_farm
	campaign.current_encounter = parsed.encounter
	campaign.last_defense_loss = parsed.last_loss
	campaign.rally_rounds = parsed.rally_rounds
	campaign.rally_cooldown = parsed.rally_cooldown
	campaign.shield_wall_rounds = parsed.shield_wall_rounds
	campaign.shield_wall_cooldown = parsed.shield_wall_cooldown
	# Snapshot stats and commander damage are re-derived; the snapshot Drill rank applies exactly once.
	var combat := Combat.new(parsed.encounter as Data.Encounter, _army(parsed.snapshot_levels, parsed.snapshot_rank),
		parsed.threat)
	if combat.is_defense:
		combat.gate_max_health = _gate_max(parsed.snapshot_gate)
		combat.gate_health = parsed.gate_health
	for i in range(combat.players.size()):
		combat.players[i].health = parsed.player_health[i]
	for i in range(combat.enemies.size()):
		combat.enemies[i].health = parsed.enemy_health[i]
	combat.rounds = parsed.rounds
	combat.result = parsed.result as Combat.Result
	combat.defeat_reason = parsed.reason as Combat.DefeatReason
	campaign.battle = combat
	campaign._settled = parsed.settled
	campaign._battle_reward = campaign.encounter_reward(parsed.encounter)
	return {"outcome": Outcome.VALID, "campaign": campaign, "round_progress_usec": parsed.progress,
		"saved_at": parsed.saved_at}
