class_name DeskContextBoard
extends Control

signal action_requested(action: String, params: Dictionary)
signal selected_info_changed(info: Dictionary)
signal resource_detached(record: Dictionary, global_point: Vector2)
signal slot_pressed(layer: String, index: int, viewport_rect: Rect2)

const ContextController := preload("res://scripts/presentation/studio/context/desk_context_controller.gd")
const LAYERS := ContextController.LAYERS
static var TITLES := {"language":DeskLocalization.source("LOC_LANGUAGE_9F6FEE1A"), "group":DeskLocalization.source("LOC_AUDIENCE_D14FC4B5"), "topics":DeskLocalization.source("LOC_TOPICS_A2C81C5A"), "stance":DeskLocalization.source("LOC_STANCE_8A2DE4CD"), "pragmatic":DeskLocalization.source("LOC_PRAGMATICS_7063D1D8")}
const ResourceGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const ComponentCopy := preload("res://scripts/presentation/studio/desk/desk_component_hover_copy.gd")
const PaperIcon := preload("res://scripts/presentation/studio/workbench/desk_workbench_icon.gd")
const HEADING_FONT := preload("res://assets/image/fonts/body_semibold_font.tres")
const INK := Color("384238")
const MUTED := Color("737968")
const DRAG_THRESHOLD := 6.0
const CARD_GAP := 12.0
const HEADING_SIZE := 20
const AXIS_HANDLE_RADIUS := 13.0
const GRID_INK := Color("737968", .14)
const GRID_PAPER := Color("737968", .025)
const REACHABLE_INK := Color("648f72", .24)

var _rules: MemeDesignRules
var _state: Dictionary = {}
var _layer := "language"
var _selected_slot := -1
var _enabled := true
var _action_callback := Callable()
var _resource_factory := Callable()
var _resource_graphics: Dictionary = {}
var _heading_icons: Dictionary = {}
var _layout_layers: Dictionary = {}
var _hover_target := ""
var _held := ""
var _held_layer := ""
var _held_slot := -1
var _press_point := Vector2.ZERO
var _last_point := Vector2.ZERO
var _held_moved := false
var _resource_dragging := false
var _drag_preview: Control
var _drag_preview_parent: Control
var _drag_target := Vector2.ZERO
var _axis_drag := false
var _token_drag_layer := ""
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
	_drag_preview_parent = self
	for id: String in LAYERS:
		var icon := PaperIcon.new()
		icon.name = id.capitalize() + "Icon"
		icon.kind = "topic" if id == "topics" else id
		add_child(icon)
		_heading_icons[id] = icon
	mouse_exited.connect(_on_mouse_exited)
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

func set_drag_preview_parent(parent: Control) -> void:
	_drag_preview_parent = parent

func perform(action: String, params: Dictionary) -> void:
	if not _enabled: return
	_action_count += 1
	if _action_callback.is_valid(): _action_callback.call(action, params.duplicate(true))
	else: action_requested.emit(action, params.duplicate(true))

func set_interaction_enabled(value: bool) -> void:
	if _enabled == value: return
	_enabled = value
	if not value:
		_cancel_input()
		_on_mouse_exited()
	queue_redraw()

func select_layer(id: String) -> void:
	if id not in LAYERS: return
	_cancel_input()
	_layer = id
	_selected_slot = -1
	selected_info_changed.emit(selected_info())
	_sync_graphics()
	queue_redraw()

func selected_info() -> Dictionary:
	var data: Dictionary = _layers().get(_layer, {})
	var result := {"layer":_layer, "title":DeskLocalization.text(TITLES[_layer]), "slot":_selected_slot, "instructions":DeskLocalization.text("LOC_CLICK_TO_FOCUS_THIS_SECTION_DRAG_A_3E6ABE39")}
	if _layer in ["stance", "pragmatic"]:
		result.merge(data.duplicate(true), true)
		result.instructions = DeskLocalization.text("LOC_DRAG_THE_MARKER_ALONG_ONE_AXIS_AT_291BFA50")
		if _layer == "stance" and not bool(data.get("known", false)): result.hint = DeskLocalization.text("LOC_UNSPECIFIED_STANCE_DOES_NOT_MEAN_NEUTRAL_DRAG_57E53949")
		if _layer == "pragmatic": result.target = _target()
	elif _selected_slot >= 0:
		var slots: Array = data.get("slots", [])
		if _selected_slot < slots.size(): result.resource = _resource(str(slots[_selected_slot].get("resource_id", slots[_selected_slot].get("id", "")))).duplicate(true)
	return result

func _layers() -> Dictionary:
	return _state.get("context_layers", {})

