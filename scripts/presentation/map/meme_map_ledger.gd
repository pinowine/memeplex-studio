extends Control

signal variant_selected(id: String)
signal country_focus_requested(country_id: String)
signal details_changed(id: String, expanded: bool)

const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const Details = preload("res://scripts/presentation/map/meme_map_details.gd")
const DetailView = preload("res://scripts/presentation/map/meme_map_detail_view.gd")
const Fields = preload("res://scripts/presentation/map/meme_map_fields.gd")
const INSET := 16.0

class HeaderIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), "source", Style.SECTION_TEAL)

class DisclosureMark extends Control:
	var expanded := false
	var ink := Style.SECONDARY_INK

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var points := PackedVector2Array([Vector2(4, 6), Vector2(8, 10), Vector2(12, 6)]) if expanded else PackedVector2Array([Vector2(6, 4), Vector2(10, 8), Vector2(6, 12)])
		draw_polyline(points, ink, 1.4, true)

class LegendBacking extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true

	func _draw() -> void:
		draw_circle(Vector2(size.x * 0.5, minf(size.y, 24.0) * 0.5), 8.0, Style.PAPER)

var _details_expanded := false
var _selected := ""
var _seed := -1
var _locale := ""
var _snapshot: Dictionary = {}
var _colors: Dictionary = {}
var _variants: Dictionary = {}
var _catalog: MemeDemoCatalog
var _country_names: Dictionary = {}
var _order: Array[String] = []
var _candidates := PackedStringArray()
var _rows: Dictionary = {}
var _panel: PanelContainer
var _heading: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ReceiptUI.create_theme()
	_panel = PanelContainer.new()
	_panel.name = "MemeLedgerPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := Style.new()
	paper.content_margin_left = INSET
	paper.content_margin_right = INSET
	paper.content_margin_top = INSET
	paper.content_margin_bottom = INSET
	_panel.add_theme_stylebox_override("panel", paper)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	header.add_child(HeaderIcon.new())
	_heading = _label("", 18)
	_heading.add_theme_font_override("font", Handwriting.SEMIBOLD_FONT)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	column.add_child(rule)
	_scroll = ScrollContainer.new()
	_scroll.name = "MemeLedgerScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_empty = _label(DeskLocalization.text("MAP_MEME_EMPTY"), 14)
	_empty.add_theme_color_override("font_color", Style.SECONDARY_INK)
	column.add_child(_empty)
	_locale = TranslationServer.get_locale()
	resized.connect(_layout)
	_list.minimum_size_changed.connect(_layout)
	_refresh_header()
	_layout()

func configure(catalog: MemeDemoCatalog) -> void:
	_catalog = catalog
	for country: Resource in catalog.gameplay_rules.map_settings.countries:
		_country_names[str(country.id)] = str(country.short_name_key)

func sync_state(snapshot: Dictionary, colors: Dictionary) -> void:
	_snapshot = snapshot
	_colors = colors
	var world: Dictionary = snapshot.world_competition
	var seed_value := int(world.world_seed)
	if _seed != seed_value:
		_seed = seed_value
		_order.clear()
		_selected = ""
		_details_expanded = false
		_candidates.clear()
	_variants = world.variants_by_id
	if not _variants.has(_selected):
		_selected = ""
		_details_expanded = false
	for id in _candidates:
		if not _variants.has(id):
			_candidates.clear()
			break
	var previous_order := _order.duplicate()
	_sort_order()
	var changed := _rows.size() != _variants.size()
	for id in _order:
		if not _rows.has(id): changed = true
	var locale_changed := _locale != TranslationServer.get_locale()
	if locale_changed:
		_locale = TranslationServer.get_locale()
		_empty.text = DeskLocalization.text("MAP_MEME_EMPTY")
	_refresh_header()
	if changed or locale_changed:
		_rebuild_rows()
		_reveal_selected.call_deferred()
	else:
		if previous_order != _order: _reorder_rows()
		_update_rows()

