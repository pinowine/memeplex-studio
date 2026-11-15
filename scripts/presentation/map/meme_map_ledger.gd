extends Control

signal variant_selected(id: String)
signal variant_hovered(id: String)

const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const Details = preload("res://scripts/presentation/map/meme_map_details.gd")
const INSET := 16.0

class HeaderIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), "source", Style.SECTION_TEAL)

class ColorDot extends Control:
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(10, 10)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(5, 5), 3.5, ink, true, -1.0, true)

class MemeTag extends PanelContainer:
	signal activated
	var title: Label
	var dot: ColorDot
	var own := false
	var selected := false
	var candidate := false
	var hovered := false
	var _armed := false
	var _natural_width := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_force_pass_scroll_events = false
		focus_mode = Control.FOCUS_ALL
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 6)
		add_child(line)
		dot = ColorDot.new()
		line.add_child(dot)
		title = Label.new()
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_override("font", Handwriting.BODY_FONT)
		title.add_theme_font_size_override("font_size", 14)
		line.add_child(title)
		mouse_entered.connect(func(): hovered = true; _style())
		mouse_exited.connect(func(): hovered = false; _armed = false; _style())
		focus_entered.connect(_style)
		focus_exited.connect(_style)

	func configure(text: String, color: Color, is_own: bool, is_selected: bool, is_candidate: bool) -> void:
		if title.text != text:
			title.text = text
			_natural_width = ceilf(Handwriting.BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 34.0)
		own = is_own
		selected = is_selected
		candidate = is_candidate
		dot.ink = color
		dot.queue_redraw()
		_style()

	func fit_width(maximum: float) -> void:
		custom_minimum_size.x = minf(_natural_width, maximum)

	func _style() -> void:
		var paper := StyleBoxFlat.new()
		paper.bg_color = Style.INK if own else Color(Style.SECTION_TEAL, 0.07)
		if hovered: paper.bg_color = Style.SECTION_TEAL if own else Color(Style.SECTION_TEAL, 0.15)
		paper.border_color = Style.SECTION_TEAL if selected or candidate or has_focus() else Color(Style.SECONDARY_INK, 0.35)
		paper.set_border_width_all(2 if selected or has_focus() else 1)
		paper.set_corner_radius_all(3)
		paper.content_margin_left = 8
		paper.content_margin_right = 8
		paper.content_margin_top = 5
		paper.content_margin_bottom = 5
		add_theme_stylebox_override("panel", paper)
		title.add_theme_color_override("font_color", Style.PAPER if own else Style.INK)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_armed = true
				grab_focus()
			elif _armed:
				_armed = false
				if Rect2(Vector2.ZERO, size).has_point(event.position): activated.emit()
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			activated.emit()
			accept_event()

var _selected := ""
var _selected_meme_id := ""
var _hovered := ""
var _seed := -1
var _locale := ""
var _snapshot: Dictionary = {}
var _colors: Dictionary = {}
var _variants: Dictionary = {}
var _catalog: MemeDemoCatalog
var _order: Array[String] = []
var _candidates := PackedStringArray()
var _rows: Dictionary = {}
var _panel: PanelContainer
var _heading: Label
var _scroll: ScrollContainer
var _flow: HFlowContainer
var _empty: Label
var _column: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ReceiptUI.create_theme()
	_panel = PanelContainer.new()
	_panel.name = "MemeLedgerPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_force_pass_scroll_events = false
	var paper := StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", paper)
	add_child(_panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	_panel.add_child(_column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.visible = false
	header.add_theme_constant_override("separation", 8)
	_column.add_child(header)
	header.add_child(HeaderIcon.new())
	_heading = _label(18)
	_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_heading.add_theme_font_override("font", Handwriting.SEMIBOLD_FONT)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.visible = false
	var line := StyleBoxLine.new()
	line.color = Style.EDGE
	rule.add_theme_stylebox_override("separator", line)
	_column.add_child(rule)
	_scroll = ScrollContainer.new()
	_scroll.name = "MemeLedgerScroll"
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(_scroll)
	_flow = HFlowContainer.new()
	_flow.name = "MemeTags"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_flow.add_theme_constant_override("h_separation", 6)
	_flow.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_flow)
	_empty = _label(14)
	_empty.add_theme_color_override("font_color", Style.SECONDARY_INK)
	_column.add_child(_empty)
	resized.connect(_layout)
	_column.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	_flow.minimum_size_changed.connect(_layout)
	_flow.resized.connect(_layout)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _set_hovered(""))
	_locale = TranslationServer.get_locale()
	_refresh_header()