func _resource(id: String) -> Dictionary:
	return ContextController.resource(_state, _rules, id)

func _target() -> String:
	var target := str((_state.get("context_draft", {}) as Dictionary).get("target",""))
	if target.is_empty(): return DeskLocalization.text("LOC_NO_TARGET_ENTERED_0397EF33")
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
	# The left column starts below the CRT; card rows keep their physical proportions.
	var axis_side := size.x * .255
	var lower_top := maxf(size.y * .555, size.y * .075 + 48 + axis_side + CARD_GAP + size.y * .03)
	var areas := {
		"language":Rect2(.055,.19,.30,.30), "group":Rect2(.055,.555,.30,.37),
		"stance":Rect2(.405,.075,.255,.39), "pragmatic":Rect2(.69,.075,.255,.39),
		"topics":Rect2(.405,.555,.54,.37)}
	for id: String in LAYERS:
		var area: Rect2 = areas[id]
		var rect := Rect2(area.position*size,area.size*size)
		if id in ["stance", "pragmatic"]: rect.size.y = 48 + axis_side + 8
		elif id in ["group", "topics"]:
			rect.position.y = lower_top
			rect.size.y = size.y * .925 - lower_top
		var data := {"rect":rect,"slot_centres":[],"slot_rects":[],"slot_pickup_rects":[]}
		data.icon_rect = Rect2(rect.position + Vector2(0, 4), Vector2(24, 24))
		data.title_rect = Rect2(rect.position + Vector2(32, 0), Vector2(rect.size.x - 32, 32))
		data.heading_hit_rect = Rect2(rect.position, Vector2(32 + minf(data.title_rect.size.x, HEADING_FONT.get_string_size(DeskLocalization.text(TITLES[id]), HORIZONTAL_ALIGNMENT_LEFT, -1, HEADING_SIZE).x), 32))
		data.heading_rule = Rect2(rect.position + Vector2(0, 40), Vector2(rect.size.x, 1))
		_layout_layers[id] = data
		data.region_polygon = _region_points(id)
		if _heading_icons.has(id):
			_heading_icons[id].position = data.icon_rect.position
			_heading_icons[id].size = data.icon_rect.size
		if id in ["stance","pragmatic"]:
			var plot_area := Rect2(rect.position + Vector2(0, 48), Vector2(rect.size.x, rect.size.y - 56))
			var side := minf(plot_area.size.x, plot_area.size.y)
			var plot := Rect2(plot_area.get_center() - Vector2.ONE * side * .5, Vector2.ONE * side)
			data.plot_rect = plot
			data.plot_available_rect = plot_area
			data.plot_fill_ratio = side / minf(plot_area.size.x, plot_area.size.y)
			data.grid_step = float(_layers().get(id, {}).get("step", _rules.axis_step if _rules != null else .1))
			data.grid_divisions = roundi(2.0 / float(data.grid_step))
			data.grid_spacing = side / float(data.grid_divisions)
			data.grid_color = GRID_INK
			data.grid_fill_color = GRID_PAPER
			var grid_lines := PackedVector2Array()
			for tick in int(data.grid_divisions) + 1:
				var offset := float(tick) * float(data.grid_spacing)
				grid_lines.append(Vector2(plot.position.x + offset, plot.position.y))
				grid_lines.append(Vector2(plot.position.x + offset, plot.end.y))
				grid_lines.append(Vector2(plot.position.x, plot.position.y + offset))
				grid_lines.append(Vector2(plot.end.x, plot.position.y + offset))
			data.grid_lines = grid_lines
			data.flow_axis_labels = true
			data.axis_caption_height = 24.0
		else:
			var count: int = (_layers().get(id, {}).get("slots", []) as Array).size()
			if count == 0: count = 3 if id == "topics" else 2
			if id in ["language", "group"]: count = mini(count, 2)
			var kind := "topic" if id == "topics" else id
			var card_size := CardFace.minimum_card_size(kind)
			var columns := mini(count, 3 if id == "topics" else 2)
			var rows := ceili(float(count) / columns)
			var content := Rect2(rect.position + Vector2(4, 64), rect.size - Vector2(8, 80))
			var cell_size := Vector2((content.size.x - CARD_GAP * (columns - 1)) / columns, (content.size.y - CARD_GAP * (rows - 1)) / rows)
			var card_scale := minf(1.0, minf(cell_size.x / card_size.x, cell_size.y / card_size.y))
			var graphic_size := card_size * card_scale
			var row_width := graphic_size.x * columns + CARD_GAP * (columns - 1)
			var rows_height := graphic_size.y * rows + CARD_GAP * (rows - 1)
			var origin := content.position + Vector2((content.size.x - row_width) * .5, maxf(0, (content.size.y - rows_height) * .5))
			for index in count:
				var center := origin + Vector2((index % columns) * (graphic_size.x + CARD_GAP), floori(float(index) / columns) * (graphic_size.y + CARD_GAP)) + graphic_size * .5
				data.slot_centres.append(center)
				data.slot_rects.append(Rect2(center-graphic_size*.5,graphic_size))
				data.slot_pickup_rects.append(Rect2(center-graphic_size*.5,graphic_size))

