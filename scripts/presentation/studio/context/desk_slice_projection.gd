extends RefCounted

var forward: Array[float] = []
var inverse: Array[float] = []
var valid := false

func fit(quad: PackedVector2Array) -> bool:
	valid = false
	if quad.size() != 4: return false
	var dx1 := quad[1].x - quad[2].x
	var dx2 := quad[3].x - quad[2].x
	var dy1 := quad[1].y - quad[2].y
	var dy2 := quad[3].y - quad[2].y
	var sx := quad[0].x - quad[1].x + quad[2].x - quad[3].x
	var sy := quad[0].y - quad[1].y + quad[2].y - quad[3].y
	var denominator := dx1 * dy2 - dx2 * dy1
	if absf(denominator) < 0.00001: return false
	var g := (sx * dy2 - dx2 * sy) / denominator
	var h := (dx1 * sy - sx * dy1) / denominator
	forward.assign([quad[1].x - quad[0].x + g * quad[1].x, quad[3].x - quad[0].x + h * quad[3].x, quad[0].x, quad[1].y - quad[0].y + g * quad[1].y, quad[3].y - quad[0].y + h * quad[3].y, quad[0].y, g, h, 1.0])
	var a := forward[0]
	var b := forward[1]
	var c := forward[2]
	var d := forward[3]
	var e := forward[4]
	var f := forward[5]
	var determinant := a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
	if absf(determinant) < 0.00001: return false
	inverse.assign([(e - f * h) / determinant, (c * h - b) / determinant, (b * f - c * e) / determinant, (f * g - d) / determinant, (a - c * g) / determinant, (c * d - a * f) / determinant, (d * h - e * g) / determinant, (b * g - a * h) / determinant, (a * e - b * d) / determinant])
	valid = true
	return true

func project(point: Vector2) -> Vector2:
	return _map(forward, point)

func unproject(point: Vector2) -> Vector2:
	return _map(inverse, point)

func _map(matrix: Array[float], point: Vector2) -> Vector2:
	if not valid: return Vector2(INF, INF)
	var denominator := matrix[6] * point.x + matrix[7] * point.y + matrix[8]
	if absf(denominator) < 0.000001: return Vector2(INF, INF)
	return Vector2((matrix[0] * point.x + matrix[1] * point.y + matrix[2]) / denominator, (matrix[3] * point.x + matrix[4] * point.y + matrix[5]) / denominator)
