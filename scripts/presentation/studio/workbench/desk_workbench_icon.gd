@tool
extends Control

const INK := Color("594d3f", .76)
const STROKE := 1.4

var kind := "language"


func _init() -> void:
	custom_minimum_size = Vector2(24, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var factor := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2.ONE * 24.0 * factor) * .5, 0, Vector2.ONE * factor)
	match kind:
		"language":
			draw_arc(Vector2(12, 12), 8, 0, TAU, 32, INK, STROKE, true)
			var meridian := PackedVector2Array()
			for index in 33:
				var angle := float(index) * TAU / 32.0
				meridian.append(Vector2(12 + sin(angle) * 3.5, 12 + cos(angle) * 8))
			_line(meridian)
			_line([Vector2(4, 12), Vector2(20, 12)])
		"group":
			draw_circle(Vector2(8, 8), 3, INK, false, STROKE, true)
			draw_circle(Vector2(17, 9), 2.5, INK, false, STROKE, true)
			draw_arc(Vector2(8, 20), 6, PI, TAU, 20, INK, STROKE, true)
			draw_arc(Vector2(17, 20), 4.5, PI, TAU, 16, INK, STROKE, true)
		"topic":
			_line([Vector2(10, 4), Vector2(7, 20)])
			_line([Vector2(17, 4), Vector2(14, 20)])
			_line([Vector2(4, 9), Vector2(21, 9)])
			_line([Vector2(3, 15), Vector2(20, 15)])
		"stance":
			_line([Vector2(12, 3), Vector2(21, 12), Vector2(12, 21), Vector2(3, 12), Vector2(12, 3)])
			_line([Vector2(12, 6), Vector2(12, 18)])
			_line([Vector2(6, 12), Vector2(18, 12)])
			draw_circle(Vector2(12, 12), 2, INK)
		"pragmatic":
			_line([Vector2(4, 4), Vector2(20, 4), Vector2(20, 16), Vector2(12, 16), Vector2(8, 20), Vector2(8, 16), Vector2(4, 16), Vector2(4, 4)])
			for x in [8, 12, 16]: draw_circle(Vector2(x, 10), .8, INK)
		"spread":
			_line([Vector2(6, 11), Vector2(16, 6)])
			_line([Vector2(6, 13), Vector2(16, 18)])
			for point: Vector2 in [Vector2(4, 12), Vector2(18, 5), Vector2(18, 19)]:
				draw_circle(point, 2.5, INK, false, STROKE, true)
		"expression":
			for x in [0, 10]:
				_line([Vector2(10 + x, 6), Vector2(7 + x, 6), Vector2(4 + x, 10), Vector2(4 + x, 17), Vector2(10 + x, 17), Vector2(10 + x, 11), Vector2(4 + x, 11)])
		"meaning":
			draw_arc(Vector2(12, 9), 6, PI * .65, PI * 2.35, 32, INK, STROKE, true)
			_line([Vector2(7, 12), Vector2(9, 16), Vector2(15, 16), Vector2(17, 12)])
			_line([Vector2(9, 19), Vector2(15, 19)])
			_line([Vector2(10, 22), Vector2(14, 22)])
		"check":
			draw_arc(Vector2(12, 12), 9, 0, TAU, 32, INK, STROKE, true)
			_line([Vector2(7, 12), Vector2(10, 15), Vector2(17, 8)])
		"lock":
			draw_arc(Vector2(12, 9), 5, PI, TAU, 20, INK, STROKE, true)
			_line([Vector2(7, 9), Vector2(7, 11)])
			_line([Vector2(17, 9), Vector2(17, 11)])
			draw_rect(Rect2(5, 11, 14, 10), INK, false, STROKE, true)
			draw_circle(Vector2(12, 15), 1, INK)
			_line([Vector2(12, 15), Vector2(12, 18)])
		"requires":
			_line([Vector2(4, 5), Vector2(10, 5), Vector2(10, 12), Vector2(18, 12)])
			_line([Vector2(4, 19), Vector2(10, 19), Vector2(10, 12)])
			_line([Vector2(15, 8), Vector2(19, 12), Vector2(15, 16)])
		"cost":
			draw_arc(Vector2(12, 12), 8, 0, TAU, 32, INK, STROKE, true)
			_line([Vector2(8, 16), Vector2(8, 8), Vector2(12, 12), Vector2(16, 8), Vector2(16, 16)])
		"balance":
			_line([Vector2(4, 7), Vector2(19, 7), Vector2(19, 20), Vector2(4, 20), Vector2(4, 7), Vector2(16, 4), Vector2(16, 7)])
			draw_rect(Rect2(14, 11, 7, 5), INK, false, STROKE, true)
			draw_circle(Vector2(17, 13.5), .8, INK)


func _line(points: PackedVector2Array) -> void:
	draw_polyline(points, INK, STROKE, true)
