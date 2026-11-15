class_name EndingSummary
extends Control

signal return_menu_requested

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const TEMPLATE = preload("res://scenes/ui/summary/ending_summary.tscn")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const ENDINGS := {
	"viral_icon": ["MM_ENDING_VIRAL_ICON_TITLE", "MM_ENDING_VIRAL_ICON_REASON", "MM_ENDING_VIRAL_ICON_COMMENT"],
	"local_classic": ["MM_ENDING_LOCAL_CLASSIC_TITLE", "MM_ENDING_LOCAL_CLASSIC_REASON", "MM_ENDING_LOCAL_CLASSIC_COMMENT"],
	"balanced_duel": ["MM_ENDING_BALANCED_DUEL_TITLE", "MM_ENDING_BALANCED_DUEL_REASON", "MM_ENDING_BALANCED_DUEL_COMMENT"],
	"successful_adaptation": ["MM_ENDING_SUCCESSFUL_ADAPTATION_TITLE", "MM_ENDING_SUCCESSFUL_ADAPTATION_REASON", "MM_ENDING_SUCCESSFUL_ADAPTATION_COMMENT"],
	"forgotten": ["MM_ENDING_FORGOTTEN_TITLE", "MM_ENDING_FORGOTTEN_REASON", "MM_ENDING_FORGOTTEN_COMMENT"],
	"best_substitute": ["MM_ENDING_BEST_SUBSTITUTE_TITLE", "MM_ENDING_BEST_SUBSTITUTE_REASON", "MM_ENDING_BEST_SUBSTITUTE_COMMENT"],
	"world_extinction": ["MM_ENDING_WORLD_EXTINCTION_TITLE", "MM_ENDING_WORLD_EXTINCTION_REASON", "MM_ENDING_WORLD_EXTINCTION_SCENE"],
	"player_extinction": ["MM_ENDING_PLAYER_EXTINCTION_TITLE", "MM_ENDING_PLAYER_EXTINCTION_REASON", "MM_ENDING_PLAYER_EXTINCTION_SCENE"]
}

const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
const CATALOG = preload("res://data/catalogs/catalog.tres")
const METRIC_KEYS := ["LOC_SUMMARY_HOUR", "LOC_SUMMARY_POPULATION", "MM_ENDING_MEMES", "LOC_SUMMARY_MEME_POINTS"]
const SHARE_KEYS := ["MM_ENDING_CURRENT_ADOPTION", "MM_ENDING_OTHER", "MM_ENDING_UNADOPTED"]
const SHARE_COLORS := [Color("667951"), Color("8b724c"), Color("9a5c45")]

