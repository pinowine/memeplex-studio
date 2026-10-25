class_name DeskHoverStrip
extends Control

const CORNER_TAPE := preload("res://assets/image/textures/studio/desk/clear_tape.png")

@export var title_font_size: int = 20
@export var detail_font_size: int = 18
@export var paper_texels_per_unit: float = 3.0
@export var ink_color := Color("3f4338")

var _font: Font
var _paper: Texture2D
var _default_text := ""
var _hover: Dictionary = {}
var _has_hover := false
var _heading := ""
var _detail := ""
var _lines: Array[Dictionary] = []
var _truncated := false
var _content_revision := 0
var _layout_revision := 0
var _corner_tape: Array[TextureRect] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = ""
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _ready() -> void:
	resized.connect(_layout)
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_content()
		_layout()

func _layout_tape() -> void:
	if _corner_tape.is_empty():
		for label: String in ["UpperLeftTape", "UpperRightTape"]:
			var tape := TextureRect.new()
			tape.name = label
			tape.texture = CORNER_TAPE
			tape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tape.stretch_mode = TextureRect.STRETCH_SCALE
			tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tape.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			tape.z_index = 2
			add_child(tape)
			_corner_tape.append(tape)
	# Different lengths and angles keep the two torn pieces from looking stamped on.
	var left: TextureRect = _corner_tape[0]
	left.size = Vector2(58, 20)
	left.pivot_offset = left.size * .5
	left.position = Vector2(-17, -7)
	left.rotation = -.29
	left.modulate = Color(1.0, .99, .96, .86)
	var right: TextureRect = _corner_tape[1]
	right.size = Vector2(66, 22)
	right.pivot_offset = right.size * .5
	right.position = Vector2(size.x - 45, -10)
	right.rotation = .21
	right.modulate = Color(1.0, .99, .95, .80)

func configure(font: Font, paper: Texture2D) -> void:
	if _font == font and _paper == paper: return
	_font = font
	_paper = paper
	_layout()

func set_default_text(current_meme: String) -> void:
	if _default_text == current_meme: return
	_default_text = current_meme
	if not _has_hover: _update_content()

func show_hover(details: Dictionary) -> void:
	if details.is_empty():
		clear_hover()
		return
	_hover = details.duplicate(true)
	_has_hover = true
	_update_content()

func clear_hover() -> void:
	if not _has_hover: return
	_has_hover = false
	_hover.clear()
	_update_content()

func _normalized(text: String) -> String:
	return " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false)).strip_edges()

func _first_text(keys: Array[String]) -> String:
	for key in keys:
		var value: Variant = _hover.get(key)
		if value is String and not str(value).strip_edges().is_empty(): return _normalized(DeskLocalization.text(value))
	return ""

func _qualifiers() -> Array[String]:
	var result: Array[String] = []
	for key in ["count", "available", "quantity"]:
		var value: Variant = _hover.get(key)
		if value is int and value >= 0:
			result.append(DeskLocalization.format_text("可用 %d", value))
			break
		if value is float and is_finite(value) and value >= 0.0 and value == floor(value) and value < 9223372036854775807.0:
			result.append(DeskLocalization.format_text("可用 %d", int(value)))
			break
	var status := _first_text(["status"])
	if not status.is_empty(): result.append(status)
	return result

func _update_content() -> void:
	var heading := _normalized(_default_text)
	var detail := ""
	if _has_hover:
		heading = _first_text(["title", "name", "label", "id"])
		var qualifiers := _qualifiers()
		if not qualifiers.is_empty():
			heading += (" · " if not heading.is_empty() else "") + " · ".join(qualifiers)
		var pieces: Array[String] = []
		for key in ["description", "hint", "gesture", "unlock_hint"]:
			var value: Variant = _hover.get(key)
			if not value is String: continue
			var clean := _normalized(DeskLocalization.text(value))
			if not clean.is_empty() and clean not in pieces: pieces.append(clean)
		detail = "；".join(pieces)
	if heading.is_empty() and not detail.is_empty():
		heading = detail
		detail = ""
	if heading == _heading and detail == _detail: return
	_heading = heading
	_detail = detail
	_content_revision += 1
	_layout()

