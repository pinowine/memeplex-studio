class_name AtlasMapGenerator
extends RefCounted

var _rng := RandomNumberGenerator.new()
var _settings: AtlasMapSettings
var _world: AtlasWorldData
var _weights: PackedFloat64Array
var _raw: Array[Array] = []
var _junctions := PackedVector2Array()
var _coast_noise: FastNoiseLite
var _boundary_noises: Array[FastNoiseLite] = []

func generate(settings: AtlasMapSettings, seed_value: int) -> AtlasWorldData:
	_settings = settings
	_rng.seed = seed_value
	_world = AtlasWorldData.new()
	_world.seed_value = seed_value
	_world.bounds = Rect2(Vector2.ZERO, settings.world_size)
	_raw.clear()
	_junctions.clear()
	_coast_noise = TerrainField.perlin(seed_value, 1.8, 6)
	_boundary_noises = [TerrainField.perlin(seed_value ^ 73471, settings.macro_boundary_frequency, 2), TerrainField.perlin(seed_value ^ 31991, settings.middle_boundary_frequency, 3), TerrainField.perlin(seed_value ^ 91813, settings.detail_boundary_frequency, 2)]
	_make_weights()
	_make_groups()
	var continents := _make_continents()
	for group in _world.groups.size():
		_partition(continents[group], _world.groups[group])
	_build_shared_geometry()
	_frame_geography()
	for territory in _world.territories:
		territory.cache_bounds()
		_measure(territory)
	_make_enclaves()
	_world.terrain = TerrainField.new()
	_world.terrain.generate(_world, _settings)
	for territory in _world.territories:
		_place_settlements(territory)
	return _world

func _make_weights() -> void:
	var ranked: Array[int] = []
	var varied: Array[float] = []
	_weights.resize(_settings.countries.size())
	for i in _settings.countries.size():
		ranked.append(i)
		var weight := pow(_settings.countries[i].reference_area_km2 / 1000000.0, _settings.area_exponent)
		varied.append(weight * _rng.randf_range(1.0 - _settings.area_jitter, 1.0 + _settings.area_jitter))
		_world.territories.append(TerritoryGeometry.new())
		_raw.append([])
	# Assign ordered jittered weights back to the original area ranking.
	ranked.sort_custom(func(a: int, b: int) -> bool: return _settings.countries[a].reference_area_km2 < _settings.countries[b].reference_area_km2)
	varied.sort()
	for i in ranked.size():
		_weights[ranked[i]] = varied[i]
		_world.territories[ranked[i]].target_weight = varied[i]

