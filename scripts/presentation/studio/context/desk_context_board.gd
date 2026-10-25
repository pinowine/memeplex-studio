## 工作纸上的五层语境视图；交互命令与拆下的切片共享同一控制器。
class_name DeskContextBoard
extends Control

signal action_requested(action: String, params: Dictionary)
signal selected_info_changed(info: Dictionary)
signal depth_changed(layer: String, depth: float)
signal resource_detached(record: Dictionary, global_point: Vector2)
signal context_layer_detached(record: Dictionary, global_point: Vector2)
signal slot_pressed(layer: String, index: int, viewport_rect: Rect2)

const ContextController := preload("res://scripts/presentation/studio/context/desk_context_controller.gd")
const LAYERS := ContextController.LAYERS
const TITLES := {"language":"语言", "group":"群体", "topics":"话题", "stance":"立场", "pragmatic":"语用"}
const DEPTHS := ContextController.DEPTHS
const ResourceGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const INK := Color("384238")
const MUTED := Color("737968")
const DRAG_THRESHOLD := 6.0

var _rules: MemeDesignRules
var _state: Dictionary = {}
var _layer := "language"
var _depth := 0.1
var _selected_slot := -1
var _enabled := true
var _action_callback := Callable()
var _resource_factory := Callable()
var _resource_graphics: Dictionary = {}
var _layout_layers: Dictionary = {}
var _held := ""
var _held_layer := ""
var _held_slot := -1
var _press_point := Vector2.ZERO
var _last_point := Vector2.ZERO
var _held_moved := false
var _axis_drag := false
var _axis := -1
var _commands := ContextController.new("board")
var _action_count := 0
var _slot_rejections := 0
var _authored_target := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	custom_minimum_size = Vector2(440, 240)
	resized.connect(_refresh)
	get_window().focus_exited.connect(_cancel_input)
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
		for graphic: Control in _resource_graphics.values(): graphic.queue_redraw()
		selected_info_changed.emit(selected_info())

func set_authored_target(source: String) -> void:
	_authored_target = source
	queue_redraw()

func configure(rules: MemeDesignRules) -> void:
	_rules = rules
	_refresh()

func set_state(design: Dictionary) -> void:
	_state = (design.get("design_state", design) as Dictionary).duplicate(true)
	_depth = float(_layers().get(_layer, {}).get("depth", DEPTHS[LAYERS.find(_layer)]))
	_refresh()

func sync_state(design: Dictionary) -> void:
	set_state(design)

func set_action_callback(callback: Callable) -> void:
	_action_callback = callback

func set_resource_factory(factory: Callable) -> void:
	_resource_factory = factory
	for graphic: Control in _resource_graphics.values():
		remove_child(graphic)
		graphic.queue_free()
	_resource_graphics.clear()
	_refresh()

func perform(action: String, params: Dictionary) -> void:
	if not _enabled: return
	_action_count += 1
	if _action_callback.is_valid(): _action_callback.call(action, params.duplicate(true))
	else: action_requested.emit(action, params.duplicate(true))

func set_interaction_enabled(value: bool) -> void:
	_enabled = value
	if not value: _cancel_input()
	queue_redraw()

func select_layer(id: String) -> void:
	if id not in LAYERS: return
	_cancel_input()
	_layer = id
	_selected_slot = -1
	_depth = float(_layers().get(id, {}).get("depth", DEPTHS[LAYERS.find(id)]))
	selected_info_changed.emit(selected_info())
	queue_redraw()

func set_depth(value: float) -> void:
	if is_finite(value): _depth = clampf(value, 0.0, 1.0)

func depth_control() -> VSlider:
	return null