func set_selected_variant(id: String) -> void:
	if _selected == id: return
	_selected = id
	_details_expanded = not id.is_empty()
	if not _rows.is_empty():
		_update_rows()
		_reveal_selected.call_deferred()
	details_changed.emit(_selected, _details_expanded)

func show_candidates(ids: PackedStringArray) -> void:
	_candidates = ids.duplicate()
	_sort_order()
	_reorder_rows()
	if ids.size() == 1:
		_select(ids[0])
	elif _selected not in ids:
		for id in _order:
			if id in ids:
				_reveal_row.call_deferred(id)
				break

func panel_width() -> float:
	return _column_width()

func handles_point(viewport_point: Vector2) -> bool:
	if not is_visible_in_tree(): return false
	var local := _panel.get_global_transform_with_canvas().affine_inverse() * viewport_point
	return Rect2(Vector2.ZERO, _panel.size).has_point(local)

func hover_info(viewport_point: Vector2) -> Dictionary:
	if not handles_point(viewport_point) or not _contains_point(_scroll, viewport_point): return {}
	var controls: Array[Control] = []
	for id in _order:
		var row: Dictionary = _rows[id]
		for key: String in ["dot", "title", "count", "origin"]: controls.append(row[key])
		if id == _selected and _details_expanded:
			controls.append_array(row.detail_view._help_controls)
	controls.reverse()
	for control in controls:
		if control.is_visible_in_tree() and not str(control.help_body).is_empty() and _contains_point(control, viewport_point):
			return Fields.hover_info(control)
	return {}

func _contains_point(control: Control, viewport_point: Vector2) -> bool:
	var point := control.get_global_transform_with_canvas().affine_inverse() * viewport_point
	return Rect2(Vector2.ZERO, control.size).has_point(point)

func inspection() -> Dictionary:
	var selected_row := {}
	if _rows.has(_selected):
		var row: Dictionary = _rows[_selected]
		selected_row = {"title_size":row.title.size, "button_size":row.button.size,
			"title_minimum":row.title.get_combined_minimum_size(), "origin_title":row.origin.text,
			"details":row.detail_view.inspection()}
	var own_ids: Array[String] = []
	for id in _order:
		if _is_own(_variants[id]): own_ids.append(id)
	return {"selected_variant":_selected, "details_expanded":_details_expanded, "variant_count":_variants.size(),
		"order":_order.duplicate(), "candidates":_candidates.duplicate(), "panel_width":panel_width(),
		"panel_rect":_panel.get_global_rect(), "own_variant_ids":own_ids,
		"sort":"control_power", "row_count":_rows.size(),
		"scroll_vertical":_scroll.scroll_vertical, "selected_row":selected_row}

func _column_width() -> float:
	return clampf(size.x * 0.30, 320.0, 380.0)

func _layout() -> void:
	if _panel == null: return
	var width := _column_width()
	var content_height := _panel.get_combined_minimum_size().y
	content_height += _list.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var desired_height := maxf(200.0, content_height)
	var height := minf(maxf(1.0, size.y - 64.0), desired_height)
	_panel.position = Vector2(size.x - width - 24.0, 32.0)
	_panel.size = Vector2(width, height)

func _refresh_header() -> void:
	var title := DeskLocalization.text("MAP_MEME_COUNT") % _variants.size()
	_heading.text = title
	_empty.visible = _variants.is_empty()
	_scroll.visible = not _variants.is_empty()
	_layout()

func _sort_order() -> void:
	_order.clear()
	var newest := {}
	var lineage: Array = _snapshot.get("lineage", [])
	for index in lineage.size():
		var id := str(lineage[index].id)
		_order.append(id)
		newest[id] = index
	_order.sort_custom(func(a: String, b: String):
		var own_a := _is_own(_variants[a])
		var own_b := _is_own(_variants[b])
		if own_a != own_b: return own_a
		if not own_a and (a in _candidates) != (b in _candidates): return a in _candidates
		var adopted_a := int(_variants[a].adopted)
		var adopted_b := int(_variants[b].adopted)
		return int(newest[a]) > int(newest[b]) if adopted_a == adopted_b else adopted_a > adopted_b)