func _make_groups() -> void:
	var ranked: Array[int] = []
	for i in _settings.countries.size(): ranked.append(i)
	ranked.sort_custom(func(a: int,b: int) -> bool: return _weights[a] > _weights[b])
	var order := PackedInt32Array(ranked.slice(3))
	for i in range(order.size()-1,0,-1):
		var j := _rng.randi_range(0,i)
		var temporary := order[i]
		order[i] = order[j]
		order[j] = temporary
	# A dominant continental system, a secondary landmass, and one or two island states.
	var count := _rng.randi_range(_settings.minimum_groups, _settings.maximum_groups)
	var island := PackedInt32Array([order[order.size() - 1]])
	order.resize(order.size() - 1)
	var other_island := PackedInt32Array()
	if count == 4:
		other_island.append(order[order.size() - 1])
		order.resize(order.size() - 1)
	var main := PackedInt32Array(ranked.slice(0,3))
	var total_weight: float = 0.0
	for weight in _weights: total_weight += weight
	var main_weight: float = 0.0
	for country in main: main_weight += _weights[country]
	# Random members extend the main continent to a majority of the weighted land.
	while main_weight < total_weight * 0.56:
		main.append(order[0])
		main_weight += _weights[order[0]]
		order.remove_at(0)
	_world.groups.append(island)
	_world.groups.append(main)
	_world.groups.append(order)
	if count == 4: _world.groups.append(other_island)
	for group in _world.groups.size():
		var countries := _world.groups[group]
		for i in range(countries.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var temporary := countries[i]
			countries[i] = countries[j]
			countries[j] = temporary
		_world.groups[group] = countries
		for country in _world.groups[group]:
			_world.territories[country].group = group

func _make_continents() -> Array[Array]:
	var shapes: Array[Array] = []
	var box_weights := PackedFloat64Array()
	for group in _world.groups:
		var parts := _continental_outline()
		var weight: float = 0.0
		for country in group: weight += _weights[country]
		shapes.append(parts)
		box_weights.append(weight / _area_sum(parts))
	var frame := Rect2(Vector2.ONE * 36.0, _settings.world_size - Vector2.ONE * 72.0)
	var gap: float = 28.0
	var island_aspect := _rng.randf_range(1.35, 1.85)
	var low: float = 0.0
	var high := frame.size.x * frame.size.y / box_weights[2]
	# Pack independent coast shapes; solve the available space, not a land percentage.
	for iteration in 32:
		var scale_area := (low + high) * 0.5
		var west_width := scale_area * box_weights[2] / frame.size.y
		var east_width := frame.size.x - gap - west_width
		var island_height := sqrt(scale_area * box_weights[0] / island_aspect)
		var island_width := island_height * island_aspect
		if shapes.size() == 4:
			var other_height := sqrt(scale_area * box_weights[3] / island_aspect)
			island_height = maxf(island_height, other_height)
			island_width += other_height * island_aspect + gap
		var fits := east_width > 0.0 and island_width <= east_width
		if fits:
			fits = scale_area * box_weights[1] / east_width + gap + island_height <= frame.size.y
		if fits: low = scale_area
		else: high = scale_area
	var west_width := low * box_weights[2] / frame.size.y
	var east_width := frame.size.x - gap - west_width
	var main_height := low * box_weights[1] / east_width
	var boxes: Array[Rect2] = []
	boxes.resize(shapes.size())
	boxes[2] = Rect2(frame.position, Vector2(west_width, frame.size.y))
	boxes[1] = Rect2(frame.position + Vector2(west_width + gap, 0), Vector2(east_width, main_height))
	var row_x := boxes[1].end.x
	for group in ([0, 3] if shapes.size() == 4 else [0]):
		var height := sqrt(low * box_weights[group] / island_aspect)
		var size := Vector2(height * island_aspect, height)
		row_x -= size.x
		boxes[group] = Rect2(Vector2(row_x, frame.end.y - size.y), size)
		row_x -= gap
	var flip_x := _rng.randf() < 0.5
	var flip_y := _rng.randf() < 0.5
	for group in shapes.size():
		for ring: PackedVector2Array in shapes[group]:
			for i in ring.size():
				ring[i] = boxes[group].position + ring[i] * boxes[group].size
				if flip_x: ring[i].x = _settings.world_size.x - ring[i].x
				if flip_y: ring[i].y = _settings.world_size.y - ring[i].y
	return shapes

func _continental_outline() -> Array:
	var phase := _rng.randf() * TAU
	var bays: Array[Vector3] = []
	var capes: Array[Vector3] = []
	for i in _rng.randi_range(2, 4):
		bays.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.16, 0.34), _rng.randf_range(0.42, 0.72)))
	for i in _rng.randi_range(2, 4):
		capes.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.12, 0.28), _rng.randf_range(0.18, 0.36)))
	for i in _rng.randi_range(3, 7):
		bays.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.012, 0.038), _rng.randf_range(0.08, 0.22)))
	var ring := PackedVector2Array()
	for i in _settings.coast_samples:
		var angle := TAU * i / float(_settings.coast_samples)
		var direction := Vector2.from_angle(angle)
		var macro_shape := 0.11 * sin(2.0 * angle + phase) + 0.07 * cos(3.0 * angle - phase) + 0.035 * sin(5.0 * angle + 2.0 * phase)
		var middle_shape: float = 0.0
		for bay in bays:
			middle_shape -= bay.z * exp(-pow(wrapf(angle - bay.x, -PI, PI) / bay.y, 2.0))
		for cape in capes:
			middle_shape += cape.z * exp(-pow(wrapf(angle - cape.x, -PI, PI) / cape.y, 2.0))
		middle_shape += 0.16 * _coast_noise.get_noise_2dv(direction * 2.3 + Vector2.ONE * phase)
		var detail_shape := 0.028 * _coast_noise.get_noise_2dv(direction * 19.0 + Vector2.ONE * phase)
		var point := direction * exp(macro_shape + middle_shape * _settings.continental_middle_amplitude + detail_shape * _settings.continental_detail_amplitude)
		point.x += 0.15 * sin(point.y * 2.4 + phase)
		ring.append(point)
	var box := _bounds(ring)
	for i in ring.size(): ring[i] = (ring[i] - box.position) / box.size
	var parts: Array = [ring]
	# Small shelf islands occupy existing bays and corner seas without expanding the footprint.
	for center in [Vector2(0.13, 0.13), Vector2(0.87, 0.13), Vector2(0.13, 0.87), Vector2(0.87, 0.87)]:
		if Geometry2D.is_point_in_polygon(center, ring): continue
		var distance: float = INF
		for i in ring.size():
			distance = minf(distance, center.distance_to(Geometry2D.get_closest_point_to_segment(center, ring[i], ring[(i + 1) % ring.size()])))
		var radius := minf(distance * 0.28, 0.038)
		if radius >= 0.012:
			parts.append(_organic_ring(center, radius, 64, phase + center.x * 19.0))
	return parts

