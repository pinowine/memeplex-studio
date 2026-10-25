class_name DeskMaterialCardFace
extends Control

const MINIMUM := Vector2(108, 72)
const TOPIC_MINIMUM := Vector2(144, 74)
const TITLES := {"language":"LANG", "group":"GROUP", "module":"PATCH", "topic":"TOPIC"}
const SHAPES := {"language":"double_layer_laminated_round", "group":"clipped_identity_card", "module":"notched_expansion_board", "topic":"notched_horizontal_ticket"}
const PALETTES := {
	"language":{"edge":Color("354d59"), "body":Color("8da5ac"), "panel":Color("d6dfd9"), "ink":Color("263e49"), "light":Color("eff4e8")},
	"group":{"edge":Color("3f4930"), "body":Color("8c966b"), "panel":Color("e0dfc8"), "ink":Color("35422c"), "light":Color("f0ecd7")},
	"module":{"edge":Color("594031"), "body":Color("b38252"), "panel":Color("d3cfb1"), "ink":Color("433c2c"), "light":Color("e7c991")},
	"topic":{"edge":Color("765b32"), "body":Color("c7a05c"), "panel":Color("e7d5a8"), "ink":Color("594523"), "light":Color("f3e4bf")}
}

var _record: Dictionary = {}
var _font: Font
var _kind := "language"
var _hovered := false
var _selected := false
var _draw_count := 0
var _layout: Dictionary = {}


static func minimum_card_size(kind: String) -> Vector2:
	return TOPIC_MINIMUM if kind in ["topic", "topics"] else MINIMUM


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	if not resized.is_connected(_refresh): resized.connect(_refresh)
	_refresh()


# Rendering owns no material identity, inventory count or installation action.
# Its caller supplies the existing authority record and handles pointer input.
func configure(record: Dictionary, font: Font = null) -> void:
	_record = record.duplicate(true)
	_kind = str(_record.get("kind", "language"))
	if _kind == "topics": _kind = "topic"
	if not PALETTES.has(_kind): _kind = "module" if _kind.begins_with("module") else "language"
	_font = font if font != null else ThemeDB.fallback_font
	custom_minimum_size = minimum_card_size(_kind)
	_refresh()


func set_hovered(value: bool) -> void:
	if value == _hovered: return
	_hovered = value
	queue_redraw()


func set_selected(value: bool) -> void:
	if value == _selected: return
	_selected = value
	queue_redraw()


func _refresh() -> void:
	_layout = _build_layout()
	queue_redraw()


func _source_text() -> String:
	for field: String in ["source_label", "source_instance_id", "event_instance_id", "source", "source_id"]:
		var value: Variant = _record.get(field, "")
		if value == null: continue
		if value is Dictionary:
			for child: String in ["title", "label", "instance_id", "event_id", "id"]:
				if value.get(child) != null and not str(value.get(child, "")).is_empty(): return str(value[child])
		elif not str(value).is_empty(): return str(value)
	return "—"


func _count_value() -> int:
	var value: Variant = _record.get("count", _record.get("available", _record.get("amount", 1)))
	if value is int: return maxi(0, value)
	if value is float and is_finite(value) and value >= 0.0 and value == floor(value) and value < 9223372036854775807.0:
		return int(value)
	return 0


func _fit_text(text: String, rect: Rect2, requested: int, minimum: int, max_lines: int) -> Dictionary:
	var face := _font if _font != null else ThemeDB.fallback_font
	var clean := text.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var chosen: Array[String] = []
	var chosen_size := requested
	var clipped := false
	for point_size in range(requested, minimum - 1, -1):
		var line_height := face.get_height(point_size)
		var capacity := mini(max_lines, maxi(1, floori(rect.size.y / maxf(1.0, line_height))))
		var lines := _word_lines(clean, rect.size.x, point_size)
		chosen = lines
		chosen_size = point_size
		if lines.size() <= capacity: break
		if point_size == minimum:
			chosen = lines.slice(0, capacity)
			var last := chosen[-1]
			while not last.is_empty() and face.get_string_size(last + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > rect.size.x:
				last = last.left(last.length() - 1)
			chosen[-1] = last + "…"
			clipped = true
	var widths: Array[float] = []
	for line: String in chosen:
		widths.append(face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen_size).x)
	var height := face.get_height(chosen_size)
	return {"original":text, "lines":chosen, "font_size":chosen_size, "line_height":height, "widths":widths, "truncated":clipped, "fits":widths.all(func(width: float) -> bool: return width <= rect.size.x + .05) and height * chosen.size() <= rect.size.y + .05, "rect":rect}


