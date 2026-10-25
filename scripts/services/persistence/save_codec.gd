extends RefCounted
## 当前存档格式的唯一边界：先解析和验证，再一次性安装完整候选状态。

const CompetitionState = preload("res://scripts/gameplay/competition/competition_state.gd")
const DesignState = preload("res://scripts/gameplay/design/design_state.gd")
const SAVE_VERSION := 3

var simulation: RefCounted
var catalog: MemeDemoCatalog
var competition: RefCounted
var design_state: MemeDemoDesignState
var economy: MemeDemoEconomy

func _init(owner_simulation: RefCounted) -> void:
	simulation = owner_simulation
	catalog = simulation.catalog
	competition = simulation.competition
	design_state = simulation.design_state
	economy = simulation.economy

func payload() -> Dictionary:
	var draft: Dictionary = simulation.latest_draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		if draft.has(key): draft[key] = [draft[key].x, draft[key].y]
	if draft.has("replaceable_slots"): draft.replaceable_slots = Array(draft.replaceable_slots)
	if draft.has("topic_ids"): draft.topic_ids = Array(draft.topic_ids)
	var data := {"save_version":SAVE_VERSION, "content_version":catalog.content_version, "content_signature":content_signature(), "seed":simulation.seed_value, "rng_state":str(simulation._rng.state), "hour":simulation.hour, "run_end_hour":simulation.run_end_hour, "phase":simulation.phase, "speed":simulation.speed, "resume_speed":simulation.resume_speed, "country_id":simulation.country_id, "country_title":simulation.country_title, "status":simulation.status, "latest_draft":draft, "families":simulation.families.duplicate(true), "variants":simulation.variants.duplicate(true), "deployments":simulation.deployments.duplicate(true), "group_state":simulation.group_state.duplicate(true), "events":simulation.events.duplicate(true), "discoveries":simulation.discoveries.duplicate(), "modifiers":simulation.modifiers.duplicate(true), "event_counts":simulation.event_counts.duplicate(), "last_event_hours":simulation.last_event_hours.duplicate(), "pending_events":simulation.pending_events.duplicate(true), "active_event":simulation.active_event.duplicate(true), "attention":simulation.attention.duplicate(), "current_variant_id":simulation.current_variant_id, "draft_distance":simulation.draft_distance, "publish_count":simulation.publish_count, "serial":simulation._serial, "economy":economy.payload()}
	data.design_state = design_state.payload()
	data.gameplay_mode = "world_competition"
	data.competition_state = competition.payload()
	var precision: Dictionary = {}
	_collect_precision(data, "", precision)
	data.numeric_precision = precision
	return data

func validate_payload(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	_decode(data, errors)
	return errors

func _decode(data: Dictionary, errors: PackedStringArray) -> Dictionary:
	var decoded := _decode_precision(data, errors)
	if not errors.is_empty(): return {}
	errors.append_array(_validate_current(decoded))
	if not errors.is_empty(): return {}
	return decoded

## 空草稿合法；出现草稿时，首发前后都遵守相同字段和有限值约束。
func _draft_from_json(draft: Dictionary, errors: PackedStringArray) -> Dictionary:
	if draft.is_empty(): return {}
	var decoded := draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		var point: Variant = draft.get(key)
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]):
			errors.append("存档草稿坐标必须是两个有限数值：" + key)
		else: decoded[key] = Vector2(point[0], point[1])
	if not draft.get("slots") is Dictionary or not draft.get("topic_ids") is Array or not draft.get("replaceable_slots") is Array or not draft.get("political_known") is bool:
		errors.append("存档草稿字段类型错误。")
	for key in ["kernel_id", "preset_id", "channel_id", "group_id", "language_id", "target", "reuse_permission"]:
		if not (draft.get(key) is String or draft.get(key) is StringName): errors.append("存档草稿文本类型错误：" + key)
		else: decoded[key] = str(draft[key])
	for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
		if not _number(draft.get(key)): errors.append("存档草稿数值类型错误：" + key)
	for key in ["topic_ids", "replaceable_slots"]:
		if not draft.get(key) is Array: continue
		for value: Variant in draft[key]:
			if not value is String: errors.append("存档草稿列表只能包含文本：" + key)
	if draft.get("slots") is Dictionary:
		for key: Variant in draft.slots:
			if not key is String or not draft.slots[key] is String: errors.append("存档语义槽位必须使用文本键和值。")
	if not errors.is_empty(): return {}
	decoded.topic_ids = PackedStringArray(draft.topic_ids)
	decoded.replaceable_slots = PackedStringArray(draft.replaceable_slots)
	return decoded

