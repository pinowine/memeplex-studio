class_name MemeDemoEvent
extends Resource

const ORIGINS := [&"world", &"transmission", &"environment_meme"]
const TRIGGER_MODES := [&"threshold", &"scheduled", &"random", &"periodic"]
const DECAY_MODES := [&"constant", &"linear", &"exponential", &"periodic"]
const DESIGN_RULES = preload("res://data/rules/design_rules.tres")

@export var id: StringName
@export var title: String = ""
@export_multiline var narrative: String = ""
@export_multiline var mentor_comment: String = ""
@export var origin: StringName = &"world"
@export var topic_ids: PackedStringArray = PackedStringArray()
@export var operation_ids: PackedStringArray = PackedStringArray()
@export var external_preset_id: StringName = &""
@export var conditions: Array[MemeDemoCondition] = []
@export var effects: Array[MemeDemoEffect] = []
@export var trigger_mode: StringName = &"scheduled"
@export var start_hour: float = 0.0
@export var weight: float = 1.0
@export var occurrence_chance: float = 1.0
@export var cooldown_hours: float = 0.0
@export var max_occurrences: int = 1
@export var physical_duration_hours: float = 0.0
@export var attention_duration_hours: float = 0.0
@export var attention_decay: StringName = &"constant"
@export var decay_parameter_hours: float = 0.0
@export var discovery_ids: PackedStringArray = PackedStringArray()
@export var evidence_status: StringName = &"design"
@export var design_rewards: Array[Dictionary] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or title.strip_edges().is_empty() or narrative.strip_edges().is_empty():
		errors.append("Event ID, title and narrative are required")
	if "\n" in mentor_comment or "\r" in mentor_comment:
		errors.append("mentor_comment: 67's comment must occupy one line")
	if not origin in ORIGINS:
		errors.append("Unknown event origin: %s" % origin)
	if not trigger_mode in TRIGGER_MODES:
		errors.append("Unknown trigger mode: %s" % trigger_mode)
	if not attention_decay in DECAY_MODES:
		errors.append("Unknown attention decay: %s" % attention_decay)
	if evidence_status != &"design":
		errors.append("Demo events must identify design evidence")
	errors.append_array(DESIGN_RULES.validate_event_rewards(design_rewards))
	if topic_ids.is_empty() or operation_ids.is_empty():
		errors.append("Events require topics and operations")
	if not external_preset_id.is_empty() and (origin != &"environment_meme" or not "emerge" in operation_ids):
		errors.append("external_preset_id: independent presets require environment_meme and emerge")
	_validate_ids(topic_ids, "topic", errors)
	_validate_ids(operation_ids, "operation", errors)
	_validate_ids(discovery_ids, "discovery", errors)
	for field_name in ["start_hour", "weight", "cooldown_hours", "physical_duration_hours", "attention_duration_hours", "decay_parameter_hours"]:
		var number: float = float(get(field_name))
		if not is_finite(number) or number < 0.0:
			errors.append("%s must be finite and nonnegative" % field_name)
	if not is_finite(occurrence_chance) or occurrence_chance < 0.0 or occurrence_chance > 1.0:
		errors.append("Occurrence chance must be in [0, 1]")
	if max_occurrences < 0:
		errors.append("Max occurrences must be nonnegative; 0 means unlimited")
	if trigger_mode == &"periodic" and cooldown_hours <= 0.0:
		errors.append("Periodic triggers require a positive cooldown")
	if attention_decay in [&"exponential", &"periodic"] and decay_parameter_hours <= 0.0:
		errors.append("Exponential or periodic decay requires a positive parameter")
	if trigger_mode == &"threshold" and conditions.is_empty():
		errors.append("Threshold events require a condition")
	for index in conditions.size():
		var condition := conditions[index]
		if condition == null:
			errors.append("conditions[%d]: null condition" % index)
		else:
			for error in condition.validate():
				errors.append("conditions[%d].%s" % [index, error])
	for index in effects.size():
		var effect := effects[index]
		if effect == null:
			errors.append("effects[%d]: null effect" % index)
		else:
			for error in effect.validate():
				errors.append("effects[%d].%s" % [index, error])
	return errors

func effect_summary() -> String:
	var descriptions := PackedStringArray()
	for effect in effects:
		if effect != null:
			descriptions.append(effect.describe())
	if not external_preset_id.is_empty():
		descriptions.append(DeskLocalization.source_format("生成独立环境家族（预设 %s），非玩家归属与控制；争夺现有注意力预算", external_preset_id))
	return DeskLocalization.source_join("；",descriptions)

func design_reward_summary() -> String:
	var parts := PackedStringArray()
	for reward in design_rewards:
		var entry: Dictionary = DESIGN_RULES.reward_resource(str(reward.get("kind", "")), str(reward.get("id", "")))
		parts.append(DeskLocalization.source_format("%s ×%d",[str(entry.get("title",reward.get("id",""))),int(reward.get("count",0))],[0]))
	return DeskLocalization.source_join("、",parts)

func impact_summary(remix_allowed: bool = true) -> String:
	var labels := {"policy":"政治", "cost_of_living":"生活成本", "work":"劳动", "platform_tools":"平台工具", "sport":"体育", "education":"教育", "identity":"身份", "language":"语言", "entertainment":"文化活动", "archive":"档案", "trust":"信任话题", "community":"社群"}
	var parts := PackedStringArray()
	for effect in effects:
		if effect == null: continue
		var arrow := "—" if is_zero_approx(effect.amount) else ("↑" if effect.amount > 0.0 else "↓")
		if absf(effect.amount) >= 0.3: arrow += arrow
		match str(effect.effect_id):
			"attention", "channel_reach":
				for topic in topic_ids:
					var text := DeskLocalization.source_format("%s%s",[str(labels.get(topic,topic)),arrow],[0])
					if not parts.has(text): parts.append(text)
			"trust": parts.append(DeskLocalization.source_format("%s%s",["信任",arrow],[0]))
			"fatigue": parts.append(DeskLocalization.source_format("%s%s",["疲劳",arrow],[0]))
			"adoption": parts.append(DeskLocalization.source_format("%s%s",["采用",arrow],[0]))
			"remix": parts.append("重混↑" if effect.amount > 0.0 and remix_allowed else "重混—")
			"semantic_shift": parts.append(DeskLocalization.source_format("语义偏移→%d%%", roundi(effect.amount * 100.0)))
			"revival": parts.append("疲劳↓" if effect.amount > 0.0 else "疲劳—")
	if not external_preset_id.is_empty() or str(id) == "competitor_birth": parts.append("环境模因↑")
	return DeskLocalization.source_join("  ",parts)

func _validate_ids(values: PackedStringArray, label: String, errors: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for value in values:
		if value.strip_edges().is_empty() or seen.has(value):
			errors.append("%s IDs must be nonempty and unique" % label)
		seen[value] = true
