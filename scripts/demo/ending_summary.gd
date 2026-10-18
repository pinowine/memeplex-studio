class_name EndingSummary
extends Control

signal return_menu_requested

const TEMPLATE = preload("res://scenes/demo/v11/ending_summary_ui.tscn")
const PaperStyle = preload("res://scripts/demo/desk_paper_style.gd")
const ENDINGS := {
	"own_world": ["你的模因占据了世界。", "You own the world.", "67：现在大家都在说你的话。请不要把这理解为大家都理解你。", "67: Everyone is saying your words. Do not confuse that with understanding you."],
	"autonomous_lineage": ["失控的突变谱系已经独自生存。", "An autonomous mutant lineage survived.", "67：它不归你管了。恭喜，你终于有了一份不用签字的成果。", "67: You no longer control it. Congratulations on a result that does not require your signature."],
	"competitor_equilibrium": ["你与竞争者的格局达到均衡。", "You reached equilibrium with competitors.", "67：谁也没把谁印没。机器可以休息，意见暂时不必一致。", "67: Nobody printed anyone out of existence. The machines can rest without an agreement."],
	"lineage_diversity": ["多个不同版本共同完成了扩散。", "Distinct versions spread together.", "67：几份稿子一起活下来了。看来统一口径不是唯一的出路。", "67: Several manuscripts survived together. A single voice was not the only way out."]
}

var _ui: Control
var _snapshot := {}
var _ending := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null: theme = load("res://assets/themes/demo_theme.tres")
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
	var english := TranslationServer.get_locale().begins_with("en")
	var copy: Array = ENDINGS[str(_ending.id)]
	_ui.get_node("Paper/Content/Title").text = "Victory" if english else "胜利"
	_ui.get_node("Paper/Content/Reason").text = copy[1 if english else 0]
	_ui.get_node("Paper/Content/Verdict/Comment").text = copy[3 if english else 2]
	_ui.get_node("Paper/Content/ReturnMenu").text = "Return to menu" if english else "返回主菜单"
	var world: Dictionary = _snapshot.get("world_competition", {})
	var hour := int(_ending.get("hour", _snapshot.get("hour", 0)))
	var own := float(_ending.get("owned_share", world.get("owned_share", 0))) * 100
	var lineage := float(_ending.get("lineage_share", world.get("lineage_share", 0))) * 100
	var escaped := float(_ending.get("escaped_share", world.get("escaped_share", 0))) * 100
	var variants: Variant = world.get("variants", [])
	var count: int = variants.size() if variants is Array or variants is Dictionary else 0
	_ui.get_node("Paper/Content/Statistics").text = ("Hour %d · Population %d\nOwned %.2f%% · Lineage %.2f%% · Escaped %.2f%%\nVariants %d · Meme %s" if english else "第 %d 小时 · 世界人口 %d\n作者归属 %.2f%% · 原生谱系 %.2f%% · 外部分家 %.2f%%\n流通版本 %d · Meme %s") % [hour, int(world.get("world_population", 0)), own, lineage, escaped, count, str(_snapshot.get("meme_points", 0))]
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
