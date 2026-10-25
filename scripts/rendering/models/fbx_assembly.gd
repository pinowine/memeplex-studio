## 使用模型层级定位设备，以完整场景 FBX 的几何和材质构造运行实例。
extends RefCounted

const PainterMaterials := preload("res://scripts/rendering/materials/painter_materials.gd")
const AUTHORING_PATH := "res://art_source/substance_painter/studio/support/fullscene/studio_fullscene_high.fbx"
const FBX_PATH := "res://assets/model/studio/environment/studio_fullscene.fbx"
const ASSEMBLY_PATH := "res://assets/model/studio/environment/desk_assembly.glb"
const MODEL_DIRECTORY := "res://assets/model/studio/paper/"

var errors: Array[String] = []
var build_report: Dictionary = {}
var paper_reports: Dictionary = {}
var painter_materials := PainterMaterials.new()
var _sources: Array[Dictionary] = []
var _asset_frames: Dictionary = {}
var _suffix := RegEx.new()
var _unsafe_name := RegEx.new()

func _init() -> void:
	_suffix.compile("_[a-fA-F0-9]{6}_high$")
	_unsafe_name.compile("[^A-Za-z0-9_]+")

func inspection() -> Dictionary:
	return {"authoring_source": AUTHORING_PATH, "source": FBX_PATH, "runtime": {"source": FBX_PATH}, "source_meshes": _sources.size(), "assembly": build_report.duplicate(true), "papers": paper_reports.duplicate(true), "painter_materials": painter_materials.inspection(), "errors": errors.duplicate()}

## 返回独立工作室实例；源场景无法加载时返回 null。
func build() -> Node3D:
	if not _load_sources():
		return null
	var template := _instantiate(ASSEMBLY_PATH)
	if template == null:
		return null
	for child in template.get_children():
		if child is Node3D:
			_asset_frames[str(child.name)] = _frame(child, template)
	build_report = _replace_geometry(template, "", Transform3D.IDENTITY)
	_restore_date_surface(template)
	_sync_contact_content_mount(template)
	build_report["procedural_content_planes"] = 1
	var hidden_output_tray_meshes: Array[String] = []
	for node in template.find_children("*", "MeshInstance3D", true, false):
		var source_name := str(node.get_meta("fbx_source_node", ""))
		if source_name.begins_with("studio_tools__MaterialTray"):
			node.hide()
			hidden_output_tray_meshes.append(source_name)
	build_report["hidden_output_tray_meshes"] = hidden_output_tray_meshes
	template.set_meta("geometry_source", FBX_PATH)
	template.set_meta("fbx_geometry_report", build_report.duplicate(true))
	return template

## 按设备中的原始安装坐标构造纸张，调用方负责实例的生命周期。
func paper_template(asset_id: String) -> Node3D:
	if not _load_sources():
		return null
	if not _asset_frames.has(asset_id):
		var assembly := _instantiate(ASSEMBLY_PATH)
		if assembly == null:
			return null
		var asset := assembly.find_child(asset_id, true, false) as Node3D
		if asset == null:
			_fail("Missing paper assembly frame: " + asset_id)
			assembly.free()
			return null
		_asset_frames[asset_id] = _frame(asset, assembly)
		assembly.free()
	var template := _instantiate(MODEL_DIRECTORY + asset_id + ".glb")
	if template == null:
		return null
	var report := _replace_geometry(template, asset_id, _asset_frames[asset_id])
	var surface := template.find_child(asset_id + "__PaperSurface", true, false) as MeshInstance3D
	if surface == null or surface.mesh == null:
		_fail("Missing FBX paper surface: " + asset_id)
		template.free()
		return null
	_project_paper_content(surface, asset_id)
	report["content_surfaces"] = surface.mesh.get_surface_count()
	paper_reports[asset_id] = report
	template.set_meta("geometry_source", FBX_PATH)
	template.set_meta("fbx_geometry_report", report.duplicate(true))
	return template

