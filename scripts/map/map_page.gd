extends Node2D

@export var settings: AtlasMapSettings
@export var studio_settings: PressStudioSettings = preload("res://content/print/studio_settings.tres")
@export var minimum_zoom: float = 0.35
@export var maximum_zoom: float = 16.0
@export var zoom_step: float = 1.25
@export var zoom_response: float = 12.0

@onready var world_layer: Node2D = %MapInput/World
@onready var terrain: Node2D = %MapInput/World/Terrain
@onready var camera: Camera2D = $MapCamera
@onready var map_input: Control = %MapInput
@onready var markers: Node2D = %MapInput/Labels
@onready var country_name: Label = %CountryName
@onready var prototype: Label = %Prototype
@onready var population: Label = %Population
@onready var conditions: Label = %Conditions
@onready var topics: Label = %Topics
@onready var events: Label = %Events
@onready var competitors: Label = %Competitors
@onready var area_label: Label = %Area
@onready var drawer: Control = %CountryDrawer
@onready var hover_note: PanelContainer = %HoverNote
@onready var setup_note: PanelContainer = %SetupNote
@onready var workbench: PanelContainer = %WorkbenchOverlay
@onready var restart_progress: ProgressBar = %RestartProgress

var world: AtlasWorldData
var clock: PressStudioClock
var selected_country: int = -1
var hovered_country: int = -1
var panning: bool = false
var detail_level: int = 0
var target_zoom: float = 1.0
var overview_zoom: float = 1.0
var _zoom_anchor := Vector2.ZERO
var _pointer := Vector2.ZERO
var _random := RandomNumberGenerator.new()
var _drawer_offset: float
var _drawer_tween: Tween
var _restart_held: bool = false
var _restart_elapsed: float = 0.0
var _restart_consumed: bool = false
# Cache presentation only; clock and camera simulation still advance normally.
var _clock_presentation_signature: Array = []
var _marker_projection_signature: Array = []
var _clock_presentation_updates := 0
var _marker_projection_updates := 0
var _marker_projection_cache_hits := 0

func _ready() -> void:
	set_process(false)
	_random.randomize()
	clock = PressStudioClock.new(studio_settings)
	_drawer_offset = drawer.offset_left
	%SpeedControl.pressed.connect(_cycle_speed)
	%StudioConfirm.pressed.connect(establish_studio)
	%DrawerClose.pressed.connect(close_drawer)
	%PointsButton.pressed.connect(open_workbench)
	%WorkbenchClose.pressed.connect(close_workbench)
	map_input.gui_input.connect(_on_map_input)
	map_input.mouse_exited.connect(_on_map_exited)
	get_viewport().size_changed.connect(_on_viewport_resized)
	await get_tree().process_frame
	regenerate(_random.randi_range(1, 2147483647))
	set_process(true)

func regenerate(seed_value: int) -> void:
	world = AtlasMapGenerator.new().generate(settings, seed_value)
	terrain.set_world(world)
	clock.reset()
	selected_country = -1
	hovered_country = -1
	panning = false
	drawer.visible = false
	hover_note.visible = false
	workbench.visible = false
	setup_note.visible = true
	terrain.set_highlight(-1, -1)
	refresh_localization()
	print("MAP_READY seed=%d countries=%d land_groups=%d geometry=vector fingerprint=%s" % [seed_value, settings.countries.size(), world.groups.size(), world.fingerprint()])

func _process(delta: float) -> void:
	if not bool(get_meta("demo_external_clock",false)): clock.advance(delta)
	_update_clock()
	if _restart_held and not _restart_consumed:
		_restart_elapsed += delta
		restart_progress.value = _restart_elapsed / studio_settings.restart_hold_seconds
		if _restart_elapsed >= studio_settings.restart_hold_seconds:
			_restart_consumed = true
			restart_progress.visible = false
			regenerate(_random.randi_range(1, 2147483647))
	if not is_equal_approx(camera.zoom.x, target_zoom):
		var anchor := _world_position(_zoom_anchor)
		var factor := 1.0 - exp(-zoom_response * delta)
		var value := exp(lerpf(log(camera.zoom.x), log(target_zoom), factor))
		camera.zoom = Vector2.ONE * value
		camera.force_update_scroll()
		camera.position += anchor - _world_position(_zoom_anchor)
		camera.force_update_scroll()
		_update_view()
	_update_marker_positions()

