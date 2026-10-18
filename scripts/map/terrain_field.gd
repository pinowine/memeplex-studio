class_name TerrainField
extends RefCounted

var elevation: FastNoiseLite
var moisture: FastNoiseLite
var heights := PackedFloat32Array()
var wetness := PackedFloat32Array()
var land := PackedByteArray()
var drainage_heights := PackedFloat32Array()
var _heap: Array[int] = []
var _heap_priorities: Array[float] = []
var _popped_priority: float
var downstream := PackedInt32Array()
var accumulation := PackedFloat32Array()
var contours := PackedVector2Array()
var rivers: Array[PackedVector2Array] = []
var river_flows: Array[Vector2] = []
var river_paths: Array[PackedVector2Array] = []
var river_path_flows: Array[PackedFloat32Array] = []
var river_bend_profile: Array[Dictionary] = []
var river_curve_records: Array[Dictionary] = []
var _river_junction_tangents: Dictionary = {}
var river_mesh_vertices := PackedVector2Array()
var river_mesh_indices := PackedInt32Array()
var river_polygons: Array[PackedVector2Array] = []
var lake_depths := PackedFloat32Array()
var lake_basins: Array[Dictionary] = []
var sources := PackedVector2Array()
var junctions := PackedVector2Array()
var mouths := PackedVector2Array()
var lakes: Array[PackedVector2Array] = []
var sediment := PackedFloat32Array()
var bed_heights := PackedFloat32Array()
var columns: int
var rows: int
var step: float
var _world: AtlasWorldData
var _coast_bins: Dictionary = {}
var _water_bins: Dictionary = {}
var _water_polygons: Array[PackedVector2Array] = []
var _river_vertex_lookup: Dictionary = {}
var _river_min_width: float
var _river_flow_scale: float

static func perlin(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	return noise

func generate(world: AtlasWorldData, settings: AtlasMapSettings) -> void:
	_world = world
	_river_min_width = settings.river_min_width
	_river_flow_scale = settings.river_flow_scale
	step = settings.terrain_step
	columns = ceili(settings.world_size.x / step) + 1
	rows = ceili(settings.world_size.y / step) + 1
	elevation = perlin(world.seed_value ^ 193939, settings.terrain_frequency, settings.terrain_octaves)
	moisture = perlin(world.seed_value ^ 81917, settings.terrain_frequency * 0.63, 4)
	heights.resize(columns * rows)
	wetness.resize(columns * rows)
	land.resize(columns * rows)
	downstream.resize(columns * rows)
	downstream.fill(-1)
	accumulation.resize(columns * rows)
	for i in heights.size():
		var point := point_at(i)
		heights[i] = height_at(point)
		wetness[i] = 0.5 + 0.5 * moisture.get_noise_2dv(point)
	_scan_land()
	_index_coast()
	_drainage(settings.river_catchment, settings)
	_contour_lines()
	_solve_lake_levels(settings)
	_lake_outlines(settings)
	_build_river_banks()
	_index_water()
	# The field does not retain its owning world after construction.
	_world = null

func height_at(point: Vector2) -> float:
	return 0.5 + 0.5 * elevation.get_noise_2dv(point)

func point_at(index: int) -> Vector2:
	return Vector2(index % columns, index / columns) * step

func _scan_land() -> void:
	# Scan conversion supplies a fast mask; final line clipping uses the exact coast.
	for territory in _world.territories:
		for ring in territory.outlines:
			for y in rows:
				var crossings: Array[float] = []
				for i in ring.size():
					var a := ring[i]
					var b := ring[(i + 1) % ring.size()]
					if (a.y > y * step) != (b.y > y * step):
						crossings.append(a.x + (y * step - a.y) * (b.x - a.x) / (b.y - a.y))
				crossings.sort()
				for i in range(0, crossings.size(), 2):
					for x in range(ceili(crossings[i] / step), floori(crossings[i+1] / step) + 1):
						land[y * columns + x] = 1

func _index_coast() -> void:
	for edge in _world.edges:
		if edge.owners.size() != 1:
			continue
		var points: PackedVector2Array = edge.points
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i+1]
			var low := Vector2i(a.min(b) / 16.0)
			var high := Vector2i(a.max(b) / 16.0)
			for y in range(low.y, high.y + 1):
				for x in range(low.x, high.x + 1):
					var key := Vector2i(x,y)
					if not _coast_bins.has(key):
						_coast_bins[key] = []
					_coast_bins[key].append(PackedVector2Array([a,b]))