class MetricIcon extends Control:
	var kind := 0
	func _init() -> void:
		custom_minimum_size = Vector2(20,20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var ink := Color("74785e")
		match kind:
			0:
				draw_arc(Vector2(10,10),8,0,TAU,28,ink,1.2,true)
				draw_polyline(PackedVector2Array([Vector2(10,4),Vector2(10,10),Vector2(15,12)]),ink,1.2,true)
			1:
				draw_arc(Vector2(10,10),8,0,TAU,28,ink,1.2,true)
				draw_line(Vector2(2,10),Vector2(18,10),ink,1.2,true)
				_draw_meridian(Vector2(10,10),Vector2(4,8),ink)
			2:
				draw_polyline(PackedVector2Array([Vector2(4,5),Vector2(10,10),Vector2(16,5)]),ink,1.2,true)
				draw_line(Vector2(10,10),Vector2(10,17),ink,1.2,true)
				for point: Vector2 in [Vector2(4,4),Vector2(16,4),Vector2(10,17)]: draw_circle(point,2,ink)
			3:
				draw_arc(Vector2(10,10),8,0,TAU,28,ink,1.2,true)
				draw_polyline(PackedVector2Array([Vector2(5,14),Vector2(5,6),Vector2(10,11),Vector2(15,6),Vector2(15,14)]),ink,1.2,true)
	func _draw_meridian(center: Vector2, radii: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for index in 33:
			var angle := TAU * float(index) / 32.0
			points.append(center + Vector2(cos(angle),sin(angle)) * radii)
		draw_polyline(points,color,1.0,true)

var _ui: Control
var _content: VBoxContainer
var _metrics: Array[Dictionary] = []
var _shares: Array[Dictionary] = []
var _statistics := ""
var _snapshot := {}
var _ending := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null: theme = load("res://data/presentation/ui/demo_theme.tres")
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_content = _ui.get_node("Paper/Scroll/Content")
	_build_statistics()
	Handwriting.apply_to(_ui)
	_content.get_node("ReturnMenu").pressed.connect(func(): return_menu_requested.emit())
	PaperStyle.apply_buttons(_ui)
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
	_content.get_node("Verdict/Comment").text = DeskLocalization.text(copy[2])
	_content.get_node("ReturnMenu").text = DeskLocalization.text("LOC_RETURN_TO_MAIN_MENU_E34E61A2")
	var world: Dictionary = _snapshot.get("world_competition", {})
	var hour := int(_ending.get("hour", _snapshot.get("hour", 0)))
	var focus_meme := str(_ending.get("meme_id", ""))
	if focus_meme.is_empty():
		for variant: Dictionary in world.get("variants", []):
			if str(variant.id) == str(_snapshot.get("current_variant_id", "")): focus_meme = str(variant.meme_id)
	var own := 0.0
	for variant: Dictionary in world.get("variants", []):
		if str(variant.meme_id) == focus_meme: own = float(variant.share) * 100.0
	var unadopted := float(world.get("unadopted_share", 1.0)) * 100
	var others := maxf(0.0, 100.0 - own - unadopted)
	var variants: Variant = world.get("variants", [])
	var count: int = variants.size() if variants is Array or variants is Dictionary else 0
	_statistics = DeskLocalization.text("MM_ENDING_STATISTICS") % [hour, int(world.get("world_population", 0)), count, str(_snapshot.get("meme_points", 0))]
	var values := [str(hour), _group_number(int(world.get("world_population", 0))), str(count), str(_snapshot.get("meme_points", 0))]
	for index in _metrics.size():
		_metrics[index].title.text = DeskLocalization.text(METRIC_KEYS[index])
		_metrics[index].value.text = values[index]
	var has_population: bool = int(world.get("world_population", 0)) > 0
	_content.get_node("Shares").visible = has_population
	var shares := [own, others, unadopted] if has_population else [0.0, 0.0, 0.0]
	for index in _shares.size():
		_shares[index].title.text = DeskLocalization.text(SHARE_KEYS[index])
		_shares[index].value.text = "%.2f%%" % shares[index]
		_shares[index].bar.value = shares[index]
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
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", 2)
		var icon := MetricIcon.new()
		icon.kind = index
		card.add_child(icon)
		var value := _label(24, true)
		card.add_child(value)
		var title := _label(13)
		title.modulate = Color("74785e")
		card.add_child(title)
		_content.get_node("Metrics").add_child(card)
		_metrics.append({"title":title,"value":value})
	for index in SHARE_KEYS.size():
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var heading := HBoxContainer.new()
		var title := _label(15)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := _label(17, true)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		heading.add_child(title)
		heading.add_child(value)
		row.add_child(heading)
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 5
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.show_percentage = false
		bar.step = 0.01
		var background := StyleBoxFlat.new()
		background.bg_color = Color("c9c5ae")
		background.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", background)
		var fill := background.duplicate() as StyleBoxFlat
		fill.bg_color = SHARE_COLORS[index]
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		_content.get_node("Shares").add_child(row)
		_shares.append({"title":title,"value":value,"bar":bar})

func _label(font_size: int, emphasis: bool = false) -> Label:
	font_size = Typography.normalized_size(font_size)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("3f4537"))
	label.add_theme_font_size_override("font_size", font_size)
	label.set_meta("paper_emphasis", emphasis)
	Typography.apply_control(label, Typography.role_for_size(font_size), true)
	return label

func _group_number(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: grouped += " "
		grouped += digits[index]
	return grouped

func _layout() -> void:
	if not is_instance_valid(_ui): return
	var paper: Control = _ui.get_node("Paper")
	paper.size = Vector2(minf(720, size.x - 32), minf(650, size.y - 28))
	paper.position = (size - paper.size) * 0.5
	var scroll: ScrollContainer = paper.get_node("Scroll")
	scroll.size = paper.size - Vector2(64, 56)
	_content.get_node("Metrics").columns = 2 if scroll.size.x < 540 else 4

func inspection() -> Dictionary:
	return {"visible": is_visible_in_tree(), "ending": _ending.duplicate(true), "snapshot": _snapshot.duplicate(true), "ending_ids": ENDINGS.keys(), "title": "" if not is_instance_valid(_ui) else _content.get_node("Title").text, "reason": "" if not is_instance_valid(_ui) else _content.get_node("Reason").text, "statistics": _statistics, "metric_count":_metrics.size(), "share_values":_shares.map(func(row: Dictionary): return row.bar.value), "shares_visible":false if not is_instance_valid(_ui) else _content.get_node("Shares").visible, "scrollable":true, "comment": "" if not is_instance_valid(_ui) else _content.get_node("Verdict/Comment").text, "scope": "Presentation of confirmed independent-meme outcomes"}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
