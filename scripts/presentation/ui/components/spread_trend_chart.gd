extends Control

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
var samples: Array = []
var show_deviation := true
var show_labels := true
var font_size := 12
var spread_ink := Typography.ACCENT
var deviation_ink := Color("ad4438")

func _init() -> void:
	custom_minimum_size = Vector2(0, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_samples(values: Array) -> void:
	if samples == values: return
	samples = values.duplicate(true)
	queue_redraw()

func _draw() -> void:
	var font := Typography.font("annotation")
	var row_height := float(font_size + 6)
	var top := row_height if show_labels else 4.0
	var plot := Rect2(0, top, size.x, maxf(1, size.y - top - row_height))
	var latest: Dictionary = samples[-1] if not samples.is_empty() else {"spread":0.0,"deviation":0.0}
	var spread_label := "%s %.2f%%" % [DeskLocalization.text("MM_SPREAD"),float(latest.spread)*100.0]
	var deviation_label := "%s %.1f%%" % [DeskLocalization.text("MM_DEVIATION"),float(latest.deviation)*100.0]
	if show_labels:
		draw_string(font, Vector2(0, font_size), spread_label, HORIZONTAL_ALIGNMENT_LEFT, size.x * .52 if show_deviation else size.x, font_size, spread_ink)
		if show_deviation: draw_string(font, Vector2(size.x * .55, font_size), deviation_label, HORIZONTAL_ALIGNMENT_LEFT, size.x * .45, font_size, deviation_ink)
	for fraction in [0.0, .5, 1.0]:
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(Vector2(0,y), Vector2(size.x,y), Color(Typography.MUTED,.2))
	if samples.is_empty(): return
	var first := float(samples[0].hour)
	for field: String in (["spread", "deviation"] if show_deviation else ["spread"]):
		var points := curve_points(field)
		var ink := spread_ink if field == "spread" else deviation_ink
		if points.size() > 1: draw_polyline(points, ink, 1.5, true)
		draw_circle(points[-1], 2, ink)
	draw_string(font, Vector2(0,size.y-2), "H%d" % int(first), HORIZONTAL_ALIGNMENT_LEFT, size.x * .5, font_size, Typography.MUTED)
	draw_string(font, Vector2(size.x * .5,size.y-2), "H%d" % int(samples[-1].hour), HORIZONTAL_ALIGNMENT_RIGHT, size.x * .5, font_size, Typography.MUTED)

func value_range() -> Vector2:
	var maximum := .01
	for sample: Dictionary in samples:
		maximum = maxf(maximum, float(sample.spread))
		if show_deviation: maximum = maxf(maximum, float(sample.deviation))
	return Vector2(0,maximum)

func curve_points(field: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if samples.is_empty(): return points
	var row_height := float(font_size + 6)
	var top := row_height if show_labels else 4.0
	var plot := Rect2(0, top, size.x, maxf(1, size.y - top - row_height))
	var first := float(samples[0].hour)
	var duration := maxf(1, float(samples[-1].hour) - first)
	var maximum := value_range().y
	for sample: Dictionary in samples:
		points.append(plot.position + Vector2((float(sample.hour)-first)/duration * plot.size.x, (1.0-float(sample[field])/maximum) * plot.size.y))
	return points
