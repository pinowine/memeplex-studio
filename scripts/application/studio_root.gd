extends Node3D

const ContentPresenter := preload("res://scripts/presentation/studio/content/content_presenter.gd")
const InputRouter := preload("res://scripts/presentation/studio/input/input_router.gd")
const GameCursors := preload("res://scripts/presentation/studio/input/game_cursors.gd")
const FbxAssembly := preload("res://scripts/rendering/models/fbx_assembly.gd")
const ButtonFeedback := preload("res://scripts/rendering/feedback/button_feedback.gd")
const PaperMasks := preload("res://scripts/rendering/paper/paper_masks.gd")
const PaperFeed := preload("res://scripts/rendering/paper/paper_feed.gd")
const HoverOutline := preload("res://scripts/rendering/feedback/hover_outline.gd")

@export var whitebox := false
@export_range(0.1, 3.0, 0.001) var overview_height_m := 0.914

const LOGICAL_SIZE := Vector2i(1600, 900)

var content := ContentPresenter.new()
var desktop: RefCounted
var input_router: RefCounted
var _node_cache: Dictionary = {}
var fbx_loader := FbxAssembly.new()
var button_feedback := ButtonFeedback.new()
var paper_masks := PaperMasks.new()
var hover_outline := HoverOutline.new()
var _hover_meshes: Dictionary = {}
var logical: SubViewport
var page: Node2D
var assembly: Node3D
var camera: Camera3D
var buttons: Dictionary = {}
var areas: Array[Area3D] = []
var hovered := ""
var cursor_shape := Input.CURSOR_ARROW
var ready_3d := false
var half_tone: ColorRect
var modal_image: TextureRect
var studio_wide := false
var startup_error := ""
var handset_cord: MeshInstance3D
var handset_connected := false
var cord_endpoints: Dictionary = {}

func _ready() -> void:
	GameCursors.install()
	DeskLocalization.ensure_loaded()
	process_priority = 100
	_setup_lighting()
	assembly = fbx_loader.build()
	if assembly == null:
		startup_error = "Cannot construct studio from fullscene FBX"
		push_error(startup_error)
		return
	assembly.name = "StudioAssets"
	add_child(assembly)
	if whitebox: _apply_whitebox(assembly)
	camera = Camera3D.new()
	camera.name = "OrthographicDeskCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.02
	camera.far = 15.0
	add_child(camera)
	camera.current = true
	logical = SubViewport.new()
	logical.name = "Authoritative2DContent"
	# Keep desk/input units fixed while preserving small overview glyphs in the backing texture.
	logical.size = LOGICAL_SIZE * 2
	logical.size_2d_override = LOGICAL_SIZE
	logical.size_2d_override_stretch = true
	logical.disable_3d = true
	logical.msaa_2d = Viewport.MSAA_4X
	# Oversampled bitmap glyphs need mip filtering when the desk is reduced.
	logical.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logical.transparent_bg = true
	logical.handle_input_locally = true
	logical.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(logical)
	var page_scene := load("res://scenes/studio/desk/game_page.tscn") as PackedScene
	if page_scene == null:
		startup_error = "Cannot load logical game scene"
		push_error(startup_error)
		return
	page = page_scene.instantiate()
	var projection := ProjectionPort.new()
	projection.minimum_camera_zoom = 0.9 / overview_height_m
	projection.exit_measurement = paper_exit
	projection.pointer_projection = root_pointer_from_logical
	projection.pointer_unprojection = logical_pointer_from_root
	projection.target_projection = project_target
	page.set_meta("studio3d", projection)
	logical.add_child(page)
	if not page.initialization_complete:
		await page.initialization_finished
	if page.initialization_error != OK:
		startup_error = page.initialization_message
		push_error(startup_error)
		return
	desktop = page.create_studio_adapter()
	desktop.prepare()
	_layout_equipment()
	if not paper_masks.configure(desktop.paper_masks()):
		startup_error += "Cannot configure Painter paper masks; "
	_node("contact_book").hide()
	page.mount_presentation_overlays(self)
	content.name = "StudioContentPresenter"
	add_child(content)
	if not content.configure(fbx_loader, assembly, logical, desktop, whitebox):
		startup_error += content.startup_error
	_bind_controls()
	button_feedback.configure(buttons)
	content.bind_monitor_icons(buttons)
	input_router = InputRouter.new()
	input_router.configure(camera, logical, get_viewport(), buttons, content.screen_surfaces, content.bindings, button_feedback, desktop)
	page._shell.tutorial.pointer_cancelled.connect(_cancel_input)
	_node("fax_machine__HandsetCord").hide()
	_node("fax_machine__ReceiverCordJack").reparent(_node("fax_machine__HandsetPivot"),true)
	handset_cord = MeshInstance3D.new()
	handset_cord.name = "ConnectedCoiledReceiverCable"
	add_child(handset_cord)
	_update_handset(true)
	_setup_postprocess()
	add_child(hover_outline)
	hover_outline.configure(camera)
	get_window().focus_exited.connect(_cancel_input)
	get_viewport().size_changed.connect(_resized)
	if not startup_error.is_empty():
		push_error(startup_error)
		return
	ready_3d = true
	print("STUDIO_3D_READY bindings=%d controls=%d projection=orthographic renderer=%s" % [content.bindings.size(),buttons.size(),RenderingServer.get_current_rendering_method()])