func refresh_localization() -> void:
	_clock_presentation_signature.clear()
	_marker_projection_signature.clear()
	for country in settings.countries:
		markers.get_node("%s/Name" % country.id).text = tr(country.short_name_key)
		for j in 4:
			markers.get_node("%s_Site%d/Name" % [country.id, j]).text = tr(country.site_name_keys[j])
		markers.get_node("%s_Geo/Name" % country.id).text = tr(country.geography_name_key)
	_update_details()
	_update_hover()
	_update_clock()
	fit_map()

func select_country(index: int) -> void:
	selected_country = index
	terrain.set_highlight(hovered_country, selected_country)
	_update_details()
	if index < 0:
		close_drawer()
		return
	if not drawer.visible:
		drawer.offset_left = 0.0
		drawer.offset_right = -_drawer_offset
		drawer.visible = true
	_animate_drawer(_drawer_offset, 0.0)

func _animate_drawer(left: float, right: float) -> void:
	if _drawer_tween != null and _drawer_tween.is_running():
		_drawer_tween.kill()
	_drawer_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_drawer_tween.tween_property(drawer, "offset_left", left, 0.28)
	_drawer_tween.tween_property(drawer, "offset_right", right, 0.28)

func close_drawer() -> void:
	selected_country = -1
	terrain.set_highlight(hovered_country, -1)
	_update_details()
	if not drawer.visible:
		return
	_animate_drawer(0.0, -_drawer_offset)
	_drawer_tween.chain().tween_callback(drawer.hide)

func _update_details() -> void:
	%StudioConfirm.disabled = selected_country < 0
	%SetupCountry.text = tr("PRINT_STUDIO_UNSELECTED") if selected_country < 0 else tr(settings.countries[selected_country].short_name_key)
	if selected_country < 0:
		return
	var country := settings.countries[selected_country]
	country_name.text = tr(country.official_name_key)
	prototype.text = tr(country.prototype_key)
	population.text = tr("MAP_POPULATION") % (country.population / 1000000.0) if country.population_configured else tr("MAP_POPULATION_PENDING")
	conditions.text = tr(country.description_key)
	topics.text = tr(country.topics_key)
	events.text = tr(country.events_key)
	competitors.text = tr(country.competitors_key)
	area_label.text = tr("MAP_AREA") % (country.reference_area_km2 / 1000000.0)

func _update_hover() -> void:
	hover_note.visible = hovered_country >= 0 and not workbench.visible
	if hovered_country < 0:
		return
	var country := settings.countries[hovered_country]
	%HoverName.text = tr(country.short_name_key)
	%HoverSummary.text = tr(country.prototype_key) + "\n" + (tr("MAP_POPULATION") % (country.population / 1000000.0) if country.population_configured else tr("MAP_POPULATION_PENDING"))
	var edge := get_viewport_rect().size - hover_note.size
	hover_note.position = (_pointer + Vector2(18.0, 18.0)).clamp(Vector2.ZERO, edge)

func establish_studio() -> void:
	clock.establish(selected_country, world.seed_value, settings.latitude_at(world.territories[selected_country].anchor))
	setup_note.visible = false
	close_drawer()
	_update_clock()

func set_speed(value: int) -> void:
	clock.set_speed(value)
	_update_clock()

func _cycle_speed() -> void:
	set_speed((clock.speed + 1) % 3)

