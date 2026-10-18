class_name DeskMemeMonitor
extends Control

@export var font_size: int = 13
@export var screen_padding: float = 10.0
@export var curve_height: float = 52.0
@export var maximum_samples: int = 128
@export var background_color := Color("06140b")
@export var ink_color := Color("93c48a")
@export var dim_color := Color("41633d")
@export var scanline_opacity: float = 0.07

var _title: String = "待印的模因"
var _title_source: String = "none"
var _hour: int = 0
var _balance: int = 0
var _origin_balance: int = 0
var _last_delta: int = 0
var _last_change_hour: int = 0
var _has_balance: bool = false
var _has_change: bool = false
var _history: Array[Dictionary] = []
var _dropped_samples: int = 0
var _reset_count: int = 0
var _last_error: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func layout_screen(rect: Rect2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = rect.size.max(Vector2.ZERO)
	queue_redraw()


func sync_state(state: Dictionary) -> void:
	if not _nonnegative_integer(state.get("meme_points")) or not _nonnegative_integer(state.get("hour")):
		_last_error = "meme_points and hour must be finite nonnegative integers"
		return
	_last_error = ""
	var hour := int(state.hour)
	var balance := int(state.meme_points)
	var title := _select_title(state)
	var changed := _hour != hour or _title != str(title.text) or _title_source != str(title.source)
	_hour = hour
	_title = str(title.text)
	_title_source = str(title.source)
	if not _has_balance:
		_has_balance = true
		_origin_balance = balance
		_balance = balance
		_history.append({"hour":hour, "balance":balance, "delta":0, "net_change":0, "baseline":true})
		changed = true
	elif balance != _balance:
		_last_delta = balance - _balance
		_last_change_hour = hour
		_has_change = true
		_balance = balance
		_history.append({"hour":hour, "balance":balance, "delta":_last_delta, "net_change":balance - _origin_balance, "baseline":false})
		changed = true
	changed = _trim_history() or changed
	if changed:
		queue_redraw()


func reset_history() -> void:
	_history.clear()
	_title = "待印的模因"
	_title_source = "none"
	_hour = 0
	_balance = 0
	_origin_balance = 0
	_last_delta = 0
	_last_change_hour = 0
	_has_balance = false
	_has_change = false
	_dropped_samples = 0
	_reset_count += 1
	_last_error = ""
	queue_redraw()


func inspection() -> Dictionary:
	return {
		"title": _title, "title_source": _title_source, "hour": _hour,
		"meme_points": _balance, "origin_balance": _origin_balance,
		"last_delta": _last_delta, "last_change_hour": _last_change_hour,
		"has_balance": _has_balance, "has_change": _has_change,
		"net_change": _balance - _origin_balance if _has_balance else 0,
		"history": _history.duplicate(true), "sample_count": _history.size(),
		"sample_limit": _sample_limit(), "dropped_samples": _dropped_samples,
		"reset_count": _reset_count, "last_error": _last_error,
		"curve_rect": _plot_rect(), "curve_points": _curve_points(),
		"curve_x_mode": _x_mode(), "curve_range": _net_range(),
		"layout_mode": "compact" if _compact() else "full",
		"title_rect": _title_rect(), "balance_rect": _balance_rect(), "axis_rect": _axis_rect(),
		"measurement": "Snapshot balance changes, not parsed income/expense transactions",
		"economic_log_parsed": false, "font_source": "theme Label font",
		"layout_rect": Rect2(position, size), "minimum_size": get_combined_minimum_size(),
		"mouse_filter": mouse_filter, "clip_contents": clip_contents
	}


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var opacity := clampf(scanline_opacity, 0.0, 0.35) if is_finite(scanline_opacity) else 0.07
	for line in range(0, int(size.y), 3):
		draw_line(Vector2(0, line), Vector2(size.x, line), Color(0, 0, 0, opacity))
	var font := get_theme_font("font", "Label")
	if _compact():
		_draw_compact(font)
		return
	var fs := _font_size()
	var padding := _padding()
	var line_height := float(fs + 5)
	_draw_mono(font, "MEME / H%d" % _hour, Vector2(padding, padding + font.get_ascent(fs)), fs, dim_color)
	_draw_mono(font, "模因：" + _title.replace("\n", " ").replace("\r", " "), Vector2(padding, padding + line_height + font.get_ascent(fs)), fs, ink_color)
	_draw_mono(font, "Meme %s" % (str(_balance) if _has_balance else "--"), Vector2(padding, padding + line_height * 2.0 + font.get_ascent(fs + 5)), fs + 5, ink_color)
	var delta_text := "上次 %s / H%d" % [_signed(_last_delta), _last_change_hour] if _has_change else "上次 -- / 首次快照"
	_draw_mono(font, delta_text, Vector2(padding, padding + line_height * 3.4 + font.get_ascent(fs)), fs, ink_color)
	_draw_mono(font, "净变化 / 快照余额", Vector2(padding, padding + line_height * 4.5 + font.get_ascent(fs)), fs, dim_color)
	var plot := _plot_rect()
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return
	_draw_plot(plot)
	var time_text := "等待余额快照"
	if not _history.is_empty():
		time_text = "H%d > H%d / 净%s" % [int(_history[0].hour), int(_history[-1].hour), _signed(_balance - _origin_balance)]
		if _x_mode() == "change_index_same_hour":
			time_text = "H%d / %d 个快照点" % [int(_history[0].hour), _history.size()]
	_draw_mono(font, time_text, Vector2(padding, plot.end.y + line_height), fs, dim_color)
	var scale := _net_range()
	_draw_mono(font, "%s..%s" % [str(int(scale.x)), str(int(scale.y))], Vector2(padding, plot.end.y + line_height * 2.0), maxi(8, fs - 2), dim_color)


func _draw_compact(font: Font) -> void:
	var title := _title_rect()
	_draw_mono(font, _title.replace("\n", " ").replace("\r", " "), title.position + Vector2(0, font.get_ascent(11)), 11, ink_color)
	var balance := _balance_rect()
	var text := "Meme%s 上次%s" % [str(_balance) if _has_balance else "--", _signed(_last_delta) if _has_change else "--"]
	_draw_mono(font, text, balance.position + Vector2(0, font.get_ascent(13)), 13, ink_color)
	var plot := _plot_rect()
	if plot.size.x > 0.0 and plot.size.y > 0.0:
		_draw_plot(plot)
	var first_hour := int(_history[0].hour) if not _history.is_empty() else _hour
	var last_hour := int(_history[-1].hour) if not _history.is_empty() else _hour
	var axis := _axis_rect()
	_draw_mono(font, "H%d > H%d / 快照" % [first_hour, last_hour], axis.position + Vector2(0, font.get_ascent(9)), 9, dim_color)


func _draw_plot(plot: Rect2) -> void:
	for fraction in [0.0, 0.5, 1.0]:
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(dim_color, 0.55))
	var points := _curve_points()
	if points.size() > 1:
		draw_polyline(points, ink_color, 1.5, true)
	for point in points:
		draw_circle(point, 2.0, ink_color)


