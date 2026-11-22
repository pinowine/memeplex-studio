extends Control

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
var samples: Array = []
var show_deviation := true
var show_labels := true
var values_in_labels := true
var metric := ""
var font_size := 12
var spread_ink := Typography.ACCENT
var deviation_ink := Color("ad4438")
var growth_ink := Color("566187")
var deviation_threshold := 0.5

func _init() -> void:
	custom_minimum_size = Vector2(0, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_samples(values: Array) -> void:
	if samples == values: return
	samples = values.duplicate(true)
	if not samples.is_empty(): deviation_threshold = float(samples[-1].get("deviation_threshold", .5))
	queue_redraw()

func _draw() -> void:
	var font := Typography.font("annotation")
	var plot := _plot_rect()
	var latest: Dictionary = samples[-1] if not samples.is_empty() else {"spread":0.0,"deviation":0.0}
	if not metric.is_empty():
		draw_string(font, Vector2(0, font_size), DeskLocalization.text("MM_" + metric.to_upper()), HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size, _series_ink(metric))
	elif show_labels:
		var spread_label := DeskLocalization.text("MM_SPREAD")
		var deviation_label := DeskLocalization.text("MM_DEVIATION")
		if values_in_labels:
			spread_label += " %.2f%%" % (float(latest.spread) * 100.0)
			deviation_label += " %.1f%%" % (float(latest.deviation) * 100.0)
		draw_string(font, Vector2(0, font_size), spread_label, HORIZONTAL_ALIGNMENT_LEFT, size.x * .52 if show_deviation else size.x, font_size, spread_ink)
		if show_deviation: draw_string(font, Vector2(size.x * .55, font_size), deviation_label, HORIZONTAL_ALIGNMENT_LEFT, size.x * .45, font_size, deviation_ink)
	for fraction in [0.0, .5, 1.0]:
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(Vector2(0,y), Vector2(size.x,y), Color(Typography.MUTED,.2))
	if show_deviation and metric.is_empty():
		var y := plot.position.y + (1.0 - deviation_threshold / value_range().y) * plot.size.y
		draw_dashed_line(Vector2(0, y), Vector2(size.x, y), Color(deviation_ink, .65), 1.0, 5.0)
		if values_in_labels:
			draw_string(font, Vector2(2, y - 3), DeskLocalization.format_text("MM_DEVIATION_THRESHOLD", deviation_threshold * 100.0), HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size - 1, deviation_ink)
	if samples.is_empty(): return
	var first := float(samples[0].hour)
	var fields := [metric] if not metric.is_empty() else (["spread", "deviation"] if show_deviation else ["spread"])
	for field: String in fields:
		var points := curve_points(field)
		var ink := _series_ink(field)
		if points.size() > 1: draw_polyline(points, ink, 1.5, true)
		draw_circle(points[-1], 2, ink)
	draw_string(font, Vector2(0,size.y-2), "H%d" % int(first), HORIZONTAL_ALIGNMENT_LEFT, size.x * .5, font_size, Typography.MUTED)
	if metric.is_empty() or float(samples[-1].hour) != first:
		draw_string(font, Vector2(size.x * .5,size.y-2), "H%d" % int(samples[-1].hour), HORIZONTAL_ALIGNMENT_RIGHT, size.x * .5, font_size, Typography.MUTED)

func value_range() -> Vector2:
	if metric == "growth":
		var magnitude := .01
		for sample: Dictionary in samples: magnitude = maxf(magnitude, absf(float(sample.get("growth", 0))))
		return Vector2(-magnitude, magnitude)
	if not metric.is_empty():
		var peak := .01
		for sample: Dictionary in samples: peak = maxf(peak, float(sample.get(metric, 0)))
		return Vector2(0, peak)
	var maximum := deviation_threshold * 1.2 if show_deviation else .01
	for sample: Dictionary in samples:
		maximum = maxf(maximum, float(sample.spread))
		if show_deviation: maximum = maxf(maximum, float(sample.deviation))
	return Vector2(0,maximum)

func curve_points(field: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if samples.is_empty(): return points
	var plot := _plot_rect()
	var first := float(samples[0].hour)
	var duration := maxf(1, float(samples[-1].hour) - first)
	var bounds := value_range()
	for sample: Dictionary in samples:
		points.append(plot.position + Vector2((float(sample.hour)-first)/duration * plot.size.x,
			(1.0 - inverse_lerp(bounds.x, bounds.y, float(sample.get(field, 0)))) * plot.size.y))
	return points

func _plot_rect() -> Rect2:
	var row_height := float(font_size + 6)
	var top := row_height if show_labels or not metric.is_empty() else (font_size + 4.0 if show_deviation else 4.0)
	var inset := 0.0 if metric.is_empty() else 3.0
	return Rect2(inset, top, size.x - inset * 2.0, maxf(1.0, size.y - top - row_height))

func _series_ink(field: String) -> Color:
	if field == "growth": return growth_ink
	return spread_ink if field == "spread" else deviation_ink
