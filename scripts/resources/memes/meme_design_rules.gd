## 当前模块、语境和传播技能的定义；事件编辑器与模拟层共享奖励校验。
class_name MemeDesignRules
extends Resource

const DEFINITION_VERSION := 7
const EVENT_REWARD_KINDS := ["module", "language", "group", "topic", "stance_token", "pragmatic_token"]
const EVENT_REWARD_LIMIT := 1
const EVENT_REWARD_COUNT := 1

@export var definition_version: int = DEFINITION_VERSION
@export var module_slots: int = 5
@export var starter_presets: PackedStringArray = PackedStringArray()
@export var modules: Array[Dictionary] = []
@export var skills: Array[Dictionary] = []
@export var context_definitions: MemeContextDefinitions
@export var axis_step: float = 0.1
@export var context_depths: PackedFloat32Array = PackedFloat32Array([0.1, 0.3, 0.5, 0.7, 0.9])

func context_resource(id: String) -> Dictionary:
	if context_definitions != null:
		for entry: Dictionary in context_definitions.entries:
			if str(entry.id) == id:
				return entry
	return {}

func event_reward_entries(kind: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if kind == "module":
		return modules
	if context_definitions != null:
		for entry: Dictionary in context_definitions.entries:
			if str(entry.get("kind", "")) == kind:
				entries.append(entry)
	return entries

## 草稿资源和读档记录都走此入口，避免编辑器与领取动作各写一份物品规则。
func validate_event_rewards(rewards: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if rewards.size() > EVENT_REWARD_LIMIT:
		errors.append("design_rewards: events allow at most one physical item")
	for index in rewards.size():
		var reward: Variant = rewards[index]
		if not reward is Dictionary:
			errors.append("design_rewards[%d]: reward must be an object" % index)
			continue
		var kind: String = str(reward.get("kind", ""))
		var count: Variant = reward.get("count")
		if kind not in EVENT_REWARD_KINDS:
			errors.append("design_rewards[%d].kind: unsupported reward kind" % index)
		if not (count is int or count is float) or not is_finite(float(count)) or float(count) != EVENT_REWARD_COUNT:
			errors.append("design_rewards[%d].count: events must award exactly one physical item" % index)
		if not reward.get("id") is String or reward_resource(kind, str(reward.get("id", ""))).is_empty():
			errors.append("design_rewards[%d].id: unknown physical item" % index)
	return errors

func reward_resource(kind: String, id: String) -> Dictionary:
	if kind == "module":
		return find("modules", id)
	var entry := context_resource(id)
	return entry if str(entry.get("kind", "")) == kind else {}

func find(kind: String, id: String) -> Dictionary:
	var values: Array[Dictionary]
	match kind:
		"modules": values = modules
		"skills": values = skills
		_: return {}
	for entry: Dictionary in values:
		if str(entry.get("id", "")) == id:
			return entry
	return {}

func signature() -> String:
	var data := {
		"version": definition_version,
		"module_slots": module_slots,
		"starters": Array(starter_presets),
		"modules": modules,
		"skills": skills,
		"contexts": context_definitions.entries if context_definitions != null else [],
		"axis_step": axis_step,
		"depths": Array(context_depths),
	}
	return JSON.stringify(data, "", true, true).sha256_text()

func validate(catalog: MemeDemoCatalog) -> PackedStringArray:
	var errors := PackedStringArray()
	if catalog == null:
		return PackedStringArray(["Design rules require a catalog"])
	if definition_version != DEFINITION_VERSION or module_slots < 1 or module_slots > 12:
		errors.append("Invalid current design version or finite module slot limit")
	if context_definitions == null:
		errors.append("Missing brain context definitions")
	else:
		errors.append_array(context_definitions.validate(catalog))
	if not is_finite(axis_step) or axis_step < 0.01 or axis_step > 1 or context_depths.size() != 5:
		errors.append("Invalid brain slice limits")
	for depth in context_depths:
		if not is_finite(depth) or depth < 0 or depth > 1:
			errors.append("Invalid brain slice depth")
	for kind in ["modules", "skills"]:
		var seen := {}
		var values: Array[Dictionary] = modules if kind == "modules" else skills
		if values.is_empty():
			errors.append("Empty design collection: " + kind)
		for entry: Dictionary in values:
			var id := str(entry.get("id", ""))
			if id.is_empty() or seen.has(id) or str(entry.get("title", "")).is_empty():
				errors.append("Invalid design ID: " + kind)
			seen[id] = true
	for module in modules:
		if not module.get("content") is String or str(module.content).strip_edges().is_empty() or not module.get("draft_effects") is Array or str(module.get("description", "")).is_empty():
			errors.append("Missing expression patch content or effects")
		else:
			for effect: Variant in module.draft_effects:
				if not effect is Dictionary or str(effect.get("field", "")) not in ["remix_cost", "context_dependency", "language_access", "recognizability"] or not (effect.get("amount") is int or effect.get("amount") is float):
					errors.append("Invalid expression patch effect")
				elif not is_finite(float(effect.amount)) or absf(float(effect.amount)) > 1.0: errors.append("Unbounded expression patch effect")
		var kernel: MemeDemoKernel = null
		for entry in catalog.kernels:
			if str(entry.id) == str(module.get("kernel_id", "")): kernel = entry
		if kernel == null:
			errors.append("Unknown module kernel")
			continue
		var nodes: Variant = module.get("neuron_nodes")
		var edges: Variant = module.get("neuron_edges")
		if not nodes is Array or not edges is Array:
			errors.append("Missing module topology")
			continue
		var node_ids := {}
		for node: Variant in nodes:
			if not node is Dictionary or str(node.get("id", "")).is_empty(): errors.append("Invalid neuron node")
			else: node_ids[str(node.id)] = true
		for slot in kernel.required_slots:
			if not node_ids.has(str(slot)): errors.append("Module topology must preserve kernel slots")
		for edge: Variant in edges:
			if not edge is Dictionary or not node_ids.has(str(edge.get("from", ""))) or not node_ids.has(str(edge.get("to", ""))): errors.append("Invalid neuron edge")
	if starter_presets.size() != 3: errors.append("Exactly three opening choices are required")
	var starter_seen := {}
	for id in starter_presets:
		if starter_seen.has(id) or catalog.find_preset(id) == null: errors.append("Invalid opening preset")
		starter_seen[id] = true
	var skill_ids := {}
	for skill in skills: skill_ids[str(skill.get("id", ""))] = true
	for skill in skills:
		var effects: Variant = skill.get("draft_effects", [])
		if not effects is Array:
			errors.append("Invalid skill draft effects")
		else:
			for effect: Variant in effects:
				if not effect is Dictionary:
					errors.append("Invalid skill draft effect")
					continue
				var amount: Variant = effect.get("amount")
				if not (amount is int or amount is float) or not is_finite(float(amount)) or absf(float(amount)) > 1.0 or str(effect.get("field", "")) not in ["remix_cost", "context_dependency", "language_access", "recognizability"]: errors.append("Skill effects must be finite bounded author fields")
		if skill.get("kind", "") not in ["root", "medium", "carrier", "instance"] or not skill.get("target_ids") is Array or str(skill.get("effect_text", "")).is_empty():
			errors.append("Missing skill layer, targets or effect")
		else:
			for target in skill.target_ids:
				var found := false
				for channel in catalog.channels: found = found or str(channel.id) == str(target)
				if not found: errors.append("Unknown skill channel target")
		if not _integer(skill.get("cost")) or int(skill.cost) < 0 or not skill.get("requires") is Array:
			errors.append("Invalid skill cost or dependencies")
			continue
		for dependency in skill.requires:
			if not dependency is String or not skill_ids.has(dependency) or dependency == str(skill.id): errors.append("Unknown skill dependency")
		if _cycle(str(skill.id), {}, {}): errors.append("Cyclic skill dependency")
	var root := find("skills", "text")
	if root.is_empty() or root.get("cost", -1) != 0 or root.get("requires", ["invalid"]) != []: errors.append("Text skill must be a free root")
	return errors

func _cycle(id: String, visiting: Dictionary, done: Dictionary) -> bool:
	if visiting.has(id): return true
	if done.has(id): return false
	var entry := find("skills", id)
	if not entry.get("requires") is Array: return false
	visiting[id] = true
	for dependency in entry.requires:
		if _cycle(str(dependency), visiting, done): return true
	visiting.erase(id)
	done[id] = true
	return false

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
