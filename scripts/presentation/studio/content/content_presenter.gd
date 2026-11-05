extends Node3D

const ScreenSurface := preload("res://scripts/rendering/screens/screen_surface.gd")
const PaperFeed := preload("res://scripts/rendering/paper/paper_feed.gd")
const PrintShader := preload("res://shaders/studio/studio_print_surface.gdshader")
const DayShader := preload("res://shaders/studio/studio_clock_day.gdshader")

var startup_error := ""
var screen_surfaces: Array[Node] = []
var bindings: Array[Dictionary] = []
var paper_bindings: Array[Dictionary] = []
var _emitted_papers: Dictionary = {}
var _logical: SubViewport
var _assembly: Node3D
var _fbx_loader: RefCounted
var _desktop: RefCounted
var _whitebox := false
var _ink: ShaderMaterial
var _day_ink: ShaderMaterial
var _node_cache: Dictionary = {}

func configure(fbx_loader: RefCounted, assembly: Node3D, logical: SubViewport, desktop: RefCounted, whitebox: bool) -> bool:
	_fbx_loader = fbx_loader
	_assembly = assembly
	_logical = logical
	_desktop = desktop
	_whitebox = whitebox
	_ink = _material(true)
	_ink.set_shader_parameter("remove_hardware", true)
	var equipment_rects := PackedVector4Array()
	var equipment_angles := PackedFloat32Array()
	for item: Dictionary in _desktop.equipment_layout():
		var source: Control = item.source
		var transform := source.get_global_transform()
		var center := transform * (source.size * .5)
		var dimensions := source.size * transform.get_scale()
		if item.id == "desk_clock":
			_ink.set_shader_parameter("clock_circle",Vector3(center.x,center.y,dimensions.x * .44))
		else:
			equipment_rects.append(Vector4(center.x,center.y,dimensions.x,dimensions.y))
			equipment_angles.append(transform.get_rotation())
	_ink.set_shader_parameter("equipment_rects", equipment_rects)
	_ink.set_shader_parameter("equipment_angles", equipment_angles)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.8, 1.8)
	var printed_desk := MeshInstance3D.new()
	printed_desk.name = "LivePrintedPaperAndMaterials"
	printed_desk.mesh = plane
	printed_desk.position.y = .0006
	printed_desk.material_override = _ink
	add_child(printed_desk)
	_bind_content()
	return startup_error.is_empty()

func sync(delta: float, clock_angles: Vector2, daylight: float) -> void:
	var canvas := _logical.get_canvas_transform()
	_ink.set_shader_parameter("canvas_origin", canvas.origin)
	_ink.set_shader_parameter("canvas_x", canvas.x)
	_ink.set_shader_parameter("canvas_y", canvas.y)
	_sync_live_papers(delta)
	for binding: Dictionary in bindings:
		var transform: Transform2D = binding.source.get_global_transform_with_canvas()
		var rect: Rect2 = binding.rect
		binding.material.set_shader_parameter("origin_px", transform * rect.position)
		binding.material.set_shader_parameter("u_px", transform.basis_xform(Vector2(rect.size.x, 0)))
		binding.material.set_shader_parameter("v_px", transform.basis_xform(Vector2(0, rect.size.y)))
	_node("desk_clock__SeasonRingPivot").rotation.y = -clock_angles.x
	_node("desk_clock__DayRingPivot").rotation.y = -clock_angles.y
	_day_ink.set_shader_parameter("daylight_fraction", daylight)

func inspection() -> Dictionary:
	var screens: Array[Dictionary] = []
	for renderer in screen_surfaces: screens.append(renderer.inspection())
	var feeds: Dictionary = {}
	for binding: Dictionary in paper_bindings:
		if binding.has("feed"): feeds[str(binding.id)] = binding.feed.inspection()
	return {"screens":screens, "paper_feeds":feeds, "content_bindings":bindings.size(), "live_papers":paper_bindings.size(), "startup_error":startup_error}

