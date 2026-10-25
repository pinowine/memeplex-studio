class_name DeskBlobFeedback
extends RefCounted

const INK := Color("485046")
const ACTIVE := Color("9d503c")
var _states: Dictionary = {}
var _hover := ""
var _pressed := ""
var _selected := ""
var _enabled := true
var _disabled: Dictionary = {}


func set_disabled(id: String, value: bool) -> void:
	_disabled[id] = value


func set_hover(id: String) -> void:
	_hover = id if _enabled else ""


func set_pressed(id: String) -> void:
	_pressed = id if _enabled else ""


func set_selected(id: String) -> void:
	_selected = id


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_hover = ""
		_pressed = ""


func tick(delta: float, ids: Array) -> bool:
	var changed := false
	var blend := 1.0 - exp(-maxf(delta, 0.0) * 15.0)
	for raw: Variant in ids:
		var id := str(raw)
		var before: Vector3 = _states.get(id, Vector3.ZERO)
		var target := Vector3(1.0 if id == _hover else 0.0, 1.0 if id == _pressed else 0.0, 1.0 if id == _selected else 0.0)
		var after := before.lerp(target, blend)
		if after.distance_to(target) < .001: after = target
		_states[id] = after
		changed = changed or before != after
	return changed


func sample(id: String) -> Dictionary:
	var state: Vector3 = _states.get(id, Vector3.ZERO)
	return {"hover":state.x,"press":state.y,"selected":state.z,"disabled":not _enabled or bool(_disabled.get(id,false))}


func paint(canvas: Control, point: Vector2, extent: Vector2, id: String) -> void:
	var state: Vector3 = _states.get(id, Vector3.ZERO)
	var rect := Rect2(point - extent * .5, extent).grow(state.x * 2.0 - state.y * 1.5)
	var color := INK.lerp(ACTIVE, state.z * .8 + state.y * .2)
	color.a = (.52 + state.x * .26 + state.z * .16) * (1.0 if _enabled and not bool(_disabled.get(id,false)) else .34)
	# Short uneven corners leave the neuron underneath unobscured.
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x,0), rect.end, rect.position + Vector2(0,rect.size.y)]:
		var inward := rect.get_center() - corner
		canvas.draw_line(corner, corner + Vector2(signf(inward.x) * 7.0, -.35), color, .8 + state.y * .25, true)
		canvas.draw_line(corner, corner + Vector2(.3, signf(inward.y) * 7.0), color, .8 + state.y * .25, true)
	if state.x > .02 or state.z > .02:
		canvas.draw_line(rect.position + Vector2(9,-2), rect.position + Vector2(rect.size.x-8,-1.6), Color(color,.25 * maxf(state.x,state.z)), .55, true)


func inspection() -> Dictionary:
	var values := {}
	for id: String in _states: values[id] = sample(id)
	return {"hovered":_hover,"pressed":_pressed,"selected":_selected,"enabled":_enabled,"states":values,"style":"handdraw_tracking_corners"}
