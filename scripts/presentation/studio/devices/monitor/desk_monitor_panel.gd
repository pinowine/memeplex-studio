class_name DeskMonitorPanel
extends Control

signal token_released(token_id: String, viewport_point: Vector2)
signal mode_changed(mode_id: String)

const MemeScreen := preload("res://scripts/presentation/studio/devices/monitor/desk_meme_monitor.gd")
const TokenGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const InventoryScreen := preload("res://scripts/presentation/studio/devices/monitor/desk_crt_inventory_screen.gd")
const BUTTON_ART := "res://assets/image/textures/studio/desk/monitor_keys_inset.png"
const BUTTON_ART_REGION := Rect2(320, 215, 1345, 400)
const KEY_FACES := [Rect2(18, 15, 395, 370), Rect2(480, 15, 395, 370), Rect2(940, 15, 395, 370)]
const MODES := ["meme", "stance", "pragmatic"]
const TOKEN_IDS := {
	"stance": ["freedom", "authority", "equality", "hierarchy"],
	"pragmatic": ["sincere", "ironic", "support", "opposition"]
}

@export var font_size: int = 13
@export var screen_padding: float = 10.0
@export var curve_height: float = 52.0

var _meme: Control
var _inventory: Control
var _button_art: TextureRect
var _buttons: Array[Button] = []
var _feedback: Array[ModeKeyInk] = []
var _rules: Resource
var _mode := "meme"
var _balances: Dictionary = {}
var _enabled := true
var _token_enabled := true
var _screen_rect := Rect2()
var _buttons_rect := Rect2()
var _key_rects: Array[Rect2] = []
var _pressed := false
var _dragging := false
var _drag_id := ""
var _press_point := Vector2.ZERO
var _preview: Control
var _release_count := 0
var _cancel_count := 0
var _mode_change_count := 0

