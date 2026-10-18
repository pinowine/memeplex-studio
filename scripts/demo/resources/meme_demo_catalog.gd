class_name MemeDemoCatalog
extends Resource

const OPERATION_IDS := ["attention_shift", "remix", "platform_change", "emerge", "split", "fatigue", "contest", "amplify", "revive"]
const DESIGN_RULES = preload("res://content/demo/design_rules.tres")

@export var events: Array[MemeDemoEvent] = []
@export var groups: Array[MemeDemoGroup] = []
@export var kernels: Array[MemeDemoKernel] = []
@export var presets: Array[MemeDemoPreset] = []
@export var channels: Array[MemeDemoChannel] = []
@export var topics: PackedStringArray = PackedStringArray()
@export var content_version: int = 1
@export var initial_meme_points: int = 80
@export var first_publish_cost: int = 20
@export var revision_publish_cost: int = 12
@export var event_research_reward: int = 5
@export var adoption_milestone: int = 100
@export var milestone_reward: int = 2
@export var run_hours: int = 48
@export var event_clock: MemeDemoEventClock
@export var gameplay_rules: Resource

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if content_version <= 0:
		errors.append("Content version must be positive")
	for field_name in ["initial_meme_points", "first_publish_cost", "revision_publish_cost", "event_research_reward", "milestone_reward"]:
		if int(get(field_name)) < 0:
			errors.append("%s must be nonnegative" % field_name)
	if adoption_milestone <= 0 or run_hours <= 0:
		errors.append("Adoption milestone and run hours must be positive")
	if event_clock != null:
		for error in event_clock.validate():
			errors.append("event_clock: " + error)
	if gameplay_rules != null:
		errors.append_array(gameplay_rules.validate())
		if run_hours != gameplay_rules.horizon_hours: errors.append("Gameplay horizon must match catalog")
		for event_id in gameplay_rules.event_presets:
			if find_preset(str(gameplay_rules.event_presets[event_id])) == null: errors.append("Unknown competitor preset: " + str(event_id))
	var topic_lookup: Dictionary = {}
	for topic in topics:
		if topic.strip_edges().is_empty() or topic_lookup.has(topic):
			errors.append("Catalog topics must be nonempty and unique")
		topic_lookup[topic] = true
	if topics.is_empty():
		errors.append("Catalog topics cannot be empty")
	var group_lookup := _validate_collection(groups, "group", errors)
	var kernel_lookup := _validate_collection(kernels, "kernel", errors)
	var preset_lookup := _validate_collection(presets, "preset", errors) if not presets.is_empty() else {}
	_validate_collection(channels, "channel", errors)
	_validate_collection(events, "event", errors)
	if gameplay_rules != null:
		var environment_ids := {}
		for event: MemeDemoEvent in events:
			if event != null and event.origin == &"environment_meme": environment_ids[str(event.id)] = true
			if event != null and event.origin == &"environment_meme" and not gameplay_rules.event_presets.has(str(event.id)): errors.append("Environment event lacks a competition source: " + str(event.id))
		for id in gameplay_rules.event_presets:
			if not environment_ids.has(str(id)): errors.append("Competition source references a non-environment event: " + str(id))
	for preset in presets:
		if preset == null:
			continue
		if not kernel_lookup.has(str(preset.kernel_id)):
			errors.append("Preset %s references unknown kernel %s" % [preset.id, preset.kernel_id])
		else:
			for kernel in kernels:
				if kernel != null and kernel.id == preset.kernel_id and kernel.required_slots != preset.required_slots:
					errors.append("Preset %s must preserve its kernel slot IDs" % preset.id)
	for group in groups:
		if group == null:
			continue
		for topic in group.topic_ids:
			if not topic_lookup.has(topic):
				errors.append("Group %s references unknown topic %s" % [group.id, topic])
	for event in events:
		if event == null:
			continue
		if content_version >= 9 and event.design_rewards.size() > 1: errors.append("Event %s has more than one context reward" % event.id)
		for reward in event.design_rewards:
			if content_version >= 9 and reward.get("count",0) != 1: errors.append("Event %s must award exactly one physical item" % event.id)
			if content_version >= 9 and str(reward.get("kind","")) not in ["module","language","group","topic","stance_token","pragmatic_token"]: errors.append("Event %s has a retired culture reward" % event.id)
			if DESIGN_RULES.reward_resource(str(reward.get("kind", "")), str(reward.get("id", ""))).is_empty(): errors.append("Event %s references unknown design reward" % event.id)
		if content_version >= 3 and event.mentor_comment.strip_edges().is_empty():
			errors.append("Event %s mentor_comment: 67's comment is required" % event.id)
		if not event.external_preset_id.is_empty():
			if not preset_lookup.has(str(event.external_preset_id)):
				errors.append("Event %s references unknown external preset %s" % [event.id, event.external_preset_id])
			if event.origin != &"environment_meme" or &"emerge" not in event.operation_ids:
				errors.append("Event %s external preset requires environment_meme and emerge" % event.id)
		for topic in event.topic_ids:
			if not topic_lookup.has(topic):
				errors.append("Event %s references unknown topic %s" % [event.id, topic])
		for operation in event.operation_ids:
			if not operation in OPERATION_IDS:
				errors.append("Event %s references unknown operation %s" % [event.id, operation])
		for discovery in event.discovery_ids:
			if not kernel_lookup.has(discovery):
				errors.append("Event %s references unknown kernel discovery %s" % [event.id, discovery])
		for effect in event.effects:
			if effect == null:
				continue
			for group_id in effect.group_ids:
				if not group_lookup.has(group_id):
					errors.append("Event %s references unknown effect group %s" % [event.id, group_id])
	return errors

func find_preset(preset_id: String) -> MemeDemoPreset:
	for preset in presets:
		if preset != null and str(preset.id) == preset_id:
			return preset
	return null

func _validate_collection(values: Array, kind: String, errors: PackedStringArray) -> Dictionary:
	var lookup: Dictionary = {}
	if values.is_empty():
		errors.append("Catalog %ss cannot be empty" % kind)
	for resource in values:
		if resource == null:
			errors.append("Null %s resource" % kind)
			continue
		var resource_id: String = String(resource.id)
		if lookup.has(resource_id):
			errors.append("Duplicate %s ID: %s" % [kind, resource_id])
		lookup[resource_id] = true
		for error in resource.validate():
			errors.append("%s %s: %s" % [kind, resource_id, error])
	return lookup
