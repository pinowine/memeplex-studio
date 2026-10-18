class_name DeskContextSliceItem
extends Control

signal item_dropped(layer: String, plane_id: String, global_point: Vector2)
signal moved(global_point: Vector2)

const Slice := preload("res://scripts/demo/desk_context_slice.gd")
var record: Dictionary = {}
var _rules: Resource
var _factory := Callable()
var _view: Control
var _pressed := false
var _dragging := false
var _origin := Vector2.ZERO
var _grab := Vector2.ZERO
var _last_point := Vector2.ZERO
var _native_drag := false
var _enabled := true

func configure(data: Dictionary, rules: Resource, factory: Callable = Callable()) -> void:
	record = data.duplicate(true)
	record.type = "design_context_layer"
	_rules = rules
	_factory = factory
	_refresh()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	if size == Vector2.ZERO: size = Vector2(240,240)
	_view = Slice.new()
	_view.name = "DetachedPlane"
	_view.theme = theme
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	resized.connect(_layout)
	get_window().focus_exited.connect(_cancel)
	_refresh()
	_layout()

func _layout() -> void:
	if _view != null:
		_view.size = size
		_view.set_plane_only(true)

func _refresh() -> void:
	if not is_instance_valid(_view): return
	_view.configure(_rules)
	_view.set_resource_factory(_factory)
	_view.set_state(record.get("snapshot",{}))
	_view.select_layer(str(record.get("layer","language")))
	_view.set_depth(float(record.get("depth",0.1)))
	_view.set_plane_only(true)
	_view.set_interaction_enabled(false)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_interaction_enabled(value: bool) -> void:
	_enabled=value
	if not value: _cancel()

func _get_drag_data(_position: Vector2) -> Variant:
	if not _enabled or str(record.get("plane_id","")).is_empty(): return null
	_native_drag=true
	return {"type":"design_context_layer","layer":str(record.layer),"plane_id":str(record.plane_id)}

func _input(event: InputEvent) -> void:
	if _native_drag and event is InputEventMouseMotion: _last_point=event.position

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END and _native_drag:
		_native_drag=false
		item_dropped.emit(str(record.get("layer","")),str(record.get("plane_id","")),_last_point)

func _gui_input(event: InputEvent) -> void:
	if not _enabled: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_global_transform_with_canvas()*event.position
		if event.pressed:
			_pressed=true
			_origin=point
			_grab=point-global_position
			_last_point=point
		elif _pressed:
			var drag := _dragging
			_cancel()
			if drag: item_dropped.emit(str(record.get("layer","")),str(record.get("plane_id","")),point)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT: _cancel(); return
		var point: Vector2 = get_global_transform_with_canvas()*event.position
		_dragging=_dragging or point.distance_to(_origin)>6
		_last_point=point
		if _dragging and not _native_drag:
			global_position=point-_grab
			moved.emit(point)
		accept_event()

func _cancel() -> void:
	_pressed=false
	_dragging=false

func inspection() -> Dictionary:
	return {"layer":str(record.get("layer","")),"plane_id":str(record.get("plane_id","")),"whole_layer":true,"consumes_resources":false,"instance_id":get_instance_id(),"snapshot":record.get("snapshot",{}).duplicate(true),"dragging":_dragging or _native_drag,"position":global_position,"size":size,"view":_view.inspection() if _view != null else {}}