func _land_pieces(a: Vector2, b: Vector2) -> Array[PackedVector2Array]:
	var cuts: Array[float] = [0.0,1.0]
	var low := Vector2i(a.min(b) / 16.0)
	var high := Vector2i(a.max(b) / 16.0)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var key := Vector2i(x,y)
			if not _coast_bins.has(key):
				continue
			for edge: PackedVector2Array in _coast_bins[key]:
				var intersection: Variant = Geometry2D.segment_intersects_segment(a,b,edge[0],edge[1])
				if intersection != null:
					cuts.append(a.distance_to(intersection) / a.distance_to(b))
	cuts.sort()
	var result: Array[PackedVector2Array] = []
	for i in range(cuts.size() - 1):
		var start := a.lerp(b,cuts[i])
		var finish := a.lerp(b,cuts[i+1])
		if start.distance_to(finish) > 0.001 and _world.country_at((start+finish)*0.5) >= 0:
			result.append(PackedVector2Array([start,finish]))
	return result

func _flood_surface(bed: PackedFloat32Array, settings: AtlasMapSettings) -> Array[int]:
	var ordered: Array[int] = []
	var visited := PackedByteArray()
	visited.resize(heights.size())
	downstream.fill(-1)
	drainage_heights = bed.duplicate()
	for index in land.size():
		drainage_heights[index] = 0.0 if land[index] == 0 else INF
	for y in range(1, rows - 1):
		for x in range(1, columns - 1):
			var index := y * columns + x
			if land[index] == 0:
				continue
			var nearest_sea: float = INF
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbor := index + dy * columns + dx
					if land[neighbor] == 0 and _flow_neighbor_allowed(index, neighbor, bed):
						var distance := Vector2(dx, dy).length()
						if distance < nearest_sea:
							nearest_sea = distance
							downstream[index] = neighbor
			if downstream[index] >= 0:
				drainage_heights[index] = bed[index]
				_heap_push(index)
	# Label-setting minimax relaxation follows lower-bed outlet routes inside basins.
	while not _heap.is_empty():
		var index := _heap_pop()
		if visited[index] == 1 or _popped_priority != drainage_heights[index]:
			continue
		visited[index] = 1
		ordered.append(index)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var neighbor := index + dy * columns + dx
				if land[neighbor] == 0 or visited[neighbor] == 1 or not _flow_neighbor_allowed(index, neighbor, bed):
					continue
				var depth := maxf(0.0, drainage_heights[index] - (bed[index] + bed[neighbor]) * 0.5)
				var resistance := settings.river_basin_min_cost + exp(-depth / settings.river_basin_depth_scale)
				var grade := settings.river_routing_grade * Vector2(dx, dy).length() * resistance
				var candidate := maxf(bed[neighbor], drainage_heights[index] + grade)
				if candidate < drainage_heights[neighbor]:
					drainage_heights[neighbor] = candidate
					downstream[neighbor] = index
					_heap_push(neighbor)
	ordered.reverse()
	_route_slopes(ordered, bed)
	return ordered

func _flow_neighbor_allowed(index: int, next: int, bed: PackedFloat32Array) -> bool:
	var dx := next % columns - index % columns
	var dy := next / columns - index / columns
	if dx == 0 or dy == 0:
		return true
	# The lower terrain diagonal is shared by both triangles in each flow cell.
	var diagonal := bed[index] + bed[next]
	var across := bed[index + dx] + bed[index + dy * columns]
	return diagonal <= across if dx * dy > 0 else diagonal < across

func _route_slopes(ordered: Array[int], bed: PackedFloat32Array) -> void:
	for index in ordered:
		var selected := downstream[index]
		if land[selected] == 0:
			continue
		var maximum := (drainage_heights[index] - drainage_heights[selected]) / point_at(index).distance_to(point_at(selected))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next := index + dy * columns + dx
				if land[next] == 0 or not _flow_neighbor_allowed(index, next, bed):
					continue
				var slope := (drainage_heights[index] - drainage_heights[next]) / point_at(index).distance_to(point_at(next))
				if slope > maximum:
					maximum = slope
					selected = next
		downstream[index] = selected