func _update_clock() -> void:
	var signature: Array = [clock.utc_seconds, clock.speed, clock.studio_index, clock.studio_latitude, clock.seed_value, clock.settings, TranslationServer.get_locale(), %ClockFace.material, %MapFinish.material, %SeasonIcons.get_meta("orbit_radius"), %SeasonIcons.get_meta("notch_angle")]
	if signature == _clock_presentation_signature: return
	_clock_presentation_signature = signature
	_clock_presentation_updates += 1
	var date := clock.local_date()
	%DateLabel.text = tr("PRINT_DATE_FORMAT") % [date.year, date.month, date.day]
	%WeatherLabel.text = clock.weather()
	var speed_icons: Array = %SpeedControl.get_meta("speed_icons")
	var speed_keys: PackedStringArray = %SpeedControl.get_meta("speed_keys")
	%SpeedControl.disabled = clock.studio_index < 0
	%SpeedControl.icon = speed_icons[clock.speed]
	%SpeedControl.tooltip_text = tr(speed_keys[clock.speed])
	%ClockFace.material.set_shader_parameter("day_phase", clock.day_phase())
	%ClockFace.material.set_shader_parameter("year_phase", clock.year_phase())
	%ClockFace.material.set_shader_parameter("daylight_fraction", clock.daylight_fraction())
	%MapFinish.material.set_shader_parameter("season_mix", clock.season_mix())
	_update_season_icons(clock.year_phase())

func _update_season_icons(phase: float) -> void:
	var icons: Array[TextureRect] = [%SeasonSpring, %SeasonSummer, %SeasonAutumn, %SeasonWinter]
	var radius: float = %SeasonIcons.get_meta("orbit_radius")
	var notch: float = %SeasonIcons.get_meta("notch_angle")
	# Upright symbols follow the printed season band without stretching their glyphs.
	for i in icons.size():
		var angle := PI + TAU * (phase - (i + 0.5) / icons.size())
		icons[i].position = Vector2(sin(angle), -cos(angle)) * radius - icons[i].size * 0.5
		icons[i].visible = absf(wrapf(angle - PI, -PI, PI)) >= notch
	var current := floori(phase * icons.size()) % icons.size()
	%CurrentSeasonIcon.texture = icons[current].texture
	var keys: PackedStringArray = %CurrentSeason.get_meta("season_keys")
	%CurrentSeason.text = tr(keys[current])

func open_workbench() -> void:
	workbench.visible = true
	hover_note.visible = false

func close_workbench() -> void:
	workbench.visible = false

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_R:
		_restart_held = event.pressed
		if event.pressed:
			_restart_elapsed = 0.0
			_restart_consumed = false
			restart_progress.value = 0.0
			restart_progress.visible = true
		else:
			restart_progress.visible = false
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	match key:
		KEY_F1: set_speed(0)
		KEY_F2: set_speed(1)
		KEY_F3: set_speed(2)
		KEY_SPACE:
			clock.toggle_pause()
			_update_clock()
		KEY_ESCAPE:
			if workbench.visible: close_workbench()
			else: close_drawer()
		KEY_COMMA, KEY_LESS: set_speed(maxi(clock.speed - 1, 0))
		KEY_PERIOD, KEY_GREATER: set_speed(mini(clock.speed + 1, 2))
		_: return
	get_viewport().set_input_as_handled()

func fit_map() -> void:
	_marker_projection_signature.clear()
	var fitted := minf(map_input.size.x / settings.world_size.x, map_input.size.y / settings.world_size.y) * 0.98
	overview_zoom = clampf(fitted, minimum_zoom, maximum_zoom)
	camera.zoom = Vector2.ONE * overview_zoom
	target_zoom = overview_zoom
	camera.position = settings.world_size * 0.5
	camera.force_update_scroll()
	_layout_country_labels()
	_update_view()
	_update_marker_positions()

func _update_view() -> void:
	var ratio := camera.zoom.x / overview_zoom
	detail_level = 2 if ratio >= settings.local_zoom else (1 if ratio >= settings.capital_zoom else 0)
	terrain.set_view(camera.zoom.x, detail_level)
	terrain.set_zoom_ratio(ratio)
	%LatitudeGrid.set_zoom_ratio(ratio)