func selected_info() -> Dictionary:
	var data: Dictionary = _layers().get(_layer, {})
	var result := {"layer":_layer, "title":DeskLocalization.text(TITLES[_layer]), "depth":_depth, "slot":_selected_slot, "attached":_attached(_layer), "instructions":DeskLocalization.text("单击查看说明；从纸舌取卡。")}
	if _layer in ["stance", "pragmatic"]:
		result.merge(data.duplicate(true), true)
		result.instructions = DeskLocalization.text("从标记拖动，单次只沿一个轴，每格 0.1；离开起点用筹码，返回起点归还。")
		if _layer == "stance" and not bool(data.get("known", false)): result.hint = DeskLocalization.text("立场未登记，不等于中立；从空心起点拖动才登记。")
		if _layer == "pragmatic": result.target = _target()
	elif _selected_slot >= 0:
		var slots: Array = data.get("slots", [])
		if _selected_slot < slots.size(): result.resource = _resource(str(slots[_selected_slot].get("resource_id", slots[_selected_slot].get("id", "")))).duplicate(true)
	return result

func _layers() -> Dictionary:
	return _state.get("context_layers", {})

func _attached(id: String) -> bool:
	return bool(_layers().get(id, {}).get("attached", true))

func _resource(id: String) -> Dictionary:
	return ContextController.resource(_state, _rules, id)

func _target() -> String:
	var target := str((_state.get("context_draft", {}) as Dictionary).get("target",""))
	if target.is_empty(): return DeskLocalization.text("未填写对象")
	return DeskLocalization.text(target) if not _authored_target.is_empty() and target == _authored_target else target

func _refresh() -> void:
	_build_layout()
	_sync_graphics()
	queue_redraw()

func _region_points(id: String) -> PackedVector2Array:
	var rect: Rect2 = _layout_layers.get(id, {}).get("rect", Rect2())
	return PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x,0), rect.end, rect.position + Vector2(0,rect.size.y)])

func _build_layout() -> void:
	_layout_layers.clear()
	# 左侧放置立场与语用坐标，右侧上方为语言和群体，下方为话题。
	var areas := {
		"stance":Rect2(.06,.055,.32,.40), "pragmatic":Rect2(.06,.535,.32,.40),
		"language":Rect2(.42,.055,.22,.40), "group":Rect2(.68,.055,.25,.40),
		"topics":Rect2(.42,.535,.51,.40)}
	for id: String in LAYERS:
		var area: Rect2 = areas[id]
		var rect := Rect2(area.position*size,area.size*size)
		var data := {"rect":rect,"handle_rect":Rect2(rect.end.x-33,rect.position.y+3,30,18),"slot_centres":[],"slot_rects":[],"slot_pickup_rects":[]}
		_layout_layers[id] = data
		data.region_polygon = _region_points(id)
		if id in ["stance","pragmatic"]:
			var plot_size := Vector2(maxf(42,rect.size.x-72),maxf(42,rect.size.y-84))
			data.plot_rect = Rect2(rect.position+Vector2(35,44),plot_size)
			data.flow_axis_labels = rect.size.y < 128
			for label: String in _axis_labels(id).values():
				if get_theme_default_font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > 34:
					data.flow_axis_labels = true
			if data.flow_axis_labels:
				var caption_height := minf(34,maxf(16,(rect.size.y-70)*.3))
				data.axis_caption_height = caption_height
				data.plot_rect = Rect2(rect.position+Vector2(35,35+caption_height),Vector2(maxf(42,rect.size.x-72),maxf(24,rect.size.y-39-caption_height*2)))
		else:
			var count: int = (_layers().get(id, {}).get("slots", []) as Array).size()
			if count == 0: count = 3 if id == "topics" else 1
			for index in count:
				var columns := 2 if id == "topics" else count
				var cell_width := (rect.size.x-14)/float(columns)
				var graphic_size := Vector2(maxf(40,cell_width-18),maxf(25,rect.size.y*.17)) if id == "topics" else Vector2.ONE*minf(84,cell_width-15)
				var center := rect.position+Vector2(7+cell_width*(float(index%columns)+.5),rect.size.y*(.37 if id == "topics" else .55)+float(index/columns)*rect.size.y*.26)
				if id == "topics" and rect.size.y < 140:
					var row_height := maxf(1,(rect.size.y-38)/ceilf(float(count)/columns))
					graphic_size.y = minf(graphic_size.y,maxf(18,row_height-6))
					center.y = rect.position.y+38+row_height*(floorf(float(index)/columns)+.5)
				data.slot_centres.append(center)
				data.slot_rects.append(Rect2(center-graphic_size*.5,graphic_size))
				data.slot_pickup_rects.append(Rect2(center.x-16,center.y+graphic_size.y*.5+3,32,15))