func _select_title(state: Dictionary) -> Dictionary:
	var draft: Variant = state.get("latest_draft")
	if draft is Dictionary:
		for key in ["target", "title"]:
			var value := str(draft.get(key, "")).strip_edges()
			if not value.is_empty():
				return {"text":value, "source":"latest_draft." + key}
	var lineage: Variant = state.get("lineage", [])
	if lineage is Array:
		for index in range(lineage.size() - 1, -1, -1):
			var branch: Variant = lineage[index]
			if not branch is Dictionary or not bool(branch.get("owned", false)) or str(branch.get("creator", "")) != "player":
				continue
			for key in ["target", "title", "text"]:
				var value := str(branch.get(key, "")).strip_edges()
				if not value.is_empty():
					return {"text":value, "source":"owned_branch." + key}
	return {"text":"待印的模因", "source":"none"}


func _trim_history() -> bool:
	var trimmed := false
	while _history.size() > _sample_limit():
		_history.pop_front()
		_dropped_samples += 1
		trimmed = true
	return trimmed


func _plot_rect() -> Rect2:
	var padding := _padding()
	if _compact():
		var top := minf(size.y, 42.0)
		return Rect2(padding, top, maxf(0.0, size.x - padding * 2.0), maxf(0.0, size.y - 16.0 - top))
	var line_height := float(_font_size() + 5)
	var top := minf(size.y, padding + line_height * 5.5)
	var available := maxf(0.0, size.y - top - padding - line_height * 2.3)
	var height := minf(available, maxf(0.0, curve_height) if is_finite(curve_height) else 52.0)
	return Rect2(padding, top, maxf(0.0, size.x - padding * 2.0), height)


