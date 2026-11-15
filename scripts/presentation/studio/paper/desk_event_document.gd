extends PanelContainer

signal meme_selected(id: String)

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
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
	"pragmatic_token":Style.SECTION_PURPLE,
	"event_type":Style.SECTION_TEAL
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
var _header: VBoxContainer
var _scroll: ScrollContainer
var _article: RichTextLabel
var _article_rule: HSeparator
var _blocks: Array[Dictionary] = []
var _headline := ""
var _impact: VBoxContainer
var _impact_labels: Array[RichTextLabel] = []
var _portrait: TextureRect
var _hover: PanelContainer
var _numbers := RegEx.create_from_string("[-+]?[0-9]+(?:[.,][0-9]+)*(?:%|％)?")
var scroll_vertical: int:
	get: return _scroll.scroll_vertical
	set(value): _scroll.scroll_vertical = value

func _init() -> void:
	var paper := Style.new()
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: paper.set_content_margin(side, 20)
	add_theme_stylebox_override("panel", paper)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	_header = VBoxContainer.new()
	_header.name = "StickyHeader"
	_header.add_theme_constant_override("separation", 12)
	layout.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.name = "ArticleScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_force_pass_scroll_events = false
	layout.add_child(_scroll)
	var gutter := MarginContainer.new()
	gutter.name = "ScrollbarGutter"
	gutter.add_theme_constant_override("margin_right", 16)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(gutter)
	_column = VBoxContainer.new()
	_column.name = "ArticleSections"
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_column.add_theme_constant_override("separation", 12)
	gutter.add_child(_column)
	var overlay := CanvasLayer.new()
	overlay.layer = 60
	add_child(overlay)
	_hover = ReceiptHover.new()
	_hover.name = "EventFieldDescription"
	_hover.set_pointer_following(true)
	_hover.hide()
	overlay.add_child(_hover)
	visibility_changed.connect(_hide_hover)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): _hide_hover())

func set_blocks(blocks: Array[Dictionary], full_title: String = "") -> void:
	_blocks = blocks.duplicate(true)
	_headline = full_title
	_hide_hover()
	_impact = null
	_impact_labels.clear()
	_portrait = null
	_article = null
	_article_rule = null
	for container: VBoxContainer in [_header, _column]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	if not full_title.is_empty():
		var title := _label(full_title, 22, Style.INK)
		title.name = "Headline"
		title.add_theme_font_override("font", ReceiptHover.BOLD_FONT)
		_header.add_child(title)
	for block: Dictionary in blocks:
		match str(block.get("role", "")):
			"metadata": _add_metadata(block)
			"narrative": _add_narrative(block)
			"impact": _add_impact(block)
			"commentary": _add_comment(block)