func _word_lines(text: String, width: float, point_size: int) -> Array[String]:
	var face := _font if _font != null else ThemeDB.fallback_font
	var result: Array[String] = []
	var line := ""
	for character: String in text.strip_edges():
		if not line.is_empty() and face.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > width:
			var space := line.rfind(" ")
			var hyphen := line.rfind("-")
			var boundary := maxi(space, hyphen + 1 if hyphen >= 0 else -1)
			if boundary > 0:
				result.append(line.left(boundary).strip_edges())
				line = line.substr(boundary).strip_edges() + character
			else:
				result.append(line)
				line = character
		else:
			line += character
	if not line.is_empty() or result.is_empty(): result.append(line.strip_edges())
	return result


func _header_layout(body: Rect2) -> Dictionary:
	var face := _font if _font != null else ThemeDB.fallback_font
	var number := str(_count_value())
	var category := str(TITLES[_kind])
	var left := body.position.x + 25.0
	var right := body.end.x - 8.0
	for number_size: int in [11, 10]:
		var badge_width := maxf(20.0, ceilf(face.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x) + 2.0)
		for category_size: int in [9, 8]:
			var category_width := face.get_string_size(category, HORIZONTAL_ALIGNMENT_LEFT, -1, category_size).x
			if category_width + 2.0 + badge_width <= right - left:
				return {"category":Rect2(left, body.position.y + 5, right - badge_width - left - 2, 14), "count":Rect2(right - badge_width, body.position.y + 5, badge_width, 16), "category_size":category_size, "count_size":number_size, "count_text":number, "overflow":false}
	# A lone ellipsis signals that the complete quantity belongs on the information paper.
	# Never render a truncated numeric prefix as though it were the actual stock count.
	return {"category":Rect2(left, body.position.y + 5, right - left - 22, 14), "count":Rect2(right - 20, body.position.y + 5, 20, 16), "category_size":9, "count_size":11, "count_text":"…", "overflow":true}


func _build_layout() -> Dictionary:
	var dimensions := size.max(minimum_card_size(_kind))
	var body := Rect2(4, 3, dimensions.x - 10, dimensions.y - 10)
	var header := _header_layout(body)
	var sections := {
		"icon":Rect2(body.position + Vector2(7, 6), Vector2(15, 13)),
		"category":header.category,
		"count":header.count,
		"title":Rect2(body.position + Vector2(10, 23), Vector2(body.size.x - 20, body.size.y - 39)),
		"source":Rect2(Vector2(body.position.x + 10, body.end.y - 15), Vector2(body.size.x - 20, 14))
	}
	var title := DeskLocalization.text(str(_record.get("title", _record.get("id", ""))))
	var text := {
		"title":_fit_text(title, sections.title, 15, 12, 2),
		"source":_fit_text(_source_text(), sections.source, 9, 8, 1),
		"category":_fit_text(str(TITLES[_kind]), sections.category, header.category_size, header.category_size, 1),
		"count":_fit_text(header.count_text, sections.count.grow(-1), header.count_size, header.count_size, 1)
	}
	text.count.original = str(_count_value())
	text.count.truncated = bool(header.overflow)
	return {"body":body, "sections":sections, "text":text, "size":dimensions, "thickness":3.6 if _kind == "module" else (2.8 if _kind == "language" else 3.2)}


