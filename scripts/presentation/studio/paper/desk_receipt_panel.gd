extends Panel

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")

@export var receipt_code := "00000067"
@export var paper_margin := 24.0

func _ready() -> void:
	add_theme_stylebox_override("panel", load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	resized.connect(queue_redraw)

func _draw() -> void:
	var y := size.y - 48
	var x := paper_margin
	while x < size.x - paper_margin:
		draw_line(Vector2(x, y), Vector2(minf(x + 4, size.x - paper_margin), y), Style.EDGE, 1)
		x += 8
	var barcode := Rect2(paper_margin, y + 12, 88, 20)
	for bar: Rect2 in Style.barcode_bars(barcode, receipt_code):
		draw_rect(bar, Style.INK)
	draw_string(Style.FONT, Vector2(size.x - paper_margin - 88, barcode.end.y - 2), "No. " + receipt_code, HORIZONTAL_ALIGNMENT_RIGHT, 88, 10, Style.SECONDARY_INK)