func _layout_equipment() -> void:
	for item: Dictionary in desktop.equipment_layout():
		var source: Control = item.source
		var transform := source.get_global_transform()
		var center := transform * (source.size * .5)
		var factor: Vector2 = source.size * transform.get_scale() / item.template_size
		var model := _node(item.id)
		model.position = Vector3((center.x - 800) / 1000.0, 0, (center.y - 450) / 1000.0)
		model.rotation.y = -transform.get_rotation()
		model.scale = Vector3(factor.x, minf(factor.x,factor.y), factor.y)

func _apply_whitebox(root: Node) -> void:
	var white := StandardMaterial3D.new()
	white.resource_name = "RuntimeWhitebox"
	white.albedo_color = Color(.82,.82,.80)
	white.roughness = .84
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		mesh.material_override = white

func modal_to_logical(point: Vector2) -> Vector2:
	return input_router.modal_to_logical(point)

func root_pointer_from_logical(point: Vector2) -> Vector2:
	if input_router != null: return input_router.root_pointer_from_logical(point)
	var world := logical.get_canvas_transform().affine_inverse() * point
	return camera.unproject_position(Vector3((world.x - 800) / 1000, .006, (world.y - 450) / 1000))

func logical_pointer_from_root(point: Vector2) -> Vector2:
	return logical.get_canvas_transform() * input_router.desktop_point(point)

func paper_exit(asset_id: String) -> Dictionary:
	return PaperFeed.measure_exit(assembly,asset_id)

func _setup_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "PhysicalStudioEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2d3435")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c8d3")
	env.ambient_light_energy = .30
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = .10
	env.ssao_intensity = 1.2
	env.ssil_enabled = true
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "WorkshopWindowDaylight"
	sun.rotation_degrees = Vector3(-65,-35,0)
	sun.light_color = Color("ffefd7")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 8.0
	add_child(sun)
	for point in [Vector3(-.6,1.2,-.5), Vector3(.8,1.5,-.9)]:
		var fill := OmniLight3D.new()
		fill.position = point
		fill.omni_range = 3.0
		fill.light_energy = .20
		fill.light_color = Color("bfd8eb")
		add_child(fill)
	var lamp := SpotLight3D.new()
	lamp.name = "ConnectedTaskLampLight"
	lamp.position = Vector3(-.94,.29,-.58)
	lamp.rotation_degrees = Vector3(-90,0,0)
	lamp.spot_range = 1.3
	lamp.spot_angle = 60.0
	lamp.light_energy = .65
	lamp.light_color = Color("ffe4ae")
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.look_at(Vector3(-.60,0,-.25))


func _node(id: String) -> Node3D:
	if not _node_cache.has(id): _node_cache[id] = assembly.find_child(id, true, false)
	return _node_cache[id] as Node3D


func _bind_controls() -> void:
	for node in assembly.find_children("*","Node3D",true,false):
		var extra: Dictionary = node.get_meta("extras",{})
		var role: String = str(extra.get("interaction_role",""))
		var asset_id := str(node.name).get_slice("__",0)
		if role not in ["button","handset"]: continue
		var action := str(extra.get("binding_id",""))
		if asset_id == "fax_machine" and action != "pickup": continue
		var key := asset_id+"/"+action
		var target: Button = desktop.button_target(asset_id, action)
		var area := Area3D.new()
		area.name = "PhysicalHitRegion"
		area.collision_layer = 1
		area.collision_mask = 0
		node.add_child(area)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var aabb := AABB(Vector3(-.027,-.020,-.115),Vector3(.054,.040,.230))
		if node is MeshInstance3D: aabb = node.get_aabb()
		shape.size = aabb.size.max(Vector3(.006,.005,.006))
		collision.shape = shape
		collision.position = aabb.get_center()
		area.add_child(collision)
		area.set_meta("button_key",key)
		areas.append(area)
		buttons[key] = {"mesh":node,"area":area,"target":target,"rest":node.position,"travel":float(extra.get("press_travel_m",0.0015)),"action":action}
		if target != null:
			target.set_meta("physical_hardware", true)
			target.button_down.connect(_press_visual.bind(key,true))
			target.button_up.connect(_press_visual.bind(key,false))

