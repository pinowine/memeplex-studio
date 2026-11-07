extends Node2D

@export var settings: AtlasMapSettings
@export var style: AtlasLatitudeStyle = preload("res://data/map/settings/latitude_style.tres")
var zoom_ratio: float = 1.0

func set_zoom_ratio(ratio: float) -> void:
	zoom_ratio = ratio
	queue_redraw()

func _draw() -> void:
	# The authored stroke dimensions stay in screen pixels as the atlas scales.
	var viewport := get_viewport()
	var screen_transform := viewport.get_final_transform() * get_global_transform_with_canvas()
	# A supersampled desk texture still measures strokes in virtual desktop pixels.
	if viewport is SubViewport and viewport.size_2d_override_stretch \
			and viewport.size_2d_override.x > 0 and viewport.size_2d_override.y > 0:
		var raster_to_logical := Vector2(viewport.size_2d_override) / Vector2(viewport.size)
		screen_transform = Transform2D.IDENTITY.scaled(raster_to_logical) * screen_transform
	var scale_value := screen_transform.x.length()
	draw_set_transform_matrix(screen_transform.affine_inverse())
	var dash := style.dash_length / scale_value
	var stride := (style.dash_length + style.gap_length) / scale_value
	for latitude in style.latitudes:
		var y := settings.world_y_at_latitude(latitude)
		var equator := is_zero_approx(latitude)
		var color := style.equator_color if equator else style.line_color
		var width := style.equator_width if equator else style.line_width
		var x: float = 0.0
		while x < settings.world_size.x:
			var start := screen_transform * Vector2(x, y)
			var end := screen_transform * Vector2(minf(x + dash, settings.world_size.x), y)
			draw_line(start, end, style.paper_color, style.paper_width, true)
			draw_line(start, end, color, width, true)
			x += stride
