@tool
extends RichTextLabel

signal source_hovered(sources: Array, excerpt: String)
signal source_hover_ended

const INK := Color("384238")
const PaperStyle := preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const CHANGED_INK := PaperStyle.ACCENT

var _segments: Array = []
var _annotations: Array[Dictionary] = []
var _current_text := ""
var _hovering_source := false


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	selection_enabled = true
	meta_underlined = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_color_override("default_color", INK)
	add_theme_constant_override("line_separation", 8)
	meta_hover_started.connect(_hover_source)
	meta_hover_ended.connect(func(_meta: Variant) -> void: _end_source_hover())
	mouse_exited.connect(_end_source_hover)


func set_segments(segments: Array, plain_text: String = "") -> void:
	_segments = segments.duplicate(true)
	_annotations.clear()
	var pieces := PackedStringArray()
	var current_pieces := PackedStringArray()
	for segment: Dictionary in _segments:
		var translated := DeskLocalization.text(str(segment.get("text", "")))
		current_pieces.append(translated)
		var escaped := _escape(translated)
		var sources: Array = segment.get("sources", [])
		if sources.is_empty():
			pieces.append(escaped)
		else:
			var index := _annotations.size()
			_annotations.append({"sources":sources.duplicate(true), "text":translated})
			pieces.append("[url=%d][color=#%s][b]%s[/b][/color][/url]" % [index, CHANGED_INK.to_html(false), escaped])
	text = "".join(pieces) if not _segments.is_empty() else _escape(DeskLocalization.text(plain_text))
	_current_text = "".join(current_pieces) if not _segments.is_empty() else DeskLocalization.text(plain_text)
	_end_source_hover()


func _hover_source(meta: Variant) -> void:
	var annotation: Dictionary = _annotations[int(str(meta))]
	_hovering_source = true
	source_hovered.emit(annotation.sources.duplicate(true), str(annotation.text))

func _end_source_hover() -> void:
	_hovering_source = false
	source_hover_ended.emit()

func cursor_shape_at(_point: Vector2) -> int:
	return CURSOR_HELP if _hovering_source else CURSOR_ARROW


func current_text() -> String:
	return _current_text


func inspection() -> Dictionary:
	return {"plain_text":current_text(), "displayed_text":get_parsed_text(), "bbcode":text, "segments":_segments.duplicate(true), "annotations":_annotations.duplicate(true), "rect":get_global_rect()}


func _escape(value: String) -> String:
	return value.replace("[", "[lb]")
