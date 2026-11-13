extends "res://scripts/presentation/studio/paper/desk_receipt_hover.gd"

const Fields = preload("res://scripts/presentation/map/meme_map_fields.gd")
const MemeHandwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const MEME_WIDTH := 300.0
const MEME_GAP := 8.0
const MEME_FOOTER_HEIGHT := 16.0
const MEME_BOTTOM_PADDING := 20.0

class MemeIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), "meme", ReceiptStyle.SECTION_TEAL)

var _meme_mode := false
var _meme_details: Dictionary = {}
var _meme_root: VBoxContainer
var _meme_scroll: ScrollContainer
var _meme_content: VBoxContainer
var _meme_title: Label
var _meme_share_label: Label
var _meme_share_value: Label
var _meme_tags: HFlowContainer
var _tag_key := ""
var _tag_chips: Array[Control] = []

func set_content(title: String, rows: Array, body: String = "", presentation: Dictionary = {}) -> void:
	_meme_mode = false
	if _meme_root != null: _meme_root.hide()
	super.set_content(title, rows, body, presentation)

func set_meme_details(details: Dictionary) -> void:
	var changed_version := str(_meme_details.get("id", "")) != str(details.get("id", ""))
	_meme_mode = true
	_meme_details = details.duplicate(true)
	_title = str(details.title)
	_body = ""
	_rows.clear()
	_presentation = {"kind":"meme"}
	_preferred_width = MEME_WIDTH
	_layout_width = minf(MEME_WIDTH, _fit_bounds.size.x - SCREEN_MARGIN * 2.0) if _fit_bounds.has_area() else MEME_WIDTH
	_build_meme_content()
	_meme_root.show()
	_meme_title.text = str(details.title)
	_meme_share_label.text = str(details.share_label)
	_meme_share_value.text = str(details.share_value)
	_update_tags(details.context_tags)
	if changed_version: _meme_scroll.scroll_vertical = 0
	_layout_content()

func is_meme_hover() -> bool:
	return _meme_mode

func scroll_details(direction: int) -> bool:
	if not _meme_mode: return false
	var scrollbar := _meme_scroll.get_v_scroll_bar()
	if scrollbar.max_value - scrollbar.page <= 1.0: return false
	_meme_scroll.scroll_vertical += direction * 72
	return true

func content_text() -> String:
	if not _meme_mode: return super.content_text()
	var lines := PackedStringArray([str(_meme_details.title), str(_meme_details.share_label) + "  " + str(_meme_details.share_value)])
	for tag: Dictionary in _meme_details.context_tags: lines.append(str(tag.text))
	return "\n".join(lines)

func fit_at(point: Vector2, bounds: Rect2) -> Rect2:
	if not _meme_mode: return super.fit_at(point, bounds)
	var previous_bounds := _fit_bounds
	_fit_bounds = bounds
	var available := bounds.grow(-SCREEN_MARGIN)
	var width := minf(_preferred_width, available.size.x)
	if not is_equal_approx(_layout_width, width) or previous_bounds.size != bounds.size:
		_layout_width = width
		_layout_content()
	scale = Vector2.ONE
	var origin := point + Vector2(16, 16)
	if origin.x + size.x > available.end.x: origin.x = point.x - size.x - 16
	if origin.y + size.y > available.end.y: origin.y = point.y - size.y - 16
	position = origin.clamp(available.position, (available.end - size).max(available.position))
	return Rect2(position, size)

func _build_meme_content() -> void:
	if _meme_root != null: return
	_meme_root = VBoxContainer.new()
	_meme_root.name = "MemeHoverContent"
	_meme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meme_root.add_theme_constant_override("separation", int(MEME_GAP))
	add_child(_meme_root)
	_meme_scroll = ScrollContainer.new()
	_meme_scroll.name = "MemeHoverScroll"
	_meme_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meme_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_meme_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_meme_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_meme_root.add_child(_meme_scroll)
	_meme_content = VBoxContainer.new()
	_meme_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meme_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meme_content.add_theme_constant_override("separation", int(MEME_GAP))
	_meme_scroll.add_child(_meme_content)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 6)
	_meme_content.add_child(header)
	header.add_child(MemeIcon.new())
	_meme_title = _meme_label(16, MemeHandwriting.BOLD_FONT, ReceiptStyle.INK)
	_meme_title.name = "MemeHoverTitle"
	header.add_child(_meme_title)
	var share := HBoxContainer.new()
	share.mouse_filter = Control.MOUSE_FILTER_IGNORE
	share.add_theme_constant_override("separation", 12)
	_meme_content.add_child(share)
	_meme_share_label = _meme_label(12, MemeHandwriting.BODY_FONT, ReceiptStyle.SECONDARY_INK)
	_meme_share_label.name = "MemeHoverShareLabel"
	share.add_child(_meme_share_label)
	_meme_share_value = _meme_label(16, MemeHandwriting.BOLD_FONT, ReceiptStyle.SECTION_TEAL)
	_meme_share_value.name = "MemeHoverShareValue"
	_meme_share_value.autowrap_mode = TextServer.AUTOWRAP_OFF
	_meme_share_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_meme_share_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	share.add_child(_meme_share_value)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := StyleBoxLine.new()
	line.color = ReceiptStyle.EDGE
	rule.add_theme_stylebox_override("separator", line)
	_meme_content.add_child(rule)
	_meme_tags = HFlowContainer.new()
	_meme_tags.name = "MemeContextTags"
	_meme_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meme_tags.add_theme_constant_override("h_separation", 4)
	_meme_tags.add_theme_constant_override("v_separation", 4)
	_meme_content.add_child(_meme_tags)
	var footer := Control.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.custom_minimum_size.y = MEME_FOOTER_HEIGHT
	_meme_root.add_child(footer)
	_meme_content.minimum_size_changed.connect(_layout_content)