func _rounded_shape(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centres := [rect.position + Vector2(radius, radius), Vector2(rect.end.x - radius, rect.position.y + radius), rect.end - Vector2.ONE * radius, Vector2(rect.position.x + radius, rect.end.y - radius)]
	for corner in 4:
		for step in 9:
			var angle := PI + float(corner) * PI * .5 + float(step) / 8.0 * PI * .5
			points.append(centres[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _shape(rect: Rect2) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	match _kind:
		"group":
			return PackedVector2Array([p, Vector2(e.x - 14, p.y), Vector2(e.x, p.y + 14), e, Vector2(p.x + 7, e.y), Vector2(p.x, e.y - 7)])
		"module":
			var points := PackedVector2Array([p + Vector2(6, 0), Vector2(e.x - 6, p.y), Vector2(e.x, p.y + 6)])
			for index in 5:
				var y := p.y + 11 + float(index) * (rect.size.y - 21) / 5.0
				points.append(Vector2(e.x, y))
				points.append(Vector2(e.x - 3, y + 1))
				points.append(Vector2(e.x - 3, y + 4))
				points.append(Vector2(e.x, y + 5))
			points.append(e - Vector2(0, 5))
			points.append(e - Vector2(6, 0))
			points.append(Vector2(p.x + 6, e.y))
			points.append(Vector2(p.x, e.y - 6))
			points.append(p + Vector2(0, 6))
			return points
		"topic":
			var middle := rect.get_center().y
			return PackedVector2Array([p + Vector2(7, 0), Vector2(e.x - 7, p.y), Vector2(e.x, p.y + 7), Vector2(e.x, middle - 4), Vector2(e.x - 4, middle), Vector2(e.x, middle + 4), e - Vector2(0, 7), e - Vector2(7, 0), Vector2(p.x + 7, e.y), Vector2(p.x, e.y - 7), Vector2(p.x, middle + 4), Vector2(p.x + 4, middle), Vector2(p.x, middle - 4), p + Vector2(0, 7)])
	return _rounded_shape(rect, 7)


func _stroke(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)


func _draw() -> void:
	_draw_count += 1
	_layout = _build_layout()
	var body: Rect2 = _layout.body
	var palette: Dictionary = PALETTES[_kind]
	var thickness: float = _layout.thickness
	for offset in [Vector2(2, 6), Vector2(1, 4)]:
		draw_colored_polygon(_shape(Rect2(body.position + offset, body.size)), Color(0.07, 0.075, 0.05, .13))
	draw_colored_polygon(_shape(Rect2(body.position + Vector2(1.2, thickness), body.size)), palette.edge)
	var outline := _shape(body)
	draw_colored_polygon(outline, palette.body)
	_stroke(outline, palette.edge, 1.1)
	_draw_face_structure(body, palette)
	_draw_icon(_layout.sections.icon, palette.ink)
	var badge: Rect2 = _layout.sections.count
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = palette.ink
	badge_style.set_corner_radius_all(2)
	draw_style_box(badge_style, badge)
	for role: String in ["category", "title", "source", "count"]:
		_draw_text(_layout.text[role], palette.light if role == "count" else palette.ink, role == "count")
	if _hovered or _selected:
		var glass := body.grow(-5)
		var intensity := .17 if _selected else .10
		draw_colored_polygon(PackedVector2Array([glass.position, glass.position + Vector2(glass.size.x * .27, 0), glass.position + Vector2(glass.size.x * .70, glass.size.y), glass.position + Vector2(glass.size.x * .49, glass.size.y)]), Color(1.0, .98, .88, intensity))
		_stroke(_shape(body.grow(-1.4)), Color(.97, .94, .79, .42 if _selected else .22), .9)


func _draw_face_structure(body: Rect2, palette: Dictionary) -> void:
	var inner := body.grow(-5)
	var panel := Rect2(body.position + Vector2(6, 21), Vector2(body.size.x - 12, body.size.y - 25))
	var style := StyleBoxFlat.new()
	style.bg_color = palette.panel
	style.border_color = Color(palette.ink, .37)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3 if _kind == "language" else 1)
	draw_style_box(style, panel)
	var divider_y := body.end.y - 16
	draw_line(Vector2(body.position.x + 9, divider_y), Vector2(body.end.x - 9, divider_y), Color(palette.ink, .35), .7, true)
	match _kind:
		"language":
			_stroke(_rounded_shape(inner, 4), Color(palette.light, .70), 1.0)
			draw_line(inner.position + Vector2(2, 4), Vector2(inner.position.x + 2, inner.end.y - 3), Color(palette.edge, .35), 1.0, true)
			for index in 4:
				var x := body.end.x - 19 + float(index) * 2.3
				draw_line(Vector2(x, body.end.y - 7), Vector2(x + 1.5, body.end.y - 11), Color(palette.light, .65), .75, true)
		"group":
			var hole := body.position + Vector2(6, 7)
			draw_circle(hole + Vector2(0, 1), 2.4, palette.edge, true, -1, true)
			draw_arc(hole, 2.6, .25, PI * 1.7, 18, palette.light, .8, true)
			draw_line(inner.position + Vector2(4, 13), Vector2(inner.end.x - 4, inner.position.y + 13), Color(palette.edge, .38), 1.0, true)
			for x in [body.position.x + 8, body.end.x - 9]:
				draw_line(Vector2(x, divider_y + 2), Vector2(x, body.end.y - 4), Color(palette.edge, .50), 1.1, true)
		"module":
			for index in 5:
				var y := body.position.y + 11 + float(index) * (body.size.y - 21) / 5.0
				draw_rect(Rect2(body.end.x - 5.8, y + 1, 4.5, 4), Color("e0b46a"))
				draw_line(Vector2(body.end.x - 4, y + 1), Vector2(body.end.x - 4, y + 4), Color("f3da9a"), .7, true)
			for point in [body.position + Vector2(4.5, 5), Vector2(body.position.x + 4.5, body.end.y - 5)]:
				draw_circle(point, 1.5, palette.edge, true, -1, true)
				draw_circle(point - Vector2(.3, .3), .6, palette.light, true, -1, true)
			for index in 6:
				var x := body.position.x + 13 + float(index) * 4.0
				draw_line(Vector2(x, body.position.y + 19), Vector2(x + 2, body.position.y + 16), Color(palette.edge, .25), .7, true)
		"topic":
			_stroke(_shape(body.grow(-3)), Color(palette.light, .66), .8)
			for index in 5:
				var x := body.end.x - 8 - float(index) * 3.2
				draw_line(Vector2(x, body.end.y - 7), Vector2(x, body.end.y - 4), Color(palette.ink, .48), .8, true)


func _draw_icon(rect: Rect2, ink: Color) -> void:
	var centre := rect.get_center()
	var width := 1.1
	match _kind:
		"language":
			draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(9, 8)), Color(ink, .20))
			draw_rect(Rect2(rect.position + Vector2(5, 4), Vector2(9, 8)), ink, false, width)
			draw_line(centre + Vector2(-5, -2), centre + Vector2(-2, -2), ink, width, true)
			draw_line(centre + Vector2(-3.5, -4), centre + Vector2(-3.5, 1), ink, width, true)
		"group":
			for delta in [Vector2(-4, 0), Vector2(4, 0), Vector2(0, -2)]:
				draw_circle(centre + delta - Vector2(0, 2), 1.6, ink, true, -1, true)
				draw_arc(centre + delta + Vector2(0, 3), 3, PI, TAU, 12, ink, width, true)
		"module":
			draw_rect(Rect2(centre - Vector2(4, 4), Vector2(8, 8)), ink, false, width)
			draw_rect(Rect2(centre - Vector2(2, 2), Vector2(4, 4)), Color(ink, .45))
			for index in 3:
				var offset := -3.0 + float(index) * 3.0
				draw_line(centre + Vector2(offset, -6), centre + Vector2(offset, -4), ink, width, true)
				draw_line(centre + Vector2(offset, 4), centre + Vector2(offset, 6), ink, width, true)
		"topic":
			for x in [-2.5, 2.5]: draw_line(centre + Vector2(x + 1, -5), centre + Vector2(x - 1, 5), ink, width, true)
			for y in [-2.0, 2.0]: draw_line(centre + Vector2(-6, y), centre + Vector2(6, y), ink, width, true)