func _update_marker_positions() -> void:
	if world == null: return
	var transform := _local_map_view()
	var time_hud: Control = %DateLabel.get_parent()
	var signature: Array = [world, transform, map_input.size, map_input.get_global_transform_with_canvas(), camera.zoom, overview_zoom, detail_level, time_hud.get_global_rect(), %PointsButton.get_global_rect(), TranslationServer.get_locale()]
	if signature == _marker_projection_signature:
		_marker_projection_cache_hits += 1
		return
	_marker_projection_signature = signature
	_marker_projection_updates += 1
	# Screen-space labels keep their native glyph resolution while the vector map scales.
	world_layer.transform = transform
	var rectangle := Rect2(Vector2.ZERO, map_input.size)
	for i in settings.countries.size():
		var country := settings.countries[i]
		var geometry := world.territories[i]
		var marker: Node2D = markers.get_node(str(country.id))
		marker.position = transform * marker.anchor
		marker.set_zoom_ratio(camera.zoom.x / overview_zoom)
		var ratio := camera.zoom.x / overview_zoom
		marker.visible = ratio + 0.001 >= marker.minimum_zoom_ratio and ratio < maxf(settings.local_zoom, marker.minimum_zoom_ratio * settings.capital_zoom) and rectangle.has_point(marker.position)
		for j in 4:
			var site: Node2D = markers.get_node("%s_Site%d" % [country.id, j])
			site.position = transform * geometry.sites[j]
			site.visible = detail_level >= (1 if j == 0 else 2) and rectangle.has_point(site.position)
		var geographic: Node2D = markers.get_node("%s_Geo" % country.id)
		geographic.position = transform * geometry.sites[3]
		geographic.visible = detail_level >= 2 and rectangle.has_point(geographic.position)
	_update_latitude_labels(transform)
	_declutter_labels()

func _update_latitude_labels(view: Transform2D) -> void:
	var padding: float = %LatitudeLabels.get_meta("edge_padding")
	var line_offset: float = %LatitudeLabels.get_meta("line_offset")
	var map_right := (view * Vector2(settings.world_size.x, 0.0)).x
	var map_left := (view * Vector2.ZERO).x
	for label: Label in %LatitudeLabels.get_children():
		var index: int = label.get_meta("latitude_index")
		var latitude: float = %LatitudeGrid.style.latitudes[index]
		var y := (view * Vector2(0.0, settings.world_y_at_latitude(latitude))).y
		label.text = tr(label.get_meta("label_key"))
		label.position = Vector2(minf(map_input.size.x, map_right) - label.size.x - padding, y - line_offset)
		# Captions only occupy fully visible map space outside the fixed stamps.
		var caption_bounds := label.get_global_rect()
		var inside_map := map_input.get_global_rect().encloses(caption_bounds)
		var time_hud: Control = %DateLabel.get_parent()
		var clear_of_stamps := not caption_bounds.intersects(time_hud.get_global_rect()) and not caption_bounds.intersects(%PointsButton.get_global_rect())
		label.visible = inside_map and clear_of_stamps and y >= line_offset and y < map_input.size.y and map_right > padding and map_left < map_input.size.x - padding

func _on_viewport_resized() -> void:
	await get_tree().process_frame
	fit_map()

func _local_map_view() -> Transform2D:
	var view := get_viewport().get_canvas_transform()
	view.origin += map_input.size * 0.5 - get_viewport_rect().size * 0.5
	return view

func map_view_transform() -> Transform2D:
	return map_input.get_global_transform_with_canvas() * _local_map_view()

func _world_position(screen_position: Vector2) -> Vector2:
	return map_view_transform().affine_inverse() * screen_position

func _on_map_input(event: InputEvent) -> void:
	# GUI input can arrive before the first frame builds the world.
	if world == null:
		return
	if event is InputEventMouseButton:
		var screen_position: Vector2 = map_input.get_global_transform_with_canvas() * event.position
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			target_zoom = camera.zoom.x
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_country(world.country_at(_world_position(screen_position)))
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_anchor = screen_position
			var factor := zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step
			target_zoom = clampf(target_zoom * factor, minimum_zoom, maximum_zoom)
		map_input.accept_event()
	elif event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / camera.zoom
			camera.force_update_scroll()
		_pointer = map_input.get_global_transform_with_canvas() * event.position
		hovered_country = world.country_at(_world_position(_pointer))
		terrain.set_highlight(hovered_country, selected_country)
		_update_hover()