func _update_tags(tags: Array) -> void:
	var key := str(tags)
	if key == _tag_key: return
	_tag_key = key
	for child in _meme_tags.get_children():
		_meme_tags.remove_child(child)
		child.queue_free()
	_tag_chips.clear()
	for tag: Dictionary in tags:
		var chip := Fields.TagChip.new()
		chip.configure(tag, false, true)
		_meme_tags.add_child(chip)
		_tag_chips.append(chip)

func _meme_label(font_size: int, font: Font, ink: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	return label

func _layout_content() -> void:
	if not _meme_mode:
		super._layout_content()
		return
	if _meme_content == null: return
	_layout_revision += 1
	_text_blocks.clear()
	_separators.clear()
	_section_rules.clear()
	_row_glyphs.clear()
	_badge_rect = Rect2()
	_icon_rect = Rect2()
	var content_height := _meme_content.get_combined_minimum_size().y
	var height := content_height + PADDING.y + MEME_GAP + MEME_FOOTER_HEIGHT + MEME_BOTTOM_PADDING
	var bounds_height := _fit_bounds.size.y if _fit_bounds.has_area() else get_viewport_rect().size.y
	height = minf(height, maxf(1.0, bounds_height - SCREEN_MARGIN * 4.0))
	custom_minimum_size = Vector2(_layout_width, height)
	size = custom_minimum_size
	scale = Vector2.ONE
	var width := _layout_width - PADDING.x * 2.0
	_barcode_rect = Rect2(Vector2(PADDING.x, height - MEME_BOTTOM_PADDING - MEME_FOOTER_HEIGHT), Vector2(minf(72, width * 0.48), 12))
	_footer_rule = _barcode_rect.position.y - MEME_GAP * 0.5
	_barcode_digits = "%08d" % posmod(content_text().hash(), 100000000)
	_barcode_bars = ReceiptStyle.barcode_bars(_barcode_rect, _barcode_digits)
	_footer_number = TextParagraph.new()
	_footer_number.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_number.width = width - _barcode_rect.size.x - 8
	_footer_number.add_string("No. " + _barcode_digits, BODY_FONT, 10)
	queue_redraw()

func _draw() -> void:
	if not _meme_mode:
		super._draw()
		return
	draw_line(Vector2(PADDING.x, _footer_rule), Vector2(size.x - PADDING.x, _footer_rule), ReceiptStyle.EDGE, 1)
	for bar: Rect2 in _barcode_bars: draw_rect(bar, ReceiptStyle.INK)
	_footer_number.draw(get_canvas_item(), Vector2(_barcode_rect.end.x + 8, _barcode_rect.end.y - _footer_number.get_size().y), ReceiptStyle.SECONDARY_INK)

func inspection() -> Dictionary:
	var state := super.inspection()
	state.meme_mode = _meme_mode
	if _meme_mode:
		var scrollbar := _meme_scroll.get_v_scroll_bar()
		state.details = _meme_details.duplicate(true)
		state.share_label = _meme_share_label.text
		state.share_value = _meme_share_value.text
		state.share_value_rect = _meme_share_value.get_global_rect()
		state.share_value_minimum_size = _meme_share_value.get_combined_minimum_size()
		state.tag_chips = _tag_chips.map(func(chip: Control): return chip.inspection())
		state.tag_row_count = _meme_tags.get_line_count()
		state.scroll_vertical = _meme_scroll.scroll_vertical
		state.scroll_maximum = maxf(0.0, scrollbar.max_value - scrollbar.page)
		state.content_height = _meme_content.size.y
		state.viewport_height = _meme_scroll.size.y
		state.horizontal_overflow = _meme_content.size.x > _meme_scroll.size.x + 1
	return state