class ModeKeyInk extends Control:
	var key: Button
	var mode_id := "meme"
	var hover := 0.0
	var press := 0.0
	var pulse := 0.0
	var held := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if key == null: return
		hover = move_toward(hover, 1.0 if not key.disabled and key.is_hovered() else 0.0, delta * 10.0)
		press = move_toward(press, 1.0 if not key.disabled and held else 0.0, delta * 16.0)
		pulse = maxf(0.0, pulse - delta * 3.5)
		if key.disabled: held = false
		queue_redraw()

	func _draw() -> void:
		var selected := key != null and key.button_pressed
		var strength := maxf(press, pulse * 0.45)
		var border := Color(0.18, 0.25, 0.16, hover * 0.52 + strength * 0.4 + (0.3 if selected else 0.0))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.20, 0.29, 0.18, hover * 0.04 + strength * 0.09 + (0.10 if selected else 0.0))
		style.border_color = border
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		draw_style_box(style, Rect2(Vector2.ONE * 2.0, (size - Vector2.ONE * 4.0).max(Vector2.ZERO)))
		var center := size * 0.5 + Vector2(0, 1.5 if selected else strength)
		var radius := minf(size.x, size.y) * 0.24
		var ink := Color("283323") if not key.disabled else Color("727364")
		var width := maxf(1.0, radius * 0.12)
		match mode_id:
			"meme":
				draw_arc(center, radius * 0.90, -PI * 0.9, PI * 0.6, 24, ink, width, true)
				draw_polyline(PackedVector2Array([center + Vector2(-0.5, 0.72) * radius, center + Vector2(-0.7, 1.10) * radius, center + Vector2(0.06, 0.91) * radius]), ink, width, true)
				for x in [-0.35, 0.35]: draw_circle(center + Vector2(x, -0.12) * radius, width, ink)
			"stance":
				draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), ink, width, true)
				draw_line(center + Vector2(0, radius), center - Vector2(0, radius), ink, width, true)
				draw_polyline(PackedVector2Array([center + Vector2(0.55, -0.35) * radius, center + Vector2(1, 0) * radius, center + Vector2(0.55, 0.35) * radius]), ink, width, true)
				draw_polyline(PackedVector2Array([center + Vector2(-0.35, -0.55) * radius, center + Vector2(0, -1) * radius, center + Vector2(0.35, -0.55) * radius]), ink, width, true)
			"pragmatic":
				draw_arc(center, radius, 0, TAU, 28, ink, width, true)
				for x in [-0.35, 0.35]: draw_circle(center + Vector2(x, -0.3) * radius, width, ink)
				draw_arc(center + Vector2(0, 0.04) * radius, radius * 0.57, 0.12, PI - 0.12, 16, ink, width, true)

	func inspection() -> Dictionary:
		return {"hover":hover, "press":press, "pulse":pulse, "held":held, "hovered":key != null and key.is_hovered(), "selected":key != null and key.button_pressed}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_meme = MemeScreen.new()
	_meme.name = "MemeBalanceSnapshots"
	add_child(_meme)
	_inventory = InventoryScreen.new()
	_inventory.name = "FourDirectionInventory"
	_inventory.token_pressed.connect(_begin_token)
	add_child(_inventory)
	_button_art = TextureRect.new()
	_button_art.name = "WeldedModeButtons"
	_button_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_button_art.stretch_mode = TextureRect.STRETCH_SCALE
	_button_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BUTTON_ART):
		# The generated source has large transparent margins. Crop those margins,
		# not the socket rims, so the keys fill the monitor's lower metalwork.
		var sockets := AtlasTexture.new()
		sockets.atlas = load(BUTTON_ART)
		sockets.region = BUTTON_ART_REGION
		_button_art.texture = sockets
	add_child(_button_art)
	for index in MODES.size():
		var button := Button.new()
		button.name = str(MODES[index]).to_pascal_case() + "Mode"
		button.text = ""
		button.tooltip_text = ""
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_select_button.bind(index))
		_button_art.add_child(button)
		_buttons.append(button)
		var feedback := ModeKeyInk.new()
		feedback.name = "ModeIconAndEdge"
		feedback.key = button
		feedback.mode_id = MODES[index]
		button.add_child(feedback)
		_feedback.append(feedback)
		button.button_down.connect(func() -> void: feedback.held = true)
		button.button_up.connect(func() -> void: feedback.held = false)
		button.pressed.connect(func() -> void: feedback.pulse = 1.0)
	_preview = TokenGraphic.new()
	_preview.name = "HeldContextToken"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.size = Vector2(48, 48)
	_preview.z_index = 99
	_preview.hide()
	add_child(_preview)
	resized.connect(_on_resized)
	get_window().focus_exited.connect(cancel_drag)
	get_viewport().size_changed.connect(cancel_drag)
	_layout()
	_refresh()

func configure(rules: Resource) -> void:
	_rules = rules

# Both rectangles are local to the machine. A camera transform moves the whole assembly.
func layout_console(screen_rect: Rect2, buttons_rect: Rect2, key_rects: Array[Rect2] = []) -> void:
	_screen_rect = screen_rect
	_buttons_rect = buttons_rect
	_key_rects = key_rects.duplicate()
	_layout()

func _layout() -> void:
	if _meme == null: return
	_meme.font_size = font_size
	_meme.screen_padding = screen_padding
	_meme.curve_height = curve_height
	_meme.layout_screen(_screen_rect)
	_inventory.position = _screen_rect.position
	_inventory.size = _screen_rect.size.max(Vector2.ZERO)
	_button_art.position = _buttons_rect.position
	_button_art.size = _buttons_rect.size.max(Vector2.ZERO)
	for index in _buttons.size():
		var source: Rect2 = KEY_FACES[index]
		var rect := _key_rects[index] if _key_rects.size() == 3 else Rect2(source.position / BUTTON_ART_REGION.size * _buttons_rect.size, source.size / BUTTON_ART_REGION.size * _buttons_rect.size)
		_buttons[index].position = rect.position
		_buttons[index].size = rect.size.max(Vector2.ZERO)
	queue_redraw()

