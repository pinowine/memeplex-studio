class_name DeskContextSlice
extends Control

signal action_requested(action: String, params: Dictionary)
signal selected_info_changed(info: Dictionary)
signal depth_changed(layer: String, depth: float)
signal resource_detached(record: Dictionary, global_point: Vector2)
signal context_layer_detached(record: Dictionary, global_point: Vector2)

const SliceProjection = preload("res://scripts/demo/desk_slice_projection.gd")
const LAYERS := ["language", "group", "topics", "stance", "pragmatic"]
const TITLES := ["语言", "群体", "话题", "立场", "语用"]
const DEPTHS := [0.1, 0.3, 0.5, 0.7, 0.9]
const PLANE_SIZE := Vector2(640, 640)

class Surface extends Control:
	var view: Control
	func _draw() -> void:
		if is_instance_valid(view): view._draw_surface(self)

var _rules: Resource
var _state := {}
var _projection := SliceProjection.new()
var _quad := PackedVector2Array()
var _viewport: SubViewport
var _surface: Surface
var _image: TextureRect
var _backplate: TextureRect
var _volume_rect := Rect2()
var _output: TextureRect
var _slider: VSlider
var _depth := 0.1
var _visual_depth := 0.1
var _layer := "language"
var _enabled := true
var _selected_slot := -1
var _axis_drag := false
var _axis := -1
var _press_uv := Vector2.ZERO
var _held_record := {}
var _held_slot := -1
var _held_moved := false
var _action_callback := Callable()
var _resource_factory := Callable()
var _resource_graphics := {}
var _request_session := Crypto.new().generate_random_bytes(12).hex_encode()
var _request_index := 0
var _action_count := 0
var _slot_rejections := 0
var _plane_only := false
var _held_plane := false
var _native_plane: Dictionary = {}
var _last_pointer := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	custom_minimum_size = Vector2(260, 230)
	_viewport = SubViewport.new()
	_viewport.name = "SliceViewport"
	_viewport.size = Vector2i(PLANE_SIZE)
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_surface = Surface.new()
	_surface.name = "SliceSurface"
	_surface.view = self
	_surface.size = PLANE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.theme = theme
	_viewport.add_child(_surface)
	_image = TextureRect.new()
	_image.name = "BrainImage"
	_image.position = PLANE_SIZE * Vector2(0.11, 0.13)
	_image.size = PLANE_SIZE * Vector2(0.78, 0.78)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/desk/v10/brain_slice.png"):
		_image.texture = load("res://assets/desk/v10/brain_slice.png")
	var brain_material := ShaderMaterial.new()
	brain_material.shader = load("res://shaders/desk_brain_slice.gdshader")
	brain_material.set_shader_parameter("brain_atlas", _image.texture)
	_image.material = brain_material
	var paper := ColorRect.new()
	paper.name = "SlicePaper"
	paper.size = PLANE_SIZE
	paper.color = Color(0.93,0.92,0.85,0.64)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(paper)
	_surface.add_child(_image)
	# Draw the interaction marks above the image.
	var overlay := Surface.new()
	overlay.name = "SliceMarks"
	overlay.view = self
	overlay.size = PLANE_SIZE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(overlay)
	_surface.view = null
	_surface = overlay
	_backplate = TextureRect.new()
	_backplate.name = "VolumeReference"
	_backplate.texture = load("res://assets/desk/v10/brain_reference_base.png")
	_backplate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backplate.stretch_mode = TextureRect.STRETCH_SCALE
	_backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reference_material := ShaderMaterial.new()
	reference_material.shader = load("res://shaders/desk_brain_reference.gdshader")
	_backplate.material = reference_material
	add_child(_backplate)
	_output = TextureRect.new()
	_output.name = "ProjectedSlice"
	_output.texture = _viewport.get_texture()
	_output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output.stretch_mode = TextureRect.STRETCH_SCALE
	_output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var projected := ShaderMaterial.new()
	projected.shader = load("res://shaders/desk_slice_projection.gdshader")
	_output.material = projected
	add_child(_output)
	_slider = VSlider.new()
	_slider.name = "DepthControl"
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = _depth
	_slider.value_changed.connect(_depth_input)
	_slider.tooltip_text = ""
	add_child(_slider)
	resized.connect(_layout)
	get_window().focus_exited.connect(_cancel_input)
	_layout()
	_refresh()