func routing_height_at(point: Vector2) -> float:
	var local := point / step
	var x := clampi(floori(local.x), 0, columns - 2)
	var y := clampi(floori(local.y), 0, rows - 2)
	var t := local - Vector2(x, y)
	var ids := PackedInt32Array([y * columns + x, y * columns + x + 1, (y + 1) * columns + x, (y + 1) * columns + x + 1])
	if bed_heights[ids[0]] + bed_heights[ids[3]] <= bed_heights[ids[1]] + bed_heights[ids[2]]:
		if t.x >= t.y:
			return drainage_heights[ids[0]] * (1.0 - t.x) + drainage_heights[ids[1]] * (t.x - t.y) + drainage_heights[ids[3]] * t.y
		return drainage_heights[ids[0]] * (1.0 - t.y) + drainage_heights[ids[2]] * (t.y - t.x) + drainage_heights[ids[3]] * t.x
	if t.x + t.y <= 1.0:
		return drainage_heights[ids[0]] * (1.0 - t.x - t.y) + drainage_heights[ids[1]] * t.x + drainage_heights[ids[2]] * t.y
	return drainage_heights[ids[1]] * (1.0 - t.y) + drainage_heights[ids[2]] * (1.0 - t.x) + drainage_heights[ids[3]] * (t.x + t.y - 1.0)

func _accumulate(ordered: Array[int]) -> void:
	accumulation.fill(0.0)
	for index in ordered:
		accumulation[index] += wetness[index]
		if downstream[index] >= 0:
			accumulation[downstream[index]] += accumulation[index]

func _drainage(threshold: float, settings: AtlasMapSettings) -> void:
	var ordered := _flood_surface(heights, settings)
	_accumulate(ordered)
	sediment.resize(heights.size())
	# One bounded deposition step models silt bars where large flows lose slope.
	for index in ordered:
		var next := downstream[index]
		if next < 0 or land[next] == 0 or accumulation[index] < threshold * 1.5:
			continue
		var slope := maxf(0.0,heights[index]-heights[next]) / step
		var deposit := minf(accumulation[index] * 0.00008,0.018) * maxf(0.0,1.0-slope/0.003)
		for dy in range(-1,2):
			for dx in range(-1,2):
				var cell := next + dy * columns + dx
				if land[cell] == 1:
					sediment[cell] = maxf(sediment[cell],deposit * exp(-float(dx*dx+dy*dy)))
	bed_heights = heights.duplicate()
	for i in bed_heights.size(): bed_heights[i] += sediment[i]
	ordered = _flood_surface(bed_heights, settings)
	_accumulate(ordered)
	var incoming := PackedInt32Array()
	incoming.resize(heights.size())
	for index in ordered:
		if accumulation[index] >= threshold and downstream[index] >= 0:
			incoming[downstream[index]] += 1
	for index in ordered:
		if incoming[index] <= 1:
			continue
		var upstream: int = -1
		var maximum_flow: float = 0.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var previous: int = index + dy * columns + dx
				if downstream[previous] == index and accumulation[previous] > maximum_flow:
					maximum_flow = accumulation[previous]
					upstream = previous
		var incoming_direction := (point_at(index) - point_at(upstream)).normalized()
		var outgoing_direction := (point_at(downstream[index]) - point_at(index)).normalized()
		_river_junction_tangents[point_at(index)] = (incoming_direction + outgoing_direction).normalized()
	for index in ordered:
		if accumulation[index] < threshold or incoming[index] == 1:
			continue
		if incoming[index] == 0: sources.append(point_at(index))
		if incoming[index] > 1: junctions.append(point_at(index))
		var path := PackedVector2Array([point_at(index)])
		var flows := PackedFloat32Array([0.0 if incoming[index]==0 else accumulation[index]])
		var cursor := downstream[index]
		while cursor >= 0:
			path.append(point_at(cursor))
			flows.append(accumulation[cursor])
			if land[cursor] == 0: mouths.append(point_at(cursor))
			if land[cursor] == 0 or incoming[cursor] != 1:
				break
			cursor = downstream[cursor]
		if path.size() < 2:
			continue
		var sampled: Dictionary = _terrain_river_curve(path, flows, settings)
		_store_river_paths(sampled.points, sampled.flows)

