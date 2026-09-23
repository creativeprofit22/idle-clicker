extends RefCounted

# Campaign storage (contract v1, D9/D11). Mirrors Save-v1's stage/verify/rotate algorithm
# in a separate file; Save-v1 (progress_save.gd) is reused only for static helpers.
const Campaign = preload("res://src/campaign.gd")
const CampaignState = preload("res://src/campaign_state.gd")
const ProgressSave = preload("res://src/progress_save.gd")

enum Outcome { MISSING, LOADED, CORRUPT, UNSUPPORTED, IO_FAILURE }
const FILE_NAME: String = "campaign.json"

var path: String
var _loaded: bool = false
var _preservation_outcome: Outcome = Outcome.MISSING

func _init(trusted_path: String = "user://campaign.json") -> void:
	path = trusted_path

func get_preservation_outcome() -> Outcome:
	return _preservation_outcome

# Isolation guard: this store may only ever touch campaign.json{,.tmp,.bak}.
func _path_allowed() -> bool:
	return path.get_file() == FILE_NAME

func _read(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		return {"outcome": Outcome.MISSING if error == ERR_FILE_NOT_FOUND and not DirAccess.dir_exists_absolute(source) else Outcome.IO_FAILURE}
	var length := file.get_length()
	if length == 0 or length > ProgressSave.MAX_BYTES:
		file.close()
		return {"outcome": Outcome.CORRUPT}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if error != OK or bytes.size() != length:
		return {"outcome": Outcome.IO_FAILURE}
	var text := bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"outcome": Outcome.CORRUPT}
	var restored := CampaignState.restore(json.data)
	match restored.outcome:
		CampaignState.Outcome.UNSUPPORTED:
			return {"outcome": Outcome.UNSUPPORTED}
		CampaignState.Outcome.VALID:
			if not ProgressSave._exact_numbers(text):
				return {"outcome": Outcome.CORRUPT}
			return {"outcome": Outcome.LOADED, "campaign": restored.campaign,
				"round_progress_usec": restored.round_progress_usec}
	return {"outcome": Outcome.CORRUPT}

# The canonical state of a loaded result, for exact comparisons.
static func _state_of(result: Dictionary) -> Variant:
	if result.outcome != Outcome.LOADED:
		return null
	var captured := CampaignState.capture(result.campaign, result.round_progress_usec)
	return captured.state if captured.outcome == CampaignState.Outcome.VALID else null

# D11: a missing primary falls back to the backup; any other primary failure is reported
# as-is (no backup bypass) and disables saving for this launch.
func load_campaign() -> Dictionary:
	if not _path_allowed():
		_loaded = true
		_preservation_outcome = Outcome.IO_FAILURE
		return {"outcome": Outcome.IO_FAILURE}
	var result := _read(path)
	if result.outcome == Outcome.MISSING:
		var backup := _read(path + ".bak")
		if backup.outcome != Outcome.MISSING:
			result = backup
			if result.outcome == Outcome.LOADED:
				result["recovered"] = true
	_loaded = true
	_preservation_outcome = result.outcome
	return result

# Narrow I/O seams allow deterministic disk-full/flush and move failure tests.
func _write_stage(destination: String, text: String) -> Error:
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	var error := file.get_error()
	if error == OK:
		file.flush()
		error = file.get_error()
	file.close()
	return error

func _move(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)

# Returns OK only once the new snapshot is the primary. Never overwrites an invalid file.
func save_campaign(campaign: Campaign, round_progress_usec: int) -> Error:
	if not _path_allowed():
		return ERR_UNAUTHORIZED
	if not _loaded:
		load_campaign()
	if _preservation_outcome not in [Outcome.MISSING, Outcome.LOADED]:
		return ERR_UNAUTHORIZED
	var captured := CampaignState.capture(campaign, round_progress_usec)
	if captured.outcome != CampaignState.Outcome.VALID:
		return ERR_INVALID_DATA
	var state: Dictionary = captured.state
	var current := _read(path)
	# An accepted session retries transient reads before staging any later snapshot.
	if current.outcome == Outcome.IO_FAILURE:
		return ERR_FILE_CANT_READ
	if current.outcome not in [Outcome.MISSING, Outcome.LOADED]:
		_preservation_outcome = current.outcome
		return ERR_UNAUTHORIZED
	var previous: Variant = _state_of(current)
	if current.outcome == Outcome.LOADED and previous == null:
		return ERR_FILE_CORRUPT
	var staged: String = path + ".tmp"
	var error := _write_stage(staged, JSON.stringify(state))
	if error != OK:
		return error
	if _state_of(_read(staged)) != state:
		return ERR_FILE_CORRUPT
	# simplification: one running instance only; add writer locking before multi-instance support.
	# No fsync: durability is bounded to what the OS flushes (contract D8).
	# Windows rename deletes an existing destination. Rotate first; never overwrite the primary.
	# A crash between moves leaves a validated backup, not a crash-atomic primary.
	if current.outcome == Outcome.LOADED:
		error = _move(path, path + ".bak")
		if error != OK:
			return error
		if _state_of(_read(path + ".bak")) != previous:
			return ERR_FILE_CORRUPT
	error = _move(staged, path)
	if error != OK and _read(path).outcome == Outcome.MISSING:
		# Keep the backup even if restoration fails; next launch reads it.
		var backup_state: Variant = _state_of(_read(path + ".bak"))
		if backup_state != null:
			var restore_error := _write_stage(staged, JSON.stringify(backup_state))
			if restore_error == OK and _state_of(_read(staged)) == backup_state:
				_move(staged, path)
	return error
