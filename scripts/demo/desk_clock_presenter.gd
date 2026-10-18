class_name DeskClockPresenter
extends RefCounted

const RingShader := preload("res://scripts/demo/desk_clock_ring.gdshader")
const CLOCK_PATH := "res://assets/desk/v4/clock_plain.png"
const SEASON_PATH := "res://assets/desk/v3/season_ring_natural.png"
const DAY_PATH := "res://assets/desk/v3/day_ring_natural.png"
const CENTER := Vector2(108, 118)
const SPEED_RECT := Rect2(92, 3, 30, 24)
const SEASON_SOURCE_CENTER := Vector2(626.5,625)
const DAY_SOURCE_CENTER := Vector2(627,616.5)
const SEASON_SCALE: float = 166.0/1005.0
const DAY_SCALE: float = 128.0/771.0
const SEASONS := ["春", "夏", "秋", "冬"]

var _atlas: Node2D
var _hud: Control
var _layer: CanvasLayer
var _art: TextureRect
var _season: TextureRect
var _day: TextureRect
var _weather: Label
var _speed: Button
var _date: Label
var _season_label: Label
var _original_owner: Node
var _last: Dictionary = {}
var _error: String = ""


func configure(atlas: Node2D) -> Control:
	if is_instance_valid(_hud) and _atlas == atlas: return _hud
	_atlas = atlas
	_hud = atlas.get_node_or_null("Interface/HUD/TimeHUD") as Control
	if _hud == null:
		_hud = atlas.get_node_or_null("DeskClockLayer/TimeHUD") as Control
	if _hud == null:
		_error = "Atlas TimeHUD is missing"
		return null
	_original_owner = _hud.owner
	# Preserve the inherited print theme when leaving the native HUD parent.
	var inherited: Node = _hud.get_parent()
	while _hud.theme == null and inherited != null:
		if inherited is Control and inherited.theme != null: _hud.theme = inherited.theme
		inherited = inherited.get_parent()
	_layer = atlas.get_node_or_null("DeskClockLayer") as CanvasLayer
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.name = "DeskClockLayer"
		atlas.add_child(_layer)
	_layer.layer = 29
	if _hud.get_parent() != _layer: _hud.reparent(_layer, true)
	_hud.owner = _original_owner
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hud.size = Vector2(216, 216)
	_hud.scale = Vector2.ONE
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in ["ClockFace", "SeasonIcons", "CurrentSeasonIcon", "IndexMark", "WeatherLabel"]:
		var node := _hud.get_node_or_null(id) as CanvasItem
		if node != null: node.hide()
	var mount := _hud.get_node_or_null("SpeedMount")
	if mount != null: mount.free()
	_art = _hud.get_node_or_null("ClockDisc") as TextureRect
	if _art == null: _art = _image("ClockDisc", CLOCK_PATH)
	else: _art.texture = load(CLOCK_PATH) as Texture2D
	_art.position = Vector2.ZERO
	_art.size = Vector2(216, 216)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.move_child(_art, 0)
	_season = _ring("PrintedSeasonRing",SEASON_PATH,SEASON_SOURCE_CENTER,SEASON_SCALE,false)
	_day = _ring("PrintedDayRing",DAY_PATH,DAY_SOURCE_CENTER,DAY_SCALE,true)
	_hud.move_child(_season, 1)
	_hud.move_child(_day, 2)
	_date = _hud.get_node("DateLabel") as Label
	_season_label = _hud.get_node("CurrentSeason") as Label
	_format_label(_date, Rect2(61, 101, 94, 16), 11)
	_format_label(_season_label, Rect2(80, 123, 56, 14), 10)
	_weather = _hud.get_node_or_null("PrintWeather") as Label
	if _weather == null:
		_weather = Label.new()
		_weather.name = "PrintWeather"
		_hud.add_child(_weather)
	_format_label(_weather, Rect2(61, 142, 94, 14), 10)
	_speed = _hud.get_node("SpeedControl") as Button
	_speed.flat = true
	_speed.custom_minimum_size = Vector2.ZERO
	_speed.add_theme_font_size_override("font_size", 11)
	_speed.add_theme_color_override("font_color", Color("262d24"))
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		_speed.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	_speed.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_speed.icon = null
	_speed.position = SPEED_RECT.position
	_speed.size = SPEED_RECT.size
	_speed.hide()
	_error = ""
	tick()
	return _hud