func _organic_ring(center: Vector2, radius: float, samples: int, offset: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in samples:
		var direction := Vector2.from_angle(TAU * i / float(samples))
		ring.append(center + direction * radius * (1.0 + 0.25 * _coast_noise.get_noise_2dv(direction + Vector2.ONE * offset)))
	return ring

func _partition(polygons: Array, countries: PackedInt32Array) -> void:
	if countries.size() == 1:
		_raw[countries[0]] = polygons
		return
	var split := ceili(countries.size() * 0.5)
	var left := countries.slice(0, split)
	var right := countries.slice(split)
	var total: float = 0.0
	var target: float = 0.0
	for country in countries:
		total += _weights[country]
	for country in left:
		target += _weights[country]
	target = target / total * _area_sum(polygons)
	var bounds := _bounds(polygons[0])
	for polygon: PackedVector2Array in polygons:
		bounds = bounds.merge(_bounds(polygon))
	# Divide the longer dimension so repeated cuts do not create narrow country ribbons.
	var angle := (0.0 if bounds.size.x > bounds.size.y else PI * 0.5) + _rng.randf_range(-0.55, 0.55)
	var fraction := target / _area_sum(polygons)
	if minf(fraction, 1.0 - fraction) < 0.20:
		angle = PI * 0.25 + _rng.randf_range(-0.22, 0.22)
	var normal := Vector2.from_angle(angle)
	var low: float = INF
	var high: float = -INF
	for polygon: PackedVector2Array in polygons:
		for point in polygon:
			low = minf(low, point.dot(normal))
			high = maxf(high, point.dot(normal))
	var profile := _partition_profile(bounds, normal)
	var amplitude: float = profile.amplitude
	low -= amplitude
	high += amplitude
	for iteration in 23:
		var midpoint := (low + high) * 0.5
		if _area_sum(_clip(polygons, profile, midpoint, true)) < target:
			low = midpoint
		else:
			high = midpoint
	var cut := (low + high) * 0.5
	var curve := _cut_curve(profile, cut)
	# Register every true curve intersection so recursive cuts share their junctions.
	for polygon: PackedVector2Array in polygons:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var ta: float = (a.dot(profile.tangent) - profile.start) / profile.step
			var tb: float = (b.dot(profile.tangent) - profile.start) / profile.step
			for j in range(maxi(0, floori(minf(ta, tb))), mini(curve.size() - 1, ceili(maxf(ta, tb)) + 1)):
				var crossing: Variant = Geometry2D.segment_intersects_segment(a, b, curve[j], curve[j + 1])
				if crossing != null: _junctions.append(_snap(crossing))
	_partition(_clip(polygons, profile, cut, true), left)
	_partition(_clip(polygons, profile, cut, false), right)

func _partition_profile(bounds: Rect2, normal: Vector2) -> Dictionary:
	var tangent := normal.orthogonal()
	var low: float = INF
	var high: float = -INF
	for point in [bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]:
		low = minf(low, point.dot(tangent))
		high = maxf(high, point.dot(tangent))
	low -= 4.0
	high += 4.0
	var length := high - low
	var size := minf(bounds.size.x, bounds.size.y)
	var samples := ceili(length / 2.0)
	var phases := Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	var regional := TerrainField.perlin(_rng.randi(), 5.0, 2)
	var detail := TerrainField.perlin(_rng.randi(), 29.0, 2)
	var offsets := PackedFloat32Array()
	var amplitude: float = 0.0
	# The partition itself meanders at three scales, before the shared geographic warp.
	for i in samples + 1:
		var t := float(i) / samples
		var broad := size * _settings.partition_macro_amplitude * sin(t * TAU * 1.3 + phases.x)
		var middle := size * _settings.partition_middle_amplitude * regional.get_noise_2d(t, phases.y)
		var fine := size * _settings.partition_detail_amplitude * detail.get_noise_2d(t, phases.z)
		var offset := broad + middle + fine
		offsets.append(offset)
		amplitude = maxf(amplitude, absf(offset))
	return {"normal":normal, "tangent":tangent, "start":low, "step":length / samples, "offsets":offsets, "amplitude":amplitude}

func _cut_curve(profile: Dictionary, cut: float) -> PackedVector2Array:
	var curve := PackedVector2Array()
	for i in profile.offsets.size():
		curve.append(profile.normal * (cut + profile.offsets[i]) + profile.tangent * (profile.start + i * profile.step))
	return curve

func _clip(polygons: Array, profile: Dictionary, cut: float, lower: bool) -> Array:
	var half := _cut_curve(profile, cut)
	var inward: Vector2 = profile.normal * (-10000.0 if lower else 10000.0)
	half.append(half[-1] + inward)
	half.append(half[0] + inward)
	var result: Array = []
	for polygon: PackedVector2Array in polygons:
		result.append_array(Geometry2D.intersect_polygons(polygon, half))
	return result

func _build_shared_geometry() -> void:
	var edge_ids: Dictionary = {}
	for country in _raw.size():
		for polygon: PackedVector2Array in _raw[country]:
			if polygon_area(polygon) < 0.001:
				continue
			var ring := PackedVector2Array()
			for i in polygon.size():
				var a := _snap(polygon[i])
				var b := _snap(polygon[(i + 1) % polygon.size()])
				var splits: Array[Vector2] = [a, b]
				for junction in _junctions:
					if junction.distance_to(a) > 0.003 and junction.distance_to(b) > 0.003 and Geometry2D.get_closest_point_to_segment(junction, a, b).distance_to(junction) < 0.003:
						splits.append(junction)
				splits.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_squared_to(a) < q.distance_squared_to(a))
				for j in range(splits.size() - 1):
					var start := splits[j]
					var end := splits[j + 1]
					if start == end:
						continue
					var forward := start.x < end.x or (start.x == end.x and start.y < end.y)
					var first := start if forward else end
					var last := end if forward else start
					var key := "%d,%d:%d,%d" % [roundi(first.x * 1000), roundi(first.y * 1000), roundi(last.x * 1000), roundi(last.y * 1000)]
					if not edge_ids.has(key):
						var points := _warped_edge(first, last)
						edge_ids[key] = _world.edges.size()
						_world.edges.append({"points":points, "owners":PackedInt32Array()})
					var edge: Dictionary = _world.edges[edge_ids[key]]
					if not edge.owners.has(country):
						edge.owners.append(country)
					var points: PackedVector2Array = edge.points.duplicate()
					if not forward:
						points.reverse()
					points.resize(points.size() - 1)
					ring.append_array(points)
			_world.territories[country].outlines.append(ring)
	for edge in _world.edges:
		if edge.owners.size() == 2:
			var a: int = edge.owners[0]
			var b: int = edge.owners[1]
			if not _world.territories[a].neighbors.has(b):
				_world.territories[a].neighbors.append(b)
				_world.territories[b].neighbors.append(a)