static func _route_point(path: PackedVector2Array, parameter: float) -> Vector2:
	var index := mini(floori(parameter), path.size() - 2)
	return path[index].lerp(path[index + 1], parameter - index)

static func _route_discharge(flows: PackedFloat32Array, parameter: float) -> float:
	var index := mini(floori(parameter), flows.size() - 2)
	return lerpf(flows[index], flows[index + 1], parameter - index)

func _terrain_gradient(point: Vector2) -> Vector2:
	var distance := step * 0.25
	return Vector2(height_at(point + Vector2(distance, 0)) - height_at(point - Vector2(distance, 0)), height_at(point + Vector2(0, distance)) - height_at(point - Vector2(0, distance))) / (distance * 2.0)

func _valley_knot(path: PackedVector2Array, parameter: float, settings: AtlasMapSettings) -> Vector2:
	var point := _route_point(path, parameter)
	if parameter == 0.0 or parameter == path.size() - 1:
		return point
	var direction := (_route_point(path, minf(path.size() - 1, parameter + 2.0)) - _route_point(path, maxf(0.0, parameter - 2.0))).normalized()
	var normal := direction.orthogonal()
	# The Perlin cross-slope moves visual knots toward local valley ground.
	var offset := -settings.river_valley_corridor * 0.75 * tanh(_terrain_gradient(point).dot(normal) / settings.river_bend_slope_scale)
	return point + normal * offset

func _curve_controls(path: PackedVector2Array, parameters: Array[float], settings: AtlasMapSettings) -> Array[PackedVector2Array]:
	var knots := PackedVector2Array()
	var tangents := PackedVector2Array()
	var reaches := PackedFloat32Array()
	for parameter in parameters:
		knots.append(_valley_knot(path, parameter, settings))
	for i in knots.size():
		var previous := knots[maxi(0, i - 1)]
		var next := knots[mini(knots.size() - 1, i + 1)]
		var direction := (next - previous).normalized()
		var gradient := _terrain_gradient(knots[i])
		if i == 0 or i == knots.size() - 1:
			if _river_junction_tangents.has(knots[i]):
				direction = _river_junction_tangents[knots[i]]
		else:
			var normal := direction.orthogonal()
			direction = (direction - normal * tanh(gradient.dot(normal) / settings.river_bend_slope_scale) * 0.2).normalized()
		var length := knots[i].distance_to(next) if i == 0 else knots[i].distance_to(previous)
		if i > 0 and i < knots.size() - 1:
			length = minf(length, knots[i].distance_to(next))
		if _river_junction_tangents.has(knots[i]):
			length = step
		var reach := length * settings.river_bend_reach * (0.65 + 0.35 / (1.0 + gradient.length() / settings.river_bend_slope_scale))
		# One handle vector per knot gives both neighboring cubics the same derivative.
		tangents.append(direction)
		reaches.append(reach)
	var controls: Array[PackedVector2Array] = []
	for i in range(knots.size() - 1):
		controls.append(PackedVector2Array([knots[i], knots[i] + tangents[i] * reaches[i], knots[i + 1] - tangents[i + 1] * reaches[i + 1], knots[i + 1]]))
	return controls

static func _cubic_point(control: PackedVector2Array, t: float) -> Vector2:
	var u := 1.0 - t
	return control[0] * u * u * u + control[1] * 3.0 * u * u * t + control[2] * 3.0 * u * t * t + control[3] * t * t * t

static func _route_distance(path: PackedVector2Array, first: float, last: float, point: Vector2) -> float:
	var closest: float = INF
	for i in range(floori(first), mini(ceili(last), path.size() - 1)):
		closest = minf(closest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])))
	return closest