func _press_visual(key: String, down: bool) -> void:
	button_feedback.set_pressed(key,down)

func _setup_postprocess() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CMYKPrintFinish"
	layer.layer = 1
	add_child(layer)
	half_tone = ColorRect.new()
	half_tone.name = "ScreenSpaceHalftone"
	half_tone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	half_tone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/studio/studio_halftone.gdshader")
	half_tone.material = material
	half_tone.visible = false
	layer.add_child(half_tone)
	var modal_layer := CanvasLayer.new()
	modal_layer.layer = 80
	add_child(modal_layer)
	modal_image = TextureRect.new()
	modal_image.name = "ScreenSpaceModalContent"
	modal_image.texture = logical.get_texture()
	modal_image.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_image.gui_input.connect(_route_input)
	modal_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	modal_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(modal_image)
	modal_image.hide()

func _process(_delta: float) -> void:
	if not ready_3d: return
	desktop.sync_raster_presentation(get_viewport().get_visible_rect(), get_window().has_focus() and not page.presentation_blocks_input() and not modal_image.visible)
	var pose: Dictionary = desktop.camera_pose()
	camera.position = Vector3((pose.position.x - 800) / 1000, 3.0, (pose.position.y - 450) / 1000)
	camera.basis = Basis(Vector3.UP, -float(pose.rotation)) * Basis.from_euler(Vector3(-PI / 2, 0, 0))
	camera.size = 0.9 / pose.zoom.y
	if page._shell.main_mode:
		camera.size *= .82
		camera.position += Vector3(.15,0,.06)
	if studio_wide:
		camera.position = Vector3(0,3,0)
		camera.basis = Basis.from_euler(Vector3(-PI/2,0,0))
		camera.size = 2.25
	content.sync(_delta, desktop.clock_angles(), page.presentation_daylight())
	_update_handset()
	var showing_modal: bool = page.presentation_modal_visible()
	if showing_modal != modal_image.visible:
		_cancel_input()
		get_viewport().gui_release_focus()
	modal_image.visible = showing_modal
	cursor_shape = _update_hover()
	if get_window().has_focus() and not showing_modal and not page.presentation_blocks_input() and desktop.pointer_dragging():
		cursor_shape = Input.CURSOR_POINTING_HAND
	GameCursors.apply(cursor_shape)
	button_feedback.tick(_delta)
	hover_outline.sync()