func _validate_current(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("save_version") != SAVE_VERSION or not _integer(data.get("content_version")) or int(data.content_version) != catalog.content_version or data.get("content_signature") != content_signature() or data.get("gameplay_mode") != "world_competition":
		return PackedStringArray(["存档版本、内容或玩法格式不匹配；只接受当前格式。"])
	var numeric := ["seed", "hour", "run_end_hour", "speed", "resume_speed", "draft_distance", "publish_count", "serial"]
	var strings := ["rng_state", "phase", "country_id", "country_title", "status", "current_variant_id"]
	var dictionaries := ["latest_draft", "families", "group_state", "event_counts", "last_event_hours", "active_event", "attention", "economy", "design_state", "competition_state"]
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
	for key in ["seed", "hour", "run_end_hour", "speed", "resume_speed", "publish_count", "serial"]:
		if not _integer(data[key]): errors.append("存档整数非法：" + key)
	if not str(data.rng_state).is_valid_int() or data.phase not in ["draft", "running", "event", "complete"] or data.hour < 0 or data.hour > data.run_end_hour or data.run_end_hour < catalog.run_hours or data.speed < 0 or data.speed > 2 or data.resume_speed < 0 or data.resume_speed > 2 or data.publish_count < 0 or data.serial < 0 or data.draft_distance < 0 or data.draft_distance > 1:
		errors.append("存档阶段、随机状态、计数或时间非法。")
	if not errors.is_empty(): return errors
	errors.append_array(competition.validate_payload(data.competition_state, data.variants, int(data.hour)))
	if data.phase in ["event", "draft", "complete"] and data.speed != 0:
		errors.append("非运行阶段必须暂停。")
	errors.append_array(economy.validate_payload(data.economy))
	for key in ["variants", "deployments", "events", "modifiers", "pending_events"]:
		for entry in data[key]:
			if not entry is Dictionary: errors.append("存档记录类型错误：" + key)
	for item in data.discoveries:
		if not item is String: errors.append("存档发现类型错误。")
	if not errors.is_empty(): return errors
	for key in ["events", "pending_events"]:
		for event in data[key]:
			_validate_event_copy(event, errors)
	if not data.active_event.is_empty(): _validate_event_copy(data.active_event, errors)
	if errors.is_empty(): _validate_event_history(data, errors)
	for deployment in data.deployments:
		if not deployment.has_all(["id", "variant_id", "country_id", "group_id", "channel_id", "hour"]): errors.append("存档投放记录字段错误。")
	if not errors.is_empty(): return errors
	var variant_ids: Dictionary = {}
	var variant_order := {}
	# 先确认来源字段类型，再比较谱系关系。
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
	if not errors.is_empty(): return errors
	errors.append_array(design_state.validate_payload(data.design_state, data.events, data.variants, data.economy))
	if not errors.is_empty(): return errors
	for variant in data.variants:
		for parent in variant.get("parent_ids", []):
			if not variant_ids.has(parent):
				errors.append("存档来源版本丢失。")
			elif int(variant_order[parent]) >= int(variant_order[variant.id]):
				errors.append("竞争版本只能引用先前存在的父版本。")
			elif variant.get("source_presets", []) != variant_ids[parent].get("source_presets", []) or str(variant.get("preset_id", "")) != str(variant_ids[parent].get("preset_id", "")):
				errors.append("存档派生版本未保留原案例来源。")
		for origin in variant.get("origin_ids", []):
			if not variant_ids.has(origin): errors.append("存档原始版本来源丢失。")
			elif (not variant_ids[origin].parent_ids.is_empty() or str(variant_ids[origin].creator) != "player"): errors.append("竞争谱系原始来源必须是作者的真实初始版本。")
	if errors.is_empty():
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
				var flow_errors := PackedStringArray()
				var flow_input := _draft_from_json(flow_draft, flow_errors)
				if not flow_errors.is_empty():
					errors.append_array(flow_errors)
					continue
				errors.append_array(simulation.validate_draft(flow_input))
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
	var restored_draft := _draft_from_json(data.latest_draft, errors)
	if data.publish_count > 0 and restored_draft.is_empty(): errors.append("已发布存档缺少当前草稿。")
	if not restored_draft.is_empty() and errors.is_empty(): errors.append_array(simulation.validate_draft(restored_draft))
	if variant_ids.has(data.current_variant_id) and restored_draft.get("preset_id", "") != variant_ids[data.current_variant_id].get("preset_id", ""):
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
	for modifier: Dictionary in data.modifiers:
		if not modifier.get("source") is String or not _number(modifier.get("amount")) or not _number(modifier.get("expires")) or not _integer(modifier.get("starts")) or not _number(modifier.get("decay_parameter")) or modifier.get("decay") not in ["constant", "linear", "exponential", "periodic"] or not modifier.get("groups") is Array or not modifier.get("topics") is Array:
			errors.append("存档作用记录字段或类型错误。")
			continue
		for key in ["groups", "topics"]:
			for identity: Variant in modifier[key]:
				if not identity is String: errors.append("存档作用对象必须是文本身份。")
	for value in data.event_counts.values():
		if not _number(value) or value < 0: errors.append("存档事件计数错误。")
	for value in data.last_event_hours.values():
		if not _number(value): errors.append("存档事件时间错误。")
	if errors.is_empty() and not design_state.author_marks_valid(data.latest_draft, data.design_state): errors.append("当前草稿表达补丁或能力来源与记录不符。")
	if errors.is_empty(): data.latest_draft = restored_draft
	return errors

func _validate_preset_sources(entry: Dictionary, label: String, errors: PackedStringArray) -> void:
	if not entry.get("preset_id", "") is String or not entry.get("source_presets") is Array:
		errors.append(DeskLocalization.source_format("存档%s预设来源字段类型错误。", label))
		return
	var preset_id: String = entry.get("preset_id", "")
	var sources: Array = entry.source_presets
	if preset_id.is_empty():
		if not sources.is_empty(): errors.append(DeskLocalization.source_format("存档%s无预设却声明案例来源。", label))
		return
	var preset := catalog.find_preset(preset_id)
	if preset == null:
		errors.append(DeskLocalization.source_format("存档%s引用未知预设。", label))
	elif sources.size() != 1 or not sources[0] is Dictionary or sources[0] != preset.source_record():
		errors.append(DeskLocalization.source_format("存档%s案例来源与内容目录不匹配。", label))

func _validate_event_copy(event: Dictionary, errors: PackedStringArray) -> void:
	for key in ["instance_id", "definition_id", "title", "narrative", "effect_text", "origin", "impact_text", "mentor_comment", "design_source_preset_id", "reward_text"]:
		if not event.get(key) is String: errors.append("存档事件文本类型错误：" + key)
	if not _integer(event.get("hour")) or not event.get("discoveries") is Array or not event.get("acknowledged") is bool or not event.get("design_rewards") is Array or not event.get("competition_variant_ids") is Array:
		errors.append("存档事件记录字段错误。")
	if not errors.is_empty(): return
	for key in ["discoveries", "competition_variant_ids"]:
		for identity: Variant in event[key]:
			if not identity is String: errors.append("存档事件引用必须使用文本身份。")
	var definition: MemeDemoEvent = null
	for candidate: MemeDemoEvent in catalog.events:
		if str(candidate.id) == event.definition_id: definition = candidate
	if definition == null:
		errors.append("事件定义不在当前内容目录中。")
		return
	var actual := JSON.stringify(JSON.parse_string(JSON.stringify(event.design_rewards)), "", true, true)
	var expected := JSON.stringify(JSON.parse_string(JSON.stringify(definition.design_rewards)), "", true, true)
	if actual != expected or event.design_source_preset_id != str(definition.external_preset_id): errors.append("事件物资或预设来源与开发定义不符。")
	var expected_text: String = (("已领取：" if event.acknowledged else "收录后领取：") + simulation._reward_summary(definition.design_rewards)) if not definition.design_rewards.is_empty() else ""
	if event.reward_text != expected_text: errors.append("事件物资文案与真实领取状态不符。")
	for field in ["impact_text", "mentor_comment"]:
		if str(event[field]).strip_edges().is_empty(): errors.append("存档事件文本为空：" + field)
	if "\n" in event.mentor_comment or "\r" in event.mentor_comment: errors.append("存档67评价不是单行。")

## 调度计数必须来自真实事件历史，内部据此直接读取最后触发时间。
func _validate_event_history(data: Dictionary, errors: PackedStringArray) -> void:
	var instance_ids := {}
	var observed_counts := {}
	var observed_hours := {}
	for event: Dictionary in data.events:
		if event.instance_id.is_empty() or instance_ids.has(event.instance_id): errors.append("存档事件实例身份为空或重复。")
		if event.hour < 0 or event.hour > data.hour: errors.append("存档事件时间超出当前局。")
		instance_ids[event.instance_id] = true
		observed_counts[event.definition_id] = int(observed_counts.get(event.definition_id, 0)) + 1
		observed_hours[event.definition_id] = int(event.hour)
	if competition._canonical(data.event_counts) != observed_counts or competition._canonical(data.last_event_hours) != observed_hours:
		errors.append("存档事件调度计数或时间与历史记录不一致。")

func restore(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var decoded := _decode(data, errors)
	if not errors.is_empty(): return errors
	var restored_competition: RefCounted = CompetitionState.new(catalog)
	errors = restored_competition.restore(decoded.competition_state, decoded.variants, int(decoded.hour))
	if not errors.is_empty(): return errors
	var restored_design: MemeDemoDesignState = DesignState.new(catalog)
	errors = restored_design.restore(decoded.design_state, decoded.events, decoded.variants, decoded.economy)
	if not errors.is_empty(): return errors
	var restored_economy := MemeDemoEconomy.new()
	restored_economy.restore(decoded.economy)
	# 所有解析、转换和账本校验结束后，才替换当前局。
	simulation.competition = restored_competition
	simulation.design_state = restored_design
	simulation.economy = restored_economy
	simulation.seed_value = int(decoded.seed)
	simulation._rng.seed = simulation.seed_value
	simulation._rng.state = int(decoded.rng_state)
	simulation._event_clock_arrivals.clear()
	simulation.hour = int(decoded.hour)
	simulation.run_end_hour = int(decoded.run_end_hour)
	simulation.speed = int(decoded.speed)
	simulation.resume_speed = int(decoded.resume_speed)
	simulation.publish_count = int(decoded.publish_count)
	simulation.phase = decoded.phase
	simulation.country_id = decoded.country_id
	simulation.country_title = decoded.country_title
	simulation.status = decoded.status
	simulation.current_variant_id = decoded.current_variant_id
	simulation.latest_draft = decoded.latest_draft
	simulation.families = decoded.families.duplicate(true)
	simulation.group_state = decoded.group_state.duplicate(true)
	simulation.event_counts = decoded.event_counts.duplicate(true)
	simulation.last_event_hours = decoded.last_event_hours.duplicate(true)
	simulation.active_event = decoded.active_event.duplicate(true)
	simulation.attention = decoded.attention.duplicate(true)
	simulation.variants.assign(decoded.variants)
	simulation.deployments.assign(decoded.deployments)
	simulation.events.assign(decoded.events)
	simulation.discoveries.assign(decoded.discoveries)
	simulation.modifiers.assign(decoded.modifiers)
	simulation.pending_events.assign(decoded.pending_events)
	simulation.draft_distance = float(decoded.draft_distance)
	simulation._serial = int(decoded.serial)
	DeskLocalization.prime_system_history(catalog, decoded)
	simulation.changed.emit()
	return errors

func content_signature() -> String:
	return JSON.stringify(_resource_data(catalog), "", true, true).sha256_text()

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

func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))