func configure(rules: Resource) -> void:
	_rules = rules
	_refresh()

func set_state(design: Dictionary) -> void:
	var data: Dictionary = design.get("design_state", design)
	_state = data.duplicate(true)
	var layer: Dictionary = _layers().get(_layer, {})
	if layer.has("depth"): set_depth(float(layer.depth))
	_refresh()

func sync_state(design: Dictionary) -> void:
	set_state(design)

func set_action_callback(callback: Callable) -> void:
	_action_callback = callback

func set_resource_factory(factory: Callable) -> void:
	_resource_factory = factory
	for graphic: Control in _resource_graphics.values():
		graphic.get_parent().remove_child(graphic)
		graphic.queue_free()
	_resource_graphics.clear()
	_refresh()

func perform(action: String, params: Dictionary) -> void:
	if not _enabled: return
	_action_count += 1
	if _action_callback.is_valid(): _action_callback.call(action, params.duplicate(true))
	else: action_requested.emit(action, params.duplicate(true))

func set_interaction_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled: _cancel_input()
	if is_instance_valid(_slider): _slider.editable = enabled
	_refresh()

func select_layer(id: String) -> void:
	if id not in LAYERS: return
	_cancel_input()
	_layer = id
	_selected_slot = -1
	var data: Dictionary = _layers().get(id, {})
	set_depth(float(data.get("depth", DEPTHS[LAYERS.find(id)])))
	_refresh()
	selected_info_changed.emit(selected_info())

func set_depth(value: float) -> void:
	if not is_finite(value): return
	_depth = clampf(value, 0.0, 1.0)
	if is_instance_valid(_slider): _slider.set_value_no_signal(_depth)
	_refresh()

func depth_control() -> VSlider:
	return _slider

func project_point(plane_point: Vector2) -> Vector2:
	return _projection.project(plane_point)

func unproject_point(local_point: Vector2) -> Vector2:
	return _projection.unproject(local_point)

func selected_info() -> Dictionary:
	var result := {"layer": _layer, "title": TITLES[LAYERS.find(_layer)], "depth": _depth, "slot": _selected_slot}
	var data: Dictionary = _layers().get(_layer, {})
	if _layer in ["stance", "pragmatic"]:
		result.merge(data.duplicate(true), true)
	elif _selected_slot >= 0 and _selected_slot < data.get("slots", []).size():
		var slot: Dictionary = data.slots[_selected_slot]
		result["resource"] = _resource(str(slot.get("resource_id", slot.get("id", "")))).duplicate(true)
	return result

func inspection() -> Dictionary:
	var centres := []
	var rectangles := []
	for point: Vector2 in _slot_points():
		centres.append(project_point(point))
		var corners := PackedVector2Array()
		for delta: Vector2 in [Vector2(-0.075, -0.075), Vector2(0.075, -0.075), Vector2(0.075, 0.075), Vector2(-0.075, 0.075)]: corners.append(project_point(point + delta))
		rectangles.append(corners)
	return {"layout_version": 11, "plane_id":str(_layers().get(_layer,{}).get("plane_id","")), "attached":_attached(), "plane_only":_plane_only, "image_opacity":0.90, "layer": _layer, "depth": _depth, "visual_depth": _visual_depth, "quad": _quad, "homography": _projection.forward.duplicate(), "inverse_homography": _projection.inverse.duplicate(), "projection_valid": _projection.valid, "slot_centres": centres, "slot_quads": rectangles, "slot_shapes": "open circle / rounded open triangle / three pins", "resource_graphics": _resource_graphics.keys(), "axis_point": project_point(_axis_point()), "axis_origin": project_point(_axis_origin()), "axis_drag": _axis_drag, "axis": _axis, "interaction_enabled": _enabled, "action_count": _action_count, "slot_rejections": _slot_rejections, "brain_texture": "" if not is_instance_valid(_image) or _image.texture == null else _image.texture.resource_path, "brain_shader": "res://shaders/desk_brain_slice.gdshader", "displayed_cells": 1, "depth_ticks": DEPTHS.duplicate(), "selection": selected_info(), "reference_texture": "" if not is_instance_valid(_backplate) else _backplate.texture.resource_path, "reference_rect": _volume_rect, "volume_backplate": true, "active_plane_count": 1 if _attached() or _plane_only else 0, "plane_depth": _depth}