func _node(id: String) -> Node3D:
	if not _node_cache.has(id): _node_cache[id] = _assembly.find_child(id, true, false)
	return _node_cache[id] as Node3D

func paper_exit(asset_id: String) -> Dictionary:
	return PaperFeed.measure_exit(_assembly, asset_id)


func _material(world: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PrintShader
	material.set_shader_parameter("desktop_texture",_logical.get_texture())
	material.set_shader_parameter("world_mapping",world)
	return material


func _bind_surface(id: String, source: Control, rect: Rect2, emission := 0.08, background := Color.TRANSPARENT) -> void:
	var target := _node(id) as MeshInstance3D
	if target == null:
		startup_error += "Missing surface: "+id+"; "
		return
	var material := _material()
	material.set_shader_parameter("screen_emission",emission)
	material.set_shader_parameter("background",background)
	target.material_override = material
	bindings.append({"mesh":target,"source":source,"rect":rect,"material":material})


func _bind_content() -> void:
	for screen: Dictionary in _desktop.screen_sources():
		_bind_screen(screen.id, screen.source, screen.rect)
	_bind_surface("desk_clock__DateContent", _desktop.date_source(), Rect2(61, 99, 94, 58))
	for id in ["fax_paper", "receipt_paper", "material_card", "note_strip", "workpaper_map", "workpaper_edit", "workpaper_cultivate", "workpaper_spread"]:
		var root := _node(id)
		if root != null: root.hide()
	for paper: Dictionary in _desktop.initial_papers():
		_add_live_paper(paper.asset, paper.source, paper.size, paper.id, paper.curve)
	var day := _node("desk_clock__DayRing") as MeshInstance3D
	_day_ink = ShaderMaterial.new()
	_day_ink.shader = DayShader
	var day_texture: Texture2D = _fbx_loader.painter_materials.texture_for_set("Print_DayRing", "BaseColor")
	_day_ink.set_shader_parameter("printed_ring",day_texture)
	# The export retains FBX UVs; the print center is normalized in the source UV frame.
	_day_ink.set_shader_parameter("source_center_uv",Vector2(0.5,616.5/1254.0))
	day.material_override = _day_ink
	for id in ["desk_clock__SeasonRing","desk_clock__PrintedFace"]:
		var part := _node(id) as MeshInstance3D
		var set_name := "Print_SeasonRing" if id.ends_with("SeasonRing") else "Print_PrintedFace"
		var mat := _fbx_loader.painter_materials.material_for_set(set_name).duplicate() as StandardMaterial3D
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		part.material_override = mat


func _bind_screen(id: String, source: Control, rect: Rect2) -> void:
	var renderer := ScreenSurface.new()
	renderer.name = id + "Presentation"
	add_child(renderer)
	if renderer.configure(_node(id) as MeshInstance3D, source, rect, _logical):
		screen_surfaces.append(renderer)
	else:
		startup_error += "Cannot configure screen: " + id + "; "
		renderer.queue_free()


func _add_live_paper(asset_id: String, source: Control, template_size: Vector2, id: String, curve := 0) -> void:
	var model: Node3D = _fbx_loader.paper_template(asset_id)
	if model == null:
		startup_error += "Missing FBX paper: "+asset_id+"; "
		return
	model.name = "LivePaper_"+id
	add_child(model)
	var surface := model.find_child(asset_id+"__PaperSurface",true,false) as MeshInstance3D
	var material := _material()
	material.set_shader_parameter("feed_curve",0)
	material.set_shader_parameter("mouth_height_m",.132 if curve==1 else .077)
	if source is TextureRect:
		material.set_shader_parameter("paper_mask_enabled", true)
		material.set_shader_parameter("paper_mask_texture", source.texture)
	elif source.has_method("print_mask"):
		material.set_shader_parameter("paper_mask_enabled", true)
		material.set_shader_parameter("paper_mask_texture", source.print_mask())
	if not _whitebox:
		material.set_shader_parameter("paper_stock_enabled",true)
		material.set_shader_parameter("paper_stock_texture",_fbx_loader.painter_materials.texture_for_set("SP_"+asset_id,"BaseColor"))
		material.set_shader_parameter("paper_stock_roughness",_fbx_loader.painter_materials.texture_for_set("SP_"+asset_id,"Roughness"))
	for index in surface.mesh.get_surface_count():
		surface.set_surface_override_material(index, material)
	for child in model.find_children("*","MeshInstance3D",true,false):
		if child != surface: child.hide()
	var binding := {"mesh":surface,"source":source,"rect":Rect2(Vector2.ZERO,source.size),"material":material,"model":model,"template":template_size,"id":id,"curve":curve}
	if curve != 0:
		var feed := PaperFeed.new()
		if feed.configure(surface,curve,template_size):
			binding["feed"] = feed
		else:
			startup_error += "Cannot configure paper feed: " + asset_id + "; "
	paper_bindings.append(binding)
	bindings.append(binding)

func _add_paper_tab(source: Control) -> Dictionary:
	var mesh := MeshInstance3D.new()
	mesh.name = "LivePaperTab"
	mesh.mesh = PlaneMesh.new()
	mesh.mesh.subdivide_depth = 8
	var material := _material()
	if source is TextureRect:
		material.set_shader_parameter("paper_mask_enabled", true)
		material.set_shader_parameter("paper_mask_texture", source.texture)
	mesh.material_override = material
	add_child(mesh)
	var binding := {"mesh":mesh, "source":source, "rect":Rect2(Vector2.ZERO, source.size), "material":material}
	bindings.append(binding)
	return binding

func _sync_paper_tab(binding: Dictionary) -> void:
	var tab: Control
	if str(binding.id) in ["map", "edit", "cultivate", "spread"]:
		tab = _desktop.sheet_tab(str(binding.id))
	elif int(binding.curve) == 2:
		tab = binding.source.get_node_or_null("EventHistoryTab")
	if tab == null: return
	if not binding.has("tab"): binding.tab = _add_paper_tab(tab)
	var tab_binding: Dictionary = binding.tab
	var frame := tab.get_global_transform()
	var center := frame * (tab.size * .5)
	var mesh: MeshInstance3D = tab_binding.mesh
	mesh.visible = tab.is_visible_in_tree()
	mesh.position = Vector3((center.x - 800) / 1000.0, binding.model.position.y + .0004, (center.y - 450) / 1000.0)
	mesh.rotation.y = -frame.get_rotation()
	tab_binding.rect = Rect2(Vector2.ZERO, tab.size)
	if int(binding.curve) == 2:
		mesh.mesh.size = tab.size * frame.get_scale().abs() / 1000.0
		var feed: Dictionary = binding.feed.inspection()
		var scale_y: float = binding.source.get_global_transform().get_scale().y
		var material: ShaderMaterial = tab_binding.material
		material.set_shader_parameter("feed_curve", 2)
		material.set_shader_parameter("sheet_depth_m", tab.size.y * absf(scale_y) / 1000.0)
		material.set_shader_parameter("mouth_height_m", feed.mouth_height_m - binding.model.position.y)
		material.set_shader_parameter("feed_falloff_m", feed.bend_falloff_m)
		material.set_shader_parameter("feed_distance_offset_m", (binding.source.size.y - tab.position.y - tab.size.y) * absf(scale_y) / 1000.0 - feed.lip_clearance_m)
	else:
		_conform_workpaper_tab(binding, tab, frame.get_scale().abs())

func _conform_workpaper_tab(binding: Dictionary, tab: Control, tab_scale: Vector2) -> void:
	var source: Control = binding.source
	var tab_binding: Dictionary = binding.tab
	var relative: Transform2D = source.get_transform().affine_inverse() * tab.get_parent().get_transform() * tab.get_transform()
	var signature: Array = [relative, source.size, tab.size, tab_scale]
	if tab_binding.has("shape_signature"):
		var previous: Array = tab_binding.shape_signature
		if relative.is_equal_approx(previous[0]) and source.size.is_equal_approx(previous[1]) and tab.size.is_equal_approx(previous[2]) and tab_scale.is_equal_approx(previous[3]): return
	var mesh: MeshInstance3D = tab_binding.mesh
	var surface: MeshInstance3D = binding.mesh
	var front := surface.mesh.surface_get_arrays(surface.mesh.get_surface_count() - 1)
	var triangles: PackedVector3Array = front[Mesh.ARRAY_VERTEX]
	var plane := PlaneMesh.new()
	plane.size = tab.size * tab_scale / 1000.0
	plane.subdivide_depth = 8
	var arrays := plane.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var heights := PackedFloat32Array()
	# Follow the attachment edge; a distant curled corner must not lift the tab.
	for row in 10:
		var point := Vector3((tab.size.x * .5 - 1.0) * tab_scale.x / 1000.0, 0.0, (float(row) / 9.0 - .5) * plane.size.y)
		var origin := surface.to_local(mesh.to_global(point))
		origin.y = surface.get_aabb().end.y + .01
		var hit: Variant = null
		for index in range(0, triangles.size(), 3):
			hit = Geometry3D.ray_intersects_triangle(origin, Vector3.DOWN, triangles[index], triangles[index + 1], triangles[index + 2])
			if hit != null: break
		assert(hit != null, "Workpaper tab attachment must lie on its sheet surface.")
		heights.append(mesh.to_local(surface.to_global(hit)).y + .0001)
	for index in vertices.size():
		vertices[index].y = heights[roundi(uvs[index].y * 9.0)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		tool.set_uv(uvs[index])
		tool.add_vertex(vertices[index])
	tool.generate_normals()
	mesh.mesh = tool.commit()
	tab_binding.shape_signature = signature


func _sync_live_papers(delta: float) -> void:
	for binding in paper_bindings.duplicate():
		if not is_instance_valid(binding.source):
			if binding.has("tab"):
				binding.tab.mesh.queue_free()
				bindings.erase(binding.tab)
			binding.model.queue_free()
			bindings.erase(binding)
			paper_bindings.erase(binding)
	for id in _emitted_papers.keys():
		if not is_instance_valid(_emitted_papers[id]): _emitted_papers.erase(id)
	var outputs: Array[Control] = _desktop.output_papers()
	for output: Control in outputs:
		if not _emitted_papers.has(output.get_instance_id()):
			_add_live_paper("fax_paper",output,Vector2(.210,.297),"fax_"+str(output.get_instance_id()),2)
			_emitted_papers[output.get_instance_id()] = output
	_sync_material_cards()
	for binding in paper_bindings:
		var source: Control = binding.source
		if not is_instance_valid(source):
			binding.model.hide()
			continue
		binding.model.visible = source.is_visible_in_tree()
		binding.rect = Rect2(Vector2.ZERO,source.size)
		var transform := source.get_global_transform()
		var center := transform*(source.size*.5)
		var scale_2d := transform.get_scale()
		binding.model.position = Vector3((center.x-800)/1000,.002,(center.y-450)/1000)
		binding.model.rotation.y = -transform.get_rotation()
		binding.model.scale = Vector3(source.size.x*scale_2d.x/1000/binding.template.x,1,source.size.y*scale_2d.y/1000/binding.template.y)
		if str(binding.id) in ["map","edit","cultivate","spread"]:
			var depth: int = _desktop.sheet_depth(str(binding.id))
			binding.model.position.y = .0015 + (depth-24)*.0007
			var index: int = binding.mesh.find_blend_shape_by_name("LiftEdge")
			if index>=0:
				var wanted := .12 if _desktop.sheets_switching() else 0.0
				binding.mesh.set_blend_shape_value(index,move_toward(binding.mesh.get_blend_shape_value(index),wanted,delta*.6))
		if int(binding.curve) == 2:
			# History selection changes sibling order without changing the output list.
			binding.model.position.y = _fax_floor_height(source)
		if binding.get("material_card",false):
			if source.has_method("print_mask"):
				binding.material.set_shader_parameter("paper_mask_texture", source.print_mask())
			var owner: Control = binding.card_owner
			var dragging := false
			if is_instance_valid(owner):
				dragging = owner.is_dragging()
			else:
				dragging = _desktop.card_dragging(str(binding.card_key))
			# Attached faces are already drawn on the fax paper's surface.
			var attached := is_instance_valid(owner) and outputs.has(owner.get_parent())
			binding.model.visible = source.is_visible_in_tree() and not attached
			binding.model.position.y = _material_card_height(source,int(binding.card_rank),dragging)
		binding.material.set_shader_parameter("sheet_depth_m",source.size.y*absf(scale_2d.y)/1000)
		if binding.has("feed") and binding.model.visible:
			binding.feed.sync(source,paper_exit("receipt_printer" if int(binding.curve)==1 else "fax_machine"))
		_sync_paper_tab(binding)


func _material_card_height(source: Control, rank: int, dragging: bool) -> float:
	var paper_top := _workpaper_top()
	for binding in paper_bindings:
		if int(binding.curve) != 2 or not binding.source.is_visible_in_tree(): continue
		var sheet: Control = binding.source
		var frame := sheet.get_global_transform().affine_inverse() * source.get_global_transform()
		var overlap := (frame * Rect2(Vector2.ZERO, source.size)).intersection(Rect2(Vector2.ZERO, sheet.size))
		if not overlap.has_area(): continue
		var floor_y := _fax_floor_height(sheet)
		var feed: Dictionary = binding.feed.inspection()
		var mouth := paper_exit("fax_machine")
		var distance := (sheet.size.y - overlap.end.y) * absf(sheet.get_global_transform().get_scale().y) / 1000.0 - float(mouth.lip_clearance_m) - float(feed.native_thickness_m)
		var height := (float(mouth.height) - floor_y) * exp(-maxf(0.0, distance) / float(feed.bend_falloff_m))
		paper_top = maxf(paper_top, floor_y + height)
	return paper_top + .001 + maxi(rank,0)*.0001 + (.006 if dragging else 0.0)

func _fax_floor_height(source: Control) -> float:
	return _workpaper_top() + .001 + source.get_index() * .0007

func _workpaper_top() -> float:
	var paper_top := .0006
	for binding in paper_bindings:
		if not is_instance_valid(binding.mesh) or not binding.mesh.is_visible_in_tree(): continue
		if str(binding.id) not in ["map","edit","cultivate","spread"]: continue
		var bounds: AABB = binding.mesh.global_transform * binding.mesh.get_aabb()
		paper_top = maxf(paper_top,bounds.end.y)
	return paper_top


func _bind_material_face(source: Control, key: String, rank: int, owner: Control = null) -> void:
	if not is_instance_valid(source): return
	var identity := source.get_instance_id()
	if not _emitted_papers.has(identity):
		_add_live_paper("material_card",source,Vector2(.085,.055),"material_"+str(identity))
		if not paper_bindings.is_empty() and paper_bindings[-1].source == source:
			var binding: Dictionary = paper_bindings[-1]
			binding.material_card = true
			binding.card_key = key
			binding.card_rank = rank
			binding.card_owner = owner
		_emitted_papers[identity] = source
	for binding in paper_bindings:
		if binding.get("material_card",false) and binding.source == source:
			binding.card_rank = rank
			break


func _sync_material_cards() -> void:
	var rank := 0
	for face: Dictionary in _desktop.material_faces():
		_bind_material_face(face.source, face.key, rank, face.owner)
		if face.visible: rank += 1
