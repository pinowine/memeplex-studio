extends Control
class_name DeskModulePaperClip

class Wire extends Control:
	func _draw() -> void:
		var outer := PackedVector2Array()
		for index in 41:
			var angle := PI + float(index) * PI / 40.0
			outer.append(Vector2(12,12) + Vector2(cos(angle)*9,sin(angle)*9))
		outer.append(Vector2(21,37))
		for index in 41:
			var angle := float(index) * PI / 40.0
			outer.append(Vector2(14,37) + Vector2(cos(angle)*7,sin(angle)*7))
		outer.append(Vector2(7,15))
		draw_set_transform(Vector2(.65,1.0))
		draw_polyline(outer,Color(0.13,0.12,0.10,0.28),3.1,true)
		draw_set_transform(Vector2.ZERO)
		draw_polyline(outer,Color("594d3f"),2.3,true)
		draw_polyline(outer,Color("b2a08a"),1.3,true)
		draw_polyline(outer,Color("e0d4b8"),0.45,true)
		draw_line(Vector2(10,32),Vector2(10,16),Color("746552"),1.6,true)

var _wire: Control

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_wire = Wire.new()
	_wire.name = "FrontWire"
	_wire.position = Vector2(size.x-25,-1)
	_wire.size = Vector2(24,48)
	_wire.rotation = -.075
	_wire.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_wire)
	resized.connect(func() -> void: _wire.position.x=size.x-25)

func bring_front() -> void:
	if is_instance_valid(_wire): move_child(_wire,get_child_count()-1)

func mouth() -> Vector2:
	return get_global_transform_with_canvas()*Vector2(size.x-13,27)

func accepts(point: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse()*point
	return is_visible_in_tree() and Rect2(-8,0,size.x+16,104).has_point(local)