func _process(delta: float) -> void:
	_visual_depth = move_toward(_visual_depth, _depth, delta * 2.0)
	if is_instance_valid(_image): _image.material.set_shader_parameter("blend_depth", _visual_depth)

func _layout() -> void:
	_cancel_input()
	var width := maxf(160.0, size.x - 76.0)
	var height := maxf(180.0, size.y - 32.0)
	var reference_size: Vector2 = _backplate.texture.get_size()
	var volume_size := reference_size * minf(width / reference_size.x, height / reference_size.y)
	_volume_rect = Rect2(Vector2((width - volume_size.x) * 0.5 + 9, (height - volume_size.y) * 0.5 + 14), volume_size)
	if is_instance_valid(_backplate):
		_backplate.position = _volume_rect.position
		_backplate.size = _volume_rect.size
	_update_plane()
	if not is_instance_valid(_slider): return
	_slider.position = Vector2(size.x - 52, 38)
	_slider.size = Vector2(20, maxf(100, size.y - 88))
	queue_redraw()

func _update_plane() -> void:
	# The same depth plane drives rendering and inverse input.
	var top := lerpf(0.08, 0.36, _depth)
	var bottom := lerpf(0.62, 0.83, _depth)
	var inset := lerpf(0.09, 0.16, _depth)
	_quad = PackedVector2Array()
	for point: Vector2 in [Vector2(inset + 0.06, top + 0.03), Vector2(1.0 - inset - 0.05, top), Vector2(1.0 - inset, bottom - 0.035), Vector2(inset, bottom)]:
		_quad.append(_volume_rect.position + point * _volume_rect.size)
	if _plane_only: _quad = PackedVector2Array([Vector2(4,4),Vector2(size.x-4,4),size-Vector2(4,4),Vector2(4,size.y-4)])
	_projection.fit(_quad)
	if not is_instance_valid(_output): return
	_output.visible = _attached() or _plane_only
	_output.size = size
	var matrix: Array[float] = _projection.inverse
	if _projection.valid:
		_output.material.set_shader_parameter("inverse_x", Vector3(matrix[0], matrix[1], matrix[2]))
		_output.material.set_shader_parameter("inverse_y", Vector3(matrix[3], matrix[4], matrix[5]))
		_output.material.set_shader_parameter("inverse_w", Vector3(matrix[6], matrix[7], matrix[8]))
		_output.material.set_shader_parameter("display_size", size)
	queue_redraw()