func _on_map_exited() -> void:
	hovered_country = -1
	panning = false
	terrain.set_highlight(-1, selected_country)
	_update_hover()

func geometry_inspection() -> Dictionary:
	var areas: Array[float] = []
	var isolated: Array[int] = []
	var bounds := Rect2(settings.world_size, Vector2.ZERO)
	var vertices: int = 0
	var land_area: float = 0.0
	for i in world.territories.size():
		var territory := world.territories[i]
		areas.append(territory.area)
		land_area += territory.area
		if territory.neighbors.is_empty():
			isolated.append(i)
		for outline in territory.outlines:
			vertices += outline.size()
			for point in outline:
				bounds = bounds.expand(point)
	return {"representation":"vector", "land_fraction":land_area/(settings.world_size.x*settings.world_size.y), "coast_stroke":false, "border_width_world":settings.border_width, "country_areas":areas, "land_groups":world.groups.size(), "isolated":isolated,
		"screen_fixed_labels":true, "territory_aligned_labels":true, "smooth_zoom":true,"elevation_noise":"Perlin FBM","visible_noise_texture":false,"enclaves":world.enclaves.size(),"river_sources":world.terrain.sources.size(),"river_confluences":world.terrain.junctions.size(),"lake_basins":world.terrain.lake_basins.size(), "detail_level":detail_level, "vertices":vertices, "terrain_type":terrain.get_class(), "fingerprint":world.fingerprint()}

func inspection_state() -> Dictionary:
	return {"marker_projection_updates":_marker_projection_updates, "marker_projection_cache_hits":_marker_projection_cache_hits, "clock_presentation_updates":_clock_presentation_updates, "seed":world.seed_value, "countries":settings.countries.size(), "groups":world.groups.size(), "fingerprint":world.fingerprint(),
		"selected":selected_country, "hovered":hovered_country, "zoom":camera.zoom.x, "target_zoom":target_zoom, "detail_level":detail_level,
		"camera":camera.position, "locale":TranslationServer.get_locale(), "map_rect":map_input.get_global_rect(), "details_visible":drawer.visible,
		"clock":clock.inspection(), "setup_visible":setup_note.visible, "workbench_visible":workbench.visible, "economy":"unconnected placeholder", "water_opacity":terrain.water_opacity}

func _label_rect(label: Label) -> Rect2:
	var font := label.get_theme_font("font")
	var text_size := font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
	var offset := Vector2((label.size.x-text_size.x)*0.5,0) if label.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER else Vector2.ZERO
	return Rect2(label.global_position+offset,text_size).grow(3.0)

func _declutter_labels() -> void:
	var occupied: Array[Rect2] = []
	for label: Label in %LatitudeLabels.get_children():
		if label.visible:
			occupied.append(_label_rect(label))
	var ink: Array[PackedVector2Array] = []
	for i in settings.countries.size():
		var marker: Node2D = markers.get_node(str(settings.countries[i].id))
		if not marker.visible: continue
		var polygons: Array[PackedVector2Array] = marker.screen_polygons()
		for polygon in polygons:
			for placed in ink:
				if not Geometry2D.intersect_polygons(polygon, placed).is_empty(): marker.visible = false
		if marker.visible:
			ink.append_array(polygons)
			occupied.append_array(marker.screen_boxes())

	for country in settings.countries:
		for suffix in ["_Site0","_Site1","_Site2","_Site3","_Geo"]:
			var marker: Node2D = markers.get_node(str(country.id)+suffix)
			var label: Label = marker.get_node("Name")
			label.visible = marker.visible
			if not marker.visible: continue
			var bounds := _label_rect(label)
			for rectangle in occupied:
				if bounds.intersects(rectangle): label.visible = false
			if label.visible: occupied.append(bounds)

func _layout_country_labels() -> void:
	for i in settings.countries.size():
		markers.get_node(str(settings.countries[i].id)).layout_country(world.territories[i], overview_zoom, PackedFloat32Array([1.0, settings.capital_zoom, settings.local_zoom]))
