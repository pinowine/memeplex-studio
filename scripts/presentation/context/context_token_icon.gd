extends RefCounted

static func _stroke(canvas: CanvasItem, points: Array, center: Vector2, radius: float, color: Color, width: float) -> void:
	var path := PackedVector2Array()
	for point: Vector2 in points: path.append(center + point * radius)
	canvas.draw_polyline(path, color, width, true)

static func draw(canvas: CanvasItem, id: String, center: Vector2, radius: float, color: Color, width: float) -> void:
	match id:
		"freedom":
			canvas.draw_rect(Rect2(center+Vector2(-.65,-.05)*radius,Vector2(1.3,.95)*radius),color,false,width)
			canvas.draw_arc(center+Vector2(.2,-.1)*radius,radius*.55,PI,TAU,24,color,width,true)
			canvas.draw_line(center+Vector2(-.35,-.1)*radius,center+Vector2(-.35,-.45)*radius,color,width,true)
			canvas.draw_circle(center+Vector2(0,.3)*radius,width,color)
		"authority":
			_stroke(canvas,[Vector2(-.65,-.8),Vector2(.15,-.8),Vector2(.15,-.3),Vector2(-.65,-.3),Vector2(-.65,-.8)],center,radius,color,width)
			_stroke(canvas,[Vector2(-.25,-.3),Vector2(.55,.55)],center,radius,color,width*1.4)
			_stroke(canvas,[Vector2(-.8,.9),Vector2(.8,.9)],center,radius,color,width*1.8)
		"equality":
			for y in [-.25,.3]: _stroke(canvas,[Vector2(-.8,y),Vector2(.8,y)],center,radius,color,width*1.5)
			for x in [-.55,.55]: canvas.draw_circle(center+Vector2(x,-.75)*radius,radius*.13,color)
		"hierarchy":
			canvas.draw_rect(Rect2(center+Vector2(-.25,-.95)*radius,Vector2(.5,.45)*radius),color,false,width)
			_stroke(canvas,[Vector2(0,-.5),Vector2(0,0),Vector2(-.65,0),Vector2(-.65,.45)],center,radius,color,width)
			_stroke(canvas,[Vector2(0,0),Vector2(.65,0),Vector2(.65,.45)],center,radius,color,width)
			for x in [-.65,.65]: canvas.draw_rect(Rect2(center+Vector2(x-.23,.45)*radius,Vector2(.46,.45)*radius),color,false,width)
		"sincere":
			_stroke(canvas,[Vector2(0,.85),Vector2(-.8,.1),Vector2(-.8,-.4),Vector2(-.45,-.7),Vector2(0,-.3),Vector2(.45,-.7),Vector2(.8,-.4),Vector2(.8,.1),Vector2(0,.85)],center,radius,color,width*1.2)
		"ironic":
			canvas.draw_arc(center,radius*.85,0,TAU,32,color,width,true)
			canvas.draw_circle(center+Vector2(-.3,-.25)*radius,radius*.1,color)
			_stroke(canvas,[Vector2(.12,-.25),Vector2(.52,-.25)],center,radius,color,width)
			_stroke(canvas,[Vector2(-.4,.45),Vector2(.15,.45),Vector2(.5,.15)],center,radius,color,width)
		"support":
			_stroke(canvas,[Vector2(-.7,.8),Vector2(-.7,-.15),Vector2(-.25,-.15),Vector2(.05,-.85),Vector2(.35,-.75),Vector2(.25,-.15),Vector2(.85,-.15),Vector2(.65,.8),Vector2(-.7,.8)],center,radius,color,width)
			_stroke(canvas,[Vector2(-.35,-.15),Vector2(-.35,.8)],center,radius,color,width)
		"opposition":
			_stroke(canvas,[Vector2(-.35,-.85),Vector2(.35,-.85),Vector2(.85,-.35),Vector2(.85,.35),Vector2(.35,.85),Vector2(-.35,.85),Vector2(-.85,.35),Vector2(-.85,-.35),Vector2(-.35,-.85)],center,radius,color,width)
			_stroke(canvas,[Vector2(-.35,-.35),Vector2(.35,.35)],center,radius,color,width*1.3)
			_stroke(canvas,[Vector2(.35,-.35),Vector2(-.35,.35)],center,radius,color,width*1.3)