func configure(catalog: MemeDemoCatalog) -> void:
	_catalog = catalog

func sync_state(snapshot: Dictionary, colors: Dictionary) -> void:
	var previous_meme := _selected_meme_id
	_snapshot = snapshot
	_colors = colors
	var world: Dictionary = snapshot.world_competition
	var world_seed := int(world.world_seed)
	if _seed != world_seed:
		_seed = world_seed
		_selected = ""
		_selected_meme_id = ""
		previous_meme = ""
		_candidates.clear()
	_variants = world.variants_by_id
	if not _variants.has(_selected):
		_selected = ""
		for id: String in _variants:
			if str(_variants[id].meme_id) == previous_meme:
				_selected = id
				break
	_selected_meme_id = str(_variants[_selected].meme_id) if _variants.has(_selected) else ""
	if not _variants.has(_hovered): _set_hovered("")
	var previous := _order.duplicate()
	_sort_order()
	var rebuild := _rows.size() != _order.size()
	for id in _order:
		if not _rows.has(id): rebuild = true
	var locale_changed := _locale != TranslationServer.get_locale()
	_locale = TranslationServer.get_locale()
	_refresh_header()
	if rebuild or locale_changed:
		_rebuild_tags()
	elif previous != _order:
		_reorder_tags()
	_update_tags()

func set_selected_variant(id: String) -> void:
	if _selected == id: return
	_selected = id
	_selected_meme_id = str(_variants[id].meme_id) if _variants.has(id) else ""
	_update_tags()

func show_candidates(ids: PackedStringArray) -> void:
	_candidates = ids.duplicate()
	_sort_order()
	_reorder_tags()
	_update_tags()
	if ids.size() == 1: _select(ids[0])

func panel_width() -> float:
	return maxf(1.0, size.x - 48.0)

func handles_point(viewport_point: Vector2) -> bool:
	return is_visible_in_tree() and _contains_point(_panel, viewport_point)

func hover_info(viewport_point: Vector2) -> Dictionary:
	if not handles_point(viewport_point) or not _contains_point(_scroll, viewport_point): return {}
	for id in _order:
		var tag: MemeTag = _rows[id].tag
		if tag.is_visible_in_tree() and _contains_point(tag, viewport_point):
			return {"title":tag.title.text, "description":DeskLocalization.text("MM_HELP_NAME"), "kind":"source"}
	return {}

func inspection() -> Dictionary:
	var own: Array[String] = []
	var tags: Array[Dictionary] = []
	for id in _order:
		if _is_own(_variants[id]): own.append(id)
		var tag: MemeTag = _rows[id].tag
		tags.append({"id":id, "meme_id":str(_variants[id].meme_id), "title":tag.title.text,
			"rect":tag.get_global_rect(), "size":tag.size, "selected":tag.selected, "own":tag.own,
			"kind":"tag", "base_button":false})
	return {"selected_variant":_selected, "selected_meme_id":_selected_meme_id,
		"meme_count":_order.size(), "row_count":_rows.size(), "tag_count":_rows.size(),
		"tag_ids":_order.duplicate(), "tag_rows":_flow.get_line_count(), "tags":tags,
		"order":_order.duplicate(), "own_variant_ids":own, "pinned_variant_ids":own,
		"independent_meme_ids":_order.map(func(id: String): return str(_variants[id].meme_id)),
		"candidates":_candidates.duplicate(), "heading":_heading.text,
		"panel_width":panel_width(), "panel_rect":_panel.get_global_rect(),
		"sort":"own_then_spread", "details_embedded":false, "expand_controls":0,
		"scroll_vertical":_scroll.scroll_vertical}

