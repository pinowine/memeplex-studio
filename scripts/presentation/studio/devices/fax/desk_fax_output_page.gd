extends Control

const FiberTexture := preload("res://assets/image/textures/studio/desk/paper_texture.png")
const SOURCE_PIXELS_PER_UNIT := 3.0

class FiberSurface extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		# Sample fibers at a fixed density; paper size never stretches the grain.
		var tile_size := FiberTexture.get_size() / SOURCE_PIXELS_PER_UNIT
		for y in range(ceili(size.y / tile_size.y)):
			for x in range(ceili(size.x / tile_size.x)):
				var origin := Vector2(x, y) * tile_size
				var extent := tile_size.min(size - origin)
				draw_texture_rect_region(FiberTexture, Rect2(origin, extent), Rect2(Vector2.ZERO, extent * SOURCE_PIXELS_PER_UNIT))

class PencilRule extends Control:
	var color := Color("777766")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2(0, .1), Vector2(size.x * .52, -.5), Vector2(size.x, .4)]), color, .7, true)

var event: Dictionary = {}
var _fibers: Control
var _title: Label
var _body: Label
var _rule: Control
var _full_size := Vector2.ZERO
var _feed_progress := 1.0
var _history_tab: Label
var _tab_index := 0
var _delivered := false
var _attachment_start := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout)

func configure(value: Dictionary, ui_theme: Theme) -> void:
	event = value.duplicate(true)
	theme = ui_theme
	if _fibers == null:
		_fibers = FiberSurface.new()
		_fibers.name = "PaperFibers"
		add_child(_fibers)
		_rule = PencilRule.new()
		_rule.name = "PencilRule"
		add_child(_rule)
		_title = Label.new()
		_title.name = "HandwrittenHeadline"
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title.add_theme_font_size_override("font_size", 12)
		_title.add_theme_color_override("font_color", Color("343b32"))
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_title)
		_body = Label.new()
		_body.name = "HandwrittenExcerpt"
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_body.add_theme_font_size_override("font_size", 9)
		_body.add_theme_color_override("font_color", Color("55594c"))
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_body)
	_title.text = DeskLocalization.text(str(event.get("title", "")))
	_body.text = DeskLocalization.text(str(event.get("narrative", "")))
	_layout()

func set_attachment_start(value: float) -> void:
	_attachment_start = maxf(0, value)
	_layout()

func set_feed_geometry(full_size: Vector2, progress: float) -> void:
	_full_size = full_size
	_feed_progress = clampf(progress, 0.0, 1.0)
	size = Vector2(full_size.x, full_size.y * _feed_progress)
	_layout()

func finish_output(index: int) -> void:
	_delivered = true
	_tab_index = index
	clip_contents = false
	if _history_tab == null:
		_history_tab = Label.new()
		_history_tab.name = "EventHistoryTab"
		_history_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_history_tab.add_theme_color_override("font_color", Color("41463a"))
		_history_tab.add_theme_font_size_override("font_size", 10)
		_history_tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_history_tab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_history_tab)
	_history_tab.text = "H%s" % str(event.get("hour", index + 1))
	_layout()

func history_tab_rect() -> Rect2:
	if not _delivered: return Rect2()
	var width := 32.0
	if _history_tab != null:
		width = maxf(width, ceilf(_history_tab.get_theme_font("font").get_string_size(_history_tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _history_tab.get_theme_font_size("font_size")).x) + 8.0)
	return Rect2(Vector2(size.x - 2, 12 + (_tab_index % 10) * 20), Vector2(width, 19))

func _fit_excerpt(label: Label, bounds: Rect2, line_limit: int) -> void:
	var line_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")) + label.get_theme_constant("line_spacing")
	label.max_lines_visible = mini(line_limit, maxi(1, floori(bounds.size.y / maxf(1.0, line_height))))
	label.position = bounds.position
	label.size = bounds.size

func inspection() -> Dictionary:
	return {"node_id": get_instance_id(), "feed_progress": _feed_progress,
		"delivered": _delivered, "tab_rect": history_tab_rect(), "event": event.duplicate(true)}

func _layout() -> void:
	if _fibers == null: return
	var dimensions := _full_size if _full_size != Vector2.ZERO else size
	_fibers.size = dimensions
	_rule.position = Vector2(12, 64)
	_rule.size = Vector2(maxf(0, dimensions.x - 24), 1)
	_fit_excerpt(_title, Rect2(12, 16, maxf(0, dimensions.x - 24), 46), 3)
	_fit_excerpt(_body, Rect2(12, 73, maxf(0, dimensions.x - 24), maxf(0, (_attachment_start - 8 if _attachment_start > 0 else dimensions.y - 19) - 73)), 12)
	if _history_tab != null:
		var tab := history_tab_rect()
		_history_tab.position = tab.position
		_history_tab.size = tab.size
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2(2, 3), size), Color(0, 0, 0, .14))
	draw_rect(Rect2(Vector2.ZERO, size), Color("e7e0c9"))
	if _delivered:
		var tab := history_tab_rect()
		draw_rect(Rect2(tab.position + Vector2(1, 2), tab.size), Color(0, 0, 0, .17))
		draw_rect(tab, Color("cfc39e"))
		draw_line(tab.position + Vector2(3, 1), tab.position + Vector2(3, tab.size.y - 1), Color("9e987e"), .7, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _title != null:
		_title.text = DeskLocalization.text(str(event.get("title","")))
		_body.text = DeskLocalization.text(str(event.get("narrative","")))
		_layout()
