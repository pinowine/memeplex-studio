extends Node2D

@onready var style: Label = $Name
var anchor: Vector2
var layout_angle: float = 0.0
var minimum_zoom_ratio: float = 1.0
var font_size: int
var glyphs: Array[Dictionary] = []
var glyph_positions := PackedVector2Array()
var glyph_angles := PackedFloat32Array()
var glyph_widths := PackedFloat32Array()
var line := TextLine.new()
var _font: Font
var _zoom_ratio: float = 1.0
var _extent: Vector2
var _layout_territory: TerritoryGeometry
var _layout_text: String
var _layout_zoom: float

func layout_country(territory: TerritoryGeometry, fitted_zoom: float, levels: PackedFloat32Array) -> void:
	if _layout_territory == territory and _layout_text == style.text and is_equal_approx(_layout_zoom, fitted_zoom): return
	_layout_territory = territory
	_layout_text = style.text
	_layout_zoom = fitted_zoom
	_font = style.get_theme_font("font")
	var largest: int = 0
	for i in territory.outlines.size():
		if AtlasMapGenerator.polygon_area(territory.outlines[i]) > AtlasMapGenerator.polygon_area(territory.outlines[largest]): largest = i
	var ring := territory.outlines[largest]
	var moments := _moments(ring)
	var centroid: Vector2 = moments.center
	var preferred: float = clampf(moments.angle, -PI * 0.45, PI * 0.45)
	var desired := clampi(roundi(sqrt(territory.area) * fitted_zoom * 0.16), style.get_theme_constant("minimum_size"), style.get_theme_font_size("font_size"))
	var best: Dictionary = {}
	# Names enter at the first semantic zoom level with enough readable interior space.
	for level in levels:
		best = _find_layout(territory, ring, centroid, preferred, desired, fitted_zoom * level)
		if not best.is_empty():
			minimum_zoom_ratio = level
			break
	assert(not best.is_empty(), "Country name has no valid interior corridor: " + style.text)
	anchor = best.anchor
	layout_angle = best.angle
	rotation = layout_angle
	font_size = best.font_size
	glyph_positions.clear()
	glyph_angles.clear()
	glyph_widths.clear()
	var tracking := minf(style.get_theme_constant("maximum_tracking"), (best.width - _extent.x) / float(glyphs.size() - 1))
	var width := _extent.x + tracking * (glyphs.size() - 1)
	var cursor := -width * 0.5
	var bow := width * 0.025 * signf((centroid - anchor).dot(Vector2.from_angle(layout_angle).orthogonal()))
	for glyph in glyphs:
		var x: float = cursor + glyph.advance * 0.5
		var t := 2.0 * x / width
		glyph_positions.append(Vector2(x, bow * (1.0 - t * t)))
		glyph_angles.append(atan(-8.0 * bow * x / (width * width)))
		glyph_widths.append(glyph.advance)
		cursor += glyph.advance + tracking
	queue_redraw()

func set_zoom_ratio(value: float) -> void:
	var ratio := clampf(sqrt(value / minimum_zoom_ratio), 0.6, 1.4)
	if is_equal_approx(_zoom_ratio, ratio): return
	_zoom_ratio = ratio
	queue_redraw()

func screen_rect() -> Rect2:
	var result := Rect2(global_position, Vector2.ZERO)
	for box in screen_boxes(): result = result.merge(box)
	return result

func screen_boxes() -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	for i in glyph_positions.size():
		var local := Transform2D(glyph_angles[i], glyph_positions[i] * _zoom_ratio)
		var result := Rect2(global_transform * local.origin, Vector2.ZERO)
		for corner in [Vector2(-glyph_widths[i] * 0.5, -_extent.y * 0.5), Vector2(glyph_widths[i] * 0.5, -_extent.y * 0.5), Vector2(-glyph_widths[i] * 0.5, _extent.y * 0.5), Vector2(glyph_widths[i] * 0.5, _extent.y * 0.5)]:
			result = result.expand(global_transform * local * corner)
		boxes.append(result.grow(style.get_theme_constant("outline_size")))
	return boxes

func _draw() -> void:
	var server := TextServerManager.get_primary_interface()
	for i in glyphs.size():
		var glyph := glyphs[i]
		draw_set_transform(glyph_positions[i] * _zoom_ratio, glyph_angles[i])
		var origin: Vector2 = Vector2(-glyph_widths[i] * 0.5, line.get_line_ascent() - _extent.y * 0.5) + glyph.offset
		server.font_draw_glyph_outline(glyph.font_rid, get_canvas_item(), font_size, style.get_theme_constant("outline_size"), origin, glyph.index, style.get_theme_color("font_outline_color"))
		server.font_draw_glyph(glyph.font_rid, get_canvas_item(), font_size, origin, glyph.index, style.get_theme_color("font_color"))
	draw_set_transform(Vector2.ZERO)

func _spans(ring: PackedVector2Array, holes: Array[PackedVector2Array], origin: Vector2, direction: Vector2) -> Array[Vector2]:
	var cuts: Array[float] = []
	var normal := direction.orthogonal()
	for outline in [ring] + holes:
		for i in outline.size():
			var a: Vector2 = outline[i] - origin
			var b: Vector2 = outline[(i + 1) % outline.size()] - origin
			var ay := a.dot(normal)
			var by := b.dot(normal)
			if (ay > 0.0) != (by > 0.0):
				cuts.append(a.lerp(b, ay / (ay - by)).dot(direction))
	cuts.sort()
	var result: Array[Vector2] = []
	for i in range(0, cuts.size() - 1, 2): result.append(Vector2(cuts[i], cuts[i + 1]))
	return result

