## 读取外置材质资源，并按精确源网格名称和纹理通道清单绑定。
extends RefCounted

const MANIFEST_PATH := "res://data/manifests/studio_materials.json"
const REQUIRED_CHANNELS := ["BaseColor", "Metallic", "Roughness", "Normal"]
const MATERIAL_TEXTURE_PROPERTIES := {
	"BaseColor": "albedo_texture",
	"Metallic": "metallic_texture",
	"Roughness": "roughness_texture",
	"Normal": "normal_texture",
	"Emission": "emission_texture",
}

var manifest: Dictionary = {}
var materials: Dictionary = {}
var errors: Array[String] = []
var _textures: Dictionary = {}
var _bound_sources: Dictionary = {}
var _bound_surfaces := 0
var _loaded := false

## 首次加载检查通道和网格映射，成功后复用本实例的材质缓存。
func load_manifest() -> bool:
	if _loaded:
		return true
	if not errors.is_empty():
		return false
	if not FileAccess.file_exists(MANIFEST_PATH):
		_fail("Missing Painter material manifest: " + MANIFEST_PATH)
		return false
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_fail("Cannot open Painter material manifest: " + MANIFEST_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("Invalid Painter material manifest JSON: " + MANIFEST_PATH)
		return false
	manifest = parsed
	if manifest.get("schema", "") != "painter-runtime-materials@1" or manifest.get("normal_convention", "") != "OpenGL":
		_fail("Unsupported Painter manifest schema or normal convention: " + MANIFEST_PATH)
		return false
	if not manifest.get("sets") is Dictionary or not manifest.get("meshes") is Dictionary or not manifest.get("material_resources") is Dictionary:
		_fail("Painter manifest requires texture sets, material resources and exact mesh mapping")
		return false
	var sets: Dictionary = manifest["sets"]
	var meshes: Dictionary = manifest["meshes"]
	var material_resources: Dictionary = manifest["material_resources"]
	if material_resources.size() != sets.size():
		_fail("Painter material resources differ from declared texture sets")
		return false
	if sets.is_empty() or meshes.is_empty():
		_fail("Painter manifest contains empty texture sets or mesh mapping")
		return false
	for set_key in sets:
		var set_name := str(set_key)
		if not sets[set_key] is Dictionary:
			_fail("Invalid Painter texture set: " + set_name)
			return false
		var channels: Dictionary = sets[set_key]
		for channel in REQUIRED_CHANNELS:
			if not channels.has(channel):
				_fail("Missing Painter channel: " + set_name + "/" + channel)
				return false
		for channel_key in channels:
			if _load_texture(str(channels[channel_key])) == null:
				return false
		var material := _load_material(set_name, str(material_resources.get(set_name, "")), channels)
		if material == null:
			return false
		materials[set_name] = material
	for source_key in meshes:
		if not materials.has(str(meshes[source_key])):
			_fail("Unknown Painter texture set for mesh: " + str(source_key))
			return false
	_loaded = true
	return true

func material_for_set(set_name: String) -> StandardMaterial3D:
	if not load_manifest():
		return null
	if not materials.has(set_name):
		_fail("Missing Painter material set: " + set_name)
		return null
	return materials[set_name] as StandardMaterial3D

func texture_for_set(set_name: String, channel: String) -> Texture2D:
	if not load_manifest():
		return null
	var sets: Dictionary = manifest["sets"]
	if not sets.has(set_name) or not sets[set_name].has(channel):
		_fail("Missing Painter texture channel: " + set_name + "/" + channel)
		return null
	return _textures[str(sets[set_name][channel])] as Texture2D

func texture_set_for_source(source_name: String) -> String:
	if not load_manifest():
		return ""
	var meshes: Dictionary = manifest["meshes"]
	if not meshes.has(source_name):
		_fail("Missing exact Painter mesh mapping: " + source_name)
		return ""
	return str(meshes[source_name])

func apply_to_mesh(source_name: String, mesh: Mesh) -> bool:
	var set_name := texture_set_for_source(source_name)
	if set_name.is_empty():
		return false
	var material := material_for_set(set_name)
	var array_mesh := mesh as ArrayMesh
	if material == null or array_mesh == null or array_mesh.get_surface_count() == 0:
		_fail("Cannot bind Painter material to imported mesh: " + source_name)
		return false
	for surface in array_mesh.get_surface_count():
		array_mesh.surface_set_material(surface, material)
	if not _bound_sources.has(source_name):
		_bound_sources[source_name] = set_name
		_bound_surfaces += array_mesh.get_surface_count()
	return true

func inspection() -> Dictionary:
	var sets: Dictionary = manifest.get("sets", {})
	var meshes: Dictionary = manifest.get("meshes", {})
	var files: Dictionary = manifest.get("files", {})
	return {"manifest_path": MANIFEST_PATH, "texture_set_count": sets.size(), "mesh_mapping_count": meshes.size(), "material_count": materials.size(), "texture_count": _textures.size(), "export_file_count": files.size(), "bound_source_meshes": _bound_sources.size(), "bound_surfaces": _bound_surfaces, "normal_convention": manifest.get("normal_convention", ""), "errors": errors.duplicate()}

## 材质参数由 .tres 定义；这里只核对归属和纹理路径，避免清单与材质接错。
func _load_material(set_name: String, path: String, channels: Dictionary) -> StandardMaterial3D:
	if path.is_empty() or not ResourceLoader.exists(path, "StandardMaterial3D"):
		_fail("Missing Painter material resource: " + set_name + "/" + path)
		return null
	var material := load(path) as StandardMaterial3D
	if material == null or str(material.get_meta("painter_set", "")) != set_name:
		_fail("Painter material set identity differs from manifest: " + set_name)
		return null
	for channel: String in MATERIAL_TEXTURE_PROPERTIES:
		var texture: Texture2D = material.get(MATERIAL_TEXTURE_PROPERTIES[channel])
		if channels.has(channel):
			if texture != _textures[str(channels[channel])]:
				_fail("Painter material texture differs from manifest: " + set_name + "/" + channel)
				return null
		elif texture != null:
			_fail("Painter material has an undeclared texture channel: " + set_name + "/" + channel)
			return null
	return material

func _load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	if path.is_empty() or not ResourceLoader.exists(path):
		_fail("Missing imported Painter texture: " + path)
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		_fail("Cannot load Painter texture: " + path)
		return null
	_textures[path] = texture
	return texture

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
