## 只呈现世界竞争模型：按各国采用人数抽样，空心标记表示出生或投放位置。
extends Control

const MAX_FAMILY_DOTS := 80
const MAX_TOTAL_DOTS := 640
const SAMPLE_ATTEMPTS := 24
const EXPLANATION := "实心点按各国已采用人数抽样；空心是出生或投放位置。颜色区分模因家族。"
const PLAYER_COLORS := [Color("ad4438"), Color("bc852c")]
const EXTERNAL_COLORS := [Color("326f91"), Color("438476"), Color("756095"), Color("3e8c96"), Color("7d7841"), Color("53699d"), Color("578950"), Color("955c83")]

var _simulation: MemeDemoSimulation
var _atlas: Node2D
var _world_layer: Node2D
var _map_input: Control
var _world_id: int = 0
var _country_indices: Dictionary = {}
var _land_cache: Dictionary = {}
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
	_project_points()

func update_simulation(simulation: MemeDemoSimulation) -> void:
	if simulation == null:
		return
	if _simulation != simulation:
		_state_signature = ""
	_simulation = simulation
	_update_competition(simulation)

func _family_color(family_id: String, player: bool) -> Color:
	var serial: int = absi(family_id.hash())
	var suffix: String = family_id.get_slice("_", family_id.get_slice_count("_") - 1)
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
	_country_indices.clear()
	var settings: Resource = _atlas.get("settings")
	var countries: Array = settings.get("countries")
	for index in mini(countries.size(), world.territories.size()):
		_country_indices[str(countries[index].id)] = index
	return true

func _land_positions(family_id: String, country_id: String) -> PackedVector2Array:
	var key := family_id + "/" + country_id
	if _land_cache.has(key): return _land_cache[key]
	var result := PackedVector2Array()
	var world: AtlasWorldData = _atlas.get("world")
	var territory: TerritoryGeometry = world.territories[int(_country_indices[country_id])]
	var boxes: Array[Rect2] = territory.outline_bounds
	if boxes.is_empty(): boxes = [territory.bounds()]
	var random := RandomNumberGenerator.new()
	random.seed = (str(world.seed_value) + "/" + key).hash()
	for index in MAX_FAMILY_DOTS:
		var accepted := false
		for attempt in SAMPLE_ATTEMPTS:
			var box: Rect2 = boxes[random.randi_range(0, boxes.size() - 1)]
			var candidate := box.position + Vector2(random.randf() * box.size.x, random.randf() * box.size.y)
			if territory.contains(candidate):
				result.append(candidate)
				accepted = true
				break
		if not accepted and territory.contains(territory.anchor): result.append(territory.anchor)
	_land_cache[key] = result
	return result

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
	_projection_updates += 1
	_view_transform = _world_layer.get_global_transform_with_canvas()
	_map_transform = _map_input.get_global_transform_with_canvas()
	_overlay_transform = get_global_transform_with_canvas()
	_map_rect = _map_transform * Rect2(Vector2.ZERO, _map_input.size)
	_screen_points.clear()
	var local_transform := _overlay_transform.affine_inverse()
	var map_inverse := _map_transform.affine_inverse()
	for point in _points:
		var projected := point.duplicate()
		var screen: Vector2 = _view_transform * Vector2(point.world_position)
		projected.screen_position = screen
		projected.local_position = local_transform * screen
		projected.visible = Rect2(Vector2.ZERO, _map_input.size).grow(-6.0).has_point(map_inverse * screen)
		_screen_points.append(projected)
	queue_redraw()

func _draw() -> void:
	for point in _screen_points:
		if not bool(point.visible): continue
		var position: Vector2 = point.local_position
		var color: Color = point.color
		if str(point.kind) == "presence":
			draw_arc(position, 4.7, 0.0, TAU, 18, color, 1.8, true)
		else:
			draw_circle(position, 3.4, Color("f3eddd"), true, -1.0, true)
			draw_circle(position, 2.6, color, true, -1.0, true)

