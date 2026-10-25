## 管理二维纸张遮罩与三维纸面的材质对应关系。
extends RefCounted

const PaperShader := preload("res://shaders/studio/desk_paper_surface.gdshader")

var errors: Array[String] = []
var _entries: Dictionary = {}

func configure(masks: Dictionary) -> bool:
	clear()
	errors.clear()
	if masks.is_empty():
		_fail("Painter paper masks require configured sheet masks")
		return false
	for key in masks:
		var mask := masks[key] as TextureRect
		if mask == null or mask.texture == null:
			_fail("Missing Painter paper mask texture: " + str(key))
			return false
		var material := mask.material as ShaderMaterial
		if material == null or material.shader != PaperShader:
			_fail("Painter paper mask requires the paper surface shader: " + str(key))
			return false
	for key in masks:
		var mask := masks[key] as TextureRect
		var material := mask.material as ShaderMaterial
		_entries[str(key)] = {"mask": mask, "material": material, "previous": (material.get_shader_parameter("painter_stock_only") == true), "texture": mask.texture, "clip_children": mask.clip_children, "clip_contents": mask.clip_contents, "self_modulate": mask.self_modulate, "children": mask.get_child_count()}
		material.set_shader_parameter("painter_stock_only", true)
	return true

## 解除本对象维护的遮罩绑定，不销毁调用方持有的纸张。
func clear() -> void:
	for entry: Dictionary in _entries.values():
		var material: ShaderMaterial = entry["material"]
		if is_instance_valid(material):
			material.set_shader_parameter("painter_stock_only", entry["previous"])
	_entries.clear()

func inspection() -> Dictionary:
	var masks: Dictionary = {}
	for key in _entries:
		var entry: Dictionary = _entries[key]
		var mask: TextureRect = entry["mask"]
		var material: ShaderMaterial = entry["material"]
		if not is_instance_valid(mask):
			masks[key] = {"valid": false}
			continue
		masks[key] = {"valid": true, "painter_stock_only": (material.get_shader_parameter("painter_stock_only") == true), "texture": mask.texture.resource_path if mask.texture != null else "", "texture_preserved": mask.texture == entry["texture"], "material_preserved": mask.material == material, "clip_children": mask.clip_children, "clip_children_preserved": mask.clip_children == entry["clip_children"], "clip_contents_preserved": mask.clip_contents == entry["clip_contents"], "self_modulate_preserved": mask.self_modulate == entry["self_modulate"], "children_preserved": mask.get_child_count() == entry["children"]}
	return {"enabled": not _entries.is_empty(), "mask_count": _entries.size(), "alpha_mode": "original_source", "masks": masks, "errors": errors.duplicate()}

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
