extends SceneTree

const FONT_PATH := "res://assets/image/fonts/handwritten_font.tres"
const FONT_SIZES := [9, 10, 11, 12, 15, 17, 24, 36, 48]
const SCALES := [0.35, 0.5, 0.75, 1.0, 2.592, 3.5]
const IMAGE_SIZE := Vector2i(1600, 620)
const ZH := "北回归线 · 海堤图书馆"
const EN := "23.44 N · MEME R01"

class TextSheet extends Node2D:
	var face: Font
	var compact := false
	func _draw() -> void:
		for row in (6 if compact else FONT_SIZES.size()):
			var size: int = FONT_SIZES[row]
			var baseline := 24 + row * 30 if compact else 60 + row * 60
			draw_string(face, Vector2(20, baseline), "海堤图书馆" if compact else ZH, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)
			draw_string(face, Vector2(200 if compact else 720, baseline), "MEME R01 Trade Offer" if compact else EN, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)

var output := ""
var source: FontVariation
var failures: Array[String] = []
var checks: Array[String] = []
var evidence: Array = []
var production := {}

func _isolate_menu(node: Node) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path == "res://scripts/presentation/ui/menus/main_menu.gd":
		node.settings_path = output.path_join("isolated_interface.cfg")

func _production_settings() -> Dictionary:
	var settings_hash := FileAccess.get_sha256("user://meme_interface.cfg") if FileAccess.file_exists("user://meme_interface.cfg") else "absent"
	node_added.connect(_isolate_menu)
	var studio: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(studio)
	for frame in 1800:
		await process_frame
		if studio.ready_3d or not str(studio.startup_error).is_empty(): break
	node_added.disconnect(_isolate_menu)
	_check(studio.ready_3d, "production_main_scene_ready")
	if not studio.ready_3d:
		studio.queue_free()
		await process_frame
		return {}
	var viewport: SubViewport = studio.logical
	var result := {"main_scene": "res://scenes/main.tscn", "viewport": str(viewport.get_path()),
		"viewport_filter": viewport.canvas_item_default_texture_filter,
		"viewport_size": [viewport.size.x, viewport.size.y],
		"settings_path": studio.page._shell.main_menu.settings_path}
	_check(result.settings_path == output.path_join("isolated_interface.cfg"), "production_settings_isolated")
	_check(viewport.size == Vector2i(1600, 900), "logical_dimensions_unchanged")
	studio.queue_free()
	await process_frame
	var after_hash := FileAccess.get_sha256("user://meme_interface.cfg") if FileAccess.file_exists("user://meme_interface.cfg") else "absent"
	_check(settings_hash == after_hash, "player_settings_unchanged")
	result["player_settings_unchanged"] = settings_hash == after_hash
	return result

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks.append(name)
	if not ok: failures.append(name)

func _font(density: float, mipmaps: bool) -> FontVariation:
	var face := source.duplicate() as FontVariation
	var base := source.base_font.duplicate() as FontFile
	base.clear_cache()
	base.oversampling = density
	base.generate_mipmaps = mipmaps
	face.base_font = base
	return face

