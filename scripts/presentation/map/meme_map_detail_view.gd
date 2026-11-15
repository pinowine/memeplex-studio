extends VBoxContainer

signal country_hovered(id: String)

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const Fields = preload("res://scripts/presentation/map/meme_map_fields.gd")

class SectionIcon extends Control:
	var kind := "source"
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), kind, ink)

var _details: Dictionary = {}
var _layout_key := ""
var _row_views: Array[Dictionary] = []
var _headers: Array[Dictionary] = []
var _help_controls: Array[Control] = []
var _country_tags: Dictionary = {}
var _country_flows: Array[HFlowContainer] = []
var _compact_layout := false
var _interactive_countries := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme = ReceiptUI.create_theme()
	add_theme_constant_override("separation", 12)

func set_details(details: Dictionary, interactive_countries: bool = true) -> void:
	_details = details
	_interactive_countries = interactive_countries
	var structure: Array = [interactive_countries, _compact_layout]
	for section: Dictionary in details.sections:
		var rows: Array = []
		for row: Dictionary in section.rows:
			var tags: Array = []
			for tag: Dictionary in row.get("tags", []): tags.append([tag.text, tag.kind])
			rows.append([row.label, row.get("country_id", ""), tags])
		structure.append([section.title, section.kind, rows])
	var key := str(structure)
	if key != _layout_key:
		_layout_key = key
		_rebuild(interactive_countries)
	for header: Dictionary in _headers:
		var section: Dictionary = details.sections[int(header.section)]
		_assign_help(header.control, str(section.title), str(section.help), str(section.kind), interactive_countries, section.get("hover_info", {}))
	for view: Dictionary in _row_views:
		var section: Dictionary = details.sections[int(view.section)]
		var row: Dictionary = section.rows[int(view.index)]
		if not str(row.get("country_id", "")).is_empty():
			_configure_country_tag(view.label, row, interactive_countries)
			continue
		_assign_help(view.label, str(row.label), str(row.help), str(section.kind), interactive_countries, row.get("hover_info", {}))
		if view.value != null and view.tags.is_empty():
			view.value.text = str(row.value)
			_assign_help(view.value, str(row.label), str(row.help), str(section.kind), interactive_countries, row.get("hover_info", {}))
		else:
			for index in view.tags.size(): view.tags[index].configure(row.tags[index], interactive_countries, bool(view.context))

func set_compact_layout(value: bool) -> void:
	if _compact_layout == value: return
	_compact_layout = value
	if not _details.is_empty(): set_details(_details, _interactive_countries)

func inspection() -> Dictionary:
	var rows: Array[Dictionary] = []
	for section: Dictionary in _details.get("sections", []):
		for row: Dictionary in section.rows: rows.append(row.duplicate(true))
	var helps: Array[Dictionary] = []
	for control: Control in _help_controls:
		helps.append({"title":str(control.help_title), "help":str(control.help_body), "kind":str(control.help_kind),
			"tooltip_text":control.tooltip_text, "mouse_filter":control.mouse_filter, "tooltip_style":"receipt",
			"rect":control.get_global_rect(), "visible":control.is_visible_in_tree()})
	return {"section_count":_details.get("sections", []).size(), "rows":rows,
		"country_ids":_country_tags.keys(), "country_tag_count":_country_tags.size(),
		"country_tag_rows":_country_flows.map(func(flow: HFlowContainer): return flow.get_line_count()),
		"country_tags":_country_tags.values().map(func(chip: Control): return chip.inspection()),
		"minimum_size":get_combined_minimum_size(), "size":size, "nested_paper":false,
		"compact_layout":_compact_layout, "context_columns":2, "help_controls":helps}

