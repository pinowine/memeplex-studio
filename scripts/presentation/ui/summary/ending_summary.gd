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

var _ui: Control
var _snapshot := {}
var _ending := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null: theme = load("res://data/presentation/ui/demo_theme.tres")
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_ui.get_node("Paper/Content/ReturnMenu").pressed.connect(func(): return_menu_requested.emit())
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
	_ui.get_node("Paper/Content/Title").text = DeskLocalization.text("LOC_VICTORY_943874EC")
	_ui.get_node("Paper/Content/Reason").text = DeskLocalization.text(copy[0])
	_ui.get_node("Paper/Content/Verdict/Comment").text = DeskLocalization.text(copy[1])
	_ui.get_node("Paper/Content/ReturnMenu").text = DeskLocalization.text("LOC_RETURN_TO_MAIN_MENU_E34E61A2")
	var world: Dictionary = _snapshot.get("world_competition", {})
	var hour := int(_ending.get("hour", _snapshot.get("hour", 0)))
	var own := float(_ending.get("owned_share", world.get("owned_share", 0))) * 100
	var lineage := float(_ending.get("lineage_share", world.get("lineage_share", 0))) * 100
	var escaped := float(_ending.get("escaped_share", world.get("escaped_share", 0))) * 100
	var variants: Variant = world.get("variants", [])
	var count: int = variants.size() if variants is Array or variants is Dictionary else 0
	_ui.get_node("Paper/Content/Statistics").text = DeskLocalization.text("LOC_HOUR_D_WORLD_POPULATION_D_AUTHOR_OWNERSHIP_877C9AE3") % [hour, int(world.get("world_population", 0)), own, lineage, escaped, count, str(_snapshot.get("meme_points", 0))]
	_layout()

func _layout() -> void:
	if not is_instance_valid(_ui): return
	var paper: Control = _ui.get_node("Paper")
	paper.size = Vector2(minf(680, size.x - 40), minf(565, size.y - 36))
	paper.position = (size - paper.size) * 0.5
	var content: Control = paper.get_node("Content")
	content.size = paper.size - Vector2(96, 84)

func inspection() -> Dictionary:
	return {"visible": is_visible_in_tree(), "ending": _ending.duplicate(true), "snapshot": _snapshot.duplicate(true), "ending_ids": ENDINGS.keys(), "title": "" if not is_instance_valid(_ui) else _ui.get_node("Paper/Content/Title").text, "reason": "" if not is_instance_valid(_ui) else _ui.get_node("Paper/Content/Reason").text, "statistics": "" if not is_instance_valid(_ui) else _ui.get_node("Paper/Content/Statistics").text, "comment": "" if not is_instance_valid(_ui) else _ui.get_node("Paper/Content/Verdict/Comment").text, "scope": "Presentation of confirmed backend victory; no threshold calculation or economy writes"}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
