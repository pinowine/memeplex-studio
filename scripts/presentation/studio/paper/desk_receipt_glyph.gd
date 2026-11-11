extends RefCounted

const STROKE := 1.2

static func draw(canvas: CanvasItem, rect: Rect2, kind: String, color: Color) -> void:
	var factor := minf(rect.size.x,rect.size.y)/24.0
	canvas.draw_set_transform(rect.get_center()-Vector2.ONE*12.0*factor,0,Vector2.ONE*factor)
	match kind:
		"language":
			canvas.draw_arc(Vector2(12,12),8,0,TAU,32,color,STROKE,true)
			var meridian := PackedVector2Array()
			for index in 33:
				var angle := float(index)*TAU/32.0
				meridian.append(Vector2(12+sin(angle)*3.5,12+cos(angle)*8))
			_line(canvas,meridian,color)
			_line(canvas,[Vector2(4,12),Vector2(20,12)],color)
		"group":
			canvas.draw_circle(Vector2(8,8),3,color,false,STROKE,true)
			canvas.draw_circle(Vector2(17,9),2.5,color,false,STROKE,true)
			canvas.draw_arc(Vector2(8,20),6,PI,TAU,20,color,STROKE,true)
			canvas.draw_arc(Vector2(17,20),4.5,PI,TAU,16,color,STROKE,true)
		"topic":
			for x in [9,16]: _line(canvas,[Vector2(x+1,4),Vector2(x-2,20)],color)
			for y in [9,15]: _line(canvas,[Vector2(4,y),Vector2(20,y)],color)
		"stance", "stance_token":
			_line(canvas,[Vector2(12,3),Vector2(21,12),Vector2(12,21),Vector2(3,12),Vector2(12,3)],color)
			_line(canvas,[Vector2(12,6),Vector2(12,18)],color)
			_line(canvas,[Vector2(6,12),Vector2(18,12)],color)
			canvas.draw_circle(Vector2(15,9),2,color)
		"pragmatic", "pragmatic_token", "mentor":
			_line(canvas,[Vector2(4,4),Vector2(20,4),Vector2(20,16),Vector2(11,16),Vector2(6,21),Vector2(6,16),Vector2(4,16),Vector2(4,4)],color)
			for x in [8,12,16]: canvas.draw_circle(Vector2(x,10),1,color)
		"module", "patch", "reward":
			var centre := Vector2(12,12)
			for tip: Vector2 in [Vector2(5,5),Vector2(20,7),Vector2(18,20),Vector2(4,17)]:
				_line(canvas,[centre,centre.lerp(tip,.55)+Vector2(1,-1),tip],color)
				canvas.draw_circle(tip,1.7,color)
			canvas.draw_circle(centre,3.5,Color(color,color.a*.16))
			canvas.draw_circle(centre,3.5,color,false,STROKE,true)
			canvas.draw_circle(centre,1.2,color)
		"impact":
			_line(canvas,[Vector2(4,4),Vector2(4,20),Vector2(21,20)],color)
			_line(canvas,[Vector2(7,16),Vector2(12,11),Vector2(15,14),Vector2(21,6)],color)
			_line(canvas,[Vector2(16,6),Vector2(21,6),Vector2(21,11)],color)
		"device", "effects":
			canvas.draw_arc(Vector2(12,12),6,0,TAU,32,color,STROKE,true)
			canvas.draw_arc(Vector2(12,12),2.5,0,TAU,24,color,STROKE,true)
			for index in 8:
				var direction := Vector2.from_angle(float(index)*TAU/8.0)
				_line(canvas,[Vector2(12,12)+direction*6,Vector2(12,12)+direction*9],color)
		"clock":
			canvas.draw_arc(Vector2(12,12),8,0,TAU,32,color,STROKE,true)
			_line(canvas,[Vector2(12,6),Vector2(12,12),Vector2(16,14)],color)
			canvas.draw_circle(Vector2(12,12),1,color)
		"monitor":
			canvas.draw_rect(Rect2(3,4,18,13),color,false,STROKE)
			canvas.draw_rect(Rect2(6,7,12,7),Color(color,color.a*.12))
			_line(canvas,[Vector2(12,17),Vector2(12,21)],color)
			_line(canvas,[Vector2(8,21),Vector2(16,21)],color)
		"fax", "printer":
			_line(canvas,[Vector2(7,9),Vector2(7,3),Vector2(17,3),Vector2(17,9)],color)
			_line(canvas,[Vector2(7,18),Vector2(3,18),Vector2(3,9),Vector2(21,9),Vector2(21,18),Vector2(17,18)],color)
			canvas.draw_rect(Rect2(7,14,10,7),color,false,STROKE)
			canvas.draw_circle(Vector2(17.5,11.5),.8,color)
			_line(canvas,[Vector2(9,17),Vector2(15,17)],color)
		"speed":
			var triangle := PackedVector2Array([Vector2(8,4),Vector2(20,12),Vector2(8,20)])
			canvas.draw_colored_polygon(triangle,Color(color,color.a*.14))
			_line(canvas,[Vector2(8,4),Vector2(20,12),Vector2(8,20),Vector2(8,4)],color)
		_:
			_line(canvas,[Vector2(5,3),Vector2(15,3),Vector2(20,8),Vector2(20,21),Vector2(5,21),Vector2(5,3)],color)
			_line(canvas,[Vector2(15,3),Vector2(15,8),Vector2(20,8)],color)
			for y in [12,16]: _line(canvas,[Vector2(8,y),Vector2(16,y)],color)
	canvas.draw_set_transform(Vector2.ZERO)

static func _line(canvas: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	canvas.draw_polyline(points,color,STROKE,true)