func _render(face: FontVariation, scale_value: float, filtering: int, resolution_factor := 1,
		viewport_filter: int = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR) -> Image:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = IMAGE_SIZE * resolution_factor
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.canvas_item_default_texture_filter = viewport_filter
	root.add_child(viewport)
	var paper := ColorRect.new()
	paper.color = Color.WHITE
	paper.size = Vector2(viewport.size)
	viewport.add_child(paper)
	var sheet := TextSheet.new()
	sheet.face = face
	sheet.compact = scale_value > 1.0
	sheet.scale = Vector2.ONE * scale_value
	sheet.texture_filter = filtering
	viewport.add_child(sheet)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = Vector2.ONE * resolution_factor
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	if resolution_factor > 1:
		image.resize(IMAGE_SIZE.x, IMAGE_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return image

func _atlas(face: FontVariation) -> Array:
	var result: Array = []
	var server := TextServerManager.get_primary_interface()
	var rid: RID = face.get_rids()[0]
	for key: Vector2i in server.font_get_size_cache_list(rid):
		var sample_glyph := server.font_get_glyph_index(rid, key.x, "海".unicode_at(0), 0)
		var sample_texture := server.font_get_glyph_texture_idx(rid, key, sample_glyph)
		for index in server.font_get_texture_count(rid, key):
			var image := server.font_get_texture_image(rid, key, index)
			var gpu_sample := {}
			if index == sample_texture:
				var texture_rid := server.font_get_glyph_texture_rid(rid, key, sample_glyph)
				var gpu_image := RenderingServer.texture_2d_get(texture_rid)
				if gpu_image != null:
					gpu_sample = {"glyph": "海", "has_mipmaps": gpu_image.has_mipmaps(),
						"mipmap_count": gpu_image.get_mipmap_count(), "bytes": gpu_image.get_data().size()}
			result.append({"pixel_font_size": key.x, "texture": index,
				"size": [image.get_width(), image.get_height()],
				"cpu_has_mipmaps": image.has_mipmaps(), "cpu_mipmap_count": image.get_mipmap_count(),
				"cpu_bytes": image.get_data().size(), "gpu_sample": gpu_sample})
	return result

func _measure(images: Array[Image], reference: Image) -> Array:
	var accumulators: Array = []
	for index in images.size():
		accumulators.append({"absolute": 0.0, "squared": 0.0, "dark_dropout": 0, "spurious_dark": 0})
	var count := 0
	for y in reference.get_height():
		for x in reference.get_width():
			var target := reference.get_pixel(x, y).r
			var values: Array[float] = []
			var minimum := target
			for image: Image in images:
				var value := image.get_pixel(x, y).r
				values.append(value)
				minimum = minf(minimum, value)
			if minimum > .99: continue
			count += 1
			for index in values.size():
				var difference := absf(values[index] - target)
				accumulators[index].absolute += difference
				accumulators[index].squared += difference * difference
				if target < .45 and values[index] > .9: accumulators[index].dark_dropout += 1
				if target > .9 and values[index] < .45: accumulators[index].spurious_dark += 1
	var result: Array = []
	for entry: Dictionary in accumulators:
		result.append({"common_ink_pixels": count,
			"mean_absolute_error": entry.absolute / maxi(1, count),
			"root_mean_square_error": sqrt(entry.squared / maxi(1, count)),
			"dark_dropout_pixels": entry.dark_dropout, "spurious_dark_pixels": entry.spurious_dark})
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].is_absolute_path():
		push_error("font_minification_probe requires an absolute disposable output directory")
		quit(2)
		return
	output = args[0]
	if DirAccess.make_dir_recursive_absolute(output) != OK or DisplayServer.get_name() == "headless":
		push_error("font_minification_probe requires writable output and a real renderer")
		quit(2)
		return
	source = load(FONT_PATH) as FontVariation
	if source == null or not source.base_font is FontFile:
		push_error("Production FontVariation is unavailable")
		quit(2)
		return
	production = await _production_settings()
	if production.is_empty():
		push_error("Cannot inspect actual production viewport")
		quit(2)
		return
	var variants: Array = [
		{"name": "current_4x_linear", "font": _font(4.0, false), "filter": CanvasItem.TEXTURE_FILTER_LINEAR},
		{"name": "mipmaps_only", "font": _font(4.0, true), "filter": CanvasItem.TEXTURE_FILTER_LINEAR},
		{"name": "filter_only", "font": _font(4.0, false), "filter": CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS},
		{"name": "mipmaps_and_filter", "font": _font(4.0, true), "filter": CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS},
		{"name": "legacy_native_density", "font": _font(0.0, false), "filter": CanvasItem.TEXTURE_FILTER_LINEAR},
		{"name": "actual_production", "font": source, "filter": CanvasItem.TEXTURE_FILTER_PARENT_NODE,
			"viewport_filter": production.viewport_filter}
	]
	var reference_font := _font(8.0, true)
	for scale_value: float in SCALES:
		var images: Array[Image] = []
		var expected := await _render(reference_font, scale_value, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, 4)
		var prefix := "scale_%.2f" % scale_value
		_check(expected.save_png(output.path_join(prefix + "_reference_4x_downsample.png")) == OK, "capture_reference_" + prefix)
		for variant: Dictionary in variants:
			var image := await _render(variant.font, scale_value, variant.filter, 1,
				variant.get("viewport_filter", Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR))
			images.append(image)
			_check(image.save_png(output.path_join(prefix + "_" + variant.name + ".png")) == OK,
				"capture_" + prefix + "_" + variant.name)
		var metrics := _measure(images, expected)
		for index in variants.size():
			metrics[index]["variant"] = variants[index].name
			metrics[index]["mae_ratio_to_current"] = metrics[index].mean_absolute_error / maxf(.00001, metrics[0].mean_absolute_error)
		_check(metrics[0].common_ink_pixels > 100, "text_present_" + prefix)
		if scale_value < 1.0:
			_check(metrics[-1].mae_ratio_to_current <= .75, "production_reduces_minification_error_" + prefix)
			_check(metrics[-1].dark_dropout_pixels < metrics[0].dark_dropout_pixels,
				"production_reduces_dropped_ink_" + prefix)
		elif scale_value > 1.0:
			_check(metrics[-1].mean_absolute_error <= metrics[4].mean_absolute_error * .75,
				"production_preserves_magnified_clarity_" + prefix)
		evidence.append({"scale": scale_value, "comparisons": metrics})
		print("FONT_MINIFICATION_SCALE " + JSON.stringify(evidence[-1]))
	var atlases: Array = []
	for variant: Dictionary in variants:
		atlases.append({"variant": variant.name, "actual_cache": _atlas(variant.font)})
	var report := {"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"production": production,
		"source_font": FONT_PATH, "source_oversampling": source.base_font.oversampling,
		"source_mipmaps": source.base_font.generate_mipmaps, "source_msdf": source.base_font.multichannel_signed_distance_field,
		"font_sizes": FONT_SIZES, "scales": SCALES, "text": [ZH, EN],
		"reference": "8x glyph rasterization rendered at 4x output resolution, then Lanczos downsampled; identical logical input and positions",
		"comparisons": evidence, "atlases": atlases, "checks": checks, "failures": failures,
		"passed": failures.is_empty(), "scope": "Actual main scene viewport configuration and production font, with isolated text filtering pixel regression; not a full scene visual or mouse acceptance"}
	var file := FileAccess.open(output.path_join("font_minification_report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write minification report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("FONT_MINIFICATION " + JSON.stringify({"passed": failures.is_empty(), "failures": failures,
		"checks": checks.size(), "report": output.path_join("font_minification_report.json")}))
	quit(0 if failures.is_empty() else 1)