func _sync_graphics() -> void:
	var wanted := {}
	for id: String in ["language", "group", "topics"]:
		if not _layout_layers.has(id): continue
		var slots: Array = _layers().get(id, {}).get("slots", [])
		var rectangles: Array = _layout_layers[id].slot_rects
		for index in mini(slots.size(), rectangles.size()):
			var resource := _resource(str(slots[index].get("resource_id", slots[index].get("id", ""))))
			if resource.is_empty() or not _attached(id): continue
			var key := "%s:%d" % [id, index]
			wanted[key] = true
			var graphic: Control = _resource_graphics.get(key)
			if not is_instance_valid(graphic):
				if _resource_factory.is_valid(): graphic = _resource_factory.call(resource.duplicate(true))
				else: graphic = ResourceGraphic.new()
				if not is_instance_valid(graphic):
					push_error("Context board resource factory returned no Control: " + key)
					continue
				graphic.name = "Installed" + id.capitalize() + str(index)
				graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(graphic)
				_resource_graphics[key] = graphic
			var rect: Rect2 = rectangles[index]
			graphic.position = rect.position
			graphic.size = rect.size
			if graphic.has_method("configure") and graphic.get_meta("board_definition", {}) != resource:
				graphic.configure(resource.duplicate(true))
				graphic.set_meta("board_definition", resource.duplicate(true))
	for key: String in _resource_graphics.keys():
		if wanted.has(key): continue
		var graphic: Control = _resource_graphics[key]
		remove_child(graphic)
		graphic.queue_free()
		_resource_graphics.erase(key)

func _text(text: String, point: Vector2, font_size: int = 13, color: Color = INK, width: float = -1.0) -> void:
	draw_string(get_theme_default_font(), point, DeskLocalization.text(text), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

func _draw_pencil_path(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	draw_polyline(points,color,width,true)
	var offset := PackedVector2Array()
	for point: Vector2 in points: offset.append(point+Vector2(1.0,-0.6))
	draw_polyline(offset,Color(color, color.a*.30),0.65,true)

func _draw() -> void:
	for id: String in LAYERS:
		if not _layout_layers.has(id): continue
		var info: Dictionary = _layout_layers[id]
		var rect: Rect2 = info.rect
		var attached := _attached(id)
		_text(TITLES[id],rect.position+Vector2(4,20),21)
		_draw_pencil_path(PackedVector2Array([rect.position+Vector2(1,29),rect.position+Vector2(rect.size.x*.42,28),rect.position+Vector2(rect.size.x*.75,30),Vector2(rect.end.x,rect.position.y+27)]),Color(INK,.64),1.15)
		var handle: Rect2 = info.handle_rect
		_text("提起" if attached else DeskLocalization.text("放回"),handle.position+Vector2(1,13),12,MUTED)
		if not attached:
			_text("待放回",rect.position+Vector2(6,rect.size.y*.57),15,MUTED,rect.size.x-12)
			continue
		if id in ["stance","pragmatic"]: _draw_axis(id)
		else: _draw_slots(id)
	if _held_moved and _held in ["layer","resource"]:
		var point := get_global_transform_with_canvas().affine_inverse()*_last_point
		draw_arc(point,17,0.2,TAU-0.2,32,Color(0.20,0.32,0.25,0.65),1.5,true)
		_text("松手取下",point+Vector2(23,5),13)

func _slot_shape(id: String) -> String:
	return {"language":"pencil_circle", "group":"pencil_square", "topics":"horizontal_strips"}.get(id, "xy_plane")

func _draw_slot_socket(id: String, rect: Rect2, selected: bool, occupied: bool) -> void:
	var centre := rect.get_center()
	var ink := INK if selected else Color(0.27, 0.35, 0.28, 0.65)
	var stroke := 2.0 if selected else 1.5
	if id == "language":
		var radius := minf(rect.size.x, rect.size.y) * 0.5 + 5.0
		draw_arc(centre, radius, 0.23, TAU - 0.23, 56, ink, stroke, true)
		if selected: draw_arc(centre, radius + 3.0, 0.23, TAU - 0.23, 56, Color(0.27, 0.35, 0.28, 0.30), 1.0, true)
	elif id == "group":
		var outline := rect.grow(4)
		_draw_pencil_path(PackedVector2Array([outline.position+Vector2(1,0),Vector2(outline.end.x,outline.position.y+2),outline.end-Vector2(2,0),Vector2(outline.position.x,outline.end.y-2),outline.position+Vector2(1,0)]),ink,stroke)
	else:
		if not occupied:
			_draw_pencil_path(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y+1),rect.end,Vector2(rect.position.x,rect.end.y-1),rect.position]),Color(ink,.35),.9)
		if selected: draw_line(rect.position-Vector2(0,3),Vector2(rect.end.x,rect.position.y-3),ink,1.0,true)

