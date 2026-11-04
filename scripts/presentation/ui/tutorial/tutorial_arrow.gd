extends Node2D

const FOLLOW_RATE := 8.0
const FLOAT_AMPLITUDE := 1.2
const FLOAT_PERIOD := 2.4
const FILL := Color(1.0, 0.96, 0.75)
const ACTION_FILL := Color(1.0, 0.84, 0.43)
const OUTLINE := Color(0.22, 0.25, 0.17)

var _destination := Vector2.ZERO
var _tip := Vector2.ZERO
var _angle := 0.0
var _length := 40.0
var _target_length := 40.0
var _elapsed := 0.0
var _requires_action := false
var _action_blend := 0.0
var _lift := 0.0
var _placed := false

func point_to(tip: Vector2, angle: float, length: float, requires_action := false) -> void:
	_destination = tip
	_angle = angle
	_target_length = length
	_requires_action = requires_action
	if not _placed:
		_tip = tip
		_length = length
		_action_blend = 1.0 if requires_action else 0.0
		rotation = angle
		position = tip
		_placed = true
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not _placed: return
	_elapsed += delta
	var weight := 1.0 - exp(-FOLLOW_RATE * delta)
	_tip = _tip.lerp(_destination, weight)
	_length = lerpf(_length, _target_length, weight)
	_action_blend = lerpf(_action_blend, 1.0 if _requires_action else 0.0, weight)
	rotation = lerp_angle(rotation, _angle, weight)
	_lift = (1.0 - cos(_elapsed * TAU / FLOAT_PERIOD)) * FLOAT_AMPLITUDE
	position = _tip + Vector2(0, -_lift)
	queue_redraw()

func _draw() -> void:
	var shaft := lerpf(2.0, 5.0, _action_blend)
	var head := lerpf(9.0, 13.0, _action_blend)
	var points := PackedVector2Array([
		Vector2(-_length, -shaft), Vector2(-16, -shaft),
		Vector2(-16, -head), Vector2.ZERO, Vector2(-16, head),
		Vector2(-16, shaft), Vector2(-_length, shaft)])
	var line := PackedVector2Array([Vector2(-_length, 0), Vector2.ZERO])
	var chevron := PackedVector2Array([Vector2(-12, -9), Vector2.ZERO, Vector2(-12, 9)])
	# A stationary shadow gives the small lift a sense of height above the desk.
	var shadow_offset := Vector2(2, 4 + _lift).rotated(-rotation)
	draw_set_transform(shadow_offset, 0.0, Vector2.ONE * (1.0 - _lift * 0.012))
	var shadow := Color(OUTLINE, 0.14 - _lift * 0.02)
	draw_polyline(line, Color(shadow, shadow.a * (1.0 - _action_blend)), 3.0, true)
	draw_polyline(chevron, Color(shadow, shadow.a * (1.0 - _action_blend)), 3.0, true)
	draw_colored_polygon(points, Color(shadow, shadow.a * _action_blend))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (1.0 + _lift * 0.008))
	draw_polyline(line, Color(OUTLINE, 1.0 - _action_blend), 3.0, true)
	draw_polyline(chevron, Color(OUTLINE, 1.0 - _action_blend), 3.0, true)
	draw_colored_polygon(points, Color(FILL.lerp(ACTION_FILL, _action_blend), _action_blend))
	points.append(points[0])
	draw_polyline(points, Color(OUTLINE, _action_blend), 2.5, true)
	for angle: float in [-0.65, 0.0, 0.65]:
		var ray := Vector2.from_angle(angle)
		draw_line(ray * 6.0, ray * 10.0, Color(OUTLINE, _action_blend * 0.7), 2.0, true)

func inspection() -> Dictionary:
	return {"instance_id":get_instance_id(), "tip":_tip, "destination":_destination,
		"position":position, "floating_offset":position - _tip, "length":_length,
		"target_length":_target_length, "requires_action":_requires_action,
		"action_blend":_action_blend, "lift":_lift, "depth_scale":1.0 + _lift * 0.008}
