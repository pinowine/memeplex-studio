extends Control

const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")

var footer := false
var kind := "source"
var code := "00000000"

func _init() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)

func _draw() -> void:
 if not footer:
  Glyph.draw(self, Rect2(Vector2.ZERO, size), kind, Style.SECTION_TEAL)
  return
 var x := 0.0
 while x < size.x:
  draw_line(Vector2(x,0), Vector2(minf(x+4,size.x),0), Style.EDGE, 1)
  x += 8
 var barcode := Rect2(0,10,minf(96,size.x*.42),18)
 for bar: Rect2 in Style.barcode_bars(barcode,code): draw_rect(bar,Style.INK)
 draw_string(Typography.font("decoration"),Vector2(barcode.end.x+8,26),"No. "+code,HORIZONTAL_ALIGNMENT_RIGHT,size.x-barcode.end.x-8,Typography.point_size("decoration"),Style.SECONDARY_INK)

func inspection() -> Dictionary:
 return {"kind":kind,"footer":footer,"code":code,"rect":get_global_rect(),"visible":is_visible_in_tree(),"mouse_filter":mouse_filter}