func _warped_edge(first: Vector2, last: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([first, last])
	var strengths := [_settings.macro_boundary_strength, _settings.middle_boundary_strength, _settings.detail_boundary_strength]
	# All owners use one composed curve: broad bends, regional meanders, then fine relief.
	for layer in 3:
		points = _shear(points, 1, 13.0 + layer * 187.0, strengths[layer], _boundary_noises[layer])
		points = _shear(points, 0, 271.0 + layer * 113.0, strengths[layer], _boundary_noises[layer])
	return points

func _shear(points: PackedVector2Array, axis: int, offset: float, strength: float, noise: FastNoiseLite) -> PackedVector2Array:
	# Sample every noise-grid crossing before applying the piecewise-affine shear.
	var result := PackedVector2Array()
	var spacing: float = _settings.curve_sample_distance
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i+1]
		var cuts: Array[float] = [0.0]
		var low := minf(a[axis], b[axis])
		var high := maxf(a[axis], b[axis])
		for j in range(floori(low / spacing)+1, ceili(high / spacing)):
			cuts.append((j * spacing - a[axis]) / (b[axis] - a[axis]))
		cuts.sort()
		for t in cuts:
			result.append(_shear_point(a.lerp(b,t),axis,offset,strength,spacing,noise))
	result.append(_shear_point(points[-1],axis,offset,strength,spacing,noise))
	return result

