extends RefCounted

const PRESET_IDS := ["low", "medium", "high", "ultra"]
const PRESET_LABELS := ["LOC_GRAPHICS_LOW", "LOC_GRAPHICS_MEDIUM", "LOC_GRAPHICS_HIGH", "LOC_GRAPHICS_ULTRA", "LOC_GRAPHICS_CUSTOM"]
const PRESETS := {
	"low": {"render_scale":0.67, "canvas_scale":1.0, "msaa_3d":0, "msaa_2d":0, "shadows":false, "ssao":false, "ssil":false},
	"medium": {"render_scale":0.85, "canvas_scale":1.0, "msaa_3d":1, "msaa_2d":1, "shadows":true, "ssao":false, "ssil":false},
	"high": {"render_scale":1.0, "canvas_scale":1.5, "msaa_3d":2, "msaa_2d":2, "shadows":true, "ssao":true, "ssil":false},
	"ultra": {"render_scale":1.0, "canvas_scale":2.0, "msaa_3d":3, "msaa_2d":2, "shadows":true, "ssao":true, "ssil":true}
}
const OPTIONS := {
	"render_scale": {"values":[0.5, 0.67, 0.75, 0.85, 1.0], "labels":["50%", "67%", "75%", "85%", "100%"]},
	"canvas_scale": {"values":[1.0, 1.5, 2.0], "labels":["LOC_GRAPHICS_STANDARD", "LOC_GRAPHICS_HIGH", "LOC_GRAPHICS_ULTRA"]},
	"msaa_3d": {"values":[0, 1, 2, 3], "labels":["LOC_GRAPHICS_OFF", "2× MSAA", "4× MSAA", "8× MSAA"]},
	"msaa_2d": {"values":[0, 1, 2], "labels":["LOC_GRAPHICS_OFF", "2× MSAA", "4× MSAA"]},
	"frame_limit": {"values":[30, 60, 120, 0], "labels":["30 FPS", "60 FPS", "120 FPS", "LOC_GRAPHICS_UNLIMITED"]}
}

static func preset(id: String) -> Dictionary:
	var settings: Dictionary = PRESETS[id].duplicate()
	settings.preset = id
	settings.frame_limit = 60
	return settings

static func read(config: ConfigFile) -> Dictionary:
	var settings := preset("medium")
	for key: String in settings:
		settings[key] = config.get_value("graphics", key, settings[key])
	return settings

static func canvas_size(pixels: Vector2i, logical_size: Vector2i, scale: float) -> Vector2i:
	# Match the window's pixel density before applying the selected supersampling.
	var density := maxf(1.0, maxf(float(pixels.x) / logical_size.x, float(pixels.y) / logical_size.y))
	return Vector2i(Vector2(logical_size) * density * scale)
