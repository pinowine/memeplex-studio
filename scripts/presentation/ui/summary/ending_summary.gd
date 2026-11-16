class_name EndingSummary
extends Control

signal return_menu_requested

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const TEMPLATE = preload("res://scenes/ui/summary/ending_summary.tscn")
const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const ENDINGS := {
	"viral_icon": ["MM_ENDING_VIRAL_ICON_TITLE", "MM_ENDING_VIRAL_ICON_REASON"],
	"local_classic": ["MM_ENDING_LOCAL_CLASSIC_TITLE", "MM_ENDING_LOCAL_CLASSIC_REASON"],
	"balanced_duel": ["MM_ENDING_BALANCED_DUEL_TITLE", "MM_ENDING_BALANCED_DUEL_REASON"],
	"successful_adaptation": ["MM_ENDING_SUCCESSFUL_ADAPTATION_TITLE", "MM_ENDING_SUCCESSFUL_ADAPTATION_REASON"],
	"forgotten": ["MM_ENDING_FORGOTTEN_TITLE", "MM_ENDING_FORGOTTEN_REASON"],
	"best_substitute": ["MM_ENDING_BEST_SUBSTITUTE_TITLE", "MM_ENDING_BEST_SUBSTITUTE_REASON"],
	"world_extinction": ["MM_ENDING_WORLD_EXTINCTION_TITLE", "MM_ENDING_WORLD_EXTINCTION_REASON"],
	"player_extinction": ["MM_ENDING_PLAYER_EXTINCTION_TITLE", "MM_ENDING_PLAYER_EXTINCTION_REASON"]
}

const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
const CATALOG = preload("res://data/catalogs/catalog.tres")
const METRIC_KEYS := ["LOC_SUMMARY_HOUR", "MM_ENDING_CURRENT_ADOPTION"]

var _ui: Control
var _content: VBoxContainer
var _metrics: Array[Dictionary] = []
var _snapshot := {}
var _ending := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ReceiptUI.create_theme()
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_content = _ui.get_node("Paper/Scroll/Content")
	_build_statistics()
	Typography.apply_control(_content.get_node("Title"), "title")
	Typography.apply_control(_content.get_node("Reason"), "body")
	var button: Button = _ui.get_node("Paper/ReturnMenu")
	ReceiptUI.primary(button)
	button.pressed.connect(func(): return_menu_requested.emit())
	_content.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	resized.connect(_layout)
	hide()

func configure(_options: Dictionary = {}) -> void:
	_layout()

func show_result(snapshot: Dictionary, ending: Dictionary = {}) -> bool:
	var competition: Dictionary = snapshot.get("world_competition", {})
	var result: Dictionary = competition.get("ending", {}) if ending.is_empty() else ending
	if not ENDINGS.has(str(result.get("id", ""))): return false
	_snapshot = snapshot.duplicate(true)
	_ending = result.duplicate(true)
	_refresh()
	show()
	return true

func _refresh() -> void:
	if not is_instance_valid(_ui) or _ending.is_empty(): return
	var copy: Array = ENDINGS[str(_ending.id)]
	_content.get_node("Title").text = DeskLocalization.text(copy[0])
	var reason := DeskLocalization.text(copy[1])
	match str(_ending.id):
		"local_classic", "successful_adaptation": reason = reason % _ending_country_name(str(_ending.get("country_id", "")))
		"balanced_duel": reason = reason % _ending_meme_name(str(_ending.get("other_meme_id", "")))
		"best_substitute": reason = reason % _ending_meme_name(str(_ending.get("meme_id", "")))
	_content.get_node("Reason").text = reason
	_ui.get_node("Paper/ReturnMenu").text = DeskLocalization.text("LOC_RETURN_TO_MAIN_MENU_E34E61A2")
	var world: Dictionary = _snapshot.get("world_competition", {})
	var hour := int(_ending.get("hour", _snapshot.get("hour", 0)))
	var focus_meme := str(_ending.get("meme_id", ""))
	if focus_meme.is_empty():
		for variant: Dictionary in world.get("variants", []):
			if str(variant.id) == str(_snapshot.get("current_variant_id", "")): focus_meme = str(variant.meme_id)
	var own := 0.0
	for variant: Dictionary in world.get("variants", []):
		if str(variant.meme_id) == focus_meme: own = float(variant.share) * 100.0
	var values := [str(hour), "%.2f%%" % own]
	for index in _metrics.size():
		_metrics[index].title.text = DeskLocalization.text(METRIC_KEYS[index])
		_metrics[index].value.text = values[index]
	_metrics[1].row.visible = int(world.get("world_population", 0)) > 0
	_ui.get_node("Paper").receipt_code = "%08d" % posmod((str(_ending.id) + ":" + str(hour)).hash(), 100000000)
	_ui.get_node("Paper").queue_redraw()
	_ui.get_node("Paper/Scroll").scroll_vertical = 0
	_layout()

func _ending_meme_name(meme_id: String) -> String:
	for raw: Dictionary in _snapshot.get("lineage", []):
		if str(raw.meme_id) == meme_id: return Identity.name(CATALOG, raw)
	return DeskLocalization.text("MM_ENDING_TARGET_MEME")

func _ending_country_name(country_id: String) -> String:
	for country: Resource in CATALOG.gameplay_rules.map_settings.countries:
		if str(country.id) == country_id: return DeskLocalization.text(str(country.short_name_key))
	return DeskLocalization.text("MM_ENDING_TARGET_COUNTRY")

func _build_statistics() -> void:
	for index in METRIC_KEYS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var title := _label("table_header")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value := _label("section")
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(title)
		row.add_child(value)
		_content.get_node("Metrics").add_child(row)
		_metrics.append({"row":row, "title":title, "value":value})

func _label(role: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Typography.apply_control(label, role)
	return label

func _layout() -> void:
	if not is_instance_valid(_ui): return
	var paper: Control = _ui.get_node("Paper")
	var scroll: ScrollContainer = paper.get_node("Scroll")
	var button: Button = paper.get_node("ReturnMenu")
	var width := minf(448, size.x - 32)
	scroll.size.x = width - 48
	_content.size.x = scroll.size.x
	var body_height := _content.get_combined_minimum_size().y
	var button_height := button.get_combined_minimum_size().y
	paper.size = Vector2(width, minf(body_height + button_height + 120, size.y - 32))
	paper.position = (size - paper.size) * 0.5
	button.position = Vector2(24, paper.size.y - 72 - button_height)
	button.size = Vector2(width - 48, button_height)
	scroll.size.y = button.position.y - 48

func inspection() -> Dictionary:
	return {"visible":is_visible_in_tree(), "ending":_ending.duplicate(true), "snapshot":_snapshot.duplicate(true),
		"ending_ids":ENDINGS.keys(), "title":"" if not is_instance_valid(_ui) else _content.get_node("Title").text,
		"reason":"" if not is_instance_valid(_ui) else _content.get_node("Reason").text, "metric_count":_metrics.size(),
		"metrics":_metrics.map(func(row: Dictionary): return {"title":row.title.text, "value":row.value.text, "visible":row.row.visible}),
		"scrollable":true}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
