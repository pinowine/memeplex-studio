extends ScrollContainer

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const MentorPortrait = preload("res://scripts/presentation/ui/tutorial/mentor_portrait.gd")
const PORTRAIT = preload("res://assets/image/textures/studio/desk/portrait_67.svg")
const ReceiptHover = preload("res://scripts/presentation/studio/paper/desk_receipt_hover.gd")
const FIELD_COLORS := {
	"group":Style.SECTION_TEAL,
	"metric":Style.SECTION_PURPLE,
	"meme":Style.SECTION_BROWN,
	"language":CardFace.PALETTES.language.ink,
	"module":CardFace.PALETTES.module.ink,
	"topic":CardFace.PALETTES.topic.ink,
	"stance_token":Style.SECTION_PURPLE,
	"pragmatic_token":Style.SECTION_PURPLE
}

class SectionIcon extends Control:
	var kind := "source"
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), kind, ink)

var _column: VBoxContainer
var _blocks: Array[Dictionary] = []
var _headline := ""
var _impact: RichTextLabel
var _portrait: TextureRect
var _hover: PanelContainer
var _numbers := RegEx.create_from_string("[-+]?[0-9]+(?:[.,][0-9]+)*(?:%|％)?")

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 16)
	add_child(_column)
	var overlay := CanvasLayer.new()
	overlay.layer = 60
	add_child(overlay)
	_hover = ReceiptHover.new()
	_hover.name = "EventFieldDescription"
	_hover.set_pointer_following(true)
	_hover.hide()
	overlay.add_child(_hover)
	visibility_changed.connect(_hide_hover)
	get_v_scroll_bar().value_changed.connect(func(_value: float): _hide_hover())

func set_blocks(blocks: Array[Dictionary], full_title: String = "") -> void:
	_blocks = blocks.duplicate(true)
	_headline = full_title
	_hide_hover()
	_impact = null
	_portrait = null
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	if not full_title.is_empty():
		var title := _label(full_title, 25, Style.INK)
		title.name = "Headline"
		title.add_theme_font_override("font", Handwriting.HEADING_FONT)
		_column.add_child(title)
	for block: Dictionary in blocks:
		match str(block.get("role", "")):
			"metadata": _add_metadata(block)
			"narrative": _add_narrative(block)
			"impact": _add_impact(block)
			"commentary": _add_comment(block)

func _add_metadata(block: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "Dateline"
	row.add_theme_constant_override("separation", 16)
	_column.add_child(row)
	row.add_child(_icon(str(block.get("kind", "clock"))))
	var event_type := _label(str(block.get("event_type", "")), 14, Style.SECONDARY_INK)
	event_type.autowrap_mode = TextServer.AUTOWRAP_OFF
	event_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(event_type)
	var timestamp := _label(str(block.get("timestamp", "")), 14, Style.SECONDARY_INK)
	timestamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(timestamp)
	_add_rule()

func _add_rule() -> void:
	var rule := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	_column.add_child(rule)

func _icon(kind: String) -> Control:
	var icon := SectionIcon.new()
	icon.kind = kind
	icon.ink = Style.SECTION_BROWN if kind == "mentor" else Style.SECTION_TEAL
	return icon

func _section(kind: String, section_name: String) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.name = section_name
	row.add_theme_constant_override("separation", 8)
	_column.add_child(row)
	row.add_child(_icon(kind))
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	return content

func _add_narrative(block: Dictionary) -> void:
	var content := _section(str(block.get("kind", "source")), "Article")
	var body := _body(16, Style.INK)
	body.name = "ArticleText"
	body.add_theme_constant_override("paragraph_separation", 16)
	content.add_child(body)
	body.push_paragraph(HORIZONTAL_ALIGNMENT_FILL)
	body.add_text(str(block.content).strip_edges())
	body.pop()

func _add_impact(block: Dictionary) -> void:
	_add_rule()
	var content := _section(str(block.get("kind", "impact")), "Impact")
	content.add_child(_label(str(block.heading), 14, Style.SECONDARY_INK))
	_impact = _body(16, Style.INK)
	_impact.name = "ImpactFields"
	_impact.meta_underlined = false
	content.add_child(_impact)
	var segments: Array = block.get("segments", [])
	_impact.set_meta("segments", segments)
	_impact.push_list(1, RichTextLabel.LIST_DOTS, false)
	for index in segments.size():
		var segment: Dictionary = segments[index]
		var annotated := not str(segment.get("tooltip_body", "")).is_empty()
		if annotated:
			_impact.push_meta(index, RichTextLabel.META_UNDERLINE_NEVER)
			_impact.push_color(FIELD_COLORS[str(segment.field_kind)])
		_write_content(_impact, str(segment.text))
		if annotated:
			_impact.pop()
			_impact.pop()
	_impact.pop()
	_impact.meta_hover_started.connect(func(meta: Variant):
		var field: Dictionary = segments[int(meta)]
		_hover.set_content(str(field.tooltip_title), [], str(field.tooltip_body), {"kind":str(field.field_kind)})
		_hover.show()
		_hover.fit_at(get_viewport().get_mouse_position(), get_viewport().get_visible_rect()))
	_impact.meta_hover_ended.connect(func(_meta: Variant): _hide_hover())
	_impact.mouse_exited.connect(_hide_hover)

func _add_comment(block: Dictionary) -> void:
	_add_rule()
	var row := HBoxContainer.new()
	row.name = "Comment67"
	row.add_theme_constant_override("separation", 16)
	_column.add_child(row)
	row.add_child(_icon(str(block.get("kind", "mentor"))))
	_portrait = MentorPortrait.new()
	_portrait.name = "Portrait67"
	_portrait.texture = PORTRAIT
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(56, 56)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.ready.connect(_portrait.set_emotion.bind("thinking"))
	row.add_child(_portrait)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	var body := _body(16, Style.SECONDARY_INK)
	content.add_child(body)
	body.add_text(str(block.content))

func _label(text: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Handwriting.SEMIBOLD_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	return label

func _body(font_size: int, ink: Color) -> RichTextLabel:
	var body := RichTextLabel.new()
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = true
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", Handwriting.BODY_FONT)
	body.add_theme_font_override("bold_font", Handwriting.BOLD_FONT)
	body.add_theme_font_size_override("normal_font_size", font_size)
	body.add_theme_font_size_override("bold_font_size", font_size)
	body.add_theme_color_override("default_color", ink)
	body.add_theme_constant_override("line_separation", 8)
	return body

func _write_content(label: RichTextLabel, text: String) -> void:
	var cursor := 0
	for number: RegExMatch in _numbers.search_all(text):
		label.add_text(text.substr(cursor, number.get_start() - cursor))
		label.push_bold()
		label.add_text(number.get_string())
		label.pop()
		cursor = number.get_end()
	label.add_text(text.substr(cursor))

func _hide_hover() -> void:
	_hover.hide()

func inspection() -> Dictionary:
	return {"blocks":_blocks.duplicate(true), "headline":_headline, "scrollable":true,
		"content_height":_column.size.y, "viewport_height":size.y, "columns":1,
		"impact_text":_impact.get_parsed_text() if _impact != null else "",
		"impact_segments":_impact.get_meta("segments") if _impact != null else [],
		"portrait":_portrait.inspection() if _portrait != null else {},
		"field_hover_visible":_hover.visible, "field_hover_text":_hover.content_text(),
		"horizontal_overflow":_column.size.x > size.x + 1}
