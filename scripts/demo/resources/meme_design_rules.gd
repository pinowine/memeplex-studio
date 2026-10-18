class_name MemeDesignRules
extends Resource

@export var definition_version: int = 1
@export var module_slots: int = 5
@export var bottle_slots: int = 3
@export var starter_presets: PackedStringArray = PackedStringArray()
@export var modules: Array[Dictionary] = []
@export var solute_definitions: Resource
@export var solutes: Array[Dictionary] = []:
	get:
		return solute_definitions.entries if solute_definitions != null else solutes
@export var solvents: Array[Dictionary] = []
@export var skills: Array[Dictionary] = []
@export var initial_solute_count: int = 2
@export var initial_solvent_count: int = 3
@export var reward_solutes: Dictionary = {}
@export var mass_units_per_solute: int = 1000
@export var grinding_distance: float = 1.0
@export var grinding_reversals: int = 3
@export var grinding_stroke_limit: float = 0.35
@export var solvent_dose: int = 1
@export var solubility_caps: Dictionary = {}
@export var liquid_units_per_quarter: int = 250
@export var flask_liquid_capacity_units: int = 4000
@export var neuron_base_volume_units: int = 1000
@export var module_volume_units: int = 250
@export var context_definitions: Resource
@export var axis_step: float = 0.1
@export var context_depths: PackedFloat32Array = PackedFloat32Array([0.1, 0.3, 0.5, 0.7, 0.9])

func context_resource(id: String) -> Dictionary:
	if context_definitions != null:
		for entry: Dictionary in context_definitions.entries:
			if str(entry.id) == id: return entry
	return {}

func reward_resource(kind: String, id: String) -> Dictionary:
	if kind == "module": return find("modules", id)
	if kind in ["solute", "solvent"]: return find("solutes" if kind == "solute" else "solvents", id)
	var entry := context_resource(id)
	return entry if str(entry.get("kind", "")) == kind else {}

func find(kind: String, id: String) -> Dictionary:
	var values: Variant = get(kind)
	if values is Array:
		for entry: Dictionary in values:
			if str(entry.get("id", "")) == id: return entry
	return {}

func signature() -> String:
	var data := {"version":definition_version, "module_slots":module_slots, "bottle_slots":bottle_slots,
		"starters":Array(starter_presets), "modules":modules, "solutes":solutes, "solvents":solvents,
		"skills":skills, "solute_count":initial_solute_count, "solvent_count":initial_solvent_count,
		"rewards":reward_solutes}
	# Preserve the field set used by each rule-signature version.
	if definition_version >= 3:
		data.merge({"mass_units":mass_units_per_solute,"grinding_distance":grinding_distance,
			"grinding_reversals":grinding_reversals,"stroke_limit":grinding_stroke_limit,
			"solvent_dose":solvent_dose,"solubility_caps":solubility_caps})
	if definition_version >= 4:
		data.merge({"liquid_scale":liquid_units_per_quarter,"flask_capacity":flask_liquid_capacity_units,
			"neuron_base_volume":neuron_base_volume_units,"module_volume":module_volume_units})
	if definition_version >= 5:
		data.merge({"contexts":context_definitions.entries if context_definitions != null else [],
			"axis_step":axis_step,
			"depths":Array(context_depths)})
	return JSON.stringify(data, "", true, true).sha256_text()

func validate(catalog: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	if catalog == null: return PackedStringArray(["Design rules require a catalog"])
	if definition_version >= 5:
		if context_definitions == null: errors.append("Missing brain context definitions")
		else: errors.append_array(context_definitions.validate(catalog))
		if not is_finite(axis_step) or axis_step < 0.01 or axis_step > 1 or context_depths.size() != 5: errors.append("Invalid brain slice limits")
		for depth in context_depths:
			if not is_finite(depth) or depth < 0 or depth > 1: errors.append("Invalid brain slice depth")
	if solute_definitions != null: errors.append_array(solute_definitions.validate())
	if definition_version <= 0 or module_slots < 1 or module_slots > 12 or bottle_slots < 1 or bottle_slots > 12:
		errors.append("Invalid design version or finite slot limit")
	if initial_solute_count < 0 or initial_solvent_count < 0: errors.append("Negative initial inventory")
	for kind in ["modules", "solutes", "solvents", "skills"]:
		var seen := {}
		var values: Array = get(kind)
		if values.is_empty(): errors.append("Empty design collection: " + kind)
		for entry: Dictionary in values:
			var id := str(entry.get("id", ""))
			if id.is_empty() or seen.has(id) or str(entry.get("title", "")).is_empty(): errors.append("Invalid design ID: " + kind)
			seen[id] = true
	for module in modules:
		if definition_version >= 2:
			if not module.get("content") is String or str(module.content).strip_edges().is_empty() or not module.get("draft_effects") is Array or str(module.get("description", "")).is_empty():
				errors.append("Missing expression patch content or effects")
			else:
				for effect: Variant in module.draft_effects:
					if not effect is Dictionary or str(effect.get("field", "")) not in ["remix_cost", "context_dependency", "language_access", "recognizability"] or not (effect.get("amount") is int or effect.get("amount") is float):
						errors.append("Invalid expression patch effect")
					elif not is_finite(float(effect.amount)) or absf(float(effect.amount)) > 1.0: errors.append("Unbounded expression patch effect")
		var kernel: Resource = null
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
	for solvent in solvents:
		if not _integer(solvent.get("boiling_order")) or int(solvent.boiling_order) < 1: errors.append("Invalid game boiling order")
		if not _integer(solvent.get("capacity")) or not _integer(solvent.get("initial_count")) or int(solvent.capacity) <= 0 or int(solvent.initial_count) < 0 or int(solvent.initial_count) > int(solvent.capacity): errors.append("Invalid solvent capacity or fill")
	if definition_version >= 3:
		if mass_units_per_solute < 4 or mass_units_per_solute > 1000000 or solvent_dose != 1 or grinding_reversals < 1 or grinding_reversals > 32 or not is_finite(grinding_distance) or grinding_distance <= 0 or not is_finite(grinding_stroke_limit) or grinding_stroke_limit <= 0 or grinding_stroke_limit > grinding_distance:
			errors.append("Invalid finite culture quantities or grinding threshold")
		if solubility_caps.size() != solvents.size(): errors.append("Incomplete solvent compatibility matrix")
		for solvent in solvents:
			var row: Variant = solubility_caps.get(str(solvent.id))
			if not _integer(solvent.get("saturation_units")) or int(solvent.saturation_units) <= 0: errors.append("Invalid solvent saturation limit")
			if not row is Dictionary or row.size() != solutes.size():
				errors.append("Incomplete solute compatibility row")
				continue
			for solute in solutes:
				var cap: Variant = row.get(str(solute.id))
				if not _integer(cap) or int(cap) < 0 or int(cap) > mass_units_per_solute: errors.append("Invalid dissolution capacity")
	if definition_version >= 4:
		if liquid_units_per_quarter < 1 or liquid_units_per_quarter > 250000 or flask_liquid_capacity_units < liquid_units_per_quarter or flask_liquid_capacity_units > 1000000 or neuron_base_volume_units < 1 or neuron_base_volume_units > 1000000 or module_volume_units < 1 or module_volume_units > 1000000:
			errors.append("Invalid continuous liquid or visual volume units")
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
	for origin in reward_solutes:
		if origin not in ["world", "transmission", "environment_meme"] or find("solutes", str(reward_solutes[origin])).is_empty(): errors.append("Invalid paper reward mapping")
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
