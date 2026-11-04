extends Node2D

const FOLLOW_RATE := 8.0
const FLOAT_AMPLITUDE := 4.0
const FLOAT_PERIOD := 1.6
const FILL := Color(1.0, 0.96, 0.75)
const OUTLINE := Color(0.22, 0.25, 0.17)

var _destination := Vector2.ZERO
var _tip := Vector2.ZERO
var _angle := 0.0
var _length := 40.0
var _elapsed := 0.0
var _placed := false

func point_to(tip: Vector2, angle: float, length: float) -> void:
	_destination = tip
	_angle = angle
	_length = length
	if not _placed:
		_tip = tip
		rotation = angle
		position = tip
		_placed = true
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _placed: return
	_elapsed += delta
	var weight := 1.0 - exp(-FOLLOW_RATE * delta)
	_tip = _tip.lerp(_destination, weight)
	rotation = lerp_angle(rotation, _angle, weight)
	position = _tip + Vector2(0, sin(_elapsed * TAU / FLOAT_PERIOD) * FLOAT_AMPLITUDE)

func _draw() -> void:
	var points := PackedVector2Array([
		Vector2(-_length, -5), Vector2(-16, -5),
		Vector2(-16, -13), Vector2.ZERO, Vector2(-16, 13),
		Vector2(-16, 5), Vector2(-_length, 5)])
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, OUTLINE, 3.0, true)

func inspection() -> Dictionary:
	return {"instance_id":get_instance_id(), "tip":_tip, "destination":_destination,
		"position":position, "floating_offset":position - _tip, "length":_length}
