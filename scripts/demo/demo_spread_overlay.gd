extends Control

const MAX_FAMILY_DOTS := 80
const MAX_TOTAL_DOTS := 640
const ADOPTIONS_PER_DOT := 12.0
const SAMPLE_ATTEMPTS := 24
const EXPLANATION := "抽样传播点，不代表个人/国家真实人口。实心根据已记录的玩家归属／来源链采用总量抽样，逐家族分配只是可视化代理；空心只表示投放或本轮出现，不是采用。独立环境模因沿首次投放国定位本轮事件，不代表其出生国家；未模拟跨国扩散。"
const PLAYER_COLORS := [Color("ad4438"), Color("bc852c")]
const EXTERNAL_COLORS := [Color("326f91"), Color("438476"), Color("756095"), Color("3e8c96"), Color("7d7841"), Color("53699d"), Color("578950"), Color("955c83")]

var _world_mode := false
var _atlas: Node2D
var _world_layer: Node2D
var _map_input: Control
var _world_id: int = 0
var _country_indices: Dictionary = {}
var _land_cache: Dictionary = {}
var _birth_metrics: Dictionary = {}
var _families: Array[Dictionary] = []
var _points: Array[Dictionary] = []
var _screen_points: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _colors: Dictionary = {}
var _metrics := {"owned":0.0, "external":0.0, "adopted":0.0}
var _state_signature: String = ""
var _simulation_id: int = 0
var _run_seed: int = 0
var _last_hour: int = 0
var _last_publish_count: int = 0
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
	if _world_id != 0:
		_rebuild_points()
	else:
		_project_points()

func update_simulation(simulation: MemeDemoSimulation) -> void:
	if simulation == null:
		return
	_world_mode = simulation.gameplay_mode() == "world_competition"
	if _world_mode:
		_update_competition(simulation)
		return
	if _simulation_id != simulation.get_instance_id() or _run_seed != simulation.seed_value or simulation.hour < _last_hour or simulation.publish_count < _last_publish_count or simulation.families.is_empty():
		_birth_metrics.clear()
		_state_signature = ""
	_simulation_id = simulation.get_instance_id()
	_run_seed = simulation.seed_value
	_last_hour = simulation.hour
	_last_publish_count = simulation.publish_count
	_metrics = {"owned":0.0, "external":0.0, "adopted":0.0}
	for group: Dictionary in simulation.group_state.values():
		_metrics.owned += maxf(0.0, float(group.get("owned", 0.0)))
		_metrics.external += maxf(0.0, float(group.get("external", 0.0)))
	_metrics.adopted = _metrics.owned + _metrics.external
	var variants: Dictionary = {}
	var event_hours: Dictionary = {}
	for variant in simulation.variants: variants[str(variant.id)] = variant
	for event in simulation.events: event_hours[str(event.instance_id)] = int(event.hour)
	var grouped: Dictionary = {}
	_rows.clear()
	for variant in simulation.variants:
		var family_id := str(variant.family_id)
		if not grouped.has(family_id): grouped[family_id] = []
		grouped[family_id].append(variant)
	var family_ids: Array = grouped.keys()
	family_ids.sort()
	_families.clear()
	_colors.clear()
	for family_id: String in family_ids:
		var members: Array = grouped[family_id]
		var countries := PackedStringArray()
		var has_controlled := false
		var has_lineage := false
		var birth_hour := simulation.hour
		for variant: Dictionary in members:
			has_controlled = has_controlled or (bool(variant.get("controlled", false)) and str(variant.get("creator", "")) == "player")
			has_lineage = has_lineage or not variant.get("origin_ids", []).is_empty()
			for country in _linked_countries(str(variant.id), variants, simulation.deployments):
				if not countries.has(country): countries.append(country)
			for deployment in simulation.deployments:
				if str(deployment.variant_id) == str(variant.id): birth_hour = mini(birth_hour, int(deployment.hour))
			if event_hours.has(str(variant.get("source_event", ""))): birth_hour = mini(birth_hour, int(event_hours[str(variant.source_event)]))
		var presence_scope := "deployment" if has_controlled else "inherited_deployment"
		if countries.is_empty() and not has_lineage:
			presence_scope = "run_event_presence"
			if not simulation.deployments.is_empty(): countries.append(str(simulation.deployments[0].country_id))
		var pool := "owned" if has_controlled else ("external" if has_lineage else "presence_only")
		var metric: float = float(_metrics.get(pool, 0.0))
		if not _birth_metrics.has(family_id):
			_birth_metrics[family_id] = metric if birth_hour >= simulation.hour else 0.0
		var growth: float = maxf(0.0, metric - float(_birth_metrics[family_id]))
		var color := _family_color(family_id, has_controlled)
		_colors[family_id] = color.to_html(false)
		_families.append({"family_id":family_id, "countries":countries, "pool":pool, "growth":growth, "color":color, "presence_scope":presence_scope, "variant_id":str(members[0].id), "birth_hour":birth_hour})
		for variant: Dictionary in members:
			if not bool(variant.get("controlled", false)) or str(variant.get("creator", "")) != "player": continue
			var title := str(variant.text).left(48)
			var preset := simulation.catalog.find_preset(str(variant.get("preset_id", ""))) if simulation.catalog != null else null
			if preset != null: title = preset.title
			_rows.append({"id":str(variant.id), "title":title, "color":color, "family_id":family_id, "country_ids":countries.duplicate(), "controlled":true, "kind":"presence", "scope":"deployment", "tooltip":EXPLANATION})
	var signature := JSON.stringify({"families":_families, "metrics":_metrics})
	var world_changed := _refresh_world()
	if signature != _state_signature or world_changed:
		_state_signature = signature
		_rebuild_points()
	else:
		_refresh_projection_if_changed()

