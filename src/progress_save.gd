extends RefCounted

const MAX_GOLD: int = 9007199254740991
const MAX_BYTES: int = 4096
enum Outcome { MISSING, LOADED, CORRUPT, UNSUPPORTED, IO_FAILURE }

var path: String
var _loaded: bool = false
var _preservation_outcome: Outcome = Outcome.MISSING

func get_preservation_outcome() -> Outcome:
	return _preservation_outcome

func _init(trusted_path: String = "user://progress.json") -> void:
	path = trusted_path

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and floor(value) == value

static func _validate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not data.has("version"):
		return {"outcome": Outcome.CORRUPT}
	if not _integer(data.version, 0, MAX_GOLD):
		return {"outcome": Outcome.CORRUPT}
	if data.version != 1:
		return {"outcome": Outcome.UNSUPPORTED}
	if data.size() != 3 or not data.has("gold") or not data.has("levels"):
		return {"outcome": Outcome.CORRUPT}
	if not _integer(data.gold, 0, MAX_GOLD) or typeof(data.levels) != TYPE_ARRAY or data.levels.size() != 3:
		return {"outcome": Outcome.CORRUPT}
	var levels: Array[int] = []
	for level in data.levels:
		if not _integer(level, 1, 3):
			return {"outcome": Outcome.CORRUPT}
		levels.append(int(level))
	return {"outcome": Outcome.LOADED, "gold": int(data.gold), "levels": levels}

static func _exact_numbers(text: String) -> bool:
	# JSON uses doubles: reject fractions that would round into apparently valid integers.
	# Skip quoted keys; schema validation has already rejected string values.
	var tokens := RegEx.new()
	tokens.compile(r'"(?:\\.|[^"\\])*"|(-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)')
	for token in tokens.search_all(text):
		var number: String = token.get_string(1)
		if number.is_empty():
			continue
		var parts := number.to_lower().trim_prefix("-").split("e")
		var mantissa: String = parts[0]
		var digits := mantissa.replace(".", "")
		while digits.begins_with("0"):
			digits = digits.substr(1)
		if digits.is_empty():
			continue
		var exponent: float = parts[1].to_float() if parts.size() == 2 else 0.0
		if not is_finite(exponent) or absf(exponent) > MAX_BYTES:
			return false
		var scale: int = int(exponent) - (mantissa.length() - mantissa.find(".") - 1 if mantissa.contains(".") else 0)
		while scale < 0 and digits.ends_with("0"):
			digits = digits.left(-1)
			scale += 1
		if scale < 0 or digits.length() + scale > 16:
			return false
		if (digits + "0".repeat(scale)).to_int() > MAX_GOLD:
			return false
	return true

func _read(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		return {"outcome": Outcome.MISSING if error == ERR_FILE_NOT_FOUND and not DirAccess.dir_exists_absolute(source) else Outcome.IO_FAILURE}
	var length := file.get_length()
	if length == 0 or length > MAX_BYTES:
		file.close()
		return {"outcome": Outcome.CORRUPT}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if error != OK or bytes.size() != length:
		return {"outcome": Outcome.IO_FAILURE}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {"outcome": Outcome.CORRUPT}
	var result := _validate(json.data)
	if result.outcome == Outcome.LOADED and not _exact_numbers(bytes.get_string_from_utf8()):
		return {"outcome": Outcome.CORRUPT}
	return result

func load_progress() -> Dictionary:
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

func save_progress(gold: int, levels: Array[int]) -> Error:
	if not _loaded:
		load_progress()
	if _preservation_outcome not in [Outcome.MISSING, Outcome.LOADED]:
		return ERR_UNAUTHORIZED
	var snapshot := _validate({"version": 1, "gold": gold, "levels": levels})
	if snapshot.outcome != Outcome.LOADED:
		return ERR_INVALID_DATA
	var current := _read(path)
	# An accepted session retries transient reads before staging any later snapshot.
	if current.outcome == Outcome.IO_FAILURE:
		return ERR_FILE_CANT_READ
	if current.outcome not in [Outcome.MISSING, Outcome.LOADED]:
		_preservation_outcome = current.outcome
		return ERR_UNAUTHORIZED
	var staged: String = path + ".tmp"
	var error := _write_stage(staged, JSON.stringify({"version": 1, "gold": gold, "levels": levels}))
	if error != OK:
		return error
	var verified := _read(staged)
	if verified.outcome != Outcome.LOADED or verified.gold != gold or verified.levels != levels:
		return ERR_FILE_CORRUPT
	# simplification: one running instance only; add writer locking before multi-instance support.
	# Windows rename deletes an existing destination. Rotate first; never overwrite the primary.
	# A crash between moves leaves a validated backup, not a crash-atomic primary.
	if current.outcome == Outcome.LOADED:
		error = _move(path, path + ".bak")
		if error != OK:
			return error
		var backup := _read(path + ".bak")
		if backup.outcome != Outcome.LOADED or backup.gold != current.gold or backup.levels != current.levels:
			return ERR_FILE_CORRUPT
	error = _move(staged, path)
	if error != OK and _read(path).outcome == Outcome.MISSING:
		# Keep the backup even if restoration fails; next launch reads it.
		var backup := _read(path + ".bak")
		if backup.outcome == Outcome.LOADED:
			var restore_error := _write_stage(staged, JSON.stringify({"version": 1, "gold": backup.gold, "levels": backup.levels}))
			if restore_error == OK and _read(staged) == backup:
				_move(staged, path)
	return error
