extends Node2D

const FOLLOW_RATE := 8.0
const FLOAT_AMPLITUDE := 1.2
const FLOAT_PERIOD := 2.4
const FILL := Color(1.0, 0.84, 0.43)
const OUTLINE := Color.BLACK

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
	var arrow := PackedVector2Array([
		Vector2(-_length, -5), Vector2(-16, -5),
		Vector2(-16, -13), Vector2.ZERO, Vector2(-16, 13),
		Vector2(-16, 5), Vector2(-_length, 5)])
	var hand_scale := minf(1.0, _length / 36.0)
	var hand := PackedVector2Array([
		Vector2(-36, -5), Vector2(-29, -5), Vector2(-25, -11),
		Vector2(-22, -12), Vector2(-19, -10), Vector2(-18, -7),
		Vector2(-20, -4), Vector2(-4, -4), Vector2(-1, -3),
		Vector2.ZERO, Vector2(-1, 3), Vector2(-4, 4),
		Vector2(-15, 4), Vector2(-13, 6), Vector2(-13, 9),
		Vector2(-16, 11), Vector2(-15, 13), Vector2(-17, 16),
		Vector2(-22, 17), Vector2(-28, 15), Vector2(-31, 10),
		Vector2(-36, 10)])
	for index in hand.size(): hand[index] *= hand_scale
	hand[0].x = -_length
	hand[hand.size() - 1].x = -_length
	# A stationary shadow gives the small lift a sense of height above the desk.
	var shadow_offset := Vector2(2, 4 + _lift).rotated(-rotation)
	draw_set_transform(shadow_offset, 0.0, Vector2.ONE * (1.0 - _lift * 0.012))
	var shadow := Color(OUTLINE, 0.14 - _lift * 0.02)
	draw_colored_polygon(arrow, Color(shadow, shadow.a * (1.0 - _action_blend)))
	draw_colored_polygon(hand, Color(shadow, shadow.a * _action_blend))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (1.0 + _lift * 0.008))
	_draw_pointer(arrow, 1.0 - _action_blend)
	_draw_pointer(hand, _action_blend)
	var crease := Color(OUTLINE, _action_blend)
	for line: Vector4 in [Vector4(-15, 4, -23, 3), Vector4(-16, 10, -23, 9), Vector4(-18, 15, -24, 13), Vector4(-31, -4, -31, 9)]:
		draw_line(Vector2(line.x, line.y) * hand_scale, Vector2(line.z, line.w) * hand_scale, crease, 1.5 * hand_scale, true)

func _draw_pointer(points: PackedVector2Array, opacity: float) -> void:
	draw_colored_polygon(points, Color(FILL, opacity))
	points.append(points[0])
	draw_polyline(points, Color(OUTLINE, opacity), 2.5, true)

func inspection() -> Dictionary:
	return {"instance_id":get_instance_id(), "tip":_tip, "destination":_destination,
		"position":position, "floating_offset":position - _tip, "length":_length,
		"target_length":_target_length, "requires_action":_requires_action,
		"action_blend":_action_blend, "lift":_lift, "depth_scale":1.0 + _lift * 0.008}