func _compact() -> bool:
	return size.y < 200.0


func _title_rect() -> Rect2:
	var top := 3.0 if _compact() else _padding() + float(_font_size() + 5)
	return _row_rect(top, 16.0 if _compact() else float(_font_size() + 5))


func _balance_rect() -> Rect2:
	var top := 22.0 if _compact() else _padding() + float(_font_size() + 5) * 2.0
	return _row_rect(top, 18.0 if _compact() else float(_font_size() + 10))


func _axis_rect() -> Rect2:
	var top := maxf(0.0, size.y - 14.0) if _compact() else _plot_rect().end.y
	return _row_rect(top, 12.0 if _compact() else float(_font_size() + 5) * 2.0)


func _row_rect(top: float, height: float) -> Rect2:
	var y := clampf(top, 0.0, size.y)
	return Rect2(_padding(), y, maxf(0.0, size.x - _padding() * 2.0), minf(height, size.y - y))


func _curve_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	var plot := _plot_rect()
	if _history.is_empty() or plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return result
	var scale := _net_range()
	var range_size := maxf(1.0, scale.y - scale.x)
	var first_hour := float(_history[0].hour)
	var hour_range := float(_history[-1].hour) - first_hour
	for index in _history.size():
		var x := float(index) / maxf(1.0, _history.size() - 1)
		if hour_range > 0.0:
			x = clampf((float(_history[index].hour) - first_hour) / hour_range, 0.0, 1.0)
		var y := 0.5 if scale.x == scale.y else 1.0 - (float(_history[index].net_change) - scale.x) / range_size
		result.append(plot.position + Vector2(x * plot.size.x, y * plot.size.y))
	return result


func _net_range() -> Vector2:
	if _history.is_empty():
		return Vector2.ZERO
	var low := float(_history[0].net_change)
	var high := low
	for sample in _history:
		low = minf(low, float(sample.net_change))
		high = maxf(high, float(sample.net_change))
	return Vector2(low, high)


func _x_mode() -> String:
	if _history.size() > 1 and int(_history[0].hour) != int(_history[-1].hour):
		return "hour"
	return "change_index_same_hour"


func _draw_mono(font: Font, text: String, baseline: Vector2, fs: int, color: Color) -> void:
	var x := baseline.x
	var right := size.x - _padding()
	var cell := maxf(1.0, font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	# Keep the theme's Chinese fallback; only Latin advances use a mono grid.
	for index in text.length():
		var character := text.substr(index, 1)
		var advance := maxf(cell, font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if x + advance > right:
			break
		draw_string(font, Vector2(x, baseline.y), character, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, color)
		x += advance


func _nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floor(float(value)) and float(value) < 9223372036854775807.0


func _sample_limit() -> int:
	return clampi(maximum_samples, 1, 128)


func _font_size() -> int:
	return clampi(font_size, 8, 64)


func _padding() -> float:
	var padding := clampf(screen_padding if is_finite(screen_padding) else 10.0, 0.0, minf(size.x, size.y) / 4.0)
	return minf(padding, 6.0) if _compact() else padding


func _signed(value: int) -> String:
	return ("+" if value >= 0 else "") + str(value)
