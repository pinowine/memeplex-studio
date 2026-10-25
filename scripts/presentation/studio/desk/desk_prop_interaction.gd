extends Node
class_name DeskPropInteraction

signal clicked(id: StringName)
signal moved(id: StringName, new_global_position: Vector2)
signal drag_rejected(id: StringName, reason: StringName)
signal hovered(id: StringName)
signal drag_started(id: StringName)

@export var drag_threshold: float = 6.0
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			cancel_drag(&"disabled")

const EPS := 0.001
var _props: Dictionary = {}
var _order: Array[StringName] = []
var _exclusions: Dictionary = {}
var _bounds := Rect2()
var _blockers: Array[Rect2] = []
var _pressed: StringName = &""
var _hovered: StringName = &""
var _press_point := Vector2.ZERO
var _press_position := Vector2.ZERO
var _dragging := false
var _last_rejection: StringName = &""
var _last_motion: StringName = &""
var _input_diagnostic := {"event_count":0, "press_count":0, "drag_start_count":0, "release_count":0,
	"cancel_count":0, "last_type":"", "last_button_mask":0, "last_point":Vector2.ZERO,
	"last_transition":"idle", "last_cancel_reason":""}
var pointer_guard: Callable
var viewport_exclusion: Callable

func _ready() -> void:
	var window := get_window()
	if window != null and not window.focus_exited.is_connected(_on_focus_exited):
		window.focus_exited.connect(_on_focus_exited)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)

func _on_focus_exited() -> void:
	cancel_drag(&"focus_exited")

func _on_viewport_resized() -> void:
	cancel_drag(&"viewport_resized")

func register_prop(id: StringName, node: Control, local_hit_rect: Rect2, blocking: bool = true, movable: bool = true) -> bool:
	if id == &"" or not is_instance_valid(node) or not _valid_rect(local_hit_rect):
		return false
	if _pressed == id:
		cancel_drag(&"prop_replaced")
	_props[id] = {"node": node, "hit_rect": local_hit_rect, "collision_rect": local_hit_rect, "blocking": blocking, "movable": movable}
	if not _order.has(id):
		_order.append(id)
	return true

func set_collision_rect(id: StringName, local_rect: Rect2) -> bool:
	if not _props.has(id) or not _valid_rect(local_rect):
		return false
	_props[id].collision_rect = local_rect
	return true

func unregister_prop(id: StringName) -> void:
	if _pressed == id:
		cancel_drag(&"prop_unregistered")
	_props.erase(id)
	_order.erase(id)
	_exclusions.erase(id)

func set_bounds(view_rect: Rect2) -> bool:
	if not _valid_rect(view_rect):
		return false
	_bounds = view_rect
	return true

func set_blockers(rectangles: Array) -> bool:
	var accepted: Array[Rect2] = []
	for rectangle in rectangles:
		if not rectangle is Rect2 or not _valid_rect(rectangle):
			return false
		accepted.append(rectangle)
	_blockers = accepted
	return true

func add_exclusion(id: StringName, node: Control) -> bool:
	if not _props.has(id) or not is_instance_valid(node):
		return false
	if not _exclusions.has(id):
		_exclusions[id] = []
	if not _exclusions[id].has(node):
		_exclusions[id].append(node)
	return true

func set_enabled(value: bool) -> void:
	enabled = value

func cancel_drag(reason: StringName = &"explicit") -> void:
	if _pressed != &"" or _dragging:
		_input_diagnostic.cancel_count += 1
		_input_diagnostic.last_cancel_reason = String(reason)
		_input_diagnostic.last_transition = "cancelled"
	_pressed = &""
	_dragging = false
	_last_rejection = &""
	_set_hover(&"")

func _input(event: InputEvent) -> void:
	if input_event(event):
		get_viewport().set_input_as_handled()

func input_event(event: InputEvent) -> bool:
	if pointer_guard.is_valid() and pointer_guard.call(event): return true
	# Keep one bounded in-memory record; never write input to player files.
	if event is InputEventMouse:
		_input_diagnostic.event_count += 1
		_input_diagnostic.last_type = event.get_class()
		_input_diagnostic.last_button_mask = event.button_mask
		_input_diagnostic.last_point = event.position
	if not enabled:
		return false
	# Godot input positions are already viewport-logical, including window stretch.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _pressed != &"":
				return false
			var id := _hit_prop(event.position)
			if id == &"":
				return false
			_pressed = id
			_press_point = event.position
			_press_position = (_props[id].node as Control).global_position
			_dragging = false
			_last_rejection = &""
			_input_diagnostic.press_count += 1
			_input_diagnostic.last_transition = "pressed"
			return true
		if _pressed != &"":
			var released_id := _pressed
			var had_drag := _dragging
			# Release may finish a drag, but cannot create one from a shifted window.
			if _dragging:
				_update_drag(event.position)
			var was_click: bool = not _dragging and _live_prop(released_id) and _hit_prop(event.position) == released_id and event.position.distance_to(_press_point) < maxf(drag_threshold, EPS)
			_input_diagnostic.release_count += 1
			_input_diagnostic.last_transition = "drag_released" if had_drag else ("clicked" if was_click else "release_without_drag")
			_pressed = &""
			_dragging = false
			_last_rejection = &""
			if was_click:
				clicked.emit(released_id)
			_set_hover(_hit_prop(event.position))
			return true
	if event is InputEventMouseMotion:
		if _pressed != &"":
			if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				cancel_drag(&"left_button_absent")
				return false
			_update_drag(event.position)
			return true
		_set_hover(_hit_prop(event.position))
	return false