func _rebuild(interactive_countries: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_row_views.clear()
	_headers.clear()
	_help_controls.clear()
	_country_tags.clear()
	_country_flows.clear()
	for section_index in _details.sections.size():
		var section: Dictionary = _details.sections[section_index]
		var section_body := VBoxContainer.new()
		section_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_body.add_theme_constant_override("separation", 8)
		add_child(section_body)
		section_body.add_child(_rule())
		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_constant_override("separation", 8)
		section_body.add_child(header)
		var icon := SectionIcon.new()
		icon.kind = "impact" if str(section.kind) == "metric" else str(section.kind)
		icon.ink = _section_ink(str(section.kind))
		header.add_child(icon)
		var title := _label(str(section.title), 14, icon.ink)
		title.add_theme_font_override("font", Handwriting.SEMIBOLD_FONT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		_headers.append({"section":section_index, "control":title})
		var context := str(section.kind) == "language"
		var content: Container
		if context:
			var grid := GridContainer.new()
			grid.name = "MemeContextColumns"
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 8)
			content = grid
		elif str(section.kind) == "group" and not section.rows.is_empty():
			var flow := HFlowContainer.new()
			flow.name = "SpreadCountryTags"
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			_country_flows.append(flow)
			content = flow
		else:
			content = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 8)
		section_body.add_child(content)
		if str(section.kind) == "group" and section.rows.is_empty():
			var empty := _label(DeskLocalization.text("MM_NO_SPREAD"), 14, Style.SECONDARY_INK)
			_assign_help(empty, str(section.title), str(section.help), str(section.kind), interactive_countries)
			content.add_child(empty)
		for row_index in section.rows.size():
			var row: Dictionary = section.rows[row_index]
			var country_id := str(row.get("country_id", ""))
			if not country_id.is_empty():
				var chip := Fields.TagChip.new()
				chip.name = "CountryTag_" + country_id
				_configure_country_tag(chip, row, interactive_countries)
				if interactive_countries:
					chip.mouse_entered.connect(func(): country_hovered.emit(country_id))
					chip.mouse_exited.connect(func(): country_hovered.emit(""))
				content.add_child(chip)
				_country_tags[country_id] = chip
				_help_controls.append(chip)
				_row_views.append({"section":section_index, "index":row_index, "label":chip, "value":null, "tags":[], "context":false})
				continue
			var prose := context or str(section.kind) == "meme" or not (row.get("tags", []) as Array).is_empty()
			var fields: BoxContainer = VBoxContainer.new() if prose else HBoxContainer.new()
			fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fields.add_theme_constant_override("separation", 8 if prose else 12)
			content.add_child(fields)
			var label: Control
			label = _label(str(row.label), 12, Style.SECONDARY_INK)
			if not prose and country_id.is_empty(): label.custom_minimum_size.x = 88
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.size_flags_stretch_ratio = 0.75
			label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			fields.add_child(label)
			var tags: Array = []
			var value: Control
			if not (row.get("tags", []) as Array).is_empty():
				var flow := HFlowContainer.new()
				flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
				flow.add_theme_constant_override("h_separation", 6)
				flow.add_theme_constant_override("v_separation", 6)
				for tag: Dictionary in row.tags:
					var chip := Fields.TagChip.new()
					chip.configure(tag, interactive_countries, context)
					flow.add_child(chip)
					_help_controls.append(chip)
					tags.append(chip)
				value = flow
			else:
				value = _label(str(row.value), 14, Style.INK)
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.size_flags_stretch_ratio = 1.25
			fields.add_child(value)
			_row_views.append({"section":section_index, "index":row_index, "label":label, "value":value, "tags":tags, "context":context})

func _configure_country_tag(chip: Control, row: Dictionary, interactive: bool) -> void:
	chip.configure({"text":str(row.label), "help":str(row.help), "kind":"group", "hover_info":row.get("hover_info", {})}, interactive)
	chip.get("_icon").hide()
	chip.custom_minimum_size.x = minf(256.0, ceilf(Typography.font("label").get_string_size(str(row.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0))
	chip.mouse_default_cursor_shape = Control.CURSOR_ARROW
	chip.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

func _assign_help(control: Control, title: String, body: String, kind: String, interactive: bool, info: Dictionary = {}) -> void:
	if info.is_empty():
		control.set_help(title, body, kind)
	else:
		control.set_help_info(info)
	if not interactive:
		control.tooltip_text = ""
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _rule() -> HSeparator:
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	return rule

func _label(text: String, font_size: int, ink: Color) -> Label:
	font_size = Typography.normalized_size(font_size)
	var label := Fields.HelpLabel.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	_help_controls.append(label)
	Typography.apply_control(label, Typography.role_for_size(font_size), true)
	return label

func _section_ink(kind: String) -> Color:
	if kind == "metric": return Style.SECTION_PURPLE
	if kind == "meme": return Style.SECTION_BROWN
	return Style.SECTION_TEAL
