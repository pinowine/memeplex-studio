extends CanvasLayer

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")

var _label: Label
var _activity: ProgressBar
var _resources: Array[Resource] = []

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
	_label.text = "LOC_LOADING"
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

func present() -> void:
	_label.text = "LOC_LOADING"
	_activity.show()
	show()
	await RenderingServer.frame_post_draw

func load_resources(paths: PackedStringArray) -> Error:
	for path: String in paths:
		var error := ResourceLoader.load_threaded_request(path)
		if error != OK:
			push_error("Cannot queue resource: " + path)
			return error
	for path: String in paths:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("Cannot load resource: " + path)
			return ERR_CANT_OPEN
		_resources.append(ResourceLoader.load_threaded_get(path))
	return OK

func fail() -> void:
	_label.text = "LOC_LOADING_FAILED"
	_activity.hide()
	show()

func _input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()