func _shear_point(point: Vector2, axis: int, offset: float, strength: float, spacing: float, noise: FastNoiseLite) -> Vector2:
	var cell := floorf(point[axis] / spacing)
	var t := point[axis] / spacing - cell
	var value := lerpf(noise.get_noise_2d(cell * spacing,offset),noise.get_noise_2d((cell+1.0) * spacing,offset),t)
	point[1-axis] += strength * value
	return point

func _frame_geography() -> void:
	var bounds := _world.territories[0].bounds()
	for territory in _world.territories: bounds = bounds.merge(territory.bounds())
	var available := _settings.world_size - Vector2.ONE * 48.0
	var scale_factor := minf(available.x / bounds.size.x, available.y / bounds.size.y)
	var center := bounds.get_center()
	var destination := _settings.world_size * 0.5
	# A single uniform framing transform keeps all coast and border curves coincident.
	for territory in _world.territories:
		for ring in territory.outlines:
			for i in ring.size(): ring[i] = destination + (ring[i] - center) * scale_factor
	for edge in _world.edges:
		for i in edge.points.size(): edge.points[i] = destination + (edge.points[i] - center) * scale_factor

func _measure(territory: TerritoryGeometry) -> void:
	for outline in territory.outlines:
		territory.area += polygon_area(outline)
		territory.triangles.append(triangulate_local(outline))

func _place_settlements(territory: TerritoryGeometry) -> void:
	var bounds := territory.bounds()
	var candidates := PackedVector2Array()
	var clearance := PackedFloat64Array()
	for y in range(1, 16):
		for x in range(1, 16):
			var point := bounds.position + bounds.size * Vector2(x / 16.0, y / 16.0)
			if territory.contains(point) and not _world.terrain.is_water(point, 3.0):
				candidates.append(point)
				clearance.append(_clearance(territory, point))
	var best: int = 0
	for i in candidates.size():
		if clearance[i] > clearance[best]:
			best = i
	territory.anchor = candidates[best]
	territory.sites.append(territory.anchor)
	for site in 3:
		var best_score: float = -1.0
		for i in candidates.size():
			var distance: float = INF
			for placed in territory.sites:
				distance = minf(distance, candidates[i].distance_to(placed))
			var score := distance * minf(clearance[i] / 12.0, 1.0)
			if score > best_score:
				best_score = score
				best = i
		territory.sites.append(candidates[best])

