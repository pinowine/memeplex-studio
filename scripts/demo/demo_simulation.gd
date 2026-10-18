class_name MemeDemoSimulation
extends RefCounted

signal event_raised(event: Dictionary)
signal changed
signal completed(result: Dictionary)

const CompetitionState = preload("res://scripts/demo/meme_competition_state.gd")
const DesignState = preload("res://scripts/demo/meme_design_state.gd")
const LegacyRewards = preload("res://scripts/demo/legacy/meme_design_rewards_v9.gd")
const OLD_DESIGN_RULES = preload("res://content/demo/design_rules_v9.tres")

var catalog: MemeDemoCatalog
var economy := MemeDemoEconomy.new()
var design_state: RefCounted
var hour: int = 0
var run_end_hour: int = 48
var phase: String = "draft"
var speed: int = 0
var resume_speed: int = 1
var seed_value: int = 20261003
var country_id: String = ""
var country_title: String = "未选择投放国家"
var status: String = "先选择国家，再编写并投放模因。人群规模使用合成样本。"
var latest_draft: Dictionary = {}
var families: Dictionary = {}
var variants: Array[Dictionary] = []
var deployments: Array[Dictionary] = []
var group_state: Dictionary = {}
var events: Array[Dictionary] = []
var discoveries: Array[String] = []
var modifiers: Array[Dictionary] = []
var event_counts: Dictionary = {}
var last_event_hours: Dictionary = {}
var pending_events: Array[Dictionary] = []
var active_event: Dictionary = {}
var attention: Dictionary = {"budget":0, "player":0, "external":0, "background":0}
var current_variant_id: String = ""
var draft_distance: float = 0.0
var publish_count: int = 0
var _serial: int = 0
var _rng := RandomNumberGenerator.new()
var _event_clock_arrivals: Dictionary = {}
var _legacy_event_clock := false
var competition: RefCounted
var _legacy_world := false
var _legacy_world_origin: Dictionary = {}

func _init(content: MemeDemoCatalog = null) -> void:
	catalog = content
	design_state = DesignState.new(content)
	competition = CompetitionState.new(content)
	if catalog != null:
		reset(seed_value)

func reset(run_seed: int) -> void:
	seed_value = run_seed
	_rng.seed = run_seed
	hour = 0
	run_end_hour = catalog.run_hours
	resume_speed = 1
	phase = "draft"
	speed = 0
	_serial = 0
	publish_count = 0
	current_variant_id = ""
	draft_distance = 0.0
	latest_draft.clear()
	families.clear()
	variants.clear()
	deployments.clear()
	group_state.clear()
	events.clear()
	discoveries.clear()
	modifiers.clear()
	event_counts.clear()
	last_event_hours.clear()
	pending_events.clear()
	active_event = {}
	_event_clock_arrivals.clear()
	_legacy_event_clock = false
	_legacy_world = catalog.gameplay_rules == null
	_legacy_world_origin.clear()
	if not _legacy_world: competition.reset()
	attention = {"budget":0, "player":0, "external":0, "background":0} if _legacy_world else competition.snapshot(variants,false).attention
	economy.reset(catalog.initial_meme_points)
	design_state.reset()
	for group in catalog.groups:
		group_state[str(group.id)] = {"exposed":0.0, "owned":0.0, "external":0.0, "fatigue":0.0, "trust":0.72}
	status = "新局：%d Meme；模因交易不可用。" % economy.balance
	changed.emit()


func gameplay_mode() -> String:
	return "legacy_sample" if _legacy_world else "world_competition"

func bind_world(world: RefCounted, settings: Resource) -> PackedStringArray:
	if _legacy_world: return PackedStringArray()
	if publish_count > 0: return PackedStringArray(["首发后不能替换世界。"])
	return competition.bind_world(world,settings)

func draft_fitness(draft: Dictionary) -> Dictionary:
	if _legacy_world: return {}
	var data := draft.duplicate(true)
	data.flow_skill_ids = design_state.snapshot().unlocked_skills.duplicate()
	var profile_data: Dictionary = competition.profile(data)
	var countries := {}
	for row: Dictionary in catalog.gameplay_rules.countries: countries[str(row.id)] = competition.fitness(profile_data,str(row.id))
	return {"countries":countries,"profile":profile_data,"evidence_status":"game_policy"}

func advance_active_seconds(delta: float) -> int:
	if _legacy_world or phase != "running" or speed == 0 or not is_finite(delta) or delta <= 0.0: return 0
	var remaining := delta
	var count := 0
	while remaining > 0.0 and phase == "running" and speed > 0:
		var rate: float = catalog.gameplay_rules.hours_per_active_second * speed
		var needed: float = (1.0 - float(competition._state.hour_credit)) / rate
		var used := minf(remaining,needed)
		competition._state.active_seconds += used
		competition._state.hour_credit += used * rate
		remaining -= used
		if float(competition._state.hour_credit) >= 1.0 - 0.0000000001:
			competition._state.hour_credit = 0.0
			if step_hour(): count += 1
		else: break
	return count

func starter_options() -> Array[Dictionary]:
	return design_state.starter_options()

func starter_draft(preset_id: String, base: Dictionary = {}) -> Dictionary:
	if catalog == null or catalog.groups.is_empty() or catalog.channels.is_empty() or catalog.topics.is_empty(): return {}
	if preset_id not in design_state.rules.starter_presets: return {}
	var preset := catalog.find_preset(preset_id)
	if preset == null or catalog.groups.is_empty() or catalog.channels.is_empty(): return {}
	var defaults := {"language_id":str(catalog.groups[0].language_id), "group_id":str(catalog.groups[0].id),
		"channel_id":"local_board" if find_channel("local_board") != null else str(catalog.channels[0].id),
		"political_known":false, "political_position":Vector2.ZERO, "pragmatic_position":Vector2.ZERO,
		"target":preset.title, "remix_cost":0.3, "context_dependency":0.5, "reuse_permission":&"unknown",
		"language_access":0.8, "recognizability":0.8, "topic_ids":PackedStringArray(["cost_of_living"] if "cost_of_living" in catalog.topics else [catalog.topics[0]])}
	defaults.merge(base, true)
	return preset.to_draft(defaults)

func design_action(action: String, params: Dictionary = {}) -> PackedStringArray:
	if phase == "event": return PackedStringArray(["请先确认当前事件。"])
	if action == "choose_starter" and (publish_count > 0 or phase != "draft"):
		return PackedStringArray(["已投放的运行不能重选开局预设。"])
	if action == "choose_starter" and design_state.rules.definition_version >= 5:
		params = params.duplicate(true)
		params.base = _encoded_draft(starter_draft(str(params.get("preset_id",""))))
	if action == "move_module":
		if not params.get("position") is Vector2: return PackedStringArray(["补丁位置需要纸内坐标。"])
		params = params.duplicate(true)
		params.position = _vector_array(params.position)
	if action in ["apply_context", "apply_skill", "take_apply_context", "install_module", "remove_module", "edit_module_content", "install_context", "remove_context", "move_context_axis", "detach_context_layer", "attach_context_layer"]:
		var draft: Variant = params.get("draft")
		if not draft is Dictionary or not draft.get("slots") is Dictionary or not draft.get("political_position") is Vector2 or not draft.get("pragmatic_position") is Vector2:
			return PackedStringArray(["应用固体需要合法的作者草稿。"])
		for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
			if not _number(draft.get(key)): return PackedStringArray(["作者草稿数值类型错误。"])
		var draft_errors := PackedStringArray() if action in ["install_context","remove_context","move_context_axis"] else validate_draft(draft)
		draft_errors.append_array(_core_errors(draft))
		if not draft_errors.is_empty(): return draft_errors
		var encoded: Dictionary = draft.duplicate(true)
		for key in ["political_position", "pragmatic_position"]: encoded[key] = _vector_array(encoded[key])
		for key in ["replaceable_slots", "topic_ids"]:
			if encoded.has(key): encoded[key] = Array(encoded[key])
		params = params.duplicate(true)
		params.erase("draft")
		params.base = encoded
	var errors: PackedStringArray = design_state.perform(action, params)
	if errors.is_empty(): changed.emit()
	return errors

func context_draft() -> Dictionary:
	var draft: Dictionary = design_state.snapshot().context_draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		if draft.has(key): draft[key] = Vector2(draft[key][0], draft[key][1])
	for key in ["replaceable_slots", "topic_ids"]:
		if draft.has(key): draft[key] = PackedStringArray(draft[key])
	return draft

func claim_design_reward(instance_id: String) -> PackedStringArray:
	for event in events:
		if str(event.instance_id) == instance_id:
			var errors: PackedStringArray = design_state.claim_event(event)
			if errors.is_empty(): changed.emit()
			return errors
	return PackedStringArray(["事件实例未登记，不能领取纸奖励。"])

func request_event_material(instance_id: String, kind: String, id: String) -> PackedStringArray:
	for event: Dictionary in events:
		if str(event.instance_id) != instance_id: continue
		if not bool(event.get("acknowledged",false)) and (phase != "event" or str(active_event.get("instance_id","")) != instance_id): return PackedStringArray(["只能搬出当前事件或已归档事件的物资纸片。"])
		var errors: PackedStringArray = design_state.request_event_material(event,kind,id)
		if errors.is_empty(): changed.emit()
		return errors
	return PackedStringArray(["物资纸片没有本局事件来源。"])

func claim_event_material(instance_id: String, kind: String, id: String) -> PackedStringArray:
	return request_event_material(instance_id,kind,id)

