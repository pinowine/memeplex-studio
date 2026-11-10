@tool
extends RichTextLabel

signal source_hovered(sources: Array, excerpt: String)
signal source_hover_ended

const INK := Color("384238")
const CHANGED_INK := Color("9d503c")

var _segments: Array = []
var _annotations: Array[Dictionary] = []


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
	meta_hover_ended.connect(func(_meta: Variant) -> void: source_hover_ended.emit())
	mouse_exited.connect(func() -> void: source_hover_ended.emit())


func set_segments(segments: Array, plain_text: String = "") -> void:
	_segments = segments.duplicate(true)
	_annotations.clear()
	var pieces := PackedStringArray()
	for segment: Dictionary in _segments:
		var translated := DeskLocalization.text(str(segment.get("text", "")))
		var escaped := _escape(translated)
		var sources: Array = segment.get("sources", [])
		if sources.is_empty():
			pieces.append(escaped)
		else:
			var index := _annotations.size()
			_annotations.append({"sources":sources.duplicate(true), "text":translated})
			pieces.append("[url=%d][color=#%s][b][u]%s[/u][/b][/color][/url]" % [index, CHANGED_INK.to_html(false), escaped])
	text = "".join(pieces) if not _segments.is_empty() else _escape(DeskLocalization.text(plain_text))
	source_hover_ended.emit()


func _hover_source(meta: Variant) -> void:
	var annotation: Dictionary = _annotations[int(str(meta))]
	source_hovered.emit(annotation.sources.duplicate(true), str(annotation.text))


func inspection() -> Dictionary:
	return {"plain_text":get_parsed_text(), "bbcode":text, "segments":_segments.duplicate(true), "annotations":_annotations.duplicate(true), "rect":get_global_rect()}


func _escape(value: String) -> String:
	return value.replace("[", "[lb]")