func _draw_text(entry: Dictionary, color: Color, centred := false) -> void:
	var face := _font if _font != null else ThemeDB.fallback_font
	var rect: Rect2 = entry.rect
	var height: float = entry.line_height
	var y := rect.position.y + maxf(0, (rect.size.y - height * entry.lines.size()) * .5) + face.get_ascent(entry.font_size)
	for index in entry.lines.size():
		var line: String = entry.lines[index]
		var x := rect.position.x + ((rect.size.x - float(entry.widths[index])) * .5 if centred else 0.0)
		draw_string(face, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, entry.font_size, color)
		y += height


func inspection() -> Dictionary:
	_layout = _build_layout()
	var fit := {}
	for role: String in _layout.text: fit[role] = _layout.text[role].duplicate(true)
	return {"component":"physical_material_card_face", "kind":_kind, "id":str(_record.get("id", "")), "shape":SHAPES[_kind], "thickness":_layout.thickness, "minimum_size":minimum_card_size(_kind), "size":size, "body":_layout.body, "silhouette":_shape(_layout.body), "sections":_layout.sections.duplicate(true), "font_fit":fit, "count":_count_value(), "source":_source_text(), "title":DeskLocalization.text(str(_record.get("title", _record.get("id", "")))), "hovered":_hovered, "selected":_selected, "reflection":_hovered or _selected, "draw_count":_draw_count, "rendering":"native_canvas_geometry_and_font", "mutates_inventory":false, "mouse_filter":mouse_filter}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