func _terrain_river_curve(path: PackedVector2Array, flows: PackedFloat32Array, settings: AtlasMapSettings) -> Dictionary:
	var parameters: Array[float] = [0.0]
	var length: float = 0.0
	for i in range(1, path.size() - 1):
		length += path[i].distance_to(path[i - 1])
		var spacing := step * (3.0 + 3.0 / (1.0 + _terrain_gradient(path[i]).length() / settings.river_bend_slope_scale))
		if length >= spacing:
			parameters.append(float(i))
			length = 0.0
	parameters.append(float(path.size() - 1))
	if parameters.size() == 2:
		parameters.insert(1, (path.size() - 1) * 0.5)
	var controls := _curve_controls(path, parameters, settings)
	var refined: bool = true
	# Adaptive subdivision keeps smooth reaches inside their original drainage corridor.
	while refined:
		refined = false
		for i in range(controls.size() - 1, -1, -1):
			var outside: bool = false
			var samples := ceili((controls[i][0].distance_to(controls[i][1]) + controls[i][1].distance_to(controls[i][2]) + controls[i][2].distance_to(controls[i][3])) / 0.25)
			for j in range(1, samples):
				if _route_distance(path, parameters[i], parameters[i + 1], _cubic_point(controls[i], j / float(samples))) > settings.river_valley_corridor:
					outside = true
					break
			if outside:
				parameters.insert(i + 1, (parameters[i] + parameters[i + 1]) * 0.5)
				refined = true
		if refined:
			controls = _curve_controls(path, parameters, settings)
	var points := PackedVector2Array([path[0]])
	var discharge := PackedFloat32Array([flows[0]])
	var maximum_deviation: float = 0.0
	for i in controls.size():
		var control := controls[i]
		var samples := ceili((control[0].distance_to(control[1]) + control[1].distance_to(control[2]) + control[2].distance_to(control[3])) / 0.25)
		for j in range(1, samples + 1):
			var t := j / float(samples)
			var point := _cubic_point(control, t)
			points.append(point)
			discharge.append(_route_discharge(flows, lerpf(parameters[i], parameters[i + 1], t)))
			maximum_deviation = maxf(maximum_deviation, _route_distance(path, parameters[i], parameters[i + 1], point))
		var gradient := _terrain_gradient(control[0])
		river_bend_profile.append({"turn":(control[1] - control[0]).angle_to(control[3] - control[2]), "incoming_reach": control[0].distance_to(control[1]), "outgoing_reach": control[2].distance_to(control[3]), "terrain_gradient":gradient.length(), "scale":1.0, "knot_span":parameters[i + 1] - parameters[i]})
	river_curve_records.append({"route":path, "controls":controls, "parameters":parameters, "maximum_corridor_deviation":maximum_deviation})
	return {"points":points, "flows":discharge}

func _store_river_paths(path: PackedVector2Array, flows: PackedFloat32Array) -> void:
	var continuous := PackedVector2Array()
	var discharge := PackedFloat32Array()
	for i in range(path.size() - 1):
		var length := path[i].distance_to(path[i + 1])
		for segment in _land_pieces(path[i], path[i + 1]):
			var start_flow := lerpf(flows[i], flows[i + 1], path[i].distance_to(segment[0]) / length)
			var end_flow := lerpf(flows[i], flows[i + 1], path[i].distance_to(segment[1]) / length)
			# Store two-point drainage segments alongside complete render paths.
			rivers.append(segment)
			river_flows.append(Vector2(start_flow, end_flow))
			if not continuous.is_empty() and continuous[-1].distance_to(segment[0]) > 0.001:
				river_paths.append(continuous)
				river_path_flows.append(discharge)
				continuous = PackedVector2Array()
				discharge = PackedFloat32Array()
			if continuous.is_empty():
				continuous.append(segment[0])
				discharge.append(start_flow)
			continuous.append(segment[1])
			discharge.append(end_flow)
	if not continuous.is_empty():
		river_paths.append(continuous)
		river_path_flows.append(discharge)

