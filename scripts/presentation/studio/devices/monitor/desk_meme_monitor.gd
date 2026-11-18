class_name DeskMemeMonitor
extends Control

const TrendChart = preload("res://scripts/presentation/ui/components/spread_trend_chart.gd")
const Details = preload("res://scripts/presentation/map/meme_map_details.gd")

@export var font_size: int = 13
@export var screen_padding: float = 10.0
@export var curve_height: float = 52.0
@export var maximum_samples: int = 128
@export var background_color := Color("06140b")
@export var ink_color := Color("93c48a")
@export var dim_color := Color("41633d")
@export var scanline_opacity: float = 0.07

var _title: String = DeskLocalization.source("LOC_MEME_AWAITING_PRINT_02E38C0D")
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
var _language_id := ""
var _language_title := ""
var _spread_history: Array = []
var _trend: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_trend = TrendChart.new()
	_trend.custom_minimum_size = Vector2.ZERO
	_trend.spread_ink = ink_color
	_trend.deviation_ink = Color("ddba74")
	add_child(_trend)


func layout_screen(rect: Rect2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = rect.size.max(Vector2.ZERO)
	queue_redraw()


func sync_state(state: Dictionary) -> void:
	_sync_language(state)
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
	_spread_history.clear()
	_language_id = ""
	_trend.set_samples([])
	_history.clear()
	_title = DeskLocalization.source("LOC_MEME_AWAITING_PRINT_02E38C0D")
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
		"curve_rect": _plot_rect(), "curve_points": _trend.curve_points("spread"),
		"deviation_curve_points":_trend.curve_points("deviation"),
		"curve_x_mode": "hour", "curve_range": _trend.value_range(),
		"layout_mode": "compact" if _compact() else "full",
		"title_rect": _title_rect(), "balance_rect": _balance_rect(), "axis_rect": _axis_rect(),
		"title_text_layout": _title_text_layout(),
		"measurement": "Language spread and weighted meaning deviation", "tracked_language":_language_id,
		"language_title":_language_title, "spread_history":_spread_history.duplicate(true),
		"economic_log_parsed": false, "font_source": "theme Label font",
		"layout_rect": Rect2(position, size), "minimum_size": get_combined_minimum_size(),
		"mouse_filter": mouse_filter, "clip_contents": clip_contents
	}

var _presentation_mirror := false

func apply_presentation(snapshot: Dictionary) -> void:
	_presentation_mirror = true
	_language_id = str(snapshot.get("tracked_language", ""))
	_language_title = str(snapshot.get("language_title", ""))
	_spread_history = snapshot.get("spread_history", []).duplicate(true)
	_trend.set_samples(_spread_history)
	# A detached screen renderer mirrors existing history without advancing it.
	_title = str(snapshot.get("title", _title))
	_title_source = str(snapshot.get("title_source", _title_source))
	_hour = int(snapshot.get("hour", _hour))
	_balance = int(snapshot.get("meme_points", _balance))
	_origin_balance = int(snapshot.get("origin_balance", _origin_balance))
	_last_delta = int(snapshot.get("last_delta", _last_delta))
	_last_change_hour = int(snapshot.get("last_change_hour", _last_change_hour))
	_has_balance = bool(snapshot.get("has_balance", _has_balance))
	_has_change = bool(snapshot.get("has_change", _has_change))
	var samples: Array = snapshot.get("history", [])
	_history.assign(samples.duplicate(true))
	_dropped_samples = int(snapshot.get("dropped_samples", _dropped_samples))
	_reset_count = int(snapshot.get("reset_count", _reset_count))
	_last_error = str(snapshot.get("last_error", _last_error))
	queue_redraw()


func _sync_language(state: Dictionary) -> void:
	var draft: Dictionary = state.get("design_state", {}).get("context_draft", {})
	var language := str(draft.get("language_id", ""))
	if language != _language_id:
		_language_id = language
		_spread_history.clear()
	_language_title = ""
	for entry: Dictionary in load("res://data/context/context_resources.tres").entries:
		if str(entry.kind) == "language" and str(entry.value) == language:
			_language_title = DeskLocalization.text(str(entry.title))
			break
	var spread := 0.0
	var deviation := 0.0
	var threshold := 0.5
	for raw: Dictionary in state.get("lineage", []):
		var profile: Dictionary = raw.get("flow_profile", {})
		if language.is_empty() or language not in profile.get("language_ids", [profile.get("language_id", "")]): continue
		if not bool(profile.get("context_layer_attachment", {}).get("language", true)): continue
		var metrics := Details.monitor_metrics(state, str(raw.id))
		spread += float(metrics.spread)
		deviation += float(metrics.deviation) * float(metrics.spread)
		if str(raw.id) == str(state.get("current_variant_id", "")): threshold = float(metrics.deviation_threshold)
	var sample := {"hour":int(state.get("hour", 0)), "spread":minf(1.0, spread), "deviation":deviation / spread if spread > 0.0 else 0.0, "deviation_threshold":threshold}
	if not _spread_history.is_empty() and int(_spread_history[-1].hour) > int(sample.hour): _spread_history.clear()
	if not _spread_history.is_empty() and int(_spread_history[-1].hour) == int(sample.hour): _spread_history.pop_back()
	_spread_history.append(sample)
	if _spread_history.size() > maximum_samples: _spread_history.pop_front()
	_trend.set_samples(_spread_history)
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0: return
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var font := get_theme_font("font", "Label")
	var padding := _padding()
	var fs := 11 if _compact() else _font_size()
	_draw_mono(font, _language_title, Vector2(padding,padding+font.get_ascent(fs)), fs, ink_color)
	_draw_mono(font, "Meme %d" % _balance, Vector2(padding,padding+fs+6+font.get_ascent(fs)), fs, ink_color)
	var top := padding + (fs + 6) * 2.0
	_trend.font_size = fs
	_trend.position = Vector2(padding, top)
	_trend.size = Vector2(maxf(0,size.x-padding*2),maxf(0,size.y-top-padding))


