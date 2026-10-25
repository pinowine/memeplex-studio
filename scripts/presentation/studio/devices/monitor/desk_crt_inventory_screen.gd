class_name DeskCRTInventoryScreen
extends Control

signal token_pressed(token_id: String, viewport_point: Vector2)

const IDS := {"stance":["freedom", "authority", "equality", "hierarchy"], "pragmatic":["sincere", "ironic", "support", "opposition"]}
const SEGMENTS := [[0,1,2,4,5,6], [2,5], [0,2,3,4,6], [0,2,3,5,6], [1,2,3,5], [0,1,3,5,6], [0,1,3,4,5,6], [0,2,5], [0,1,2,3,4,5,6], [0,1,2,3,5,6]]
const INK := Color("9dc996")
const DIM := Color("38533a")
var _mode := "stance"
var _balances: Dictionary = {}
var _enabled := true
var _hover := -1

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void: _hover = -1; queue_redraw())
	resized.connect(queue_redraw)

func sync_inventory(mode_id: String, balances: Dictionary, enabled: bool) -> void:
	_mode = mode_id if mode_id in IDS else "stance"
	_balances = balances.duplicate(true)
	_enabled = enabled
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	queue_redraw()

func cell_rect(index: int) -> Rect2:
	var padding := minf(size.x, size.y) * 0.065
	var area := Rect2(Vector2.ONE * padding, (size - Vector2.ONE * padding * 2.0).max(Vector2.ZERO))
	var gap := minf(size.x, size.y) * 0.045
	var cell := (area.size - Vector2.ONE * gap) * 0.5
	return Rect2(area.position + Vector2(index % 2, index / 2) * (cell + Vector2.ONE * gap), cell)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = -1
		for index in 4:
			if cell_rect(index).has_point(event.position): _hover = index
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _enabled:
		for index in 4:
			var id: String = IDS[_mode][index]
			if cell_rect(index).has_point(event.position) and int(_balances.get(id, 0)) > 0:
				token_pressed.emit(id, get_global_transform_with_canvas() * event.position)
				accept_event()
				return

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("06140b"))
	var center := size * 0.5
	var inset := minf(size.x, size.y) * 0.035
	draw_line(Vector2(center.x, inset), Vector2(center.x, size.y - inset), DIM, 1.0, true)
	draw_line(Vector2(inset, center.y), Vector2(size.x - inset, center.y), DIM, 1.0, true)
	for index in 4:
		var rect := cell_rect(index)
		var id: String = IDS[_mode][index]
		var color := INK if int(_balances.get(id, 0)) > 0 else Color("48674b")
		if _hover == index:
			draw_rect(rect.grow(1), Color(0.65, 0.8, 0.6, 0.07), true)
			draw_rect(rect, Color(0.65, 0.8, 0.6, 0.5), false, 1.0)
		var symbol_center := rect.position + rect.size * Vector2(0.20, 0.5)
		_symbol(id, symbol_center, minf(rect.size.x * 0.15, rect.size.y * 0.28), color)
		var digits := Rect2(rect.position + rect.size * Vector2(0.40, 0.19), rect.size * Vector2(0.55, 0.62))
		_number(str(int(_balances.get(id, 0))), digits, color)
	for line in range(0, int(size.y), 3):
		draw_line(Vector2(0, line), Vector2(size.x, line), Color(0, 0, 0, 0.07))

func _number(text: String, rect: Rect2, color: Color) -> void:
	var width := minf(rect.size.y * 0.55, rect.size.x / maxf(1.0, text.length() * 1.18))
	var height := minf(rect.size.y, width / 0.55)
	var origin := rect.get_center() - Vector2(width * (text.length() * 1.18 - 0.18), height) * 0.5
	for index in text.length():
		_digit(int(text.substr(index, 1)), Rect2(origin + Vector2(index * width * 1.18, 0), Vector2(width, height)), color)