func _is_own(variant: Dictionary) -> bool:
	return bool(variant.controlled) and str(variant.creator) == "player"

func _reorder_rows() -> void:
	for index in _order.size(): _list.move_child(_rows[_order[index]].column, index)

func _rebuild_rows() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	for id in _order:
		var frame := PanelContainer.new()
		frame.name = "Version_" + id
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(frame)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		frame.add_child(column)
		var button := _button("")
		button.name = "SelectVersion"
		button.custom_minimum_size.y = 56
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(id))
		column.add_child(button)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		button.add_child(margin)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 8)
		margin.add_child(line)
		var dot := _field_label(16)
		dot.custom_minimum_size.x = 16
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(dot)
		var summary := VBoxContainer.new()
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.add_theme_constant_override("separation", 4)
		line.add_child(summary)
		var title := _field_label(16)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.max_lines_visible = 2
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.add_child(title)
		var origin := _field_label(14)
		origin.max_lines_visible = 1
		origin.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		origin.add_theme_color_override("font_color", Style.SECONDARY_INK)
		summary.add_child(origin)
		var count := _field_label(14)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		count.custom_minimum_size.x = 64
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(count)
		var disclosure := _button("")
		disclosure.name = "ToggleVersionDetails"
		disclosure.custom_minimum_size = Vector2(24, 24)
		disclosure.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		disclosure.pressed.connect(_toggle_details.bind(id))
		line.add_child(disclosure)
		var mark := DisclosureMark.new()
		disclosure.add_child(mark)
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		mark.offset_left = -8
		mark.offset_top = -8
		mark.offset_right = 8
		mark.offset_bottom = 8
		var details := VBoxContainer.new()
		details.add_theme_constant_override("separation", 8)
		column.add_child(details)
		var detail_view := DetailView.new()
		detail_view.country_selected.connect(func(country_id: String): country_focus_requested.emit(country_id))
		details.add_child(detail_view)
		_rows[id] = {"column":frame, "button":button, "title":title, "count":count, "dot":dot,
			"origin":origin, "details":details, "detail_view":detail_view, "disclosure":disclosure,
			"mark":mark, "own":_is_own(_variants[id])}
		frame.add_theme_stylebox_override("panel", _row_frame())
		if bool(_rows[id].own): _style_own_summary(_rows[id])
		button.resized.connect(_measure_row.bind(id))
		count.minimum_size_changed.connect(_measure_row.bind(id))
	_update_rows()

func _update_rows() -> void:
	for id in _order:
		var variant: Dictionary = _variants[id]
		var row: Dictionary = _rows[id]
		var selected := id == _selected
		var name := Details.short_name(_snapshot, _catalog, id)
		row.title.text = name
		row.origin.text = _country_title(str(variant.origin_country))
		row.count.text = _number(int(variant.adopted))
		row.dot.text = "●" if int(variant.adopted) > 0 else "○"
		var color: Variant = _colors.get(str(variant.family_id), Style.INK)
		row.dot.add_theme_color_override("font_color", Color(color) if color is String else color)
		row.button.set_help(name, DeskLocalization.text("MM_HELP_NAME"), "source")
		row.title.set_help(name, DeskLocalization.text("MM_HELP_NAME"), "source")
		row.origin.set_help(str(row.origin.text), DeskLocalization.text("MM_HELP_ORIGIN"), "group")
		row.count.set_help(str(row.count.text), DeskLocalization.text("MM_HELP_ADOPTION"), "metric")
		row.dot.set_help(name, DeskLocalization.text("MM_HELP_LEGEND"), "source")
		row.disclosure.set_help(name, DeskLocalization.text("MM_HELP_NAME"), "source")
		row.details.visible = selected and _details_expanded
		row.mark.expanded = selected and _details_expanded
		row.mark.queue_redraw()
		row.title.add_theme_color_override("font_color", Style.PAPER if bool(row.own) else (Style.SECTION_TEAL if selected else Style.INK))
		_measure_row(id)
		if selected and _details_expanded: row.detail_view.set_details(Details.build(_snapshot, _catalog, id))

