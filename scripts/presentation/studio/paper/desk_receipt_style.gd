@tool
class_name DeskReceiptStyle
extends StyleBox

const PAPER := Color("eee6d3")
const INK := Color("3f4338")
const SECONDARY_INK := Color("68604f")
const EDGE := Color("b8ad96")
const FONT = preload("res://assets/image/fonts/development_font.tres")
const SHADOW_OFFSET := Vector2(0,4)
const TOOTH_PITCH := 8.0
const TOOTH_DEPTH := 3.0
const CODE39_PATTERNS := {
	"0":"111221211", "1":"211211112", "2":"112211112", "3":"212211111",
	"4":"111221112", "5":"211221111", "6":"112221111", "7":"111211212",
	"8":"211211211", "9":"112211211", "*":"121121211"
}

static func barcode_bars(rect: Rect2, digits: String) -> Array[Rect2]:
	var symbols := "*"+digits+"*"
	var narrow := rect.size.x/float(symbols.length()*12+symbols.length()-1)
	var bars: Array[Rect2] = []
	var x := rect.position.x
	for symbol_index in symbols.length():
		if symbol_index > 0: x += narrow
		var pattern: String = CODE39_PATTERNS[symbols[symbol_index]]
		for element in 9:
			var width := narrow*int(pattern[element])
			if element%2 == 0: bars.append(Rect2(x,rect.position.y,width,rect.size.y))
			x += width
	return bars

func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.expand(rect.end+SHADOW_OFFSET)

func _outline(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var teeth := maxi(1,floori(rect.size.x/TOOTH_PITCH))
	var step := rect.size.x/teeth
	points.append(rect.position+Vector2(0,TOOTH_DEPTH))
	for index in teeth:
		points.append(rect.position+Vector2((index+.5)*step,0))
		points.append(rect.position+Vector2((index+1)*step,TOOTH_DEPTH))
	points.append(rect.position+Vector2(rect.size.x,rect.size.y-TOOTH_DEPTH))
	for index in teeth:
		points.append(rect.position+Vector2(rect.size.x-(index+.5)*step,rect.size.y))
		points.append(rect.position+Vector2(rect.size.x-(index+1)*step,rect.size.y-TOOTH_DEPTH))
	return points

func _draw(canvas_item: RID, rect: Rect2) -> void:
	var points := _outline(rect)
	var shadow := PackedVector2Array()
	for point: Vector2 in points: shadow.append(point+SHADOW_OFFSET)
	RenderingServer.canvas_item_add_polygon(canvas_item,shadow,PackedColorArray([Color(0,0,0,.19)]))
	RenderingServer.canvas_item_add_polygon(canvas_item,points,PackedColorArray([PAPER]))
	points.append(points[0])
	RenderingServer.canvas_item_add_polyline(canvas_item,points,PackedColorArray([EDGE]),.75,true)

static func apply_tooltip_theme(target: Theme, font: Font = null, font_size: int = 14) -> void:
	target.set_stylebox("panel","TooltipPanel",load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	target.set_font("font","TooltipLabel",font if font != null else FONT)
	target.set_font_size("font_size","TooltipLabel",font_size)
	target.set_color("font_color","TooltipLabel",INK)
	target.set_color("font_shadow_color","TooltipLabel",Color.TRANSPARENT)
	target.set_constant("outline_size","TooltipLabel",0)
