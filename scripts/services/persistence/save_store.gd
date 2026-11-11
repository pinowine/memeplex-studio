class_name MemeDemoStore
extends RefCounted

var last_errors := PackedStringArray()

func startup_world_seed(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary: return -1
	var competition: Variant = json.data.get("competition_state")
	if not competition is Dictionary: return -1
	var seed: Variant = competition.get("world_seed")
	if not (seed is int or seed is float): return -1
	if not is_finite(float(seed)) or float(seed) < 0.0 or float(seed) != floorf(float(seed)): return -1
	return int(seed)

func save_run(simulation: MemeDemoSimulation, path: String) -> Error:
	last_errors.clear()
	var data := simulation.payload()
	last_errors = simulation.validate_payload(data)
	if not last_errors.is_empty(): return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return error
	var temporary := absolute + ".tmp.%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", false, true))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		# 完整写入后才替换正式存档；替换失败时原文件保持不变。
		error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		last_errors.append(DeskLocalization.source("LOC_FAILED_TO_WRITE_OR_REPLACE_THE_SAVE_E43EEC87") + error_string(error))
		var cleanup := DirAccess.remove_absolute(temporary)
		if cleanup != OK: last_errors.append(DeskLocalization.source("LOC_FAILED_TO_REMOVE_THE_TEMPORARY_SAVE_5892833F") + error_string(cleanup))
	return error

func load_run(simulation: MemeDemoSimulation, path: String) -> Error:
	last_errors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		last_errors.append(DeskLocalization.source("LOC_SAVE_IS_NOT_A_VALID_JSON_OBJECT_5324AFC6"))
		return ERR_PARSE_ERROR
	last_errors = simulation.restore(json.data)
	return OK if last_errors.is_empty() else ERR_INVALID_DATA