func tick() -> void:
	if not is_instance_valid(_atlas) or not is_instance_valid(_hud): return
	var clock: Variant = _atlas.get("clock")
	if clock == null: return
	var date: Dictionary = clock.local_date()
	var year_phase: float = clock.year_phase()
	var day_phase: float = clock.day_phase()
	var daylight: float = clock.daylight_fraction()
	var weather: String = clock.weather()
	var season_index := posmod(floori(year_phase * 4.0), 4)
	var daylit := absf(day_phase - 0.5) <= daylight * 0.5 and daylight > 0.0
	_date.text = "%04d.%02d.%02d" % [int(date.year), int(date.month), int(date.day)]
	_season_label.text = SEASONS[season_index]
	_weather.text = "%s · %s" % ["昼" if daylit else "夜", _weather_word(weather)]
	_speed.hide()
	_season.rotation = -TAU * year_phase
	_day.rotation = PI - TAU * day_phase
	(_day.material as ShaderMaterial).set_shader_parameter("daylight_fraction", daylight)
	for id in ["ClockFace", "SeasonIcons", "CurrentSeasonIcon", "IndexMark", "WeatherLabel"]:
		var node := _hud.get_node_or_null(id) as CanvasItem
		if node != null: node.hide()
	_last = {"date":date.duplicate(), "day_phase":day_phase, "year_phase":year_phase, "daylight_fraction":daylight, "weather":weather, "weather_word":_weather_word(weather), "season_index":season_index, "speed":int(clock.speed), "daylit":daylit}


func image_node() -> TextureRect:
	return _art


func inspection() -> Dictionary:
	var result := _last.duplicate(true)
	result.merge({"configured":is_instance_valid(_hud), "error":_error, "layer":_layer.layer if is_instance_valid(_layer) else -1, "hud_path":str(_hud.get_path()) if is_instance_valid(_hud) else "", "owner_preserved":is_instance_valid(_hud) and _hud.owner == _original_owner, "center":CENTER, "source_pixels":{"canvas":[1254,1254], "clock_center":[625,682], "button_center":[625,70], "season_center":SEASON_SOURCE_CENTER,"day_center":DAY_SOURCE_CENTER,"season_hard_bbox":Rect2(125,123,1004,1005),"day_hard_bbox":Rect2(242,234,771,766)}, "radii":{"season":[420.5*SEASON_SCALE,83],"day":[299.5*DAY_SCALE,64]},"ring_uniform_scales":{"season":SEASON_SCALE,"day":DAY_SCALE},"ring_display_sizes":{"season":_season.size if is_instance_valid(_season) else Vector2.ZERO,"day":_day.size if is_instance_valid(_day) else Vector2.ZERO},"radial_remap":false, "rotations":{"season":_season.rotation if is_instance_valid(_season) else 0.0, "day":_day.rotation if is_instance_valid(_day) else 0.0}, "speed_rect":Rect2(_speed.position,_speed.size) if is_instance_valid(_speed) else Rect2(), "speed_text":_speed.text if is_instance_valid(_speed) else "", "date_text":_date.text if is_instance_valid(_date) else "", "season_text":_season_label.text if is_instance_valid(_season_label) else "", "weather_text":_weather.text if is_instance_valid(_weather) else "", "assets":[CLOCK_PATH,SEASON_PATH,DAY_PATH], "shader":RingShader.resource_path}, true)
	return result


func _weather_word(symbol: String) -> String:
	if "☀" in symbol: return "晴"
	if "☁" in symbol: return "多云"
	if "🌧" in symbol: return "雨"
	if "❄" in symbol: return "雪"
	if "🌬" in symbol: return "风"
	return "未设站"


func _format_label(label: Label, rect: Rect2, font_size: int) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("292d25"))
	label.show()


func _image(id: String, path: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = id
	image.texture = load(path) as Texture2D
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(image)
	return image


func _ring(id: String,path: String,source_center: Vector2,uniform_scale: float,solar: bool) -> TextureRect:
	var image := _hud.get_node_or_null(id) as TextureRect
	if image == null: image = _image(id,path)
	else: image.texture = load(path) as Texture2D
	# Scale the full clock texture uniformly to preserve its annulus.
	image.size = image.texture.get_size()*uniform_scale
	image.pivot_offset = source_center*uniform_scale
	image.position = CENTER-image.pivot_offset
	var ink := ShaderMaterial.new()
	ink.shader = RingShader
	ink.set_shader_parameter("source_center_uv",source_center/image.texture.get_size())
	ink.set_shader_parameter("solar_band",solar)
	image.material = ink
	return image