func _linked_countries(id: String, variants: Dictionary, deployments: Array[Dictionary]) -> PackedStringArray:
	var result := PackedStringArray()
	var pending := PackedStringArray([id])
	var seen: Dictionary = {}
	var visits := 0
	while not pending.is_empty() and visits < 256:
		var current: String = pending[0]
		pending.remove_at(0)
		if seen.has(current): continue
		seen[current] = true
		visits += 1
		for deployment in deployments:
			if str(deployment.variant_id) == current and not result.has(str(deployment.country_id)):
				result.append(str(deployment.country_id))
		if not variants.has(current): continue
		var variant: Dictionary = variants[current]
		for parent in variant.get("parent_ids", []) + variant.get("origin_ids", []): pending.append(str(parent))
	return result

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

func _rebuild_points() -> void:
	_geometry_rebuilds += 1
	_points.clear()
	var visible_families: Array[Dictionary] = []
	for family in _families:
		var countries := PackedStringArray()
		for country in family.countries:
			if _country_indices.has(country): countries.append(country)
		if countries.is_empty() or visible_families.size() >= MAX_TOTAL_DOTS: continue
		var visible := family.duplicate()
		visible.countries = countries
		visible_families.append(visible)
	var remaining := MAX_TOTAL_DOTS - visible_families.size()
	var allocations: Dictionary = {}
	for pool in ["owned", "external"]:
		var eligible: Array[Dictionary] = []
		var total_growth: float = 0.0
		for family in visible_families:
			if str(family.pool) == pool and float(family.growth) > 0.0:
				eligible.append(family)
				total_growth += float(family.growth)
		var budget := mini(remaining, mini(ceili(float(_metrics[pool]) / ADOPTIONS_PER_DOT), eligible.size() * (MAX_FAMILY_DOTS - 1)))
		if total_growth <= 0.0: continue
		for slot in budget:
			var chosen := ""
			var highest := -INF
			for family in eligible:
				var id: String = family.family_id
				var assigned := int(allocations.get(id, 0))
				if assigned >= MAX_FAMILY_DOTS - 1: continue
				var score: float = budget * float(family.growth) / total_growth - assigned
				if score > highest:
					highest = score
					chosen = id
			if chosen.is_empty(): break
			allocations[chosen] = int(allocations.get(chosen, 0)) + 1
			remaining -= 1
	for family in visible_families:
		var count := 1 + int(allocations.get(str(family.family_id), 0))
		for index in count:
			if _points.size() >= MAX_TOTAL_DOTS: break
			var country: String = family.countries[index % family.countries.size()]
			var point_index: int = index / int(family.countries.size())
			var positions := _land_positions(str(family.family_id), country)
			if point_index >= positions.size(): continue
			_points.append({"family_id":str(family.family_id), "variant_id":str(family.variant_id), "country_id":country, "world_position":positions[point_index], "color":family.color, "kind":"presence" if index == 0 else "adoption", "scope":str(family.presence_scope) if index == 0 else "aggregate_adoption_proxy", "pool":str(family.pool), "adoption_count_known":false})
	_project_points()

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
		_rebuild_points()
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
		row.scope = ("country_adoption_sample" if _world_mode else "aggregate_adoption_proxy") if row.kind == "adoption" else "deployment"
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
	return {"dot_count":_points.size(), "drawn_dot_count":drawn, "family_count":family_counts.size(), "colors":_colors.duplicate(), "countries":countries, "family_dot_counts":family_counts, "representative_points":representative, "points":_screen_points.duplicate(true), "adoption_sample_count":filled, "presence_marker_count":hollow, "observed_totals":_metrics.duplicate(), "mode":"world_competition" if _world_mode else "legacy_sample", "metric_explanation":_explanation(), "explanation":_explanation(), "legend_rows":legend_rows(), "max_per_family":MAX_FAMILY_DOTS, "max_total":MAX_TOTAL_DOTS, "sampling_attempts_per_point":SAMPLE_ATTEMPTS, "geometry_rebuilds":_geometry_rebuilds, "projection_updates":_projection_updates, "mouse_filter":mouse_filter, "map_rect":_map_rect, "view_transform":_view_transform}


func _explanation() -> String:
	return "实心点按各国已采用人数抽样；空心是出生或投放位置。颜色区分模因家族。" if _world_mode else EXPLANATION

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
