class_name MemeDemoSimulation
extends RefCounted

signal event_raised(event: Dictionary)
signal changed
signal completed(result: Dictionary)

const CompetitionState = preload("res://scripts/gameplay/competition/competition_state.gd")
const DesignState = preload("res://scripts/gameplay/design/design_state.gd")
const SaveCodec = preload("res://scripts/services/persistence/save_codec.gd")
const EventScheduler = preload("res://scripts/gameplay/events/event_scheduler.gd")
const EffectRules = preload("res://scripts/gameplay/events/effect_rules.gd")

var catalog: MemeDemoCatalog
var economy := MemeDemoEconomy.new()
var design_state: MemeDemoDesignState
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
var competition: RefCounted

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
	competition.reset()
	attention = competition.snapshot(variants,false).attention
	economy.reset(catalog.initial_meme_points)
	design_state.reset()
	for group in catalog.groups:
		group_state[str(group.id)] = {"exposed":0.0, "owned":0.0, "external":0.0, "fatigue":0.0, "trust":0.72}
	status = DeskLocalization.source_format("新局：%d Meme；模因交易不可用。", economy.balance)
	changed.emit()


func gameplay_mode() -> String:
	return "world_competition"

func bind_world(world: RefCounted, settings: Resource) -> PackedStringArray:
	if publish_count > 0: return PackedStringArray(["首发后不能替换世界。"])
	return competition.bind_world(world,settings)

func draft_fitness(draft: Dictionary) -> Dictionary:
	var data := draft.duplicate(true)
	data.flow_skill_ids = design_state.snapshot().unlocked_skills.duplicate()
	var profile_data: Dictionary = competition.profile(data)
	var countries := {}
	for row: Dictionary in catalog.gameplay_rules.countries: countries[str(row.id)] = competition.fitness(profile_data,str(row.id))
	return {"countries":countries,"profile":profile_data,"evidence_status":"game_policy"}

func _required_context_errors() -> PackedStringArray:
	return design_state.required_context_errors()

func advance_active_seconds(delta: float) -> int:
	if phase != "running" or speed == 0 or not is_finite(delta) or delta <= 0.0: return 0
	if not _required_context_errors().is_empty(): return 0
	var remaining_seconds := delta
	var advanced_hours := 0
	while remaining_seconds > 0.0 and phase == "running" and speed > 0:
		var hours_per_second: float = catalog.gameplay_rules.hours_per_active_second * speed
		var seconds_to_next_hour: float = (1.0 - float(competition._state.hour_credit)) / hours_per_second
		var elapsed_seconds := minf(remaining_seconds,seconds_to_next_hour)
		competition._state.active_seconds += elapsed_seconds
		competition._state.hour_credit += elapsed_seconds * hours_per_second
		remaining_seconds -= elapsed_seconds
		if float(competition._state.hour_credit) >= 1.0 - 0.0000000001:
			competition._state.hour_credit = 0.0
			if step_hour(): advanced_hours += 1
		else: break
	return advanced_hours

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
	if action == "choose_starter":
		params = params.duplicate(true)
		params.base = _encoded_draft(starter_draft(str(params.get("preset_id",""))))
	if action == "move_module":
		if not params.get("position") is Vector2: return PackedStringArray(["补丁位置需要纸内坐标。"])
		params = params.duplicate(true)
		params.position = _vector_array(params.position)
	if action in ["apply_skill", "install_module", "remove_module", "edit_module_content", "install_context", "remove_context", "move_context_axis", "detach_context_layer", "attach_context_layer"]:
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
			if str(reward.kind) in ["language","group","topic","stance_token","pragmatic_token"]: available = int(design.available_context_inventory.get(str(reward.id),0))
			var entry: Dictionary = design_state.rules.reward_resource(str(reward.kind),str(reward.id))
			result.append({"instance_id":str(event.instance_id),"kind":str(reward.kind),"id":str(reward.id),"title":str(entry.get("title",reward.id)),"count":int(reward.count),"acknowledged":acknowledged,"requested":requested,"pending":requested and not acknowledged,"claimed":requested and acknowledged,"available":requested and acknowledged and available>0,"source":{"source_instance_id":str(event.instance_id),"definition_id":str(event.definition_id),"preset_id":str(event.get("design_source_preset_id","")),"kind":str(reward.kind),"id":str(reward.id),"count":int(reward.count)}})
	return result

