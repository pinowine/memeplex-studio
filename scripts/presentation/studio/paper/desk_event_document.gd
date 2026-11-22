extends PanelContainer

signal meme_selected(id: String)
signal country_hovered(id: String)
signal close_requested

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const Decoration = preload("res://scripts/presentation/studio/paper/desk_paper_decoration.gd")
const MemeDetailView = preload("res://scripts/presentation/map/meme_map_detail_view.gd")
const MemeFields = preload("res://scripts/presentation/map/meme_map_fields.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const ResourceGraphic = preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const Rules = preload("res://data/rules/design_rules.tres")
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

class TendencyPlot extends Control:
	const PLOT_SIDE := 182.0
	const LABEL_INSET := 8.0
	const MIN_ARROW_TRAVEL := 16.0

	var before := Vector2.ZERO
	var after := Vector2.ZERO
	var ink := Style.SECTION_TEAL
	var labels: PackedStringArray
	var progress := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, PLOT_SIDE + 2.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resized.connect(queue_redraw)
		if before.is_equal_approx(after):
			progress = 1.0
		else:
			create_tween().tween_method(_move_marker, 0.0, 1.0, .44).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _move_marker(value: float) -> void:
		progress = value
		queue_redraw()

	func _draw() -> void:
		var font := Typography.font("hint")
		var fs := Typography.point_size("hint")
		var bounds := _frame_rect()
		if not bounds.has_area(): return
		var center := bounds.get_center()
		var captions := _axis_label_rects(bounds, font, fs)
		draw_rect(bounds, Color(ink, .06))
		draw_rect(bounds, Color(ink, .28), false)
		var axis_ink := Color(ink, .35)
		draw_line(Vector2(bounds.position.x + LABEL_INSET, center.y), Vector2(bounds.end.x - LABEL_INSET, center.y), axis_ink, 1.0, true)
		draw_line(Vector2(center.x, captions[2].end.y + 3.0), Vector2(center.x, captions[3].position.y - 3.0), axis_ink, 1.0, true)
		for index in captions.size():
			var area := captions[index]
			draw_string(font, area.position + Vector2(0, font.get_ascent(fs)), labels[index], HORIZONTAL_ALIGNMENT_LEFT, area.size.x, fs, Style.SECONDARY_INK)
		var positions := _plot_positions(bounds, font.get_height(fs))
		var from := positions[0]
		var destination := positions[1]
		var arrow := _displacement_arrow(positions)
		if not arrow.is_empty():
			var direction := from.direction_to(destination)
			draw_arc(from, 5, 0.0, TAU, 20, ink, 1.4, true)
			if from.distance_to(destination) > 22.0:
				draw_dashed_line(from + direction * 5.0, arrow[1], ink, 1.4, 4.0, true)
			else:
				draw_line(arrow[1] - direction * 12.0, arrow[1], ink, 1.4, true)
			draw_polyline(arrow, ink, 1.8, true)
		draw_circle(from.lerp(destination, progress), 4.0, ink, true, -1.0, true)

	func _frame_rect() -> Rect2:
		var side := clampf(minf(size.x, size.y) - 2.0, 0.0, PLOT_SIDE)
		var dimensions := Vector2.ONE * side
		return Rect2((size - dimensions) * .5, dimensions)

	func _axis_label_rects(frame: Rect2, font: Font, font_size: int) -> Array[Rect2]:
		var inner := frame.grow(-LABEL_INSET)
		var center := frame.get_center()
		var height := ceilf(font.get_height(font_size))
		var boxes: Array[Rect2] = []
		for index in labels.size():
			var width := minf(inner.size.x * .5, ceilf(font.get_string_size(labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 1.0)
			var x := center.x - width * .5
			var y := center.y + 5.0
			match index:
				0: x = inner.position.x
				1: x = inner.end.x - width
				2: y = inner.position.y
				3: y = inner.end.y - height
			boxes.append(Rect2(Vector2(x, y), Vector2(width, height)))
		return boxes

	func _plot_positions(frame: Rect2, label_height: float) -> PackedVector2Array:
		var center := frame.get_center()
		var extent := maxf(0.0, frame.size.x * .5 - maxf(22.0, LABEL_INSET + label_height + 4.0))
		return PackedVector2Array([center + before * extent, center + after * extent])

	func _displacement_arrow(positions: PackedVector2Array) -> PackedVector2Array:
		var from := positions[0]
		var destination := positions[1]
		if from.distance_squared_to(destination) < MIN_ARROW_TRAVEL * MIN_ARROW_TRAVEL:
			return PackedVector2Array()
		return _shift_arrow(from, destination)

	func _shift_arrow(from: Vector2, destination: Vector2) -> PackedVector2Array:
		var offset := destination - from
		if offset.is_zero_approx(): return PackedVector2Array()
		var direction := offset.normalized()
		var tip := destination - direction * 6.0
		var tail := tip - direction * 7.0
		var wing := direction.orthogonal() * 4.0
		return PackedVector2Array([tail + wing, tip, tail - wing])

	func inspection() -> Dictionary:
		var frame := _frame_rect()
		var font := Typography.font("hint")
		var fs := Typography.point_size("hint")
		return {"from":before, "to":after, "progress":progress, "frame":frame,
			"axis_label_rects":_axis_label_rects(frame, font, fs),
			"arrow":_displacement_arrow(_plot_positions(frame, font.get_height(fs)))}

var _meme_mode := false
var _meme_details: Dictionary = {}
var _meme_header_key := ""
var _meme_view: Control
var _meme_close: Button
var _footer: Control
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
var font_scale := 1.0
var scroll_vertical: int:
	get: return _scroll.scroll_vertical
	set(value): _scroll.scroll_vertical = value

func _init() -> void:
	var paper := Style.new()
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: paper.set_content_margin(side, 16)
	add_theme_stylebox_override("panel", paper)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)
	_header = VBoxContainer.new()
	_header.name = "StickyHeader"
	_header.add_theme_constant_override("separation", 8)
	layout.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.name = "ArticleScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_force_pass_scroll_events = false
	layout.add_child(_scroll)
	_footer = Decoration.new()
	_footer.name = "PaperBarcode"
	_footer.footer = true
	_footer.custom_minimum_size = Vector2(0,28)
	layout.add_child(_footer)
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
	_column.add_theme_constant_override("separation", 8)
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

func add_action_button(button: Button) -> void:
	var layout := _footer.get_parent()
	button.reparent(layout, false)
	layout.move_child(button, _footer.get_index())

func mount_hover_overlay(parent: Node) -> void:
	var previous := _hover.get_parent()
	_hover.reparent(parent, false)
	_hover.z_index = 25
	if previous is CanvasLayer and previous.get_parent() == self:
		remove_child(previous)
		previous.queue_free()

func set_details(details: Dictionary) -> void:
	var blocks: Array[Dictionary] = []
	for section: Dictionary in details.sections:
		var block := section.duplicate(true)
		block.content = DeskLocalization.text(str(section.get("body", "")))
		for key: String in ["country_title", "timestamp"]:
			block[key] = DeskLocalization.text(str(section.get(key, "")))
		for fields: Array in [block.get("segments", []), block.get("event_fields", []), [block.get("country_field", {})]]:
			for field: Dictionary in fields:
				for key: String in ["text", "tooltip_title", "tooltip_body", "tooltip_note"]:
					if field.has(key): field[key] = DeskLocalization.text(str(field[key]))
		blocks.append(block)
	set_blocks(blocks, DeskLocalization.text(str(details.title)))
	_scroll.scroll_vertical = 0

func set_blocks(blocks: Array[Dictionary], full_title: String = "") -> void:
	if _meme_mode: country_hovered.emit("")
	_meme_mode = false
	_meme_details.clear()
	_meme_header_key = ""
	_meme_view = null
	_meme_close = null
	_blocks = blocks.duplicate(true)
	_headline = full_title
	_footer.code = "%08d" % posmod(full_title.hash(),100000000)
	_footer.queue_redraw()
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
		var headline := HBoxContainer.new()
		headline.name = "HeadlineRow"
		headline.add_theme_constant_override("separation", 8)
		headline.add_child(_icon("source", true))
		_header.add_child(headline)
		var title := _label(full_title, 22, Style.INK)
		title.name = "Headline"
		var headline_font := FontVariation.new()
		headline_font.base_font = ReceiptHover.BOLD_FONT
		headline_font.spacing_top = -10
		headline_font.spacing_bottom = -10
		title.add_theme_font_override("font", headline_font)
		title.add_theme_constant_override("line_spacing", 0)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if size.x > 64.0: title.size.x = size.x - 64.0
		headline.add_child(title)
	for block: Dictionary in blocks:
		match str(block.get("role", "")):
			"metadata": _add_metadata(block)
			"narrative": _add_narrative(block)
			"impact": _add_impact(block)
			"commentary": _add_comment(block)

func _add_metadata(block: Dictionary) -> void:
	var row := HFlowContainer.new()
	row.name = "MetadataLine"
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 6)
	_header.add_child(row)
	var types := HBoxContainer.new()
	types.name = "EventTypes"
	types.add_theme_constant_override("separation", 0)
	types.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(types)
	var fields: Array = block.get("event_fields", [])
	for index in fields.size():
		var field: Dictionary = fields[index]
		var tag := PanelContainer.new()
		tag.name = "EventPrimary" if index == 0 else "EventSubtype"
		tag.add_theme_stylebox_override("panel", _tag_style(index > 0))
		types.add_child(tag)
		tag.add_child(_compact_field(field, "EventType", 11, Style.PAPER if index == 0 else Style.SECTION_TEAL))
	var dateline := HBoxContainer.new()
	dateline.name = "CountryDate"
	dateline.alignment = BoxContainer.ALIGNMENT_END
	dateline.add_theme_constant_override("separation", 8)
	dateline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dateline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dateline)
	var country := str(block.get("country_title", ""))
	if not country.is_empty():
		var field: Dictionary = block.get("country_field", {})
		var location: Control = _tag_field(field, "Country", false) if not field.is_empty() else _label(country, 11, Style.SECONDARY_INK)
		location.name = "Country"
		if location is Label: location.autowrap_mode = TextServer.AUTOWRAP_OFF
		dateline.add_child(location)
	var date_text := str(block.get("timestamp", ""))
	var timestamp := _body(11, Style.SECONDARY_INK)
	timestamp.name = "EventDate"
	timestamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	timestamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timestamp.add_theme_constant_override("line_separation", 0)
	timestamp.custom_minimum_size.x = ceilf(timestamp.get_theme_font("normal_font").get_string_size(date_text, HORIZONTAL_ALIGNMENT_LEFT, -1, timestamp.get_theme_font_size("normal_font_size")).x) + 2
	timestamp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	timestamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timestamp.add_text(date_text)
	dateline.add_child(timestamp)
	_add_rule(_header)