func legend_rows() -> Array[Dictionary]:
	var filled_families: Dictionary = {}
	for point in _points:
		if str(point.kind) == "adoption": filled_families[str(point.family_id)] = true
	for row in _rows:
		row.kind = "adoption" if filled_families.has(str(row.family_id)) else "presence"
		row.scope = "country_adoption_sample" if row.kind == "adoption" else "deployment"
	return _rows.duplicate(true)

func inspection() -> Dictionary:
	_refresh_projection_if_changed()
	var countries: Dictionary = {}
	var family_counts: Dictionary = {}
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
		var family: String = point.family_id
		if not family_counts.has(family): representative.append(point.duplicate(true))
		family_counts[family] = int(family_counts.get(family, 0)) + 1
	return {"dot_count":_points.size(), "drawn_dot_count":drawn, "family_count":family_counts.size(), "colors":_colors.duplicate(), "countries":countries, "family_dot_counts":family_counts, "representative_points":representative, "points":_screen_points.duplicate(true), "adoption_sample_count":filled, "presence_marker_count":hollow, "observed_totals":_metrics.duplicate(), "mode":"world_competition", "metric_explanation":EXPLANATION, "explanation":EXPLANATION, "legend_rows":legend_rows(), "max_per_family":MAX_FAMILY_DOTS, "max_total":MAX_TOTAL_DOTS, "sampling_attempts_per_point":SAMPLE_ATTEMPTS, "geometry_rebuilds":_geometry_rebuilds, "projection_updates":_projection_updates, "mouse_filter":mouse_filter, "map_rect":_map_rect, "view_transform":_view_transform}


func _update_competition(simulation: MemeDemoSimulation) -> void:
	var world: Dictionary = simulation.competition.snapshot(simulation.variants)
	var signature := str(simulation.seed_value) + "/" + str(simulation.hour) + "/" + str(simulation.variants.size()) + "/" + str(simulation.publish_count)
	var world_changed := _refresh_world()
	if signature == _state_signature and not world_changed:
		_refresh_projection_if_changed()
		return
	_state_signature = signature
	_rows.clear()
	_colors.clear()
	_points.clear()
	_metrics = {"owned":float(world.owned_adopted),"external":float(world.adopted)-float(world.owned_adopted),"adopted":float(world.adopted)}
	var population: float = maxf(1.0,float(world.world_population))
	var variants: Array = world.variants
	var units: float = population / float(MAX_TOTAL_DOTS)
	for variant: Dictionary in variants:
		var id := str(variant.id)
		var family := str(variant.family_id)
		var controlled: bool = bool(variant.controlled) and str(variant.creator) == "player"
		var color := _family_color(family,bool(variant.owned))
		_colors[family] = color.to_html(false)
		var countries := PackedStringArray()
		for country: Dictionary in world.countries:
			var cid := str(country.id)
			var adopted := 0
			for presence: Dictionary in country.variants:
				if str(presence.id) == id: adopted = int(presence.adopted); break
			if adopted <= 0 or not _country_indices.has(cid): continue
			countries.append(cid)
			var positions := _land_positions(family,cid)
			var count := mini(positions.size(),maxi(1,ceili(adopted/units)))
			for index in count:
				if _points.size() >= MAX_TOTAL_DOTS: break
				_points.append({"family_id":family,"variant_id":id,"country_id":cid,"world_position":positions[index],"color":color,"kind":"adoption","scope":"country_adoption_sample","pool":"owned" if variant.owned else "external","adoption_count_known":true,"country_adopted":adopted})
		if countries.is_empty() and _country_indices.has(str(variant.origin_country)) and _points.size() < MAX_TOTAL_DOTS:
			var cid := str(variant.origin_country)
			var positions := _land_positions(family,cid)
			if not positions.is_empty(): _points.append({"family_id":family,"variant_id":id,"country_id":cid,"world_position":positions[0],"color":color,"kind":"presence","scope":"origin_country","pool":"owned" if variant.owned else "external","adoption_count_known":true,"country_adopted":0})
		if controlled: _rows.append({"id":id,"title":str(variant.title).left(48),"color":color,"family_id":family,"country_ids":countries,"controlled":true,"kind":"adoption" if int(variant.adopted)>0 else "presence","scope":"country_adoption_sample","tooltip":""})
	_geometry_rebuilds += 1
	_project_points()
