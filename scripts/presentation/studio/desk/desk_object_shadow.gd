@tool
extends TextureRect
class_name DeskObjectShadow

const SHADOW_SHADER := preload("res://shaders/studio/desk_contact_shadow.gdshader")

@export var source_path: NodePath
@export var shadow_offset := Vector2(7.0, 10.0):
	set(value):
		shadow_offset = value
		apply_parameters()
@export_range(0.0, 128.0, 0.5) var shadow_blur := 10.0:
	set(value):
		shadow_blur = value
		apply_parameters()
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 0.28:
	set(value):
		shadow_opacity = value
		apply_parameters()
@export_range(0.0, 128.0, 0.5) var ao_radius := 3.0:
	set(value):
		ao_radius = value
		apply_parameters()
@export_range(0.0, 1.0, 0.01) var ao_strength := 0.2:
	set(value):
		ao_strength = value
		apply_parameters()
@export var shadow_color := Color(0.08, 0.07, 0.06, 1.0):
	set(value):
		shadow_color = value
		apply_parameters()
@export_range(0.0, 32.0, 0.5) var extra_padding := 2.0:
	set(value):
		extra_padding = value
		apply_parameters()

var _source: TextureRect
var _shadow_material: ShaderMaterial
var _draw_rect := Rect2()
var _padding := Vector2.ZERO
var _object_size := Vector2.ZERO
var _base_position := Vector2.ZERO
var _base_pivot := Vector2.ZERO
var _applying := false
var _has_object_rect := false
var _applied_parameters: Array = []
var _parameter_updates := 0
var _parameter_cache_hits := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ensure_material()
	if not source_path.is_empty():
		bind_source(get_node_or_null(source_path) as TextureRect)
	else:
		if not _has_object_rect:
			_object_size = size
			_base_position = position
			_base_pivot = pivot_offset
		apply_parameters()