func _sync_graphics() -> void:
	var wanted := {}
	for id: String in ["language", "group", "topics"]:
		if not _layout_layers.has(id): continue
		var slots: Array = _layers().get(id, {}).get("slots", [])
		var rectangles: Array = _layout_layers[id].slot_rects
		for index in mini(slots.size(), rectangles.size()):
			var resource := _resource(str(slots[index].get("resource_id", slots[index].get("id", ""))))
			if resource.is_empty(): continue
			var key := "%s:%d" % [id, index]
			wanted[key] = true
			var graphic: Control = _resource_graphics.get(key)
			if not is_instance_valid(graphic):
				if _resource_factory.is_valid(): graphic = _resource_factory.call(resource.duplicate(true))
				else: graphic = CardFace.new()
				if not is_instance_valid(graphic):
					push_error("Context board resource factory returned no Control: " + key)
					continue
				graphic.name = "Installed" + id.capitalize() + str(index)
				graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(graphic)
				_resource_graphics[key] = graphic
			var rect: Rect2 = rectangles[index]
			graphic.position = rect.position
			if graphic.has_method("configure") and graphic.get_meta("board_definition", {}) != resource:
				if graphic is DeskMaterialCardFace:
					var face_record := resource.duplicate(true)
					face_record.count = 1
					graphic.configure(face_record, get_theme_default_font())
				else: graphic.configure(resource.duplicate(true))
				graphic.set_meta("board_definition", resource.duplicate(true))
			if graphic is DeskMaterialCardFace:
				graphic.size = CardFace.minimum_card_size(str(resource.kind))
				graphic.scale = rect.size / graphic.size
				graphic.set_selected(id == _layer and index == _selected_slot)
				graphic.placement = CardFace.Placement.FIXED
			else: graphic.size = rect.size
			graphic.visible = not (_resource_dragging and id == _held_layer and index == _held_slot)
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
	for column_rule: Rect2 in _column_rules():
		draw_line(column_rule.position, column_rule.end, Color(MUTED, .28), .9, true)
	for id: String in LAYERS:
		if not _layout_layers.has(id): continue
		var info: Dictionary = _layout_layers[id]
		var title: Rect2 = info.title_rect
		draw_string(HEADING_FONT, title.position + Vector2(0, (title.size.y-HEADING_FONT.get_height(HEADING_SIZE))*.5+HEADING_FONT.get_ascent(HEADING_SIZE)), DeskLocalization.text(TITLES[id]), HORIZONTAL_ALIGNMENT_LEFT, title.size.x, HEADING_SIZE, INK)
		var rule: Rect2 = info.heading_rule
		draw_line(rule.position, rule.end, Color(INK, .35), 1.0, true)
		if id == _layer: draw_line(rule.position, rule.position + Vector2(32, 0), Color(INK, .85), 2.0, true)
		if id in ["stance","pragmatic"]: _draw_axis(id)
		else: _draw_slots(id)

func _column_rules() -> Array[Rect2]:
	return [Rect2(Vector2(size.x * .38, size.y * .19), Vector2(0, size.y * .735)),
		Rect2(Vector2(size.x * .675, size.y * .075), Vector2(0, _layout_layers.stance.rect.size.y)),
		Rect2(Vector2(size.x * .055, _layout_layers.topics.rect.position.y - size.y * .03), Vector2(size.x * .89, 0))]

func _slot_shape(id: String) -> String:
	return CardFace.SHAPES.get("topic" if id == "topics" else id, "xy_plane")

func _socket_outline(id: String, rect: Rect2) -> PackedVector2Array:
	var kind := "topic" if id == "topics" else id
	var dimensions := CardFace.minimum_card_size(kind)
	var points := CardFace.outline_for(kind, Rect2(4, 3, dimensions.x - 10, dimensions.y - 10))
	var scaled := PackedVector2Array()
	for point: Vector2 in points: scaled.append(rect.position + point * rect.size / dimensions)
	return scaled

