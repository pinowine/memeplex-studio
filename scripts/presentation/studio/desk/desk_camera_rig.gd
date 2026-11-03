class_name DeskCameraRig
extends Camera2D

signal focus_arrived(id: String)
signal overview_arrived
signal view_restored

const FOCUS_DURATION := 0.55
const RETURN_DURATION := 0.45

var _world_size := Vector2(1600, 900)
var _target_id := ""
var _target_center := Vector2.ZERO
var _state := "overview"
var _generation := 0
var _motion: Tween
var _arrival_count := 0
var _home_zoom := 1.0

func configure(world_size: Vector2) -> void:
	_world_size = world_size
	process_priority = 50
	position_smoothing_enabled = false
	ignore_rotation = false
	enabled = true
	make_current()
	get_viewport().size_changed.connect(_on_viewport_changed)
	get_window().focus_exited.connect(_on_focus_exited)
	return_overview(false)

func _process(delta: float) -> void:
	# Advance before the 3D presenter reads the pose and canvas transform.
	# Automatic SceneTree tweens run after _process and would split those frames.
	if _motion != null and _motion.is_valid():
		_motion.custom_step(delta)
		force_update_scroll()

func _projection_zoom(value: Vector2) -> Vector2:
	if get_parent().has_meta("studio3d"):
		return value.max(Vector2.ONE * get_parent().get_meta("studio3d").minimum_camera_zoom)
	return value

func _move_to(center: Vector2, angle: float, target_zoom: Vector2, duration: float) -> void:
	_motion = create_tween().set_parallel(true)
	_motion.pause()
	_motion.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "position", center, duration)
	_motion.tween_property(self, "rotation", rotation + angle_difference(rotation, angle), duration)
	# Bound the endpoints, then interpolate visible height without a mid-flight clamp.
	var start := 1.0 / _projection_zoom(zoom).y
	var finish := 1.0 / _projection_zoom(target_zoom).y
	_motion.tween_method(func(height: float): zoom = Vector2.ONE / height, start, finish, duration)

func focus_on(id: String, world_rect: Rect2, magnification := 1.15, angle := 0.0) -> bool:
	if id.is_empty() or not world_rect.has_area() or not world_rect.position.is_finite(): return false
	_cancel_motion()
	_target_id = id
	_target_center = world_rect.get_center()
	_state = "travelling"
	var serial := _generation
	_move_to(_target_center, angle, Vector2.ONE * _fit_zoom() * magnification, FOCUS_DURATION)
	_motion.chain().tween_callback(func() -> void:
		if serial != _generation: return
		_state = "focused"
		_arrival_count += 1
		force_update_scroll()
		focus_arrived.emit(_target_id))
	return true

func focus_equipment(id: String, center: Vector2, dimensions: Vector2, angle: float, enlargement := 1.0) -> bool:
	if not center.is_finite() or not dimensions.is_finite() or dimensions.x <= 0 or dimensions.y <= 0: return false
	var view := get_viewport_rect().size
	var scale := minf(view.x * .48 / dimensions.x, view.y * .62 / dimensions.y)
	scale = clampf(scale * enlargement, _fit_zoom() * 1.35, _fit_zoom() * 3.6)
	# Inverse-rotate the camera, leaving the actual equipment in its fixed desk pose.
	var offset := Vector2(view.x * .18, 0) / scale
	# Put the printer halfway above the top edge, leaving the view for its receipt.
	if id == "printer": offset.y = view.y * .5 / scale
	var camera_center := center + offset.rotated(angle)
	return focus_on(id, Rect2(camera_center - Vector2.ONE, Vector2(2,2)), scale / _fit_zoom(), angle)

func capture_view() -> Dictionary:
	return {"position":position, "zoom":zoom, "target":_target_id, "state":_state, "rotation":rotation}

func focus_slot(id: String, world_rect: Rect2, magnification := 2.0) -> bool:
	if not world_rect.has_area() or not world_rect.position.is_finite(): return false
	var scale := _fit_zoom() * clampf(magnification, 1.0, 2.2)
	var view := get_viewport_rect().size
	# Leave the right side for the explanation paper, not for a second object move.
	var offset := Vector2(view.x * 0.18, -view.y * 0.02) / scale
	var target := Rect2(world_rect.position + offset.rotated(rotation), world_rect.size)
	return focus_on(id, target, clampf(magnification, 1.0, 2.2), rotation)

func restore_view(view: Dictionary) -> bool:
	if not view.get("position") is Vector2 or not view.get("zoom") is Vector2: return false
	_cancel_motion()
	_target_id = str(view.get("target", ""))
	_state = "travelling"
	var serial := _generation
	_move_to(view.position, float(view.get("rotation",0.0)), view.zoom, RETURN_DURATION)
	_motion.chain().tween_callback(func() -> void:
		if serial != _generation: return
		position = view.position
		rotation = float(view.get("rotation",0.0))
		zoom = _projection_zoom(view.zoom)
		_state = str(view.get("state", "focused"))
		force_update_scroll()
		view_restored.emit())
	return true

func return_overview(animate := true) -> void:
	_cancel_motion()
	_target_id = ""
	_home_zoom = _fit_zoom()
	var home := _world_size * 0.5
	if not animate:
		position = home
		rotation = 0.0
		zoom = _projection_zoom(Vector2.ONE * _home_zoom)
		_state = "overview"
		force_update_scroll()
		overview_arrived.emit()
		return
	_state = "returning"
	var serial := _generation
	_move_to(home, 0.0, Vector2.ONE * _home_zoom, RETURN_DURATION)
	_motion.chain().tween_callback(func() -> void:
		if serial != _generation: return
		_state = "overview"
		force_update_scroll()
		overview_arrived.emit())

func _fit_zoom() -> float:
	var view := get_viewport_rect().size
	var framing := .72 if get_parent().has_meta("studio3d") else 1.0
	return maxf(0.1, minf(view.x / _world_size.x, view.y / _world_size.y) * framing)

func _cancel_motion() -> void:
	_generation += 1
	if _motion != null and _motion.is_valid(): _motion.kill()

func _on_viewport_changed() -> void:
	# A resize cancels a pending reveal rather than completing an obsolete focus.
	return_overview(false)

func _on_focus_exited() -> void:
	if _state == "travelling": return_overview(false)

func inspection() -> Dictionary:
	return {"implementation":"Camera2D", "state":_state, "target":_target_id,
		"position":position, "zoom":zoom, "rotation":rotation, "home_position":_world_size * 0.5,
		"world_size":_world_size, "arrival_count":_arrival_count, "generation":_generation,
		"canvas_transform":get_viewport().get_canvas_transform()}
