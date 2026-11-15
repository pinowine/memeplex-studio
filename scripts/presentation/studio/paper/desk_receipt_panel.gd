extends Panel

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")

@export var receipt_code := "00000067"
@export var paper_margin := 24.0

func _ready() -> void:
	add_theme_stylebox_override("panel", load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	resized.connect(queue_redraw)

func _footer_layout() -> Dictionary:
	var y := size.y - 48
	var number := "No. " + receipt_code
	var number_width := ceilf(Style.FONT.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
	var available := size.x - paper_margin * 2.0
	var barcode_width := minf(88.0, available - number_width - 8.0)
	return {"rule_y":y, "barcode_rect":Rect2(paper_margin, y + 12, barcode_width, 20),
		"number_rect":Rect2(size.x - paper_margin - number_width, y + 12, number_width, 20), "font_size":10}

func _draw() -> void:
	var footer := _footer_layout()
	var y := float(footer.rule_y)
	var x := paper_margin
	while x < size.x - paper_margin:
		draw_line(Vector2(x, y), Vector2(minf(x + 4, size.x - paper_margin), y), Style.EDGE, 1)
		x += 8
	var barcode: Rect2 = footer.barcode_rect
	for bar: Rect2 in Style.barcode_bars(barcode, receipt_code):
		draw_rect(bar, Style.INK)
	var number: Rect2 = footer.number_rect
	draw_string(Style.FONT, Vector2(number.position.x, number.end.y - 2), "No. " + receipt_code, HORIZONTAL_ALIGNMENT_RIGHT, number.size.x, int(footer.font_size), Style.SECONDARY_INK)
