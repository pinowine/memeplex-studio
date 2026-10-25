class_name MemeDemoStore
extends RefCounted

var last_errors := PackedStringArray()

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
		last_errors.append("存档写入或替换失败：" + error_string(error))
		var cleanup := DirAccess.remove_absolute(temporary)
		if cleanup != OK: last_errors.append("临时存档清理失败：" + error_string(cleanup))
	return error

func load_run(simulation: MemeDemoSimulation, path: String) -> Error:
	last_errors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		last_errors.append("存档不是有效的 JSON 对象。")
		return ERR_PARSE_ERROR
	last_errors = simulation.restore(json.data)
	return OK if last_errors.is_empty() else ERR_INVALID_DATA