func _draw_slots(id: String) -> void:
	var info: Dictionary = _layout_layers[id]
	var slots: Array = _layers().get(id, {}).get("slots", [])
	for index in (info.slot_centres as Array).size():
		var rect: Rect2 = info.slot_rects[index]
		var occupied: bool = index < slots.size() and not slots[index].is_empty()
		_draw_slot_socket(id, rect, id == _layer and index == _selected_slot, occupied)
		if not occupied:
			var label: String = DeskLocalization.format_text("话题 %d", (index + 1)) if id == "topics" else DeskLocalization.text(TITLES[id])
			_draw_text_layout(ResourceGraphic.fit_text(get_theme_default_font(),label,rect.grow(-1),12,12,1),MUTED)
		else:
			var tongue: Rect2 = info.slot_pickup_rects[index]
			if id=="topics":
				draw_rect(tongue,Color("c9c1a6"))
				_text("取卡",tongue.position+Vector2(2,11),13)
			else:
				draw_line(tongue.position+Vector2(2,12),tongue.end-Vector2(2,1),Color(0.29,0.32,0.26,0.45),0.9,true)
func _draw_axis(id: String) -> void:
	var info: Dictionary = _layout_layers[id]
	var plot: Rect2 = info.plot_rect
	var data: Dictionary = _layers().get(id, {})
	var center := plot.get_center()
	for tick in 11:
		var t := float(tick)/10.0
		if tick == 5: continue
		draw_line(Vector2(plot.position.x+plot.size.x*t,center.y-2),Vector2(plot.position.x+plot.size.x*t,center.y+2),Color(MUTED,.35),.8,true)
		draw_line(Vector2(center.x-2,plot.position.y+plot.size.y*t),Vector2(center.x+2,plot.position.y+plot.size.y*t),Color(MUTED,.35),.8,true)
	_draw_pencil_path(PackedVector2Array([Vector2(plot.position.x,center.y),center+Vector2(3,-1),Vector2(plot.end.x,center.y+1)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(center.x+1,plot.end.y),center-Vector2(1,4),Vector2(center.x,plot.position.y)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(plot.end.x-10,center.y-6),Vector2(plot.end.x,center.y+1),Vector2(plot.end.x-9,center.y+7)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(center.x-6,plot.position.y+10),Vector2(center.x,plot.position.y),Vector2(center.x+6,plot.position.y+10)]),Color(INK,.75),1.2)
	var label_layouts := _axis_label_layouts(id)
	for key: String in ["x_negative", "x_positive", "y_negative", "y_positive"]:
		_draw_text_layout(label_layouts[key])
	draw_arc(_axis_origin(id), 7, 0, TAU, 28, INK, 1.5, true)
	var known := id != "stance" or bool(data.get("known", false))
	if known:
		draw_circle(_axis_point(id), 4, INK)
		var current: Array = data.get("current", [0.0, 0.0])
		var coordinates := "%.1f / %.1f" % [float(current[0]), float(current[1])]
		var available: float = (info.handle_rect as Rect2).position.x-info.rect.position.x-58
		if get_theme_default_font().get_string_size(coordinates,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x > available:
			coordinates = "%.1f/%.1f" % [float(current[0]),float(current[1])]
		_text(coordinates, info.rect.position + Vector2(53,20),12,MUTED)
	else:
		_text("未登记", info.rect.position + Vector2(53, 20), 14, MUTED)

func _axis_labels(id: String) -> Dictionary:
	var labels := {"x_negative":DeskLocalization.text("自由") if id == "stance" else DeskLocalization.text("真诚"), "x_positive":DeskLocalization.text("威权") if id == "stance" else DeskLocalization.text("反讽"), "y_negative":DeskLocalization.text("平等") if id == "stance" else DeskLocalization.text("支持"), "y_positive":DeskLocalization.text("等级") if id == "stance" else DeskLocalization.text("反对")}
	labels.merge(_layers().get(id, {}).get("axis_labels", {}), true)
	for key: String in labels: labels[key] = DeskLocalization.text(str(labels[key]))
	return labels

func _axis_label_positions(id: String) -> Dictionary:
	var result := {}
	var layouts := _axis_label_layouts(id)
	for key: String in layouts:
		var lines: Array = layouts[key].lines
		result[key] = lines[0].baseline if not lines.is_empty() else Vector2.ZERO
	return result

func _draw_text_layout(layout: Dictionary, color: Color = INK) -> void:
	for line: Dictionary in layout.get("lines",[]): _text(line.text,line.baseline,int(line.font_size),color)

func _axis_label_layouts(id: String) -> Dictionary:
	var plot: Rect2 = _layout_layers.get(id, {}).get("plot_rect", Rect2())
	var center := plot.get_center()
	var info: Dictionary = _layout_layers[id]
	var labels := _axis_labels(id)
	var font := get_theme_default_font()
	var areas := {}
	if not bool(info.get("flow_axis_labels",false)):
		var positions := {"x_negative":Vector2(plot.position.x-31,center.y+4),"x_positive":Vector2(plot.end.x+6,center.y+4),"y_negative":Vector2(center.x-12,plot.position.y-7),"y_positive":Vector2(center.x-12,plot.end.y+17)}
		for key: String in positions:
			var width := font.get_string_size(str(labels[key]),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
			areas[key] = Rect2(positions[key]-Vector2(0,font.get_ascent(14)),Vector2(width,font.get_ascent(14)+font.get_descent(14)))
	else:
		var rect: Rect2 = info.rect
		var height := float(info.axis_caption_height)
		var side_width := maxf(1,rect.size.x*.30-4)
		var middle_width := rect.size.x*.32
		areas = {
			"x_negative":Rect2(Vector2(rect.position.x+1,center.y+6),Vector2(side_width,height)),
			"x_positive":Rect2(Vector2(rect.end.x-side_width-1,center.y+6),Vector2(side_width,height)),
			"y_negative":Rect2(Vector2(rect.get_center().x-middle_width*.5,rect.position.y+31),Vector2(middle_width,height)),
			"y_positive":Rect2(Vector2(rect.get_center().x-middle_width*.5,rect.end.y-height-1),Vector2(middle_width,height))}
	var result := {}
	for key: String in areas: result[key]=ResourceGraphic.fit_text(font,str(labels[key]),areas[key],14,12,2)
	return result

func _axis_point(id: String) -> Vector2:
	return _axis_position(id, _layers().get(id, {}).get("current", [0.0, 0.0]))

func _axis_origin(id: String) -> Vector2:
	return _axis_position(id, _layers().get(id, {}).get("origin", [0.0, 0.0]))

func _axis_position(id: String, values: Array) -> Vector2:
	var plot: Rect2 = _layout_layers.get(id, {}).get("plot_rect", Rect2())
	return plot.get_center() + Vector2(float(values[0]), float(values[1])) * plot.size * 0.5

func _layer_at(point: Vector2) -> String:
	# 取卡纸舌可以伸出所属纸面，命中时先于整层判断。
	for id: String in LAYERS:
		if not _layout_layers.has(id): continue
		if (_layout_layers[id].handle_rect as Rect2).has_point(point): return id
	for id: String in LAYERS:
		if not _layout_layers.has(id): continue
		var info: Dictionary = _layout_layers[id]
		for pickup: Rect2 in info.slot_pickup_rects:
			if pickup.has_point(point): return id
		if _slot_at(id, point) >= 0: return id
		if (info.get("plot_rect", Rect2()) as Rect2).has_point(point): return id
	for id: String in LAYERS:
		if not _layout_layers.has(id): continue
		if Geometry2D.is_point_in_polygon(point,_layout_layers[id].region_polygon): return id
	return ""

func _slot_at(id: String, point: Vector2) -> int:
	var rectangles: Array = _layout_layers.get(id, {}).get("slot_rects", [])
	for index in rectangles.size():
		if (rectangles[index] as Rect2).grow(7).has_point(point): return index
	return -1

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	if not _enabled or not data is Dictionary:
		return false
	var layer := _layer_at(point)
	if str(data.get("type", "")) == "design_context_layer":
		return ContextController.can_attach(_state, layer, data)
	return ContextController.can_install(_state, _rules, layer, _slot_at(layer, point), data)

func _drop_data(point: Vector2, data: Variant) -> void:
	if not _can_drop_data(point, data):
		_slot_rejections += 1
		return
	var id := _layer_at(point)
	select_layer(id)
	if str(data.get("type", "")) == "design_context_layer":
		perform("attach_context_layer", {"layer":id, "plane_id":str(data.plane_id)})
	else:
		_selected_slot = _slot_at(id, point)
		perform("install_context", {"layer":id, "slot":_selected_slot, "resource_id":str(data.resource_id)})
	selected_info_changed.emit(selected_info())
	queue_redraw()

func accept_tabletop_item(kind: String, id: String, global_position: Vector2) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse() * global_position
	var data := {"type":"context_resource", "kind":kind, "resource_id":id}
	if not _can_drop_data(point, data): return false
	var layer := _layer_at(point)
	var slot := _slot_at(layer, point)
	_drop_data(point, data)
	var slots: Array = _layers().get(layer, {}).get("slots", [])
	return slot >= 0 and slot < slots.size() and str(slots[slot].get("resource_id", slots[slot].get("id", ""))) == id

func accept_tabletop_layer(record: Dictionary, global_point: Vector2) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse() * global_point
	if not _can_drop_data(point, record): return false
	_drop_data(point, record)
	return _attached(str(record.get("layer", "")))

func plane_record(id: String = "") -> Dictionary:
	if id.is_empty(): id = _layer
	var data: Dictionary = _layers().get(id, {})
	return {"type":"design_context_layer", "layer":id, "plane_id":str(data.get("plane_id", "")), "depth":float(data.get("depth", DEPTHS[LAYERS.find(id)])), "snapshot":_state.duplicate(true)}

func _gui_input(event: InputEvent) -> void:
	if not _enabled: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_last_point = get_global_transform_with_canvas() * event.position
		if event.pressed: _begin_pointer(event.position)
		else: _release_pointer(event.position)
		accept_event()
	elif event is InputEventMouseMotion and not _held.is_empty():
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_cancel_input()
			return
		_last_point = get_global_transform_with_canvas() * event.position
		_held_moved = _held_moved or event.position.distance_to(_press_point) > DRAG_THRESHOLD
		if _axis_drag:
			var delta: Vector2 = event.position - _press_point
			var plot: Rect2 = _layout_layers[_held_layer].plot_rect
			var step := float(_layers().get(_held_layer, {}).get("step", 0.1))
			# 小尺寸纸面也必须能拖动一个完整网格步长。
			var threshold := minf(DRAG_THRESHOLD, minf(plot.size.x, plot.size.y) * step * 0.175)
			if _axis < 0 and delta.length() > threshold: _axis = 0 if absf(delta.x) >= absf(delta.y) else 1
			if _axis >= 0: _move_axis(event.position)
		queue_redraw()
		accept_event()

func _begin_pointer(point: Vector2) -> void:
	_cancel_input()
	var id := _layer_at(point)
	if id.is_empty(): return
	_layer = id
	_depth = float(_layers().get(id, {}).get("depth", DEPTHS[LAYERS.find(id)]))
	_selected_slot = _slot_at(id, point)
	_press_point = point
	_held_layer = id
	_held_slot = _selected_slot
	_held = "selection"
	if _attached(id):
		if (_layout_layers[id].handle_rect as Rect2).has_point(point): _held = "layer"
		elif id in ["stance", "pragmatic"]:
			var anchor := _axis_point(id)
			if id == "stance" and not bool(_layers().get(id, {}).get("known", false)): anchor = _axis_origin(id)
			if point.distance_to(anchor) <= 13:
				_held = "axis"
				_axis_drag = true
		else:
			var slots: Array = _layers().get(id, {}).get("slots", [])
			var pickups: Array = _layout_layers[id].slot_pickup_rects
			for index in pickups.size():
				if (pickups[index] as Rect2).has_point(point) and index < slots.size() and not slots[index].is_empty():
					_held = "resource"
					_held_slot = index
					_selected_slot = index
	selected_info_changed.emit(selected_info())
	queue_redraw()

func _release_pointer(point: Vector2) -> void:
	var held := _held
	var id := _held_layer
	var slot := _held_slot
	var moved := _held_moved
	_cancel_input()
	if id.is_empty(): return
	if not moved:
		if held == "selection" or held == "resource" or held == "axis":
			var index := slot if slot >= 0 else _slot_at(id,point)
			var local_rect: Rect2 = _layout_layers[id].slot_rects[index] if index >= 0 else _layout_layers[id].get("plot_rect",_layout_layers[id].rect)
			slot_pressed.emit(id,index,_viewport_rect(local_rect))
		return
	if held == "layer" and _layer_at(point) != id:
		var record := plane_record(id)
		if str(record.plane_id).is_empty() or not _attached(id): return
		perform("detach_context_layer", {"layer":id, "plane_id":str(record.plane_id)})
		if not _attached(id):
			record.snapshot = _state.duplicate(true)
			context_layer_detached.emit(record, _last_point)
	elif held == "resource" and _slot_at(id, point) != slot:
		var slots: Array = _layers().get(id, {}).get("slots", [])
		if slot < 0 or slot >= slots.size() or slots[slot].is_empty(): return
		var record := _resource(str(slots[slot].get("resource_id", slots[slot].get("id", "")))).duplicate(true)
		perform("remove_context", {"layer":id, "slot":slot})
		var current: Array = _layers().get(id, {}).get("slots", [])
		if slot < current.size() and current[slot].is_empty(): resource_detached.emit(record, _last_point)
	selected_info_changed.emit(selected_info())

func _move_axis(point: Vector2) -> void:
	var id := _held_layer
	var data: Dictionary = _layers().get(id, {})
	var plot: Rect2 = _layout_layers[id].plot_rect
	var step := float(data.get("step", 0.1))
	if step <= 0.0: return
	var value := clampf((point[_axis] - plot.get_center()[_axis]) / (plot.size[_axis] * 0.5), -1.0, 1.0)
	var origin: Array = data.get("origin", [0.0, 0.0])
	var target := roundi((value - float(origin[_axis])) / step)
	_commands.move_axis(_layers, perform, id, _axis, target)
	selected_info_changed.emit(selected_info())
	queue_redraw()

func _cancel_input() -> void:
	_held = ""
	_held_layer = ""
	_held_slot = -1
	_held_moved = false
	_axis_drag = false
	_axis = -1
	queue_redraw()

func _get_drag_data(_position: Vector2) -> Variant:
	# 手动处理取卡手势，保证一次释放只提交一次权威操作。
	return null

func create_slice_item(record: Dictionary) -> Control:
	var code: Script = load("res://scripts/presentation/studio/context/desk_context_slice_item.gd")
	var item: Control = code.new()
	item.theme = theme
	item.configure(record, _rules, _resource_factory)
	return item

func inspection() -> Dictionary:
	var layers := {}
	var visible: Array = []
	for id: String in LAYERS:
		var info: Dictionary = _layout_layers.get(id, {}).duplicate(true)
		info.plane_id = str(_layers().get(id, {}).get("plane_id", ""))
		info.attached = _attached(id)
		info.slot_shape = _slot_shape(id)
		info.slot_material = "pencil_outline" if id in ["language","group"] else ("horizontal_paper_strip" if id=="topics" else "pencil_axes")
		info.pin_style = ""
		var quads: Array = []
		for rect: Rect2 in info.get("slot_rects", []):
			quads.append(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]))
		info.slot_quads = quads
		if id in ["stance", "pragmatic"]:
			info.axis_rect = info.plot_rect
			info.axis_labels = _axis_labels(id)
			info.axis_label_positions = _axis_label_positions(id)
			info.marker_known = bool(_layers().get(id, {}).get("known", false)) if id == "stance" else true
			info.axis_point = _axis_point(id)
			info.axis_origin = _axis_origin(id)
			info.known = bool(_layers().get(id, {}).get("known", false)) if id == "stance" else true
			info.current_marker_visible = info.attached and info.known
			info.origin_marker_shape = "hollow_circle"
			info.current_marker_shape = "solid_circle" if info.known else "none"
			info.target = _target() if id == "pragmatic" else ""
		else:
			info.axis_point = Vector2.ZERO
			info.axis_origin = Vector2.ZERO
		layers[id] = info
		visible.append(id)
	var selected: Dictionary = layers.get(_layer, {})
	return {"layout_mode":"assembly_board", "layout_version":13, "layers":layers, "visible_layers":visible, "depth_control_visible":false, "subviewport_count":0, "displayed_cells":5, "active_plane_count":LAYERS.filter(func(id): return _attached(str(id))).size(), "layer":_layer, "plane_id":selected.get("plane_id", ""), "attached":_attached(_layer), "depth":_depth, "visual_depth":_depth, "plane_depth":_depth, "slot_shape":selected.get("slot_shape", ""), "slot_shapes":"pencil_circle / pencil_square / horizontal_strips", "slot_centres":selected.get("slot_centres", []), "slot_quads":selected.get("slot_quads", []), "slot_pickup_rects":selected.get("slot_pickup_rects", []), "axis_point":selected.get("axis_point", Vector2.ZERO), "axis_origin":selected.get("axis_origin", Vector2.ZERO), "axis_drag":_axis_drag, "axis":_axis, "interaction_enabled":_enabled, "selection":selected_info(), "action_count":_action_count, "slot_rejections":_slot_rejections, "resource_graphics":_resource_graphics.keys(), "brain_texture":"", "image_opacity":0.0, "single_brain":false, "brain_image_count":0, "panel_background_count":0, "brain_rect":Rect2(), "brain_source_rect":Rect2(), "topic_pin_style":"none", "plane_only":false, "gesture":_held, "gesture_layer":_held_layer, "native_detach_enabled":false}

