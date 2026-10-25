extends Control

signal closed
signal option_selected(index: int)
signal contact_selected(index: int)

const SLIDE_DURATION := .24
const SOURCE_PIXELS_PER_UNIT := 3.0

class PaperSurface extends Control:
	var paper: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		var face := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(Vector2(4, 5), size), Color(0, 0, 0, .19))
		draw_rect(face, Color("e8dfc9"))
		if paper != null:
			# A larger note reveals more fibers, rather than enlarging the same grain.
			var tile_size := paper.get_size() / SOURCE_PIXELS_PER_UNIT
			for y in range(ceili(size.y / tile_size.y)):
				for x in range(ceili(size.x / tile_size.x)):
					var origin := Vector2(x, y) * tile_size
					var extent := tile_size.min(size - origin)
					draw_texture_rect_region(paper, Rect2(origin, extent), Rect2(Vector2.ZERO, extent * SOURCE_PIXELS_PER_UNIT))
		var edge := PackedVector2Array([Vector2(.4, 1.2), Vector2(size.x - .5, .3), Vector2(size.x - .2, size.y - .7), Vector2(.6, size.y - .2), Vector2(.4, 1.2)])
		draw_polyline(edge, Color(.39, .36, .28, .35), .7, true)

class PencilRule extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(size.x * .42, -.5), Vector2(size.x * .78, .4), Vector2(size.x, -.2)]), Color("777766"), .8, true)

var _choice_scroll: ScrollContainer
var _choice_box: VBoxContainer
var _full_title_in_body := false
var _choice_buttons: Array[Button] = []
var _choice_rows: Array = []
var _built := false
var _paper_holder: Control
var _surface: Control
var _title_label: Label
var _body_label: RichTextLabel
var _rule: Control
var _font: Font
var _paper: Texture2D
var _details := {}
var _title := ""
var _body := ""
var _phase := "hidden"
var _generation := 0
var _motion: Tween
var _viewport_rect := Rect2()
var _target_rect := Rect2()
var _offscreen_rect := Rect2()
var _slide_progress := 0.0:
	set(value):
		_slide_progress = clampf(value, 0.0, 1.0)
		if _built: _layout_paper()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)

func _exit_tree() -> void:
	_cancel_motion()

func configure(hand_font: Font, paper: Texture2D) -> void:
	_build()
	_font = hand_font
	_paper = paper
	_surface.paper = paper
	_surface.queue_redraw()
	if hand_font != null:
		_title_label.add_theme_font_override("font", hand_font)
		for kind: String in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			_body_label.add_theme_font_override(kind, hand_font)
	else:
		_title_label.remove_theme_font_override("font")
		for kind: String in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			_body_label.remove_theme_font_override(kind)

func show_details(details: Dictionary, viewport_rect: Rect2) -> bool:
	var title := _text(details, "title")
	var paragraphs := PackedStringArray()
	var body := _text(details, "body", "text")
	if not body.is_empty(): paragraphs.append(body)
	var sections: Variant = details.get("sections", [])
	if sections is Array:
		for section: Variant in sections:
			if not section is Dictionary: continue
			var section_title := _text(section, "title")
			var section_body := _text(section, "body", "text")
			var paragraph := section_title
			if not section_body.is_empty(): paragraph += ("\n" if not paragraph.is_empty() else "") + section_body
			if not paragraph.is_empty(): paragraphs.append(paragraph)
	if (title.is_empty() and paragraphs.is_empty()) or not _valid_viewport(viewport_rect): return false
	_build()
	_cancel_motion()
	_details = details.duplicate(true)
	_viewport_rect = viewport_rect
	_build_choices(details)
	_refresh_translation(true)
	visible = true
	_phase = "entering" if _slide_progress < 1.0 else "shown"
	_layout_paper()
	if _phase == "entering": _animate_to(1.0)
	return true

func hide_details() -> bool:
	if _phase in ["hidden", "exiting"]: return false
	_cancel_motion()
	_phase = "exiting"
	_animate_to(0.0)
	return true

func handles_viewport_point(point: Vector2) -> bool:
	return _built and is_visible_in_tree() and point.is_finite() and _viewport_bounds(_paper_holder).has_point(point)

func inspection() -> Dictionary:
	return {"visible":is_visible_in_tree(), "phase":_phase, "rect":_viewport_bounds(_paper_holder) if _built else Rect2(),
		"slide_progress":_slide_progress, "title":_title, "body":_body, "details":_details.duplicate(true),
		"target_rect":_target_rect, "offscreen_rect":_offscreen_rect, "viewport_rect":_viewport_rect, "generation":_generation,
		"mouse_filter":mouse_filter, "paper_mouse_filter":_paper_holder.mouse_filter if _built else Control.MOUSE_FILTER_IGNORE,
		"body_rect":_viewport_bounds(_body_label) if _built else Rect2(), "body_plain_text":not _body_label.bbcode_enabled if _built else true,
		"scroll_active":_body_label.scroll_active if _built else false, "font_bound":_font != null, "paper_texture_bound":_paper != null,
		"source_pixels_per_world_unit":SOURCE_PIXELS_PER_UNIT, "slide_duration":SLIDE_DURATION}

