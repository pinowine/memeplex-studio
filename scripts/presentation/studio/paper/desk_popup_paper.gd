extends Control

const SOURCE_PIXELS_PER_UNIT := 3.0
@export var paper: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)

func _draw() -> void:
	var face := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(Vector2(4, 5), size), Color(0, 0, 0, .19))
	draw_rect(face, Color("e8dfc9"))
	if paper != null:
		# Larger sheets reveal more fibers at the same print density.
		var tile_size := paper.get_size() / SOURCE_PIXELS_PER_UNIT
		for y in range(ceili(size.y / tile_size.y)):
			for x in range(ceili(size.x / tile_size.x)):
				var origin := Vector2(x, y) * tile_size
				var extent := tile_size.min(size - origin)
				draw_texture_rect_region(paper, Rect2(origin, extent), Rect2(Vector2.ZERO, extent * SOURCE_PIXELS_PER_UNIT))
	var edge := PackedVector2Array([Vector2(.4, 1.2), Vector2(size.x - .5, .3), Vector2(size.x - .2, size.y - .7), Vector2(.6, size.y - .2), Vector2(.4, 1.2)])
	draw_polyline(edge, Color(.39, .36, .28, .35), .7, true)