func _digit(value: int, rect: Rect2, color: Color) -> void:
	var a := rect.position
	var b := rect.end
	var mid := rect.get_center().y
	var inset := rect.size.x * 0.14
	var lines := [
		[Vector2(a.x + inset, a.y), Vector2(b.x - inset, a.y)],
		[Vector2(a.x, a.y + inset), Vector2(a.x, mid - inset)],
		[Vector2(b.x, a.y + inset), Vector2(b.x, mid - inset)],
		[Vector2(a.x + inset, mid), Vector2(b.x - inset, mid)],
		[Vector2(a.x, mid + inset), Vector2(a.x, b.y - inset)],
		[Vector2(b.x, mid + inset), Vector2(b.x, b.y - inset)],
		[Vector2(a.x + inset, b.y), Vector2(b.x - inset, b.y)]
	]
	var thickness := maxf(0.65, rect.size.x * 0.13)
	for index in 7:
		draw_line(lines[index][0], lines[index][1], color if index in SEGMENTS[value] else Color(color, 0.08), thickness, true)

func _stroke(points: Array, center: Vector2, radius: float, color: Color, width: float) -> void:
	var path := PackedVector2Array()
	for point: Vector2 in points: path.append(center + point * radius)
	draw_polyline(path, color, width, true)

func _symbol(id: String, center: Vector2, radius: float, color: Color) -> void:
	var width := maxf(0.8, radius * 0.09)
	match id:
		"freedom":
			_stroke([Vector2(-0.85,-0.2),Vector2(-0.34,0.08),Vector2(0,-0.52),Vector2(0.34,0.08),Vector2(0.85,-0.2)],center,radius,color,width)
			_stroke([Vector2(-0.85,-0.2),Vector2(-0.26,0.55),Vector2(0,0.12),Vector2(0.26,0.55),Vector2(0.85,-0.2)],center,radius,color,width)
		"authority":
			_stroke([Vector2(-0.6,0.8),Vector2(-0.6,-0.35),Vector2(-0.28,-0.35),Vector2(-0.28,-0.76),Vector2(0.28,-0.76),Vector2(0.28,-0.35),Vector2(0.6,-0.35),Vector2(0.6,0.8),Vector2(-0.6,0.8)],center,radius,color,width)
			_stroke([Vector2(0,-0.12),Vector2(0,0.62)],center,radius,color,width)
		"equality":
			for y in [-0.27,0.27]: draw_line(center+Vector2(-0.8,y)*radius,center+Vector2(0.8,y)*radius,color,width,true)
		"hierarchy":
			for row in 3:
				var half := 0.25+row*0.25
				draw_line(center+Vector2(-half,-0.7+row*0.52)*radius,center+Vector2(half,-0.7+row*0.52)*radius,color,width,true)
			draw_line(center-Vector2(0,radius*0.9),center+Vector2(0,radius*0.68),color,width,true)
		"sincere":
			_stroke([Vector2(0,0.8),Vector2(-0.72,0.04),Vector2(-0.6,-0.55),Vector2(0,-0.25),Vector2(0.6,-0.55),Vector2(0.72,0.04),Vector2(0,0.8)],center,radius,color,width)
		"ironic":
			draw_arc(center,radius*0.8,-PI*0.86,PI*0.84,28,color,width,true)
			_stroke([Vector2(-0.62,0.5),Vector2(0.6,-0.4),Vector2(0.65,0.1)],center,radius,color,width)
			for x in [-0.3,0.3]: draw_circle(center+Vector2(x,-0.24)*radius,radius*0.085,color)
		"support": _stroke([Vector2(-0.8,0.3),Vector2(-0.3,0.7),Vector2(0.8,-0.65)],center,radius,color,width*1.15)
		"opposition":
			draw_arc(center,radius*0.8,0,TAU,28,color,width,true)
			draw_line(center+Vector2(-0.58,0.58)*radius,center+Vector2(0.58,-0.58)*radius,color,width,true)

func inspection() -> Dictionary:
	var cells: Array[Dictionary] = []
	for index in 4:
		var id: String = IDS[_mode][index]
		cells.append({"id":id,"count":int(_balances.get(id,0)),"digits":str(int(_balances.get(id,0))),"rect":cell_rect(index)})
	return {"mode":_mode,"cells":cells,"hovered":_hover,"enabled":_enabled,"digits_renderer":"vector_seven_segment","symbol_renderer":"vector_direction_symbols","quad_layout":"two_by_two","mutates_inventory":false}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()
