class_name DeskReceiptHover
extends PanelContainer

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const ReceiptStyle = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const ContextTag = preload("res://scripts/presentation/context/context_tag.gd")
const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const DEFAULT_WIDTH := 224.0
const PADDING := Vector2(16,16)
const BOTTOM_PADDING := 20.0
const GROUP_GAP := 16.0
const ROW_GAP := 8.0
const SCREEN_MARGIN := 8.0
const BARCODE_HEIGHT := 20.0
const FOOTER_HEIGHT := 24.0

const BOLD_FONT = preload("res://assets/image/fonts/body_bold_font.tres")

var _title := ""
var _body := ""
var _presentation: Dictionary = {}
var _rows: Array[Dictionary] = []
var _preferred_width := DEFAULT_WIDTH
var _layout_width := DEFAULT_WIDTH
var _text_blocks: Array[Dictionary] = []
var _separators: Array[float] = []
var _fit_bounds := Rect2()
var _pointer_following := false
var _pointer_viewport := Vector2.ZERO
var _pointer_source: Callable
var _pointer_avoidance: Callable
var _layout_revision := 0
var _barcode_rect := Rect2()
var _barcode_bars: Array[Rect2] = []
var _barcode_digits := ""
var _footer_rule := 0.0
var _section_rules: Array[Dictionary] = []
var _row_glyphs: Array[Dictionary] = []
var _tag_panels: Array[Dictionary] = []
var _grouped_bars: Array[Dictionary] = []
var _axis_plots: Array[Dictionary] = []
var _icon_rect := Rect2()
var _badge_rect := Rect2()
var _footer_number: TextParagraph

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	tooltip_text = ""
	add_theme_stylebox_override("panel",load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	_layout_content()

func _ready() -> void:
	set_process(_pointer_following)
	if _pointer_following and is_visible_in_tree(): _follow_pointer()

func _process(_delta: float) -> void:
	if _pointer_following and is_visible_in_tree(): _follow_pointer()

func set_pointer_following(enabled: bool) -> void:
	_pointer_following = enabled
	set_process(enabled)
	if enabled and is_inside_tree() and is_visible_in_tree(): _follow_pointer()

func set_pointer_source(source: Callable) -> void:
	_pointer_source = source

func set_pointer_avoidance(avoidance: Callable) -> void:
	_pointer_avoidance = avoidance

func _follow_pointer() -> void:
	var viewport := get_viewport()
	_pointer_viewport = _pointer_source.call() if _pointer_source.is_valid() else viewport.get_mouse_position()
	var parent_to_viewport := get_global_transform_with_canvas()*get_transform().affine_inverse()
	var to_parent := parent_to_viewport.affine_inverse()
	var bounds := to_parent * viewport.get_visible_rect()
	var fitted := fit_at(to_parent * _pointer_viewport, bounds)
	if not _pointer_avoidance.is_valid(): return
	var avoid: Rect2 = _pointer_avoidance.call()
	if avoid.has_area():
		var available := bounds.grow(-SCREEN_MARGIN)
		_avoid_pointer_overlap(fitted.size, available.position, (available.end - fitted.size).max(available.position), (to_parent * avoid).grow(SCREEN_MARGIN))

func set_content(title: String, rows: Array, body: String = "", presentation: Dictionary = {}) -> void:
	_title = title
	_rows.assign(rows.duplicate(true))
	_body = body
	_presentation = presentation.duplicate(true)
	_layout_content()

func set_width(width: float) -> void:
	_preferred_width = width
	_layout_width = width
	scale = Vector2.ONE
	_layout_content()

func content_text() -> String:
	var sections := PackedStringArray()
	if not _title.is_empty(): sections.append(_title)
	if not str(_presentation.get("badge","")).is_empty(): sections.append(str(_presentation.badge))
	if not str(_presentation.get("metric_value","")).is_empty(): sections.append(str(_presentation.get("metric_label",""))+"  "+str(_presentation.metric_value))
	for row: Dictionary in _rows:
		var category := str(row.get("category",""))
		var value := str(row.get("value",""))
		if row.has("tags"):
			var titles := PackedStringArray()
			for tag: Dictionary in row.tags: titles.append(str(tag.text))
			value = " / ".join(titles)
		sections.append(category+"  "+value if not category.is_empty() else value)
	if not _body.is_empty(): sections.append(_body)
	if not str(_presentation.get("note","")).is_empty(): sections.append(str(_presentation.note))
	return "\n".join(sections)

func fit_at(point: Vector2, bounds: Rect2) -> Rect2:
	_fit_bounds = bounds
	var available := bounds.grow(-SCREEN_MARGIN)
	var width := minf(_preferred_width,available.size.x)
	if not is_equal_approx(_layout_width,width):
		_layout_width = width
		_layout_content()
	var factor := minf(1.0,available.size.y/size.y)
	scale = Vector2.ONE*factor
	var extent := size*factor
	var origin := point+Vector2(16,16)
	if origin.x+extent.x > available.end.x: origin.x=point.x-extent.x-16
	if origin.y+extent.y > available.end.y: origin.y=point.y-extent.y-16
	position = origin.clamp(available.position,(available.end-extent).max(available.position))
	return Rect2(position,extent)

func _avoid_pointer_overlap(extent: Vector2, lower: Vector2, upper: Vector2, avoid: Rect2) -> void:
	var overlap := Rect2(position, extent).intersection(avoid).get_area()
	if is_zero_approx(overlap): return
	var origin := position
	var options := [Vector2(avoid.position.x - extent.x, origin.y), Vector2(avoid.end.x, origin.y),
		Vector2(origin.x, avoid.position.y - extent.y), Vector2(origin.x, avoid.end.y)]
	for option: Vector2 in options:
		var candidate := option.clamp(lower, upper)
		var area := Rect2(candidate, extent).intersection(avoid).get_area()
		if area < overlap or (is_equal_approx(area, overlap) and candidate.distance_squared_to(origin) < position.distance_squared_to(origin)):
			position = candidate
			overlap = area

func _add_text(text: String, at: Vector2, width: float, font: Font, font_size: int, color: Color, role: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var text_role := str({"title":"section", "metric_value":"title", "metric_label":"table_header", "category":"table_header", "value":"body", "body":"body", "note":"reference", "badge":"annotation", "context_tag":"label", "bar_label":"label", "bar_primary":"label"}.get(role, "body"))
	if role in ["quote", "annotation"]: text_role = role
	font_size = Typography.point_size(text_role)
	font = Typography.SEMIBOLD_FONT if role == "bar_primary" else Typography.font(text_role)
	var paragraph := TextParagraph.new()
	paragraph.line_spacing = float(Typography.ROLES[text_role].line_gap)
	paragraph.width = width
	paragraph.alignment = alignment
	paragraph.break_flags = TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE
	# TextParagraph keeps brackets and markup literal in every hover source.
	paragraph.add_string(text,font,font_size)
	var height := ceilf(paragraph.get_size().y)
	_text_blocks.append({"text":text,"paragraph":paragraph,"position":at,"rect":Rect2(at,Vector2(width,height)),"font_size":font_size,"color":color,"role":role,"text_role":text_role})
	return height

func _add_separator(y: float) -> float:
	_separators.append(y+GROUP_GAP*.5)
	return y+GROUP_GAP

func _add_tags(tags: Array, y: float, width: float, left: float = PADDING.x, vertical: bool = false) -> float:
	var x := left
	var row_height := 0.0
	for tag: Dictionary in tags:
		var text := str(tag.text)
		var kind := str(tag.kind)
		var chip_width := minf(minf(256.0, width), ceilf(BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Typography.point_size("label")).x + 30.0))
		if x > left and (vertical or x + chip_width > left + width):
			x = left
			y += row_height + 4
			row_height = 0
		var colors := ContextTag.palette(kind)
		var text_height := _add_text(text, Vector2(x + 22, y + 2), chip_width - 28, BODY_FONT, 12, colors.ink, "context_tag", HORIZONTAL_ALIGNMENT_CENTER)
		var chip_height := maxf(14, text_height) + 4
		var rect := Rect2(x, y, chip_width, chip_height)
		_tag_panels.append({"text":text, "kind":kind, "rect":rect, "paper":ContextTag.paper(kind)})
		_row_glyphs.append({"rect":Rect2(x + 4, y + (chip_height - 14) * 0.5, 14, 14), "kind":kind, "color":colors.ink})
		row_height = maxf(row_height, chip_height)
		x += chip_width + 4
	return y + row_height

func _layout_content() -> void:
	_layout_revision += 1
	_text_blocks.clear()
	_separators.clear()
	_section_rules.clear()
	_row_glyphs.clear()
	_tag_panels.clear()
	_grouped_bars.clear()
	_axis_plots.clear()
	_badge_rect = Rect2()
	var width := _layout_width-PADDING.x*2.0
	var y := PADDING.y
	_icon_rect = Rect2(PADDING,Vector2(32,32))
	if not _title.is_empty():
		var axes: Array = _presentation.get("axes", [])
		var axes_width := 144.0 if not axes.is_empty() else 0.0
		var title_x := PADDING.x+40
		var title_width := width-40-axes_width-(GROUP_GAP if not axes.is_empty() else 0.0)
		var title_height := _add_text(_title,Vector2(title_x,y),title_width,BOLD_FONT,18,ReceiptStyle.INK,"title")
		var header_height := maxf(_icon_rect.size.y,title_height)
		var title_block: Dictionary = _text_blocks.back()
		title_block.position.y += (header_height-title_height)*.5
		title_block.rect.position = title_block.position
		_icon_rect.position.y += (header_height-_icon_rect.size.y)*.5
		y += header_height
		var badge := str(_presentation.get("badge",""))
		if not badge.is_empty():
			y += 6
			var badge_width := minf(title_width,BODY_FONT.get_string_size(badge,HORIZONTAL_ALIGNMENT_LEFT,-1,Typography.point_size("annotation")).x+12)
			var badge_height := _add_text(badge,Vector2(title_x+6,y+3),badge_width-12,BODY_FONT,11,ReceiptStyle.INK,"badge",HORIZONTAL_ALIGNMENT_CENTER)+6
			_badge_rect = Rect2(title_x,y,badge_width,badge_height)
			y += badge_height
		if not axes.is_empty():
			var top: float = title_block.rect.position.y
			_layout_axes(axes, Rect2(PADDING.x+width-axes_width, top, axes_width, y-top))
		y = maxf(y,_icon_rect.end.y)+GROUP_GAP
	var metric_value := str(_presentation.get("metric_value",""))
	if not metric_value.is_empty():
		var label_height := _add_text(str(_presentation.get("metric_label","")),Vector2(PADDING.x,y),width,BODY_FONT,12,ReceiptStyle.SECONDARY_INK,"metric_label")
		y += label_height+4
		y += _add_text(metric_value,Vector2(PADDING.x,y),width,BOLD_FONT,32,ReceiptStyle.INK,"metric_value")+GROUP_GAP
	var label_width := 0.0
	for row: Dictionary in _rows:
		if row.has("tags"): continue
		label_width = maxf(label_width,BOLD_FONT.get_string_size(str(row.get("category","")),HORIZONTAL_ALIGNMENT_LEFT,-1,Typography.point_size("table_header")).x+24)
	label_width = minf(label_width,width*.5)
	var column_layout := bool(_presentation.get("columns", false))
	var column_bottom := y
	var grouped_bars := bool(_presentation.get("grouped_bars", false))
	if grouped_bars: y = _layout_grouped_bars(y, width)
	for index in _rows.size():
		if grouped_bars: break
		var row: Dictionary = _rows[index]
		if column_layout:
			var column_width := (width - ROW_GAP * 2) / 3.0
			var left := PADDING.x + index * (column_width + ROW_GAP)
			var top := y + _add_text(str(row.label), Vector2(left,y), column_width, BOLD_FONT, 12, ReceiptStyle.SECONDARY_INK, "category") + ROW_GAP
			column_bottom = maxf(column_bottom, _add_tags(row.tags, top, column_width, left, true))
			continue
		if row.has("tags"):
			var heading := str(row.get("label", ""))
			if not heading.is_empty(): y += _add_text(heading, Vector2(PADDING.x,y), width, BOLD_FONT, 12, ReceiptStyle.SECONDARY_INK, "category") + ROW_GAP
			y = _add_tags(row.tags, y, width)
			if index < _rows.size()-1: y += ROW_GAP
			continue
		var category := str(row.get("category",""))
		var value := str(row.get("value",""))
		var row_height := 0.0
		var value_x := PADDING.x
		if not category.is_empty():
			var kind := str(row.get("kind","source"))
			var category_height := _add_text(category,Vector2(PADDING.x+24,y+2),label_width-24,BOLD_FONT,12,ReceiptStyle.SECONDARY_INK,"category")
			_row_glyphs.append({"rect":Rect2(PADDING.x,y+2+(category_height-16)*.5,16,16),"kind":kind,"color":_section_color(kind)})
			row_height = category_height+2
			value_x += label_width+ROW_GAP
		row_height = maxf(row_height,_add_text(value,Vector2(value_x,y),PADDING.x+width-value_x,BODY_FONT,14,ReceiptStyle.INK,"value"))
		y += maxf(20,row_height)
		if index < _rows.size()-1:
			_section_rules.append({"y":y+GROUP_GAP*.5,"color":ReceiptStyle.EDGE})
			y += GROUP_GAP
	if column_layout: y = column_bottom
	if not _body.is_empty():
		if not _rows.is_empty(): y = _add_separator(y)
		y += _add_text(_body,Vector2(PADDING.x,y),width,BODY_FONT,14,ReceiptStyle.INK,"body")
	var note := str(_presentation.get("note",""))
	if not note.is_empty():
		y += GROUP_GAP
		var citation := note.rsplit("\n", true, 1)
		if citation.size() == 2 and note.begins_with("“"):
			y += _add_text(citation[0],Vector2(PADDING.x,y),width,BODY_FONT,12,Typography.ROLES.quote.color,"quote") + ROW_GAP
			y += _add_text(citation[1],Vector2(PADDING.x,y),width,BODY_FONT,10,Typography.ROLES.reference.color,"note",HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			y += _add_text(note,Vector2(PADDING.x,y),width,BODY_FONT,12,ReceiptStyle.SECONDARY_INK,"note")
	var annotation := str(_presentation.get("annotation", ""))
	if not annotation.is_empty():
		y += GROUP_GAP
		y += _add_text(annotation,Vector2(PADDING.x,y),width,BODY_FONT,12,ReceiptStyle.SECONDARY_INK,"annotation")
	var height := y+GROUP_GAP+FOOTER_HEIGHT+BOTTOM_PADDING
	_barcode_rect = Rect2(Vector2(PADDING.x,height-BOTTOM_PADDING-FOOTER_HEIGHT),Vector2(minf(88,width*.48),BARCODE_HEIGHT))
	_footer_rule = _barcode_rect.position.y-GROUP_GAP*.5
	_barcode_digits = "%08d" % posmod(content_text().hash(),100000000)
	_barcode_bars = ReceiptStyle.barcode_bars(_barcode_rect,_barcode_digits)
	_footer_number = TextParagraph.new()
	_footer_number.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_number.width = width-_barcode_rect.size.x-8
	_footer_number.add_string("No. "+_barcode_digits,BODY_FONT,10)
	custom_minimum_size = Vector2(_layout_width,height)
	size = custom_minimum_size
	queue_redraw()

func _layout_axes(axes: Array, area: Rect2) -> void:
	var chart_width := (area.size.x - GROUP_GAP) * .5
	for index in axes.size():
		var axis: Dictionary = axes[index]
		var left := area.position.x + index * (chart_width + GROUP_GAP)
		var stance := str(axis.kind) == "stance"
		var ink := ReceiptStyle.SECTION_PURPLE if stance else ReceiptStyle.SECTION_TEAL
		var plot := Rect2(left, area.position.y, chart_width, area.size.y)
		var point: Array = axis.point
		_axis_plots.append({"rect":plot, "point":plot.get_center() + Vector2(float(point[0]), float(point[1])) * plot.size * .5, "color":ink})

func _layout_grouped_bars(top: float, width: float) -> float:
	var column_width := (width - ROW_GAP * 2) / 3.0
	var bottom := top
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var x := PADDING.x + index * (column_width + ROW_GAP)
		var y := top + _add_text(str(row.label), Vector2(x, top), column_width, BOLD_FONT, 12, ReceiptStyle.SECONDARY_INK, "category") + ROW_GAP
		for tag: Dictionary in row.tags:
			var ink: Color = ContextTag.CardFace.PALETTES[str(tag.kind)].body
			var primary := bool(tag.primary)
			var text := "%s %d%%" % [str(tag.name), roundi(float(tag.share) * 100)]
			var text_height := _add_text(text, Vector2(x + 6, y + 4), column_width - 12, BODY_FONT, 12, ReceiptStyle.INK, "bar_primary" if primary else "bar_label", HORIZONTAL_ALIGNMENT_CENTER)
			var bar_height := maxf(28, text_height + 8)
			var text_block: Dictionary = _text_blocks.back()
			text_block.position.y = y + (bar_height - text_height) * .5
			text_block.rect.position = text_block.position
			_grouped_bars.append({"rect":Rect2(x,y,column_width,bar_height), "share":float(tag.share), "color":ink, "primary":primary})
			y += bar_height + 4
		bottom = maxf(bottom, y - 4)
	return bottom

func _draw() -> void:
	for axis: Dictionary in _axis_plots:
		var plot: Rect2 = axis.rect
		var center := plot.get_center()
		var ink: Color = axis.color
		draw_rect(plot, Color(ink, .04))
		draw_line(Vector2(plot.position.x, center.y), Vector2(plot.end.x, center.y), Color(ink, .45), 1, true)
		draw_line(Vector2(center.x, plot.position.y), Vector2(center.x, plot.end.y), Color(ink, .45), 1, true)
		draw_circle(axis.point, 4, ink)
	for bar: Dictionary in _grouped_bars:
		var rect: Rect2 = bar.rect
		draw_rect(rect, Color(bar.color, .12))
		if bool(bar.primary): draw_rect(rect, Color(bar.color, .55), false, 1)
		rect.size.x *= float(bar.share)
		draw_rect(rect, Color(bar.color, .25 + .40 * float(bar.share)))
	for tag: Dictionary in _tag_panels:
		draw_style_box(tag.paper, tag.rect)
	for y: float in _separators:
		var x := PADDING.x
		while x < size.x-PADDING.x:
			draw_line(Vector2(x,y),Vector2(minf(x+4,size.x-PADDING.x),y),ReceiptStyle.EDGE,1)
			x += 8
	for rule: Dictionary in _section_rules:
		draw_line(Vector2(PADDING.x,rule.y),Vector2(size.x-PADDING.x,rule.y),rule.color,1.2)
	for glyph: Dictionary in _row_glyphs:
		Glyph.draw(self,glyph.rect,glyph.kind,glyph.color)
	var kind := str(_presentation.get("kind","source"))
	var accent := _section_color(kind)
	draw_rect(_icon_rect,Color(accent,.10))
	Glyph.draw(self,_icon_rect.grow(-4),kind,accent)
	if _badge_rect.has_area(): draw_rect(_badge_rect,Color(accent,.13))
	for block: Dictionary in _text_blocks:
		var paragraph: TextParagraph = block.paragraph
		paragraph.draw(get_canvas_item(),block.position,block.color)
	for bar: Rect2 in _barcode_bars: draw_rect(bar,ReceiptStyle.INK)
	_footer_number.draw(get_canvas_item(),Vector2(_barcode_rect.end.x+8,_barcode_rect.end.y-_footer_number.get_size().y),ReceiptStyle.SECONDARY_INK)

func _section_color(kind: String) -> Color:
	if kind in ["patch","module","stance","stance_token","pragmatic","pragmatic_token"]: return ReceiptStyle.SECTION_PURPLE
	if kind in ["topic","source"]: return ReceiptStyle.SECTION_BROWN
	return ReceiptStyle.SECTION_TEAL

func inspection() -> Dictionary:
	var blocks: Array[Dictionary] = []
	var fits := true
	for block: Dictionary in _text_blocks:
		blocks.append({"text":block.text,"rect":block.rect,"font_size":block.font_size,"role":block.role})
		fits = fits and Rect2(Vector2.ZERO,size).encloses(block.rect)
	var tags: Array[Dictionary] = []
	for tag: Dictionary in _tag_panels if not _rows.is_empty() else []:
		tags.append({"text":tag.text, "kind":tag.kind, "rect":tag.rect})
		fits = fits and Rect2(Vector2.ZERO,size).encloses(tag.rect)
	return {"component":"receipt_hover","title":_title,"rows":_rows.duplicate(true),"body":_body,"text":content_text(),
		"rect":Rect2(position,size*scale),"preferred_width":_preferred_width,"layout_width":_layout_width,"scale":scale,
		"text_blocks":blocks,"text_fits":fits,"separators":_separators.duplicate(),"fit_bounds":_fit_bounds,
		"pointer_following":_pointer_following,"pointer_viewport":_pointer_viewport,"layout_revision":_layout_revision,
		"format":"portrait_receipt","barcode_rect":_barcode_rect,"barcode_digits":_barcode_digits,"barcode_bars":_barcode_bars.duplicate(),"footer_rule":_footer_rule,
		"presentation":_presentation.duplicate(true),"icon_rect":_icon_rect,"badge_rect":_badge_rect,"section_rules":_section_rules.duplicate(true),"row_glyphs":_row_glyphs.duplicate(true),"tag_chips":tags,
		"mouse_filter":mouse_filter,"tooltip_text":tooltip_text,"content_format":"plain_text","serrated_edges":false}