func _update_drag(point: Vector2) -> void:
	if not _live_prop(_pressed):
		cancel_drag(&"prop_unavailable")
		return
	var delta := point - _press_point
	if not _dragging and delta.length() < maxf(drag_threshold, 0.0):
		return
	if not _dragging:
		_dragging = true
		_input_diagnostic.drag_start_count += 1
		_input_diagnostic.last_transition = "dragging"
		drag_started.emit(_pressed)
	var prop: Dictionary = _props[_pressed]
	if not prop.movable:
		_reject(&"fixed")
		return
	var node := prop.node as Control
	var canvas := node.get_canvas_transform()
	if absf(canvas.determinant()) < EPS:
		_reject(&"singular_transform")
		return
	var target := _press_position + canvas.affine_inverse().basis_xform(delta)
	var current_rect := _collision_view_rect(_pressed)
	var target_rect := _collision_view_rect(_pressed, target)
	var reason := _move_error(_pressed, current_rect, target_rect, target)
	if reason != &"":
		var slide := node.global_position
		var progress := EPS
		var axis_mode: StringName = &""
		if reason == &"collision":
			# Each slide has its own complete swept test; never jump through an obstacle.
			for axis in range(2):
				var candidate := node.global_position
				candidate[axis] = target[axis]
				var distance := candidate.distance_to(node.global_position)
				if distance > progress and _move_error(_pressed, current_rect, _collision_view_rect(_pressed, candidate), candidate) == &"":
					slide = candidate
					progress = distance
					axis_mode = &"slide_x" if axis == 0 else &"slide_y"
		if axis_mode == &"":
			_last_motion = &"rejected"
			_reject(reason)
			return
		target = slide
		_last_motion = axis_mode
	else:
		_last_motion = &"direct"
	_last_rejection = &""
	if not node.global_position.is_equal_approx(target):
		node.global_position = target
		moved.emit(_pressed, node.global_position)

func _hit_prop(point: Vector2) -> StringName:
	if viewport_exclusion.is_valid() and viewport_exclusion.call(point): return &""
	# Later registrations win overlaps; root registers in visual stacking order.
	for index in range(_order.size() - 1, -1, -1):
		var id := _order[index]
		if not _live_prop(id):
			continue
		var node := _props[id].node as Control
		var transform := node.get_global_transform_with_canvas()
		if absf(transform.determinant()) < EPS:
			continue
		if (_props[id].hit_rect as Rect2).has_point(transform.affine_inverse() * point):
			if _excluded(id, point):
				return &""
			return id
	return &""

func _excluded(id: StringName, point: Vector2) -> bool:
	for node in _exclusions.get(id, []):
		if is_instance_valid(node) and node is Control and _control_contains(node, point):
			return true
	return _button_at(_props[id].node, point)

func _button_at(node: Node, point: Vector2) -> bool:
	if node is BaseButton and not node.disabled and _control_contains(node, point):
		return true
	for child in node.get_children():
		if _button_at(child, point):
			return true
	return false

func _control_contains(node: Control, point: Vector2) -> bool:
	if not node.is_visible_in_tree() or node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var transform := node.get_global_transform_with_canvas()
	return absf(transform.determinant()) >= EPS and Rect2(Vector2.ZERO, node.size).has_point(transform.affine_inverse() * point)

func _view_rect(id: StringName, target: Variant = null) -> Rect2:
	return _transformed_rect(id, _props[id].hit_rect, target)

func _collision_view_rect(id: StringName, target: Variant = null) -> Rect2:
	return _transformed_rect(id, _props[id].collision_rect, target)

func _transformed_rect(id: StringName, rectangle: Rect2, target: Variant) -> Rect2:
	var node := _props[id].node as Control
	var transform := node.get_global_transform_with_canvas()
	if target is Vector2:
		transform.origin += node.get_canvas_transform().basis_xform(target - node.global_position)
	return transform * rectangle