func _contour_lines() -> void:
	for y in range(rows - 1):
		for x in range(columns - 1):
			var ids := PackedInt32Array([y*columns+x,y*columns+x+1,(y+1)*columns+x+1,(y+1)*columns+x])
			if land[ids[0]]+land[ids[1]]+land[ids[2]]+land[ids[3]] == 0:
				continue
			var low := minf(minf(heights[ids[0]],heights[ids[1]]),minf(heights[ids[2]],heights[ids[3]]))
			var high := maxf(maxf(heights[ids[0]],heights[ids[1]]),maxf(heights[ids[2]],heights[ids[3]]))
			for level in range(ceili(low / 0.04),floori(high / 0.04)+1):
				var iso: float = level * 0.04
				var hits := PackedVector2Array()
				for edge in 4:
					var a := ids[edge]
					var b := ids[(edge+1)%4]
					if (heights[a] > iso) != (heights[b] > iso):
						hits.append(point_at(a).lerp(point_at(b),(iso-heights[a])/(heights[b]-heights[a])))
				for i in range(0,hits.size(),2):
					for segment in _land_pieces(hits[i],hits[i+1]):
						contours.append_array(segment)

func _heap_push(index: int) -> void:
	var priority: float = drainage_heights[index]
	_heap.append(index)
	_heap_priorities.append(priority)
	var cursor := _heap.size() - 1
	while cursor > 0:
		var parent := (cursor - 1) / 2
		if _heap_priorities[parent] <= priority:
			break
		_heap[cursor] = _heap[parent]
		_heap_priorities[cursor] = _heap_priorities[parent]
		cursor = parent
	_heap[cursor] = index
	_heap_priorities[cursor] = priority

func _heap_pop() -> int:
	var first := _heap[0]
	_popped_priority = _heap_priorities[0]
	var last: int = _heap.pop_back()
	var last_priority: float = _heap_priorities.pop_back()
	if _heap.is_empty():
		return first
	var cursor: int = 0
	while cursor * 2 + 1 < _heap.size():
		var child := cursor * 2 + 1
		if child + 1 < _heap.size() and _heap_priorities[child + 1] < _heap_priorities[child]:
			child += 1
		if last_priority <= _heap_priorities[child]:
			break
		_heap[cursor] = _heap[child]
		_heap_priorities[cursor] = _heap_priorities[child]
		cursor = child
	_heap[cursor] = last
	_heap_priorities[cursor] = last_priority
	return first

func elevation_image(size: Vector2i) -> Image:
	var samples := PackedFloat32Array()
	samples.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			samples[y*size.x+x] = height_at(Vector2(x,y))
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RF,samples.to_byte_array())

func _solve_lake_levels(settings: AtlasMapSettings) -> void:
	lake_depths.resize(heights.size())
	var visited := PackedByteArray()
	visited.resize(heights.size())
	for start in heights.size():
		if visited[start] == 1 or land[start] == 0 or drainage_heights[start] - bed_heights[start] <= settings.lake_basin_depth:
			continue
		var cells := PackedInt32Array([start])
		visited[start] = 1
		var cursor: int = 0
		var floor_height := bed_heights[start]
		var spill_height := drainage_heights[start]
		var humidity: float = 0.0
		while cursor < cells.size():
			var cell := cells[cursor]
			cursor += 1
			floor_height = minf(floor_height, bed_heights[cell])
			spill_height = minf(spill_height, drainage_heights[cell])
			humidity += wetness[cell]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := cell % columns + dx
					var y := cell / columns + dy
					if x < 0 or x >= columns or y < 0 or y >= rows:
						continue
					var next := y * columns + x
					if visited[next] == 1 or land[next] == 0 or drainage_heights[next] - bed_heights[next] <= settings.lake_basin_depth:
						continue
					visited[next] = 1
					cells.append(next)
		humidity /= cells.size()
		var capacity: float = 0.0
		for cell in cells:
			capacity += maxf(spill_height - bed_heights[cell], 0.0) * step * step
		# This demo reservoir budget is separate from the routing flood, not a hydrology simulation.
		var volume := capacity * settings.lake_retention_ratio * pow(humidity, settings.lake_moisture_exponent)
		var low := floor_height
		var high := spill_height
		for iteration in 28:
			var level := (low + high) * 0.5
			var filled: float = 0.0
			for cell in cells:
				filled += maxf(level - bed_heights[cell], 0.0) * step * step
			if filled < volume:
				low = level
			else:
				high = level
		var surface := (low + high) * 0.5
		for cell in cells:
			lake_depths[cell] = maxf(surface - bed_heights[cell], 0.0)
		lake_basins.append({"cells": cells.size(), "capacity": capacity, "volume": volume, "humidity": humidity, "surface": surface, "spill": spill_height})