func _make_enclaves() -> void:
	# Enclaves transfer a small, explicitly accounted area to their actual owner.
	var group := _world.groups[_rng.randi_range(1, 2)]
	var count := _rng.randi_range(1, 3)
	var host_id: int = group[0]
	var guest_id: int = group[1]
	for index in count:
		var host := _world.territories[host_id]
		var guest := _world.territories[guest_id]
		var box := host.bounds()
		var center := Vector2.ZERO
		var radius: float = -1.0
		for y in range(1, 20):
			for x in range(1, 20):
				var point := box.position + box.size * Vector2(x, y) / 20.0
				if not host.contains(point):
					continue
				var room := _clearance(host, point)
				if room > radius:
					radius = room
					center = point
		# The transfer is tiny relative to both countries and their area-ranking gap.
		var gap := absf(host.area - guest.area)
		for country in _world.territories:
			if country != host: gap = minf(gap,absf(country.area-host.area))
			if country != guest: gap = minf(gap,absf(country.area-guest.area))
		var area_budget := minf(minf(host.area, guest.area) * 0.001, gap * 0.03)
		radius = minf(radius * 0.55, sqrt(area_budget / PI))
		var ring := _organic_ring(center, radius, 64, index * 7.0)
		var area := polygon_area(ring)
		host.holes.append(ring)
		host.area -= area
		guest.area += area
		guest.outlines.append(ring)
		guest.outline_bounds.append(_bounds(ring))
		guest.triangles.append(triangulate_local(ring))
		host.cache_bounds()
		guest.cache_bounds()
		_world.enclaves.append({"host":host_id,"owner":guest_id,"outline":guest.outlines.size()-1,"center":center,"area":area})
		var border := ring.duplicate()
		border.append(ring[0])
		_world.edges.append({"points":border,"owners":PackedInt32Array([host_id,guest_id])})
		if not host.neighbors.has(guest_id):
			host.neighbors.append(guest_id)
			guest.neighbors.append(host_id)
		var temporary := host_id
		host_id = guest_id
		guest_id = temporary

func _clearance(territory: TerritoryGeometry, point: Vector2) -> float:
	var distance: float = INF
	for outline in territory.outlines + territory.holes:
		for i in outline.size():
			distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()])))
	return distance

static func polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in polygon.size():
		area += (polygon[i] - polygon[0]).cross(polygon[(i + 1) % polygon.size()] - polygon[0])
	return absf(area) * 0.5

func _area_sum(polygons: Array) -> float:
	var result: float = 0.0
	for polygon: PackedVector2Array in polygons:
		result += polygon_area(polygon)
	return result

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		result = result.expand(point)
	return result

func _snap(point: Vector2) -> Vector2:
	# Clipping emits the same junction with slightly different floating-point endpoints.
	for junction in _junctions:
		if point.distance_to(junction) < 0.02:
			return junction
	return (point * 1000.0).round() / 1000.0

static func triangulate_local(polygon: PackedVector2Array) -> PackedInt32Array:
	if polygon.size() < 3: return PackedInt32Array()
	var sources := PackedInt32Array()
	for index in polygon.size():
		if not polygon[index].is_finite(): return PackedInt32Array()
		if sources.is_empty() or not _same_float32_sample(polygon[sources[-1]],polygon[index]):
			sources.append(index)
	if sources.size() > 1 and _same_float32_sample(polygon[sources[0]],polygon[sources[-1]]):
		sources.resize(sources.size()-1)
	if sources.size() < 3: return PackedInt32Array()
	# Weld precision-neighbor samples only in this view; saved world geometry stays unchanged.
	var local := PackedVector2Array()
	for source in sources: local.append(polygon[source]-polygon[sources[0]])
	if polygon_area(local) == 0.0: return PackedInt32Array()
	var triangles := Geometry2D.triangulate_polygon(local)
	for index in triangles.size(): triangles[index] = sources[triangles[index]]
	return triangles

static func _same_float32_sample(a: Vector2, b: Vector2) -> bool:
	var magnitude := maxf(maxf(absf(a.x),absf(a.y)),maxf(absf(b.x),absf(b.y)))
	var tolerance := magnitude * 0.0000002384185791015625
	return a.distance_squared_to(b) <= tolerance * tolerance