func _on_resized() -> void:
	cancel_drag()
	_layout()

func sync_state(snapshot: Dictionary) -> void:
	if _meme == null: return
	_meme.sync_state(snapshot)
	var design: Variant = snapshot.get("design_state", snapshot)
	var source: Variant = design.get("context_token_balances", {}) if design is Dictionary else {}
	_balances.clear()
	for layer: String in TOKEN_IDS:
		for id: String in TOKEN_IDS[layer]:
			var value: Variant = source.get(id, 0) if source is Dictionary else 0
			var valid: bool = value is int and value >= 0
			if value is float:
				valid = is_finite(value) and value >= 0.0 and value == floor(value) and value < 9223372036854775807.0
			_balances[id] = int(value) if valid else 0
	if _pressed and int(_balances.get(_drag_id, 0)) == 0: cancel_drag()
	_refresh()

func reset_history() -> void:
	if _meme != null: _meme.reset_history()
	cancel_drag()

func screen_presentation() -> Dictionary:
	return {"mode":_mode, "meme":_meme.inspection() if _meme != null else {}, "balances":_balances.duplicate(true), "enabled":_enabled and _token_enabled}

func set_mode(id: String) -> bool:
	if id not in MODES: return false
	if _mode == id: return true
	cancel_drag()
	_mode = id
	_mode_change_count += 1
	_refresh()
	mode_changed.emit(_mode)
	return true

func mode() -> String:
	return _mode

func _select_button(index: int) -> void:
	if not _enabled: return
	set_mode(MODES[index])
	_refresh()

func set_interaction_enabled(value: bool) -> void:
	_enabled = value
	if not value: cancel_drag()
	_refresh()

func set_token_interaction_enabled(value: bool) -> void:
	_token_enabled = value
	if not value: cancel_drag()
	_refresh()

func _refresh() -> void:
	if _meme == null: return
	_meme.visible = _mode == "meme"
	_inventory.visible = _mode != "meme"
	_inventory.sync_inventory(_mode, _balances, _enabled and _token_enabled)
	for index in _buttons.size():
		_buttons[index].disabled = not _enabled
		_buttons[index].set_pressed_no_signal(MODES[index] == _mode)

func _begin_token(id: String, viewport_point: Vector2) -> void:
	if not _enabled or not _token_enabled or _mode == "meme" or int(_balances.get(id, 0)) <= 0: return
	cancel_drag()
	_pressed = true
	_drag_id = id
	_press_point = viewport_point
	var definition: Dictionary = _rules.context_resource(id) if _rules != null else {"id":id, "kind":"stance_token" if _mode == "stance" else "pragmatic_token", "title":id}
	_preview.configure(definition)

func _input(event: InputEvent) -> void:
	if not _pressed: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if not _enabled or not _token_enabled or event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			cancel_drag()
			return
		_dragging = _dragging or event.position.distance_to(_press_point) >= 6.0
		if _dragging:
			_preview.position = get_global_transform_with_canvas().affine_inverse() * event.position - _preview.size * 0.5
			_preview.show()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var released := _drag_id if _dragging else ""
		_clear_drag()
		if not released.is_empty():
			_release_count += 1
			# Only the existing design authority may validate or spend this token.
			token_released.emit(released, event.position)
		get_viewport().set_input_as_handled()

func _clear_drag() -> void:
	_pressed = false
	_dragging = false
	_drag_id = ""
	if is_instance_valid(_preview): _preview.hide()

func cancel_drag() -> void:
	if _pressed: _cancel_count += 1
	_clear_drag()