static func fit_rect(source_size: Vector2, box_size: Vector2, mode: int = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or box_size.x <= 0.0 or box_size.y <= 0.0:
		return Rect2()
	if mode == TextureRect.STRETCH_SCALE:
		return Rect2(Vector2.ZERO, box_size)
	if mode == TextureRect.STRETCH_KEEP_ASPECT or mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		var fitted := source_size * minf(box_size.x / source_size.x, box_size.y / source_size.y)
		return Rect2((box_size - fitted) * 0.5 if mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED else Vector2.ZERO, fitted)
	if mode == TextureRect.STRETCH_KEEP or mode == TextureRect.STRETCH_KEEP_CENTERED:
		return Rect2((box_size - source_size) * 0.5 if mode == TextureRect.STRETCH_KEEP_CENTERED else Vector2.ZERO, source_size)
	push_error("DeskObjectShadow requires SCALE, KEEP or KEEP_ASPECT texture placement.")
	return Rect2()


func configure(source_texture: Texture2D, drawn_size: Vector2 = Vector2.ZERO, keep_aspect: bool = true) -> Rect2:
	texture = source_texture
	if texture == null:
		_draw_rect = Rect2()
		visible = false
		return _draw_rect
	var box := drawn_size if drawn_size.x > 0.0 and drawn_size.y > 0.0 else texture.get_size()
	_draw_rect = fit_rect(texture.get_size(), box, TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep_aspect else TextureRect.STRETCH_SCALE)
	_object_size = _draw_rect.size
	_has_object_rect = true
	visible = true
	apply_parameters()
	return _draw_rect


func place_rect(rect: Rect2) -> void:
	_disconnect_source()
	_draw_rect = Rect2(Vector2.ZERO, rect.size)
	_base_position = rect.position
	_object_size = rect.size.max(Vector2.ZERO)
	_base_pivot = Vector2.ZERO
	_has_object_rect = true
	rotation = 0.0
	scale = Vector2.ONE
	visible = rect.has_area() and texture != null
	apply_parameters()


func bind_source(source: TextureRect) -> void:
	_disconnect_source()
	if source == null or source == self:
		push_error("DeskObjectShadow needs a different TextureRect source.")
		return
	if source.get_parent() != get_parent():
		push_error("DeskObjectShadow and its source must be siblings.")
		return
	_source = source
	_source.item_rect_changed.connect(_sync_bound_source)
	_source.visibility_changed.connect(_sync_bound_source)
	_source.tree_exiting.connect(_source_exiting)
	sync_from(_source)


func sync_from(source: TextureRect) -> void:
	if source == null or source.texture == null:
		visible = false
		return
	_draw_rect = fit_rect(source.texture.get_size(), source.size, source.stretch_mode)
	if not _draw_rect.has_area():
		visible = false
		return
	texture = source.texture
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_base_position = source.position + _draw_rect.position
	_object_size = _draw_rect.size
	_has_object_rect = true
	rotation = source.rotation
	scale = source.scale
	_base_pivot = source.pivot_offset - _draw_rect.position
	flip_h = source.flip_h
	flip_v = source.flip_v
	modulate = source.modulate
	self_modulate = source.self_modulate
	visible = source.visible
	apply_parameters()


func apply_parameters() -> void:
	if not is_node_ready() or _applying: return
	_applying = true
	_ensure_material()
	var radius := maxf(maxf(0.0, shadow_blur), maxf(0.0, ao_radius))
	var padding := shadow_offset.abs() + Vector2.ONE * (radius + maxf(0.0, extra_padding))
	var sample_texture: Texture2D = texture
	var uv_rect := Rect2(Vector2.ZERO, Vector2.ONE)
	var atlas_margin := Rect2()
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		sample_texture = atlas.atlas
		atlas_margin = atlas.margin
		if atlas.atlas != null and atlas.region.has_area():
			uv_rect = Rect2(atlas.region.position / atlas.atlas.get_size(), atlas.region.size / atlas.atlas.get_size())
	var parameters: Array = [_base_position, _base_pivot, _object_size, padding, shadow_offset, shadow_blur, shadow_opacity, ao_radius, ao_strength, shadow_color, flip_h, flip_v, sample_texture, uv_rect, atlas_margin]
	var desired_position := _base_position - padding
	var desired_size := _object_size + padding * 2.0
	var desired_pivot := _base_pivot + padding
	# Idle synchronization must not resend identical rendering-server commands.
	if parameters == _applied_parameters and position == desired_position and size == desired_size and pivot_offset == desired_pivot:
		_parameter_cache_hits += 1
		_applying = false
		return
	_applied_parameters = parameters
	_parameter_updates += 1
	_padding = padding
	position = desired_position
	size = desired_size
	pivot_offset = desired_pivot
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(Vector2.ZERO, size))
	_shadow_material.set_shader_parameter("object_size", _object_size.max(Vector2.ONE))
	_shadow_material.set_shader_parameter("rect_origin", _padding)
	_shadow_material.set_shader_parameter("geometry_is_padded", true)
	_shadow_material.set_shader_parameter("padding", _padding)
	_shadow_material.set_shader_parameter("shadow_offset", shadow_offset)
	_shadow_material.set_shader_parameter("shadow_blur", maxf(0.0, shadow_blur))
	_shadow_material.set_shader_parameter("shadow_opacity", clampf(shadow_opacity, 0.0, 1.0))
	_shadow_material.set_shader_parameter("ao_radius", maxf(0.0, ao_radius))
	_shadow_material.set_shader_parameter("ao_strength", clampf(ao_strength, 0.0, 1.0))
	_shadow_material.set_shader_parameter("shadow_color", shadow_color)
	_shadow_material.set_shader_parameter("source_flip_h", flip_h)
	_shadow_material.set_shader_parameter("source_flip_v", flip_v)
	_shadow_material.set_shader_parameter("source_texture", sample_texture)
	_shadow_material.set_shader_parameter("source_uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))
	if atlas_margin.has_area():
		push_warning("DeskObjectShadow supports AtlasTexture regions without margins.")
	_applying = false
	queue_redraw()


func _ensure_material() -> void:
	if _shadow_material != null: return
	if material is ShaderMaterial and (material as ShaderMaterial).shader == SHADOW_SHADER:
		_shadow_material = material.duplicate() as ShaderMaterial
	else:
		_shadow_material = ShaderMaterial.new()
		_shadow_material.shader = SHADOW_SHADER
	material = _shadow_material
	use_parent_material = false


func _sync_bound_source() -> void:
	if is_instance_valid(_source): sync_from(_source)


func _source_exiting() -> void:
	_source = null
	visible = false


func _disconnect_source() -> void:
	if not is_instance_valid(_source): return
	_source.item_rect_changed.disconnect(_sync_bound_source)
	_source.visibility_changed.disconnect(_sync_bound_source)
	_source.tree_exiting.disconnect(_source_exiting)
	_source = null


func inspection() -> Dictionary:
	return {"parameter_updates":_parameter_updates, "parameter_cache_hits":_parameter_cache_hits, "source_path":str(_source.get_path()) if is_instance_valid(_source) else "", "texture_path":texture.resource_path if texture != null else "", "draw_rect":_draw_rect, "size":size, "object_size":_object_size, "object_rect":get_global_transform() * Rect2(_padding, _object_size), "padding":_padding, "expanded_rect":get_global_transform() * Rect2(Vector2.ZERO, size), "shadow_offset":shadow_offset, "shadow_blur":shadow_blur, "shadow_opacity":shadow_opacity, "ao_radius":ao_radius, "ao_strength":ao_strength, "shadow_color":shadow_color, "shader_path":SHADOW_SHADER.resource_path, "mouse_filter":mouse_filter, "sampling":"Actual source alpha; 13-tap soft cast plus separate unshifted contact AO; expanded physical draw geometry; no image edits"}
