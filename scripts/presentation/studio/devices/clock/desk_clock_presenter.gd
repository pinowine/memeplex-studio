class_name DeskClockPresenter
extends RefCounted

const HardwareFrames := preload("res://scripts/presentation/studio/desk/hardware_frames.gd")
const TEXT_FONT := preload("res://assets/image/fonts/development_font.tres")
const DATE_FONT := preload("res://assets/image/fonts/body_medium_font.tres")
const CENTER := Vector2(108, 118)
const SPEED_RECT := Rect2(92, 3, 30, 24)
static var SEASONS := [DeskLocalization.source("LOC_SPRING_B3C33B7A"), DeskLocalization.source("LOC_SUMMER_8482432C"), DeskLocalization.source("LOC_AUTUMN_5A2E5E4B"), DeskLocalization.source("LOC_WINTER_0868FBC8")]

var _atlas: Node2D
var _hud: Control
var _layer: CanvasLayer
var _art: TextureRect
var _weather: Label
var _speed: Button
var _date: Label
var _season_label: Label
var _season_icon: TextureRect
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
	for id in ["ClockFace", "SeasonIcons", "IndexMark", "WeatherLabel"]:
		var node := _hud.get_node_or_null(id) as CanvasItem
		if node != null: node.hide()
	var mount := _hud.get_node_or_null("SpeedMount")
	if mount != null: mount.free()
	_art = _hud.get_node_or_null("ClockDisc") as TextureRect
	if _art == null:
		_art = TextureRect.new()
		_art.name = "ClockDisc"
		_hud.add_child(_art)
	_art.texture = HardwareFrames.texture(Vector2(1254, 1254))
	_art.self_modulate.a = 0.0
	_art.position = Vector2.ZERO
	_art.size = Vector2(216, 216)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.move_child(_art, 0)
	_date = _hud.get_node("DateLabel") as Label
	_season_label = _hud.get_node("CurrentSeason") as Label
	_format_label(_date, Rect2(61, 100, 94, 18), 12)
	_date.add_theme_font_override("font", DATE_FONT)
	_format_label(_season_label, Rect2(80, 121, 60, 16), 10)
	_season_icon = _hud.get_node("CurrentSeasonIcon") as TextureRect
	_season_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_season_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_season_icon.size = Vector2(12, 12)
	_season_icon.show()
	_weather = _hud.get_node_or_null("PrintWeather") as Label
	if _weather == null:
		_weather = Label.new()
		_weather.name = "PrintWeather"
		_hud.add_child(_weather)
	_format_label(_weather, Rect2(61, 140, 94, 15), 9)
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
	_fit_text(_date, "%04d.%02d.%02d" % [int(date.year), int(date.month), int(date.day)], 12)
	_season_label.size.x = 60.0
	_fit_text(_season_label, DeskLocalization.text(SEASONS[season_index]), 10)
	var season_width := minf(TEXT_FONT.get_string_size(_season_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _season_label.get_theme_font_size("font_size")).x, 60.0)
	var season_left := CENTER.x - (season_width + 16.0) * 0.5
	_season_icon.position = Vector2(season_left, 123)
	_season_icon.texture = (_hud.get_node("SeasonIcons").get_child(season_index) as TextureRect).texture
	_season_label.position.x = season_left + 16.0
	_season_label.size.x = season_width
	_fit_text(_weather, "%s · %s" % [DeskLocalization.text("LOC_DAY_0201C422") if daylit else DeskLocalization.text("LOC_NIGHT_A519542A"), _weather_word(weather)], 9)
	_speed.hide()
	for id in ["ClockFace", "SeasonIcons", "IndexMark", "WeatherLabel"]:
		var node := _hud.get_node_or_null(id) as CanvasItem
		if node != null: node.hide()
	_last = {"date":date.duplicate(), "day_phase":day_phase, "year_phase":year_phase, "daylight_fraction":daylight, "weather":weather, "weather_word":_weather_word(weather), "season_index":season_index, "speed":int(clock.speed), "daylit":daylit}


func image_node() -> TextureRect:
	return _art


func inspection() -> Dictionary:
	var result := _last.duplicate(true)
	result.merge({"configured":is_instance_valid(_hud), "error":_error, "layer":_layer.layer if is_instance_valid(_layer) else -1, "hud_path":str(_hud.get_path()) if is_instance_valid(_hud) else "", "owner_preserved":is_instance_valid(_hud) and _hud.owner == _original_owner, "speed_rect":Rect2(_speed.position,_speed.size) if is_instance_valid(_speed) else Rect2(), "speed_text":_speed.text if is_instance_valid(_speed) else "", "date_text":_date.text if is_instance_valid(_date) else "", "season_text":_season_label.text if is_instance_valid(_season_label) else "", "weather_text":_weather.text if is_instance_valid(_weather) else ""}, true)
	return result


func _weather_word(symbol: String) -> String:
	if "☀" in symbol: return DeskLocalization.text("LOC_CLEAR_6379EDE5")
	if "☁" in symbol: return DeskLocalization.text("LOC_CLOUDY_30C37977")
	if "🌧" in symbol: return DeskLocalization.text("LOC_RAIN_124D6058")
	if "❄" in symbol: return DeskLocalization.text("LOC_SNOW_53058FE2")
	if "🌬" in symbol: return DeskLocalization.text("LOC_WIND_BE65BD55")
	return DeskLocalization.text("LOC_NO_STATION_0EBEB720")


func _format_label(label: Label, rect: Rect2, font_size: int) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	# Scene placeholders must not enlarge the text area sampled by the clock face.
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font", TEXT_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("292d25"))
	label.show()


func _fit_text(label: Label, text: String, font_size: int) -> void:
	label.text = text
	var font := label.get_theme_font("font")
	while font_size > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func angles() -> Vector2:
	return Vector2(-TAU * float(_last.year_phase), PI - TAU * float(_last.day_phase))
