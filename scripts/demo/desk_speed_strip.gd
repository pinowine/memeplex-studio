class_name DeskSpeedStrip
extends Control

signal speed_requested(value: int)

const ART_PATH := "res://assets/desk/v4/speed_strip.png"
const SOURCE_SIZE := Vector2(2058, 764)
const KEY_RECTS := [Rect2(271, 160, 445, 402), Rect2(799, 160, 447, 402), Rect2(1337, 160, 447, 402)]

var _buttons: Array[Button] = []
var _paper: TextureRect
var _speed := 0
var _feedback: Array[KeyFeedback] = []

class KeyFeedback extends Control:
	var key: Button
	var hover := 0.0
	var press := 0.0
	var pulse := 0.0
	var held := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if key == null: return
		var active := not key.disabled
		var wanted_hover := 1.0 if active and key.is_hovered() else 0.0
		var wanted_press := 1.0 if active and held else 0.0
		hover = move_toward(hover, wanted_hover, delta * 10.0)
		press = move_toward(press, wanted_press, delta * 16.0)
		pulse = maxf(0.0, pulse - delta * 3.5) if active else 0.0
		if not active: held = false
		queue_redraw()

	func _draw() -> void:
		var strength := maxf(press, pulse * .45)
		var outline := Color(.18, .25, .16, hover * .42 + strength * .4)
		var inset := 2.0 + strength
		var rect := Rect2(Vector2.ONE * inset, (size - Vector2.ONE * inset * 2).max(Vector2.ZERO))
		draw_style_box(_style(outline, hover, strength), rect)

	func _style(outline: Color, hovered: float, pressed: float) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.28, .35, .2, hovered * .04 + pressed * .09)
		style.border_color = outline
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		return style

	func inspection() -> Dictionary:
		return {"hover":hover,"press":press,"pulse":pulse,"held":held,
			"hovered":not key.disabled and key.is_hovered(),"disabled":key.disabled}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper = TextureRect.new()
	_paper.name = "PrintedSpeedPlate"
	_paper.texture = load(ART_PATH)
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_paper)
	var row := Control.new()
	row.name = "ThreeSpeeds"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	for index in 3:
		var button := Button.new()
		button.name = ["Pause", "Normal", "Fast"][index]
		button.text = ""
		button.tooltip_text = ""
		button.toggle_mode = true
		button.icon = load("res://assets/desk/v4/icons/" + ["pause", "play", "fast_forward"][index] + ".svg")
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 14)
		button.add_theme_constant_override("h_separation", 3)
		button.add_theme_color_override("icon_normal_color", Color("353a2e"))
		button.add_theme_color_override("icon_pressed_color", Color("192218"))
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color("353a2e"))
		button.add_theme_color_override("font_pressed_color", Color("192218"))
		button.add_theme_color_override("font_disabled_color", Color("727364"))
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.20, 0.29, 0.18, 0.24) if state == "pressed" else Color(0.20, 0.29, 0.18, 0.10 if state == "hover" else 0.0)
			style.border_color = Color(0.20, 0.29, 0.18, 0.7)
			style.set_border_width_all(1 if state in ["pressed", "focus"] else 0)
			style.set_corner_radius_all(3)
			style.set_content_margin_all(0)
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(_request.bind(index))
		row.add_child(button)
		_buttons.append(button)
		var feedback := KeyFeedback.new()
		feedback.name = "KeyFeedback"
		feedback.key = button
		button.add_child(feedback)
		_feedback.append(feedback)
		button.button_down.connect(func() -> void: feedback.held = true)
		button.button_up.connect(func() -> void: feedback.held = false)
		button.pressed.connect(func() -> void: feedback.pulse = 1.0)
	resized.connect(_layout_buttons)
	_layout_buttons()
	sync(0, false)


func _layout_buttons() -> void:
	if _buttons.is_empty(): return
	var factor := minf(size.x / SOURCE_SIZE.x, size.y / SOURCE_SIZE.y)
	var origin := (size - SOURCE_SIZE * factor) * 0.5
	for index in _buttons.size():
		# Match hit areas to the keycaps, excluding transparent margins.
		_buttons[index].position = origin + KEY_RECTS[index].position * factor
		_buttons[index].size = KEY_RECTS[index].size * factor


func _request(value: int) -> void:
	speed_requested.emit(value)
	# Selection follows the accepted simulation state, not the tentative click.
	sync(_speed, not _buttons[0].disabled)


func sync(value: int, enabled: bool) -> void:
	_speed = clampi(value, 0, 2)
	for index in _buttons.size():
		_buttons[index].set_pressed_no_signal(index == _speed)
		_buttons[index].disabled = not enabled


func background_node() -> TextureRect:
	return _paper


func inspection() -> Dictionary:
	var keys: Array[Dictionary] = []
	var feedback: Array[Dictionary] = []
	var hovered := -1
	for index in _feedback.size():
		var state := _feedback[index].inspection()
		feedback.append(state)
		if state.hovered: hovered = index
	for button in _buttons:
		keys.append({"name":button.name,"rect":button.get_global_rect(),"pressed":button.button_pressed,"disabled":button.disabled})
	return {"component":"independent_three_speed_strip", "speed":_speed,
		"enabled":not _buttons.is_empty() and not _buttons[0].disabled,
		"button_count":_buttons.size(), "rect":get_global_rect(), "parent":str(get_parent().get_path()),
		"art_path":ART_PATH,"source_size":SOURCE_SIZE,"key_source_rects":KEY_RECTS,"keys":keys,
		"hovered":hovered,"feedback":feedback,"feedback_scope":"individual_keys","wholeplate_animation":false}

