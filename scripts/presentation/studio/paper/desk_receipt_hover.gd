class_name DeskReceiptHover
extends PanelContainer

const ReceiptStyle = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const HEADING_FONT = preload("res://assets/image/fonts/print_heading_font.tres")
const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const DEFAULT_WIDTH := 176.0
const MINIMUM_HEIGHT := 240.0
const PADDING := Vector2(16,16)
const BOTTOM_PADDING := 20.0
const GROUP_GAP := 16.0
const ROW_GAP := 8.0
const SCREEN_MARGIN := 8.0
const BARCODE_HEIGHT := 32.0
const FOOTER_HEIGHT := 56.0

var _title := ""
var _body := ""
var _rows: Array[Dictionary] = []
var _preferred_width := DEFAULT_WIDTH
var _layout_width := DEFAULT_WIDTH
var _text_blocks: Array[Dictionary] = []
var _separators: Array[float] = []
var _fit_bounds := Rect2()
var _pointer_following := false
var _pointer_viewport := Vector2.ZERO
var _pointer_source: Callable
var _layout_revision := 0
var _barcode_rect := Rect2()
var _barcode_bars: Array[Rect2] = []
var _barcode_digits := ""
var _footer_rule := 0.0

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

func _follow_pointer() -> void:
	var viewport := get_viewport()
	_pointer_viewport = _pointer_source.call() if _pointer_source.is_valid() else viewport.get_mouse_position()
	var parent_to_viewport := get_global_transform_with_canvas()*get_transform().affine_inverse()
	var to_parent := parent_to_viewport.affine_inverse()
	fit_at(to_parent*_pointer_viewport,to_parent*viewport.get_visible_rect())

func set_content(title: String, rows: Array, body: String = "") -> void:
	_title = title
	_rows.assign(rows.duplicate(true))
	_body = body
	_layout_content()

func set_width(width: float) -> void:
	_preferred_width = width
	_layout_width = width
	scale = Vector2.ONE
	_layout_content()

func content_text() -> String:
	var sections := PackedStringArray()
	if not _title.is_empty(): sections.append(_title)
	for row: Dictionary in _rows:
		var category := str(row.get("category",""))
		var value := str(row.get("value",""))
		sections.append(category+"  "+value if not category.is_empty() else value)
	if not _body.is_empty(): sections.append(_body)
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

func _add_text(text: String, at: Vector2, width: float, font: Font, font_size: int, color: Color, role: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.alignment = alignment
	paragraph.break_flags = TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE
	# TextParagraph keeps brackets and markup literal in every hover source.
	paragraph.add_string(text,font,font_size)
	var height := ceilf(paragraph.get_size().y)
	_text_blocks.append({"text":text,"paragraph":paragraph,"position":at,"rect":Rect2(at,Vector2(width,height)),"font_size":font_size,"color":color,"role":role})
	return height

func _add_separator(y: float) -> float:
	_separators.append(y+GROUP_GAP*.5)
	return y+GROUP_GAP

func _layout_content() -> void:
	_layout_revision += 1
	_text_blocks.clear()
	_separators.clear()
	var width := _layout_width-PADDING.x*2.0
	var y := PADDING.y
	if not _title.is_empty():
		y += _add_text(_title,Vector2(PADDING.x,y),width,HEADING_FONT,16,ReceiptStyle.INK,"title",HORIZONTAL_ALIGNMENT_CENTER)
		if not _rows.is_empty() or not _body.is_empty(): y = _add_separator(y)
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var category := str(row.get("category",""))
		var value := str(row.get("value",""))
		if not category.is_empty():
			y += _add_text(category,Vector2(PADDING.x,y),width,BODY_FONT,12,ReceiptStyle.SECONDARY_INK,"category")+ROW_GAP*.5
		y += _add_text(value,Vector2(PADDING.x,y),width,BODY_FONT,14,ReceiptStyle.INK,"value")
		if index < _rows.size()-1: y += GROUP_GAP
	if not _body.is_empty():
		if not _rows.is_empty(): y = _add_separator(y)
		y += _add_text(_body,Vector2(PADDING.x,y),width,BODY_FONT,14,ReceiptStyle.INK,"body")
	var height := maxf(MINIMUM_HEIGHT,y+GROUP_GAP+FOOTER_HEIGHT+BOTTOM_PADDING)
	_barcode_rect = Rect2(Vector2(PADDING.x,height-BOTTOM_PADDING-FOOTER_HEIGHT),Vector2(width,BARCODE_HEIGHT))
	_footer_rule = _barcode_rect.position.y-GROUP_GAP*.5
	_barcode_digits = "%08d" % posmod(content_text().hash(),100000000)
	_barcode_bars = ReceiptStyle.barcode_bars(_barcode_rect.grow_individual(-8,0,-8,0),_barcode_digits)
	custom_minimum_size = Vector2(_layout_width,height)
	size = custom_minimum_size
	queue_redraw()

func _draw() -> void:
	var rules := _separators.duplicate()
	rules.append(_footer_rule)
	for y: float in rules:
		var x := PADDING.x
		while x < size.x-PADDING.x:
			draw_line(Vector2(x,y),Vector2(minf(x+4,size.x-PADDING.x),y),ReceiptStyle.EDGE,1)
			x += 8
	for block: Dictionary in _text_blocks:
		var paragraph: TextParagraph = block.paragraph
		paragraph.draw(get_canvas_item(),block.position,block.color)
	for bar: Rect2 in _barcode_bars: draw_rect(bar,ReceiptStyle.INK)
	var baseline := _barcode_rect.end.y+ROW_GAP+BODY_FONT.get_ascent(10)
	draw_string(BODY_FONT,Vector2(PADDING.x,baseline),_barcode_digits,HORIZONTAL_ALIGNMENT_CENTER,_barcode_rect.size.x,10,ReceiptStyle.SECONDARY_INK)

func inspection() -> Dictionary:
	var blocks: Array[Dictionary] = []
	var fits := true
	for block: Dictionary in _text_blocks:
		blocks.append({"text":block.text,"rect":block.rect,"font_size":block.font_size,"role":block.role})
		fits = fits and Rect2(Vector2.ZERO,size).encloses(block.rect)
	return {"component":"receipt_hover","title":_title,"rows":_rows.duplicate(true),"body":_body,"text":content_text(),
		"rect":Rect2(position,size*scale),"preferred_width":_preferred_width,"layout_width":_layout_width,"scale":scale,
		"text_blocks":blocks,"text_fits":fits,"separators":_separators.duplicate(),"fit_bounds":_fit_bounds,
		"pointer_following":_pointer_following,"pointer_viewport":_pointer_viewport,"layout_revision":_layout_revision,
		"format":"portrait_receipt","barcode_rect":_barcode_rect,"barcode_digits":_barcode_digits,"barcode_bars":_barcode_bars.duplicate(),"footer_rule":_footer_rule,
		"mouse_filter":mouse_filter,"tooltip_text":tooltip_text,"content_format":"plain_text","serrated_edges":true}
