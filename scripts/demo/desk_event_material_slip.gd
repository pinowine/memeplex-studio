class_name DeskEventMaterialSlip
extends Control

signal dropped(record: Dictionary, point: Vector2)

const ResourceGraphic := preload("res://scripts/demo/desk_context_resource_graphic.gd")
const NeuronGraphic := preload("res://scripts/demo/desk_neuron_graphic.gd")
const RULES := preload("res://content/demo/design_rules.tres")

const Paper := preload("res://assets/desk/v1/blank_print_paper.png")

var record: Dictionary = {}
var _paper: TextureRect
var _label: Label
var _graphic: Control
var _pressed := false
var _dragging := false
var _committed := false
var _enabled := true
var _press := Vector2.ZERO
var _offset := Vector2.ZERO
var _origin_parent: Node
var _origin_position := Vector2.ZERO
var _origin_rotation := 0.0
var _drag_host: Control

func _ready() -> void:
	get_viewport().focus_exited.connect(cancel_drag)
	get_viewport().size_changed.connect(cancel_drag)

func configure(value: Dictionary, drag_host: Control, ui_theme: Theme = null) -> void:
	record = value.duplicate(true)
	_drag_host = drag_host
	if ui_theme != null: theme = ui_theme
	mouse_filter = MOUSE_FILTER_STOP
	tooltip_text = ""
	if _paper == null:
		_paper = TextureRect.new()
		_paper.name = "Paper"
		_paper.texture = Paper
		_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_paper)
		_label = Label.new()
		_label.name = "HandwrittenTitle"
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.clip_text = true
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_color", Color("101610"))
		_label.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_label)
	if not resized.is_connected(_layout): resized.connect(_layout)
	if _graphic == null:
		var kind := str(record.get("kind","module"))
		_graphic = NeuronGraphic.new() if kind=="module" else ResourceGraphic.new()
		_graphic.name="ResourceGraphic"
		add_child(_graphic)
		if kind=="module":
			_graphic.configure(str(record.get("id","")),str(RULES.find("modules",str(record.get("id",""))).get("kernel_id","stance")))
			_graphic.grow()
		else:
			_graphic.configure(RULES.context_resource(str(record.get("id",""))))
	_label.text = "%s\n×%d%s" % [str(record.get("title", record.get("id", "物资"))), int(record.get("count", 1)), "\n待收录" if record.get("pending", false) else ""]
	_layout()

func _layout() -> void:
	if _paper == null: return
	_paper.size = size
	# Feed geometry must not cache a wrapped title taller than its paper.
	_label.add_theme_font_size_override("font_size", 11 if size.x >= 76 else 9)
	_label.position = Vector2(5, 4)
	_label.size = Vector2(maxf(0,size.x-10),22)
	if _graphic != null:
		_graphic.position=Vector2(size.x*.15,25)
		_graphic.size=Vector2(size.x*.7,maxf(20,size.y-28))

func set_interaction_enabled(value: bool) -> void:
	_enabled = value
	if not value: cancel_drag()
	mouse_filter = MOUSE_FILTER_STOP if value else MOUSE_FILTER_IGNORE

func set_committed(value: bool) -> void:
	_committed = value

func is_dragging() -> bool:
	return _dragging

func _gui_input(event: InputEvent) -> void:
	if not _enabled or _pressed: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed = true
		_committed = false
		_press = get_global_transform_with_canvas()*event.position
		_offset = _press-get_global_transform_with_canvas().origin
		_origin_parent = get_parent()
		_origin_position = position
		_origin_rotation = rotation
		accept_event()

func _input(event: InputEvent) -> void:
	if not _pressed: return
	if event is InputEventMouseMotion:
		if not _enabled or event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			cancel_drag()
			return
		if not _dragging and event.position.distance_to(_press) >= 6.0:
			_dragging = true
			var angle := get_global_transform_with_canvas().get_rotation()
			if is_instance_valid(_drag_host):
				reparent(_drag_host, true)
				rotation = angle-_drag_host.get_global_transform_with_canvas().get_rotation()
				z_index = 2
		if _dragging and is_instance_valid(_drag_host):
			position = _drag_host.get_global_transform_with_canvas().affine_inverse()*(event.position-_offset)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var drag := _dragging
		_pressed = false
		_dragging = false
		if drag and _enabled:
			dropped.emit(record.duplicate(true), event.position)
		if not _committed: _restore()
		get_viewport().set_input_as_handled()

func cancel_drag() -> void:
	if not _pressed and not _dragging: return
	_pressed = false
	_dragging = false
	_restore()

func _restore() -> void:
	if is_instance_valid(_origin_parent) and get_parent() != _origin_parent:
		reparent(_origin_parent, false)
	position = _origin_position
	rotation = _origin_rotation
	z_index = 0

func inspection() -> Dictionary:
	return {"record":record.duplicate(true), "rect":get_global_rect(), "dragging":_dragging,
		"pressed":_pressed, "enabled":_enabled, "grants_inventory":false, "writes_save":false}
