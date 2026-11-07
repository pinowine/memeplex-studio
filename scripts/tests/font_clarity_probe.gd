extends SceneTree

const FONT_PATH := "res://assets/image/fonts/handwritten_font.tres"
const FONT_SIZES := [9, 10, 11, 12, 15, 17]
const CAMERA_ZOOMS := [1.0, 2.592, 3.5]
const REFERENCE_DENSITY := 8.0
const SAMPLES := {
	"zh": "海堤图书馆晚间开放 · 冬",
	"en": "MEME R01 Trade Offer 2000.01.13"
}

class TextSheet extends Node2D:
	var face: Font
	var text := ""
	func _draw() -> void:
		for row in FONT_SIZES.size():
			draw_string(face, Vector2(12, 26 + row * 34), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZES[row], Color.BLACK)

var output := ""
var failures: Array[String] = []
var checks: Array[String] = []
var report := {}
var source: FontVariation
var reference: FontVariation
var legacy: FontVariation
var headless := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition: failures.append(name)

func _v(value: Vector2) -> Array:
	return [value.x, value.y]

func _settle() -> void:
	for frame in 3: await process_frame
	if not headless: await RenderingServer.frame_post_draw

func _copy_font(density: float) -> FontVariation:
	var copy := source.duplicate() as FontVariation
	var base := source.base_font.duplicate() as FontFile
	base.clear_cache()
	base.oversampling = density
	copy.base_font = base
	return copy

func _glyph_evidence(face: FontVariation) -> Array:
	var result: Array = []
	var server := TextServerManager.get_primary_interface()
	var rid: RID = face.get_rids()[0]
	var canvas_item := RenderingServer.canvas_item_create()
	for font_size: int in FONT_SIZES:
		face.draw_string(canvas_item, Vector2.ZERO, SAMPLES.zh + SAMPLES.en,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	RenderingServer.free_rid(canvas_item)
	for size_key: Vector2i in server.font_get_size_cache_list(rid):
		if server.font_get_texture_count(rid, size_key) == 0: continue
		var glyphs: Array = []
		for symbol: String in ["海", "图", "冬", "M", "R", "0"]:
			var codepoint := symbol.unicode_at(0)
			var glyph := server.font_get_glyph_index(rid, size_key.x, codepoint, 0)
			var extent := server.font_get_glyph_size(rid, size_key, glyph)
			var uv := server.font_get_glyph_uv_rect(rid, size_key, glyph)
			glyphs.append({"symbol": symbol, "glyph": glyph,
				"cache_glyph_size": _v(extent), "atlas_pixel_size": _v(uv.size)})
		var textures: Array = []
		for texture_index in server.font_get_texture_count(rid, size_key):
			var atlas := server.font_get_texture_image(rid, size_key, texture_index)
			textures.append({"index": texture_index, "size": _v(atlas.get_size()), "bytes": atlas.get_data().size()})
		result.append({"cache_pixel_font_size": size_key.x, "outline_size": size_key.y,
			"glyphs": glyphs, "atlas_textures": textures})
	return result

func _shape(face: Font, value: String, font_size: int) -> Dictionary:
	var paragraph := TextParagraph.new()
	paragraph.width = 186.0
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	paragraph.add_string(value, face, font_size)
	return {"text": value, "font_size": font_size,
		"string_size": _v(face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)),
		"height": face.get_height(font_size), "ascent": face.get_ascent(font_size),
		"paragraph_size": _v(paragraph.get_size()), "line_count": paragraph.get_line_count()}

func _shape_checks() -> void:
	var values := ["", SAMPLES.zh, SAMPLES.en, SAMPLES.zh.repeat(8), SAMPLES.en.repeat(8)]
	var entries: Array = []
	for value: String in values:
		for font_size: int in FONT_SIZES:
			var current := _shape(source, value, font_size)
			var old := _shape(legacy, value, font_size)
			entries.append({"current": current, "default_density": old})
			_check(current == old, "shape_matches_default_%d_%d" % [value.length(), font_size])
			_check(current.text == value, "shape_preserves_text_%d_%d" % [value.length(), font_size])
			_check(is_finite(current.string_size[0]) and current.string_size[0] >= 0,
				"finite_text_width_%d_%d" % [value.length(), font_size])
			if value.is_empty(): _check(current.string_size[0] == 0, "empty_text_width_%d" % font_size)
	report["shaping"] = entries

func _fax_checks() -> void:
	var fax_script: Script = load("res://scripts/presentation/studio/devices/fax/desk_fax_output_page.gd")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 1000)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var theme := Theme.new()
	theme.default_font = source
	var fax: Control = fax_script.new()
	viewport.add_child(fax)
	var event := {"id": "font_clarity_fixture", "hour": 296, "title": SAMPLES.zh,
		"narrative": "海堤图书馆试行延长晚间开放，学生不必在闭馆后匆忙寻找去处。 " + SAMPLES.en}
	fax.configure(event, theme)
	fax.set_feed_geometry(Vector2(210, 297), 1.0)
	fax.finish_output(0)
	fax.position = Vector2(30, 20)
	fax.scale = Vector2.ONE * 2.592
	await _settle()
	var evidence: Array = []
	for item: String in ["HandwrittenHeadline", "HandwrittenExcerpt", "EventHistoryTab"]:
		var label: Label = fax.get_node(item)
		evidence.append({"node": item, "text": label.text,
			"size": _v(label.size), "position": _v(label.position),
			"font_size": label.get_theme_font_size("font_size"), "line_count": label.get_line_count()})
	_check(fax.event == event, "production_fax_keeps_event_identity")
	_check(fax.get_node("EventHistoryTab").text == "H296", "production_history_identity")
	if not headless:
		_check(viewport.get_texture().get_image().save_png(output.path_join("production_fax.png")) == OK,
			"production_fax_capture")
	fax.configure({"id": "empty", "title": "", "narrative": ""}, theme)
	_check(fax.get_node("HandwrittenHeadline").text.is_empty(), "production_empty_title")
	_check(fax.get_node("HandwrittenExcerpt").text.is_empty(), "production_empty_body")
	fax.configure({"id": "long", "title": SAMPLES.en.repeat(20), "narrative": SAMPLES.zh.repeat(80)}, theme)
	await _settle()
	_check(fax.event.narrative == SAMPLES.zh.repeat(80), "production_long_text_identity")
	_check(fax.get_node("HandwrittenExcerpt").max_lines_visible <= 12, "production_long_text_bounded")
	report["production_fax"] = evidence
	viewport.queue_free()
	await process_frame

