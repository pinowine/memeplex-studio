extends Node2D

@export var settings: AtlasMapSettings
var world: AtlasWorldData
var terrain_material: ShaderMaterial
var meshes: Array[Array] = []
var coast_lines := PackedVector2Array()
var border_lines := PackedVector2Array()
var river_mesh: ArrayMesh
var lake_meshes: Array[ArrayMesh] = []
var hovered_country: int = -1
var selected_country: int = -1
var zoom_value: float = 1.0
var detail_level: int = 0
var water_opacity: float = 0.0

func set_world(value: AtlasWorldData) -> void:
	world = value
	terrain_material = settings.terrain_material.duplicate()
	terrain_material.set_shader_parameter("elevation_field", ImageTexture.create_from_image(world.terrain.elevation_image(Vector2i(settings.world_size))))
	terrain_material.set_shader_parameter("world_size", settings.world_size)
	$Surface.material = terrain_material
	meshes.clear()
	coast_lines.clear()
	border_lines.clear()
	lake_meshes.clear()
	for edge in world.edges:
		var target: PackedVector2Array = coast_lines if edge.owners.size()==1 else border_lines
		for i in range(edge.points.size()-1):
			target.append(edge.points[i])
			target.append(edge.points[i+1])
	_build_water_meshes()
	for territory in world.territories:
		var surfaces: Array[ArrayMesh] = []
		for i in territory.outlines.size():
			var vertices := PackedVector3Array()
			for point in territory.outlines[i]:
				vertices.append(Vector3(point.x, point.y, 0))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_INDEX] = territory.triangles[i]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			surfaces.append(mesh)
		meshes.append(surfaces)
	hovered_country = -1
	selected_country = -1
	$Water.visible = true
	$Surface.queue_redraw()
	queue_redraw()

func set_highlight(hovered: int, selected: int) -> void:
	hovered_country = hovered
	selected_country = selected
	$Surface.queue_redraw()
	queue_redraw()

func set_view(zoom: float, level: int) -> void:
	zoom_value = zoom
	detail_level = level
	terrain_material.set_shader_parameter("detail_level", float(level))
	$Surface.queue_redraw()
	queue_redraw()

func set_zoom_ratio(ratio: float) -> void:
	water_opacity = water_opacity_at(ratio)
	$Water.self_modulate.a = water_opacity
	$Water/Fill.queue_redraw()

func water_opacity_at(ratio: float) -> float:
	return settings.water_max_opacity * smoothstep(settings.water_fade_start, settings.water_fade_end, ratio)

func _country_color(country: int) -> Color:
	var color := settings.country_colors[country]
	if country == selected_country:
		color = color.blend(settings.selection_color)
	elif country == hovered_country:
		color = color.blend(settings.hover_color)
	return color

func _draw() -> void:
	if meshes.is_empty():
		return
	draw_multiline(border_lines, settings.border_color, settings.border_width, true)
	if selected_country >= 0:
		var width := settings.selected_border_width / pow(zoom_value, settings.selected_border_zoom_exponent)
		for ring in world.territories[selected_country].outlines + world.territories[selected_country].holes:
			var outline: PackedVector2Array = ring.duplicate()
			outline.append(ring[0])
			draw_polyline(outline, settings.selected_border_color, width, true)

func _build_water_meshes() -> void:
	var vertices := PackedVector3Array()
	for point in world.terrain.river_mesh_vertices:
		vertices.append(Vector3(point.x, point.y, 0))
	river_mesh = _mesh(vertices, world.terrain.river_mesh_indices)
	var lake_vertices := PackedVector3Array()
	var lake_indices := PackedInt32Array()
	for polygon in world.terrain.lakes:
		var offset := lake_vertices.size()
		for point in polygon:
			lake_vertices.append(Vector3(point.x, point.y, 0))
		for index in AtlasMapGenerator.triangulate_local(polygon):
			lake_indices.append(index + offset)
	# A scalar-cell mesh keeps holes as empty space, not separately filled rings.
	if not lake_indices.is_empty():
		lake_meshes.append(_mesh(lake_vertices, lake_indices))
	$Water/Fill.queue_redraw()

func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