func _load_sources() -> bool:
	if not _sources.is_empty():
		return true
	if not painter_materials.load_manifest():
		for message in painter_materials.errors:
			_fail(message)
		return false
	var scene := _instantiate(FBX_PATH)
	if scene == null:
		return false
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source.mesh == null:
			continue
		if not painter_materials.apply_to_mesh(str(source.name), source.mesh):
			for message in painter_materials.errors:
				_fail(message)
			_fail("Painter material binding failed for exact FBX source: " + str(source.name))
			scene.free()
			_sources.clear()
			return false
		var frame := _frame(source, scene)
		_sources.append({"name": str(source.name), "canonical": _canonical(str(source.name)), "mesh": source.mesh, "frame": frame, "world_aabb": frame * source.get_aabb(), "painter_set": painter_materials.texture_set_for_source(str(source.name))})
	scene.free()
	if _sources.size() != painter_materials.manifest["meshes"].size():
		_fail("Painter mesh mapping count differs from imported FBX mesh count")
		_sources.clear()
		return false
	if _sources.is_empty():
		_fail("FBX contains no imported mesh geometry: " + FBX_PATH)
	return not _sources.is_empty()

func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("Cannot load scene: " + path)
		return null
	var scene := packed.instantiate() as Node3D
	if scene == null:
		_fail("Scene has no Node3D root: " + path)
	return scene

func _replace_geometry(template: Node3D, asset_filter: String, assembly_frame: Transform3D) -> Dictionary:
	var originals: Array[Dictionary] = []
	var used: Dictionary = {}
	var matched := 0
	var added := 0
	var removed := 0
	var vertices := 0
	for node in template.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var frame := assembly_frame * _frame(mesh_node, template)
		originals.append({"node": mesh_node, "frame": frame, "aabb": frame * mesh_node.get_aabb(), "name": str(mesh_node.name)})
		mesh_node.mesh = null
		mesh_node.material_override = null
	for original in originals:
		var node: MeshInstance3D = original.node
		var best := _match_source(original, used, asset_filter)
		if best < 0:
			if original.name == "desk_clock__DateContent":
				continue
			var parent := node.get_parent() as Node3D
			for child in node.get_children():
				var child_frame: Transform3D = node.transform * child.transform if child is Node3D else Transform3D.IDENTITY
				node.remove_child(child)
				parent.add_child(child)
				if child is Node3D:
					child.transform = child_frame
			parent.remove_child(node)
			node.free()
			removed += 1
			continue
		used[best] = true
		var source: Dictionary = _sources[best]
		var local_from_source: Transform3D = original.frame.affine_inverse() * source.frame
		node.mesh = _bake(source.mesh, local_from_source)
		_mark_source(node, source.name)
		vertices += _vertex_count(node.mesh)
		matched += 1
	for i in _sources.size():
		if used.has(i):
			continue
		var source: Dictionary = _sources[i]
		var prefix: String = str(source.canonical).get_slice("__", 0)
		if not asset_filter.is_empty() and prefix != asset_filter:
			continue
		var parent := template.find_child(prefix, true, false) as Node3D
		if parent == null:
			parent = Node3D.new()
			parent.name = prefix
			template.add_child(parent)
		var node := MeshInstance3D.new()
		node.name = source.canonical
		if parent.find_child(str(node.name), false, false) != null:
			node.name = source.name
		parent.add_child(node)
		var parent_frame: Transform3D = assembly_frame * _frame(parent, template)
		node.mesh = _bake(source.mesh, parent_frame.affine_inverse() * source.frame)
		_mark_source(node, source.name)
		vertices += _vertex_count(node.mesh)
		added += 1
	return {"matched_fbx_meshes": matched, "additional_fbx_meshes": added, "fbx_meshes": matched + added, "removed_template_meshes": removed, "retained_old_geometry": 0, "vertices": vertices}

func _match_source(original: Dictionary, used: Dictionary, asset_filter: String) -> int:
	var name: String = original.name
	var exported := _unsafe_name.sub(name.replace("-", "_neg_"), "_", true).left(40)
	var best := -1
	var best_distance := INF
	for i in _sources.size():
		if used.has(i):
			continue
		var source: Dictionary = _sources[i]
		var canonical: String = source.canonical
		if not asset_filter.is_empty() and canonical.get_slice("__", 0) != asset_filter:
			continue
		if canonical != name and canonical != exported:
			continue
		var source_box: AABB = source.world_aabb
		var original_box: AABB = original.aabb
		var distance := source_box.get_center().distance_squared_to(original_box.get_center())
		if distance < best_distance:
			best = i
			best_distance = distance
	return best