func _draw_slot_socket(id: String, rect: Rect2, selected: bool, occupied: bool) -> void:
	var outline := _socket_outline(id, rect.grow(4))
	draw_colored_polygon(outline, Color(INK, .02 if occupied else .035))
	outline.append(outline[0])
	draw_polyline(outline, Color(INK, .75 if selected else .38), 1.7 if selected else 1.0, true)

func can_choose_context_slot(layer: String, slot: int) -> bool:
	var kind := "topic" if layer == "topics" else layer
	for record: Dictionary in _state.get("resources", []):
		if str(record.kind) != kind or int(record.get("available", 0)) <= 0: continue
		if ContextController.can_install(_state, _rules, layer, slot, {"type":"context_resource", "resource_id":str(record.id)}): return true
	return false

func install_context_resource(layer: String, slot: int, resource_id: String) -> bool:
	if not _enabled or not ContextController.can_install(_state, _rules, layer, slot, {"type":"context_resource", "resource_id":resource_id}): return false
	perform("install_context", {"layer":layer, "slot":slot, "resource_id":resource_id})
	var current: Array = _layers().get(layer, {}).get("slots", [])
	return str(current[slot].get("resource_id", "")) == resource_id

func _draw_slots(id: String) -> void:
	var info: Dictionary = _layout_layers[id]
	var slots: Array = _layers().get(id, {}).get("slots", [])
	for index in (info.slot_centres as Array).size():
		var rect: Rect2 = info.slot_rects[index]
		var occupied: bool = index < slots.size() and not slots[index].is_empty()
		_draw_slot_socket(id, rect, id == _layer and index == _selected_slot, occupied)
		if not occupied:
			var center := rect.get_center() - Vector2(2, 2)
			var radius := minf(8, minf(rect.size.x, rect.size.y) * .12)
			var plus_ink := Color(INK, .55 if can_choose_context_slot(id, index) else .16)
			draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), plus_ink, 1.8, true)
			draw_line(center - Vector2(0, radius), center + Vector2(0, radius), plus_ink, 1.8, true)

func set_token_drag(token_id: String) -> void:
	var layer := ""
	for id: String in ["stance", "pragmatic"]:
		if token_id in _layers().get(id, {}).get("token_ids", {}).values(): layer = id
	if layer == _token_drag_layer: return
	_token_drag_layer = layer
	queue_redraw()