func _core_errors(draft: Dictionary) -> PackedStringArray:
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
		return PackedStringArray([DeskLocalization.source_format("Meme 点数不足，首次投放需预留 %d 点。", reserve)])
	var candidate: MemeDemoDesignState = DesignState.new(catalog)
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
	if not group_found and not (str(data.get("group_id", "")).is_empty() and not _draft_layer_attached(data,"group")):
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
	if topics.is_empty() and _draft_layer_attached(data,"topics"): errors.append("请至少选择一个话题。")
	for topic in topics:
		if topic not in catalog.topics: errors.append("话题未登记：" + topic)
	return errors

func _draft_layer_attached(data: Dictionary,layer: String) -> bool:
	var flags: Variant = data.get("context_layer_attachment",{})
	return not (flags is Dictionary and flags.get(layer) is bool and flags[layer] == false)

## 校验来源、语境和费用后投放；外部版本不获得作者控制权。
func publish(data: Dictionary) -> PackedStringArray:
	var errors := validate_draft(data)
	errors.append_array(_required_context_errors())
	errors.append_array(_core_errors(data))
	errors.append_array(design_state.record_errors())
	errors.append_array(design_state.layer_errors(_encoded_draft(data)))
	if not design_state.author_marks_valid(data): errors.append("表达补丁与能力记录必须来自本局的作者操作。")
	if not str(design_state.snapshot().starter_preset_id).is_empty() and str(data.get("channel_id", "")) not in design_state.supported_channels():
		errors.append("该渠道支持能力尚未解锁。")
	if phase != "draft":
		errors.append("请先返回创作台，建立自己的新版本。")
	if not competition.has_country(country_id): errors.append("投放国家不在当前世界中。")
	if country_id.is_empty():
		errors.append("请先在地图选择投放国家。")
	var cost: int = catalog.first_publish_cost if publish_count == 0 else catalog.revision_publish_cost
	if economy.balance < cost:
		errors.append(DeskLocalization.source_format("Meme 点数不足：需要 %d，当前 %d。", [cost, economy.balance]))
	if not errors.is_empty():
		status = DeskLocalization.source_join("；",errors)
		changed.emit()
		return errors
	# 校验通过后才扣款并创建身份。
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
	for field in ["module_patch_record", "skill_effects", "context_layer_record", "context_layer_attachment"]:
		if data.has(field): variants.back()[field] = data[field].duplicate(true)
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
	status = DeskLocalization.source_format("已投放到 %s；后续外部版本不能直接编辑。", country_title, [0])
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
		var candidate: MemeDemoDesignState = DesignState.new(catalog)
		candidate._state = design_state.payload()
		errors = candidate.apply_unlocked(_encoded_draft(authored), phase != "draft")
		if not errors.is_empty():
			status = DeskLocalization.source_join("；",errors)
			changed.emit()
			return errors
		design_state = candidate
		latest_draft = context_draft()
	if phase == "complete":
		run_end_hour = hour + catalog.run_hours
		competition._state.victory = {}
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
	if not _required_context_errors().is_empty(): return false
	hour += 1
	_expire_modifiers()
	_spread_world()
	_schedule_events()
	_open_next_event()
	if phase == "running" and (hour >= run_end_hour or not competition._state.victory.is_empty()):
		_finish()
	changed.emit()
	return true

func _expire_modifiers() -> void:
	for index in range(modifiers.size() - 1, -1, -1):
		if hour >= float(modifiers[index].expires):
			modifiers.remove_at(index)

func _spread_world() -> void:
	var factors := {}
	for variant: Dictionary in variants:
		var entry: Dictionary = competition._state.registry[str(variant.id)]
		var group_id: String = str(entry.profile.group_id) if competition.attached(entry.profile,"group") else ""
		var state: Dictionary = group_state.get(group_id,{"trust":0.72,"fatigue":0.0})
		factors[str(variant.id)] = EffectRules.attraction_factor(modifiers, hour, group_id, competition.active_topics(entry.profile)) * maxf(0.05,float(state.trust)) * maxf(0.05,1.0-float(state.fatigue))
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
	var parent_id: String = str(variant.parent_ids[0]) if not variant.parent_ids.is_empty() else ""
	var profile_data: Dictionary = competition.inherited_profile(variant,parent_id)
	variant.flow_profile = profile_data.duplicate(true)
	var origin: String = str(competition._state.registry.get(parent_id,{}).get("origin_country",""))
	competition.register(variant,profile_data,origin,hour)

func _reward_milestones() -> void:
	var totals := totals_state()
	var milestone_size: int = maxi(1,floori(competition.snapshot(variants,false).world_population * catalog.gameplay_rules.milestone_population_fraction))
	var milestone := floori(float(totals.owned_adopted) / milestone_size)
	for index in range(1, milestone + 1):
		economy.reward("adoption_%d" % index, catalog.milestone_reward, DeskLocalization.source_format("作者归属采用里程碑 %d", (index * milestone_size)), hour)

