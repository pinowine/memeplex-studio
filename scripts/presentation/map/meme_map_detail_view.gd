extends VBoxContainer

signal country_selected(id: String)

const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
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
var _country_buttons: Dictionary = {}
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
		_assign_help(header.control, str(section.title), str(section.help), str(section.kind), interactive_countries)
	for view: Dictionary in _row_views:
		var section: Dictionary = details.sections[int(view.section)]
		var row: Dictionary = section.rows[int(view.index)]
		_assign_help(view.label, str(row.label), str(row.help), str(section.kind), interactive_countries)
		if view.tags.is_empty():
			view.value.text = str(row.value)
			_assign_help(view.value, str(row.label), str(row.help), str(section.kind), interactive_countries)
		else:
			for index in view.tags.size(): view.tags[index].configure(row.tags[index], interactive_countries)

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
		"country_ids":_country_buttons.keys(), "country_button_count":_country_buttons.size(),
		"minimum_size":get_combined_minimum_size(), "size":size, "nested_paper":false,
		"compact_layout":_compact_layout, "help_controls":helps}

func _rebuild(interactive_countries: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_row_views.clear()
	_headers.clear()
	_help_controls.clear()
	_country_buttons.clear()
	var compact_columns: HBoxContainer
	for section_index in _details.sections.size():
		var section: Dictionary = _details.sections[section_index]
		var section_body := VBoxContainer.new()
		section_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_body.add_theme_constant_override("separation", 8)
		if _compact_layout and section_index > 0:
			if compact_columns == null:
				compact_columns = HBoxContainer.new()
				compact_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
				compact_columns.add_theme_constant_override("separation", 16)
				add_child(compact_columns)
			compact_columns.add_child(section_body)
		else:
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
		var content := VBoxContainer.new()
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
			if not country_id.is_empty() and row_index > 0: content.add_child(_rule())
			var prose := str(section.kind) == "meme" or not (row.get("tags", []) as Array).is_empty()
			var fields: BoxContainer = VBoxContainer.new() if prose else HBoxContainer.new()
			fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fields.add_theme_constant_override("separation", 8 if prose else 12)
			content.add_child(fields)
			var label: Control
			if interactive_countries and not country_id.is_empty():
				var button := Fields.HelpButton.new()
				button.text = str(row.label)
				button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				button.clip_text = true
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.add_theme_font_size_override("font_size", 14)
				PaperStyle.apply_button(button, true)
				button.pressed.connect(func(): country_selected.emit(country_id))
				_country_buttons[country_id] = button
				_help_controls.append(button)
				label = button
			else:
				label = _label(str(row.label), 12, Style.SECONDARY_INK)
			if not prose: label.custom_minimum_size.x = 88
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
					chip.configure(tag, interactive_countries)
					flow.add_child(chip)
					_help_controls.append(chip)
					tags.append(chip)
				value = flow
			else:
				value = _label(str(row.value), 14, Style.INK)
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.size_flags_stretch_ratio = 1.25
			fields.add_child(value)
			_row_views.append({"section":section_index, "index":row_index, "label":label, "value":value, "tags":tags})

func _assign_help(control: Control, title: String, body: String, kind: String, interactive: bool) -> void:
	control.set_help(title, body, kind)
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
	var label := Fields.HelpLabel.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	_help_controls.append(label)
	return label

func _section_ink(kind: String) -> Color:
	if kind == "metric": return Style.SECTION_PURPLE
	if kind == "meme": return Style.SECTION_BROWN
	return Style.SECTION_TEAL