func _active_font() -> Font:
	return _font if _font != null else get_theme_font("font", "Label")

func _padding() -> Vector2:
	return Vector2(minf(48.0,maxf(0.0,size.x*.20)), minf(9.0, maxf(0.0, size.y * 0.12)))

func _text_rect() -> Rect2:
	var padding := _padding()
	return Rect2(padding, (size - padding * 2.0).max(Vector2.ZERO))

func _text_width(text: String, font: Font, fs: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x

func _prefix_length(text: String, font: Font, fs: int, width: float) -> int:
	var low := 0
	var high := text.length()
	while low < high:
		var middle := (low + high + 1) / 2
		if _text_width(text.left(middle), font, fs) <= width:
			low = middle
		else:
			high = middle - 1
	return low

func _ellipsize(text: String, font: Font, fs: int, width: float) -> String:
	if _text_width(text, font, fs) <= width: return text
	var ellipsis := "…"
	if _text_width(ellipsis, font, fs) > width: return ""
	var count := _prefix_length(text, font, fs, width - _text_width(ellipsis, font, fs))
	return text.left(count).strip_edges() + ellipsis

func _default_rows(font: Font, width: float, first_size: int, second_size: int) -> Array[String]:
	var rows: Array[String] = []
	if _heading.is_empty(): return rows
	var count := _prefix_length(_heading, font, first_size, width)
	if count == 0:
		var shortened := _ellipsize(_heading, font, first_size, width)
		if not shortened.is_empty(): rows.append(shortened)
		_truncated = true
		return rows
	if count >= _heading.length():
		rows.append(_heading)
		return rows
	# Prefer a word boundary when there is one; Chinese text can wrap by character.
	var first := _heading.left(count)
	var boundary := first.rfind(" ")
	if boundary > count / 2: count = boundary
	first = _heading.left(count).strip_edges()
	if not first.is_empty(): rows.append(first)
	var rest := _heading.substr(count).strip_edges()
	var second := _ellipsize(rest, font, second_size, width)
	if not second.is_empty(): rows.append(second)
	_truncated = second != rest
	return rows

func _hover_heading(font: Font, fs: int, width: float) -> String:
	var qualifiers := _qualifiers()
	var name := _first_text(["title", "name", "label", "id"])
	if not qualifiers.is_empty() and not name.is_empty():
		var suffix := " · ".join(qualifiers)
		var suffix_width := _text_width(" · " + suffix, font, fs)
		if suffix_width <= width:
			var shortened := _ellipsize(name, font, fs, width - suffix_width)
			return (shortened + " · " if not shortened.is_empty() else "") + suffix
	return _ellipsize(_heading, font, fs, width)

func _layout() -> void:
	_layout_tape()
	_lines.clear()
	_truncated = false
	_layout_revision += 1
	if size.x <= 0.0 or size.y <= 0.0:
		_truncated = not _heading.is_empty() or not _detail.is_empty()
		queue_redraw()
		return
	var font := _active_font()
	var area := _text_rect()
	var first_size := clampi(title_font_size, 8, 40)
	var second_size := clampi(detail_font_size, 8, 40)
	var texts: Array[String] = []
	if _has_hover:
		if not _heading.is_empty(): texts.append(_hover_heading(font, first_size, area.size.x))
		if not _detail.is_empty(): texts.append(_ellipsize(_detail, font, second_size, area.size.x))
		_truncated = (not texts.is_empty() and texts[0] != _heading) or (texts.size() > 1 and texts[1] != _detail)
	else:
		texts = _default_rows(font, area.size.x, first_size, second_size)
	var total := 0.0
	for index in texts.size():
		var fs := first_size if index == 0 else second_size
		total += ceilf(font.get_ascent(fs) + font.get_descent(fs))
	if texts.size() > 1: total += 2.0
	while not texts.is_empty() and total > area.size.y:
		var index := texts.size() - 1
		var fs := first_size if index == 0 else second_size
		total -= ceilf(font.get_ascent(fs) + font.get_descent(fs))
		if texts.size() > 1: total -= 2.0
		texts.pop_back()
		_truncated = true
	var top := area.position.y + maxf(0.0, (area.size.y - total) * 0.5)
	for index in texts.size():
		var fs := first_size if index == 0 else second_size
		var height := ceilf(font.get_ascent(fs) + font.get_descent(fs))
		var rect := Rect2(Vector2(area.position.x, top), Vector2(_text_width(texts[index], font, fs), height))
		_lines.append({"text":texts[index], "font_size":fs, "rect":rect, "baseline":rect.position + Vector2(0, font.get_ascent(fs))})
		top += height + 2.0
	queue_redraw()

func _outline() -> PackedVector2Array:
	var inset := minf(1.5, minf(size.x, size.y) * 0.05)
	var left := inset
	var right := maxf(inset, size.x - inset)
	var top := inset
	var bottom := maxf(inset, size.y - inset)
	return PackedVector2Array([
		Vector2(left + 2, top + 1), Vector2(size.x * 0.18, top), Vector2(size.x * 0.39, top + 0.9),
		Vector2(size.x * 0.65, top + 0.2), Vector2(right - 1, top + 1.1), Vector2(right, size.y * 0.39),
		Vector2(right - 0.8, bottom - 1), Vector2(size.x * 0.76, bottom), Vector2(size.x * 0.48, bottom - 0.7),
		Vector2(size.x * 0.22, bottom + 0.2), Vector2(left, bottom - 0.9), Vector2(left + 0.5, size.y * 0.41)
	])

func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0: return
	var outline := _outline()
	var shadow := PackedVector2Array()
	for point in outline: shadow.append(point + Vector2(2.5, 3.0))
	draw_colored_polygon(shadow, Color(0.12, 0.10, 0.07, 0.20))
	draw_colored_polygon(outline, Color("eee6d3"))
	if _paper != null:
		var uv := PackedVector2Array()
		var source := _paper.get_size().max(Vector2.ONE)
		var density := clampf(paper_texels_per_unit, 1.0, 8.0) if is_finite(paper_texels_per_unit) else 2.0
		for point in outline: uv.append(point * density / source + Vector2(0.17, 0.23))
		draw_polygon(outline, PackedColorArray([Color(1, 1, 1, 0.80)]), uv, _paper)
	var edge := outline.duplicate()
	edge.append(outline[0])
	draw_polyline(edge, Color(0.40, 0.36, 0.28, 0.16), 0.7, true)
	var font := _active_font()
	for line: Dictionary in _lines:
		draw_string(font, line.baseline, line.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(line.font_size), ink_color)

func inspection() -> Dictionary:
	var visible_text := PackedStringArray()
	var fits := true
	for line: Dictionary in _lines:
		visible_text.append(line.text)
		fits = fits and _text_rect().grow(0.01).encloses(line.rect)
	var tape_rows: Array[Dictionary] = []
	for tape: TextureRect in _corner_tape:
		var bounds := tape.get_transform() * Rect2(Vector2.ZERO, tape.size)
		tape_rows.append({"name":str(tape.name), "rect":bounds, "rotation":tape.rotation,
			"texture":tape.texture.resource_path, "mouse_filter":tape.mouse_filter,
			"crosses_top_edge":bounds.position.y < 0.0 and bounds.end.y > 0.0,
			"opacity":tape.modulate.a})
	return {
		"component":"handwritten_desktop_hover_strip", "mode":"hover" if _has_hover else "current_meme",
		"default_text":_default_text, "hover_details":_hover.duplicate(true), "heading":_heading, "detail":_detail,
		"visible_text":"\n".join(visible_text), "lines":_lines.duplicate(true), "line_count":_lines.size(),
		"maximum_lines":2, "title_font_size":title_font_size, "detail_font_size":detail_font_size,
		"text_rect":_text_rect(), "content_rect":Rect2(position,size), "text_fits":fits, "truncated":_truncated,
		"mouse_filter":mouse_filter, "tooltip_text":tooltip_text, "content_revision":_content_revision,
		"layout_revision":_layout_revision, "timers":0, "reads_simulation":false,
		"font_provided":_font != null, "font":_font, "paper_texture":_paper.resource_path if _paper != null else "",
		"paper_mapping":"native_density_uv_tiling", "paper_texels_per_unit":paper_texels_per_unit,
		"corner_tape":tape_rows, "tape_placement":"two_irregular_top_corners"
	}