func event_materials(design: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if design.is_empty(): design = design_state.snapshot()
	for event: Dictionary in events:
		for reward: Dictionary in event.get("design_rewards",[]):
			var requested := false
			for claim: Dictionary in design.event_material_claims:
				if claim.source_instance_id == str(event.instance_id) and claim.kind == str(reward.kind) and claim.id == str(reward.id): requested = true
			var acknowledged: bool = str(event.instance_id) in design.claimed_events
			var available := 0
			match str(reward.kind):
				"module":
					available = int(design.available_module_inventory.get(str(reward.id),0))
					for installed in design.module_slots:
						if str(installed) == str(reward.id): available -= 1
				"solute": available = int(design.available_solute_inventory.get(str(reward.id),0))
				"solvent": available = int(design.available_solvent_units.get(str(reward.id),0))+int(design.available_solvent_reserve_units.get(str(reward.id),0))
			if str(reward.kind) in ["language","group","topic","stance_token","pragmatic_token"]: available = int(design.available_context_inventory.get(str(reward.id),0))
			var entry: Dictionary = design_state.rules.reward_resource(str(reward.kind),str(reward.id))
			result.append({"instance_id":str(event.instance_id),"kind":str(reward.kind),"id":str(reward.id),"title":str(entry.get("title",reward.id)),"count":int(reward.count),"acknowledged":acknowledged,"requested":requested,"pending":requested and not acknowledged,"claimed":requested and acknowledged,"available":requested and acknowledged and available>0,"source":{"source_instance_id":str(event.instance_id),"definition_id":str(event.definition_id),"preset_id":str(event.get("design_source_preset_id","")),"kind":str(reward.kind),"id":str(reward.id),"count":int(reward.count)}})
	return result

func _core_errors(draft: Dictionary) -> PackedStringArray:
	if catalog.content_version < 6: return PackedStringArray()
	var state: Dictionary = design_state.snapshot()
	if not str(state.core_kernel_id).is_empty() and (str(draft.get("kernel_id", "")) != str(state.core_kernel_id) or str(draft.get("preset_id", "")) != str(state.core_preset_id)):
		return PackedStringArray(["已确认的基模不可重选；表达补丁只修正自己的内容。"])
	return PackedStringArray()

func _encoded_draft(draft: Dictionary) -> Dictionary:
	var encoded := draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		if encoded.get(key) is Vector2: encoded[key] = _vector_array(encoded[key])
	for key in ["replaceable_slots", "topic_ids"]:
		if encoded.has(key): encoded[key] = Array(encoded[key])
	return encoded

func buy_propagation_skill(id: String, draft: Dictionary = {}) -> PackedStringArray:
	if phase == "event": return PackedStringArray(["请先确认当前事件。"])
	var errors: PackedStringArray = design_state.skill_errors(id)
	if not errors.is_empty(): return errors
	var cost: int = int(design_state.rules.find("skills", id).cost)
	var reserve: int = catalog.first_publish_cost if publish_count == 0 else 0
	if economy.balance - cost < reserve:
		return PackedStringArray(["Meme 点数不足，首次投放需预留 %d 点。" % reserve])
	var candidate: RefCounted = DesignState.new(catalog)
	candidate._state = design_state.payload()
	errors = candidate.unlock_skill(id)
	if not errors.is_empty(): return errors
	if draft.is_empty():
		draft = latest_draft.duplicate(true)
		if draft.is_empty() and not str(candidate.snapshot().starter_preset_id).is_empty(): draft = starter_draft(str(candidate.snapshot().starter_preset_id))
	if not draft.is_empty():
		errors = validate_draft(draft)
		errors.append_array(_core_errors(draft))
		if not errors.is_empty(): return errors
		errors = candidate.apply_unlocked(_encoded_draft(draft))
		if not errors.is_empty(): return errors
	elif not candidate.rules.find("skills", id).get("draft_effects", []).is_empty(): return PackedStringArray(["请先确认自己的模因草稿。"])
	if not economy.charge(cost, "技能解锁：" + id, hour): return PackedStringArray(["Meme 点数不足。"])
	design_state = candidate
	changed.emit()
	return errors

func bind_country(id: String, title: String) -> void:
	country_id = id
	country_title = title
	changed.emit()

func _new_id(prefix: String) -> String:
	_serial += 1
	return "%s_%04d" % [prefix, _serial]

func find_kernel(id: String) -> MemeDemoKernel:
	for kernel in catalog.kernels:
		if str(kernel.id) == id:
			return kernel
	return null

func find_channel(id: String) -> MemeDemoChannel:
	for channel in catalog.channels:
		if str(channel.id) == id:
			return channel
	return null

func validate_draft(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var kernel := find_kernel(str(data.get("kernel_id", "")))
	if kernel == null:
		errors.append("基模未登记。")
		return errors
	var preset_id := str(data.get("preset_id", ""))
	if not preset_id.is_empty():
		var preset := catalog.find_preset(preset_id)
		if preset == null:
			errors.append("预设家族未登记。")
		elif preset.kernel_id != kernel.id:
			errors.append("预设家族与基模不匹配。")
	var slots: Dictionary = data.get("slots", {})
	for slot in kernel.required_slots:
		if str(slots.get(slot, "")).strip_edges().is_empty():
			errors.append("缺少语义槽位：" + slot)
	if find_channel(str(data.get("channel_id", ""))) == null:
		errors.append("传播渠道未登记。")
	var group_found := false
	for group in catalog.groups:
		group_found = group_found or str(group.id) == str(data.get("group_id", ""))
	if not group_found and not (not _legacy_world and str(data.get("group_id", "")).is_empty() and not _draft_layer_attached(data,"group")):
		errors.append("首批群体未登记。")
	if str(data.get("target", "")).strip_edges().is_empty():
		errors.append("请填写支持／反对的表态对象。")
	for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
		var number: float = float(data.get(key, -1.0))
		if not is_finite(number) or number < 0.0 or number > 1.0:
			errors.append(key + " 必须在 0—1 范围内。")
	for key in ["political_position", "pragmatic_position"]:
		var position: Vector2 = data.get(key, Vector2.ZERO)
		if not is_finite(position.x) or not is_finite(position.y) or absf(position.x) > 1.0 or absf(position.y) > 1.0:
			errors.append(key + " 坐标超出范围。")
	var replaceable_seen: Dictionary = {}
	for slot in PackedStringArray(data.get("replaceable_slots", [])):
		if slot not in kernel.required_slots: errors.append("可替换槽位未登记：" + slot)
		if replaceable_seen.has(slot): errors.append("可替换槽位重复：" + slot)
		replaceable_seen[slot] = true
	if str(data.get("reuse_permission", "unknown")) not in ["allowed", "conditional", "restricted", "unknown"]:
		errors.append("再利用许可未登记。")
	var topics := PackedStringArray(data.get("topic_ids", []))
	if topics.is_empty() and (_legacy_world or _draft_layer_attached(data,"topics")): errors.append("请至少选择一个话题。")
	for topic in topics:
		if topic not in catalog.topics: errors.append("话题未登记：" + topic)
	return errors

func _draft_layer_attached(data: Dictionary,layer: String) -> bool:
	var flags: Variant = data.get("context_layer_attachment",{})
	return not (flags is Dictionary and flags.get(layer) is bool and flags[layer] == false)

func publish(data: Dictionary) -> PackedStringArray:
	var errors := validate_draft(data)
	errors.append_array(_core_errors(data))
	errors.append_array(design_state.record_errors())
	errors.append_array(design_state.layer_errors(_encoded_draft(data)))
	if not design_state.context_sources_valid(data.get("context_sources", [])): errors.append("固体来源必须来自本局已应用的事件材料。")
	if not design_state.author_marks_valid(data): errors.append("表达补丁与能力记录必须来自本局的作者操作。")
	if not str(design_state.snapshot().starter_preset_id).is_empty() and str(data.get("channel_id", "")) not in design_state.supported_channels():
		errors.append("该渠道支持能力尚未解锁。")
	if phase != "draft":
		errors.append("请先返回创作台，建立自己的新版本。")
	if not _legacy_world and not competition.has_country(country_id): errors.append("投放国家不在当前世界中。")
	if country_id.is_empty():
		errors.append("请先在地图选择投放国家。")
	var cost: int = catalog.first_publish_cost if publish_count == 0 else catalog.revision_publish_cost
	if economy.balance < cost:
		errors.append("Meme 点数不足：需要 %d，当前 %d。" % [cost, economy.balance])
	if not errors.is_empty():
		status = "；".join(errors)
		changed.emit()
		return errors
	# Validate before charging or creating identities.
	economy.charge(cost, "首次投放" if publish_count == 0 else "再创作投放", hour)
	var kernel := find_kernel(str(data.kernel_id))
	var preset_id := str(data.get("preset_id", ""))
	var preset := catalog.find_preset(preset_id)
	var source_presets: Array = [preset.source_record()] if preset != null else []
	var anchor := preset.family_anchor if preset != null else kernel.family_anchor
	var family_id := ""
	var parent_ids: Array[String] = []
	var old := variant_by_id(current_variant_id)
	if not old.is_empty() and old.kernel_id == str(kernel.id) and str(old.get("preset_id", "")) == preset_id:
		family_id = old.family_id
		parent_ids.append(old.id)
	else:
		family_id = _new_id("family")
		families[family_id] = {"id":family_id, "owner":"player", "anchor":anchor, "split_threshold":kernel.split_threshold, "derived_from":[], "preset_id":preset_id, "source_presets":source_presets.duplicate(true)}
	var id := _new_id("variant")
	var text_parts := PackedStringArray()
	for slot in kernel.required_slots:
		text_parts.append(str(data.slots[slot]))
	var text := " / ".join(text_parts)
	variants.append({"id":id, "family_id":family_id, "parent_ids":parent_ids, "origin_ids":[id] if parent_ids.is_empty() else old.origin_ids.duplicate(), "creator":"player", "owned":true, "controlled":true, "text":text, "kernel_id":str(kernel.id), "preset_id":preset_id, "source_presets":source_presets.duplicate(true), "semantic_distance":0.0, "language_id":str(data.language_id), "pragmatic_position":_vector_array(data.pragmatic_position), "political_position":_vector_array(data.political_position) if data.get("political_known", false) else [], "target":str(data.target), "topic_ids":Array(data.get("topic_ids", []))})
	if data.has("context_sources"): variants.back().context_sources = data.context_sources.duplicate(true)
	for field in ["module_patch_record", "skill_effects", "context_layer_record", "context_layer_attachment"]:
		if data.has(field): variants.back()[field] = data[field].duplicate(true)
	if not _legacy_world:
		var profile_draft := data.duplicate(true)
		profile_draft.flow_skill_ids = design_state.snapshot().unlocked_skills.duplicate()
		variants.back().flow_draft = _encoded_draft(profile_draft)
		variants.back().flow_profile = competition.profile(profile_draft)
		competition.register(variants.back(),variants.back().flow_profile,country_id,hour)
	design_state.record_publish(variants.back())
	current_variant_id = id
	latest_draft = data.duplicate(true)
	draft_distance = 0.0
	publish_count += 1
	deployments.append({"id":_new_id("deployment"), "variant_id":id, "country_id":country_id, "group_id":str(data.group_id), "channel_id":str(data.channel_id), "hour":hour})
	phase = "running"
	speed = 1
	status = "已投放到 %s；后续外部版本不能直接编辑。" % country_title
	changed.emit()
	return errors

func begin_revision(draft: Dictionary = {}) -> PackedStringArray:
	if phase == "draft" and draft.is_empty(): return PackedStringArray()
	if phase == "event":
		status = "请先收录／确认当前事件。"
		changed.emit()
		return PackedStringArray([status])
	var authored: Dictionary = latest_draft if draft.is_empty() else draft
	if not authored.is_empty():
		var errors := validate_draft(authored)
		errors.append_array(_core_errors(authored))
		if not errors.is_empty(): return errors
		var candidate: RefCounted = DesignState.new(catalog)
		candidate._state = design_state.payload()
		errors = candidate.apply_unlocked(_encoded_draft(authored), phase != "draft")
		if not errors.is_empty():
			status = "；".join(errors)
			changed.emit()
			return errors
		design_state = candidate
		latest_draft = context_draft()
	if phase == "complete":
		run_end_hour = hour + (48 if _legacy_world and catalog.gameplay_rules != null else catalog.run_hours)
		if not _legacy_world: competition._state.victory = {}
	phase = "draft"
	speed = 0
	status = "创作自己的新版；已流通的外部版本保持不变。"
	changed.emit()
	return PackedStringArray()

func variant_by_id(id: String) -> Dictionary:
	for item in variants:
		if item.id == id:
			return item
	return {}

func set_speed(value: int) -> void:
	speed = clampi(value, 0, 2) if phase == "running" else 0
	changed.emit()

func step_hour() -> bool:
	if phase != "running":
		return false
	hour += 1
	_expire_modifiers()
	if _legacy_world: _spread()
	else: _spread_world()
	_schedule_events()
	_open_next_event()
	if phase == "running" and (hour >= run_end_hour or not _legacy_world and not competition._state.victory.is_empty()):
		_finish()
	changed.emit()
	return true

func _expire_modifiers() -> void:
	for index in range(modifiers.size() - 1, -1, -1):
		if hour >= float(modifiers[index].expires):
			modifiers.remove_at(index)

func _modifier_factor(group_id: String, topics: PackedStringArray) -> float:
	var factor: float = 1.0
	for item in modifiers:
		if not item.groups.is_empty() and group_id not in item.groups:
			continue
		var overlap: bool = item.get("topics", []).is_empty()
		for topic in topics:
			overlap = overlap or topic in item.get("topics", [])
		if not overlap:
			continue
		var elapsed: float = hour - float(item.get("starts", hour))
		var duration: float = maxf(1.0, float(item.expires) - float(item.get("starts", hour)))
		var decay: float = 1.0
		match str(item.get("decay", "constant")):
			"linear": decay = maxf(0.0, 1.0 - elapsed / duration)
			"exponential": decay = exp(-elapsed / maxf(0.01, float(item.get("decay_parameter", duration))))
			"periodic": decay = 0.5 + 0.5 * cos(TAU * elapsed / maxf(1.0, float(item.get("decay_parameter", duration))))
		factor *= maxf(0.05, 1.0 + float(item.amount) * decay)
	return factor

func _affinity(group: MemeDemoGroup, topics: PackedStringArray = PackedStringArray()) -> float:
	var total: float = 0.0
	var selected := topics if not topics.is_empty() else PackedStringArray(latest_draft.get("topic_ids", []))
	for topic in selected:
		var index := group.topic_ids.find(topic)
		total += group.topic_affinities[index] if index >= 0 else 0.08
	return total / maxf(1.0, selected.size())

func _spread() -> void:
	attention = {"budget":0, "player":0, "external":0, "background":0}
	var channel := find_channel(str(latest_draft.get("channel_id", "")))
	if channel == null:
		return
	for group in catalog.groups:
		var id := str(group.id)
		var state: Dictionary = group_state[id]
		var budget := maxi(0, floori(group.sample_size * group.attention_fraction))
		var matched: float = 1.35 if id == str(latest_draft.group_id) else 0.8
		var topics := PackedStringArray(latest_draft.get("topic_ids", []))
		var player_weight: float = maxf(0.02, _affinity(group, topics) * matched * channel.reach_factor * (1.0 - state.fatigue) * _modifier_factor(id, topics))
		var outside_weight: float = 0.0
		var owned_weight: float = 0.0
		var lineage_weight: float = 0.0
		for variant in variants:
			if variant.controlled:
				continue
			var variant_topics := PackedStringArray(variant.get("topic_ids", ["sport"]))
			var weight: float = (0.35 if not variant.origin_ids.is_empty() else 0.65) * _affinity(group, variant_topics) * _modifier_factor(id, variant_topics) * float(variant.get("reuse_factor", 1.0))
			outside_weight += weight
			if not variant.origin_ids.is_empty(): lineage_weight += weight
			if variant.owned: owned_weight += weight
		var denominator: float = player_weight + outside_weight + 1.0
		var player_slots := floori(budget * player_weight / denominator)
		var outside_slots := floori(budget * outside_weight / denominator)
		attention.budget += budget
		attention.player += player_slots
		attention.external += outside_slots
		attention.background += budget - player_slots - outside_slots
		var lineage_share: float = lineage_weight / maxf(0.01, outside_weight)
		var external_lineage := outside_slots * lineage_share
		var unique_new := minf(group.sample_size - state.exposed, player_slots * 0.72 + external_lineage * 0.60)
		state.exposed += maxf(0.0, unique_new)
		var context_access: float = 1.0 if id == str(latest_draft.group_id) else 1.0 - float(latest_draft.context_dependency) * 0.5
		var understanding: float = group.language_access * float(latest_draft.language_access) * group.recognizability * float(latest_draft.recognizability) * context_access
		var available: float = maxf(0.0, state.exposed - state.owned - state.external)
		var adopted := minf(available, unique_new * understanding * state.trust * 0.58)
		var owned_share: float = clampf((player_slots + outside_slots * owned_weight / maxf(0.01, outside_weight)) / maxf(1.0, player_slots + external_lineage), 0.0, 1.0)
		state.owned += adopted * owned_share
		state.external += adopted * (1.0 - owned_share)
		state.fatigue = clampf(state.fatigue + float(player_slots) / maxf(1.0, group.sample_size) * 0.025 - 0.004, 0.0, 1.0)
		group_state[id] = state
	_reward_milestones()

func _spread_world() -> void:
	var factors := {}
	for variant: Dictionary in variants:
		var entry: Dictionary = competition._state.registry[str(variant.id)]
		var group_id: String = str(entry.profile.group_id) if competition.attached(entry.profile,"group") else ""
		var state: Dictionary = group_state.get(group_id,{"trust":0.72,"fatigue":0.0})
		factors[str(variant.id)] = _modifier_factor(group_id,competition.active_topics(entry.profile)) * maxf(0.05,float(state.trust)) * maxf(0.05,1.0-float(state.fatigue))
	competition.step(hour,variants,factors)
	var view: Dictionary = competition.snapshot(variants,false)
	attention = view.attention
	for group: MemeDemoGroup in catalog.groups:
		var state: Dictionary = group_state[str(group.id)]
		state.exposed = group.sample_size * float(view.exposed) / maxf(1.0,view.world_population)
		state.owned = group.sample_size * float(view.owned_adopted) / maxf(1.0,view.world_population)
		state.external = group.sample_size * float(view.lineage_adopted-view.owned_adopted) / maxf(1.0,view.world_population)
		state.external = maxf(0.0,state.external)
		state.fatigue = clampf(float(state.fatigue)+float(attention.player)/maxf(1.0,attention.budget)*catalog.gameplay_rules.fatigue_gain-catalog.gameplay_rules.fatigue_recovery,0.0,1.0)
	_reward_milestones()

func _register_external_world(variant: Dictionary) -> void:
	if _legacy_world: return
	var parent_id: String = str(variant.parent_ids[0]) if not variant.parent_ids.is_empty() else ""
	var profile_data: Dictionary = competition.inherited_profile(variant,parent_id)
	variant.flow_profile = profile_data.duplicate(true)
	var origin: String = str(competition._state.registry.get(parent_id,{}).get("origin_country",""))
	competition.register(variant,profile_data,origin,hour)

func _reward_milestones() -> void:
	var totals := totals_state()
	var milestone_size: int = catalog.adoption_milestone if _legacy_world else maxi(1,floori(competition.snapshot(variants,false).world_population * catalog.gameplay_rules.milestone_population_fraction))
	var milestone := floori(float(totals.owned_adopted) / milestone_size)
	for index in range(1, milestone + 1):
		economy.reward("adoption_%d" % index, catalog.milestone_reward, "作者归属采用里程碑 %d" % (index * milestone_size), hour)

func totals_state() -> Dictionary:
	if not _legacy_world:
		var view: Dictionary = competition.snapshot(variants,false)
		var fatigue := 0.0
		for state: Dictionary in group_state.values(): fatigue += float(state.fatigue)
		return {"exposed":view.exposed,"adopted":view.adopted,"owned_adopted":view.owned_adopted,"lineage_adopted":view.lineage_adopted,"fatigue":fatigue/maxf(1.0,group_state.size())}
	var exposed: float = 0.0
	var owned: float = 0.0
	var external: float = 0.0
	var fatigue: float = 0.0
	for value: Dictionary in group_state.values():
		exposed += value.exposed
		owned += value.owned
		external += value.external
		fatigue += value.fatigue
	return {"exposed":floori(exposed), "adopted":floori(owned + external), "owned_adopted":floori(owned), "lineage_adopted":floori(owned + external), "fatigue":fatigue / maxf(1.0, group_state.size())}

func _condition_passes(condition: MemeDemoCondition) -> bool:
	var totals := totals_state()
	var values := {"hour":hour, "exposed":totals.exposed, "adopted":totals.adopted, "variants":variants.size(), "families":families.size(), "fatigue":totals.fatigue}
	var actual: float = float(values.get(str(condition.field), -INF))
	if not _legacy_world:
		if str(condition.field) == "hour": actual /= catalog.gameplay_rules.event_time_scale
		elif str(condition.field) in ["exposed","adopted"]:
			var sample_total := 0
			for group: MemeDemoGroup in catalog.groups: sample_total += group.sample_size
			actual = actual / maxf(1.0,competition.snapshot(variants,false).world_population) * sample_total
	match str(condition.operator):
		"ge": return actual >= condition.value
		"gt": return actual > condition.value
		"le": return actual <= condition.value
		"lt": return actual < condition.value
		"eq": return is_equal_approx(actual, condition.value)
	return false

func _schedule_events() -> void:
	if event_clock_mode() == "legacy":
		_schedule_legacy_events()
		return
	var arrivals := 0
	for day in floori(float(hour - 1) / 24.0) + 1:
		if not _event_clock_arrivals.has(day):
			_event_clock_arrivals[day] = catalog.event_clock.arrival_hours(seed_value, day)
		for arrival: int in _event_clock_arrivals[day]:
			if arrival <= hour: arrivals += 1
	# Unfulfilled arrivals remain credits; an empty pool never discards them.
	while events.size() < arrivals:
		var pool: Array[MemeDemoEvent] = []
		var total_weight := 0.0
		for definition in catalog.events:
			var id := str(definition.id)
			var count := int(event_counts.get(id, 0))
			if definition.weight <= 0.0 or hour < _event_hours(definition.start_hour):
				continue
			if definition.max_occurrences > 0 and count >= definition.max_occurrences:
				continue
			if last_event_hours.has(id) and hour - float(last_event_hours[id]) < _event_hours(definition.cooldown_hours):
				continue
			if definition.trigger_mode == &"periodic" and count > 0 and hour - float(last_event_hours.get(id, 0)) < maxf(1.0, _event_hours(definition.decay_parameter_hours)):
				continue
			var qualified := true
			for condition in definition.conditions:
				qualified = qualified and _condition_passes(condition)
			if not qualified or _rng.randf() >= definition.occurrence_chance:
				continue
			pool.append(definition)
			total_weight += definition.weight
		if total_weight <= 0.0:
			return
		var choice := _rng.randf() * total_weight
		for definition in pool:
			choice -= definition.weight
			if choice < 0.0:
				_execute_event(definition)
				break

func _schedule_legacy_events() -> void:
	var random_pool: Array[MemeDemoEvent] = []
	var total_weight: float = 0.0
	for definition in catalog.events:
		var id := str(definition.id)
		var count: int = int(event_counts.get(id, 0))
		if definition.weight <= 0.0 or hour < definition.start_hour:
			continue
		if definition.max_occurrences > 0 and count >= definition.max_occurrences:
			continue
		if last_event_hours.has(id) and hour - float(last_event_hours[id]) < definition.cooldown_hours:
			continue
		var qualified := true
		for condition in definition.conditions:
			qualified = qualified and _condition_passes(condition)
		if not qualified:
			continue
		if definition.trigger_mode == &"periodic" and count > 0 and hour - float(last_event_hours.get(id, 0)) < maxf(1.0, definition.decay_parameter_hours):
			continue
		if _rng.randf() >= definition.occurrence_chance:
			continue
		if definition.trigger_mode == &"random":
			random_pool.append(definition)
			total_weight += definition.weight
		else:
			_execute_event(definition)
	if total_weight <= 0.0:
		return
	# Draw at most one random event after filtering the eligible pool.
	var choice: float = _rng.randf() * total_weight
	for definition in random_pool:
		choice -= definition.weight
		if choice < 0.0:
			_execute_event(definition)
			break

func _execute_event(definition: MemeDemoEvent) -> void:
	var id := str(definition.id)
	var event_id := _new_id("event")
	var first_variant: int = variants.size()
	var observed := PackedStringArray()
	for effect in definition.effects:
		observed.append(_apply_effect(effect, event_id, definition))
	if id == "competitor_birth":
		if _legacy_world:
			_spawn_competitor(event_id)
			observed.append("产生一个独立环境模因家族，与玩家共同争夺同一注意力预算。")
		else:
			var preset_event: MemeDemoEvent = definition.duplicate(true)
			preset_event.external_preset_id = StringName(catalog.gameplay_rules.event_presets[id])
			observed.append(_spawn_external_preset(event_id,preset_event))
	elif not definition.external_preset_id.is_empty() and definition.origin == &"environment_meme" and &"emerge" in definition.operation_ids:
		observed.append(_spawn_external_preset(event_id, definition))
	if not _legacy_world and definition.origin == &"environment_meme" and variants.size() == first_variant:
		var independent: MemeDemoEvent = definition.duplicate(true)
		independent.external_preset_id = StringName(catalog.gameplay_rules.event_presets.get(id,"case_w01"))
		observed.append(_spawn_external_preset(event_id,independent))
	if not _legacy_world:
		for index in range(first_variant,variants.size()): _register_external_world(variants[index])
	event_counts[id] = int(event_counts.get(id, 0)) + 1
	last_event_hours[id] = hour
	var record := {"instance_id":event_id, "definition_id":id, "title":definition.title, "narrative":definition.narrative, "impact_text":definition.impact_summary(latest_draft.get("reuse_permission", "unknown") != "restricted"), "mentor_comment":definition.mentor_comment, "effect_text":"\n".join(observed), "origin":str(definition.origin), "hour":hour, "discoveries":Array(definition.discovery_ids), "acknowledged":false, "design_rewards":definition.design_rewards.duplicate(true), "design_source_preset_id":str(definition.external_preset_id), "reward_text":("收录后领取：" + definition.design_reward_summary()) if not definition.design_rewards.is_empty() else ""}
	if not _legacy_world:
		record.competition_variant_ids = []
		for index in range(first_variant,variants.size()): record.competition_variant_ids.append(str(variants[index].id))
	events.append(record)
	pending_events.append(record)

func _event_hours(value: float) -> float:
	return value if _legacy_world else value * catalog.gameplay_rules.event_time_scale

func _apply_effect(effect: MemeDemoEffect, event_id: String, definition: MemeDemoEvent = null) -> String:
	var ids: Array[String] = []
	for group in catalog.groups:
		if effect.group_ids.is_empty() or group.id in effect.group_ids:
			ids.append(str(group.id))
	var scope := "全部合成人群" if effect.group_ids.is_empty() else "、".join(ids)
	var amount: float = effect.amount
	match str(effect.effect_id):
		"attention", "channel_reach":
			modifiers.append({"source":event_id, "amount":amount, "groups":ids, "starts":hour, "expires":hour + maxf(1.0, _event_hours(effect.duration_hours)), "topics":Array(definition.topic_ids) if definition != null else [], "decay":str(definition.attention_decay) if definition != null else "constant", "decay_parameter":_event_hours(definition.decay_parameter_hours) if definition != null else 1.0})
			return "%s：吸引系数 ×%.2f，持续 %.0f 游戏小时；总注意力预算不增加。" % [scope, maxf(0.05, 1.0 + amount), maxf(1.0, _event_hours(effect.duration_hours))]
		"trust", "fatigue":
			var field := str(effect.effect_id)
			var changes := PackedStringArray()
			for id in ids:
				var state: Dictionary = group_state[id]
				var before: float = state[field]
				state[field] = clampf(before + amount, 0.0, 1.0)
				group_state[id] = state
				changes.append("%s %.2f→%.2f" % [id, before, state[field]])
			return ("信任" if field == "trust" else "疲劳") + "：" + "；".join(changes)
		"adoption":
			if not _legacy_world:
				var added_world: int = competition.adoption_pulse(current_variant_id,amount)
				_reward_milestones()
				return "已曝光而未采用者新增采用 %d。" % added_world
			var added: float = 0.0
			for id in ids:
				var state: Dictionary = group_state[id]
				var delta: float = maxf(0.0, state.exposed - state.owned - state.external) * clampf(amount, 0.0, 1.0)
				state.owned += delta
				added += delta
				group_state[id] = state
			_reward_milestones()
			return "%s：已曝光而未采用者中新增采用 %d；未凭空增加曝光。" % [scope, floori(added)]
		"semantic_shift":
			draft_distance = clampf(amount, 0.0, 1.0)
			return "外部改写相对固定家族锚点的语义偏移设为 %.2f；下一次改写按分家规则处理。" % draft_distance
		"remix":
			if amount <= 0.0: return "改写数量为零，不生成版本。"
			if latest_draft.get("reuse_permission", "unknown") == "restricted":
				return "再利用许可受限：这次规范内的重混未产生版本；许可不是对外部世界的强制控制。"
			return _spawn_remix(event_id, ids[0] if not ids.is_empty() else "community", str(definition.id) if definition != null else "")
		"revival":
			for id in ids:
				var state: Dictionary = group_state[id]
				state.fatigue = clampf(state.fatigue - maxf(0.0, amount), 0.0, 1.0)
				group_state[id] = state
			return "%s：疲劳降低 %.2f，旧表达重新进入使用；不恢复对外部分家的控制。" % [scope, maxf(0.0, amount)]
	push_error("Invalid effect reached simulation: " + str(effect.effect_id))
	return "错误：效果未登记。"

func _spawn_remix(event_id: String, creator: String, definition_id: String = "") -> String:
	var parent := variant_by_id(current_variant_id)
	if parent.is_empty():
		return "没有可改写的已投放版本。"
	var family_id: String = parent.family_id
	var split := draft_distance >= float(families[family_id].split_threshold)
	if split:
		var previous := family_id
		family_id = _new_id("family")
		families[family_id] = {"id":family_id, "owner":creator, "anchor":"外部共同体重新解释", "split_threshold":families[previous].split_threshold, "derived_from":[previous], "preset_id":str(parent.get("preset_id", "")), "source_presets":parent.get("source_presets", []).duplicate(true)}
	var id := _new_id("variant")
	var remix_text: String = "群体重写：" + parent.text
	match definition_id:
		"cross_language": remix_text = "Not a privilege, just a daily trip. / 日常通勤不是特权。"
		"platform_tool": remix_text = "用我的日常账单重填这张模板：" + parent.text
		"semantic_split": remix_text = "涨价才是公平：谁用得多，谁就该付得多。"
		"critical_quote": remix_text = "反讽引用：你说这是公平，我看到的是谁被留在站外。"
	var permission_factor: float = 0.6 if str(latest_draft.get("reuse_permission", "unknown")) == "conditional" else 1.0
	var replaceability: float = float(PackedStringArray(latest_draft.get("replaceable_slots", [])).size()) / maxf(1.0, find_kernel(parent.kernel_id).required_slots.size())
	var reuse_factor: float = permission_factor * (0.3 + 0.7 * replaceability) * (1.0 - float(latest_draft.remix_cost) * 0.7) * (1.0 - float(latest_draft.context_dependency) * 0.5)
	variants.append({"id":id, "family_id":family_id, "parent_ids":[parent.id], "origin_ids":parent.origin_ids.duplicate(), "creator":creator, "owned":not split, "controlled":false, "text":remix_text, "kernel_id":parent.kernel_id, "preset_id":str(parent.get("preset_id", "")), "source_presets":parent.get("source_presets", []).duplicate(true), "semantic_distance":draft_distance, "language_id":"mixed", "source_event":event_id, "topic_ids":parent.get("topic_ids", []).duplicate(), "reuse_factor":reuse_factor})
	if parent.has("context_sources"): variants.back().context_sources = parent.context_sources.duplicate(true)
	return "%s %s；版本 %s 由 %s 制作，玩家不可编辑；来源保留。" % ["新家族" if split else "原家族变体", family_id, id, creator]

func _spawn_external_preset(event_id: String, definition: MemeDemoEvent) -> String:
	var preset := catalog.find_preset(str(definition.external_preset_id))
	if preset == null:
		push_error("External preset not registered: " + str(definition.external_preset_id))
		return "错误：外部预设未登记，没有创建家族。"
	var kernel := find_kernel(str(preset.kernel_id))
	var family_id := _new_id("family")
	var id := _new_id("variant")
	var source_presets: Array = [preset.source_record()]
	families[family_id] = {"id":family_id, "owner":"environment", "anchor":preset.family_anchor, "split_threshold":kernel.split_threshold, "derived_from":[], "preset_id":str(preset.id), "source_presets":source_presets.duplicate(true)}
	variants.append({"id":id, "family_id":family_id, "parent_ids":[], "origin_ids":[], "creator":"environment", "owned":false, "controlled":false, "text":" / ".join(preset.default_values), "kernel_id":str(preset.kernel_id), "preset_id":str(preset.id), "source_presets":source_presets.duplicate(true), "semantic_distance":0.0, "language_id":"mixed", "source_event":event_id, "topic_ids":Array(definition.topic_ids)})
	return "%s 正被其他人接续传播；发声者没有署名，你还无法接管它。" % preset.title

func _spawn_competitor(event_id: String) -> void:
	var family_id := _new_id("family")
	families[family_id] = {"id":family_id, "owner":"environment", "anchor":"漏掉一分钟的街角世界", "split_threshold":0.6, "derived_from":[]}
	variants.append({"id":_new_id("variant"), "family_id":family_id, "parent_ids":[], "origin_ids":[], "creator":"environment", "owned":false, "controlled":false, "text":"漏掉一分钟：街角时钟不等人，一群人共同填补消失的那一分钟。", "kernel_id":"shared_world", "semantic_distance":0.0, "language_id":"zh", "source_event":event_id, "topic_ids":["entertainment", "community"]})

func _open_next_event() -> void:
	if pending_events.is_empty():
		return
	active_event = pending_events.pop_front()
	if phase == "running": resume_speed = speed
	phase = "event"
	speed = 0
	status = "事件暂停：叙事描述与实际作用分别显示。"
	event_raised.emit(active_event.duplicate(true))

func acknowledge_event() -> void:
	if phase != "event" or active_event.is_empty():
		return
	var paper := active_event.duplicate(true)
	paper.acknowledged = true
	var design_errors: PackedStringArray = design_state.claim_event(paper)
	if not design_errors.is_empty():
		status = "；".join(design_errors)
		changed.emit()
		return
	var id: String = active_event.instance_id
	if economy.reward("event_" + id, catalog.event_research_reward, "收录传播研究发现", hour):
		for item: String in active_event.discoveries:
			if item not in discoveries:
				discoveries.append(item)
	for event in events:
		if event.instance_id == id:
			event.acknowledged = true
			var definition := _event_definition(str(event.definition_id))
			if definition != null and not event.get("design_rewards",[]).is_empty(): event.reward_text = "已领取：" + _reward_summary(event.design_rewards,event.get("design_reward_version",9) == 8)
	active_event = {}
	phase = "running"
	speed = resume_speed
	_open_next_event()
	if phase == "running" and (hour >= run_end_hour or not _legacy_world and not competition._state.victory.is_empty()):
		_finish()
	changed.emit()

func _finish() -> void:
	phase = "complete"
	speed = 0
	status = "本轮结束：保留作者归属成果，也看见已经脱离控制的来源影响。"
	if not _legacy_world and not competition._state.victory.is_empty(): status = "胜利：" + str(competition._state.victory.id)
	completed.emit(snapshot())

func snapshot() -> Dictionary:
	var state := totals_state()
	state.merge({"hour":hour, "run_end_hour":run_end_hour, "phase":phase, "speed":speed, "resume_speed":resume_speed, "country_id":country_id, "country_title":country_title, "status":status, "families":families.size(), "variants":variants.size(), "events":events.duplicate(true), "lineage":variants.duplicate(true), "discoveries":discoveries.duplicate(), "meme_points":economy.balance, "point_cost":catalog.first_publish_cost if publish_count == 0 else catalog.revision_publish_cost, "economy_log":economy.lines(), "attention_budget":attention.budget, "attention_player":attention.player, "attention_external":attention.external, "attention_background":attention.background, "purchase_system":"not_designed"})
	state.gameplay = {"mode":gameplay_mode(),"day":float(hour)/24.0,"horizon_hours":run_end_hour,"active_seconds":0.0 if _legacy_world else competition._state.active_seconds,"hours_per_active_second":0.0 if _legacy_world else catalog.gameplay_rules.hours_per_active_second}
	if not _legacy_world: state.world_competition = competition.snapshot(variants)
	state.design_state = design_state.snapshot(variants)
	state.design_state.event_materials = event_materials(state.design_state)
	state.event_materials = state.design_state.event_materials.duplicate(true)
	return state

func _vector_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func payload() -> Dictionary:
	var draft := latest_draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		if draft.has(key): draft[key] = _vector_array(draft[key])
	if draft.has("replaceable_slots"): draft.replaceable_slots = Array(draft.replaceable_slots)
	if draft.has("topic_ids"): draft.topic_ids = Array(draft.topic_ids)
	var data := {"save_version":2, "content_version":catalog.content_version, "content_signature":_content_signature(), "seed":seed_value, "rng_state":str(_rng.state), "hour":hour, "run_end_hour":run_end_hour, "phase":phase, "speed":speed, "resume_speed":resume_speed, "country_id":country_id, "country_title":country_title, "status":status, "latest_draft":draft, "families":families.duplicate(true), "variants":variants.duplicate(true), "deployments":deployments.duplicate(true), "group_state":group_state.duplicate(true), "events":events.duplicate(true), "discoveries":discoveries.duplicate(), "modifiers":modifiers.duplicate(true), "event_counts":event_counts.duplicate(), "last_event_hours":last_event_hours.duplicate(), "pending_events":pending_events.duplicate(true), "active_event":active_event.duplicate(true), "attention":attention.duplicate(), "current_variant_id":current_variant_id, "draft_distance":draft_distance, "publish_count":publish_count, "serial":_serial, "economy":economy.payload()}
	data.design_state = design_state.payload()
	if catalog.gameplay_rules != null:
		data.gameplay_mode = gameplay_mode()
		if _legacy_world: data.legacy_world_origin = _legacy_world_origin.duplicate(true)
		else: data.competition_state = competition.payload()
	var precision: Dictionary = {}
	_collect_precision(data, "", precision)
	data.numeric_precision = precision
	return data

func validate_payload(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	data = _decode_precision(data, errors)
	if not errors.is_empty(): return errors
	var signature := str(data.get("content_signature", ""))
	var valid_version: bool = _number(data.get("content_version")) and float(data.content_version) == floorf(float(data.content_version))
	var current: bool = valid_version and int(data.content_version) == catalog.content_version and signature in [_current_content_signature(), _legacy_content_signature()]
	var pre_v11: bool = catalog.content_version >= 10 and valid_version and int(data.content_version) == 9 and signature in [_pre_v11_content_signature(false),_pre_v11_content_signature(true)]
	var pre_design: bool = catalog.content_version >= 5 and valid_version and int(data.content_version) == 4 and signature in [_pre_design_content_signature(false), _pre_design_content_signature(true)]
	var pre_v6: bool = catalog.content_version >= 6 and valid_version and int(data.content_version) == 5 and signature in [_pre_v6_content_signature(false), _pre_v6_content_signature(true)]
	var pre_v8: bool = catalog.content_version >= 7 and valid_version and int(data.content_version) == 6 and signature in [_pre_v8_content_signature(false), _pre_v8_content_signature(true)]
	var pre_v10: bool = catalog.content_version >= 9 and valid_version and int(data.content_version) == 8 and signature in [_pre_v10_content_signature(false), _pre_v10_content_signature(true)]
	var pre_v9: bool = catalog.content_version >= 8 and valid_version and int(data.content_version) == 7 and signature in [_pre_v9_content_signature(false), _pre_v9_content_signature(true)]
	if data.get("save_version", 0) != 2 or not (current or pre_design or pre_v6 or pre_v8 or pre_v9 or pre_v10 or pre_v11):
		errors.append("存档版本或内容版本不匹配。")
	if pre_design or pre_v6: _upgrade_event_reward_records(data, true)
	var numeric := ["seed", "hour", "run_end_hour", "speed", "resume_speed", "draft_distance", "publish_count", "serial"]
	var strings := ["rng_state", "phase", "country_id", "country_title", "status", "current_variant_id"]
	var dictionaries := ["latest_draft", "families", "group_state", "event_counts", "last_event_hours", "active_event", "attention", "economy"]
	var arrays := ["variants", "deployments", "events", "discoveries", "modifiers", "pending_events"]
	for key in numeric:
		if not data.has(key) or not _number(data[key]): errors.append("存档数值类型错误：" + key)
	for key in strings:
		if not data.get(key) is String: errors.append("存档文本类型错误：" + key)
	for key in dictionaries:
		if not data.get(key) is Dictionary: errors.append("存档对象类型错误：" + key)
	for key in arrays:
		if not data.get(key) is Array: errors.append("存档数组类型错误：" + key)
	if not errors.is_empty(): return errors
	var minimum_horizon: int = catalog.run_hours if catalog.gameplay_rules == null or current and data.get("gameplay_mode","") == "world_competition" else 48
	if not str(data.rng_state).is_valid_int() or str(data.phase) not in ["draft", "running", "event", "complete"] or data.hour < 0 or data.hour > data.run_end_hour or data.run_end_hour < minimum_horizon or data.speed < 0 or data.speed > 2 or data.resume_speed < 0 or data.resume_speed > 2:
		errors.append("存档阶段、随机状态或时间非法。")
	var world_mode: bool = current and catalog.gameplay_rules != null and data.get("gameplay_mode","") == "world_competition"
	if current and catalog.gameplay_rules != null and not world_mode and (data.get("gameplay_mode","") != "legacy_sample" or not _valid_legacy_origin(data.get("legacy_world_origin"))): errors.append("旧传播回放缺少认证来源。")
	if world_mode:
		if not data.get("design_state") is Dictionary: errors.append("竞争作者设计记录缺失或类型非法。")
		for key in ["seed","hour","run_end_hour","speed","resume_speed","publish_count","serial"]:
			if not competition._integer(data[key]): errors.append("竞争存档整数非法："+key)
		if not data.get("competition_state") is Dictionary: errors.append("竞争存档缺失。")
		else: errors.append_array(competition.validate_payload(data.competition_state,data.variants,int(data.hour)))
	if data.phase in ["event", "draft", "complete"] and data.speed != 0:
		errors.append("非运行阶段必须暂停。")
	errors.append_array(economy.validate_payload(data.economy))
	for key in ["variants", "deployments", "events", "modifiers", "pending_events"]:
		for entry in data[key]:
			if not entry is Dictionary: errors.append("存档记录类型错误：" + key)
	for item in data.discoveries:
		if not item is String: errors.append("存档发现类型错误。")
	if not errors.is_empty(): return errors
	var legacy_reward_history: bool = int(data.content_version) < 9
	if data.get("design_state") is Dictionary and data.design_state.get("operations") is Array:
		for operation: Variant in data.design_state.operations:
			if operation is Dictionary and str(operation.get("action","")) in ["legacy_import","initialize_context"]: legacy_reward_history = true
	for key in ["events", "pending_events"]:
		for event in data[key]:
			if not event.has_all(["instance_id", "definition_id", "title", "narrative", "effect_text", "origin", "hour", "discoveries", "acknowledged"]) or not event.get("discoveries") is Array or not event.get("acknowledged") is bool:
				errors.append("存档事件记录字段错误。")
			_validate_event_copy(event, errors, int(data.content_version), legacy_reward_history)
	if not data.active_event.is_empty(): _validate_event_copy(data.active_event, errors, int(data.content_version), legacy_reward_history)
	for deployment in data.deployments:
		if not deployment.has_all(["id", "variant_id", "country_id", "group_id", "channel_id", "hour"]): errors.append("存档投放记录字段错误。")
	if not errors.is_empty(): return errors
	var variant_ids: Dictionary = {}
	var variant_order := {}
	# Validate source types before comparing lineage records.
	for family in data.families.values():
		if family is Dictionary: _validate_preset_sources(family, "家族", errors)
	for variant in data.variants:
		_validate_preset_sources(variant, "版本", errors)
	if not errors.is_empty(): return errors
	for family in data.families.values():
		if not family is Dictionary or not family.has_all(["id", "owner", "anchor", "split_threshold", "derived_from"]) or not _number(family.get("split_threshold")) or not family.get("derived_from") is Array:
			errors.append("存档家族字段错误。")
			continue
		var family_preset := catalog.find_preset(str(family.get("preset_id", "")))
		if family_preset != null and family.derived_from.is_empty() and str(family.anchor) != family_preset.family_anchor:
			errors.append("存档预设家族锚点不匹配。")
		for previous in family.derived_from:
			if not data.families.has(previous) or not data.families[previous] is Dictionary:
				errors.append("存档派生家族来源丢失。")
			elif family.get("source_presets", []) != data.families[previous].get("source_presets", []) or str(family.get("preset_id", "")) != str(data.families[previous].get("preset_id", "")):
				errors.append("存档分家未保留原案例来源。")
	for variant in data.variants:
		if not variant.has_all(["id", "family_id", "parent_ids", "origin_ids", "creator", "owned", "controlled", "text", "kernel_id", "semantic_distance", "language_id"]) or not variant.parent_ids is Array or not variant.origin_ids is Array:
			errors.append("存档版本字段错误。")
			continue
		if variant_ids.has(variant.id) or not data.families.has(variant.family_id): errors.append("存档版本身份或家族引用错误。")
		variant_order[variant.id] = variant_ids.size()
		variant_ids[variant.id] = variant
		var variant_preset := catalog.find_preset(str(variant.get("preset_id", "")))
		if variant_preset != null and str(variant.kernel_id) != str(variant_preset.kernel_id): errors.append("存档版本预设与基模不匹配。")
		if data.families.get(variant.family_id) is Dictionary:
			var family: Dictionary = data.families[variant.family_id]
			if variant.get("source_presets", []) != family.get("source_presets", []) or str(variant.get("preset_id", "")) != str(family.get("preset_id", "")):
				errors.append("存档版本与家族案例来源不一致。")
	if not str(data.current_variant_id).is_empty() and not variant_ids.has(data.current_variant_id): errors.append("存档当前版本丢失。")
	for variant in data.variants:
		for parent in variant.get("parent_ids", []):
			if not variant_ids.has(parent):
				errors.append("存档来源版本丢失。")
			elif world_mode and int(variant_order[parent]) >= int(variant_order[variant.id]):
				errors.append("竞争版本只能引用先前存在的父版本。")
			elif variant.get("source_presets", []) != variant_ids[parent].get("source_presets", []) or str(variant.get("preset_id", "")) != str(variant_ids[parent].get("preset_id", "")):
				errors.append("存档派生版本未保留原案例来源。")
		for origin in variant.get("origin_ids", []):
			if not variant_ids.has(origin): errors.append("存档原始版本来源丢失。")
			elif world_mode and (not variant_ids[origin].parent_ids.is_empty() or str(variant_ids[origin].creator) != "player"): errors.append("竞争谱系原始来源必须是作者的真实初始版本。")
	if world_mode and errors.is_empty():
		var source_checker: RefCounted = CompetitionState.new(catalog)
		source_checker._state = data.competition_state.duplicate(true)
		if competition._canonical(data.attention) != competition._canonical(source_checker.snapshot(data.variants,false).attention): errors.append("显示注意力与国家实际分配不一致。")
		for variant: Dictionary in data.variants:
			if not variant.get("owned") is bool or not variant.get("controlled") is bool:
				errors.append("竞争归属与控制权必须分别为布尔值。")
				continue
			if str(variant.creator) == "player" and (not variant.owned or not variant.controlled): errors.append("玩家原始版本不能伪装为外部失控变异。")
			if str(variant.creator) != "player" and variant.controlled: errors.append("外部版本不能伪造玩家控制权。")
			var family: Dictionary = data.families[variant.family_id]
			if not family.owner is String or variant.owned != (str(family.owner) == "player"): errors.append("作者归属与实际家族不一致。")
			if not _number(variant.semantic_distance) or float(variant.semantic_distance) < 0.0 or float(variant.semantic_distance) > 1.0: errors.append("竞争语义偏移非法。")
			if str(variant.creator) != "player":
				if variant.parent_ids.is_empty():
					if not variant.origin_ids.is_empty() or variant.owned: errors.append("独立外部版本不能伪造玩家来源。")
				else:
					var parent: Dictionary = variant_ids[variant.parent_ids[0]]
					if competition._canonical(variant.origin_ids) != competition._canonical(parent.origin_ids): errors.append("变异必须保留真实原始投放来源。")
					var split: bool = float(variant.semantic_distance) >= float(data.families[parent.family_id].split_threshold)
					if split != (str(variant.family_id) != str(parent.family_id)) or variant.owned == split: errors.append("变异归属与固定家族分家规则不一致。")
			var entry: Dictionary = data.competition_state.registry[str(variant.id)]
			if not variant.get("flow_profile") is Dictionary or competition._canonical(variant.flow_profile) != competition._canonical(entry.profile): errors.append("竞争表达配置与版本不匹配。")
			if variant.controlled:
				if not variant.get("flow_draft") is Dictionary:
					errors.append("作者传播配置缺少原始草稿。")
					continue
				var flow_draft: Dictionary = variant.flow_draft
				if not flow_draft.get("slots") is Dictionary or not flow_draft.get("flow_skill_ids") is Array:
					errors.append("作者传播草稿结构非法。")
					continue
				var flow_input: Dictionary = flow_draft.duplicate(true)
				var valid_flow := flow_input.get("political_known") is bool and flow_input.get("topic_ids") is Array and flow_input.get("replaceable_slots") is Array
				for key in ["political_position","pragmatic_position"]:
					if not flow_input.get(key) is Array or flow_input[key].size() != 2 or not _number(flow_input[key][0]) or not _number(flow_input[key][1]): valid_flow = false
					else: flow_input[key] = Vector2(flow_input[key][0],flow_input[key][1])
				for key in ["remix_cost","context_dependency","language_access","recognizability"]:
					if not _number(flow_input.get(key)): valid_flow = false
				if not valid_flow:
					errors.append("作者传播草稿字段类型非法。")
					continue
				errors.append_array(validate_draft(flow_input))
				for skill_id: Variant in flow_draft.flow_skill_ids:
					if skill_id not in data.get("design_state",{}).get("unlocked_skills",[]): errors.append("传播能力没有合法解锁记录。")
				if competition._canonical(competition.profile(flow_draft)) != competition._canonical(entry.profile) or not design_state.author_marks_valid(flow_draft,data.design_state): errors.append("传播配置与作者操作不一致。")
				if str(flow_draft.get("kernel_id","")) != str(variant.kernel_id) or str(flow_draft.get("preset_id","")) != str(variant.get("preset_id","")): errors.append("传播配置不能更换基模或来源。")
			else:
				var parent_id: String = str(variant.parent_ids[0]) if not variant.parent_ids.is_empty() else ""
				if competition._canonical(source_checker.inherited_profile(variant,parent_id)) != competition._canonical(entry.profile): errors.append("外部传播表达与实际来源不一致。")
			if str(variant.get("source_event","")) != "":
				var found := false
				for event: Dictionary in data.events:
					if str(event.instance_id) == str(variant.source_event) and str(variant.id) in event.get("competition_variant_ids",[]): found = true
				if not found: errors.append("竞争出生事件来源丢失。")
		for event: Dictionary in data.events:
			for id in event.get("competition_variant_ids",[]):
				if not variant_ids.has(id) or str(variant_ids[id].get("source_event","")) != str(event.instance_id): errors.append("事件竞争版本引用非法。")
	if data.publish_count > 0:
		var draft: Dictionary = data.latest_draft.duplicate(true)
		for key in ["political_position", "pragmatic_position"]:
			if not draft.get(key) is Array or draft[key].size() != 2 or not _number(draft[key][0]) or not _number(draft[key][1]):
				errors.append("存档立场坐标错误。")
			else: draft[key] = Vector2(draft[key][0], draft[key][1])
		if not draft.get("slots") is Dictionary or not draft.get("topic_ids") is Array:
			errors.append("存档草稿字段错误。")
		if errors.is_empty(): errors.append_array(validate_draft(draft))
		if variant_ids.has(data.current_variant_id) and str(draft.get("preset_id", "")) != str(variant_ids[data.current_variant_id].get("preset_id", "")):
			errors.append("存档当前草稿与版本预设不一致。")
	for group in catalog.groups:
		var id := str(group.id)
		if not data.group_state.has(id) or not data.group_state[id] is Dictionary or not data.group_state[id].has_all(["exposed", "owned", "external", "fatigue", "trust"]):
			errors.append("存档缺少群体 " + id)
			continue
		var state: Dictionary = data.group_state[id]
		var valid := true
		for key in ["exposed", "owned", "external", "fatigue", "trust"]:
			valid = valid and _number(state[key])
		if not valid:
			errors.append("存档群体数值错误。")
			continue
		if state.exposed < 0 or state.exposed > group.sample_size or state.owned < 0 or state.external < 0 or state.owned + state.external > state.exposed + 0.001 or state.fatigue < 0 or state.fatigue > 1 or state.trust < 0 or state.trust > 1:
			errors.append("存档人口状态不守恒。")
	if not data.attention.has_all(["budget", "player", "external", "background"]):
		errors.append("存档缺少注意力预算。")
	else:
		var valid := true
		for key in ["budget", "player", "external", "background"]:
			valid = valid and _number(data.attention[key]) and data.attention[key] >= 0
		if not valid or data.attention.player + data.attention.external + data.attention.background != data.attention.budget: errors.append("存档注意力不守恒。")
	if data.phase == "event" and (data.active_event.is_empty() or not data.active_event.has_all(["instance_id", "discoveries", "title", "narrative", "effect_text"])):
		errors.append("事件暂停缺少当前事件。")
	for modifier in data.modifiers:
		if not modifier.has_all(["source", "amount", "groups", "expires"]) or not _number(modifier.get("amount")) or not _number(modifier.get("expires")) or not modifier.groups is Array: errors.append("存档作用记录错误。")
	for value in data.event_counts.values():
		if not _number(value) or value < 0: errors.append("存档事件计数错误。")
	for value in data.last_event_hours.values():
		if not _number(value): errors.append("存档事件时间错误。")
	if data.has("design_state"):
		if not data.design_state is Dictionary: errors.append("设计存档字段类型错误。")
		else:
			errors.append_array(design_state.validate_payload(data.design_state, data.events, data.variants, data.economy))
			if errors.is_empty() and not design_state.context_sources_valid(data.latest_draft.get("context_sources", []), data.design_state.applied_context_sources): errors.append("当前草稿固体来源不符合已应用记录。")
			if errors.is_empty() and not design_state.author_marks_valid(data.latest_draft, data.design_state): errors.append("当前草稿表达补丁或能力来源与记录不符。")
	else:
		var sources: Variant = data.latest_draft.get("context_sources", [])
		if not sources is Array or not sources.is_empty(): errors.append("无设计记录却声明固体来源。")
	return errors

func _validate_preset_sources(entry: Dictionary, label: String, errors: PackedStringArray) -> void:
	# Legacy records without preset metadata remain valid.
	if not entry.has("preset_id") and not entry.has("source_presets"):
		return
	if not entry.get("preset_id", "") is String or not entry.get("source_presets") is Array:
		errors.append("存档%s预设来源字段类型错误。" % label)
		return
	var preset_id: String = entry.get("preset_id", "")
	var sources: Array = entry.source_presets
	if preset_id.is_empty():
		if not sources.is_empty(): errors.append("存档%s无预设却声明案例来源。" % label)
		return
	var preset := catalog.find_preset(preset_id)
	if preset == null:
		errors.append("存档%s引用未知预设。" % label)
	elif sources.size() != 1 or not sources[0] is Dictionary or sources[0] != preset.source_record():
		errors.append("存档%s案例来源与内容目录不匹配。" % label)

func _collect_precision(value: Variant, path: String, precision: Dictionary) -> void:
	if value is float and is_finite(value) and value != floor(value):
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		precision[path] = bytes.hex_encode()
	elif value is Dictionary:
		for key in value:
			_collect_precision(value[key], path + "/" + str(key).replace("~", "~0").replace("/", "~1"), precision)
	elif value is Array:
		for index in value.size(): _collect_precision(value[index], path + "/" + str(index), precision)

func _decode_precision(data: Dictionary, errors: PackedStringArray) -> Dictionary:
	if not data.get("numeric_precision") is Dictionary:
		errors.append("存档缺少浮点精度记录。")
		return data
	var required: Dictionary = {}
	_collect_precision(data, "", required)
	for path in required:
		if not data.numeric_precision.has(path): errors.append("存档精度记录缺少字段：" + path)
	var seen: Dictionary = {}
	var decoded: Dictionary = _precise_value(data, "", data.numeric_precision, seen, errors)
	for path in data.numeric_precision:
		if not seen.has(path): errors.append("存档精度记录引用未知字段。")
	return decoded

func _precise_value(value: Variant, path: String, precision: Dictionary, seen: Dictionary, errors: PackedStringArray) -> Variant:
	if precision.has(path):
		seen[path] = true
		var hex: Variant = precision[path]
		if not _number(value) or not hex is String or hex.length() != 16 or not hex.is_valid_hex_number(false):
			errors.append("存档浮点精度格式非法：" + path)
			return value
		var exact: float = hex.hex_decode().decode_double(0)
		if not is_finite(exact) or absf(float(value) - exact) > maxf(0.000000001, absf(exact) * 0.00000000000001):
			errors.append("存档浮点精度与数值不一致：" + path)
			return value
		return exact
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:
			copy[key] = value[key] if key == "numeric_precision" else _precise_value(value[key], path + "/" + str(key).replace("~", "~0").replace("/", "~1"), precision, seen, errors)
		return copy
	if value is Array:
		var copy: Array = []
		for index in value.size(): copy.append(_precise_value(value[index], path + "/" + str(index), precision, seen, errors))
		return copy
	return value

func _content_signature() -> String:
	return _legacy_content_signature() if event_clock_mode() == "legacy" else _current_content_signature()

func event_clock_mode() -> String:
	return "legacy" if _legacy_event_clock or catalog.event_clock == null else "bursty_daily"

func _current_content_signature() -> String:
	if catalog.event_clock == null:
		return _legacy_content_signature()
	return JSON.stringify(_resource_data(catalog), "", true, true).sha256_text()

func _legacy_content_signature() -> String:
	var data: Dictionary = _resource_data(catalog)
	# Omit event_clock from legacy signatures; hash all other content fields.
	data.erase("event_clock")
	return JSON.stringify(data, "", true, true).sha256_text()


func _event_definition(id: String) -> MemeDemoEvent:
	for definition in catalog.events:
		if str(definition.id) == id: return definition
	return null

func _pre_design_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _pre_world_data(_resource_data(catalog))
	data.content_version = 4
	if catalog.content_version >= 6: data.first_publish_cost = 20
	if legacy_clock: data.erase("event_clock")
	for event: Dictionary in data.events: event.erase("design_rewards")
	return JSON.stringify(data, "", true, true).sha256_text()

func _pre_v6_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _old_reward_data(_pre_world_data(_resource_data(catalog)))
	data.content_version = 5
	data.first_publish_cost = 20
	if legacy_clock: data.erase("event_clock")
	return JSON.stringify(data, "", true, true).sha256_text()

func _pre_v8_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _old_reward_data(_pre_world_data(_resource_data(catalog)))
	data.content_version = 6
	if legacy_clock: data.erase("event_clock")
	return JSON.stringify(data, "", true, true).sha256_text()

func _pre_v9_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _old_reward_data(_pre_world_data(_resource_data(catalog)))
	data.content_version = 7
	if legacy_clock: data.erase("event_clock")
	return JSON.stringify(data, "", true, true).sha256_text()

func _old_reward_data(data: Dictionary) -> Dictionary:
	for event: Dictionary in data.events: event.design_rewards = LegacyRewards.REWARDS.get(str(event.id),[]).duplicate(true)
	return data

func _pre_v10_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _old_reward_data(_pre_world_data(_resource_data(catalog)))
	data.content_version = 8
	if legacy_clock: data.erase("event_clock")
	return JSON.stringify(data, "", true, true).sha256_text()

func _pre_world_data(data: Dictionary) -> Dictionary:
	data.erase("gameplay_rules")
	if catalog.gameplay_rules != null: data.run_hours = 48
	return data

func _pre_v11_content_signature(legacy_clock: bool) -> String:
	var data: Dictionary = _pre_world_data(_resource_data(catalog))
	data.content_version = 9
	if legacy_clock: data.erase("event_clock")
	return JSON.stringify(data,"",true,true).sha256_text()

func _valid_legacy_origin(origin: Variant) -> bool:
	if not origin is Dictionary or not _number(origin.get("content_version")) or not origin.get("content_signature") is String: return false
	if float(origin.content_version) != floorf(float(origin.content_version)): return false
	var version := int(origin.content_version)
	var signatures: Array = []
	match version:
		4: signatures = [_pre_design_content_signature(false),_pre_design_content_signature(true)]
		5: signatures = [_pre_v6_content_signature(false),_pre_v6_content_signature(true)]
		6: signatures = [_pre_v8_content_signature(false),_pre_v8_content_signature(true)]
		7: signatures = [_pre_v9_content_signature(false),_pre_v9_content_signature(true)]
		8: signatures = [_pre_v10_content_signature(false),_pre_v10_content_signature(true)]
		9: signatures = [_pre_v11_content_signature(false),_pre_v11_content_signature(true)]
	return str(origin.content_signature) in signatures

func _reward_summary(rewards: Array, legacy: bool) -> String:
	var parts := PackedStringArray()
	var rules: Resource = OLD_DESIGN_RULES if legacy else design_state.rules
	for reward: Dictionary in rewards:
		parts.append("%s ×%d" % [str(rules.reward_resource(str(reward.kind),str(reward.id)).get("title",reward.id)),int(reward.count)])
	return "、".join(parts)

func _upgrade_event_reward_records(data: Dictionary, legacy: bool = false) -> void:
	# Migrate only saves with a matching pre-extension content signature.
	for key in ["events", "pending_events"]:
		if data.get(key) is Array:
			for event: Variant in data[key]:
				if event is Dictionary: _upgrade_event_reward(event,legacy)
	if data.get("active_event") is Dictionary and not data.active_event.is_empty(): _upgrade_event_reward(data.active_event,legacy)

func _upgrade_event_reward(event: Dictionary, legacy: bool = false) -> void:
	var definition := _event_definition(str(event.get("definition_id", "")))
	if definition == null: return
	event.design_rewards = LegacyRewards.REWARDS.get(str(definition.id),[]).duplicate(true) if legacy else definition.design_rewards.duplicate(true)
	event.design_source_preset_id = str(definition.external_preset_id)
	event.reward_text = (("已领取：" if event.get("acknowledged", false) else "收录后领取：") + _reward_summary(event.design_rewards,legacy)) if not event.design_rewards.is_empty() else ""

func _resource_data(value: Variant) -> Variant:
	if value is Resource:
		var result: Dictionary = {}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
				if property.name == "gameplay_rules" and value.get(property.name) == null: continue
				result[property.name] = _resource_data(value.get(property.name))
		return result
	if value is Array:
		var items: Array = []
		for item in value: items.append(_resource_data(item))
		return items
	return value

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _validate_event_copy(event: Dictionary, errors: PackedStringArray, save_content_version: int = 9, legacy_reward_history: bool = false) -> void:
	if event.get("design_reward_version",9) != 9 and (event.get("design_reward_version") != 8 or not legacy_reward_history): errors.append("历史奖励标识缺少认证迁移来源。")
	if catalog.content_version >= 5:
		var definition := _event_definition(str(event.get("definition_id", "")))
		if definition == null or not event.get("design_rewards") is Array or not event.get("design_source_preset_id") is String or not event.get("reward_text") is String:
			errors.append("事件物资元数据缺失或类型错误。")
		else:
			var actual := JSON.stringify(JSON.parse_string(JSON.stringify(event.design_rewards)), "", true, true)
			var legacy_reward: bool = save_content_version < 9 or event.get("design_reward_version",9) == 8
			var rewards: Array = LegacyRewards.REWARDS.get(str(definition.id),[]) if legacy_reward else definition.design_rewards
			var expected := JSON.stringify(JSON.parse_string(JSON.stringify(rewards)), "", true, true)
			if actual != expected or event.design_source_preset_id != str(definition.external_preset_id): errors.append("事件物资或预设来源与开发定义不符。")
			var expected_text := (("已领取：" if event.get("acknowledged", false) else "收录后领取：") + _reward_summary(rewards,legacy_reward)) if not rewards.is_empty() else ""
			if event.reward_text != expected_text: errors.append("事件物资文案与真实领取状态不符。")
	for field in ["impact_text", "mentor_comment"]:
		if catalog.content_version >= 3 and not event.has(field):
			errors.append("存档事件文本缺失：" + field)
		elif event.has(field) and not event[field] is String:
			errors.append("存档事件文本类型错误：" + field)
		elif catalog.content_version >= 3 and event.has(field) and str(event[field]).strip_edges().is_empty():
			errors.append("存档事件文本为空：" + field)
	if event.get("mentor_comment") is String and ("\n" in event.mentor_comment or "\r" in event.mentor_comment):
		errors.append("存档67评价不是单行。")

func restore(data: Dictionary) -> PackedStringArray:
	var errors := validate_payload(data)
	if not errors.is_empty(): return errors
	data = _decode_precision(data, errors)
	if catalog.content_version >= 5 and int(data.content_version) == 4 or catalog.content_version >= 6 and int(data.content_version) == 5: _upgrade_event_reward_records(data,true)
	var restored_competition: RefCounted = CompetitionState.new(catalog)
	var restore_world: bool = data.get("gameplay_mode","") == "world_competition"
	if restore_world:
		errors = restored_competition.restore(data.competition_state,data.variants,int(data.hour))
		if not errors.is_empty(): return errors
	var restored_design: RefCounted = DesignState.new(catalog)
	if data.has("design_state"):
		errors = restored_design.restore(data.design_state, data.events, data.variants, data.economy, data.latest_draft)
		if not errors.is_empty(): return errors
	else:
		restored_design.migrate(data.events, data.variants)
		if catalog.content_version >= 9 and not data.latest_draft.is_empty():
			errors = restored_design.initialize_context(data.latest_draft)
			if not errors.is_empty(): return errors
	if catalog.content_version >= 9 and int(data.content_version) < 9:
		for key in ["events","pending_events"]:
			for event: Dictionary in data[key]: event.design_reward_version = 8
		if not data.active_event.is_empty(): data.active_event.design_reward_version = 8
	_legacy_event_clock = catalog.event_clock != null and str(data.content_signature) in [_pre_v11_content_signature(true),_pre_v10_content_signature(true),_legacy_content_signature(), _pre_design_content_signature(true), _pre_v6_content_signature(true), _pre_v8_content_signature(true), _pre_v9_content_signature(true)]
	_legacy_world = not restore_world
	_legacy_world_origin = data.get("legacy_world_origin",{"content_version":int(data.content_version),"content_signature":str(data.content_signature)}).duplicate(true) if _legacy_world else {}
	competition = restored_competition
	seed_value = int(data.seed)
	_rng.seed = seed_value
	_rng.state = int(data.rng_state)
	_event_clock_arrivals.clear()
	hour = int(data.hour)
	run_end_hour = int(data.run_end_hour)
	phase = str(data.phase)
	speed = int(data.speed)
	resume_speed = int(data.resume_speed)
	country_id = str(data.country_id)
	country_title = str(data.country_title)
	status = str(data.status)
	latest_draft = data.latest_draft.duplicate(true)
	if catalog.content_version >= 9 and int(data.content_version) < 9 and not restored_design.snapshot().context_draft.is_empty(): latest_draft = restored_design.snapshot().context_draft.duplicate(true)
	if data.get("design_state") is Dictionary and data.design_state.get("design_version") == 1 and not latest_draft.is_empty():
		var marks: Array = restored_design.legacy_draft_marks()
		if not marks.is_empty(): latest_draft.skill_effects = marks
	for key in ["political_position", "pragmatic_position"]:
		if latest_draft.has(key): latest_draft[key] = Vector2(latest_draft[key][0], latest_draft[key][1])
	if latest_draft.has("replaceable_slots"): latest_draft.replaceable_slots = PackedStringArray(latest_draft.replaceable_slots)
	if latest_draft.has("topic_ids"): latest_draft.topic_ids = PackedStringArray(latest_draft.topic_ids)
	families = data.families.duplicate(true)
	group_state = data.group_state.duplicate(true)
	variants.assign(data.variants)
	deployments.assign(data.deployments)
	events.assign(data.events)
	discoveries.assign(data.discoveries)
	modifiers.assign(data.modifiers)
	event_counts = data.event_counts.duplicate()
	last_event_hours = data.last_event_hours.duplicate()
	pending_events.assign(data.pending_events)
	active_event = data.active_event.duplicate(true)
	attention = data.attention.duplicate()
	current_variant_id = str(data.current_variant_id)
	draft_distance = float(data.draft_distance)
	publish_count = int(data.publish_count)
	_serial = int(data.serial)
	economy.restore(data.economy)
	design_state = restored_design
	changed.emit()
	return errors