func _row_frame() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.TRANSPARENT
	return frame

func _style_own_summary(row: Dictionary) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var face := StyleBoxFlat.new()
		face.bg_color = Style.SECTION_TEAL if state == "hover" else (Style.SECTION_BROWN if state in ["pressed", "hover_pressed"] else Style.INK)
		face.content_margin_left = 16
		face.content_margin_right = 16
		face.content_margin_top = 8
		face.content_margin_bottom = 8
		row.button.add_theme_stylebox_override(state, face)
		row.disclosure.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for button: Button in [row.button, row.disclosure]:
		button.get_node("HanddrawFeedback").hide()
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
			button.add_theme_color_override(color_name, Style.PAPER)
	row.count.add_theme_color_override("font_color", Style.PAPER)
	row.origin.add_theme_color_override("font_color", Style.PAPER.lerp(Style.EDGE, 0.25))
	row.mark.ink = Style.PAPER
	var backing := LegendBacking.new()
	row.dot.add_child(backing)
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _measure_row(id: String) -> void:
	var row: Dictionary = _rows[id]
	var width: float = row.button.size.x
	if width <= 0.0: width = _column_width() - INSET * 2.0
	var title_width := maxf(1.0, width - 40.0 - row.dot.get_combined_minimum_size().x - row.count.get_combined_minimum_size().x - row.disclosure.get_combined_minimum_size().x)
	var title: Label = row.title
	var paragraph := TextParagraph.new()
	paragraph.width = title_width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(title.text, title.get_theme_font("font"), title.get_theme_font_size("font_size"))
	var line_count := paragraph.get_line_count()
	var visible_lines := mini(2, line_count)
	var height := float(visible_lines * title.get_line_height())
	height += maxf(0.0, float(visible_lines - 1)) * title.get_theme_constant("line_spacing")
	title.custom_minimum_size.y = ceilf(height)
	var origin: Label = row.origin
	origin.custom_minimum_size.y = origin.get_line_height()
	row.button.custom_minimum_size.y = maxf(64.0, ceilf(height) + origin.get_line_height() + 20.0)

func _select(id: String) -> void:
	var choosing_candidate := not _candidates.is_empty()
	_candidates.clear()
	set_selected_variant(id)
	if not _details_expanded: _set_details_expanded(true)
	if choosing_candidate:
		_sort_order()
		_reorder_rows()
		_reveal_selected.call_deferred()
	variant_selected.emit(id)

func _toggle_details(id: String) -> void:
	if id != _selected:
		_select(id)
		return
	_set_details_expanded(not _details_expanded)
	variant_selected.emit(id)

func _set_details_expanded(value: bool) -> void:
	if _details_expanded == value: return
	_details_expanded = value
	_update_rows()
	details_changed.emit(_selected, value)

func _reveal_selected() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _rows.has(_selected) and (_candidates.is_empty() or _selected in _candidates):
		_scroll.scroll_vertical = int(_rows[_selected].column.position.y)

func _reveal_row(id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _rows.has(id): _scroll.scroll_vertical = int(_rows[id].column.position.y)

func _country_title(id: String) -> String:
	return tr(str(_country_names[id]))

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _field_label(font_size: int) -> Fields.HelpLabel:
	var label := Fields.HelpLabel.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String) -> Fields.HelpButton:
	var button := Fields.HelpButton.new()
	button.text = text
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	PaperStyle.apply_button(button, true)
	return button

func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: result += ","
		result += digits[index]
	return result