func _move_error(id: StringName, current: Rect2, candidate: Rect2, target: Vector2) -> StringName:
	if _valid_rect(_bounds) and not _bounds.encloses(_view_rect(id, target)):
		return &"bounds"
	if _props[id].blocking:
		for other in _order:
			if other != id and _live_prop(other) and _props[other].blocking:
				if _swept_intersects(current, candidate, _collision_view_rect(other)):
					return &"collision"
	for obstacle in _blockers:
		if _swept_intersects(current, candidate, obstacle):
			return &"collision"
	return &""

func _swept_intersects(current: Rect2, candidate: Rect2, obstacle: Rect2) -> bool:
	if candidate.intersects(obstacle, false) or current.intersects(obstacle, false):
		return true
	var motion := candidate.position - current.position
	var low := obstacle.position - current.size + Vector2(EPS, EPS)
	var high := obstacle.end - Vector2(EPS, EPS)
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if absf(motion[axis]) < EPS:
			if current.position[axis] <= low[axis] or current.position[axis] >= high[axis]:
				return false
		else:
			var first: float = (low[axis] - current.position[axis]) / motion[axis]
			var last: float = (high[axis] - current.position[axis]) / motion[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter > leave:
				return false
	return enter <= leave and leave >= 0.0 and enter <= 1.0

func placements() -> Dictionary:
	var result := {}
	for id in _order:
		if _live_prop(id) and _props[id].movable:
			var point := (_props[id].node as Control).global_position
			result[String(id)] = {"x": point.x, "y": point.y}
	return result

func apply_placements(layout: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var targets := {}
	for key in layout:
		var id := StringName(str(key))
		if not _live_prop(id) or not _props[id].movable:
			errors.append("Unknown or fixed prop: %s" % id)
			continue
		var value: Variant = layout[key]
		if not value is Dictionary or not _number(value.get("x")) or not _number(value.get("y")):
			errors.append("Invalid position: %s" % id)
			continue
		targets[id] = Vector2(float(value.x), float(value.y))
	if not errors.is_empty():
		return errors
	var rectangles := {}
	var hit_rectangles := {}
	for id in _order:
		if _live_prop(id):
			rectangles[id] = _collision_view_rect(id, targets.get(id))
			hit_rectangles[id] = _view_rect(id, targets.get(id))
	for id in targets:
		var rectangle: Rect2 = rectangles[id]
		if _valid_rect(_bounds) and not _bounds.encloses(hit_rectangles[id]):
			errors.append("Out of bounds: %s" % id)
		if _props[id].blocking:
			for other in rectangles:
				if other != id and _props[other].blocking and rectangle.intersects(rectangles[other], false):
					errors.append("Collision: %s / %s" % [id, other])
		for obstacle in _blockers:
			if rectangle.intersects(obstacle, false):
				errors.append("Collision: %s / static" % id)
	if not errors.is_empty():
		return errors
	# Saved placement is validated as one transaction, not replayed as a drag path.
	for id in targets:
		var node := _props[id].node as Control
		if not node.global_position.is_equal_approx(targets[id]):
			node.global_position = targets[id]
			moved.emit(id, node.global_position)
	return errors

func inspection() -> Dictionary:
	var props := []
	for id in _order:
		if _live_prop(id):
			var node := _props[id].node as Control
			props.append({"id": String(id), "position": node.global_position, "view_rect": _view_rect(id), "local_hit_rect": _props[id].hit_rect, "collision_rect": _props[id].collision_rect, "collision_view_rect": _collision_view_rect(id), "blocking": _props[id].blocking, "movable": _props[id].movable})
	return {"enabled": enabled, "pressed": String(_pressed), "dragging": _dragging, "hovered": String(_hovered), "last_motion": String(_last_motion), "input_diagnostic":_input_diagnostic.duplicate(true), "bounds": _bounds, "props": props, "extra_blockers": _blockers.duplicate(), "coordinate_space": "viewport logical; independent interaction and collision rectangles; swept AABBs with legal axis slides", "persistence": "caller-owned atomic layout; no player save writes"}

func _live_prop(id: StringName) -> bool:
	return _props.has(id) and is_instance_valid(_props[id].node) and (_props[id].node as Control).is_visible_in_tree()

func _set_hover(id: StringName) -> void:
	if _hovered != id:
		_hovered = id
		hovered.emit(id)

func _reject(reason: StringName) -> void:
	if _last_rejection != reason:
		_last_rejection = reason
		drag_rejected.emit(_pressed, reason)

func _valid_rect(rectangle: Rect2) -> bool:
	return rectangle.position.is_finite() and rectangle.size.is_finite() and rectangle.size.x > 0.0 and rectangle.size.y > 0.0

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