func _bake(mesh: Mesh, transform: Transform3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var surface := SurfaceTool.new()
		surface.append_from(mesh, i, transform)
		surface.commit(result)
		result.surface_set_material(result.get_surface_count() - 1, mesh.surface_get_material(i))
	return result

func _mark_source(node: MeshInstance3D, source_name: String) -> void:
	node.set_meta("geometry_source", FBX_PATH)
	node.set_meta("fbx_source_node", source_name)
	node.set_meta("painter_set", painter_materials.texture_set_for_source(source_name))

func _canonical(name: String) -> String:
	return _suffix.sub(name, "")

func _frame(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = current.transform * result
		current = current.get_parent()
	return result

func _restore_date_surface(template: Node3D) -> void:
	var mount := template.find_child("desk_clock__DateContentMount", true, false) as Node3D
	var surface := template.find_child("desk_clock__DateContent", true, false) as MeshInstance3D
	if mount == null:
		_fail("Missing clock date content anchor")
		return
	if surface == null:
		surface = MeshInstance3D.new()
		surface.name = "desk_clock__DateContent"
		mount.get_parent().add_child(surface)
	surface.transform = mount.transform
	var plane := PlaneMesh.new()
	plane.size = Vector2(.102, .058)
	surface.mesh = plane
	surface.set_meta("geometry_source", "procedural_content_plane")
	surface.set_meta("content_anchor", "desk_clock__DateContentMount")

func _sync_contact_content_mount(template: Node3D) -> void:
	var mount := template.find_child("contact_book__PageContentMount", true, false) as Node3D
	var content := template.find_child("contact_book__PageContent", true, false) as MeshInstance3D
	if mount == null or content == null or content.mesh == null:
		_fail("Missing contact book content surface or anchor")
		return
	var surface_frame := _frame(content, template)
	var center := content.get_aabb().get_center()
	center.y = content.get_aabb().position.y
	var target_frame := surface_frame
	target_frame.origin = surface_frame * center
	var parent_frame := _frame(mount.get_parent() as Node3D, template)
	mount.transform = parent_frame.affine_inverse() * target_frame

func _project_paper_content(node: MeshInstance3D, asset_id: String) -> void:
	var mesh := node.mesh
	var box := node.get_aabb()
	var projected := ArrayMesh.new()
	var back := SurfaceTool.new()
	var front := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front_count := 0
	var back_count := 0
	var base_material: Material
	for i in mesh.get_surface_count():
		if base_material == null:
			base_material = mesh.surface_get_material(i)
		var arrays := mesh.surface_get_arrays(i)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var count := indices.size() if not indices.is_empty() else positions.size()
		for triangle in range(0, count, 3):
			var ids: Array[int] = []
			var normal_sum := Vector3.ZERO
			for corner in 3:
				var index := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				ids.append(index)
				normal_sum += normals[index]
			var is_front := normal_sum.y > .01
			var tool := front if is_front else back
			for index in ids:
				tool.set_normal(normals[index])
				tool.set_uv2(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
				if is_front:
					tool.set_uv(Vector2((positions[index].x - box.position.x) / box.size.x, (positions[index].z - box.position.z) / box.size.z))
				else:
					tool.set_uv(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
				tool.add_vertex(positions[index])
			if is_front:
				front_count += 3
			else:
				back_count += 3
	if back_count > 0:
		back.generate_tangents()
		back.commit(projected)
		projected.surface_set_material(projected.get_surface_count() - 1, base_material)
	if front_count > 0:
		front.generate_tangents()
		front.commit(projected)
		var material := StandardMaterial3D.new()
		material.resource_name = "RT_" + asset_id + "_front"
		material.albedo_color = Color.WHITE
		material.roughness = .95
		material.set_meta("painter_stock_set", "SP_" + asset_id)
		material.set_meta("painter_basecolor", painter_materials.texture_for_set("SP_" + asset_id, "BaseColor"))
		material.set_meta("painter_roughness", painter_materials.texture_for_set("SP_" + asset_id, "Roughness"))
		projected.surface_set_material(projected.get_surface_count() - 1, material)
	else:
		_fail("FBX paper has no positive-Y front triangles: " + asset_id)
	node.mesh = projected
	node.set_meta("content_uv", "paper_local_xz_normalized")
	node.set_meta("painter_stock_set", "SP_" + asset_id)

func _vertex_count(mesh: Mesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		count += mesh.surface_get_array_len(i)
	return count

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