func totals_state() -> Dictionary:
	var view: Dictionary = competition.snapshot(variants,false)
	var fatigue := 0.0
	for state: Dictionary in group_state.values(): fatigue += float(state.fatigue)
	return {"exposed":view.exposed,"adopted":view.adopted,"owned_adopted":view.owned_adopted,"lineage_adopted":view.lineage_adopted,"fatigue":fatigue/maxf(1.0,group_state.size())}

func _event_condition_values() -> Dictionary:
	var totals := totals_state()
	var sample_population := 0
	for group: MemeDemoGroup in catalog.groups: sample_population += group.sample_size
	var world_population: int = competition.snapshot(variants, false).world_population
	return {"hour":float(hour) / catalog.gameplay_rules.event_time_scale,
		"exposed":float(totals.exposed) / maxf(1.0, world_population) * sample_population,
		"adopted":float(totals.adopted) / maxf(1.0, world_population) * sample_population,
		"variants":variants.size(), "families":families.size(), "fatigue":totals.fatigue}

## 每次执行事件后重新计算候选条件；空候选池保留未使用的到达次数。
func _schedule_events() -> void:
	var arrivals := EventScheduler.arrival_count(catalog.event_clock, seed_value, hour, _event_clock_arrivals)
	while events.size() < arrivals:
		var definition := EventScheduler.choose_event(catalog.events, hour, catalog.gameplay_rules.event_time_scale,
			event_counts, last_event_hours, _event_condition_values(), _rng)
		if definition == null: return
		_execute_event(definition)

## 统一创建事件身份、应用效果并登记来源，界面只接收记录副本。
func _execute_event(definition: MemeDemoEvent) -> void:
	var id := str(definition.id)
	var event_id := _new_id("event")
	var first_variant: int = variants.size()
	var observed := PackedStringArray()
	for effect in definition.effects:
		observed.append(_apply_effect(effect, event_id, definition))
	if id == "competitor_birth":
		var preset_event: MemeDemoEvent = definition.duplicate(true)
		preset_event.external_preset_id = StringName(catalog.gameplay_rules.event_presets[id])
		observed.append(_spawn_external_preset(event_id,preset_event))
	elif not definition.external_preset_id.is_empty() and definition.origin == &"environment_meme" and &"emerge" in definition.operation_ids:
		observed.append(_spawn_external_preset(event_id, definition))
	if definition.origin == &"environment_meme" and variants.size() == first_variant:
		var independent: MemeDemoEvent = definition.duplicate(true)
		independent.external_preset_id = StringName(catalog.gameplay_rules.event_presets[id])
		observed.append(_spawn_external_preset(event_id,independent))
	for index in range(first_variant,variants.size()): _register_external_world(variants[index])
	event_counts[id] = int(event_counts.get(id, 0)) + 1
	last_event_hours[id] = hour
	var record := {"instance_id":event_id, "definition_id":id, "title":definition.title, "narrative":definition.narrative, "impact_text":definition.impact_summary(latest_draft.get("reuse_permission", "unknown") != "restricted"), "mentor_comment":definition.mentor_comment, "effect_text":DeskLocalization.source_join("\n",observed), "origin":str(definition.origin), "hour":hour, "discoveries":Array(definition.discovery_ids), "acknowledged":false, "design_rewards":definition.design_rewards.duplicate(true), "design_source_preset_id":str(definition.external_preset_id), "reward_text":("收录后领取：" + definition.design_reward_summary()) if not definition.design_rewards.is_empty() else ""}
	record.competition_variant_ids = []
	for index in range(first_variant,variants.size()): record.competition_variant_ids.append(str(variants[index].id))
	events.append(record)
	pending_events.append(record)