func _intersect_spans(left: Array[Vector2], right: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for a in left:
		for b in right:
			var start := maxf(a.x, b.x)
			var end := minf(a.y, b.y)
			if end > start: result.append(Vector2(start, end))
	return result

func _moments(ring: PackedVector2Array) -> Dictionary:
	var area: float = 0.0
	var center := Vector2.ZERO
	var xx: float = 0.0
	var yy: float = 0.0
	var xy: float = 0.0
	for i in ring.size():
		var a := ring[i] - ring[0]
		var b := ring[(i + 1) % ring.size()] - ring[0]
		var cross := float(a.cross(b))
		area += cross * 0.5
		center += (a + b) * cross
		xx += (a.x * a.x + a.x * b.x + b.x * b.x) * cross
		yy += (a.y * a.y + a.y * b.y + b.y * b.y) * cross
		xy += (2.0 * a.x * a.y + a.x * b.y + b.x * a.y + 2.0 * b.x * b.y) * cross
	center /= 6.0 * area
	xx = xx / (12.0 * area) - center.x * center.x
	yy = yy / (12.0 * area) - center.y * center.y
	xy = xy / (24.0 * area) - center.x * center.y
	return {"center":center + ring[0], "angle":0.5 * atan2(2.0 * xy, xx - yy)}


func _shape(size: int) -> void:
	line.clear()
	line.add_string(style.text, _font, size, TranslationServer.get_locale())
	_extent = line.get_size()
	glyphs.clear()
	for glyph in TextServerManager.get_primary_interface().shaped_text_get_glyphs(line.get_rid()):
		if glyph.advance == 0.0 and glyph.index == 0: continue
		for repeat in glyph.repeat: glyphs.append(glyph)

func _ink_fits(territory: TerritoryGeometry, position: Vector2, angle: float, available: float, centroid: Vector2, zoom: float) -> bool:
	var tracking := minf(style.get_theme_constant("maximum_tracking"), (available - _extent.x) / float(glyphs.size() - 1))
	var width := _extent.x + tracking * (glyphs.size() - 1)
	var cursor := -width * 0.5
	var bow := width * 0.025 * signf((centroid - position).dot(Vector2.from_angle(angle).orthogonal()))
	for glyph in glyphs:
		var x: float = cursor + glyph.advance * 0.5
		var center := Vector2(x, bow * (1.0 - pow(2.0 * x / width, 2.0)))
		var slope := atan(-8.0 * bow * x / (width * width))
		for corner in [Vector2.ZERO, Vector2(-glyph.advance * 0.5, -_extent.y * 0.5), Vector2(glyph.advance * 0.5, -_extent.y * 0.5), Vector2(glyph.advance * 0.5, _extent.y * 0.5), Vector2(-glyph.advance * 0.5, _extent.y * 0.5)]:
			var point: Vector2 = position + (center + corner.rotated(slope)).rotated(angle) / zoom
			if not territory.contains(point): return false
		cursor += glyph.advance + tracking
	return true

func screen_polygons() -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for i in glyph_positions.size():
		var local := Transform2D(glyph_angles[i], glyph_positions[i] * _zoom_ratio)
		var ring := PackedVector2Array()
		for corner in [Vector2(-glyph_widths[i] * 0.5, -_extent.y * 0.5), Vector2(glyph_widths[i] * 0.5, -_extent.y * 0.5), Vector2(glyph_widths[i] * 0.5, _extent.y * 0.5), Vector2(-glyph_widths[i] * 0.5, _extent.y * 0.5)]:
			ring.append(global_transform * local * corner)
		polygons.append(ring)
	return polygons

func _find_layout(territory: TerritoryGeometry, ring: PackedVector2Array, centroid: Vector2, preferred: float, desired: int, fitted_zoom: float) -> Dictionary:
	var best_score: float = -INF
	var best: Dictionary = {}
	# Fit the whole name inside an interior corridor, not across the territory bounding box.
	for candidate_size in range(desired, style.get_theme_constant("minimum_size") - 1, -1):
		_shape(candidate_size)
		var text_width := _extent.x
		var height := _font.get_height(candidate_size) / fitted_zoom
		for angle in [preferred, preferred - 0.30, preferred + 0.30, 0.0, -0.6, 0.6, -1.35, 1.35]:
			angle = clampf(angle, -PI * 0.45, PI * 0.45)
			var direction := Vector2.from_angle(angle)
			var normal := direction.orthogonal()
			for offset in [-0.60, -0.45, -0.3, -0.15, 0.0, 0.15, 0.3, 0.45, 0.60]:
				var origin: Vector2 = centroid + normal * sqrt(territory.area) * offset
				var spans := _spans(ring, territory.holes, origin, direction)
				for side in [-1.0, 1.0]:
					spans = _intersect_spans(spans, _spans(ring, territory.holes, origin + normal * height * side * 0.65, direction))
				for span in spans:
					var width: float = (span.y - span.x) * 0.90 * fitted_zoom
					if width < text_width: continue
					var score: float = width + candidate_size * 12.0 - absf(offset) * 20.0 - absf(angle - preferred) * 15.0
					var position: Vector2 = origin + direction * (span.x + span.y) * 0.5
					if score > best_score and _ink_fits(territory, position, angle, width, centroid, fitted_zoom):
						best_score = score
						best = {"anchor":origin + direction * (span.x + span.y) * 0.5, "angle":angle, "width":width, "font_size":candidate_size}
		if not best.is_empty(): break
	return best
