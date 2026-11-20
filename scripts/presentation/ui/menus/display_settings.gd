extends RefCounted

const RESOLUTIONS := [Vector2i(960,540), Vector2i(1024,768), Vector2i(1280,720), Vector2i(1280,800), Vector2i(1600,900), Vector2i(1600,1000), Vector2i(1920,1080), Vector2i(1920,1200), Vector2i(2048,1152), Vector2i(2560,1080), Vector2i(2560,1440), Vector2i(2560,1600), Vector2i(2880,1800), Vector2i(3200,1800), Vector2i(3200,2000), Vector2i(3440,1440), Vector2i(3840,1600), Vector2i(3840,2160), Vector2i(3840,2400), Vector2i(5120,1440), Vector2i(5120,2160), Vector2i(5120,2880), Vector2i(7680,2160), Vector2i(7680,4320)]

static func current(window: Window) -> Dictionary:
	return {"resolution":window.size, "fullscreen":window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN], "vsync":DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED}

static func resolutions(window: Window, selected: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var screen := DisplayServer.screen_get_size(window.current_screen)
	for dimensions: Vector2i in RESOLUTIONS:
		if dimensions.x <= screen.x and dimensions.y <= screen.y: result.append(dimensions)
	if screen not in result: result.append(screen)
	if selected not in result: result.append(selected)
	return result

static func apply(window: Window, settings: Dictionary) -> void:
	window.mode = Window.MODE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
	if not settings.fullscreen:
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		var requested := Vector2(settings.resolution)
		var factor := minf(1.0, minf(usable.size.x / requested.x, usable.size.y / requested.y))
		window.size = Vector2i(requested * factor)
		window.position = usable.position + Vector2i(Vector2(usable.size - window.size) * .5)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
