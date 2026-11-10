@tool
extends VBoxContainer

signal source_hovered(sources: Array, excerpt: String)
signal source_hover_ended

const AnnotatedText = preload("res://scripts/presentation/studio/workbench/desk_annotated_text.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const INK := Color("384238")
const SECONDARY_INK := Color("594d3f")
const SPACE := 8
const BODY_SIZE := 18


class ExpressionSurface extends MarginContainer:
	var kind := "plain"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resized.connect(queue_redraw)

	func _draw() -> void:
		var accent := PaperStyle.ACCENT
		if kind == "post":
			draw_rect(Rect2(Vector2.ZERO,size),Color(accent,.035))
			draw_line(Vector2(48,16),Vector2(48,size.y-16),Color(accent,.34),1.0,true)
			draw_circle(Vector2(24,29),14,Color(accent,.10))
			draw_circle(Vector2(24,25),4,accent)
			draw_arc(Vector2(24,35),8,PI,TAU,16,accent,2.0,true)
		elif kind == "reply":
			var panel := StyleBoxFlat.new()
			panel.bg_color = Color(accent,.075)
			panel.set_corner_radius_all(8)
			panel.corner_radius_top_left = 0
			draw_style_box(panel,Rect2(Vector2.ZERO,size))
		elif kind == "quote":
			draw_line(Vector2(1,0),Vector2(1,size.y),Color(accent,.35),2.0,true)
		elif kind == "speaker":
			draw_line(Vector2(1,0),Vector2(1,size.y),Color(accent,.55),2.0,true)


var _preset_id := ""
var _segments: Array = []
var _context_segments: Array = []
var _fallback := ""
var _expression_host: Control
var _context_label: RichTextLabel
var _labels: Array[RichTextLabel] = []
var _rows: Array[Dictionary] = []
var _layout_kind := "plain"
var _interaction_enabled := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override("separation",SPACE*2)


func configure(preset_id: String, expression_segments: Array, context_segments: Array, fallback: String = "") -> void:
	_preset_id = preset_id
	_segments = expression_segments.duplicate(true)
	_context_segments = context_segments.duplicate(true)
	_fallback = fallback
	_rebuild()


func set_segments(segments: Array, plain_text: String = "") -> void:
	configure(_preset_id,segments,_context_segments,plain_text)


func _rebuild() -> void:
	source_hover_ended.emit()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_labels.clear()
	_rows.clear()
	_context_label = null
	_layout_kind = {"versailles_2020":"post","nobody_2020":"dialogue","ok_boomer_2020":"reply"}.get(_preset_id,"plain")
	if not _context_segments.is_empty():
		var quote := _surface(self,"quote",SPACE*2,0,SPACE,0)
		quote.name = "ContextQuote"
		_context_label = _readout(quote,_context_segments,"",SECONDARY_INK)
		_context_label.name = "ContextText"
	var surface_kind := "plain" if _layout_kind == "dialogue" else _layout_kind
	var left := SPACE*8 if _layout_kind == "post" else (SPACE*2 if _layout_kind == "reply" else 0)
	var padding := SPACE*2 if _layout_kind in ["post","reply"] else 0
	_expression_host = _surface(self,surface_kind,left,padding,padding,padding)
	_expression_host.name = "ExpressionBody"
	if _layout_kind == "dialogue":
		_build_dialogue()
	else:
		var label := _readout(_expression_host,_segments,_fallback,INK)
		label.name = "ExpressionText"
		_rows.append({"control":label,"role":"expression"})
	set_interaction_enabled(_interaction_enabled)
	update_minimum_size()


func _build_dialogue() -> void:
	var stack := VBoxContainer.new()
	stack.name = "SpeakingLines"
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation",SPACE*2)
	_expression_host.add_child(stack)
	var lines := _split_lines()
	for index in lines.size():
		var speaking := index == lines.size()-1
		var row := _surface(stack,"speaker" if speaking else "plain",SPACE*3 if speaking else 0,0,0,0)
		row.name = "SpeakingLine%d" % index
		var label := _readout(row,lines[index],"",INK if speaking else SECONDARY_INK)
		label.name = "LineText"
		_rows.append({"control":label,"role":"speaker" if speaking else "prompt"})


func _split_lines() -> Array[Array]:
	var lines: Array[Array] = [[]]
	var segments := _segments if not _segments.is_empty() else [{"text":_fallback,"sources":[]}]
	for segment: Dictionary in segments:
		var canonical := str(segment.get("text",""))
		var parts := canonical.split("\n")
		var chinese := DeskLocalization.chinese_text(canonical).split("\n")
		var english := DeskLocalization.english_text(canonical).split("\n")
		for index in parts.size():
			if index > 0: lines.append([])
			if str(parts[index]).is_empty(): continue
			# A line keeps its authored translation and source records when its layout changes.
			if parts.size() > 1: DeskLocalization.register_display(parts[index],english[index],chinese[index])
			lines.back().append({"text":parts[index],"sources":segment.get("sources",[]).duplicate(true)})
	return lines


func _surface(parent: Node, kind: String, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var surface := ExpressionSurface.new()
	surface.kind = kind
	for pair: Array in [["left",left],["top",top],["right",right],["bottom",bottom]]:
		surface.add_theme_constant_override("margin_"+str(pair[0]),int(pair[1]))
	parent.add_child(surface)
	return surface


func _readout(parent: Node, segments: Array, fallback: String, color: Color) -> RichTextLabel:
	var label := AnnotatedText.new()
	label.add_theme_font_size_override("normal_font_size",BODY_SIZE)
	label.add_theme_font_size_override("bold_font_size",BODY_SIZE)
	label.add_theme_color_override("default_color",color)
	label.set_segments(segments,fallback)
	label.source_hovered.connect(_forward_source)
	label.source_hover_ended.connect(func() -> void: source_hover_ended.emit())
	parent.add_child(label)
	_labels.append(label)
	return label


func _forward_source(sources: Array, excerpt: String) -> void:
	if _interaction_enabled: source_hovered.emit(sources,excerpt)


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	for label: RichTextLabel in _labels:
		label.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled: source_hover_ended.emit()


func expression_control() -> Control:
	return _expression_host


func current_text() -> String:
	return _translated(_segments,_fallback)


func get_parsed_text() -> String:
	return current_text()


func context_text() -> String:
	return _translated(_context_segments)


func _translated(segments: Array, fallback: String = "") -> String:
	var result := ""
	for segment: Dictionary in segments: result += DeskLocalization.text(str(segment.get("text","")))
	return result if not segments.is_empty() else DeskLocalization.text(fallback)


func inspection() -> Dictionary:
	var annotations: Array = []
	var rows: Array[Dictionary] = []
	var markup := PackedStringArray()
	for row: Dictionary in _rows:
		var label: RichTextLabel = row.control
		var info: Dictionary = label.inspection()
		annotations.append_array(info.annotations)
		markup.append(info.bbcode)
		rows.append({"text":info.plain_text,"role":row.role,"rect":info.rect,"font_size":BODY_SIZE,"annotations":info.annotations})
	var context_info: Dictionary = _context_label.inspection() if _context_label != null else {}
	return {"plain_text":current_text(),"displayed_text":current_text(),"segments":_segments.duplicate(true),"annotations":annotations,"bbcode":"\n".join(markup),"rect":get_global_rect(),
		"context_text":context_text(),"context_segments":_context_segments.duplicate(true),"context_annotations":context_info.get("annotations",[]),
		"layout":{"kind":_layout_kind,"rows":rows,"expression_rect":_expression_host.get_global_rect() if _expression_host != null else Rect2(),"context_rect":context_info.get("rect",Rect2()),"body_font_size":BODY_SIZE,"avatar":_layout_kind == "post","reply_card":_layout_kind == "reply","interaction_enabled":_interaction_enabled}}
