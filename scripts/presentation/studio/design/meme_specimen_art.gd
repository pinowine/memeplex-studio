@tool
extends Control

const FONT := preload("res://assets/image/fonts/handwritten_font.tres")
const INK := Color("514b40")
const SOFT_INK := Color("a69a81")
const PAPER := Color("f3ecd9")
const MARK := Color("a14c3d")
const COAT := Color("c6a16c")
const MUZZLE := Color("eee0bb")

var _illustration := ""
var _patches: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(0, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	resized.connect(queue_redraw)

func configure(composed: Dictionary, patches: Array = []) -> void:
	_illustration = str(composed.get("illustration", ""))
	_patches = (patches if not patches.is_empty() else composed.get("patch_ids", [])).duplicate()
	visible = _illustration.begins_with("versailles_") or _illustration.begins_with("cheems_")
	queue_redraw()

func inspection() -> Dictionary:
	return {"illustration":_illustration, "visible":visible, "patch_ids":_patches.duplicate(),
		"panels":_panel_rects().size() if visible else 0, "annotation":"module_boundary" in _patches,
		"renderer":"procedural_specimen", "minimum_size":custom_minimum_size, "mouse_filter":mouse_filter}

func _panel_rects() -> Array[Rect2]:
	var area := Rect2(Vector2(3, 3), (size - Vector2(6, 6)).max(Vector2.ZERO))
	if "module_relation" not in _patches: return [area]
	var half := Vector2(maxf(0, (area.size.x - 12) * 0.5), area.size.y)
	return [Rect2(area.position, half), Rect2(area.position + Vector2(half.x + 12, 0), half)]

func _draw() -> void:
	if not visible: return
	var panels := _panel_rects()
	for index in panels.size():
		var area: Rect2 = panels[index]
		var scale_factor := minf(area.size.x / 140.0, area.size.y / 94.0)
		if scale_factor <= 0: continue
		draw_set_transform(area.get_center() - Vector2(70, 47) * scale_factor, 0, Vector2.ONE * scale_factor)
		if _illustration.begins_with("versailles_"): _exam(index)
		else: _cheems(index, panels.size() > 1)
		draw_set_transform(Vector2.ZERO)
	if panels.size() == 2:
		draw_line(Vector2(size.x * 0.5, 10), Vector2(size.x * 0.5, size.y - 10), Color(SOFT_INK, 0.5), 1, true)

func _exam(panel: int) -> void:
	_shape([Vector2(34, 4), Vector2(103, 7), Vector2(109, 89), Vector2(29, 87)], PAPER, INK)
	_line([Vector2(38, 20), Vector2(91, 22)], SOFT_INK)
	var grade_width := FONT.get_string_size("100/100", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(FONT, Vector2(70 - grade_width * 0.5, 39), "100/100", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MARK)
	for row in 4:
		var y := 48.0 + row * 8
		_line([Vector2(38, y), Vector2(48, y - 1), Vector2(57, y + 1), Vector2(67, y), Vector2(82 - row * 2, y + 0.5)], Color(INK, 0.64), 0.9)
		_line([Vector2(87, y - 1), Vector2(90, y + 2), Vector2(97, y - 4)], MARK, 1.1)
	if panel == 0 and "module_relation" in _patches:
		_line([Vector2(42, 60), Vector2(74, 66), Vector2(44, 66), Vector2(71, 60)], Color(INK, 0.55), 0.8)
	if "module_boundary" in _patches:
		draw_arc(Vector2(72, 34), 26, 0.07, TAU - 0.06, 38, Color(MARK, 0.8), 1.0, true)
		_line([Vector2(96, 43), Vector2(117, 51), Vector2(111, 54)], MARK, 1.0)
	if "module_stance" in _patches:
		_line([Vector2(113, 18), Vector2(119, 15), Vector2(124, 19), Vector2(122, 24), Vector2(117, 28), Vector2(118, 33)], INK)
		draw_circle(Vector2(118, 38), 1.2, INK)
	if _illustration.ends_with("training"):
		_shape([Vector2(8, 52), Vector2(24, 52), Vector2(24, 75), Vector2(8, 75)], Color("ded6bd"), SOFT_INK)
		draw_circle(Vector2(16, 59), 3, INK)
		_line([Vector2(12, 67), Vector2(20, 67)], INK)
	elif _illustration.ends_with("quiz"):
		draw_arc(Vector2(17, 61), 9, 0, TAU, 28, SOFT_INK, 1, true)
		_line([Vector2(10, 73), Vector2(24, 73), Vector2(26, 80), Vector2(8, 80)], INK)

func _cheems(panel: int, comparison: bool) -> void:
	var confident := comparison and panel == 0
	var head_offset := Vector2(0, -3 if confident else 2)
	_ellipse(Vector2(66, 82), Vector2(40, 8), Color(INK, 0.08))
	_shape([Vector2(42, 62), Vector2(89, 60), Vector2(102, 80), Vector2(91, 87), Vector2(40, 86), Vector2(30, 77)], COAT, INK)
	_shape([Vector2(42, 34), Vector2(39, 8), Vector2(61, 20), Vector2(80, 20), Vector2(99, 8), Vector2(99, 37)], COAT, INK, head_offset)
	_shape([Vector2(45, 27), Vector2(44, 14), Vector2(57, 22)], Color("927154"), Color.TRANSPARENT, head_offset)
	_shape([Vector2(85, 22), Vector2(94, 15), Vector2(94, 29)], Color("927154"), Color.TRANSPARENT, head_offset)
	_shape([Vector2(40, 32), Vector2(50, 23), Vector2(72, 20), Vector2(92, 27), Vector2(102, 43), Vector2(96, 63), Vector2(81, 73), Vector2(53, 72), Vector2(35, 59), Vector2(33, 44)], COAT, INK, head_offset)
	_ellipse(Vector2(67, 56) + head_offset, Vector2(27, 16), MUZZLE)
	_ellipse(Vector2(46, 47) + head_offset, Vector2(10, 10), MUZZLE)
	_ellipse(Vector2(87, 48) + head_offset, Vector2(9, 10), MUZZLE)
	if confident:
		_line([Vector2(45, 39), Vector2(51, 36), Vector2(57, 39)], INK, 1.6, head_offset)
		_line([Vector2(78, 39), Vector2(84, 36), Vector2(90, 39)], INK, 1.6, head_offset)
	else:
		_line([Vector2(44, 39), Vector2(51, 42), Vector2(58, 41)], INK, 1.5, head_offset)
		_line([Vector2(78, 41), Vector2(84, 43), Vector2(90, 40)], INK, 1.5, head_offset)
		draw_circle(Vector2(53, 43) + head_offset, 1.8, INK)
		draw_circle(Vector2(83, 44) + head_offset, 1.8, INK)
	_shape([Vector2(63, 50), Vector2(73, 50), Vector2(70, 55), Vector2(66, 55)], INK, INK, head_offset)
	_line([Vector2(68, 55), Vector2(68, 61), Vector2(61, 63), Vector2(56, 61)], INK, 1.1, head_offset)
	_line([Vector2(68, 61), Vector2(76, 64), Vector2(81, 62)], INK, 1.1, head_offset)
	_line([Vector2(50, 77), Vector2(48, 85)], SOFT_INK)
	_line([Vector2(84, 76), Vector2(88, 85)], SOFT_INK)
	_scene_prop()
	if "module_boundary" in _patches:
		_line([Vector2(96, 49), Vector2(111, 42), Vector2(125, 42)], MARK)
		draw_arc(Vector2(85, 43) + head_offset, 10, -0.6, 3.8, 24, Color(MARK, 0.75), 0.9, true)

func _scene_prop() -> void:
	if _illustration.ends_with("meeting"):
		_shape([Vector2(94, 66), Vector2(128, 61), Vector2(132, 81), Vector2(98, 87)], PAPER, INK)
		_line([Vector2(101, 70), Vector2(122, 67)], SOFT_INK)
		_line([Vector2(103, 76), Vector2(120, 73)], SOFT_INK)
	elif _illustration.ends_with("presentation"):
		_shape([Vector2(91, 68), Vector2(127, 68), Vector2(123, 91), Vector2(95, 91)], Color("bcb299"), INK)
		_line([Vector2(115, 67), Vector2(115, 58), Vector2(110, 55)], INK)
		draw_circle(Vector2(108, 54), 2.2, INK)
	else:
		_shape([Vector2(97, 11), Vector2(134, 11), Vector2(134, 33), Vector2(117, 33), Vector2(109, 40), Vector2(109, 33), Vector2(97, 33)], PAPER, INK)
		if _illustration.ends_with("fan_chat"):
			_line([Vector2(105, 19), Vector2(125, 19)], SOFT_INK)
			_line([Vector2(105, 26), Vector2(120, 26)], SOFT_INK)
		else:
			for x in [106, 115, 124]: draw_circle(Vector2(x, 22), 1.3, INK)

func _line(points: Array, color: Color, width: float = 1.15, offset: Vector2 = Vector2.ZERO) -> void:
	var path := PackedVector2Array()
	for point: Vector2 in points: path.append(point + offset)
	draw_polyline(path, color, width, true)

func _shape(points: Array, fill: Color, stroke: Color, offset: Vector2 = Vector2.ZERO) -> void:
	var polygon := PackedVector2Array()
	for point: Vector2 in points: polygon.append(point + offset)
	draw_colored_polygon(polygon, fill)
	if stroke.a > 0:
		polygon.append(polygon[0])
		draw_polyline(polygon, stroke, 1.0, true)

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 32:
		var angle := TAU * index / 32.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
