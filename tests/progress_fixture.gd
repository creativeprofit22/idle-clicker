extends RefCounted

var directory: String
var path: String
var owned: bool = false

func _init() -> void:
	directory = "user://progress-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	owned = DirAccess.make_dir_absolute(directory) == OK
	path = directory.path_join("progress.json")

func put(text: String, suffix: String = "") -> Error:
	if not owned:
		return ERR_UNAUTHORIZED
	var file := FileAccess.open(path + suffix, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func cleanup() -> Error:
	if not owned:
		return ERR_UNAUTHORIZED
	# Only this freshly-created directory and these test-owned entries may be removed.
	for suffix in ["", ".tmp", ".bak"]:
		var entry: String = path + suffix
		if FileAccess.file_exists(entry) or DirAccess.dir_exists_absolute(entry):
			var error := DirAccess.remove_absolute(entry)
			if error != OK:
				return error
	var error := DirAccess.remove_absolute(directory)
	if error == OK:
		owned = false
	return error
