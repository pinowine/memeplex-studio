@tool
class_name DeskReceiptStyle
extends StyleBox

const PAPER := Color("eee6d3")
const INK := Color("3f4338")
const SECONDARY_INK := Color("68604f")
const EDGE := Color("b8ad96")
const SECTION_TEAL := Color("41675f")
const SECTION_PURPLE := Color("716b92")
const SECTION_BROWN := Color("594d3f")
const FONT = preload("res://assets/image/fonts/development_font.tres")
const SHADOW_OFFSET := Vector2(0,4)
const SHADOW_SPREAD := 3.0
const CUT_INSET := 7.0
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
	return rect.merge(Rect2(rect.position+SHADOW_OFFSET,rect.size).grow(SHADOW_SPREAD))

func _outline(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func _draw(canvas_item: RID, rect: Rect2) -> void:
	var shadow := Rect2(rect.position+SHADOW_OFFSET,rect.size)
	for spread in range(int(SHADOW_SPREAD),-1,-1):
		RenderingServer.canvas_item_add_rect(canvas_item,shadow.grow(spread),Color(0,0,0,.025+.015*(SHADOW_SPREAD-spread)))
	RenderingServer.canvas_item_add_polygon(canvas_item,_outline(rect),PackedColorArray([PAPER]))
	for inset: float in [.5,3.0]:
		var edge := _outline(rect.grow(-inset))
		edge.append(edge[0])
		RenderingServer.canvas_item_add_polyline(canvas_item,edge,PackedColorArray([Color(EDGE,.65 if inset<1 else .30)]),.75,true)
	for y: float in [rect.position.y+CUT_INSET,rect.end.y-CUT_INSET]:
		var x := rect.position.x+CUT_INSET
		while x < rect.end.x-CUT_INSET:
			RenderingServer.canvas_item_add_line(canvas_item,Vector2(x,y),Vector2(minf(x+4,rect.end.x-CUT_INSET),y),Color(SECONDARY_INK,.35),.75,true)
			x += 8

static func apply_tooltip_theme(target: Theme, font: Font = null, font_size: int = 14) -> void:
	target.set_stylebox("panel","TooltipPanel",load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	target.set_font("font","TooltipLabel",font if font != null else FONT)
	target.set_font_size("font_size","TooltipLabel",font_size)
	target.set_color("font_color","TooltipLabel",INK)
	target.set_color("font_shadow_color","TooltipLabel",Color.TRANSPARENT)
	target.set_constant("outline_size","TooltipLabel",0)
