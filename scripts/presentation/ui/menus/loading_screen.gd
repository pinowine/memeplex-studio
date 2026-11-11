extends CanvasLayer

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")

var _label: Label
var _activity: ProgressBar
var _resources: Array[Resource] = []
var _stage := "LOC_LOADING"
var _loaded_resources := -1
var _resource_count := 0
var _stage_started := 0

func _ready() -> void:
	layer = 100
	var background := ColorRect.new()
	background.color = Style.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	background.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	content.offset_left = -160
	content.offset_right = 160
	content.offset_top = -32
	content.offset_bottom = 32
	_label = Label.new()
	_label.text = tr(_stage)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Style.INK)
	content.add_child(_label)
	_activity = ProgressBar.new()
	_activity.custom_minimum_size.y = 4
	_activity.show_percentage = false
	_activity.indeterminate = true
	for slot: String in ["background", "fill"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Style.EDGE if slot == "background" else Style.INK
		_activity.add_theme_stylebox_override(slot, box)
	content.add_child(_activity)

func set_stage(key: String) -> void:
	if _stage == key: return
	var now := Time.get_ticks_msec()
	if _stage_started > 0:
		print("LOAD_STAGE stage=%s duration_ms=%d" % [_stage, now - _stage_started])
	_stage_started = now
	_stage = key
	_loaded_resources = -1
	_resource_count = 0
	_activity.indeterminate = true
	_activity.value = 0
	_refresh_label()

func present(key: String = "LOC_LOADING") -> void:
	set_stage(key)
	if _stage_started == 0: _stage_started = Time.get_ticks_msec()
	_activity.show()
	show()
	await RenderingServer.frame_post_draw

func finish() -> void:
	print("LOAD_STAGE stage=%s duration_ms=%d" % [_stage, Time.get_ticks_msec() - _stage_started])
	_stage_started = 0
	hide()

func load_resources(paths: PackedStringArray) -> Error:
	set_stage("LOC_LOADING_ASSETS")
	_loaded_resources = 0
	_resource_count = paths.size()
	_activity.indeterminate = false
	_refresh_label()
	await RenderingServer.frame_post_draw
	for path: String in paths:
		var error := ResourceLoader.load_threaded_request(path)
		if error != OK:
			push_error("Cannot queue resource: " + path)
			return error
	while _loaded_resources < _resource_count:
		_loaded_resources = 0
		var progress := 0.0
		for path: String in paths:
			var resource_progress: Array = []
			var status := ResourceLoader.load_threaded_get_status(path, resource_progress)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_loaded_resources += 1
				progress += 1.0
			elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if not resource_progress.is_empty(): progress += float(resource_progress[0])
			else:
				push_error("Cannot load resource: " + path)
				return ERR_CANT_OPEN
		_activity.value = 100.0 * progress / _resource_count
		_refresh_label()
		if _loaded_resources < _resource_count: await get_tree().process_frame
	for path: String in paths:
		_resources.append(ResourceLoader.load_threaded_get(path))
	return OK

func prepare_rendering() -> void:
	var compilations := _pipeline_compilations()
	var initial_compilations := compilations
	await present("LOC_LOADING_RENDERING")
	while _pipeline_compilations() > compilations:
		compilations = _pipeline_compilations()
		await present("LOC_LOADING_SHADERS")
	print("LOAD_RENDER new_pipelines=%d" % (compilations - initial_compilations))

func _pipeline_compilations() -> int:
	var count := 0
	for kind in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW]:
		count += RenderingServer.get_rendering_info(kind)
	return count

func fail() -> void:
	set_stage("LOC_LOADING_FAILED")
	_activity.hide()
	show()

func _refresh_label() -> void:
	var text := tr(_stage)
	if _loaded_resources >= 0:
		text += " %d/%d" % [_loaded_resources, _resource_count]
	_label.text = text

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_label):
		_refresh_label()

func _input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()