func _build() -> void:
	if _built: return
	_built = true
	_paper_holder = Control.new()
	_paper_holder.name = "DescriptionPaper"
	_paper_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_paper_holder)
	_surface = PaperSurface.new()
	_surface.name = "HighDensityPaperFibers"
	_paper_holder.add_child(_surface)
	_title_label = Label.new()
	_title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title_label.name = "HandwrittenTitle"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.max_lines_visible = 2
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_color_override("font_color", Color("373d33"))
	_title_label.add_theme_font_size_override("font_size", 25)
	_paper_holder.add_child(_title_label)
	_rule = PencilRule.new()
	_rule.name = "PencilRule"
	_paper_holder.add_child(_rule)
	_body_label = RichTextLabel.new()
	_body_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body_label.name = "HandwrittenExplanation"
	_body_label.bbcode_enabled = false
	_body_label.scroll_active = true
	_body_label.selection_enabled = true
	_body_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_body_label.add_theme_color_override("default_color", Color("4e5346"))
	_body_label.add_theme_font_size_override("normal_font_size", 18)
	_body_label.add_theme_constant_override("line_separation", 5)
	_paper_holder.add_child(_body_label)
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.name = "PaperChoices"
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_choice_scroll.follow_focus = true
	_paper_holder.add_child(_choice_scroll)
	_choice_box = VBoxContainer.new()
	_choice_box.name = "OriginalChoices"
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_box.add_theme_constant_override("separation",5)
	_choice_scroll.add_child(_choice_box)

func _layout_paper() -> void:
	if not _valid_viewport(_viewport_rect): return
	var view := _viewport_rect
	var margin := clampf(view.size.x * .018, 12.0, 28.0)
	var top := clampf(view.size.y * .055, 18.0, 48.0)
	var dimensions := Vector2(minf(430.0, view.size.x * .36), minf(640.0, view.size.y * .82)).round()
	_target_rect = Rect2(Vector2(view.end.x - margin - dimensions.x, view.position.y + top).round(), dimensions)
	_offscreen_rect = Rect2(Vector2(view.end.x + margin, _target_rect.position.y).round(), dimensions)
	# This is a screen-layer paper: whole-pixel poses keep fibers and ink sharp.
	_paper_holder.position = _offscreen_rect.position.lerp(_target_rect.position, _slide_progress).round()
	_paper_holder.size = dimensions
	_surface.size = dimensions
	var padding := minf(30.0, dimensions.x * .075)
	var width := maxf(1, dimensions.x - padding * 2.0)
	var font := _font if _font != null else ThemeDB.fallback_font
	var measured := font.get_multiline_string_size(_title,HORIZONTAL_ALIGNMENT_LEFT,width,25)
	var title_height := minf(ceilf(measured.y),ceilf(font.get_height(25)*2)) if not _title.is_empty() else 0.0
	_full_title_in_body = not _title.is_empty() and measured.y>title_height+1
	_title_label.visible = not _title.is_empty()
	_title_label.position = Vector2(padding,25)
	_title_label.size = Vector2(width,title_height)
	_rule.visible = not _title.is_empty()
	_rule.position = Vector2(padding,25+title_height+7)
	_rule.size = Vector2(width,1)
	var body_y := 25.0+title_height+(25.0 if not _title.is_empty() else 0.0)
	var rendered_body := (_title+"\n\n" if _full_title_in_body else "")+_body
	if _body_label.text != rendered_body: _body_label.text = rendered_body
	var content_width := maxf(1,width-16)
	var natural_height := 0.0
	for button: Button in _choice_buttons:
		var fs := button.get_theme_font_size("font_size")
		var needed := font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,content_width-20),fs)
		button.custom_minimum_size = Vector2(0,maxf(44,ceilf(needed.y)+12))
		button.size = Vector2(content_width,button.custom_minimum_size.y)
		natural_height += button.custom_minimum_size.y+5
	if not _choice_buttons.is_empty(): natural_height-=5
	var choice_height := minf(natural_height,floorf(dimensions.y*.42))
	_choice_scroll.visible = not _choice_buttons.is_empty()
	_choice_scroll.position = Vector2(padding,dimensions.y-22-choice_height)
	_choice_scroll.size = Vector2(width,choice_height)
	_choice_box.custom_minimum_size.x = content_width
	_choice_box.size = Vector2(content_width,natural_height)
	_body_label.position = Vector2(padding,body_y)
	_body_label.size = Vector2(width,maxf(48,dimensions.y-body_y-choice_height-(34 if choice_height>0 else 28)))

func text_layout_inspection() -> Dictionary:
	return {"complete_title":_title,"full_title_in_body":_full_title_in_body,"choices_scrollable":_choice_scroll != null and _choice_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"choice_count":_choice_buttons.size(),"rendered_body":_body_label.text if _built else ""}