func _tag_style(outlined: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT if outlined else Style.SECTION_TEAL
	style.border_color = Style.SECTION_TEAL
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	return style

func _compact_field(field: Dictionary, node_name: String, font_size: int, ink: Color = Color.TRANSPARENT) -> RichTextLabel:
	var label := _body(font_size, FIELD_COLORS[str(field.field_kind)] if ink.a == 0.0 else ink)
	label.name = node_name
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("line_separation", 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size.x = ceilf(label.get_theme_font("normal_font").get_string_size(str(field.text), HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("normal_font_size")).x) + 2
	_write_field(label, field, 0, ink)
	_bind_fields(label, [field])
	return label

func _tag_field(field: Dictionary, node_name: String, show_icon: bool = true) -> Control:
	var tag := MemeFields.TagChip.new()
	tag.name = node_name
	tag.configure({"text":str(field.text), "help":str(field.tooltip_body), "kind":str(field.field_kind), "hover_info":field.get("tooltip_info", {})}, true, false, show_icon)
	tag.mouse_default_cursor_shape = Control.CURSOR_HELP
	tag.mouse_entered.connect(_show_field_hover.bind(field))
	tag.mouse_exited.connect(_hide_hover)
	return tag

func _add_rule(container: VBoxContainer = null) -> HSeparator:
	var rule := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	(_column if container == null else container).add_child(rule)
	return rule

func _icon(kind: String, centered: bool = false) -> Control:
	var icon := SectionIcon.new()
	icon.kind = kind
	if centered: icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	var rewards: Array = block.get("reward_cards", [])
	var tendencies: Array = block.get("tendencies", [])
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
	for group: String in ["scope", "effects", "variants", "rewards", "audience"]:
		if not groups.has(group) and not (group == "rewards" and not rewards.is_empty()) and not (group == "audience" and not tendencies.is_empty()): continue
		var section := VBoxContainer.new()
		section.name = "ImpactGroup_" + group
		section.add_theme_constant_override("separation", 6)
		_impact.add_child(section)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		section.add_child(heading)
		heading.add_child(_icon(str(icons[group]), true))
		var title := _label(DeskLocalization.text("LOC_EVENT_SECTION_" + group.to_upper()), 12, Style.SECONDARY_INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font", ReceiptHover.BOLD_FONT)
		heading.add_child(title)
		for row_indices: Array in groups.get(group, []): _add_impact_row(section, segments, row_indices)
		if group == "audience": _add_tendencies(section, tendencies)
		if group == "rewards" and not rewards.is_empty():
			_add_reward_cards(section, rewards, bool(rewards[0].get("received", false)))

func _add_reward_cards(section: VBoxContainer, rewards: Array, received: bool) -> void:
	var tray := HFlowContainer.new()
	tray.name = "RewardCards"
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_constant_override("h_separation", 8)
	section.add_child(tray)
	for record: Dictionary in rewards:
		var preview: Control
		if str(record.kind) in ["stance_token", "pragmatic_token"]:
			preview = ResourceGraphic.new()
			preview.configure(record)
			preview.custom_minimum_size = Vector2(54, 54)
			if received: preview.self_modulate.a = .74
		else:
			preview = CardFace.new()
			preview.configure(record, Typography.font("body"))
			preview.placement = CardFace.Placement.FIXED
			preview.custom_minimum_size = CardFace.minimum_card_size(str(record.kind)) * 1.25
			preview.paper_view = received
			preview.shadow_enabled = not received
		preview.name = "RewardCard_" + str(record.id)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tray.add_child(preview)

func _add_tendencies(section: VBoxContainer, tendencies: Array) -> void:
	var plots := HBoxContainer.new()
	plots.add_theme_constant_override("separation", 16)
	section.add_child(plots)
	for row: Dictionary in tendencies:
		var kind := str(row.kind)
		var stance := kind == "stance"
		var keys := ["freedom", "authority", "equality", "hierarchy"] if stance else ["sincere", "ironic", "support", "opposition"]
		var group := VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plots.add_child(group)
		var ink := Style.SECTION_PURPLE if stance else Style.SECTION_TEAL
		var title := _label(DeskLocalization.text("LOC_EVENT_TENDENCY_PLOT_" + kind.to_upper()), 14, ink)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group.add_child(title)
		var plot := TendencyPlot.new()
		plot.name = "TendencyPlot_" + kind
		plot.ink = ink
		plot.labels = PackedStringArray(keys.map(func(id: String): return DeskLocalization.text(str(Rules.context_resource(id).title))))
		plot.before = row["from"]
		plot.after = row["to"]
		group.add_child(plot)

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
	label.custom_minimum_size.x = ceilf(72.0 * float(label.get_theme_font_size("normal_font_size")) / 10.0)
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
	var tags := HFlowContainer.new()
	tags.name = "TopicTags"
	tags.add_theme_constant_override("h_separation", 4)
	tags.add_theme_constant_override("v_separation", 4)
	values.add_child(tags)
	for index: int in indices:
		var segment: Dictionary = segments[index]
		match str(segment.get("impact_role", "value")):
			"label": _write_impact_field(label, segment, index)
			_:
				if str(segment.get("field_kind", "")) == "topic" and segment.has("resource_id"):
					tags.add_child(_tag_field(segment, "Topic_" + str(segment.resource_id)))
				else: _write_impact_field(body, segment, index)
	for field_label: RichTextLabel in [label, body]:
		_bind_fields(field_label, segments)
		field_label.visible = not field_label.get_parsed_text().strip_edges().is_empty()
	tags.visible = tags.get_child_count() > 0
	if not body.visible and not tags.visible:
		values.hide()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _write_impact_field(label: RichTextLabel, field: Dictionary, index: int) -> void:
	var direction := int(field.get("impact_direction", 0))
	if direction != 0:
		label.push_bold()
		label.push_color(Style.SECTION_TEAL if direction > 0 else Style.SECTION_BROWN)
		label.add_text(str(field.text))
		label.pop()
		label.pop()
		return
	var rendered := field
	if label.get_total_character_count() == 0:
		rendered = field.duplicate()
		rendered.text = str(field.text).strip_edges(true, false)
	_write_field(label, rendered, index)

func _write_field(label: RichTextLabel, field: Dictionary, index: int, ink: Color = Color.TRANSPARENT) -> void:
	var annotated := not str(field.get("tooltip_body", "")).is_empty()
	var linked := not str(field.get("variant_id", "")).is_empty()
	if annotated or linked:
		label.push_meta(index, RichTextLabel.META_UNDERLINE_ALWAYS if linked else RichTextLabel.META_UNDERLINE_NEVER)
		label.push_color(FIELD_COLORS[str(field.field_kind)] if ink.a == 0.0 else ink)
	_write_content(label, str(field.text))
	if annotated or linked:
		label.pop()
		label.pop()

func _bind_fields(label: RichTextLabel, segments: Array) -> void:
	label.meta_hover_started.connect(func(meta: Variant):
		var field: Dictionary = segments[int(meta)]
		label.set_meta("annotation_cursor", Input.CURSOR_POINTING_HAND if not str(field.get("variant_id", "")).is_empty() else Input.CURSOR_HELP)
		_show_field_hover(field))
	label.meta_clicked.connect(func(meta: Variant):
		var id := str(segments[int(meta)].get("variant_id", ""))
		if not id.is_empty():
			_hide_hover()
			meme_selected.emit(id))
	label.meta_hover_ended.connect(func(_meta: Variant):
		label.remove_meta("annotation_cursor")
		_hide_hover())
	label.mouse_exited.connect(func():
		label.remove_meta("annotation_cursor")
		_hide_hover())

func _show_field_hover(field: Dictionary) -> void:
	if str(field.get("tooltip_body", "")).is_empty():
		_hide_hover()
		return
	_hover.set_width(float(field.get("tooltip_width", ReceiptHover.DEFAULT_WIDTH)))
	if field.has("tooltip_info"):
		var info: Dictionary = field.tooltip_info
		_hover.set_width(float(info.hover_width))
		_hover.set_content(str(info.title), info.rows, str(info.description), info.presentation)
	else:
		_hover.set_content(str(field.tooltip_title), [], str(field.tooltip_body), {"kind":str(field.field_kind), "note":str(field.get("tooltip_note", ""))})
	_hover.show()
	_hover._follow_pointer()

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
	_portrait.custom_minimum_size = Vector2.ONE * roundf(56.0 * font_scale)
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

func _scaled_size(font_size: int) -> int:
	return Typography.normalized_size(font_size) if is_equal_approx(font_scale, 1.0) else roundi(font_size * font_scale)

func _label(text: String, font_size: int, ink: Color) -> Label:
	var text_role := Typography.role_for_size(font_size)
	font_size = _scaled_size(font_size)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", ReceiptHover.BODY_FONT)
	label.add_theme_color_override("font_color", ink)
	Typography.apply_control(label, text_role, true)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _body(font_size: int, ink: Color) -> RichTextLabel:
	var text_role := Typography.role_for_size(font_size)
	font_size = _scaled_size(font_size)
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
	body.add_theme_color_override("default_color", ink)
	body.add_theme_constant_override("line_separation", 4)
	Typography.apply_control(body, text_role, true)
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		body.add_theme_font_size_override(key, font_size)
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
	if _meme_mode: country_hovered.emit("")

func set_meme_details(details: Dictionary) -> void:
	if not _meme_mode:
		set_blocks([], "")
		_meme_mode = true
		_meme_view = MemeDetailView.new()
		_meme_view.name = "MemeDetails"
		_meme_view.country_hovered.connect(func(id: String): country_hovered.emit(id))
		_column.add_child(_meme_view)
	_meme_details = details.duplicate(true)
	_headline = str(details.title)
	_footer.code = "%08d" % posmod(_headline.hash(),100000000)
	_footer.queue_redraw()
	var header_key := str([details.title, details.get("source_kind", ""), details.get("origin_title", ""), TranslationServer.get_locale()])
	if header_key != _meme_header_key:
		_meme_header_key = header_key
		_rebuild_meme_header(details)
	_meme_view.set_details(details)

func _rebuild_meme_header(details: Dictionary) -> void:
	for child in _header.get_children():
		_header.remove_child(child)
		child.queue_free()
	var heading := HBoxContainer.new()
	heading.name = "MemeHeadline"
	heading.add_theme_constant_override("separation", 12)
	_header.add_child(heading)
	heading.add_child(_icon("source", true))
	var title := _label(str(details.title), 22, Style.INK)
	title.name = "Headline"
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = str(details.title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ReceiptHover.BOLD_FONT)
	heading.add_child(title)
	var fields: Array[Dictionary] = []
	if not str(details.get("source_kind", "")).is_empty():
		fields.append({"text":str(details.source_kind), "field_kind":"meme",
			"tooltip_title":str(details.source_kind), "tooltip_body":str(details.kind_help)})
	_add_metadata({"event_fields":fields, "country_title":str(details.get("origin_title", "")), "country_field":{"text":str(details.origin_title), "field_kind":"group", "tooltip_title":str(details.origin_hover.title), "tooltip_body":str(details.origin_hover.description), "tooltip_info":details.origin_hover}})
	# The detail section supplies the first rule, avoiding two adjacent separators.
	var duplicate_rule: HSeparator = _header.get_child(_header.get_child_count() - 1)
	_header.remove_child(duplicate_rule)
	duplicate_rule.queue_free()

func meme_hover_info(point: Vector2) -> Dictionary:
	if not _meme_mode or not is_visible_in_tree() or not _contains_viewport_point(_scroll, point): return {}
	var controls: Array[Control] = _meme_view.get("_help_controls").duplicate()
	controls.reverse()
	for control: Control in controls:
		if control.is_visible_in_tree() and not str(control.help_body).is_empty() and _contains_viewport_point(control, point):
			return MemeFields.hover_info(control)
	return {}

func _contains_viewport_point(control: Control, point: Vector2) -> bool:
	var local := control.get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(Vector2.ZERO, control.size).has_point(local)

func inspection() -> Dictionary:
	var impact_text := PackedStringArray()
	if _impact != null:
		for segment: Dictionary in _impact.get_meta("segments"): impact_text.append(str(segment.text))
	var narrative_gap := _article_rule.global_position.y - (_article.global_position.y + _article.size.y) if _article != null and _article_rule != null else 0.0
	var bar := _scroll.get_v_scroll_bar()
	return {"blocks":_blocks.duplicate(true), "headline":_headline, "paper_footer":_footer.inspection(), "scrollable":true,
		"meme_mode":_meme_mode, "meme_details":_meme_view.inspection() if _meme_mode else {},
		"meme_sections":_meme_details.get("sections", []).duplicate(true), "paper_style":"event",
		"close_button_visible":false,
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
