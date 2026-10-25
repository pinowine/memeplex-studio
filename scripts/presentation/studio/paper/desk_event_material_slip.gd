class_name DeskEventMaterialSlip
extends Control

signal dropped(record: Dictionary, point: Vector2)

const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const ResourceGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const NeuronGraphic := preload("res://scripts/presentation/studio/design/desk_neuron_graphic.gd")
const RULES := preload("res://data/rules/design_rules.tres")

const Paper := preload("res://assets/image/textures/studio/desk/blank_print_paper.png")

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
var _card_style := ""
var _face: Control

class CardMarks extends Control:
	var kind := ""
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var ink: Color = {"language":Color("648578"), "group":Color("9d754c"), "module":Color("716b92"), "topic":Color("9e8451")}.get(kind,Color("7b7e69"))
		draw_line(Vector2(5,23),Vector2(size.x-5,23),ink,1.0,true)
		if kind == "language":
			for y in range(30,int(size.y)-4,8): draw_line(Vector2(5,y),Vector2(size.x-5,y),Color(ink,.17),.6,true)
		elif kind == "group":
			for x in [5.0,size.x-13.0]: draw_rect(Rect2(x,5,8,4),Color(ink,.45))
		elif kind == "module":
			for x in range(6,int(size.x),8): draw_line(Vector2(x,27),Vector2(x,size.y-5),Color(ink,.14),.5,true)
		elif kind == "topic":
			draw_line(Vector2(6,size.y-5),Vector2(size.x-6,size.y-6),Color(ink,.5),.8,true)


func _ready() -> void:
	get_window().focus_exited.connect(cancel_drag)
	get_viewport().size_changed.connect(cancel_drag)

func configure(value: Dictionary, drag_host: Control, ui_theme: Theme = null) -> void:
	record = value.duplicate(true)
	_drag_host = drag_host
	_card_style = {"language":"ruled_language_card", "group":"ochre_group_card", "module":"graph_patch_card", "topic":"horizontal_topic_card"}.get(str(record.get("kind", "")),"material_card")
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
		var marks := CardMarks.new()
		marks.name = "HanddrawnCardMarks"
		marks.kind = str(record.get("kind", ""))
		marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(marks)
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
		_graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_graphic)
		if kind=="module":
			_graphic.configure(str(record.get("id","")),str(RULES.find("modules",str(record.get("id",""))).get("kernel_id","stance")))
			_graphic.grow()
		else:
			_graphic.configure(RULES.context_resource(str(record.get("id",""))))
	_paper.modulate = {"language":Color("e2e7dc"), "group":Color("e4d6b6"), "module":Color("dddbe5"), "topic":Color("eee1ba")}.get(str(record.get("kind", "")),Color.WHITE)
	if str(record.get("kind", "")) in ["language","group","module","topic"]:
		if _face == null:
			_face = CardFace.new()
			_face.name = "PhysicalMaterialCardFace"
			_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_face)
			mouse_entered.connect(func():
				if _face != null: _face.set_hovered(_enabled))
			mouse_exited.connect(func():
				if _face != null: _face.set_hovered(false))
		var face_record := record.duplicate(true)
		face_record.source_instance_id = str(record.get("instance_id", ""))
		_face.configure(face_record,get_theme_font("font","Label"))
		_card_style = str(_face.inspection().shape)
		custom_minimum_size = CardFace.minimum_card_size(str(record.kind))
		_paper.hide()
		_graphic.hide()
		_label.hide()
		var marks := get_node_or_null("HanddrawnCardMarks")
		if marks != null: marks.hide()
	_label.text = "%s\n×%d%s" % [DeskLocalization.text(str(record.get("title", record.get("id", "物资")))), int(record.get("count", 1)), "\n待收录" if record.get("pending", false) else ""]
	_layout()

func _layout() -> void:
	if _paper == null: return
	_paper.size = size
	if _face != null:
		_face.size = size
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
		"face":_face.inspection() if _face != null else {}, "card_style":_card_style, "source_instance_id":str(record.get("instance_id", "")), "pressed":_pressed, "enabled":_enabled, "grants_inventory":false, "writes_save":false}