func _animate_to(target: float) -> void:
	var serial := _generation
	_motion = create_tween()
	_motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if target > 0 else Tween.EASE_IN)
	_motion.tween_property(self, "_slide_progress", target, maxf(.01, SLIDE_DURATION * absf(target - _slide_progress)))
	_motion.tween_callback(func() -> void:
		if serial != _generation: return
		self._slide_progress = target
		_layout_paper()
		if target > 0:
			_phase = "shown"
		else:
			_phase = "hidden"
			visible = false
			closed.emit())

func _cancel_motion() -> void:
	_generation += 1
	if _motion != null and _motion.is_valid(): _motion.kill()
	_motion = null

func _on_viewport_resized() -> void:
	_viewport_rect = get_viewport().get_visible_rect()
	_layout_paper()

func _valid_viewport(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.size.x >= 240.0 and rect.size.y >= 180.0

func _viewport_bounds(node: Control) -> Rect2:
	var transform := node.get_global_transform_with_canvas()
	var corners := [transform * Vector2.ZERO, transform * Vector2(node.size.x, 0), transform * node.size, transform * Vector2(0, node.size.y)]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners: bounds = bounds.expand(corner)
	return bounds

func _text(record: Dictionary, key: String, alternate: String = "") -> String:
	var value: Variant = record.get(key)
	if value is String: return value.strip_edges()
	value = record.get(alternate) if not alternate.is_empty() else null
	return value.strip_edges() if value is String else ""

func _build_choices(details: Dictionary) -> void:
	for button in _choice_buttons:
		button.get_parent().remove_child(button)
		button.queue_free()
	_choice_buttons.clear()
	_choice_rows.clear()
	var contacts: Array = details.get("contacts",[])
	var options: Array = details.get("options",[])
	var rows := contacts if not contacts.is_empty() else options
	for index in rows.size():
		var row: Variant = rows[index]
		var button := Button.new()
		button.name = ("Contact" if not contacts.is_empty() else "Reply") + str(index)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text = _choice_text(row,not contacts.is_empty())
		_choice_rows.append(row.duplicate(true) if row is Dictionary else row)
		button.disabled = contacts.is_empty() and not bool(details.get("reply_enabled",false))
		button.add_theme_font_override("font",_font)
		button.add_theme_font_size_override("font_size",17)
		var ink := StyleBoxEmpty.new()
		ink.set_content_margin(SIDE_LEFT,10)
		ink.set_content_margin(SIDE_RIGHT,10)
		ink.set_content_margin(SIDE_TOP,6)
		ink.set_content_margin(SIDE_BOTTOM,6)
		for state: String in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,ink)
		button.add_theme_color_override("font_color",Color("444b3e"))
		button.add_theme_color_override("font_hover_color",Color("8e5c37"))
		button.add_theme_color_override("font_disabled_color",Color("858372"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = false
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choice_box.add_child(button)
		_choice_buttons.append(button)
		if not contacts.is_empty(): button.pressed.connect(func(): contact_selected.emit(index))
		else: button.pressed.connect(func(): option_selected.emit(index))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built:
		refresh_locale.call_deferred()

func refresh_locale() -> void:
	if _built and not _details.is_empty(): _refresh_translation(false)

func _refresh_translation(reset_scroll: bool) -> void:
	var scroll := _body_label.get_v_scroll_bar().value
	_title = DeskLocalization.text(_text(_details,"title"))
	var paragraphs := PackedStringArray()
	var body := _text(_details,"body","text")
	if not body.is_empty(): paragraphs.append(_localized_block(body))
	for section: Variant in _details.get("sections",[]):
		if not section is Dictionary: continue
		var heading := DeskLocalization.text(_text(section,"title"))
		var content := _localized_block(_text(section,"body","text"))
		var paragraph := heading + ("\n" if not heading.is_empty() and not content.is_empty() else "") + content
		if not paragraph.is_empty(): paragraphs.append(paragraph)
	_body = "\n\n".join(paragraphs)
	_title_label.text = _title
	_body_label.text = _body
	var contacts := not (_details.get("contacts",[]) as Array).is_empty()
	for index in _choice_buttons.size(): _choice_buttons[index].text = _choice_text(_choice_rows[index],contacts)
	_layout_paper()
	if reset_scroll: _body_label.scroll_to_line(0)
	else: _body_label.get_v_scroll_bar().set_deferred("value",scroll)

func _choice_text(row: Variant, contact: bool) -> String:
	var source := str(row.get("name",row.get("title",row.get("label",row.get("id",""))))) if row is Dictionary else str(row)
	return DeskLocalization.text(source) + ("  " + str(row.get("number","")) if contact else "")

func _localized_block(source: String) -> String:
	var exact := str(TranslationServer.translate(StringName(source)))
	if exact != source: return exact
	return "\n".join(DeskLocalization.lines(Array(source.split("\n",true))))
