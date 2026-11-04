extends Node2D

const FILL := Color(1.0, 0.84, 0.43)
const OUTLINE := Color.BLACK
const SEGMENTS := 40

var _source := Vector2.ZERO
var _destination := Vector2.ZERO
var _control_start := Vector2.ZERO
var _control_end := Vector2.ZERO
var _head_direction := Vector2.ZERO
var _curve := PackedVector2Array()
var _shaft := PackedVector2Array()
var _head := PackedVector2Array()

func connect_points(source: Vector2, destination: Vector2) -> void:
	_source = source
	_destination = destination
	var delta := destination - source
	var distance := delta.length()
	var bend := delta.orthogonal().normalized() * minf(140.0, distance * 0.24)
	_control_start = source.lerp(destination, 0.3) + bend
	_control_end = source.lerp(destination, 0.7) + bend
	_head_direction = (destination - _control_end).normalized()
	var head_length := minf(18.0, distance * 0.35)
	var side := _head_direction.orthogonal() * head_length * 0.6
	var base := destination - _head_direction * head_length
	_head = PackedVector2Array([destination, base + side, base - side])
	# End the stroke inside the arrowhead so its border never crosses the tip.
	var shaft_end := 1.0 - head_length * 0.65 / maxf(1.0, 3.0 * destination.distance_to(_control_end))
	_curve.resize(SEGMENTS + 1)
	_shaft.resize(SEGMENTS + 1)
	for index in SEGMENTS + 1:
		var progress := float(index) / SEGMENTS
		_curve[index] = source.bezier_interpolate(_control_start, _control_end, destination, progress)
		_shaft[index] = source.bezier_interpolate(_control_start, _control_end, destination, progress * shaft_end)
	queue_redraw()

func intersects_rect(rectangle: Rect2) -> bool:
	for point: Vector2 in _curve:
		if rectangle.has_point(point): return true
	return false

func _draw() -> void:
	if _curve.is_empty(): return
	if _source.distance_to(_destination) > 2.0:
		draw_polyline(_shaft, OUTLINE, 7.0, true)
		draw_polyline(_shaft, FILL, 4.0, true)
		draw_colored_polygon(_head, FILL)
		var outline := _head.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, OUTLINE, 2.5, true)
	draw_circle(_source, 6.5, OUTLINE, true, -1.0, true)
	draw_circle(_source, 4.5, FILL, true, -1.0, true)

func inspection() -> Dictionary:
	return {"source":_source, "destination":_destination,
		"control_points":PackedVector2Array([_source, _control_start, _control_end, _destination]),
		"head_direction":_head_direction, "curve":_curve, "head":_head}
