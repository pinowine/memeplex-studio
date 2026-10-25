extends RefCounted

const OUTSIDE := Vector2(-100000, -100000)
var pointer_position := Vector2.ZERO
var pointer_known := false
var forwarded_events := 0
var cancel_count := 0
var _logical_mouse_inside := false
var _captured_key := ""
var _camera: Camera3D
var _logical: SubViewport
var _viewport: Viewport
var _buttons: Dictionary
var _screens: Array[Node]
var _surface_bindings: Array[Dictionary]
var _feedback: RefCounted
var _desktop: RefCounted

func configure(camera: Camera3D, logical: SubViewport, viewport: Viewport, buttons: Dictionary, screens: Array[Node], bindings: Array[Dictionary], feedback: RefCounted, desktop: RefCounted) -> void:
	_camera = camera
	_logical = logical
	_viewport = viewport
	_buttons = buttons
	_screens = screens
	_surface_bindings = bindings
	_feedback = feedback
	_desktop = desktop

func modal_to_logical(point: Vector2) -> Vector2:
	return point * Vector2(_logical.size) / _viewport.get_visible_rect().size

func root_pointer_from_logical(point: Vector2) -> Vector2:
	if pointer_known: return pointer_position
	var world := _logical.get_canvas_transform().affine_inverse() * point
	return _camera.unproject_position(Vector3((world.x - 800) / 1000, .006, (world.y - 450) / 1000))

func hit(point: Vector2) -> Dictionary:
	var origin := _camera.project_ray_origin(point)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(point) * 10, 1)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	return _camera.get_world_3d().direct_space_state.intersect_ray(ray)

func desktop_point(point: Vector2) -> Vector2:
	var crossing: Variant = Plane(Vector3.UP, .006).intersects_ray(_camera.project_ray_origin(point), _camera.project_ray_normal(point))
	if crossing == null: return OUTSIDE
	return Vector2(crossing.x, crossing.z) * 1000 + Vector2(800, 450)

func screen_input(point: Vector2) -> Vector2:
	for renderer in _screens:
		var mapped: Vector2 = renderer.input_from_ray(_camera.project_ray_origin(point), _camera.project_ray_normal(point))
		if mapped.is_finite(): return mapped
	for binding in _surface_bindings:
		var glass := binding.mesh as MeshInstance3D
		if str(glass.name) not in ["crt_terminal__ScreenSurface", "contact_book__PageContent", "fax_machine__StatusScreen"]: continue
		if not glass.is_visible_in_tree() or not binding.source.is_visible_in_tree(): continue
		var bounds := glass.get_aabb()
		var origin := glass.to_local(_camera.project_ray_origin(point))
		var direction := glass.global_basis.inverse() * _camera.project_ray_normal(point)
		var crossing: Variant = Plane(Vector3.UP, bounds.get_center().y).intersects_ray(origin, direction)
		if crossing == null or bounds.size.x <= 0 or bounds.size.z <= 0: continue
		var uv := Vector2((crossing.x - bounds.position.x) / bounds.size.x, (crossing.z - bounds.position.z) / bounds.size.z)
		if Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv):
			var area: Rect2 = binding.rect
			return binding.source.get_global_transform_with_canvas() * (area.position + uv * area.size)
	return _logical.get_canvas_transform() * desktop_point(point)

func route_event(event: InputEvent, modal_visible: bool, input_blocked: bool) -> void:
	if input_blocked and not modal_visible: return
	if event is InputEventMouse:
		_route_mouse(event, modal_visible)
	elif event is InputEventKey:
		_logical.push_input(event.duplicate(), true)
		_viewport.set_input_as_handled()

func _route_mouse(event: InputEventMouse, modal_visible: bool) -> void:
	pointer_position = event.position
	pointer_known = true
	if not _logical_mouse_inside:
		_logical.notify_mouse_entered()
		_logical_mouse_inside = true
	var forwarded := event.duplicate() as InputEventMouse
	var physical_hit := {} if modal_visible else hit(event.position)
	var key := str(physical_hit.collider.get_meta("button_key", "")) if not physical_hit.is_empty() else ""
	var point := modal_to_logical(event.position) if modal_visible else screen_input(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not key.is_empty() and not modal_visible:
			_captured_key = key
		elif not event.pressed and not _captured_key.is_empty():
			if key != _captured_key: point = OUTSIDE
			key = _captured_key
			_captured_key = ""
		if not key.is_empty() and point != OUTSIDE:
			_feedback.set_pressed(key, event.pressed)
			var target: Button = _buttons[key].target
			if target != null:
				point = target.get_global_transform_with_canvas() * (target.size * .5)
			else:
				if not event.pressed: _desktop.activate_device(key)
				_viewport.set_input_as_handled()
				return
	forwarded.position = point
	forwarded.global_position = point
	if forwarded is InputEventMouseMotion:
		forwarded.relative = modal_to_logical(event.relative) if modal_visible else point - screen_input(event.position - event.relative)
	_logical.push_input(forwarded, true)
	forwarded_events += 1
	_viewport.set_input_as_handled()

func cancel() -> void:
	_desktop.cancel_interactions()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = OUTSIDE
	release.global_position = OUTSIDE
	_logical.push_input(release, true)
	if _logical_mouse_inside:
		_logical.notify_mouse_exited()
		_logical_mouse_inside = false
	for key in _buttons: _feedback.set_pressed(key, false)
	_feedback.clear()
	_captured_key = ""
	pointer_known = false
	_logical.gui_release_focus()
	cancel_count += 1

func inspection() -> Dictionary:
	return {"forwarded_events":forwarded_events, "cancel_count":cancel_count, "captured_key":_captured_key}