func _draw_compact(font: Font) -> void:
	var title := _title_rect()
	_draw_mono(font, str(_title_text_layout().text), title.position + Vector2(0, font.get_ascent(11)), 11, ink_color)
	var balance := _balance_rect()
	var text := DeskLocalization.format_text("LOC_MEME_S_PREVIOUS_S_894D6A67", [str(_balance) if _has_balance else "--", _signed(_last_delta) if _has_change else "--"])
	_draw_mono(font, text, balance.position + Vector2(0, font.get_ascent(13)), 13, ink_color)
	var plot := _plot_rect()
	if plot.size.x > 0.0 and plot.size.y > 0.0:
		_draw_plot(plot)
	var first_hour := int(_history[0].hour) if not _history.is_empty() else _hour
	var last_hour := int(_history[-1].hour) if not _history.is_empty() else _hour
	var axis := _axis_rect()
	_draw_mono(font, DeskLocalization.format_text("LOC_H_D_H_D_SNAPSHOT_803657E4", [first_hour, last_hour]), axis.position + Vector2(0, font.get_ascent(9)), 9, dim_color)


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
	return {"text":DeskLocalization.source("LOC_MEME_AWAITING_PRINT_02E38C0D"), "source":"none"}


func _trim_history() -> bool:
	var trimmed := false
	while _history.size() > _sample_limit():
		_history.pop_front()
		_dropped_samples += 1
		trimmed = true
	return trimmed


func _plot_rect() -> Rect2:
	var padding := _padding()
	var row_height := float((11 if _compact() else _font_size()) + 6)
	var top := padding + row_height * 3.0
	return Rect2(padding, top, maxf(0.0, size.x-padding*2), maxf(0.0,size.y-padding-top-row_height))


func _compact() -> bool:
	return size.y < 200.0


func _title_rect() -> Rect2:
	return _row_rect(_padding(), 16.0 if _compact() else float(_font_size() + 5))


func _balance_rect() -> Rect2:
	var top := _padding() + float((11 if _compact() else _font_size()) + 6)
	return _row_rect(top, 18.0 if _compact() else float(_font_size() + 10))


func _axis_rect() -> Rect2:
	var top := _plot_rect().end.y
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


func _mono_text_width(font: Font, text: String, fs: int) -> float:
	var cell := maxf(1.0, font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var width := 0.0
	for character: String in text:
		width += maxf(cell, font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return width


func _title_text_layout() -> Dictionary:
	var font := get_theme_font("font", "Label")
	var fs := 11 if _compact() else _font_size()
	var title := _language_title
	var text := title.replace("\n", " ").replace("\r", " ")
	var rect := _title_rect()
	var truncated := _mono_text_width(font, text, fs) > rect.size.x
	var visible := text
	if truncated:
		visible = ""
		# The mark uses the same per-glyph advances as the CRT renderer.
		# Hover carries the original title; the displayed row is never the source.
		if _mono_text_width(font, "…", fs) <= rect.size.x:
			for character: String in text:
				if _mono_text_width(font, visible + character + "…", fs) > rect.size.x: break
				visible += character
			visible += "…"
	return {"text":visible, "full_text":title, "truncated":truncated, "font_size":fs, "width":_mono_text_width(font, visible, fs), "rect":rect}


func title_hover_info(viewport_point: Vector2) -> Dictionary:
	if not is_visible_in_tree(): return {}
	var local := get_global_transform_with_canvas().affine_inverse() * viewport_point
	if not _title_rect().has_point(local): return {}
	var layout := _title_text_layout()
	return {"kind":"meme_title", "title":layout.full_text, "description":layout.full_text, "truncated":layout.truncated}


func _draw_mono(font: Font, text: String, baseline: Vector2, fs: int, color: Color) -> void:
	if _presentation_mirror:
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, size.x-_padding()-baseline.x), fs, color)
		return
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()