func _lake_depth_sample(point: Vector2) -> float:
	var sample := point / step
	var base := Vector2i(sample.floor())
	var t := sample - Vector2(base)
	var wx := PackedFloat32Array([pow(1.0 - t.x, 3.0), 3.0 * pow(t.x, 3.0) - 6.0 * t.x * t.x + 4.0, -3.0 * pow(t.x, 3.0) + 3.0 * t.x * t.x + 3.0 * t.x + 1.0, pow(t.x, 3.0)])
	var wy := PackedFloat32Array([pow(1.0 - t.y, 3.0), 3.0 * pow(t.y, 3.0) - 6.0 * t.y * t.y + 4.0, -3.0 * pow(t.y, 3.0) + 3.0 * t.y * t.y + 3.0 * t.y + 1.0, pow(t.y, 3.0)])
	var depth: float = 0.0
	for y in 4:
		for x in 4:
			var index := clampi(base.y + y - 1, 0, rows - 1) * columns + clampi(base.x + x - 1, 0, columns - 1)
			depth += lake_depths[index] * wx[x] * wy[y] / 36.0
	return depth

func _lake_outlines(settings: AtlasMapSettings) -> void:
	# Subdivided scalar cells preserve dry islands without filling nested boundary rings.
	for y in range(rows - 1):
		for x in range(columns - 1):
			var maximum_depth: float = 0.0
			for dy in range(-1, 3):
				for dx in range(-1, 3):
					var index := clampi(y + dy, 0, rows - 1) * columns + clampi(x + dx, 0, columns - 1)
					maximum_depth = maxf(maximum_depth, lake_depths[index])
			if maximum_depth <= settings.lake_visible_depth:
				continue
			var subdivisions := settings.lake_mesh_subdivisions
			for sy in subdivisions:
				for sx in subdivisions:
					var origin := (Vector2(x, y) + Vector2(sx, sy) / subdivisions) * step
					var size := step / subdivisions
					var corners := PackedVector2Array([origin, origin + Vector2(size, 0), origin + Vector2(size, size), origin + Vector2(0, size)])
					var depth := PackedFloat32Array()
					for point in corners:
						depth.append(_lake_depth_sample(point) - settings.lake_visible_depth)
					for triangle in [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3])]:
						var points := PackedVector2Array()
						var levels := PackedFloat32Array()
						for i in triangle:
							points.append(corners[i])
							levels.append(depth[i])
						var wet := _wet_triangle(points, levels)
						if wet.size() < 3 or AtlasMapGenerator.polygon_area(wet) < 0.00001:
							continue
						for part in _water_parts(wet):
							lakes.append(part)