func _viewport_rect(rect: Rect2) -> Rect2:
	var transform := get_global_transform_with_canvas()
	var result := Rect2(transform*rect.position,Vector2.ZERO)
	for point: Vector2 in [rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: result = result.expand(transform*point)
	return result

func hover_info(viewport_point: Vector2) -> Dictionary:
	var point := get_global_transform_with_canvas().affine_inverse()*viewport_point
	var layer := _layer_at(point)
	if layer.is_empty(): return {}
	var index := _slot_at(layer,point)
	var data: Dictionary = _layers().get(layer,{})
	var result := {"layer":layer,"slot":index,"title":TITLES[layer],"text":DeskLocalization.text("单击查看说明"),"attached":_attached(layer)}
	if layer in ["stance","pragmatic"]:
		result.text = " / ".join(_axis_labels(layer).values())
		result.current = data.get("current",[0,0])
	elif index >= 0:
		var slots: Array = data.get("slots",[])
		var resource := _resource(str(slots[index].get("resource_id",slots[index].get("id","")))) if index < slots.size() else {}
		if resource.is_empty(): result.text = DeskLocalization.text("空槽 · 放入")+TITLES[layer]
		else:
			result.title = resource.get("title",TITLES[layer])
			result.text = resource.get("description","")
			result.resource = resource.duplicate(true)
	return result
