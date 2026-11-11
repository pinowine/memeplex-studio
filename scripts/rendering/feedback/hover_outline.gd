extends Node

const TornHover := preload("res://shaders/ui/desk_torn_hover.gdshader")

var _camera: Camera3D
var _mask_camera: Camera3D
var _mask: SubViewport
var _polygon: Polygon2D
var _outline: TextureRect
var _material: ShaderMaterial
var _white: StandardMaterial3D
var _meshes: Dictionary = {}
var _active_meshes: Array[Dictionary] = []
var _key := ""
var _mode := ""

func configure(camera: Camera3D) -> void:
	_camera = camera
	_mask = SubViewport.new()
	_mask.name = "HoverSilhouette"
	_mask.transparent_bg = true
	_mask.own_world_3d = true
	_mask.world_2d = World2D.new()
	_mask.gui_disable_input = true
	_mask.msaa_3d = Viewport.MSAA_2X
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask)
	_mask_camera = Camera3D.new()
	_mask.add_child(_mask_camera)
	_mask_camera.current = true
	_white = StandardMaterial3D.new()
	_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_white.cull_mode = BaseMaterial3D.CULL_DISABLED
	_white.albedo_color = Color.WHITE
	_polygon = Polygon2D.new()
	_polygon.color = Color.WHITE
	_mask.add_child(_polygon)
	var layer := CanvasLayer.new()
	layer.name = "HoverOutline"
	# Keep target outlines above the desk finish and below foreground papers.
	layer.layer = 2
	add_child(layer)
	_outline = TextureRect.new()
	_outline.name = "TornHover"
	_outline.texture = _mask.get_texture()
	_outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = TornHover
	_material.set_shader_parameter("source_texture", _mask.get_texture())
	_material.set_shader_parameter("rect_origin", Vector2.ZERO)
	_material.set_shader_parameter("padding", Vector2.ZERO)
	_material.set_shader_parameter("band_width", 5.0)
	_outline.material = _material
	layer.add_child(_outline)
	_outline.hide()
	sync()

func show_meshes(key: String, meshes: Array[MeshInstance3D]) -> void:
	if _key == key and _mode == "meshes": return
	clear()
	_key = key
	_mode = "meshes"
	_mask.msaa_2d = Viewport.MSAA_DISABLED
	for source: MeshInstance3D in meshes:
		var id := source.get_instance_id()
		if not _meshes.has(id):
			var copy := MeshInstance3D.new()
			copy.name = "Silhouette_" + str(source.name)
			copy.mesh = source.mesh
			for surface in source.mesh.get_surface_count():
				var material := source.get_active_material(surface)
				# Printed overlays need their alpha cutouts in the silhouette too.
				var opaque: bool = material is BaseMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				copy.set_surface_override_material(surface, _white if opaque else material)
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mask.add_child(copy)
			_meshes[id] = {"source":source, "copy":copy}
		_active_meshes.append(_meshes[id])
	_outline.show()
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sync()

func show_polygon(key: String, polygon: PackedVector2Array, texture: Texture2D = null) -> void:
	if _mode != "polygon": clear()
	_key = key
	_mode = "polygon"
	_mask.msaa_2d = Viewport.MSAA_2X
	if _polygon.polygon != polygon: _polygon.polygon = polygon
	_polygon.texture = texture
	if texture != null:
		var dimensions := texture.get_size()
		_polygon.uv = PackedVector2Array([Vector2.ZERO, Vector2(dimensions.x, 0), dimensions, Vector2(0, dimensions.y)])
	else: _polygon.uv = PackedVector2Array()
	_polygon.show()
	_outline.show()
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sync()

func clear() -> void:
	for entry: Dictionary in _active_meshes:
		entry.copy.hide()
	_active_meshes.clear()
	_polygon.hide()
	_outline.hide()
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_key = ""
	_mode = ""

func sync() -> void:
	var dimensions := Vector2i(_camera.get_viewport().get_visible_rect().size)
	if _mask.size != dimensions:
		_mask.size = dimensions
		_outline.size = Vector2(dimensions)
		_material.set_shader_parameter("object_size", Vector2(dimensions))
	if _mode != "meshes": return
	_mask_camera.global_transform = _camera.global_transform
	_mask_camera.projection = _camera.projection
	_mask_camera.keep_aspect = _camera.keep_aspect
	_mask_camera.size = _camera.size
	_mask_camera.fov = _camera.fov
	_mask_camera.near = _camera.near
	_mask_camera.far = _camera.far
	_mask_camera.h_offset = _camera.h_offset
	_mask_camera.v_offset = _camera.v_offset
	for entry: Dictionary in _active_meshes:
		entry.copy.global_transform = entry.source.global_transform
		entry.copy.visible = entry.source.is_visible_in_tree()

func inspection() -> Dictionary:
	return {"target":_key, "mode":_mode, "visible":_outline.visible, "mesh_count":_active_meshes.size(), "cached_meshes":_meshes.size(), "polygon":_polygon.polygon, "size":_mask.size, "shader":TornHover.resource_path}
