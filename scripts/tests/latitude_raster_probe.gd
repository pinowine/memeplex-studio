extends SceneTree

const GRID_PATH := "res://scripts/presentation/map/map_latitude_grid.gd"
const SETTINGS_PATH := "res://data/map/settings/world_settings.tres"
const STYLE_PATH := "res://data/map/settings/latitude_style.tres"
const LOGICAL_SIZE := Vector2i(640, 320)
const WORLD_SIZE := Vector2(360, 120)
const ORIGIN := Vector2(32, 40)
const SCALES := [0.75, 1.0, 1.5]

var output := ""
var checks: Array[String] = []
var failures: Array[String] = []
var evidence: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func _capture(density: int, zoom: float, diagnostic_width: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "LatitudeRaster%d" % density
	viewport.size = LOGICAL_SIZE * density
	viewport.size_2d_override = LOGICAL_SIZE
	viewport.size_2d_override_stretch = true
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var grid: Node2D = load(GRID_PATH).new()
	grid.settings = load(SETTINGS_PATH).duplicate()
	grid.settings.world_size = WORLD_SIZE
	grid.style = load(STYLE_PATH).duplicate()
	grid.style.latitudes = PackedFloat32Array([0.0])
	if diagnostic_width:
		grid.style.line_color = Color.BLACK
		grid.style.equator_color = Color.BLACK
		grid.style.paper_color = Color.TRANSPARENT
		grid.style.line_width = 6.0
		grid.style.equator_width = 6.0
	grid.position = ORIGIN
	grid.scale = Vector2.ONE * zoom
	viewport.add_child(grid)
	for frame in 4:
		await process_frame
		RenderingServer.force_draw(false)
	var physical: Image = viewport.get_texture().get_image()
	var displayed: Image = physical.duplicate()
	# Area reduction preserves measured ink mass instead of sharpening the reference.
	if density != 1: displayed.resize(LOGICAL_SIZE.x, LOGICAL_SIZE.y, Image.INTERPOLATE_TRILINEAR)
	var label := "%s_zoom_%.2f_density_%d" % ["wide_geometry" if diagnostic_width else "production_style", zoom, density]
	_check(physical.save_png(output.path_join(label + "_physical.png")) == OK, "capture_physical_" + label)
	_check(displayed.save_png(output.path_join(label + "_displayed.png")) == OK, "capture_displayed_" + label)
	var transforms := {"physical_size": viewport.size, "logical_rect": viewport.get_visible_rect(),
		"final_transform": viewport.get_final_transform(), "grid_canvas_transform": grid.get_global_transform_with_canvas()}
	var metrics := _measure(displayed, zoom)
	viewport.queue_free()
	await process_frame
	return {"label": label, "density": density, "zoom": zoom, "diagnostic_width": diagnostic_width,
		"transforms": transforms, "metrics": metrics}

func _measure(image: Image, zoom: float) -> Dictionary:
	var expected_y := ORIGIN.y + WORLD_SIZE.y * 0.5 * zoom
	var left := ceili(ORIGIN.x + 20.0)
	var right := floori(ORIGIN.x + WORLD_SIZE.x * zoom - 20.0)
	var top := floori(expected_y) - 9
	var bottom := ceili(expected_y) + 9
	var columns: Array[float] = []
	var total_alpha := 0.0
	var alpha_y := 0.0
	var peak_column := 0.0
	for x in range(left, right):
		var ink := 0.0
		for y in range(top, bottom + 1):
			var alpha := image.get_pixel(x, y).a
			ink += alpha
			alpha_y += alpha * (float(y) + 0.5)
		columns.append(ink)
		total_alpha += ink
		peak_column = maxf(peak_column, ink)
	var starts: Array[int] = []
	var lengths: Array[int] = []
	var inside := false
	var start := 0
	var threshold := peak_column * 0.5
	for index in columns.size():
		var on := columns[index] > threshold
		if on and not inside:
			start = index
			if index > 0: starts.append(index + left)
		elif not on and inside and start > 0:
			lengths.append(index - start)
		inside = on
	var period := 0.0
	for index in range(1, starts.size()): period += starts[index] - starts[index - 1]
	period /= maxi(1, starts.size() - 1)
	var dash := 0.0
	for length in lengths: dash += length
	dash /= maxi(1, lengths.size())
	# Integrated coverage avoids a one-pixel edge crossing the 50% threshold.
	var equivalent_dash := 0.0
	for index in range(1, starts.size()):
		var ink := 0.0
		for x in range(starts[index - 1] - left, starts[index] - left): ink += columns[x]
		equivalent_dash += ink / maxf(peak_column, 0.00001)
	equivalent_dash /= maxi(1, starts.size() - 1)
	return {"dash_starts": starts, "dash_count": starts.size(), "mean_period": period,
		"mean_dash_length": dash, "mean_equivalent_dash_length": equivalent_dash,
		"peak_column_coverage": peak_column, "total_alpha": total_alpha,
		"centroid_y": alpha_y / maxf(total_alpha, 0.00001), "expected_center_y": expected_y,
		"sample_bounds": Rect2i(left, top, right - left, bottom - top + 1)}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].is_absolute_path():
		push_error("latitude_raster_probe requires an absolute disposable output directory")
		quit(2)
		return
	output = args[0]
	if DisplayServer.get_name() == "headless" or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("latitude_raster_probe requires writable output and a real renderer")
		quit(2)
		return
	for diagnostic_width in [false, true]:
		for zoom: float in SCALES:
			var native: Dictionary = await _capture(1, zoom, diagnostic_width)
			var doubled: Dictionary = await _capture(2, zoom, diagnostic_width)
			var a: Dictionary = native.metrics
			var b: Dictionary = doubled.metrics
			var label := "%s_zoom_%.2f" % ["wide_geometry" if diagnostic_width else "production_style", zoom]
			_check(a.dash_count >= 8 and b.dash_count >= 8, label + "_visible_dashes")
			_check(absf(a.mean_period - 16.0) <= 0.25, label + "_native_period_16")
			_check(absf(b.mean_period - a.mean_period) <= 0.25, label + "_backing_preserves_period")
			_check(absf(b.mean_equivalent_dash_length - a.mean_equivalent_dash_length) <= 0.5, label + "_backing_preserves_dash_length")
			_check(absf(b.centroid_y - a.centroid_y) <= 0.6, label + "_backing_preserves_position")
			var coverage_ratio: float = b.peak_column_coverage / maxf(a.peak_column_coverage, 0.00001)
			_check(coverage_ratio >= 0.75 and coverage_ratio <= 1.25, label + "_backing_preserves_stroke_coverage")
			if diagnostic_width:
				_check(absf(a.peak_column_coverage - 6.0) <= 0.75, label + "_native_width_6")
				_check(absf(b.peak_column_coverage - 6.0) <= 0.75, label + "_doubled_width_6")
			evidence.append({"native": native, "doubled": doubled, "coverage_ratio": coverage_ratio})
			print("LATITUDE_CASE " + JSON.stringify(evidence[-1]))
	var report := {"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"grid_path": GRID_PATH, "grid_sha256": FileAccess.get_sha256(GRID_PATH),
		"settings_path": SETTINGS_PATH, "style_path": STYLE_PATH,
		"fixture": "Production grid/settings/style, isolated equator and 360x120 logical world; authored colors and widths plus opaque 6-pixel diagnostic stroke; identical coordinates at 1x and 2x backing.",
		"downsample": "Image.INTERPOLATE_TRILINEAR to common 640x320 logical size; transparency coverage, not RGB contrast.",
		"scope": "Actual grid drawing and raster geometry, not full 3D texture sampling or the Window path.",
		"comparisons": evidence, "checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open(output.path_join("latitude_raster_report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write latitude raster report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("LATITUDE_RASTER " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(),
		"failures": failures, "report": output.path_join("latitude_raster_report.json")}))
	quit(0 if failures.is_empty() else 1)