func inventory_viewport_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _inventory == null or _mode == "meme": return result
	var ids: Array = TOKEN_IDS[_mode]
	for index in 4:
		result.append({"id":ids[index], "count":int(_balances.get(ids[index], 0)), "rect":_inventory.get_global_transform_with_canvas() * _inventory.cell_rect(index), "index":index})
	return result

func interactive_viewport_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not _enabled: return result
	for button in _buttons:
		result.append(button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size))
	if _mode != "meme" and _token_enabled and _inventory != null:
		result.append(_inventory.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _inventory.size))
	return result

func handles_viewport_point(viewport_point: Vector2) -> bool:
	if not _enabled: return false
	for button in _buttons:
		var local := button.get_global_transform_with_canvas().affine_inverse() * viewport_point
		if Rect2(Vector2.ZERO, button.size).has_point(local): return true
	if _mode != "meme" and _token_enabled and _inventory != null:
		var local := _inventory.get_global_transform_with_canvas().affine_inverse() * viewport_point
		return Rect2(Vector2.ZERO, _inventory.size).has_point(local)
	return false

func hover_info(viewport_point: Vector2 = Vector2.INF) -> Dictionary:
	if viewport_point == Vector2.INF: viewport_point = get_viewport().get_mouse_position()
	for index in _buttons.size():
		var button := _buttons[index]
		var local := button.get_global_transform_with_canvas().affine_inverse() * viewport_point
		if Rect2(Vector2.ZERO, button.size).has_point(local):
			return {"kind":"monitor_mode", "id":MODES[index], "title":["Meme 点数", "政治点数", "语用点数"][index], "description":["查看余额与快照变化", "查看四个政治方向的可用点数", "查看四个语用方向的可用点数"][index]}
	if _mode == "meme" and _meme != null:
		return _meme.title_hover_info(viewport_point)
	if _mode != "meme" and _inventory != null:
		var local := _inventory.get_global_transform_with_canvas().affine_inverse() * viewport_point
		for index in 4:
			if _inventory.cell_rect(index).has_point(local):
				var id: String = TOKEN_IDS[_mode][index]
				var definition: Dictionary = _rules.context_resource(id) if _rules != null else {}
				return {"kind":"context_token", "id":id, "layer":_mode, "title":DeskLocalization.text(str(definition.get("title", id))), "count":int(_balances.get(id, 0)), "description":DeskLocalization.format_text("可用 %d；拖到对应坐标轴使用", int(_balances.get(id, 0)))}
	return {}

func inspection() -> Dictionary:
	var result: Dictionary = _meme.inspection() if _meme != null else {}
	var buttons: Array[Dictionary] = []
	for index in _buttons.size():
		var button := _buttons[index]
		buttons.append({"id":MODES[index], "text":button.text, "rect":button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size), "local_size":button.size, "selected":button.button_pressed, "disabled":button.disabled, "feedback":_feedback[index].inspection(), "parent":str(button.get_parent().get_path())})
	result.merge({"component":"machine_attached_monitor_console", "mode":_mode, "mode_ids":MODES.duplicate(), "mode_change_count":_mode_change_count, "enabled":_enabled, "token_enabled":_token_enabled, "buttons":buttons, "button_art":BUTTON_ART, "button_art_region":BUTTON_ART_REGION, "button_mount":"individual_sockets_in_existing_chassis", "button_art_loaded":_button_art != null and _button_art.texture != null, "buttons_machine_local_rect":_buttons_rect, "screen_machine_local_rect":_screen_rect, "interactive_viewport_rects":interactive_viewport_rects(), "inventory_cells":inventory_viewport_cells(), "inventory":_inventory.inspection() if _inventory != null else {}, "token_pressed":_pressed, "token_dragging":_dragging, "drag_id":_drag_id, "release_count":_release_count, "cancel_count":_cancel_count, "mutates_inventory":false, "machine_parent":str(get_parent().get_path()) if get_parent() != null else "", "curve_preserved_across_modes":true}, true)
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