func _reachable_cells(id: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not ((_axis_drag and _held_layer == id) or _token_drag_layer == id): return result
	var data: Dictionary = _layers().get(id, {})
	var ranges: Array = data.get("reachable_offsets", [])
	if ranges.is_empty(): return result
	var cell_size := Vector2.ONE * float(_layout_layers[id].grid_spacing) * .84
	var step := float(data.step)
	for x in range(int(ranges[0][0]), int(ranges[0][1]) + 1):
		for y in range(int(ranges[1][0]), int(ranges[1][1]) + 1):
			var coordinate := [clampf(float(data.origin[0]) + x * step, -1, 1), clampf(float(data.origin[1]) + y * step, -1, 1)]
			result.append(Rect2(_axis_position(id, coordinate) - cell_size * .5, cell_size).intersection(_layout_layers[id].plot_rect))
	return result

func _draw_axis(id: String) -> void:
	var info: Dictionary = _layout_layers[id]
	var plot: Rect2 = info.plot_rect
	var data: Dictionary = _layers().get(id, {})
	var center := plot.get_center()
	draw_rect(plot, info.grid_fill_color)
	for cell: Rect2 in _reachable_cells(id): draw_rect(cell, REACHABLE_INK)
	draw_multiline(info.grid_lines, info.grid_color, .7, true)
	for tick in 11:
		var t := float(tick)/10.0
		if tick == 5: continue
		draw_line(Vector2(plot.position.x+plot.size.x*t,center.y-2),Vector2(plot.position.x+plot.size.x*t,center.y+2),Color(MUTED,.35),.8,true)
		draw_line(Vector2(center.x-2,plot.position.y+plot.size.y*t),Vector2(center.x+2,plot.position.y+plot.size.y*t),Color(MUTED,.35),.8,true)
	_draw_pencil_path(PackedVector2Array([Vector2(plot.position.x,center.y),center+Vector2(3,-1),Vector2(plot.end.x,center.y+1)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(center.x+1,plot.end.y),center-Vector2(1,4),Vector2(center.x,plot.position.y)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(plot.end.x-10,center.y-6),Vector2(plot.end.x,center.y+1),Vector2(plot.end.x-9,center.y+7)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(center.x-6,plot.position.y+10),Vector2(center.x,plot.position.y),Vector2(center.x+6,plot.position.y+10)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(plot.position.x+9,center.y-6),Vector2(plot.position.x,center.y),Vector2(plot.position.x+9,center.y+6)]),Color(INK,.75),1.2)
	_draw_pencil_path(PackedVector2Array([Vector2(center.x-6,plot.end.y-9),Vector2(center.x,plot.end.y),Vector2(center.x+6,plot.end.y-9)]),Color(INK,.75),1.2)
	var label_layouts := _axis_label_layouts(id)
	for key: String in ["x_negative", "x_positive", "y_negative", "y_positive"]:
		for line: Dictionary in label_layouts[key].lines: draw_rect((line.rect as Rect2).grow(2), Color("eee6d3", .94))
		_draw_text_layout(label_layouts[key])
	var known := id != "stance" or bool(data.get("known", false))
	var anchor := _axis_point(id) if known else _axis_origin(id)
	var active := _enabled and (_hover_target == id + "/axis" or (_axis_drag and _held_layer == id))
	if known: draw_circle(anchor, AXIS_HANDLE_RADIUS - 1, Color("eee6d3"))
	draw_arc(anchor, AXIS_HANDLE_RADIUS - 1, 0, TAU, 32, Color(INK, .85 if active else .55), 1.8 if active else 1.2, true)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(anchor + direction * 9, anchor + direction * 14, Color(INK, .65), 1.2, true)
	draw_arc(_axis_origin(id), 7, 0, TAU, 28, INK, 1.5, true)
	if known: draw_circle(_axis_point(id), 4, INK)

func _axis_labels(id: String) -> Dictionary:
	var labels := {"x_negative":DeskLocalization.text("LOC_FREEDOM_D1047EED") if id == "stance" else DeskLocalization.text("LOC_SINCERITY_8BB7FF57"), "x_positive":DeskLocalization.text("LOC_AUTHORITY_E9D827BA") if id == "stance" else DeskLocalization.text("LOC_IRONY_06D9BA32"), "y_negative":DeskLocalization.text("LOC_EQUALITY_14DD2491") if id == "stance" else DeskLocalization.text("LOC_SUPPORT_D93373F8"), "y_positive":DeskLocalization.text("LOC_HIERARCHY_33771717") if id == "stance" else DeskLocalization.text("LOC_OPPOSITION_454F03C9")}
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
	var labels := _axis_labels(id)
	var font := get_theme_default_font()
	var side_width := plot.size.x * .5 - 12
	var areas := {
		"x_negative":Rect2(Vector2(plot.position.x + 4, center.y + 8), Vector2(side_width, 18)),
		"x_positive":Rect2(Vector2(center.x + 8, center.y + 8), Vector2(side_width, 18)),
		"y_negative":Rect2(Vector2(center.x + 8, plot.position.y + 2), Vector2(side_width, 18)),
		"y_positive":Rect2(Vector2(center.x + 8, plot.end.y - 20), Vector2(side_width, 18))}
	var known := id != "stance" or bool(_layers().get(id, {}).get("known", false))
	var anchor := _axis_point(id) if known else _axis_origin(id)
	var marker := Rect2(anchor - Vector2.ONE * 16, Vector2.ONE * 32)
	var result := {}
	for key: String in areas:
		var area: Rect2 = areas[key]
		var label_width := minf(area.size.x, ceilf(font.get_string_size(str(labels[key]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 2)
		if key == "x_positive": area.position.x = plot.end.x - label_width - 4
		area.size.x = label_width
		var layout := ResourceGraphic.fit_text(font, str(labels[key]), area, 12, 12, 1)
		if not layout.lines.is_empty() and (layout.lines[0].rect as Rect2).grow(2).intersects(marker):
			var alternate: Rect2 = areas[key]
			if key.begins_with("x_"):
				alternate.position.y = center.y + 16
			else:
				alternate.position.x = plot.position.x + 4 if anchor.x >= center.x else center.x + 4
				alternate.size.x = plot.size.x * .5 - 8
			var candidate := ResourceGraphic.fit_text(font, str(labels[key]), alternate, 12, 12, 1)
			if not candidate.truncated and not candidate.lines.is_empty() and not (candidate.lines[0].rect as Rect2).grow(2).intersects(marker): layout = candidate
		result[key] = layout
	return result

func _axis_point(id: String) -> Vector2:
	return _axis_position(id, _layers().get(id, {}).get("current", [0.0, 0.0]))

func _axis_origin(id: String) -> Vector2:
	return _axis_position(id, _layers().get(id, {}).get("origin", [0.0, 0.0]))

func _axis_position(id: String, values: Array) -> Vector2:
	var plot: Rect2 = _layout_layers.get(id, {}).get("plot_rect", Rect2())
	return plot.get_center() + Vector2(float(values[0]), float(values[1])) * plot.size * 0.5

func _layer_at(point: Vector2) -> String:
	# Card hit areas take precedence over the surrounding section.
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
		if (rectangles[index] as Rect2).has_point(point): return index
	return -1

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	if not _enabled or not data is Dictionary:
		return false
	var layer := _layer_at(point)
	return ContextController.can_install(_state, _rules, layer, _slot_at(layer, point), data)

func tabletop_drop_pose(kind: String, id: String, global_point: Vector2) -> Dictionary:
	var point := get_global_transform_with_canvas().affine_inverse() * global_point
	if not _can_drop_data(point, {"type":"context_resource", "kind":kind, "resource_id":id}): return {}
	var rect: Rect2 = _layout_layers[_layer_at(point)].slot_rects[_slot_at(_layer_at(point), point)]
	return {"center":get_global_transform_with_canvas() * rect.get_center(), "rotation":get_global_transform_with_canvas().get_rotation()}

func _drop_data(point: Vector2, data: Variant) -> void:
	if not _can_drop_data(point, data):
		_slot_rejections += 1
		return
	var id := _layer_at(point)
	select_layer(id)
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

func _gui_input(event: InputEvent) -> void:
	if not _enabled: return
	if event is InputEventMouseMotion: _update_pointer(event.position)
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
		_update_resource_drag()
		if _axis_drag:
			var delta: Vector2 = event.position - _press_point
			var plot: Rect2 = _layout_layers[_held_layer].plot_rect
			var step := float(_layers().get(_held_layer, {}).get("step", 0.1))
			# Start after a small movement, then track both coordinates through the origin.
			var threshold := minf(DRAG_THRESHOLD, minf(plot.size.x, plot.size.y) * step * 0.175)
			_held_moved = _held_moved or delta.length() > threshold
			if _held_moved: _move_axis(event.position)
		queue_redraw()
		accept_event()

func _begin_pointer(point: Vector2) -> void:
	_cancel_input()
	var id := _layer_at(point)
	if id.is_empty(): return
	_layer = id
	_selected_slot = _slot_at(id, point)
	_press_point = point
	_held_layer = id
	_held_slot = _selected_slot
	_held = "selection"
	if id in ["stance", "pragmatic"]:
		var anchor := _axis_point(id)
		if id == "stance" and not bool(_layers().get(id, {}).get("known", false)): anchor = _axis_origin(id)
		if point.distance_to(anchor) <= AXIS_HANDLE_RADIUS:
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
	_sync_graphics()
	queue_redraw()

func _on_mouse_exited() -> void:
	_hover_target = ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()

func cursor_shape_at(point: Vector2) -> int:
	var id := _layer_at(point)
	if id.is_empty(): return Control.CURSOR_ARROW
	if not _enabled: return Control.CURSOR_FORBIDDEN
	if id in ["stance", "pragmatic"]:
		var anchor := _axis_origin(id) if id == "stance" and not bool(_layers().get(id, {}).get("known", false)) else _axis_point(id)
		if point.distance_to(anchor) <= AXIS_HANDLE_RADIUS: return Control.CURSOR_POINTING_HAND
	else:
		var slot := _slot_at(id, point)
		var slots: Array = _layers().get(id, {}).get("slots", [])
		if slot >= 0 and slot < slots.size():
			if not slots[slot].is_empty() or can_choose_context_slot(id, slot): return Control.CURSOR_POINTING_HAND
			return Control.CURSOR_FORBIDDEN
	return Control.CURSOR_ARROW if hover_info(get_global_transform_with_canvas() * point).is_empty() else Control.CURSOR_HELP

func _update_pointer(point: Vector2) -> void:
	var id := _layer_at(point)
	var target := id
	var cursor := cursor_shape_at(point)
	if not id.is_empty():
		if id in ["stance", "pragmatic"]:
			var anchor := _axis_point(id)
			if id == "stance" and not bool(_layers().get(id, {}).get("known", false)): anchor = _axis_origin(id)
			if point.distance_to(anchor) <= AXIS_HANDLE_RADIUS:
				target += "/axis"
				cursor = Control.CURSOR_DRAG
		else:
			var slot := _slot_at(id, point)
			var slots: Array = _layers().get(id, {}).get("slots", [])
			if slot >= 0 and slot < slots.size() and not slots[slot].is_empty(): cursor = Control.CURSOR_DRAG
	mouse_default_cursor_shape = cursor
	if target != _hover_target:
		_hover_target = target
		queue_redraw()

func _update_resource_drag() -> void:
	if _held != "resource" or not _held_moved: return
	if not _resource_dragging:
		_resource_dragging = true
		var slot: Dictionary = _layers()[_held_layer].slots[_held_slot]
		var record := _resource(str(slot.get("resource_id", slot.get("id", "")))).duplicate(true)
		record.count = 1
		_drag_preview = CardFace.new()
		_drag_preview.name = "PickedUpContextCard"
		_drag_preview.z_index = 100
		_drag_preview_parent.add_child(_drag_preview)
		_drag_preview.configure(record, get_theme_default_font())
		_drag_preview.size = CardFace.minimum_card_size(str(record.kind))
		var host_transform := _drag_preview_parent.get_global_transform_with_canvas().affine_inverse() * get_global_transform_with_canvas()
		_drag_preview.rotation = host_transform.get_rotation()
		_drag_preview.scale = host_transform.get_scale() * _layout_layers[_held_layer].slot_rects[_held_slot].size / _drag_preview.size
		_drag_preview.position = host_transform * _layout_layers[_held_layer].slot_rects[_held_slot].position
		_sync_graphics()
	var board_point := get_global_transform_with_canvas().affine_inverse() * _last_point
	var slot := _slot_at(_held_layer, board_point)
	var center := _last_point
	if slot >= 0: center = get_global_transform_with_canvas() * _layout_layers[_held_layer].slot_rects[slot].get_center()
	_drag_preview.placement = CardFace.Placement.TARGETED if slot >= 0 else CardFace.Placement.DRAGGING
	_drag_target = _drag_preview_parent.get_global_transform_with_canvas().affine_inverse() * center - _drag_preview.get_transform().basis_xform(_drag_preview.size * .5)

func _process(delta: float) -> void:
	if _resource_dragging:
		_drag_preview.position = _drag_preview.position.lerp(_drag_target, 1.0 - exp(-24.0 * delta))

func _release_pointer(point: Vector2) -> void:
	var held := _held
	var id := _held_layer
	var slot := _held_slot
	var moved := _held_moved
	var resource_dragged := _resource_dragging
	_cancel_input()
	if id.is_empty(): return
	if not moved:
		var index := slot if slot >= 0 else _slot_at(id,point)
		if id in ["language", "group", "topics"] and index >= 0:
			var slots: Array = _layers().get(id, {}).get("slots", [])
			if slots[index].is_empty() and not can_choose_context_slot(id, index): return
		slot_pressed.emit(id,index,layer_viewport_rect(id))
		return
	if held == "resource" and resource_dragged and _slot_at(id, point) != slot:
		var slots: Array = _layers().get(id, {}).get("slots", [])
		if slot < 0 or slot >= slots.size() or slots[slot].is_empty(): return
		var target := _slot_at(id, point)
		if target >= 0:
			perform("move_context", {"layer":id, "slot":slot, "target_slot":target})
		else:
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
	var origin: Array = data.get("origin", [0.0, 0.0])
	var targets: Array = []
	for axis in 2:
		var value := clampf((point[axis] - plot.get_center()[axis]) / (plot.size[axis] * 0.5), -1.0, 1.0)
		targets.append(roundi((value - float(origin[axis])) / step))
	_commands.move_axes(_layers, perform, id, targets)
	selected_info_changed.emit(selected_info())
	queue_redraw()

func _cancel_input() -> void:
	if is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
		_drag_preview = null
	_resource_dragging = false
	for graphic: Control in _resource_graphics.values(): graphic.show()
	_held = ""
	_held_layer = ""
	_held_slot = -1
	_held_moved = false
	_axis_drag = false
	queue_redraw()

func _get_drag_data(_position: Vector2) -> Variant:
	# Commit inventory changes on release after distinguishing a drag from a click.
	return null

func inspection() -> Dictionary:
	var layers := {}
	var visible: Array = []
	for id: String in LAYERS:
		var info: Dictionary = _layout_layers.get(id, {}).duplicate(true)
		info.slot_shape = _slot_shape(id)
		info.slot_material = "fitted_card_socket" if id in ["language","group","topics"] else "pencil_axes"
		info.pin_style = ""
		info.heading_rect = Rect2(info.rect.position, Vector2(info.rect.size.x, 32))
		info.heading_font_size = HEADING_SIZE
		info.heading_emphasis = "semibold"
		info.empty_slot_style = "card_silhouette_plus" if id in ["language", "group", "topics"] else "axis_drag_handle"
		var quads: Array = []
		for rect: Rect2 in info.get("slot_rects", []):
			quads.append(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]))
		info.slot_quads = quads
		if id in ["stance", "pragmatic"]:
			info.coordinate_readout_visible = false
			info.reachable_cells = _reachable_cells(id)
			info.reachable_color = REACHABLE_INK
			info.axis_rect = info.plot_rect
			info.axis_labels = _axis_labels(id)
			info.axis_label_positions = _axis_label_positions(id)
			info.axis_label_layouts = _axis_label_layouts(id)
			info.axis_label_rects = {}
			for key: String in info.axis_label_layouts:
				var lines: Array = info.axis_label_layouts[key].lines
				info.axis_label_rects[key] = lines[0].rect if not lines.is_empty() else Rect2()
			info.axis_handle_radius = AXIS_HANDLE_RADIUS
			info.marker_known = bool(_layers().get(id, {}).get("known", false)) if id == "stance" else true
			info.axis_point = _axis_point(id)
			info.axis_origin = _axis_origin(id)
			info.known = bool(_layers().get(id, {}).get("known", false)) if id == "stance" else true
			info.current_marker_visible = info.known
			info.origin_marker_shape = "hollow_circle"
			info.current_marker_shape = "solid_circle" if info.known else "none"
			info.target = _target() if id == "pragmatic" else ""
		else:
			info.axis_point = Vector2.ZERO
			info.axis_origin = Vector2.ZERO
		layers[id] = info
		visible.append(id)
	var selected: Dictionary = layers.get(_layer, {})
	return {"layout_mode":"assembly_board", "layout_version":17, "layers":layers, "visible_layers":visible, "section_icon_count":_heading_icons.size(), "column_rules":_column_rules(), "instruction_labels_visible":false, "subviewport_count":0, "displayed_cells":5, "layer":_layer, "slot_shape":selected.get("slot_shape", ""), "slot_shapes":"physical_card_silhouettes", "slot_centres":selected.get("slot_centres", []), "slot_quads":selected.get("slot_quads", []), "slot_pickup_rects":selected.get("slot_pickup_rects", []), "axis_point":selected.get("axis_point", Vector2.ZERO), "axis_origin":selected.get("axis_origin", Vector2.ZERO), "axis_drag":_axis_drag, "axis":-1, "interaction_enabled":_enabled, "selection":selected_info(), "action_count":_action_count, "slot_rejections":_slot_rejections, "resource_graphics":_resource_graphics.keys(), "panel_background_count":0, "topic_pin_style":"none", "gesture":_held, "gesture_layer":_held_layer, "focus_unit":"block", "drag_threshold":DRAG_THRESHOLD, "resource_dragging":_resource_dragging}

func _viewport_rect(rect: Rect2) -> Rect2:
	var transform := get_global_transform_with_canvas()
	var result := Rect2(transform*rect.position,Vector2.ZERO)
	for point: Vector2 in [rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: result = result.expand(transform*point)
	return result

func layer_viewport_rect(layer: String) -> Rect2:
	return _viewport_rect(_layout_layers[layer].rect)

func hover_info(viewport_point: Vector2) -> Dictionary:
	var point := get_global_transform_with_canvas().affine_inverse()*viewport_point
	var layer := _layer_at(point)
	if layer.is_empty(): return {}
	if (_layout_layers[layer].heading_hit_rect as Rect2).has_point(point):
		var copy := ComponentCopy.for_kind("context/" + layer)
		return {"kind":"topic" if layer == "topics" else layer, "title":TITLES[layer], "hover_description":copy.description, "hover_note":copy.note}
	var index := _slot_at(layer,point)
	var data: Dictionary = _layers().get(layer,{})
	var result := {"layer":layer,"slot":index,"title":TITLES[layer],"text":""}
	if layer in ["stance","pragmatic"]:
		result.kind = layer
		result.text = ""
		var directions := {"x_negative":"freedom", "x_positive":"authority", "y_negative":"equality", "y_positive":"hierarchy"} if layer == "stance" else {"x_negative":"sincere", "x_positive":"ironic", "y_negative":"support", "y_positive":"opposition"}
		var labels := _axis_labels(layer)
		var layouts := _axis_label_layouts(layer)
		for key: String in layouts:
			for line: Dictionary in layouts[key].lines:
				if (line.rect as Rect2).grow(2).has_point(point):
					var resource := _resource(directions[key])
					return {"kind":layer, "id":directions[key], "title":labels[key], "description":resource.get("description", ""), "resource":resource}
		return {}
	elif index >= 0:
		var slots: Array = data.get("slots",[])
		var resource := _resource(str(slots[index].get("resource_id",slots[index].get("id","")))) if index < slots.size() else {}
		if resource.is_empty(): return {}
		result.title = resource.get("title",TITLES[layer])
		result.text = resource.get("description","")
		result.resource = resource.duplicate(true)
		return result
	return {}
