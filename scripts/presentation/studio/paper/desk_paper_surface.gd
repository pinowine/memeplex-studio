class_name DeskPaperSurface
extends RefCounted

const SURFACE_SHADER := preload("res://shaders/studio/desk_paper_surface.gdshader")
const MACRO_EDGE := 96
const DETAIL_DENSITY := 3.2
static var _macro_maps: Dictionary = {}

static func make_material(paper: Texture2D, world_size: Vector2, seed: float = 0.0) -> ShaderMaterial:
	if paper == null or not world_size.is_finite() or world_size.x <= 0.0 or world_size.y <= 0.0:
		push_error("Paper surface requires a texture and positive finite world size.")
		return null
	var macro := _macro_map(paper)
	if macro == null: return null
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("paper_size",world_size)
	material.set_shader_parameter("macro_map",macro)
	material.set_shader_parameter("fiber_seed",seed)
	material.set_shader_parameter("detail_density",DETAIL_DENSITY)
	material.set_shader_parameter("sharpen_alpha",false)
	return material

static func apply_to(mask: TextureRect, seed: float = 0.0) -> ShaderMaterial:
	if mask == null: return null
	var existing := mask.material as ShaderMaterial
	if existing != null and existing.shader == SURFACE_SHADER:
		existing.set_shader_parameter("paper_size",mask.size.max(Vector2.ONE))
		return existing
	if mask.material != null:
		push_error("Paper surface cannot replace an unrelated mask material.")
		return null
	var material := make_material(mask.texture,mask.size.max(Vector2.ONE),seed)
	if material == null: return null
	mask.material = material
	mask.resized.connect(func() -> void:
		if is_instance_valid(mask) and mask.material == material:
			material.set_shader_parameter("paper_size",mask.size.max(Vector2.ONE)))
	return material

static func _macro_map(paper: Texture2D) -> Texture2D:
	var key := paper.get_instance_id()
	if _macro_maps.has(key): return _macro_maps[key]
	var source := paper.get_image()
	if source == null or source.is_empty():
		push_error("Paper surface cannot read its source colour map.")
		return null
	var macro := source.duplicate() as Image
	if macro.is_compressed():
		var status := macro.decompress()
		if status != OK:
			push_error("Paper surface colour-map decompression failed: "+str(status))
			return null
	# This small map carries broad paper colour only; all fine fibres are analytic.
	var ratio := float(MACRO_EDGE)/float(maxi(macro.get_width(),macro.get_height()))
	macro.resize(maxi(1,roundi(macro.get_width()*ratio)),maxi(1,roundi(macro.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	macro.generate_mipmaps()
	var texture := ImageTexture.create_from_image(macro)
	_macro_maps[key] = texture
	return texture

static func inspection(mask: TextureRect) -> Dictionary:
	if mask == null: return {}
	var material := mask.material as ShaderMaterial
	if material == null or material.shader != SURFACE_SHADER: return {"enabled":false}
	var macro := material.get_shader_parameter("macro_map") as Texture2D
	return {"enabled":true,"shader":SURFACE_SHADER.resource_path,"paper_size":material.get_shader_parameter("paper_size"),"body_detail":"analytic_world_coordinate_fibres","detail_lattice_samples_per_world_unit":material.get_shader_parameter("detail_density"),"macro_resolution":macro.get_size() if macro != null else Vector2.ZERO,"original_texture":mask.texture.resource_path if mask.texture != null else "","original_texture_instance":mask.texture.get_instance_id() if mask.texture != null else 0,"alpha_mode":"original_source" if not bool(material.get_shader_parameter("sharpen_alpha")) else "same_half_alpha_contour_sharpened_fringe","mutates_source_image":false,"resized_binding":true}
