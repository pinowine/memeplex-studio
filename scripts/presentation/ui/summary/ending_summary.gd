class_name EndingSummary
extends Control

signal return_menu_requested

const TEMPLATE = preload("res://scenes/ui/summary/ending_summary.tscn")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const ENDINGS := {
	"own_world": ["LOC_YOUR_MEME_HAS_TAKEN_OVER_THE_WORLD_B77F0A22", "LOC_EVERYONE_IS_SAYING_YOUR_WORDS_NOW_PLEASE_41ADB542"],
	"autonomous_lineage": ["LOC_THE_UNCONTROLLED_MUTANT_LINEAGE_IS_SURVIVING_ON_0D828D42", "LOC_IT_S_OUT_OF_YOUR_HANDS_CONGRATULATIONS_C2D7631D"],
	"competitor_equilibrium": ["LOC_YOU_AND_YOUR_COMPETITORS_HAVE_REACHED_EQUILIBRIUM_7117C232", "LOC_NEITHER_SIDE_PRINTED_THE_OTHER_OUT_OF_C3A5D603"],
	"lineage_diversity": ["LOC_MULTIPLE_DISTINCT_VERSIONS_HAVE_SPREAD_TOGETHER_C71AB8B3", "LOC_SEVERAL_DRAFTS_SURVIVED_TOGETHER_APPARENTLY_A_SINGLE_E053C7C9"]
}

const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const METRIC_KEYS := ["HOUR", "POPULATION", "VARIANTS", "MEME_POINTS"]
const SHARE_KEYS := ["OWNED", "LINEAGE", "ESCAPED"]
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
	var result: Dictionary = competition.get("victory", {}) if ending.is_empty() else ending
	if not ENDINGS.has(str(result.get("id", ""))): return false
	_snapshot = snapshot.duplicate(true)
	_ending = result.duplicate(true)
	_refresh()
	show()
	return true

func _refresh() -> void:
	if not is_instance_valid(_ui) or _ending.is_empty(): return
	var copy: Array = ENDINGS[str(_ending.id)]
	_content.get_node("Title").text = DeskLocalization.text("LOC_VICTORY_943874EC")
	_content.get_node("Reason").text = DeskLocalization.text(copy[0])
	_content.get_node("Verdict/Comment").text = DeskLocalization.text(copy[1])
	_content.get_node("ReturnMenu").text = DeskLocalization.text("LOC_RETURN_TO_MAIN_MENU_E34E61A2")
	var world: Dictionary = _snapshot.get("world_competition", {})
	var hour := int(_ending.get("hour", _snapshot.get("hour", 0)))
	var own := float(_ending.get("owned_share", world.get("owned_share", 0))) * 100
	var lineage := float(_ending.get("lineage_share", world.get("lineage_share", 0))) * 100
	var escaped := float(_ending.get("escaped_share", world.get("escaped_share", 0))) * 100
	var variants: Variant = world.get("variants", [])
	var count: int = variants.size() if variants is Array or variants is Dictionary else 0
	_statistics = DeskLocalization.text("LOC_HOUR_D_WORLD_POPULATION_D_AUTHOR_OWNERSHIP_877C9AE3") % [hour, int(world.get("world_population", 0)), own, lineage, escaped, count, str(_snapshot.get("meme_points", 0))]
	var values := [str(hour), _group_number(int(world.get("world_population", 0))), str(count), str(_snapshot.get("meme_points", 0))]
	for index in _metrics.size():
		_metrics[index].title.text = DeskLocalization.text("LOC_SUMMARY_" + METRIC_KEYS[index])
		_metrics[index].value.text = values[index]
	var shares := [own, lineage, escaped]
	for index in _shares.size():
		_shares[index].title.text = DeskLocalization.text("LOC_SUMMARY_" + SHARE_KEYS[index])
		_shares[index].value.text = "%.2f%%" % shares[index]
		_shares[index].bar.value = shares[index]
	_layout()

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
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("3f4537"))
	label.add_theme_font_size_override("font_size", font_size)
	label.set_meta("paper_emphasis", emphasis)
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
	return {"visible": is_visible_in_tree(), "ending": _ending.duplicate(true), "snapshot": _snapshot.duplicate(true), "ending_ids": ENDINGS.keys(), "title": "" if not is_instance_valid(_ui) else _content.get_node("Title").text, "reason": "" if not is_instance_valid(_ui) else _content.get_node("Reason").text, "statistics": _statistics, "metric_count":_metrics.size(), "share_values":_shares.map(func(row: Dictionary): return row.bar.value), "scrollable":true, "comment": "" if not is_instance_valid(_ui) else _content.get_node("Verdict/Comment").text, "scope": "Presentation of confirmed backend victory; no threshold calculation or economy writes"}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