func _sort_order() -> void:
	_order.clear()
	var newest := {}
	var by_meme := {}
	var lineage: Array = _snapshot.get("lineage", [])
	for index in lineage.size():
		var id := str(lineage[index].id)
		if not _variants.has(id): continue
		by_meme[str(_variants[id].meme_id)] = id
		newest[id] = index
	for id: String in by_meme.values(): _order.append(id)
	_order.sort_custom(func(a: String, b: String):
		var own_a := _is_own(_variants[a])
		var own_b := _is_own(_variants[b])
		if own_a != own_b: return own_a
		if not own_a and (a in _candidates) != (b in _candidates): return a in _candidates
		var spread_a := float(_variants[a].get("monitor_spread", 0.0))
		var spread_b := float(_variants[b].get("monitor_spread", 0.0))
		return int(newest[a]) > int(newest[b]) if is_equal_approx(spread_a, spread_b) else spread_a > spread_b)

func _is_own(variant: Dictionary) -> bool:
	return bool(variant.controlled) and str(variant.creator) == "player"

func _rebuild_tags() -> void:
	_set_hovered("")
	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	_rows.clear()
	for id in _order:
		var tag := MemeTag.new()
		tag.name = "MemeTag_" + str(_variants[id].meme_id)
		tag.activated.connect(_select.bind(id))
		tag.mouse_entered.connect(_set_hovered.bind(id))
		tag.mouse_exited.connect(func():
			if _hovered == id: _set_hovered(""))
		_flow.add_child(tag)
		_rows[id] = {"tag":tag}

func _reorder_tags() -> void:
	for index in _order.size(): _flow.move_child(_rows[_order[index]].tag, index)

func _update_tags() -> void:
	for id in _order:
		var variant: Dictionary = _variants[id]
		var color: Variant = _colors.get(str(variant.meme_id), Style.SECTION_TEAL)
		_rows[id].tag.configure(Details.short_name(_snapshot, _catalog, id), Color(color) if color is String else color,
			_is_own(variant), id == _selected, id in _candidates)
	_layout()

func _set_hovered(id: String) -> void:
	if _hovered == id: return
	_hovered = id
	variant_hovered.emit(id)

func _select(id: String) -> void:
	_candidates.clear()
	set_selected_variant(id)
	_update_tags()
	variant_selected.emit(id)

func _refresh_header() -> void:
	_heading.text = DeskLocalization.text("MAP_MEME_MONITOR")
	_empty.text = DeskLocalization.text("MAP_MEME_EMPTY")
	_empty.visible = _variants.is_empty()
	_scroll.visible = not _variants.is_empty()
	_layout()

func _layout() -> void:
	if _panel == null: return
	var width := panel_width()
	# Reserve scrollbar space before fitting tags to avoid resize feedback at the threshold.
	var content_width := width - INSET * 2.0 - 14.0
	for row: Dictionary in _rows.values(): row.tag.fit_width(content_width)
	var height := _column.get_combined_minimum_size().y + INSET * 2.0
	if _scroll.visible: height += _flow.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_panel.position = Vector2(24.0, 16.0)
	_panel.size = Vector2(width, minf(maxf(1.0, size.y * 0.22), maxf(36.0, height)))

func _contains_point(control: Control, viewport_point: Vector2) -> bool:
	var point := control.get_global_transform_with_canvas().affine_inverse() * viewport_point
	return Rect2(Vector2.ZERO, control.size).has_point(point)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label