func _add_metadata(block: Dictionary) -> void:
	var types := HFlowContainer.new()
	types.name = "EventTypes"
	types.add_theme_constant_override("h_separation", 16)
	types.add_theme_constant_override("v_separation", 4)
	_header.add_child(types)
	for field: Dictionary in block.get("event_fields", []):
		var event_type := _body(14, Style.SECTION_TEAL)
		event_type.name = "EventType"
		event_type.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		event_type.custom_minimum_size.x = minf(200, ReceiptHover.BODY_FONT.get_string_size(str(field.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 2)
		types.add_child(event_type)
		_write_field(event_type, field, 0)
		_bind_fields(event_type, [field])
	var row := HFlowContainer.new()
	row.name = "Dateline"
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 4)
	_header.add_child(row)
	var country := str(block.get("country_title", ""))
	if not country.is_empty():
		var location := _label(country, 12, Style.SECONDARY_INK)
		location.name = "Country"
		location.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(location)
	var timestamp := _label(str(block.get("timestamp", "")), 12, Style.SECONDARY_INK)
	timestamp.name = "EventDate"
	timestamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	timestamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(timestamp)
	_add_rule(_header)

func _add_rule(container: VBoxContainer = null) -> HSeparator:
	var rule := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	(_column if container == null else container).add_child(rule)
	return rule

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
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	return content

func _add_narrative(block: Dictionary) -> void:
	var content := _section(str(block.get("kind", "source")), "Article")
	var body := _body(14, Style.INK)
	body.name = "ArticleText"
	body.add_theme_constant_override("paragraph_separation", 6)
	content.add_child(body)
	body.add_text(str(block.content).strip_edges())
	_article = body

func _add_impact(block: Dictionary) -> void:
	_article_rule = _add_rule()
	_impact = VBoxContainer.new()
	_impact.name = "ImpactFields"
	_impact.add_theme_constant_override("separation", 14)
	_column.add_child(_impact)
	var segments: Array = block.get("segments", [])
	_impact.set_meta("segments", segments)
	var groups := {}
	var indices: Array[int] = []
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if str(segment.text) == "\n":
			_collect_impact_row(groups, segments, indices)
			indices = []
		else:
			indices.append(index)
	_collect_impact_row(groups, segments, indices)
	var icons := {"scope":"language", "effects":"impact", "audience":"group", "variants":"source", "rewards":"reward"}
	for group: String in ["scope", "effects", "audience", "variants", "rewards"]:
		if not groups.has(group): continue
		var section := VBoxContainer.new()
		section.name = "ImpactGroup_" + group
		section.add_theme_constant_override("separation", 6)
		_impact.add_child(section)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		section.add_child(heading)
		heading.add_child(_icon(str(icons[group])))
		var title := _label(DeskLocalization.text("LOC_EVENT_SECTION_" + group.to_upper()), 12, Style.SECONDARY_INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_override("font", ReceiptHover.BOLD_FONT)
		heading.add_child(title)
		for row_indices: Array in groups[group]: _add_impact_row(section, segments, row_indices)

func _collect_impact_row(groups: Dictionary, segments: Array, indices: Array[int]) -> void:
	if indices.is_empty(): return
	var group := str(segments[indices[0]].get("impact_group", "effects"))
	if not groups.has(group): groups[group] = []
	groups[group].append(indices)

func _add_impact_row(section: VBoxContainer, segments: Array, indices: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)
	var label := _body(12, Style.SECONDARY_INK)
	label.name = "ImpactLabel"
	label.custom_minimum_size.x = 72
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	var values := VBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	values.add_theme_constant_override("separation", 2)
	row.add_child(values)
	var body := _body(14, Style.INK)
	body.name = "ImpactText"
	values.add_child(body)
	_impact_labels.append(body)
	var stats := HBoxContainer.new()
	stats.name = "ImpactNumbers"
	stats.add_theme_constant_override("separation", 8)
	values.add_child(stats)
	var amount := _body(14, Style.INK)
	amount.name = "ImpactAmount"
	amount.custom_minimum_size.x = 48
	amount.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.add_child(amount)
	var duration := _body(12, Style.SECONDARY_INK)
	duration.name = "ImpactDuration"
	stats.add_child(duration)
	for index: int in indices:
		var segment: Dictionary = segments[index]
		match str(segment.get("impact_role", "value")):
			"label": _write_impact_field(label, segment, index)
			"amount": _write_impact_field(amount, segment, index)
			"duration": _write_impact_field(duration, segment, index)
			_: _write_impact_field(body, segment, index)
	for field_label: RichTextLabel in [label, body, amount, duration]:
		_bind_fields(field_label, segments)
		field_label.visible = not field_label.get_parsed_text().strip_edges().is_empty()
	stats.visible = amount.visible or duration.visible
	if str(segments[int(indices[0])].impact_group) == "rewards":
		stats.reparent(row)
		stats.size_flags_horizontal = Control.SIZE_SHRINK_END
		stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _write_impact_field(label: RichTextLabel, field: Dictionary, index: int) -> void:
	var rendered := field
	if label.get_total_character_count() == 0:
		rendered = field.duplicate()
		rendered.text = str(field.text).strip_edges(true, false)
	_write_field(label, rendered, index)

func _write_field(label: RichTextLabel, field: Dictionary, index: int) -> void:
	var annotated := not str(field.get("tooltip_body", "")).is_empty()
	var linked := not str(field.get("variant_id", "")).is_empty()
	if annotated or linked:
		label.push_meta(index, RichTextLabel.META_UNDERLINE_ALWAYS if linked else RichTextLabel.META_UNDERLINE_NEVER)
		label.push_color(FIELD_COLORS[str(field.field_kind)])
	_write_content(label, str(field.text))
	if annotated or linked:
		label.pop()
		label.pop()

func _bind_fields(label: RichTextLabel, segments: Array) -> void:
	label.meta_hover_started.connect(func(meta: Variant):
		var field: Dictionary = segments[int(meta)]
		if str(field.get("tooltip_body", "")).is_empty():
			_hide_hover()
			return
		_hover.set_content(str(field.tooltip_title), [], str(field.tooltip_body), {"kind":str(field.field_kind), "note":str(field.get("tooltip_note", ""))})
		_hover.show()
		_hover.fit_at(get_viewport().get_mouse_position(), get_viewport().get_visible_rect()))
	label.meta_clicked.connect(func(meta: Variant):
		var id := str(segments[int(meta)].get("variant_id", ""))
		if not id.is_empty():
			_hide_hover()
			meme_selected.emit(id))
	label.meta_hover_ended.connect(func(_meta: Variant): _hide_hover())
	label.mouse_exited.connect(_hide_hover)

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
	var body := _body(14, Style.SECONDARY_INK)
	content.add_child(body)
	body.add_text(str(block.content))

func _label(text: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", ReceiptHover.BODY_FONT)
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
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_theme_font_override("normal_font", ReceiptHover.BODY_FONT)
	body.add_theme_font_override("bold_font", ReceiptHover.BOLD_FONT)
	body.add_theme_font_size_override("normal_font_size", font_size)
	body.add_theme_font_size_override("bold_font_size", font_size)
	body.add_theme_color_override("default_color", ink)
	body.add_theme_constant_override("line_separation", 4)
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
	var impact_text := PackedStringArray()
	if _impact != null:
		for segment: Dictionary in _impact.get_meta("segments"): impact_text.append(str(segment.text))
	var narrative_gap := _article_rule.global_position.y - (_article.global_position.y + _article.size.y) if _article != null and _article_rule != null else 0.0
	var bar := _scroll.get_v_scroll_bar()
	return {"blocks":_blocks.duplicate(true), "headline":_headline, "scrollable":true,
		"content_height":_column.size.y, "viewport_height":_scroll.size.y, "columns":2,
		"header_rect":_header.get_global_rect(), "scroll_rect":_scroll.get_global_rect(),
		"scrollbar_rect":bar.get_global_rect(), "scrollbar_gap":bar.global_position.x - _column.get_global_rect().end.x,
		"narrative_rect":_article.get_global_rect() if _article != null else Rect2(), "narrative_gap":narrative_gap,
		"content_scroll_top":_scroll.scroll_vertical,
		"impact_text":"".join(impact_text), "impact_count":_impact_labels.size(),
		"impact_segments":_impact.get_meta("segments") if _impact != null else [],
		"portrait":_portrait.inspection() if _portrait != null else {},
		"field_hover_visible":_hover.visible, "field_hover_text":_hover.content_text(),
		"horizontal_overflow":_column.size.x > _scroll.size.x + 1}