func _event_hours(value: float) -> float:
	return value * catalog.gameplay_rules.event_time_scale

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
			return DeskLocalization.source_format("%s：吸引系数 ×%.2f，持续 %.0f 游戏小时；总注意力预算不增加。", [scope, maxf(0.05, 1.0 + amount), maxf(1.0, _event_hours(effect.duration_hours))], [0])
		"trust", "fatigue":
			var field := str(effect.effect_id)
			var changes := PackedStringArray()
			for id in ids:
				var state: Dictionary = group_state[id]
				var before: float = state[field]
				state[field] = clampf(before + amount, 0.0, 1.0)
				group_state[id] = state
				changes.append("%s %.2f→%.2f" % [id, before, state[field]])
			return DeskLocalization.source_format("%s：%s",[("信任" if field == "trust" else "疲劳"),DeskLocalization.source_join("；",changes)],[0,1])
		"adoption":
			var added: int = competition.adoption_pulse(current_variant_id,amount)
			_reward_milestones()
			return DeskLocalization.source_format("已曝光而未采用者新增采用 %d。", added)
		"semantic_shift":
			draft_distance = clampf(amount, 0.0, 1.0)
			return DeskLocalization.source_format("外部改写相对固定家族锚点的语义偏移设为 %.2f；下一次改写按分家规则处理。", draft_distance)
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
			return DeskLocalization.source_format("%s：疲劳降低 %.2f，旧表达重新进入使用；不恢复对外部分家的控制。", [scope, maxf(0.0, amount)], [0])
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
	var remix_text := EffectRules.remix_text(definition_id, parent.text)
	var reuse_factor := EffectRules.reuse_factor(str(latest_draft.reuse_permission),
		PackedStringArray(latest_draft.replaceable_slots).size(), find_kernel(parent.kernel_id).required_slots.size(),
		float(latest_draft.remix_cost), float(latest_draft.context_dependency))
	variants.append({"id":id, "family_id":family_id, "parent_ids":[parent.id], "origin_ids":parent.origin_ids.duplicate(), "creator":creator, "owned":not split, "controlled":false, "text":remix_text, "kernel_id":parent.kernel_id, "preset_id":str(parent.get("preset_id", "")), "source_presets":parent.get("source_presets", []).duplicate(true), "semantic_distance":draft_distance, "language_id":"mixed", "source_event":event_id, "topic_ids":parent.get("topic_ids", []).duplicate(), "reuse_factor":reuse_factor})
	return DeskLocalization.source_format("%s %s；版本 %s 由 %s 制作，玩家不可编辑；来源保留。", ["新家族" if split else "原家族变体", family_id, id, creator], [0])

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
	return DeskLocalization.source_format("%s 正被其他人接续传播；发声者没有署名，你还无法接管它。", preset.title, [0])

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
		status = DeskLocalization.source_join("；",design_errors)
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
			if definition != null and not event.get("design_rewards",[]).is_empty(): event.reward_text = "已领取：" + _reward_summary(event.design_rewards)
	active_event = {}
	phase = "running"
	speed = resume_speed
	_open_next_event()
	if phase == "running" and (hour >= run_end_hour or not competition._state.victory.is_empty()):
		_finish()
	changed.emit()

func _finish() -> void:
	phase = "complete"
	speed = 0
	status = "本轮结束：保留作者归属成果，也看见已经脱离控制的来源影响。"
	if not competition._state.victory.is_empty(): status = "胜利：" + str(competition._state.victory.id)
	completed.emit(snapshot())

func snapshot() -> Dictionary:
	var state := totals_state()
	state.merge({"hour":hour, "run_end_hour":run_end_hour, "phase":phase, "speed":speed, "resume_speed":resume_speed, "country_id":country_id, "country_title":country_title, "status":status, "families":families.size(), "variants":variants.size(), "events":events.duplicate(true), "lineage":variants.duplicate(true), "discoveries":discoveries.duplicate(), "meme_points":economy.balance, "point_cost":catalog.first_publish_cost if publish_count == 0 else catalog.revision_publish_cost, "economy_log":economy.lines(), "attention_budget":attention.budget, "attention_player":attention.player, "attention_external":attention.external, "attention_background":attention.background, "purchase_system":"not_designed"})
	state.gameplay = {"mode":gameplay_mode(),"day":float(hour)/24.0,"horizon_hours":run_end_hour,"active_seconds":competition._state.active_seconds,"hours_per_active_second":catalog.gameplay_rules.hours_per_active_second}
	state.world_competition = competition.snapshot(variants)
	state.design_state = design_state.snapshot(variants)
	state.design_state.event_materials = event_materials(state.design_state)
	state.event_materials = state.design_state.event_materials.duplicate(true)
	return state

func _vector_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func payload() -> Dictionary:
	return SaveCodec.new(self).payload()

func validate_payload(data: Dictionary) -> PackedStringArray:
	return SaveCodec.new(self).validate_payload(data)

func _event_definition(id: String) -> MemeDemoEvent:
	for definition in catalog.events:
		if str(definition.id) == id: return definition
	return null

func _reward_summary(rewards: Array) -> String:
	var parts := PackedStringArray()
	for reward: Dictionary in rewards:
		parts.append("%s ×%d" % [str(design_state.rules.reward_resource(str(reward.kind),str(reward.id)).get("title",reward.id)),int(reward.count)])
	return "、".join(parts)

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## 解析与候选账本构造由存档边界完成，失败不改变当前局。
func restore(data: Dictionary) -> PackedStringArray:
	return SaveCodec.new(self).restore(data)