func _render(face: Font, value: String, zoom: float) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 750)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_2d = Viewport.MSAA_4X
	root.add_child(viewport)
	var paper := ColorRect.new()
	paper.color = Color.WHITE
	paper.size = Vector2(1600, 750)
	viewport.add_child(paper)
	var sheet := TextSheet.new()
	sheet.face = face
	sheet.text = value
	viewport.add_child(sheet)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = Vector2.ONE * zoom
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	await _settle()
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image

func _pixel_error(actual: Image, expected: Image, third: Image) -> Dictionary:
	var sum := 0.0
	var squared := 0.0
	var compared := 0
	var maximum := 0.0
	for y in actual.get_height():
		for x in actual.get_width():
			var a := actual.get_pixel(x, y).r
			var b := expected.get_pixel(x, y).r
			if minf(minf(a, b), third.get_pixel(x, y).r) > .99: continue
			var difference := absf(a - b)
			sum += difference
			squared += difference * difference
			maximum = maxf(maximum, difference)
			compared += 1
	return {"ink_pixels": compared, "mean_absolute_error": sum / maxi(1, compared),
		"root_mean_square_error": sqrt(squared / maxi(1, compared)), "maximum_error": maximum}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].is_absolute_path():
		push_error("font_clarity_probe requires an absolute disposable output directory")
		quit(2)
		return
	output = args[0]
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create probe output directory: " + output)
		quit(2)
		return
	headless = DisplayServer.get_name() == "headless"
	source = load(FONT_PATH) as FontVariation
	if source == null or not source.base_font is FontFile:
		push_error("Production font resource is not a FontVariation backed by FontFile")
		quit(2)
		return
	reference = _copy_font(REFERENCE_DENSITY)
	legacy = _copy_font(0.0)
	report = {"engine": Engine.get_version_info(), "headless": headless,
		"renderer": RenderingServer.get_current_rendering_method(), "font": FONT_PATH,
		"configured_oversampling": source.base_font.oversampling,
		"msdf_enabled": source.base_font.multichannel_signed_distance_field,
		"reference_density": REFERENCE_DENSITY, "camera_zooms": CAMERA_ZOOMS}
	_check(not source.base_font.multichannel_signed_distance_field, "bitmap_font_preserved")
	report["actual_atlas"] = _glyph_evidence(source)
	report["reference_atlas"] = _glyph_evidence(reference)
	_check(not report.actual_atlas.is_empty(), "draw_string_populates_raster_cache")
	_check(not report.reference_atlas.is_empty(), "reference_populates_raster_cache")
	_shape_checks()
	await _fax_checks()
	var comparisons: Array = []
	if not headless:
		for zoom: float in CAMERA_ZOOMS:
			for language: String in SAMPLES:
				var actual := await _render(source, SAMPLES[language], zoom)
				var expected := await _render(reference, SAMPLES[language], zoom)
				var default_density := await _render(legacy, SAMPLES[language], zoom)
				var name := "%s_zoom_%.3f" % [language, zoom]
				_check(actual.save_png(output.path_join(name + "_actual.png")) == OK, "capture_actual_" + name)
				_check(expected.save_png(output.path_join(name + "_reference.png")) == OK, "capture_reference_" + name)
				_check(default_density.save_png(output.path_join(name + "_legacy.png")) == OK, "capture_legacy_" + name)
				var comparison := _pixel_error(actual, expected, default_density)
				var legacy_error := _pixel_error(default_density, expected, actual)
				comparison["name"] = name
				comparison["legacy_error"] = legacy_error
				comparison["actual_to_legacy_error_ratio"] = comparison.mean_absolute_error / maxf(.00001, legacy_error.mean_absolute_error)
				comparisons.append(comparison)
				_check(comparison.ink_pixels > 100, "rendered_text_present_" + name)
				if zoom > 1.0:
					_check(comparison.actual_to_legacy_error_ratio <= .7, "magnified_text_reduces_reference_error_" + name)
	report["pixel_comparisons"] = comparisons
	report["checks"] = checks
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var json := JSON.stringify(report, "\t")
	var file := FileAccess.open(output.path_join("font_clarity_report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write font_clarity_report.json")
		quit(2)
		return
	file.store_string(json + "\n")
	file.close()
	print("FONT_CLARITY " + JSON.stringify({"passed": failures.is_empty(), "failures": failures,
		"checks": checks.size(), "headless": headless, "pixel_comparisons": comparisons,
		"configured_oversampling": source.base_font.oversampling,
		"report": output.path_join("font_clarity_report.json")}))
	quit(0 if failures.is_empty() else 1)
