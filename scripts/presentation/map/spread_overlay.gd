## Map local composite spread to stable land samples; hover alone changes emphasis.
extends Control

const MAX_TOTAL_DOTS := 12000
const HIT_CELL_SIZE := 16.0
const DOT_RADIUS := 1.6
const HOVER_RADIUS := 2.5
const OTHER_HOVER_OPACITY := 0.25
const POINT_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D hover_mask : filter_nearest, repeat_disable;
uniform bool has_hover = false;
uniform float hover_country = -1.0;
uniform float view_scale = 1.0;
uniform vec3 world_to_map_x;
uniform vec3 world_to_map_y;
uniform vec2 map_size;
varying vec2 unit_point;
varying float marker_radius;
varying float core_radius;
varying float origin_marker;
varying float marker_opacity;
void vertex() {
	unit_point = VERTEX;
	float country = floor(INSTANCE_CUSTOM.y * 0.5);
	origin_marker = mod(INSTANCE_CUSTOM.y, 2.0);
	bool highlighted = has_hover && texelFetch(hover_mask, ivec2(int(INSTANCE_CUSTOM.x), 0), 0).r > 0.5 && (hover_country < 0.0 || country == hover_country);
	core_radius = highlighted ? 2.5 : 1.6;
	marker_radius = core_radius + mix(1.0, 3.5, origin_marker);
	vec3 world_position = vec3(INSTANCE_CUSTOM.zw, 1.0);
	vec2 map_position = vec2(dot(world_to_map_x, world_position), dot(world_to_map_y, world_position));
	float inside = step(6.0, map_position.x) * step(6.0, map_position.y) * step(map_position.x, map_size.x - 6.0) * step(map_position.y, map_size.y - 6.0);
	marker_opacity = inside * ((has_hover && !highlighted) ? 0.25 : 1.0);
	VERTEX *= marker_radius / view_scale;
}
void fragment() {
	float distance_px = length(unit_point) * marker_radius;
	float antialias = max(fwidth(distance_px), 0.7);
	float fill = 1.0 - smoothstep(core_radius - antialias * 0.5, core_radius + antialias * 0.5, distance_px);
	float ring_distance = abs(distance_px - (core_radius + 2.0));
	float ring = (1.0 - smoothstep(0.6 - antialias * 0.5, 0.6 + antialias * 0.5, ring_distance)) * origin_marker;
	COLOR.a *= max(fill, ring) * marker_opacity;
}
"""
const SAMPLE_ATTEMPTS := 24
const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
static var EXPLANATION := DeskLocalization.source("MM_HELP_LEGEND")
const PLAYER_COLORS := [Color("ad4438"), Color("bc852c")]
const EXTERNAL_COLORS := [Color("326f91"), Color("438476"), Color("756095"), Color("3e8c96"), Color("7d7841"), Color("53699d"), Color("578950"), Color("955c83")]

var _simulation: MemeDemoSimulation
var _atlas: Node2D
var _world_layer: Node2D
var _map_input: Control
var _world_id: int = 0
var _country_indices: Dictionary = {}
var _land_cache: Dictionary = {}
var _land_random: Dictionary = {}
var _country_sampling: Dictionary = {}
var _country_capacities: Dictionary = {}
var _point_pools: Dictionary = {}
var _buffer_pools: Dictionary = {}
var _pool_hit_grid: Dictionary = {}
var _active_counts: Dictionary = {}
var _presence_by_key: Dictionary = {}
var _next_sample_order := 0
var _hit_grid: Dictionary = {}
var _projected_geometry := -1
var _projected_view := -1
var _point_multimesh := MultiMesh.new()
var _point_material := ShaderMaterial.new()
var _hover_texture: ImageTexture
var _hover_texture_width := 0
var _meme_draw_indices: Dictionary = {}
var _variant_draw_indices: Dictionary = {}
var _last_upload_usec := 0
var _last_debug_projection_usec := 0
var _sample_points_generated := 0
var _sample_rejections := 0
var _last_hit_candidates := 0
var _last_hit_usec := 0
var _max_hit_usec := 0
var _last_projection_usec := 0
var _max_projection_usec := 0
var _last_geometry_usec := 0
var _last_draw_usec := 0
var _max_draw_usec := 0
var _points: Array[Dictionary] = []
var _screen_points: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _colors: Dictionary = {}
var _metrics := {"owned":0.0, "external":0.0, "adopted":0.0}
var _state_signature: String = ""
var _view_transform := Transform2D.IDENTITY
var _map_transform := Transform2D.IDENTITY
var _overlay_transform := Transform2D.IDENTITY
var _map_rect := Rect2()
var _geometry_rebuilds: int = 0
var _projection_updates: int = 0
var selected_variant_id := ""
var hovered_variant_ids := PackedStringArray()
var hovered_country_id := ""

func _init() -> void:
	var shader := Shader.new()
	shader.code = POINT_SHADER
	_point_material.shader = shader
	material = _point_material
	_point_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_point_multimesh.use_colors = true
	_point_multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_point_multimesh.mesh = quad
	_update_hover_uniforms()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = ""
	process_priority = 25
	set_process(false)

func configure(atlas: Node2D) -> void:
	_atlas = atlas
	_world_layer = atlas.get("world_layer") as Node2D
	_map_input = atlas.get("map_input") as Control
	_world_id = 0
	_refresh_world()
	set_process(true)
	_state_signature = ""
	_points.clear()
	_projected_geometry = -1
	_project_points()

func update_simulation(simulation: MemeDemoSimulation) -> void:
	if simulation == null:
		return
	if _simulation != simulation:
		_state_signature = ""
	_simulation = simulation
	_update_competition(simulation)

func set_selected_variant(id: String) -> void:
	if selected_variant_id == id: return
	selected_variant_id = id

func set_hovered_variants(ids: PackedStringArray, country_id: String = "") -> void:
	if hovered_variant_ids == ids and hovered_country_id == country_id: return
	hovered_variant_ids = ids.duplicate()
	hovered_country_id = country_id if not ids.is_empty() else ""
	_update_hover_uniforms()
	queue_redraw()

func origin_position(id: String) -> Vector2:
	var world: Dictionary = _simulation.competition.snapshot(_simulation.variants)
	var variant: Dictionary = world.variants_by_id[id]
	return _land_positions(str(variant.meme_id), str(variant.origin_country))[0]

func _active_highlights() -> PackedStringArray:
	return hovered_variant_ids

func hit_at(logical_viewport_point: Vector2, radius: float = 8.0) -> Array[Dictionary]:
	var started := Time.get_ticks_usec()
	_refresh_projection_if_changed()
	_last_hit_candidates = 0
	var matches := {}
	var pointer := _view_transform.affine_inverse() * logical_viewport_point
	var world_radius := radius / _view_transform.x.length()
	var first := _hit_cell(pointer - Vector2.ONE * world_radius)
	var last := _hit_cell(pointer + Vector2.ONE * world_radius)
	var map_inverse := _map_transform.affine_inverse()
	var map_rect := Rect2(Vector2.ZERO, _map_input.size).grow(-6.0)
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for entry: Variant in _hit_grid.get(Vector2i(x, y), []):
				var point: Dictionary = entry if entry is Dictionary else _points[int(entry)]
				if point.has("_sample_key") and int(point._sample_index) >= int(_active_counts.get(str(point._sample_key), 0)): continue
				_last_hit_candidates += 1
				var index: int = int(point.get("_sample_order", 0)) if entry is Dictionary else int(entry)
				var screen := _view_transform * Vector2(point.world_position)
				if not map_rect.has_point(map_inverse * screen): continue
				var distance := logical_viewport_point.distance_to(screen)
				if distance > radius: continue
				var key := str(point.variant_id) + "/" + str(point.country_id)
				if matches.has(key) and float(matches[key].distance) <= distance: continue
				var hit := _current_point(point)
				hit.screen_position = screen
				hit.local_position = _overlay_transform.affine_inverse() * screen
				hit.visible = true
				hit.distance = distance
				hit.draw_order = index
				matches[key] = hit
	var hits: Array[Dictionary] = []
	hits.assign(matches.values())
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.distance), float(b.distance)): return float(a.distance) < float(b.distance)
		return int(a.draw_order) > int(b.draw_order))
	_last_hit_usec = Time.get_ticks_usec() - started
	_max_hit_usec = maxi(_max_hit_usec, _last_hit_usec)
	return hits

func _hit_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / HIT_CELL_SIZE), floori(point.y / HIT_CELL_SIZE))

func _meme_color(meme_id: String, player: bool) -> Color:
	var serial: int = absi(meme_id.hash())
	var suffix: String = meme_id.get_slice("_", meme_id.get_slice_count("_") - 1)
	if suffix.is_valid_int(): serial = maxi(1, int(suffix)) - 1
	var palette: Array = PLAYER_COLORS if player else EXTERNAL_COLORS
	var color: Color = palette[serial % palette.size()]
	return color.lightened(minf(0.24, float((serial / palette.size()) % 7) * 0.035))

func _refresh_world() -> bool:
	if not is_instance_valid(_atlas) or _atlas.get("world") == null:
		return false
	if not is_instance_valid(_world_layer): _world_layer = _atlas.get("world_layer") as Node2D
	if not is_instance_valid(_map_input): _map_input = _atlas.get("map_input") as Control
	var world: AtlasWorldData = _atlas.get("world")
	if world.get_instance_id() == _world_id:
		return false
	_world_id = world.get_instance_id()
	_land_cache.clear()
	_land_random.clear()
	_country_sampling.clear()
	_country_capacities.clear()
	_point_pools.clear()
	_buffer_pools.clear()
	_pool_hit_grid.clear()
	_active_counts.clear()
	_presence_by_key.clear()
	_meme_draw_indices.clear()
	_variant_draw_indices.clear()
	_next_sample_order = 0
	_country_indices.clear()
	var settings: Resource = _atlas.get("settings")
	var countries: Array = settings.get("countries")
	var capacities: Array[Dictionary] = []
	var total_area := 0.0
	for index in mini(countries.size(), world.territories.size()):
		var id := str(countries[index].id)
		_country_indices[id] = index
		total_area += world.territories[index].area
	for id: String in _country_indices:
		var area: float = world.territories[int(_country_indices[id])].area
		capacities.append({"key":id, "wanted":area / total_area * MAX_TOTAL_DOTS})
	var allocations := _budget_counts(capacities, MAX_TOTAL_DOTS, false)
	for index in capacities.size(): _country_capacities[str(capacities[index].key)] = allocations[index]
	return true

func _sampling_mesh(country_id: String) -> Dictionary:
	if _country_sampling.has(country_id): return _country_sampling[country_id]
	var world: AtlasWorldData = _atlas.get("world")
	var territory: TerritoryGeometry = world.territories[int(_country_indices[country_id])]
	var vertices := PackedVector2Array()
	var weights := PackedFloat64Array()
	var total := 0.0
	for outline_index in territory.outlines.size():
		var ring: PackedVector2Array = territory.outlines[outline_index]
		var triangles: PackedInt32Array = territory.triangles[outline_index]
		for index in range(0, triangles.size(), 3):
			var a := ring[triangles[index]]
			var b := ring[triangles[index + 1]]
			var c := ring[triangles[index + 2]]
			var area := absf((b - a).cross(c - a)) * 0.5
			if area == 0.0: continue
			vertices.append_array(PackedVector2Array([a, b, c]))
			total += area
			weights.append(total)
	var mesh := {"vertices":vertices, "weights":weights, "area":total}
	_country_sampling[country_id] = mesh
	return mesh

func _land_positions(meme_id: String, country_id: String, required: int = 1) -> PackedVector2Array:
	var key := meme_id + "/" + country_id
	var result: PackedVector2Array = _land_cache.get(key, PackedVector2Array())
	if result.size() >= required: return result
	var world: AtlasWorldData = _atlas.get("world")
	var territory: TerritoryGeometry = world.territories[int(_country_indices[country_id])]
	var mesh := _sampling_mesh(country_id)
	if not _land_random.has(key):
		var generator := RandomNumberGenerator.new()
		generator.seed = (str(world.seed_value) + "/" + key).hash()
		_land_random[key] = generator
	var random: RandomNumberGenerator = _land_random[key]
	# Triangle areas choose land uniformly; the ownership test excludes enclave holes.
	for index in range(result.size(), required):
		for attempt in SAMPLE_ATTEMPTS:
			var triangle: int = mesh.weights.bsearch(random.randf() * float(mesh.area))
			var a: Vector2 = mesh.vertices[triangle * 3]
			var b: Vector2 = mesh.vertices[triangle * 3 + 1]
			var c: Vector2 = mesh.vertices[triangle * 3 + 2]
			var u := sqrt(random.randf())
			var v := random.randf()
			var candidate := a * (1.0 - u) + b * (u * (1.0 - v)) + c * (u * v)
			if territory.contains(candidate):
				result.append(candidate)
				_sample_points_generated += 1
				break
			_sample_rejections += 1
	_land_cache[key] = result
	return result

func _budget_counts(requests: Array[Dictionary], budget: int, only_reduce: bool = true) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(requests.size())
	var total := 0.0
	for request: Dictionary in requests: total += float(request.wanted)
	if total <= 0.0 or budget <= 0: return counts
	var factor := minf(1.0, float(budget) / total) if only_reduce else float(budget) / total
	var fractions: Array[Dictionary] = []
	var used := 0
	for index in requests.size():
		var exact := float(requests[index].wanted) * factor
		counts[index] = floori(exact)
		used += counts[index]
		fractions.append({"index":index, "fraction":exact - floorf(exact), "key":str(requests[index].key)})
	var target := mini(budget, roundi(total)) if only_reduce else budget
	fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.key) < str(b.key) if is_equal_approx(float(a.fraction), float(b.fraction)) else float(a.fraction) > float(b.fraction))
	for index in target - used: counts[int(fractions[index].index)] += 1
	return counts

func _process(_delta: float) -> void:
	if _refresh_world():
		_state_signature = ""
		if _simulation != null:
			_update_competition(_simulation)
		else:
			_project_points()
	else:
		_refresh_projection_if_changed()

func _refresh_projection_if_changed() -> void:
	if not is_instance_valid(_world_layer) or not is_instance_valid(_map_input): return
	if _view_transform != _world_layer.get_global_transform_with_canvas() or _map_transform != _map_input.get_global_transform_with_canvas() or _overlay_transform != get_global_transform_with_canvas() or _map_rect.size != (_map_input.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _map_input.size)).size: _project_points()

func _project_points() -> void:
	if not is_instance_valid(_world_layer) or not is_instance_valid(_map_input): return
	var started := Time.get_ticks_usec()
	_projection_updates += 1
	_view_transform = _world_layer.get_global_transform_with_canvas()
	_map_transform = _map_input.get_global_transform_with_canvas()
	_overlay_transform = get_global_transform_with_canvas()
	_map_rect = _map_transform * Rect2(Vector2.ZERO, _map_input.size)
	var world_to_map := _map_transform.affine_inverse() * _view_transform
	_point_material.set_shader_parameter("world_to_map_x", Vector3(world_to_map.x.x, world_to_map.y.x, world_to_map.origin.x))
	_point_material.set_shader_parameter("world_to_map_y", Vector3(world_to_map.x.y, world_to_map.y.y, world_to_map.origin.y))
	_point_material.set_shader_parameter("map_size", _map_input.size)
	_point_material.set_shader_parameter("view_scale", _view_transform.x.length())
	_last_projection_usec = Time.get_ticks_usec() - started
	_max_projection_usec = maxi(_max_projection_usec, _last_projection_usec)
	queue_redraw()

func _materialize_screen_points() -> void:
	if _projected_geometry == _geometry_rebuilds and _projected_view == _projection_updates: return
	var started := Time.get_ticks_usec()
	if _projected_geometry != _geometry_rebuilds or _screen_points.size() != _points.size():
		_screen_points.clear()
		for point: Dictionary in _points: _screen_points.append(_current_point(point))
		_projected_geometry = _geometry_rebuilds
	var local_transform := _overlay_transform.affine_inverse()
	var map_inverse := _map_transform.affine_inverse()
	var visible_rect := Rect2(Vector2.ZERO, _map_input.size).grow(-6.0)
	for projected: Dictionary in _screen_points:
		var screen: Vector2 = _view_transform * Vector2(projected.world_position)
		projected.screen_position = screen
		projected.local_position = local_transform * screen
		projected.visible = visible_rect.has_point(map_inverse * screen)
	_projected_view = _projection_updates
	_last_debug_projection_usec = Time.get_ticks_usec() - started

func _update_hover_uniforms() -> void:
	var width := maxi(1, _meme_draw_indices.size())
	var values := PackedByteArray()
	values.resize(width)
	for id: String in hovered_variant_ids:
		if _variant_draw_indices.has(id): values[int(_variant_draw_indices[id])] = 255
	var image := Image.create_from_data(width, 1, false, Image.FORMAT_R8, values)
	if _hover_texture_width != width:
		_hover_texture = ImageTexture.create_from_image(image)
		_hover_texture_width = width
		_point_material.set_shader_parameter("hover_mask", _hover_texture)
	else:
		_hover_texture.update(image)
	_point_material.set_shader_parameter("has_hover", not hovered_variant_ids.is_empty())
	_point_material.set_shader_parameter("hover_country", float(_country_indices.get(hovered_country_id, -1)))

func _current_point(point: Dictionary) -> Dictionary:
	var result := point.duplicate()
	var key := str(point.get("_sample_key", ""))
	if _presence_by_key.has(key):
		var request: Dictionary = _presence_by_key[key]
		result.country_adopted = int(request.adopted)
		result.country_exposed = int(request.exposed)
		result.country_attention = int(request.attention)
		result.local_spread = float(request.spread)
		result.kind = "adoption" if int(request.adopted) > 0 else "presence"
	result.erase("_sample_key")
	result.erase("_sample_index")
	result.erase("_sample_order")
	return result

func _cached_segment(request: Dictionary, offset: int, count: int) -> Dictionary:
	var key := str(request.key)
	var required := offset + count
	var positions := _land_positions(str(request.meme_id), str(request.country_id), required)
	var pool: Array[Dictionary] = _point_pools.get(key, [] as Array[Dictionary])
	var buffer: PackedFloat32Array = _buffer_pools.get(key, PackedFloat32Array())
	for index in range(pool.size(), mini(required, positions.size())):
		var point := _spread_point(request, positions[index], bool(request.origin) and index == 0)
		point._sample_key = key
		point._sample_index = index
		point._sample_order = _next_sample_order
		_next_sample_order += 1
		pool.append(point)
		var cell := _hit_cell(positions[index])
		if not _pool_hit_grid.has(cell): _pool_hit_grid[cell] = []
		_pool_hit_grid[cell].append(point)
		var color: Color = point.color
		buffer.append_array(PackedFloat32Array([1, 0, 0, positions[index].x, 0, 1, 0, positions[index].y,
			color.r, color.g, color.b, color.a, float(_meme_draw_indices[str(point.meme_id)]),
			float(_country_indices[str(point.country_id)]) * 2.0 + (1.0 if bool(point.origin) else 0.0), positions[index].x, positions[index].y]))
	_point_pools[key] = pool
	_buffer_pools[key] = buffer
	var available := maxi(0, mini(count, pool.size() - offset))
	_points.append_array(pool.slice(offset, offset + available))
	_active_counts[key] = maxi(int(_active_counts.get(key, 0)), offset + available)
	return {"key":key, "offset":offset, "count":available}

func _upload_segments(segments: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	var data := PackedFloat32Array()
	for segment: Dictionary in segments:
		var buffer: PackedFloat32Array = _buffer_pools[str(segment.key)]
		data.append_array(buffer.slice(int(segment.offset) * 16, (int(segment.offset) + int(segment.count)) * 16))
	_point_multimesh.instance_count = _points.size()
	_point_multimesh.buffer = data
	_hit_grid = _pool_hit_grid
	var world: AtlasWorldData = _atlas.get("world")
	var bounds := world.bounds.grow(64.0)
	_point_multimesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1), Vector3(bounds.size.x, bounds.size.y, 2))
	_update_hover_uniforms()
	_last_upload_usec = Time.get_ticks_usec() - started

func _upload_points() -> void:
	var started := Time.get_ticks_usec()
	_hit_grid = {}
	for point: Dictionary in _points:
		var meme := str(point.meme_id)
		if not _meme_draw_indices.has(meme): _meme_draw_indices[meme] = _meme_draw_indices.size()
		_variant_draw_indices[str(point.variant_id)] = _meme_draw_indices[meme]
	var data := PackedFloat32Array()
	data.resize(_points.size() * 16)
	for index in _points.size():
		var point: Dictionary = _points[index]
		var position: Vector2 = point.world_position
		var color: Color = point.color
		var offset := index * 16
		data[offset] = 1.0
		data[offset + 3] = position.x
		data[offset + 5] = 1.0
		data[offset + 7] = position.y
		data[offset + 8] = color.r
		data[offset + 9] = color.g
		data[offset + 10] = color.b
		data[offset + 11] = color.a
		data[offset + 12] = float(_meme_draw_indices[str(point.meme_id)])
		data[offset + 13] = float(_country_indices[str(point.country_id)]) * 2.0 + (1.0 if bool(point.origin) else 0.0)
		data[offset + 14] = position.x
		data[offset + 15] = position.y
		var cell := _hit_cell(position)
		if not _hit_grid.has(cell): _hit_grid[cell] = []
		_hit_grid[cell].append(index)
	_point_multimesh.instance_count = _points.size()
	_point_multimesh.buffer = data
	var world: AtlasWorldData = _atlas.get("world")
	var bounds := world.bounds.grow(64.0)
	_point_multimesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1), Vector3(bounds.size.x, bounds.size.y, 2))
	_update_hover_uniforms()
	_last_upload_usec = Time.get_ticks_usec() - started

func _point_highlighted(point: Dictionary) -> bool:
	return str(point.variant_id) in hovered_variant_ids and (hovered_country_id.is_empty() or str(point.country_id) == hovered_country_id)

func _point_opacity(point: Dictionary) -> float:
	return OTHER_HOVER_OPACITY if not hovered_variant_ids.is_empty() and not _point_highlighted(point) else 1.0

func _draw() -> void:
	var started := Time.get_ticks_usec()
	draw_set_transform_matrix(_overlay_transform.affine_inverse() * _view_transform)
	draw_multimesh(_point_multimesh, null)
	_last_draw_usec = Time.get_ticks_usec() - started
	_max_draw_usec = maxi(_max_draw_usec, _last_draw_usec)

func legend_rows() -> Array[Dictionary]:
	return _rows.duplicate(true)

func colors() -> Dictionary:
	return _colors.duplicate()

func inspection() -> Dictionary:
	_refresh_projection_if_changed()
	_materialize_screen_points()
	var countries: Dictionary = {}
	var meme_counts: Dictionary = {}
	var representative: Array[Dictionary] = []
	var filled := 0
	var hollow := 0
	var drawn := 0
	for point in _screen_points:
		var country: String = point.country_id
		if not countries.has(country): countries[country] = {"dot_count":0, "adoption_samples":0, "presence_markers":0}
		countries[country].dot_count += 1
		var kind: String = point.kind
		if kind == "adoption":
			filled += 1
			countries[country].adoption_samples += 1
		else:
			hollow += 1
			countries[country].presence_markers += 1
		if point.visible: drawn += 1
		var meme: String = point.meme_id
		if not meme_counts.has(meme): representative.append(point.duplicate(true))
		meme_counts[meme] = int(meme_counts.get(meme, 0)) + 1
	return {"dot_count":_points.size(), "drawn_dot_count":drawn, "meme_count":meme_counts.size(), "colors":_colors.duplicate(), "countries":countries, "meme_dot_counts":meme_counts, "representative_points":representative, "points":_screen_points.duplicate(true), "adoption_sample_count":filled, "presence_marker_count":hollow, "observed_totals":_metrics.duplicate(), "mode":"world_competition", "metric_explanation":EXPLANATION, "explanation":EXPLANATION, "legend_rows":legend_rows(), "selected_variant_id":selected_variant_id, "hovered_variant_ids":hovered_variant_ids.duplicate(), "hovered_country_id":hovered_country_id, "highlighted_variant_ids":_active_highlights().duplicate(), "highlighted_points":_screen_points.filter(_point_highlighted).duplicate(true), "origin_marker_style":"solid_with_ring", "propagation_marker_style":"solid", "max_per_meme":MAX_TOTAL_DOTS, "max_total":MAX_TOTAL_DOTS, "sampling_attempts_per_point":SAMPLE_ATTEMPTS, "geometry_rebuilds":_geometry_rebuilds, "projection_updates":_projection_updates, "mouse_filter":mouse_filter, "map_rect":_map_rect, "view_transform":_view_transform,
		"density_model":"local_composite_by_land_area", "country_capacities":_country_capacities.duplicate(),
		"emphasis":"hover_only", "base_radius":DOT_RADIUS, "hover_other_opacity":OTHER_HOVER_OPACITY,
		"sample_points_generated":_sample_points_generated, "sample_rejections":_sample_rejections,
		"hit_cell_size":HIT_CELL_SIZE, "hit_grid_space":"world", "render_batch_count":1, "hit_grid_cells":_hit_grid.size(), "last_hit_candidates":_last_hit_candidates,
		"last_hit_usec":_last_hit_usec, "max_hit_usec":_max_hit_usec,
		"last_projection_usec":_last_projection_usec, "max_projection_usec":_max_projection_usec,
		"last_geometry_usec":_last_geometry_usec, "last_upload_usec":_last_upload_usec, "last_debug_projection_usec":_last_debug_projection_usec, "last_draw_usec":_last_draw_usec, "max_draw_usec":_max_draw_usec}


func _update_competition(simulation: MemeDemoSimulation) -> void:
	var started := Time.get_ticks_usec()
	var world: Dictionary = simulation.competition.snapshot(simulation.variants)
	var signature_rows: Array = []
	for row: Dictionary in world.variants: signature_rows.append([row.id, row.meme_id, row.get("meme_name", ""), row.adopted, row.exposed, row.attention])
	var country_signature: Array = []
	for country: Dictionary in world.countries:
		var presence_rows: Array = []
		for presence: Dictionary in country.variants: presence_rows.append([presence.id, presence.adopted, presence.exposed, presence.attention])
		country_signature.append([country.id, country.population, presence_rows])
	var signature := str([world.world_seed, signature_rows, country_signature])
	var world_changed := _refresh_world()
	if signature == _state_signature and not world_changed:
		_refresh_projection_if_changed()
		return
	_state_signature = signature
	var selected_meme := ""
	for previous: Dictionary in _rows:
		if str(previous.id) == selected_variant_id:
			selected_meme = str(previous.meme_id)
			break
	if not world.variants_by_id.has(selected_variant_id):
		selected_variant_id = ""
		for current: Dictionary in world.variants:
			if str(current.meme_id) == selected_meme:
				selected_variant_id = str(current.id)
				break
	_rows.clear()
	_colors.clear()
	_points.clear()
	_metrics = {"owned":float(world.owned_adopted),"external":float(world.adopted)-float(world.owned_adopted),"adopted":float(world.adopted)}
	var raw_by_id := {}
	for raw: Dictionary in simulation.competition.active_variants(simulation.variants): raw_by_id[str(raw.id)] = raw
	var requests: Array[Dictionary] = []
	var requests_by_key := {}
	for country: Dictionary in world.countries:
		var cid := str(country.id)
		if not _country_indices.has(cid): continue
		var budget := floori(int(country.population) * simulation.catalog.gameplay_rules.attention_fraction)
		for presence: Dictionary in country.variants:
			var id := str(presence.id)
			var variant: Dictionary = world.variants_by_id[id]
			var spread := MonitorMetrics.spread(presence, int(country.population), budget)
			var origin := cid == str(variant.origin_country)
			var wanted := maxi(0, ceili(float(_country_capacities[cid]) * spread) - (1 if origin else 0))
			var key := str(variant.meme_id) + "/" + cid
			var request := {"key":key,"id":id,"meme_id":str(variant.meme_id),"country_id":cid,
				"wanted":wanted,"spread":spread,"origin":origin,"adopted":int(presence.adopted),
				"exposed":int(presence.exposed),"attention":int(presence.attention),
				"color":_meme_color(str(variant.meme_id),bool(variant.owned)),"owned":bool(variant.owned)}
			requests_by_key[key] = request
			if wanted > 0: requests.append(request)
	_presence_by_key = requests_by_key
	_active_counts.clear()
	_variant_draw_indices.clear()
	for variant: Dictionary in world.variants:
		var meme := str(variant.meme_id)
		if not _meme_draw_indices.has(meme): _meme_draw_indices[meme] = _meme_draw_indices.size()
		_variant_draw_indices[str(variant.id)] = _meme_draw_indices[meme]
	var segments: Array[Dictionary] = []
	# Every origin survives allocation and remains separate from spread density.
	for variant: Dictionary in world.variants:
		var cid := str(variant.origin_country)
		if not _country_indices.has(cid) or _points.size() >= MAX_TOTAL_DOTS: continue
		var key := str(variant.meme_id) + "/" + cid
		segments.append(_cached_segment(requests_by_key[key], 0, 1))
	var allocations := _budget_counts(requests, MAX_TOTAL_DOTS - _points.size())
	for index in requests.size():
		var request: Dictionary = requests[index]
		var count := allocations[index]
		if count == 0: continue
		var offset := 1 if bool(request.origin) else 0
		segments.append(_cached_segment(request, offset, count))
	for variant: Dictionary in world.variants:
		var id := str(variant.id)
		var meme := str(variant.meme_id)
		var color := _meme_color(meme,bool(variant.owned))
		_colors[meme] = color.to_html(false)
		var countries := PackedStringArray()
		for country: Dictionary in world.countries:
			var key := meme + "/" + str(country.id)
			if requests_by_key.has(key) and float(requests_by_key[key].spread) > 0.0: countries.append(str(country.id))
		var row := variant.duplicate(true)
		row.title = Identity.name(simulation.catalog, raw_by_id[id])
		row.merge({"color":color,"country_ids":countries,"kind":"spread","scope":"country_composite_sample","tooltip":""})
		_rows.append(row)
	_geometry_rebuilds += 1
	_upload_segments(segments)
	_project_points()
	_last_geometry_usec = Time.get_ticks_usec() - started

func _spread_point(request: Dictionary, position: Vector2, origin: bool) -> Dictionary:
	return {"meme_id":str(request.meme_id),"variant_id":str(request.id),"country_id":str(request.country_id),
		"world_position":position,"color":request.color,"kind":"adoption" if int(request.adopted)>0 else "presence",
		"origin":origin,"scope":"origin_country" if origin else "country_composite_sample",
		"pool":"owned" if bool(request.owned) else "external","adoption_count_known":true,
		"country_adopted":int(request.adopted),"country_exposed":int(request.exposed),
		"country_attention":int(request.attention),"local_spread":float(request.spread)}