func _update_handset(force := false) -> void:
	var connected: bool = desktop.handset_connected()
	if not force and connected == handset_connected: return
	handset_connected = connected
	var receiver := _node("fax_machine__HandsetPivot")
	receiver.position = buttons["fax_machine/pickup"].rest + Vector3(0,.045 if connected else 0.0,0)
	var body := _node("fax_machine")
	var start := _node("fax_machine__ReceiverCordJack").global_position
	var end := _node("fax_machine__ReceiverJack").global_position
	var path: Array[Vector3] = [start,body.to_global(Vector3(-.153,.024,.090))]
	for i in 361:
		var t := float(i)/360
		path.append(body.to_global(Vector3(-.151-.006*cos(t*TAU*24),.023+.006*sin(t*TAU*24),.095+t*.09)))
	path.append(body.to_global(Vector3(-.158,.020,.19)))
	path.append(body.to_global(Vector3(-.158,.020,-.075)))
	path.append(end)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in path.size():
		var tangent := (path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized()
		var normal := tangent.cross(Vector3.UP).normalized()
		if normal.length_squared()<.1: normal=Vector3.RIGHT
		var binormal := tangent.cross(normal).normalized()
		for side in 8:
			var radial := normal*cos(side*TAU/8)+binormal*sin(side*TAU/8)
			vertices.append(path[i]+radial*.0013)
			normals.append(radial)
			if i<path.size()-1:
				var a:=i*8+side;var b:=i*8+(side+1)%8
				indices.append_array(PackedInt32Array([a,b,a+8,b,b+8,a+8]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	handset_cord.mesh=mesh
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color=Color("171b1a");rubber.roughness=.88
	handset_cord.material_override=rubber
	cord_endpoints={"receiver":start,"jack":end,"receiver_gap_m":path[0].distance_to(start),"jack_gap_m":path[-1].distance_to(end)}


func _update_hover() -> int:
	hovered = ""
	button_feedback.update_hover("")
	if not get_window().has_focus():
		hover_outline.clear()
		return Input.CURSOR_ARROW
	var target: Dictionary = desktop.control_hover_target(get_viewport().gui_get_hovered_control())
	if not target.is_empty():
		_show_hover_target(target)
		return target.cursor_shape
	if desktop.foreground_ui_handles(get_viewport().get_mouse_position()):
		hover_outline.clear()
		return desktop.control_cursor_shape(get_viewport().gui_get_hovered_control())
	if modal_image.visible:
		target = desktop.control_hover_target(logical.gui_get_hovered_control())
		if not target.is_empty():
			var polygon: PackedVector2Array = target.polygon
			for index in polygon.size(): polygon[index] *= get_viewport().get_visible_rect().size / logical.get_visible_rect().size
			hover_outline.show_polygon(str(target.key), polygon)
		else: hover_outline.clear()
		return target.cursor_shape if not target.is_empty() else desktop.control_cursor_shape(logical.gui_get_hovered_control())
	if page.presentation_blocks_input():
		hover_outline.clear()
		return Input.CURSOR_ARROW
	var point := get_viewport().get_mouse_position()
	if not page._shell.tutorial.allows_hover(point):
		hover_outline.clear()
		return Input.CURSOR_ARROW
	var desktop_position: Vector2 = logical.get_canvas_transform() * input_router.desktop_point(point)
	var material_input: bool = desktop.material_handles_viewport_point(desktop_position)
	var physical_hit: Dictionary = {} if material_input else input_router.hit(point)
	if not physical_hit.is_empty():
		var key := str(physical_hit.collider.get_meta("button_key", ""))
		var button: Button = buttons[key].target
		var enabled: bool = desktop.device_enabled(key) if button == null else not button.disabled
		if enabled:
			hovered = key
			button_feedback.update_hover(key)
			hover_outline.show_meshes(key, _meshes_for_hover(key, buttons[key].mesh))
		else: hover_outline.clear()
		return Input.CURSOR_POINTING_HAND if enabled else Input.CURSOR_ARROW
	target = desktop.hover_target_at(desktop_position if material_input else input_router.screen_input(point))
	if not target.is_empty():
		_show_hover_target(target)
		return target.cursor_shape
	hovered = desktop.hovered_equipment(input_router.desktop_point(point))
	if hovered.is_empty(): hover_outline.clear()
	else: hover_outline.show_meshes(hovered, _meshes_for_hover(hovered, _node(hovered)))
	if not hovered.is_empty(): return Input.CURSOR_HELP
	return desktop.control_cursor_shape(logical.gui_get_hovered_control(), desktop_position if material_input else input_router.screen_input(point))

func _meshes_for_hover(key: String, root: Node3D) -> Array[MeshInstance3D]:
	if not _hover_meshes.has(key):
		var meshes: Array[MeshInstance3D] = []
		if root is MeshInstance3D: meshes.append(root)
		for child: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false): meshes.append(child)
		_hover_meshes[key] = meshes
	return _hover_meshes[key]

func _show_hover_target(target: Dictionary) -> void:
	hovered = str(target.key)
	var polygon: PackedVector2Array = target.polygon
	var source: Control = target.source
	if hovered.begins_with("inventory/"):
		for screen in content.screen_surfaces:
			if screen.contains_control(source):
				polygon = screen.project_inventory_cell(hovered.trim_prefix("inventory/"), camera)
				hover_outline.show_polygon(hovered, polygon)
				return
	if source.get_viewport() != get_viewport():
		var projected := PackedVector2Array()
		for point in polygon:
			var world: Vector2 = logical.get_canvas_transform().affine_inverse() * point
			projected.append(camera.unproject_position(Vector3((world.x - 800) / 1000, .006, (world.y - 450) / 1000)))
		polygon = projected
	hover_outline.show_polygon(hovered, polygon, target.get("texture"))

func _unhandled_input(event: InputEvent) -> void:
	if not ready_3d: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		studio_wide = not studio_wide
		_cancel_input()
		get_viewport().set_input_as_handled()
		return
	_route_input(event)

func _route_input(event: InputEvent) -> void:
	if ready_3d:
		input_router.route_event(event, modal_image.visible, page.presentation_blocks_input())

func _cancel_input() -> void:
	cursor_shape = Input.CURSOR_ARROW
	GameCursors.apply(cursor_shape)
	if ready_3d:
		input_router.cancel()
		hover_outline.clear()

func _resized() -> void:
	_cancel_input()
	if ready_3d: desktop.return_overview()

func project_target(target: Variant) -> Variant:
	if target is Dictionary and target.has("hardware_key"):
		if not ready_3d: return Rect2()
		var binding: Dictionary = buttons[str(target.hardware_key)]
		var bounds: AABB = binding.mesh.get_aabb() if binding.mesh is MeshInstance3D else AABB(Vector3(-.03,0,-.115),Vector3(.06,.04,.23))
		var result := Rect2()
		for corner in 8:
			var offset := Vector3(bounds.size.x if (corner & 1) != 0 else 0.0, bounds.size.y if (corner & 2) != 0 else 0.0, bounds.size.z if (corner & 4) != 0 else 0.0)
			var point := camera.unproject_position(binding.mesh.to_global(bounds.position + offset))
			result = Rect2(point, Vector2.ZERO) if corner == 0 else result.expand(point)
		return result.grow(6.0)
	if target is Dictionary and target.has("equipment_part"):
		var mesh := _node(str(target.equipment_part)) as MeshInstance3D
		var bounds := mesh.get_aabb()
		var result := Rect2()
		for corner in 8:
			var offset := Vector3(bounds.size.x if (corner & 1) != 0 else 0.0, bounds.size.y if (corner & 2) != 0 else 0.0, bounds.size.z if (corner & 4) != 0 else 0.0)
			var point := camera.unproject_position(mesh.to_global(bounds.position + offset))
			result = Rect2(point, Vector2.ZERO) if corner == 0 else result.expand(point)
		return result.grow(6.0)
	if target is Control:
		if target.get_viewport() == get_viewport(): return target
		for binding in buttons.values():
			if binding.target == target:
				var aabb: AABB = binding.mesh.get_aabb() if binding.mesh is MeshInstance3D else AABB(Vector3(-.03,0,-.115),Vector3(.06,.04,.23))
				var a := camera.unproject_position(binding.mesh.to_global(aabb.position))
				var b := camera.unproject_position(binding.mesh.to_global(aabb.end))
				return Rect2(a.min(b),a.max(b)-a.min(b)).grow(6)
		for surface: Node in content.screen_surfaces:
			var screen_rect: Rect2 = surface.project_control_rect(target, camera)
			if screen_rect.has_area(): return screen_rect
		var transform: Transform2D = target.get_global_transform()
		var corners := [Vector2.ZERO,Vector2(target.size.x,0),target.size,Vector2(0,target.size.y)]
		var result := Rect2()
		for i in corners.size():
			var logical_point: Vector2 = transform*corners[i]
			var point := camera.unproject_position(Vector3((logical_point.x-800)/1000,.006,(logical_point.y-450)/1000))
			if i==0: result=Rect2(point,Vector2.ZERO)
			else: result=result.expand(point)
		return result
	return target

func interaction_inspection() -> Dictionary:
	var report: Dictionary = content.inspection()
	report.phonebook_removed = not _node("contact_book").is_visible_in_tree()
	report.button_feedback = button_feedback.inspection()
	report.hover_outline = hover_outline.inspection()
	report.cursor_shape = cursor_shape
	report.paper_masks = paper_masks.inspection()
	return report

func inspection() -> Dictionary:
	return {"enabled":ready_3d,"source_fbx":FbxAssembly.FBX_PATH,"whitebox":whitebox,"fbx":fbx_loader.inspection(),"projection":"orthographic","overview_height_m":overview_height_m,"camera_size_m":camera.size if camera != null else 0.0,"controls":buttons.size(),"content":content.inspection(),"receiver_cord":cord_endpoints,"input":input_router.inspection() if input_router != null else {},"hovered":hovered,"source_size":logical.size,"shader":half_tone.material.shader.resource_path if half_tone!=null else "","startup_error":startup_error,"renderer":RenderingServer.get_current_rendering_method()}


class ProjectionPort extends RefCounted:
	var minimum_camera_zoom: float
	var exit_measurement: Callable
	var pointer_projection: Callable
	var pointer_unprojection: Callable
	var target_projection: Callable

	func paper_exit(asset_id: String) -> Dictionary:
		return exit_measurement.call(asset_id)

	func root_pointer_from_logical(point: Vector2) -> Vector2:
		return pointer_projection.call(point)

	func logical_pointer_from_root(point: Vector2) -> Vector2:
		return pointer_unprojection.call(point)

	func project_target(target: Variant) -> Variant:
		return target_projection.call(target)
