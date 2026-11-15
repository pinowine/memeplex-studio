class_name DeskLogPrinter
extends Control

signal event_requested(instance_id: String)
signal details_changed

@export var chars_per_second: float = 240.0
@export var feed_speed: float = 600.0
@export var row_height: float = 24.0
@export var font_size: int = 16
@export var paper_padding: float = 12.0
@export var paper_region_rect := Rect2()
@export var ink_color := Color("302e29")
@export var wheel_scroll_enabled: bool = false
@export var automatic_advance: bool = true
@export var hierarchical_typography: bool = false

var _entries: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _queue: Array[int] = []
var _printed: Array[int] = []
var _active: int = -1
var _feed_height: float = 0.0
var _char_cursor: float = 0.0
var _scroll_offset: float = 0.0
var _generation: int = 0
var _sync_kind: String = "empty"
var _paper_texture: Texture2D
var _grain_texture: Texture2D
var _paper_style: StyleBoxTexture
var _layout_signature: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)


func _ready() -> void:
	resized.connect(_invalidate_layout)
	_update_processing()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_invalidate_layout()
		details_changed.emit()

func configure(texture: Texture2D, grain: Texture2D) -> void:
	_paper_texture = texture
	_grain_texture = grain
	_paper_style = StyleBoxTexture.new()
	_paper_style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_paper_style.set_texture_margin(side, 8.0)
	_paper_style.region_rect = paper_region_rect
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func layout_area(rect: Rect2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = rect.size.max(Vector2.ZERO)
	_invalidate_layout()


func sync_entries(entries: Array) -> void:
	var incoming := _normalize(entries)
	if incoming == _entries:
		_sync_kind = "unchanged"
		return
	var append_only := incoming.size() >= _entries.size()
	for index in mini(incoming.size(), _entries.size()):
		if incoming[index] != _entries[index]:
			append_only = false
			break
	if not append_only or incoming.is_empty():
		_clear_print_state()
		_generation += 1
		_sync_kind = "clear" if incoming.is_empty() else "replace"
	else:
		_sync_kind = "append"
	var start := _entries.size()
	_entries = incoming
	for index in range(start, _entries.size()):
		_rows.append({"printed_chars": 0, "complete": false, "lines": PackedStringArray(), "height": 0.0})
		_queue.append(index)
	_invalidate_layout()
	_update_processing()
	details_changed.emit()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_ensure_layout()
	var remaining := delta
	var characters := _positive(chars_per_second, 240.0)
	var feed := _positive(feed_speed, 600.0)
	# Consume elapsed time, not frame counts, including several queued records.
	while remaining > 0.0:
		if _active < 0:
			if _queue.is_empty():
				break
			_active = _queue.pop_front()
			_printed.append(_active)
			_feed_height = 0.0
			_char_cursor = 0.0
		var height := float(_rows[_active].height)
		if _feed_height < height:
			var feed_time := (height - _feed_height) / feed
			var consumed := minf(remaining, feed_time)
			var before := _feed_height
			_feed_height = minf(height, _feed_height + consumed * feed)
			if consumed >= feed_time:
				_feed_height = height
			if _scroll_offset > 0.0:
				_scroll_offset += _feed_height - before
			remaining = maxf(0.0, remaining - consumed)
			if _feed_height < height:
				break
		var length := str(_rows[_active].display_text).length()
		var print_time := maxf(0.0, float(length) - _char_cursor) / characters
		var consumed := minf(remaining, print_time)
		_char_cursor = minf(float(length), _char_cursor + consumed * characters)
		if consumed >= print_time:
			_char_cursor = float(length)
		_rows[_active].printed_chars = mini(length, int(floor(_char_cursor + 0.000000001)))
		remaining = maxf(0.0, remaining - consumed)
		if _char_cursor >= float(length):
			_rows[_active].complete = true
			_active = -1
		else:
			break
	_clamp_scroll()
	_update_processing()
	queue_redraw()


func scroll_rows(count: float) -> void:
	if not is_finite(count):
		return
	_ensure_layout()
	_scroll_offset += count * _line_height()
	_clamp_scroll()
	queue_redraw()


func inspection() -> Dictionary:
	_ensure_layout()
	var queued := PackedStringArray()
	for index in _queue:
		queued.append(str(_entries[index].id))
	var characters := 0
	var visual_rows := 0
	for index in _printed:
		characters += int(_rows[index].printed_chars)
		visual_rows += _prefix_lines(index).size()
	var active_length := str(_rows[_active].display_text).length() if _active >= 0 else 0
	return {
		"entry_count": _entries.size(), "entries": _entries.duplicate(true),
		"source_order": "oldest_first", "newest_on_top": true,
		"sync_kind": _sync_kind, "generation": _generation,
		"active_id": str(_entries[_active].id) if _active >= 0 else "",
		"active_index": _active, "queue": _queue.size(), "queued_ids": queued,
		"progress": _char_cursor / float(active_length) if active_length > 0 else 1.0,
		"feed_progress": _feed_height / float(_rows[_active].height) if _active >= 0 else 1.0,
		"printed_chars_total": characters, "printed_rows": visual_rows,
		"visible_rows": _visible_rows(), "paper_length": _paper_length(),
		"scroll_offset": _scroll_offset, "scroll_max": _scroll_max(),
		"mouse_filter": mouse_filter, "clip_contents": clip_contents,
		"minimum_size": get_combined_minimum_size(), "layout_rect": Rect2(position, size),
		"receipt_style":"thermal_receipt", "chars_per_second":chars_per_second, "feed_speed":feed_speed,
		"hierarchical_typography": hierarchical_typography, "texture_configured": _paper_texture != null, "grain_configured": _grain_texture != null
	}


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not wheel_scroll_enabled or not is_visible_in_tree() or not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	var local := get_global_transform_with_canvas().affine_inverse() * button.position
	if not button.pressed or not Rect2(Vector2.ZERO, size).has_point(local):
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		var id := event_at(local)
		if not id.is_empty():
			event_requested.emit(id)
			get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_rows(3.0)
	elif button.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_rows(-3.0)
	# Observe an explicitly enabled archive area without consuming map input.


func event_at(local: Vector2) -> String:
	if not Rect2(Vector2.ZERO, size).has_point(local): return ""
	for row in _visible_rows():
		if int(row.printed_chars) > 0 and local.y >= float(row.y) and local.y < float(row.y) + float(row.height):
			return str(row.get("event_id", ""))
	return ""


func _draw() -> void:
	_ensure_layout()
	var length := _paper_length()
	if length <= 0.0:
		return
	var paper_rect := Rect2(0.0, -_scroll_offset, size.x, length)
	draw_rect(paper_rect, Color("e8e2d3"))
	if _paper_style != null and _paper_texture != null:
		_paper_style.region_rect = paper_region_rect
		draw_style_box(_paper_style, paper_rect)
	if _grain_texture != null:
		draw_texture_rect(_grain_texture, paper_rect, true, Color(1.0, 1.0, 1.0, 0.12))
	var font := _font()
	var line_height := _line_height()
	var padding := _padding()
	if hierarchical_typography:
		var top := padding - _scroll_offset
		var width := maxf(1.0, size.x - padding * 2.0)
		draw_string(font, Vector2(padding, top + font.get_ascent(_font_size())), "MEMEPLEX", HORIZONTAL_ALIGNMENT_CENTER, width, _font_size(), ink_color)
		draw_string(font, Vector2(padding, top + line_height + font.get_ascent(_font_size())), DeskLocalization.text("LOC_LOG_RECEIPT_HEADING"), HORIZONTAL_ALIGNMENT_CENTER, width, _font_size(), ink_color)
		_receipt_rule(top + _receipt_header_height() - 4.0)
	for row: Dictionary in _visible_rows():
		var lines: PackedStringArray = row.lines
		if hierarchical_typography and bool(row.complete):
			_receipt_rule(float(row.y) + float(row.height) - 4.0)
		for index in lines.size():
			var baseline := float(row.y) + index * line_height + (line_height - font.get_height(_font_size())) * .5 + font.get_ascent(_font_size())
			var color := Color("68604f") if hierarchical_typography and index == 0 else ink_color
			var alignment := HORIZONTAL_ALIGNMENT_RIGHT if bool(row.amount_line) and index == lines.size() - 1 and bool(row.complete) else HORIZONTAL_ALIGNMENT_LEFT
			draw_string(font, Vector2(padding, baseline), lines[index], alignment, maxf(1.0, size.x - padding * 2.0), _font_size(), color)
			if hierarchical_typography and index == 1:
				# A light second ink pass gives headings weight without wider glyph metrics.
				draw_string(font, Vector2(padding + 0.3, baseline), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size(), color)


func _receipt_rule(y: float) -> void:
	var x := _padding()
	while x < size.x - _padding():
		draw_line(Vector2(x, y), Vector2(minf(x + 3.0, size.x - _padding()), y), Color("b8ad96"), 0.7)
		x += 6.0


func _receipt_header_height() -> float:
	return _line_height() * 2.0 + 8.0 if hierarchical_typography else 0.0


func receipt_details() -> Dictionary:
	var sections: Array[Dictionary] = []
	for index in range(_entries.size() - 1, -1, -1):
		sections.append({"body":_entry_details(_entries[index])})
	return {"title":DeskLocalization.source("LOC_EVENT_LOG_F77E28E6"), "sections":sections,
		"document_kind":"log_receipt", "receipt_width":size.x, "receipt_code":str(_entries.size()).pad_zeros(8),
		"body":DeskLocalization.source("LOC_LOG_RECEIPT_EMPTY") if sections.is_empty() else ""}


func _normalize(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in entries.size():
		var entry: Variant = entries[index]
		if entry is Dictionary:
			var record: Dictionary = entry.duplicate(true)
			record.id = str(record.get("id", "row_%06d" % index))
			record.text = str(record.get("text", ""))
			result.append(record)
		else:
			result.append({"id": "row_%06d" % index, "text": str(entry)})
	return result


func _clear_print_state() -> void:
	_entries.clear()
	_rows.clear()
	_queue.clear()
	_printed.clear()
	_active = -1
	_feed_height = 0.0
	_char_cursor = 0.0
	_scroll_offset = 0.0
	_layout_signature = ""


func _invalidate_layout() -> void:
	_layout_signature = ""
	_ensure_layout()
	queue_redraw()


func _ensure_layout() -> void:
	var signature := str(size.x) + "/" + str(_font_size()) + "/" + str(_line_height()) + "/" + str(_padding()) + "/" + str(_font().get_instance_id()) + "/" + TranslationServer.get_locale()
	if signature == _layout_signature:
		return
	_layout_signature = signature
	var fraction := _feed_height / float(_rows[_active].height) if _active >= 0 and float(_rows[_active].height) > 0.0 else 0.0
	var old_length := str(_rows[_active].get("display_text", "")).length() if _active >= 0 else 0
	var print_fraction := _char_cursor / float(old_length) if old_length > 0 else 0.0
	for index in _rows.size():
		var displayed := _entry_display(_entries[index])
		var lines := _wrap(displayed)
		_rows[index].display_text = displayed
		_rows[index].lines = lines
		_rows[index].height = lines.size() * _line_height() + (10.0 if hierarchical_typography else 0.0)
		if bool(_rows[index].complete): _rows[index].printed_chars = displayed.length()
	if _active >= 0:
		_feed_height = fraction * float(_rows[_active].height)
		_char_cursor = print_fraction * str(_rows[_active].display_text).length()
		_rows[_active].printed_chars = int(floor(_char_cursor))
	_clamp_scroll()


func _wrap(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	var line := ""
	var available := maxf(1.0, size.x - _padding() * 2.0 - (.3 if hierarchical_typography else 0.0))
	var font := _font()
	for index in text.length():
		var character := text.substr(index, 1)
		if character == "\n":
			result.append(line)
			line = ""
			continue
		var candidate := line + character
		if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x > available:
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
			line = candidate
	result.append(line)
	return result


func _visible_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var y := _padding() + _receipt_header_height() - _scroll_offset
	for printed_index in range(_printed.size() - 1, -1, -1):
		var index := _printed[printed_index]
		var height := _feed_height if index == _active else float(_rows[index].height)
		if height > 0.0 and y + height > 0.0 and y < size.y:
			result.append({
				"id": str(_entries[index].id), "event_id":str(_entries[index].get("event_id", "")), "text": _display_prefix(index), "canonical_text":str(_entries[index].text).left(int(_rows[index].printed_chars)),
				"printed_chars": int(_rows[index].printed_chars), "complete": bool(_rows[index].complete),
				"lines":_prefix_lines(index), "amount_line":str(_entries[index].get("receipt", {}).get("kind", "")) == "points",
				"y": y, "height": height
			})
		y += height
	return result


func _paper_length() -> float:
	if _printed.is_empty():
		return 0.0
	var length := _padding() * 2.0 + _receipt_header_height()
	for index in _printed:
		length += _feed_height if index == _active else float(_rows[index].height)
	return length


func _scroll_max() -> float:
	return maxf(0.0, _paper_length() - size.y)


func _clamp_scroll() -> void:
	_scroll_offset = clampf(_scroll_offset, 0.0, _scroll_max())


func _update_processing() -> void:
	set_process(automatic_advance and (_active >= 0 or not _queue.is_empty()))


func _font() -> Font:
	return get_theme_font("font", "Label")


func _font_size() -> int:
	return clampi(font_size, 1, 128)


func _line_height() -> float:
	return maxf(_positive(row_height, 24.0), ceilf(_font().get_height(_font_size())) + 2.0)


func _padding() -> float:
	return maxf(0.0, paper_padding) if is_finite(paper_padding) else 12.0


func _positive(value: float, fallback: float) -> float:
	return value if is_finite(value) and value > 0.0 else fallback

func _display_prefix(index: int) -> String:
	return str(_rows[index].display_text).left(int(_rows[index].printed_chars))

func _prefix_lines(index: int) -> PackedStringArray:
	if bool(_rows[index].complete): return _rows[index].lines
	return _wrap(_display_prefix(index))

func _localized_block(source: String) -> String:
	var exact := str(TranslationServer.translate(StringName(source)))
	if exact != source: return exact
	return "\n".join(DeskLocalization.lines(Array(source.split("\n",true))))

func _entry_display(entry: Dictionary) -> String:
	if not entry.has("receipt"): return _entry_details(entry)
	var receipt: Dictionary = entry.receipt
	var kind := str(receipt.kind)
	var label := DeskLocalization.text("LOC_LOG_RECEIPT_" + kind.to_upper())
	var heading := "H%03d  %s" % [int(receipt.hour), label]
	var title := _localized_block(str(receipt.title)).replace("\n", " ").strip_edges()
	var lines := PackedStringArray([heading, title])
	if kind == "points":
		lines.append("%+d  %s %d" % [int(receipt.delta), DeskLocalization.text("LOC_LOG_RECEIPT_BALANCE"), int(receipt.balance)])
	return "\n".join(lines)

func _entry_details(entry: Dictionary) -> String:
	if entry.get("display_template") is String and entry.get("display_arguments") is Array:
		var values: Array = entry.display_arguments.duplicate()
		for position: Variant in entry.get("localize_arguments",[]):
			if position is int and position >= 0 and position < values.size() and (values[position] is String or values[position] is StringName):
				values[position] = _localized_block(str(values[position]))
		return DeskLocalization.format_text(str(entry.display_template),values)
	return _localized_block(str(entry.text))
