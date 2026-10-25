class_name TerritoryGeometry
extends RefCounted

var outlines: Array[PackedVector2Array] = []
var outline_bounds: Array[Rect2] = []
var holes: Array[PackedVector2Array] = []
var triangles: Array[PackedInt32Array] = []
var neighbors := PackedInt32Array()
var sites := PackedVector2Array()
var anchor: Vector2
var area: float = 0.0
var target_weight: float
var group: int

var _ray_rows: Array[PackedVector4Array] = []
var _ray_first_row: int
var _ray_bounds: Rect2
const RAY_ROW_HEIGHT: float = 8.0

func contains(point: Vector2) -> bool:
	if not _ray_bounds.has_point(point): return false
	var inside: bool = false
	var row := floori(point.y / RAY_ROW_HEIGHT) - _ray_first_row
	# Half-open crossings count shared vertices once, using scalar double precision.
	for edge in _ray_rows[row]:
		if (edge.y > point.y) != (edge.w > point.y):
			var crossing := float(edge.x) + (float(point.y) - edge.y) * (float(edge.z) - edge.x) / (float(edge.w) - edge.y)
			if point.x < crossing: inside = not inside
	return inside

func cache_bounds() -> void:
	outline_bounds.clear()
	_ray_bounds = bounds()
	_ray_first_row = floori(_ray_bounds.position.y / RAY_ROW_HEIGHT)
	_ray_rows.clear()
	for row in floori(_ray_bounds.end.y / RAY_ROW_HEIGHT) - _ray_first_row + 1:
		_ray_rows.append(PackedVector4Array())
	for ring in outlines:
		var box := Rect2(ring[0], Vector2.ZERO)
		for point in ring: box = box.expand(point)
		outline_bounds.append(box)
	for ring in outlines + holes:
		for i in ring.size():
			var a: Vector2 = ring[i]
			var b: Vector2 = ring[(i + 1) % ring.size()]
			var first := floori(minf(a.y, b.y) / RAY_ROW_HEIGHT) - _ray_first_row
			var last := floori(maxf(a.y, b.y) / RAY_ROW_HEIGHT) - _ray_first_row
			for row in range(first, last + 1):
				_ray_rows[row].append(Vector4(a.x, a.y, b.x, b.y))

func bounds() -> Rect2:
	var result := Rect2(outlines[0][0], Vector2.ZERO)
	for outline in outlines:
		for point in outline:
			result = result.expand(point)
	return result