static func _wet_triangle(points: PackedVector2Array, depths: PackedFloat32Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var next := (i + 1) % points.size()
		if depths[i] > 0.0:
			result.append(points[i])
		if (depths[i] > 0.0) != (depths[next] > 0.0):
			result.append(points[i].lerp(points[next], depths[i] / (depths[i] - depths[next])))
	return result

func _water_parts(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		box = box.expand(point)
	var low := Vector2i(box.position / 16.0)
	var high := Vector2i(box.end / 16.0)
	var coastal: bool = false
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			coastal = coastal or _coast_bins.has(Vector2i(x, y))
	if not coastal:
		return [polygon]
	var result: Array[PackedVector2Array] = []
	var origin := polygon[0]
	var local := Transform2D(0.0, -origin)
	for territory in _world.territories:
		if not territory.bounds().intersects(box):
			continue
		for outline in territory.outlines:
			for part in Geometry2D.intersect_polygons(local * polygon, local * outline):
				var normalized := _water_ring(Transform2D(0.0, origin) * part)
				if AtlasMapGenerator.polygon_area(normalized) > 0.00001:
					result.append(normalized)
	return result

static func _water_ring(polygon: PackedVector2Array) -> PackedVector2Array:
	var ring := polygon.duplicate()
	var changed: bool = true
	while changed and ring.size() > 3:
		changed = false
		for i in range(ring.size() - 1, -1, -1):
			if ring.size() == 3:
				break
			var previous := ring[(i + ring.size() - 1) % ring.size()]
			var next := ring[(i + 1) % ring.size()]
			var closest := Geometry2D.get_closest_point_to_segment(ring[i], previous, next)
			# Boolean clipping returns near-collinear float32 shoreline vertices.
			var precision := maxf(absf(ring[i].x), absf(ring[i].y)) * 0.0000002384185791
			if ring[i].distance_to(closest) <= precision:
				ring.remove_at(i)
				changed = true
	return ring

func river_width(flow: float) -> float:
	return 0.0 if flow == 0.0 else _river_min_width + _river_flow_scale * sqrt(flow)

static func river_banks(path: PackedVector2Array, flows: PackedFloat32Array, minimum_width: float, flow_scale: float) -> PackedVector2Array:
	var banks := PackedVector2Array()
	for i in path.size():
		var previous := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, path.size() - 1)]
		var normal := (next - previous).normalized().orthogonal()
		var width := 0.0 if flows[i] == 0.0 else minimum_width + flow_scale * sqrt(flows[i])
		banks.append(path[i] - normal * width * 0.5)
		banks.append(path[i] + normal * width * 0.5)
	return banks

func _build_river_banks() -> void:
	for branch in river_paths.size():
		var path := river_paths[branch]
		var banks := river_banks(path, river_path_flows[branch], _river_min_width, _river_flow_scale)
		for endpoint in [0, path.size() - 1]:
			if _river_junction_tangents.has(path[endpoint]):
				var normal: Vector2 = _river_junction_tangents[path[endpoint]].orthogonal()
				var radius := river_width(river_path_flows[branch][endpoint]) * 0.5
				# Every incident reach uses the same final confluence bank pair.
				banks[endpoint * 2] = path[endpoint] - normal * radius
				banks[endpoint * 2 + 1] = path[endpoint] + normal * radius
		for i in range(path.size() - 1):
			for triangle in [PackedInt32Array([i * 2, i * 2 + 1, i * 2 + 2]), PackedInt32Array([i * 2 + 1, i * 2 + 3, i * 2 + 2])]:
				var points := PackedVector2Array([banks[triangle[0]], banks[triangle[1]], banks[triangle[2]]])
				if AtlasMapGenerator.polygon_area(points) < 0.0000001:
					continue
				for polygon in _water_parts(points):
					river_polygons.append(polygon)
					var indices := AtlasMapGenerator.triangulate_local(polygon)
					var registered := PackedInt32Array()
					for point in polygon:
						if not _river_vertex_lookup.has(point):
							_river_vertex_lookup[point] = river_mesh_vertices.size()
							river_mesh_vertices.append(point)
						registered.append(_river_vertex_lookup[point])
					for index in indices:
						river_mesh_indices.append(registered[index])

func _index_water() -> void:
	_water_polygons.append_array(river_polygons)
	_water_polygons.append_array(lakes)
	for i in _water_polygons.size():
		var polygon := _water_polygons[i]
		var box := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			box = box.expand(point)
		var low := Vector2i(box.position / 16.0)
		var high := Vector2i(box.end / 16.0)
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, y)
				if not _water_bins.has(key):
					_water_bins[key] = []
				_water_bins[key].append(i)

func is_water(point: Vector2, buffer: float = 0.0) -> bool:
	var low := Vector2i((point - Vector2.ONE * buffer) / 16.0)
	var high := Vector2i((point + Vector2.ONE * buffer) / 16.0)
	var visited: Dictionary = {}
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var key := Vector2i(x, y)
			if not _water_bins.has(key):
				continue
			for index: int in _water_bins[key]:
				if visited.has(index):
					continue
				visited[index] = true
				var polygon := _water_polygons[index]
				if Geometry2D.is_point_in_polygon(Vector2.ZERO, Transform2D(0.0, -point) * polygon):
					return true
				for i in polygon.size():
					if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])) <= buffer:
						return true
	return false