func _draw() -> void:
	if _plane_only or not is_instance_valid(_slider): return
	var font := get_theme_font("font", "Label")
	var ink := Color(0.19, 0.23, 0.21)
	draw_string(font, Vector2(size.x - 69, 20), "深度", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	for index in DEPTHS.size():
		var y: float = _slider.position.y + _slider.size.y * (1.0 - DEPTHS[index])
		draw_line(Vector2(size.x - 60, y), Vector2(size.x - 54, y), ink, 1, true)
		draw_string(font, Vector2(size.x - 29, y + 4), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)

func _draw_surface(canvas: Control) -> void:
	var font := get_theme_font("font", "Label")
	var ink := Color(0.09, 0.17, 0.13, 0.95)
	var pale := Color(0.90, 0.88, 0.78, 0.94)
	canvas.draw_polyline(PackedVector2Array([Vector2(2, 2), Vector2(638, 2), Vector2(638, 638), Vector2(2, 638), Vector2(2, 2)]), Color(0.20, 0.34, 0.28, 0.42), 2, true)
	canvas.draw_string(font, PLANE_SIZE * Vector2(0.16, 0.09), TITLES[LAYERS.find(_layer)], HORIZONTAL_ALIGNMENT_LEFT, -1, 27, ink)
	if _layer in ["stance", "pragmatic"]:
		var data: Dictionary = _layers().get(_layer, {})
		var labels: Dictionary = data.get("axis_labels", {"x_negative": "自由" if _layer == "stance" else "真诚", "x_positive": "威权" if _layer == "stance" else "反讽", "y_negative": "平等" if _layer == "stance" else "支持", "y_positive": "等级" if _layer == "stance" else "反对"})
		canvas.draw_line(PLANE_SIZE * Vector2(0.20, 0.52), PLANE_SIZE * Vector2(0.80, 0.52), pale, 3, true)
		canvas.draw_line(PLANE_SIZE * Vector2(0.5, 0.22), PLANE_SIZE * Vector2(0.5, 0.82), pale, 3, true)
		for index in 21:
			var step := 0.22 + index * 0.028
			canvas.draw_line(PLANE_SIZE * Vector2(step, 0.51), PLANE_SIZE * Vector2(step, 0.53), pale, 1, true)
			canvas.draw_line(PLANE_SIZE * Vector2(0.49, step + 0.02), PLANE_SIZE * Vector2(0.51, step + 0.02), pale, 1, true)
		for entry: Array in [["x_negative", Vector2(0.06, 0.53)], ["x_positive", Vector2(0.82, 0.53)], ["y_negative", Vector2(0.45, 0.18)], ["y_positive", Vector2(0.45, 0.90)]]:
			canvas.draw_string(font, PLANE_SIZE * entry[1], str(labels.get(entry[0], "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
		canvas.draw_arc(_axis_origin() * PLANE_SIZE, 11, 0, TAU, 32, pale, 2, true)
		canvas.draw_circle(_axis_point() * PLANE_SIZE, 9, ink if _enabled else Color(0.4, 0.4, 0.4))
	else:
		var slots: Array = _layers().get(_layer, {}).get("slots", [])
		var points := _slot_points()
		for index in points.size():
			var centre: Vector2 = points[index] * PLANE_SIZE
			var record: Dictionary = slots[index] if index < slots.size() else {}
			var resource := _resource(str(record.get("resource_id", record.get("id", ""))))
			if _resource_graphics.has(index):
				if index == _selected_slot: canvas.draw_arc(centre, 54, 0, TAU, 48, ink, 2, true)
				continue
			canvas.draw_circle(centre, 46, pale)
			if _layer == "language": canvas.draw_arc(centre, 43, 0.22, TAU - 0.22, 48, ink, 3, true)
			elif _layer == "group":
				canvas.draw_polyline(_rounded_triangle(centre), ink, 3, true)
			else:
				canvas.draw_circle(centre + Vector2(0, -29), 7, ink)
				canvas.draw_line(centre + Vector2(0, -21), centre + Vector2(0, 20), ink, 2, true)
			var text := str(resource.get("title", "空位"))
			canvas.draw_string(font, centre + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, 70), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
			if index == _selected_slot: canvas.draw_arc(centre, 51, 0, TAU, 48, ink, 2, true)

func _slot_points() -> Array[Vector2]:
	if _layer in ["language", "group"]: return [Vector2(0.5, 0.5)]
	if _layer == "topics": return [Vector2(0.28, 0.49), Vector2(0.5, 0.49), Vector2(0.72, 0.49)]
	return []

func _rounded_triangle(centre: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([centre + Vector2(-6, -35), centre + Vector2(-34, 18)])
	for corner: Array in [[Vector2(-34, 18), Vector2(-42, 32), Vector2(-26, 32)], [Vector2(26, 32), Vector2(42, 32), Vector2(34, 18)]]:
		for index in 9:
			var progress := index / 8.0
			points.append(centre + Vector2(corner[0]).lerp(corner[1], progress).lerp(Vector2(corner[1]).lerp(corner[2], progress), progress))
	points.append(centre + Vector2(6, -35))
	return points

func _axis_point() -> Vector2:
	var values: Array = _layers().get(_layer, {}).get("current", [0.0, 0.0])
	return Vector2(0.5, 0.52) + Vector2(float(values[0]), float(values[1])) * 0.28

func _axis_origin() -> Vector2:
	var values: Array = _layers().get(_layer, {}).get("origin", [0.0, 0.0])
	return Vector2(0.5, 0.52) + Vector2(float(values[0]), float(values[1])) * 0.28

func _layers() -> Dictionary:
	return _state.get("context_layers", {})

func _resource(id: String) -> Dictionary:
	for record: Dictionary in _state.get("resources", []):
		if str(record.get("resource_id", record.get("id", ""))) == id: return record
	if _rules != null and _rules.has_method("context_resource"): return _rules.context_resource(id)
	return {}

func _refresh() -> void:
	if is_instance_valid(_output): _update_plane()
	if is_instance_valid(_surface):
		_sync_resource_graphics()
		_surface.queue_redraw()
	queue_redraw()

func _sync_resource_graphics() -> void:
	var slots: Array = _layers().get(_layer, {}).get("slots", [])
	var points := _slot_points()
	for key: int in _resource_graphics.keys():
		if key >= slots.size() or key >= points.size() or slots[key].is_empty():
			_resource_graphics[key].get_parent().remove_child(_resource_graphics[key])
			_resource_graphics[key].queue_free()
			_resource_graphics.erase(key)
	for index in mini(slots.size(), points.size()):
		var record := _resource(str(slots[index].get("resource_id", "")))
		if record.is_empty(): continue
		var graphic: Control = _resource_graphics.get(index)
		if not is_instance_valid(graphic):
			if _resource_factory.is_valid(): graphic = _resource_factory.call(record.duplicate(true))
			elif ResourceLoader.exists("res://scripts/demo/desk_context_resource_graphic.gd"):
				var code: Script = load("res://scripts/demo/desk_context_resource_graphic.gd")
				if code.can_instantiate(): graphic = code.new()
			if not is_instance_valid(graphic): continue
			graphic.name = "InstalledResource%d" % index
			graphic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_surface.add_child(graphic)
			_resource_graphics[index] = graphic
		var graphic_size := Vector2(72, 114) if _layer == "topics" else Vector2(96, 96)
		graphic.position = points[index] * PLANE_SIZE - graphic_size * 0.5
		graphic.size = graphic_size
		if graphic.has_method("configure") and graphic.get_meta("slice_definition", {}) != record:
			graphic.configure(record.duplicate(true))
			graphic.set_meta("slice_definition", record.duplicate(true))

func _has_point(point: Vector2) -> bool:
	if not _plane_only and _volume_rect.has_point(point): return true
	if is_instance_valid(_slider) and _slider.get_rect().has_point(point): return true
	return (_attached() or _plane_only) and Rect2(Vector2.ZERO, Vector2.ONE).has_point(unproject_point(point))

func _slot_at(point: Vector2) -> int:
	var points := _slot_points()
	for index in points.size():
		if _layer == "topics" and _resource_graphics.has(index):
			var graphic: Control = _resource_graphics[index]
			var paper := Rect2(graphic.position + Vector2(graphic.size.x * 0.22, 0), Vector2(graphic.size.x * 0.56, graphic.size.y))
			if paper.has_point(point * PLANE_SIZE): return index
			continue
		if point.distance_to(points[index]) <= 0.075: return index
	return -1

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _enabled or not data is Dictionary: return false
	if str(data.get("type","")) == "design_context_layer":
		var layer := str(data.get("layer",""))
		var actual: Dictionary = _layers().get(layer,{})
		return not _plane_only and layer in LAYERS and not bool(actual.get("attached",true)) and str(actual.get("plane_id","")) == str(data.get("plane_id","")) and not str(data.get("plane_id","")).is_empty() and _volume_rect.has_point(at_position)
	if not _attached() or str(data.get("type","")) != "context_resource": return false
	var slot := _slot_at(unproject_point(at_position))
	if slot < 0: return false
	var record := _resource(str(data.get("resource_id", "")))
	var kind := "topic" if _layer == "topics" else _layer
	var slots: Array = _layers().get(_layer, {}).get("slots", [])
	return str(record.get("kind", "")) == kind and int(record.get("available", 0)) > 0 and slot < slots.size() and slots[slot].is_empty()

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		_slot_rejections += 1
		return
	if str(data.get("type","")) == "design_context_layer":
		var layer := str(data.layer)
		perform("attach_context_layer",{"layer":layer,"plane_id":str(data.plane_id)})
		if bool(_layers().get(layer,{}).get("attached",false)): select_layer(layer)
		return
	_selected_slot = _slot_at(unproject_point(at_position))
	perform("install_context", {"layer": _layer, "slot": _selected_slot, "resource_id": str(data.resource_id)})
	selected_info_changed.emit(selected_info())

func accept_tabletop_item(kind: String, id: String, global_position: Vector2) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse() * global_position
	var packet := {"type": "context_resource", "kind": kind, "resource_id": id}
	if not _can_drop_data(point, packet): return false
	var layer := _layer
	var slot := _slot_at(unproject_point(point))
	_drop_data(point, packet)
	var slots: Array = _layers().get(layer, {}).get("slots", [])
	return slot < slots.size() and str(slots[slot].get("resource_id", "")) == id

func _gui_input(event: InputEvent) -> void:
	if not _enabled: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_last_pointer = get_global_transform_with_canvas()*event.position
		var uv := unproject_point(event.position)
		if event.pressed:
			_held_plane = _edge_at(uv)
			_press_uv = uv
			_axis = -1
			_axis_drag = _layer in ["stance", "pragmatic"] and uv.distance_to(_axis_point()) <= 0.08
			_held_slot = _slot_at(uv)
			_held_moved = false
			_held_record = {}
			if _held_slot >= 0:
				_selected_slot = _held_slot
				var slots: Array = _layers().get(_layer, {}).get("slots", [])
				if _held_slot < slots.size(): _held_record = slots[_held_slot].duplicate(true)
			selected_info_changed.emit(selected_info())
			_refresh()
		else:
			if _held_plane and _held_moved and not Rect2(Vector2.ZERO,Vector2.ONE).has_point(uv): _detach_plane(_last_pointer)
			if _held_moved and not _held_record.is_empty() and not Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv):
				var record := _resource(str(_held_record.get("resource_id", ""))).duplicate(true)
				perform("remove_context", {"layer": _layer, "slot": _held_slot})
				var slots: Array = _layers().get(_layer, {}).get("slots", [])
				if _held_slot < slots.size() and slots[_held_slot].is_empty(): resource_detached.emit(record, get_global_transform_with_canvas() * event.position)
			_cancel_input()
		accept_event()
	elif event is InputEventMouseMotion:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_cancel_input()
			return
		_last_pointer = get_global_transform_with_canvas()*event.position
		var uv := unproject_point(event.position)
		if _held_plane and uv.distance_to(_press_uv)>0.025: _held_moved=true
		if not _held_record.is_empty() and uv.distance_to(_press_uv) > 0.025: _held_moved = true
		if not _axis_drag: return
		if _axis < 0 and uv.distance_to(_press_uv) > 0.012:
			_axis = 0 if absf(uv.x - _press_uv.x) >= absf(uv.y - _press_uv.y) else 1
		if _axis >= 0: _move_axis(uv)
		accept_event()

func _move_axis(uv: Vector2) -> void:
	var data: Dictionary = _layers().get(_layer, {})
	var origin: Array = data.get("origin", [0.0, 0.0])
	var value := clampf((uv[_axis] - (0.5 if _axis == 0 else 0.52)) / 0.28, -1.0, 1.0)
	var step := float(data.get("step", 0.1))
	if step <= 0: return
	var target := roundi((value - float(origin[_axis])) / step)
	for attempt in 20:
		data = _layers().get(_layer, {})
		var offsets: Array = data.get("offsets", [0, 0])
		var previous := int(offsets[_axis])
		if previous == target: break
		_request_index += 1
		var direction := 1 if target > previous else -1
		perform("move_context_axis", {"layer": _layer, "axis": "x" if _axis == 0 else "y", "direction": direction, "request_id": "slice:%s:%s" % [_request_session, _request_index]})
		var actual: Array = _layers().get(_layer, {}).get("offsets", [0, 0])
		if int(actual[_axis]) != previous + direction: break
	_refresh()
	selected_info_changed.emit(selected_info())

func _depth_input(value: float) -> void:
	if not _enabled: return
	_depth = value
	_layer = LAYERS[clampi(floori(value * 5), 0, 4)]
	_selected_slot = -1
	perform("set_context_depth", {"layer": _layer, "depth": value})
	depth_changed.emit(_layer, value)
	selected_info_changed.emit(selected_info())
	_refresh()

func _cancel_input() -> void:
	_axis_drag = false
	_axis = -1
	_held_record = {}
	_held_slot = -1
	_held_moved = false

func _attached() -> bool:
	return bool(_layers().get(_layer,{}).get("attached",true))

func _edge_at(uv: Vector2) -> bool:
	return not _plane_only and _attached() and Rect2(Vector2.ZERO,Vector2.ONE).has_point(uv) and minf(minf(uv.x,uv.y),minf(1.0-uv.x,1.0-uv.y)) <= 0.08

func plane_record() -> Dictionary:
	var data: Dictionary = _layers().get(_layer,{})
	return {"type":"design_context_layer","layer":_layer,"plane_id":str(data.get("plane_id","")),"depth":_depth,"snapshot":_state.duplicate(true)}

func _detach_plane(point: Vector2) -> void:
	var record := plane_record()
	if str(record.plane_id).is_empty() or not _attached(): return
	perform("detach_context_layer",{"layer":_layer,"plane_id":str(record.plane_id)})
	if not _attached():
		record.snapshot = _state.duplicate(true)
		context_layer_detached.emit(record,point)

func _get_drag_data(at_position: Vector2) -> Variant:
	if not _enabled or not _edge_at(unproject_point(at_position)): return null
	var record := plane_record()
	perform("detach_context_layer",{"layer":_layer,"plane_id":str(record.plane_id)})
	if _attached(): return null
	record.snapshot = _state.duplicate(true)
	_native_plane = record
	var preview := TextureRect.new()
	preview.texture = _viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(180,180)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"type":"design_context_layer","layer":_layer,"plane_id":str(record.plane_id)}

func _input(event: InputEvent) -> void:
	if not _native_plane.is_empty() and event is InputEventMouseMotion: _last_pointer = event.position

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _native_plane.is_empty():
		var record := _native_plane
		_native_plane = {}
		if not bool(_layers().get(str(record.layer),{}).get("attached",true)): context_layer_detached.emit(record,_last_pointer)

func accept_tabletop_layer(record: Dictionary, global_point: Vector2) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse()*global_point
	if not _can_drop_data(point,record): return false
	_drop_data(point,record)
	return bool(_layers().get(str(record.layer),{}).get("attached",false))

func set_plane_only(value: bool) -> void:
	_plane_only = value
	if value: custom_minimum_size = Vector2.ZERO
	if not is_node_ready(): return
	_backplate.visible = not value
	_slider.visible = not value
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	_refresh()

func create_slice_item(record: Dictionary) -> Control:
	var code: Script = load("res://scripts/demo/desk_context_slice_item.gd")
	var item: Control = code.new()
	item.theme = theme
	item.configure(record,_rules,_resource_factory)
	return item
